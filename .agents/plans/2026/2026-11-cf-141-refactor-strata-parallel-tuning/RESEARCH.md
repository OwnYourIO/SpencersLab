# RESEARCH — cf-141 refactor: Tune Strata for parallel performance (AD-141)

Round 1 — agent-research, 2026-11-10. Scope set by the launch brief: adjudicate the card's
0.2.13-era deployment guide against our **binding pin Strata 0.2.9 / engine 0.1.55** (OQ-1,
OQ-2, OQ-5, OQ-6, memory-budget inputs, and the 0.2.10→0.2.13 changelog that matters to the
guide). The bump evaluation (`.agents/plans/2026-11-10-dep-strata-engine-0213-eval.md`) is
NOT re-opened here.

Method: STORM-style multi-lens research run inline (lenses: launcher/config engineer, engine
C++ implementer, doc maintainer at the tag, upstream issue/PR reporter, release historian,
cluster operator). Primary evidence = the **full v0.2.9 source tree fetched at its exact
commit** and grepped locally, plus GitHub API reads of releases/issues/PRs. The lens
interviews collapsed to one shared ground truth: the pinned tag is checkable file-by-file,
so contradictions between the guide and the tag were settled from code, not from prose.
Evidence tags follow the card's own discipline: **[M]** measured in a cited upstream source,
**[E]** arithmetic/estimate, **[I]** inferred, **[V]** read by me at the v0.2.9 commit/API,
**[R]** repo record (file cited). Source keys `[n]` resolve in `## Sources` at the bottom.

## TL;DR (5 lines)

1. `parallel:` IS `--batch` at our pin: the 0.2.9 server translates the run-config key into
   engine `--batch N` [5][13]; the pinning law — **N slot sessions + 1 main session, each
   sized for the whole `--max-context`, allocated at engine start** — holds verbatim at
   v0.2.9 in code and docs [4][6][7][44].
