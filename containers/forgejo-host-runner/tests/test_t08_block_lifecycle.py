"""t8 (C01 Tests): machine-block LIFECYCLE — contract §5 "block lifecycle
(idempotent, N2-a)": re-runs update in place and never stack; a later
auto-inclusion transition removes sync's own block and renames its own files
via ledger ops, touching nothing human. C01 AC4."""

from conftest import (
    MANUAL_DERIVATIVES,
    album_dto,
    expected_base_name,
    expected_sync_name,
    load_allowlist_text,
    make_asset,
    slug_of,
    sync_result,
)

PAGE = "plants/aeroponics/past-designs/grow-environments"
ALBUM = "Past Designs Archive"
SLUG = slug_of(ALBUM)
A1 = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])

GLOB_LINE = f'{{{{< gallery match="sync-{SLUG}-*" sort="desc" >}}}}'


def _run(site, server, al, run_sync, state_dir, **kw):
    return run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al, **kw
    )


def _first_run(site, make_fake_immich, run_sync, state_dir, assets=None):
    site.six_glob_page(PAGE)
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM, "page": PAGE}]))
    server = make_fake_immich([album_dto("al-a", ALBUM, assets or [A1])])
    res = _run(site, server, al, run_sync, state_dir)
    assert res.rc == 0, res.output
    return server, al, res


def test_rerun_block_is_byte_identical_never_stacks(site, make_fake_immich, run_sync, state_dir):
    """N2-a: recognized by markers → re-run with an unchanged album leaves
    the page byte-for-byte identical (no second block, no drift). C01 AC4;
    also AC6 (second run changed=no)."""
    server, al, res = _first_run(site, make_fake_immich, run_sync, state_dir)
    page_bytes = site.page_bytes(PAGE)
    r2 = _run(site, server, al, run_sync, state_dir, force=True)  # FORCE re-probes; block must not stack
    assert r2.rc == 0, r2.output
    assert site.page_bytes(PAGE) == page_bytes, "page drifted on re-run"
    text = site.page_text(PAGE)
    assert text.count(f"<!-- immich-sync:album=\"{ALBUM}\"") == 1
    assert text.count(GLOB_LINE) == 1
    assert text.count(f"<!-- immich-sync:end:{SLUG} -->") == 1
    s = sync_result(r2.out)
    assert s and s["changed"] == "no"


def test_owner_widen_removes_block_and_renames_files_via_ledger(site, make_fake_immich, run_sync, state_dir):
    """§5 lifecycle: the owner edits the page so an authored call now
    includes the prefixed files → sync REMOVES its own block and renames
    its files to unprefixed (machine content managed by the machine; the
    authored page lines the owner wrote stay byte-identical). C01 AC4."""
    server, al, res = _first_run(site, make_fake_immich, run_sync, state_dir)
    prefixed = site.root / "content" / PAGE / expected_sync_name(A1, ALBUM)
    assert prefixed.exists()
    machine_bytes = prefixed.read_bytes()

    # The owner widens an authored gallery to include the prospective
    # (unprefixed, date-first) names — §5 outcome 1 evaluated on those
    # names flips the album to auto-included, and the machine block is
    # sync's own to remove.
    owner_edit = site.page_text(PAGE).replace(
        '{{< gallery match="v6-*" sort="asc" >}}',
        '{{< gallery match="2*" sort="asc" >}}',
    )
    (site.root / "content" / PAGE / "index.md").write_text(owner_edit)

    r2 = _run(site, server, al, run_sync, state_dir, force=True)
    assert r2.rc == 0, r2.output
    text = site.page_text(PAGE)
    assert "immich-sync:" not in text, "sync block survived the auto-inclusion"
    unprefixed = site.root / "content" / PAGE / expected_base_name(A1)
    assert unprefixed.exists(), "ledger rename did not produce the unprefixed file"
    assert unprefixed.read_bytes() == machine_bytes, "rename must preserve bytes (a move, not a re-download)"
    assert not prefixed.exists(), "prefixed file left behind after rename"
    # The owner's widened authored call and every other authored gallery
    # line survive exactly — the block removal must not rewrite them.
    assert '{{< gallery match="2*" sort="asc" >}}' in text
    for glob in ("v5-*", "v4-*", "v3-*", "v2-*", "2017-pfc-*"):
        assert f'{{{{< gallery match="{glob}" sort="asc" >}}}}' in text


