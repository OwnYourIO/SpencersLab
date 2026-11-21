# cf-144 C03 — strata host-index enumeration contract (OQ-E/P07; doc §4
# rows 1–2; EXPLORE §6.4 gotcha 4). DESIGN: the two keys below name HOST
# POSITION, and position moved when the second R9700 landed 2026-11-21
# (BDFs c3/c7 cards + c8 APU — the ROCm INDEX order is exactly what the
# owner `rocminfo` receipt decides; the chunk is receipt-gated, C01 claimed
# the pair is live-2 without any table edit). Radiance itself is immune (the
# named pool injects devices, env absent by the C02 absence law) — do not
# sweep radiance or the dormant vllm lane from here (chunk Notes).
#
# HONEST POSTURE, both receipt outcomes:
#   * RECEIPT MOVED ⇒ dev edits values + comment; the equality legs redden
#     until the strata_testlib constants block (the single re-pin site,
#     ROCR_PRIMARY/ROCR_STRIX) moves in the same wave, and the receipt-
#     marker leg reddens a moved pair that carries no dated rocminfo
#     sentence in the values comment. The stale-story leg reddens a moved
#     pair whose comment still tells the pre-card2 tale verbatim.
#   * RECEIPT UNMOVED ⇒ no values edit, constants stay, every leg here is
#     green — the honest no-op close.
#   * RECEIPT NOT LANDED IN-RUN ⇒ chunk closes DEFERRED (recorded, not red):
#     these legs are consistent-vs-consistency checks, NOT demands that
#     C03 ran. What no repo leg can do is second-guess the host itself: an
#     unchanged pair against a MOVED enumeration is repo-invisible BY
#     DESIGN — that is the owner's rocminfo half of the gate. The claim-2
#     exposure (strata restore-back binding wrong silicon, the 307/310
#     crash-loop class) survives only through that half, so the gate stays
#     where doc §4 puts it; the suite's job is that a re-pin cannot land
#     half-moved, unprovenanced, self-contradictory, or out of the 3-GPU
#     domain, and that the strix index is asserted by a render leg where
#     none existed before this ticket.
#
# The pre-ticket fixture evidence/cf143-pre-ticket-strata/ keeps its
# historical ROCR_VISIBLE_DEVICES=0 bytes — an ORACLE, never re-pin it.
#
# Run per-directory: python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import re

import pytest
import yaml

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)


def _chart_strata_block() -> tuple[dict, str]:
    """The strata: subtree of charts/llama-swap/values.yaml, plus the raw
    comment region around the two index keys (the enumeration story lives
    there; YAML parses no comments, so the legs read text)."""
    text = (S.CHART_DIR / "values.yaml").read_text()
    sub = yaml.safe_load(text)["strata"]
    return sub, text


def _index_pair(sub: dict) -> tuple:
    primary = str(sub.get("rocrVisibleDevices"))
    by_model = sub.get("rocrVisibleDevicesByModel") or {}
    strix = str(by_model.get(S.STRIX_ID))
    return primary, strix


def _enumeration_violations(pair, count: int) -> list:
    """Pure invariant validator over an (primary, strix, index-domain)
    triple: distinct, integer-parsable, inside the 0..count-1 enumeration.
    Returns the violation list — empty means clean. Self-proven green-both-
    ways by test_c03_validator_teeth below (§12.14: an arm that cannot red
    the lie AND green the truth is half a tripwire)."""
    errs = []
    primary, strix = pair
    vals = []
    for name, tok in (("rocrVisibleDevices", primary), ("strix", strix)):
        try:
            vals.append(int(tok))
        except (TypeError, ValueError):
            errs.append(f"{name}={tok!r} is not an integer host index")
    if len(vals) == 2:
        if vals[0] == vals[1]:
            errs.append(f"primary and strix bind the SAME host index {vals[0]} — the strix "
                        "fallback's 'names the OTHER silicon' invariant (doc §4, chunk AC3)")
        for v in vals:
            if not 0 <= v < count:
                errs.append(f"index {v} is outside the 0..{count - 1} host enumeration domain "
                            f"({count} GPUs since card 2 landed — EXPLORE §0; a wider index binds nothing)")
    return errs


# --- equality vs the single re-pin site (designed shape of C03's test-wave) ----


