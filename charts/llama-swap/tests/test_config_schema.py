# C02 roster-schema contract: chart/service values must carry the COMPACT
# desired-state schema (hf/draft/spec/use/flags/disabled + passthrough,
# filterPresets, escape-hatch cmd) and the templates must compose it into
# today's config surface.
#
# Everything here is RED until C02 lands — the values files today still hold
# hand-written llama-swap YAML (raw `cmd` on every model, the
# &vlWorkloadFilters anchor, no `hf:`/`disabled:`/`filterPresets` keys), and
# templates/configmap-llama-swap.yaml is a plain `toYaml .Values.config`
# passthrough, so synthetic schema entries render verbatim instead of being
# composed. File-structure tests run WITHOUT helm; the composition tests use
# the same skip gate as the render suite.

from __future__ import annotations

import pytest

import llama_swap_testlib as L

# ---------------------------------------------------------------------------
# Values-file shape (pure YAML reads — no helm needed, hard tests)
# ---------------------------------------------------------------------------


def test_c02_filterpresets_named_entry():
    """The &vlWorkloadFilters anchor becomes a named filterPresets entry
    (plan C02 schema: filterPresets.vl-workload with the two setParamsByID
    keys). Its content must equal what the 12 VL models render today."""
    cfg = L.chart_values()["config"]
    presets = cfg.get("filterPresets")
    assert isinstance(presets, dict), "config.filterPresets missing — schema not implemented"
    vl = presets.get("vl-workload")
    assert vl is not None, "filterPresets has no vl-workload entry"
    keys = set((vl.get("setParamsByID") or {}))
    assert keys == {"${MODEL_ID}:tags", "${MODEL_ID}:caption"}
    golden_filters = L.all_models_of(L.golden_config("gpu"))["qwen3-vl-4b-q4"]["filters"]
    assert vl == golden_filters, (
        "vl-workload preset content differs from the anchor it replaces:\n"
        f"preset: {vl}\ngolden: {golden_filters}"
    )


def test_c02_chart_models_are_composition_or_documented_escape_hatch():
    """Every chart model is either a schema record (hf-composition: `hf` ref,
    optional draft/spec/use/flags — never a raw cmd) or in the raw-cmd escape
    hatch set {whisper-large-v3}. Precedence disabled > cmd > hf-composition
    means a `cmd` key outside the escape set is a contract violation."""
    models = L.chart_values()["config"]["models"]
    offenders = []
    for mid, m in models.items():
        if mid in L.CHART_RAW_CMD_IDS:
            continue
        if "cmd" in m:
            offenders.append(f"{mid}: raw cmd outside the escape hatch")
        if "hf" not in m:
            offenders.append(f"{mid}: no hf ref field")
    assert not offenders, "chart values not in roster schema:\n" + "\n".join(sorted(offenders))


def test_c02_chart_composition_hf_refs_match_golden():
    """Conversion fidelity is a SOURCE check: each composition model's `hf`
    value must equal the `-hf` token pair in that model's golden cmd, and
    `draft` (where present) the `-hfd` pair — C02 converts 1:1 in golden
    order, so a wrong ref cannot hide behind the cmd renderer."""
    models = L.chart_values()["config"]["models"]
    golden_models = L.all_models_of(L.golden_config("gpu"))
    problems = []
    for mid in L.CHART_MODEL_IDS:
        if mid in L.CHART_RAW_CMD_IDS:
            continue
        m = models[mid]
        gcmd = golden_models[mid]["cmd"]
        want_hf = L.cmd_flag_value(gcmd, "-hf")
        assert want_hf, f"golden {mid} has no -hf token — spec premise broken"
        if m.get("hf") != want_hf:
            problems.append(f"{mid}: hf={m.get('hf')!r} but golden -hf={want_hf!r}")
        want_hfd = L.cmd_flag_value(gcmd, "-hfd")
        if want_hfd and m.get("draft") != want_hfd:
            problems.append(f"{mid}: draft={m.get('draft')!r} but golden -hfd={want_hfd!r}")
    assert not problems, "schema refs diverge from golden cmd tokens:\n" + "\n".join(problems)


def test_c02_vl_models_reference_filter_preset():
    """The 12 vl-workload models must reference the preset by NAME
    (`filters: vl-workload`), replacing the YAML anchor alias."""
    models = L.chart_values()["config"]["models"]
    offenders = [
        mid for mid in L.VL_WORKLOAD_IDS
        if models.get(mid, {}).get("filters") != "vl-workload"
    ]
    assert not offenders, f"VL models not referencing filterPresets entry: {offenders}"


