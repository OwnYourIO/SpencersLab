"""t2 (C06 Tests): .forgejo/workflows/sync.yml — the daily Immich sync.
Contract points: cron 17 5 * * * (answer 7 DAILY, off-the-hour :17),
workflow_dispatch override inputs, checkout lfs:false + git lfs install
--local, the sync step's env block matching the C01 contract key-for-key,
the publish step gated on the changed flag with the PAT secret (P5: a PAT
so the PR event fires the farm deploy), and the N2-c reviewer note
(gallery-call extensions ship in the SAME PR). The chunk's second note pin
— the daily-cadence watchdog as compensating control — was voided with the
C05 drop (owner review 2026-11-06): no schedule watchdog exists, so there
is no comment to pin; coverage is the sync's commits/PRs + Immich
webhooks + run history. C06 AC2/AC3."""

import re

import pytest
from conftest import (
    PUBLISH_ENV_MIN,
    SYNC,
    SYNC_ENV_KEYS,
    env_map,
    load_yaml_text,
    read_text,
    workflow_job,
)


@pytest.fixture(scope="module")
def sync():
    return load_yaml_text(read_text(SYNC, "t2"))


@pytest.fixture(scope="module")
def sync_text():
    return read_text(SYNC, "t2")


def test_triggers_daily_cron_and_dispatch(sync):
    on = sync["on"]
    assert on.get("schedule") == [{"cron": "17 5 * * *"}], on.get("schedule")
    wd = on.get("workflow_dispatch")
    assert wd is not None, "workflow_dispatch missing (manual sync is phase-1)"
    inputs = (wd or {}).get("inputs") or {}
    assert "albums" in inputs and inputs["albums"].get("type") == "string", inputs
    assert inputs["albums"].get("required") in (False, None), inputs
    assert "force" in inputs and inputs["force"].get("type") == "boolean", inputs
    assert inputs["force"].get("default") is False, inputs


def test_concurrency_and_job_shape(sync):
    c = sync["concurrency"]
    assert c.get("group") == "immich-sync", c
    assert c.get("cancel-in-progress") is False, c
    job = workflow_job(sync)
    assert job.get("runs-on") == "cf-host"
    assert job.get("timeout-minutes") == 30


def test_checkout_pointer_only_then_lfs_install(sync):
    """AC: checkout of the default branch with fetch-depth 1 and lfs:false —
    existence checks work on LFS pointers, new files commit through the
    filter; `git lfs install --local` runs first (§2 step 1)."""
    job = workflow_job(sync)
    co = [s for s in job.get("steps") or [] if "checkout" in str(s.get("uses") or "")]
    assert co, "no actions/checkout step"
    with_ = co[0].get("with") or {}
    assert str(with_.get("fetch-depth")) == "1", with_
    assert with_.get("lfs") is False, with_
    runs = "\n".join(str(s.get("run") or "") for s in job.get("steps") or [])
    idx_install = runs.find("git lfs install --local")
    assert idx_install >= 0, "no `git lfs install --local` step"
    idx_sync = runs.find("immich-hugo-sync")
    assert idx_install < idx_sync, "lfs install must precede the sync step"


def _step_containing(sync, needle):
    for s in workflow_job(sync).get("steps") or []:
        if needle in str(s.get("run") or "") or needle in str(s.get("name") or ""):
            return s
    return None


def test_sync_step_env_matches_c01_contract_key_for_key(sync):
    """C06 AC3: the env block IS the C01 contract — same eight keys, no
    extras (drift here silently breaks the baked tool)."""
    step = _step_containing(sync, "immich-hugo-sync")
    assert step, "no step invokes immich-hugo-sync"
    keys = set(env_map(step)) | {k for k in (workflow_job(sync).get("env") or {})}
    missing = SYNC_ENV_KEYS - keys
    assert not missing, f"sync env lost contract keys: {sorted(missing)}"
    assert not (keys - SYNC_ENV_KEYS - {"PATH"}), f"unexpected extra sync env keys: {sorted(keys - SYNC_ENV_KEYS)}"


