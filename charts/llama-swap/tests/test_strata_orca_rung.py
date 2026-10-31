# cf-86 C02 — the gated orcarouter Uncensored IQ3_XXS Strata rung (plan
# 2026/2026-10-cf-86-feat-more-strata-models, chunks/C02.md AC1-AC7).
#
# Red posture: the arena/profile/matrix/token-placement needles are RED pre-dev
# (C02 has not landed); the keyless SERVE-path guard, the pre-cf-86 profile
# preservation and the peers-wave law are green today and stay green.
#
# Token law is the interesting part of this file. The C-A keyless ruling stays
# absolute for the SERVE path (containers, inner supervisor config, run-config
# profiles). The research item R-d ruling sanctions the EXISTING hf-token
# Secret as a DOWNLOAD-ONLY consumer on the strata model-fetch init — that is
# what AC3 pins here, and it is why C01's chain-wide token ban is expressed as
# "no token before the orca arena exists" (test_strata_abliterated_rung.py),
# not as a permanent one. A dev choice to serve orca without the init token
# (e.g. a pre-staged pack) is NOT a license to edit this file: it is a
# NEEDS_INFO route back to the test session.

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request

import pytest
import yaml

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)
hf_live = pytest.mark.skipif(
    os.environ.get("RUN_HF_CHECK") != "1",
    reason="evidence gate: RUN_HF_CHECK=1 re-reads the two HF trees the pack pins come from",
)

ORCA_INNER_ALIAS = "qwen3.8-flash-next-orca"
OUTER_ORCA_ID = "qwen3.8-flash-next-orca-q6"
PACK_MARKER = S.ORCA_PACK_MARKER

# Byte sizes of every object the pack step stages are the contract the downloader
# compares against, so they are pinned from the HF tree API, not from ORCA.md's
# rounded GB figures. Provenance, read 2026-10-30 with no credential anywhere in
# the request:
#   GET /api/models/SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF/tree/main/IQ3_XXS
#     -> 200: 47342144896 + 28800138432
#   GET /api/models/orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF/tree/main
#     -> 200: …-IQ3_XXS-00001-of-00002.gguf 44637691008, …-00002-of-00002.gguf
#        40564977024 (sum 85202668032 = the 85.20 GB RESEARCH [S23] measures)
# The tree METADATA is public for both repos; the BYTES are not always:
#   GET …/orcarouter/…/resolve/main/<IQ3_XXS shard> anonymous -> 401 + Bearer
#     challenge (repo `gated: "auto"`), which is what makes AC3's init token
#     load-bearing rather than decorative; the same request on SC117 answers 206
#     with a Range header, which is what keeps C01's path keyless.
HF_REPO_ABL = "SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF"
HF_REPO_ORCA = "orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF"
ABL_SHARD_BYTES = (47342144896, 28800138432)
ORCA_SHARD_BYTES = (44637691008, 40564977024)

# The pinned strata image carries no shell HTTP client (C01 review finding 1,
# major: upstream docker/Dockerfile@v0.2.7 apt lists + this repo's verify step
# pin only git/c++), so a download that names one of these breaks the
# model-fetch init, and the strata Deployment's Recreate strategy takes the
# serving arenas down with it.
_HTTP_CLIENT = re.compile(r"\b(curl|wget|aria2c|axel)\b")


def _docs():
    return S.render_on()[0]


def _service_docs():
    return S.render_service_overlay()[0]


def _model(model_id: str) -> dict:
    models = S.inner_config(_docs())["models"]
    assert model_id in models, (
        f"inner config serves no {model_id} — C02 not landed (arenas: {sorted(models)})"
    )
    return models[model_id]


def _profile() -> dict:
    file = S.profile_file_of(_model(S.ORCA_INNER_ID))
    assert file == S.PROFILE_ORCA_FILE, (
        f"orca arena names {file!r}, want the frozen {S.PROFILE_ORCA_FILE!r}"
    )
    return S.profile_json(_docs(), file)


def _init_container(docs) -> dict:
    inits = S.strata_pod(docs)["spec"].get("initContainers") or []
    hits = [c for c in inits if c.get("name") == "model-fetch"]
    assert hits, f"strata pod has no model-fetch init: {[c.get('name') for c in inits]}"
    return hits[0]


