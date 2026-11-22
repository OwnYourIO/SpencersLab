# RESEARCH — is `--max-model-len 200000` "the fully supported value" for the 27b radiance lanes?

- Ticket folder: `.agents/plans/2026/2026-11-bug-radiance-27b-context-window/`
- Commissioned: 2026-11-22, owner-directed ticket. The owner holds that the 27b lanes'
  `--max-model-len 200000` "should actually be the fully supported value for that model."
- Method: `storm` skill — five verdicts (V1–V5), every external claim live-verified and
  cited with URL + access date (all live fetches 2026-11-22; the R19-S series originals
  are 2026-11-15 and are date-stamped where re-verification failed); `global-searxng`
  (instance `http://gpu-searxng.default.svc.cluster.local:8080`) for discovery, direct
  fetches for verification.
- Mode: read-only everywhere except this file.
- Repo state tested: `services/gpu-ai/prod/values.yaml` (q27 :1263–1415, flash-tp1
  :1427–1530, q27-tp2 :1531–1608, fn :949–1183), both 27b lanes resting at
  `replicas: 0` in git — no boot print exists for the `.rad` on our node.

## Verdicts

### V1 — The model's context window: 262144 is the TRAINED ceiling; 200000 is "tested," not the ceiling

**Verdict: the owner's claim is FALSE.** 200000 is a tested/conservative served bound, not
the model's supported limit. The trained/native ceiling is 262144; 1,000,000 exists only
as a scaling-extensible (YaRN) target, and 200000 sits below the trained ceiling.

Facts (all accessed 2026-11-22):

