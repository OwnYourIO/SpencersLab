# cf-86 C06 — the Strata Q4 rung, FINAL Shape-A-tweak (plan
# 2026/2026-10-cf-86-feat-more-strata-models, chunks/C06.md FINAL pins /
# AC1-AC7). Authority: DECISIONS "Research verdicts + final rulings" (R-b
# OVERTURN, U6 confirmed, U8 rung+tweak) — a deviation here re-opens the gate,
# so the pin block below is asserted verbatim.
#
# FINAL pins asserted: --conversation-cache-mib 8192, --conversation-cache-
# slots 16, --slot-save-path /models/strata/sessions, --memory-limit-mib 95232
# with the container cgroup at 100Gi (lockstep pair), UD-Q4_K_XL paths.
# Negative pins: NO --batch, NO --layer-split, NO --prompt-cache 0, NO
# --ple-io ram (session files are disabled by the first three; PLE stays mmap
# per the v0.2.7 +28.8 GiB RAM-resident hazard).
#
# The Round-2 UD-IQ4_XS fallback (conv 32768 / 108Gi / 102400) is NOT a second
# passing shape: it is a human-owned on-target outcome (first HIP session
# save/restore round-trip). If that gate trips, the revert is routed back to
# the test session for a re-pin with the DECISIONS citation — never a dev edit
# of this file.
#
# Cross-referenced arms living elsewhere: the ornith Shape-B absence-arm
# (test_catalog_contract.py::test_c05_ornith_strata_id_absent_everywhere) and
# the q4 catalog entry + no-phantom law (same file).

from __future__ import annotations

import pytest
import yaml

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

GRACE_SECONDS = 420


def _docs():
    return S.render_on()[0]


def _model() -> dict:
    models = S.inner_config(_docs())["models"]
    assert S.Q4_ID in models, f"inner config serves no {S.Q4_ID} — C06 not landed (arenas: {sorted(models)})"
    return models[S.Q4_ID]


def _profile() -> dict:
    file = S.profile_file_of(_model())
    assert file == S.PROFILE_Q4_FILE, f"q4 arena names {file!r}, want the frozen {S.PROFILE_Q4_FILE!r}"
    return S.profile_json(_docs(), file)


def _args() -> dict:
    return dict(S.arg_pairs(_profile()))


def _init_container() -> dict:
    docs, _raw = S.render_service_overlay()
    inits = S.strata_pod(docs)["spec"].get("initContainers") or []
    hits = [c for c in inits if c.get("name") == "model-fetch"]
    assert hits, f"strata pod has no model-fetch init: {[c.get('name') for c in inits]}"
    return hits[0]


def _init_script() -> str:
    ctr = _init_container()
    return "\n".join([str(x) for x in (ctr.get("command") or [])] + [str(x) for x in (ctr.get("args") or [])])


def _init_env() -> dict:
    out = {}
    for e in _init_container().get("env") or []:
        if isinstance(e, dict) and e.get("name"):
            out[e["name"]] = e.get("value")
    return out


# --- AC1: the arena and the five-way alternation ------------------------------


@helm
def test_c06_q4_arena_served_with_residency_contract():
    new, primary = _model(), S.inner_config(_docs())["models"][S.PRIMARY_ID]
    for key, want in (("ttl", 3600), ("unloadTimeout", 180), ("checkEndpoint", "/health")):
        assert new.get(key) == want, f"{S.Q4_ID}.{key} = {new.get(key)!r}, want {want!r}"
    assert new["cmd"] == primary["cmd"].replace(
        f"--profile /profile/{S.PROFILE_PRIMARY_FILE}", f"--profile /profile/{S.PROFILE_Q4_FILE}"
    ), f"q4 cmd must mirror the frozen serve wrapper (ulimit wrapper is load-bearing): {new['cmd']!r}"
    flags = set(S.cmd_flag_tokens(new["cmd"]))
    assert not flags - S.SERVE_FLAGS, f"serve flags outside the frozen set: {sorted(flags - S.SERVE_FLAGS)}"


