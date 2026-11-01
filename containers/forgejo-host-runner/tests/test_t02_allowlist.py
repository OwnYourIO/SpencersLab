"""t2 (C01 Tests): allowlist schema validation and album selection —
owner answer N3 (page: REQUIRED, loud failure naming the entry; NO
content/photos/ fallback) and the ALBUMS dispatch override. C01 AC5."""

import pytest

from conftest import album_dto, load_allowlist_text, make_asset, tree_digest

PAGE = "plants/aeroponics/current-grows"
ALBUM_A = "Aeroponics Current"
ALBUM_B = "Past Designs Archive"

ASSET = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])


def _albums():
    return [album_dto("al-a", ALBUM_A, [ASSET]), album_dto("al-b", ALBUM_B, [ASSET])]


def test_missing_page_fails_loud_naming_entry(site, state_dir, make_fake_immich, run_sync):
    """N3: an entry without page: is a schema error that names the entry and
    exits non-zero BEFORE any network or write (C01 §1 "validate the
    allowlist FIRST"). The loud-failure-not-fallback posture is AC5."""
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(f'albums:\n  - name: "{ALBUM_B}"\n')  # no page: key
    before = tree_digest(site.root)
    server = make_fake_immich(_albums())
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc != 0, f"schema-invalid entry accepted: {res.output!r}"
    assert ALBUM_B in res.output, f"error does not name the entry: {res.output!r}"
    assert tree_digest(site.root) == before, "a rejected allowlist still wrote files"
    assert not server.hits("GET", "/albums"), "validation must precede album resolution"


def test_missing_name_fails_loud_naming_entry(site, state_dir, make_fake_immich, run_sync):
    """§1: missing name: likewise — non-zero naming the entry (the page
    string is the entry's only identifier here). C01 AC5."""
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(f"albums:\n  - page: {PAGE}\n")
    server = make_fake_immich(_albums())
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc != 0, f"schema-invalid entry accepted: {res.output!r}"
    assert PAGE in res.output, f"error does not identify the entry: {res.output!r}"
    assert not server.hits("GET", "/albums")


# The prefix is concatenated straight into derivative file names, so these
# characters would escape the bundle directory or feed a shell (path
# smuggling past the §3 target guard). The safe-PREFIX half stays covered by
# t07's accepted "v7-web" fit — a narrowed rejection class turns THAT red.
UNSAFE_PREFIXES = ["a/b", "../esc", "a\\b", "two words", "; touch x", "$(id)", "v6*"]


@pytest.mark.parametrize("prefix", UNSAFE_PREFIXES)
def test_unsafe_prefix_fails_loud_naming_entry(site, state_dir, make_fake_immich, run_sync, prefix):
    """§1/AC5 loud-fail posture extended to the unsafe prefix: schema error
    naming the entry, exit non-zero BEFORE any network or write (same shape
    as the missing-page guard — validation runs over the whole allowlist
    first). Review-found: dev's defensive guard had no test."""
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(
        f'albums:\n  - name: "{ALBUM_B}"\n    page: {PAGE}\n    prefix: "{prefix}"\n'
    )
    before = tree_digest(site.root)
    server = make_fake_immich(_albums())
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc != 0, f"unsafe prefix {prefix!r} accepted: {res.output!r}"
    assert ALBUM_B in res.output, f"error does not name the entry: {res.output!r}"
    assert tree_digest(site.root) == before, "a rejected allowlist still wrote files"
    assert not server.hits("GET", "/albums"), "validation must precede album resolution"


def test_empty_allowlist_is_clean_noop(site, state_dir, make_fake_immich, run_sync):
    """albums: [] ships empty in C06 ("nothing syncs until the owner
    curates") — a valid no-op, exit 0. C01 AC1 boundary."""
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text("albums: []\n")
    server = make_fake_immich(_albums())
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    assert not server.hits("GET", "/albums"), "an empty allowlist must not query Immich"


def test_albums_override_selects_subset(site, make_fake_immich, run_sync, state_dir):
    """ALBUMS (dispatch input) restricts the run to the named subset of the
    allowlist file — the file still supplies the page mapping. C01 §env."""
    site.no_glob_page(PAGE)
    site.six_glob_page()
    al = site.root / "sync-albums.yaml"
    al.write_text(
        load_allowlist_text(
            [{"name": ALBUM_A, "page": PAGE}, {"name": ALBUM_B, "page": "plants/aeroponics/past-designs/grow-environments"}]
        )
    )
    server = make_fake_immich(_albums())
    res = run_sync(
        immich_url=server.base_url,
        site_dir=site.root,
        state_dir=state_dir,
        albums_file=al,
        albums=ALBUM_A,
    )
    assert res.rc == 0, res.output
    unselected = site.bundle_files("plants/aeroponics/past-designs/grow-environments")
    assert not any(n.startswith("sync-") or n.startswith("2026") for n in unselected), \
        f"ALBUMS override synced an unselected album: {unselected}"


def test_albums_override_unknown_name_errors(site, make_fake_immich, run_sync, state_dir):
    """§env: ALBUMS entries not in the allowlist error loud — the override
    narrows the curated set, it never widens it. C01 §1/AC5."""
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM_A, "page": PAGE}]))
    server = make_fake_immich(_albums())
    res = run_sync(
        immich_url=server.base_url,
        site_dir=site.root,
        state_dir=state_dir,
        albums_file=al,
        albums="Ghost Album",
    )
    assert res.rc != 0, res.output
    assert "Ghost Album" in res.output


def test_unresolved_album_name_errors(site, make_fake_immich, run_sync, state_dir):
    """§1: allowlist name with no matching Immich album = fail loud naming
    it — the exact-name resolution has no fuzzy fallback. C01 AC5."""
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM_B, "page": PAGE}]))
    server = make_fake_immich([album_dto("al-a", ALBUM_A, [ASSET])])
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc != 0, res.output
    assert ALBUM_B in res.output
