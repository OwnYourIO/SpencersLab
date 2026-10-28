# r2-C03 wiring + r2-C02 deletion contract — the gpu-ai service layer speaks
# the single-Application shape (run-2 chunks/C03.md AC1–AC3, C02.md AC1–AC3;
# grep gates from the plan's "Commands").
#
# Service-values assertions are RED until r2-C03 lands (the run-1 shape is
# still in the file); the deletion asserts are RED until r2-C02 lands; the
# PRESERVATION pins (gpu box untouched, no outer shadowing, no ingress host)
# are green today and must stay green — a red there is drift, not a queue.
#
# Peers truth is read from tests/evidence/strata-peers-expected.yaml — the
# single sanctioned source (re-authored by this test session for the
# consolidated URL); dev edits the service values to MATCH it, never the
# reverse.

from __future__ import annotations

import re

import pytest
import yaml

import llama_swap_testlib as L
import strata_testlib as S

_ok, _reason = S.env_ready()
_js_ok, _js_reason = S.jsonschema_ready()
helm = pytest.mark.skipif(not _ok, reason=_reason)
schema_gated = pytest.mark.skipif(not (_ok and _js_ok), reason=_js_reason if _ok else _reason)


def _service_doc() -> dict:
    return yaml.safe_load(S.SERVICE_VALUES.read_text())


def _evidence() -> dict:
    return yaml.safe_load(S.PEERS_EVIDENCE.read_text())["strata"]


def _peers_entry() -> dict:
    return _service_doc()["llama-swap"]["config"]["peers"][S.PEER_NAME]


# --- AC1 (r2-C03): the consolidated service shape --------------------------------


def test_c03_charts_strata_entry_removed():
    """One Application, two controllers: the standalone appset entry dies —
    its ArgoCD Application prunes at sync (repo law: GitOps-only, no manual
    cluster step)."""
    charts = _service_doc()["charts"]
    assert "strata" not in charts, (
        "charts: still carries a strata entry — r2-C03 deletes it (the gpu-ai-strata "
        "Application prunes via GitOps)"
    )


def test_c03_seven_flags_present_true_under_llama_swap_overlay():
    """The flags are SCALARS only (deep-merge replaces lists wholesale — the
    engineProfile/model-env/mount lists are never overridden from the service
    block; run-1's list-warning comment relocates here)."""
    block = _service_doc()["llama-swap"]
    missing = []
    for path in S.FLAG_PATHS:
        full = f"app-template.{path}"
        found, val = S.dig(block, full)
        if not (found and val is True):
            missing.append(full)
    assert not missing, (
        f"llama-swap.app-template overlay lacks the true-ified flags {missing} — "
        "r2-C03 sets all seven TOGETHER (a partial set fails the render by design)"
    )


def test_c03_strata_block_nested_without_secret_chain():
    block = _service_doc()["llama-swap"]
    assert "strata" in block, "llama-swap.strata: sub-block missing (run-1's sibling block relocates here)"
    sub = block["strata"]
    assert "bitwardenIds" not in sub, (
        "bitwardenIds survived inside the relocated strata block — C-A deletes the sentinel chain"
    )
    assert str(sub.get("rocrVisibleDevices")) == "0", (
        "default device index the on-target rocminfo gate retargets"
    )


def test_c03_peers_proxy_is_the_consolidated_service_from_evidence():
    """Path appends VERBATIM to proxy — a /v1 suffix double-prefixes every
    request; equality with the EVIDENCE file pins the appset/release naming
    (evidence wins over any chunk string per the C03 conflict rule)."""
    ev = _evidence()
    proxy = _peers_entry()["proxy"]
    assert proxy == ev["proxy"], (
        f"peers proxy {proxy!r} != evidence {ev['proxy']!r} — r2-C03 flips the service "
        "values to the consolidated Service name; the evidence file is the single source"
    )
    assert not re.search(r"/v1/?$", proxy), f"/v1 suffix in {proxy} — verbatim-append double-prefix bug"


