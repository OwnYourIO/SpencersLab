# C02 trio contract (born 2026/2026-11-cf-105-feat-implement-vllm —
# chunks/C02.md AC5 + the plan trio greps; cf-131 C02 reworded the modelPath
# leg to the raw-release dir law): the gpu-ai ApplicationSet entry is
# exact, the service-level `vllm:` block carries the two documented overrides
# and nothing else, the trio proxy leg is deliberately skipped with a ruling
# comment, and the two sibling surfaces that must stay untouched
# (custom-values/gpu-ai and services/gpu) carry zero vllm keys. Pure file reads — no helm needed — and
# all designed-red at test-write time: the `vllm:` block and the charts entry
# do not exist yet.
#
# cf-143 C01 era inversion (2026-11-11, owner Q3 — the vllm lane, charts/vllm
# being the magiccodingman/vllm-radiance FORK, NOT the cf-143 radiance
# engine, is disabled COMMENTED-OUT one-edit-reversible): the two
# enable-era-shape legs flip to the DISABLED shapes of chunks/C01.md AC1 —
# the charts entry ABSENT live with its exact trio preserved commented +
# cf-143 marked, the top-level `vllm` key live as the explicit EMPTY flow map
# with its two overrides commented underneath. The skip-comment leg, the
# no-subdomain leg and the sibling-surface HOLDs are era-neutral and stay
# byte-untouched. Re-enable = these arms flip back with the uncomment
# (the commented shapes they now pin ARE the re-enable recipe).

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
    """cf-143 C01 AC1 (era inversion of the C02 AC5 exact-entry leg): the
    live charts map has NO vllm key — the entry is commented out with its
    exact {namespace, ServerSideApply} shape and a cf-143 marker preserved
    one line above the block (locate-and-uncomment re-enable, owner Q3)."""
    charts = _svc().get("charts") or {}
    assert "vllm" not in charts, (
        "cf-143 C01 AC1: charts.vllm is a live entry — the disable must go through the "
        "commented shape (reversible per owner Q3), not a live/delete flip"
    )
    text = SERVICE.read_text()
    m = re.search(r"(?ms)^  # vllm:\n((?:^  #.*\n?)+)", text)
    assert m, (
        "cf-143 C01 AC1: no commented '# vllm:' entry block found under charts: — the "
        "supersession keeps the block, it does not delete it"
    )
    block = m.group(1)
    assert re.search(r"^\s*#\s*namespace:\s*default\s*$", block, re.M), (
        f"cf-143 C01 AC1: the commented entry lost its namespace leg: {block!r}"
    )
    assert re.search(r'^\s*#\s*ServerSideApply:\s*"false"\s*$', block, re.M), (
        f"cf-143 C01 AC1: the commented entry lost the ServerSideApply \"false\" leg "
        f"(the gotcha-6 llama-swap-family pin must survive commented for the re-enable): {block!r}"
    )
    region = text[max(0, m.start() - 900): m.start()]
    assert "cf-143" in region, (
        "cf-143 C01 AC7: the commented charts.vllm entry carries no cf-143 marker within the "
        "(the disable site must be grep-findable for the re-enable)"
    )


def test_trio_vllm_block_carries_the_two_overrides():
    """cf-143 C01 AC1 (era inversion): the top-level `vllm:` block is the
    explicit EMPTY flow map — parses to exactly {} — with its two documented
    overrides (modelPath, rocrVisibleDevices) preserved commented underneath,
    the workflow-extraction survivor of EXPLORE gotcha 14. The former
    exactly-two-keys equality is the re-enable recipe, now asserted of the
    COMMENT block rather than live keys."""
    block = _svc().get("vllm")
    assert isinstance(block, dict) and block == {}, (
        "cf-143 C01 AC1: top-level vllm must exist as the explicit empty flow map {} "
        f"(got {block!r}) — the key stays live for the workflow extraction, no null, no live keys"
    )
    text = SERVICE.read_text()
    m = re.search(r"(?m)^vllm:\s*$", text)
    assert m, "cf-143 C01 AC1: no top-level vllm: key found"
    region = text[m.end(): m.end() + 4000]
    assert re.search(r"^\s*#\s*modelPath:\s*\S", region, re.M), (
        "cf-143 C01 AC1: the commented app-template.modelPath override is missing under "
        "vllm: — the two overrides retire COMMENTED, they are not deleted (Q3)"
    )
    assert re.search(r'^\s*#\s*rocrVisibleDevices:\s*"0"', region, re.M), (
        "cf-143 C01 AC1: the commented rocrVisibleDevices override is missing under vllm:"
    )
    assert "cf-143" in region, (
        "cf-143 C01 AC7: the vllm: empty-key region carries no cf-143 marker"
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
