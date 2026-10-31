# cf-86 C08 (revision round 2, owner U9.1/U9.2/U9.3) — rung shifts, authored
# NOW but red BY DESIGN until C08 lands (chunks/C08.md: "sweep arms red
# pre-dev, they assert the post-state"). Two sub-waves inside the file:
#
# - SC117 removal sweep (U9.3): the arena id must vanish from every live
#   surface — render, matrix, profile ConfigMap, service env/peers, catalog,
#   image files, and the C01 test file itself (retired to these absence arms).
# - orca IQ3_XXS -> IQ4_XS REPLACE (U9.2): frozen id, no matrix growth; the
#   pack/byte pins move to the three IQ4_XS shards below, the profile moves to
#   conv-cache 8192 to fit the 92160-declared cap (R4 [B4] math; the cgroup
#   does NOT move — #1601 is declared<=cgroup, not equal).
#
# The IQ4_XS byte table is a LIVE pin, read 2026-10-31 with no credential
# (anonymous tree metadata; the BYTES stay token-gated — re-proved by the live
# arm). Σ equals the chunk's 97,473,155,200 exactly, so the chunk text and the
# tree agree — no render-truth delta to flag. The publisher keeps the old
# IQ3_XXS family on the tree; OUR pins move, upstream does not, so nothing
# here asserts upstream absence.
#
# Wave guards (green now, green at C07, red if a wave half-moves early) pin
# the C07-era state of the test-side tables; the C08-era arms pin what the
# test-session flips at C08 landing (TEST_SPEC 9.15 flip list). Outer frozen
# tables (CATALOG/GPUAI_LOCAL/GPU_ECHO) are pinned as sweep-INVARIANT —
# measured live: the SC117 id never joined them (inner arenas never join the
# outer matrix), so the chunk's "-1 / 34->33 / 26->25" line recomputes to
# ZERO movement there (TEST_SPEC 9.15).

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)
hf_live = pytest.mark.skipif(
    __import__("os").environ.get("RUN_HF_CHECK") != "1",
    reason="evidence gate: RUN_HF_CHECK=1 re-reads the orcarouter tree the IQ4_XS pins come from",
)

HF_REPO_ORCA = "orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF"
IQ4_STEM = "Qwen3.8-Flash-Next-Uncensored-IQ4_XS"

# LIVE PIN (anonymous HF tree API, 2026-10-31): flat-root paths, per-shard
# bytes; the MTP sibling family is deliberately NOT staged (the rung stages
# experts only, as in C02). Σ = 97,473,155,200 == the chunk/RESEARCH [B7] total.
IQ4_SHARD_BYTES = {
    f"{IQ4_STEM}-00001-of-00003.gguf": 44766155936,
    f"{IQ4_STEM}-00002-of-00003.gguf": 44735995008,
    f"{IQ4_STEM}-00003-of-00003.gguf": 7971004256,
}
IQ4_PACK_TOTAL = sum(IQ4_SHARD_BYTES.values())

PROFILE_ORCA_C08_FILE = "strata-orca-iq4_xs.json"
C08_PEERS_ORDER = [S.PRIMARY_ID, S.STRIX_ID, S.ORCA_INNER_ID, S.Q4_ID]

RETIRED_C01_TEST = S.TESTS_DIR / "test_strata_abliterated_rung.py"


def _on():
    return S.render_on()[0]


def _service():
    return S.render_service_overlay()[0]


# --- SC117 sweep: the post-state, everywhere (red until C08) --------------------


@helm
def test_c08_sc117_arena_gone_from_the_inner_config_and_matrix():
    cfg = S.inner_config(_on())
    assert S.ABL_ID not in cfg["models"], (
        f"{S.ABL_ID} still served — U9.3 removal not landed"
    )
    vars_ = (cfg.get("matrix") or {}).get("vars") or {}
    assert "c" not in vars_, f"matrix.vars.c survives: {vars_.get('c')!r}"
    arenas = {S.PRIMARY_ID, S.STRIX_ID, S.ORCA_INNER_ID, S.Q4_ID}
    combos = S.matrix_expansions(cfg).get("main", [])
    reachable = {next(iter(c & arenas)) for c in combos if c & arenas}
    assert reachable == arenas, f"sets.main arenas {sorted(reachable)}, want exactly p|s|o|q"
    for combo in combos:
        assert len(combo & arenas) <= 1, f"combo co-loads arenas {sorted(combo & arenas)}"


