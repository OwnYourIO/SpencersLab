# Shared helpers for the charts/amd-gpu render-contract suite
# (2026-11-cf-143-feat-radiance-replaces-strata, C07; re-authored for the
# C08 T-A FIRST-PARTY conversion — DECISIONS D22 item 5 / D23, RESEARCH §R7).
#
# charts/amd-gpu was the D19 vendored fork of upstream 0.22.0 (+ the ~10-line
# args hook the released chart lacked). C08 converts it to a first-party
# app-template 5.0.1 chart: templates/ emptied (no _helpers.tpl, no NOTES.txt,
# no vendored DS), the pod expressed entirely from the app-template: values
# subtree, object-name byte-identity traded for a one-sync DS swap inside the
# flip wave (D23 strain). The shipped pod facts are UNCHANGED — the parity
# oracle is evidence/pre-c08-deviceplugin-ds.yaml (the vendored render,
# captured pre-conversion); the law is "parity, not improvement" (chunks/C08.md).

from __future__ import annotations

import functools
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

# ---------------------------------------------------------------------------
# GPU RESOURCE-NAME CONSTANTS — C08 OWNER LANE RULING LANDED (2026-11-12,
# mid-test-round amendment; DECISIONS D24 supersedes D23 names-stay). The
# rename is decided: table-mount lane → the R9700 pool is amd.com/gpu-r9700-1
# (§R7-Q2: the closest name ANY mechanism produces — the amd.com namespace and
# the gpu- prefix are CODE constants; the bare "gpu-r9700-1 minus gpu-"
# string the owner first asked is UNREACHABLE and must never appear as a
# claim). APU pool UNCHANGED; the overlay/peers/catalog/strata surfaces
# untouched by the ruling. The pre-C08 pool name is the HISTORICAL value —
# zero-stale AC4 sweeps it from charts/, services/, tests/ and .agents/notes/;
# it lives on only in pipeline records (DECISIONS/plan/TEST_SPEC/RESEARCH/git)
# and in this file ASSEMBLED so the sweep cannot trip on its own needle (the
# vllm_testlib LEGACY_REF precedent).
# This block + the marked blocks at tests/services/amd-gpu-naming.sh,
# tests/notes/radiance-runbook.sh and tests/notes/radiance-tp2.sh's tops are
# the ONLY name needles ticket-wide: any future lane change edits HERE, never
# needle archaeology. charts/radiance/tests/radiance_testlib.py and
# charts/llama-swap/tests/test_cf143_naming_flip.py resolve THIS module (the
# ledger's home chart is the names' single source).
GPU_RESOURCE_PREFIX = "amd.com/"                       # code constant (§R7-Q1)
R9700_POOL_NAME = "gpu-r9700-1"                       # THE ruling (D24); patched-table row
APU_POOL_NAME = "gpu-8060s"                           # frozen by the ruling scope
BARE_GPU_CLAIM = "amd.com/gpu"                        # gpu-cluster tree-global; never renames
R9700_CLAIM = GPU_RESOURCE_PREFIX + R9700_POOL_NAME
APU_CLAIM = GPU_RESOURCE_PREFIX + APU_POOL_NAME
# Pre-C08 pool name, assembled so no AC4-swept file ever carries it whole:
HISTORICAL_R9700_POOL_NAME = "gpu-ai-pro-" + "r9700"  # superseded-by-mount (D24)
# The plugin's const IDsPath the patched table mounts over (§R7-Q2; the
# Dockerfile COPY law is what makes the ConfigMap overlay effective):
IDS_PATH = "/usr/share/libdrm/amdgpu.ids"
IDS_TABLE_KEY = "amdgpu.ids"
# The sanitizer-traced product string for the 7551/C0 row (D24/§R7-Q2):
R9700_PRODUCT_STRING = "r9700-1"
# ---------------------------------------------------------------------------

# The vendored upstream identity (D23: HISTORY only — the conversion ends the
# refresh debt; the blob-identity legs (chart index digest, fork tag) died
# with the C08 re-author and are deliberately NOT asserted anymore).
PLUGIN_TAG = "1.31.0.12"
PLUGIN_REPO = "docker.io/rocm/k8s-device-plugin"
PLUGIN_AMD64_DIGEST_PREFIX = "sha256:6437c74f"        # §R6-Q5/§R6-S13 (amd64 manifest)

# The four plain args (§R7-Q5 ship facts): restated image CMD trio + the
# strategy arg. Declaring args DROPS the image CMD, so the trio must be
# restated verbatim; -v=5 is runbook-log-bearing (receipt (b) greps the
# enumeration logs — the D19 law survives as a values comment, C08 T-A).
CMD_RESTATED = ["-logtostderr=true", "-stderrthreshold=INFO", "-v=5"]
STRATEGY_FLAG = "-resource_naming_strategy=product"
ARGS_CONTRACT = CMD_RESTATED + [STRATEGY_FLAG]

