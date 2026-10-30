# cf-86 C03 — flash-next heretic-2 Q4_K_M llama.cpp rung (plan
# 2026/2026-10-cf-86-feat-more-strata-models, chunks/C03.md AC1-AC6).
#
# Red posture pre-dev: the id, its cmd legs, the fnher var and the solo
# membership are RED; the gpu-side preservation arms (echo shape, macro-free
# echo, family absent in the bare chart render) are green today and must stay
# green — they are the proof the new family does not leak off-cluster.
#
# The mmap-regime literals are copied VERBATIM from the shape-donor family
# (qwen3.8-flash-next-orca): this file compares the new rung's legs against the
# donor's rendered legs instead of restating them, so a donor re-tune can never
# silently half-apply to the heretic rung. The -ot string is byte-exact
# contract (TEST_SPEC §8 lineage).
#
# The -hf ref is the source gate's verified value (CF86_HF_REFS, HF API tree
# 2026-10-29). The liveness arm runs only under RUN_HF_CHECK=1 like the
# existing hf checks; the ref-literal arm runs always.

from __future__ import annotations

import json
import os
import re
import urllib.request

import pytest

import llama_swap_testlib as L
import strata_testlib as S

NEW_ID = "qwen3.8-flash-next-heretic-q4"
DONOR_ID = "qwen3.8-flash-next-orca-q6"

_ok, _reason = L.helm_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

hf_gated = pytest.mark.skipif(
    os.environ.get("RUN_HF_CHECK") != "1",
    reason="evidence gate: RUN_HF_CHECK=1 re-verifies the C03 -hf ref against the live HF API",
)


def _ai():
    return L.rendered_config("gpu-ai")


def _cmd() -> str:
    cfg = _ai()
    models = L.all_models_of(cfg)
    assert NEW_ID in models, f"gpu-ai render has no {NEW_ID} — C03 not landed"
    return L.effective_cmd(cfg, NEW_ID)


# --- AC1: the rung exists and carries the mmap regime ------------------------


@helm
def test_c03_rung_expands_to_the_frozen_id():
    """Family + rung grammar produces exactly `qwen3.8-flash-next-heretic-q4`
    (the plan's frozen id) — and no sibling variant (no -1m, no q8)."""
    models = L.all_models_of(_ai())
    assert NEW_ID in models, f"gpu-ai render has no {NEW_ID} — C03 not landed"
    near = sorted(m for m in models if m.startswith("qwen3.8-flash-next-heretic"))
    assert near == [NEW_ID], f"heretic family expansion produced {near}, want exactly [{NEW_ID}]"


@helm
def test_c03_mmap_regime_legs_match_the_donor():
    """The regime legs are what makes this rung fit the node: experts on CPU
    via -ot, mmap load, fit off, -ngl 99. Compared against the donor family's
    rendered legs (byte-exact), and 262144 ctx only — no 1M variant."""
    donor = L.effective_cmd(_ai(), DONOR_ID)
    cmd = _cmd()
    for leg in ('-ngl 99', L.CF86_MOE_OFFLOAD_LEG, '--load-mode mmap', '--fit off'):
        assert leg in donor, f"donor {DONOR_ID} no longer carries {leg!r} — donor re-tune, re-pin this file"
        assert leg in cmd, f"{NEW_ID} missing the mmap-regime leg {leg!r}"
    assert "--ctx-size 262144" in cmd, f"{NEW_ID} lacks the 256k ctx leg"
    assert "1010000" not in cmd, f"{NEW_ID} carries a 1M ctx variant (C03 forbids it)"


@helm
def test_c03_hf_ref_is_the_gate_verified_pack():
    """`-hf` is the source gate's literal, pinned from the testlib table (a
    source-gate deviation re-pins the table through the test session)."""
    want = L.CF86_HF_REFS[NEW_ID]
    got = L.cmd_flag_value(_cmd(), "-hf")
    assert got == want, f"-hf {got!r} != gate-verified {want!r}"


@helm
def test_c03_mtp_spec_follows_the_pack():
    """The verified pack carries MTP (Q4_K_M/MTP shards + mtp/mtp-*-Q8_0 draft
    in the HF tree, recorded with the source gate), so the two-gate precedent
    puts spec decoding on this rung — draft-mtp n-max 2, same as the donor."""
    cmd = _cmd()
    assert "--spec-type draft-mtp" in cmd, f"{NEW_ID} has no draft-mtp spec despite an MTP-bearing pack"
    assert "--spec-draft-n-max 2" in cmd, f"{NEW_ID} draft-n-max differs from the family default (2)"


