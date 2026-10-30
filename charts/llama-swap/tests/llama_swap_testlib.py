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
TESTS_DIR = CHART_DIR / "tests"
SERVICE_VALUES = {
    "gpu": REPO_ROOT / "services/gpu/prod/values.yaml",
    "gpu-ai": REPO_ROOT / "services/gpu-ai/prod/values.yaml",
}


# ---------------------------------------------------------------------------
# Environment gating
# ---------------------------------------------------------------------------


def helm_ready() -> tuple[bool, str]:
    if shutil.which("helm") is None:
        return False, "helm binary not on PATH"
    if not list(CHART_DIR.glob("charts/app-template-*.tgz")):
        return False, "app-template dependency missing (run: helm dependency update charts/llama-swap)"
    return True, ""


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


def render_rc(cluster: str, overlay: dict | None = None) -> tuple[int, str]:
    """helm template rc + combined output for a render that is EXPECTED TO
    FAIL (drift guards: CA2 duplicate IDs, CA4 args/scanPaths disagreement or
    reintroduced command:). render_docs raises on rc!=0, so guard-probe tests
    need the non-raising form."""
    import tempfile
    with tempfile.TemporaryDirectory(prefix="llamaswap-rc-") as tmp:
        vals = extract_service_values(cluster, Path(tmp) / "vals.yaml")
        cmd = ["helm", "template", "llama-swap", str(CHART_DIR), "-f", str(vals),
               "--set", "domain=spencerslab.com", "--set", f"clusterName={cluster}"]
        if overlay is not None:
            ov = Path(tmp) / "ov.yaml"
            ov.write_text(yaml.safe_dump(overlay))
            cmd += ["-f", str(ov)]
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        return out.returncode, out.stdout + out.stderr


def configmap_data(cluster: str, name: str, key: str, extra_overlay: dict | None = None) -> dict:
    """Parsed YAML body of one ConfigMap data key (llama-swap configs)."""
    for doc in render_docs(cluster, extra_overlay):
        if doc.get("kind") == "ConfigMap" and doc.get("metadata", {}).get("name") == name:
            raw = doc["data"][key]
            return yaml.safe_load(raw)
    raise AssertionError(f"ConfigMap {name} not rendered for {cluster}")


def rendered_config(cluster: str) -> dict:
    return configmap_data(cluster, "llama-swap-config", "config.yaml")


@functools.lru_cache(maxsize=None)
def _render_default_docs() -> tuple:
    """docs of the chart-values-only render (NO service overlay) — the
    'default' leg of the boot-safety invariant (CA2 full-catalog default-
    disabled: every rendered entry is an echo)."""
    cmd = [
        "helm", "template", "llama-swap", str(CHART_DIR),
        "--set", "domain=spencerslab.com",
        "--set", "clusterName=default",
    ]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if out.returncode != 0:
        raise AssertionError(f"helm template failed for default:\n{out.stderr}")
    docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
    return tuple(_freeze(d) for d in docs)


def rendered_config_default() -> dict:
    for doc in _thaw(_render_default_docs()):
        if doc.get("kind") == "ConfigMap" and doc.get("metadata", {}).get("name") == "llama-swap-config":
            return yaml.safe_load(doc["data"]["config.yaml"])
    raise AssertionError("llama-swap-config not rendered for default")


def golden_config(cluster: str) -> dict:
    path = GOLDEN_DIR / f"{cluster}.config.yaml"
    assert path.exists(), f"golden fixture {path} missing — fixture breakage, not a code red"
    return yaml.safe_load(path.read_text())


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
# macros.go port-rule simulation (C01 boot-safety contract, 2026-10-25)
# ---------------------------------------------------------------------------
#
# The deployed llama-swap (unified-vulkan-262 rebuild .. v266) hard-fails
# config load with `proxy uses ${PORT} but cmd does not`; macros.go is
# byte-identical across the v262-v266 source tarballs (verified 2026-10-25),
# and there is no docker in this env, so this offline simulation is the
# pre-merge boot proof (the never-run `-validate` replacement).
#
# Faithful to internal/config/macros.go resolveConfigMacros, step for step:
# StripComments on cmd/cmdStop BEFORE expansion, the default proxy injected
# for models without one BEFORE the rule, mergeModelMacros +
# substituteMacroList, then the ${PORT} test on the EXPANDED strings.