2. Every flag the guide's tuning touches **exists at 0.2.9** except `--vram-reserve-mib` was
   unknown-to-repo (it exists, default 700 [18]) and the `--kv-pool-tokens` shared pool
   (absent, PR #1011 unmerged [34][44]); the full existence/default/semantics table is below.
3. Three concrete **at-pin tuning levers** the plan can adopt without a bump: the 9-variable
   parallel-request stack is **never** applied to HIP — not at 0.2.9, not even at 0.2.13
   [14][38] — and `STRATA_MMQ_KQ` (K-quant prompt kernels, later a gfx12 default, R9700
   +10–17% prompts) is opt-in-only at 0.2.9 [32][36].
4. `--kv q4_0` is real at our pin (PR #21 merged 2026-09-27, engine accepts it [3][8][43]);
   quality cost is modest on chat-style text (PPL +1.1%) but **doubles on agent-segment
   KL** [42] — our fleet is agent-heavy, so this needs an owner call, not a silent adoption.
5. hipBLASLt: "silence expected on gfx1201 at our stack" is **grounded** — auto-table use was
   gfx1151-only by owner ruling [22], the tag ships no `gfx1201-hipblaslt-100401` table [23],
   and our claim-compiled engine has no packaged `tuning/` dir at all [22][25].

## 0. Pin facts (binding, verified)

- v0.2.9 tag `d94bac6` → commit **`c62d5e3a15b40ea51c96aae9e8d36928965f53ab`**, released
  **2026-10-31T08:02Z** [1][2]. Release notes state verbatim: "The app is 0.2.9. Control and
  every engine package are **0.1.55**" [2]. Engine == the `src/` tree at that commit (our
  production engine is the claim-compiled build of exactly this tree — EXPLORE §1; engine
  component versions per release: 0.2.10=0.1.56, 0.2.11=0.1.57, 0.2.12=0.1.58,
  0.2.13=0.1.59 [35][36][37][38]).
- Repo-side shipped posture (binding envelope, owner-ruled twice on 2026-11-10): q4 arena
  `parallel: 4`, `--expert-cache auto`, `--prefill auto`, `--kv int8 --kv-resident 32768`,
  `--max-context 262144`, `--conversation-cache-mib 16384 ×16 slots`,
  `--memory-limit-mib 103680`, `backend: hip`, **`env: {}`** — all five rungs set
  `backend: hip` and four of five `parallel: 4` (ornith 1) [52].

## OQ-1 — the slot-pinning law under our build: RESOLVED, and it bites

**`parallel:` ≡ `--batch`.** The run-config key `parallel` is a validated integer override
(1..1024) in `strata_control/profiles.py` [13]; `serve/server.py engine_args()` calls
`parallel_args(cfg, args)` which returns **`["--batch", str(n)]`** when `parallel` ≥ 2 and the
args carry no explicit `--batch`/`--slots` [5]. Server-side cap `PARALLEL_MAX = 8`
(without `--batch-mtp` or a layer split the engine "runs at most 8 … and says so") [5].
The engine itself has **no `--parallel` flag** — only `--batch N` (also spelled `--slots N`)
[3][6]. The 0.2.9 release-notes sentence "with `--parallel` or `--batch` of 2 or more" is
notes-speak for the config key [2]. So our q4 `parallel: 4` ⇒ engine `--batch 4`, confirmed
[5][6][13][52]. (The Q2 "batch rejection" ruling in cf-77 DECISIONS was about not passing a
literal `--batch` argv element; the shipped `parallel: 4` key lands on the same engine path —
this closes EXPLORE §5's open mapping question.)

**The pinning law at engine 0.1.55 — holds, exactly as the guide states:**

- `src/program/generate.cpp` ~L6160–6225 **[V]**: at serve start, `if (o.batch > 0)` the
  engine creates **`o.batch` slot sessions**, each `session_bytes(g, o.max_context, …)` —
  sized for the **whole `--max-context`**, allocated **at start**, before the MTP drafter and
  expert cache are loaded. If a slot does not fit it warns and **degrades the count**
  ("`--batch %d: slot %d's session does not fit … %d slot(s)`"); if fewer than 2 fit it
  **turns batching off** ("`--batch is off: not two slot sessions fit (a smaller
  --max-context or KV streaming, --kv-resident, makes them smaller)`"). Final count is
  reported as `INFO batch_slots=N` [55] and exposed via `/v1/status` `concurrency.serving` [6].
- The guide's "(N slots **+ 1 main session**)" law: the main session is allocated the same
  full-`--max-context` way independently (the slot loop only creates the extra N) [4][29].
  Upstream states it verbatim in PR #1011: "With KV streaming (`--kv-resident`) **every
  session pins the whole context's K/V in RAM: the main session and each `--batch` slot**. At
  `--max-context 262144` that is 3.09 GiB per session, so **4 lanes pin 5 × 3.09 = 15.5
  GiB**" [44].
- With **`--kv int8 --kv-resident 32768`** (our q4 shape) the two-plane consequence at our pin
  [7][6]:
  - **VRAM per slot** shrinks to the resident-window session ("only the attention's 32K window
    stays in VRAM", docs measure 0.56 GiB/slot at 32K int8; our chart's own count ~0.4 GiB)
    [6][7][53]; the engine logs the VRAM cost line "`--batch N: the slot sessions take X GiB
    of VRAM on CUDA0 that the expert cache would otherwise hold`" [4].
  - **Host RAM per session** grows to the **whole max-context** in pinned RAM — engine help at
    the tag: "`--kv-resident N … keep N cells of each QSA layer in VRAM (min 20480) and the
    whole K/V in **pinned RAM**`" [7], and the startup line prints it ("`the K/V in %.2f GiB
    of pinned RAM`" at `generate.cpp:5969` [V]). So 4 slots + main ⇒ **5 × full-context
    pinned KV**, plus the arena and everything else.
- **Per-token KV math at the pin:** the help fixes the per-cell constants — int8 = **1,056
  B/cell per QSA layer**, k8v4 = **816** [7][8]; our chart's derivation of 13 KV-bearing
  layers × 1,056 = **13,728 B/token** → **3.35 GiB @ 262,144** [52][53] is the code-law figure.
  Upstream logs of the same law read **3.09 GiB** on 0.1.40–0.1.52-era engines [41][42][44],
  and BATCHING.md@tag rounds it to "1.6 GB at 128K" [6]. The 3.09 vs 3.35 gap (~8%) is not
  resolvable from static sources (build-era or per-state rounding); the plan should treat
  **3.1–3.35 GiB/slot@262K int8** as the band and **read the engine's own pinned-RAM line at
  our startup** as truth (user action, U1).

**Answer to the ask as posed** ("does N slots + 1 main session pin for the whole max-context
at start, at engine 0.1.55?"): **Yes** [4][6][7][44]. The guide's slot math is structurally
correct at our pin; only its byte-constant sits slightly below our code-derived value.

## OQ-2 — flag surface at 0.2.9 / engine 0.1.55

Engine flags were extracted from `src/program/generate.cpp` at the commit (the flag list is
the union of parsed `--flags` there and env strings across `src/`) [3]. Launcher/config keys
from `strata_control/profiles.py` + `serve/server.py` [5][13][14][15][16][27]. Table: **flag →
present at pin? → default → semantics at our pin → source.**

| # | Flag / knob | Present | Default at 0.2.9 | Semantics at our pin | Src |
|---|---|---|---|---|---|
| 1 | `--expert-cache N` | ✅ | unset/`auto` → sized from VRAM free after reserve + draft head | Sizes the **VRAM** expert cache. At 0.2.9 the batch slot sessions are carved **before** auto sizing (code order L6160 slots → L6955 auto), so auto already "sees" the slots on this source — unlike the 0.2.0-beta shape #3364 reported (cache first, slots fail, exit 1; **still OPEN** upstream [39]). APU/Strix gets an extra warning-only guard. Small-card rescue may lower the reserve. Explicit N: fill can overshoot (#3693, closed only by **housekeeping sweep**, no fix recorded — assume live at 0.1.55 [40]). Read the startup lines back, always. | [17][39][40] |
| 2 | `--vram-reserve-mib` | ✅ **(answers EXPLORE's unknown)** | **700** MiB; engine default | Keep N MiB VRAM free after the cache; passing it sets `vram_reserve_given` → disables the auto-shrink rescue. Guide's 2048 is a supported value. (vision-config path also writes 700) | [18][5] |
| 3 | `--prefill N` / `auto[:N]` | ✅ | unset → chunk 0; `auto` → 8192 ceiling here; **`auto:16384`/`auto:32768` accepted** (clamped to {8192,16384,32768}); `STRATA_PREFILL_AUTO_MAX` equivalent; bare-auto 6144 only on Windows-HIP | Prompt chunk size; `--prefill 32768` (guide form) and `--prefill auto:32768` (our shipped T3 form) both parse at the pin. The gfx12 *bare-auto* ceiling raise to 32768 is a 0.2.11 default — post-pin; at 0.2.9 pass it explicitly. | [19][36] |
| 4 | `--kv fp16\|int8\|q4_0\|k8v4` | ✅ all four | fp16 | int8 = 1,056 B/cell/layer [M-doc]; q4_0 = Hadamard-rotated 4-bit, "half of int8's memory" (PR #21 merged **2026-09-27**, well inside our build); k8v4 = INT8 K + Q4_0 V = 816 B/cell and the help at our tag says it **"streams with --kv-resident too"** — the #1188 degeneration (fixed pre-10-07) is resolved at our pin [41]. `q4` aliases to `q4_0`. | [3][7][8][41][42][43] |
| 5 | `--kv-resident N` | ✅ | 0 (all KV in VRAM) | KV streaming: N cells/layer in VRAM (**min 20480**, requests below clamp up), **whole K/V in pinned host RAM**; ctx ≤ N not streamed. Startup prints its GiB. | [7] |
| 6 | `--ple-io ram\|direct\|mmap` | ✅ all three values | not given → **direct**, then auto-RAM policy may promote to mlocked RAM ("`--ple-io ram chosen by the residency policy`") only when table + expert-arena fill + **8 GiB headroom** fit `available_host_bytes()` **cgroup- and `--memory-limit-mib`-aware**; `STRATA_PLE_AUTO_RAM=0` pins direct, `STRATA_PLE_AUTO_MMAP` fallback tier. Explicit `ram` **overrides the policy's own protection** — the negative-pinned hazard our 2026-10-29 OOM proved. | [26] |
| 7 | `--mtp PATH` `--spec N` `--spec-min-p P` | ✅ | spec off without --mtp | Native draft layer; DETAILS@tag: draft layer "**~0.7-1 GiB** of VRAM"; without it "drafts then come from the suffix and prompt-lookup drafter only". Our profiles already pass `--mtp … --spec 4 --spec-min-p 0.5`. | [30] |
| 8 | `--batch-mtp` / `STRATA_BATCH_MTP=1` | ✅ | **off** (opt-in) | Each batch slot verifies one MTP proposal per window; **runs on a single GPU** (needs `--mtp`+`--spec`; per-slot drafters logged "`--batch-mtp: N slot drafters on CUDAk (X MiB each)`", their K/V ring also keeps a pinned-RAM copy). Upstream's own R9700-adjacent evidence: single-GPU +31..39% owner runs "a RX R9700 run too"; 2×R9700 layer-split all-in-VRAM −21.9% (not our topology). "it pays only when the experts do not all fit in VRAM". A slot left alone reverts to the solo path **with** drafts. | [6] |
| 9 | `--resident-experts` | ✅ **present**, and *reachable* in the sense that it parses at our tag — but it **opts OUT of the arena**: sets `mmap_experts = resident_cpu_experts = resident_pin = resident_soft = true`, headroom 4 GiB (`STRATA_RESIDENT_PIN=0` / `STRATA_RESIDENT_HEADROOM_GIB=N` A/B switches). All measurements at the tag are CUDA (2×RTX 5090, 2×5090 split); **#3734** (AMD ~2× expert RAM duplication) closed by **format housekeeping, not a fix** [49]; **#5020** — filed **against engine 0.1.55 itself** — open: arena keeps all 24,576 experts in host RAM *on top of* the VRAM cache, documented escape = `--mmap-experts` modes [48]. Verdict: present but unproven on gfx1201, AMD-hazard live at our pin → **not a plan lever** (matches guide's own caution). | [21][48][49][6] |
| 10 | `--mtp-window N` | ✅ | **32768** (0 = every cell) | Draft layer attends to last N cells. Strix profile's `--mtp-window 8192` is valid at 0.2.9; the +3.5%-at-64K measurement is Strix/main-doc, fine to re-derive. | [33] |
| 11 | `--lookup-chain N` / `--lookup-chain-min M` | ✅ | **0 (off)** / min 3; clamped 0..7 | Prompt-lookup suffix drafts; with `--spec ≥ 2` it *extends the verify window* (spec grows up to 8 rows). No R9700 measurement upstream → [I]. | [33] |
| 12 | route-tail skip / `STRATA_ROUTE_TAIL_SKIP` | ✅ | default rank **7** on CUDA **since 0.1.42**, and DETAILS.md **@v0.2.9** documents the same for "**CUDA, and HIP gfx1200/gfx1201**"; env-unset default path requires: `--batch == 0` (solo), not all-resident, <90% experts cached (60% on HIP split), no peer. **Not applied with `--batch` slots** even when the env is set explicitly (docs@tag) | So the card's "arrived in 0.2.11" is **wrong at engine level** — the 0.2.11 change was *setup/launcher no longer writing `STRATA_ROUTE_TAIL_SKIP=0` for Unsloth files on gfx12* [36]; the engine default at our pin already covers gfx1201 [9][10][11][12]. Consequence for us: on our **batched** q4/orca/primary rungs the skip is OFF at 0.2.9 (batch gate) — same as it is post-pin; on the **solo ornith rung** it is ON by default at the pin. | [9][10][11][12][36] |
| 13 | hipBLASLt tables / `STRATA_HIPBLASLT_TUNING` / `STRATA_HIPBLASLT_TABLE` | ✅ both envs (and `"hipblaslt_table"` config key) | auto (`TABLE` unset) uses the **packaged** table on **gfx1151 only** — `AUTO_USES_TABLE=False`, `AUTO_ARCHS=("gfx1151",)`, owner ruling 2026-10-19 ("on gfx1201 the gain was ~1% and decode lost ~2%"); `TUNING=<file>` "always wins"; engine accepts a table only if arch **and** hipBLASLt version match (`gemm.cu`), log line verbatim: "`prefill gemm: hipBLASLt tuning enabled (N rows, <arch>, version N)`" | See OQ-6 for the gfx1201-at-our-pin adjudication. | [22][24][25] |
| 14 | `--max-context N` | ✅ | model-native | Sizes every session at start (the 1:1 trade knob the guide describes; no per-slot context option exists at the tag — checked, none) [3][4]. | [3][4][44] |
| 15 | `--no-prefill-borrow` / `STRATA_PREFILL_BORROW` | ✅ | borrow ON (prompt reads borrow expert-cache slots) | Turning borrow off reserves 128 slots for the prompt path instead; interacts with `--prefill` chunk sizing (`pf_mib` term). | [3][17] |
| 16 | `STRATA_PREFILL_CPU_SHARE` | ✅ | **not armed by default** (memory verdict gates; engine prints why unless env set); `auto` = measured share; numeric 0..1 | An explicit value is *kept with a warning* on memory-tight hosts. Our chart already ships `=auto` [52]. | [20] |
| 17 | `STRATA_ENGINE_NICE` | ✅ **(launcher-side, serve/server.py, Linux only)** | +5 **only when a visible arch is an iGPU (HIP_IGPU_ARCHS, e.g. gfx1151)**, else 0; `=0` off, `=N` set | R9700-only arenas get nice 0 by default at our pin — the guide's `STRATA_ENGINE_NICE=0` step is a **no-op for our flash-next rungs**; it matters for the strix arena (gfx1151 visible ⇒ +5) if we ever want the CPU pool unsandbagged there. | [16] |
| 18 | `--conversation-cache-mib / -slots / -min-free-mib / -min-tokens / -park-gain` | ✅ | `-mib`: **sized from free RAM, up to 8192, on the serve path** (#3493); 0 = off. `-slots`: **4**. | So the guide's "conversation cache is opt-in, leave it at 0" is **wrong at our pin** — it auto-sizes unless told; our shipped 16384×16 is a deliberate doubling above the auto default [52]; the parked conversations consume the same host RAM the KV law counts (#5020's smaps showed 2.99 GiB of parked-conversation `/dev/zero`) [48]. | [27][48] |
| 19 | `--memory-limit-mib` | ✅ | unset | Help@tag: "the total RAM (MiB) this engine's **container or cgroup** may use" — cgroup-aware; feeds the arena/PLE/auto-cache RAM budget math. | [28][26] |
| 20 | `--kv-grow` / `--no-kv-grow`, `STRATA_KV_GROW_*` | ✅ | off | Elastic KV: VRAM only for reached cells, expert cache holds the rest; **requires whole-KV-in-VRAM → mutually exclusive with `--kv-resident` streaming** [6][7]. **Correction to EXPLORE gotcha 5:** `STRATA_KV_GROW_HOLD` is **not** phantom at our pin — it exists (`generate.cpp:14636`: opt-in "keep the K/V as long as the longest parked conversation; default: trim to this request alone, as 0.1.40"). | [6][7][V-14636] |
| 21 | `--kv-pool-tokens` (shared pinned KV pool) | ❌ **absent** | — | PR #1011 closed **unmerged** (2026-10-06) [44]; follow-up **PR #1614 is OPEN, not closed** (guide says "appears closed too" — refuted [45]); string exists nowhere in the v0.2.9 tree [34]. Guide's "not available" verdict: **holds**, with the citation fixed. | [34][44][45] |
| 22 | `--resident-budget-gib` / `--resident-cpu-experts` / `--mmap-experts` | ✅ | arena on (none set) | The low-RAM tier; `--resident-budget-gib` implies mmap (every expert above budget reads SSD per token) — guide's "do not use" holds [V][6]. | [21][6] |
| 23 | `--draft dflash2` / DFlash2 | present-but-moot | never chosen by us | `src/core/dflash2.cpp` + `--draft` exist at 0.2.9, but the launcher "drafting auto" concept arrives **0.2.10**; our profiles pass `--mtp` explicitly, and the entire DFlash2 stall story (11/50 on 0.2.11, gfx1201 Auto→MTP at 0.2.12) is **post-pin and moot for us** [35][37][52]. | [3][35][37] |
| 24 | bench suites `standard-v1`, `parallel-mixed-v1` | ✅ | `standard-v1` default | `strata bench run --suite` choices@tag: `standard-v1`, `serving-smoke`, `parallel-mixed-v1`, `parallel-overload-v1`, `parallel-cancel-v1`, `parallel-prefill-cancel-v1`; `parallel-mixed-v1` = warmup+serial+mixed+mixed phases [31]. EXPLORE's "existence UNVERIFIED on our pin" — **verified: both guide names exist at 0.2.9**. | [31] |
| 25 | `STRATA_MMQ_KQ` (K-quant prompt kernels) | ✅ | **off at 0.2.9** (`on = getenv("STRATA_MMQ_KQ")[0]=='1'`) | 0.2.11 flips it to default-**on** for gfx12 with R9700 numbers **4K +10.3%, 8K +14.3%, 32K +16.8%** (first-token KL 0.031, agent 0.065, top-1 23/24) [36]. At our pin it is an **opt-in env lever** for the arena — see Implications L2. | [32][36] |
| 26 | `STRATA_ARENA_FILE_CACHE`, `--ram-keep-gib` | ❌ | — | Re-confirmed absent at 0.2.9 (grep over src/serve/strata_control) — matches the bump-eval doc's finding [34]. | [34] |
| 27 | gfx12 platform defaults already live at our pin | — | — | 0.2.9 itself made: chunked GDN scan active on all-gfx12 Linux at ≥64 tokens (release notes "prompts 2-6% faster … by default"; launcher also writes `STRATA_GDN_CHUNKED=1` for all-gfx12 visible cards, Linux-only); `STRATA_HIP_WMMA` + `STRATA_PF_FUSED` default-on for Linux gfx12 (`gfx12_platform_defaults.hpp`: `gfx12_prompt_defaults_on(windows) = !windows`) | [2][15][V-hdr] |
| — | 9-var parallel stack | ✅ exists, **never on for HIP** | off for `backend: hip` | see Implications L1 [14] | |

## OQ-5 — `--kv q4_0` at our pin: RESOLVED (present; quality picture mixed, agent-heavy caveat)

- **Existence:** hard yes. Engine accepts `fp16|int8|q4_0|k8v4` (alias `q4`→`q4_0`)
  [3][8]; the runtime wires `qsa_set_kv_q4` citing **PR #21** inline [8]; PR #21 was **merged
  2026-09-27** — before the engine that became 0.1.55 [43]. The Hadamard (FWHT-256) design
  claims attention-score invariance and "fully compatible with speculative verification,
  MTP, and QSA decode streaming" [43]; parity tests shipped (`kv_q4_parity.cpp`,
  `kv_window_parity.cpp` built for "q4_0 KV + KV streaming + MTP") [3][8].
- **Memory:** half of int8 → our code-law ~1.72 GiB @262144; upstream measured "3.09 → **1.69
  GiB**, frees 1.4 GiB pinned RAM at 256k, no meaningful speed change" on engine ~0.1.52-era
  [M #4159] [42][44]. At `parallel: 4` the whole-arena saving is ≈ **(5 sessions × ~1.4–1.7
  GiB) ≈ 7–8 GiB** of host RAM — the cheapest slot-pressure reliever, consistent with the
  guide and the repo's rungs research [53].
- **Quality, grounded at sources readable now:** #4159 (MI50, IQ3_S pack, 2K prefix through
  the batched path): vs FP16-KV reference — int8 KL 0.055 / top-1 94.9% / PPL 2.762; **q4_0
  KL 0.130 / top-1 91.7% / PPL 2.793**; **agent segment KL: 0.090 (int8) → 0.200 (q4_0)**
  [42]. #1188's spot probes showed q4_0 output byte-identical to int8 on short factual runs
  [41]. The guide's "+8-12% perplexity on long docs, PR #21" is **not in PR #21's merged body**
  (which claims perplexity *preserved*); treat it as [I]-grade upper bound, with #4159's
  measured +1.1% PPL / ~2× agent-segment KL as the [M] reality. **Decision relevance:** our
  consumer is the agent fleet — an agent-heavy workload is exactly the segment that degrades
  most; q4_0 must be a measured arm against our tasks, not a silent adoption.

## OQ-6 — hipBLASLt on gfx1201 at our pin: "silence expected" CONFIRMED (three independent layers)

1. **Policy:** at v0.2.9 `strata_control/hipblaslt_tuning.py` ships `AUTO_USES_TABLE = False`
   and `AUTO_ARCHS = ("gfx1151",)` — an owner ruling dated **2026-10-19**: gfx1201 table gain
   was ~1% with decode −2%, so auto stays off there [22]. AMD_HIP.md@tag documents the same
   switch semantics (`STRATA_HIPBLASLT_TABLE=on` to opt in, `TUNING=<file>` always wins) [25].
2. **Packaging:** auto-selection only ever reads a **packaged engine**'s `tuning/` dir +
   `BUILD.json hipblaslt_version`; our production engine is the claim-compiled checkout build
   (`/models/strata/Strata/engine/strata`) with no package beside it — `resolve()` returns
   "package without tables: nothing to say" [22][25][52].
3. **Table availability:** the tag's `tools/hip/` ships gfx1201 tables only for hipBLASLt
   **1.2.2 (100202)** and **1.5.0 (100500)**; none for the 100401 class our image's
   gfx120X-all venv carries (README ladder rung 2) — and the engine hard-checks arch+version
   (`gemm.cu`, exact startup line "prefill gemm: hipBLASLt tuning enabled (N rows, …, version
   …)") and otherwise uses plain hipBLAS, "a wrong table can never change a result, it only
   wastes the speed-up" [22][23][24].
   Post-pin only strengthens this: 0.2.10–0.2.12 engines overrode the gfx1151-only auto rule,
   and 0.2.13 restored "off by default on Windows gfx1201" [35][38]; even at 0.2.13 the
   launcher-written default list says "the **gfx1151** hipBLASLt table" [38].
   ⇒ The guide's `STRATA_HIPBLASLT_TUNING` step is a **no-op at our posture** unless someone
   (a) runs `tools/hip/tune_hipblaslt.cpp` to *generate* a 100401-class gfx1201 table for our
   venv and (b) accepts the ~1% gain / −2% decode upstream measured (not worth an arm now).
   OQ-6 closes: silence is the grounded expectation; remaining verification is the one-line
   startup-log grep in U1.

## Guide memory-budget inputs — adjudicated at the pin

| Guide input | Tag verdict |
|---|---|
| UD-Q4_K_XL experts **71.7 GiB** (24,576 = 48×512, 2.99 MiB/expert) | holds — #5020's smaps on **engine 0.1.55** shows the arena anon region at exactly **71.732 GiB = 24,576 blobs** [48] |
| PLE table 26.8 GiB (IQ4_NL 28.8 GB) | holds [R UNSLOTH_Q4; #5020's mmap line 5.685 GiB is a different table path, not a contradiction of size] |
| int8 pinned KV **3.09** GiB/slot@262144 [M #1011/#1188] | law holds; constant: code@tag ⇒ **3.35** (13×1,056 B/cell); 3.09 measured on 0.1.40/0.1.52-era [M]; band 3.1–3.35, read our own line (U1) [6][7][41][42][44][53] |
| k8v4 2.39 → code-law 2.59; q4_0 1.69 → code-law ~1.72 | same regime note [7][42] |
| "(N+1) sessions pinned at start, 1:1 max-context↔slots trade; no per-slot context knob" | **holds verbatim** at 0.2.9; checked: no per-slot context exists [4][7][44] |
| `--kv-pool-tokens` unavailable | holds (absent; #1011 unmerged; **#1614 is open**, guide's "appears closed" wrong) [34][44][45] |
| MTP draft ≈ **0.8 GiB** (835 MiB [M #2126]) | holds at tag: DETAILS.md@v0.2.9 "**~0.7-1 GiB** of VRAM"; 835 MiB is the CUDA log inside #2126; batch-mtp slot drafters log separately ("X MiB each", ring pinned-RAM copy too) [30][47][6] |
| VRAM/slot with `--kv-resident 32768` ≈ 0.56 GiB (BATCHING [M]) / card log 0.95 (#4167) | BATCHING.md@tag carries the 0.56 GiB-at-32K-int8 figure and the 11-24% solo-cost on 12 GB cards; "read your own line" discipline is exactly what our pin's log offers [6] |
| `--vram-reserve-mib` 2048 vs "700 default stalled" | default **700 confirmed in code**; 2048 supported [18] |
| OS + headroom ≥8 GiB / Strix UMA headroom 6 GiB; "RAM − 20-24 GB" budgeting rule | our shipped analogue: `--memory-limit-mib 103680` inside a **110Gi cgroup** on a 125.08 GiB node [52][28]; PLE auto-RAM policy additionally demands 8 GiB headroom over table+arena before it ever locks the table [26] |

## What 0.2.10 → 0.2.13 changed that MATTERS to the guide

(For the plan's "which guide claims are post-pin" cut. Engine versions: 0.2.10=0.1.56,
0.2.11=0.1.57, 0.2.12=0.1.58, 0.2.13=0.1.59 [35][36][37][38].)

- **0.2.10**: launcher "drafting: auto" introduced — **DFlash2 default drafter** on CUDA
  8.6/8.9/12.x and **gfx1100/gfx1151/gfx1201** (Auto picks MTP instead when `--parallel`/
  `--batch` ≥ 2) — so the guide's whole DFlash2 stall arc only *begins* post-pin; at 0.2.9 no
  auto-drafter machinery touches us and our profiles pin MTP explicitly [35][52]. Also:
  vram-reserve cap 1536 MiB on ≤16 GB cards (#3750), arena-lock fix #4846.
- **0.2.11** (engine 0.1.57): Unsloth **v3.1** catalog (7 files) — repo's engine-gate ≥0.1.57
  note confirmed; **gfx12 defaults batch**: K-quant prompt kernels ON (`STRATA_MMQ_KQ` opt-out),
  bare-`auto` prefill ceiling 16384→**32768**, prompt staging ring 96→256/192, **route-tail
  skip stays on for Unsloth files on gfx1200/1201 — the change is that setup stopped writing
  `STRATA_ROUTE_TAIL_SKIP=0`**, the engine default itself predates our pin [12][36]; UD
  hot-set profile tested +0.6%, default unchanged; R9700 solo route-tail +6.18% measured
  [M]; MTP-vs-DFlash2-per-user matrix (NVIDIA, the guide's 8-user MTP loss) [36]; chunk-size
  answer-sensitivity story (agent prompts flip on near-ties — a caution for any prefill-chunk
  A/B!) [36].
- **0.2.12**: **gfx1201 Auto → MTP** (because 11/50 DFlash2 engines stalled on prompts at
  0.2.11; hand-chosen DFlash2 still stalls — "known problems") [37]; R9700 32K prompts
  +8.6-11.6%.
- **0.2.13**: "Settings the launcher used to write are **now the engine's own defaults**:
  the parallel stack on **Linux CUDA** with 2+ slots, GDN settings on Linux CUDA, **chunked
  GDN scan on Linux with all cards gfx12**, the **gfx1151** hipBLASLt table, …" — note two
  things the plan must not gloss: (a) it is still CUDA-scoped for the parallel stack —
  **HIP never gets it, even here** [38][14]; (b) our 0.2.9 launcher already writes the GDN
  chunked setting for all-gfx12 Linux, matching the engine-side default the 0.2.9 notes
  claim [2][15]. Also: Windows-only hipBLASLt-table re-restriction (gfx1201/gfx1100 off by
  default, "restores the 10-19 rule"), new DFlash2 per-card defaults, #5327 arena-file-cache
  fix (still post-pin for us).

## Guide-claim adjudication table (tuning-relevant claims → holds / post-pin / refuted at 0.2.9)

| Guide claim (card) | Verdict at our pin | Basis |
|---|---|---|
| R9700-only visibility via `ROCR_VISIBLE_DEVICES` | **holds** (shipped) | [52] |
| `parallel:`/`--batch` pins N+1 full-max-context sessions at start | **holds** | [4][6][7][44] |
| "start 4 slots × 128K, then 8 × 256K" posture | **post-pin ambition** — owner envelope is 4 × 262144 in a 110Gi cgroup; any slot×context re-shape is owner-gated (cf-141 OQ3, EXPLORE §6) | [52] |
| `--expert-cache auto` untrustworthy under batch (#3364); explicit N not a cap (#3693); read startup lines back | **holds in practice** — #3364 open (its exit-1 ordering predates the tag's slots-before-cache order, partial mitigation at 0.1.55); #3693 closed by housekeeping only | [17][39][40] |
| `--vram-reserve-mib 2048` | **holds** (flag exists, default 700) — resolves EXPLORE §6 "unknown at 0.2.9" | [18] |
| `--ple-io ram` as default-table posture | **refuted as advice for our box**: flag exists, but auto-policy is cgroup-aware and `--ple-io ram` bypasses exactly that protection (our 2026-10-29 OOM law); keep it unpinned | [26][52] |
| `--resident-experts` to reach 8 × 256K | **present; unproven + hazardous at pin** — forces mmap mode, CUDA-only evidence, #3734 unfixed, #5020 filed at 0.1.55 | [21][48][49] |
| `--kv q4_0` fallback saves ~half pinned KV | **holds** (present, merged pre-pin); quality numbers: guide's "+8-12% PPL" **unsupported** at cited sources; measured PPL +1.1%, agent-KL ×2.2 | [8][42][43] |
| "avoid `--kv k8v4` with `--kv-resident`" (repetition bug) | **refuted at our pin** — fixed pre-10-07; help@tag: "streams with --kv-resident too"; no fresh HIP confirmation → [E] | [7][41] |
| "conversation cache opt-in, leave at 0" | **refuted at our pin** — auto-sizes ≤8192 on serve path; we deliberately ship 16384 | [27][52] |
| MTP + `--spec 4 --spec-min-p 0.5`; solo-with-drafts / batch-without unless `--batch-mtp`; slot left alone returns to solo path with drafts; batch-mtp A/B at 2-4 concurrent | **holds** (all documented/implemented at tag; R9700 single-GPU evidence thin but "a RX R9700 run too") | [6] |
| "never DFlash2 on gfx1201 (11/50 stalls)" | **post-pin story, moot** — 0.2.9 launcher has no drafting-auto; our profiles pin MTP explicitly. Advice safe regardless | [35][37][52] |
| "Auto has picked MTP on R9700 since 0.2.12" | **post-pin** — no auto-drafter at 0.2.9; irrelevant for explicit-`--mtp` profiles | [37] |
| "route-tail skip default 7 … on for UD files on gfx1200/1201 **since 0.2.11**; not applied with batch slots" | **mixed**: engine default-on at gfx1200/1201 **exists at our pin** (DETAILS@tag; default since 0.1.42 CUDA / gfx12 HIP); 0.2.11 only changed **setup's config** for UD files; "not applied with batch" **holds at tag** → our batched rungs never see it either way | [9][10][12][36] |
| hipBLASLt tuning tables on gfx1201 | **holds as no-op for us** — gfx1151-only auto rule at tag, no 100401-class gfx1201 table shipped, unpackaged engine path never auto-resolves (OQ-6) | [22][23][24][25] |
| "`--batch N` = guide's `--batch` (N slots + 1)" naming for us | **holds via `parallel:`** — server maps it; `PARALLEL_MAX=8`; explicit `--batch` in args wins and conflicts with overrides | [5][6][13] |
| `STRATA_ENGINE_NICE=0` | **holds as no-op on R9700-only rungs** (default nice 0 there at pin), **live only on the strix arena** (gfx1151 ⇒ +5) | [16] |
| `STRATA_PREFILL_CPU_SHARE=auto` "helps only without --batch" | engine env + auto semantics **hold at pin**; the batch-caveat is PR #3636's measured observation — keep as [M-external], untestable from source | [20][51] |
| Bench suite names (`standard-v1`, `parallel-mixed-v1`) | **hold at pin** (verified in cli choices) — resolves EXPLORE §5's UNVERIFIED note | [31] |
| "Strata changed defaults in every release 0.2.9→0.2.13; verify every flag against the installed build" | **confirmed emphatically** — that is precisely what this round did; the per-flag table above IS the installed-build answer until U1 supersedes it | [2][35][36][37][38] |
| IQ3_S 8 × 256K scenario H math | out of envelope scope — our flagship *is* IQ3_S-class (primary runs ISTA IQ3_S) but at `parallel: 4` under owner rulings; H's 8-slot math is [E] and owner-gated | [52] |

## Implications for the plan (adaptable TODAY, no bump, no owner-ruling re-litigation)

Ranked by expected value on the *shipped* 4-slot/110Gi posture:

- **L1 — the parallel stack, manually, as a measured arm.** The 9 bit-qualified env vars
  (`STRATA_CKPT_POOL=1, STRATA_CKPT_POOL_READY=4, STRATA_SLOT_CKPT_MOVE=1,
  STRATA_SLOT_COPY_DIRECT=1, STRATA_SLOT_COPY_BATCHSYNC=1, STRATA_BATCH_GDN_GROUPS=1,
  STRATA_BATCH_ATTN_ROWS=1, STRATA_BATCH_SELF_COMMIT=1, STRATA_QSA_SLOTS=1`) are exactly what
  the 0.2.9 release's "parallel requests 1.45× at c=8" headline is built from — and the 0.2.9
  launcher **refuses them to `backend: hip`** ("HIP got no measurement without replicas")
  [14][2]. All five of our rungs set `backend: hip` with `env: {}`, so **our batch slots run
  without this stack at 0.2.9 and would still not have it at 0.2.13** [14][38][52]. The
  profile env is a pure values edit (chart-side, list-merge gotcha respected). Risk: upstream
  qualified CUDA-only → run as a benchmark arm with the guide's §10.6 stop criteria + our
  Grafana/Loki method, and the batch path degrades safely if any switch misbehaves.
  **This is the single most promising at-pin parallel-performance lever found.**
- **L2 — `STRATA_MMQ_KQ=1` arm** (K-quant prompt kernels): on by default upstream since 0.2.11
  for gfx12 with R9700 +10.3/14.3/16.8% prompt numbers; present but opt-in at our pin
  [32][36]. Quality caveat that the release notes themselves flag: chunk-size/rounding changes
  flip near-tie agent answers (first-token KL 0.031/agent 0.065) — measure against our fleet's
  agent traffic shape before adopting [36].
- **L3 — batch-MTP A/B** (`--batch-mtp` in args or `STRATA_BATCH_MTP=1` env): fully supported
  at pin on a single GPU with our exact `--mtp/--spec` shape; guide's advice (A/B at 2-4,
  expect flat-to-negative at 6-8, read the "X MiB each" drafter line and the resulting
  expert-cache shrink) is implementable as-is [6][8-line-help]. One q4-specific interaction:
  slot drafters further shrink the cache the slots already took — keep `--expert-cache auto`
  per arm or set explicit N, and read `batch_slots` + `expert cache auto` back [4][17].
- **L4 — `--kv q4_0` deep-context relief** (OQ-5): −7–8 GiB pinned host KV at 4 slots
  [M-class]; the honest trade is agent-segment KL ≈ ×2.2 [M #4159] on our most-heavy segment —
  propose as a **plan question** (owner decides), or a per-rung arm (e.g. ornith/strix
  deep-park rungs) rather than fleet-wide default. Do NOT pair it with k8v4 avoidance advice
  from the guide (refuted at pin).
- **L5 — `--vram-reserve-mib 2048`** (or ≥1 GiB floor per PR #3636's stall story) as a batch
  arm; at the pin it disables the small-card auto-shrink (`vram_reserve_given`) — which is
  fine for us (32 GB card) [18].
- **L6 — discipline layer (cheap, adopt verbatim):** read-back of `INFO batch_slots`,
  "expert cache auto: … -> N slots", "the slot sessions take X GiB", "the K/V in X GiB of
  pinned RAM", drafter lines; `/v1/status concurrency.serving`; stop criteria §10.6 — all
  exist at our pin exactly as the guide assumes [4][6][7][55].
- **L7 — bench protocol localisation:** suite names verified at pin [31]; run in-pod via the
  README ladder's user-exec form (no agent pod exec); `parallel-mixed-v1` + custom depth
  sweep via `/v1/chat/completions` as the guide describes [31][51].
- **Explicitly NOT levers at this pin:** `--resident-experts` (unproven AMD + open duplication
  bugs) [21][48][49]; shared KV pool (`absent`) [34]; DFlash2/Auto drafting (post-pin machinery,
  moot) [35][37]; `--ple-io ram` pinning (hazard law) [26][52]; hipBLASLt table step (no-op)
  (OQ-6); any slot×context re-shape past the owner envelope (OQ-3, owner-gated);
  `concurrencyLimit`-style re-limits (owner ruling 2026-11-10 stands) [52].

## Contradictions and how to weigh them

1. **3.09 vs 3.35 GiB/slot@262K int8**: both are "[M]" — 0.1.40/0.1.52-era logs vs the code
   arithmetic at 0.2.9 (13 layers × 1,056 B). Weight: code-law for planning budgets (it's our
   build), startup line for truth (U1). Do not "fix" either doc to the other.
2. **route-tail-skip "since 0.2.11" (card) vs default-on at 0.2.9 (this round)**: settled by
   DETAILS.md@tag + the 0.2.11 note's own wording — the card conflated a setup-behavior change
   with the engine default. The practical effect is unchanged for our **batched** rungs (skip
   off either way) [12][36].
3. **#3364 open vs code showing slots-before-cache at the tag**: the issue's exit-1 signature
   was a 0.2.0-beta ordering; the tag's ordering narrows it to "auto gives the cache what's
   left after slots" — but "batch degrades to fewer slots" remains exactly what the tag's
   degrade-and-report path does, so the guide's read-back rule survives with changed
   mechanism. Weight the code (it's checkable) over the tracker (it's stale-ish).
4. **PR #1614 "appears closed" (card) vs open (API)** — refuted, minor [45].
5. **#3693/#3734 "closed" (tracker) vs closed-by-housekeeping (comments)** — both remain live
   hazards; this is why tracker state alone was not trusted [40][49].

## Adjacent (out of core scope, for the docs round per EXPLORE gotcha 4)

- `STRATA_KV_GROW_HOLD` **does exist** at 0.2.9 (`generate.cpp:14636`, opt-in elastic-KV
  hold) — EXPLORE gotcha 5's "VOID/doesn't exist" needs correcting before it hardens into a
  plan assumption (it only said the guide misuses it; the *existence* claim is wrong).
- Runbook §4 "no `--batch`" phrasing vs `parallel: 4` — this round settles the semantics:
  same thing, spelled through `parallel_args` [5].
- EXPLORE §6 "--vram-reserve-mib … unknown at 0.2.9" → **known now**: exists, default 700 [18].

## Open questions left (for coord batch / owner / user actions — NOT asked this session)

- **U1 (user action, pre-adoption gate)**: capture once in-pod: `strata --version`, engine
  `--help` grep for the table flags, and the full startup log block for the q4 arena
  (`batch_slots`, `expert cache auto: … -> N slots`, `the slot sessions take … GiB`, `the K/V
  in … GiB of pinned RAM`, `hipBLASLt tuning` line, `--ple-io`/residency line) — settles the
  3.09-vs-3.35 constant and the table silence against the *installed* build (commands already
  written: runbook §3.4/§3.5, README ladder rungs 1-4).
- **U2 (owner question)**: adopt L1 (HIP-unqualified parallel-stack arm) and L2 (`STRATA_MMQ_KQ`)
  as benchmark arms on the shipped 4-slot envelope? Both are env/args values edits inside the
  existing rulings; L4 (q4_0 KV) is a quality trade for the fleet and deserves its own owner
  answer.
- **U3 (research gap, low priority)**: exact hipBLASLt version string in our image's venv
  (100401-class per README rung 2 — [R], not re-measured here); a table *generation* run
  (`tools/hip/tune_hipblaslt.cpp`) would be the only way the guide's §7.4 ever applies here.
- Not answerable from source at all: on-our-box decode/TTFT deltas for L1-L5 — by design,
  that's the plan's benchmark, not research's.

## Reliability notes (peer-review pass)

Strongest findings: OQ-1 mapping + pinning law, the OQ-2 flag table, L1/L2 (multiple
independent primary sources at the exact commit). Weakest claim: **L1's transferability to
HIP** — upstream excluded HIP because it was never measured alone; my grounding is the code
gate + release-notes numbers (CUDA hardware). Confidence 6/10 that the stack is a net win on
gfx1201; it is proposed as an arm, not an adoption. Second-weakest: the 3.35 GiB constant
(layer-count read of the chart comment + code formula; 3.09 is log-measured elsewhere) —
band-bounded, U1 settles it. Perspective bias: heavy weight on source@tag over issue-tracker
state (deliberate — tracker hygiene was demonstrably noisy [40][49]); a missed angle: replica
mode (`serve/replicas.py`) as an alternative parallelism surface — out of scope for the
110Gi single-pod envelope but a legitimate 6th lens if L1 disappoints.

## Sources

(All fetched/read 2026-11-10 this session; repo paths relative to worktree root.)

1. GitHub API `repos/Niko1221/Strata/git/ref/tags/v0.2.9` → tag obj `d94bac6` → commit `c62d5e3a15b40ea51c96aae9e8d36928965f53ab`. [V]
2. GitHub API `releases/tags/v0.2.9` — title/body; "Control and every engine package are 0.1.55"; published 2026-10-31T08:02:32Z; "nine qualified settings" line; gfx12 chunked-kernel ≥64-token default line. [V]
3. v0.2.9 tree (tarball @commit, local): full `--flag` enumeration from `src/program/generate.cpp` + all `STRATA_*` env strings from `src/`. [V]
4. `src/program/generate.cpp` @v0.2.9, L6160–6225 (slot sessions at start, degrade/fit warnings, "slot sessions take … GiB of VRAM … the expert cache would otherwise hold"), L6225-6260 (STRATA_PIPED_MTP gating text). [V]
5. `serve/server.py` @v0.2.9: `engine_args()` L3245-3295, `parallel_args` L3303-3326 (`PARALLEL_MAX=8`), `--parallel` server flag L8990/L9104-9106, `parallel_slots` L3684. [V]
6. `docs/BATCHING.md` @v0.2.9: L1-31 (parallel=--batch=--slots; batch-mtp single-GPU opt-in; "(a RX R9700 run too)"; cannot-run list), L33-41 (layer-split slot drafters, pinned-RAM ring copies), L69 (-21.9% 2×R9700), L88-97 (option table; engine "at most 8 slots", INFO batch_slots, /v1/status), L129-136 (16-slot switches 4×R9700), L140-160 (what a slot costs; 0.56 GiB@32K int8; "1.6 GB at 128K"; setup recommends), L640, L655-665 (11-24%). [V]
7. `src/program/generate.cpp` @v0.2.9 L951-960 help: `--kv int8` (1,056 vs fp16 halved VRAM), `--kv q4_0` (PR #21, half of int8), `--kv k8v4` "816 B/cell … streams with --kv-resident too", `--kv-resident` (min 20480, whole K/V in pinned RAM, ≤N not streamed), `--kv-grow` (whole max-context at start default). [V]
8. `src/program/generate.cpp` @v0.2.9 L3795-3808 (kv value validation; q4→q4_0; `qsa_set_kv_q4` "PR #21: 4-bit codes after a Hadamard rotation (kv_q4.hpp)"; k8v4 = INT8 K + rotated Q4_0 V). [V]
9. `src/core/expert_source.cpp` @v0.2.9 L4840-4855, 4932-4975 (env read-once; skip rank 1..9; skip in window gather). [V]
10. `src/program/generate.cpp` @v0.2.9 L11140-11180 (default-7 gate: env-unset ∧ !all_resident ∧ !nearly_cached(HIP-split 60% / else 90%) ∧ `o.batch==0` ∧ `decode_defaults_arch_ok()` ∧ peer<0 ∧ !NVFP4). [V]
11. `src/program/generate.cpp` L2155-2164 + `include/strata/kernels/gfx_arch.hpp:30` — HIP arch gate = gfx1200/gfx1201 WMMA. [V]
12. `docs/DETAILS.md` @v0.2.9 L1003 (route-tail skip row: default 7; "CUDA, and HIP gfx1200/gfx1201"; "Not applied when every expert is in VRAM, with --batch slots, with a peer tier or helper GPU, on other HIP and SYCL, or ≥90% cached"; `STRATA_TAIL_SKIP_MAX_CACHED`) and L1424 (default-on since 0.1.42, KL/PPL table). [V]
13. `strata_control/profiles.py` @v0.2.9 L26, L70, L106 (`parallel` ∈ override keys, int 1..1024) + `strata_cli/cli.py` L749-813 (override precedence; conflict rule vs explicit --batch/--slots; run_config origin stays in cfg). [V]
14. `serve/server.py` @v0.2.9 L3670-3713: `PARALLEL_STACK_ENV` nine vars, `parallel_stack_env()` with `if cfg.get("backend") == "hip": return` and the comment "HIP got no measurement without replicas"; header comment "0.2.9: … +16% at c=8 two A6000 and +40..65% on one big card, no solo cost". [V]
15. `serve/server.py` @v0.2.9 L3716-3740 `gdn_stack_env` (Linux-only; HIP+all-gfx12 → `STRATA_GDN_CHUNKED=1`; CUDA → GDN_TC/CONVL2). [V]
16. `serve/server.py` @v0.2.9 L3455-3480 `engine_nice` (Linux; default +5 only when a HIP_IGPU arch visible; `STRATA_ENGINE_NICE` 0..19) + `docs/STRIX_HALO.md:247`. [V]
17. `src/program/generate.cpp` @v0.2.9 L6670-7030 (auto cache sizing after slots; reserve + draft-head terms; APU warning; `kSmallReserveMib=300` rescue; `vram_reserve_given` honored). [V]
18. `src/program/generate.cpp` @v0.2.9 L729 (`int vram_reserve_mib = 700;`), L3158 (`vram_reserve_given`). [V]
19. `src/program/generate.cpp` @v0.2.9 L3161-3173 (`--prefill auto[:N]` ∈ {8192,16384,32768}; `STRATA_PREFILL_AUTO_MAX`; Windows-HIP bare auto 6144). [V]
20. `src/prefill/prefill.cpp` @v0.2.9 L242-252 + `generate.cpp` L9321-9330 (CPU-share env, auto=measured, not-armed-by-default verdict). [V]
21. `src/program/generate.cpp` @v0.2.9 L3341-3356 (`--resident-experts` ⇒ mmap_experts+resident_cpu_experts+pin+soft, headroom 4 GiB, `STRATA_RESIDENT_PIN`/`STRATA_RESIDENT_HEADROOM_GIB`). [V]
22. `strata_control/hipblaslt_tuning.py` @v0.2.9 (docstring; `AUTO_USES_TABLE=False`; `AUTO_ARCHS=("gfx1151",)` owner ruling 2026-10-19 with gfx1201 ~1% gain/−2% decode; version numbering 1.5.0→100500, 1.2.2→100202; `resolve()` package-table logic L185-203). [V]
23. v0.2.9 tree listing `tools/hip/*.txt` — gfx1201 tables: `100202`, `100500` only (100401 exists only for gfx1100/1103/1150/1151). [V]
24. `src/prefill/gemm.cu` @v0.2.9 L318 ("prefill gemm: hipBLASLt tuning enabled (%zu rows, %s, version %d)"), L521 (rocBLAS), L912. [V]
25. `docs/AMD_HIP.md` @v0.2.9 L65-112 (packages carry tables `tuning/<arch>-hipblaslt-<version>.txt`, matched on arch+version else plain hipBLAS; switch table incl. `STRATA_HIPBLASLT_TABLE`/`"hipblaslt_table"`; `TUNING=<file>` always kept; log line `hipBLASLt tuning table: …`; Linux rx9070 package = TheRock 7.10.0a20251120 gfx120X-all wheels) and L303-304 (`STRATA_PLE_AUTO_RAM` on where RAM fits; RDNA4 8K +22.5%). [V]
26. `src/program/generate.cpp` @v0.2.9 L3790 (`--ple-io` value set), L4716-4799 (ram=mmap+mlock; default direct; auto-RAM policy needs table+arena+8 GiB headroom within `available_host_bytes()` — cgroup and `--memory-limit-mib` aware; `STRATA_PLE_AUTO_RAM=0`; `STRATA_PLE_AUTO_MMAP`). [V]
27. `src/program/generate.cpp` @v0.2.9 L853, L1017-1026 (conversation-cache help: serve default sized from free RAM up to 8192, `0`=off, slots default 4, min-free-mib under MemAvailable AND cgroup). [V]
28. `src/program/generate.cpp` @v0.2.9 L1021 (`--memory-limit-mib` help: "the total RAM (MiB) this engine's container or cgroup may use"). [V]
29. `src/core/session.cpp` L51-70 + `src/core/layer.cpp` L774-791 @v0.2.9 (session_bytes formula: QSA states at max_cells, single RoPE table borrowed across, GDN state, buffers). [V]
30. `docs/DETAILS.md` @v0.2.9 L319 (`--mtp`: draft layer ~0.7-1 GiB VRAM; suffix/prompt-lookup drafts without it). [V]
31. `strata_cli/cli.py` L297-300 + `strata_cli/bench.py` L45-56 @v0.2.9 (suite choices incl. `standard-v1` default, `parallel-mixed-v1` = warmup,serial,mixed,mixed). [V]
32. `src/prefill/mmq_kq_loader.cpp` @v0.2.9 L108-114 (`STRATA_MMQ_KQ` on iff "1" — default OFF at the pin). [V]
33. `src/program/generate.cpp` @v0.2.9 L803 (`mtp_window = 32768`), L907-908 (`lookup_chain = 0`, min 3), L3211/3261-3262, L3824-3827 (chain extends spec window ≤8). [V]
34. Absent-at-tag greps: `--kv-pool-tokens`, `--ram-keep-gib`/`STRATA_RAM_KEEP_GIB`, `STRATA_ARENA_FILE_CACHE` — zero hits in `src/ serve/ strata_control/`. [V]
35. GitHub API `releases/tags/v0.2.10` (engine 0.1.56; DFlash2 default drafter incl. gfx1201; Auto→MTP when batch≥2; #3750 reserve cap; #4846). [V]
36. GitHub API `releases/tags/v0.2.11` (engine 0.1.57; Unsloth v3.1; "Linux Radeon (gfx1200/gfx1201): the route-tail skip stays on for Unsloth files — Setup used to write `STRATA_ROUTE_TAIL_SKIP=0` … it no longer does"; R9700 solo +6.18% [M], KL 0.077 upper bound; gfx12 defaults: K-quant kernels on, bare auto 32768 (was 16384), ring 256/192; UD hot-set +0.6% not changed; MTP-vs-no-drafter per-user matrix; chunk-size near-tie answer sensitivity). [V]
37. GitHub API `releases/tags/v0.2.12` (engine 0.1.58; "Radeon gfx1201: Auto starts MTP, not DFlash2, because 11 of 50 DFlash2 engines on 0.2.11 stopped on the prompt"; manual DFlash2 can stall — known problems; R9700 32K +8.6-11.6%). [V]
38. GitHub API `releases/tags/v0.2.13` (engine 0.1.59; "Settings the launcher used to write are now the engine's own defaults: the parallel stack on **Linux CUDA** with 2+ slots, … the **gfx1151** hipBLASLt table …"; Windows gfx1201/1100 table default-off restoring the 10-19 rule; DFlash2 defaults per card; #5327). [V]
39. GitHub API `issues/3364` — **open**; "[Engine] expert-cache auto does not reserve memory for --batch slots; MTP allocation fails and the engine exits 1"; v0.2.0-beta; 2× R9700 gfx1201; `--kv int8 --kv-resident 32768`; `"parallel": 4` → engine `--batch 4`; slots ~1.27 GiB each. [V]
40. GitHub API `issues/3693` + comments — closed 2026-11-05 by maintainer **bulk housekeeping** ("closed does not mean rejected; re-test on 0.2.11"); original: explicit `--expert-cache 4497` overshoots to 5,118 (engine 0.1.44.1, recurs on 0.1.45/0.2.0-beta). [V]
41. GitHub API `issues/1188` — closed 2026-10-07; k8v4+resident repetition at 0.1.40; log lines: "KV streaming: 20480 of 262144 cells per QSA layer in VRAM, the K/V in 2.39 GiB of pinned RAM"; int8 = **3.09 GiB** @262144; q4_0 clean byte-identical. [V]
42. GitHub API `issues/4159` — closed 2026-10-29; MI50 gfx906, v0.2.6 (engine ~0.1.52), IQ3_S pack; KV-vs-FP16: int8 KL 0.055/top1 94.9/PPL 2.762; k8v4 0.104/91.9/2.900; **q4_0 0.130/91.7/2.793**; agent-segment KL int8 0.090 vs q4_0 0.200; "q4_0 frees 1.4 GiB pinned RAM at 256k (3.09 → 1.69) with no meaningful speed change". [V]
43. GitHub API `pulls/21` — **merged 2026-09-27**; Q4_0 KV with FWHT-256 rotation; halves vs 8-bit; verify/MTP/QSA-streaming compatible; perplexity preserved (no "+8-12% PPL" claim in merged body). [V]
44. GitHub API `pulls/1011` — closed **unmerged** 2026-10-06; "with KV streaming every session pins the whole context's K/V in RAM: **the main session and each --batch slot**; at 262144 that is 3.09 GiB per session, so **4 lanes pin 5 × 3.09 = 15.5 GiB**"; `--kv-pool-tokens` design; 503 `kv_pool_full` behavior. [V]
45. GitHub API `pulls/1614` — **open** (shared KV pool follow-up, unmerged) — refutes guide's "appears closed too". [V]
46. GitHub API `pulls/711` — closed unmerged. [V]
47. GitHub API `issues/2126` — closed 2026-10-19; 0.1.43 `--batch` startup hang (compaction storm) on 3× RTX 3060; body logs: healthy order "–batch: 2 slot sessions on CUDA0 (0.34 GiB each)" **before** "expert cache auto: 5.32 GiB free, 700 MiB reserved … -> 1870 slots"; "strata mtp: draft layer loaded, **835 MiB** of VRAM (experts 675, dense 111)". [V]
48. GitHub API `issues/5020` — **open**; filed against **engine 0.1.55** (`f-029-rel 99866a47a2b8`); arena keeps all 24,576 experts (**71.732 GiB** anon, fully resident) on top of the VRAM cache; documented escape = `--mmap-experts` low-RAM modes; smaps incl. parked-conversation `/dev/zero` 2.994 GiB. [V]
49. GitHub API `issues/3734` + comments — closed 2026-10-28 by **format-housekeeping bot**, no fix recorded; AMD in-place-GGUF pages ~2× expert RAM; `posix_fadvise(DONTNEED)` frees nothing. [V]
50. GitHub API `pulls/2963` — open, unmerged (sliced page-locking). [V]
51. GitHub API `pulls/3636` — closed benchmark report (R9700+Strix OCuLink; 124 GB; link ~7.2 GB/s; the guide's §3 table source). [V]
52. Repo: `EXPLORE.md` §1-§8 (live pins, ConfigMap reads, owner rulings 2026-11-10); `charts/llama-swap/values.yaml` L2142/L2252/L2267 (q4 `env: {}`, `backend: hip`, `parallel: 4`), L1883/1890, L1994/2003, L2105/2113, L2351/2356; q4 args block incl. `--expert-cache auto`, `--prefill auto`, `--kv int8`, `--kv-resident 32768`, `--conversation-cache-mib 16384`, `--memory-limit-mib 103680`; the chart's own 13,728 B/token comment. [R/V-live via EXPLORE]
53. Repo: `.agents/plans/2026-11-10-research-strata-q3-q4-rungs.md` (KV law; `--kv-resident` VRAM-window regime; arena calibration). [R]
54. Repo: `.agents/plans/2026-11-10-dep-strata-engine-0213-eval.md` (bump gate; `--ram-keep-gib`/`STRATA_ARENA_FILE_CACHE` absent at 0.2.9 — independently re-verified by [34]). [R]
55. `src/program/generate.cpp` @v0.2.9 L12284 (`INFO batch_slots=` telemetry string), L5969 ("GiB of pinned RAM" startup line), L957/L1034/L1037/L1040 (help: --kv-resident min 20480; --batch 2..8; --batch-mtp needs --mtp+--spec). [V]

---

# Round 2 — v0.2.13 / engine 0.1.59 under the bump frame

Round 2 — agent-research, 2026-11-10 (later session, same day). The owner's answers re-framed
the ticket: **the bump to 0.2.13/0.1.59 is this ticket's work, and the envelope opens toward
8 slots**. Round 1 (above) stays as the v0.2.9 adjudication — its flag table and laws remain
the BEFORE picture every diff here refers to. Method unchanged: full v0.2.13 tarball at its
tag commit grepped locally, GitHub API for live issue state, sources continue the round-1
numbering from **[56]**. `[M]/[E]/[I]` and `[V]/[R]` discipline as before. Read
EXPLORE.md "Round 2" (R2-A…R2-E) first — it owns the repo-side gate list; this section owns
the upstream facts those gates bind.

## TL;DR (bump frame)

1. **Every load-bearing law survives at 0.1.59 unchanged**: `parallel:`→`--batch` with
   `PARALLEL_MAX = 8` [57], the (N+1)-sessions-pinned-whole-max-context-at-start block is
   byte-identical to round-1's code [58], `--kv-resident` help verbatim [59], route-tail-skip
   gate identical [64]. The guide's 8-slot methodology transfers intact.
2. **The file-cache-arena regime is NOT a q4-8-slot saviour for us**: the rescue fires only
   when the arena is short AND **no cgroup limit is detected** — our engine runs under a
   110Gi k3s cgroup, so that path is excluded by construction [67]. What DOES exist at
   0.1.59: `--ram-keep-gib` and `--resident-budget-gib` push the arena to a bounded RAM copy
   + OS-file-cache reads (reclaimable inside the cgroup, SSD under pressure) — the one
   arithmetic-feasible 8×262K q4 shape, [E]-grade, measure-first [66][67][R2-§B'].
3. **L2 folds into the bump, confirmed in code**: `STRATA_MMQ_KQ=1` is the engine's own Linux
   gfx12 default at 0.1.59, joined by `STRATA_SELECT_WMMA` (+5.7% at 98K on R9700) — the
   profile-level env pin becomes intent-pinning, and both re-bench deltas belong to the bump
   [61][62]. The 9-var parallel stack, by contrast, is default-only on Linux-CUDA and
   Windows-gfx1151 at 0.1.59 — **L1 stays a manual, HIP-unqualified arm post-bump** [61].
4. **Crash cluster is worse than the bump-eval doc says**: as of today all five are OPEN with
   **zero maintainer replies**, and same-day reporter updates put **0.1.59 itself** in the
   crash set (#5559 "0.1.59 stops the same way"; #5635 "confirmed … on engine 0.1.59"; new
   #5701 runs gfx1201+0.1.59 degradation). The "0.1.57 clean" premise in R2-A §3 is dead —
   the reporter corrected it [74]. Two additional gfx1201 crash reports the eval's list
   misses: **#5614** (MES REMOVE_QUEUE wedge, 0.1.58) and **#5701** (non-finite-logits
   degradation on 0.1.59) [75].
5. **The bump carries a new config obligation**: 0.2.13's `engine_args()` runs
   `drafting.apply()` **unconditionally** — the 0.2.9 conditional is gone [79]. Our keyless
   profiles still resolve to MTP on gfx1201 (0.2.12 Auto→MTP + no DFlash2 pack on the claim +
   parallel≥2), but the bump chunk should add explicit `"drafting": "mtp"` to every flash-next
   profile as a pin.

## R2-0. Pin facts at the new candidate

- v0.2.13 tag `fb57f74` → commit **`d2f096475817d4666c364c820b0ca830f751cfc5`**; "The app and
  the Terminal are 0.2.13. Control and every engine package are **0.1.59**. Update feed
  sequence 124" [38][56]. Engine-dir naming pattern confirmed live: `0.1.59-windows-x86_64-hip-rx9070`
  (#5701), `0.1.58-linux-x86_64-hip-rx9070` (#5559 log) — so the chart's strix `exe` moves to
  `0.1.59-linux-x86_64-hip-halo/strata` exactly as EXPLORE R2-B writes it [73][77].
- Flag surface diff 0.2.9→0.2.13: **additions only** — `--ram-keep-gib`, `--draft-fallback`,
  `--draft-rule`, `--draft-mtp-min-p`, `--draft-mtp-spec`, `--geometry`, `--lookup-max-t`,
  `--lookup-sizes`; **no removals, no renames** of any flag our tuning touches [65]. Env diff:
  124 new `STRATA_*`, 4 removed (`STRATA_NVFP4_PREFETCH`, `STRATA_PARTIAL_PIN(_GIB)`,
  `STRATA_PATTN_SM60`) — none ours [65].

## OQ-R2b.1 — mapping + pinning law at 0.1.59: all survive; one new graceful path

- `parallel:` still becomes `--batch` (same "recommend, never force" wording), `PARALLEL_MAX =
  8` with the same `kVerifyNarrowT` comment [57]; `kVerifyNarrowT == 8` unchanged
  ("the narrow window is the 0.2.7 one: 8 rows") [70]. Owner's 8 = the exact pin ceiling.
  New `parallel_args` branches serve only the DeepSeek engine (`--parallel`, not our family)
  and the all-cards split engine (`split_engine_note`, which our hand-written profiles do not
  carry) — no effect on our mapping [57].
- The slot-pinning block is **identical** to v0.2.9's (verified by the same anchors:
  `bslot_ss.resize(1 + stages.size())`, per-slot `session_bytes(g, o.max_context, …)` at
  start, fit-down warning, "not two slot sessions fit" exit-down, "the slot sessions take
  X GiB of VRAM … the expert cache would otherwise hold") at `generate.cpp` L6985–7036
  [58]; expert-cache auto sizing still runs **after** the slots (L8017+) [58];
  `session_bytes`'s QSA-term section diffs clean against the 0.2.9 file [59]. **(N+1) ×
  whole-max-context, allocated at start: holds at 0.1.59.** The host-RAM side of
  `--kv-resident` — "the whole K/V in pinned RAM" — is the verbatim same help line [59];
  the per-cell constants (int8 1,056 / k8v4 816 B/cell) unchanged → our 13,728 B/token law
  and the 3.09–3.35 GiB band stand post-bump.
- **New graceful path at the pin**: when a card runs short, the server's `vram_fit.fit_start`
  steps the **KV VRAM window down 20480 → 8192 → 4096 cells** (floor `4096`, was 20480;
  `STRATA_KV_RESIDENT_MIN` overrides; only on a card that is short; setup still writes 32768)
  — "never a smaller context and never fewer requests (owner 2026-11-02)" [60][79]. At 8
  slots this materially changes the VRAM contention arithmetic vs 0.2.9: the engine now keeps
  8 slots by shrinking windows before degrading the count. The internal floor also means an
  8-slot q4 can run windows as small as 4096 cells, pushing MORE KV reads through pinned-RAM
  streaming per token (the 56.71%-hit line in #5559's log shows the streaming hit-rate is
  observable per start — add it to the read-back list).

## OQ-R2b.2 — the arena-file-cache regime and the 8-slot q4 question

**ID verification first** (EXPLORE asked): the release-notes citation "Linux, #5327 (PR
#5531, pjgmobile)" checks out but is about a DIFFERENT problem class than "arena reclaim" —
#5327 is "[Engine] Qwen3.8 q2_0 decode ~2.4x slower at 1M context since 0.1.56", **closed
completed 2026-11-09 by the maintainer citing PR #5531 merged into 0.2.13**; PR #5531
(`closed, merged 2026-11-09`) restores loading the expert arena "through the file cache"
when MemAvailable looks short but free pages + droppable file cache + a reserved hugetlb
pool can hold it — a correction to the 0.1.56 guard (itself from #4846/#4051) that
over-refused. On the 1M run: decode 47 → 124 tok/s. The engine prints the notice **on stdout
under --serve** ("a service setup never sees stderr") [67][68]. So: this is a *startup
admission* rescue for host-RAM-tight boxes, **not** a mechanism that makes an accepted
full arena reclaimable.

**Does it help our q4 arena term?** Directly, no — three code-grounded reasons:
1. The rescue requires `hm.cgroup_limit == ~uint64_t{0}`: "not under a cgroup limit (the
   host's cache is not the container's to drop)" [67]. Our engine runs inside the 110Gi
   k3s cgroup with `--memory-limit-mib` set — excluded by construction.
2. When a full arena *fits* (71.73 GiB into ~108 GiB of cgroup-aware available), it is
   still taken as the resident anon arena — #5020 ("arena keeps all 24,576 experts in RAM
   on top of the VRAM cache", filed on **0.1.55**) is **still open, zero comments** [74].
   No 0.2.10-13 note names a fix. The pinned floor at 0.1.59 is the same 71.73 GiB anon
   term round 1 measured [48].
3. The genuinely new levers are different knobs: **`--ram-keep-gib W`** (0.1.59: arena
   admitted only if W GiB stay free after it; otherwise the engine takes a RAM copy of the
   *hottest* experts leaving `max(W, 4 GiB safety on Linux)` free and reads the rest
   "from the file, like `--mmap-experts` — same answers") [66], and the explicit
   `--resident-budget-gib B`. Under our cgroup the file tier's room is honestly credited:
   "available_memory_bytes credits the group's whole `file` counter as reclaimable
   (cgroup_available_bytes)"; the **`--memory-limit-mib` operator cap is deliberately NOT
   applied to the file-cache room** ("it bounds the engine's own allocations, not the page
   cache") — and the gfx906 HMM-reclaim wedge (#1752) was checked and **"gfx1201 measured:
   not affected"** [file-tier comment, src/core/expert_source.cpp ~L905-945, V].
   That last line matters: the file-tier mode on OUR arch is explicitly probe-cleared.

**Recomputed scenarios at 0.1.59, 8 slots × 262144 int8, our node numbers** (visible
125.08 GiB [52], non-strata floor ~7.3, transient margin 8-10 → safe cgroup ceiling
~107.8-109.8 GiB; KV/session 3.35 GiB code-law [52][59] → 9 sessions = **30.15 GiB**
[band 27.8-30.15]; conv-cache 16 GiB q4-declared; misc+OS ≈ 6+7.3+8 ≈ counted as the
~108 headroom budget; [E] arithmetic on [M] terms, same shape as EXPLORE R2-C but at the
new regime):

| ID | Shape (all q4 UD-Q4_K_XL, 8×262144 int8 unless noted) | Host terms (GiB) | Total | Verdict |
|---|---|---|---|---|
| A | full arena + `--ple-io ram` + conv 16 | 71.73 + 26.8 + 30.15 + 16 + 6 | **150.7** | ✗ does not fit — not even close; guide's 137.3 was the same verdict without conv16 |
| A′ | full arena, PLE auto→**direct** (0.1.59 default here), conv 16 | 71.73 + 30.15 + 16 + 6 | **123.9** | ✗ > 110 cgroup, ≫ safe ~108 — confirms EXPLORE R2-C's q4-8-slot row; **engine degrades to 2-4 slots at boot rather than dying** [58] |
| E | `--resident-experts` complement (≈71.73−VRAM-cache≈**51.7** pinned), PLE direct, conv 16 | 51.7 + 30.15 + 16 + 6 | **103.9** | ⚠ fits on paper ONLY — unchanged from round 1's risk stack: CUDA-only evidence, #3734 ~2× duplication never fixed (closed by housekeeping) [49], #5020 open [48]; experimental soak material, not a shipping shape |
| G | experts via **file tier** (`--resident-budget-gib 44` + honest-cgroup cache, PLE direct, conv 16) | 44 + 30.15 + 16 + 6 anon + ~evictable file | **96.2 anon** | ✓ **the only realistic 8×262K q4 host shape at 0.1.59** — anon term fits with ~12 GiB margin; the 27.7 GiB above budget lives as reclaimable page cache inside the cgroup and reads hit SSD only under pressure; cost = expert-refill latency on decode (guide's `--resident-budget-gib` caution softened by 0.1.59's cached, not unbuffered, tier [file-tier V] + gfx1201 #1752-clear [V]) — MUST be measured, [E]; `--ram-keep-gib 30` expresses the same fallback by free-RAM target [66] |
| H | **primary IQ3_S** (arena 46.84), PLE forced **direct** (`STRATA_PLE_AUTO_RAM=0` [26]), conv 32→16 | 46.84 + 30.15 + 16 + 6 | **99.0** | ✓ fits (EXPLORE R2-C row holds at the new tag; KV window walkdown [60] protects the VRAM side) — **the deliverable 8-slot shape without file-tier risk**; conditional on the conv-halving owner decision and pinning `STRATA_PLE_AUTO_RAM=0`, because the auto-RAM policy WILL admit the 26.8 GiB table on this rung (46.84+26.8+8 = 81.6 < 108 available → +26.8 → 125.8 > cap) |
| — | orca 8×262144 | 57.7 + 30.15 + 8 + 6 = 101.9 | — | ✗ vs its 90 GiB declared cap (U9.2 zero-growth law) — out |
| — | q4 A′ with `--kv q4_0` | 71.73 + 9×1.72 + 16 + 6 = **109.2** | — | ✗ still over the safe ceiling at conv 16; conv 8 + q4_0 = 101.2: over the 108 line by a hair; q4_0 alone does not make q4×8×262K fit — the arena term is the wall [E] |

VRAM side (all shapes, 32 GiB R9700): dense ~5-7 + 9 streamed windows (32768 cells ≈
0.4-0.56 GiB each, or the walkdown floor) + MTP 0.7-1 + reserve ≥1.5-2 ⇒ expert cache
~16-22 GiB ≈ 5.5-7.4k of 24,576 Q4 experts (~22-30%) — read `expert cache auto → slots` +
`VRAM free` back at first boot; expect the BATCHING solo-cost class to bite per-stream
decode at 8 [6][58][70].

## OQ-R2b.3 — route-tail / batch-MTP / MMQ_KQ at 0.1.59

- **Route-tail skip**: default gate **character-for-character unchanged** from 0.2.9
  (rank 7 default; requires `o.batch == 0`, arch gate = gfx1200/gfx1201 WMMA on HIP,
  <90% cached, no peer; NVFP4 excluded) [64]. Consequence stands: OFF on our batched
  rungs at any slot count ≤8 (batch gate), ON by default on solo paths; explicit env
  cannot force it onto `--batch` slots (docs@0.2.13 unchanged). The guide's per-user
  recommendation matrix reads identically post-bump.
- **`--batch-mtp` / `STRATA_BATCH_MTP`**: present, opt-in, same single-GPU semantics and
  start-up drafter accounting at 0.1.59 (same anchors in the batch block) [58][6]; new
  adjacent env `STRATA_BATCH_MTP_SERIAL` etc. unchanged. L3 stands as written.
- **`STRATA_MMQ_KQ`**: the loader still reads `env=="1"` [32] — but the **engine's own
  arch-default layer** (`arch_defaults.cpp`, new at 0.2.13) now applies
  `STRATA_MMQ_KQ=1` for **gfx12 + Linux** (gated off only by `STRATA_GFX12_DEFAULTS=0` /
  `STRATA_DEFAULTS=026`; "a switch you set is kept") [61][62]. The engine logs it:
  "a model with K-quant experts (Unsloth UD-Q4/Q5/Q6_K_XL) reads its prompt on llama.cpp's
  MMQ kernels (+10..17% prompt speed on an R9700, first-token KL ≈ 0.03…)" — **and says
  nothing on packs without K-quant experts**: IQ3_S (primary) is NOT in scope of the
  flip; q4/orca/ornith (UD-Q4_K_XL) ARE. So EXPLORE R2-E4 is exactly right: post-bump L2
  is default behaviour folded into the bump (keep the profile env=1 as intent-pinning —
  user-set wins — but don't A/B it against a non-default). **New co-default**:
  `STRATA_SELECT_WMMA=1` + `STRATA_SELECT_ALT_MIN_TOKENS=28672` (matrix-core QSA scorer
  past 28,672-token prompts, "+5.7% at 98K on R9700, first-token KL 0.002 above 30K")
  — part of the same bump delta, answers-bit-changing, add to the re-bench expectation
  sheet [62]. And bare `--prefill auto` on gfx12 gains the **32768 ceiling** with the
  32768→16384→8192 RAM-guard walkdown (q4/orca's bare-auto profiles speed up with NO
  args edit; `STRATA_GFX12_CHUNK` steps it back) [63].
- Launcher-side: `parallel_stack_env`/`gdn_stack_env` are **gone from server.py** — those
  settings now come from the engine's `apply_parallel_defaults_cuda` (Linux CUDA) /
  `apply_gdn_chunked_default` (Linux all-gfx12) / gfx1151-Windows sets. For us:
  GDN-chunked still arrives (engine-side, same effect as before) [61]; the 9-var
  parallel stack still never fires on Linux HIP at 0.1.59 — **L1 post-bump is exactly the
  same manual env block, nothing more** [61].

## OQ-R2b.4 — adjudication updates: what the plan may treat as written in the guide

Round-1 rows marked post-pin, restated at the new pin:

| Guide claim | Verdict at v0.2.13 / 0.1.59 |
|---|---|
| `--batch` laws, "(N+1)" slot pinning, per-slot cost lines, suite names, `--vram-reserve-mib`, `--mtp-window`, `--lookup-chain` | **all hold** (unchanged code/text; [57][58][59][64][70][72]) |
| "Auto has picked MTP on R9700 since 0.2.12; never DFlash2" | **holds at the new pin** — gfx1201 Auto→MTP is the shipped behaviour [37]; our profiles additionally pin `--mtp` (see the drafting-guard row in OQ-R2b.5) |
| "DFlash2 not on gfx1201 (11/50 stall; still open)" | holds and is upstream's own state: 0.2.13 Known problems repeats "DFlash2 chosen by hand can stall on the prompt … Not looked at again in 0.2.13" [38][76] |
| "Route-tail skip … since 0.2.11 … not with batch" | same as round 1 at the new pin: engine default-on (gfx1201, solo-only); 0.2.11 was the setup-config change [64] |
| "`--expert-cache auto` unreliable under batch (#3364); explicit N not a cap (#3693)" | **holds at 0.1.59** — #3364 still open, still 4 comments (no fix recorded); #3693 still closed-by-housekeeping only [74]. Slots-before-cache ordering (partial mitigation) identical at both tags [58] |
| "`--resident-experts` marginal scenario E" | holds-with-risk unchanged: #5020 still open (filed at 0.1.55), #3734 closed-by-bot not fix, PR #2963 open-unmerged [49][50][74] |
| "hipBLASLt table step" | still a no-op at 0.2.13: launcher rule unchanged (`AUTO_ARCHS=("gfx1151",)`, gfx1201 "~1% gain / −2% decode"), **still no gfx1201 table for our venv class** — tools/hip@0.2.13 lists only 100202/100500 for gfx1201 [71]; 0.2.13 only re-restricted Windows [38] |
| "launcher-written settings are now engine defaults (0.2.13)" | **verified and scoped**: Linux-CUDA parallel stack / GDN, Windows-gfx1151, all-gfx12 chunked GDN, gfx1151 table, … — our HIP arenas gain the GDN + gfx12 default sets via the engine, but NOT the parallel stack [61][38][62] |
| "Strata changed defaults in every release 0.2.9→0.2.13" | confirmed — see the churn checklist below; the guide's "grep your --help before every flag" rule is the U1 checklist |
| Scenario A/B/E/G/H math | re-derived at the new tag in the table above — A/B/E′+ram never fit; H (primary) fits now-ish; **q4@8×262K only via the file-tier/budget regime, [E]** |

## OQ-R2b.5 — version-churn checklist for the U1 `--help`/startup capture at 0.1.59

Everything that CHANGED between our current pin and the bump target and can alter what our
profiles mean (name unchanged but semantics moved = more dangerous than a rename — renames:
none [65]):

1. **`drafting.apply()` now runs unconditionally** at every server start (0.2.9 skipped it
   for keyless-MTP configs; 0.2.13 always shapes) [79]. Resolution for our shape is MTP
   (0.2.12 gfx1201 Auto→MTP; parallel≥2→MTP; DFlash2 pack absent on the claim → can't start
   it anyway), but the bump chunk should add **`"drafting": "mtp"`** to every flash-next
   profile so intent is explicit — and grep the start log for any `[strata] drafting:` line.
2. **Bare `--prefill auto`** on gfx12: 8192 → **32768** ceiling (walkdown-protected);
   affects q4/orca shipped form [63]. `--prefill auto:32768` (primary) unchanged.
3. **`STRATA_MMQ_KQ` / `STRATA_SELECT_WMMA`**: opt-in → Linux-gfx12 default-on (UD-Q4-class
   packs; scorer ≥28,672 tokens) [61][62] — answers move; re-bench attribution belongs to the
   bump. `STRATA_GFX12_DEFAULTS=0` restores both.
4. **`--kv-resident` internal floor** 20480 → 4096 with `vram_fit` window walkdown at short
   cards [60]; explicit `--kv-resident 32768` unchanged in meaning.
5. **`--expert-cache auto`**: same formula, but a short-VRAM start now auto-retries **without
   the drafter** ("starting again without a drafter" → decode speed silently drops; watch the
   `[strata]` lines + `drafting_note` in /metrics) [79].
6. **Arena admission**: 0.1.56+ RAM guard refuses a short arena → falls back to
   file/mmap-experts reads for the run ("same answers", slower — the #5327 2.4× decode-loss
   class); 0.1.59 adds the hugetlb/file-cache rescue **only outside cgroups** — our pod does
   not get it [67][68]. Under `--ram-keep-gib`/`--resident-budget-gib` the hot-copy+file-tier
   fallback is the deliberate version of the same path [66].
7. **New knobs worth knowing exist** (defaults all preserve old behaviour): `--ram-keep-gib`
   (default 0), `STRATA_ARENA_FILE_CACHE` (default on outside cgroups; =0 refuses as
   0.1.56-58 did), `STRATA_ARENA_RAM_FALLBACK=0`, `STRATA_FILE_TIER_HONEST=0`,
   `STRATA_PREFILL_CPU_SHARE_BATCH=1` (opt-in CPU pool beside batch slots — the named answer
   to the guide's "CPU share helps only without --batch" row; default OFF, i.e. 0.2.9
   behaviour) [66][67][69], `STRATA_KV_RESIDENT_MIN`, `STRATA_GFX12_RING`,
   `STRATA_GDN_CHUNKED_MIN`.
8. **Unchanged but re-verify by grep anyway (one-change-at-a-time discipline)**: our shipped
   envs all still parse — `STRATA_REQUEST_LINES`, `STRATA_PREFILL_CPU_SHARE`,
   `STRATA_PF_FUSED` (0.1.59 keeps it as an explicit gfx12 prompt default line:
   "prompt experts on the fused int8 kernels" seen verbatim in #5559's 0.1.58 log),
   `MALLOC_MMAP_THRESHOLD_` (libc, version-free), `ROCR_VISIBLE_DEVICES` injection
   (chart-side) [65][73][74].

## OQ-R2c — live state of the gfx1201 crash cluster (fetched 2026-11-10, this session)

Per-issue, with dates; "our shape" = R9700/gfx1201-only + arena-in-RAM + int8 KV + MTP +
conv-heavy agent sessions [74][75]:

| Issue | State @fetch | Maintainer reply? | Fix in 0.1.59 named? | 0.1.59 evidence | Workload vs ours |
|---|---|---|---|---|---|
| **#5559** GPF storm `libhsa-runtime64` | **open** (2026-11-08) | **none** (2 comments, both reporter) | no | **crashes on it**: reporter follow-up 2026-11-10 16:36Z — "0.1.57 is not clean either, and **0.1.59 stops the same way**… common factor looks like prompt length"; 16:53Z: faults all in `hsa_signal_load/store_relaxed` via freed/overwritten signal vtable; bundled `libhsa-runtime64.so.1` md5-**identical 0.1.57/58/59** | **nearest published twin**: single R9700 + 128 GB RAM, IQ3_S arena box, 262144 int8, `--mtp --spec 4 --spec-min-p 0.5`, `--parallel 2`, 35K-92K prompts with conv-cache reuse — minus the container/cgroup, plus `--ple-io ram` (unlocked) |
| **#5608** gfxhub page faults RX 9070 XT | **open** (2026-11-08) | none | no | **fails under Docker 0.2.13 too** (reporter 2026-11-10 06:45Z: two page-fault events, engine auto-restart, no container OOM); HSA-env workarounds confirmed ineffective | desktop-app IQ3_S, 32K-64K contexts, no arena/MTP claims — weaker twin |
| **#5635** load-RAM regression (iq3_s 256k) | **open** (2026-11-09) | none | no | **confirmed on 0.1.59** (comment 2026-11-10 03:49Z, Windows/CUDA box: load peak ~64 GB @0.1.57 → ~92 GB @0.1.59; original Linux/AMD 0.1.58: 68→114.8 GB, systemd-oomd SIGKILL) | iq3_s 256k `--kv int8 --kv-resident 32768` = **our primary's exact shape** (different drafter); load-peak class = the 2026-11-10 incident class — a direct soak watch-item |
| **#5614** MES REMOVE_QUEUE wedge | **open** (2026-11-08; NOT in the eval's list) | none | no | not yet run by reporter | RX 9070 XT gfx1201, IQ3_S, `--mtp --kv int8`, 163840 ctx — verify-path "unspecified launch failure" escalated to kernel MES wedge + lost desktop; reporter's prior #5103 (same box, 0.1.54, 20K+ prefill MES wedge) cited |
| **#5558** 0.2.12 fails to start (unsloth Q8_0 256k) | **open** (2026-11-08) | none | no | unclear (reporter on 0.1.56) | **not gfx1201** (RTX 4080, CUDA) — class-relevant only via "runtime operation wait expired" startup timeouts; our healthCheckTimeout 1800 already covers long loads |
| **#5564** prefill stuck ~111K | **open** (2026-11-08) | none | no | unclear | **not gfx1201** (2× 2080 Ti, CUDA sm_75) — same symptom family (#4284/#5404); our soak should watch the same signature (cancel mid-prefill → busy-wait, no watchdog line) |
| **#3574** carry-patch home | closed **not_planned** 2026-10-26 | n/a | n/a | n/a | our `carry/ornith-q36.patch` still must apply cleanly at v0.2.13 (EXPLORE R2-E3 stands; Dockerfile verify layer is the tripwire) |
| NEW 2026-11-10: **#5701** gfx1201 **0.1.59** Windows UD-IQ4_XS long-agent-session degradation → non-finite logits (#879/#2519 GDN-overflow family), reproduced | **open** | (1 comment) | no | **runs on 0.1.59 and fails** | Windows/WDDM + 61 GB RAM box — not our topology, but it is the first gfx1201+0.1.59 quality-decay report under **agent traffic**, exactly our consumer |
| #5629 "verify: layer N never rang (illegal memory access)", 0.1.58, int8 KV | **open** | (1 comment) | no | unclear | matched a gfx1201 search but the body does not name the GPU — treat as unconfirmed arch; IQ3_XXS/Swift IQ3_S, 64 GB Windows |

**Cluster ruling for the plan (research voice):** EXPLORE R2-A's rule "treat no post-0.1.55
engine as proven on gfx1201" is not merely precautionary today — it is **observed**: #5559
(on the closest twin box) and #5635 both reproduce on 0.1.59 as of today, and no cluster
issue has a maintainer reply. #5327 — the only cluster-adjacent CLOSED-completed with a
named fix in 0.2.13 — is a decode-**speed** regression (arena-fallback artifact), not a
crash; its fix (PR #5531) does not help our cgroup'd posture [67][68]. Consequences the
plan must encode: (a) the bump gate #1 answer today is **NO upstream clearance** — the
soak (gate 3) is the deciding evidence, run it against #5559's exact signature (dmesg
`libhsa-runtime64 … d4a65/d4a68` offsets + exit -6/-11 pairs), #5635's load-peak metric
(`kube_pod_container_status_restarts_total` + MemAvailable curve at model load), and
#5614's MES wedge (dmesg `gfxhub`/`REMOVE_QUEUE`); (b) the plan's stop-condition (soak
reproduces → bump leg returns to the owner) is load-bearing, keep it; (c) re-fetch this
table immediately before the bump chunk lands — the cluster churns daily [77 OQ-R2c].

## Round-2 implications for the plan

- **Sequencing stands as EXPLORE R2-C wrote it**: bump PR merges → fresh startup-line
  capture on the new build (U1-v2: `strata --version`, engine label dirs, batch_slots,
  `expert cache auto → N slots`, "the K/V in X GiB of pinned RAM", `KV streaming: % hit`,
  hipBLASLt line, drafting line, gfx12 defaults lines from [62]) → **re-derive** caps from
  measured numbers → then the slot-raise PR (conv-halving + `STRATA_PLE_AUTO_RAM=0` on the
  primary + per-rung owner answers). Do not ship 110592-successors computed from 0.2.9
  arithmetic; #5635's load-peak behaviour at 0.1.59 is precisely the unknown.
- **Deliverable 8-slot shapes**: primary IQ3_S at conv-16 with forced PLE-direct (row H,
  [E] fits with ~9 GiB margin under the current cgroup) is the safe first raise; q4@8×262K
  is a **file-tier experiment** (row G) — its own plan chunk with its own rollback, not a
  values default; q4_0 does not rescue q4@8 (row "q4+q4_0" above), so OQ-5's owner question
  is worth less than round 1 estimated for slot relief (it still halves deep-park KV cost at
  4 slots — unchanged conclusion for the 4-slot posture).
- **L1 stays open post-bump** with the identical nine-env block (engine never applies it to
  Linux HIP, even 0.1.59) [61]; **L3 unchanged**; new follow-up arm: `STRATA_PREFILL_CPU_
  SHARE_BATCH=1` (0.1.59-only, opt-in, exactly addresses short-prompt TTFT beside slots)
  [69].
- **Bump PR config obligations** (beyond EXPLORE R2-B's literal list): `"drafting": "mtp"`
  key into the four flash-next profiles [79]; keep `STRATA_MMQ_KQ=1` as intent-pinning
  (user-set wins) or drop it consciously — plan decides, log line proves either [61][62];
  no action needed for `STRATA_PREFILL_CPU_SHARE`/`STRATA_REQUEST_LINES`/`MALLOC_*` (all
  parse at 0.1.59) [65][73].

## Contradictions (round 2)

1. **"0.1.57 clean on the twin box" (bump-eval doc / EXPLORE R2-A) vs the reporter's same-day
   correction** — weight the reporter (it is their box, journal-counted) [74].
2. **Guide cites `--ple-io ram` posture; #5559's twin box ran `--ple-io ram` (unlocked, page-
   cache resident) and crashed inside PLE-table filemap pages at the fault boundary** — one
   data point, not a mechanism proof; our runbook's "never pin the table" law [52] already
   excludes the risk on our side — noted for completeness.
3. **EXPLORE R2-C says "PR #5531 makes the arena load from the file cache … (#5317/#5341
   class)" — the actual issue number is #5327** (the release notes and API agree; #5317/5341
   were not fetched and are not load-bearing) [68][76].

## Open questions (round 2 — user/on-target actions; none asked live)

- **U1-v2 (user, post-bump image)**: the full startup capture above ON THE NODE — includes
  the four numbers round 2 could not compute statically: our venv's exact hipBLASLt version
  line, pinned-RAM GiB per session at 262144 on 0.1.59 (settles the 3.09-3.35 band),
  `expert cache auto` slots at 8×32768-windows, and whether any
  `[strata] drafting:` / vram-fit lines appear.
- **U2-v2 (owner, via plan questions)**: (a) does the 8-slot raise land on the primary rung
  only (row H) with the conv-halving + `STRATA_PLE_AUTO_RAM=0` side-decisions? (b) is the
  q4 file-tier experiment (row G) authorized as a soak-only branch shape with rollback?
  (c) given the cluster table above, does the owner still want the bump BEFORE the slot
  raise, or the slot raise on 0.2.9 first (row H fits at 0.2.9 today with the same conv
  decisions — the bump is not required for the deliverable 8-slot primary; research note:
  **the bump's unique envelope contributions are the walkdown grace [60], CPU-share-batch
  [69], and file-tier quality [G]** — worth stating plainly in the replan).
- **U3-v2 (on-target probe, cheap)**: does our k3s pod actually present a detectable
  cgroup limit to `host_available_memory()` (the file-cache-rescue exclusion [67] assumes
  yes)? — one `/proc` grep inside the pod settles it; if the engine reads NO limit, row-G
  reasoning improves (rescue could even fire for load-time shortfalls).
- Unresolvable from sources at either pin: any on-box 0.1.59 decode/TTFT/peak-RAM number —
  by construction, the soak measures it.

## Reliability notes (round 2 peer review)

Strongest: law-survival diffs (same code anchors read at both commits) [58][59][64]; the
arch-defaults/MMQ_KQ fold [61][62]; the crash-cluster live table (primary API, dated).
Weakest: row G's [E] margin — the file-tier page-cache behaviour INSIDE a 110 GiB cgroup
under concurrent KV-pinning pressure is inferred from code comments ("credits the group's
whole `file` counter as reclaimable"), not measured anywhere upstream on gfx1201 at our
slot shape; a bad read here means thrash, not crash (KV term is anon-pinned first). Second
weakest: treating #5701 (Windows) as informative for Linux — flagged as such. Bias check: I
relied on reporter self-corrections over the tracker's title state (correctly, per #3693's
housekeeping precedent); no source at all speaks for our exact posture (R9700-only +
cgroup'd + 8×262144 + UD-Q4) — every row above inherits that single missing measurement.

## Sources (round 2; 56+ continues the round-1 list; round-1 numbers cited as [n] refer to
`## Sources` above)

56. GitHub API `git/ref/tags/v0.2.13` → tag obj `fb57f74` peeled to commit `d2f096475817d4666c364c820b0ca830f751cfc5`; full tarball fetched + grepped locally this session. [V]
57. `serve/server.py` @v0.2.13: `PARALLEL_MAX = 8` L3861 (comment unchanged), `parallel_args` L3874-3911 (split-engine note branch; DeepSeek `--parallel` branch; `--batch` mapping + warn-over-cap identical otherwise). [V]
58. `src/program/generate.cpp` @v0.2.13: batch block L6985-7036 (`bslot_ss.resize(1 + stages.size())`, fit-down warning, "not two slot sessions fit", "the slot sessions take … that the expert cache would otherwise hold"); expert-cache auto L8017-8024+. [V]
59. `src/program/generate.cpp` @v0.2.13 L1050-1052 (`--kv-resident` help verbatim vs 0.2.9); `grep -c "of pinned RAM"` = 1; `src/core/session.cpp` L1-80 diff vs 0.2.9 = empty. [V]
60. `src/core/layer.cpp` @v0.2.13 L770-782: streamed-window floor 4096 (was 20480; equality-tested at 4096/8192 vs 20480; `STRATA_KV_RESIDENT_MIN` override; Metal keeps 20480) + `serve/server.py` vram_fit.fit_start call region (window walkdown 20480/8192/4096, "never a smaller context and never fewer requests (owner, 2026-11-02)"). [V]
61. `src/core/arch_defaults.cpp` @v0.2.13: `parallel_stack_table()` L203-215 (same 9 vars), `parallel_default_env` = **Windows && gfx1151 && slots≥2** L217-222, `parallel_default_env_cuda` = **Linux CUDA && slots≥2** L224-227, `apply_parallel_defaults_cuda` (user value wins), `gdn_default_env_cuda`, `gdn_chunked_default_env` (Linux all-gfx12), `launch_default_env` (Windows gfx1151 async launch). `serve/server.py` @v0.2.13: `parallel_stack_env`/`gdn_stack_env` absent (launcher writing gone). [V]
62. `include/strata/core/gfx12_extra.hpp` @v0.2.13 L52-68 + `arch_defaults.cpp` L299-330: gfx12 value-changing defaults = `STRATA_SELECT_WMMA=1` + `STRATA_SELECT_ALT_MIN_TOKENS=28672` + Linux `STRATA_MMQ_KQ=1`; opt-outs `STRATA_GFX12_DEFAULTS=0`/`STRATA_DEFAULTS=026`; startup lines verbatim: "+10..17% prompt speed on an R9700, first-token KL … about 0.03" and "+5.7% prompt speed at 98K on an R9700 … first-token KL 0.002 above 30K"; chunked-GDN auto line "prompt chunks of 30,000+ tokens use the chunked GDN scan". [V]
63. `src/program/generate.cpp` @v0.2.13 L3936-3966 + L9873: gfx12 bare-`auto` ceiling 32768 by default, `STRATA_GFX12_CHUNK=16`→16384 / `=0`→8192, RAM guard steps 32768→16384→8192; `--prefill auto:N` parsing unchanged L3551-3559. [V]
64. `src/program/generate.cpp` @v0.2.13 L12790-12817 + L2477-2486 (tail-default gate byte-shape identical to 0.2.9; HIP arch gate gfx1200/gfx1201); `docs/BATCHING.md` @v0.2.13 L145/L147/L236/L639/L660 identical to round-1 [6]. [V]
65. Flag-list diff (`src/program/generate.cpp`, 0.2.9 vs 0.2.13): additions `--draft-fallback --draft-mtp-min-p --draft-mtp-spec --draft-rule --geometry --lookup-max-t --lookup-sizes --ram-keep-gib`; removals none. Env-string diff (`src/`): +124, −4 (`STRATA_NVFP4_PREFETCH STRATA_PARTIAL_PIN STRATA_PARTIAL_PIN_GIB STRATA_PATTN_SM60`). [V]
66. `src/program/generate.cpp` @v0.2.13: `--ram-keep-gib` help L1297 (default 0; `STRATA_RAM_KEEP_GIB`), parse L3754-3756, admission logic L7739-7760 (arena only if W GiB stay free after; else hot-copy RAM fallback leaving max(W, 8 GiB Windows / 4 GiB else, or `STRATA_RESIDENT_HEADROOM_GIB`)); fallback line "reads the experts from the file, like --mmap-experts (slower; the answers are the same)" + stdout-under-serve (#5327 law). [V]
67. `src/core/expert_source.cpp` @v0.2.13 L6040-6090: file-cache arena rescue — verdict FallBack + `hm.cgroup_limit == ~uint64_t{0}` + not Windows + `STRATA_ARENA_FILE_CACHE=0` opt-out; credits free pages + droppable file pages + reserved hugetlb pool; "load, LOUDLY (a service setup never sees stderr)"; "same answers". [V]
68. GitHub API: PR #5531 (pjgmobile) closed **merged 2026-11-09** — body: 0.1.56 guard over-refused (hugetlb reserve credited wrong), "Fixes #5327", mechanism + correction note re MemAvailable semantics; issue #5327 closed **completed 2026-11-09** by maintainer Niko1221: "Strata 0.2.13 includes that change… decode went from 47 to 124 tokens per second" + bisect comments (0.1.55 fast / 0.1.56 cliff / 1M-context isolation / UD-IQ1_M second model confirmation). [V]
69. `src/prefill/prefill.cpp` @v0.2.13 L331-340 + `src/program/generate.cpp` L10725-10734: `STRATA_PREFILL_CPU_SHARE_BATCH=1` opt-in — CPU pool beside batch slots, taken only while no slot decodes; default preserves 0.2.9 behaviour (`share_pool = (o.batch <= 0 || share_batch)`). [V]
70. `include/strata/kernels/window_limits.hpp:21` @v0.2.13 `kVerifyNarrowT = 8` + `src/core/window_limits_test.cpp` ("the narrow window is the 0.2.7 one: 8 rows"); `serve/server.py` L1110 conversation-cache auto "up to 8192" unchanged. [V]
71. `strata_control/hipblaslt_tuning.py` @v0.2.13: `AUTO_USES_TABLE=False`, `AUTO_ARCHS=("gfx1151",)` owner-ruling comment unchanged from 0.2.9 [22]; `ls tools/hip/*.txt` @v0.2.13: gfx1201 tables = 100202 + 100500 only (100401-class still tableless for gfx1201). [V]
72. `strata_cli/cli.py` @v0.2.13 L298-300: bench suite choices identical to round-1 [31]. [V]
73. `serve/server.py` @v0.2.13 L720/L1186: `STRATA_REQUEST_LINES` survives; engine component dir naming per live reports (`0.1.58-linux-x86_64-hip-rx9070`, `0.1.59-windows-x86_64-hip-rx9070`) → halo dir label pattern for the chart's strix exe row confirmed [74][75]. [V]
74. GitHub API live fetch 2026-11-10 (issues + comments, full bodies): #5559 (open; reporter-only 2 comments incl. 2026-11-10T16:36Z "0.1.57 is not clean either, and 0.1.59 stops the same way… common factor … prompt length" + 16:53Z `hsa_signal_load_relaxed`/`store_relaxed` vtable use-after-free analysis, bundled libhsa md5 identical 0.1.57/58/59; config: single R9700 + 128 GB, IQ3_S, 262144, int8 KV, `--mtp --spec 4 --spec-min-p 0.5`, `--parallel 2`, 35K-92K prompts conv-cache 83-88K reuse, `--ple-io ram` unlocked, startup lines incl. "prompt experts on the fused int8 kernels (STRATA_PF_FUSED=1)", "draft head over 106299 tokens (212.9 MiB)", "KV streaming: 56.71% of 30816 block reads hit VRAM"); #5608 (open; 10 comments — HSA-env workaround failed, Docker 0.2.12 clean ≤65K, **Docker 0.2.13 faults 2026-11-10 06:45Z**; no maintainer); #5635 (open; comment 2026-11-10T03:49Z **confirms on engine 0.1.59**, load ~64→~92 GB peak iq3_s 256k; original 68→114.8 GB on 0.1.58 Linux); #5558 (open; 0.1.56 CUDA RTX4080 Q8_0 start expiry 307 s); #5564 (open; sm_75 CUDA; udqe static analysis; maintainer none); #3574 (closed not_planned 2026-10-26 — re-confirmed today); #5020 (open, 0 comments); #3364 (open, 4 comments, no fix recorded); #3693/#3734 (closed-by-housekeeping only). [V]
75. GitHub API search (2026-11-10): `is:issue created:>2026-11-08 gfx1201` + citation search on 5559/5608/5635 → **new cluster-class reports the eval list lacks**: #5614 (open; RX 9070 XT gfx1201 engine 0.1.58, IQ3_S `--mtp --kv int8` 163840 ctx — "verify: unspecified launch failure" → kernel MES REMOVE_QUEUE wedge; reporter cites their prior #5103 MES wedge at 20K+ prefill on 0.1.54; 0.1.59 not yet run by them); #5701 (open; **engine 0.1.59** Windows gfx1201 RX 9070 XT UD-IQ4_XS-v31 `--kv int8 --spec 4 --mtp`, long agent sessions → non-finite logits #879/#2519/#4304 family, reproduced same-day on 0.1.59); #5629 (open; 0.1.58 "verify: layer N never rang (illegal memory access)", int8 KV, GPU not explicit in body); #5663 (open; "ds4 won't start on R9700" — DeepSeek engine, out of scope). [V]
76. v0.2.10/11/12/13 release bodies @GitHub API (round-1 [35][36][37][38]) re-mined: 0.2.13 Known-problems line verbatim "Radeon gfx1201: DFlash2 chosen by hand can stall on the prompt (11 of 50 engines on 0.2.11). Not looked at again in 0.2.13"; #5327→PR #5531 item; Windows table re-restriction item; "Settings the launcher used to write are now the engine's own defaults" item verbatim (Linux CUDA / gfx1151 / all-gfx12-GDN scoping). [V]
77. Repo: `EXPLORE.md` Round-2 section R2-A…R2-E (gates, bump surface literals, envelope math, validation reality, blockers incl. the stale "0.1.57 clean" and "#5317/#5341" citations corrected here) [R].
78. Repo: `.agents/plans/2026-11-10-dep-strata-engine-0213-eval.md` gate list (as quoted in EXPLORE R2-A) [R].
79. `serve/server.py` @v0.2.13 `engine_args` L3781-3830: `drafting.apply(...)` called **unconditionally** (no 0.2.9-style guard), with `detect_hardware()`, `slots=parallel_n` (Auto→MTP with ≥2 slots), `engine=exe` flag-capability shaping; retry paths L1274-1301: VRAM-short restart **without drafter**, DFlash2-didn't-start restart **with the MTP**, `drafting_note` via /metrics; `vram_fit.fit_start` wired into args shaping. [V]

---

# Round 3 — v0.2.13 geometry-load question (C04 re-cut gate)

Round 3 — agent-research, 2026-11-11. The carry-patch tripwire fired at v0.2.13 (hunk 1's
preimage gone: `kNativeHBytes = 1024;` became a `kCompiledGeometry` expression). The settled
question, answered from the v0.2.13 tarball @`d2f0964` (round 2's tree [56]) plus live GitHub
reads: **does a flash_next-geometry-compiled 0.2.13 engine load and serve the ornith
Q4_K_XL GGUF, with and without a widened pool floor?** Sources continue from [80].

## TL;DR

1. **The family switch saves ornith**: at 0.2.13 `main()` detects `qwen35moe` from the GGUF
   header and `return`s into `strata::qwen35::run` **before any of the q4exp engine's state
   exists** [83]. Every compiled-geometry refusal the bump added (`geometry_unsupported`'s
   19 pins incl. `expert_feed_forward_length`, `compiled_geometry_mismatch`, the verify /
   remote-experts / native_moe / fused_gr / qsa / ngram pins) lives on the q4exp side and is
   **unreachable for ornith** — same structure as 0.2.9, where our patched engine proves it
   live [82][83][89].
2. **Exactly two walls remain at 0.2.13, identical in kind to the v0.2.9 ones**: (W1) the CPU
   expert pool's `kNativeHBytes` floor — now `max(native_act_bytes_for(kCompiledGeometry.n_ff),
   1024)` = **1024** under the flash_next geometry vs ornith's runtime down-activation
   Q8_K(1024)=**1168 B** → the same "activation larger than the pool's buffers" refusal, just
   expressed through the new constexpr [86][87]; (W2) `STRATA_D_FMTS` still lacks `X(12)` —
   hunk 2's preimage survives byte-identical (line offset 846→853) [92]. **The re-cut that
   changes only the ternary's floor (`1024`→`2048`, both spots on the kNativeHBytes line) plus
   the unchanged hunk-2 body clears everything statically identifiable.**
3. **Verdict: (a) — loads + serves with the 2-hunk-preserving re-cut**, high static
   confidence, with a community field report that the exact same q36 path serves Ornith-1.5-
   122B "loads and answers" with ~three small changes [94] and our 0.2.9 control (same two
   walls, serving today). Verdict (c) "refuses regardless of floor" is **ruled out**: the only
   reachable geometry refusal IS the floor wall. The remaining unknown is a runtime smoke,
   not a static analysis — the one-command probe is named for the user leg.
4. **Cluster side-note (feeds the bump gate table)**: #5701 got the cluster's first
   maintainer reply (2026-11-10T23:22Z): the maintainer ran the reporter's 124K-token prompt
   + quant + settings on an **R9700, Linux, engine 0.1.59** box and did **not** reproduce;
   asks the reporter for `STRATA_DBG_NAN=1` output [96]. No ornith/geometry fix upstream
   (#3574 still closed not_planned, no new comments since round 2; maintainer: "not in the
   plan … we want to add it later" [94]); 0.2.13's per-shape engine-download law
   (`strata-q4-<shape>`, `strata --geometry`) is the plumbing that would carry a per-geometry
   ornith binary if the probe ever surprises [95].

## R3-0. The runtime shape being adjudicated (ours, [R/V])

`engineProfileStrataOrnith` (values.yaml L2391+): `exe: /models/strata/Strata/engine/strata`
(the claim-compiled binary — the law in `test_strata_c09_ornith_arena.py` L276: "only the
claim-compiled engine carries the patched constants" [98]), args
`--native .../Ornith-1.5-122B-GGUF/UD-Q4_K_XL/…-00001-of-00003.gguf --max-context 131072
--prefill auto --mtp 2`, `parallel: 1`, `env: {}`, `backend: hip`, no `--pack` (arena-from-
GGUF native path), no `--kv` (fp16 KV), no `--expert-cache`. Build: `fetch_models.sh`
compiles `-DSTRATA_ENABLE_HIP=ON -DSTRATA_PREFILL_MMQ=ON -DSTRATA_Q6K_EXPERTS=ON
-DSTRATA_MMQ_KQUANTS=ON`, **no geometry flag → default `flash_next`** [92][98]; q36 support is
linked for every HIP arch except gfx906 (`if(NOT STRATA_HIP_GFX906) … target_
compile_definitions(strata PRIVATE STRATA_HAVE_QWEN35=1)`) — same gate at 0.2.9 and 0.2.13
[84]. Ornith: 48×512 experts, FF **1024**, Q4_K (fmt 12) downs; a 122B GGUF's expert set
never fits the 32 GB VRAM → **the CPU expert pool (hybrid mode) is always the live path** —
the W1 wall is not a dead branch [84 note under STRATA_NATIVE_EXPERTS: "the hybrid mode
(experts that do not all fit in VRAM): the CPU expert pool"].

## R3-1. Gate map between pack-load and serve at 0.2.13

Per gate: what is compared, ornith's value, verdict under a flash_next-compiled binary.
**Reachability** is decided by the family switch: `qwen35moe` → `strata::qwen35::run` at
`generate.cpp` L3369-3385, before q4exp state; the q4exp-only guards never see ornith [83].

| # | Gate (0.2.13 site) | Compares | Ornith under flash_next geometry | Verdict pristine → re-cut |
|---|---|---|---|---|
| G1 | `model_family_not_supported` via `check_engine_architecture` (gguf_reader:862; also generate 4385-4394) | architecture known & runnable? | q36 IS a supported family (linked non-gfx906) [84][91] | PASS → PASS |
| G2 | Family switch (generate:3382) | `general.architecture` == qwen35moe | routes to `qwen35::run` — everything below in this table that says "q4exp-only" is UNREACHED | n/a |
| G3 | `check_architecture_qwen35moe` (gguf_reader:645-665) | 17 `qwen35moe.*` metadata keys present + numeric; `nextn < block_count`; `full_attention_interval ≥ 2` | our GGUF passed the equivalent guard at 0.2.9 (same function/lines at the control tag — [M-node]); keys unchanged | PASS → PASS |
| G4 | `geometry_unsupported` (gguf_reader:805-846) | **19 runtime-vs-kCompiledGeometry pins incl. `expert_feed_forward_length`** | **q4exp-only** (family branch at :853 precedes it) — never runs for qwen35moe | UNREACHED |
| G5 | `compiled_geometry_mismatch` (family_layout:96-108; sole caller generate:4879) | family + field pins ("n_expert and top-k are run-time sizes") | **q4exp driver only** (post-switch) — never runs for qwen35moe | UNREACHED |
| G6 | `ArenaExpertSource::open` (expert_source:5885-5900) | `lay.n_layers/n_expert` (layout built from the same file) vs driver's runtime g — self-consistency, not compiled shape | 48×512 vs 48×512 (own values) | PASS → PASS |
| G7 | `check_experts_gguf` (from_gguf native path, expert_source:~5898-5910) | every (file,offset) tensor = claimed type/dims/inside-file, vs the **runtime** layout | self-consistent | PASS → PASS |
| G8 | **W1 — `native_fmt` pool floor** (native_expert.hpp:17-31 + native_expert.cpp:301-305; **called from q36_engine.cu:2973 with runtime `g.n_embd, g.n_ff`**) | `f.h_bytes = ggml_row_size(vdt_d, n_ff)` (ornith: Q8_K(1024)=**1168**) vs `kNativeHBytes = max(native_act_bytes_for(640)=720, 1024)=1024` | **FAIL** — "native experts: activation larger than the pool's buffers" (same wall as v0.2.9, new expression) | **FAIL → PASS with floor-2048 re-cut** (act side untouched: Q8_K(3072)=3504 ≤ `kNativeActBytes` 4096 ✓ [86][87]) |
| G9 | q36 layout cross-check (q36_engine:2974-2976) | native_fmt's computed up_off/down_off/bytes == pack layout's | derived from the same table | PASS → PASS |
| G10 | **W2 — `STRATA_D_FMTS` instantiation** (iq_kernels.cu:853-858, `STRATA_Q6K_EXPERTS` branch live in our build) | fmt 12 (Q4_K) compiled into the down-kernel list | **FAIL** — GU list has 12, D list lacks 12; q36 has no fallback for an unsupported expert pair (hard load refusal, per the patch header) | **FAIL → PASS with unchanged hunk-2 body** (preimage context byte-identical at :853/:855/:857; only line numbers drifted) [92] |
| G11 | verify.cpp:930 / remote_experts.cpp:272 `kCompiledGeometry.n_expert_used` pins | compiled top-k (10) vs runtime k | q4exp artifact/remote machinery — un-reached (q36 owns its verify windows, `kVerify=8` locally [88]; our shape has no remote/peer) | UNREACHED |
| G12 | static_assert pins in fused_gr/qsa/ngram/gdn_chunk/prefill kernels (the 18 files that gained kCompiledGeometry refs since 0.2.9 [89]) | compiled dims baked into kernels | of these, only `fused_gdn.cu` is in q36's include closure — its **single** pin is `ssm_state_size == 128` [89], which q36/ornith share ("same GDN + gated-attention 3:1 pattern, the same head dims" — model_family.hpp [91]); `native_moe_combine` appears in q36 only in a comment (q36 uses its own combine) [88] | PASS (or UNREACHED) |
| G13 | q36 MMQ prompt arm (q36_engine:1374-1377) | `MMQ::supported(type) && MMQ::fits(type, 2*n_ff)` — capability bool | false → falls back to the non-MMQ prompt path (no refusal; `STRATA_Q36_NO_MMQ=1` forces off) | PASS-by-gate → PASS |
| G14 | Pool buffer allocation (pool.hpp:367 `hq[MAXT][kNativeHBytes]`) | — | the re-cut enlarges per-worker activation buffers 1024→2048 B/row — tens of MiB across workers; no format arithmetic reads the constant (it sizes buffers; kernels use runtime `f.h_bytes`) | [E] cost trivial |

## R3-2. Does the floor re-cut clear ONLY W1? Yes — and nothing else trips

Enumerated above: the two walls G8+G10 are exactly the v0.2.9 walls re-verified at the new
tag (same refusal strings, same mechanism — G10 byte-identical; G8 expressed differently).
Every new 0.2.13 geometry mechanism (G4/G5/G11/G12-pins) sits on the q4exp side of the
family switch or is capability-gated. The re-cut shape that preserves the 2-hunk law:

- **Hunk 1** (new preimage): in `include/strata/kernels/cpu/native_expert.hpp`, the
  `kNativeHBytes` ternary's floor constant — `... > 1024 ? native_act_bytes_for(...) : 1024;`
  → the same two occurrences → `2048`, with the carry comment updated to reference
  `native_act_bytes_for` ("#3574, closed not_planned"). One line of substance.
- **Hunk 2**: unchanged content, regenerate offsets (add `X(12)` to both D_FMTS branches at
  their new lines).

Nothing else on q36's load path compares ornith's 1024 against a compiled value [V sweep:
`grep kCompiledGeometry src/qwen35/ = 0 hits` [88]].

## R3-3. Verdict and option analysis

**(a) loads + serves with the 2-hunk re-cut** — as the default posture. Confidence
[E-from-V] high: static enumeration is closed over q36's include/dependency set, the 0.2.9
control shows the same two walls were the complete answer, and the community field report
[kirinriki7777-sys, #3574] ran Ornith-1.5-122B on the q36 path with "three small changes" to
"loads and answers" (24 GB card, hybrid mode — i.e., the pool path, our mode) [M-community]
[94]. What static analysis cannot settle: q36 serve **quality/throughput on 0.2.13's q36
engine changes** (e.g. #5465's in-flight flash-attention work targets 0.2.13+ q36 prompt
paths) — that is re-bench material, not a load/refusal question [97].

(b) silent-degrade/mis-serve: not the shape of the answer — geometry values all come from
the file's own metadata at runtime (that is q36's whole design, [83][88]) and the engine's
load-time self-checks (G6/G7/G9) are pack-vs-itself consistency. The docs' "refused …
instead of mis-running" philosophy applies to q4exp; for q36 the pins just don't exist.

(c) refuses regardless of floor: **no** — the floor wall IS the only reachable geometry
refusal.

Fallback options if the on-target probe surprises:

- **O1 per-geometry/per-shape ornith binary** — mechanisms: (i) `-DSTRATA_GEOMETRY_FILE=<ornith
  header>` (the day-one mechanism: a custom header with the model's shape auto-clears G8 —
  `native_act_bytes_for(1024)=1168 > 1024` floor — but changes every q4exp kernel's
  static_asserts, so it can only serve as a SECOND binary; G10 still needs hunk 2); (ii) just
  compile the SAME v0.2.13 checkout twice (flash_next default for the four flash-next rungs,
  one re-cut-applied build — actually the re-cut makes geometry irrelevant for q36, so O1
  would only differ by patch set). Upstream's own law for new shapes is exactly this: "a
  model of a new shape gets its own engine download (`strata-q4-<shape>`) beside the Strata
  engine" + `strata --geometry` + Control manifest checks [95]. Repo cost: a second claim
  path (`/models/strata/Strata/engine-ornith/strata`), a values `exe:` move that **breaks the
  c09 arena law** (L276 pins ornith to THE claim-compiled engine) → test-session re-pin +
  fetch_models second compile pass. Strictly worse than the re-cut unless the probe fails.
- **O2 hold ornith at 0.1.55 while the other four bump: not expressible per-rung.** All five
  rungs' engines are either the one claim-compiled binary (four rungs, version-free path —
  one compile, one binary [R]) or the packaged root (strix only). There is no 0.1.55 engine
  beside the 0.1.59 claim binary after migration (the claim re-syncs the checkout; marker
  law re-fires recompile). O2 therefore means running the whole fleet at 0.2.9 or building
  two claim engines (an O1 variant with a frozen v0.2.9 checkout — the checkout is "never
  delete / one checkout" law, runbook). O2 is rejected as a shape; O1 is the escape hatch.

**The probe that settles (d)-style residual risk (user leg, commands to run on the re-cut
branch-built image or after a scratch claim-migration, per R2-D's deployment paths):**

1. Capability lines (seconds): `…/engine/strata --families` → expect `qwen4exp qwen35moe`;
   `…/engine/strata --geometry` → expect `flash_next` [83][95].
2. Load-smoke (the decisive one): start the ornith run config against the re-cut engine on a
   scratch port and watch the load phase for the two refusal strings
   (`activation larger than the pool's buffers`, `cannot load format`/layout-refusal class):
   `strata serve --config /profile/strata-ornith.json --port 8123` (or the --plan form runbook
   §3.4). A clean "session is up"/READY → W1 cleared; then
3. Answer-smoke: one `/v1/chat/completions` max_tokens 8 (same shape as the health script) →
   serves; compare greedy output vs the 0.2.9 carry engine on one fixed prompt (quality
   parity, [E]-optional but cheap).
   Cost note: the load pulls the full 122B expert set — pool/arena RAM ~65-70 GiB; run it as
   the pod's only arena (matrix time-share, or a scratch pod on the RWO claim).

## R3-4. Upstream state on this exact question (fetched 2026-11-11)

- **#3574 unchanged**: closed, state_reason **not_planned**, last human comment = the
  maintainer's "not in the plan for the next release, but we want to add it later … the
  report in this thread will help then" (2026-10-22) [94]. No geometry/ornith work landed in
  0.2.10-0.2.13 releases or the notes around it (search hits are unrelated: #5465 q36
  flash-attn proposal, #5391 cold-tier scope proposal, #5480 Windows hipMemcpy2D corruption
  report, #5379 session-file identity, #5507 pack_gguf, #5717 update.sh build-cache) [97].
- The 0.2.13 "Qwen4 groundwork" (selectable compiled geometries, `--geometry`, per-shape
  engine downloads) is the upstream **mechanism** for this problem class — it does not add
  first-class ornith support [95].
- Therefore: **the carry stays, re-cut** — and RE-WATCH #3574 at every future pin (the
  patch's own law: drop it the moment upstream ships ornith first-class).

## R3-5. Repo-side re-pin inventory for the bump chunk (law, not research — recorded so the
plan carries it):

1. Re-cut `carry/ornith-q36.patch` at v0.2.13 (2 hunks preserved; hunk 1 re-expressed per
   R3-2) [80].
2. `containers/strata/Dockerfile` verify layer L130: grep `kNativeHBytes = 2048` → **stale by
   construction** — re-pin to the new ternary shape (e.g. `grep -F '> 2048 ?'` +
   `grep -F ': 2048;'` on the kNativeHBytes line); L131 `X(12)` still valid [98].
3. `test_strata_c09_ornith_carry.py` hunk-shape/byte arms re-pin for the new hunks (the
   exactly-2-hunks law holds); clone↔README pairing rows ride the version bump (R2-B) [98].
4. `test_strata_c09_ornith_arena.py` L276 law: ornith keeps the claim-compiled exe → the
   re-cut (not a second binary) is what this law wants; keep [98].
5. Docs: README carry-patch row + the patch header's "generated as a real diff against the
   v0.2.9 tree" provenance line → v0.2.13, and re-verify hunk 2's claim "GU_FMTS already
   instantiates 12 … q36 has no fallback" still holds at the new tag (it does — checked) [92].

## Contradictions (round 3)

- The chunk brief said the family is "flash_next-geometry-compiled … serves the ORNITH pack";
  the actual mechanism is stronger than expected: ornith never runs Flash-Next-compiled
  kernels at all — the compiled geometry only sizes the pool constants it shares with the
  q4exp path. "Geometry mismatch is fatal" (option c) is therefore **not** the right frame
  for q36; the fatal-mismatch machinery (G4/G5) is q4exp's own contract. Weighed by direct
  code reading at both tags + the 0.2.9 working control.
- #5701 (round 2, 0.1.59 degradation) vs the maintainer's same-day non-reproduction on their
  R9700/Linux/0.1.59 box [96]: reporter is Windows/WDDM/16 GB-card — both stand; it narrows
  our soak's suspect surface (Linux 32 GB cards at least survived a 124K read in the
  maintainer's hands [M-upstream-claim, unverified]).

## Reliability notes (round 3)

Strongest: G8's wall arithmetic (1056→1168 vs floor 1024 — pure constants from the file),
the family-switch unreachability (one `return` statement, read at both tags), hunk-2
preimage identity. Weakest claim: "nothing else trips" is a **negative over a code set** —
I enumerated q36's dependency closure by includes + call grep, but a dim constant inside a
kernel reached through the engine's own launch tables (not by name) could evade the sweep;
the 0.2.9 control bounds the blast radius (serving today with the same two hunks ⇒ any new
silent wall would have to arrive inside 0.2.10-13's q36 code). Confidence: 8/10 that the
re-cut loads+serves; the probe lifts it to 10 for a few minutes of user time. Second-
weakest: assuming the GGUF's `qwen35moe.*` key set matches G3 exactly at 0.2.13 (it was read
under the 0.2.9 guard, whose key list is identical at both tags — low drift risk, probe
settles).

## Open questions (round 3 — on-target only)

- **P1 (user, minutes)**: R3-3's probe trio (`--families` + `--geometry` + ornith load-smoke
  with the re-cut engine; answer-smoke if load clears) — run on the branch-built image via
  the workflow_dispatch vehicle or a scratch claim-migration pod. This is the gate BEFORE
  landing the re-cut patch as law.
- **P2 (user, soak)**: q36 prompt/decode parity 0.1.55-carry vs 0.1.59-recut on one fixed
  prompt set (the re-bench already planned; ornith is cheap to fold in, GPU idle window).
- Unresolvable from sources: whether unsloth's next Ornith re-upload changes the FF/keys
  (would re-open G3/G8 arithmetic) — watch #3574.

## Sources (round 3; [56]-[79] = round 2 above; [1]-[55] = round 1)

80. Repo: `containers/strata/carry/ornith-q36.patch` (header law text + both hunks; hunk 1 preimage `kNativeHBytes = 1024;` @native_expert.hpp v0.2.9; hunk 2 X(12) both D_FMTS branches). [V]
81. v0.2.13 `include/strata/core/geometry.hpp` L1-100 — ModelGeometry (runtime struct, defaults = Flash-Next, GGUF keys named per field); `kCompiledGeometry` = header chosen at configure (`-DSTRATA_GEOMETRY` / `-DSTRATA_GEOMETRY_FILE`); "a model file of another shape is refused at load with the metadata key that differs (geometry_unsupported) instead of mis-running". [V]
82. v0.2.13 `include/strata/artifact/gguf_reader.hpp`:645-665 (`check_architecture_qwen35moe` — 17-key presence/numeric guard + nextn<block + interval≥2, NO compiled-shape pins), :805-846 (`geometry_unsupported` — 19 pins incl. `expert_feed_forward_length`; doc: "only the expert count and the experts per token are free"), :849-858 (`check_architecture`: family branch — Qwen35Moe → key-guard; else q4exp pins). Control @v0.2.9: same structure, `check_architecture` at gguf_reader.hpp:849 routes Qwen35Moe first (grep-verified). [V]
83. v0.2.13 `src/program/generate.cpp`:3369-3385 — THE FAMILY SWITCH: `#if defined(STRATA_HAVE_QWEN35)` … reads `general.architecture` from `--native`/`--model` shard header "before any of this engine's state exists", `return strata::qwen35::run(argc, argv)`; :3307-3313 `--families` output (qwen4exp qwen35moe when built); :4875-4884 sole caller of `compiled_geometry_mismatch` (q4exp driver, post-switch). [V]
84. v0.2.13 `cmake/strata_gpu_engine.cmake` L490-513 — q36 static lib linked + `STRATA_HAVE_QWEN35=1` on `strata` for every HIP arch **except gfx906** (#3172/#3271 cuBLAS/warp rationale); `STRATA_Q36_CPU_POOL=1` under `STRATA_NATIVE_EXPERTS`: "the hybrid mode (experts that do not all fit in VRAM): the CPU expert pool on ggml-cpu's arithmetic"; separate `strata-q36` executable. Control @0.2.9: CMakeLists.txt:889/:903 same gate. [V]
85. v0.2.13 `include/strata/core/family_layout.hpp`:96-108 — `compiled_geometry_mismatch` (family pin + field pins; "n_expert and top-k are run-time sizes (the Coder ships 256 experts), and n_vocab is the embedding's business"). [V]
86. v0.2.13 `include/strata/kernels/cpu/native_expert.hpp`:17-31 — `native_act_bytes_for(n) = max((n/256)*292, (n/32)*36)`; `kNativeActBytes = max(f(kCompiledGeometry.n_embd), 4096)`; `kNativeHBytes = max(f(kCompiledGeometry.n_ff), 1024)` → flash_next: f(640)=720 → **1024**. [V]
87. v0.2.13 `src/kernels/cpu/native_expert.cpp`:296-306 — runtime `f.h_bytes = ggml_row_size(vdt_d, n_ff)`; refusal "native experts: activation larger than the pool's buffers" iff act/h bytes exceed the compiled constants. Ornith: h=Q8_K(1024)=1168 > 1024 FAIL; act=Q8_K(3072)=3504 ≤ 4096 PASS (patch header's own census [80]). [V]
88. v0.2.13 `src/qwen35/q36_engine.cu` — `grep kCompiledGeometry` = 0 refs; :2973 `C::native_fmt(gu, d, g.n_embd, g.n_ff …)` (runtime → W1 reachable in the q36 path) + :2974-2976 pack-offset self-check "the CPU and GPU expert layouts differ"; :1374-1377 `MMQ::built/supported/fits` capability gate + `STRATA_Q36_NO_MMQ`; :1165 `kVerify = 8` (own windows); :151 comment-only mention of `native_moe_combine` (no call); `HD=256`, `S=128` constants. [V]
89. `kCompiledGeometry` file-set diff: 15 files @v0.2.9 → 33 @v0.2.13; the additions (geometries/*, family_layout, geometry_checks, native_expert.hpp, ngram.hpp, qsa.hpp, moe_fused.hpp, remote_experts.cpp, verify.cpp:930, native_moe.cu:35 `KU=n_expert_used` static, gdn_chunk.cu, prefill kernels/cu, generate.cpp) are q4exp-side except `fused_gdn.cu`'s single pin (ssm_state_size==128 — shared by the q36 family per model_family.hpp). [V]
90. v0.2.13 `src/core/expert_source.cpp`:5885-5900 — ArenaExpertSource geometry guard (`lay.n_layers/n_expert` vs driver runtime g; pack-vs-itself consistency), from_gguf native branch (`check_experts_gguf` tensor census before allocation). [V]
91. v0.2.13 `include/strata/artifact/model_family.hpp` — families (`Qwen35Moe = "Qwen3.6-35B-A3B (Unsloth's MTP GGUFs): plain pre-norm residual, dense attention, nextn MTP block"`; same GDN/head dims claim in the file header); `model_family_runs` = Qwen4Exp-only (the q4exp driver's guard; unreachable for q36 via the switch [83]). [V]
92. v0.2.13 `src/kernels/cuda/iq_kernels.cu`:849-859 — GU_FMTS has X(12) both branches; STRATA_D_FMTS lacks 12 in both branches (`STRATA_Q6K_EXPERTS` ON/OFF); preimage comment/context identical to the patch's hunk-2 (offset only). Repo: `fetch_models.sh` L157 compiles `-DSTRATA_Q6K_EXPERTS=ON` → the Q6K branch is the live one. [V]
93. Pack-format parity: `tools/iq_pack.py` @v0.2.9 vs @v0.2.13 identical on the v3/v4/v5 native_experts.txt header lines (no pack-format drift → existing claim packs load under the new engine). [V]
94. GitHub API #3574 live fetch (state + comments desc): closed, not_planned, closed 2026-10-26; kirinriki7777-sys 2026-10-21T18:29Z: "I tried Ornith-1.5-122B on the Qwen3.6 engine path (strata-q36). With three small changes it loads and answers; on a 24 GB card in the hybrid mode it is slow…"; Niko1221 2026-10-22T13:07Z: "Ornith 122B is not in the plan for the next release, but we want to add it later…". No activity since round-2's fetch. [V]
95. v0.2.13 release body (re-mine): "A model of a new shape gets its own engine download (`strata-q4-<shape>`) beside the Strata engine, which stays as it is. The engine reports its shape with `strata --geometry`, and Control checks it against the signed manifest" + Qwen4-groundwork framing. [V]
96. GitHub API #5701 comments 2026-11-10T23:22Z Niko1221: ran the 124,004-token prompt with the reporter's quant+settings on "our own RX 9070-class card (a 32 GB R9700, Linux, engine 0.1.59)" — did not fail, with own-card cache and with cache/chunk sized to the 16 GB card; requests `STRATA_DBG_NAN=1` capture; cluster's first maintainer touch. [V]
97. GitHub API search `is:issue geometry created:>2026-11-05`: #5465 (q36 prompt flash attention, open), #5391 (managed cold tier below RAM budget — scope proposal, open), #5480/#5379/#5507/#5717 — no merged ornith/geometry fix upstream. [V]
98. Repo: `charts/llama-swap/values.yaml` L2391+ ornith profile verbatim (native GGUF, 131072, --prefill auto, --mtp 2, parallel 1, env {}, backend hip, claim exe); `containers/strata/files/fetch_models.sh` L150-166 (hip compile flags, no geometry flag); `containers/strata/Dockerfile` L130-131 (verify greps — `kNativeHBytes = 2048` stale-by-recut, `X(12)` survives); `charts/llama-swap/tests/test_strata_c09_ornith_arena.py` L276 (claim-engine law), `test_strata_c09_ornith_carry.py` (hunk-shape arms), `test_strata_cf141_envelope.py` L111/L286-290 (ornith parallel-1 negative pins — Q9 read = flash-next rungs only). [R/V]