def test_c03_values_match_the_constants_site_pairwise():
    """Chart values AND the gpu-ai service overlay must equal the
    strata_testlib constants block (ROCR_PRIMARY/ROCR_STRIX). The overlay
    re-pins the primary key, so a one-sided move anywhere reddens here,
    naming the ONE edit site — this is the leg C03's moved-receipt wave
    drives; the no-op wave keeps it green untouched."""
    sub, _ = _chart_strata_block()
    pair = _index_pair(sub)
    assert pair == (S.ROCR_PRIMARY, S.ROCR_STRIX), (
        f"cf-144 C03: chart values strata index pair {pair} != the constants site "
        f"{(S.ROCR_PRIMARY, S.ROCR_STRIX)} — if the rocminfo receipt MOVED the indices, values "
        "and strata_testlib's ROCr block move in ONE wave (single re-pin site; a values-only "
        "edit is a half-move). If no receipt landed, this leg's red means an unprovenanced "
        "edit — route it back through the C03 gate, never by silently re-pinning here"
    )
    overlay = S.service_strata_overlay()
    assert str(overlay.get("rocrVisibleDevices")) == S.ROCR_PRIMARY, (
        f"cf-144 C03: service overlay strata.rocrVisibleDevices {overlay.get('rocrVisibleDevices')!r} "
        "drifted from the chart/constants pair — the overlay re-pin and the chart key are ONE fact"
    )


def test_c03_invariants_hold_on_both_sides_of_the_pin():
    """Distinct + integer + in-domain, checked on the constants (the test
    side's own re-pin self-guard) AND on the chart values (dev's side)."""
    assert _enumeration_violations((S.ROCR_PRIMARY, S.ROCR_STRIX), S.ROCR_HOST_GPU_COUNT) == [], (
        "cf-144 C03: the constants block itself violates the enumeration invariants — the "
        "re-pin site moved wrong; fix HERE first"
    )
    sub, _ = _chart_strata_block()
    errs = _enumeration_violations(_index_pair(sub), S.ROCR_HOST_GPU_COUNT)
    assert not errs, "cf-144 C03: " + "; ".join(errs)


# --- render-level: the indices reach the inner config (strix leg is NEW) -------


@helm
def test_c03_rendered_inner_config_carries_the_pinned_indices():
    """Primary model env ROCR_VISIBLE_DEVICES==ROCR_PRIMARY (the cf-143 leg's
    semantics, now resolved through the constants) and the STRIX model env
    ROCR_VISIBLE_DEVICES==ROCR_STRIX — the latter had NO render leg before
    cf-144: an unasserted strix index is exactly how a mis-bound APU lane
    would 'silently pass' today, so this leg closes the coverage gap the
    receipt gate needs armed for."""
    docs = S.render_on()[0]
    inner = S.inner_config(docs)
    for mid, want, why in (
        (S.PRIMARY_ID, S.ROCR_PRIMARY, "primary lane (an R9700 — PR #3636 hide-the-APU intent)"),
        (S.STRIX_ID, S.ROCR_STRIX, "strix fallback (the OTHER silicon)"),
    ):
        env = S.env_list(inner["models"][mid])
        rocr = [e for e in env if e.startswith("ROCR_VISIBLE_DEVICES=")]
        assert rocr == [f"ROCR_VISIBLE_DEVICES={want}"], (
            f"cf-144 C03: {mid} renders {rocr}, want exactly "
            f"[ROCR_VISIBLE_DEVICES={want}] — {why}; the values keys are the only sanctioned "
            "re-pin path (template untouched — chunk 'Values keys ONLY')"
        )


# --- overlay-merged strix resolution (cf-144 C03 review minor M-3) -------------


def _c03_merged_bymodel() -> tuple:
    """The MERGED strata index state the gpu-ai release actually renders from:
    the service overlay's strata block deep-merges OVER the chart's (the appset
    `index $.Values` merge), so an overlay-added rocrVisibleDevicesByModel map
    wins per-key. Returns (merged_global, merged_bymodel) as strings/dicts —
    pure values reads, deterministic, no cluster."""
    chart_sub, _ = _chart_strata_block()
    overlay = S.service_strata_overlay()
    merged_global = str(overlay.get("rocrVisibleDevices",
                                    chart_sub.get("rocrVisibleDevices")))
    bymodel = {**(chart_sub.get("rocrVisibleDevicesByModel") or {}),
               **(overlay.get("rocrVisibleDevicesByModel") or {})}
    return merged_global, {str(k): str(v) for k, v in bymodel.items()}


def test_c03_overlay_merged_bymodel_resolution_equals_the_site():
    """cf-144 C03 review minor (M-3): the hole was silent — an overlay-added
    `strata.rocrVisibleDevicesByModel` strix pin (e.g. the stale "1") merges
    OVER the chart key in the live appset shape, the chart-level equality leg
    reads only the chart side, and the P16 oracle carve SENTINELS exactly the
    rendered strix ROCr line — so such a pin could pass the whole suite.
    This leg resolves the strix lane through the MERGED values with the
    template's own precedence (configmap-strata.yaml: `default primary
    (get byModel model)` — byModel non-empty wins, else global) and demands
    the constants site. Any merged strix resolution — chart, overlay-added,
    or overlay-overridden — that is not ROCR_STRIX reddens HERE, naming the
    overlay as the divergent layer when it is the author."""
    merged_global, merged_bymodel = _c03_merged_bymodel()
    resolved = merged_bymodel.get(S.STRIX_ID) or merged_global
    assert resolved == S.ROCR_STRIX, (
        f"cf-144 C03 M-3: MERGED strix resolution is {resolved!r}, want {S.ROCR_STRIX!r} "
        f"(the constants site). byModel layers — chart: "
        f"{(_chart_strata_block()[0].get('rocrVisibleDevicesByModel') or {})!r}, overlay: "
        f"{(S.service_strata_overlay().get('rocrVisibleDevicesByModel') or {})!r} — an "
        "overlay byModel pin must match the receipted site or go absent; editing it is "
        "the same one-wave law as the chart key (values-only, never the template)"
    )


