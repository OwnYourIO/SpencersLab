# cf-143 C07 — the per-cluster APU-naming shield (chunks/C07.md AC3 + Tests
# bullet 4, RE-PINNED in the C07 landing round per DECISIONS D21 / owner B1
# ruling). Round 1 pinned the flip on the chart's tree-global resources line;
# the owner's shield moved it: the chart default MUST keep the bare
# `amd.com/gpu: 1` claim (the gpu cluster's plugin stays single-naming
# 1.31.0.9 — services/gpu/prod/values.yaml keeps the external entry; that
# name is all it can advertise, and live gpu-llama-swap 1/1 must stay
# schedulable), while the gpu-AI SERVICE OVERLAY flips the same container:
# limits {amd.com/gpu: null, amd.com/gpu-8060s: 1} + an explicit requests
# mirror — maps deep-merge ADD-only, so the null is load-bearing (cf-97's
# valuesObject fact): it RETIRES the inherited bare key in the gpu-ai render.
#
# The arms are therefore `res=`-level render proofs, per cluster:
#   gpu-ai overlay-merged render → limits exactly {amd.com/gpu-8060s: 1},
#     the APU mirror present in requests, bare absent from BOTH maps;
#   gpu-cluster render → bare {amd.com/gpu: 1} intact (the shield's
#     executable proof — D21's whole point is this render never moves).
# Values-level: the chart's claim line stays bare with its WHY comment;
# stray guards keep the APU name confined to the gpu-ai overlay and the
# R9700 name to charts/radiance once C02 lands (the AC4 per-cluster law;
# the whole-repo sweep is amd-gpu-naming.sh n3).
#
# Red/green at this round: the claim arms go GREEN with the dev's landing
# tree (overlay + reverted chart line); the realized-prose and tools-sidecar
# legs are the same bars round-1 wrote and stay byte-kept where true.
#
# C08 T-B re-point (mid-round amendment): the R9700 pool name resolved to
# the PATCHED-TABLE rename (D24) — this suite's legs read the CANONICAL
# constants block in charts/amd-gpu/tests/amd_gpu_testlib.py (the marked one-
# edit site; the APU claim it asserts is frozen by the ruling). No literal
# names live in this file.
#
# Run with the suite (per-directory): python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import re
import sys

import pytest
import yaml

import llama_swap_testlib as L

_ok, _reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_reason)

_amd_tests = L.REPO_ROOT / "charts" / "amd-gpu" / "tests"
assert _amd_tests.is_dir(), (
    "cf-143 naming suite: the GPU-name constants home (charts/amd-gpu/tests) is missing — "
    "names resolve from the one marked block, never from forked literals"
)
if str(_amd_tests) not in sys.path:
    sys.path.insert(0, str(_amd_tests))
import amd_gpu_testlib as AMDNAMES  # noqa: E402

APU_CLAIM = AMDNAMES.APU_CLAIM
R9700_CLAIM = AMDNAMES.R9700_CLAIM
BARE_CLAIM = AMDNAMES.BARE_GPU_CLAIM
VALUES = L.CHART_DIR / "values.yaml"
GPU_AI_SERVICE = L.REPO_ROOT / "services" / "gpu-ai" / "prod" / "values.yaml"


def _main_resources(cluster: str) -> dict:
    """The outer llama-swap main container's resources at the res= level of
    the REAL per-cluster overlay-merged render (the twin-sidecar leg below
    reads the same level)."""
    docs = L.render_docs(cluster)
    dep = next(d for d in docs
               if d.get("kind") == "Deployment" and d.get("metadata", {}).get("name") == "llama-swap")
    for c in dep["spec"]["template"]["spec"]["containers"]:
        if c.get("name") == "main":
            return c.get("resources") or {}
    raise AssertionError("C07: no llama-swap main container rendered (render-shape drift, not the flip)")


# --- gpu-ai: the named APU pool (overlay flip, null-retire) ---------------------


