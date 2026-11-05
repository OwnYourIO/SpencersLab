# C02 render contract (2026/2026-11-cf-105-feat-implement-vllm —
# chunks/C02.md AC1-AC4): extract the service `vllm:` subtree, render with
# --set domain/clusterName, and assert AC2/AC3/AC4 line by line — the full
# D4 serve recipe verbatim, the complete container env set, probes,
# securityContext, GPU/RAM/shm pod shape, the exactly-two scrape annotations,
# the peer-hop Service name, and both persistence legs. All tests
# designed-red at test-write time: charts/vllm and the service `vllm:` block
# do not exist yet, so every render/extract fails on the absent chart — that
# is the designed state, not a harness fault.

from __future__ import annotations

import pytest

import vllm_testlib as V

_ok, _reason = V.helm_ready()
pytestmark = pytest.mark.skipif(not _ok, reason=_reason)


def _service_render():
    return V.render(release="vllm", service=True)


# --- AC1: both renders pass with no OVERRIDE_* sentinels ---------------------


@pytest.mark.parametrize("service", [False, True], ids=["chart-defaults", "service-level"])
def test_ac1_render_produces_deployment_without_sentinels(service):
    docs, raw = V.render(release="vllm", service=service)
    V.deployment(docs)
    assert "OVERRIDE_" not in raw, "a rendered manifest still carries an OVERRIDE_* sentinel"


# --- AC2: the rendered Deployment line by line -------------------------------


def test_ac2_serve_args_are_the_d4_recipe_verbatim():
    """The rendered args equal the D4 recipe in order with the service
    modelPath spliced at --model: no silent mutation (add, drop, reorder,
    re-value) survives this bar."""
    docs, _ = _service_render()
    container = V.main_container(V.deployment(docs))
    block = V.service_vllm_block()
    assert "modelPath" in block, (
        "C02 AC2: the service vllm: block carries no modelPath (the --model splice source — "
        "pinned to the actual q4 GGUF path on the PVC, C02 task)"
    )
    model_path = block["modelPath"]
    V.assert_model_path_shape(model_path, "service values")
    got = V.flag_pairs(container.get("args", []))
    want = V.expected_recipe(model_path)
    assert got == want, (
        f"C02 AC2: rendered serve args diverge from the D4 recipe\n  got:      {got}\n  expected: {want}"
    )


def test_ac2_container_env_is_exactly_the_contract_set():
    """The FULL env set (AC2): the four contract vars and nothing else —
    ROCR_VISIBLE_DEVICES (chip targeting; a values key so the template never
    changes), the two /data cache mounts, and VLLM_SERVER_DEV_MODE which the
    dev-gated /sleep + /wake_up endpoints REQUIRE alongside
    --enable-sleep-mode (Post Research V5)."""
    docs, _ = _service_render()
    env = V.env_map(V.main_container(V.deployment(docs)))
    want = {
        "ROCR_VISIBLE_DEVICES": str(V.service_vllm_block().get("rocrVisibleDevices", "0")),
        "TRITON_CACHE_DIR": "/data/triton",
        "HUGGINGFACE_HUB_CACHE": "/data/hf",
        "VLLM_SERVER_DEV_MODE": "1",
    }
    assert env == want, (
        f"C02 AC2: container env set diverges\n  got:      {env}\n  expected: {want}"
    )


def test_ac2_probes_are_warmup_sized_on_health():
    docs, _ = _service_render()
    container = V.main_container(V.deployment(docs))
    startup = container.get("startupProbe") or {}
    # The port may render as 8000 or as the named container port "http"
    # (bound to 8000 by the containerPort contract asserted below) — same
    # endpoint either way.
    assert startup.get("httpGet", {}).get("path") == "/health" and startup.get("httpGet", {}).get("port") in V.PROBE_PORT_OK, (
        "C02 AC2: startup probe must hit httpGet /health:8000"
    )
    assert startup.get("initialDelaySeconds") == 60, "C02 AC2: startup initialDelaySeconds must be 60"
    assert startup.get("periodSeconds") == 10, "C02 AC2: startup periodSeconds must be 10"
    # 18 GiB pull + Triton JIT: the ~15 min warmup envelope is a floor.
    assert (startup.get("failureThreshold") or 0) >= 90, (
        f"C02 AC2: startup failureThreshold {startup.get('failureThreshold')} < 90 (the 15 min warmup envelope)"
    )
    for name in ("livenessProbe", "readinessProbe"):
        probe = container.get(name) or {}
        assert probe.get("httpGet", {}).get("path") == "/health" and probe.get("httpGet", {}).get("port") in V.PROBE_PORT_OK, (
            f"C02 AC2: {name} must hit httpGet /health:8000 (gated by the startup probe)"
        )


