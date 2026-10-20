# 2026-10-20 debug — gpu / gpu-ai / dev offline investigation

Status: investigation complete, root causes identified, no code changes made.

## Symptom

User-reported recurring offline events on the gpu, gpu-ai, and dev clusters.
Investigated via readonly-gpu-kubernetes MCP, Loki (datasource P8E80F9AEF21F6940),
and Prometheus (datasource prometheus), covering ~4 days with focus on the last 24h.

## Findings — four distinct causes

### 1. AMD GPU VRAM exhaustion + driver hangs (gpu-ai and gpu) — biggest outage source

gpu-ai node, device `0000:c2:00.0` (evidence: node journal in Loki):

| Time (UTC) | Event |
|---|---|
| 10-18 04:29:49 | `amdgpu_vm_validate() failed` / `Not enough memory for command submission!` storm; node NotReady k8s event 04:29:31; +18 pod restarts ~04:35 |
| 10-18 23:46:47 | same VRAM errors; +10 pod restarts ~23:50 |
| 10-19 07:06-07:07 | two `llama-server` coredumps, stack in `libggml-vulkan.so`, amid VRAM errors |
| 10-19 14:06, 15:54; 10-20 00:09, 01:09 | `Fence fallback timer expired on ring comp_1.x.0` (GPU compute-ring stalls) |

gpu node, device `0000:05:00.0`:

- 10-18 16:09-16:37 UTC: amdgpu VM-validate failures plus kernel stack traces blocked in
  `amdgpu_gem_create_ioctl`. Containers mass-killed 16:09:59, k3s died (PID 138138 → new PID
  181938 at 16:37:35), whole VM frozen 16:28→16:37 (no journal or qemu-guest-agent activity),
  metrics/journal gap ~26 min, +74 then +53 pod restarts in two waves. Biggest gpu outage in window.

Context: follows recent llama roster growth and model preloading work
(10-16 `feat(gpu-ai): persist llama caches and preload model trio`,
10-18 `feat(gpu-ai): add uncensored qwen36 heretic/huihui + coder-next-ablit`),
and the earlier 2026-10-11 VRAM OOM debug plan. Over-committed VRAM → failed Vulkan
command submission → llama-server crash / GPU hang → single-node cluster drags down with it.

### 2. K3s auto-upgrade jobs kill k3s even when nothing changed (all clusters)

- `charts/base/templates/k3s-version.yaml` pins `server-plan`/`agent-plan` at
  `version: v1.36.5+k3s1` (last bumped 10-08, commit 356c771e0). The `rancher/k3s-upgrade`
  job SIGTERMs k3s unconditionally — today's run logged "Binary already been replaced" and
  still killed the service.
- Last-day example (gpu): 01:39:23 ArgoCD sync of the `system-upgrade-controller` Application
  initiated by tms@spencerslab.com → Plan re-applied → job created 01:39:58 → cordon 01:40:10
  → `kill -SIGTERM 1660780` 01:40:23 → kubelet back 01:40:40 → uncordon 01:41:06. ~1 min API
  outage plus pod restarts (cloudnative-pg, alloy-operator, seaweedfs-csi-controller).
- Any re-apply that changes the plan hash (renovate K3s bump, ArgoCD prune/recreate, manual
  sync) re-fires the job. kubelet restart counts (~20 per 42d on gpu) show this recurs.

### 3. gpu-supabase kong container OOMKilled every ~2h50m (gpu, chronic)

- kong (image kong:3.9.3, limit 1Gi) restartCount 382; lastState OOMKilled exitCode 137 at
  10-20 00:20:34 (containerID matches the kernel cgroup-OOM log `cri-containerd-250c12ea...`).
- Kernel journal: cgroup OOM kills of ~9 nginx workers + 1 sh per event at 10-19 16:00, 18:47,
  21:34, 10-20 00:20; baseline 2-3 oom-killer invocations per 6h for ≥5 days (spikes: 18 events
  10-16 06:00 bucket, 36 events 10-18 18:00 bucket).
- Effect: supabase gateway flap (+8 restarts last day) — services behind it look offline.

### 4. Unclean simultaneous reboot of gpu + dev nodes 10-16 21:22 UTC (host-level)

- gpu journal ends mid-flight at 21:17:58 (guest-ping, normal etcd compaction) with NO shutdown
  sequence; node boot 21:22:35; all containers exited code 255 "Unknown" at 21:22:49.
- Prometheus: gpu and dev node uptimes both ≈3.19d (boots within ~2 min of each other);
  gpu-ai ≈5.48d (booted 10-14 ~18:30). All three are QEMU VMs (qemu-guest-agent present).
- Simultaneous hard resets ⇒ hypervisor host crash/reboot or power event. Not visible from
  inside the clusters — needs Proxmox/host logs around 10-16 21:20 UTC.

