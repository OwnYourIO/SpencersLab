"""t9 (C01 Tests): front-matter policy on EXISTING pages — owner answer N1
(as recommended): append-only machine marker keys if absent; every
pre-existing key byte-identical; NEVER set or flip draft /
author_reviewed / editor_reviewed (draft:true would un-publish =
destructive). C01 AC3."""

import re

from conftest import album_dto, load_allowlist_text, make_asset

PAGE = "plants/aeroponics/current-grows"
ALBUM = "Aeroponics Current"
A1 = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])

ORIGINAL_FM_LINES = [
    "title: Current Grow System",
    "weight: 1",
    "type: docs",
    'todo: "- keep the narrative current"',
    "author_reviewed: false",
    "editor_reviewed: false",
]


def _setup(site):
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM, "page": PAGE}]))
    return al


def _run(site, server, al, run_sync, state_dir, **kw):
    return run_sync(
        immich_url=server.base_url,
        site_dir=site.root,
        state_dir=state_dir,
        albums_file=al,
        **kw,
    )


def test_marker_appended_existing_keys_untouched(site, make_fake_immich, run_sync, state_dir):
    """§8: immich_synced appears; all original front-matter keys keep their
    exact bytes and relative order (append-only, never inline edits)."""
    al = _setup(site)
    server = make_fake_immich([album_dto("al-a", ALBUM, [A1])])
    res = _run(site, server, al, run_sync, state_dir)
    assert res.rc == 0, res.output
    fm = site.fm_of(site.page_text(PAGE))
    lines = [l for l in fm.splitlines() if l.strip()]
    assert any(l.startswith("immich_synced") for l in lines), fm
    idx = -1
    for line in ORIGINAL_FM_LINES:
        hits = [i for i, l in enumerate(lines) if l == line]
        assert hits, f"pre-existing key lost or rewritten: {line!r} not in {lines}"
        assert hits[0] > idx, f"pre-existing key order changed: {line!r}"
        idx = hits[0]
    assert ALBUM in fm, f"marker must list the album: {fm!r}"


def test_marker_lists_multiple_albums_on_a_shared_page(site, make_fake_immich, run_sync, state_dir):
    """§8 shape `immich_synced: {albums: [...], at: <date>}` — two albums
    targeting one page accumulate in ONE marker's albums list (a second
    top-level key would violate append-only idempotency)."""
    a2 = make_asset("a2", "IMG_2.JPG", bytes(range(16, 32)), "2026-03-15T10:00:00+00:00", ["al-b"])
    site.six_glob_page("shared/page")
    al = site.root / "sync-albums.yaml"
    al.write_text(
        load_allowlist_text(
            [
                {"name": "Aeroponics Current", "page": "shared/page"},
                {"name": "Past Designs Archive", "page": "shared/page"},
            ]
        )
    )
    server = make_fake_immich(
        [album_dto("al-a", "Aeroponics Current", [A1]), album_dto("al-b", "Past Designs Archive", [a2])]
    )
    res = _run(site, server, al, run_sync, state_dir)
    assert res.rc == 0, res.output
    fm = site.fm_of(site.page_text("shared/page"))
    assert fm.count("immich_synced") == 1, fm
    assert "Aeroponics Current" in fm and "Past Designs Archive" in fm


def test_never_draft_or_flip_review_flags(site, make_fake_immich, run_sync, state_dir):
    """§8 N1: no draft key appears and the review flags keep their exact
    lines — the human gate is the PR + farm preview, not sync."""
    al = _setup(site)
    server = make_fake_immich([album_dto("al-a", ALBUM, [A1])])
    res = _run(site, server, al, run_sync, state_dir)
    assert res.rc == 0, res.output
    fm = site.fm_of(site.page_text(PAGE))
    assert not re.search(r"^draft:", fm, re.M), fm
    for key in ("author_reviewed: false", "editor_reviewed: false"):
        assert fm.count(key) == 1, f"{key} count changed in {fm!r}"


def test_rerun_adds_no_second_marker(site, make_fake_immich, run_sync, state_dir):
    """§8 + §10 idempotency: the marker is added if ABSENT — a second run
    leaves the whole page byte-identical (no front-matter churn in the PR
    diff)."""
    al = _setup(site)
    server = make_fake_immich([album_dto("al-a", ALBUM, [A1])])
    r1 = _run(site, server, al, run_sync, state_dir)
    assert r1.rc == 0, r1.output
    after_first = site.page_bytes(PAGE)
    r2 = _run(site, server, al, run_sync, state_dir, force=True)
    assert r2.rc == 0, r2.output
    assert site.fm_of(site.page_text(PAGE)).count("immich_synced") == 1
    assert site.page_bytes(PAGE) == after_first, "front matter drifted on re-run"
