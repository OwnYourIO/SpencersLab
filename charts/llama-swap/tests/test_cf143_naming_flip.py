# cf-143 C07 — the llama-swap same-wave GPU-name flip (chunks/C07.md Tests
# bullet 4, "charts/llama-swap render-suite re-pin: wherever the pod
# resources are asserted, the needle flips — test property; dev conforms
# values, never the reverse").
#
# The owner Q9 ruling's second half: the APU stays assigned to the llama-swap
# pod BY NAME. charts/llama-swap/values.yaml:1045's `amd.com/gpu: 1` limit
# flips to `amd.com/gpu-8060s: 1` — a NAMED GUARANTEE replacing what today is
# an accident of nodeId-order allocation. After the strategy flip bare
# `amd.com/gpu` no longer exists on the node, so a stray live bare claim
# anywhere in the chart would be Pending-forever (loud by design; the sweep
# needle below keeps the chart itself clean).
#
# Pre-pin state (this session, before C07 dev): designed-RED — the values line
# still carries the bare claim. The golden ConfigMap is UNAFFECTED (pod
# resources are not in the ConfigMap — chunks/C07.md files-in-scope).
# Strata legs: its container must claim NOTHING from the plugin accounting
# (privileged hostPath shape, R6-Q4-3) — that pin is the existing
# test_strata_render bar and stays green throughout.
#
# Run with the suite (per-directory): python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import pytest

import llama_swap_testlib as L

_ok, _reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_reason)

APU_CLAIM = "amd.com/gpu-8060s"
BARE_CLAIM = "amd.com/gpu"
VALUES = L.CHART_DIR / "values.yaml"


def _main_container_docs():
    docs = L.render_docs("gpu-ai")
    for doc in docs:
        if doc.get("kind") == "Deployment" and doc.get("metadata", {}).get("name") == "llama-swap":
            for c in doc["spec"]["template"]["spec"]["containers"]:
                if c.get("name") == "main":
                    return c
    raise AssertionError("C07: no llama-swap main container rendered (render-shape drift, not the flip)")


# --- the flip needle ------------------------------------------------------------


def test_main_container_claims_named_apu_pool():
    """C07 AC3: the outer pod's GPU limit is exactly the APU product pool —
    requests auto-mirror for extended resources, so requests stay cpu/memory
    only (the live pod shape, R6-S12)."""
    ctr = _main_container_docs()
    limits = ctr.get("limits") or {}
    assert limits.get(APU_CLAIM) == 1, (
        f"C07: main container limits are {limits} — the flip line is `amd.com/gpu-8060s: 1` "
        "(the named guarantee replacing the nodeId-order accident, owner Q9)"
    )
    assert BARE_CLAIM not in limits and BARE_CLAIM not in (ctr.get("requests") or {}), (
        f"C07: the main container still claims bare {BARE_CLAIM} — after the vendored "
        "plugin lands, that name does not exist on the node: Pending-forever"
    )
    req = ctr.get("requests") or {}
    assert APU_CLAIM not in req, (
        f"C07: requests names {APU_CLAIM} explicitly — the chart ships requests cpu/memory "
        "only and kubelet auto-mirrors extended-resource requests (live-pod shape, R6-S12)"
    )


def test_values_yaml_has_no_live_bare_claim():
    """C07 AC3 text leg: `amd.com/gpu:` survives in charts/llama-swap/values.yaml
    only inside comments (the realized-history prose), never as a live
    requests/limits key."""
    live = []
    for i, ln in enumerate(VALUES.read_text().splitlines(), 1):
        if ln.lstrip().startswith("#"):
            continue
        if f"{BARE_CLAIM}:" in ln and ("limits" in ln or "requests" in ln or ln.strip().startswith(BARE_CLAIM)):
            live.append(f"{i}: {ln.strip()[:100]}")
    assert not live, (
        f"C07 AC3: live bare-claim lines in charts/llama-swap/values.yaml: {live} — line "
        "1045 flips to amd.com/gpu-8060s in the SAME commit as the vendored chart (same-wave law)"
    )
    text = VALUES.read_text()
    assert f"{APU_CLAIM}: 1" in text, (
        "C07 AC3: the flipped claim line amd.com/gpu-8060s: 1 is absent from values.yaml"
    )


def test_realized_prose_replaces_the_fallback_comment():
    """C07: the comment 1331-1338 ("...fallback once a naming-capable plugin
    exists: amd.com/gpu + IPC_LOCK/SYS_RESOURCE + non-privileged") retires as
    REALIZED prose — the named pools exist since cf-143 C07. The word
    'fallback' in that specific forward-looking spelling must be gone from the
    strata/llama-swap security comments; the APU bucket is now named."""
    text = VALUES.read_text().lower()
    assert "fallback once a naming-capable plugin exists" not in text, (
        "C07: the pre-naming 'fallback once a naming-capable plugin exists' comment survived — "
        "it rewrites to REALIZED prose (per-name pools, APU bucket by explicit name)"
    )
    assert "gpu-8060s" in text, (
        "C07: the realized prose never names the APU pool the pod now claims"
    )


def test_tools_sidecar_stays_gpu_free():
    """HOLD (existing bar re-expressed at the render level for the flip wave):
    the tools sidecar claims nothing from the plugin — the flip is ONE
    resources line, no second GPU consumer sneaks in."""
    ctrs = {c.get("name"): c for c in
            next(d for d in L.render_docs("gpu-ai")
                 if d.get("kind") == "Deployment" and d.get("metadata", {}).get("name") == "llama-swap")
            ["spec"]["template"]["spec"]["containers"]}
    if "tools" not in ctrs:
        pytest.skip("tools sidecar disabled on this render — the HOLD is trivially satisfied")
    res = ctrs["tools"].get("resources") or {}
    gpu_keys = [k for k in (res.get("limits") or {}) | (res.get("requests") or {}) if k.startswith("amd.com/")]
    assert not gpu_keys, f"C07: the tools sidecar claims GPU pools {gpu_keys} — one consumer, by ruling"
