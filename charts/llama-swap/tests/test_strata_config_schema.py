# r2-C01 config-schema contract — the INNER llama-swap config + run-config
# profiles rendered by the parent chart's gated templates
# (run-2 chunks/C01.md AC4; run-1 C02 AC4/AC5 semantics re-homed unchanged).
#
# No upstream JSON schema exists for strata run-config profiles (run-1
# residual 3): the repo-side gate is valid JSON + required/forbidden token
# sets + the C-A keyless pin; semantic validation is the on-target
# `strata serve --plan` runbook step, NOT a repo test.
#
# RED until r2-C01 lands (the ON render fails before then); the v266 schema
# fixture self-checks are green today by design.

from __future__ import annotations

import json

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
_js_ok, _js_reason = S.jsonschema_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)
schema_gated = pytest.mark.skipif(not (_ok and _js_ok), reason=_js_reason if _ok else _reason)


def _docs():
    return S.render_on()[0]


def _primary_model(docs):
    return S.inner_config(docs)["models"][S.PRIMARY_ID]


# --- schema fixture provenance (green today — validates the moved file) --------


@schema_gated
def test_c01_vendored_schema_declares_peers_required_keys():
    """Provenance sanity: the vendored generation has the peers shape the
    route rides (required proxy+models) — guards a wrong-tag re-vendor before
    any config touches it."""
    peers = S.v266_schema()["properties"]["peers"]["additionalProperties"]
    assert sorted(peers["required"]) == ["models", "proxy"]


# --- AC4: inner config vs the VENDORED v266 schema -----------------------------


@schema_gated
def test_c01_ac4_inner_config_validates_against_v266_schema():
    """v266 = the deployed pin's schema; main-only keys would false-fail
    (run-1 RESEARCH 'Implications/Validation'); schema/PROVENANCE.json carries
    the vendored digest."""
    errs = S.schema_errors(S.inner_config(_docs()))
    assert not errs, [(list(e.absolute_path), e.message) for e in errs[:8]]


@helm
def test_c01_ac4_top_level_config_literals():
    cfg = S.inner_config(_docs())
    assert cfg.get("healthCheckTimeout") == 1800, (
        "1800 fits the ~17.3 GiB/s arena read of the cold pin (run-1 O2)"
    )
    assert cfg.get("startPort") == 10001
    assert cfg.get("globalTTL") == 0, "Q2 lazy posture: nothing unloads on a timer"
    assert cfg.get("apiKeys") == [], (
        "empty = default-allow; the keyless posture (C-A) mirrors this on the engine side"
    )


@helm
def test_c01_ac4_model_residency_and_stop_windows():
    m = _primary_model(_docs())
    assert m.get("ttl") == 3600, (
        "time-share residency (2026-10-29 OOM post-mortem): permanent pin "
        "beside uncapped llama.cpp demand harvested the node; 3600s idle "
        "hands the arena back; flip to 0 only for dedicated windows"
    )
    assert m.get("unloadTimeout") == 180, (
        "llama-swap force-kills at the GLOBAL default 10s long before the 420s grace "
        "matters — a ~47 GiB page-locked unload needs the raised window (run-1 contradictions #4)"
    )
    assert m.get("checkEndpoint") == "/health"
    hooks = S.inner_config(_docs()).get("hooks") or {}
    preload = ((hooks.get("on_startup") or {}).get("preload")) or []
    assert preload == [], "preload must stay empty (swap-load warning for matrix alternatives, run-1 RESEARCH §3)"
    assert "proxy" not in m, (
        "cmd uses ${PORT} — an explicit proxy key is the port-drift bug the skill calls "
        "the most common config error; absence is the contract here"
    )