# Name-targeting (D23 strain 1): either the live names are reproduced byte-
# identical (nameOverride + identifier where cheap), or the rename-set is
# enumerated in the values ledger. The oracle fixture carries the live truth.
# The selector value is historical-documentation only: app-template
# hardcodes the app.kubernetes.io triple (§R7-Q5), so no render ever
# reproduces it again — the coherence leg asserts selector SELF-coherence.
LIVE_DS_NAME = "amd-gpu-device-plugin-daemonset"
LIVE_SELECTOR_VALUE = "amd-gpu-dp-ds"          # historical (library-unreachable now)
LIVE_CONTAINER_NAME = "amd-gpu-dp-cntr"

# The expected-names ledger rows the values comment must carry (§R6-Q1).
# Same-line row form is the parse anchor n4 and amd_gpu_ledger_names() read —
# C08 T-A MOVES the block within values.yaml but KEEPS these anchors.
EXPECTED_NAME_LEDGER = [
    ("7551", "C0", R9700_POOL_NAME),
    ("1586", None, APU_POOL_NAME),   # revisions C1/C3/C6/D1 — one row suffices
]

CHART_DIR = Path(__file__).resolve().parent.parent      # charts/amd-gpu
TESTS_DIR = CHART_DIR / "tests"
REPO_ROOT = CHART_DIR.parent.parent
ORACLE = TESTS_DIR / "evidence" / "pre-c08-deviceplugin-ds.yaml"
TABLE_AUTHORITY = TESTS_DIR / "evidence" / "pre-c08-amdgpu-ids-rows.txt"


def table_authority() -> tuple[list, list, list]:
    """The fetched baked-table extract: (header_lines, version_line, rows).
    Fixture breakage is loud (test-session property); rows are byte-verbatim
    with their tabs — the parity legs compare exact strings, never fields."""
    assert TABLE_AUTHORITY.is_file(), (
        f"C08: table authority {TABLE_AUTHORITY} missing — fixture breakage, not a code red"
    )
    lines = TABLE_AUTHORITY.read_text().splitlines(keepends=True)
    start = next((i for i, ln in enumerate(lines) if ln.startswith("# List of AMDGPU IDs")), None)
    assert start is not None, "table authority lacks the format header ('# List of AMDGPU IDs')"
    content = lines[start:]

    def is_data(ln: str) -> bool:
        head = ln.split(",", 1)[0].strip()
        return len(head) == 4 and all(c in "0123456789abcdefABCDEF" for c in head)

    head = []
    version: list[str] = []
    rows = []
    for ln in content:
        if ln.startswith("#") or (ln.strip() == "" and not version):
            head.append(ln)
        elif is_data(ln):
            rows.append(ln)
        elif not version:
            version.append(ln)          # the bare "1.0.0" format-version line
    return head, version, rows


def sanitize_product(marketing: str) -> str:
    """Faithful mini-port of the plugin sanitizer (§R6-Q1/§R7-Q2 naming.go +
    products.go, the rules the JS port reproduced against upstream fixtures):
    strings.Fields on the marketing name, each token lowercased with
    non-[a-z0-9.-] -> '-', filler words {amd, ati, instinct, radeon,
    graphics, series} dropped (`pro`/`rx` deliberately KEPT — they are why
    the HISTORICAL constant above was derived), joined with '-', prefixed
    'gpu-', '--' collapsed, truncate at 63 after 'amd.com/'. This is the
    derivation engine the table legs run: rows are asserted by what the
    BINARY would advertise, not by string presence."""
    filler = {"amd", "ati", "instinct", "radeon", "graphics", "series"}
    kept = []
    for tok in marketing.split():
        t = tok.lower()
        t = "".join(ch if (ch.isalnum() or ch in ".-") else "-" for ch in t)
        if t and t not in filler:
            kept.append(t)
    out = "gpu-" + "-".join(kept)
    while "--" in out:
        out = out.replace("--", "-")
    out = out.strip("-.")
    return out[:63]


def helm_ready() -> tuple[bool, str]:
    # Binary check ONLY (the vllm_testlib law): a missing chart/dependency is
    # implementation state — the render legs must RED naming C08, not skip
    # (repo mass-skip trap, EXPLORE §4; the app-template tgz is asserted by
    # test_provenance, and the fresh-tree dep trap is the FRICTION §12 law).
    if shutil.which("helm") is None:
        return False, ("helm binary not on PATH (~/.local/bin/helm — export PATH; "
                       "without it the helm-guarded tests skip silently, EXPLORE §4)")
    return True, ""


