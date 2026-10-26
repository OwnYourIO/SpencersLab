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
    # (coord-routed defect G1 amendment, 2026-10-24): the loop iterates
    # (family KEY, spec DICT); reading `.get("quants")`/merging off the key
    # string AttributeError-crashed ANY families implementation. `spec` is
    # the values dict; `fam` stays the key for the ID derivation.
    for fam, spec in cfg["families"].items():
        for quant, rung in (spec.get("quants") or {}).items():
            mid = (rung or {}).get("id") or f"{fam}-{quant}"
            merged = {**(spec or {}), **(rung or {})}
            merged.pop("quants", None)
            if mid in L.CHART_RAW_CMD_IDS:
                if "cmd" not in merged:
                    offenders.append(f"{mid}: escape-hatch rung lost its raw cmd")
                continue
            if "cmd" in merged:
                offenders.append(f"{mid}: raw cmd outside the escape hatch")
            # CR5 (amendment S, shape-tolerant): a rung resolves via literal
            # hf OR shorthand composition (repo|hfRepo + tag|culture[quant]);
            # culture maps are read ONLY from chart values config.tagCultures
            # (single source; HEAD has none, so resolution = literals).
            if L.rung_effective_ref(cfg, fam, spec, quant) is None and "disabled" not in merged:
                offenders.append(f"{mid}: no resolvable hf ref and no disabled reason")
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
            if mid not in goldens["gpu"] and mid not in goldens["gpu-ai"]:
                # Round-2 review fix 1: the 16 C04-approved-new ids postdate the
                # pre-C04 goldens — no golden cmd carries their refs. Their -hf
                # coverage stays pinned by test_new_roster.
                # test_c04_1_exact_hf_ref_per_approved_id (C04_HF_REFS
                # parametrization); skipping here removes a guaranteed
                # post-CA2 KeyError without removing any assertion.
                continue
            src = "gpu" if mid in goldens["gpu"] else "gpu-ai"
            gcmd = goldens[src][mid]["cmd"]
            if L.is_echo_cmd(gcmd):  # golden echo (surviving disables): ref lives in the other golden
                other = "gpu-ai" if src == "gpu" else "gpu"
                gcmd, src = goldens[other][mid]["cmd"], other
            eff_hf = L.rung_effective_ref(cfg, fam, spec, quant)
            want_hf = L.cmd_flag_value(gcmd, "-hf")
            want_hfd = L.cmd_flag_value(gcmd, "-hfd")
            if want_hf is None:
                # (coord-routed defect G2 amendment, 2026-10-24): rana's
                # golden cmd is the raw /bin/sh -c bootstrap — shlex keeps the
                # quoted script ONE opaque token, so no standalone -hf/-hfd
                # token can exist, while P1 + CR1 make the rung chart-side
                # with real hf/draft fields. Route to the token-boundary
                # regex over the raw text (ratified defect-A machinery;
                # rightmost match = llama.cpp's effective flag, consistent
                # with cmd_flag_value). If NEITHER mechanism finds -hf, the
                # original loud assert stays.
                hfs = re.findall(r"(?:^|\s)-hf\s+(\S+)", gcmd)
                hfds = re.findall(r"(?:^|\s)-hfd\s+(\S+)", gcmd)
                want_hf = hfs[-1] if hfs else None
                want_hfd = hfds[-1] if hfds else want_hfd
            assert want_hf, f"golden {src} {mid} has no -hf token — spec premise broken"
            if eff_hf != want_hf:
                problems.append(f"{mid}: effective hf={eff_hf!r} but golden({src}) -hf={want_hf!r}")
            if want_hfd and eff.get("draft") != want_hfd:
                problems.append(f"{mid}: draft={eff.get('draft')!r} but golden({src}) -hfd={want_hfd!r}"  # draft stays full-literal (CR5)
)
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
    # Amendment I (round-2: loop ACTUALLY removed — the round-1 patch silently
    # no-oped here, the drift review caught): the per-entry `assert "hf" in m`
    # loop is SUPERSEDED, coverage moved chart-side
    # (test_c02_chart_composition_hf_refs_match_golden over config.families)
    # plus render-side (parity P2). Post-CA2 a service-block entry may be a
    # partial override without `hf` (CR1.5 merge-over-expansion) — requiring
    # it here false-reds a compliant CA2 while pinning nothing extra.
    pass


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