def test_c03_peers_clauses_unchanged_by_the_flip():
    """Models/timeouts/no-apiKey clauses survive the URL flip untouched
    (r2 Test-authority item 5): non-empty list naming the inner IDs, one per
    line in source, responseHeader 1800 = O2 cold-start, no apiKey = the
    keyless posture."""
    ev = _evidence()
    peer = _peers_entry()
    assert {"proxy", "models"} <= set(peer), f"peer keys {sorted(peer)} (v266 requires proxy+models)"
    assert "apiKey" not in peer, (
        "outer apiKey contradicts the C-A keyless posture (inner apiKeys: [] mirrors the outer)"
    )
    models = peer["models"]
    assert models and models[0] == ev["models_must_include"][0], f"models: {models}"
    assert set(models) <= {S.PRIMARY_ID, S.STRIX_ID}, f"unknown peer models: {models}"
    text = S.SERVICE_VALUES.read_text()
    block = text[text.index("peers:"):]
    listed = re.findall(r"^\s*-\s+(qwen3\.8-flash-next-strata[\w-]*)\s*$", block, re.M)
    assert listed, "models entries must stay one-per-line block items"
    t = peer["timeouts"]
    assert t.get("responseHeader") == 1800 and t.get("connect") == 30, t


def test_c03_peers_evidence_is_the_pin_and_the_testlib_agrees():
    """Two owned surfaces must not drift silently: the testlib constant is a
    MIRROR, the evidence file is the source (both test-session property)."""
    assert S.PEERS_PROXY == _evidence()["proxy"], (
        f"strata_testlib.PEERS_PROXY {S.PEERS_PROXY!r} drifted from the evidence "
        f"{_evidence()['proxy']!r} — fix BOTH in the same test-session pass"
    )


@helm
def test_c03_extract_and_render_yields_on_shape_keyless():
    """Proves the OVERLAY PATH SPELLING: extracting the service llama-swap
    block onto the parent chart must render the ON object set with zero
    sentinels and zero secret chain (AC2)."""
    docs = L.render_docs("gpu-ai")
    ids = S.obj_ids(docs)
    assert {
        ("Deployment", S.STRATA_OBJECT_NAME), ("Service", S.STRATA_OBJECT_NAME),
        ("ConfigMap", S.CM_CONFIG), ("ConfigMap", S.CM_PROFILE),
    } <= ids, f"ON objects missing from the service-overlay render: {sorted(ids)[:8]}…"
    raw = yaml.safe_dump_all(list(docs))
    assert "OVERRIDE_VIA" not in raw, "sentinel reached the rendered manifests"
    assert "strata-api-key" not in raw and "ExternalSecret" not in raw, (
        "secret-chain artifacts in the service-overlay render (C-A)"
    )
    cfg = L.rendered_config("gpu-ai")
    assert set(cfg["peers"]) == {S.PEER_NAME}
    assert set(cfg["peers"][S.PEER_NAME]["models"]) == {S.PRIMARY_ID, S.STRIX_ID}


# --- custom-values extraction (r2-C03) -------------------------------------------


def test_c03_custom_values_strata_section_deleted():
    """Q5's placeholder + the UUID concept die with the secret chain; the
    hf-token sibling must survive the extraction untouched."""
    text = S.CUSTOM_VALUES.read_text()
    doc = yaml.safe_load(text)
    assert "strata" not in doc, "custom-values still carries a strata: section — r2-C03 deletes it"
    assert "PENDING-OPERATOR" not in text and "strata-api-key" not in text, (
        "placeholder/secret tokens survived the extraction"
    )
    assert "hf-token" in text, "the llama-swap hf-token entry must NOT be collateral damage"


def test_c03_sentinel_and_secret_greps_zero():
    """Plan Commands grep gate, inverted to run 2: no live surface may still
    carry the strata sentinel, the key env passthrough, or the placeholder.
    Hits under the standalone chart dir retire with r2-C02's deletion (waves
    run C02 before C03's review); service/ custom-values/ hits are r2-C03's."""
    offenders = {}
    for needle in ("strata-api-key", "PENDING-OPERATOR"):
        hits = S.live_code_grep(needle)
        if hits:
            offenders[needle] = hits
    assert not offenders, (
        f"secret-chain tokens live in code surfaces: {offenders} — "
        f"service/custom-values hits are r2-C03's extraction, {S.STANDALONE_CHART_PATH_TEXT} "
        "hits retire with r2-C02"
    )


# --- preserved pins (green today; a red means drift, not a queue) ----------------


def test_c03_no_ingress_subdomain_strata_host():
    """Q4 internal-only deviation preserved through consolidation: a strata
    subdomain would publish the pod the peers hop exists to keep private."""
    subs = _service_doc()["ingress"]["subdomains"]
    offenders = [k for k in subs if k.startswith("strata")]
    assert not offenders, f"ingress.subdomains carries {offenders} — Q4 says internal only"


def test_c03_generic_ingress_template_strata_free():
    text = (S.REPO_ROOT / "services" / "gpu-ai" / "prod" / "templates" / "generic-ingress.yaml").read_text()
    assert "strata" not in text.lower(), (
        "generic-ingress.yaml mentions strata — the consolidation adds no public host"
    )


