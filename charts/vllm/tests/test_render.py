# Render contract for charts/vllm (born in 2026/2026-11-cf-105-feat-implement-
# vllm C02 — AC1-AC4; re-pinned by cf-131 C02/C03): extract the service `vllm:`
# subtree, render with --set domain/clusterName, and assert AC2/AC3/AC4 line by
# line — the full contract serve recipe verbatim (the cf-105 D4 recipe until
# the C02 flip, the cf-131 D24 0.30 Shape-B recipe after it), the complete
# container env set (four vars, then the D25 twenty-var law), probes,
# securityContext, the privileged+hostPath device shape, GPU/RAM/shm pod shape,
# the exactly-two scrape annotations, the peer-hop Service name, the
# persistence legs (globalMounts until C03, the advancedMounts ro/rw split +
# the /cache move after it) and the C03 setup init container. Generation
# branching is explained in vllm_testlib; the deliberately-unchanged legs
# (security/devices/resources/annotations/Service/hand-written PVC) are every
# chunk's stability witness — if one ever needs a hand edit to stay green,
# that is scope creep, not test maintenance.

from __future__ import annotations

import re

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


def test_ac2_serve_args_are_the_contract_recipe_verbatim():
    """The rendered args equal the contract recipe in order: pre-flip the
    cf-105 D4 list with the service modelPath spliced at --model; from the
    C02 flip the cf-131 D24 list with the model PATH as args[0] — the 0.30
    entrypoint does `exec vllm serve "$@"`, so a vllm/serve token or a
    --model flag would double the verb the image already supplies (R3 L1.3).
    No silent mutation (add, drop, reorder, re-value) survives this bar."""
    docs, _ = _service_render()
    container = V.main_container(V.deployment(docs))
    block = V.service_vllm_block()
    sub = block.get("app-template")
    assert isinstance(sub, dict) and "modelPath" in sub, (
        "C07 AC2: the service vllm: block must carry modelPath under its app-template: subtree "
        "(the repo app-template idiom — the model splice source)"
    )
    model_path = sub["modelPath"]
    V.assert_model_path_shape(model_path, "service values")
    args = container.get("args", [])
    if V.cf131_plane():
        # The dual edit, render-side: chart anchor, service override and the
        # leading arg are the same exact raw-release dir (AC3).
        chart_model = (V.chart_values().get("app-template") or {}).get("modelPath")
        assert chart_model == model_path == V.MODEL_DIR, (
            f"C02 (cf-131) AC3: the dual edit diverged — chart modelPath {chart_model!r}, "
            f"service modelPath {model_path!r}, want both {V.MODEL_DIR}"
        )
        assert args and args[0] == model_path, (
            f"C02 (cf-131) AC2: args[0] is {args[:1]} — the pod args must START with the "
            "model path (the entrypoint supplies `vllm serve`, D24)"
        )
        double_verb = [a for a in args if a in ("vllm", "serve", "--model")]
        assert not double_verb, (
            f"C02 (cf-131) AC2: the args carry {double_verb} — a vllm/serve/--model token "
            "doubles what the 0.30 entrypoint already does"
        )
    got = V.flag_pairs(args)
    want = V.expected_recipe(model_path)
    assert got == want, (
        f"C02 AC2: rendered serve args diverge from the contract recipe\n  got:      {got}\n  expected: {want}"
    )
    if V.cf131_plane():
        # AC7's absence side named per flag (the exact-equality above already
        # excludes them — this leg exists so a failure says WHICH drop leaked).
        leaked = [flag for flag, _ in got if flag in V.DROPPED_FLAGS_CF131]
        assert not leaked, f"C02 AC7: dropped flags leaked into the render: {leaked}"


