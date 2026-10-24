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
#
# REPLAN rebase (amendment I, 2026-10-24): the ladder DATA moves chart-side
# into `config.families` (CR1), so the value-shape tests read families;
# `config.models` remains the per-ID override/escape-hatch layer (merge-over-
# expansion, CR1.5). Family-contract render tests (derivation, id:, merge
# layering, enablement flips, duplicate-ID fail, override layering) are NEW
# and name CA2 — none of that exists at HEAD. The per-ID composition/
# precedence/ttl-proxy render bars are UNCHANGED: the escape-hatch + override
# semantics they pin survive the rebase verbatim.

from __future__ import annotations

import re

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


def derived_family_ids(chart_cfg: dict) -> set[str]:
    """The CR1.1 derivation rule applied to chart values:
    id = rung.id | f"<family>-<quant>"."""
    out = set()
    for fam, spec in (chart_cfg.get("families") or {}).items():
        for quant, rung in (spec.get("quants") or {}).items():
            out.add((rung or {}).get("id") or f"{fam}-{quant}")
    return out


def test_c02_chart_models_are_composition_or_documented_escape_hatch():
    """Families version (amendment I; old: chart config.models audit): the
    chart catalog must carry ALL 58 IDs as family rungs, each rung (or its
    family) supplying schema fields — raw cmd only for the documented
    escape hatch {whisper-large-v3}. Red at handoff: CA2 has not converted
    chart values to config.families."""
    cfg = L.chart_values()["config"]
    assert cfg.get("families"), "config.families missing — CA2 catalog conversion not landed"
    assert derived_family_ids(cfg) == set(L.CATALOG_IDS), (
        f"derived catalog diverges: +{sorted(derived_family_ids(cfg) - set(L.CATALOG_IDS))} "
        f"-{sorted(set(L.CATALOG_IDS) - derived_family_ids(cfg))}"
    )
    offenders = []
    for fam, spec in cfg["families"].items():
        fam = fam or {}
        for quant, rung in (fam.get("quants") or {}).items():
            mid = (rung or {}).get("id") or f"{fam and ''}{fam}-{quant}"
            merged = {**(fam or {}), **(rung or {})}
            merged.pop("quants", None)
            if mid in L.CHART_RAW_CMD_IDS:
                if "cmd" not in merged:
                    offenders.append(f"{mid}: escape-hatch rung lost its raw cmd")
                continue
            if "cmd" in merged:
                offenders.append(f"{mid}: raw cmd outside the escape hatch")
            if "hf" not in merged and "disabled" not in merged:
                offenders.append(f"{mid}: no hf ref and no disabled reason")
    # the per-ID override layer may add schema records (gpu disabled: overrides
    # etc.) but must never re-introduce the ladder (ids are family-owned now)
    for mid, m in (cfg.get("models") or {}).items():
        if mid in L.CHART_RAW_CMD_IDS or not isinstance(m, dict):
            continue
        if "cmd" in m and mid not in L.CHART_RAW_CMD_IDS and "hf" not in m \
           and mid not in derived_family_ids(cfg):
            offenders.append(f"models.{mid}: raw cmd for a non-catalog, non-escape id")
    assert not offenders, "chart families not in roster schema:\n" + "\n".join(sorted(offenders))


def test_c02_chart_composition_hf_refs_match_golden():
    """Conversion fidelity is a SOURCE check (amendment I: source moved from
    flat config.models to config.families rungs; the BAR is unchanged): each
    live catalog rung's effective `hf` equals the `-hf` token in that model's
    golden cmd, routed by where the golden render still carries a live cmd
    (B/D pattern; REMOVED ids skipped — absent from the future catalog)."""
    cfg = L.chart_values()["config"]
    assert cfg.get("families"), "config.families missing — CA2 not landed"
    goldens = {"gpu": L.all_models_of(L.golden_config("gpu")),
               "gpu-ai": L.all_models_of(L.golden_config("gpu-ai"))}
    problems = []
    for fam, spec in cfg["families"].items():
        for quant, rung in (spec.get("quants") or {}).items():
            mid = (rung or {}).get("id") or f"{fam}-{quant}"
            if mid in L.CHART_RAW_CMD_IDS or mid in L.REMOVED_IDS:
                continue
            eff = {**(spec or {}), **(rung or {})}
            eff.pop("quants", None)
            src = "gpu" if mid in goldens["gpu"] else "gpu-ai"
            gcmd = goldens[src][mid]["cmd"]
            if L.is_echo_cmd(gcmd):  # golden echo (surviving disables): ref lives in the other golden
                other = "gpu-ai" if src == "gpu" else "gpu"
                gcmd, src = goldens[other][mid]["cmd"], other
            want_hf = L.cmd_flag_value(gcmd, "-hf")
            assert want_hf, f"golden {src} {mid} has no -hf token — spec premise broken"
            if eff.get("hf") != want_hf:
                problems.append(f"{mid}: hf={eff.get('hf')!r} but golden({src}) -hf={want_hf!r}")
            want_hfd = L.cmd_flag_value(gcmd, "-hfd")
            if want_hfd and eff.get("draft") != want_hfd:
                problems.append(f"{mid}: draft={eff.get('draft')!r} but golden({src}) -hfd={want_hfd!r}")
    assert not problems, "family refs diverge from golden cmd tokens:\n" + "\n".join(problems)


