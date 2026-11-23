"""D8 receipt-gate proof legs — bug-radiance-27b-context-window (2026-11-23).

The gate is the anti-drift half of parent-ruling D49 (a gate which can pass
on absence is not a gate). These legs prove the gate's three-state law with
SYNTHETIC prints — the real print is PRINT-PENDING (plan OQ 1-5) and arrives
at the owner's scale act: a complete print passes; a partial one refuses and
NAMES the missing item; a block-detected FAIL/MISMATCH marker refuses with the
block's reason; a missing log file refuses with the missing lane named. The
shape independence is the point: the gate does not parse print prose, it
requires the OK marker with embedded evidence, so the first owner run calibrates
the block's greps without the gate's law moving.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

import receipt_gate as G
import radiance_testlib as R

HELD_GIB = {"radiance": "110", "radiance-q27": "24", "radiance-flash-tp1": "110", "radiance-q27-tp2": "24"}


def _lane_print(lane: str, *, pool_m: str | None = "8", smoke: int = 8) -> str:
    held = HELD_GIB[lane]
    lines = [f"=== lane {lane} (held {held} GiB) @ synthetic ==="]
    lines.append("ITEM1: DIAG_OK max-model-len 262144")
    lines.append("ITEM2: VRAM_OK weights 39.5GiB | kv pool 12.48GiB | drafter 0.42GiB")
    if pool_m is None:
        lines.append("ITEM3: POOL_MISSING no 'pool backs' line in the boot log")
    elif pool_m == "":
        lines.append("ITEM3: POOL_OK kv: the pool backs 41% of the worst case (no session figure)")
    else:
        lines.append(f"ITEM3: POOL_OK kv: the pool backs 41% of the worst case ... {pool_m} full-length sessions")
    lines.append(f"ITEM4: PIN_OK pinned=71.04GiB held={held}GiB diff={float(held) - 71.04 if held == '110' else float(held) - 9.2}")
    lines.append("ITEM5: SLOTS_OK checkpoint slots 9 per 200K-class session (log-scaled)")
    lines.append("ITEM6: WARN_OK prefix cache tier (4 GiB) is smaller than one full conversation (16.0 GiB)")
    lines.append("ITEM7: MEM_OK peak=88.2GiB oom_kill=0")
    lines.append("ITEM8: PEER_HOP_OK " + _served_id(lane))
    lines.append("ITEM9: NEAR_FULL_OK 262143")
    if lane == G.FN_LANE:
        for i in range(1, smoke + 1):
            lines.append(f"SMOKE: ADMITTED {i} 200")
    return "\n".join(lines) + "\n"


def _served_id(lane: str) -> str:
    return {
        "radiance": "qwen3.8-flash-next-radiance",
        "radiance-q27": "qwen3.8-27b-radiance",
        "radiance-flash-tp1": "qwen3.8-flash-next-radiance-tp1",
        "radiance-q27-tp2": "qwen3.8-27b-radiance-tp2",
    }[lane]


def _write_logs(tmp_path: Path, prints: dict[str, str]) -> Path:
    # write exactly the lanes given — the missing-lane legs omit one on purpose
    for name, text in prints.items():
        (tmp_path / f"{name}.log").write_text(text)
    return tmp_path


def _complete_prints() -> dict[str, str]:
    return {lane: _lane_print(lane) for lane in G.LANES}


def test_receipt_gate_passes_on_a_complete_synthetic_print(tmp_path):
    """The positive control: every item present on all four lanes (fn M=8,
    eight admitted) — the gate closes, i.e. returns an empty diagnostic list."""
    _write_logs(tmp_path, _complete_prints())
    assert G.gate(tmp_path) == []


def test_receipt_gate_refuses_a_planted_partial_print_and_names_the_items(tmp_path):
    """The D49 core: a partial print REFUSES and the diagnostic NAMES the
    missing item — flash-TP1's pool-backs line removed, fn's pool backs
    M=7 (< 8, D9(a)). Both are named, and the refusal does not silently
    pass on the absence."""
    prints = _complete_prints()
    flash = [ln for ln in prints["radiance-flash-tp1"].splitlines() if not ln.startswith("ITEM3:")]
    prints["radiance-flash-tp1"] = "\n".join(flash) + "\n"
    prints["radiance"] = _lane_print("radiance", pool_m="7")
    _write_logs(tmp_path, prints)
    diags = G.gate(tmp_path)
    assert diags, "a partial print must refuse"
    assert any("radiance-flash-tp1: item 3" in d for d in diags), f"the missing item must be NAMED: {diags}"
    assert any("D9(a)" in d and "M=7" in d for d in diags), f"the fn M bar miss must be NAMED: {diags}"
    assert any("C03 trigger, not a close" in d for d in diags), f"M < 8 is a C03 trigger, not a close: {diags}"
    # the other three lanes' items are complete and must not be named
    assert not any(d.startswith("radiance-q27") or d.startswith("radiance-q27-tp2") for d in diags)


def test_receipt_gate_names_a_missing_log_file(tmp_path):
    """A lane the block never ran (missing file) is NAMED — absence of the
    whole log is a refusal, never a pass."""
    prints = _complete_prints()
    _write_logs(tmp_path, {k: v for k, v in prints.items() if k != "radiance-q27"})
    diags = G.gate(tmp_path)
    assert diags
    assert any("radiance-q27" in d and "no log file" in d for d in diags), diags


def test_receipt_gate_names_a_seven_of_eight_admitted_smoke(tmp_path):
    """D9(b) loud check: seven of eight near-full sessions admitted — the
    silent failure mode (Radiance warns, does not refuse) is named, not
    waved through."""
    prints = _complete_prints()
    prints["radiance"] = _lane_print("radiance", smoke=7)
    _write_logs(tmp_path, prints)
    diags = G.gate(tmp_path)
    assert diags
    assert any("D9(b)" in d and "7/8" in d and "missing: ['8']" in d for d in diags), diags


def test_receipt_gate_names_a_non_2xx_admission(tmp_path):
    """D9(b), other end: eight entries but one 503 — 'admitted' means 2xx;
    a funded-but-refused session is the refutation the bar prices."""
    prints = _complete_prints()
    lines = prints["radiance"].splitlines()
    lines[-4] = "SMOKE: ADMITTED 5 503"
    prints["radiance"] = "\n".join(lines) + "\n"
    _write_logs(tmp_path, prints)
    diags = G.gate(tmp_path)
    assert any("D9(b)" in d and "503" in d for d in diags), diags


def test_receipt_gate_names_a_block_detected_fail_marker(tmp_path):
    """The three-state law's middle state: the block RAN and DETECTED a
    failure (MEM_FAIL) — the gate refuses with the block's reason embedded,
    distinct from the 'no line at all' refusal."""
    prints = _complete_prints()
    lines = [ln for ln in prints["radiance-q27"].splitlines() if not ln.startswith("ITEM7:")]
    lines.append("ITEM7: MEM_FAIL peak=<none> oom=oom_kill=2")
    prints["radiance-q27"] = "\n".join(lines) + "\n"
    _write_logs(tmp_path, prints)
    diags = G.gate(tmp_path)
    assert any("radiance-q27: item 7" in d and "MEM_FAIL" in d for d in diags), diags


def test_receipt_gate_refuses_when_the_pool_line_lacks_an_m_figure(tmp_path):
    """D9(a) parse arm: the pool-backs line is present but carries no
    'M full-length sessions' figure — the bar cannot be evaluated, so it
    cannot pass (a gate that cannot evaluate is a gate that can pass on
    absence — the D49 class)."""
    prints = _complete_prints()
    prints["radiance"] = _lane_print("radiance", pool_m="")
    _write_logs(tmp_path, prints)
    diags = G.gate(tmp_path)
    assert any("D9(a)" in d and "cannot be evaluated" in d for d in diags), diags


def test_receipt_gate_lanes_are_exactly_the_four_ruled_lanes():
    """D8: the block and the gate share the lane set — and it is the FOUR
    ruled lanes (the ticket's scope: D1/D2/D5/D9), nothing more, nothing
    less. Cross-pinned against testlib's composition lanes so a lane rename
    cannot drift the two artifacts apart."""
    assert set(G.LANES) == {"radiance", "radiance-q27", "radiance-flash-tp1", "radiance-q27-tp2"}
    assert set(G.LANES) == set(R.COMPOSITION_LANES)
    assert len(G.LANES) == len(set(G.LANES)) == 4


def test_command_block_enumerates_all_four_lanes_and_the_receipt_dir():
    """The pre-authored block: all four lanes enumerated with held + served
    facts, the eight-session smoke gated to fn, the logs written to
    tests/radiance-receipt/ — and NEVER to evidence/ (the C03 pin's
    territory; a log there breaks the pin)."""
    block = G.RECEIPT_COMMAND_BLOCK
    for lane in G.LANES:
        assert f'"{lane}|' in block, f"the block must enumerate {lane}"
    assert "tests/radiance-receipt" in block
    assert "SMOKE: ADMITTED" in block and 'if [ "$name" = "radiance" ]' in block
    assert "262143" in block  # the near-full token figure (item 9 + the smoke)
    # evidence/ must be a comment-only mention (the warning), never a write target
    for ln in block.splitlines():
        if "evidence/" in ln:
            assert ln.lstrip().startswith("#"), f"a block line writes into evidence/: {ln!r}"


def test_command_block_cli_refuses_a_missing_file_and_exits_1(tmp_path):
    """The CLI surface the C04 closing leg runs: a missing lane file is a
    refusal with exit 1 and the missing lane NAMED — not a silent 0."""
    prints = _complete_prints()
    _write_logs(tmp_path, {k: v for k, v in prints.items() if k != "radiance-flash-tp1"})
    out = subprocess.run(
        [sys.executable, str(Path(__file__).parent / "receipt_gate.py"), "--gate", "--logs-dir", str(tmp_path)],
        capture_output=True, text=True, timeout=120,
    )
    assert out.returncode == 1, f"refusal must exit 1 (got {out.returncode}): {out.stdout}"
    assert "radiance-flash-tp1" in out.stdout and "REFUSED" in out.stdout, out.stdout
    assert "PROVISIONAL stays open" in out.stdout, out.stdout