@helm
def test_c08_sets_main_expression_is_the_shrunk_alternation_literal():
    """The chart data line is chunk-frozen: "(p | s | o | q)" — literal pin so
    a silently reordered or c-keeping edit reds without matrix-solver masking."""
    text = S.read(S.CHART_DIR / "values.yaml", "C08 edits sets.main in the strata matrix")
    assert re.search(r'^\s*main:\s*"\(p \| s \| o \| q\)"', text, re.M), (
        "sets.main is not the C08 four-arm alternation; today's line: "
        f"{[ln.strip() for ln in text.splitlines() if ln.strip().startswith('main:')]}"
    )
    assert 'main: "(p | s | c | o | q)"' not in text, "the c-arm is still in the alternation"


@helm
def test_c08_abliterated_profile_gone_from_the_render_and_template_data():
    files = S.profile_files(_on())
    assert S.PROFILE_ABL_FILE not in files, f"profile ConfigMap still carries {S.PROFILE_ABL_FILE}: {sorted(files)}"
    tmpl = S.read(S.STRATA_TEMPLATES_DIR / "configmap-strata-profile.yaml",
                  "the strip machinery is data-driven; the deletion is data-side")
    assert "abliterated" not in tmpl, "the profile template names abliterated outside the data it renders from"


@helm
def test_c08_service_env_and_peers_shrink_to_the_three_token_state():
    inits = {c.get("name"): c for c in S.strata_pod(_service())["spec"].get("initContainers") or []}
    env = {e.get("name"): e for e in (inits["model-fetch"].get("env") or []) if isinstance(e, dict)}
    assert (env.get("STRATA_QUANTS") or {}).get("value") == "q3,orca,q4", env.get("STRATA_QUANTS")
    assert "STRATA_MODEL_ABL" not in env, "STRATA_MODEL_ABL survives the sweep"
    assert (env.get("STRATA_MODEL_ORCA") or {}).get("value") == "orca/IQ4_XS", env.get("STRATA_MODEL_ORCA")
    outer = S.by_name_kind(_service(), "ConfigMap", "llama-swap-config")
    peers = S.yaml.safe_load(outer["data"]["config.yaml"])["peers"][S.PEER_NAME]["models"]
    assert peers == C08_PEERS_ORDER, f"peers {peers}, want the C08 four-id wave (== the flipped evidence)"


@helm
def test_c08_abliterated_id_absent_from_every_live_surface():
    """The chunk's absence law, executable: zero hits repo-wide over live code
    surfaces (plan folders and this suite are the allowed history homes). Red
    per file today: values.yaml arena block, profile template data, service
    env/peers/comments, the catalog entry, the image script."""
    hits = S.live_code_grep("strata-abliterated")
    assert not hits, f"strata-abliterated survives in: {hits}"
    assert not S.live_code_grep("abliterated-iq3_xxs"), "the retired profile-file name survives"


@helm
def test_c08_catalog_drops_the_abliterated_entry_and_flips_the_orca_name():
    raw = S.read(S.REPO_ROOT / ".opencode" / "opencode.jsonc", "C08 deletes one entry, flips one name")
    stripped = re.sub(r"^\s*//.*$", "", raw, flags=re.M)
    models = ((json.loads(stripped).get("providers") or {}).get("gpu-ai") or {}).get("models") or {}
    assert S.ABL_ID not in models, "the catalog still routes the removed arena"
    orca = models.get(S.ORCA_INNER_ID)
    assert orca is not None, "the frozen orca id must SURVIVE (REPLACE shape — no id churn)"
    assert orca.get("modelID") == S.ORCA_INNER_ID, "modelID drifted — frozen-id law"
    assert "IQ4_XS" in str(orca.get("name", "")), f"orca catalog name not flipped: {orca.get('name')!r}"


