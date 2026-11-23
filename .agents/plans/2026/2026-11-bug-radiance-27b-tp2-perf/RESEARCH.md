# RESEARCH — 27b-TP2 radiance lane: optimization round (Q1–Q6)

- **Ticket folder:** `.agents/plans/2026/2026-11-bug-radiance-27b-tp2-perf/`
- **Round:** agent-research, 2026-11-23. Builds on `EXPLORE.md` (scout, same date) — and **tests** its
  re-attribution rather than relaying it. Scope additions: Q6 (MTP) from the owner, mid-round.
- **Method:** `storm` skill — five derived perspectives (§1), live retrieval-grounded answers
  (`global-searxng` discovery + direct fetches of the Radiance docs at the pinned tag `v1.17.0`,
  AMD/Qwen/HF/Codeberg), and re-measurement of the scout's claims over the **whole 14 h 45 m pod
  life**, not only the owner's 3 h 09 m window.
- **Mode:** read-only everywhere except this file. No config/code edits, no commits, no pod exec,
  no admin tiers. Labels used throughout: **MEASURED** (query/log/receipt with its source),
  **DERIVED** (arithmetic from measured or cited inputs, shown), **CLAIMED** (source assertion,
  attributed).
- **Sources list is §S at the end; every non-obvious claim carries `[Sn]` or a file:line.**

## TL;DR

1. **The "40% prefill deficit vs 3,212" is mostly a comparison artifact, not a defect.** The ladder
   row is a *64 k-context* measurement; our 1.9 k is at *~185 k context*. On this hybrid architecture
   per-token prefill FLOPs rise 1.59× from 64 k to 185 k (DERIVED, §2), and the engine's own published
   points (4,655 t/s @24 k; 2,665 t/s @221 k [S1]) are reproduced by that model to within 1.3%.
   Length-corrected, a Gen4-×4-class rig should do ~2,313 t/s at 185 k; **our best observed cold prefill
   is 2,405 t/s (MEASURED) — i.e. at class, ~104%.** The residual to the creator-rig figure (~2,880) is
   link class + rig, not a broken lane.
2. **The scout was right that the KV/PCIe theory is dead, and wrong that all PCIe candidates are 1–2
   orders of magnitude too small.** It priced only KV-stream (0 bytes — confirmed over the full life)
   and the embedding gather. It never priced the **TP collectives**, which are per-token and MB-scale;
   the docs' own law is that *"every rank's link carries at least the whole message each way… so the
   slowest link sets the time of every prefill all-reduce"* [S1]. DERIVED (§3): 2.68 GB of all-reduce per
   2048-token chunk on the exact wire, 1.51 GB with `wht6` — vs ~711 ms of compute for that chunk. On a
   Gen3-×4 leg that is 96% / 54% of compute time. `wht6` is load-bearing here, and rank 1's parked link
   is a live prefill-headroom suspect, not a curiosity.
3. **MTP is unambiguously active on this lane and disabling it is a bad trade (Q6).** The absent env does
   not mean off: the boot receipt prints `speculation: depth 7 … 'dflash2' proposes 7 token(s) in ONE
   block pass over 8 row(s)` (MEASURED), and the lane drafts 4.95 gen-tokens per decode step with
   per-position acceptance 0.70→0.77 (MEASURED). Disabling it frees ≈0.67 GiB/card (≤3% of the pool →
   ~+0.16 fundable sessions, DERIVED) and costs most of decode (docs' measured MTP gain: 39.9 → 62–65 t/s
   [S1]). **Verdict: the proposed fix does not apply to this lane — it points at the flash lanes.**
4. **The 66% / 5.3-session finding is the lane being provisioned by ruling rather than arithmetic**, and
   the pool arithmetic is now fully decomposed and exact: `22.24 = 20.98 (kv_attn) + 1.16 (per-seq state)
   + 0.09 (kv_draft)` GiB/card (MEASURED boot lines, sums to the printed elastic to 0.01 GiB). The
   documented, per-lane-settable fix that closes most of it without touching held memory or FORM seqs is
   the narrow KV layout (`k6_v4` = 22/32 of fp8 cost, +16% measured long-prompt prefill [S1]) — but the
   dtype flag is FORM-fixed, so it is a chart-wide ruling with an accuracy purchase, not a tweak.
5. **Nothing in the measured record says "reduce concurrency".** Allocation is lazy, the pool reached
   1.0000 usage with 0 preemptions / 0 admission rejections / waiting max 1, and the engine's own
   degradation path at pool exhaustion is eviction → recompute → preemption [S2], never refusal. The
   real, previously-unquantified cost is the **prefix-hit cut tax: 2,186,144 of 7,819,024 lifetime
   computed tokens (28%) are recompute below a shortened hit** (MEASURED) — a cache-shape cost, not a
   bandwidth cost.

## Reliability notes (storm peer review)

