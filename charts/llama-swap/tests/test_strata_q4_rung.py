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
# per the v0.2.7 +28.8 GiB RAM-resident hazard), and NO --ple-gguf sidecar
# (setup emits one only for ≤2-shard packs; this family has four shards).
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

import os

import pytest
import yaml

import llama_swap_testlib as L
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
    """C07 re-anchor (chunks/C07.md): the driver body lives in the baked image
    file now, so the staging-dir law follows the code, not the render. Red
    until the C07 port lands the file."""
    return S.read(S.FETCH_SH, "cf-86 C07 lift — the staging driver is baked at /opt/strata/bin now")


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
def test_c06_matrix_alternatives_over_all_four_arenas():
    """(Named five-arenas at authoring; C08's U9.3 sweep — the arenas are four
    now, the alternation law is unchanged.)"""
    cfg = S.inner_config(_docs())
    vars_ = (cfg.get("matrix") or {}).get("vars") or {}
    assert vars_.get("q") == S.Q4_ID, f"matrix.vars.q = {vars_.get('q')!r}"
    arenas = set(S.INNER_MATRIX_VARS.values())  # combos hold resolved MODEL ids, not letters
    combos = S.matrix_expansions(cfg).get("main", [])
    for combo in combos:
        clash = combo & arenas
        assert len(clash) <= 1, (
            f"matrix combo co-loads arenas {sorted(clash)} — the ~64 GiB Q4 arena on top of "
            "another arena recreates #1715's node OOM"
        )
    reachable = {next(iter(c & arenas)) for c in combos if c & arenas}
    assert reachable == arenas, f"arenas reachable in sets.main: {sorted(reachable)}, want all four"
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
    assert tokens, "the q4 profile renders no flags at all — every negative pin below passes vacuously"
    assert not tokens & banned_flags, f"negative-pinned flags present in strata-q4.json: {sorted(tokens & banned_flags)}"
    assert "--prompt-cache 0" not in joined, "--prompt-cache 0 in the Q4 arm (disables session files)"
    # The session path is a VALUE, not a flag: arg_pairs keys are flags, so
    # membership in the key set can never hold for any correct profile.
    pairs = dict(S.arg_pairs(_profile()))
    assert pairs.get("--slot-save-path") == S.Q4_SLOT_SAVE_PATH, (
        f"negative pins passed but the session path vanished — --slot-save-path is "
        f"{pairs.get('--slot-save-path')!r}, want {S.Q4_SLOT_SAVE_PATH!r}; the pair is what "
        "makes the arm meaningful"
    )


@helm
def test_c06_existing_profiles_stay_byte_unchanged_iq3_s_keeps_92160():
    """AC2's second half: the four earlier profiles are untouched, and the
    IQ3_S pair (92160 inside 96Gi-era pins) keeps its numbers — the lockstep
    law is per-pair, not a global raise. Fixtures are era-mapped in
    strata_testlib (strix's C07-era chain guarded in test_strata_strix)."""
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        assert S.profile_fixture(file) == S.profile_json(_docs(), file), f"{file} diverged from its frozen-era capture"
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
def test_c06_peers_wave_is_the_final_id_set():
    docs, _raw = S.render_service_overlay()
    served = set(S.inner_config(docs)["models"])
    outer = S.by_name_kind(docs, "ConfigMap", "llama-swap-config")
    peers = yaml.safe_load(outer["data"]["config.yaml"])["peers"][S.PEER_NAME]["models"]
    assert peers == S.expected_strata_peers(served), f"peers {peers} diverge from the wave for {sorted(served)}"
    if S.Q4_ID in served:
        assert peers == [S.PRIMARY_ID, S.STRIX_ID, S.ORCA_INNER_ID, S.Q4_ID], (
            f"the C08-final peers list must be the four served ids in card order: {peers} "
            "(five at C06 authoring; C08's U9.3 sweep removed the abliterated entry)"
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


# --- AC4/AC6: the pack shape, then the live source it stages from (gated) -----


@helm
def test_c06_pack_profile_carries_no_ple_gguf_line():
    """setup.py@v0.2.7 emits `--ple-gguf` only for packs of two shards or fewer
    (`["--ple-gguf", ple] if len(shards) <= 2 else []`), and this family has
    four. A guessed shard here is the wrong-weights failure, so the line's
    absence is a pin, not an omission."""
    args = dict(S.arg_pairs(_profile()))
    assert "--ple-gguf" not in args, (
        f"q4 profile carries --ple-gguf {args['--ple-gguf']!r} — a 4-shard pack gets no PLE "
        "sidecar from setup, and a hand-written one points at the wrong weights"
    )


hf_gated = pytest.mark.skipif(
    os.environ.get("RUN_HF_CHECK") != "1",
    reason="evidence gate: RUN_HF_CHECK=1 re-reads the unsloth UD-Q4_K_XL tree the q4 pack stages from",
)

# Read 2026-10-30 from the HF tree API with no credential — the family lists
# anonymously, which is what makes AC4's "no new secret material" true. The
# chart's pack comment names these same four sizes; its SUM line (111,334,256,784)
# is 398,000 B below the sum of its own cited shards, so the per-shard values
# below are the authority and the comment waits on the docs round (TEST_SPEC
# §9.12 records the discrepancy and who owes the fix).
Q4_REPO = "unsloth/Qwen3.8-Flash-Next-GGUF"
Q4_REF = "UD-Q4_K_XL"
Q4_SHARD_BYTES = {
    "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf": 10_946_624,
    "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf": 49_859_583_136,
    "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf": 49_376_141_504,
    "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf": 12_087_983_520,
}
Q4_PACK_TOTAL = sum(Q4_SHARD_BYTES.values())


@hf_gated
def test_c06_q4_shard_family_is_the_four_shard_pack_it_stages_from():
    """Churn guard for the pack source: the RAM/VRAM pair was sized for this
    family's bytes, and a re-shard changes both the download and what setup
    stages. Same discipline as the llama.cpp pick arms — the loader/setup rule
    (llama_swap_testlib.hf_pick/hf_split_family) is mirrored here, so a tree
    re-organization goes red in review instead of on the node."""
    entries = L.hf_tree(Q4_REPO, Q4_REF)
    shards = {e["path"]: int(e["size"]) for e in entries if str(e["path"]).endswith(".gguf")}
    assert shards, f"no .gguf under {Q4_REPO}:{Q4_REF} — the pack source vanished or moved"
    assert shards == Q4_SHARD_BYTES, (
        f"{Q4_REPO}:{Q4_REF} shard set moved: {shards} != the pinned {Q4_SHARD_BYTES} — "
        "re-run the source gate and re-pin through the test session"
    )
    assert sum(shards.values()) == Q4_PACK_TOTAL, (
        f"family total {sum(shards.values())} != the {Q4_PACK_TOTAL} the envelope math counts"
    )
    paths = [e["path"] for e in entries]
    picked = L.hf_pick(paths, Q4_REF)
    declared = L.hf_split_info(picked)[2] if picked else 0
    family = L.hf_split_family(paths, picked) if picked else []
    assert picked and declared == 4 and len(family) == 4, (
        f"{Q4_REF} no longer resolves to a complete 4-of-4 family (pick {picked!r}, "
        f"declared {declared}, family {family}) — a partial pack serves as wrong weights"
    )
    staged = dict(S.arg_pairs(_profile())).get("--native") or ""
    assert picked and staged.endswith(picked.rpartition("/")[2]), (
        f"profile --native {staged!r} is not the primary shard of the live family "
        f"({picked!r}) — the pack would stage from other files"
    )
