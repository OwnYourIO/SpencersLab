# C04 verification contract (ticket 2026/2026-10-debug-flash-next-vulkan-oom,
# chunks/C04.md AC1-5). Two layers, per the chunk's Tests section ("review
# re-runs criteria 1-5 read-only against recorded artifacts when it cannot
# observe the live window"):
#
#  A) PROCEDURE AUDIT (hard, green at write time): evidence/
#     c04_verification_procedure.yaml is the frozen procedure - these tests
#     prove it names every control BEFORE anyone runs it, so a dev/review pass
#     cannot quietly narrow a grep set or drop the freeze protocol.
#  B) ATTEMPT RECORD (evidence-gated): validators over the EVIDENCE.md
#     post-fix section. Skipped until the section exists (C04 is post-merge
#     work - TEST_SPEC §4 gate style); once present every check is HARD.
#
# The record validators assert the CONTRACT shape (all four journal patterns
# zero-matched, single attempt, MTP disjunction), never outcome values a C01
# result could legitimately change (coord scope note; e.g. branch B's
# booted-values step is conditional by design).

from __future__ import annotations

import os
import re
from pathlib import Path

import pytest
import yaml

import llama_swap_testlib as L

PROC_PATH = L.TESTS_DIR / "evidence" / "c04_verification_procedure.yaml"
PROC = yaml.safe_load(PROC_PATH.read_text())

# Same artifact path (and same FLASHNEXT_EVIDENCE override for satisfiability
# self-tests) as test_c01_evidence.py - C04 appends its post-fix section there.
EVIDENCE = Path(os.environ.get(
    "FLASHNEXT_EVIDENCE",
    L.REPO_ROOT / ".agents/plans/2026/2026-10-debug-flash-next-vulkan-oom/EVIDENCE.md",
))

REQUIRED_JOURNAL_PATTERNS = [
    "amdgpu_vm_validate", "BO_VA", "command submission", "ring .* timeout",
]


def _step(step_id: str) -> dict:
    for s in PROC["steps"]:
        if s["id"] == step_id:
            return s
    pytest.fail(f"procedure lost step {step_id!r} - the contract itself regressed")


# --- A) procedure self-audit --------------------------------------------------


def test_c04_procedure_journal_pattern_set_exact():
    """AC2 widened set (RESEARCH §1.1 + the ring-timeout class): exactly these
    four, no narrower - the 2026-10-18/19 freeze signature must be grep-proven
    absent in full."""
    assert set(PROC["journal_clean_patterns"]) == set(REQUIRED_JOURNAL_PATTERNS), (
        f"procedure journal patterns {PROC['journal_clean_patterns']} diverge from the "
        f"AC2 set {REQUIRED_JOURNAL_PATTERNS}"
    )


def test_c04_procedure_freeze_protocol_intact():
    p = PROC["protocol"]
    for key in ("one_attempt_per_variable_change", "retry_loops_forbidden",
                "operator_consent_required_before_attempt",
                "solo_rung_trio_eviction_scheduled", "kernel_params_untouched"):
        assert p.get(key) is True, (
            f"protocol.{key} must be true - operator-accepted one-attempt freeze protocol "
            "(DECISIONS 2026-10-22 + 2026-10-26); the protocol IS the control on a single-node box"
        )


def test_c04_procedure_shell_steps_are_user_run():
    """No agent may hold a pod/host exec step (repo rule: MCP grants no exec):
    every step carrying shell `commands` is run_by: user."""
    offenders = [s["id"] for s in PROC["steps"] if s.get("commands") and s.get("run_by") != "user"]
    assert not offenders, f"steps with shell commands not marked user-run: {offenders}"


