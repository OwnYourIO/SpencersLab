# C01 evidence contract — validators for EVIDENCE.md, the chunk's only
# deliverable (ticket 2026/2026-10-debug-flash-next-vulkan-oom, chunks/C01.md
# acceptance criteria 1-7 + the chunk's "Tests" additions).
#
# Why file-gated instead of hard-red today: these read an in-ticket artifact
# (the feature folder), not a repo source file, so an absent EVIDENCE.md means
# "C01 not landed yet" — a TEST_SPEC §4-style evidence gate with a loud reason
# (review needs RAN vs SKIPPED, and the C03-era CI must not red before wave 1
# completes). Once the file exists, every check below is HARD: a section that
# fails is a C01 acceptance failure, not a skip.
#
# grep-style by design (chunk Tests): we verify the fingerprint the mechanism
# needs (Vulkan_Host vs CPU_Mapped numbers distinguished, the exact tensor
# name in the MTP verdict), never the VALUES — the values ARE the unknowns.

from __future__ import annotations

import os
import re
from pathlib import Path

import pytest

import llama_swap_testlib as L

FEATURE_DIR = L.REPO_ROOT / ".agents" / "plans" / "2026" / "2026-10-debug-flash-next-vulkan-oom"
EVIDENCE = Path(os.environ.get("FLASHNEXT_EVIDENCE", FEATURE_DIR / "EVIDENCE.md"))

if not EVIDENCE.exists():
    pytest.skip(
        f"EVIDENCE.md absent ({EVIDENCE}) — C01 evidence artifact "
        "not landed; content checks become hard once dev writes the file",
        allow_module_level=True,
    )

DOC = EVIDENCE.read_text()

_TS = re.compile(r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}|\d{4}-\d{2}-\d{2}")
_SIZE = r"\d[\d,.]*\s*(?:MiB|GiB|MB|GB)"


def _has(pattern: str, flags: int = 0) -> re.Pattern | None:
    m = re.search(pattern, DOC, flags)
    return m


# --- AC1: the load_tensors buffer split (or explicit absence statement) ------


def test_c01_ac1_buffer_split_fingerprint_or_absent_statement():
    assert _has(r"load_tensors", re.I), (
        "AC1: no load_tensors section — EVIDENCE.md must carry the crash-window "
        "buffer-split numbers OR explicitly state the historical log lacks them"
    )
    has_vh = _has(rf"Vulkan_Host[^\n]*{_SIZE}")
    has_cm = _has(rf"CPU_Mapped[^\n]*{_SIZE}")
    absent_stmt = _has(r"(?:absent|not present|no longer|lacks|did not (?:reach|print)|missing)", re.I)
    quoted_tail = _has(r"(?:^> |\n```)", re.M)
    if has_vh and has_cm:
        # chunk Tests addendum: the split must DISTINGUISH the two buffer
        # classes explicitly — they are the mechanism's fingerprint.
        assert "Vulkan_Host" in DOC and "CPU_Mapped" in DOC
        return
    assert absent_stmt and quoted_tail, (
        "AC1: neither a Vulkan_Host/CPU_Mapped split with numbers nor an explicit "
        "'absent' statement with the quoted tail of what exists instead — found "
        f"Vulkan_Host+size: {bool(has_vh)}, CPU_Mapped+size: {bool(has_cm)}"
    )


# --- AC2: GTT budget measurement + the C03 gate table -----------------------


def test_c01_ac2_gtt_budget_measured():
    assert _has(rf"(?:{_SIZE}[^\n]{{0,60}}of GTT memory|GTT memory ready[^\n]{{0,60}}{_SIZE})", re.I), (
        "AC2: no dmesg/journal '… of GTT memory ready' line with its size — "
        "the boot line IS the budget (plan: /api/hardware's 512 MiB is the UMA carve-out, not it)"
    )
    assert _has(r"ttm/parameters/pages_limit", re.I), (
        "AC2: /sys/module/ttm/parameters/pages_limit read missing (or explicitly noted unavailable)"
    )
    assert _has(r"amdgpu/parameters/gttsize", re.I), (
        "AC2: /sys/module/amdgpu/parameters/gttsize read missing (chunk records value-or-default)"
    )


def test_c01_ac2_required_vs_budget_verdict():
    assert _has(r"(?:required|demand)[^\n]{0,80}(?:budget)|(?:budget)[^\n]{0,80}(?:required|demand)", re.I), (
        "AC2: no required-vs-budget comparison present — C03's A-vs-A+B gate is "
        "'arithmetic, not guesswork' (chunk Goal); the table is the deliverable"
    )
    assert _has(r"(?:verdict|gate)[^\n]{0,120}(\bA\s*(?:\+|and)?\s*B\b|branch[ -]?A\b|\bA[- ]alone\b)", re.I), (
        "AC2: no one-line A / A+B verdict derivable from the table"
    )


