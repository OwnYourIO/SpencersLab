# cf-143 C01 re-pin (2026-11-11) — this file is the GitOps-DISABLE witness for
# the peers.vllm hop, not its enable contract (the enable era's record:
# 2026/2026-11-cf-105-feat-implement-vllm C03 + cf-105-vllm-followup C01
# re-pin, both preserved in git history and TEST_SPEC §10/§11/§12).
#
# Owner ruling Q3 (DECISIONS): the vllm lane (charts/vllm — the
# magiccodingman/vllm-radiance FORK engine, NOT the cf-143 radiance engine) is
# disabled COMMENTED-OUT with the artifact kept one-edit-reversible; the
# rendered gpu-ai config must therefore carry NO peers.vllm block, while
# peers.strata REMAINS live (Q5 — "Strata shouldn't be disabled yet").
#
# Red state at handoff (designed): T1 and T4 red until the C01 dev lands the
# values comment-out + the paired golden re-capture (TEST_SPEC §1 pattern —
# the capture note is the test session's, recorded in TEST_SPEC §12; the
# re-capture itself is the dev obligation, cf-105 C03 precedent). T2 (schema
# validity of the vllm-free render) and both T3 HOLDs are green now and must
# stay green — they pin the gpu box and gpu golden staying peer-vllm-free
# across every cf-143 wave (the radiance peer joins gpu-ai-only too, C04).
#
# Run with the suite (per-directory): python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import pytest

import llama_swap_testlib as L
import strata_testlib as S

_ok, _ok_reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_ok_reason)


def _peers(cfg: dict) -> dict:
    return cfg.get("peers") or {}


# --- T1: peers.vllm is ABSENT from the rendered gpu-ai config ------------------


def test_t1_peers_vllm_absent_strata_remains():
    """cf-143 C01 AC1/AC4 — the disable is executable here: the FE hop's vllm
    leg is gone from the render, and the strata peer (its models list still a
    sanctioned evidence wave) still serves. A leftover peers.vllm block would
    keep routing a dormant engine (gpu-ai-vllm sits at replicas 0 out-of-band;
    the GitOps disable is what makes that permanent)."""
    cfg = L.rendered_config("gpu-ai")
    peers = _peers(cfg)
    assert "vllm" not in peers, (
        "cf-143 C01 T1: rendered gpu-ai config still carries peers.vllm — the "
        "vllm (charts/vllm, magiccodingman/vllm-radiance fork) lane is not "
        "commented out yet (owner Q3: disable, keep the artifact reversible)"
    )
    assert "strata" in peers, (
        "cf-143 C01 T1: peers.strata MISSING — Q5 keeps strata live; deleting it here is a "
        "scope violation, not a fix (the red means the render lost the live peer)"
    )
    served = set(S.inner_config(L.render_docs("gpu-ai"))["models"])
    assert peers["strata"]["models"] == S.expected_strata_peers(served), (
        "cf-143 C01 T1: peers.strata.models left the sanctioned evidence wave — "
        "the strata peer must be byte-stable through the vllm disable"
    )


# --- T2: the rendered config still validates against the pinned v266 schema ---


def test_t2_vllm_free_render_validates_against_v266():
    """cf-143 C01 T1 re-pin, kept from the cf-105 T2 schema leg: the
    peers subtree WITHOUT vllm must still be schema-legal (the standing
    pre-cf-77 performance.enable carve-out applies, unchanged)."""
    cfg = L.rendered_config("gpu-ai")
    carved = S.strip_legacy_performance_keys(cfg)
    errs = S.schema_errors(carved, S.v266_schema())
    assert not errs, (
        "cf-143 C01 T2: the rendered gpu-ai config (vllm-free) violates the pinned v266 "
        "schema:\n  " + "\n  ".join(f"{'.'.join(map(str, list(e.absolute_path))) or '<root>'}: {e.message[:160]}" for e in errs[:8])
    )


# --- T3: the gpu cluster is unaffected (HOLDs, green now, green after) --------


def test_t3_gpu_render_carries_no_vllm_peer():
    cfg = L.rendered_config("gpu")
    assert _peers(cfg).get("vllm") is None, (
        "cf-143 C01 T3: peers.vllm leaked into the gpu cluster render — the hop was "
        "gpu-ai-only in its live era and stays gpu-ai-only in its disabled shape"
    )


def test_t3_gpu_golden_stays_vllm_free():
    """The gpu golden is NOT re-captured by cf-143 (both cf-143 peer edits are
    gpu-ai-only, plan 'Golden churn'): no vllm text may appear in it."""
    path = L.GOLDEN_DIR / "gpu.config.yaml"
    assert path.is_file(), f"cf-143 C01 T3: golden fixture {path} missing"
    assert "vllm" not in path.read_text().lower(), (
        "cf-143 C01 T3: the gpu golden carries vllm text — the gpu-side golden must stay "
        "untouched by the cf-143 waves"
    )


# --- T4: the re-captured gpu-ai golden is byte-stable and vllm-free -----------


def test_t4_gpuai_golden_byte_equal_and_vllm_free():
    """TEST_SPEC §1 capture pattern, byte-stable parity as the cf-105 T4 was:
    every data byte of the golden equals a fresh render (column-0 ruling
    annotations exempt — toYaml never emits them; indented # lines are
    block-scalar macro CONTENT, byte-pinned as data). cf-143 C01 adds the
    era inversion: the golden's peers subtree must carry NO vllm block —
    the re-capture obligation is what turns this green, and the capture note
    lands in TEST_SPEC §12 (test session) beside the dev's re-capture."""
    docs = L.render_docs("gpu-ai")
    fresh = None
    for doc in docs:
        if doc.get("kind") == "ConfigMap" and doc.get("metadata", {}).get("name") == "llama-swap-config":
            fresh = doc["data"]["config.yaml"]
            break
    assert fresh is not None, "cf-143 C01 T4: the gpu-ai render produced no llama-swap-config ConfigMap"
    path = L.GOLDEN_DIR / "gpu-ai.config.yaml"
    assert path.is_file(), f"cf-143 C01 T4: golden fixture {path} missing"

    def top_comment_free(text: str) -> str:
        # Column-0 lines only: the fixture's dated ruling annotations.
        return "\n".join(ln for ln in text.splitlines() if not ln.startswith("#"))

    assert top_comment_free(path.read_text()) == top_comment_free(fresh), (
        "cf-143 C01 T4: the gpu-ai golden differs from a fresh render (data bytes; only the "
        "column-0 annotation comments are exempt) — re-capture per TEST_SPEC §1 "
        "(extract the llama-swap: subtree -> helm template --show-only templates/configmap-llama-swap.yaml "
        "-> extract .data['config.yaml'] verbatim) and record the capture note in TEST_SPEC.md"
    )
    golden_peers = _peers(L.golden_config("gpu-ai"))
    assert "vllm" not in golden_peers, (
        "cf-143 C01 T4: the golden's peers subtree still carries the vllm block — the "
        "re-capture must land WITH the values comment-out, never after (paired obligation, "
        "cf-105 C03 precedent)"
    )
    assert "strata" in golden_peers, (
        "cf-143 C01 T4: the golden lost peers.strata — Q5: the strata block is byte-stable "
        "through the re-capture"
    )