@helm
def test_c01_ac4_cmd_is_the_serve_wrapper_verbatim():
    """SanitizeCommand-safe single form; the cmd is UNCHANGED by run 2 — only
    the secret chain left. serve carries ONLY these flags (run-1 RESEARCH §2):
    no --api-key flag exists, no engine tuning in cmd."""
    cmd = S.norm_ws(_primary_model(_docs())["cmd"])
    expected = S.norm_ws(
        "bash -c 'ulimit -n 524288; exec /opt/strata/terminal/bin/strata serve "
        f"--profile /profile/{S.PROFILE_PRIMARY_FILE} --host 127.0.0.1 --port ${{PORT}}'"
    )
    assert cmd == expected, f"cmd diverges from the serve-wrapper contract:\n got: {cmd}\nwant: {expected}"
    flags = set(S.cmd_flag_tokens(cmd))
    assert flags <= S.SERVE_FLAGS, f"non-serve flags in cmd: {sorted(flags - S.SERVE_FLAGS)}"


@helm
def test_c01_ac4_ulimit_wrapper_stays_mandatory():
    """No release self-raises nofile (PR #2399 open, run-1 RESEARCH §2 /
    contradiction #5): `ulimit -n 524288` is load-bearing for any future
    --kv-grow flip."""
    cmd = _primary_model(_docs())["cmd"]
    assert "ulimit -n 524288" in cmd


@helm
def test_c01_ac4_env_contract_keyless():
    m = _primary_model(_docs())
    env = set(S.env_list(m))
    for entry in S.PRIMARY_ENV_FIVE:
        assert entry in env, f"PR #3636 one-at-a-time arm env switch missing: {entry}"
    assert "STRATA_PREFILL_CPU_SHARE=auto" in env
    rocr = [e for e in env if e.startswith("ROCR_VISIBLE_DEVICES=")]
    assert rocr == ["ROCR_VISIBLE_DEVICES=0"], f"default device pin (on-target rocminfo retargets via strata.rocrVisibleDevices): {rocr}"
    # C-A: the ${env.STRATA_API_KEY} passthrough is DELETED, not guarded —
    # its run-1 absence would now be a config-load landmine instead of a gate.
    assert not any("STRATA_API_KEY" in e for e in env), (
        f"STRATA_API_KEY reference survived in model env (C-A deletion incomplete): {env}"
    )


@helm
def test_c01_container_env_has_no_secret_ref():
    """The container-side secretKeyRef died with the chain; the strata
    container keeps only values-driven env (ROCR retarget rides model env —
    run-1 shape minus the key)."""
    ctr = S.strata_container(_docs())
    blob = json.dumps(ctr.get("env") or [])
    assert "STRATA_API_KEY" not in blob and "secretKeyRef" not in blob, (
        f"secret-chain remnants in strata container env (C-A): {blob}"
    )


# --- AC4/profiles: the run-config bodies ----------------------------------------


@helm
def test_c01_ac4_profiles_pin_api_key_none():
    """C-A shipped default: BOTH run-configs carry `"api_key": "none"`
    (run-1 RESEARCH §2: config `api_key` accepts "none"; --api-key was never a
    serve flag)."""
    for fn in (S.PROFILE_PRIMARY_FILE, S.PROFILE_STRIX_FILE):
        profile = S.profile_json(_docs(), fn)
        assert profile.get("api_key") == S.API_KEY_NONE, (
            f"{fn}: api_key is {profile.get('api_key')!r}, expected 'none' (C-A)"
        )


@helm
def test_c01_ac5_profile_is_valid_json_rendered_verbatim():
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    assert isinstance(profile, dict)


@helm
def test_c01_ac5_required_arg_pairs():
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    pairs = S.arg_pairs(profile)
    for flag, value in S.PRIMARY_REQUIRED_PAIRS:
        assert (flag, value) in pairs, (
            f"{flag} {value} missing — the r9700-arena-pf32k seed (run-1 RESEARCH §5) minus "
            f"the ruled exclusions; pairs present: {pairs}"
        )
    toks = set(S.arg_tokens(profile))
    for flag in S.PRIMARY_REQUIRED_FLAGS:
        assert flag in toks, (
            f"{flag} missing — the seed carries it and no ruling excluded it "
            "(its value stays values-configurable, so only presence is pinned)"
        )


