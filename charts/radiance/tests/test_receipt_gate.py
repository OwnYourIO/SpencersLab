"""D8 receipt-gate proof legs — bug-radiance-27b-context-window (2026-11-23;
gate-fix round: the per-lane fit adjudication).

The gate is the anti-drift half of parent-ruling D49 (a gate which can pass
on absence is not a gate). These legs prove the gate's three-state law with
SYNTHETIC prints — the real print is PRINT-PENDING (plan OQ 1-5) and arrives
at the owner's scale act: a complete print passes; a partial one refuses and
NAMES the missing item; a block-detected FAIL/MISMATCH marker refuses with
the block's reason; a missing log file refuses with the missing lane named.
The shape independence is the point: the gate does not parse print prose, it
requires the OK marker with embedded evidence, so the first owner run
calibrates the block's greps without the gate's law moving.

The gate-fix round (the final-review defect): the pre-fix gate certified
item 3 by the PRESENCE of the pool-backs line and parsed the M figure for
fn only — a non-fn lane's POOL_OK at 4 full-length sessions (75% of the
worst case) passed, which is exactly the unobserved-value completeness gate
the D49 lesson exists to catch. The legs below prove the fix both
directions: the machine bar refuses on a short or unparseable M on ANY lane
and on an unreadable/ambiguous fallback; N% < 100 (or the N% figure absent)
is surfaced as an owner-read warning — visible, attributable, never a
refusal; the fn loud checks (D9(a) M bar, the admitted-sessions smoke) stay
intact.

[2026-11-feat-radiance-fp8v4-lane D-16/D-20 — the per-lane bar RE-CUT, this
wave's load-bearing rewrite]: --max-num-seqs became per-lane (5 on the four
existing lanes, 8 on the new fp8_v4 lane), so the M bar is no longer the
whole chart's single FORM-fixed digit — it is resolved PER LANE as the chart
fallback overridden by that lane's RADIANCE_MAX_NUM_SEQS env, and the old
"two distinct = ambiguous" rule (which per-lane formation produces by
design) is re-pinned: per-lane bars are the DESIGNED state, while an
undecidable FALLBACK (unreadable chart, absent flag, two distinct fallbacks)
or a malformed lane env still REFUSES (the D49 absence law survives in its
new form). fn's smoke becomes five-admitted (D-16 superseding D9(b)'s eight).
The fp8_v4 lane's M < 8 refusal is the ACCEPTED deficit (D-20): its bar stays
8, the boot print adjudicates, and 6.77 / 84.7% are DERIVED figures that
appear as a pass condition NOWHERE.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

import receipt_gate as G
import radiance_testlib as R

HELD_GIB = {"radiance": "110", "radiance-q27": "24", "radiance-flash-tp1": "110",
            "radiance-q27-tp2": "24", "radiance-q27-fp8v4": "24"}


def _lane_print(lane: str, *, pool_m: str | None = "8", pool_pct: str = "41", smoke: int = 5) -> str:
    held = HELD_GIB[lane]
    lines = [f"=== lane {lane} (held {held} GiB) @ synthetic ==="]
    lines.append("ITEM1: DIAG_OK max-model-len 262144")
    lines.append("ITEM2: VRAM_OK weights 39.5GiB | kv pool 12.48GiB | drafter 0.42GiB")
    if pool_m is None:
        lines.append("ITEM3: POOL_MISSING no 'pool backs' line in the boot log")
    elif pool_m == "":
        lines.append(f"ITEM3: POOL_OK kv: the pool backs {pool_pct}% of the worst case (no session figure)")
    else:
        lines.append(f"ITEM3: POOL_OK kv: the pool backs {pool_pct}% of the worst case ... {pool_m} full-length sessions")
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
        "radiance-q27-fp8v4": "qwen3.8-27b-radiance-fp8v4",
    }[lane]


def _write_logs(tmp_path: Path, prints: dict[str, str]) -> Path:
    # write exactly the lanes given — the missing-lane legs omit one on purpose
    for name, text in prints.items():
        (tmp_path / f"{name}.log").write_text(text)
    return tmp_path


def _complete_prints() -> dict[str, str]:
    return {lane: _lane_print(lane) for lane in G.LANES}


def test_receipt_gate_passes_on_a_complete_synthetic_print(tmp_path):
    """The positive control + the M>=bar/N%<100 plant: every item present on
    all five lanes (M=8 at 41% on every lane — on today's env-less tree every
    bar is the fallback 8 — five admitted on fn) — the gate closes (no
    refusals) AND every lane's 41% figure surfaces as an owner-read warning:
    N% < 100 is recorded and surfaced (visible, attributable), not silently
    accepted and not a close bar."""
    _write_logs(tmp_path, _complete_prints())
    diags, warnings = G.gate(tmp_path)
    assert diags == []
    assert len(warnings) == len(G.LANES), f"every lane's 41% figure must be surfaced: {warnings}"
    for lane in G.LANES:
        assert any(lane in w and "41%" in w for w in warnings), f"{lane}'s 41% figure must be NAMED: {warnings}"


def test_receipt_gate_passes_clean_with_a_fully_funded_pool(tmp_path):
    """The no-false-alarm control: M at the bar and N% = 100 on every lane —
    the gate closes with ZERO warnings (a fully-funded pool is not an
    owner-read concern to surface; a warning here would be noise the owner
    learns to ignore)."""
    _write_logs(tmp_path, {lane: _lane_print(lane, pool_pct="100") for lane in G.LANES})
    diags, warnings = G.gate(tmp_path)
    assert diags == []
    assert warnings == []


def test_receipt_gate_refuses_a_non_fn_lane_with_an_underfunded_pool(tmp_path):
    """The gate-fix plant (the final-review defect, both directions): the
    pre-fix gate certified item 3 by PRESENCE, so a non-fn lane's POOL_OK
    at 4 full-length sessions (75% of the worst case) passed — the lane the
    evidence PREDICTS will not fit (V3/S10). The machine bar is now
    per-lane: the refusal NAMES the lane, the parsed M, and the required
    bar."""
    prints = _complete_prints()
    prints["radiance-q27"] = _lane_print("radiance-q27", pool_m="4", pool_pct="75")
    _write_logs(tmp_path, prints)
    diags, _ = G.gate(tmp_path)
    assert diags, "an under-funded NON-FN lane must REFUSE (presence is not a pass)"
    assert any("radiance-q27" in d and "M=4" in d and "M >= 8" in d for d in diags), f"the lane, the parsed M and the bar must all be NAMED: {diags}"
    # the other lanes' items are complete and their M=8 holds — only the
    # under-funded lane is refused (the fp8_v4 lane is a funded synthetic here;
    # its real first print is the D-20 deficit, exercised by its own leg)
    assert not any(d.startswith("radiance:") or d.startswith("radiance-flash-tp1") or d.startswith("radiance-q27-tp2") or d.startswith("radiance-q27-fp8v4") for d in diags), f"the funded lanes must not be named: {diags}"


def test_receipt_gate_refuses_a_non_fn_lane_whose_pool_line_lacks_an_m_figure(tmp_path):
    """The D49 class, non-fn side: the POOL_OK line is present but carries
    no M figure on a NON-FN lane — pre-fix a presence pass; the bar cannot
    be evaluated, so it cannot pass (absence is not a pass)."""
    prints = _complete_prints()
    prints["radiance-flash-tp1"] = _lane_print("radiance-flash-tp1", pool_m="")
    _write_logs(tmp_path, prints)
    diags, _ = G.gate(tmp_path)
    assert any("radiance-flash-tp1" in d and "cannot be evaluated" in d for d in diags), diags


def test_gate_refuses_the_fp8v4_lane_below_8_as_the_ruled_deficit(tmp_path):
    """DECISIONS D-20 — the ACCEPTED DEFICIT, encoded so a reviewer cannot
    misread it as an unfunded failure awaiting repair. The fp8_v4 lane's
    configured --max-num-seqs is 8 (the chart fallback; it authors no seqs env),
    and its first boot print is EXPECTED to fund FEWER than 8 sessions. This
    leg asserts exactly two things: (a) the machine bar for this lane is 8 and
    is NEVER lowered to make the deficit pass (D49 + D-20), and (b) a print
    showing fewer than 8 REFUSES, naming the lane's own 8 bar — the ruled
    expected steady state, not a defect. It asserts NOTHING about what number
    the print will show: the boot print adjudicates. 6.77 and 84.7% are DERIVED
    figures and must appear as a pass condition nowhere; the below-bar value
    planted here ("3") is an arbitrary sub-bar stand-in to fire the refusal,
    never a predicted outcome."""
    chart_text, err = G._read_chart_text(G.chart_values_path())
    assert err is None, err
    services = G._read_services_doc(G.services_values_path())
    bar, bar_err = G.lane_max_num_seqs("radiance-q27-fp8v4", chart_text, services)
    assert bar == 8, f"D-20: the fp8_v4 lane's bar must stay at its configured 8, never lowered: {bar} ({bar_err})"
    prints = _complete_prints()
    prints["radiance-q27-fp8v4"] = _lane_print("radiance-q27-fp8v4", pool_m="3", pool_pct="60")
    _write_logs(tmp_path, prints)
    diags, _ = G.gate(tmp_path)
    assert any("radiance-q27-fp8v4" in d and "M >= 8" in d for d in diags), (
        f"the M<8 refusal on this lane is the ruled expected state and must name its own 8 bar: {diags}")
    verdicts = " ".join(diags)
    assert "6.77" not in verdicts and "84.7" not in verdicts, (
        f"D-20/receipt LAW: a derived figure leaked into a gate verdict as if it were a pass value: {verdicts}")


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
    diags, _ = G.gate(tmp_path)
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
    diags, _ = G.gate(tmp_path)
    assert diags
    assert any("radiance-q27" in d and "no log file" in d for d in diags), diags


def test_receipt_gate_names_a_four_of_five_admitted_smoke(tmp_path):
    """D-16 loud check (fn's five-admitted smoke, superseding D9(b)'s eight):
    four of five near-full sessions admitted — the silent failure mode
    (Radiance warns, does not refuse) is named, not waved through."""
    prints = _complete_prints()
    prints["radiance"] = _lane_print("radiance", smoke=4)
    _write_logs(tmp_path, prints)
    diags, _ = G.gate(tmp_path)
    assert diags
    assert any("D9(b)/D-16" in d and "4/5" in d and "missing: ['5']" in d for d in diags), diags


def test_receipt_gate_names_a_non_2xx_admission(tmp_path):
    """D-16, other end: five entries but one 503 — 'admitted' means 2xx; a
    funded-but-refused session is the refutation the bar prices."""
    prints = _complete_prints()
    lines = prints["radiance"].splitlines()
    lines = ["SMOKE: ADMITTED 5 503" if ln == "SMOKE: ADMITTED 5 200" else ln for ln in lines]
    assert any(ln == "SMOKE: ADMITTED 5 503" for ln in lines), "the planted 503 did not land on an fn smoke line"
    prints["radiance"] = "\n".join(lines) + "\n"
    _write_logs(tmp_path, prints)
    diags, _ = G.gate(tmp_path)
    assert any("D9(b)/D-16" in d and "503" in d for d in diags), diags


def test_receipt_gate_names_a_block_detected_fail_marker(tmp_path):
    """The three-state law's middle state: the block RAN and DETECTED a
    failure (MEM_FAIL) — the gate refuses with the block's reason embedded,
    distinct from the 'no line at all' refusal."""
    prints = _complete_prints()
    lines = [ln for ln in prints["radiance-q27"].splitlines() if not ln.startswith("ITEM7:")]
    lines.append("ITEM7: MEM_FAIL peak=<none> oom=oom_kill=2")
    prints["radiance-q27"] = "\n".join(lines) + "\n"
    _write_logs(tmp_path, prints)
    diags, _ = G.gate(tmp_path)
    assert any("radiance-q27: item 7" in d and "MEM_FAIL" in d for d in diags), diags


def test_receipt_gate_refuses_when_the_pool_line_lacks_an_m_figure(tmp_path):
    """D9(a) parse arm (fn side, kept intact): the pool-backs line is
    present but carries no 'M full-length sessions' figure — the bar cannot
    be evaluated, so it cannot pass (a gate that cannot evaluate is a gate
    that can pass on absence — the D49 class)."""
    prints = _complete_prints()
    prints["radiance"] = _lane_print("radiance", pool_m="")
    _write_logs(tmp_path, prints)
    diags, _ = G.gate(tmp_path)
    assert any("D9(a)" in d and "cannot be evaluated" in d for d in diags), diags


def test_receipt_gate_refuses_when_the_configured_seqs_cannot_be_read(tmp_path):
    """The D49 no-fallback law: the bar is READ from the chart's FORM (D6),
    and when it cannot be read the gate refuses with the read failure
    NAMED — it never falls back to a hardcoded 8, because an unverified bar
    is the pass-on-absence class (the M=8 print would pass a fallback bar;
    it must still refuse)."""
    _write_logs(tmp_path, _complete_prints())
    diags, _ = G.gate(tmp_path, values_path=tmp_path / "no-such-values.yaml")
    assert diags, "an unreadable bar must REFUSE (never a fallback to a hardcoded 8)"
    assert any("--max-num-seqs" in d and "cannot be evaluated" in d for d in diags), f"the read failure must be NAMED: {diags}"


def test_gate_bar_is_read_from_the_chart_fallback_and_overridden_per_lane():
    """The per-lane bar RE-CUT (D-16). The baseline follows the FORM, not a
    hardcoded 8: read_configured_max_num_seqs on the real chart returns the
    shipped fallback (8 today, whether the literal or the ${...:-8} expansion),
    and a planted chart with fallback 5 moves the default bar for env-less
    lanes. Then the per-lane override: a lane that authors
    RADIANCE_MAX_NUM_SEQS "5" has bar 5 while its env-less sibling stays at the
    chart fallback — the existing four move to 5 and the fp8_v4 lane keeps the
    fallback 8, each bar read from its own source."""
    chart8 = '  set -- --max-num-seqs "${RADIANCE_MAX_NUM_SEQS:-8}"\n'
    bar, err = G.read_configured_max_num_seqs(G.chart_values_path())
    assert err is None, err
    assert bar == 8, f"the shipped fallback byte today is 8 (parent-D46, FORM fallback); got {bar}"
    assert G.chart_seqs_fallback('  --max-num-seqs "${RADIANCE_MAX_NUM_SEQS:-5}"') == (5, None), \
        "a planted fallback-5 chart must move the baseline bar for env-less lanes"
    services = {"radiance-flash-tp1": {"app-template": {"controllers": {"radiance":
                {"containers": {"radiance": {"env": [
                    {"name": "RADIANCE_MAX_NUM_SEQS", "value": "5"}]}}}}}}}
    assert G.lane_max_num_seqs("radiance-flash-tp1", chart8, services) == (5, None), \
        "the env-authoring lane's bar is its own 5"
    assert G.lane_max_num_seqs("radiance-q27-tp2", chart8, services) == (8, None), \
        "an env-less sibling keeps the chart fallback — per-lane, not shared"


def test_gate_per_lane_bars_are_the_designed_state_not_an_ambiguity(tmp_path):
    """The re-pin of the old "two distinct = ambiguous" rule (D-16). Per-lane
    resolution makes different bars across lanes the DESIGNED state, never an
    ambiguity — but the ambiguity guard keeps teeth for the case that still
    means ambiguity: a fallback that cannot be decided for the whole FORM (two
    distinct expansion matches), and the D49 absence law (a missing fallback)
    both still refuse."""
    chart8 = '  --max-num-seqs "${RADIANCE_MAX_NUM_SEQS:-8}"'
    env_5 = {"app-template": {"controllers": {"radiance": {"containers": {"radiance": {"env": [
        {"name": "RADIANCE_MAX_NUM_SEQS", "value": "5"}]}}}}}}
    services = {lane: env_5 for lane in ("radiance", "radiance-q27",
                                         "radiance-flash-tp1", "radiance-q27-tp2")}
    bars = {G.lane_max_num_seqs(l, chart8, services)[0] for l in G.LANES}
    assert bars == {5, 8}, (f"four env-authored lanes at 5 and the fp8_v4 lane at the fallback 8 is the "
                            f"designed per-lane state, not an ambiguity: {bars}")
    two = 'a --max-num-seqs "${RADIANCE_MAX_NUM_SEQS:-8}" b --max-num-seqs "${RADIANCE_MAX_NUM_SEQS:-32}"'
    fb, err = G.chart_seqs_fallback(two)
    assert fb is None and err is not None and "--max-num-seqs" in err, \
        f"a FORM whose fallback is undecided must REFUSE, naming the flag: {err}"
    none_fb, none_err = G.chart_seqs_fallback("nothing that configures seqs here")
    assert none_fb is None and none_err is not None and "cannot be evaluated" in none_err, \
        f"a missing fallback still refuses (the D49 absence law, re-cut's new form): {none_err}"


def test_gate_resolves_every_bar_to_the_chart_fallback_on_the_current_tree():
    """AC2a — the re-cut never invents bars. No lane authors a seqs env yet
    (C04/C05 land them, C03's block does not exist), so on the current tree
    ALL FIVE bars resolve from the chart fallback to the shipped 8; the fp8_v4
    lane resolves to 8 with no block present at all."""
    chart_text, err = G._read_chart_text(G.chart_values_path())
    assert err is None, err
    services = G._read_services_doc(G.services_values_path())
    assert not any(G.lane_max_num_seqs(l, chart_text, services)[0] != 8 for l in G.LANES), \
        {l: G.lane_max_num_seqs(l, chart_text, services) for l in G.LANES}


def test_receipt_gate_lanes_are_exactly_the_five_ruled_lanes():
    """D8: the block and the gate share the lane set — and it is the FIVE
    ruled lanes (the ticket's scope: the four context-window lanes plus this
    ticket's fp8_v4 lane), nothing more, nothing less. Cross-pinned against
    testlib's composition lanes so a lane rename cannot drift the two artifacts
    apart."""
    assert set(G.LANES) == {"radiance", "radiance-q27", "radiance-flash-tp1",
                            "radiance-q27-tp2", "radiance-q27-fp8v4"}
    assert set(G.LANES) == set(R.COMPOSITION_LANES)
    assert len(G.LANES) == len(set(G.LANES)) == 5


def test_command_block_enumerates_all_five_lanes_and_the_receipt_dir():
    """The pre-authored block: all five lanes enumerated with held + served
    facts, the five-session smoke gated to fn (D-16), the logs written to
    tests/radiance-receipt/ — and NEVER to evidence/ (the C03 pin's
    territory; a log there breaks the pin)."""
    block = G.RECEIPT_COMMAND_BLOCK
    for lane in G.LANES:
        assert f'"{lane}|' in block, f"the block must enumerate {lane}"
    assert "tests/radiance-receipt" in block
    assert "SMOKE: ADMITTED" in block and 'if [ "$name" = "radiance" ]' in block
    assert 'while [ "$i" -le 5 ]' in block, "the fn smoke loop must run five admitted sessions (D-16 superseding eight)"
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
