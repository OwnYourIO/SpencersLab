# EXPLORE.md — flash-TP2 (fn) lane performance ground truth (2026-11-23)

*Scout round, 2026-11-23 ~20:32–20:47Z. Sources: repo reads (worktree
`feat-radiance-multi-instance` @ 3400ed49d), `readonly-ai-gpu-kubernetes`
(pods/pods_get), `readonly-global-grafana` PromQL (datasourceUid `prometheus`) +
Loki (`P8E80F9AEF21F6940`), read-only git, one webfetch (upstream vLLM MTP docs).
Deliverable: this file only; no other writes, no admin tiers, no pod exec.
Every figure carries its query + window. No metric invented — the live
radiance/vllm census (§0) is the only family source used.*

## 0. Provenance, access, observer effect

- **I run on `gpu-ai/qwen3.8-flash-next-radiance` — the lane under investigation.**
  This scout session (and very likely the launching coordinator and other live
  pipeline agents) generated engine traffic inside the measured window
  (session start ≈ 20:32Z; the window runs 18:52→20:47Z). All engine-side
  clients appear as ONE ip — `::ffff:10.42.0.166`, the `gpu-ai-llama-swap` pod —
  so **agent-driven load cannot be separated from the owner's load by any
  instrument we have** (`vllm:num_requests_running` and the done-lines count
  ports, not owners). Where separable by TIME (the pre-scout hour
  19:00→19:59Z predates this session) it is noted. No throughput figure below
  is attributed to "the lane's own behavior" free of this mix.
- **Grafana access verified working.** Call shapes (recording the sibling's
  quirks + two new ones):
  - `query_prometheus`: `expr`/`startTime`/`endTime`/`stepSeconds`/`queryType`.
  - `query_loki_logs`: params are **`startRfc3339`/`endRfc3339`** — `startTime`/
    `endTime` are silently IGNORED (defaults to last hour; my first probe scanned
    216 lines and returned 0 until the names were fixed).
  - **Loki pod identity is in `structuredMetadata.pod`, not a stream label** —
    label selectors by pod return 0; filter client-side. `query_loki_stats`
    rejects pipelines (label selectors only).
- **Metric census** (instant `group by (__name__) ({__name__=~"radiance:.+|vllm:.+"})`
  at 20:46Z): 90 families, identical in name to the sibling's q27 list
  (their §2) plus this lane's activity on `radiance:linear_*`,
  `radiance:lookup_*`, `radiance:draft_position_*`. Label census: the only live
  `model_name` is `qwen3.8-flash-next-radiance`; job `radiance`; pod per §1.
- **Repo facts confirmed before probing** (all at this worktree's HEAD):
  `services/gpu-ai/prod/values.yaml:1157-1158` fn `RADIANCE_MAX_MODEL_LEN
  "262144"`; `:1593-1594` flash-TP1 same; `:1169-1170` and `:1603-1604` the two
  flash lanes' `RADIANCE_NUM_SPECULATIVE_TOKENS "3"`; parent ticket DECISIONS D47
  (`.agents/plans/2026/2026-11-feat-radiance-multi-instance/DECISIONS.md:517`)
  unifying catalog `limit.context: 262144` (`.opencode/opencode.jsonc:731` fn trio
  verified at 262144); merge commit `bc4b2a3fa` author-dated **2026-11-23
  04:41:49 +0000** (`git show bc4b2a3fa --stat`).
- **Cluster/server mapping:** the radiance fleet lives on the **ai-gpu**
  cluster (`readonly-ai-gpu-kubernetes`), namespace `default`; metrics carry
  `cluster="gpu-ai"`. Current fleet: exactly ONE radiance pod —
  `gpu-ai-radiance-544c9bbdf5-rs6cp` (10.42.0.178); no flash-TP1 or q27 pod is
  up (switch discipline: fn UP claims both cards c7:00.0 + c3:00.0, both
  Healthy).

## 1. Verified window + inferred offset

fn-lane (release `gpu-ai-radiance`, served id `qwen3.8-flash-next-radiance`)
pod chronology, from `up{job="radiance"}` range 11-22T14:00→11-23T20:46Z @60s
plus Loki boot echoes:

| pod (RS) | argv `--max-model-len` | scrape up | served traffic |
|---|---|---|---|
| `64bb5cf587-lcjv8` | (no composed-argv echo in window) | 11-22 22:20–22:21 (2 samples) | none found |
| `5b69c57dc8-rcs7v` | **200000** (echo 22:21:01.995Z) | 22:22–22:25 | **0 completions** (done-lines query 22:00→04:10Z returns only q27 lines; counters absent at 23:59) |
| `5b69c57dc8-5qvzf` | **200000** (echo 03:59:30.298Z) | (none) | 0 |
| `544c9bbdf5-rnrgh` | **262144** (echo 04:00:07.421Z) | 04:02 (1 sample) | 0 |
| `544c9bbdf5-rs6cp` (current) | **262144** (echo 18:49:59.556Z) | 18:52 → 20:46 (present) | **all of it: first nonzero `rate(generation_tokens[5m])` sample 18:55Z** |

- **The flash lane's real measured window = 18:52→~20:47Z (~1 h 55 m, and still
  running at scout end).** Everything the owner called "flash 12:00→now" is this
  single pod's life; the pod has NO longer life, and no other pod ever served
  flash traffic (the 200000-era boots died in the load/scale window).
- **Inferred offset ≈ UTC−7 again**: owner "12:00" ↔ rs6cp boot 18:49:59Z /
  first traffic 18:55Z (+6 h 50 / +6 h 55); owner "now" ≈ 13:4x ↔ scout-end
  20:47Z. Matches the sibling scout's estimate.
