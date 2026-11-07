# Shared helpers for the charts/vllm render-contract suite
# (2026/2026-11-cf-105-feat-implement-vllm — C02).
#
# Contract surface (plan "Commands"): the service-level render is produced
# with the documented extract-and-render pattern — the `vllm:` subtree of
# services/gpu-ai/prod/values.yaml dumped to a file and overlaid with -f,
# plus --set domain/clusterName (the appset injects those as top-level
# values). A second render uses the appset release name `gpu-ai-vllm`
# because the peer-hop DNS name (AC3) only resolves under that release name.
#
# Everything here is designed-red at test-write time: charts/vllm does not
# exist yet, so every render and values read below fails naming C02.

from __future__ import annotations

import functools
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml

CHART_DIR = Path(__file__).resolve().parent.parent  # charts/vllm
REPO_ROOT = CHART_DIR.parent.parent
SERVICE_VALUES = REPO_ROOT / "services" / "gpu-ai" / "prod" / "values.yaml"
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "vllm-render-tests.yaml"

# The D4 serve recipe (plan locked decision D4, HR3 re-scoped): exact flag
# order and values. The MODEL placeholder is substituted with the
# values-driven modelPath.
D4_RECIPE = [
    ("--model", "MODEL"),
    ("--served-model-name", "qwen3.8-27b-vllm"),
    ("--scheduling-policy", "priority"),
    ("--max-model-len", "262144"),
    ("--max-num-seqs", "4"),
    ("--kv-cache-dtype", "fp8"),
    ("--gpu-memory-utilization", "0.95"),
    ("--enable-prefix-caching", None),
    ("--language-model-only", None),
    ("--enforce-eager", None),
    ("--watermark", "0.05"),
    ("--enable-sleep-mode", None),
    ("--disable-access-log-for-endpoints", "/health,/metrics,/ping"),
]

# The known Q4 GGUF location (RESEARCH Post Research V3: the live
# qwen3.8-27b-q4 rung's file, unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL,
# -hf auto-fetched by llama.cpp at the LLAMA_CACHE=/models root — no
# hub/ segment, that is the HUGGINGFACE_HUB_CACHE convention, not
# llama.cpp's). The values pin the live snapshot hash (discovered on
# target 2026-11-07), so the contract is layout + exact filename, never
# the full path.
MODEL_PREFIX = "/models/models--unsloth--Qwen3.8-27B-GGUF/snapshots/"
MODEL_FILENAME = "Qwen3.8-27B-UD-Q4_K_XL.gguf"

# Probe ports may render as the numeric 8000 or the named container port
# "http" — the name is bound to 8000 by the containerPort contract
# (test_render), so both forms hit the same endpoint.
PROBE_PORT_OK = (8000, "http")


def helm_ready() -> tuple[bool, str]:
    # Binary check ONLY: an absent helm is an environment skip, but a missing
    # chart is implementation state — render tests must RED naming C02, not
    # skip (the mass-skip trap of the repo's helm-guarded suites, EXPLORE §4;
    # the app-template tgz is asserted by test_contract, not gated here).
    if shutil.which("helm") is None:
        return False, ("helm binary not on PATH (~/.local/bin/helm — export PATH; "
                       "without it the helm-guarded tests skip silently, EXPLORE §4)")
    return True, ""


def chart_values() -> dict:
    path = CHART_DIR / "values.yaml"
    assert path.is_file(), "C02: charts/vllm/values.yaml missing — the chart is not implemented yet"
    return yaml.safe_load(path.read_text())


def service_vllm_block() -> dict:
    data = yaml.safe_load(SERVICE_VALUES.read_text())
    block = data.get("vllm")
    assert block is not None, (
        "C02: services/gpu-ai/prod/values.yaml has no top-level vllm: block "
        "— the ApplicationSet values block is not implemented yet"
    )
    return block


@functools.lru_cache(maxsize=None)
def _render_cache(release: str, service: bool, extra: str) -> tuple:
    with tempfile.TemporaryDirectory(prefix="vllm-test-") as tmp:
        cmd = [
            "helm", "template", release, str(CHART_DIR),
            "--set", "domain=spencerslab.com",
            "--set", "clusterName=gpu-ai",
        ]
        if service:
            vals = Path(tmp) / "vals.yaml"
            with vals.open("w") as fh:
                yaml.safe_dump(service_vllm_block(), fh)
            cmd += ["-f", str(vals)]
        if extra:
            cmd += extra.split()
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if out.returncode != 0:
            raise AssertionError(
                f"C02: helm template failed (release={release}, service={service}):\n{out.stderr}"
            )
        docs = tuple(d for d in yaml.safe_load_all(out.stdout) if d)
        return docs, out.stdout


def render(release: str = "vllm", service: bool = True, extra_set: str = ""):
    """(docs, raw stdout) of one render; raises AssertionError on helm failure."""
    return _render_cache(release, service, extra_set)


def deployment(docs) -> dict:
    deploys = [d for d in docs if d.get("kind") == "Deployment"]
    assert deploys, "C02: no Deployment rendered"
    assert len(deploys) == 1, f"C02: expected one Deployment, got {[d['metadata']['name'] for d in deploys]}"
    return deploys[0]


def main_container(deploy: dict) -> dict:
    containers = deploy["spec"]["template"]["spec"].get("containers", [])
    for c in containers:
        if c.get("name") == "vllm":
            return c
    raise AssertionError(f"C02: no container named 'vllm'; got {[c.get('name') for c in containers]}")


def pod_template(deploy: dict) -> dict:
    return deploy["spec"]["template"]


def env_map(container: dict) -> dict:
    return {e["name"]: e.get("value") for e in container.get("env", [])}


def services(docs) -> list:
    return [d for d in docs if d.get("kind") == "Service"]


def persistent_volume_claims(docs) -> list:
    return [d for d in docs if d.get("kind") == "PersistentVolumeClaim"]


def assert_model_path_shape(path, label: str) -> None:
    assert isinstance(path, str) and path.startswith(MODEL_PREFIX), (
        f"C02: {label} --model path {path!r} must live under the LLAMA_CACHE-root "
        f"snapshot layout {MODEL_PREFIX} (the 500 GiB weights PVC, RESEARCH Post Research V3)"
    )
    assert path.endswith(MODEL_FILENAME), (
        f"C02: {label} --model path {path!r} must name the known Q4 GGUF file {MODEL_FILENAME}"
    )


def flag_pairs(args: list) -> list:
    """Rendered args as ordered [(flag, value|None), ...]. `--flag=value`
    splits on the first =; a following non-flag token is the value; a
    trailing/---prefixed successor makes the flag boolean."""
    out = []
    i = 0
    while i < len(args):
        tok = args[i]
        if not tok.startswith("--"):
            i += 1
            continue
        if "=" in tok:
            flag, val = tok.split("=", 1)
            out.append((flag, val))
            i += 1
        elif i + 1 < len(args) and not args[i + 1].startswith("--"):
            out.append((tok, args[i + 1]))
            i += 2
        else:
            out.append((tok, None))
            i += 1
    return out


def expected_recipe(model_path: str) -> list:
    return [(flag, model_path if value == "MODEL" else value)
            for flag, value in D4_RECIPE]


def grafana_annotations(deploy: dict) -> dict:
    ann = (pod_template(deploy).get("metadata") or {}).get("annotations") or {}
    return {k: v for k, v in ann.items() if k.startswith("k8s.grafana.com/")}