def _init_script(docs) -> str:
    """C07 re-anchor (chunks/C07.md): the pack/download bodies now live in the
    image source — this suite's script-text laws follow the code, the render
    only keeps env/mounts. Red until the C07 port lands the file; the wave
    replacements (IQ4_XS tier, SC117 deletion) live in
    test_strata_c08_rung_shifts.py."""
    return S.read(S.FETCH_SH, "cf-86 C07 lift — the pack bodies live in the baked driver now")


def _body_lines(docs) -> list:
    """Numbered lines that can execute. The staging rationale comments NAME curl
    to forbid it, so an invocation law runs over non-comment lines only — the
    same scoping the C01 review used when it counted zero invocations.
    C07 re-anchor: the driver and its sourced pins file are read as ONE program
    (byte_pins.env is a source-time inclusion, so a law that used to see a
    literal on the leg line sees it in the pins now)."""
    text = _init_script(docs) + "\n" + S.read(S.BYTE_PINS_ENV, "the driver sources its byte literals (C07)")
    return [(n, ln) for n, ln in enumerate(text.splitlines()) if not ln.strip().startswith("#")]


def _downloader_text() -> str:
    """The other half of the lifted pair: hf_fetch.py, where the urllib client
    and the redirect-trust law live after C07."""
    return S.read(S.HF_FETCH_PY, "cf-86 C07 lift — the downloaders are a baked file, not a heredoc")


def _pins_size(body, size: int) -> bool:
    return any(re.search(rf"(?<!\d){size}(?!\d)", ln) for _, ln in body)


def _unpinned_legs(body) -> list[str]:
    """A download leg must state the byte count it verifies against — as a
    literal (pre-C07 shape) or as a byte_pins.env var the pins file assigns
    (post-C07 shape). Anything else is an un-pinned multi-GB download."""
    assigned = {m.group(1) for _, ln in body for m in re.finditer(r"^([A-Z][A-Z0-9_]*)=\d{8,}$", ln)}
    out = []
    for _, ln in body:
        if "resolve/main" not in ln:
            continue
        if re.search(r"(?<!\d)\d{8,}(?!\d)", ln):
            continue
        if any(f"${name}" in ln or f"${{{name}}}" in ln for name in assigned):
            continue
        out.append(ln.strip())
    return out


def _marker_pattern(body) -> str:
    """How the orca completeness marker can be spelled in the script: the chunk's
    literal path, or a shell variable assigned to it (C01's shape assigns once and
    references "$MARK" in the guard and the touch). Returns the regex alternation
    that matches any of those spellings."""
    names = [m.group(1) for _, ln in body if (m := re.match(r"^(\w+)=\S*(?:pack-orca|setup-ORCA)", ln.strip()))]
    return r"\.pack-orca|\.setup-ORCA" + "".join(rf"|\$\{{{n}\}}|\${n}\b" for n in names)


# --- AC2: the fourth arena, its contract, the alternation ---------------------


@helm
def test_c02_orca_arena_served_with_residency_contract():
    """The orca arena carries the same residency contract as the primary
    (ttl 3600 time-share, 180 s unload window, /health readiness) — the arena
    (~49.8 GiB, ORCA.md) sits at today's envelope, so nothing here moves."""
    new, primary = _model(S.ORCA_INNER_ID), S.inner_config(_docs())["models"][S.PRIMARY_ID]
    for key, want in (("ttl", 3600), ("unloadTimeout", 180), ("checkEndpoint", "/health")):
        assert new.get(key) == want, f"{S.ORCA_INNER_ID}.{key} = {new.get(key)!r}, want {want!r}"
    assert new["cmd"] == primary["cmd"].replace(
        f"--profile /profile/{S.PROFILE_PRIMARY_FILE}", f"--profile /profile/{S.PROFILE_ORCA_FILE}"
    ), f"orca cmd must mirror the frozen serve wrapper: {new['cmd']!r}"
    flags = set(S.cmd_flag_tokens(new["cmd"]))
    assert not flags - S.SERVE_FLAGS, f"serve flags outside the frozen set: {sorted(flags - S.SERVE_FLAGS)}"


