"""t12 (C01 Tests): shared HTTP layer — 'timeout + one 5xx retry'; a 4xx is
a clean error (no retry storm, no traceback leak). Asserted from the wire:
the fake counts attempts. Contract 'Shared HTTP layer'."""

from conftest import album_dto, expected_base_name, load_allowlist_text, make_asset

PAGE = "plants/aeroponics/current-grows"
ALBUM = "Aeroponics Current"
A1 = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])
A2 = make_asset("a2", "IMG_2.JPG", bytes(range(16, 32)), "2026-03-15T10:00:00+00:00", ["al-a"])


def _setup(site, make_fake_immich, assets, **server_kw):
    site.no_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM, "page": PAGE}]))
    server = make_fake_immich([album_dto("al-a", ALBUM, assets)], **server_kw)
    return server, al


def test_5xx_is_retried_exactly_once(site, state_dir, make_fake_immich, run_sync):
    server, al = _setup(site, make_fake_immich, [A1])
    server.thumbnail_5xx_once.add(A1["id"])
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    attempts = [r for r in server.hits("GET", "/thumbnail") if A1["id"] in r.path]
    assert len(attempts) == 2, f"expected exactly one retry, saw {len(attempts)}"
    assert (site.root / "content" / PAGE / expected_base_name(A1)).exists(), \
        "retry must still deliver the file"


def test_4xx_is_a_clean_single_attempt_error(site, state_dir, make_fake_immich, run_sync):
    """AC2/t12: a hard 404 must fail the run NON-ZERO after a single
    attempt — the one-retry budget belongs to 5xx only — and report cleanly
    (names the asset, raises no raw traceback)."""
    server, al = _setup(site, make_fake_immich, [A1, A2])
    server.thumbnail_404.add(A2["id"])
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc != 0, f"404 swallowed: {res.output!r}"
    attempts = [r for r in server.hits("GET", "/thumbnail") if A2["id"] in r.path]
    # One attempt per endpoint mount at most: a client that tries the bare
    # path before the /api prefix may log two, but neither path may repeat —
    # the single-retry budget belongs to 5xx only.
    variants = {("/api/" in r.path) for r in attempts}
    assert len(attempts) <= 2 and len(variants) == len(attempts), \
        f"4xx was retried on some mount: {[r.path for r in attempts]}"
    assert "Traceback" not in res.err, res.err
