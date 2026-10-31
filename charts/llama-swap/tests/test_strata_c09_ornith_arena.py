# cf-86 C09 — the ornith-on-Strata ARENA, chart side (chunks/C09.md b).
# Frozen NEW id `ornith-1.5-122b-strata-q4` on a fresh family prefix: this is
# the §9.17 by-name flip — the old ornith-`*strata*` ABSENCE arms (Shape-B
# record in test_catalog_contract.py) flip to PRESENCE here, while the
# llama.cpp ornith ladder arms elsewhere stay green and untouched (their
# retirement is a separate owner election, C09 forbidden list).
#
# Red posture: every arm here is designed-red until dev lands the arena
# (values.yaml block, engineProfileStrataOrnith subtree, configmap render,
# matrix letter n). The q36 positive-surface set is authored PARAMETERIZED per
# the chunk's dev-round gate: dev reads setup.py@v0.2.9's qwen36 entry +
# engine.hpp first and records the read; the closed-world ⊆ law below is the
# pre-dev pin of the engine.hpp surface, and any legitimate setup-generated
# addition flips through the test session, never a silent dev edit.
#
# The gfx120x-only caveat is executable: the ornith profile must ride the
# CLAIM-COMPILED engine (the migration's recompile carries the patched
# constants) — the packaged halo root is NOT patched, so an ornith profile
# pointing at components/engine would serve the broken tree on Strix and hide
# it. Strix simply omits the arena.
#
# Image-side companion + live tree arms: test_strata_c09_ornith_carry.py.
# The strix 0.1.54→0.1.55 literals pair with the containers suite's flipped
# ENGINE_VERSION (three-surface arm); the §9.16 era-2 fixture tethers redden
# at dev landing and take the era-3 capture in the C09-landing test round.

from __future__ import annotations

import re

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

# engine.hpp q36 run surface ([C6] — NOT the flash-next profile grammar;
# conversation-cache/session flags DO NOT carry over, R5 open-item #2).
Q36_SURFACE = {
    "--native", "--serve", "--max-context", "--prefill", "--chunk", "--mtp",
    "--pool-workers", "--expert-vram", "--expert-slots", "--hybrid-rows", "--cpu-threads",
}
# Chunk-pinned members: multi-shard --native (q36 load() joins shards itself),
# the 262K class, and --mtp 2 (file carries blk.48 MTP, types clean).
Q36_REQUIRED = {"--native", "--max-context", "--mtp"}
# FORBIDDEN flag classes in this profile (chunk forbidden list + AC3): the
# flash-next-only grammar. Absence is law regardless of what else dev's read
# adds to the surface.
Q36_FORBIDDEN_PREFIXES = ("--conversation-cache", "--slot-save-path", "--memory-limit-mib")


def _docs():
    return S.render_on()[0]


def _model():
    models = S.inner_config(_docs())["models"]
    assert S.ORNITH_ID in models, (
        f"inner config serves no {S.ORNITH_ID} — C09 not landed (arenas: {sorted(models)})"
    )
    return models[S.ORNITH_ID]


def _profile() -> dict:
    file = S.profile_file_of(_model())
    assert file == S.PROFILE_ORNITH_FILE, (
        f"ornith arena names {file!r}, want the frozen {S.PROFILE_ORNITH_FILE!r}"
    )
    return S.profile_json(_docs(), file)


def _args() -> dict:
    return dict(S.arg_pairs(_profile()))


# --- AC3: the arena and its residency contract --------------------------------


@helm
def test_c09_ornith_arena_served_with_the_residency_contract():
    """On the q4 pattern verbatim: ttl/unloadTimeout/checkEndpoint equality
    (rung-wide time-share law), the ulimit-wrapped serve cmd byte-mirroring
    the primary except the profile file, keyless api_key, SERVE_FLAGS closure."""
    new, primary = _model(), S.inner_config(_docs())["models"][S.PRIMARY_ID]
    for key, want in (("ttl", 3600), ("unloadTimeout", 180), ("checkEndpoint", "/health")):
        assert new.get(key) == want, f"{S.ORNITH_ID}.{key} = {new.get(key)!r}, want {want!r}"
    assert new["cmd"] == primary["cmd"].replace(
        f"--profile /profile/{S.PROFILE_PRIMARY_FILE}", f"--profile /profile/{S.PROFILE_ORNITH_FILE}"
    ), f"ornith cmd must mirror the frozen serve wrapper (the ulimit wrapper is load-bearing): {new['cmd']!r}"
    flags = set(S.cmd_flag_tokens(new["cmd"]))
    assert not flags - S.SERVE_FLAGS, f"serve flags outside the frozen set: {sorted(flags - S.SERVE_FLAGS)}"
    prof = _profile()
    assert prof.get("api_key") == S.API_KEY_NONE, (
        "ornith serve surface gained an api_key — bytes are UNGATED, no secret anywhere (C09 b)"
    )


