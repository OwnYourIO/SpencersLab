"""immich-hugo-sync — sync allowlisted Immich albums INTO existing Hugo page
bundles (chunks/C01.md contract §1-§11, DECISIONS R11/R12/R13).

Owner-pinned postures:
- N3 (§1): `page:` is REQUIRED on every allowlist entry; schema-invalid
  entries, unresolved album names and missing target pages fail loud BEFORE
  any network call or write — there is no content/photos/ fallback and sync
  never creates pages.
- N2 (§5): where a page's authored gallery calls would not include the
  synced files, sync manages its own machine-marked gallery block on that
  page and prefixes those files `sync-<albumslug>-`; authored calls are
  never rewritten. Auto-inclusion transitions remove the block and rename
  the files through ledger ops.
- N1 (§8): the only front-matter edit is an append-only machine marker key.
- §7: removals come ONLY from the state-recorded ledger minus the current
  asset set; lost state means additive-only, never pattern inference.
"""

import argparse
import fnmatch
import json
import os
import sys
from datetime import date
from pathlib import Path
from types import SimpleNamespace

from . import allowlist, http_client, hugo_page, naming

STATE_FILENAME = "curatedforest-sync.json"
_MODE_MACHINE = naming.MODE_MACHINE

_SEARCH_PAGE_LIMIT = 1000

SUMMARY_LINE = "SYNC_RESULT albums={albums} added={added} removed={removed} blocks={blocks} changed={changed}"


class SyncError(Exception):
    """Any loud contract failure: reported on stderr, non-zero exit, no
    state advance and no traceback (t12: 4xx-class errors must report
    cleanly)."""


def resolve_bundle(content_root, page):
    """§3 + HARD GUARDS: the target bundle MUST exist under content/ with an
    index page. Path normalization is the guard against `../` escapes (t10
    g3); nothing here creates a page (t6)."""
    root = content_root.resolve()
    resolved = (root / page).resolve()
    if resolved != root and not resolved.is_relative_to(root):
        raise SyncError(f"target page {page!r} resolves outside {root} — refusing")
    if not resolved.is_dir():
        raise SyncError(f"target page content/{page} does not exist (sync never creates pages)")
    page_file = hugo_page.page_file_in_bundle(resolved)
    if page_file is None:
        raise SyncError(f"target page content/{page} has no _index.md/index.md — a directory is not a page")
    return resolved, page_file


def integration_mode(text, entry, assets):
    """§5 outcomes in contract order: an authored no-match call takes
    everything; otherwise the prospective (allowlist-prefixed, never
    sync-prefixed) names must all satisfy an existing glob; anything else —
    including an unparseable call — lands on the machine block."""
    all_inclusive, globs, unparseable = hugo_page.authored_gallery_globs(text.splitlines())
    if unparseable or all_inclusive:
        return _MODE_MACHINE if unparseable else naming.MODE_AUTO
    if not globs:
        return _MODE_MACHINE
    candidates = [f"{entry['prefix']}{naming.base_name(asset)}" for asset in assets]
    if all(any(fnmatch.fnmatch(name, glob) for glob in globs) for name in candidates):
        return naming.MODE_AUTO
    return _MODE_MACHINE


class ImmichClient:
    """v3 endpoint surface per RESEARCH.md R2.3 and the fixture fakes:
    GET /albums?isOwned=true (body pagination) and POST /search/metadata
    (assets.nextPage is a string only while more pages exist)."""

    def __init__(self, base_url, api_key, transport=None):
        self.base = base_url.rstrip("/") + "/api"
        self.headers = {"x-api-key": api_key}
        self.transport = transport

    def owned_albums(self):
        albums = []
        page = 1
        while True:
            resp = http_client.json_request(
                "GET", f"{self.base}/albums?isOwned=true&page={page}",
                headers=self.headers, transport=self.transport)
            items = resp.get("albums", resp) if isinstance(resp, dict) else resp
            albums.extend(items)
            nxt = resp.get("nextPage") if isinstance(resp, dict) else None
            if not nxt:
                return albums
            page = int(nxt)

    def album_images(self, album_id):
        seen = set()
        assets = []
        page = 1
        while page <= _SEARCH_PAGE_LIMIT:
            resp = http_client.json_request(
                "POST", f"{self.base}/search/metadata", headers=self.headers,
                body={"albumIds": [album_id], "type": "IMAGE", "page": page},
                transport=self.transport)
            envelope = resp.get("assets") or {}
            for item in envelope.get("items") or []:
                if item["id"] not in seen:
                    seen.add(item["id"])
                    assets.append(item)
            nxt = envelope.get("nextPage")
            # Real v3 SearchAssetResponseDto serializes only nextPage
            # (null when done); hasNextPage is a fixture-only field and
            # gating on it would silently truncate big albums after page 1.
            if not nxt:
                return assets
            page = int(nxt)
        raise SyncError(f"album {album_id}: search pagination exceeded {_SEARCH_PAGE_LIMIT} pages")

    def download_derivative(self, asset_id, dest_path):
        # size=preview only — GET /assets/{id}/original is deprecated and
        # size=original never (C01 "Notes for dev", RESEARCH.md R2.3).
        url = f"{self.base}/assets/{asset_id}/thumbnail?size=preview"
        try:
            http_client.download(url, dest_path, headers=self.headers, transport=self.transport)
        except http_client.HttpError as exc:
            raise SyncError(f"derivative download failed for asset {asset_id}: {exc}") from None