@helm
def test_c03_merged_service_overlay_render_strix_env_equals_the_site():
    """M-3's end-to-end twin: render the gpu-ai SERVICE-OVERLAY MERGE (the
    exact P16 oracle path) and read the strix model's ROCR_VISIBLE_DEVICES
    env line from the strata-config inner config. The oracle leg cannot
    witness this (the carve sentinel removes strix's line from its compare);
    this leg compares it raw against the site, so the shipped value and any
    future layer drift are both caught at the render, not only at the
    values."""
    docs, _raw = S.render_service_overlay("gpu-ai")
    env = S.env_list(S.inner_config(docs)["models"][S.STRIX_ID])
    rocr = [e for e in env if e.startswith("ROCR_VISIBLE_DEVICES=")]
    assert rocr == [f"ROCR_VISIBLE_DEVICES={S.ROCR_STRIX}"], (
        f"cf-144 C03 M-3: merged overlay render injects {rocr} for {S.STRIX_ID}, want "
        f"exactly [ROCR_VISIBLE_DEVICES={S.ROCR_STRIX}] — this is the line the P16 carve "
        "exempts FROM THE ORACLE, which is precisely why this leg exists (the exemption "
        "must never become an open door for a third value)"
    )


# --- the receipt-provenance one-way arm (fires ONLY in a moved world) ----------


def test_c03_moved_pair_requires_dated_rocminfo_provenance_in_the_comment():
    """The designed posture for the receipt outcome (OQ-E: 'receipt now'):
    dormant while the pair equals the PRE-receipt story (0, 1) — that is
    both today's tree and the honest no-op close. The moment the pair
    MOVES, the values comment beside the keys must carry the dated
    rocminfo receipt sentence AND must stop telling the pre-card2 story
    verbatim ('dGPU first, chip second') — an unprovenanced or story-stale
    re-pin reddens instead of silently shipping wrong silicon."""
    sub, text = _chart_strata_block()
    pair = _index_pair(sub)
    if pair == S.ROCR_PRE_CARD2_PAIR:
        return  # today / no-op world: dormant arm, honest by design (see header)
    start = text.index("rocrVisibleDevices:")
    window = text[max(0, start - 3000): start + 3000]
    flat = " ".join(window.split())
    errs = []
    if not (re.search(r"rocminfo", flat, re.I) and re.search(r"(?i)receipt", flat)
            and re.search(r"2026-\d\d-\d\d", flat)):
        errs.append("a moved index pair without a dated rocminfo receipt sentence in the values "
                    "comment (tokens: rocminfo + receipt + a yyyy-mm-dd date) — C03's whole point "
                    "is that every shipped index equals the receipt line-for-line (chunk AC1)")
    if re.search(r"dGPU first, chip second", flat):
        errs.append("the pair moved but the comment still asserts the PRE-card2 story verbatim "
                    "('dGPU first, chip second') — the chunk's re-pin task updates the enumeration "
                    "story accordingly; leaving it is the stale-narrative half-move")
    assert not errs, "cf-144 C03: " + "; ".join(errs)


# --- validator teeth (§12.14 green-both-ways, runs every time) ------------------


def test_c03_validator_teeth_green_both_ways():
    """The invariant validator must GREEN the truthful pairs and RED the
    mis-bind classes: same-index (the mis-bound-strix lie), out-of-domain
    (binds nothing / a fourth GPU the receipt never claimed), non-integer."""
    clean = ("0", "1"), ("1", "2"), ("0", "2")
    for pair in clean:
        assert _enumeration_violations(pair, S.ROCR_HOST_GPU_COUNT) == [], (
            f"cf-144 C03 teeth DEFECT: truthful pair {pair} REJECTED — half tripwire, "
            "the TEST lane owns this repair"
        )
    lies = {
        ("0", "0"): "same index",
        ("2", "2"): "same index",
        ("3", "1"): "out of domain",
        ("0", "-1"): "out of domain",
        ("", "1"): "non-integer",
    }
    for pair, _why in lies.items():
        assert _enumeration_violations(pair, S.ROCR_HOST_GPU_COUNT), (
            f"cf-144 C03 teeth DEFECT: mis-bind pair {pair} PASSED clean — the invariant legs "
            "above are half a tripwire"
        )