@helm
def test_c09_arena_env_carries_the_host_allow_list_and_dense_mmq():
    """ALLOWED_HOSTS like every rung (peers-forwarded Host), and the
    STRATA_DENSE_MMQ=1 env arm per #3926 (+47–67 % prompts on the q36 HIP
    path) — the chunk declares it, so its absence is drift."""
    env = [str(e) for e in _model().get("env") or []]
    allow = [e for e in env if e.startswith("STRATA_ALLOWED_HOSTS=")]
    assert allow and "gpu-ai-llama-swap-strata" in allow[0], (
        f"ornith arena env lacks the peers-forwarded allow list: {env}"
    )
    assert any(re.search(r"STRATA_DENSE_MMQ=1\b", e) for e in env), (
        f"no STRATA_DENSE_MMQ=1 arm (#3926) in {env}"
    )


@helm
def test_c09_inner_alias_is_unique_and_names_no_outer_id():
    """Anti-split law parameterized (the chunk freezes the ARENA id, not the
    alias): the ornith profile must claim ≥1 route alias, every claimed alias
    resolves to exactly one arena, and no alias may equal any model id on the
    inner or the served ladder — two routable surfaces, one name, is the
    frozen-id rule's death case."""
    cfg = S.inner_config(_docs())
    model = _model()

    def claimed(surface) -> list:
        val = surface.get("aliases")
        return [val] if isinstance(val, str) else list(val or [])

    orn = claimed(model) + claimed(_profile())
    assert orn, f"the ornith arena claims no alias (aliases seen: " \
        f"{sorted({a for m in cfg['models'].values() for a in claimed(m)})})"
    holders = {}
    for mid, m in cfg["models"].items():
        prof = S.profile_file_of(m)
        keys = claimed(m) + (claimed(S.profile_json(_docs(), prof)) if prof else [])
        for a in set(keys):
            holders.setdefault(a, []).append(mid)
    for alias in orn:
        assert len(holders.get(alias, [])) == 1, (
            f"alias {alias!r} resolves to {holders.get(alias)} — one key, one arena"
        )
        served_ids = set(cfg["models"])
        assert alias not in served_ids, f"alias {alias!r} shadows a model id (route-key collision)"


# --- matrix: fresh letter n, grown alternation, five-way swap law --------------


@helm
def test_c09_matrix_gains_letter_n_never_the_retired_c():
    """Letter n joins the alternation — and its vars key must be QUOTED.
    Helm's YAML 1.1 parser resolves a bare `n:` to the boolean False, so the
    live ConfigMap would carry vars {"false": …} and sets.main "(… | n)" would
    fail to resolve at runtime; only "n" survives the round-trip (probe-proven
    §9.19: unquoted injection renders vars key 'false')."""
    text = S.read(S.CHART_DIR / "values.yaml", "C09 grows the strata matrix")
    assert re.search(r'^\s*main:\s*"\(p \| s \| o \| q \| n\)"', text, re.M), (
        f"sets.main is not the C09 five-arm alternation; today's line: "
        f"{[ln.strip() for ln in text.splitlines() if ln.strip().startswith('main:')]}"
    )
    assert 'main: "(p | s | c' not in text and "(c |" not in text, (
        "the C08-retired letter c is back in an alternation — frozen-table hygiene takes a fresh letter"
    )
    assert not re.search(r'^\s*n:\s', text, re.M), (
        'the vars letter is written bare `n:` — helm resolves it to boolean False '
        '(YAML 1.1) and the set token n never resolves; the key must be quoted "n":'
    )
    assert re.search(r"""^\s*["']n["']\s*:\s*["']?""" + re.escape(S.ORNITH_ID), text, re.M), (
        'no quoted "n": <ornith id> entry in the strata matrix vars'
    )
    vars_ = (S.inner_config(_docs()).get("matrix") or {}).get("vars") or {}
    assert vars_.get("n") == S.ORNITH_ID, (
        f"matrix.vars.n = {vars_.get('n')!r}; rendered keys: {sorted(map(str, vars_))}"
    )


@helm
def test_c09_alternation_expands_five_arenas_and_ornith_only_swaps():
    """§9.10 combo law re-pinned for the five-letter table (the growth
    precedent rides the strata tables here, not the outer CF86 ones): every
    combo holds ≤1 arena, all five stay reachable, nothing preloads — and
    specifically ornith never co-loads with q4, the two biggest pinned
    arenas on the node (ornith ~40–48 GiB class + q4 71.7 GiB > the 128 GB
    physics twice over)."""
    cfg = S.inner_config(_docs())
    arenas = set(S.INNER_MATRIX_VARS.values())
    combos = S.matrix_expansions(cfg).get("main", [])
    for combo in combos:
        clash = combo & arenas
        assert len(clash) <= 1, (
            f"matrix combo co-loads arenas {sorted(clash)} — ornith×q4 or any pair recreates #1715's node OOM"
        )
    assert not any({S.ORNITH_ID, S.Q4_ID} <= c for c in combos), (
        "an ornith+q4 co-residency combo exists — the two largest arenas must stay alternates"
    )
    reachable = {next(iter(c & arenas)) for c in combos if c & arenas}
    assert reachable == arenas, f"arenas reachable in sets.main: {sorted(reachable)}, want all {len(arenas)}"
    served = set(cfg["models"])
    assert S.ORNITH_ID in served
    assert S.profile_files(_docs()) == S.expected_profile_files(served), (
        "profile ConfigMap key set diverges from the served arenas (the +strata-ornith-q4.json render line)"
    )


