# cf-143 C02 — charts/radiance chart-metadata + CI-workflow contract
# (chunks/C02.md Tests bullet 3; AC1/AC5/AC6). Chart floors: brand-new chart
# entry law (version 1.0.0 — the sanctioned new-chart exception; release.yaml
# owns every later bump), appVersion "1.17.0" (the ENGINE version —
# stilldeadcode/radiance, NOT the vllm-radiance fork's numbering), exactly
# one dep app-template 5.0.1 (charts/vllm idiom), Chart.lock committed +
# vendored tgz parity with the vllm contract leg. The CI workflow is the
# clone-of-idiom per C02 task: triggers + dep-update + pytest + lint + the
# TWO render legs, the service extraction hardened `d.get('radiance') or {}`
# from birth (AC6: the leg works BEFORE and AFTER C04's service block).
#
# Red state at handoff (designed): every leg red until C02 lands (missing
# files name C02 — pure reads, no skip gate; only the two helm-run legs
# carry the loud binary skip).

from __future__ import annotations

import subprocess

import pytest
import yaml

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)

CHART_DIR = R.CHART_DIR


# --- AC1 (lint leg) + floors ----------------------------------------------------


@helm_skip
def test_ac1_helm_lint_passes():
    out = subprocess.run(["helm", "lint", str(CHART_DIR)], capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr


def test_ac5_chart_metadata_floors():
    path = CHART_DIR / "Chart.yaml"
    assert path.is_file(), "C02: charts/radiance/Chart.yaml missing — the chart is not implemented"
    meta = yaml.safe_load(path.read_text())
    assert meta.get("name") == "radiance", f"Chart.yaml name is {meta.get('name')!r}, want radiance"
    # version 1.0.0 exactly: brand-new chart (plan DECISIONS 'Repo version law' —
    # the only sanctioned 1.0.0 of this ticket; no hand-bumps, release.yaml owns
    # everything after).
    assert str(meta.get("version")) == "1.0.0", (
        f"C02 AC5: Chart.yaml version is {meta.get('version')!r}, want 1.0.0 (new-chart rule)"
    )
    assert str(meta.get("appVersion")) == R.IMAGE_TAG, (
        f"C02 AC5: appVersion is {meta.get('appVersion')!r}, want {R.IMAGE_TAG} — the radiance "
        "ENGINE version (RESEARCH RQ0), not any vllm-radiance fork number"
    )
    deps = meta.get("dependencies") or []
    assert deps == [{"name": "app-template", "version": "5.0.1",
                     "repository": "https://bjw-s-labs.github.io/helm-charts/"}], (
        "C02: Chart.yaml dependencies must be EXACTLY app-template 5.0.1 on the sibling "
        f"repository form (charts/vllm idiom); deps: {deps}"
    )


def test_ac1_chart_lock_and_vendored_dependency():
    """vendored-tgz absence parity with the charts/vllm contract leg: lock
    pins exactly app-template 5.0.1, its tgz is present after the dependency
    update, and no stale common-*.tgz exists."""
    lock = CHART_DIR / "Chart.lock"
    assert lock.is_file(), "C02 AC1: Chart.lock missing (helm dependency update output, committed)"
    deps = yaml.safe_load(lock.read_text()).get("dependencies", [])
    assert len(deps) == 1 and deps[0].get("name") == "app-template" and str(deps[0].get("version")) == "5.0.1", (
        f"C02: Chart.lock must pin EXACTLY app-template 5.0.1, got {deps}"
    )
    assert list(CHART_DIR.glob("charts/app-template-5.0.1.tgz")), (
        "C02: the vendored charts/app-template-5.0.1.tgz is missing (run helm dependency "
        "update charts/radiance; the tgz dir stays gitignored, Chart.lock is the committed artifact)"
    )
    assert not list(CHART_DIR.glob("charts/common-*.tgz")), (
        "C02: a vendored charts/common-*.tgz exists — the app-template-bundles-common idiom "
        "means exactly one dep (vllm parity, TEST-FAULTY law)"
    )


# --- scaffold files ---------------------------------------------------------------


def test_scaffold_notes_present():
    assert (CHART_DIR / "templates" / "NOTES.txt").is_file(), (
        "C02: templates/NOTES.txt missing — the peer-URL surface C04 consumes"
    )


def test_no_secret_templates_anywhere():
    """D8: keyless + ungated packs => no secret surface — not even a guarded
    template (the strata secret-chain precedent: it was DELETED, not
    switched off)."""
    tdir = CHART_DIR / "templates"
    assert tdir.is_dir(), "C02: charts/radiance/templates missing"
    secrets = [p.name for p in tdir.iterdir() if "secret" in p.name.lower()]
    assert not secrets, f"C02/D8: secret templates present: {secrets}"
    text = "\n".join(p.read_text(errors="replace") for p in tdir.iterdir() if p.is_file())
    for token in ("ExternalSecret", "bitwarden", "secretKeyRef"):
        assert token not in text, f"C02/D8: templates reference {token} — no secret chain on this lane"


# --- AC5/AC6: the CI workflow ------------------------------------------------------


def test_ac6_workflow_exists_parses_and_triggers():
    assert R.WORKFLOW.is_file(), "C02 AC6: .github/workflows/radiance-render-tests.yaml missing"
    wf = yaml.safe_load(R.WORKFLOW.read_text())
    on = wf.get("on", wf.get(True))  # YAML 1.1 parses bare `on:` as True
    assert isinstance(on, dict), "C02 AC6: the workflow has no on: trigger block"
    want_paths = {"charts/radiance/**", "services/gpu-ai/prod/values.yaml",
                  ".github/workflows/radiance-render-tests.yaml"}
    for kind in ("push", "pull_request"):
        paths = set((on.get(kind) or {}).get("paths") or [])
        assert paths == want_paths, (
            f"C02 AC6: the {kind} trigger paths must be exactly {sorted(want_paths)} (the "
            f"vllm-workflow clone idiom minus the container leg), got {sorted(paths)}"
        )
    runs = []

    def walk(node):
        if isinstance(node, dict):
            if isinstance(node.get("run"), str):
                runs.append(node["run"])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(wf)
    joined = "\n".join(runs)
    for ladder in ("helm dependency update charts/radiance", "pytest charts/radiance/tests",
                   "helm lint charts/radiance"):
        assert ladder in joined, f"C02 AC6: the CI ladder lacks '{ladder}'"
    template_steps = [r for r in runs if "helm template" in r and "charts/radiance" in r]
    assert len([r for r in template_steps]) >= 2, (
        "C02 AC6: the workflow needs BOTH render legs (chart defaults + the service-subtree "
        f"overlay), got {len(template_steps)}"
    )
    assert "d.get('radiance') or {}" in joined, (
        "C02 AC6: the service extraction must be the hardened d.get('radiance') or {} form "
        "FROM BIRTH — the C01 lesson (gotcha 14): the leg must work before AND after C04's "
        "block lands, and after any later key cleanup"
    )


def test_ac6_extraction_leg_runs_against_current_service_values():
    """AC6 executable half (offline, no helm): the extraction expression from
    the workflow, run against the live service values, must yield a dict in
    BOTH wave states — {} pre-C04, the subtree after."""
    assert R.WORKFLOW.is_file(), "C02 AC6: workflow missing (see above)"
    doc = yaml.safe_load(R.SERVICE_VALUES.read_text())
    extracted = doc.get("radiance") or {}
    assert isinstance(extracted, dict), (
        f"C04 AC6: the radiance service extraction yields {type(extracted).__name__}, want a dict"
    )


# --- NOTES surface (C02 task; the peer-URL law lives here for C04) ----------------


def test_notes_carries_the_peer_url_shape_without_v1():
    notes = (CHART_DIR / "templates" / "NOTES.txt")
    assert notes.is_file(), "C02: templates/NOTES.txt missing"
    text = notes.read_text()
    assert "svc.cluster.local:8000" in text, (
        "C02 NOTES: the peer URL surface (…default.svc.cluster.local:8000) is missing — "
        "C04 consumes exactly this string"
    )
    url_lines = [ln.strip() for ln in text.splitlines() if "svc.cluster.local" in ln]
    assert url_lines and all("/v1" not in ln for ln in url_lines), (
        f"C02 NOTES: a /v1 suffix crept into the peer URL lines {url_lines} — request paths "
        "append verbatim (the strata peer law)"
    )