# --- AC3: lockup_timeout recorded, no change ---------------------------------


def test_c01_ac3_lockup_timeout_recorded_no_change():
    assert _has(r"lockup_timeout[^\n]*(?:=|:|\n)[^\n]*\d", re.I), (
        "AC3: lockup_timeout value not recorded (RESEARCH contradiction #1 must be "
        "settled by the sysfs read)"
    )
    assert _has(r"lockup_timeout[\s\S]{0,200}(?:no change|unchanged|record(?:ed)? only|not (?:changed|modified))", re.I), (
        "AC3: EVIDENCE must state no change is made (decision rule for the single-node box)"
    )


# --- AC4: ik-llama-server presence, three-way verdict -----------------------


def test_c01_ac4_ik_presence_verdict():
    assert _has(r"ik[-_]llama", re.I), (
        "AC4: no ik-llama-server section (presence/version in unified-vulkan-266)"
    )
    assert _has(r"\b(present|absent|unverifiable)\b", re.I), (
        "AC4: presence/absent/unverifiable verdict word missing"
    )
    assert _has(r"2369"), (
        "AC4: the qwen4exp-support note must reference ik PR #2369 (bundled-commit vs "
        "PR-date gate for C1)"
    )


# --- AC5: tensor-name dump + MTP hc-layout with the exact tensor name -------


def test_c01_ac5_tensor_name_dump_verdicts():
    assert _has(r"ffn_.*exps|\.ffn_", re.I), (
        "AC5: no -ot regex (ffn_*_exps) match verdict for UD-Q3_K_XL routed experts"
    )
    assert _has(rf"per_layer_token_embd\.weight[^\n]{{0,160}}{_SIZE}", re.I), (
        "AC5: per_layer_token_embd.weight size not recorded (the >4 GiB host-forced tensor)"
    )


def test_c01_ac5_mtp_hc_layout_verdict_exact_tensor_name():
    # chunk Tests addendum: the verdict must name the exact tensor checked.
    assert _has(r"output_hc_norm\.weight"), (
        "AC5: MTP hc-layout verdict must reference 'output_hc_norm.weight' explicitly "
        "(the post-#28901 marker; absent on a pre-#28901 sidecar -> C04 gate 2 BLOCKED)"
    )
    assert _has(r"(?:output_hc_norm\.weight|hc[- ]layout)[\s\S]{0,300}(?:found|not found|absent|present|post-?#?28901|pre-?#?28901|blocked)", re.I), (
        "AC5: no layout verdict (post/pre-#28901) attached to the tensor-name proof"
    )


# --- AC6: the pod's Mesa, not the host's ------------------------------------


def test_c01_ac6_pod_mesa_version():
    assert _has(rf"Mesa[^\n]{{0,60}}\d+\.\d+", re.I), (
        "AC6: no Mesa version string recorded"
    )
    assert _has(r"(?:/versions\.txt|kubectl exec|pod)", re.I), (
        "AC6: Mesa read must be attributed to the POD image (it ships its own Mesa [44])"
    )


# --- AC7: provenance discipline ----------------------------------------------


def test_c01_ac7_sources_timestamps_and_user_run_attribution():
    stamps = _TS.findall(DOC)
    assert len(stamps) >= 5, (
        f"AC7: only {len(stamps)} timestamp hits — every quoted command/log needs source + timestamp"
    )
    assert _has(r"user-run|operator-run|run by the (?:user|operator)", re.I), (
        "AC7: exec/kubectl material must be presented as user-run — no agent may claim a pod-exec (repo rule)"
    )
    assert not _has(r"(?:agent|i) (?:ran|executed|just ran)[^\n]{0,40}kubectl exec", re.I), (
        "AC7: document claims an agent-run pod-exec — forbidden"
    )


# --- chunk tasks 17-19: timeline, working-regime comparison, host snapshot ---


def test_c01_task_timeline_and_comparison_and_host_snapshot():
    assert _has(r"crash[- ]window|timeline", re.I), (
        "chunk task: crash-window upstream log + kernel journal lines (or explicit 'absent') with timestamps"
    )
    assert _has(r"qwen3\.6-35b-a3b-q8", re.I), (
        "chunk task: working-regime comparison via the 35B-q8 load's buffer-split summary"
    )
    assert _has(r"free -h", re.I) and _has(r"mem_info_", re.I) and _has(r"/proc/cmdline", re.I), (
        "chunk task: host context snapshot (free -h, /sys/class/drm/card*/device/mem_info_*, /proc/cmdline)"
    )