def chart_values_text() -> str:
    path = CHART_DIR / "values.yaml"
    assert path.is_file(), (
        "C08: charts/amd-gpu/values.yaml missing — the chart values are not on this tree"
    )
    return path.read_text()


def chart_values() -> dict:
    return yaml.safe_load(chart_values_text())


def chart_meta() -> dict:
    path = CHART_DIR / "Chart.yaml"
    assert path.is_file(), "C08: charts/amd-gpu/Chart.yaml missing"
    return yaml.safe_load(path.read_text())


def chart_meta_text() -> str:
    path = CHART_DIR / "Chart.yaml"
    assert path.is_file(), "C08: charts/amd-gpu/Chart.yaml missing"
    return path.read_text()


# --- the parity oracle (pre-c08 vendored render; test-session capture) ----------


def _load_oracle() -> tuple[dict, list]:
    assert ORACLE.is_file(), (
        f"C08: parity oracle {ORACLE} missing — fixture breakage, not a code red "
        "(test-session property, captured at eef04f9c3 before the conversion)"
    )
    docs = [d for d in yaml.safe_load_all(ORACLE.read_text()) if d]
    assert len(docs) == 2 and isinstance(docs[0].get("observed_kinds"), list) \
        and docs[1].get("kind") == "DaemonSet", \
        f"C08: parity oracle {ORACLE} malformed (want kinds-projection doc + DaemonSet doc), got {[type(d) for d in docs]}"
    return docs[1], docs[0]["observed_kinds"]


def oracle_ds() -> dict:
    ds, _ = _load_oracle()
    return ds


def oracle_kinds() -> list:
    _, kinds = _load_oracle()
    return kinds


# --- rendering -------------------------------------------------------------------


@functools.lru_cache(maxsize=None)
def _render_cached(overlay_json: str) -> tuple:
    """(docs, raw stdout) of `helm template amd-gpu charts/amd-gpu` with an
    optional -f overlay file written from the JSON-packed YAML string."""
    import json

    cmd = ["helm", "template", "amd-gpu", str(CHART_DIR),
           "--set", "domain=spencerslab.com", "--set", "clusterName=gpu-ai"]
    with tempfile.TemporaryDirectory(prefix="amdgpu-test-") as tmp:
        if overlay_json:
            ov = Path(tmp) / "ov.yaml"
            ov.write_text(json.loads(overlay_json))
            cmd += ["-f", str(ov)]
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if out.returncode != 0:
            raise AssertionError(
                "C08: helm template charts/amd-gpu failed (a missing app-template "
                f"dependency means `helm dependency update charts/amd-gpu` — fresh-tree "
                f"law):\n{out.stderr}"
            )
        docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
        return docs, out.stdout


def render(overlay_yaml: str = "") -> tuple:
    """docs, raw stdout. overlay_yaml (when given) is written as a -f file —
    the values-level experiment surface (e.g. app-template toggles)."""
    return _render_cached(json.dumps(overlay_yaml) if overlay_yaml else "")


# --- extraction (name-agnostic post-conversion; the name legs are separate) ------


def docs_kinds(docs) -> list:
    return sorted(f"{d['kind']}/{d['metadata']['name']}" for d in docs)


def daemonset(docs) -> dict:
    dss = [d for d in docs if d.get("kind") == "DaemonSet"]
    assert len(dss) == 1, f"C08: expected exactly one DaemonSet rendered, got {[d['metadata']['name'] for d in dss]}"
    return dss[0]


def dp_container(docs) -> dict:
    """The plugin container, found by the SINGLE-container invariant (the
    name is a D23 strain target — legs that care about the name assert it
    separately via test_live_names_coherent)."""
    spec = daemonset(docs)["spec"]["template"]["spec"]
    ctrs = spec["containers"]
    assert len(ctrs) == 1, f"C08: expected one plugin container, got {[c.get('name') for c in ctrs]}"
    return ctrs[0]


def pod_spec(docs) -> dict:
    return daemonset(docs)["spec"]["template"]["spec"]


def amd_gpu_ledger_names() -> dict:
    """The device->pool map from the chart's expected-names ledger comment
    (C07 authority, C08 T-A: SAME strings, file structure may move — the
    read is line-scoped so the app-template rewrite cannot break it).
    Returns {device-id: sanitized-name-without-prefix} for comment lines
    pairing 7551/1586 with a gpu-* token."""
    out: dict[str, str] = {}
    for ln in chart_values_text().splitlines():
        if not ln.lstrip().startswith("#"):
            continue
        m = re.search(r"(amd\.com/)?(gpu-[a-z0-9][a-z0-9.-]*)", ln)
        if not m:
            continue
        for device in ("7551", "1586"):
            if device in ln and device not in out:
                out[device] = m.group(2)
    return out
