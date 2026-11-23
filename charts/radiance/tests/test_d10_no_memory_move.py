"""D10 (bug-radiance-27b-context-window 2026-11-23, coord-note): NO memory
value changes anywhere in this ticket.

C02 moves the four per-lane RADIANCE_MAX_MODEL_LEN env entries (the context
bound) and nothing else; the held 24Gi/110Gi pairs stay print-gated by
D7 / cf-143 D28(6) / cf-144 P11 — memory moves only on a contradicting
print, never pre-emptively (F2's arithmetic closed the sizing question, so
nothing pre-empts those prints). This leg pins the memory VALUES in the
values file — the edit site, so a later "helpful" re-pin is caught here
rather than trusted — for ALL FOUR lanes, and it is green pre- and
post-C02 (C02 does not touch it). The existing render-side legs (fn
110Gi in test_serve_args/test_render, the resting lanes' pairs in
test_resting_lanes, q27 24Gi in test_q27_lane) pin the rendered half;
this one pins the authored scalars the render splices from.
"""

from __future__ import annotations

import pytest
import yaml

import radiance_testlib as R

# The held pairs, per lane (D10/D7): fn + flash-TP1 hold the fn working set
# (110Gi), the 27b lanes hold the 24Gi band. Pre- and post-C02 — the context
# move is orthogonal to the cgroup price (plan fact 11).
HELD_MEMORY = {
    "radiance": "110Gi",
    "radiance-q27": "24Gi",
    "radiance-flash-tp1": "110Gi",
    "radiance-q27-tp2": "24Gi",
}


def _lane_app(name: str) -> dict:
    svc = yaml.safe_load(R.SERVICE_VALUES.read_text())
    block = svc.get(name)
    assert isinstance(block, dict), f"D10: no top-level {name}: block in the gpu-ai service values"
    return block.get("app-template") or {}


@pytest.mark.parametrize("lane,mem", sorted(HELD_MEMORY.items()))
def test_d10_held_memory_pair_is_unmoved_in_the_values_file(lane, mem):
    """D10: the authored resource pair is the HELD figure for every lane, both
    maps equal (the Guaranteed law) — C02's context move must not ride on a
    memory re-pin, and a later "helpful" one reddens this leg in the values
    file before it ever reaches the render."""
    app = _lane_app(lane)
    cont = (((app.get("controllers") or {}).get("radiance") or {}).get("containers") or {}).get("radiance") or {}
    res = cont.get("resources") or {}
    for side in ("requests", "limits"):
        got = (res.get(side) or {}).get("memory")
        assert got == mem, (
            f"D10: {lane} resources.{side}.memory is {got!r}, want the held {mem!r} — "
            "no memory value changes anywhere in this ticket (D7: prints price numbers, "
            "estimates do not; cf-143 D28(6)/cf-144 P11). The context move (C02) touches "
            "the RADIANCE_MAX_MODEL_LEN env only; a memory re-pin is a separate print-gated act"
        )


def test_d10_fn_guaranteed_memory_scalar_is_the_held_110():
    """D10: fn's block scalar is the P11 HELD 110 (the render-side legs splice
    from it — pinning the scalar pins the whole chain, source to render)."""
    app = _lane_app("radiance")
    got = app.get("guaranteedMemoryGi")
    assert got == R.SCALARS["guaranteedMemoryGi"] == 110, (
        f"D10: radiance-block app-template.guaranteedMemoryGi is {got!r}, want the held "
        "110 (P11; the DOWN re-pin is post-boot, print-gated) — the context move does not "
        "pre-empt that print"
    )