# --- orca IQ4_XS: profile render post-state (red until C08) ---------------------


@helm
def test_c08_orca_profile_key_and_cmd_flip_to_the_iq4_xs_file():
    docs = _on()
    files = S.profile_files(docs)
    assert PROFILE_ORCA_C08_FILE in files, f"profile set lacks {PROFILE_ORCA_C08_FILE}: {sorted(files)}"
    model = S.inner_config(docs)["models"][S.ORCA_INNER_ID]
    assert f"/profile/{PROFILE_ORCA_C08_FILE}" in model["cmd"], model["cmd"]
    prof = S.profile_json(docs, PROFILE_ORCA_C08_FILE)
    assert prof.get("model_name") == "qwen3.8-flash-next-orca-iq4_xs", prof.get("model_name")


@helm
def test_c08_orca_args_are_the_iq4_xs_pack_shape():
    prof = S.profile_json(_on(), PROFILE_ORCA_C08_FILE)
    args = dict(S.arg_pairs(prof))
    assert args.get("--pack") == "/models/strata/Strata-data/packs/orca-iq4_xs", args.get("--pack")
    shard1 = "/models/strata/Strata-data/models/IQ4_XS-orca/" + IQ4_STEM + "-00001-of-00003.gguf"
    assert args.get("--native") == shard1, f"--native {args.get('--native')!r}"
    assert args.get("--ple-gguf") == shard1, (
        f"--ple-gguf {args.get('--ple-gguf')!r} — PLE-in-shard-1 carried from ORCA.md's pattern; "
        "the 3-shard placement is the on-target --plan gate, not a dev guess"
    )
    assert prof.get("tokenizer") == "/models/strata/Strata-data/packs/orca-iq4_xs/tokenizer"


@helm
def test_c08_orca_envelope_fits_the_92160_cap_ONLY_with_the_conv_trim():
    """R4 [B4] + the U8 conv-8 precedent: 57.7 arena + 8 conv + 13 KV-worst +
    6 supervisor ≈ 84.7 GiB inside 92160; conv 32 would need 108.7 — over even
    the 100Gi cgroup. So the trim (32768 -> 8192) is arithmetic, not tuning,
    and the cap/slots/cgroup must NOT move (U9.2 zero-envelope-growth law)."""
    prof = S.profile_json(_on(), PROFILE_ORCA_C08_FILE)
    args = dict(S.arg_pairs(prof))
    assert args.get("--conversation-cache-mib") == "8192", args.get("--conversation-cache-mib")
    assert "--conversation-cache-mib 32768" not in " ".join(S.arg_tokens(prof)), (
        "the pre-shift conv 32 survived on orca — 108.7 GiB over a 100Gi cgroup"
    )
    assert args.get("--conversation-cache-slots") == "16"
    assert args.get("--memory-limit-mib") == "92160", (
        "orca rides the 92160 declared cap — the 100Gi cgroup raise was the Q4 lockstep"
    )
    ctr = S.strata_container(_on())
    assert ctr["resources"]["limits"]["memory"] == S.Q4_CGROUP_LIMIT, "cgroup must not move for orca"


@helm
def test_c08_the_other_three_profiles_stay_byte_unchanged_under_the_shift():
    """C08 touches ONLY the orca profile among the run-configs; q4's FINAL
    pins especially (95232 / 8192 / slot-save-path) must be unmoved."""
    docs = _on()
    q4 = dict(S.arg_pairs(S.profile_json(docs, S.PROFILE_Q4_FILE)))
    assert q4.get("--memory-limit-mib") == str(S.Q4_MEMORY_LIMIT_MIB)
    assert q4.get("--conversation-cache-mib") == str(S.Q4_CONV_CACHE_MIB)
    assert q4.get("--slot-save-path") == S.Q4_SLOT_SAVE_PATH
    primary = S.profile_json(docs, S.PROFILE_PRIMARY_FILE)
    assert dict(S.arg_pairs(primary)).get("--conversation-cache-mib") == "32768", (
        "the primary's conv 32 is its own envelope — the orca trim must not propagate"
    )


# --- orca IQ4_XS: image-side post-state (existence guards make these
#     red-until-C07 then content-red-until-C08, never vacuously green) ----------