@helm
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
    # Round-2 review fix 4: `id:` REPLACES the derived name (it does not add a
    # second entry), and the not-enabled rung renders as an echo per CR1.4 —
    # its shape is owned by test_fam_enablement... (old clause
    # `f"{FAM}-off" not in models` was mutually unsatisfiable with it).
    assert "custom-smoke-id" in models and f"{FAM}-q8" not in models
    assert L.cmd_flag_value(models[SMOKE_RUNG_ID]["cmd"], "-hf") == "smolorg/Smoke-GGUF:Q4_K_M"


@helm
def test_fam_fields_merge_family_below_rung():
    """CR1.2: family fields merge down; rung fields win (ttl: family 0 -> rung
    300 for the custom-id rung; use/threads still inherited)."""
    models = L.all_models_of(L.configmap_data("gpu", "llama-swap-config", "config.yaml", SMOKE_OVERLAY))
    assert "custom-smoke-id" in models, "CA2 family expansion missing (id: override rung not rendered)"
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
    assert off is not None, "CA2 missing: not-enabled rung vanished instead of echoing (CR1.4 / P5)"
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
    assert SMOKE_RUNG_ID in models, "CA2 expansion missing (smoke rung not rendered)"
    m = models[SMOKE_RUNG_ID]
    assert m.get("ttl") == 77 and m.get("name") == "Smoke Q4", (
        f"CA2 CR1.5 merge-over-expansion wrong: ttl={m.get('ttl')!r} name={m.get('name')!r}"
    )
    toks = set(L.cmd_tokens(m["cmd"]))
    assert {"--tuned-override", "1"} <= toks and "smolorg/Smoke-GGUF:Q4_K_M" in toks


@helm
def test_fam_duplicate_derived_id_fails_render():
    """CR1 + DECISIONS: a duplicate rendered ID fails the RENDER (loud), not a
    silent overwrite — two smoke families deriving the same id."""
    dup = {"config": {"families": {
        "dupfam": {"enabled": True, "quants": {"x": {"hf": "a/b:Q4_K_M"}}},
        "dupfam-x": {"enabled": True, "quants": {"y": {"id": "dupfam-x", "hf": "a/b:Q4_K_M"}}},
    }}}
    rc, out = L.render_rc("gpu", dup)
    assert rc != 0, (
        "CA2 duplicate-ID guard missing: two rungs deriving 'dupfam-x' rendered fine "
        "(DECISIONS: duplicate rendered ID fails the render)\n" + out[-400:]
    )


@helm
def test_fam_key_stripped_from_rendered_output():
    """DECISIONS + CR5: values-only concepts must never reach the rendered
    llama-swap config. Extended (amendment U-1) to the CR5 schema keys on
    every model entry and the new top-level keys."""
    cfg = L.configmap_data("gpu", "llama-swap-config", "config.yaml", SMOKE_OVERLAY)
    banned_top = {"families", "filterPresets", "tagCultures"}
    assert not banned_top & set(cfg), f"values-only top-level keys leaked: {sorted(banned_top & set(cfg))}"
    leaks = [f"{mid}.{k}" for mid, m in L.all_models_of(cfg).items()
             for k in L.NEW_SCHEMA_KEYS if k in m]
    assert not leaks, f"CR5 schema keys leaked into rendered entries: {leaks[:12]}"


# ---------------------------------------------------------------------------
# CR5 synthetic final-shape tests (amendment U; §7ter method: executed against
# a fixture of CB2's prescribed schema, not just HEAD). RED at CB1 handoff for
# the right reason — HEAD's templates ignore the shorthand/vocab fields (probed
# 2026-10-24: no -hf composed, hfRepo/dispName/descBase LEAKED into entries,
# unresolvable rungs rendered silently) — and GREEN at CB2 completion.
# ---------------------------------------------------------------------------

SH_SHORTHAND = {"config": {
    "tagCultures": {"cr5-smoke": {"q4": "Q4_K_M", "q8": "Q8_0"}},
    "families": {"cr5-smoke": {
        "enabled": True,
        "hfRepo": "smolorg/Cr5-Smoke-GGUF",
        "tagCulture": "cr5-smoke",
        "dispName": "CR5 Smoke",
        "descBase": "Smoke catalog family",
        "quants": {
            "q4": {"size": "9.9 GiB", "suffix": "probe"},
            "q8": {"repo": "otherorg/Cr5-Smoke-GGUF", "tag": "Q8_0",
                   "draft": "ggml-org/Dummy-GGUF:mtp-draft-Q8_0",
                   "spec": {"type": "draft-mtp", "draft_n_max": 2}},
        },
    }},
}}