@helm
def test_c03_no_preload_and_no_models_layer_override():
    """Never preloaded (the SOLO weight class must not boot-pin the node) and
    the chart-side composition is the truth — a services models-layer cmd
    override would escape every chart arm in this file."""
    cfg = _ai()
    preload = ((cfg.get("hooks") or {}).get("on_startup") or {}).get("preload") or []
    assert preload == L.C04_PRELOAD_PINNED, f"gpu-ai preload changed: {preload}"
    assert NEW_ID not in preload
    svc = L.service_overlay("gpu-ai")
    models_override = ((svc.get("config") or {}).get("models") or {})
    assert NEW_ID not in models_override, (
        f"services/gpu-ai carries a models-layer cmd override for {NEW_ID} — escape hatch only"
    )


# --- AC2: matrix law — solo only, never co-loaded ----------------------------


@helm
def test_c03_fnher_var_and_solo_membership():
    cfg = _ai()
    vars_ = (cfg.get("matrix") or {}).get("vars") or {}
    assert vars_.get("fnher") == NEW_ID, f"matrix.vars.fnher = {vars_.get('fnher')!r}"
    sets = S.matrix_expansions(cfg)
    assert any(NEW_ID in c for c in sets.get("solo", [])), f"{NEW_ID} is not in sets.solo"
    assert not any(NEW_ID in c for c in sets.get("main", [])), f"{NEW_ID} leaked into sets.main"
    for name, combos in sets.items():
        if name in ("main", "solo"):
            continue
        assert not any(NEW_ID in c for c in combos), f"{NEW_ID} appears in matrix set {name!r}"


@helm
def test_c03_solo_law_two_mmap_rungs_never_co_load():
    """The memory law in executable form: two mmap/fit-off flash-next-class
    rungs co-resident blow the node budget, so no DNF combo may hold more than
    one. Regime-based (the --fit off leg) so it stays correct as rungs grow."""
    cfg = _ai()
    models = L.all_models_of(cfg)
    mmap_ids = {mid for mid, m in models.items() if "--fit off" in L.effective_cmd(cfg, mid)}
    for name, combos in S.matrix_expansions(cfg).items():
        for combo in combos:
            clash = combo & mmap_ids
            assert len(clash) <= 1, f"matrix set {name!r} co-loads mmap rungs {sorted(clash)}"


# --- AC1/AC4: gpu side stays echo-only; chart default stays family-off --------


@helm
def test_c03_gpu_render_echoes_the_rung_macro_free():
    """gpu does not enable the family: the id must arrive as the standard id-
    prefixed fail-fast echo (P5 superset law) with NO macro or llama.cpp flag
    resolved — the echo path must never become runnable off-cluster."""
    models = L.all_models_of(L.rendered_config("gpu"))
    assert NEW_ID in models, f"gpu render lacks the {NEW_ID} echo (P5)"
    cmd = models[NEW_ID]["cmd"]
    assert L.is_echo_cmd(cmd), f"gpu/{NEW_ID} is not an echo: {cmd!r}"
    assert NEW_ID in cmd, f"gpu/{NEW_ID} echo must be id-prefixed: {cmd!r}"
    assert "${" not in cmd and "--fit" not in cmd and "-ot" not in cmd, (
        f"gpu/{NEW_ID} echo resolved content: {cmd!r}"
    )


@helm
def test_c03_chart_default_render_keeps_the_rung_echo_only():
    """`enabled: false` chart-side: the bare chart render (no service overlay)
    must not gain a RUNNABLE heretic rung. Absence is not the chart's mechanism
    for that — CR1.4/P5 renders every catalog id, enabled or not, as the standard
    id-prefixed fail-fast echo (test_boot_safety documents the default render as
    entirely echo entries), so the executable law is echo-shaped and
    macro-free."""
    models = L.all_models_of(L.rendered_config_default())
    entry = models.get(NEW_ID)
    assert entry, (
        f"chart default render has no {NEW_ID} entry at all — the catalog lost it "
        "(P5 superset law: every catalog id renders everywhere)"
    )
    cmd = entry.get("cmd") or ""
    assert L.is_echo_cmd(cmd), f"chart default render makes {NEW_ID} runnable: {cmd!r}"
    assert NEW_ID in cmd, f"chart default render/{NEW_ID} echo is not id-prefixed: {cmd!r}"
    assert "${" not in cmd and "--fit" not in cmd and "-ot" not in cmd, (
        f"chart default render/{NEW_ID} echo resolved content: {cmd!r}"
    )


