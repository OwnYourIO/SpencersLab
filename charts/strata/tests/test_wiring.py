# C03 wiring contract — gpu-ai appset entry, peers route, secrets
# (chunks/C03.md AC1–AC4; grep gates from the plan's "Commands").
#
# AC5 rides the existing charts/llama-swap parity test (reuse, do not
# duplicate): charts/llama-swap/tests/test_config_parity.py carries the
# additive-peers allowance, pinned by tests/evidence/strata-peers-expected.yaml.
#
# RED until C03 lands: the service values block and custom-values entry do not
# exist yet; the strata chart itself is C02's. Bare-file reads give the
# precise missing-surface message.

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


def _peers_entry() -> dict:
    return _service_doc()["llama-swap"]["config"]["peers"][S.PEER_NAME]


# --- AC1: wiring greps as assertions ------------------------------------------


def test_c03_ac1_charts_entry_mirrors_llama_swap():
    """Privileged hostPath pod → same ServerSideApply posture rationale as the
    llama-swap entry (C03 task 1)."""
    charts = _service_doc()["charts"]
    assert "strata" in charts, "no strata entry under charts: — ApplicationSet will not deploy the pod"
    assert charts["strata"].get("namespace") == "default"
    assert str(charts["strata"].get("ServerSideApply")) == "false", charts["strata"]


def test_c03_ac1_no_ingress_subdomain_deliberate_deviation():
    """Q4 trio-rule deviation: internal-only by operator ruling — a strata
    subdomain would publish the pod the peers hop exists to keep private."""
    subs = _service_doc()["ingress"]["subdomains"]
    offenders = [k for k in subs if k.startswith("strata")]
    assert not offenders, f"ingress.subdomains carries {offenders} — Q4 says internal only"


def test_c03_ac1_strata_values_block_present():
    doc = _service_doc()
    block = doc["strata"]
    assert block["bitwardenIds"]["strata-api-key"] == "OVERRIDE_VIA_CUSTOM_VALUES"
    assert str(block.get("rocrVisibleDevices")) == "0", (
        "default device index the on-target rocminfo gate retargets (C02 key name)"
    )


def test_c03_ac1_custom_values_single_placeholder_entry():
    text = S.CUSTOM_VALUES.read_text()
    lines = [ln for ln in text.splitlines() if "strata-api-key" in ln]
    assert len(lines) == 1, f"exactly one strata-api-key line required, found {len(lines)}: {lines}"
    assert "PENDING-OPERATOR-UUID" in lines[0], (
        "Q5: placeholder until the operator creates the Bitwarden item `strata` — "
        "a real UUID committed here instead would fabricate the human step"
    )
    doc = yaml.safe_load(text)
    uuid = doc["strata"]["bitwardenIds"]["strata-api-key"]
    assert uuid == "PENDING-OPERATOR-UUID"


def test_c03_ac1_sentinel_1_to_1():
    """Repo law: every OVERRIDE_VIA_CUSTOM_VALUES placeholder has exactly one
    custom-values counterpart (the plan's wiring-grep gate)."""
    svc = yaml.safe_load(S.SERVICE_VALUES.read_text())
    svc_sentinels = [
        k for k, v in (svc["strata"].get("bitwardenIds") or {}).items()
        if v == "OVERRIDE_VIA_CUSTOM_VALUES"
    ]
    custom = yaml.safe_load(S.CUSTOM_VALUES.read_text())
    have = set((custom.get("strata") or {}).get("bitwardenIds") or {})
    assert set(svc_sentinels) == have & set(svc_sentinels), (
        f"sentinel/custom-values mismatch: {sorted(set(svc_sentinels) - have)} unbacked"
    )


# --- AC2: peers shape == RESEARCH §3 facts --------------------------------------


def test_c03_ac2_peer_required_keys_and_no_api_key():
    peer = _peers_entry()
    assert {"proxy", "models"} <= set(peer), f"peer keys {sorted(peer)} (v266 requires proxy+models)"
    assert "apiKey" not in peer, (
        "inner apiKeys: [] is the quarantine posture; a key here would half-open "
        "the surface the operator ruled private (Q4/Q5)"
    )


def test_c03_ac2_proxy_exact_service_dns_no_v1():
    """Path appends VERBATIM to proxy — a /v1 suffix double-prefixes every
    request. Equality against S.PEERS_PROXY pins the appset release naming;
    the render cross-check below catches a chart-side rename of the Service."""
    proxy = _peers_entry()["proxy"]
    assert proxy == S.PEERS_PROXY, f"proxy {proxy!r} != {S.PEERS_PROXY!r}"
    assert not re.search(r"/v1/?$", proxy), f"/v1 suffix in {proxy} — verbatim-append double-prefix bug"


@helm
def test_c03_ac2_proxy_matches_rendered_strata_service():
    docs, _raw = S.render_strata()
    svc = S.rendered_service_name(docs)
    dns = f"http://{svc}.{S.NAMESPACE}.svc.cluster.local:8080"
    assert _peers_entry()["proxy"] == dns, (
        f"peers proxy out of sync with the rendered Service identity ({dns}) — rename drift"
    )


def test_c03_ac2_models_list_primary_first_one_per_line():
    """C05 appends the strix ID as a one-line edit — the list ships formatted
    one-per-line so the seam diff stays clean (C03 dev note)."""
    peer = _peers_entry()
    models = peer["models"]
    assert models and models[0] == S.PRIMARY_ID, f"models: {models}"
    assert set(models) <= {S.PRIMARY_ID, S.STRIX_ID}, f"unknown peer models: {models}"
    text = S.SERVICE_VALUES.read_text()
    block = text[text.index("peers:"):]
    listed = re.findall(r"^\s*-\s+(qwen3\.8-flash-next-strata[\w-]*)\s*$", block, re.M)
    assert listed, "models entries must be one-per-line block items (C05 seam formatting)"