def test_ac2_container_env_is_exactly_the_contract_set():
    """The FULL env set: pre-flip the four cf-105 contract vars; from the C02
    flip the D25 twenty-var law exactly — and the three named drops
    (RADIANCE_GDN_LAZY absent because the feature is not in the 0.30 stack;
    HUGGINGFACE_HUB_CACHE / VLLM_SERVER_DEV_MODE dropped with the GGUF and
    sleep-mode stories)."""
    docs, _ = _service_render()
    env = V.env_map(V.main_container(V.deployment(docs)))
    block = V.service_vllm_block()
    sub = block.get("app-template")
    # Hard read (no .get default): the C02 top-level key is dead on the C07
    # block shape, and a fallback to a default that happens to equal the
    # rendered value would make the want-set a test-internal constant — the
    # service-coupling of the assert (rendered env follows the operator
    # re-pin surface) is what this arm pins.
    assert isinstance(sub, dict) and "rocrVisibleDevices" in sub, (
        "C07 AC2: the service vllm: block must carry rocrVisibleDevices under its app-template: "
        "subtree (the chip-targeting values key, D2)"
    )
    if V.cf131_plane():
        want = V.env_want_cf131(str(sub["rocrVisibleDevices"]))
        assert env == want, (
            f"C02 (cf-131) AC5: container env diverges from the D25 twenty-var set\n  got:      {env}\n  expected: {want}"
        )
        leaked = [name for name in V.DROPPED_ENV_CF131 if name in env]
        assert not leaked, (
            f"C02 AC5: dropped env vars leaked into the render: {leaked} — RADIANCE_GDN_LAZY "
            "names a feature absent from the 0.30 stack, the other two die with the GGUF "
            "cache and the sleep-mode surface"
        )
        return
    want = {
        "ROCR_VISIBLE_DEVICES": str(sub["rocrVisibleDevices"]),
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
    if V.cf131_plane():
        # The D18 40-min carry (60 s + 15 s × 160) is the EXACT budget, not a
        # floor: it is also the LIVE-262144 risk's loud gated refusal (D31) —
        # a drift here silently changes when a degenerate-pool boot fails.
        assert startup.get("periodSeconds") == V.PROBES_CF131["periodSeconds"], (
            f"C02 (cf-131) AC6: startup periodSeconds is {startup.get('periodSeconds')}, "
            f"want {V.PROBES_CF131['periodSeconds']} (the D18 carry)"
        )
        assert startup.get("failureThreshold") == V.PROBES_CF131["failureThreshold"], (
            f"C02 (cf-131) AC6: startup failureThreshold is {startup.get('failureThreshold')}, "
            f"want {V.PROBES_CF131['failureThreshold']} (the 40-min probe budget)"
        )
    else:
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
    assert sc.get("runAsUser") == 0, (
        "C02 AC2: runAsUser must be 0 (a non-root uid cannot open the host-group-486 /dev/kfd "
        "even under privileged — root is the proven zero-GPU-crash fix)"
    )
    assert "SYS_PTRACE" in (sc.get("capabilities") or {}).get("add", []), (
        "C02 AC2: capabilities.add must include SYS_PTRACE"
    )
    assert sc.get("allowPrivilegeEscalation") is not False, (
        "C02 AC2: allowPrivilegeEscalation must not be explicitly false "
        "(k8s rejects false alongside privileged: true — the strata shape omits the key)"
    )


def test_ac2_privileged_hostpath_devices():
    """The strata device-access ruling (EXPLORE 8.7) rendered: privileged
    plus the /dev/kfd (CharDevice) and /dev/dri (Directory) hostPath volumes
    mounted back at the same paths — the only sanctioned GPU device path on
    this node. The plugin side (no amd.com/gpu) is pinned in
    test_ac2_gpu_ram_shm_pod_shape; together the two tests hold the
    hostPath-for-privileged swap closed."""
    docs, _ = _service_render()
    container = V.main_container(V.deployment(docs))
    assert container.get("securityContext", {}).get("privileged") is True, (
        "C02 AC2: privileged must be true (the strata device-access ruling, EXPLORE 8.7)"
    )
    pod = V.pod_template(V.deployment(docs))["spec"]
    hostpaths = {v["hostPath"]["path"]: v["hostPath"].get("type")
                 for v in pod.get("volumes", []) if "hostPath" in v}
    assert hostpaths.get("/dev/kfd") == "CharDevice", (
        f"C02 AC2: /dev/kfd must be a CharDevice hostPath volume, got {hostpaths}"
    )
    assert hostpaths.get("/dev/dri") == "Directory", (
        f"C02 AC2: /dev/dri must be a Directory hostPath volume, got {hostpaths}"
    )
    mounts = {m.get("mountPath") for c in pod["containers"] for m in c.get("volumeMounts", [])}
    assert {"/dev/kfd", "/dev/dri"} <= mounts, (
        f"C02 AC2: the container must mount both host device paths, got {sorted(mounts)}"
    )


def test_ac2_gpu_ram_shm_pod_shape():
    docs, _ = _service_render()
    deploy = V.deployment(docs)
    pod = V.pod_template(deploy)["spec"]
    assert pod.get("hostIPC") is True, "C02 AC2: hostIPC must be true"

    container = V.main_container(deploy)
    resources = container.get("resources") or {}
    limits = resources.get("limits") or {}
    requests = resources.get("requests") or {}
    # The strata device-access ruling (EXPLORE 8.7): the GPU arrives by
    # privileged + hostPath /dev/kfd + /dev/dri (pinned in
    # test_ac2_privileged_hostpath_devices), so a device-plugin allocation
    # is a contradiction, not a second device source.
    assert "amd.com/gpu" not in {**requests, **limits}, (
        f"C02 AC2: amd.com/gpu contradicts the privileged+hostPath device ruling, got {resources}"
    )
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

    # 8Gi Memory emptyDir mounted at /dev/shm (R1 Q5 shm sizing, TP=1; the
    # D19 keep — the KVCACHE-tier 16Gi-shm headroom stays un-adopted).
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
    """The claims mount per generation: until C03 both legs ride
    globalMounts (models ro at /models, cache at /data); from the C03 flip
    the models leg is the advancedMounts actor split — the serve container
    reads /models, the setup container writes it — and the cache leg moves
    to /cache (the D25 env law's mount target), with the old /data subtree
    left unmounted (the one-cache-per-config law: GGUF-era cache content is
    incompatible with the 0.30 first boot)."""
    docs, _ = _service_render()
    pod = V.pod_template(V.deployment(docs))["spec"]
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
    deploy = V.deployment(docs)
    if V.staged_plane(deploy):
        main_mounts = {m.get("mountPath"): m for m in V.main_container(deploy).get("volumeMounts", [])}
        init_mounts = {m.get("mountPath"): m for m in V.init_container(deploy).get("volumeMounts", [])}
        assert main_mounts.get("/models", {}).get("name") == by_claim["llama-swap"]["name"], (
            f"C03 AC3: the main /models mount must bind the llama-swap claim, got {main_mounts.get('/models')}"
        )
        assert main_mounts["/models"].get("readOnly") is True, (
            "C03 AC3: the weights mount must be read-only on the serve container (the D1 read law)"
        )
        assert init_mounts.get("/models", {}).get("name") == by_claim["llama-swap"]["name"], (
            f"C03 AC3: the init /models mount must bind the llama-swap claim, got {init_mounts.get('/models')}"
        )
        assert init_mounts["/models"].get("readOnly") is not True, (
            "C03 AC3: the staging plane must WRITE /models — the advancedMounts ro/rw split is the D14 actor law"
        )
        assert main_mounts.get("/cache", {}).get("name") == by_claim["vllm-cache"]["name"], (
            f"C03 AC4: the /cache mount must bind the vllm-cache claim, got {main_mounts.get('/cache')}"
        )
        all_paths = {m.get("mountPath") for c in [V.main_container(deploy), V.init_container(deploy)]
                     for m in c.get("volumeMounts", [])}
        assert "/data" not in all_paths, (
            "C03 AC4: a /data mount survives the persistence restructure — the 0.30 caches land at /cache"
        )
        return
    mounts = {m.get("name"): m for c in pod["containers"] for m in c.get("volumeMounts", [])}
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
    asserted on the chart-defaults render where the default applies. The
    claim never moves across the ticket — C03 relocates its MOUNT path, not
    the PVC spec (AC7's byte-identical bar)."""
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


# --- C03: the setup init container (the staging actor, D14/D26) ---------------


def test_c03_setup_init_container():
    """Before C03 the data plane is the witness: the pod runs NO init
    container (staging is not yet on this commit). After the flip: exactly
    one, named setup, on the C01 re-export image (the init-image ==
    main-image triple), staging BOTH trees by revision pin with the
    both-sha marker — and NO fp8_mtp rewrite step (the round-2 Q8 raw-release
    ruling is the pin), device-free and root-but-unprivileged, with no env
    of its own (the offline law must not leak into the downloader)."""
    docs, _ = _service_render()
    deploy = V.deployment(docs)
    pod = V.pod_template(deploy)["spec"]
    if not V.staged_plane(deploy):
        assert not pod.get("initContainers"), (
            f"C03: the serve plane already runs init containers {pod.get('initContainers')} — "
            "staging belongs to C03's commit, not C02's"
        )
        pytest.skip("cf-131 C03: the setup init container is not on this commit yet")
    init = V.init_container(deploy)
    main = V.main_container(deploy)
    assert init.get("image") == main.get("image"), (
        f"C03 AC2: the init image {init.get('image')!r} must equal the main container's "
        f"{main.get('image')!r} (rendered from the SAME values keys)"
    )
    assert init.get("imagePullPolicy") == main.get("imagePullPolicy"), (
        "C03 AC2: the init pullPolicy must equal the main container's (the same first-build spec)"
    )

    command = init.get("command") or []
    assert command and all(isinstance(tok, str) for tok in command), (
        "C03 AC5: the init command must be a non-empty list (the two-download + marker script)"
    )
    body = "\n".join(command)
    assert ".staged-mxfp4" in body, "C03 AC5: the marker name .staged-mxfp4 is absent from the command"
    assert V.TARGET_SHA in body and V.DRAFTER_SHA in body, (
        f"C03 AC5: the command lacks a staging revision pin — both {V.TARGET_SHA[:8]}… "
        f"(raw release) and {V.DRAFTER_SHA[:8]}… (qualified drafter) must appear (D26)"
    )
    literal_marker = f".staged-mxfp4-{V.TARGET_SHA}-{V.DRAFTER_SHA}"
    marker_lines = [ln for ln in body.splitlines() if ".staged-mxfp4" in ln]
    if literal_marker not in body:
        # The chunk's command form keys the marker through shell variables
        # (`MARKER=/models/.staged-mxfp4-$TSRC-$TDRAFT`): accept that shape
        # only when the marker line interpolates the two assignments whose
        # values (checked above) are the revision shas.
        assert any(ln.count("$") >= 2 for ln in marker_lines), (
            f"C03 AC5: the marker line {marker_lines} is neither the both-sha literal nor a "
            "two-variable interpolation — the D14 re-fetch law keys on BOTH shas"
        )
    for needle in (V.TARGET_REPO, V.DRAFTER_REPO, V.MODEL_DIR, V.DRAFTER_DIR):
        assert needle in body, f"C03 AC5: the staging command does not reference {needle!r}"
    assert body.count("revision=") >= 2 and body.count("snapshot_download") >= 2 \
        and body.count("local_dir") >= 2, (
        "C03 AC5: the command is not the two `snapshot_download(revision=…, local_dir=…)` "
        "downloads landing both trees directly on the claim"
    )
    # The Q8 drop pin: the rewrite must be absent as a RUN STEP. The
    # chunk's literal command still NAMES fp8_mtp inside its `echo`
    # narrative (the staging log states what was skipped), so the pin is
    # scoped to executed lines: any non-echo line mentioning the rewrite
    # would be the dropped step re-landing.
    action_lines = [ln for ln in body.splitlines()
                    if ln.strip() and not ln.strip().startswith(("echo", "#"))]
    leaked_rewrite = [ln for ln in action_lines if "fp8_mtp" in ln]
    assert not leaked_rewrite, (
        f"C03 AC5: executable lines reference the fp8_mtp rewrite {leaked_rewrite} — the "
        "round-2 Q8 ruling ships the raw release as-is; the rewrite is the runbook's "
        "recorded contingency only (echo narrative is not a run step)"
    )

    resources = init.get("resources") or {}
    assert {k: str(v) for k, v in (resources.get("requests") or {}).items()} == \
        {k: str(v) for k, v in V.INIT_RESOURCES["requests"].items()}, (
        f"C03 AC5: init requests must be exactly {V.INIT_RESOURCES['requests']}, got {resources.get('requests')}"
    )
    assert str((resources.get("limits") or {}).get("memory")) == V.INIT_RESOURCES["limits"]["memory"], (
        f"C03 AC5: init memory limit must be 8Gi, got {resources.get('limits')}"
    )

    sc = init.get("securityContext") or {}
    assert sc.get("runAsUser") == 0, (
        "C03 AC5: runAsUser 0 on the init is the claim-ownership fact (root-owned dirs) — "
        "NOT the main container's GID-486 device law"
    )
    assert sc.get("allowPrivilegeEscalation") is False, (
        "C03 AC5: the repo privilege standard holds on the device-free init"
    )
    assert (sc.get("capabilities") or {}).get("drop") == ["ALL"], (
        f"C03 AC5: the init must drop ALL capabilities, got {sc.get('capabilities')}"
    )
    assert "privileged" not in sc, (
        "C03 AC5: the main container's approved privileged deviation must stay confined — "
        "no GPU work happens in the init (the script is pure network + disk IO)"
    )

    assert not init.get("env"), (
        f"C03 AC5: the init declares env {init.get('env')!r} — the image defaults apply; the "
        "serve pod's HF_HUB_OFFLINE law especially must not leak into the download step"
    )


# --- C03: the install-hint reword ---------------------------------------------


def test_c03_notes_point_at_the_030_shape():
    """The NOTES.txt Next-step pointer follows the shipped shape: the
    runbook stays the landing page, the sleep/wake time-sharing story dies
    with the Q7 drop and the GGUF-era 'weight find' phrasing goes with it
    (AC7's no-surface-claims reword)."""
    docs, _ = _service_render()
    if not V.staged_plane(V.deployment(docs)):
        pytest.skip("cf-131 C03: the NOTES reword lands with the data plane")
    notes = (V.CHART_DIR / "templates" / "NOTES.txt").read_text()
    assert "vllm-on-target-acceptance" in notes, (
        "C03: NOTES.txt lost the on-target runbook pointer (the install hint keeps its landing page)"
    )
    assert not re.search(r"sleep\s*/?\s*wake", notes, re.I), (
        "C03: NOTES.txt still advertises the sleep/wake time-sharing sequence — the Q7 drop "
        "makes the one-engine-per-card law the step-8 story"
    )
    assert "weight find" not in notes.lower(), (
        "C03: NOTES.txt keeps the GGUF-era 'weight find' phrasing — the pointer names the "
        "init-container staging fact + the day-one re-measure gate now"
    )