# --- liveness (gated like the existing hf checks) ----------------------------


@hf_gated
def test_c03_hf_pack_resolves_live():
    """Registry evidence for AC5: the gate-verified repo:quant must resolve
    through the llama.cpp loader mirror (runs in review under RUN_HF_CHECK=1)."""
    import hf_check

    refs = [("gpu-ai", NEW_ID, "-hf", L.CF86_HF_REFS[NEW_ID]),
            ("gpu-ai", "qwen38-heretic", "-hf", L.CF86_HF_REFS["qwen38-heretic"])]
    problems = hf_check.collect_problems(refs)
    assert not problems, "cf-86 -hf refs failed to resolve:\n" + "\n".join(problems)


# Source-gate byte evidence, read from the HF tree API on 2026-10-30 with no
# credential (spiritfather's republication is ungated — that is why this pack
# needs no token leg, unlike the C02 orca fetch). Pinned so a re-upload or a
# repo re-organization turns red instead of silently changing the ~130.8 GiB of
# weights the node pulls:
#   Q4_K_M/Qwen3.8-Flash-Next-heretic-2-Q4_K_M-0000N-of-00005.gguf  (N = 1..5)
#   mtp/mtp-Qwen3.8-Flash-Next-heretic-2-Q8_0.gguf                  (the named draft)
# Recorded at the same read, NOT asserted as a law: Q4_K_M/MTP/ holds only
# shards 1+6 of 6 and its files carry an uppercase "-MTP-", which defeats
# hf_check's case-sensitive "-mtp-" skip while the HF listing sorts that
# directory ahead of the trunk — llama.cpp's find_best_model takes the first
# case-insensitive Q4_K_M[.-] hit, so the on-target pick needs verification
# (C03 dev recorded the same hazard; the chunk's AC5 asks existence only).
HERETIC_REPO = "spiritfather/Qwen3.8-Flash-Next-heretic-2-GGUF"
HERETIC_TRUNK_BYTES = [10945472, 682434912, 54400261312, 47643214976, 37673027808]
HERETIC_TRUNK_TOTAL = 140409884480
HERETIC_DRAFT_BYTES = 4137429280


@hf_gated
def test_c03_hf_pack_bytes_still_match_the_source_gate():
    """Churn guard for AC5's source gate: the Q4_K_M trunk must stay a complete
    1..5 shard set at the pinned per-shard sizes, and the draft sidecar the gate
    named must still exist at its pinned size (a silently resized pack is a
    different model)."""
    shards = _shards_by_index(_tree(HERETIC_REPO, "Q4_K_M"))
    assert sorted(shards) == list(range(1, 6)), (
        f"Q4_K_M trunk is no longer a complete 1..5 set: {sorted(shards)}"
    )
    assert [shards[i] for i in range(1, 6)] == HERETIC_TRUNK_BYTES, (
        f"Q4_K_M shard sizes changed — re-run the source gate and re-pin here: "
        f"{[shards.get(i) for i in range(1, 6)]}"
    )
    assert sum(shards.values()) == HERETIC_TRUNK_TOTAL, (
        f"trunk total {sum(shards.values())} != gate-verified {HERETIC_TRUNK_TOTAL} (130.8 GiB)"
    )
    draft = {
        f["path"]: f.get("size") or (f.get("lfs") or {}).get("size")
        for f in _tree(HERETIC_REPO, "mtp")
        if f["path"].endswith(".gguf")
    }
    assert list(draft.values()) == [HERETIC_DRAFT_BYTES], (
        f"mtp/ draft sidecar set changed — the two-gate precedent re-pins through the test session: {draft}"
    )


def _shards_by_index(entries: list) -> dict:
    """Shard number -> byte size for a split GGUF listing (…-0000N-of-0000M.gguf)."""
    out = {}
    for f in entries:
        m = re.search(r"-(\d{5})-of-\d{5}\.gguf$", f["path"])
        if m:
            out[int(m.group(1))] = f.get("size") or (f.get("lfs") or {}).get("size")
    return out


def _tree(repo: str, path: str = "") -> list:
    """Anonymous HF tree listing (stdlib only). Sends no Authorization header on
    purpose: an ungated pack's evidence must stay re-checkable without a token,
    and an arm that sent one could not tell a public repo from a gated one."""
    url = f"https://huggingface.co/api/models/{repo}/tree/main" + (f"/{path}" if path else "")
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.loads(resp.read())
