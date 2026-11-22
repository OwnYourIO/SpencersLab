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
# suite).
#
# 2026-11-feat-radiance-multi-instance C03 carrier move: the lane DATA this
# suite pins (args, scalars, modelPath, the receipt comment) moved from
# charts/radiance/values.yaml into the radiance: roster block (OQ-D mechanism-
# only shell); the block-fed render is what production feeds the pod.
#
# 2026-11-22 owner ruling D43 re-anchored the whole suite a second time: the
# fn lane's profile is no longer proven against RENDERED ARGS (those bytes
# leave the render) but against the vector the chart-owned serve wrapper
# COMPOSES at boot from the lane's rendered env — proven by executing the
# shipped carrier in the sandbox (radiance_testlib's D43 harness). The
# TP2_LEDGER_KEYS splice guard retired with the rendered arg it ledgered
# against; the single-source law it served now runs as the env-authority
# equality. The arithmetic-comment leg (C12 AC1) is untouched — it prices a
# memory scalar, not argv.
#
# Red state at handoff (designed): the D43 legs are RED until dev round 3
# lands the wrapper and the fn env block.
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


def _fn_composition():
    """The fn lane's D43 triple: shipped serve wrapper + rendered env + sandbox
    facts. Designed-red naming dev round 3 while the carrier or the lane env is
    absent (radiance_testlib.lane_composition raises with the ruling named)."""
    return R.lane_composition("radiance")


@c04_wiring
@helm_skip
def test_ac3_composed_vector_is_the_full_profile_set():
    """Set equality, order-insensitive, exact — every flag once, every value
    as pinned — at the RUNTIME shape D43 ruled: the vector the engine receives
    when the shipped wrapper boots on this lane's rendered env."""
    comp = _fn_composition()
    facts = comp["facts"]
    assert facts["rc"] == 0, (
        f"C03/D43: the serve wrapper died on the fn env (rc {facts['rc']}, "
        f"stderr {facts['stderr'][:200]!r})"
    )
    argv = facts["argv"]
    assert argv, "C03/D43: the engine stub never ran — no composed vector to compare"
    pairs = R.flag_pairs(argv)
    want = {f: str(v) for f, v in R.FULL_PROFILE.items()}
    missing = {f: v for f, v in want.items() if pairs.get(f) != v}
    extra = {f: v for f, v in pairs.items() if f not in want}
    assert not missing and not extra, (
        f"C02 AC3/D43: composed vector diverges from the FULL pinned profile (Q10/D17/P04)\n"
        f"  missing/incorrect: {missing}\n  extra: {extra}"
    )
    seen = collections.Counter(a for a in argv if a.startswith("--"))
    dupes = {f: c for f, c in seen.items() if c > 1}
    assert not dupes, f"C02 AC3: duplicated flags {dupes} — the profile ships each exactly once"


@c04_wiring
@helm_skip
def test_ac3_env_is_the_single_sizing_source():
    """The sizing single-source law at its D43 shape: the pod resources still
    splice from the fn BLOCK scalars (guaranteedMemoryGi 110 is the P11 HELD
    value; cpu is authored), and every non-FORM profile value reaches the
    vector through exactly ONE env channel — the rendered RADIANCE_* env
    equals the profile's projection exactly. The era's scalar/ledger splice
    (TP2_LEDGER_KEYS against rendered args) retired 2026-11-22 with D43: there
    is no rendered arg to half-move anymore; the env equality subsumes it."""
    block = R.service_block()
    assert isinstance(block, dict), "C03: no radiance: block — the scalar home does not exist yet"
    app = block.get("app-template") or {}
    for key in ("guaranteedMemoryGi", "cpuCores"):
        assert app.get(key) == R.SCALARS[key], (
            f"C03/D43: radiance-block app-template.{key} is {app.get(key)!r}, want {R.SCALARS[key]} — "
            "resources splice from the block scalars (guaranteedMemoryGi 110 is the P11 HELD value, "
            "the DOWN re-pin is post-boot)"
        )
    docs, _ = R.render(release="gpu-ai-radiance", service=True)
    res = R.resources(R.serve_container(R.deployment(docs)))
    assert res["limits"]["memory"] == f"{app['guaranteedMemoryGi']}Gi"
    assert res["limits"]["cpu"] == str(app["cpuCores"])
    comp = _fn_composition()
    want_env = R.expected_env(R.FULL_PROFILE)
    got_env = comp["env"]
    missing = {k: v for k, v in want_env.items() if got_env.get(k) != v}
    extra = {k: v for k, v in got_env.items() if k not in want_env}
    assert not missing and not extra, (
        f"C03/D43: the fn lane's rendered RADIANCE_* env diverges from the profile projection\n"
        f"  missing/incorrect: {missing}\n  extra (second channel or unmapped): {extra}"
    )


