# Shared helpers for the llama-swap config-generation feature tests
# (.agents/plans/2026/2026-10-feat-llama-swap-config-generation).
#
# Contract surface (plan "Commands" section): per-cluster renders are produced
# with the documented extract-and-render trick
# (skills/helm-chart-creation/references/mcp-servers.md) — the `llama-swap:`
# subtree of the service values is dumped to a file and overlaid on the chart
# with -f. Goldens under tests/golden/ are the byte-exact `config.yaml` ConfigMap
# DATA of the pre-conversion chart (captured 2026-10-22 at commit b2aa2e4b2,
# helm v3.16.4, app-template 5.0.1); they are the immutable parity spec.
#
# Parity semantics follow the plan's risks section: normalized-token equality
# (cmd flag-token multisets), not byte equality — Helm `toYaml` already dropped
# comments, and the schema rewrite re-wraps multi-line strings, so only the
# semantic token stream at llama-swap's macro-expansion input is stable.

from __future__ import annotations

import collections
import functools
import re
import shlex
import shutil
import subprocess
from pathlib import Path

import yaml

CHART_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = CHART_DIR.parent.parent
GOLDEN_DIR = CHART_DIR / "tests" / "golden"
FIXTURES_DIR = CHART_DIR / "tests" / "fixtures"
TESTS_DIR = CHART_DIR / "tests"
SERVICE_VALUES = {
    "gpu": REPO_ROOT / "services/gpu/prod/values.yaml",
    "gpu-ai": REPO_ROOT / "services/gpu-ai/prod/values.yaml",
}

# Pinned autogen tool: supply-chain anchor of containers/llama-swap-autogen
# (DECISIONS 2026-10-22 "Planning decisions"). If dev moves the pin, these
# tests move only when the decision record moves with it.
AUTOGEN_REPO = "shirayu/llama_swap_config_autogen"
AUTOGEN_COMMIT = "c7357e68c755b54557f5b0f88b0507bf1c981500"
AUTOGEN_TARBALL_URL = (
    "https://github.com/shirayu/llama_swap_config_autogen/archive/"
    f"{AUTOGEN_COMMIT}.tar.gz"
)

AUTOGEN_IMAGE = "ghcr.io/ownyourio/llama-swap-autogen"
FLEET_IMAGE = "ghcr.io/mostlygeek/llama-swap:unified-vulkan-262"

# ---------------------------------------------------------------------------
# Environment gating
# ---------------------------------------------------------------------------


def helm_ready() -> tuple[bool, str]:
    if shutil.which("helm") is None:
        return False, "helm binary not on PATH"
    if not list(CHART_DIR.glob("charts/app-template-*.tgz")):
        return False, "app-template dependency missing (run: helm dependency update charts/llama-swap)"
    return True, ""


def docker_ready() -> tuple[bool, str]:
    if shutil.which("docker") is None:
        return False, "docker CLI not on PATH"
    probe = subprocess.run(["docker", "info"], capture_output=True, text=True, timeout=30)
    if probe.returncode != 0:
        return False, "docker daemon not reachable"
    return True, ""


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def extract_service_values(cluster: str, dest: Path) -> Path:
    subtree = yaml.safe_load(SERVICE_VALUES[cluster].read_text())["llama-swap"]
    dest.write_text(yaml.safe_dump(subtree))
    return dest


@functools.lru_cache(maxsize=None)
def _render_tuple(cluster: str, extra_overlay: str) -> tuple:
    """Full docs of one cluster render, cached (each helm run is ~1s)."""
    import tempfile
    import json as _json

    with tempfile.TemporaryDirectory(prefix="llamaswap-test-") as tmp:
        vals = extract_service_values(cluster, Path(tmp) / "vals.yaml")
        cmd = [
            "helm", "template", "llama-swap", str(CHART_DIR),
            "-f", str(vals),
            "--set", "domain=spencerslab.com",
            "--set", f"clusterName={cluster}",
        ]
        if extra_overlay:
            cmd += _json.loads(extra_overlay)
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if out.returncode != 0:
            raise AssertionError(f"helm template failed for {cluster}:\n{out.stderr}")
        docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
        # Return plain data only (docs reference tempfile paths via nothing, but
        # keep strings for any later re-render needs).
        return tuple(_freeze(d) for d in docs)