@helm
def test_c02_inner_alias_unique_and_not_the_outer_orca_id():
    """The inner alias `qwen3.8-flash-next-orca` must be unique across the
    arenas and must NOT equal the outer llama.cpp id `…-orca-q6`: two routable
    surfaces with one name would split the same model family across engines
    invisibly (the plan's frozen-id rule)."""
    cfg = S.inner_config(_docs())
    _model(S.ORCA_INNER_ID)

    def claimed(surface) -> list:
        val = surface.get("aliases")
        return [val] if isinstance(val, str) else list(val or [])

    # The shipped alias surface is the run-config profile's `aliases` list (the
    # inner supervisor's route keys) — model-level aliases are accepted too in
    # case a rung spells them there.
    holders = []
    for mid, m in cfg["models"].items():
        if ORCA_INNER_ALIAS in claimed(m):
            holders.append(f"model:{mid}")
        prof_file = S.profile_file_of(m)
        if prof_file and ORCA_INNER_ALIAS in claimed(S.profile_json(_docs(), prof_file)):
            holders.append(f"profile:{prof_file}")
    assert holders, (
        f"no inner surface claims the frozen alias {ORCA_INNER_ALIAS!r} "
        f"(aliases seen: {sorted({a for m in cfg['models'].values() for a in claimed(m)})})"
    )
    # Uniqueness is per route key, NOT global: primary/strix legitimately share
    # the family alias qwen3.8-flash-next today, but one key resolving to two
    # arenas would route a request ambiguously.
    assert len(holders) == 1, f"inner alias {ORCA_INNER_ALIAS} claimed by {holders} — one key, one arena"
    assert ORCA_INNER_ALIAS != OUTER_ORCA_ID


@helm
def test_c02_matrix_alternatives_extend_to_o():
    """vars gain `o` and sets.main stays an ALTERNATION: no DNF combo may hold
    two arenas (additive page-locked arenas on the 128 GB node = #1715)."""
    cfg = S.inner_config(_docs())
    vars_ = (cfg.get("matrix") or {}).get("vars") or {}
    assert vars_.get("o") == S.ORCA_INNER_ID, f"matrix.vars.o = {vars_.get('o')!r}"
    arenas = set(S.INNER_MATRIX_VARS.values())  # combos hold resolved MODEL ids, not letters
    for combo in S.matrix_expansions(cfg).get("main", []):
        clash = combo & arenas
        assert len(clash) <= 1, f"matrix combo co-loads arenas {sorted(clash)}"
    reachable = {next(iter(c & arenas)) for c in S.matrix_expansions(cfg).get("main", []) if c & arenas}
    assert reachable >= {S.PRIMARY_ID, S.STRIX_ID, S.ABL_ID, S.ORCA_INNER_ID}, (
        f"arenas reachable in sets.main: {sorted(reachable)}"
    )


@helm
def test_c02_four_profiles_and_orca_shape():
    """Four files in the strata-profile ConfigMap; the orca JSON parses, names
    the frozen model_name, keeps api_key none / user_args empty, and reuses the
    primary's memory-declaration envelope verbatim (chunk Notes: no memory-key
    changes for the ~49.8 GiB arena)."""
    cfg = S.inner_config(_docs())
    assert S.profile_files(_docs()) == S.expected_profile_files(cfg["models"])
    prof = _profile()
    assert prof.get("model_name") == "qwen3.8-flash-next-orca-iq3_xxs", f"model_name {prof.get('model_name')!r}"
    assert prof.get("api_key") == S.API_KEY_NONE
    assert prof.get("user_args") == []
    args = dict(S.arg_pairs(prof))
    primary = dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)))
    for flag in ("--memory-limit-mib", "--kv-resident", "--conversation-cache-mib",
                 "--conversation-cache-slots", "--max-context", "--kv"):
        assert args.get(flag) == primary.get(flag), (
            f"orca {flag} = {args.get(flag)!r} != primary {primary.get(flag)!r} — the IQ3_XXS "
            "arena rides the same envelope; a trim here is an untracked budget change"
        )


@helm
def test_c02_pack_paths_strata_data_shaped_and_distinct():
    """IQ3_XXS-orca paths: under Strata-data, and not the IQ3_S primary's pack
    or weights (the branch-B staging layout is gate-parameterized, so the shape
    plus distinctness is the executable part of the contract)."""
    args = dict(S.arg_pairs(_profile()))
    primary = dict(S.arg_pairs(S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)))
    for flag in ("--pack", "--native"):
        val = args.get(flag) or ""
        assert val.startswith("/models/strata/Strata-data/"), f"{flag} = {val!r} outside Strata-data"
        assert val != primary.get(flag), f"{flag} reuses the IQ3_S path — orca would serve the primary's weights"
    prof = _profile()
    tok = prof.get("tokenizer")
    assert isinstance(tok, str) and tok.startswith("/models/strata/Strata-data/"), (
        f"profile-level tokenizer = {tok!r} — the run-config vocabulary spells tokenizer as a "
        "top-level key beside args (setup.py@v0.2.7 SETUP_KEYS), never as an engine arg"
    )
    assert not any("tokenizer" in str(a) for a in S.arg_tokens(prof)), "tokenizer spelled as an engine arg"
    assert tok != S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE).get("tokenizer"), (
        "orca arena resolves the IQ3_S pack's tokenizer directory — the tokenizer dir rides inside each pack"
    )


