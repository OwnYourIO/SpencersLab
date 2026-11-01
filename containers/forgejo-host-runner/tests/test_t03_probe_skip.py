"""t3 (C01 Tests): change-probe and skip — §2 compares the album's
lastModifiedAssetTimestamp against state and skips unchanged albums unless
FORCE. The probe is what makes the daily cadence cheap (answer 7 context).
C01 AC6."""

from conftest import album_dto, load_allowlist_text, make_asset, sync_result

PAGE = "plants/aeroponics/current-grows"
ALBUM = "Aeroponics Current"
ASSET = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])


def _setup(synced, site):
    site.no_glob_page(PAGE)
    entries = [{"name": ALBUM, "page": PAGE}]
    return synced(entries, [album_dto("al-a", ALBUM, [ASSET])])


def test_unchanged_album_skipped_on_rerun(site, state_dir, make_fake_immich, run_sync):
    """Run 2 with an unchanged album: no /search/metadata at all (the probe
    answered from the GET /albums list), summary changed=no (§2 + AC6)."""
    site.no_glob_page(PAGE)
    entries = [{"name": ALBUM, "page": PAGE}]
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text(entries))
    server = make_fake_immich([album_dto("al-a", ALBUM, [ASSET])])
    kw = dict(immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al)
    r1 = run_sync(**kw)
    assert r1.rc == 0, r1.output
    searches_1 = len(server.hits("POST", "/search/metadata"))
    assert searches_1 >= 1

    r2 = run_sync(**kw)
    assert r2.rc == 0, r2.output
    assert len(server.hits("POST", "/search/metadata")) == searches_1, \
        "unchanged album was re-searched — the lastModifiedAssetTimestamp probe must skip it"
    s2 = sync_result(r2.out)
    assert s2 and s2["changed"] == "no", f"second run reported {s2}"


def test_force_bypasses_the_probe(site, state_dir, make_fake_immich, run_sync, synced):
    """FORCE=true re-searches even a timestamp-unchanged album (§2); files
    already exist so the run stays diff-empty (§6/§10 checksum naming)."""
    server, r1, al = _setup(synced, site)
    searches_1 = len(server.hits("POST", "/search/metadata"))
    r2 = run_sync(
        immich_url=server.base_url,
        site_dir=site.root,
        state_dir=state_dir,
        albums_file=al,
        force=True,
    )
    assert r2.rc == 0, r2.output
    assert len(server.hits("POST", "/search/metadata")) > searches_1, \
        "FORCE did not bypass the probe"
    s2 = sync_result(r2.out)
    assert s2 and s2["changed"] == "no" and s2["added"] == 0


def test_bumped_album_timestamp_triggers_repull(site, state_dir, make_fake_immich, run_sync, synced):
    """§2: an album whose lastModifiedAssetTimestamp moved since the state
    record IS re-probed (the daily sync catches new photos)."""
    server, r1, al = _setup(synced, site)
    base_hits = len(server.hits("POST", "/search/metadata"))
    server.last_modified["al-a"] = "2026-04-01T00:00:00.000Z"
    r2 = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert r2.rc == 0, r2.output
    assert len(server.hits("POST", "/search/metadata")) > base_hits, \
        "bumped album timestamp ignored — probe compares against state"
