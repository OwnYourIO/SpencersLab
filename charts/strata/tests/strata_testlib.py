# Shared helpers for the strata chart render-contract suite
# (.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap, chunks C02/C03/C05).
#
# Harness pattern: charts/llama-swap/tests/llama_swap_testlib.py (extract the
# service-side values subtree to a temp file, overlay it on the chart with -f).
# Contract literals below are frozen plan facts — each cites the chunk/AC and
# RESEARCH section it pins. Tests aim at not-yet-written artifacts by design:
# a missing file or failing helm render is a RED naming the chunk, not a skip.
# Only tooling absence (helm binary, jsonschema lib) may skip.

from __future__ import annotations

import functools
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

CHART_DIR = Path(__file__).resolve().parent.parent          # charts/strata
TESTS_DIR = Path(__file__).resolve().parent                 # charts/strata/tests
REPO_ROOT = CHART_DIR.parent.parent
SCHEMA_DIR = TESTS_DIR / "schema"
SERVICE_VALUES = REPO_ROOT / "services/gpu-ai/prod/values.yaml"
CUSTOM_VALUES = REPO_ROOT / "custom-values/gpu-ai/prod-values.yaml"
LLAMA_SWAP_CHART = REPO_ROOT / "charts/llama-swap"
CONTAINER_DIR = REPO_ROOT / "containers/strata"
RUNBOOK_NOTE = REPO_ROOT / ".agents/notes/strata-host-prep-gpu-ai.md"

# --- C01 interface contract (containers/strata/README.md freezes these) ------
# RESEARCH §1: engine package lives at /opt/strata/components/engine/<label>/;
# the exact binary filename under the label dir is a C01 build-time capture —
# never invent it here. The label dir and its version prefix drift with the
# engine version, so pin the FORM and cross-check literals against the README.
SERVE_ENTRY = "/opt/strata/terminal/bin/strata"
ENGINE_ROOT = "/opt/strata/components/engine"
# C01 task 3/README: rx9070 label = gfx120x flavor (R9700-alone primary),
# halo label = gfx1151 flavor (Strix fallback, C05).
ENGINE_LABEL_RE = re.compile(r"^\d+\.\d+\.\d+-linux-x86_64-hip-(rx9070|halo)$")

# --- C02 frozen literals ------------------------------------------------------
RELEASE = "gpu-ai-strata"   # appset release name: <serviceName>-<appName>
NAMESPACE = "default"
PEER_NAME = "strata"
PRIMARY_ID = "qwen3.8-flash-next-strata"
STRIX_ID = "qwen3.8-flash-next-strata-strix"
PROFILE_PRIMARY_FILE = "strata-iq3_s.json"
PROFILE_STRIX_FILE = "strata-strix-iq3_s.json"

# C02 task 2 / AC4: the cmd is contract-literal — serve takes only these four
# flags (RESEARCH §2); all engine tuning lives in the profile JSON.
SERVE_FLAGS = {"--profile", "--host", "--port"}

PRIMARY_ENV_FIVE = [
    "STRATA_PF_FUSED=1", "STRATA_PF_GEMM=1", "STRATA_PA_FAST=1",
    "STRATA_HIP_WMMA=1", "STRATA_SELECT_WMMA=1",
]

# RESEARCH §2 measured absence (DECISIONS amendment): the env var does not
# exist upstream; any appearance in chart/container surfaces is the card
# guide's misattribution re-introduced.
VOID_ENV_TOKEN = "STRATA_KV_GROW_HOLD"

# C02 AC5 forbidden + inclusion pairs. --kv-resident is the batch-column item
# the DECISIONS amendment explicitly removes (one-at-a-time posture).
PRIMARY_FORBIDDEN_FLAGS = [
    "--resident-budget-gib", "--prompt-cache", "--kv-grow", "--vision",
    "--kv-resident",
]
# AC5 names the first four pairs literally; the rest ride the same DECISIONS
# amendment ("args seeded 1:1 on the PR's r9700-arena-pf32k.json MINUS the
# named exclusions", RESEARCH §5) — anything the amendment does not remove is
# contractual. --batch-mtp is deliberately absent from BOTH lists: the
# one-at-a-time clause removes "--batch/--kv-resident", and whether the
# distinct --batch-mtp flag survives the posture cut is not plan-specified.
PRIMARY_REQUIRED_PAIRS = [
    ("--prefill", "32768"),
    ("--conversation-cache-mib", "24576"),
    ("--conversation-cache-slots", "16"),
    ("--expert-cache", "auto"),
    ("--max-context", "262144"),
    ("--kv", "int8"),
    ("--spec", "4"),
    ("--spec-min-p", "0.5"),
    ("--mtp-window", "8192"),
]
# Presence-only: recipe flags whose VALUES are path-shaped (weights, pack and
# MTP dirs live under the values-configurable /models/strata layout).
PRIMARY_REQUIRED_FLAGS = [
    "--pack", "--native", "--ple-gguf", "--expert-profile", "--mtp",
]