@helm
def test_c02_earlier_profiles_still_byte_unchanged():
    """Preservation for the arenas C02 must not touch, against the frozen-era
    captures (era map in strata_testlib; strix's C07-era chain is guarded in
    test_strata_strix). C01's abliterated profile is guarded by that chunk's
    own frozen pins (envelope/paths/flags) — this suite never re-captures goldens."""
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        assert S.profile_fixture(file) == S.profile_json(_docs(), file), f"{file} diverged from its frozen-era capture"


# --- AC3/AC4: the token-placement law ----------------------------------------


@helm
def test_c02_hf_token_reaches_the_model_fetch_init_only():
    """R-d ruling (DECISIONS): the existing hf-token Secret is sanctioned for
    DOWNLOAD ONLY, consumed via secretKeyRef on the strata model-fetch init.
    Asserted on the SERVICE-overlay render — the Secret is gpu-ai-only, so the
    chart's bare render has nothing to wire."""
    docs = _service_docs()
    env = _init_container(docs).get("env") or []
    hf = [e for e in env if str((e.get("name") if isinstance(e, dict) else e)) == "HF_TOKEN"]
    assert hf, (
        "the model-fetch init carries no HF_TOKEN — C02's gated orcarouter pack "
        "(R-d sanctioned download) not landed"
    )
    entry = hf[0]
    assert isinstance(entry, dict) and entry.get("valueFrom", {}).get("secretKeyRef", {}).get("name") == "hf-token", (
        f"HF_TOKEN must come from secretKeyRef hf-token, not a literal: {entry!r}"
    )


@helm
def test_c02_serve_path_stays_keyless_despite_the_init_token():
    """AC4's negative arm: even with the init carrying the token, nothing
    reaches the serve path — no HF_TOKEN/secret chain in the strata container,
    the inner config apiKeys, or any run-config profile."""
    hits = S.serve_path_secret_hits(_service_docs())
    assert not hits, f"secret material on the strata serve path: {hits}"
    assert S.inner_config(_service_docs()).get("apiKeys") == [], "inner apiKeys must stay []"
    for file in S.profile_files(_service_docs()):
        assert S.profile_json(_service_docs(), file).get("api_key") == S.API_KEY_NONE, f"{file} api_key changed"


# --- AC6: manual-pack step invariants ----------------------------------------


@helm
def test_c02_pack_step_is_marker_gated_and_never_destructive():
    """Branch-B idempotency contract: the init script names the `.pack-orca`
    marker (never overwrite without it), keeps the script's existing loud-fail
    helper, and never deletes the Strata-data tree — an interrupted 85 GB pack
    must fail loudly, not get wiped and re-pulled on the next pod start."""
    script = _init_script(_docs())
    assert PACK_MARKER in script, (
        f"model-fetch init does not reference {PACK_MARKER} — C02's idempotent "
        "manual-pack step (branch B) not landed"
    )
    assert "fail()" in script, "the init script lost its loud-fail helper"
    for line in script.splitlines():
        if line.strip().startswith("#"):
            continue
        assert "rm -rf /models/strata/Strata-data" not in line, (
            f"destructive pack delete in the init script: {line.strip()!r} — pack re-pulls are "
            "marker-gated, never wipe-and-redownload"
        )


@helm
def test_c02_peers_carries_the_orca_arena_once():
    """AC5: the outer peers list is the evidence's four-id wave once C02 lands
    (no dups, no phantom). The wave law itself lives in the evidence file +
    strata_testlib; this is the chunk-facing pin."""
    docs = _service_docs()
    served = set(S.inner_config(docs)["models"])
    if S.ORCA_INNER_ID not in served:
        pytest.fail(
            f"peers AC5 unresolvable: the inner config serves no {S.ORCA_INNER_ID} — C02 not landed"
        )
    outer = S.by_name_kind(docs, "ConfigMap", "llama-swap-config")
    cfg = yaml.safe_load(outer["data"]["config.yaml"])
    peers = cfg["peers"][S.PEER_NAME]["models"]
    assert peers == S.expected_strata_peers(served), f"peers {peers} diverge from the wave for {sorted(served)}"
    assert S.ORCA_INNER_ID in peers, f"orca arena has no peers route: {peers}"
    assert len(set(peers)) == len(peers), f"duplicate peers models: {peers}"