# --- engineProfileStrataOrnith: q36 surface positives, flash-next negatives ---


@helm
def test_c09_ornith_profile_args_stay_on_the_q36_surface():
    """Closed-world ⊆ law + chunk-pinned members. Dev's setup.py@v0.2.9 +
    engine.hpp read (recorded in commands_run) is the authority for the exact
    surface; a legitimate generated-config addition re-pins THIS set through
    the test session — an unlisted flag here is an unproven flag."""
    args = _args()
    seen = set(args)
    extra = seen - Q36_SURFACE
    assert not extra, f"ornith profile carries flags outside the q36 surface: {sorted(extra)}"
    missing = Q36_REQUIRED - seen
    assert not missing, f"chunk-pinned q36 members missing: {sorted(missing)}"
    assert args.get("--max-context") == "262144", f"--max-context {args.get('--max-context')!r}, want the 262K class"
    assert args.get("--mtp") == "2", f"--mtp {args.get('--mtp')!r}, want 2 (blk.48 MTP, types clean)"


@helm
def test_c09_ornith_profile_carries_no_flash_next_only_flags():
    """conversation-cache/session/memory-limit flags DO NOT exist on the q36
    surface (R5 open-item #2) — smuggling them in would look like envelope
    discipline while being a flag the engine cannot parse."""
    seen = set(_args())
    smuggled = [f for f in seen if f.startswith(Q36_FORBIDDEN_PREFIXES)]
    assert not smuggled, f"flash-next-only flags in the ornith profile: {sorted(smuggled)}"


@helm
def test_c09_native_points_the_three_shard_family_under_original_names():
    """Multi-shard --native: q36's load() joins shards itself, so the pointer
    is either the shard-1 path (original repo name) or the family dir — and
    either way it lives under the Strata-data claim root where the driver
    staged it. A pointer naming a pack path is the forbidden pack-shape."""
    native = _args().get("--native") or ""
    assert native.startswith("/models/strata/Strata-data/"), (
        f"--native {native!r} outside Strata-data — the GGUF-direct set stages under the claim root"
    )
    assert "packs/" not in native, f"--native {native!r} points at a pack — q36 is GGUF-direct, no pack exists"
    if native.endswith(".gguf"):
        assert "00001-of-00003" in native, (
            f"--native names {native!r} — the 3-shard family's join entry is shard 1 of 3, original name"
        )


@helm
def test_c09_model_name_is_honest_about_the_rung():
    """§9.17 honesty law (profile-internal model_name, not the frozen arena
    id): it must read as ornith on a q4-class Strata rung — never borrowing
    the flash-next family name it is not, and never claiming a higher quant
    than the served UD-Q4_K_XL."""
    prof = _profile()
    name = str(prof.get("model_name") or "")
    assert "ornith" in name.lower(), f"model_name {name!r} does not name the model it serves"
    assert "flash" not in name.lower(), f"model_name {name!r} borrows the flash-next family"
    assert "q4" in name.lower(), f"model_name {name!r} hides the quant class"


@helm
def test_c09_ornith_rides_the_claim_compiled_engine_not_the_packaged_halo_root():
    """The gfx120x-only law, executable: the patch lands ONLY in the claim-
    compiled engine (the migration recompile); the prebuilt packaged roots
    (components/engine/*) are UNPATCHED, so an ornith profile pointing at one
    would boot the exact tree that refuses the model. Strix omits the arena
    outright — and must keep omitting it: no packaged-engine profile may name
    the ornith profile file."""
    prof = _profile()
    assert prof.get("exe") == "/models/strata/Strata/engine/strata", (
        f"ornith exe {prof.get('exe')!r} — only the claim-compiled engine carries the patched constants"
    )
    blob = S.yaml.safe_dump(prof)
    assert "components/engine" not in blob, "the ornith profile references a packaged engine root (unpatched)"


@helm
def test_c09_configmap_renders_the_ornith_profile_key():
    """The +1 render line, asserted on the outcome: the strata-profile
    ConfigMap carries the frozen file name (the by-name presence twin of the
    catalog flip in test_catalog_contract.py)."""
    files = S.profile_files(_docs())
    assert S.PROFILE_ORNITH_FILE in files, (
        f"{S.PROFILE_ORNITH_FILE} missing from the profile ConfigMap: {sorted(files)}"
    )
