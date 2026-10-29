# Shared helpers for the strata render-contract suite, run-2 shape
# (.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap-1 — chunks r2-C01..C04).
# Re-homed from the run-1 standalone-chart suite; the parent chart now owns the
# strata workload as a second app-template controller (seven default-OFF data
# flags) and the standalone chart dir retires (Q-C ruling).
#
# Contract literals below are frozen plan facts — each cites its r2 chunk/AC and
# the run-1 RESEARCH section it pins. Tests aim at not-yet-written behavior by
# design: a missing file or failing helm render is a RED naming its chunk, not
# a skip. Only tooling absence (helm binary, jsonschema lib) may skip.

from __future__ import annotations

import functools
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

CHART_DIR = Path(__file__).resolve().parent.parent       # charts/llama-swap
TESTS_DIR = Path(__file__).resolve().parent              # charts/llama-swap/tests
REPO_ROOT = CHART_DIR.parent.parent
SCHEMA_DIR = TESTS_DIR / "schema"
EVIDENCE_DIR = TESTS_DIR / "evidence"
PEERS_EVIDENCE = EVIDENCE_DIR / "strata-peers-expected.yaml"
OFF_FIXTURE = EVIDENCE_DIR / "off-parity" / "render-default.yaml"
OFF_PROVENANCE = EVIDENCE_DIR / "off-parity" / "PROVENANCE.md"
SERVICE_VALUES = REPO_ROOT / "services" / "gpu-ai" / "prod" / "values.yaml"
GPU_VALUES = REPO_ROOT / "services" / "gpu" / "prod" / "values.yaml"
CUSTOM_VALUES = REPO_ROOT / "custom-values" / "gpu-ai" / "prod-values.yaml"
RUNBOOK_NOTE = REPO_ROOT / ".agents" / "notes" / "strata-host-prep-gpu-ai.md"
PARENT_README = CHART_DIR / "README.md"
CONTAINER_DIR = REPO_ROOT / "containers" / "strata"
STRATA_TEMPLATES_DIR = CHART_DIR / "templates"
RELEASE_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "release.yaml"
GITIGNORE = REPO_ROOT / ".gitignore"

# The retired standalone-chart dir. C02's repo grep (r2-C02 AC3) forbids live
# code paths from referencing it — this suite asserts that grep, so it must not
# itself contain the literal path string: the Path is COMPOSED, never written.
STANDALONE_CHART_DIR = REPO_ROOT / "charts" / "strata"
STANDALONE_CHART_PATH_TEXT = "charts" + "/" + "strata"

# --- r2-C01 chart interface ---------------------------------------------------
RELEASE = "gpu-ai-llama-swap"                 # the single Application/release
STRATA_OBJECT_NAME = "gpu-ai-llama-swap-strata"   # app-template fullname + controller key
NAMESPACE = "default"
CM_CONFIG = "strata-config"
CM_PROFILE = "strata-profile"

# Default-OFF is seven native data flags (plan architecture, prototype-verified):
# a partial set must fail loudly — an advancedMounts into a DISABLED controller
# hard-fails the render, which is why the persistence entries carry flags too.
SEVEN_FLAGS = (
    "app-template.controllers.strata.enabled=true",
    "app-template.service.strata.enabled=true",
    "app-template.persistence.strata-config.enabled=true",
    "app-template.persistence.strata-profile.enabled=true",
    "app-template.persistence.strata-kfd.enabled=true",
    "app-template.persistence.strata-dri.enabled=true",
    "app-template.persistence.strata-shm.enabled=true",
)
FLAG_PATHS = tuple(f.rsplit("=", 1)[0] for f in SEVEN_FLAGS)
# FLAG_PATHS carry the chart-root key path (already app-template.-prefixed) —
# the same string is BOTH the --set key (with =value appended in SEVEN_FLAGS)
# and the service-overlay dig path: overlay and chart gate path spelling must
# be IDENTICAL, and that identity is itself r2-C03's contract. Derived proper
# subsets for the divergence guards (--set needs key=value, never bare keys):
SEVEN_FLAGS_PERSISTENCE = SEVEN_FLAGS[2:]
SEVEN_FLAGS_CONTROLLER_SERVICE = SEVEN_FLAGS[:2]
CANONICAL_MISSING_CONTROLLER = re.compile(r"No enabled controller found with identifier")

# --- run-1 constants that survive consolidation (values re-keyed, facts not) --
PEER_NAME = "strata"
PRIMARY_ID = "qwen3.8-flash-next-strata"
STRIX_ID = "qwen3.8-flash-next-strata-strix"
PROFILE_PRIMARY_FILE = "strata-iq3_s.json"
PROFILE_STRIX_FILE = "strata-strix-iq3_s.json"

