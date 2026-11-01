"""t11 (C01 Tests): immich-hugo-publish — the single-PR mechanics (§
"immich-hugo-publish unchanged"). Force-push on the bot-owned branch is the
documented answer-4 exemption; the fake Forgejo + a bare local origin prove
the wire and git effects, not the code path. C01 AC1."""

import pytest

from conftest import (
    FAKE_FORGEJO_HEADER,
    album_dto,
    expected_base_name,
    git,
    init_git_repo,
    load_allowlist_text,
    make_asset,
)

PAGE = "plants/aeroponics/current-grows"
ALBUM = "Aeroponics Current"
A1 = make_asset("a1", "IMG_1.JPG", bytes(range(16)), "2026-03-14T09:26:53+00:00", ["al-a"])
A2 = make_asset("a2", "IMG_2.JPG", bytes(range(16, 32)), "2026-03-15T10:00:00+00:00", ["al-a"])
REPO = "CuratedForest/CuratedForest.com"


@pytest.fixture()
def git_site(site, tmp_path):
    """The sync-PR surface needs a real git repo with a pushable origin."""
    site.no_glob_page(PAGE)
    site.site_chrome()
    al = site.root / "sync-albums.yaml"
    al.write_text(load_allowlist_text([{"name": ALBUM, "page": PAGE}]))
    origin = init_git_repo(site, tmp_path / "origin.git")
    site.origin = origin
    return site


def _publish(run_publish, git_site, forgejo, branch="immich-sync", body="sync body", summary=None):
    return run_publish(
        site_dir=git_site.root,
        forgejo_url=forgejo.base_url,
        repo=REPO,
        branch=branch,
        pr_title="Immich sync",
        pr_body=body,
        summary=summary,
    )


def _sync_write(site, server, al, run_sync, state_dir):
    res = run_sync(
        immich_url=server.base_url, site_dir=site.root, state_dir=state_dir, albums_file=al
    )
    assert res.rc == 0, res.output
    return res


@pytest.fixture()
def synced_server(site, state_dir, make_fake_immich, run_sync, git_site):
    al = git_site.root / "sync-albums.yaml"
    server = make_fake_immich([album_dto("al-a", ALBUM, [A1])])
    _sync_write(git_site, server, al, run_sync, state_dir)
    return server, al


def test_first_publish_resets_branch_commits_pushes_and_opens_pr(
    git_site, synced_server, make_fake_forgejo, run_publish, state_dir, git_identity_env
):
    """§publish: checkout -B → git add content/ → commit → push -f → create
    PR head=<branch>; prints PR_URL=. Branch reset effect: the immich-sync
    branch carries exactly the sync commit on top of main."""
    server, al = synced_server
    forgejo = make_fake_forgejo(prs=[])
    res = _publish(run_publish, git_site, forgejo, body="hello from sync")
    assert res.rc == 0, res.output

    branch = git_site.root
    local_sha = git(branch, "rev-parse", "immich-sync").strip()
    assert git(git_site.origin, "rev-parse", "immich-sync").strip() == local_sha, \
        "push did not update origin"
    # One commit on the branch atop main's seed commit.
    parents = git(branch, "rev-list", "--count", "immich-sync").strip()
    main_count = git(branch, "rev-list", "--count", "main").strip()
    assert int(parents) == int(main_count) + 1, (parents, main_count)
    changed = git(branch, "show", "--name-only", "--format=", "immich-sync").split()
    assert all(f.startswith("content/") for f in changed), changed
    assert expected_base_name(A1) in " ".join(changed)

    assert len(forgejo.created) == 1, f"expected one PR create, saw {len(forgejo.created)}"
    posted = forgejo.created[0]["body"]
    assert posted.get("head") == "immich-sync", posted
    assert "hello from sync" in (posted.get("body") or ""), posted
    assert "PR_URL=" in res.out, res.out

    author = git(branch, "log", "-1", "--format=%an <%ae>", "immich-sync").strip()
    assert author == f"{git_identity_env['GIT_IDENTITY_NAME']} <{git_identity_env['GIT_IDENTITY_EMAIL']}>", author

    api = forgejo.pulls_hits()
    assert api and all(r.headers.get("Authorization") == f"token {FAKE_FORGEJO_HEADER}" for r in api)


def test_second_publish_updates_body_single_pr_invariant(
    git_site, synced_server, make_fake_forgejo, run_publish, state_dir, make_fake_immich, run_sync
):
    """§publish: open PR with head exists → UPDATE body, never a second PR;
    the branch force-reset picks up the new sync commit (answer 4 exemption
    + P6 ephemeral branch)."""
    server, al = synced_server
    forgejo = make_fake_forgejo(prs=[])
    r1 = _publish(run_publish, git_site, forgejo)
    assert r1.rc == 0, r1.output

    # Second batch of changes: new asset, re-sync, re-publish.
    server.albums[0]["_assets"].append(A2)
    server.last_modified["al-a"] = "2026-06-01T00:00:00.000Z"
    _sync_write(git_site, server, al, run_sync, state_dir)
    r2 = _publish(run_publish, git_site, forgejo, body="second body")
    assert r2.rc == 0, r2.output

    assert len(forgejo.created) == 1, "single-PR invariant broken"
    assert len(forgejo.updated) >= 1, "existing PR body was not updated"
    assert "second body" in (forgejo.prs[0]["body"] or "")
    assert git(git_site.origin, "rev-parse", "immich-sync").strip() == git(
        git_site.root, "rev-parse", "immich-sync"
    ).strip(), "force-push did not update origin after the branch reset"


def test_nothing_staged_exits_unchanged_without_push_or_pr(
    git_site, synced_server, make_fake_forgejo, run_publish
):
    """§publish: after a successful publish, a second run with nothing new
    staged must not push and must not touch the API (§ 'nothing staged →
    exit unchanged, no push')."""
    server, al = synced_server
    forgejo = make_fake_forgejo(prs=[])
    r1 = _publish(run_publish, git_site, forgejo)
    assert r1.rc == 0, r1.output
    api_hits = len(forgejo.pulls_hits())
    before = git(git_site.origin, "rev-parse", "immich-sync").strip()

    r2 = _publish(run_publish, git_site, forgejo)
    assert len(forgejo.pulls_hits()) == api_hits, "API chatter on a no-op run"
    assert git(git_site.origin, "rev-parse", "immich-sync").strip() == before, \
        "no-op run still pushed"
    assert "unchanged" in (r2.out + r2.err).lower(), (r2.out, r2.err)
