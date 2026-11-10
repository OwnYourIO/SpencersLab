# cf-86 C06 — the Strata Q4 rung, FINAL Shape-A-tweak (plan
# 2026/2026-10-cf-86-feat-more-strata-models, chunks/C06.md FINAL pins /
# AC1-AC7). Authority: DECISIONS "Research verdicts + final rulings" (R-b
# OVERTURN, U6 confirmed, U8 rung+tweak) — a deviation here re-opens the gate,
# so the pin block below is asserted verbatim.
#
# Pins asserted since the executed 2026-11-01 on-target gate (owner half-
# restore ruling): --conversation-cache-mib 16384, --conversation-cache-slots
# 16, --memory-limit-mib 103680 with the container cgroup at 108Gi (lockstep
# pair), UD-Q4_K_XL paths. The U8-era conv 8192 + --slot-save-path pair is
# SUPERSEDED: the claim-compiled HIP engine rejected the session flag at argv
# (session files are the CUDA trial class; the Round-3 caveat, now measured),
# which voided the trim's compensation — conv was restored halfway.
# Negative pins: NO --slot-save-path (the engine refuses it); NO --layer-split
# and NO --prompt-cache 0 (session-file guard rails retired at the same gate —
# they stay out as untouched defaults, not as live protection); NO --ple-io
# ram (PLE stays mmap per the v0.2.7 +28.8 GiB RAM-resident hazard) and NO
# --ple-gguf sidecar (setup emits one only for ≤2-shard packs; this family has
# four shards).
#
# The Round-2 UD-IQ4_XS fallback (conv 32768 / cgroup+cap envelope sized for
# the SMALLER pack) was executed at the owner gate on 2026-11-01 and DECLINED
# on measurement: on this pack it computes ~116.7 of the 125 GiB node — the
# Oct-29 OOM-harvest shape. The half-restore above IS the shipped authority;
# a deviation re-opens that gate. The re-pin itself is test-session property
# per the cf-77/cf-83 law — this file moved under the gate ruling's citation,
# not as a dev edit.
#
# Cross-referenced arms living elsewhere: the ornith-Strata presence arm
# (test_catalog_contract.py::test_c05_ornith_strata_id_present_only_where_it_
# should_be — the C09 flip of the old Shape-B absence arm) and the q4 catalog
# entry + no-phantom law (same file).
#
# 2026-11-10 envelope round re-pins (owner-approved, post-SystemOOM-crashloop:
# cgroup + node floor exceeded the 125.1 GiB node; Strata #5697 heap
# retention): cgroup 116 -> 110Gi with NO cap moving (STRATA_CGROUP_LIMIT)
# and MALLOC_MMAP_THRESHOLD_=1048576 on all five arena envs. Same-day OWNER
# RULING reverted the round's q4 parallel 4 -> 2 and concurrencyLimit 1: q4
# keeps parallel 4 (the byte-identical-to-primary loop below) and NO
# concurrencyLimit — the protections are the 110Gi cgroup + the malloc env +
# the serialized-deep-prompts traffic law; the two-concurrent-deep-prefill
# shape is accepted risk. The gate-era history above stays the record; this
# round's pins ride their own arms below.

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
def test_c06_matrix_alternatives_over_the_full_arena_set():
    """(Named five at authoring, four after C08's sweep, five again at C09's
    `n` — the name now follows the table, not the era, so the wave-companions
    in test_strata_c09_ornith_arena.py carry the growth law and this arm just
    asserts the alternation.)"""
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
    assert reachable == arenas, f"arenas reachable in sets.main: {sorted(reachable)}, want all of them"
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
        ("--memory-limit-mib", str(S.Q4_MEMORY_LIMIT_MIB)),
    ):
        assert args.get(flag) == want, (
            f"post-gate pin {flag} {want!r} renders as {args.get(flag)!r} — the 2026-11-01 "
            "owner half-restore ruling; a deviation re-opens the gate"
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
    """Post-gate pins, executable (2026-11-01): --slot-save-path must be ABSENT
    — the claim-compiled HIP engine refuses it at argv. --layer-split and
    --prompt-cache 0 stay out as retired session-file guard rails (now default
    posture, not protection). --ple-io ram makes the 28.8 GiB n-gram table
    RAM-resident (the OOM that killed system pods on 2026-10-29). --batch is
    NOT a profile pin: the arm's parallel 4 reaches the engine as --batch
    through serve itself (2026-11-01 first-boot argv), so the old session-file
    rationale for banning it was doubly moot once the feature compiled out."""
    joined = " ".join(S.arg_tokens(_profile()))
    tokens = set(S.cmd_flag_tokens(joined))
    banned_flags = {"--layer-split", "--ple-io"}
    assert tokens, "the q4 profile renders no flags at all — every negative pin below passes vacuously"
    assert not tokens & banned_flags, f"negative-pinned flags present in strata-q4.json: {sorted(tokens & banned_flags)}"
    assert "--prompt-cache 0" not in joined, "--prompt-cache 0 in the Q4 arm (retired guard rail)"
    # The gate's own artifact: the flag that crashed the first boot stays out.
    pairs = dict(S.arg_pairs(_profile()))
    assert S.Q4_SESSION_FLAG not in pairs, (
        f"{S.Q4_SESSION_FLAG} is back in the q4 arm — the HIP engine exits 2 on it "
        "before it is ready (2026-11-01 first boot); conv 16384 is the compensation, not the flag"
    )


@helm
def test_c06_existing_profiles_stay_byte_unchanged_caps_are_per_rung():
    """AC2's second half: the earlier profiles are untouched at their own
    frozen eras, and every rung keeps ITS OWN declared cap — the lockstep law
    is per-rung, not a global raise. Fixtures are era-mapped in strata_testlib
    (strix's C07-era chain and the primary's T3/U14 chain are both guarded in
    test_strata_strix). Renamed from …_iq3_s_keeps_92160 at U14: the flagship's
    cap is now 110592 (its term-sum is 91.84 GiB, which 92160 never covered);
    92160 is orca's live number, pinned below."""
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        assert S.profile_fixture(file) == S.profile_json(_docs(), file), f"{file} diverged from its frozen-era capture"
    primary = dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)))
    assert primary.get("--memory-limit-mib") == str(S.PRIMARY_MEMORY_LIMIT_MIB), (
        f"IQ3_S engine cap reads {primary.get('--memory-limit-mib')!r}, want {S.PRIMARY_MEMORY_LIMIT_MIB} — "
        "U14 raised it to fit the rung's own terms inside what it declares"
    )
    orca = dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_ORCA_FILE)))
    assert orca.get("--memory-limit-mib") == "92160", (
        f"orca cap moved to {orca.get('--memory-limit-mib')!r} — U9.2's zero-envelope-growth law: "
        "the U14 cgroup raise does not leak into rungs that were never bumping against the ceiling"
    )
    if S.ABL_ID in S.inner_config(_docs())["models"]:
        abl = dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_ABL_FILE)))
        assert abl.get("--memory-limit-mib") == "92160", "the IQ3_XXS rungs keep the 92160 pair"


