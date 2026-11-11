# r2-C01 Strix fallback contract — the gfx1151 second inner model on the
# consolidated strata pod (run-1 C05 semantics; the chart body lands with
# run-2 C01's relocation, so every red here names r2-C01).
#
# The fallback rides the bundled gfx1151 engine (containers/strata, untouched
# by run 2) as a SECOND inner model, selectable by ID and never co-resident
# with the R9700 primary: both arenas pin RAM, and co-loading recreates
# #1715's global OOM (run-1 RESEARCH §7).

from __future__ import annotations

import json
import re

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
    """The era-1 "(p | s)" set guards that the inner solver never admits both
    arenas — preload-empty alone would not stop a request-driven co-load.
    Checked on the DNF COMBOS, not var membership: the expression mentions
    both arenas while the alternation must expand to one-model combos
    ([p],[s]); a combo holding both recreates #1715 (arenas add up on the
    128 GB node, run-1 RESEARCH §7). Today's sets.main is the five-letter
    alternation — its all-arenas law is test_strata_c09_ornith_arena.py::
    test_c09_alternation_expands_five_arenas_and_ornith_only_swaps; this arm
    stays the founding p/s pair check."""
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


# --- C07 re-pin era chain (TEST_SPEC 9.16): the fixture law survived the move ----


def test_c07_strix_fixture_era_delta_is_only_the_engine_root_pair():
    """C07 AC3/U9.4 re-pinned the engine (0.1.52 -> 0.1.54) and C09 re-pinned
    it again (0.1.54 -> 0.1.55 with the 0.2.9 flavor image) — each time
    PROVENANCE routed the fixture re-pin to the test session. The
    byte-invariance law survives intact across the WHOLE chain: every
    adjacent era delta is ONLY the sanctioned step, and every era
    pins its captured root exactly, so the three preservation arms
    (abliterated/orca/q4) keep whole-file deep-equality with no exempt-key
    hole.

    cf-141 widens this law to STEP KINDS (DECISIONS round 2, "row-H is a
    law-move chunk"): the strix chain continues through the landed cf-141
    steps — C03's envelope step moves exactly {parallel}, C04's engine step
    (cf141-engine59) exactly {exe, lib_dirs}, C04's bump-config step exactly
    {drafting} — every step-set pinned in strata_testlib.CF141_ERA_STEP;
    nothing else rides any step. Un-landed steps stop the walk; the envelope
    and bump arms name the missing capture."""
    chain = [
        ("era 1 pre-cf86",
         json.loads((S.EVIDENCE_DIR / "strata-profiles-pre-cf86" / S.PROFILE_STRIX_FILE).read_text()),
         f"{S.ENGINE_ROOT}/0.1.52-linux-x86_64-hip-halo", None),
        ("era 2 c07-repin",
         json.loads((S.EVIDENCE_DIR / "strata-profiles-c07-repin" / S.PROFILE_STRIX_FILE).read_text()),
         f"{S.ENGINE_ROOT}/0.1.54-linux-x86_64-hip-halo", {"exe", "lib_dirs"}),
    ]
    if S.cf141_era_landed(S.PROFILE_STRIX_FILE, S.CF141_ERA_STRIX8):
        chain.append(("era 4 cf141-strix8",
                      json.loads((S.EVIDENCE_DIR / S.CF141_ERA_STRIX8 / S.PROFILE_STRIX_FILE).read_text()),
                      None, S.CF141_ERA_STEP[S.CF141_ERA_STRIX8]))
    if S.cf141_era_landed(S.PROFILE_STRIX_FILE, S.CF141_ERA_BUMP):
        chain.append(("era 5 cf141-bump",
                      json.loads((S.EVIDENCE_DIR / S.CF141_ERA_BUMP / S.PROFILE_STRIX_FILE).read_text()),
                      f"{S.ENGINE_ROOT}/{S.CF141_ENGINE_HALO_LABEL}",
                      S.cf141_step_for(S.PROFILE_STRIX_FILE, S.CF141_ERA_BUMP)))
    # era 3 (c09-repin) sits between era 2 and the cf-141 steps: engine-root
    # delta; read it directly so the walk order is the CHAIN order, not the
    # file order. It is also the fixture while no cf-141 strix step has
    # landed, so the map and the chain can never silently disagree.
    chain.insert(2, ("era 3 c09-repin",
                     json.loads((S.EVIDENCE_DIR / "strata-profiles-c09-repin" / S.PROFILE_STRIX_FILE).read_text()),
                     f"{S.ENGINE_ROOT}/0.1.55-linux-x86_64-hip-halo", {"exe", "lib_dirs"}))
    for name, era, root, delta_in in chain:
        if root is not None:
            assert era["exe"] == f"{root}/strata" and era["lib_dirs"] == [root], (
                f"{name} must pin its captured root {root!r} exactly — era files are "
                "append-only history; a root moved without PROVENANCE is an unsanctioned re-pin"
            )
        if delta_in is not None:
            prev = chain[chain.index((name, era, root, delta_in)) - 1]
            moved = S.era_delta(prev[1], era)
            assert moved == frozenset(delta_in), (
                f"{prev[0]}->{name}: adjacent era delta is {sorted(moved)}, the step law "
                f"pins {sorted(delta_in)} — anything else moving is an un-sanctioned re-tune "
                "riding a re-pin (engine steps {exe,lib_dirs}, envelope {parallel}, "
                "bump-config {drafting})"
            )
    assert S.profile_fixture(S.PROFILE_STRIX_FILE) == chain[-1][1], (
        "profile_fixture must resolve to the newest LANDED strix era (chain tip) — "
        "the era map and the cf-141 chain steps drifted apart"
    )
    assert not any(
        (S.EVIDENCE_DIR / d / S.PROFILE_PRIMARY_FILE).exists()
        for d in ("strata-profiles-c07-repin", "strata-profiles-c09-repin")
    ), (
        "the primary profile rides the version-free claim-compiled pack root — an "
        "engine re-pin cannot move its era; a re-pin-era primary file is a false pin"
    )