@helm
def test_c06_matrix_alternatives_over_all_five_arenas():
    cfg = S.inner_config(_docs())
    vars_ = (cfg.get("matrix") or {}).get("vars") or {}
    assert vars_.get("q") == S.Q4_ID, f"matrix.vars.q = {vars_.get('q')!r}"
    arenas = set(S.INNER_MATRIX_VARS)
    combos = S.matrix_expansions(cfg).get("main", [])
    for combo in combos:
        clash = combo & arenas
        assert len(clash) <= 1, (
            f"matrix combo co-loads arenas {sorted(clash)} — the ~64 GiB Q4 arena on top of "
            "another arena recreates #1715's node OOM"
        )
    reachable = {next(iter(c & arenas)) for c in combos if c & arenas}
    assert reachable == arenas, f"arenas reachable in sets.main: {sorted(reachable)}, want all five"
    assert S.profile_files(_docs()) == S.expected_profile_files(cfg["models"]), (
        "profile ConfigMap key set diverges from the served arenas"
    )


# --- AC2: the FINAL pin block, verbatim --------------------------------------


@helm
def test_c06_final_pin_block_verbatim():
    args = _args()
    for flag, want in (
        ("--conversation-cache-mib", str(S.Q4_CONV_CACHE_MIB)),
        ("--conversation-cache-slots", str(S.Q4_CONV_CACHE_SLOTS)),
        ("--slot-save-path", S.Q4_SLOT_SAVE_PATH),
        ("--memory-limit-mib", str(S.Q4_MEMORY_LIMIT_MIB)),
    ):
        assert args.get(flag) == want, (
            f"FINAL pin {flag} {want!r} renders as {args.get(flag)!r} — U8/Round-3 authority; "
            "a deviation re-opens the gate"
        )


@helm
def test_c06_profile_shape_and_ud_q4_k_xl_paths():
    prof = _profile()
    assert prof.get("api_key") == S.API_KEY_NONE
    assert prof.get("user_args") == []
    args = _args()
    primary = dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)))
    for flag in ("--pack", "--native"):
        val = args.get(flag) or ""
        assert val.startswith("/models/strata/Strata-data/"), f"{flag} = {val!r} outside Strata-data"
        assert val != primary.get(flag), f"{flag} reuses the IQ3_S primary's path"
        assert "q4" in val.lower(), (
            f"{flag} = {val!r} carries no Q4 class marker — the Round-2 UD-Q4_K_XL inventory "
            "lays weights under a Q4-class dir; a name-guess here is the wrong weights"
        )
    for key in ("exe", "cwd", "lib_dirs", "backend", "gpu", "parallel", "host"):
        if key in prof:
            assert prof[key] == S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE).get(key), (
                f"q4 profile {key} diverges from the primary — the engine build/paths are "
                "per-node, not per-rung; only the data paths may differ"
            )


@helm
def test_c06_negative_pins_absent_from_the_q4_arm():
    """Round-2 findings, executable: --batch / --layer-split / --prompt-cache 0
    disable session files outright, and --ple-io ram makes the 28.8 GiB n-gram
    table RAM-resident (the OOM that killed system pods on 2026-10-29). The
    FINAL shape depends on all four staying out."""
    joined = " ".join(S.arg_tokens(_profile()))
    tokens = set(S.cmd_flag_tokens(joined))
    banned_flags = {"--batch", "--layer-split", "--ple-io"}
    assert not tokens & banned_flags, f"negative-pinned flags present in strata-q4.json: {sorted(tokens & banned_flags)}"
    assert "--prompt-cache 0" not in joined, "--prompt-cache 0 in the Q4 arm (disables session files)"
    assert S.Q4_SLOT_SAVE_PATH in dict(S.arg_pairs(_profile())), (
        "negative pins passed but the session path vanished — the pair is what makes the arm meaningful"
    )


