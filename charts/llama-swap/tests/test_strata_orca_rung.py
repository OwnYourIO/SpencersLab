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

import pytest
import yaml

import strata_testlib as S

_ok, _reason = S.env_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

ORCA_INNER_ALIAS = "qwen3.8-flash-next-orca"
OUTER_ORCA_ID = "qwen3.8-flash-next-orca-q6"
PACK_MARKER = S.ORCA_PACK_MARKER


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
    ctr = _init_container(docs)
    return "\n".join([str(x) for x in (ctr.get("command") or [])] + [str(x) for x in (ctr.get("args") or [])])


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
    """Preservation for the arenas C02 must not touch, against the pre-cf-86
    captures. C01's abliterated profile is guarded by that chunk's own frozen
    pins (envelope/paths/flags) — this suite never re-captures goldens."""
    fixtures = S.EVIDENCE_DIR / "strata-profiles-pre-cf86"
    for file in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        before = json.loads((fixtures / file).read_text())
        assert before == S.profile_json(_docs(), file), f"{file} diverged from the pre-cf-86 capture"


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
    docs, _raw = _service_docs()
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
