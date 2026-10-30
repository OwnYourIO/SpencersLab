# cf-86 C04 — the 27B heretic Q4_K_M(-mtp) llama.cpp rung in the existing
# qwen38 ablation family (plan 2026/2026-10-cf-86-feat-more-strata-models,
# chunks/C04.md AC1-AC6).
#
# Red posture pre-dev: id/cmd/matrix needles RED. The regime-difference arm is
# the interesting one: this rung is DENSE (q38-common: -ngl 999, --load-mode
# none, -np 1) while C03's flash-next heretic is MoE-mmap (-ngl 99, -ot, --fit
# off). Asserting both sides of that difference is what proves the two rungs
# were keyed to the right memory law instead of copy-pasted.
#
# The -hf ref is the source-gate literal (CF86_HF_REFS: 0bserverx pack, Q4_K_M
# with embedded MTP per RESEARCH [S22]). Live arms under RUN_HF_CHECK=1: ref
# resolution in test_heretic_rungs_flashnext.py::test_c03_hf_pack_resolves_live
# (both cf-86 refs in one network pass), byte pins and the loader-pick guard here.
#
# Message class: every red before C04 lands names C04 (the guards in _cmd/_model
# and the explicit asserts), never a bare KeyError. In a count-only residual map
# an arm that dies on KeyError is indistinguishable from suite breakage — the
# C02 round proved that costs a dev round to untangle.

from __future__ import annotations

import os

import pytest

import llama_swap_testlib as L
import strata_testlib as S

NEW_ID = "qwen38-heretic"
SIBLING_ID = "qwen38-ara"

_ok, _reason = L.helm_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)


def _ai():
    return L.rendered_config("gpu-ai")


def _cmd() -> str:
    cfg = _ai()
    models = L.all_models_of(cfg)
    assert NEW_ID in models, f"gpu-ai render has no {NEW_ID} — C04 not landed"
    return L.effective_cmd(cfg, NEW_ID)


def _model() -> dict:
    models = L.all_models_of(_ai())
    assert NEW_ID in models, f"gpu-ai render has no {NEW_ID} — C04 not landed"
    return models[NEW_ID]


# --- AC1: the rung and its dense regime -------------------------------------


@helm
def test_c04_rung_expands_to_the_frozen_id():
    """`qwen38` family + `heretic` rung key = exactly `qwen38-heretic`; the
    ara/rana/humanlike siblings stay themselves (the naming-honesty note: this
    rung is the 0bserverx uncensored Q4_K_M build, not heretic-ara)."""
    models = L.all_models_of(_ai())
    assert NEW_ID in models, f"gpu-ai render has no {NEW_ID} — C04 not landed"
    near = sorted(m for m in models if m.startswith("qwen38-heretic"))
    assert near == [NEW_ID], f"heretic rung expanded to {near}, want exactly [{NEW_ID}]"
    name = str(models[NEW_ID].get("name") or "")
    assert "ara" not in name.lower(), f"{NEW_ID} display name blurs the heretic-ara sibling: {name!r}"


@helm
def test_c04_dense_regime_and_256k_ctx():
    """q38-common's dense legs, byte-present, plus the -c 262144 sibling
    grammar — and the MoE/mmap legs ABSENT (that absence is the memory-law
    proof against C03's mmap rung)."""
    cmd = _cmd()
    sibling = L.effective_cmd(_ai(), SIBLING_ID)
    for leg in ("-ngl 999", "--load-mode none", "-np 1"):
        assert leg in sibling, f"q38 sibling {SIBLING_ID} no longer carries {leg!r} — re-pin this file"
        assert leg in cmd, f"{NEW_ID} missing the dense-regime leg {leg!r}"
    assert "-c 262144" in cmd, f"{NEW_ID} lacks the 256k ctx leg the q38 rungs use"
    for leg in (L.CF86_MOE_OFFLOAD_LEG, "--fit off", "--load-mode mmap"):
        assert leg not in cmd, f"{NEW_ID} carries the MoE/mmap leg {leg!r} — dense rung keyed to the wrong regime"


@helm
def test_c04_hf_ref_is_the_gate_verified_pack_with_embedded_mtp():
    """Embedded MTP (the pack file is named -mtp), so no `-hfd` draft sidecar:
    draft-mtp n-max 2 per the gate, and a borrowed draft would be a churn
    hazard the siblings document."""
    cmd = _cmd()
    assert L.cmd_flag_value(cmd, "-hf") == L.CF86_HF_REFS[NEW_ID], (
        f"-hf {L.cmd_flag_value(cmd, '-hf')!r} != gate-verified {L.CF86_HF_REFS[NEW_ID]!r}"
    )
    assert L.cmd_flag_value(cmd, "-hfd") is None, (
        f"{NEW_ID} points at an external MTP draft despite an embedded -mtp pack"
    )
    assert "--spec-type draft-mtp" in cmd and "--spec-draft-n-max 2" in cmd, (
        f"{NEW_ID} MTP spec missing or not n-max 2: {cmd!r}"
    )


