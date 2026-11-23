# RESEARCH — radiance `-fp8_v4` lane + per-lane seqs + 1.5× YaRN window (G1–G6)

- **Ticket folder:** `.agents/plans/2026/2026-11-feat-radiance-fp8v4-yarn/` (new, owner-directed)
- **Round:** agent-research, 2026-11-23 ~21:20–22:00Z. Grounding for a ticket **before anything is
  built**. Mode: read-only everywhere except this file; no config/code edits, no commits, no pod
  exec, no admin tiers.
- **Owner's asks (verbatim intent):** (1) add a new pod/Application `-fp8_v4`; (2) `--max-num-seqs`
  → **5** on the existing four lanes; (3) the new lane **leaves it at 8**; (4) **1.5× context
  (262,144 → ~393,216) via RoPE/YaRN**; (5) update all of these models in `opencode.jsonc`.
- **Method:** `storm` — survey (`global-searxng`), five derived perspectives (§P), live retrieval at
  **both branches separately** (pin `v1.17.0` vs `main`/2.x), contradiction mapping (§9), and the
  repo's own measured record ([E27], [EF], [CW], [ROST], chart/values reads). Every figure carries
  **MEASURED / DERIVED / CLAIMED** and its conditions (context length, batched-tokens, rig,
  session-vs-bytes unit) per the launch's method constraint.

## TL;DR

1. **G1: the 1.5× YaRN request is implementable as stated at our pin** — `--rope-scaling
   yarn:FACTOR[:ORIG]` exists in GUIDE@v1.17.0's flag table, the factor is a *finite number ≥ 1*
   (fractional legal, f64 through the kernel contract), `ORIG` is optional and defaults to the
   container's own trained length, and the packs' `rope_type: default` is exactly the unscaled state
   the runtime flag is designed to override (the feared blocker is refuted by the doc, which names
   the Qwen3.8 containers). **But factor 1.5 is nowhere validated** — the validated pair is factor 2
   (±1% TP3 perplexity, retrieval ~500K, on these exact containers), and the docs' own example serves
   *409,600 under a factor-2 map* — so `yarn:2` + `--max-model-len 393,216` is the defensible form.
2. **G2: `fp8_v4` at 1.5× window with 8 sequences is a REGRESSION versus today, and the owner's
   reasoning is arithmetically right** — 1.5× window needs +50% pool tokens; `fp8_v4` gives +28%,
   `k6_v4` gives +45% (§2). Funded sessions fall 5.3 → **4.6** (`fp8_v4`) or **5.2** (`k6_v4`),
   backing 66% → 57%/65%. Under the fixed 22.24 GiB/card pool, window and session-count are ONE
   budget — the two goals are mutually exclusive at TP2×8-seqs; §7 gives the shapes that do fund.
3. **The brief's "+12% long-prompt prefill" headline is a misattribution** (carried from the prior
   round): GUIDE@v1.17.0's dtype table shows **no dtype-alone prefill gain** (41 k prefill 9.76 /
   9.76 / 9.84 s for fp8 / fp8_v4 / k6_v4); the 2,666→3,097 t/s interval is `--attn-prefill-fp8
   both` *on top of* `fp8_v4` — the lossy-attention flag whose measured tool-calling cost (KL
   0.17–0.27) is our exact workload. The dtype table's KL (~0.040 vs bf16, all three layouts) is on
   **log-analysis** documents, not tool-calling.
