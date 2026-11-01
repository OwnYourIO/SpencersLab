"""Harness for the C01 sync/publish contract (chunks/C01.md of ticket
2026-10-cf-11-feat-immich-hugo-pipeline). Tests drive the two entry points
through their pinned env-config surface (contract "Entry points" + env
sections) and observe the scratch site — internals are never imported, so dev
owns module structure beyond sync/immich_sync.py and sync/forgejo_publish.py.

AC trace: t01[naming AC1] t02[allowlist N3/AC5] t03[probe] t04[pagination]
t05[additive writer AC3] t06[target resolution] t07[integration AC4]
t08[block lifecycle AC4] t09[front matter N1 AC3] t10[HARD GUARDS AC3]
t11[publish] t12[HTTP layer] t13[FIXTURE E2E AC1].
"""

import base64
import importlib
import os
import re
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).resolve().parent
CONTAINER_DIR = TESTS_DIR.parent
SEED_JPG = TESTS_DIR / "fixtures" / "derivative-seed.jpg"

# Wire values for the two fake servers (never real credentials — the fakes
# reject anything else). The fixture naming keeps the fake-vs-real seam
# greppable and non-secret-shaped.
FAKE_IMMICH_HEADER = "sentinel-immich-fixture"
FAKE_FORGEJO_HEADER = "sentinel-forgejo-fixture"

STATE_FILE = "curatedforest-sync.json"

# The two manual derivatives of the real current-grows bundle, names verbatim
# from RESEARCH-curatedforest-repo.md [10][12] — C01 HARD GUARDS protect them
# through the ledger rule ("no special-casing; test asserts"), so the names
# are fixture data, not tool logic.
MANUAL_DERIVATIVES = (
    "20250921-120050_18179443841_IMG_20250921_115827_912.jpg",
    "20251201-172814_14244004796_IMG_20251130_100709_792.jpg",
)

# Slug-rule interpretation pinned here (contract §5 "slugified album name"
# does not spell out the separator): lowercase, each run of non-alphanumerics
# becomes a single hyphen. Both C01 (machine block + file prefix) and C06
# (t5(b) byte-exact block fixture) must agree byte-for-byte, so the rule is
# frozen in the tests, not left to the implementation.
ALBUM_SLUG = {
    "Aeroponics Current": "aeroponics-current",
    "Past Designs Archive": "past-designs-archive",
    "Empty Album": "empty-album",
}

SUMMARY_RE = re.compile(
    r"SYNC_RESULT albums=(\d+) added=(\d+) removed=(\d+) blocks=(\d+) changed=(yes|no)"
)


def slug_of(album_name):
    return ALBUM_SLUG[album_name]


def expected_base_name(asset):
    """Reference implementation of contract §4 derivative naming.

    Interprets 'ASCII-folded' as NFKD transliteration to ASCII (é→e) BEFORE
    the [^A-Za-z0-9._-]→_ filter — the two-step order the §4 sentence
    describes. Fixture capture times are fixed at +00:00 so no field in the
    DTO fallback chain can shift the wall-clock reading the name must carry.
    """
    return f"{_capture_stamp(asset)}_{checksum8(asset['checksum'])}_{safe_original(asset['originalFileName'])}.jpg"


def expected_sync_name(asset, album_name):
    """Contract §5 machine-block naming: sync-<albumslug>- prefix."""
    return f"sync-{slug_of(album_name)}-{expected_base_name(asset)}"


def expected_prefixed_name(asset, prefix):
    """Allowlist prefix path (§5, zero-edit case): direct concatenation —
    the C06 example (prefix v7-web fitting glob v7-*) only holds under it."""
    return f"{prefix}{expected_base_name(asset)}"


def checksum8(checksum_b64):
    return base64.b64decode(checksum_b64).hex()[:8]


def _capture_stamp(asset):
    local = asset["localDateTime"][:19]
    return re.sub(r"[-:]", "", local[:10]) + "-" + local[11:19].replace(":", "")


def safe_original(original_name):
    stem = Path(original_name).stem
    folded = unicodedata.normalize("NFKD", stem).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^A-Za-z0-9._-]", "_", folded).lower()


