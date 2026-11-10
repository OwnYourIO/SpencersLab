# 2026-11-10 debug — strata pod (gpu-ai) OOM crash-loop on the q4 rung

> **Correction addendum (same day, post-research).**
> `.agents/plans/2026-11-10-research-strata-q3-q4-rungs.md` (§5/§7, sources
> verified three ways) corrects three first-pass claims below:
> (1) `--kv-resident` is a VRAM cell window (32,768 cells ≈ 0.4 GiB
> VRAM/slot), NOT a 32 GiB host-RAM budget — trimming it frees zero host RAM;
> (2) the collapse's ~25 GiB transient was parking/heap-dominated, not KV
> (2×99k prefills = only ~2.7 GB at the verified 13,728 B/token int8 law),
> amplified by upstream Strata #5697 — evicted parked conversations retained
> in the glibc heap; reporter-confirmed one-env-line workaround on our 0.2.9
> pin: `MALLOC_MMAP_THRESHOLD_=1048576`;
> (3) llama-swap `concurrencyLimit` rejects excess requests with HTTP 429
> immediately — it does not queue.
> Root cause and Recommendations sections updated in place accordingly.

## Symptom

`gpu-ai-llama-swap-strata-5fd4c94fcc-x8r57` (default ns, gpu-ai cluster, node
`ai-gpu`): container `strata` OOMKilled (exit 137, `reason: OOMKilled`) 11 times
on 2026-11-10 — restart steps at 01:57, 02:08, 02:22, 02:47, 02:51, 11:22,
11:23, 11:25, 11:26, 12:28, 12:30 UTC (Prometheus
`kube_pod_container_status_restarts_total`). Node events: `SystemOOM … victim
process: strata` at 11:22:30, 11:23:35, 11:24:52, 12:27:17. Collateral: the
02:08–03:02 storm also harvested metrics-server, argocd-repo-server,
alloy-operator, toolhive (their restart ages align).

## Evidence

- Node `ai-gpu` MemTotal = 125.1 GiB (single node).
- `node_memory_MemAvailable_bytes` (Prometheus, cluster=gpu-ai):
  - 00:44 → 114 GiB avail; 00:58 → 27.9 GiB (q4 arena pinned: engine logged
    `experts loaded: 71.73 GiB at 4.90 GiB/s`; steady loaded working set
    90–99 GiB incl. PLE mmap pin).
  - 01:56–02:20 → avail collapses 25.9 → 1.5 → 0.7 GiB = node-wide exhaustion
    (not just the 116Gi cgroup).
  - 03:06–11:18 → strata idle (0.2 GiB), avail ~86 GiB.
  - 11:22–11:26 and 12:27–12:30 → killed ~50 s into cold reloads (working set
    caught mid-load at 36 GiB); one attempt at ~12:30 succeeded.
- Loki (container=strata), 01:40–02:05: one agent session's context climbs
  56k → 98,844 prompt tokens; at 01:56:24 TWO concurrent prefill streams on
  the same 98.8k prompt (client retry while the first was in flight); decode
  collapses to 16.9 tok/s, `output 1`, then engine restart. After each reload
  the doubled ~99k prefill resumes immediately → kill within ~10 min (01:57
  cycle) or ~60 s (02:0x cycles).
- Main llama-swap (trio) pod stayed ≤ 2.7 GiB throughout — no trio model was
  resident; no vLLM pod existed. Strata's own q4 traffic was the sole load.
- Trigger change: commit fb3f7aa0b (2026-11-09, owner ruling) routed
  Flash+Local — the hourly pipeline runner model — to
  `qwen3.8-flash-next-strata-q4`, making the 71.7 GiB-arena rung the constant
  production load for the first time.

## Root cause

(Corrected in place per the research file §5/§7 — the first-pass attribution
to KV overrun was wrong.)

The q4 rung's real footprint under production agent traffic exceeds the
125.1 GiB single-node budget:

- Pinned floor: 71.73 GiB experts + ~28 GiB-class PLE table (`direct` mode)
  + ~6 GiB dense/MTP/supervisor → ~90–99 GiB working set at steady state.
