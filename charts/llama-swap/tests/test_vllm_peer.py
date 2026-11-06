# C03 peers.vllm hop contract (2026/2026-11-cf-105-feat-implement-vllm —
# chunks/C03.md, tests T1-T4). The gpu-ai llama-swap config gains the
# peers.vllm hop (D7: vLLM reached exclusively through the llama-swap
# surface) with the D6 priority floor, and the re-captured gpu-ai golden
# must be byte-stable against a fresh render.
#
# Red state at handoff (designed): T1/T2 red — peers.vllm is not in the
# gpu-ai render yet; T4 red — the committed gpu-ai golden predates the
# current render (pre-C03 catalog drift) and gains the peers.vllm block
# only with the C03 re-capture (the TEST_SPEC §1 pattern), the obligation
# that turns it green. T3 is a HOLD bar, green at handoff and must stay
# green: the gpu render carries no vllm peer and the gpu golden stays
# vllm-free (the block is gpu-ai-only; the gpu golden is untouched by C03).
#
# cf-105-vllm-followup C01 re-pin (2026-11-06): T1's floor constant moves
# 10 -> 5 with the default class (the four-class amendment — the peer floor
# follows the default class, D2), so T1's block-equality leg is
# designed-red until the wire change + golden re-capture land; T2 (schema),
# T3 and T4 carry over unchanged.
#
# Run with the suite (per-directory): python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import pytest

import llama_swap_testlib as L
import strata_testlib as S

_ok, _reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_reason)

# The peer block exactly per the C03 task spec: proxy carries NO /v1 suffix
# (path appended verbatim, EXPLORE §8.9), models lists the served name
# explicitly, responseHeader 1800 is the deep-prefill first-byte knob
# (Strata precedent), setParams "priority?" is the set-if-undefined floor 5
# (a client-sent priority wins, so the C04 class rows pass through untouched).
# No apiKey: keyless in-cluster (R3 Q5.3). The literal itself lives in the
# testlib (L.PEER_VLLM) — the single source shared with the parity and
# strata-wiring arms that re-pin the same block.
PEER_VLLM = L.PEER_VLLM


def _peers(cfg: dict) -> dict:
    return cfg.get("peers") or {}


# --- T1: the rendered peers.vllm block is exactly the task spec ---------------


def test_t1_peers_vllm_block_exact():
    cfg = L.rendered_config("gpu-ai")
    peer = _peers(cfg).get("vllm")
    assert peer is not None, (
        "C03 T1: rendered gpu-ai config has no peers.vllm block — the llama-swap FE hop (D7) is not implemented"
    )
    assert peer.get("proxy") == PEER_VLLM["proxy"], (
        f"C03 T1: peer proxy is {peer.get('proxy')!r}, want {PEER_VLLM['proxy']!r} "
        "(the C02 Service DNS name — http://gpu-ai-vllm.default.svc.cluster.local:8000)"
    )
    assert "/v1" not in peer.get("proxy", ""), (
        f"C03 T1: peer proxy {peer.get('proxy')!r} carries a /v1 suffix — the request path is appended "
        "verbatim, a suffix would double-prefix every route"
    )
    assert peer.get("models") == PEER_VLLM["models"], (
        f"C03 T1: peer models is {peer.get('models')!r}, want {PEER_VLLM['models']!r} "
        "(the served name listed explicitly — peers is not a blanket URL proxy)"
    )
    assert peer.get("timeouts") == PEER_VLLM["timeouts"], (
        f"C03 T1: peer timeouts is {peer.get('timeouts')!r}, want {PEER_VLLM['timeouts']!r} "
        "(responseHeader 1800 = the deep-prefill first-byte knob, Strata precedent)"
    )
    assert peer.get("filters") == PEER_VLLM["filters"], (
        f"C03 T1: peer filters is {peer.get('filters')!r}, want {PEER_VLLM['filters']!r} "
        '(the "priority?" set-if-undefined floor 5 — default class, client-sent value wins)'
    )
    assert peer == PEER_VLLM, (
        f"C03 T1: the peers.vllm block must be EXACTLY the task spec (no apiKey, no extra keys)\n"
        f"  got:      {peer}\n  expected: {PEER_VLLM}"
    )


