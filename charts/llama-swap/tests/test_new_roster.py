# C04 new-roster contract: the approved ID table (DECISIONS 2026-10-22 "Plan
# approval" — long-form IDs + user-approved 7-entry 35B ladder) must appear in
# the per-cluster renders with the exact -hf/-hfd refs, the placement rules
# (solo / main / absent-from-matrix), the gpu tuned/disabled treatments, and
# zero disturbance to the pre-existing surface (guarded by the immutable C02
# parity tests).
#
# ALL ID-presence tests are RED at write time for the right reason: none of
# these models exist in today's values (golden sets are 40 / 55 — pinned by
# test_config_parity). The matrix-closure test is green today and must stay
# green (standing invariant, C04 acceptance 3).
#
# REPLAN rebase (amendment J, 2026-10-24): the gpu isolation bar FLIPS from
# "gpu-ai-only IDs absent" to "present as catalog echoes" (CR2/CA1); exact-set
# now equals the frozen 58-ID CATALOG (P1-consistent); -hf ref routing is the
# generalized B/D shape-pattern (echo on the primary cluster -> cross-read a
# live one), which the enablement matrix makes deterministic.
#
# Deliberately NOT asserted (C04 makes implementation-time header checks with
# two outcomes, so any hard assert here would be wrong for one branch):
# orca-q6 embedded-MTP resolution (only its first-cut ABSENCE is pinned, see
# §8), 122B MTP via
# prithivMLmods (filename regex verification), the `-ot` expert-offload regex
# FIT itself (the plan allows a `fn-moe` macro substitute — flash-next tests
# accept either `${moe}`/`${fn-moe}` reference or an emitted `-ot` token).
# Those findings land in chunks/C04.md Review notes / the chunk itself.

from __future__ import annotations

import re

import pytest

import llama_swap_testlib as L

_ok, _reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_reason)

FLASHNEXT = ["qwen3.8-flash-next-q3", "qwen3.8-flash-next-q4",
             "qwen3.8-flash-next-q5", "qwen3.8-flash-next-q6"]
FLASHNEXT_ORCA = "qwen3.8-flash-next-orca-q6"
ORNITH_122B = ["ornith-1.5-122b-q3", "ornith-1.5-122b-q4",
               "ornith-1.5-122b-q5", "ornith-1.5-122b-q6"]
LADDER = L.C04_LADDER_35B_IDS
GPU_AI_ONLY = FLASHNEXT + [FLASHNEXT_ORCA] + ORNITH_122B

_DISABLED_SHAPE = re.compile(r'^/bin/sh -c "echo \'.*\' >&2; exit 1"\n?$')


def models(cluster: str) -> dict:
    return L.all_models_of(L.rendered_config(cluster))


# ---------------------------------------------------------------------------
# Acceptance 1: roster completeness vs the approved table (exact sets)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("cluster", ["gpu", "gpu-ai"])
def test_c04_1_roster_is_exactly_golden_plus_approved_table(cluster):
    """P1-consistent roster completeness (amendment J: expected set re-based
    from golden+approved-C04 to the frozen REPLAN CATALOG — CA2/CA3 own the
    conversion and removals)."""
    fresh = set(models(cluster))
    assert fresh == set(L.CATALOG_IDS), (
        f"{cluster}: roster diverges from the frozen CATALOG — "
        f"missing {sorted(set(L.CATALOG_IDS) - fresh)}, "
        f"unexpected {sorted(fresh - set(L.CATALOG_IDS))} (awaiting CA2/CA3)"
    )