# --- AC6 addendum (C01 review deferral): laws of the code path C02 reuses -----
# C01 review round 2 deferred these because nothing pinned them: the pack step's
# downloader mechanism, its byte pins, and the completeness-marker ordering. C02
# stages its 85.20 GB gated pack through the same init and the same downloader,
# so a regression on this path is C02 acceptance, not C01 archaeology.


@helm
def test_c02_downloader_reuses_the_venv_urllib_path_not_a_shell_client():
    """Staging is driven by the checkout venv interpreter over stdlib urllib —
    the image provably carries no curl, and setup's own downloader is the same
    stdlib call. C02's gated fetch must extend that body with an Authorization
    header, not introduce a second client."""
    body = _body_lines(_docs())
    offenders = [ln.strip() for _, ln in body if _HTTP_CLIENT.search(ln)]
    assert not offenders, f"model-fetch init invokes a shell HTTP client: {offenders}"
    assert any(".venv/bin/python" in ln for _, ln in body), (
        "no $SRC/.venv/bin/python download driver — C01's staging mechanism was replaced"
    )
    assert "urllib.request" in _downloader_text(), "the staged fetch is no longer stdlib urllib"


@helm
def test_c02_abliterated_stage_keeps_the_byte_pins_the_orca_stage_copies():
    """Each download invocation carries its HF-tree byte size: the downloader
    loops until that size and `mv`s only on an exact match, so the pin is what
    keeps a truncated shard out of iq_pack. Green today on the C01 path; it is
    the shape C02's orca stage must reproduce."""
    body = _body_lines(_docs())
    assert any(HF_REPO_ABL in ln for _, ln in body), f"init script no longer names {HF_REPO_ABL}"
    for size in ABL_SHARD_BYTES:
        assert _pins_size(body, size), f"abliterated shard byte pin {size} missing from the staging program"
    unpinned = _unpinned_legs(body)
    assert not unpinned, f"download invocation with no byte pin: {unpinned}"


@helm
def test_c02_reuse_source_marks_the_pack_only_after_it_builds():
    """The marker discipline C02 has to copy, pinned on the path it copies from:
    skip when the marker exists, run the pack, `touch` the marker last. A marker
    written before the pack completes makes a partial pack permanent — the skip
    guard means nothing ever re-enters the step, and the arena serves missing
    weights."""
    body = _body_lines(_docs())
    assign = [(n, ln) for n, ln in body if re.match(r"^\s*\w+=\S*\.setup-", ln)]
    assert assign, "no /models/strata/.setup-* marker assignment — C01's skip-guard pattern is gone"
    var = re.match(r"^\s*(\w+)=", assign[0][1]).group(1)
    guard = re.compile(r'\[\s*-f\s+"\$' + var + r'["}]')
    touch = re.compile(r'touch\s+"\$' + var + r'["}]')
    assert any(guard.search(ln) for _, ln in body), (
        f"the .setup marker has no `-f` skip guard — every boot re-provisions: {assign}"
    )
    pack_calls = [n for n, ln in body if re.match(r"^\s*abl_pack\b", ln)]
    touches = [n for n, ln in body if touch.search(ln)]
    assert pack_calls and touches, f"abl_pack call or marker touch missing (packs: {pack_calls}, touches: {touches})"
    assert min(touches) > min(pack_calls), (
        f"marker touched at line {min(touches)} before abl_pack at {min(pack_calls)} — "
        "the marker claims a pack the step has not built yet"
    )


