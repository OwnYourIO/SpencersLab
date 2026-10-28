# r2-C01 Strix fallback contract — the gfx1151 second inner model on the
# consolidated strata pod (run-1 C05 semantics; the chart body lands with
# run-2 C01's relocation, so every red here names r2-C01).
#
# The fallback rides the bundled gfx1151 engine (containers/strata, untouched
# by run 2) as a SECOND inner model, selectable by ID and never co-resident
# with the R9700 primary: both arenas pin RAM, and co-loading recreates
# #1715's global OOM (run-1 RESEARCH §7).

from __future__ import annotations

import pytest

import llama_swap_testlib as L
import strata_testlib as S

_ok, _reason = S.env_ready()
_js_ok, _js_reason = S.jsonschema_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)
schema_gated = pytest.mark.skipif(not (_ok and _js_ok), reason=_js_reason if _ok else _reason)


def _docs():
    return S.render_on()[0]


def _models(docs):
    return S.inner_config(docs)["models"]


def _strix_profile(docs):
    return S.profile_json(docs, S.PROFILE_STRIX_FILE)


def _primary_profile(docs):
    return S.profile_json(docs, S.PROFILE_PRIMARY_FILE)


# --- AC1 (run-1 C05): both inner models + alternation --------------------------


@helm
def test_c01_strix_both_models_present_keyless():
    models = _models(_docs())
    assert {S.PRIMARY_ID, S.STRIX_ID} <= set(models), f"inner models: {sorted(models)}"
    for mid in (S.PRIMARY_ID, S.STRIX_ID):
        m = models[mid]
        assert m.get("checkEndpoint") == "/health"
        assert m.get("unloadTimeout") == 180, (
            f"{mid}: a 10s global unloadTimeout force-kills a page-locked arena "
            "(run-1 RESEARCH contradictions #4) — strix inherits the raised window"
        )
        assert not any("STRATA_API_KEY" in e for e in S.env_list(m)), (
            f"{mid}: STRATA_API_KEY passthrough survived in model env (C-A)"
        )


@helm
def test_c01_strix_cmds_share_terminal_entry_per_model_profiles():
    models = _models(_docs())
    for mid, profile_file in ((S.PRIMARY_ID, S.PROFILE_PRIMARY_FILE), (S.STRIX_ID, S.PROFILE_STRIX_FILE)):
        cmd = S.norm_ws(models[mid]["cmd"])
        assert S.SERVE_ENTRY in cmd, f"{mid}: cmd must launch the C01-bundled terminal entry"
        assert f"--profile /profile/{profile_file}" in cmd, f"{mid}: wrong/missing profile: {cmd}"
        assert "ulimit -n 524288" in cmd, f"{mid}: nofile wrapper missing (PR #2399-open keeps it mandatory)"
        assert "--kv-grow" not in cmd, f"{mid}: R4 deferral applies to strix too"
    for mid in (S.PRIMARY_ID, S.STRIX_ID):
        assert "proxy" not in models[mid]


@helm
def test_c01_strix_matrix_alternation_never_co_loads():
    """The (p|s) set guards that the inner solver never admits both arenas —
    preload-empty alone would not stop a request-driven co-load. Checked on
    the DNF COMBOS, not var membership: the contract expression "(p | s)"
    mentions both arenas while the alternation must expand to one-model
    combos ([p],[s]); a combo holding both recreates #1715 (arenas add up on
    the 128 GB node, run-1 RESEARCH §7)."""
    cfg = S.inner_config(_docs())
    matrix = cfg.get("matrix") or {}
    assert "groups" not in cfg, "llama-swap hard-errors when matrix and groups coexist"
    vars_ = matrix.get("vars") or {}
    assert vars_.get("p") == S.PRIMARY_ID and vars_.get("s") == S.STRIX_ID, vars_
    expansions = S.matrix_expansions(cfg)
    assert expansions, "no matrix sets rendered"
    coloc = [
        name for name, combos in expansions.items()
        if any({S.PRIMARY_ID, S.STRIX_ID} <= combo for combo in combos)
    ]
    assert not coloc, f"matrix sets whose expansion admits both arenas together: {coloc}"
    all_combos = [c for combos in expansions.values() for c in combos]
    for mid in (S.PRIMARY_ID, S.STRIX_ID):
        assert any(mid in c for c in all_combos), f"{mid} unreachable in the inner matrix"
    L.assert_matrix_closure(cfg, "strata-inner")


def test_c01_harness_matrix_expansion_matches_skill_semantics():
    """Self-check for matrix_expansions so review can trust the alternation
    bar: the llama-swap skill's documented example expands to [g,v],[q,v],
    [m,v]; a bare alternation to single-model combos; '+name' inlines the
    referenced set's combos."""
    cfg = {"matrix": {"vars": {"g": "G", "q": "Q", "m": "M", "v": "V"},
                      "sets": {"standard": "(g | q | m) & v",
                               "alone": "g | v",
                               "full": "g & v",
                               "combo": "m | +full"}}}
    exp = S.matrix_expansions(cfg)
    assert {frozenset(c) for c in exp["standard"]} == {
        frozenset({"G", "V"}), frozenset({"Q", "V"}), frozenset({"M", "V"})}
    assert {frozenset(c) for c in exp["alone"]} == {frozenset({"G"}), frozenset({"V"})}
    assert {frozenset(c) for c in exp["combo"]} == {frozenset({"M"}), frozenset({"G", "V"})}


