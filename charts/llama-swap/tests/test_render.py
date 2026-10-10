# Helm-render contract tests for the llama-swap chart changes:
#   - tools sidecar absent by default, present when enabled
#   - ExternalSecret absent without bitwardenIds, present with
#   - PVC renders 300Gi by default and honors modelsPvcSize
#
# Skipped when the helm binary or the chart's app-template dependency is
# missing (run `helm dependency update charts/llama-swap` first; the GitHub
# workflow does).

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

CHART_DIR = Path(__file__).resolve().parent.parent

pytestmark = pytest.mark.skipif(
    shutil.which("helm") is None or not list(CHART_DIR.glob("charts/app-template-*.tgz")),
    reason="helm binary or app-template dependency not available",
)


def helm_template(extra: list[str] | None = None) -> list[dict]:
    cmd = ["helm", "template", "llama-swap", str(CHART_DIR),
           "--set", "domain=spencerslab.com", "--set", "clusterName=test"]
    if extra:
        cmd += extra
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, f"helm template failed:\n{out.stderr}"
    docs = [d for d in yaml.safe_load_all(out.stdout) if d]
    return docs


def by_kind_name(docs, kind, name):
    return [d for d in docs
            if d.get("kind") == kind and d.get("metadata", {}).get("name") == name]


def deployment(docs):
    deps = [d for d in docs if d.get("kind") == "Deployment"]
    assert len(deps) == 1
    return deps[0]


def container_names(dep):
    return [c["name"] for c in dep["spec"]["template"]["spec"]["containers"]]


# ---------------------------------------------------------------------------
# Defaults (gpu-style render: no bitwardenIds, no overrides)
# ---------------------------------------------------------------------------

def test_default_no_externalsecret_no_tools_container():
    docs = helm_template()
    assert not by_kind_name(docs, "ExternalSecret", "hf-token"), \
        "ExternalSecret must not render without bitwardenIds.hf-token"
    dep = deployment(docs)
    assert container_names(dep) == ["main"]


def test_default_pvc_300gi():
    docs = helm_template()
    pvc = by_kind_name(docs, "PersistentVolumeClaim", "llama-swap")
    assert len(pvc) == 1
    assert pvc[0]["spec"]["resources"]["requests"]["storage"] == "300Gi"


def test_default_tools_configmap_mounted_readonly():
    docs = helm_template()
    dep = deployment(docs)
    main = dep["spec"]["template"]["spec"]["containers"][0]
    mounts = {m["mountPath"]: m for m in main.get("volumeMounts", [])}
    assert "/app/tools" in mounts and mounts["/app/tools"].get("readOnly") is True

    cm = by_kind_name(docs, "ConfigMap", "llama-swap-tools")
    assert len(cm) == 1
    keys = set(cm[0]["data"])
    assert "llama_tools.py" in keys and "convert_lora_to_gguf.py" in keys
    assert {"conversion__init__.py", "conversion__base.py", "conversion__qwen.py"} <= keys
    assert {"gguf_py__init__.py", "gguf_py__constants.py",
            "gguf_py__gguf_writer.py", "gguf_py__tensor_mapping.py"} <= keys, \
        "b10015 converter needs the repo-local gguf-py (PyPI gguf is too old)"
    # the vendored converter must actually be embedded, not empty
    assert "def parse_args" in cm[0]["data"]["convert_lora_to_gguf.py"]
    assert "ModelBase" in cm[0]["data"]["conversion__base.py"]
    assert "MODEL_ARCH" in cm[0]["data"]["gguf_py__constants.py"]


# ---------------------------------------------------------------------------
# gpu-ai-style render (bitwardenIds + tools enabled + 500Gi)
# ---------------------------------------------------------------------------

GPU_AI_VALUES = """
modelsPvcSize: 500Gi
bitwardenIds:
  hf-token: 00000000-0000-0000-0000-000000000000
app-template:
  controllers:
    llama-swap:
      containers:
        main:
          env:
            HF_TOKEN:
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: token
        tools:
          enabled: true
          env:
            HF_TOKEN:
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: token
"""


@pytest.fixture()
def gpu_ai_values(tmp_path):
    f = tmp_path / "gpu-ai-values.yaml"
    f.write_text(GPU_AI_VALUES)
    return str(f)


def test_gpu_ai_externalsecret_renders_with_uuid(gpu_ai_values):
    docs = helm_template(["-f", gpu_ai_values])
    es = by_kind_name(docs, "ExternalSecret", "hf-token")
    assert len(es) == 1
    ref = es[0]["spec"]["data"][0]["remoteRef"]
    assert ref["key"] == "00000000-0000-0000-0000-000000000000"
    assert ref["property"] == "password"
    assert es[0]["spec"]["target"]["name"] == "hf-token"


def test_gpu_ai_tools_container_enabled_with_token(gpu_ai_values):
    docs = helm_template(["-f", gpu_ai_values])
    dep = deployment(docs)
    names = container_names(dep)
    assert names == ["main", "tools"]

    tools = next(c for c in dep["spec"]["template"]["spec"]["containers"] if c["name"] == "tools")
    assert tools["image"] == "python:3.12.15-slim-bookworm"
    assert tools["command"] == ["sleep", "infinity"]
    env = {e["name"]: e for e in tools.get("env", [])}
    assert env["HF_TOKEN"]["valueFrom"]["secretKeyRef"] == {"name": "hf-token", "key": "token"}
    caps = tools["securityContext"]["capabilities"]["drop"]
    assert "ALL" in caps
    assert tools.get("resources", {}).get("limits", {}).get("amd.com/gpu") is None, \
        "tools sidecar must not request the GPU"

    main = next(c for c in dep["spec"]["template"]["spec"]["containers"] if c["name"] == "main")
    main_env = {e["name"]: e for e in main.get("env", [])}
    assert "HF_TOKEN" in main_env, "gated -hf repos need the token on main too"

    # /models reaches the tools container via globalMounts
    tools_mounts = {m["mountPath"] for m in tools.get("volumeMounts", [])}
    assert "/models" in tools_mounts and "/app/tools" in tools_mounts


def test_gpu_ai_pvc_500gi(gpu_ai_values):
    docs = helm_template(["-f", gpu_ai_values])
    pvc = by_kind_name(docs, "PersistentVolumeClaim", "llama-swap")
    assert pvc[0]["spec"]["resources"]["requests"]["storage"] == "500Gi"


def test_no_sentinels_render(gpu_ai_values):
    for extra in ([], ["-f", gpu_ai_values]):
        cmd = ["helm", "template", "llama-swap", str(CHART_DIR),
               "--set", "domain=spencerslab.com", "--set", "clusterName=test"] + extra
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        assert "OVERRIDE_VIA" not in out.stdout
