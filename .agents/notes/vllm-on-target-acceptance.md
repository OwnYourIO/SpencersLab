# vLLM on target — acceptance runbook (operator-owned)

**Provenance.** WeKan card cf-105 (`R4EjaHtDeHMjAkDpf`), branch
`cf-105-feat-implement-vllm`; feature folder
`.agents/plans/2026/2026-11-cf-105-feat-implement-vllm/` — plan of record
`2026-11-04-feat-cf-105-feat-implement-vllm.md`, `DECISIONS.md`, `RESEARCH.md`
(cited by section), `chunks/C06.md`. This file is C06: what to verify on the
ai-gpu node after the branch merges and ArgoCD syncs. The first deploy is a
benchmark/acceptance run, not a service flip (R1 top risk 3 — RDNA-vLLM
software maturity). Its measured numbers feed follow-up card #2 (alert
thresholds) and step 10 (the image pin).

**Ground rules.** The cluster's only input is git — ArgoCD applies everything,
and no step here mutates cluster objects. The one sanctioned exception is
step 5b, a temporary values flip that is a GIT change to
`charts/vllm/values.yaml` picked up by ArgoCD's own reconciliation (human-run);
step 10 is likewise a values-only commit. Agent sessions have no pod-exec
tier (EXPLORE §7), so every pod-internal command is operator-run through the
operator's own pod access, and every node-side command runs on the `ai-gpu`
node.

**The honest envelope (D4, HR3/Q3 override) — the benchmark expectations in
step 6 are pre-registered against this, not vibes:**

- One session up to the model's full 256k context: ≈7.8 GiB of fp8 KV —
  fits with headroom on the R9700's 32 GiB (R1 §3).
- Simultaneous sessions share the ~13.4 GiB fp8-KV pool the Q4 weights
  leave; 4×100k ≈ 12.2 GiB runs at the edge.
- When the pool exhausts, vLLM priority-preempts the lower-priority class by
  recompute. That preemption is intended behavior — the arbitration the
  card-Priority work (C03/C04) exists to provide.
- 256k × 3–4 simultaneously is impossible on one 32 GiB card (R1 §3:
  4×256k = 31.2 GiB of KV alone). No step in this runbook claims it.

**Names used throughout (no placeholders).** Pod selector
`app.kubernetes.io/name=vllm`, namespace `default`, release `gpu-ai-vllm`,
node `ai-gpu`. Engine service `gpu-ai-vllm.default.svc.cluster.local:8000`.
Public FE chain `https://llama.spencerslab.com/v1`. Served model name
`qwen3.8-27b-vllm`; urgent class row `qwen3.8-27b-vllm-urgent`. Image
`ghcr.io/ownyourio/vllm-rocm:main` until step 10 pins the first `:v<run>`.
Central stack: Prometheus `prometheus.spencerslab.com`, Grafana
`grafana.spencerslab.com`, Loki `loki.spencerslab.com`.

## 0. Host gates

Operator commands on the `ai-gpu` node, before the vLLM pod is expected to
commit anything. Record every result; the `free -h` reading is the RAM-law
baseline (EXPLORE §8.6: ~125 GiB usable shared by Strata's 116 Gi-limit
pod, the llama.cpp trio, and the OS).

| # | Check | Command | Gate / record |
|---|---|---|---|
| 0.1 | GPU enumeration | `rocminfo` | the agent list shows `gfx1201` and the R9700 is enumerated as device 0 (the 8060S is gfx1151, device 1) — the host driver sees the chip the pod will claim |
| 0.2 | amdgpu driver | `modinfo amdgpu \| grep version` | record the version against the ROCm 10.0 expectations R1 OQ5 names — a driver too old for the v0.33.0-rocm100 runtime is the first suspect for every later GPU failure |
| 0.3 | RAM baseline | `free -h` | record `available` — the node-RAM headroom baseline before vLLM commits anything (EXPLORE §8.6); steps 6e and 9 compare against this |

## 1. Pod facts

After ArgoCD syncs the merged branch, the pod must land on `ai-gpu` and pass
the C02 startup probe (`/health`, 60 s initial delay + 10 s period × 90
failures — the 15-minute envelope).

**1.1 — Pod lands, node is ai-gpu.**

```
kubectl -n default get pod -l app.kubernetes.io/name=vllm -o wide
```

