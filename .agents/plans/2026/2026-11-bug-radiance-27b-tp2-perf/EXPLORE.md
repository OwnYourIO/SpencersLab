# EXPLORE.md — 27b-TP2 lane performance ground truth (owner's 2026-11-23 run)

*Scout round, 2026-11-23 ~20:04–20:40Z. Sources: repo reads (worktree
`feat-radiance-multi-instance` @ cbd77c82e, clean ticket folder),
`tools["readonly-global-grafana"]` PromQL (datasourceUid `prometheus`) and Loki
(datasourceUid `P8E80F9AEF21F6940`), read-only git. No writes anywhere except this
file; no admin tiers; no pod exec; every figure below carries its exact query +
window. No metric was invented: every series name was verified present in the TSDB
before use (metric-name census `{__name__=~"radiance:.+|vllm:.+"}` instant query).*

## 0. Provenance, access, file handling

- **Path correction honored.** The launch named
  `.../2026-11-bug-radiance-27b-context-window/EXPLORE-27B-TP2-PERF.md`; a
  coordinator correction (mid-run) redirected the deliverable to this
  folder-of-its-own per the one-folder-per-piece-of-work convention. The old path
  **never existed** (verified `stat` — no such file; the concurrent-writer check
  applied to it found nothing to append to). Nothing in the
  `bug-radiance-27b-context-window` folder was touched. This file is the only write.
- **Concurrent-writer posture:** the new folder was created by this write
  (`write` auto-creates parents); nothing pre-existed at the new path either
  (verified `test -e` before writing: "target absent").
- **Grafana access verified working** — Prometheus range/instant queries, Loki
  label/log/stats queries, datasources API all live this round. Two tool-shape
  gotchas for the next agent:
  - `query_prometheus` takes `expr`/`startTime`/`endTime`/`stepSeconds`/`queryType`
    — NOT `query`/`start`/`end` (the error prints the correct keys).
  - `query_loki_stats` takes `logql` and **rejects line filters/pipelines**
    ("only label matchers are supported"); `query_loki_logs` accepts full LogQL.
    Radiance **engine** logs are indexed under `{cluster="gpu-ai",
    container="radiance"}`; the `pod` label is NOT in the Loki index for them
    (`list_loki_label_values pod=...` returns only loki-canary) — pod identity is in
    `structuredMetadata.pod`, so per-pod selection must be client-side, and label
    selectors like `{pod="gpu-ai-radiance-q27-tp2-..."}` return 0.
- **Scrape surface is cf-145's** and it works: the `radiance` job exists
  (`job` label value census), series carry `cluster="gpu-ai"`, `job="radiance"`,
  `model_name="qwen3.8-27b-radiance-tp2"`, `instance=<podIP>:8000`, `engine="0"`.
  Mechanism: `k8s.grafana.com/*` annotation autodiscovery (cf-145 DECISIONS D-8,
  `.agents/plans/2026/2026-11-cf-145-feat-radiance-grafana-metrics/DECISIONS.md:24`),
  chart gate `monitoring.annotations: true`
  (`charts/radiance/values.yaml:251-252`), annotation pair
  `charts/radiance/values.yaml:273-275`, 60 s default interval, path `/metrics`.
- Never invent a metric — honored; see §10 for what genuinely does not exist.

## 1. Verified time window + inferred offset