4. **The dtype itself is accuracy-cheap, the mechanism is chart-wide:** `fp8_v4` = K E4M3 + **V
   int4**; `k6_v4` = **K int6** + V int4 (owner's "6-bit K / 8-bit V" guess is wrong on V). Both are
   offered on **both** Qwen3.8 plugins (`qwen35_fp8`, `qwen4exp_fp8`), drafter cache stays fp8.
   Making dtype/seqs/rope per-lane is three new env channels in the serve FORM plus a **receipt_gate
   rewrite** (its single-distinct-`--max-num-seqs` read goes ambiguous the moment lanes differ).
5. **2.x is the anti-direction:** at `main`, `fp8_v4`/`k6_v4` are **refused**, `fp8` is refused by
   most plugins, and our MXFP4 `.rad` packs are refused at startup by name — the whole plan is a
   **v1.17.0-only** structure (with #457's open −30%/2×-step claim on 2.0.0 as extra reason).

## Reliability notes (storm peer review)

| Finding | Confidence | Reason |
|---|---|---|
| YaRN flag syntax + fractional legality at v1.17.0 | 8 | GUIDE@tag :2071 + YARN@tag verbatim; parse of `1.5` is docs-wording (CLAIMED), not executed — boot print is the arbiter |
| ORIG optional / packs unscaled-by-design | 9 | YARN@tag names the Qwen3.8 container's `text_config.rope_parameters` = `default` and the ORIG default |
| Funding matrix (formula reproduces both prints) | 9 | Inputs measured boot prints; fp8@262144 recomputes 66.8%→printed 66, 5.34→printed 5.3; fn 51.5%→printed 52, 4.12→4.1 |
| `fp8_v4`@1.5×@8 = regression | 9 | Pure pool arithmetic on measured elastic; only escape is seqs or memory (both constrained) |
| dtype bit-layouts + plugin scope | 9 | GUIDE@tag §4.4 verbatim, both branches checked separately |
| dtype table ≠ tool-calling accuracy | 7 | Doc's eval corpus is 17 log-analysis docs; the narrow layouts were never scored on tool-calling |
| 5-lane ladder forces a second named low-tie | 8 | TEST_SPEC §3 laws applied mechanically (cols unique/decreasing, no negatives, low<def strictly) |
| 2.x refuses v4 + our packs | 9 | GUIDE@main §migration verbatim + #457 author's observed refusal (CLAIMED, open issue) |
| fn at seqs 5 still refutes (M 4.1 < 5) | 8 | MEASURED pool-token count, D16 bar re-scoped |

**Weakest claim:** the parse-legality of `yarn:1.5` rests on doc wording ("finite number >= 1",
f64 coefficients) plus the fact that `yarn_from`/`rope_override` is unit-tested against vLLM's
integers *at factor 2* only. One controlled boot settles it (§10 Q4's receipt line).
**Perspective over-weighted:** P3 (docs lawyer) — the branch-separation discipline makes every
`main` number suspect, which is correct but depresses some genuinely stable facts (YaRN math).
**Missing angle:** a drafter-interaction analyst — YaRN applies the same factor to the drafter over
*its own* trained length; whether DFlash2's windowed cache + rescaled draft angles changes draft
acceptance on our traffic is unmeasured anywhere (open).

---

## §0 — Method, sources by branch, and what could not be verified

**Sources at the PIN (`v1.17.0`)** — fetched this round from
`https://codeberg.org/StillDeadcode/radiance/raw/tag/v1.17.0/…` unless stated:
- `[G@t]` `docs/GUIDE.md` (294,533 B; cited by line)
- `[Y@t]` `docs/YARN.md` (7,477 B; full text read)
- `[O@t]` `docs/OPS.md` (op-schema tables: `rope`/`rope_table`/`qsa_block_key` take optional
  `yarn_factor`/`yarn_low`/`yarn_high`/`yarn_magnitude` **f64** params — lines 960–965, 2977)
- `[C27@t]` `deploy/compose/qwen3.8-27b-mxfp4.yaml` (`--tp 2 --max-num-seqs 32 --max-model-len
  200000 --kv-cache-dtype fp8`), `[CF@t]` `deploy/compose/flashnext.yaml` (`--max-num-seqs 8 …
  fp8 … 2048`) — **upstream publishes no v4-dtype or rope-scaling profile at the pin** (CLAIMED,
  absence-in-fetched-files).

**Sources at `main` (2.x) — kept separate, never blended:**
- `[G@m]` `docs/GUIDE.md` (348,332 B): `rope-scaling: SPEC` still exists as a **config key** (line
  2645, YAML-shaped table — the 2.x interface moved from flag to file key); **`kv-cache-dtype:
  fp8_v4` and `k6_v4` are refused** and `fp8` is refused by every model whose plugin does not keep
  E4M3; `i8` (int8 K+V, scale per token+head) replaces them; a container with MXFP4/block-FP8
  weights **is refused at startup** (migration chapter, lines 4820–4840).
- `[Y@m]` `docs/YARN.md` (7,476 B): same factor laws; adds "Muse Glimmer validated at factor 8";
  wording shifts "flag" → "key".
- `[I457]` issue **#457 re-verified this round via Codeberg API: state OPEN**, updated 2026-11-22,
  7 comments: 1.17.0 (`--kv-cache-dtype k6_v4 --max-num-seqs 8 --num-speculative-tokens 6
  --draft-window adaptive --prefix-cache-mib 16384 --checkpoint-slots 48`, TP1, 262144 ctx) vs
  2.0.0 (`i8`): 8-session aggregate 98.7→35.4 t/s, step 31.9→63.2 ms, pool 535,824→363,072 tokens;
  author: "k6_v4 is refused … a shame since it worked so well for me on v1". (CLAIMED — third-party
  measurements, single rig; doubles as a **community witness that k6_v4@8×262144 serves in anger**.)

**Repo record (MEASURED, carried with file cites):**
`[E27]` `…/2026-11-bug-radiance-27b-tp2-perf/EXPLORE.md` + `RESEARCH.md` (boot receipts: 66%/5.3,
22.24 = 20.98+1.16+0.09 GiB, 16 KiB/token/card, 148 MiB/seq state, argv echo with
`--max-num-seqs 8 --kv-cache-dtype fp8`, no rope flag);
`[EF]` `…/2026-11-bug-radiance-flash-tp2-perf/EXPLORE.md` (fn 52%/4.1, 7.3125 KiB/token/card,
1,080,204 pool tokens, 8.40 GiB/card);
`[CW]` `…/2026-11-bug-radiance-27b-context-window/{DECISIONS,RESEARCH,STATE}.json/md` (D1–D19, D6,
D9(a) M≥8 bar, D10/D7 held memory, M9-A2 equality, parent-D27 jsonc protection; the D1 "factor 2,
524288, engine-validated" citation);
`[ROST]` `.agents/notes/radiance-multi-instance-roster.md` (five claimants / two cards);
`[FORM]` `charts/radiance/values.yaml:210-241` (serve FORM), `charts/radiance/tests/`
(testlib/receipt_gate legs), `tests/pipeline-models/surface.sh` M8/M9, `TEST_SPEC.md` §3.

**External anchors:** Qwen deployment docs via search — "vLLM implements static YaRN … scaling
factor remains constant regardless of input length, **potentially impacting performance on shorter
texts** … advise adding `rope_scaling` only when long contexts are required" (qwen.readthedocs.io,
vLLM-Qwen page; also qwen.ai blog: 1M "validated … using the YaRN method"); YaRN paper (Peng et
al., ICLR 2024, arXiv 2309.00071) — α is a continuous ratio; `attention_factor 1 + 0.1·ln α` is the
paper's mscale rule as re-implemented `[Y@t]`.

**Could NOT verify this round:**
1. That the v1.17.0 **binary** parses `yarn:1.5` — docs support it; no exec on our image was
   available. The boot echo + `rope: YaRN factor …` line (§1.6) is the receipt.
2. Any v4-dtype or YaRN measurement **on our rig** — the 25/32·22/32 ratios and all speed/KL rows
   are creator-rig (Gen5 x8/x8, 215–300 W) CLAIMED; our print confirmed only the fp8 baseline.
3. Tool-calling accuracy for the dtype change — the doc tables that move 0.17–0.27 KL are
   `--attn-prefill-fp8` rows; the dtype table's corpus is log-analysis docs. Nobody has scored the
   narrow layouts on agent transcripts.
4. Whether `prefix_hit`/tier bytes scale with the packed layout (tier holds *attention blocks*;
   §2.6's tier-token figures are DERIVED, print-gated).
5. The prior round's `[S6]` root-path `GUIDE.md@v1.17.0` (345,752 B) — that URL form 404s today;
   only `main` exists as a branch (tags list verified: v1.17.0 … v2.2.0). All pin citations here
   resolve under `docs/` at `/raw/tag/v1.17.0/`. No conclusion this round depends on the 404'd file.
6. Slot count / pinned-host growth for a 393,216-token session (`geometric-backoff keeps 9 for a
   262144-token session` is MEASURED; the 393,216 value is not printed anywhere — §2.7 bounds it).
7. A phantom directory listing observed mid-round (`ls` showed a 22:48-dated RESEARCH.md at this
   deliverable's path ~16 min in the future; the folder did not exist on re-check or to the read
   tool). Treated as noise; this file is the first write, and if it collides with a concurrent
   writer the merge is the coordinator's call.

## §P — Perspectives (derived, not a stock cast)

| # | Lens | What it sees | Its conflict |
|---|---|---|---|
| P1 | RoPE-extension mathematician | factor is a continuous α; 1.5 is legal; over-scaling trades short-context resolution for reach | vs P3: the engine's *validated* set is factor 2 only; "legal" ≠ "receipted" |
| P2 | KV-pool actuary | pool tokens are one budget: window×sessions invariant; dtype is the only in-rule token buyer | vs P4: wants a funded matrix the gate can print; seqs-5-on-fn still fails his bar |
| P3 | Docs-lawyer (branch separation) | 2.x refuses v4 and our packs; every `main` number is evidence about a different build | vs everyone: forces boot-print receipts for anything the pin's docs merely permit |
| P4 | Chart/test-contract auditor | FORM-fixed seqs/dtype are one file:226-228; the receipt gate's ambiguity rule breaks first | vs P2/P5: any per-lane knob is a chart-wide mechanism edit with named red legs |
| P5 | Owner-capacity auditor (rulings-vs-print) | C04 is still open on all four lanes; this ticket stacks two more unruled changes on a live default route | vs all: nothing here may move held memory, fn's ranks, or the jsonc bytes unilaterally |

---

## §1 — G1 verdict: 1.5× YaRN at v1.17.0

**Verdict: IMPLEMENTABLE AS ASKED — with one substitution strongly recommended.** The feature is
not merely "supported": fractional factors are legal by every surface fetched, the packs are in
exactly the state the runtime override exists for, and no conversion is required. The reservation is
about *validation*, not capability: the engine validated **factor 2**, and factor 1.5 would be a
first.

### 1.1 Syntax at our pin (CLAIMED — `[G@t:2071]`, `[Y@t]`)
- Flag: `--rope-scaling SPEC`, default "the checkpoint's"; `SPEC` =
  **`yarn:FACTOR[:ORIG]`** — field order FACTOR then ORIG, ORIG optional (`none` disables a
  checkpoint's YaRN). Confirmed at the pin's config table `[G@t:2071]`; `[Y@t]` gives the worked
  serve example `radiance --model … --rope-scaling yarn:2 --max-model-len 409600`.
- At `main` the same feature is tabled as a **config key** `rope-scaling: SPEC` `[G@m:2645]` — do
  not copy `main`'s YAML spelling into our env-fed FORM. (Branch law: the mechanism is stable
  across branches; the *interface shape* is not.)

### 1.2 Fractional factor: YES, not integer-only (CLAIMED — `[Y@t]` metadata table, `[O@t]`)
The rotary-object metadata table defines `factor` as "**finite number >= 1**, required for YaRN";
`beta_fast/slow` carry inequalities but no integrality; the engine's `attention_factor` default is
`1 + 0.1·ln(factor)` (continuous). The kernel contract passes `yarn_factor`/`yarn_low`/`yarn_high`/
`yarn_magnitude` as **f64** `[O@t]`, and `truncate` (default true) floor/ceils the ramp bounds so
fractional factors yield integer correction bounds. **No source says integers only.** Consequence:
1.5 → rotary reach 262,144 × 1.5 = **393,216** is expressible exactly as asked. Residual risk:
the CLI string parser (`core/format/rope_override.h`) is tested at factor 2 integers; nothing
executed `yarn:1.5` on our image — the boot receipt (§1.6) adjudicates. Label: CLAIMED-legal,
receipt-pending.

### 1.3 The packs' native bound — the feared blocker is REFUTED (CLAIMED, `[Y@t]`; MEASURED config)
The base `Qwen/Qwen3.8-27B` config carries `max_position_embeddings: 262144` and **no rope_scaling**
(CW S3, re-cited); `[Y@t]` goes further than permitting this case — it *names the container*: "For a
Qwen3.8 container that is `text_config.rope_parameters`, which already says `default`; YaRN written
under plain `rope_parameters` would never be read." A `default` (or absent, or legacy `mrope`)
rotary object is "no scaling", and `--rope-scaling yarn:F` writes into the first object the reader
takes — no reconvert, no new pack. The fn scout's `mrope=unrotated` reading is consistent: legacy
`mrope` is a no-scaling state `[Y@t]`. So: **runtime scaling is the designed path for exactly these
packs**, and `ORIG` is **not required** — it defaults to "the container's own trained length"
(262,144), which is the number we want preserved. Stacking is refused (`linear`/explicit types are
refused, not stacked; `mscale`/`mscale_all_dim` keys refused — use `attention_factor`).

### 1.4 Validation state and accuracy cost (CLAIMED + DERIVED)
- **Validated set `[Y@t]`:** Qwen3.8-27B, Qwen3.6-35B-A3B, and **both Flash-Next variants at factor
  2**, with retrieval at ~500K tokens and TP3 perplexity within ±1% of unscaled; test contract pins
  correction bounds to vLLM's integers *at factor 2* (56/85 at rotary width 256, θ 1e7, 262144
  trained) and reference-compares angles to 524,287. `[Y@m]` adds only Muse Glimmer @8 over 131,072.
  **Factor 1.5 is validated nowhere, on no model, in either branch.** The doc's own law: "Whether
  the extension keeps useful accuracy must be measured on the model and workload."
- **1.5×-vs-2× shape argument (DERIVED, P1):** serving exactly 393,216 under `yarn:1.5` puts the
  longest request at the **extreme edge** of the scaled map (position 393,216 ↔ effective 262,144 =
  the trained bound) — the worst-position regime, and one the engine's validation never probed
  (they validated *at* 524,288 under factor 2, which is the same relative edge, but only there).
  `yarn:2` serving 393,216 keeps every position ≤ effective 196,608 — comfortably inside the
  validated envelope, on a validated factor, and is the pattern the doc's own example ships (409,600
  served under a 524,288 map). Costs: attention_factor 1.0693 vs 1.0405 `[Y@t]` default formula, and
  coarser low-frequency resolution at short lengths.
- **Short-context cost of ANY static YaRN (CLAIMED, Qwen deployment docs):** "static YaRN … scaling
  factor remains constant regardless of input length, potentially impacting performance on shorter
  texts … add rope_scaling only when long contexts are required." Our agent workload mixes 2K-tool-
  result turns with 130–250K chains — a rope-scaled lane pays a small, unquantified tax on every
  short turn. The doc's mitigation is behavioral (separate lane), which is what the owner's new pod
  already is.
- **Tool-calling accuracy:** NO YaRN quality data exists for tool-calling on this family. The
  tool-calling figures the launch associates with this change (KL 0.17–0.27, top-1 91–93%) are
  `--attn-prefill-fp8` rows `[G@t:958-965]` — a **different flag**. Do not fold them into the YaRN
  decision; do not stack the two lossy choices on one route without a quality read (§8).
- **Vision legs unaffected:** the vision tower keeps its axial rotary; axial+YaRN is refused only
  for the target `[Y@t]`.

### 1.5 Prefix cache / position / step-cost effects at the same KV budget (DERIVED, prints govern)
- **Pool funding** falls with any window increase — the whole of §2.
- **Host prefix tier** (`--prefix-cache-mib 4096`, 131,072 tokens at fp8 `[E27 §6]`): YaRN does not
  change tier math; a dtype move does (tier holds attention blocks at the cache's per-token bytes) —
  §2.6.
- **Checkpoint store:** auto slots are `seqs × (kept-per-conversation + 1)`; kept grows
  logarithmically with conversation length (9 at 262144 @2048 interval, MEASURED) — at 393,216
  expect 10–11 kept ⇒ slots ≈ 88–96 and pinned store ≈ 13.2–14.3 GiB vs today's 11.98
  (153.38 MiB/slot, MEASURED) — inside 24Gi with the embeddings (2.36) + tier (4.0), but **the
  thinnest the host plane has ever been; boot-print gated** (§2.7).
- **Decode/prefill attention cost grows with context:** dense trunk reads the whole history; on the
  prior round's calibrated model (§2.1 of [E27] RESEARCH: 48.6 + 0.196608·P GFLOP/token) a
  full 393,216 prefill is 125.9 GFLOP/token vs 100.1 at 262,144 → **−20% cold-prefill rate at the
  ceiling** (docs-class 2,313 → ~1,850 t/s at 185k-equivalent class; DERIVED, same model that
  reproduced the docs' anchors to 1.3%). The window purchase has a TTFT-tail price on exactly the
  giant cold prompts this lane exists to accept.
- **Positions:** RoPE-only (no learned position table to resize); `qsa_block_key` ops accept the
  yarn coefficients `[O@t]`; the drafter gets the same factor over **its own** trained length
  `[Y@t]` (acceptance impact unmeasured — open).

### 1.6 The receipt (what the boot must print for G1 to count as landed)
`radiance serve: composed engine argv: … --rope-scaling yarn:<F> …` plus `[Y@t]`'s startup line,
verbatim format:
`rope: YaRN factor <F> over 262144 trained positions -- the rotary reaches <F×262144>;
--max-model-len 393216 (--rope-scaling)` — no warn line (393,216 ≤ the rotary reach under either
factor). Absence of the `rope:` line = the override never applied.

---

## §2 — G2: the funding matrix, with units and the blunt verdict

### 2.0 Formula and held constants
All figures are **GiB per card** on the **q27-TP2 (dense, `qwen35_fp8`) geometry**, at the HELD
envelope — no memory move (D7/D10/D28(6)/P11):

```
per-token/card (fp8)   = 16 KiB                     [MEASURED boot pool arithmetic, E27 §7]
per-token/card(d)      = 16 KiB × r_d                [CLAIMED ratio law G@t:937-939; DERIVED product]
   r_fp8 = 32/32,  r_fp8_v4 = 25/32,  r_k6_v4 = 22/32
per-session(C,d)       = C × per-token/card(d) + 148 MiB      [state unchanged by dtype — G@t:932-936]
pool-for-context       = 22.24 − 0.09 = 22.15 GiB/card        [MEASURED decomposition E27 R§4.1]
M(C,d)                 = 22.15 / per-session(C,d)             [the print's "full-length sessions"]
backing(N%, seqs)      = 22.15 / (seqs × per-session)         [the print's "N% of the worst case"]
```
Validation: the formula reproduces the lane's real print — fp8@262,144@8 → **M 5.34 / 66.8%**
against printed **5.3 / 66%** — so it is the engine's own accounting, not a re-guess. (The doc's
alternative reading of `M` is "compare M with the sessions you expect to keep live" `[G@t:1017-1020]`
— not necessarily `M == seqs`.)

### 2.1 Per-token KV bytes (current dtype `fp8`, and the two v4 layouts)

| dtype | KiB/token/card | KiB/token lane | GiB @ 262,144/card | GiB @ 393,216/card |
|---|---|---|---|---|
| `fp8` (today's FORM) | 16 | 32 | 4.000 | 6.000 |
| `fp8_v4` | 12.5 | 25 | 3.125 | 4.6875 |
| `k6_v4` | 11 | 22 | 2.750 | 4.125 |

(MEASURED fp8 row; CLAIMED ratios × measured base for v4 rows. "Lane" = both TP2 ranks' shards.)
Session-count vs rate figures never mix here: every §2 number is **bytes**, and M is a derived
count, never an input.

### 2.2 Worst-case pool matrix, q27-TP2 — M and backing by (seqs × context × dtype)

| dtype | context | seqs | worst-case need GiB/card | backing % | M (funded sessions) | funded? (M ≥ seqs) |
|---|---|---|---|---|---|---|
| fp8 (today) | 262,144 | 8 | 33.16 | **66.8** (print 66) | **5.34** (print 5.3) | ✗ (−2.7) |
| fp8 | 262,144 | 5 | 20.72 | 100 (106.9) | 5.34 | **✓** |
| fp8 | 393,216 | 8 | 49.16 | 45.1 | 3.60 | ✗ |
| fp8 | 393,216 | 5 | 30.72 | 72.1 | 3.60 | ✗ |
| fp8_v4 | 262,144 | 8 | 26.16 | 84.7 | 6.77 | ✗ (by 1.2) |
| fp8_v4 | 262,144 | 5 | 16.35 | 100 | 6.77 | **✓** |
| fp8_v4 | 393,216 | 8 | 38.66 | **57.3** | **4.58** | ✗ |
| fp8_v4 | 393,216 | 5 | 24.16 | 91.7 | 4.58 | ✗ (by 0.4) |
| k6_v4 | 262,144 | 8 | 23.16 | **95.7** | **7.65** | ✗ (by 0.35) |
| k6_v4 | 262,144 | 5 | 14.47 | 100 | 7.65 | **✓** |
| **k6_v4** | **393,216** | **5** | 21.35 | **100** (103.8) | **5.19** | **✓ — the only funded 1.5× shape** |
| k6_v4 | 393,216 | 8 | 34.16 | 64.8 | 5.19 | ✗ |

(DERIVED from §2.0; all conditions: q27-TP2 TP2 dense geometry, 22.15 GiB context pool/card, held
24Gi host, creator-untouched `--prefix-cache-mib 4096`, drafter fp8-plane unchanged. Note the
38.66 GiB worst-case row: `fp8_v4@393,216@8` needs **more cache plane than the whole claimable
card** (30.73) — with 8.50 GiB weights the shape is unbuildable at 100%, as the backing % says.)

### 2.3 The fn (flash-TP2) lane at the owner's seqs 5 (MEASURED pool, DERIVED bar)
fn is the live default route; its geometry differs (7.3125 KiB/token/card fp8, 8.40 GiB/card,
1,080,204 pool tokens — `[EF]` §7). Lowering its FORM seqs 8→5 changes the **denominator and the
bar, not the pool**: backing 52% → 82.4%, and the D9(a)/D16 bar becomes **M ≥ 5** — printed
M ≈ 4.1 < 5, so **fn remains refuting at 5 sessions**; only `seqs ≤ 4` makes fn's print pass.
(If fn ever moved dtype: `fp8_v4`→M ≈ 5.1, `k6_v4`→M ≈ 5.7 at 262,144 — §3 notes why its QSA share
does not shrink; not asked, not recommended.)

### 2.4 q27-TP1 and flash-TP1 rows (print-pending, DERIVED class)
Single-card q27 at 262,144 pays 32 KiB/token/card (no KV split): Wilde-class pool 12.46 GiB →
**M(fp8) ≈ 1.5, M(fp8_v4) ≈ 1.9, M(k6_v4) ≈ 2.2** — a TP1 lane funds one-to-two full-length sessions
at ANY in-family dtype, 26–44% of a 5-seqs worst case; at 393,216 all three fall ≤ 1.5. C04's
predicted-not-to-fit leg stays as ruled; seqs-5 does not rescue TP1. (This is also why an
`-fp8_v4` **TP1** variant is a *capacity* pod, not a concurrency pod — §5.)

### 2.5 What the print must show to count as funded
Per D9(a) as generalized by D16 (receipt gate: read `M` per lane against the lane's
**configured** seqs, refuse on absent/unparseable, `N% < 100` is an owner-read warning, never a
machine bar): **`M ≥ configured seqs` AND `N% ≥ 100`** (they are the same inequality against the
pool); `M` is engine-self-reported, so the first boot of any new shape calibrates the greps (D16
limit 1). Today's measured reality — 52%/4.1 and 66%/5.3 at 8×262,144 — means any shape in §2.2
marked ✗ will print a warning line, and any new lane landing < its seqs is the same
ruling-vs-arithmetic item the last ticket ended on, re-paid at a different exchange rate.

### 2.6 Tier side-effect of the dtype move (DERIVED, print-gated)
The host tier stores attention blocks at the cache's per-token bytes `[G@t §4.8]`:
4,096 MiB holds **131,072 tokens at fp8** (MEASURED boot W-line), ≈ **167,772 at fp8_v4**,
≈ **190,650 at k6_v4** — i.e. the narrow layouts *increase* tier coverage (53%/73% of a
393,216-token conversation, up from 33%) and bring the "8193 MiB would hold one" warning toward
"this tier holds one" at 262,144 (6,554/5,760 MiB needed, DERIVED).

### 2.7 If a later print moved held memory — what would have to be true (stated, not proposed)
Nothing here re-pins 110Gi/24Gi (D7/D10/D28(6)/P11 — prints, not estimates). What the *cgroup
envelope* would have to keep true if a print ever moved it: on the 24Gi lanes the printed pinned
legs must satisfy `limit − printed-pinned ≥ 4` (repo law). At seqs 5 the checkpoint store *shrinks*
by ruling of the auto law (`each of --max-num-seqs gets what checkpoint-policy keeps + 1`
`[G@t:1694-1702]`): 5×10 = 50 slots ≈ **7.49 GiB** vs today's 80×153.38 MiB = 11.98 (MEASURED) —
the existing 27b lanes gain ~4.5 GiB of host slack; on the new 8×393,216 lane it *grows* (§1.5) to
~13.2–14.3 GiB, putting printed-pinned ≈ 15.6–16.7 + tier 4.0 ≈ **19.6–20.7 of 24 Gi** — thinner
than the measured 19.73 peak, still under the leg law, but the first lane whose host budget, not
its card pool, would be the marginal constraint.

### 2.8 — THE BLUNT G2 VERDICT
**`fp8_v4` at 1.5× context with `--max-num-seqs 8` is a regression versus today, on the one axis the
request was motivated by.** Today's lane funds 5.34 full sessions (66% backing); the combination
funds **4.58** (57%). The owner's reasoning is exactly right and the numbers are above: window ×1.5
demands 50% more pool tokens than today; `fp8_v4` supplies 28% (`k6_v4` 45%); the dtype gain is
erased with a loss (net 1.17× / 1.03× worse). The lane additionally runs ~20% slower on cold
full-window prefills (§1.5), at an unvalidated YaRN factor if 1.5 is used, and its worst case exceeds
the physical card. **What is NOT a regression:** the *aggregate context in flight* is pool-token
invariant (same 22.15 GiB either way) — the dtype lever buys tokens, and §7 shows the only
allocations of those tokens that fund. If the goal is "hold at least as many full-length sessions
AS today while serving 1.5× windows," no in-family dtype at 8 seqs does it on 2×R9700; something
must give — §7 lists what.

---

## §3 — G3: what the dtypes are, and per-lane dtype mechanism cost

### 3.1 Definitions (CLAIMED, verbatim from `[G@t:929-941]` — correcting the launch's guess)
- `fp8`: E4M3 cache with per-(sequence, head) descales; halves a token vs bf16; "a real
  quantisation that changes the output slightly."
- **`fp8_v4`: K stays E4M3 (8-bit), V becomes int4** — groups of 32 dimensions with an f16 scale
  each. Token = **25/32** of fp8.
- **`k6_v4`: K becomes int6, V stays int4** ("stores K as int6 too"). Token = **22/32**.
- **The owner's guess is wrong in both parts:** k6 is not "6-bit K / 8-bit V" (V is 4-bit); fp8_v4
  is not an "8-bit V variant" (it is an 8-bit **K** / 4-bit **V** — the "v4" names the V width in
  both).
- Unchanged by either: the drafter's cache ("stays fp8"), the delta-net recurrent state, and the
  QSA indexer's key cache ("its share of a token does not shrink" — the fn-lane figures in §2.3).
- Availability is plugin-scoped: libr4d ships the kernels for **Qwen3.8-27B** (`qwen35_fp8`,
  head_dim 256, gqa 6) **and Qwen3.8-Flash-Next** (`qwen4exp_fp8`); "the server refuses them, naming
  the plugin, anywhere else." A packed cache also turns off `--kv-resident` streaming `[G@t:1055]`
  (moot for our dense lane, which cannot stream anyway).

### 3.2 Measured accuracy/speed profile, with conditions (CLAIMED, `[G@t:942-953]`)
Creator rig, 2×R9700, TP2, at `qwen3.8-27b-mxfp4.yaml` serve flags + `--max-num-batched-tokens
2048` + **12 GiB/card left to another engine** (so its pool ≈ our elastic scale), scored against
the bf16 model on **17 long log-analysis documents, 60,368 scored positions**:

| dtype | KV pool tokens | mean KL | top-1 | 41k prefill | decode 1/16 streams |
|---|---|---|---|---|---|
| fp8 | 518,800 | 0.039963 | 94.03% | 9.76 s | 134-140 / 550-555 t/s |
| fp8_v4 | 664,400 (+28%) | 0.040076 | 94.03% | 9.76 s | 130-139 / 553-557 |
| k6_v4 | 755,184 (+46%) | 0.039965 | 94.06% | 9.84 s | 136-138 / 553-561 |

Read with the brief's conditions rule: **the pool column is bytes-backed and transfers to our rig by
ratio (25/32, 22/32 — our §2 matrix); the prefill column shows NO dtype speed win (9.76/9.76/9.84
s); decode is at run-to-run spread.** The "fp8_v4 = +12% long-prompt prefill" carried in the launch
is the *separate* `--attn-prefill-fp8 both` row measured over fp8_v4 (221k prompt: 2,666 → 3,097
t/s, i.e. +16.2%; 24k: 4,636 → 4,778, +3.1% `[G@t:982-983]`) — that flag is lossy
(q/e4m3 attention math), its eval ran at **`--max-num-seqs 5`** on the same rig, and its measured
worst movers are **tool-calling/SWE transcripts, KL 0.17–0.27 at 91–93% top-1** `[G@t:958-977]` —
our workload exactly. Stacking dtype + `attn-prefill-fp8` + `wht6` (already on) is three
unreceipted output-bit purchases on the agent route. **Recommendation-relevant fact: `k6_v4`
dominates `fp8_v4` on the doc's own table** (+46% vs +28% pool, equal KL/top-1, equal speed) —
if the choice was made on the funding number the prior round derived (7.7 vs 6.8), the name
`-fp8_v4` should be reconsidered as `-k6v4`, or the owner accept paying the window for something
else. (Open: tool-calling accuracy of the *layouts* — the KL table is log-analysis corpus; the V
int4 of both layouts was never scored on agent transcripts, though its incremental move over
today's fp8, which already stores V at 8 bits, should be small — DERIVED, unvalidated.)

### 3.3 Making dtype per-lane (mechanism, MEASURED from repo)
Today `--kv-cache-dtype fp8` is FORM-fixed `[FORM:226-228]`; no env channel exists; the suite
reds any lane that smuggles the flag through env (dual-channel rule, testlib :1197) and
`FORM_FIXED_FLAGS` (:970-974) asserts the fixed byte. Per-lane dtype = **one chart edit + the
test-wave that follows it**:
1. serve FORM: `--kv-cache-dtype fp8` leaves the fixed pair; becomes
   `[ -n "${RADIANCE_KV_CACHE_DTYPE:-}" ] && …` **with an explicit `fp8` fallback** (the absent-
   env-means-absent-flag law would otherwise silently drop resting lanes to the engine's `bf16`
   default `[G@t:2079]` — 2× the bytes on a parked lane, caught only at next boot).
2. testlib: dtype exits `FORM_FIXED_FLAGS`; enters every lane profile (`FULL_PROFILE:145`, q27
   :309, new-lane `q27_v4_profile()`); a new "resting lanes keep fp8" leg to make the fallback
   machine-verified.
3. New-lane profile + values subtree env + boot-echo receipt expectations; notes-suite T2 blocks
   that quote the composed vector (q27-boot Step-3 witness, runbook profile list) re-pin.
4. Docs law: v4 dtypes are refused **on 2.x** `[G@m]` — a chart that carries
   `RADIANCE_KV_CACHE_DTYPE: fp8_v4` silently pins this deployment to the 1.x line; the values
   annotation must say so.
Blast radius: all four existing lanes re-render (their composed argv changes only if they set the
env — with the fp8 fallback they do not), so the receipt legs re-green without new boots; the new
lane's boot print is the dtype receipt (`kv: the pool backs …` should land near §2.2's prediction;
the `page 256.00 KiB` line should shrink to 200.00/176.00 KiB per 16-token block — DERIVED check
the print enables).

---

## §4 — G4: cost of per-lane `--max-num-seqs` (named legs, and what a reviewer needs on fn)

### 4.1 Mechanism
Same class as §3.3: FORM line `charts/radiance/values.yaml:226-228` fixed `--max-num-seqs 8` →
`RADIANCE_MAX_NUM_SEQS` env-fed **with an `8` fallback** (the engine default is **256**
`[G@t:2069]` — an absent-env-means-absent-flag lane edit would size the worst case at 256×context
and change admission/queue math wholesale; the fallback is mandatory, and must be suite-pinned).
D6's ruling ("8 stays, because changing it invalidates the receipt this ticket exists to capture")
is **an argument for doing this deliberately with its own receipts, not against the mechanism** —
but note the receipts C04 still owes have not been taken yet: the seqs wave would land *before*
the first per-lane prints of the current shape. The clean sequence is: owner runs the owed D8
receipt block at the next scale act (current shape), THEN the seqs/dtype lane lands — otherwise no
baseline print exists to compare the new prints against.

### 4.2 Named files and test legs (MEASURED inventory, this worktree)
- `charts/radiance/values.yaml:226-228` — the FORM fixed pair (seqs + dtype).
- `charts/radiance/tests/radiance_testlib.py` — `FORM_FIXED_FLAGS` :970-974 + guard :985-988 +
  dual-channel :1197; `FULL_PROFILE` :141; q27 profiles :309; four-lane roster maps `LANES` :715,
  `COMPOSITION_LANES` :1051; :93's comment that seqs "is FORM-fixed … the lane may not size it at
  all" becomes stale (annotate, never rewrite).
- `charts/radiance/tests/test_c03_generic_shell.py` — FORM-flag parametrisation legs :173-209,
  fixed-flags tuple :521 ("all four lanes per flag" equality becomes per-lane).
- `charts/radiance/tests/receipt_gate.py` — **breaks structurally**: `_SEQS_RE` (:253) reads the
  chart's configured seqs and REFUSES on two distinct values (:278 "ambiguous --max-num-seqs …
  the M bar cannot be evaluated"), which is exactly what a per-lane FORM produces. Must be re-cut
  to resolve **per lane** (chart fallback + the lane's env), with `test_receipt_gate.py`'s
  "bar follows the FORM" (:229-236) and "two distinct = ambiguous" (:240-247) legs re-pinned
  (test authority first — parent-D30).
- Receipt block wording: item 3 "M >= the FORM-fixed --max-num-seqs … (all four lanes)" (:80) and
  the PASS banner (:410) re-pin to per-lane bars; D9(b)'s **eight-admitted-sessions smoke** becomes
  a five-admitted smoke on fn (`FN_LANE` :63).
- `tests/notes/radiance-runbook.sh:278` — regex needle `max-num-seqs…8|8 sessions|8 concurrent` in
  the acceptance note: doc half + test half (the D12 lesson: assign both by name).
- Catalog side: `surface.sh` M8 legs do **not** pin seqs (they pin ctx/priority) — no M-leg churn
  from seqs alone; `TEST_SPEC.md` prose that names "configured 8" (D15/D16 records) annotated.
- Docs-law effects of seqs on the engine's own numbers (CLAIMED `[G@t]`): default
  `--max-queued-requests` = 8×seqs → **40 at 5** (429-class pressure changes); `--max-n` =
  max(8, seqs) stays 8; checkpoint-slots auto → seqs×10 (§2.7); and the `wht6` law ("decode steps
  above the row count startup names are all-reduced lossily") means a 5-row lane crosses the lossy
  threshold *less often* — a small accuracy *win* at 5.

### 4.3 What a reviewer needs to call the fn-lane leg safe (live default route)
fn is every tier + the hourly runner (parent-D16; [ROST]): the seqs-5 edit on fn changes
admission width (64→40 queued), the D9(a) bar (8→5 — and §2.3 says fn's M 4.1 still refutes at 5,
so the reviewer must not be sold "5 fixes funding": it doesn't), and the receipt the P11-carrying
bring-up is still owed. Reviewer's evidence set: (a) the owed C04 print of the CURRENT shape,
quoted into DECISIONS, before this change; (b) composed-argv echo of the new boot; (c) the new
`pool backs N% … M` line against **M ≥ 5** (D16-style per-lane read — post-gate-rewrite); (d) a
five-concurrent admitted-session smoke replacing D9(b)'s; (e) the roll window stated (D9(c)); (f)
`AISLOP`/battery green with the four named test legs re-pinned first. Without (a)–(e) this is
exactly the "unproven value on a live route" class D19 flagged, again.

---

## §5 — G5: the fifth radiance release on a two-card pool (sixth claimant overall)

The roster today is **five claimants** (4 radiance releases + parked strata) on `amd.com/gpu-r9700`
count 2 [ROST]. The new pod makes it **six claimants / five radiance releases**. The launch's "5th
claimant" framing matches the release count; the roster heading ("five claimants, one pool of two")
must be re-titled with its row set — [ROST] is machine-tied (`tests/notes/radiance-roster.sh` T2
re-derives every claim count and replicas value from the tree, so a lane added without a roster row
is red by construction — this is the note's own drift law).

**Claim count depends on the lane's width:**
- **TP2 shape (the concurrency story §2 assumes): claim `"2"`** — the new lane takes BOTH cards
  alone; while fn is UP it Pends; while it is UP everything else Pends. It is a swap sibling of
  q27-TP2 (same pack `qwen3.8-27b-mxfp4.rad` — shared marker → boot-skip, no second 18 GiB fetch).
- **TP1 shape: claim `"1"`** — pool-wise it can stack beside q27 (1+1=2) or claimed strata (1+1=2);
  RAM-wise only **q27(24)+new(24) ≤ 125.08** co-boots (both held-class pairs), and only with fn and
  strata DOWN. But §2.4: TP1 funds ≤ 2 full-length sessions at any dtype — as a `-fp8_v4` lane it
  would be a *big-single-window* pod (or a 200K-class conservative pod), not an 8-session pod.
- Resting state either way: `replicas: 0`, flip by owner scale act only; peers hop 502-loud while
  parked; never a default; runner literal untouched.

**Exclusivity-table additions (the [ROST] steady-state table, post-edit rows that must say):**

| UP set | claims on 2 | verdict |
|---|---|---|
| new-TP2 alone | 2 | YES — takes both cards, everything else Pends |
| new-TP2 + anything (incl. q27-TP1) | >2 | **NO — never attempt; the Pending pod is the failure, not a delay** (plugin claims are integer counts, no overcommit — `[S6-of-tp2-note]`) |
| fn + new (any widths) | ≥3 | NO (existing law, restated for the new lane) |
| q27 (1) + new-TP1 (1) | 2 | pool-wise YES; RAM-wise YES at held 24+24 — the ONLY two-radiance co-boot at held values; fn must be DOWN first |
| new-TP1 + strata | 2 | pool-wise YES; RAM-wise NO at held 110+24 (existing shape, new instance) |

**What the roster/ApplicationSet must add (per lane, MEASURED mechanism):** `charts:` entry in
`services/gpu-ai/prod/values.yaml` (`namespace: default`, `ServerSideApply: "false"`,
`chart: radiance` — the base appset derives Application `gpu-ai-radiance-<key>`); the per-release
subtree (modelPath/radianceFetch/fetch scalars + env list + request==limit pair + claim, the
:1629-1734 shape); a `peers.<lane>` hop in the llama-swap block (no `/v1` suffix, timeouts
1800/30, `filters.setParams "priority?"` = the lane's own default class — §6); a per-key evidence
YAML (`charts/llama-swap/tests/evidence/radiance-<lane>-peers-expected.yaml`, D13 law) —
which **reddens three exact-set legs**: `test_config_parity.py:337`,
`test_flashnext_blast_radius.py:217`, `test_radiance_peer.py:130` all assert
`{strata, radiance, radiance-q27, radiance-flash-tp1, radiance-q27-tp2}`; plus testlib `LANES`/
`COMPOSITION_LANES`/`NEW_LANE_NAMES`, `receipt_gate.LANES` (four→five; "D8: a lane-count change
lands in both"), the roster note row + T2, and the M8-A2/D19_BASE_KEYS re-freeze (§6).
**Naming:** the release/Application name must be RFC1123 (`radiance-q27-fp8-v4` /
`radiance-q27-k6-v4` — underscores are illegal in object names); the served id may keep the
underscore (`qwen3.8-27b-radiance-fp8_v4`) since it is an env string, but then catalog key, served
id, and release name differ by spelling and every leg that maps them must say which.
**Belongs in the existing fleet roster: yes** — [ROST] is the single prose authority and is
machine-tied to the tree; a second roster note would be the drift class.

---

## §6 — G6: `opencode.jsonc` (owner-protected surface) — requirements, not authorization

**Parent D27 stands: the catalog bytes are the owner's** (M8-A's own error text: re-pinning the
context values is "an owner act, not a ticket act"). "Update all these models in opencode.jsonc"
specifies a **diff to hand the owner** (plus a test wave that re-pins the legs), never a licence for
an agent to hand-edit the file. What the rows must satisfy:

1. **New trio** (base/`-urgent`/`-low`, shared modelID, only `body.priority` differs) for the new
   lane, registered in the D19 ladder order: five lanes now. The §3 arithmetic: `urgent`/`default`
   columns are cross-lane **pairwise-unique and strictly decreasing in lane rank** → new urgent
   ∈ {5,4,3,2,…} (unique within its own column), new default ∈ {1,0} (below 27b-TP2's 2), and low
   must be strictly below its default with no negatives (M9-A2 bars them; the C05 round already
   rejected the negative-rung ladder and left `priority-0` semantics UNVERIFIED as q27's property).
   If new default = 1, low can only be 0 — **which ties q27's low 0**: legal only if named in
   `ACCEPTED_LOW_TIES` (the suite reddens any *unnamed* second tie; today's accepted tie is
   fn-low-1 ≡ 27b-TP2-low-1, justified per-lane by "four engines, four separate queues, floors are
   per lane" — the justification extends to five). **There is no collision-free fifth trio under
   the current laws** — the ladder choice is: accept a second named low tie (e.g. 5/1/0), or rule a
   rank above 9 (breaks "strictly below live lanes"), or merge the new lane into an existing trio's
   ranks (breaks trio identity). Flag to owner as a ruling, §10 Q5.
2. **Peer floor law** (D-2): each lane's `peers.<lane>.filters.setParams "priority?"` = **the
   lane's own default-class row** — the new hop's floor must equal the new trio's default value
   (e.g. 1), never a borrowed fn/q27 rank; evidence YAML carries it.
3. **`limit.context`:** M9-A2 (re-pinned by CW D4/D11) — **catalog context must equal the lane's
   served `--max-model-len`; equality is legal now.** So:
   - If the new lane serves **262,144** (no YaRN): its trio is 262,144 and the twelve-row family
     figure stays uniform — cheapest catalog outcome, zero prose churn beyond the new rows.
   - If it serves **393,216** (YaRN leg): its trio carries 393,216, **breaking the family-uniform
     figure for the first time** and inverting the D47 pair-law's input (catalog prose today says
     "the trained 262,144 window the client budgets against"; served > trained requires the restated
     authority to be the *YaRN-reach* — 393,216/524,288 — with the validation cite, and TEST_SPEC
     §1's per-lane served column gains its first >trained row).
4. **The "unproven value on a live route" risk, named:** raising a trio's `limit.context` to 393,216
   tells every client session to budget a window the pod has never printed — prefill +50% slower at
   the ceiling (§1.5), and if the YaRN override silently failed to apply (parse risk §1.2) the
   client's 300K-prompt hits either the warn-not-refuse rotary cliff (degraded quality) or the loud
   400 past `--max-model-len`. The ordering law from CW D19 generalizes: **scale act → boot receipts
   (`rope:` line + `pool backs` line + near-ceiling admitted probe) → then the jsonc context leg**
   (the near-ceiling acceptance is receipt item 9's class, re-run at 393,216). Catalog rows for the
   OTHER four lanes do not move at all (their served figure is unchanged by a seqs edit).
5. **Mechanics:** the file is rulesync-adjacent but hand-managed (`AGENTS.md`:
   `.opencode/opencode.jsonc` is the dev half of agent config, version-controlled; provider model
   rows carry `limit.context`). Re-freeze obligations that a new trio necessarily breaks:
   `M8-A2`/`M9-B`'s frozen key-base deltas ("the live delta is exactly D19's six … a SEVENTH row
   reddens the leg") → test-authority re-freeze wave (CF143/D19 base gains the new trio), M8-A gains
   a fifth trio loop with the new ranks, `TEST_SPEC §3`'s table + ladder proof, and the M9-A2 prose
   half (both-figures needles). Battery: `surface.sh M8|M9` explicit legs + `agents-md.sh`/
   `rulesync-surface` untouched unless roster prose changes.

---

## §7 — The concrete configuration that meets the real goal (or the conflict statement)

**The goals, restated as one budget:** the owner wants (a) more concurrent funded sessions, (b) a
1.5× window, (c) the v4 dtype win. On a fixed pool, `sessions × window ≤ pool_tokens(dtype)`.
Today: 22.15 GiB ÷ 32 KiB = 713,600 tokens ≈ 5.34 × 262,144. dtype widens the numerator by 1.28×
(fp8_v4) or 1.45× (k6_v4) — **that is the entire budget**. A 1.5× window alone claims 1.5× of it.
**Under 2 cards and the held envelope, "more sessions AND a 1.5× window" is arithmetically
impossible at any in-family dtype** — §2.2's grid is the proof — so one of the goals must give:

- **Option A — concurrency first (recommended default).** New lane
  `radiance-q27-k6v4` (TP2, claim 2, pack-shared): `RADIANCE_KV_CACHE_DTYPE k6_v4`,
  `RADIANCE_MAX_MODEL_LEN 262144`, seqs **8** (per-lane env, §3.3/§4.1 mechanism); existing four
  lanes to seqs 5 with the **fp8 fallback in the FORM** (only the three 27b/flash lanes' env
  changes; fn's deficit stays explicit). Result: new lane prints **M ≈ 7.65 / ~96% backing** —
  **+43% funded sessions over today** (§2.2) — and is the only lane whose M ≥ 5-vs-8 bar has
  *margin*; no YaRN, catalog family stays uniform (cheapest §6). The window goal is deferred to
  Option B's receipt sequence, not silently dropped.
- **Option B — window first.** Same lane with the dtype move AND `RADIANCE_ROPE_SCALING
  "yarn:2"` + `RADIANCE_MAX_MODEL_LEN 393216`, but **seqs 5** on this lane too (not 8): prints
  **M ≈ 5.19 / funded at 5** — §2.2's only funded 1.5× shape — on the *validated* factor with the
  served window a third inside the rotary reach (the doc's own pattern `[Y@t]`). Concurrency then
  equals today's per-lane reality (fn runs 4-5, q27 ran max 7), not today's *promise* of 8.
  Catalog takes the §6.3 context-393216 leg, receipts first (§6.4).
  If the owner insists on 8 seqs with the 1.5× window: the honest print is **64.8% / 5.19** (k6_v4)
  or **57.3% / 4.58** (fp8_v4) — an explicit-deficit shape, i.e. today's D1+D6 price paid twice.
- **Option C — neither, if §1/§3 receipts disappoint:** just the seqs-5 wave on the existing lanes
  (q27 pair becomes fully funded, 106.9%; fn remains 82%/4.1 — and per §4.3 that should be
  *ruled* as an accepted deficit, not shipped as a "fix"), plus `k6_v4` on the existing q27-TP2
  lane (no new pod, dtype via the same FORM channel) → 7.65 sessions on the lane that exists today,
  minus a pod-swap row, minus a catalog trio, minus a ladder ruling. Cheapest path to the
  concurrency the original finding was about.

**What must give, plainly:** at `fp8_v4`+`yarn`+8-seqs (the request as literally composed), the
funded-session count gives (5.3 → 4.6), and the gate will print the warning line to prove it.
`k6_v4` is the better name for either option on the doc's own table. Memory gives nothing (§2.7);
the third card is the only outside-envelope buyer of "both", and cf-143-class hardware moves are
owner-lane.

## §8 — Non-recommendations (each with its reason)

1. **Do not adopt `--attn-prefill-fp8` on the strength of the mis-read "+12%."** The dtype carries
   no measured speed; the speed is the lossy-attention flag; our workload is its worst-moving
   category (KL 0.17–0.27 tool-calling `[G@t]`) and the lane already runs `wht6` unreceipted for
   quality (C9 below). Needs its own eval, not this ticket's enthusiasm.
2. **Do not use `yarn:1.5` as the first factor on this image** while `yarn:2` is the validated pair
   and the docs themselves serve 409,600 under factor 2. Legal ≠ receipted (§1.2/§1.4).
3. **Do not let the absent-env law bite the new FORM channels:** seqs and dtype envs need explicit
   fallbacks (8 / fp8) or a quiet resting lane reboots at `256` seqs / `bf16` (§4.1, §3.3 — the
   engine defaults are the hazard, not the edit).
4. **Do not touch 110Gi/24Gi** (D7/D10/D28(6)/P11); §2.7 states the envelope facts only.
5. **Do not hand-edit `.opencode/opencode.jsonc`** in a ticket session (parent D27); ship the spec +
   test wave, the owner lands the bytes; context legs follow the receipts, never precede them
   (§6.4 — the D19 lesson).
6. **Do not read this plan onto 2.x:** upgrade-temptation aside, 2.x refuses `fp8_v4`/`k6_v4`,
   refuses `fp8` on most plugins, refuses our MXFP4 `-fp8.rad`/`-mxfp4.rad` containers by name, and
   the family's own 2.0.0 witness (#457, open) reports −30%/2×-step; any move to i8/2.x is a
   separate, from-scratch ruling `[G@m]`, `[Y@m]`, `[I457]`.
7. **Do not lower q27-TP2's seqs to 5 AND expect the D9(a) story to close** — the bar is
   read-per-lane; §2.2 says fp8@5 funds (106.9%) and the receipt will say so, but fn@5 does not
   (M 4.1 < 5, §2.3) and the smoke must follow the new widths (§4.2).
8. **Do not ship the seqs/dtype wave before the C04 prints the current shape owes** (§4.1) —
   otherwise there is no baseline print to price the change against, and the ticket re-opens CW
   D3's exact wound (merged-unobserved ×2).
9. **Do not stack the new lossy choices on the tool-calling route without one quality read**: the
   lane already spent `wht6` (KL 0.065 class) with no accuracy receipt; dtype + optional YaRN are
   two more output-bit purchases (prior round's C3 stands).
10. **Do not add the lane without the roster row and the peer-set re-pin** — [ROST]'s T2 and three
    llama-swap exact-set test legs make a silent lane addition structurally red; that is the
    feature, not friction.

## §9 — Conflicts left unresolved (real ones)

- **C1 — "7.7/6.8 sessions and +12% prefill" vs the doc's own tables.** The session numbers survive
  (they are DERIVED from our measured pool × the doc's ratio law, and the ratio law reproduces the
  doc's pool-token row exactly: 518,800×32/25 = 664,160 ≈ 664,400 ✓); the **+12% prefill does not**
  — it belongs to `--attn-prefill-fp8 both`, not to dtype (§2.8/§3.2). The prior round's §6.2 line
  "`fp8_v4` takes 221k prefill 2,666 → 3,097 (+12%)" reads the table's last sentence as
  dtype-alone; the table's dtype row shows 9.76→9.76 s. Carried-forward brief inherited the
  misattribution. Unresolved remainder: whether the *narrow layouts* speed decode-side cache
  traffic on our Gen3/Gen4-x4 rig (the doc's decode rows say "same speed there").
- **C2 — P1 vs P3 on factor 1.5.** Parse-legal-by-wording vs validated-only-at-2, with the
  worst-position-edge argument (§1.4). Resolves only at a boot receipt + one near-393K probe; until
  then the report sides with P3 (use factor 2).
- **C3 — the owner's seqs-5 rule vs D9(a)'s purpose on fn.** seqs 5 makes fn's *bar* passable only
  at seqs ≤ 4; the rule "5 on existing lanes" therefore converts fn's refutation from 4.1<8 to
  4.1<5 — less dramatic, still true. Nobody should present 5 as fixing fn.
- **C4 — ladder laws vs a fifth trio** (§6.1): the rule set (unique/decreasing per column, no
  negatives, low strictly below default, unnamed ties red) has no solution for a fifth trio without
  either a second *named* low tie or a fresh rank-range ruling. The laws were authored when "four
  engines, four queues" justified ties; five engines inherits the justification but the suite needs
  the enumeration act.
- **C5 — docs provenance drift at the pin**: two "GUIDE.md @v1.17.0" surfaces have been cited by
  prior rounds (root 345,752 B, now 404; docs/ 294,533 B, live) with slightly different table
  shapes. Every citation this round resolves in the live `docs/` file at `/raw/tag/`; where an old
  cite could not be re-verified (§0.5) the claim was re-derived or dropped.
- **C6 — dtype availability vs our two packs.** `[G@t]` says both v4 layouts are offered on
  `qwen35_fp8` **and** `qwen4exp_fp8`, so fn could take the same funding lever (§2.3's 5.1/5.7
  rows, DERIVED with the QSA-share caveat) — yet the owner's plan puts the dtype only on the new
  27b pod. If fn's 4.1/52% is the live-route problem, the *same mechanism the new lane uses* fixes
  fn more than seqs-5 does. Deliberately left un-asked (§10 Q6) because it changes fn's serving
  text, and fn is every tier's route.

## §10 — Questions for the owner (batched)

1. **Which lanes get the 1.5× window** — the new pod only, or all five? (The seqs/dtype/catalog
   plan below changes completely; §2.2 says TP1 lanes cannot fund it at all, and fn — a MoE — pays
   the expert-plane cost, not just the trunk.)
2. **`k6_v4` or `fp8_v4` for the new lane?** The doc's own table dominates fp8_v4 by every column
   measured (§3.2). Keep the `-fp8_v4` name only if the V-4-bit/K-E4M3 split is what you want.
3. **Do you accept Option A (concurrency) now and defer the window, or Option B (window at seqs 5
   on the new lane), or the explicit-deficit shape (window at 8, gate prints ~57–65% and you rule
   "accepted")?** §7 has each one's exact prints-to-come.
4. **YaRN factor: 2 (validated, docs' own pattern) or 1.5 (legal, first-of-its-kind)?** Either way
   the boot receipt is `rope: YaRN factor F over 262144 trained positions -- the rotary reaches
   …` — no such line, no scaling.
5. **Fifth-trio ranks:** authorize the second named low-tie (5/1/0 suggestion) or extend the ladder
   range? (No collision-free option exists under the current M9-A2 laws, §6.1.)
6. **Should fn (or q27-TP2-in-place) also move to the narrow dtype?** It is the only lever that
   actually funds fn's 4.1<5 deficit (§2.3/C6) — and it changes the live default route's output
   bits; the seqs-5 wave alone does not fix fn.
7. **Sequence consent:** owner runs the owed C04 receipt block at the current shape FIRST, then the
   seqs/dtype wave lands (§4.1); or you rule the receipts taken on the new shape directly.
8. **The jsonc leg is yours** (parent D27): confirm you'll apply the catalog diff (new trio rows;
   context leg only after the YaRN lane's receipts) once the test wave defines the rows.

## Implications for the plan (what the planner must decide differently)

- Scope the chart change as **one FORM wave with three env channels** (`RADIANCE_KV_CACHE_DTYPE`,
  `RADIANCE_MAX_NUM_SEQS`, `RADIANCE_ROPE_SCALING`, each with suite-pinned fallbacks), not three
  separate edits — same file, same testlib map, one receipt-gate rewrite (§4.2 covers the full leg
  list).
- The receipt gate must become **per-lane configurable-seqs resolution** (its current single-
  distinct rule is a hard break, not a warning) — plan it in the test-authority wave before any dev.
- Plan the C04-first ordering explicitly (owner leg, then wave, then new-shape prints) — the ticket
  otherwise stacks on un-closed PROVISIONAL state (CW D15/D19).
- Ladder/context catalog rows go in the plan as **specs to the owner**, with the M8-A2/D19 re-freeze
  as its own test chunk.
- Budget one quality read (small tool-calling probe A/B) against whichever lossy set the owner
  finally stacks (`wht6`+dtype±YaRN) — everything else here is bytes and receipts.

*(Sources table: §0's bracket keys — `[G@t]`, `[Y@t]`, `[O@t]`, `[C27@t]`, `[CF@t]`, `[G@m]`,
`[Y@m]`, `[I457]`, `[E27]`, `[EF]`, `[CW]`, `[ROST]`, `[FORM]`, Qwen/vLLM deployment docs,
YaRN paper arXiv:2309.00071. All pin fetches used `/raw/tag/v1.17.0/docs/…` and are line-cited;
all `main` fetches are separate rows. Repo file:line cites are this worktree @ `e65b5c5a8`.)*

RESULT
status: DONE
chunk: research (fp8v4/yarn/per-lane-seqs grounding round, G1–G6)
files_changed: [.agents/plans/2026/2026-11-feat-radiance-fp8v4-yarn/RESEARCH.md]
commands_run: [
 skill loads /storm /pipeline-conventions /pipeline-role-research => pass;
 reads: 27b-tp2-perf EXPLORE.md+RESEARCH.md (full), flash-tp2-perf EXPLORE.md (full), context-window DECISIONS.md D1–D19 + STATE.json incl. handoff_2026_11_23.carry_forward, notes radiance-q27-boot.md (full) / radiance-second-gpu-tp2.md (full) / radiance-host-tuning.md (§14 grep + LEAVE-IT-ALONE) / radiance-multi-instance-roster.md (full) / radiance-on-target-acceptance.md (profile + step-6 greps), charts/radiance/values.yaml FORM :180-359, services/gpu-ai/prod/values.yaml :1-140+:1125-1175+:1600-1734, .opencode/opencode.jsonc :713-879, charts/radiance/tests testlib/receipt_gate/test_c03/test_receipt_gate greps, tests/pipeline-models surface.sh M8 + TEST_SPEC §3, tests/notes greps => pass;
 execute+fetch: codeberg raw @tag/v1.17.0 docs/GUIDE.md (294,533 B), docs/YARN.md (7,477 B full read), docs/OPS.md (yarn-op-schema lines), deploy/compose/qwen3.8-27b-mxfp4.yaml + flashnext.yaml + common.yaml; @branch/main docs/GUIDE.md (348,332 B) + docs/YARN.md (7,476 B); API: issues/457 (state open, re-verified), branches (main only), tags (v1.17.0…v2.2.0); root-GUIDE@v1.17.0 => 404 (recorded §0.5); arxiv.org/abs/2309.00071 => 200 => pass;
 global-searxng: 3 surveys (YaRN fractional/degradation; Qwen YaRN 1.5; radiance YaRN) — qwen.readthedocs static-YaRN short-text quote recovered => pass;
 Code Mode arithmetic: funding matrix (formula validated against BOTH real prints 66/5.3 and 52/4.1), tier/token ratios, attention_factor defaults, FLOPs length-scaling => pass;
 verification: target folder confirmed absent before write (earlier phantom listing recorded §0.7) => pass]
deviations: wrote only the named deliverable (folder auto-created by write); kept storm intermediates in-file (no scratch writes outside the ticket folder, same posture as the prior research round); did NOT adopt the launch's k6_v4/fp8_v4 bit-layout guess nor its "+12% prefill" attribution — both corrected from the fetched pin docs; treated "v1.17.0" surfaces by verified path only (§0.5); the prior root-GUIDE surface cited by earlier rounds is now 404 and no conclusion rests on it.
friction: root-path GUIDE.md@v1.17.0 cited by the context-window round 404s today (branch-less tag refs + docs/ relocation) — resolved by re-fetching everything under /raw/tag/v1.17.0/docs/ and line-citing; a phantom ls listing at the deliverable path (future-dated file, folder absent to re-check) — recorded §0.7, no action; searxng returned noise rows on "qwen yarn factor 1.5" — recovered the usable anchor (qwen.readthedocs static-YaRN warning) from the same result set; receipt_gate's per-lane breakage found by reading the gate rather than the ticket docs (no doc names it).
open_questions: [owner: the §10 batch (window scope, k6_v4-vs-fp8_v4, Option A/B/deficit, factor 1.5-vs-2, fifth-trio ranks, fn dtype, C04-first sequencing, jsonc leg); boot-receipt: does 1.17.0's rope_override parser accept "yarn:1.5" (one boot of the new lane settles §1.2), does the narrow dtype shrink the page/KiB boot line as predicted (§3.3), and do 393,216-era checkpoint-slot/pinned numbers hold the `limit − printed-pinned ≥ 4` law (§2.7); research-owned: YaRN effect on DFlash2 draft acceptance (drafter gets the factor over its own trained length — nobody has measured the interaction); tool-calling accuracy of the v4 layouts (log-analysis KL table does not transfer)]
next_suggested: feed §7's Options A/B + the §10 batch to the owner as the ticket's pre-build ruling round; if Option A/B is chosen, the plan should open with the test-authority wave (FORM channels + receipt_gate per-lane rewrite + M8-A2 re-freeze + roster/peer-set legs) before any values/dev chunk, and the seqs/dtype wave should explicitly follow the owed C04 prints of the current shape.