Expected: one pod, node column `ai-gpu`, `READY 1/1` (or `0/1` inside the
15-minute probe window — see 1.2).
If it fails: `Pending` or a different node means the `amd.com/gpu: 1`
request or node placement is wrong — the chart values are the fix surface,
not this runbook.

**1.2 — Startup duration against the probe envelope.**

```
kubectl -n default get pod -l app.kubernetes.io/name=vllm \
  -o jsonpath='{.items[0].status.startTime}'
kubectl -n default logs -l app.kubernetes.io/name=vllm --tail=100
```

Expected: the engine startup lines (weights loaded, model served) well
inside the 15-minute C02 envelope. Record the measured start→ready
duration — the first pull is ~18 GiB plus Triton JIT, and the number feeds
the follow-up probe sizing.
If it fails: restarting past the 90-failure window means the engine never
reached `/health` — the step 3 gates localize which leg.

**1.3 — The chip actually selected (confirms the `ROCR_VISIBLE_DEVICES`
spelling — R1 OQ4).**

```
kubectl -n default logs -l app.kubernetes.io/name=vllm | grep -i -m 5 'gfx\|device'
```

Expected: the log names exactly one chip — `gfx1201` (the R9700).
If it fails: if the env was ignored, the pod sees BOTH chips and the run is
aborted — fix the values key (`rocrVisibleDevices`, under `app-template:`
in `charts/vllm/values.yaml` and `services/gpu-ai/prod/values.yaml`),
not the template. The variable's semantics (device index or UUID, ROCm 10)
confirmed (Post Research V2); only the index is target-verified.