@helm
def test_c04_ttl_matches_dense_siblings():
    assert _model().get("ttl") == 300, f"{NEW_ID} ttl = {_model().get('ttl')!r}, siblings use 300"


# --- AC2: matrix law — main dense alternation only ---------------------------


@helm
def test_c04_q38her_var_and_main_membership():
    cfg = _ai()
    vars_ = (cfg.get("matrix") or {}).get("vars") or {}
    assert vars_.get("q38her") == NEW_ID, f"matrix.vars.q38her = {vars_.get('q38her')!r}"
    sets = S.matrix_expansions(cfg)
    assert any(NEW_ID in c for c in sets.get("main", [])), f"{NEW_ID} is not in sets.main"
    assert not any(NEW_ID in c for c in sets.get("solo", [])), (
        f"{NEW_ID} joined sets.solo — the ~17 GB dense class rides the main-set trio budget, "
        "and soloing it silently changes what the trio math budgets"
    )


@helm
def test_c04_never_two_dense_rungs_in_one_combo():
    """The trio math assumes ONE dense resident per combo. Dense class is
    identified by its regime leg (-np 1) so the law survives rung churn."""
    cfg = _ai()
    models = L.all_models_of(cfg)
    dense_ids = {mid for mid, m in models.items() if "-np 1" in L.effective_cmd(cfg, mid)}
    assert NEW_ID in dense_ids, (
        f"{NEW_ID} carries no dense-regime leg (-np 1) — C04 not landed or keyed to the wrong regime"
    )
    for name, combos in S.matrix_expansions(cfg).items():
        for combo in combos:
            clash = combo & dense_ids
            assert len(clash) <= 1, f"matrix set {name!r} co-loads dense rungs {sorted(clash)}"


@helm
def test_c04_no_preload_and_no_models_layer_entry():
    """AC1/Notes: the rung rides the chart-side family — gpu-ai needs no
    models-layer entry, and nothing may preload it."""
    cfg = _ai()
    preload = ((cfg.get("hooks") or {}).get("on_startup") or {}).get("preload") or []
    assert preload == L.C04_PRELOAD_PINNED, f"gpu-ai preload changed: {preload}"
    svc = L.service_overlay("gpu-ai")
    assert NEW_ID not in ((svc.get("config") or {}).get("models") or {}), (
        f"services/gpu-ai carries a models-layer entry for {NEW_ID} — C04 expects none"
    )


# --- AC1/AC4: gpu side --------------------------------------------------------


@helm
def test_c04_gpu_render_echoes_the_rung():
    """The qwen38 family is gpu-ai-local, so on gpu the new id must be the
    standard fail-fast echo — never a live dense rung competing with the gpu
    box's own trio."""
    models = L.all_models_of(L.rendered_config("gpu"))
    assert NEW_ID in models, f"gpu render lacks the {NEW_ID} echo (P5 superset law)"
    cmd = models[NEW_ID]["cmd"]
    assert L.is_echo_cmd(cmd) and NEW_ID in cmd, f"gpu/{NEW_ID} echo wrong shape: {cmd!r}"
    assert "${" not in cmd and "-ngl" not in cmd, f"gpu/{NEW_ID} echo resolved content: {cmd!r}"


@helm
def test_c04_rana_escape_hatch_stays_the_only_new_raw_cmd():
    """C04's Notes forbid touching rana's raw-cmd escape hatch; the schema suite
    owns the exact escape-hatch set, so this arm only pins that C04 introduces
    no second one (a raw cmd bypasses every family-composition arm in this
    file)."""
    cfg = _ai()
    raw = {mid for mid, m in L.all_models_of(cfg).items() if "curl" in str(m.get("cmd") or "")}
    assert raw <= {"qwen38-rana", "whisper-large-v3"}, (
        f"raw-cmd (curl) entries beyond the documented escape hatches: {sorted(raw)}"
    )


# --- AC5: source-gate byte evidence + loader-pick churn (gated) --------------

hf_gated = pytest.mark.skipif(
    os.environ.get("RUN_HF_CHECK") != "1",
    reason="evidence gate: RUN_HF_CHECK=1 re-reads the C04 pack and re-derives the cf-86 loader picks",
)