@pytest.mark.parametrize("mid,ref", sorted(L.C04_HF_REFS.items()))
def test_c04_1_exact_hf_ref_per_approved_id(mid, ref):
    """Each approved ID's cmd carries the exact `-hf repo:TAG` pair re-verified
    against the HF API (C04 task 1 attaches the script output to the chunk;
    hf_check.py / the gated HF test re-runs it).

    An entry rendered fail-fast (`-bf16 -> disabled:` on gpu, per the plan) has
    no -hf token in that cluster by design — the ratified disabled-shape
    contract and this ref contract would otherwise be mutually unsatisfiable
    (coord-routed defect D amendment, 2026-10-23; same class as ratified B;
    generalized to the ENABLEMENT table by amendment J). Its ref is cross-read
    from the live cluster; presence + echo shape stay pinned by
    test_c04_1_35b_bf16_gpu_disabled_failfast and P5."""
    # Amendment J: routing generalized from D (fixed gpu-ai fallback) to the
    # enablement table — read from the cluster where the rung is ENABLED
    # (exactly one exists for every approved ID per ENABLEMENT), so the
    # CA2 echo-flip can never make this assertion ambiguous.
    live = [c for c in ("gpu", "gpu-ai") if mid in set(L.ENABLEMENT[c]["enabled"])]
    assert live, f"{mid}: approved id enabled on no cluster — ENABLEMENT table drift"
    m = models(live[0]).get(mid)
    assert m is not None, (
        f"{mid}: not rendered on its enabled cluster {live[0]} — awaiting CA2/CA3"
    )
    assert not L.is_echo_cmd(m["cmd"]), f"{live[0]}/{mid}: enabled rung rendered as echo"
    assert L.cmd_flag_value(m["cmd"], "-hf") == ref, (
        f"{mid}: -hf is {L.cmd_flag_value(m['cmd'], '-hf')!r}, approved ref is {ref!r}"
    )


def test_c04_1_flashnext_mtp_draft_wired():
    """ACCEPTANCE C03-1 (GATE-2 RE-EXPRESSION 2026-10-26 — TEST_SPEC §8.2):
    the two-gate path ran its full course — first cut MTP-off (DECISIONS
    2026-10-26), no-MTP load proved journal-clean (EVIDENCE.md §13.2-4), and
    gate 2 re-added the sidecar draft at family level (chart commit
    eb0a0cf92). The name again describes the contract, as it did on the prior
    ticket: -hfd pinned to C04_FLASHNEXT_DRAFT with the draft-mtp spec block
    on q3/q4/q5/q6; orca-q6 carries the spec alone (embedded MTP —
    publisher convention, probe-on-miss per values.yaml; deliberately NOT
    asserting which resolves at runtime). The expert-offload leg stays
    required (AC1 disjunction, checked on the EXPANDED cmd so any sanctioned
    macro name passes)."""
    cfg = L.rendered_config("gpu-ai")
    m = L.all_models_of(cfg)
    for mid in FLASHNEXT + [FLASHNEXT_ORCA]:
        cmd = m[mid]["cmd"]
        hfd = L.cmd_flag_value(cmd, "-hfd")
        if mid == FLASHNEXT_ORCA:
            assert hfd is None, (
                f"{mid}: renders a standalone -hfd draft — orca's gate-2 shape is embedded-MTP + spec only; "
                "wiring the sidecar changes the contract (re-home via the test session)"
            )
        else:
            assert hfd == L.C04_FLASHNEXT_DRAFT, (
                f"{mid}: -hfd is {hfd!r}, gate-2 sidecar ref is {L.C04_FLASHNEXT_DRAFT!r}"
            )
        assert L.cmd_flag_value(cmd, "--spec-type") == "draft-mtp", (
            f"{mid}: spec-type is {L.cmd_flag_value(cmd, '--spec-type')!r}, gate-2 contract is 'draft-mtp'"
        )
        assert L.cmd_flag_value(cmd, "--spec-draft-n-max") == "2", (
            f"{mid}: draft_n_max is {L.cmd_flag_value(cmd, '--spec-draft-n-max')!r}, gate-2 spec block carries 2"
        )
        etoks = set(L.cmd_tokens(L.effective_cmd(cfg, mid)).elements())
        assert etoks & {"-ot", "--n-cpu-moe"}, (
            f"{mid}: no expert-offload leg in the expanded cmd — AC1 requires the "
            '-ot "\\.ffn_.*_exps\\.=CPU" regex or the justified --n-cpu-moe substitute'
        )