def test_c02_vl_models_reference_filter_preset():
    """The 12 vl-workload rungs must reference the preset by NAME
    (`filters: vl-workload`, family- or rung-level; amendment I re-points the
    read from config.models to config.families)."""
    cfg = L.chart_values()["config"]
    assert cfg.get("families"), "config.families missing — CA2 not landed"
    eff = {}
    for fam, spec in cfg["families"].items():
        for quant, rung in (spec.get("quants") or {}).items():
            mid = (rung or {}).get("id") or f"{fam}-{quant}"
            merged = {**(spec or {}), **(rung or {})}
            merged.pop("quants", None)
            eff[mid] = merged
    offenders = [
        mid for mid in L.VL_WORKLOAD_IDS
        if (eff.get(mid) or {}).get("filters") != "vl-workload"
    ]
    assert not offenders, f"VL rungs not referencing filterPresets entry: {offenders}"


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
    # Count WHITESPACE-DELIMITED tokens, not "-hf" substrings: the golden
    # (byte-pinned by the parity contract) legitimately carries "-hf" inside
    # the "-hfd" draft flag as well — substring counting made this assertion
    # unsatisfiable by any golden-preserving implementation (coord-routed
    # defect A amendment, 2026-10-23). Intent: one PRIMARY download (-hf)
    # plus one draft (-hfd).
    assert len(re.findall(r"(?:^|\s)-hf(?=\s)", exec_lines[0])) == 1, "rana: expected exactly one -hf primary"
    assert len(re.findall(r"(?:^|\s)-hfd(?=\s)", exec_lines[0])) == 1, "rana: expected exactly one -hfd draft"
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
    sources = [("chart-models", chart_cfg.get("models") or {}),
               ("gpu-ai-models", ai_overlay.get("models") or {}),
               ("chart-families", chart_cfg.get("families") or {})]
    for cluster, models in sources:
        for mid, m in models.items():
            assert "matrix" not in m and "hooks" not in m, (
                f"{cluster}/{mid}: matrix/hooks leaked into an entry (load error in v262)"
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


# ---------------------------------------------------------------------------
# Family-contract render tests (REPLAN CR1; amendment I). RED at CA1 handoff:
# HEAD's templates have no expansion step, so overlaid families are ignored
# (smoke IDs never appear) and duplicate derived IDs render fine instead of
# failing. All name CA2.
# ---------------------------------------------------------------------------

FAM = "smokefam"
SMOKE_RUNG_ID = f"{FAM}-q4"
SMOKE_OVERLAY = {"config": {"families": {FAM: {
    "enabled": True,
    "ttl": 0,
    "use": ["threads"],
    "quants": {
        "q4": {"hf": "smolorg/Smoke-GGUF:Q4_K_M", "name": "Smoke Q4"},
        "q8": {"hf": "smolorg/Smoke-GGUF:Q8_0", "id": "custom-smoke-id", "ttl": 300},
        "off": {"hf": "smolorg/Smoke-GGUF:BF16", "enabled": False},
    },
}}}}


@helm
def test_fam_derivation_and_id_override():
    """CR1.1: rendered ID = rung.id | <family>-<quant>."""
    models = L.all_models_of(L.configmap_data("gpu", "llama-swap-config", "config.yaml", SMOKE_OVERLAY))
    assert SMOKE_RUNG_ID in models, f"derived id {SMOKE_RUNG_ID!r} not rendered — CA2 expansion missing"
    assert "custom-smoke-id" in models and f"{FAM}-off" not in models
    assert L.cmd_flag_value(models[SMOKE_RUNG_ID]["cmd"], "-hf") == "smolorg/Smoke-GGUF:Q4_K_M"


@helm
def test_fam_fields_merge_family_below_rung():
    """CR1.2: family fields merge down; rung fields win (ttl: family 0 -> rung
    300 for the custom-id rung; use/threads still inherited)."""
    models = L.all_models_of(L.configmap_data("gpu", "llama-swap-config", "config.yaml", SMOKE_OVERLAY))
    rung = models["custom-smoke-id"]
    assert rung.get("ttl") == 300, f"rung ttl override lost to family merge: {rung.get('ttl')!r}"
    assert models[SMOKE_RUNG_ID].get("ttl") == 0, "family ttl did not merge down"
    L.render_macro_or_literal(rung["cmd"], "threads", ("-t", "10"))
    L.render_macro_or_literal(models[SMOKE_RUNG_ID]["cmd"], "threads", ("-t", "10"))


@helm
def test_fam_enablement_and_disabled_beats_enabled():
    """CR1.3: not-enabled rung -> deviation-1 echo with the DEFAULT 'not
    enabled' message (message text not pinned beyond that); a `disabled:`
    beats enablement. The `off` rung (enabled: false at rung level) must echo
    even though family.enabled is true; a models.<id>.disabled override on an
    enabled rung also echoes with its own message."""
    overlay = {"config": {"models": {SMOKE_RUNG_ID: {"disabled": "smoke ruled out"}}}}
    merged = {**SMOKE_OVERLAY}
    merged["config"] = {**SMOKE_OVERLAY["config"], **overlay["config"]}
    models = L.all_models_of(L.configmap_data("gpu", "llama-swap-config", "config.yaml", merged))
    off = models.get(f"{FAM}-off")
    assert off is not None, "not-enabled rung vanished instead of echoing (P5 contract)"
    assert L.is_echo_cmd(off["cmd"]) and f"{FAM}-off" in off["cmd"] and "not enabled" in off["cmd"], off["cmd"]
    dis = models[SMOKE_RUNG_ID]
    assert L.is_echo_cmd(dis["cmd"]) and "smoke ruled out" in dis["cmd"], (
        f"disabled overrode... wrong way: {dis['cmd']!r}"
    )
    assert "smolorg/Smoke-GGUF:Q4_K_M" not in dis["cmd"], "disabled rung still composed its hf cmd"


@helm
def test_fam_models_merge_over_expansion():
    """CR1.5: raw config.models.<id> deep-merges OVER the expansion — tuned
    overrides (ttl here, flags like gpu's regimes) win per-field while family-
    sourced fields (hf, name) remain."""
    overlay = {"config": {
        "families": SMOKE_OVERLAY["config"]["families"],
        "models": {SMOKE_RUNG_ID: {"ttl": 77, "flags": "--tuned-override 1"}},
    }}
    models = L.all_models_of(L.configmap_data("gpu", "llama-swap-config", "config.yaml", overlay))
    m = models[SMOKE_RUNG_ID]
    assert m.get("ttl") == 77 and m.get("name") == "Smoke Q4"
    toks = set(L.cmd_tokens(m["cmd"]))
    assert {"--tuned-override", "1"} <= toks and "smolorg/Smoke-GGUF:Q4_K_M" in toks


@helm
def test_fam_duplicate_derived_id_fails_render():
    """CR1 + DECISIONS: a duplicate rendered ID fails the RENDER (loud), not a
    silent overwrite — two smoke families deriving the same id."""
    dup = {"config": {"families": {
        "dupfam": {"enabled": True, "quants": {"x": {"hf": "a/b:Q4_K_M"}}},
        "dupfam-x": {"enabled": True, "quants": {"": {"id": "dupfam-x", "hf": "a/b:Q4_K_M"}}},
    }}}
    with pytest.raises(AssertionError, match="helm template failed|duplicate"):
        L.configmap_data("gpu", "llama-swap-config", "config.yaml", dup)


@helm
def test_fam_key_stripped_from_rendered_output():
    """DECISIONS: `families` is a chart-values concept (like filterPresets) —
    it must not leak into the rendered llama-swap config."""
    cfg = L.configmap_data("gpu", "llama-swap-config", "config.yaml", SMOKE_OVERLAY)
    assert "families" not in cfg, "families key leaked into rendered config (CA2)"