**Owner's raw guess (from the launch):** 27b ran `08:30→12:00`, flash `12:00→now
(~19:55)`. Taken as UTC this is **false** (below). All timestamps UTC, 2026-11-23
unless dated otherwise.

Pod chronology for `gpu-ai-radiance-q27-tp2` (Deployment `gpu-ai-radiance-q27-tp2`,
served id `qwen3.8-27b-radiance-tp2`), from `up{job="radiance"}` and
`rate(vllm:generation_tokens_total[5m]) > 0` range queries (now−30 h, step 300 s)
and boot echoes in Loki:

| pod (RS) | config booted | scrape up | engine activity (nonzero token rate) |
|---|---|---|---|
| `...-77b576cb54-d8sj7` | **200000** (argv echo 2026-11-22T22:25:42) | 11-22 22:27 → 11-23 03:57 | 11-22 22:30 → 11-23 03:40 (the *previous night's* heavy run: +93.6 M prompt, +1.03 M gen by 03:07) |
| `...-648f6dd5c7-ppt7l` | **262144** (argv echo 04:01:38) | 04:07 → 18:46 (+log tail to 18:49:52) | bursts 04:05→04:35, 04:50, 05:30→05:40; **idle 06:07→15:07** (counters frozen at prompt=11,102,397 / gen=219,941 across 06:07–15:07 hourly samples); **main run 15:40 → 18:50**, with an internal idle gap ~17:10→17:45 |
| `...-544c9bbdf5-rs6cp` (fn lane, out of scope) | 262144 (argv echo 18:49:59) | 18:52 → present | serving from ~18:57 |

- **The owner's 27b run = ppt7l 15:40→18:49:52Z (SIGTERM drain line 18:49:52,
  last completion 18:49:01): ~3 h 10 min.** This matches the launch's "~3.5 h".
- **Inferred clock offset ≈ UTC−7**: owner 08:30 ↔ measured 15:40 (+7 h 10);
  owner 12:00 ↔ fn boot 18:49:59–18:52 (+6 h 50/52). The coordinator's
  parenthetical "now ~19:55" is **server/UTC** (matches my `date -u` 20:04Z at
  session start), not the owner's clock — do not treat 19:55 as owner-local "now".
- The raw-as-UTC guess fails both ways: at 08:30–12:00Z the 27b counters are
  **frozen** (idle), and no flash lane existed before 18:49:52Z.
- **Deploy wrinkle (provenance, not conclusion):** the pod rendered with
  `--max-model-len 262144` at 04:01:38, but the ArgoCD manifest-cache key logged at
  the 03:50 comparison names revision `0eeee59c3` which — verified by
  `git show 0eeee59c3:services/gpu-ai/prod/values.yaml` — still carries `200000`
  at all four lanes, and the landing merge `bc4b2a3fa` carries author-date
  04:41:49 (≈40 min AFTER the boot that served 262144). The 03:59:19–04:00:09Z
  SyncOperations logged `Revision:` (empty = resolved target HEAD). The rendered
  env demonstrably contained the raise at 04:01:38; which ref-state ArgoCD
  resolved at 03:59 is **not determinable from the data side** — flagged as an
  open question. The runtime facts below are unaffected.
- Same sync wave (03:59–04:01Z) briefly rolled fn too: `5b69c57dc8-5qvzf` argv
  echo 03:59:30 (200000) → `544c9bbdf5-rnrgh` argv echo 04:00:07 (**262144**);
  rnrgh never appears in `up` (scaled down again with no scrape — consistent with
  the parked-lane shape).

## 2. Configured shape (repo, with `file:line`)

**Lane block `radiance-q27-tp2`** — `services/gpu-ai/prod/values.yaml` (line cites
= this worktree @ cbd77c82e; content-grepped):

| item | value | cite |
|---|---|---|
| `modelPath` / `RADIANCE_MODEL_PATH` | `/models/radiance/qwen3.8-27b-mxfp4.rad` | :1645, :1688-1689 |
| `RADIANCE_SERVED_ID` | `qwen3.8-27b-radiance-tp2` | :1690-1691 |
| `RADIANCE_TP` / `RADIANCE_TP_WIRE` | `"2"` / `wht6` | :1692-1695 |
| `RADIANCE_MAX_MODEL_LEN` | **`"262144"`** — C02 PROVISIONAL raise (ruling D1), annotation names the pending receipt | :1696-1715 |
| `RADIANCE_PREFIX_CACHE_MIB` | `"4096"` | :1716-1717 |
| ABSENT by the dense-bars law (named list) | `RADIANCE_KV_RESIDENT`, `RADIANCE_PLACEMENT`, `RADIANCE_HOST_POOL_MIB`, `RADIANCE_NGRAM_PLACEMENT`, `RADIANCE_NUM_SPECULATIVE_TOKENS`, `RADIANCE_GPU_HEADROOM_MIB`, `RADIANCE_MAX_NUM_BATCHED_TOKENS`, `RADIANCE_CHECKPOINT_INTERVAL` | :1663-1668 |
| replicas | `0` in git (owner scale act runs it; observed live 1/1 all day) | :1660 |
| memory class | `24Gi` request==limit (Guaranteed; held per D7/D10) | :1718-1734 |
| gpu claim | `amd.com/gpu-r9700: "2"` both maps (both cards while up) | :1730, :1734 |
| cpu | `"8"` | :1728, :1732 |
| stale prose (found, not asserted wrong elsewhere) | comment at :1683-1686 still says "the dense context terms ride unchanged from q27 (per-session **200000** ceiling…)" while :1714 ships 262144 — pre-C02 wording that survived the annotation law; runtime truth is 262144 (§7) | :1683-1686 |

Sibling `radiance-q27` (TP1 twin): `services/gpu-ai/prod/values.yaml:1299-1489`;
same absences; env `RADIANCE_MAX_MODEL_LEN "262144"` at :1441-1442; `24Gi`/claim `"1"`.

**FORM-fixed flags** — `charts/radiance/values.yaml` serve.sh (D43): the compose
wrapper fixes `--port 8000 --host :: --max-num-seqs 8 --kv-cache-dtype fp8` and the
required trio (`--model/--served-model-name/--tp/--max-model-len` loud-guarded);
everything else is env-fed and **absent env = absent flag**
(`charts/radiance/values.yaml:210-241`, fixed pair :226-228). The boot echo
`radiance serve: composed engine argv: $*` (:240) is the receipt line that §7
quotes verbatim. Image pin `stilldeadcode/radiance:1.17.0` (:332-346).
Recreate + 180 s grace (:324, :276); startup probe `/health` up to 30 min
(:375-386); shm 2 GiB (:545-548); devices injected by the named-pool plugin,
no hostPath (:551-554). cf-145 scrape gate/annotations (:251-252, :273-275).

**Engine defaults that fired anyway (boot prints, §6/§7):** `--gpu-headroom-mib`
applied at **96 MiB default** despite no env ("the 96.00 MiB --gpu-headroom-mib and
136.26 MiB kept for the step staging"); `--num-speculative-tokens` resolved to
**7** ("depth 7, this drafter's own operating point" — the in-pack DFlash2 states
it; the flag's absence does NOT mean speculation off); `--p2p auto → peer to
peer`; `--embedding-placement ram` default (1.18 GiB token-embedding per rank
pinned host, "read over the link in place"); `--busy-prefill-chunk auto` keeps
≥ 64 tokens (dense; fn's MoE print says 1024); `checkpoint-interval` default 2048
("9 for a 262144-token session at a 2048-token interval"); `--ngram-placement n/a`
("this model has no n-gram table").

**Canonical metric names (cf-145):** dashboard family list
`.../cf-145-.../EXPLORE.md:41` (fact 11). Live TSDB confirms extras beyond that
list: `radiance:prefill_tokens_per_second`, `radiance:decode_tokens_per_second`,
`radiance:engine_prefill_chunks_capped_total`, `radiance:decode_step_seconds_{best,recent}`,
`radiance:kv_cache_max_{tokens,bytes}`, `radiance:kv_stream_bytes_total{dir="in"}`
(only `in` exists), `radiance:draft_*`, `radiance:prefix_cache_*` (+
`_by_reason_total`), `vllm:` TTFT/TPOT/e2e histograms (µs-scale buckets),
`vllm:request_success_total{finished_reason="stop|length|tool_calls|abort|error"}`,
`vllm:prompt_tokens_total`, `vllm:generation_tokens_total`,
`vllm:num_requests_running/waiting`, `vllm:gpu_cache_usage_perc` ==
`vllm:kv_cache_usage_perc`, `vllm:gpu_prefix_cache_hit_rate`. No
`amdgpu`/`vram`/`rocm` families exist anywhere in the TSDB
(`count by (__name__) ({__name__=~".*(vram|amdgpu|gpu_mem|rocm).*"})` = empty).

**Read-not-restated ticket docs** (this worktree): `.agents/notes/radiance-q27-boot.md`
(receipt law: the print adjudicates); `.agents/notes/radiance-second-gpu-tp2.md`
(§2 switch-fabric ~13.4 GB/s P2P class, §7 recipe, §8 envelope tables);
`.agents/notes/radiance-host-tuning.md` (§1 LINK CLOSED at **Gen4 x4** on the
swapped socket — rank-0-class path; the Gen3-era `3.94 GB/s ≈ half of 7.0–7.2` and
"the fix landed at the M.2 socket" (D44); §14 mover/heat-engine is fn-MoE, not
this dense lane); `.agents/notes/radiance-on-target-acceptance.md` (step-0 receipts);
ticket `DECISIONS.md` D1-D19 (D1 raise ruling; D2 warn-not-refuse hazard;
D9(a) M≥8 bar is fn-only; D16 gate limits; D19 merged);
`RESEARCH.md` V3 (**"TP2 buys card memory, not host RAM"**, 32 KiB trunk /
~64 KiB "effective" per token, 262144 fits TP2 ~100 MiB/card headroom per Wilde)
and V5 (TP2 = 1.67× speed class; TP collectives "stage through pinned host memory"
— **that clause is the Wilde rig, contradicted by this rig's P2P boot line, §4/§9**).

## 3. Generation throughput — per-request vs aggregate

Window for all per-minute stats: `2026-11-23T15:20→18:50Z`, pod ppt7l. Run totals
(`increase(...[3h30m])` at 18:50Z): **697,761 gen tokens, ~524 request
completions** (`increase(vllm:request_generation_tokens_count[3h30m])` = 524;
`vllm:request_success_total` lifetime at 18:44Z: `tool_calls 669 / stop 37 /
length 1 / abort 0 / error 0`).

- **Aggregate gen rate** (`rate(vllm:generation_tokens_total[2m])`, active-only):
  p50 **91**, p95 **266**, **peak 469 tok/s @ 18:34Z**; `[5m]`: p50 86.5, p95 188,
  peak **328**. Duty cycle: `increase(radiance:engine_step_seconds_total[3h30m])`
  = 7,029 s of 12,600 s (56% stepping).
- **Per-request decode speed**
  (`rate(vllm:request_generation_tokens_sum[5m]) / rate(vllm:request_decode_time_seconds_sum[5m])`):
  p50 **99.1**, p95 **143.2**, **peak 159.2 tok/s**. Engine log printouts agree
  (n=284 done-lines 16:00–18:50: printed `… tok/s` p50 94.4, p95 167.3, peak 321.6).
- **Engine gauges** (semantics undocumented — reported with that caveat):
  `radiance:decode_tokens_per_second` p50 41.3 / p95 243 / peak 359.7 (single-stream
  instants ≈ 1/0.0265 s ≈ 37, so the gauge is the per-step aggregate; the low p50
  vs the rate-based p50 99 reflects spec rows).
  `radiance:decode_step_seconds_recent` 26.5–27.8 ms (best 20.19 ms) → step floor
  ~36–38 steps/s.
- **Concurrency:** `vllm:num_requests_running` p50 **1**, p95 6, **peak 7** @18:21
  (configured 8 never reached); `vllm:num_requests_waiting` peak 1;
  `radiance:http_queue_depth` peak 7; admission rejected **0**; client disconnects
  **0** (lifetime).
- Speculation: `radiance:draft_acceptance_ratio` ≈ 0.29; run draft accepted
  482,739 of 1,539,772 proposed = **31.4%**; `decode_rows_unspeculated_total` 454
  (lifetime — nearly all rows run speculated). gen tokens per decode step ≈
  697,761 / (run decode steps ≈ 170,600 of 211,337 lifetime `engine_steps_decode_total`)
  ≈ 4.1.
- **Verdict on "as high as 150 tok/s gen agg":** the number 150 is the
  **per-request** rate's high side (p95 143 / peak 159), not the aggregate's —
  aggregate ran *higher* (p95 188–266, peak 328–469 across windows). The claim is
  not contradicted as an experience (they saw ~150 on their side) but it is
  mislabeled: as an aggregate it is an understatement; as a per-request p95 it is
  exactly right.

## 4. Prefill — slow by which measure; what the link did

**Traffic shape (run window, `increase[3h30m]`):** prompt tokens admitted
**73,340,830**; tokens actually prefilled (`radiance:prefill_tokens_total`)
**5,471,941** = **7.5%**; `radiance:attn_cached_tokens_total` 70,374,428
(96% of admitted served from the attention prefix cache);
`vllm:gpu_prefix_cache_hit_rate` p50 **0.93** / p95 0.94 sustained. This was a
long-context multi-turn tool-calling workload (agent client from a single
cluster IP `::ffff:10.42.0.166`; done-lines show prompt growth 76k→141k across
`msgs=17…37, tools=12` chains; sample p50 prompt **119,865**, peak **247,612**;
p50 cache/prompt ratio **0.96**).

- **TTFT** (n=284 log done-lines + `vllm:time_to_first_token_seconds` rates):
  p50 **2.82 s**, p90 15.5, p95 20.7, **peak 97.55 s** (179,396-token prompt with
  cache=2048, i.e., essentially cold). Histogram-window quantiles: p95 max 412 s,
  p50 max 120 s — those 10-min-window extremes are the giant cold prefills queueing.
- **Prefill duration/rate:** aggregate admitted prompt rate (`rate(vllm:prompt_
  tokens_total[5m])`) p50 6.7k / peak 27.1k tok/s — but that is **inflated by
  cache hits** (they cost ~nothing). The compute truth: engine
  `radiance:prefill_tokens_per_second` gauge p95 **2,308**, peak **6,865** tok/s;
  single-shot cold rates from done-lines: ~**1,839–1,941 tok/s** on solo 180–190K
  prompts (ttft ≈ 97 s), and **413–585 tok/s** when a cold chunk shares steps with
  concurrent decode (23,668 cold-of-244,852 in 57.27 s; 27k cold in ~50 s).
  Cross-check totals: 5.47M computed / 1,687 lifetime prefill steps (+2,639 mixed)
  ≈ 1.4k tok/step; step seconds share consistent.
- **Batch-cap / scheduler signature:** `radiance:engine_prefill_chunks_capped_total`
  = **520 events in the run** (564 lifetime) with `--busy-prefill-chunk auto`
  keeping ≥64 tokens per shared step — prefill ran chunked *behind* decode, by
  design; `engine_steps_held_total` = 0 (nothing held).
- **What the link did:** `radiance:kv_stream_bytes_total{dir="in"}` = **0 for the
  whole pod lifetime** (instant of the counter at 18:44 = 0; `increase` = 0; no
  `dir="out"` series exists at all). `radiance:kv_resident_blocks` 0,
  `radiance:kv_stream_misses_total` 0. **The KV-plane host↔card traffic was
  exactly zero — the discriminator: a silent link during a slow-prefill run.**
- **P2P:** boot line `I device: the 2 cards reach each other's memory directly
  (peer to peer)` + `--p2p … peer to peer [auto]` — card↔card collectives do not
  detour through host mailboxes on this rig.
- **Negotiated PCIe at boot (04:01:47, startup report — the only link telemetry
  that exists):** rank 0 chain `link 00:02.5 **16.0 GT/s x4** (max 16.0 GT/s x4) ->
  c1:00.0 16.0 GT/s x4 -> c2/c3 32.0 GT/s x16` (root-port capped x4, at its max);
  rank 1 chain `link 00:03.2 **8.0 GT/s x4 (max 16.0 GT/s x4)** -> c5…c7 …`
  printed **`WARN startup report: link-below-max: card 0000:c7:00.0 (rank 1): the
  PCIe link … runs 8.0 GT/s x4 of its 16.0 GT/s x4 while the card is 31% busy`** —
  i.e., **card 2 parked at Gen3 x4** (the D39/D43-era class that host-tuning §1
  chased on card 1; it was NOT re-chased here — runtime state uninstrumented).
- **`--tp-wire wht6` boot WARN:** `LOSSY … at 128 KiB a message and above —
  cross-rank all-reduce carries a quantised payload (Walsh-Hadamard-rotated 6-bit
  at two ranks)… this process does not compute the same function the exact wire
  does.` (Accuracy caveat; also means TP collectives were bandwidth-reduced by
  design above 128 KiB.)

**Bottleneck signature verdict:** slow-prefill episodes coincide with (a) huge
cold prompt volume at compute-bound rates ~1.8k tok/s solo / sub-1k under
concurrency, (b) chunk-capped interleaving behind 5–7 concurrent decodes, (c) the
96%-cache regime making the *admitted-token* view misleading, and (d) the 4 GiB host
prefix tier being **smaller than one 262144 conversation** (boot W line: holds
131,072 tokens; "8193 MiB would hold one"), so cold tails beyond 131K must be
re-prefilled (and `W prefix cache: 256 entries erased with no copy off the card`
×47 in the run — tier churn forcing recompute). None of these is PCIe KV-transfer.

## 5. "All on card" — settled

- **KV: TRUE, card-resident, 100%.** Boot budget (04:01:39): `card total 31.86
  GiB / claimable 30.73 GiB / static weights 8.50 GiB (per rank) / elastic 22.24
  GiB → kv cache 22.24 GiB "100% of it"`; `kv_attn … 16 layers, block 16 tok,
  page 256.00 KiB, 85952 blocks = 20.98 GiB (1375232 tokens)`; `1.16 GiB …
  per-sequence state, and nothing is lent: it is all the cache's`; mover
  `0 slab slots`; **no experts** (dense — placement/host-pool absent by law).
  Runtime: `kv_cache_max_tokens 1,375,232`, `kv_cache_max_bytes 22.24 GiB` (per
  card — the boot line prints "a card"), `radiance:kv_stream_bytes_total` 0,
  `kv_resident_blocks` 0, `stream_misses` 0, `engine_steps_held` 0. Pool usage
  `vllm:kv_cache_usage_perc` p50 0.82, mean 0.72, peak 1.00 — no eviction-class
  KV pressure events (`num_requests_preempted` 0, `preempt_forced_total` 0,
  `vllm:num_preemptions_total` 0).
