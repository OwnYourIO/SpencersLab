# cf-86 C01 — the SC117 abliterated IQ3_XXS Strata rung (plan
# 2026/2026-10-cf-86-feat-more-strata-models, chunks/C01.md AC1-AC7).
#
# Red posture (pipeline-role-test): the needles naming the new arena are RED
# pre-dev — the id, its profile file, the third matrix var. The PRESERVATION
# arms (pre-cf-86 profiles byte-deep-equal, off-parity, serve-path keyless)
# are green today and must stay green; a red there is drift, not a queue.
#
# Frozen ids/paths are test-author property from DECISIONS "Renumap + final-
# shape decisions" and the chunk's cmd literal. Model-DIR names are NOT
# pinned: C01's catalog gate parameterizes them ("never guessed"), so the arms
# here pin the path SHAPE (under Strata-data, distinct from the IQ3_S pair)
# plus everything the chunk froze verbatim.

from __future__ import annotations

import pytest
import yaml

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)


def _on():
    return S.render_on()[0]


def _inner():
    return S.inner_config(_on())


def _served_arenas() -> set:
    return set(_inner()["models"])


def _model(model_id: str) -> dict:
    models = _inner()["models"]
    assert model_id in models, (
        f"inner config serves no {model_id} — C01 not landed (arenas: {sorted(models)})"
    )
    return models[model_id]


def _profile_for(model_id: str) -> dict:
    file = S.profile_file_of(_model(model_id))
    assert file, f"{model_id}: cmd names no /profile file"
    return S.profile_json(_on(), file)


# --- AC2: the arena entry, its residency contract, and the matrix law --------


@helm
def test_c01_abliterated_arena_served():
    """The third inner arena exists with the primary's residency contract —
    ttl/unloadTimeout/checkEndpoint equality is what keeps the cold-pin time-
    share discipline and the 420s grace invariant honest for a new rung."""
    models = _inner()["models"]
    assert S.ABL_ID in models, (
        f"inner config serves no {S.ABL_ID} — C01 not landed (arenas: {sorted(models)})"
    )
    new, primary = models[S.ABL_ID], models[S.PRIMARY_ID]
    for key, want in (("ttl", 3600), ("unloadTimeout", 180), ("checkEndpoint", "/health")):
        assert new.get(key) == want, f"{S.ABL_ID}.{key} = {new.get(key)!r}, want {want!r}"
    assert new["cmd"] == primary["cmd"].replace(
        f"--profile /profile/{S.PROFILE_PRIMARY_FILE}",
        f"--profile /profile/{S.PROFILE_ABL_FILE}",
    ), f"{S.ABL_ID} cmd must mirror the primary's serve wrapper verbatim (ulimit + exec + PORT macro): {new['cmd']!r}"


@helm
def test_c01_serve_flag_surface():
    """serve takes ONLY --profile/--host/--port (run-1 RESEARCH §2 interface
    freeze): tuning that leaks into the cmd line bypasses the profile JSON and
    the plan gate."""
    cmd = _model(S.ABL_ID)["cmd"]
    flags = set(S.cmd_flag_tokens(cmd))
    extra = flags - S.SERVE_FLAGS
    assert not extra, f"{S.ABL_ID}: serve flags outside the frozen set: {sorted(extra)}"


@helm
def test_c01_matrix_grows_to_three_alternatives():
    """vars ⊇ {p,s,c} and every DNF combo holds exactly ONE arena — the
    arenas page-lock RAM additively on the 128 GB node, so a two-arena combo
    recreates cf-77 #1715's node OOM (the whole reason the set is an
    alternation)."""
    cfg = _inner()
    vars_ = (cfg.get("matrix") or {}).get("vars") or {}
    want = {S.INNER_MATRIX_VARS[k]: k for k in ("p", "s", "c")}
    for model_id, letter in want.items():
        assert vars_.get(letter) == model_id, f"matrix.vars.{letter} = {vars_.get(letter)!r}, want {model_id!r}"
    combos = S.matrix_expansions(cfg).get("main", [])
    # matrix_expansions resolves vars to MODEL ids, so the arena set must be the
    # VALUES of the letter table — intersecting on the letters (p/s/c/…) would
    # match nothing and make the law vacuously true.
    arenas = set(S.INNER_MATRIX_VARS.values())
    for combo in combos:
        clash = combo & arenas
        assert len(clash) <= 1, f"matrix combo co-loads arenas {sorted(clash)} — arenas must stay alternatives"
    reachable = {next(iter(c & arenas)) for c in combos if c & arenas}
    assert set(want) <= reachable, (
        f"arenas reachable in sets.main: {sorted(reachable)}, want at least {sorted(set(want))}"
    )