# --- T2: the rendered config still validates against the pinned v266 schema ---


def test_t2_rendered_config_validates_against_v266():
    """AC1's schema leg: the peers.*.filters.setParams shape is schema-legal
    (R4 [111]) — reusing the existing schema harness helpers (the
    performance.enable carve-out is the standing pre-cf-77 divergence pin)."""
    cfg = L.rendered_config("gpu-ai")
    assert _peers(cfg).get("vllm") is not None, (
        "C03 T2: peers.vllm absent — nothing to schema-check yet (the block must exist before its shape can be proven legal)"
    )
    carved = S.strip_legacy_performance_keys(cfg)
    errs = S.schema_errors(carved, S.v266_schema())
    assert not errs, (
        "C03 T2: the rendered gpu-ai config (with peers.vllm) violates the pinned v266 schema:\n  "
        + "\n  ".join(f"{'.'.join(map(str, list(e.absolute_path))) or '<root>'}: {e.message[:160]}" for e in errs[:8])
    )


# --- T3: the gpu cluster is unaffected -----------------------------------------


def test_t3_gpu_render_carries_no_vllm_peer():
    cfg = L.rendered_config("gpu")
    assert _peers(cfg).get("vllm") is None, (
        "C03 T3: peers.vllm leaked into the gpu cluster render — the block is gpu-ai-only (D2: the 8 GiB box is untouched)"
    )


def test_t3_gpu_golden_stays_vllm_free():
    """The gpu golden is NOT re-captured by C03 (the block is gpu-ai-only,
    plan Risks 'Golden churn'): no vllm text may appear in it, in any case."""
    path = L.GOLDEN_DIR / "gpu.config.yaml"
    assert path.is_file(), f"C03 T3: golden fixture {path} missing"
    assert "vllm" not in path.read_text().lower(), (
        "C03 T3: the gpu golden carries vllm text — the gpu-side golden must stay untouched by C03"
    )


# --- T4: the re-captured gpu-ai golden is byte-stable ----------------------------


def test_t4_gpuai_golden_byte_equal_to_fresh_render():
    """TEST_SPEC §1 capture pattern: the golden is the ConfigMap
    .data['config.yaml'] string itself, re-captured by C03 when the peers
    block changes the render. Byte-stable parity: every data byte must
    equal a fresh render (trailing newline normalized), so a faithful
    re-capture reproduces it — sound because helm output is deterministic
    for identical input (two independent renders byte-compare clean).
    The one exempted layer is a column-0 YAML comment line: the dated
    ruling annotations the cf-77/U15 re-captures embed in this fixture,
    which toYaml never emits into a fresh render. Indented # lines are
    block-scalar macro CONTENT — never stripped, byte-pinned as data."""
    docs = L.render_docs("gpu-ai")
    fresh = None
    for doc in docs:
        if doc.get("kind") == "ConfigMap" and doc.get("metadata", {}).get("name") == "llama-swap-config":
            fresh = doc["data"]["config.yaml"]
            break
    assert fresh is not None, "C03 T4: the gpu-ai render produced no llama-swap-config ConfigMap"
    path = L.GOLDEN_DIR / "gpu-ai.config.yaml"
    assert path.is_file(), f"C03 T4: golden fixture {path} missing"

    def top_comment_free(text: str) -> str:
        # Column-0 lines only: the fixture's dated ruling annotations.
        # Indented # lines live inside block scalars and are data.
        return "\n".join(ln for ln in text.splitlines() if not ln.startswith("#"))

    assert top_comment_free(path.read_text()) == top_comment_free(fresh), (
        "C03 T4: the gpu-ai golden differs from a fresh render (data bytes; only the "
        "column-0 annotation comments are exempt) — re-capture per TEST_SPEC §1 "
        "(extract the llama-swap: subtree -> helm template --show-only templates/configmap-llama-swap.yaml "
        "-> extract .data['config.yaml'] verbatim) and record the capture note in TEST_SPEC.md"
    )
