# C02 trio contract (2026/2026-11-cf-105-feat-implement-vllm —
# chunks/C02.md AC5 + the plan trio greps): the gpu-ai ApplicationSet entry is
# exact, the service-level `vllm:` block carries the two documented overrides,
# the trio proxy leg is deliberately skipped with a ruling comment, and the
# two sibling surfaces that must stay untouched (custom-values/gpu-ai and
# services/gpu) carry zero vllm keys. Pure file reads — no helm needed — and
# all designed-red at test-write time: the `vllm:` block and the charts entry
# do not exist yet.

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

import vllm_testlib as V

SERVICE = V.SERVICE_VALUES


def _svc() -> dict:
    assert SERVICE.is_file(), f"C02: {SERVICE} missing"
    return yaml.safe_load(SERVICE.read_text())


def test_trio_charts_vllm_entry_is_exact():
    charts = _svc().get("charts") or {}
    entry = charts.get("vllm")
    assert entry is not None, "C02 AC5: charts: entry for vllm missing from services/gpu-ai/prod/values.yaml"
    assert entry == {"namespace": "default", "ServerSideApply": "false"}, (
        f"C02 AC5: charts.vllm must be exactly {{namespace: default, ServerSideApply: \"false\"}}, got {entry}"
    )


def test_trio_vllm_block_carries_the_two_overrides():
    block = _svc().get("vllm")
    assert isinstance(block, dict), "C02 AC5: no top-level vllm: values block in services/gpu-ai/prod/values.yaml"
    sub = block.get("app-template")
    assert isinstance(sub, dict), (
        "C07 AC5: the vllm: block must nest its overrides under app-template: (the repo "
        "app-template idiom — C02's top-level shape is void, owner ruling 2026-11-06)"
    )
    # modelPath pinned to the actual q4 GGUF path on the PVC (C02 task).
    model_path = sub.get("modelPath")
    V.assert_model_path_shape(model_path, "service vllm block")
    # rocrVisibleDevices "0" = R9700 (D2); a values key so the template never changes.
    assert str(sub.get("rocrVisibleDevices")) == "0", (
        f"C02 AC5: vllm block app-template.rocrVisibleDevices must be \"0\" (R9700), got {sub.get('rocrVisibleDevices')!r}"
    )


def test_trio_no_proxy_subdomain_vllm():
    subs = ((_svc().get("ingress") or {}).get("subdomains")) or {}
    assert "vllm" not in subs, (
        "C02 AC5: ingress.subdomains.vllm must NOT exist — the trio proxy leg is skipped (internal-only, D7/Q4)"
    )


def test_trio_skip_ruling_comment_present():
    """The proxy-leg skip must be documented where the reader looks for the
    host: a comment inside the ingress/subdomains block naming vllm (the
    strata Q4 precedent at the top of that block)."""
    lines = SERVICE.read_text().splitlines()
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^\s*subdomains:\s*$", ln):
            start = i + 1
            break
    assert start is not None, "C02: no ingress.subdomains: block found to search for the skip-ruling comment"
    region = []
    for ln in lines[start:]:
        if re.match(r"^[^\s#]", ln):  # next top-level key ends the ingress block
            break
        region.append(ln)
    hits = [ln for ln in region if ln.lstrip().startswith("#") and "vllm" in ln.lower()]
    assert hits, (
        "C02 AC5: the ingress.subdomains block carries no comment explaining the vllm skip "
        "(internal-only per D7/Q4 — the strata Q4 precedent comment shape)"
    )


@pytest.mark.parametrize("target", [
    "custom-values/gpu-ai/prod-values.yaml",
    "services/gpu/prod/values.yaml",
], ids=["custom-values/gpu-ai", "services/gpu"])
def test_trio_sibling_surfaces_stay_vllm_free(target):
    path = V.REPO_ROOT / target
    assert path.is_file(), f"C02: {target} missing (expected to exist and stay untouched)"
    blob = path.read_text()
    assert "vllm" not in blob.lower(), (
        f"C02 AC5: {target} must stay byte-unchanged by this ticket (no secrets, 8 GiB box untouched) — "
        f"found a vllm reference"
    )