# --- AC3: the memory envelope renders as a pair -------------------------------


@helm
def test_c06_cgroup_108gi_and_engine_cap_lockstep():
    ctr = S.strata_container(_docs())
    res = ctr.get("resources") or {}
    limits, requests = res.get("limits") or {}, res.get("requests") or {}
    assert limits.get("memory") == S.Q4_CGROUP_LIMIT, (
        f"limits {limits} — the q4 arm rides the pod cgroup; the shipped pair is "
        f"({S.Q4_CGROUP_LIMIT}, {S.Q4_MEMORY_LIMIT_MIB}) since the 2026-11-10 "
        "envelope round lowered the ceiling 116Gi -> 110Gi with no cap moving"
    )
    assert requests.get("memory") == "64Gi", f"requests {requests} must stay 64Gi"
    cap = int(dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_Q4_FILE))).get("--memory-limit-mib", "0"))
    assert cap < 110 * 1024, f"engine cap {cap} MiB is not inside the 110Gi cgroup (#1601 pairing)"
    assert cap == S.Q4_MEMORY_LIMIT_MIB
    pod_spec = S.strata_pod(_docs())["spec"]
    assert pod_spec.get("terminationGracePeriodSeconds") == GRACE_SECONDS, (
        f"grace must stay {GRACE_SECONDS} (the 420 > 180+30 invariant is off-limits to C06): "
        f"{pod_spec.get('terminationGracePeriodSeconds')!r}"
    )


