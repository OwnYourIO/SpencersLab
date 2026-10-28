# C02 config-schema contract — inner llama-swap config + run-config profile
# (chunks/C02.md AC4/AC5; C01 README seam per the coordinator's residual 2).
#
# No upstream JSON schema exists for strata run-config profiles (residual 3):
# the repo-side gate is valid JSON + the required/forbidden token sets below;
# semantic validation is the on-target `strata serve --plan` runbook step
# (C04/human step 3), NOT a repo test.

from __future__ import annotations

import pytest

import strata_testlib as S

_ok, _reason = S.env_ready()
_js_ok, _js_reason = S.jsonschema_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)
schema_gated = pytest.mark.skipif(not (_ok and _js_ok), reason=_js_reason if _ok else _reason)


def _docs():
    return S.render_strata()[0]


def _primary_model(docs):
    return S.inner_config(docs)["models"][S.PRIMARY_ID]


# --- C02 AC4: inner config vs the VENDORED v266 schema ------------------------


@schema_gated
def test_c02_ac4_inner_config_validates_against_v266_schema():
    """v266 = the deployed pin's schema (charts/llama-swap unified-vulkan-266).
    main-only keys would false-fail — RESEARCH "Implications/Validation";
    schema/PROVENANCE.json carries the vendored digest."""
    errs = S.schema_errors(S.inner_config(_docs()))
    assert not errs, [
        (list(e.absolute_path), e.message) for e in errs[:8]
    ]


@schema_gated
def test_c02_vendored_schema_declares_peers_required_keys():
    """Provenance sanity: the vendored file is the generation that has the
    peers shape C03 rides (required proxy+models) — guards a wrong-tag re-
    vendor before any config ever touches it."""
    peers = S.v266_schema()["properties"]["peers"]["additionalProperties"]
    assert sorted(peers["required"]) == ["models", "proxy"]


# --- C02 AC4: inner config literals (config: body, C02 task 2) ----------------


@helm
def test_c02_ac4_top_level_config_literals():
    cfg = S.inner_config(_docs())
    assert cfg.get("healthCheckTimeout") == 1800, (
        "1800 fits the ~17.3 GiB/s arena read of the cold pin (RESEARCH §3/O2)"
    )
    assert cfg.get("startPort") == 10001
    assert cfg.get("globalTTL") == 0, "Q2 lazy posture: nothing unloads on a timer"
    assert cfg.get("apiKeys") == [], (
        "empty = default-allow (quarantine posture DECISIONS: the secret gate lives "
        "in ${env.STRATA_API_KEY}, not in peer auth)"
    )


@helm
def test_c02_ac4_model_residency_and_stop_windows():
    m = _primary_model(_docs())
    assert m.get("ttl") == 0, "ttl 0 = NEVER unload (tri-state trap; per-model, on top of globalTTL 0)"
    assert m.get("unloadTimeout") == 180, (
        "llama-swap force-kills at the GLOBAL default 10s long before the 420s grace "
        "matters — a ~47 GiB page-locked unload needs the raised window (RESEARCH contradictions #4)"
    )
    assert m.get("checkEndpoint") == "/health"
    hooks = S.inner_config(_docs()).get("hooks") or {}
    preload = ((hooks.get("on_startup") or {}).get("preload")) or []
    assert preload == [], "preload must stay empty (swap-load warning for matrix alternatives, RESEARCH §3)"
    assert "proxy" not in m, (
        "cmd uses ${PORT} — an explicit proxy key is the port-drift bug the skill calls "
        "the most common config error; absence is the contract here"
    )


@helm
def test_c02_ac4_cmd_is_the_serve_wrapper_verbatim():
    """SanitizeCommand-safe single form (DECISIONS amend): the cmd carries ONLY
    the serve CLI shape — no --api-key flag (it does not exist on serve,
    RESEARCH §2), no engine tuning flags (those live in the profile JSON)."""
    cmd = S.norm_ws(_primary_model(_docs())["cmd"])
    expected = S.norm_ws(
        "bash -c 'ulimit -n 524288; exec /opt/strata/terminal/bin/strata serve "
        f"--profile /profile/{S.PROFILE_PRIMARY_FILE} --host 127.0.0.1 --port ${{PORT}}'"
    )
    assert cmd == expected, f"cmd diverges from the C02 contract string:\n got: {cmd}\nwant: {expected}"
    flags = set(S.cmd_flag_tokens(cmd))
    assert flags <= S.SERVE_FLAGS, f"non-serve flags in cmd: {sorted(flags - S.SERVE_FLAGS)}"


@helm
def test_c02_ac4_ulimit_wrapper_stays_mandatory():
    """No release self-raises nofile (PR #2399 still open, RESEARCH §2/contradiction #5):
    `ulimit -n 524288` in the wrapper is load-bearing for any future --kv-grow flip."""
    cmd = _primary_model(_docs())["cmd"]
    assert "ulimit -n 524288" in cmd


@helm
def test_c02_ac4_env_contract():
    m = _primary_model(_docs())
    env = set(S.env_list(m))
    for entry in S.PRIMARY_ENV_FIVE:
        assert entry in env, f"PR #3636 one-at-a-time arm env switch missing: {entry}"
    assert "STRATA_PREFILL_CPU_SHARE=auto" in env
    assert "STRATA_API_KEY=${env.STRATA_API_KEY}" in env, (
        "the ${env.} reference must stay UNSET-able: an unset env var is a hard llama-swap "
        "config-load failure — that breakage IS the pre-sync quarantine gate (C02 dev note)"
    )
    rocr = [e for e in env if e.startswith("ROCR_VISIBLE_DEVICES=")]
    assert rocr == ["ROCR_VISIBLE_DEVICES=0"], f"default device pin (on-target rocminfo retargets via values): {rocr}"