- **Per-card VRAM vs ~31.86 usable:** `I[0] and I[1] card settled at 246.36 MiB
  free, against 232.26 MiB (the 96.00 MiB --gpu-headroom-mib + 136.26 MiB step
  staging)` — both cards fully claimed to the headroom line.
- **Host plane (the part "all on card" glosses):** pinned host memory exists and
  is sized at boot — **checkpoint slots 80 × 153.38 MiB = 11.98 GiB pinned host,
  "none of it on the card"** + **token embedding 1.18 GiB per rank pinned host,
  read over the link in place** (`host_pool 1.18 GiB budget` per rank) + prefix
  host tier **4.00 GiB (131,072 tokens)** ⇒ ~18.3 GiB host budget against the
  24 Gi cgroup; measured `container_memory_working_set_bytes{container="radiance"}`
  peak **19.73 GiB** (p50 not computed; limit `24Gi` = 25,769,803,776 B verified
  via `kube_pod_container_resource_limits`), **0 restarts, 0 OOM kills** (no
  `last_terminated_reason` series nonzero). The pinned leg test
  `24 − (11.98 + 2×1.18) = 9.66 ≥ 4` passes on the printed budget lines.
- **Host pool vs configured `--host-pool-mib`:** not configured on this lane
  (dense bar) and the engine's `host_pool` region auto-sized to 1.18 GiB/rank
  (embeddings only). Nothing occupies more. The 12288-per-rank host-pool figure
  belongs to fn (MoE), not here.
