# RESEARCH — cf-105 vLLM v0.33.0 zero-device import crash (RQ1–RQ3)

**Commissioned by** coord (chat run, no board card), 2026-11-07, by
`agent-research`. Standalone research thread in this ticket folder (separate
from the folder's priority-class plan of record). Answers the coordinator's
RQ1/RQ2/RQ3 on the vLLM v0.33.0 `No CUDA GPUs are available` import-time
crashloop on node `ai-gpu`. Method: STORM — 4 grounded perspectives
(hip-runtime, k8s-plumbing, cdi-operator, rdna-community) over live web
research (sources [1]–[34], "Sources" section) + repo/cluster-grounded facts
([G1]–[G8], probed live 2026-11-07 via readonly k8s MCP + git; no pod-exec
tier exists on any agent tier). Parent-ticket grounding cited, not
re-derived: cf-105 `RESEARCH.md` R1/V2 (parent folder
`2026/2026-11-cf-105-feat-implement-vllm/`), `EXPLORE.md` §1/§7/§8,
`DECISIONS.md` D2/D5.

## TL;DR (5 lines)
1. The crash means "in-container HSA/KFD enumeration returned 0 devices"; it
   fires before any arch-specific code, so arch mismatch and the
   ROCR_VISIBLE_DEVICES value are ruled out as root causes (both remain
   relevant as chip-selection levers, not as crash causes).
2. Both deployed shapes are equal-or-strict-superset of the official vLLM
   ROCm container shape, so the pod-spec layer is not the disease: a
   maximally privileged pod with the whole host /dev still sees 0 devices.
3. Convergent evidence points at the HOST layer: node `ai-gpu` runs an
   unsupported rolling openSUSE TW kernel 7.3.0 (openSUSE is on no ROCm
   support list for these GPUs), the live device-plugin log shows the
   kernel-7.x KFD-topology break documented by a same-plugin/same-hardware
   community report (fix: LTS kernel pin) [17], and openSUSE's own SDB says
   ROCm-in-containers on TW requires kernel-longterm + amdgpu-dkms [26][29].
4. Shape A additionally failed on the plugin's broken KFD-node mapping
   (both cards -> nodeId 0; wrong card allocated; the allocation is not
   usable for chip targeting even after a host fix) [15][16][32].
5. Fix ranking: (1) host kernel/driver fix — owner-run, the only option that
   addresses the leading root cause; (2) keep shape B + pin chip by UUID
   (values-only, once the on-target gate runs) [11][32]; (3) plugin hygiene
   (1.31.0.12 + privileged plugin per upstream manifest); (4) diagnostic
   AMD_LOG_LEVEL env; (5) CDI as a later consolidation, GPU Operator not now,
   8060S retarget only as a last-resort fallback.

## GROUNDED facts (live probes 2026-11-07 01:50-02:00 UTC + git; do not re-gather)

- **[G1]** Live crashing pod `gpu-ai-vllm-54fbb97d8-jrwzs` (default ns, node
  ai-gpu, created 2026-11-07T01:39:40Z, CrashLoopBackOff, restartCount 6):
  shape B exactly — `privileged: true`; hostPath `/dev/kfd` (CharDevice) +
  `/dev/dri` (Directory) at same paths; `ROCR_VISIBLE_DEVICES=0`,
  `TRITON_CACHE_DIR=/data/triton`, `HUGGINGFACE_HUB_CACHE=/data/hf`,
  `VLLM_SERVER_DEV_MODE=1`; `hostIPC: true`; `runAsGroup: 44`; caps add
  `[SYS_PTRACE]`; seccomp `Unconfined`; 8Gi Memory emptyDir at /dev/shm;
  limits mem 32Gi / requests cpu 4 mem 16Gi; NO `amd.com/gpu`; image
  `ghcr.io/ownyourio/vllm-rocm:main`; PVCs `vllm-cache`->/data,
  `llama-swap`->/models (RO); startupProbe httpGet /health:8000 60s+10sx90.
  Crash (current AND previous log, identical): 3x
  `Failed to open scsi_host root directory, while DiscoverBRCMswitchDevices
  and graceful exit./sys/class/scsi_host.: No such file or directory`, then
  traceback `vllm/platforms/rocm.py:215 _GCN_ARCH = _get_gcn_arch()` ->
  `rocm.py:209 torch.cuda.get_device_properties("cuda").gcnArchName` ->
  `torch/cuda/__init__.py:747 _lazy_init` -> `:539 torch._C._cuda_init()` ->
  `RuntimeError: No CUDA GPUs are available`. Serve args include
  `--watermark 0.05` — a valid v0.33.0 scheduler arg (KV-preemption headroom;
  verified in v0.33.0 `arg_utils.py`: field
  `watermark: float = SchedulerConfig.watermark`, registered `--watermark`)
  [33] — not the next failure.
- **[G2]** Device plugin pod `amd-gpu-device-plugin-daemonset-knf6w`
  (default ns, 28 d old, restarts 15, last 3h37m ago):
  `rocm/k8s-device-plugin:1.31.0.9`, non-privileged, drops ALL caps, mounts
  hostPath whole `/sys` + kubelet dp dir + `/var/lib/amd-metrics-exporter/`.
  Log: `Found 2 AMDGPUs`; devices map
  `0000:c4:00.0: {card:1 renderD:128 nodeId:0 devID:(empty) numaNode:-1}` and
  `0000:c5:00.0: {card:2 renderD:129 nodeId:0 devID:(empty) numaNode:-1}`;
  `E Topology property not found. Regex: drm_render_minor\s(\d+)` for KFD
  topology nodes 1 AND 2 (node 0 = CPU node, no error);
  `E allocator init failed ... Besteffort Policy init failed to initialize
  p2pWeights -> Falling back to kubelet default allocation`; allocations:
  c4 -> llama-swap (22:09, 23:23), c5 -> vLLM (00:01).
- **[G3]** Node `ai-gpu`: k3s v1.36.5+k3s1, containerd 2.3.4-k3s1.36,
  openSUSE Tumbleweed, kernel **7.3.0-1-default**, 32 CPU / ~128 GiB,
  allocatable `amd.com/gpu: 2`.
- **[G4]** Working control pods, same node, 0 restarts:
  `gpu-ai-llama-swap-strata-...` (privileged, hostPath /dev/kfd CharDevice +
  /dev/dri Directory, 2Gi shm, NO hostIPC/caps/seccompProfile — **Vulkan
  engine, no KFD/HIP dependency**) and `gpu-ai-llama-swap-...` main
  (non-priv, drop ALL, `amd.com/gpu: 1` req+lim — **Vulkan llama.cpp**).
  **No running workload on this node has ever exercised KFD/HIP.**
- **[G5]** Repo history (branch `fix-vllm-common-loader`): `b81faa9e5`
  (2026-11-07 01:01Z, deploy agent, owner-ruled) introduced shape B —
  message: "strata device idiom — privileged hostPath /dev/kfd+/dev/dri,
  drop amd.com/gpu (plugin allocated the 8060S and injected no visible
  devices)"; `88c896cd0` (01:37Z) dropped `allowPrivilegeEscalation: false`
  (k8s rejects it alongside `privileged: true`). The shape-A pod requested
  `amd.com/gpu: 1` (limits) + the upstream non-privileged securityContext
  (seccomp Unconfined, runAsGroup 44, SYS_PTRACE, hostIPC, 8Gi shm) —
  i.e. shape A = official shape + `amd.com/gpu` request [15][16][19].
- **[G6]** Parent-ticket facts (cited, not re-derived): R1 verdict — R9700
  GO (gfx1201, 32 GB GDDR6 @ 640 GB/s, ~40 tok/s ceiling), 8060S MARGINAL
  (~16 tok/s single-stream, no MTP on AMD, RAM-coexistence risk on the
  125 GiB node); V2 — `ROCR_VISIBLE_DEVICES` is still the correct targeting
  var under ROCm 10 (device index OR UUID; value = host enumeration);
  index 0 = R9700 is the repo assumption, gated on-target by the C06
  rocminfo step — NOT yet confirmed on target; D2 (chip = R9700, env
  spelling is a values key), D5 (`--enable-sleep-mode` on + operator
  time-sharing), EXPLORE §7 (no agent pod-exec tier), §8.7 (plugin is
  count-only; chip targeting via env or privileged hostPath).
- **[G7]** Base-image arch facts (repo-grounded, `containers/vllm-rocm/README.md`
   "Base-image facts (pinned image registry data, probed 2026-11-05)"): the
   v0.33.0-rocm100 base's `PYTORCH_ROCM_ARCH` includes gfx1201+gfx1151 (both
   chips on this node); `AITER_ROCM_ARCH` is CDNA-only, hence the baked
   `VLLM_ROCM_USE_AITER=0`; base entrypoint `["vllm","serve"]`, overlay user
   uid 65532 over a root base.