@helm
def test_c02_orca_profile_serves_exactly_the_staged_paths():
    """The pairing law the C02 review deferred: the arena is only correct if the
    paths the run-config profile serves are the paths the init stages — a profile
    pointing one directory off serves the wrong weights or none, and every other
    arm stays green. Derived from both sides of the render (script assignments and
    profile args), so a rename on one side goes red instead of a literal on the
    other side drifting with it."""
    docs = _docs()
    tier = _staged_tier(_service_docs())
    staged = _staged_paths(_init_script(docs), tier)
    prof = _profile()
    args = dict(S.arg_pairs(prof))

    assert tier == "IQ3_XXS", (
        f"orca staging tier {tier!r} — the C07-era wave pins IQ3_XXS; C08's shift to "
        "IQ4_XS is pinned (with its own path law) in test_strata_c08_rung_shifts.py"
    )
    assert args.get("--pack") == staged["pack"], (
        f"profile --pack {args.get('--pack')!r} != the pack the init builds at {staged['pack']!r}"
    )
    assert prof.get("tokenizer") == f"{staged['pack']}/tokenizer", (
        f"profile tokenizer {prof.get('tokenizer')!r} != iq_pack's exported directory "
        f"{staged['pack']}/tokenizer (the pack carries its own tokenizer/)"
    )
    assert args.get("--native") == staged["s1"], (
        f"profile --native {args.get('--native')!r} != staged shard 1 {staged['s1']!r} "
        "(the file iq_pack was run against)"
    )
    # ORCA.md's example profile points --native and --ple-gguf at the SAME shard
    # for this pack: its PLE table rides inside shard 1, unlike the SC117 pair.
    assert args.get("--ple-gguf") == staged["s1"], (
        f"profile --ple-gguf {args.get('--ple-gguf')!r} != staged shard 1 {staged['s1']!r} — "
        "the orcarouter PLE table lives in shard 1 (ORCA.md)"
    )
    legs = _orca_download_legs(_init_script(docs), _body_lines(docs))
    for key in ("s1", "s2"):
        assert key in legs, (
            f"the init never downloads ${{{key}}} ({staged[key]!r}) — iq_pack reads both "
            "shard halves, so an unstaged half is a broken pack"
        )
        assert legs[key] in ORCA_SHARD_BYTES, (
            f"the ${{{key}}} leg carries byte pin {legs[key]}, outside the tree-API "
            f"pins {ORCA_SHARD_BYTES} — the resume/verify target and the evidence disagree"
        )


def _staged_tier(service_docs) -> str:
    """The quant tier the init stages for the orca pseudo-family, read from the
    rendered model-fetch env (`STRATA_MODEL_ORCA=[family/]TIER`)."""
    entries = {e.get("name"): e for e in _init_container(service_docs).get("env") or []}
    value = (entries.get("STRATA_MODEL_ORCA") or {}).get("value")
    assert isinstance(value, str) and "/" in value, (
        f"model-fetch env STRATA_MODEL_ORCA = {value!r} — the init has no orca routing token"
    )
    return value.rsplit("/", 1)[-1]


def _staged_paths(script: str, tier: str) -> dict:
    """The staging layout from the orca_pack body: dir/pack/stem assignments plus
    the two shard paths, expanded with the tier the loop passes."""
    body = re.search(r"^orca_pack\(\) \{\n(.*?)\n\}$", script, re.S | re.M)
    assert body, "no orca_pack function in the model-fetch init — the C02 pack step is not landed"
    block = body.group(1)

    def assign(name: str) -> str:
        m = re.search(rf"^\s*{name}=(\S+)\s*$", block, re.M)
        assert m, f"orca_pack assigns no {name} — the staging layout changed shape, re-express this arm"
        return m.group(1)

    def expand(value: str, seen: dict) -> str:
        out = value.replace("$tierl", tier.lower()).replace("$tier", tier)
        for name, val in seen.items():
            out = out.replace(f"${name}", val)
        return out

    paths, order = {}, ("dir", "pack", "stem", "s1", "s2")
    for name in order:
        paths[name] = expand(assign(name), paths)
    return paths


def _orca_download_legs(script: str, body) -> dict:
    """Variable each orca_dl writes -> the byte count it verifies against, with
    byte_pins.env vars resolved (pre-C07 the count sat on the leg line as a
    literal). Keys are bare names (`s1`), so they line up with the orca_pack
    assignments the pairing law compares against."""
    assigned = {m.group(1): int(m.group(2)) for _, ln in body
                for m in re.finditer(r"^([A-Z][A-Z0-9_]*)=(\d{8,})$", ln)}
    legs = {}
    for m in re.finditer(r'orca_dl\s+"[^"]+"\s+"\$\{?(\w+)\}?"\s+(\$?\{?[A-Z][A-Z0-9_]*\}?|\d+)', script):
        pin = m.group(2)
        legs[m.group(1)] = int(pin) if pin.isdigit() else assigned.get(pin.strip("${}"))
    return legs


