# cf-143 C02 — the FULL serving profile contract (chunks/C02.md Tests bullet 2;
# AC3). Q10 ruled the shadow profile VOID: the chart ships the complete
# RESEARCH "Serving envelope" as SINGLE-SOURCE scalars (args + resources splice
# from them; D15). Set equality is ORDER-INSENSITIVE (AC3) but EXACT: an extra
# flag is as red as a missing one, because every stale-guide survivor shipped
# is a boot-time refusal or a silently different memory story (RESEARCH "Guide
# corrections").
#
# cf-144 C01 TP2 re-pin (plan P04/OQ-C, owner "Confirm as specced"): the
# profile is the doc §7 multiset — tp 2 + tp-wire wht6, per-rank pool 12288,
# chunk 2048, prefix-cache 4096 IN, kv-resident OUT (the ABSENT_FLAGS polarity
# flipped with it). Memory stays PINNED at 110 — the P11 owner ruling "Hold
# 110, re-pin after the print" (the 48 draft value must never appear in this
# suite). Red state at handoff (designed): the flipped legs are RED against
# today's TP1/claim-1 tree and green against the C01 implementation. The
# dual-edit service leg stays C04-gated (generation-witness law: it binds at
# once when the service block lands).
#
# 2026-11-feat-radiance-multi-instance C03 carrier move: the lane DATA this
# suite pins (args, scalars, modelPath, the receipt comment) moved from
# charts/radiance/values.yaml into the radiance: roster block (OQ-D mechanism-
# only shell). Every leg now reads the BLOCK carrier — same arithmetic, same
# set equality, new source path; the block-fed render is what production feeds
# the pod.
#
# Run per-directory: python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import collections
import re

import pytest

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)
c04_wiring = pytest.mark.skipif(
    not R.SERVICE_VALUES.is_file() or not R.service_block_present(),
    reason="cf-143 C04: the service radiance: subtree is not on this commit yet",
)


def _serve_args():
    """The fn lane's rendered args — per-BLOCK since the C03 carrier move: the
    chart ships no lane args (mechanism only), so the roster block is the only
    carrier left that can serve anything. The render path is the appset-merge
    shape (chart + the extracted radiance: subtree)."""
    docs, _ = R.render(release="gpu-ai-radiance", service=True)
    args = R.serve_container(R.deployment(docs)).get("args") or []
    assert isinstance(args, list) and args, "C02 AC3: the serve container renders no args"
    return [str(a) for a in args]


@c04_wiring
def test_ac3_args_are_the_full_profile_set():
    """Set equality, order-insensitive, exact — every flag once, every value
    as pinned. The scalars splice at their pinned values."""
    args = _serve_args()
    pairs = R.flag_pairs(args)
    want = dict(R.FULL_PROFILE)
    missing = {f: v for f, v in want.items() if pairs.get(f) != v}
    extra = {f: v for f, v in pairs.items() if f not in want}
    assert not missing and not extra, (
        f"C02 AC3: serve args diverge from the FULL pinned profile (Q10/D17)\n"
        f"  missing/incorrect: {missing}\n  extra: {extra}"
    )
    seen = collections.Counter(a for a in args if a.startswith("--"))
    dupes = {f: c for f, c in seen.items() if c > 1}
    assert not dupes, f"C02 AC3: duplicated flags {dupes} — the profile ships each exactly once"


