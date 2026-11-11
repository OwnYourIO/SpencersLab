# cf-143 C04 — the coexistence wiring contract (chunks/C04.md Tests, bullet 3;
# Q5 "Strata shouldn't be disabled yet" made executable end to end).
#
# Two halves, one file:
#  * STRATA AS TODAY — the strata render legs (controller Deployment,
#    Service, config/profile ConfigMaps) compared against the checked-in
#    pre-ticket baseline evidence/cf143-pre-ticket-strata/ (captured by the
#    cf-143 test session at the clean branch tip) — byte-identical docs,
#    now and after every cf-143 wave. Plus the service-level parse pins:
#    the seven-flag strata enable-set still enabled:true, the matrix/preload
#    blocks un-disturbed.
#  * RADIANCE LANDS BESIDE IT — the charts.radiance appset entry renders
#    from the internal charts/ shape (name gpu-ai-radiance derived from the
#    base appset template — the template read is the evidence, same shape as
#    C07's amd-gpu n1 leg), the top-level radiance: service block carries
#    scalars ONLY, and neither engine disables the other (no radiance rung
#    joins the outer matrix; no strata flag flips).
#
# Red state at handoff (designed): the strata baseline + enable-set legs are
# GREEN NOW (they must STAY green — a red there names a chunk that touched
# strata, which review rejects) and the radiance-entry legs are RED until
# C04's values edit lands.
#
# Run with the suite (per-directory): python3 -m pytest charts/llama-swap/tests -v

from __future__ import annotations

import re

import pytest
import yaml

import llama_swap_testlib as L
import strata_testlib as S

_ok, _ok_reason = L.helm_ready()
helm_mark = pytest.mark.skipif(not _ok, reason=_ok_reason)

BASELINE = L.TESTS_DIR / "evidence" / "cf143-pre-ticket-strata" / "gpu-ai.strata-docs.yaml"
BASE_APPSET = L.REPO_ROOT / "charts" / "base" / "templates" / "appset-charts.yaml"
CUSTOM_VALUES = L.REPO_ROOT / "custom-values" / "gpu-ai" / "prod-values.yaml"


def _svc() -> dict:
    return yaml.safe_load(S.SERVICE_VALUES.read_text())


def _strata_docs(docs) -> list:
    wanted = {("Deployment", S.STRATA_OBJECT_NAME), ("Service", S.STRATA_OBJECT_NAME),
              ("ConfigMap", S.CM_CONFIG), ("ConfigMap", S.CM_PROFILE)}
    picked = [d for d in docs if (d.get("kind"), (d.get("metadata") or {}).get("name")) in wanted]
    found = {(d["kind"], (d.get("metadata") or {}).get("name")) for d in picked}
    assert found == wanted, f"strata render legs missing from the live render: {sorted(wanted - found)}"
    return sorted(picked, key=lambda d: (d["kind"], d["metadata"]["name"]))


# --- half 1: strata renders AS TODAY ------------------------------------------


def test_baseline_fixture_present():
    assert BASELINE.is_file(), (
        f"cf-143 C04: pre-ticket strata baseline {BASELINE} missing — fixture breakage, "
        "not a code red (test-session property; cf-143 test session, TEST_SPEC §12)"
    )


@helm_mark
def test_strata_render_byte_equal_to_pre_ticket_baseline():
    """C04 AC1 (the executable reading of "ZERO changed lines inside the strata
    enable-set"): the four strata docs in the live service-overlay render must
    parse-equal the pre-ticket baseline. The baseline was captured at a clean
    tree, so any strata-surface move by C01/C04/C05/C07 reds HERE, naming Q5."""
    assert BASELINE.is_file(), f"cf-143 C04: baseline fixture {BASELINE} missing"
    baseline = yaml.safe_load(BASELINE.read_text())
    assert isinstance(baseline, list), f"cf-143 C04: baseline fixture is {type(baseline).__name__}, want a list of docs"
    docs, _raw = S.render_service_overlay("gpu-ai")
    current = _strata_docs(docs)
    assert len(current) == len(baseline) == 4, "cf-143 C04: baseline/live doc count mismatch"
    for b, c in zip(baseline, current):
        assert b == c, (
            f"cf-143 C04/Q5: strata {c['kind']}/{c['metadata']['name']} render diverged from "
            "the pre-ticket baseline — the cf-143 waves are ADDITIVE; a strata diff here is "
            "rejected outright by review (chunks/C04.md notes-for-dev)"
        )