# MODEL_CONFIG_DEFAULT_PROXY (internal/config/model_config.go:11). A model
# without a proxy key is given this BEFORE the port rule runs
# (macros.go:127-129) — so key absence is not an escape from the rule; the
# only escape for a ${PORT}-less cmd is an explicit ${PORT}-free proxy.
LLAMA_SWAP_DEFAULT_PROXY = "http://localhost:${PORT}"


def strip_cmd_comments(cmd: str) -> str:
    """macros.go StripComments (commands.go): comment lines drop before macro
    expansion, so a ${PORT} inside a cmd comment is not a port request."""
    return "\n".join(ln for ln in cmd.split("\n") if not ln.strip().startswith("#"))


def _go_macro_str(value) -> str:
    """fmt.Sprintf("%v", v) for the scalar macro values llama-swap allows
    (string, int, float, bool — validateMacro)."""
    if isinstance(value, str):
        return value
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return format(value, "g")
    raise AssertionError(f"macro value must be scalar, got {type(value)}: {value!r}")


def merge_model_macros(model_id, global_macros, model_macros):
    """mergeModelMacros (macros.go:236): MODEL_ID first, then global macros in
    declaration order; a model-level entry OVERRIDES a same-named global in
    place (keeping the global's position), otherwise appends."""
    merged = [("MODEL_ID", model_id)] + list(global_macros)
    for name, value in model_macros:
        for i, (existing, _) in enumerate(merged):
            if existing == name:
                merged[i] = (name, value)
                break
        else:
            merged.append((name, value))
    return merged


def _substitute_macro_in_value(value, name, macro_value):
    slug = f"${{{name}}}"
    macro_str = _go_macro_str(macro_value)
    if isinstance(value, str):
        if value == slug:
            return macro_value
        return value.replace(slug, macro_str) if slug in value else value
    if isinstance(value, dict):
        return {k: _substitute_macro_in_value(v, name, macro_value) for k, v in value.items()}
    if isinstance(value, list):
        return [_substitute_macro_in_value(v, name, macro_value) for v in value]
    return value


def substitute_macro_list(value, macros):
    """substituteMacroList (macros.go:257): reversed declaration order, so a
    macro value may reference only macros declared earlier than it."""
    for name, macro_value in reversed(macros):
        value = _substitute_macro_in_value(value, name, macro_value)
    return value


def effective_cmd(cfg: dict, model_id: str) -> str:
    """The cmd as the llama-swap binary executes it: comment-stripped, then
    model+global macros expanded through the same merge/substitute pipeline as
    port_rule_violations. Regime contracts (debug-flash-next-vulkan-oom C03)
    must assert on this stream — chart composition may carry placement inside
    a macro reference whose raw render hides its tokens."""
    model = dict((cfg.get("models") or {}).get(model_id) or {})
    model_macros = list((model.pop("macros", None) or {}).items())
    if isinstance(model.get("cmd"), str):
        model["cmd"] = strip_cmd_comments(model["cmd"])
    macros = merge_model_macros(model_id, list((cfg.get("macros") or {}).items()), model_macros)
    expanded = substitute_macro_list(model, macros)
    cmd = expanded.get("cmd")
    assert isinstance(cmd, str), f"{model_id}: rendered cmd is not a string: {cmd!r}"
    return cmd


