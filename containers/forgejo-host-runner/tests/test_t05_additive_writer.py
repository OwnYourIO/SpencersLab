"""t5 (C01 Tests): additive writer — §6 downloads only MISSING derivatives;
existing files (same name) are never re-downloaded or overwritten. This is
the "additive-only" half of the owner answer-9 seam pivot. C01 AC3."""

import hashlib

from conftest import FAKE_IMMICH_HEADER, album_dto, expected_base_name, load_allowlist_text, make_asset

PAGE = "plants/aeroponics/current-grows"
ALBUM = "Aeroponics Current"
A1 = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])
A2 = make_asset("a2", "IMG_2.JPG", bytes(range(16, 32)), "2026-03-15T10:00:00+00:00", ["al-a"])

SENTINEL = b"HUMAN BYTE-FOR-BYTE -- never overwrite this file\n" * 8


def _site_and_allowlist(site):
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM, "page": PAGE}]))
    return al


def test_missing_derivatives_downloaded_cleanly(site, make_fake_immich, run_sync, state_dir):
    """§6: each missing derivative lands; the temp→rename discipline leaves
    no partial/temp file in the bundle; size=preview is the pinned route
    (RESEARCH.md R2.3: size=original is deprecated — never use it)."""
    al = _site_and_allowlist(site)
    server = make_fake_immich([album_dto("al-a", ALBUM, [A1, A2])])
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    for asset in (A1, A2):
        assert (site.root / "content" / PAGE / expected_base_name(asset)).exists()
    thumbs = server.hits("GET", "/thumbnail")
    assert thumbs, "no thumbnail fetch"
    assert all("size=preview" in r.path for r in thumbs), [r.path for r in thumbs]
    assert all(not n.endswith(".tmp") for n in site.bundle_files(PAGE)), site.bundle_files(PAGE)


def test_existing_derivative_never_refetched_or_overwritten(site, make_fake_immich, run_sync, state_dir):
    """§6/HARD GUARDS: a same-name file on disk stays byte-identical even
    when the album is re-searched (FORCE) — the additive-only floor."""
    al = _site_and_allowlist(site)
    target = site.root / "content" / PAGE / expected_base_name(A1)
    target.write_bytes(SENTINEL)
    before = hashlib.sha256(target.read_bytes()).hexdigest()
    server = make_fake_immich([album_dto("al-a", ALBUM, [A1, A2])])
    res = run_sync(
        immich_url=server.base_url,
        site_dir=site.root,
        state_dir=state_dir,
        albums_file=al,
        force=True,  # re-search the album so the fetch decision is exercised
    )
    assert res.rc == 0, res.output
    assert hashlib.sha256(target.read_bytes()).hexdigest() == before, \
        "existing file was rewritten despite the same-name skip rule"
    assert not [r for r in server.hits("GET", "/thumbnail") if A1["id"] in r.path], \
        "same-name file was re-downloaded"
    assert expected_base_name(A2) in site.bundle_files(PAGE), "missing sibling not fetched"


def test_immich_calls_carry_x_api_key(site, make_fake_immich, run_sync, state_dir):
    """Contract 'Shared HTTP layer': x-api-key on every Immich call. The
    fake 401s anything else — a passing run plus header records prove the
    wire shape from both sides."""
    al = _site_and_allowlist(site)
    server = make_fake_immich([album_dto("al-a", ALBUM, [A1])])
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    assert server.requests, "sync succeeded without a single recorded Immich call"
    assert all(
        r.headers.get("x-api-key") == FAKE_IMMICH_HEADER
        for r in server.requests
        if r.path.split("?")[0] not in ("/", "")
    ), sorted({str(r.headers.get("x-api-key")) for r in server.requests})