- **[G8]** The ROCm device plugin is REPO-MANAGED: the external `amd-gpu`
   Helm chart (`repository: https://rocm.github.io/k8s-device-plugin/`,
   version 0.22.0, namespace default, no image override) in
   `services/gpu-ai/prod/values.yaml` — the environment serving node
   ai-gpu; the sibling entry in `services/gpu/prod/values.yaml` is a
   different cluster. The chart default is what G2's pod runs (1.31.0.9);
   the chart-version to image-tag mapping for newer plugin releases must be
   checked at implementation time (OQ6).

## RQ1 — Why does torch HIP see zero devices, and what is the known-good pod spec?

### 1.1 What the crash mechanically means
- `RuntimeError: No CUDA GPUs are available` is raised by
  `torch._C._cuda_init()` when HIP device enumeration returns 0. The ROCm-side
  reports of the identical error: [8] documents the userspace variant "rocminfo
  works but device_count 0"; [28] documents the `hipErrorNoDevice` variant from torch;
  [12] documents the same import-time arch probe on RDNA4 (gfx1201) containers.
  On a ROCm build this is `hipGetDeviceCount() == 0` — HSA/ROCR enumeration
  found zero KFD devices. It happens in `_lazy_init` ->
  `torch._C._cuda_init()`, i.e. BEFORE any arch-specific code runs.
- vLLM v0.33.0 reaches it at IMPORT time because `vllm/platforms/rocm.py:215`
  executes `_GCN_ARCH = _get_gcn_arch()` at module level, and in 0.33.0 the
  fallback path calls `torch.cuda.get_device_properties("cuda")` ([G1]
  traceback; [12] shows the same import-time arch probe, and that the
  amdsmi-based detection has its own container failures [12][23]).
- Conclusion: the failing unit is "in-container HSA enumeration over
  /dev/kfd". Three layers can make it 0: (a) the container lacks a usable
  /dev/kfd (absent mount, permission, cgroup-v2 BPF device gate [18]); (b) the
  host KFD is up at the topology-sysfs level but its GPU compute nodes are
  non-functional for this userspace (kernel uAPI/firmware/driver mismatch);
  (c) the container's ROCr userspace itself fails to talk to host KFD
  (ROCr version vs kernel KFD uAPI skew; bundled libhsa mismatch class [8]).

### 1.2 Ruled OUT as root cause (with the reason)
- **Chip arch mismatch (gfx1201/gfx1151 / PYTORCH_ROCM_ARCH)**: enumeration
  is arch-agnostic — an unsupported arch fails LATER at kernel load/dispatch,
  never as "No CUDA GPUs are available" at `_cuda_init` [8][12]. Additionally
  the image's arch set already contains both chips on this node (gfx1151 + gfx1201)
  [G7]. Ruled out as cause; PYTORCH_ROCM_ARCH is only a relevant LEVER if a
  later arch error appears.