### dev-specific irritant

- 10-18 14:56 UTC: containerd RPC failures (`ContainerStatus from runtime service failed`),
  kine `Slow SQL` writes, apiserver errors → +3 restarts ~14:50. Disk-latency related.
  Quiet in the last 24h.

## Last-24h incident list (as asked)

- gpu: kong OOMKilled 10-20 00:20; K3s upgrade-job k3s kill 10-20 01:40:10-01:41:06 (kubelet
  restart 01:40:40) following 01:39 ArgoCD syncs + chart releases (01:33/01:39/01:49); ArgoCD
  chart redeploy 01:39-01:50; restarts/day: gpu-supabase +8, seaweedfs-csi-controller +9,
  alloy-operator +3, gpu-cloudnative-pg +3, gpu-cert-manager +2, toolhive-operator +3.
- gpu-ai: llama-server Vulkan coredumps 10-19 07:06-07:07 with VRAM-exhaustion storm;
  GPU fence timeouts 10-19 14:06/15:54 and 10-20 00:09/01:09.
- dev: no node-level events in the last 24h (last: kine slow-SQL stall 10-18 14:56).

## Recommendations (not yet implemented)

1. VRAM budget for llama-swap on gpu-ai/gpu: trim preloaded roster or cap concurrent VRAM
   (leading indicator: `amdgpu_vm_validate` errors in node journal; llama-swap already
   restarts crashed backends, but the GPU hangs take the node down with them).
2. supabase kong: raise the 1Gi memory limit or fix the leak (workers reach 1Gi in ~2h50m;
   382 restarts).
3. Stop gratuitous k3s kills: either set `autoUpdateK3s: false` per cluster until K3s bumps
   are intentional maintenance, or make the Plans immune to re-apply churn (ArgoCD
   sync-options / ignoreDifferences on the Plan specs) so jobs only fire on a real version bump.