def test_c04_1_gpu_ai_only_families_present_as_echo_on_gpu():
    """CA1 ISOLATION FLIP (user-requested CR2 consequence): gpu-ai-only
    catalog rungs are now PRESENT on gpu as fail-fast echoes (routable,
    instant-exit), not absent. orcarouter HF_TOKEN-gating stays a runtime
    concern — the echo never downloads. Red at CA1 handoff: gpu still lacks
    these IDs entirely (awaiting CA2 catalog)."""
    gpu = models("gpu")
    missing = [mid for mid in GPU_AI_ONLY if mid not in gpu]
    assert not missing, (
        f"gpu render lacks the catalog echo entries {missing} — CA2 not landed"
    )
    for mid in GPU_AI_ONLY:
        assert L.is_echo_cmd(gpu[mid]["cmd"]) and mid in gpu[mid]["cmd"], (
            f"gpu/{mid}: expected fail-fast echo shaped for the off-cluster rung, got {gpu[mid]['cmd']!r}"
        )


# ---------------------------------------------------------------------------
# Acceptance 1: matrix placement + preload discipline
# ---------------------------------------------------------------------------


def test_c04_1_flashnext_matrix_placement():
    """q3/q4 -> solo; q5/q6 -> NO set at all (run-alone semantics: a model in
    no matrix set can only run alone — user-accepted OOM-churn risk,
    DECISIONS). Asserting absence from every set is the loadable encoding of
    'never swapped in under a co-residency promise'."""
    cfg = L.rendered_config("gpu-ai")
    sets = L.matrix_all_sets(cfg)
    members = {name: ids for name, ids in sets.items()}
    solo = members.get("solo", set())
    for mid in ["qwen3.8-flash-next-q3", "qwen3.8-flash-next-q4"]:
        assert mid in solo, f"{mid}: expected in the solo set"
    for mid in ["qwen3.8-flash-next-q5", "qwen3.8-flash-next-q6"]:
        in_sets = [name for name, ids in members.items() if mid in ids]
        assert not in_sets, f"{mid}: must be in NO matrix set, found in {in_sets}"


def test_c04_1_orca_and_122b_solo():
    solo = L.matrix_member_ids(L.rendered_config("gpu-ai"), "solo")
    for mid in [FLASHNEXT_ORCA] + ORNITH_122B:
        assert mid in solo, f"{mid}: expected in the solo set (over-budget for co-residency)"


def test_c04_1_35b_ladder_matrix_membership():
    """gpu-ai: iq2xxs..q8 join the main MoE alternation, bf16 -> solo.
    gpu (chart matrix): main alternation += all seven (bf16 renders the
    disabled echo on gpu — same pattern as the kat-coder entries there)."""
    ai = L.rendered_config("gpu-ai")
    ai_main = L.matrix_member_ids(ai, "main")
    ai_solo = L.matrix_member_ids(ai, "solo")
    for mid in LADDER:
        if mid.endswith("-bf16"):
            assert mid in ai_solo and mid not in ai_main, f"gpu-ai/{mid}: expected solo-only"
        else:
            assert mid in ai_main, f"gpu-ai/{mid}: expected in the main set"
    gpu_main = L.matrix_member_ids(L.rendered_config("gpu"), "main")
    for mid in LADDER:
        assert mid in gpu_main, f"gpu/{mid}: expected in the chart main alternation"


def test_c04_1_no_new_model_preloaded():
    """C04 task: preload unchanged — no new model rides boot."""
    cfg = L.rendered_config("gpu-ai")
    preload = ((cfg.get("hooks") or {}).get("on_startup") or {}).get("preload") or []
    assert preload == L.C04_PRELOAD_PINNED, f"gpu-ai preload changed: {preload}"
    new_ids = set(L.C04_NEW_IDS["gpu-ai"]) | set(L.C04_NEW_IDS["gpu"])
    assert not new_ids & set(preload)


# ---------------------------------------------------------------------------
# Acceptance 1: per-entry treatments (ttl, capabilities, gpu tune/disable)
# ---------------------------------------------------------------------------