@helm
def test_c01_arena_roster_and_profiles_agree():
    """No phantom arena and no orphan profile: the strata-profile ConfigMap's
    key set equals exactly the files the served arenas' --profile flags name."""
    models = _inner()["models"]
    files = S.profile_files(_on())
    assert files == S.expected_profile_files(models), (
        f"profile ConfigMap keys {sorted(files)} != the profiles the served arenas name "
        f"{sorted(S.expected_profile_files(models))}"
    )
    for mid, file in S.INNER_PROFILE_FILES.items():
        if mid in models:
            assert f"/profile/{file}" in models[mid]["cmd"], f"{mid} does not name /profile/{file}"


# --- AC3: the run-config profile ---------------------------------------------


@helm
def test_c01_abliterated_profile_is_valid_run_config():
    """JSON validity IS the red (run-1 AC5 lineage): api_key "none", the IQ3_XXS
    model_name the chunk froze, user_args empty, and the exe/cwd/backend
    identity byte-identical to the primary (same node, same engine build)."""
    prof = _profile_for(S.ABL_ID)
    assert prof.get("api_key") == S.API_KEY_NONE, f"api_key {prof.get('api_key')!r}"
    assert prof.get("model_name") == "qwen3.8-flash-next-abliterated-iq3_xxs", (
        f"model_name {prof.get('model_name')!r}"
    )
    assert prof.get("user_args") == [], f"user_args {prof.get('user_args')!r}"
    primary = S.profile_json(_on(), S.PROFILE_PRIMARY_FILE)
    for key in ("exe", "cwd", "lib_dirs", "backend", "gpu", "parallel", "host"):
        if key in primary:
            assert prof.get(key) == primary[key], (
                f"abliterated profile {key} = {prof.get(key)!r} != primary {primary[key]!r} "
                "— the engine build is per-node, not per-rung"
            )


@helm
def test_c01_profile_envelope_matches_the_iq3_s_pair():
    """No memory-key changes on this rung (chunk Notes: the ~50 GiB arena sits
    inside today's envelope), so the #1601 pair and the parked-conversation
    arms must equal the primary's — the pair is cgroup-lockstepped in
    test_strata_render.py, and a silent trim here is a second, untracked budget."""
    args = dict(S.arg_pairs(_profile_for(S.ABL_ID)))
    primary = dict(S.arg_pairs(S.profile_json(_on(), S.PROFILE_PRIMARY_FILE)))
    for flag in ("--memory-limit-mib", "--kv-resident", "--conversation-cache-mib",
                 "--conversation-cache-slots"):
        assert args.get(flag) == primary.get(flag), (
            f"abliterated {flag} = {args.get(flag)!r} != primary {primary.get(flag)!r}"
        )
    for flag, value in (("--max-context", "262144"), ("--kv", "int8"),
                        ("--expert-cache", "auto")):
        assert args.get(flag) == value, f"abliterated {flag} = {args.get(flag)!r}, want {value!r}"