def sync_result(summary_text):
    """Parsed 'SYNC_RESULT albums=… changed=…' line (contract §11); None if
    the line is absent so failures print the whole stdout."""
    m = SUMMARY_RE.search(summary_text)
    if not m:
        return None
    return {
        "albums": int(m.group(1)),
        "added": int(m.group(2)),
        "removed": int(m.group(3)),
        "blocks": int(m.group(4)),
        "changed": m.group(5),
    }


def tree_digest(root):
    """relpath -> sha256 for every file under root; the byte-identity device
    behind HARD GUARDS 'never modifies/moves/deletes existing files'."""
    import hashlib

    out = {}
    for p in sorted(root.rglob("*")):
        if p.is_file():
            out[str(p.relative_to(root))] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def machine_block(album_name):
    slug = slug_of(album_name)
    return [
        f'<!-- immich-sync:album="{album_name}" slug={slug} -->',
        f'{{{{< gallery match="sync-{slug}-*" sort="desc" >}}}}',
        f"<!-- immich-sync:end:{slug} -->",
    ]


def load_allowlist_text(entries):
    """YAML text per the C01 'Allowlist schema' section (name/page/prefix)."""
    lines = ["albums:"]
    for e in entries:
        lines.append(f'  - name: "{e["name"]}"')
        if "page" in e:
            lines.append(f'    page: {e["page"]}')
        if "prefix" in e:
            lines.append(f'    prefix: "{e["prefix"]}"')
    return "\n".join(lines) + "\n"


def make_asset(asset_id, original_name, checksum_raw, capture, album_ids):
    """Minimal v3 AssetResponseDto surface the contract reads (§4): id,
    checksum (base64 in the DTO), originalFileName, and BOTH time fields of
    the fallback chain carrying the same UTC wall clock so the test pins the
    capture time without pinning which field dev reads."""
    return {
        "id": asset_id,
        "checksum": base64.b64encode(checksum_raw).decode(),
        "originalFileName": original_name,
        "type": "IMAGE",
        "localDateTime": capture,
        "exifInfo": {"dateTimeOriginal": capture},
        "albumIds": list(album_ids),
    }


def album_dto(album_id, name, assets, last_modified="2026-03-01T10:00:00.000Z"):
    """AlbumResponseDto surface the contract probes (§1/§2) + the private
    _assets join the fake search reads (fake.albums_view strips it)."""
    return {
        "id": album_id,
        "albumName": name,
        "assetCount": len(assets),
        "lastModifiedAssetTimestamp": last_modified,
        "description": "",
        "_assets": list(assets),
    }