- Verified KV law (int8, 13 KV-bearing layers × 1,056 B/token): 13,728 B per
  context token per slot → 1.28 GiB per 100k tokens; 4-slot full-262k worst
  case 13.4 GiB (the budget's counted "~13 GiB" was numerically right). Two
  concurrent 99k prefills ≈ only ~2.7 GB of KV.
- `--kv-resident 32768` is a VRAM cell window (~0.4 GiB VRAM/slot), not a
  host-RAM budget — the values.yaml "32 GiB KV streaming budget" comment is
  wrong (docs round needed).
- Observed killer: TWO concurrent ~99k-token prefills (parallel agent
  sessions + client retries) on top of the ~90–99 GiB steady base → ~25 GiB
  parking/heap/transient growth (exact decomposition not recoverable from
  existing metrics; candidates: parking snapshots up to the 16 GiB conv
  budget, checkpoint pools, prefill staging rings, page-cache transients) →
  node RAM exhausted → kernel SystemOOM picks the largest RSS (strata) →
  OOMKilled → CrashLoopBackOff.
- Amplifier: upstream Strata #5697 (open, filed 2026-11-10 — same shape as
  this incident): once the conversation cache fills and evicts, the evicted
  bytes stay in the glibc heap, the engine's RAM admission gate refuses
  parking forever, and MemAvailable never recovers. Every kill also triggers
  client retries → cold reload re-pins 71.73 GiB and re-prefills the huge
  contexts, sometimes OOMing mid-load (the ~50 s deaths) → death spiral
  until clients give up.

The accepted config's own worst case (values comment: "~116.7 of the 125 GiB
node") leaves no room for the ~10–13 GiB cluster baseline; the Nov-9 routing
change made that worst case routine instead of rare. Same failure family as
the documented 2026-10-29 "OOM harvest" incident.

## Recommendations (owner decision — budget law is owner-gated)

Corrected per the research file §2A, cheapest first:

1. Add `MALLOC_MMAP_THRESHOLD_=1048576` to the strata model env —
   reporter-confirmed fix for the #5697 eviction-retention spiral;
   glibc-level, engine-version-independent, works on the pinned 0.2.9 build.
2. Single-flight the q4 arena: `concurrencyLimit: 1` on the q4 model —
   excess requests get HTTP 429 immediately (clients must back off/retry;
   llama-swap does not queue).
3. Right-size from the verified KV arithmetic: `parallel: 4 → 2` halves the
   4-slot worst-case KV (13.4 → 6.7 GiB) and the transient stacking; and/or
   `--conversation-cache-mib 16384 → 8192` (note: 8192 was the U8 value,
   half-reverted at the 2026-11-01 owner gate — re-trimming needs a fresh
   ruling). Leave `--kv-resident` alone for RAM purposes (it is VRAM).
4. Lower the cgroup so the container dies before the node: 116Gi →
   ~108–110Gi (the 2026-11-10 SystemOOM harvested cluster system pods
   precisely because cgroup + node floor exceeded total RAM).
5. Interim traffic option: route the hourly runner back to the q3 flagship
   (46.84 GiB arena, ~10–30% faster decode, 87.7% vs 93.1% top-token match)
   until the q4 envelope is re-ruled.
6. Engine pin: stay on 0.2.9/0.1.55 — 0.2.12 has an open gfx1201
   crash-regression cluster (#5559/#5635/#5564), 0.2.13 (0.1.59) is unproven;
   any bump follows the containers/strata ledger + soak + `--plan` + re-bench
   law (research §2D).
7. Docs round: correct the `--kv-resident` / "worst-case KV" comments in
   charts/llama-swap/values.yaml to the derived arithmetic (research §5).
8. Hygiene (non-causal): engine warns the config passes each `--flag value`
   as one argv element ("split into the flag and its value"); tolerated
   today, fragile across engine bumps.

## Live risk at write time (12:40 UTC)

Container reloaded ~12:30 and is serving TWO concurrent thinking streams
(24k-token budgets) at 91.4 GiB working set; node avail back to ~27.8 GiB —
the same pre-collapse shape as 01:56. Recurrence likely if those sessions
grow toward ~100k contexts or a second cold-load race occurs.

Update (post-research re-check): working set has climbed 91.4 → 114.8 GiB
with NO restart (restartCount still 11), node avail steady ~28.6 GiB — the
#5697 heap-retention signature (evicted parks invisible to the engine's RAM
gate, visible to the cgroup). The container is within ~1.2 GiB of its 116Gi
cgroup ceiling; another kill is likely unless traffic stops or the pod is
recycled.

## Validation / method

Read-only investigation: readonly-ai-gpu-kubernetes (pods, events, logs,
deployment/RS), Grafana Prometheus (restart staircase, node MemAvailable,
container working sets), Loki (engine logs across the collapse), repo history
(git log charts/llama-swap, containers/strata; values.yaml budget comments;
.agents/notes/strata-host-prep-gpu-ai.md). No cluster mutations, no repo
source changes.