def test_c02_gpu_block_disabled_entries_use_schema_key():
    """The 6 gpu fail-fast entries convert from hand-written echo cmds to
    `disabled: <reason>` + description; the tuned 35B-q8 override converts to
    schema fields (flags carrying --no-mmproj / -np 1 / --cache-reuse 256 /
    -ub 1024), so NO gpu-block entry keeps a raw cmd."""
    models = L.service_overlay("gpu")["config"]["models"]
    offenders = []
    for mid in L.GPU_DISABLED_IDS:
        m = models.get(mid) or {}
        if "disabled" not in m or not str(m.get("disabled")).strip():
            offenders.append(f"{mid}: missing disabled reason")
        if "cmd" in m:
            offenders.append(f"{mid}: still carries raw cmd")
    tuned = models.get("qwen3.6-35b-a3b-q8") or {}
    if "cmd" in tuned:
        offenders.append("qwen3.6-35b-a3b-q8: tuned override still a raw cmd")
    blob = str(tuned.get("flags", "")) + str(tuned.get("use", ""))
    for tok in ("--no-mmproj", "-np", "--cache-reuse", "-ub"):
        if tok not in blob:
            offenders.append(f"qwen3.6-35b-a3b-q8: tuned flag {tok} not expressed in schema fields")
    assert not offenders, "gpu service block not in roster schema:\n" + "\n".join(offenders)


def test_c02_gpuai_block_escape_hatch_is_exactly_rana():
    """qwen38-rana's multi-curl exec bootstrap (one-physical-line invariant)
    passes through as raw cmd; whisper lives in the chart. Nothing else in the
    gpu-ai block may keep a cmd, and rana must keep its single-line exec."""
    models = L.service_overlay("gpu-ai")["config"]["models"]
    raw = {mid for mid, m in models.items() if "cmd" in m}
    assert raw == L.GPUAI_RAW_CMD_IDS, (
        f"gpu-ai raw-cmd set is {sorted(raw)}, expected {sorted(L.GPUAI_RAW_CMD_IDS)}"
    )
    rana = models["qwen38-rana"]["cmd"]
    exec_lines = [ln for ln in rana.splitlines() if "exec llama-server" in ln]
    assert len(exec_lines) == 1, "rana exec line split across lines — breaks SanitizeCommand"
    assert exec_lines[0].count("-hf") == 1 and "-hfd" in exec_lines[0]
    for mid in models:
        if mid in L.GPUAI_RAW_CMD_IDS:
            continue
        m = models[mid]
        assert "hf" in m, f"gpu-ai/{mid}: neither hf ref nor escape hatch"


def test_c02_macros_matrix_hooks_stay_top_level_single_source():
    """macros/matrix/hooks keep their current top-level placement in the
    values subtrees (they are NOT moved under base.yaml - the two-file merge
    forbids matrix/hooks in both halves, DECISIONS). The schema governs
    models only; matrix/hooks may NOT appear inside any model entry."""
    chart_cfg = L.chart_values()["config"]
    assert isinstance(chart_cfg.get("macros"), dict), "chart macros must stay top-level config"
    assert isinstance(chart_cfg.get("matrix"), dict), "chart matrix must stay top-level config"
    ai_overlay = L.service_overlay("gpu-ai").get("config", {})
    assert isinstance(ai_overlay.get("matrix"), dict), "gpu-ai matrix override missing"
    assert isinstance(ai_overlay.get("hooks"), dict), "gpu-ai preload hooks missing"
    for cluster, models in (("chart", chart_cfg["models"]), ("gpu-ai", ai_overlay.get("models", {}))):
        for mid, m in models.items():
            assert "matrix" not in m and "hooks" not in m, (
                f"{cluster}/{mid}: matrix/hooks leaked into a model entry (load error in v262)"
            )


# ---------------------------------------------------------------------------
# Composition semantics (helm renders — same gate as parity file)
# ---------------------------------------------------------------------------

_ok, _reason = L.helm_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)

SMOKE = "schema-smoke"


def _require_cmd(models: dict, mid: str) -> str:
    m = models[mid]
    assert "cmd" in m, (
        f"rendered {mid} has no cmd — the ConfigMap template is still a raw "
        "toYaml passthrough; the C02 schema composition renderer is missing"
    )
    return m["cmd"]


@pytest.fixture()
def synthetic_overlay():
    """Inject composition fixtures into a fresh render. The smoke IDs are only
    present in these overlay renders, never in the parity renders."""
    models = {
        f"{SMOKE}-hf": {
            "hf": "smolorg/Smoke-GGUF:Q4_K_M",
            "draft": "smolorg/Smoke-GGUF:mtp-Smoke-Q8_0",
            "spec": {"type": "draft-mtp", "draft_n_max": 2, "draft_p_min": 0.75},
            "use": ["threads", "ctx-256k"],
            "flags": "--smoke-flag 7",
            "name": "Smoke Model",
            "ttl": 300,
        },
        f"{SMOKE}-ttl-default": {"hf": "smolorg/Smoke-GGUF:Q8_0", "use": ["threads"]},
        f"{SMOKE}-raw": {"cmd": "llama-server --smoke-raw-only 1", "ttl": 0},
        f"{SMOKE}-disabled": {
            "disabled": "provenance fixture says no",
            "cmd": "llama-server --must-be-ignored 1",
            "hf": "smolorg/Ignored-GGUF:Q0_0",
            "ttl": 0,
        },
    }
    return {"config": {"models": models}}