- **No restarts**: `pods_get` rs6cp containerStatuses `restartCount: 0`,
  `lastState: {}`, startedAt 18:49:59Z, startTime 18:49:58Z.
- Deploy-provenance (same ambiguity as the sibling's lane, and it resolves the
  same way for TODAY): RS `544c9bbdf5` was created in the 03:59–04:01Z sync wave
  — before `bc4b2a3fa` (04:41:49) — so the stale-sync reading applies to the RS
  template's BIRTH; the pod itself booted 14 h after the merge, and its live env
  (read via `pods_get`) matches current main's rendered profile entry-for-entry
  (§2). No deploy defect visible in the RUNNING object.

## 2. Q1 — what ceiling the lane actually serves: 262144, triple-receipted

**Headline: the current pod serves 262144. The argv is NOT 200000.** Receipts,
each from a different witness class:

1. **Composed-argv echo** (rs6cp, 18:49:59.556Z, verbatim):
   `radiance serve: composed engine argv: --model
   /models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad --served-model-name
   qwen3.8-flash-next-radiance --port 8000 --host :: --max-num-seqs 8
   --kv-cache-dtype fp8 --tp 2 --max-model-len 262144 --tp-wire wht6
   --host-pool-mib 12288 --gpu-headroom-mib 96 --prefix-cache-mib 4096
   --placement expert_tiered --ngram-placement disk --num-speculative-tokens 3
   --max-num-batched-tokens 2048 --checkpoint-interval 4096`
2. **Engine CONFIGURATION startup report** (18:50:19Z):
   `I   --max-model-len                    262144   [command line]` and
   `I model: qwen4exp  arch=qwen4exp  quant=bf16  48 layers  262144 ctx`.
3. **Behavior**: `increase(count{le="+Inf"}) − increase(bucket{le="200000"})`
   over the window = **~20 requests > 200,000 tokens admitted** (buckets: 17 ≤50K,
   74 ≤100K, 270 ≤200K, 290 total), and `http_responses_total` shows
   **4xx = 0, 5xx = 0** (instant at 20:47Z) — a 200000-clamped engine could not
   accept those. No `refused … maximum context length` line exists anywhere in
   the window's logs.
4. Live pod object: `RADIANCE_MAX_MODEL_LEN "262144"` among 13 env entries
   (matches values.yaml:1125-1174 exactly).

Every `--max-model-len` seen across the lane's boot life with timestamp + pod:
**200000** (`rcs7v` 2026-11-22T22:21:01Z), **200000** (`5qvzf`
11-23T03:59:30Z), **262144** (`rnrgh` 11-23T04:00:07Z), **262144** (`rs6cp`
11-23T18:49:59Z — current). The 200000 era served zero traffic, so **no flash
user ever saw the old ceiling on this rig** — the owner's suspicion is not a
deploy-provenance defect for this lane, and no tuning question follows from Q1.
The lane's funding print does follow (it is the first TP2 print cf-144 P11 owed):

- rs6cp @262144 (echoed verbatim 18:50:02Z): `I kv: the pool backs 52% of the
  worst case (8 sequences all at 262144 tokens), 4.1 full-length sessions; a
  larger --host-pool-mib gives the cache more`
- rnrgh @262144: identical 52%/4.1 (04:00:09Z).
- 200000-era fn boots (rcs7v, 5qvzf): `69% of the worst case (8 sequences all at
  200000 tokens), 5.5 full-length sessions` — cache `8.53 GiB a card, 1100092
  tokens`.
- By D9(a)'s bar (`values.yaml:1148-1149`: "M ≥ 8 is the pass bar … M < 8 is the
  refutation"): **fn refutes at BOTH ceilings** — 4.1 < 8 now; 5.5 < 8 before.
  The raise cost −1.4 sessions of funding; the underfunding is structural
  (experts eat 67% of elastic), not caused by the raise.

## 3. Q2 — MTP: measured acceptance, docs-priced benefit, pack-native ownership

**Is MTP hurting? The data says no sign of harm; the docs price MTP as a large
net WIN for this pack. But this rig has never run an A/B, and neither has
anyone measured it disabled here — the honest state is "helps, per docs;
unmeasured-on-this-rig."**

Measured on rs6cp (18:52→20:47Z):
- `increase(radiance:draft_accepted_total[117m])` = 167,636 of
  `increase(radiance:draft_tokens_total[117m])` = 295,169 → **acceptance 56.8%**
  (gauge `draft_acceptance_ratio` p50 0.563, p95 0.605).
- Position ladder (`draft_position_{reached,accepted}_total` increases):
  pos0 98,398→72,750 (73.9%), pos1 72,750→54,160 (74.4%), pos2 54,160→40,740
  (75.2%) — **per-position acceptance ~74%, flat across depth** (a dying drafter
  shows steep per-position decay; this one does not).
- `increase(radiance:decode_rows_unspeculated_total[117m])` = **3** — essentially
  every row-step ran speculated. Accepted per drafted row-step = 1.70 → ≈2.7
  tokens per row-step vs 1.0 unserialized.
- Boot ownership line (18:50:01Z): `I speculation: 'mtp' drafts 3 token(s) a
  step in 3 serial pass(es); prompt lookup fills in for any sequence it
  declines` — the cost side is 3 serial draft passes per step; no per-pass
  timing counter exists (§8), so cost-vs-benefit ON THIS RIG is not directly
  measurable from /metrics.
- `radiance:draft_refills_total` / `draft_refill_tokens_total` /
  `lookup_proposals_total` / `lookup_held_*` = **all 0 in the window** — the
  prompt-lookup n-gram fallback never ran (see §4 ngram row).