def test_c04_procedure_forbids_kernel_mutation():
    blob = yaml.safe_dump(PROC)
    assert not re.search(r"(?:echo[^|\n]*>|\btee\b)[^|\n]*/sys/", blob), (
        "procedure must contain no /sys write - kernel params stay untouched in every branch (AC3)"
    )
    prefill = _step("long-prefill-probe")
    assert "lockup_timeout" in prefill["forbidden"], (
        "the ring-timeout mitigation rule must name lockup_timeout as forbidden; "
        "mitigations are llama-side (GGML_VK_MAX_NODES_PER_SUBMIT / -ub)"
    )
    assert "GGML_VK_MAX_NODES_PER_SUBMIT" in prefill["on_ring_timeout"] and "-ub" in prefill["on_ring_timeout"], (
        "on_ring_timeout must specify the llama-side mitigations (chunk task: env and/or -ub 512)"
    )


def test_c04_procedure_fingerprint_check_contract():
    """The visual proof the pinned regime was left: experts under CPU_Mapped,
    Vulkan_Host near zero, vs C01's recorded pre-fix split - and a mismatch
    stops without retry."""
    fp = _step("live-log-watch")["fingerprint_expect"]
    assert "CPU_Mapped" in fp["experts_placement"] and "near zero" in fp["vulkan_host"], (
        f"fingerprint expectations incomplete: {fp}"
    )
    assert re.search(r"stop.*not retry|do not retry", fp["on_mismatch"]), (
        "a still-huge Vulkan_Host means the override did not compose as rendered: "
        "stop and report - retry would burn the one-attempt protocol"
    )
    joined = " ".join(fp["regime_lines"])
    assert "--load-mode mmap" in joined and "--fit off" in joined and "spec" in joined, (
        f"regime_lines must confirm the C03 flags actually applied at load: {fp['regime_lines']}"
    )


def test_c04_procedure_mtp_gate2_is_a_disjunction():
    """Gate 2: re-add ONLY through a passing hc-layout verdict, else blocked-
    with-evidence (agentionai candidates) - never a blind graft (AC4)."""
    g = _step("mtp-gate-2")
    assert "hc-layout" in g["when"] and "C01" in g["when"]
    assert g.get("on_pass") and g.get("on_fail"), "both gate-2 outcomes must be specified"
    assert "agentionai" in g["on_fail"] or "blocked" in g["on_fail"], (
        "the blocked branch must carry the follow-up path, not silence"
    )


def test_c04_procedure_branch_b_check_is_conditional():
    """B is fork-dependent (C01's gate): the booted-values verification rides
    ONLY if B triggered - and then BEFORE any attempt, with the kubelet
    allocatable recheck (GTT pages are pinned RAM)."""
    b = _step("branch-b-booted-values")
    assert "if" in b["when"] and "B" in b["when"]
    joined = " ".join(b["commands"])
    assert "pages_limit" in joined and ("Allocatable" in joined or "allocatable" in joined)
    assert "BEFORE any attempt" in b["expect"] or "before any attempt" in b["expect"]


# --- B) recorded-attempt validators (EVIDENCE.md post-fix section) ------------


def _post_fix_text() -> str:
    if not EVIDENCE.exists():
        pytest.skip("EVIDENCE.md absent - C01 evidence gate not yet passed")
    m = re.search(r"^#{1,6}[^\n]*post[- ]?fix[^\n]*\n", EVIDENCE.read_text(), re.M | re.I)
    if not m:
        pytest.skip(
            "no post-fix section in EVIDENCE.md - C04's consented attempt not yet recorded "
            "(post-merge verification; TEST_SPEC §4 evidence gate)"
        )
    return EVIDENCE.read_text()[m.start():]