def test_ac2_security_context_trio_plus_repo_standard():
    docs, _ = _service_render()
    sc = V.main_container(V.deployment(docs)).get("securityContext") or {}
    assert (sc.get("seccompProfile") or {}).get("type") == "Unconfined", (
        "C02 AC2: seccompProfile must be Unconfined (the upstream AMD pod shape, R1 Q5)"
    )
    assert sc.get("runAsGroup") == 44, "C02 AC2: runAsGroup must be 44 (video)"
    assert "SYS_PTRACE" in (sc.get("capabilities") or {}).get("add", []), (
        "C02 AC2: capabilities.add must include SYS_PTRACE"
    )
    assert sc.get("allowPrivilegeEscalation") is False, (
        "C02 AC2: allowPrivilegeEscalation must be false (repo standard)"
    )


def test_ac2_gpu_ram_shm_pod_shape():
    docs, _ = _service_render()
    deploy = V.deployment(docs)
    pod = V.pod_template(deploy)["spec"]
    assert pod.get("hostIPC") is True, "C02 AC2: hostIPC must be true"

    container = V.main_container(deploy)
    resources = container.get("resources") or {}
    limits = resources.get("limits") or {}
    assert str(limits.get("amd.com/gpu")) == "1", (
        f"C02 AC2: limits must carry amd.com/gpu '1', got {limits}"
    )
    requests = resources.get("requests") or {}
    assert str(requests.get("cpu")) == "4", f"C02 AC2: cpu request must be 4, got {requests.get('cpu')}"
    # RAM-law sizing (EXPLORE §8.6): the 32Gi limit is the cap that keeps the
    # 125Gi node undisturbed; the request rides the documented band
    # 16Gi..32Gi — the C02 task lets dev adjust within that band with a
    # recorded rationale, so only the band is asserted, not one point in it.
    assert str(limits.get("memory")) == "32Gi", (
        f"C02 AC2: memory limit must be 32Gi (the RAM-law cap), got {limits.get('memory')}"
    )
    mem_req = str(requests.get("memory"))
    try:
        mem_req_gi = float(mem_req.rstrip("Gi"))
        assert 16 <= mem_req_gi <= 32, (
            f"C02 AC2: memory request {mem_req} is outside the RAM-law band 16Gi..32Gi"
        )
    except ValueError:
        raise AssertionError(f"C02 AC2: memory request {mem_req!r} is not a plain Gi quantity")

    # 8Gi Memory emptyDir mounted at /dev/shm (R1 Q5 shm sizing, TP=1).
    mounts = {m.get("mountPath"): m for c in pod["containers"] for m in c.get("volumeMounts", [])}
    shm_mount = mounts.get("/dev/shm")
    assert shm_mount is not None, "C02 AC2: no volume mounted at /dev/shm"
    volume_names = {v["name"]: v for v in pod.get("volumes", [])}
    empty = (volume_names.get(shm_mount["name"]) or {}).get("emptyDir") or {}
    assert empty.get("medium") == "Memory", "C02 AC2: /dev/shm must be an emptyDir with medium Memory"
    assert str(empty.get("sizeLimit")) == "8Gi", f"C02 AC2: /dev/shm sizeLimit must be 8Gi, got {empty.get('sizeLimit')}"

    ports = container.get("ports") or []
    assert any(p.get("name") == "http" and p.get("containerPort") == 8000 for p in ports), (
        f"C02 AC2: the container must expose a named port http: 8000, got {ports}"
    )


def test_ac2_pod_carries_exactly_the_two_scrape_annotations():
    """D8/Q5: exactly two k8s.grafana.com/* pod annotations — scrape +
    metrics.portNumber — and NO metrics.scrapeInterval key (the 60 s v4
    annotationAutodiscovery feature default governs)."""
    docs, _ = _service_render()
    grafana = V.grafana_annotations(V.deployment(docs))
    assert grafana == {"k8s.grafana.com/scrape": "true",
                       "k8s.grafana.com/metrics.portNumber": "8000"}, (
        f"C02 AC2: the pod must carry exactly the two scrape annotations, got {grafana}"
    )