def _freeze(obj):
    if isinstance(obj, dict):
        return {k: _freeze(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return tuple(_freeze(v) for v in obj)
    return obj


def _thaw(obj):
    if isinstance(obj, dict):
        return {k: _thaw(v) for k, v in obj.items()}
    if isinstance(obj, tuple):
        return [_thaw(v) for v in obj]
    return obj


def render_docs(cluster: str, extra_overlay: dict | None = None):
    """Pod/ConfigMap docs for a cluster render. `extra_overlay` is a dict of
    chart values merged via an additional -f file (synthetic schema fixtures)."""
    extra_json = ""
    if extra_overlay is not None:
        import json as _json
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as fh:
            yaml.safe_dump(extra_overlay, fh)
            overlay_path = fh.name
        extra_json = _json.dumps(["-f", overlay_path])
        docs = _thaw(_render_tuple(cluster, extra_json))
        Path(overlay_path).unlink(missing_ok=True)
        return docs
    return _thaw(_render_tuple(cluster, ""))


def configmap_data(cluster: str, name: str, key: str, extra_overlay: dict | None = None) -> dict:
    """Parsed YAML body of one ConfigMap data key (llama-swap configs)."""
    for doc in render_docs(cluster, extra_overlay):
        if doc.get("kind") == "ConfigMap" and doc.get("metadata", {}).get("name") == name:
            raw = doc["data"][key]
            return yaml.safe_load(raw)
    raise AssertionError(f"ConfigMap {name} not rendered for {cluster}")


def rendered_config(cluster: str) -> dict:
    return configmap_data(cluster, "llama-swap-config", "config.yaml")


def golden_config(cluster: str) -> dict:
    path = GOLDEN_DIR / f"{cluster}.config.yaml"
    assert path.exists(), f"golden fixture {path} missing — fixture breakage, not a code red"
    return yaml.safe_load(path.read_text())


def pod_spec(cluster: str) -> dict:
    deps = [d for d in render_docs(cluster) if d.get("kind") == "Deployment"]
    assert len(deps) == 1, f"expected exactly one Deployment, got {len(deps)}"
    return deps[0]["spec"]["template"]["spec"]


def container(cluster: str, name: str) -> dict:
    spec = pod_spec(cluster)
    for c in spec.get("containers", []):
        if c["name"] == name:
            return c
    raise AssertionError(f"container {name} not found in pod spec")


def init_container(cluster: str, name: str) -> dict:
    spec = pod_spec(cluster)
    for c in spec.get("initContainers", []):
        if c["name"] == name:
            return c
    raise AssertionError(
        f"initContainer {name} not found — C03 wiring (autogen initContainer) not implemented"
    )


def env_map(c: dict) -> dict:
    return {e["name"]: e.get("value") for e in c.get("env", []) if "value" in e}


def mount_paths(c: dict) -> dict:
    return {m["mountPath"]: m for m in c.get("volumeMounts", [])}


# ---------------------------------------------------------------------------
# Normalization (plan C02: "cmd → shlex-ish token multiset per line, # comment
# lines dropped, blank stripped; deep-map compare otherwise")
# ---------------------------------------------------------------------------

_COMMENT_LINE = re.compile(r"^\s*#")


def cmd_tokens(cmd: str) -> collections.Counter:
    """Flag-token multiset of one llama-swap `cmd` string.

    Comment lines are dropped because llama-swap's SanitizeCommand strips them
    before execution, so they are not behavior. The remainder is shlex-split
    across joined lines so multi-line quoted scripts (whisper/rana bootstraps)
    tokenize as single opaque tokens — quoting fidelity is part of the contract
    (their inner commands must stay one physical line)."""
    if not isinstance(cmd, str):
        raise AssertionError(f"cmd must be a string, got {type(cmd)}: {cmd!r}")
    lines = [ln for ln in cmd.splitlines() if ln.strip() and not _COMMENT_LINE.match(ln)]
    joined = " \n".join(lines)
    try:
        toks = shlex.split(joined, posix=True)
    except ValueError:
        # Unbalanced quoting is itself contract-relevant; fall back to a
        # whitespace multiset so the diff stays readable instead of erroring.
        toks = joined.split()
    return collections.Counter(toks)


def model_tokens(cfg_models: dict) -> dict[str, dict]:
    """Per-model {cmd token Counter, everything else as-is} for a rendered
    config's models map."""
    out = {}
    for mid, m in cfg_models.items():
        rest = {k: v for k, v in m.items() if k != "cmd"}
        out[mid] = {"cmd": cmd_tokens(m.get("cmd", "")), "rest": rest}
    return out


# ---------------------------------------------------------------------------
# Matrix DSL (v262: vars short-name -> model ID; sets are boolean expressions
# over var names; matrix.vars referencing a missing model is a load error —
# v262 matrix.go:71, DECISIONS "standing invariant")
# ---------------------------------------------------------------------------

_MATRIX_TOKEN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_]*")


def matrix_member_ids(cfg: dict, set_name: str) -> set[str]:
    """Model IDs referenced (via vars) by one matrix set expression."""
    matrix = cfg.get("matrix") or {}
    vars_ = matrix.get("vars") or {}
    sets = matrix.get("sets") or {}
    assert set_name in sets, f"matrix set {set_name!r} absent; sets present: {sorted(sets)}"
    tokens = set(_MATRIX_TOKEN.findall(sets[set_name]))
    unknown = tokens - set(vars_)
    assert not unknown, f"matrix set {set_name} references undefined vars {sorted(unknown)}"
    return {vars_[t] for t in tokens}


def matrix_all_sets(cfg: dict) -> dict[str, set[str]]:
    return {name: matrix_member_ids(cfg, name) for name in ((cfg.get("matrix") or {}).get("sets") or {})}


def assert_matrix_closure(cfg: dict, cluster: str) -> None:
    ids = set((cfg.get("models") or {}).keys())
    vars_ = (cfg.get("matrix") or {}).get("vars") or {}
    dangling = {k: v for k, v in vars_.items() if v not in ids}
    assert not dangling, (
        f"{cluster}: matrix.vars references missing models (v262 load error): {dangling}"
    )


# ---------------------------------------------------------------------------
# -hf flag extraction from a golden cmd
# ---------------------------------------------------------------------------


def cmd_flag_value(cmd: str, flag: str) -> str | None:
    """Value token after the LAST occurrence of `flag` (e.g. '-hf') in the
    token stream: llama.cpp treats duplicated flags as rightmost-wins, so the
    effective value is the last pair (e.g. q38q8 sets --cache-reuse twice)."""
    toks = list(cmd_tokens(cmd).elements())
    found = None
    for i, t in enumerate(toks):
        if t == flag and i + 1 < len(toks):
            found = toks[i + 1]
    return found


def render_macro_or_literal(cmd: str, macro: str, expanded_tokens: tuple[str, ...]) -> None:
    """Assert a `use:` macro is present in the cmd token stream EITHER as the
    `${macro}` reference (what the current chart emits — llama-swap expands at
    load) OR fully expanded. The schema plan says composition emits each `use`
    macro's expansion; parity forbids changing the golden byte stream, so both
    shapes are contract-equal as long as llama-swap resolves to the same flags."""
    toks = set(cmd_tokens(cmd))
    if f"${{{macro}}}" in toks:
        return
    missing = [t for t in expanded_tokens if t not in toks]
    assert not missing, f"neither macro reference ${{{macro}}} nor its expansion {expanded_tokens} in cmd"


# ---------------------------------------------------------------------------
# Values-file loading (schema contract tests read YAML directly)
# ---------------------------------------------------------------------------


def chart_values() -> dict:
    return yaml.safe_load((CHART_DIR / "values.yaml").read_text())


def service_overlay(cluster: str) -> dict:
    return yaml.safe_load(SERVICE_VALUES[cluster].read_text())["llama-swap"]


# ---------------------------------------------------------------------------
# Roster data tables (approved ID list — DECISIONS 2026-10-22 "Plan approval")
# ---------------------------------------------------------------------------

CHART_MODEL_IDS = [
    "qwen3.8-27b-q4", "qwen3.8-27b-q6", "qwen3.8-27b-q8", "qwen3.8-27b-bf16",
    "qwen3.6-27b-q6", "qwen3.6-27b-q8",
    "qwen3-coder-next-q6", "qwen3-coder-next-q8",
    "qwen3.6-35b-a3b-q6", "qwen3.6-35b-a3b-q8", "qwen3.6-35b-a3b-1m", "qwen3.6-35b-a3b-bf16",
    "qwen3-30b-a3b-q4", "qwen3-30b-a3b-q8",
    "qwen3-8b-q4", "qwen3-8b-q8",
    "home-3b-v3-gpu", "home-3b-v3",
    "kat-coder-q4", "kat-coder-q6", "kat-coder-q8",
    "qwen3-vl-4b-q4", "qwen3-vl-8b-q4", "qwen3-vl-8b-q8", "qwen3-vl-8b-bf16",
    "qwen3-vl-30b-a3b-q4", "qwen3-vl-30b-a3b-q8", "qwen3-vl-30b-a3b-bf16",
    "qwen3-vl-2b-q8", "qwen3-vl-2b-q4", "qwen3-vl-2b-bf16",
    "qwen3-vl-4b-q8", "qwen3-vl-4b-bf16",
    "qwen3-vl-4b-thinking-q8", "qwen3-vl-4b-thinking-q4", "qwen3-vl-4b-thinking-bf16",
    "qwen3-vl-30b-a3b-thinking-q8", "qwen3-vl-30b-a3b-thinking-q4", "qwen3-vl-30b-a3b-thinking-bf16",
    "whisper-large-v3",
]

GPUAI_LOCAL_IDS = [
    "qwen38-orca", "qwen38-ara", "qwen38-rana", "qwen38-humanlike", "qwen38-orca-f16",
    "qwen3.8-27b-q8-visual", "qwen3.6-35b-a3b-q8-visual", "qwen3-embedding-0.6b",
    "qwen3.8-27b-q8-1m",
    "kat-coder-q4-1m", "kat-coder-q6-1m", "kat-coder-q8-1m",
    "qwen36-heretic", "qwen36-huihui", "coder-next-ablit",
]

# The six gpu fail-fast DISABLED entries (C02 acceptance 4) and, for C04, the
# new gpu disabled entry (ornith 35B bf16).
GPU_DISABLED_IDS = [
    "kat-coder-q4", "kat-coder-q6", "kat-coder-q8",
    "qwen3.6-35b-a3b-bf16", "qwen3.6-35b-a3b-1m", "qwen3-vl-30b-a3b-bf16",
]

# Raw-`cmd` escape hatch (plan C02: whisper keeps its /bin/sh bootstrap; nothing
# else in the chart; qwen38-rana's multi-curl exec has no schema equivalent).
CHART_RAW_CMD_IDS = {"whisper-large-v3"}
GPUAI_RAW_CMD_IDS = {"qwen38-rana"}

# 12 chart models carrying the vl-workload filter (all non-Thinking Qwen3-VL
# Instruct entries — the ones that today use the &vlWorkloadFilters anchor).
VL_WORKLOAD_IDS = [
    "qwen3-vl-4b-q4", "qwen3-vl-8b-q4", "qwen3-vl-8b-q8", "qwen3-vl-8b-bf16",
    "qwen3-vl-30b-a3b-q4", "qwen3-vl-30b-a3b-q8", "qwen3-vl-30b-a3b-bf16",
    "qwen3-vl-2b-q8", "qwen3-vl-2b-q4", "qwen3-vl-2b-bf16",
    "qwen3-vl-4b-q8", "qwen3-vl-4b-bf16",
]

# C04 approved additions (exact ID table from plan "Delivery decisions",
# user-approved 2026-10-22). Bounds the parity test's allowed superset so the
# same parity assertions stay valid from C02 through C04 (tests are immutable).
C04_NEW_IDS = {
    "gpu-ai": [
        "qwen3.8-flash-next-q3", "qwen3.8-flash-next-q4",
        "qwen3.8-flash-next-q5", "qwen3.8-flash-next-q6",
        "qwen3.8-flash-next-orca-q6",
        "ornith-1.5-122b-q3", "ornith-1.5-122b-q4",
        "ornith-1.5-122b-q5", "ornith-1.5-122b-q6",
    ],
    "gpu": [],
}
C04_LADDER_35B_IDS = [
    "ornith-1.5-35b-a3b-iq2xxs", "ornith-1.5-35b-a3b-q3", "ornith-1.5-35b-a3b-q4",
    "ornith-1.5-35b-a3b-q5", "ornith-1.5-35b-a3b-q6", "ornith-1.5-35b-a3b-q8",
    "ornith-1.5-35b-a3b-bf16",
]
C04_NEW_IDS["gpu"] = list(C04_LADDER_35B_IDS)
C04_NEW_IDS["gpu-ai"] = C04_NEW_IDS["gpu-ai"] + list(C04_LADDER_35B_IDS)

# Exact -hf refs of the approved ladder as verified on 2026-10-22 (C04 task 1
# re-verifies against the HF API at implementation time; if churn lands, the
# evidence goes through the test writer session, not silent test edits).
C04_HF_REFS = {
    "qwen3.8-flash-next-q3": "unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q3_K_XL",
    "qwen3.8-flash-next-q4": "unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q4_K_XL",
    "qwen3.8-flash-next-q5": "unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q5_K_XL",
    "qwen3.8-flash-next-q6": "unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q6_K_XL",
    "qwen3.8-flash-next-orca-q6": "orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF:Q6_K",
    "ornith-1.5-122b-q3": "unsloth/Ornith-1.5-122B-GGUF:UD-Q3_K_XL",
    "ornith-1.5-122b-q4": "unsloth/Ornith-1.5-122B-GGUF:UD-Q4_K_XL",
    "ornith-1.5-122b-q5": "unsloth/Ornith-1.5-122B-GGUF:UD-Q5_K_XL",
    "ornith-1.5-122b-q6": "unsloth/Ornith-1.5-122B-GGUF:UD-Q6_K_XL",
    "ornith-1.5-35b-a3b-q4": "ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q4_K_M",
    "ornith-1.5-35b-a3b-q5": "ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q5_K_M",
    "ornith-1.5-35b-a3b-q6": "ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q6_K",
    "ornith-1.5-35b-a3b-q8": "ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q8_0",
    "ornith-1.5-35b-a3b-bf16": "ornith-ai/Ornith-1.5-35B-A3B-GGUF:BF16",
    "ornith-1.5-35b-a3b-q3": "bartowski/Ornith-1.5-35B-A3B-GGUF:Q3_K_XL",
    "ornith-1.5-35b-a3b-iq2xxs": "bartowski/Ornith-1.5-35B-A3B-GGUF:IQ2_XXS",
}

# Flash-next q3/q4 MTP draft is unconditional (in-repo mtp file, DECISIONS);
# orca-q6 MTP and 122B MTP are header-check-conditional at C04 time — NOT
# asserted here (see TEST_SPEC "deliberately untested").
C04_FLASHNEXT_DRAFT = "unsloth/Qwen3.8-Flash-Next-GGUF:mtp-Qwen3.8-Flash-Next-Q8_0"

# gpu-ai preload (golden-derived; C04 "preload unchanged"): no new model may
# enter it, and flash-next q5/q6 must appear in NO matrix set at all.
C04_PRELOAD_PINNED = ["qwen3.8-27b-q8", "qwen3-embedding-0.6b"]


def all_models_of(cfg: dict) -> dict:
    models = cfg.get("models")
    assert isinstance(models, dict), "rendered config lacks a models map"
    return models
