# EXPLORE.md — cf-143 feat-radiance-replaces-strata (board card AD-143)

Scout grounding for the planner + researcher. Read-only pass over the repo
(worktree `cf-143-feat-radiance-replaces-strata`, branch of the same name, HEAD
`0d9b41785`) and the live gpu-ai cluster (`readonly-ai-gpu-kubernetes` probes).
Every claim below carries the file:line or cluster-read it came from. The card's
deployment-guide claims (pod security, memlock/nofile, pinned-RAM accounting,
TP2) are NOT evaluated here — flagged to research at the end.

Naming landmine up front: **"Radiance" already names two different surfaces in
this repo** — the vLLM fork image `magiccodingman/vllm-radiance:1.0.397` and its
re-export `ghcr.io/ownyourio/vllm-radiance-mxfp4` behind `charts/vllm` (every
`RADIANCE_*` env var in `charts/vllm/values.yaml` belongs to that fork). The
card's target is a third, unrelated project: `stilldeadcode/radiance`
(`docker.io/stilldeadcode/radiance`, 1.17.0, digest-pinned) replacing Strata
(`Niko1221/Strata`). Plan/research must keep these namespaces distinct or half
the tests/comments will attach to the wrong "radiance".

---

## 1. Strata-in-llama-swap peer wiring TODAY

### 1a. The peer block (outer instance) — `services/gpu-ai/prod/values.yaml`

- `llama-swap.config.peers.strata` — **lines 520-533**:
  `proxy: http://gpu-ai-llama-swap-strata.default.svc.cluster.local:8080`
  (line 522), five `models:` ids (525-530):
  `qwen3.8-flash-next-strata`, `qwen3.8-flash-next-strata-strix`,
  `qwen3.8-flash-next-strata-orca`, `qwen3.8-flash-next-strata-q4`,
  `ornith-1.5-122b-strata-q4`; `timeouts.responseHeader: 1800`,
  `timeouts.connect: 30` (531-533). No `apiKey` (keyless C-A ruling; comments
  505-519: no `/v1` suffix — the request path appends verbatim; peer models stay
  OUT of the outer matrix; models must be listed explicitly — peers is not a
  blanket URL proxy).
- `llama-swap.config.peers.vllm` — **lines 534-560**:
  `proxy: http://gpu-ai-vllm.default.svc.cluster.local:8000` (552),
  `models: [qwen3.8-27b-vllm]` (553-554), same timeouts (555-557), and the only
  `filters:` on the board — `setParams."priority?": 5` (558-560; the `?` suffix
  is part of the key = set-if-undefined floor; schema semantics at
  `charts/llama-swap/tests/schema/config-schema.v266.json:775-780`).
- Outer enablement context: `llama-swap:` block starts line 95;
  `config.families` full-on table 270-308; per-model overrides 318-454;
  `hooks.on_startup.preload: []` 502-504 (owner ruling 2026-11-02: nothing
  boots resident because llama-swap cannot evict across instances — the RAM law
  comment 493-501); outer `matrix.sets.main/solo` 561-599 (gpu-ai narrows the
  chart sets; peer engines are not matrix members).
- The peers subtree renders verbatim into the ConfigMap:
  `charts/llama-swap/templates/configmap-llama-swap.yaml` (whole file, 10 lines)
  → helper `llama-swap.declaredConfig` in
  `charts/llama-swap/templates/_helpers-llama-swap.tpl` (`.Values.config`
  passthrough; comment lines 35-36: macros/matrix/hooks pass through, only
  `models:` is derived).
- Golden echo of both peers: `charts/llama-swap/tests/golden/gpu-ai.config.yaml`
  line 1359 `peers:` — strata block then `vllm:` block with
  `priority?: 5`. Any peers edit forces a golden re-capture (TEST_SPEC §1
  pattern, header of `charts/llama-swap/tests/test_vllm_peer.py`).

### 1b. The strata engine pod — NOT a standalone chart

Strata is the **second controller of the llama-swap Application** (cf-77 run-2
consolidation). There is no `charts/strata/` directory. Definitions:

- `charts/llama-swap/values.yaml`:
  - controller `app-template.controllers.strata` — **lines 1087-1336**,
    default `enabled: false` (1088); `strategy: Recreate` (1093, pinned-RAM
    double-arena law); `pod.terminationGracePeriodSeconds: 420` (1104, invariant
    420 > unloadTimeout 180 + drain 30 + slack, comment 1100-1103);
    `pod.securityContext.supplementalGroups: []` (1106-1110, numeric GIDs
    resolved on-target per C04 runbook — still empty in the live pod),
    `seccompProfile.type: Unconfined` (1112-1117).
  - init `model-fetch` — 1153-1204: image `ghcr.io/ownyourio/strata:main`,
    `pullPolicy: Always` (1155-1164); `command: [/opt/strata/bin/fetch_models.sh]`
    exec-form boot guard (1165-1171); env `STRATA_QUANTS: "q3"` chart default
    (1172-1183); resources requests 200m/2Gi, limit 32Gi (1184-1196);
    `privileged: true` (1197-1204, HIP detection during setup).
  - main container `strata` — 1205-1336: image `ghcr.io/ownyourio/strata:main`
    + `Always` (rolling-pair law enforced by `test_strata_thin_init.py`,
    1207-1217); `args: ["-config", "/app/config/config.yaml"]` (1221-1223);
    **zero container env** — keyless C-A ruling deleted the secret chain
    (1224-1228); probes all `GET /health:8080` with startup 150×10s
    (1229-1259, probe law: never probe a model/upstream endpoint — it triggers
    loads); resources `requests: {cpu: 8, memory: 64Gi}`
    `limits: {memory: 110Gi}` (1260-1325, the full OOM post-mortem + owner
    rulings 2026-10-29 → 2026-11-10 are in that comment block);
    `privileged: true` (1326-1336) — **deliberate NOT-via-device-plugin
    posture**: "the plugin advertises by count and cannot name gfx1201 vs the
    8060S on this mixed APU+dGPU node" (1327-1335); chip hiding happens inside
    via `ROCR_VISIBLE_DEVICES`.
  - service — `app-template.service.strata` 1344-1355: `enabled: false`, port
    8080, ClusterIP, **no ingress** (Q4 internal-only ruling).
  - persistence — 1357-1460: `config`/`tools` via `advancedMounts` (directory
    mounts, never subPath — hot-reload law, 1359-1371/1407-1409);
    `models`: `existingClaim: *chartName` (= `llama-swap`) + `globalMounts
    [/models]` (1394-1402 — the ONE entry that stays globalMounts; strata
    shares the claim, Q3 ruling); `strata-config` + `strata-profile`
    (configMap directory mounts at `/app/config`, `/profile`; gated templates
    `configmap-strata.yaml`, `configmap-strata-profile.yaml`);
    `strata-kfd` hostPath `/dev/kfd` CharDevice + `strata-dri` hostPath
    `/dev/dri` Directory (both mounted into `strata` AND `model-fetch`,
    1427-1450); `strata-shm` emptyDir `medium: Memory` `sizeLimit: 2Gi` at
    `/dev/shm` (1451-1460, DOCKER.md `--shm-size 2g` equivalent).
  - **seven-flag enable set** (controller + service + five persistence flips
    TOGETHER; partial set hard-fails the render — comment 1076-1086): service
    values flip them on at `services/gpu-ai/prod/values.yaml:121-197`
    (controller `enabled: true` 135-136; init env override
    `STRATA_QUANTS: "q3,orca,q4,orn"` + `STRATA_MODEL_ORCA/Q4/ORN` + gated
    `HF_TOKEN` secretKeyRef on the init only, 170-183; `service.strata.enabled`
    184-186; five persistence enabled 187-197). Scalars-only override law
    (lists deep-merge REPLACE — comment 129-134).
  - workload DATA `strata:` — `charts/llama-swap/values.yaml:1473-2504`:
    `rocrVisibleDevices: "0"` (1477) + `rocrVisibleDevicesByModel`
    strix=`"1"` (1490-1491, PR #3636 enumeration; dGPU first); inner
    supervisor config 1502-1527 (`healthCheckTimeout: 1800`, `startPort: 10001`,
    `globalTTL: 0`, `apiKeys: []`, `logToStdout: "both"`); five inner models
    1529-1700 (each: `cmd: bash -c 'ulimit -n 524288; exec
    /opt/strata/terminal/bin/strata serve --profile /profile/<f>.json --host
    127.0.0.1 --port ${PORT}'` — the ulimit wrapper is load-bearing (no 0.2.x
    self-raises nofile, PR #2399 open), `ttl: 3600` (1800 strix),
    `unloadTimeout: 180`, `checkEndpoint: /health`, env list with
    `STRATA_REQUEST_LINES=1`, `MALLOC_MMAP_THRESHOLD_=1048576` (#5697),
    `STRATA_ALLOWED_HOSTS=gpu-ai-llama-swap-strata,...` (DNS-rebinding guard
    allow-list — a Radiance peer will need the same or its engine refuses the
    forwarded Host); primary rungs also carry the `STRATA_PF_FUSED/GEMM,
    STRATA_PA_FAST, STRATA_HIP_WMMA, STRATA_SELECT_WMMA,
    STRATA_PREFILL_CPU_SHARE` set (1570-1592) and ornith adds
    `STRATA_DENSE_MMQ=1` (1700)); inner matrix `(p | s | o | q | "n")` —
    alternatives never co-resident (1702-1726; the quoted `"n"` is YAML-1.1
    boolean-`n` hygiene, 1719-1724); five run-config profiles
    `engineProfile` 1741-1946, `engineProfileStrix` 1957-2073,
    `engineProfileOrca` 2113-2215, `engineProfileStrataQ4` 2233-2414,
    `engineProfileStrataOrnith` 2433-2504 — every tuning knob lives here
    (`exe: /models/strata/Strata/engine/strata` claim-compiled vs the packaged
    `/opt/strata/components/engine/0.1.59-linux-x86_64-hip-halo/strata` for
    strix; `--memory-limit-mib` per rung 110592/92160/103680 vs the 110Gi
    cgroup; `parallel: 8` everywhere except ornith `1`; `host: "127.0.0.1"`;
    `api_key: "none"`).
  - gated templates: `charts/llama-swap/templates/configmap-strata.yaml`
    (renders `.Values.strata.config` minus `engineProfile*` keys, injects the
    per-model `ROCR_VISIBLE_DEVICES` from `rocrVisibleDevices` /
    `rocrVisibleDevicesByModel` — lines 34-52) and
    `configmap-strata-profile.yaml` (the five `engineProfile*` → pretty JSON
    into one ConfigMap `strata-profile` — lines 20-28).
- The peer-shape authority file:
  `charts/llama-swap/tests/evidence/strata-peers-expected.yaml` (75 lines) —
  header law: "This file is the SINGLE source for the peers shape; the C03 dev
  edits services/gpu-ai/prod/values.yaml to MATCH it, never the reverse";
  `models_states` is an append-only history of exact sanctioned lists (current
  five-id state at lines 73-75). A radiance run must re-author this or its
  successor (it is test-writer property — dev may not edit it).

### 1c. Outer chart-side model/matrix surface (`charts/llama-swap/values.yaml`)

Outer config head 13-51 (`healthCheckTimeout: 3600`, `apiKeys: []` line 43,
`globalTTL: 0`, `unloadTimeout: 30`); macros 52-101; `filterPresets` 121-132;
`tagCultures` 139-~208; families catalog 209-873 (the served GGUF rungs, incl.
all flash-next/ornith rungs — peer model ids are NOT in here); outer matrix vars
875-954 + chart default sets 955-962. `app-template.controllers.llama-swap` main
container 972-1050: image `ghcr.io/mostlygeek/llama-swap`
`tag: unified-vulkan-266` (1005-1007, digest history comment 984-998:
`sha256:0cc42f1024b54be3de100ae7a7a2730047ca5c27cf7a354f8a9f63142f00c045`),
env `LLAMA_CACHE: /models`, `LLAMA_SWAP_CONFIG: /app/config/config.yaml`,
`LLAMA_SWAP_WATCH_CONFIG: "true"` (1010-1019), probes `/health:8080`
(1025-1039), resources `requests {cpu: 1000m, memory: 4Gi}` +
`limits {amd.com/gpu: 1}` (1040-1045), drop-ALL secCtx (1046-1050); `tools`
sidecar default-off 1056-1074 (gpu-ai enables it, service values 110-120).
`HF_TOKEN` injection pattern for gated downloads: service values 104-120
(secretKeyRef name `hf-token` key `token`) fed by the ExternalSecret template
(§5).

---

## 2. `charts/vllm/**` — full surface (this is the chart to DISABLE)

Files (all of them): `Chart.yaml`, `Chart.lock`, `values.yaml` (597 lines),
`templates/pvc-vllm-cache.yaml`, `templates/NOTES.txt`,
`tests/{vllm_testlib.py,test_trio.py,test_render.py,test_contract.py}`.
No secret templates (keyless in-cluster engine).

- `Chart.yaml`: `name: vllm`, `version: 1.0.0`, `appVersion: "0.30.0"`,
  single dep `app-template 5.0.1` from `https://bjw-s-labs.github.io/helm-charts/`
  (repo idiom, comment lines 6-9). `Chart.lock` digest
  `sha256:0ea7893a…`, generated 2026-11-06. NOTE: the "vendored tgz" leg of
  `test_contract.py` reads the lock; there is no `charts/vllm/charts/` dir
  present in the worktree (dependency fetched by CI via
  `helm dependency update`, workflow line 45).
- `values.yaml` anchors:
  - `cachePvcSize: 10Gi` line 8 (parent-only key — the hand-written PVC template
    reads chart top level, comment 5-7).
  - `app-template.modelPath: &modelPath /models/Qwen3.8-27B-Quark-AWQ-MXFP4`
    line 28 (raw release `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` @
    `93245f7c00f1a8964b66a97c6e02e2fd09080be4`; the **dual-edit law** — chart
    modelPath + service re-pin must move together because YAML anchors resolve
    per-document, comments 18-27 + the suite's `args[0] == service modelPath`
    assert).
  - `kvCacheDtype: &kvCacheDtype int4_per_token_head` line 49 (TRITON_ATTN-only;
    fp8 documented toggle).
  - `rocrVisibleDevices: "0"` line 55 (host enumeration; C06 rocminfo gate
    retargets the key, never the template).
  - `specMethod: "dflash"` line 76; `specConfig` JSON line 101 (draft
    `/models/Qwen3.8-27B-DFlash2-FP8` @ `ee0cb26a…`, K7).
  - `monitoring.annotations: true` line 106-107 (the two
    `k8s.grafana.com/*` ternary pod annotations, 262-264).
  - `serveArgs: &serveArgs` lines 172-245 — args START with the model dir
    (image entrypoint `/opt/radiance_entrypoint.sh` execs `vllm serve "$@"` —
    a verb token double-verbs it); served name `qwen3.8-27b-vllm` (174-175);
    `--tensor-parallel-size 1` (176-177); `--max-model-len 262144`; util 0.98;
    `--kv-cache-dtype-skip-layers sliding_window`; `--attention-backend
    TRITON_ATTN`; tool/reasoning parsers `qwen3_coder`/`qwen3`;
    `--scheduling-policy priority` + `--watermark 0.05` +
    `--language-model-only` (241-245, the priority-wiring half); the commented
    48 GB re-enable rider 227-240.
  - `global.createDefaultServiceAccount: false` line 252 (tokenless pod,
    home-assistant/mosquitto precedent).
  - `defaultPodOptions.hostIPC: true` line 256.
  - container image 272-288: `ghcr.io/ownyourio/vllm-radiance-mxfp4`,
    `tag: main`, `pullPolicy: Always`, **PIN-ME comment** 282-285 (pin the first
    `:v<run>` once docker-build ran on main, then drop Always — cf-105 C06
    step-10 law). Upstream ledger comment 273-281:
    `magiccodingman/vllm-radiance:1.0.397 @
    sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0`,
    OCI revision `5b99d66c…`, engine vLLM 0.30.0 @ `ced6857a`.
  - env 290-381 — the 21-var law: `ROCR_VISIBLE_DEVICES` (tpl'd from the values
    key, 307), `HIP_VISIBLE_DEVICES: "0"` (310), `HF_HUB_OFFLINE: "1"` (313),
    the four `/cache/*` pins (321-324), `FLASH_ATTENTION_TRITON_AMD_ENABLE`
    (334), `RADIANCE_WEIGHT_QUANTIZATION: auto` (340), `RADIANCE_MXFP4*` family
    (347-353), `VLLM_USE_V2_MODEL_RUNNER`, `RADIANCE_FAST_DRAFT` (359-360),
    `RADIANCE_COMPILATION_CONFIG` (366), `HSA_TOOLS_DISABLE_REGISTER` (372),
    `VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS: "0"` (381).
  - probes 386-420: `/health:8000`, startup 60s + 15s×160 (40-min envelope).
  - resources 421-428: requests 4 CPU/16Gi, **limits memory 32Gi** ("the cap
    that keeps the 125Gi node undisturbed while Strata's pod coexists" — RAM law
    comment references EXPLORE 8.6 of the cf-105 folder).
  - securityContext 429-460: `privileged: true`, `seccompProfile Unconfined`,
    `runAsUser 0`, `runAsGroup 44`, `capabilities.add: [SYS_PTRACE]`; the
    comment is the richest pod-security precedent in the repo (GID-486 vs image
    `video`=44 on openSUSE, runc capability-drop on setuid, the 2026-11-07
    crash-loop where the **device plugin allocated the 8060S**, why no
    `allowPrivilegeEscalation: false` next to `privileged: true`).
  - init `setup` 462-532: same image by anchor; `sh -c` staging script with the
    two revision shas as marker key (`TSRC=93245f7c…`,
    `TDRAFT=ee0cb26a…`, marker `/models/.staged-mxfp4-$TSRC-$TDRAFT`,
    493-508); resources 2/4Gi–8Gi; non-privileged `runAsUser 0` + drop-ALL
    (517-529); **no env** so `HF_HUB_OFFLINE` can't reach the downloader
    (530-532).
  - service 534-539 (`http` port 8000); persistence 541-597: `models` =
    `existingClaim: llama-swap` with per-container `advancedMounts`
    (`vllm` read-only, `setup` read-write — comment 542-552 incl. the
    do-not-delete GGUF warning), `cache` = `existingClaim: vllm-cache` mounted
    `/cache` (562-575), `shm` emptyDir Memory **8Gi** (576-582), `kfd`/`dri`
    hostPaths (583-597).
  - `templates/pvc-vllm-cache.yaml`: hand-written RWO PVC
    (`existingClaim` entries render no PVC — library law), size from
    `cachePvcSize`, `/cache` subtree rationale comments.
  - `templates/NOTES.txt`: prints the exact peer URL
    `http://{{ .Release.Name }}.default.svc.cluster.local:8000` + port-forward
    debug + pointer to the on-target runbook.
- Service wiring (`services/gpu-ai/prod/values.yaml`): `charts.vllm:
  {namespace: default, ServerSideApply: "false"}` lines 35-37;
  `ingress.subdomains` deliberately has NO vllm host (comment 48-52, D7/Q4
  ruling); top-level `vllm:` block 601-619 — exactly two overrides
  (`app-template.modelPath` 617, `app-template.rocrVisibleDevices: "0"` 619).
- `custom-values/gpu-ai/prod-values.yaml`: **zero vllm keys** (whole file 22
  lines: base argocd/cert-manager ids, hivetools mcp-sso, and
  `llama-swap.bitwardenIds.hf-token: 2ebdd082-4996-440b-a8c1-b4de01130738`
  line 22). `services/gpu/prod/values.yaml`: 0 hits for
  strata|vllm (checked) — both engines are gpu-ai-only.
- Grafana dashboards (vllm's monitoring tail):
  `services/monitoring/prod/values.yaml` lines 659-667 —
  `vllm-performance-statistics` + `vllm-query-statistics` url-pinned to
  `vllm-project/vllm/v0.33.0/examples/observability/dashboards/...` (the tag
  couples to the retired `containers/vllm-rocm` base per the comment).
- `.github/workflows/vllm-render-tests.yaml` (59 lines): triggers on
  `charts/vllm/**`, `containers/vllm-radiance-mxfp4/**`,
  `services/gpu-ai/prod/values.yaml`, itself; steps = `helm dependency update
  charts/vllm` + `pytest charts/vllm/tests -v` + `helm lint` + `helm template`
  chart defaults + `helm template` with the service `vllm:` subtree extracted
  by an inline python one-liner (lines 56-59). A disabled-but-commented chart
  must keep this workflow's extraction line from choking (it reads
  `d['vllm']` — a missing top-level `vllm:` key throws and fails the job).
- Provider catalog (`.opencode/opencode.jsonc`, provider `gpu-ai` starts
  line 76: `baseURL https://llama.spencerslab.com/v1`, `headerTimeout`/
  `chunkTimeout` 7200000 — 88-93): the three vllm rows at **795-815** —
  `qwen3.8-27b-vllm` (`body.priority: 5`), `qwen3.8-27b-vllm-urgent`
  (`modelID` still `qwen3.8-27b-vllm`, `priority: 1`), `qwen3.8-27b-vllm-low`
  (same modelID, `priority: 9`); all `{input: [text], output: [text], tools:
  true}`, context 262144 (D38 text-only honesty marker).
  Strata rows at **656-719**: `qwen3.8-flash-next-strata`,
  `…-strata-orca`, `…-strata-q4`, `ornith-1.5-122b-strata-q4` (context 262144,
  tools true, the `-strix` id is NOT cataloged — manual fallback only).
- `tests/pipeline-models/surface.sh` M-arms pinning the catalog: M3 (379-479:
  HOLD-presence of the rows incl. the three vllm rows' shared wire modelID,
  `body.priority` 5/1/9, and the negative "qwen3.8-27b-vllm must NOT be a local
  llama-swap model id" — 463), M4 (482-500: serving-fact cross-check — the id
  must appear in the serving authority, which today is
  `peers.vllm.models`), M7 (581-708: cf-105 priority wiring; the class-table
  needle rows at 699-708 pin urgent→`…-vllm-urgent`/1, default→`…-vllm`/5,
  low→`…-vllm-low`/9). **These needles live against the .rulesync/boilerplate
  tables** — see §5e.

---

## 3. The amd GPU device plugin — in-repo entry + live cluster truth

- In-repo: it is an **external chart** (`charts/` has no amd-gpu directory).
  `services/gpu-ai/prod/values.yaml:40-44` — `charts.amd-gpu: {version: 0.22.0,
  repository: https://rocm.github.io/k8s-device-plugin/, namespace: default,
  ServerSideApply: "true"}`. Grepping `services/`+`charts/` for
  `amd.com/gpu`: only the llama-swap chart's `limits.amd.com/gpu: 1`
  (`charts/llama-swap/values.yaml:1045`); the strata controller and charts/vllm
  never reference it (both use privileged hostPath instead — §1b/§2).
- Live (readonly-ai-gpu-kubernetes, 2026-11-11):
  - Node `ai-gpu` (single node, k3s v1.36.5, openSUSE Tumbleweed, kernel
    7.3.0-1-default, containerd 2.3.4-k3s1.36):
    **capacity = allocatable = `amd.com/gpu: 2`** — the plugin reports BOTH
    cards (R9700 gfx1201 + Strix 8060S gfx1151). `cpu: 32`,
    `memory: 131151328Ki` (≈125.08 GiB allocatable), `pods: 110`, swap
    2,148,204,544 B (~2.0 GiB — matches the "swap is 2.0 GiB, cgroup is the ONLY
    containment" law). Node labels: **only stock k3s labels — no custom GPU
    label**; no taints visible in spec.
  - DaemonSet `amd-gpu-device-plugin-daemonset` (ns `default`, 33d, 1/1 ready):
    container `amd-gpu-dp-cntr`, image `docker.io/rocm/k8s-device-plugin:1.31.0.9`,
    selector `name=amd-gpu-dp-ds`, nodeSelector `<none>`.
  - Pods consuming GPU today:
    - `gpu-ai-llama-swap-74467df97b-zkvbf` (Running): main container
      requests+limits `amd.com/gpu: 1` (live-verified) — plugin-allocated; it
      runs llama.cpp on the unified-memory 8060S (service values comment
      486-488), i.e. the plugin handed it the 8060S. drop-ALL, non-privileged.
    - `gpu-ai-llama-swap-strata-6cd875db6d-sr5m2` (Running):
      does NOT request `amd.com/gpu` — privileged + hostPath `/dev/kfd`+`/dev/dri`,
      pod seccomp Unconfined, `terminationGracePeriodSeconds: 420`, container
      requests 8 CPU/64Gi limit 110Gi, init `model-fetch` privileged
      (live-pod read; matches chart). `supplementalGroups` NOT set on the live
      pod either (chart ships `[]`). **The R9700 is occupied by the strata pod's
      five time-shared arenas** (ttl 3600/1800 lazy unloads; preload list empty).
    - `gpu-ai-vllm` Deployment exists (Argo Application `gpu-ai-vllm` exists)
      but **`spec.replicas: 0`, no pods running**; strategy Recreate; last
      condition transition 2026-11-11T14:11:24Z "Deployment has minimum
      availability" (Available=True at 0/0). The chart never sets replicas →
      the scale-to-zero was applied out-of-band (kubectl scale or an Argo
      operation; the repo has no replica key). Treat as: vllm is ALREADY not
      serving; the card's "disable" makes that GitOps-permanent. (Open question
      — §Open: who zeroed it; whether re-enabling the vllm chart later should
      carry `replicas: 0` in values or the chart default 1.)
  - PVCs (ns default): `llama-swap` Bound 500Gi (`pvc-e4f5adf3-…`),
    `vllm-cache` Bound 10Gi (`pvc-f986a778-…`). Provisioner:
    `local-path-provisioner` (kube-system).
  - Node image cache (useful digests): `ghcr.io/ownyourio/vllm-radiance-mxfp4:main`
    @ `sha256:887962d04f8a570ffbb0801f9edde5806f59c900fd7b745ccde97257b83e79a8`
    (+ prior `3b981e9c…`), `ghcr.io/ownyourio/strata:main` @
    `sha256:ded0447b500f17d423c88e2cbec927772391a4d8a48af5afdc1a3b439775814b`
    (+ `de8ccd35…`, `d95db6db…`), `ghcr.io/mostlygeek/llama-swap:unified-vulkan-266`
    @ `sha256:0cc42f10…` (chart-pinned digest confirmed on-node), plus the
    retired-era `ghcr.io/ownyourio/vllm-rocm:main` @ `452091b4…` (18 GB, still
    cached — the cf-105 v1 image; nothing references it except the
    monitoring-dashboard comment).

---

## 4. Strata pod-spec details to replace (consolidated from §1b + live pod)

- nodeSelector/tolerations: **none** (single-node k3s; control-plane pod
  scheduling allowed — every workload pod runs on `ai-gpu`).
- hostPath mounts: `/dev/kfd` (CharDevice), `/dev/dri` (Directory) — each into
  the serve container AND the staging init.
- privileged: `true` on both containers (serve + init model-fetch); pod level:
  `seccompProfile Unconfined`, `supplementalGroups []` (unresolved on-target;
  DOCKER.md wants video+render GIDs — the chart comment 1106-1110 defers them
  to the C04 runbook gate; live pod confirms never set).
- shm: emptyDir `medium: Memory` 2Gi at `/dev/shm` (vllm's equivalent is 8Gi —
  the Radiance guide's shm claims are a research item).
- `/models`: `existingClaim: llama-swap` (the outer chart's own
  `pvc-llama-swap-default.yaml` 500Gi claim on local-path; mounted whole via
  `globalMounts`; RWO same-node double-mount across the llama-swap + strata +
  vllm pods is the established single-node pattern — chart values 1394-1402,
  vllm values 542-552).
- probes: supervisor `/health` at 8080 (startup 150×10s; liveness+readiness
  plain). No container env, no secrets, args just `-config`
  `/app/config/config.yaml`.
- strategy Recreate; grace 420 s tied to `unloadTimeout 180` + engine drain 30.
- reloader: `reloader.stakater.com/auto: "true"` pod annotation on both
  controllers (config hot-reload belt; reloader deployment
  `gpu-ai-reloader-reloader` is live in-cluster).

---

## 5. Repo patterns a Radiance run will reuse

a. **OpenAI-compatible peer block**: copy the shape from `peers.vllm` (service
   values 534-560) — `proxy` (cluster DNS, port, NO `/v1`), `models` (explicit
   ids), `timeouts {responseHeader: 1800, connect: 30}`, optional
   `filters.setParams`. Schema authority: `config-schema.v266.json:734-810`
   (peer keys: `proxy`+`models` required; `apiKey`, `tailcatKey`, `filters`
   (stripParams/setParams), `timeouts` (connect/keepalive/responseHeader/
   tlsHandshake)). Keep the evidence-file law in mind (§1b end).

b. **ExternalSecret/Bitwarden pattern**: `charts/llama-swap/templates/
   secret-hf-token.yaml` (30 lines) is the template to mirror — guarded on
   `bitwardenIds`, `external-secrets.io/v1`, `storeRef: bitwarden-login
   (SecretStore)`, `remoteRef.key` = Bitwarden item UUID, `property: password`.
   charts/vllm ships NO secret template; strata's keyless ruling means the only
   in-cluster API-key precedent for a peer is… none (both peers are keyless;
   outer `apiKeys: []` chart values line 43). UUIDs live in
   `custom-values/gpu-ai/prod-values.yaml` (`llama-swap.bitwardenIds.hf-token`
   line 22). The header comment names `charts/audiomuse-ai` as the repo-wide
   pattern home.

c. **Chart entry shape in the ApplicationSet values**: add to
   `services/gpu-ai/prod/values.yaml` `charts:` — internal chart (no
   version/repository, renders from `charts/`) = `{namespace: default,
   ServerSideApply: "false"}` (the llama-swap/vllm precedent, lines 22-24,
   35-37); external = `version` + `repository` (+ the commented `# renovate:
   datasource=helm …` idiom on lines 26-27/31-32 where pinned). The
   ApplicationSet machinery itself: `services/gpu-ai/prod/templates/appset.yaml`
   (clusters×list matrix, `baseChartVersion: 1.0.198` with a
   `# renovate: datasource=helm` comment, templatePatch resolves per-chart
   Applications from `Values.charts`). Trio rule: chart entry + service values
   entry + proxy entry — with the **documented skip** for internal-only engines
   (no ingress host; the strata Q4 / vllm D7 comments, service values 48-58,
   are the precedent text to mirror verbatim for radiance).

d. **Test layout**: per-chart pytest `charts/<chart>/tests/` (run
   per-directory: `python3 -m pytest charts/llama-swap/tests -v` — basenames
   duplicate across suites) with a `<name>_testlib.py` render helper
   (`helm_ready()` skip gate; the repo lesson: export
   `PATH=$HOME/.local/bin:$PATH` or helm-guarded tests silently mass-skip),
   evidence YAMLs + a byte-golden under `tests/golden/`, plus bash contract
   scripts under `tests/<group>/` (`tests/notes/vllm-runbook.sh` T1-T5,
   `tests/services/vllm-dashboards.sh` t1-t4,
   `tests/containers/vllm-radiance-mxfp4.sh` t1-t7,
   `tests/pipeline-models/surface.sh` M1-M7 — none wired into GitHub workflows;
   the pipeline test sessions run them). CI shape for a new chart = clone
   `.github/workflows/vllm-render-tests.yaml`.

e. **Operator docs to mirror for a Radiance runbook**:
   `.agents/notes/vllm-on-target-acceptance.md` (the 0.30 acceptance runbook —
   ~1,200 lines: names-block pin ledger, rocminfo gate §1, staging, DRY_RUN
   args capture, re-measure gate, catalog/priority steps 4-5, KV watch §6,
   Strata-coexistence observation §9 lines 1080-1101, issue watch §10),
   `.agents/notes/strata-host-prep-gpu-ai.md` (host prep + enablement, operator
   owned), `.agents/notes/strata-parallel-tuning-runbook.md` (cf-141 tuning
   runbook: pin & envelope board §1, gates §4, ladder §6),
   `charts/llama-swap/README.md` (interface freeze table + peers URL + per-rung
   caps; lines 6-71), `containers/strata/README.md` (image ledger),
   `containers/vllm-radiance-mxfp4/README.md` (tag→digest pin table).

f. **Skill/agent-context surfaces naming the vllm/strata ids** (comment, don't
   delete, per the launch hint; surface.sh M1/M2/M5 pin these strings):
   `.rulesync/skills/pipeline-models/SKILL.md` — combination rule line 34
   (Flash+Local → `gpu-ai/qwen3.8-flash-next-strata-q4`), Priority class table
   lines 45-48 (the vllm rows), favorited-table rows 59-63
   (`…-strata-q4` row + the three `…-vllm*` rows);
   `.rulesync/skills/pipeline-kickoff/SKILL.md` line 26 (route derivation);
   `.rulesync/skills/boards/SKILL.md` line 251 (Strata default route). Edits go
   in `.rulesync/` then `rulesync generate` (never hand-edit
   `.opencode/skills/`) — M6 (surface.sh 552-567) checks mirror integrity.
   Also the runner-model literal in AGENTS.md ("Pipeline worker iterations":
   `gpu-ai/qwen3.8-flash-next-strata-q4` — owner-ruling-owned, not a
   pipeline-agent edit).

---

## 6. Renovate handling of the vllm/strata/llama-swap image pins

- `renovate.json` (302 lines, packageRules tail): the ONE relevant rule is
  lines 284-293 — `ghcr.io/mostlygeek/llama-swap` scoped
  `versioning: "regex:^unified-vulkan-(?<major>\d+)$"` because the built-in
  `helm-values` manager extracts the `repository:`/`tag:` pair from
  `charts/llama-swap/values.yaml` and default docker versioning can't parse the
  tag family. No rule exists for strata, vllm-radiance-mxfp4, or the
  magiccodingman upstream.
- Pin comment shapes in use:
  `charts/llama-swap/values.yaml:1006` —
  `# renovate: datasource=docker depName=ghcr.io/mostlygeek/llama-swap` above
  `tag: unified-vulkan-266`.
  `charts/vllm/values.yaml` — NO renovate comment: `ghcr.io/ownyourio/*`
  re-exports are rolling `:main` + `Always` by the first-build/PIN-ME law
  (282-285); versioned `:v<run>` adoption is "a Renovate chores decision, never
  a hand-bump" (chart values 1157-1164/1209-1215 for strata's image too).
  `containers/strata/Dockerfile:8-14` — explicit **no renovate comment** ruling
  (coord ruling (b): no manager extracts the ARG pin; the README's tag→digest
  ledger + manual bump procedure is the cadence owner; #3421 and the
  unified-vulkan-262 in-place rebuild are the cited why).
  `containers/vllm-radiance-mxfp4/Dockerfile:58` —
  `ARG FLASH_ATTN_VERSION=2.8.3.post2` (the one sanctioned overlay layer).
  `services/gpu-ai/prod/values.yaml:26-27,31-32,42-44,appset 33` —
  `# renovate: datasource=helm registryUrl=…` idiom on external chart versions
  (amd-gpu `0.22.0` is a live, renovate-visible version entry).
- Consequence for the card's target: a `docker.io/stilldeadcode/radiance:1.17.0`
  digest pin is a NEW datasource. The repo has two sanctioned postures — (i)
  renovate-comment + tag on the upstream public image (llama-swap precedent),
  or (ii) thin re-export under `containers/` with rolling `:main` + ledger
  (strata/vllm precedent, docker-build.yaml pushes `:v<run>` + `:main`). Which
  posture Radiance takes is a planning decision; research should verify the
  upstream image's tag/digest hygiene (the values 984-998 comment is the
  cautionary record: tags CAN be rebuilt in place).

---

## 7. Second-R9700 / TP2 notes already in-repo

- `charts/vllm/values.yaml:176-177` — shipped `--tensor-parallel-size 1`;
  `:96-97` — omitted `draft_tensor_parallel_size` ("TP1 — their TP2 profile
  sets 2").
- `.agents/notes/vllm-on-target-acceptance.md` — line 114 ("exists at any TP1
  shape (R3 L2.4); the 0.30 TP2 Quark capacity table is …"), 736 and 758
  (the 30/30 tool record is TP2-only — "two GPUs is the only configuration
  tested so far"), 910-931 (the 0.30 TP2 cross-stack SANITY class — record,
  not expectation; K7 TP2 row 42.26%/3.958 = sanity bar).
- cf-131 chunk records: `.agents/plans/2026/2026-11-cf-131-feat-vllm-fp8-official/chunks/C04.md:130`,
  `chunks/C05.md:20-21,88,363,488`.
- cf-141 RESEARCH (`…cf-141-refactor-strata-parallel-tuning/RESEARCH.md:386-414,
  465-471`) — gfx1201 issue cluster incl. **#3364**: open, "[Engine]
  expert-cache auto does not reserve memory for --batch slots", reporter box
  **2× R9700 gfx1201** — the only published twin of a TP2-class Strix-Halo+R9700
  setup in the repo's evidence.
- Node today reports `amd.com/gpu: 2` = {R9700, 8060S} — a second physical R9700
  would make 3 devices / change host enumeration and the
  `rocrVisibleDevices`/`ROCR_VISIBLE_DEVICES` index law in EVERY engine (chart
  values 1480-1491 strix-index comment is the enumeration record). Nothing in
  the repo documents a second R9700 as purchased/planned — the TP2 story is all
  upstream-capability, not local-hardware. Card-guide verification: research.

---

## 8. llama-swap's own deployment + appset entry shapes

- Deployment: single Application `gpu-ai-llama-swap` (live), chart
  `charts/llama-swap` (app-template 5.0.1 umbrella; Chart.yaml 8 lines,
  `version 1.0.0`+lock), two controllers (§1), services
  `gpu-ai-llama-swap:8080` + `gpu-ai-llama-swap-strata:8080`, ingress surface:
  `services/gpu-ai/prod/values.yaml:59-73` — `ai-llama-swap` subdomain (direct)
  + `llama` subdomain (`clusterBase: true` + `serviceName: llama` → renders
  `llama.gpu-ai.<domain>` internal hop AND public `llama.<domain>`); the
  timeout chain: `services/gpu-ai/prod/templates/generic-ingress.yaml`
  (annotation `traefik.ingress.kubernetes.io/service.serverstransport:
  default-llama-timeouts@kubernetescrd`, lines 15-17) +
  `servicestransport-llama.yaml` (same dir; long-load timeouts). Public chain:
  `services/proxy-local/prod/values.yaml:286-298` (llama → gpu-ai reroute, SSO
  redirect to `/ui/`) and `services/proxy-remote/prod/values.yaml:92-97`.
  The gpu-ai provider's `baseURL` (`https://llama.spencerslab.com/v1`) rides
  that chain — so peer models served via llama-swap automatically reach
  OpenCode without provider URL changes; only catalog ROWS change.
- Peer reach: pure cluster DNS service names (chart values 1350-1355:
  "app-template fullname + controller key… read it from NOTES, keep the no-/v1
  suffix shape"); NO apiKeys env anywhere (outer `apiKeys: []`, inner
  `apiKeys: []`, profiles `api_key: "none"`); profiles/hooks: outer
  `hooks.on_startup.preload: []` (service 502-504), inner preload commented-off
  shape (chart values 1593-1598), engine profiles = the five
  `engineProfile*` (§1b).
- New-chart entry shape to copy: `charts:` map entry (§5c) + top-level `<name>:`
  values block + `ingress.subdomains` skip comment; internal chart →
  `charts/<name>/` with the app-template dep trio (Chart.yaml/Chart.lock via
  `helm dependency update`, values.yaml, templates/, tests/).

---

## Gotchas (established, each with its source)

1. **subPath never hot-reloads**: every ConfigMap mount in this chart is a
   DIRECTORY, never subPath (chart values 1359-1365, 1407-1409; the 2026-10-17
   whisper incident). A radiance config/profile mount follows the same law.
2. **advancedMounts vs globalMounts**: `advancedMounts` naming a DISABLED
   controller hard-fails the render, and a globalMount attaches to EVERY
   enabled controller (collision with strata's own `/app/config` — why
   config/tools enumerate). Only `models` stays global. (chart values 1076-1086,
   1366-1371, 1395-1402.)
3. **Helm deep-merge REPLACES lists wholesale**: service values may flip
   strata scalars only — never engineProfile args / model env lists / mount
   lists (service values 129-134). A radiance service block inherits this law.
4. **YAML 1.1 boolean gotcha**: bare `n:` matrix var key parses to `False` —
   quote it (chart values 1719-1724). Same family: `on_startup` etc. quoted
   where needed.
5. **`OVERRIDE_VIA_CUSTOM_VALUES` / `OVERRIDE_VIA_APPSET` sentinels**: chart
   values `domain: OVERRIDE_VIA_APPSET` line 1; service values lines 9-10;
   `bitwardenIds.hf-token: OVERRIDE_VIA_CUSTOM_VALUES` service line 98 — the
   suite (`test_ac1_render_produces_deployment_without_sentinels`,
   charts/vllm/tests/test_render.py AC1) fails any render still carrying an
   `OVERRIDE_` string. Secret templates guard on the id so clusters without one
   render clean (secret-hf-token.yaml line 7).
6. **ServerSideApply**: vllm/llama-swap entries use `"false"`; SSA +
   list-shaped controller data was the drift class — match `"false"` for a
   llama-swap-family chart (service values 22-24, 35-37).
7. **Anchors resolve per-document**: the vllm service re-pin does NOT reach the
   chart's serveArgs splice — retarget is a dual edit guarded by
   `args[0] == service modelPath` (vllm values 18-27/144-148; service values
   607-616). A radiance chart using anchors copies this trap.
8. **`exec`-form init commands as boot guards**: `/bin/sh -c` fallbacks are the
   rejected alternative; loud-fail at container start is the design
   (chart values 1143-1152, 1165-1171).
9. **SanitizeCommand strips backslash continuations**: multi-line `cmd:` values
   must stay one physical line inside `/bin/sh -c` scripts (service values
   436-442).
10. **Probe law**: kubelet probes hit the SUPERVISOR `/health` only — probing a
    model/upstream endpoint triggers loads and isn't probe-safe (chart values
    1229-1234).
11. **DNS-rebinding guard / allowed hosts**: engine `*_ALLOWED_HOSTS` must
    enumerate the peer-forwarded Service DNS forms (chart values 1564-1570,
    1592) — a radiance peer gets a new service name → new allow-list entries.
12. **Peers truth lives in the evidence file, not values**
    (`strata-peers-expected.yaml` header): dev edits values to match the
    evidence; the evidence is test-session property. Golden re-capture is the
    companion obligation (test_vllm_peer.py header T4).
13. **vllm is currently scale-0 out-of-band** (§3): the GitOps tree still says
    1 replica; commenting-out vs leaving the Deployment zero matters — an Argo
    sync with selfHeal could resurrect it (the `gpu-ai-vllm` Application is
    live). No `replicas:` key exists in the chart or service values today.
14. **workflow path-triggers**: `.github/workflows/vllm-render-tests.yaml` keys
    on `services/gpu-ai/prod/values.yaml` — edits for radiance/strata will also
    run the vllm workflow, and its inline `d['vllm']` extraction fails if the
    top-level `vllm:` key is deleted (workflow 56-59). "Leave commented-out
    entries" keeps that green only if the `vllm:` key itself remains or the
    workflow is amended.
15. **rolling `:main` + `pullPolicy: Always` is LAW on ownyourio re-exports**
    (thin-init pair test, boot-guard self-heal rationale) — a digest-pinned
    `docker.io/stilldeadcode/radiance` is a posture CHANGE; the repo's digest-
    pin precedents are comments/ledgers, not `image.digest` fields (no
    `digest:` usage in either chart's image blocks — app-template's image
    schema supports repository/tag/pullPolicy here).

## Open ground not covered (hand-offs)

- **Research (AD-143 guide verification)**: every claim of the card's deployment
  guide (stilldeadcode/radiance 1.17.0 image + digest, memlock/nofile,
  pinned-RAM accounting, supplementalGroups/seccomp/IPC_LOCK, per-profile
  flags, TP2 section) — none of it is in-repo; only the equivalents for
  Strata/vllm are grounded above. Also: whether `stilldeadcode/radiance` is the
  renamed/successor of `Niko1221/Strata` (same-author hypothesis — would change
  the replacement story's semantics) and how it relates to `magiccodingman/
  vllm-radiance` (different project per all repo evidence; confirm).
- **Coord/owner facts**: who/when scaled `gpu-ai-vllm` to 0 and whether the
  "disable" should carry an explicit `replicas: 0` (commented) or GitOps prune;
  whether the owner intends the radiance pod to REPLACE strata in the
  llama-swap Application (second controller, the cf-77 consolidation shape) or
  ship as its own chart+Application (the card says "NEW chart" — but the strata
  peer wiring it says to mirror lives inside the llama-swap chart; that
  structural tension is a planning decision, not a repo fact).
- **Not grounded (depth)**: amd-gpu helm chart internals (external repo, not
  vendored); the `services/gpu` box's disabled-override pattern detail
  (chart values line 960 reference); live Grafana dashboard provisioning state
  for the two vllm dashboards beyond the values pin; Argo Application health
  fields (MCP list returned names only); whether the runner model literal
  `gpu-ai/qwen3.8-flash-next-strata-q4` (AGENTS.md + loops file) is in scope
  for the switchover — owner-ruling-owned.
- **Test-authority obligations on any peers change**: re-capture
  `tests/golden/gpu-ai.config.yaml`, re-author `strata-peers-expected.yaml`
  (or its successor evidence), M-arm re-pins in `tests/pipeline-models/
  surface.sh` for whatever replaces the strata route strings, and the
  `rulesync generate` round-trip for `.rulesync/skills/*` edits (§5f).

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md]
commands_run: [repo reads/globs/greps (values, workflows, tests, notes, containers, renovate.json, opencode.jsonc, .rulesync skills) => pass; git status/log read => pass (branch cf-143-feat-radiance-replaces-strata @ 0d9b41785, clean-ish, no writes); readonly-ai-gpu-kubernetes: nodes+capacity (amd.com/gpu:2, 125.08GiB, 32cpu), DaemonSet list (amd-gpu-device-plugin 1/1 @ rocm/k8s-device-plugin:1.31.0.9), pods default ns, strata+llama-swap pod specs, gpu-ai-vllm deployment (replicas 0), PVCs (llama-swap 500Gi Bound, vllm-cache 10Gi Bound), Application list => pass]
deviations: none — stayed read-only; wrote only EXPLORE.md in the ticket folder.
friction: readonly-ai-gpu-kubernetes resources_list returns flattened summary objects (Name/Images/… keys), not raw manifests; use pods_get/resources_get for spec detail. Application list carries no health fields through that MCP. The vllm-render workflow's inline python depends on the top-level vllm: key — noted as gotcha 14 rather than friction.
open_questions: [Needs research: yes — verify stilldeadcode/radiance 1.17.0 guide claims + its identity vs Niko1221/Strata and vs magiccodingman/vllm-radiance (namespace collision). Coord/owner: why is gpu-ai-vllm scaled to 0 today and should the disabled shape carry replicas:0?; should the new radiance chart be a llama-swap second controller (strata-consolidation shape) or its own ApplicationSet entry (card's "NEW chart")?; is the strata route string in AGENTS.md/loops/pipeline-models tables in scope this run?]
next_suggested: agent-research on the card guide + radiance identity, then agent-plan; plan should read §Gotchas 12-15 and the open structural question before chunking.

## §D1 — C08 conversion: container command dropped (live RunContainerError) (2026-11-13, scout round 2, HEAD 5d2afd129)

The owner's live error is real, on-target, and root-caused: `exec: "-logtostderr=true":
executable file not found in $PATH` on the converted `gpu-ai-amd-gpu-device-plugin-daemonset`
pod (container `deviceplugin`, Waiting/RunContainerError, exit 128 StartError). The plugin
image has **no ENTRYPOINT — the binary ships in CMD only**, so declaring `args` without
`command` makes args[0] the exec path. The C07 args-hook, the parity oracle, and the C08
conversion ALL carry the same broken shape: the oracle could never witness the defect
because the oracle *is* the defect.

### D1.1 LIVE GROUNDING (readonly-ai-gpu-kubernetes, ns default, 2026-11-13)

- DaemonSet `gpu-ai-amd-gpu-device-plugin-daemonset`: age ~5 min, Desired 1, Ready 0;
  labels carry `helm.sh/chart=app-template-5.0.1`, container `deviceplugin`, image
  `docker.io/rocm/k8s-device-plugin:1.31.0.12`. The OLD `amd-gpu-device-plugin-daemonset`
  (1.31.0.9) is GONE — the D23 one-sync prune+create swap completed (the swap law worked;
  the payload is what fails).
- Pod `gpu-ai-amd-gpu-device-plugin-daemonset-kfvnr` (node ai-gpu), CrashLoopBackOff, 5
  restarts: `spec.containers[0].command` = **absent (null)**, `args` = exactly
  `[-logtostderr=true, -stderrthreshold=INFO, -v=5, -resource_naming_strategy=product]`;
  `containerStatuses[0].state.waiting`: reason `RunContainerError`, message
  `…error during container init: exec: "-logtostderr=true": executable file not found in $PATH`;
  lastState.terminated reason `StartError`, exitCode 128. The live spec matches the local
  render (D1.3) field-for-field.
- DOWNSTREAM STALL (ticket-wide blast radius, cite in the fix card): pods
  `gpu-ai-radiance-59c96d5bcd-dsscv` and `gpu-ai-llama-swap-779b58445d-mmwrj` are **Pending**
  (no node advertises `amd.com/gpu-r9700-1` / `amd.com/gpu-8060s` while the plugin is down —
  the D24 product pools exist only once this container starts). `gpu-ai-llama-swap-strata-…`
  keeps Running (32h) on its pre-swap allocation — §R6-Q4 allocation law holding.

### D1.2 THE PARITY ORACLE — it has NO command (the oracle is broken, not the conversion)

- `charts/amd-gpu/tests/evidence/pre-c08-deviceplugin-ds.yaml`: container block lines 35–43:
  `args:` (36–40, the four items), `image: docker.io/rocm/k8s-device-plugin:1.31.0.12` (41),
  `name: amd-gpu-dp-cntr` (42) — **no `command:` key anywhere in the file** (the vendored
  render it captured simply omitted it).
- The template that produced it — `git show a81989b47^:charts/amd-gpu/templates/deviceplugin-daemonset.yaml`
  (the C07 vendored 0.22.0+args-hook): container starts line 35, `image:` line 36, `args:`
  line 40 — the ~10-line args hook emitted `args` ONLY; grep confirms zero `command` lines
  in that template. It did NOT set a binary path. The bug was BORN here (C07) and was never
  live-tested: gpu-ai kept running the EXTERNAL 0.22.0 chart (no args surface, image default
  CMD) until the C08 swap landed this shape on the cluster for the first time.
- `git show 0d9b41785:…` → path does not exist at that commit (charts/amd-gpu was vendored
  later in the run) — the launch's first citation is void, the a81989b47^ one is the real
  pre-conversion template.

### D1.3 THE SHIPPED CONVERSION — render reproduces the oracle exactly (faithful port of a broken shape)

- `cp -r charts/amd-gpu /tmp/cf143-amd-gpu-explore && helm dependency update .` (app-template
  5.0.1 tgz fetched from bjw-s-labs) → `helm template gpu-ai-amd-gpu .` (helm v3.16.4):
  the DaemonSet's container (`deviceplugin`) renders `args:` with `-logtostderr=true` FIRST
  and the four items, `image: docker.io/rocm/k8s-device-plugin:1.31.0.12`, NO `command:` —
  identical to the live pod (D1.1). Values source: `charts/amd-gpu/values.yaml` — container
  keys are exactly `image` (94), `args` (111–115), `securityContext` (116+); no command key.
- So C08's conversion is NOT where the field was dropped — `command` was absent upstream of
  it. The "PARITY, NOT IMPROVEMENT" law executed perfectly against an oracle that itself
  predates any successful live run of that shape.

### D1.4 APP-TEMPLATE 5.0.1 SURFACE (vendored tgz, extracted /tmp/at501)

- Values key (schema): `controllers.<name>.containers.<container>.command` —
  `app-template/values.schema.json` → `$.properties.controllers.additionalProperties
  .properties.containers.additionalProperties.properties.command`: `oneOf [array-of-strings,
  string]`, description "Command for the container entrypoint." (`defaultContainerOptions
  .command` also exists). `args` is the sibling key.
- Render: `charts/common/templates/lib/container/_spec.tpl` lines 15–17:
  `{{- with (include "…field.command" …) }} command: …` — command renders ONLY when the values
  key is set; `fields/_command.tpl` lines 4–23: string → wrapped into a one-element list
  (14–15), list → verbatim toYaml (17), unset → empty → skipped. **There is NO entrypoint-
  providing default: with only `args` set the library emits `args` and never `command`**
  (same symmetric logic in `fields/_args.tpl`). The library cannot know the image lacks an
  ENTRYPOINT — the values must carry `command`.
- Repo precedent (app-template charts): `command:` + `args:` pairs in values are an established
  idiom — `charts/betanin/values.yaml:25` (`command: ["/bin/sh", "-c"]` + args),
  `charts/archon/values.yaml:21-27` (command list), `charts/erp-next/values.yaml:140,173`
  (`command: ["bash","-c"]` + args), and INSIDE this ticket's own chart:
  `charts/radiance/values.yaml:318` (curl init container `command: [sh, -c, …]`).
  `charts/amd-gpu` is the first app-template workload that needed the binary itself and didn't
  declare it.

### D1.5 THE IMAGE AUTHORITY — no ENTRYPOINT, binary lives in CMD (registry + Dockerfile, both at the exact pin)

- Registry (docker.io API, anonymous pull; tag manifest `docker-content-digest` =
  `sha256:6437c74f6566e5d11c20c42369fca7194315943aea91f7bd6c98de1b19caf117` — EXACTLY the
  amd64 ledger digest in `charts/amd-gpu/values.yaml:104-106`, so this config IS the pinned
  bytes; config blob `sha256:740b1675d6a980236a2f5138a04738c5806a7dc1484ff562ab8d68ed0eae6d79`):
  `image.config` = **no `Entrypoint`**, `Cmd: ["./k8s-device-plugin", "-logtostderr=true",
  "-stderrthreshold=INFO", "-v=5"]`, `WorkingDir: "/root/"`, `User: root`.
  → K8s semantics: `command` overrides ENTRYPOINT (empty here), `args` overrides CMD —
  declaring args alone leaves process = args, and runc execs `-logtostderr=true`. The exit-128
  message is the exact predicted shape. Note the CMD is FOUR items: binary + trio — the
  "CMD trio restated in full" comment law (`values.yaml:108-110`, testlib
  `CMD_RESTATED` line 72) restated only the FLAGS half and silently dropped the binary half.
- Dockerfile (raw GitHub, tag `v1.31.0.12` exists — `ROCm/k8s-device-plugin/Dockerfile`):
  final stage `WORKDIR /root/` + `COPY --from=0 /go/bin/k8s-device-plugin .` → the binary is
  **`/root/k8s-device-plugin`**; `CMD ["./k8s-device-plugin", "-logtostderr=true",
  "-stderrthreshold=INFO", "-v=5"]`; NO ENTRYPOINT line. Same fetch CONFIRMS the D24 mount
  law holds at this tag: `COPY … /usr/share/libdrm/amdgpu.ids` (the IDS_PATH const).
- Upstream HELM chart 0.22.0 (`amd-gpu-helm-0.22.0` tag, `helm/amd-gpu/templates/
  deviceplugin-daemonset.yaml`): container block = name/image/securityContext/volumeMounts/
  resources ONLY — no `command:`/`args:` lines at all (validates the vendored Chart.yaml
  header claim "it has no args/command surface at all"). With no args declared the runtime
  uses the image CMD wholesale, binary included — which is why the 5-week-old external-chart
  pod ran fine at 1.31.0.9.

### D1.6 THE TEST GAP — zero `command` legs in the whole amd-gpu suite

- `grep -rn command charts/amd-gpu/tests/ tests/services/amd-gpu-naming.sh` → **no match**.
  The parity-leg inventory (`test_render.py`): args == ARGS_CONTRACT (61), -v=5 alone (74),
  image==oracle (84), pod facts priority/tolerations/secctx/nodeSelector-absent/
  imagePullSecrets-absent/resources-empty (99), hostPath trio + mounts byte-parity incl the
  extra-mount whitelist ids-table (130), updateStrategy-absent (170), kinds⊆{DS,CM} zero-RBAC
  (185), table subPath mount (215), name coherence (256), values-shape first-party (304).
  `test_provenance.py`: provenance/ledger/text legs (header floors, tgz+lock, renovate pin,
  digest ledger, strategy-plain 158, gaps documented, ledger names, table rows vs authority,
  minimality, zero-stale, placement guard). `tests/services/amd-gpu-naming.sh`: services-entry
  shape only (its line 105 checks the gpu-ai entry's namespace/SSA). NOTHING reads the
  container `command`, and the oracle equality legs would GREEN a command-less render forever
  — the oracle cannot be the authority for a field the oracle lacks.
- MISSING LEG (for agent-test, red-first): a `command`-parity leg beside
  `test_args_are_the_four_plain_items` in `charts/amd-gpu/tests/test_render.py` — e.g.
  `test_container_command_carries_the_plugin_binary` asserting
  `A.dp_container(docs)["command"] == A.PLUGIN_COMMAND` (new testlib constants, e.g.
  `PLUGIN_BINARY = "/root/k8s-device-plugin"`; `PLUGIN_COMMAND = [PLUGIN_BINARY]`), anchored
  on NEW evidence (capture the registry image-config Cmd/Entrypoint — D1.5 digests — into
  `tests/evidence/`, e.g. `image-config-1.31.0.12.json`, since the DS oracle cannot supply
  it); plus a command+args JOINT invariant (args alone legal only if Entrypoint evidence
  exists). Precedent shapes for asserting `.command` in render tests:
  `charts/llama-swap/tests/test_render.py:167`, `charts/llama-swap/tests/test_strata_thin_init.py:56,73`,
  `charts/radiance/tests/test_render.py:276`. Also mechanical: the oracle's header comment
  should gain a line recording that its command-absence is the CAPTURED DEFECT (test-session
  property — coord routes, not review).
- Leg naming caution for the test/dev rounds: "args are the four plain items" stays GREEN
  after the fix (the four items remain as args; the binary rides `command`), so the fix is
  additive to the suite, not a re-pin of ARGS_CONTRACT.

### D1.7 SIDE EFFECTS

- ids-table ConfigMap mount: UNAFFECTED by the exec defect and its fix — the binary reads the
  const IDS_PATH `/usr/share/libdrm/amdgpu.ids` (Dockerfile COPY line at v1.31.0.12 re-
  confirmed in D1.5); with `command` set, the subPath mount still overlays it.
- Flag reachability after the fix: `command: [/root/k8s-device-plugin]` + the existing 4-item
  `args` → argv = binary + all four flags; `-v=5` and `-resource_naming_strategy=product`
  reach the binary exactly as ARGS_CONTRACT promises (runbook receipt (b) law holds).
- OTHER args-without-command surfaces vs their images' ENTRYPOINT:
  - `charts/radiance` main container: `args: *serveArgs` (values.yaml:224), no command —
    SAFE, verified via registry: `stilldeadcode/radiance:1.17.0` amd64 (manifest
    `sha256:6fb0e99b…` = the values ledger D1.170 pin) image config
    (`sha256:5b4c1470…`) HAS `Entrypoint: ["radiance"]` (PATH includes /opt/radiance/bin) —
    args append to it; that pod's Pending (D1.1) is the device-pool starvation, not this bug.
  - `charts/generic-device-plugin/values.yaml:11` args-only: pre-existing surface, NOT a
    C08-converted chart; squat/generic-device-plugin ships its binary via ENTRYPOINT
    (upstream image idiom) and it has run live for months — not ticket-scoped, no action.
  - The gpu cluster entry (`services/gpu/prod/values.yaml:135` amd-gpu version 0.22.0 from
    rocm.github.io): external chart, no args/command — untouched by C08 (D21 shield), unaffected.
- VERDICT / fix shape (values-only, library-supported, no template exception):
  add to `charts/amd-gpu/values.yaml` under
  `app-template.controllers.device-plugin-daemonset.containers.deviceplugin`:

      command: ["/root/k8s-device-plugin"]

  (list form per repo precedent; the absolute path removes the image-WORKDIR dependency that
  the relative `./k8s-device-plugin` form would keep; DO NOT move the flags into command —
  args stays as the 4-item ARGS_CONTRACT). Validated by render on the /tmp copy:
  `helm template … -f overlay(command)` emits `command:\n- /root/k8s-device-plugin` beside
  the untouched args (exit 0). After the values edit the test suite needs the D1.6 leg
  red-first, then the bar re-run; landing stays owner-owned (PR — the branch's commits are
  local per pipeline law).

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md]
commands_run: [repo reads/greps + git show a81989b47^ template + ls-tree 0d9b41785 => pass; cp chart to /tmp + helm dependency update + helm template gpu-ai-amd-gpu (with and without command-overlay) => pass; docker.io registry API image-config fetches (rocm/k8s-device-plugin:1.31.0.12, stilldeadcode/radiance:1.17.0) => pass; raw GitHub Dockerfile@v1.31.0.12 + upstream template@amd-gpu-helm-0.22.0 => pass; readonly-ai-gpu-kubernetes: DaemonSet list, Pod list, pods_get failing pod => pass]
deviations: none — read-only on the repo (only EXPLORE.md written); all renders/copies in /tmp.
friction: the launch's first git citation (0d9b41785:…template) is void — the file did not exist there (recorded in D1.2); resources_list MCP needs kind+apiVersion and returns flattened rows (round-1 friction, unchanged); Code Mode has no filesystem/globalThis.crypto, schema digs went through shell python.
open_questions: none research-grade — the fix shape is fully grounded in-repo + registry; owner/coord choice reduced to list-vs-string form and whether the C08 rework round also re-words the "CMD trio restated in full" comments (they encode the binary-dropping misreading, D1.5).
next_suggested: agent-test adds the D1.6 command leg red-first (new image-config evidence + PLUGIN_COMMAND constant), then agent-dev adds the one `command:` key to values.yaml; after the sync lands, the Pending radiance/llama-swap pods are the on-target receipt.

## §D2 — live post-C09 scheduling state (owner report 2026-11-13) (scout round 3, readonly-ai-gpu-kubernetes, ~02:27–02:30Z)

**VERDICT FIRST.** (A) C09 is LIVE-GOOD: the plugin container carries `command: [/root/k8s-device-plugin]` + the four args, Running, 0 restarts. (B) D24 landed live: the node advertises exactly `amd.com/gpu-r9700-1: 1` and `amd.com/gpu-8060s: 1`, the `-v=5` log prints "Loaded 10 GPU products from /usr/share/libdrm/amdgpu.ids" and "Reporting 1 devices as gpu-r9700-1/gpu-8060s". (C) The owner's quoted "Insufficient memory … No preemption victims found" message is the **RADIANCE** pod (`gpu-ai-radiance-59c96d5bcd-5xt4h`, event 2026-11-13 02:28:44.700372Z) and it is the **DESIGNED handshake** (D17/Q10) down to the byte: live sum(running requests) = 65.158 Gi, allocatable 125.08 Gi → free 59.92 Gi < 64 → short by ~4.08 Gi; step-3 (owner strata scale-down) is the ONLY knob — it lifts free to 123.92 Gi. **BUT** a second, genuinely NEW live defect sits beside it: the owner's quoted message is memory, yet the **outer llama-swap pod is ALSO Pending on `Insufficient amd.com/gpu`** (a different event, D2.6) because the `amd.com/gpu: null` retirement in the B1 overlay is **dropped by the ApplicationSet→Application chain before helm ever sees it** — the chart's tree-global bare claim survives live, the bare pool is 0-capacity, and the pod is Pending-forever under a Recreate Deployment: **the llama.spencerslab.com router has been DOWN since 01:52:09Z** regardless of step 3. That is a branch defect needing its own fix round; radiance's Pending is not.

### D2.1 Device-plugin health — the C09 receipt (live)

- DaemonSet `gpu-ai-amd-gpu-device-plugin-daemonset` (ns default, uid `d6d1beb3-3f99-4c5c-b0c3-fe876912c20e`, created 2026-11-13T01:54:09Z, `deprecated.daemonset.template.generation: "2"`, generation 2): status desiredNumberScheduled 1 / currentNumberScheduled 1 / updatedNumberScheduled 1 / **numberReady 1 / numberAvailable 1**, observedGeneration 2.
- Pod `gpu-ai-amd-gpu-device-plugin-daemonset-b79lf` (uid `d66e5412-0968-42ae-ad4c-38e514a11dc4`, node ai-gpu, pod-template-generation 2, controller-revision-hash 847f87ffc9): **Running, ready 1/1, restartCount 0**, container `deviceplugin` state `running`, imageID `docker.io/rocm/k8s-device-plugin@sha256:6437c74f6566e5d11c20c42369fca7194315943aea91f7bd6c98de1b19caf117` — byte-equal the `charts/amd-gpu/values.yaml` ledger digest (§D1.5).
- Rendered command/args (live spec, both DS template and pod): `command: ["/root/k8s-device-plugin"]` + `args: ["-logtostderr=true","-stderrthreshold=INFO","-v=5","-resource_naming_strategy=product"]` — EXACTLY the D1.7 fix shape. The C09 crashloop class is gone (first log line 02:27:41.791957, container start after the fix sync; the runbook step-2 C09-exec-receipt expects precisely `Command: /root/k8s-device-plugin` + four Args + State: Running).
- Plugin log receipts (runbook step 2.2, verbatim from `pods_log`): `I1113 02:27:41.792051 main.go:72] Loaded 10 GPU products from /usr/share/libdrm/amdgpu.ids` (TEN = the MINIMAL patched table's data-row count, D24 overlay applied); `plugin.go:280] Reporting 1 devices as gpu-r9700-1` and `…as gpu-8060s` (02:27:41.797323/.797400); registrations `gpu-r9700-1: Registration for endpoint amd.com_gpu-r9700-1` + `gpu-8060s: … amd.com_gpu-8060s`. The devices map read the sysfs pairs live: `0000:c4:00.0 deviceID:7551 revisionID:C0 renderD:128` and `0000:c5:00.0 deviceID:1586 revisionID:C1 renderD:129`. NOTE vs runbook step-0(a): the prose expected c4 to read `0x1586` (RQ3-era enumeration); LIVE c4 is the R9700 (7551/C0) — the gate's own law ("derive the names from the device reads, not from BDF position; the pair is the authority") holds, both pairs land on patched-table rows, no fallback fired.
- ids-table ConfigMap `gpu-ai-amd-gpu-amdgpu-ids` (uid `d1a0c4c8-de0e-4763-84f0-d096241a1bd1`, created 01:54:09Z): key `amdgpu.ids`, **455 bytes**, 10 data rows ending `1586 D5 AMD Radeon 8040S Graphics` + `7551\tC0,\tr9700-1` — and it is mounted per D24: volume `ids-table` → `mountPath: /usr/share/libdrm/amdgpu.ids`, `subPath: amdgpu.ids`, readOnly (live DS spec).

### D2.2 Node advertisement (node `ai-gpu`, uid `5a95d367-ee6d-4ae6-a316-08cfcc5ef068`)

- capacity AND allocatable both carry: **`amd.com/gpu-r9700-1: 1`**, **`amd.com/gpu-8060s: 1`**, and — nuance for the step-2.3 assert — **`amd.com/gpu: "0"`** (the key is PRESENT with value 0, not literally absent). Semantics: the fallback trap did NOT fire (both cards matched the patched table; the new plugin registers only the two named pools per D2.1 log); the zero key is kubelet retention of the single-naming era's advertisement (the pruned 1.31.0.9 plugin reported `amd.com/gpu: 2`; the key lingers at 0). Scheduling truth: **bare `amd.com/gpu` has zero capacity — a stray bare claim there is unschedulable forever**, exactly the runbook line-188 "Pending-forever — loud by design" state. The runbook's gate text "bare `amd.com/gpu` ABSENT" should be read/rewritten as "count 0" (docs nit, not a cluster defect).
- `memory`: capacity = allocatable = `131151328Ki` = **125.08 Gi** (no memory reservation subtracted — allocatable equals capacity, the number D17's arithmetic rides). `cpu: 32`, `pods: 110`, `hugepages-1Gi/2Mi: 0`, ephemeral capacity 950796Mi/allocatable 947132772429B. Swap capacity 2148204544 B (~2.0 GiB — the cgroup-is-the-only-containment law unchanged).
- nodeInfo: kernel `7.3.0-1-default`, openSUSE Tumbleweed, kubelet `v1.36.5+k3s1`, containerd `2.3.4-k3s1.36` — no drift vs round-1 §3.
- conditions (heartbeat 2026-11-13T02:27:46Z): Ready=True, **MemoryPressure=False**, DiskPressure=False, PIDPressure=False — the Pending is pure requests arithmetic, not real memory pressure.

### D2.3 Who is Pending (cluster-wide `status.phase=Pending` sweep: exactly two pods, both ns default)

1. **`gpu-ai-radiance-59c96d5bcd-5xt4h`** — uid `20ce09f6-56da-4151-9c6e-1719a10d1f90`, owner ReplicaSet `gpu-ai-radiance-59c96d5bcd` (uid `a0e225f7-b62d-42f7-aed3-dc2e2def0d23`, controller chain Deployment `gpu-ai-radiance`), priority 0, QoS **Guaranteed**, condition `PodScheduled=False(Unschedulable)`. FailedScheduling verbatim:
   `0/1 nodes are available: 1 Insufficient memory. no new claims to deallocate, preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.` — **2026-11-13 02:28:44.700372 +0000 UTC**. **This is the owner's message, and its producer is RADIANCE, not llama-swap.** The predecessor radiance pod (`gpu-ai-radiance-59c96d5bcd-dsscv`, same template hash) received the identical memory-only message at 02:27:46.895 — from 02:27:46 onward (post-C09-sync) radiance's ONLY failing dimension is memory; dsscv→5xt4h was an RS re-create, not a template change.
2. **`gpu-ai-llama-swap-965d474b7-xlwfh`** — uid `3eac8cad-e3b5-4157-8f19-51cf7ffe3e23`, owner RS `gpu-ai-llama-swap-965d474b7` (uid `835eaa35-dd84-4420-8f55-40f788b409fb`), priority 0, QoS **Burstable** (2 containers main+tools; main per-container requests {cpu:1, memory:4Gi, amd.com/gpu-8060s:1, **amd.com/gpu:1**} + limits {amd.com/gpu-8060s:1, **amd.com/gpu:1**} — the bare claim is the live defect, D2.6; the bare appears in requests only because kubelet mirrors limits→requests for extended resources, the Deployment template itself has it in limits only). FailedScheduling verbatim:
   `0/1 nodes are available: 1 Insufficient amd.com/gpu. no new claims to deallocate, preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.` — 02:27:46.779008 and 02:27:46.895219Z. NOT a memory story. Its predecessor RS 779b58445d event history proves the wave progression: 01:52:39 `Insufficient amd.com/gpu-8060s` (pool not yet advertised, old plugin gone), 02:08:09 `Insufficient amd.com/gpu, 1 Insufficient amd.com/gpu-8060s` (crashloop window), 02:27:46 `Insufficient amd.com/gpu` only (pools live, bare still 0, 8060s now satisfiable — the ONLY unfixable-by-knobs line left is the stray bare claim).
- **No other Pending/ContainerCreating pods exist**, and — the operational headline — **NO RUNNING outer llama-swap pod exists anywhere**: Deployment `gpu-ai-llama-swap` is `strategy: Recreate`, observedGeneration 49, `Available=False "Deployment does not have minimum availability"` since **2026-11-13T01:52:09Z**, unavailableReplicas 1. The naming wave's Recreate killed the serving pod before its replacement could ever schedule; the public chain `llama.spencerslab.com` (peer hop, catalog routes, the hourly loop's runner literal) has had no outer supervisor for ~40 min at probe time. Strata's pod (below) still serves on its own service DNS, but nothing fronts it. URGENT — owner-facing.

### D2.4 Who holds what — full node allocation and the arithmetic (scheduler-relevant = requests)

Per-pod (all on ai-gpu; memory Gi; `effReq` = max(Σcontainers, maxInit) per pod, sidecars included):

| pod | phase | effReq mem | limits mem | amd.com claims (req/lim) | QoS |
|---|---|---|---|---|---|
| `gpu-ai-llama-swap-strata-6cd875db6d-sr5m2` (uid `a87c2618-71f7-47a3-904a-7e44f582ee82`) | Running 33h | **64** (init model-fetch 2 ≤ 64) | 110 | NONE — privileged + hostPath posture, scheduler-invisible R9700 holder (chart law lines 1327-1335) | Burstable |
| `gpu-ai-radiance-59c96d5bcd-5xt4h` | **Pending** | 64 | 64 | `gpu-r9700-1: 1` req==lim ✓ | Guaranteed |
| `gpu-ai-llama-swap-965d474b7-xlwfh` | **Pending** | 4.125 | main — + tools 1 | `gpu-8060s: 1` ✓ + stray `amd.com/gpu: 1` ✗ | Burstable |
| system floor: alloy-logs .299, alloy-metrics-0 .174, alloy-singleton .111, reloader .125, mcp-admin-proxy .125, mcp-readonly-proxy .125, toolhive-operator .063, coredns .068, metrics-server .068 | Running | **1.158 total** | — | none | mixed |
| argocd ×5, cert-manager ×3, ext-secrets ×3, kube-state-metrics, node-exporter, bitwarden-cli, local-path, svclb-traefik, traefik, plugin DS pod (`resources: {}`) | Running | 0 (BestEffort) | 0 | none | BestEffort |

- **Σ running effective requests = 65.158 Gi; allocatable = 125.08 Gi → free = 59.92 Gi.**
- Radiance fit test: needs 64 → **short by 4.08 Gi** → `Insufficient memory`. CPU (8/32) and its pool (r9700-1 1-of-1, capacity 1 allocated 0 — strata holds the card by privilege, not claim, §R6-Q4 law) both PASS; memory is the single failing dimension, exactly the shipped formula's prediction: D17/runbook 64+64+4 = 132 > 125.08 (live-grounded: 65.158 + 64 = 129.16 > 125.08; the shipped 132 undercounts the 1.158 Gi system floor, direction of the error is MORE over-budget, never less).
- **The knob is step 3, not the ladder**: scale strata to 0 → Σ drops to ~1.158, free = **123.92 Gi** ≥ 64 → radiance schedules on its own; even the step-6 ladder-UP ceiling (96+4 < 125.08) fits then. Do NOT move `guaranteedMemoryGi` to clear this Pending — runbook lines 116-122 forbid it verbatim (below).
- Radiance's own number is right: requests == limits == **64Gi** — `guaranteedMemoryGi: 64` shipped as designed (C08 answer-in-place), ≠ defect.
- Llama-swap fit test: its 4.125 Gi fits the current free 59.92, `gpu-8060s` 1-of-1 is FREE (capacity 1, allocated 0), only `amd.com/gpu` fails and it fails at capacity-0 — no node-level action (scale-down, ladder, wait) can ever satisfy it. Git fix required (D2.6).

### D2.5 Radiance pod posture — every shipped expectation reached live (unscheduled yet)

- Claim pair `amd.com/gpu-r9700-1`: requests `1` == limits `1` ✓; cpu 8 == 8; memory 64Gi == 64Gi; **pod status.qosClass = `Guaranteed`** including init `radiance-fetch` requests==limits {cpu 200m, memory 2Gi} (curlimages/curl:8.23.0, exec-form `sh -c`, LFS_SHA `0af5e962…` marker script byte-consistent with runbook step 4) — D15 holds end-to-end.
- Container args live == runbook step-5 expectation token-for-token: `--model /models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad --port 8000 --host :: --tp 1 --max-model-len 200000 --max-num-seqs 8 --placement expert_tiered --host-pool-mib 43000 --gpu-headroom-mib 96 --kv-cache-dtype fp8 --kv-resident 32768 --num-speculative-tokens 3 --max-num-batched-tokens 4096 --checkpoint-interval 4096 --ngram-placement disk --served-model-name qwen3.8-flash-next-radiance`; the absence law holds (no `serve` verb, no prefix-cache flag, no api-key flag). Image `docker.io/stilldeadcode/radiance:1.17.0` ✓ (no imageID yet — pod never scheduled, nothing pulled).
- Pending reason = memory arithmetic ONLY (D2.3/D2.4). **This is the designed handshake state, confirmed to the byte.**

### D2.6 NEW LIVE DEFECT (D26 candidate) — the overlay `amd.com/gpu: null` never reaches Helm; the outer llama-swap is Pending-forever and the router is down

The evidence chain, layer by layer (all read this round):

1. **Branch intent**: `services/gpu-ai/prod/values.yaml:170-175` — gpu-ai overlay `limits: {amd.com/gpu: null, amd.com/gpu-8060s: 1}` + requests mirror; the law comment 162-169 asserts "the null on the inherited bare key is load-bearing: it is what RETIRES amd.com/gpu in this render". The inherited key: `charts/llama-swap/values.yaml:1055` `amd.com/gpu: 1` (tree-global by B1/D21 shield; its comment 1050-1054 repeats the null-retirement claim).
2. **Helm DOES honor it standalone** (verified locally on this worktree): `cp -r charts/llama-swap /tmp/… && helm dependency update && helm template gpu-ai-llama-swap . -f <extracted llama-swap: subtree>` (helm v3.16.4; subtree extracted exactly as CI's workflow does, via safe_load of the whole service doc so anchors resolve) → rendered Deployment main container `limits: {amd.com/gpu-8060s: 1}` — bare key RETIRED. The chart-side law is true one layer below production.
3. **The ApplicationSet render carries the null**: `charts/base/templates/appset-charts.yaml:36` `values: {{ merge $extraValues (index $.Values $appName) | toJson }}` — local render of `services/gpu-ai/prod` keeps `"amd.com/gpu":null`, and the **live** ApplicationSet `gpu-ai-charts-appset` (read this round) has it in the list-generator element too. Helm's sprig merge + toJson preserve it.
4. **The Application never got it**: live `Application gpu-ai-llama-swap` `spec.sources[].helm.valuesObject` = `"resources":{"limits":{"amd.com/gpu-8060s":1},"requests":{"amd.com/gpu-8060s":1}}` — the 8060s add-lines arrived (object is fresh, regenerated in the same 02:27 wave that produced RS 965d474b7) but the null key is GONE. The drop happens in the ApplicationSet-controller side of the templatePatch evaluation — `appset-charts.yaml:120` `merge (deepCopy $appCustomValues) (deepCopy $serviceCustomValues) (deepCopy $baseValues)` (both custom dicts empty for every app here, so the merge runs on nothing but silently swallows nil-valued keys — mergo-family merges skip nil sources; argocd's vendored sprig differs from helm's, which is why the SAME-looking merge at line 36 preserves it) — or in that render's YAML→Application-struct round-trip. Either way the deletion instruction dies BEFORE Argo's helm render, the chart default survives, and line 122's `valuesObject:` is the observable death site. The whole chain is live-verified end-to-end except WHICH of those two argocd-side steps drops it (not distinguishable read-only; does not change the fix).
5. **Live consequence** (D2.3/D2.4): stray bare claim in the running Deployment template, `Insufficient amd.com/gpu` forever (bare pool capacity 0), under `strategy: Recreate` → serving outage since 01:52:09Z. The event text is literally what `test_cf143_naming_flip.py:100-104` warns about ("a stray bare claim there is Pending-forever") — the suite's own words, at the one layer it does not model.
6. **Why every gate stayed green (the oracle gap, same class as §D1.2)**: `charts/llama-swap/tests/test_cf143_naming_flip.py:80-104` (`test_main_container_claims_named_apu_pool`) asserts on a DIRECT helm overlay render — proven GREEN locally in D2.2 above while the live object is BROKEN. The oracle omits the ApplicationSet→Application valuesObject layer where the null dies. `test_render.py:172` and `test_cf143_naming_flip.py:137-144` pin the same law from the chart/values text side. Nothing models `appset-charts.yaml`'s merge path (the gpu-ai golden `tests/golden/gpu-ai.config.yaml` is the llama-swap ConfigMap, not resources).
7. **Where the correction belongs (shapes for plan/coord — scout grounds, does not decide)**: the robust class is **stop deleting through the merge chain — ADD per-cluster instead**:
   - `charts/llama-swap/values.yaml:1040-1055` — drop the bare `amd.com/gpu: 1` from the tree-global default `limits` (requests keep cpu/memory); re-write the 1045-1054 "RETIREs this key via the service overlay's null" comment — that law is empirically false through appset-charts.
   - `services/gpu/prod/values.yaml` (llama-swap subtree starts line 275, today carries NO `app-template…main.resources` keys — verified by read: it inherits the chart default) — ADD `app-template.controllers.llama-swap.containers.main.resources.limits."amd.com/gpu": 1` there; a pure ADD survives every merge layer (that is exactly how the gpu-ai overlay's 8060s lines reached live). The gpu cluster's single-naming 1.31.0.9 plugin then still gets its name; the B1 shield semantics are preserved, relocated.
   - `services/gpu-ai/prod/values.yaml:170-175` — remove the inert `amd.com/gpu: null` line and re-word the 162-169 merge-law comment (maps ADD; null-retirement does not survive the appset valuesObject path — name the layer).
   - Test arms to re-pin (agent-test property): `test_cf143_naming_flip.py:5-16,80-104,137-147` flip to the add-per-cluster shape, and a new leg should model the production path (render the appset and assert the Application-side valuesObject shape, or at minimum assert "no `amd.com/gpu: null` deletion-dependency lines anywhere in the gpu-ai subtree" — the pattern that cannot fail silently).
   - Optional root fix with repo-wide blast radius (owner decision, NOT cf-143-owned): `charts/base/templates/appset-charts.yaml:117-123` — pass `$baseValues` through untouched when both custom dicts are empty, so null deletion semantics hold for every chart. Flagged as a follow-up-card candidate; every current consumer only ADDs today, so it is latent, not active, for the rest of the fleet.
   - Runbook obligation: step-2.4 (lines 276-285, "llama-swap post-rollout check") and §D1.1's "after this fix, Pending there means the plugin is NOT Running, not a name defect" (line 241-243) are now SUPERSEDED — a third failure class exists (plugin Running, pools advertised, pod still Pending on `Insufficient amd.com/gpu`): the needle diagnosis is "check the live Application's valuesObject for the dropped null". Until the git fix lands, step 3's scale-down schedules RADIANCE but NOT the router.

### D2.7 The runbook lines the owner should be walked through — and whether today matches

- Step-0(b), lines 116-122, verbatim: *"The shipped arithmetic (`charts/radiance/values.yaml` comment): radiance Guaranteed 64Gi + strata's 64Gi REQUEST (its limits are 110Gi — requests are what schedule) + the outer llama-swap 4Gi = 132 > 125.08, so a radiance pod beside a LIVE strata sits Pending with 'Insufficient memory' — that is the DESIGNED handshake of the owner's manual scale-down protocol, loud and safe, never a bug to fix by shrinking the chart (D17). Radiance scheduling REQUIRES step 3."*
- Step 3, lines 320-333: suspend auto-sync for `gpu-ai-llama-swap` in the ArgoCD UI first (selfHeal would revert the scale), then the OWNER-EXECUTED `kubectl -n default scale deploy/gpu-ai-llama-swap-strata --replicas=0`; *"Only NOW does the pending `gpu-ai-radiance` pod schedule — the step-0(b) arithmetic flips green the moment strata's 64Gi request leaves the node."*
- Step 6, lines 417-420: *"a pod stuck Pending at this point is step-0(b)'s arithmetic still in effect — strata's request has not actually left the node (re-check step 3, selfHeal included); that is the Pending-by-design handshake state, not an engine failure."*
- Step-1 pool row, line 188: *"bare `amd.com/gpu` is GONE there (stray bare claims on gpu-ai schedule Pending-forever — loud by design)."*
- **Plainly**: today's RADIANCE observation matches the documented expectation exactly (numbers, message text, and the required next action = step 3). Today's LLAMA-SWAP observation matches the line-188 symptom text but NOT the documented pipeline: the stray claim is there only because the branch's retirement mechanism fails in the appset chain (D2.6) — that half is a genuine defect, not a designed state, and it is what broke the router.

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md]
commands_run: [readonly-ai-gpu-kubernetes: DaemonSet get (1/1/1, gen 2), Node get (pools 1/1, bare 0, allocatable 125.08Gi, MemoryPressure=False), default+kube-system pod inventories, Pending sweep, pods_get radiance/llama-swap/strata/plugin + all-node request-sum pass (Σ running eff requests = 65.158Gi), events_list FailedScheduling verbatim (radiance 02:28:44.700372Z memory; llama-swap 02:27:46.779Z amd.com/gpu), plugin pods_log (Loaded 10 GPU products; Reporting 1 devices as gpu-r9700-1/gpu-8060s), ConfigMap gpu-ai-amd-gpu-amdgpu-ids get (455B, 10 rows), Application get (valuesObject null ABSENT), ApplicationSet get (values null PRESENT), Deployment llama-swap get (Recreate, Available=False since 01:52:09Z) => pass; local: cp charts/llama-swap + helm dependency update + helm template with extracted gpu-ai subtree => null-retires at the helm layer; helm template services/gpu-ai/prod => null survives appset render; repo reads (services/gpu-ai + services/gpu values, charts/llama-swap values/tests, appset-charts.yaml, runbook, DECISIONS/STATE/chunks) => pass]
deviations: none — read-only cluster probes (readonly tier only), repo writes confined to EXPLORE.md; the only fs writes outside the ticket folder were /tmp/opencode render scratch (same precedent as §D1.3).
friction: the MCP events_list returns flattened column rows (message verbatim survives — good); pods_list/resources_list are flattened (prior rounds' friction, unchanged); Application CR read shape: spec.source(helm) vs spec.sources[] — valuesObject lives under spec.sources[i].helm, found by raw-string scan; one pods_get miss from my own name typo (mcp-readonly proxy pod) — refetched correctly in the precision pass, no live object unexamined.
open_questions: [None research-grade. Coord decision owed on the D2.6 fix: (1) adopt the add-per-cluster shape (charts/llama-swap/values.yaml:1055 drop + services/gpu/prod/values.yaml add + gpu-ai null-line removal + test_cf143_naming_flip.py oracle re-pin modeling the appset→valuesObject layer) — recommended, null-drop mechanism proven dead through the merge chain; (2) whether the base appset-charts.yaml:117-123 passthrough root-fix is filed as a follow-up card (repo-wide blast radius, latent for other charts). Owner-facing URGENT either way: the outer llama-swap router (llama.spencerslab.com, peer hop, hourly-loop runner route) has had no serving pod since 01:52:09Z — step 3 alone does NOT restore it; and radiance's Pending is the designed handshake — proceed step 3 (selfHeal suspend first) and it schedules.]
next_suggested: coordinator: mark C09 live-good (AC7 receipt satisfied — DS 1/1, Command/Args/Running as the runbook step-2 receipt demands) and radiance-Pending as step-3-gated; open a new defect round for D2.6 (test leg red-first modeling the valuesObject path, then the values trio fix); walk the owner the runbook step-0(b)/step-3 lines with the router-outage caveat.

## §D2.8 — mechanism adjudication: why the router was actually stuck (scout round 4)

Launch asked me to adjudicate CAUSE-A ("a null in the merged values does NOT delete an inherited chart default — helm/mergo semantics") vs CAUSE-B ("propagation staleness — the Application was rendered from a pre-ADD state; the wedge was a transient mid-rollout and the null-never-works law is false"). **Verdict: neither as framed. The surviving story is §D2.6's, now source-grounded and history-closed: Helm DOES retire nulls (coalesce.go deletes them — reproduced offline), the null DID reach the ApplicationSet CR, and it dies specifically inside the ApplicationSet→Application valuesObject hand-off — every null key, every app, in a single hop. The wedge was never transient. AND — the launch's own premise is refuted live: C10 has NOT been merged and the gpu-ai router is STILL DOWN at probe time (~04:35Z); the "04:01 recovery" does not describe this cluster.**

### D2.8.1 LIVE STATE NOW — "post-C10, router healthy" is FALSE

| object (uid/identities) | field | value @ ~04:30–04:35Z 2026-11-13 |
|---|---|---|
| Deployment `gpu-ai-llama-swap` (ns default) | metadata.generation | **49** (unchanged since 02:27:46Z — no new template has landed) |
| ″ | spec.template main resources | `limits {amd.com/gpu: "1", amd.com/gpu-8060s: "1"}` + `requests {amd.com/gpu-8060s, cpu, memory 4Gi}` — **bare claim STILL injected** |
| ″ | status | replicas 1, updated 1, **unavailable 1**; `Available=False @ 2026-11-13T01:52:09Z MinimumReplicasUnavailable` (lastTransitionTime unchanged since the wave — **the Deployment has NEVER had an available replica since 01:52:09Z**); `Progressing=False @ 02:37:47Z ProgressDeadlineExceeded` |
| Pod `gpu-ai-llama-swap-965d474b7-xlwfh` (uid 3eac8cad…) | status | **Pending, 0/2 ready, age 125m** at probe; the only Pending llama-swap pod; no Running outer pod exists |
| Application `gpu-ai-llama-swap` (created 10-07T23:06:28Z, rv 4911350) | status.operationState | phase Succeeded, **startedAt=finishedAt=2026-11-13T02:28:03Z** "successfully synced (all tasks run)" — the LAST operation ever run on it; reconciledAt 04:30:06Z (a refresh with nothing new to apply) |
| ApplicationSet `gpu-ai-charts-appset` | metadata.resourceVersion | **4895314** — older than the C09-era DS rv (4898957): the appset CR has not been re-written since the naming wave; its llama-swap generator STILL carries `amd.com/gpu: null` (git pre-C10) |
| main branch position (git, origin dir `/home/coder/SpencersLab`) | `merge-base --is-ancestor` | **C10 (56142d511) NOT in main**; main HEAD = `ec18281fb` = "fix(cf-143): C09 — plugin container command…" (= the rev the 02:27:45/02:28:03Z syncs id 131/132 deployed). C07's branch sha 546f03e01 is likewise not an ancestor (the wave content landed as re-created shas on main — chain …`4c18143ad`→`5600ec601`→`f97276161`→`ec18281fb`) |
| Node `ai-gpu` | allocatable + heartbeat | `amd.com/gpu: "0"`, `amd.com/gpu-8060s: 1`, `amd.com/gpu-r9700-1: 1`, memory 131151328Ki; Ready/MemPressure-Disk-PID all normal @ 04:30:20Z. Consumption: **8060s and r9700-1 both UNALLOCATED (1 free each)** — the Pending router holds nothing; radiance still Pending because step 3 has NOT been executed (strata pod `…6cd875db6d-sr5m2` Running 35h, request 64Gi still on the node — §D2.4 free 59.92 Gi < 64 unchanged) |

What IS healthy: the **gpu cluster's** router — `gpu-llama-swap` (readonly-gpu-kubernetes, ns default): generation 22, `Available=True` since 2026-11-12T17:50:43Z, 1/1, template `limits {amd.com/gpu: "1"}` + `requests {cpu, memory 4Gi}`, served by the EXTERNAL single-naming plugin (bare pool `amd.com/gpu: 1` on node gpu). The most likely source of the "04:01 recovery" reading is either this other cluster's green row or the ticket-side events of ~04:0x (C10 review r2 APPROVED, plans commit `4652671fd`) — no gpu-ai cluster state changed at 04:01: the Deployment condition history is monotone False since 01:52:09Z and Argo ran no operation after 02:28:03Z. **C10 landing (merge + sync) remains the router's only recovery route; §D2.7's "step 3 alone does NOT restore it" stands and gets reinforced: today even step 3 has not been run, yet the router is the thing still down.**

### D2.8.2 THE VALUESOBJECT HISTORY — CAUSE-B falsified to the byte

`Application.status.history` (10 rolling entries, each a full sources[] snapshot) + current spec, main-container resources extracted per sync:

```
2026-11-09T12:48:07Z id 123 rev 1865031af218  main.resources ABSENT   (pre-ticket)
2026-11-10T15:41:14Z id 124 rev a6e493b7884e  main.resources ABSENT
2026-11-11T14:11:11Z id 125 rev c555304578a9  main.resources ABSENT
2026-11-11T17:13:58Z id 126 rev 0d9b41785fcc  main.resources ABSENT   (main at branch-mint base)
2026-11-13T01:44:44Z id 127 rev 0d9b41785fcc  main.resources ABSENT
2026-11-13T01:48:37Z id 128 rev 0d9b41785fcc  main.resources ABSENT
2026-11-13T01:51:46Z id 129 rev 5600ec6019ff  main.resources ABSENT   (first sync on the wave merge rev — spec not yet re-written by the appset controller)
2026-11-13T01:52:08Z id 130 rev 5600ec6019ff  {limits:{amd.com/gpu-8060s:1}, requests:{amd.com/gpu-8060s:1}}   ← ADD ARRIVES, NULL ALREADY DEAD
2026-11-13T02:27:45Z id 131 rev ec18281fb2aa  same pair
2026-11-13T02:28:03Z id 132 rev ec18281fb2aa  same pair
NOW (spec.sources[1].helm.valuesObject, doc-wide scan)  {limits:{amd.com/gpu-8060s:1}, requests:{amd.com/gpu-8060s:1}} | nulls in the ENTIRE Application document: 0
```

- CAUSE-B predicted: a pre-04:01 valuesObject with the **ADD ABSENT** (stale generator). Observed instead: **the ADD is present in every snapshot from the instant it first existed (id 130, 01:52:08Z) and the null is absent from all of them.** The wedge window (01:52:09 → probe, now ~2h45m) spans TWO revisions (5600ec601, ec18281fb), FOUR sync operations (ids 129–132) and TWO ReplicaSets — the valuesObject never once held a shape that could schedule the pod. Not transient; not staleness.
- Earliest live-possible ADD: git commit 546f03e01 (C07, 2026-11-12T04:16:29Z, branch) reached main only with the wave merge resolved by Argo as 5600ec6019ff — first sync carrying it id 129 @ 01:51:46Z; the Deployment's first APU-claiming pod (RS `gpu-ai-llama-swap-779b58445d`, rev 36) was created 01:52:39Z. The C09-era syncs (ids 131/132 @ 02:27:45/02:28:03, rev ec18281fb) already carried the add — answering the launch's "did the C09-era sync already carry it": YES.
- The RS pair (read this round): `779b58445d` (created 01:52:39Z, deployment-rev 36) and `965d474b7` (02:27:46Z, rev 37) have **identical** main resources blocks — `mainLimKeys [amd.com/gpu, amd.com/gpu-8060s]` both — and differ ONLY in the `reloader.stakater.com/last-reloaded-from` ConfigMap-hash annotation (f2b7f101… → 186b03e2…, config re-render at the C09 sync; the RS flip was reloader's, not Argo's claim change). **No APU-only template has EVER existed on this cluster** — the replacement §D2.6.5 anticipated is exactly what C10's merge would create, and it hasn't.

### D2.8.3 THE HELM LAYER HONORS THE NULL — CAUSE-A falsified where it claims helm ignores it

Source-grounded (fetched this round, both citable):

- helm v3.16.4 `pkg/chartutil/coalesce.go`, `coalesceValues()`: the exact block — `if value == nil && !merge { // When the YAML value is null and we are coalescing instead of merging, we remove the value's key. // This allows Helm's various sources of values (value files or --set) to remove incompatible keys from any previous chart, file, or set values. delete(v, key) }`. (Same delete in `coalesceTablesFullKey`: `if dv, ok := dst[key]; ok && !merge && dv == nil { delete(dst, key) }`.) Contrast `MergeValues`/`MergeTables` (merge=true), which the file's own comments say "keeps the null values" — deletion is COALESCE-mode behavior, i.e. exactly what `-f values` user-supplied values go through. URL: https://raw.githubusercontent.com/helm/helm/v3.16.4/pkg/chartutil/coalesce.go
- Helm docs, Values Files → **"Deleting a default key"**: *"If you need to delete a key from the default values, you may override the value of the key to be `null`, in which case Helm will remove the key from the overridden values merge."* URL: https://helm.sh/docs/chart_template_guide/values_files/ (v4 page; the v3 doc carries the same section)
- Local reproduction at the exact pre-C10 blobs (`git show 56142d511^:…` → /tmp/opencode/cf143-d4, helm v3.16.4, `charts/llama-swap` + `helm dependency update`):
  - **A)** pre-C10 chart (bare default at values.yaml:1055) + pre-C10 overlay (ADD + NULL as one -f file) → main renders `limits: {amd.com/gpu-8060s: 1}` — **bare REMOVED**. Had production delivered this file to helm, the router scheduled at 02:27 when the pools came up.
  - **B)** pre-C10 chart + the LIVE valuesObject shape (ADD only, null dead upstream) → `limits: {amd.com/gpu: 1, amd.com/gpu-8060s: 1}` — **byte-shape of both wedged RS templates (§D2.8.2)**. The broken render is reproducible offline from the broken INPUT, closing the loop: helm honored what it was given; what it was given is what the hand-off left behind.

So the sentence "a null in the merged values does not delete an inherited chart default" is FALSE of Helm (docs + source + reproduction A) — and TRUE of the production channel only because the null is **never in the values helm receives** (reproduction B). The operative law for this repo's overlays: **deletion instructions cannot be expressed through the ApplicationSet→Application valuesObject hand-off at all; only ADDs carry.** The service-file comment's "maps deep-merge — null retires" law (`services/gpu-ai/prod/values.yaml:162-169` pre-C10 wording) died on the hop, not in helm.

### D2.8.4 WHERE THE NULL DIES — narrowed beyond §D2.6.4's "two indistinguishable candidates"

Three live objects read this round triangulate the death site INSIDE the ApplicationSet-controller hand-off and EXONERATE both neighbours:

1. **ApplicationSet CR stores nulls fine** (it is helm-rendered and API-stored): `gpu-ai-charts-appset` llama-swap element keeps BOTH null paths — `values.app-template.controllers.llama-swap.containers.main.resources.limits."amd.com/gpu" = null` AND `values.shared-storage = null` (the second is `dict "shared-storage" (index $.Values "shared-storage")` at appset-charts.yaml:32 — an index of an absent key, a NIL the toJson wrote verbatim). RV 4895314. So "CRD/etcd silently erases nulls" is FALSE — the null survived git→helm→appset-CR completely.
2. **Every Application document is null-free** (0 nulls doc-wide on all three read): llama-swap valuesObject = the APU pair, null absent; `gpu-ai-radiance` valuesObject keys = `["app-template"]` only — its `shared-storage: null` ALSO vanished; `gpu-ai-amd-gpu` valuesObject = **`{}`** — its generator element's ONLY payload was the shared-storage null, and after the hand-off the map is literally empty (line 121's `hasKey . "values"` gate passed, so the write happened; content = zero keys). The killer is **whole-tree and class-wide**, not subtree-specific: no null-valued key of any kind survives the templatePatch→Application write (appset-charts.yaml:114-122 evaluated by the applicationset controller — argocd v3.5.4, per the on-node image `quay.io/argoproj/argocd:v3.5.4`), whether it is inside merged maps (`amd.com/gpu: null`) or at the top level (`shared-storage: null`).
3. Helm is downstream and innocent (§D2.8.3). Which internal step strips the nils — the sprig `merge` (mergo-family merges that never *create* keys whose source value is nil) at line 120, or `toYaml`→Application-struct unmarshal at line 122 — remains **not distinguishable read-only from outside the controller binary**, and now clearly does not matter for the repo law. What §D2.6.4 called "the YAML→Application struct round-trip" candidate is subsumed: the observable contract is **null-absence at valuesObject, fleet-wide, on every hand-off.**

### D2.8.5 ADJUDICATION + the three consequences the launch demanded

**CAUSE-B: falsified** (§D2.8.2 — the add was in the valuesObject from birth of the wedge; the null never was in any snapshot; four syncs and two RSes could not clear it; "the 'null never works' law retracted" is NOT what the evidence permits). **CAUSE-A as worded ("helm ignores nulls"): falsified** (§D2.8.3 — helm's coalesce deletes; local render A retires). **The truth is §D2.6's original claim, hardened**: the per-cluster null-retirement mechanism was inert THROUGHOUT this stack's production channel because the deletion marker dies in the ApplicationSet→Application hand-off (§D2.8.4) before helm sees anything. The quoted §D2.7 sentence "the null WAS retired NORMATIVE — a null key simply never appears in the valuesObject because a null value is absent" **exists nowhere in the ticket** (grep: 0 hits for `NORMATIVE` / `never appears` / `null value is absent`); the file's §D2.7 (and §D2.6) say the drop-during-hand-off story, and my §D2.6.4's recorded live read was the APU-ADD-PRESENT, NULL-ABSENT pair — NOT "null with add absent" as the launch paraphrase claims; that reading is now re-verified doc-wide (§D2.8.2). The partial-read flag is honestly closed: round 3 quoted a ±400-byte window, which fully bracketed the resources map; this round replaces it with the whole-document census + history table.

(i) **C10's carrier move is still the right fix under both candidate causes — and is the only correct fix under the real one.** Under the (falsified) helm-ignores-null A: chart claim-less + per-cluster ADD removes the need for any deletion, so C10 fixes it regardless. Under the (falsified) staleness B: C10 still fixes it because the wedge demonstrably outlived every propagation order ArgoCD offers. Under the real cause: the ADD is the *only* key-class proven to cross the hand-off (every snapshot shows add-arrival within ~20 s of merge-syncs), while nulls are proven to never cross it (3 apps, 5 snapshots, 0 survivors). Regression-safety stays as C10 review certified it: gpu-llama-swap's live template (limits `{amd.com/gpu:"1"}`, 1/1 Available, §D2.8.1) is the exact shape C10's gpu-side ADD must reproduce, byte-for-byte.

(ii) **What DECISIONS D26 / the FRICTION law / the C10 commit-message claim must say.** The C10 commit message (`56142d511`) — *"appset->valuesObject chain drops nulls so per-cluster retirement-by-null never worked"* — **stands VERBATIM correct; this round upgrades its confidence from one evidence pair to a fleet-wide class law.** D26 (DECISIONS.md:377-386) — *"THE FACT — the B1 overlay's `amd.com/gpu: null` retirement never reaches Helm: the ApplicationSet→Application valuesObject chain drops null-valued keys before helm ever sees them"* — **also stands**, with ONE sentence to amend: "The two death-site candidates (mergo-nil-skip in the templatePatch merge at `charts/base/templates/appset-charts.yaml:120`, or the YAML->struct round-trip) are indistinguishable read-only" → keep (still true inside the controller) but ADD: *"§D2.8.4 closes the outer boundaries: the ApplicationSet CR provably STORES both nulls (claim + shared-storage), every Application provably carries NONE (amd-gpu's valuesObject = `{}` where the shared-storage null was the only content), and helm provably deletes when given the null — the strip is whole-tree and happens in the appset-controller hand-off only."* The FRICTION line (FRICTION.md:26, "(mergo/JSON nil-skip on that path)") stands — it already names the hand-off, not helm. What must NOT be written anywhere is the retired-NORMATIVE framing: **no layer retired anything; the pod-template never lost the bare claim until C10's chart-side deletion lands.** The sentences the launch asked me to retract ("null is dropped by the chain" as *wrong*) — I do not retract them; they are the surviving truth. If any round later drafts "the valuesObject was stale" into D27/FRICTION, that sentence is exactly what §D2.8.2 falsifies and must not enter the record.

(iii) **Follow-up root-cause card — corrected body text, ready to paste** (replaces the chunks/C10.md:204 placeholder line "appset-charts valuesObject merge drops null-valued keys — fix the passthrough…" with the adjudicated framing):

> **Card body (root-cause, charts/base):** In the ai-gpu stack, null-valued keys never survive the ApplicationSet→Application hand-off: the live `gpu-ai-charts-appset` CR holds explicit nulls written by helm (`shared-storage: null` in EVERY generator element; `resources.limits."amd.com/gpu": null` while the B1 overlay was on main), yet every live Application is null-free doc-wide — including `gpu-ai-amd-gpu`, whose valuesObject is `{}` because its only generator content was such a null. Helm itself honors nulls at the layer below (v3.16.4 `pkg/chartutil/coalesce.go` deletes nil keys under coalesce; docs "Deleting a default key"; offline render proves it), so the deletion instruction dies precisely in the applicationset-controller evaluation of `charts/base/templates/appset-charts.yaml:114-122` (argocd v3.5.4) — sprig/mergo nil-skip in the line-120 `merge` or its serialization path, not distinguishable externally. Task: (1) reproduce the strip offline against argocd's pinned sprig/mergo (or file it upstream with the `{}`-valuesObject datum), (2) decide whether the line-117-123 passthrough (skip the merge when both custom dicts are empty) or a `toYaml`-of-$baseValues direct path can carry deletions, and (3) whichever way the decision goes, codify the repo rule now proven by §D2.8: **service overlays express per-cluster intent with ADDs only; deletion-inherited-by-null is a banned pattern repo-wide** (C10's carrier move is the reference implementation). Blast radius today: ZERO — no chart default in this repo currently requires per-cluster retirement through the chain (the two surviving generator nulls are the inert shared-storage one plus the amd claim C10 removes at the root), so this is hardening, not outage risk.

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md]
commands_run: [readonly-ai-gpu-kubernetes: Application gpu-ai-llama-swap full read (valuesObject census 0 nulls / APU pair, status.operationState 02:28:03Z, 10-entry history with per-sync sources snapshots, managedFields), ApplicationSet generator null-path enumeration (2 nulls live), Deployment (gen 49, bare pair template, Available=False@01:52:09Z, ProgressDeadlineExceeded@02:37:47Z, unavailable 1), ReplicaSets 779b58445d/965d474b7 template compare (identical limits, reloader-hash-only delta, revs 36/37 @01:52:39/02:27:46), Pending sweep + strata/radiance/router pod states, Node capacity/allocatable/heartbeat 04:30:20Z, Applications gpu-ai-amd-gpu (valuesObject {}) + gpu-ai-radiance null censuses => pass; readonly-gpu-kubernetes: Deployment gpu-llama-swap (gen 22, Available=True since 11-12T17:50:43Z, limits {amd.com/gpu:1}) => pass; git -C /home/coder/SpencersLab log/merge-base (main=ec18281fb, C07+C10 NOT ancestors; history revs 5600ec601/ec18281fb resolved) => pass; local helm v3.16.4 A/B renders on 56142d511^ blobs (A: null RETIRES at helm layer; B: live shape reproduces broken pair) => pass; webfetch helm coalesce.go v3.16.4 raw + helm docs values_files => pass; repo greps (NORMATIVE-phrase hunt = 0 hits, FRICTION/D26/C10 message reads) => pass]
deviations: none — read-only throughout; only EXPLORE.md written (this §D2.8 + RESULT). Launch premise corrected rather than assumed: the round was framed as post-C10-router-healthy; live state says C10 is unmerged and the router is still down — recorded as D2.8.1 instead of silently accepting the frame.
friction: Application CR reads arrive whole (no flattening on resources_get for CRs) — good; the 10-entry history cap means pre-Nov-9 syncs are gone (adjudication never needed them); the saved tool-output truncation required a python parse of the persisted JSON for the history table (round-3 friction note about flattened list reads stays valid for list ops only).
open_questions: [Owner/coord action owed, urgent: merge + sync C10 (56142d511) — it is the router's ONLY recovery route (manual step 3 does not fix the bare claim; staleness/retry does not either — D2.8.2), and the owner's "04:01 recovery" appears to be the gpu-cluster router or the ticket-side r2 approval, not gpu-ai; after the C10 sync, the AC7 receipt is router pod Running on gpu-8060s. Optional D26 amendment: append the §D2.8.4 boundary clause + the §D2.8.5(iii) corrected card body to the follow-up-card record before it is authored.]
next_suggested: coord: fold §D2.8 into D26's card-body line (the ready-to-paste paragraph above supersedes the :204 placeholder framing), ping the owner with the corrected live truth (router still down, C10 unmerged, step 3 also unexecuted — merge+sync C10 FIRST, then the Q10 protocol for radiance), and treat "null-absence at valuesObject fleet-wide" as the settled class law.