def git(site_dir, *args):
    return subprocess.run(
        ["git", "-C", str(site_dir), *args],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def init_git_repo(site, origin):
    """Seed SITE_DIR as a git repo with a bare origin — publish's surface
    (branch reset, push -f) needs a real remote; no network involved."""
    subprocess.run(
        ["git", "init", "-b", "main", str(site.root)], check=True, capture_output=True
    )
    git(site.root, "config", "user.name", "seed")
    git(site.root, "config", "user.email", "seed@sentinel.invalid")
    git(site.root, "add", "-A")
    git(site.root, "commit", "-qm", "seed site")
    subprocess.run(["git", "init", "--bare", str(origin)], check=True, capture_output=True)
    git(site.root, "remote", "add", "origin", str(origin))
    git(site.root, "push", "-q", "origin", "main")
    return origin


@pytest.fixture()
def git_identity_env():
    return {"GIT_IDENTITY_NAME": "immich-sync-bot", "GIT_IDENTITY_EMAIL": "sync@sentinel.invalid"}


@dataclass
class ProcResult:
    rc: int
    out: str
    err: str = ""

    @property
    def output(self):
        """Everything the entry point printed — error-naming assertions check
        both streams because the contract does not say which carries it."""
        return self.out + self.err


def _clear_env(monkeypatch):
    for k in list(os.environ):
        if k.startswith(
            (
                "IMMICH_",
                "SITE_DIR",
                "ALBUMS",
                "FORCE",
                "STATE_DIR",
                "OUTPUT_FLAG",
                "FORGEJO_",
                "PR_",
                "SUMMARY",
                "GIT_IDENTITY_",
                "BRANCH",
            )
        ):
            monkeypatch.delenv(k, raising=False)


def _invoke(monkeypatch, capsys, entry, env):
    """Call an entry point's main() with a clean env and a bare argv —
    pytest's own argv must never reach argparse (contract: CLI flags are an
    optional mirror; these tests drive the env surface only)."""
    _clear_env(monkeypatch)
    for k, v in env.items():
        monkeypatch.setenv(k, str(v))
    monkeypatch.setattr(sys, "argv", [entry])
    mod_name = {"immich-hugo-sync": "sync.immich_sync", "immich-hugo-publish": "sync.forgejo_publish"}[entry]
    if str(CONTAINER_DIR) not in sys.path:
        sys.path.insert(0, str(CONTAINER_DIR))
    try:
        mod = importlib.import_module(mod_name)
        mod = importlib.reload(mod)
    except ImportError as exc:
        pytest.fail(
            f"C01 implementation missing: {mod_name} not importable ({exc}). "
            "Intended green condition: sync/ modules per chunks/C01.md contract."
        )
    try:
        rc = mod.main()
    except SystemExit as exc:
        rc = exc.code
    captured = capsys.readouterr()
    return ProcResult(int(rc or 0), captured.out, captured.err)


@pytest.fixture()
def run_sync(monkeypatch, capsys):
    def _run(*, immich_url, site_dir, state_dir, albums_file=None, albums=None,
             force=None, output_flag=None, api_key=FAKE_IMMICH_HEADER, extra_env=None):
        env = {
            "IMMICH_URL": immich_url,
            "IMMICH_API_KEY": api_key,
            "SITE_DIR": site_dir,
            "STATE_DIR": state_dir,
        }
        if albums_file is not None:
            env["ALBUMS_FILE"] = albums_file
        if albums is not None:
            env["ALBUMS"] = albums
        if force is not None:
            env["FORCE"] = "true" if force else "false"
        if output_flag is not None:
            env["OUTPUT_FLAG"] = output_flag
        if extra_env:
            env.update(extra_env)
        return _invoke(monkeypatch, capsys, "immich-hugo-sync", env)

    return _run


@pytest.fixture()
def run_publish(monkeypatch, capsys, git_identity_env):
    def _run(*, site_dir, forgejo_url, repo, pat=FAKE_FORGEJO_HEADER, branch="immich-sync",
             pr_title=None, pr_body=None, summary=None, extra_env=None):
        env = {
            "SITE_DIR": site_dir,
            "BRANCH": branch,
            "FORGEJO_URL": forgejo_url,
            "FORGEJO_REPO": repo,
            "FORGEJO_PAT": pat,
            **git_identity_env,
        }
        if pr_title is not None:
            env["PR_TITLE"] = pr_title
        if pr_body is not None:
            env["PR_BODY"] = pr_body
        if summary is not None:
            env["SUMMARY"] = summary
        if extra_env:
            env.update(extra_env)
        return _invoke(monkeypatch, capsys, "immich-hugo-publish", env)

    return _run


@pytest.fixture()
def site(tmp_path):
    from fixture_site import Site

    return Site(tmp_path / "site")


@pytest.fixture()
def state_dir(tmp_path):
    d = tmp_path / "data" / "state"
    d.mkdir(parents=True)
    return d


@pytest.fixture()
def make_fake_immich():
    from fakes import FakeImmichServer

    servers = []

    def _make(albums, **kw):
        s = FakeImmichServer(albums, api_key=FAKE_IMMICH_HEADER, **kw)
        s.start()
        servers.append(s)
        return s

    yield _make
    for s in servers:
        s.stop()


@pytest.fixture()
def make_fake_forgejo():
    from fakes import FakeForgejoServer

    servers = []

    def _make(prs=None, **kw):
        s = FakeForgejoServer(prs=prs or [], pat=FAKE_FORGEJO_HEADER, **kw)
        s.start()
        servers.append(s)
        return s

    yield _make
    for s in servers:
        s.stop()


@pytest.fixture()
def synced(site, state_dir, make_fake_immich, run_sync):
    """One-shot convenience: write allowlist entries, serve albums, run once.
    Returns (server, result, allowlist_path)."""

    def _go(entries, albums, **run_kw):
        al = site.root / "sync-albums.yaml"
        al.write_text(load_allowlist_text(entries))
        server = make_fake_immich(albums)
        res = run_sync(
            immich_url=server.base_url,
            site_dir=site.root,
            state_dir=state_dir,
            albums_file=al,
            **run_kw,
        )
        return server, res, al

    return _go