@helm
def test_c01_paths_are_strata_data_shaped_and_distinct():
    """Path SHAPE law, deliberately not name-pinned: the catalog gate (C01 AC1)
    parameterizes the IQ3_XXS directory names, so the executable contract is
    'under Strata-data, and not the IQ3_S primary's files' — a rung pointing at
    the primary's pack serves the wrong weights under a new id."""
    args = dict(S.arg_pairs(_profile_for(S.ABL_ID)))
    primary = dict(S.arg_pairs(S.profile_json(_on(), S.PROFILE_PRIMARY_FILE)))
    for flag in ("--pack", "--native"):
        val = args.get(flag) or ""
        assert val.startswith("/models/strata/Strata-data/"), f"{flag} = {val!r} outside Strata-data"
        assert val != primary.get(flag), f"{flag} reuses the IQ3_S primary's path — wrong weights behind a new id"
    # tokenizer is a TOP-LEVEL run-config key, never an engine arg: the pinned
    # checkout's vocabulary (setup.py@v0.2.7 SETUP_KEYS) and both serving
    # profiles spell it beside `args`, and it resolves to the tokenizer
    # DIRECTORY riding inside each pack (the seed's GGUF-file pointer was the
    # crash strata.py named).
    prof = _profile_for(S.ABL_ID)
    tok = prof.get("tokenizer")
    assert isinstance(tok, str) and tok.startswith("/models/strata/Strata-data/"), (
        f"profile-level tokenizer = {tok!r} — absent, or spelled as an engine arg instead of the profile key"
    )
    assert not any("tokenizer" in str(a) for a in S.arg_tokens(prof)), (
        "tokenizer appears among the engine args — the engine never parses it there"
    )
    assert tok != S.profile_json(_on(), S.PROFILE_PRIMARY_FILE).get("tokenizer"), (
        "abliterated arena resolves the IQ3_S pack's tokenizer directory — each pack carries its own"
    )


@helm
def test_c01_node_bleed_flags_stay_absent():
    """The 2026-10-29 OOM doctrine is node-wide, not rung-wide: a second arena
    that re-admits --ple-io / --batch / --layer-split / --prompt-cache recreates
    the kill. Absence is the pin; re-admitting one needs a test-session re-pin
    with a capacity plan, never a silent dev edit."""
    tokens = set(S.cmd_flag_tokens(" ".join(S.arg_tokens(_profile_for(S.ABL_ID)))))
    banned = {"--ple-io", "--batch", "--layer-split", "--resident-budget-gib",
              "--prompt-cache", "--kv-grow", "--vision"}
    assert not tokens & banned, f"forbidden engine flags in the abliterated profile: {sorted(tokens & banned)}"
    assert S.VOID_ENV_TOKEN not in S.env_list(_model(S.ABL_ID))


@helm
def test_c01_inner_alias_is_frozen_and_does_not_shadow_the_family():
    """C01 freezes the inner alias `qwen3.8-flash-next-abliterated` and forbids
    a claim on `qwen3.8-flash-next`: the two serving arenas already share that
    family alias, so a third claimant on the same route key would spread
    requests across arenas invisibly."""
    prof = _profile_for(S.ABL_ID)
    val = prof.get("aliases")
    claimed = {val} if isinstance(val, str) else set(val or [])
    assert "qwen3.8-flash-next-abliterated" in claimed, (
        f"abliterated profile aliases {sorted(claimed)}, want the frozen 'qwen3.8-flash-next-abliterated'"
    )
    assert "qwen3.8-flash-next" not in claimed, (
        "the abliterated arena shadows the family alias qwen3.8-flash-next"
    )


# --- AC3 preservation: the pre-cf-86 profiles are untouched -------------------

@helm
def test_c01_existing_profiles_byte_unchanged():
    """Byte-unchanged existing profiles, enforced against the captured pre-
    cf-86 fixtures (evidence/strata-profiles-pre-cf86/) on the PARSED JSON —
    helm re-wrap is not behavior, a changed arg is. The outer goldens stay
    byte-invariant too (additive-preservation precedent, TEST_SPEC)."""
    import json

    fixtures = S.EVIDENCE_DIR / "strata-profiles-pre-cf86"
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        before = json.loads((fixtures / file).read_text())
        after = S.profile_json(_on(), file)
        assert before == after, (
            f"{file} diverged from the pre-cf-86 capture — C01 may only ADD a "
            f"profile; drift here is a re-tune of a serving rung: {sorted(set(before) ^ set(after))}"
        )