- **ROCR_VISIBLE_DEVICES="0" value**: it is an HSA-LEVEL PRE-FILTER over
  enumerated device indices/UUIDs [10][9]. With a valid index form
  ("0"), it cannot turn N>0 into 0 — it filters an already-enumerated set; it
  only yields 0 if (i) the underlying enumeration is already 0, or (ii) the
  value is a UUID that matches nothing [10], or (iii) it stacks with another visibility var into the hide-all semantics [9]. Ours is an index "0", which
  matches whenever >=1 device enumerates. Ruled out as cause. It REMAINS the
  chip-selection lever: index order = host KFD enumeration order (NOT
  guaranteed = PCI order) [10][11], so "0 = R9700" is an UNCONFIRMED
  assumption (confirm via the RQ2 probe's `rocminfo` before relying on it).
- **The pod spec shape (shape B)**: it is a strict SUPERSET of the official
  vLLM ROCm docker shape (non-privileged `--device /dev/kfd --device
  /dev/dri --group-add=video --cap-add=SYS_PTRACE --security-opt
  seccomp=unconfined --ipc=host` [19]). A maximally privileged pod with the
  whole host /dev still sees 0 devices, so the pod-spec layer is not the
  disease — the 0 is upstream of container permissions.
- **The `scsi_host` / `DiscoverBRCMswitchDevices` lines**: a benign
  host-device-discovery path in the ROCm userspace, printed even on WORKING
  hosts, ruled a red herring in the only other report of the exact same line
  (a Strix Halo vLLM case where plugging in a USB drive made the line
  disappear while the failure remained) [13]. The same line class is a known
  benign amdsmi `scsi_host` discovery path [23]. Not the cause.

### 1.3 Leading root cause (confidence ~0.75, needs RQ2 confirmation)
**The host KFD/kernel layer on node ai-gpu is the failing layer** — the node
runs an UNSUPPORTED rolling openSUSE Tumbleweed kernel 7.3.0-1-default with
the inbox amdgpu, OUTSIDE AMD's tested envelope, and the kernel-7.x KFD
topology surface is already observably broken (the device plugin cannot
resolve `drm_render_minor` on this node — see GROUNDED G2). Convergent
evidence:
- **Same plugin + same hardware class, documented break + fix**: a k3s/RDNA
  community report running the SAME plugin image (1.31.0.9) on RDNA states
  "kernel 7.x changed the /sys/class/kfd topology format enough that the AMD
  GPU device plugin could no longer resolve `drm_render_minor`; it marked the
  GPU unhealthy and silently stopped advertising amd.com/gpu. The fix is
  pinning a kernel the plugin understands (6.12 and 6.6 also work)" [17].
- **openSUSE is on NO ROCm support list**: ROCm 10.0.0 / 10.1.0
  compatibility matrices list, for gfx1201 (R9700 class): Ubuntu 26.04
  (kernel 7.0) / 24.04.4 (HWE 6.17) / 22.04.5 (HWE 6.8) / RHEL 10.2 (6.12) /
  9.8 (5.14) with AMD amdgpu DKMS 31.50.0/31.60.0; for gfx1151 (8060S):
  Ubuntu 26.04 (7.0) / 24.04.4 (OEM 6.17) INBOX kernel driver. No openSUSE
  row for either card [5][6]. The node's rolling 7.3 kernel is NEWER
  than any tested kernel and on an unsupported distro.
- **The 6.18→7.x kernel line carries documented RDNA KFD regressions**:
  ROCm/amdgpu#225 (KFD/SDMA compute regression introduced in 6.18, present
  through 7.0.x, RDNA3) [22]; Fedora 7.2 AMDGPU boot/plasma freeze on RX 9070
  XT (RDNA4) [30]; level1techs "immature gfx1201 kernel ecosystem" [31].
- **mainline vs this node**: mainline `kfd_topology.c` `node_show()` writes
  `drm_render_minor <n>` unconditionally [24][25] — so its ABSENCE on
  this node's GPU nodes is a distro-kernel anomaly (a 7.3.0-1-default
  Tumbleweed build), confirmable on-target (RQ2 step 1).

**Implication of the leading root cause**: if the host KFD/kernel layer is the
failing layer, then NO container/pod-spec change can fix it — the fix is a
host kernel/driver action (RQ3 option 1), and the pod spec is a non-factor.
The RQ2 probe is the confirmation.

### 1.4 Shape A's co-cause: the allocation was structurally untargetable

The plugin's `Allocate()` (1.31.0.9, `internal/pkg/plugin/plugin.go` [15])
injects, per allocation: `/dev/kfd` rw — the code comment reads "there are
only 1 /dev/kfd per nodes regardless of the # of GPU available for
compute/rocm/HSA use cases" — plus, for each allocated device,
`/dev/dri/card<card>` and `/dev/dri/renderD<renderD>` rw. **No env vars are
injected by the plugin** [15]. So the shape-A pod received /dev/kfd +
/dev/dri/card2 + /dev/dri/renderD129 — the 8060S's render nodes only — while
`ROCR_VISIBLE_DEVICES=0` targeted KFD index 0.

On this node the plugin's KFD-node-to-PCI mapping was already broken (G2):
both devices carried `nodeId:0 devID:(empty)` — the documented
`amdgpu.go` fallback when the `drm_render_minor` property cannot be
resolved [16] — and p2pWeights init failed, so it fell back to "kubelet
default allocation" [16]: blind. The blind allocator gave c5 (the 8060S) to
vLLM.

The all-nodes rule [32] (independent, merged 2026-10-16; tested on this
exact topology class — an AMD SoC iGPU plus a discrete gfx1201 dGPU,
Fedora 44, rootless podman, ROCm 7.2) makes that allocation structurally
untargetable:

> "ROCm's thunk sets up every GPU in the kernel's KFD topology
> (`/sys/class/kfd/kfd/topology/nodes`), which the container sees in full;
> when one of them has no render node in the container (here the iGPU) it
> fails for all of them."

Their measured matrix (their machine; the mechanism transfers, the numbers
do not) [32]:

| devices in the container | `ROCR_VISIBLE_DEVICES` | result |
|---|---|---|
| `/dev/kfd` + dGPU render node only (what the plugin injects) | unset, `0`, or the dGPU UUID | **0 GPUs** |
| same + `seccomp=unconfined` or `SYS_NICE` | unset | **0 GPUs** |
| `/dev/kfd` + dGPU + iGPU render nodes | dGPU UUID | 1 GPU (gfx1201) |
| `/dev/kfd` + both render nodes | iGPU index `1` | 1 GPU (the iGPU) |

