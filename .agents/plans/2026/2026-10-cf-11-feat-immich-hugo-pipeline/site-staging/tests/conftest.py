"""Harness for the C06 site-staging contract (ticket
2026-10-cf-11-feat-immich-hugo-pipeline). Artifacts are the files C06 dev
stages under site-staging/ (workflows, sync-albums.yaml, APPLY-INSTRUCTIONS);
the live CuratedForest.com checkout is READ-ONLY reference material — no
test here may write it (plan Out-of-scope + AC6; test_t5 asserts the guard).

AC trace: t1[C06 AC2 deploy.yml] t2[AC2/AC3 sync.yml vs the C01 contract]
t3[AC4 allowlist schema + N3 grep gate] t4[AC2 secret hygiene]
t5[AC5 render gate].

The structural gates are red-first: a missing artifact fails with its path.
"""

from pathlib import Path

import pytest
import yaml

TESTS_DIR = Path(__file__).resolve().parent
STAGING = TESTS_DIR.parent
DEPLOY = STAGING / ".forgejo" / "workflows" / "deploy.yml"
SYNC = STAGING / ".forgejo" / "workflows" / "sync.yml"
ALLOWLIST = STAGING / "sync-albums.yaml"
APPLY = STAGING / "APPLY-INSTRUCTIONS.md"

# The live site checkout (read-only). Its absence is an environment gap the
# render gate reports as SKIP-BLOCKED (never a fake pass); the structural
# gates do not need it.
LIVE_SITE = Path("/home/coder/CuratedForest.com")
GALLERY_HTML = LIVE_SITE / "layouts" / "_shortcodes" / "gallery.html"

# The C01 sync entry's env surface, key-for-key (chunks/C01.md §env — C06
# AC3 pins the workflow to exactly this set).
SYNC_ENV_KEYS = {
    "IMMICH_URL",
    "IMMICH_API_KEY",
    "SITE_DIR",
    "ALBUMS_FILE",
    "ALBUMS",
    "FORCE",
    "STATE_DIR",
    "OUTPUT_FLAG",
}
PUBLISH_ENV_MIN = {
    "SITE_DIR",
    "BRANCH",
    "FORGEJO_URL",
    "FORGEJO_REPO",
    "FORGEJO_PAT",
    "SUMMARY",
}
SECRET_NAMES = {
    "IMMICH_API_KEY",
    "FORGEJO_SYNC_PAT",
    "NETLIFY_AUTH_TOKEN",
    "NETLIFY_SITE_ID",
    "NETLIFY_SITE_ID_FARM",
}


def load_yaml_text(text):
    """Forgejo/GitHub workflow YAML: PyYAML (YAML 1.1) reads the `on:` key
    as boolean True — normalize back so tests can speak the workflow's own
    vocabulary."""
    doc = yaml.safe_load(text)
    if isinstance(doc, dict) and True in doc:
        doc["on"] = doc.pop(True)
    return doc


def require_artifact(path, leg):
    if not path.exists():
        pytest.fail(
            f"{leg}: {path} does not exist — C06 has not staged it yet. "
            "Intended green condition: the artifact lands per chunks/C06.md."
        )


def read_text(path, leg):
    require_artifact(path, leg)
    return path.read_text()


def staging_artifact_files():
    """Everything dev stages (the gate's scan scope): site-staging minus the
    test suite itself (its banned-term literals must not self-trip the
    grep) and minus pytest runtime droppings (.pytest_cache lands next to
    the invoked root)."""
    skip_top = {"tests", ".pytest_cache"}
    out = []
    for p in sorted(STAGING.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(STAGING)
        if rel.parts[0] in skip_top or "__pycache__" in str(rel):
            continue
        out.append(p)
    return out


def workflow_job(doc):
    jobs = doc.get("jobs") or {}
    assert len(jobs) == 1, f"expected exactly one job, got {sorted(jobs)}"
    return next(iter(jobs.values()))


def step_run(step):
    return str(step.get("run") or "")


def all_run_text(job):
    return "\n".join(step_run(s) for s in job.get("steps") or [])


def env_map(step):
    out = {}
    for k, v in (step.get("env") or {}).items():
        out[str(k)] = str(v)
    return out