- **Residency verdict:** for the *decision-relevant plane* (KV) the owner's
  "all on card" is measured TRUE — which is exactly why the PCIe-KV theory cannot
  hold (§8/§9).

## 6. Log findings (real lines quoted; Loki `{cluster="gpu-ai", container="radiance"}`)

- **Context-length class:** at the raised 262144 ceiling, `--max-model-len == the
  trained rotary bound`, so the expected "past what the rotary covers" warning has
  nothing to warn about and **none printed** — the ceiling evidence instead is
  the single refusal line (ppt7l, 05:28:50): `I req refused from
  ::ffff:10.42.0.166:58116 -> 400 invalid_request_error: This model's maximum
  context length is 262144 tokens: the request (755328 tokens) exceeds the
  available context size (262144 tokens) and leaves nothing to generate into` —
  it also proves the **served** ceiling was 262144, independent of the argv echo.
  In the *previous* (200000) pod d8sj7 the same class fired repeatedly
  (23:02:42 `request (283516 tokens)…`, 23:02:42 `238139…`, 23:14:03 `200047…`,
  23:21:06 `204684…`) — real clients were over the old bound; zero such refusals
  after the raise except the 755K outlier.
- **Tier-smaller-than-conversation (boot, ppt7l 04:01:47):** `W kv tiers:
  --prefix-cache-mib 4096 holds 131072 tokens of context (512.00 KiB per 16-token
  block), less than one --max-model-len 262144 conversation: a longer one keeps
  its first 131072 tokens in host memory and is prefilled again past them once
  VRAM gives it up. 8193 MiB would hold one.`