def test_c03_ac2_timeouts():
    """responseHeader 1800 ≈ inner healthCheckTimeout: a cold arena pin answers
    minutes into the request (O2 resolved, RESEARCH §3)."""
    t = _peers_entry()["timeouts"]
    assert t.get("responseHeader") == 1800, t
    assert t.get("connect") == 30, t


# --- AC4: extract-and-render of the strata: block ------------------------------


@helm
def test_c03_ac4_service_block_renders_valid_no_sentinels():
    docs, raw = S.render_service_strata(test_uuid=None)
    assert docs, "strata: block extracted against charts/strata rendered nothing"
    assert "OVERRIDE_VIA" not in raw, "sentinel reached the rendered manifests"
    assert not S.find_kind(docs, "ExternalSecret"), (
        "without bitwardenIds the secret must not render (gpu-style clean render)"
    )


@helm
def test_c03_ac4_test_uuid_renders_external_secret():
    docs, raw = S.render_service_strata(test_uuid="test-uuid")
    assert "OVERRIDE_VIA" not in raw
    es_list = S.find_kind(docs, "ExternalSecret")
    assert len(es_list) == 1, f"ExternalSecrets rendered: {len(es_list)}"
    es = es_list[0]
    data = es["spec"]["data"]
    assert any(d["remoteRef"]["key"] == "test-uuid" for d in data), data
    ent = [d for d in data if d.get("secretKey") == "api_key"]
    assert ent, f"secretKey must be api_key (Bitwarden fields store, DECISIONS): {data}"
    assert ent[0]["remoteRef"].get("property") == "api_key", (
        f"the bitwarden-fields store selects the custom field through remoteRef.property "
        f"(SecretStore jsonPath fields[?@.name==property], charts/external-secrets-bitwarden) "
        f"— an entry without it fetches nothing: {ent[0]}"
    )
    stores = {d["sourceRef"]["storeRef"]["name"] for d in data}
    assert stores == {"bitwarden-fields"}, f"store must be bitwarden-fields, got {stores}"


@helm
def test_c03_ac4_pod_consumes_secret_env_without_default():
    """The fail-fast pre-sync gate BREAKS the strata pod alone until the
    operator lands the UUID (Q5 quarantine) — a `default:` on the env entry
    would soften it into silence."""
    docs, raw = S.render_service_strata(test_uuid="test-uuid")
    pod = S.the_pod(docs)
    ctr = S.main_container(docs)
    blob = yaml.safe_dump(pod)
    assert "strata-api-key" in blob, "no reference to the ExternalSecret target in the pod"
    refs = [e for e in ctr.get("env", []) if (e.get("valueFrom") or {}).get("secretKeyRef", {}).get("name") == "strata-api-key"]
    from_env = [f for f in ctr.get("envFrom", []) if (f.get("secretRef") or {}).get("name") == "strata-api-key"]
    assert refs or from_env, f"STRATA_API_KEY secret wiring missing: {ctr.get('env')}"


# --- outer rendered config: v266 schema + matrix guards --------------------------


@schema_gated
def test_c03_outer_full_config_validates_v266_modulo_legacy_carve():
    """Documented carve: `performance` carries a pre-cf-77 key (`enable`) the
    v266 JSON schema does not declare — it predates this ticket on both
    clusters and cf-77 forbids touching the existing block. Everything else,
    peers included, must validate."""
    cfg = L.rendered_config("gpu-ai")
    errs = S.schema_errors(S.strip_legacy_performance_keys(cfg))
    assert not errs, [(list(e.absolute_path), e.message) for e in errs[:8]]


@schema_gated
def test_c03_peers_subtree_validates_strictly():
    """The uncarved peers proof: exact v266 peer-definition conformance, so
    the config llama-swap loads on the deployed pin accepts the spellings."""
    schema = S.v266_schema()
    peers_def = {
        "type": "object",
        "additionalProperties": schema["properties"]["peers"]["additionalProperties"],
    }
    errs = S.schema_errors({"peers": _peers_entry()}, schema=peers_def)
    assert not errs, [(list(e.absolute_path), e.message) for e in errs[:8]]


def test_c03_matrix_guard_strata_not_a_roster_member():
    """Peers models are NOT outer matrix/roster entries (RESEARCH §3): they are
    invisible to the outer solver, which keeps the RAM law operator discipline.
    A strata id appearing in outer vars/models/aliases is wiring drift."""
    cfg = L.rendered_config("gpu-ai")
    ids = set(L.all_models_of(cfg))
    assert not {S.PRIMARY_ID, S.STRIX_ID} & ids, "strata id rendered as an OUTER model (breaks the (b) architecture)"
    vars_vals = set(((cfg.get("matrix") or {}).get("vars") or {}).values())
    assert not vars_vals & {S.PRIMARY_ID, S.STRIX_ID}, "outer matrix.vars references a strata id"
    preload = ((cfg.get("hooks") or {}).get("on_startup") or {}).get("preload") or []
    assert not set(preload) & {S.PRIMARY_ID, S.STRIX_ID}
    # matrix closure stays intact for the existing roster too (v262 load error)
    L.assert_matrix_closure(cfg, "gpu-ai")


def test_c03_no_proxy_values_entry_untouched():
    """Verify-only file from C03's scope: the generic ingress must not gain a
    strata host (the subdomains check above reads the same truth through the
    values; this catches a template-side hack)."""
    text = (S.REPO_ROOT / "services/gpu-ai/prod/templates/generic-ingress.yaml").read_text()
    assert "strata" not in text.lower(), (
        "generic-ingress.yaml mentions strata — C03 scope says this file is verify-only"
    )