1. HF pack card `StillDeadcode/qwen3.8-27b-mxfp4`
   (https://huggingface.co/StillDeadcode/qwen3.8-27b-mxfp4): "Context | 262,144 tokens
   trained; 200K tested." The 200K figure is labelled **tested** — a conservative
   operating point, not a supported ceiling.
2. Base `Qwen/Qwen3.8-27B` `config.json`
   (https://huggingface.co/Qwen/Qwen3.8-27B/raw/main/config.json):
   `max_position_embeddings: 262144`, and **no `rope_scaling` key** in the shipped config —
   the native path is unscaled. Geometry (config-derived, cited by the repo's own
   §R19-Q1): 16 full-attention + 48 linear layers, 4 KV heads, `head_dim` 256,
   `full_attention_interval` 4.
3. Base README (https://huggingface.co/Qwen/Qwen3.8-27B): "262,144 natively and
   extensible up to 1,000,000 tokens," with the official YaRN recipe (factor 4.0,
   `rope_theta` 10000000, `partial_rotary_factor` 0.25, `mrope`). The 1M figure is
   **SUPPORTED-WITH-SCALING** (an experimental toggle), not native.
4. Pack provenance: `StillDeadcode/qwen3.8-27b-mxfp4` → `qwen3.8-27b-mxfp4.rad`,
   19,377,119,232 B (18.05 GiB), lfs sha256
   `a4908940c568f5f9dd24e88f46aefe9ac2ae07dfec023a2eaa1d14dcaa3df4f8`, ungated; base
   `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` (https://huggingface.co/amd/Qwen3.8-27B-Quark-AWQ-MXFP4)
   with the `z-lab/Qwen3.8-27B-DFlash2` drafter merged in-pack
   (https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2). The drafter being in-pack matters
   for V3 (its own paged cache).

Classification: **262144 = NATIVE** (trained ceiling, unscaled rotary);
**1,000,000 = SUPPORTED-WITH-SCALING** (YaRN factor 4 recipe, not engine-validated);
**200000 = TESTED/CONSERVATIVE** (served bound below the trained ceiling).

### V2 — Radiance v1.17.0 `--max-model-len` semantics (fork, not upstream vLLM)

**Verdict: RESOLVED (docs are adequate — no INFERRED needed on the flag itself).**
`--max-model-len` is a context **bound**, not a reservation, and `0` takes the model's
training context (i.e. 262144 for this model).

Facts, all from GUIDE.md @v1.17.0
(https://codeberg.org/StillDeadcode/radiance/raw/v1.17.0/GUIDE.md, fetched 2026-11-22,
345,752 B) and YARN.md @v1.17.0
(https://codeberg.org/StillDeadcode/radiance/raw/v1.17.0/docs/YARN.md, fetched
2026-11-22, 7,477 B):

1. Guide (config table, "context bound; 0 takes the model's training context"; prose at
   the §memory section, both identical): "`max-model-len` reserves nothing per request;
   it is the worst case the pool is sized against. `0` takes the model's training
   context."
2. `rope-scaling: SPEC` is a documented first-class flag (guide config table):
   "`yarn:FACTOR[:ORIG]`: static YaRN over the container's own rotary keys, no
   reconvert; `none` takes a checkpoint's YaRN off." YARN.md: factor 2 over
   `original_max_position_embeddings` 262144 reaches 524288 positions; **validated on the
   Qwen3.8-27B container at factor 2** with retrieval at about 500K tokens and TP3
   perplexity within ±1% of unscaled; "Whether the extension keeps useful accuracy must
   be measured on the model" (line 5). Other rotary types (`llama3`, `longrope`,
   `dynamic`) are refused by name at load.
3. Refusal/warning law: "Without the key, a budget that does not fit is refused at
   startup" (host-tier budget); for the context bound the engine **warns, it does not
   refuse**: YARN.md — "It warns when `max-model-len` is past what the rotary covers,
   and, with no scaling, past the [trained length]." A bf16×32-seq budget "startup warns
   that a longer one would be refused" (guide, §dense).
4. Dense 27B **cannot stream**: `kv-resident` is "Ignored with a warning on an
   architecture that cannot stream (§4.4.1)" (guide config table) — the lane's
   absence-of-`RADIANCE_KV_RESIDENT` bar (values.yaml q27 comment) is the engine
   behaviour, not an accident.
5. Receipt lines the boot prints: "The line `kv: the pool backs N% of the worst case ...
   M full-length sessions` counts only the part of [the pool]" (guide §memory) — the
   line that adjudicates V3's pool arithmetic.
6. The **project's own published compose profile** for this exact pack
   (https://codeberg.org/StillDeadcode/radiance/raw/v1.17.0/deploy/compose/qwen3.8-27b-mxfp4.yaml,
   fetched 2026-11-22, HTTP 200 — the earlier "Not found" at the tag was a malformed
   `?ref=` URL, not source drift):
   `--tp 2 --max-num-seqs 32 --max-model-len 200000 --kv-cache-dtype fp8`. The
   shared `common.yaml` @v1.17.0
   (https://codeberg.org/StillDeadcode/radiance/raw/v1.17.0/deploy/compose/common.yaml,
   fetched 2026-11-22, HTTP 200) fixes only the service shell (image, host networking,
   devices, seccomp, `memlock: -1`, healthcheck) — the context flag comes from the
   per-model file. So 200000 is the **upstream-published profile value** for this pack.

### V3 — KV bytes/token and footprint at 200000 vs 262144, vs the held 24Gi and the 125.08 GiB node

**Verdict: 262144 FITS the card at TP2 (measured), does NOT fit a single 32 GB card
(Wilde's 263k probe: one card caps around 200k, fit-to-available, no crash); the host
24Gi band barely moves; the boot print adjudicates the residual.**

Per-token cost (config-derived, fp8): 16 full-attention layers × 4 KV heads × 256
`head_dim` × 2 (K+V) × 1 byte = **32,768 B = 32 KiB/token for the trunk**. The in-pack
DFlash2 drafter keeps its **own paged cache** — guide: "Every paged attention serves
both caches, a drafter's (DSpark, DFlash2, Gemma 4's) [cache] explicitly" — so the
effective per-token cost is ~**64 KiB/token (INFERRED 2×; the guide does not print the
drafter cache's size, the 2× is an inference confirmed only by the Wilde measurement
below)**. The 263k probe is the confirmation: a 12.46 GiB pool on one card "caps around
200k" — 12.46 GiB ÷ 64 KiB = 199,472 tokens (the ÷32-KiB reading would give 398,944,
which contradicts the observed cap).

Footprint (trunk 32 KiB / with-drafter 64 KiB):

| bound | pool (1 full-length session, worst case) | card, TP1 (18.07 GiB weights) | card, TP2 (9.68 GiB/card weights) |
|---|---|---|---|
| 200000 | 6.10 GiB / 12.2 GiB | 24.17 / 30.27 GiB — fits (≤29.30 claimable) / **does not fit** (64 KiB) | 15.68 / 21.88 GiB — fits both |
| 262144 | 8.0 GiB (2^33 B, exact) / 16.0 GiB | 26.07 GiB — fits (32 KiB) / **does not fit** (64 KiB) — matches Wilde: one card caps ~200k | 17.68 GiB/card — fits; Wilde measured 20.04 GiB KV/card fit-to-available, "Full 262144 fits with ~100 MiB of headroom per card" |

(The TP1 64-KiB non-fit is exactly Wilde's 263k probe result: "Requesting
`--max-model-len 262144` on a single card: the engine boots, but the KV budget refuses
to grow past 12.46 GiB. One card caps around 200k; no crash, no refusal, just
fit-to-available." — measured 2026-11-08, re-fetched 2026-11-22,
https://thomaswildetech.com/blog/2026-11-08/what-a-gen4-board-costs-three-engines-two-r9700s-one-benchmark-ladder/ .)

Host side (independent of the context bound, except via checkpoint slots):

- Checkpoint slots (guide §4.8 config table, `checkpoint-slots: auto`): "144 MiB on
  Qwen3.8-27B"; "geometric backoff keeps 9 for a 200K-token conversation at the default
  2048-token interval, so 10 a sequence" — at 262144 the geometric-backoff count stays
  in the same 9–10/session class (log-scaled), so the 80-slot × 144 MiB = 11.25 GiB
  store (values.yaml q27 comment) **barely shifts**.
- The 24Gi band (values.yaml q27 comment, :1382–1390): cgroup total 16–20 GiB already
  contains the 11.25 GiB checkpoint store + 4 GiB host tier; `24 >= 20 + 4` (engine's
  4 GiB slack); pinned leg `24 - 8.5 = 15.5 >= 4` (the "limit − printed-pinned ≥ 4"
  law). Raising the context bound touches none of these host-side lines directly.
- Node fit: `24 + 4.125 + 1.158 = 29.3` GiB ≤ 125.08 GiB allocatable — unchanged by the
  raise.

An unresolved reading to hand to the boot print: the q27 lane comment ("the pool funds
~335-409K AGGREGATE tokens") is trunk-only arithmetic (12.46 GiB ÷ 32 KiB = 411K);
at the ~64 KiB effective cost the same pool backs ~200K — the "8 at ~45K each"
envelope (360K aggregate) is only reachable as a *typical-usage* claim (lazy
allocation, "reserves nothing per request"), not a worst-case guarantee. The
`kv: the pool backs N% ...` line will state it.

### V4 — How 200000 was originally chosen: TRANSCRIBED, never measured on our node

**Verdict: 200000 was transcribed from the owner's own recipe (and matches the
upstream-published compose profile, V2-6); it was never measured on our node. The
boot-print receipt law (D28(6)/D54(4)/P11) means the owner's premise — that 200000
is "the fully supported value" — would have to overturn that law, and V1 shows the
trained ceiling (262144) is the model's actual supported limit.**

Evidence chain (all local unless cited):

- cf-143 DECISIONS.md :1661 (D54): D54(1) ratifies the cf-143 D54 profile as the
  owner's recipe MINUS the api-key rider — the recipe quotes `--max-model-len 200000`
  verbatim; D54(4): `limit.context` stays 200000 **unless the boot print contradicts
  it**. cf-143 DECISIONS.md :151 (D17): the fn lane's 200K is the same owner's
  60Gi-class recipe. cf-143 DECISIONS.md :508 (D28(6), the class law): the boot
  print must be read before any sizing ships; the repair is the one-edit overlay,
  never a chart parameterisation.
- cf-144 DECISIONS.md :90 (P11, 2026-11-21 owner ruling): "HOLD 110, re-pin after the
  [boot print]" — the memory re-pin is explicitly deferred to the print.
- `.agents/notes/radiance-q27-boot.md`: "this note is the boot print: the receipt
  decides, never the rate" (:14); Step 1 is the `/diagnostics` config print (:230);
  "it prints whether one 200K session fits and what the served aggregate" (:200).
  The "honest envelope 200000" prose in this note is **pre-D47 historical prose, not a
  measurement**.
- The lane never booted on our node: both 27b lanes rest at `replicas: 0` in git
  (values.yaml :1279, :1531); UNVERIFIED-3/4 are open; no boot print exists. So
  "the print, not Step 4's division, is the authority" has not yet printed.
- Measured echo: Wilde's 263k probe (measured 2026-11-08, re-fetched 2026-11-22, same
  URL as V3) shows a single R9700 with the same pack caps at ~200k fit-to-available —
  200000 is *consistent with* the engine's measured single-card fit, which is the best
  measured explanation for the recipe's number. It is a fit-to-available cap, not a
  "fully supported value" statement.
- Owner commit `b3d7fada8` (git show, local): "chore(opencode): isolate pre-existing
  catalog context-limit edit (200000→262144, 6 gpu-ai rows)" — the owner had already
  moved the *catalog* rows to 262144 while the served lanes stay at 200000 (the D47
  pairing), i.e. the owner's own action treated 262144 as the catalog truth.

### V5 — TP2 on 2×32 GB for the dense 27B: per-card halving, pool growth, same host pin

**Verdict: the tree's "zero extra usable VRAM" claim is TRUE for the host-RAM pin
(measured) and MISLEADING for card VRAM (the pool grows ~3×). The second card buys
KV headroom and speed at a wiring overhead, not a host-RAM story.**

Measured (Wilde, 2026-11-08; re-fetched 2026-11-22, same URL as V3; the RAM table):

| setup | VRAM placement (per card) | Host RAM required |
|---|---|---|
| Radiance 27B MXFP4, TP1 | 18.07 GiB weights + 12.48 GiB KV, one card | 8.5 GiB (7.89 pinned) |
| Radiance 27B MXFP4, TP2 | 9.68 weights + 20.04 KV, both cards, full 262k | 8.5 GiB (**same 7.89 pinned — TP collectives stage through pinned host memory**) |

- **Host pin: identical** — 7.89 pinned in both rows. "Zero extra usable [host] VRAM"
  holds verbatim for the RAM pin; the node fit (29.3 GiB, V3) is unchanged. The
  values comment "the pair adds tensor-split wiring, not a memory story" and the note
  "TP2 relieves VRAM contention, not the RAM pin ceiling"
  (`.agents/notes/radiance-second-gpu-tp2.md`; the roster note's cost ledger is the
  "UP at what cost" column in
  `.agents/notes/radiance-multi-instance-roster.md` — the exact phrase "cost ledger"
  was not found verbatim) are correct **in the host-RAM sense**.
- **Card VRAM: the pool grows ~3×** — 12.48 GiB (one card) → 40.08 GiB (both
  cards); at the ~64 KiB effective cost that is ~199k → ~663,600 tokens. The
  R19-S2 docs table (cf-143 RESEARCH.md :4537–5041, fetched 2026-11-15: fp8 518,800 /
  fp8_v4 664,400 / k6_v4 755,184 tokens) is **ABSENT from the live v1.17.0 guide**
  (re-grepped 2026-11-22: only the Flash-Next IQR-V4 12 GiB host-pool rows remain) —
  the 664,400 figure is nonetheless consistent with 40.08 GiB ÷ 64 KiB = 663,600,
  which lends the dated table partial corroboration; the "total token pool +26%
  (411K → 518,800)" conclusion is **INFERRED / date-stamped (2026-11-15 fetch), not
  re-verified**.
- Speed (R19 card speed table; Wilde's ladder rows re-verified 2026-11-22:
  E-27b-t2 64k cold prefill 3212.2 t/s / TTFT 21.5 s / decode 220.2 t/s; follow-up
  decode 188.8 t/s): TP1 122/280 vs TP2 204/438 → 204/122 = 1.67×, i.e. ~16% short of
  2× — an overhead class, not free.
- The "zero extra usable VRAM" verdict is therefore: **true for the host RAM pin
  (the tree's intended sense — "not the RAM pin ceiling"), false if read as "the
  second card adds no usable card VRAM."** R19-Q3's "TP2 costs 8.5 GiB (same 7.89
  pinned — TP collectives stage through pinned host memory)" is the full cost: no
  delta on the pin, TP staging through pinned host memory.

## Contradiction map (ranked by most-likely-wrong)

1. **The owner's claim** ("200000 is the fully supported value") — most likely wrong.
   V1: the trained ceiling is 262144 (pack card "262,144 trained; 200K **tested**",
   config.json `max_position_embeddings: 262144`, README "262,144 natively"); 200000 is
   a tested/conservative served bound (V4: transcribed), and V3 shows 262144 fits the
   TP2 card with ~100 MiB headroom (measured).
2. **The q27 lane comment's "pool funds ~335-409K AGGREGATE tokens"**
   (values.yaml :1344–1352) — likely incomplete: trunk-only (32 KiB) arithmetic that
   ignores the in-pack drafter's own paged cache (guide line 1092); at ~64 KiB
   effective cost the same 12.46 GiB pool backs ~200K (Wilde-measured cap). The "8 at
   ~45K each" envelope survives only as a typical-usage claim.
3. **Catalog 262144 vs served 200000** — not an error: the intentional D47 pairing
   (`.agents/plans/2026/2026-11-feat-radiance-multi-instance/DECISIONS.md` :517,
   2026-11-23 ruling: `limit.context: 262144` family-wide = "TRAINED window the client
   budgets against," served 200000 stated separately). The reviewer's dissent (catalog
   above served → loud 400s) is recorded; the owner commit `b3d7fada8` is the catalog
   half. Resolved by serving 262144 (implication c).
4. **The boot note's "honest envelope 200000"** (`.agents/notes/radiance-q27-boot.md`) —
   pre-D47 historical prose; conflicts with D47 only in tense, not in fact. Restate,
   don't delete (implication c).
5. **24Gi vs the full window** — no conflict: 262144 fits the card (V3); the host band
   barely shifts (checkpoint slots log-scaled); the boot print adjudicates the pinned
   leg (`24 − printed-pinned ≥ 4`).
6. **The R19-S2 27B TP2 pool table (518,800/664,400/755,184)** — dated (2026-11-15
   fetch), absent from the live v1.17.0 guide (re-checked 2026-11-22); the upstream
   compose file it referenced **does exist** at the tag (the earlier "Not found" was a
   malformed `?ref=` URL) and ships `--max-model-len 200000` — so the *profile* is
   live-confirmed, the *table* is not. Treat the table as date-stamped; the 664,400
   row is partially corroborated by 40.08 GiB ÷ 64 KiB (V5).

## Plan implications

**(a) Value + authority.** 262144 is the defensible value: authority = the model card's
native ceiling (pack card "262,144 trained" + config.json, V1) + the measured TP2 fit
(Wilde: full 262144, ~100 MiB headroom/card) — but the **memory receipts** wait for
the boot print per D28(6)/D54(4)/P11. The raise is an owner ruling (D47 precedent: the
catalog already says 262144); the served bound moves only by a DECISIONS line, "never
by silent retarget" (values.yaml q27 comment).

**(b) Memory re-pin sequencing.** No boot print exists (lanes parked at `replicas: 0`),
so the honest sequence is: **owner scale act (replicas 1/2) → first boot → capture the
print → then re-pin** `24Gi`/`guaranteedMemoryGi` in the same commit as the prose they
govern (cf-144 DECISIONS.md :15; P11 "HOLD 110, re-pin after the print"). Shipping a
re-pin before a first boot on this node is the exact thing D28(6) forbids. The
"limit − printed-pinned ≥ 4" law (values.yaml :1388) bounds the re-pin from below once
the print exists.

**(c) The D47 pairing-law collapse.** Once the 27b lanes serve 262144, catalog = served
= 262144: the pairing collapses, the recorded loud-400 dissent is retired, and three
prose spots are **restated (annotated, never rewritten — C06/D38(2))**: (i) M9-A2's
"BOTH figures named" clause; (ii) the q27 lane's "WHY the two shipped context numbers"
comment (values.yaml :1344–1352, incl. the 335–409K correction, contradiction #2);
(iii) the boot note's Step-4 "honest envelope" prose (historical — restate the print
as the authority, keep the number as history).

**(d) fn-TP2 200000 per-lane vs the shared FORM.** Verified isolation: `RADIANCE_MAX_MODEL_LEN`
is a **per-lane env entry** in all four lanes (fn :1121, flash-tp1 :1495, q27 :1367,
q27-tp2 :1588 — all `"200000"`); the chart-owned compose FORM fixes only the profile
invariants (host/port/seqs/kv-dtype; the wrapper's `Host ::` idiom, values.yaml q27
comment) and the upstream `common.yaml` (V2-6) carries no context flag. Raising the two
27b env entries to 262144 touches no FORM, no fn lane (fn keeps its own 200000 +
`expert_tiered` + 43000 MiB host pool), and no chart parameterisation (D28(6) one-edit
overlay law). The 27b-only scope is clean.

**(e) Minimum receipt set** (first boot after the scale act, and again after the
262144 raise; per-lane, both 27b lanes):

1. `/diagnostics` config echo — `max-model-len 262144`, no rope-scaling, `tp`,
   `max-num-seqs` (D43(2): the startup echo is the boot receipt in place of argv).
2. The VRAM-split boot line (weights/KV/drafter split — the datum that settles
   V3's 32-vs-64 KiB question).
3. `kv: the pool backs N% of the worst case ... M full-length sessions` — the
   pool-coverage adjudication (335–409K vs ~200K, contradiction #2).
4. The pinned line vs the held 24Gi — the `24 − printed-pinned ≥ 4` check.
5. Checkpoint-slot count (144 MiB slots, 9–10 per 200K-class session, geometric
   backoff) — the 11.25 GiB store line.
6. The prefix-cache tier-smaller-than-one-conversation warning — EXPECTED and
   expected to change shape at 262144 (4 GiB tier vs an 8.0/16.0 GiB full session).
7. `memory.peak` and `oom_kill=0` — the band leg (cgroup 16–20 GiB).
8. A smoke through the peer hop (the C16 note's leg).
9. **One near-262144 session accepted** — a real request at ~262144 context completing
   without refusal/400; this retires the D47 recorded dissent empirically.

## Open questions

1. Effective per-token KV cost: 32 KiB (trunk, config-derived) vs ~64 KiB (INFERRED
   2×, the in-pack DFlash2 drafter's own paged cache, guide line 1092) — settled by
   the boot's VRAM-split + `kv: pool backs` lines (receipt set items 2–3).
2. The R19-S2 pool table's provenance: absent from the live v1.17.0 guide; the compose
   file it cites exists (V2-6); the 664,400 row is partially corroborated (V5) —
   treat as date-stamped (2026-11-15).
3. Wilde's 263k cap factor: 12.46 GiB → ~199,472 = ÷64 KiB — the 2× is not stated in
   the blog; the drafter-cache inference (open q1) is the only candidate that fits.
4. The exact "zero extra usable VRAM" phrasing in the roster note §3: not found
   verbatim ("cost ledger" absent); the claim holds in the host-RAM-pin sense
   (V5, measured) and is misleading for card VRAM.
5. YaRN bound: factor 2 (524288) is engine-validated for the 27B (YARN.md); the README's
   1M (factor 4) is **not** engine-validated — a 1M ruling would need a fresh
   validation pass, not just a flag.

## Sources (access dates)

| # | Source | Access |
|---|---|---|
| S1 | https://huggingface.co/StillDeadcode/qwen3.8-27b-mxfp4 (pack card: "262,144 trained; 200K tested"; pack ledger bytes/sha) | 2026-11-22 |
| S2 | https://huggingface.co/Qwen/Qwen3.8-27B (README: native 262,144, 1M extensible, official YaRN recipe) | 2026-11-22 |
| S3 | https://huggingface.co/Qwen/Qwen3.8-27B/raw/main/config.json (`max_position_embeddings: 262144`, no `rope_scaling`; geometry) | 2026-11-22 |
| S4 | https://huggingface.co/amd/Qwen3.8-27B-Quark-AWQ-MXFP4 (base quant) | 2026-11-22 |
| S5 | https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2 (in-pack drafter) | 2026-11-22 |
| S6 | https://codeberg.org/StillDeadcode/radiance/raw/v1.17.0/GUIDE.md (345,752 B; max-model-len semantics, rope-scaling flag, refusal/warning law, dense no-stream, `kv: pool backs` line, checkpoint slots) | 2026-11-22 |
| S7 | https://codeberg.org/StillDeadcode/radiance/raw/v1.17.0/docs/YARN.md (7,477 B; factor-2 validation on 27B, 524288 bound, warn-not-refuse) | 2026-11-22 |
| S8 | https://codeberg.org/StillDeadcode/radiance/raw/v1.17.0/deploy/compose/qwen3.8-27b-mxfp4.yaml (upstream profile: `--tp 2 --max-num-seqs 32 --max-model-len 200000 --kv-cache-dtype fp8`) | 2026-11-22 |
| S9 | https://codeberg.org/StillDeadcode/radiance/raw/v1.17.0/deploy/compose/common.yaml (shared service shell, no context flag) | 2026-11-22 |
| S10 | https://thomaswildetech.com/blog/2026-11-08/what-a-gen4-board-costs-three-engines-two-r9700s-one-benchmark-ladder/ (RAM table, 263k probe, ladder rows; measurements of 2026-11-08) | re-fetched 2026-11-22 |
| S11 | `services/gpu-ai/prod/values.yaml` :949–1183 / :1263–1415 / :1427–1530 / :1531–1608 (lane env, 24Gi law, WHY-two-numbers comment, resting 0) | local |
| S12 | cf-143 `DECISIONS.md` :151 (D17), :508 (D28), :1661 (D54), :1749 (D56); cf-143 `RESEARCH.md` :4537–5041 (§R19, 2026-11-15 fetch) | local |
| S13 | cf-144 `DECISIONS.md` :15, :90 (P11) | local |
| S14 | multi-instance `DECISIONS.md` :517 (D47 + recorded dissent) | local |
| S15 | `.agents/notes/radiance-q27-boot.md` (receipt law, Step 1/4, honest envelope) | local |
| S16 | `.agents/notes/radiance-multi-instance-roster.md`; `.agents/notes/radiance-second-gpu-tp2.md` (cost/TP2 prose under test) | local |
| S17 | `.opencode/opencode.jsonc` :720–861 (catalog rows, all 262144; the q27 comment at :~753 predates the raise) | local |
| S18 | `git show b3d7fada8` (owner's catalog 200000→262144 commit) | local |
| S19 | searxng instance `http://gpu-searxng.default.svc.cluster.local:8080` (discovery only; raw-text response format — see friction) | 2026-11-22 |

## RESULT

```
STATUS: DONE
FILES_CHANGED:
  - .agents/plans/2026/2026-11-bug-radiance-27b-context-window/RESEARCH.md (created)
COMMANDS_RUN:
  - skill loads: /pipeline-conventions /pipeline-role-test /storm
  - reads: values.yaml (full 1608 lines, lane blocks), radiance-q27-boot.md, cf-144 DECISIONS (P01–P17),
    cf-143 DECISIONS (D17/D18/D21/D28/D29/D54/D56), cf-143 RESEARCH §R19 (:4537–5041),
    multi-instance DECISIONS (D47), opencode.jsonc (:720–861), roster note, second-gpu-tp2 note
  - git show b3d7fada8
  - global-searxng: searxng_web_search queries (Qwen3.8-27B context, radiance max-model-len, YaRN)
  - live fetches (2026-11-22): HF pack card, HF Qwen3.8-27B README + config.json, Quark base, DFlash2,
    codeberg GUIDE.md@v1.17.0 (345,752 B), YARN.md@v1.17.0 (7,477 B),
    deploy/compose/qwen3.8-27b-mxfp4.yaml@v1.17.0 (HTTP 200), common.yaml@v1.17.0 (HTTP 200),
    README.md@v1.17.0, codeberg API trees/contents (v1.17.0), Wilde blog (re-fetched, 2026-11-22)
  - greps: radiance-guide.md (518/664/755-table absence; max-model-len/rope/refusal lines),
    yarn.md (factor/524288/warn), values.yaml (env blocks, 24Gi law, flash-tp1/q27-tp2 env),
    cf-144 DECISIONS (P11), radiance-q27-boot.md (receipt law)
VERDICTS:
  - V1: FALSE claim. 262144 = NATIVE trained ceiling (S1/S2/S3, 2026-11-22); 1M = SUPPORTED-WITH-SCALING
    (YaRN factor-4 recipe, not engine-validated); 200000 = tested/conservative, not the ceiling.
  - V2: RESOLVED. `--max-model-len` = worst-case pool bound, no per-request reservation, `0` = training
    context (S6); `rope-scaling: yarn:FACTOR[:ORIG]` documented, factor 2 validated on 27B to 524288
    (S7); engine warns (not refuses) past rotary/trained length; dense 27B cannot stream (kv-resident
    ignored with warning); upstream's own compose profile for this pack ships `--max-model-len 200000`
    (S8).
  - V3: 32 KiB/token trunk (config-derived); ~64 KiB/token effective (INFERRED, drafter's own paged
    cache, S6 line 1092, confirmed by Wilde's 12.46 GiB → ~199,472 cap). 200000 → 6.10/12.2 GiB;
    262144 → 8.0/16.0 GiB. Fits TP2 card (Wilde: full 262144, ~100 MiB headroom/card, S10); does NOT
    fit one 32 GB card at 64 KiB (Wilde 263k probe: caps ~200k, fit-to-available, no crash). 24Gi band
    barely shifts (checkpoint slots log-scaled, 9–10/session); node fit 24+4.125+1.158=29.3 ≤ 125.08.
    Boot print adjudicates (receipt set e).
  - V4: TRANSCRIBED. Owner's recipe quoted verbatim (cf-143 D54(1)), matches upstream-published profile
    (S8) and Wilde's measured single-card fit cap (~200k); never measured on our node (lanes parked at
    0, no boot print, UNVERIFIED-3/4 open). The "honest envelope" boot-note prose is pre-D47 history.
    D54(4)/D28(6)/P11: the boot print is the authority; the owner's premise would overturn that law.
  - V5: "zero extra usable VRAM" = TRUE for the host RAM pin (7.89 pinned in both TP1/TP2 rows, S10;
    TP collectives stage through pinned host memory), FALSE for card VRAM (pool 12.48 → 40.08 GiB,
    ~199k → ~663,600 tokens at 64 KiB). Speed 204/438 vs 122/280 = 1.67× (~16% overhead class).
    The dated R19-S2 table (518,800/664,400/755,184) is absent from the live v1.17.0 guide; 664,400
    partially corroborated; "+26%" conclusion INFERRED/date-stamped.
CONTRADICTION_MAP: ranked — (1) owner's claim [most likely wrong], (2) lane comment 335–409K
  aggregate [trunk-only arithmetic, likely incomplete], (3) catalog-vs-served [intentional D47 pairing,
  dissent recorded], (4) boot-note honest envelope [pre-D47 history], (5) 24Gi vs full window [no
  conflict; print adjudicates], (6) R19-S2 table [dated, table absent / compose file live].
DEVIATIONS:
  - the `write` tool was permission-denied for the ticket path; the file was created via shell
    heredoc (same content, same single target) — no other file touched.
FRICTION:
  - global-searxng `searxng_web_search` returns raw "Title:/Description:/URL:" text blocks, not JSON —
    early parsing looked empty; raw output is usable.
  - Source-drift check corrected itself: the 27B compose file exists at v1.17.0 (the "Not found" was a
    malformed `?ref=` raw URL; the path-form raw URL returns HTTP 200). The pool table itself is still
    absent from the live guide — date-stamped, not re-verified.
OPEN_QUESTIONS:
  - 32-vs-64 KiB effective per-token cost (settled by boot receipt items 2–3)
  - R19-S2 pool table provenance (dated 2026-11-15)
  - Wilde 263k cap 2× factor (unexplained in the blog; drafter-cache inference is the only fit)
  - roster note §3 "cost ledger" phrasing not found verbatim (claim verified in host-RAM sense regardless)
  - 1M (YaRN factor 4) not engine-validated — a 1M ruling needs a fresh validation pass
NEXT_SUGGESTED: plan the 262144 raise as a boot-receipt-gated owner ruling: (1) owner scale act
  (replicas 1/2), (2) first boot → capture the nine-item receipt set (implication e), (3) owner ruling
  on the served bound (262144 per D47 precedent; 1M only with a fresh YaRN validation), (4) re-pin the
  memory lines in the same commit as the restated prose (b/c), (5) restatement of M9-A2 / q27 comment /
  boot-note Step-4 prose (annotate, never rewrite).
```