def test_ac2_reloader_annotation_on_controller():
    docs, _ = _service_render()
    ann = V.deployment(docs).get("metadata", {}).get("annotations") or {}
    assert ann.get("reloader.stakater.com/auto") == "true", (
        "C02 AC2: the controller must carry reloader.stakater.com/auto: \"true\" (repo convention)"
    )


# --- AC3: the Service the peers.vllm hop consumes ----------------------------


def test_ac3_service_is_the_peer_hop_target():
    """Rendered under the ApplicationSet release name (gpu-ai-<appName>):
    ClusterIP Service `gpu-ai-vllm` with the named port http: 8000 — the
    peer URL is http://gpu-ai-vllm.default.svc.cluster.local:8000 with NO
    /v1 suffix (C03 consumes it verbatim)."""
    docs, _ = V.render(release="gpu-ai-vllm", service=True)
    svcs = V.services(docs)
    main = [s for s in svcs if s["metadata"]["name"] == "gpu-ai-vllm"]
    assert main, f"C02 AC3: no Service named gpu-ai-vllm; got {[s['metadata']['name'] for s in svcs]}"
    spec = main[0]["spec"]
    assert spec.get("type") in (None, "ClusterIP"), (
        f"C02 AC3: the vllm Service must be ClusterIP, got {spec.get('type')}"
    )
    ports = spec.get("ports") or []
    assert any(p.get("name") == "http" and p.get("port") == 8000 for p in ports), (
        f"C02 AC3: the Service must carry a named port http: 8000, got {ports}"
    )


# --- AC4: both persistence legs + the hand-written cache PVC ------------------


def test_ac4_models_and_cache_claims_mounted():
    docs, _ = _service_render()
    pod = V.pod_template(V.deployment(docs))["spec"]
    mounts = {m.get("name"): m for c in pod["containers"] for m in c.get("volumeMounts", [])}
    by_claim = {}
    for vol in pod.get("volumes", []):
        claim = (vol.get("persistentVolumeClaim") or {}).get("claimName")
        if claim:
            by_claim[claim] = vol
    assert "llama-swap" in by_claim, (
        f"C02 AC4: no volume bound to existingClaim llama-swap; claims: {sorted(by_claim)}"
    )
    assert "vllm-cache" in by_claim, (
        f"C02 AC4: no volume bound to existingClaim vllm-cache; claims: {sorted(by_claim)}"
    )
    models_mount = mounts.get(by_claim["llama-swap"]["name"])
    assert models_mount and models_mount.get("mountPath") == "/models", (
        f"C02 AC4: the llama-swap claim must mount at /models, got {models_mount}"
    )
    assert models_mount.get("readOnly") is True, "C02 AC4: the weights mount must be read-only"
    cache_mount = mounts.get(by_claim["vllm-cache"]["name"])
    assert cache_mount and cache_mount.get("mountPath") == "/data", (
        f"C02 AC4: the vllm-cache claim must mount at /data, got {cache_mount}"
    )


def test_ac4_hand_written_cache_pvc():
    """The hand-written templates/pvc-vllm-cache.yaml (qdrant pattern): one
    RWO claim named vllm-cache sized from cachePvcSize (default 10Gi),
    asserted on the chart-defaults render where the default applies."""
    docs, _ = V.render(release="vllm", service=False)
    pvcs = V.persistent_volume_claims(docs)
    cache = [p for p in pvcs if p["metadata"]["name"] == "vllm-cache"]
    assert len(cache) == 1, (
        f"C02 AC4: the render must carry exactly one PVC named vllm-cache, got {[p['metadata']['name'] for p in pvcs]}"
    )
    spec = cache[0]["spec"]
    assert spec.get("accessModes") == ["ReadWriteOnce"], (
        f"C02 AC4: the vllm-cache PVC must be RWO, got {spec.get('accessModes')}"
    )
    assert str(spec.get("resources", {}).get("requests", {}).get("storage")) == "10Gi", (
        f"C02 AC4: the vllm-cache PVC size must be the cachePvcSize default 10Gi, "
        f"got {spec.get('resources', {}).get('requests', {}).get('storage')}"
    )