def test_c04_ac1_load_reached_and_regime_applied():
    t = _post_fix_text()
    assert re.search(r"running|completion", t, re.I), "AC1: no reaching-running / completion record"
    assert "--load-mode mmap" in t and "--fit off" in t, (
        "AC1: the load log record must confirm the C03 regime actually applied"
    )
    assert re.search(r"(?:no|without)[^\n]{0,40}(?:--spec-type|spec|draft)", t, re.I), (
        "AC1: no first-cut spec/draft absence confirmation in the load record"
    )
    assert "CPU_Mapped" in t and "Vulkan_Host" in t, (
        "AC1: buffer split with experts NOT in Vulkan_Host is the fingerprint - both classes must appear"
    )
    assert re.search(r"Vulkan_Host[\s\S]{0,120}(?:near[- ]?zero|≈\s*0|\b0\b|<\s*\d+\s*GiB|under)", t, re.I), (
        "AC1: Vulkan_Host must be recorded near-zero (vs C01's pre-fix split) - "
        "otherwise the GTT-pinned regime was never left"
    )


def test_c04_ac2_journal_clean_all_four_recorded():
    t = _post_fix_text()
    for pattern in REQUIRED_JOURNAL_PATTERNS:
        idx = t.find(pattern)
        assert idx >= 0, f"AC2: pattern {pattern!r} not individually recorded in the attempt window"
        window = t[max(0, idx - 120): idx + 260]
        assert re.search(r"0(?:\s*(?:matches?|hits?))|no (?:matches?|hits?)|zero (?:matches?|hits?)|absent|clean", window, re.I), (
            f"AC2: no zero-match claim adjacent to {pattern!r} - all four patterns need explicit "
            "'no matches' evidence with the window timestamps"
        )
    assert re.search(r"node[^\n]{0,60}Ready", t, re.I), "AC2: node Ready proof missing"
    assert re.search(r"restart", t, re.I), "AC2: container-restart statement missing (none unexplained)"
    assert re.search(r"trio|/running|running-state", t, re.I), "AC2: trio running-state / clean reload record missing"
    assert re.search(r"(?:one|single|1)[^\n]{0,30}attempt|no retr(?:y|ies)", t, re.I), (
        "AC2: the one-attempt protocol must be proven by the record (no retry loops)"
    )


def test_c04_ac3_long_prefill_probe_outcome():
    t = _post_fix_text()
    assert re.search(r"prefill probe|8[–-]?16\s*k|16k", t, re.I), (
        "AC3: no long-prefill (~8-16k token) probe record for the runtime ring-timeout class"
    )
    assert re.search(r"clean|mitigat|GGML_VK_MAX_NODES_PER_SUBMIT|-ub 512", t, re.I), (
        "AC3: probe outcome must be either clean or mitigated llama-side + re-probed"
    )
    assert re.search(r"lockup_timeout[\s\S]{0,120}(?:untouched|not (?:changed|modified)|unchanged)|kernel params? (?:untouched|unchanged)", t, re.I), (
        "AC3: kernel params untouched must be stated explicitly in every branch"
    )


def test_c04_ac4_mtp_either_readded_or_blocked():
    t = _post_fix_text()
    re_added = re.search(r"(?:re-?added|second gate)[\s\S]{0,160}(?:passed|running|clean)", t, re.I)
    blocked = re.search(r"blocked", t, re.I) and re.search(r"hc[- ]?layout|output_hc_norm|agentionai|#?28901", t, re.I)
    assert re_added or blocked, (
        "AC4: MTP must be recorded as re-added through a passing gate 2 (second consented load, "
        "journal watch) OR blocked-with-evidence citing C01's layout verdict - no silent omission"
    )


def test_c04_ac5_headroom_quantified_and_bookkeeping():
    t = _post_fix_text()
    assert re.search(r"free -h|Mem:\s+\d|\d+(?:\.\d+)?\s*GiB", t), (
        "AC5: measured memory numbers (free -h / allocation summary) missing"
    )
    assert re.search(r"headroom", t, re.I), "AC5: no post-fix headroom table vs the C01 pre-fix numbers"
    assert re.search(r"q4", t, re.I) and re.search(r"DECISIONS", t), (
        "AC5: the q4 budget arithmetic and the DECISIONS.md entry are the outcome bookkeeping deliverables"
    )