@helm
def test_c01_ac5_forbidden_flags_absent():
    """Regression guard against re-introducing the card guide's
    misattributions: --resident-budget-gib flips the engine to --mmap-experts
    (opposite of the page-locked arena), --prompt-cache* is the #4206 no-op
    edge, --kv-grow is R4-deferred, --vision is R2-off, --kv-resident is the
    batch-column item."""
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    toks = S.arg_tokens(profile)
    offenders = [t for t in toks if any(t.startswith(f) for f in S.PRIMARY_FORBIDDEN_FLAGS)]
    assert not offenders, f"forbidden args in primary profile: {offenders}"


@helm
def test_c01_ac5_profile_shape_keys():
    """Run-config key vocabulary (run-1 RESEARCH §2, measured from
    profiles.py). NO `port` key — llama-swap owns the port via ${PORT}→--port;
    a baked port pins the arena server to a port the supervisor didn't
    assign."""
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    for key in ("exe", "args", "env", "backend", "aliases", "gpu", "tokenizer", "model_name"):
        assert key in profile, f"run-config key {key!r} missing (run-1 RESEARCH §2 shape)"
    assert "port" not in profile
    assert profile.get("backend") == "hip"
    assert profile.get("user_args") in ([], None), "user_args must start empty (person-wins layer)"
    assert isinstance(profile.get("lib_dirs"), list) and profile["lib_dirs"], "lib_dirs list missing"


@helm
def test_c01_ac5_env_map_no_void_token():
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    env = profile.get("env") or {}
    assert S.VOID_ENV_TOKEN not in env
    for k in env:
        assert k == k.upper(), f"env key {k!r} not spelled as the upstream literal"


@helm
def test_c01_removed_items_are_commented_values_toggles():
    """Q-D: the engine toggles (kv-grow R4, vision R2, preload flip, the
    removed misattributions) relocate VERBATIM with the profile bodies — each
    stays one values edit. Reads the values source because comments vanish in
    the render."""
    text = S.read(S.CHART_DIR / "values.yaml", "r2-C01 relocates config.engineProfile under strata:")
    region = S.values_region(text, "engineProfile")
    for token in ("kv-grow", "vision", "resident-budget-gib", "prompt-cache-every"):
        assert token in region, (
            f"{token}: run-1 amendment removed it but left no commented toggle in the relocated "
            "engineProfile (Q-D says the toggles ride along untouched)"
        )


# --- run-1 C01 seam: exe literals pin the container README contract -------------


@helm
def test_c01_seam_exe_matches_container_readme_form():
    """Post-transplant (2026-10-29): the primary's exe is the engine the
    model-fetch setup COMPILED into the checkout on the claim — the seam to
    containers/strata is the documented compile flow ("compiles the
    checkout's AMD engine"), no longer a packaged label dir. Strix still
    pins the packaged halo root (test_strata_strix covers that seam)."""
    readme = S.read(S.CONTAINER_DIR / "README.md", "the C01 image contract lives in the container, unchanged")
    exe = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)["exe"]
    assert exe == "/models/strata/Strata/engine/strata", (
        f"primary profile exe {exe!r} must be the checkout-compiled engine "
        "(generated run-config baseline, 2026-10-29 transplant)"
    )
    assert "compiles the checkout" in readme, (
        "container README no longer documents the setup compile the primary "
        "exe seam relies on — re-establish before landing a profile change"
    )


@helm
def test_c01_seam_serve_entry_is_readme_path():
    readme = S.read(S.CONTAINER_DIR / "README.md", "C01 README documents the serve entry")
    assert S.SERVE_ENTRY in readme
    assert S.SERVE_ENTRY in _primary_model(_docs())["cmd"]