- **Run-window churn (15:20→18:50): 27 × `W kv tiers: … entries got no host copy:
  the host tier … is full`** and **47 × `W prefix cache: 256 entries erased with
  no copy off the card -- the host tier had no room for them in time`** (16:10→
  16:16 cluster, tail at 18:46:08, 18:47:57). These are recompute-forcing events,
  correlated with the cold-prefill TTFT spikes (prefix re-prefill, not transfers).
- **OOM/refusal/restart classes:** **none.** `E`-level engine lines: 0 in pod
  lifetime; `vllm:request_success_total` abort=0 error=0 (length=1);
  `http_admission_rejected_total` +0 (429 class — note the 400 refusals above do
  NOT count here; different class); `stream_overflow_total` 0,
  `client_disconnect_total` 0; kube restarts 0, terminated_reason none;
  `num_requests_preempted`/`preempt_forced_total`/`vllm:num_preemptions_total` 0.
  (The task-listed `context_length_exceeded` string is not this engine's wording —
  it prints `invalid_request_error: … maximum context length is …` — searched both.)
- **Lossy-wire and kernel-plugin boot W lines** quoted in §4 (wht6; the libhalo/
  libr3d fat-binary declines belong to the fn boot captured in the same tail).
- **End of run:** `18:49:52 I stopping: draining in-flight requests` (SIGTERM;
  180 s grace; last done-line 18:49:01 `finish=stop prompt=141707 (cache 139264)
  gen=2215 ttft=1.39s`). fn's boot echo lands 7 s later.
- Throughput-dip correlation: the run's two quiet stretches (15:07-15:40 ramp,
  ~17:10-17:45) show frozen token counters — gaps were client-side (owner
  stepping away / sessions idle), not engine stalls.

## 7. The 262144 funding evidence (partial C04 receipt capture)

This is precisely what the data shows — items are the D8/RESEARCH-(e) receipt set
where today's instrumentation reaches:

1. **Config echo (item 1):** composed argv, ppt7l boot 04:01:38:
   `--model /models/radiance/qwen3.8-27b-mxfp4.rad --served-model-name
   qwen3.8-27b-radiance-tp2 --port 8000 --host :: --max-num-seqs 8 --kv-cache-dtype
   fp8 --tp 2 --max-model-len 262144 --tp-wire wht6 --prefix-cache-mib 4096` —
   exact profile; no rope-scaling flag (unscaled, correct at the trained ceiling).
2. **VRAM split (item 2):** static 8.50 + kv 22.24 + headroom 96 MiB + 136 MiB
   staging per card; `1.16 GiB per-sequence state; nothing is lent`. **Arithmetic
   finding:** pool tokens 1,375,232 ↔ 22.24 GiB/card ⇒ **16 KiB/token/card = 32
   KiB/token lane — trunk-only; RESEARCH V3 open-q1's "~64 KiB effective (drafter
   2×)" is NOT what the pool funds** (the drafter's paged groups are separate
   small planes: `draft floor: 2 paged group(s), 1 prefix-cached`). One 262144
   session = 4.0 GiB attention/card.
3. **Pool-backs line (item 3):** `I kv: the pool backs 66% of the worst case (8
   sequences all at 262144 tokens), 5.3 full-length sessions` (+ budget-table line
   `66% backing of the 8 x 262144 worst case: 5.3 full-length` and cache line
   `5.2 sessions at 262144`). **66% < 100%: the 8×262144 worst case is NOT
   fully funded** on this node even with 100% of elastic claimed — at trunk-only
   cost, 8×262,144 needs 33.6 GiB/card vs claimable 30.73. D15-F2's `M`-vs-seqs
   bar would read **5.3 < 8** here.
4. **Pinned line vs 24Gi (item 4):** printed pinned-class host legs = 11.98
   (checkpoints) + 2.36 (embeddings) ⇒ `24 − 14.3 = 9.66 ≥ 4` ✓; working-set peak
   19.73/24 ✓ (band leg 7).
5. **Checkpoint slots (item 5):** `80 linear-state snapshot(s) of 153.38 MiB in
   pinned host memory (11.98 GiB), none of it on the card; 10 a sequence for
   --max-num-seqs 8: geometric-backoff keeps 9 for a 262144-token session at a
   2048-token interval` (V3's "144 MiB / 11.25 GiB store" class, repriced here at
   153.38 MiB — same 11.98 GiB).
6. **Tier warning (item 6):** fired, exactly the predicted
   tier-smaller-than-conversation shape, restated for 262144 (§6).
7. **cgroup leg (item 7):** working-set peak 19.73 GiB inside V3's 16–20 band;
   **no `memory.peak`/`oom_kill` series exists** — honest partial (gap §10).
