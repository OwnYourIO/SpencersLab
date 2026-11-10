# 2026-11-10 research — Strata q3/q4 rungs for Qwen3.8-Flash-Next on gpu-ai (releases, RAM envelope, tok/s, KV sizing)

**Provenance.** Standalone research commissioned by the repo owner; motivated by the
2026-11-10 q4 OOM crashloop (`.agents/plans/2026-11-10-debug-strata-q4-oom-crashloop.md`).
Method: STORM (5 perspectives: release watcher, catalog analyst, memory-systems
engineer, gfx1201 perf analyst, SRE incident correlator); all web sources fetched
2026-11-10 (citation list §9; intermediate trail in the session's storm-run folder).
`global-searxng` MCP was degraded (empty result sets) — native websearch + direct
GitHub/HF/GHCR API fetches + Grafana Prometheus reads used instead. Repo grounding:
debug note, `strata-host-prep-gpu-ai.md`, `vllm-on-target-acceptance.md`,
`charts/llama-swap/values.yaml`, cf-77/cf-86/vulkan-oom RESEARCH + cf-86 DECISIONS,
`containers/strata/{Dockerfile,README.md}`. Read-only: no cluster mutation, no repo
source edits, this file is the only write.

**Evidence labels used throughout:**
- **[M-node]** measured on our ai-gpu node (repo records, engine logs, Grafana/Prometheus)
- **[M-9700]** measured by upstream or community on an R9700 / RX 9070 (gfx1201) box
- **[R-near]** reported on nearest hardware (Strix Halo gfx1151, DDR4-bandwidth R9700 rig, multi-card splits, other engines)
- **[V]** vendor self-reported (unsloth benchmarks, RMSE)
- **[E]** estimated by arithmetic from calibrated anchors (setup.py `arena_gb` ↔ our measured arenas, 1:1 within 0.1%)
- **[—]** searched, not found anywhere — never invented

---

## 1. TL;DR

1. **The q4 pack itself is NOT superseded**: unsloth's 2026-11-04 "Dynamic V3.1" re-release left `UD-Q4_K_XL` weights unchanged (files merely re-split, −6 B total); Strata still pins the 09-30 revision we fetch. Same for ISTA IQ3_S (repo untouched since 2026-09-29) [1][5][8][16].
2. **V3.1 adds genuine NEW q3-class rungs** — `UD-IQ3_XXS` (83.6 GB, arena ≈46.9 GiB, same envelope as our IQ3_S flagship) and `UD-Q3_K_XL` (89.5 GB, arena ≈52.3 GiB) — with vendor-claimed +10–15% agentic accuracy vs GSQ-RCO [V], but they need Strata engine ≥0.1.57 (we pin 0.1.55) and have **zero** published Strata quality yardsticks and **zero** single-R9700 Linux speed numbers [3][5][16][19].
3. **The repo's `--kv-resident 32768` reading is wrong**: it is a 32,768-*cell* VRAM window (~0.4 GiB VRAM/slot), not a 32 GiB RAM budget. Real KV RAM law: **13,728 B per context token per slot** (int8; 13 layers × 1,056 B) → 1.28 GiB per 100k tokens, 3.35 GiB per full 262k slot, 13.4 GiB for 4 slots [5][10][11].
4. **Two concurrent 99k prefills only add ~2.7 GB of KV** — the incident's ~25 GiB collapse was parking/heap/transient-dominated, and upstream has an OPEN same-day bug (#5697: evicted parked conversations stay in the glibc heap so the RAM gate refuses forever) with a **one-env-line workaround that works on our 0.2.9 pin today**: `MALLOC_MMAP_THRESHOLD_=1048576` [12].
5. **Do NOT bump the engine to 0.2.12** (engine 0.1.58): an open gfx1201 crash-regression cluster (#5559 GPF storm on an R9700/128 GB box; #5635 load-RAM regression 67.8→114.8 GB → oomd kills; #5564 111K-prefill stuck; #5558 start failure). 0.2.11 (0.1.57) carries the big gfx12 wins but has its own open gfx1201 page-fault report (#5608); 0.2.13 (0.1.59, released yesterday) is unproven against both [16][21][22][23][24].

---

## 2. Executive summary — what should the owner change, if anything

Ranked, all owner-gated (budget law is owner property; nothing here is a decision):

**A. Repair the q4 envelope first — no model change needed.** The config's own worst
case still exceeds the node: 71.73 (arena [M-node]) + 16 (conv budget) + 13.4 (4-slot
262k KV, §5 arithmetic) + ~6–8 (dense/native 2.7 GiB, MTP, supervisor [11][E]) ≈
**107–109 GiB inside a 101.25 GiB engine cap, a 116Gi cgroup, and a 125.1 GiB node
whose measured floor is ~7–8 GiB** (non-strata containers 2.97 GiB live, plus the
idle llama.cpp main pod's 0.11 GiB [M-node §5];
U14's all-in node floor 7.3 GiB). Levers, cheapest first:
1. Add `MALLOC_MMAP_THRESHOLD_=1048576` to the strata model env — reporter-confirmed fix for the eviction-refusal death spiral (#5697), glibc-level, engine-version-independent, zero behavior cost [12].
2. Single-flight the q4 arena (`concurrencyLimit: 1` on the q4 model in llama-swap values) — **caveat correcting the debug note**: llama-swap does NOT queue excess requests; it rejects immediately with HTTP 429 (clients must back off/retry) [28].
3. Right-size the q4 pair from arithmetic instead of estimates: `parallel: 4→2` halves KV worst case (13.4→6.7 GiB); conv 16→8 GiB; either alone brings worst case ≈99–102 GiB, both ≈92–94 GiB [E §5]. Leave `--kv-resident 32768` ALONE for RAM purposes (it is VRAM; lowering it frees no host RAM, §5).
4. Lower the cgroup so the **container** dies before the **node** (e.g. 116Gi→~108–110Gi): SystemOOM harvested cluster system pods on 2026-11-10 precisely because the cgroup + floor exceeded node RAM [debug note; 15].

**B. Model choice: keep the current packs; treat V3.1 as a gated experiment, not an upgrade.**
- q4 production runner (`UD-Q4_K_XL`): unchanged by V3.1 — nothing to adopt, nothing superseded [5][16].
- q3 flagship (ISTA `IQ3_S`): ISTA repo unchanged since 09-29 [8]. The one same-envelope candidate is unsloth `UD-IQ3_XXS` v3.1 (arena ≈46.9 GiB ≈ identical [E]); vendor claims better accuracy retention than GSQ-RCO [V][3], but the only gfx1201 datapoint has it *slower* than IQ3_S (60–65 vs 70–75 tok/s @256k, one user) [19], and Strata's own yardstick (top-token vs Q8_0) has never been run on it [—]. Requires an engine bump to ≥0.1.57 (§D). Recommendation class: not worth a bump on its own; revisit if a bump happens anyway.
- If the owner wants a *smaller* q3-class envelope with better-than-IQ3_XXS quality: `UD-Q3_K_XL` v3.1 (arena ≈52.3 GiB, vendor top-1 recovery 88.3% vs IQ3_XXS 85.4%) — but 20 of 48 layers use Q5_0 downs, which measured **40–55% slower prompt reads on AMD without the opt-in fused kernel** (`STRATA_PF_FUSED_Q50=1`, 0.2.12+; +44%/+40% at 2K/8K on an R9700 when on) [6][16]. No speed data on a single R9700 exists [—].
- Orthogonal quality lever new since 11-04: **engram (PLE table) mix-and-match** — any set's 28.8 GB IQ4_NL table shard can be swapped for Q5_1 (38.4 GB, RMSE 0.0376) or Q8_0 (54.4 GB, RMSE 0.0053) [V][1][3]. Strata reads Q8_0 PLE tables (UD-Q5/Q6/Q8 sets ship them) [17]. Cost: +9.6/+25.6 GB disk and ~1.3×/1.9× the bytes-per-row in `direct` PLE mode (our probe read 120,960 rows/s vs the 15,000 warning line — 8× headroom at 90 B/row; a Q8_0 table roughly doubles bytes/row, so re-run the probe gate before adopting) [E; repo U14 record].

**C. Traffic law (community-converged, matches the incident):** at ≥131k contexts, do not run concurrent deep prompts on one arena — "fan out shallow, serialize deep" [30][32]. The engine already admits cold prompts one at a time, but each admitted slot's KV + parking + buffers stack in host RAM [10].

**D. Engine pin: stay on 0.2.9/0.1.55 for now; the bump path is gated and bumpy.**
- 0.2.10 has **no container image** (GHCR tag list: 0.2.11/12/13 exist for both rocm flavors; 0.2.10 absent — the image-gap law strikes again) [25].
- 0.2.11 (0.1.57) is the perf-interesting step for gfx12: K-quant MMQ prompt kernels default-on (+10–17% prompts on an R9700), bare `--prefill auto` ceiling 32768 (the q4/orca flash-next profiles would gain 32K chunks for free; the ornith q36 surface keeps its own chunk rules), bigger staging ring, route-tail-skip on for unsloth files (+6.2% decode geomean on an R9700, with a measured KL cost of 0.077 teacher-forced / agent-segment 0.203), v3.1 catalog support [16][17]. But #5608 reports repeatable gfx1201 page faults on 0.1.57 (different box/distro than #5559's clean report) [21][23].
- 0.2.12 (0.1.58): avoid — the regression cluster in TL;DR 5 [21][22][23][24].
- 0.2.13 (0.1.59, 2026-11-09): DETAILS.md gains `--ram-keep-gib` (arena used only if W GiB stay free after it; absent from the v0.2.9 docs — release bodies do not name the release that introduced it), plus the #5327/PR #5531 arena-loads-from-file-cache fix and hipBLASLt-table-off by default on gfx1201 (moot for us: our venv table is 1.2.0-class, 0–3%) [10][16][20]. Whether 0.1.59 fixes #5559/#5635 is **unknown** — both open, no fix named in the 0.2.13 body [21][22]. One community strata_bench of UD-IQ3_XXS v3.1 on engine 0.1.59 ran clean (CUDA, #5687) [33].
- Any bump follows repo law regardless: ledger digest re-read, one commit for both FROM tags, on-target `--plan` re-check, re-bench (`containers/strata/README.md`).

---

## 3. State of the model: new releases vs our current packs (Q1)

| Packager / repo | Last touched | Verdict vs our packs |
|---|---|---|
| **unsloth/Qwen3.8-Flash-Next-GGUF** | **2026-11-04 "Dynamic V3.1"** (repo head 11-07, sha 084c631a) [1][2] | New ladder UD-IQ1_M…UD-IQ4_XS-v31 at revision d9620119; **UD-Q4_K_XL/Q5/Q6/Q8_0 weights UNCHANGED** (Q4_K_XL re-split into different shard boundaries, total 111,334,654,778 B vs our pinned 111,334,654,784 B; Strata keeps fetching the 09-30 revision 38bb39ee and accepts the new split via `sha256_alt` pins) [1][5][16]. Our q4 provisioning path (setup.sh catalog) is revision-pinned and unaffected [repo fetch_models.sh]. |
| unsloth `engram/` folder (NEW) | 2026-11-04 [1][3] | Mix-and-match PLE/n-gram table: IQ4_NL 28.8 GB (ships in every set), Q5_1 38.4, Q8_0 54.4, BF16 102.4; RMSE vs BF16 0.0757/0.0376/0.0053/0 [V]. `set_split.py` stamps the split header. Strata-compatible in principle (Q8_0 tables ship inside UD-Q5/Q6/Q8 sets) [17]; on-node PLE probe gate required (§2B). |
| unsloth MTP `*-shared-*` modules (NEW) | 2026-11-04 [1][3] | shared-Q8_0 2.79 GB vs full Q8_0 4.14 GB (−1.35 GB). Documented for llama.cpp (`-md` + danielhanchen fork branch `qwen4exp/mtp`); Strata provisions its own `mtp/rt` — compatibility with shared modules **[—]**. |
| ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF | 2026-09-29 — unchanged [8] | Our IQ3_S pair (revision ed59f920) is still the current ISTA release. Nothing supersedes it from ISTA. |
| bartowski/Qwen3.8-Flash-Next-GGUF | 2026-10-13 [HF API] | llama.cpp-oriented mirror line; no Strata pack path, nothing new in Nov. |
| mradermacher flash-next repos | 2026-08-29 [HF API] | Stale; i1 imatrix line, no Nov activity. |
| orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF (gated `auto`, HF_TOKEN) | 2026-10-27 [HF API] | Unchanged — our orca IQ4_XS trio (resolve/main + byte pins in `fetch_models.sh`) is safe; ladder still IQ4_XS 97.47 GB / Q4_K_S 111.77 GB / no UD rung (cf-86 R4-Q stands). |
| SkyIsNotGreen/Scion-FlashNext-176B-A6B (NEW) | 2026-11-05 [7][9] | Experimental ternary/2-bit community line (F16 65.8 GB, Q6_K 60.2 GB, Q6_K-Q4X160 57.6 GB, apache-2.0). A "Strata-compatible Q2 bridge repack" scored 28/30 tasks vs UD-Q2_K_XL 30/30 in a community 30-task A/B at ~4× the effective tok/s on a slow box (different spec settings — not engine-comparable) [7]. Experimental; not a production candidate. |
| amd/Qwen3.8-Flash-Next-Quark-MXFP4 | updated 2026-11-10 [HF search] | AMD-official MXFP4 checkpoint for the vLLM/Radiance path — not GGUF, not Strata-loadable (arch guard); relevant only to a future vLLM-on-flash-next idea. |
| Ornith siblings | unsloth/Ornith-1.5-122B-GGUF unchanged since 2026-10-21 [HF API] | No new 122B ladder; new small siblings (Ornith-1.5-9B community GGUFs, Nov 9) and a zephel01 Ornith-1.5-397B-IQ2_XXS exist — nothing that changes our ornith-strata carry rung or fits this node better. |

**Strata engine support nuances (confirmed at v0.2.13):** v3.1 sets require engine
≥0.1.57 (`UNSLOTH_V31_ENGINE = (0,1,57)`; "i-quant experts with Q2_0/IQ4_NL/Q5_0
downs, a Q6_K dense side") [5]. `UD-IQ1_S` does not load at all (mixed expert formats
in one layer) [16]. Plain IQ4_XS experts remain kernel-supported on the q38 path
(our orca rung's basis, engine 0.1.31/0.1.32) [5][16]. PLE policy at v0.2.9
(auto-RAM when table+8 GiB fits, else `direct`) is what our node measured on boot
(DIRECT, 120,960 rows/s vs 15,000 warning line — repo U14 record); nothing in
0.2.10–0.2.13 changes that policy for our arena sizes [16].

---

## 4. The actual q3/q4-class ladder downloadable today (Q2)

Arena GiB = setup.py `arena_gb` × 0.9313 (GB→GiB), calibrated 1:1 against our two
node-measured arenas (IQ3_S 50.3 GB→46.84 GiB measured; UD-Q4_K_XL 77.0 GB→71.71
vs 71.73 GiB logged) [5][repo]. "Node envelope" = arena + conv budget + 4-slot 262k
int8 KV (13.4 GiB) + ~6 GiB dense/MTP/supervisor — the repo's own decomposition
style, KV now from §5 arithmetic [E]. Node law: 125.1 GiB total, measured non-strata
container floor 2.97 GiB + OS/k3s (U14 all-in ~7.3 GiB) [15].

### q3-class (arena ≲53 GiB)

| Artifact | Source / gating | Disk (exact) | Arena GiB | Envelope GiB (conv as noted) | Quality | Decode tok/s | Prefill tok/s |
|---|---|---|---|---|---|---|---|
| **ISTA GSQ-RCO IQ3_S** (current flagship) | HF ISTA-DASLab, public | 83.62 GB (2 shards) [8] | **46.84 [M-node]** | ~98 (conv 32) / ~74 (conv 8) [E] | 87.69% top-token vs Q8_0; KL 0.144; ppl 4.097 [M-9700, upstream yardstick 17] | 91–98 short-prompt single (R9700, 0.2.11) [M-9700 16]; 72.9 chat / 75.0 agent (RX 9070 XT bench) [M-9700 11]; 75 story/95 code (DDR4 R9700 rig = floor) [R-near 17]; 80 @64K one-at-a-time (PR #3636 node class) [R-near repo] | 1,519 cold 72k single [M-node repo U14]; 3,076→3,304 @32K (R9700, 0.2.11→0.2.12) [M-9700 16]; 1,048@4K / 1,229@16K (RX 9070 XT) [M-9700 11]; 2,505–2,802 @8K/32K (125 GB-RAM R9700 ref box, 0.2.7) [R-near repo]; ≈2,519 @64–200K node-class bar (PR #3636) [R-near repo] |
| **unsloth UD-IQ3_XXS v3.1** (NEW 11-04) | HF unsloth, public; Strata catalog ≥0.2.11, engine ≥0.1.57 [5][16] | 83,626,438,426 B (4 files; last = shared 28.8 GB engram) [1] | 46.85 [E from 5] | ~98 (conv 32) [E] | vendor: top-1 recovery 85.4%, KLD 0.165 vs baseline [V 3]; Strata yardstick **[—]** | 60–65 @256k (RX 9070 XT + 64 GB, one user) [M-9700 19]; 85–95 @128k single-slot (RTX 5070 12GB + 64 GB DDR4, engine 0.1.59, strata_bench #5687) [R-near 33] | **[—]** single-R9700 Linux |
| **unsloth UD-Q3_K_XL v3.1** (NEW 11-04) | same; 20/48 layers Q5_0 down → wants `STRATA_PF_FUSED_Q50=1` (0.2.12+) [6][16] | 89,464,948,506 B (4 files) [1] | 52.34 [E from 5] | ~104 (conv 32) / ~88 (conv 16) [E] | vendor: top-1 88.3%, KLD 0.107 [V 3]; Strata yardstick **[—]** | **[—]** (Q5_0 penalty class on AMD pre-kernel: −40–55% prompts on gfx1151 [M-near 6]) | **[—]** |
| ISTA IQ3_XXS | HF ISTA, public | 75.8 GB [5] | 39.95 [E] | ~91 (conv 32) [E] | 84.46% top-token; ppl 4.119 [M-9700 17] | "slower (more CPU work per token)" [17]; 47–49 (RTX 3060 12GB/62 GiB RAM, IQ3_XXS native pack) [R-near 34]; 30–50 (RX 7900 XTX, 32 GB RAM, streaming) [R-near 19] | ~800 (RX 7900 XTX) [R-near 19]; 1,043–1,088 (RTX 3060/62 GiB) [R-near 34] |
| orcarouter IQ3_XXS (uncensored) | HF orcarouter, **gated HF_TOKEN**; ORCA.md manual-pack path | 85.20 GB [repo ORCA record] | ~49.8 [E repo] | ~96 (conv 32) [E] | ablation: KLD-class per cf-86 (orca 0.022 vs heretic 0.019) [repo]; yardstick **[—]** | **[—]** | **[—]** |
| SC117 abliterated IQ3_S / IQ3_XXS (uncensored) | HF SC117, public (repo removed the rung per U9.3) | 83.86 / 76.14 GB [repo R4] | ~46.9 / ~40 [E] | as IQ3_S / IQ3_XXS | same format family as ISTA; yardstick **[—]** | **[—]** | **[—]** |

### q4-class (arena ≈56–77 GiB)

| Artifact | Source / gating | Disk (exact) | Arena GiB | Envelope GiB | Quality | Decode tok/s | Prefill tok/s |
|---|---|---|---|---|---|---|---|
| **unsloth UD-Q4_K_XL** (current production runner) | HF unsloth, public; Strata-pinned rev 38bb39ee (09-30) — V3.1 re-split is same weights [5][16] | 111,334,654,784 B pinned (main now 111,334,654,778 B re-split) [1][repo] | **71.73 [M-node]** | ~107–109 (conv 16, 4 slots) — **over its own 101.25 GiB cap; over node with floor+transients** [E §5] | 93.09% top-token vs Q8_0; KL 0.056; ppl 4.068 (Q8_0: 4.052) [M-9700 17]; vendor top-1 recovery 92.3% [V 3] | **40–60 under production agent traffic (56–99k ctx, concurrency) [M-node]**; 72–104 short-prompt single (R9700, 0.2.11, tail-skip on) [M-9700 16]; 56.6 chat / 58.0 agent (RX 9070 XT) [M-9700 11]; 63–64 story / 85–88 code (DDR4 R9700 = floor) [R-near 17]; 94 + DFlash2 (R9700, 0.2.10) [M-9700 16]; 46.6–49.1 (Strix Halo, 0.2.13) [R-near 16] | **19–332 on 56k–99k prompts under concurrency [M-node]**; 1,519 single cold [M-node]; 750@4K / 900@16K (RX 9070 XT) [M-9700 11]; 1,110–1,320 @32K (DDR4 R9700) [R-near 17]; R9700 32K prompts +8.6–11.6% at 0.2.12 and K-quant MMQ default +10–17% at 0.2.11 (gfx12) [M-9700 16] |
| **unsloth UD-IQ4_XS-v31** (NEW 11-04) | HF unsloth, public; engine ≥0.1.57; 33/48 Q5_0 down layers → `STRATA_PF_FUSED_Q50=1` strongly advised on AMD [6][16] | 93,672,359,738 B (4 files) [1] | 56.25 [E from 5] | ~92 (conv 16) / ~100 (conv 24) [E] | old UD-IQ4_XS yardstick 88.91% top-token / KL 0.101 / ppl 4.120 [M-9700 17]; **v31 file changed 345/1224 tensor types — its own yardstick [—]**; vendor top-1 89.6% [V 3] | 40–50 @256k (RX 9070 XT, one user — "~40% penalty vs IQ3_S") [M-9700 19]; 56.6–60.2 (R9700+6800XT mixed split, old IQ4_XS, 0.1.58) [M-9700 18] | v31 without Q5_0 kernel: −40–55% vs old file (Strix Halo A/B: 381–760 vs 870–1,293) [M-near 6]; with 0.2.12 gfx12 defaults: 2,817–3,015 @32K (R9700) [M-9700 16] |
| unsloth UD-IQ4_XS (OLD, 3-shard) | only at pinned rev 38bb39ee (folder on main now holds v31 files) [1][5] | 93,682,584,224 B [repo cf-86] | 55.4 [E from 5] | ~91 (conv 16) [E] | 88.91% / KL 0.101 [17] | 63.9–66.0 (Strix Halo, 0.2.10-era) [M-near 6] | 870–1,293 (Strix Halo) [M-near 6] |
| orcarouter IQ4_XS (current orca rung, uncensored) | HF orcarouter, **gated HF_TOKEN** | 97,473,155,200 B (3 shards) [repo] | 57.7 [E ratio, repo-recorded] | ~85 (conv 8, as shipped cap 92160) [repo] | ablation KLD 0.022 vs original [repo cf-86]; yardstick **[—]** | **[—]** (never measured on-node — repo record) | **[—]** |
| orcarouter Q4_K_S (uncensored) | gated; manual path documented; needs `STRATA_ORCA_Q4KS_MMQ=ON` engine build flag (no setup hook — image-side governance; declined as C11) [repo R4/R5] | 111.77 GB [repo R4] | ~72.0 [E ratio] | ~101 (conv 8) [E] | **[—]** | **[—]** | **[—]** |
| spiritfather heretic-2 Q4_K_M (uncensored) | HF public | 140.41 GB [repo R4] | 83–90 [E repo R4] | **BLOCKED-at-envelope** (cf-86 R4-H verdict stands; all-in-RAM impossible; budget mode ×1.34–1.40 decode penalty) | arch verified identical (qwen4exp) [repo R4] | — | — |

### Adjacent rungs worth knowing (outside the q3/q4 ask, node-feasible)

- **UD-Q2_K_XL v3.1** (79.58 GB, arena ≈42.8 GiB [E]): community 30-task A/B 30/30 tasks [7]; R9700 numbers **[—]**.
- **UD-IQ1_M v3.1** (68.0 GB, arena ≈32.4 GiB [E]): R9700 start 114 s, decode **100–130 tok/s** (0.2.11 real-file test) [M-9700 16] — the fastest flash-next decode datapoint on our exact card, at 1-bit quality (vendor top-1 79.7% [V 3]).
- Gyro-M (92 GB down / ~35 GB memory class, decode −16–21% vs Q2_0) [17]; Coder IQ1_M (58.4 GB / arena 23.4 GB → 21.8 GiB, the only true-coexist tier) [5].
- llama.cpp-served rungs of the same files stay dramatically slower on this family: 18–20 tok/s decode for UD-Q4_K_XL on the same R9700 [R-near 17] — the Strata arena is the right engine here; no finding in this research argues for moving flash-next back to llama.cpp.

---

## 5. KV per-token arithmetic and what it implies (Q3)

**Architecture (verified three ways: repo GGUF-header census cf-86 [B6], setup.py
v0.2.13 source, upstream engine logs):** qwen4exp has 48 layers with
`full_attention_interval 4` → **12 full-attention (QSA) layers**, plus the **MTP
draft layer** carries KV → **13 KV-bearing layers**. Per-layer int8 KV cell =
**1,056 B/token** (setup.py `KV_CELL_BYTES`/`UD_FIT_KV_BYTES`: int8 1056, k8v4 816,
q4_0 576, fp16 2112) [5]. An engine boot log on a gfx1201 box confirms the aggregate:
*"KV streaming: 32768 of 262144 cells per QSA layer in VRAM, the K/V in 3.09 GiB of
pinned RAM"* — 262,144 × 12 × 1,056 B = 3.09 GiB exactly [11].

**The law (int8, streaming mode, which our 262,144-context profiles are in):**

| Quantity | int8 | k8v4 | q4_0 |
|---|---|---|---|
| Bytes per context token (13 layers) | **13,728 B (13.7 KB)** | 10,608 B | 7,488 B |
| **Per 100k tokens, per slot** | **1.373 GB = 1.28 GiB** | 1.06 GB = 0.99 GiB | 0.749 GB = 0.70 GiB |
| Full 262,144 ctx, per slot | 3.599 GB = **3.35 GiB** | 2.78 GB = 2.59 GiB | 1.96 GB = 1.83 GiB |
| 2 slots × 99k (the incident shape) | 2.71 GB | — | — |
| 4 slots × full ctx (worst case) | 14.4 GB = **13.4 GiB** | 11.1 GB = 10.4 GiB | 7.9 GB = 7.3 GiB |

Quality/speed trade (upstream docs, version-stable since ≤0.2.9): `q4_0` halves KV
(+4% faster at 128K; long-document perplexity +8–12%, needle tests still pass);
`k8v4` = −23% KV vs int8, more precise than q4_0, prompts 2–5% slower [10][20].

**`--kv-resident` is NOT a RAM budget (correction to values.yaml comments and the
debug note).** `--kv-resident N` keeps N KV *cells* (token positions) per QSA layer
in **VRAM** and streams the rest from pinned host RAM; the host-RAM cost is
`context × 13,728 B` per slot **regardless of N**. N=32768 costs ≈0.39 GiB VRAM
(+~0.17 GiB DeltaNet state; setup's measured "0.56 GiB at 32K int8" per slot)
[5][10][11]. Implications:
- Lowering `--kv-resident 32768→16384` (debug-note rec 2) frees **zero host RAM**; it shrinks the VRAM attention window (more re-reads from host during deep-context decode). The RAM levers are `--max-context`, the slot count (`parallel:`), and `--conversation-cache-mib`.
- The repo's counted "worst-case ~13 GiB 4-slot KV" was numerically right (13.4 GiB) — keep that term in budgets, now derived rather than estimated.
- `--max-context 262144→131072` on q4 would halve per-slot KV to 1.68 GiB (4-slot worst 6.7 GiB) at the cost of the 262k advertisement (catalog true-axis implication — owner ruling class, cf. D31-style).
- Parking snapshots are additional host RAM on top of live KV ("snapshots hold running state, checkpoints, used K/V pages and draft-layer K/V... They add host RAM, not VRAM") — a parked 99k conversation ≈ another ~1.3 GiB, bounded only by `--conversation-cache-mib` [10].
- `--conversation-cache-mib 16384` is therefore a real worst-case adder of 16 GiB (it is a budget the engine fills on demand), and its eviction path is currently buggy on Linux (#5697 — evicted bytes stay in the glibc heap; `MALLOC_MMAP_THRESHOLD_=1048576` workaround reporter-confirmed in Docker, ~40 requests 0 refusals) [12]. The guard-accounting class (#5504: clean `active_file` cache not credited; #5519: ZFS ARC) also matches our recorded U14 "3259 MiB available, source flag while node MemAvailable read 40 GiB" experience [13][26].

**Right-sized budget formula (proposed convention for values comments):**
`cap ≥ arena + conv + slots × min(max_context, ctx) × 13,728 B + ~6 GiB` and
`cgroup ≤ node_total − measured_floor − transient_margin`, with the measured floor
~7–8 GiB (containers 2.97 GiB live + OS/k3s/kernel; U14 record ~7.3 GiB all-in) and
a transient margin ≥8–10 GiB (the 2026-11-10 collapse added ~25 GiB over the steady
base during doubled 99k prefills — composition not fully recoverable after the fact;
candidates: parking snapshots up to conv budget, checkpoint pools, prefill staging
rings/buffers, page-cache transients) [15][12][E].

---

## 6. Upstream incident correlation since Oct 2026 (Q4)

**Direct matches to our failure class (node-RAM exhaustion / long-context / concurrency):**

| Ref | Date | Machine | What happened | Relevance |
|---|---|---|---|---|
| Strata **#5697** (open) [12] | 2026-11-10 | Docker/Linux, Claude Code agent, 150–169K + 55K alternating convs | Once the conv cache filled, the RAM admission gate evicted ~6 GB but MemAvailable never rose (glibc heap retention) → 11 parking refusals in 25 min → 151–159K-token re-reads (~57 s each). Present in 0.1.58/0.1.59; predecessors #2934/#3115 closed in tracker reset; fix #2253 open | **Highest relevance**: our fleet's exact usage shape (agent controller+worker histories); explains parking-refusal spirals and re-prefill amplification on ANY engine version incl. our 0.1.55; one-env-line workaround |
| Strata **#5635** (open) [22] | 2026-11-09 | 121 GiB RAM, 2×RTX 3060, IQ3_S 256k | 0.1.58 load peak 114.8 GB vs ~67.8 GB on 0.1.57 → systemd-oomd SIGKILL, reproducible with 117 GiB free; also `--no-tui` foreground regression breaking systemd units | Bump-hazard: 0.1.58 imports a load-time RAM regression |
| Strata **#5559** (open) [21] | 2026-11-08 | **R9700 32 GB + 9800X3D + 128 GB RAM** (nearest twin of ai-gpu), IQ3_S abliterated, `--ple-io ram`, conv 20480×6, parallel 2 | 0.1.58: 9 crashes in 5 h under 35K–92K prompts (GPF in libhsa-runtime64; exit −6/−11; kernel Bad-page-map on the PLE GGUF mmap); 0.1.57 clean on this box; control's "usual cause is running out of RAM" hint misleading (no OOM-killer line) | Same card+RAM class as ours; long-prompt crash class; warning that engine "out of RAM" messages can mislead |
| Strata **#5608** (open, 10 comments) [23] | 2026-11-08 | RX 9070 XT gfx1201, 64 GB, CachyOS (kernels 7.3.1 + 6.18.55) | Repeatable AMDGPU gfxhub page faults during IQ3_S inference on **both 0.1.57 and 0.1.58**; exit −13 | Contradicts #5559's "0.1.57 clean" → gfx1201 stability is box-dependent; argue for staying on the node-proven 0.1.55 or soak-testing any bump |
| Strata **#5564** (open) [35] | 2026-11-08 | IQ3_XXS, 0.1.58 | Prefill stuck at ~111K tokens; cancel leaves busy-wait | Long-prefill hang class in 0.1.58 |
| Strata **#5504** (open) [13] | 2026-11-07 | production Linux, mmap-heavy | Memory guard credits only `inactive_file`; 17.5 GiB clean `active_file` invisible → refused 50 MiB session read with 28 GiB free | Matches our U14 "source flag" parking-refusal record; guard accounting is a known-open defect class |
| Strata **#5519** (open) [26] | 2026-11-07 | ZFS host | ARC treated as unreclaimable → engine self-limits | Same family |
| Strata **#5317/#5341 → PR #5531** (fixed 0.2.13) [14][16] | 2026-11-05/09 | Linux | 0.2.10+ arena RAM check ignored file-cache/hugetlb headroom → fell back to `--mmap-experts` (decode −2.4× per #5327); 0.2.13 loads the arena when free memory/file cache/hugetlb can hold it | If we ever bump to 0.2.10–0.2.12, expect arena-load pathologies; 0.2.13 is the first with the fix |
| llama-swap **#1295** (open) [29] | 2026-11-01 | — | Feature request: yieldable VRAM/RAM for elastic engines (Strata named) in the merged capacity router (#1242); today only external cmd/cmdStop scripts | Upstream direction for the repo's open card `igToA96TH8aYJHWKf` (single llama-swap instance + capacity routing) |
| llama-swap **config docs** [28] | current main | — | `concurrencyLimit` / `globalConcurrencyLimit`: excess requests get **HTTP 429 immediately — "rather than being queued"** (#1256's 503-instead ask closed) | Corrects the debug note's "retries queue" phrasing: single-flighting works, but as reject-and-client-retry |
| PR **#4967** (open) [27] | 2026-11-02 | Fedora/Ubuntu | serve would warn when systemd-oomd is running and name it on signal-9 deaths (oomd kills before the kernel OOM killer, no dmesg line) | Diagnostic hygiene for exactly our ambiguity class (SystemOOM vs oomd vs engine abort) |

**Community (Reddit/HF) correlations:** ≥131K context + `--parallel` = "severe speed
drop or OOM" rule of thumb; conv-cache 4 GiB/2-slot sizing on small boxes [30];
90K-context hard OOM on a 32 GB-RAM RX 7900 XTX box [31]; PLE-table-on-NVMe proven
viable (~4% decode cost) with "fan out shallow, serialize deep" as the concurrency
law and cgroup write-caging to protect serving [32]; a Strix Halo 128 GB user traced
extended-session crashes to the AMDGPU kernel driver+SMU (self-patched) — gfx-class
instability on 128 GB boxes is not unique to our node [36].
**No upstream report found** that matches our exact incident (k3s cgroup 116Gi +
two concurrent ~99k prefills on a 125 GiB single node) — our failure was
configuration-envelope-first, with #5697-class parking behavior as amplifier [—].

---

## 7. Contradictions and how to weigh them

1. **0.1.57 on gfx1201**: #5559 says clean (R9700/Ubuntu), #5608 says repeatable page faults (9070 XT/CachyOS). Both open, different machines. Weigh: treat *no* post-0.1.55 engine as proven on gfx1201; bump only behind the repo's ledger + soak + `--plan` + re-bench law.
2. **Incident causation**: debug note's "KV demand well past 13 GiB" vs arithmetic (2×99k = 2.7 GB KV). Weigh: the engine-log-verified KV law wins; the kill was steady-base (90–99 GiB) + parking/heap/transients against a node with ~7–12 GiB floor and a 116Gi cgroup. Mitigation ranking shifts accordingly (cgroup resize + single-flight + conv trim + malloc env > kv-resident trim).
3. **`--kv-resident` units**: repo comments ("32 GiB streaming budget") vs setup.py + DETAILS.md + boot log (32,768 VRAM cells ≈ 0.4 GiB). Three concurring primary sources; repo docs should be corrected in a future docs round (not this research's write scope).
4. **V3.1 quality**: vendor +10–15% (26.2B tokens, 256K agentic, self-graded) [3][4] vs one gfx1201 user "no substantial quality difference" + measured AMD speed penalties [6][19]. Weigh: vendor method is heavy but unaudited and llama.cpp-side; the *speed* penalty is measured and reproducible (revision revert restores old numbers exactly [6]). Treat V3.1 quality gain as plausible-but-unproven for Strata serving; treat the Q5_0 prefill penalty as fact requiring ≥0.2.12 + `STRATA_PF_FUSED_Q50=1`.
5. **Cluster baseline**: 10–13 GiB (debug note) vs 2.97 GiB measured containers + ~7.3 GiB U14 all-in floor. Weigh: ~7–8 GiB planning value, 10 GiB conservative; the cgroup conclusion (116Gi too big beside the floor) holds under both.
6. **R9700 q4 decode band**: upstream 72–104 tok/s (short, single, 0.2.11) vs our 40–60 (long-context, concurrent). Not a conflict: QUANTS.md's own "after a 6K document" row (70–72) and #4943's agent row (58) bracket our figures; our fleet is 96% prefix-cached with deep contexts. Both true; label the regime with every number.

**Blind spot nobody covered (valuable):** no published Strata top-token yardstick for
any v3.1 set; no single-R9700-Linux speed for UD-IQ3_XXS/UD-Q3_K_XL v31; no evidence
yet that 0.1.59 clears #5559/#5635/#5608; no on-node tok/s ever recorded for our orca
IQ4_XS rung; and the exact GiB decomposition of the 11-10 transient is not recoverable
from existing metrics (would need cgroup `memory.stat` sampling during a repro).

---

## 8. Open questions (owner / follow-up cards)

1. Take the four envelope repairs (§2A) as one values PR? (malloc env line; concurrencyLimit 1 on q4 with the 429 caveat; parallel 4→2 and/or conv 16→8 on q4; cgroup 116→~108–110Gi.) Each is owner-gated budget law.
2. Correct the values.yaml/README `--kv-resident` and "worst-case KV" comments to the derived arithmetic (docs round; includes the debug-note rec-2 correction)?
3. Schedule a gated engine-bump evaluation (0.2.13/0.1.59 soak on a branch image, ledger + `--plan` + re-bench + #5559/#5635 re-check), or stay on 0.2.9 until upstream closes the gfx1201 cluster?
4. If a bump happens: trial `UD-IQ3_XXS` v3.1 as a q3 alternative (same envelope as IQ3_S) with an on-node yardstick run (`tools/quant_quality.py`) before any routing change?
5. Trial the engram Q5_1/Q8_0 table swap on the q3 or q4 arena (disk headroom + PLE direct-read probe re-gate first)?
6. Watch list: Strata #5697/#2253 (malloc_trim fix), #5504/#5519 (guard accounting), #5559/#5608/#5635 (gfx1201 + 0.1.58 class), #5317→PR #5531 (landed 0.2.13), llama-swap #1295 + capacity router; unsloth repo revisions (our setup pins are revision-safe, but any future manual fetch from `main` gets v31 files).

---

## 9. Reliability notes (STORM self-review)

- **Confidence**: KV arithmetic 9/10 (setup.py source + docs + an independent engine boot log all agree to the byte). Catalog bytes/arenas 9/10 (HF API + calibrated setup figures; two node-measured anchors). Release/regression landscape 8/10 (primary release bodies + live issue states; the ground moves weekly — #5559 had 0 comments at fetch). V3.1 quality claims 5/10 (vendor-only, no independent Strata-side reproduction). gfx1201 tok/s transferability 6/10 (same GPU arch; host RAM bandwidth, OS and sampling regimes differ). #5697 workaround 7/10 (single reporter, but Docker-confirmed with smaps evidence and a well-understood glibc mechanism).
- **Weakest claim**: "0.2.13/0.1.59 is a safe bump target" — *not* claimed here; the honest state is "unproven, two open gfx1201 crash reports against its predecessor, one load-RAM regression unfixed as of fetch." Verification would be a soak run on a branch-built image with #5559's traffic shape.
- **Over-weighted perspective**: the release watcher (rich primary sources) vs community sentiment (Reddit fetches are partial; searxng MCP degraded mid-run — native search substituted).
- **6th angle that would change conclusions**: on-node measurement of the incident transient (cgroup memory.stat + per-slot parking counters during a controlled doubled-99k repro). If prefill staging rings (not parking) dominate, conv-cache trimming buys less than §2A implies and single-flighting buys more.

---

## 10. Citations (all accessed 2026-11-10)

Web sources (numbering matches the storm run's `sources.md`):
1. https://huggingface.co/api/models/unsloth/Qwen3.8-Flash-Next-GGUF/tree/main — current file tree incl. V3.1 sets + `engram/` folder (exact bytes).
2. https://huggingface.co/api/models/unsloth/Qwen3.8-Flash-Next-GGUF — repo metadata (sha 084c631a, lastModified 2026-11-07, ungated).
3. https://unsloth.ai/docs/models/qwen3.8-next — Dynamic V3.1 announcement (Nov 4 2026), benchmark method (26.2B tokens, 256K agentic), top-1/KLD table, engram mix-and-match + RMSE table, hardware/MTP tables.
4. https://x.com/danielhanchen/status/2118037508139413742 — V3.1 release tweet (+10–15% vs GSQ-RCO; engram RMSE figures).
5. https://raw.githubusercontent.com/Niko1221/Strata/v0.2.13/setup.py — catalog `arena_gb`/`download_gb` per set; `KV_CELL_BYTES` (int8 1056/k8v4 816/q4_0 576/fp16 2112); `kv_streaming_ram_gb` (13×1056); `parallel_slot_gb` ("0.56 GiB at 32K int8"); `UNSLOTH_V31_REVISION d9620119…`, `UNSLOTH_V31_ENGINE (0,1,57)`, `UNSLOTH_Q4_V31_SHARDS`/`sha256_alt`; HF_REVISIONS pins (unsloth 38bb39ee 09-30, ISTA ed59f920 09-29).
6. https://github.com/Niko1221/Strata/issues/5296 — v3.1 UD-IQ4_XS 40–55% slower prompt reads on gfx1151 (Q5_0 down layers off the fused path); full Strix Halo A/B table; revision-revert control.
7. https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/discussions/93 — community 30-task A/B: UD-Q2_K_XL v3.1 vs Scion Q6_K / Q2-bridge repack.
8. https://huggingface.co/api/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF — unchanged since 2026-09-29 (sha ed59f920…, 6.95M downloads).
9. https://huggingface.co/api/models/SkyIsNotGreen/Scion-FlashNext-176B-A6B — Scion experimental packs (2026-11-05; F16 65.8 GB / Q6_K 60.2 GB / Q6_K-Q4X160 57.6 GB).
10. https://raw.githubusercontent.com/Niko1221/Strata/v0.2.13/docs/DETAILS.md — `--kv-streaming` (13.7 KB/token; 1.7 GB at 128K), `--kv q4_0/k8v4` trade rows, conversation-cache defaults (40% above floor, ≤8192 MiB), `--memory-limit-mib` scope ("parking and session files only"), arena-fit behavior (#4051 wait, file-cache load, `--ram-keep-gib`, `STRATA_ARENA_FILE_CACHE`), snapshot contents ("add host RAM, not VRAM"), session files still "Linux and CUDA only".
11. https://github.com/Niko1221/Strata/issues/4943 — RX 9070 XT (gfx1201) iq3_s vs ud-q4_k_xl strata-bench table (72.9/56.6 decode; 1,048/750 @4K; 1,229/900 @16K); engine log "KV streaming: 32768 of 262144 cells per QSA layer in VRAM, the K/V in 3.09 GiB of pinned RAM"; prefill-collapse→reboot recovery anecdote; 128 GB-RAM class box.
12. https://github.com/Niko1221/Strata/issues/5697 — evicted parked conversations stay in glibc heap (open 2026-11-10; present 0.1.58/0.1.59; `MALLOC_MMAP_THRESHOLD_=1048576` workaround with smaps evidence; #2253 malloc_trim fix open).
13. https://github.com/Niko1221/Strata/issues/5504 — memory guard doesn't credit clean `active_file` cache (matches our U14 parking-refusal record).
14. https://github.com/Niko1221/Strata/issues/5317 — arena RAM check ignores hugetlb pool → mmap fallback (0.2.10+); fixed via PR #5531 in 0.2.13.
15. Grafana/Prometheus `prometheus.spencerslab.com` live reads (cluster=gpu-ai, 2026-11-10 ~13:10 UTC): `node_memory_MemAvailable_bytes` 27.96 GiB now / 0.23 GiB 24h-min; strata container working set 115.06 GiB; all other containers Σ2.97 GiB; `kube_pod_container_status_restarts_total`=11 (pod …-x8r57).
16. https://api.github.com/repos/Niko1221/Strata/releases — v0.2.10/0.2.11/0.2.12/0.2.13 full bodies (v3.1 catalog + revision/engine-minimum notes; gfx12 defaults: MMQ K-quant +10.3/14.3/16.8%, auto-ceiling 32768, ring 256/192; route-tail-skip R9700 A/B 72–104 tok/s & KL 0.077; 0.2.12 R9700 prompt rows 3,076→3,304 / 2,817→3,015, GDN ≥30K +6.1/6.7%, `STRATA_PF_FUSED_Q50` +44/40%; 0.2.13 gfx1201 hipBLASLt-table-off default, #5327/PR #5531, DFlash2 per-card defaults, known-problems incl. gfx1201 DFlash2 stall).
17. https://raw.githubusercontent.com/Niko1221/Strata/v0.2.13/docs/QUANTS.md — per-file expert formats (UD-Q4_K_XL: Q4_K/Q5_K gate-up, Q5_1 downs, PLE IQ4_NL 26.8 GiB); quality yardstick on R9700/HIP (UD-Q4_K_XL 93.09%/KL 0.056/ppl 4.068; IQ3_S 87.69%/0.144/4.097; UD-IQ4_XS 88.91%; IQ3_XXS 84.46%; Q2_0 80.60%); R9700+EPYC-DDR4 speed table (IQ3_S 75/95, prompt 1,555; UD-Q4_K_XL 63–64/85–88, prompt 1,110–1,320; llama.cpp same card 18–20/198–257); decode-window anatomy; resident-vs-budget ×1.34–1.40.
18. https://github.com/Niko1221/Strata/issues/5565 — R9700+RX 6800 XT mixed split, UD-IQ4_XS, 0.1.58 source build: prompt-4k 533 / prompt-16k 865 / decode 56.6–60.2 (standard-v1 ×3).
19. https://llamaperf.com/model/qwen3-8 — community reports (as of 2026-11-10): RX 9070 XT + 64 GB Strata @256k (IQ3_S 70–75; UD-IQ3_XS-v31 60–65; UD-IQ4_XS-v31 40–50 tok/s); Strix Halo Gufo UD-Q4_K_XL (1,888 pp@16K; 34.1–41 decode); libosmos ud-iq3_xxs (873 pp@2k; 27.1/45.6 decode); 4×R9700 Radiance fp8-iq4r (195 tok/s @32K, ~6,800 pp aggregate, PLE 47.7 GiB pinned); R9700 4-bit partial-RAM median 31.3 gen / 279.3 pp.
20. https://raw.githubusercontent.com/Niko1221/Strata/v0.2.9/docs/DETAILS.md — pin-baseline checks: kv-streaming/13.7 KB and memory-guard text already present at 0.2.9; `--ram-keep-gib` and `STRATA_ARENA_FILE_CACHE` absent at 0.2.9.
21. https://github.com/Niko1221/Strata/issues/5559 — 0.1.58 hip-rx9070 gfx1201 GPF crash storm (R9700/9800X3D/128 GB; 35K–92K prompts; 0.1.57 clean there; kernel Bad-page-map on PLE mmap).
22. https://github.com/Niko1221/Strata/issues/5635 — 0.1.58 load-RAM regression (114.8 GB vs 67.8 GB peak) → systemd-oomd kill; `--no-tui` systemd breakage.
23. https://github.com/Niko1221/Strata/issues/5608 — RX 9070 XT gfx1201 repeatable GPU page faults on 0.1.57 AND 0.1.58 (CachyOS).
24. https://github.com/Niko1221/Strata/issues/5558 — 0.2.12 fails to start flash-next unsloth Q8_0 256k.
25. https://ghcr.io/v2/niko1221/strata/tags/list — images exist for 0.2.11/0.2.12/0.2.13 (rocm-gfx120x + gfx1151); **0.2.10 absent** (image-gap law).
26. https://github.com/Niko1221/Strata/issues/5519 — ZFS ARC treated as unreclaimable (guard-accounting family).
27. https://github.com/Niko1221/Strata/pull/4967 — serve: warn about systemd-oomd; name it on signal-9 deaths (open).
28. https://github.com/mostlygeek/llama-swap/blob/main/docs/config.example.yaml — `concurrencyLimit`/`globalConcurrencyLimit`: excess requests get HTTP 429 immediately, "rather than being queued".
29. https://github.com/mostlygeek/llama-swap/issues/1295 — yieldable VRAM/RAM for elastic engines (Strata) in the capacity router (open; follow-up to merged #1242).
30. https://www.reddit.com/r/LocalLLaMA/comments/1xft2ae/ — Strata on 8 GB VRAM/32 GB RAM guide: "≥131K context… cannot safely use --parallel… severe speed drop or OOM"; conv-cache 4096/2-slot sizing (2026-11-10).
31. https://www.reddit.com/r/LocalLLM/comments/1wxsjbk/ — Strata Tuning Guide thread; comment: RX 7900 XTX + 32 GB, IQ3_XXS, "when the context reach 90k the model crash out of memory".
32. https://www.reddit.com/r/LocalLLaMA/comments/1w1p065/ — 2×3090 + 96 GB: PLE mmap'd on NVMe viable (vLLM: 15.3 vs 16.0 t/s stubbed ≈ 4% cost); "Concurrency erases it — fan out shallow, serialize deep"; cgroup write-caging.
33. https://github.com/Niko1221/Strata/issues/5687 — community strata_bench (2026-11-09): UD-IQ3_XXS v3.1, RTX 5070 12GB + i7-12700K/64 GB DDR4, Ubuntu, Strata 0.2.13 / engine 0.1.59, 131072 ctx, 1 slot: 85–95 tok/s decode class (3-run medians; speed-only suite).
34. https://github.com/Niko1221/Strata/issues/5289 — 0.1.56-era isolation table (RTX 3060 12GB, 62 GiB RAM, sm_86): IQ3_XXS native pack prefill medians 1,043–1,088 tok/s, decode 47–49 (STRATA_KVA=1 arm; the Q2_0 SIGSEGV subject of the issue).
35. https://github.com/Niko1221/Strata/issues/5564 — 0.1.58: IQ3_XXS prefill stuck at ~111K tokens; cancel leaves the engine busy-wait (open 2026-11-08).
36. https://www.reddit.com/r/LocalLLaMA/comments/1w7zz1o/ — thread comment (MISEMUNJIOZONE): Strix Halo 128 GB + Vulkan llama.cpp UD-Q4_K_XL — extended-session crashes traced to the AMDGPU kernel driver + SMU, fixed with a self-written kernel patch.

Repo records (internal, read-only): `.agents/plans/2026-11-10-debug-strata-q4-oom-crashloop.md`;
`.agents/notes/strata-host-prep-gpu-ai.md` (arena table §3.3, perf bar §3.4a, caps ledger);
`.agents/notes/vllm-on-target-acceptance.md` (§0.3/§8–9 RAM law; envelope-block method);
`charts/llama-swap/values.yaml` (model catalog + five strata profiles + budget comments);
`.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap/RESEARCH.md`;
`.agents/plans/2026/2026-10-cf-86-feat-more-strata-models/RESEARCH.md` (Rounds 1–5 incl. [A1][A2][B4][B7][C6]) + `DECISIONS.md` (U8/U9.2/U12/U13/U14);
`.agents/plans/2026/2026-10-debug-flash-next-vulkan-oom/RESEARCH.md`;
`containers/strata/Dockerfile` + `README.md` (0.2.9/0.1.55 pin ledger, carry patch, fetch driver).