@c04_wiring
@helm_skip
def test_ac3_model_path_is_the_anchor():
    """--model equals the block's modelPath (the pack ledger: HF
    StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe, 121,969,901,568 B, lfs
    0af5e962…, ungated — RESEARCH RQ0). D43 made the anchor THREE-place:
    modelPath ledger == env RADIANCE_MODEL_PATH == composed --model; any two
    agreeing while the third drifts is how a lane serves the sibling's pack."""
    block = R.service_block()
    vals = (block.get("app-template") or {}) if isinstance(block, dict) else {}
    assert vals.get("modelPath") == R.MODEL_PATH, (
        f"C03: block modelPath {vals.get('modelPath')!r}, want {R.MODEL_PATH}"
    )
    comp = _fn_composition()
    env_model = comp["env"].get(R.ENV_MODEL_PATH)
    assert env_model == R.MODEL_PATH, (
        f"C03/D43: rendered env {R.ENV_MODEL_PATH}={env_model!r}, want {R.MODEL_PATH!r} — env is "
        "the lane's pack channel"
    )
    argv = comp["facts"]["argv"]
    assert argv, "C03/D43: no composed vector (see the AC1 leg)"
    assert R.flag_pairs(argv)["--model"] == env_model == vals["modelPath"], (
        "C03/D43: the three-place modelPath anchor broke (ledger / env / composed --model)"
    )


@c04_wiring
@helm_skip
def test_ac3_absence_needles():
    """Absence at both layers: the composed vector must not carry the banned
    flags, and the lane env must not feed the env names that would produce
    them (D43 turned absence into an env law — a flag is absent because its
    env is absent)."""
    comp = _fn_composition()
    argv = comp["facts"]["argv"]
    assert argv, "C03/D43: no composed vector (see the AC1 leg)"
    pairs = R.flag_pairs(argv)
    for flag in R.ABSENT_FLAGS:
        assert flag not in pairs, (
            f"C02 AC3 (cf-144 C01 polarity): {flag} composed — {
                'TP2 ships the prefix tier and the mirror is mutually exclusive with it — kv-resident back in would take the tier away (P04, doc §7)'
                if flag == '--kv-resident' else
                'api-key contradicts the keyless ruling (D8)' if 'api-key' in flag else
                'stale-guide flag (RESEARCH Guide corrections)'
            }"
        )
    for env_name, flag in R.ENV_TO_FLAG.items():
        if flag in R.ABSENT_FLAGS:
            assert env_name not in comp["env"], (
                f"C03/D43: env {env_name} is authored although {flag} is a banned flag — "
                "env-absent is the absence mechanism; authoring it re-arms the refusal"
            )
    assert "serve" not in argv, (
        "C02 AC3: a `serve` VERB token — radiance takes the args directly (RESEARCH RQ0: no "
        "serve verb; the vllm entrypoint double-verbs it)"
    )


@c04_wiring
@helm_skip
def test_dual_edit_guard_model_path_matches_service_repin():
    """C02 Tests bullet 2 (dual-edit guard) + C04 AC5, re-anchored twice (C03
    moved the carrier to the block; D43 moved the served value into env + the
    composed vector): the ledger modelPath, the rendered env and the composed
    --model are ONE fact in THREE places. A retarget that moves one side and
    not the others is how a lane serves the sibling's pack; the guard reddens
    whatever the direction."""
    svc = R.service_block()
    sub = svc.get("app-template") or {}
    comp = _fn_composition()
    argv = comp["facts"]["argv"]
    assert argv, "C03/D43: no composed vector (see the AC1 leg)"
    composed = R.flag_pairs(argv).get("--model")
    assert sub.get("modelPath") == comp["env"].get(R.ENV_MODEL_PATH) == composed, (
        f"C03/D43: modelPath {sub.get('modelPath')!r} / env {comp['env'].get(R.ENV_MODEL_PATH)!r} "
        f"/ composed {composed!r} — three writes of one fact must move together"
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
