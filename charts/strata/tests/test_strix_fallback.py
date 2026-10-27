# C05 contract — Strix-alone fallback profile on the strata pod
# (chunks/C05.md AC1–AC5).
#
# The fallback rides the bundled gfx1151 engine (C01) as a SECOND inner model,
# selected by ID and never co-resident with the R9700 primary: both arenas pin
# RAM, and co-loading recreates #1715's global OOM (RESEARCH §7).

from __future__ import annotations

import pytest

import llama_swap_testlib as L
import strata_testlib as S

_ok, _reason = S.env_ready()
_js_ok, _js_reason = S.jsonschema_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)
schema_gated = pytest.mark.skipif(not (_ok and _js_ok), reason=_js_reason if _ok else _reason)


def _docs():
    return S.render_strata()[0]


def _models(docs):
    return S.inner_config(docs)["models"]


def _strix_profile(docs):
    return S.profile_json(docs, S.PROFILE_STRIX_FILE)


def _primary_profile(docs):
    return S.profile_json(docs, S.PROFILE_PRIMARY_FILE)


# --- AC1: both inner models + alternation --------------------------------------


@helm
def test_c05_ac1_both_models_present():
    models = _models(_docs())
    assert {S.PRIMARY_ID, S.STRIX_ID} <= set(models), f"inner models: {sorted(models)}"
    for mid in (S.PRIMARY_ID, S.STRIX_ID):
        m = models[mid]
        assert m.get("checkEndpoint") == "/health"
        assert m.get("unloadTimeout") == 180, (
            f"{mid}: a 10s global unloadTimeout force-kills a page-locked arena "
            "(RESEARCH contradictions #4) — strix inherits the raised window"
        )


@helm
def test_c05_ac1_cmds_share_terminal_entry_per_model_profiles():
    models = _models(_docs())
    for mid, profile_file in ((S.PRIMARY_ID, S.PROFILE_PRIMARY_FILE), (S.STRIX_ID, S.PROFILE_STRIX_FILE)):
        cmd = S.norm_ws(models[mid]["cmd"])
        assert S.SERVE_ENTRY in cmd, f"{mid}: cmd must launch the C01-bundled terminal entry"
        assert f"--profile /profile/{profile_file}" in cmd, f"{mid}: wrong/missing profile: {cmd}"
        assert "ulimit -n 524288" in cmd, f"{mid}: nofile wrapper missing (PR #2399-open keeps it mandatory)"
        assert "--kv-grow" not in cmd, f"{mid}: R4 deferral applies to strix too"
    # ${PORT} without an explicit proxy key — the C02 cmd-shape contract, per model
    for mid in (S.PRIMARY_ID, S.STRIX_ID):
        assert "proxy" not in models[mid]


@helm
def test_c05_ac1_matrix_alternation_never_co_loads():
    """DECISIONS 'matrix not groups': the (p|s) set is the guard that the inner
    solver never admits both arenas — preload-empty alone would not stop a
    request-driven co-load. Checked on the DNF COMBOS, not var membership: the
    contract expression "(p | s)" mentions both arenas while the alternation
    must expand to one-model combos ([p],[s]); a combo holding both is what
    recreates #1715 (arenas are additive on a 128 GB node, RESEARCH §7)."""
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


