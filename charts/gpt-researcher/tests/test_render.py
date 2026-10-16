# Helm-render contract tests for the gpt-researcher chart:
#   - every path of templates/ingress-backend.yaml targets a Service
#     name+port the chart actually renders (Kubernetes does not validate
#     Ingress backends, so a values.yaml rename would otherwise 502 at
#     runtime with every layer of CI green)
#   - the backend ingress host is the top-level research.<domain> (matches
#     the umbrella generic-ingress `research` entry, user decision 2026-10-13)
#   - the frontend service exposes the port the umbrella generic-ingress
#     `research` entry expects
#   - the backend container carries the lab wiring (llama-swap LLMs,
#     SearXNG retriever, LOCAL embeddings)
#
# Skipped when the helm binary or the chart's app-template dependency is
# missing (run `helm dependency update charts/gpt-researcher` first; the
# GitHub workflow does).

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

CHART_DIR = Path(__file__).resolve().parent.parent
RELEASE_NAME = "dev-gpt-researcher"

pytestmark = pytest.mark.skipif(
    shutil.which("helm") is None or not list(CHART_DIR.glob("charts/app-template-*.tgz")),
    reason="helm binary or app-template dependency not available",
)


def helm_template(extra: list[str] | None = None) -> list[dict]:
    cmd = ["helm", "template", RELEASE_NAME, str(CHART_DIR),
           "--set", "domain=scifi.farm", "--set", "clusterName=dev"]
    if extra:
        cmd += extra
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    assert out.returncode == 0, f"helm template failed:\n{out.stderr}"
    return [d for d in yaml.safe_load_all(out.stdout) if d]


def services(docs):
    return {d["metadata"]["name"]: d for d in docs if d.get("kind") == "Service"}


def by_kind_name(docs, kind, name):
    return [d for d in docs
            if d.get("kind") == kind and d.get("metadata", {}).get("name") == name]


def service_ports(svc):
    return {p["port"] for p in svc["spec"]["ports"]}


def backend_ingress(docs):
    matches = [d for d in docs if d.get("kind") == "Ingress"
               and d["metadata"]["name"] == "gpt-researcher-backend-ingress"]
    assert len(matches) == 1
    return matches[0]


def test_ingress_backend_targets_rendered_service():
    docs = helm_template()
    svcs = services(docs)
    paths = backend_ingress(docs)["spec"]["rules"][0]["http"]["paths"]
    assert paths, "backend ingress renders no paths"
    for p in paths:
        backend = p["backend"]["service"]
        name, port = backend["name"], backend["port"]["number"]
        assert name in svcs, (
            f"ingress path {p['path']} targets unknown Service {name!r}; "
            f"rendered Services: {sorted(svcs)}")
        assert port in service_ports(svcs[name]), (
            f"ingress path {p['path']} targets {name}:{port}, but that "
            f"Service exposes {sorted(service_ports(svcs[name]))}")


def test_backend_ingress_host_is_top_level():
    docs = helm_template()
    ingress = backend_ingress(docs)
    host = ingress["spec"]["rules"][0]["host"]
    # Same host as the umbrella generic-ingress `research` entry:
    # top-level <name>.<domain> (NOT cluster-scoped since 2026-10-13).
    assert host == "research.scifi.farm"
    # Top-level hosts are covered by wildcard-cert (*.scifi.farm).
    assert ingress["spec"]["tls"][0]["secretName"] == "wildcard-cert"
    assert ingress["spec"]["tls"][0]["hosts"] == ["research.scifi.farm"]


def test_frontend_service_matches_umbrella_ingress_entry():
    # services/dev/prod routes the `research` subdomain at
    # dev-gpt-researcher:3000.
    docs = helm_template()
    svcs = services(docs)
    assert RELEASE_NAME in svcs
    assert 3000 in service_ports(svcs[RELEASE_NAME])


def test_backend_container_lab_env():
    docs = helm_template()
    deps = [d for d in docs if d.get("kind") == "Deployment"]
    assert len(deps) == 1
    containers = {c["name"]: c
                  for c in deps[0]["spec"]["template"]["spec"]["containers"]}
    env = {e["name"]: e for e in containers["backend"]["env"]}
    assert env["RETRIEVER"]["value"] == "searx"
    # Embeddings run locally in the backend image — llama-swap serves no
    # embedding model.
    assert str(env["EMBEDDING"]["value"]).startswith("huggingface:")
    for key in ("FAST_LLM", "SMART_LLM", "STRATEGIC_LLM"):
        assert str(env[key]["value"]).startswith("openai:")


def test_backend_endpoints_come_from_secret():
    # The lab endpoints are composed from the cluster's domain into a
    # chart-rendered Secret and reach the container via secretKeyRef
    # (user decisions 2026-10-12/13). Rendered here with domain=scifi.farm.
    docs = helm_template()
    secrets = by_kind_name(docs, "Secret", "gpt-researcher-endpoints")
    assert len(secrets) == 1
    string_data = secrets[0]["stringData"]
    assert string_data["OPENAI_BASE_URL"] == "https://llama.scifi.farm/v1"
    assert string_data["SEARX_URL"] == "https://searxng.scifi.farm"

    deps = [d for d in docs if d.get("kind") == "Deployment"]
    env = {e["name"]: e for e in deps[0]["spec"]["template"]["spec"]["containers"][0]["env"]}
    for key in ("OPENAI_BASE_URL", "SEARX_URL"):
        ref = env[key]["valueFrom"]["secretKeyRef"]
        assert ref["name"] == "gpt-researcher-endpoints"
        assert ref["key"] == key
