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
# C10 re-anchor (§D2, D26 — LIVE OUTAGE round): a per-cluster `null`
# retirement NEVER crosses the ApplicationSet→Application valuesObject chain
# (null dropped pre-helm; live pair: present in the generator, absent in the
# Application; helm-alone honors it — proof at the wrong layer). The claim
# therefore became a per-cluster positive ADD and the gpu-ai legs move to the
# PROJECTION layer (testlib appset→valuesObject model, §12.9) — the exact
# shape the cluster renders. gpu-cluster shields stay GREEN BOTH DIRECTIONS
# (byte-identical transfer is the point); the chart-default arm flips to
# CLAIM-LESS with the carrier WHY; a null-absence guard closes the class.
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


# --- gpu-ai: the named APU pool — two layers, one law ---------------------------


def _proj_main(cluster: str) -> dict:
    main = L.projection_main_container(cluster)
    return main.get("resources") or {}


def test_gpu_ai_valuesobject_projection_claims_only_apu():
    """C10 AC3 leg A — THE production-shaped witness, DESIGNED-RED until dev
    lands the carrier move: through the appset→valuesObject projection (§D2 —
    the model lives at ONE site in the testlib with the evidence pair cited),
    gpu-ai's main container limits must be EXACTLY {amd.com/gpu-8060s: 1}.
    Today the projection DROPS the overlay null, the chart's tree-global bare
    survives beside the ADD — the unschedulable pair that has the router down
    since 01:52:09Z (§D2.3; node bare pool sits at capacity 0, §D2.2). The
    fix is the chart going claim-less + per-cluster ADDs (AC2); a null can
    never retire a claim across this chain, and 0 is not a legal extended-
    resource value either — positive ADDs are the only carrier (D26)."""
    res = _proj_main("gpu-ai")
    assert res.get("limits") == {APU_CLAIM: 1}, (
        f"C10 AC3 leg A: projected gpu-ai limits are {res.get('limits')}, want exactly "
        f"{{{APU_CLAIM!r}: 1}} — any surviving {BARE_CLAIM} line is the tree-global default "
        "riding past the chain (the live Pending-forever shape); see §D2/D26"
    )
    req = res.get("requests") or {}
    assert req.get(APU_CLAIM) == 1 and req.get("cpu") == "1000m" and req.get("memory") == "4Gi", (
        f"C10: projected gpu-ai requests {req} — APU mirror + cpu/memory expected (the requests "
        "mirror survives the chain — it is an ADD, never an inherited-key retirement)"
    )
    assert BARE_CLAIM not in res.get("limits", {}) and BARE_CLAIM not in req, (
        "C10/D26: bare amd.com/gpu in the projected gpu-ai render — a stray bare claim there is "
        "Pending-forever at the node's capacity-0 retention (the live defect, §D2.2)"
    )


