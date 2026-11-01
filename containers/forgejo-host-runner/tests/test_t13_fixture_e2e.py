"""t13 (C01 Tests): the FIXTURE E2E — C01 AC1's named spine: scratch replica
of the real site shape (no-glob sort=desc bundle WITH the two manual
derivative names + semantic-glob bundle with SIX authored globs) ×
FakeImmichServer serving two albums; album A auto-included (zero edit),
album B gets the machine block + prefixed files; hugo-independent render
contract on both pages' post-state; second run changed=no and blocks
byte-stable; PR step stubbed at the git boundary. (Card #11 E2E posture:
DECISIONS R2 — the real Immich API is unreachable from dev/gpu; card #88
owns the live E2E.)"""

import json
from fnmatch import fnmatch

from conftest import (
    MANUAL_DERIVATIVES,
    STATE_FILE,
    album_dto,
    expected_base_name,
    expected_sync_name,
    git,
    init_git_repo,
    load_allowlist_text,
    machine_block,
    make_asset,
    slug_of,
    sync_result,
)

CURRENT = "plants/aeroponics/current-grows"
ENVS = "plants/aeroponics/past-designs/grow-environments"
AER = "Aeroponics Current"
PDA = "Past Designs Archive"

A_CUR = [
    make_asset(
        f"c{i}", f"IMG_C{i}.JPG", bytes([10 + i]) * 16, f"2026-02-0{i + 1}T08:0{i + 1}:00+00:00", ["al-cur"]
    )
    for i in range(3)
]
A_PDA = [
    make_asset(
        f"g{i}", f"IMG_G{i}.JPG", bytes([20 + i]) * 16, f"2026-01-0{i + 1}T21:05:0{i}+00:00", ["al-pda"]
    )
    for i in range(2)
]
REPO = "CuratedForest/CuratedForest.com"


def _site_and_server(site, make_fake_immich, git_repo=False, tmp_origin=None):
    site.no_glob_page(CURRENT)
    site.six_glob_page(ENVS)
    site.site_chrome()
    al = site.root / "sync-albums.yaml"
    al.write_text(
        load_allowlist_text([{"name": AER, "page": CURRENT}, {"name": PDA, "page": ENVS}])
    )
    if git_repo:
        init_git_repo(site, tmp_origin)
    server = make_fake_immich(
        [album_dto("al-cur", AER, A_CUR), album_dto("al-pda", PDA, A_PDA)]
    )
    return server, al


def test_two_albums_two_outcomes_end_to_end(site, make_fake_immich, run_sync, state_dir, tmp_path):
    """Full contract walk: selection → probe → pull → integration → write →
    state → summary flag → idempotent re-run."""
    server, al = _site_and_server(site, make_fake_immich)
    flag = tmp_path / "flag.txt"
    kw = dict(immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al)
    r1 = run_sync(**kw, output_flag=flag)
    assert r1.rc == 0, r1.output
    s1 = sync_result(r1.out)
    assert s1 == {"albums": 2, "added": 5, "removed": 0, "blocks": 1, "changed": "yes"}, s1
    assert flag.read_text().strip() == "changed", flag.read_text()

    # Outcome 1 (no-glob page): unprefixed files, zero body edits.
    body = site.body_of(site.page_text(CURRENT))
    assert "immich-sync:" not in body
    cur_names = site.bundle_files(CURRENT)
    for a in A_CUR:
        assert expected_base_name(a) in cur_names
    for name in MANUAL_DERIVATIVES:
        assert name in cur_names, "AC3 named case: manual derivatives present in E2E shape"

    # Outcome 2 (six-glob page): the pinned block + prefixed files.
    text = site.page_text(ENVS)
    lines = text.splitlines()
    block = machine_block(PDA)
    starts = [i for i, l in enumerate(lines) if l == block[0]]
    assert len(starts) == 1 and lines[starts[0] : starts[0] + 3] == block
    env_names = site.bundle_files(ENVS)
    assert sorted(n for n in env_names if fnmatch(n, f"sync-{slug_of(PDA)}-*")) == sorted(
        expected_sync_name(a, PDA) for a in A_PDA
    )

    # §10: state file is valid JSON carrying the ledger.
    state = json.loads((state_dir / STATE_FILE).read_text())
    assert isinstance(state, dict) and state

    # Second run: probe-skipped, changed=no, page bytes stable.
    page_bytes = site.page_bytes(ENVS)
    searches = len(server.hits("POST", "/search/metadata"))
    r2 = run_sync(**kw, output_flag=flag)
    assert r2.rc == 0, r2.output
    s2 = sync_result(r2.out)
    assert s2 and s2["changed"] == "no", s2
    assert flag.read_text().strip() == "unchanged", flag.read_text()
    assert site.page_bytes(ENVS) == page_bytes
    assert len(server.hits("POST", "/search/metadata")) == searches


def test_hugo_semantics_contract_on_post_state(site, make_fake_immich, run_sync, state_dir):
    """'Hugo-independent render contract assertions' (t13): replicate
    .Resources.Match + Name-sort over the final bundle listing — the machine
    glob resolves to exactly the two prefixed files (newest first under the
    block's sort=desc), and the no-glob page's descending Name order puts
    the newest derivative ahead of every authored date-name.
    Reference semantics: RESEARCH-curatedforest-repo.md [8]."""
    server, al = _site_and_server(site, make_fake_immich)
    r1 = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert r1.rc == 0, r1.output

    env_images = [n for n in site.bundle_files(ENVS) if n.endswith(".jpg")]
    block_set = [n for n in env_images if fnmatch(n, f"sync-{slug_of(PDA)}-*")]
    assert set(block_set) == {expected_sync_name(a, PDA) for a in A_PDA}, block_set
    assert sorted(block_set, reverse=True)[0] == expected_sync_name(A_PDA[1], PDA)  # 2026-01-02

    cur_images = sorted((n for n in site.bundle_files(CURRENT) if n.endswith(".jpg")), reverse=True)
    assert cur_images[0] == expected_base_name(A_CUR[2]), cur_images


def test_pr_step_stubbed_at_git_boundary(
    site, tmp_path, make_fake_immich, make_fake_forgejo, run_sync, run_publish, state_dir
):
    """'PR step stubbed at the git boundary': sync into a seeded repo,
    publish once against the fake Forgejo — the whole change set lands in
    one branch commit behind exactly ONE PR, printing PR_URL=."""
    origin = tmp_path / "origin.git"
    server, al = _site_and_server(site, make_fake_immich, git_repo=True, tmp_origin=origin)
    r1 = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert r1.rc == 0, r1.output
    forgejo = make_fake_forgejo(prs=[])
    res = run_publish(
        site_dir=site.root,
        forgejo_url=forgejo.base_url,
        repo=REPO,
        pr_title="Immich sync",
        pr_body="E2E batch",
    )
    assert res.rc == 0, res.output
    assert len(forgejo.created) == 1, "single-PR invariant"
    assert forgejo.created[0]["body"].get("head") == "immich-sync"
    assert git(origin, "rev-parse", "immich-sync").strip() == git(
        site.root, "rev-parse", "immich-sync"
    ).strip(), "publish did not push the branch to origin"
    changed = git(site.root, "show", "--name-only", "--format=", "immich-sync").split()
    assert changed and all(c.startswith("content/") for c in changed), changed
    jpgs = [c for c in changed if c.endswith(".jpg")]
    assert len(jpgs) == 5, jpgs
    assert "PR_URL=" in res.out, res.out
