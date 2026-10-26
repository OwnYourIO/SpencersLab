# RESEARCH — Qwen3.8-Flash-Next UD-Q3_K_XL (83.8 GiB) Vulkan device-lost on gpu-ai (Strix Halo gfx1151)

Written by `agent-research` (storm method, 5 perspectives, 57 sources) on 2026-10-26, for ticket
`2026-10-debug-flash-next-vulkan-oom`, feeding the post-research reintegration pass that rewrites C03.
Every claim below that isn't repo-verified carries a numbered citation to the Sources section; claims
derived by synthesis are marked **(derived)**.

## TL;DR

1. The crash signature is a fully-documented llama.cpp-on-AMD-APU failure: with mmap disabled
   (`--load-mode none`, and since Aug-2026 the `auto` default on iGPUs), llama.cpp's Vulkan backend
   routes "CPU-offloaded" weights into `Vulkan_Host` buffers, which on a RADV APU are **GTT-domain
   allocations** — so the whole model must fit the driver's GTT budget (~half of RAM by default ≈
   63 GiB on this node) *plus* pin that much physical RAM. 83.8 GiB can't → kernel
   `amdgpu_vm_validate()` ENOMEM → `radv/amdgpu: Not enough memory for command submission` → device
   lost, mid-load [27][35][40][23].