# Read 2026-10-30 from the HF tree API with no credential (repo reports
# gated: False, so this pack needs no token leg). The layout is flat and
# single-file: RVN-Q4_K_M-mtp.gguf carries the MTP head IN MODEL, which is why
# C04 has no draft: sidecar and no split-family exposure.
C04_REPO = "0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF"
C04_PACK_BYTES = 16998720736  # RVN-Q4_K_M-mtp.gguf — the ref's target (~17.0 GB, RESEARCH [S22])
C04_PLAIN_BYTES = 16547399968  # RVN-Q4_K_M.gguf — what the ref resolves to WITHOUT -mtp


@hf_gated
def test_c04_hf_pack_bytes_still_match_the_source_gate():
    """Churn guard for AC5's source gate: a re-upload or a re-ladder turns red
    instead of silently changing the ~17.0 GB the node pulls. Both files are
    pinned because the size difference between them is what makes the `-mtp`
    suffix load-bearing — a suffix-less ref resolves to other weights."""
    sizes = {e["path"]: e["size"] for e in L.hf_tree(C04_REPO)}
    assert sizes.get("RVN-Q4_K_M-mtp.gguf") == C04_PACK_BYTES, (
        f"RVN-Q4_K_M-mtp.gguf is {sizes.get('RVN-Q4_K_M-mtp.gguf')!r}, not the gate-verified "
        f"{C04_PACK_BYTES} — re-run the source gate and re-pin CF86_HF_REFS via the test session"
    )
    assert sizes.get("RVN-Q4_K_M.gguf") == C04_PLAIN_BYTES, (
        f"RVN-Q4_K_M.gguf is {sizes.get('RVN-Q4_K_M.gguf')!r}, not {C04_PLAIN_BYTES} — the "
        "sibling that separates an embedded-MTP ref from a plain one moved"
    )


# Loader-ORDERING churn guard: the byte arms and hf_check's liveness pass only
# ask whether the ref RESOLVES. The pick rule lives in llama.cpp's downloader
# (mirrored by llama_swap_testlib.hf_pick/hf_split_family, cited there), and it
# can land the loader on a partial split family while every chart-side arm stays
# green — that is how cf-86 C03's heretic-2 ref resolves to a 2-of-6 pair (C03
# review finding, runbook-handled). Pinning each ref's current pick keeps a
# silently re-organized tree red in either direction.
C03_ID = "qwen3.8-flash-next-heretic-q4"
C03_PACK_PICK = {
    "pick": "Q4_K_M/MTP/Qwen3.8-Flash-Next-heretic-2-Q4_K_M-MTP-00001-of-00006.gguf",
    "family": [
        "Q4_K_M/MTP/Qwen3.8-Flash-Next-heretic-2-Q4_K_M-MTP-00001-of-00006.gguf",
        "Q4_K_M/MTP/Qwen3.8-Flash-Next-heretic-2-Q4_K_M-MTP-00006-of-00006.gguf",
    ],
    "shards_declared": 6,
}


@hf_gated
def test_c04_hf_pick_resolves_to_a_complete_file_set():
    """`qwen38-heretic`'s ref must keep picking a COMPLETE file set (a single
    file, or a split family whose every declared shard exists). The same rule
    run against C03's ref at authoring time is what would have caught its
    hazard; today that pick is pinned as the known-broken shape
    (C04_PACK_PICK), so an upstream fix or a re-shuffle goes red and re-pins
    through the test session instead of quietly changing what the loader pulls."""
    problems = []
    for mid in L.CF86_NEW_IDS:
        ref = L.CF86_HF_REFS[mid]
        repo, _, tag = ref.rpartition(":")
        entries = L.hf_tree(repo)
        paths = [e["path"] for e in entries]
        picked = L.hf_pick(paths, tag)
        if picked is None:
            problems.append(f"{mid}: -hf {ref} matches no model file under the loader's pick rule")
            continue
        family = L.hf_split_family(paths, picked)
        declared = L.hf_split_info(picked)[2]
        if mid == C03_ID:
            if picked != C03_PACK_PICK["pick"] or family != C03_PACK_PICK["family"]:
                problems.append(
                    f"{mid}: pick/family changed from the runbook-pinned broken shape "
                    f"(pick {picked!r}, family {family}) — the tree moved; re-pin via the test "
                    "session and tell coord whether the C03 runbook note can go"
                )
            continue
        if declared > 1 and len(family) != declared:
            problems.append(
                f"{mid}: -hf {ref} picks {picked!r} from a {declared}-shard family but only "
                f"{len(family)} shards exist: {family}"
            )
    assert not problems, "cf-86 loader pick outside its pinned shape:\n" + "\n".join(problems)