@helm
def test_c02_ac4_rocr_values_overridable():
    docs, _ = S.render_strata(overlay={"rocrVisibleDevices": "3"})
    env = S.env_list(_primary_model(docs))
    assert "ROCR_VISIBLE_DEVICES=3" in env, f"values key did not reach inner config: {env}"


@helm
def test_c02_no_secret_material_in_inner_config():
    """The Bitwarden UUID belongs to the guard-rendered ExternalSecret and the
    API key to the pod env — never to the config ConfigMap, which the reloader
    diffs and every in-pod process can read."""
    import json
    docs, _raw = S.render_strata(
        sets=("domain=test.example.com", "bitwardenIds.strata-api-key=test-uuid"))
    assert "test-uuid" not in json.dumps(S.inner_config(docs)), (
        "bitwardenIds value leaked into the llama-swap config.yaml"
    )


# --- C02 AC5: the run-config profile ------------------------------------------


@helm
def test_c02_ac5_profile_is_valid_json_rendered_verbatim():
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    assert isinstance(profile, dict)


@helm
def test_c02_ac5_required_arg_pairs():
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    pairs = S.arg_pairs(profile)
    for flag, value in S.PRIMARY_REQUIRED_PAIRS:
        assert (flag, value) in pairs, (
            f"{flag} {value} missing — seeded from the PR #3636 r9700-arena-pf32k.json "
            f"class (RESEARCH §5); arg pairs present: {pairs}"
        )
    toks = set(S.arg_tokens(profile))
    for flag in S.PRIMARY_REQUIRED_FLAGS:
        assert flag in toks, (
            f"{flag} missing — the seed carries it and no ruling excluded it "
            "(its value stays values-configurable, so only presence is pinned)"
        )


@helm
def test_c02_ac5_forbidden_flags_absent():
    """The regression guard against re-introducing the card guide's
    misattributions: --resident-budget-gib flips the engine to --mmap-experts
    (the opposite of the page-locked arena), --prompt-cache* is the #4206
    no-op edge, --kv-grow is R4-deferred, --vision is R2-off, --kv-resident
    is the batch-column item the DECISIONS amendment removed."""
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    toks = S.arg_tokens(profile)
    offenders = [t for t in toks if any(t.startswith(f) for f in S.PRIMARY_FORBIDDEN_FLAGS)]
    assert not offenders, f"forbidden args in primary profile: {offenders}"


@helm
def test_c02_ac5_profile_shape_keys():
    """Run-config key vocabulary (RESEARCH §2, measured from profiles.py):
    exe/args/user_args/env/tokenizer/model_name/lib_dirs/backend/aliases/gpu.
    NO `port` key — llama-swap owns the port via ${PORT}→--port; a baked port
    would pin the arena server to a port the supervisor didn't assign."""
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    for key in ("exe", "args", "env", "backend", "aliases", "gpu", "tokenizer", "model_name"):
        assert key in profile, f"run-config key {key!r} missing (RESEARCH §2 shape)"
    assert "port" not in profile
    assert profile.get("backend") == "hip"
    assert profile.get("user_args") in ([], None), "user_args must start empty (person-wins layer, RESEARCH §2)"
    assert isinstance(profile.get("lib_dirs"), list) and profile["lib_dirs"], "lib_dirs list missing"


@helm
def test_c02_ac5_env_map_no_void_token():
    profile = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)
    env = profile.get("env") or {}
    assert S.VOID_ENV_TOKEN not in env
    for k in env:
        assert k == k.upper(), f"env key {k!r} not spelled as the upstream literal"


@helm
def test_c02_ac5_removed_items_are_commented_values_toggles():
    """AC5 second clause: each amendment-removed item stays reachable as a
    documented values toggle — comments are invisible in the render, so this
    reads the values.yaml source region."""
    text = S.read(S.CHART_DIR / "values.yaml", "C02 task 3 writes config.engineProfile")
    region = S.values_region(text, "engineProfile")
    for token in ("kv-grow", "vision", "resident-budget-gib", "prompt-cache-every"):
        assert token in region, (
            f"{token}: removed per DECISIONS but no commented toggle in config.engineProfile "
            "(AC5 — the deferral must stay one values edit, not a template rewrite)"
        )


# --- C01 seam: exe literals pin the README-captured contract (residual 2) ------


@helm
def test_c01_seam_exe_matches_readme_contract_form():
    """The engine binary's FILENAME is a C01 build-time capture — never
    invented here. What IS pinned: the contract form
    /opt/strata/components/engine/<label>/<binary>, the rx9070 label for the
    primary (gfx120x), and chart literal == README literal (interface freeze,
    C01 AC3)."""
    readme = S.read(S.CONTAINER_DIR / "README.md", "C01 freezes the image interface here")
    exe = S.profile_json(_docs(), S.PROFILE_PRIMARY_FILE)["exe"]
    documented = S.engine_exe_paths(readme)
    assert documented, f"README documents no exe contract path of the form {S.ENGINE_ROOT}/<label>/<binary>"
    assert exe in documented, f"profile exe {exe!r} not among README contract paths {sorted(documented)}"
    assert "-hip-rx9070/" in exe, "primary profile exe must sit under the gfx120x (rx9070) engine root"


@helm
def test_c01_seam_serve_entry_from_cmd_is_readme_path():
    readme = S.read(S.CONTAINER_DIR / "README.md", "C01 README documents the serve entry")
    assert S.SERVE_ENTRY in readme
    assert S.SERVE_ENTRY in _primary_model(_docs())["cmd"]
