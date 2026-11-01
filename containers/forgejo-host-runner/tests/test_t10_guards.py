"""t10 (C01 Tests): the HARD GUARDS — AC3 requires a dedicated test per
guard. Guards under test (chunks/C01.md "HARD GUARDS"):
  g1 permitted edits only (front-matter marker + own machine blocks)
  g2 machine files = ledger-recorded files (covered jointly with t8)
  g3 never write outside SITE_DIR/content/ (path normalization enforced)
  g4 hugo.yaml / layouts / netlify.toml / .gitattributes / .forgejo untouched
  g5 the two manual derivatives stay byte-identical (ledger rule, no
     special-casing)
  g6 albums with zero IMAGE assets skipped.
"""

import pytest

from conftest import (
    MANUAL_DERIVATIVES,
    album_dto,
    expected_base_name,
    load_allowlist_text,
    make_asset,
    tree_digest,
)

PAGE = "plants/aeroponics/current-grows"
ALBUM = "Aeroponics Current"
A1 = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])

PROTECTED = (
    "hugo.yaml",
    "netlify.toml",
    ".gitattributes",
    "layouts/_shortcodes/gallery.html",
    ".forgejo/workflows/deploy.yml",
    "content/_index.md",
    "content/plants/aeroponics/untargeted/_index.md",
    "content/plants/aeroponics/untargeted/keepme-001.jpg",
)


@pytest.fixture()
def full_site(site):
    site.no_glob_page(PAGE)
    site.site_chrome()
    return site


def _sync(full_site, make_fake_immich, run_sync, state_dir, entries, albums):
    al = full_site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text(entries))
    server = make_fake_immich(albums)
    return server, run_sync(
        immich_url=server.base_url,
        site_dir=full_site.root,
        state_dir=state_dir,
        albums_file=al,
    )


def test_g3_writes_outside_content_rejected_including_traversal(full_site, make_fake_immich, run_sync, state_dir):
    """g3: a page: reaching outside content/ (../ traversal) is a loud
    error; nothing is created; no normal-path run ever writes off-content
    either (asserted jointly by the site-chrome digests below)."""
    before = tree_digest(full_site.root)
    _server, res = _sync(
        full_site,
        make_fake_immich,
        run_sync,
        state_dir,
        [{"name": ALBUM, "page": "../../escape-target"}],
        [album_dto("al-a", ALBUM, [A1])],
    )
    assert res.rc != 0, res.output
    digest_after = tree_digest(full_site.root)
    new = set(digest_after) - set(before) - {"sync-albums.yaml"}
    assert not any(not n.startswith("content/") for n in new), sorted(new)


def test_g4_protected_files_byte_identical_after_full_sync(full_site, make_fake_immich, run_sync, state_dir):
    """g1+g4: a complete sync (target resolution, writes, machine blocks,
    front matter) leaves every config/layout/CI/attributes file and every
    untargeted content file byte-identical."""
    before = tree_digest(full_site.root)
    six = full_site.six_glob_page("plants/aeroponics/past-designs/grow-environments")
    _server, res = _sync(
        full_site,
        make_fake_immich,
        run_sync,
        state_dir,
        [
            {"name": ALBUM, "page": PAGE},
            {"name": "Past Designs Archive", "page": six},
        ],
        [
            album_dto("al-a", ALBUM, [A1]),
            album_dto("al-b", "Past Designs Archive", [A1]),
        ],
    )
    assert res.rc == 0, res.output
    after = tree_digest(full_site.root)
    for rel in PROTECTED:
        assert rel in before, f"fixture lost {rel}"
        assert after.get(rel) == before[rel], f"{rel} was modified"
    # Everything that changed must be a permitted edit or a machine file:
    changed = {r for r in before if after.get(r) != before[r]}
    removed = set(before) - set(after)
    assert not removed, f"files deleted by sync: {sorted(removed)}"
    for r in changed:
        assert r.startswith("content/"), r
        assert r.endswith(".md"), f"unexpected non-page edit: {r}"


def test_g5_manual_derivatives_survive_full_sync(full_site, make_fake_immich, run_sync, state_dir):
    """g5: the two manual derivatives in the no-glob bundle receive new
    siblings (the page auto-includes everything) and come out
    byte-identical — the ledger rule protects them WITHOUT special-casing
    their names. C01 AC3's named case."""
    root = full_site.root
    before = {
        name: (root / "content" / PAGE / name).read_bytes() for name in MANUAL_DERIVATIVES
    }
    _server, res = _sync(
        full_site,
        make_fake_immich,
        run_sync,
        state_dir,
        [{"name": ALBUM, "page": PAGE}],
        [album_dto("al-a", ALBUM, [A1])],
    )
    assert res.rc == 0, res.output
    for name, data in before.items():
        assert (root / "content" / PAGE / name).read_bytes() == data, name
    assert expected_base_name(A1) in full_site.bundle_files(PAGE), "sync wrote nothing here"


def test_g6_zero_image_album_skipped_not_error(full_site, make_fake_immich, run_sync, state_dir):
    """g6: an allowlisted album whose IMAGE set is empty (videos only) is
    skipped — exit stays 0, nothing written for it, the image album still
    syncs."""
    video = dict(A1, id="v1", type="VIDEO", originalFileName="CLIP.MOV")
    _server, res = _sync(
        full_site,
        make_fake_immich,
        run_sync,
        state_dir,
        [
            {"name": ALBUM, "page": PAGE},
            {"name": "Empty Album", "page": PAGE},
        ],
        [
            album_dto("al-a", ALBUM, [A1]),
            album_dto("al-e", "Empty Album", [video]),
        ],
    )
    assert res.rc == 0, res.output
    assert expected_base_name(A1) in full_site.bundle_files(PAGE)
    # The VIDEO asset must not be pulled despite living in the album:
    assert expected_base_name(video) not in full_site.bundle_files(PAGE)
