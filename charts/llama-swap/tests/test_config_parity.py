# C02 declared-half parity contract: the NEW schema-rendered config.yaml must
# be semantically identical per cluster to the captured golden (pre-change
# render). One test per acceptance criterion of chunks/C02.md (1-5).
#
# Why several of these are green at test-write time: the goldens were captured
# from the CURRENT chart before any dev edit (the plan's timing constraint), so
# render-vs-golden is trivially equal today. They are preservation contracts —
# they turn red only when C02/C03/C04 change a consumer-visible byte of the
# config surface. The C02 work that is NOT yet done (the schema itself) is
# pinned red by test_config_schema.py; per-test expected states are recorded
# in TEST_SPEC.md.
#
# Skipped when the helm binary or the chart's app-template dependency is
# missing (same gate as test_render.py; CI installs both).

from __future__ import annotations

import re
import subprocess

import pytest

import llama_swap_testlib as L

_ok, _reason = L.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_reason)

CLUSTERS = ["gpu", "gpu-ai"]

# Consumer-critical alias surface (C02 acceptance 3): clients configured before
# quant-suffixed IDs (OpenWebUI/Pictaria/Immich/HA routing) keep resolving.
# value = the cluster whose render must carry the alias.
BACKCOMPAT_ALIASES = {
    "qwen3-vl-4b": "gpu",           # chart models -> every cluster
    "qwen3-vl-8b": "gpu",
    "qwen3-vl-30b-a3b": "gpu",
    "qwen3.8": "gpu-ai",            # gpu-ai-only (qwen38-orca)
    "local/qwen3.8-27b": "gpu-ai",
}

# Fail-fast disabled shape as rendered today (C02 acceptance 4, byte-exact):
# a single /bin/sh -c invocation whose script is one echo-to-stderr + exit 1.
_FAILFAST = re.compile(r'^/bin/sh -c "echo \'.*\' >&2; exit 1"\n?$')


def _first_diff_key(a, b, prefix=""):
    if a == b:
        return None
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b), key=str):
            if k not in a:
                return f"{prefix}{k} (added)"
            if k not in b:
                return f"{prefix}{k} (removed)"
            d = _first_diff_key(a[k], b[k], f"{prefix}{k}.")
            if d:
                return d
        return None
    return prefix or "<value>"


# --- criterion 1: lint + the four renders pass ------------------------------