# C01 interface contract (containers/strata/README.md freezes these; the
# container itself is untouched by run 2 — RESEARCH §1).
SERVE_ENTRY = "/opt/strata/terminal/bin/strata"
ENGINE_ROOT = "/opt/strata/components/engine"
ENGINE_LABEL_RE = re.compile(r"^\d+\.\d+\.\d+-linux-x86_64-hip-(rx9070|halo)$")

# r2-C01 task: serve takes only these flags (run-1 RESEARCH §2); all engine
# tuning lives in the profile JSON.
SERVE_FLAGS = {"--profile", "--host", "--port"}

PRIMARY_ENV_FIVE = [
    "STRATA_PF_FUSED=1", "STRATA_PF_GEMM=1", "STRATA_PA_FAST=1",
    "STRATA_HIP_WMMA=1", "STRATA_SELECT_WMMA=1",
]

# run-1 RESEARCH §2 measured absence: the env var does not exist upstream; any
# appearance in chart/container surfaces is the card guide's misattribution.
VOID_ENV_TOKEN = "STRATA_KV_GROW_HOLD"

PRIMARY_FORBIDDEN_FLAGS = [
    "--resident-budget-gib", "--prompt-cache", "--kv-grow", "--vision",
    # --ple-io (any value): the engine default maps the 28.8 GiB n-gram
    # table from disk; setup's node-probed `ram` choice + the trio warm is
    # what OOM-killed the node 2026-10-29. Re-admitting it is a test-
    # session re-pin paired with a real capacity plan, not a silent edit.
    "--ple-io",
    # --kv-resident was listed under the run-1 reading of RESEARCH §5
    # ("batch-column item"); the generated run-config for THIS node proves
    # setup itself pairs it with --ple-io ram outside any --batch context
    # (2026-10-29 transplant), so it is baseline now, not forbidden.
]
# Baseline = the generated run-config (2026-10-29 transplant) PLUS the
# owner budget ruling of the same day: --prefill auto (machine-sized),
# Strata-data paths and --kv-resident required so a revert to the seed
# guesses goes red; --memory-limit-mib 92160 inside the 96Gi cgroup
# (#1601 pair); conversation-cache 32768 x 16 explicit. --mtp-window stays
# absent (toggle); --batch-mtp on neither list (one-at-a-time posture).
PRIMARY_REQUIRED_PAIRS = [
    ("--pack", "/models/strata/Strata-data/packs/iq3_s"),
    ("--native", "/models/strata/Strata-data/models/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf"),
    ("--expert-cache", "auto"),
    ("--max-context", "262144"),
    ("--kv", "int8"),
    ("--spec", "4"),
    ("--spec-min-p", "0.5"),
    ("--prefill", "auto"),
    ("--kv-resident", "32768"),
    # 2026-10-29 OOM pairing: a cgroup limit without the engine knowing it
    # gets the arena killed mid-pin; this pair is the #1601 contract (90 GiB
    # inside the 96Gi cgroup, owner budget ruling same day).
    ("--memory-limit-mib", "92160"),
    # Owner budget ruling 2026-10-29: 32 GiB parked-conversation budget,
    # 16 slots (IQ3_S full-256k park ~= 3.3 GiB of it).
    ("--conversation-cache-mib", "32768"),
    ("--conversation-cache-slots", "16"),
]
PRIMARY_REQUIRED_FLAGS = [
    "--pack", "--native", "--ple-gguf", "--expert-profile", "--mtp",
]

# run-1 RESEARCH §7 verbatim eight-set — spellings are upstream literals;
# normalizing them (case, prefixes) breaks the engine's env parsing.
STRIX_EIGHT_SET = [
    "STRATA_PF_FUSED=1", "STRATA_PF_GEMM=1", "STRATA_HC_UPMIX=1",
    "STRATA_PA_FAST=1", "STRATA_HIP_WMMA=1", "STRATA_SELECT_WMMA=1",
    "STRATA_PF_SWITCH_MIN_T=4096", "STRATA_PREFILL_STREAM_MIN=128",
]

# C-A keyless (r2 DECISIONS): "api_key": "none" is the shipped default in BOTH
# run-config profiles; the secret chain (ExternalSecret, bitwardenIds,
# ${env.STRATA_API_KEY}, secretKeyRef) is REMOVED, not guarded-off.
API_KEY_NONE = "none"
SECRET_CHAIN_TOKENS = [
    "strata-api-key", "STRATA_API_KEY", "PENDING-OPERATOR",
    "ExternalSecret", "secretKeyRef", "bitwarden",
]

# r2-C03 / evidence: the consolidated pod is a controller of THIS release, so
# the peers proxy flips to the app-prefixed Service name. Single source:
# evidence/strata-peers-expected.yaml — this constant mirrors it, and the
# wiring tests assert render==evidence, so drift between the two is loud.
PEERS_PROXY = f"http://{STRATA_OBJECT_NAME}.{NAMESPACE}.svc.cluster.local:8080"