def test_sync_env_values_pinned(sync):
    step = _step_containing(sync, "immich-hugo-sync")
    job_env = {str(k): str(v) for k, v in (workflow_job(sync).get("env") or {}).items()}
    step_env = env_map(step)
    env = {**job_env, **step_env}
    # IMMICH_URL lives at workflow level (one-line edit; reachability is
    # card #88's open item — the artifact must not hardcode assumptions
    # beyond the BG value).
    assert "IMMICH_URL" in job_env, f"IMMICH_URL is not a workflow-level env: {sorted(job_env)}"
    assert job_env["IMMICH_URL"] == "http://home-immich-server:2283", job_env["IMMICH_URL"]
    assert env["IMMICH_API_KEY"] == "${{ secrets.IMMICH_API_KEY }}", env
    assert "github.workspace" in env["SITE_DIR"], env
    assert env["ALBUMS_FILE"].endswith("sync-albums.yaml") and "github.workspace" in env["ALBUMS_FILE"], env
    assert env["STATE_DIR"] == "/data/state", env
    assert "inputs.albums" in env["ALBUMS"], env
    assert "inputs.force" in env["FORCE"], env
    assert "OUTPUT_FLAG" in env and env["OUTPUT_FLAG"], env


def test_publish_step_gated_and_pat(sync):
    """The publish leg runs only when the flag says changed; it uses
    FORGEJO_SYNC_PAT (NOT FORGEJO_TOKEN — answer 4/P5: the PR event must
    fire the farm deploy), pins BRANCH immich-sync, and the FORGEJO_REPO
    comment carries the org-owner note (answer 6)."""
    job = workflow_job(sync)
    step = _step_containing(sync, "immich-hugo-publish")
    assert step, "no step invokes immich-hugo-publish"
    cond = str(step.get("if") or "")
    assert cond, "publish step is not gated on the changed flag"
    assert "changed" in cond, f"publish gate does not mention the changed flag: {cond}"
    env = env_map(step)
    missing = PUBLISH_ENV_MIN - set(env)
    assert not missing, f"publish env lacks contract keys: {sorted(missing)}"
    assert env["BRANCH"] == "immich-sync", env
    assert env["FORGEJO_PAT"] == "${{ secrets.FORGEJO_SYNC_PAT }}", env
    assert "FORGEJO_TOKEN" not in (job.get("env") or {}), "FORGEJO_TOKEN wired — anti-recursion suppression would kill the farm deploy (P5)"
    text = read_text(SYNC, "t2")
    assert re.search(r"(?i)org", text[text.find("FORGEJO_REPO") - 400 : text.find("FORGEJO_REPO") + 400]), \
        "no org-owner comment around FORGEJO_REPO (answer 6)"


def test_no_changes_fallback(sync):
    """Else branch: log 'no changes' and exit clean (§2 step 4)."""
    runs = "\n".join(str(s.get("run") or "") + " " + str(s.get("name") or "")
                     for s in workflow_job(sync).get("steps") or [])
    assert re.search(r"(?i)no changes", runs), runs


def test_reviewer_notes_present(sync_text):
    """C06 AC3: the N2-c same-PR gallery-extension note is REQUIRED
    reviewer text. The chunk's other note pin (the C05 daily-cadence
    watchdog as compensating control) was voided with C05's drop, owner
    review 2026-11-06 — no schedule watchdog exists, so no watchdog
    comment is pinned: t2's contract is the cron, dispatch inputs, PR
    mechanics and the env surface, not commentary."""
    assert re.search(r"(?i)same (PR|pull request)", sync_text), "no same-PR gallery-extension note"
    assert re.search(r"(?i)gallery", sync_text)


def test_secrets_by_reference_only(sync_text):
    for expr in re.findall(r"\$\{\{([^}]*)\}\}", sync_text):
        e = expr.strip()
        ok = (
            e.startswith("secrets.")
            or e.startswith("github.")
            or e.startswith("inputs.")
            or e.startswith("steps.")
            or e.startswith("outputs.")
        )
        assert ok, f"unapproved expression: ${{{{{expr}}}}}"
    secret_refs = set(re.findall(r"secrets\.([A-Z_]+)", sync_text))
    assert secret_refs <= {"IMMICH_API_KEY", "FORGEJO_SYNC_PAT", "NETLIFY_AUTH_TOKEN",
                          "NETLIFY_SITE_ID", "NETLIFY_SITE_ID_FARM"}, sorted(secret_refs)