def test_strata_enable_set_unchanged_seven_flags():
    """The seven default-OFF flags stay enabled:true in the service values —
    parse-compare against the checked expectation (the FLAG_PATHS table from
    strata's own consolidation law), no render needed."""
    block = _svc()["llama-swap"]

    def dig(doc, path: str):
        cur = doc
        for part in path.split("."):
            if not isinstance(cur, dict) or part not in cur:
                return None
            cur = cur[part]
        return cur

    flipped = []
    for fp in S.FLAG_PATHS:
        # FLAG_PATHS spell the chart-root key path (app-template.-prefixed) —
        # the service block nests the same tree under llama-swap:, so the
        # dig starts at llama-swap and keeps the full path.
        if dig(block, fp) is not True:
            flipped.append(fp)
    assert not flipped, (
        f"cf-143 C04/Q5: strata enable flags no longer true in the service values: {flipped} — "
        "the enable-set (121-197) is byte-stable through the radiance join"
    )


# --- half 2: radiance lands beside it ------------------------------------------


def test_radiance_charts_entry_internal_shape():
    """C04 AC4 trio leg 1: charts.radiance = {namespace: default,
    ServerSideApply: "false"} (gotcha 6: SSA "false" for the llama-swap
    family), no version/repository keys (internal chart)."""
    entry = (_svc().get("charts") or {}).get("radiance")
    assert entry is not None, (
        "cf-143 C04: charts.radiance entry missing from services/gpu-ai/prod/values.yaml — "
        "the appset leg of the trio is not wired"
    )
    assert entry == {"namespace": "default", "ServerSideApply": "false"}, (
        f"cf-143 C04: charts.radiance is {entry}, want exactly "
        '{namespace: default, ServerSideApply: "false"} (internal-chart shape, gotcha 6)'
    )


def test_application_name_derivation_is_gpu_ai_radiance():
    """C04 AC4 (name evidence): the base appset template derives the
    Application name as {{serviceName}}-{{appName}} (radiance -> gpu-ai-
    radiance, the peer URL's host) and renders internal entries (no
    version/repository) as a git path source — the same read C07's n1
    needle pins for amd-gpu."""
    text = BASE_APPSET.read_text()
    assert 'name: "{{ `{{ .serviceName }}` }}-{{ `{{ .appName }}` }}"' in text, (
        "cf-143 C04: the base appset Application-name derivation changed — re-read "
        "charts/base/templates/appset-charts.yaml and re-pin the peer-URL reasoning"
    )
    assert re.search(r"- repoURL: '.*hasKey \. \"repository\".*services\.repo.*'", text), (
        "cf-143 C04: the appset repoURL branch (repository ? external : git repo) changed "
        "shape — internal entries (charts.radiance) resolve to services.repo + path"
    )


def test_service_radiance_block_scalars_only_and_dual_edit():
    """C04 task 2 + AC5: top-level radiance: block — scalars ONLY (deep-merge
    REPLACE law, comment 129-134), app-template.modelPath re-pin EQUAL to the
    chart's modelPath anchor (dual-edit law), NO rocrVisibleDevices key (no
    env on the named-pool path)."""
    block = _svc().get("radiance")
    assert isinstance(block, dict), (
        "cf-143 C04: no top-level radiance: values block — the service half of the "
        "chart-into-appset wiring is missing"
    )

    def walk(node, path="radiance"):
        if isinstance(node, dict):
            for k, v in node.items():
                yield from walk(v, f"{path}.{k}")
        elif isinstance(node, list):
            yield path, "list"

    list_paths = sorted(p for p, kind in walk(block) if kind == "list")
    assert not list_paths, (
        f"cf-143 C04: radiance service block carries lists at {list_paths} — helm deep-merge "
        "REPLACES lists wholesale (gotcha 3); the block is scalars-only"
    )
    sub = block.get("app-template") or {}
    assert "rocrVisibleDevices" not in sub, (
        "cf-143 C04: radiance service block re-pins rocrVisibleDevices — the named-pool "
        "path sets no ROCr/HIP env (C02 absence law)"
    )
    chart_values = L.REPO_ROOT / "charts" / "radiance" / "values.yaml"
    assert chart_values.is_file(), (
        "cf-143 C04: charts/radiance/values.yaml missing — C02 must land first (wave 2 dep); "
        "the dual-edit equality has no chart side to compare against"
    )
    chart_model = (yaml.safe_load(chart_values.read_text()).get("app-template") or {}).get("modelPath")
    assert sub.get("modelPath") == chart_model, (
        f"cf-143 C04 AC5: service modelPath {sub.get('modelPath')!r} != chart modelPath "
        f"{chart_model!r} — anchors resolve per document, the retarget is a DUAL edit"
    )