# --- 2026-11-10 envelope round: malloc arena + the owner's reverted levers ---


@helm
def test_2026_11_10_q4_carries_no_concurrency_limit():
    """Same-day OWNER RULING (2026-11-10) reverted the envelope round's
    concurrencyLimit 1 + parallel 4 -> 2 with the regression risk explicitly
    presented and accepted: q4 keeps parallel 4 (the byte-identical-to-primary
    loop above) and NO concurrencyLimit — the protections are the 110Gi cgroup
    (container dies before the node), MALLOC_MMAP_THRESHOLD_ (#5697) and the
    serialized-deep-prompts traffic law; two concurrent deep prefills is
    accepted risk."""
    assert "concurrencyLimit" not in _model(), (
        f"q4 model carries concurrencyLimit = {_model().get('concurrencyLimit')!r} — "
        "the owner's same-day ruling removed it; the protections are the 110Gi "
        "cgroup + the malloc env, not single-flighting"
    )


@helm
def test_2026_11_10_malloc_mmap_threshold_on_every_arena_env():
    """Strata #5697 (open): evicted conversation-cache parks stay in the glibc
    heap, so the engine's RAM admission gate refuses forever and MemAvailable
    never recovers. The one-env-line workaround rides every arena's model env
    (the retention is engine-wide behavior, not a per-rung property)."""
    models = S.inner_config(_docs())["models"]
    arenas = [i for i in (S.PRIMARY_ID, S.STRIX_ID, S.ORCA_INNER_ID, S.Q4_ID, S.ORNITH_ID) if i in models]
    assert len(arenas) == 5, f"expected five arenas, rendered {sorted(arenas)}"
    for aid in arenas:
        env = set(S.env_list(models[aid]))
        assert S.MALLOC_MMAP_ENV in env, (
            f"{aid} model env lacks {S.MALLOC_MMAP_ENV} — evicted parks stay in the "
            "glibc heap and the engine's RAM gate refuses forever (Strata #5697)"
        )


@helm
def test_c06_peers_wave_is_the_final_id_set():
    docs, _raw = S.render_service_overlay()
    served = set(S.inner_config(docs)["models"])
    outer = S.by_name_kind(docs, "ConfigMap", "llama-swap-config")
    peers = yaml.safe_load(outer["data"]["config.yaml"])["peers"][S.PEER_NAME]["models"]
    assert peers == S.expected_strata_peers(served), f"peers {peers} diverge from the wave for {sorted(served)}"
    if S.Q4_ID in served:
        assert peers == [S.PRIMARY_ID, S.STRIX_ID, S.ORCA_INNER_ID, S.Q4_ID, S.ORNITH_ID], (
            f"the final peers list must be the served Strata ids in card order: {peers} "
            "(four after C08's sweep; C09's ornith arena grows the fifth — the evidence wave "
            "chain records both states)"
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
    assert "mkdir -p " + S.Q4_SESSION_DIR in _init_script(), (
        f"the init script lacks the idempotent 'mkdir -p {S.Q4_SESSION_DIR}' (post-gate dir stays, the flag does not)"
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
