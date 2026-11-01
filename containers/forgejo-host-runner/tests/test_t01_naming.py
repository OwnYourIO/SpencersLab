"""t1 (C01 Tests): derivative filename assembly — contract §4 base shape and
§5 machine prefix. C01 AC1 (tooling tests) + AC4 (prefixed filenames match
the block glob)."""

from conftest import (
    album_dto,
    checksum8,
    expected_base_name,
    expected_prefixed_name,
    expected_sync_name,
    make_asset,
    slug_of,
)

ALBUM = "Aeroponics Current"
PAGE = "plants/aeroponics/current-grows"

# +00:00 on every fixture time: the contract takes the asset's LOCAL capture
# time and the DTO fallback chain is dev's choice, so the fixtures keep both
# fields at the same UTC wall clock — the name pins the capture instant
# without pinning which field was read.
A1 = make_asset("a1", "IMG_2026 0314#01(2).CR3", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al1"])
A2 = make_asset("a2", "Café Bar.JPG", bytes.fromhex("deadbeefcafebabe0123456789abcd"), "2025-12-01T17:28:14+00:00", ["al1"])


def _one_asset_site(synced, site, page):
    """ALBUM → [page] with the two shared assets served."""
    entries = [{"name": ALBUM, "page": page}]
    return synced(entries, [album_dto("al1", ALBUM, [A1, A2])])


def test_checksum8_and_capture_stamp(site, synced):
    """§4: checksum8 = first 8 hex of the base64 DTO checksum; date/time =
    capture stamp. C01 AC1."""
    site.no_glob_page(PAGE)
    _server, res, _ = _one_asset_site(synced, site, PAGE)
    assert res.rc == 0, res.output
    names = set(site.bundle_files(PAGE))
    for asset in (A1, A2):
        expected = expected_base_name(asset)
        assert expected in names, f"missing {expected} in {sorted(names)}"
    assert checksum8(A1["checksum"]) == "00010203"


def test_safe_original_sanitization(site, synced):
    """§4: basename ASCII-folded, non-[A-Za-z0-9._-] → _, lowercased,
    extension forced .jpg. 'Café Bar.JPG' proves the fold runs before the
    filter (é→e, not é→_); '(2)'/space prove the filter; .CR3 proves the
    extension override. C01 AC1."""
    site.no_glob_page(PAGE)
    _one_asset_site(synced, site, PAGE)
    names = site.bundle_files(PAGE)
    assert "20260314-092653_00010203_img_2026_0314_01_2_.jpg" in names, names
    assert "20251201-172814_deadbeef_cafe_bar.jpg" in names, names


def test_machine_prefix_assembly(site, synced):
    """§5 no-fit case: sync-<albumslug>-{YYYYMMDD}-{HHMMSS}_{checksum8}_{safe}.jpg,
    and every prefixed file satisfies the machine block's own glob. C01 AC4."""
    import fnmatch

    page = site.six_glob_page()
    entries = [{"name": ALBUM, "page": page}]
    _server, res, _ = synced(entries, [album_dto("al1", ALBUM, [A1])])
    assert res.rc == 0, res.output
    expected = expected_sync_name(A1, ALBUM)
    assert expected in site.bundle_files(page)
    glob = f"sync-{slug_of(ALBUM)}-*"
    matched = [n for n in site.bundle_files(page) if fnmatch.fnmatch(n, glob)]
    assert matched == [expected]


def test_allowlist_prefix_concatenation(site, synced):
    """§5 zero-edit path: allowlist prefix: prepends the base name directly
    (the C06 example prefix v7-web fitting glob v7-* only holds under
    concatenation). C01 AC4."""
    import fnmatch

    page = site.v7_glob_page()
    entries = [{"name": ALBUM, "page": page, "prefix": "v7-web"}]
    server, res, _ = synced(entries, [album_dto("al1", ALBUM, [A1])])
    assert res.rc == 0, res.output
    expected = expected_prefixed_name(A1, "v7-web")
    assert expected in site.bundle_files(page), sorted(site.bundle_files(page))
    assert fnmatch.fnmatch(expected, "v7-*")
