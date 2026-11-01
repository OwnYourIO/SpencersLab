"""t6 (C01 Tests): target resolution — §3: the page: bundle dir MUST exist
and carry index.md or _index.md, else a loud error; sync NEVER creates
pages (the N3 no-fallback posture's write-side twin). C01 AC5."""

from conftest import album_dto, expected_base_name, load_allowlist_text, make_asset, tree_digest

ALBUM = "Aeroponics Current"
ASSET = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])
PAGE = "plants/aeroponics/current-grows"


def _run(site, make_fake_immich, run_sync, state_dir, page):
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM, "page": page}]))
    server = make_fake_immich([album_dto("al-a", ALBUM, [ASSET])])
    return server, run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )


def test_missing_page_dir_is_loud_error_no_creation(site, make_fake_immich, run_sync, state_dir):
    """§3 "never create pages": a page: naming an absent directory fails
    loud and leaves the content tree byte-identical. C01 AC5."""
    site.no_glob_page(PAGE)
    site.site_chrome()
    before = tree_digest(site.root)
    _server, res = _run(site, make_fake_immich, run_sync, state_dir, "plants/aeroponics/ghost-bundle")
    assert res.rc != 0, res.output
    assert "plants/aeroponics/ghost-bundle" in res.output, \
        f"error does not name the offending page: {res.output!r}"
    after = {k: v for k, v in tree_digest(site.root).items() if k != "sync-albums.yaml"}
    assert after == before, "a rejected target still wrote files"


def test_page_dir_without_index_is_loud_error(site, make_fake_immich, run_sync, state_dir):
    """§3: the bundle exists but has no index.md/_index.md — still a loud
    error (a directory is not a page)."""
    site.no_glob_page(PAGE)
    (site.root / "content" / "plants" / "aeroponics" / "empty-dir").mkdir(parents=True)
    before = tree_digest(site.root)
    _server, res = _run(site, make_fake_immich, run_sync, state_dir, "plants/aeroponics/empty-dir")
    assert res.rc != 0, res.output
    after = {k: v for k, v in tree_digest(site.root).items() if k != "sync-albums.yaml"}
    assert after == before


def test_accepts_index_and_underscore_index(site, make_fake_immich, run_sync, state_dir):
    """§3 names BOTH index shapes — the real repo mixes them (current-grows
    uses _index.md, grow-environments uses index.md). Two albums, one per
    shape: the state model pins albumId -> exactly one target, so one album
    never spans two pages."""
    site.bundle_page("under/_", title="Underscore", galleries=['sort="desc"'], index="_index.md")
    site.bundle_page("under/plain", title="Plain", galleries=['sort="desc"'], index="index.md")
    album_b = make_asset("b1", "IMG_B.JPG", bytes(range(16, 32)), "2026-03-15T10:00:00+00:00", ["al-b"])
    al = site.root / "sync-albums.yaml"
    al.write_text(
        load_allowlist_text(
            [
                {"name": ALBUM, "page": "under/_"},
                {"name": "Past Designs Archive", "page": "under/plain"},
            ]
        )
    )
    server = make_fake_immich(
        [album_dto("al-a", ALBUM, [ASSET]), album_dto("al-b", "Past Designs Archive", [album_b])]
    )
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    assert expected_base_name(ASSET) in site.bundle_files("under/_")
    assert expected_base_name(album_b) in site.bundle_files("under/plain")