def test_primary_fixture_era_chain_is_one_owner_ruled_flag_per_step():
    """The primary's frozen era has moved twice, both times by owner ruling on
    2026-11-01 — U13/T3 (prompt chunk: bare `auto` = 16,384 on gfx12, 32,768 is
    what PR #3636 measured at ~2,519 tok/s on this node class) and U14 (the
    declared cap: 92160 never covered the rung's own 46.84 + 32 + ~13 ≈ 91.84
    GiB, so parking was refused inside its own number while the node sat idle).
    This arm is what stops either move becoming the exempt-key hole the
    engine-re-pin law above exists to prevent: every adjacent SINGLE-FLAG
    step must be args-only, membership-identical, and exactly ONE flag
    value, and cf-141's sanctioned step kinds (the row-H shape step with its
    pinned {args, env, parallel} surface and single args pair, the bump
    {drafting} step) are machine-verified against the same no-riders bar.
    An era step with an unpinned key set, a dropped flag, or a rider is red,
    and the pre-ruling eras stay append-only history."""
    base_eras = (
        ("era 1 pre-cf86", S.EVIDENCE_DIR / "strata-profiles-pre-cf86",
         {"--prefill": "auto", "--memory-limit-mib": "92160"}),
        ("era 2 U13/T3", S.EVIDENCE_DIR / "strata-profiles-t03-repin",
         {"--prefill": "auto:32768", "--memory-limit-mib": "92160"}),
        ("era 3 U14", S.EVIDENCE_DIR / "strata-profiles-u14-repin",
         {"--prefill": "auto:32768", "--memory-limit-mib": str(S.PRIMARY_MEMORY_LIMIT_MIB)}),
    )
    loaded = []
    for name, dirpath, expect in base_eras:
        era = json.loads((dirpath / S.PROFILE_PRIMARY_FILE).read_text())
        flags = dict(S.arg_pairs(era))
        assert era["env"] == {}, f"{name}: primary profile-layer env must stay empty (C-A keyless; T0 rides the model env)"
        for flag, want in expect.items():
            assert flags.get(flag) == want, f"{name}: {flag} reads {flags.get(flag)!r}, captured era says {want!r}"
        loaded.append((name, flags, era))
    for (na, a, _), (nb, b, _) in zip(loaded, loaded[1:]):
        assert set(a) == set(b), (
            f"{na}->{nb}: args membership changed ({sorted(set(b) ^ set(a))}) — an era step is a "
            "value ruling, not a flag add/remove"
        )
        diff = {k for k in a if a[k] != b[k]}
        assert len(diff) == 1, (
            f"{na}->{nb} moved {sorted(diff)}; every sanctioned single-flag era step is exactly "
            "ONE flag (U13 = --prefill, U14 = --memory-limit-mib)"
        )
        for untouched in ("--conversation-cache-mib", "--conversation-cache-slots", "--kv-resident", "--max-context"):
            assert a[untouched] == b[untouched], f"{na}->{nb}: {untouched} rode an unrelated era step"

    # cf-141 step kinds (DECISIONS round 2): the row-H SHAPE step moves the
    # pinned surface set {args, env, parallel} as ONE owner ruling (Q9+Q10) —
    # args membership stays identical and exactly the conv-cache pair moves
    # inside it; the bump-config step moves exactly {drafting}. Each is
    # machine-verifiable against the same no-riders bar as the single-flag
    # steps; unlanded steps stop the walk (the envelope/bump arms name them).
    prev_name, prev_flags, prev_era = loaded[-1]
    if S.cf141_era_landed(S.PROFILE_PRIMARY_FILE, S.CF141_ERA_ROWH):
        rowh = json.loads((S.EVIDENCE_DIR / S.CF141_ERA_ROWH / S.PROFILE_PRIMARY_FILE).read_text())
        flags = dict(S.arg_pairs(rowh))
        assert S.era_delta(prev_era, rowh) == S.cf141_step_for(S.PROFILE_PRIMARY_FILE, S.CF141_ERA_ROWH), (
            f"{prev_name}->cf141-rowh: shape-step delta {sorted(S.era_delta(prev_era, rowh))}, "
            "pinned {args, env, parallel} — nothing else rides the row-H ruling"
        )
        assert set(flags) == set(prev_flags), "row-H changed args membership, not just the ruled value"
        moved_pairs = {k for k in prev_flags if prev_flags[k] != flags.get(k)}
        assert moved_pairs == {"--conversation-cache-mib"}, (
            f"row-H moves exactly the conversation-cache pair (32768->16384), got {sorted(moved_pairs)}"
        )
        assert flags["--conversation-cache-mib"] == "16384" and flags["--conversation-cache-slots"] == "16"
        assert rowh.get("env") == S.CF141_PRIMARY_ENV_ARMED, (
            f"row-H env must be exactly {S.CF141_PRIMARY_ENV_ARMED!r} (Q10, quoted string), got {rowh.get('env')!r}"
        )
        assert rowh.get("parallel") == 8, f"row-H parallel {rowh.get('parallel')!r}, owner Q9 says 8"
        prev_name, prev_flags, prev_era = "cf141-rowh", flags, rowh
        loaded.append((prev_name, prev_flags, rowh))
    if S.cf141_era_landed(S.PROFILE_PRIMARY_FILE, S.CF141_ERA_BUMP):
        bump = json.loads((S.EVIDENCE_DIR / S.CF141_ERA_BUMP / S.PROFILE_PRIMARY_FILE).read_text())
        assert S.era_delta(prev_era, bump) == S.cf141_step_for(S.PROFILE_PRIMARY_FILE, S.CF141_ERA_BUMP), (
            f"{prev_name}->cf141-bump: delta {sorted(S.era_delta(prev_era, bump))}, the bump-config "
            "step pins {drafting} — no envelope literal may ride the bump (C04 AC4)"
        )
        assert bump.get("drafting") == S.CF141_DRAFTING_VALUE, (
            f"bump era drafting reads {bump.get('drafting')!r}, RESEARCH [79] obligation says 'mtp'"
        )
        loaded.append(("cf141-bump", dict(S.arg_pairs(bump)), bump))

    final = loaded[-1][1]
    cgroup_mib = int(str(S.STRATA_CGROUP_LIMIT).removesuffix("Gi")) * 1024
    assert int(final["--memory-limit-mib"]) <= cgroup_mib, (
        f"the captured primary cap {final['--memory-limit-mib']} MiB exceeds the {S.STRATA_CGROUP_LIMIT} "
        "cgroup — the #1601 pairing would be unshippable"
    )
    assert S.profile_fixture(S.PROFILE_PRIMARY_FILE) == loaded[-1][2], (
        "profile_fixture must resolve to the newest LANDED primary era (chain tip) — the era map "
        "and the cf-141 chain steps drifted apart"
    )