def effective_proxy(cfg: dict, model_id: str) -> str:
    """The proxy string as the binary sees it at the port rule: binary default
    when the key is absent/null, user macros expanded (same merge/substitute
    pipeline as the cmd). Non-string results render via _go_macro_str (Go
    fmt %v), as the Go string-conversion would."""
    model = dict((cfg.get("models") or {}).get(model_id) or {})
    model_macros = list((model.pop("macros", None) or {}).items())
    proxy = model.get("proxy")
    if proxy is None:
        proxy = LLAMA_SWAP_DEFAULT_PROXY
    macros = merge_model_macros(model_id, list((cfg.get("macros") or {}).items()), model_macros)
    resolved = substitute_macro_list(proxy, macros)
    return resolved if isinstance(resolved, str) else _go_macro_str(resolved)


def port_rule_violations(cfg: dict) -> list[str]:
    """Every model id the deployed binary rejects with `proxy uses ${PORT} but
    cmd does not` (macros.go:182-184 — checked AFTER comment strip, default
    proxy injection and user-macro expansion). Go stops at the first
    violator; this enumerates all of them so a failure names every broken
    entry instead of one of twenty-four."""
    global_macros = list((cfg.get("macros") or {}).items())
    models = cfg.get("models") or {}
    violations = []
    for model_id in sorted(models):
        model = models.get(model_id)
        if not isinstance(model, dict):
            continue
        model = dict(model)
        model_macros = list((model.pop("macros", None) or {}).items())
        if isinstance(model.get("cmd"), str):
            model["cmd"] = strip_cmd_comments(model["cmd"])
        if isinstance(model.get("cmdStop"), str):
            model["cmdStop"] = strip_cmd_comments(model["cmdStop"])
        model = substitute_macro_list(model, merge_model_macros(model_id, global_macros, model_macros))
        cmd = model.get("cmd")
        proxy = model.get("proxy")
        cmd_str = cmd if isinstance(cmd, str) else ""
        proxy_str = LLAMA_SWAP_DEFAULT_PROXY if proxy is None else proxy
        proxy_str = proxy_str if isinstance(proxy_str, str) else _go_macro_str(proxy_str)
        if "${PORT}" in proxy_str and "${PORT}" not in cmd_str:
            violations.append(model_id)
    return violations


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