8. **Peer-hop smoke (item 8):** effectively witnessed continuously — all 706
   completions ran through the cluster-internal peer path (single client IP
   10.42.0.166; `finish=tool_calls` 669) through the llama-swap peer hop, no 502s
   (no error/abort class at all).
9. **Near-ceiling acceptance (item 9):** prompt **247,612 tokens (94.5% of
   262144) accepted and completed** (18:04:52→18:07:10, `finish=stop cache 243712
   ttft=2.97s`); **~105 requests > 200,000 admitted during the run**
   (hourly `increase(request_prompt_tokens_bucket[1h])`: (+Inf − le=200000) =
   24+52+29), zero over-ceiling refusals. The D47 recorded dissent (loud-400 risk)
   is empirically retired for TP2 at this ceiling.
- **Concurrency behavior:** worst case never stressed — `num_requests_running`
  peaked 7 (of 8) and p95 6; the 66% funding would only bite at sustained ≥5.3
  near-full-context sessions simultaneously. Truncation/eviction during the run:
  96,434 prefix-cache entry evictions + `length`-finish 1 (lifetime) — recompute
  churn, not context truncation.

**Summary of what closes and what stays owed:** the formal `receipt_gate.py
--commands` artifact (D8) still has not been run by the owner (STATE says C04
NOT RUN) — but the *content* of items 1-6, 8, 9 is now captured from Prometheus +
Loki without pod exec, and item 3's answer is **"66% / 5.3 sessions — under-funded
for the 8-worst-case, funded for ≤5 simultaneous full-length"**, which is a
*confirmation-shape* for D1 (fit per-session at TP2) and a refutation of the
V3-64-KiB sizing arithmetic (it was ~2× pessimistic on pool backing yet arrived at
the same "fits" verdict only per-session).

## 8. PCIe arithmetic, computed

