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

## §D3 — radiance-fetch init: download stalls at ~1126 B then the pod stops (owner report 2026-11-13 ~12:37Z)

**VERDICT FIRST: there is no defect — the premise is false on both halves.** (1) The transfer never stalled: the `100 1126 100 1126 0 0 3070 0` line is curl completing the HF **302 redirect interstitial** (the resolve endpoint's body is literally `Found. Redirecting to https://us.aws.cdn.hf.co/xet-bridge-us/…`, content-length 1124–1128 B — signature-nonce variance), and every byte of the real 113.5 GiB stream flowed after it at **~95 MB/s** — at scout probe 12:47Z the same container log had grown to 66,035 bytes / 847 progress frames reading `69 113.5G 69 78.37G … 94.61M … 14:08 06:21`. (2) Nothing stopped the pod: initContainer `radiance-fetch` is **Running, restartCount 0, `lastState: {}` (never terminated once)**, no Killing/BackOff/OOM/Eviction events, `activeDeadlineSeconds` UNSET. The owner's viewer showed "nothing" because curl redraws the *same* progress line with `\r` and emits a newline only at stream end — a newline-rendering log view freezes exactly where the owner saw it freeze. The "stopping" signal is the Deployment's **`progressDeadlineSeconds: 600`** (app-template 5.0.1 default; the chart sets no override) firing `Progressing=False "ReplicaSet gpu-ai-radiance-59c96d5bcd has timed out progressing" (ProgressDeadlineExceeded)` — a **condition, not a killer**: it never touches the pod, it just makes ArgoCD/UI paint the app Degraded during a legitimately >10-min init. The "3070 B/s" the owner read is curl's average column for the 1126-byte redirect page alone (~0.4 s), not the stream. **No C11 chart fix site exists; owner action: wait out steps 4–5 of the runbook (§D3.7).** Context receipts the launch asked for: **step 3 HAS happened** (strata Deployment `spec.replicas: 0`, its pod gone; radiance scheduled the instant memory freed) and **C10 HAS landed live** (router recovered) — details §D3.8.

### D3.1 LIVE POD — every field of record (readonly-ai-gpu-kubernetes, probes 12:40–12:47Z)

- Pod `gpu-ai-radiance-59c96d5bcd-5xt4h`, uid `20ce09f6-56da-4151-9c6e-1719a10d1f90` — the SAME pod §D2.3 called Pending (created 02:28:44Z; it waited 9h58m for step 3, then scheduled at **12:26:24.441Z**). phase Pending (normal while an init runs), QoS **Guaranteed**, `terminationGracePeriodSeconds: 180`, `restartPolicy: Always`, **`activeDeadlineSeconds`: absent**, `metadata.annotations`: absent (⇒ no `reloader.stakater.com/auto` — chart ships it off on purpose, values.yaml:199-202 — so the reloader class cannot touch this pod, §D2.8.2's RS-flip mechanism does not apply here).
- `initContainerStatuses[0]` (radiance-fetch): image `docker.io/curlimages/curl:8.23.0`, imageID digest `sha256:3fb7e13e…`, **state.running.startedAt 12:26:27Z**, `ready: false`, `started: true`, **restartCount 0, `lastState: {}`** — there is no exitCode/signal/finishedAt because the container has NEVER exited. resources `200m/2Gi` requests==limits. `user.linux`: uid/gid 65532, supplementalGroups [486, 65532] — the D1 "supplementalGroups never set" note was strata's; radiance ships 486 live as designed.
- `containerStatuses[0]` (radiance serve): waiting `PodInitializing`, **imageID "" (engine image not pulled yet)** — the post-init sequence still to come: pull `stilldeadcode/radiance:1.17.0` (IfNotPresent, not on-node yet), then the ~66 GiB load under the 180×10 s startupProbe (values.yaml:235-246).
- GPU claim materialized: `allocatedResourcesStatus` shows `amd.com/gpu-r9700-1 → resourceID 0000:c4:00.0, Healthy` — first live receipt that the D24 named pool hands radiance the **R9700** (c4 = deviceID 7551 per §D2.1's sysfs read). The scheduler-determinism law §D3/D24 was designed for, working.
- Volumes: `models` = `persistentVolumeClaim llama-swap` (NOT hostPath-direct, NOT emptyDir), `shm` = emptyDir Memory 2Gi. Mounts: init `/models` RW + `/dev/shm`; serve `/models` `readOnly: true` + `recursiveReadOnly: Disabled`.
- Pod events, full list (events_list, 12:44Z pass): FailedScheduling 02:34:09 (the §D2 memory handshake, last of its kind), **Scheduled 12:26:24.441**, **AlreadyMountedVolume WARN 12:26:24**: *"The requested fsGroup is 65532, but the volume pvc-e4f5adf3-fc6d-42a0-af93-e888bf0b5934 has GID 0. The volume may not be shareable."* — cosmetic on local-path hostPath dirs sharing the RWO claim (same claim §3 called by PVC id — matches §3's `pvc-e4f5adf3-…`); the mount demonstrably works: 78+ GiB written by uid 65532 at probe time. Pulling 12:26:24 → Pulled 12:26:27 (2.259 s, 10,853,220 B) → Created 12:26:27 → Started 12:26:27. **ZERO Killing / BackOff / OOMKilling / Evicted / FailedToPull / Failed events on the pod.**
- Init log (pods_log -c radiance-fetch): 49,651 B / 637 `\r`-frames @ 12:40:57 → 66,035 B / 847 frames @ 12:47 (≈ +16.4 KB of frames in 6 min, monotone). Structure: echo line `radiance staging: fetch /models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad (curl-resume, 113.6 GiB class)` (script's own text, values.yaml:332), curl header rows, then `0 0 0 0…` (waiting headers) → `100 1126 100 1126 0 0 3070 0` (**newline-terminated** — curl closes the per-response meter when it moves to the redirected URL; this is the LAST line a newline-only viewer shows until the stream ends) → `0 113.5G 0 5.23M … 9:43:16 00:01 …` onward — all `\r`-separated, **ends mid-frame, no curl error code anywhere** (`endsWithErr` regex on `curl: (\d+)|failed rc=` = false).

### D3.2 THE KILLER QUESTION — nobody. Adjudication of (a)–(e)

- **(a) curl exited on its own: NO** — container still Running, restartCount 0, lastState {} (a single exit would have recorded terminated + incremented restartCount; the script's `exit "$rc"` paths all terminate the container).
- **(b) deadline: NO, and none could** — pod has no `activeDeadlineSeconds` (absent from the live spec; the chart never sets it). `progressDeadlineSeconds: 600` fired (live Deployment: Progressing=False/ProgressDeadlineExceeded, lastTransition **02:38:45Z** — it went stale during the 10 h Pending wait, 10 min after pod creation 02:28:44) but progressDeadline only flips a Deployment CONDITION; it kills nothing. Liveness/startup probes **cannot** touch an init container — kubelet probes app containers only, and the sole containerStatus shows `PodInitializing`. (Optional hardening, plan's call, NOT a defect: a legitimately >10-min first-boot init + load means the radiance Deployment will read "timed out progressing" through the whole healthy first boot — a `progressDeadlineSeconds` raise in `defaultPodOptions`/workload values would stop the lie; the sticky condition is precisely what sold the owner "the pod stopped".)
- **(c) OOMKilled: NO** — no OOMKilling event, node MemoryPressure=False (heartbeat 12:39:03Z), lastState {} ; and the arithmetic is laughable-class: curl's working set streams to disk at MB-scale buffers, far under the 2Gi init limit (D15's 2Gi holds).
- **(d) ephemeral-storage eviction: NO, and structurally impossible** — the 113.6 GiB lands on the **llama-swap PVC** (local-path → `/var/lib/rancher/k3s/storage/pvc-e4f5adf3-…`), which kubelet does NOT count against pod `ephemeral-storage`; DiskPressure=False; no Evicted event; the runbook's own pre-flight gate (step-0 table line 174: ≥120 GiB free on the 500Gi claim, `df -h`) was owner-executed host prep, and 78 GiB demonstrably landed.
- **(e) ArgoCD sync / reloader killing it: NO** — `Application gpu-ai-radiance` events show three manual syncs by `tms@spencerslab.com` at **12:25:25 / 12:25:39 / 12:25:56** to main `dc35707411a14c0c…` — all BEFORE the pod scheduled, and the pod identity is unchanged (same uid, created 02:28:44, generation 1): the syncs did NOT recreate or restart it (the C10 wave changed the llama-swap chart, not the radiance template — Deployment gen still 1). The reloader cannot be a killer here: the pod carries **no annotations at all** (D3.1) — §D2.8.2's ConfigMap-hash RS flip mechanism has no hook on this pod by design.

### D3.3 THE CHART — branch truth, and the rendered array equals it verbatim

`charts/radiance/values.yaml`, init `radiance-fetch` (controllers.radiance.initContainers) **lines 302–368**: image block 313–317 (`curlimages/curl:8.23.0`, IfNotPresent, renovate-pinned 315); `command:` 318–348 = `["sh","-c", <script>]` exec-form boot-guard idiom (repo gotcha 8), `args:` absent. Script constants: `LFS_SHA=0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20` (323), `PACK=/models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad` (324), `MARKER=/models/radiance/.staged-$LFS_SHA` (325), **URL line 326** `https://huggingface.co/StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe/resolve/main/qwen3.8-next-flash-fp8-iq4r-moe.rad`, marker-skip gate 328–331, the fetch line **338 verbatim**:
```
curl --fail --location --retry 5 --retry-delay 10 --continue-at - --output "$PACK" "$URL" || rc=$?
```
flags inventory: `-f/--fail` yes, `-L/--location` yes, `-C -/--continue-at` yes, `--retry 5 --retry-delay 10` yes; **NO** `--retry-max-time`, **NO** `--max-time`, **NO** `--speed-limit/--speed-time`, **NO** `--retry-all-errors`, **NO** `-sS`/`-#` (default `\r` progress meter — the viewer artifact's source), `-o` yes. rc-33 tolerated 339–342 (the "already fully retrieved" resume case — comment 333–336); `sha256sum --check` gate 343–346; `touch "$MARKER"` 347. Resources 349–360 (200m/2Gi equal pair); securityContext 361–368 (drop-ALL, no privilege). Staging path becomes the served path by identity — PACK *is* `/models/radiance/<file>`, the same `&modelPath` the serve args splice (26, 126), via persistence 393–401: `models: existingClaim: llama-swap`, advancedMounts `radiance.radiance → /models readOnly` + `radiance.radiance-fetch → /models` RW. The "113.6 GiB class" figure: pack ledger comment 16–26 (121,969,901,568 bytes, sha, ungated — RESEARCH RQ0) echoed into the 332 string. **Timeout knobs in chart values: none exist** — the D15 single-source scalars (53–64) are sizing only. **The live `spec.initContainers[0].command` string equals the values.yaml script byte-for-byte — no render drift** (contrast §D2.6's valuesObject layer: the null-drop disease does not reach plain string values; only nil-valued keys die).

### D3.4 THE 1126-BYTE ANSWER — offline reproduction at the sandbox (the decisive test)

Against the exact URL of D3.3, plain curl:
- **HEAD (no -L)**: `HTTP/2 302`, `content-length: 1124`, `location: https://us.aws.cdn.hf.co/xet-bridge-us/6ac1441f…/3c755720…?…Signature=…&Key-Pair-Id=01KXEF4KZ1B6FV465MAWR4M21F&Hash-Algorithm=SHA256`, `accept-ranges: bytes`, **`x-linked-size: 121969901568`**, **`x-linked-etag: "0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20"`** (the LFS oid == the chart's LFS_SHA, served in the header), `x-repo-commit: 8267a673…`, `x-hf-warning: unauthenticated…` (rate-limit advisory only), ratelimit `"resolvers";q=3000;w=300`.
- **GET (no -L), body captured**: 302 + body **1128 bytes**, `text/plain`, head = `Found. Redirecting to https://us.aws.cdn.hf.co/xet-bridge-us/…` — NOT an HF LFS pointer (~130 B), NOT JSON, NOT an HTML/JS interstitial: a plain-text redirect stub whose length **wobbles with the signed-URL nonce** (observed 1124 / 1126 / 1128 across three requests — the owner's 1126 is one draw of this distribution).
- **GET with -L** (range `-r 0-63`): `HTTP/2 302` → `HTTP/2 206`, `content-range: bytes 0-63/121969901568`, and the written file is **exactly 64 bytes** (`-L` discards the redirect body — proof the stub can never pollute `$PACK`), head `52 41 44 31` = ASCII **`RAD1`** — the .rad container magic (RESEARCH line 529 "`.rad` container file" VERIFIED) — binary object, not text.
- **Resume-shape probe** (`-L -r 1126-1189`): 302 (CL **1126** this draw) → **206 `content-range: bytes 1126-1189/121969901568`** — the Range header survives the redirect hop and the Xet-bridge CDN honors it: exactly the exchange `-C -` will perform after a partial.
- **Repo/file truth** (`/api/models/StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe/tree/main`): `qwen3.8-next-flash-fp8-iq4r-moe.rad  size=121969901568  lfs.oid=0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20 lfs.size=121969901568` — name, size, sha **triple-match the chart ledger** (values.yaml:19–21) and RESEARCH RQ0 (line 144). **The URL is correct — nothing is wrong to fix; no name/size mismatch, no LFS pointer trap.** The signed redirect target carries `Expires=1794577367` = +1 h validity — irrelevant to this design: every attempt re-enters through the resolve endpoint (fresh 302), and a connection already serving a 206 is not re-checked mid-stream.

### D3.5 RESUME SEMANTICS — the curl-resume design is real on this deployment shape

(i) **Missing/zero-byte `$PACK` with `-C -`**: no file (or 0 bytes) → offset 0, normal full transfer, no rc 33 — proven by the live first boot itself (the PVC held no `/models/radiance` tree; `mkdir -p` 327, transfer began at 0). rc 33 arises only when local size ≥ remote size — script already treats 33 as DONE (333–342).
(ii) **Partial stub**: `-C -` computes `Range: bytes=<size>-`, resolve 302s, **curl re-sends Range to the CDN and gets 206 at the exact offset** (D3.4 probe #4 = the live shape). No 416 exposure for any size < 121,969,901,568; at full size curl exits 33 pre-request → tolerated → sha → marker. And the 302-interstitial can never become the stub: with `-L` the redirect body is not written to `-o` (D3.4 probe #3, 64 of 64 bytes).
(iii) **Survival across restarts**: `/models` is the **llama-swap 500Gi PVC** (local-path → on-node storage dir, pod-independent); emptyDir is only `/dev/shm` (values 405–410). A crash, reschedule, or node reboot leaves the partial intact → the next init resumes; the marker short-circuits completed staging (328–331). No re-download-of-113.6-GiB-per-restart exposure exists. (Honest limit: mid-stream-resume after a forced kill was not observed live — no restarts to read; the offline probes cover its server-side half exactly.)

### D3.6 TIMING ARITHMETIC — the object began moving at ~12:26:30

Stream reality (live frames): after the 302, first real frame `0 113.5G 0 5.23M … 00:01`, then steady 80–100 MB/s current-speed; at 12:47Z: **69 % / 78.37 GiB / avg 94.61 MB/s / spent 14:08 / left 06:21** — curl's own total estimate 20:29, i.e. the 121,969,901,568 B pack in ~21 min ≈ 760 Mbps, the 1-Gbps-class ≈ 110 MiB/s expectation the launch sketched (its "~18 min" at 110 MiB/s is the same class). The owner's "3070 B/s" is the average-speed column **of the 1126-byte redirect page alone** (~0.37 s spent); at 3070 B/s the pack would need ≈ 4.6 years — the number never described the stream. **The transfer BEGAN moving the object** (second real byte ~3 s after start): the "times out too soon" hypothesis is dead — there is also nothing that could time out (no `--max-time`/`--speed-limit`/`--speed-time` on the curl line, no `activeDeadlineSeconds` on the pod; curl's 300 s connect timeout applies to connection setup only, and connects are completing in ~3 s). The network traffic the owner sees is the ~95 MB/s stream itself.

### D3.7 RUNBOOK / RESEARCH CROSS-CHECK — this step is predicted with receipts; today's behavior is the predicted behavior

- `.agents/notes/radiance-on-target-acceptance.md`: step-0 host-prep row **line 174** ("claim free space … ≥120 GiB free on the 500Gi claim before the 113.60 GiB pack stages"); names-block **line 193** (pack `/models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad — 113.60 GiB (121,969,901,568 B), lfs sha256 0af5e962…, ungated, staged on the shared llama-swap claim — identical to the live ledger); **Step 4, lines 380–395**: the `radiance-fetch` staging receipts — log tail command `kubectl -n default logs deploy/gpu-ai-radiance -c radiance-fetch | tail -5` (line 388: the **kubectl** form renders `\r` updates and would NOT have frozen for the owner), expectation "radiance staging: complete" (or marker-skip) + `.rad`+marker owner/group `65532:65532` (392–393), and the explicit warning that the independent sha256sum re-check is "a minutes-class full read — run it only if the marker is doubted" (394–395). Step-5/6 **lines 452–455**: init completes → engine container starts, loads ~66 GiB working set (113.6 pack − 47.7 GiB streamed n-gram tier) — with the 180×10 s startupProbe envelope (chart 235–246) as the load allowance.
- `RESEARCH.md`: **line 144** RQ0 pack ledger row (bytes/GiB/sha — matches chart, live 302 headers, and HF API); **line 532**: the upstream project's own documented download shape — "download resumes (`curl -LC -`)" — the chart implements the upstream-sanctioned method verbatim (plus `--fail --location`); lines 151/658: 113.6 GiB / ~47.7 GiB n-gram / MTP-3 cross-checks; line 529: `.rad` container-file verification (magic `RAD1` now additionally witnessed D3.4). The disk ngram tier (`--ngram-placement disk`, arg 14 of serveArgs) is the same 47.7 GiB staying on disk — consistent with the 113.6 landing on the PVC.
- **Nothing the fix would touch**: the runbook's own step-4 receipt path (kubectl logs) and expectation lines are the operating instructions TODAY — verdict = owner waits for "radiance staging: complete" (~12:50Z expected: 06:21 remaining + sha256sum minutes-class at ~350 MB/s–2 GB/s single-thread), then step 5 (image pull + engine boot).

### D3.8 CONTEXT THE LAUNCH ASKED FOR — step 3 happened; C10 landed; router healthy; strata is down

- **Step 3 executed**: Deployment `gpu-ai-llama-swap-strata` `spec.replicas: 0` (observedGeneration 45), its pod gone from the namespace inventory; radiance's `Insufficient memory` FailedScheduling has no successor after **12:26:24.441 Scheduled** — the free-memory flip is exactly §D2.4's arithmetic coming true (64 Gi strata request leaves → 123.9 Gi class free ≥ 64 → scheduler acted within the minute).
- **C10 landed live**: main = `dc3570741` (plans records) atop `dc69d64ec` = "fix(cf-143): C10 — claim carrier…" — the C10 fix IS in main history (56142d511 is not an ancestor because the merge re-created it; dc69d64ec is that content). Argo synced Application gpu-ai-radiance to `dc35707411a14c0c…` at 12:25:25–56 (tms@spencerslab.com, manual). Router: Deployment gpu-ai-llama-swap gen **50**, RS `gpu-ai-llama-swap-6796d989db` — **Available=True since 12:25:27Z**, pod `…-6796d989db-qvdg4` Running **2/2**, main resources `{limits: {amd.com/gpu-8060s: 1}, requests: {amd.com/gpu-8060s: 1, cpu: 1, memory: 4Gi}}` — **the bare `amd.com/gpu` claim is gone from the live template**: §D2.6's outage is closed; `llama.spencerslab.com` fronting is restored (the owner's "got the pod started" = this router pod).
- Node: pools `gpu-r9700-1: 1` / `gpu-8060s: 1` / bare `amd.com/gpu: "0"` unchanged; Ready/MemoryPressure=False/DiskPressure=False @ 12:39:03Z; ephemeral capacity 950796Mi. Free-memory by the §D2.4 method now: Σ running eff-requests ≈ system 1.158 + router 5.125 + radiance 64 (init 2Gi ≤ the 64 pod-total already on the books) ≈ 70.3 Gi → **≈ 54.8 Gi free** — the step-6 ladder-up headroom (≤ 96 Gi pins) remains open.

### D3.9 BLAST RADIUS — the same fetch shape exists once elsewhere and is fine

Grep of `charts/` for the `resolve/main`+curl pattern outside radiance: `charts/llama-swap/values.yaml:567` — the gpu-cluster whisper rung's `curl -fL --retry 3 --retry-all-errors -o /models/whisper/ggml-large-v3.bin.part …` (+ its golden/evidence copies: `tests/golden/gpu.config.yaml:794`, `gpu-ai.config.yaml:1332/1351`, `flashnext-pre-chunk-baseline/*`) and the rana `dl` helper. Same 302-interstitial mechanics but ~3 GB files that complete in seconds–minutes, `-o …part` + mv rename, and no `--continue-at`; no defect and no freeze-window worth a card. The radiance fetch is the only 113.6-GiB-class curl in the repo; `charts/vllm` stages via `huggingface_hub.snapshot_download` in the engine image's python (values 462–532 region), a different mechanism, untouched. `--continue-at` appears nowhere else.

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md]
commands_run: [readonly-ai-gpu-kubernetes: pods_list_in_namespace default, pods_get radiance pod (full spec+status), events_list (radiance-scoped pass), pods_log -c radiance-fetch (3 tail passes 12:40–12:47Z), resources_get Deployments radiance/strata/router + Node ai-gpu + Application(argocd ns — kind/apiVersion miss on that MCP), nodes_stats_summary (fs parse came back empty — DiskPressure=False + 78 GiB landed carried the disk claim instead) => pass; offline: curl HEAD/GET-no-L/GET-with-L(-r 0-63)/resume-probe(-r 1126-1189) against the chart's exact resolve URL + HF tree API + od of bodies => pass; git -C /home/coder/SpencersLab log/merge-base main (C10 = dc69d64ec, main HEAD dc3570741) => pass; repo greps (runbook fetch/113.6/progress lines, RESEARCH RQ0 ledger, charts/ curl-pattern blast radius) => pass]
deviations: none — read-only probes on the readonly tier; no pod exec, no mutations; the only file written is this EXPLORE.md §D3. The offline URL test stayed byte-safe (HEAD, one ~1.1 KB redirect body, and ranged GETs of 64 B).
friction: the MCP Application read failed on apiVersion resolution ("no matches for kind Application in argoproj.io/v1alpha2" — this readonly-ai-gpu server's discovery lacks the argo CRDs; the sync evidence came from Application-labelled Events instead); nodes_stats_summary fs block arrives unparseable via the MCP wrapper (worked around with node conditions + the live byte-progress); the owner's log-viewer freeze class itself: progress lines are \r-delimited, so tailLines counts "lines" oddly (637 frames in 49 KB).
open_questions: none research-grade. Cosmetic options for plan/coord, explicitly NOT defects: (1) a `progressDeadlineSeconds` override (or runbook sentence) so the radiance Deployment stops reading "timed out progressing" during legitimate first boots — the app-template 600 s default is what sold the "pod stopped" story; (2) an optional `--silent`/`-#` single-line progress style in the fetch if the owner's log tooling stays newline-rendering. Owner-facing answer to today: the fetch is healthy at ~95 MB/s (curl's own ETA 20:29 total), step 4 receipts per runbook lines 380–395 expect "radiance staging: complete" then the engine boot — do NOT restart the pod, do NOT touch the chart.
next_suggested: tell the owner the single honest line — the premise "timing out too soon" is FALSE: nothing times out and nothing stopped; 1126 B was the redirect interstitial, the object itself has been streaming at 95 MB/s and the init completes on its own (~12:50Z staging + step-5 boot) — then let the C06 step-4/5 receipts close the run; keep the two cosmetic items (progressDeadline prose/override, log style) as optional plan-side polish only if the final review wants them.

## §D3 — radiance-fetch: BusyBox sha256sum has no --check (live restart loop, owner report 2026-11-13 ~12:4xZ)

*(Scout round 5, probes ~13:02–13:03Z, readonly-ai-gpu-kubernetes + repo reads + busybox upstream. The duplicate §D3 heading is launch-verbatim; this section continues the §D3 above — same init container, minutes later on the clock — and its subsections use **D3b.*** so cross-references stay unambiguous. §D3's "no defect" verdict stays correct FOR THE DOWNLOAD it watched; the defect it stepped over is the very gate §D3.3 transcribed without adjudication: "`sha256sum --check` gate 343–346". The download §D3.6 saw streaming at 95 MB/s finished at 12:52:40Z and the pod has been crash-looping on the checksum line ever since — the §D3 "wait it out" advice expired at completion.)*

**VERDICT FIRST.** One chart line is defective: `charts/radiance/values.yaml:346` — `echo "$LFS_SHA  $PACK" | sha256sum --check`, run by `sh` inside `docker.io/curlimages/curl:8.23.0` (values 313–317), an **Alpine-based image whose coreutils applets ARE BusyBox v1.37.0** — the live container log's own banner is the authority. BusyBox `sha256sum` declares only short options (`getopt32(argv, "^" "scwbt" ...)`, upstream `coreutils/md5_sha1_sum.c`); ANY GNU long option (`--check`, `--status`, `--quiet`) hits the unrecognized-option path: prints `sha256sum: unrecognized option: check` + usage, **exit 1** (live `lastState.terminated.exitCode: 1`), `set -e` aborts before `touch "$MARKER"` (347) — so the marker can NEVER be written, every restart re-enters, the curl resume is a <2 s no-op (the pack is fully on the claim: resume offset **121,969,901,568 == the full ledger size**), and the pod CrashLoopBackOffs (live: **restartCount 6, back-off 5m0s**). Fix shape: replace the gate with the BusyBox/GNU-portable equality check (full command array in D3b.4); the equally-portable minimal-diff variant `sha256sum -c -` is recorded and adjudicated. Blast radius: **this is the only defective busybox-grammar call site in the repo** (charts/ + services/ + scripts/ + containers/ audited, D3b.7); two prose carriers restate the broken form and ride the fix: `.agents/notes/radiance-on-target-acceptance.md:383` and `chunks/C06.md:267`. No owner-side unblock makes the pod's own gate work without the fix; a same-verification host-side marker exists as a human-owned loop-breaker only (D3b.6).

### D3b.1 THE CHART'S OWN WORDS (file:line, verbatim)

- Init `radiance-fetch` under `controllers.radiance.initContainers`: **values.yaml 302–368**. Image block **313–317**: `repository: docker.io/curlimages/curl` (314), renovate pin `# renovate: datasource=docker depName=docker.io/curlimages/curl` (**315**), `tag: "8.23.0"` (**316**), `pullPolicy: IfNotPresent` (317). No digest FIELD (repo D2 law); forensic anchor = live `imageID: docker.io/curlimages/curl@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93` (pods_get today) — and the same container's own log emits `BusyBox v1.37.0 (2026-01-10 15:38:28 UTC) multi-call binary` ⇒ **the busybox-family image in this chart is the INIT image itself, not the engine image** (`stilldeadcode/radiance:1.17.0` is the serve container; the engine image is never exec'd by the fetch step).
- Rendered command = `["sh","-c",<script>]` (318–348), re-confirmed byte-equal to values in TODAY's live pod spec (§D3.3 established the no-render-drift property; re-read holds). Script verbatim (line numbers = values.yaml):
  ```
  322  set -e
  323  LFS_SHA=0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20
  324  PACK=/models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad
  325  MARKER=/models/radiance/.staged-$LFS_SHA
  326  URL=https://huggingface.co/StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe/resolve/main/qwen3.8-next-flash-fp8-iq4r-moe.rad
  327  mkdir -p /models/radiance
  328  if [ -f "$MARKER" ] && [ -f "$PACK" ]; then
  329    echo "radiance staging: marker + pack present — skipping"
  330    exit 0
  331  fi
  332  echo "radiance staging: fetch $PACK (curl-resume, 113.6 GiB class)"
  ...  rc=0; curl --fail --location --retry 5 --retry-delay 10 --continue-at - --output "$PACK" "$URL" || rc=$?   (337–338)
  ...  if [ "$rc" -ne 0 ] && [ "$rc" -ne 33 ]; then ... exit "$rc"; fi                                          (339–342)
  346  echo "$LFS_SHA  $PACK" | sha256sum --check
  347  touch "$MARKER"
  348  echo "radiance staging: complete"
  ```
- **Exact sha256sum invocation form**: GNU long option `--check`, NO operand file, check-line delivered via **stdin pipe** — relying on GNU's "with -c and no file, read the checksums from stdin" behavior. No `--status`/`-s`, no checksum FILE path on disk. BusyBox never reaches check mode at all — it dies at option parsing.
- **Expected-digest source**: hardcoded `LFS_SHA` at **323**, equal to the pack ledger in the values header (16–26: 121,969,901,568 B / 113.60 GiB / sha `0af5e962…` / ungated — **RESEARCH RQ0**, RESEARCH.md:144) and independently live-verified against the HF API §D3.4 (`x-linked-etag` header == the same sha; tree API `lfs.oid` == the same sha). The digest value is RIGHT; only the syntax carrier is wrong.
- Other GNU-only long-option coreutils calls in this chart/repo: **none** — full audit in D3b.7.

### D3b.2 LIVE CONFIRMATION (readonly-ai-gpu-kubernetes, pods_get + events_list + pods_log, 13:02–13:03Z)

- `initContainerStatuses[0]` (radiance-fetch): **`restartCount: 6`**, `state.waiting.reason: CrashLoopBackOff`, message `back-off 5m0s restarting failed container=radiance-fetch`; **`lastState.terminated`: exitCode 1, reason Error, startedAt 12:52:39Z, finishedAt 12:52:40Z** — a **1-second** iteration: marker-skip not taken (marker absent by construction), fetch echo, curl resume no-op, `--check` boom. First run: Started 12:26:27 → terminated 12:52:40 = the ~26-min stream completing at exactly the moment §D3.6 predicted (its ETA arithmetic said ~12:50Z).
- **The loop is the checksum exit, not the download** — current log tail (pods_log -c radiance-fetch, 13:02Z) verbatim structure: `radiance staging: fetch …(curl-resume, 113.6 GiB class)` → `** Resuming transfer from byte position 121969901568` → redirect-page meter (`100 1124` — the same §D3.4 interstitial, size-wobble draw) → four all-zero frames (nothing to transfer) → `sha256sum: unrecognized option: check` + BusyBox v1.37.0 banner + `Usage: sha256sum [-c[sw]] [FILE]...`. No `curl:` error code anywhere, no "curl failed rc=" line (the rc-tolerance at 339–342 is working — curl exited 0/33 as designed).
- **Main container has NEVER started**: `containerStatuses[0]` (radiance serve): `waiting: PodInitializing`, **`imageID: ""`** (engine image not even pulled), `started: false`, `restartCount: 0` — no model load has happened; nothing on the GPU side to unwind.
- **File completeness**: no API object carries the file size (it is the `llama-swap` PVC → local-path hostPath `pvc-e4f5adf3-…/radiance/`; the PVC/PV only show the 500Gi VOLUME capacity) — say so plainly. The size proof is curl itself: `-C -` computes the resume offset **from the local file** and printed 121,969,901,568 == the exact ledger size (RESEARCH RQ0 / values:19), and §D3.4 proved `-L` discards the redirect stub (it can never pollute `$PACK`). **Honest caveat**: size-complete ≠ hash-complete — the verification has NEVER passed, so the bytes are unverified by the pod's own gate. That is precisely why the fix must repair the gate, and why nobody should "skip to the marker" without running the hash once (D3b.6).
- Events (fieldSelector involvedObject.name=…5xt4h): Scheduled 12:26:24, Pulling/Pulled 12:26:24–27 (2.259 s, 10,853,220 B), Created/Started 12:52:39, **BackOff 12:57:30**. ZERO Killing/OOMKilling/Eviction — nothing external touches the pod; it self-crashes via exit 1 + `restartPolicy: Always` on the init. Pod `activeDeadlineSeconds` still absent.

### D3b.3 BUSYBOX v1.37.0 SEMANTICS — source-grounded

Authority: `coreutils/md5_sha1_sum.c`, busybox upstream (GitHub `mirror/busybox` raw fetches this round at tag `1_36_1` and `master`; the check-loop below is **byte-identical across both** ⇒ 1.37.0 sits inside the proven range), corroborated by the LIVE banner/behavior in the owner's own log.

- **Long options are not implemented by the applet.** Parse path: `flags = getopt32(argv, "^" "scwbt" "\0" "s?c:w?c")` — a SHORT-opt string only; unknown `--foo` lands in libbb's unrecognized-option printer → `bb_error_msg("unrecognized option: %s")` + applet usage + non-zero exit. Exactly the owner log. ⇒ `--check`/`--status`/`--quiet` are illegal in this image, period.
- **The source's own FIXME spells out the GNU side of the asymmetry**: *"GNU coreutils 8.25 has no -s option, it has only these two long opts: --quiet / --status"* ⇒ **`-c -s`/`-cs` is BusyBox-only and BREAKS GNU** — the launch's hypothesis (b) `sha256sum -cs file` is NOT image-swap-portable. Rejected.
- **(a) check-file via `-` on stdin — YES, both.** BusyBox: `pre_computed_stream = xfopen_stdin(*argv)` (libbb maps `"-"` → stdin) and additionally `if (!*argv) *--argv = (char*)"-";` (no operand defaults to stdin on ≥1.36); the applet's built-in example is literally `$ md5sum -c -` → `busybox: OK`. GNU: `-c -` is the classic documented idiom (GNU does NOT accept bare `-c` with no operand ⇒ always write the explicit `-`). Check-line grammar: split at first space, then skip `"  "` or `" *"` (comment cites coreutils 9.1 single-space too) ⇒ the `"hash␣␣/abs/path"` line at 346 parses identically on both.
- **Failure semantics under `-c` (loud, no `-s`)**: mismatch prints `<file>: FAILED` + stderr `WARNING: 1 of 1 computed checksums did NOT match`, `EXIT_FAILURE`; **missing file** → `can't open '<file>'` + `FAILED` + `EXIT_FAILURE`; empty/malformed stdin → `no checksum lines found` + `EXIT_FAILURE`. `-s` suppresses OK/FAILED AND the WARNING (usage: "Don't output anything, status code shows success") ⇒ `-s` is the WRONG choice for a boot gate that must log loudly.
- **(c) compute-and-compare in shell — YES, both.** Compute form: `printf("%s  %s\n", hash_value, *argv)` — the two-space GNU-text-mode shape — so `sha256sum "$PACK" | cut -d' ' -f1` yields the bare hex on BOTH BusyBox and GNU (`cut` is a busybox applet present in Alpine; POSIX `[` and `$(…)/set -e` interaction: a failing substitution in an assignment kills the script under `set -e` — busybox ash and bash alike).

### D3b.4 THE FIX SHAPE (surgical, portable, survives an image swap)

**Recommended replacement — one-line→four-line edit at values.yaml:346, everything else byte-kept.** Full replacement command array as it renders:

```yaml
command:
  - sh
  - -c
  - |-
    set -e
    LFS_SHA=0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20
    PACK=/models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad
    MARKER=/models/radiance/.staged-$LFS_SHA
    URL=https://huggingface.co/StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe/resolve/main/qwen3.8-next-flash-fp8-iq4r-moe.rad
    mkdir -p /models/radiance
    if [ -f "$MARKER" ] && [ -f "$PACK" ]; then
      echo "radiance staging: marker + pack present — skipping"
      exit 0
    fi
    echo "radiance staging: fetch $PACK (curl-resume, 113.6 GiB class)"
    # rc 33 = "the file is already completely retrieved" under
    # --continue-at - : a pack that finished without ever having
    # written its marker (kill between bytes and touch) is DONE,
    # not a failure — set -e would otherwise boot-loop on it.
    rc=0
    curl --fail --location --retry 5 --retry-delay 10 --continue-at - --output "$PACK" "$URL" || rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 33 ]; then
      echo "radiance staging: curl failed rc=$rc"
      exit "$rc"
    fi
    # The marker is only written after the sha256 PASSES — the
    # marker IS the landed-file provenance (C06 step-4 receipts
    # sha256sum against this same ledgered value). BusyBox grammar only:
    # the curl image is Alpine — sha256sum there implements short -c[sw]
    # and NO GNU long options; GNU in turn has no short -s. Equality on
    # the two-space compute form (printf("%s  %s") upstream) is the only
    # shape both applet families pass, loudly, with the digests on one line.
    actual=$(sha256sum "$PACK" | cut -d' ' -f1)
    if [ "$actual" != "$LFS_SHA" ]; then
      echo "radiance staging: sha256 MISMATCH expected=$LFS_SHA actual=$actual"
      exit 1
    fi
    touch "$MARKER"
    echo "radiance staging: complete"
```

- **Why this and not the alternatives**: the launch's hypothesis (plain shell equality) CONFIRMED as the primary shape — it is the only recommended form that satisfies "log line naming expected vs actual" literally (D3b.3: neither BusyBox nor GNU `-c` prints the computed digest on mismatch); it survives any future image swap (busybox↔GNU) untouched. **Coarse-grained accepted variant** (smaller diff, two tokens: `sha256sum --check` → `sha256sum -c -`): equally portable, keeps the `"<pack>: OK"` receipt, fails non-zero with `FAILED`+WARNING and names the FILE but never the digests — plan's call between the two; **`-c -s`/`--status`/`--check` and bare `-c` are all rejected with source reasons above**; a temp check-file + `sha256sum -c "$FILE"` is portable but strictly more moving parts (and rootfs writes) for zero gain.
- **Failure semantics preserved** (the law the gate exists for): wrong/partial digest → `sha256 MISMATCH expected=… actual=…` + `exit 1` → init crash (loud, non-zero), `touch "$MARKER"` (347) unreachable ⇒ the marker stays the provenance authority (values 343–345 comment unchanged in meaning). Missing `$PACK` → `sha256sum: can't open …` (busybox) / `cannot open … ` (GNU), substitution rc≠0 on the assignment → `set -e` aborts, non-zero, marker untouched. Marker-skip gate (328–331) untouched — after one good staging, restarts remain a 0 s skip.
- **Nothing else in the init changes** (honest per-item verdict): the **curl flags are fine** — `--fail --location --retry 5 --retry-delay 10 --continue-at -` are real-curl options (the image ships full curl, not busybox curl) and today's log proves the resume no-op round-trips in <2 s with the rc-33/0 tolerance working exactly as designed; **the "113.6 GiB class" wording is accurate** (121,969,901,568 B = 113.60 GiB); **the progress output** (`\r` default meter, the §D3 freeze artifact, the 1124 B redirect row) stays a cosmetic option only; **timeout posture unchanged** — no `--max-time` needed, no pod `activeDeadlineSeconds` involved, and the loop self-sustains at ≤1 s per iteration with no node cost (backoff-capped at 5 m).
- **Prose carriers to re-pin in the same fix wave** (they restate the broken form as fact): `.agents/notes/radiance-on-target-acceptance.md:383` ("marker ONLY after `sha256sum --check` passes" → the portable-gate wording; the runbook step-4 receipts and the host-side `sha256sum` re-check line 394 stay — host has GNU, compute-only, never `--check`-dependent), and the plan-side **`chunks/C06.md:267`** ("sha256sum --check … byte-confirmed in the chart" — the C06 operator-proof checked PRESENCE of the string, not the grammar against the image's applet set: third sighting of the "one layer below the surface" class beside §12.8's command/entrypoint law). DECISIONS **D10 (DECISIONS.md:72)** names only mechanism + marker ("marker-gated on the lfs sha") — no amendment owed (append-only anyway).

### D3b.5 TEST-SITE MAP (red-first leg)

- **Law home**: `charts/llama-swap/tests/TEST_SPEC.md` "## 12. cf-143 … whole-wave test contract" (**line 3343**); fetch-init arms descend from the wave table's C02 row (**3378**, `charts/radiance/tests/*`) and the §12.3 class law (**3604**, "after any surface move, enumerate ALL suites reading the moved literals"); a fix round records as the test session's next §12.x section (numbering is the test session's property — §12.8/§12.9 precedent).
- **Current assertion site (the silent gap)**: `charts/radiance/tests/test_render.py::test_ac2_staging_init_shape` (**268–309**) — pins exec-form command list, `.staged-` marker + full lfs sha + HF resolve URL + curl presence, image family (`curlimages/curl` OR engine image, **300–304**), renovate-comment presence (**305–309**). It asserts the staging **vocabulary** but never the checksum **grammar** — a suite-wide 43P (STATE: C10 round) through a broken gate. Helper: `radiance_testlib.py` `fetch_init()` (**235**), `INIT_NAME` (**117**).
- **Red-first needle shape (parse-based, not a crude whole-file grep)** — new arm in `test_render.py`, e.g. `test_ac2_staging_grammar_matches_the_init_image_applets`: render (`R.render(service=False)`), take `init = R.fetch_init(...)`, `script = command[2]`; gate the arm on **image identity**: if `init.image.repository` ∈ busybox-family set `{docker.io/curlimages/curl, curlimages/curl, docker.io/alpine, alpine, busybox}` (the premise pin — makes the class law non-vacuous and survives an image swap), then for every script line invoking a coreutils hash applet (`\b(md5sum|sha1sum|sha224sum|sha256sum|sha384sum|sha512sum)\b`) assert: **no `--` long option on the line** (BusyBox declares only short `scwbt` — cite `md5_sha1_sum.c` getopt32 + the live banner), and **no lone `-s`/`-w` without `-c`** plus reject bare `-c` without an explicit operand (GNU asymmetry per the source FIXME). RED today at values.yaml:346 naming the fix chunk; green with either recommended shape.
- **Image-identity leg to add** (the class must not silently return via an image swap): keep the 300–304 family assertion, ADD a digest-ledger comment check beside the init image block (repo D2 tag+digest-in-comment convention — seed value: live imageID `sha256:3fb7e13e…`, D3b.1) so the busybox applet set under the grammar law is *pinned*, not inferred from a floating tag; and keep the renovate pin leg (305–309). If the swap story ever moves to a GNU-coreutils curl image, the family-set membership flip is an explicit one-edit-site change that the grammar leg will re-adjudicate.
- **Runbook-side**: `tests/notes/radiance-runbook.sh` needs the literal `sha256sum` in the doc (T5 `need_lit` **line 514**, marker-set **561**) — the prose re-pin in D3b.4 keeps that literal (the doc still names the tool; only `--check` dies). No runbook.sh needle references `--check`. The C06 test round's "owner-executed command" law (test-wave deviation 7, STATE:576) is unaffected.

### D3b.6 COST / CONTEXT FOR THE OWNER

- **Post-fix runtime from exactly this point**: nothing re-downloads — 113.6 GiB is already on the claim (size-proven, D3b.2). Next iteration after merge+sync: marker-skip not taken (<1 s) + curl resume no-op (~2 s, live-measured) + **one full `sha256sum` pass** over 113.6 GiB: disk-bound single-thread, the runbook's own "minutes-class full read" (line 394) and §D3.7's 350 MB/s–2 GB/s envelope ⇒ **~1–6 min, one time** — then `touch marker`, exit 0, engine pull + boot (step 5). Every restart AFTER that is the marker-skip exit 0 in <1 s. The pod needs no deletion: the Deployment's restarts keep coming (backoff-capped 5 min); sync applies the fixed template, a fresh pod rolls under `strategy: Recreate`.
- **Owner-side unblock WITHOUT the chart fix**: strictly — **none exists that makes the pod's own gate work; the checksum is the gate and the gate is the defect** (say-so explicit per the launch). What DOES exist is a human-owned *loop-breaker with the same verification*, not a bypass: on the node, `sha256sum /var/lib/rancher/k3s/storage/*llama-swap*/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad` (host GNU, compute form — must print `0af5e962…`), and ONLY on a match, `touch …/radiance/.staged-0af5e962…` + `chown 65532:65532` of the marker — the init then marker-skips. That is the runbook step-4 re-check clause (394–395) executed out-of-band; it is barred to agents (host lane + no-exec law), and it does NOT substitute for the chart fix: the in-pod gate stays broken for any future cold staging until line 346 lands. Do NOT touch the pack file itself (the design never truncates it; `curl -C -` only extends).

### D3b.7 BLAST RADIUS — the BusyBox-vs-GNU class, repo-wide

- **Defective sites: exactly one** — `charts/radiance/values.yaml:346`. Plus its two prose carriers (runbook :383, chunks/C06.md :267).
- Busybox-family images with shell commands elsewhere, all verified POSIX-applet-safe: `charts/playsms/values.yaml` init-gammu-spool on `busybox:stable` (13–28): `mkdir -p`/`chown -R`/`chmod -R 0775` — fine. `charts/prowlarr/values.yaml` init-config on `alpine:3.24` (28–32): `chown -R 568:568` — fine. (`charts/mosquitto` "-alpine" and `charts/privatebin` "nginx-fpm-alpine" are APP images — no shell init.)
- Long options that are NOT this class (app's own parser, full binary in the image): every `curl --flag` site (radiance 338; `charts/llama-swap/values.yaml:567` whisper `--retry-all-errors` — curlimages/strata images ship real curl; §D3.9 already cleared it); `git apply --check [--reverse]` (`containers/strata/Dockerfile:145` build RUN, `charts/llama-swap/tests/test_strata_c09_ornith_carry.py:291` needle — git implements its own long options); `rulesync generate --check` / `aislop` / pytest legs (dev/CI runners, GNU userland). `sed -i` (exporter-mikrotik values 58–60 inside `ghcr.io/akpw/mktxp` app image; playsms ConfigMap script 97–102) — busybox sed AND GNU sed both support `-i`, not a risk either way.
- `services/`, `scripts/`: zero `sha256sum`/`sha512sum`/`md5sum` hits. `containers/`: sha256 references are digest literals in ledgers/tests, no runtime coreutils-long-option calls. **Conclusion: the class cannot currently return anywhere else in the repo; the D3b.5 legs are what keep radiance itself from re-introducing it.**

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md]
commands_run: [readonly-ai-gpu-kubernetes: pods_get gpu-ai-radiance-59c96d5bcd-5xt4h default (full spec+status), events_list fieldSelector involvedObject.name=…, pods_log -c radiance-fetch tail=30 => pass; repo reads/greps: charts/radiance/values.yaml whole-file, test_render.py 260–319, radiance_testlib.py, TEST_SPEC §12 (3343+), chunks/C06.md, runbook + radiance-runbook.sh greps, charts/ + containers/ + services/ + scripts/ GNU-long-option + busybox-image audit, playsms/prowlarr/exporter-mikrotik init reads => pass; webfetch busybox mirror/busybox md5_sha1_sum.c @1_36_1 + @master, curl-docker repo listing, HF/ghcr earlier-round receipts reused => pass; git log/branch read-only => pass]
deviations: none — read-only probes + the single sanctioned EXPLORE.md append. Duplicate "## §D3" heading is launch-verbatim (subsections D3b.* disambiguate). The prior §D3's verdict stands for the download it probed; its completion window is where the checksum defect surfaced — recorded as supersession-at-completion, not as a falsified earlier finding.
friction: busybox gitweb (git.busybox.net /plain/) + mirror 1_37_0/1.37.0 raw URLs all 404 (mirror/busybox tags stop at 1_36_1) — worked around by diffing 1_36_1 vs master, bracketing 1.37.0, and anchoring on the live banner; curl/curl-docker alpine Dockerfile not resolvable by path — Alpine-base claim rests on the live image's own BusyBox banner (runtime authority anyway); the glob tool returned "No files found" for the dot-hidden plans path (used shell ls).
open_questions: none research-grade. For coord/plan: (1) decide D3b.4 primary (equality) vs minimal variant (`-c -`) — both portable; equality is the only shape whose failure log names expected AND actual; (2) the fix is a NEW live-defect chunk (C11-class) whose test wave is the D3b.5 red-first legs + §12.x class-law record; prose carriers (runbook :383, chunks/C06.md :267) ride the same commit per the §12.3 enumerate-all-suites law; (3) owner line: loop cause = BusyBox `sha256sum` has no `--check`; the 113.6 GiB download is DONE and size-verified; the bytes are NOT yet hash-verified (the gate never passed) — post-fix init spends one minutes-class sha256 pass then exits 0 and boots the engine, zero re-download; the only without-fix path is the host-side hash+marker touch (human-owned, same verification, D3b.6).
next_suggested: plan a C11-class live-defect fix chunk straight from D3b.4's replacement command array + D3b.5's two legs; fold the owner word (fix-merge vs host-side unblock) into the next batched question round.

## §D4 — sha256 pass: live elapsed + the real envelope (scout round 6)

**VERDICT FIRST: still running at the final probe (14:04:36Z) — elapsed 25 min 48 s — and the "~1–6 min" envelope (§D3b.6, EXPLORE.md:1195) is not merely beaten, it is STRUCTURALLY refuted.** The pass is NOT disk-bound: it is **CPU-QUOTA-BOUND at the chart's own 200m init limit** — measured `radiance-fetch` cpu `usageNanoCores 200,974,597` (pinned at the 0.200-core cap, kubelet stats 14:02:11Z), cpu PSI `some.avg10 = 64.73` (severely stalled on CPU) vs **io PSI `avg10 = 0.00`** and `majorPageFaults = 0` (disk invisible). Expected total: **~30–68 min** (central ~45–55) ⇒ completion window **≈ 14:08–14:47Z, central ≈ 14:20–14:30Z**. A cap-imposed hard floor exists regardless of any disk/cache: **no busybox sha256 speed on this node finishes the pass in under ~20.3 min** (121,969,901,568 B ÷ (0.2 × 500 MB/s) = 1220 s). Nothing in the stack will abort it (no `activeDeadlineSeconds`; reloader `--reload-strategy=annotations` + zero reloader annotations; Application has NO `automated` syncPolicy ⇒ selfHeal moot) — the ONLY kill class is human action, and a kill restarts the hash at byte 0 (download resumes, hashing never does).

### D4.1 THE POD NOW — launch premise CONFIRMED

- Pod `gpu-ai-radiance-7b4b757fff-dnfbf`, uid `d2feb92f-1cad-409f-9ec6-ce411e933797`, ns `default`, node `ai-gpu`; `creationTimestamp 13:38:18Z`; **Scheduled event 13:38:47.746653Z** — the launch's "7b4b757fff-dnfbf scheduled 13:38:47Z" is exact. phase **Pending**; QoS **Guaranteed**; pod `metadata.annotations`: **absent**; **`activeDeadlineSeconds`: absent**; `terminationGracePeriodSeconds 180`; `restartPolicy Always`.
- It is the C11 roll: Deployment `gpu-ai-radiance` generation **2**, annotation `deployment.kubernetes.io/revision: "2"`, RS `7b4b757fff`; the live init command array embeds the corrected equality gate verbatim (`actual=$(sha256sum "$PACK" | cut -d' ' -f1)` → MISMATCH echo naming expected+actual → exit 1 → `touch "$MARKER"` → `echo "radiance staging: complete"`) — **C11 confirmed live in the pod spec** (also in the last-applied dump).
- `initContainerStatuses[0]` (radiance-fetch): `state.running.startedAt` **2026-11-13T13:38:48Z**; `ready: false`; `started: true`; **restartCount 0, `lastState: {}`** (never terminated — THE HEADLINE: init has run **25:48** at the 14:04:36Z probe, no `terminated`, no exitCode, no marker ⇒ **hashing, not yet complete**); image `docker.io/curlimages/curl@sha256:3fb7e13e5d17…` (same digest as the §D3b.1 ledger pin); resources `limits cpu 200m / memory 2Gi` (requests equal — the cap that bounds the pass); user uid/gid 65532, supplemental [486, 65532].
- `containerStatuses[0]` (serve `radiance`): `waiting.reason PodInitializing`, **`imageID: ""`** ⇒ the engine image `docker.io/stilldeadcode/radiance:1.17.0` pull has NOT started (kubelet pulls app containers only after all inits complete) — no startup-report capture line exists yet; its probes are not armed.
- Conditions: `PodScheduled True` 13:38:47Z; `Initialized False` reason ContainersNotInitialized "containers with incomplete status: [radiance-fetch]" 13:38:47Z; `Ready/ContainersReady False`; `PodReadyToStartContainers True` 13:38:48Z. Full event list: FailedScheduling ×2 (13:38:18/13:38:28 "Insufficient memory" — the ~29 s Recreate-handshake while the old pod's 64Gi request deallocated), Scheduled 13:38:47.746, AlreadyMountedVolume WARN (fsGroup 65532 vs GID 0 — same cosmetic as §D3.1), Pulled/Created/Started 13:38:48. **ZERO Killing/BackOff/OOM/Evict/FailedToPull.**
- Re-confirmation of §D3.2(b): Application `gpu-ai-radiance` `status.health = Degraded` `lastTransitionTime 13:48:19Z` — exactly 600 s after pod creation = the `progressDeadlineSeconds: 600` CONDITION firing through a healthy >10-min init; it paints the app red and kills nothing.

### D4.2 THE LOG — the correct silence

`pods_log -c radiance-fetch` (14:02 and 14:04:36Z, tail): header `radiance staging: fetch …`, then `** Resuming transfer from byte position 121969901568**` (pack complete — the resume no-op), the 1124 B redirect-stub rows, four zero-progress frames, **then nothing**. No MISMATCH, no `radiance staging: complete`, no `curl failed rc=`. This silence IS the running-hash signature: busybox sha256sum's compute form prints `printf("%s  %s  %s\n"…)` — one line, only at completion — no intermediate output exists to show. Serve-container log: N/A (not started, D4.1).

### D4.3 THE STORAGE REALITY

- Chain: pod volume `models` → PVC `default/llama-swap` (`storageClassName: local-path`, 500Gi requested = 500Gi capacity, RWO, Filesystem, **Bound**) → PV `pvc-e4f5adf3-fc6d-42a0-af93-e888bf0b5934` → `local.path` = **`/var/lib/rancher/k3s/storage/pvc-e4f5adf3-fc6d-42a0-af93-e888bf0b5934_default_llama-swap`**, `nodeAffinity` hostname In [ai-gpu], `persistentVolumeReclaimPolicy: Delete`. StorageClass `local-path`: provisioner **`rancher.io/local-path`** (k3s's bundled default add-on — annotation `owner-name: local-storage`, `is-default-class: true`), `volumeBindingMode: WaitForFirstConsumer`. Not hostPath, not emptyDir.
- Host filesystem (kubelet stats 14:02:22Z): `capacityBytes 996,981,866,496` (928.5 GiB), `availableBytes 325,669,113,856` (303.3 GiB free).
- Node `ai-gpu`: 32 CPUs amd64, `memory 131,151,328Ki` = **125.08 GiB**, ephemeral-storage 950,796Mi, swap 2,148,204,544 B, openSUSE Tumbleweed, kernel 7.3.0-1, containerd 2.3.4-k3s1, kubelet v1.36.5+k3s1.
- **Device class: NOT DETERMINABLE read-only — stated without guessing.** local-path is a plain host directory on the node's k3s storage filesystem; no PV/SC/Node/kubelet-stats object exposes the backing device's model or media (NVMe vs SATA vs HDD), and nodeInfo carries no CPU model either. It does not matter for this pass: D4.4 shows the demand is 30–70 MB/s and the io PSI is 0 — even the slowest credible class clears it 2–15×.

### D4.4 THE BOUND — measured regime is the CPU quota, and the arithmetic follows

- BusyBox software implementation (fetched live 14:03Z, `mirror/busybox@master coreutils/md5_sha1_sum.c`): the `sha256sum` applet dispatches `sha256_begin / sha256_hash / sha256_end` (libbb's table-driven C); the hot loop is single-threaded `while ((count = safe_read(src_fd, in_buf, BUFSZ)) > 0) update(&context, in_buf, count);`. **No SHA-NI/hardware SHA-2 path exists anywhere in the applet** (busybox's asm hooks are the SHA3 `SHA3_HW_ENDIANS` only); single thread, so the 200m quota throttles the WHOLE pass. (The same source re-grounds the §D3b grammar: applet usage `[-c[sw]]`, `getopt32("scwbt")` — no long options — and the two-space compute print C11 parses.)
- Measured ledger decides the regime: cumulative `usageCoreNanoSeconds 280,648,715,000` = 280.65 core·s at wall 1403 s ⇒ **exactly 0.2000 core from t0** (full quota ever since the ~2 s curl no-op); `usageNanoCores 200,974,597` pinned at the cap; PSI cpu avg60 57.76. Non-completion at 1403 s bounds per-core speed **S < ~435 MB/s**; the published busybox sha256 class is ~150–350 MB/s/core on modern x86.
- Envelope table (total = 113.593 GiB ÷ (0.2 × S)): S=150→**67.8 min** (done ≈14:47); 200→**50.8** (≈14:30); 250→**40.7** (≈14:19); 300→**33.9** (≈14:13); 350→**29.1** (≈14:08). Progress at probe: 34.5–69% hashed. Dominant regime: **CFS 200m quota — the disk never binds.**
- The counterfactuals that made "1–6 min" wrong: pure disk-bound at full feed — NVMe 1.5–3 GB/s ⇒ 63–127 s; SATA 0.5 GB/s ⇒ ~244 s; HDD 0.15 GB/s ⇒ ~813 s (13.5 min); and an UNthrottled single busybox core alone (S=150–350) ⇒ 8–23 min. All of them collapse against the quota: the pass supplies at most 0.2×S = **30–70 MB/s**, so even the HDD case leaves 540 s minimum and the cap extends it 4–5×. Runbook :394's "minutes-class" survives only stretched to "tens-of-minutes class".
- Page cache, with the node numbers: RAM 125.08 GiB; node working set ~16.6–17.4 GiB (metrics-server nodes_top 14:02Z: 17,362,232Ki; pod cpu-total 506.8m without radiance); cache headroom ≈ 105 GiB < 113.59 GiB ⇒ the file **cannot be fully resident** — the oldest-written (head) pages have likely been evicted and the pass re-reads some fraction from disk. **The cache helps the disk, not the wall clock**: demand ≤70 MB/s is already off the critical path (majorPageFaults 0, io PSI 0), so whether pages hit cache or platter, the throughput stays the quota's 0.2×S. The init cgroup itself: workingSet 4.1 MB, rss 274 KB vs 2Gi limit; container swap 0 — no memory class of risk.
- After the hash completes: `touch marker` + `radiance staging: complete` + exit 0 (~1 s), THEN the engine pull (`stilldeadcode/radiance:1.17.0`, IfNotPresent, not on-node yet) + the ~66 GiB load under the 180×10 s startupProbe — runbook steps 5–6, untouched by this section.

### D4.5 WHAT COULD ABORT IT — adjudicated from the objects

- **K8s deadline: none.** `activeDeadlineSeconds` absent in the live spec; no init-container timeout exists in the API; kubelet waits indefinitely; probes address only app containers (none running). progressDeadline fired (D4.1) — condition, not killer (§D3.2(b) law, now twice witnessed).
- **Eviction: structurally off the table.** The 113.6 GiB lives on the PVC (not ephemeral-storage); Guaranteed QoS; node MemoryPressure/DiskPressure/PIDPressure all False, Ready, heartbeat 14:00:42Z.
- **Stakater reloader: DENIED for this pod — triple defense, all verified live.** (i) The reloader deployment runs args `--log-level=info --reload-strategy=annotations` (read 14:06Z) — there is no global auto-watch. (ii) The radiance Deployment carries only `argocd.argoproj.io/tracking-id` + `deployment.kubernetes.io/revision` + `kubectl.kubernetes.io/last-applied-configuration` — **zero `reloader.stakater.com/*`** annotations, and the pod template + pod carry no annotations at all (the chart's deliberate values.yaml:199-202 posture, still true on the gen-2 roll). (iii) The pod references **no ConfigMap/Secret anywhere** (volumes = llama-swap PVC + emptyDir Memory `shm`; no envFrom). ⇒ **Editing the llama-swap/radiance peers ConfigMap during the hash cannot restart this pod** — the §D2.8.2 RS-flip mechanism has no hook here. (It can restart the llama-swap router if annotated there — irrelevant to the radiance pass.)
- **ArgoCD: cannot roll it unattended.** Application `gpu-ai-radiance` `spec.syncPolicy` = syncOptions only (`CreateNamespace=true`, `ServerSideApply=false`, `RespectIgnoreDifferences=true`) — **no `automated` block**, hence no auto-sync and no `selfHeal` (selfHeal exists only under `automated`). The runbook's "suspend selfHeal" is already structurally satisfied — there is nothing to suspend. The only apply since was the owner's manual sync 13:38:16Z (Succeeded, revision `de02e1884f42…`).
- **Residual kill list = human actions only**: (a) merge to main touching the radiance template + click Sync (Recreate rolls — exactly how THIS pod was born at 13:38); (b) delete pod / rollout restart; (c) node reboot or power loss. Any pod loss re-runs the pass from byte 0 — the design's resume covers the download (bytes intact on the PVC) but there is NO resume for hashing and NO marker until the pass ends — the elapsed 26+ min is thrown away whole. **THE ONE INSTRUCTION: touch nothing radiance-related — no merges/syncs of the radiance template, no pod delete, no node restart — until the log reads "radiance staging: complete" (expected ≈14:08–14:47Z).**

### D4.6 COMPARISON POINT — the records to correct (coord fold; runbook not edited here)

- Runbook `.agents/notes/radiance-on-target-acceptance.md:394-395` (quoted in §D3.7): the independent sha256sum re-check is "**a minutes-class full read** — run it only if the marker is doubted".
- §D3b.6 (EXPLORE.md:1195): "one full `sha256sum` pass … **~1–6 min, one time**" (via §D3.7's "~350 MB/s–2 GB/s" disk-bound framing); §D3.7 (EXPLORE.md:1062) even projected "~12:50Z expected" for the whole staging.
- **The live elapsed falsifies the §D3b.6 "1–6 min" outright** (25:48 at 14:04:36Z, STILL RUNNING — ≥4.3× the envelope's top) and stretches the runbook's "minutes-class" into the tens of minutes. Root cause of the miss, named plainly: both models priced the DISK at full-core single-thread speed and **ignored the chart's own init CPU limit `200m`** (values.yaml:349-360 — "200m/2Gi equal pair" was in §D3.3's own record and not multiplied into the estimate). Corrected wording for the fold: *"one full sha256sum pass under the 200m init cap ≈ 30–70 min (expected total ~45–55 min; hard floor ~20 min) — CPU-quota-bound, not disk-bound; every restart after completion is the marker-skip in <1 s; raise the init CPU limit if a faster first-hash is wanted."*

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md]
commands_run: [readonly-ai-gpu-kubernetes: pods_get gpu-ai-radiance-7b4b757fff-dnfbf default ×2, pods_list_in_namespace default, pods_log -c radiance-fetch ×3, events_list fieldSelector involvedObject.name=…, resources_get Deployment(gpu-ai-radiance/Application(gpu-ai-radiance/PVC(llama-swap/PV(pvc-e4f5adf3…/StorageClass(local-path/Node(ai-gpu/Deployment(gpu-ai-reloader-reloader), pods_top default, nodes_top, nodes_stats_summary ai-gpu ×2 => pass; repo greps: EXPLORE.md/plan/runbook quote locations => pass; webfetch mirror/busybox md5_sha1_sum.c @master (git.busybox.net + libbb/sha256.c paths 404) => pass; shell date/time arithmetic => pass]
deviations: none — read-only throughout; only the sanctioned EXPLORE.md append (§D4). Launch framing "1–6 min guess likely failed" — CONFIRMED failed, and refuted further than asked: the regime is not disk-class-at-all but CPU-quota-bound, so the storage device class (undeterminable read-only, reported as such) does not bound the answer.
friction: nodes_stats_summary full JSON exceeded the Code Mode result window twice (second call returned empty) — worked around by targeted string-window extraction across two calls; busybox raw mirror 404s on tag 1_36_1 and libbb/sha256.c path (same class as §D3b's note) — master coreutils/md5_sha1_sum.c fetched fine and carries the needed implementation evidence.
open_questions: none research-grade. For coord: (1) fold D4.6's corrected wording into the runbook/plan carriers (and §D3b.6) in the C11-era record round — the "1–6 min" sentence is now live-falsified with a measured counter-case; (2) a plan-side question worth ONE batched slot: raise `controllers.radiance` init resources from 200m/2Gi (e.g. to 1000m) so first-time cold staging hashes land in ~8–23 min instead of ~30–70 — cosmetic, not a defect; (3) owner line: DO NOT sync/delete/reboot anything radiance-related until "radiance staging: complete" (expected ≈14:08–14:47Z central ~14:20–14:30); a kill now restarts the 30–70 min pass from byte 0; after the marker lands, every restart is the <1 s marker-skip.
next_suggested: hold the ticket quiet until completion, then the AC6 receipt walk (marker + 65532:65532 + serve pull + engine boot under the 180×10 s startupProbe); fold §D4 into DECISIONS/plan wording corrections in the next doc round.

## §D6 — the planned memory figures (owner: '110 for gpu-ai and 64 for gpu') + two probe corrections (scout round 7)

*(Probes ~15:00–15:10Z 2026-11-13, readonly-ai-gpu-kubernetes + readonly-gpu-kubernetes only; repo reads; webfetches: man-pages 6.19 `statx(2)`, containerd CRI config docs. Launch framing tested, not assumed — and partially refuted below.)*

**VERDICT FIRST.** The owner's two numbers are REAL repo numbers wearing the wrong name-tags. `110` and `64` are the **strata pod's limit/request pair ON gpu-ai** — the owner's own 2026-11-10 envelope ruling ("the container must die BEFORE the node. 110Gi + the measured node floor ~7-8 GiB … fits the 125.1 GiB allocatable — 116Gi plus that floor did not", `charts/llama-swap/values.yaml:1319-1325`; requests verbatim `memory: 64Gi` at :1288-1290) — NOT a gpu-ai/gpu split, and never a radiance plan: **the literal 110 appears ZERO times in any radiance surface** (charts/radiance, services/gpu-ai, radiance runbook/tests, .rulesync — grep clean this round; `110592` is a strata engine-side MiB cap, not a pod number). What the repo DID plan for radiance: the owner's own Q10 words "60Gi class" (DECISIONS.md:138-139) → shipped 64 (D17) → documented ladder ceiling **96** (values.yaml:48, C12 AC1). "64 for gpu" has a second, independent repo carrier: the gpu cluster's box recorded as **64 GiB RAM** in four 2026-10 notes — and the LIVE gpu node refutes it at **28.60 GiB allocatable** (29,994,244Ki), so that spec record is drift and belongs to the owner to confirm, not to the chart. `64` never meant a radiance pod anywhere: radiance serves gpu-ai ONLY (`charts/radiance/values.yaml:96` "this chart serves gpu-ai only"; zero `radiance` keys in `services/gpu/prod/values.yaml`). **The arithmetic the owner's figure needs: 110 DOES fit gpu-ai** — `110 + router 4.125 + system floor 1.158 = 115.28 ≤ 125.08` (free 9.80 GiB) while strata is down, engine rule `110 − 71.04 printed = 38.96 ≫ 4` ✓, and it is the exact node-envelope arithmetic the owner ruled for strata on this same box; with strata up, 180.3 > 125.08 keeps the designed Pending handshake unchanged. What the owner actually set on the live pod: **limit 94Gi ONLY — requests stayed 64Gi** (Deployment gen 3 / rev "3", template `requests {memory: 64Gi}` + `limits {memory: 94Gi}`, pod `gpu-ai-radiance-849ddf8b66-wpc89` identical) ⇒ the manual bump **silently downgraded the pod from Guaranteed to Burstable** (`status.qosClass: "Burstable"`, live field) — D15's requests==laws broken out-of-band, exactly the drift class C12 AC6 says the sync overwrites. And the headline the framing did not expect: **the node REBOOTED at ~15:01Z** (event "Node ai-gpu has been rebooted, boot id: 69259d13-…"), and the fresh engine boot took new receipts: **LINK WARN REPRINTED under load** (retrain-vs-luck is CLOSED: not retrained), **memlock still 8.00 MiB**, **governor still powersave** — both §D6.3/D6.4 corrections below ride on that single fact.

### D6.1 REPO ARCHAEOLOGY — every planned/stated memory figure (quoted, file:line, cluster, number)

| # | source | verbatim (abridged) | cluster | asserts |
|---|---|---|---|---|
| 1 | `charts/llama-swap/values.yaml:1319-1325` + `:1340-1341` | "Why 110Gi (owner ruling 2026-11-10, supersedes U14's 116Gi): the container must die BEFORE the node. 110Gi + the measured node floor ~7-8 GiB (all non-strata workloads ~7.3 GiB…) … fits the 125.1 GiB allocatable — 116Gi plus that floor did not." | **gpu-ai** | STRATA limit **110Gi** — the owner's node-envelope law |
| 2 | `charts/llama-swap/values.yaml:1288-1290` + `:1334-1336` | `requests: {cpu: 8, memory: 64Gi}`; "requests stay 64Gi, so the scheduler can still pack a neighbour here" | **gpu-ai** | STRATA request **64Gi** |
| 3 | DECISIONS.md:99-103 (D12, 2026-11-11) | "the full profile (pool 43000/200K/**≈110Gi**) is the runbook's documented post-retirement ladder" | gpu-ai | radiance full-profile CLASS ≈110Gi — **the only ≈110 ever planned for radiance; superseded the SAME DAY by D17** |
| 4 | DECISIONS.md:138-139 + :151-157 (D17) | Q10 owner verbatim: "ship the FULL RESEARCH serving envelope (pool 43000 / **60Gi class** …)"; D17: "guaranteedMemoryGi 64 as the single scalar honoring the owner's '60Gi-class' … ladder UP (64→**96Gi**, schedulable only while strata is manually scaled down)" | gpu-ai | radiance PLANNED = 64 shipped, ceiling **96** |
| 5 | `charts/radiance/values.yaml:37-53` | "guaranteedMemoryGi = 64 … schedulable to ~96 only while strata is down"; `:281-285` requests==limits `64Gi` both maps | gpu-ai | shipped 64, ladder 96 — NO 110 anywhere in the chart |
| 6 | `chunks/C12.md:50-63` | "The shipped value: `guaranteedMemoryGi: 96` — D17's OWN documented ladder ceiling"; pair "96+64+6.3 > 125.08 / 96+6.3 ≤ 125.08 (~22.8 GiB free)" | gpu-ai | C12's AC1 target **96** |
| 7 | RESEARCH.md:690, :296-303, :723 | "host ~124 GiB (allocatable 125.08 GiB [S14]); pinned cap ≈ **120.6 GiB**"; "**fn-tp1-ram variant**: ngram `ram` (+47.7) → total pins ≈ **100–110 GiB**"; "42.0 pool + 47.7 table + snapshots 8.9 + embed ~1 + tier/arena + headroom ≈ **105–110 < 120.6** … only with everything else gone" | gpu-ai | the RAM-ngram-tier profile's ≈105–110 pin class — ≈110 is real, but as the RAM-TIER VARIANT footprint, not a shipped pod limit |
| 8 | RESEARCH.md:72 [S14] | "strata pod … workingSet 109.05 GiB of the 125.08 GiB node (110Gi container limit)" | gpu-ai | the 110 envelope witnessed live |
| 9 | `.agents/notes/radiance-on-target-acceptance.md:117, :189, :195, :359` | "Guaranteed 64Gi + strata's 64Gi REQUEST (its limits are 110Gi…)"; shipped scalars 64; step-1 names block "Strata … request 64Gi/8 cpu, limit 110Gi"; "The strata arenas drain and the ~110Gi working set releases" | gpu-ai | 110 in the cf-143 runbook = ALWAYS strata's |
| 10 | `services/gpu/prod/values.yaml:367-368` (+ golden `gpu.config.yaml:730`, evidence `flashnext-pre-chunk-baseline/gpu.config.yaml:845`) | "`--cache-ram` deliberately left at the 8 GiB default: ~32 GiB experts already resident in **this box's 64 GiB RAM**" | **gpu** | gpu box recorded as **64 GiB RAM** (2026-10 era) |
| 11 | `.agents/plans/2026-10-11-debug-gpu-moe-qwen36-35b-q8-vram-oom.md:38`; `2026-10-feat-llama-swap-config-generation/RESEARCH.md:83, :121` + FRICTION.md:13 + DECISIONS.md:47 | "Radeon 780M (gfx1102), **8 GiB VRAM, 64 GiB RAM**"; "gpu box (8 GiB VRAM / 64 GiB RAM)"; "64 GiB RAM = the lab's `gpu-moe` LLM provider" | gpu | same 64 GiB spec, four carriers |
| 12 | cf-141 EXPLORE.md:72 | "One pod, one cgroup **110Gi** on a **125.08 GiB** node (measured non-strata floor ~7–8 GiB)" | gpu-ai | the envelope law restated |
| 13 | cf-86 RESEARCH.md:235 | strata "cgroup **96Gi**/requests **64Gi**" | gpu-ai | 96 has STRATA provenance too (cf-86 era cap before 100/108/110/116 moves) |
| 14 | AGENTS.md, `.agents/loops/**`, `.rulesync/skills/pipeline-models/**` + `pipeline-kickoff/**` | grep for `110 / 64Gi / GiB-capacity` sizing prose: **zero node-memory statements** (the models skill's only radiance number is the favorites-table "~66 GiB load" class line, `.rulesync/skills/pipeline-models/SKILL.md` favorited row) | both | no catalog/kickoff planning figure exists |
| 15 | `charts/vllm/values.yaml:230-232` | vllm "requests 16Gi / limits 32Gi — the cap that keeps the 125Gi node undisturbed while Strata's pod coexists" | gpu-ai | retired-lane memory class; not 110/64 |
| 16 | `.agents/notes/strata-host-prep-gpu-ai.md:39, :115-118, :126-128` | host-prep row 0.12 "before §1.5 defaults are small; after, `1048576` / `infinity`"; the recorded drop-in: `printf '[Service]\nLimitNOFILE=1048576\nLimitMEMLOCK=infinity\n'` … "LimitMEMLOCK=infinity is the host half of DOCKER.md's `--ulimit memlock=-1:-1`: a strata arena page-locks ~47 GiB … a capped memlock fails the pin at load" | gpu-ai | the repo's OWN LimitMEMLOCK=infinity precedent (§1.5, strata era) — see D6.3 |

**Plainly:** there is NO repo plan of "radiance = 110 on gpu-ai, 64 on gpu". The 110/64 pair belongs to strata on gpu-ai; the radiance plan on record is 60-class → 64 → ceiling 96 (C12's 96 is the documented planning answer, receipt-anchored at 71.04+4+~21); the only radiance-flavoured ≈110s are D12's superseded class line and RESEARCH's RAM-tier variant footprint (105–110, "sole large tenant"). If the owner now rules 110 for radiance, they are EXTENDING their own 2026-11-10 node-envelope ruling to the new engine — arithmetically legal (D6.2), repo-wise new. And "64 for gpu" is not a pod plan at all — it is the gpu box's RECORDED spec, which the live node contradicts.

### D6.2 LIVE CAPACITY FACTS — both clusters (readonly reads @15:00-15:10Z)

**gpu-ai node `ai-gpu`** (resources_get Node, post-reboot): `memory` capacity = allocatable = **`131151320Ki`** = 125.08 GiB — re-verified against the recorded `131151328Ki` (§1 round 1, §D2.2): an **8 KiB wobble**, same displayed 125.08; the node's own MemTotal moves slightly across boots — cite this round's value for fresh arithmetic. Pools unchanged: `gpu-r9700-1: 1`, `gpu-8060s: 1`, bare `amd.com/gpu: "0"`; `cpu: 32`, `pods: 110`; MemoryPressure/Disk/PID False, Ready @15:01:18Z.

Currently resident (requests = what schedules):
- **strata Deployment `gpu-ai-llama-swap-strata`: `spec.replicas: 0`** (obsGen 47) — step 3 still in effect, its 64Gi request is OFF the node, pod gone from the namespace (same §D3.8 posture).
- **radiance pod `gpu-ai-radiance-849ddf8b66-wpc89`** (Running @15:03, created 15:01:14 after the reboot): serve container `requests {cpu: 8, memory: 64Gi, gpu-r9700-1: 1}` + `limits {cpu: 8, memory: 94Gi, gpu-r9700-1: 1}`; `allocatedResources.memory: 64Gi`; **`status.qosClass: Burstable`** — the owner's 94 is a LIMIT-ONLY hand-edit (rev "3", rolled 14:24:59Z per Deployment conditions), NOT a request+limit pair. Init `radiance-fetch` still `200m/2Gi` pair (C12's init-CPU knob has NOT landed). Serve container RUNNING, init terminated 0 (marker exists — C11 hash completed), first request served at **11.2 tok/s** (vs report-2's 5.1).
- router `gpu-ai-llama-swap` (6796d989db-lz4fd, Running): main requests `4Gi`+`gpu-8060s` (limit gpu-only), tools `128Mi` → effReq 4.125.
- system floor ≈ 1.158 (the §D2.4 alloy/reloader/coredns/mcp set, unchanged pods).

**The 110 arithmetic (the number the owner named):**
```
Guaranteed pair at 110, strata DOWN:   110 + 4.125 + 1.158 = 115.28 ≤ 125.08 → fits, 9.80 GiB scheduler headroom
Engine ≥4-GiB-free-under-cgroup:       110 − 71.04 (printed pinned, report 2) = 38.96 ≥ 4 → passes with margin
Owner's own node law (values:1319-1321): 110 + floor ~7.3 = ~117.3 ≤ 125.08 → the EXACT strata-era envelope, proven on this box
With strata UP (any variant):          110 + 64 + 6.3 = 180.3 > 125.08 → designed Pending — step-3 protocol UNCHANGED at 110
C12's 96 for comparison:               96 + 6.3 = 102.3 ≤ 125.08 (22.8 free); 96 − 71.04 = 24.96 ≥ 4 ✓ — both numbers are LEGAL; 110 buys +14 GiB prefill-burst headroom at the cost of 14 GiB less node-free
RAM-ngram-tier variant (D6.5):         71.04 + 47.68 = 118.72 > 110 (and > 96) → NO pod limit on this node can host it — see D6.5
```
**Strata at 110:** nothing changes about it — it is scaled down and its restore-back (runbook step 10) can never co-reside with a 110-request radiance (174 > 125.08 even ignoring the floor). The handshake inverts whichever number ships: whoever starts second sits Pending by design.

**gpu cluster node `gpu`** (readonly-gpu-kubernetes, resources_get): capacity = allocatable = `memory 29994244Ki` = **28.60 GiB**, `cpu: 13`, `amd.com/gpu: 1` (external single-naming 1.31.0.9 DaemonSet running), `pods: 110`, no swap entry in capacity; openSUSE Tumbleweed, kernel 7.3.0-1, k3s v1.36.5; systemUUID==machineID (VM/cloud-init signature — whether the k3s node is bare-metal or a VM on the 780M box is NOT determinable from these objects). `gpu-llama-swap-…-rd4cj` Running: main `requests {cpu: 1, memory: 4Gi, amd.com/gpu: 1}`, limits gpu-only — Burstable (the chart's 4Gi class, no memory cap).
**"64 for gpu" adjudication:** the live object does NOT prove a 64 GiB box — it proves **28.60 GiB allocatable with zero reservations subtracted** (capacity==allocatable, the same pattern as ai-gpu's proven 125.08=MemTotal). So "64" cannot be a pod limit there (a 64Gi request would never schedule; even the repo's own 2026-10 fit-tables sized gpu workloads against "8 GiB VRAM / 64 GiB RAM" — if the box is now 28.6, `services/gpu/prod/values.yaml:363-371`'s "~32 GiB experts resident" line is physically stale). The reframe the launch floated — "NODE memory for both clusters" — is HALF right: 110≈ the owner's usable-class figure for the gpu-ai node (their strata ruling) and 64 = their memory of the gpu box spec; but the gpu node object refutes the 64, and NO radiance pod was ever planned for gpu. **This is spec-drift for the owner to confirm (dimms pulled? VM capped? node rebuilt?), not a chart value.**

### D6.3 PROBE CORRECTION (a) — MEMLOCK: right process, right value, only route

**What the earlier probe got wrong:** `crictl inspectp <pod-sandbox-id>` reports the **pause/sandbox** process (pid in the paste showed `Max locked memory 16787369984`). That is NOT the radiance container. Observation worth recording: 16,787,369,984 B × 8 = 134,298,959,872 B = **exactly MemTotal/8** of the round-3 reading (131,151,328Ki) — a computed default of unknown origin (which unit/process computes it is NOT resolvable read-only; the paste's "containerd unit carries it" stands as the owner's evidence). Meanwhile the radiance ENGINE printed its own `getrlimit` from inside the container: **`RLIMIT_MEMLOCK is 8.00 MiB`** — reprinted by the fresh 15:01Z boot (this round's `pods_log -c radiance`, `note memlock-limited` line). The engine's own print IS the container's rlimit by definition — the host-side corroboration must read the CONTAINER's init, not the sandbox.

**Correct read-only method (owner's host lane, no exec):**
```bash
cid=$(crictl ps --name radiance -q | head -1)                      # the serve CONTAINER id (crictl ps, not inspectp)
pid=$(crictl inspect "$cid" | python3 -c 'import json,sys;print(json.load(sys.stdin)["info"]["pid"])')   # container init pid
grep -E 'Max locked memory|Max open files' /proc/$pid/limits        # what PID 1 inside the container — and the engine — sees
```
(The runbook already mandates the in-container twin of this: `grep -E 'Max locked memory|Max open files' /proc/1/limits` "post-boot re-read", `radiance-on-target-acceptance.md:155-157`.)

**What is a "good" value here:** the RAM n-gram tier pins the **47.68 GiB table** as locked host memory, so the container's rlimit must be effectively unbounded: **`LimitMEMLOCK=infinity`** — the upstream compose equivalent `--ulimit memlock=-1:-1` (RESEARCH RQ3 [S3 DOCKER.md]; the engine's own fix string at report line: "Docker: ulimits memlock -1; systemd: LimitMEMLOCK=infinity"). 8 MiB (current) is not enough and neither is 15.6 GiB. **Scope discipline (D28 law, re-cite):** memlock gates ONLY the RAM-ngram tier + io_uring ring headroom; the 71 GiB pool is driver-locked card-path memory, NOT ulimit-charged — do not oversell the drop-in.

**Can a pod get infinity while its runtime chain carries 15.6 GiB?** Not by asking: the observed split (sandbox 15.6 GiB / app container 8 MiB) proves the unit-level value does not reach this pod as-is; the mechanism that injects 8 MiB into CRI app containers is NOT distinguishable read-only and is honestly left open. What is settled, with sources:
1. **Kubernetes cannot set RLIMIT_MEMLOCK per pod/container.** There is no rlimit field anywhere in PodSpec; `securityContext` offers `capabilities` (the chart already ships `IPC_LOCK`, `charts/radiance/values.yaml:297-301`) and `sysctls`, and RLIMIT_MEMLOCK is not a sysctl at all (it is a per-process ulimit inherited from the runtime chain).
2. **containerd's CRI plugin has no `default_ulimits` knob** — the full config-key list (fetched upstream `docs/cri/config.md` this round, 2.x `version = 3` block) contains no ulimit/rlimit key; the OCI-spec escape (`base_runtime_spec`) exists but is documented as needing a containerd restart and is not a k3s-supported surface. ⇒ **the node-level route is the only one**: the repo's OWN precedent — `strata-host-prep-gpu-ai.md:115-118` writes the `[Service] LimitNOFILE=1048576 / LimitMEMLOCK=infinity` drop-in for **k3s.service**, re-read row 0.12 (:39), then `daemon-reload` + k3s restart ("to this inherited hard ceiling", :126-128). k3s hosts containerd, so the drop-in must land on the unit that owns the runtime; after any change the receipt is the D6.3 container-pid read above, because the sandbox-vs-container split shows unit values are not trustworthy proxies.
3. **Nuance the owner may exploit (kernel semantics, one line):** `CAP_IPC_LOCK` in the container's capability set bypasses RLIMIT_MEMLOCK for actual `mlock()` charges — so the pod COULD lock 47.68 GiB even at the printed 8 MiB. But the engine's tier gate reads the printed rlimit ("the memlock limit is one of the things that keeps --ngram-placement auto off it" — its own note, live), so the capability alone will NOT unlock the tier without an engine-behavior answer (does radiance `setrlimit` first? — no repo evidence either way; **open question**, engine-docs territory, not a scout verdict).
4. The restart tax: applying the drop-in restarts k3s ⇒ all pods on the node roll (the ~15:01Z reboot just demonstrated the blast radius: radiance + router pods recreated, strata untouched at 0). Schedule it inside a radiance-down window and mind the §D4.5 touch-quiet law (a pod loss mid-hash restarts the hash at byte 0 — moot now: the marker exists, every restart is the <1 s marker-skip).

### D6.4 PROBE CORRECTION (b) — GOVERNOR: boot snapshot + the reboot closes the loop

Owner's host paste §3: **all 32 CPUs `performance`/EPP `performance`, policy 2.00–5.19 GHz** (amd-pstate `performance` — the guide's "perf profile" host-checklist item, RESEARCH:679). Engine startup report: **`note cpu-governor: the CPU governor is powersave with energy preference balance_performance`** — and NOT only the 13:38Z boot the framing assumed: **the fresh `wpc89` boot at 15:01:14Z prints the same powersave line** (live log read this round). Adjudication:
- The engine's HARDWARE block is a **boot-time snapshot** (RESEARCH RQ3: the startup report "prints … memlock limits, cgroup limits and swap usage … `/diagnostics` re-reads live" — the governor line belongs to the boot snapshot, not a continuous read).
- The **events settle the timing**: "Node ai-gpu has been rebooted, boot id: 69259d13…" ~15:01Z. `cpupower frequency-set` / per-CPU writes do NOT survive reboot unless a persisting stack (tuned/tlp/systemd unit) re-applies them — exactly the clause C12 AC2.4 wrote ("governor persistence across reboot = tuned/tlp note"). So the most probable reading: **the owner set performance before the reboot; the reboot reverted the host to the platform default; the 15:01Z boot correctly printed powersave.** The alternative (owner set it AFTER 15:01 and the engine read is simply stale for later per-CPU changes) can't be excluded from the engine side alone.
- **Repo record of WHEN performance was set: none.** The ONLY governor/cpupower mentions in the whole repo are the C12 checklist plan (`chunks/C12.md:11, :126-130, :230`), one plan-file line (:1099), and STATE.json's D28 fold note (:573). No note/ticket logs the owner's act — their paste is the only evidence of the write.
- **Confirmation recipe (read-only, both sides):** on the host NOW: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c` and `…/energy_performance_preference | sort | uniq -c` (if these say performance at time T while the engine still printed powersave at boot 15:01, the discrepancy is pure snapshot-staleness). Final authority: the engine re-read = **restart the pod (owner action: delete pod or rollout restart — RECREATE strategy, marker-skip init <1 s) and re-read the startup-report line**; that is exactly what the 15:01 reboot already did once — the honest current receipt is `powersave` per the newest boot. If persistence is wanted, the fix belongs to the owner's tuned/tlp stack (C12's checklist lane), not the chart.

### D6.5 BTRFS / O_DIRECT — the engine's "no direct-I/O alignment" vs the owner's working dd

Owner paste §5 proves direct I/O **works** on this btrfs: `dd iflag=direct` 537 MB in 0.15688 s = **3.42 GB/s**; buffered 5.6 GB/s; WD_BLACK SN7100 (NVMe, ROTA=0, discard=async), subvol `/@/var`. Yet the engine (line reprinted on the 15:01 boot): "`libavx: /models/radiance/…rad: the filesystem reports no direct-I/O alignment, so the n-gram table is read in spans of its block size, 4096 bytes; a direct read of one returned the file's bytes`". Adjudication:
- **(ii) FIRST, because it decides (i) and (iii): this is NOT a probe failure — it is what the kernel reports on btrfs.** The statx(2) man page (fetched this round, man-pages 6.19, 2026-02-08): the direct-I/O alignment fields are `stx_dio_mem_align` / `stx_dio_offset_align` (STATX_DIOALIGN, Linux 6.1+), and *"The support on regular files varies by filesystem; **it is supported by ext4, f2fs, and xfs**"* — **btrfs is not in the list**; unsupported fields come back with the mask bit cleared and the field 0. `stx_dio_read_offset_align` is XFS-only (6.14+). btrfs cannot promise fixed extent alignment under CoW — so it honestly reports nothing; meanwhile plain `O_DIRECT` syscalls still work (the owner's dd: "a direct read of one returned the file's bytes" — the engine itself confirmed that). The two statements are consistent: **alignment UNREPORTED ≠ direct I/O broken**; the engine's 4 KiB-span fallback is conservative policy against an absent hint. Residual UNVERIFIED: whether any btrfs version beyond the man-page's list reports alignment — if the owner wants the kernel's current answer, the one-liner is below.
- **(i) the 5 GB/s gate:** the repo's own bar is `radiance-on-target-acceptance.md:173` (step-0(e) O_DIRECT row): *"the disk ngram tier REQUIRES an O_DIRECT-capable fs and the rig checklist wants ≥5 GB/s class — record the MB/s"* (same gate cited RESEARCH:425-426, 679). **3.42 GB/s IS BELOW the gate** — the gate's own wording makes this a RECORD result, not a hard blocker (the tier shipped and runs anyway, as observed: disk tier, spans mode). Honest caveat: 537 MB single-stream may under-read the drive's spec (~7 GB/s class) — a repeat with larger count /iodepth via `fio` would separate "btrfs tax" from "dd depth".
- **(iii) the REAL tier options with arithmetic** (base facts: node allocatable 125.08 GiB; printed host-side pins with disk tier = **71.04 GiB** report 2; n-gram table **47.68 GiB**; pool printed **42.70**; kv-resident mirror booked ≈**32**; engine rule ≥4 GiB free under cgroup):
  - **(b) RAM / `ram=DIR` n-gram tier: DEAD on this box with the shipped 8×200K profile.** 71.04 + 47.68 = **118.72 GiB pinned — exceeds EVERY candidate limit** (96: +22.7 over; 110: +8.7 over), and the ≥4 rule would demand a ≥122.7 GiB cgroup on a node that has 125.08 total and ~5.3 GiB of other requests — impossible; even bare `42.70 + 47.68 = 90.38` + arena/placement ≈ 93.6 leaves 2.4 GiB under a 96 cgroup (< 4, engine refuses) and the `ram=DIR` tmpfs mechanism is RESEARCH's two-engine shared-table lever with the `amdgpu.no_system_mem_limit=1` pin-twice trap (RQ1:199-202) — not this single-pod lane. Only the reduced profile WITHOUT the 32 GiB kv-resident mirror (pool+table+arena+placement ≈ 93.6) fits 110 — but dropping `--kv-resident` forfeits the 8-session lever the owner's goal rides on (RQ1:717-722). Show-don't-hide: **this option is a profile negotiation, never a scalar.**
  - **(a) move the pack to XFS/ext4:** makes statx report alignment ⇒ engine stops falling back to 4 KiB spans, and gives the ≥5 gate its best shot (XFS is the listed supporter). COST, stated plainly: the 113.6 GiB pack lives on the SHARED `llama-swap` 500Gi local-path claim whose host directory sits on `/@/var` (btrfs) — moving it means a second device/mount + repointing the local-path provisioner root or a new storage class — and the SAME claim carries llama.cpp models, strata staging and the vllm lane. That is a **host/storage-layout decision the owner owns** (a follow-up-card class, not a C12 chart value — local-path storage-path config is node-level; nothing in the chart can express it).
  - **(c) accept disk-tier 4 KiB spans (today's posture):** the cost envelope is RESEARCH's measured ngram ram-vs-disk delta **3–10% decode** ("≤10%, measure", :773-774 + bigcherry #512 10% / L1T 3%); at the new live 11.2 tok/s that is a 0.3–1.2 tok/s class cost — second-order against the LINK defect (below, worth ~2-4× prefill).
  - **(d) does `--ngram-placement` matter for decode at all?** RQ1:195-197: disk = "a host io_uring row cache (~85 MiB, O_DIRECT, ~half first-seen rows)" — per-token gathers are row lookups against that cache, not table streaming; the whole-table cross-link reads are the RAM tier's job (+12–40 s startup). The speculative-accept path makes it decode-side; the 3–10% band is the published bound; the fresh boot adds a second mover: "expert prefetch resting: the steps used 29% of its last 3528 copies, under the 30% that pays for them" — prefetch is IDLE, which is the HEAT-ENGINE family (C12 AC2.14), not the ngram tier. **Recommendation with numbers: stay (c) now; measure (a) only if the 3–10% band earns a device move after the link is fixed.**
  - Owner-side read-only measurements to settle this box's numbers: `python3` statx probe (the kernel's own answer for THIS file): `python3 -c "import os; st=os.stat('/var/lib/rancher/k3s/storage/<pvc-dir>/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad', follow_symlinks=False); r=os.listxattr(...)"` — plain `os.stat` does NOT expose dio fields; use the syscall: `ctypes`/`syscall` route or `xfs_io -c 'statx -m dioalign'` if installed. Simpler and sufficient (all read-only, owner lane): `sudo filefrag -v <pack> | head -20` (extent alignment), `sudo btrfs filesystem df <mount>`, `findmnt -T <pack path>` (fs type — C12 AC2.3's check), `strace -e trace=%file …` skipped as overkill, and the statx one-liner via `perl -MFcntl -e …`/`python3` `ctypes syscall(332=statx)` — the VALUE that matters is whether `stx_mask` carries `STATX_DIOALIGN` (0x00000800 — mark UNVERIFIED that btrfs 7.3.0 added it; man-page list says no as of 2026-02).

### D6.6 THE LINK — genuinely downgraded (the retrain-vs-luck clause is CLOSED by live evidence)

Owner paste §… now nails it: `00:00:03.1` root port **LnkCap 16GT/s x4 / LnkSta 8GT/s x4**; `c2:00.0` (switch upstream) **LnkCap 32GT/s x16 / LnkSta 8GT/s (downgraded) x4 (downgraded)**; boot line: *"31.504 Gb/s available PCIe bandwidth, limited by 8.0 GT/s PCIe x4 link at 0000:00:03.1 (capable of 504.112 Gb/s with 32.0 GT/s PCIe x16)"*. And the decisive NEW read (this round): the 15:01Z boot **reprinted the WARN under load** — `link-below-max: … runs 8.0 GT/s x4 of its 16.0 GT/s x4 while the card is 49% busy`. §D28/C12's open clause ("retrained-vs-the-check-didnt-fire are INDISTINGUISHABLE") is resolved: **NOT retrained — persistently Gen3 x4** (the report-2 silence was luck/state, exactly the alternative the clause allowed). Arithmetic: Gen3 x4 ≈ 3.94 GB/s raw; the root port's own ceiling Gen4 x4 ≈ 7.88.
- **What RESEARCH predicted for this box:** the TP1 one-card path was class'd at **OCuLink Gen4 x4 ≈ 7.0–7.2 GB/s measured** driving prefill **~454 tok/s @55k** (15 MB/token ÷ link rate — RESEARCH:263-271, :688; the "few hundred tok/s" guide estimate verified). The ~13.4 GB/s symmetric figure is the **TP2 two-card PEX-switch fabric class** (S19, RQ4:462-464) — a different path, NOT this card's host link. So **3.94 GB/s is HALF the planned class and is a defect-or-configuration state, not expected-here** — and it predicts the observed prefill signature (~142 ≈ half of the ~225 half-rate class, C12 AC2.1).
- **Width vs speed, stated precisely:** the **x4 width is physical here** — the root port's own `LnkCap` says `x4` (OCuLink/SFF-8611 carries 4 lanes; 504 Gb/s "capable" refers to the endpoint's x16 silicon, unreachable through a x4-cap port; the switch internals `c3:00.0/c4:00.0` at 32GT/s x16 prove the downstream is NOT the limiter). So "downgraded x4" on `c2:00.0` vs its own x16 cap is the cable/port doing its designed 4 lanes — NOT a fault. **The only defect candidate is the SPEED: Gen3 where the port caps Gen4.** Three causes distinguishable read-only: BIOS per-slot Link Speed pin, a Gen3-rated/degraded cable, or failed Gen4 equalization (training). The engine's own fix line already says: "a link stuck one level down after long uptime has been cleared by a reboot; … reseat or move the card if it trains narrow" — **the reboot did NOT clear it** (still 8GT/s post-reboot boot), which pushes toward BIOS-pin-or-cable over transient-stick.
- **Exact next read-only commands (owner lane):**
```bash
sudo lspci -vvv -s 00:00:03.1 | grep -E 'LnkCap:|LnkSta:|LnkCtl2|TargetSpeed'
sudo lspci -vvv -s 00:00:c2:00.0 | grep -E 'LnkCap:|LnkSta:|LnkCtl2|TargetSpeed|Slot'
cat /sys/bus/pci/devices/0000:c2:00.0/current_speed /sys/bus/pci/devices/0000:c2:00.0/current_width
sudo dmesg | grep -iE 'pci.*(8\.0|16\.0|32\.0) GT/s|link training|downgraded'
```
  **Adjudication rule:** `LnkCtl2: TargetSpeed=8.0 GT/s` ⇒ the platform/BIOS PINNED Gen3 → the fix is a BIOS slot-speed setting (Gen4/Auto). `TargetSpeed=16.0 GT/s` (or fastest) while `LnkSta` sits at 8.0 ⇒ Gen4 training FAILED on the electrical path → cable quality/length or reseat (the OCuLink cable must be Gen4-rated). dmesg repeated retrains/re-coveries is the flaky-cable signature. (A forced retrain — `setpci` LnkCtl Retrain bit or remove/rescan — is a WRITE; owner's lane only, never from the repo.) Keep C12's `/diagnostics`-under-long-prefill capture as the load-side receipt per AC2.1.

### D6.7 WHAT C12 AC1'S NUMBER SHOULD BE — recommendation with the sums shown

The repo's documented planning answer is **96** (D17 ladder ceiling, C12 receipt-anchored) — and the in-flight C12 test round has ALREADY re-pinned to 96 (working tree `radiance_testlib.py` SCALARS `"guaranteedMemoryGi": 96`, ~40 added 96-lines, RED-first, uncommitted as of probe). The owner's word — the one input that outranks any doc ceiling — says the plan was ~110, and **110 is arithmetically legal on this node and is the owner's OWN proven envelope for a big engine here** (strata's 110Gi ruling rode the identical 110+floor≤125.08 line; radiance at 110/110 Guaranteed: `110+4.125+1.158 = 115.28 ≤ 125.08`, 9.80 GiB free, engine rule `110−71.04 = 38.96 ≥ 4`). **Recommendation: ship `guaranteedMemoryGi: 110` IF the owner confirms in the batched question** (their sentence IS a ruling in flight; coord should spend one slot: "110/110 Guaranteed on gpu-ai, strata-down handshake restated as 110+64+6.3>125.08 / 110+6.3=116.3≤125.08 (9.8 free) — OK, or hold 96?"), because 110 strictly dominates 96 on headroom (prefill bursts, the prefix/ngram-tier negotiation) at zero scheduling cost — the strata-up Pending is the designed state either way. If the owner does not confirm, **96 stays shipped-plan** (receipt-anchored, documented, already tested). Consequences of the flip, enumerated for coord (all mechanical): C12 AC1/AC6 text 96→110; the red-first legs just written (testlib SCALARS, `test_ac2_guaranteed_pair*` 96Gi pair, `test_serve_args` arithmetic needles, `tests/notes/radiance-runbook.sh` 96-pair needles, TEST_SPEC §12.x) re-pin 96→110 with the new sums; runbook step-0(b)/step-3/step-6 arithmetic needles move from `96+64+6.3 / 96+6.3` to `110+64+6.3 / 110+6.3`; NOTES.txt:30 + values comment "schedulable to ~96" ladder sentences re-word. **For the gpu cluster: NOTHING to update** — no radiance surface exists there; instead file the node-spec drift (repo "64 GiB RAM" vs live 28.60 GiB allocatable) as an owner confirm + a docs follow-up card if the box really changed (it touches the 2026-10 llama-swap fit notes, NOT this chart).
And one honest correction to carry NOW regardless of 96-vs-110: the live pod is **Burstable (req 64 / lim 94)** because of the manual limit-only bump — the next sync rolls the repo pair and restores Guaranteed at whichever number lands; say it plainly in AC6's owner sentence (they will see 94→96/110 AND a QoS class flip back to Guaranteed in the same roll).

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md (this §D6 append only)]
commands_run: [readonly-ai-gpu-kubernetes: resources_get Node(ai-gpu) fresh KiB, pods_list_in_namespace default, resources_get Deployments radiance/strata/router, pods_get gpu-ai-radiance-849ddf8b66-wpc89 (resources/qos/allocated), pods_log -c radiance (fresh 15:01 startup report), events_list (Rebooted + radiance/router wave) => pass; readonly-gpu-kubernetes: resources_list Node, resources_get Node(gpu) (28.60 GiB), pods_list_in_namespace default, pods_get gpu-llama-swap rd4cj => pass; repo greps: guaranteedMemoryGi/110Gi/110 GiB/64Gi/125.08/memlock/cpupower+governor/O_DIRECT+GB/s/110-on-radiance-surfaces/96-diff-scan + full reads (radiance values 1-305, strata values 1259-1344, C12.md, C06.md hits, runbook step-0(d)/(e), RESEARCH RQ1/RQ3/RQ4/envelope, DECISIONS whole, pipeline-models SKILL whole, services/gpu values 270-354, gpu-ai radiance block) => pass; git log/status/diff (branch 9248151c9, main de02e1884, dirty C12 test round) => pass; webfetch man7 statx(2) (man-pages 6.19) + containerd docs/cri/config.md full key list => pass; ECONNREFUSED retry pass on readonly-ai-gpu-kubernetes (resolved — see friction)]
deviations: none — read-only cluster probes (readonly tiers only), no exec, no mutations; the only file written is this EXPLORE.md §D6. Launch framing refuted where the evidence demanded: (a) "110 for gpu-ai / 64 for gpu" is NOT a per-cluster radiance plan — 110/64 are the strata gpu-ai limit/request pair; the only radiance≈110 carriers are D12's superseded line and RESEARCH's RAM-tier variant; (b) "64 for gpu" as node memory is HALF-wrong: the repo DID record the gpu box at 64 GiB (four 2026-10 notes + a live values comment), but the node object reports 28.60 GiB allocatable — spec drift, owner to confirm; (c) the owner's manual bump is LIMIT-ONLY 94Gi (request stayed 64Gi) — not a 94 pair — and silently degraded the pod to Burstable; (d) the governor discrepancy is not just boot-snapshot staleness — the node REBOOTED ~15:01Z and the fresh boot still printed powersave, so non-persistence across reboot is the live explanation.
friction: readonly-ai-gpu-kubernetes returned ECONNREFUSED for ~3 min at probe start — caused by the very node reboot this section records (the MCP proxy pod was re-coming-up); survived retries, everything resolved, and the outage is itself evidence. `search` is only callable inside execute's runtime, not as a top-level tool — used it as such after one failed guess. statx via python os.stat does not expose the dio-alignment fields (needs the raw syscall) — owner command kept to filefrag/findmnt + the man-page list as the authority instead.
open_questions: [Owner ruling owed (batched round, ONE slot): confirm guaranteedMemoryGi = 110 (their words; arithmetic legal, sums in D6.7) vs holding C12's documented 96 — and note the in-flight test round is already pinned at 96, so the flip is a same-wave re-pin list (D6.7). Owner/host: confirm the gpu box's real RAM (repo 64 GiB notes vs live 28.60 GiB allocatable — if it moved, the 2026-10 gpu fit-notes + `services/gpu/prod/values.yaml:363-371` comment are stale → docs follow-up card). Owner/host: does radiance honor CAP_IPC_LOCK over the printed RLIMIT for the RAM ngram tier (engine behavior — moot until the limit question resolves since D6.5 kills the RAM tier arithmetically anyway). Not research-grade: the LnkCtl2 TargetSpeed read (D6.6) decides BIOS-pin-vs-cable without any web work.]
next_suggested: coord: ask the ONE batched memory question (110 vs 96) BEFORE the C12 dev round consumes the 96-pinned tests; tell the owner the live 94 bump degraded QoS to Burstable (the sync repairs it either way), that the LINK WARN reprinted post-reboot (fix the link first — it is worth 2-4× prefill, the ngram spans 3-10%), that memlock/governor both need node-lane persistence (the §1.5 LimitMEMLOCK drop-in precedent + tuned/tlp for the governor) with the corrected crictl-ps container-pid read as the receipt, and that the gpu box spec (28.6 vs 64 GiB) is theirs to settle.

## §D7 — is gpu-ai-radiance selfHeal-moot or selfHeal-live? (§D4 vs C12 review r2 contradiction)

*(Scout round 8, probes 16:30–16:44:45Z 2026-11-13, readonly-ai-gpu-kubernetes + readonly-gpu-kubernetes + repo reads + git. Launch: settle the §D4-vs-r2 contradiction, fast and decisive.)*

**VERDICT FIRST: §D4 was RIGHT on the live fact; C12 review r2 (MINOR-R2-1) was WRONG on the live fact — in terms the runbook edit can quote: the sentence “the Applications sync automated with `selfHeal: true`, so an un-guarded manual scale reverts at the next sync” (`radiance-on-target-acceptance.md:360-361`) is FALSE of the live gpu-ai stack: every Application in it — `gpu-ai-radiance`, `gpu-ai-llama-swap`, and all siblings plus the parent `gpu-ai` app — carries `spec.syncPolicy` WITHOUT any `automated` block (re-verified this round at 16:30–16:44Z, §D4's identical read at ~14:04Z stands), so there is no auto-sync and no selfHeal to suspend anywhere on gpu-ai.** r2's error is visible in its own words: “**Verified in-repo** … no selfHeal=false annotation is set anywhere **in `services/` or `custom-values/`**” (`chunks/C12.md:654-664`) — the repo proves only what the template *defaults to*, and the template's own comment (`appset-charts.yaml:126-129`) says the override knob is a **cluster-registration annotation**, which is not a repo file and which the gpu-ai registration has in fact set to non-"true" (inference closed below). BUT the contradiction's survivor is not "no hazard": the resurrection class r2 feared is REAL with a corrected trigger — **any sync (manual included) re-applies git's values over hand-edits**, proven today by the owner's own click: the 16:29:51Z manual sync of `gpu-ai-radiance` applied the C12 pair and WIPED the owner's hand-edited 94 Gi limit (§D6.7's predicted roll, now witnessed). So: §D4's “suspend selfHeal is structurally moot” — TRUE as written (nothing to suspend); r2's “wants step 10 to carry a suspend guard” — right to add a guard, wrong about which guard. The fold must REPLACE the UI-suspend idiom with the DON'T-SYNC idiom (D7.4).

### D7.1 LIVE OBJECTS — both apps, read-only, this round (readonly-ai-gpu-kubernetes, ns `default`, ArgoCD runs on ai-gpu itself)

- **Application `gpu-ai-radiance`** (ns default; created **2026-11-13T01:51:48Z**, generation **342**, resourceVersion 4983868; ownerRefs = [`ApplicationSet/gpu-ai-charts-appset`] — appset-generated):
  - `spec.syncPolicy` VERBATIM: `{"syncOptions":["CreateNamespace=true","ServerSideApply=false","RespectIgnoreDifferences=true"]}` — **NO `automated` key** (and no `retry`).
  - `status.sync`: **Synced**, `revisions: [eaaba4197dea74c9db77c678231ceab047a11c6c ×2]` — the app is ON C12 main right now.
  - `status.health`: **Healthy**, lastTransitionTime **2026-11-13T16:30:13Z**.
  - `status.operationState`: phase **Succeeded**, startedAt **2026-11-13T16:29:51Z**, `operation.initiatedBy.username = "tms@spencerslab.com"` — **MANUAL** (an automated sync would read `initiatedBy: {username: "automation"}`).
  - Its Deployment (apps/v1) NOW: `spec.replicas: 1`, generation **4**, template `requests.memory: 110Gi` + `limits.memory: 110Gi` + init cpu `1/1` pair + init mem 2Gi, strategy **Recreate** — the 110/110 Guaranteed pair LIVE, which also means the sync **replaced the owner's hand-edit (req 64/lim 94, Burstable — §D6.7) with git's values at 16:29:51Z**. This is today's own object-witness that on this stack *sync = git re-applied over manual drift*, exactly the mechanism §D6.7 forecast.
- **Application `gpu-ai-llama-swap`** (created 2026-10-07T23:06:28Z, generation 16953; same ownerRef):
  - `spec.syncPolicy` VERBATIM: `{"syncOptions":["CreateNamespace=true","ServerSideApply=false","RespectIgnoreDifferences=true"]}` — again **NO `automated`**.
  - `status.sync`: **OutOfSync** against `eaaba4197` (target) — and it has been sitting OutOfSync for many minutes at probe time. **If automated+selfHeal existed, ArgoCD would have synced it by itself; it has not.** `status.health` Healthy @ 13:38:47Z; last `operationState` Succeeded **13:38:15Z, initiatedBy tms@spencerslab.com (manual)**.
  - Its strata child Deployment `gpu-ai-llama-swap-strata`: **`spec.replicas: 0`** (generation 47) — the owner's step-3 scale-down is STILL holding at 16:44Z because nothing auto-syncs.
- **ApplicationSet template check (the rendered truth, since children are generated):** the LIVE `gpu-ai-charts-appset` CR (ns default, created 2026-10-07T23:06:28Z, generation 37, conditions ResourcesUpToDate) has `spec.template.spec` **without any syncPolicy** — all sync policy arrives via `spec.templatePatch`, whose STORED text contains the block verbatim: `{{- $serviceSelfHeal := index .metadata.annotations (printf "services.%s.selfHeal" .serviceName) | default "true" }} … {{- if eq $appSelfHeal "true" }} automated: {prune: true, selfHeal: true} {{- end }} syncOptions: … ServerSideApply={{ .ServerSideApply }} …` — **and the children prove the patch rendered** (syncOptions present, per-app ServerSideApply values correct: `false` on radiance/llama-swap, `true` on amd-gpu/k8s-monitoring/ESB/reloader) while the `automated` branch was skipped for EVERY child.
- **Fleet census (why “default true” cannot explain the objects):** six children sampled — `gpu-ai-radiance`, `gpu-ai-llama-swap`, `gpu-ai-amd-gpu`, `gpu-ai-k8s-monitoring`, `gpu-ai-external-secrets-bitwarden`, `gpu-ai-reloader` — **0/6 have `automated`**; plus the PARENT `gpu-ai` Application (from `services/gpu-ai/prod/templates/appset.yaml`, whose :135 gate reads the same `services.gpu-ai.selfHeal` annotation) also has **no `automated`** (its syncOptions shape `[CreateNamespace=true, ServerSideApply=true]` is that file's own rendering). Control read on the gpu cluster: `gpu-llama-swap` Application — likewise **no `automated`** (read this round; the 2026-10-20 selfHeal-churn incident notes prove it DID have automated then, so the registration posture changed at some later, out-of-git moment).
- **The annotation itself is not readable by me (RBAC), and that is honestly part of the evidence chain:** `kubernetes-mcp-readonly` cannot list/get Secrets in `argocd` (forbidden — cluster-registration secrets live there). The inference is nonetheless closed by elimination: the stored patch emits `automated` **iff** `$appSelfHeal == "true"`; a MISSING annotation key yields `"true"` via `default "true"` → `automated` present; the observed children have the patch's syncOptions but no `automated` → the key is present on the gpu-ai cluster registration with a value **other than "true"** (the lab's own documented idiom, `services.gpu-ai.selfHeal="false"` per the template comment :130-131). No surviving alternative: the patch demonstrably rendered, and an appset-managed app's spec is rewritten from the patch each reconcile (radiance generation 342 IS that churn), so a UI “pause” click could not be the explanation either — appset would re-add what the template emits.

### D7.2 REPO SOURCE — what the generator actually emits (file:line)

- `charts/base/templates/appset-charts.yaml:124` — every child gets a `syncPolicy:` block; **:132** `$serviceSelfHeal := index .metadata.annotations (printf "services.%s.selfHeal" .serviceName) | default "true"`; **:133** app-specific `services.{svc}.{app}.selfHeal` overrides service-wide; **:134-138** `automated: {prune: true, selfHeal: true}` emitted ONLY when the resolved value equals `"true"`; **:139-143** syncOptions always (`CreateNamespace=true`, `ServerSideApply={{ .ServerSideApply }}`, `RespectIgnoreDifferences=true`). selfHeal is therefore **templated with a default-true gate** — repo-wise r2's :132-138 quote is accurate; the live render says the gate answered false.
- Parent layer `services/gpu-ai/prod/templates/appset.yaml:135-138` — same key, same default-true shape, and the live parent Application likewise lacks `automated` → one cluster annotation explains the whole gpu-ai service at both layers.
- The annotation is **by design not in git**: :125-131 comments say “Configuration via cluster annotations” — i.e., set on the ArgoCD cluster-registration secret (ai-gpu's `argocd` ns, RBAC-closed to scouts; repo-wide grep: ZERO manifests with `argocd.argoproj.io/secret-type` — cluster registration is out-of-band by house style, cf. `charts/base/values.yaml:146` "tokens minted per-cluster out-of-band"). r2's “no selfHeal=false annotation is set anywhere in `services/` or `custom-values/`” is TRUE OF THE REPO and IRRELEVANT — the knob does not live in the repo. The same grep is why the values-side comments believing in live selfHeal (`services/gpu-ai/prod/values.yaml:40-41`, cf-77 era 2026-10-29) predate/never checked the registration: prose inference, not observation.
- No per-application `ignoreDifferences` exists that would shield hand-scales: live `spec.ignoreDifferences` = `[]` on both apps; the fleet-wide cmp customizations `charts/base/values.yaml:116-121` cover only `.spec.template.spec.hostUsers`, reloader annotations, argocd selector/label noise — **`/spec/replicas` is NOT ignored**, so a hand scale DOES show as OutOfSync drift (exactly what `gpu-ai-llama-swap` displays now) and WOULD be reverted by any sync that does run. `RespectIgnoreDifferences=true` in syncOptions is a carrier for the Plan-status rule (:140-142), not a replicas shield.
- Git value that a llama-swap sync would restore: **`replicas: 1` for strata** — grep evidence: ZERO `replicas:` keys in `charts/llama-swap/values.yaml`, in `services/gpu-ai/prod/values.yaml`, and in `custom-values/gpu-ai/prod-values.yaml`; the rendered value is the vendored `app-template-5.0.1` controller default 1 (`charts/llama-swap/charts/app-template-5.0.1.tgz`, `app-template/charts/common/templates/classes/_deployment.tpl`), witnessed live: `charts/radiance/values.yaml` likewise has ZERO `replicas:` yet the rendered radiance Deployment says `replicas: 1`. Same law holds for a radiance scale-down: git renders 1, so any sync of `gpu-ai-radiance` resurrects it at 110/110.

### D7.3 RECONCILIATION — which record was wrong, and why it read that way

- **§D4 (round 6, live reads ~13:38–14:06Z): CORRECT, and independently re-verified this round at 16:30–16:44:45Z** — no `automated` at either time; nothing changed in between. Its sentence (EXPLORE.md:1253) even quoted the exact syncOptions list that this round re-quoted byte-for-byte from the live object.
- **r2 (round 2, `chunks/C12.md:654-675`, STATE.json:574 stamps it at 2026-11-13T17:10:00Z): WRONG about the live state** — it never read an Application object (its own bar line says “no cluster action”); it derived behavior from the repo template's default-true gate and then searched for the override in the wrong namespace of truth (`services/` + `custom-values/`, where the annotation can never appear). Classic shape: template-default reasoning masquerading as object verification. The parenthetical “(verified appset-charts.yaml:132-138…)” verifies the EMITTER, not the EMITTED value; the live gate answer came back `false` for all 7 gpu-ai apps, and the OutOfSync-then-nothing-synced posture plus the manual-initiatedBy on every recorded operation independently corroborate.
- Not a staleness/timing story: both records are about the same objects, minutes apart, in one unbroken no-`automated` state. The state flip itself (auto-sync on → off, if it ever was on for gpu-ai) is UN-PINNABLE read-only: the repo's last beliefs (:40-41 of 2026-10-29; runbook :360 fold) all predate any live Application read in this ticket's records; §D4 is the FIRST live read on record, and it said “absent” from the start.
- The runbook sentence r2 *upheld* (:360-361) is the true error source — it asserted the fleet behavior from the same repo-only inference when it was written, and r2 then graded step 10 against that false law instead of against the objects. **For the fold: §D4's “that runbook step is structurally moot” is the quotable live-truth; but pair it with the witnessed counter-law — “no selfHeal resurrects you; a SYNC does, and on gpu-ai every sync is a human click” (16:29:51Z proved it on the 94 edit).**

### D7.4 CONSEQUENCE FOR THE PROSE — decision-ready answers

1. **Step 3's “suspend selfHeal” (runbook :361-363): MOOT — and WRONG AS WRITTEN.** There is no automated sync policy on `gpu-ai-llama-swap` to suspend (live, twice), so the UI step has no button to press; worse, the sentence teaches a false law (“reverts at the next sync” ⇒ self-acting). Replace with the true guard: *“gpu-ai Applications do not auto-sync (the cluster registration carries the appset's `services.<scope>.selfHeal` override — `appset-charts.yaml:132-138` gate; live-verified §D7); your scale-down sticks across reconciliations. It does NOT survive a sync of `gpu-ai-llama-swap` — git renders `replicas: 1` (no `replicas:` key anywhere in llama-swap values/custom-values) — so **do not sync that Application while strata must stay down**; the app will read OutOfSync all through the window, and that red-ish state is EXPECTED, not something to fix with a Sync click.”*
2. **Step 10's radiance scale-down — does r2's MINOR-R2-1 clause get adopted? YES-as-concern, NO-as-wording.** r2 was right that the offered human lane needs a written guard, wrong that it is a suspend: `gpu-ai-radiance` has no `automated` either (live), so “suspend auto-sync for gpu-ai-radiance first” would have the owner chasing a button that governs nothing. The correct parallel clause: *“the scale-down sticks until `gpu-ai-radiance` is next synced — **sync nothing radiance-owned while it must stay at 0**; a later sync resurrects it at 110/110 Guaranteed (Recreate) — the 16:29:51Z sync already demonstrated sync-overwrites-hand-edits by replacing the 94 limit with git's pair. The durable route remains step 11(i) (git change), as r2 said.”* The :690-691 “resume auto-sync (the step-3 suspend's counterpart)” sentence must go with the step-3 sentence — there is nothing to resume.
3. **Correct repo-supported shapes — use the lab's OWN live idiom, invent nothing:** the proven mechanism that keeps hand scale-downs sticky here is already fully deployed: the **cluster-registration annotation** the template itself documents (`appset-charts.yaml:125-133`: `services.{serviceName}[.{appName}].selfHeal` set non-"true" — observably the state of gpu-ai's registration today; the same posture on the gpu cluster's one control app read). NO repo precedent exists for the other floated shapes: no `argocd app set --sync-policy none` / UI-pause record anywhere in `.agents/notes` (the only mentions are the runbook's now-falsified :361/:690 sentences), no replicas compare-options/ignoreDifferences (the fleet cmp customization at `charts/base/values.yaml:116-121` deliberately omits `/spec/replicas`, and the gpu-ai apps' `spec.ignoreDifferences` are `[]`), and the ApplicationSet-controller pause is not a shape this repo uses. For PERMANENT disable the lab's idiom is the **vllm pattern**: out-of-band `replicas 0` + commenting the `charts:` entry “to make the disable declarative” (`services/gpu-ai/prod/values.yaml:35-41`) — but Q10 rules strata/radiance scale-downs OUT-of-band by design, so the procedural “don't sync the owning app” guard of (1)/(2) is the whole answer; deliberately leaving the app OutOfSync visible is the drift alarm.
4. **C12 mid-round landing (main == origin/main == eaaba4197) — interaction ADJUDICATED, and partly already EXECUTED:** the pair sync did NOT resurrect strata, because the owner has NOT synced `gpu-ai-llama-swap` — its last operation is the **13:38:15Z manual** sync and it now sits **OutOfSync vs eaaba4197**; C12's landing touched ONLY radiance-rendering files (`git diff de02e1884..eaaba4197 --stat -- charts/ services/`: `charts/radiance/{values.yaml,NOTES.txt,tests/*}` + `charts/llama-swap/tests/TEST_SPEC.md` — no render-affecting llama-swap/services change), so that OutOfSync marker IS the strata `replicas: 0` drift (git target 1). What the owner DID sync is `gpu-ai-radiance` at **16:29:51Z** (manual, Succeeded): `replicas: 1`, gen 4, **110Gi req/110Gi lim pair live, Burstable 94 gone, Guaranteed restored, pod Ready, Health Healthy @ 16:30:13Z** — §D6.7's forecast confirmed by the objects themselves; the hash pass is not re-running (marker exists, init <1 s skip). **Before merging more, the owner's ordering: (a) do NOT click Sync on `gpu-ai-llama-swap` until step 10's restore is intended (a sync now re-applies `replicas: 1` and reschedules strata — which at 110+64 > 125.08 would sit Pending with priority-10 preemption pressure against the live radiance, D17's class); (b) at step 10, scaling strata back to 1 via kubectl first and THEN syncing the app is self-consistent (git and live agree on 1 — the sync clears the standing OutOfSync honestly); (c) the visible OutOfSync of `gpu-ai-llama-swap` throughout the test window is the designed state under the don't-sync law, not a defect; (d) future merges touching `charts/llama-swap` values stay harmless by themselves — harm only arrives at the click.**

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md (this §D7 append only)]
commands_run: [readonly-ai-gpu-kubernetes: resources_get Application(gpu-ai-radiance, gpu-ai-llama-swap, gpu-ai-amd-gpu, gpu-ai-k8s-monitoring, gpu-ai-external-secrets-bitwarden, gpu-ai-reloader, gpu-ai) ns default, resources_get ApplicationSet(gpu-ai-charts-appset) argocd→404/default→OK, resources_get Deployment(gpu-ai-radiance, gpu-ai-llama-swap-strata), Secret get ×3 names in argocd => FORBIDDEN (RBAC, recorded as the evidence gap) => pass-with-documented-denial; readonly-gpu-kubernetes: resources_get Application(gpu-llama-swap) => pass; repo reads: appset-charts.yaml whole, services/gpu-ai/prod/{templates/appset.yaml,values.yaml}, charts/base/values.yaml:104-148, runbook :340-380/:669-712, C12.md r2 records, EXPLORE.md §D4/§D6; greps: selfHeal repo-wide, replicas values-files (0 hits), secret-type (0 hits), suspend/paused/auto-sync in notes => pass; git: log -S selfHeal/-–follow appset-charts.yaml (gate original d92c129c7 2025-10-09), diff de02e1884..eaaba4197 --stat charts/ services/, tar -O app-template tgz, log/status => pass; shell date -u (16:44:45Z) => pass]
deviations: none — read-only throughout (readonly tiers only, no exec, no mutations); only EXPLORE.md written. One launch premise corrected rather than assumed: it framed the 110 pair as “about to sync” — the owner already synced gpu-ai-radiance manually at 16:29:51Z (objects prove it; §D7.4(4) restates the window from the live state).
friction: argocd-ns Secrets RBAC-forbidden to the readonly SA (cluster-registration annotations unreadable — the mechanism proof degrades to an elimination-inference from the rendered children; the rendered result itself is directly observed, so the verdict is unaffected). pods_list_in_namespace takes only a continue token (no namespace arg) — worked around with Deployment-level receipts (replicas/gen/template), which carry the same proof. helm template of llama-swap with the service values returned nothing renderable offline (values shape needs the full appset overlay) — used the zero-`replicas`-keys grep + the live rendered Deployments as the replicas-1 proof instead.
open_questions: none research-grade. For coord (prose fold): (1) runbook step 3 :358-366 — REPLACE the “suspend selfHeal / reverts at the next sync” sentence with the D7.4(1) don't-sync guard text (§D7.3 wording is quotable: no automated block live, twice, on all 7 gpu-ai apps); (2) step 10 :676-691 — adopt r2's guard INTENT with corrected mechanism (D7.4(2)) and DELETE the “resume auto-sync” counterpart clause; (3) runbook :360's “ground truth, charts/base/templates/appset-charts.yaml” attribution must change to “live Application read §D7” — repo templates are defaults, the gpu-ai cluster registration overrides the knob, and the registration is out-of-band (RBAC-closed); (4) note for the fleet docs: the vllm resurrection comment (services/gpu-ai/prod/values.yaml:40-41) and the gpu-cluster 2026-10-20 selfHeal incident prose now CONTRADICT today's reads fleet-wide — worth one follow-up card to re-verify the selfHeal posture per cluster and correct the comments, not this ticket's lane.
next_suggested: coord folds D7.4(1)/(2) into the runbook edit (owner-facing prose that decides whether a hand scale-down sticks — now with the right mechanism named), treats MINOR-R2-1 as SUPERSEDED-BY-OBJECTS with its guard preserved, and closes the §D4-vs-r2 contradiction with this section as the record of authority.

## §D8 — post-110 performance: what is binding, quantified (scout round 9)

*(Probes 17:24–17:35Z 2026-11-13, readonly-ai-gpu-kubernetes + readonly-global-grafana + repo reads + webfetch of the pinned upstream docs (codeberg StillDeadcode/radiance @v1.17.0: GUIDE.md, spec.md, core/place/heat.h, docs/PREPARING_YOUR_RIG.md) + the router's own /v1/models read. Owner report being adjudicated: deployed the 110 GiB pair, "still shit performance". Launch framing tested — and refuted in three places below.)*

**VERDICT FIRST: the 110 GiB pair was a CORRECTNESS fix that provably cannot change the rate — the live boot reprints `pinned by this process 71.04 GiB` byte-identical to the 94-cgroup boot (the reservations are eager, R8-Q1's boot-A proof), so "still shit performance at 110" is the designed outcome, not a surprise. The ceiling is the PCIe link at `00:03.1`: still `8.0 GT/s x4 of its 16.0 GT/s x4` (3.94 GB/s), re-printed by the engine's own HARDWARE block at 17:20:25Z while the card sat 50% busy — it has NOT retrained across the 15:01Z reboot, the 16:29:51Z roll or the 17:20:05Z restart. The four decode receipts on record (5.1 / 12.4 / 19.3 / 12.4 t/s) fit ONE arithmetic model with a single free parameter — miss-stream bytes per decoded token crossing that link — and 19.3 t/s is NOT explainable by the link ALONE: a fully-miss decode token is 48 routed layers × 10 experts × 2.42 MiB = ~1.13 GiB → 3.2 t/s is the all-miss ceiling; the observed 19.3 implies ~17% of routings miss (~200 MiB/token → link ceiling 19–20 t/s, which the observation sits ON). The knob is therefore miss-stream ÷ link-bandwidth: fix the link speed (BIOS slot Gen4 or cable) and BOTH legs move ~2× — prefill 249→~450–500 tok/s (the docs' measured Gen4-x4 class is 454 @55k) and single-stream decode ~19→~30–40 t/s, converging on the published x16-class 35 t/s floor (29.0/28.0 ms steps). Second knob, smaller and not chart-reachable: the heat/prefetch engine has NO knob we ship and NO warmup requirement (source: `warmup_dispatches = 0`, `--deterministic` not set) — its live counters must be read under the fixed probe before any `--placement` thought; and the visible APU costs nothing today (own root port, `not serving`, router reports EVERY model `unloaded`).**

### D8.1 THE CURRENT POD — live objects (readonly-ai-gpu-kubernetes, 17:24–17:35Z)

- Pod `gpu-ai-radiance-5f7d6b95d7-4fccz`, uid `3d90f54d-9c4d-422f-8980-8e56a97fd470`, ns `default`, node `ai-gpu`, `creationTimestamp 2026-11-13T17:20:05Z`, phase Running, **`status.qosClass: Guaranteed`**, `allocatedResources {memory: 110Gi, cpu: 8, amd.com/gpu-r9700-1: 1}` — the launch's expectation **CONFIRMED: requests==limits==110Gi** (`spec.containers[radiance].resources` pairs identical, Deployment gen 4 / rev "4", strategy Recreate). Init `radiance-fetch` `1/1` CPU pair + 2Gi (C12's init-CPU knob IS live): `state.terminated {exitCode: 0, reason: Completed, startedAt: 17:20:05, finishedAt: 17:20:05}` — **marker-skip, <1 s, restartCount 0**. Serve container `radiance` (imageID `docker.io/stilldeadcode/radiance@sha256:c2acbaa3…` = the digest-pinned 1.17.0 index, RESEARCH S4): `running.since 17:20:06`, `ready: true`, `restartCount: 0`; conditions Initialized 17:20:06, **Ready 17:20:25** — the boot itself was 20 s (load lines below: 65.89 GiB read in 11.8 s at 6.0 GB/s, 11.4 s of that disk).
- **Why this pod and not the 16:30 one:** RS `5f7d6b95d7` predates (age 58 min at 17:28 ⇒ born of the owner's 16:29:51Z sync — §D7's roll), so the 17:20:05 creation is a **within-RS recreation**: event `Killing Pod/gpu-ai-radiance-5f7d6b95d7-trqlk "Stopping container radiance" 17:20:05` immediately after a SECOND manual sync `17:19:56Z` (Application `gpu-ai-radiance`: opState Succeeded, initiatedBy `tms@spencerslab.com`, strategy `{hook:{}}`, revision `da46cee2e…` = same as `comparedTo.revisions` ⇒ the sync itself was a no-op, the old pod was deleted by/for the owner). **Consequence: at probe time the engine is COLD — up ~10 min, and it has served EXACTLY ONE request.** No ramp is visible in THIS state; §D8.2's rate model uses the boot-B trio + this one line.
- **The one `req … done` receipt (this boot, the first request ever on the 110 pair):** `I req chatcmpl-5714bfa7aba0359a40749a36 chat stream from ::ffff:10.42.0.3:52394 … msgs=47 … prompt=3343 tok n=1 max_tokens=4096` → `I req … done … finish=stop prompt=3343 (cache 0) gen=884 reason=393 ttft=13.42s 12.4 tok/s 84.83s`. (Client 10.42.0.3 = the llama-swap router peer hop, C04 wiring. `reason=393` is not documented in GUIDE §5.7/5.8 — flagged as unresolved, immaterial.) Implied prefill rate: 3343 ÷ 13.42 = **249 tok/s**; decode **12.4 t/s at gen 884** — byte-identical in shape to boot B's 12.4-at-896 line.
- **HARDWARE block, verbatim, this boot (post-110):**
  - `host  AMD RYZEN AI MAX+ 395 w/ Radeon 8060S | 16 cores, 32 threads | RAM 125.08 GiB, 45.74 GiB available | swap 2.00 GiB, 0 B used`
  - `system kernel 7.3.0-1-default | … | cgroup memory 110.00 GiB | memlock 8.00 MiB` — the 110 limit IS what the cgroup reports; **memlock unchanged at 8 MiB** (§D6.3 posture).
  - `memory huge pages always (defrag madvise, shmem never) | ttm.pages_limit 112.00 GiB | pinned by this process 71.04 GiB` — **pinned printed 71.04 at 110 exactly as at 94** — the eager-reservation law (RESEARCH R8-Q1 boot-A proof) shown harmless-on-rate: raising the cap moves nothing that was binding.
  - `iommu off (no IOMMU is registered)`; `cpu governor powersave, energy preference balance_performance (amd-pstate-epp) | io_uring available` (same powersave reprint as §D6.4); `amdgpu cwsr_enable 1`; boot params line repeats `amd_iommu=off amdgpu.lockup_timeout=30000 ttm.page_pool_size=29360128 ttm.pages_limit=29360128`.
  - **card 0 (serving)** `0000:c4:00.0 rank 0 (device 0) gfx1201 "AMD Radeon AI PRO R9700" 31.86 GiB VRAM NUMA -1 driver amdgpu card1` — `link 00:03.1 8.0 GT/s x4 (max 16.0 GT/s x4) -> c2:00.0 8.0 GT/s x4 (max 32.0 GT/s x16) -> c3:00.0 32.0 GT/s x16 -> c4:00.0 32.0 GT/s x16  [read at 50% busy]`; `pcie 0: 2.5GT/s x4 250Mhz | 1: 16.0GT/s x4 616Mhz | 2: 16.0GT/s x4 1143Mhz`; `dma copy lists on DMA engine 0, a queue of this process's own; they give way to the collectives`; `power cap 300 W (default 300 W, max 300 W) | sclk 500-2350 MHz | mclk 96-1258 MHz | runtime pm active (control auto)`.
  - **card 1 (the APU)** `0000:c5:00.0 not serving 0x1002:0x1586 512.00 MiB VRAM NUMA -1 driver amdgpu card2` — `link 00:08.1 16.0 GT/s x16 (max 16.0 GT/s x16) -> c5:00.0 16.0 GT/s x16  [read at 0% busy: a link at rest parks below its maximum]`; `power cap unknown … runtime pm active (control on)`.
  - **FINDINGS — the WARN reprints for the third boot in a row:** `WARN link-below-max: card 0000:c4:00.0 (rank 0): the PCIe link at 0000:00:03.1 runs 8.0 GT/s x4 of its 16.0 GT/s x4 while the card is 50% busy` (+ the engine's own fix line: reboot-cleared-if-stuck / reseat / move; "check that it recovers under load (GET /diagnostics during a long prefill)"), `note experts-from-host: 41.52 GiB of weights a rank live in the pinned host pool and cross PCIe when they are used — "a prefill step streams every routed layer's pooled experts onto the card, so its speed is bounded by the link; decode reads the ones it routes to"`, `note link-capped` (root port max 16.0 GT/s x4 vs card's 32.0 x16 — the OCuLink port class, §D6.6 law), `note memlock-limited`, `note cpu-governor`.
  - **VRAM budget lines (unchanged by 110 — they are per-CARD):** `claimable 29.30 GiB`, `static weights 5.40`, `experts 17.76 GiB (74%)`, `kv cache 4.51 (19%)`, `prefill staging 1.63`, `unclaimed 94.82 MiB`, `card 0 settled at 220.80 MiB free`; `weights by tier: VRAM 23.07 GiB, host pool 42.70 GiB, container on disk 0 B, mapped 47.68 GiB (rank 0)`; `kv cache 4.49 GiB a card: 1600000 tokens, 8.0 sessions at 200000`.
  - **Placement/mover/heat config lines (new, quotable):** `I heat engine: 25078 movable units, 64 moves a step, decay 0.950 hysteresis 1.25 min-gain 1.50 credit cap 512 admit-heat 8.0`; `I mover: 7520 slab slots (32 shadow, 160 more kept free out of a loan), 17591 pinned pool slots`; `I rank 0: expert prefetch on: 2 copies a routed layer by DMA, ring 14.51 MiB`; `I prefill staging: … a step of more than 1024 tokens copies the pooled experts of 48 routed layers onto the card up to 3 layers ahead`; `I "--kv-resident 32768 raised to 65664 tokens"`; `I placement: token embedding (1.18 GiB) ram`, `n-gram table (47.68 GiB) disk: as asked`; `I load: one pass over the container, 65.89 GiB read in 11.8 s (6.0 GB/s) … 11.4 s of that was the disk (6.2 GB/s)`; the libavx 4096-byte-span line reprints verbatim; and the idle-engine signal `I rank 0: expert prefetch resting: the steps used 22% of its last 3410 copies, under the 30% that pays for them; it measures again every 8192 passes`.

### D8.2 THE ARITHMETIC — which candidate explains the observed rates

**(a) LINK.** The model's routed geometry, from live prints + the lab's own config strings: `qwen4exp arch … 48 layers` (boot line 2) — "180B-class MoE (512 experts/top-10)" (`charts/llama-swap/tests/evidence/flashnext-pre-chunk-baseline/gpu-ai.config.yaml:1056`; also the live router `/v1/models` description) — movable expert units `25078`, of which the card holds `7520` slab slots and the pinned pool `17591` (boot lines) ⇒ **522.5 units/layer, 30.0% card-resident, 70.0% (17558 units / 41.52 GiB) crossing PCIe when read** (the `experts-from-host 41.52 GiB` note ✓). Unit size is receipt-derived, NOT a doc figure: (17.76 + 41.52) GiB × 1024 ÷ 25078 = **2.42 MiB/unit** — which **refutes RESEARCH's carried decode estimate** (RESEARCH:777 "10 experts/step × 1.245 MiB ≈ 12.5 MB/token → near link-insensitive"): it priced whole-token routing as 10 fetches model-wide; the receipts say 10/layer × 48 layers with 2.42 MiB units. The arithmetic:
```
all-miss decode token  = 48 × 10 × 2.42 MiB  = 1,162 MiB
Gen3 x4  = 8 GT/s × 4 × 128/130 = 3.94 GB/s = 3,755 MiB/s   (boot: "8.0 GT/s x4", live)
Gen4 x4  = 7.88 GB/s = 7,510 MiB/s                            (the root port's own max, "16.0 GT/s x4")
all-miss ceiling       = 3755/1162  = 3.2 t/s (Gen3)   / 6.5 t/s (Gen4)
observed-rate miss fraction m = 3755 / (1162 × t/s):
   5.1 t/s (boot B, 1st req) → m = 0.64   |   12.4 t/s (boot B, gen 896) → m = 0.26
   19.3 t/s (boot B, gen 717) → m = 0.17  |   12.4 t/s (this boot, gen 884) → m = 0.26
prefill check: 3343 tok / 13.42 s = 249 t/s → 3755/249 = 15.1 MiB/token
   — exactly the guide's 15 MB/token prefill model that produced the docs' 454 t/s @55k on Gen4 x4 (RESEARCH:265-271).
```
**Conclusions.** (1) **19.3 t/s is NOT explainable by the link ALONE** — all-miss over Gen3 x4 would be 3.2 t/s; neither is it explainable by residency alone — a 70%-non-resident card over a healthy link (Gen4 x4) predicts ~6.5 t/s at full miss but the miss tail shrinks with heat, and 19.3 needs m≈0.17. The number is **link × miss-tail together**: observed decode sits exactly ON the Gen3-x4 saturation line of its CURRENT ~83% hit-rate miss stream (~200 MiB/token). (2) The implied ceilings: Gen3 x4 at today's warm residency **≈ 19–20 t/s** (we are there — the pair, the ngram spans and the governor are NOT the binding pair on the rate); Gen4 x4 at the same residency **≈ 37–40 t/s**; the docs' measured x16-class floor (RESEARCH:664, 29.0/28.0 ms single-stream steps ≈ 35 t/s) says the compute side tops out near there anyway — **the fix moves us FROM 19 TO the compute floor, it does not promise 160.** (3) The heat.h replay expectation corroborates: "Qwen3.8-Flash-Next TP1, 40% of experts resident … 78.0% vs 78.4% (oracle) at 64 swaps a step" — a 22% miss stream ⇒ 256 MiB/token ⇒ 14.7 t/s at Gen3 x4; our warm m=0.17 with 30% residency = imatrix warm start + skew beating the uniform case. **Link alone: refuted. Non-residency alone: refuted. The product, on a half-width half-speed link, is the ceiling.**

**(b) NON-RESIDENCY / THE MOVER NOT ENGAGING — what the ENGINE'S OWN DOCS say makes it dispatch.** (sources: spec.md §5.1–§5.4 and `core/place/heat.h` @v1.17.0, fetched 17:3xZ; GUIDE.md flag table §4.11/§8)
- **No warmup, no sustained-load gate.** heat.h `HeatParams::warmup_dispatches = 0` verbatim: *"Dispatches to watch before moving anything. 0, because min_gain already requires `hot >= cold*hysteresis + 1.5` … a warmup only delays convergence."* Heat accrues from the **routing histograms the card copies back each step** (one step stale by design; "Hit rate is therefore a property of the placement policy").
- **The only off-switch is `--deterministic`** (GUIDE flag table: *"pin placement to the loader's plan, so the resident set cannot change under the heat engine"*; heat.h `init`: under deterministic *"step() proposes nothing for the whole run"*). Our serveArgs **do not set it** — the live CONFIGURATION block lists every non-default option (model/tp/batched 4096/seqs 8/200K/headroom 96/fp8/kv-resident 32768/pool 43000/embedding ram/ngram disk/placement expert_tiered/checkpoint 4096/spec 3/host/port/served-name) + `105 options at their default`; there is **no `--expert-*` flag shipped at all** (the absence law, `charts/radiance/values.yaml:137` — the stale `--expert-vs-cache-ratio` never shipped), and GUIDE §8's env surface (RADIANCE_HOME/KERNELS/LOG/HF_TOKEN/XDG + R4D_AR_MAX_BLOCKS) carries **no heat knob** — `RAD_PLACE_MOVES_PER_STEP` (64) is a build-time constant per heat.h's own comment ("the value and its reason are at RAD_PLACE_MOVES_PER_STEP", not in the env table). ⇒ **Nothing we ship gates the mover; nothing we ship can tune it either.**
- **Why the resident set still starts warm without any dispatches:** spec §5.3 *"Warm start from the profile. The container's expert-popularity profile, derived from the imatrix's activation counts, ranks which experts begin resident… the heat engine re-ranks within a few steps."* That is the load-time 7520-unit slab fill (`I load: rank 0, mover took 23.16 GiB`) — profile-ranked. So **card residency exists from boot even if runtime heat never moved anything** — the D28(5) "cold expert set + half-width link" all-miss story (DECISIONS.md:569-572) is REFINED here: the expert set is warm-started, the link is the half-width, and the observed m values are exactly what that pairing predicts.
- **Is `min 0 max 154 mean 54.4 sd 73.3, L48+ ≈ 0` the expected steady state?** Reconciled, with the live prints: per-layer slab capacity = (7520 − 32 shadow − 160 loan-free)/48 = **152.7 ⇒ the `max 154` rows ARE full layers**; the engine itself declares the tie-break law that fills layers evenly ("A layer starved of slots misses on nearly every token" — heat.h `res_count_` comment); and `L48+ ≈ 0` rows are the NON-routed plane — the model is a 48-routed-layer MoE inside 113 "real layers" (boot `I kv: KV layer bundles 13/36/36/13/1/1/13 (113 real layers)`) whose drafter/vision/linear layers legitimately own zero expert residency. A mean of 54.4 over such a mixed row set with routed layers at ~128–154 is **consistent with a near-full slab, NOT with a tiering that never ramped.** What IS un-settled from the retained log: the literal boot-B `heat engine: 0 dispatches` reading (carrier DECISIONS.md:569-570) is **inconsistent with heat.h semantics under served traffic** (three requests ⇒ thousands of credited histograms ⇒ dispatches should be large, `proposed` small and `refused` dominant — "a dispatch that proposes nothing (nearly all of them once residency settles)"). Either the capture line was `0 proposed/refused` or the counters were read while idle; **NOT determinable read-only** (the boot-B pod is gone; this boot's counters exist only in `/stats` or the exit banner of the NEXT pod — `report()` is documented: "Exit banner, ending with the per-layer resident counts"). Exact owner probes in D8.3.

### D8.3 WARM OR COLD — is 19.3 fair, and the fixed-probe recipe

We are quoting rates off a **path-dependent, single-stream, mostly-cold engine**: boot B's trio spans 5.1→19.3 (3.8×) across three requests, and THIS boot's only receipt is the cold first request again (12.4 at gen 884 — vs boot B's warm 19.3 at gen 717). The expected shape of the ramp, per the docs: (1) **speculation warm-up** — `mtp` drafts 3 tokens in 3 serial passes and "prompt lookup fills in for any sequence it declines" (boot line; GUIDE §4.6) — acceptance starts low until the lookup tables see the text (`lookup_held_total` counts held-back proposals); published pack acceptance 62–88% (RESEARCH S5); (2) **n-gram row-cache warm** — the disk tier keeps a "~85 MiB io_uring row cache, ~half first-seen rows" (S2 §4.3, RESEARCH:195-196) — first-sight rows are 4 KiB-span reads off the NVMe (3.42 GB/s class, §D6.5); (3) **heat re-rank** — decay half-life ~14 steps, 64 swaps/step ⇒ convergence inside a few hundred tokens (heat.h); (4) **host clocks ramp** — powersave/balance_performance cores idle at 1.77–2.0 GHz (LIVE: Prometheus `node_cpu_scaling_frequency_hertz{cluster="gpu-ai"}` min 1.765 / max 3.548 / avg 2.219 GHz at 17:3xZ idle; datasource uid `prometheus` @ graphs.spencerslab.com) and the engine's own note says the per-rank serial host work "shows as host gap between steps". The engine's OWN fairness instrument (docs/GUIDE §6.1): the dashboard's `best 14.79ms | recent 15.21ms | now 97% of best` tiles — `best` = **fastest 32-consecutive-single-stream-step window this process has run, reset on restart**; a healthy lane's recent sits 3–11% above best and "that is not degradation". **Fixed-probe recipe (docs-supported; the tiles/metrics are documented, the recipe operationalizes them):** same prompt **≥2000 tokens** (one prefill regime, ≥ the 2048-token planning band), `n=1`, `temperature 0` (greedy ⇒ identical drafts/acceptance between runs; field range [0,2] per §5.7), `max_tokens 256+` (≥8 best-windows of 32 steps), **run it twice back-to-back and quote the SECOND run**, and between runs re-read: `kubectl -n default port-forward pod/gpu-ai-radiance-5f7d6b95d7-4fccz 8000:8000` then `curl -s localhost:8000/diagnostics | jq '.findings, .hardware.cards'` (the machine-only route passes on a port-forward socket: §6.6 admits loopback + `Host: localhost`; "hardware read again now" §7.1) + `curl -s localhost:8000/stats | jq` (heat counters live: dispatches/proposed/promotions/demotions/refused/no_candidate/distinct_promoted/readmits/routed/routed_resident/stream_bytes — the exact HeatStats fields in heat.h) + `curl -s localhost:8000/metrics | grep -E 'decode_step_seconds_(best|recent)|draft_acceptance_ratio'` (§6.3, plus its pitfall: acceptance ratio can stay high while tokens-per-step collapse — use `scripts/mcdecl.sh`'s blocks-per-step form). **The single number that ends this debate: `stream_bytes ÷ decode_tokens_total`** — the engine's own counted miss-stream per decoded token (heat.h: "stream_bytes is that traffic, the cost promotions exist to avoid"). If it reads ≈ 200 MiB → link-saturated at Gen3, case closed; ≈ 60 MiB → residency carries most of the step and the floor is host/compute, not the link.

### D8.4 OTHER FACTORS, RANKED (live number or doc cite each)

1. **PCIe link Gen3 x4** — live boot HARDWARE + WARN (D8.1); all ceilings above; worth ~2× on both legs. The doc says the reboot clears a *stuck* one ("An idle link reads 2.5 GT/s in lspci, and that is normal. If one card measures half the other's rate under load, the PCIe power state of its root port is stuck one level down, and a reboot clears it" — PREPARING_YOUR_RIG.md §5); **the reboot did NOT clear it** (§D6.6 + this reprint) ⇒ per that doc's own firmware table the next candidate is the slot's link-speed pin ("PCIe link speed of both slots | Gen5 | stops the slots training at a lower generation" — §1) or a Gen3-rated cable; the discriminator is the owner's `LnkCtl2: TargetSpeed` read (§D6.6's command block unchanged).
2. **Miss tail / prefetch resting** — `expert prefetch resting: 22% of its last 3410 copies, under the 30% that pays` (live); prefetch off the critical path only when it pays, so today's misses are serial ("A miss … for a host-pinned unit crosses the link on the step's critical path" — heat.h HeatStats comment). Headroom left by the mover at fixed link: Belady-unrestricted 92% hit (heat.h) vs our ~83% ⇒ at most ~1.3× more decode — and every swap spends the same 3.94 GB/s, so **link first**. No chart knob exists (D8.2b).
3. **CPU governor / clocks** — powersave reprint at 17:20 (D8.1) + live idle frequency spread (D8.3); engine note #cpu-governor; fix is host persistence (tuned/tlp, §D6.4 law), zero profile cost, magnitude unproven vs the link — it is the free second swing, not the headline.
4. **memlock 8 MiB** — live `memlock 8.00 MiB` + `note memlock-limited` unchanged at 110. **RAM n-gram tier is STILL dead at 110 — the sum again:** `pinned 71.04 + table 47.68 = 118.72 > 110.00`; the engine's own gate needs the table's size free *after* pools under the cgroup (RESEARCH:195-199), and 110 − 71.04 = **38.96 slack < 47.68 table**. §D6.5/§R8 verdict stands verbatim at 110: the drop-in buys **zero tok/s on this profile**; `io_uring available` already prints (live) — the ring works at 8 MiB.
5. **ngram 4 KiB spans** — libavx span line reprints (live); measured 3.42 GB/s O_DIRECT (§D6.5); published disk-vs-ram tier delta 3–10% (RESEARCH:773-774) ⇒ ≤1.9 t/s at 19.3 — third-order; earns a device move only AFTER the link.
6. **THP / compaction** — engine's live read: `huge pages always (defrag madvise, shmem never)`. The owner's capture decodes exactly: `AnonHugePages 78585856 kB` is **kilobytes, not bytes — ≈ 74.9 GiB (≈ 78.6 GB decimal), NOT "78.5 TB"** — it means ~three-quarters of the node's RAM is currently anonymous memory mapped through 2 MiB THP pages — which is *the pinned pool itself* (71.04 GiB mlocked anon + mirrors) **successfully huge-page-backed**: THP working as intended, no defect. `HugePages_Total 0` is the hugetlbfs *static pool* (irrelevant when THP is the mechanism) — and it is **live-confirmed right now**: PromQL `node_memory_HugePages_Total{cluster="gpu-ai"}` = `0`, `node_memory_MemAvailable_bytes{cluster="gpu-ai"}` = 49,397,030,912 (46.0 GiB) at 17:3xZ. `compact_fail 47681` / `allocstall_movable 116143` are **cumulative since boot** — they include the two 71 GiB pin bursts (boots A/B and every restart) on a 125 GiB box; whether compaction is happening NOW needs the delta: `grep -E 'compact_(stall|fail)|allocstall' /proc/vmstat`, wait 60 s idle, subtract — near-zero deltas ⇒ not binding (NOT readable by me: node-exporter here exports neither the vmstat nor the AnonHugePages field — verified, `node_vmstat_compact_fail*` empty in the TSDB).
7. **Power cap / clocks** — `power cap 300 W (default 300 W, max 300 W)` (live): the cap is at factory max, NOT a limit; the rig doc prices the other direction: "210 W costs under 1% of decode speed against the 300 W default" (PREPARING_YOUR_RIG §6). sclk/mclk under load: **no live read exists** — federated TSDB carries zero GPU metrics (`count({__name__=~".*gpu.*"})` and DCGM/amdgpu regexes all empty, live-verified this round) — the boot's `sclk 500-2350 | mclk 96-1258` are the DPM RANGE table, not the current P-state. Owner's load-time read: `cat /sys/class/drm/card1/device/pp_dpm_sclk` + `/sys/class/drm/card1/gpu_busy_percent` immediately around the fixed probe (no exec needed, host sysfs).
8. **NUMA -1 / root-port path / APU** — see D8.5's dedicated answer; engine prints `NUMA -1` for both cards (the SoC exposes no proximity domains — nothing to bind to, nothing lost read-only-provably); the contention question is settled by topology + the router's unloaded state below.

### D8.5 THE DECISION LIST (ordered by expected gain) — and the APU answer

| # | change (class) | the ONE probe that proves it | capability cost |
|---|---|---|---|
| 1 | **Link speed**: owner reads `sudo lspci -vvv -s 00:00:03.1 \| grep -E 'LnkSta:|LnkCtl2'` — `TargetSpeed 8.0` ⇒ BIOS slot pin → set Gen4/Auto (rig-doc firmware table); `TargetSpeed 16.0` while LnkSta 8.0 ⇒ electrical/cable → reseat/replace with Gen4-rated OCuLink | next boot's HARDWARE line reads `00:03.1 16.0 GT/s x4` — or mid-session without a restart: `GET /diagnostics` during a long prefill (§7.1: hardware read again now; the WARN's own fix line says exactly this) | none — zero profile changes; expect prefill 249→~450–500, decode 19.3→~30–40 |
| 2 | **Read the mover before touching anything else**: /stats heat counters + stream_bytes/token + dashboard expert plane, under the D8.3 fixed probe | `stream_bytes ÷ decode_tokens` ≫ 200 MiB or ≪ it decides link-vs-compute attribution in one number; `no_candidate` dominance would be the only sign of a budget problem | none (read-only) |
| 3 | **Governor persistence**: tuned/tlp (or whatever re-applies after reboot — §D6.4 proved bare writes don't survive) | next boot prints `cpu governor performance …` instead of powersave | none |
| 4 | **Accept 110 for what it is**: correctness/burst-cover, NOT a rate lever — pinned prints 71.04 unchanged at 94 and 110 (D8.1); keep the pair, do not revert (64 was the defect class, D28 class law) | — | — |
| 5 | **Then profile-side, only if the owner wants more than ~35–40 t/s single-stream**: the engine's OWN fix list for `experts-from-host` — "a shorter `--max-model-len` or fewer `--max-num-seqs`, `--embedding-placement ram` [already ours], `--kv-cache-dtype fp8` [already ours], or more cards (`--tp`)" (live FINDINGS note) — cutting seqs/ctx frees VRAM → slab grows → miss fraction m drops | re-run the fixed probe: m (or stream_bytes/token) falls and rate rises toward the compute floor | the 8-session lever is what dies first (`--max-num-seqs 8` is the owner's goal, D17; 200K is the model's trained ctx) — **profile negotiation, never a silent edit** |
| 6 | **Later, small**: XFS/ext4 pack move (kills 4 KiB spans, 3–10% band — §D6.5 adjudication unchanged at 110); k3s `LimitMEMLOCK=infinity` drop-in (buy 0 tok/s today — RAM tier still arithmetically dead at 110, D8.4-4 — do it only inside a planned k3s-restart window) | ngram span line gone from the next boot / `memlock unlimited` in HARDWARE | host storage layout work / k3s restart blast (§D6.3) |
| 7 | **The only documented road to the 140–160 t/s class: TP2 (second R9700)** — docs' §8 table (`radiance-second-gpu-tp2.md:222-223`: creator ~160 t/s & ~6,400 pp; Wilde Gen4 142–146 & 2,816–3,552) — and that class lives on the **switch-fabric / x16 path, not this box's x4 uplink**; TP2 re-pins the host answer DOWN (pool 12288/rank, D29/TP2 §12) | — | capital + the strata co-existence question re-opens (D29's either/or) |

**The honest null, checked, not assumed: the link did NOT retrain.** Three boots since the 15:01Z reboot (15:01, 16:30 roll, 17:20) all reprint `8.0 GT/s x4`, the newest one under a 50%-busy card — the §D6.6 "retrained-vs-luck" clause stays CLOSED and the Gen3 state is now witnessed across the 110 deployment too.

**APU answer — is the visible APU costing anything at all? NO, with three live lines:** (i) **topology**: the APU is `0000:c5:00.0` behind its own root port `00:08.1` at full `16.0 GT/s x16`; the R9700's chain is `00:03.1 → c2 → c3 → c4` — different upstream port, so APU PCIe traffic can never compete for the x4 uplink's 3.94 GB/s (both chains are the engine's own HARDWARE prints, D8.1); (ii) the engine prints the APU as `not serving` and its compute backend enumerated `1 device(s) [0:gfx1201]` — the c5 block is the HARDWARE section's /sys walk of "each display device" (§7.1), not a device the step loop touches; (iii) **contention is off right now**: the router's live `/v1/models` (public read, this round) reports **every model `unloaded`** — radiance/strata peers and all llama.cpp entries — and its log tail is only kube-probe health hits; so the 8060S holds no arena, no pinned DRAM, no memory-controller load. The APU's only theoretical cost channel is shared SoC DRAM bandwidth when a router model IS hot (llama.cpp CPU-expert reads + the APU's unified memory vs radiance's pinned-pool streaming) — a workload-time effect, not an enumeration artifact, and it does not exist at idle. **Cheaper-than-vfio scoping, if ever wanted:** the chart already allocates ONLY the R9700 (`amd.com/gpu-r9700-1` product-name claim, `charts/radiance/values.yaml:279-299`; the plugin's Allocate grants `/dev/kfd + card1/renderD128`, RESEARCH S13) — the residual visibility is /sys-enumeration-only and harmless; a belt to the suspenders would be `HIP_VISIBLE_DEVICES=0` as container env (one values edit, blast radius: this pod's enumeration only; llama-swap runs in its own pod against `gpu-8060s`, untouched). **A vfio bind WOULD be the harmful route — it strips the router's own render node.** Verdict: change nothing for the APU.

### D8.6 WHAT THE RUNBOOK ALREADY TELLS THEM — and how the receipts read at 110

The step-6 receipt list C13 folded (`.agents/notes/radiance-on-target-acceptance.md:527-535`, §R8/D30(4)) is, verbatim in force: `cgroup memory.peak ≤ 100 (the cap the ramp must not touch)`, `memory.events — oom_kill = 0 (the no-kill proof; max hits count how close the limit bit)`, `cgroup file ≈ 0 — the O_DIRECT falsifier`, `node MemAvailable ≥ 8 GiB at peak`, `/proc/buddyinfo` plus `compact_stall/compact_fail` deltas across the ramp, and the engine's `pinned by this process …` inside the 71–78 GiB window — under the standing law: **"the receipt decides, never the rate."** How they read NOW at 110: `pinned … 71.04 GiB` — IN window, identical at 94 and 110 (D8.1 — the eager-reservation law made this predictable, R8-Q1); `MemAvailable` — 46.0 GiB live (Prom, D8.4-6) ≫ the 8 GiB floor at steady state, but that floor is a FILL-time reading nobody has taken yet; `oom_kill` — the corollary is `restartCount: 0` on this pod (zero OOMs since the pair went live); `memory.peak`, `file`, the compact deltas across the ramp, and the fixed-probe decode numbers **all still require the 8-session gate to have run — and it has not** (one request served on this boot). So the owner's "still shit performance" is, per the runbook's own law, a RATE complaint pre-dating the RECEIPT: the single-stream rate ceiling this section quantifies (link × miss-tail, ≈19–20 t/s warm on Gen3 x4) is independent of the fill, and the fill is what proves the 110 envelope holds. The two lanes to run side by side: fix the link (decision 1), then run step-6's fill WITH the D8.3 fixed probe in the idle windows.

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md (this §D8 append only)]
commands_run: [readonly-ai-gpu-kubernetes: pods_list_in_namespace default (paged), pods_get gpu-ai-radiance-5f7d6b95d7-4fccz, pods_log -c radiance (tail 500, full startup report + the one req-done line), events_list (involvedObject + reason=Killing), resources_get Deployment(gpu-ai-radiance)/Application(gpu-ai-radiance) ×2, resources_list ReplicaSet => pass; pods_top => FAIL (metrics API RESOURCE_NOT_FOUND at 17:2xZ, transient; not needed); readonly-global-grafana: list_datasources, query_prometheus ×10 (count amdgpu/DCGM/radiance/gpu regex => EMPTY; kube_node_info{cluster="gpu-ai"} => present; node_cpu_scaling_frequency_hertz min/max/avg; node_memory_HugePages_Total=0; node_memory_MemAvailable_bytes=49,397,030,912) => pass; webfetch: codeberg raw GUIDE.md/spec.md/core/place/heat.h/core/place/mover.h/PREPARING_YOUR_RIG.md @v1.17.0 (section extractions), router https://llama.spencerslab.com/v1/models => pass; repo greps/reads: RESEARCH (S-table, RQ1 143-217, envelope 685-734, contradictions 755-804, R8 1588-1700), DECISIONS D28(5) 552-575, runbook 460-560, TP2 doc :222-223, values.yaml serveArgs/claims, gpu-ai.config.yaml:1056 => pass; git status/log => pass (clean tree, HEAD 384e3135e)]
deviations: none beyond scope notes — read-only throughout (readonly tiers + webfetch of the pinned tag); only EXPLORE.md written; used readonly-global-grafana (a named-readonly server) for the metrics-ground question the launch explicitly invited. Launch framings REFUTED where evidence disagreed: (1) 19.3 t/s is NOT explainable by the link alone — all-miss predicts 3.2 t/s; the observed rate sits exactly on the Gen3-x4 line of a ~17%-miss stream; (2) RESEARCH's carried "12.5 MB/token → link-insensitive decode" figure (line 777) contradicts the boot's own receipts (2.42 MiB/unit × 48 layers × 10) by ~18× — the receipts win; (3) "L48+ at 0 ⇒ tiering never ramped" is misread — those rows are the non-MoE layer plane (113 real layers vs 48 routed); max 154 = full slab row, so the table is consistent with a near-full slab; (4) the 110 pair was never a rate lever — pinned prints 71.04 unchanged at 94 and 110 (eager reservations, R8-Q1).
friction: pods_top threw RESOURCE_NOT_FOUND via the metrics API at probe time (skipped — Deployment/pod objects carried the proof); events_list/pods_list_in_namespace return table-formatted rows (key-shape workaround as in §D7); readonly-global-grafana tools use camelCase datasourceUid and require endTime (signature read via search before retry); node_exporter on gpu-ai exports neither vmstat-compact nor AnonHugePages metrics — THP/compaction-now stays owner-lane; Codeberg trees endpoint 404'd (used raw file paths; RESEARCH's S-table carried them).
open_questions: none research-grade (the physics is quantified; nothing needs storm). Owner-lane reads that would settle the residuals in one minute each: (1) `GET /stats` heat counters + `stream_bytes ÷ decode_tokens_total` under the fixed probe (settles the boot-B "0 dispatches" anomaly vs heat.h semantics and attributes decode between link and compute); (2) `lspci -vvv -s 00:00:03.1` LnkCtl2 TargetSpeed (BIOS-pin vs cable, §D6.6 rule); (3) `/proc/vmstat` compact/allocstall 60-s idle delta + `pp_dpm_sclk`/`gpu_busy_percent` around the probe (no GPU exporter exists in the federated TSDB — live-verified); (4) what `reason=393` means in the req-done line — undocumented in GUIDE §5.7/5.8, immaterial to the ceiling.
next_suggested: owner fixes the link (decision 1 — expected ~2× on BOTH legs, zero profile cost) and runs the D8.3 fixed probe before ANY profile or scalar conversation; coord folds D8.2(a)'s correction (RESEARCH:777's 12.5 MB/token decode estimate is falsified by the boot receipts — mark it SUPERSEDED in the next doc round, same class as the cold-hash correction), D8.2(b)'s "nothing chart-ships gates the mover and nothing chart-ships tunes it" law, and D8.5's APU=free verdict into DECISIONS/plan; the 8-session gate stays the receipt-decides arbiter and has still never run.

## §D10 — post-ritual link re-read: what the cold boot did and did not change (scout round 10)

*(Probes 21:41–21:52Z 2026-11-13, readonly-ai-gpu-kubernetes + readonly-gpu-kubernetes + repo reads. Owner action adjudicated (verbatim): "I turned everything off, turned the card dock on, waited 10 s, turned on the desktop, but performance is the same or worse." §R10 ranked that ritual as its #1 candidate (RESEARCH:2417 "Highest-probability single action: the dock-first FULL-COLD-BOOT sequence"; :2499 cause (a) power-state/ordering latch = "STRONGEST"). This section records the falsification precisely — hardware-state-did-not-move and hardware-moved-but-rate-did-not are different conclusions; pick the right one.)*

**VERDICT FIRST: (i) — THE RITUAL CHANGED NOTHING IN THE HARDWARE STATE. The engine's own HARDWARE block, printed on a genuinely NEW boot (node event `Rebooted … boot id: 4d6202d9-14f2-4e7d-b107-1edec278a73d` at 21:34:43Z — not a warm reboot; the old pod took SIGTERM at 21:31:24Z and drained cleanly, off-window ≈ 3 min 19 s, consistent with "everything off → dock on → 10 s → desktop on"), reprints the root port EXACTLY degraded: `link 00:03.1 8.0 GT/s x4 (max 16.0 GT/s x4) -> c2:00.0 8.0 GT/s x4 … [read at 48% busy]`, and FINDINGS re-warns `link-below-max … runs 8.0 GT/s x4 of its 16.0 GT/s x4 while the card is 48% busy`. The rate did not move BECAUSE THE LINK DID NOT MOVE — §R10's rung-1 (power-ordering latch as sufficient cause) is FALSIFIED by exactly the experiment R10 prescribed, one full-cold execution in. The ladder moves to R10-Q5 rungs 2→3→4 (reseat both ends → known-Gen4 SFF-8611 cable swap → DOCK BYPASS, the definitive discriminator), with the R10-Q3 stability trio still armed and unre-addressed (the report STILL prints `runtime pm active (control auto)`). BONUS FINDING, the round's real news: the retired pod's EXIT BANNER proves the MOVER FULLY ENGAGED — `heat engine: 20678 dispatches, 12129 swaps proposed, 13736 promotions, 11960 demotions`, `resident units a layer: min 0 max 300 mean 67.2 sd 94.5` — which settles §D8's open question (boot B's "0 dispatches" was a read artifact) AND REFUTES my own §D8.2(b) capacity reconciliation (154 was NOT the per-layer cap — layers reach 300; and 36% of promotions are re-admits, mover+prefetch moved 71.40 GiB h2d / 19.08 GiB d2h over one served request — extra link traffic the §D8 model priced at zero).**

### D10.1 THE POD AND BOOT STATE — a NEW boot; the launch's "≈18:4xZ" premise corrected

- **New serving pod**: `gpu-ai-radiance-5f7d6b95d7-6h9cz`, uid `656ca946-d5a1-4876-aebd-bfa92e65a221`, created **2026-11-13T21:34:47Z**, node `ai-gpu`, Running, **`qosClass: Guaranteed`**, `allocatedResources {memory 110Gi, cpu 8, amd.com/gpu-r9700-1: 1}` — template UNCHANGED (same RS `5f7d6b95d7`; nothing re-rendered; the recreation is the node power-cycle, not a roll). Init `radiance-fetch`: terminated exitCode 0, startedAt==finishedAt==21:34:53 (marker-skip <1 s, restartCount 0). Serve: `running.since 21:34:54`, ready true, **restartCount 0**, Initialized 21:34:54, **Ready 21:35:13** — 19 s boot-to-serve, same class as §D8 (`I load: one pass over the container, 65.89 GiB read in 12.0 s (5.9 GB/s) … 11.5 s of that was the disk (6.1 GB/s)`).
- **Old pod `5f7d6b95d7-4fccz`** (§D8's): `phase: Succeeded`; serve container `terminated {exitCode: 0, reason: Completed, startedAt 17:20:06, finishedAt 21:31:24}` — the host-shutdown SIGTERM, drained (`I stopping: draining in-flight requests`) and wrote its exit banner (D10.5). Over its 4 h 11 m life it served EXACTLY ONE request — **no 18:4xZ traffic and no 18:4xZ boot exist in the record**; the §D8 probe window (17:24–17:35Z) ran inside boot `69259d13…` (the §D6 15:01Z boot). The launch's "a fresh boot after ~18:4xZ" is corrected: the fresh boot is **21:34:43Z**.
- **THE BOOT evidence**: `Node/ai-gpu "Node ai-gpu has been rebooted, boot id: 4d6202d9-14f2-4e7d-b107-1edec278a73d" 21:34:43Z (Warning/Rebooted)` + `Starting kubelet.` + `NodeAllocatableEnforced` (same second). This is the **first cold cycle since 15:01Z and the first dock-first ritual cold boot ever witnessed in the ticket** (§R10-Q1: "no cold-boot-with-dock-first witnessed in the ticket's boot history" — now one was, and Gen4 did not appear). Whether the dock's own button was actually cycled before the host is NOT observable from k8s — accepted on the owner's word; the ≥3-min off-window is consistent with the stated 10 s order.
- Surroundings: node conditions 21:43:13Z all-False pressures, Ready True. Router recreated as `gpu-ai-llama-swap-6796d989db-6qn8f`, Running `2/2`, restarts 0 (old `lz4fd` now an `Unknown` GC-orphan row — why the request client IP moved from `10.42.0.3` to `10.42.0.47`). Strata Deployment `gpu-ai-llama-swap-strata`: **`spec.replicas: 0`** (gen 47, unchanged) — the §D7 don't-sync law held through the power cycle.

### D10.2 THE LINK LINES, FRESHLY PRINTED — the key question, answered verbatim

- **R9700 chain (card 0000:c4:00.0, rank 0, gfx1201, 31.86 GiB, NUMA -1, card1)**: `link   00:03.1 8.0 GT/s x4 (max 16.0 GT/s x4) -> c2:00.0 8.0 GT/s x4 (max 32.0 GT/s x16) -> c3:00.0 32.0 GT/s x16 (max 32.0 GT/s x16) -> c4:00.0 32.0 GT/s x16 (max 32.0 GT/s x16)  [read at 48% busy]` — **it is NOT 16.0 at the root-port hop after the ritual; the launch's "say so loudly if it did" branch is not taken.** The DPM-table line `pcie   0: 2.5GT/s, x4 250Mhz | 1: 16.0GT/s, x4 616Mhz | 2: 16.0GT/s, x4 1143Mhz` is byte-identical to §D8's.
- **APU (0000:c5:00.0, `not serving`)**: `link   00:08.1 16.0 GT/s x16 (max 16.0 GT/s x16) -> c5:00.0 16.0 GT/s x16  [read at 0% busy: a link at rest parks below its maximum]` — unchanged; §D8's APU verdict untouched.
- **busy%% census — launch framing corrected**: the recorded reads are **49% (§D6.6, EXPLORE.md:1367, 15:01Z boot) → 50% (§D8.1, 17:20Z boot) → 48% (this 21:35Z boot)**. **A "61%" reading does not exist anywhere in the ticket** (grep `61%` over EXPLORE/RESEARCH/DECISIONS/chunks: zero hits) — the launch's citation is a false memory; the three real reads show the load-state training check rock-stable across ritual and non-ritual boots.

### D10.3 THE FINDINGS BLOCK — 1 warning, 4 notes, zero delta

`I FINDINGS -- 1 warning, 4 notes`, the §D8 set reprinted: `WARN link-below-max: … 00:00:03.1 runs 8.0 GT/s x4 of its 16.0 GT/s x4 while the card is 48% busy` (+ its fix line: reboot-cleared-if-stuck / "check that it recovers under load (GET /diagnostics during a long prefill)" / "reseat or move the card if it trains narrow"), `note experts-from-host: 41.52 GiB … cross PCIe when they are used`, `note link-capped` (card 32.0 x16 max vs host-side 16.0 GT/s x4), `note memlock-limited: RLIMIT_MEMLOCK is 8.00 MiB`, `note cpu-governor: powersave with energy preference balance_performance`. HARDWARE unchanged elsewhere: `cgroup memory 110.00 GiB | memlock 8.00 MiB`; `ttm.pages_limit 112.00 GiB | pinned by this process 71.04 GiB` — **FOURTH byte-identical pinned print (94→110→110→110 across a cold boot): §D8's eager-reservation law re-confirmed**; `RAM 125.08 GiB, 46.86 GiB available | swap 2.00 GiB, 0 B used`; `iommu off`; `huge pages always (defrag madvise, shmem never)`; **`power cap 300 W (default 300 W, max 300 W) | … | runtime pm active (control auto)` on c4, `(control on)` on c5 — the R10-Q3 stability trio (`/sys/bus/pci/devices/0000:00:03.1/d3cold_allowed`, `power/control`, `current_link_speed`, chain-wide) is still UNADDRESSED and armed.** **The governor line reprints `powersave` after a full power cycle — §D6.4's non-persistence adjudication re-confirmed for the second reboot: the performance writes did NOT survive; the tuned/tlp persistence lane is still owed.** No NEW finding appeared (no swap-in-use, no device-lost class) — the launch's option (iii) "fresh hazard" is EMPTY.

### D10.4 THE RATES — "same or worse" adjudicated

Exactly two `req … done` lines since the boot (log read whole at 21:44Z):
```
req chatcmpl-299e52fb9afb607656ec282a done … finish=stop prompt=3847 (cache 0) gen=1047 reason=486 ttft=13.43s 11.0 tok/s 108.73s   → prefill ≈286 t/s
req chatcmpl-c0632436af145f836e085d86 done … finish=stop prompt=4421 (cache 0) gen=1707 reason=1127 ttft=16.41s 16.4 tok/s 120.69s   → prefill ≈269 t/s
```
Position-for-position against the series (same warm-up slot per boot): first-request-after-boot was 5.1 (boot B) then 12.4 (§D8 boot) → now **11.0** (§D8's m=0.26 → m=0.29 — same distribution, one sample); request-#2-class was 12.4→19.3 (boot B) → now **16.4** at m=0.20, mid-convergence toward the same ~0.17 asymptote, and its gen (1707) is LONGER than boot B's 19.3-sample (717), which costs rate at growing context by itself. Prefill 249 → 286/269 t/s ⇒ implied 13.1–13.9 MiB/token — the same Gen3-x4 15-MiB/token band (§D8.2a), nudged by the longer prompts. **"Same or worse" is SUPPORTED, but only as "SAME, MID-RAMP"**: the owner's two samples are exactly the first two points of the 3.8× warm-up curve §D8.3 quantified, ~7 minutes post-Ready; nothing says the ritual hurt, nothing says it helped — which is precisely what "the hardware did not move" predicts. A fair post-ritual number still needs the §D8.3 fixed probe at request-position ≥4 — not run.

### D10.5 THE MOVER / WARM-START — §D8's open question CLOSED by a recovered exit banner

The shutdown was graceful, so 4fccz's log ENDS with heat.h's documented exit report ("Exit banner, ending with the per-layer resident counts"), readable by readonly pods_log on the Succeeded pod — the ticket's first complete mover receipt:
```
I heat engine: 20678 dispatches, 12129 swaps proposed, 13736 promotions, 11960 demotions
  328 dispatches declined on hysteresis, 0 found no candidate at one end
  9993 distinct units promoted, 4971 readmits (36% of promotions were of something already demoted)
  resident units a layer: min 0 max 300 mean 67.2 sd 94.5
   L0 300 272 275 172 200 208 241 227 199 181 216 193 | L12 234 230 200 103 … | L24 194 190 216 … | L36 165 181 … | L48 273 then 0s | L60–L107 all 0 | L108–L138 ≈1
I   routing evidence: 20678 layer-histograms credited, 49 layer-sweeps found nothing new, 0 dropped by a ring shallower than the run-ahead
I mover: 423 dispatches, 13736 promotions, 11960 demotions, 0 staged (71.40 GiB h2d, 19.08 GiB d2h)
  0 found no free move record, 265 starved of a slab slot, 3721 of a pool slot; 25696 slots quarantined
I rank 0: expert prefetch: 25529 copies planned, 11798 of 25523 looked back on routed (46.2%), 6 requests dropped behind a slow queue, 1 rests
```
Readings, each against §D8: **(1) THE MOVER ENGAGES** — 20678 dispatches and 13736 promotions from ONE served request (884 gen tokens) plus idle: boot B's literal `0 dispatches` (DECISIONS.md:569-570) is refuted as a state; it was a read artifact (its own banner is unrecoverable). The "warm or cold engine" question now has its warm-side witness. **(2) §D8.2(b) is SELF-CORRECTED HERE**: `max 154` was NOT the per-layer slab capacity — residency reaches **300**/layer; total resident units ≈ 9342 ≈ the 7520-slot slab (192 reserved) **+ the documented loans** (`mover: 520 slots can be lent out of the KV cache (1.23 GiB) … 1416 slots out of the activation arena (3.34 GiB)`) ⇒ residency ≈ 37% of the 25078 units, hot layers up to ~57% covered. The boot-B table's "L48+ zero" reading is re-confirmed as the non-MoE layer plane, but §D8's capacity inference was wrong and this paragraph supersedes it. **(3) It CHURNS, and the churn rides the same link**: 36% re-admits (heat.h: "Readmits say whether the guards are set right" — here, not quite), 46.2% of prefetch copies never looked back on, and 71.40 GiB h2d + 19.08 GiB d2h of mover transfers during a session whose decode-token count was ~884 — on the order of a further ~90–100 MiB per served token of RE-PLACEMENT traffic on top of the ~200 MiB/token miss stream. This refines the §D8 model rather than breaking it: the settled `49 layer-sweeps found nothing new` state is where m≈0.17 lives; the CONVERGENCE cost lands on the 3.94 GB/s bus during exactly the early requests whose rates look worst (11.0/12.4). Fixing the link halves the misses AND the churn AND the prefetch waste together — the link-first ordering survives the new finding intact. **(4) Current-pod live state**: `expert prefetch resting: the steps used 26% of its last 3534 copies, under the 30% that pays` (same idle signature as §D8's 22%, boot B's 29%); `kv streaming … request end: 19741 resolves, 36,437,040 lookups, 35600 misses (+13 this interval) … overflow no` — healthy; `weights by tier  VRAM 23.07 GiB, host pool 42.70 GiB, container on disk 0 B, mapped 47.68 GiB (rank 0)` — identical.

### D10.6 STABILITY SIDE-EFFECTS OF THE RITUAL — none

Events (ns default windows incl. Node + reason=Killing): only the standard `SandboxChanged … killed and re-created` wave on system pods and the `Rebooted` warning; **no `BackOff`, `OOMKilling`, `Evicted`, `FailedScheduling`, or device-loss-class event touches radiance** (the only Killing in the window remains 17:20:05Z's manual delete — expired evidence). Old pod exitCode 0; new pod restartCount 0; card re-enumerated and loaded 65.89 GiB in 12 s; **no `device lost from bus` D3cold symptom HAS appeared** — while its precondition (R10-S6: root-port `d3cold_allowed=1` default + `power/control auto`) remains armed un-pinned. The 8-session gate: STILL NOT RUN — three single-stream requests total across the two post-110 boots; nothing ever Pending; the strata 0/Pending-handshake posture undisturbed.

### D10.7 THE GPU-CLUSTER CONTROL — untouched, invariant held

Node `gpu`: Ready=True since `2026-11-12T08:19:39Z` (predates the ritual by >13 h), bootID `a5b6abf9-be11-4353-ad7d-632905ad2727`, capacity `29994244Ki`, pressures False. `gpu-llama-swap-6c6fb487cb-rd4cj`: **Running 1/1, Age 27h, restartCount 0 — the SAME pod object §D6.2 read at 15:0xZ, alive across gpu-ai's power cycle** (the `Unknown` rows around it are old RS GC-residue). The ritual touched only the gpu-ai box.

### D10.8 WHICH CONCLUSION — (i), named, with the ladder that follows

**(i): the ritual changed NOTHING in the hardware state** — root port `8.0 GT/s x4 (max 16.0 GT/s x4)` on a fresh cold-boot training, busy-read band unchanged (49/50/48), findings unchanged, pinned unchanged, memlock/governor unchanged. The owner's observation is the designed consequence of (i), and **§R10's #1-ranked cause (a) power-state/ordering latch is FALSIFIED by its own prescribed experiment** (one full-cold execution; the "×2-3" text leaves a cheap repeat, but every mechanism R10 cited is first-contact latch and first contact was ritualized this time — spend the next power cycles on rungs 2-3, not on repeating rung 1). Consequences per the ticket's own ladder:
1. **Rungs 2→3 now (cost ~0)**: reseat the SFF-8611 at both ends until the latch clicks + full 24-pin/AC seating; then swap in a known-Gen4-rated short cable. Witness after each: `journalctl -k -b | grep 'available PCIe bandwidth'` + the engine's `link` line under load. Cause (d) (cable/connector integrity) is R10-Q2's surviving STRONG candidate now that (a) died; a fresh cold training re-failing Gen4 EQ down to Gen3 is exactly cause (c)-via-channel.
2. **Rung 4 is the decisive separator**: dock bypass — card+cable straight into the host's own OCuLink port, open frame (R10-Q3 verbatim: "Gen4 there with the SAME cable ⇒ the dock's PCB/power path is the defect; Gen3 still ⇒ the host port ↔ cable ↔ card triple owns it"). The dock is a proven Gen4-class witness elsewhere (chimolog 7.07 GB/s, R10-S8) and the card class is ruled out (R10-Q2 (f)); the BIOS-pin arm was already closed by the owner's `Target Link Speed: 16GT/s` read (D34).
3. **The stability row is due regardless**: `runtime pm active (control auto)` persists (D10.3) → the `d3cold_allowed=0` udev chain rule + `amdgpu.runpm=0` (R10-Q4 row $2) is *stability*, not speed ("Anything that doesn't land LnkSta first is not a fix, it's hygiene" — R10-Q4), and D10.5's churn makes a mid-session link power-state drop costlier on this lane than anywhere else.
4. **The rate question needs no new theory**: §D8's arithmetic stands, refined by D10.5 — settled warm ceiling on Gen3 x4 ≈ 19–20 t/s (observed asymptotes 19.3/16.4), prefill ~15 MiB/token ≈ 250–290 t/s; the engine's own four prints say nothing else moved. Anything faster is bought at `LnkSta`, not at the chart.

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md (this §D10 append only)]
commands_run: [readonly-ai-gpu-kubernetes: pods_list_in_namespace default (paged), pods_get gpu-ai-radiance-5f7d6b95d7-6h9cz + 5f7d6b95d7-4fccz, pods_log 6h9cz -c radiance (full post-boot report: HARDWARE, FINDINGS, 2 req-done lines), pods_log 4fccz -c radiance tail 220 + tail 0 FULL (exit banner recovered — graceful drain preserved it), events_list (Node window, reason=Killing, default-ns 60), resources_get Node(ai-gpu) + Deployment(gpu-ai-llama-swap-strata) => pass; readonly-gpu-kubernetes: resources_get Node(gpu), pods_list_in_namespace default (paged) => pass; repo reads: RESEARCH §R10 (ladder + causes table, 2410-2515), EXPLORE §D6.6/§D8 cross-check greps, DECISIONS D28(5) carrier; greps "61%" (zero hits) + busy%% census => pass]
deviations: none — read-only tiers only, no exec, no mutations; EXPLORE.md the only write. Framing corrections recorded in place: (1) launch's "fresh boot after ~18:4xZ" — the boot is 21:34:43Z (boot id 4d6202d9); (2) "§D6's 61% busy reading" never existed — real census 49/50/48; (3) my own §D8.2(b) per-layer capacity inference (154≈cap) REFUTED by the recovered exit banner (max 300 + loan math) — D10.5(2) supersedes it; (4) boot-B "0 dispatches" positively re-classified as a read artifact — the mover demonstrably engages on this profile.
friction: pods/events servers return table-formatted rows (key-shape workarounds, known class §D7); dock power-ordering is not observable from k8s (owner's word + off-window length recorded as the evidence); the running pod has no exit banner yet — mid-run mover state quoted from boot lines + the `expert prefetch resting` print; 4fccz's own banner is what closed D8's open question.
open_questions: none research-grade. Owner-lane reads settling the residuals: (1) rungs 2-3 (reseat, cable swap) then rung 4 (dock bypass) with the engine link-line witness — no read-only k8s probe can separate cable/dock/host-port, that is the physical ladder R10 already ranked; (2) `/sys/bus/pci/devices/0000:00:03.1/d3cold_allowed` + `power/control` chain read (stability lane); (3) the §D8.3 fixed probe at request-position ≥4 (settles whether settled m improved now that the predecessor reached `49 layer-sweeps found nothing new`); (4) whether 36% readmits + 46.2% wasted prefetch merit an upstream radiance report (the churn is ~40% of the served-token link load on this link width — heat.h's own U-curve note says tightening guards past the min loses hit rate without saving bytes, so the guards may already be at their documented optimum and the link the true cause).
next_suggested: coord records the falsification (D33-class: ritual rung-1 FALSIFIED by cold boot 4d6202d9; ladder → reseat/cable → dock-bypass; d3cold/runpm stability row due regardless; mover proven engaged + churning — boot-B 0-dispatches superseded as artifact; §D8.2(b) capacity line corrected), and the owner gets the two-cost-next list (reseat + cable swap with link-line witness, then dock bypass); the fixed probe and the step-6 8-session gate stay queued behind whichever lands `LnkSta 16.0`.

## §D11 — host identity + slot/topology facts readable from the cluster (scout round 11)

*(Probes 2026-11-14 00:44–00:56Z, readonly-ai-gpu-kubernetes + readonly-gpu-kubernetes + readonly-global-grafana + repo reads. Re-land record (required by the lost-lock rule): the first append of this section was BLOCKED ~00:56Z — the scout lane's claim had been reaped stale at 00:45:29Z (timer; >2 h heartbeat gap between scout rounds; pipeline_status then read `session: null`, only an unrelated `CICD` set live). The step stopped, exactly ONE sanctioned question was asked, the human answered "yes — re-claim and write", and the card was re-claimed at 01:0xZ (card `Na5LxMaY3ptABWhAy`, setId `ba079f6f-78cd-46c1-98f0-aa9e330bbec0`, pipeline `default` — the card carries no `Pipeline:` labels); EXPLORE.md was verified unmodified in between (1609 lines, §D10 tail intact, byte-checked). This append IS the resumed write. Launch: establish the MACHINE IDENTITY of ai-gpu so §R11 can target the right platform — owner says "framework desktop 16" — and re-verify link state. Framing tested, not assumed; it survives where it matters: §R9/§R10 DID reason from a GMKtec-class board (RESEARCH.md:2379 literally labels the EVO-X3 source "**(the lab's machine class)**") and no cluster object ever verified that label.)*

**VERDICT FIRST: NOT-DETERMINABLE-from-the-cluster (the third option — neither Framework nor GMKtec can be PROVED from any cluster object). The cluster carries ZERO vendor identity surface: no NFD anywhere (zero daemonsets/pods matching nfd|feature-discovery in a fully-paged sweep — 35 pods over gpu-ai's complete namespace set `default, kube-system, system-upgrade`, 94 pods over the same three on gpu; zero NFD CRDs in the 99-entry CRD list; zero `feature.node.kubernetes.io/*` labels), and kubelet's `status.nodeInfo` exposes no DMI manufacturer/product — only machineID/systemUUID/bootID/os strings. BUT the cluster-side hardware profile is CONSISTENT-with (not proof-of) a real firmware board under the owner's claim, and §D10's metric blind-spot was partly MYSELF: two self-corrections land here — `node_memory_AnonHugePages_bytes` DOES exist on ai-gpu (my earlier lowercase-name query missed it) and reads **80,809,558,016 B = 75.26 GiB** live, and `node_cpu_scaling_governor` gives a first cluster-LIVE governor read: **all 32 cores `governor="powersave" == 1`, `governor="performance" == 0` at 00:47Z**. And the link: NOTHING moved since §D10 — bootID is still `4d6202d9-14f2-4e7d-b107-1edec278a73d` (node_exporter `node_boot_time_seconds 1794605659` = 21:34:19Z Nov 13 = the ritual boot), same pod `5f7d6b95d7-6h9cz` restartCount 0, the startup `link 00:03.1 8.0 GT/s x4 … [read at 48% busy]` line is the same print, and no new requests have arrived (the two `done` lines from §D10 are still the only traffic). Consequence for the record: the tuning note's **Rung 4 "explicit Gen4, not Auto" advice targets a board the lab may not own** — the sentence at `.agents/notes/radiance-host-tuning.md:108-112` (and its source row `RESEARCH.md:2379`) must be re-scoped to Framework Desktop in §R11; the owner's five-command `dmidecode`/`fwupdmgr` block (D11.7) settles identity in one paste.**

### D11.1 NODE IDENTITY — ai-gpu, every field verbatim (resources_get Node, 00:44Z)

- `status.nodeInfo`: `machineID e6a0b13b981744ba9d4af533db217b20` · `systemUUID edff8d86-8f81-f111-8010-9cbf0d01f966` · `bootID 4d6202d9-14f2-4e7d-b107-1edec278a73d` (unchanged from §D10's ritual boot) · `kernelVersion 7.3.0-1-default` · `osImage openSUSE Tumbleweed` · `containerRuntimeVersion containerd://2.3.4-k3s1.36` · `kubeletVersion v1.36.5+k3s1` · `swap.capacity 2148204544`.
- `metadata.labels` IN FULL — every label, nothing else: `beta.kubernetes.io/arch=amd64`, `beta.kubernetes.io/instance-type=k3s`, `beta.kubernetes.io/os=linux`, `kubernetes.io/arch=amd64`, `kubernetes.io/hostname=ai-gpu`, `kubernetes.io/os=linux`, `node-role.kubernetes.io/control-plane=true`, `node.kubernetes.io/instance-type=k3s`, `plan.upgrade.cattle.io/server-plan=2338042de5…`. **No `feature.node.kubernetes.io/*`, no cpu/system/pci labels.**
- `metadata.annotations`: only k3s/flannel plumbing — `k3s.io/hostname`, `k3s.io/internal-ip 10.0.99.151`, `k3s.io/node-args ["server"]`, `k3s.io/node-config-hash`, `k3s.io/node-env {}`, flannel VXLAN pair, `alpha.kubernetes.io/provided-node-ip`, `node.alpha.kubernetes.io/ttl`, `volumes.kubernetes.io/controller-managed-attach-detach`. No DMI, no kubeadm.
- `spec.providerID: "k3s://ai-gpu"` (k3s default — carries nothing), `spec.taints: none`, addresses `10.0.99.151 / ai-gpu`.
- **Identity-adjacent hardware facts the cluster DOES give** (via the federated node_exporter, §D11.3): `node_os_info{id="opensuse-tumbleweed", version_id="20261024"}`; `node_uname_info{release="7.3.0-1-default", version="#1 SMP PREEMPT_DYNAMIC Mon Oct 19 15:21:44 UTC 2026 (7f1f6b1)"}`; MAC/UUID coupling: NIC `enp191s0` MAC `9c:bf:0d:01:f9:66` vs `systemUUID …8010-9cbf0d01f966` — **the SMBIOS UUID embeds the MAC** (firmware-generated UUID, real-board style); and `machineID ≠ systemUUID` (a locally generated /etc/machine-id, the bare-metal install pattern) — in pointed contrast to the gpu box (D11.4). None of these names a vendor — Strix Halo boards (Framework Desktop, GMKtec EVO-X3, Minisforum MS-S1 class) would all produce the same strings; the CPU string alone identifies only the SoC class (`AMD RYZEN AI MAX+ 395 w/ Radeon 8060S | 16 cores, 32 threads` — the engine print), which is exactly why the launch says do-NOT-infer, and why §R11 must stop inferring EVO-X3 from it too.

### D11.2 NFD: ABSENT, plainly

Both clusters were swept with fully-paged `pods_list` (gpu-ai: 35 pods across the complete namespace set `default/kube-system/system-upgrade`; gpu: 94 pods, same three namespaces) plus DaemonSet lists — gpu-ai runs exactly `gpu-ai-amd-gpu-device-plugin-daemonset`, `gpu-ai-k8s-monitoring-alloy-logs`, `gpu-ai-k8s-monitoring-node-exporter` (default ns); **no nfd worker anywhere, no `nodes.config-feature-discovery.kubernetes.io` CRD among the 99 listed CRDs, and no feature labels on the node (D11.1)**. ⇒ The only cluster-side identity surface is kubelet's `nodeInfo` + the metrics-info labels above, and **the manufacturer question can ONLY be settled host-side (`dmidecode`, `fwupdmgr`, `hostnamectl`)**. If the owner wants future rounds to answer identity from the cluster, the permanent fix is deploying NFD with the `system`+`pci` sources — a new workload, human-owned, out of this ticket's scope (noted for follow-up, not proposed as a chunk).

### D11.3 TOPOLOGY / METRICS INVENTORY — what the cluster actually sees of the hardware

- **AMD device plugin** (`gpu-ai-amd-gpu-device-plugin-daemonset-b79lf`, Running 22h, 2 restarts @ the 21:34 ritual boot): `Devices map: 0000:c4:00.0 {card:1 deviceID:7551 renderD:128 nodeId:0 numaNode:-1 revisionID:C0} | 0000:c5:00.0 {card:2 deviceID:1586 renderD:129 nodeId:0 numaNode:-1 revisionID:C1}` + `Parsing /sys/class/kfd/kfd/topology/nodes/0|1/properties`. **No PCIe link state, no chain** — the plugin sees cards and kfd nodes only; the ONLY cluster-visible link-state witness remains the engine's own startup print (§D10.2, unchanged).
- **NEW cluster fact — the NVMe sits on the same PCI arm as the dock chain:** `node_disk_info{device="nvme0n1", model="WD_BLACK SN7100 1TB", path="pci-0000:c1:00.0-nvme-1", serial 260409802393, rotational 0}`. The R9700 chain is `00:03.1 → c2:00.0 → c3:00.0 → c4:00.0`; the drive is `c1:00.0`. **Whether c1 shares the `00:03.x` root-port complex (making n-gram disk reads and expert streaming share upstream silicon) is NOT readable from the cluster** — owner-lane: `readlink -f /sys/block/nvme0n1/device` + `lspci -t -vvv`. If shared, it joins the §D8 traffic picture on the same bridge; if not, the disk path is independent. Flagged for §R11/owner, priced as UNKNOWN here.
- **Grafana datasource `prometheus` (graphs.spencerslab.com), instance `ai-gpu`, job `integrations/node_exporter` — 206 series; the names that matter (all VERIFIED present, none invented):** `node_cpu_scaling_governor{cpu,governor}` — **live read 00:47Z: powersave=1, performance=0 on ALL 32 cores** (first continuous cluster-side governor witness; the tuned/tlp persistence lane's before/after is now measurable without a reboot); `node_cpu_scaling_frequency_hertz` (+min/avg/max family; idle avg 2.24 GHz), `node_cpu_frequency_{avg,max,min}_hertz`; `node_memory_AnonHugePages_bytes` = **80,809,558,016 (75.26 GiB — the pinned pool IS THP-backed anon on the node side, re-confirming §D8.4-6's kB-unit decode from the metrics side)**; `node_memory_MemAvailable_bytes` = 49,504,407,552 (46.1 GiB); `node_memory_Mlocked_bytes` = **0** and `node_memory_Unevictable_bytes` = 360,448 (~0.3 MiB) while the engine prints `pinned by this process 71.04 GiB` — a live, quantitative confirmation of §D6.3's scope law: the pool is driver-pinned (TTM/imported pages, off the LRU and outside mlock() accounting — hence Mlocked=0), NOT RLIMIT_MEMLOCK-charged; `node_memory_SwapFree_bytes` = 2,148,204,544 (FULL — 0 B swap used ✓ engine line); `node_memory_HugePages_Total` = 0 (hugetlb pool absent, THP is the mechanism ✓); `node_disk_{read,write}_*_total` (+ discard family — the SN7100's IO is observable), `node_filesystem_*` (87 series — `/models` PV included), `node_network_speed_bytes`/`node_network_info` (NIC `enp191s0` + wifi `wlp192s0` onboard-class). `node_vmstat_*` exports ONLY `oom_kill, pgfault, pgmajfault, pgpgin, pgpgout, pswpin, pswpout` — **no compact_*/allocstall fields, no `node_pressure_*` PSI** (the §D10 statement holds for compaction; it was WRONG for AnonHugePages — corrected above). **GPU metrics: re-VERIFIED absent** — `count({__name__=~".*(amdgpu|gpu|dcgm|hwmon).*", cluster="gpu-ai"})` → EMPTY (no GPU exporter in the federated TSDB; `up{instance="ai-gpu"}` shows exactly four healthy targets: resources, kubelet, cadvisor, node_exporter). Clock-under-load stays sysfs/`/stats` owner-lane (unchanged); `node_boot_time_seconds` now gives the boot EPOCH from metrics (1794605659 = 21:34:19Z) — useful for correlating future rituals with LnkSta re-reads.
- **Link-state delta since §D10: NONE (expected unchanged, confirmed):** bootID unchanged (no new boot, so no new startup print exists to differ); pod `6h9cz` restartCount 0, same two `done` lines (`11.0` @1047, `16.4` @1707 — no overnight traffic, engine idle 3+ h); router `6796d989db-6qn8f` Running 2/2 on ai-gpu; node conditions all-False/Ready @00:46:50Z. The mid-session no-reboot check for any later ritual remains exactly one read: `GET /diagnostics` (hardware-reads-live) via port-forward (§D8.3).

### D11.4 THE GPU CLUSTER CONTRAST — both boxes now profiled

Node `gpu` (00:45Z re-read): `machineID 70d7c9a99fee402cb807a44cddccfc7d` and `systemUUID 70d7c9a9-9fee-402c-b807-a44cddccfc7d` — **THE SAME 16 bytes** (the §D6.2 VM/cloud-init identity signature re-confirmed: machine-id copied from DMI UUID, the pattern cloud images produce); `kernelVersion 7.3.0-1-default`, `osImage openSUSE Tumbleweed`, kubelet `v1.36.5+k3s1`; capacity `cpu: 13`, **`memory: 29994244Ki` == allocatable == 28.60 GiB** (live number re-confirmed this round); labels: the same bare k3s set, no NFD; daemonsets: device-plugin + node-exporter + alloy-logs + seaweedfs ×2 (no NFD). `gpu-llama-swap-…-rd4cj` Running 1/1, restarts 0, ~30 h — untouched invariant. **STATE.deferred[33] adjudication:** the live number (28.60 GiB, re-read 2026-11-14) stands against the 2026-10 "64 GiB RAM" four carriers; manufacturer/product stays NOT-DETERMINABLE from the cluster (same NFD absence), so the row's "exact spec OWED" stays owner-side — but the identity asymmetry is now on record: **ai-gpu = firmware-UUID + local machine-id (real hardware install pattern); gpu = UUID-copied machine-id (cloud-image/VM pattern)** — consistent with §D6.2's "VM vs bare-metal on the 780M box, undeterminable" and one notch closer to VM, still not proof.

### D11.5 BIOS/FIRMWARE VISIBLE VIA KUBLET? — NO.

Kubelet exposes no DMI/bios fields in any object checked (node.nodeInfo fields are the full surface; conditions/labels/annotations carry none — D11.1); k3s's node annotations carry only launch plumbing; no kubelet-config ConfigMap field names hardware. The firmware-adjacent evidence reachable from the cluster remains exactly what §D8/§D10 already quoted — the engine's own startup print of the kernel command line (`amd_iommu=off amdgpu.lockup_timeout=30000 ttm.page_pool_size=29360128 ttm.pages_limit=29360128`) and the boot-bandwidth kernel line as captured in the owner's paste. The engine's `system … | unknown | …` field is its container-side /proc read (no host distribution identity from inside the pod) — it is NOT a DMI slot and says nothing about the vendor. BIOS version, per-slot speed menus, EQ presets: **zero cluster surface; owner `dmidecode` + firmware setup only.**

### D11.6 WHAT THIS MEANS FOR THE RECORD (fold list, file:line)

1. **`RESEARCH.md:2379`** — the R9-S8 source row's parenthetical **"EVO-X3 (the lab's machine class)"** is an UNVERIFIED inference now contradicted by the owner's own platform word ("framework desktop 16"); it should be marked ASSUMPTION-WRONG-PENDING-CONFIRM (or re-worded "a Strix Halo-class host; exact board owed"), because everything downstream that trusts the board identity inherits it.
2. **`.agents/notes/radiance-host-tuning.md:108-112`** — the Rung-4 sentence ("explicit per-slot 'Gen4, not Auto' menu — and ONLY if such a menu exists on this board. The EVO-X3-class lead (R9-S17) is an SEO page; no primary GMKtec/AMD BIOS document exists") already self-flags the lead as untrustworthy; with the platform in doubt the sentence should be re-aimed at **Framework Desktop BIOS/EC docs in §R11** (their firmware ships via LVFS/`fwupdmgr` — a completely different, and much better documented, firmware surface than GMKtec's).
3. **DECISIONS.md:865-866** already records the SEO trust-flag — no edit needed, just §R11's re-aim.
4. **§D10's metrics claim** "node_exporter exports neither the vmstat-compact nor the AnonHugePages field" — HALF WRONG: AnonHugePages IS exported (queried here live); only the compact/allocstall/PSI families are genuinely absent. §D8.4-6's unit-decode conclusion (≈75 GiB THP-backed anon) is thereby UPGRADED from owner-paste to cluster-witnessed.
5. **§R10's power-ordering falsification (D10.8) is UNAFFECTED by the platform question** — the link read is the same garbage on ritual or non-ritual boots regardless of which board's BIOS is being reasoned about; the ladder (reseat → cable → dock-bypass) holds. What the identity changes is WHOSE docs the next research round should read, not what the engine printed.

### D11.7 PASTE-READY BLOCK FOR §R11 (coordinator hands verbatim)

```
PROVEN about ai-gpu (cluster-cited):
- SoC class: "AMD RYZEN AI MAX+ 395 w/ Radeon 8060S | 16 cores, 32 threads | RAM 125.08 GiB" (engine HARDWARE print, boot 4d6202d9) — a Strix Halo board; this string CANNOT distinguish Framework/GMKtec/Minisforum.
- OS/kernel: openSUSE Tumbleweed 20261024, kernel 7.3.0-1 (#1 SMP Mon Oct 19 2026), k3s v1.36.5 (nodeInfo + node_os_info/node_uname_info).
- Real-firmware signature: SMBIOS systemUUID edff8d86-8f81-f111-8010-9cbf0d01f966 embeds the NIC MAC 9c:bf:0d:01:f9:66 (enp191s0); machineID ≠ systemUUID (local machine-id).
- Storage: WD_BLACK SN7100 1TB at PCI c1:00.0 (node_disk_info path label) — sibling-ish of the dock chain c2..c4; parent bridge of c1 NOT readable from cluster.
- Dock chain link state: "00:03.1 8.0 GT/s x4 (max 16.0 GT/s x4) -> c2 -> c3 -> c4" — engine print, four boots incl one cold ritual boot.
- Live governor/freq: node_cpu_scaling_governor powersave=1 on 32/32; scaling freq idle avg 2.24 GHz.
NOT PROVEN (and NOT inferable from the cluster): manufacturer, product name, BIOS vendor/version/date, per-slot speed menus, whether c1:00.0 shares 00:03.x upstream.
Owner commands that settle it (read-only):
- sudo dmidecode -s system-manufacturer; sudo dmidecode -s system-product-name; sudo dmidecode -s system-version; sudo dmidecode -s bios-version; sudo dmidecode -s bios-release-date
- hostnamectl   (Chassis + Operating-System; static-hostname sometimes names the board)
- fwupdmgr get-devices 2>/dev/null | head -40   (Framework firmware ships via LVFS — a Framework board names itself here)
- sudo lspci -t -vvv | head -40 ; readlink -f /sys/block/nvme0n1/device   (does c1:00.0 sit under 00:03.x?)
- sudo lspci -vvv -s 00:00:03.1 | egrep 'LnkCap:|LnkSta:|LnkCtl2|SltCap'   (rung-2/3 witness after reseat/cable)
R11 targeting note: search "Framework Desktop + OCuLink + eGPU / DEG1 / R9700 Gen4" (community.frame.work dGPU thread is already in-corpus as R9-S2; daimonion's oculink doc carries a "Framework Desktop R9700 BAR capture" as R9-S10) — and re-price the BIOS-slot rung against Framework's actual firmware surface, NOT the GMKtec EVO-X3 SEO page.
```

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/EXPLORE.md (this §D11 append only)]
commands_run: [readonly-ai-gpu-kubernetes: resources_get Node(ai-gpu), resources_list DaemonSet + CustomResourceDefinition (fully-paged: 99 CRDs, zero feature-discovery), pods_list (fully-paged: 35 pods, ns default/kube-system/system-upgrade, zero nfd) + pods_list_in_namespace (paged), pods_log gpu-ai-radiance-5f7d6b95d7-6h9cz -c radiance (tail — no new traffic), pods_log device-plugin daemonset pod => pass; readonly-gpu-kubernetes: resources_get Node(gpu), resources_list DaemonSet, pods_list (fully-paged: 94 pods, same 3 ns, zero nfd) => pass; readonly-global-grafana query_prometheus ×14: node_boot_time_seconds, count by __name__ over instance ai-gpu (206 names), AnonHugePages/Mlocked/Unevictable/MemAvailable/SwapFree/HugePages_Total, node_cpu_scaling_governor (+==1 filter), scaling-freq avg, node_os_info/node_uname_info/node_disk_info/node_network_*, GPU-metric regex re-check (empty), up{instance="ai-gpu"} => pass; repo reads: RESEARCH §R10 platform passages (2379, 2113-2150, 2465-2515), radiance-host-tuning.md 100-120, DECISIONS grep, STATE.json deferred[33] + cardId via python walk => pass; pipeline_status (reap evidence), pipeline_claim after sanctioned human yes => ok]
deviations: none — read-only probes throughout; EXPLORE.md the only write, landed AFTER the human-authorized takeover (record: stale reap of the scout lane's claim at 00:45:29Z → step stopped → ONE sanctioned question → "yes" → re-claim card Na5LxMaY3ptABWhAy pipelines default, setId ba079f6f-78cd-46c1-98f0-aa9e330bbec0 — takeover recorded in the §D11 preamble; file byte-verified unmodified between attempts). Launch framing CONFIRMED where testable (§R9/R10 reasoned from GMKtec EVO-X3 with the "(the lab's machine class)" label at RESEARCH.md:2379 — now known unverified) and answered with the third option (NOT-DETERMINABLE from cluster). Self-corrections filed in D11.6(4)/D11.3: §D10's "AnonHugePages not exported" was my case-sensitive query miss — it exists and reads 75.26 GiB; compact/allocstall/PSI genuinely absent stands.
friction: PIPELINE LOCK LOST mid-write (claim reaped stale during the >2 h inter-round gap; edit guard blocked §D11 cleanly — file verified unmodified, zero duplicate risk); resolved per the C09 protocol (stop → one question → human yes → re-claim → write). Rounds idling >2 h lose the lock the same way — worth a heartbeat-keepalive or shorter round gaps for the long-running board loop; owner/coord judgment.
open_questions: none research-grade for the scout lane. For §R11 (pasteable per D11.7): (1) platform identity via the owner's dmidecode/fwupdmgr paste ("framework desktop 16" is currently owner's word, not a cluster fact); (2) whether c1:00.0 (the SN7100 carrying the 4 KiB-span n-gram reads) shares the 00:03.x upstream with the dock chain — owner lspci -t; (3) Framework Desktop firmware/BIOS docs to replace the EVO-X3 lead in tuning-note Rung 4.
next_suggested: coord: (a) hand §R11 the D11.7 block verbatim and require the dmidecode paste BEFORE research re-prices the BIOS rung; (b) fold the D11.6 correction list (RESEARCH:2379 label, tuning-note:108-112 re-aim, §D10 metric-claim half-correction); (c) note for the fleet docs: deploying NFD (system+pci sources) on gpu-ai would make future identity rounds cluster-answerable — human-owned, follow-up-card class. LOCK BOOKKEEPING: this scout session now HOLDS the `default`-pipeline claim on card Na5LxMaY3ptABWhAy (setId ba079f6f…, re-claimed under the human's takeover ruling) — the spawning coordinator should re-sync its claim state (or release) so the next board-coord tick does not see a surprise holder.

## §D54 — q27 lane grounding: what the shipped radiance chart assumes about one model per release (2026-11-15, scout round 12 — owner ask "add support for 27b in radiance"; HEAD 8b8746911)

Grounding target: a second model lane — `StillDeadcode/qwen3.8-27b-mxfp4` → `qwen3.8-27b-mxfp4.rad`, **19,377,119,232 B = 18.05 GiB**, lfs sha256 `a4908940c568f5f9dd24e88f46aefe9ac2ae07dfec023a2eaa1d14dcaa3df4f8`, ungated, **dense (not MoE), z-lab DFlash2 drafter merged IN-PACK** (no `--draft-model`; "the depth flag doesn't own the drafter"), vision tower in-pack, needs radiance ≥1.2.3 — RESEARCH.md:146 (pack table row), :153-156, TP2 doc §9 (:241-245). All file:line evidence below is from THIS worktree unless marked HEAD-only.

**TREE-STATE CAVEAT (read before planning):** the working-tree `DECISIONS.md` and `RESEARCH.md` are MODIFIED vs HEAD and are MISSING the newest entries — `git diff --stat` shows DECISIONS.md −67 lines (D52 + D53 gone from the tree) and RESEARCH.md −243 lines (§R17 gone). The content EXISTS at HEAD (`git show HEAD:.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/DECISIONS.md` lines 1594-1660 = D52/D53; same for RESEARCH.md §R17). Nothing else in either file differs. Do NOT read the truncation as "D52/D53 were retracted" — they are committed (784ff8dd6, 8b8746911); something in the worktree reverted the files. Flagged to coord; no repo edit made by the scout.

### A. `charts/radiance/values.yaml` in full (458 lines) — every fn-shaped key

Structure: header naming/internal law :1-12; the whole pod is app-template values (`app-template:` root) with NO chart-authored templates except NOTES.txt.

- **modelPath + pack ledger** :14-26 — verbatim:
  ```yaml
  modelPath: &modelPath /models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad
  ```
  with the ledger comment :16-25: "HF StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe, file qwen3.8-next-flash-fp8-iq4r-moe.rad, 121,969,901,568 bytes (113.60 GiB), lfs sha256 0af5e962…aa4d20, ungated (gated:False verified against the HF API)" + the anchor-trap law ("Anchors resolve per-document, so the C04 service block's modelPath re-pin does NOT reach this render").
- **sizing scalars (ledger-only ints, nothing consumes them)** :72-83: `guaranteedMemoryGi: 110`, `hostPoolMib: 43000`, `maxModelLen: 200000`, `maxNumSeqs: 8`, `cpuCores: 8`. The comment :28-35 states the law: "the args/resources carriers below hold the STRING FORM of each number and these ints are the LEDGER: test_ac3_scalar_splice … reds any half-move of one side". `--kv-resident 32768` is deliberately NOT a scalar ("recipe-constant, not a ladder rung", :76-82) + its mutual-exclusion-with-`--prefix-cache-mib` law.
- **serveArgs** :144-160 — verbatim, order as shipped:
  ```yaml
  serveArgs: &serveArgs
    ["--model", *modelPath,
     "--port", "8000",
     "--host", "::",
     "--tp", "1",
     "--max-model-len", "200000",
     "--max-num-seqs", "8",
     "--placement", "expert_tiered",
     "--host-pool-mib", "43000",
     "--gpu-headroom-mib", "96",
     "--kv-cache-dtype", "fp8",
     "--kv-resident", "32768",
     "--num-speculative-tokens", "3",
     "--max-num-batched-tokens", "4096",
     "--checkpoint-interval", "4096",
     "--ngram-placement", "disk",
     "--served-model-name", "qwen3.8-flash-next-radiance"]
  ```
  Absence law :131-143: NO `serve` verb, no `--expert-vs-cache-ratio`, no `--prefix-cache-mib`, **no `--api-key` (keyless D8)**; `--num-speculative-tokens 3` = "the pack's native MTP depth" (fn-specific rationale).
- **global / pod options** :162-210: `nameOverride: &chartName radiance`, `createDefaultServiceAccount: false`, `terminationGracePeriodSeconds: 180`, pod securityContext `runAsUser/runAsGroup/fsGroup: 65532`, `fsGroupChangePolicy: OnRootMismatch`, `supplementalGroups: [486]`, `seccompProfile: type: Unconfined` (io_uring law).
- **image pin** :224-242 — `repository: docker.io/stilldeadcode/radiance`, renovate comment :226, `tag: "1.17.0"`, `pullPolicy: IfNotPresent`; digest ledger comments: amd64 image manifest `sha256:6fb0e99b…cf5330` :234, tag index `sha256:c2acbaa3…7100` :238, tag-rebuild caution :239-242. `args: *serveArgs` :243 (the anchor splice). Ports http/8000 :244-247.
- **probes** :248-279 — all three `/health` on 8000, `custom: true`; startup `periodSeconds: 10`, `failureThreshold: 180` (180×10s = 30-min ceiling, :261-265); liveness/readiness plain httpGet :266-279.
- **resources (the fn pair, chart-BAKED claim)** :298-305 — verbatim:
  ```yaml
  requests:
    cpu: "8"
    memory: "110Gi"
    amd.com/gpu-r9700-1: "1"
  limits:
    cpu: "8"
    memory: "110Gi"
    amd.com/gpu-r9700-1: "1"
  ```
- **container securityContext** :306-320 — drop ALL + `add: [IPC_LOCK]`, `allowPrivilegeEscalation: false`, no privileged, no readOnlyRootFilesystem.
- **init container `radiance-fetch`** :321-412 — image `docker.io/curlimages/curl:8.23.0` + BusyBox-premise digest comment `sha256:3fb7e13e…` :333-342; the gate is a single literal shell script :343-382 — verbatim key lines:
  ```yaml
  LFS_SHA=0af5e96244e80c21ac8edca1719dae49b8a201b94a2f3994c3e24026ceaa4d20
  PACK=/models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad
  MARKER=/models/radiance/.staged-$LFS_SHA
  URL=https://huggingface.co/StillDeadcode/qwen3.8-next-flash-fp8-iq4r-moe/resolve/main/qwen3.8-next-flash-fp8-iq4r-moe.rad
  ```
  marker-skip :353-356, curl `--continue-at -` with rc-33 tolerance :358-367, the PORTABLE EQUALITY GATE :368-380 — `actual=$(sha256sum "$PACK" | cut -d' ' -f1)` ; `if [ "$actual" != "$LFS_SHA"]` → MISMATCH echo with both digests on one line → `exit 1` → `touch "$MARKER"` AFTER the guard (the `--check`-style forms are BANNED — D27/§D3b: BusyBox rejects GNU long options; rejected shapes `--check/--status/-cs/-c -s`). Init resources :383-404: `cpu: 1000m` / `memory: 2Gi` equal pair (C12 §D4 CPU-quota law); init securityContext :405-412 (non-privileged, drop ALL).
- **service** :414-425 — `service.radiance: controller: *chartName`, port 8000; comment: NO ingress anywhere, the trio law's proxy leg is SKIPPED by the internal-only ruling; client route = the llama-swap peers hop.
- **persistence** :427-458 — `models: existingClaim: llama-swap` (the shared 500Gi claim) with `advancedMounts.radiance.{radiance: /models RO, radiance-fetch: /models RW}` :437-445 (note the mount keys are the CONTROLLER name, stable per release), `shm: emptyDir medium Memory sizeLimit 2Gi` at /dev/shm :446-454, NO kfd/dri hostPath (:455-458, "test-pinned, load-bearing").
- **OVERRIDE_VIA placeholders: NONE in this chart** (D8: keyless ⇒ no `bitwardenIds`, no ExternalSecret leg, no custom-values entry — "the trio law's documented skip", header :8-12). The sentinels on the lane live only in the service file: `services/gpu-ai/prod/values.yaml:9-10` (`domain/clusterName: OVERRIDE_VIA_APPSET`) and `:145` (`hf-token: OVERRIDE_VIA_CUSTOM_VALUES`, llama-swap's, not radiance's).

### B. Is the chart single-model by construction? — NO (render-wise) / YES (contract-wise)

- `charts/radiance/templates/` contains ONLY `NOTES.txt` — every object renders from the vendored `app-template 5.0.1` (Chart.yaml:13-16 + charts/app-template-5.0.1.tgz). No chart template hardcodes model logic. NOTES.txt DOES carry fn prose (served id, peer URL shape, the 180.3 > 125.08 arithmetic, "Radiance (qwen3.8-flash-next profile)") — it is a render surface per release (wrong-but-inert text for q27; pinned only by test_contract's `svc.cluster.local:8000`-present + no-/v1 legs and test_resource_name_identity's GPU_CLAIM-in-NOTES leg, all model-agnostic).
- **How the pieces flow:** `modelPath` reaches args ONLY via the same-document YAML anchor `*modelPath` inside `serveArgs` (:145); `args: *serveArgs` (:243) materializes the list at values-PARSE time, so post-merge overlay edits to `app-template.modelPath` never move `--model` (the dual-edit law, overlay :752-760, guarded by test_serve_args.py:120-138). The sizing scalars reach NOTHING — they are test-enforced ledgers against the literal strings in the carriers (test_serve_args.py:63-82). The init's PACK path is a THIRD literal copy of modelPath inside the shell string (:349) + the URL (:351) a fourth (repo+file) — none anchored.
- **Empirical probe (read-only local render, this round):** rendering the SAME chart with release name `gpu-ai-radiance-q27` and a synthetic q27 overlay (full args-list replacement incl. `--api-key "$RADIANCE_API_KEY"`, `--prefix-cache-mib 4096`, no ngram/expert_tiered flags; `requests/limits {memory: 20Gi}` map overlay; init command replacement) — `helm template rc=0`, Service+Deployment both dedup to name `gpu-ai-radiance-q27` (the NOTES fullname law holds), args list fully replaced, memory overridden while `cpu: "8"` and `amd.com/gpu-r9700-1: "1"` are INHERITED from the chart (map deep-merge adds/updates keys, never removes; D26's null-drop means a claim CANNOT be retired by overlay). Probe script: /tmp/opencode/q27-probe/vals.yaml (outside the repo).
- **So a second release renders cleanly, but everything fn-specific must be REPLACED at overlay level or duplicated chart-side:** the args list (whole-list replacement — a list override in the overlay is exactly what the overlay's "SCALARS ONLY, never lists" law forbids, :743-746, because it truncates the chart seed — here truncation IS the intent, which the law does not distinguish), the init script (one pack, one sha, one marker, one URL — hardcoded to one .rad per release), modelPath re-pin, served id (`--served-model-name`), memory pair, and the NOTES prose. Already per-release-safe: controller key `radiance` (workload/service names dedup from the RELEASE name), advancedMounts keys, probes, claims (inherited — and that is exactly the problem in H).
- **What must become parameterised vs left alone:** the chart has zero per-model parameterisation by design — the single-source scalars are ledger-only and the suite pins chart-DEFAULTS. For a q27 lane the honest options are (a) a sibling chart directory `charts/radiance-q27` (own values + own suite, roster entry without a `chart:` override), (b) reuse `charts/radiance` via a roster `chart: radiance` override + a heavy `radiance-q27:` overlay doing list-replacements, or (c) parameterise the existing chart (anchors → inputs + a second evidence/serveArgs leg). The suite currently reads exactly ONE service subtree (`values.yaml.get("radiance")`, testlib:222-233) — options (b)/(c) need new test surface either way; the q27 release is INVISIBLE to charts/radiance/tests (blind, not red).

### C. How radiance is deployed (ApplicationSet chain + the trio-law file list)

- `services/gpu-ai/prod/templates/appset.yaml` — ONE ApplicationSet `gpu-ai-appset`, matrix generator `clusters × list` with exactly ONE list element `serviceName: gpu-ai` (:9-32), template name `{{ .serviceName }}` → one Application `gpu-ai` per cluster, namespace from cluster annotation default `default` (:39-42). Its templatePatch sources: the service path chart (`services/gpu-ai/prod`, :93-110) + the external `base` chart (:111-133) which consumes `services/gpu-ai/prod/values.yaml` and renders `charts/base/templates/appset-charts.yaml`.
- `charts/base/templates/appset-charts.yaml` — the REAL per-app generator: `range $appName, $chartConfig := .Values.charts` (:16-36); internal chart ⇒ path `{{ chart.repo.path }}/{{ if hasKey . "chart" }}{{ .chart }}{{ else }}{{ .appName }}{{ end }}` (:83); Application name `{{ .serviceName }}-{{ .appName }}` (:41); per-app values subtree = `merge $extraValues (index $.Values $appName)` (:34) — i.e. the overlay TOP-LEVEL KEY must equal the roster/appName key, and the `chart:` roster key lets an appName DIFFER from the chart directory — THAT is the second-release plumbing (analogous to nothing in-repo today; the TP2 doc §11 sketch :308-321 anticipated it and says "do not copy this sketch blind" — it names exactly "how one internal chart yields two Applications, the sibling service-values subtree, and the second peer key").
- Today's radiance entry: roster `charts: { radiance: { namespace: default, ServerSideApply: "false" } }` (services/gpu-ai/prod/values.yaml:78-80) → Application `gpu-ai-radiance`, destination namespace `default`, git path `charts/radiance`.
- **A `gpu-ai-radiance-q27` lane touches, per the trio law:** (1) CHART leg — either a new `charts/radiance-q27/` (chart entry) or reuse via roster `chart: radiance` (then the overlay block carries all the model truth); (2) APPLICATIONSET-VALUES leg — `services/gpu-ai/prod/values.yaml`: new roster entry `radiance-q27:` (+ its `radiance-q27:` top-level overlay subtree + the `peers.radiance-q27` block in the llama-swap config); (3) PROXY leg — SKIPPED, same documented internal-only ruling (the skip comment region is :99-105, which C04 mirrored for radiance; test_coexistence_wiring requires a radiance skip comment to stay). FOURTH leg becomes mandatory ONLY IF q27 ships a secret (its `--api-key`): `custom-values/gpu-ai/prod-values.yaml` gets `radiance-q27: bitwardenIds: …` — but see D: a test currently FORBIDS any "radiance" substring there.
- CI leg: `.github/workflows/radiance-render-tests.yaml` — triggers exactly `charts/radiance/**` + `services/gpu-ai/prod/values.yaml` + itself (test_contract pins this path SET exactly, test_contract.py:112-118); a new chart dir or a workflow change re-pins that leg; a second lane's render legs are not covered by this workflow (the extraction reads `d.get('radiance') or {}`).

### D. The service overlay (verbatim) + the auth question

- **roster entry** services/gpu-ai/prod/values.yaml:78-80:
  ```yaml
  radiance:
    namespace: default
    ServerSideApply: "false"
  ```
  preceded by the C04 law comment :68-77 ("the base appset renders a git-path source and derives the Application name serviceName+appName = gpu-ai-radiance — the host of the peers.radiance hop below; a release name drifting from it silently breaks that route… Keyless chart (D8): no bitwardenIds here, no custom-values leg").
- **top-level radiance overlay block** :752-760 — verbatim (only ONE override exists today):
  ```yaml
  radiance:
    app-template:
      modelPath: /models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad
  ```
  + the :761-769 law: sizing scalars "deliberately NOT re-pinned… re-pin one here only on a per-environment divergence the C06 runbook receipts names… NO rocrVisibleDevices re-pin". **The `amd.com/gpu-r9700-1` ADD is NOT here — the claim pair is chart-baked (charts/radiance/values.yaml:298-305); the overlay carries NO radiance memory override either (110Gi ships in the chart).** The overlay-ADD-vs-null law (:157-171, D26) explains why: overlays can ADD, never REMOVE or null.
- **llama-swap `gpu-8060s` ADD** :172-176:
  ```yaml
  resources:
    limits:
      amd.com/gpu-8060s: 1
    requests:
      amd.com/gpu-8060s: 1
  ```
- **peers blocks** (the pattern a `peers.radiance-q27` sibling clones): `peers.strata` :587-599 (proxy `http://gpu-ai-llama-swap-strata.default.svc.cluster.local:8080`, 5 models, timeouts responseHeader 1800 / connect 30, no filters) and `peers.radiance` :629-638 verbatim:
  ```yaml
  radiance:
    proxy: http://gpu-ai-radiance.default.svc.cluster.local:8000
    models:
      - qwen3.8-flash-next-radiance
    timeouts:
      responseHeader: 1800
      connect: 30
    filters:
      setParams:
        "priority?": 5
  ```
  (`peers.vllm` is the commented precedent :661-670; same shape.) Peer laws restated in-file: no `/v1` suffix, explicit `models` list (peers is not a blanket proxy), models stay OUT of the outer matrix (:610-614, test-pinned by test_coexistence_wiring.py:223-240), no apiKey (:614).
- **AUTH: there is NO radiance api key wired anywhere today.** Repo-wide grep for `RADIANCE_API_KEY` → zero hits. `charts/radiance` renders no Secret/ExternalSecret/ServiceAccount (values header :8-12; test_render.py:200-210 bars those KINDS; test_contract.py:88-98 bars the TOKENS `ExternalSecret|bitwarden|secretKeyRef` in templates/; testlib ABSENT_FLAGS :111-116 bans BOTH `--api-key` AND `--api-key-env` from the rendered args). fn handles auth today by being KEYLESS + cluster-internal (D8) — the peers hop is the sole route and `/health` (the probe path) is key-EXEMPT per RESEARCH :558-568. RESEARCH :589-591 records the engine's two forms: `--api-key` (Bearer/X-Api-Key) or `--api-key-env NAME` ("preferred; argv is world-readable"). Consequences for the owner's `--api-key "$RADIANCE_API_KEY"` sketch: (i) the `$VAR` must expand INSIDE the pod (helm bakes the literal string — my probe's `--api-key $RADIANCE_API_KEY` arg would pass the raw text without env/`$(...)`+shell form), (ii) a real key needs the env secretKeyRef + bitwardenIds + custom-values UUID chain, (iii) that collides with FOUR currently-green test legs + the D8 ruling itself ⇒ a DECISIONS-line change, not a values edit. (Keyless cluster-internal is the shipped posture; q27 could ride it too — the owner's flag list is a question, not a constraint to honor blindly.)

### E. The catalog / ids table

- Home: `.opencode/opencode.jsonc`, provider `gpu-ai` (:75-92; `baseURL: https://llama.spencerslab.com/v1` — the OUTER llama-swap host; hand-managed, NOT rulesync-generated per AGENTS.md). Current radiance rows :716-735 verbatim:
  ```jsonc
  "qwen3.8-flash-next-radiance":        { "modelID": "qwen3.8-flash-next-radiance", "name": "Qwen 3.8 Flash Next (Radiance, R9700) - default priority",
    "capabilities": { "input": ["text","image"], "output": ["text"], "tools": true }, "limit": { "context": 200000 }, "body": { "priority": 5 } },
  "qwen3.8-flash-next-radiance-urgent": { "modelID": "qwen3.8-flash-next-radiance", … "body": { "priority": 9 } },
  "qwen3.8-flash-next-radiance-low":    { "modelID": "qwen3.8-flash-next-radiance", … "body": { "priority": 1 } },
  ```
  The why-comment :702-715: higher-wins 9/5/1, "the floor is server-side in peers.radiance's filters.setParams", `context 200000 = what the pod serves (--max-model-len)`, Q8 [text,image] vision claim.
- **How a row points at a backend: it does not carry a URL/peer reference.** The row key/modelID is the wire model name; the outer llama-swap resolves it against its `models`+`peers.*.models` tables — so a q27 row set is only routable once `peers.radiance-q27.models` (or peers.radiance's extended list) contains the id. That seam is where the tests bite (F).
- `-strix` rows: NONE in the catalog (grep `strix` .opencode/opencode.jsonc → zero). The strix sibling lives ONLY in `peers.strata.models` (`qwen3.8-flash-next-strata-strix`, values.yaml:594) and as prose: .rulesync/skills/pipeline-models/SKILL.md:59 ("the `-strix` sibling is a manual/secondary fallback only, never an agent route"). So no strix catalog precedent to clone — q27 clones the fn radiance trio.
- What `qwen3.8-27b-radiance` + `-urgent`/`-low` need: shared modelID + body.priority 9/5/1 (TP2 doc §11 item 6, :323-329), `limit.context` = THAT pod's served truth (its `--max-model-len`, e.g. 200000 as in RESEARCH :542-543's q27 profile), capabilities per pack (vision tower verified in-pack :154-156 ⇒ the Q8 pattern applies), plus the pipeline-models skill tables (.rulesync source :45-47 class rows + :60-61 favorited row — rulesync-generated twin at .opencode/skills/pipeline-models/SKILL.md; rulesync generate + M6/M8 legs re-pin).

### F. Tests layout + the same-wave red list (§12.14-era frozen tokens)

`charts/radiance/tests/` — **46 tests** (collect: test_contract 8, test_peers_stability 3, test_render 21, test_renovate_ledger 4, test_resource_name_identity 4, test_serve_args 6). All legs render the CHART (defaults or the one `radiance` subtree) — per-release q27 truth is untested by them; per F-G below, several CROSS-SURFACE legs reddens on a third peer/catalog row.

Hardcoded-fn tokens that freeze the lane (file:line → frozen token):
- charts/radiance/tests/radiance_testlib.py:42-104 — `SERVED_ID="qwen3.8-flash-next-radiance"`, `MODEL_PATH`, `PACK_REPO/PACK_BYTES=121_969_901_568/PACK_LFS_SHA=0af5e962…`, `SCALARS {guaranteedMemoryGi:110, hostPoolMib:43000, maxModelLen:200000, maxNumSeqs:8, cpuCores:8}`, `KV_RESIDENT_TOKENS=32768`, `FULL_PROFILE` (every flag/value incl. `--ngram-placement disk`, `--placement expert_tiered`, `--gpu-headroom-mib 96`, `--checkpoint-interval 4096`), `ABSENT_FLAGS` (`--api-key`, `--api-key-env`, `--prefix-cache-mib`, `--expert-vs-cache-ratio`), `INIT_PAIR {cpu 1000m, memory 2Gi}`, `IMAGE_REPO/TAG/AMD64_IMAGE_MANIFEST/INDEX_DIGEST`, `PEER_URL=http://gpu-ai-radiance.default.svc.cluster.local:8000`.
- test_serve_args.py:46-117 set-equality (EXACT: an extra flag is as red as a missing one) + scalar-splice:63-82 (changing `guaranteedMemoryGi` without moving both resource strings reddens) + :141-184 `test_scalars_commented_with_the_arithmetic` — the values.yaml COMMENT must contain `71.04`, owner-ruling/D29, `110+64+6.3`/`180.3>125.08`+Pending, `115.28`/`9.80`, `38.96`+`>=4`, "prints its own budget". ANY memory re-ruling reddens this leg until the comment moves same-wave.
- test_render.py:132-138 exact pair `{cpu "8", memory 110Gi, gpu-r9700-1 1}`; :200-210 no Ingress/Secret/ExternalSecret/ServiceAccount kinds; :281-317 + :321-461 init/staging gate shape (PACK marker `.staged-0af5e962`, the equality-gate tokens, REJECTED `--check/--status/-cs/-c -s`, curl `--continue-at -` byte-kept, BusyBox-family pins); :165-178 Recreate+180s+no nodeSelector; :213-224 exactly one Service/one Deployment (per render).
- test_peers_stability.py:32-66 — served id == evidence `models_allowed == [SERVED_ID]` and `proxy == PEER_URL`.
- test_resource_name_identity.py — claims == exactly {R9700 pool}; pools disjoint; gpu-cluster bare-name shield; NOTES carries the pool name.
- test_renovate_ledger.py:96-117 — the pack ledger comment must stay in values.yaml verbatim-complete (repo, `121,969,901,568`, lfs sha, "ungated").
- charts/llama-swap/tests: `evidence/radiance-peers-expected.yaml` :33-46 — proxy/timeout/floor/model EXACT, `models_states: - [qwen3.8-flash-next-radiance]` APPEND-ONLY ("dev must not edit this file" :5-6 — a q27 peer join needs a NEW per-key evidence file per the D13 per-peer law, AND the models_states comment explicitly anticipates "a second radiance arena… would be the next appended state" for a SAME-peer arena, not a new peer key); `test_config_parity.py:333-337` — **the peer-key wave law `wave in ({"strata"}, {"strata","radiance"})`: a THIRD peer key is RED ("a live vllm peer or a third phantom is drift")**; `test_radiance_peer.py:120-138` — golden peers keys == {strata, radiance} EXACT + golden-vs-render equality (golden/gpu-ai.config.yaml:1359-1370 re-capture paired obligation); `test_coexistence_wiring.py:215-222` — `"radiance" not in custom-values text.lower()`: a q27 bitwardenIds key REDDENS it (the D8 no-secrets law made mechanical); `test_catalog_contract.py:196-206` — phantom allowlist reads `peers.radiance.models` ONLY: `qwen3.8-27b-radiance` catalog rows routed via a NEW `peers.radiance-q27` are PHANTOM-RED until the leg is extended (routing by a second wire id inside the existing peer would pass the phantom leg but red the `models_allowed` exact-equality in the radiance evidence).
- tests/pipeline-models/surface.sh:791-830 — M8-A trio HOLD (ids, modelID, priorities, ctx, caps), **M8-A2 DELTA equality: `added` must equal EXACTLY the radiance trio vs the frozen 86-key `CF143_BASE_KEYS`** — +3 q27 rows red this leg until the base/delta is re-frozen by the test lane; :861-872 M8-D negative needle (wire id must not become a local id — clones needed per q27 id); :897-927 the pipeline-models class-table + favorited-row needles.
- tests/notes/radiance-runbook.sh — T2: "EXACTLY ONE" fenced `--served-model-name qwen3.8-flash-next-radiance` block whose flag/value multiset EQUALS the chart serveArgs, with scalars 43000/200000/8/110 needle-pinned scope-aware both sides (header :23-33). A q27 args doc inside that runbook reds the one-block law; a q27 runbook wants its OWN contract script (the C06 idiom). Status today: **5 ok, green**.
- tests/notes/radiance-host-tuning.sh — T2 family tokens + T4 two-doc gate coherence; the §12.14 frozen set (charts/llama-swap/tests/TEST_SPEC.md:4347+, row "frozen set (AC4)"): headings×15 order, envelope pair halves, sums `110/71.04/118.72/115.28/9.80/38.96`. **guaranteedMemoryGi changes = same-wave docs+arm move (D36(4)); the scripts are TEST-lane-owned — dev/review edit prose docs, never the arms (the C12/C13 rounds routed every needle change back to a test session).** Status today: **4 ok, green**.
- tests/notes/radiance-tp2.sh — pins the TP2 doc structure/needles incl. §11 sketch tokens (`radiance-tp2` names, `R9700_CLAIM="amd.com/gpu-r9700-1"` bash twin :33-36). Status: **3 ok, green**. A q27 doc that edits TP2 §9/§11 strings re-pins this suite same-wave.
- tests/services/amd-gpu-naming.sh — pool-name census (NON-FLIP witnesses); q27 with NO rename → green, touched only if naming moves.
- What a q27 variant ADDS test-wise (per lane): the memory pair at the q27 value, its own arg list (no `--ngram-placement`/no `--placement expert_tiered` — dense has no experts; `--prefix-cache-mib` is legal for q27 since q27 ships WITHOUT `--kv-resident`, per RESEARCH :542-546), pack pin (19,377,119,232 B / a4908940…), no-ngram + served-id/peer/catalog rows, the third-peer-wave re-pin in test_config_parity, a per-key evidence file, catalog delta re-freeze.

### G. The capacity ruling + q27 history, quoted for the planner

- **TP2 doc §9 (.agents/notes/radiance-second-gpu-tp2.md:233-255)**: "With one card the honest choices were one resident lane or a swap-child, because fn TP1 alone consumes ~28–30 GiB of the ~31.86 GiB usable card and **two peer pods on one GPU is NOT feasible for fn+q27** — capacity-ruled, 'do not plan it' (RQ5, Structural options D). That single-card ruling lifts with a second card: two peer pods, one card each, each claiming 1 from the same `gpu-r9700-1` pool… the retired vLLM 27B lane (C01's commented disable) can return as **radiance q27** on the second card — pack `qwen3.8-27b-mxfp4.rad`, 18.05 GiB (19,377,119,232 B), lfs `a4908940…`, ungated, with the z-lab DFlash2 drafter merged in-pack (no `--draft-model`, it is a parse error)… q27 TP1 fits one 32 GiB card outright (weights ~18.07 + KV ~12.48 receipt class; host side ≈8.5 GiB)… Priority stays higher-wins 9/5/1 across BOTH pods… Host-RAM honesty: TP2 relieves VRAM contention, not the RAM pin ceiling — pins still sum against the ≈120.6 GiB cap formula with the 4-GiB-free rule."
- **§11 items 5-6 (:299-329)** — the `radiance-q27`-shaped sketch: "Second lane (q27 pod beside fn): a second release of the same chart. SKETCH — the TP2 ticket resolves the exact appset plumbing (how one internal chart yields two Applications, the sibling service-values subtree, and the second peer key) against `charts/base`'s appset shapes; do not copy this sketch blind: `charts: { …, radiance-tp2: {namespace: default, ServerSideApply: "false"} }` · `radiance-tp2:` top-level block, scalars only (deep-merge REPLACE law), `modelPath` re-pin to the q27 `.rad` · peer addition as a `peers.radiance-tp2` block beside the existing two (proxy to the new service on 8000, NO `/v1` suffix, timeouts 1800/30, `priority?` floor 5) · its own per-peer evidence file joins the D13 per-key law." + "**Catalog second row**: for a q27 lane, add rows under the honest-id law (e.g. `qwen3.8-27b-radiance` + `-urgent`/`-low` wire-siblings sharing the modelID, `body.priority` 9/5/1, `limit.context` = that pod's served truth) via the rulesync source" [note: the CATALOG rows themselves land in .opencode/opencode.jsonc (hand-managed) — only the pipeline-models SKILL is rulesync; §11's sentence compresses both].
- **§12 (:332-359)** — coexistence: strata's hostPath arenas sit physically inside the pool-named card ("naming is scheduler bookkeeping, not VRAM arbitration"); a second R9700 dissolves the card contention; "at the shipped 110 (D29) strata can never co-reside beside a scheduled 110-radiance — 110 + 64 + 6.3 = 180.3 > 125.08, and a second card adds VRAM, not host RAM"; TP2 re-pins host demand DOWN ~3× (pool 12288×2, mirror gone ⇒ ~30-35 GiB class) and at THAT number "strata co-existence may arithmetically RE-OPEN (~35 + 64 + 4.1 + 1.2 ≈ 104 ≤ 125.08)" — rides the cutover ticket.
- **RESEARCH q27 mentions**: TLDR :34-35 ("8 sessions on one R9700 is a q27-shaped problem (solved, with receipts)"); pack table :146; pack facts :153-156; RQ5 :594-646 — the three structural options with the closing finding "two peer radiance pods on one GPU is NOT feasible for fn+q27 (capacity), and … fn-tp1-ram profile + q27 co-residency blows the RAM budget too (105–110 pinned + 8.5)"; Structural options D :765-766 "ruled out by capacity (fn ~28–30 GiB of the 31.86 GiB usable) — do not plan it"; serving envelope q27 row :700-707 (flags `--tp 1 --max-model-len 200000 --kv-cache-dtype fp8 --max-num-seqs 8 [--prefix-cache-mib 4096]`, host RAM ≈8.5 GiB / 7.89 pinned, "**8 sessions: this is the session-capable lane** (admission ceiling = 8×max-num-seqs queued → 429)", link-immune x4 −5%); :572-574 (q27 loads 18 GiB sub-minute); R14/R15 q27 rows :3456/3473/3487-3498 (q27 dense is the ONLY single-R9700 124-130 t/s class), :3584 (`--num-speculative-tokens 7` is q27-dense-recipe, "do not copy q27's 7 onto fn"), :3734 (ngram-ram as the fn+q27 co-residency lever + `amdgpu.no_system_mem_limit=1`), :3839 ("The owner's '70+ on one R9700' is… the dense q27 lane").
- **DECISIONS**: **D3** (worktree :34-42): rejected "q27-only lane (card says radiance replaces STRATA = the flash-next lane), fn+q27 co-residency (ruled out by capacity, RESEARCH option D)". **D21** (:212-238): B1 shield — gpu cluster keeps bare `amd.com/gpu` (external single-naming plugin), product naming + the named pools are gpu-ai-only, same-wave/lockstep-revert law; mechanism later SUPERSEDED by D26 (carrier flips, intent stands). **D24** (:296-335): the patched amdgpu.ids table → `amd.com/gpu-r9700-1`; "THE APU-ROWS-MUST-CARRY LAW" (dropping any 1586 row strands gpu-8060s); MINIMALITY LAW + "TP2 CARDS REQUIRE TABLE RE-VERIFICATION BEFORE SCHEDULING TRUST"; FROZEN: gpu-8060s, peers/catalog (engine ids ≠ GPU names). **D26** (:374-417): null-drop ⇒ overlays ADD only; extended resources take positive integers, `null`/`0` retirements are banned patterns — this is why a second release CANNOT drop the inherited r9700-1 claim. **D29** (:595-614): 110 = owner ruling "110 GiB (your figure)"; strata-DOWN 115.28 ≤ 125.08 (free 9.80), strata-UP 180.3 > 125.08 designed Pending, handshake INVERTED at 110 = "the cutover is now a real either/or"; RAM-ngram tier dead (118.72 > 110). **D31** (:715-745): NO selfHeal on gpu-ai children (sync is manual) — "strata's `replicas: 0` survives ONLY because `gpu-ai-llama-swap` has not been synced (git renders `replicas: 1` by app-template default…) ⇒ syncing that app IS step 10's restore moment". **D52/D53 (HEAD-only, tree :1594 absent — see caveat)**: D52 disposed the APU-hide question ("the cost is the router… its one repo claimant is the llama-swap overlay (services/gpu-ai/prod/values.yaml:174,176) which strands at its next restart — a C10 replay"; "strata co-residency arithmetic re-opens *without* hiding — ~35 + 64 + 4.1 + 1.2 ≈ 111.2 ≤ 125.08 — the door being held shut is THE 110 PAIR"); D53 owner override ("Tell me how to disable the APU!!!") with the code-first/boot-time-only/rollback-rehearsed conditions. **DECISIONS Deferred (:1595, :1629)**: "Strata cutover/retirement — OWNER's metrics decision… the cutover no longer gates the profile — it only ends the scale-down dance"; **"q27-on-radiance second lane + IQR-V4 pack adoption — unlocks with card 2 (TP2) / post-cutover (C03 doc)"** — the owner's ask today is the activation of exactly this deferred line.

### H. Node/scheduler arithmetic as shipped

- fn today: Guaranteed pair `{cpu 8, memory 110Gi, amd.com/gpu-r9700-1 1}` (chart values:298-305). Node `ai-gpu` allocatable **125.08 GiB** (capacity==allocatable, §D6.2; STATE C12-r2 reviewer read: exactly 131,151,320 Ki). Non-radiance terms on the node when strata is DOWN: router 4.125 + system floor 1.158 (radiance_testlib.py:68-70) ⇒ fn leaves **125.08 − 110 − 4.125 − 1.158 = 9.797 ≈ 9.80 GiB** of schedulable host memory. A hypothetical q27 Guaranteed pair at X schedules ONLY while X ≤ 9.8 GiB — RESEARCH's q27 host receipt class is ≈8.5 GiB (7.89 pinned, :702-707) ⇒ arithmetically it fits with ~1.3 GiB to spare, but that violates the lane's own budget-line culture ("limit − printed pinned ≥ 4", D28 class law) and leaves the node free at 1.3 GiB — and it requires strata to stay DOWN (strata's 64Gi request + fn's 110 + q27 = 184+ ≫ 125.08). Honest statement for the plan: **host RAM is the binding side of a same-node fn+q27; the TP2 doc §9's "card-per-pod" unlock is about VRAM; a second card adds VRAM, NOT host RAM (§12).**
- GPU pool exclusivity AS CODE: both releases render `amd.com/gpu-r9700-1: "1"` in requests+limits because the claim is chart-baked and the overlay chain can only ADD (D26). The pool holds exactly ONE device on this node (chart values:289-293 "the pool holds exactly one device"; amd-gpu patched table). So a q27 pod scheduled beside fn asks 1 from a capacity-1 pool ⇒ **the second pod sits Pending forever ("Insufficient amd.com/gpu-r9700-1")** — my B-probe render confirms the claim is inherited unchanged at 20Gi memory. Two pods become schedulable only when the pool advertises 2 (a second card with the same (7551,C0) sysfs pair — TP2 doc §11 item 4's RE-VERIFICATION LAW), which is hardware the owner has not installed yet (the current box has one R9700 + the Strix APU in its own pool).
- strata: `replicas` appears NOWHERE in charts/llama-swap/values.yaml, services/gpu-ai/prod/values.yaml or charts/radiance/values.yaml (grep) ⇒ app-template default renders `replicas: 1` — the live scale-down to 0 is out-of-git manual drift (D31). strata's memory REQUEST lives at charts/llama-swap/values.yaml:1288-1290 (`requests: cpu 8 / memory 64Gi`), its limit at :1340-1341 (`limits: memory 110Gi`) — limit-only pair ⇒ strata is Burstable by design; the "requests stay 64Gi, so the scheduler can still pack a neighbour" comment is at :1337-1339.

### I. STATE.json (as of this round)

`plan_status: "complete"` (note: FINAL review round 6 APPROVED, fourteen chunks, ten review rounds; the remaining items are owner hardware rungs + the docs-only landing delta + card triage). Chunks C01–C14 ALL `done` (waves 1→11, C13/C14 the docs micro-rounds; `current_wave: 11`, `updated_at: 2026-11-14T02:30:00+00:00`). `blocked: []`. `deferred: 38 rows` — q27-relevant: [8] the TP2 co-residency consequence of §R8-Q5 (110 strands nothing at TP2, ~30-35 GiB class), [0] the D45 follow-ups (tuning-note re-points, `powerprofilesctl` experiment, the ≥2000-token probe), [34] gpu-box spec drift (28.60 GiB node ≠ 64 GiB), [36] the fleet selfHeal-prose card, [37] card #1 re-publish owed (the TP2 doc — which §11/§12 edits would touch AGAIN). **Next free chunk id: `C15`.** The cutover decision (fn-vs-strata either/or at 110) is the Deferred head row (:1595) and D50 already framed "the owner must pick one engine" — a q27 lane intensifies it: three lanes, one node, one card.

### §D54 summary — what must change to ship a q27 lane / what hard-blocks two engines on one card

MUST CHANGE (plan input, no verdicts here): the second-lane plumbing itself (roster `chart: radiance` override vs sibling chart — B/C), every fn-literal in values (args list, init pack/sha/marker/URL, memory pair, served id, NOTES prose), a new per-key peers evidence file + `peers.radiance-q27` block + golden re-capture, catalog trio rows + delta/base re-freeze (M8-A2) + pipeline-models tables, the test_config_parity third-peer wave law, test_catalog_contract phantom-routing leg, a q27 runbook/contract lane (the one-fenced-block law), and — if any key ships — the D8 keyless ruling + FOUR secret-ban legs (D). The api-key question deserves an owner answer: keyless (match fn) vs `--api-key-env` (RESEARCH-preferred form if a key is wanted).

HARD-BLOCKS TODAY (capacity + code, independent of effort): ONE R9700 device in the `gpu-r9700-1` pool ⇒ two pods claiming it = Pending-forever (claim chart-baked, overlays cannot subtract — D26); fn TP1 eats ~28-30/31.86 GiB VRAM ⇒ fn+q27 co-resident on one card is capacity-ruled OUT (RQ5 option D, "do not plan it"); host RAM at the shipped 110 leaves 9.80 GiB ⇒ a same-node q27 pair is at the edge of impossible with the ≥4-slack law, and strata-up makes everything Pending (180.3 > 125.08 — the designed handshake). The second lane UNLOCKS with the second physical card (TP2 / card AD-144) — precisely the deferred row DECISIONS:1629 recorded.