2. Upstream has NOT fixed the placement behavior as of b11810 (bisect-confirmed #29455 still open
   2026-10-09; the same-model #30987 report from 2026-10-22 reproduces on Mesa 26.2.5) [27][35].
3. The fix regime is known and community-proven on identical silicon: `--load-mode mmap` (or `dio`)
   + `--fit off` (± `--no-host`) — several owners serve 86–111 GB flash-next GGUFs on 128 GB Strix
   Halo boxes today, incl. at 262k ctx [40][27][47][42][53][33].
4. Two follow-on cliffs exist *after* a load fix, both on this exact chip: the deprecated MTP
   sidecar layout (b11386+/b11810 may refuse `mtp-Qwen3.8-Flash-Next-Q8_0` pre-#28901) [54][55],
   and a separate runtime DeviceLost class for MTP/ring-timeout at long prefill [36][20][52].
5. Branch ordering evidence strongly favors **A (flag regime) first**, B (GTT kernel params) only as
   an arithmetic complement, C (engine) as the track-record fallback (ROCm is the best-proven engine
   for this model on this chip but is an L-size change), D is premature: the model class demonstrably
   runs on this hardware today.

## Q1 — Mechanics: "Not enough memory for command submission" + device-lost on gfx1151, GTT semantics, kernel params

### 1.1 What the error actually is
- The RADV-side message is emitted when the amdgpu **command submission ioctl fails with ENOMEM
  while the kernel validates the GPU VM** — the kernel-side twin lines `amdgpu_vm_validate() failed`
  + `Not enough memory for command submission!` accompany every llama.cpp Ollama-family repro
  [40][27][29][28]. The Strix Halo comment on #27360 (owner-side analysis with Mesa/llama.cpp line
  numbers, Mesa 26.2.2, kernel 7.2.3-cachyos, gfx1151) pins the mechanism: on a RADV APU,
  HOST_VISIBLE|COHERENT|CACHED memory types are `RADEON_DOMAIN_GTT`, and VRAM-domain buffers are
  also placement-fallback to GTT; ggml-vulkan treats iGPU "free memory" as the GTT budget [40].
- The wording does **not** mean command-buffer pool exhaustion; size-driven load-time failures are
  consistently GTT-budget-driven: Ollama Renoir 66 GB model [29], 680M Gemma-4-26B [40], gfx1151
  MiniMax ~80 GB [23], and the same-model flash-next `-ncmoe` report whose author self-closed:
  *"if --load-mode none is used, GTT is used for CPU kept experts, GTT was OOMing while VRAM stayed
  not full. The more experts I pushed to CPU, the more demand of GTT"* [35].
- Lab-grade Strix record confirms the kernel pair appears in the journal of a loaded-but-degraded
  72B VLM too, and cautions that *residence errors and submission errors are separate
  observations* — our case is the load-time (residence/GTT) flavor, kernel journal is the arbiter
  [51]. C04's journal-clean proof should therefore grep both `amdgpu_vm_validate` and `BO_VA`
  (MiniMax showed `Couldn't update BO_VA (-12)` as the kernel-side variant) [23].

### 1.2 APU heap semantics (why "512 MiB dedicated" is plausible-but-misleading)
- On APUs, `AMDGPU_GEM_DOMAIN_VRAM` is only the **BIOS carve-out**; 512 MB is the community-
  recommended/minimum BIOS UMA setting [16][45][25]. The kernel boot prints both budgets
  ("`1024M of VRAM memory ready … 122880M of GTT memory ready`") — C01 should grab these lines
  from dmesg/journal [23]. `/api/hardware`'s 512 MiB is consistent with reading just the carve-out
  heap; llama.cpp itself reports carve-out+GTT as Vulkan0 capacity (123904 MiB after
  `gttsize=122880`) [40][23]. **(derived)** The real budget to check is the **GTT line**, not the
  dedicated figure.
- Vulkan cannot allocate a single buffer larger than ~4 GiB on this driver (`maxStorageBufferRange`
  = 4294967295 on gfx1151; 0cc4m: "cannot allocate buffers larger than 4GB … no straightforward
  solutions") — which is why the flash-next `per_layer_token_embd.weight` (~27–29 GiB, one tensor)
  always lands host-side and dominates the CPU-list accounting [41][42][35].

### 1.3 Kernel parameters that move the budget (exact names/units/defaults)
- `amdgpu.gttsize` (int, **MiB**): restricts the userspace GTT domain. Historical default `-1` =
  **1/2 of system RAM, min 3 GB**; current default `-1` = *whatever TTM specifies*; the parameter
  is **deprecated** (Jan-2025 patch series, warning on use, removal planned after the next LTS),
  with `ttm.pages_limit` as its replacement [14][15][16][17].
- `ttm.pages_limit` (pages of 4 KiB): TTM pool limit that sizes GTT on modern kernels [17].
  Community 128 GB-Strix values: `amdgpu.gttsize=126976 ttm.pages_limit=32505856` (≈124 GiB)
  [13][42]; `amdgpu.gttsize=131072 ttm.pages_limit=31457280` [45]; `ttm.page_pool_size` seen set
  alongside in [23]. halo-box guidance: BIOS UMA split + gttsize/pages_limit, and "newer kernels
  size GTT more generously on their own" (unquantified — measure) [24].
- `amdgpu.gartsize` (uint, MiB): kernel-side GART, per-ASIC default — not the userspace lever [14].
  `amdgpu.smu_memory_pool_size` reserves GTT for SMU debug (×256 MiB, default 0) — a foot-gun
  subtractive to the same budget [14].
- `amdgpu.lockup_timeout` (ms, string `[GFX,Compute,SDMA,Video]`): compute-ring watchdog behind the
  *other* DeviceLost class (ring timeout → reset → DeviceLost) [20][21]. Docs: 10000 non-compute /
  60000 compute on older kernels [19][16]; a 2025-06 patch unifies all to 10000 [18]; field reports
  claim 2000 ms defaults on some setups [20][21]. **Contradiction — read
  `/sys/module/amdgpu/parameters/lockup_timeout` on the node (C01).** Raising/infiniting it is
  explicitly warned as system-hang risk [21][20] → on a single-node k3s box, prefer the llama.cpp
  side (`GGML_VK_MAX_NODES_PER_SUBMIT`, merged 2026-06-24) over the kernel side [22].

### 1.4 Stability risk on this node (127.3 GiB, ~2 GiB swap, single-node k3s)
- GTT pages are **pinned physical system RAM** — raising GTT doesn't create memory, it reserves
  addressable budget that becomes unusable-by-OS once touched. The MiniMax repro crashed with
  `gttsize=122880` precisely because `--no-mmap` pinned the whole ~80 GB model through GTT while
  RAM/swap headroom ran out; kernel logged `VM memory stats … non-zero when fini` [23]. drluoto
  measured `RssAnon` 33.8 GB + `MemAvailable` 8 GB with a PLE table in anonymous (dio) memory and
  attributed an early-September OOM-kill to it [42]. Windows owners report the analogous carve-
  overflow behavior *freezes the whole box* [42-olliehm].
- Repo-internal context (ground facts): the same kernel signature preceded the 2026-10-18/19
  gpu-ai node freezes. Everything above says that risk is real and load-regime-driven, not
  budget-driven alone; the plan's bias ("smaller GPU-resident footprint / engine fixes over bigger
  apertures") matches the evidence [40][23][47].

## Q2 — Qwen3.8-Flash-Next (qwen4exp) support status at b11810; fused top-k warning; is the `-ot` regex effective?

### 2.1 Architecture support is real and mostly in-tree before b11810
- `qwen4exp` model support merged 2026-08-27 (#27742) [39]; MTP draft-head (`--spec-type draft-mtp`)
  merged upstream 2026-10-01 (#29761, ≈b11386) after earlier community PRs (#27836 Aug-27) [37][53]
  — so b11810 has the arch and the draft path [55]. Vulkan-specific gaps closed too: the
  GATED_LINEAR_ATTN op (the 36 recurrent layers) got a Vulkan compute shader 2026-08-04 [31], and
  the mul_mat_id row-id hoisting limit was raised 256→512 experts 2026-09-18 (#28501, +19 % prefill
  measured on Strix) — both inside b11810 [49].
- Model shape (for accounting): 125B-total/6B-active MoE, 512 experts / 10 active, 48 layers
  (≈3/4 gated-delta-net, ≈1/4 full-attention with QSA top-2048 selection), **plus a separate ~51B
  n-gram PLE embedding table** = the 27–29 GiB single tensor, 262K native context [57][42][35].
- Known correctness scar tissue on gfx1151: multi-segment prompts degenerated to `//////` — root-
  caused to the `GGML_CUDA_ENABLE_UNIFIED_MEMORY` env var on **HIP** builds (not the qwen4exp
  graph); PR #27902 + removing the env var resolved it; issue closed as stale-with-resolution [33].
  Note the env-var trap: its *presence* (even `=0`) flips the HIP managed-memory path [13].

### 2.2 "fused top-k mask not supported, set to disabled"
- Meaning: llama.cpp's `resolve_fused_ops` wanted the fused MoE-routing op (the softmax/top-k/mask
  chain as one kernel — a backend opt-in fusion); the active backend lacks it, so fusion is
  disabled and the routing runs as ordinary unfused ops [32][34][57]. It is a **perf**, not
  correctness, switch — models log the same warnings while loading and serving fine (Metal
  MTL0 logs for this very model: warnings present, `model loaded`, 36–55 t/s served) [32 — low-
  confidence artifact blog, directionally corroborated by [34] and by the fact that flash-next
  serves on Vulkan forks that carry no fused top-k path [47][48]).
- For the ticket: it appears ~2 s before the abort in all crash logs but is also present in
  successful loads → **confirmed red herring for the crash** (matches the plan's hypothesis),
  though it does mean the 512-expert routing is unfused on Vulkan (the #28501 hoist fix is the
  relevant mitigation and is already in the image) [49][35].

### 2.3 Does `-ot "\.ffn_.*_exps\.=CPU"` actually offload qwen4exp experts?
- Almost certainly yes *at placement time*: on the same GGUF family, changing expert-CPU knobs
  verifiably moves buffers between `Vulkan0` / `Vulkan_Host` / `CPU_Mapped` in the load log, and
  `-ot` cherry-picking behaves identically to `-ncmoe` ("doesn't matter which layers, tried to
  cherrypick with -ot, same result") [35]. Unsloth GGUFs follow llama.cpp naming; experts are
  `blk.N.ffn_{gate,up,down}_exps.weight` (matched by the regex), while the PLE table is
  `per_layer_token_embd.weight` (not matched — and forced host-side by the 4 GiB cap anyway)
  [35][42][41]. **(derived, C01 must verify with the GGUF tensor-name dump and load-time buffer
  lines)**
- The trap is the **destination**, not the match: under `--load-mode none` those "CPU" experts
  become `Vulkan_Host` = GTT-pinned, so the offload regex being "effective" is exactly what drives
  GTT demand through the roof (the reporter's own conclusion) [35][40]. Under `mmap`, the same
  placement yields `CPU_Mapped` (file-backed, reclaimable, no GTT pin) [40].

## Q3 — Viable engines/builds on gfx1151 for ≥80 GiB GGUFs

### 3.1 Newer stock llama.cpp builds: waiting won't help
- The Vulkan_Host/GTT placement is unfixed upstream through at least b11783–b11810: #29455
  (bisect-confirmed against #26081) open as of 2026-10-09; #27360 open with an un-merged suggested
  fix; #28326 ("disable lazy tensor loading by default on iGPUs", merged 2026-09-08) does NOT
  change load-mode placement (#28326 shipped in the b11351 vendor bump but per the vendor reporter
  "does not change the load-mode behaviour" [30][28][27][40]). So "roll the renovate pin and hope"
  is not a plan; the discriminating knob is `--load-mode`.

### 3.2 ik_llama.cpp — already in the image, unknown on this model
- `ghcr.io/mostlygeek/llama-swap:unified-vulkan` **bundles `ik-llama-server`**, built with
  `-DGGML_VULKAN=ON` (docker/unified build graph: `vulkan … llama ik-llama … assemble`) [1][2] —
  C01 verifies presence in `-266` inside the pod (`ls` of the bin dir / `/versions.txt`).
- ik mainline merged qwen4exp MTP support 2026-09-02 (PR #2369) [3], but whether the *pinned
  commit* in image `-266` includes it is unverified; and Strix tuning guidance rates ik as
  "gains are CPU/CUDA-focused, Vulkan support is thinner than upstream. Measurable experiment,
  not a known win" [4]. ik predates/diverges from the #26081 load-mode machinery — its GTT behavior
  under `-ncmoe` on RADV APUs is unresearched. Cheap as a rung test, low confidence.

### 3.3 ROCm/HIP — the best-documented path for THIS model on THIS chip, but an L-size change
- Feasible and measured: kyuz0 toolboxes `rocm-10.0-strix-llama` published **Qwen3.8-Flash-Next
  Q4_K_XL + shared-Q8 MTP: 1207 t/s pp2048, 1055 t/s @32k, 43.9 t/s decode** on Strix Halo; `rocm-
  10.0-gufo` also validated on flash-next UD-Q4_K_XL with shared-Q8 MTP [5][42-drluoto ROCm
  lineage][37]. #27797's reporter loaded UD-Q4_K_XL (111.3 GB) on a 128 GB Strix box under ROCm
  7.2/kernel 6.19.8 [33]. Xolotl's Strix recipe runs ROCm 7.14.1 with a hipBLASLt tuning table and
  recommends UD-IQ4_XS from ~80 GB [25]. Lemonade ships gfx1151 ROCm llama.cpp builds [8][9].
- Minefields (why it's L, not M): historical hipBLASLt "unsupported architecture" fallback on
  ROCm 7.1 (#5643; needs newer SDK or tuning tables) [6][7]; `HSA_OVERRIDE_GFX_VERSION=11.5.1`,
  `ROCBLAS_USE_HIPBLASLT=1`, `HSA_XNACK`, `HSA_ENABLE_SDMA` env set for containers [13]; an async
  batched-inference **correctness** bug requiring `HIP_LAUNCH_BLOCKING=1` (PPL 88 vs 9.4!) [24];
  the `GGML_CUDA_ENABLE_UNIFIED_MEMORY` corruption trap [33][13]; April-2026-era HIP page-faults
  at load [43]; gfx1151 reports `VMM: no` (no virtual-memory-management path in ggml HIP) [7].
  Pod needs `/dev/kfd` + render group — the amd-gpu device plugin 0.22.0 currently exposes
  `amd.com/gpu`; a ROCm image is a new container under `containers/` per container-creation,
  image pin renovate-governed (no hand-bump).
- If pursued, note soothill's Aug-2026 result: a **patched Vulkan** build beat ROCm 7.14 on
  DeepSeek-V4-Flash 97 GiB across all four tests, with clean kernel logs both arms [10].

### 3.4 GGML_VULKAN_* / env + heap controls (stock b11810 surface)
- `GGML_VK_MAX_NODES_PER_SUBMIT` (from #24872, merged 2026-06-24 — in b11810): splits graph
  submits to dodge the ring watchdog [22][20]; insufficient alone against the MTP-prefill class
  [36]. `GGML_VK_VISIBLE_DEVICES` used in Ollama repros [29]. No env knob exists to cap
  `Vulkan_Host` size or force CPU-buffer placement — that's what `--no-host` / `--load-mode` flags
  do [40]. Fork-only knobs worth knowing exist but aren't in our image (`GGML_VK_PERF_LOGGER`,
  `GGML_VK_MMV_NO_SPLIT`, `GGML_VK_DISABLE_GDN_CACHE_FUSION`, `GGML_VK_FA_KV_CONTIG`) [24][47][48].
- No public report of a `GGML_VULKAN_*` memory-limit / import-control fixing the GTT class — the
  lever is load-mode placement, not backend env tuning. **(gap; searched)**

### 3.5 Strix-specific forks = the demonstrated flash-next stack
- drluoto `strix-halo-vulkan` fork docs give the full working recipe for exactly this model on
  exactly this chip (Vulkan-only, Mesa 26.0.3, `-lm dio`, 262k ctx, `--ctx-checkpoints 8`, trimmed
  frspec MTP head): 33–58 t/s decode, 517 t/s pp [47]. Nathanw1014's toolbox (bundled current Mesa
  + FA/MoE-prefill fix set, several merged upstream incl. #25494) publishes a **Q3-class
  flash-next** flag line: `-ngl 99 --n-cpu-moe 0 -fa on --load-mode mmap --no-host --no-repack
  --fit off` measured on gfx1151/64 GB [48]. EngramHalo.cpp additionally runs the 27 GiB engram
  table SSD-backed [54]. Community consensus: stock llama.cpp leaves ~50 % of the hardware on the
  table, forks carry the rest [50][8]. A repo-built custom image would be branch-C work with these
  recipes as its validation target.

## Q4 — Peak-memory accounting for the exact failing regime on this node

### 4.1 The load-time accounting, empirically (same model family, mmap-off regime)
- #30987's crash log is the Rosetta stone (Qwen3.8-Flash-Next UD-IQ4_XS-merged, `--load-mode none`,
  `-ncmoe 33`): the loader printed **`Vulkan0 model buffer 21184 MiB + Vulkan_Host model buffer
  40681 MiB + CPU_Mapped model buffer 27465 MiB`** → then the GTT OOM. Raising `-ncmoe` moved more
  weight into `Vulkan_Host` (=GTT) and crashed sooner, "while VRAM stayed not full" [35].
- Mapping onto our ticket (83.8 GiB UD-Q3_K_XL, `-ot experts=CPU`, `-ngl 99`, `--load-mode none`):
  experts ≈ 55–65 GiB requested as "CPU" → become Vulkan_Host/GTT; dense + output + KV + compute +
  draft add ≈ 15–20 GiB more device/GTT demand; PLE (~27 GiB single tensor) cannot be a GPU buffer
  [41][42]. Required GTT ≈ 70–85 GiB vs default budget ≈ **half of 127.3 GiB ≈ 63 GiB** [15][17] →
  ENOMEM partway through `load_tensors` — consistent with aborting ~21 s in, mid-load [27][40].
  **(derived — C01 must confirm the node's actual GTT line; kernel 7.3 may be "more generous" [24],
  which would shift the cliff — but MiniMax at gttsize=120 GiB still crashed, see 4.3.)**
- Why the 32 GiB rungs live: their entire GTT demand (weights-pinned-when-offloaded + KV + compute)
  stays below the same ~63 GiB budget. Same mechanism, different size — no contradiction [35].

### 4.2 Does `--load-mode none` "double-count"?
- Not in the literal two-copies-per-tensor sense (with mmap off, the bytes are copied once, into
  the GTT-backed host buffer). The effective penalty is threefold **(derived from [26][40][35][23])**:
  (a) everything resident is **pinned** (GTT pages = non-reclaimable RAM; page cache under `mmap`
  is reclaimable — which is exactly why `mmap` survives), (b) both `Vulkan_Host` weights AND
  Vulkan0-overflow (beyond the 512 MiB carve-out) share the **one** GTT budget, and (c) `--fit`
  (default on) dry-loads with `LOAD_MODE_NONE` repeatedly, adding transient churn and *mis-
  accounting* the GTT-backed buffers as host memory (it "can't see this" per the #27360 analysis)
  [40]. PR #26081's "model in RAM twice" rationale is about dGPU-style copy paths; on a UMA APU the
  memory is already device-visible, so `none` buys nothing and costs the reclaimability [26][40].
- `--load-mode dio` (exists in b11810): anonymous, non-evictable copies like `none`, but avoids the
  Vulkan_Host/GTT detour for host-list weights per the Windows observation and drluoto's working
  `-lm dio` line — treat as the second-choice variant of A on Linux RADV [47][42].

### 4.3 The regime that minimizes peak device/GTT memory — what sources actually recommend
Order of directness for our crash:
1. `--load-mode mmap` — the confirmed fix in #27360 (680M), #29455 (Renoir bisect), Ollama vendor
   cases; the flash-next config block quoted in PR #27836 runs `load-mode=mmap` + `n-cpu-moe=48` +
   262k ctx + FA on [40][27][28][53].
2. `--fit off` (avoid LOAD_MODE_NONE dry-loads) [40][48]; `--no-host` (route CPU-list weights to
   CPU/CPU_REPACK instead of Vulkan_Host — measured table at `-ngl ≤ 32` on gfx1151 in [40]).
3. Keep `-ngl 99`/`-ot`/`-ncmoe` — under `mmap` the placement works the way the repo intended;
   lowering `-ngl` or `--no-kv-offload` are *redundant levers* once load-mode is right (they move
   bytes between Vulkan0 and Vulkan_Host, "whatever -ngl is" under the broken regime) [40][35].
4. KV/ctx: f16 KV at `-c 262144 -np 3` fits alongside an 86 GiB trunk on this chip [47] — the
   ticket's q8_0 KV at 1 slot is not the binding constraint; dropping the 3.9 GiB MTP draft only
   helps if the draft itself (or its *runtime* class, see Q5) is what breaks [36][47].
- Hard counter-evidence for "just raise the aperture": MiniMax ~80 GB on a 128 GB Strix box with
  `gttsize=122880` + `--no-mmap` → same kernel ENOMEM (`Couldn't update BO_VA (-12)`) — with the
  whole model pinned via GTT, the budget raise converted a driver OOM into a physical-RAM OOM [23].
  Pair B with A (mmap/dio) or it fails; community B-only recipes all implicitly sit on mmap/dio
  default loads [13][45][42][46].

## Q5 — Community evidence: ≥80 GiB flash-next-class MoE on Ryzen AI MAX+ 395 / Strix Halo

### 5.1 Successes (configs, versions)
| Stack | Weights | Engine / regime | Result | Source |
|---|---|---|---|---|
| drluoto, Bosgame M5 128 GB, **Mesa 26.0.3**, RADV | IQ4_XS trunk + requant Q5_K (~86 GB) + 2.4–3.9 GB MTP | **fork strix-halo-vulkan**, `-lm dio -fa 1 -ub 2048 -c 262144 -np 3 --ctx-checkpoints 8 -ctk/-ctv f16`, draft-mtp n-max 3, **no ngram-mod** | 33.1 warm / 32.5 cold decode, 517 pp@8k; bit-identical greedy | [47][42] |
| KYmidnight, 128 GB, Fedora 44, **`gttsize=126976 ttm.pages_limit=32505856` (124 GB GTT)** | ROCmFP4-FAST ~90 GiB + 2.4 GiB MTP | fork b10981, **`--load-mode mmap` -ngl 99 -fa 1 -np 2 -c 524288 f16 KV**, draft-mtp adaptive | 46.9 t/s decode @24k; accepts 0.86–1.0 | [42] |
| olliehm, Windows 11 (same silicon class), 96/32 carve | UD-IQ4_XS, 74 GB fit at 262k in 96 GB carve + Q8_0 MTP | HIP TheRock 10.1 + rdna-boosts, mmap PLE host-side | 38 t/s served, 85–100 % accept | [42] |
| flobob45 validation, gfx1151 RADV, 96 GB | **UD-Q3_K_XL** + self-grafted MTP | PR #27836 build, Vulkan | loads/runs; MTP draft path a net loss on stock Vulkan | [53] |
| #27797 reporter, Strix laptop, ROCm 7.2, kernel 6.19.8 | **UD-Q4_K_XL (111.3 GB)** | HIP, `-ngl auto -c 8192` | loads & serves after env-var fix | [33] |
| kyuz0 toolboxes `rocm-10.0-strix-llama` | Q4_K_XL + shared-Q8 MTP | ROCm 10.0 | pp2048 1207 / decode 43.9 t/s | [5] |
| Nipal33 | stock Unsloth UD-IQ4_XS + MTP | fork strix-halo-vulkan | ~33 t/s → 38.7 with requant | [42] |
| agledger, Strix Halo Ubuntu 26.04 | gpt-oss-120b | stock llama.cpp Vulkan | 128k prefill stable only with **`-ub 512`** + FA; 2048/1024 → ring-timeout DeviceLost | [52] |

Takeaways: (a) the model class runs on 128 GB Strix Halo today on both engines; (b) **no working
≥80 GiB report uses `--load-mode none`** — every survivor uses mmap or dio (or Windows-HIP); (c) the
big-context successes are on patched/fork builds, and stock Vulkan successes stick to modest ctx.

### 5.2 Failures matching our signature
- #30987 (2026-10-22): exact model, `--load-mode none`, GTT OOM — author understood & self-closed
  [35]; #27360 (auto-default crash class, gfx1151 comment reproduces at 16 GiB model / 4 GiB
  carve-out) [40]; #29455 bisect [27]; Ollama #17748 (780M) / #18272 (Renoir 66 GB) vendor
  regressions to the same commit [28][29]; kyuz0 #95 MiniMax (Strix, --no-mmap) [23]; lab record
  with identical kernel pair under a running 72B VLM (unattributed causally) [51].
- *Different* signature, same chip — the runtime DeviceLost family (ring timeout → reset):
  ollama #17870 (long-prefill prefill; num_batch=128 works around; upstream fix = nodes-per-submit
  PR #24872) [20][22]; #27306 (draft-mtp re-decodes after every prefill ubatch → death at 55k /
  114–117k even with `GGML_VK_MAX_NODES_PER_SUBMIT=1`; MTP-off survives 125k; open) [36];
  #21724 (older APU analog; `lockup_timeout` workaround) [21]. These are **post-load** cliffs the
  C03 regime must pre-empt or consciously accept.

## Contradictions & uncertainty (explicit)

1. **lockup_timeout default**: 2000 ms claimed from the field [20][21] vs 10000/60000 in kernel
   docs [19][16] vs unified-10000 patch [18]. Weight: field values are kernel/distro-specific —
   measure on node; not load-bearing for the load crash (different class).
2. **"raise GTT → works" vs "raise GTT → still crashed"** [13][45][46] vs [23]. Weight: not
   contradictory — the pair (aperture size × pinning regime) must satisfy budget AND physical RAM;
   sources that "just set gttsize" all run mmap/dio loads underneath. Treat B as necessary-sometimes
   *only with* A.
3. **Bug vs driver truth** for #26081: designed to *save* iGPU users [26]; bisected as a crash
   regression [27][40]; accepted as understood GTT semantics by the flash-next reporter [35].
   Weight: behavior is real in b11810 and unfixed; what matters operationally is that the workaround
   (`mmap`/`no-host`) is the maintainers' own [40].
4. **Vulkan vs ROCm superiority**: [10][12][47] vs [11][5][9] vs [43][6]. Weight: chronological —
   ROCm on gfx1151 improved 2025→2026 (7.14/10.0 era is genuinely good for this model per [5][42
   drluoto-ROCm]), while patched-Vulkan advocates close the gap [10][47]. For branch C, choose on
   *correctness minefields + ops cost*, not on benchmark threads.
5. **MTP value on stock Vulkan for this arch**: net loss at b10xxx [53] vs big gains on forks with
   trimmed heads + determinism patches [47][42]; and stock MTP-at-depth carries the #27306 device-
   lost class [36]. Weight: keep MTP out of the *first* successful-load test; re-add deliberately.
6. **PLE per-head split necessary?** [42-KYmidnight "or it will swap you into the ground"] vs
   [42-drluoto "<1 % wall time, left unsplit"]. Weight: regime-dependent (mmap slot-count/pressure
   vs dio); not required for the fix, revisit at perf stage.
7. **Our node's GTT default** is unmeasured — kernel 7.3.0 may size it more generously than the
   1/2-RAM doc default [24][14]; the entire Q4 arithmetic cliff moves with this one number. C01's
   dmesg read settles it.
8. Low-confidence source flagged: [32] Metal-warning-parity blog (garbled artifacts; used only for
   "warning ≠ abort", which is independently supported by [34][47][53]).

## Implications for the plan (C03 branch mapping)

**Recommended branch ordering: A → (A+B if budget-short) → C(ik probe → ROCm/fork image) → D.**
D is pre-empted by evidence: ≥80 GiB flash-next runs on this chip today; the ticket's "cannot run
today" would be a *regime* verdict, not a *hardware* one [47][42][33][5][53].

### Branch A — flag/regime on `unified-vulkan-266` (recommended first; repo-side; S–M)
Change the flash-next `${moe}` regime in `services/gpu-ai/prod/values.yaml` (+ chart macro if
shared): replace `--load-mode none` with **`--load-mode mmap`**, add **`--fit off`**, consider
**`--no-host`**; keep `-ngl 99`, keep the `-ot` regex (or the `--n-cpu-moe 48` variant quoted in
#27836 — equivalent placement, robust to tensor naming [53]); optionally drop `--spec-type draft-mtp`
and the `-hfd` MTP sidecar for the first controlled load (see C04 gate + the deprecated-sidecar
risk [54][55][37]). Sequel test for the *runtime* cliff once load passes: `GGML_VK_MAX_NODES_-
PER_SUBMIT=1` env on the model (image has #24872 [22]) and/or `-ub 512` [52][20][36].
- **Cheapest discriminating test (zero crash risk):** re-read the *existing* crash attempt's
  upstream log (llama-swap `/logs/stream/{model_id}` history in Loki) for the `load_tensors:`
  buffer-split lines — if `Vulkan_Host model buffer size` is tens of GiB while `CPU_Mapped` is
  ~the PLE size, the GTT mechanism is confirmed from logs already on the box [35][40]. Then the
  one consented load attempt with `--load-mode mmap --fit off`: success → A chosen; kernel
  `amdgpu_vm_validate` again → capture GTT default (→ B).

### Branch B — kernel/aperture params (user-owned host change; only as A's complement)
Record as precondition: `ttm.pages_limit=32505856` (+ `amdgpu.gttsize=126976` if kept for
compat, deprecated [14][17]) — the 128 GB-Strix community standard [13][45][42]; decide the BIOS
UMA question (512 MB is fine **if** the regime is mmap — larger carve-out trades host RAM for
driver-visible, [45][46][25]). Freeze-risk rules for DECISIONS: (i) never pair B with `--load-mode
none` (MiniMax proof [23]); (ii) re-check kubelet allocatable after boot (GTT pages are pinned RAM
[16][42]); (iii) do **not** touch `lockup_timeout` on this single-node box until the runtime class
actually bites [18][21][20]. Repo delta: annotation/DECISIONS only.
- **Cheapest discriminating test:** `dmesg | grep -E "VRAM|GTT memory ready"` +
  `/sys/module/ttm/parameters/pages_limit` on the node — one command, no attempt consumed. If the
  printed GTT < required device+KV (~"dense+KV+compute ≈ 25–30 GiB" under A/mmap), A alone can't
  load either and B is forced; if GTT ≈ 60 GiB+, A should be sufficient.

### Branch C — engine/build change (M–L)
C1 **ik-llama-server** (already bundled in unified-vulkan [1][2]): one rung's `cmd:` pointed at it —
repo-side S test, but verify qwen4exp presence in the bundled commit first [3][4]; low confidence.
C2 **ROCm/HIP image** (new `containers/llama-*`, `/dev/kfd`, device-plugin work, env minefields
[13][24][33][6]): the strongest *published* track record for this model on this chip [5][33][42];
L-size. C3 **Strix Vulkan fork image** (drluoto strix-halo-vulkan / Nathanw1014 recipes [47][48]):
also brings Mesa-in-image currency (our pod ships its own Mesa [44]); M–L. Prefer C2/C3 only if
A(+B) loads but the *serving* quality/runtime crashes make the rung useless, or if load fails under
every stock regime.
- **Cheapest discriminating test:** for C1, `kubectl exec` listing (user-run) of `/app/bin` (or
  `/versions.txt`) inside the running pod — presence/cost of ik in -266; for C2, a distrobox/
  toolbox run of `kyuz0/amd-strix-halo-toolboxes:rocm-10.0-strix-llama` (or `-vulkan-radv-
  performance`) **off-cluster** with the same GGUF shard [5][23] — proves the engine on the metal
  before any repo/container investment.

### Branch D — accept-unrunnable (S)
Evidence forbids the current form: replace "cannot run" with a precise, dated statement — "stock
b11810 + `--load-mode none` cannot run UD-Q3_K_XL on gfx1151 (GTT-pinned regime exceeds the
aperture [35][40][23]); the model class runs on this chip with mmap/dio regimes [47][42][53]". D
then becomes: keep C02 fail-fast, file the regime change as a *future* A-ticket, revisit at next
engine train. Only take D if A/B/C1 all land without a load.

### Guardrails the rewrite should carry
- The deprecated MTP sidecar is a latent second failure: verify the `-hfd …mtp-Qwen3.8-Flash-Next-
  Q8_0` file is post-#28901 (hc) layout before re-enabling `--spec-type draft-mtp`; expect a hard
  `check_tensor_dims: tensor 'output_hc_norm.weight' not found` if not [54][55][38].
- C04's freeze protocol remains one-attempt/journal-clean [23][51]; journal greps:
  `amdgpu_vm_validate|BO_VA|command submission|ring .* timeout`.
- No hand-bumped image tags; `--fit off` etc. go through the per-rung `flags:`/`use:` override
  layer; chart pytest goldens re-capture routes through agent-test [plan Commands].

## Open questions (for C01 / the reintegration pass)

1. **Measured GTT default on gpu-ai** (kernel 7.3.0 "generous" claim unquantified) — dmesg + sysfs
   [24][14]. Determines whether A suffices alone.
2. **The historical crash log's `load_tensors:` buffer split** for flash-next-q3 (Vulkan_Host vs
   CPU_Mapped MiB) — may already exist in Loki from prior attempts; would close Q4 without a new
   repro [35][40].
3. **Pod Mesa/RADV version** (`/versions.txt`, `vulkaninfo` inside the container) — the pod uses the
   image's bundled Mesa, not the host's; community repros span 25.2.8–26.2.5 with identical
   behavior, but exactness matters for fork-image choices [44][23][35][47].
4. **ik-llama-server presence + commit in unified-vulkan-266**, and whether that ik revision has
   qwen4exp [1][3][4].
5. **Whether llama-swap's catalog injects `--fit` by default** in this repo's config (fit behavior
   is the difference between one GTT load and several) [40].
6. Whether b11810's `resolve_fused_ops` CPU-fallback for top-k-mask leaves any correctness-affecting
   op unfused beyond perf (no source claims correctness impact; treat as perf-only) [32][34].
7. GPU-side GTT accounting with `-ot` under **mmap**: no source measures flash-next-q3's
   `Vulkan0`+GTT footprint at exactly `-ngl 99 experts→CPU 262k q8 KV`; C01's EVIDENCE.md numbers
   will show the true headroom [40][35].

## Sources

1. ik_llama.cpp build+install (BACKEND=vulkan) — https://github.com/mostlygeek/llama-swap/blob/main/docker/unified/install-ik-llama.sh
2. llama-swap unified image README (build graph; vulkan variant includes ik-llama) — https://github.com/mostlygeek/llama-swap/blob/main/docker/unified/README.md
3. qwen4exp MTP merged into ik_llama.cpp main PR #2369 (2026-09-02) — https://huggingface.co/jamesrogers/Qwen3.8-Flash-Next-MTP-MXFP4-GGUF/blob/main/README.md
4. strix-halo-llm GOING-FASTER (ik Vulkan "thinner, not a known win") — https://github.com/lazarevtill/strix-halo-llm/blob/main/docs/GOING-FASTER.md
5. kyuz0/amd-strix-halo-toolboxes (rocm-10.0-strix-llama flash-next measurements) — https://github.com/kyuz0/amd-strix-halo-toolboxes
6. ROCm #5643 hipBLASLt fallback on gfx1151 (ROCm 7.1) — https://github.com/ROCm/ROCm/issues/5643
7. llama.cpp #13565 HIP poor perf on Strix Halo; ROCBLAS_USE_HIPBLASLT=1; VMM: no — https://github.com/ggml-org/llama.cpp/issues/13565
8. strixhalo.wiki AI Capabilities Overview — https://strixhalo.wiki/AI/AI_Capabilities_Overview
9. strixhalo.wiki llamacpp-with-ROCm — https://strixhalo.wiki/AI/llamacpp-with-ROCm
10. soothill: DeepSeek V4 Flash 97 GiB ROCm vs Vulkan on Strix Halo (2026-08-09) — https://www.soothill.io/blog/2026-08-09/deepseek-v4-flash-vulkan-rocm-strix-halo/
11. bkpaine: tuned HIP vs Vulkan on Strix Halo (2026-07) — https://medium.com/@bkpaine1/i-tuned-llama-cpp-33d68b1c851d
12. llama.cpp discussion #10879 (same-box Vulkan vs ROCm UMA entry, 2026-08) — https://github.com/ggml-org/llama.cpp/discussions/10879
13. LocalAI PR #9229 Strix Halo ROCm doc (env set, kernel params, GGML_CUDA_ENABLE_UNIFIED_MEMORY trap) — https://github.com/mudler/LocalAI/pull/9229
14. kernel docs: amdgpu module parameters (current; gttsize deprecated) — https://docs.kernel.org/gpu/amdgpu/module-parameters.html
15. kernel docs 6.10: gttsize default 1/2 RAM min 3 GB — https://docs.kernel.org/6.10/gpu/amdgpu/module-parameters.html
16. kernel docs v5.11: GEM domains; APU VRAM = BIOS carve-out; lockup_timeout defaults — https://www.kernel.org/doc/html/v5.11/gpu/amdgpu.html
17. amd-gfx 2025-01: mark amdgpu.gttsize deprecated, use ttm.pages_limit — https://lists.freedesktop.org/archives/amd-gfx/2025-January/118863.html
18. amd-gfx 2025-06: make compute timeouts consistent — https://lists.freedesktop.org/archives/amd-gfx/2025-June/126586.html
19. kernel docs v5.14: lockup_timeout — https://www.kernel.org/doc/html/v5.14/gpu/amdgpu.html
20. ollama #17870 gfx1151 ring timeout/DeviceLost long prefill; num_batch=128; 2000 ms claim — https://github.com/ollama/ollama/issues/17870
21. llama.cpp #21724 Vulkan DeviceLost on AMD APUs (job timeout; nodes_per_submit) — https://github.com/ggml-org/llama.cpp/issues/21724
22. llama.cpp PR #24872 allow reducing graph submission batches (merged 2026-06-24) — https://github.com/ggml-org/llama.cpp/pull/24872
23. kyuz0 toolboxes #95 MiniMax ~80 GB crash on Strix Halo (gttsize=122880, --no-mmap, BO_VA -12) — https://github.com/kyuz0/amd-strix-halo-toolboxes/issues/95
24. halo-box/strix-llama.cpp README (BIOS+gttsize+ttm.pages_limit guidance; HIP_LAUNCH_BLOCKING; env knobs) — https://github.com/halo-box/strix-llama.cpp
25. Xolotl docs/STRIX_HALO.md (ROCm 7.14.1 gfx1151 recipe; carve-out+GTT memory accounting) — https://github.com/Indras-Mirror/Xolotl/blob/main/docs/STRIX_HALO.md
26. llama.cpp PR #26081 default load-mode auto avoids mmap on iGPUs (merged 2026-08-11) — https://github.com/ggml-org/llama.cpp/pull/26081
27. llama.cpp #29455 Vulkan startup crash after #26081 (git-bisect confirmed; open 2026-10-09) — https://github.com/ggml-org/llama.cpp/issues/29455
28. ollama #17748 780M Vulkan regression (vendor bump past b10380) — https://github.com/ollama/ollama/issues/17748
29. ollama #18272 66 GB model Vulkan iGPU crash (Renoir) — https://github.com/ollama/ollama/issues/18272
30. llama.cpp PR #28326 disable lazy tensor loading by default on iGPUs (merged 2026-09-08) — https://github.com/ggml-org/llama.cpp/pull/28326
31. llama.cpp #20354 Vulkan missing GATED_DELTA_NET shader (GLA op added 2026-08-04) — https://github.com/ggml-org/llama.cpp/issues/20354
32. cephalochromoscope.net Metal run log (flash-next; fused top-k warnings non-fatal) — LOW CONFIDENCE — https://cephalochromoscope.net/cd314ede-9350-474c-b699-b7f2ad3adcd6
33. llama.cpp #27797 qwen4exp '//////' on gfx1151 → GGML_CUDA_ENABLE_UNIFIED_MEMORY (HIP); PR #27902 — https://github.com/ggml-org/llama.cpp/issues/27797
34. llama.cpp discussion #28248 RFC moe-expert-cache measured on qwen4exp UD-Q3_K_XL — https://github.com/ggml-org/llama.cpp/discussions/28248
35. llama.cpp #30987 flash-next -ncmoe GTT OOM (load-mode none → CPU experts consume GTT; buffer split log) — https://github.com/ggml-org/llama.cpp/issues/30987
36. llama.cpp #27306 draft-mtp DeviceLost during prompt on gfx1151 (open) — https://github.com/ggml-org/llama.cpp/issues/27306
37. llama.cpp PR #29761 Qwen4Exp: add MTP (merged 2026-10-01, b11386) — https://github.com/ggml-org/llama.cpp/pull/29761
38. llama.cpp PR #28901 qwen4exp: add hc ops (merged 2026-09-16; sidecar layout change) — https://github.com/ggml-org/llama.cpp/pull/28901
39. llama.cpp PR #27742 model: add Qwen3.8-Flash-Next (qwen4exp) (merged 2026-08-27) — https://github.com/ggml-org/llama.cpp/pull/27742
40. llama.cpp #27360 Vulkan/RADV 680M load-mode auto regression; mmap fixes; gfx1151 analysis (--no-host table, Mesa domain mapping, fit mis-accounting) — https://github.com/ggml-org/llama.cpp/issues/27360
41. llama.cpp #15009 Strix Halo ctx limit; 0cc4m: no Vulkan buffers > 4 GiB — https://github.com/ggml-org/llama.cpp/issues/15009
42. llama.cpp discussion #27950 (KYmidnight 90 GiB mmap/124 GB GTT Vulkan; drluoto ROCm→Vulkan; olliehm Windows; PLE/maxStorageBufferRange; checkpoints) — https://github.com/ggml-org/llama.cpp/discussions/27950
43. flueben/strix-halo-llama-fix (HIP page-fault → Vulkan; Mesa 25.2.8/kernel 6.17) — https://github.com/flueben/strix-halo-llama-fix
44. llama-swap unified runtime.Dockerfile (runtime-vulkan: ubuntu 24.04 + mesa-vulkan-drivers) — https://github.com/mostlygeek/llama-swap/blob/main/docker/unified/runtime.Dockerfile
45. strix-halo-guide (BIOS UMA 512 MB; gttsize=131072 ttm.pages_limit=31457280; iommu caveat) — https://hogeheer499-commits.github.io/strix-halo-guide/
46. yandaq/qwen38-flash-next-strix-halo (2 GB UMA + 104 GB GTT via ttm.pages_limit; Ubuntu 26.04 kernel 7.0.0-29) — https://github.com/yandaq/qwen38-flash-next-strix-halo
47. drluoto strix-halo-flash-next-vulkan.md (working recipe: -lm dio, 262k, checkpoints, Mesa 26.0.3) — https://github.com/drluoto/llama.cpp/blob/strix-halo-vulkan/docs/strix-halo-flash-next-vulkan.md
48. Nathanw1014/strix-halo-llamacpp (flash-next Q3 flags: mmap --no-host --fit off; FA/MoE fixes) — https://github.com/Nathanw1014/strix-halo-llamacpp
49. llama.cpp PR #28501 raise hoisted row-id limit to 512 experts (merged 2026-09-18) — https://github.com/ggml-org/llama.cpp/pull/28501
50. r/StrixHalo: stock llama.cpp underuses the hardware; fork landscape — https://www.reddit.com/r/StrixHalo/comments/1wafy3w/for_strix_halo_official_llamacpp_isnt_ideal_and
51. Local AI Infrastructure Lab: Memory, Vulkan and AMD Strix Halo (vm_validate/CS pairs; residence vs submission observations) — https://deshimarusakaguchi.com/lab/local-ai-cluster/memory-vulkan-strix-halo/
52. agledger: gpt-oss-120b 128k on Strix Halo (ring-watchdog DeviceLost at >80k prefill; -ub 512 stable) — https://agledger.ai/blog/gpt-oss-120b-128k-context-strix-halo/
53. llama.cpp PR #27836 qwen4exp NextN/MTP draft head (unsloth recommended regime; flobob45 gfx1151 Vulkan UD-Q3_K_XL validation) — https://github.com/ggml-org/llama.cpp/pull/27836
54. EasiiX/Qwen3.8-Flash-Next-MTP-Strix-Halo-GGUF (deprecated pre-#28901 sidecar refused by current builds; EngramHalo fork) — https://huggingface.co/EasiiX/Qwen3.8-Flash-Next-MTP-Strix-Halo-GGUF
55. agentionai/Qwen3.8-Flash-Next-MTP-Q8_0-GGUF (needs b11386+; 2026-10-05 upstream tensor names) — https://huggingface.co/agentionai/Qwen3.8-Flash-Next-MTP-Q8_0-GGUF
56. unsloth/Qwen3.8-Flash-Next-GGUF MTP/README.md (MTP support paths at that rev) — https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/raw/38bb39ee97821de2c9009abb7e93950eec396e66/MTP/README.md
57. r/LocalLLM: qwen4exp architecture facts + engine gap (512 experts/10 active, GDN+QSA hybrid, ~51B n-gram table, 262K ctx) — https://www.reddit.com/r/LocalLLM/comments/1w1gvqu/qwen38flashnext_qwen4exp_llamacpp_isnt_ready_for
