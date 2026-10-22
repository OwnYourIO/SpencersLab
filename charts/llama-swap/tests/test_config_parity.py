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
    """Golden IDs must all survive; additions only from the C04 approved table
    (the plan's 'equal EXACTLY' holds at C02 time because no addition exists
    yet; the bounded superset keeps this same immutable test valid through
    C03/C04, which add models on purpose — tests are immutable downstream)."""
    golden = L.all_models_of(L.golden_config(cluster))
    fresh = L.all_models_of(L.rendered_config(cluster))
    removed = set(golden) - set(fresh)
    added = set(fresh) - set(golden)
    allowed = set(L.C04_NEW_IDS[cluster])
    assert not removed, f"{cluster}: model IDs dropped vs golden: {sorted(removed)}"
    assert added <= allowed, (
        f"{cluster}: model IDs added outside the approved C04 table: {sorted(added - allowed)}"
    )


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_2_cmd_flag_multisets_parity(cluster):
    """cmd equality = shlex token MULTISET per model (plan risks: normalized-
    token equality, not byte equality — the schema re-wraps lines and may
    reorder segments; llama.cpp is rightmost-wins so order is not contractual)."""
    golden = L.model_tokens(L.all_models_of(L.golden_config(cluster)))
    fresh = L.model_tokens(L.all_models_of(L.rendered_config(cluster)))
    diffs = []
    for mid in sorted(set(golden) & set(fresh)):
        g, f = golden[mid]["cmd"], fresh[mid]["cmd"]
        if g != f:
            missing = list((g - f).elements())
            extra = list((f - g).elements())
            diffs.append(
                f"model {mid!r}: golden-only tokens {missing[:12]}, render-only tokens {extra[:12]}"
            )
    assert not diffs, f"{cluster}: cmd token multisets diverge:\n" + "\n".join(diffs)


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_2_per_model_fields_deep_equal(cluster):
    """name/description/ttl/proxy/aliases/capabilities/checkEndpoint/filters/env
    — every non-cmd model key — deep-equal vs golden."""
    golden = L.model_tokens(L.all_models_of(L.golden_config(cluster)))
    fresh = L.model_tokens(L.all_models_of(L.rendered_config(cluster)))
    problems = []
    for mid in sorted(set(golden) & set(fresh)):
        if golden[mid]["rest"] != fresh[mid]["rest"]:
            problems.append(f"{mid}: {_first_diff_key(golden[mid]['rest'], fresh[mid]['rest'])}")
    assert not problems, f"{cluster}: per-model field divergence:\n" + "\n".join(problems)


def _ws_norm(macros: dict) -> dict:
    """Macro equality up to intra-line whitespace: toYaml of a rewritten values
    file may re-indent continuation lines without changing the flag stream the
    macro expands to (llama-swap splits on whitespace)."""
    return {k: re.sub(r"[ \t]+", " ", (v or "").strip()) for k, v in (macros or {}).items()}


@pytest.mark.parametrize("cluster", CLUSTERS)
def test_c02_2_config_layer_macros_matrix_hooks_scalars(cluster):
    g = L.golden_config(cluster)
    f = L.rendered_config(cluster)
    assert _ws_norm(g.get("macros")) == _ws_norm(f.get("macros")), (
        f"{cluster}: macros diverge (whitespace-normalized)"
    )
    assert g.get("matrix") == f.get("matrix"), f"{cluster}: matrix diverged"
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
    fresh = set(L.all_models_of(L.rendered_config(cluster)))
    golden = set(L.all_models_of(L.golden_config(cluster)))
    assert golden <= fresh, f"{cluster}: rendered IDs dropped vs golden: {sorted(golden - fresh)}"


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
    """The 6 DISABLED cmd strings must render byte-identical to the golden:
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