def test_main_container_claims_named_apu_pool():
    """D21/AC3 per-cluster truth at the gpu-ai render: limits EXACTLY
    {amd.com/gpu-8060s: 1} — the overlay's `amd.com/gpu: null` retired the
    inherited bare key — and the explicit requests mirror ships alongside
    (self-documentation per D21; the scheduler auto-mirrors extended
    resources anyway, and requests never inherited the bare key, so there is
    nothing to null there)."""
    res = _main_resources("gpu-ai")
    assert res.get("limits") == {APU_CLAIM: 1}, (
        f"C07/D21: gpu-ai main limits are {res.get('limits')} — want exactly {{{APU_CLAIM!r}: 1}}; "
        "the bare amd.com/gpu must be RETIRED by the overlay null (maps ADD, null removes)"
    )
    req = res.get("requests") or {}
    assert req.get(APU_CLAIM) == 1, (
        f"C07/D21: gpu-ai main requests {req} lack the explicit {APU_CLAIM}: 1 mirror "
        "(the shipped self-documentation; a silently auto-mirrored-only shape is drift)"
    )
    assert req.get("cpu") == "1000m" and req.get("memory") == "4Gi", (
        f"C07: gpu-ai main requests lost the chart's cpu/memory pair: {req}"
    )
    assert BARE_CLAIM not in res.get("limits", {}) and BARE_CLAIM not in req, (
        "C07/D21: the bare amd.com/gpu claim survived in the gpu-ai render (either map) — "
        "after the vendored plugin registers product naming the name does not exist on "
        "THE gpu-ai NODE: a stray bare claim there is Pending-forever"
    )


# --- gpu cluster: the shield's bare default, INTACT ------------------------------


def test_gpu_cluster_render_keeps_bare_claim():
    """The executable B1 proof: the gpu-cluster overlay-merged render still
    claims {amd.com/gpu: 1} — the only name its single-naming 1.31.0.9
    plugin can advertise — with no APU name leaking in. If this arm ever
    reds, the per-cluster shield has been broken in the worst direction."""
    res = _main_resources("gpu")
    assert res.get("limits") == {BARE_CLAIM: 1}, (
        f"C07/D21: gpu-cluster main limits are {res.get('limits')}, want exactly "
        f"{{{BARE_CLAIM!r}: 1}} — the gpu-ai flip must NEVER reach this render"
    )
    blob = yaml.safe_dump(res)
    assert APU_CLAIM not in blob, (
        "C07/D21: the APU pool name leaked into the gpu-cluster render — that cluster's "
        "plugin cannot advertise it; the live gpu-llama-swap would be unschedulable"
    )


# --- values-level per-cluster law (AC4's chart/overlay legs) --------------------


def _live_claim_lines(path, claim):
    """Non-comment lines carrying `claim: <int>` — the live-claim shape."""
    pat = re.compile(rf"^\s*{re.escape(claim)}:\s*[0-9]+\s*(#.*)?$")
    return [f"{i}: {ln.strip()[:100]}" for i, ln in enumerate(path.read_text().splitlines(), 1)
            if pat.match(ln) and not ln.lstrip().startswith("#")]


def test_chart_default_claim_stays_bare_with_why():
    """Per-cluster law at the chart source: the tree-global claim line is the
    BARE name BY DESIGN (zero claim-line diff vs pre-ticket — AC3), its
    WHY comment present, and no APU-named live claim anywhere in the chart."""
    live = _live_claim_lines(VALUES, BARE_CLAIM)
    assert any(ln.split(": ", 1)[1].endswith("amd.com/gpu: 1") or "amd.com/gpu: 1" in ln for ln in live), (
        f"C07/D21 AC3: charts/llama-swap/values.yaml lost the tree-global bare `amd.com/gpu: 1` "
        f"claim line (live bare lines: {live}) — the gpu cluster renders this chart too"
    )
    assert not _live_claim_lines(VALUES, APU_CLAIM), (
        "C07/D21: a LIVE amd.com/gpu-8060s claim line in the CHART values — the flip is "
        "overlay-only; a tree-global flip strands gpu-llama-swap (the B1 leak)"
    )
    assert not _live_claim_lines(VALUES, R9700_CLAIM), "C07: the R9700 pool name has no business in charts/llama-swap"
    text = VALUES.read_text()
    assert "THE CLAIM IS TREE-GLOBAL" in text and "single-naming" in text, (
        "C07/D21: the bare-claim line's WHY comment (tree-global claim, gpu cluster's "
        "single-naming 1.31.0.9) is missing — the next reader must not 'fix' this line"
    )