# C05 / RESEARCH §7 verbatim eight-set — spellings are upstream literals;
# normalizing them (case, prefixes) breaks the engine's env parsing.
STRIX_EIGHT_SET = [
    "STRATA_PF_FUSED=1", "STRATA_PF_GEMM=1", "STRATA_HC_UPMIX=1",
    "STRATA_PA_FAST=1", "STRATA_HIP_WMMA=1", "STRATA_SELECT_WMMA=1",
    "STRATA_PF_SWITCH_MIN_T=4096", "STRATA_PREFILL_STREAM_MIN=128",
]

# RESEARCH §1 digests recorded 2026-10-27 (in-place-rebuild guard, repo law;
# why-citation: issue #3421).
STRATA_DIGEST_GFX120X = "sha256:703efd51c040152e9fceb993688b01ca0374535a5bfd86c14a60b5e60c96407a"
STRATA_DIGEST_GFX1151 = "sha256:29ecd5cf8b0e21525dbb5c0191d7743d62fa356da646cb6aaf0546e5a31a8b3f"
LLAMA_SWAP_DIGEST = "sha256:0cc42f1024b54be3de100ae7a7a2730047ca5c27cf7a354f8a9f63142f00c045"

# C03 AC2 / RESEARCH §3: proxy must carry NO /v1 suffix — the request path
# appends verbatim, a /v1 there double-prefixes and every route 404s.
PEERS_PROXY = f"http://{RELEASE}.{NAMESPACE}.svc.cluster.local:8080"


# ---------------------------------------------------------------------------
# Environment gating
# ---------------------------------------------------------------------------


def env_ready() -> tuple[bool, str]:
    """Only TOOLING absence may skip a test; a missing chart, Dockerfile or
    render failure must stay RED and name its chunk."""
    if shutil.which("helm") is None:
        return False, "helm binary not on PATH"
    return True, ""


def jsonschema_ready() -> tuple[bool, str]:
    try:
        import jsonschema  # noqa: F401
    except ImportError:
        return False, "jsonschema not installed (pip install jsonschema)"
    return True, ""


def read(path: Path, why: str) -> str:
    assert path.is_file(), f"{path.relative_to(REPO_ROOT)} missing — {why}"
    return path.read_text()


# ---------------------------------------------------------------------------
# Helm rendering
# ---------------------------------------------------------------------------


def _values_file_arg(overlay: dict) -> list[str]:
    """Overlay values via a temp file (helm merges -f layers into chart
    values). File lives until the render completes — tempfile cleanup after
    subprocess.run."""
    fd, p = tempfile.mkstemp(prefix="strata-test-", suffix=".yaml")
    with open(fd, "w") as fh:
        yaml.safe_dump(overlay, fh)
    return ["-f", p]


@functools.lru_cache(maxsize=None)
def _render_cached(release: str, sets_key: tuple, overlay_key: str) -> tuple:
    """docs + raw stdout of one strata-chart render, cached per argument
    tuple. overlay_key is the YAML text of the overlay (empty = chart
    defaults only)."""
    cmd = ["helm", "template", release, str(CHART_DIR)]
    tmp_path = None
    if overlay_key:
        tmp_path = _values_file_arg(yaml.safe_load(overlay_key))
        cmd += tmp_path
    for kv in sets_key:
        cmd += ["--set", kv]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if tmp_path:
        Path(tmp_path[1]).unlink(missing_ok=True)
    if out.returncode != 0:
        raise AssertionError(
            f"helm template failed (release {release}, sets {sets_key}):\n{out.stderr}"
        )
    docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
    return tuple(docs), out.stdout


def render_strata(release: str = RELEASE, sets: tuple = (), overlay: dict | None = None) -> tuple:
    """(docs, raw_stdout) for a strata chart render. `sets` are --set k=v
    strings; `overlay` is a values dict merged via -f (service-side extract)."""
    overlay_key = yaml.safe_dump(overlay, sort_keys=True) if overlay else ""
    return _render_cached(release, tuple(sets), overlay_key)


def service_strata_block() -> dict:
    doc = yaml.safe_load(SERVICE_VALUES.read_text())
    assert isinstance(doc, dict) and "strata" in doc, (
        "services/gpu-ai/prod/values.yaml has no strata: block — C03 not landed"
    )
    return doc["strata"]