@helm
def test_c01_inner_config_carries_no_engine_profile_keys():
    """Strip-list arm: the supervisor config must not carry engineProfile*
    keys — they live in the profile ConfigMap, and a second copy in the inner
    config is a fork of the run-config truth."""
    leaked = [k for k in _inner() if k.startswith("engineProfile")]
    assert not leaked, f"inner config carries profile keys: {leaked}"


# --- AC6: keyless serve path (SC117 is ungated) -------------------------------


@helm
def test_c01_serve_path_is_keyless():
    """No secret chain on the SERVE path. C02's R-d ruling sanctions the
    hf-token Secret for DOWNLOAD ONLY on the model-fetch init, so from that
    chunk on the init is a scoped exception — test_strata_orca_rung.py owns
    that placement; this guard never loosens for containers, profiles or the
    inner config. While the orca arena is unserved the whole chain (init
    included) must stay token-free, which is C01's stricter AC6."""
    hits = S.serve_path_secret_hits(_on())
    assert not hits, f"secret chain on the strata serve path: {hits}"
    if S.ORCA_INNER_ID not in _served_arenas():
        init_blob = yaml.safe_dump(S.strata_pod(_on())["spec"].get("initContainers") or [])
        for tok in ("HF_TOKEN", "secretKeyRef", "hf-token"):
            assert tok not in init_blob, (
                f"strata init carries {tok} before C02's R-d-gated orca rung exists — "
                "C01's pack is ungated (keyless posture untouched)"
            )


@helm
def test_c01_init_env_stages_the_abliterated_set():
    """C01 AC6's other half: the arena is only real if the model-fetch init is
    told to stage it — STRATA_QUANTS must carry the `abl` iteration and
    STRATA_MODEL_ABL must name a model. Both are literal scalars: the set is
    ungated SC117 material, so the C01 keys themselves never become secret
    references (C02's download-only hf-token exception, when it lands, is
    scoped to its own rung and pinned there)."""
    docs, _raw = S.render_service_overlay()
    inits = {c.get("name"): c for c in S.strata_pod(docs)["spec"].get("initContainers") or []}
    fetch = inits.get("model-fetch")
    assert fetch, f"strata pod has no model-fetch init (inits: {sorted(inits)})"
    entries = {e.get("name"): e for e in fetch.get("env") or []}
    quants = (entries.get("STRATA_QUANTS") or {}).get("value")
    assert "abl" in str(quants or "").split(","), (
        f"STRATA_QUANTS = {quants!r} — the abl iteration never runs, so no pack lands"
    )
    abl = (entries.get("STRATA_MODEL_ABL") or {}).get("value")
    assert isinstance(abl, str) and abl.strip(), (
        f"STRATA_MODEL_ABL = {abl!r} — the init has no model to fetch (catalog-gate value missing)"
    )
    for name in ("STRATA_QUANTS", "STRATA_MODEL_ABL"):
        entry = entries.get(name)
        assert entry, f"model-fetch env lacks {name} (env: {sorted(entries)})"
        assert "valueFrom" not in entry, f"{name} sourced via valueFrom — C01 stages scalars only"


@helm
def test_c01_outer_peers_follow_the_served_wave():
    """Peers truth is the evidence wave table: whatever arenas the inner config
    serves, the OUTER peers list must equal that wave's ordered list. Green at
    every intermediate state; red the moment a peers entry is a phantom (an
    arena that does not serve) or an arena loses its route."""
    import llama_swap_testlib as L

    docs, _raw = S.render_service_overlay()
    outer = S.by_name_kind(docs, "ConfigMap", "llama-swap-config")
    cfg = S.yaml.safe_load(outer["data"]["config.yaml"])
    peers = cfg["peers"][S.PEER_NAME]["models"]
    served = set(S.inner_config(docs)["models"])
    assert peers == S.expected_strata_peers(served), (
        f"peers {peers} != the sanctioned wave for arenas {sorted(served)} — "
        f"evidence is the single source (dev edits the service values to match)"
    )
    assert len(set(peers)) == len(peers)
    assert not set(peers) & set(L.all_models_of(L.rendered_config("gpu-ai"))), (
        "a peers model is also an outer roster id — inner arenas never join the outer matrix"
    )