# ---------------------------------------------------------------------------
# Environment gating
# ---------------------------------------------------------------------------


def env_ready() -> tuple[bool, str]:
    """Only TOOLING absence may skip a test; a missing render or failing helm
    run must stay RED and name its chunk."""
    if shutil.which("helm") is None:
        return False, "helm binary not on PATH (~/.local/bin/helm — export PATH; run-2 FRICTION)"
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
# Helm rendering (parent chart; OFF = defaults, ON = the seven flags)
# ---------------------------------------------------------------------------


def _values_file_arg(overlay: dict) -> list[str]:
    """Overlay values via a temp file (helm merges -f layers into chart
    values). File lives until the render completes — cleanup after run."""
    fd, p = tempfile.mkstemp(prefix="strata-test-", suffix=".yaml")
    with open(fd, "w") as fh:
        yaml.safe_dump(overlay, fh)
    return ["-f", p]


@functools.lru_cache(maxsize=None)
def _render_cached(release: str, sets_key: tuple, overlay_key: str) -> tuple:
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


DOMAIN_SET = ("domain=test.example.com",)


def render_off() -> tuple:
    """Default-OFF render — the exact plan-Commands command line."""
    return _render_cached(RELEASE, DOMAIN_SET, "")


def render_on(sets_extra: tuple = ()) -> tuple:
    """Fully ON render: domain + the seven flags (r2-C01 AC2)."""
    return _render_cached(RELEASE, DOMAIN_SET + SEVEN_FLAGS + sets_extra, "")


def render_on_overlay(overlay: dict, sets_extra: tuple = ()) -> tuple:
    """ON render with an extra values overlay (synthetic fixtures, e.g.
    rocrVisibleDevices retargets under the strata: values container)."""
    overlay_key = yaml.safe_dump(overlay, sort_keys=True)
    return _render_cached(RELEASE, DOMAIN_SET + SEVEN_FLAGS + sets_extra, overlay_key)


def render_subset(subset: tuple[str, ...]) -> tuple[int, str]:
    """Non-raising render with a PROPER SUBSET of the seven flags (plus
    domain): (returncode, stdout+stderr) — for the loud-fail guards."""
    cmd = ["helm", "template", RELEASE, str(CHART_DIR), "--set", "domain=test.example.com"]
    for f in subset:
        cmd += ["--set", f]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    return out.returncode, out.stdout + out.stderr


def service_strata_overlay() -> dict:
    doc = yaml.safe_load(SERVICE_VALUES.read_text())
    block = doc["llama-swap"]
    assert "strata" in block, (
        "services/gpu-ai/prod/values.yaml llama-swap block has no strata: sub-key — r2-C03 not landed"
    )
    return block["strata"]


def render_service_overlay(cluster: str = "gpu-ai") -> tuple:
    """Extract-and-render of the service's llama-swap block onto the parent
    chart under the REAL appset release name (gpu-ai-llama-swap). L.
    render_docs cannot serve here: it renders as release `llama-swap`, so
    every object name loses the cluster prefix — while the consolidated
    identity (gpu-ai-llama-swap-strata) the peers evidence pins IS what this
    render must produce. Returns (docs, raw stdout) for line-scoped scans."""
    block = yaml.safe_load(SERVICE_VALUES.read_text())["llama-swap"]
    docs_t, raw = _render_cached(RELEASE, DOMAIN_SET + (f"clusterName={cluster}",),
                                 yaml.safe_dump(block, sort_keys=True))
    return docs_t, raw


# ---------------------------------------------------------------------------
# Rendered-object extraction
# ---------------------------------------------------------------------------


def find_kind(docs, kind: str) -> list:
    return [d for d in docs if d.get("kind") == kind]


def by_name_kind(docs, kind: str, name: str):
    hits = [d for d in docs if d.get("kind") == kind
            and d.get("metadata", {}).get("name") == name]
    assert len(hits) == 1, f"{kind}/{name}: expected exactly one, got {len(hits)}"
    return hits[0]


def obj_ids(docs) -> set:
    return {(d.get("kind"), d.get("metadata", {}).get("name")) for d in docs}


def strata_pod(docs) -> dict:
    dep = by_name_kind(docs, "Deployment", STRATA_OBJECT_NAME)
    return dep["spec"]["template"]


def strata_container(docs) -> dict:
    return strata_pod(docs)["spec"]["containers"][0]


def strata_deployment(docs) -> dict:
    return by_name_kind(docs, "Deployment", STRATA_OBJECT_NAME)