def render_service_strata(test_uuid: str | None = None) -> tuple:
    """AC4 (C03): extract-and-render of the service `strata:` block against
    the chart, with the bitwardenIds sentinel replaced by a test UUID (or
    emptied when test_uuid is None, proving the no-secret render is clean)."""
    block = json.loads(json.dumps(service_strata_block()))
    bid = block.get("bitwardenIds") or {}
    if test_uuid is None:
        bid.pop("strata-api-key", None)
    else:
        bid["strata-api-key"] = test_uuid
    block["bitwardenIds"] = bid
    return render_strata(overlay=block)


# ---------------------------------------------------------------------------
# Rendered-object extraction
# ---------------------------------------------------------------------------


def find_kind(docs, kind: str) -> list:
    return [d for d in docs if d.get("kind") == kind]


def the_pod(docs) -> dict:
    pods = find_kind(docs, "Pod")
    if pods:
        return pods[0]
    deps = find_kind(docs, "Deployment")
    assert deps, "no Pod or Deployment rendered"
    return deps[0]["spec"]["template"]


def main_container(docs) -> dict:
    ctrs = the_pod(docs)["spec"]["containers"]
    return ctrs[0]


def declared_configmaps(docs) -> list:
    return find_kind(docs, "ConfigMap")


def _cm_with_key(docs, key: str) -> tuple:
    """The ConfigMap holding `key` in its data. Matching on the DATA KEY
    (not the CM name) keeps the suite agnostic to how C02 named the objects —
    the data keys and mount paths are the contractual surface."""
    for cm in declared_configmaps(docs):
        if key in (cm.get("data") or {}):
            return cm, key
    raise AssertionError(
        f"no ConfigMap carries data key {key!r}; CMs rendered: "
        f"{[(c.get('metadata', {}).get('name'), sorted((c.get('data') or {}).keys())) for c in declared_configmaps(docs)]}"
    )


def inner_config(docs) -> dict:
    """The INNER llama-swap declared config (config.yaml data key)."""
    cm, key = _cm_with_key(docs, "config.yaml")
    return yaml.safe_load(cm["data"][key])


def profile_json(docs, filename: str) -> dict:
    """One run-config profile rendered VERBATIM as JSON (C02 AC5: valid
    JSON — json.loads failing is itself the red)."""
    cm, key = _cm_with_key(docs, filename)
    return json.loads(cm["data"][key])


def rendered_service_name(docs) -> str:
    svcs = find_kind(docs, "Service")
    assert svcs, "no Service rendered"
    return svcs[0]["metadata"]["name"]


def env_list(model: dict) -> list[str]:
    return [str(e) for e in (model.get("env") or [])]


def has_env(model: dict, entry: str) -> bool:
    return entry in env_list(model)


def cmd_flag_tokens(cmd: str) -> list[str]:
    """Every --flag token in a cmd string (contract: serve flags only)."""
    return re.findall(r"(?<![^\s])--[\w-]+", cmd)


