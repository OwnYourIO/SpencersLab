# cf-143 C02 — the FULL serving profile contract (chunks/C02.md Tests bullet 2;
# AC3). Q10 ruled the shadow profile VOID: the chart ships the complete
# RESEARCH "Serving envelope" — pool 43000 / 200K ctx / 8 seqs /
# --kv-resident 32768 / chunks 4096 / ngram on disk — as SINGLE-SOURCE
# scalars (args + resources splice from them; D15). Set equality is
# ORDER-INSENSITIVE (AC3) but EXACT: an extra flag is as red as a missing
# one, because every stale-guide survivor shipped is a boot-time refusal or
# a silently different memory story (RESEARCH "Guide corrections").
#
# Absence needles: no `serve` verb (the engine takes args directly), no
# --expert-vs-cache-ratio (stale), no --prefix-cache-mib (MUTUALLY EXCLUSIVE
# with --kv-resident — the 8-session lever IS kv-resident; idle sessions
# re-prefill against the x4-link wall, honest-envelope note per plan Risks),
# no --api-key (keyless D8/Q3-A).
#
# Red state at handoff (designed): all legs red until C02; the dual-edit
# service leg is gated on C04 (generation-witness law: it binds at once when
# the service block lands).
#
# Run per-directory: python3 -m pytest charts/radiance/tests -v

from __future__ import annotations

import collections

import pytest

import radiance_testlib as R

_ok, _reason = R.helm_ready()
helm_skip = pytest.mark.skipif(not _ok, reason=_reason)
c04_wiring = pytest.mark.skipif(
    not R.SERVICE_VALUES.is_file() or not R.service_block_present(),
    reason="cf-143 C04: the service radiance: subtree is not on this commit yet",
)


def _serve_args():
    docs, _ = R.render(service=False)
    args = R.serve_container(R.deployment(docs)).get("args") or []
    assert isinstance(args, list) and args, "C02 AC3: the serve container renders no args"
    return [str(a) for a in args]


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


def test_ac3_scalar_splice_is_single_source():
    """The four sizing scalars in chart values are the ONE home: rendered
    args AND resources both read from them (changing values must not need a
    second edit anywhere — D15 single-source law)."""
    vals = R.chart_values()
    app = vals.get("app-template") or {}
    for key, want in R.SCALARS.items():
        assert app.get(key) == want, (
            f"C02 AC3: app-template.{key} is {app.get(key)!r}, want {want} — the scalars are "
            "the single source (args+resources splice; runbook ladders are ONE edit)"
        )
    pairs = R.flag_pairs(_serve_args())
    assert pairs["--host-pool-mib"] == str(app["hostPoolMib"])
    assert pairs["--max-model-len"] == str(app["maxModelLen"])
    assert pairs["--max-num-seqs"] == str(app["maxNumSeqs"])
    assert pairs["--kv-resident"] == str(R.KV_RESIDENT_TOKENS)
    docs, _ = R.render(service=False)
    res = R.resources(R.serve_container(R.deployment(docs)))
    assert res["limits"]["memory"] == f"{app['guaranteedMemoryGi']}Gi"
    assert res["limits"]["cpu"] == str(app["cpuCores"])


def test_ac3_model_path_is_the_anchor():
    """--model equals the chart's modelPath anchor (the pack ledger: HF
    StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe, 121,969,901,568 B, lfs
    0af5e962…, ungated — RESEARCH RQ0)."""
    args = _serve_args()
    vals = (R.chart_values().get("app-template") or {})
    assert vals.get("modelPath") == R.MODEL_PATH, (
        f"C02 AC3: chart modelPath {vals.get('modelPath')!r}, want {R.MODEL_PATH}"
    )
    assert R.flag_pairs(args)["--model"] == vals["modelPath"], (
        "C02 AC3: --model does not splice the modelPath anchor (the vllm anchor-trap: anchors "
        "resolve per-document — the args carry the value, verified at render)"
    )


def test_ac3_absence_needles():
    args = _serve_args()
    joined = " ".join(args)
    pairs = R.flag_pairs(args)
    for flag in R.ABSENT_FLAGS:
        assert flag not in pairs and flag not in joined, (
            f"C02 AC3: {flag} shipped — {
                'prefix-cache is mutually exclusive with --kv-resident (D3: the 8-session lever IS kv-resident)'
                if flag == '--prefix-cache-mib' else
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
    """C02 Tests bullet 2 (dual-edit guard) + C04 AC5: once the service
    block lands, `--model` == chart modelPath == service re-pin — the vllm
    pattern (anchors do not cross documents; without the guard a service
    retarget silently misses the args)."""
    vals = (R.chart_values().get("app-template") or {})
    svc = R.service_block()
    sub = svc.get("app-template") or {}
    assert sub.get("modelPath") == vals.get("modelPath"), (
        f"C04 AC5: service modelPath {sub.get('modelPath')!r} != chart "
        f"{vals.get('modelPath')!r} — the retarget is a DUAL edit"
    )
    docs, _ = R.render(release="gpu-ai-radiance", service=True)
    pairs = R.flag_pairs([str(a) for a in (R.serve_container(R.deployment(docs)).get("args") or [])])
    assert pairs["--model"] == vals.get("modelPath"), (
        "C04 AC5: the SERVICE-level render's --model misses the chart anchor — anchors resolve "
        "per-document (gotcha 7), the splice must carry the chart value into the args"
    )


def test_scalars_commented_with_the_arithmetic():
    """The scalars ship with their why (plan: 'commented with the full
    arithmetic'): the guaranteedMemoryGi comment carries the owner's
    '60Gi-class' phrase + the receipt-gate note; the hostPoolMib comment
    names the Q10 ruling class; the coexistence Pending handshake is on the
    record (64+64+4 > 125.08 — Pending beside a live strata is the designed
    handshake, not a bug)."""
    text = R.chart_values_text()
    flat = " ".join(text.split())
    assert "60Gi-class" in flat, "C02: the guaranteedMemoryGi comment never names the owner's '60Gi-class' ruling (Q10)"
    assert "125.08" in flat and "Pending" in flat, (
        "C02: the coexistence arithmetic (64+64+4 > 125.08 allocatable => Pending beside live "
        "strata, the designed scale-down handshake) is not on the record"
    )