**Memory tax question (the ~1–2 KiB/token worry):** the boot prints settle it
structurally — `I draft floor: 2 paged group(s), 2 prefix-cached, 0 in the
window snapshot -> a hit leaves no hole` — the MTP drafter rides the lane's SAME
two paged KV groups (kv_attn 13 layers page 26.00 KiB/4 tok + kv_qsa_bkey page
3.25 KiB/4 tok = 7.31 KiB/token/card, §7); an extra MTP layer with 2 of 4 KV
heads is bounded by **~0.5–1 KiB/token lane (DERIVED)** — ≤7% of the trunk — and
it is ALREADY inside the pool that funds 4.1 sessions (the 52% print prices all 8
KV groups inside the 8.40 GiB). "MTP pages a separate cache that taxes
concurrency" is not what the prints show; the concurrency tax here is the
EXPERT slab, not the drafter.

**Pack-native / can it be disabled:**
- Engine docs v1.17.0 §4.6, quoted into the parent RESEARCH and verified again
  here via the boot prints: *"If the container carries a draft head, it is used
  by default at the depth the plugin states … `radiance --draft-model` is an
  error that says so"* (`.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/RESEARCH.md:4785-4788`, [R19-S2 §4.6]).
  cf-144 fact 7: *"nothing to change for fn (3 is the pack's depth) … do not
  copy q27's 7 onto fn (depth exists in the pack, not the flag)"* (RESEARCH:3584).
  **So "turn it off" is NOT removing an add-on: the drafter is merged into the
  .rad checkpoint; only the per-step USE is flag-governed.** The sibling lane
  proves the default: q27 boots with NO `--num-speculative-tokens` env and
  resolves depth 7 from the pack ("this drafter's own operating point").
- **Does an off state exist? Yes, and the docs measured it**: v1.17.0 docs' own
  fn TP2 rows: **62.3 (56.8–67.7) / 64.8 (53.2–76.5) t/s WITH MTP vs 39.89 /
  39.78 t/s without** (2,048 tokens, 1 request, 2×16 GB gfx1201 creator-class
  rig) — RESEARCH R14-D/R14-Q4 item 3. The exact flag syntax for "off"
  (`--num-speculative-tokens 0` vs another switch) is **NOT in any window we
  fetched** — do not assume 0 means off; the research round must price it from
  GUIDE §4.6/§4.11 verbatim. Zeroing is possible in principle (the docs'
  off-MTP rows ran on a real engine) but "may silently change which weights
  load" is the right caution: the head loads regardless (it lives in the pack).
- **The turn-off direction looks economically WRONG on current data**: at 56.8%
  acceptance the lane is inside the docs' win band (+56% decode); turning MTP off
  should move per-request decode DOWN toward the 39.9/64.8 ≈ 0.62× ratio of the
  docs — if anything MTP depth could be a candidate to RAISE only on evidence
  (cf-144 priced 3 = pack depth; q27's 7 is a DENSE DFlash2 head, not
  transferable).
- **Fork-vs-upstream, flagged explicitly**: the radiance FORK (stilldeadcode,
  image `radiance:1.17.0`, digest c2acbaa373…) exposes a flat
  `--num-speculative-tokens N` flag with an in-pack draft head. Upstream vLLM
  (docs fetched 2026-11-23, `docs.vllm.ai/en/latest/features/speculative_decoding/mtp/`)
  has no such flag: MTP is
  `--speculative-config '{"method":"mtp","num_speculative_tokens":N}'`, advises
  *"A small value like 1 is a good default to start with"*, and works "only for
  model families that support MTP". The upstream "guidance for MoE/512-expert
  models at depth 3" the launch hoped for **does not exist in either corpus**:
  the radiance docs give per-model RECIPES (flashnext TP1/TP2 yamls + HF cards
  all ship 3 for fn; dense q27 recipe 7), not a general MoE depth rule. Any
  conflation of `--speculative-config` with `--num-speculative-tokens` is
  fork-vs-upstream confusion — the same class the launch notes already
  misdirected this investigation.

## 4. Q3 candidate-cause table (measured window 18:52→20:47Z, rs6cp)