def test_c03_gpu_box_stays_flagless_and_strata_free():
    """No flags exist in the gpu service block → its render must equal the
    OFF shape (zero strata objects) — the OFF-state data posture holds per
    cluster (AC3)."""
    gpu_block = yaml.safe_load(S.GPU_VALUES.read_text())["llama-swap"]
    found, _ = S.dig(gpu_block, "app-template.controllers.strata.enabled")
    assert not found, "gpu service block grew strata flags — consolidation is a gpu-ai-only change"
    docs = L.render_docs("gpu")
    strata_objs = [f"{k}/{n}" for k, n in S.obj_ids(docs)
                   if S.STRATA_OBJECT_NAME in str(n) or str(n) in (S.CM_CONFIG, S.CM_PROFILE)]
    assert not strata_objs, f"gpu render grew strata objects without the flags: {strata_objs}"


@helm
def test_c03_outer_config_still_validates_v266_modulo_legacy_carve():
    """Documented carve: `performance.enable` is a pre-cf-77 key the v266 JSON
    schema does not declare and this ticket may not touch; everything else,
    peers included, must validate (run-1 lineage, unchanged by run 2)."""
    cfg = L.rendered_config("gpu-ai")
    errs = S.schema_errors(S.strip_legacy_performance_keys(cfg))
    assert not errs, [(list(e.absolute_path), e.message) for e in errs[:8]]


@schema_gated
def test_c03_peers_subtree_validates_strictly():
    """The uncarved peers proof: exact v266 peer-definition conformance for
    whatever URL the service block carries (before AND after the flip)."""
    schema = S.v266_schema()
    peers_def = {
        "type": "object",
        "additionalProperties": schema["properties"]["peers"]["additionalProperties"],
    }
    errs = S.schema_errors({"peers": _peers_entry()}, schema=peers_def)
    assert not errs, [(list(e.absolute_path), e.message) for e in errs[:8]]


def test_c03_strata_ids_never_join_the_outer_roster():
    """Peers models are NOT outer matrix/roster entries (run-1 RESEARCH §3):
    the outer solver keeps the RAM law as operator discipline; a strata id
    appearing in outer vars/models/aliases is wiring drift. Bare-ID routing
    additionally requires no outer shadow (run-1 O1 resolution)."""
    cfg = L.rendered_config("gpu-ai")
    ids = set(L.all_models_of(cfg))
    aliases = {a for m in L.all_models_of(cfg).values() for a in (m.get("aliases") or [])}
    shadowed = ({S.PRIMARY_ID, S.STRIX_ID} & ids) | ({S.PRIMARY_ID, S.STRIX_ID} & aliases)
    assert not shadowed, f"outer surface shadows inner IDs: {sorted(shadowed)}"
    vars_vals = set(((cfg.get("matrix") or {}).get("vars") or {}).values())
    assert not vars_vals & {S.PRIMARY_ID, S.STRIX_ID}, "outer matrix.vars references a strata id"
    preload = ((cfg.get("hooks") or {}).get("on_startup") or {}).get("preload") or []
    assert not set(preload) & {S.PRIMARY_ID, S.STRIX_ID}
    L.assert_matrix_closure(cfg, "gpu-ai")


# --- r2-C02: the standalone chart retires ---------------------------------------


def test_c02_standalone_chart_dir_absent():
    assert not S.STANDALONE_CHART_DIR.is_dir(), (
        f"{S.STANDALONE_CHART_PATH_TEXT} still exists — r2-C02 deletes the whole dir "
        "(the suite is re-homed to charts/llama-swap/tests, the body to the parent chart)"
    )


def test_c02_no_live_path_references():
    """Repo grep gate (C02 AC3): outside the frozen history + run-2 plan
    folders, no live surface may reference the retired chart path. Hit
    attribution: services/gpu-ai comments → r2-C03 rewrite; the standalone
    chart's own files → r2-C02 deletion; containers/strata/{Dockerfile,README.md}
    carry three stale ONE-LINE consumer pointers the plan's "containers
    untouched" scope never accounted for (C02 AC3 is repo-wide — this red is
    the escalation; a coord amendment should hand the pointer reword to
    r2-C04's docs sweep, not delete the gate). This suite composes its own
    path string, so it stays invisible to its own grep."""
    hits = S.live_code_grep(S.STANDALONE_CHART_PATH_TEXT)
    assert not hits, f"live surfaces still reference {S.STANDALONE_CHART_PATH_TEXT}/: {hits}"
