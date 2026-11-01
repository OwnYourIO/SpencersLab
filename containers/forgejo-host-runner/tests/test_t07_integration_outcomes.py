"""t7 (C01 Tests): the three gallery-integration outcomes of contract §5,
owner answer N2 (AUTO-EXTEND, pinned block shape). All three outcomes are
required by C01 AC4; the block bytes are the DECISIONS R12 pinned shape."""

import fnmatch

from conftest import (
    album_dto,
    expected_base_name,
    load_allowlist_text,
    machine_block,
    make_asset,
    slug_of,
    sync_result,
)

A1 = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])
A2 = make_asset("a2", "IMG_2.JPG", bytes(range(16, 32)), "2026-03-15T10:00:00+00:00", ["al-a"])
NO_GLOB = "plants/aeroponics/current-grows"
SIX_GLOB = "plants/aeroponics/past-designs/grow-environments"


def _one(site, make_fake_immich, run_sync, state_dir, page, entries):
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text(entries))
    server = make_fake_immich([album_dto("al-a", entries[0]["name"], [A1, A2])])
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    return server, res


def test_no_glob_page_takes_files_unprefixed_with_zero_body_edits(site, make_fake_immich, run_sync, state_dir):
    """§5 outcome 1: a no-match gallery (.ByType image) includes anything —
    files land UNPREFIXED, chronological inside the authored Name-sort, and
    the page body carries no machine marker. C01 AC4."""
    site.no_glob_page(NO_GLOB)
    before_body = site.body_of(site.page_text(NO_GLOB))
    _server, _res = _one(
        site, make_fake_immich, run_sync, state_dir, NO_GLOB,
        [{"name": "Aeroponics Current", "page": NO_GLOB}],
    )
    names = site.bundle_files(NO_GLOB)
    assert expected_base_name(A1) in names and expected_base_name(A2) in names
    assert not any(n.startswith("sync-") for n in names), names
    page_text = site.page_text(NO_GLOB)
    assert "immich-sync:" not in page_text, "machine block written onto an auto-including page"
    assert site.body_of(page_text) == before_body, "page body edited on the auto-include path"


def test_authored_glob_fit_needs_no_prefix_no_block(site, make_fake_immich, run_sync, state_dir):
    """§5 outcome 1 (glob branch): a case-insensitive jpg glob already
    includes the plain date names → unprefixed, zero page edits."""
    site.jpg_glob_page()
    page = "plants/aeroponics/past-designs"
    before_body = site.body_of(site.page_text(page))
    _server, _res = _one(
        site, make_fake_immich, run_sync, state_dir, page,
        [{"name": "Aeroponics Current", "page": page}],
    )
    names = site.bundle_files(page)
    assert expected_base_name(A1) in names
    assert not any(n.startswith("sync-") for n in names)
    assert site.body_of(site.page_text(page)) == before_body
    assert "immich-sync:" not in site.page_text(page)


def test_allowlist_prefix_fit_zero_page_edits(site, make_fake_immich, run_sync, state_dir):
    """§5: prefix: on a fitting authored glob = the zero-edit path the owner
    keeps available even though no-fit auto-extends (R12 last sentence)."""
    site.v7_glob_page()
    page = "plants/aeroponics/past-designs/v7-designs"
    before_body = site.body_of(site.page_text(page))
    _server, _res = _one(
        site, make_fake_immich, run_sync, state_dir, page,
        [{"name": "Aeroponics Current", "page": page, "prefix": "v7-web"}],
    )
    assert not any(fnmatch.fnmatch(n, "sync-*") for n in site.bundle_files(page))
    assert "immich-sync:" not in site.page_text(page)
    assert site.body_of(site.page_text(page)) == before_body


def test_no_fit_writes_exactly_one_pinned_machine_block(site, make_fake_immich, run_sync, state_dir):
    """§5 outcome 2 (R12 pinned shape, byte-exact): six authored globs, no
    fit → one block per (page, album) appended after the file's last line,
    prefixed filenames matching the block's glob, summary counts it.
    C01 AC4."""
    site.six_glob_page(SIX_GLOB)
    album = "Past Designs Archive"
    _server, res = _one(
        site, make_fake_immich, run_sync, state_dir, SIX_GLOB,
        [{"name": album, "page": SIX_GLOB}],
    )
    text = site.page_text(SIX_GLOB)
    block = machine_block(album)
    lines = text.splitlines()
    start = [i for i, l in enumerate(lines) if l == block[0]]
    assert len(start) == 1, f"expected exactly one machine block, found {len(start)}"
    assert lines[start[0] : start[0] + 3] == block, lines[start[0] : start[0] + 5]
    assert lines[-3:] == block, "block not appended after the file's last line"
    names = site.bundle_files(SIX_GLOB)
    prefixed = [n for n in names if n.startswith(f"sync-{slug_of(album)}-")]
    assert sorted(prefixed) == sorted([f"sync-{slug_of(album)}-{expected_base_name(A1)}",
                                       f"sync-{slug_of(album)}-{expected_base_name(A2)}"]), names
    glob = f"sync-{slug_of(album)}-*"
    assert [n for n in names if fnmatch.fnmatch(n, glob)] == sorted(prefixed)
    s = sync_result(res.out)
    assert s and s["blocks"] == 1, f"summary blocks= disagrees: {s}"


def test_two_albums_no_fit_write_one_block_each(site, make_fake_immich, run_sync, state_dir):
    """§5: one block per (page, album) — two no-fit albums on one page get
    two distinct blocks, never one merged."""
    site.six_glob_page(SIX_GLOB)
    a1 = make_asset("b1", "IMG_A.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])
    a2 = make_asset("b2", "IMG_B.JPG", bytes(range(16, 32)), "2026-04-14T09:26:53+00:00", ["al-b"])
    al = site.root / "sync-albums.yaml"
    entries = [
        {"name": "Aeroponics Current", "page": SIX_GLOB},
        {"name": "Past Designs Archive", "page": SIX_GLOB},
    ]
    al.write_text(load_allowlist_text(entries))
    server = make_fake_immich(
        [album_dto("al-a", "Aeroponics Current", [a1]), album_dto("al-b", "Past Designs Archive", [a2])]
    )
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    text = site.page_text(SIX_GLOB)
    for album in ("Aeroponics Current", "Past Designs Archive"):
        block = machine_block(album)
        lines = text.splitlines()
        starts = [i for i, l in enumerate(lines) if l == block[0]]
        assert len(starts) == 1, f"{album}: {len(starts)} blocks"
        assert lines[starts[0] : starts[0] + 3] == block
    s = sync_result(res.out)
    assert s and s["blocks"] == 2
