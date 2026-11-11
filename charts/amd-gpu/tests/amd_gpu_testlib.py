# Shared helpers for the charts/amd-gpu vendored-chart render contract
# (2026-11-cf-143-feat-radiance-replaces-strata, C07; DECISIONS D18/D19).
#
# charts/amd-gpu is a VENDORED copy of upstream chart 0.22.0 (tag
# amd-gpu-helm-0.22.0) + the exact ~10-line args hook — the released chart
# cannot pass `-resource_naming_strategy=product` (no args/command hook;
# upstream PR #122 stale since 2025-04-22). The vendored chart makes the
# node advertise per-device PRODUCT names: the R9700 (7551/C0) lands
# `amd.com/gpu-ai-pro-r9700`, the APU (1586/C1|C3|C6|D1) lands
# `amd.com/gpu-8060s`, and bare `amd.com/gpu` DISAPPEARS (RESEARCH §R6-Q1).
#
# helm_ready is the vllm-law gate: an absent helm binary is a LOUD skip
# naming the PATH export; a missing chart is implementation state and must
# RED naming C07 (the repo mass-skip trap, EXPLORE §4 — never gate the chart
# itself here). Chart-level renders only: the ApplicationSet entry carries no
# top-level `amd-gpu:` values block (plan Q13 best guess — chart values own
# tag+extraArgs), so there is no service-subtree extraction leg here; the
# appset-entry shape is pinned by tests/services/amd-gpu-naming.sh n1.
#
# The EXPECTED-NAMES LEDGER lives as a comment block in charts/amd-gpu/
# values.yaml (7551/C0 -> gpu-ai-pro-r9700; 1586 -> gpu-8060s) — computed
# from the plugin's baked amdgpu.ids by RESEARCH §R6-Q1, recorded there so
# C02's cross-chart name-identity needle and this suite's n4 legs read the
# SAME authority. The fallback trap (unknown sysfs (device,revision) ->
# bare amd.com/gpu) is closed by the C06 runbook step-0 receipts, not here.

from __future__ import annotations

import functools
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

CHART_DIR = Path(__file__).resolve().parent.parent      # charts/amd-gpu
REPO_ROOT = CHART_DIR.parent.parent

# The vendored upstream identity (D19 fork point; RESEARCH §R6-Q2/§R6-Q5).
UPSTREAM_CHART_VERSION = "0.22.0"
UPSTREAM_CHART_TAG = "amd-gpu-helm-0.22.0"
PLUGIN_TAG = "1.31.0.12"
PLUGIN_REPO = "docker.io/rocm/k8s-device-plugin"
PLUGIN_AMD64_DIGEST_PREFIX = "sha256:6437c74f"           # §R6-Q5/§R6-S13 (amd64 manifest)
HELM_INDEX_DIGEST_PREFIX = "791ada88"                   # chart 0.22.0 index digest (D19)

# The image CMD restated in full by the args hook (Dockerfile CMD, §R6-Q2:
# ["./k8s-device-plugin","-logtostderr=true","-stderrthreshold=INFO","-v=5"]).
# Declaring args: DROPS the CMD, so the trio must be restated verbatim;
# -v=5 is runbook-log-bearing (receipt (b) greps the enumeration logs).
CMD_RESTATED = ["-logtostderr=true", "-stderrthreshold=INFO", "-v=5"]
STRATEGY_FLAG = "-resource_naming_strategy=product"

# Names pinned to upstream (Chart.yaml name must stay `amd-gpu`: the vendored
# templates hardcode .Chart.Name, and the Application source-flip repo->
# git-path only lands orphan-free if the rendered objects keep these names).
DS_NAME = "amd-gpu-device-plugin-daemonset"
DS_SELECTOR = {"name": "amd-gpu-dp-ds"}
DS_CONTAINER = "amd-gpu-dp-cntr"

# The expected-names ledger rows the values comment must carry (§R6-Q1).
EXPECTED_NAME_LEDGER = [
    # (pci device id, revision id, resource name WITHOUT the amd.com/ prefix)
    ("7551", "C0", "gpu-ai-pro-r9700"),
    ("1586", None, "gpu-8060s"),   # revisions C1/C3/C6/D1 — one row is enough
]


def helm_ready() -> tuple[bool, str]:
    # Binary check ONLY (the vllm_testlib law): a missing chart/dependency is
    # implementation state — the render legs must RED naming C07, not skip.
    if shutil.which("helm") is None:
        return False, ("helm binary not on PATH (~/.local/bin/helm — export PATH; "
                       "without it the helm-guarded tests skip silently, EXPLORE §4)")
    return True, ""


def chart_values_text() -> str:
    path = CHART_DIR / "values.yaml"
    assert path.is_file(), (
        "C07: charts/amd-gpu/values.yaml missing — the vendored chart is not implemented yet"
    )
    return path.read_text()


def chart_values() -> dict:
    return yaml.safe_load(chart_values_text())


def chart_meta() -> dict:
    path = CHART_DIR / "Chart.yaml"
    assert path.is_file(), "C07: charts/amd-gpu/Chart.yaml missing — the vendored chart is not implemented yet"
    return yaml.safe_load(path.read_text())


@functools.lru_cache(maxsize=None)
def _render_cached(overlay_json: str) -> tuple:
    """(docs, raw stdout) of `helm template amd-gpu charts/amd-gpu` with an
    optional -f overlay (extraArgs experiments)."""
    import json

    cmd = ["helm", "template", "amd-gpu", str(CHART_DIR),
           "--set", "domain=spencerslab.com", "--set", "clusterName=gpu-ai"]
    with tempfile.TemporaryDirectory(prefix="amdgpu-test-") as tmp:
        if overlay_json:
            ov = Path(tmp) / "ov.yaml"
            ov.write_text(json.loads(overlay_json))
            cmd += ["-f", str(ov)]
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if out.returncode != 0:
            raise AssertionError(
                f"C07: helm template charts/amd-gpu failed:\n{out.stderr}"
            )
        docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
        return docs, out.stdout


def render(overlay_yaml: str = "") -> tuple:
    """docs, raw stdout. overlay_yaml (when given) is written as a -f file —
    the values-level experiment surface (e.g. dp.extraArgs: [])."""
    import json

    return _render_cached(json.dumps(overlay_yaml) if overlay_yaml else "")


def daemonset(docs) -> dict:
    dss = [d for d in docs if d.get("kind") == "DaemonSet"]
    assert len(dss) == 1, f"C07: expected exactly one DaemonSet rendered, got {[d['metadata']['name'] for d in dss]}"
    return dss[0]


def dp_container(docs) -> dict:
    spec = daemonset(docs)["spec"]["template"]["spec"]
    ctrs = spec["containers"]
    assert len(ctrs) == 1, f"C07: expected one plugin container, got {[c.get('name') for c in ctrs]}"
    return ctrs[0]