**1.4 — Image-side `rocminfo` (the C01 image's OWN ROCr enumeration).**

Step 0.1 proves the host driver; this one-shot container run of the pulled
image proves the image's enumeration — under the v0.33.0-rocm100 image the
R9700 must sit at index 0, which is what `ROCR_VISIBLE_DEVICES: "0"`
targets (the Post Research V2 residual fact). Node-side, on `ai-gpu`
(containerd via k3s; the pod has already pulled the image into the
`k3s.io` namespace):

```
ctr -n k3s.io run --rm \
  --entrypoint rocminfo \
  --device /dev/kfd --device /dev/dri --group-add 44 \
  ghcr.io/ownyourio/vllm-rocm:main
```

(docker equivalent, if the node has it:
`docker run --rm --entrypoint rocminfo --device /dev/kfd --device /dev/dri
--group-add 44 ghcr.io/ownyourio/vllm-rocm:main`.)

Expected: the gfx1201 R9700 at ROCr index 0.
If it fails: a different index means `ROCR_VISIBLE_DEVICES: "0"` targets
the wrong chip — retarget the values key, then re-run 1.3.

## 2. Weight + cache

**2.1 — Weight presence (RESEARCH Post Research V3).** The exact Q4 file on
the shared 500 GiB PVC: `Qwen3.8-27B-UD-Q4_K_XL.gguf` (16.35 GiB,
`unsloth/Qwen3.8-27B-GGUF`), populated by llama.cpp's `-hf` auto-fetch into
`LLAMA_CACHE=/models` in the HF hub-cache layout:

```
# run inside the vllm pod — the operator's own pod access (no agent tier grants it, EXPLORE §7)
find /models -name 'Qwen3.8-27B-UD-Q4_K_XL.gguf'
```

Expected: exactly the path the chart renders as `--model`
(`/models/hub/models--unsloth--Qwen3.8-27B-GGUF/snapshots/<commit>/…gguf`).
The find output IS the `--model` value — if it differs from the chart's
rendered `modelPath`, that is a values-only fix: record the actual path.
If it fails: file absent means the llama.cpp rung never fetched it — the
weight leg is down, not the engine.

**2.2 — Triton cache under `/data`.** `TRITON_CACHE_DIR=/data/triton` on
the vLLM-cache PVC: record the 1.2 startup duration of the FIRST pod, then
restart the pod once (owner's own rollout trigger — a values no-op touch,
human-run) and record the second duration.
Expected: the second restart is measurably faster (JIT kernels cached).
If it fails: no speedup means the `/data` cache is not persisting — check
the `vllm-cache` claim binding before blaming the kernels.

## 3. Engine smoke (first engine gate)

The first on-RDNA engine proof: does the patched plugin actually load the
qwen3_5 GGUF on gfx1201? No public RDNA run exists (RESEARCH Post Research
V1) — the import probe below is the gate, and a failure here is a C01 image
defect, not a config issue.

**3.1 — Patched-plugin import probe (node-side one-shot).**

```
ctr -n k3s.io run --rm \
  --entrypoint python \
  ghcr.io/ownyourio/vllm-rocm:main \
  -c "import vllm_gguf_plugin"
```

(docker equivalent:
`docker run --rm --entrypoint python ghcr.io/ownyourio/vllm-rocm:main -c
"import vllm_gguf_plugin"`.)

Expected: exit 0, no traceback — the `vllm.general_plugins` registration
chain does not ModuleNotFoundError on the pinned base (the carry patch
absorbs the vLLM #60623 import skew, Post Research V1).
If it fails: stop here and report the traceback — do not continue to 3.2/3.3.

**3.2 — In-cluster `curl` to the vLLM service.** Operator-run, from any
machine with cluster access (read-only probe):

```
kubectl -n default port-forward svc/gpu-ai-vllm 8000:8000
curl -sS http://127.0.0.1:8000/health
curl -sS http://127.0.0.1:8000/v1/models
```

Expected: `/health` → 200; `/v1/models` lists the served name
`qwen3.8-27b-vllm` with `max_model_len: 262144`.
If it fails: `/health` down = the pod is not actually serving (1.2); a
different served name = `--served-model-name` drift in the serveArgs.

**3.3 — One 1-token chat completion.** The GGUF serve + first-token proof —
weights loaded from the step-2 q4 GGUF through the patched adapter, not a
stock safetensors path:

```
curl -sS http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","messages":[{"role":"user","content":"Reply with the single word: ok"}],"max_tokens":1}'
```

Expected: HTTP 200 with one generated token.
If it fails: the weights loaded but decode dies — with `--enforce-eager`
already set, the next suspect is the GDN Triton kernel path on gfx1201
(report the log lines; that is the R1 software-maturity risk materializing).

## 4. FE chain smoke

Through the public chain `https://llama.spencerslab.com/v1` — the peers.vllm
hop is the only client route (D7; the gpu-ai generic-ingress injects the
`llama-timeouts` ServersTransport, `responseHeaderTimeout: 0`, on every
subdomain Ingress, so deep prefills do not 499).

**4.1 — Models list: qualified AND unqualified.**

```
curl -sS https://llama.spencerslab.com/v1/models
```

Expected: `qwen3.8-27b-vllm` is listed (unqualified resolution — lab
convention, D10) and the qualified form `vllm/qwen3.8-27b-vllm` resolves.
Record whether the entry carries a `max_model_len` — that is R3 OQ3
(closes on-target: does the pinned llama-swap v266 populate the peer
model's context length in `/v1/models`?).
If it fails: the model missing from the list = the peer block or its
`models:` entry is wrong in `services/gpu-ai/prod/values.yaml`.

**4.2 — STREAMED chat completion (SSE through the public chain).** This is
the R3-weakest-claim verification: "no SSE risk through the lab's public
chain" was inferred (Go flush semantics, no compress middleware, the
working llama.cpp streaming chain) and never measured — the first streamed
vLLM response through the public host is the measurement.

```
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","stream":true,"max_tokens":32,"messages":[{"role":"user","content":"Count from one to five, one word per line."}]}'
```

Expected: `data:` lines arrive incrementally (several bytes at a time over
seconds), ending `data: [DONE]`.
If it fails: one lump at the end = a hop is buffering (next suspect: a
compress middleware — none is in the repo — or the transport); 502-EOF =
the post-SSE keep-alive class (R3 OQ4 watch-item: no peer-level
`disableKeepAlives` in v266 — file upstream, tune uvicorn).

**4.3 — The `/ui` models page.** Open `https://llama.spencerslab.com/ui` →
Models.
Expected: `qwen3.8-27b-vllm` listed (peer models appear in listings — R3 Q5).

**4.4 — The urgent model row.** A request via `qwen3.8-27b-vllm-urgent`
works — the OpenCode row's `body` merge is live:

```
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm-urgent","max_tokens":8,"messages":[{"role":"user","content":"Reply: ready"}]}'
```

Expected: 200 + completion — the row resolved to the same wire model with a
different body priority. This closes R4's medium-confidence claim (a): the
first observed model-level `body` merge on this exact provider chain.
If it fails: the row 404s or resolves to a different model = the catalog
row / peer name is wrong in `.opencode/opencode.jsonc` or the peer block.

## 5. Priority proof (R4 acceptance lines)

The engine runs `--scheduling-policy priority` (C02 serveArgs), so a
non-zero body priority is legal; the peer floor `filters.setParams
"priority?": 10` puts non-priority clients in the default class. Class
rows (D6): urgent class row `qwen3.8-27b-vllm-urgent` (priority 1),
default class row `qwen3.8-27b-vllm` (priority 10).

**5.1 — Explicit `priority: 5` through the full chain.**

```
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","priority":5,"max_tokens":8,"messages":[{"role":"user","content":"Reply: ack"}]}'
```

Expected: 200 + completion — the non-zero value is legal under the
priority policy and the body field reached vLLM.

**5.2 — OPTIONAL: fcfs negative proof.** The only step that requires a
temporary flip; belt-and-braces for the R4 pass-through claim (the step-4
chain smoke already exercises the body merge for both class rows). Run it
only if the owner wants the negative proof:

1. GIT values change (human-run): in `charts/vllm/values.yaml`'s
   `app-template.serveArgs`, flip `--scheduling-policy` from `priority`
   to `fcfs`; commit on the ticket branch; ArgoCD's own reconciliation
   picks it up (no manual sync — sync is not a runbook step).
2. Re-run the 5.1 request.
   Expected: vLLM REJECTS it with the non-zero-priority error (the fcfs
   gate, R4 Q1) — proving the body field survived both OpenCode's merge
   AND llama-swap's proxy end-to-end.
3. Flip the values back to `priority`; re-sync; re-run 5.1 to confirm 200.
   Do not leave `fcfs` in place.

**5.3 — Behavioral: two classes saturating the pool** (R4 acceptance
line 2). Drive two concurrent sessions of different classes until the
pool is saturated (≥100k prefills at `--max-num-seqs 4`), then read the
preemption split in central Prometheus:

```
sum by (model_name) (increase(vllm:num_preemptions_total[10m]))
histogram_quantile(0.5, sum by (le) (rate(vllm:request_num_preemptions_bucket[30m])))
```

Expected: the urgent class shows NO preemptions while the default class
does. A PASS is the priority split holding — preemption under exhaustion
is the design (D4), not a fault.
If it fails: urgent-class preemptions mean the class values did not reach
the engine (check 4.4 and the row's `body` merge); zero preemptions
anywhere = the pool never saturated (drive longer contexts).

## 6. Benchmark (pre-registered — the D4/Q3 envelope)

The expectations below are registered BEFORE the numbers: one 256k
(≈7.8 GiB KV) fits, 4×100k (≈12.2 GiB) sits at the ~13.4 GiB pool edge,
256k × 3–4 simultaneously is impossible on one 32 GiB card (R1 §3).
Record every number — they are the follow-up card #2 thresholds.

**6.1 — Single-session 256k-prefill TTFT** (the envelope's headline case —
one full-context request must complete). A 262144-token prompt, small
`max_tokens`; time to first byte is the number. Expect minutes-scale
physics: R1 §4 measured 131.5 s TTFT at 128K and 320.7 s at 256K on the
8060S even under llama.cpp — the R9700 is faster but the same KV physics.
The peer `responseHeader: 1800` covers the end-to-end first byte; the C02
startup probe is unaffected (it hits `/health`, not a completion).

**6.2 — 100k-prefill TTFT, single session.**

**6.3 — 2–4 concurrent ≈100k sessions, aggregate tok/s.** The R1 §4
measured-pattern comparison point (32B-FP8 on 2×R9700: ~3× single-stream
at c=3, ~7× at c=8). This card is one R9700 at `max-num-seqs 4` — expect
within that pattern's 2–4× band, and record where 4×100k actually lands
relative to the pool edge.

**6.4 — Single-stream tok/s.** The llama.cpp-parity expectation is ≈30 on
the R9700 (R1 §4: llama.cpp 27B Q4_K_M 29–33 tok/s; vLLM 32B-FP8
1-stream 25.8–29.1 on 2×R9700 eager).

**6.5 — Node RAM headroom after full load.**

```
free -h
```

Compare `available` against the step 0.3 baseline (EXPLORE §8.6).
Expected: the delta stays inside the vLLM pod's 16 Gi request / 32 Gi
limit — no swap-thrash, no pressure on Strata's 116 Gi-limit pod.

**6.6 — KV-pool exhaustion behavior.** Several simultaneous long sessions
until `vllm:kv_cache_usage_perc` (central Prometheus) peaks:

```
vllm:kv_cache_usage_perc{model_name="qwen3.8-27b-vllm"}
```

Expected: the gauge peaks, the lower-priority class is preempted +
recomputed while the urgent class is unimpeded. A PASS when the priority
split holds — the Q3 trade-off working as designed (preemption is
intended; the recompute cost is R4 OQ6 territory, recorded for the
follow-up).

## 7. Monitoring check (R5 deploy confirmations)

**7.1 — `up{job="vllm"}` in central Prometheus**
(`prometheus.spencerslab.com`):

```
up{job="vllm"}
```

Expected: 1. This confirms the job-label fallback (R5 Q2): no
`k8s.grafana.com/job` annotation is shipped, so the job falls back to
`app.kubernetes.io/name` = `vllm`.
If it fails: `up` absent = the pod annotations did not land (7.6);
`up{job="..."}` under a different job name = the fallback chain broke.

**7.2 — The histograms are quantile-computable** (RW 0.1 classic-histogram
integrity through the remote-write into central Prometheus 3.6.0, R5 Q2):

```
histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[10m])))
```

Expected: a finite number once 6.1–6.2 have produced TTFT samples (not
NaN, not empty).

**7.3 — Both dashboards render in the central Grafana**
(`grafana.spencerslab.com` → `default` folder):
`vllm-performance-statistics` + `vllm-query-statistics` (C05's `url:`-pinned
entries, tag v0.33.0). This is the R5-weakest-claim closure: the import was
verified by inspection only (no Grafana write tier in the research
session) — opening both panels is the execution.
Expected: both render with data after the step 6 benchmarks.

**7.4 — The Loki stream for the pod** (`loki.spencerslab.com`, LogQL):

```
{container="vllm"}
```

Expected: the engine log lines (periodic engine stat line, which
self-demotes to DEBUG when idle) plus uvicorn access lines WITHOUT the
suppressed `/health`, `/metrics`, `/ping` noise (the
`--disable-access-log-for-endpoints` flag, R5 Q3).

**7.5 — `finished_reason` enum values** observed in central Prometheus:

```
vllm:request_success_total
```

Record the distinct `finished_reason` label values seen (R5 OQ6 — they feed
follow-up card #2 alert #9, which filters
`finished_reason=~"error|abort"`).

**7.6 — Scrape annotations: exactly two, no interval key.**

```
kubectl -n default get pod -l app.kubernetes.io/name=vllm \
  -o jsonpath='{.items[0].metadata.annotations}'
```

Expected: `k8s.grafana.com/scrape: "true"` and
`k8s.grafana.com/metrics.portNumber: "8000"` — and the ABSENCE of a
`metrics.scrapeInterval` annotation (Q5 ruling: the 60 s scrape is the
k8s-monitoring v4 annotationAutodiscovery feature default; the absence is
the contract).
If it fails: a third `k8s.grafana.com/*` key = an annotation crept into
`charts/vllm/values.yaml`; an enabled value that is not `"true"`/`"8000"` =
the `app-template.monitoring.annotations` gate is mis-rendered.

## 8. Sleep-mode check + the R9700 time-sharing sequence (D5/HR6)

The documented sequence — NOT a bare sleep/wake pair. The dev endpoints
exist because C02 sets `VLLM_SERVER_DEV_MODE: "1"` (v0.33.0 attaches
`/sleep`, `/wake_up`, `/is_sleeping`, `/release_kv_cache_memory` only in
dev mode — Post Research V5). Level-1 sleep keeps the offloaded weights
but discards KV + the GDN recurrent/conv state, re-created on wake
(in-tree regression-tested). Strata stays evicted from the R9700 for the
whole window; it comes back only in 8.3. Use the 3.2 port-forward.

**8.1 — `POST /sleep` (level 1).**

```
curl -sS -X POST 'http://127.0.0.1:8000/sleep?level=1'
```

Expected: 200; then `curl -sS http://127.0.0.1:8000/is_sleeping` reports
sleeping at level 1.

**8.2 — Verify VRAM reclamation on the R9700 BEFORE waking (the gate).**

```
# central Prometheus:
vllm:engine_sleep_state{model_name="qwen3.8-27b-vllm"}
# on the ai-gpu node:
rocm-smi --showmeminfo vram
```

Gate: `vllm:engine_sleep_state` shows `weights_offloaded` AND the R9700's
free VRAM is back up in the node reading.
Documented ROCm caveat (Post Research V5, the vLLM GDN sleep/wake
regression-test docstring): on some amdgpu drivers the VRAM discarded by
`sleep()` is not returned to the free pool before `wake_up()` re-creates
it, so the woken allocation must coexist with the not-yet-reclaimed one —
~2x peak. With `gpu_memory_utilization` at 0.95 (D4), that coexistence
OOMs in `cuMemCreate` on wake.
- Gate passes → proceed to 8.3.
- Gate fails → do not wake. Record the `rocm-smi` free-VRAM numbers
  before/after the sleep (the on-target measurement for the Post Research
  open question 5) and stop the sequence — the time-sharing discipline is
  suspended until the owner rules on the driver/limit interaction.

**8.3 — `POST /wake_up` (only when the 8.2 gate passed).**

```
curl -sS -X POST 'http://127.0.0.1:8000/wake_up'
```

Expected: `vllm:engine_sleep_state` back to `awake`, and a 1-token
completion (the 3.3 command) still succeeds. THEN allow the Strata
re-pin on the R9700 (step 9 observes the coexistence afterwards). Record
the wake-up duration — the R9700/Strata time-sharing cost that feeds the
Q6 ruling.
If it fails: a `cuMemCreate` OOM on wake is the 8.2 caveat materializing
(reclaim did not actually complete despite the gate reading — re-run 8.2's
record and stop); a hung wake = report the engine logs.

## 9. Strata coexistence observation

With Strata warm (arena re-pinned on the R9700 per 8.3), one vLLM request
completes without node-level OOM. The two chips are separate (R9700 vs
8060S); the RAM claim is what to watch (EXPLORE §8.6) — record the node's
`available` before/after:

```
free -h
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","max_tokens":8,"messages":[{"role":"user","content":"Reply: ok"}]}'
free -h
```

Expected: the request completes; no OOM-kill of either pod; the
`available` delta stays inside the vLLM pod's 32 Gi limit.
If it fails: node-level pressure means the two pods' RAM budgets do not
coexist — that is the EXPLORE §8.6 law biting, and it is a sizing change
(chart values), not a runbook fix.

## 10. PIN-ME follow-through

After the CI build lands (`docker-build.yaml` pushes `:v<run_number>`
(immutable) + `:main` (rolling) on the merge):

1. In `charts/vllm/values.yaml`, pin the image `tag` to the first
   `:v<run_number>` (the immutable tag — never `:main` steady-state) and
   drop `pullPolicy` to the default (delete the `pullPolicy: Always` line).
2. Delete the PIN-ME comment.
3. Re-run C01's ledger note: record the new versioned tag in the
   tag→digest ledger of `containers/vllm-rocm/README.md` (its manual-bump
   procedure; the base tag `v0.33.0-rocm100` + plugin git ref + import
   patch are unchanged — only the overlay image gains a version).
4. Record which leg this landed as: a values-only commit on the ticket
   branch BEFORE the PR (if the `:v<run>` exists at review time) — or the
   owner's first post-merge follow-up commit.

## If the owner wants a public host later (not a step)

The Q4 ruling kept vLLM cluster-internal (no `vllm.<domain>`); the
alternative, when the owner changes their mind, is two values edits — no
chart work:

1. One `ingress.subdomains.vllm` entry in `services/gpu-ai/prod/values.yaml`
   (`service: gpu-ai-vllm`, `port: 8000`). The gpu-ai generic-ingress
   already injects the `llama-timeouts` ServersTransport on every
   subdomain Ingress (`forwardingTimeouts.responseHeaderTimeout: 0`) — a
   public vLLM surface needs exactly that for deep-prefill 499s (EXPLORE
   §8.8).
2. The proxy-local `target: gpu-ai` leg in
   `services/proxy-local/prod/values.yaml` (the `llama:` entry is the
   shape precedent, with the Keycloak SSO redirect).

If browser UIs ever point at the public host directly, the v0.32+ CORS
`--allowed-origins` story (R3 OQ6) also enters.