4. Host check: Proxmox/hypervisor logs for 10-16 ~21:20 UTC (and 10-14 for gpu-ai's reboot);
   also dev VM disk latency.

## Remediation (implemented 2026-10-20, uncommitted on main checkout)

Hypervisor confirmation: pve-gpu IS visible in Grafana/Prometheus (node_exporter,
job integrations/unix). It rebooted 3x in 4d (10-15 ~22:55, 10-16 ~00:20,
10-16 21:20 UTC — last one hard-reset gpu+dev VMs); pve-main rebooted 10-19
02:10 (grow/home/media/infra/monitoring/proxy-local affected). pve-gpu runs a
year-old kernel 6.8.12-16-pve vs 6.17.x on other hosts. Host-level journal
needed (journalctl -b -1 on pve-gpu); not shipped to Loki, no pve_exporter.

1. **Stop spurious K3s-upgrade kills (user: keep auto-update enabled).**
   Added `resource.customizations.ignoreDifferences.upgrade.cattle.io_Plan`
   (/status jsonPointer) to argocd-cm in `charts/base/values.yaml`, matching the
   existing reloader customizations. The controller rewrites Plan /status on
   every reconcile; ignoring it stops selfHeal re-apply churn that coincided
   with the 10-20 01:39 UTC spurious job. Real /spec changes (renovate K3s
   bumps) still apply and fire the upgrade once.
   Note: per-appset ignoreDifferences was tried and reverted in favor of this
   central location (single point, covers all apps/clusters).
2. **Disable supabase on gpu (kong OOM crashloop, 382 restarts).**
   Commented out in `services/gpu/prod/values.yaml`: charts: entry, ingress
   entry, and the hivetools postgresMcp supabase entry (dated notes, archon
   pattern). Archon was already disabled 2026-10-06 (verified; only the
   bitwardenIds block remains in custom-values/gpu, per pattern).
   **TWO-STAGE MERGE REQUIRED** — PVC audit showed ArgoCD pruned the PVCs of
   previously disabled charts (neo4j/archon/qdrant PVCs are gone), and CNPG
   deletes its PVCs when the Cluster CR is deleted. So
   `charts/supabase/templates/{pg-supabase,pvc-supabase-default}.yaml` gained
   `argocd.argoproj.io/sync-options: Prune=false`. Stage 1 = merge+sync the
   chart annotations FIRST; stage 2 = merge the values disable after. Merged
   together, the annotations never reach the live objects and
   pg-supabase-1 (DB) + supabase (20Gi) are destroyed.
   The prune-protected CNPG cluster keeps running after disable; decommission
   it (and the bitwarden items) once the data is no longer needed.
3. Validation: YAML parse all touched files; helm lint + helm template OK for
   charts/base, charts/supabase, services/gpu/prod (deps via
   `helm dependency update`, gitignored); rendered supabase output carries
   Prune=false on Cluster+PVC; rendered argocd-cm carries the Plan
   customization; rendered gpu appset has zero supabase references.
4. Not done here: kong memory-limit fix if supabase is re-enabled, pve-gpu host
   journal investigation + kernel update, pve-exporter/host-journal shipping
   to Loki.

## VRAM remediation (implemented 2026-10-20, uncommitted on main checkout)

Evidence (Loki llama-swap logs + node journals):

- gpu-ai 10-18 04:29 and 10-19 07:07 crashes: both fired the moment the
  startup preload began loading qwen3.6-35b-a3b-q8 while qwen3.8-27b-q8 was
  resident with an active KV pool (opencode streaming). Kernel: amdgpu
  `amdgpu_vm_validate() failed` / `Not enough memory for command submission`
  → Vulkan device-lost → running q38q8 llama-server EOF'd / coredumped
  (libggml-vulkan stack). The trio budget (dense ~38 + MoE ~41 + embed ~1 +
  cache 34 + system ~6 ≈ 119/125 GiB) leaves ~6 GiB — load transients bust it.
- gpu 10-18 16:10 freeze: `kat-coder-q6` (~80B-A3B MoE, ${moe} macro) was
  requested on the 8 GiB 780M at 15:39, VRAM exhausted at load → device-lost
  → node frozen ~27 min (the big gpu outage). Same class as the 2026-10-11
  qwen3.6-35b-a3b-q8 incident; only q35q8 had received the fit-override then.

Changes:

1. `services/gpu/prod/values.yaml` — fail-fast cmd overrides (exit 1 with a
   logged reason; no GPU involvement) for the six ${moe}-macro landmines that
   can never fit 8 GiB: kat-coder-q4/q6/q8 (q6 = the 10-18 incident),
   qwen3.6-35b-a3b-bf16, qwen3.6-35b-a3b-1m (1M KV GPU-resident, no
   --no-kv-offload in the chart entry), qwen3-vl-30b-a3b-bf16 (untuned
   placement unlike the 8GB-measured moe-vl q4/q8). IDs stay routable with a
   "DISABLED… use gpu-ai" description instead of freezing the node. Dense
   models without user-set -ngl are left alone: llama.cpp fit-params degrades
   them to partial offload (fit aborts only when -ngl is user-set — the
   mechanism behind every observed device-lost).
2. `services/gpu-ai/prod/values.yaml`:
   - preload: qwen3.6-35b-a3b-q8 dropped (both crashes were restart-preload
     transients); it lazy-loads on first MoE request. Preload = q38q8 + emb06.
   - matrix main set: q38bf16 (BF16 dense ≈ 66 GiB vs the ~38 budgeted) and
     katq4/katq6/katq8 (48+ GiB experts-on-CPU co-resident with the trio
     overflows the 125 GiB node — same documented reason cnxabl is solo)
     moved to the solo set. Vars unchanged (chart vars deep-merge).
3. Validation: YAML parse ✓; helm lint charts/llama-swap + services/gpu/prod
   + services/gpu-ai/prod ✓; rendered ConfigMap config.yaml parses with all
   matrix vars resolving (gpu 40 models/1 set, gpu-ai 55 models/2 sets) and
   the new preload list (2 entries).

Follow-ups if crashes continue: trim warm-cache caps (q38 24 GiB / q35
10 GiB --cache-ram are the biggest reclaimable headroom), and watch whether
lazy q35q8 loads beside an active q38q8 still hit the transient peak.
Pending operator call: q35q8 `-np 2` → `-np 1` would reclaim ~3 GiB more
(512k→256k preallocated KV pool) at the cost of serializing concurrent MoE
sessions.

## Base chart pin bump (2026-10-20)

Bumped `baseChartVersion` 1.0.197 → 1.0.198 in the gpu, gpu-ai, and dev
appsets so the argocd-cm Plan /status ignoreDifferences lands on those
clusters. 1.0.198 does not exist in the chart repo yet: the Release Charts
CI creates it when the charts/base change merges (release.yaml patch-bumps
changed charts). Between merge and publish the three apps show source errors
and self-heal on retry; running workloads are unaffected. Only the base
change needs the pin bump — the supabase annotations and llama-swap values
flow from main at merge time (internal charts/service values are unpinned).
Renovate owns the pin for all other clusters (annotation intact).

## Validation

Read-only investigation: no charts/values touched, no helm lint/template applicable.
Evidence sources: readonly-gpu-kubernetes (pods, events, node stats/objects), Loki queries
(node journals per cluster, kubernetes-events, system-upgrade logs), Prometheus
(node_boot_time, kube_pod_container_status_restarts_total, kube_node_status_condition,
scrape-gap analysis), git history (charts/base/templates/k3s-version.yaml, merge timeline).