def test_non_block_page_content_byte_identical_throughout(site, make_fake_immich, run_sync, state_dir):
    """§5/AC4: everything that is not sync's block never moves — authored
    images and the two manual derivatives included (they live OUTSIDE this
    bundle, so the whole-site control uses a second page)."""
    site.no_glob_page("plants/aeroponics/current-grows")
    before = {
        name: (site.root / "content" / "plants" / "aeroponics" / "current-grows" / name).read_bytes()
        for name in MANUAL_DERIVATIVES
    }
    _first_run(site, make_fake_immich, run_sync, state_dir)
    for name, data in before.items():
        p = site.root / "content" / "plants" / "aeroponics" / "current-grows" / name
        assert p.read_bytes() == data, f"manual derivative {name} touched"


def test_album_shrinkage_deletes_only_ledgered_machine_files(site, make_fake_immich, run_sync, state_dir):
    """§7 removals: the deletion set is the state ledger minus the current
    asset set — nothing pattern-inferred. An authored file named exactly
    like a machine file survives (the ledger, not the name, decides)."""
    a2 = make_asset("a2", "IMG_2.JPG", bytes(range(16, 32)), "2026-03-15T10:00:00+00:00", ["al-a"])
    server, al, res = _first_run(site, make_fake_immich, run_sync, state_dir, assets=[A1, a2])
    decoy = f"sync-{SLUG}-{expected_base_name(A1)}"
    victim = f"sync-{SLUG}-{expected_base_name(a2)}"
    # Authored file with a machine-looking name: NOT in the ledger.
    (site.root / "content" / PAGE / decoy).write_bytes(b"authored-decoy")

    album_assets = [x for x in server.albums[0]["_assets"] if x["id"] == "a1"]
    server.albums[0]["_assets"][:] = album_assets
    server.albums[0]["assetCount"] = 1
    server.last_modified["al-a"] = "2026-05-01T00:00:00.000Z"

    r2 = _run(site, server, al, run_sync, state_dir)
    assert r2.rc == 0, r2.output
    names = site.bundle_files(PAGE)
    assert victim not in names, f"ledgered file not removed: {names}"
    assert decoy in names, "non-ledger file deleted by pattern inference"
    s = sync_result(r2.out)
    assert s and s["removed"] == 1, s


def test_state_loss_means_no_deletions(site, make_fake_immich, run_sync, state_dir, tmp_path):
    """§7/§10: state lost → full re-probe but NO deletions (additive-only
    floor) even when the album has shrunk; blocks re-recognized by markers
    stay single."""
    a2 = make_asset("a2", "IMG_2.JPG", bytes(range(16, 32)), "2026-03-15T10:00:00+00:00", ["al-a"])
    server, al, res = _first_run(site, make_fake_immich, run_sync, state_dir, assets=[A1, a2])
    (state_dir / "curatedforest-sync.json").unlink()
    server.albums[0]["_assets"][:] = [x for x in server.albums[0]["_assets"] if x["id"] == "a1"]
    server.last_modified["al-a"] = "2026-05-02T00:00:00.000Z"
    r2 = _run(site, server, al, run_sync, state_dir)
    assert r2.rc == 0, r2.output
    names = site.bundle_files(PAGE)
    assert expected_sync_name(a2, ALBUM) in names, "orphan deleted from stateless inference"
    text = site.page_text(PAGE)
    assert text.count(f"<!-- immich-sync:album=\"{ALBUM}\"") == 1