def test_c04_1_big_family_ttl_300_and_ladder_ttl_0():
    m = models("gpu-ai")
    for mid in GPU_AI_ONLY:
        assert m[mid].get("ttl") == 300, f"{mid}: plan pins ttl 300 (evict-friendly), got {m[mid].get('ttl')!r}"
    for cluster in ("gpu", "gpu-ai"):
        for mid in LADDER:
            # amendment J note: ttl survives the echo flip as a passthrough
            # field — the gpu bf16 echo keeps its ttl: 0 from C04 behavior.
            m = models(cluster).get(mid)
            assert m is not None, f"{cluster}/{mid}: not rendered (awaiting CA2)"
            assert m.get("ttl") == 0, (
                f"{cluster}/{mid}: chart-pattern ttl 0 (never idle-unload), got {m.get('ttl')!r}"
            )


def test_c04_1_vision_capabilities_declared():
    """flash-next (mmproj everywhere) and the 35B ladder (mmproj-BF16 in the
    official repo) declare vision input; the gpu-bf16 entry is fail-fast so
    its capabilities ride from the chart unchanged but load is disabled."""
    for mid in FLASHNEXT + [FLASHNEXT_ORCA]:
        caps = (models("gpu-ai")[mid].get("capabilities") or {}).get("in") or []
        assert "image" in caps, f"{mid}: capabilities.in lacks image"
    for mid in LADDER:
        if mid.endswith("-bf16"):
            continue  # gpu override sets description+disable; chart keeps the rest
        caps = (models("gpu-ai")[mid].get("capabilities") or {}).get("in") or []
        assert "image" in caps, f"gpu-ai/{mid}: capabilities.in lacks image"


def test_c04_1_35b_q6_q8_gpu_tuned_regime():
    """gpu service block gives -q6/-q8 the evidence-backed 8-GiB treatment
    copied from qwen3.6-35b-a3b-q8: --no-mmproj, ctx 262144, -b 2048,
    -ub 1024, ${moe}, ${flash-and-q8}, --cache-reuse 256, -np 1."""
    for mid in ["ornith-1.5-35b-a3b-q6", "ornith-1.5-35b-a3b-q8"]:
        cmd = models("gpu")[mid]["cmd"]
        toks = L.cmd_tokens(cmd)
        assert "--no-mmproj" in toks, f"gpu/{mid}: tuned regime missing --no-mmproj"
        for flag, val in [("-ub", "1024"), ("--cache-reuse", "256"), ("-np", "1")]:
            got = L.cmd_flag_value(cmd, flag)
            assert got == val, f"gpu/{mid}: tuned regime {flag} -> {got!r}, expected {val!r}"
        # 256k context may arrive as the literal pair or via the ctx-256k
        # macro reference (llama-swap expands at load to the same stream).
        if "${ctx-256k}" not in toks:
            assert L.cmd_flag_value(cmd, "--ctx-size") == "262144", f"gpu/{mid}: 256k ctx missing"
        L.render_macro_or_literal(cmd, "moe",
                                  ("-ngl", "99", "-ot", "\\.ffn_.*_exps\\.=CPU", "--load-mode", "none"))
        L.render_macro_or_literal(cmd, "flash-and-q8",
                                  ("--flash-attn", "on", "--cache-type-k", "q8_0", "--cache-type-v", "q8_0"))


def test_c04_1_35b_bf16_gpu_disabled_failfast():
    """`-bf16` -> `disabled:` fail-fast with a measured reason on gpu — the ID
    stays routable (a loadable model that exits 1 with a logged reason beats
    a 404), mirroring the six existing DISABLED entries."""
    m = models("gpu")["ornith-1.5-35b-a3b-bf16"]
    cmd = m["cmd"]
    assert _DISABLED_SHAPE.match(cmd.strip()), f"gpu bf16 not in fail-fast shape: {cmd!r}"
    assert "ornith-1.5-35b-a3b-bf16" in cmd and "disabled" in cmd
    assert "8GiB" in cmd or "8 GiB" in cmd, "reason must carry the measured box constraint"


# ---------------------------------------------------------------------------
# Acceptance 3: matrix closure (standing invariant on the enlarged roster)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("cluster", ["gpu", "gpu-ai"])
def test_c04_3_matrix_closure_after_additions(cluster):
    L.assert_matrix_closure(L.rendered_config(cluster), cluster)