def _fetch_sh_or_c08() -> str:
    assert S.FETCH_SH.is_file(), (
        "containers/strata/files/fetch_models.sh missing — C07 must land first "
        "(R4 ordering law); C08 edits are file edits, not values.yaml script surgery"
    )
    return S.FETCH_SH.read_text()


@helm
def test_c08_image_files_lose_every_abliterated_leg():
    body = S.body_lines(_fetch_sh_or_c08())
    offenders = [ln.strip() for _, ln in body if re.search(r"abliterated|SC117|abl_pack|abl_dl", ln)]
    assert not offenders, f"abliterated plumbing survives the C08 sweep: {offenders[:4]}"
    assert re.search(r'\[ "\$FAM" = orca \]', _fetch_sh_or_c08()), (
        "orca pseudo-family routing must SURVIVE — it is the single ablated arena"
    )


@helm
def test_c08_byte_pins_env_carries_the_three_iq4_xs_literals_and_sum():
    assert S.BYTE_PINS_ENV.is_file(), "byte_pins.env missing — C07 gate (see the driver arms)"
    pins = S.BYTE_PINS_ENV.read_text()
    assert not re.search(r"47342144896|28800138432", pins), "SC117 byte literals survived"
    assert not re.search(r"44637691008|40564977024", pins), "the IQ3_XXS-era orca pair survived"
    for size in IQ4_SHARD_BYTES.values():
        assert re.search(rf"^[A-Z][A-Z0-9_]*={size}$", pins, re.M), (
            f"byte_pins.env has no NAME={size} — the LIVE-pinned IQ4_XS shard byte (2026-10-31 read) "
            "must be a sourced literal, dev copies it verbatim"
        )
    assert "97473155200" in pins, "the Σ total comment must ride with the three literals (R4 [B7])"
    extra = set(re.findall(r"^[A-Z][A-Z0-9_]*=(\d{8,})$", pins, re.M))
    assert extra == {str(s) for s in IQ4_SHARD_BYTES.values()}, (
        f"C08-era byte_pins literals {sorted(extra)} != the pinned IQ4_XS trio"
    )


@helm
def test_c08_orca_pack_stages_the_three_shard_iq4_xs_family():
    script = _fetch_sh_or_c08()
    staged = S.staged_paths(script, "orca_pack", "IQ4_XS")
    assert staged["dir"] == "/models/strata/Strata-data/models/IQ4_XS-orca"
    assert staged["pack"] == "/models/strata/Strata-data/packs/orca-iq4_xs"
    assert staged["stem"] == IQ4_STEM
    for i in (1, 2, 3):
        want = f"-0000{i}-of-00003.gguf"
        assert staged[f"s{i}"].endswith(want), f"orca s{i} = {staged[f's{i}']!r}, want a 3-of-3 shard"
    legs = re.findall(
        r'\borca_dl\s+"https://huggingface\.co/orcarouter/[^"]*-0000([123])-of-00003[^"]*"'
        r'\s+"\$\{?(\w+)\}?"\s+(?:\"?\$\{?[A-Z][A-Z0-9_]*\}?\"?|\d{8,})',
        script,
    )
    assert sorted(legs) == [("1", "s1"), ("2", "s2"), ("3", "s3")], (
        f"orca_dl legs {legs} — the three-shard staging needs exactly three legs, "
        "shard 1/2/3 into $s1/$s2/$s3, each with a want-bytes leg"
    )


@helm
def test_c08_c01_test_file_is_retired_and_its_laws_have_surviving_homes():
    """The retirement is real only with a receipt: the C01 file leaves the tree
    (its arena-side laws die WITH the arena; its preservation and keyless laws
    live on in other files — homes listed in TEST_SPEC 9.15)."""
    assert not RETIRED_C01_TEST.exists(), (
        f"{RETIRED_C01_TEST.name} still collected — C08 retires it to this file's absence arms"
    )


