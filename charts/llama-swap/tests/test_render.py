# Helm-render contract tests for the llama-swap chart changes:
#   - tools sidecar absent by default, present when enabled
#   - ExternalSecret absent without bitwardenIds, present with
#   - PVC renders 300Gi by default and honors modelsPvcSize
#
# Skipped when the helm binary or the chart's app-template dependency is
# missing (run `helm dependency update charts/llama-swap` first; the GitHub
# workflow does).

from __future__ import annotations

import json
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
    # ONLY the operator CLI + the provenance pin are embedded. The vendored
    # b11515 converter closure (~870 KiB) must stay out of the ConfigMap:
    # the chart is applied client-side, so kubectl mirrors the whole object
    # into the last-applied-configuration annotation, which the API server
    # caps at 256 KiB ("metadata.annotations: Too long" — the exact failure
    # this guard exists for). `prepare` fetches the pinned files instead.
    assert keys == {"llama_tools.py", "converter-source.json"}, keys
    assert "def main" in cm[0]["data"]["llama_tools.py"]
    assert "CONVERTER_FILES" not in cm[0]["data"]["llama_tools.py"], \
        "the flat-key embedding map must not come back"

    prov = json.loads(cm[0]["data"]["converter-source.json"])
    assert prov["tag"] == "b11515"
    assert "convert_lora_to_gguf.py" in prov["files"]
    assert prov["raw_url_pattern"].startswith("https://raw.githubusercontent.com/")

    # Hard regression guard: keep the ConfigMap far below the 256 KiB
    # annotation ceiling (and the 1 MiB etcd object limit).
    total = sum(len(k.encode()) + len(v.encode()) for k, v in cm[0]["data"].items())
    assert total < 200_000, f"tools ConfigMap grew to {total} bytes — syncs will break"


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