| # | candidate | metric that would confirm it | what the data shows | verdict |
|---|---|---|---|---|
| 1 | **Concurrency contention** (5 sessions sharing) | `vllm:num_requests_running`, per-request vs agg split, ITL | running p50 **4**, p95 5, peak 5 (of 8); `vllm:inter_token_latency_seconds` ratio p50 **88 ms**; per-request decode p50 **13.0**; agg 5m p50 **36.9**. Pre-scout hour (19:00–19:59Z): running 4, perReq p50 **11.7** — the 10–13 tok/s stands WITHOUT this scout's load | **SUPPORTED (headline mechanism)** |
| 2 | **Prefill-chunk starvation** (mixed steps dominate wall-clock) | step-kind counters | `engine_step_seconds_decode_total` 2,158 s / 35,702 decode steps = **60 ms**; non-decode steps: (6,721−2,158) s / 1,977 steps = **~2.3 s average per mixed/prefill step**, each advancing decode rows by only one draft round (~2.7 tok). 4,563 s of 6,721 step-seconds (**68%**) sit in chunk-capped prefill at `chunks_capped` = 260; duty cycle 6,721/7,020 s = **95.7%** (q27: 56%) | **SUPPORTED (the engine is never idle; work shape is ~290 reqs × 130K-prompt/900-gen)** |
| 3 | **Expert tiering × link** (spilling/re-read per step over a degraded link) | mover/heat byte counters | **None exist** (§8). Indirect, all consistent: boot `--placement expert_tiered`; elastic split `experts 17.74 GiB (67%) / kv 8.40 GiB (32%)` per card; `host_pool 12.59 GiB` per rank; prefill staging line *"a step of more than 1024 tokens copies the pooled experts of 48 routed layers onto the card up to 3 layers ahead"*; **`WARN link-below-max: card 0000:c7:00.0 (rank 1) … 8.0 GT/s x4 of its 16.0 GT/s x4 while the card is 34% busy`** + rank 0 `note link-capped … 16.0 GT/s x4 at most`; engine's own why: *"a prefill step streams every routed layer's pooled experts onto the card, so its speed is bounded by the link"*; measured `prefill_tokens_per_second` p50 **404** / p95 **806** vs creator TP2 card row **~6,400 @26K on Gen5 x8/x8** — and 404–806 ≈ 6,400 × (3.94–7.88 ÷ ~50) **scales with our Gen4x4/Gen3x4 widths** (DERIVED) | **SUPPORTED as the structural flash-vs-q27 difference; runtime bytes NOT MEASURABLE here — owner `/diagnostics`/`/stats` leg under load** |
| 4 | **Pool funding (52%/4.1)** | funding print vs demand | 4.1 sessions funded vs running p50 4 / peak 5; `vllm:kv_cache_usage_perc` p50 **0.74**, p95 **0.96**, peak **1.00**; `prefix_cache_evictions_total` +171,654 in 117 m; docs' sharp-cliff precedent ("173.0 s at 0.0% hit with a pool too small", RESEARCH §R14-Q2). BUT: **0 preemptions** (`num_requests_preempted`/`preempt_forced_total`/`vllm:num_preemptions_total` all 0), and hit rate stayed p50 **0.948** | **SUPPORTED as risk + churn; NOT the proven limiter this window (no cliff day, no preemption)** |
| 5 | **Batch cap 2048** | prefill rate at cap vs 4096 | `chunk geometry: … max_tok 2048 -> prefill chunks of at most 2048` at boot; docs verbatim (flashnext-tp1 yaml header): *"A prefill step copies every pooled expert across the link once… a 4096-token step amortises that copy over twice the tokens of a 2048-token one (26K prompts: 2545 vs 1413 tok/s)"*. Counter: the creator's TP2 recipe row ALSO ships 2048 and reached 6,400 — so 2048 is not why flash < q27, it is why flash's prefill pays 2× the per-token expert-copy cost it could | **SUPPORTED as a real prefill-amortization halver on this pack (knob: `RADIANCE_MAX_NUM_BATCHED_TOKENS` 2048→4096); REFUTED as THE lane-difference driver** |
| 6 | **Ngram on disk** | disk-wait / row-cache counters | None exist. Boot: `I placement: n-gram table (47.68 GiB) disk: as asked`; read-in-place line `4 weight(s), 95.37 GiB, read in place from the container's mapping — not copied and charged to no pool`; `note memlock-limited: RLIMIT_MEMLOCK is 8.00 MiB and the n-gram table is read from the container on disk … keeps --ngram-placement auto off [the RAM tier]`; `governor powersave`. Docs: table reads "a few rows a token" — **it IS on the decode path**; published delta of placement **3–10%** (cf-143 RQ1, §R14-Q4 rank 3). The launch's "TP1-era value": under TP1's 71 GiB pinned the RAM tier was arithmetically DEAD (D8.4-4); **at TP2 it is affordable** (working-set p50 39.2 GiB + 47.68 < 110) — but needs the node memlock drop-in, which the boot says it does not have | **NOT MEASURABLE (no IO counters); bounded ≤10% per docs; knob: `--ngram-placement` + node LimitMEMLOCK** |
| 7 | **MTP hurting** | A/B decode | §3: 56.8%/flat-74% acceptance, docs +56% win, refills 0 | **REFUTED on docs+acceptance; A/B on this rig not run** |
| 8 | **PCIe KV streaming** | `kv_stream_bytes_total` | in = **0 bytes** whole window; `kv_resident_blocks` 0; `stream_misses` 0 — this lane TIERs (prefix-cache-mib 4096), never mirrors; 0 429s; 0 admissions rejected | **REFUTED (plane is zero by design; the expert plane is #3 instead)** |

**Link-vs-q27 headline (launch asked for it):** the q27 lane showed a quiet link
(0 B) + full KV residency + per-request ~99 tok/s. The flash lane is the
opposite **on the expert plane**: half its card RAM is expert slab, its pooled
experts are re-read over a rank-0 Gen4 x4 / rank-1 **Gen3 x4 (WARN)** pair, and
96% duty with 2.3 s mixed steps starves decode rows to ~13 tok/s. That is the
real difference between the two lanes (see §9).

## 5. Throughput — per-request vs aggregate (rs6cp, 18:52→20:47Z)

Per-minute stats, `rate(...[5m])` unless noted; step 60 s:

| measure | p50 | p95 | peak (when) |
|---|---|---|---|
| **Aggregate** gen, 2 m rate | 17.7 t/s | 127.2 | **372.3 (20:38Z)** |
| **Aggregate** gen, 5 m rate | 36.9 t/s | 93.0 | 138.9 (20:06Z) |
| **Per-request** decode (`req_gen_sum[5m]/req_decode_sum[5m]`) | **13.0 t/s** | 77.3 | 84.9 (20:29Z) |
| ITL ratio (`inter_token_latency_sum/count`, 10 m) | 88 ms (≈11.4 t/s) | 285 ms | 503 ms |
| Hour split: 19:00–19:59Z (pre-scout) | agg **52.3**, perReq **11.7**, running 4 | | |
| Hour split: 20:00–20:47Z (scout in mix) | agg 43.9, perReq 18.5, running 4 | | |
| `radiance:decode_tokens_per_second` gauge | 7.0 | 184.9 | 248.1 (19:07Z) |
| `radiance:prefill_tokens_per_second` gauge | 404 | 806 | 4,097 (20:23Z) |
| TTFT mean-in-10 m-window | **23.0 s** | 92.5 | **192.6 s** |
| concurrency (`num_requests_running`) | 4 | 5 | 5 (cap 8 never near) |

Run totals: prompt admitted 37.85M; computed prefill 2.85M (**7.5%**, cache
95%); generated 261.6K; 290 completions (280 tool_calls / 8 stop / 2 abort),
mean prompt **130,357**, mean gen 901 tokens; hourly gen 14,969 (19:xx) vs
139,298 (20:xx — scout-hour, observer effect). Done-line printed rates (100-line
sample): 3.1 / 8.6 / 11.4 / 12.3 / 16.5 / 18.0 / 20.5 / 21.1 / 22.4 / 28.1 /
36.4 tok/s — the owner's "closer to 10 tok/s" is the measured per-request
median of this window (11.7–13), and "MAYBE 50 agg" is the 5 m aggregate p50
(37–52). Both of the owner's numbers are REAL and they are the SAME story:
**4–5 concurrent agent sessions ÷ a saturated engine**, not a broken lane.

## 6. Log findings (real lines, rs6cp; `{cluster="gpu-ai", container="radiance"}`)

- Boot ceiling + budget: `--max-model-len 262144 [command line]`; `card total
  31.86 GiB … claimable 30.21 GiB … static weights 3.58 GiB … elastic 26.62 GiB
  … experts 17.74 GiB 67% of it … kv cache 8.40 GiB 32% of it -- 52% backing of
  the 8 x 262144 worst case: 4.1 full-length sessions`; `card 0 settled at
  233.05 MiB free, against 221.78 MiB (the 96.00 MiB --gpu-headroom-mib and
  125.78 MiB kept for the step staging…)` (headroom line held on both cards).
- Pool/host: `I[0] pools: vram_weights 21.32 GiB … vram_kv 8.40 GiB … host_pool
  12.59 GiB budget` per rank (= configured 12288 MiB + 606.25 MiB embedding —
  the TP2 §7 profile, not a stale TP1 value; TP1-era was the ONE-envelope 43000);
  `checkpoint slots: auto: 72 linear-state snapshot(s) of 112.73 MiB (7.93 GiB)`;
  `kv tiers: … copied to host memory at once (4.00 GiB, 71697 entries, 286788
  tokens of context)` — **286788 > 262144, so the tier holds one full conversation
  and the q27-style "tier smaller than conversation" WARN never printed** (0 `W`
  lines all window).
- Expert plane: `I mover: 6365 slots can be lent out of the KV cache (7.52 GiB),
  filled as it lends them`; `heat engine: 25078 movable units, 64 moves a step…`;
  `prefill staging: a 498.27 MiB ring … copies the pooled experts of 48 routed
  layers onto the card up to 3 layers ahead of the layers that read them`;
  `I kv: the cache can grow to 8.40 GiB a card -- 1080204 tokens of context, 4.1
  sessions at 262144 -- with every block it lends the experts taken back`.
- Link: `I device: the 2 cards reach each other's memory directly (peer to
  peer)`; rank 0 `link 00:02.5 16.0 GT/s x4 (max 16.0 GT/s x4)`; rank 1
  `link 00:03.2 8.0 GT/s x4 (max 16.0 GT/s x4) [read at 34% busy]`;
  **`W startup report: link-below-max: card 0000:c7:00.0 (rank 1): … runs 8.0
  GT/s x4 of its 16.0 GT/s x4 … Fix: a link stuck one level down after long
  uptime has been cleared by a reboot; check that it recovers under load (GET
  /diagnostics during a long prefill), and reseat or move the card if it trains
  narrow`** — the same c7 card the q27 boot flagged; un-cleared.
- Host state: `cpu governor powersave, energy preference performance
  (amd-pstate-epp) | io_uring available`; `memlock 8.00 MiB` + memlock-limited
  note on the ngram tier. cf-143's rank-1 suspect (governor never at performance)
  **is still true at this boot.**
- Wire lossiness: `W tp wire: LOSSY (--tp-wire wht6) at 128 KiB a message and
  above` (accuracy rider, already ruled); libhalo/libr3d fat-binary declines
  (gfx1151-only, inert here).
- Window hygiene: **0 `E` lines, 0 `W` runtime lines, 0 refusals, 0 4xx/5xx,
  0 preemption lines, 0 queue/reload/`not serving` lines**; only churn counters
  (§4#4). `18:50:19 I serving on http://:::8000`; last done-line before scout
  end 20:4xZ. No restarts (§1).
- Done-line shape (contention quotes): `19:11:05 … prompt=137245 (cache 129024)
  gen=536 … ttft=19.03s 3.7 tok/s 162.81s`; `20:19:46 … prompt=149112 (cache
  147456) gen=1330 … ttft=190.66s 3.1 tok/s 624.92s` — the second is a **99%-cached
  prompt taking 190 s to first token**: queue/chunk starvation, not cache miss.

## 7. Arithmetic shown (all inputs from boot prints or counters above)

- **Per-token context cost**: kv_attn page 26.00 KiB / 4 tok = **6.5 KiB/token/card**;
  kv_qsa_bkey 3.25/4 = 0.8125 → **7.3125 KiB/token/card → 14.625 KiB/token lane**
  (the launch's "~12 KiB/token trunk" was ~18% optimistic). Check: 8.40 GiB ÷
  7.3125 KiB = 1,100,361 ≈ printed 1,080,204 (block rounding + the 883 MiB
  per-seq-state carve) ✓. Tier entry 29.25 KiB / 4 tok = 7.31 KiB/token lane-side
  ✓ consistent.
- **Pool funding**: 8 × 262,144 = 2,097,152 tokens needed vs 1,080,204 funded =
  **51.5% → print's 52% / 4.1 sessions**; D9(a) bar M ≥ 8 → REFUTED (also at
  200000: 5.5 < 8). One 262144 session = 1.87 GiB/card.
- **Expert universe vs pool (DERIVED, answering "TP1-era pool on TP2 ranks")**:
  25,078 units/rank × 1.21 MiB (the TP1 receipt's 2.42 MiB unit halved per rank,
  R14-Q3 §D8.2) ≈ 30.3 GiB universe/rank; resident 17.74 + host pool 12.59 ≈
  30.3 GiB → at boot the plane is FULLY covered card+host (nothing expert on
  disk); what the 12288 buys is a HOST-pinned pool that every step may re-read —
  12.55 GiB/rank of the universe lives across the link by design. The q27 lane
  has NO such plane. This is why the flash lane's step time is link-shaped and
  q27's was 0-bytes quiet.
- **Prefill step economics**: mixed/prefill steps measured at ~2,308 ms avg with
  chunk cap 2048 → realized prefill 404–886 t/s ≈ the engine's expert-copy
  amortization at our widths; docs' same-pack ladder on the creator's TP1 x16-era
  rig: **2545 (chunk 4096) vs 1413 (chunk 2048) t/s — exactly 2.0×**, and the
  ratio is what 4096 would buy here too (link-parallel, same copy count halved).
- **Duty/saturation**: step-seconds 6,721 s vs window 7,020 s = 95.7%; decode
  wall-share 2,158 s (31%), prefill-chunk-share 4,563 s (65%) — while users
  experienced "the lane is slow", the engine was 65% busy doing cold-ish prefill
  chunks (2.85M computed tokens at 2048 a step).
- **Decode math**: gen 261,565 ÷ 37,523 decode+mixed steps = 6.97 tok/step ÷
  ~2.6 active rows/step ≈ 2.7 tok/row-step (matches draft ladder 1+1.70 accepted);
  row-step cadence at 60 ms decode-only floor ≈ 45 t/s solo; the observed 13 is
  the mixed-step (2.3 s) dilution.
- **Working set vs caps**: p50 39.17 / peak 39.23 GiB vs 110Gi limit — huge
  headroom; ngram-to-RAM arithmetic (39.2 + 47.68 ≈ 86.9 < 110) is affordable at
  TP2 (unlike TP1) **if** the memlock limit moves.

## 8. Not instrumented (unanswerable from /metrics + Loki today)

- **Expert streaming bytes / mover traffic / slab residency over time** — no
  family exists (census: nothing under `radiance:` names expert/mover/heat).
  The engine's own counters for these live on `/stats` + `/diagnostics` —
  owner-exec (AGENTS MCP law). §4#3's link theory is therefore indirect-only.
- **Runtime PCIe state** — link width only at boot; the rank-1 Gen3 parking
  persisting/cleared under load is owner-lane (lspci / `/diagnostics` during a
  long prefill, the engine's own fix text).
- **Per-card VRAM over time** — no amdgpu/vram family (sibling verified
  negative census; unchanged).
- **Host-pool occupancy over time** — boot `12.59 GiB budget` only; no usage gauge.
- **Ngram disk I/O wait / row-cache hit rate** — no counter; `lookup_*` (the
  prompt-lookup drafter path) is a DIFFERENT plane and stayed 0.
- **Owner-vs-agent traffic attribution** — single client ip (llama-swap). Ports
  rotate per session but no identity is mapped. Observer effect is real in
  hour 2; hour 1 (19:00–19:59Z, pre-scout) is the cleaner owner proxy.
- **The MTP pass cost** (3 serial draft passes → ms/step) — counters give
  acceptance, not the time cost of the passes; only an A/B (or docs §4.6 step
  table windows, which exist) settles it.
- **Gauge semantics** — `radiance:decode_tokens_per_second` /
  `prefill_tokens_per_second` remain undocumented repo-wide (sibling caveat
  carried); rate-based figures are the primary record. `engine_step_seconds_*`
  appear to be wall-seconds-per-step (their averages reproduce the observed
  prefill rates); treat as inferred.
- `vllm:request_prompt_tokens_bucket` tops at le=200000 (same as q27): the 20
  over-200K requests are a +Inf lump.

## 9. Most probable cause + the falsifying measurement

**The lane DID get the raised ceiling (262144 on every witness). The slowness is
not a ceiling defect, not MTP, and not a PCIe-KV story (that plane is 0 bytes).
The measured picture: a 4–5-concurrent, ~130K-prompt agent workload pushed a
~96%-cache-hit prefill demand through a TP2 MoE lane whose KV pool funds only
4.1 full sessions and whose expert plane re-reads ~12.5 GiB/rank of host-pinned
experts over a Gen4 x4 (rank 0) / Gen3 x4 (rank 1) link — so 65% of engine
wall-clock goes into ~2.3 s chunk-capped prefill steps (2048-token cap
halving the amortization) that advance decode rows one draft round each,
yielding per-request ~13 tok/s against a 60 ms decode-step floor.
Confidence: HIGH that the ceiling and MTP are innocent (multi-receipt);
MEDIUM-HIGH that the expert-streaming × link × batch-cap stack is the
first-order limiter (strong indirect fit: prefill scales with link class,
65% step-time share, creator rig with Gen5 x8/x8 got 16× our prefill on the
same recipe); LOW-grade but un-cleared: the powersave governor (cf-143's
rank-1 host suspect, still printed at this boot) competes for part of the gap.**

**The single falsifying measurement: one fixed-probe single-stream run on this
pod (short prompt, 512-token gen, zero concurrency) read against the docs'
62–65 t/s (with-MTP) / 39.9 (no-MTP) TP2 band.** If single-stream decode lands
in/above ~40–60 t/s, the ~13 tok/s is PURE contention/prefill-coupling (the
pool-funding + batch-cap + seqs knobs), and any "lane is broken" theory (link
included) dies; if it lands ~10–20 t/s solo, the link/expert-streaming story
headlines and the owner's `/diagnostics` + reboot/reseat leg takes priority.
Supporting measurements after that, in cost order: (a) owner `/stats` two-point
delta during a long prefill (mover bytes — settles #3), (b) `chunks_capped` +
prefill rate after a 2048→4096 batch-cap boot comparison (settles #5, one env
edit), (c) the governor fix at performance + fixed-probe best-tile (settles the
host-gap share), (d) ngram placement A/B after a memlock drop-in (settles #6,
3–10% band).
Knob pointers only, per the launch's rule — no recommendation is made here;
the evidence that would justify each turn is named.

## 10. Contradictions, stated bluntly

Against the launch's own premises:
1. **"Determine whether the current pod serves 200000 or 262144" / "if the argv
   shows 200000, say so loudly"** — it does not: rs6cp serves **262144**
   (argv, CONFIGURATION print, 20 accepted >200K requests, zero 4xx). The
   deploy-provenance defect the sibling's lane flirted with is HISTORICAL for
   fn: its RS template was born in the same pre-merge 04:00Z wave, but the pod
   booted 14 h after `bc4b2a3fa` and its live env equals current main.
2. **"A TP1-era host-pool size sitting on TP2 ranks" / "2048 is a TP1-era value
   inherited by a TP2 lane"** — both inverted vs the repo: 12288 PER RANK and
   2048 are the cf-144 §7 **TP2 recipe** values (byte-for-byte as ruled,
   DECISIONS D43-era; `RESEARCH.md:261` fn HF card TP2 row uses both); the
   TP1-era values were the one-envelope **43000** and **4096**
   (`git show e7536b2c9^:charts/radiance/values.yaml:149-159`). flash-TP1 still
   carries the TP1 pair (43000/4096) and has NEVER booted (zero pods, zero
   scrapes in the 30 h census).
3. **"The 27b lanes don't carry [spec tokens] at all" → implying q27 does not
   speculate** — q27 simply lets the pack default fire (sibling's boot: depth
   **7** resolved without the flag). Both lane families speculate; the asymmetry
   is declared-vs-default, not on-vs-off.
4. **"12 KiB/token trunk"** — measured 14.625 KiB/token lane (§7). And the
   "MTP adds ~1–2 KiB/token on top" worry lands inside the pool the 52% print
   already prices; the concurrency tax is the expert slab, not the drafter.
5. **"The flag might not be zeroable at all for this pack"** — the docs' own
   fn TP2 table contains **without-MTP rows** (39.89/39.78 t/s), so an off
   state demonstrably exists and is priced; the exact flag syntax to reach it is
   unverified in our fetched windows — say "unverified mechanism", never
   "unsupported".

Against the owner's account:
6. **"Flash running at 200k"** — refuted (§2); the owner may have seen the
   old-`limit.context` catalog prose or the `RADIANCE_MAX_MODEL_LEN` git-era
   value, not the lane.
7. **"10 tok/s or maybe 50 agg" on a lane designed to be fast** — both numbers
   confirmed (§5), but the design expectation belongs to the DOCS' single-stream
   class (62–65 t/s) — at 4–5 concurrency this lane was never running the
   benchmark it was designed against; "closer to 10" is contention arithmetic,
   not a broken floor.
8. **"12:00→now"** — true modulo the ~UTC−7 offset; the pod's life IS the
   window (booted 18:49:59Z), so there is no longer flash era to blame.

Carried from the sibling scout (re-verified, not re-derived): PromQL arg names,
`query_loki_stats` pipeline rejection, Loki pod-in-structuredMetadata, owner
clock offset, and the `0eeee59c3`-vs-`bc4b2a3fa` provenance note — all
consistent with this round's observations.

## Appendix A — exact queries (datasourceUid `prometheus` / Loki `P8E80F9AEF21F6940`)

`P = pod="gpu-ai-radiance-544c9bbdf5-rs6cp"`, window `2026-11-23T18:50→20:47Z`
(counters `increase(...[117m])` ending 20:47Z).
1. Census: `group by (__name__) ({__name__=~"radiance:.+|vllm:.+"})` instant;
   `group by (model_name) (radiance:engine_step_seconds_total)`.
2. Chronology: `up{job="radiance"}` range 11-22T14:00→11-23T20:46Z @60;
   `rate(vllm:generation_tokens_total{model_name="qwen3.8-flash-next-radiance"}[5m]) > 0`
   @60; readonly-ai-gpu-kubernetes pods_list_in_namespace(default) +
   pods_get(rs6cp).
3. Throughput: §5 table expressions (2 m/5 m `rate`, ratio, ITL/TTFT window
   means, hourly p50s @300 s).
4. Totals: `increase` of `vllm:{prompt,generation}_tokens_total`,
   `vllm:request_{generation,prompt}_tokens_{sum,count}`,
   `vllm:request_{success,prompt_tokens_bucket}`, `vllm:num_requests_{running,waiting}`,
   `radiance:{http_queue_depth,http_admission_rejected_total,http_responses_total,client_disconnect_total}`,
   `radiance:engine_{steps,step_seconds}_{decode,prefill,mixed,held}(_total)`,
   `radiance:engine_prefill_chunks_capped_total`,
   `radiance:draft_{tokens,accepted}_total`, `radiance:draft_position_{reached,accepted}_total`,
   `radiance:decode_rows_unspeculated_total`, `radiance:draft_refill(s)_total`,
   `radiance:lookup_*`, `radiance:{num_requests_preempted,preempt_forced_total}`,
   `vllm:num_preemptions_total`, `radiance:kv_stream_bytes_total{dir="in"}`,
   `radiance:kv_stream_misses_total`, `radiance:kv_resident_blocks`,
   `radiance:prefix_cache_*`, `vllm:kv_cache_usage_perc`,
   `vllm:gpu_prefix_cache_hit_rate`, `radiance:kv_cache_max_{tokens,bytes}`,
   `container_memory_working_set_bytes{pod=...,container="radiance"}/1073741824`.
5. Loki (all with `startRfc3339`/`endRfc3339`): `|= "composed engine argv"`
   72 h; boot tail `{selector}` 18:49:30→18:58:00 (argv, budget, pools, mover,
   heat, chunk geometry, checkpoints, tiers, draft floor, CONFIGURATION,
   startup report); `|~ "(?i)(link|GT/s|WARN|not serving|listening|ready|http)"`
   18:50:19→19:00; `|= " pool backs "` / `|= "sessions at"` 11-22T22:19→11-23T04:10;
   `|= " done from "` (100-line sample 18:52→); `|= " W "`, `|= " E "`,
   `|~ "(?i)(refused|400|maximum context|exceeds)"`,
   `|~ "(?i)(governor|HARDWARE|powersave|io_uring|memlock)"`,
   `|~ "(?i)(queue|stopping|reload)"` over 18:52→20:48.
6. Docs/upstream: repo windows (cf-143 RESEARCH `R14-D/E`, `R14-Q2/3/4`,
   `R15` batch-cap quote, `R19-S2 §4.6` draft-head-defaults, `R8-Q5` TP2 §7
   verbatim; cf-144/cf-143 DECISIONS + values.yaml annotations); webfetch
   `docs.vllm.ai/en/latest/features/speculative_decoding/mtp/` (2026-11-23).
7. Git: `show bc4b2a3fa` (04:41:49 +0000); `log -L` + `show e7536b2c9^:charts/radiance/values.yaml`
   (TP1-era 43000/4096/200000 lines 149–159).

RESULT
status: DONE
chunk: explore (flash-TP2 perf scout)
files_changed: [.agents/plans/2026/2026-11-bug-radiance-flash-tp2-perf/EXPLORE.md]
commands_run: [repo reads/greps (values.yaml fn+flash-TP1 lane blocks, charts/radiance FORM serve.sh, parent D47 + cf-143 R14/R15/R19 windows, opencode.jsonc catalog rows) => pass; git log/show -L (read-only; bc4b2a3fa date, e7536b2c9^ chart) => pass; readonly-ai-gpu-kubernetes pods_list_in_namespace + pods_get(rs6cp) => pass; readonly-global-grafana query_prometheus ~20 (census, up chronology, rates/increases, buckets, working-set) => pass; query_loki_logs ~10 (argv echoes 72h, boot block, startup report, pool backs, done/W/E/refusal/governor classes) => pass; webfetch upstream vLLM MTP docs => pass; date -u => pass]
deviations: none — wrote only the EXPLORE.md at the named path (folder auto-created by write); no config edits; the "1 restart" seen in pods_list was verified FALSE (pods_get containerStatuses restartCount=0 — list column was Ready, misparsed then corrected before recording)
friction: query_loki_logs silently ignores startTime/endTime — it wants startRfc3339/endRfc3339 (defaulted my first probe to last hour, returned 0; recorded §0); list_prometheus_metric_names truncates at limit so radiance:/vllm: families were invisible in the first 1000 alphabetical names — use the __name__-regex census instead; Loki 'structuredMetadata.pod' filter must be done client-side (sibling law, honored); engine gauge semantics (decode/prefill_tokens_per_second, engine_step_seconds_*) still undocumented anywhere — figures labeled accordingly
open_questions: [needs research: yes — (1) GUIDE v1.17.0 §4.6/§4.11 VERBATIM for the MTP off mechanism (--num-speculative-tokens 0 semantics vs "used by default at the depth the plugin states") and any MoE depth guidance beyond the per-recipe tables; (2) price 4096-chunk amortization for THIS TP2 lane from the docs' expert-copy model (the 2545-vs-1413 quote is TP1-era creator rig); (3) owner-side measurements this scout cannot take: /diagnostics + /stats two-point delta under load (mover/expert bytes, link-under-load), the fixed-probe single-stream run vs the 62–65/39.9 docs band, and the rank-1 c7 Gen3-x4 retrain/reseat leg (engine WARN's own fix text), plus the powersave-governor persistence question cf-143 ranks #1; (4) whether the community fn-TP2 convention (pool 12288 + prefix 12288 + max-num-seqs 2 at 262144, R14-S6 gostar77 card) is the envelope the owner actually wants — it halves/halves-down the 8-session promise D9(a) bars against, so the 52%/4.1 print needs an owner ruling, not a scout opinion]
next_suggested: hand to agent-research for the optimization round with §9's falsifying measurement (single-stream fixed probe) as the first data ask; note this file also captures cf-144 P11's long-owed first-TP2-print receipt content (52%/4.1 — a REFUTING print under D9(a), pre-agreed C03 forward-fix shape), which the coordinator should route to the owner rather than re-run.
