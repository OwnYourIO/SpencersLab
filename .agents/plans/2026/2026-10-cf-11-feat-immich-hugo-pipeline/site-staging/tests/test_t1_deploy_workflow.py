"""t1 (C06 Tests): .forgejo/workflows/deploy.yml — the delivery contract the
plan locked (merge->main = curatedforest.com prod; PR->main =
curatedforest.farm, last-PR-wins via concurrency; CLI deploy, no --build,
no auto-merge; C03's cf-host label). C06 AC2."""

import re

import pytest
from conftest import DEPLOY, all_run_text, load_yaml_text, read_text, workflow_job


@pytest.fixture(scope="module")
def deploy():
    return load_yaml_text(read_text(DEPLOY, "t1"))


def test_triggers(deploy):
    on = deploy["on"]
    assert "push" in on and "pull_request" in on, sorted(on)
    assert on["push"]["branches"] == ["main"], on["push"]
    pr = on["pull_request"]
    assert pr["branches"] == ["main"], pr
    assert set(pr.get("types") or []) == {"opened", "synchronize", "reopened"}, pr


def test_concurrency_last_pr_wins(deploy):
    c = deploy["concurrency"]
    # group keeps ONE farm slot per event class; cancel-in-progress false so
    # queued runs finish in order -> the LAST PR wins (locked direction 3).
    assert c.get("group") == "${{ github.event_name }}-deploy", c
    assert c.get("cancel-in-progress") is False, c


def test_job_shape(deploy):
    job = workflow_job(deploy)
    assert job.get("runs-on") == "cf-host", job.get("runs-on")
    assert job.get("timeout-minutes") == 30


def test_checkout_full_history_and_lfs(deploy):
    job = workflow_job(deploy)
    co = [s for s in job.get("steps") or [] if "checkout" in str((s.get("uses") or ""))]
    assert co, "no actions/checkout step"
    with_ = co[0].get("with") or {}
    assert str(with_.get("fetch-depth")) == "0", with_
    assert with_.get("lfs") is True, with_


def test_build_and_deploy_commands(deploy):
    job = workflow_job(deploy)
    runs = all_run_text(job)
    assert re.search(r"hugo --gc --minify -b https://curatedforest\.com\b", runs), runs
    assert re.search(r"hugo -D --gc --minify -b https://curatedforest\.farm\b", runs), runs
    assert re.search(r"netlify deploy --prod --no-build --dir public --site (\$NETLIFY_SITE_ID|\$\{NETLIFY_SITE_ID\})\b", runs), runs
    assert re.search(r"--site (\$NETLIFY_SITE_ID_FARM|\$\{NETLIFY_SITE_ID_FARM\})\b", runs), runs
    assert "--build" not in runs.replace("--no-build", ""), "a netlify --build flag appears — deploys are --no-build (P7)"
    assert "auto-merge" not in runs.lower()


def test_drafts_flag_only_on_farm_leg(deploy):
    """The -D split is what makes the farm a review surface and prod the
    merged-into one: every hugo step must pair -D with the .farm base URL
    and never with .com."""
    for s in workflow_job(deploy).get("steps") or []:
        run = str(s.get("run") or "")
        if "hugo" not in run:
            continue
        if re.search(r"(^|\s)-D(\s|$)", run):
            assert "curatedforest.farm" in run, f"-D on a non-farm leg: {run}"
        else:
            assert "curatedforest.farm" not in run, f"farm leg build without -D: {run}"


def test_leg_event_gating(deploy):
    """No main writes from PR runs and no farm build on pushes: each site
    leg's step must be conditioned on its event class (the contract branches
    on push->main vs PR)."""
    steps = workflow_job(deploy).get("steps") or []
    for s in steps:
        run = str(s.get("run") or "")
        cond = str(s.get("if") or "")
        if "curatedforest.com" in run and "--site" in run:
            assert re.search(r"(github\.event_name.*push|refs/heads/main)", cond), \
                f"prod deploy step without push/main gating if: {s}"
        if "curatedforest.farm" in run and "--site" in run:
            assert "pull_request" in cond, f"farm deploy step without PR gating if: {s}"


def test_env_secret_refs_and_cache_dir(deploy):
    job = workflow_job(deploy)
    envs = dict((job.get("env") or {}))
    for s in job.get("steps") or []:
        envs.update(s.get("env") or {})
    envs = {str(k): str(v) for k, v in envs.items()}
    assert envs.get("NETLIFY_AUTH_TOKEN") == "${{ secrets.NETLIFY_AUTH_TOKEN }}", envs
    assert envs.get("HUGO_CACHEDIR") == "/data/hugo-cache", envs
    for site_id in ("NETLIFY_SITE_ID", "NETLIFY_SITE_ID_FARM"):
        assert site_id in envs and re.match(r"^\$\{\{ secrets\." + site_id + r" \}\}$", envs[site_id]), envs


def test_no_literal_secrets(deploy):
    """Secret REFERENCES by name only (AC2): every ${{ }} expression in the
    workflow is a secrets.<allowed> or github.* context reference — nothing
    else can ride in."""
    text = read_text(DEPLOY, "t1")
    for expr in re.findall(r"\$\{\{([^}]*)\}\}", text):
        e = expr.strip()
        ok = (
            re.fullmatch(r"(secrets\.(%s))" % "|".join(
                ["IMMICH_API_KEY", "FORGEJO_SYNC_PAT", "NETLIFY_AUTH_TOKEN",
                 "NETLIFY_SITE_ID", "NETLIFY_SITE_ID_FARM"]), e)
            or e.startswith("github.")
            or e.startswith("inputs.")
            or e.startswith("steps.")
            or e.startswith("needs.")
            or e.startswith("hashFiles(")
        )
        assert ok, f"unapproved expression context: ${{{{{expr}}}}}"