def test_harness_matrix_expansion_matches_skill_semantics():
    """Self-check for matrix_expansions so review can trust the C05 bar:
    the llama-swap skill's documented example expands to [g,v],[q,v],[m,v],
    a bare alternation to single-model combos, and '+name' inlines the
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
def test_c05_ac1_preload_stays_empty():
    hooks = S.inner_config(_docs()).get("hooks") or {}
    preload = ((hooks.get("on_startup") or {}).get("preload")) or []
    assert preload == [], (
        "preloading two matrix alternatives swap-loads them (RESEARCH §3 warning) — "
        "the lazy Q2 posture is the contract"
    )


# --- AC2: strix profile content; primary untouched ------------------------------


@helm
def test_c05_ac2_strix_eight_set_env_verbatim():
    env = _strix_profile(_docs()).get("env") or {}
    want = dict(e.split("=", 1) for e in S.STRIX_EIGHT_SET)
    got = {k: str(v) for k, v in env.items()}
    missing = {k: v for k, v in want.items() if got.get(k) != v}
    assert not missing, f"STRIX_HALO §5 eight-set drift (spellings are upstream literals): {missing}"


@helm
def test_c05_ac2_strix_hypothesis_pair_present_and_verify_marked():
    """expert-cache 24576 / resident-budget 55 ship as VERIFY-marked
    hypotheses (no upstream source, RESEARCH §7) — the finalizer is the
    on-target --plan gate (C04), and the values comment must say so."""
    profile = _strix_profile(_docs())
    pairs = S.arg_pairs(profile)
    assert ("--expert-cache", "24576") in pairs, f"strix expert-cache pair: {pairs}"
    assert ("--resident-budget-gib", "55") in pairs, f"strix resident-budget pair: {pairs}"
    text = S.read(S.CHART_DIR / "values.yaml", "C05 task 2 writes config.engineProfileStrix")
    region = S.values_region(text, "engineProfileStrix")
    assert "VERIFY" in region, "hypothesis pair lacks its VERIFY marker"
    assert "--plan" in region, "the values comment must name the --plan gate as the finalizer (R1)"


@helm
def test_c05_ac2_strix_recipe_args_and_backend():
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
def test_c05_ac2_strix_exe_is_halo_root_from_readme():
    readme = S.read(S.CONTAINER_DIR / "README.md", "C01 froze the two-flavor exe contract")
    exe = _strix_profile(_docs())["exe"]
    assert exe in S.engine_exe_paths(readme), f"strix exe {exe!r} not a README contract path"
    assert "-hip-halo/" in exe, (
        "strix must run the gfx1151 engine root — swapping the roots loads the "
        "wrong-arch kernels against the 8060S"
    )
    assert exe != _primary_profile(_docs())["exe"], "strix and primary must not share one exe path"


@helm
def test_c05_ac2_primary_profile_unchanged():
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
def test_c05_ac3_inner_config_with_both_models_validates():
    errs = S.schema_errors(S.inner_config(_docs()))
    assert not errs, [(list(e.absolute_path), e.message) for e in errs[:8]]


@schema_gated
def test_c05_ac3_both_profiles_are_json_maps():
    for fn in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        assert isinstance(S.profile_json(_docs(), fn), dict)


# --- AC4: outer peers list + bare-ID routing precondition -----------------------


def test_c05_ac4_peers_models_contain_both_ids():
    peer = L.service_overlay("gpu-ai")["config"]["peers"][S.PEER_NAME]
    assert set(peer["models"]) >= {S.PRIMARY_ID, S.STRIX_ID}, peer["models"]


def test_c05_ac4_no_outer_shadow_of_inner_ids():
    """Bare-ID routing works only while exactly one peer serves the ID and no
    outer model/alias shadows it (RESEARCH §3, O1 resolved) — a future outer
    roster addition named *-strata would silently steal the route."""
    outer = L.rendered_config("gpu-ai")
    ids = set(L.all_models_of(outer))
    aliases = {a for m in L.all_models_of(outer).values() for a in (m.get("aliases") or [])}
    shadowed = ({S.PRIMARY_ID, S.STRIX_ID} & ids) | ({S.PRIMARY_ID, S.STRIX_ID} & aliases)
    assert not shadowed, f"outer surface shadows inner IDs: {sorted(shadowed)}"


# --- AC5: fallback runbook section ----------------------------------------------


def test_c05_ac5_readme_fallback_section_epoch_labeled():
    """History vs current-epoch citations are the AC5 bar: the 1,265/59.1 @8K
    row is engine-0.1.40-era, the bundled engine is 0.1.52 — restating the old
    numbers unlabeled is the perf-myth failure mode this ticket keeps hitting."""
    text = S.read(S.CHART_DIR / "README.md", "C05 task 4 adds the fallback runbook section")
    lowered = text.lower()
    assert "strix" in lowered and "fallback" in lowered, "no strix fallback section"
    window = lowered[lowered.index("strix"):]
    assert "0.1.40" in window, "History citation not epoch-labeled (engine-0.1.40-era)"
    assert any(tok in text for tok in ("1,265", "1265")) and "59.1" in text, "History perf row not cited"
    assert any(tok in text for tok in ("KL-gated", "KL gated")), "the 'rounds differ' caveat is part of AC5"


def test_c05_ac5_hazard_citations_present():
    text = S.read(S.CHART_DIR / "README.md", "C05 fallback runbook")
    assert "#2706" in text, "HC_UPMIX split-mode hazard history (log-check gate) must ride the runbook"
    assert "#1715" in text, "the 8060S/LPDDR5X co-residency warning cites #1715 (guide Step 5)"
    assert "8060S" in text
    assert "--plan" in text, "final numbers are the --plan gate's — the runbook must point there"