@helm
def test_c06_existing_profiles_stay_byte_unchanged_iq3_s_keeps_92160():
    """AC2's second half: the four earlier profiles are untouched, and the
    IQ3_S pair (92160 inside 96Gi-era pins) keeps its numbers — the lockstep
    law is per-pair, not a global raise."""
    import json

    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        before = json.loads((S.EVIDENCE_DIR / "strata-profiles-pre-cf86" / file).read_text())
        assert before == S.profile_json(_docs(), file), f"{file} diverged from the pre-cf-86 capture"
    iq3s = dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)))
    assert iq3s.get("--memory-limit-mib") == "92160", (
        f"IQ3_S engine cap moved to {iq3s.get('--memory-limit-mib')!r} — the Q4 rung rides its OWN pair"
    )
    if S.ABL_ID in S.inner_config(_docs())["models"]:
        abl = dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_ABL_FILE)))
        assert abl.get("--memory-limit-mib") == "92160", "the IQ3_XXS rungs keep the 92160 pair"


# --- AC3: the memory envelope renders as a pair -------------------------------


@helm
def test_c06_cgroup_100gi_and_engine_cap_lockstep():
    ctr = S.strata_container(_docs())
    res = ctr.get("resources") or {}
    limits, requests = res.get("limits") or {}, res.get("requests") or {}
    assert limits.get("memory") == S.Q4_CGROUP_LIMIT, (
        f"limits {limits} — the Q4 rung needs the 100Gi cgroup; the pair is (100Gi, {S.Q4_MEMORY_LIMIT_MIB})"
    )
    assert requests.get("memory") == "64Gi", f"requests {requests} must stay 64Gi"
    cap = int(dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_Q4_FILE))).get("--memory-limit-mib", "0"))
    assert cap < 100 * 1024, f"engine cap {cap} MiB is not inside the 100Gi cgroup (#1601 pairing)"
    assert cap == S.Q4_MEMORY_LIMIT_MIB
    pod_spec = S.strata_pod(_docs())["spec"]
    assert pod_spec.get("terminationGracePeriodSeconds") == GRACE_SECONDS, (
        f"grace must stay {GRACE_SECONDS} (the 420 > 180+30 invariant is off-limits to C06): "
        f"{pod_spec.get('terminationGracePeriodSeconds')!r}"
    )


@helm
def test_c06_peers_wave_is_the_five_id_set():
    docs, _raw = S.render_service_overlay()
    served = set(S.inner_config(docs)["models"])
    outer = S.by_name_kind(docs, "ConfigMap", "llama-swap-config")
    peers = yaml.safe_load(outer["data"]["config.yaml"])["peers"][S.PEER_NAME]["models"]
    assert peers == S.expected_strata_peers(served), f"peers {peers} diverge from the wave for {sorted(served)}"
    if S.Q4_ID in served:
        assert peers == [S.PRIMARY_ID, S.STRIX_ID, S.ABL_ID, S.ORCA_INNER_ID, S.Q4_ID], (
            f"the C06-final peers list must be the five frozen ids in card order: {peers}"
        )


# --- AC4: init wiring — q4 token, sessions dir, no new secrets ---------------


@helm
def test_c06_init_fetches_the_q4_pack_without_new_secret_material():
    env = _init_env()
    quants = str(env.get("STRATA_QUANTS") or "")
    assert "q4" in quants.replace(",", " ").split(), f"STRATA_QUANTS = {quants!r} carries no q4 token"
    model = str(env.get("STRATA_MODEL_Q4") or "")
    assert "unsloth/UD-Q4_K_XL" in model, (
        f"STRATA_MODEL_Q4 = {model!r} — the Round-2 unsloth family token is the frozen value"
    )
    assert "mkdir -p " + S.Q4_SLOT_SAVE_PATH in _init_script(), (
        f"the init script lacks the idempotent 'mkdir -p {S.Q4_SLOT_SAVE_PATH}' (C06 disk gate)"
    )


@helm
def test_c06_no_token_touch_for_the_q4_rung():
    """unsloth is public: C02's download-only exception must not spread. The
    serve path stays keyless and the init keeps exactly one secret consumer
    (the hf-token entry C02 sanctioned), no new names."""
    hits = S.serve_path_secret_hits(S.render_service_overlay()[0])
    assert not hits, f"secret material on the strata serve path: {hits}"
    env = _init_container().get("env") or []
    secrets = [e for e in env if isinstance(e, dict) and "valueFrom" in e]
    for e in secrets:
        name = e["valueFrom"].get("secretKeyRef", {}).get("name")
        assert name == "hf-token", f"init consumes an unexpected Secret {name!r} for the ungated q4 pack"