| Finding | Confidence (1–10) | Reason |
|---|---|---|
| KV/PCIe prefill theory refuted; `kv_stream_bytes`=0 full life | 10 | Counter re-queried over 14 h 50 m [S12]; matches scout |
| "40% deficit" is chiefly a context-length artifact | 8 | FLOPs model reproduces both docs anchors within 1.3%; one un-re-fetched external anchor (Wilde's row, [S10]) |
| Gen3 leg is a *prefill-headroom* suspect via collectives | 6 | Volume law + geometry DERIVED; exposed fraction unknown (overlap/fusion machinery unmeasurable here) |
| Pool decomposition exact (20.98+1.16+0.09) | 9 | Boot receipt lines, sums to printed elastic |
| MTP active; disabling = ~+3% pool for ~−60% decode | 9 | Boot receipt + draft counters + docs' measured MTP rows |
| Tier churn is retention-driven, not store-full-driven | 7 | Reason census measured (74/2,945 store_full); counters' scope not doc-verified |
| `prefix_hit_cut_tokens` = 28% of computed | 6 | Metric name/label semantics undocumented; interpretation DERIVED from `reason=resumed_below` |
| k6_v4 → ~7.7 fundable sessions | 7 | Docs' 22/32 ratio [S1] × measured per-card budget; the docs' own 755,184-token row is version-dated |

**Weakest claim:** the collective-exposure estimate (§3.3) — it assumes 2 unfused all-reduces/layer over
the full 5,120-wide hidden and no overlap; TP4.md shows the fork *does* overlap at two ranks [S3]. It is
therefore an upper bound on link sensitivity, offered as a falsifiable hypothesis with a cheap test, not a
verdict. **Verify with:** `rocm-bandwidth-test` card↔card + one `--tp-wire exact` A/B boot (§3.4).
**Perspective over-weighted:** P1 (engine-throughput) — its FLOPs model explains most of Q1 and may tempt
under-attribution of the link; §9 keeps P2's dissent on the record.
**Missing 6th angle:** a *workload-client* analyst — 707 completions came from one client IP in
tool-calling chains; if the agent client truncates/replays context, part of the "96% hit rate" is a client
artifact, not an engine property. No data here can test that.

---

## §0 — What was measured vs assumed, and what I could not verify

**Re-measured over the WHOLE pod life (03:55→18:55Z, step 300–60 s), not the owner's window** [S12]:

| Scout claim (EXPLORE §) | This round | Verdict |
|---|---|---|
| 96% of admitted prompt tokens were prefix-cache hits (§4, window) | lifetime cached/admitted = **0.948** on ppt7l; **0.969** on the previous 200 k pod d8sj7 | **HOLDS, not window-specific** — it is the workload's nature (agent tool-chains), and it held at the old ceiling too |
| `kv_stream_bytes_total` = 0 for pod lifetime (§4/§5) | `increase(...[14h50m])` dir=in = **0**; `kv_resident_blocks` = 0 | **HOLDS** |
| 520 `chunks_capped` in run, 564 lifetime (§4) | `[3h15m]`=527, `[14h]`=525, `[14h50m]`-style windows vary | **PARTLY** — magnitude right; `increase()` across the 04:01 counter reset extrapolates, so lifetime totals are only approximate. Capping is NOT window-only: the 04:05–05:40 verification burst also produced capped events |
| prefill gauge "p95 2,308, peak 6,865" (§4) | active-only (>0, 60 s step, full life): p50 **1,232**, p90 **2,546**, p95 **2,856**, max **6,865** | **DISCREPANCY = filtering**, not data: the scout's window differs. Peak reproduced exactly. Gauge semantics remain undocumented [S6] — the log done-lines are the primary record |
| cold 1.9 k solo / 400–900 under 5–7 streams (§4) | 855 done-lines ≥100 k parsed from both pods: cold ≥130 k → median **1,903**, best **2,405**; slowest (620, 1,004 t/s) had **61–103 capped events in the prior 3 min**, fastest (2,327) had **0** | **HOLDS, with a correction:** the ceiling is ~2.4 k even solo; sub-1 k is shared-step scheduling (confirmed), but the 1.9 k median is *not* purely scheduler |
| "150 tok/s was per-request p95" (§3/§9.2) | aggregate gen rate bucketed by concurrency: 1 stream med 89 / max 469; 4 streams med 204 | **HOLDS** (relabelled, not contradicted) |
| running peaked 7, never 8 (§3) | `max_over_time(num_requests_running[14h50m])` = **7** | **HOLDS full-life** |
| 66% / 5.3 sessions; pool all-VRAM (§5/§7) | boot lines quoted verbatim (§4.1 below); pool usage max = **1.0000** | **HOLDS** |
| 262144 admissions: ~105 >200 k, zero refusals except the 755,328 outlier (§6/§7) | refusals over 22:00 (prev. day) → 18:55Z: **11** lines all on d8sj7 at the 200,000 bound (200,047 / 200,185 / 204,684 / 238,139 / 283,516 — the 200,047 request retried 7×), **1** on ppt7l (755,328) | **HOLDS, and strengthened across the full life** — the raise retired 11 of 12 refusals. The `le=+Inf − le=200000` bucket arithmetic did not return a usable lifetime count (label-pair subtraction failed) — **not independently verified** |
| 0 preemptions / 0 OOM / 0 restarts (§5) | `vllm:num_preemptions_total`, `radiance:preempt_forced_total`, `radiance:num_requests_preempted`, `engine_steps_held_total` all **0** | **HOLDS** |

**Claims I could NOT verify this round (and did not adopt as fact):**

1. **The 3,212 row's own provenance** — engine version, `--max-num-batched-tokens`, concurrency, link
   widths of Wilde's rig. Not re-fetched (blog cited via the repo's own §R19-Q4 attribution table [S15] and
   the prior round's 2026-11-22 re-fetch [S10]); its context length (64 k cold) is the repo-recorded value.
   **Treat every use of it below as conditional on that record.**
2. **`--gpu-headroom-mib 96` "costs the pool ~0.19 GiB/card"** (scout §8) — the 96 MiB/card is measured;
   the pool *loss* attribution is DERIVED by the scout and plausible but not printed anywhere.
3. **"no `dir="out"` series exists"** — I did not re-run the negative census; only `dir="in"` was needed.
4. **Exact tie between each slow cold prefill and a per-second running count** — my offset-instant lookup
   returned null (`runningMaxBefore` null in all probes); the correlation I report uses *capped-event
   density in the preceding 3 min* as the proxy instead.
5. **P2P realized bandwidth under load** — no series exists (scout §10 confirmed; nothing to add).
6. **Which ref-state ArgoCD rendered at 03:59Z** (scout §1 deploy wrinkle) — out of scope, still open.
7. **Semantics of `radiance:prefix_hit_cut_tokens_total` / `prefix_cache_expired_total`** — not documented
   in GUIDE@v1.17.0 or OPS@v1.17.0; I use them with the label evidence (`reason=resumed_below`,
   `reason=store_full`) and label the interpretation DERIVED.
8. **Docs-version drift for claims I took from `main`** (TP4.md, README profiles, PREPARING_YOUR_RIG.md):
   these are 2.x-era documents; v1.17.0 GUIDE's flag table does not appear in the same form on `main`
   (checked: string `| \`--max-num-batched-tokens N\`` absent from GUIDE@main). Issue #457 — *"v2.0.0 …
   30% less throughput than 1.17.0 and a decode step about 2× longer"*, **open** [S7] — proves the fork's
   numbers move materially across versions. Everything labelled `[S1]/[S2]/[S6]` was fetched at the pinned
   tag; everything `[S3]/[S4]/[S5]` is `main` and must be re-priced against our pin before shipping.

---

## §1 — Perspectives: derived from the sources, not a stock cast

Five lenses with genuinely different stakes, each with what it sees that the others miss and where it
conflicts. Conflicts are carried to §9 unresolved where real.

| # | Perspective | Lens / stake | What it sees that others miss | Its conflict |
|---|---|---|---|---|
| **P1** | **Inference-engine throughput engineer** (kernels + chunk geometry) | "Is the step doing the FLOPs it should?" — defends the engine's published numbers as the only legitimate baseline | The docs' own two anchors (4,655 @24 k / 2,665 @221 k) *are* a length-scaling curve; `chunk = min(budget, interval×span)` and the arena law mean most "missing speed" is mis-framed | Vs P2: the docs' exact→wht6 delta is only +7% at 221 k — if the wire capped prefill, cutting payload 2.7× would pay far more than 7% |
| **P2** | **Interconnect / PCIe-topology engineer** | "What is on the wire that nobody instrumented?" — defends the claim that the rig, not the config, sets the ceiling | Radiance's own two-shot rule makes the *slowest* link the prefill all-reduce clock [S1]; ReBAR is a P2P prerequisite [S5]; a parked Gen3 leg is within ~2× of compute time, not 50× | Vs P1 and vs the scout: "1–2 orders too small" was asserted without pricing collectives |
| **P3** | **KV-cache / tier-policy engineer** | "How much context is *actually recomputed*, and why?" | The dominant measured loss is the prefix-**hit cut** (28% of computed tokens), not bandwidth and not refusal; `kv_draft` is *windowed, not cached* — so drafter cost is per-sequence, not per-context-token | Vs P4: the docs' pool law says a full pool ends in preemption; a 66%-funded pool is a *real* risk the lazy-allocation argument cannot wish away |
| **P4** | **Scheduler / concurrency engineer** | "Was the worst case ever reached?" | `max-model-len` reserves nothing per request [S1]; usage hit 1.0000 with 0 preemptions and waiting max 1 — the deficit is *addressed*, not *met* | Vs P3/P5: "not stressed today" ≠ "correctly sized"; the D9(a) `M ≥ 8` bar is a *funding* test, and it reads 5.3 |
| **P5** | **Owner's capacity auditor** (ruling-vs-arithmetic) | "Which 'defects' are actually purchases the owner already signed?" | Four purchases hide inside this lane: 262144 at 8 seqs (unfundable at 100%), 4 GiB tier < one conversation ("partial retention IS the config"), `wht6` (buys bits-swap speed), and both cards for p50 concurrency = 1 | Vs everyone: any knob that "changes the text" (docs) is an accuracy purchase, not a free win — including the two levers P1/P3 like best |

---

## §2 — Q1: why solo cold prefill runs ~1.9 k when the ladder says 3,212

### 2.1 First: the number being compared is not a like-for-like quantity

Three separate mismatches, each quantified:

**(a) Quantity.** 3,212 is a *dedicated single-prompt* cold prefill rate. Our 1,903 is
`(prompt − cache)/ttft` from a live agent stream — a per-request end-to-end rate that carries queue wait,
the drafter-window tail and any shared step. The engine's own instantaneous figure on the same hardware
reaches **6,865 t/s** (MEASURED gauge max, at `num_requests_running = 1`, 16:45Z) — i.e. the lane is not
hard-capped at 1.9 k; the *measurement* is.

**(b) Context length — the big one.** Geometry [S8]: 64 layers (16 full-attention + 48 linear),
hidden 5,120, 24 query heads, 4 KV heads, `head_dim` 256, `attn_output_gate`.

DERIVED, shown so it can be checked:

```
GEMM FLOPs/token        = 2 × ~24.3e9 active params  ≈ 48.6 GFLOP   (length-independent)
attention FLOPs/token   = 4 × head_dim × n_q_heads × L_mean × n_full_layers
                        = 4 × 256 × 24 × (P/2) × 16  = 196,608 × P  (linear in prompt length)
```

| prompt | GFLOP/token | docs-rig predicted t/s (calib. @24 k) | docs-rig predicted (calib. @221 k) |
|---|---|---|---|
| 24 k | 53.3 | **4,655** (anchor) | 4,601 |
| 64 k | 61.2 | 4,057 | 4,010 |
| 185 k | 85.0 | **2,921** | **2,887** |
| 221 k | 92.1 | 2,696 | **2,665** (anchor) |
| 262 k | 100.1 | 2,479 | 2,450 |

The two independent calibrations agree to **1.3%** at each anchor — so the docs' own published pair
[S1, `--attn-prefill-fp8` table] *is* this curve, and attention is ~43% of the work at 185 k on a
16-of-64-layer hybrid. **Length alone explains 3,212 → ~2,313 on a Gen4-×4-class rig.**

**(c) Rig class.** Rescaling Wilde's 3,212 (64 k) to 185 k gives **2,313 t/s** (DERIVED, same curve).
Our best observed cold prefill at 185 k is **2,405** (MEASURED, 156,864 cold tokens in 65.22 s, on the
*200 k* pod) and **2,327** at 172,724 cold with **zero** capped events in the preceding 3 min. The lane is
running **at** the Gen4-×4 class, ~104%; the creator-rig class (~2,880) is 20% above it — and the docs'
own rig is "MSI MPG X670E CARBON, Ryzen 9 7950X3D … **32.0 GT/s PCIe x8 per card**" [S5], i.e. 4–8× our
per-lane wire.

### 2.2 What is left after the artifact is removed

Residual ≈ (median 1,903 vs ceiling 2,405) = **21% scheduler**, plus (best 2,405 vs Gen4-class model
2,313) ≈ **0%, at class**, plus (docs-class 2,880 vs our class 2,405) ≈ **17% rig/link/power**.

- **Scheduler (MEASURED, confirmed):** cold ≥130 k requests with 61 and 103 capped events in the prior
  3 min ran 620 and 1,004 t/s; the one with 0 capped events ran 2,327. This is *design*: `--busy-prefill-chunk`
  default `auto` — "a prefill chunk sharing a step leaves decode rows and waiting requests their room …
  so a long prompt (a minute or more at 256K) does not starve decode rows or admission" [S1]. Boot print:
  `scheduler: --busy-prefill-chunk auto: … keeps at least 64 tokens` (MEASURED). **So the scout's
  "scheduler artifact rather than physics" is right about the *shortfall*, wrong if read as "the ceiling is
  fine": the ceiling itself (2.4 k) is rig-class physics, not a scheduler illusion.**
- **Chunk geometry (MEASURED boot line):** `chunk geometry: quantum 64 (attn block 16, state chunk 64),
  checkpoint interval 2048, max_tok 2048 -> prefill chunks of at most 2048`. Default
  `--max-num-batched-tokens` = **2048** [S1], and `chunk = min(budget, interval × span)` with
  `--prefill-span` default 1 [S3]. Our lane sets neither → 2048 chunks, exactly the docs' tabled shape.
- **MTP drag (CLAIMED + measured):** docs' measured rows show MTP costs 1–4% of prefill
  (2,722→2,600; 2,635→2,577 at 250 k) [S1]. Small.
- **Power/clocks (OPEN, owner-side only):** the host-tuning note's POWER-CLOCKS chapter is still
  un-closed on this box — "sclk must ramp to 2350 MHz under load — today the boot read the 500–2350 MHz
  range with the card idle; CHECK THE RAMP under a running prefill" [S16]. The card's dense FP8 matrix peak
  is 383 TFLOPS at 300 W TBP [S9]; a lane stuck at low sclk would show exactly our flat ~2.4 k ceiling
  independent of prompt length — which is what §2.3 measures.
- **`wht6` is NOT a prefill tax (CLAIMED, docs):** on the docs' rig the lossy wire is *faster*
  (2,665 → 2,853 at 221 k) [S1], and TP4.md records `--tp-wire exact` everywhere as **−7.6 to −8.3%** [S3].
  So the answer to "does the lossy wire cost prefill" is *no — it buys prefill*, at an output-bits price.

### 2.3 A shape test that discriminates the candidates (MEASURED)

Bucketed cold-token rate (855 done-lines ≥100 k prompts, both pods, ttft ≥1.5 s):

| cold tokens | n | median rate | p90 |
|---|---|---|---|
| 0–5 k | 562 | 1,607 | 1,946 |
| 5–15 k | 146 | 1,755 | 2,053 |
| 15–40 k | 38 | 1,747 | 2,062 |
| 130 k+ | 13 | 1,903 | 1,927 |
| best single by bucket | — | 2,182 (6 k) / 2,251 (20 k) / 2,405 (157 k) / 2,327 (173 k) | — |

The **upper envelope is flat in length** (2.2–2.4 k from 6 k to 173 k cold) whereas the docs' curve falls
1.75× across 24 k→221 k. A compute-limited lane should show the docs' slope. Two readings fit: (i) our
ceiling is set by something length-independent (wire per-chunk sync, clock, or fixed per-step overhead),
or (ii) small-cold samples are contaminated by fixed request cost — note `ttft ≥1.5 s` still admits 2 s
tails. **This is the sharpest open discriminator in the whole round and it is answerable only by a
controlled solo prefill probe** (§8 of the owner ask, §7 R2).

---

## §3 — Q2: what rank 1's Gen3-×4 parking costs, and the host data only the owner can supply

### 3.1 The measured state (and its limits)

Verbatim boot WARN, ppt7l 04:01:47Z (MEASURED via Loki):

> `WARN link-below-max: card 0000:c7:00.0 (rank 1): the PCIe link at 0000:00:03.2 runs 8.0 GT/s x4 of its
> 16.0 GT/s x4 while the card is 31% busy`

- rank 0 chain: `00:02.5 16.0 GT/s x4 (max 16.0 GT/s x4)` → root-port capped at ×4, at its max [S13].
- The card silicon is **PCIe 5.0 ×16** [S9]; the internal bridges read 32.0 GT/s ×16 — the limiter is the
  socket/root-port path, exactly the D44 finding for card 1 ("the fault was the M.2 SOCKET / root-port
  path … a screwdriver") [S16].
- **No runtime link instrument exists** (scout §10, re-confirmed): the read is a boot snapshot at 31%
  busy; whether it persists, renegotiates, or parks lower under sustained load is *not answerable from
  metrics* — and host-tuning's own law is that idle parks links (reads must be **under load**) [S16].

### 3.2 What it does NOT cost (confirmed, and one correction)

- **KV host↔card traffic: 0 bytes** (MEASURED full life) — the refuted theory stays refuted.
- **Embedding gather: ~0.1–0.2 MB/s at peak** (DERIVED by scout, arithmetic sound) — negligible.
- **Model load: disk-bound** — boot print `18.04 GiB read in 4.7 s (4.1 GB/s) … 3.8 s of that was the
  disk (5.1 GB/s)` (MEASURED) — the wire was never the boot bottleneck.

**Correction to the scout's verdict:** its §8 conclusion was *"every PCIe candidate is 1–2 orders of
magnitude too small to produce the observed prefill cost"*. That statement was demonstrated for
KV-stream, embedding and tier bytes; it was **never evaluated for the TP collectives**, and the engine's
own documentation contradicts it for exactly the case at hand:

> *"In the two-shot rank r reduces shard r of the message, and **every rank's link carries at least the
> whole message each way** whatever its shard, so **the slowest link sets the time of every prefill
> all-reduce**."* [S1, §4.7 "Cards on unequal links"]

### 3.3 What it plausibly DOES cost (DERIVED — upper bound, falsifiable)

Per 2048-token chunk, assuming 2 all-reduces/layer over the hidden vector (5,120 × 2 B bf16 = 10.24 KB
per collective per token), 64 layers, no fusion, no overlap:

```
exact wire : 2048 × 10.24 KB × 2 × 64 = 2.68 GB per chunk
wht6 (6-bit, ×0.375) two-shot (×1.5)  = 1.51 GB per chunk
chunk compute at the docs-class rate   = 2048 / 2880 t/s ≈ 711 ms
```

| link | exact-wire collective time | wht6 collective time | as % of chunk compute |
|---|---|---|---|
| Gen5 ×16 (docs rig, ~60 GB/s line rate [S3]) | 43 ms | 24 ms | 6% / 3% |
| Gen4 ×4 (rank 0 here, 7.88 GB/s raw [S16]) | 341 ms | 192 ms | 48% / 27% |
| **Gen3 ×4 (rank 1 here, 3.94 GB/s raw)** | **681 ms** | **383 ms** | **96% / 54%** |

Two consequences:

1. **At the exact wire, a Gen3-×4 leg is a prefill wall** (collectives ≈ compute). Our lane runs `wht6`,
   which moves the wall to ~54% of compute time — survivable *only* if the engine overlaps it. TP4.md
   shows the overlap machinery is real and that at **two ranks** the dense pipelined prefill path is
   enabled (`g.world == 2`) [S3]; it also shows a *missing* link-hold release costs 3.7% at c8 on four
   ranks. So the exposed fraction is unknown here — this is an upper bound, not a verdict.
2. **This explains why `wht6` is load-bearing rather than merely accurate-cheap on our rig**, and why a
   further park (Gen2/Gen1 under a marginal channel — the same LTSSM margin class our own §R10/R13 chased
   [S16]) would hit prefill hard, not just model load. The scout's dismissal inverted the risk.

**Host→device staging that the narrow leg definitely carries:** checkpoint-slot restore writes (docs:
"Snapshots never take VRAM: each is copied to host memory"; host-side slots are engine-default), prefix
tier restores — *"One host slot holds the whole engine's entry: each rank's shard of every cached group,
end to end … rank 0 writes it and every rank reads it back on a restore"* [S1] — so **a tier restore puts
rank 1's shard across its own narrow link**, and the docs carry **no byte counter** for tier copies
(scout §10). Boot print sizes the pieces: 80 slots × 153.38 MiB (11.98 GiB host), prefix tier 4.00 GiB
(131,072 tokens), embedding 1.18 GiB/rank "read over the link in place" (all MEASURED).

### 3.4 Exactly what the owner must run (no metric can substitute)

Read-only, under a sustained solo cold prefill (≥150 k prompt, so the collectives are saturated), per
host-tuning's standing rule that a rung scores only when BOTH ends and the kernel agree [S16]:

1. `sudo lspci -vvv -s 0000:00:03.2 | grep -E 'LnkCap:|LnkSta:|LnkCtl2|TargetSpeed|Phy16Sta'`
   and the same for `00:00:02.5` (rank 0's port) — speed/width, instructed target, and Gen4 EQ state
   under load, per port.
2. `cat /sys/bus/pci/devices/0000:c7:00.0/current_speed /sys/bus/pci/devices/0000:c7:00.0/current_width`
   and `…/c3:00.0/…` — per-card, sampled *during* the prefill, not at rest.
3. `sudo journalctl -k -b | grep -i 'available PCIe bandwidth'` +
   `sudo dmesg | grep -iE 'GT/s|link training|downgraded'` — the kernel's second witness.
4. `sudo lspci -vv -d 1002:7551 | grep 'Region 0'` → **must read `size=32G` on BOTH cards**: ReBAR is a
   *P2P prerequisite* in the engine's own rig doc ("peer access needs the large BAR") [S5]; an unequal BAR
   would explain an asymmetric path that Gen3-parking merely reports.
5. `rocm-bandwidth-test` card↔card (install via AUR per [S5]) — the single missing number that prices
   §3.3: measured P2P GB/s for the c3↔c7 pair on this root complex, plus `zcat /proc/config.gz |
   grep -E 'HSA_AMD_P2P|PCI_P2PDMA'` (both `=y`).
6. `GET /diagnostics` on the lane **during that same prefill** — the live link block, owner-exec route
   only (AGENTS MCP law: no pod exec for agents) [S16].
7. Clock/power ramp in the same window: `rocm-smi --showclocks --showpower` /
   `cat /sys/class/drm/card*/device/gpu_busy_percent` — closes POWER-CLOCKS (§10) and tests §2.3's flat
   ceiling.
8. `lspci -tvv` + `readlink -f /sys/class/nvme/nvme0/device` — does rank 1's card share a root port with
   the NVMe (the D44 confounder class, §R12 closed it for card 1)?

**Hardware hypothesis to state plainly:** rank 1's parking is the *same failure family* D44 closed on
card 1 by moving the M.2→OCuLink adapter to the other socket. The prior fix cost a screwdriver, not
software. If item 1 prints `Target Link Speed: 16GT/s` with `LnkSta: 8GT/s x4`, the BIOS-pin branch is
already dead by precedent [S16] and the socket/cable path is the suspect.

---

## §4 — Q3: the concurrency math, honestly

### 4.1 The pool, fully decomposed (MEASURED boot lines, exact)

```
claimable 30.73 GiB/card; static weights 8.50; headroom 96 MiB; step staging 136.26 MiB; settled 246.36 MiB free
elastic (the cache's share) ......... 22.24 GiB/card
  kv_attn  full 16 layers, block 16 tok, page 256.00 KiB, 85,952 blocks = 20.98 GiB (1,375,232 tokens)
  per-sequence state .................  1.16 GiB ("nothing is lent: it is all the cache's")
  kv_draft windowed 5 layers, block 16, page 80.00 KiB, 1,168 blocks = 0.09 GiB (18,688 tokens)
  ---------------------------------------------------------------  sum = 22.23 ≈ printed 22.24 ✓
```

- Per token: **16 KiB/card = 32 KiB/lane**, trunk-only, matching the config-derived 32,768 B
  (16 × 4 × 256 × 2 × 1 B) exactly. **V3's "~64 KiB effective (drafter 2×)" is refuted, and the reason is
  now mechanical:** the drafter's cache is a *windowed* 1,168-block plane (129 blocks ≈ 2,064 tokens per
  sequence, "not cached" [MEASURED boot]), so it does not scale with context and cannot be a per-token 2×.
- Per full session: 262,144 × 16 KiB = **4.0 GiB/card** + 148 MiB state = **4.145 GiB** →
  22.24 / 4.145 = **5.37** ✓ the printed "5.3 full-length sessions"; worst case 8 × 4.145 = 33.2 GiB vs
  22.24 → **67%** ✓ the printed "66%".
- The scout's "32 KiB/token trunk" is therefore **confirmed and completed**: the missing 8% of the pool is
  state + draft window, not a hidden cache multiplier.

### 4.2 Does a 66%-funded pool degrade throughput, admission, or both? (MEASURED + docs)

**Neither refusal nor truncation — the degradation ladder is throughput first.** Docs, verbatim:
- *"The dim segment is prefix cache, finished turns kept for reuse, **which gives way the moment a live
  request needs it** … **a full pool causes preemption**"* [S2, OPS];
- `--preempt-wait-ms` default 5000: *"how long a preempted prefill may wait for its whole-recompute gate
  before **reclaiming cache blocks and preempting lowest-priority running requests** until one overdue
  request can prefill"* [S1];
- pool buffer = *"one prefill chunk, or the largest shortfall admission met in the last few seconds"*
  [S2] — i.e. admission shortfall is absorbed by the elastic buffer before anything is refused.

What actually happened over the whole life (MEASURED): `kv_cache_usage_perc` **max 1.0000**, p50 0.24
across the life (0.82 in-window); `num_requests_running` max **7**, p50 0–1; `num_requests_waiting` max 1;
`http_admission_rejected_total` +0; **`vllm:num_preemptions_total` / `preempt_forced_total` /
`num_requests_preempted` / `engine_steps_held_total` all 0**; `finish=length` 1 lifetime. So the pool
*did* reach saturation and the lane absorbed it with eviction/recompute (138,480 evictions;
2,186,144 hit-cut tokens), never with refusal or preemption. **The 66% number is addressed, not met.**

### 4.3 What "worst case" means for Radiance's pool, per the engine docs at v1.17.0

- *"max-model-len reserves nothing per request; it is the worst case the pool is sized against"* [S1] —
  so the 8 × 262,144 figure is a **sizing convention, not a reservation**, and `M` in `pool backs N% … M
  full-length sessions` is explicitly *"counts only the part of the pool that holds context; compare M with
  the sessions you expect to keep live"* [S1]. **The docs' own advice is to compare M to expected
  concurrency, not to demand M = max-num-seqs.**
- The engine's published capacity statement for this exact model: *"The 27B in FP8 holds **2.8
  full-length sessions at 32**"* [S1] — i.e. at the engine's default `--max-num-seqs 256`/doc-recommended
  32, *under-funding full-length concurrency is the model's documented nature on 2×32 GB*, not a defect of
  our raise. Our lane is better-proportioned than the docs row because seqs is FORM-fixed at 8.
- Recurrent state and block tables are per-sequence regardless of occupancy [S1, "Many sequences"], and
  *"with speculation"* the delta-net state is held in **two copies** — which is why per-seq state is
  148 MiB/card (DERIVED: 48 layers × 48 heads × 128 × 128 × 2 B ≈ 75.6 MB × 2 copies ≈ 151 MB ≈ the
  printed 1.16 GiB/8 ✓; the same class as the 153.38 MiB checkpoint slot).

### 4.4 Testing the scout's "scheduler artifact rather than physics" claim (Q3's asked test)

**Verdict: half-adopt.** Confirmed: the *sub-ceiling* spread is scheduler-made (capped-event density
tracks rate: 0 → 2,327; 61–103 → 620–1,004). Refuted as a total explanation: the ceiling itself (2.4 k
solo) is a rig-class number that a scheduler change cannot lift, and the docs' shape (2,880) sits 20%
above it. So recommendations must not stop at "it's only interleaving" — see §7 (R1, R3, R4 ranked
independently).

### 4.5 Which setting is correct — the three-way choice the brief asked about

| Option | Funding math | Verdict |
|---|---|---|
| Reduce `--max-num-seqs` 8 → 5 | 5 × 4.145 = 20.7 GiB ≤ 22.24 → 100% funded | **Rejected as an agent recommendation.** FORM-fixed across all four lanes [S17]; D6 ruled it needs its own ruling *because* lowering it "would invalidate the very receipt this ticket exists to capture". It also forfeits the 94.8% hit-rate regime (fewer live sessions = more cold re-prefill per turn) |
| Lower served context | — | **Banned by the brief's constraint** and by D1; the admissions prove the raise pays (11 of 12 refusals retired, MEASURED) |
| Accept 66%, rely on the hit pattern | measured: saturation absorbed by eviction, 0 preemptions at 7 running | **Correct today — but name it as a purchase, and buy the margin back with the dtype lever** (R4) rather than with seqs. The risk is not today's p50 = 1; it is an 8-session burst, whose documented cost is preemption + *whole-recompute* of the victim |

**The arithmetic-vs-ruling item, named rather than smoothed:** the lane was provisioned by D1 + D6 to serve
8 × 262,144 on 2 × 30.73 GiB claimable, which needs 33.2 GiB/card. **No knob inside the constraint set
(mems held, seqs fixed, context ≥200 K) makes that 100% at fp8.** The 66% is not a measurement error,
not V3's pessimism, and not the scout's discovery — it is the ruling's price, first printed by our own
boot receipt. What *is* fixable inside the rules is the size of the bill: `k6_v4` moves 5.3 → ~7.7
sessions (DERIVED, §6.2), i.e. 96% funded; `fp8_v4` → ~6.8 (85%). Anything beyond that is a memory or
seqs ruling, which is owner-owned by D7/D10/D6.

---

## §5 — Q4: is a 4,096 MiB prefix tier a useful tier or a churn generator?

### 5.1 What the tier is for, per the docs at the pin (CLAIMED, v1.17.0)

*"A conversation larger than the tier keeps its start there and is prefilled again past it once VRAM gives
the rest up; the startup log warns when the tier holds less than one `--max-model-len` conversation and
says how many MiB would, and a `kv tiers: … got no host copy` line appears when it happens (`/sessions`
`moved.held_back`). … It holds attention blocks only; a hybrid model's linear-state snapshots are already
in host memory, in the `--checkpoint-slots` store"* [S1].
*"Every stored conversation expires: one unused for `--prefix-cache-ttl` seconds is removed from whichever
tier holds it"* [S1].

So the tier's job in this workload is **cross-turn and cross-session resume of the conversation start**,
and partial retention is the designed posture — our own lane comment says the same: *"partial retention IS
the config"* [S17].

### 5.2 Is it churning? (MEASURED — and this corrects the scout's emphasis)

Lifetime counters, ppt7l [S12]:

| counter | value | reading |
|---|---|---|
| `prefix_cache_expired_total` | 161,413 | designed TTL/retention removals |
| `prefix_cache_evictions_total` | 138,480 | VRAM-side pool pressure removals |
| `prefix_cache_ckpt_evictions_total` | 2,945 | slot-store removals |
| `…_ckpt_evictions_by_reason{reason="retention"}` | **2,871** | 97.5% |
| `…_ckpt_evictions_by_reason{reason="store_full"}` | **74** | 2.5% |
| `prefix_hit_cuts{reason="resumed_below" / "no_snapshot" / "windowed_group" / "adopt_failed"}` | 303 / 7 / 0 / 0 | hits cut short |
| `prefix_hit_cut_tokens_total` | **2,186,144** | **28.0% of the 7,819,024 lifetime computed tokens** |
| `draft_refills_total` × 2,048 = `draft_refill_tokens_total` | 175 × 2,048 = 358,400 | 4.6% of computed |

**Findings:**
1. **"Tier full" is a minor cause, not the engine of churn.** The log lines the scout highlighted
   (27 × `got no host copy`, 47 × `256 entries erased with no copy off the card` ≈ 12 K entries) are real,
   but the reason census says store_full accounts for 2.5% of slot evictions; the bulk is retention/TTL —
   *the cache working as designed.* The scout's "tier churn forcing re-prefills" over-weights it.
2. **The big measurable loss is the hit-cut: 28% of all prefill compute in the pod's life was tokens
   below a shortened prefix hit** (MEASURED; semantics DERIVED from the label set). The mechanism is
   documented, and it is **not the tier's fault**: for a model with linear state, *"after a prefix hit
   [the drafter] could not draft until its window had slid past the hit"* [S1] — hence our boot line
   `draft refill: a prefix hit ends 2048 tokens before the prompt's end, so the drafter's window is
   recomputed` (MEASURED) — plus block alignment (16-token pages) and the resume-point policy. Measured
   median cold per hit-turn = **3,464 tokens ≈ 2,048 (drafter window) + ~1,400 (new turn)** (DERIVED from
   the done-lines, MEASURED inputs).
3. **A bigger tier would not buy the 28% back.** It buys only the `store_full` slice and demotion capacity.
   Raising it to "hold one 262,144 conversation" (the boot's own `8193 MiB would hold one`) is
   **bounded by the held 24 Gi, by measurement**: printed pinned legs 11.98 (slots) + 2.36 (embeddings)
   = 14.34; tier 4.00 → working-set peak **19.73 GiB** (MEASURED). A 8 GiB tier puts the peak at ~23.7 of
   24 GiB — inside 1.2% of the limit, and the engine's host-side rule (`limit − printed-pinned ≥ 4`,
   repo law [S16]) plus the demotion-pinned-burst class in our notes [S16][S18] is precisely the Wilde OOM
   shape. **So: the tier is not free to double; the memory number is the wall, and it is print-gated.**

### 5.3 Answer to Q4

The 4 GiB tier is **useful, under-sized by design, and not the main loss source.** Do not raise it
(agent-side); the two things that actually attack the 28% hit-cut tax are (i) the drafter-window refill
mechanism, which is only reducible by changing speculation depth/block policy (see §6.5 — the price is
decode), and (ii) `--checkpoint-interval`/`--checkpoint-policy`, which set where resumes can land
(env-settable today: `RADIANCE_CHECKPOINT_INTERVAL` exists in the FORM [S17]; the policy flag does not).
Open question, not answerable from here: whether `resumed_below` is bounded by the drafter window
(2,048) or by the checkpoint-interval — our 7,215 tokens per cut average is well above 2,048, so
something else also cuts, and the docs don't price it.

---

## §6 — Q5: Radiance-specific knobs for this architecture at v1.17.0, with fork caveats

### 6.1 Chunked prefill family (all documented at [S1])

| flag | default | what it does | settable per lane today? |
|---|---|---|---|
| `--max-num-batched-tokens` | **2048** | largest token count one step may carry | **YES** — `RADIANCE_MAX_NUM_BATCHED_TOKENS` |
| `--checkpoint-interval` | 2048 | caps the chunk *before* the budget: `chunk = min(budget, interval×span)` [S3] | **YES** — `RADIANCE_CHECKPOINT_INTERVAL` |
| `--prefill-span` | 1 | a *lone* prefill carries N intervals/step; every other step is planned at `budget − extra intervals`, "so a long prompt (a minute or more at 256K) does not starve decode rows" | **NO** — not in the FORM env list → chart edit, all lanes |
| `--busy-prefill-chunk` | auto | shared-step chunk policy (`off` takes the whole step, `N` holds to N) | **NO** — FORM edit |
| `--prefill-interleave` | 0 (off) | decode-only steps after each prefill chunk, ≤64 | **NO** |
| `--preempt-wait-ms` | 5000 | the recompute/preempt ladder at pool exhaustion | **NO** |
| `--attn-prefill-fp8` | **off** ("It is lossy, so the default is `off`") | e4m3 QKᵀ/PV over the cache: measured 221 k prompt **2,665 → 3,210** (+20%), 24 k 4,655 → 4,835; combines with `wht6`; KL 0.058, top-1 96.0%; **tool-calling/SWE transcripts move most, 0.17–0.27 KL at 91–93% top-1** | **NO** — FORM edit |

**The trap the docs name and our lane is one flag away from falling into:** *"asking for 4096 runs
2048-token chunks with an activation arena sized for 4096"* [S1]. Our receipt prints
`activation arena 549.88 MiB … charged to the VRAM budget before it was split` and
`not lent — the 'qwen35_fp8' plugin does not declare at a smaller step size`. So raising
`--max-num-batched-tokens` **alone** costs arena GiB-for-GiB out of the KV pool and buys nothing, because
`chunk = min(budget, interval × span)` — the *pair* (interval or span) is the lever. Quantified: arena at
budget 2048 is 549.88 MiB/card ≈ 0.13 sessions; doubling the arena without raising the chunk would drop
funding 5.3 → ~5.2 for zero speed.

### 6.2 KV layout / residency (the funding lever)

- `--kv-cache-dtype fp8` is **FORM-fixed in the chart** at `fp8` [S17]; the docs offer, for this exact
  model: *"`fp8_v4` and `k6_v4` narrow the trunk's attention cache… A token then costs **25/32 or 22/32**
  of what fp8 costs, and a drafter's cache stays fp8. libr4d has their kernels for Qwen3.8-27B's attention
  (head_dim 256, gqa 6) … the server refuses them, naming the plugin, anywhere else"* [S1].
- **Funding math (DERIVED from the measured budget):** 16 KiB/token/card × 22/32 = 11 KiB → per session
  2.75 GiB + 0.145 state → 22.24/2.895 = **7.67 sessions** (≈96% of the 8-worst case); `fp8_v4` → **6.8**
  (≈85%). Cross-check against the dated upstream table (fp8 518,800 / fp8_v4 664,400 / k6_v4 755,184
  tokens): ratios 1.28 and 1.4545 — **exactly 32/25 and 32/22**. The live v1.17.0 guide no longer prints
  that table (V5's finding) but now *derives* it from the ratio law, which corroborates it independently.
- **Speed bonus, measured on the docs' rig:** `fp8_v4` takes 221 k prefill **2,666 → 3,097** (+12%) and
  24 k 4,636 → 4,778 [S1] — less cache traffic per attention step.
- **Price:** "a real quantisation that changes the output slightly"; V/K at int4/int6. Our workload is
  tool-calling transcripts — the docs' *worst-moving* category.
- Not applicable: `--kv-resident` (dense "cannot stream", ignored with a warning), `--placement`,
  `--host-pool-mib` for experts. **Caveat on a scout-suggested rescue:** the boot's own tail
  *"a larger `--host-pool-mib` gives the cache more"* only helps by moving *weights* off-card, which puts
  per-step weight reads on the narrow link — on this rig that trades the funding problem for a bandwidth
  problem. Do not treat it as a dense-lane funding lever.
- `--gpu-headroom-mib` (96 default): do **not** shave. Docs: headroom exists for *"a kernel's code object,
  which HIP loads at the kernel's first launch … With too little left, the first kernel that has never run
  (**a draft head's**, a sampler chain's) fails its load and faults inside the HIP runtime: a segfault in a
  correct kernel on a server that had been serving"* [S1]. Upstream issue #594 is open on 2.2.0:
  *"card-headroom-mib does not reserve VRAM"* [S7] — fork-side reason enough not to tune it blind.

### 6.3 Speculation / drafter knobs (docs [S1])

| flag | default | measured effect (docs, Qwen3.8-27B MXFP4 + DFlash2, 2×R9700, `k6_v4`, depth 7) |
|---|---|---|
| `--num-speculative-tokens` | auto (here **7**) | *"0 disables"*; docs' MTP rows: decode 39.89 → 62.3–64.8 t/s; prefill −1 to −4% |
| `--draft-short-from N` | auto: *"never switches a chain and switches a tree drafter from 2"*; DFlash2 on `qwen35_fp8` *"declares a block of 4 (3 drafts)"* | aggregate tok/s, unset → `8`: 8 streams **652.8 → 696.8** (+6.7%), 16 **751.9 → 945.6** (+26%), 32 +8.6%, 64 +26.5% |
| `--draft-window` | `fixed` | `adaptive` *"follows each sequence's acceptance and the measured step cost"* — for prose that "falls off after a position or two" |
| per-position acceptance (MEASURED here) | — | 0.700, 0.684, 0.687, 0.704, 0.720, 0.748, 0.772 → **rising with depth**; deep drafting is paying on this traffic |

**This is the highest-value unclaimed pair in the round**: a documented, model-declared short block with a
measured +6.7% at exactly our observed concurrency (5–7 streams), priced at nothing but output bits at a
near-tie (the docs warn a different verify shape "is a different batch shape… a different token" at ties).
It needs `RADIANCE_DRAFT_SHORT_FROM`, which does not exist in the FORM [S17] → chart edit, all lanes.

### 6.4 Fork-vs-upstream caveats (explicit, because this misled the investigation once)

1. **Radiance ≠ the `magiccodingman/vllm-radiance` fork, ≠ Strata, ≠ upstream vLLM** — the repo's own
   three-way naming law [S16 §13]. Upstream vLLM keeps `enable_chunked_prefill` and
   `max_num_batched_tokens` as *auto-derived scheduler* settings [S11]; Radiance's 2048 default, its
   `min(budget, interval×span)` chunk law, its `busy-prefill-chunk` "leave decode its room" policy, and
   its `pool backs N%` receipt line **have no upstream equivalent**. Any intuition imported from vLLM
   tuning posts is out of scope for this lane — including the RCCL/hipIpc crash class (radiance uses no
   RCCL [S16]).
2. **Radiance 1.17.0 ≠ Radiance main (2.2.0).** Our pin is `stilldeadcode/radiance:1.17.0` [S17].
   Issue #457 (open): *"v2.0.0 on one R9700 (Qwen3.8-27B + MTP): 30% less throughput than 1.17.0 and a
   decode step about 2× longer"* [S7]. Docs fetched at `main` (TP4.md, README profiles, rig doc) are
   therefore **evidence about a different build**; GUIDE/OPS/DEVLOG claims used above were fetched at the
   pinned tag. The README's own published profiles (main) use `kv-cache-dtype: i8` and explicit
   `num-speculative-tokens: 3` / `max-num-batched-tokens: 2048` [S4] — *not* our FORM's `fp8` — so even
   the "vendor recommendation" is version-shifted.
3. **Creator-rig numbers are not this-rig numbers.** Docs tables are Gen5 x8/x16, 215–300 W, X670E;
   ours is Strix with two x4 OCuLink-class paths, one of them parked [S5][S16]. The docs' own hygiene rule,
   quoted from Wilde via our §R19-D: *"quoting a throughput number without its context length and headcount
   is meaningless"* [S15]; and upstream issue #603 is literally titled *"can't replicate your decode
   numbers"* [S7].
4. **Undocumented gauge semantics**: `radiance:prefill_tokens_per_second` / `decode_tokens_per_second`
   [S13 §10]; `step_ns_decode_best/recent` are a *32-step single-row window floor* whose estimator history
   is a chain of refuted premises [S6] — use them for shape, never as a target.

---

## §6.5 — Q6: should MTP be turned off, and does it apply to this lane at all?

### 6.5.1 It applies — the two repo artifacts that said otherwise are being misread

**The owner's two undercuttings, resolved from the docs rather than the config:**

1. *The q27 comment at `values.yaml:1373`* — *"no RADIANCE_NUM_SPECULATIVE_TOKENS (the z-lab DFlash2
   drafter is compiled into the .rad — '**the flag simply doesn't own the drafter**', §R19-Q5, and
   `--draft-model` is a parse error)"*. Read against the pin's docs, that sentence is **true about which
   weights exist and false about whether drafting runs**. v1.17.0 states:
   `| --num-speculative-tokens N | auto | speculative window; **0 disables**. The ceiling under
   --draft-window adaptive |` and, with worked examples:
   `radiance --model m.rad # auto: the drafter's own operating point` /
   `radiance --model m.rad --num-speculative-tokens 0 # off` [S1].
   What the flag "doesn't own" is the *drafter model selection* (`--draft-model` is a parse error; the head
   is in-pack). **"Absent env" = "auto" = "the depth the drafter states as its operating point", which our
   boot print says is 7 — not off.** (MEASURED: `I speculation: depth 7, this drafter's own operating point
   (--num-speculative-tokens N overrides it)`; `I speculation: 'dflash2' proposes 7 token(s) in ONE block
   pass over 8 row(s) (mask id 248070, window 2048); prompt lookup fills in for any sequence it declines`.)
2. *The 32-vs-64 KiB tension.* It dissolves: the drafter is resident and active, but its cache is
   **windowed and fixed**, not proportional to context — `kv_draft window 5 layers block 16 tok page
   80.00 KiB 1168 blocks = 91.25 MiB (18688 tokens)` and `group 'kv_draft' is windowed (129 blocks): not
   cached` (MEASURED), and the docs: *"A drafter with a sliding window over its own cache (DFlash2) keeps
   that cache **outside the prefix cache**"* [S1]. So it cannot be the 2× V3 guessed, and it cannot be a
   funding lever of any size. The lane comment's citation of the flag's absence is a *reason*, not an
   off-switch — the correct reading is: drafting is on by default, at depth 7, and only `0` turns it off.

**Corroborating that drafting really is running on this lane (MEASURED, lifetime):**
`draft_tokens_total` 2,577,323 · `draft_accepted_total` 783,696 · ratio 0.304 · per-position conditional
0.700→0.772 · `decode_rows_unspeculated_total` 545 (≈0.2% of rows) · generation tokens per decode step in
the run **4.95**.

### 6.5.2 Can it be disabled on each model — pack-native or flag?

- **Both packs:** `--num-speculative-tokens 0` is the documented off, honored even with an in-pack head
  (docs examples use a generic `m.rad`; the upstream README profile for the *27B bf16/IQ8R* rows simply
  omits the flag, and the *Flash-Next bf16* row sets `num-speculative-tokens: 0` explicitly [S4] — so 0 is
  a shipped, supported value for these families). Zeroing it does **not** change which weights load; it
  changes which pass shape runs. Two caveats: (i) with the head off, *"prompt lookup still drafts for every
  sequence a declared head declines"* — but our boot print says `--ngram-placement n/a` ("this model has no
  n-gram table"), so on q27 `0` should mean no drafting at all; verify the boot line after the change.
  (ii) per-lane it is env-clean today: `RADIANCE_NUM_SPECULATIVE_TOKENS` already exists in the FORM [S17],
  so `"0"` on the 27b lane is a **values-only edit, no chart change, no blast radius**. That makes it a
  cheap experiment — and the reason to be careful about recommending it is the price, below.

### 6.5.3 What it costs when active, quantified against the 66% pool (DERIVED from MEASURED)

Pool share (per card): `kv_draft` 0.09 GiB (fixed) + recurrent-state doubling ≤ 0.58 GiB (the docs' "two
copies with speculation" [S1]; measured state total 1.16 GiB/8 seqs = 148 MiB/seq ≈ 2 × 75.6 MB).
→ **Maximum recoverable by `--num-speculative-tokens 0` ≈ 0.67 GiB/card = 3.0% of the 22.24 GiB elastic
share = +0.16 fundable full-length sessions: 5.3 → ~5.5.** It does **not** reach 8; nothing that only
removes the drafter can.

What it buys when on (docs measured, [S1]): decode **39.89 → 62.3–64.8 t/s** (single-stream, Flash-Next
rig); our lane's own analogue: step floor `decode_step_seconds_best` **20.19 ms** / `recent` 25.17 ms
(≈ 40–50 steps/s), measured **4.95 generated tokens per decode step**, per-request 99–143–159 t/s. With
drafting off, tokens/step → 1, i.e. **per-request decode lands at roughly 40–50 t/s** — a ~60% regression —
while prefill *gains* 1–4%. `--gpu-headroom-mib` must stay 96 regardless: the docs name *"a draft head's"*
first-launch kernel load as precisely what the headroom protects [S1], so shaving headroom to reclaim
0.09 GiB is the documented segfault class, not a saving.

### 6.5.4 Low acceptance on a memory-starved lane: self-reinforcing? And its signature

**Assessment: not self-reinforcing here, and the measured numbers say so.** Acceptance on this lane is
*high and rising with depth* (0.700→0.772), and `windowed_group`/`adopt_failed` hit-cuts are **0** — i.e.
no measured mechanism by which pool pressure degrades drafting. The one documented coupling runs the other
way: pool pressure → eviction → **hit cuts** → per-turn recompute of the drafter window
(`draft_refill_tokens_total` 358,400, MEASURED), which costs prefill, not acceptance.

The discriminator table, so the next session does not guess:

| Signature | Speculation drag (depth/block mis-set) | Pool starvation (funding) |
|---|---|---|
| `decode_rows_unspeculated_total` | rises (sequences dropped out of drafting) | flat |
| per-position acceptance | falls off early (position 1 ≫ position 3+) | unchanged |
| tok/step | → toward 1 | unchanged |
| `engine_steps_held_total`, `num_preemptions_total`, `preempt_forced_total` | flat 0 | **rise** (docs: a full pool causes preemption) |
| `prefix_cache_evictions_total`, `prefix_hit_cut_tokens_total` | flat | **rise** |
| `decode_step_seconds_recent/best` ratio | step time grows **with rows at fixed acceptance** | step time grows **when a prefill/checkpoint interposes** [S6] |

Today's record reads **pool-starvation-side counters rising, speculation-side counters healthy** — the
opposite of the "low acceptance on a starved lane" hypothesis.

### 6.5.5 Q6 verdict (§7 carries the recommendation)

**REFUTED as a fix for this lane** — not because MTP is inactive (it is very active), but because the
problem MTP-off is meant to solve (pool funding) moves by **3%**, while the thing it destroys (decode)
moves by ~60%. **SUPPORTED** as a *flash-lane* question at `depth 3` (upstream ships `3` there;
`--draft-short-from` is the concurrency-shaped variant with measured +6.7% @8 streams and +26% @16).
**Not determinable from available data:** whether `--num-speculative-tokens 0` on q27 leaves prompt-lookup
drafting active (boot says no n-gram table; docs' sentence is about declared heads) — one boot receipt
settles it. **The one measurement that decides it:** a same-boot A/B of the fixed ≥2,000-token decode
probe (host-tuning §15 protocol [S16]) at depth 7 vs 0, reading `generation_tokens_total /
engine_steps_decode_total` and the pool `cache can grow to` line — the first number prices the loss, the
second prices the (tiny) gain.

---

## §7 — Recommendations, ranked by confidence then blast radius

Each states: the **measured fact** supporting it, the **falsifier**, and **blast radius**.
Order = (confidence desc., then radius asc.). None touches held memory; none drops served context below
200 K; no `--max-num-seqs` change is proposed as an agent action.

**R1 — Close POWER-CLOCKS and take a controlled solo-prefill probe before buying any software lever.**
*Blast radius: none (owner read-only + one probe request). Confidence: high (P1+P2 agree).*
Supporting measured fact: §2.3's **flat upper envelope** (2,405 at 173 k cold; 2,182 at 6 k) — a lane
compute-limited at full clocks should show the docs' 1.75× length slope, not a plateau; and the
POWER-CLOCKS chapter is explicitly open with the boot reading "500–2350 MHz, card idle" [S16][S9].
Falsified if: sclk reads ~2,350 MHz during a 150 k prefill **and** the length slope appears in the probe
(then the flatness is a measurement artifact and R2/R3 carry the weight).

**R2 — Owner-run the §3.4 host block, and A/B `--tp-wire exact` for one boot on a solo 150 k prefill.**
*Blast radius: boot-level, no permanent change (TP_WIRE is a per-lane env today [S17]). Confidence: medium.*
Supporting measured fact: the verbatim WARN `… runs 8.0 GT/s x4 of its 16.0 GT/s x4 while the card is 31%
busy` [MEASURED]; DERIVED §3.3 puts exact-wire collectives at 96% of chunk compute on a Gen3-×4 leg; the
docs' slowest-link law [S1].
Falsified if: `rocm-bandwidth-test` shows the pair at ≥ 7 GB/s (the Gen3 print was transient/parked-at-idle)
**or** the exact-wire boot shows no prefill change (then collectives are fully overlapped and the leg is
cosmetic for prefill). **This is the only experiment that separates P1 from P2.**

**R3 — Adopt `--draft-short-from` (or `--draft-window adaptive`) rather than `--num-speculative-tokens 0`
for the 5–7-concurrency regime.** *Blast radius: chart FORM edit (new env name) → all four lanes, needs a
ruling. Confidence: medium-high, and docs-measured.*
Supporting measured fact: our observed `num_requests_running` max 7 / p95 6, acceptance 0.304 with
per-position 0.70→0.77, and docs' Qwen3.8-27B-on-two-R9700 table **652.8 → 696.8 @8 streams, 751.9 → 945.6
@16** [S1]; DFlash2 on `qwen35_fp8` *declares* the short block (block 4 / 3 drafts), so the flag has
territory here.
Falsified if: our `auto` default already switched (the startup print would say
`speculation: from N decoding sequences on, 'dflash2' runs its short block…` — **grep that line on the next
boot; if it is already active, R3 is void**; if it warns "serial head / declares no shorter block", R3 is
also void).

**R4 — Rule on `--kv-cache-dtype` ∈ {`fp8_v4`, `k6_v4`} for the 27b lanes.** *Blast radius: HIGH — FORM-fixed
value [S17], so a chart edit touching all four lanes, plus an output-bits purchase. Confidence: medium-high
on the funding math, medium on the quality acceptance.*
Supporting measured fact: the pool decomposition §4.1 (16 KiB/token/card, `kv_attn` 20.98 GiB, 5.3
sessions, printed 66%) and the docs' ratio law 22/32 · 25/32 with **libr4d kernels explicitly for
Qwen3.8-27B's head_dim-256/gqa-6 attention**, plus a **measured +12% long-prompt prefill** at `fp8_v4`
[MEASURED + S1].
Effect (DERIVED): funding 5.3 → **~6.8 (`fp8_v4`) / ~7.7 (`k6_v4`)** sessions — i.e. the only in-rule lever
that materially closes the 66% gap without moving memory or seqs.
Falsified if: (a) an accuracy eval on *our* traffic (tool-calling transcripts — the docs' worst-movers,
0.17–0.27 KL at 91–93% top-1) is unacceptable to the owner; (b) the boot's `pool backs N%` does not move as
predicted (would mean the drafter/host-tier planes don't scale the way §4.1 assumes).

**R5 — Do not "fix" the 66% by reducing concurrency; make `M ≥ configured seqs` a *decision*, not a
silent acceptance.** *Blast radius: none now; the ruling itself is chart-wide. Confidence: high.*
Supporting measured fact: saturation reached 1.0000 with **0 preemptions / 0 refusals / waiting ≤1**;
docs' own capacity statement *"the 27B in FP8 holds 2.8 full-length sessions at 32"* [S1]; D15-F2/D16
already made the gate parse `M` per lane and surface `N% < 100` as an owner-read warning.
Falsified if: a sustained 8×≥250 k burst is ever run and produces preemption or `engine_steps_held` — that
converts the deficit from latent to active, and then seqs/context/dtype must be re-ruled together.

**R6 — Leave the prefix tier at 4096; attack the 28% hit-cut tax via checkpoint policy, not tier size.**
*Blast radius: low (`RADIANCE_CHECKPOINT_INTERVAL` is env-settable today) but NOT recommended to move
blindly. Confidence: medium.*
Supporting measured fact: `prefix_cache_ckpt_evictions_by_reason` = 2,871 retention / **74 store_full**;
`prefix_hit_cut_tokens_total` 2,186,144 = **28%** of computed with `resumed_below` 303 / `windowed_group` 0
[MEASURED]; working-set peak 19.73 of a held 24 Gi (so the tier is memory-bounded, §5.2).
Falsified if: raising `--checkpoint-interval` (coarser snapshots, fewer chunk boundaries) reduces
`prefix_hit_cut_tokens_total` per admitted token — if instead it *raises* recompute, the cut is bound by
the drafter window (2,048) alone and no policy change helps.

**R7 — Explicit MTP verdict (owner's Q6): supported-by-evidence that the proposed fix does not apply to
this lane.** *Blast radius of NOT doing it: zero. Confidence: high.*
Lead-with-it plainly: **`--num-speculative-tokens` is absent, MTP is nonetheless ON at depth 7 (boot
receipt), and turning it off buys ~0.67 GiB/card = +0.16 sessions while costing ~60% of decode.** The
"turn off MTP" ask is *right about the flash lanes* (`depth 3` shipped, upstream ships `i8` + `3`, and the
`--draft-short-from` table is measured there) and *wrong about 27b-TP2*. Delivered to the coordinator as
the answer the flash scout will need from the other side — and note the constraint that the two lanes
share one FORM, so any lane-specific speculation change should be env-shaped, per lane [S17].
Falsified if: the same-boot depth-7-vs-0 A/B shows decode tokens/step barely above 1 with drafting on
(then drafting is dead weight and the arithmetic flips) — our counters say otherwise (4.95 tok/step).

---

## §8 — Explicit non-recommendations, with reasons

1. **Do not raise `--max-num-batched-tokens` alone.** Docs: interval clamps the chunk first —
   *"asking for 4096 runs 2048-token chunks with an activation arena sized for 4096"* [S1]; our arena is
   **not lent** on `qwen35_fp8` (MEASURED) → pure pool loss. Pair it with span/interval or skip it.
2. **Do not reduce `--max-num-seqs` to 5.** FORM-fixed, chart-wide, D6's ruling exists precisely to keep
   this receipt valid; and the deficit it "fixes" has not bitten (R5's evidence).
3. **Do not lower served context below 262,144** (brief constraint + MEASURED: 11 of 12 refusals retired;
   a 247,612-token request completed with `cache 243,712 ttft=2.97s`).
4. **Do not touch 24 Gi / 110 Gi.** No recommendation here pre-empts a print (D7/D10/D28(6)/P11). The tier
   and slot numbers above are all *within* the held envelope; the 8 GiB tier is explicitly NOT proposed
   because it isn't.
5. **Do not shave `--gpu-headroom-mib` to fund sessions** — 0.19 GiB for a documented segfault class
   ("a draft head's … first kernel") [S1], with upstream #594 open on the flag's semantics [S7].
6. **Do not turn MTP off on this lane** (§6.5). Do not turn it off on the flash lanes on *this* ticket's
   authority either — that scout is running, and the flash arithmetic differs (they ship depth 3, the
   `i8` cache, and expert planes that *do* consume the released VRAM).
7. **Do not adopt `--attn-prefill-fp8 both` on the strength of +20% prefill**, at least not before an
   accuracy read: the docs' own worst-movers are tool-calling/SWE (KL 0.17–0.27, 91–93% top-1) [S1] and
   our workload is 669/707 `finish=tool_calls` (MEASURED). It is the single biggest prefill lever on the
   table and the single biggest accuracy purchase; it needs an eval, not a ruling-by-enthusiasm.
8. **Do not buy hardware for this ticket.** The switch-fabric/PEX path in [S16 §2] is a different
   topology than the live one (two separate root ports, P2P direct); the D44 precedent says the last
   fix of this class cost a screwdriver — do that read first (R2), purchase only on its result.
9. **Do not treat the 04:05–05:40 verification burst as a second sample of the owner's run** — the
   concurrency regime differs (d8sj7 ran max 3 concurrent; ppt7l max 7), so capped-event density and
   cold rates are not comparable across pods without the length/scheduler corrections in §2.

---

## §9 — Conflicts left unresolved (real ones, not smoothed)

**C1 — P1 (compute) vs P2 (wire).** P1: the docs' exact→wht6 delta is +7% at 221 k on a *faster* rig; if
the wire mattered, payload÷2.7 should have paid much more — and our own boot shows `wht6` already
selected, so the Gen3 leg is downstream of the binding constraint. P2: the docs' law makes the slowest
link the prefill all-reduce clock and the DERIVED volume on a Gen3-×4 leg is 96% (exact) / 54% (wht6) of
chunk compute — so even "survivable" means little headroom, and the flat envelope (§2.3) is exactly what a
wire- or clock-bound lane looks like. **Unresolved because the discriminating datum (P2P GB/s under load,
and one exact-wire boot) exists only on the host** — R2.

**C2 — P4 (addressed ≠ met) vs P3 (the pool is a hard wall).** P4: lazy allocation, `max-model-len
reserves nothing`, saturation absorbed at 0 preemptions → the 66% is a sizing convention. P3: hit-cut
tokens are already **28% of all compute**, `expired`+`evictions` ≈ 300 k entries in 15 h, and docs say a
full pool ends in preemption — so the deficit is *already* being paid, in recompute, just not in refusals.
**Unresolved:** whether the 28% cut tax would fall if the pool funded 8 (no counter attributes cuts to pool
pressure vs. the drafter window) — the honest statement is *both mechanisms are live and the split is
unmeasured*.

**C3 — P5 (accuracy purchases) vs P1/P3 (the two best levers).** Every fix that actually moves funding or
prefill (`k6_v4`, `attn-prefill-fp8`, `draft-short-from`, `wht6`) is documented to change output bits:
*"Changing it changes the text… this flag is part of the configuration like `--tp`"* [S1]. P5's position:
the lane already spent `wht6` (KL 0.065, top-1 95.7%) without an accuracy receipt, and stacking three more
lossy choices on a tool-calling route is a compounding, unreceipted purchase. **Unresolved and owner-owned.**

**C4 — Docs-version conflict.** TP4.md/README/rig-doc at `main` (2.x) versus our pin 1.17.0, with #457
open claiming a −30% throughput / 2× step regression in 2.0.0 for this model family [S7]. Several numbers
used above (`i8` dtype, span +5–11%, 60 GB/s) are `main`-era. **Unresolved:** they are cited as
directional, never as receipts for the pinned build.

**C5 — Is 2,405 t/s the lane's ceiling or the workload's?** The best cold rates were observed at
*different* prompt sizes on *different* pods (2,405 on the 200 k pod, 2,327 on the 262 k pod) with n=1
each; the aggregate envelope is built from tails of unequal concurrency. A same-boot, same-prompt probe
(R1) is the only thing that turns this into a number anyone should quote.

**C6 — Scout-vs-this-round on `wht6` semantics.** The scout read the WARN as "TP collectives were
bandwidth-reduced by design"; the docs make it *both* a bandwidth reduction and an accuracy event that
"does not compute the same function the exact wire does", and note *"at 8 sequences and depth 3,
Flash-Next's decode steps are above [the lossy threshold]"* [S1] — i.e. our decode steps at depth 7 and
rows 8 are likely lossy-wired too, which nobody has priced for *quality* on this lane. Open.

---

## §S — Sources (all accessed 2026-11-23 unless dated otherwise)

| # | Source | Used for |
|---|---|---|
| S1 | **`docs/GUIDE.md` @ tag `v1.17.0`**, https://codeberg.org/StillDeadcode/radiance/raw/tag/v1.17.0/docs/GUIDE.md (294,533 B) | flag defaults (`max-num-batched-tokens 2048`, `busy-prefill-chunk auto`, `preempt-wait-ms 5000`, `max-num-seqs 256`, `prefill-interleave`); `--num-speculative-tokens` "0 disables"; `--draft-short-from` + Qwen3.8-27B streams table (652.8→696.8 @8); `--attn-prefill-fp8` measured table (2,665/2,853/3,210 @221 k; 4,655 @24 k; `fp8_v4` 2,666→3,097) + "changes the text"; `fp8_v4`/`k6_v4` 25/32·22/32 + libr4d kernels for head_dim 256/gqa 6; `--prefix-cache-mib` tier law + hit-cut/boot warning + host-slot-under-TP + `--prefix-cache-ttl`; "max-model-len reserves nothing"; "pool backs N% … compare M with the sessions you expect"; "Many sequences" (recurrent state "two copies with speculation"; "the 27B in FP8 holds 2.8 full-length sessions at 32"); checkpoint-interval caps chunk; activation arena; headroom/segfault law; §4.7 **unequal-links "slowest link sets the time of every prefill all-reduce"**, exact-wire one/two-shot, mailbox-vs-P2P, DFlash2 sliding window outside the prefix cache |
| S2 | **`docs/OPS.md` @ `v1.17.0`** (265,380 B) | "the dim segment is prefix cache … **a full pool causes preemption**"; "The KV pool is always elastic… buffer (one prefill chunk, or the largest shortfall admission met)"; ReBAR dispatch-arg law ("0.4–1.8%"); startup-report format |
| S3 | `docs/TP4.md` @ **main** (4,297 B) | `prefill-span: 2` = +5–11% pp (interval 2048 + all_vram); `chunk = min(budget, interval × span)`; peer push ~60 GB/s (Gen5 x16 line rate); all-reduce GB/s at M=2048 = 34.5; `tp-wire exact` −7.6…−8.3%; dense pipelined prefill runs at two ranks; every elementwise op ~4–4.6 µs |
| S4 | `README.md` @ **main** (39,010 B) | published per-model profile table (flash `i8` + `num-speculative-tokens: 3` + `max-num-batched-tokens: 2048`; 27B rows; `Flash-Next bf16 … num-speculative-tokens: 0`) |
| S5 | `docs/PREPARING_YOUR_RIG.md` @ **main** (8,235 B) | reference rig X670E + 7950X3D, **"32.0 GT/s PCIe x8 per card"**; `lspci -vv -d 1002:7551 \| grep 'Region 0'` → size=32G ReBAR; `journalctl -k -b \| grep 'available PCIe bandwidth'`; `rocm-bandwidth-test`; `HSA_AMD_P2P`/`PCI_P2PDMA`; "peer access needs the large BAR"; power-cap/undervolt unit |
| S6 | `docs/DEVLOG-decode-floor.md` @ `v1.17.0` | `step_ns_decode_best/recent` = 32-step single-row window; the refuted-premise history → use gauges for shape only |
| S7 | Radiance issues (Codeberg API, main): **#457** open ("v2.0.0 … 30% less throughput than 1.17.0, decode step 2× longer"), **#592** open→corrected ("With a lending cache, `core/mem/vram_budget.cpp` takes the staging out of the cache"), **#594** open ("card-headroom-mib does not reserve VRAM"), **#603** closed ("can't replicate your decode numbers") | version drift, headroom/staging semantics, published-number reproducibility |
| S8 | `https://huggingface.co/Qwen/Qwen3.8-27B/raw/main/config.json` | geometry: hidden 5120, 64 layers (16 full / 48 linear, `full_attention_interval 4`), 24 q-heads, 4 kv-heads, head_dim 256, `attn_output_gate`, `intermediate_size 17408`, `max_position_embeddings 262144`, linear k/v head dims 128 |
| S9 | AMD product page + datasheet PDF + TechPowerUp for Radeon AI PRO R9700 | **PCIe 5.0 x16 bus**, FP8 matrix 383 TFLOPS dense, FP16 matrix 191, INT4 766 TOPS, 32 GB GDDR6 @640 GB/s, 300 W TBP, game clock 2350 MHz |
| S10 | Wilde, *"What a Gen4 board costs…"* (2026-11-08) — **carried via the prior round's 2026-11-22 re-fetch and §R19-Q4 attribution; NOT re-fetched this round** | the 3,212.2 t/s E-27b-t2 @64 k row, "quoting a throughput number without its context length and headcount is meaningless" |
| S11 | `vllm/engine/arg_utils.py` @ GitHub main | upstream keeps `max_num_batched_tokens`/`enable_chunked_prefill` as auto-derived scheduler knobs → no equivalent of Radiance's chunk/interval/busy-chunk laws |
| S12 | **`readonly-global-grafana` PromQL (uid `prometheus`) + LogQL (uid `P8E80F9AEF21F6940`), this round.** Queries: `{pod=…}`-scoped `radiance:prefill_tokens_per_second`, `radiance:decode_step_seconds_{best,recent}`, `vllm:num_requests_{running,waiting}`, `vllm:kv_cache_usage_perc`, `vllm:gpu_prefix_cache_hit_rate`, `rate(radiance:engine_prefill_chunks_capped_total[5m])`, `increase()` pairs for `attn_cached_tokens_total / prompt_tokens_total`, `prefix_tokens_total`, `engine_steps_{prefill,mixed,decode,held}_total`, `prefix_cache_{evictions,expired,ckpt_*}_total`(+`_by_reason`), `prefix_hit_cuts{reason}`+`prefix_hit_cut_tokens_total`, `draft_{tokens,accepted,refills,refill_tokens}_total`, `draft_position_{acceptance_ratio,reached,accepted}`, `decode_rows_unspeculated_total`, `kv_stream_bytes_total{dir=in}`, `kv_resident_blocks`, preemption family, `max_over_time(...[14h50m])`, `increase(request_prompt_tokens_bucket)` — windows 2026-11-22T22:00Z→2026-11-23T18:55Z, both 27b pods; **855 parsed ` done from ` lines** (`prompt=(\d+) (cache (\d+) … ttft=…`) binned by cold-token count; boot-receipt lines 04:01:20–04:02:40Z | every MEASURED figure above |
| S13 | `EXPLORE.md` (this ticket) — scout, 2026-11-23 | the claims under test; chronology; metric census; §10 instrument gaps |
| S14 | `2026-11-bug-radiance-27b-context-window/` `RESEARCH.md` V1–V5 + `DECISIONS.md` D1–D19 | V3's 64 KiB estimate (now refuted), V5's TP1-vs-TOTAL claims, D1 raise, D6 seqs-FORM, D7/D10 held memory, D9(a) `M ≥ 8` bar, D15/D16 gate limits |
| S15 | cf-143 `RESEARCH.md` §R19-Q4/Q5 (attribution table; mxfp4 on gfx1201; docs' measured tables) | the 3,212 row's conditions as recorded; Wilde-vs-card attribution hygiene |
| S16 | `.agents/notes/radiance-second-gpu-tp2.md` (§2, §8, §10, §13) and `radiance-host-tuning.md` (§1 D44/D51 link law, §7 RUNTIME-PM, §9 PROVEN-DONE, §10 POWER-CLOCKS, §14, §15 protocol) and `radiance-q27-boot.md` (receipt law) | host-side reads that are owner-lane; mailbox-vs-P2P envelope; Gen3-latch precedent; the `limit − pinned ≥ 4` law |
| S17 | `services/gpu-ai/prod/values.yaml` (:1355–1400 q27 absences comment incl. :1373; :1163–1175 fn spec env; :1597–1610 flash-tp1; q27-tp2 lane block :1645–1734) and `charts/radiance/values.yaml` (serve FORM :210–241, env list, pin :332–346) | what is per-lane env today vs FORM-fixed; the :1373 comment Q6 turns on |
| S18 | prior rounds' Wilde OOM/pinned-burst demotion caveat, carried in [S16] and `radiance-second-gpu-tp2.md` §7 | tier-size host-memory bound |

---

RESULT
status: DONE
chunk: research (27b-TP2 perf optimization round, Q1–Q6)
files_changed: [.agents/plans/2026/2026-11-bug-radiance-27b-tp2-perf/RESEARCH.md]
commands_run: [
 skill loads /storm /pipeline-conventions /pipeline-role-research => pass;
 reads: EXPLORE.md (this ticket, full), context-window RESEARCH.md (V1–V5) + DECISIONS.md (D1–D19), cf-143 RESEARCH §R19-Q4/Q5 + ladder greps, notes radiance-second-gpu-tp2.md (full) / radiance-host-tuning.md (§1,7,9,10,14,15) / roster + q27-boot (headings), services/gpu-ai/prod/values.yaml :1163-1175/:1355-1400/:1597-1610/:1655-1675, charts/radiance/values.yaml serve FORM + RADIANCE_* census => pass;
 read-only git (git log) => pass;
 execute+fetch (no file writes): codeberg API tags/contents for GUIDE/OPS/TP4/TP3/README/PREPARING_YOUR_RIG/DEVLOG at BOTH v1.17.0 and main, in-memory grep/slice; Qwen3.8-27B config.json; vLLM arg_utils.py; radiance issues 592/603/457/594 listings => pass (GUIDE.md at root and docs/GUIDE.md@branch/main form: 404/table-absent — recorded in §0.8);
 websearch: R9700 specs (AMD page + datasheet + TPU) => pass;
 readonly-global-grafana query_prometheus ~45 (chronology, rates, quantiles, lifetime increases, by-reason censuses, concurrency buckets) + query_loki_logs ~30 (boot receipts 04:01Z, 855 done-lines, refusal census, WARN/speculation/chunk-geometry/pool/draft lines) => pass;
 arithmetic in Code Mode: FLOPs-vs-length model calibrated on the docs' two published anchors; collective volume/time per link class; pool decomposition; MTP footprint and session deltas => pass]
deviations: [Wrote only the named deliverable; the write succeeded first attempt (no refusal to report). Did NOT read or write 2026-11-bug-radiance-flash-tp2-perf/ (flash scout isolation honored). Kept no storm scratch files: the skill's intermediate files (storm-runs/, perspectives.md, raw/) would have been file writes outside the deliverable, so the run-dir scaffolding was skipped and the method executed in-conversation with the full source/contradiction trail recorded inside RESEARCH.md (§1 perspectives, §9 conflicts, §S sources, Reliability notes). Wilde's blog not re-fetched this round (used as carried evidence, flagged §0.1). Two of the scout's figures I could not reproduce exactly (prefill-gauge p95; chunks_capped lifetime) — reported as filtering/extrapolation differences rather than forced into agreement.]
friction: [PromQL: `quantile_over_time` cannot wrap a filtered vector (`> 0 [5h]` → parse error) and `{__name__=~"radiance:x.++"}` is invalid RE2 (nested repetition) — resolved by client-side percentile computation and `.*` alternations; Grafana MCP response shape is `{data:[{metric,values:[[ts,val]]}]}` (not `.data.result`) — one batch of 10 queries died on that; Loki instant-with-offset probe shape returned null, so per-request concurrency attribution used capped-event density in the prior 3 min as proxy; `increase()` across the 04:01 pod-boot counter reset extrapolates → lifetime totals for capped/eviction counters are approximate; GUIDE.md@v1.17.0 lives under docs/ (root path 404s) and the v1.17.0 flag table is absent from main's GUIDE form — both recorded as version-drift caveats rather than silently averaged]
open_questions: [owner-side: the §3.4 host block (per-port LnkSta/LnkCtl2/Phy16Sta under load, current_speed/width per BDF, ReBAR Region 0 both cards, rocm-bandwidth-test c3↔c7, journalctl bandwidth line, /diagnostics live block, sclk/power ramp) — nothing else can separate P1-vs-P2 (C1); owner-side: one same-boot fixed-probe A/B at --tp-wire exact vs wht6 for a solo ~150k prefill (R2); coordinator: does the next boot print "speculation: from N decoding sequences on, 'dflash2' runs its short block" or a "declares no shorter block / serial head" warning? — that single line decides whether R3 has any territory; research-owned: what bounds prefix_hit_cuts reason=resumed_below (drafter window 2,048 vs checkpoint-interval vs tier boundary)? measured avg cut is 7,215 tokens, unexplained by any documented constant; owner: is a 1.17.0→2.x move ever contemplated, given issue #457's −30%/2×-step report for this model family? (relevant because three of the levers here are documented at main, not at the pin)]
next_suggested: [hand §7 R1+R2 to the owner as one read-only block (clocks + link + P2P + /diagnostics under a solo 150k prefill, plus the exact-wire A/B boot), and grep the next boot for the "speculation:" short-block line; then decide R3/R4/R7 with that evidence rather than adding more software knobs; keep C1–C6 visible in DECISIONS (esp. the ruling-vs-arithmetic item: 8×262144 is not fundable at fp8 on 2×30.73 GiB claimable, and that is the ruling's price, not a measurement error)]