@helm
def test_c01_strix_preload_stays_empty():
    hooks = S.inner_config(_docs()).get("hooks") or {}
    preload = ((hooks.get("on_startup") or {}).get("preload")) or []
    assert preload == [], (
        "preloading two matrix alternatives swap-loads them (run-1 RESEARCH §3 warning) — "
        "the lazy Q2 posture is the contract"
    )


# --- AC2: strix profile content; primary untouched -------------------------------


@helm
def test_c01_strix_eight_set_env_verbatim():
    env = _strix_profile(_docs()).get("env") or {}
    want = dict(e.split("=", 1) for e in S.STRIX_EIGHT_SET)
    got = {k: str(v) for k, v in env.items()}
    missing = {k: v for k, v in want.items() if got.get(k) != v}
    assert not missing, f"STRIX_HALO §5 eight-set drift (spellings are upstream literals): {missing}"


@helm
def test_c01_strix_hypothesis_pair_present_and_verify_marked():
    """expert-cache 24576 / resident-budget 55 ship as VERIFY-marked
    hypotheses (no upstream source, run-1 RESEARCH §7) — the finalizer is the
    on-target --plan gate (runbook), and the values comment must say so."""
    profile = _strix_profile(_docs())
    pairs = S.arg_pairs(profile)
    assert ("--expert-cache", "24576") in pairs, f"strix expert-cache pair: {pairs}"
    assert ("--resident-budget-gib", "55") in pairs, f"strix resident-budget pair: {pairs}"
    assert profile.get("api_key") == S.API_KEY_NONE, "strix profile lost the C-A keyless pin"
    text = S.read(S.CHART_DIR / "values.yaml", "r2-C01 relocates config.engineProfileStrix under strata:")
    region = S.values_region(text, "engineProfileStrix")
    assert "VERIFY" in region, "hypothesis pair lacks its VERIFY marker"
    assert "--plan" in region, "the values comment must name the --plan gate as the finalizer (R1)"


@helm
def test_c01_strix_recipe_args_and_backend():
    profile = _strix_profile(_docs())
    pairs = S.arg_pairs(profile)
    for flag, value in (
        ("--prefill", "16384"), ("--max-context", "262144"), ("--kv", "int8"),
        ("--spec", "4"), ("--spec-min-p", "0.5"), ("--mtp-window", "8192"),
    ):
        assert (flag, value) in pairs, f"{flag} {value} missing (STRIX_HALO history-class recipe): {pairs}"
    assert profile.get("backend") == "hip"
    toks = S.arg_tokens(profile)
    assert not any(t.startswith("--vision") for t in toks), "R2 vision-off applies to both profiles"
    assert not any(t.startswith("--prompt-cache") for t in toks)


@helm
def test_c01_strix_exe_is_halo_root_from_container_readme():
    readme = S.read(S.CONTAINER_DIR / "README.md", "the two-flavor exe contract, containers/strata (untouched)")
    exe = _strix_profile(_docs())["exe"]
    assert exe in S.engine_exe_paths(readme), f"strix exe {exe!r} not a README contract path"
    assert "-hip-halo/" in exe, (
        "strix must run the gfx1151 engine root — swapping the roots loads the "
        "wrong-arch kernels against the 8060S"
    )
    assert exe != _primary_profile(_docs())["exe"], "strix and primary must not share one exe path"


@helm
def test_c01_strix_primary_profile_unchanged():
    """Render-diff-additive rule: the strix numbers must not migrate into the
    primary, and the R2/R4 exclusions must not move."""
    profile = _primary_profile(_docs())
    pairs = S.arg_pairs(profile)
    toks = S.arg_tokens(profile)
    assert ("--expert-cache", "auto") in pairs, f"primary lost its auto seed: {pairs}"
    assert ("--expert-cache", "24576") not in pairs
    assert not any(t.startswith("--resident-budget-gib") for t in toks)
    assert not any(t.startswith("--prompt-cache") for t in toks)
    assert not any(t.startswith("--kv-grow") for t in toks)
    assert not any(t.startswith("--vision") for t in toks)
    env = profile.get("env") or {}
    for extra in ("STRATA_HC_UPMIX", "STRATA_PF_SWITCH_MIN_T", "STRATA_PREFILL_STREAM_MIN"):
        assert extra not in env, f"strix eight-set item {extra} leaked into the primary env"
    assert S.VOID_ENV_TOKEN not in env


# --- AC3: schema gates with two models ------------------------------------------


@schema_gated
def test_c01_inner_config_with_both_models_validates():
    errs = S.schema_errors(S.inner_config(_docs()))
    assert not errs, [(list(e.absolute_path), e.message) for e in errs[:8]]


@schema_gated
def test_c01_both_profiles_are_json_maps():
    for fn in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        assert isinstance(S.profile_json(_docs(), fn), dict)