def test_apu_name_lives_only_in_the_gpu_ai_overlay():
    """The AC4 stray-guard, chart-side pair of amd-gpu-naming.sh n3: live
    amd.com/gpu-8060s CLAIM lines (not comments, not fixtures) appear ONLY in
    services/gpu-ai/prod/values.yaml — the whole-repo sweep is n3's; this arm
    keeps the pytest suite honest about the same law."""
    hits = []
    for path in sorted(L.REPO_ROOT.glob("services/*/*/values.yaml")):
        if _live_claim_lines(path, APU_CLAIM):
            hits.append(str(path.relative_to(L.REPO_ROOT)))
    assert hits == ["services/gpu-ai/prod/values.yaml"], (
        f"C07/D21 AC4: services-layer live APU claims outside the gpu-ai overlay: {hits} — "
        "any other cluster would ask its single-naming plugin for a name it cannot give"
    )
    assert _live_claim_lines(GPU_AI_SERVICE, APU_CLAIM), (
        "C07/D21: the gpu-ai overlay carries NO live APU claim line — the flip leg is missing"
    )
    # R9700 stray-guard, C02-visible: zero live claims repo-wide today; when
    # charts/radiance lands the name belongs THERE (+ the amd-gpu ledger
    # comment, comments exempt) — a stray elsewhere still reds here.
    rad = L.REPO_ROOT / "charts" / "radiance" / "values.yaml"
    svc_hits = _live_claim_lines(GPU_AI_SERVICE, R9700_CLAIM)
    other_services = [
        str(p.relative_to(L.REPO_ROOT))
        for p in sorted(L.REPO_ROOT.glob("services/*/*/values.yaml"))
        if p != GPU_AI_SERVICE and _live_claim_lines(p, R9700_CLAIM)
    ]
    chart_py_hits = [] if not rad.is_dir() else sorted(
        str(p.relative_to(L.REPO_ROOT))
        for p in (L.REPO_ROOT / "charts").rglob("*.yaml")
        if "tests" not in p.parts and "radiance" not in p.parts and _live_claim_lines(p, R9700_CLAIM)
    )
    assert not svc_hits and not other_services and not chart_py_hits, (
        f"C07 AC4 / C02: the R9700 pool name claimed outside charts/radiance — "
        f"gpu-ai overlay: {svc_hits}, other services: {other_services}, other charts: {chart_py_hits}"
    )


def test_realized_prose_replaces_the_fallback_comment():
    """C07 (carried from round 1, B1-intact): the comment 1331-1338
    ("...fallback once a naming-capable plugin exists: amd.com/gpu +
    IPC_LOCK/SYS_RESOURCE + non-privileged") rewrites to per-cluster REALIZED
    prose — the capability exists on gpu-ai (vendored plugin + overlay flip),
    the gpu cluster stays single-naming; the APU bucket is now a named
    guarantee there. The old forward-looking sentence is gone."""
    text = VALUES.read_text().lower()
    assert "fallback once a naming-capable plugin exists" not in text, (
        "C07: the pre-naming 'fallback once a naming-capable plugin exists' comment survived — "
        "it rewrites to REALIZED prose (D21 per-cluster wording)"
    )
    assert "gpu-8060s" in text and ("realized" in text or "per-cluster" in text), (
        "C07: the realized prose never names the APU pool or the per-cluster shield — "
        "the comment rewrite is the ONLY chart-side change (AC3 zero claim-line diff)"
    )


def test_tools_sidecar_stays_gpu_free():
    """HOLD (existing bar re-expressed at the render level for the flip wave):
    the tools sidecar claims nothing from the plugin — the flip is ONE
    overlay block, no second GPU consumer sneaks in."""
    docs = L.render_docs("gpu-ai")
    dep = next(d for d in docs
               if d.get("kind") == "Deployment" and d.get("metadata", {}).get("name") == "llama-swap")
    ctrs = {c.get("name"): c for c in dep["spec"]["template"]["spec"]["containers"]}
    if "tools" not in ctrs:
        pytest.skip("tools sidecar disabled on this render — the HOLD is trivially satisfied")
    res = ctrs["tools"].get("resources") or {}
    merged = {}
    for m in ("limits", "requests"):
        merged.update(res.get(m) or {})
    gpu_keys = [k for k in merged if k.startswith("amd.com/")]
    assert not gpu_keys, f"C07: the tools sidecar claims GPU pools {gpu_keys} — one consumer, by ruling"
