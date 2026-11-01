"""t4 (C01 Tests): search pagination — POST /search/metadata is paginated
(v3 SearchAssetResponseDto carries nextPage, null ends the walk — the fake
emits exactly that, no hasNextPage); a multi-page result must be fetched
fully. C01 AC1."""

from conftest import album_dto, expected_base_name, load_allowlist_text, make_asset, sync_result

PAGE = "plants/aeroponics/current-grows"
ALBUM = "Aeroponics Current"

# Five distinct capture times → five distinct names (checksums differ too);
# the fake caps pages at 2 items, so a complete walk needs 3 requests.
ASSETS = [
    make_asset(f"a{i}", f"IMG_{i}.JPG", bytes([i]) * 16, f"2026-03-1{i}T09:26:5{i}+00:00", ["al-a"])
    for i in range(1, 6)
]


def test_multi_page_search_fully_fetched(site, make_fake_immich, run_sync, state_dir):
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM, "page": PAGE}]))
    server = make_fake_immich([album_dto("al-a", ALBUM, ASSETS)], max_search_page_size=2)
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    names = set(site.bundle_files(PAGE))
    for asset in ASSETS:
        expected = expected_base_name(asset)
        assert expected in names, f"page walk dropped {expected}; got {sorted(names)}"
    searches = server.hits("POST", "/search/metadata")
    assert len(searches) >= 3, f"expected a walk of >=3 pages, saw {len(searches)}"
    s = sync_result(res.out)
    assert s and s["added"] == 5, f"summary disagrees with the fetched set: {s}"