Ceilings (this rig's negotiated boot widths — host-tuning §1 measured rates):
- rank 0: **Gen4 x4** ≈ raw 7.88 GB/s (D44: "the 3.94→7.88 GB/s uplift DID land").
- rank 1: **Gen3 x4** ≈ raw 3.94 GB/s (boot WARN; half of its own port's max).
- P2P available card↔card (boot line) — TP collectives do not traverse host RAM
  here (contra V5's Wilde-rig clause).

Observed link demand during the run (instruments in the TSDB):
- KV stream bytes: `increase(radiance:kv_stream_bytes_total{dir="in"}[3h30m])`
  = **0 B** ⇒ 0 B/s vs a 3.94 GB/s worst ceiling — **0% of even the narrow link.**
- Embedding gather over the link: 1 row/token ≈ 256 B/token bf16 (qwen35-class
  hidden ≈ 256 B rows; per V1 geometry `head_dim 256`) — at the peak *generated*
  469 tok/s that is ~0.1–0.2 MB/s even if counted per-row across 8 rows/step —
  ≪ 1% of the narrowest link. (Engine: "read over the link in place" — the only
  designed per-token link traffic this dense lane has.)
- Tier demote/promote bytes: **no byte counter exists**; bounding worst case —
  every completed session (≤ ~706) moving its full 4 GiB host tier copy once ⇒
  ≤ ~2,800 GiB/day at the ceiling; over the run (~650 sessions incl. tool-chain
  segments) even 10% of that (280 GiB) at ~3.5 GB/s combined would be only ~80 s
  of pure-link time spread over 3 h — and the observed cost events were
  *re-prefills* (counted in prefill_tokens_total), not transfers.
- Cold prefill demand: 5.47M computed tokens; the *only* link-adjacent input is
  the pack/prefix-tier, boot-time `one pass over the container, 18.04 GiB read in
  4.7 s (4.1 GB/s)… 3.8 s of that was the disk (5.1 GB/s)` — boot load was
  **disk-bound**, not wire-bound (and completed in seconds).
- Consistency check: observed cold prefill ≈ 1.9k tok/s solo. At Gen3-x4
  (3.94 GB/s = ~3.5 GiB/s effective payload class), matching 1.9k tok/s with
  *link* would require ~1.8 MB of wire per token (3.5 GiB/s ÷ 1.9k tok/s) —
  **56× the entire 32 KiB/token KV footprint.** The prefill slowness is ~56× too
  large to be link-borne; it is dequant/compute + chunk-capped sharing.
- Candidates that ARE consistent with the observed rates: dense fp8/mxfp4 prefill
  compute (16 full-attn + 48 linear layers, 64 layers, TP2 sharding overhead
  ~16% per V5's 1.67× ladder class), `--busy-prefill-chunk` interleaving (520
  capped events, steps sharing decode at 27 ms/step), the 96%→0% cache-hit cliff
  on fresh giant prompts (cold 180K = ~97 s by construction), and placement/resume
  shape (`draft refill: a prefix hit ends 2048 tokens before the prompt's end, so
  the drafter's window is recomputed` — designed 2048-token tail recompute per
  resumed turn). `--gpu-headroom-mib 96` (default) costs the pool ~0.19 GiB/card
  — ~0.5 session's worth; it shaved funding, did not slow serving. mmap-vs-resident
  and cold page-cache: the boot load line above prices the cold path (4.7 s);
  tier churn (§6) is the recompute analogue, page-cache misses have **no
  instrument** (§10).

**Arithmetic verdict:** every PCIe candidate is 1–2 orders of magnitude too small
to produce the observed prefill cost; the one real PCIe defect (rank 1 Gen3 x4,
boot WARN) touched only the embedding gather and whatever the uninstrumented
P2P/tier paths actually put on the wire at *reduced* (6-bit wht6) message sizes.

## 9. Contradictions with the owner's account — stated bluntly

Owner: *"27b pretty much matched my expectations — all on card, slow prefill. Got
as high as 150 tok/s gen agg… but again I think the prefill pci-e limitation slowed
it down."*

1. **"All on card" is TRUE for KV — and that is exactly what kills "the prefill
   PCIe limitation slowed it down."** The premise pair the owner asserted both
   ways is internally contradictory, and the measurement lands on the contradiction:
   `kv_stream_bytes_total` = **0 bytes for the entire life of the pod**. There was
   no host-resident KV pathology to have a PCIe cost from — none, not one byte.
   The slow prefill is compute/scheduler/cache-shape, with the cold-prefill rate
   (~1.9k tok/s solo on 180K prompts) being ~56× too slow to be wire-borne at any
   PCIe width. A genuine but *different* PCIe defect exists — **rank 1 card
   parked at Gen3 x4, WARN printed** — but it carries only ~0.1 MB/s of embedding
   gather, not the prefill. If the owner's "PCIe" intuition was really about the
   x4 width + lossy `wht6` wire capping TP2 headroom (the creator rig's 3,212
   tok/s prefill vs our ~1.9k, and V5's 1.67×-not-2× class), that is defensible;
   the "PCIe slows prefill via resident-plane transfers" version is refuted.
2. **"150 tok/s gen agg" is mislabeled.** Measured per-request p95 = 143, peak =
   159 (the number the owner saw is a *per-request* high side); measured
   *aggregate* was higher — p95 188–266, 2-min peak 469, 5-min peak 328. As an
   aggregate claim 150 is an **understatement**; as an experience it is the
   per-request rate. (Concurrency never exceeded 7/8, median 1 — the lane was
   mostly single-stream, where "agg" and "per-request" collapse except in bursts.)
3. **"Slow prefill" needs a qualifier:** the *median* prefill experience was fast
   (TTFT p50 2.8 s) because 96% of admitted prompt tokens were prefix-cache hits
   in a long multi-turn tool-calling workload. What was slow: cold giant prompts
   (TTFT to 97.4 s) and cold rates under concurrency (413–585 tok/s). "Slow
   prefill" is a true description of the tail, false as a description of the run.
4. **"Matched my expectations" is only half-true against this repo's own
   expectations:** decode per-request (99–159 tok/s) meets or beats the Wilde
   Gen4-class receipt band (142–146; V5's E-27b-t2 220 single-stream is creator-
   rig class); prefill ~1.9k tok/s solo-cold is **60% of** the ladder's
   3,212 t/s row; and the 8×262144 worst case is funded **66% / 5.3 sessions**,
   which D1's "TP2 fit (measured)" claim from V3/S10 never actually priced at
   full concurrency — V3's "~64 KiB/token effective" was ~2× pessimistic on the
   pool's per-token cost (measured 32 KiB/token lane, trunk-only) yet the
   "worst-case-8" shape still doesn't fit even with corrected arithmetic (33.6
   GiB/card needed vs 30.73 claimable).
5. **The clock:** owner times were UTC−7; the raw-as-UTC reading is wrong by ~7 h
   on both lane switches (§1). The "3.5 h run" is real (15:40→18:49:52Z = 3 h 10 m
   measured); "flash 12:00→now" matches fn boot 18:49:59–18:52Z (+6 h 52).
6. (Context, not a contradiction: the lane ALSO carried a prior heavy 200000-era
   run on `d8sj7` (11-22 22:30→11-23 03:40) with real 400-refusals at
   200,001–283,516-token requests, and ppt7l had a 1.5 h verification burst
   (04:05→05:40) before the owner's run window.)

## 10. What today's instrumentation cannot answer (missing-metric list)

- **Any runtime PCIe telemetry**: no link-width/speed gauge exists as a series;
  the only link state is the boot-time startup-report snapshot (Loki). Gen3
  parking of rank 1 can neither be confirmed persisting nor cleared from here —
  and the host-tuning note's own law says retrain/link reads are OWNER-lane
  (lspci/`/diagnostics` under load).
- **Per-card VRAM over time**: no `amdgpu`/`vram`/`rocm` families anywhere in the
  TSDB — the 31.86-GiB budget is boot-print only; no VRAM-usage series to detect
  creep, fragmentation or the `+1 GiB`-class staging growth the 136 MiB line
  warns about.
- **P2P bandwidth / collective bytes**: no counter; `--tp-wire wht6` traffic
  volume and the P2P path's realized rate under load are invisible (engine log
  probe line exists; nothing periodic).
- **Prefix host-tier byte flow**: tier events are entry/token counters
  (`prefix_cache_evictions_total`, `_ckpt_*`, `_expired`, `_released`, hit/miss
  cuts) — there is **no bytes_total for tier copies/restores**, so "did the host
  tier actually transfer bytes over PCIe and how many" is unanswerable (only the
  KV-stream counter has bytes, and it's for streaming, which dense never does).
- **Pinned-bytes time series** (the `pinned by this process` budget line is boot
  print only; `memory.peak`/`oom_kill` cgroup files are not scraped as series —
  working-set is the only proxy; host-tuning §6 "three pin numbers, three scopes"
  remains unsettled by design).
- **Prompt-size granularity above 200,000**: `vllm:request_prompt_tokens_bucket`
  tops out at `le=200000` — the 105 over-200K requests are a +Inf lump (only the
  log done-lines price individual sizes).
- **Post-boot config drift**: the argv echo is the only config witness; no
  config-hash gauge.
- **KV per-sequence window occupancy vs pool**: `kv_cache_usage_perc` is the pool;
  nothing separates "8 sessions × near-262144" from "1 × 2M" pre-empt risk — the
  funding stress never happened (running max 7, p50 1) so the 66% number was
  never exercised.
- **`/diagnostics` live block** (link-under-load, expert/KV-tier live counts):
  owner-exec route only (no agent exec; AGENTS MCP law).
- Also: `vllm:gpu_cache_usage_perc` and `vllm:kv_cache_usage_perc` are duplicate
  series (identical values); `radiance:decode_tokens_per_second` /
  `prefill_tokens_per_second` gauge semantics (instant-step vs windowed) are
  undocumented anywhere in the repo — treat their p50s with care, the rate-based
  figures in §3-4 are the primary record.

## Appendix A — exact queries (all datasourceUid `prometheus` / Loki `P8E80F9AEF21F6940`)

Window key: `P = pod="gpu-ai-radiance-q27-tp2-648f6dd5c7-ppt7l"`,
run `2026-11-23T15:20→18:50Z` (boundaries from the discovery rows below).

1. Window/chronology: `up{job="radiance"}` range now−30 h step 300 (per-pod
   first/last); `kube_pod_info{pod=~"gpu-ai-radiance.*", cluster="gpu-ai"}` same;
   `rate(vllm:generation_tokens_total{pod=~"...ppt7l|...d8sj7"}[5m]) > 0` range
   at 300 s; `increase(vllm:{prompt,generation}_tokens_total[1h])` hourly steps.
2. Throughput: `rate(vllm:generation_tokens_total{P}[2m|5m])` 60 s;
   `rate(vllm:request_generation_tokens_sum{P}[5m]) /
   rate(vllm:request_decode_time_seconds_sum{P}[5m])`;
   `radiance:decode_tokens_per_second{P}`;
   `vllm:num_requests_running/waiting{P}`; `radiance:decode_step_seconds_{best,recent}{P}`;
   lifetime `vllm:request_success_total{P}` (labels `finished_reason=...`).
3. Prefill: `rate(vllm:time_to_first_token_seconds_{sum,count}[5m])` +
   `histogram_quantile(... rate(bucket[10m]))`; `rate(vllm:prompt_tokens_total[5m])`;
   `radiance:prefill_tokens_per_second{P}`; `increase(radiance:prefill_tokens_total{P}[3h30m])`;
   `increase(radiance:attn_cached_tokens_total{P}[3h30m])`;
   `vllm:gpu_prefix_cache_hit_rate{P}`; `rate(radiance:engine_prefill_chunks_capped_total[5m])`;
   `increase(radiance:engine_steps_{prefill,decode,mixed,held}_total[3h30m])`;
   `increase(vllm:request_prompt_tokens_bucket[1h])` by `le`.
4. Link/residency: `increase(radiance:kv_stream_bytes_total{P,dir="in"}[3h30m])`;
   `radiance:kv_resident_blocks{P}`; `radiance:kv_stream_misses_total`;
   `radiance:kv_cache_max_{tokens,bytes}{P}`; `vllm:kv_cache_usage_perc{P}`;
   `container_memory_working_set_bytes{pod=...}`;
   `kube_pod_container_resource_limits{pod=...}`;
   `kube_pod_container_status_restarts_total{pod=...}`.
5. Logs (LogQL, pod filter client-side): selector
   `{cluster="gpu-ai", container="radiance"}` with `|= "composed engine argv"`,
   `|= "pool backs"`, `|= "cache can grow"`, `|= "free, against"`, `|~ "(?i)(GT/s|Gen[345])"`,
   `|~ "(?i)(p2p|wire|link|mailbox|collective)"`, `|~ "(?i)(context|exceed|truncat)"`,
   `|~ "(?i)(oom|refus|denied|insufficient)"`, `|= "W "`, `|= "E "`, `|= " done from "`,
   `|= "draining"` over the pod windows above.
6. Repo: `git show 0eeee59c3:services/gpu-ai/prod/values.yaml` (render check),
   `git merge-base --is-ancestor` probes (documented dead-ends), content greps
   for all §2 cites.

RESULT
status: DONE
chunk: explore (27b-TP2 perf scout)
files_changed: [.agents/plans/2026/2026-11-bug-radiance-27b-tp2-perf/EXPLORE.md]
commands_run: [repo reads/greps (values.yaml lane blocks, charts/radiance serve.sh FORM + cf-145 annotations, cf-145 EXPLORE/DECISIONS, notes q27-boot/second-gpu-tp2/host-tuning, ticket STATE/DECISIONS/RESEARCH/FRICTION) => pass; git (log/show/merge-base --is-ancestor, read-only; incl. 0eeee59c3 render check) => pass; readonly-global-grafana via execute: query_prometheus ×~30 (up chronology, kube_pod_info, token-counter rates/increases, TTFT quantiles, per-request ratios, kv_cache_max_*, kv_stream_bytes_total, usage, working-set, limits, restarts, finished_reason census, metric-family censuses incl. the negative one for vram/amdgpu) => pass; query_loki_logs/label_names/label_values/stats ~15 (argv echoes, pool-backs, VRAM splits, link/PCIe startup chains, P2P, tier warnings, refusal/W/E classes, drain tail, done-line samples n=284) => pass; grafana_api_request /api/datasources + list_prometheus_label_values(job) => pass; date -u => pass]
deviations: path corrected mid-run per coordinator instruction — wrote to the new ticket folder `2026-11-bug-radiance-27b-tp2-perf/EXPLORE.md` instead of the originally named `EXPLORE-27B-TP2-PERF.md` in the context-window folder; the original target never existed (nothing to append); no heredoc; write succeeded first-attempt; context-window folder untouched.
friction: Loki engine logs index pod in structuredMetadata, not as a stream label (label selector by pod returns 0 — client-side filter required); query_loki_stats rejects LogQL pipelines; query_prometheus arg-name trap (expr/endTime, not query/end) — all three recorded in §0 for the next agent; git forensics could not pin which ref-state the 03:59Z ArgoCD sync rendered (empty Revision field) — flagged §1.
open_questions: [deploy-provenance: which ref carried the 262144 render into the 04:01:38 boot when the 03:50 cached revision 0eeee59c3 verifiably still holds 200000 and bc4b2a3fa author-dates 04:41:49 (owner-side ArgoCD operation history would settle it); needs research: no for the perf question itself (all perf answers are measured here) — but the follow-up research round should price (a) why solo cold prefill is ~1.9k tok/s on TP2 when the ladder row says 3,212, (b) what the uninstrumented P2P collective traffic + wht6 actually cost, (c) whether the boot-printed rank-1 Gen3-x4 parking persists under load (owner /diagnostics/lspci leg).]
next_suggested: hand this file to agent-research for the optimization round; recommend the owner run the D8 receipt block at the next scale act (this file captures items 1-6/8/9 passively; item 7's memory.peak/oom_kill and the live /diagnostics under-load leg remain owner-only).