@c04_wiring
def test_ac3_scalar_splice_is_single_source():
    """The sizing scalars in the fn BLOCK are the ONE home: rendered args AND
    resources both read from them (changing values must not need a second
    edit anywhere — D15 single-source law, whose carrier moved to the block at
    C03). cf-144 C01: hostPoolMib is the TP2 per-rank 12288;
    guaranteedMemoryGi splices the PAIR at the HELD 110
    (P11 — this leg is why a silent 110→48 or one-sided pair bump reddens);
    the tp/recipe constants are carrier-shape-agnostic — if dev ledgered any
    TP2_LEDGER_KEYS scalar, it must equal the rendered arg, so a HALF-MOVE of
    one side cannot stay green either way (C01 splice-guard contract)."""
    block = R.service_block()
    assert isinstance(block, dict), "C03: no radiance: block — the scalar home does not exist yet"
    app = block.get("app-template") or {}
    for key, want in R.SCALARS.items():
        assert app.get(key) == want, (
            f"cf-144 C01: radiance-block app-template.{key} is {app.get(key)!r}, want {want} — the scalars are "
            "the single source (args+resources splice; runbook ladders are ONE edit; "
            "guaranteedMemoryGi 110 is the P11 HELD value, the DOWN re-pin is post-boot)"
        )
    pairs = R.flag_pairs(_serve_args())
    assert pairs["--host-pool-mib"] == str(app["hostPoolMib"])
    assert pairs["--max-model-len"] == str(app["maxModelLen"])
    assert pairs["--max-num-seqs"] == str(app["maxNumSeqs"])
    for key, flag in R.TP2_LEDGER_KEYS.items():
        if key in app:
            assert str(app[key]) == pairs.get(flag) == R.FULL_PROFILE[flag], (
                f"cf-144 C01: ledgered app-template.{key}={app[key]!r}, rendered {flag}="
                f"{pairs.get(flag)!r}, profile pins {R.FULL_PROFILE[flag]!r} — a half-move of "
                "one side does not stay green (carrier-shape-agnostic splice guard)"
            )
    docs, _ = R.render(release="gpu-ai-radiance", service=True)
    res = R.resources(R.serve_container(R.deployment(docs)))
    assert res["limits"]["memory"] == f"{app['guaranteedMemoryGi']}Gi"
    assert res["limits"]["cpu"] == str(app["cpuCores"])


@c04_wiring
def test_ac3_model_path_is_the_anchor():
    """--model equals the block's modelPath (the pack ledger: HF
    StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe, 121,969,901,568 B, lfs
    0af5e962…, ungated — RESEARCH RQ0). Post-C03 the trap runs in REVERSE at
    this lane too: the block's args carry the path LITERALLY (app-template
    renders args verbatim — no splice exists), so modelPath is the ledger the
    args must agree with, verified at the block-fed render."""
    args = _serve_args()
    block = R.service_block()
    vals = (block.get("app-template") or {}) if isinstance(block, dict) else {}
    assert vals.get("modelPath") == R.MODEL_PATH, (
        f"C03: block modelPath {vals.get('modelPath')!r}, want {R.MODEL_PATH}"
    )
    assert R.flag_pairs(args)["--model"] == vals["modelPath"], (
        "C03: --model does not equal the block modelPath — args are literal bytes (the app-template "
        "no-tpl law), so a retarget that edits only one side serves the wrong pack"
    )


@c04_wiring
def test_ac3_absence_needles():
    args = _serve_args()
    joined = " ".join(args)
    pairs = R.flag_pairs(args)
    for flag in R.ABSENT_FLAGS:
        assert flag not in pairs and flag not in joined, (
            f"C02 AC3 (cf-144 C01 polarity): {flag} shipped — {
                'TP2 ships the prefix tier and the mirror is mutually exclusive with it — kv-resident back in would take the tier away (P04, doc §7)'
                if flag == '--kv-resident' else
                'api-key contradicts the keyless ruling (D8)' if 'api-key' in flag else
                'stale-guide flag (RESEARCH Guide corrections)'
            }"
        )
    assert "serve" not in args, (
        "C02 AC3: a `serve` VERB token — radiance takes the args directly (RESEARCH RQ0: no "
        "serve verb; the vllm entrypoint double-verbs it)"
    )
    assert "--api-key" not in joined, "C02 AC3: --api-key present (keyless: D8)"


