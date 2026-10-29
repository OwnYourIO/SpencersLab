# RESEARCH — cf-86 "More models for Strata" (gpu-ai)

Pre-plan research round, 2026-10-29. Card checklists: Services gpu-ai · Type feat · Models Qwen Flash + Local · Research before+after planning · HITL Plan.
Method: STORM-style survey → grounded interviews over live web (SearXNG/webfetch: Strata upstream docs/issues/releases, Hugging Face API trees, orcarouter blog, Reddit threads) plus repo inspection. Prior verified base: cf-77 `RESEARCH.md` (Strata image/CLI/peers/arena mechanics — cited here as [S0], not re-derived) and cf-83 plan record [S0b].

Evidence tags: **[repo]** verified from this repo · **[web]** verified from a fetched web source · **[assumed]** inference, flagged.

## TL;DR

1. **Strata has no live model swapping.** One serve process = one model/profile; switching is stop-and-restart (upstream hot-switch API request was closed *not planned*). llama-swap integration starts/stops a per-model process, and arenas are additive so two Strata models must never co-load. Swapping costs a cold arena pin measured at ~17.3 GiB/s → minutes per swap (IQ3_S ≈ 2.7 min; smaller quants proportionally less).
2. **"More models on Strata" is gated by the page-locked arena against the 125 GiB node, not by file availability.** The unsloth-family Q4 files for flash-next exist upstream and the init-container plumbing (`STRATA_MODEL_Q4=unsloth/UD-Q4_K_XL`) is already designed for them — but Strata's own docs put UD-Q4_K_XL's expert set at 72 GiB (pinned arena) / ~88 GB all-experts RAM, which this repo already ruled "past this node's arena model". The realistic new Strata rungs are **smaller**, not bigger: Coder IQ1_M (~23 GB experts), IQ3_XXS (43 GB), Gyro (27.6–35 GB total), qwen3.6-35B-A3B (22.9–37.8 GB files), and the OrcaRouter uncensored IQ3_XXS manual path (~49.8 GiB arena, per ORCA.md).
3. **Ornith-1.5-122B is NOT a Strata candidate today** — upstream closed the support request ("not in the plan for the next release, add later", #3574; a second request #4460 is still open as of 2026-10-28 and a community member has publicly announced an in-progress Strata optimization for it). It is already served well by llama.cpp on this cluster. Its quality case vs flash-next is real (notably SWE-bench Pro *no-hack* 76.9 vs 43.9 on the vendor card) but harness-dependent and contradicted by flash-next's own card (62.5 on SWE-bench Pro under a different protocol) — see Contradictions.
4. **Coding ablations beyond orca are abundant and rankable.** For flash-next the community-favored, measured line is heretic-style (trohrbaugh heretic/heretic-2 ≈ KLD 0.019–0.035 from the original, "least change" per independent AtomicChat comparison) over huihui-ai-style (KLD 0.20, +8–10% perplexity). For Strata specifically only IQ3_XXS-class ablations have a validated path (orcarouter via ORCA.md; SC117's abliterated ships the exact ISTA sizes with a `strata/` folder). For 27B the field is large (heretic-ara already served as `ara`; orcarouter Q4_K_M 16.8 GB is small and public via bartowski mirror).
5. **Coexist-vs-swap order on this node:** only arenas ≲ 30 GiB can plausibly sit beside llama.cpp warmth (Coder, Gyro, qwen36); IQ3_XXS (~40 GiB arena) and IQ3_S (46.8 GiB) and orca-IQ3_XXS (~49.8 GiB) are time-share (swap) rungs; UD-IQ4_XS (55 GiB) is borderline and buys little (88.9% vs 87.7% Q8_0 top-token match, and ~15% slower decode on R9700 per upstream's own table); UD-Q4_K_XL and above are infeasible on 125 GiB with any other load.

---

## Q1 — Live swapping: one server or several; swap latency; RAM/VRAM constraint

**Model of the engine [web]:** Strata runs one model per engine process. Docs "Adding or switching models" describe selecting a model and `--restart` when replacing a running launch [S1]; the llama-swap integration doc is explicit that llama-swap **starts and stops** a Strata process per model ("Strata needs the card's memory to itself") [S2]. Upstream issue **#1738** (hot model-switch API) was **closed `not_planned`** [S3] — there is no in-process model swap and none planned. **[repo]** confirms the shape we shipped: the Strata pod's inner llama-swap (v266) supervises `strata serve` per run-config profile; the inner matrix declares `(p | s)` as **alternatives, never co-loaded** — "arenas are additive; co-residency recreates #1715" (cf-77 C05) [S4].

**Swap latency [repo, measured on-class]:** the arena is page-locked host RAM read once at load: **IQ3_S arena 46.84 GiB at ~17.3 GiB/s ≈ 2.7 min** cold pin (cf-77 RESEARCH §4/§5); outer peers use `responseHeader: 1800`, inner `healthCheckTimeout: 1800`, `ttl: 3600` time-share against the llama.cpp trio [S5]. Teardown needs a wide `unloadTimeout` (≥180 s; llama-swap default 10 s would force-kill a ~47 GiB pinned arena) [S0 cf-77 §3]. So each swap between Strata profiles is on the order of **3–6 minutes round trip**, plus engine startup/tokenizer load [assumed from the measured pin rate + cf-77 runbook timings].

**Binding constraint:** RAM, not VRAM. The R9700 is 32 GB and only holds the hot working set (active experts + KV); the pinned arena comes straight off the 128 GB node pool (runbook gate 0.13; "the arena math spends it with the llama.cpp trio idle") [S6]. Strata docs agree in the consumer framing: "A bigger graphics card makes it faster and does not lower the RAM needed" and the fit rule is **RAM ≥ shard-1 experts + ~10 GB** [S1]. On this node the repo's own residency law (runbook §"LPDDR5X budget law"): a warm Strata arena (~47 GiB) beside a warm llama.cpp trio (~90–119 GiB) **exceeds 125 GiB** — coexistence only until the first Strata request; `POST /api/models/unload/:id` on the inner instance is the escape [S6].

**Consequence for the card:** "more models for Strata" is a *scheduling* feature, not a catalog feature — each added Strata profile adds minutes-of-cold-start rungs that time-share the same pinned-RAM budget.

## Q2 — flash-next Q4 and Ornith-1.5-122B Q4: catalog facts

### flash-next Q4

**[repo]** The serving catalog already has flash-next Q4 on the llama.cpp side: `unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q4_K_XL`, 103.7 GiB, enabled on gpu-ai (family entry `charts/llama-swap/values.yaml` L735–742; gpu-ai models override) [S5].
**[web]** Verified at source: `unsloth/Qwen3.8-Flash-Next-GGUF` ships `UD-Q4_K_XL` (4 shards, 111,334,652,184 B = 111.3 GB total) and `UD-IQ4_XS` (93.7 GB), plus `MTP/mtp-…-Q4_K_M/Q8_0/BF16` drafts, mmproj, imatrix [S7]. The 111.3 GB figure matches Strata's MODELS.md unsloth table exactly, so Strata's `--family unsloth` targets these very files [S1].
**[web]** Strata's unsloth-family numbers [S1]:

| Size | Download | Experts | RAM for all experts | Top-token vs Q8_0 |
| --- | ---: | ---: | ---: | ---: |
| UD-IQ4_XS | 94 GB | 55 GiB | ~72 GB | 88.9% |
| UD-Q4_K_XL | 111 GB | 72 GiB | ~88 GB | 93.1% |
| UD-Q5_K_XL | 158 GB | 92 GiB | ~108 GB | 94.6% |

For comparison the doc notes **IQ3_S (what we run) matches Q8_0's top token 87.7%** of the time — UD-IQ4_XS gains +1.2 pt for ~8 GiB more pinned experts [S1]. Upstream's measured R9700 speeds (older engine): UD-Q4_K_XL 63 story / 87 code tok/s vs IQ3_S 75 / 95 same card [S1] — i.e. **Strata-side Q4 is slower to decode than today's IQ3_S on our exact GPU**.
**[repo]** The init container already anticipates this: `STRATA_QUANTS` tokens map through `STRATA_MODEL_Qx=[family/]model`; the qwen family caps at the four ISTA quants; "q4/q5 come from the unsloth family (UD-Q4_K_XL ~104 GB incl. the shared 28.8 GB n-gram shard…) — **past this node's arena model**" (`charts/llama-swap/values.yaml` L1143–1153) [S5]. The comment cites "cf-78 arena-math"; **no cf-78 folder exists in this worktree** — the reference is to a card/folder not present here [repo; flag].

### Ornith-1.5-122B Q4

**[repo]** Already served on the llama.cpp side: `unsloth/Ornith-1.5-122B-GGUF`, UD Q3–Q6 enabled on gpu-ai (q4 UD ≈ 74.2 GiB, solo sets; values L357–360); "unsloth repo has no mtp-* files" — MTP builds live in `prithivMLmods/Ornith-1.5-122B-MTP-GGUF` [S5]. `.opencode/opencode.jsonc` has **no ornith entries** — not agent-routable today (relevant to the Models checklist: card routes Qwen Flash + Local) [S8].
**[web]** Model card (`ornith-ai/Ornith-1.5-122B`): 122B-class MoE (community post details: 125.1B total, 256 experts / 8 active + 1 shared, 48 layers, 1 MTP layer, 2 KV heads), MIT license, 262,144 native ctx (YaRN ×4 → ~1M), reasoning model, tool parsers qwen3_xml/qwen3_coder [S9][S10]. Benchmarks (vendor card): SWE-bench Verified 84.5 (vs flash-next 82.8), SWE-bench Pro *no-hack* 76.9 (vs 43.9), TerminalBench 2.1 81.2 (vs 83.4 — flash-next leads), NL2Repo 51.2 (vs 45.2), CyberGym 80 (vs 78) [S9].
**[web] Strata support: blocked.** Issue **#3574** (Ornith-1.5-122B support) closed by the maintainer — "not in the plan for the next release, add later"; issue **#4460** (filed 2026-10-28, `needs-format`, 1 comment) still open [S11]. Community is moving: an r/LocalLLM thread (2026-10-25) announces a single-GPU showdown — "I'm working on top of the Strata local inference engine, optimizing its inference speed for Ornith-1.5-122B" [S12]; Strata's q36 engine path benchmarks Ornith-1.5-35B-A3B (PR #3677) — the 35B-A3B runs on the existing path, the 122B does not [S13]. **[assumed]** If a plan wants Ornith-on-Strata, it must wait for upstream (watch #4460) or carry a fork — out of scope for cf-86.

## Q3 — Coding ablations of flash-next and 27B beyond orca

*(repo baseline: `qwen3.8-flash-next-orca` = orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF:Q6_K, gated, the only flash-next ablation currently served; the 27B `qwen38` family already serves orca Q6_K, `ara` (heretic-ara), `rana`, `humanlike` [S5].)*

### flash-next ablation field [web]

- **SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF** — the Strata-relevant one: ships the exact ISTA-validated size set (Q2_0/IQ2_XS/IQ3_XXS/IQ3_S) **plus a `strata/` folder and MTP files**; ~3.0M downloads [S14].
- **orcarouter Uncensored** (the already-served one): 13 quants IQ2_XXS→Q5_K_M (IQ4_XS ≈ 97.5 GB; Q4_K_M ≈ 119 GB); no Q6_K/Q8 tier *structurally* — the n-gram (PLE) table can't fit HF's 50 GB per-file limit at those sizes; gated (HF_TOKEN) [S15].
- **trohrbaugh heretic / heretic-2** (HF, popular): decensored with documented heretic-fork parameters; republishes the full Qwen benchmark table [S16].
- **AtomicChat Uncensored GGUF + LoRA adapter** — independent head-to-head of the ablation packs at Q8_0 vs BF16 reference: heretic-2 changed the model least (KLD 0.019), orcarouter 0.022, their own release 0.026; MMLU deltas ≤0.7 pt across all; also reports that attention-output-only edits (what Heretic-style tools reach) leave 96% of refusals on this architecture — "the refusal lives in the experts too" [S17].
- **satellitedown heretic-fngine pack** — agreement measurements: heretic stays within ~0.035 KLD of the original while **huihui-ai's abliteration sits at 0.204 KLD with 8–10% higher perplexity on ordinary text** [S18]. → Quality ranking signal for planning: *heretic-style > orca ≈ AtomicChat > huihui-style* for coding agents that must stay close to base behavior.
- Other lineups (llama.cpp-only, not Strata-validated sizes): spiritfather heretic-2 GGUF (Q4_K_M–Q8 + MTP + mmproj), huihui-ai abliterated + v2, DavidAU Turbo-Brilliance GSQ-RCO, jimmy31chen RVN IQ3_S-Strata merged 88.9 GB pack, alesha-pro Strata packs, Swift-1.5-abliterated (SC117) [S14][S19].
- **Community coding experience (near-class hardware, 128 GB Strix Halo):** "Qwen3.8 Flash Next is the best model I tested for 128Gb" [S20]; deepu105's longitudinal writeups: 27B Q6_K ≈ 31 GiB resident vs flash-next UD-Q4_K_XL ≈ 86 GiB resident; flash-next = same task success as 27B with 45% fewer tokens, 76.5 s vs 289.8 s wall; **MTP is the biggest speed win** (7.3→22.4 tok/s decode on an empty window; 1.15× at full 256K) [S21].

### 27B ablation field [web]

- **orcarouter/Qwen3.8-27B-Uncensored-GGUF** (served as orca): full tier ladder Q4_K_M 16.8 GB / Q4_K_S 15.8 / IQ4_XS 15.3 / Q6_K 22.4 / Q8_0 / F16 — small dense files; **public ungated mirror exists: bartowski/orcarouter_Qwen3.8-27B-Uncensored-GGUF** [S22].
- **huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF** (~2.9M dl) [S22].
- **0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF** — RVN quant ladder incl. `Q4_K_M -mtp` ≈ 17.0 GB + `mtp-RVN.gguf` drafts [S22].
- MTP/coding-flavored: HauhauCS Aggressive-MTP, DavidAU TURBO-Fable-Cold-Fusion CODER-MAX-MTP, nerkyor Coder390-SFT-RLOO (DFlash2), mradermacher Fable-5-Coding-Distilled, ayozhee Abliterated-GSQ-Orca (IQ2_S/IQ3_S MTP, Strata-small class) [S22].
- `ara` is already the heretic-ara serving rung in this repo [S5].

## Q4 — Fit per model on the Strata node; coexist vs swap order

Node budget [repo]: 128 GB total ≈ **125 GiB spendable** (cf-77 R3 math); R9700 32 GB via OCuLink x4 (~7.2 GB/s end-to-end); today's Strata pod: cgroup 96 Gi, engine `--memory-limit-mib 92160` sized as arena ~50 + conv-cache 32 + KV ~13 for IQ3_S; trio-warm 90–119 GiB; residency law: arena + warm trio > node [S5][S6].
Arena estimate for a new quant ≈ its shard-1 experts figure (Strata docs: "experts go into RAM at start") — IQ3_S experts 50 GB ↔ measured arena 46.84 GiB, so **arena ≈ experts figure, 1:1** [assumed-by-calibration, S1+repo-measured].

| Strata candidate (family/model) | Experts → arena | Pod all-in (arena+conv+KV) | On 125 GiB node | Verdict |
| --- | ---: | ---: | --- | --- |
| **Coder IQ1_M** (ISTA GSQ-RCO) | ~23 GB [S1] | ~60–66 Gi | roomy; only candidate with plausible **true coexist** beside llama.cpp warmth (cgroup could shrink) | **swap-cheapest too** (~1.7 min pin); SWE Verified ≈91% of full, LCB 99% per authors; weak outside code/CJK |
| **qwen (ISTA) IQ3_XXS** | 43 GB [S1] | ~80–90 Gi | fits solo; not beside warm trio | swap rung, general use |
| **orcarouter Uncensored IQ3_XXS** (ORCA.md manual pack) | arena ~49.8 GiB [S23 repo ORCA.md] | ~95 Gi | fits solo, ≈ today's IQ3_S shape | uncensored swap rung; needs manual pack step + gated HF_TOKEN in init |
| **qwen36 Qwen3.6-35B-A3B** UD-Q4/Q6/Q8 | files 22.9–37.8 GB, engine plans 32–52 GB [S1] | small | **coexists**; R9700 measured 117.8 tok/s decode [S1] | different model, fast + parallel requests; duplicates the llama.cpp-served qwen3.6-35b |
| **gyro Gyro-S / Gyro-M** | 27.6 / 35 GB total memory [S1] | small | coexists; AMD "experimental", 16–21% slower decode than Q2_0 | niche memory-saver |
| **swift Swift 1.5** | same as original size [S1] | as IQ2_XS/IQ3_XXS | swap rung; shorter thinking, ~same quality | optional |
| **unsloth UD-IQ4_XS** | 55 GiB [S1] | ~100–106 Gi | borderline solo (cgroup 96Gi → raise to ~110Gi; no llama.cpp warmth, thin system headroom) | +1.2 pt top-token, −15% decode vs IQ3_S on R9700 [S1] — **poor ROI** |
| **unsloth UD-Q4_K_XL** | 72 GiB [S1] | ~117+ Gi | exceeds the node with any other load — matches the repo's existing ruling "past this node's arena model" [S5] | **no** |
| **Ornith-1.5-122B** (any quant) | — | — | engine path absent (upstream #3574 "add later", #4460 open) | **no, this ticket** |

**Coexist-vs-swap order (recommended planning frame):** tier-0 coexist = Coder + qwen36 (+gyro niche) → tier-1 swap = IQ3_XXS / orca-IQ3_XXS ≈ IQ3_S today → tier-2 decline = unsloth Q4 family → tier-3 blocked = Ornith-on-Strata. Inner matrix grows as **alternatives** (`(p | strix | coder | …)`, never co-load), outer peers routes gain one model id per new inner profile, `responseHeader: 1800` already covers the cold pins; provider catalog (`.opencode/opencode.jsonc`) needs an entry per new routable Strata id (it lacks ornith AND any future coder/qwen36-strata ids) [S5][S8].

## Implications for the plan

1. Cheapest genuine win: **Coder IQ1_M as a second/third inner-matrix alternative** — coding-specialist rung, arena ~23 GB, fastest cold pin, and the only profile that could relax the residency law; plumbing is a `STRATA_QUANTS`/`STRATA_MODEL_*` token + a run-config profile + matrix entry + peers route + provider-catalog entry.
2. If the card means "uncensored Strata": orcarouter IQ3_XXS via the ORCA.md manual-pack path (already documented in this repo's container README area) or SC117's abliterated ISTA set (ships `strata/` folder; sizes are exactly the installer-validated ones) [S14][S23].
3. **Do not pursue flash-next Q4-on-Strata or Ornith-122B-on-Strata in this ticket** — Q4 fails the node's arena math (and is already served by llama.cpp at better practicality); Ornith awaits upstream engine support. Both are honest "not now" answers for the card.
4. Suite-style validations the repo will expect: rendered inner matrix has no set co-loading two arena models; peers list covers every inner profile id; no outer alias shadows inner ids (bare-ID routing precondition); `helm lint/template` green.

## Contradictions / cautions

- **SWE-bench Pro flash-next: 43.9 (Ornith card, "no-hack" protocol) vs 62.5 (flash-next's own card table, Claude-Code harness)** [S9][S16] — harness/protocol-dependent; don't plan on either number alone. Same pattern for TerminalBench where flash-next *leads* 83.4 vs 81.2.
- **flash-next size naming:** ollama/community say 125B total / 6B active (+51B n-gram embedding params) [S16][S24]; this repo's chart comment says "180B-class" — stale/wrong, the unsloth UD-Q4_K_XL file is 111.3 GB and Strata docs call the model Qwen3.8-Flash-Next consistently [S1][S7].
- **"cf-78 arena-math" comment in values.yaml has no cf-78 folder in this worktree** — either a card not yet landed as a plan folder or a stale reference; the conclusion itself is independently reproduced above from Strata's docs [S5].
- Strata's consumer "Will it fit" experts figures (IQ3_S 50 GB) vs our measured arena (46.84 GiB) differ by ~6% — calibration is close but docs numbers are estimates [S1][S0].
- Gyro on AMD and the q36-path Ornith-35B benchmark are marked experimental/upstream-PR — verify before planning them in.
- Community ablation quality numbers are single-source self-measurements (satellitedown, AtomicChat) — directionally consistent (heretic-style gentler than huihui-style) but not independently reproduced [S17][S18].

## Open questions (for the coordinator's batched round)

1. Does "More models for Strata" mean **true coexistence** (Strata warm beside llama.cpp warmth — forces the ≤30 GiB-arena tier: Coder/qwen36/gyro) or **catalog breadth with minutes-long swaps accepted** (adds IQ3_XXS/orca-IQ3_XXS rungs)? The plan candidates differ by this answer.
2. Is an **uncensored Strata rung** wanted (orcarouter IQ3_XXS manual pack + gated HF_TOKEN in the Strata init container, or SC117 abliterated ISTA set)? That adds an init-container capability (manual pack step) beyond a simple token.
3. Accept the **Coder trade** (91% SWE Verified, weaker general/multilingual) as a dedicated coding profile?
4. Add **qwen3.6-35B-A3B on Strata** (fastest measured decode on the R9700, coexists, serves concurrent requests) even though a llama.cpp-served `qwen3.6-35b` already exists on the cluster?
5. `.opencode/opencode.jsonc` currently lacks entries for **ornith-1.5-122b-* and flash-next-orca** (llama.cpp-served but not agent-routable). In scope for cf-86 as a catalog-hygiene chunk, or separate card?

## Sources

- [S0] `.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap/RESEARCH.md` — verified Strata image/CLI/peers/arena/unload mechanics ([S12] therein = PR #3636 `r9700-arena-pf32k.json`: arena read 46.84 GiB @17.3 GiB/s).
- [S0b] `.agents/plans/2026/2026-10-cf-83-refactor-strata-flash/` (route id `gpu-ai/qwen3.8-flash-next-strata`, peers authority, cold-start clause).
- [S1] Strata `docs/MODELS.md` @main (raw.githubusercontent.com/Niko1221/Strata) — fetched 2026-10-29: unsloth family table (UD-IQ4_XS 94 GB/55 GiB/~72 GB/88.9%; UD-Q4_K_XL 111 GB/72 GiB/~88 GB/93.1%; UD-Q5 158/92/~108), IQ3_S 87.7% top-token, experts-per-size fit table (IQ3_XXS 43 GB, IQ3_S 50 GB, Coder 23 GB), Coder (256/512 experts, 91% SWE Verified, 99% LCB), Swift 1.5, Gyro (S 27.6 GB / M 35 GB, R9700 −16–21% vs Q2_0), qwen36 (UD-Q4 22.9 GB file / 32 GB planned; R9700 117.8 tok/s), R9700 UD-Q4_K_XL 63/87 tok/s vs IQ3_S 75/95, switching = `--restart`.
- [S2] Strata `docs/LLAMA_SWAP.md` @main — per-model start/stop; "Strata needs the card's memory to itself".
- [S3] Niko1221/Strata issue #1738 — hot model-switch API closed `not_planned` (fetched via GitHub API).
- [S4] cf-77 `chunks/C05.md` — inner matrix `(p | s)` alternatives, "arenas are additive; co-residency recreates #1715".
- [S5] `charts/llama-swap/values.yaml` (families L146/210–260/353–360/735–784; strata block: STRATA_QUANTS loop + "q4/q5 … past this node's arena model" comment L1143–1153; cgroup/engine memory) + `services/gpu-ai/prod/values.yaml` (enablement, peers.strata, responseHeader 1800) + `.agents/notes/strata-host-prep-gpu-ai.md` (ORCA.md IQ3_XXS numbers, unload, residency discipline).
- [S6] `.agents/notes/strata-host-prep-gpu-ai.md` — gate 0.4 OCuLink x4 ~7.2 GB/s; gate 0.13 RAM 128 GB; LPDDR5X budget law L383–392 (arena + warm trio exceeds 125 GB; unload escape).
- [S7] HF API tree `unsloth/Qwen3.8-Flash-Next-GGUF` @main — UD-Q4_K_XL 111.33 GB (4 shards), UD-IQ4_XS 93.68 GB, MTP drafts, mmproj, imatrix. Fetched 2026-10-29.
- [S8] `.opencode/opencode.jsonc` — gpu-ai provider catalog: qwen3.8-27b-q4/q6, flash-next q3/q4/strata @262144; no ornith or flash-next-orca entries.
- [S9] `ornith-ai/Ornith-1.5-122B` (+ -GGUF) model cards — benchmark table vs flash-next/27B; MIT; 262144; tool parsers; unsloth GGUF companion.
- [S10] r/ollama + r/LocalLLaMA posts on Ornith-1.5-122B (2026-10-27/28) — arch details (256 experts/8 active+1 shared, 1 MTP layer), Q4_K_M ≈ 77 GB, community take: "keep both — one to implement, one to review", Ornith more meticulous/verification-biased, slower rumination.
- [S11] Niko1221/Strata issues: #3574 (Ornith 122B support; closed, maintainer "not in the plan for the next release, add later"); #4460 (open, `needs-format`, 2026-10-28, community request citing a NVFP4-DFlash2 pack). Fetched via GitHub API.
- [S12] r/LocalLLM "Ornith-1.5-122B vs Flash-Next: single-GPU showdown coming" (2026-10-25) — third-party Strata optimization for Ornith-1.5-122B in progress.
- [S13] Strata PR #3677 — benchmark of Ornith-1.5-35B-A3B via the q36 engine path (35B-A3B class runs; 122B does not).
- [S14] HF API tree `SC117/Qwen3.8-Flash-Next-GSQ-RCO-abliterated-GGUF` — Q2_0/IQ2_XS/IQ3_XXS/IQ3_S + `strata/` folder + MTP files; ~3.0M downloads.
- [S15] orcarouter blog "Qwen3.8-Flash-Next-Uncensored: GGUF and MLX Runbook" (2026-08-28) + HF tree — 13 quants, IQ4_XS ≈ 97.5 GB / Q4_K_M ≈ 119 GB, no Q6_K/Q8 at ≤50 GB/file (n-gram table), gated.
- [S16] HF `trohrbaugh/Qwen3.8-Flash-Next-heretic` / `-heretic-2` — heretic-fork parameters; official Qwen benchmark table (125B/6B active/51B n-gram; SWE-bench Pro 62.5; LiveCodeBench 91.9).
- [S17] HF `AtomicChat/Qwen3.8-Flash-Next-Uncensored-GGUF` — independent ablation comparison (KLD: heretic-2 0.019 < orcarouter 0.022 < AtomicChat 0.026; huihui excluded as harsher), refusal-in-experts finding.
- [S18] HF `satellitedown/Qwen3.8-Flash-Next-heretic-fngine` — agreement/KLD vs original: heretic 0.035 vs huihui 0.204 (huihui +8–10% perplexity); one-request-at-a-time note.
- [S19] HF trees: spiritfather heretic-2 GGUF (llama.cpp quants + MTP + mmproj), huihui-ai, DavidAU, jimmy31chen RVN IQ3_S Strata pack, alesha-pro Strata packs, SC117 Swift-1.5-abliterated (earlier fetches this session).
- [S20] r/LocalLLM "Qwen3.8 Flash Next is the best model I tested for 128Gb".
- [S21] deepu105: r/Qwen_AI "Qwen3.8 27B vs Flash Next for agentic coding" (2026-10-23) + deepu.tech writeups — 128 GB Strix Halo: 27B Q6_K ≈ 31 GiB, flash-next UD-Q4_K_XL ≈ 86 GiB resident; token efficiency 45% fewer; MTP 7.3→22.4 tok/s, 1.15× at 256K.
- [S22] HF listings 27B ablations: orcarouter Uncensored tiers, bartowski public mirror, huihui-ai (~2.9M dl), 0bserverx heretic RVN+MTP, HauhauCS, DavidAU, nerkyor, mradermacher, ayozhee (earlier fetches this session).
- [S23] Strata `docs/ORCA.md` (as recorded in this repo's ORCA.md note/cf-77 research): OrcaRouter flash-next IQ3_XXS manual path — 85.20 GB, arena ~49.8 GiB, IQ3_XXS only validated quant.
- [S24] ollama library Qwen3.8-Flash-Next — 125B/6B, 512 experts top-10 (against chart's "180B-class" comment: contradiction, see cautions).

*Method deviation (friction): STORM run scaffolding was initialized (`/tmp/opencode/storm-runs/more-models-for-strata-gpu-ai-live-swapping-on-the-strata/`) but the perspective/interview intermediate files were not written — the four questions were answerable directly from primary sources, so synthesis went straight to this document.*