# --- wave guards: the C08 landing consumed the C07-era table guard -----------
# test_wave_c07_era_tables_still_carry_the_five_id_state guarded the pre-state
# (tables must NOT move before C08 dev lands). C08 landed and the flip commit
# moved the tables atomically — the guard's job is done; test_c08_catalog_wave_
# tables_shrink_with_the_sweep below is its post-state successor, and
# test_wave_outer_frozen_tables_are_sweep_invariant keeps guarding the outer
# tables (TEST_SPEC 9.15 retirement ledger / 9.17 flip ledger).


def test_wave_outer_frozen_tables_are_sweep_invariant():
    """Measured live 2026-10-31: no Strata inner id appears in CATALOG_IDS /
    GPUAI_LOCAL_IDS / GPU_ECHO_IDS (inner arenas never join the outer matrix),
    so the SC117 sweep moves NONE of them. Lengths pinned exactly —
    the chunk's '-1' line recomputes to zero here (TEST_SPEC 9.15)."""
    import llama_swap_testlib as L

    for name, length in (("CATALOG_IDS", 60), ("GPUAI_LOCAL_IDS", 15),
                         ("GPU_ECHO_IDS", 26), ("GPUAI_LOCAL_CATALOG_IDS", 22)):
        table = getattr(L, name)
        assert len(table) == length, f"{name} length {len(table)} != the measured {length}"
        assert not any(S.ABL_ID in i for i in table), f"{name} carries the inner id — the sweep cannot touch it"


# --- C08-era table flip targets (red until the C08 landing flip) ----------------


def test_c08_catalog_wave_tables_shrink_with_the_sweep():
    """The test-session's own C08 flip, pinned as an expectation: at C08 landing
    CF86_NEW_CATALOG_IDS 5->4, CF86_TRIO_IDS 3->2, INNER_MATRIX_VARS/
    INNER_PROFILE_FILES drop c, PROFILE_ORCA_FILE becomes the iq4_xs name —
    one atomic mechanical edit by the test side at C08 dev landing."""
    import test_catalog_contract as C

    assert S.ABL_ID not in C.CF86_NEW_CATALOG_IDS, "CF86_NEW_CATALOG_IDS still five (flip at C08 landing)"
    assert C.CF86_TRIO_IDS == [S.ORCA_INNER_ID, S.Q4_ID], f"trio {C.CF86_TRIO_IDS}, want 2"
    assert "c" not in S.INNER_MATRIX_VARS, "INNER_MATRIX_VARS still has c"
    assert S.PROFILE_ORCA_FILE == PROFILE_ORCA_C08_FILE, "the frozen profile-file name flip is pending"


# --- live arm: the tree the C08 pins came from (RUN_HF_CHECK class) ------------


@hf_live
def test_c08_iq4_xs_pin_table_matches_the_live_orcarouter_tree():
    """Anonymous tree read (metadata public, bytes gated — the same posture
    AC3's token rests on). The flat root resolves as resolve/main/<shard>, so
    the chunk's 'flat vs per-quant dir' question is resolved HERE, in the test
    round, not guessed by dev. The MTP sibling family stays unstaged."""
    with urllib.request.urlopen(
        f"https://huggingface.co/api/models/{HF_REPO_ORCA}/tree/main", timeout=60
    ) as resp:
        entries = json.loads(resp.read())
    sizes = {
        e["path"]: e.get("size") or (e.get("lfs") or {}).get("size")
        for e in entries
        if e["path"].endswith(".gguf") and "-IQ4_XS-" in e["path"] and "-MTP-" not in e["path"]
    }
    assert sizes == IQ4_SHARD_BYTES, f"live tree {sizes} != the pinned {IQ4_SHARD_BYTES} — re-pin, render truth"
    assert sum(sizes.values()) == IQ4_PACK_TOTAL == 97_473_155_200

    try:
        urllib.request.urlopen(
            f"https://huggingface.co/{HF_REPO_ORCA}/resolve/main/{IQ4_STEM}-00001-of-00003.gguf", timeout=30
        )
        gated = False
    except urllib.error.HTTPError as err:
        gated = err.code in (401, 403)
    assert gated, (
        "IQ4_XS shard bytes served anonymously — the gated premise behind the "
        "orcarouter token (R-d) needs re-ruling before C08 ships"
    )