@c04_wiring
def test_dual_edit_guard_model_path_matches_service_repin():
    """C02 Tests bullet 2 (dual-edit guard) + C04 AC5, C03 carrier re-aim: the
    chart no longer ships a modelPath (mechanism-only shell), so BOTH sides of
    the dual edit live in the block — the ledger `modelPath` must equal the
    `--model` the block's own args actually serve. A retarget that moves one
    side and not the other is how a lane serves the sibling's pack; the guard
    reddens it whatever the direction."""
    svc = R.service_block()
    sub = svc.get("app-template") or {}
    docs, _ = R.render(release="gpu-ai-radiance", service=True)
    pairs = R.flag_pairs([str(a) for a in (R.serve_container(R.deployment(docs)).get("args") or [])])
    assert sub.get("modelPath") == pairs["--model"], (
        f"C03: block modelPath {sub.get('modelPath')!r} != served --model {pairs['--model']!r} — "
        "args are literal bytes (no splice), so ledger and served path are one fact written twice"
    )


@c04_wiring
def test_scalars_commented_with_the_arithmetic():
    """AC6, era-pinned twice (C03 moved the carrier: the arithmetic comment now
    sits in the fn roster block beside the scalars it prices — same needles,
    same mandates, region text of the block is the source): C08 T-D demanded the D17 per-token derivation
    (19.3/8.9) and a class-median marking; C12 AC4 (ORIGINAL) replaced that
    basis with the printed-receipt arithmetic at the plan's 96; the C12
    AMENDMENT (owner batched answer "110 GiB (your figure)", D29) re-points
    the value AND the sums — the comment must now answer 'where did 110 come
    from': the 71.04-GiB printed budget (report 2), the owner ruling over
    D28's 96 ceiling, §D6.2's exact terms (UP 110+64+6.3 = 180.3 > 125.08 —
    the designed Pending survives; DOWN 110 + router 4.125 + system 1.158 =
    115.28 <= 125.08, 9.80 GiB free), the engine-rule walk 110 - 71.04 =
    38.96 >= 4, and the prints-its-own-budget law line. RED today (C12): the
    shipped comment still carries the 64-era derivation; the value itself
    stays pinned by the scalar-splice leg, so a comment rewrite that drops a
    mandated fact reddens HERE, not silently."""
    text = R.lane_region_text("radiance")
    flat = " ".join(text.split())
    assert "71.04" in flat, (
        "C12 AC1: the receipt anchor 71.04 (the engine's printed 'pinned by this process "
        "71.04 GiB', report 2) is absent — the scalar must be receipt-anchored (D28 class law)"
    )
    assert re.search(r"(?i)owner ruling|your figure|D29", flat), (
        "C12 AC1 amendment: the comment does not mark the 110 as the OWNER'S RULING "
        "('110 GiB (your figure)', D29 over D28's 96) — provenance of a ruling differs from a "
        "plan figure; §D6.1 says 110 is nowhere a radiance plan number (it is strata's limit "
        "envelope), so the comment must say who chose it and why it is legal"
    )
    assert re.search(r"110\s*\+\s*64\s*\+\s*6\.3|180\.3[^.]{0,30}125\.08", flat) and "Pending" in flat, (
        "C12 AC1 amendment: the strata-UP arithmetic (110+64+6.3 = 180.3 > 125.08 ⇒ designed "
        "Pending, step-3 handshake restated at 110) is not in the comment"
    )
    assert re.search(r"115\.28|110\s*\+\s*4\.125", flat) and "9.80" in flat, (
        "C12 AC1 amendment: the strata-DOWN schedulability (110+4.125+1.158 = 115.28 <= 125.08, "
        "9.80 GiB free — §D6.2's exact live terms) is not stated — the old 96-pair (102.3/22.8) "
        "dies with the ruling"
    )
    assert "38.96" in flat and re.search(r"(?i)(≥ ?4|>= ?4)", flat), (
        "C12 AC1: the engine-rule walk (110 - 71.04 = 38.96 >= 4 free-under-cgroup) is missing — "
        "the >=4 rule stated WITHOUT its computed slack at the shipped value is the vocabulary-"
        "not-arithmetic class §12.11 names"
    )
    assert re.search(r"(?i)prints? (its|the) own budget", flat), (
        "C12 AC1/D28: the budget-line law line ('the engine prints its own budget — read it') "
        "is missing — the sentence that makes the NEXT profile change walk the receipt"
    )