def main_pod_containers(docs) -> dict[str, dict]:
    """Containers of the llama-swap MAIN pod, keyed by name — the mount-
    exactness comparison surface (r2-C01 AC3)."""
    pod = by_name_kind(docs, "Deployment", RELEASE)["spec"]["template"]
    return {c["name"]: c for c in pod["spec"]["containers"]}


def mount_triples(container: dict) -> list:
    return sorted((m["name"], m["mountPath"], bool(m.get("readOnly")))
                  for m in container.get("volumeMounts") or [])


def inner_config(docs) -> dict:
    cm = by_name_kind(docs, "ConfigMap", CM_CONFIG)
    return yaml.safe_load(cm["data"]["config.yaml"])


def profile_json(docs, filename: str) -> dict:
    """One run-config profile rendered VERBATIM as JSON (valid JSON is itself
    the red when it fails — run-1 AC5 lineage)."""
    cm = by_name_kind(docs, "ConfigMap", CM_PROFILE)
    assert filename in cm.get("data", {}), (
        f"ConfigMap {CM_PROFILE} has no data key {filename!r}; keys: {sorted(cm.get('data', {}))}"
    )
    return json.loads(cm["data"][filename])


def env_list(model: dict) -> list[str]:
    return [str(e) for e in (model.get("env") or [])]


def cmd_flag_tokens(cmd: str) -> list[str]:
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


def engine_exe_paths(text: str) -> set[str]:
    """Full exe paths of the contract form /opt/strata/components/engine/<label>/<binary>.
    The label dir is pinned; the FILENAME is whatever C01's build-log capture
    recorded in the container README — the seam tests compare chart literal to
    README literal, so nothing is invented here."""
    out = set()
    for m in re.finditer(
        re.escape(ENGINE_ROOT) + r"/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)", text
    ):
        if ENGINE_LABEL_RE.match(m.group(1)):
            out.add(f"{ENGINE_ROOT}/{m.group(1)}/{m.group(2)}")
    return out


# ---------------------------------------------------------------------------
# Matrix DSL expansion (r2-C01 inner solver alternation)
# ---------------------------------------------------------------------------
# llama-swap expands a set expression to DNF COMBOS: '&' joins vars into one
# combo, '|' alternates combos, '+name' inlines another set (skill: "(g | q |
# m) & v" → [g,v],[q,v],[m,v]; a combo listing two models admits their
# co-residency, only the requested model starts). Flat membership of the var
# references is the wrong bar for the (p | s) contract — that expression
# mentions both arenas while no combo may ever hold both.


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
    unresolved var token raises — the load-error class assert_matrix_closure
    pins for the outer config."""
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
# Vendored v266 config schema (re-homed with the suite from run-1's
# standalone-chart test directory)
# ---------------------------------------------------------------------------


def v266_schema() -> dict:
    """Load + integrity-check the vendored schema before use. Provenance
    guard mirrors scripts/converter-source.json's pattern (recorded digest).
    v266 = the deployed llama-swap pin's schema — main-only keys would
    false-fail (run-1 RESEARCH 'Validation')."""
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
    """Pre-cf-77 divergence pin (carried from run-1): the outer config's
    `performance.enable` key predates this ticket on both clusters and the
    cf-77 runs forbid touching that block, so the outer-config schema gate
    runs with the subtree carved out. Carve-out + peers-subtree validation
    together still prove every peers spelling."""
    out = json.loads(json.dumps(cfg))
    out.pop("performance", None)
    return out


# ---------------------------------------------------------------------------
# Values-source readers (comments are invisible in loaded data)
# ---------------------------------------------------------------------------


def values_region(text: str, key: str) -> str:
    """Raw source of one values key's block — from the key line to the next
    line at shallower-or-equal indent. Used where the WHY-comments THEMSELVES
    are contractual (toggles, VERIFY markers, runbook pointers)."""
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


def dig(d, path: str):
    """Walk a dotted key path through nested dicts; returns (found, value)."""
    cur = d
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return False, None
        cur = cur[part]
    return True, cur


def live_code_grep(needle: str) -> list[str]:
    """Repo-wide text search for `needle` over live surfaces only: services/,
    custom-values/, charts/, containers/, skills/, .github/. Excludes
    .agents/ (both plan folders are sanctioned history/plan references per
    r2-C02 AC3), the tests dir of THIS suite (its own negative pins embed
    needles), caches and binary/vendor blobs."""
    roots = [REPO_ROOT / p for p in
             ("services", "custom-values", "charts", "containers", "skills", ".github")]
    hits = []
    for root in roots:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            s = str(path)
            if (f"{os.sep}tests{os.sep}" in s or "__pycache__" in s
                    or path.suffix in {".tgz", ".pyc", ".gz"}):
                continue
            if needle in path.read_text(errors="replace"):
                hits.append(str(path.relative_to(REPO_ROOT)))
    return hits
