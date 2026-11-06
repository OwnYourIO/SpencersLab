# C02 contract suite (2026/2026-11-cf-105-feat-implement-vllm —
# chunks/C02.md AC1, AC6, AC7 + the serveArgs/monitoring-gate task clauses):
# Chart.yaml metadata on the new-chart rule, the committed dependency lock +
# vendored tgz, the first-build image pin shape, the values-level serveArgs
# D4 recipe, the monitoring-annotations gate (default ON; gate-OFF disables
# the scrape — see test_monitoring_gate_off_disables_scrape), and the
# per-chart CI workflow ladder.
# All tests designed-red at test-write time: charts/vllm does not exist yet.

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest
import yaml

import vllm_testlib as V

# Only the two helm-rendering tests below carry the skip gate; the pure file
# reads are NOT skipped when helm is absent — a missing chart must read as an
# assertion red, not a silent skip (the mass-skip trap of the repo's
# helm-guarded suites).
_helm_ok, _helm_reason = V.helm_ready()
helm_skip = pytest.mark.skipif(not _helm_ok, reason=_helm_reason)

CHART_DIR = V.CHART_DIR


# --- AC1 (lint leg) ------------------------------------------------------------


@helm_skip
def test_ac1_helm_lint_passes():
    out = subprocess.run(["helm", "lint", str(CHART_DIR)],
                         capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr


# --- AC6: chart metadata on the new-chart rule ----------------------------------


def test_ac6_chart_metadata():
    assert (CHART_DIR / "Chart.yaml").is_file(), "C02: charts/vllm/Chart.yaml missing — the chart is not implemented"
    meta = yaml.safe_load((CHART_DIR / "Chart.yaml").read_text())
    assert meta.get("name") == "vllm", f"Chart.yaml name is {meta.get('name')!r}, want vllm"
    # version 1.0.0 exactly: chart-releaser bumps the patch on every merge to
    # main — a new chart never starts on a hand-picked other number.
    assert str(meta.get("version")) == "1.0.0", (
        f"Chart.yaml version is {meta.get('version')!r}, want 1.0.0 (new-chart rule)"
    )
    assert str(meta.get("appVersion")) == "0.33.0", f"appVersion is {meta.get('appVersion')!r}, want 0.33.0"
    # Exactly one dep: app-template bundles the common chart internally (zero
    # k8s objects of its own), so the C07 owner ruling voids C02's two-dep
    # shape — a second entry (common) re-introduces it.
    deps = meta.get("dependencies") or []
    assert deps == [{"name": "app-template",
                     "version": "5.0.1",
                     "repository": "https://bjw-s-labs.github.io/helm-charts/"}], (
        "C07 AC1: Chart.yaml dependencies must be EXACTLY one entry — app-template 5.0.1 on the "
        f"sibling repository form with the trailing slash (charts/llama-swap); deps: {deps}"
    )


def test_ac6_chart_lock_and_vendored_dependency():
    lock = CHART_DIR / "Chart.lock"
    assert lock.is_file(), "C02 AC6: Chart.lock missing (helm dependency update output, committed)"
    # helm writes Chart.lock as YAML, not JSON (v3.16.4 verified 2026-11-05) —
    # a JSON lock can never survive the workflow's `helm dependency update`
    # step, so the criterion parses through yaml (TEST-FAULTY repair).
    deps = yaml.safe_load(lock.read_text()).get("dependencies", [])
    assert len(deps) == 1, (
        "C07 AC1: Chart.lock must pin EXACTLY one dependency — [app-template 5.0.1] (the common "
        f"dep is void under the repo app-template idiom); deps: {deps}"
    )
    assert deps[0].get("name") == "app-template" and str(deps[0].get("version")) == "5.0.1", (
        f"C02 AC6: Chart.lock must pin app-template 5.0.1, got {deps}"
    )
    assert list(CHART_DIR.glob("charts/app-template-5.0.1.tgz")), (
        "C02 AC6: the vendored charts/app-template-5.0.1.tgz is missing (helm dependency update output)"
    )
    assert not list(CHART_DIR.glob("charts/common-*.tgz")), (
        "C07 AC1: a vendored charts/common-*.tgz survived — dropping the common dep must delete the "
        "stale tgz (helm dependency update does it; the tgz dir is gitignored, Chart.lock is the committed artifact)"
    )


def test_ac6_image_pin_is_first_build_shape():
    """ghcr.io/ownyourio/vllm-rocm at tag main + pullPolicy Always + the
    PIN-ME comment (strata first-build pattern): the first :v<run> pin lands
    as the C06 step-10 follow-through, never a hand edit in this chunk."""
    values_path = CHART_DIR / "values.yaml"
    assert values_path.is_file(), "C02: charts/vllm/values.yaml missing"
    values_text = values_path.read_text()

    found = []

    def find_image_nodes(node):
        if isinstance(node, dict):
            if node.get("repository") == "ghcr.io/ownyourio/vllm-rocm":
                found.append(node)
            for v in node.values():
                find_image_nodes(v)
        elif isinstance(node, list):
            for v in node:
                find_image_nodes(v)

    find_image_nodes(V.chart_values())
    assert found, "C02 AC6: no image spec for ghcr.io/ownyourio/vllm-rocm in charts/vllm/values.yaml"
    for node in found:
        assert str(node.get("tag")) == "main", (
            f"C02 AC6: first-build image tag must be main (rolling), got {node.get('tag')!r}"
        )
        assert node.get("pullPolicy") == "Always", (
            f"C02 AC6: pullPolicy Always must sit on the image spec beside the :main pin, got {node.get('pullPolicy')!r}"
        )
    assert re.search(r"PIN-ME", values_text, re.I), (
        "C02 AC6: values.yaml carries no PIN-ME comment — the first :v<run> pin obligation (C06 step 10) is undocumented"
    )


# --- serveArgs values contract ---------------------------------------------------


def test_serveargs_values_carry_the_d4_recipe():
    """The values-level serveArgs list (under the app-template: subtree, the
    C07 idiom location) is what the template renders VERBATIM (C02 task): the
    D4 flags present in the D4 order. The rendered-args equality (order,
    values, --model splice) is asserted at render level in test_render.py."""
    serve = (V.chart_values().get("app-template") or {}).get("serveArgs")
    assert isinstance(serve, list) and serve, (
        "C02: charts/vllm/values.yaml must carry the serveArgs list under the app-template: subtree"
    )
    flags = [a for a in serve if isinstance(a, str) and a.startswith("--")]
    want_flags = [flag for flag, _ in V.D4_RECIPE]
    assert flags == want_flags, (
        f"C02: serveArgs flags diverge from the D4 recipe order\n  got:      {flags}\n  expected: {want_flags}"
    )


# --- monitoring-annotations gate ---------------------------------------------------


def test_monitoring_gate_default_on():
    gate = ((V.chart_values().get("app-template") or {}).get("monitoring") or {}).get("annotations")
    assert gate, (
        "C02: the app-template.monitoring.annotations values key must default ON (D8) — the pod ships the two scrape annotations by default"
    )


@helm_skip
def test_monitoring_gate_off_disables_scrape():
    """Re-expresses the chunk's gate-OFF 'zero k8s.grafana.com/* keys' bar
    (TEST-FAULTY repair, test session 2026-11-04): app-template 5.0.1 tpl's
    the pod annotation map as a whole (common lib pod.metadata.annotations),
    so a values-level gate-OFF keeps the keys with inert values — live-verified
    on the vendored app-template-5.0.1.tgz (scrape renders '' and the key
    survives). Zero keys is mechanically unreachable by any such
    implementation; the functional contract instead is that no k8s.grafana.com/*
    annotation is enabled ('true'), so k8s-monitoring's annotationAutodiscovery
    does not scrape the pod. A key-dropping implementation would pass too —
    the bar checks the property, not the mechanism.

    C07 idiom rework (owner ruling 2026-11-06): the gate key moved one level
    down under app-template:, so the --set path is a layout pin re-pinned
    with the move. The planning probe (2026-11-06, helm v3.16.4) shows the
    OLD top-level path no longer gates: --set monitoring.annotations=false
    still renders k8s.grafana.com/scrape 'true' and metrics.portNumber
    '8000' — a test left on the old path would false-green, so it must read
    the new path to be a real gate check."""
    docs, _ = V.render(release="vllm", service=False, extra_set="--set app-template.monitoring.annotations=false")
    grafana = V.grafana_annotations(V.deployment(docs))
    assert "true" not in grafana.values(), (
        f"C02: with app-template.monitoring.annotations=false no k8s.grafana.com/* annotation "
        f"may be enabled (value 'true') — the gate must disable the scrape, got {grafana!r}"
    )


# --- scaffold files -----------------------------------------------------------------


def test_scaffold_common_loader_and_notes():
    """C07 flip of the C02 loader bar (owner ruling 2026-11-06): the repo
    app-template idiom renders the workload from the chart's own
    app-template: values — no parent-side loader file, no second dep, no
    bjw-s.common.* invocation in any parent-context template (the vendored
    app-template tgz bundles common internally; it generates no k8s objects
    of its own). NOTES.txt stays: the install-hint surface is chart-owned."""
    assert not (CHART_DIR / "templates" / "common.yaml").is_file(), (
        "C07 AC1: templates/common.yaml (the one-line bjw-s loader include) must be ABSENT — "
        "the repo app-template idiom renders without a parent-side loader"
    )
    # AC1's zero-common grep, text-only: exclude tests/ (this file carries the
    # needle literal in this absence-assert) and the gitignored vendored
    # charts/ tgz dir. Fixed-string needle — every real invocation starts with
    # bjw-s.common.*, and the regex-dot form of the needle would also match
    # prose like 'bjw-s common'.
    for path in sorted(CHART_DIR.rglob("*")):
        if not path.is_file():
            continue
        if path.relative_to(CHART_DIR).parts[0] in ("tests", "charts"):
            continue
        assert "bjw-s.common" not in path.read_text(), (
            f"C07 AC1: {path.relative_to(CHART_DIR)} still invokes the common chart "
            "(bjw-s.common.*) — the zero-common surface allows no parent-template include"
        )
    assert (CHART_DIR / "templates" / "NOTES.txt").is_file(), "C02: templates/NOTES.txt missing"


# --- AC7: the per-chart CI workflow ---------------------------------------------------


def test_ac7_workflow_exists_and_parses():
    assert V.WORKFLOW.is_file(), "C02 AC7: .github/workflows/vllm-render-tests.yaml missing"
    wf = yaml.safe_load(V.WORKFLOW.read_text())
    assert isinstance(wf, dict), "C02 AC7: the workflow YAML does not parse to a mapping"
    # YAML 1.1 parses the bare `on:` key as boolean True; accept both.
    on = wf.get("on", wf.get(True))
    assert isinstance(on, dict), "C02 AC7: the workflow has no on: trigger block"
    want_paths = {
        "charts/vllm/**",
        "containers/vllm-rocm/**",
        "services/gpu-ai/prod/values.yaml",
        ".github/workflows/vllm-render-tests.yaml",
    }
    for kind in ("push", "pull_request"):
        paths = set((on.get(kind) or {}).get("paths") or [])
        missing = want_paths - paths
        assert not missing, f"C02 AC7: {kind} trigger missing paths {sorted(missing)}"

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
    for ladder in ("helm dependency update charts/vllm", "pytest charts/vllm/tests", "helm lint charts/vllm"):
        assert ladder in joined, f"C02 AC7: the CI step ladder lacks '{ladder}'"
    template_steps = [r for r in runs if "helm template" in r and "charts/vllm" in r]
    assert template_steps, "C02 AC7: no helm template step over charts/vllm"
    assert any("-f" in r for r in template_steps), (
        "C02 AC7: the service-level -f render (the plan Commands pattern) is missing from the workflow"
    )