@helm
def test_cr5_shorthand_composition_render():
    """CR5 grammar outcome bars on the synthetic shorthand family: effective
    -hf composes from hfRepo+culture (and repo+tag exceptions); NAME carries
    (TAG), the ", MTP" marker derives from draft/spec presence, suffix rides
    as data; DESCRIPTION composes from descBase+TAG and interpolates the size
    datum; no schema key leaks. Awaits CB2."""
    cfg = L.configmap_data("gpu", "llama-swap-config", "config.yaml", SH_SHORTHAND)
    models = L.all_models_of(cfg)
    q4, q8 = models.get("cr5-smoke-q4"), models.get("cr5-smoke-q8")
    assert q4 and q8, "CB2 shorthand family not expanded (cr5-smoke-q4/q8 missing)"
    assert L.cmd_flag_value(q4["cmd"], "-hf") == "smolorg/Cr5-Smoke-GGUF:Q4_K_M", \
        f"culture-composed ref wrong: {L.cmd_flag_value(q4['cmd'], '-hf')!r} (CB2)"
    assert L.cmd_flag_value(q8["cmd"], "-hf") == "otherorg/Cr5-Smoke-GGUF:Q8_0", \
        f"repo/tag-exception ref wrong: {L.cmd_flag_value(q8['cmd'], '-hf')!r} (CB2)"
    assert "Q4_K_M" in (q4.get("name") or "") and "MTP" not in q4.get("name", ""), \
        f"name grammar not composed / MTP wrongly present: {q4.get('name')!r} (CB2)"
    assert "Q8_0" in (q8.get("name") or "") and "MTP" in q8.get("name", ""), \
        f"MTP auto-marker missing from draft/spec rung name: {q8.get('name')!r} (CB2)"
    assert " - probe" in (q4.get("name") or ""), f"suffix data not carried: {q4.get('name')!r} (CB2)"
    assert "Q4_K_M" in (q4.get("description") or "") and "9.9 GiB" in q4.get("description", ""), \
        f"desc grammar/size interpolation missing: {q4.get('description')!r} (CB2)"
    leaks = [f"{m}.{k}" for mid, m in models.items()
             if mid.startswith("cr5-smoke") for k in L.NEW_SCHEMA_KEYS if k in m]
    assert not leaks and "tagCultures" not in cfg, f"schema keys leaked: {leaks[:8]} (CB2 strip)"


SH_UNRESOLVABLE = {"config": {"families": {"cr5-ghost": {
    "enabled": True,
    "hfRepo": "smolorg/Ghost-GGUF",
    "quants": {"nope": {}},  # no hf, no tag, no culture, no cmd, no disabled
}}}}


@helm
def test_cr5_unresolvable_rung_fails_render():
    """CR5 loud-offender rule (G1 precedent): a rung with no resolvable ref,
    no cmd, no disabled must FAIL THE RENDER, not emit a cmd-less model.
    HEAD renders it silently (probed rc=0) -> red naming CB2."""
    rc, out = L.render_rc("gpu", SH_UNRESOLVABLE)
    assert rc != 0, (
        "CB2 fail-guard missing: unresolvable rung cr5-ghost-nope rendered with rc=0 "
        "instead of failing the render\n" + out[-300:]
    )


# ---------------------------------------------------------------------------
# CR6 re-home (CC1): the reloader guard survived the autogen retirement because
# the RELOAD mechanism is what CR6 keeps; the two-ConfigMap `match` leg is
# deleted with the second CM. Declared-scope restatement of C03-5.
# ---------------------------------------------------------------------------


@helm
@pytest.mark.parametrize("cluster", ["gpu", "gpu-ai"])
def test_cr6_reloader_guard_declared_scope(cluster):
    """The pod must roll on data change of the declared ConfigMap: either the
    stakater auto annotation (watches mounted CMs) or an explicit
    reloader.stakater.com/match naming `llama-swap-config`. Reads RENDERED
    annotations only — the CA4 lesson: values-level overlays the templates never
    see are not evidence."""
    for doc in L.render_docs(cluster):
        if doc.get("kind") == "Deployment":
            dep_ann = (doc.get("metadata") or {}).get("annotations") or {}
            pod_ann = (doc["spec"]["template"].get("metadata") or {}).get("annotations") or {}
            break
    else:
        raise AssertionError("no Deployment rendered")
    ann = {**dep_ann, **pod_ann}
    if ann.get("reloader.stakater.com/auto") == "true":
        return  # auto mode covers the mounted declared CM
    match = ann.get("reloader.stakater.com/match", "")
    # Comma-token membership, not substring (final-4 nit-2): a match naming
    # e.g. llama-swap-config-backup must NOT satisfy the guard.
    assert "llama-swap-config" in {m.strip() for m in match.split(",")}, (
        f"{cluster}: neither auto-reload nor explicit llama-swap-config match-token: {ann}"
    )