@helm
def test_c02_synthetic_composition_render(synthetic_overlay):
    """cmd composition = ${server-cmd} line first, then -hf, -hfd, each `use`
    macro, spec flags, then `flags` verbatim (plan C02). Compared as token
    multisets; a macro may appear as the `${name}` reference (llama-swap
    expands at load — today's golden shape) or pre-expanded, as long as the
    flag stream resolves identically."""
    cfg = L.configmap_data("gpu", "llama-swap-config", "config.yaml", synthetic_overlay)
    models = L.all_models_of(cfg)
    cmd = _require_cmd(models, f"{SMOKE}-hf")
    toks = L.cmd_tokens(cmd)
    assert {"-hf", "smolorg/Smoke-GGUF:Q4_K_M"} <= set(toks)
    assert {"-hfd", "smolorg/Smoke-GGUF:mtp-Smoke-Q8_0"} <= set(toks)
    assert {"--spec-type", "draft-mtp", "--spec-draft-n-max", "2", "--spec-draft-p-min", "0.75"} <= set(toks)
    assert {"--smoke-flag", "7"} <= set(toks)
    L.render_macro_or_literal(cmd, "threads", ("-t", "10"))
    L.render_macro_or_literal(cmd, "ctx-256k", ("--ctx-size", "262144"))
    # server-cmd first: first token of the stream is the macro reference or
    # the literal binary llama-server itself.
    first = list(toks.elements())[0]
    assert first in ("${server-cmd}", "llama-server"), f"cmd starts with {first!r}"
    m = models[f"{SMOKE}-hf"]
    assert m.get("name") == "Smoke Model" and m.get("ttl") == 300


@helm
def test_c02_synthetic_ttl_omitted_and_proxy_default(synthetic_overlay):
    """Omitted `ttl` stays omitted (inherits globalTTL), and `proxy` defaults
    to http://localhost:${PORT} when the schema entry omits it (C02 schema
    rules). The composition fixture above omits both."""
    cfg = L.configmap_data("gpu", "llama-swap-config", "config.yaml", synthetic_overlay)
    models = L.all_models_of(cfg)
    _require_cmd(models, f"{SMOKE}-ttl-default")
    m = models[f"{SMOKE}-ttl-default"]
    assert "ttl" not in m, f"ttl injected where schema omitted it: {m.get('ttl')!r}"
    assert m.get("proxy") == "http://localhost:${PORT}", f"proxy default missing: {m.get('proxy')!r}"


@helm
def test_c02_synthetic_precedence_disabled_wins(synthetic_overlay):
    """Precedence disabled > cmd > hf-composition: with all three present the
    rendered cmd is the lab's fail-fast echo shape carrying the ID and the
    reason; neither the raw cmd nor the hf composition may leak in."""
    cfg = L.configmap_data("gpu", "llama-swap-config", "config.yaml", synthetic_overlay)
    cmd = _require_cmd(L.all_models_of(cfg), f"{SMOKE}-disabled")
    assert cmd.strip().startswith('/bin/sh -c "echo ')
    assert "' >&2; exit 1" in cmd
    assert f"{SMOKE}-disabled" in cmd and "provenance fixture says no" in cmd
    leak = {"--must-be-ignored", "smolorg/Ignored-GGUF:Q0_0", "--smoke-raw-only"} & set(L.cmd_tokens(cmd))
    assert not leak, f"higher-precedence fields leaked: {sorted(leak)}"


@helm
def test_c02_synthetic_raw_cmd_passthrough_verbatim(synthetic_overlay):
    """The `cmd` escape hatch passes through untouched — including inline
    `#` comments (llama-swap SanitizeCommand strips them at load; the loader
    contract, not Helm's). Raw cmd must NOT gain macro scaffolding."""
    cfg = L.configmap_data("gpu", "llama-swap-config", "config.yaml", synthetic_overlay)
    cmd = _require_cmd(L.all_models_of(cfg), f"{SMOKE}-raw")
    assert set(L.cmd_tokens(cmd)) == {"llama-server", "--smoke-raw-only", "1"}


def test_c02_schema_smoke_absent_from_parity_renders():
    """Guard that the smoke fixtures never leak into the baseline renders the
    parity file compares against goldens (cache keys differ by overlay, this
    pins it behaviorally): a render WITHOUT the overlay must not contain them."""
    baseline = L.all_models_of(L.rendered_config("gpu"))
    assert not [mid for mid in baseline if mid.startswith(SMOKE)]