def test_c02_1_helm_lint_passes():
    out = subprocess.run(["helm", "lint", str(L.CHART_DIR)], capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, out.stdout + out.stderr


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_1_cluster_render_produces_configmap(cluster):
    # render_docs() raises AssertionError on helm rc != 0; the CM lookup proves
    # the documented per-cluster extract-and-render lands a llama-swap config.
    cfg = L.rendered_config(cluster)
    assert cfg, f"{cluster}: rendered config.yaml is empty"


# --- criterion 2: normalized parity ------------------------------------------


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_2_model_id_sets_equal(cluster):
    """P1 (REPLAN CR2, amendment G/H 2026-10-24): every cluster render carries
    EXACTLY the frozen 58-ID catalog — the superset pattern means gpu also
    renders the gpu-ai-local rungs as echoes and both drop the ruled 13.
    Red at CA1 handoff: CA2 (catalog conversion) + CA3 (removals) not landed."""
    fresh = set(L.all_models_of(L.rendered_config(cluster)))
    assert fresh == set(L.CATALOG_IDS), (
        f"{cluster}: rendered ID set diverges from the frozen CATALOG "
        f"(missing {sorted(set(L.CATALOG_IDS) - fresh)}, "
        f"unexpected {sorted(fresh - set(L.CATALOG_IDS))}) — awaiting CA2/CA3"
    )


def test_repl_tables_match_frozen_decisions():
    """Acceptance-5 support: the frozen tables must equal the arithmetic the
    user ruled (58 = golden-union - removed + C04-approved-new; gpu partition
    34+24). Pure table audit against the byte-untouched goldens — GREEN at
    handoff by design; it fails only if a table drifts from the rulings."""
    g = set(L.all_models_of(L.golden_config("gpu")))
    a = set(L.all_models_of(L.golden_config("gpu-ai")))
    c04_new = set(L.C04_NEW_IDS["gpu-ai"]) - set(L.C04_LADDER_35B_IDS) | set(L.C04_LADDER_35B_IDS)
    derived = (g | a | c04_new) - set(L.REMOVED_IDS)
    assert derived == set(L.CATALOG_IDS), f"CATALOG drift: {derived ^ set(L.CATALOG_IDS)}"
    assert len(L.REMOVED_IDS) == 13
    assert set(L.REMOVED_IDS) <= (g | a), "a REMOVED id never existed in the goldens"
    assert len(L.GPU_ENABLED_IDS) == 34 and len(L.GPU_ECHO_IDS) == 24
    assert set(L.ENABLEMENT["gpu-ai"]["enabled"]) == set(L.CATALOG_IDS)
    assert not L.ENABLEMENT["gpu-ai"]["echo"]
    assert set(L.GPUAI_LOCAL_CATALOG_IDS) <= set(L.GPU_ECHO_IDS), "gpu-ai-local rungs are gpu echoes (P5)"
    assert set(L.GPU_DISABLED_IDS) <= set(L.GPU_ECHO_IDS), "legacy golden echoes stay echoed on gpu"
    # legacy byte-pinned echoes: the 3 survivors are golden echoes today...
    for mid in L.GPU_DISABLED_IDS:
        assert L.is_echo_cmd(L.all_models_of(L.golden_config("gpu"))[mid]["cmd"])
    # ...and exactly the 3 pre-replan golden echoes that survive the ruling.
    assert set(L.GPU_DISABLED_IDS_PRE_REPLAN) - set(L.REMOVED_IDS) == set(L.GPU_DISABLED_IDS)


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_P4_removed_ids_absent_in_any_form(cluster):
    """P4 (CR3 frozen 13): absent from models, from matrix.vars values, from
    preload — 'removed' means not routable under any reference (dangling
    matrix vars are a v262 hard load error, closure test re-pins consistency).
    Red at CA1 handoff: names CA3 scope."""
    cfg = L.rendered_config(cluster)
    ids = set(L.all_models_of(cfg))
    hit = ids & set(L.REMOVED_IDS)
    varhit = {k: v for k, v in ((cfg.get("matrix") or {}).get("vars") or {}).items() if v in L.REMOVED_IDS}
    prehit = set((((cfg.get("hooks") or {}).get("on_startup") or {}).get("preload") or [])) & set(L.REMOVED_IDS)
    assert not hit and not varhit and not prehit, (
        f"{cluster}: REMOVED ids still referenced — models {sorted(hit)}, "
        f"matrix vars {varhit}, preload {sorted(prehit)} — awaiting CA3"
    )


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_P5_offcluster_catalog_ids_echo_shaped(cluster):
    """P5 (CR2): catalog IDs that postdate the golden render as fail-fast
    ECHOES on clusters that don't enable them (shape + id-prefixed message;
    the default message text is NOT golden-pinned), and as live cmds where
    enabled. The CA1 isolation flip: absent -> present-as-echo.
    Red at CA1 handoff: names CA2 scope (gpu side)."""
    golden = set(L.all_models_of(L.golden_config(cluster)))
    fresh = L.all_models_of(L.rendered_config(cluster))
    enabled = set(L.ENABLEMENT[cluster]["enabled"])
    for mid in sorted(set(L.CATALOG_IDS) - golden):
        assert mid in fresh, f"{cluster}: catalog id {mid} not rendered at all (P5: echoes must be present; awaiting CA2)"
        echo = L.is_echo_cmd(fresh[mid]["cmd"])
        if mid in enabled:
            assert not echo, f"{cluster}/{mid}: ENABLED rung rendered as echo — enablement wrong"
        else:
            assert echo and mid in fresh[mid]["cmd"], (
                f"{cluster}/{mid}: off-cluster catalog rung must be id-prefixed fail-fast echo"
            )


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_2_cmd_flag_multisets_parity(cluster):
    """cmd equality = shlex token MULTISET per model (plan risks: normalized-
    token equality, not byte equality — the schema re-wraps lines and may
    reorder segments; llama.cpp is rightmost-wins so order is not contractual)."""
    golden = L.model_tokens(L.all_models_of(L.golden_config(cluster)))
    fresh = L.model_tokens(L.all_models_of(L.rendered_config(cluster)))
    diffs = []
    # P2: surviving (not REMOVED) golden models keep EXACT token-multiset
    # equality (amendment H: the bar itself is unchanged — REMOVED ids leave
    # the loop because P1/P4 remove them from the render, not because the
    # equality was loosened).
    for mid in sorted(set(golden) & set(fresh) - set(L.REMOVED_IDS)):
        g, f = golden[mid]["cmd"], fresh[mid]["cmd"]
        if g != f:
            missing = list((g - f).elements())
            extra = list((f - g).elements())
            diffs.append(
                f"model {mid!r}: golden-only tokens {missing[:12]}, render-only tokens {extra[:12]}"
            )
    assert not diffs, f"{cluster}: cmd token multisets diverge:\n" + "\n".join(diffs)


DISPLAY_FIELDS = ("name", "description")


def _strip_display(rest: dict) -> dict:
    return {k: v for k, v in rest.items() if k not in DISPLAY_FIELDS}


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_2_per_model_fields_deep_equal(cluster):
    """ttl/proxy/aliases/capabilities/checkEndpoint/filters/env — every non-cmd
    model key EXCEPT display text — deep-equal vs golden.

    CR5 display excision (amendment P, user-ratified 2026-10-24: "RELAX P2 for
    display fields"): name/description leave this comparison so the template
    grammar may recompose picker text. This is the amendment's ONLY assertion-
    scope removal and it is COMPENSATED, not bare: presence on all 58 rungs
    (test_cr5_display_presence), grammar shape (test_cr5_display_name_grammar /
    test_cr5_ladder_descriptions_mention_tag), and a user-reviewed per-id
    before/after display table gating the PR (plan CR5 bar 2). IDs, aliases,
    cmd tokens (P2 above — untouched), echo byte-strings (P3), P4/P5/P6 stay
    UNBENTED golden pins."""
    golden = L.model_tokens(L.all_models_of(L.golden_config(cluster)))
    fresh = L.model_tokens(L.all_models_of(L.rendered_config(cluster)))
    problems = []
    for mid in sorted(set(golden) & set(fresh) - set(L.REMOVED_IDS)):  # P2 fields half
        g_rest, f_rest = _strip_display(golden[mid]["rest"]), _strip_display(fresh[mid]["rest"])
        if g_rest != f_rest:
            problems.append(f"{mid}: {_first_diff_key(g_rest, f_rest)}")
    assert not problems, f"{cluster}: per-model field divergence:\n" + "\n".join(problems)


def _ws_norm(macros: dict) -> dict:
    """Macro equality up to intra-line whitespace: toYaml of a rewritten values
    file may re-indent continuation lines without changing the flag stream the
    macro expands to (llama-swap splits on whitespace)."""
    return {k: re.sub(r"[ \t]+", " ", (v or "").strip()) for k, v in (macros or {}).items()}


def _assert_matrix_preserved(cluster: str, g: dict, f: dict) -> None:
    """Golden-matrix SURVIVAL expressed as additive preservation
    (coord-routed defect E amendment, 2026-10-23): every golden var must map
    to the same model ID and every golden set must keep its full membership.
    Whole-matrix equality was unsatisfiable from C04 onward BY DESIGN —
    chunks/C04.md tasks require new vars and main/solo alternation additions;
    exactness of the NEW memberships is pinned by test_new_roster's placement
    tests (division of labor preserved)."""
    gvars = (g.get("matrix") or {}).get("vars") or {}
    fvars = (f.get("matrix") or {}).get("vars") or {}
    # P6 (amendment H): additive preservation MODULO REMOVED — CA3 legitimately
    # drops coder/kat/qwen3-text vars and set tokens (dangling vars would be a
    # v262 load error); every OTHER golden var must map unchanged.
    changed = {k: (v, fvars.get(k)) for k, v in gvars.items()
               if v not in L.REMOVED_IDS and fvars.get(k) != v}
    assert not changed, f"{cluster}: surviving golden matrix vars changed/removed: {changed}"
    gsets = (g.get("matrix") or {}).get("sets") or {}
    fsets = (f.get("matrix") or {}).get("sets") or {}
    assert set(gsets) <= set(fsets), (
        f"{cluster}: golden matrix sets vanished: {sorted(set(gsets) - set(fsets))}"
    )
    for name in gsets:
        lost = L.matrix_member_ids(g, name) - L.matrix_member_ids(f, name) - set(L.REMOVED_IDS)
        assert not lost, f"{cluster}: matrix set {name} dropped surviving golden members: {sorted(lost)}"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_2_config_layer_macros_matrix_hooks_scalars(cluster):
    g = L.golden_config(cluster)
    f = L.rendered_config(cluster)
    assert _ws_norm(g.get("macros")) == _ws_norm(f.get("macros")), (
        f"{cluster}: macros diverge (whitespace-normalized)"
    )
    _assert_matrix_preserved(cluster, g, f)
    assert g.get("hooks") == f.get("hooks"), f"{cluster}: hooks diverged"
    skip = {"models", "macros", "matrix", "hooks"}
    g_scalars = {k: v for k, v in g.items() if k not in skip}
    f_scalars = {k: v for k, v in f.items() if k not in skip}
    assert g_scalars == f_scalars, (
        f"{cluster}: top-level config keys diverged: {_first_diff_key(g_scalars, f_scalars)}"
    )


# --- criterion 3: consumer-critical surface ----------------------------------


def test_c02_3_golden_baselines_match_plan_inventory():
    """The captured goldens themselves must match the plan's inventory:
    gpu = chart 40 IDs; gpu-ai = the 40 + its gpu-ai-local block keys.
    (Chunk text says '16 local'; the merged service block holds 20 keys of
    which 5 override chart IDs -> 15 net-local. TEST_SPEC records the count;
    the golden is ground truth for what existed pre-change.)"""
    gpu_ids = set(L.all_models_of(L.golden_config("gpu")))
    ai_ids = set(L.all_models_of(L.golden_config("gpu-ai")))
    assert gpu_ids == set(L.CHART_MODEL_IDS), (
        f"golden gpu set != chart inventory: +{sorted(ai_ids - gpu_ids)} -{sorted(gpu_ids - ai_ids)}"
    )
    assert len(gpu_ids) == 40
    assert ai_ids == gpu_ids | set(L.GPUAI_LOCAL_IDS)
    assert len(ai_ids) == 55


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_3_ids_survive_in_fresh_render(cluster):
    """Survival half of the P1/P4 pair (amendment H): every golden ID except
    the ruled REMOVED set must still be rendered on both clusters."""
    fresh = set(L.all_models_of(L.rendered_config(cluster)))
    golden = set(L.all_models_of(L.golden_config(cluster))) - set(L.REMOVED_IDS)
    assert golden <= fresh, f"{cluster}: surviving golden IDs dropped vs golden: {sorted(golden - fresh)}"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_3_consumer_aliases_survive(cluster):
    fresh = L.model_tokens(L.all_models_of(L.rendered_config(cluster)))
    alias_index = {}
    for mid, m in fresh.items():
        for a in m["rest"].get("aliases") or []:
            alias_index[a] = mid
    for alias, owner in BACKCOMPAT_ALIASES.items():
        # chart-owned aliases exist on every cluster; gpu-ai-owned only there.
        clusters_to_check = CLUSTERS if owner == "gpu" else [owner]
        if cluster not in clusters_to_check:
            continue
        assert alias in alias_index, f"{cluster}: consumer alias {alias!r} no longer registered"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_3_vl_workload_setparams_by_id_keys(cluster):
    """:tags/:caption setParamsByID keys (auto-aliased by llama-swap, verified
    upstream in load.go) intact on all 12 vl-workload models. After C02 they
    must resolve from the named `filterPresets` entry to the SAME final YAML
    (today they come from the &vlWorkloadFilters anchor)."""
    fresh = L.model_tokens(L.all_models_of(L.rendered_config(cluster)))
    expected_keys = {"${MODEL_ID}:tags", "${MODEL_ID}:caption"}
    for mid in L.VL_WORKLOAD_IDS:
        keys = set((fresh[mid]["rest"].get("filters") or {}).get("setParamsByID") or {})
        assert keys == expected_keys, f"{cluster}/{mid}: setParamsByID keys are {sorted(keys)}"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_3_matrix_referential_closure(cluster):
    """v262 matrix.go:71 — matrix.vars referencing a missing model is a LOAD
    error; DECISIONS adopts closure as a standing invariant (C02 acceptance 3
    and C04 acceptance 3)."""
    L.assert_matrix_closure(L.rendered_config(cluster), cluster)


# --- criterion 4: gpu fail-fast disabled entries ------------------------------


def test_c02_4_gpu_disabled_entries_byte_identical_echo():
    """P3: the surviving DISABLED cmd strings (3 under ruling B — the kat
    trio left with REMOVED_IDS) render byte-identical to the golden echoes:
    the echo body is the operator-facing reason contract (C02 acceptance 4)."""
    golden = L.all_models_of(L.golden_config("gpu"))
    fresh = L.all_models_of(L.rendered_config("gpu"))
    for mid in L.GPU_DISABLED_IDS:
        g, f = golden[mid]["cmd"], fresh[mid]["cmd"]
        assert _FAILFAST.match(g.strip()), f"golden {mid} is not fail-fast shaped — fixture broken"
        assert f == g, (
            f"gpu/{mid}: disabled cmd drifted from golden (echo strings must be byte-identical):\n"
            f"golden: {g!r}\nrender: {f!r}"
        )


# --- criterion 5: sentinel hygiene --------------------------------------------


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_5_no_override_sentinel_in_rendered_config(cluster):
    """bitwardenIds/hf-token wiring lives OUTSIDE the config ConfigMap; no
    OVERRIDE_* sentinel may ever reach the rendered llama-swap YAML."""
    cfg = L.configmap_data(cluster, "llama-swap-config", "config.yaml")
    import json
    assert "OVERRIDE_VIA" not in json.dumps(cfg), f"{cluster}: sentinel leaked into llama-swap-config"


# ---------------------------------------------------------------------------
# CR5 compensating display contract (CB1; replaces the golden display pin —
# see test_c02_2_per_model_fields_deep_equal provenance). GREEN at CB1 handoff
# against HEAD's explicit text AND required green post-CB2 under derivation:
# they are the replacement bars, never CB2-named reds.
# ---------------------------------------------------------------------------


def _models_layer_display_overrides(cluster: str) -> set[str]:
    om = L.service_overlay(cluster).get("config", {}).get("models", {}) or {}
    return {mid for mid, m in om.items() if isinstance(m, dict)
            and ("name" in m or "description" in m)}


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_cr5_display_presence(cluster):
    """Every catalog id on every cluster render carries a NON-EMPTY name AND
    description — red if CB2 deletes display text without composing it."""
    fresh = L.all_models_of(L.rendered_config(cluster))
    gaps = [f"{mid} ({k})" for mid in L.CATALOG_IDS for k in DISPLAY_FIELDS
            if not str(fresh[mid].get(k) or "").strip()]
    assert not gaps, f"{cluster}: display text missing on {gaps}"


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_cr5_display_name_grammar(cluster):
    """NAME shape bar (outcome-level grammar; exact text is the user's table):
    every non-exempt id with an effective -hf ref carries "(...TAG...)" in its
    name. Exempt: raw-cmd escape ids and models-layer display overrides (their
    explicit text is data, never grammar). Echo renders with no -hf ref are
    skipped here (P5 owns their shape; presence above covers their text)."""
    fresh = L.all_models_of(L.rendered_config(cluster))
    exempt = L.CHART_RAW_CMD_IDS | L.GPUAI_RAW_CMD_IDS | _models_layer_display_overrides(cluster)
    problems = []
    for mid in L.CATALOG_IDS:
        if mid in exempt:
            continue
        tag = L.cmd_effective_tag(fresh[mid]["cmd"])
        if not tag:
            continue
        name = fresh[mid].get("name") or ""
        parens = re.findall(r"\(([^)]*)\)", name)
        if not any(tag in p for p in parens):
            problems.append(f"{mid}: name {name!r} lacks ({tag}...) in parens")
    assert not problems, f"{cluster}: name grammar violations:\n" + "\n".join(problems)


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_cr5_ladder_descriptions_mention_tag(cluster):
    """DESC obligation limited to LADDER rungs (quant key in LADDER_QUANT_KEYS,
    effective TAG in the culture-tag space) on families whose description the
    grammar honestly carries; prose-exempt families (DESC_PROSE_EXEMPT_FAMILIES
    — gated-repo caveats etc.) and models-layer display overrides skip the
    TAG-mention check (their desc is data reviewed via the display table).
    Both-states green: HEAD's C04-era ladders already mention their TAG; the
    CB2 grammar `{descBase}, {TAG} quant` guarantees it by construction."""
    fresh = L.all_models_of(L.rendered_config(cluster))
    fam_idx = L.id_family_index(L.chart_values()["config"])
    exempt_ids = _models_layer_display_overrides(cluster)
    problems = []
    for mid, (fam, quant) in sorted(fam_idx.items()):
        if mid not in set(L.CATALOG_IDS) or mid not in fresh:
            continue
        if (quant not in L.LADDER_QUANT_KEYS or fam in L.DESC_PROSE_EXEMPT_FAMILIES
                or mid in exempt_ids or mid in L.CHART_RAW_CMD_IDS | L.GPUAI_RAW_CMD_IDS):
            continue
        tag = L.cmd_effective_tag(fresh[mid]["cmd"])
        if not tag:
            continue
        if L.is_echo_cmd(fresh[mid]["cmd"]):
            continue
        if tag not in (fresh[mid].get("description") or ""):
            problems.append(f"{mid} ({fam}/{quant}): desc lacks TAG {tag!r}: "
                            f"{(fresh[mid].get('description') or '')[:80]!r}")
    assert not problems, f"{cluster}: ladder desc-TAG violations:\n" + "\n".join(problems)