def test_no_radiance_ingress_host_and_two_skip_comments():
    """C04 AC4 trio leg 3 (the documented skip): NO radiance key under
    ingress.subdomains, and the subdomains block now carries TWO internal-
    only skip comments (strata's Q4 stays as-is + radiance's mirror)."""
    svc = _svc()
    subs = (svc.get("ingress") or {}).get("subdomains") or {}
    offenders = [k for k in subs if "radiance" in k]
    assert not offenders, f"cf-143 C04: ingress.subdomains carries {offenders} — radiance is internal-only (Q4 mirror)"
    text = S.SERVICE_VALUES.read_text()
    m = re.search(r"^\s*subdomains:\s*$", text, re.M)
    assert m, "cf-143 C04: no ingress.subdomains block to search for the skip comments"
    rest = text[m.end():]
    stop = re.search(r"^[a-z]", rest, re.M)
    region = rest[: stop.start() if stop else len(rest)]
    comment_lines = [ln for ln in region.splitlines() if ln.lstrip().startswith("#")]
    radiance_skips = [ln for ln in comment_lines if "radiance" in ln.lower()]
    strata_skips = [ln for ln in comment_lines if "strata" in ln.lower()]
    assert radiance_skips, (
        "cf-143 C04: no radiance internal-only skip comment in the subdomains block "
        "(the D7/Q4 precedent text mirrored — trio law's documented skip)"
    )
    assert strata_skips, "cf-143 C04: the strata Q4 skip comment vanished — that block is byte-stable (Q5)"


def test_custom_values_gains_no_radiance_key():
    """D8: keyless + ungated packs = no secret surface = no custom-values leg
    (the trio law's secrets-condition documented in the chunk)."""
    text = CUSTOM_VALUES.read_text()
    assert "radiance" not in text.lower(), (
        "cf-143 C04/D8: custom-values/gpu-ai/prod-values.yaml gained a radiance key — "
        "the lane ships no secrets; a bitwardenId here contradicts D8"
    )


@helm_mark
def test_radiance_id_stays_out_of_the_outer_matrix_and_models():
    """Peer law (RESEARCH 'Catalog/matrix anchors'): peer models stay OUT of
    the outer matrix; the outer config gains no radiance rung."""
    cfg = L.rendered_config("gpu-ai")
    models = set(L.all_models_of(cfg))
    served_id = "qwen3.8-flash-next-radiance"
    assert served_id not in models, (
        f"cf-143 C04: {served_id} rendered as an OUTER llama-swap model — the peer join "
        "must not register it in the outer models map (local ids would shadow the peer)"
    )
    matrix = cfg.get("matrix") or {}
    vars_blob = yaml.safe_dump(matrix.get("vars") or {}) + yaml.safe_dump(matrix.get("sets") or {})
    assert served_id not in vars_blob, (
        "cf-143 C04: the radiance id joined a matrix var/set — peers are not matrix members"
    )
    # Neither disables the other: the strata peer is still live in the SAME
    # render the radiance appset entry serves beside (coexistence, Q5).
    assert "strata" in (cfg.get("peers") or {}), (
        "cf-143 C04: peers.strata gone from the render — nothing in this ticket disables strata"
    )