So even on a HEALTHY host, shape A enumerated the 8060S only if KFD index 0
= c5; if index 0 = c4 (the repo's unconfirmed assumption, G6), the target
card's render node was absent from the container and EVERY init failed ->
0 GPUs. Neither case yields "the R9700": the allocation could not be used
for chip targeting. The deploy note in b81faa9e5 ("the plugin allocated the
8060S and injected no visible devices", G6) is the compressed form of this
mechanism, and it reconciles with the plugin code [15] — see
contradictions #2. Shape B's whole-`/dev/dri` mount carries BOTH render
nodes, so it satisfies the all-nodes rule [32] independent of any
allocation.

Caveat: the shape-A pod was replaced by shape B, so its `/dev` cannot be
inspected after the fact. The mechanism above is established from the
plugin source [15][16], the live plugin log (G2), and the independent
tested report [32] — not from the dead pod. Confidence: high in the
mechanism; the index-0 identity is RQ2 step 4's job.

### 1.5 Known-good pod spec

**Given a healthy host KFD layer** (RQ3 option 1, or a RQ2 step-3 "2
agents" outcome):

- **The committed shape B (G1) IS the known-good spec here.** It is a
  strict superset of the official non-privileged vLLM ROCm docker shape
  (`--device /dev/kfd --device /dev/dri --group-add=video
  --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host` [19]),
  and an RDNA4/k3s community deployment proved vLLM serving on a healthy
  host in an unprivileged pod of exactly that class [20]. Shape B also
  satisfies the all-nodes rule [32] (whole `/dev/dri` -> both render
  nodes).
- **One refinement, values-only:** after RQ2 step 4, replace
  `ROCR_VISIBLE_DEVICES: "0"` with the UUID form `GPU-<unique_id>`
  [10][11][32] — the index form works too, but its order is KFD-topology
  order (not guaranteed PCI order) and is unconfirmed on this node (G6).
- **What is NOT known-good:** shape A (plugin allocation) on a two-card
  SoC node [15][32]; any pod whose device set lacks a render node of a
  KFD-visible GPU while targeting by index [32]; and, until the host fix,
  ANY pod shape — the 0-device outcome is upstream of the pod (G1 vs
  §1.2's superset argument).
- `--watermark 0.05` in the serve args is a valid v0.33.0 scheduler arg
  (`watermark: float = SchedulerConfig.watermark`, registered
  `--watermark` [33]; KV-preemption headroom per parent C02) and is
  distinct from the text-watermarking `--watermark-config` [33] — no
  change needed.

## RQ2 — Owner-run diagnostic ladder (no pod-exec anywhere)

Every step is either a node-side shell command on `ai-gpu` (the operator's
own access), a `kubectl logs` read, or the node-side one-shot container-run
idiom already sanctioned by the acceptance runbook
(`.agents/notes/vllm-on-target-acceptance.md` §1.4/§3.1: `ctr -n k3s.io run
--rm` against the pulled image). No agent tier grants pod-exec (G6,
parent EXPLORE §7); the runbook's own host gates (0.1 `rocminfo`, 0.2
`modinfo amdgpu`, 0.3 `free -h`) are folded into step 2 below. Record every
output — the decision table closes the loop.

**Step 0 — Record kernel + runc vintage (one line each).**

```
uname -r
uptime
runc --version | head -1
```

Fixes the host envelope for the record (G3: k3s v1.36.5+k3s1 ships runc
v1.4.2 [34]) and answers OQ7 (boot epoch vs the Strata pin) in passing.

**Step 1 — The host KFD-topology surface (the plugin's witness, read
directly).**

```
for n in /sys/class/kfd/topology/nodes/[0-9]*; do
  echo "== $n"; grep -E '^(name|drm_render_minor|visible)' "$n/properties" 2>/dev/null
done
ls -la /dev/dri
lspci -nn | grep -iE 'vga|3d|display'
dmesg | grep -Ei 'kfd|amdgpu' | tail -80
```

Reads:
- **Do the GPU KFD nodes (1, 2) carry `drm_render_minor`?** Mainline
  `kfd_topology.c` `node_show()` writes it unconditionally [24][25] — so
  its ABSENCE is the 7.3.0-1-default anomaly the plugin log already
  witnessed (G2; contradictions #1/#5: content variant, not read-gated).
  Its PRESENCE re-scopes the plugin failure to the read/permission variant
  [17] (RQ3 option 3 applies after all).
- **The dmesg KFD/amdgpu lines**: per-card init, KFD compute-node creation,
  any kfd errors — the host-side witness no agent tier can see.
- Record card-to-BDF (`/dev/dri/card{1,2}` <-> `0000:c4:00.0` /
  `0000:c5:00.0`, per G2/G3) for step 4's mapping.

**Step 2 — Host-side HSA sanity (if host ROCm tools exist; runbook 0.1/0.2
equivalent).**

```
modinfo amdgpu | grep version
rocminfo 2>/dev/null | grep -E 'gfx_target_version|unique_id|Card' || echo "no host rocminfo"
rocm-smi || true
```

(The runbook §8.2 already uses host `rocm-smi`, so at least that is
present.) Read: if host `rocminfo` reports **0 HSA agents**, the
host-userspace-to-KFD interface is broken (kernel/driver class
[22][30]; openSUSE off-matrix [5][6][26]) — stop the container-side work
and go straight to RQ3 option 1. If it reports **2 agents** with
`gfx_target_version` 12.0.1 + 11.5.1, record each agent's `unique_id`
(`GPU-…`) — step 4's input.

**Step 3 — In-image enumeration, the decisive gate (runbook §1.4 idiom).**

```
ctr -n k3s.io run --rm --entrypoint rocminfo \
  --device /dev/kfd --device /dev/dri --group-add 44 \
  ghcr.io/ownyourio/vllm-rocm:main
```

Reads:
- **2 agents (12.0.1 + 11.5.1)** -> the host KFD is healthy for this
  image's ROCr; the crash is image/runtime-state (the bundled-libhsa class
  [8]) or chip targeting — proceed to step 4, then RQ3 option 2.
- **1 agent, gfx1151 only** -> host KFD up but the R9700's KFD node broken
  (or the openSUSE iGPU+dGPU coexistence warning active [26]) — re-read
  step 1's dmesg for c4-specific lines; RQ3 option 1.
- **0 agents** -> the container-side HSA sees nothing: host KFD/userspace
  interface broken (the kernel-7.x family [17][22][30]) or image ROCr
  state [8]; the step-1 properties answer (present/absent) tells which.
  RQ3 option 1. (The control for "what 0 looks like when the devices are
  simply not passed at all" is documented in [14].)

torch-level variant — the EXACT failing unit, with the runtime trace
enabled:

```
ctr -n k3s.io run --rm --entrypoint python \
  --device /dev/kfd --device /dev/dri --group-add 44 \
  --env AMD_LOG_LEVEL=3 \
  ghcr.io/ownyourio/vllm-rocm:main \
  -c 'import torch; print(torch.version.hip, torch.cuda.device_count())'
```

If `device_count() == 0`, `AMD_LOG_LEVEL=3` prints the runtime trace on the
console (captured in the `ctr` output) — the same trace [8] used to pin
`hipGetDeviceCount: Returned hipErrorNoDevice`, which distinguishes "HSA
init failed" from "HSA init OK, empty device list" [10]. This is also what
RQ3 option 4 (a persistent env) would produce inside the crashlooping pod.

**Step 4 — Card-to-chip-to-UUID mapping (the input to option 2).**

Chain: KFD-node property `drm_render_minor` (128 -> renderD128 -> card1;
129 -> renderD129 -> card2, per G2/G3) -> `/sys/class/dri/card{N}/device`
symlink -> PCI BDF (c4/c5) -> host `rocm-smi` row (BDF + GPU idx + name) ->
`rocminfo` agent: `gfx_target_version` (**12.0.1 = R9700 (gfx1201);
11.5.1 = 8060S (gfx1151)**) [10][32], and `unique_id` = the `GPU-…` string
[32]. Output: `R9700 = GPU-<uuid>` and the R9700's KFD index — confirms or
overturns the G6 "index 0" assumption (index order = KFD-topology order,
not PCI order [11]).

**Step 5 — (Only if step 1 found the properties PRESENT) The plugin read
path.**

```
kubectl -n default logs amd-gpu-device-plugin-daemonset-<pod> --tail=200
```

Re-read the G2 signature live: if the properties exist on the host yet the
plugin still logs `Topology property not found`, the plugin container's
/sys read is gated (the "silent I/O error" variant [17]) -> RQ3 option 3's
privileged+mounts patch applies to this node; if the plugin log is clean,
the step-1 read was transient — record and move on.

**Decision table (outcome -> conclusion -> next move):**

| observation | conclusion | next move |
|---|---|---|
| GPU KFD nodes lack `drm_render_minor` (step 1) | 7.3-kernel topology-surface anomaly (the G2 witness; mainline writes it [24]) | RQ3 option 1 |
| properties present; host `rocminfo` 0 agents | host userspace-KFD broken ([22][30]; openSUSE off-matrix [5][6]) | RQ3 option 1 |
| host `rocminfo` 2 agents; in-image probe 0 agents | image ROCr-to-host-KFD mismatch class (libhsa/wheel [8]) | re-pull the image / verify its digest; if it persists -> RQ3 option 1 |
| in-image probe: 1 agent, gfx1151 only | R9700 KFD node dead, or iGPU coexistence warning [26] | re-read dmesg (c4 lines); RQ3 option 1 |
| in-image probe: 2 agents | host healthy -> the crash is targeting/runtime-state | step 4; RQ3 option 2 |
| torch probe 0 with "empty device list" trace while `rocminfo` saw N | visibility/filter layer (a stray ROCR var stacking [9]) | audit pod env; the runbook §1.4 shape passes only /dev/kfd + /dev/dri |
| torch probe 0 with "HSA init failed" trace | ROCr/kernel KFD uAPI skew | RQ3 option 1 |
| properties present; plugin still errors (step 5) | plugin read gated (the I/O-error variant [17]) | RQ3 option 3 |
| `runc --version` < 1.0.0-rc94 (expectation: no — v1.4.2 [34]) | cgroup-v2 BPF device class [18] in play | (record only; k3s 1.36.5 ships v1.4.2) |

## RQ3 — Ranked fix options for this repo

**1. Host kernel/driver pin (owner-run; the ONLY option addressing the
leading root cause).**
- **What:** `kernel-longterm` (6.12 LTS) + reboot [26]; the udev rule
  `KERNEL=="kfd", GROUP=="video", MODE="0660"` [29]; and, if the 6.12 inbox
  amdgpu is too old for gfx1201 (step 2's `modinfo` + step 1's dmesg say),
  additionally AMD's `amdgpu-dkms` from the AMD/SLE-15.6 repo [29] — the
  ROCm 10.0.0/10.1.0 matrices pair gfx1201 with amdgpu DKMS 31.50.0/31.60.0
  (the RHEL 10.2/6.12 row) [5][6].
- **Why 6.12:** the community's kernel-7.x break was fixed by pinning
  (6.18; 6.12 and 6.6 also work) [17]; ROCm/amdgpu#225 documents a KFD/SDMA
  compute regression INTRODUCED in 6.18 and present through 7.0.x [22] —
  so avoid 6.18; 6.12 LTS is the common denominator appearing in the
  tested matrix rows [5][6] and is openSUSE's sanctioned "longterm" [26].
- **Not a repo change** — owner-run host action. The repo's response is to
  re-run the RQ2 ladder + the C06 acceptance runbook afterwards.
- **Risk:** a whole-node host change touching the Strata/llama-swap Vulkan
  workloads (G4) — re-validate them after the reboot (runbook step-0
  gates). openSUSE's iGPU+dGPU coexistence warning applies to this node's
  8060S iGPU + R9700 dGPU combination — the per-card reads in steps 1/2
  are the check [26].
- **Confidence:** ~0.75 that this is the root cause (pending steps 1/3);
  high that the mechanism is real (G2 + [17] + [24]).

**2. KEEP shape B (b81faa9e5) + re-pin the chip by UUID (values-only; a
refinement, not a fix).**
- **What:** `rocrVisibleDevices: "GPU-<uuid>"` in `charts/vllm/values.yaml`
  (plus the matching `services/gpu-ai/prod/values.yaml` entry if the
  override lives there); shape B otherwise unchanged (G1).
- **Why:** the index "0" is an unconfirmed repo assumption (G6); the UUID
  form is the documented robust targeting [10][11] and was measured to
  yield exactly one GPU of the intended arch [32].
- **Dependency:** option 1 (or a step-3 "2 agents" outcome) — otherwise it
  is a UUID pointing at a dead KFD. This is the follow-up commit AFTER the
  host fix + step-4 mapping, not a standalone fix.

**3. Plugin hygiene (repo change: the `amd-gpu` chart entry, G8).**
- **What:** bump the `amd-gpu` chart from 0.22.0 to the version shipping
  `rocm/k8s-device-plugin:1.31.0.12` (verify the chart-to-image mapping
  via `helm show versions amd-gpu` / the chart index at implementation
  time — OQ6), or override the image tag in values. 1.31.0.12 brings the
  ListAndWatch stream-disconnect exit fix (the EOF-loop class [17]),
  product naming (the R9700 gets a proper label), and health-check
  tightening [7] — but the `drm_render_minor` topology regex is UNCHANGED
  between 1.31.0.9 and 1.31.0.12 [7][16], so this fixes NEITHER the broken
  KFD mapping NOR the zero-device symptom.
- **Scope on this node:** the t1m.me privileged+mounts plugin patch [17]
  was for the read-GATED (I/O-error) variant; our plugin pod already reads
  /sys and its witness is property CONTENT (G2; contradictions #1) — so
  option 3 here is image-bump-only, unless RQ2 step 5 proves the read-gate.
- **Confidence:** low as a fix; hygiene only (addresses G2's
  restartCount-15 churn).

**4. `AMD_LOG_LEVEL: "3"` diagnostic env (values-only; makes the next
crashloop readable).**
- **What:** add the env to the vLLM pod (RQ2 step 3's torch probe is the
  one-shot equivalent [10]). The trace lines (`hipGetDeviceCount: Returned
  hipErrorNoDevice` class [8]) distinguish the mechanisms on any LATER
  regression without a node visit. Remove (or drop to level 0) once the
  root cause is confirmed and C06 passes. Cost: log volume.

**5. CDI as a later consolidation (owner-run node change + repo values;
NOT now).**
- **What:** `amd-ctk cdi generate` (ROCm Container Toolkit [1]) ->
  `/etc/cdi/amd.json`; on k3s: `/var/lib/rancher/k3s/agent/etc/containerd/
  config-v3.toml.tmpl` with `{{ template "base" . }}` + `enable_cdi = true`
  (the containerd 2.0 path [3], the containerd CRI knobs [21]); pods
  request the CDI device — the runtime-agnostic pattern the NVIDIA operator
  made its default in v25.10.0 [2].
- **Why later:** CDI fixes device INJECTION, not host KFD state — if the
  root cause is option 1's, CDI inherits the same failure. And the
  all-nodes rule [32] implies the spec must carry EVERY card's render
  nodes (the `amd.com/gpu=all` form + a UUID ROCR pin) — a single-GPU CDI
  spec would reproduce shape A's untargetable allocation. Do it only after
  the host is healthy, if the owner wants to retire the
  privileged/hostPath idiom in favour of spec-managed devices.

**6. AMD GPU Operator — NOT now.**
- The KMM-installed amdgpu-DKMS on a distro that is off-matrix for both
  cards [4][5][6] would replace the inbox amdgpu that Strata/llama.cpp
  Vulkan depend on (G4) — a whole-node driver surgery with no AMD support
  backstop; the operator+KMM+NFD+cert-manager footprint on a single-node
  k3s; and it does not answer the zero-device diagnosis (orthogonal,
  heavier). Revisit only if the owner wants long-term AMD-managed driver
  lifecycle.

**7. Retarget the 8060S — LAST RESORT ONLY.**
- Parent R1 verdict: MARGINAL (~16 tok/s single-stream, no MTP on AMD, RAM
  coexistence risk on the ~125 GiB node) [G6]; the gfx1151 supported-kernel
  rows are Ubuntu 7.0/OEM-6.17 inbox [5][6] — off the option-1 6.12 pin
  (workable: first working gfx1151 vLLM evidence exists [13]; its CWSR
  performance floor of 6.18.4+ is a SPEED issue, not a boot issue [13]).
  Take this route only if step 3 returns "1 agent, gfx1151 only" inverted
  (the R9700's KFD node dead on the pinned kernel while the 8060S's lives).

**Explicitly NOT recommended:**
- **Re-attempting shape A via "fixed" plugin allocation** — the count-only
  design + the all-nodes rule make it structurally fragile on a two-card
  SoC node [15][32].
- **`PYTORCH_ROCM_ARCH` / image-build changes** — both chips are already
  in the image's arch set (G7); the failure precedes arch-specific code
  (§1.1).
- **A runc/device-cgroup fix** — k3s v1.36.5 ships runc v1.4.2 [34], far
  past the documented `< rc94` window [18].
- **Treating the `scsi_host` line or `--watermark` as failure candidates**
  — §1.2/§1.5 rulings [13][23][33].

## Contradictions and how to weigh them (STORM conflict map, final)

1. **Plugin still advertises AND allocates (G2) vs the blog's "kernel 7.x
   stops the plugin advertising entirely" [17].** Both true: the
   kernel-7.x KFD-topology break has a severity spectrum — on the blog's
   7.1.3 the topology files were UNREADABLE inside the capability-stripped
   plugin container (I/O error -> unhealthy -> no advertisement); on our
   7.3 the files ARE readable but the property is MISSING ->
   degraded-but-functional (advertising, mis-mapped KFD node ids). Same
   regression family; we are the milder variant.
2. **Deploy note "injected no visible devices" (G6) vs plugin code that
   always injects /dev/kfd + card + renderD [15].** Reconciled: the
   injection DID happen (for c5); "no visible devices" = "no devices for
   the card the pod targets" — the all-nodes rule [32] (§1.4).
3. **Shape B (maximally privileged) still zero devices (G1) vs "the
   pod-shape axis is settled" [19][20].** Not a contradiction: shape
   correctness is necessary, not sufficient. A maximally-permissive shape
   seeing zero devices is the strongest evidence the failure is HOST-side.
4. **Strata pod healthy (G4) as "proof hostPath works for HIP" (the
   launch-brief caution).** The caution stands: Strata + llama.cpp are
   Vulkan/DRM render-node consumers; NO healthy workload on this node
   exercises the KFD compute path. Healthy DRM consumers prove the
   driver's graphics path, not KFD.
5. **Mainline writes `drm_render_minor` unconditionally [24][25] vs its
   absence on our GPU nodes (G2 witness).** Unresolvable by source reading
   alone (master snapshot vs a distro build; no 7.0->7.3 tree change
   located). The live plugin log is the ground truth for THIS node;
   mainline is the reference for what SHOULD be there. Arbiter: RQ2
   step 1.
6. **Matrix "RX 9000 with amdgpu DKMS 31.50/31.60" vs "8060S with inbox
   driver" [5][6].** Different GPU rows; both cards are off-matrix on
   openSUSE, and the 8060S inbox row does not bless a 7.3 kernel (only
   Ubuntu 7.0/6.17).
7. **Three kernel recommendations: t1m.me "pin 6.18 works" [17] vs
   ROCm/amdgpu#225 "6.18 introduced a KFD/SDMA regression" [22] vs openSUSE
   SDB "kernel-longterm (6.12) + amdgpu-dkms" [26][29].** Weigh: #225's
   regression is a specific SDMA page-fault path under sustained rocFFT on
   a datacenter RDNA3 SKU; t1m.me's 6.18 fixed the TOPOLOGY symptom on
   their hardware; 6.12 LTS appears in every supported matrix row
   (RHEL 10.2/6.12; SLES/Debian rows) [5][6]. **6.12 LTS is the safest
   common denominator; 6.17/7.0 are alternatives; avoid 6.18.**

## Implications for the plan (this folder's plan of record + parent cf-105)

- The priority-class work (C03/C04 of the folder's plan) is gated on the
  engine ever starting: RQ3 option 1 (owner-run host fix) is the critical
  path and lives OUTSIDE this repo — the plan should record it as a
  prerequisite risk, not as a chunk.
- The runbook's C06 host gates (§0.1/§1.4) are the RQ2 step 2/3 equivalents:
  run them BEFORE the first serve attempt post host-fix, and put step 4
  (the UUID mapping) ahead of any `rocrVisibleDevices` values commit
  (option 2).
- No `serveArgs` change is needed for the crash itself (`--watermark 0.05`
  is valid [33]); option 4's env is the only values-side addition the
  diagnosis itself needs.
- If step 3 returns "2 agents" (host healthy), the §1.3 leading cause
  inverts: the crash becomes image/runtime-state [8], and the plan's next
  move is a digest re-pull + the step-3 torch probe, not a kernel pin.
- Parent D2 (chip = R9700, index "0") survives as an assumption pending
  step 4; D5 (sleep mode) is unaffected by the device layer, but its
  wake-time VRAM-reclaim caveat (runbook §8.2) is driver-version-dependent
  — re-validate it after option 1 changes the amdgpu vintage.

## Open questions (need the owner / a next session; not resolvable by this agent)

1. **OQ1** — Does 7.3.0-1-default actually omit `drm_render_minor` on the
   GPU KFD nodes? (RQ2 step 1; G2 is the plugin-side witness only.)
2. **OQ2** — Which KFD node is the R9700 (the index-0 identity)? (step 4;
   the G6 assumption is unconfirmed.)
3. **OQ3** — Does the 6.12 inbox amdgpu initialise gfx1201 (MES) on this
   board, or does option 1 need `amdgpu-dkms`? (step 2's `modinfo` +
   step 1's dmesg; the matrices say DKMS 31.50/31.60 [5][6].)
4. **OQ4** — Does the 8060S iGPU coexist cleanly on 6.12 (openSUSE's
   iGPU+dGPU warning [26])? (steps 1/2 per-card reads.)
5. **OQ5** — Is the plugin failure the content variant or the read-gated
   variant? (G2 says content — the plugin reads /sys fine; step 5
   re-checks after any host change.)
6. **OQ6** — Which `amd-gpu` chart version ships 1.31.0.12? (the G8
   mapping is chart-side; verify at implementation time — not resolvable
   from the live pod.)
7. **OQ7** — Did the node boot into 7.3.0 before or after the Strata pin?
   (uptime vs pin residency — the ladder's step-0 `uptime` answers it in
   passing.)

## Adjacent findings (out of scope; recorded for the next failure class)

- **amdsmi-in-container fragility** is a documented vLLM-on-RDNA path
  (AMDSMI_STATUS_NOT_INIT -> platform not detected; fixed upstream by the
  KFD-topology-detection commit) [12] — the next-failure candidate AFTER
  the device layer is fixed; the runbook §3.3 fallback names it. Related
  zero-device reports on gfx1151/gfx1201 containers [27][28] are the same
  class, cited via #40081's related list, not individually read.
- **7.x-kernel RDNA ecosystem maturity**: the KFD/SDMA compute regression
  [22], the RDNA4 7.2 boot/plasma freeze [30], and the "immature gfx1201
  kernel ecosystem" signal [31] — the option-1 rationale in
  community-signal form.
- **ROCR/HIP visibility-var stacking** ("ROCR=2 + HIP=2 hides all
  devices" [9]) — relevant only if a future pod ever carries both vars
  (none do today, G1).
- **Zero-GPU control shape**: a container with the device flags not passed
  at all returns 0 GPUs [14] — what a negative control for step 3 looks
  like if the owner wants one.
- **The `scsi_host` warning class** is a separate, near-fixed upstream
  amdsmi wart [23] — the §1.2 ruling's citation.

## Sources

- [1] ROCm Container Toolkit (amd-ctk) — CDI spec generation (`amd-ctk cdi generate`), runtime-agnostic device form — https://github.com/ROCm/container-toolkit
- [2] NVIDIA GPU Operator docs — CDI default since v25.10.0 (the runtime-agnostic pattern) — https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/cdi.html
- [3] k3s advanced configuration — containerd 2.0 `config-v3.toml.tmpl` + `{{ template "base" . }}` extension — https://docs.k3s.io/advanced
- [4] AMD GPU Operator README — Instinct+Radeon scope, k8s 1.29+, cert-manager, KMM driver install, DeviceConfig — https://github.com/ROCm/gpu-operator
- [5] ROCm 10.0.0 compatibility matrix — gfx1201 with amdgpu DKMS 31.50.0 (RHEL 10.2/6.12 row); 8060S inbox 7.0/OEM 6.17; no openSUSE row — https://rocm.docs.amd.com/en/docs-10.0.0/compatibility/compatibility-matrix.html
- [6] ROCm 10.1.0 compatibility matrix — same pattern, DKMS 31.60.0 — https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html
- [7] k8s-device-plugin v1.31.0.9...v1.31.0.12 compare — topology regex unchanged (67 commits); ListAndWatch exit fix; product naming; health-check tightening — https://github.com/ROCm/k8s-device-plugin/compare/v1.31.0.9...v1.31.0.12
- [8] ROCm/ROCm#5461 — "rocminfo works but device count 0": the `AMD_LOG_LEVEL=3` `hipGetDeviceCount: Returned hipErrorNoDevice` trace; bundled-libhsa mismatch + fix — https://github.com/ROCm/ROCm/issues/5461
- [9] vllm#12572 — ROCR_VISIBLE_DEVICES HSA-level pre-filter semantics; "ROCR=2 + HIP=2 = hide all the devices" (HPC-docs quote); Ray sets it per-rank — https://github.com/vllm-project/vllm/issues/12572
- [10] HIP environment variables reference (7.16.0) — `ROCR_VISIBLE_DEVICES` (device indices or UUIDs, recommended on Linux), `GPU_DEVICE_ORDINAL`, `AMD_LOG_LEVEL` — https://rocm.docs.amd.com/projects/HIP/en/latest/reference/env_variables.html
- [11] ollama#7480 — ROCR vs HIP_VISIBLE_DEVICES; "ordering isn't consistent, so using UUIDs ensures we query and target the intended GPU" — https://github.com/ollama/ollama/issues/7480
- [12] vllm#40081 — RDNA4 gfx1201 container: amdsmi AMDSMI_STATUS_NOT_INIT, circular-import in `_get_gcn_arch` fallback, `device_count()==0` with working HIP; upstream KFD-topology-detection commit — https://github.com/vllm-project/vllm/issues/40081
- [13] nix-amd-ai#68 — Strix Halo vLLM: scsi_host line ruled a red herring (USB-drive test); first working gfx1151 vLLM evidence; CWSR kernel 6.18.4+ floor (speed, not boot) — https://github.com/noamsto/nix-amd-ai/issues/68
- [14] kyuz0/ai-toolbox-cockpit#7 — zero GPUs when the device flags are not passed (the control shape) — https://github.com/kyuz0/ai-toolbox-cockpit/issues/7
- [15] k8s-device-plugin `internal/pkg/plugin/plugin.go` @v1.31.0.9 — `Allocate()` injects /dev/kfd (rw, one per node) + per-device /dev/dri/cardN + /dev/dri/renderDNNN (rw); NO env vars — https://github.com/ROCm/k8s-device-plugin/blob/v1.31.0.9/internal/pkg/plugin/plugin.go
- [16] k8s-device-plugin `internal/pkg/amdgpu/amdgpu.go` @v1.31.0.9 — the `drm_render_minor\s(\d+)` topology regex; `nodeId:0`/`devID:(empty)` fallback; p2pWeights init failure -> kubelet default allocation — https://github.com/ROCm/k8s-device-plugin/blob/v1.31.0.9/internal/pkg/amdgpu/amdgpu.go
- [17] t1m.me blog — vLLM+LiteLLM on Strix Halo k3s with the SAME plugin image (1.31.0.9): kernel 7.x broke `drm_render_minor` resolution; fix = pin kernel 6.18 (6.12/6.6 also work); privileged+mounts plugin patch for the I/O-error variant — https://blog.t1m.me/blog/vllm-litellm-on-amd-strix-halo
- [18] ROCm/k8s-device-plugin#65 — cgroup-v2 BPF device filter + runc < 1.0.0-rc94 + "rw" device spec -> `access(F_OK)` EPERM -> 0 devices; fixed in runc — https://github.com/ROCm/k8s-device-plugin/issues/65
- [19] vLLM official ROCm docker run shape (non-privileged: /dev/kfd + /dev/dri, video group, SYS_PTRACE, seccomp unconfined, ipc host) — https://docs.vllm.ai/en/stable/deployment/docker
- [20] sleeepss/vllm-rdna4-container-patches — vLLM on RX 9070 XT in an unprivileged pod on stock k3s; the blockers were image/host-side, not pod-shape — https://github.com/sleeepss/vllm-rdna4-container-patches
- [21] containerd CRI configuration — `enable_cdi`, `privileged_without_host_devices` — https://github.com/containerd/containerd/blob/main/docs/cri/config.md
- [22] ROCm/amdgpu#225 — KFD/SDMA compute regression on RDNA introduced in 6.18, present through 7.0.x — https://github.com/ROCm/amdgpu/issues/225
- [23] ROCm/rocm-systems#9789 — the amd-smi `scsi_host` discovery warning (upstream wart, fix commit referenced) — https://github.com/ROCm/rocm-systems/issues/9789
- [24] mainline `drivers/gpu/drm/amd/amdkfd/kfd_topology.c` — `node_show()` writes `drm_render_minor <n>` unconditionally — https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/amdkfd/kfd_topology.c
- [25] kfd_topology.c code-browser mirror (same property) — https://codebrowser.dev/linux/linux/drivers/gpu/drm/amd/amdkfd/kfd_topology.c.html
- [26] openSUSE SDB: AMD GPGPU — TW container path = kernel-longterm + amdgpu-dkms; iGPU+dGPU coexistence warning; udev kfd group-video rule — https://en.opensuse.org/SDB:AMD_GPGPU
- [27] vllm#34573 — "No HIP GPUs are available" gfx1151 container (cited via #40081's related list) — https://github.com/vllm-project/vllm/issues/34573
- [28] ROCm/HIP#3710 — hipErrorNoDevice surfaced from torch (cited via #40081's related list) — https://github.com/ROCm/HIP/issues/3710
- [29] torsten-online gist — ROCm on openSUSE TW = kernel-longterm + amdgpu-dkms (AMD SLE-15.6 repo) + udev kfd rules — https://gist.github.com/torsten-online/22dd2746ddad13ebbc156498d7bc3a80
- [30] Fedora discussion — Linux 7.2 AMDGPU boot/plasma freeze on RX 9070 XT (RDNA4): the 7.x-line RDNA trouble signal — https://discussion.fedoraproject.org/t/workaround-for-linux-7-2-amdgpu-boot-plasma-freeze-on-rx-7800xt-rx-9070xt-dcn-4-0-1-rdna3-rdna4/201542/8
- [31] level1techs — 8x gfx1201 TP=8 deployment; "immature gfx1201 kernel ecosystem" — https://forum.level1techs.com/t/deepseek-v4-flash-on-8x-amd-gfx1201-packaged-tp-8-deployment/252722
- [32] sybil-solutions/local-ai-registry PR#256 (merged 2026-10-16) — ROCm's thunk sets up EVERY KFD-topology GPU; a missing render node for one fails ALL; measured matrix (iGPU+dGPU SoC, Fedora 44, ROCm 7.2): plugin-style injection -> 0 GPUs; both render nodes + UUID ROCR pin -> exactly 1 GPU of the intended arch — https://github.com/sybil-solutions/local-ai-registry/pull/256
- [33] vLLM v0.33.0 `vllm/engine/arg_utils.py` — `watermark: float = SchedulerConfig.watermark` registered as `--watermark` (scheduler KV-preemption headroom), distinct from `--watermark-config` (text watermarking) — https://github.com/vllm-project/vllm/blob/v0.33.0/vllm/engine/arg_utils.py
- [34] k3s v1.36.5+k3s1 release notes — embedded component versions: containerd v2.3.4-k3s1.36, runc v1.4.2 — https://github.com/k3s-io/k3s/releases/tag/v1.36.5+k3s1

## Reliability & confidence notes

- **[32] is a single test report** (one machine: RX 9070 XT + Ryzen iGPU,
  Fedora 44, rootless podman, ROCm 7.2): the mechanism (every-KFD-node
  render rule) is corroborated by our G2 plugin log + mainline source
  [15][16][24], but its numbers do not transfer to this node; treat it as
  mechanism evidence, not benchmark.
- **[17] is a single blog** (Strix Halo k3s, same plugin image): the
  byte-identical `Topology property not found` line makes it the closest
  analogue; its kernel-pin fix is corroborated by [26][29][5][6]. Weight:
  high for the symptom, medium for the specific pin recommendation.
- **[13]'s scsi_host ruling** is the maintainer's word in the issue
  thread (the USB-drive test is the reporter's): high confidence "not the
  cause"; the emitting library remains unidentified (a ladder note only).
- **[27][28][14] are cited via #40081's related list / titles** — not
  individually read: medium confidence, used only as same-class
  corroboration, never as the sole support of a claim.
- **The G-facts** were probed live 2026-11-07 (readonly k8s MCP + git on
  this worktree); the shape-A pod no longer exists, so its `/dev` is
  established from source [15][16] + log (G2), not observation.
- **The host-kernel anomaly claim (OQ1)** rests on the plugin witness +
  mainline source; the direct on-target read is pending (RQ2 step 1) —
  which is why the §1.3 confidence is ~0.75, not ~0.9.
- **Repo-grounded vs researched:** G1–G8 and the runbook/plan/parent
  citations are repo/cluster facts; everything else carries a [n] web
  citation. No claim in this document rests on a source weaker than the
  one named beside it.