@helm
def test_c02_orca_stage_pins_the_orcarouter_byte_sizes():
    """Branch-B staging of the gated IQ3_XXS pair through the same byte-pinned
    downloader. The repo literal is what stops the orca id from fetching some
    other repo's bytes; the sizes are the tree-API literals pinned above."""
    body = _body_lines(_docs())
    assert any(HF_REPO_ORCA in ln for _, ln in body), (
        f"model-fetch init never names {HF_REPO_ORCA} — the gated orca pack step (branch B) is not landed"
    )
    for size in ORCA_SHARD_BYTES:
        assert _pins_size(body, size), (
            f"orca shard byte pin {size} missing — an un-pinned 40 GB download cannot be "
            "distinguished from a truncated one"
        )
    unpinned = _unpinned_legs(body)
    assert not unpinned, f"download invocation with no byte pin: {unpinned}"


@helm
def test_c02_orca_marker_is_touched_only_after_the_pack_completes():
    """AC6 idempotency for the 85 GB rung: the chunk's `.pack-orca` marker sits
    behind a `-f` skip guard and is touched only after the staged shards and the
    pack step have run (the touch follows the byte-pinned downloads in script
    order), so an interrupted pack re-enters the step instead of being marked done."""
    body = _body_lines(_docs())
    pattern = _marker_pattern(body)
    refs = [(n, ln) for n, ln in body if re.search(pattern, ln)]
    assert refs, f"model-fetch init has no {PACK_MARKER} completeness marker reference — C02 not landed"
    assert any(re.search(rf"\[\s*-f\s+\"?({pattern})", ln) for _, ln in refs), (
        f"no `-f` skip guard on the orca marker — every boot re-downloads 85.20 GB: {[ln for _, ln in refs]}"
    )
    touches = [n for n, ln in refs if re.search(rf"touch\s+\"?({pattern})", ln)]
    assert touches, f"nothing touches the orca marker: {[ln for _, ln in refs]}"
    staged = [n for n, ln in body if re.search(r"\borca_dl\s+\"https?://", ln)]
    assert staged, "no orca download leg to order the marker against (see the byte-pin arm)"
    assert min(touches) > max(staged), (
        f"orca marker touched at line {min(touches)}, before its staged shards at "
        f"{max(staged)} — a pack that never completed would be marked complete"
    )


@hf_live
def test_c02_pack_pins_still_match_the_live_hf_trees():
    """Re-reads both trees the literals above came from, anonymously — no
    credential is sent, so this arm proves the metadata is public while the
    orca BYTES stay token-gated (401 + Bearer challenge on resolve/main), which
    is the fact AC3's download-only token rests on."""
    sizes = {f["path"]: f.get("size") or (f.get("lfs") or {}).get("size") for f in _tree(HF_REPO_ABL, "IQ3_XXS")}
    abl = {name: size for name, size in sizes.items() if name.endswith(".gguf")}
    assert sorted(abl.values()) == sorted(ABL_SHARD_BYTES), f"SC117 IQ3_XXS tree now reports {abl} — re-pin the literals"

    orca = {
        f["path"]: f.get("size") or (f.get("lfs") or {}).get("size")
        for f in _tree(HF_REPO_ORCA)
        if "-IQ3_XXS-" in f["path"] and f["path"].endswith(".gguf")
    }
    assert sorted(orca.values()) == sorted(ORCA_SHARD_BYTES), f"orcarouter IQ3_XXS tree now reports {orca} — re-pin"

    shard = next(name for name in orca if name.endswith("-00001-of-00002.gguf"))
    try:
        urllib.request.urlopen(f"https://huggingface.co/{HF_REPO_ORCA}/resolve/main/{shard}", timeout=30)
        gated = False
    except urllib.error.HTTPError as err:
        gated = err.code in (401, 403)
    assert gated, (
        f"{HF_REPO_ORCA}/resolve/main served {shard} anonymously — the gated premise behind "
        "the init-token exception (R-d) needs re-ruling"
    )


def _tree(repo: str, path: str = "") -> list:
    """Anonymous HF tree listing. Deliberately sends no Authorization header and
    never reads HF_TOKEN: a suite arm that consumed the token could not tell a
    public repo from a gated one."""
    url = f"https://huggingface.co/api/models/{repo}/tree/main" + (f"/{path}" if path else "")
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.loads(resp.read())