def test_gpu_ai_helm_merge_shape_keeps_apu_only():
    """The helm-merge level (what a direct `helm -f` does IF handed the
    overlay — §D2.6's locally-reproduced honoring): APU limits + the explicit
    requests mirror + no bare, both pre- and post-C10. Pre: the null honors
    HERE — and precisely MISLEADS (this layer is not what the cluster renders;
    the live pair §D2 shows the null dropped one layer up). Post: chart
    carries no bare, the ADDs stand. GREEN both directions; a red means the
    overlay's ADDs moved. Absorbs the pre-C10 gpu-ai leg whose null-retire
    D26 retired."""
    res = _main_resources("gpu-ai")
    assert res.get("limits") == {APU_CLAIM: 1}, (
        f"C10: helm-merge gpu-ai limits {res.get('limits')} — want {{{APU_CLAIM!r}: 1}} at this layer too"
    )
    req = res.get("requests") or {}
    assert req.get(APU_CLAIM) == 1 and req.get("cpu") == "1000m" and req.get("memory") == "4Gi", (
        f"C10: helm-merge gpu-ai requests {req} — APU mirror + cpu/memory expected"
    )
    assert BARE_CLAIM not in res.get("limits", {}) and BARE_CLAIM not in req, (
        "C10: bare amd.com/gpu at the helm-merge level of gpu-ai (post-C10 nothing "
        "injects it there; pre-C10 only the honored-null hid it — see leg A for the production shape)"
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


def test_gpu_cluster_valuesobject_projection_keeps_bare_only():
    """C10 AC3 leg B — the shield witness at the PRODUCTION layer: projected
    gpu-cluster limits EXACTLY {amd.com/gpu: 1}, requests cpu/memory only (the
    kubelet mirrors extended resources itself — the gpu ADD is limits-only by
    the D26 byte-law adjudication), APU absent. GREEN pre-C10 (bare rides the
    chart default through the chain) and GREEN post-C10 (bare rides the gpu
    overlay ADD) — the transfer is byte-neutral BY DESIGN; if this arm ever
    reddens, a cluster lost its only schedulable claim."""
    res = _proj_main("gpu")
    assert res.get("limits") == {BARE_CLAIM: 1}, (
        f"C10 leg B/shield: projected gpu limits are {res.get('limits')} — must stay exactly "
        f"{{{BARE_CLAIM!r}: 1}} across the carrier move"
    )
    assert res.get("requests") == {"cpu": "1000m", "memory": "4Gi"}, (
        f"C10 leg B: gpu requests moved ({res.get('requests')}) — the byte-law proof says the "
        "gpu-cluster Deployment resources block stays byte-identical pre/post (AC4)"
    )
    assert APU_CLAIM not in yaml.safe_dump(res), (
        "C10 leg B: the APU name leaked into the gpu cluster — that plugin cannot advertise it"
    )


def test_no_retirement_instructions_survive_the_chain():
    """C10 AC3 leg C — the pattern that cannot fail silently (§D2.6.7):
    NO null-valued key anywhere in the parsed llama-swap generator values of
    EITHER umbrella (the projection would eat it — deletion is INERT through
    the chain, leaving the live defect one sync away forever), and no
    claim-retirement `: null` line in any service values file. DESIGNED-RED
    until dev drops the inert null + prose; guard both render-side and
    text-side so a future overlay cannot re-introduce the pattern quietly."""
    problems = []
    for cluster in ("gpu", "gpu-ai"):
        _docs, _raw, rv = L.render_via_projection(cluster)
        parsed = yaml.safe_load(rv)

        def walk(node, path):
            if isinstance(node, dict):
                for k, v in node.items():
                    if v is None:
                        problems.append(f"{cluster}: {path}.{k} = null (will be dropped pre-helm)")
                    else:
                        walk(v, f"{path}.{k}")
            elif isinstance(node, list):
                for i, v in enumerate(node):
                    walk(v, f"{path}[{i}]")

        walk(parsed, "values")
    for path in sorted(L.REPO_ROOT.glob("services/*/*/values.yaml")):
        for i, ln in enumerate(path.read_text().splitlines(), 1):
            if re.match(r"^[ 	]*amd\.com/\S*:[ 	]*null", ln) and not ln.lstrip().startswith("#"):
                problems.append(f"{path.relative_to(L.REPO_ROOT)}:{i} live ': null' retirement line")
    assert not problems, (
        "C10 AC3 leg C / §D2 / D26: retirement instructions in the tree-global-claim era —\n  "
        + "\n  ".join(problems)
        + "\nnulls never cross the appset→application valuesObject chain (helm-only proofs lie); "
        "extended resources take positive integers only — the carrier is a per-cluster ADD."
    )


# --- values-level per-cluster law (AC4's chart/overlay legs) --------------------


def _live_claim_lines(path, claim):
    """Non-comment lines carrying `claim: <int>` — the live-claim shape."""
    pat = re.compile(rf"^\s*{re.escape(claim)}:\s*[0-9]+\s*(#.*)?$")
    return [f"{i}: {ln.strip()[:100]}" for i, ln in enumerate(path.read_text().splitlines(), 1)
            if pat.match(ln) and not ln.lstrip().startswith("#")]


def test_chart_default_is_claim_less_with_carrier_why():
    """C10 AC2.1 (arm FLIPPED from the round-1 'stays bare' law — the D21
    carrier died; the intent stands): the chart ships NO GPU claim at all.
    A fresh cluster without its own overlay ADD simply gets a GPU-less
    llama-swap pod — the accepted standalone-usable trade-off, and the ONLY
    shape that cannot strand a cluster through the valuesObject chain
    (deletions are inert there; positive ADDs survive). DESIGNED-RED today:
    the bare line still sits at the chart default. WHY needles keep
    grep-symmetry with the bash n2 mirror: per-cluster, the APU name,
    single-naming, the ADD word, and the positive-integers sentence."""
    live_bare = _live_claim_lines(VALUES, BARE_CLAIM)
    assert not live_bare, (
        f"C10 AC2.1: charts/llama-swap/values.yaml still carries live bare-claim lines "
        f"{live_bare} — the carrier moves per-cluster (services/gpu ADDs bare, services/gpu-ai "
        "already ADDs the APU); a tree-global claim cannot be retired downstream (D26)"
    )
    assert not _live_claim_lines(VALUES, APU_CLAIM), (
        "C10: a live APU claim in the CHART values would strand the gpu cluster (D21 intent)"
    )
    assert not _live_claim_lines(VALUES, R9700_CLAIM), "C07: the R9700 pool name has no business in charts/llama-swap"
    text = " ".join(VALUES.read_text().split())
    assert "THE CLAIM IS TREE-GLOBAL" not in text, (
        "C10 AC2.1: the tree-global sentence survived the rewrite — its era is over (needle "
        "symmetry with the flipped bash n2 mirror)"
    )
    # NIT-1 (C10 review r1) tightening: the WHY needles read the comment run
    # IMMEDIATELY ABOVE the resources key (the block AC2.1 restructures) — a
    # whole-file prose match let stray words elsewhere (values.yaml:3's
    # "per-cluster" about custom-values, e.g.) satisfy the law. The
    # load-bearing discriminators stay whole-file by nature (absence of the
    # TREE-GLOBAL sentence, absence of live claim lines); wrap-safety kept
    # (comment lines join so "positive / # integers" cannot defeat a
    # present-where-owned needle).
    raw_lines = VALUES.read_text().splitlines()
    ridx = next((i for i, ln in enumerate(raw_lines) if ln.strip() == "resources:"), None)
    assert ridx is not None, "C10 AC2.1: no resources: key in charts/llama-swap/values.yaml at all"
    why: list[str] = []
    j = ridx - 1                      # comment run ABOVE the key ...
    while j >= 0:
        s = raw_lines[j].strip()
        if s.startswith("#"):
            why.insert(0, s.lstrip("#").strip())
            j -= 1
        else:
            break
    j = ridx + 1                      # ... and/or INSIDE the block (dev placed
    while j < len(raw_lines):         # the C10 WHY under the key)
        s = raw_lines[j].strip()
        if s.startswith("#"):
            why.append(s.lstrip("#").strip())
            j += 1
        else:
            break
    assert why, (
        "C10 AC2.1: no comment block directly above the resources: key — the WHY "
        "must live AT the claim-less default it explains, not merely somewhere"
    )
    prose = " ".join(why)
    assert "per-cluster" in prose and APU_CLAIM in prose and "single-naming" in prose, (
        "C10 AC2.1: the restructured WHY comment lacks per-cluster carrier / gpu-8060s / "
        "single-naming facts (the comment must answer 'why is there no default claim here?')"
    )
    assert re.search(r"(?i)\badd(ed)?\b", prose) and re.search(r"(?i)positive integer", prose), (
        "C10 AC2.1: the WHY comment must name the surviving mechanism (per-cluster positive ADD) "
        "— §D2.6.7's silent-failure class is closed only if the reader learns null AND 0 are dead ends"
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
    # R9700 stray-guard (C02+ claim site): live R9700 claims belong ONLY in
    # charts/radiance (+ the amd-gpu ledger, comments exempt) — a stray
    # elsewhere still reds here.
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
