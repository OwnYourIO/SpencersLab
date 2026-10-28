# r2 Q-C machine pins — the ruling that reshaped run 2 was "release.yaml gets
# NO edits and the standalone chart ceases to exist as a top-level chart dir";
# these guards make the FIRST half mechanical (the second half lives in
# test_strata_wiring.py). The poison the ruling dodged: release.yaml's
# `Add repositories` awk loop mis-splits empty repo fields, so ANY declared
# subchart dependency in ANY chart breaks every future release job (run-2
# FRICTION + DECISIONS 2026-10-28 re-weigh).
#
# Green TODAY (nothing touches these files yet); a red names the chunk whose
# edit violated the ruling — dev may not "fix" these by editing the guard.

from __future__ import annotations

import subprocess

import pytest
import yaml

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)


def test_c01_release_workflow_carries_no_strata_reference():
    """The Q-C constraint: .github/workflows/release.yaml stays pristine —
    no matrix exclusion, no file:// guard, nothing strata-shaped. Its generic
    charts/** globs are not references."""
    text = S.read(S.RELEASE_WORKFLOW, "untouched-by-design (Q-C ruling)")
    assert "strata" not in text.lower(), (
        "release.yaml mentions strata — the Q-C ruling forbids workflow edits on this ticket"
    )


def test_c01_gitignore_untouched_by_strata():
    text = S.read(S.GITIGNORE, "untouched-by-design (Q-C ruling)")
    assert "strata" not in text.lower(), ".gitignore gained a strata entry — Q-C forbids it"


def test_c01_parent_chart_yaml_declares_only_app_template():
    """A declared subchart (file:// or empty-repo) would poison every release
    job (DECISIONS re-weigh variants 1b/1c) — Chart.yaml must stay exactly
    one dependency deep."""
    doc = yaml.safe_load(S.read(S.CHART_DIR / "Chart.yaml", "parent chart metadata stays pristine"))
    deps = {d.get("name") for d in (doc.get("dependencies") or [])}
    assert deps == {"app-template"}, f"Chart.yaml dependencies grew: {deps} — Q-C rules out subcharting"


def test_c01_chart_lock_has_no_strata_entry():
    lock = S.CHART_DIR / "Chart.lock"
    if not lock.is_file():
        pytest.skip("no Chart.lock in this tree state")
    doc = yaml.safe_load(lock.read_text())
    names = {d.get("name") for d in (doc.get("dependencies") or [])}
    assert "strata" not in names, f"Chart.lock gained a strata dependency: {names} — lock churn is Q-C-forbidden"


@helm
def test_c01_helm_dependency_list_never_sees_strata():
    """The release.yaml awk loop consumes exactly this output; an extra line
    is the reproduced poison shape. app-template must remain the ONLY entry."""
    out = subprocess.run(["helm", "dependency", "list", str(S.CHART_DIR)],
                         capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stderr
    names = {ln.split()[0] for ln in out.stdout.splitlines()[1:] if ln.strip()}
    assert names == {"app-template"}, (
        f"helm dependency list emits {sorted(names)} — every future release job runs its "
        "repository loop over exactly this shape (Q-C ruling; run-2 FRICTION)"
    )


def test_c01_no_secret_template_in_the_parent():
    """C-A deleted secret-strata.yaml at the standalone chart; it must NOT be
    moved into the parent (the task explicitly says the file stops existing
    at the parent too)."""
    assert not (S.STRATA_TEMPLATES_DIR / "secret-strata.yaml").exists(), (
        "secret-strata.yaml appeared under charts/llama-swap/templates — the keyless "
        "ruling (C-A) deletes the ExternalSecret, it does not relocate it"
    )


def test_c01_parent_values_bitwardenids_keeps_only_hf_token():
    """The parent's own secret concept is untouched; the ONLY guard against
    re-introducing the strata sentinel chain at the parent."""
    doc = yaml.safe_load(S.read(S.CHART_DIR / "values.yaml", "parent chart values"))
    bids = doc.get("bitwardenIds") or {}
    assert not [k for k in bids if "strata" in str(k)], (
        f"parent bitwardenIds grew strata keys: {sorted(bids)} — C-A deleted the chain"
    )