# P3 survivors (REPLAN amendment G, 2026-10-24): gpu fail-fast DISABLED entries
# whose golden echo stays BYTE-PINNED. The pre-replan list held six; the kat
# trio left with REMOVED_IDS under the user's CR3 ruling.
GPU_DISABLED_IDS = [
    "qwen3.6-35b-a3b-bf16", "qwen3.6-35b-a3b-1m", "qwen3-vl-30b-a3b-bf16",
]
GPU_DISABLED_IDS_PRE_REPLAN = GPU_DISABLED_IDS + [
    "kat-coder-q4", "kat-coder-q6", "kat-coder-q8",
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

# MTP draft sidecar ref for the flash-next ladder. The PREVIOUS ticket's
# "unconditional draft" contract was superseded by this ticket's DECISIONS
# 2026-10-26 (MTP is a two-gate path: off for C03's first cut, re-added only
# through C04's gate 2 on C01's hc-layout verdict). The constant stays as the
# gate-2 candidate ref and the layout-check target.
C04_FLASHNEXT_DRAFT = "unsloth/Qwen3.8-Flash-Next-GGUF:mtp-Qwen3.8-Flash-Next-Q8_0"

# The flash-next family's rendered IDs — the ONLY surface C03 may change
# (chunks/C03.md AC2 blast-radius rule; DECISIONS 2026-10-26 "${moe} untouched").
# Both qwen3.8-flash-next and qwen3.8-flash-next-orca families.
FLASHNEXT_FAMILY_IDS = [
    "qwen3.8-flash-next-q3", "qwen3.8-flash-next-q4",
    "qwen3.8-flash-next-q5", "qwen3.8-flash-next-q6",
    "qwen3.8-flash-next-orca-q6",
]

# Pre-chunk render baseline (captured by the test session at commit 561d0559e,
# clean tree, helm v3.16.4 + app-template 5.0.1, round-trip byte-verified).
# This is the "approved pre-chunk table" chunks/C03.md AC2/AC3 diff against:
# everything outside FLASHNEXT_FAMILY_IDS must stay identical through C03/C04.
BASELINE_DIR = TESTS_DIR / "evidence" / "flashnext-pre-chunk-baseline"


def baseline_raw(cluster: str) -> str:
    path = BASELINE_DIR / f"{cluster}.config.yaml"
    assert path.exists(), f"pre-chunk baseline fixture {path} missing — fixture breakage, not a code red"
    return path.read_text()


def baseline_config(cluster: str) -> dict:
    return yaml.safe_load(baseline_raw(cluster))


# gpu-ai preload (2026-10-29 OOM ruling re-pin; C04 "no new model may enter
# it" carries over): the list is embedding-only — q8 went lazy with the
# strata arena sharing the node's RAM — and flash-next q5/q6 must appear in
# NO matrix set at all.
C04_PRELOAD_PINNED = ["qwen3-embedding-0.6b"]


def all_models_of(cfg: dict) -> dict:
    models = cfg.get("models")
    assert isinstance(models, dict), "rendered config lacks a models map"
    return models

# ---------------------------------------------------------------------------
# REPLAN 2026-10-24 frozen tables (user rulings; ground truth = DECISIONS.md
# 'Replan decisions + user rulings' + plan CR2/CR3). CA1 freezes them here as
# literals so review can diff verbatim against the rulings; the arithmetic
# identity vs the (byte-untouched) goldens is pinned by
# test_repl_tables_match_frozen_decisions in test_config_parity.py.
# ---------------------------------------------------------------------------


# FROZEN set of 13 (CR3): coder duo + kat trio + kat-1m trio + coder-next-ablit
# (ruled in with the coder family) + ruling B's older text-only Qwen3 line.
# The ENTIRE qwen3.6 line SURVIVES (incl. gpu's golden-pinned tuned 35B-q8).
REMOVED_IDS = [
    "coder-next-ablit",
    "kat-coder-q4",
    "kat-coder-q4-1m",
    "kat-coder-q6",
    "kat-coder-q6-1m",
    "kat-coder-q8",
    "kat-coder-q8-1m",
    "qwen3-30b-a3b-q4",
    "qwen3-30b-a3b-q8",
    "qwen3-8b-q4",
    "qwen3-8b-q8",
    "qwen3-coder-next-q6",
    "qwen3-coder-next-q8",
]

# CR2: the full post-replan rendered catalog — every cluster render must carry
# EXACTLY these IDs (P1). gpu side = chart survivors, gpu-ai-local added.
# cf-86 growth (2026-10-29): +qwen3.8-flash-next-heretic-q4 (C03) and
# +qwen38-heretic (C04) — both gpu-ai-only, so the partition moves to
# 60 = gpu 34+26 / gpu-ai 60+0 (card ask; the gpu side only echoes them, P5).
CATALOG_IDS = [
    "home-3b-v3",
    "home-3b-v3-gpu",
    "ornith-1.5-122b-q3",
    "ornith-1.5-122b-q4",
    "ornith-1.5-122b-q5",
    "ornith-1.5-122b-q6",
    "ornith-1.5-35b-a3b-bf16",
    "ornith-1.5-35b-a3b-iq2xxs",
    "ornith-1.5-35b-a3b-q3",
    "ornith-1.5-35b-a3b-q4",
    "ornith-1.5-35b-a3b-q5",
    "ornith-1.5-35b-a3b-q6",
    "ornith-1.5-35b-a3b-q8",
    "qwen3-embedding-0.6b",
    "qwen3-vl-2b-bf16",
    "qwen3-vl-2b-q4",
    "qwen3-vl-2b-q8",
    "qwen3-vl-30b-a3b-bf16",
    "qwen3-vl-30b-a3b-q4",
    "qwen3-vl-30b-a3b-q8",
    "qwen3-vl-30b-a3b-thinking-bf16",
    "qwen3-vl-30b-a3b-thinking-q4",
    "qwen3-vl-30b-a3b-thinking-q8",
    "qwen3-vl-4b-bf16",
    "qwen3-vl-4b-q4",
    "qwen3-vl-4b-q8",
    "qwen3-vl-4b-thinking-bf16",
    "qwen3-vl-4b-thinking-q4",
    "qwen3-vl-4b-thinking-q8",
    "qwen3-vl-8b-bf16",
    "qwen3-vl-8b-q4",
    "qwen3-vl-8b-q8",
    "qwen3.6-27b-q6",
    "qwen3.6-27b-q8",
    "qwen3.6-35b-a3b-1m",
    "qwen3.6-35b-a3b-bf16",
    "qwen3.6-35b-a3b-q6",
    "qwen3.6-35b-a3b-q8",
    "qwen3.6-35b-a3b-q8-visual",
    "qwen3.8-27b-bf16",
    "qwen3.8-27b-q4",
    "qwen3.8-27b-q6",
    "qwen3.8-27b-q8",
    "qwen3.8-27b-q8-1m",
    "qwen3.8-27b-q8-visual",
    "qwen3.8-flash-next-heretic-q4",
    "qwen3.8-flash-next-orca-q6",
    "qwen3.8-flash-next-q3",
    "qwen3.8-flash-next-q4",
    "qwen3.8-flash-next-q5",
    "qwen3.8-flash-next-q6",
    "qwen36-heretic",
    "qwen36-huihui",
    "qwen38-ara",
    "qwen38-heretic",
    "qwen38-humanlike",
    "qwen38-orca",
    "qwen38-orca-f16",
    "qwen38-rana",
    "whisper-large-v3",
]

# gpu-ai-enabled catalog rungs (22 after the cf-86 pair): these render as
# catalog echoes on gpu (CA1 isolation flip: absent -> present-as-echo).
GPUAI_LOCAL_CATALOG_IDS = [
    "ornith-1.5-122b-q3",
    "ornith-1.5-122b-q4",
    "ornith-1.5-122b-q5",
    "ornith-1.5-122b-q6",
    "qwen3-embedding-0.6b",
    "qwen3.6-35b-a3b-q8-visual",
    "qwen3.8-27b-q8-1m",
    "qwen3.8-27b-q8-visual",
    "qwen3.8-flash-next-heretic-q4",
    "qwen3.8-flash-next-orca-q6",
    "qwen3.8-flash-next-q3",
    "qwen3.8-flash-next-q4",
    "qwen3.8-flash-next-q5",
    "qwen3.8-flash-next-q6",
    "qwen36-heretic",
    "qwen36-huihui",
    "qwen38-ara",
    "qwen38-heretic",
    "qwen38-humanlike",
    "qwen38-orca",
    "qwen38-orca-f16",
    "qwen38-rana",
]

# gpu renders these as fail-fast echoes: the 3 surviving golden byte-pinned
# echoes + the C04 ornith bf16 echo + the gpu-ai-local catalog IDs (22 after
# the cf-86 pair land, C03/C04).
GPU_ECHO_IDS = [
    "ornith-1.5-122b-q3",
    "ornith-1.5-122b-q4",
    "ornith-1.5-122b-q5",
    "ornith-1.5-122b-q6",
    "ornith-1.5-35b-a3b-bf16",
    "qwen3-embedding-0.6b",
    "qwen3-vl-30b-a3b-bf16",
    "qwen3.6-35b-a3b-1m",
    "qwen3.6-35b-a3b-bf16",
    "qwen3.6-35b-a3b-q8-visual",
    "qwen3.8-27b-q8-1m",
    "qwen3.8-27b-q8-visual",
    "qwen3.8-flash-next-heretic-q4",
    "qwen3.8-flash-next-orca-q6",
    "qwen3.8-flash-next-q3",
    "qwen3.8-flash-next-q4",
    "qwen3.8-flash-next-q5",
    "qwen3.8-flash-next-q6",
    "qwen36-heretic",
    "qwen36-huihui",
    "qwen38-ara",
    "qwen38-heretic",
    "qwen38-humanlike",
    "qwen38-orca",
    "qwen38-orca-f16",
    "qwen38-rana",
]

# Enablement matrix (CA1 freeze; DECISIONS arithmetic "58 = gpu 34+24 /
# gpu-ai 58+0", cf-86 moves the partition to 60 = gpu 34+26 / gpu-ai 60+0 —
# the two new rungs are gpu-ai-only, gpu only echoes them). GPU_ENABLED_IDS
# derives from the frozen partition — CATALOG minus the echoes — so the two
# lists cannot drift apart silently.
GPU_ENABLED_IDS = [i for i in CATALOG_IDS if i not in set(GPU_ECHO_IDS)]
ENABLEMENT = {
    "gpu": {"enabled": GPU_ENABLED_IDS, "echo": GPU_ECHO_IDS},
    "gpu-ai": {"enabled": CATALOG_IDS, "echo": []},
}


_ECHO_CMD = re.compile("^/bin/sh -c \"echo '.*' >&2; exit 1\"\\n?$")


def is_echo_cmd(cmd: str) -> bool:
    """Fail-fast echo shape (ratified deviation-1 wording) — the loader-safe
    predicate behind P3/P5 and the generalized B/D ref routing."""
    return bool(_ECHO_CMD.match((cmd or "").strip()))

# ---------------------------------------------------------------------------
# CR5 (REPLAN round 2) machinery: shorthand-aware effective refs + display
# scoping. Grammar is outcome-level per plan "CR5 grammar"; the TEST-side
# mirror reads the SAME config.tagCultures map from chart values (validates
# composition, never map content - plan risk note). No test-side culture copy:
# HEAD's values have no shorthand, so resolution falls through to literals and
# the bar behaves exactly as pre-CB1 in both states.
# ---------------------------------------------------------------------------

NEW_SCHEMA_KEYS = [
    "dispName", "descBase", "descTail", "size", "disp", "suffix",
    "hfRepo", "tagCulture", "tag", "repo",
]
NEW_TOP_KEYS = ["tagCultures"]
LADDER_QUANT_KEYS = {"q3", "q4", "q5", "q6", "q8", "bf16"}

# Desc-TAG obligation (CB1 grammar-consistency): prose rungs the user ruling
# leaves explicit - gated-repo caveats/HF_TOKEN provenance that the uniform
# grammar cannot carry. Their NAME still faces the parenthesized-TAG rule;
# the before/after display table (CR5 bar 2) is the human review of their text.
DESC_PROSE_EXEMPT_FAMILIES = {"qwen3.8-flash-next-orca"}

# ---------------------------------------------------------------------------
# cf-86 frozen tables (plan 2026-10-29 + DECISIONS "Renumap + final-shape
# decisions"). The two llama.cpp rungs C03/C04 land as chart-family data;
# both render LIVE on gpu-ai and as catalog ECHOES on gpu (their families are
# default-disabled chart-side, gpu-ai-only BY ENABLEMENT like the orca family).
# ---------------------------------------------------------------------------

CF86_NEW_IDS = ["qwen3.8-flash-next-heretic-q4", "qwen38-heretic"]
CF86_NEW_FAMILY = {  # rendered ID -> (family, quant key) per the CR1.1 grammar
    "qwen3.8-flash-next-heretic-q4": ("qwen3.8-flash-next-heretic", "q4"),
    "qwen38-heretic": ("qwen38", "heretic"),
}
# -hf refs verified live against the HF API by the cf-86 test session
# (2026-10-29): spiritfather's heretic-2 republish carries Q4_K_M shards +
# Q4_K_M/MTP + mtp/mtp-* draft + mmproj/*; 0bserverx's 27B heretic ladder
# carries the embedded-MTP RVN-Q4_K_M-mtp.gguf at 16,998,720,736 B (~17.0 GB,
# RESEARCH [S22]). A source-gate deviation re-pins THIS table via the test
# session, never a silent dev edit.
CF86_HF_REFS = {
    "qwen3.8-flash-next-heretic-q4": "spiritfather/Qwen3.8-Flash-Next-heretic-2-GGUF:Q4_K_M",
    "qwen38-heretic": "0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF:Q4_K_M-mtp",
}
# Matrix vars the chunks add, letter -> rendered id (C03 fnher into the gpu-ai
# SOLO alternation, C04 q38her into the gpu-ai main dense alternation).
CF86_MATRIX_VARS = {
    "fnher": "qwen3.8-flash-next-heretic-q4",
    "q38her": "qwen38-heretic",
}
CF86_SET_ADDITIONS = {  # set name -> the ONLY vars its expression may gain
    "solo": {"fnher"},
    "main": {"q38her"},
}
# The mmap-regime literals C03 copies verbatim from the flash-next/orca
# families (the -ot string is byte-exact contract, TEST_SPEC §8 lineage).
CF86_MOE_OFFLOAD_LEG = '-ot "\\.ffn_.*_exps\\.=CPU"'


def cf86_matrix_growth_violations(base: dict, cur: dict) -> list[str]:
    """The confined shape of sanctioned cf-86 matrix growth in a render where
    the new rungs are NOT enabled: existing vars stay byte-equal, additions are
    only the pinned letters at their pinned ids, and every set's DNF expansion
    stays identical — a chart-level var joins every cluster's render, but only the
    gpu-ai service overlay may put it into a set, so co-residency must not move
    anywhere else. Expansions are compared, not expressions, so values or helm
    re-wrapping cannot hide a pairing change."""
    import strata_testlib as S

    out = []
    b_vars = (base.get("matrix") or {}).get("vars") or {}
    c_vars = (cur.get("matrix") or {}).get("vars") or {}
    for name, val in sorted(b_vars.items()):
        if c_vars.get(name) != val:
            out.append(f"matrix.vars.{name}: {val!r} -> {c_vars.get(name)!r}")
    for name in sorted(set(c_vars) - set(b_vars)):
        if CF86_MATRIX_VARS.get(name) != c_vars[name]:
            out.append(f"matrix.vars.{name} = {c_vars[name]!r}: not a cf-86 pinned letter/value")
    b_exp, c_exp = S.matrix_expansions(base), S.matrix_expansions(cur)
    for name in sorted(set(b_exp) | set(c_exp)):
        b_combos = sorted(map(sorted, b_exp.get(name, [])))
        c_combos = sorted(map(sorted, c_exp.get(name, [])))
        if b_combos != c_combos:
            out.append(f"matrix.sets.{name}: combos changed: {b_combos} -> {c_combos}")
    return out


def rung_effective_ref(chart_cfg: dict, fam: str, spec: dict, quant: str) -> str | None:
    """CR5 HF resolution order: rung hf literal > {repo | fam.hfRepo} :
    {tag | tagCultures[fam.tagCulture][quant]}."""
    rung = (spec.get("quants") or {}).get(quant) or {}
    if rung.get("hf"):
        return rung["hf"]
    repo = rung.get("repo") or spec.get("hfRepo")
    culture = (chart_cfg.get("tagCultures") or {}).get(spec.get("tagCulture") or "") or {}
    tag = rung.get("tag") or culture.get(quant)
    if repo and tag:
        return f"{repo}:{tag}"
    return None


def id_family_index(chart_cfg: dict) -> dict[str, tuple[str, str]]:
    """rendered ID -> (family, quant-key) via the CR1.1 derivation."""
    out = {}
    for fam, spec in (chart_cfg.get("families") or {}).items():
        for quant, rung in (spec.get("quants") or {}).items():
            mid = (rung or {}).get("id") or f"{fam}-{quant}"
            out[mid] = (fam, quant)
    return out


def cmd_effective_tag(cmd: str) -> str | None:
    """TAG of the effective -hf ref of a rendered cmd (rightmost; opaque
    raw-script fallback per ratified G2 machinery)."""
    ref = cmd_flag_value(cmd, "-hf")
    if ref is None:
        hfs = re.findall(r"(?:^|\s)-hf\s+(\S+)", cmd)
        ref = hfs[-1] if hfs else None
    if ref and ":" in ref:
        return ref.split(":", 1)[1]
    return None