def test_c07_strix_fixture_ties_to_the_built_halo_root():
    """Anti-drift tether (the repair's strengthening half): the frozen
    fixture's exe/lib_dirs must name THE halo root the containers/strata
    Dockerfile itself COPYs and test -x-es. The fixture cannot silently
    drift back toward 0.1.52, and a future image re-pin reddens this arm
    (plus the container three-surface arm) before any render arm can go
    stale — the era chain then re-runs through the test session."""
    dockerfile = S.read(S.CONTAINER_DIR / "Dockerfile", "the C07 build's engine COPY/verify lines")
    labels = {m.group(0) for m in re.finditer(r"\d+\.\d+\.\d+-linux-x86_64-hip-halo", dockerfile)}
    assert len(labels) == 1, (
        f"the Dockerfile names {sorted(labels)} halo roots — one era builds exactly one; "
        "a mid-re-pin half-edit must not let the fixture chase whichever it reads first"
    )
    root = f"{S.ENGINE_ROOT}/{next(iter(labels))}"
    era2 = S.profile_fixture(S.PROFILE_STRIX_FILE)
    assert era2["exe"] == f"{root}/strata" and era2["lib_dirs"] == [root], (
        f"strix fixture exe/lib_dirs ({era2.get('exe')!r}, {era2.get('lib_dirs')!r}) "
        f"drifted from the build-verified halo root {root!r}"
    )


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