def norm_ws(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def arg_pairs(profile: dict) -> list[tuple[str, str]]:
    """Flatten `args` (list of strings, each possibly a whole flag+value
    group) into (flag, value) pairs in order."""
    toks = []
    for a in profile.get("args") or []:
        toks += str(a).split()
    pairs = []
    for i, t in enumerate(toks):
        if t.startswith("--") and i + 1 < len(toks) and not toks[i + 1].startswith("--"):
            pairs.append((t, toks[i + 1]))
    return pairs


def arg_tokens(profile: dict) -> list[str]:
    toks = []
    for a in profile.get("args") or []:
        toks += str(a).split()
    return toks


# ---------------------------------------------------------------------------
# Matrix DSL expansion (C05 AC1 alternation)
# ---------------------------------------------------------------------------
# llama-swap expands a set expression to DNF COMBOS: '&' joins vars into one
# combo, '|' alternates combos, '+name' inlines another set (skill: "(g | q |
# m) & v" → [g,v],[q,v],[m,v]; a combo listing two models admits their
# co-residency, only the requested model starts). Flat membership of the var
# references is the wrong bar for the (p | s) contract — that expression
# mentions BOTH arenas while no combo may ever hold both.


_M_DSL_TOKEN = re.compile(r"&|\||\(|\)|\+[A-Za-z0-9_]+|[A-Za-z0-9_]+")
_M_DNF_CAP = 4096


def _m_tokens(expr: str) -> list[str]:
    return _M_DSL_TOKEN.findall(str(expr))


def _m_parse_expr(toks: list[str], i: int, sets: dict) -> tuple[list, int]:
    terms, i = _m_parse_and(toks, i, sets)
    while i < len(toks) and toks[i] == "|":
        rhs, i = _m_parse_and(toks, i + 1, sets)
        terms = terms + rhs
    return terms, i


def _m_parse_and(toks: list[str], i: int, sets: dict) -> tuple[list, int]:
    terms, i = _m_parse_term(toks, i, sets)
    while i < len(toks) and toks[i] == "&":
        rhs, i = _m_parse_term(toks, i + 1, sets)
        terms = [a | b for a in terms for b in rhs]
        assert len(terms) <= _M_DNF_CAP, f"DNF explosion ({len(terms)} combos) — malformed matrix?"
    return terms, i


def _m_parse_term(toks: list[str], i: int, sets: dict) -> tuple[list, int]:
    t = toks[i]
    if t == "(":
        terms, i = _m_parse_expr(toks, i + 1, sets)
        assert i < len(toks) and toks[i] == ")", "unbalanced parentheses in matrix expression"
        return terms, i + 1
    if t.startswith("+"):
        name = t[1:]
        assert name in sets, f"+{name} references an undefined matrix set"
        return _m_parse_expr(_m_tokens(sets[name]), 0, sets)
    return [frozenset({t})], i + 1


def matrix_expansions(cfg: dict) -> dict[str, list[set[str]]]:
    """Per matrix set: the DNF combos of MODEL IDs (vars resolved). An
    unresolved var token raises — a dangling vars reference is the v262
    load-error class assert_matrix_closure pins for the outer config."""
    matrix = cfg.get("matrix") or {}
    vars_ = matrix.get("vars") or {}
    sets = matrix.get("sets") or {}
    out: dict[str, list[set[str]]] = {}
    for name, expr in sets.items():
        toks = _m_tokens(expr)
        terms, i = _m_parse_expr(toks, 0, sets)
        assert i == len(toks), f"matrix set {name}: unparsed trailing tokens in {expr!r}"
        combos = []
        for term in terms:
            unknown = term - set(vars_)
            assert not unknown, f"matrix set {name}: undefined vars {sorted(unknown)}"
            combos.append({vars_[v] for v in term})
        out[name] = combos
    return out


# ---------------------------------------------------------------------------
# Vendored v266 config schema
# ---------------------------------------------------------------------------


def v266_schema() -> dict:
    """Load + integrity-check the vendored schema before use.

    The provenance guard mirrors scripts/converter-source.json's pattern: the
    file must hash to the recorded digest. It is deliberately NOT pinned to
    the v266 tag in the repo's Renovate ARG-pin pattern (repo law reserves
    those pins for Dockerfile ARG lines).
    """
    raw = (SCHEMA_DIR / "config-schema.v266.json").read_bytes()
    prov = json.loads((SCHEMA_DIR / "PROVENANCE.json").read_text())
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == prov["sha256"], (
        f"vendored schema drifted from PROVENANCE.json ({digest} != {prov['sha256']}) — "
        "re-fetch the v266 tag and record the new digest"
    )
    return json.loads(raw)


def schema_errors(cfg: dict, schema: dict | None = None) -> list:
    import jsonschema
    schema = schema if schema is not None else v266_schema()
    v = jsonschema.Draft7Validator(schema)
    return sorted(v.iter_errors(cfg), key=lambda e: str(list(e.absolute_path)))


def strip_legacy_performance_keys(cfg: dict) -> dict:
    """The pre-cf-77 `performance.enable` key is a documented legacy
    divergence from the v266 JSON schema (it predates this ticket on both
    clusters; cf-77 forbids touching the existing block). C03's outer-config
    schema gate therefore runs with the `performance` subtree carved out —
    carve-out + peers-subtree test together still prove the peers spellings.
    """
    out = json.loads(json.dumps(cfg))
    out.pop("performance", None)
    return out


def engine_exe_paths(text: str) -> set[str]:
    """Full exe paths of the contract form /opt/strata/components/engine/<label>/<binary>
    appearing anywhere in `text`. The label dir is pinned; the filename is
    whatever C01's build-log capture recorded — the seam test compares the
    chart's exe literal against the README's, so nothing is invented here."""
    out = set()
    for m in re.finditer(
        re.escape(ENGINE_ROOT) + r"/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)", text
    ):
        if ENGINE_LABEL_RE.match(m.group(1)):
            out.add(f"{ENGINE_ROOT}/{m.group(1)}/{m.group(2)}")
    return out


def values_region(text: str, key: str) -> str:
    """Raw source of one values key's block — from the key line to the next
    line at shallower-or-equal indent. YAML comments parse out of loaded data,
    and these tests check the WHY-comments themselves."""
    lines = text.splitlines()
    start = next((i for i, ln in enumerate(lines) if ln.strip().startswith(f"{key}:")), None)
    assert start is not None, f"{key}: not found in values source"
    indent = len(lines[start]) - len(lines[start].lstrip())
    end = next(
        (i for i in range(start + 1, len(lines))
         if lines[i].strip() and len(lines[i]) - len(lines[i].lstrip()) <= indent
         and not lines[i].lstrip().startswith("#")),
        len(lines),
    )
    return "\n".join(lines[start:end])