def load_state(state_dir):
    path = Path(state_dir) / STATE_FILENAME
    try:
        raw = json.loads(path.read_text())
        state = raw if isinstance(raw, dict) else {}
    except FileNotFoundError:
        state = {}
    except json.JSONDecodeError:
        # §10: corrupt state degrades to a full re-probe with no deletions —
        # an unparseable ledger must never drive file removals.
        state = {}
    albums = state.get("albums")
    state["albums"] = albums if isinstance(albums, dict) else {}
    return state


def write_state(state_dir, state):
    directory = Path(state_dir)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / STATE_FILENAME
    tmp = directory / (STATE_FILENAME + ".tmp")
    tmp.write_text(json.dumps({"version": 1, "albums": state["albums"]}, indent=2) + "\n")
    os.replace(tmp, path)  # §10: readers never observe a half-written file


def _drop_block_from_page(content_root, page, slug):
    """Retarget move: sync removes its own block from the page it managed
    before (machine content is managed by the machine; nothing else on that
    page is touched). page was validated under content/ when it was set."""
    page_file = hugo_page.page_file_in_bundle(content_root / Path(page))
    if page_file is None or not page_file.is_file():
        return False
    text = page_file.read_text()
    updated = hugo_page.apply_machine_block(text, None, slug, want_machine=False)
    if updated != text:
        page_file.write_text(updated)
        return True
    return False


def _apply_file_ledger(client, bundle_dir, ledger, assets, name_for, stats):
    """Ledger ops for one album: deletions (§7), mode-transition renames
    (§5) and downloads of missing derivatives (§6). Mutates `ledger`."""
    live_ids = {asset["id"] for asset in assets}
    for asset_id, file_name in list(ledger.items()):
        name = Path(file_name).name
        if name != file_name:
            ledger.pop(asset_id)
            continue
        if asset_id not in live_ids:
            stale = bundle_dir / name
            if stale.is_file():
                stale.unlink()
                stats.removed += 1
                stats.changed = True
            ledger.pop(asset_id)

    for asset in assets:
        name = name_for(asset)
        target = bundle_dir / name
        current = ledger.get(asset["id"])
        if current and current != name:
            previous = bundle_dir / Path(current).name
            if previous.is_file() and not target.exists():
                # A rename on an integration-mode transition: a move, never
                # a re-download (§5 lifecycle, t8 owner-widen case).
                os.rename(previous, target)
                stats.changed = True
        ledger[asset["id"]] = name
        if not target.exists():
            client.download_derivative(asset["id"], target)  # §6: missing files only
            stats.added += 1
            stats.changed = True


def sync_album(ctx, state_albums, entry, album_dto, stats):
    album_id = album_dto["id"]
    live_ts = album_dto.get("lastModifiedAssetTimestamp")
    record = state_albums.get(album_id)

    if record and not ctx.force and record.get("last_modified") == live_ts:
        return record.get("mode")  # §2 skip: disk and state untouched

    bundle_dir, page_file = resolve_bundle(ctx.content_root, entry["page"])
    assets = ctx.client.album_images(album_id)
    if not assets and record is None:
        # HARD GUARD: an album with zero IMAGE assets is skipped entirely —
        # not an error, nothing written for it (t10 g6).
        return None

    slug = (record or {}).get("slug") or naming.album_slug(entry["name"])
    if record and record.get("page") and record["page"] != entry["page"]:
        if _drop_block_from_page(ctx.content_root, record["page"], slug):
            stats.changed = True

    text = page_file.read_text()
    mode = integration_mode(text, entry, assets)
    ledger = dict((record or {}).get("ledger") or {})
    _apply_file_ledger(ctx.client, bundle_dir, ledger, assets,
                       lambda asset: naming.derivative_name(asset, mode, slug, entry["prefix"]), stats)

    updated = hugo_page.apply_machine_block(text, entry["name"], slug, want_machine=(mode == _MODE_MACHINE))
    updated = hugo_page.apply_fm_marker(updated, entry["name"], ctx.today)
    if updated != text:
        page_file.write_text(updated)
        stats.changed = True

    state_albums[album_id] = {
        "name": entry["name"],
        "slug": slug,
        "page": entry["page"],
        "prefix": entry["prefix"],
        "mode": mode,
        "last_modified": live_ts,
        "ledger": ledger,
    }
    return mode


def run(cfg, transport=None):
    entries = allowlist.validate(allowlist.parse(Path(cfg["albums_file"]).read_text()))
    selected = allowlist.select(entries, cfg["albums"])

    stats = SimpleNamespace(added=0, removed=0, changed=False)
    state = load_state(cfg["state_dir"])
    blocks = 0

    if selected:
        # An empty selection never touches the network (t2); the client is
        # constructed lazily so "validate FIRST" holds on the wire too.
        client = ImmichClient(cfg["immich_url"], cfg["api_key"], transport=transport)
        ctx = SimpleNamespace(client=client,
                              content_root=Path(cfg["site_dir"]) / "content",
                              force=cfg["force"],
                              today=date.today().isoformat())
        by_name = {}
        for album in client.owned_albums():
            name = album.get("albumName")
            if name in by_name:
                raise SyncError(f"Immich has multiple albums named {name!r}; exact-name resolution cannot choose")
            by_name[name] = album
        for entry in selected:
            album = by_name.get(entry["name"])
            if album is None:
                raise SyncError(f"allowlist album {entry['name']!r} not found among owned Immich albums")
            if sync_album(ctx, state["albums"], entry, album, stats) == _MODE_MACHINE:
                blocks += 1

    write_state(cfg["state_dir"], state)
    print(SUMMARY_LINE.format(
        albums=len(selected), added=stats.added, removed=stats.removed,
        blocks=blocks, changed="yes" if stats.changed else "no",
    ))
    if cfg["output_flag"]:
        Path(cfg["output_flag"]).write_text("changed\n" if stats.changed else "unchanged\n")
    return 0


def build_arg_parser():
    parser = argparse.ArgumentParser(prog="immich-hugo-sync")
    for flag, env in (
        ("--immich-url", "IMMICH_URL"),
        ("--immich-api-key", "IMMICH_API_KEY"),
        ("--site-dir", "SITE_DIR"),
        ("--albums-file", "ALBUMS_FILE"),
        ("--albums", "ALBUMS"),
        ("--state-dir", "STATE_DIR"),
        ("--output-flag", "OUTPUT_FLAG"),
    ):
        parser.add_argument(flag, dest=env.lower(), default=None)
    parser.add_argument("--force", action="store_true", default=None)
    return parser


def read_config(argv=None):
    args = build_arg_parser().parse_args(argv)

    def pick(flag_value, env_name, default=None, required=False):
        if flag_value is not None:
            return flag_value
        from_environ = os.environ.get(env_name) or None
        if from_environ is None:
            if required:
                raise SyncError(f"missing required configuration: {env_name} (env or matching --flag)")
            return default
        return from_environ

    site = pick(args.site_dir, "SITE_DIR", required=True)
    force_raw = True if args.force else os.environ.get("FORCE")
    return {
        "immich_url": pick(args.immich_url, "IMMICH_URL", required=True),
        "api_key": pick(args.immich_api_key, "IMMICH_API_KEY", required=True),
        "site_dir": site,
        "albums_file": pick(args.albums_file, "ALBUMS_FILE", default=str(Path(site) / "sync-albums.yaml")),
        "albums": pick(args.albums, "ALBUMS", default=""),
        "force": bool(force_raw and str(force_raw).lower() in ("1", "true", "yes")),
        "state_dir": pick(args.state_dir, "STATE_DIR", default="/data/state"),
        "output_flag": pick(args.output_flag, "OUTPUT_FLAG"),
    }


def main():
    try:
        return run(read_config())
    except (SyncError, allowlist.AllowlistError, http_client.HttpError, OSError, ValueError) as exc:
        print(f"immich-hugo-sync: error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
