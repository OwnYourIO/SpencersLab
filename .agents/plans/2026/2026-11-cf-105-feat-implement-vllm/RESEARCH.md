# RESEARCH — cf-105 "Implement vLLM"

Deep-research summaries per ask (storm method, `global-searxng` + `webfetch`, no repo
changes). Everyone reads this at run start. Citation keys `[n]` resolve in the
per-section source lists. All web evidence accessed **2026-11-04** unless stamped
otherwise; publication/update dates given per source.

---

## R1 — vLLM serving a Qwen3-27B-class dense model on this lab's AMD hardware

### TL;DR

- **Both chips are officially supported today**: gfx1201/R9700 (RDNA 4) and gfx1151/8060S
  (RDNA 3.5) are on vLLM's AMD GPU list [1], on AMD's validated vLLM pages [12], and the
  official `vllm/vllm-openai-rocm` image ships device kernels for both [3]. No
  `HSA_OVERRIDE_GFX_VERSION` is needed for either chip anymore [13][14].
- **The current image is `vllm/vllm-openai-rocm:v0.33.0-rocm100`** (= `:latest`), ~18 GB,
  ROCm 10.0 SDK + PyTorch 2.13.0, Python 3.12, amd64, pushed 2026-11-02 [2].
- **On the 8060S only Q4-class weights fit a 32 GB budget** (BF16 55.6 GiB and stock FP8
  ~28.5 GiB leave no KV headroom; gfx1151 has no native FP8 [16]). Q4 + FP8 KV makes
  **~4×100k or 1×256k possible but not 3–4×256k** (4×256k = 31.2 GiB of KV alone) [5][19].
- **Expected speed**: 8060S decode ceiling ≈16 tok/s (Q4, 256 GB/s) — below today's
  llama.cpp+MTP 11.9–15.4 tok/s single-stream, and vLLM MTP is "under development" on AMD
  [9][13][18]; R9700 ceiling ≈40 tok/s, measured vLLM 32B-FP8 ≈27 tok/s (1-stream, eager)
  on 2×R9700 [20].
- **Verdict: conditional GO on the R9700 (gfx1201); MARGINAL on the 8060S.** The stated
  3–4×256k target does not fit any single 32 GB card. Top risks: KV physics, 8060S RAM
  coexistence (Strata 116 Gi limit), RDNA-vLLM software maturity (no MTP/AITER on gfx11x,
  FP8-WMMA partial on gfx1201 with NaN graph-capture bug → `--enforce-eager`).

### Q1 — ROCm support status for gfx1201 and gfx1151

**Officially supported (both), with different maturity:**

- **gfx1201 / RDNA 4 (RX 9070 class, R9700)**: listed in vLLM's GPU requirements
  ("Radeon RX 9000 series (gfx1200/1201)") [1]; AMD's AI-ecosystem page lists RX 9070 XT /
  9070 GRE / 9070 / R9700 / R9700S (all gfx1201) against vLLM 0.27 (ROCm 10.0) and 0.29
  (ROCm 10.1), ROCm 10.1.0 dated 2026-08-26 [12][11]. The official rocm100 image compiles
  device kernels for gfx1200 **and** gfx1201 [3]. History: ROCm 7.2 (Jan 2026) made RDNA4
  first-class [13]; a rocBLASLt `gfx1200.dat`-lookup bug SIGKILLed gfx1201 model loads in
  ROCm ≤7.2.3 (ROCm/ROCm#5812; `HSA_OVERRIDE_GFX_VERSION=12.0.1` was confirmed by AMD to be
  not a proper fix; fixed in ROCm 7.2.4, May 2026) [14][28]. **The FP8 performance path is
  still not fully upstream**: issue vllm-project/vllm#28649 (open) tracks it — native FP8
  WMMA works for tuned shapes only, many shapes silently FP32-dequant, and there is a
  HIP-graph-capture NaN bug under batched FP8 that `--enforce-eager` eliminates (0% NaN at
  concurrency 96) [20][21].
- **gfx1151 / RDNA 3.5 (Strix Halo, Radeon 8060S)**: listed in vLLM's GPU requirements
  ("Ryzen AI MAX / AI 300 Series (gfx1151/1150)", "requires ROCm 7.0.2 or above") [1]; AMD's
  page lists 8060S (Ryzen AI Max+ 395/392/388) [12]; ROCm 10.1.0 matrix supports Strix Halo
  with the **inbox kernel driver** on Ubuntu 24.04.5/26.04.1 [11]. Community toolboxes prove
  stock-ish vLLM runs on it: kyuz0's `vllm-therock-gfx1151` (ROCm 10.0 + latest stable
  vLLM, AITER patches) [16] and asf0's `strix-vllm` fork (ROCm 10.1, GDN KV-subpools,
  Qwen3.8 models) [23]. Gaps: **gfx1151 has no native FP8** — stock vLLM rejects FP8
  checkpoints with "Failed to find a kernel that can implement the ScaledMM linear layer"
  [16]; AITER C++/ASM kernels don't work on gfx11x and the broad `VLLM_ROCM_USE_AITER`
  toggle must stay off (patches guard MoE/FP8/RMSNorm paths) [16]; AITER in the official
  image is prebuilt **only for gfx942/950 (CDNA)** [3].

**HSA_OVERRIDE_GFX_VERSION today**: an unsupported-card workaround (e.g. gfx1031/1032 →
`10.3.0`, 780M gfx1103 → `11.0.0`) [13]. **Not applicable to gfx1151 or gfx1201 in current
ROCm (7.2+/10.x)** — both ship native kernels via TheRock per-arch wheels
(`torch[device-gfx1151]`, `torch[device-gfx1201]`) [12][13]. Historical context: gfx1151
was absent from upstream ROCm through 6.x/early 7.x (TheRock nightly was the only path)
[bitserv-ai/_gfx115x_, search snippet, 2026-11-04]; gfx1151-specific LocalAI/Ollama reports
used `11.0.0`/`11.5.1` overrides pre-that (mudler/LocalAI#5822; runaihome fix guide).

### Q2 — Which container image

**Use the upstream official image** (vLLM docs deprecate AMD's `rocm/vllm` + `rocm/vllm-dev`
in favor of it, dated 2026-01-20) [1]:

| Image / tag | ROCm / stack | Size | Notes |
|---|---|---|---|
| `vllm/vllm-openai-rocm:v0.33.0-rocm100` (= `:latest`, `:latest-rocm100`) | ROCm 10.0.0 (TheRock pip SDK), PyTorch 2.13.0+rocm10.0.0, Python 3.12, AITER v0.1.27 (CDNA prebuilds), Triton 3.8.0 (ROCm fork), MORI v1.2.3 | **18.04 GB** (digest `sha256:4fcd39b7…fba`, amd64, pushed 2026-11-02) | current stable; device kernels for gfx90a/942/950/1100/1101/1200/1201/1150/1151 [3] |
| `vllm/vllm-openai-rocm:nightly-rocm100` | same stack, dev branch | 8.98 GB (multi-arch index) | 2026-11-03 [2] |
| `vllm/vllm-openai-rocm:v0.33.0-rocm72` (= `:latest-rocm72`) | legacy ROCm 7.2, system-SDK style | 11.76 GB | "no longer updated" [1][2] |
| `rocm/vllm:rocm10.1.0_ubuntu24.04_py3.14-pytorch_2.13.0_vllm-0.29.0` | ROCm 10.1.0, **py3.14** | n/m | AMD's own get-started recommendation (AMD-validated line lags upstream: 0.29 vs 0.33) [12] |
| `kyuz0/vllm-therock-gfx1151:latest` | ROCm 10.0 + latest stable vLLM + gfx1151 AITER patches | n/m | community, Strix-focused; `rocm-smi` must print the 8060S as acceptance test [16] |
| `ghcr.io/asf0/strix-vllm:latest` | ROCm 10.1, gfx1151 fork w/ GDN KV subpools + Qwen3.8 support | n/m | community; needed only if serving Qwen3.8-Flash-Next-class models [23] |

Image facts that matter here: ROCm 10.0 images use **zstd-compressed layers — need Docker
≥23 / containerd ≥1.5** (node runs containerd 2.3.4 → fine) [1]. ROCm prebuilt wheels are
**Python 3.12-only** (a mismatched Python silently pulls the CUDA wheel) [1]. The upstream
image carries a custom-built ROCr/CLR (multi-stream perf fix) and
`ROCPROFILER_QUEUE_INTERPOSITION=0` env [3]. AMD's validated vLLM 0.29/0.27/0.23 lines
ship per-arch torch wheels from `stable.repo.amd.com/rocm/whl-next/`
(`torch[device-gfx1151]==2.13.0+rocm10.1.0`, `torch[device-gfx1201]`, …) [12].
**Renovate fit**: the upstream tags are semver-shaped (`v0.33.0-rocm100`) — a scoped
packageRule (pattern on the `-rocm100` family, cf. the lab's `unified-vulkan-<N>` precedent
in EXPLORE §8.2) can track them.

### Q3 — Model/quant feasibility on a 32 GB budget

**The model's actual architecture (fetched live from HF, 2026-11-04)**: `Qwen3.8-27B` is
`model_type: qwen3_5` — a **hybrid**: 64 layers = 48 GDN (gated DeltaNet linear attention)
+ 16 full-attention (`full_attention_interval: 4`), 24 query heads / **4 KV heads /
head_dim 256**, GDN 16×128 key + 48×128 value state in **float32**, `mtp_num_hidden_layers:
1` (MTP head), `max_position_embeddings: 262144`, bf16, vocab 248320, and a 27-layer
vision tower (`language_model_only` field present) [19]. vLLM supports this family
(Qwen3.5/3.6 GDN hybrid + MTP recipe; verified on MI300X/MI355X/H200, **not on RDNA**)
[9]. The hybrid layout is the whole ballgame for KV math: only the 16 full-attention
layers grow per token.

**KV cache math (derived from [19])**:
- Full-attention KV per token: 2 × 16 × 4 × 256 × 2 B = **64 KiB/token (bf16)**; with
  `--kv-cache-dtype fp8` (= `fp8_e4m3`, the ROCm-supported KV dtype) = **32 KiB/token** [5].
- GDN recurrent state: **144 MiB per sequence, fixed** (not per token); with MTP (k=2) one
  state per verification position is held (~3× ≈ 0.47 GB/seq — asf0's fork collapses it to
  a single state, ~470 MB saved) [19][23].

**What fits in 32 GiB (weights + ~2 GiB vLLM workspace/activations + 4×144 MiB GDN):**

| Weights | Size | KV space left | fp8 KV capacity | bf16 KV capacity |
|---|---|---|---|---|
| BF16 | 55.6 GiB | — | **doesn't fit** | — |
| FP8 (W8A8) | ~28.5 GiB (est.) | ~0.9 GiB | ~29k tok | ~15k tok — useless |
| Q8_0 GGUF | 26.63 GiB [18] | ~2.8 GiB | ~91k tok (1 session) | ~45k |
| Q6_K GGUF | ~20–21 GiB (est., scaled from [18]) | ~8.9 GiB | ~292k tok (2×100k + 2×45k) | ~146k |
| Q4_K GGUF | ~16 GiB | ~13.4 GiB | **~439k tok (≈4×100k, right at the edge)** | ~220k (2×100k) |

Target check (fp8 KV): 3×100k = 9.2 GiB, **4×100k = 12.2 GiB (fits under Q4 only)**,
1×256k = 7.8 GiB (fits under Q4/Q6/Q8-ish), **3×256k = 23.4 GiB, 4×256k = 31.2 GiB —
KV alone exceeds the whole card** (any weight format included). So the card's stated
target (3–4 sessions @ 100k–256k) is **not physically achievable at 256k on any single
32 GB card**; at 100k it is achievable with Q4 weights + fp8 KV, with the pool shared
across 3–4 sequences (vLLM preempts/recomputes when the pool exhausts).

**Quant format availability in vLLM on AMD (official matrix, updated 2026-11-03)** [4]:
FP8 W8A8 (llm-compressor) ✅, **GGUF ✅ (but "highly experimental and under-optimized… a
way to reduce memory footprint", moved to the OOT `vllm-gguf-plugin` — not in the stock
image)** [6], AMD Quark ✅ (FP8 weight/activation/KV toolkit) [4];
**AWQ ❌, GPTQ ❌, Marlin ❌, bitsandbytes ❌, INT8 W8A8 ❌** [4]. On gfx1151 specifically,
stock vLLM **rejects FP8 checkpoints outright** (no ScaledMM kernel) [16] — so on the
8060S the realistic 32 GB paths are **GGUF Q4/Q6 via the OOT plugin** (needs a container
overlay) or a larger GTT allocation (see open questions). The lab's existing rungs
(q4/q6/q8 GGUF on the 500 GiB PVC) are directly reusable in principle [18].

**Knobs that control this** (engine-args reference, fetched 2026-11-04) [8]:
- `--gpu-memory-utilization` (a.k.a. `--device-memory-utilization`): fraction of *device*
  memory the engine may use (weights + KV + workspace). Default 0.92 (1.0 with extensible
  KV). **Per-instance only — it does not know about co-tenants**; on the 8060S "device
  memory" is the GTT carve-out of system RAM shared with the OS and every other engine, so
  this is the single most dangerous knob there.
- `--kv-cache-memory-bytes`: explicit KV pool size in bytes; overrides
  `gpu-memory-utilization` — the precise lever for "I have N GiB left after weights".
- `--kv-cache-dtype fp8`: `fp8_e4m3` on ROCm [5]; halves KV vs bf16.
- `--max-model-len`: caps per-sequence length; `-1`/`auto` sizes to what fits.
- `--max-num-seqs`: max concurrent sequences admitted (the "3–4 parallel sessions" knob).
- `--max-num-batched-tokens` (+ chunked prefill, on by default in V1): token budget per
  engine step — controls prefill/decode interleaving and TTFT under load.
- `--enable-prefix-caching` (shared system prompts across sessions hit the cache),
  `--block-size`, `--enable-extensible-kv-cache` (ROCm + V2 runner: sizes KV from measured
  free memory after warmup).

**iGPU caveat (stated explicitly)**: on the 8060S, "VRAM" = LPDDR5X shared with the CPU,
OS, Strata's page-locked arenas, and the llama.cpp trio (EXPLORE §8.6). `--gpu-memory-
utilization 0.92` of a 32 GiB GTT = 29.4 GiB of *system RAM* committed, on a node where
the Strata pod already carries a 116 Gi memory **limit** (actual arena residency
unverified). vLLM will OOM-kill or swap-thrash the whole node if the budget is wrong —
there is no discrete-VRAM cushion. Strix Halo boxes can allocate far more than 32 GB to
the iGPU via GTT (up to ~96–110 GB on 128 GB systems) [13], so the effective budget is an
operator-verifiable fact, not a constant (open question 1).

### Q4 — Expected throughput vs the llama.cpp baseline

**Decode is memory-bandwidth-limited.** Bandwidth ceilings (vendor bandwidth ÷ bytes
swept per token) and measurements:

| Hardware | Bandwidth | 27B-class Q4 ceiling (16 GiB) | Measured (llama.cpp) | Measured (vLLM) |
|---|---|---|---|---|
| 8060S (gfx1151, ~256 GB/s LPDDR5X) [13] | ~256 GB/s | **~16 tok/s** | Q8 7.53 → +MTP 11.87 (60.8% draft accept) → Q4+MTP **15.35** tok/s single-stream [18] | no public 27B number; 14B-AWQ peak *batched* 159.9 tok/s aggregate (200 ShareGPT prompts, in+out tokens) [17] |
| R9700 (gfx1201, 640 GB/s GDDR6) [15] | 640 GB/s | **~40 tok/s** | 27B dense Q4_K_M **29–33 tok/s** [15] | 32B-FP8 on 2×R9700 TP=2, eager: c=1 **25.8–29.1**, c=3 **71–85**, c=8 **182–204** tok/s aggregate (Sep 2026, ROCm 10.1 nightly + source build) [20]; 9B Q6 single-stream 48 tok/s on RX 9070 XT, ROCm 7.2, Mar 2026 (vs llama Vulkan 62 — pre-FP8-fix era) [22] |

Readings for the plan:
- **vs the ~50 tok/s bar**: that bar is the *Flash* model (MoE, ~13B active) on Strata — a
  different class. Dense 27B single-stream **cannot hit 50 tok/s on either card** (ceilings
  16 / 40). On the R9700 vLLM lands at parity with llama.cpp (~30 tok/s); on the 8060S
  vLLM is likely *slower* single-stream than the current llama.cpp+MTP (11.9–15.4 tok/s)
  because **MTP speculative decoding on AMD is "under development" in vLLM** [9] and the
  GDN path is less tuned than llama.cpp's (asf0's fork exists precisely to close this gap
  [23]).
- **Where vLLM genuinely wins**: continuous batching of 3–4 concurrent sessions (aggregate
  throughput under load, measured pattern: ~3× at c=3, ~7× at c=8 [20]), chunked prefill
  (TTFT stays bounded while decodes proceed), prefix caching across shared agent system
  prompts, PagedAttention preemption instead of hard OOM, OpenAI-compatible API +
  `/metrics`, and (on the R9700) sleep mode for time-sharing (see Q5).
- **Where it may lose on a unified-memory iGPU**: single-stream decode (no MTP, Triton/GDN
  kernel tuning lag, AITER disabled [16]); prefill on 8060S (40-CU iGPU is compute-poor —
  slb350 measured TTFT 131.5 s at 128K → 320.7 s at 256K context even with llama.cpp
  [18]); and any configuration where the 256 GB/s ceiling means 4 concurrent sessions
  share ~16 tok/s aggregate (~4 tok/s each).
- **RDNA4-specific caveat**: the FP8 numbers above assume `--enforce-eager` (graph-capture
  NaN bug) [20]; with graphs restored and shape tuning completed, the community estimates a
  further 25–60%+ decode gain [20]. BF16 weights avoid the FP8 path entirely but need 2×
  the VRAM.

### Q5 — Kubernetes deployment-shape facts

- **Device plugin (already deployed)**: the ai-gpu node runs
  `default/amd-gpu-device-plugin-daemonset`, image
  `docker.io/rocm/k8s-device-plugin:1.31.0.9` (the official ROCm plugin, live probe
  2026-11-04) [27][24]. It exposes **`amd.com/gpu`** (count-only: `2` on ai-gpu — cannot
  name gfx1201 vs gfx1151; chip targeting stays env-based, the lab's established pattern
  via `rocrVisibleDevices`, EXPLORE §8.7). Plugin pod is non-privileged (drops ALL caps);
  privileged mode is only needed if device *health checks* are enabled [24]. It mounts
  `/var/lib/amd-metrics-exporter/` but **no metrics exporter is running** there (R5 gap).
- **Pod shape (official, non-privileged)**: vLLM's own K8s AMD example [10] —
  `resources.limits.amd.com/gpu: "1"`; `securityContext: {seccompProfile: Unconfined,
  runAsGroup: 44 (video), capabilities.add: [SYS_PTRACE]}`; `hostIPC: true`; shm
  `emptyDir {medium: Memory, sizeLimit: 8Gi}` at `/dev/shm`; probes on `httpGet
  /health:8000` with generous `initialDelaySeconds`. The docker-equivalent flags the
  official images are tested with: `--group-add=video --cap-add=SYS_PTRACE
  --security-opt seccomp=unconfined --device /dev/kfd --device /dev/dri --ipc=host`
  [1][12]. Full sample tree: `ROCm/k8s-device-plugin/example/vllm-serve` [10].
  **No privileged requirement in the non-privileged path** — the upstream pod example [10]
  needs neither privileged mode nor IPC_LOCK/SYS_RESOURCE; the lab's documented strata
  fallback (`amd.com/gpu` + IPC_LOCK/SYS_RESOURCE non-privileged) remains the in-repo
  pattern (EXPLORE §8.7), and strata's privileged+hostPath `/dev/kfd`,`/dev/dri` remains
  the accepted deviation for the device-injection path.
- **shm sizing**: vLLM needs shared memory for multi-process workers (the `--ipc=host` /
  `--shm-size` note in the docker docs [1]); TP=1 single-GPU serving works with the
  2–8 GiB class (strata uses 2 GiB [EXPLORE §1]), while the 2×R9700 community compose uses
  `shm_size: 32gb` [20] — size by TP/worker count, default to ≥8 GiB.
- **Gotchas specific to this cluster**:
  1. **zstd image layers** (ROCm 10.0 images) need containerd ≥1.5 — node has 2.3.4, OK [1].
  2. **18 GB pull** from Docker Hub on first deploy; pin digest per repo pinning law
     (EXPLORE §8.2) and keep renovate tracking the `-rocm100` tag family.
  3. **Long startup**: weight load + Triton JIT/warmup. AMD documents "significantly
     longer warmup times" on Radeon for vLLM v0.21.0–v0.25.0, fixed in ≥0.26 [12] (v0.33 is
     clear); k8s-side, set startupProbe `failureThreshold` high enough or the kubelet kills
     the pod mid-warmup with "KeyboardInterrupt: terminated" [10].
  4. **First-run kernel compilation**: persist `TRITON_CACHE_DIR` (and HF cache) on a
     PVC/emptyDir — the 500 GiB `llama-swap` PVC can host the weights mount [20][EXPLORE §1].
  5. **PyTorch allocator**: `PYTORCH_ALLOC_CONF=expandable_segments:True` is the community
     setting for ROCm fragmentation [20].
  6. **Chip selection**: with `amd.com/gpu: 1` the plugin injects *both* chips' devices;
     the pod must set the ROCR visible-devices env to pick one (strata precedent:
     `rocrVisibleDevices: "0"` = R9700, `"1"` = 8060S) (EXPLORE §1/§8.7; exact upstream
     env name in PyTorch-ROCm/TheRock to be confirmed — open question 4).
  7. **Coexistence lever**: `--enable-sleep-mode` ("only cuda and hip platforms are
     supported") [8] lets a vLLM pod on the R9700 offload weights to CPU when idle — the
     engine-side analog of llama-swap eviction, if the owner wants vLLM and Strata to
     time-share the R9700 (open question 6).
- **Host driver**: ROCm 10.1.0 matrix expects amdgpu 31.50.0/31.60.0 for RDNA4 desktop and
  the *inbox* kernel driver for Strix Halo APUs [11]; the ai-gpu host is openSUSE TW (not a
  listed ROCm distro — SLES is the nearest listed SUSE). Containerized TheRock mostly
  sidesteps distro support, but the **kernel amdgpu version on TW is the one unverified
  dependency** (operator `dmesg`/`modinfo` check — no exec tier in agent sessions).

### Q6 — Go/no-go verdict

**GO (conditional) on the R9700 (gfx1201)** — best fit: dedicated 32 GB GDDR6 @ 640 GB/s
(no system-RAM coexistence), official support [1][12][3]; 27B-class Q4 GGUF fits
comfortably (~13 GiB KV headroom), FP8 weights (~28.5 GiB est.) only with ~1.5 GiB left
for KV. ~30 tok/s single-stream (llama.cpp parity) and ~70–200 tok/s aggregate at 3–8
concurrent (32B-FP8, 2-card TP=2) [15][20]. Conditions: `--enforce-eager` until the graph-capture NaN bug clears upstream [20],
chip targeting via ROCR env, and a coexistence ruling with Strata (sleep mode vs arena
eviction) [8].

**MARGINAL GO on the 8060S (gfx1151)** — officially supported and runnable [1][12][16][23],
but: the only 32 GB weight path is **GGUF Q4 via the experimental OOT plugin** [4][6][16]
(no FP8/AWQ/GPTQ/bnb on AMD [4]; no native FP8 on gfx1151 [16]); no MTP on AMD [9] so
single-stream likely trails the llama.cpp+MTP it would replace (15.35 tok/s measured
[18] vs ~8–16 tok/s estimated); the RAM-coexistence budget is unverified (open questions
1/9). vLLM's value there is specifically the 3–4-session batched-scheduling story — if the
owner only wants 1–2 sessions on that card, llama.cpp stays the better engine.

**NO-GO as stated**: "3–4 parallel sessions at 100k–256k ctx" on one 32 GB card — 4×256k
needs 31.2 GiB of KV alone (fp8) [19-math]; 100k×3–4 fits only Q4+fp8KV, at the very edge
of 32 GiB. Re-scoped target: **R9700 (Q4+fp8KV): 2–3 sessions @ 64–100k, 1 @ up to 256k;
R9700 (FP8 weights): ~1–2 sessions @ 50–100k; 8060S (Q4+fp8KV): 2–4 sessions @ ~64–100k,
preemption when the pool fills.**

**Top 3 risks:**
1. **KV/weight physics vs the stated target** (above): every configuration that fits 32 GB
   leaves 256k-class multi-session serving impossible; mis-scoping this becomes a
   "vLLM is slow/OOMs" incident later.
2. **8060S system-RAM coexistence**: vLLM's `--gpu-memory-utilization` commits GTT-backed
   RAM that the OS, Strata (116 Gi *limit* pod) and the llama.cpp trio also claim; GTT
   allocation is unverified (could be 32 GiB or more — Strix Halo allows ~96–110 GB on
   128 GB boards [13]). A wrong budget destabilizes the whole node, not just vLLM.
3. **RDNA vLLM software maturity**: MTP "under development" [9]; AITER CDNA-only prebuilds
   + gfx1151 patch requirements [3][16]; gfx1201 FP8-WMMA partial with documented NaN /
   graph-capture failures and a 1-year-old open tracking issue (#28649, "still not
   reliably selected" as of 2026-10-20) [20][21]; GGUF path experimental + out-of-tree [6].
   Mitigation: pin one image tag + one env/config recipe, `--enforce-eager` on gfx1201,
   and treat the first deploy as a benchmark/acceptance run, not a service flip.

### Contradictions and how to weigh them

1. **AWQ/GPTQ on vLLM-AMD**: official matrix ❌❌ [4] vs kyuz0's "tested" AWQ-4bit/GPTQ
   models on gfx1151 [16][17] and an RDNA3 AWQ recipe in a third-party guide [13]. *Weigh*:
   the matrix governs stock vLLM — assume ❌; the community toolbox clearly loads those
   formats (likely via patched AITER/compressed-tensors paths). Do not build the plan on
   AWQ/GPTQ working in the official image.
2. **"FP8 ✅ on AMD GPU"** [4] vs **"gfx1151 has no native FP8, stock vLLM rejects FP8
   checkpoints"** [16] vs **gfx1201 FP8 partially tuned with dequant fallbacks** [20][21].
   *Weigh*: all true at different arch layers. FP8 W8A8 works where kernels exist — CDNA
   fully, RDNA4 partially (eager mode), RDNA3.5 not at all. gfx1151 ⇒ GGUF-only in
   practice.
3. **"Supported" gfx1201** [1][12] vs community "completely unstable… no stable release"
   (vllm#28649, Jul 2026) [20]. *Weigh*: "supported" = listed + loads + serves correctly
   (eager); performance/stability = community-patched and moving. Treat R9700 as
   supported-but-young, pin exact versions, benchmark on arrival.
4. **Image authority**: vLLM docs deprecate `rocm/vllm` (2026-01-20) [1] while AMD's own
   current AI-ecosystem page still leads with `rocm/vllm:rocm10.1.0…vllm-0.29.0` [12].
   *Weigh*: use the upstream official image (newer: v0.33.0/ROCm 10.0 vs AMD-validated
   0.29/ROCm 10.1); note AMD's validated vLLM line lags upstream stable, and the py3.14
   (AMD) vs py3.12 (upstream image) split — the lab image must be the upstream one.
5. **vLLM vs llama.cpp speed**: llama wins single-stream on RDNA4 today (48 vs 62, Mar
   2026 [22]; 15.35 MTP vs no-MTP on Strix [18][9]) while vLLM wins aggregate/batched
   (c=8 ≈ 7× c=1 [20]; 159.9 tok/s peak batched [17]). *Weigh*: they measure different
   axes; the 3–4-session card goal is exactly the axis vLLM wins.
6. **R9700 VRAM confusion risk**: RX 9070 class = 16 GB, but the **R9700 is 32 GB GDDR6**
   [15] (AMD datasheet, cited therein) — both node GPUs are "32 GB" cards with different
   physics (shared ~256 GB/s LPDDR5X vs discrete 640 GB/s GDDR6).

### Implications for the plan

- **Card choice (feeds OQ2)**: plan the vLLM 27B service **R9700-first**. The 8060S
  variant is only worth it for the batched-sessions story and only after the GTT/RAM
  headroom verification (open questions 1/9). Moving the 27B to vLLM-on-R9700 also *frees*
  the 8060S RAM for llama.cpp's flash-model duty.
- **Deployment shape (feeds OQ1)**: vLLM is a long-running OpenAI-compatible API server,
  not a process llama-swap swaps in/out — a **standalone `charts/vllm`** (own image pin,
  own probes, own PodMonitor) with the llama-swap **`peers`** hop in front for the unified
  `/v1` surface (EXPLORE §1/§8.9 pattern) is the cleaner fit than a strata-style second
  controller of the llama-swap Application. If the owner wants R9700 time-sharing with
  Strata, add `--enable-sleep-mode` as a values flag (hip-supported [8]).
- **Container**: upstream `vllm/vllm-openai-rocm:v0.33.0-rocm100` + digest pin + scoped
  renovate packageRule (tag family `-rocm100`). **Only if** the GGUF path is chosen on
  gfx1151 (or for reusing lab GGUFs): a `containers/vllm-rocm` overlay installing
  `vllm-gguf-plugin` (CI-primary build, `:main` until first `:v<run>`, per container
  rules) [6].
- **Engine recipe to bake into values**: `--language-model-only` (skip vision tower [9]),
  `--kv-cache-dtype fp8`, `--gpu-memory-utilization` or explicit `--kv-cache-memory-bytes`,
  `--max-num-seqs 3–4`, `--enable-prefix-caching`, `--max-model-len 131072` (start ≤100k;
  256k only single-session), `--enforce-eager` on gfx1201 [20], `VLLM_ROCM_USE_AITER=0` on
  gfx1151 [16], `PYTORCH_ALLOC_CONF=expandable_segments:True` [20], persisted
  `TRITON_CACHE_DIR`.
- **Acceptance = a benchmark run, not a lint**: on-target (operator-run; no exec tier):
  rocminfo agent list (gfx1201/gfx1151 detected), 1-token generation, 100k-prefill TTFT,
  3–4 concurrent 100k sessions aggregate tok/s, node RAM headroom (8060S case), and
  vLLM startup duration (probe sizing) [10][12].
- **Repo validation** (unchanged from EXPLORE §4): `helm lint`/`helm template`, trio
  greps, no `OVERRIDE_*` sentinels, per-directory pytest; no unit-test suite exists for
  engine behavior — the on-target smoke run *is* the test.

### Open questions (R1)

1. **GTT allocation on ai-gpu**: is the 8060S actually capped at 32 GiB, or can the
   ~128 GiB node expose more to the iGPU (Strix Halo supports ~96–110 GB on Linux) [13]?
   Operator: `rocminfo` vram limit / `dmesg | grep amdgpu` / BIOS setting. Changes the
   8060S weight-format ceiling (Q4-only vs Q8/FP8-feasible).
2. **Checkpoint for vLLM**: does an official FP8 safetensors of `qwen3.8-27b` exist (a
   Qwen3.6-27B-FP8 deployment is cited in [20]; the Qwen3.5/3.6 family ships official FP8
   checkpoints [9])? If not,
   GGUF Q4 via the OOT plugin is the only sub-FP8 fit on 32 GB — which forces the overlay
   container decision.
3. **Text-only serving**: serve with `--language-model-only` (the lab's usage is text; the
   config carries a 27-layer vision tower [19][9])? Confirm with the owner.
4. **Chip-targeting env in the ROCm 10 stack**: exact env name honored by
   PyTorch-ROCm/TheRock for single-chip visibility (`ROCR_VISIBLE_DEVICES` vs the lab's
   strata `rocrVisibleDevices` spelling) — confirm during the on-target smoke.
5. **Host driver version** (openSUSE TW amdgpu) vs ROCm 10.0/10.1 expectations [11] —
   operator `modinfo amdgpu | grep version` / `dmesg`.
6. **R9700 coexistence policy with Strata**: vLLM sleep-mode time-sharing vs Strata arena
   eviction vs R9700-exclusive-for-vLLM — owner ruling (OQ2 territory).
7. **Image choice**: upstream `v0.33.0-rocm100` (newest, py3.12) vs AMD-validated
   `rocm/vllm` 0.29/ROCm 10.1 (py3.14) vs community `asf0/strix-vllm` (ROCm 10.1, GDN
   subpools — only if Qwen3.8 GDN-specific vLLM fixes are needed) [12][2][23].
8. **Whether to ship a repo overlay container** (`containers/vllm-rocm`) for the GGUF
   plugin / env pins, vs running the stock image with values-only configuration.
9. **Strata's real arena RAM residency** (116 Gi is a *limit*; actual page-locked usage
   unmeasured) — determines the 8060S vLLM budget. Operator: `kubectl top pod` /
   cgroup memory.current.
10. **GDN SSM state dtype**: config says float32 (144 MiB/seq [19]); whether vLLM-ROCm
    allows fp16 SSM (halves it) — minor, check in the engine logs.

### Sources (R1)

All web sources accessed 2026-11-04 via `global-searxng`/`webfetch`; [27] is a live
read-only MCP probe (2026-11-04).

1. vLLM docs — Installation: GPU (AMD ROCm): https://docs.vllm.ai/en/latest/getting_started/installation/gpu/
2. Docker Hub API — `vllm/vllm-openai-rocm` tags (v0.33.0-rocm100, 18,038,402,058 B, digest sha256:4fcd39b758b660c4e9c345c021e2ea8f0ccdb31e3c32507d676cc3005ae83fba, pushed 2026-11-02): https://hub.docker.com/v2/repositories/vllm/vllm-openai-rocm/tags?page_size=100
3. vLLM `docker/Dockerfile.rocm_base` (main, REFRESH=2026-10-12; ROCM_SDK_VERSION=10.0.0, TORCH 2.13.0+rocm10.0.0, PYTORCH_ROCM_ARCH incl. gfx1200;gfx1201;gfx1150;gfx1151, AITER_ROCM_ARCH=gfx942;gfx950): https://raw.githubusercontent.com/vllm-project/vllm/main/docker/Dockerfile.rocm_base
4. vLLM docs — Quantization, supported-hardware matrix (page updated 2026-11-03): https://docs.vllm.ai/en/latest/features/quantization/
5. vLLM docs — Quantized KV Cache (updated 2026-11-02; `fp8_e4m3` on ROCm): https://docs.vllm.ai/en/latest/features/quantization/quantized_kvcache/
6. vLLM docs — GGUF (updated 2026-06-12; "highly experimental and under-optimized", OOT `vllm-gguf-plugin`): https://docs.vllm.ai/en/latest/features/quantization/gguf/
7. vLLM docs — FP8 W8A8 / llm-compressor (updated 2026-09-24; HW accel H100/MI300x, kernel-selection chain): https://docs.vllm.ai/en/latest/features/quantization/llm_compressor/fp8/
8. vLLM docs — Engine Arguments (gpu-memory-utilization, kv-cache-memory-bytes, max-model-len auto, max-num-batched-tokens, max-num-seqs, chunked-prefill, prefix-caching, extensible KV cache on ROCm, sleep mode cuda+hip): https://docs.vllm.ai/en/latest/configuration/engine_args/
9. vLLM Recipes — Qwen3.5 & Qwen3.6 (updated 2026-04-15; GDN hybrid, MTP, `--language-model-only`, "MTP-1 speculative decoding for AMD GPUs is under development", GDN capture-size gotcha): https://docs.vllm.ai/projects/recipes/en/stable/Qwen/Qwen3.5.html
10. vLLM docs — Using Kubernetes (updated 2026-07-16; AMD pod example: seccomp Unconfined, runAsGroup 44, SYS_PTRACE, hostIPC, shm 8Gi, amd.com/gpu:1; startup-probe "KeyboardInterrupt" troubleshooting; links `ROCm/k8s-device-plugin/example/vllm-serve`): https://docs.vllm.ai/en/stable/deployment/k8s/
11. ROCm 10.1.0 compatibility matrix (2026-08-26; R9700 gfx1201 + 8060S gfx1151 entries, driver 31.50/31.60, APU inbox driver): https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html
12. AMD ROCm AI Ecosystem — vLLM inference and serving on ROCm (validated vLLM 0.29/ROCm 10.1.0, 0.27/10.0.0, 0.23/7.14.x; device lists incl. R9700 + Ryzen AI Max; per-arch torch wheels; known issues: tensorizer 2.12.1 bump, Radeon warmup v0.21–v0.25 fixed in ≥0.26; rocm/vllm get-started): https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/inference/vllm.html
13. Local AI Master — AMD ROCm Local LLM Setup 2026 (updated 2026-11-02; ROCm release timeline 7.2→10.1, TheRock since 7.14, HSA_OVERRIDE only for unsupported cards, Strix Halo ~256 GB/s + GTT up to ~96–110 GB, RDNA3 no-FP8 / RDNA4 FP8-HW): https://localaimaster.com/blog/amd-rocm-local-llm-setup
14. RunAIHome — ROCm 7.2 on Ubuntu 2026 (2026-06-04; gfx1201 rocBLASLt SIGKILL bug, fixed 7.2.4; override not a proper fix): https://runaihome.com/blog/rocm-7-ubuntu-local-llm-setup-2026/
15. RunAIHome — Radeon AI PRO R9700 guide (2026-07-23, prices upd. 2026-10-28; 32 GB GDDR6 640 GB/s 300 W; llama.cpp 27B dense Q4 29–33 tok/s; MoE 127–156 tok/s): https://runaihome.com/blog/amd-radeon-ai-pro-r9700-local-ai-hardware-guide-2026/
16. kyuz0 — amd-strix-halo-vllm-toolboxes README (gfx1151 no native FP8, stock vLLM rejects FP8, VLLM_STRIX_FP8_TRITON=1 + PolyForm-Noncommercial caveat, AITER gfx1x patches, container flags, image channels): https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes
17. kyuz0 Strix Halo benchmark JSON — Qwen3-14B-AWQ, TP1, 200 ShareGPT prompts: 159.9 tok/s peak batched (in+out tokens): https://raw.githubusercontent.com/kyuz0/amd-strix-halo-vllm-toolboxes/main/benchmarks/2025-12/benchmark_results/Qwen_Qwen3-14B-AWQ_tp1_throughput.json
18. slb350 — Strix Benchmarks (Ryzen AI MAX+ 395 / 8060S / 128 GB UMA; Qwen3.8-27B Q8_0 26.63 GiB + MTP drafter 2.95 GiB; TG 7.53 → 11.87 (MTP n=3, 60.84% accept) → 15.35 (Q4+MTP) tok/s; Flash-Next 128K/192K/256K sweep 31.68/29.09/28.49 tok/s, TTFT 131.5→320.7 s): https://slb350.github.io/strix-benchmarks/
19. Qwen3.8-27B `config.json` (HF; qwen3_5, 64 layers = 48 GDN + 16 full-attn, 24q/4kv heads, head_dim 256, GDN 16×128/48×128 fp32 state, mtp 1, 262144 max, vision tower 27 layers, bf16): https://huggingface.co/Qwen/Qwen3.8-27B/raw/main/config.json
20. vllm-project/vllm issue #28649 — "[Feature] upstream this gfx1201/RDNA4 FP8 patch" (OPEN; accessed 2026-11-04; Nov 2025 patch 52→85 tok/s Qwen3-30B; Feb 2026 "not fully merged"; Jul 2026 HIP-graph NaN + `--enforce-eager` 0% at c=96, eager FP8 +11% over FP16; Sep 2026 2×R9700 TP2 32B-FP8 eager c=1/3/8 = 25.8–29.1/71–85/182–204 tok/s; ROCm/aiter#5286 split-K NaN; Oct 2026 "still not reliably selected… 25–60%+ decode improvement" pending; jptissot 27B-FP8 TP=2 200k-ctx compose w/ shm 32 gb, expandable_segments, VLLM_ROCM_* envs; aml731/vllm-aiter image): https://github.com/vllm-project/vllm/issues/28649
21. vLLM forum — "Native FP8 WMMA Support for AMD RDNA4 (RX 9070 XT / R9700) in vLLM" (2025-11-13; patch mechanics: gfx1201→MI350X AITER arch mapping, `VLLM_ROCM_USE_AITER=0`, 16 kernel-config JSONs, device 0x7551; Triton auto-lowers FP8 to WMMA `v_wmma_f32_16x16x16_fp8_fp8`): https://discuss.vllm.ai/t/native-fp8-wmma-support-for-amd-rdna4-rx-9070-xt-r9700-in-vllm/1900
22. digtvbg — "Local LLM Inference on AMD RX 9070 XT — Vulkan vs ROCm" (2026-03-22; 9B Q6_K single-stream: vLLM ROCm 7.2 48 tok/s vs llama-server Vulkan 62 tok/s; FP32-dequant cause; issue #28649 cited): https://digtvbg.com/blog/llama-server-vulkan-rdna4-vllm-rocm-benchmark/
23. asf0/strix-vllm (fork, branch `gfx1151`; heterogeneous KV subpools, GDN state replay under MTP ~470 MB saved at MTP k=2, Qwen3.8-Flash-Next AWQ W4A16 1,539–1,617 prefill / 40–43 decode tok/s single-stream, image `ghcr.io/asf0/strix-vllm:latest` ROCm 10.1): https://github.com/asf0/strix-vllm
24. ROCm/k8s-device-plugin README (plugin registers `amd.com/gpu`; host needs ROCm kernel driver; health-check mode requires privileged pods; Helm chart amd-gpu-helm; node labeller): https://github.com/ROCm/k8s-device-plugin
25. datahardware.ai — "Strix Halo Tokens Per Second 2026" (dense 70B ~5 tok/s vs 30B MoE 72–75 tok/s on Ryzen AI Max+ 395): https://datahardware.ai/blog/strix-halo-tokens-per-second-2026
26. kyuz0 — amd-r9700-vllm-toolboxes (2×R9700 64 GB bench site, ROCm 7.2.53150): https://github.com/kyuz0/amd-r9700-vllm-toolboxes
27. Live probe 2026-11-04 (`readonly-ai-gpu-kubernetes`): `default/amd-gpu-device-plugin-daemonset` = `docker.io/rocm/k8s-device-plugin:1.31.0.9`, non-privileged container (drop ALL caps), hostPaths /var/lib/kubelet/device-plugins, /sys, /var/lib/amd-metrics-exporter; node capacity `amd.com/gpu: 2` (EXPLORE §1).
28. ROCm/ROCm issue #5812 — gfx1201 rocBLASLt lookup bug (cited by [14]): https://github.com/ROCm/ROCm/issues/5812

### Reliability notes (self-review)

- **High confidence** (primary/multiple independent): support status of both chips [1][11][12][3]; image tags/sizes/digest [2][3]; quant matrix [4]; KV math (derived from the model's own config [19], cross-checked against slb350's measured 26.63 GiB Q8 footprint and 256K-ctx runs [18]); k8s pod shape [10][24][27].
- **Medium confidence**: R9700 27B vLLM numbers — single data point (2×R9700, 32B-FP8,
  Sep 2026, forum issue thread [20]) plus llama.cpp measurements [15]; 8060S Q4 vLLM
  decode estimate is an extrapolation (bandwidth ceiling [13] + no-MTP gap [9]), not a
  measurement.
- **Weakest claim**: "4×100k fits under Q4+fp8KV on the 8060S" — it fits *arithmetically*
  (12.2 GiB KV + 16 GiB weights + ~2.6 GiB overhead ≈ 30.8 GiB) but only if the GTT
  allocation really is 32 GiB **and** the Strata arena isn't simultaneously resident in
  that same RAM (open questions 1/9). Verify on target before promising it.
- **Perspective weighting**: community sources (#20/#21/#16/#23) carry disproportionate
  weight because no *AMD-official* RDNA vLLM benchmark exists for 27B-class — AMD's
  performance-validation content targets MI300X/MI355X. The plan should budget an
  on-target benchmark run as acceptance, not trust any published number.
- **Blind spot** (no source addressed): nothing public measures 27B vLLM on an 8060S
  constrained to a 32 GiB GTT on a node sharing RAM with a 116 Gi-limited Strata pod, nor
  ROCm-in-container on an openSUSE TW host.

---

## R2 — Can vLLM get the flash model to Strata's ~50 tok/s? (dedicated round)

### TL;DR

- **The flash model is Qwen3.8-Flash-Next = 125B MoE (512 experts, top-10) + 51B N-gram
  embedding ("PLE", 26.8 GiB in every quant) = 176B total, only 6B active per token** [29][30]
  — not "13B active" as R1 assumed. This corrects R1's bandwidth premise and is the single
  most load-bearing fact of this round.
- **vLLM natively supports the architecture** (`qwen4_exp`, vLLM ≥0.30; GDN+QSA hybrid,
  512-expert MoE, MTP, PLE) [31][48] — but every validated vLLM deployment of this model is
  on 8×H200/GB300 or **MI355X** (751–801 tok/s out at c=8, MXFP4/FP8, 170–173 GiB
  checkpoints) [31]. No RDNA validation exists for this model in any engine.
- **R9700 (32 GB discrete) is a dead end for the flash in vLLM**: the 26.8 GiB PLE table
  must be VRAM-resident on AMD (vLLM's PLE/engram CPU-offload "currently only runs on
  Nvidia devices" [31]), leaving ≤5 GiB for dense+KV+experts; the only >VRAM path
  (`--cpu-offload-gb`, UVA zero-copy host reads on every forward) crosses the lab's
  **OCuLink x4 ≈ 7.2 GB/s** link [EXPLORE-runbook 0.4] — derived ceiling **~2–7 tok/s**,
  measured analog on another platform for this exact model: **4.26–9.46 tok/s** [32].
- **8060S unified is the only viable vLLM-flash topology** (GTT-backed "VRAM", 256 GB/s
  LPDDR5X, no link): arithmetic single-stream ceiling ~80–95 tok/s at IQ3_S (6B active
  ≈ 2.6 GB/token) [29][30][R1-13], but the best *measured* vLLM-family number on this
  exact platform class is **40–43 tok/s** (asf0/strix-vllm, ROCm 10.1 fork, AWQ W4A16,
  [R1-23]) and the best non-vLLM single-user number is 33–41 (llama.cpp fork + MTP [45][46]).
  **50+ single-stream has never been demonstrated by vLLM anywhere on Strix-class silicon.**
- **Coexistence is physically impossible**: a vLLM-flash instance needs ~105–130 GiB of
  node RAM (weights + KV + overhead) [29][45]; a warm Strata arena needs 47–92 GiB
  page-locked (runbook §3.3/§4). One 125 GiB node, one big MoE at a time — the RAM law
  already enforces this for Strata+llama.cpp; it kills "vLLM flash **while Strata keeps
  running**" outright.
- **Verdict: the user's 50+ condition FAILS for the flash model.** Recommended split:
  vLLM takes the dense 27B (R1 scope, R9700-first); Strata keeps the flash; the 8060S
  vLLM-flash path is a watch-item (re-evaluate on UVA-on-ROCm + PLE-offload-on-AMD +
  MTP-on-RDNA landing), and MTP is the one feature that would close most of the gap if it
  ever lands on RDNA (it is the Strata/halogen/EngramHalo edge: +60–100% single-stream
  [40][41][45]).

### Q1 — Can vLLM serve a ~180B-class MoE at Q4/Q3 on 32 GB RDNA4 + host RAM?

**Architecture first (corrects R1).** `Qwen/Qwen3.8-Flash-Next` is `model_type: qwen4_exp`
(`Qwen4ExpForConditionalGeneration`), fetched live 2026-11-04 [29]: 48 layers, 3-of-4 GDN
(`linear_attention`) + 1-of-4 full-attention, `num_experts: 512`, `num_experts_per_tok:
10`, `moe_intermediate_size: 640` + shared expert 640, hidden 2560, MTP 1 layer, 262144
max ctx, 27-layer vision tower, and a **PLE N-gram table: 20,000,000 n-grams (size 3) ×
2560 dim = 51B params** — 26.8 GiB in *every* quant, because it is a stored lookup table,
not a matmul [29][45]. The design paper (arXiv 2608.30320) states the PLE is "held off
the accelerator" [30]: per-token cost is a small gather, not bandwidth. **Active per
token = 6B** [30][31] (≈2.6 GB at IQ3_S / ≈3.7 GB at Q4_K_XL), not R1's ~13B.

**The four candidate vLLM mechanisms, each checked:**

1. **`--cpu-offload-gb` (weight offload).** Since v0.31 (in the lab's v0.33 image) there
   are two backends [35]: **UVA** — offloaded params are pinned in host memory and the
   GPU reads them **zero-copy over the interconnect on every forward pass** (`--cpu-offload-
   params experts` restricts the offload to sparsely-read expert tensors; without the
   selector vLLM offloads the *hottest* dense weights first — bug, open [32]) — and
   **prefetch** — whole *layers* copied back on a side stream (layer-granular, wrong
   shape for sparse MoE [35]). Known failure modes: quantized weights renamed after load
   silently stay on GPU [35]; pinned allocations round up **1.15–1.9×** host RAM
   (`VLLM_WEIGHT_OFFLOADING_DISABLE_PIN_MEMORY=1` → 1.01× — mandatory on a RAM-caged node
   [35]); v0.27.x V2-runner silent no-op (irrelevant, we're on 0.33 [35]).
   - *Measured penalty, this exact model, one card, `--cpu-offload-gb 47`* (vLLM issue
     #54593, Intel XPU, FP8): default order **4.26 tok/s** (4.5 GiB/token over PCIe) vs
     `--cpu-offload-params experts` **9.46 tok/s** (0.93 GiB/token) [32]. The gap is pure
     bus bandwidth; the issue explicitly notes platform doesn't change the math [32].
   - *Lab mapping (derived from [32] + [35] + runbook 0.4 link facts):* R9700 link 7.2
     GB/s → 0.93–3.2 GiB/token ⇒ **~2–7 tok/s ceiling** (UVA gather latency over x4
     pushes reality to the low end; no MTP). 8060S unified: no interconnect — the UVA
     view reads LPDDR5X at ~256 GB/s ⇒ ceiling 256/2.6–3.2 ≈ **80–98 tok/s**; realistic
     vLLM single-stream 30–45 (kernel tuning + no MTP; asf0's 40–43 on the *resident*
     fork config is the measured anchor, and his fork had GDN-specific fixes stock lacks
     [R1-23]).
2. **Offloading connector / KV-offload** (v0.11+; `TieringOffloadingSpec` validated for
   this model only on 4×H200 in v0.30, [31][36]): tiers the *KV cache* (CPU DRAM /
   filesystem) to extend the prefix cache. **It does not fit weights** — it is a RAM
   *consumer* on a RAM-caged node, irrelevant to the 50 tok/s question, and only useful
   later for long-ctx session reuse [36].
3. **Expert offloading (hot-expert GPU cache over CPU-backed experts).** The Strata design
   itself. In vLLM upstream this **does not exist**: the dedicated PR (#31938: pinned
   streaming + AVX/AMX CPU MoE kernels + GPU hot-expert cache + prefetch, DeepSeek-R1
   class) was **closed unmerged**; the RFC (#33869) stands open [33][34]. Community
   existence proofs: `leoustc/vllm-moe` (`--moe-gpu-prefetch N` LRU expert cache;
   26B-A4B on A100-40GB: 30–55 tok/s; **CUDA-only, no RDNA claim** [43]) and vllm-metal's
   expert-offload (Apple Silicon, same design class [44]). Nothing RDNA-usable, and
   nothing in the stock image.
4. **PLE (N-gram table) placement** — the quiet killer on AMD. vLLM's PLE/engram
   CPU-offload (`--engram-config '{"cpu_offload":true}'`, on by default on H100-class) is
   "**the initial implementation supports both ModelRunner V1 and V2**… currently **only
   runs on Nvidia devices**" [31]. On AMD the 26.8 GiB table lands in "VRAM" — on the
   R9700 that alone is 84% of the card. (A UVA `--cpu-offload-params` push of the table
   tensor *might* work since gathers are per-token-trivial, but the table's parameter
   names and whether `qwen4_exp` layers register with the offloader are unverified —
   open question 3.)

**Minimum sensible VRAM for the flash at Q4/Q3-class (derived, [29][30][32][35]):**

| Topology | Layout | Minimum sensible VRAM | Realistic single-stream |
|---|---|---|---|
| R9700, PLE VRAM-resident (only known AMD path) | PLE 26.8 + dense ~2.5 + KV 1–2.4 + ws 1–2 | **~32–34 GiB → no expert headroom; infeasible** | n/a |
| R9700, PLE+experts UVA-offloaded (unverified) | dense 2.5 + hot-expert cache 0–10 + KV | ~10–20 GiB | **~2–7 tok/s** (7.2 GB/s link, [32][35]) |
| 8060S, GTT ~32 GiB, experts UVA-offloaded (unverified) | PLE 26.8 + dense 2.5 in GTT, ~55 GB experts in host [repo cf-77] | ~32 GiB GTT | **~30–45 est.** (256 GB/s physics; anchor: 40–43 measured fork [R1-23]) |
| 8060S, GTT ~110 GiB, all resident | 104 GB weights + KV | ~110 GiB GTT (max, [R1-13]) | **~40–45 measured class** (asf0: 40–43, AWQ W4A16 [R1-23]); ceiling ~80–95 |

So: **yes, vLLM can *load and serve* the flash on this hardware in principle** (native
model class [31][48]; 8060S unified is the workable form), **but the >VRAM paths deliver
single-digit tok/s on the R9700 and 30–45-class on the 8060S** — and two of the four
load-bearing pieces (UVA-on-ROCm, PLE placement on RDNA) are unverified (open questions).

### Q2 — Bandwidth reality check

Facts with sources: ai-gpu = Ryzen AI Max+ 395 class, 8-ch LPDDR5X ≈ **256 GB/s**
platform bandwidth [R1-13][45 (same SOC)]; R9700 = 32 GB GDDR6 @ 640 GB/s [R1-15];
**R9700↔host link = OCuLink, `Speed 16GT/s Width x4` ≈ 7.2 GB/s end-to-end** (runbook
gate 0.4 — measured-expected, x1 would have pivoted to the Strix fallback [repo]).

Bytes/token for Flash-Next decode (derived from [29][30]):

| Quant | Active 6B | + shared/dense read | ≈ per token |
|---|---|---|---|
| IQ3_S (~3.4 bpw) | ~2.4 GB | +~0.4 GB | **~2.6–2.8 GB** |
| Q4_K_XL (~4.9 bpw) | ~3.6 GB | +~0.6 GB | **~3.7–4.2 GB** |
| (FP8, for ref.) | ~6.0 GB | +~1.0 GB | ~7 GB |

(PLE gathers add KB-scale traffic, not GB [30][32].) Single-stream ceilings
(bandwidth ÷ bytes/token, compute-overhead-free):

| Path | Bandwidth available to weights | Ceiling (IQ3_S) | Ceiling (Q4_K_XL) | 50+ reachable? |
|---|---|---|---|---|
| 8060S unified (GTT, all weights in LPDDR5X) | ~256 GB/s | **~90 tok/s** | ~62 tok/s | *arithmetically yes; never measured in vLLM* |
| 8060S, experts UVA-offloaded (32 GiB GTT) | ~256 GB/s (same bus) | ~90 tok/s | ~62 tok/s | *same — no link involved* |
| R9700, hot experts in 32 GB GDDR6 (Strata's trick) | 640 GB/s hot + 7.2 GB/s cold | 50–80 **measured by Strata with MTP** [repo cf-77] | — | only *with* expert-cache + MTP, which vLLM does not have [33][34] |
| R9700, experts UVA-offloaded over OCuLink x4 | 7.2 GB/s | **~2.7 tok/s** | ~2 tok/s | **no — 20× off** |

**Plain answer:** on the ai-gpu node, 50+ tok/s single-stream in vLLM is **not
demonstrable today**. The 8060S arithmetic says it's *possible* (ceiling ~90 at IQ3_S),
and the measured neighborhood (asf0 fork 40–43 [R1-23]; EngramHalo llama.cpp+MTP 33–41
[45][46]; halogen 35.9 [45]) sits at ~40 — i.e. vLLM on the 8060S lands at the 40s, one
MTP away from the bar, on hardware that can't simultaneously run Strata. The R9700 path
fails by an order of magnitude on link physics, independent of software.

**Where vLLM could win instead (the real value axes):**
- **Aggregate/batched throughput** — continuous batching + prefix caching across the 3–4
  concurrent agent sessions the card wants; the measured pattern on this SOC class:
  4 concurrent ≈ 2× single-stream aggregate (halogen 68.7 vs 35.9 [45]; vLLM RDNA MoE
  782 aggregate @c32 on 2×R9700 [40]) — and vLLM's batching is more elastic than
  llama.cpp's (Strata rejected `--batch` after a stall incident [repo cf-77]).
- **27B dense on R9700** (R1's GO): the RDNA4-vLLM fork shows **55 tok/s single-stream
  and 315 aggregate @c16 for 27B-FP8 with MTP-3** [40] — vLLM+MTP *beats* Strata's 50 on
  the dense model, the axis where the weights actually fit VRAM.
- Ops: preemption instead of hard OOM, `/metrics`, OpenAI/Anthropic surface, sleep mode
  (hip [R1-8]), KV tiering for long-ctx session reuse [36].
- MoE expert-parallel: N/A for this model on this node — EP needs homogeneous multi-GPU;
  R9700+8060S is a heterogeneous pair no engine TP/EP-shares (and 176B won't fit the
  32+32 anyway).

### Q3 — Does vLLM support the flash model's architecture class?

- **Model class: yes, natively.** `qwen4_exp` is in stock vLLM (≥0.30) [31][48];
  GDN+QSA hybrid, 512-expert top-10 MoE, MTP speculative decoding, PLE all first-class
  for this exact checkpoint [31]. vLLM 0.33 (lab image, R1[2]) ≥ 0.30 ✓.
- **MoE on ROCm: yes on CDNA, community-only on RDNA.** Validated MI355X runs use AITER
  + FlyDSL MoE/GDN kernels (MXFP4, TEP8/TP2/TP1, 751–801 tok/s @c8, GSM8K 0.965–0.967
  [31]); on gfx12 the community RDNA4 port serves a 256-expert MXFP4 MoE via
  `--moe-backend triton_unfused` — with the warning that **every native MXFP4 MoE backend
  is CUDA/CDNA-gated and the auto-fallback is ~5× slower** [40]. AITER in the official
  image is CDNA-only prebuilt (R1[3]).
- **FP8 vs GGUF for this model on RDNA:** official checkpoints are FP8 (172.78 GiB),
  BF16 (335.28), NVFP4, Quark MXFP4 (169.8) [31][37] — all 4–6× the 32 GB card, i.e.
  server-class. The only 32-GB-class form is the **GGUF Q4/IQ3 (103.7 GiB Q4_K_XL /
  83.6 GB IQ3_S, PLE shard 28.8 GB [repo runbook §2])** — which in vLLM means the
  **experimental OOT `vllm-gguf-plugin`** (R1[6]); GGUF+qwen4_exp on RDNA has no public
  validation (open question 2). On gfx1151 stock vLLM rejects FP8 checkpoints outright
  (R1[16]) — the 8060S path is GGUF-only in practice.
- **Large-ctx MoE on RDNA: no reported working deployment** of this 176B model on any
  RDNA card (searched; the only 262k-ctx validations are CDNA/Hopper, and even there a
  single 262K request was left untested [31]). The nearest public large-MoE-on-RDNA
  deployments are ≤35B active-fitting models [40] and Strata's own arena work [repo].

### Q4 — Alternatives the go/no-go needs

| Option | Flash-model single-stream | Evidence | Coexists with warm Strata? |
|---|---|---|---|
| **Strata (status quo, R9700 arena)** | **~50 user-reported; 80 bench @64K** (IQ3_S, MTP spec-4, int8 KV, expert cache) [repo cf-77 §5] | measured in-repo | n/a (it is Strata) |
| Strata strix profile (8060S) | 59.1 @8K / 42.1 @128K (0.1.40-era) [repo cf-77 §7] | measured (engine-epoch caveat) | no — same arena law |
| **vLLM stock v0.33, R9700** | **~2–7 derived (UVA/x4)** [32][35]; PLE-residency problem [31] | derived + platform analog | no (and pointless) |
| **vLLM stock/fork, 8060S unified** | **40–43 measured (fork, AWQ W4A16)** [R1-23]; 30–45 est. stock | measured (fork) | **no** — 105–130 GiB RAM need vs 47–92 GiB warm arena [45][repo] |
| llama.cpp + MTP fork (EngramHalo), 8060S | 33–41 (Q4_K_XL, 32k ctx) [45][46] | measured | no |
| llama.cpp stock, 8060S | 28–32 @128K–256K [R1-18] | measured | no |
| halogen-flash-server (3rd engine, gfx1151-only HIP) | 35.9 single; **68.7 total @4 concurrent**; 1350 tok/s prefill [45] | measured (2026-09-16) | no ("only one runs at a time" [45]) |
| SGLang | gfx1151 **official image** (`rocm/sgl-dev:*-gfx1151*`, `SGLANG_USE_AITER=0`) [38]; day-0 model support validated **CDNA/NV only** [37]; RDNA4 official support still an open tracking issue [39] | n/a | no |
| TGI | **maintenance mode** (HF) [47]; ROCm validation MI210/MI250/MI300-class only [47] | n/a | n/a |
| ik_llama | no credible Strix/RDNA MoE data found in this round | — | — |
| MTP/speculative decoding on ROCm (any engine) | official vLLM-ROCm measurements **CDNA only** (MI300X/MI355X, 2026-08-23) [41]; RDNA: community RDNA4-vLLM fork ships **MTP-3 as production default** [40]; Q4-2026 roadmap item = "close spec-decoding gap on ROCm, prioritizing Qwen3.x" [42]; stock v0.33 on RDNA unverified | measured (CDNA), community (RDNA) | — |

**Nothing credibly beats 50 tok/s single-stream on this hardware except the already-
deployed Strata R9700-arena path.** The 8060S ecosystem converges on ~35–43 single-user
for this model (three independent measurements, three engines [45][46][R1-23]); Strata's
80/50 comes from the R9700's 640 GB/s GDDR6 expert cache + MTP + int8 KV, i.e. the exact
mechanisms vLLM lacks on RDNA [33][34][41][42]. The one "beats 50" row (halogen 68.7) is
*aggregate across 4 requests* on a dedicated gfx1151 engine — a different axis, not
vLLM, and it still can't share the node with warm Strata [45].

### Contradictions and how to weigh them

1. **R1's "~13B active" vs config's 6B** [29][30] — the config and the paper win; R1's
   R2 framing (13B) is superseded. All R2 bandwidth math uses 6B; the R1 27B-dense
   sections are unaffected.
2. **"vLLM supports Flash-Next" (HF card: "compatible with vLLM") vs no RDNA deployment
   exists** [31] — both true: the *model code* is in vLLM; the *validated hardware* is
   Hopper/Blackwell/MI355X. Plan against the hardware matrix, not the compatibility line.
3. **"PLE held off the accelerator" [30] vs vLLM "PLE offload only runs on Nvidia"
   [31]** — the paper describes the intended design; vLLM's AMD reality forces the 26.8
   GiB table into VRAM. This is what makes the R9700 infeasible; the SGLang side has the
   same flag but validates it on GB10/MI355X, not RDNA [37].
4. **UVA offload "2.2× from one flag" [32] vs "UVA caps 10 GiB at ~3 tok/s on Gen4"
   [35]** — not a clash: different links (the XPU box ran a faster interconnect) and
   different offload sets (0.93 vs 4.5 GiB/token). The lab's x4 link is slower than
   either reference, so take the pessimistic end of [32]'s measured pair as the ceiling
   and treat [35]'s latency notes as the haircut.
5. **Strata 80 tok/s (bench) vs user's ~50 (production)** — different contexts
   (64K bench one-at-a-time vs mixed real traffic) and quant/epoch; treat 50 as the
   service bar (the user's number, repeated in the card) and 80 as the demonstrated
   ceiling of the current deployment [repo cf-77].
6. **"SGLang on AMD" (day-0, "on NVIDIA and AMD" [37]) vs "no RDNA"** — "AMD" in the
   day-0 copy means Instinct; the gfx1151 image [38] exists but is unvalidated for this
   model. Don't sell SGLang as an R9700/8060S flash option; it is a *maybe* for the
   8060S if the owner wants a second vLLM-family engine (watch [39]).

### Implications for the plan

- **Scope split (feeds OQ2 and the card's four threads):**
  - **vLLM = dense 27B + everything the card's non-flash threads need** (R1 GO, R9700-
    first): the 27B-FP8 55 tok/s + MTP RDNA data point [40] strengthens R1's R9700 GO —
    if the owner accepts the community RDNA4 fork or waits for the official image's
    RDNA MTP (roadmap [42]), vLLM *exceeds* Strata's bar on the 27B, which is the model
    vLLM is actually good for here.
  - **Flash model stays on Strata.** Do not plan a vLLM-flash deployment. The user's
    "keep llama.cpp and strata running" condition is honored trivially; "implement
    everything in vLLM" is scoped to 27B service + UI + priority + monitoring.
  - **8060S vLLM-flash is a watch-item, not a chunk:** it needs (a) GTT ≥ ~40 GiB verified
    (R1 OQ1), (b) UVA-on-ROCm + `qwen4_exp` offload-path verified on-target, (c) the PLE
    placement question answered, and (d) Strata cold. Re-check when any of vLLM #31938/
    #33869 (expert cache [33][34]), PLE-offload-on-AMD [31], or RDNA MTP [41][42] lands.
- **The x4 OCuLink link is the reason to keep the flash off the R9700-in-vLLM forever**
  (absent a cable/BIOS x16 upgrade — an operator question, not a plan item): even a
  future perfect vLLM expert-cache would be capped at 7.2 GB/s for cold experts [repo].
- **If the owner ever wants "everything in vLLM" including the flash**, the only
  credible shape on this node is: R9700 exclusive to vLLM-27B (Strata retired or
  R9700-less), flash on the 8060S via unified memory with Strata's arena gone — a
  node re-architecture, a different ticket.
- **RAM law update for planning:** add to the coexistence ledger that *any*
  >~60 GiB weight set (vLLM-flash, Strata-Q4 rung, llama.cpp 107 GB runs [45]) is
  mutually exclusive with *any* other warm >~50 GiB residency on this node.
- **Acceptance for the 27B vLLM chunk should include a flash-model *negative* smoke**
  only if the owner wants it (expected: infeasible error/over-budget — do not benchmark
  it into service; record the error path as evidence).

### Open questions (R2)

1. **GTT allocation** (carried from R1 OQ1): 32 GiB or up to ~110 GiB on ai-gpu?
   Decides whether the 8060S vLLM-flash watch-item is "GTT 32 + UVA offload" or "GTT
   110 resident". Operator: `rocminfo`/BIOS.
2. **GGUF + qwen4_exp on RDNA in vLLM**: does the OOT GGUF plugin load
   `qwen4_exp` (512-expert, PLE shard) at all, let alone on gfx1151/gfx1201? No public
   validation found. On-target 10-min check (expect loader error) would close it.
3. **`qwen4_exp` in the UVA offloader path**: does its layer stack register with
   `make_layers()`-style offload (particula's documented list for 0.31 covers
   qwen3_next et al., not qwen4_exp [35]), and what are the expert/PLE parameter names
   for the `--cpu-offload-params` selector? Confirm by printing one decoder layer's
   `named_parameters()` before any offload attempt (the documented procedure [35]).
4. **UVA on ROCm/HIP**: every public UVA data point is CUDA/XPU [32][35]. Does the
   pinned-host zero-copy path work in the `vllm-openai-rocm` image (HIP mapped host
   memory)? Single on-target smoke: load a 30B GGUF with 20 GB UVA offload, read the
   "Total CPU offloaded parameters" line, measure tok/s.
5. **PLE placement on RDNA**: with engram-offload NVIDIA-only [31], does vLLM
   place the 26.8 GiB PLE in GTT/VRAM, refuse to load, or accept a UVA push? Determines
   the R9700 infeasibility claim's strength (currently: infeasible *as documented*).
6. **Strata current-era strix numbers**: repo strix decode numbers are 0.1.40-era
   (59.1@8K/42.1@128K [repo cf-77]); the running engine is 0.1.55 — an on-target
   `strata bench` would pin what "Strata on the 8060S" means today (matters only if the
   owner ever drops the R9700).
7. **halogen-flash-server** [45] is a credible 8060S flash engine (35.9 single / 68.7
   @4) but is a third engine to operate, gfx1151-only, with its own 5.53-bit checkpoint —
   out of card scope; note for the owner, not a plan item.
8. **Link upgrade feasibility** (operator/BIOS, not research): if the OCuLink could run
   x8/x16, the R9700-vLLM-flash ceiling moves from ~2–7 to ~8–30 tok/s — still below 50,
   so the verdict is link-insensitive. Recorded so nobody re-derives it.

### Sources (R2)

All web sources accessed **2026-11-04** via `global-searxng` + `web_url_read`; repo
sources are the cf-77 research/runbook artifacts (cited `[repo …]`) and R1's numbered
sources (re-cited as `[R1-n]`).

29. Qwen3.8-Flash-Next `config.json` (HF, fetched 2026-11-04): `qwen4_exp`/`Qwen4ExpForConditionalGeneration`; 48 layers 3:1 GDN:full-attention; 512 experts, top-10; moe_intermediate 640 + shared 640; hidden 2560; MTP 1 layer; PLE ngram_size 3, 20,000,000 × 2560 (51B); 262144 ctx; vision 27 layers: https://huggingface.co/Qwen/Qwen3.8-Flash-Next/raw/main/config.json
30. arXiv 2608.30320 — "On the Design of Qwen3.8-Next Architecture": 125B MoE, 6B active/token, 51B N-gram embedding "held off the accelerator", leads 397B-A17B predecessor on 8/14 benchmarks: https://arxiv.org/abs/2608.30320
31. vLLM Recipes — Qwen/Qwen3.8-Flash-Next (fetched 2026-11-04): vLLM ≥0.30.0 runs the model (nightly-tuned); AMD validation = MI355X only (Quark MXFP4, TEP8/TP2/TP1: GSM8K 0.965–0.967, 665–801 tok/s @c8, 1282–1831 @c32); PLE CPU offload `--engram-config` "only runs on Nvidia devices" (initial impl); MTP `--speculative-config '{"method":"mtp","num_speculative_tokens":3}'` (opt-in on MI355X); checkpoint sizes FP8 172.78 GiB / BF16 335.28 / MXFP4 169.8; KV offloading upstream since v0.30 (#57145) validated 4×H200; 262K native, single-262K-request untested: https://recipes.vllm.ai/Qwen/Qwen3.8-Flash-Next
32. vllm-project/vllm issue #54593 (OPEN, 2026-08-31) — "cpu-offload-gb evicts in declaration order, offloading the hottest weights first": UvaOffloader mechanics; Flash-Next one-card `--cpu-offload-gb 47`: **4.26 tok/s (4.5 GiB/token) default vs 9.46 tok/s (0.93 GiB/token) with `--cpu-offload-params experts`**; weight table dense 4.80 GiB / experts 62.11 GiB / n-gram 47.75 GiB (gather-only); measured Intel XPU, "platform doesn't matter here": https://github.com/vllm-project/vllm/issues/54593
33. vllm-project/vllm PR #31938 (CLOSED, unmerged) — "CPU Offload for MoE Inference in vLLM": hybrid GPU-CPU, pinned streaming, AVX/AMX CPU MoE kernels, DBO/prefetch, GPU hot-expert cache: https://github.com/vllm-project/vllm/pulls/31938
34. vllm-project/vllm issue #33869 (RFC) — "DeepSeek-R1 Moe offload", references #31938: https://github.com/vllm-project/vllm/issues/33869
35. particula.tech — "vLLM CPU Offload Not Working: Fix --cpu-offload-gb" (2026-10-12, pinned to v0.31.0 source + upstream issues 51396/53931/54593/56410/58178/56283): two backends (UVA zero-copy pinned-host reads every forward; prefetch layer-granular copy-back); "10 GiB of always-read weights caps a single stream at about 3 tokens/s on PCIe Gen4"; `--cpu-offload-params experts` selector semantics; quant-rename silent-GPU-residency gotcha; pinned alloc 1.15–1.9× rounding, `VLLM_WEIGHT_OFFLOADING_DISABLE_PIN_MEMORY=1` → 1.01×; v0.27.x V2 no-op fixed in v0.28.0 (PR 51413); make_layers() architecture list for 0.31: https://particula.tech/blog/vllm-cpu-offload-not-working
36. vLLM docs — KV Offloading (OffloadingConnector: CPU DRAM + filesystem tiers of the KV/prefix cache, DMA transfers; Prometheus `vllm:kv_offload_config_info`) + vLLM blog 2026-01-08 (introduced v0.11.0, host-device bandwidth deep-dive): https://docs.vllm.ai/en/stable/features/kv_offloading_usage/ ; https://vllm-project.github.io/2026-01-08/kv-offloading-connector.html
37. SGLang cookbook — Qwen3.8-Flash-Next (day-0; 176B/6B GDN+QSA; hardware matrix BF16/FP8 = H200/B200/B300/GB300/MI350X/MI355X, NVFP4 = RDXA+Spark; MI355X cell: `sglang-rocm:v0.5.23-rocm10-mi35x-20261031`, Quark MXFP4, NEXTN MTP accept 3.3–3.7/4, `--ple-offload-embedding` pinned-host/file, FlyDSL monokernel; no RDNA cell): https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.8-Flash-Next
38. SGLang docs — AMD GPUs (official gfx1151 Strix Halo section: `rocm/sgl-dev:*-gfx1151*` images, `SGLANG_USE_AITER=0`, triton attention default, GTT/BIOS aperture note; no gfx1201/RDNA4 section): https://docs.sglang.io/docs/hardware-platforms/amd_gpu
39. sglang issue #30599 (OPEN) — "[AMD] Officially support consumer Radeon RDNA3/RDNA4" tracking umbrella: https://github.com/sgl-project/sglang/issues/30599
40. Capicua25x/vllm-rocm-rdna4 (GitHub + Docker Hub `:0.28.0-rdna4` rc12, 2026-08-28; vLLM 0.28.0-based RDNA4 port, 27k pulls; 2×R9700/9070XT measurements): Qwen3.8-27B-FP8 TP2 MTP-3 = 55 tok/s c1 @6k, 315 agg @c16, ~16-user ceiling; DFlash2 k=7 = 65–70 tok/s c1; Ornith-1.5-35B-A3B MXFP4 (256-expert MoE) `triton_unfused` = 92.5/64.2 tok/s c1, 782 agg @c32; GDN-hardened (fp8 KV + bf16 SSM, prefix caching "align"); "every native MXFP4 MoE backend is CUDA/CDNA-gated… fallback ~5× slower": https://github.com/Capicua25x/vllm-rocm-rdna4 ; https://hub.docker.com/r/capicua25x/vllm-rocm-rdna4
41. vLLM blog 2026-08-23 — "Exploring Speculative Decoding in vLLM on AMD GPUs": native MTP, Gemma-4 MTP, EAGLE-3, DFlash, DSpark measured on **MI300X/MI355X** (no RDNA): https://vllm.ai/blog/2026-08-23-speculative-decoding-amd-gpus
42. vllm-project/vllm issue #61024 — Roadmap Q4 2026: "SIG AMD: Close frontier-model prefill, decode, speculative decoding, and long-context performance gaps on ROCm, prioritizing … Qwen3.x": https://github.com/vllm-project/vllm/issues/61024
43. leoustc/vllm-moe — community branch: `--moe-cpu-offload` (passive CPU-backed experts, per-step active-expert staging) + `--moe-gpu-prefetch N` (bounded GPU active-expert cache, LRU); 26B-A4B on A100-40GB: 30.27–55.32 tok/s (c16 agg); CUDA-only, no RDNA claim: https://github.com/leoustc/vllm-moe
44. vllm-metal docs — MoE Expert Offloading (expert cache + one-layer expert reservation sizing; Apple Silicon; the design class upstream is converging on): https://docs.vllm.ai/projects/vllm-metal/en/latest/moe_offload/
45. kksoftwareag — "Qwen3.8-Flash-Next on Strix Halo" (project site, 2026-09-16; Ryzen AI MAX+ 395 / 8060S / 128 GB, Fedora 44, ROCm 7.1): PLE table 26.8 GB in every quant; stock llama.cpp OOMs >107 GB for UD-Q4_K_XL+MTP; EngramHalo.cpp (llama.cpp fork) Q4_K_XL: 20.8 t/s no MTP / 36.1 (code) / 41 (reasoning) with MTP, 32k ctx, q8_0 KV; "MTP raises single-user 21→33–41, from two concurrent users lowers total"; halogen-flash-server (peonist-ai, gfx1151-only HIP engine, 5.53-bit checkpoint): 35.9 t/s single, **68.7 t/s @4 concurrent**, 28.4 s prefill of 38k (~1,350 t/s), 262k ctx, 7 concurrent 262k on llama.cpp vs 2 on halogen; "each server claims most of the memory, so they take turns": https://kksoftwareag.github.io/strix-halo-qwen-3.8-flash-next/index.html
46. sleepingrobots — "EngramHalo.cpp: Qwen 3.8 Flash Next at 38 t/s on Strix Halo" (llama.cpp fork, RDNA3.5 kernel patches + MTP: 28–38 decode vs 15–20 baseline, same HW/quant): https://sleepingrobots.com/dreams/engramhalo-qwen38-flash-next-strix-halo/
47. Hugging Face — TGI docs: "text-generation-inference is now in maintenance mode"; dev.to (rosgluk, 2026) — TGI ROCm validation centered on MI210/MI250/MI300 (no RDNA): https://huggingface.co/docs/text-generation-inference/index ; https://dev.to/rosgluk/rocm-vs-vulkan-for-amd-local-llm-hosting-2026-guide-5c70
48. vLLM API docs — `qwen4_exp` model package (native classes `Qwen4ExpForConditionalGeneration`, `Qwen4ExpMixtureOfExperts`, Qwen3-VL vision tower, Gated HyperConnection): https://docs.vllm.ai/en/latest/api/vllm/models/qwen4_exp/
49. QwenLM/Qwen3.8-Flash-Next (GitHub) — "125B-parameter main model, supplemented by an additional 51B N-gram embeddings, with 6B parameters activated per token": https://github.com/QwenLM/Qwen3.8-Flash-Next/

**[repo]** in-repo sources (grounded, not web): cf-77 run-1 `RESEARCH.md` §4–§5 (IQ3_S 83.62 GB pair, PLE = shard 00002; PR #3636 bench 2026-10-21: prefill ~2,519 tok/s @64–200K, **decode 80 one-at-a-time @64K**, 429–443 short-prompt prefill; strix 0.1.40-era 59.1@8K / 42.1@128K); `.agents/notes/strata-host-prep-gpu-ai.md` §0.4 (OCuLink `16GT/s x4` ≈ 7.2 GB/s gate), §2 (Q4 rung 111,334,654,784 B; IQ3_S 54.8 GB working set; MTP draft `mtp/rt`), §3.3 (arena caps: IQ3_S 46.84 GiB pinned, Q4 71.7 GiB, conv caches 32/16/8 GiB, worst-case ~91.8/100.7 GiB in the 116 Gi cgroup), §4 (RAM law: one-at-a-time, `ttl 3600`, no concurrent large residency).

### Reliability notes (R2, self-review)

- **High confidence** (primary or multi-source): model spec 125B+51B/6B-active [29][30][31][49];
  vLLM native qwen4_exp support + AMD-validation-is-MI355X-only [31][48]; UVA/prefetch
  mechanics + measured 4.26/9.46 tok/s [32][35]; PR #31938 unmerged / RFC open [33][34];
  PLE-offload-Nvidia-only [31]; SGLang day-0 scope + gfx1151 image + RDNA tracking issue
  [37][38][39]; TGI maintenance mode [47]; the 8060S single-user cluster 33–43
  [45][46][R1-23]; Strata 80/50 and arena/RAM law [repo]; OCuLink x4 7.2 GB/s [repo].
- **Medium confidence**: the R9700 "~2–7 tok/s" figure is a *derivation* (measured
  XPU pair [32] × lab link bandwidth ÷ per-token bytes [29][30]) — the direction and
  order of magnitude are robust; the exact value would need one on-target smoke
  (open question 4/5). The 8060S "30–45 stock vLLM" is an interpolation between the
  asf0 fork measurement [R1-23] and the bandwidth ceiling — no stock-vLLM RDNA
  Flash-Next measurement exists anywhere.
- **Weakest claim**: "minimum sensible VRAM ~32–34 GiB makes R9700 infeasible" — it
  rests on PLE offload being NVIDIA-only [31]; if a UVA push of the PLE tensor works on
  ROCm (unverified), the R9700 layout becomes *loadable* but stays ~2–7 tok/s, so the
  verdict (fail 50+) is insensitive to this claim. Flagged so the planner doesn't
  over-cite the infeasibility beyond what is documented.
- **Perspective weighting**: Strata-side numbers are single-machine in-repo benchmarks
  (2026-10-21, engine 0.1.52-era vs running 0.1.55) [repo]; the 8060S ecosystem numbers
  are one hobbyist's documented project [45][46] plus asf0's fork [R1-23] — three
  independent measurements agreeing at ~35–43 is about as good as public data gets for
  this SOC; treat 50+ on the 8060S as *unproven*, not *impossible*.
- **Blind spot** (nothing found): (a) no public vLLM (stock *or* fork) measurement of
  Flash-Next on gfx1201 in any form; (b) no public UVA-offload-on-ROCm measurement;
  (c) no public PLE-on-RDNA placement behavior; (d) halogen's [45] internals (5.53-bit
  checkpoint, prompt-cache-on-disk) are undocumented beyond the project site; (e) whether
  SGLang's gfx1151 image [38] can even load `qwen4_exp` (no RDNA cell exists [37][39]).

---

## R3 — UI for the vLLM service: what vLLM ships, community UIs, and the llama-swap-as-FE option (dedicated round)

User's exact ask: *"I'd also like you to do some research around a UI for it. Does it come
with one? If not, has anyone made one? Or is it possible to reuse llama-swap as the FE?"*

Scope context (fixed by R1/R2): vLLM serves the dense 27B on the R9700 via
`vllm/vllm-openai-rocm:v0.33.0-rocm100`; the agent fleet reaches inference today through
llama-swap at `llama.spencerslab.com/v1` (a `peers:` route already exists for Strata), and
`.opencode/opencode.jsonc` maps gpu-ai model IDs 1:1 to llama-swap model IDs.

### TL;DR

- **vLLM ships no web UI.** As of `v0.33.0rc3` (2026-11-02, the lab's image class) the
  server is API-only: OpenAI/Anthropic-compatible HTTP, `/metrics`, `/health`, and
  (experimental, opt-in) a Rust rewrite of the API frontend [76][79]. The only bundled
  human-facing surfaces are the official **Prometheus/Grafana example + in-repo Grafana
  and Perses dashboards** [72][71]. The user's remembered "old `vllm/serve` frontend" does
  not exist — the 2024 issue titled "Improve Web UI" was about the *docs site*, not the
  server [75]. A community `--enable-dashboard` PR is **still an open DRAFT, stalled
  since 2026-03-10** [74]. Nothing is deprecated/removed: there was never a UI to remove.
- **Has anyone made one? Yes, three flavors:** (1) **vLLM Playground** — community,
  pip-installable, on the official vLLM blog: chat + structured outputs + GuideLLM
  benchmarking, but it *launches and orchestrates vLLM containers itself* (Podman/K8s
  API), so it competes with the lab's deployment story rather than observing an
  existing pod [82]; (2) **vLLM Semantic Router dashboard** — `vllm-project` org, the only
  thing that renders vLLM metrics natively (embedded Grafana/Prometheus), but it is the
  operator UI of the **semantic-router product** (a competing MoM routing layer), not a
  UI for a standalone vLLM server [83][84]; (3) **generic OpenAI-compatible chat UIs** —
  **Open WebUI** is the lightest server-side option (one container, SQLite default,
  built-in auth, first user = admin) and has an official vLLM integration page on both
  vLLM's and Open WebUI's docs [73][85][86][87]; Jan (desktop) and LM Studio (desktop,
  server-first; remote-client needs a plugin) are workstations, not homelab web surfaces;
  LibreChat is heavy (MongoDB + Redis) [88][89][90][91].
- **Reusing llama-swap as the FE is fully supported and is the best fit.** vLLM is a
  first-class llama-swap upstream (named in the README, detected via `owned_by: vllm`,
  usage/tok-s parsed into the Activity view, `vllm-wrapper` ships in the unified image
  for the local-process variant) [50][55][56][64]. The pinned **v266** schema carries
  everything needed: `peers` (proxy/path-append, `models`, `apiKey`, `timeouts`,
  `filters`), `selectors` (warm/pin/spillover virtual IDs, **peer models are legal
  spillover targets**, shown in the UI), `ui.activity`, `store.path`, `apiKeys` — all
  verified against the repo's pinned schema plus upstream KB/PRs [51][53][62][65][66].
- **Recommendation: llama-swap `peers.vllm` + optional `selectors` as the primary shape —
  zero new chart/ingress/proxy surface for the UI itself** (the FE is a values block in
  the existing llama-swap chart; `/ui` is already reachable on the existing hosts);
  **engine-level live state (KV usage, queue, TTFT/ITL, sleep state) is Prometheus-native
  and belongs to the R5 monitoring thread** (PodMonitor → central Grafana, official
  vLLM dashboards) [71][72] — no chat UI gives that natively.
- **Plan-changer gotchas:** SSE through Traefik is fine by construction (Go flush
  `text/event-stream` per write; no compress middleware in the repo; the `llama-timeouts`
  transport already sets `responseHeaderTimeout: 0`) [92][93]; but vLLM's **first byte on
  a 100k+ prefill** means the peer's `timeouts.responseHeader` must be raised (Strata
  precedent: 1800 s) [51][repo]; model-name collisions are resolved by llama-swap's
  precedence rules + vLLM's `--served-model-name` [51][78]; **nothing in the repo sends
  the Activity session headers** (`X-Session-ID`/`X-Litellm-Session-Id`), so per-session
  grouping of agent traffic is not happening today and vLLM changes nothing [repo]; and
  **llama-swap cannot unload/sleep a peer** — a vLLM peer model is always-on from
  llama-swap's point of view [51].

### Q1 — Does vLLM itself ship any web UI / admin surface today?

**No UI in the server. The current (2026-11) state, piece by piece:**

1. **The server is API-only.** `vllm serve` exposes the OpenAI-compatible endpoint
   family (chat/completions, responses, embeddings, …), Anthropic Messages, gRPC
   (opt-in), `/metrics`, and `/health` [77][79]. The default frontend is Python (FastAPI);
   since ~v0.28 there is a **Rust drop-in replacement frontend** (`vllm-frontend-rs`,
   `rust/` in-tree, enabled with `VLLM_USE_RUST_FRONTEND=1`, gRPC control plane with
   "engine-aware health reporting, abort control, server and model discovery, KV event
   source discovery" [76][79]). The Rust README calls it **"experimental, and
   not feature-complete"** [76]. It is an *API server* rewrite — **not a UI**, and it is
   not the default in v0.33 (release notes describe it as an opt-in feature line [79]).
2. **`--api-server-count` is not an admin surface.** It controls how many *API server
   process replicas* front the engine (auto-scaled to the data-parallel size;
   "vLLM load balances between local data parallel ranks, but an external LB balances
   between vLLM nodes/replicas") [77][78]. Load-balancing plumbing only.
3. **The old "vllm/serve frontend" the user remembers does not exist.** vLLM has never
   shipped a bundled web chat/admin UI in the server. The only "Web UI" issue in the
   vllm-project/vllm tracker ([#10090], closed 2024-11-08, label `documentation`) was
   about the **docs website** (mkdocs "ask AI" button overlapping the version selector)
   [75]. So there is **no deprecation story — nothing was removed**; the server was
   always API-first with external UIs.
4. **The one in-flight UI proposal: PR #32256 `--enable-dashboard`** (opened 2026-01-13
   by community member esmeetu). It would add a built-in `/dashboard`: real-time engine
   metrics (running/waiting requests, TTFT, E2E latency, KV cache usage, prefix-cache
   hit rate, 5 s auto-refresh), full VllmConfig + `VLLM_*` env panels, a Quick Chat
   test box, and bug-report env collection. Author's stated scope: *"engine
   debugging/monitoring tool, not a production vllm chat application"*; auth/history/RAG
   **explicitly out of scope**; "good enough for quick checks, and if you need more, use
   Grafana" [74]. **Status as of 2026-11-04: still `draft: true`, open, `needs-rebase`,
   last updated 2026-03-10, merge conflicts flagged 2026-03-03/10** [74]. No maintainer
   commitment is visible in the thread. Plan against its absence; treat it as a
   watch-item (it would be the "free UI" if it ever lands and the lab's vLLM version
   includes it).
5. **What vLLM DOES ship for humans: the observability stack.** `/metrics` is a
   Prometheus endpoint on the API server, enabled by default [71]. Documented general
   metrics include `vllm:kv_cache_usage_perc`, `vllm:num_requests_running/waiting`
   class, `vllm:num_preemptions`, `vllm:prefix_cache_hits/queries`,
   `vllm:prompt_tokens`/`generation_tokens`, `vllm:engine_sleep_state` (awake /
   weights_offloaded / discard_all — sleep mode is *observable*),
   `vllm:admission_rejections`, plus request-level histograms (TTFT, inter-token
   latency, e2e latency, queue time) [71][96]. The repo bundles a **Prometheus+Grafana
   docker-compose example** and **official Grafana dashboards**
   (`performance_statistics.json`, `query_statistics.json`) plus a Perses variant under
   `examples/observability/` [72]. This is the sanctioned "dashboard" story — and it is
   exactly what this lab's existing central Prometheus/Grafana already consumes (R5
   thread: add a PodMonitor; the dashboards import as-is).

**Answer to "is a UI deprecated/removed upstream?":** N/A — none ever shipped in the
server; the only candidate is the stalled community draft [74], and the project's own
direction is "use Grafana / dedicated tools" for monitoring [74][72].

### Q2 — Community UIs against an OpenAI-compatible endpoint

Two different jobs get conflated under "UI": (a) **chat with the model** (human/agent
front end) and (b) **watch the engine** (live model/queue state). Nothing renders
vLLM's *Prometheus* metrics natively except the vLLM-SR dashboard (which monitors
*semantic-router*) and plain Grafana.

| Option | Class | Extra DB / auth stack? | Live model/queue state? | Renders vLLM Prometheus natively? | Notes for this lab |
|---|---|---|---|---|---|
| **llama-swap `/ui`** (already deployed) | ops UI: model list (incl. peers + selectors), Activity (per-request timing/tokens, vLLM-usage aware), logs, playground, MCP endpoint + local-model Help agent [50][54][63] | **none** (in-memory by default; optional `store.path` SQLite) | model status + in-flight requests, per-request activity; **not** engine queue/KV | no (own `/metrics`; vLLM engine state via response usage, not Prometheus) | zero new surface — the reuse option, Q3 |
| **Open WebUI** | chat app (RAG, functions, multi-user) [85] | **none required**: single container, SQLite default, built-in auth, first user auto-admin, signups auto-disabled after first user [86][87]; Postgres/Redis only for multi-replica "production" scale [97] | no engine state (model list from `/v1/models`, per-chat token usage) | no | official vLLM integration on both doc sites [73][85]; timeout knob `AIOHTTP_CLIENT_TIMEOUT_MODEL_LIST` for slow model listing [85]; lightest *server-side* chat UI |
| **vLLM Playground** (`micytao/vllm-playground`, community, official blog 2026-01-02) | manager+chat: launches vLLM via **Podman or K8s API**, chat, structured outputs, tool calling, GuideLLM benchmarking, vLLM-recipes catalog [82] | none of its own, but it **owns container lifecycle** | per-response metrics (tok/s, token counts) + benchmark runs; no engine queue | no (GuideLLM benchmarking, not Prometheus) | wrong shape here: it would manage a vLLM container instead of observing the lab's k8s pod; useful as a *feature reference* only |
| **vLLM Semantic Router dashboard** (`vllm-project/semantic-router`, v0.4) | operator UI for the **semantic-router** product: config editor, topology view, chat playground, **embedded Grafana+Prometheus** [83] | runs with the router stack (Docker Compose incl. Grafana/Prometheus, or K8s) | router metrics + embedded Grafana | **yes — the only "vLLM-ecosystem" UI that embeds Prometheus** | but it is the UI *for semantic-router* (a signal-driven MoM routing layer) — adopting it means adopting a second router that overlaps llama-swap's role; llm-d (the upstream platform it grew from) likewise offers Prometheus/Grafana/OTel, not a standalone UI [84] |
| **Jan** (desktop app) | chat UI, any OpenAI/Anthropic wire format incl. **vLLM**, Ollama, llama.cpp [88] | none (local app) | none | no | desktop-only — a per-workstation client, not a lab web surface |
| **LM Studio** (desktop app) | chat UI; its docs are server-side (OpenAI-compat endpoint it *exposes*) [89]; using its chat UI against a remote vLLM is a **plugin** story (`lmstudio-universal-endpoint`) [90] | none | none | no | same as Jan: workstation tool, not a homelab FE |
| **LibreChat** | chat app | **MongoDB (default compose) + Redis for scale** [91] | none | no | heaviest; fails the "no extra DB" criterion |
| **Ollama-WebUI / text-generation-webui class** | chat UIs for other engines | varies | none | no | not OpenAI-proxy-first for this use; omitted from shortlist |

**Lightest answers to the user's two sub-questions:**
- *(a) live model/queue state, no extra DB/auth:* **llama-swap `/ui`** (model status,
  in-flight, per-request Activity with vLLM usage already parsed [54][64][65]) + the
  lab's **Grafana with the official vLLM dashboards** for true engine state [72] — and
  the former is already deployed.
- *(b) a human chat FE with no extra DB/auth:* **Open WebUI** — one container, SQLite,
  built-in auth, first user admin, points at `…/v1` [85][86][87]. It is a real app (RAG,
  users, workspaces), so "light" is relative: it is still one more chart + ingress + SSO
  leg if it goes public in this repo's shape.
- *Renders vLLM's Prometheus natively:* only the vLLM-SR dashboard (embedded Grafana)
  [83] — and that comes with a router you don't want to adopt [83][84].

### Q3 — Reuse llama-swap as the frontend: verification against the upstream config schema/docs

**Verdict: fully supported for the vLLM-peer use case, in the pinned v266.** vLLM is not
an afterthought in llama-swap: it is named in the README's supported-upstreams line and
as a repo topic [50], has a purpose-built wrapper tool shipped inside the unified image
(`vllm-wrapper`, for the local-process variant) [56][63], a capability reader selected
via `owned_by: vllm` in the upstream's own `/v1/models` [55], and per-response usage
parsing for the Activity view (v237, predates the pin) [64]. The lab's deployed config
already runs one peer (Strata) through exactly this mechanism [repo EXPLORE §1].

Verified item by item (pinned `config-schema.v266.json` in the repo as the authority;
upstream docs/KB/PRs for behavior; all schema blocks read directly this session):

| Question (from the ask) | Answer | Evidence |
|---|---|---|
| Path/prefix semantics | `proxy` is a base URL; the requested path is **appended verbatim** — so `proxy: http://gpu-ai-vllm.default.svc.cluster.local:8000` (no `/v1` suffix) + `/v1/chat/completions` → correct vLLM URL. Same rule the Strata peer uses | pinned schema `peers.*.proxy`; KB peers examples [51][62] |
| Which models are exposed | `peers.<id>.models` must list the model IDs **explicitly** (required array). The ID sent to vLLM is the list entry, so vLLM must serve it via `--served-model-name` (repeatable; first name is what appears in responses) | pinned schema (`models` required); vLLM serve CLI docs [78]; KB [51] |
| Naming / addressing | Peer models are always addressable as `<peerID>/<modelID>`; an **unqualified** ID works only when exactly one peer provides it; **local model IDs and aliases always take precedence** over unqualified peer IDs; fully-qualified peer names are reserved and are what `/v1/models` reports | KB peers-and-multi-host [51]; KB remote-peers [52]; config.example.yaml [62]; PR #950 [65] |
| Streaming / SSE passthrough | llama-swap is a streaming reverse proxy (its whole product; it sets `X-Accel-Buffering: no`; the README's reverse-proxy section is about *ingress* buffering breaking SSE, with the nginx `proxy_buffering off` guidance) — no SSE-specific limitation is documented for vLLM peers | README [50] |
| `/v1/models` | Peers appear in `/v1/models` as fully-qualified IDs; vLLM reports `max_model_len` (and `root`) in its own model cards, which llama-swap's vLLM capability reader consumes (context length auto-filled; tools/image must be set by hand for vLLM) | [51][55][65][95] |
| `checkEndpoint` / health | vLLM serves `/health` (200 when the engine is healthy, 503 on `EngineDeadError`) — llama-swap's default check path. For **peers** there is no load/wait semantics at all: llama-swap "does not manage the peer's lifecycle. It cannot start, stop or TTL-unload anything on the other side" — a peer model is simply always proxyable once its pod is up | vLLM `/health` API docs [98]; KB caveats [51]; vllm-wrapper `--health-path /health` default [56] |
| apiKeys | Two independent layers: top-level `apiKeys` (empty = **no auth checked at all**; covers the web UI and `/api/` too; clients may use Bearer, `x-api-key`, or Basic) and `peers.*.apiKey` (injected *outgoing* as both `Authorization: Bearer` and `x-api-key`; blank = none; use `${env.VAR}` for secrets — unset var = hard config-load failure) | pinned schema `apiKeys`/`peers.*.apiKey`; KB [57] |
| Per-peer timeouts | `peers.*.timeouts.{connect,keepalive,responseHeader,tlsHandshake,idleConn}` (seconds; `responseHeader` default 60 = "the one to raise for a peer that has to cold-start"; `0` disables). The Strata peer already uses `responseHeader: 1800` in this repo | pinned schema; KB [51]; config.example.yaml [62]; [repo] |
| Per-peer filters | `peers.*.filters.stripParams` / `setParams` (set-if-undefined via `key?`); **`model` is a protected param and can never be overridden or stripped** — i.e. you cannot rewrite the model name at the peer layer; name alignment must happen via vLLM's `--served-model-name` | pinned schema; KB [51][62] |
| Does the `/ui` show peer models | **Yes** — PR #950 (v242, in the pin): "Address peer models by fully qualified names across routing, selectors, model listings, **and the UI** … show peer models in Playground model pickers". Selectors are shown on the Models page (v246); per-request activity, in-flight requests and logs are UI pages; the UI also gained a local-model **Help agent** (chat over llama-swap's own docs/KB) and an **MCP endpoint at `/api/mcp`** in the same releases [50][63][65] |
| Does the `/ui` show peer activity | Activity rows are per-request through llama-swap's proxy layer (paginated, stats API, SQLite-persistable via `store.path`); vLLM usage (token counts + tok/s) is parsed from vLLM's own response format in both streaming and non-streaming mode (v237). Prefill/decode split columns are populated by upstreams that report it (Hipfire does; vLLM's per-request `timings` are not part of the OpenAI wire format, so expect tokens+aggregate rate, not prefill/decode split) | KB observability [54]; PR #898 [66]; PR #910 [64]; KB [54] hipfire section |
| Selectors / routing as the "one model ID" mechanism | `selectors.<virtual>.strategy: warm|pin|spillover` with ordered `targets` of model IDs/aliases — **peer models are legal targets** (KB spillover example uses `workstation/qwen3-coder-30b`); rules: selector IDs may not collide with model IDs/aliases/fully-qualified peer names; targets may not be other selectors; not supported on `/upstream/<id>`; profiles run first and may pin to a selector. `warm` = first ready target, else already-starting, else cold-start first; `spillover` = N reserved requests per target before moving on | KB profiles-and-selectors [53]; config.example.yaml [62]; PR #942 [67]; KB peers [51] |
| Concurrency guards | `models.*.concurrencyLimit` (per-model, HTTP 429 above) and top-level `globalConcurrencyLimit` (across all models, 429 immediately, not queued) exist and are in the pin; they apply to the local routing layer (a 429 from vLLM itself would pass through as-is — see Q5 admission note) | pinned schema; KB capacity-and-queues [60] |
| UI behind a subpath | The v266 release specifically made the UI base-path agnostic (relative assets/API/redirects) for exactly this "serve behind another proxy" case; prefix must be *stripped* by the proxy | CHANGELOG v266 [63]; KB reverse-proxy-subpath [59] |
| Alternative llama-swap patterns considered | (1) `cmd`/`vllm-wrapper` local-process swap — only works if vLLM runs *inside* the llama-swap pod (single-host design; contradicts the R9700 k8s pod plan); (2) `kubeswap` — llama-swap spawns model pods via the K8s API (DRA resource claims, PVC volumes) — a *different* architecture where llama-swap owns engine lifecycle; also not the lab's shape (independent vLLM chart + peer hop is the R1/OQ1 direction) | KB vllm-wrapper [56]; KB kubeswap [61]; CHANGELOG v265/v266 [63] |

**Version drift (pin v266, 2026-10-22, vs upstream main, 2026-11-04):** the pin already
contains everything the plan needs (peers, selectors, UI+peer pickers, activity+SQLite,
vLLM usage parsing, vllm-wrapper, base-path UI, `maxRequestBodyMB`, `security.cors`,
`store`, `globalConcurrencyLimit`). Post-pin releases add: v267 capacity router +
Help-agent source search, v268 pause/resume API, v269 per-upstream usage-extraction
refactor (vLLM among the explicit handlers), UI capability-category grouping, PNG
activity export, persistent captures [63]. Nothing in the v267–v269 set changes the
feasibility of this plan; renovate will pick the version up over time
[63][70]. **Known open rough edges (v266-era):** prompt/cached token values can vary
by backend (open issue #1218) [68]; `warm` selector falls back to `targets[0]` while it
is stopping; no automatic failover strategy for selectors (open issues #1240, #945)
[69].

### Q4 — Concrete recommendation for THIS lab

**Primary shape: "llama-swap as the FE" — a `peers.vllm` block in the existing
llama-swap chart values, optional `selectors` for a unified model ID, `/ui` as the
ops surface, and the existing central Prometheus/Grafana (via a new vLLM PodMonitor,
R5 thread) as the engine-state surface.**

What it costs in repo surface:
- **UI itself: nothing new.** No new chart, no new Ingress, no new proxy-local leg,
  no `custom-values` entry (no secrets needed if vLLM runs keyless in-cluster — the
  Strata peer precedent [repo]). The FE change is a block inside
  `services/gpu-ai/prod/values.yaml`'s existing `llama-swap.config` (peer + selector +
  optional `store.path`/`ui.activity`), which renders into the existing
  `llama-swap-config` ConfigMap. `/ui` is then reachable exactly where it is today
  (`llama.spencerslab.com/ui` behind the Keycloak-SSO hop, `ai-llama-swap` directly).
- **The vLLM service's own surface** (chart + ApplicationSet entry + proxy values
  entry per the trio) is independent of the UI decision — it is OQ1/R1 territory
  (standalone `charts/vllm` vs second controller of the llama-swap Application).
  The peer approach works with **either** shape (proxy URL = Service ClusterIP).
- **If the owner additionally wants a human chat UI:** Open WebUI is the
  recommendation — one more chart + Ingress + (if public) proxy-local/SSO leg, pointed
  at llama-swap's `/v1` so the model list stays single-sourced. That is a full service
  trio, i.e. a *separate optional chunk*, not part of the vLLM service itself.

What the UI does **NOT** give that the monitoring thread (R5) must cover:
- **Engine-internal state**: KV-cache usage, running/waiting queue, preemption counts,
  prefix-cache hit rate, TTFT/ITL/e2e latency histograms, sleep state, admission
  rejections — all live in vLLM's `/metrics` [71]; the llama-swap `/ui` Activity shows
  *per-request* timing/tokens as seen at the proxy, not engine state.
- **Grafana dashboards**: the vLLM project ships official ones
  (`examples/observability/dashboards/grafana/{performance_statistics,query_statistics}.json`)
  to import into the lab's central Grafana [72].
- **GPU-side observability** (no ROCm GPU exporter in the stack — R1/explore gap):
  neither UI shows R9700 VRAM/occupancy; that is a separate exporter problem.
- **Cross-engine view**: the 27B-on-vLLM vs 27B-on-llama.cpp vs Strata-flash story
  needs PromQL over both metric families (llama-swap `/metrics` + vLLM `/metrics`) —
  no single UI provides that today.

### Q5 — Gotchas that change the plan

1. **SSE through Traefik is safe by construction — but the first byte is the risk.**
   Go's reverse-proxy machinery (Traefik) flushes `text/event-stream` on every write,
   so streaming works out of the box; the documented breakers are a **compression
   middleware** (none exists anywhere in `services/`/`charts/` — grep-verified this
   session) and **timeouts** [92][93]. The lab's llama subdomains already carry the
   `llama-timeouts` ServersTransport (`responseHeaderTimeout: 0`, `idleConnTimeout:
   3600s`) [repo EXPLORE §1/§8.8], and llama-swap sets `X-Accel-Buffering: no` itself
   [50]. The one real exposure: **vLLM's TTFT on a 100k+ prefill** — the peer's
   `timeouts.responseHeader` (default 60 s) will cut deep-prefill requests that the
   same host serves fine today; the Strata peer sets 1800 s for exactly this reason
   [repo] — copy it for the vLLM peer (or size it from the R1 TTFT numbers).
   Provider-side 2 h `headerTimeout`/`chunkTimeout` in `.opencode/opencode.jsonc`
   already covers the client end [repo EXPLORE §2].
2. **Model-name collisions are policy, not accident.** llama-swap precedence: local
   model IDs/aliases **beat** unqualified peer IDs; peer names are only unambiguous
   when exactly one peer provides them [51][62]. Consequences: (a) never give the vLLM
   model the *same* ID as an existing local rung unless that shadowing is intended
   (local wins, peer reachable only as `vllm/<id>`); (b) vLLM must serve the exact
   name listed in `peers.vllm.models` — use `--served-model-name qwen3.8-27b-vllm`
   (repeatable flag; response `model` field = first name) rather than the HF path [78];
   (c) a *selector* ID must not collide with any model/alias/qualified-peer name [53];
   (d) the `.opencode/opencode.jsonc` catalog row uses whatever ID lands in
   `/v1/models` (qualified peer ID, unqualified unique ID, or selector ID) — 1:1
   mapping is unchanged.
3. **Auth is layered and currently edge-only.** llama-swap top-level `apiKeys` is
   empty in this repo (default-allow) [repo]; the public chain's Keycloak SSO is the
   actual gate, and `/ui` is already as exposed as `/v1` is today [repo EXPLORE §1].
   Keep the vLLM peer **keyless in-cluster** (no `peers.vllm.apiKey`, no
   `--api-key` on vLLM) unless the owner wants defense-in-depth — if added, it must
   flow through `${env.*}` + a Bitwarden `custom-values` entry (the
   `llama-swap.bitwardenIds` pattern) because an unset env var **hard-fails config
   load** [57][repo]. Note for the future: `apiKeys` (top-level) is the knob that also
   locks the web UI [57]. vLLM's own CORS defaults changed in v0.32 (no longer
   all-origins) [79] — irrelevant behind llama-swap, relevant only if anyone points a
   browser UI straight at the vLLM pod.
4. **Session-activity tracking headers are not sent by the fleet today.** The
   Activity page groups sessions by `ui.activity.session_id` headers (default
   `X-Session-ID`, `X-Litellm-Session-Id`) [62][repo schema] — but **grep of
   `.opencode/` + `.rulesync/` finds zero references to either header**: nothing in the
   agent-fleet config sends them, so agent traffic (llama.cpp *and* future vLLM) shows
   as ungrouped per-request rows. This is a pre-existing property of the deployment,
   not a vLLM regression; fixing it is a client-side header story (AI SDK
   `headers`/fetch wrapper) if session attribution ever matters — recorded as open
   question 5.
5. **llama-swap cannot touch a peer's lifecycle.** No start/stop/TTL/sleep for peer
   models [51] — vLLM is *always on* from the proxy's perspective. Any R9700
   time-sharing with Strata (R1 OQ6) must be implemented at the pod level (vLLM
   `--enable-sleep-mode` + `/sleep`/`/wake_up` API calls, operator- or cron-driven),
   not via llama-swap. (`vllm-wrapper` sleep/wake exists but only for the
   local-`cmd` pattern, where vLLM is a child process [56].)
6. **Overload semantics differ from llama.cpp.** llama-swap queues requests while a
   model loads; vLLM admits into its scheduler and (since v0.29) can hard-reject with
   429 via `--max-num-queued-reqs`/`--max-num-queued-tokens` (default:
   `max_num_seqs`-derived limits, `vllm:admission_rejections` metric) [80][81][71].
   llama-swap `concurrencyLimit`/`globalConcurrencyLimit` 429s happen *before* the hop
   [60]. The plan should pick admission knobs deliberately (3–4 concurrent sessions →
   `--max-num-seqs 4` class; queue caps optional) and expect the agent harness to see
   429s under saturation, not silent queues.
7. **Keep-alive 502-EOF after a stream: documented failure class, no peer knob.**
   Upstreams that advertise keep-alive on streamed responses but then close the
   connection cause a 502 `proxy error: EOF` on the *next* request reusing that
   connection; llama-swap's fix (`disableKeepAlives: true`) exists **only on
   `models.*`, not on `peers.*`** (verified in both the pinned v266 schema and current
   upstream schema) [58][62][70]. vLLM/uvicorn's post-SSE connection behavior is not
   publicly documented — watch for it in the first week; if it bites, the options are
   an upstream llama-swap feature request or a vLLM-side uvicorn keep-alive tuning
   (no clean knob documented today).
8. **`maxRequestBodyMB` (v266+):** defaults 250 MB [63] — 256k-token prompts (~1 MB
   JSON) pass comfortably; no action needed, noted so the number isn't "explained"
   later.
9. **UI subpath (if ever needed):** llama-swap has no base-path setting; serve
   behind a prefix only with a *prefix-stripping* proxy (v266 made the UI
   base-path-agnostic) [59][63]. Not needed today (whole-host ingress).

### Contradictions and how to weigh them

1. **The user's premise "the old `vllm/serve` frontend" vs reality.** vLLM never
   shipped a server web UI; the only "Web UI" issue in the tracker was the *docs site*
   [75], and the one server-dashboard proposal is an 8-month-stalled community draft
   with auth/history explicitly out of scope [74]. *Weigh:* answer the card as "no, it
   doesn't come with one; here is who has made one" — and do not plan any vLLM-side
   UI surface; watch PR #32256 as a free future upgrade.
2. **"vLLM is first-class in llama-swap" vs the peer-path gaps.** First-class
   (README, `owned_by` reader, usage parsing, vllm-wrapper) targets the
   *local-process* deployment shape [50][55][56][64]; the *peer* shape gets
   "any OpenAI-compatible server" treatment: solid routing/listing/UI, but no
   lifecycle control, no `disableKeepAlives`, and post-pin usage-parsing rework [51][58][70][68].
   *Weigh:* both are true — plan the peer hop as fully supported for routing/UX, and
   keep lifecycle/EOF/accuracy items as explicit watch-outs (Q5.5/7), not assumptions.
3. **Pinned v266 vs upstream v269.** Everything the plan needs is in the pin [62][63];
   the v269 per-upstream usage-extraction refactor (vLLM named) and UI category
   grouping are niceties [63]. *Weigh:* no blocking; the open token-accounting issue
   #1218 [68] is the one to keep on the radar for Activity accuracy.
4. **"Lightest UI with no extra DB/auth" splits into two answers.** For *chat*:
   Open WebUI is the lightest server-side (SQLite, built-in auth) [85][86][87] but is
   still a full app with its own user store (a second identity surface next to
   Keycloak). For *live state*: the lightest is the already-deployed llama-swap `/ui`
   [50][54] + the already-existing Grafana [72] — which is why the recommendation
   leads with reuse instead of adding a chat app.
5. **vLLM-SR dashboard "real-time monitoring" vs adopting it.** The only
   vLLM-ecosystem UI rendering Prometheus natively is the semantic-router's dashboard,
   and that dashboard is the operator UI of a *competing routing layer* (signal-driven
   MoM router, K8s/compose stack) [83]; llm-d (its platform root) likewise is
   Prometheus/Grafana/OTel, not a standalone UI [84]. *Weigh:* do not adopt semantic
   router or llm-d to get a UI — llama-swap already holds the routing role in this
   fleet; the dashboard is a different architecture's cockpit.

### Implications for the plan

- **The UI ask resolves to a values change, not a service.** Plan chunk:
  `peers.vllm: {proxy: http://<vllm-svc>.default.svc.cluster.local:8000, models:
  [<served-name>], timeouts: {responseHeader: <TTFT-sized, Strata 1800 precedent>}}`
  plus (optional, recommended if a stable single ID is wanted for agents)
  `selectors.<id>: {strategy: warm|spillover, targets: [<vllm peer model>, <llama.cpp
  rungs>…]}` — all in `services/gpu-ai/prod/values.yaml`, schema-validated by the
  existing golden/parity harness (the v266 schema test gate already covers
  `peers`/`selectors` blocks [repo EXPLORE §8.5]).
- **vLLM engine recipe additions** from this round: `--served-model-name
  qwen3.8-27b-vllm` (naming, Q5.2), `--max-num-seqs 3-4` + queue admission decision
  (Q5.6), `--enable-sleep-mode` kept available for the R9700 time-sharing ruling
  (Q5.5), `/health` as the startup/readiness probe path (Q3 table) [78][80][56][98].
- **Observability split is the plan's second UI answer**: llama-swap `/ui` =
  per-request ops view (already there); vLLM `/metrics` → PodMonitor → central
  Prometheus → Grafana official vLLM dashboards = engine view (R5 chunk). Name the
  dashboards in the R5 chunk so the "UI" question closes with a linkable panel, not a
  promise [71][72].
- **Open WebUI = optional follow-up, explicitly out of the vLLM chunk** if the owner
  wants a browser chat client: one chart + ingress trio, connect to `…/v1` via the
  documented `OPENAI_API_BASE_URL`/Connections flow, `AIOHTTP_CLIENT_TIMEOUT_MODEL_
  LIST` sized for the fleet [85][73]. If declined, the `/ui` playground tab already
  gives a chat test box for any model in the list (peers included [65]).
- **Do not plan** vLLM Playground (manages its own containers [82]), semantic-router /
  llm-d (competing router stacks [83][84]), or LM Studio/Jan as the lab FE (desktop
  workstations [88][89][90]).
- **Test additions for the plan's Commands section:** rendered-config assertions that
  the vLLM peer block and any selector pass the pinned schema (extend the existing
  llama-swap test harness), and an on-target smoke line: `curl /v1/models` shows the
  vLLM model (qualified + unqualified forms), a streamed chat completion through
  llama-swap → vLLM arrives incrementally, and `/ui` models page lists it — this is
  the acceptance for "the FE works", complementing R1's engine benchmark run.

### Open questions (R3)

1. **Does the owner actually want a human browser chat UI** (→ Open WebUI optional
   chunk), or is "a UI" satisfied by llama-swap `/ui` + Grafana for ops? The card
   wording suggests curiosity more than requirement; the default plan answers with
   reuse + dashboards and offers OWUI as a follow-up.
2. **Unified model ID: selector or separate IDs?** A `warm`/`spillover` selector
   exposing "the 27B" across the vLLM peer and llama.cpp rungs is supported in v266
   [53][65], but the *strategy* (prefer-what's-loaded vs vLLM-first-N vs pin) depends
   on the R9700 coexistence ruling (R1 OQ6) and the owner's intent (speed vs engine
   diversity). Plan decision, informed by R1.
3. **Verify on target (5-min smoke):** does the pinned v266 populate the vLLM peer
   model's context length in `/v1/models` (capability discovery applied to peers —
   documented for upstream readers generally [55], peer application inferred from
   [65])? Record `max_model_len` presence/absence in the acceptance run.
4. **vLLM post-SSE keep-alive behavior** (Q5.7): no public data; if 502-EOF appears,
   there is no peer-level `disableKeepAlives` in v266 *or current upstream* [70] —
   file upstream / tune uvicorn. Watch-item for the first week.
5. **Session attribution in Activity**: fleet clients send none of the configured
   session headers today (grep-verified, [repo]); if per-session grouping of agent
   traffic is wanted, that's an AI-SDK client-header change independent of vLLM —
   confirm with the owner whether it's in scope.
6. **Public vLLM host or internal-only?** (interacts with OQ3): the peer hop implies
   internal-only (vLLM reachable via `llama.spencerslab.com/v1` + `/ui` as today); a
   separate `vllm.<domain>` host would need the llama-timeouts transport + proxy-local
   leg and — if browser UIs ever point at it directly — the v0.32+ CORS
   `--allowed-origins` story [79].
7. **Admission/queue caps** (Q5.6): default `max_num_seqs`-derived vs explicit
   `--max-num-queued-reqs`/`--max-num-queued-tokens` — pick at plan time from the
   3–4-session target (R1).
8. **Activity persistence**: give llama-swap a `store.path` (SQLite on a PVC) so the
   vLLM-era activity survives restarts? Currently in-memory only (no `store` in the
   deployed config [repo]) — small persistence addition if the owner values history
   [54][66].

### Sources (R3)

All web sources accessed **2026-11-04** via `global-searxng` + `webfetch`/raw fetches;
upstream docs/KB/PRs fetched from `main` (or the pinned repo schema) unless stamped.
`[repo …]` = in-repo grounding from EXPLORE.md or this session's greps (not web).

50. llama-swap README (github.com/mostlygeek/llama-swap, fetched 2026-11-04): "On-demand model switching for many local AI servers (llama.cpp + forks, **vllm**, stable-diffusion.cpp, audio.cpp, ComfyUI, etc.)"; `vllm` repo topic; "For Python based inference servers like vllm … it is recommended to run them via podman or docker"; Web UI section (playground, token metrics, request/response inspection, manual load/unload, real-time log streaming); nginx reverse-proxy SSE section (`proxy_buffering off` for `/api/events` + `/v1/chat/completions`, llama-swap sets `X-Accel-Buffering: no`, issue #236); `/ui`, `/upstream/:model_id`, `/running`, `/api/models/unload|pause|resume`, profiles API, `/logs/stream/*`, `/health`, `/metrics`; API keys; `useModelName`; Help page = local-model docs agent; `/api/mcp` endpoint: https://github.com/mostlygeek/llama-swap
51. llama-swap KB — Peers: splitting models across machines and providers (`docs/kb/examples/peers-and-multi-host.md`, updated 2026-08-25): peer = "another llama-swap or **any** server providing the `/v1/` endpoints"; path appended to `proxy`; naming (`<peerID>/<modelID>` always, unqualified only when exactly one peer provides it, **local IDs/aliases take precedence**, fully-qualified names reserved and reported by `/v1/models`); `apiKey` injected as Bearer + x-api-key; `timeouts` (responseHeader for cold starts); peer `filters` (`model` protected); spillover selector example with peer targets; caveats (selectors not on `/upstream`, **no peer lifecycle management**): https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/examples/peers-and-multi-host.md
52. llama-swap KB — Route to remote peers (`docs/kb/guides/connectivity/remote-peers.md`, updated 2026-08-28): minimal peer block, `peer-name/model-id` addressing: https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/connectivity/remote-peers.md
53. llama-swap KB — Profiles and selectors (`docs/kb/guides/routing/profiles-and-selectors.md`, updated 2026-08-25): profile pin targets may be local model / **fully qualified peer model** / alias / selector; selectors = virtual IDs resolved per request; `warm` (first ready → starting → cold-start first), `pin` (always first target), `spillover` (reservation count per target, local+remote example); rules (no ID collisions with models/aliases/qualified peer names; targets can't be selectors; not on `/upstream`; profiles run first): https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/routing/profiles-and-selectors.md
54. llama-swap KB — Observability, storage and Activity (`docs/kb/guides/operations/observability-storage-and-activity.md`, updated 2026-10-31): Activity view = recent request timing + model events; three log streams (proxy/upstream/http) with UI tabs + `/logs/stream/<stream>`; `store.path` SQLite persistence for activity rows (in-memory default), `store.persistCaptures` + `captureBuffer` for request/response captures; upstream-specific Activity columns (Hipfire prefill/decode from response `timings`; "If Hipfire reports no decode rate … Decode stays unknown"): https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/operations/observability-storage-and-activity.md
55. llama-swap KB — Model capabilities and model listings (`docs/kb/guides/model-runtime/capabilities-and-model-listings.md`, updated 2026-10-28): auto-discovery probes the upstream once ready, cached in SQLite; **per-upstream readers selected by `owned_by` in the server's own `/v1/models`: `llamacpp`, `vllm`, `halogen`**; vLLM table (context length: yes, `max_model_len`; image/audio/tools: no → set by hand in `capabilities:`); "A model that a never been loaded shows nothing"; discovery cache needs `store.path` to survive restarts: https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/model-runtime/capabilities-and-model-listings.md
56. llama-swap KB — Fast vLLM swapping with vllm-wrapper (`docs/kb/guides/tools/vllm-wrapper.md`, updated 2026-10-23): `vllm-wrapper serve`/`sleep` as `cmd`/`cmdStop`; vLLM must run `--enable-sleep-mode` (answers `/sleep`, `/wake_up`); `--health-path /health` default; `--wait-timeout` for cold starts; `--stop-pid ${PID}` requirement; failure modes (first-swap timeout, VRAM not freed, process-group kill): https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/tools/vllm-wrapper.md
57. llama-swap KB — API keys, access control (`docs/kb/guides/api-integration/api-keys-and-auth.md`, updated 2026-08-25): default-allow; Bearer / x-api-key / Basic; **web UI and `/api/` covered**; `${env.*}` macros (unset = hard config-load failure); `peers.*.apiKey` = outgoing key only; "apiKeys is not a substitute for a firewall": https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/api-integration/api-keys-and-auth.md
58. llama-swap KB — Proxy and model startup timeouts (`docs/kb/guides/connectivity/proxy-timeouts.md`, updated 2026-10-07): **502 "proxy error: EOF" right after a stream** (upstream advertises keep-alive on streamed response then closes; retry succeeds; fix `disableKeepAlives: true` — a `models.*` key): https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/connectivity/proxy-timeouts.md
59. llama-swap KB — Serving under a reverse proxy subpath (`docs/kb/guides/connectivity/reverse-proxy-subpath.md`, updated 2026-11-14): no base-path setting; prefix must be stripped; UI follows the prefix via relative paths: https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/connectivity/reverse-proxy-subpath.md
60. llama-swap KB — Routing capacity and request queues (`docs/kb/guides/routing/capacity-and-queues.md`, updated 2026-09-10): router serializes swaps and queues until the model is ready; `models.*.concurrencyLimit` (429 above); `globalConcurrencyLimit` (shared semaphore, **429 immediately, no queue**): https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/routing/capacity-and-queues.md
61. llama-swap KB — kubeswap: a complete multi-engine Kubernetes configuration (`docs/kb/examples/kubeswap-kubernetes.md`, updated 2026-09-14): llama-swap models as K8s workloads via `cmd`/`cmdStop` + kubeswap wrapper (DRA resource claims, PVC model cache, exclusive swap groups) — the *alternative* architecture where llama-swap owns engine pods: https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/examples/kubeswap-kubernetes.md
62. llama-swap `docs/config.example.yaml` (main, fetched 2026-11-04): annotated `ui.activity.session_id: ["X-Session-ID","X-Litellm-Session-Id"]`, `selectors` (warm/pin/spillover + rules), `routing` (group/matrix; upstream main adds `capacity`), `peers` (all rules incl. "local model IDs and aliases take precedence over unqualified peer model IDs"), `hooks`, `profiles`: https://raw.githubusercontent.com/mostlygeek/llama-swap/main/docs/config.example.yaml
63. llama-swap CHANGELOG (fetched 2026-11-04): **v266 (Oct 22, 2026)** = lab pin (UI base-path agnostic, `maxRequestBodyMB`, kubeswap DRA); **v267** capacity router + Help-agent source search; **v268** pause/resume; **v269 (Oct 31)** per-upstream usage extraction (llama-server, **vLLM**, Anthropic, OpenAI, TabbyAPI, oMLX, auto fallback; records task/route/**peer**/reasoning tokens in Activity — PR #1292), UI capability categories, PNG activity export, persistent captures; v237 "support vLLM metrics" (#910); v238 improved vLLM response metric calculation (#913); v241 selectors (#942) + profiles (#935); v242 peer namespaces (#950) + activity SQLite (#898); v243 vllm-wrapper (#941); v246 selectors on Models page (#975): https://raw.githubusercontent.com/mostlygeek/llama-swap/main/CHANGELOG.md
64. llama-swap PR #910 (merged 2026-07-10, v237) — "internal/server: support vLLM metrics": "Read vLLM usage token counts and response generation speed from completion responses … parse tokens_per_second from non-streaming metrics; retain streaming metrics from final events; cover both vLLM response modes": https://github.com/mostlygeek/llama-swap/pull/910
65. llama-swap PR #950 (merged 2026-07-25, v242) — "internal/server,ui-svelte: add peer model namespaces": "Address peer models by fully qualified names across routing, selectors, model listings, **and the UI** … support peer models in selector spillover targets; **show peer models in Playground model pickers**": https://github.com/mostlygeek/llama-swap/pull/950
66. llama-swap PR #898 (merged 2026-07-07, v242) — "internal/store: persist activity metrics to sqlite": `store.path`, activity pagination/stats APIs, durable activity history: https://github.com/mostlygeek/llama-swap/pull/898
67. llama-swap PR #942 (merged 2026-07-22, v241) — "internal/server: implement selectors" (pin/warm/balance; rules incl. selector-ID collision protection, no selector-in-selector, not on `/upstream`): https://github.com/mostlygeek/llama-swap/pull/942
68. llama-swap issue #1218 (OPEN, 2026-10-10) — "bug: prompt and cached token values vary by backend": https://github.com/mostlygeek/llama-swap/issues/1218
69. llama-swap selector issues — #1240 (OPEN, 2026-10-17) "strategy: warm falls back to targets[0] while that target is stopping"; #945 (OPEN, 2026-07-22) "Automatic failover strategy for selector" (feature request): https://github.com/mostlygeek/llama-swap/issues/1240 ; https://github.com/mostlygeek/llama-swap/issues/945
70. llama-swap `config-schema.json` (main, fetched 2026-11-04) — peer object keys: `apiKey, filters, models, proxy, tailcatKey, timeouts` (**no `disableKeepAlives`, no `useModelName` at peer level**); top-level adds `helpagent`, `security` (cors) vs the pinned v266; lab pin: `charts/llama-swap/tests/schema/config-schema.v266.json` (read this session: `peers`/`ui.activity`/`routing.{scheduler.fifo.priority,router.group|matrix}`/`selectors`/`store.path`/`apiKeys`/`globalConcurrencyLimit`/`security.cors`/`maxRequestBodyMB`/model-level `useModelName`, `checkEndpoint` (default `/health`, progress JSON), `concurrencyLimit`, `unlisted`, `timeouts`): https://raw.githubusercontent.com/mostlygeek/llama-swap/main/config-schema.json
71. vLLM docs — Production Metrics (fetched 2026-11-04): `/metrics` on the OpenAI-compatible API server, enabled by default; general metrics table incl. `vllm:kv_cache_usage_perc`, `vllm:num_preemptions`, `vllm:prefix_cache_hits/queries`, `vllm:prompt_tokens`/`generation_tokens`, `vllm:engine_sleep_state` (awake / weights_offloaded / discard_all), `vllm:admission_rejections`, `vllm:iteration_tokens_total`; request-level histogram families (e2e latency, queue time, TTFT, inter-token latency) with `--custom-histogram-buckets`; deprecation policy: https://docs.vllm.ai/en/latest/usage/metrics/
72. vLLM repo — `examples/observability/` (fetched 2026-11-04): `prometheus_grafana/` (docker-compose + README: "Prometheus metric logging is enabled by default", import `grafana.json`), `dashboards/grafana/{performance_statistics.json, query_statistics.json}` (35 KB / 25 KB official dashboards), `dashboards/perses/`, `metrics/offline.py`: https://github.com/vllm-project/vllm/tree/main/examples/observability
73. vLLM docs — Open WebUI (fetched 2026-11-04): official integration: run vLLM, start Open WebUI with `OPENAI_API_BASE_URL=http://…:8000/v1`, model appears in the UI: https://docs.vllm.ai/en/latest/deployment/frameworks/open-webui/
74. vLLM PR #32256 (OPEN, **draft: true**, created 2026-01-13, last updated 2026-03-10, `needs-rebase`, merge conflicts flagged 2026-03-03/10) — "[Frontend][CLI] Add --enable-dashboard for vLLM Web UI": `/dashboard` with real-time metrics (running/waiting, TTFT, E2E latency, KV usage, prefix-cache hit rate, 5 s refresh), VllmConfig + `VLLM_*` env panels, Quick Chat, env collection; author: "engine debugging/monitoring tool, not a production vllm chat application"; "Application-side features (auth, history, RAG, etc.) are explicitly out of scope"; "similar to how Prometheus has a basic built-in UI … if you need more, use Grafana": https://github.com/vllm-project/vllm/issues/32256
75. vLLM issue #10090 (closed 2024-11-08, label `documentation`) — "[Misc] Improve Web UI": about the **docs website** (mkdocs "ask AI" button overlapping version selector), not the server: https://github.com/vllm-project/vllm/issues/10090
76. vLLM `rust/README.md` (vllm-frontend-rs, fetched 2026-11-04): "Rust drop-in alternative frontend … rebuild the northbound serving layer in Rust … talking to the core Python vLLM engine process(es) via ZMQ"; **"should still be considered experimental, and is not feature-complete"**; `VLLM_USE_RUST_FRONTEND=1`; `--grpc-port` control services: https://raw.githubusercontent.com/vllm-project/vllm/main/rust/README.md
77. vLLM docs — Architecture Overview (fetched 2026-11-04): "By default, there is 1 API server process, but when data parallelism is used, the API server count automatically scales to match the data parallel size. This can also be manually configured with the --api-server-count flag" (DP load-balancing surface, not a UI): https://docs.vllm.ai/en/stable/design/arch_overview/
78. vLLM docs — `serve` CLI (fetched 2026-11-04): `--served-model-name` repeatable — "If multiple names are provided, the server will respond to any of the provided names. The model name in the model field of a response will be the first name in this list"; `--api-server-count` for DP; cross-ref forum: `--served-model-name` "remains the correct way to set alternative model names" (vllm forums #2277): https://docs.vllm.ai/en/latest/cli/serve/
79. vLLM releases v0.33.0rc3 (2026-11-02), v0.32.0 (2026-10-18), v0.31.0 (2026-10-05) (fetched 2026-11-04): Rust frontend feature line (gRPC control plane: "engine-aware health reporting, abort control, server and model discovery, KV event source discovery"; `--sse-keep-alive-interval` v0.31); v0.32: "Default CORS settings no longer allow every origin in the Python and Rust frontends; set `--allowed-origins` to permit browser origins": https://github.com/vllm-project/vllm/releases
80. ramgpt.org — "vLLM 0.31 Admission Control: Active Sequences vs Queue Limits" (fetched 2026-11-04): queue cap enforced per API-server process; without an explicit active-sequence cap vLLM uses `max_num_seqs` as the admission limit: https://ramgpt.org/articles/vllm-031-active-sequences-scheduler-admission/
81. cometapi community — "vLLM 0.29.0: Should API Admission Limits Bound Queued Requests or Queued Tokens?" (fetched 2026-11-04): v0.29 release notes introduce `--max-num-queued-reqs` and `--max-num-queued-tokens` (PR #49445, queue admission control): https://community.cometapi.com/t/vllm-0-29-0-should-api-admission-limits-bound-queued-requests-or-queued-tokens/794
82. vLLM Playground — official vLLM blog "Introducing vLLM Playground" (2026-01-02, micytao; also on vllm-project community tools page): `pip install vllm-playground`, FastAPI web UI on :7860, **container orchestration via Podman or Kubernetes API** (starts/stops vLLM containers, cross-platform images incl. `vllm/vllm-openai`), chat with structured outputs + tool calling, GuideLLM benchmarking, vLLM-recipes catalog, OpenShift/K8s deploy scripts: https://vllm.ai/blog/2026-01-02-introducing-vllm-playground ; https://github.com/micytao/vllm-playground ; https://pypi.org/project/vllm-playground/
83. vLLM Semantic Router (`vllm-project/semantic-router`, v0.4 docs, fetched 2026-11-04): "open-source routing and control layer for building Mixture-of-Models systems"; apps call a stable OpenAI/Anthropic endpoint while the router chooses/composes the capability path; **Semantic Router Dashboard** = "unified operator UI … Configuration Management, Interactive Playground, Real-time Monitoring & Observability … embedded Grafana dashboard" (React SPA + Go backend proxying router API/Grafana/Prometheus; Docker Compose or K8s): https://vllm-sr.ai/docs/intro/ ; https://vllm-sr.ai/docs/v0.1/tutorials/observability/dashboard/ ; https://github.com/vllm-project/semantic-router
84. llm-d — Observability docs (fetched 2026-11-04): "Monitor and debug llm-d deployments with Prometheus metrics, Grafana dashboards, and OpenTelemetry distributed tracing" (platform-level, no standalone UI): https://llm-d.ai/docs/operations/observability
85. Open WebUI docs — vLLM quick start (fetched 2026-11-04): "vLLM provides an OpenAI-compatible API (Chat Completions), making it easy to connect to Open WebUI"; Settings → Admin → Connections → Add Connection (URL + Bearer auth); `AIOHTTP_CLIENT_TIMEOUT_MODEL_LIST` (default 10 s) for slow model listing: https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-vllm/
86. Open WebUI docs — RBAC Roles (fetched 2026-11-04): "First User: The very first account created on a fresh installation is automatically assigned the Admin role"; headless admin creation supported: https://docs.openwebui.com/features/authentication-access/rbac/roles/
87. Open WebUI discussion #11666 (fetched 2026-11-04): signups auto-disabled after the first user is created (code-level: `if user_count == 0: ENABLE_SIGNUP=False`): https://github.com/open-webui/open-webui/discussions/11666
88. Jan docs — Custom Endpoints (fetched 2026-11-04): "Jan can connect to any endpoint that speaks the OpenAI or Anthropic wire format. This covers self-hosted servers (**vLLM**, Ollama, LocalAI, llama.cpp server, TGI) …" (desktop app): https://docs.jan.ai/desktop/remote-models/custom-endpoint
89. LM Studio docs — OpenAI Compatibility Endpoints (fetched 2026-11-04): LM Studio *exposes* an OpenAI-compatible server API (base-URL swap for clients) — its documented role is server-side: https://lmstudio.ai/docs/developer/openai-compat
90. lmstudio-universal-endpoint (fetched 2026-11-04): community **plugin** "for connecting the chat UI to any OpenAI-compatible API without a fixed model list" (Base URL + API key + model ID) — remote-client capability is plugin-based, not first-class chat-UI surface: https://github.com/J0hnSm1thyk/lmstudio-universal-endpoint
91. LibreChat docs — Local install with Docker (fetched 2026-11-04): default Docker Compose ships MongoDB (AVX CPU note); the platform's data layer is MongoDB (+ Redis for scale-out): https://www.librechat.ai/docs/local/docker
92. server-sent-events.com — Configuring Caddy and Traefik for SSE (fetched 2026-11-04): "Caddy and Traefik are both written in Go, and both inherit a convenient behaviour from Go's reverse-proxy machinery: responses with `Content-Type: text/event-stream` are flushed to the client immediately rather than on an interval … SSE work out of the box"; remaining risks: **compression middleware**, **timeouts** capping long responses, upstream content-type before first byte: https://www.server-sent-events.com/sse-protocol-fundamentals-architecture/proxy-and-cdn-configuration-for-sse/configuring-caddy-and-traefik-for-sse/
93. dev.to (libme) — "Token Streaming Works Locally but Arrives All at Once in Production" (fetched 2026-11-04): "nginx buffers proxied responses by default (proxy_buffering on)"; SSE/chunked responses are the class where buffering destroys streaming: https://dev.to/libme/token-streaming-works-locally-but-arrives-all-at-once-in-production-finding-the-buffer-1o9g
94. DimitrovK/sse-proxy-buffering-harness (fetched 2026-11-04): test harness measuring whether **nginx, Caddy, Traefik and HAProxy** pass SSE streams through incrementally: https://github.com/DimitrovK/sse-proxy-buffering-harness
95. vLLM source — `vllm/entrypoints/openai/models/serving.py` (main, fetched 2026-11-04): `show_available_models()` returns `ModelCard(id=…, max_model_len=…, root=…, permission=…)` — vLLM's `/v1/models` carries `max_model_len` (the field llama-swap's vLLM reader consumes [55]): https://raw.githubusercontent.com/vllm-project/vllm/main/vllm/entrypoints/openai/models/serving.py
96. dev.to (rosgluk) — "Monitor LLM Inference in Production (2026)" (fetched 2026-11-04): vLLM exposes Prometheus-compatible `/metrics` "with the `vllm:` prefix, including gauges like running requests and KV cache usage": https://dev.to/rosgluk/monitor-llm-inference-in-production-2026-prometheus-grafana-for-vllm-tgi-llamacpp-1o1h
97. markaicode — "Open WebUI Production Architecture: Postgres, Redis, K8s" (fetched 2026-11-04): "a production Open WebUI deployment replaces the **default single-container SQLite setup** with PostgreSQL … and the Redis-backed WebSocket manager so multiple backends…" — i.e. SQLite/single-container is the default, Postgres/Redis only for multi-replica: https://markaicode.com/architecture/open-webui-enterprise-deployment/
98. vLLM docs — `/health` endpoint (fetched 2026-11-04): 200 from `client.check_health()`, 503 on `EngineDeadError`; render-only servers always healthy: https://docs.vllm.ai/en/stable/api/vllm/entrypoints/serve/instrumentator/health/

**[repo]** in-repo grounding (this session + EXPLORE.md): pinned v266 schema blocks read directly
(`charts/llama-swap/tests/schema/config-schema.v266.json`: `peers.*.{proxy,apiKey,models,filters,timeouts}`,
`ui.activity.session_id` default headers, `routing.{scheduler.fifo.priority,router}`, `selectors.*.{strategy,warm|pin|spillover,targets,settings}`,
`store.path` (SQLite), `apiKeys`, `globalConcurrencyLimit`, `maxRequestBodyMB`, `security.cors`, model-level
`useModelName`/`checkEndpoint` (default `/health`, progress-JSON)/`concurrencyLimit` (429)/`unlisted`);
`services/gpu-ai/prod/values.yaml` Strata peer (`proxy` without `/v1`, explicit `models`, `timeouts.responseHeader: 1800`);
`services/gpu-ai/prod/templates/generic-ingress.yaml` (`llama-timeouts` ServersTransport per subdomain;
`servicestransport-llama.yaml` `responseHeaderTimeout: 0` + `idleConnTimeout: 3600s`); **no Traefik
`compress` middleware anywhere in `services/`/`charts/`** (grep, this session); `.opencode/opencode.jsonc`
gpu-ai provider (baseURL `https://llama.spencerslab.com/v1`, 1:1 model-ID catalog, 2 h header/chunk timeouts);
**zero occurrences of `X-Session-ID`/`X-Litellm-Session-Id` in `.opencode/` + `.rulesync/`** (grep, this session);
no `store:` block in the deployed llama-swap config (activity in-memory today).

### Reliability notes (R3, self-review)

- **High confidence** (primary docs/schema/PRs, mutually consistent): no bundled vLLM
  UI + stalled `--enable-dashboard` draft [74][75][76][79]; `--api-server-count` = DP
  replicas [77][78]; vLLM `/metrics` + official Grafana/Perses dashboards [71][72];
  llama-swap peer/selector/UI semantics (pinned schema + KB + PRs #910/#942/#950/#898
  all predate the v266 pin [62][63][64][65][66][67]); `owned_by: vllm` capability
  reader [55]; `max_model_len` in vLLM model cards [95]; OWUI single-container SQLite +
  first-user-admin [85][86][87][97]; Traefik SSE out-of-the-box + compression/timeout
  risks [92][93][94]; no compress middleware + no session headers in this repo (grep).
- **Medium confidence:** (a) capability discovery *applied to peer models* in the
  pinned v266 — the KB documents per-upstream readers generally [55] and #950 shows
  peer models in listings/UI [65], but a peer-specific vLLM-context probe is inferred,
  not demonstrated; the on-target smoke (open question 3) settles it. (b) llama-swap
  Activity quality for vLLM *peer* requests — vLLM usage parsing is proven for the
  local path (#910 [64]) and peer rows exist (#950 [65], #1292 records `peer` [63]),
  but the token-accounting drift issue is open (#1218 [68]). (c) vLLM admission/429
  behavior summaries rest on v0.29/v0.31-era third-party writeups [80][81] + the
  metrics table [71] — directionally solid, exact defaults engine-version-dependent.
- **Weakest claim:** "no SSE risk through the lab's public chain" — it is *inferred*
  from (i) Go reverse-proxy flush semantics [92], (ii) absence of compression
  middleware in-repo (grep), (iii) the existing working llama.cpp streaming chain, and
  (iv) `responseHeaderTimeout: 0` [repo]. Nobody has measured the exact
  Traefik→llama-swap→vLLM path; the first streamed vLLM response through the public
  host is the verification (acceptance smoke).
- **Perspective weighting:** llama-swap evidence is unusually strong because the
  upstream maintainer documents vLLM support explicitly (README, KB, wrapper, PRs) —
  the main risk is *version drift* (pin v266 vs main [63][70]), which is renovate-
  resolved over time and does not block. The vLLM-side evidence for "no UI" is
  primary (tracker + releases + rust README). Community UI claims (Playground,
  semantic-router dashboard) are single-vendor/first-party-blog sourced [82][83] —
  adequate for "exists and what it is", not for operational maturity.
- **Blind spot** (nothing found): no public end-to-end report of vLLM *as a
  llama-swap peer* behind a public ingress (the Strata peer is in-repo precedent but
  Strata is not vLLM); no public data on vLLM/uvicorn post-SSE keep-alive behavior
  (the 502-EOF class is documented for llama-server [58] only); no source on whether
  Open WebUI's model-list poller copes with llama-swap's 2 h provider timeouts at the
  OWUI hop (mitigation documented: `AIOHTTP_CLIENT_TIMEOUT_MODEL_LIST` [85]).

---

## R4 — Card `Priority` → inference scheduling: vLLM priority semantics, llama-swap pass-through, agent-context carriers (dedicated round)

User's exact ask: *"One thing I'm particularly excited about vLLM for is the priority
settings. Please research this option and identify what needs to change to support
setting it as a custom field on cards. I already added it to the board as Priority, so
will likely just need agent context changes."*

Board fact (live-verified in EXPLORE §6, not re-derived): `Priority` custom field is
NUMBER type, id `fp5vnD5YrA7oAxPiK`, `settings: {}` (no min/max), `always_on_card:
true`; `get_card` is the only source of `custom_fields` `[{id, value}]`; the
claim-time `preload_board` payload does NOT carry it.

STORM method note: interviews ran in-session (no subagent fan-out), grounded in
`global-searxng` + direct source fetches plus in-repo/binary reads; all web evidence
accessed **2026-11-04**. Citation keys `[n]` continue R3's numbering.

### TL;DR

- **vLLM has real request-level priority today, in the v0.33 image class**: `priority`
  in the completions/chat-completions body (int64, default 0, **lower = handled
  earlier**) plus an `X-Vllm-Priority` header (integer, overrides body), both
  documented for v0.33.0; non-zero values **raise an API error unless the server runs
  `--scheduling-policy priority`** (default `fcfs`) [99][106].
- **Under the priority policy the scheduler admits by (priority, arrival) order and,
  on KV exhaustion, force-preempts the LOWEST-priority running request by recompute**
  (V1 has no swap mode) — so priority is not TTFT-only; it decides which running
  requests get killed under memory pressure [103][104].
- **llama-swap passes the body field through unchanged by default** (filters are
  opt-in rewrites; `model` is the only protected param) [109][111] — but its own
  `fifo.priority` is a **static per-model** queue-ordering knob that **never applies to
  peer traffic** (peers are always ready → fast path, never queued) [110].
- **The agent-side carrier exists in the installed OpenCode v2.1.4**: provider/model
  (and per-variant) `headers` + `body` config merges — verified in the binary's
  compiled schema — so a model row with `body: {"priority": N}` sends N on **every
  request** of that model; the lab's machine-global agents already use the same
  `request.body` machinery [112][repo].
- **Verdict: the user's instinct is right** — the change is (1) agent-context skills
  (roster/D12 carve-out, `pipeline-models` class table, kickoff/STATE.json record),
  (2) vLLM model rows in `.opencode/opencode.jsonc` carrying the class value, (3) one
  vLLM serve flag. What is NOT possible today: per-request *dynamic* values (config is
  static per model row), any effect on llama.cpp/Strata traffic, and priority-based
  admission caps (none exist on either proxy or engine) [99][103][106][109][110][112].

### Q1 — vLLM's own priority semantics today

**API surface (both in the v0.33.0 versioned docs — the lab's image class [R1-2]).**

- **Body field.** The Completions and Chat Completions request schemas carry
  `priority: int = Field(default=0, ge=_INT64_MIN, le=_INT64_MAX, description="The
  priority of the request (lower means earlier handling; default: 0). Any priority
  other than 0 will raise an error if the served model does not use priority
  scheduling.")` — i.e. any signed 64-bit int, no 0–100 range, and a **hard error
  gate** on non-zero values when the server runs `fcfs` [99]. (The same field appears
  on both API schemas; the Responses API at least takes the header [99].)
- **Header.** "The Completions, Chat Completions, and Responses APIs also support the
  `X-Vllm-Priority` request header. Its value must be an integer and **overrides the
  `priority` value in the JSON request body**. Non-zero priorities require the server
  to use priority scheduling." The docs example sends `-10` (negative values are
  legal) [99][100]. Provenance: RFC #6077 (2024-07) → PR #5958 introduced priority
  scheduling [101]; the header itself landed 2026-08-06 via PR #51089 answering issue
  #51023, whose stated motivation is exactly this lab's topology — *"operational side
  wants to adjust request priority via HTTP header at an intermediate proxy/LB, an
  order of magnitude easier than parsing and rewriting the JSON request body"* [102].
  A third-party client (earendil-works/pi) documents the same convention: "vLLM 0.28+;
  lower value = handled earlier, default 0" [119]. The numeric convention is **vLLM's
  own** — OpenAI's "priority" is a different thing (a paid `service_tier` string:
  `fast`/`priority` processing tiers, not a per-request scheduling integer) [118].
- **Session identity.** The same schemas now carry `session_id`: "Stable session
  identity shared by related requests. Unlike `request_id`, this value is expected to
  remain stable across multiple requests in the same conversation or **agent
  session**" [99]. It is an *identity*, not a priority carrier — there is no
  per-session priority registry server-side.

**Scheduler semantics (v1 engine, current source + v0.33 docs).**

- `--scheduling-policy`: `fcfs` (default) | `priority`; "priority" = "requests are
  handled based on given priority (lower value means earlier handling) and time of
  arrival deciding any ties" [106][105].
- The **waiting queue is a policy-ordered heap**: "requests with a smaller value of
  priority are processed first. If multiple requests have the same priority, the one
  with the earlier `arrival_time` is processed first" [104].
- **Preemption (the load-bearing part).** In the v1 scheduler, when a waiting request
  cannot get KV blocks, the scheduler force-preempts a running one — victim selection
  is policy-dependent [103]:
  - `PRIORITY`: `preempted_req = max(self.running, key=lambda r: (r.priority,
    r.arrival_time))` — the **lowest-priority** (highest number) running request,
    newest arrival breaking ties; if the freed blocks still don't fit, it can
    "preempt itself" and the scan continues to the next-lowest-priority runner.
  - `FCFS`: `self.running[-1]` — the most recently admitted request.
  - `_preempt_request` then **frees all KV blocks and sets
    `num_computed_tokens = 0`** — pure **recompute**: the victim returns to the
    waiting queue and re-prefills from scratch. V1 has **no swap mode** (`--preemption-
    mode` does not exist in current engine args; swap was the v0 story) [103][106].
- **Answering the two sub-questions directly:**
  - *"Is preemption disabled by default?"* **No.** Preemption is always active under
    KV exhaustion in either policy; `--scheduling-policy` only changes **which**
    request is the victim (newest under fcfs, lowest-priority under priority).
  - *"Does priority affect TTFT only?"* **No.** It affects (a) admission order from
    the waiting queue → TTFT of queued requests, and (b) preemption victim selection
    → under memory pressure, low-priority *running* requests lose their KV and are
    re-prefilled (their ITL/total time suffers; the high-priority side is
    unimpeded). It does **not** change decode speed of non-victim running requests.
- **History note:** an early maintainer answer (issue #3058, v0.x era) said priority
  only moved requests to the front of the waiting queue and did "not … take
  precedence over already running low priority requests" — that was superseded: the
  current v1 code does exactly that forced preemption [107][103].
- **Starvation.** The ordering is strict `(priority, arrival_time)` with **no aging**
  in v1 [103][104]; sustained higher-priority traffic can starve lower-priority
  requests indefinitely (the standard priority-scheduling caveat; the per-priority
  observability gap is below).
- **Per-session/per-card expressibility.** Priority is a per-request attribute; a
  client can set a different value on every request, and the same value on every
  request of a session — which is exactly the "per-card" shape (a card's value is
  constant for its run). There is no server-side per-user/per-session mapping [99].

**Admission / queue knobs (all static, all priority-agnostic).**

- `--max-num-seqs`: max sequences per iteration; also sizes the model runner and is
  the default admission limit [106].
- `--max-num-batched-tokens`: token budget per engine step (chunked-prefill
  interleaving; TTFT under load) [106] (see also [R1-8]).
- `--max-num-queued-reqs`: max **in-flight (waiting or running)** requests; over it
  → **HTTP 503** "so the client can retry on another instance"; enforced in the API-
  server process across all DP ranks; "primarily a coarse capacity valve" [106].
- `--max-num-queued-tokens`: max prompt tokens in the prefill backlog; over it →
  503; documented as a **TTFT QoS** mechanism ("set to `target_TTFT *
  prefill_throughput`") [106].
- `--max-num-active-seqs`: lowers only the RUNNING admission count (decode batches)
  without shrinking runner capacity [106].
- `--watermark`: fraction of total KV blocks kept free when admitting waiting or
  **preempted** requests — "helps avoid frequent KV cache eviction and the resulting
  repeated preemption of requests when GPU memory is scarce"; default `0.0`
  (disabled) [106]. The natural companion knob for a priority deployment on a small
  KV pool (R1's 32 GB budget).
- **No priority-aware admission exists**: the 503 caps reject regardless of priority
  value, and there is no per-priority queue length or reservation [106].
- **Observability gap**: no per-priority metrics today (open feature request #58077
  confirms priority scheduling is "supported and actively improved (preemption
  ordering, KV-cache eviction, admission control)" but unobservable per priority);
  what exists: `vllm:num_preemptions`, `request_num_preemptions` histogram family,
  `vllm:num_requests_running/waiting` [108][R3-71][106].

### Q2 — llama-swap v266: per-model vs per-request priority, and pass-through

**`routing.scheduler.settings.fifo.priority` — what it is (pinned schema, v266 tag
source, both read this session).**

- Per-**model** static integer: "Keys are model IDs, values are integers (default
  0). **Higher values are serviced first**" [111]. The **polarity is inverted vs
  vLLM** (llama-swap: higher = first; vLLM: lower = first) — any mapping must
  convert, not copy.
- From the **pinned v266 source** (`internal/router/scheduler/fifo.go` at tag `v266`,
  logic byte-identical to current main — drift checked): the FIFO decision tree's
  **fast path** ("target process already ready, nothing to evict, no colliding
  in-flight swap → grant immediately") bypasses the queue entirely; a request is
  **enqueued only** when it (4) collides with an in-flight swap, (5) would evict a
  still-busy process, or waits on a load — and `enqueue` inserts "in priority order:
  … higher-priority models are serviced first while equal-priority requests keep
  their arrival (FIFO) order. Priorities come from the FifoConfig; unlisted models
  default to 0" [110]. `admit` enforces per-model `concurrencyLimit` (429, **no
  queue**) [110][R3-60].
- **Consequence for this topology: the knob cannot affect vLLM peer traffic at
  all.** A peer is an always-ready upstream ("does not manage the peer's lifecycle"
  [R3-51]): its requests always take the fast path, so `fifo.priority` never sees
  them. It only orders *local* llama.cpp load/swap contention (e.g. two agents
  competing for the 27B-q4 rung while it loads). It is a **config-time per-model
  constant** — there is no runtime channel to set it from a card (changing it =
  editing the llama-swap ConfigMap + reload; `LLAMA_SWAP_WATCH_CONFIG: true` hot-
  reloads [EXPLORE §1]).
- **Adopting `routing` at all is a migration**: the schema says a config "must not
  use both styles" (routing vs the legacy top-level `groups`/`matrix`), and the
  deployed config is legacy-matrix [111][EXPLORE §1]. Only relevant if the plan ever
  wants option B below.
- `hooks` in v266 supports **only `on_startup`** — no per-request hook to rewrite a
  body field from card state [111].

**Does a per-request `priority` survive the peer proxy? Yes, by default.**

- The pinned schema + KB describe filters as **opt-in body rewrites**: `stripParams`
  "Comma separated list of parameters to remove from the request"; `setParams` sets
  values ("`key?`" = set-if-undefined, so a client-supplied value **wins**); "`model`
  is a protected param and can never be overridden or stripped"; pipeline order is
  `stripParams | setParams [| setParamsByID]` → "The request is proxied" [111][109].
  With no `filters` block (the deployed Strata peer has none [EXPLORE §1]) the body
  arrives at the peer **verbatim except for the `model` rewrite** to the peer's
  `models:` list entry [109][111]. So a client-sent `priority` (or
  `X-Vllm-Priority` header, which no filter touches) passes through untouched.
- The static-injection surfaces, for the menu below: `peers.<id>.filters.setParams`
  ("For peers this is how you inject provider-specific settings" — a **per-peer**
  constant; `priority?` would be a floor that client values override) and
  `models.<id>.filters.setParams`/`setParamsByID` (the latter **per model ID or
  alias**, `${MODEL_ID}` macro keys, **auto-created aliases** — one loaded model
  serving `id`, `id:high`, `id:low` variants "with different parameters applied", "no
  swap, no reload" — but it exists on **local models only**, not peers) [109][111].

**What it cannot do:** carry a per-card value at runtime. Every llama-swap priority
surface (fifo config, filters) is static per model/peer; the only per-request value
that reaches vLLM is whatever the **client** (OpenCode) puts in the body/header.

### Q3 — The agent-context half: what actually exists to carry a per-card value

**Stack recall** (EXPLORE §2): agents → OpenCode (the OpenChamber-embedded v2.1.4
server) → `gpu-ai` provider (`aisdk:@ai-sdk/openai-compatible`, `baseURL
https://llama.spencerslab.com/v1`, 2 h header/chunk timeouts) → llama-swap (v266,
matrix style) → `peers.vllm` (planned, R1/R3) → vLLM. Model choice happens **at
kickoff** (Model(s) checklist → `pipeline-models` table → `STATE.json
kickoff.models`); everything after that is per-request plumbing.

**OpenCode (the installed v2.1.4 binary — the exact server OpenChamber runs):**
- The compiled config schema in the binary contains, on **provider** entries, a
  `{settings, headers: Record<string,string>, body: Record}` triple, and on **model**
  entries the *same* triple plus `variants: {id, ...triple}` (per-variant
  `settings`/`headers`/`body`); the per-agent surface is `request: {headers, body}`
  (schema identifier `Config.Provider.Request`); the HTTP layer is
  `AI.HttpOptions {body, headers, query}` with an explicit merge of `body`/`headers`
  across the layered options [112].
- The live published schema agrees: `Config.ProviderEncoded = {canonical, name, env,
  package, compatibility, settings, **headers, body**, models}` (`additionalProperties:
  false` at provider level — `headers`/`body` are first-class, not escape hatches)
  and `Config.ModelEncoded = {modelID, …, settings, **headers, body**, capabilities,
  **variants[{id, settings, headers, body}]**, …}` [114]. The docs page documents
  `options.headers` for custom providers (Helicone example: static custom headers)
  [113]; the custom-body-field feature request predates it [115].
- **Lab precedent that this machinery is live and trusted**: the machine-global
  `~/.config/opencode/opencode.json` (not version-controlled) defines its SDLC agents
  with per-agent `"request": {"body": {"temperature": 0.1|0.2}}` — the same
  body-merge surface, already in production in this fleet [repo].
- **Therefore**: a vLLM model row in `.opencode/opencode.jsonc` with
  `body: {"priority": N}` sends `priority: N` in **every** chat-completions request
  for that model. Granularity = **model row** (and variant), static per config.
  Equivalently, a provider-level `headers: {"X-Vllm-Priority": "N"}` works (vLLM
  honors the header; it overrides the body [99]) and headers pass llama-swap
  untouched (it rewrites only `model` in the body and injects auth only when
  configured [109][111]) — but the **body route is the documented default-pass-
  through path and needs no header-forwarding assumption**, so it is the primary
  choice.
- **What does NOT exist in OpenCode today**: per-request or per-session *dynamic*
  body/header values — the config surface is static (per provider / per model / per
  variant / per agent); there is no API or config hook to vary a body field from
  session metadata at call time. (The AI SDK's per-call options exist in the library
  but are not exposed by OpenCode's config surface; per-call custom-body features of
  issue #29592 lineage are not shipped) [112][114][115].

**OpenChamber:** an open-source agentic workspace running **on top of** the OpenCode
server (sessions sidebar, "Sessions in Work", scheduled tasks — the hourly
`/pipeline-boards-hourly` entry point [117][repo AGENTS.md]). Its **"Auto Model
Routing"** picks a model per *prompt* by having a classifier ("Jev") sort each prompt
into settings-defined categories (Trivial/Research/Implement/Hard → model/thinking/
agent), re-evaluated every message [116]. Two readings for this feature:
- It is a precedent that the stack can already switch models **per message at
  runtime** — but it is **prompt-class-driven, settings-configured**, with no card-
  custom-field input surface; it cannot read a WeKan card's Priority.
- It is a future alternative carrier *if* the owner ever wants prompt-level (not
  run-level) routing — recorded, not recommended (category semantics ≠ priority
  semantics, and it would bypass the pipeline's kickoff routing authority).

**Net for Q3:** a per-card value *is* implementable as a **per-run constant** using
only in-repo config + skill text: card `Priority` (read once at kickoff via
`get_card`) → class (mapping table in `pipeline-models`) → model row (class carries
`body: {priority: N}` in `.opencode/opencode.jsonc`) → every request of every
subagent in that run carries N → llama-swap passes it through → vLLM schedules by
it. A per-request *varying* value (mid-run changes, per-stage boosts) is **not**
implementable without an OpenCode upstream feature.

### Q4 — Repo surfaces a card-`Priority`→routing feature must touch, and the mapping menu

**Surface inventory** (each with what the change semantically means):

| # | Surface | File | Change means |
|---|---|---|---|
| 1 | Board CF roster line + D12 ruling | `.rulesync/skills/boards/SKILL.md:16` (source) → `rulesync generate` | Amend "exactly ONE board-level text field — `slug`" to the two-field roster (`slug` + `Priority`, resolved by id/name via `list_custom_fields`); record a D-ruling: **Priority is a *serving-class* field consumed at kickoff; D12 stands that model *choice* still rides the Model(s) checklist** — Priority modifies how the resolved model is served, it does not pick models itself (unless option E's C-leg is adopted). Hard rule: edit the `.rulesync/` source, never the generated `.opencode/skills/` |
| 2 | Kickoff answers + routing record | `.rulesync/skills/boards/SKILL.md:214,228,386` | "the sole routing input is the checked Model(s) items (D12)" gains a sibling bullet: the `Priority` CF value (string→int coercion; `null` = default class) joins the card-provided answers block ("…plus the card's `slug` custom-field value … and its `cardNumber`") and the *resolved class* is recorded in STATE.json + the claim comment alongside `kickoff.models` (the board field itself is never written back by agents) |
| 3 | Kickoff record semantics | `.rulesync/skills/pipeline-kickoff/SKILL.md` | Board runs skip the live round (D1); the kickoff record (`slug`, `worktree`, `models {plan, code}`, `local`, …) gains a `priority: {raw, class}` slot for board runs — the live-kickoff family stays byte-identical unless the owner wants a live question too (the field is board-intake-only) |
| 4 | Routing map | `.rulesync/skills/pipeline-models/SKILL.md` | The role→model table and kickoff picker gain the **priority-class mapping** (number → class → model row) plus the new vLLM rows in "Favorited models in this lab". Single authority the boards skill cites for the resolution (same pattern as "size order … stay in `pipeline-models` — reference it, never duplicate") |
| 5 | STATE.json kickoff record | `pipeline-conventions` + planner write | Machine-readable `kickoff.priority.{raw, class}` so every subagent launch derives its model from the table exactly like the existing `local` flag does |
| 6 | Provider catalog (the actual carrier) | `.opencode/opencode.jsonc` (repo, versioned) — `providers.gpu-ai.models` (or new class-scoped provider rows) | One row per class: `modelID` = vLLM served name, `limit.context`, and **`body: {"priority": N}`** (v2.1.4-verified merge [112][114]); 2 h timeouts inherit from the provider `settings` [repo] |
| 7 | llama-swap values | `services/gpu-ai/prod/values.yaml` (the R3 `config.peers.vllm` block) | Optional static floor `filters.setParams: {"priority?": 0}` (client/class value wins via set-if-undefined [109]); **no other change** — pass-through is the default [109][111]; (B only) the `routing`-style migration |
| 8 | vLLM chart values (new `charts/vllm`, the R1/OQ1 chunk) | serve args | `--scheduling-policy priority` (REQUIRED for any non-zero class), `--served-model-name` (repeatable — one name per class or one shared name [R3-78]), `--max-num-seqs` (R1's 3–4), `--watermark` > 0 for preemption headroom [106] |
| 9 | wekan-mcp | — | **No change.** `get_card` already returns `custom_fields [{id, value}]` [repo call-shapes]; the field is live and `always_on_card` (EXPLORE §6) |
| 10 | Board structure | — | **Already done by the user** (human-owned; no agent board-write) |

**Mapping menu** (the planner picks one, not a blend):

- **A — Priority → vLLM request priority (per-run, static body carrier).**
  Number → class → model row with `body: {priority: N}` → every request of the run
  carries N → vLLM admits by it and preempts against it under KV pressure [99][103].
  Expressiveness: *per-request* in wire terms, *per-card-run constant* in practice.
  Trade-offs: requires the vLLM flag (the engine then runs all traffic under priority
  scheduling — benign; it only changes victim selection and queue order); class count
  bounded by model rows (2–4 sane; arbitrary per-card ints would explode rows — NOT
  viable without per-request OpenCode support); zero effect on non-vLLM engines.
- **B — Priority → llama-swap `fifo.priority`.**
  Static per-model config only; **cannot be per-card at all** (no runtime channel,
  Q2); **zero effect on vLLM peer traffic** (always-ready fast path [110]); would
  need the legacy-matrix → `routing` migration [111]. Only sane use: ordering
  llama.cpp load contention between *local* models — a different feature than the
  user asked. Not recommended.
- **C — Priority → model-tier choice at kickoff.**
  Number → class → *engine/model* (e.g. urgent → vLLM 27B row; background → local
  llama.cpp q4 or Flash). Pure agent-context (surfaces 1–5), no engine flag, no
  carrier body — the "serving" difference is which engine/quanta serves the run.
  Coarsest; most robust (works even if vLLM preemption proves rough on RDNA);
  closest to the user's "just agent context changes" reading.
- **D — Priority → queue admission.**
  **Not expressible today — named so it isn't invented**: vLLM's
  `--max-num-queued-reqs/-tokens` 503s are priority-agnostic caps [106], llama-swap's
  `concurrencyLimit`/`globalConcurrencyLimit` 429s are static and unqueued [R3-60] —
  neither side has per-priority admission queues or reservations.
- **E — Hybrid A+C (recommended default).**
  The class table maps number → (model row **and** body priority) together: urgent
  class = vLLM row with `body: {priority: 0}` (served first, preempts others);
  default class = vLLM row with a higher number (or the single shared row at the
  vLLM default); background class = local llama.cpp row (off vLLM entirely, keeping
  KV-pool headroom for the urgent class). Delivers "the number on the card changes
  how its inference is served" end-to-end with every surface already inventoried, and
  degrades to C if the vLLM flag is dropped.

**Polarity/convention trap (all three layers disagree):** vLLM lower = first [99];
llama-swap fifo higher = first [111]; the board field is unanchored (`settings: {}`,
no min/max [EXPLORE §6]). The mapping table in surface 4 must state the convention
explicitly. Recommended default: board number passes through 1:1 to the vLLM value,
so "1" = most urgent = handled first = matches vLLM's "lower means earlier". The
user's mental direction is an open question (R4 OQ1) — note the side effect: 1:1
means "1" outranks even the unset default 0, so the plan must decide whether unset
cards get a *highest-numbered* default class (they trail every set card) or the
values are shifted (unset = 0 baseline, set cards start at 1… inverting urgency).
Plan decision either way; both are one table row.

### Contradictions and how to weigh them

1. **Early "priority doesn't preempt running requests" (#3058) vs current V1 forced
   preemption** [107] vs [103]. *Weigh:* the code is newer and is the lab's actual
   runtime path (v0.33 = V1 engine), and the versioned docs agree with it; the 2024-
   era answer describes v0 behavior. Plan against forced preemption; the acceptance
   smoke confirms it.
2. **"Priority" means three different things across the stack** (vLLM integer
   scheduling value [99] / OpenAI paid `service_tier` [118] / llama-swap fifo queue
   weight [111]). *Weigh:* the lab targets only vLLM; OpenAI's tier is a billing
   concept (irrelevant); llama-swap's is per-model static. One mapping table owns
   the translation; no skill text may say "priority" without naming the layer.
3. **llama-swap main vs pinned v266 source drift** on FIFO semantics. *Weigh:*
   resolved — the `v266` tag's `fifo.go` carries the identical fast-path/enqueue
   logic [110] and the pin's schema the identical `priority` description [111].
4. **OpenCode docs show `options.headers` (v1 key shape) vs binary/schema show the v2
   `headers`/`body` triple.** *Weigh:* both true — the repo config already uses the
   v2 shape (`package`/`settings` [repo]); the installed v2.1.4 binary's compiled
   schema is the authority for what the running server accepts [112], and the live
   published schema matches the binary [114].
5. **"Pass-through by default" (KB) vs "does the pinned v266 build really not strip
   unknown params?"** *Weigh:* the KB's pipeline model (explicit strip list → set →
   proxy) plus the schema's own framing ("parameters to *remove* from the request"
   [111]) make pass-through the only consistent reading, and the deployed peer has no
   filters at all — but it remains an on-target smoke, not a paper proof (OQ5).

### Implications for the plan

- **Confirm the user's hypothesis, with scope**: "will likely just need agent context
  changes" is TRUE for the card side (surfaces 1–5 + 9 + 10 = skill text + one
  STATE.json field, zero tool code), and the serving-side cost is two lines the
  ticket already carries: one vLLM serve flag (surface 8, inside the vLLM chunk) and
  the class model rows in `.opencode/opencode.jsonc` (surface 6, co-chunked with the
  gpu-ai provider catalog work). No wekan-mcp change, no OpenCode/OpenChamber code
  change, no llama-swap code change, no board write.
- **Plan the classes before the rows**: 2–4 classes, each = one model row with a
  fixed `body.priority`; state the polarity convention in the `pipeline-models`
  table; `null`/unset = default class (OQ1/OQ2).
- **Option E is the recommendation** (A+C hybrid): the only option that both (a) uses
  vLLM's real priority mechanism and (b) stays entirely within existing, verified
  surfaces. Option C alone is the safe fallback if the R1 RDNA caveats
  (`--enforce-eager`, young FP8 path) make the owner distrust preemption on this
  hardware.
- **Acceptance lines for the plan's Commands (on-target; operator-assisted where no
  exec tier):**
  1. *Negative pass-through proof:* vLLM still running `fcfs` (pre-flag), one request
     through the full chain (OpenCode row with `body: {"priority": 5}` → llama-swap
     → vLLM) **must be rejected by vLLM with the non-zero-priority error** [99] —
     proving the body field survived both OpenCode's merge AND llama-swap's proxy.
     Then flip `--scheduling-policy priority`; the same request succeeds.
  2. *Behavioral:* two concurrent sessions of different classes saturating the KV
     pool (R1's `--max-num-seqs`-sized benchmark) — the lower-urgency class shows
     preemptions (`vllm:num_preemptions` / `request_num_preemptions` [106][108])
     while the higher-urgency one does not.
  3. *Record:* claim comment + `STATE.json kickoff.priority` carry the raw number and
     resolved class.
- **R5 coupling:** dashboards will show aggregate preemption/queue metrics, not
  per-priority ones (the gap is upstream open issue #58077 [108]) — name that in the
  monitoring chunk so "watch my priority work" gets an honest panel.
- **Watch-item, not plan-item:** OpenChamber Auto Model Routing [116] if the owner
  later wants *prompt*-level (vs run-level) model switching; it has no card-CF input
  today.

### Open questions (R4)

1. **Number direction convention**: does the user read the board's `Priority` number
   as "1 = most urgent" (matches vLLM's lower-first with 1:1 passthrough) or
   "10 = most urgent" (needs inversion in the class table)? The field has no min/max
   to anchor it. Plan-time user question; default recommendation: 1 = most urgent,
   1:1 passthrough.
2. **Class count and values**: 2 classes (e.g. urgent 0 / normal 10) vs 3 (0/5/10) vs
   "background goes off-vLLM to llama.cpp" (option E's third leg)? Also decides
   whether unset cards outrank or trail explicitly-set ones (the 1-vs-0 ordering
   trap noted in Q4).
3. **Does Priority also move the model-tier (C-leg) or only scheduling (A-leg)?**
   E.g. low-priority cards → local llama.cpp q4 to keep the vLLM KV pool clear, vs
   everyone on vLLM with different priorities. Owner intent ("how its inference is
   served") reads as both; planner picks, owner confirms.
4. **Non-vLLM engines get no per-card priority** (B is not viable per-card, D
   doesn't exist) — acceptable, or does the owner expect local-model fairness too
   (that would be a separate *static* `fifo.priority` decision, not card-driven)?
5. **On-target confirmation of pass-through in the pinned v266 build** (a smoke
   question, not a research one): the KB/schema say default pass-through [109][111],
   but the first vLLM request through `peers.vllm` with a `priority` body is the
   proof — acceptance line 1 doubles as this check.
6. **Prefix-caching interaction**: with `--enable-prefix-caching` (R1's recipe), a
   recompute-preempted request re-prefills — how much of that prompt re-prefill hits
   the prefix cache (i.e. how "cheap" preemption actually is on this pool)? Not
   documented per-arch; measurable in the benchmark run (a medium-confidence claim in
   the notes below rests on it being at least partial).
7. **Per-request dynamic priority is the only genuine capability gap** (static-per-
   model-row carrier only). If the owner wants mid-run priority changes (a "boost
   this stage"), that needs an OpenCode upstream per-call body/headers surface —
   file/watch upstream (issue #29592 lineage [115]) rather than work around it.

### Sources (R4)

All web sources accessed **2026-11-04** via `global-searxng` + direct fetches.
Cross-round re-citations: [R1-n], [R3-n]. `[repo …]` = in-repo grounding (EXPLORE.md,
this session's schema/skill/binary reads).

99. vLLM docs — OpenAI-Compatible Server, **v0.33.0 versioned** (the lab image class; fetched 2026-11-04): "The Completions, Chat Completions, and Responses APIs also support the `X-Vllm-Priority` request header. Its value must be an integer and overrides the `priority` value in the JSON request body. Non-zero priorities require the server to use priority scheduling." (docs example sends `-10`); Completions + Chat Completions schemas carry `priority: int = Field(default=0, ge=_INT64_MIN, le=_INT64_MAX, "The priority of the request (lower means earlier handling; default: 0). Any priority other than 0 will raise an error if the served model does not use priority scheduling.")`; `session_id` field: "Stable session identity shared by related requests … remain stable across multiple requests in the same conversation or agent session": https://docs.vllm.ai/en/v0.33.0/serving/online_serving/openai_compatible_server/
100. vLLM docs — OpenAI-Compatible Server, latest (dev preview; parity check with [99]): https://docs.vllm.ai/en/latest/serving/online_serving/openai_compatible_server/
101. vllm-project/vllm RFC #6077 "[RFC]: Priority Scheduling" (2024-07-02, apatke; closed by PR #5958): priority field in the sequence group (static or dynamic), waiting-queue sorting by policy, "jointly sorting the waiting and running queue … not possible without forcefully preempting" running requests, KV-preservation preemption, batch/interactive co-location motivation, dynamic priority for fairness/starvation as future work: https://github.com/vllm-project/vllm/issues/6077
102. vllm-project/vllm PR #51089 "[Feature] Parse request priority from HTTP header" — **merged into main 2026-08-06** (hence in v0.33.0, Nov 2026); answers issue #51023: "Priority from a header must override any priority found in the request body. The information about the intended priority of requests is often neither of concern, nor even available to individual clients" — proxy/LB-side priority is the documented use case: https://github.com/vllm-project/vllm/pull/51089 ; https://github.com/vllm-project/vllm/issues/51023
103. vLLM v1 scheduler source, `vllm/v1/core/sched/scheduler.py` (main, fetched 2026-11-04): `self.waiting = create_request_queue(self.policy)`; on KV-allocation failure — PRIORITY: `preempted_req = max(self.running, key=lambda r: (r.priority, r.arrival_time))`, FCFS: `self.running[-1]`; self-preemption continue-when-still-short; `_preempt_request`: `self._free_request_blocks(request)` + `request.num_computed_tokens = 0` + `RequestStatus.PREEMPTED` (recompute-only; no swap path in V1): https://raw.githubusercontent.com/vllm-project/vllm/main/vllm/v1/core/sched/scheduler.py
104. vLLM API docs — v1 request queue (fetched 2026-11-04): "A priority queue that supports heap operations. Respects the ordering defined in the Request class, where requests with a **smaller value of priority are processed first**. If multiple requests have the same priority, the one with the **earlier arrival_time** is processed first.": https://docs.vllm.ai/en/latest/api/vllm/v1/core/sched/request_queue/
105. vLLM API docs — `SchedulerConfig.policy` (fetched 2026-11-04): `"fcfs"` = arrival order; `"priority"` = "handled based on given priority (lower value means earlier handling) and time of arrival deciding any ties": https://docs.vllm.ai/en/stable/api/vllm/config/scheduler/
106. vLLM docs — Engine Arguments (latest, fetched 2026-11-04): `--scheduling-policy` (fcfs|priority, default fcfs); `--max-num-seqs` ("Maximum number of sequences to be processed in a single iteration"); `--max-num-batched-tokens` (token budget per iteration); `--max-num-queued-reqs` (in-flight waiting-or-running cap → **HTTP 503**, "coarse capacity valve", enforced in the API-server process across DP ranks, sized ~`data_parallel_size * max_num_seqs` + queue depth); `--max-num-queued-tokens` (prefill-backlog cap → 503, "a TTFT QoS mechanism … `target_TTFT * prefill_throughput`"); `--max-num-active-seqs` (RUNNING-admission cap); `--watermark` (KV-blocks kept free on admitting waiting/preempted requests, "avoid frequent KV cache eviction and the resulting repeated preemption …", default 0.0 disabled); `request_num_preemptions` histogram family; **no `--preemption-mode` in current (V1) args**: https://docs.vllm.ai/en/latest/configuration/engine_args/
107. vllm-project/vllm issue #3058 "Is there a mechanism of priorities when sending a new request" (early-era maintainer answer: priority moves requests to the front of the waiting queue; "This does not, however, lead to new high priority requests taking precedence over already running low priority requests" — superseded by V1 forced preemption [103]): https://github.com/vllm-project/vllm/issues/3058
108. vllm-project/vllm issue #58077 "[Feature]: Per-priority observability for --scheduling-policy priority" (open; confirms priority scheduling "supported and actively improved (preemption ordering, KV-cache eviction, admission control)" with per-priority metrics still missing): https://github.com/vllm-project/vllm/issues/58077
109. llama-swap KB — "Rewriting requests with filters" (`docs/kb/guides/api-integration/filters-and-request-rewriting.md`, updated 2026-09-01): "Filters modify the JSON request body **before it reaches the upstream server**"; `model` is the only protected param; `stripParams` = "comma-separated list of JSON keys to delete" (opt-in); `setParams` "Runs on every request … and overrides whatever the client sent", `key?` = set-if-undefined ("a client that sends its own value wins"); peer use = "inject provider-specific settings"; `setParamsByID` (models only) maps model IDs/aliases to param sets and "**automatically creates a model alias for each key** … All three hit the same running process — no swap, no reload"; order of operations ends "6. The request is proxied": https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/api-integration/filters-and-request-rewriting.md
110. llama-swap **pinned v266 tag** source — `internal/router/scheduler/fifo.go` (fetched 2026-11-04; logic byte-identical to current main): decision tree (1 unknown model / 2 join in-flight swap / **3 fast path: "ready, nothing to evict, and no in-flight swap evicting it → hand back its ServeHTTP immediately"** / 4 collide → queue / 5 would-evict-busy → queue / 6 start swap); `enqueue`: "inserts req into the queue in priority order … higher-priority models are serviced first while equal-priority requests keep their arrival (FIFO) order. Priorities come from the FifoConfig; unlisted models default to 0"; `grantHandler` records `fifo_priority` ctx metadata; `admit` → per-model `concurrencyLimit` rejection (429, no queue): https://raw.githubusercontent.com/mostlygeek/llama-swap/v266/internal/router/scheduler/fifo.go
111. llama-swap pinned v266 schema (in-repo, read this session): `routing` ("Alternative to the legacy top-level 'groups'/'matrix' keys; a config must not use both styles"); `routing.scheduler.use: fifo` ("Only 'fifo' is currently supported"); `routing.scheduler.settings.fifo.priority` ("Per-model priority. Keys are model IDs, values are integers (default 0). Higher values are serviced first."); `peers.*.filters.{stripParams,setParams}` (setParams: "for injecting provider-specific settings", `key?` set-if-undefined, "Protected params like 'model' cannot be overridden", values strings/numbers/booleans/arrays/objects); `models.*.filters.setParamsByID` ("${MODEL_ID}" macro keys); `hooks` = "Only supported hook is on_startup": `charts/llama-swap/tests/schema/config-schema.v266.json` (lines 505–538, 660–686, 766–785, 940–999)
112. **OpenCode v2.1.4 installed binary** (local evidence, read 2026-11-04): `opencode --version` = v2.1.4 at `/home/coder/.nvm/versions/node/v26.5.0/lib/node_modules/@opencode/cli/bin/opencode.exe`; compiled config-schema strings: `Config.Provider.Settings` (timeout/headerTimeout/chunkTimeout/compaction/transport/encoding + open additionalProperties); provider-level triple `p = {settings, headers: Record<string,string>, body: Record}`; model-level triple `f = {settings, headers, body}` spread into `class Config.Model ({modelID, family, name, releaseDate, compatibility, package, ...f, capabilities, variants: o({id, ...f}), cost, disabled, limit})`; `Config.Provider.Request = {headers, body}` (per-agent `request` field); `AI.HttpOptions {body, headers, query}` with layered body/headers merge (`Object.fromEntries(...flatMap(entries...filter(≠void)))`)
113. OpenCode docs — Providers (fetched 2026-11-04): custom-provider keys "npm / name / models / options.baseURL / options.apiKey / **options.headers: Optionally set custom headers**"; Helicone example with a static `options.headers` map: https://opencode.ai/docs/providers/
114. OpenCode live config schema (opencode.ai/config.json, fetched 2026-11-04): `Config.ProviderEncoded = {canonical, name, env, package, compatibility, settings, **headers: Record<string,string>**, **body: object**, models} (additionalProperties: false)`; `Config.ModelEncoded = {modelID, type, family, name, releaseDate, compatibility, package, settings, **headers**, **body**, capabilities, **variants: [{id, settings, headers, body}]**, cost, disabled, limit}`; top-level `providers` (v2) vs deprecated singular `provider` (v1): https://opencode.ai/config.json
115. anomalyco/opencode issue #29592 "[FEATURE]: Support custom HTTP body fields in provider configuration" (the per-provider custom body/headers request the v2 schema now ships [112][114]): https://github.com/anomalyco/opencode/issues/29592
116. OpenChamber docs — Auto Model Routing (fetched 2026-11-04): pick Auto in the model picker; a classification provider ("Jev") sorts **every prompt** into categories (built-in Trivial/Research/Implement/Hard; editable, custom allowed; "Jev sorts prompts by reading the category names and descriptions"); per-category model + thinking + agent configured in Settings; fallback model on <60% confidence or >4 s; "Every message is sorted again, so a session can move from a cheap model … to your strongest one"; server-side (desktop/web/mobile, not VS Code) — prompt-class-driven, **no card/custom-field input surface**: https://docs.openchamber.dev/auto-model-routing/
117. OpenChamber — overview/repo (fetched 2026-11-04): "open-source workspace for running and reviewing AI coding work on desktop, web, VS Code, and mobile"; runs on an OpenCode server; scheduled tasks, session sidebar "Sessions in Work": https://github.com/openchamber/openchamber ; https://docs.openchamber.dev/
118. OpenAI docs — Fast mode / Priority processing (fetched 2026-11-04): "priority" at OpenAI = a **paid processing tier** via string `service_tier: fast|priority` (or project setting) — "delivers significantly lower and more consistent latency … pay-as-you-go flexibility"; NOT a per-request numeric scheduling field (the numeric convention belongs to vLLM [99][101]): https://developers.openai.com/api/docs/guides/fast-mode ; https://developers.openai.com/api/docs/guides/priority-processing
119. earendil-works/pi issue #9005 (fetched 2026-11-04): client compat flag for "vLLM's top-level priority request field (**vLLM 0.28+**; lower value = handled earlier, default 0)" — third-party confirmation of the vLLM-side convention: https://github.com/earendil-works/pi/issues/9005

**[repo]** in-repo grounding (this session + EXPLORE.md): `.opencode/opencode.jsonc:75-92`
gpu-ai provider (`package: "aisdk:@ai-sdk/openai-compatible"`, `settings.baseURL
https://llama.spencerslab.com/v1`, `headerTimeout`/`chunkTimeout` 7200000, ~70 model
rows with `modelID`/`limit.context`; **no `headers`/`body` keys on it today** —
grep); `~/.config/opencode/opencode.json` (machine-global, not version-controlled):
SDLC agent definitions with **per-agent `"request": {"body": {"temperature": 0.1|0.2}}`**
— the same body-merge surface in live use in this fleet; `.rulesync/skills/boards/
SKILL.md:16` (roster: "exactly ONE board-level text field — `slug` … There is no
`models` custom field (D12) — model routing rides the Model(s) checklist, never a
field. Nor a `pipeline` field … (D19)"), `:214` ("the sole routing input is the
checked Model(s) items (D12)"), `:228` (resolved tiers "in STATE.json `kickoff.models`
and in the claim comment — never as a custom field"), `:261` (kickoff record fields),
`:386` (card-provided answers block: "the CHECKED items, plus the card's `slug`
custom-field value … and its `cardNumber`"); `.rulesync/skills/pipeline-kickoff/
SKILL.md` (live questions Q1–Q2; routing derivation; STATE.json `kickoff` = slug,
worktree, `models {plan, code}`, `local`, `coord_session`, `origin_dir`, `branch`);
`.rulesync/skills/pipeline-models/SKILL.md` (role→tier table, kickoff picker mapping,
favorited-models table); `skills/wekan-mcp/references/call-shapes.md:35` (`get_card`
= "only source of `card_number`, `custom_fields` `[{id, value}]`, `label_ids`");
pinned v266 schema (see [111]); EXPLORE §6 (live `Priority` CF facts; `preload_board`
does not carry custom fields; D12 roster line); EXPLORE §1 (deployed config = legacy
`matrix` style; Strata peer has no `filters` block; `LLAMA_SWAP_WATCH_CONFIG: true`).

### Reliability notes (R4, self-review)

- **High confidence** (primary docs/source/schema, mutually consistent): vLLM
  `priority` field + `X-Vllm-Priority` header + polarity + the fcfs error gate [99]
  [100][104][105][119]; V1 forced-preemption victim selection + recompute-only
  preemption [103]; engine-arg admission knobs incl. 503 semantics and
  `--watermark` [106]; header provenance/merge date [102]; llama-swap filter
  pass-through model + protected `model` + set-if-undefined [109][111]; llama-swap
  FIFO fast-path-vs-queue split and per-model static priority, **verified at the
  pinned v266 tag** [110]; the v266-vs-main drift check [110][111]; OpenCode v2.1.4
  provider/model/variant `headers`+`body` in the *installed* binary's compiled schema
  + the live published schema [112][114]; the lab's own live `request.body`
  precedent [repo]; no per-priority vLLM metrics [108].
- **Medium confidence:** (a) the model-level `body` merge actually landing in the
  final chat-completions HTTP payload on this exact provider chain — the binary shows
  the schema + the `AI.HttpOptions` merge and the fleet already uses the agent-level
  `request.body` (proven for `temperature`), but no model-level `body` request has
  been observed through OpenCode→llama-swap→vLLM in this session; acceptance line 1
  (the fcfs negative test) is designed to close exactly this. (b) "prefix caching
  makes recompute-preemption partially cheap" — standard vLLM behavior but not
  measured on this arch/recipe (OQ6). (c) llama-swap *header* pass-through for
  `X-Vllm-Priority` — true by proxy design (no header-filtering surface exists in the
  v266 schema) but the plan uses the **body** route, so it is moot unless the header
  variant is chosen.
- **Weakest claim:** "fifo.priority has zero effect on vLLM peer traffic" — it
  follows from the fast-path code (always-ready peer → never enqueued) [110] and the
  "no peer lifecycle" doc [R3-51], but the interaction (a peer request arriving while
  an in-flight local swap collides) was not traced line-by-line; if a peer request
  could ever be parked in the FIFO queue, its *model's* configured priority would
  order it — still static per-model, never per-card. The conclusion (not a card-level
  lever) holds either way.
- **Perspective weighting:** vLLM claims rest on primary source (v0.33.0 versioned
  docs + current engine source) — unusually solid for a fast-moving project; the one
  soft spot is v0.33.0-vs-main engine drift (the scheduler source read is `main`;
  v0.33.0 is a Nov-2026 stable within weeks of it, and the versioned *docs* agree).
  OpenCode claims rest on the installed binary itself (the strongest possible
  evidence for "what this lab's server accepts") rather than docs alone.
- **Blind spot** (nothing found): no public report of `priority`/`X-Vllm-Priority`
  traversing a third-party reverse proxy (llama-swap) end-to-end; no public data on
  preemption *cost* (re-prefill latency) under `--enforce-eager` on RDNA — both are
  the acceptance run's job, not the research's.

---

## R5 — Monitoring vLLM with Prometheus/Loki/Alloy in this stack (dedicated round)

User's exact ask: *"The final piece that'll need research is how to monitor vLLM with
prometheus/loki/alloy. It's time to collect that information."*

Scope: the planned deployment from R1/R2/R3 — `vllm/vllm-openai-rocm:v0.33.0-rocm100`
serving the dense 27B on the R9700, reached through llama-swap `peers.vllm`, deployed on
the gpu-ai cluster. Stack facts below are re-verified this session (chart pulls, live MCP
probes, greps) — where they correct EXPLORE.md that is called out explicitly.

STORM method note: interviews ran in-session (no subagent fan-out), five perspectives —
vLLM observability maintainer, Prometheus/platform engineer, SRE/alerting, log/Loki
engineer, ROCm GPU-stack expert — grounded in `global-searxng` + direct source fetches and
repo/live-cluster reads; all web evidence accessed **2026-11-04**. Citation keys `[n]`
resolve in the source list at the end of this section (continuing R4's numbering).

### TL;DR

- **The vLLM v0.33.0 `/metrics` surface is rich and all classic-Prometheus**: ~30 engine
  metrics labeled `{model_name, engine}` — KV-usage gauge, running/waiting gauges,
  preemption counter + per-request histogram, TTFT/ITL/TPOT/e2e/queue/prefill/decode
  histograms with sensible default buckets, prefix-cache hit/query counters (+ by-source),
  sleep-state gauge, admission-rejection counters. Always on, on the main API-server
  port (8000) — **no enable flag, no separate metrics port, no disable flag exists**
  [120][121][123][124].
- **Least-new-surface scrape in THIS stack: two pod annotations**
  (`k8s.grafana.com/scrape: "true"` + `k8s.grafana.com/metrics.portNumber: "8000"`) — the
  already-enabled k8s-monitoring v4 `annotationAutodiscovery` feature (all namespaces,
  60 s default) picks the pod up and remote-writes it over the existing alloy-metrics
  destination. Zero CRs, zero wrapper changes, zero central changes. (A PodMonitor CR is
  the equivalent operator-idiom alternative — pick ONE, never both.) **Correction to
  EXPLORE §3:** the annotation namespace is `k8s.grafana.com/*`, NOT `prometheus.io/*` —
  the repo's only `prometheus.io/*` user (exporter-mikrotik) is a dead letter [129][139].
- **Histograms ride intact over this path.** vLLM emits classic histograms only
  (python `prometheus_client`); the path uses Remote Write **0.1**
  (`remoteWriteProtocol: 1` default), which carries classic histograms verbatim as
  `_bucket`/`_sum`/`_count` series — `histogram_quantile()` works at the central as-is.
  Native histograms are irrelevant today: Alloy `scrapeNativeHistograms` defaults false,
  central Prometheus is 3.6.0 (stable-NH needs 3.8+ and explicit flags), and vLLM never
  emits them [129][130][131][132].
- **Official dashboards: two JSONs in the vLLM repo** (`performance_statistics`,
  `query_statistics`) — both single-engine-safe (a `model_name` variable only; no
  dp_rank/engine filters, no KV/preemption panels) and import cleanly via this repo's
  proven `grafana.dashboards` `url:` convention pinned to tag `v0.33.0`. The operator
  story's KV/queue/preemption panels are **not** in the official set → those come as
  alert rules (+ optional custom panels) per Q4 [128].
- **Logs: zero new surface** — `podLogsViaLoki` (alloy-logs, live on ai-gpu) already ships
  every pod log to central Loki. vLLM's default logging is modest (stat lines self-demote
  to DEBUG when idle; per-request body logging off by default, prompts never logged at
  INFO). The one documented volume problem — uvicorn access-log lines for probes +
  scrapers (issue #29023) — has a one-flag fix:
  `--disable-access-log-for-endpoints /health,/metrics,/ping` [125][126][127].
- **Alerts: concrete PromQL** for KV pressure, preemption storms, TTFT SLO, queue
  saturation, admission 503s, and pod restarts (Q4). **GPU-side is an honest gap**: no
  ROCm exporter exists in the stack, DCGM is NVIDIA-only; the official candidate is AMD's
  **Device Metrics Exporter** (R9700 = "Radeon AI platform", nominally in scope, but host
  distro Ubuntu-only vs openSUSE TW and no APU line in the matrix → on-target
  verification) — follow-up card, not this chunk [133][134][135][137].

### Q1 — The v0.33.0 `/metrics` surface (exact tag of the image class)

**Endpoint/port facts (source-verified):** `/metrics` is mounted on the **main** FastAPI
app by the instrumentator (`make_asgi_app` over the multiprocess registry) — same port as
serving, `--port` default **8000** [124]. There is **no separate metrics port, no
`--disable-metrics`, and no `--disable-logs` flag anywhere in the v0.33.0 CLI** (full
CLI page grepped); the endpoint is always enabled once the server is up [125]. The
multiprocess registry uses a temp `PROMETHEUS_MULTIPROC_DIR` (warning logged if a user
pre-sets it) [124].

**Labels:** every engine metric carries `{model_name, engine}` where `model_name` is the
**first** `--served-model-name` (or `--model` if unset) and `engine` is the engine index
as a string (`"0"` for a single engine) [121][125]. Per-metric extra labels are noted
below.

**Gauges (always registered unless noted):**

| Metric | Labels | Meaning / note |
|---|---|---|
| `vllm:kv_cache_usage_perc` | — | KV-cache usage, 1 = 100% — the primary pool-pressure signal [120][121] |
| `vllm:num_requests_running` | — | requests in execution batches [121] |
| `vllm:num_requests_waiting` | — | waiting + skipped(waiting) [121] |
| `vllm:num_requests_waiting_by_reason` | `reason=capacity\|deferred` | capacity = scheduling capacity; deferred = transient constraints (LoRA budget, KV transfer, blocked) [121] |
| `vllm:engine_sleep_state` | `sleep_state=awake\|weights_offloaded\|discard_all` | registered by default (awake=1 = awake); level-1/level-2 values move only with `--enable-sleep-mode` [120][121] |
| `vllm:cache_config_info` | full `CacheConfig` dict as labels | info gauge (value 1) — `num_gpu_blocks`, `block_size`, `kv_cache_dtype`, …; the KV-pool *capacity* reference for dashboards [121] |
| `vllm:lora_requests_info` | — | only with LoRA config [121] |
| `vllm:num_requests_kv_fetch_by_stage` | `stage` | only with async KV connectors [120] |

**Counters** (exposed with `_total` suffix in the text format):

| Metric | Labels | Meaning / note |
|---|---|---|
| `vllm:num_preemptions` | — | cumulative engine preemptions [120][121] |
| `vllm:request_num_preemptions` *(histogram)* | — | per-request preemption counts, buckets 1–20 [120][123] |
| `vllm:prompt_tokens` / `vllm:generation_tokens` | — | prefill/generation token throughput counters [120] |
| `vllm:prompt_tokens_cached` (+ `_by_source`) | `source=device\|host\|disk\|p2p\|external_unspecified` | cached prompt tokens by supplying tier; `by_source` sums to `prefix_cache_hits` + `external_prefix_cache_hits` [120][121] |
| `vllm:prefix_cache_queries` / `vllm:prefix_cache_hits` | — | hit-rate numerator/denominator [120][121] |
| `vllm:external_prefix_cache_*` | — | only with KV connectors (cross-instance) [120] |
| `vllm:mm_cache_queries` / `vllm:mm_cache_hits` | — | multimodal cache; registered but inert for a text-only 27B [120][121] |
| `vllm:request_success` | `finished_reason` | count of finished requests by finish reason [121] |
| `vllm:admission_rejections` | `reason=max_num_queued_reqs\|max_num_queued_tokens` | registered by default; increments only when a queue-limit 503 actually fires (R3's admission knobs) [120][121] |
| `vllm:watermark_requests` | `status` | only with `watermark_config` [120][121] |
| `vllm:corrupted_requests` | — | only with `VLLM_COMPUTE_NANS_IN_LOGITS` [121] |
| `vllm:spec_decode_num_drafts` / `_num_draft_tokens` / `_num_accepted_tokens` (+ `_num_accepted_tokens_per_pos{position}`) | — | **only registered when speculative decoding is configured** — which is NOT the case in this RDNA deployment (MTP under development on AMD, R1) — so expect the family absent; acceptance-rate PromQL is documented in the source docstring (`rate(accepted)/rate(draft_tokens)`, mean acceptance length `1 + rate(accepted)/rate(drafts)`) [120][122] |
| `vllm:estimated_flops_per_gpu_total` / `_read_bytes` / `_write_bytes` | — | only with `--enable-mfu-metrics` (MFU = flops / peak) [120][121] |

**Histograms** (all classic; default bucket families from the v0.33.0 source [123]):

| Metric | Default buckets | Note |
|---|---|---|
| `vllm:time_to_first_token_seconds` | 0.001 → 2560 s (22 boundaries) | ms-resolution sub-second, minutes-at-tail — quantile-computable even for 100k prefill [123] |
| `vllm:inter_token_latency_seconds` | 0.01 → 80 s (19) | per-step ITL [123] |
| `vllm:request_time_per_output_token_seconds` | ITL family | per-request TPOT [120][123] |
| `vllm:e2e_request_latency_seconds`, `vllm:request_queue_time_seconds`, `vllm:request_inference_time_seconds`, `vllm:request_prefill_time_seconds`, `vllm:request_decode_time_seconds` | family `request_latency`: 0.3 → 7680 s (21) | **smallest boundary 0.3 s** — sub-300 ms SLOs need a `--custom-histogram-buckets` override [120][123] |
| `vllm:iteration_tokens_total` | 1/8/16/… | tokens per engine step [120][123] |
| `vllm:request_prompt_tokens`, `vllm:request_generation_tokens`, `vllm:request_max_num_generation_tokens`, `vllm:request_params_max_tokens`, `vllm:request_prefill_kv_computed_tokens` | family `request_tokens`, **scales with `--max-model-len`** | wide family at 131k–262k ctx — the main cardinality cost of this pool (each boundary = one series per label set) [120][123] |
| `vllm:request_params_n` | 1/2/5/10/20 | — [123] |
| `vllm:request_num_preemptions` | 1 → 20 | per-request preemption histogram [120][123] |
| `vllm:kv_block_lifetime_seconds`, `vllm:kv_block_idle_before_evict_seconds`, `vllm:kv_block_reuse_gap_seconds` | family `kv_cache_residency` | **opt-in**: `--kv-cache-metrics` (sampling `--kv-cache-metrics-sample`, default 0.01 = 1% of blocks; requires log-stats enabled) [120][121][125] |

**Flags that change the surface** (v0.33.0 CLI page + source [120][121][125]):

| Flag | Effect on `/metrics` |
|---|---|
| `--kv-cache-metrics` (+ `--kv-cache-metrics-sample`) | adds the three `kv_block_*` histograms (sampled) |
| `--enable-mfu-metrics` | adds the three `estimated_*_per_gpu_total` counters |
| `--custom-histogram-buckets '<json>'` | replaces bucket boundaries for 8 named families (`request_latency`, `time_to_first_token`, `inter_token_latency`, `iteration_tokens`, `request_params_n`, `request_num_preemptions`, `request_tokens`, `kv_cache_residency`); unknown keys rejected at startup; cardinality warning in docs |
| `--show-hidden-metrics-for-version=X.Y` | re-enables deprecated-then-hidden names (deprecation policy: hidden in X.Y+1, removed in X.Y+2) — e.g. older `gpu_cache_usage_perc`-era names; current surface is `kv_cache_usage_perc` |
| `--served-model-name` | sets the `model_name` label value (first name wins) |
| `--otlp-traces-endpoint` (+ `--collect-detailed-traces all\|model\|worker`) | **OpenTelemetry traces only** (span export to a collector) — zero effect on `/metrics`; vLLM has no OTLP metrics path. Also "possibly costly and or blocking" per docs → leave unset (no OTel collector exists in this stack anyway) |
| speculative decoding (n/a here, R1) | gates the `spec_decode_*` family [122] |
| LoRA / watermark / NANS-logits / KV connectors | gate their respective optional families |

**What is NOT there** (for R4's coupling and the operator story): no per-priority
metrics (upstream gap #58077, open — R4[108]); no GPU-side (VRAM/occupancy) metrics —
the engine reports KV *blocks* and pool fractions, never device memory; that is the
exporter problem in Q4.

### Q2 — How to scrape it in THIS stack with the least new surface

**What's already live on gpu-ai (verified this session, not taken from EXPLORE):**
k8s-monitoring **v4.5.5** (pinned in `charts/k8s-monitoring/Chart.yaml`) with
`prometheusOperatorObjects.enabled: true` **and** `annotationAutodiscovery.enabled: true`
(both forwarding to the `prometheus` destination → remote write to
`prometheus.spencerslab.com`), collectors alloy-metrics (statefulset) / alloy-singleton /
alloy-logs — all `grafana/alloy:v1.21.2`, live probed on the gpu-ai `default` namespace
[129][139].

**The three mechanisms, precisely (chart templates + feature READMEs + Alloy component
docs [129][130]):**

1. **Annotation autodiscovery** — pods/services annotated `k8s.grafana.com/scrape:
   "true"` are discovered by `discovery.kubernetes` (role=pod) + relabeled. **The v4
   default annotation names are `k8s.grafana.com/*`, NOT `prometheus.io/*`**
   (`scrape`, `job`, `instance`, `metrics.container`, `metrics.path` (default
   `/metrics`), `metrics.portName`, `metrics.portNumber`, `metrics.scheme` (default
   http), `metrics.param`, `metrics.scrapeInterval` (default 60s),
   `metrics.scrapeTimeout` (default 10s)); the wrapper sets none of them, so defaults
   govern. Discovery generates a target **per declared container port**; `metrics.portNumber`
   overrides `__address__` to `podIP:<port>` **regardless of declared ports**;
   `metrics.portName` keeps only the target whose container port name matches. Without
   either, every declared port becomes a target (non-metrics ports then scrape-fail as
   `up=0` noise). `pods.onlyScrapeReadyPods` defaults **true** → a not-ready vLLM pod
   (multi-minute warmup) is simply not scraped — no failure noise. Job-label fallback
  chain: `k8s.grafana.com/job` → `app.kubernetes.io/name` → `app` → container name
  (app-template sets `app.kubernetes.io/name` → `job="vllm"` for a chart named `vllm`).
  Per-target interval override: `k8s.grafana.com/metrics.scrapeInterval`.
2. **PodMonitor CRs** (prometheus-operator CRDs, installed by the wrapper's
  `prometheus-operator-crds` dependency) — consumed by the Alloy
  `prometheus.operator.podmonitors` component (all namespaces by default, 60 s default
  interval, `metricsTuning` include/exclude regex). `podMetricsEndpoints[].port` is a
  **containerPort name** → the pod must declare a named port.
3. **ServiceMonitor CRs** — same component family, service-port based (the repo's only
  precedent, `self-monitor.yaml`, lives on the central monitoring cluster).

**Answering the specific sub-questions:**

- **Which knob / does the port name have to match?** For annotations: `metrics.portNumber`
  needs **no** declared port (it overrides the target address to `podIP:<port>`),
  `metrics.portName` **must** match a declared `containerPort` name; omitting both creates
  one target per declared container port (hazard for multi-port pods). For PodMonitor:
  the `port` field is a declared containerPort name — must match. vLLM has a single port
  (8000 = serving = metrics), so either style is trivial [129][124][125].
- **CRD discovery vs annotation discovery conflict?** There is **no dedup** — two
  independent scrape pipelines. A pod that is both PodMonitored and annotation-scraped is
  scraped twice (two different `job` labels); `sum()`-based alerts/dashboards then
  double-count. Rule for the plan: **pick one mechanism per endpoint** [129][130].
- **Does the metrics port differ from the serving port?** No — same port (8000), no
  separate metrics port exists in v0.33.0 [124][125].
- **Do histograms survive remote write?** Yes, verbatim — but only the *classic* kind,
  which is all vLLM emits. The path here is `prometheus.remote_write` with
  `remoteWriteProtocol: 1` (the k8s-monitoring default; the wrapper sets neither
  `protobufMessage` nor `remoteWriteProtocol`) = **Remote Write 0.1** (`prometheus.WriteRequest`),
  in which classic histograms ride as plain `_bucket{le=…}`/`_sum`/_count series —
  nothing special needed at the central Prometheus (which already runs
  `enableRemoteWriteReceiver: true`). **Native histograms** are a different story and
  moot here: Alloy scrapes them only with `scrapeNativeHistograms: true` (default false),
  sends them only on Remote Write 2.0, and the Prometheus server side is stable only
  since v3.8.0 with explicit `scrape_native_histograms`/`send_native_histograms` config
  (the `--enable-feature=native-histograms` flag is a no-op since 3.9; defaults flip in
  v4.0). Central here is **3.6.0** (kps 78.1.0 default image, no override in lab values).
  If native histograms ever mattered: alloy `global.scrapeNativeHistograms: true` +
  destination `remoteWriteProtocol: 2` + central ≥3.8 — recorded as trivia, not action
  [129][130][131][132].

**Recommendation (least new surface):** two annotations on the vLLM pod template
(`k8s.grafana.com/scrape: "true"`, `k8s.grafana.com/metrics.portNumber: "8000"`,
optionally `k8s.grafana.com/metrics.scrapeInterval: "30s"`) in the new `charts/vllm` —
the annotationAutodiscovery feature does everything else. The PodMonitor-CR alternative
adds one template file and buys per-endpoint operator-idiom tuning; it is not needed for
this single-port, single-container service. **Do not** use `prometheus.io/*` annotations
here — nothing in the per-cluster stack reads them (the exporter-mikrotik precedent is a
dead letter; its actual scrape is an explicit static `ScrapeConfig` CR on the monitoring
cluster) [129][139].

### Q3 — Official dashboards + the log side (Loki)

**Dashboards (fetched from the `v0.33.0` tag, all panel exprs enumerated this session
[128]):**

| File (in vllm repo) | uid / size | Panels / metrics |
|---|---|---|
| `examples/observability/dashboards/grafana/performance_statistics.json` | `performance-statistics`, 35,464 B, 21 panels | mean + p50/p90/p99 (`histogram_quantile` over `_bucket`) for `e2e_request_latency_seconds`, `time_to_first_token_seconds`, `inter_token_latency_seconds`; `rate(prompt_tokens_total)`, `rate(generation_tokens_total)`, `rate(iteration_tokens_total_count)` |
| `examples/observability/dashboards/grafana/query_statistics.json` | `query-statistics4`, 24,773 B, 14 panels | `rate(request_success_total)` by `finished_reason`, e2e p50/p90/p99, `request_prompt_tokens` histogram + per-request prompt/generation token averages |
| `examples/observability/prometheus_grafana/` (compose example) | — | docker-compose demo; README: "Prometheus metric logging is enabled by default in the OpenAI-compatible server"; carries an older standalone `grafana.json` |

Both dashboards' variables: `DS_PROMETHEUS` (**type `datasource`, query
`"prometheus"`** — a type-based lookup that resolves to the lab's "Prometheus" datasource
automatically), `Deployment_id` = `label_values(vllm:generation_tokens_total,
model_name)` / `label_values(vllm:request_success_total, model_name)`, plus `agg_method`
and `rush_hours`. **No `__inputs` block** (so the Grafana chart's `__inputs` substitution
is a no-op — harmless, same as the repo's other `url:` dashboards) and **no
dp_rank/engine/multi-tenant label filters** → the single-engine deployment (engine="0")
renders as-is. **What's missing from the official set:** KV-usage, waiting/queue,
preemption, prefix-cache-hit-rate panels — exactly the operator-story signals; those
belong in alert rules (Q4) and, if wanted, a small custom panel set. (No `gnetId`
exists for these on grafana.com — `url:` provisioning is the form.)

**Import per this repo's convention:** `services/monitoring/prod/values.yaml` already
provisions dashboards via `grafana.dashboards.<folder>.<name>: {url: <raw GitHub>,
datasource: Prometheus}` (proven entries: crowdsecurity ×4, seaweedfs, cloudnative-pg,
emqx ×5) with `datasource:` mapping [139]. The vLLM pair lands as two such entries under
an existing folder (`default`, or a new folder = one extra provider block — plan call),
**pinned to the same tag as the image** (`v0.33.0`) with a comment pairing them, because
renovate cannot track raw-URL dashboard pins.

**Log side — plumbing: zero new surface.** `podLogsViaLoki.enabled: true` (alloy-logs
daemonset + filesystem-log-reader, live on ai-gpu per this session's probe) already ships
**every** container log from every pod in the cluster to central Loki with k8s labels
(pod/container/namespace/node) [139]. A vLLM pod's logs appear in Loki on day one,
queryable as `{container="<vllm container>"} or {pod=~"gpu-ai-vllm.*"}`.

**vLLM's logging shape (v0.33.0, CLI page + logging docs [125][126]):**

- **Default: text, INFO.** The periodic engine stat line (throughput / running / waiting
  / KV usage) **self-demotes to DEBUG when the engine is idle** (source: `log_fn =
  logger.debug if self.engine_is_idle else logger.info`) — quiet at night, no flag needed
  for that.
- `--disable-log-stats` — removes the stat lines entirely (also the gate for
  `--kv-cache-metrics`).
- **Per-request content logging is OFF by default** (`--enable-log-requests` False): INFO
  would log request ID/params, **DEBUG would log prompts**; `--max-log-len` caps prompt
  length when enabled. **Do not enable** — prompt content would flow into Loki (privacy +
  volume) [125].
- `--enable-log-outputs` (logs generated text; requires `--enable-log-requests`) — same
  privacy note.
- **uvicorn access log is ON by default** → one line per HTTP request, **including every
  `/health` probe and every `/metrics` scrape** — this is the documented volume problem:
  issue #29023 ("IGW hits `/metrics` continuously … leads to an overload of logs"; closed
  completed 2026-03) [127]. **The fix is one flag:**
  `--disable-access-log-for-endpoints /health,/metrics,/ping` (exact path match, query
  params ignored) [125][126]. `--disable-uvicorn-access-log` nukes all access lines if
  the probe noise dominates.
- **Structured JSON is available** if wanted later:
  `--logging-config.formatter json` → one JSON object per vLLM **and** uvicorn record
  (fields: `asctime`, `levelname`, `name`, `processName`, `process` (PID), `message`,
  `vllm_process_name` = logical process incl. worker rank); a custom
  `pylogging_config_file` (Python dictConfig JSON, mounted via the chart's config mount)
  replaces the built-in config wholesale; caveat: only records emitted through the
  configured loggers are converted (direct stdout writes are not) [126]. A Loki `| json`
  pipeline stage could then key on `vllm_process_name`/`levelname` — follow-up, not
  required (plain-line Loki works today).
- Volume reality check for this pool: 3–4 agent sessions produce modest request lines;
  the dominant noise class is probes+scrapes (fixed by the flag above); at 30-day Loki
  retention the ingestion cost is negligible either way [139].

### Q4 — Alert-worthy signals for this pool (concrete PromQL)

Single pool → label set `{model_name="<served-name>", engine="0"}`; `job="vllm"` from the
annotation fallback (confirm at deploy). Thresholds marked *(calibrate)* should be set
from the R1 on-target benchmark run, not vibes.

| # | Signal | PromQL | Severity / note |
|---|---|---|---|
| 1 | Scrape down | `up{job="vllm"} == 0` (for 2m) | critical |
| 2 | Target staleness (belt) | `time() - timestamp(vllm:kv_cache_usage_perc) > 300` | warning — catches scrape loss before `up` flaps |
| 3 | KV cache pressure | `vllm:kv_cache_usage_perc > 0.9` (5m) / `> 0.98` (10m) | warning / critical — R1's pool is small by design; >0.98 = preemption territory |
| 4 | Preemption storm | `rate(vllm:num_preemptions_total[10m]) > 0.1` | warning — sustained ≈1 preemption/100 s; pair with # |
| 4b | Preemption per request | `histogram_quantile(0.5, sum by (le) (rate(vllm:request_num_preemptions_bucket[30m]))) > 1` | warning — median request preempted ≥1×/30 min (also the R4 acceptance-smoke key metric) |
| 5 | Queue saturation | `vllm:num_requests_waiting > 0` (for 10m) **and** `vllm:num_requests_waiting_by_reason{reason="capacity"} >= 4` (for 10m, 4 = R1's `--max-num-seqs`) | warning — persistent queue / pool full |
| 5b | Queue time | `histogram_quantile(0.95, sum by (le) (rate(vllm:request_queue_time_seconds_bucket[10m]))) > 30` *(calibrate)* | warning |
| 6 | TTFT SLO | `histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[10m]))) > 15` *(calibrate from R1 benchmark)* | warning — buckets span 1 ms–2560 s so quantiles stay computable through 100k prefill; do not alert-tune before the benchmark run |
| 7 | Decode stutter (ITL) | `histogram_quantile(0.95, sum by (le) (rate(vllm:inter_token_latency_seconds_bucket[10m]))) > 0.5` | warning — ~30 tok/s decode ≈ 0.03 s ITL; 0.5 s = stall class |
| 8 | Admission 503s | `rate(vllm:admission_rejections_total[5m]) > 0` (by `reason` label) | warning — the queue-limit valves (R3 Q5.6) firing |
| 9 | Request failures | `sum by (finished_reason) (rate(vllm:request_success_total{finished_reason=~"error\|abort"}[10m])) > 0` | warning — verify the `finished_reason` enum values at deploy |
| 10 | Pod restarts | `increase(kube_pod_container_status_restarts_total{namespace="default", pod=~"gpu-ai-vllm.*"}[1h]) > 0` | warning — kube-state-metrics is deployed (telemetryServices) |
| 11 | Engine asleep (only if `--enable-sleep-mode`, R1 OQ6) | `vllm:engine_sleep_state{sleep_state="awake"} == 0` (15m) | info — asleep by design vs stuck is ambiguous; page only if traffic is expected |
| 12 | Prefix-cache efficiency (info) | `rate(vllm:prefix_cache_hits_total[10m]) / rate(vllm:prefix_cache_queries_total[10m]) < 0.2` under load | info — R1's recipe enables prefix caching; a low hit rate means shared system prompts aren't caching |

**Delivery:** the repo contains **no PrometheusRule or alert templates today** (grep) —
the central kps Prometheus selects `ruleSelector: {}` (any rule in the monitoring
cluster is picked up), so the *first* rule template would live at
`services/monitoring/prod/templates/` as a `monitoring.coreos.com/v1` PrometheusRule —
a new convention the plan can adopt or defer (Grafana alert rules are the lighter
alternative). Not a blocker for metrics/dashboards; plan call [139].

**The GPU-side gap — stated honestly:** there is **no ROCm GPU exporter anywhere in this
stack** (kepler/opencost disabled in the wrapper; no rocm/dcgm chart exists in
`charts/`), so **R9700 VRAM/occupancy has zero series**, and the 8060S gets only the
indirect proxy of `node_memory_*`/`container_memory_*` (already scraped) because its
"VRAM" is system RAM. DCGM — the NVIDIA node-level exporter with DCGM-exporter +
Prometheus integration — is **NVIDIA-only by definition** ("gathering telemetry … of
NVIDIA GPUs" [137]); **no DCGM-equivalent node-level metric exists for RDNA4**.
Candidates for the gap (all researched, none yet deployed):

| Candidate | What it is | Container/K8s support | gfx1201 (R9700) | gfx1151 (8060S APU) |
|---|---|---|---|---|
| **AMD Device Metrics Exporter** (official, `ROCm/device-metrics-exporter`) | Prometheus-format temp/util/VRAM used+free/GTT/power/clock/ECC from amdsmi/rocm-smi; image `docker.io/rocm/device-metrics-exporter`; Helm chart + Slurm; **beta DRA GPU-claim support (K8s 1.34+)** [133][134] | DaemonSet (beta DRA GPU-claim support (K8s 1.34+)); device-plugin health check consumes its gRPC socket at `/var/lib/amd-metrics-exporter/…grpc.socket` — **that hostPath is already mounted on the live ai-gpu plugin pod (unused today)** [135][139] | Nominally in scope: requirements line "MI350P or **Radeon AI** platform: ROCm 7.13 or later" (R9700 = Radeon AI PRO, ROCm 10.x ≥ 7.13) — but the per-metric matrix is MI2xx/MI3xx-centric and the host requirement is **Ubuntu 22.04/24.04 vs the node's openSUSE TW** → untested combination | **Not in the documented matrix** (no APU/iGPU line; the Radeon notes cite W7900-class discrete cards) → unverified |
| **ROCm GPU Operator** (official, `ROCm/gpu-operator`, v1.4.0 chart, active Oct 2026) | Turnkey bundle: controller + device plugin + **node labeller** (`amd.com/gpu.*` labels incl. device-id/product-name/vram/cu-count — would also solve chip naming, EXPLORE §8.7) + DRA driver + Device Config Manager + **Device Metrics Exporter** + device test runner + NFD + **kernel module management (KMM)**; "AMD Instinct™ and AMD Radeon™" [136] | Full operator stack on K8s 1.29+; bundles Grafana dashboards for exporter metrics | In scope (Radeon line) | In scope (Radeon line) |
| **Kepler** (`sustainable-computing-io/kepler`, CNCF Sandbox) | Energy attribution (container/pod/node watts, joules) Prometheus exporter; GPU telemetry via DCGM/NVML [138] | DaemonSet/Helm; k8s-monitoring has a kepler slot but the **lab wrapper disables kepler/opencost** [139] | GPU path is DCGM/NVML-based → **NVIDIA**; no AMD GPU path documented | same |
| Community rocm-smi-based exporters | assorted gists/wrappers | — | unofficial; superseded by the official DME for the same data | same |

**Read:** the official DME (standalone DaemonSet, no operator) is the natural follow-up
card — it is AMD's own answer to "DCGM-equivalent for ROCm", the health-check socket path
is already staged on the node's plugin pod, and it would also enable the plugin's GPU
health checks. The two verification items that decide it are on-target and operator-run
(no exec tier): (a) does the exporter image report the R9700 (and the 8060S) with
non-zero VRAM/util/power on an **openSUSE TW** host, and (b) which of the MI-centric
metrics actually light up on RDNA4 (expect `GPU_GFX_ACTIVITY`, VRAM used/free, power; the
`GPU_PROF_*` family is explicitly Radeon-degraded per the matrix [133]). The GPU Operator
is the heavier turnkey alternative — attractive for the node labeller, but KMM driver
management collides with the lab's manual driver policy, so it is a "if we ever want full
AMD GPU ops" decision, not this ticket.

### Contradictions and how to weigh them

1. **EXPLORE §3 "annotationAutodiscovery → `prometheus.io/*` discovery" vs the chart.**
   The v4.5.5 feature defaults are `k8s.grafana.com/*` (and the wrapper sets no
   `annotations:` overrides) [129][139]. *Weigh:* the chart is the authority (the v3→v4
   rename dropped the prometheus.io defaults); the repo's only `prometheus.io/*` user
   (exporter-mikrotik) is demonstrably a dead letter — its actual scrape is an explicit
   static ScrapeConfig on the monitoring cluster [139]. Use `k8s.grafana.com/*`; treat
   any future `prometheus.io/*` annotation in a chart as inert on the per-cluster
   stack.
2. **"vLLM ships Grafana dashboards" (R3 framing) vs what the dashboards contain.** The
   two official JSONs cover latency/throughput/finish-reason only — no KV/queue/preemption
   panels [128]. *Weigh:* import both as-is (they work on this single-engine pool with
   zero edits) AND supply the operator story via Q4 alert rules (+ optional custom
   panels). Don't oversell the dashboards as "the vLLM operator view".
3. **DME "supports Radeon" (requirements line) vs MI2xx/MI3xx-centric metric matrix.**
   Both true at different layers: the exporter *runs* on Radeon AI platforms (ROCm ≥7.13)
   but many documented metrics are MI-tagged, and the Radeon notes explicitly degrade the
   `GPU_PROF_*` counters [133]. *Weigh:* plan the follow-up card around the core telemetry
   (VRAM used/free, GFX activity, power, clock) as the expected-good set; treat
   profiling counters as nice-to-have; the openSUSE TW host requirement is a third,
   untested variable — all three resolved by one 10-minute on-target pod test.
4. **"#29023 log overload" vs "default logging is modest".** Not a clash: the overload
   class is the uvicorn *access log* (probe + scrape frequency × lines), while the engine
   *stat* lines self-throttle to DEBUG when idle [125][127]. *Weigh:* ship the
   `--disable-access-log-for-endpoints` flag by default; no other log tuning needed.
5. **"Histograms over remote write" splits by flavor.** Classic = intact on this path
   (RW 0.1, plain series) [129]; native = unsupported here (RW 2.0 + explicit config on
   both ends + server ≥3.8) [131]. *Weigh:* no action — vLLM emits classic only; recorded
   so nobody "fixes" a non-problem by enabling NH flags.

### Implications for the plan

- **Monitoring closes inside the vLLM chart chunk + one monitoring values block.**
  (a) `charts/vllm` pod template: `k8s.grafana.com/scrape: "true"`,
  `k8s.grafana.com/metrics.portNumber: "8000"` (+ optionally
  `k8s.grafana.com/metrics.scrapeInterval: "30s"`); declare the containerPort with a name
  (`http: 8000`) anyway (Service/peers hop + future PodMonitor-proofing). (b) serve args:
  `--disable-access-log-for-endpoints /health,/metrics,/ping` (log hygiene, #29023);
  `--kv-cache-metrics` + `--enable-mfu-metrics` optional (both cheap, opt-in families).
  (c) `services/monitoring/prod/values.yaml`: two `grafana.dashboards` `url:` entries
  pinned to tag `v0.33.0`, `datasource: Prometheus`, folder per plan call, comment pairing
  the dashboard pin with the image pin (renovate can't track the URL).
- **Nothing else:** no wrapper chart change, no CRs, no central Prometheus flags, no
  custom-values entry (no secrets), no ingress (metrics stays ClusterIP-only), no Loki
  pipeline change.
- **Alerts are a plan decision with a defined shape:** the Q4 table is the rule content;
  delivery = first-ever PrometheusRule template under `services/monitoring/prod/templates/`
  (kps `ruleSelector: {}` already ingests monitoring-cluster rules) or Grafana alert
  rules; the TTFT/queue-time thresholds are marked *(calibrate)* and must be set from the
  R1 benchmark acceptance run — the plan's Commands should carry that line.
- **R4 coupling stands:** dashboards/alerts show *aggregate* preemption/queue metrics
  only — no per-priority metrics exist upstream (#58077, R4[108]); the R4 acceptance
  smoke already keys on `vllm:num_preemptions`/`request_num_preemptions` [121][122].
- **GPU-side telemetry = follow-up card, explicitly out of this chunk:** AMD Device
  Metrics Exporter evaluation (image tag, R9700+8060S sensor availability on openSUSE TW,
  DaemonSet on ai-gpu, scrape via the same annotation mechanism, optional device-plugin
  health enablement) — with the GPU Operator recorded as the heavy alternative (KMM
  collision with the manual driver policy) [133][134][135][136][137].
- **Do not enable** `--enable-log-requests`/`--enable-log-outputs` (prompt/output content
  into Loki) and leave `--otlp-traces-endpoint` unset (no OTel collector in the stack)
  [125][126].

### Open questions (R5)

1. **Scrape interval:** 60 s (feature default, zero extra annotations) vs 30 s (one extra
   annotation; better KV/queue gauge resolution) — plan call; lean 30 s.
2. **Dashboard folder:** existing `default` (no new provider block) vs a new
   `AI`/`Inference` folder (one extra `dashboardProviders` entry) — plan call; either
   works with the `url:` convention.
3. **Alert delivery convention:** this ticket introduces the repo's first PrometheusRule
   (new template + values), or defers to Grafana alert rules / a follow-up — plan call;
   metrics + dashboards are unaffected.
4. **TTFT/queue-time SLO numbers** — must come from the R1 benchmark run on the R9700
   (100k-prefill TTFT, 3–4 concurrent sessions); the Q4 table ships with *(calibrate)*
   markers until then.
5. **DME on-target verification (operator, for the follow-up card):** does
   `docker.io/rocm/device-metrics-exporter` (v1.2.0 per the install-guide example, or a
   newer tag) report the R9700 and the 8060S with non-zero VRAM/util/power on the
   **openSUSE TW** node; which MI-centric metrics actually light on gfx1201; and does the
   live plugin pod's pre-staged `/var/lib/amd-metrics-exporter` socket pair with the
   exporter to enable device-plugin health checks.
6. **`finished_reason` enum values** for alert #9 — verify against the live `/metrics`
   output at deploy (the gauge/counter is registered by default; the label values come
   from the vLLM `FinishReason` enum, not re-verified against the v0.33.0 source this
   round).
7. **KV-residency histograms** (`--kv-cache-metrics`, 1% sample): enable by default in
   the chart (useful for R4's preemption-cost question and cheap at 1% sampling) or
   leave off until needed — plan call.

### Sources (R5)

All web sources accessed **2026-11-04** via `global-searxng` + direct fetches (v0.33.0
tag sources fetched from the git tag matching the lab's image class; docs pages stamped
with their site dates). Cross-round re-citations: [R1-n], [R3-n], [R4-n]. `[repo …]` =
in-repo grounding (this session's greps/chart pulls/live probes + EXPLORE.md).

120. vLLM docs — Production Metrics, **v0.33.0 versioned page** (fetched 2026-11-04): general-metrics table (names/types incl. `vllm:kv_cache_usage_perc`, `vllm:num_preemptions`, `vllm:num_requests_waiting_by_reason` reasons, `vllm:engine_sleep_state`, `vllm:admission_rejections`, `vllm:cache_config_info` via info-gauge pattern), spec-decode table (per_pos counter; family otherwise source-verified [122]), NIXL/HiSparse/SimpleCPUOffload connector metric sections, MFU metrics via `--enable-mfu-metrics`, `--custom-histogram-buckets` family table + bucket-cardinality warning, deprecation policy (hidden X.Y+1 / removed X.Y+2, `--show-hidden-metrics-for-version` escape hatch). https://docs.vllm.ai/en/v0.33.0/usage/metrics/
121. vLLM v0.33.0 source — `vllm/v1/metrics/loggers.py` (fetched 2026-11-04): `PrometheusStatLogger` exact registrations and gating — `labelnames = ["model_name", "engine"]` (+ `reason=capacity|deferred`, `sleep_state=awake|weights_offloaded|discard_all`, `finished_reason`, `reason=max_num_queued_reqs|max_num_queued_tokens` (the `ADMISSION_REASONS` constant), `stage`, `position`); `kv_block_*` histograms gated on `observability_config.kv_cache_metrics`; `lora_requests_info` gated on `lora_config`; `corrupted_requests` gated on `VLLM_COMPUTE_NANS_IN_LOGITS`; `cache_config_info` = whole `CacheConfig` dict as labels; `request_tokens` bucket family scaled by `max_model_len`; engine stat log line `logger.debug if self.engine_is_idle else logger.info`. https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/metrics/loggers.py
122. vLLM v0.33.0 source — `vllm/v1/spec_decode/metrics.py` (fetched 2026-11-04): `SpecDecodingProm` registers nothing unless `speculative_config` is set; counters `vllm:spec_decode_num_drafts`, `_num_draft_tokens`, `_num_accepted_tokens`, `_num_accepted_tokens_per_pos` (per `num_speculative_tokens`, `position` label); acceptance-rate PromQL in the docstring (`rate(accepted)/rate(draft_tokens)`; mean acceptance length `1 + rate(accepted)/rate(drafts)`; per-position vector). https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/spec_decode/metrics.py
123. vLLM v0.33.0 source — `vllm/v1/metrics/buckets.py` (fetched 2026-11-04): default families — `request_latency` 0.3→7680 s (21 boundaries), `time_to_first_token` 0.001→2560 s (22), `inter_token_latency` 0.01→80 s (19), `iteration_tokens` 1/8/16…, `request_params_n` 1/2/5/10/20, `request_num_preemptions` 1→20, `kv_cache_residency` (gated); `request_tokens` built from `max_model_len` via `build_buckets`. https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/metrics/buckets.py
124. vLLM v0.33.0 source — `vllm/entrypoints/serve/instrumentator/metrics.py` + `__init__.py` (fetched 2026-11-04): `/metrics` mounted on the main FastAPI app via `make_asgi_app(registry=…)` (same port as serving); multiprocess registry with temp `PROMETHEUS_MULTIPROC_DIR` (warning if user pre-set); instrumentator excludes `/metrics,/health,/load,/ping,/version,/server_info` from request metrics. https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/entrypoints/serve/instrumentator/metrics.py
125. vLLM docs — `vllm serve` CLI, **v0.33.0 versioned page** (fetched 2026-11-04): `--port` default 8000; **no `--metrics-port`, no `--disable-metrics`, no `--disable-logs` flag exists** (page grepped); ObservabilityConfig: `--otlp-traces-endpoint` ("Target URL to which OpenTelemetry traces will be sent"), `--collect-detailed-traces all|model|worker` ("possibly costly and or blocking"), `--kv-cache-metrics` (+ `--kv-cache-metrics-sample` default 0.01, "Requires log stats to be enabled"), `--custom-histogram-buckets` (JSON family→boundaries), `--enable-mfu-metrics`, `--show-hidden-metrics-for-version`; logging: `--log-level`, `--logging-config` (`.formatter json`, `.pylogging_config_file`, `.configure_logging false`), `--disable-log-stats`, `--enable-log-requests` (default False; INFO = request ID/params, DEBUG = prompt inputs; `VLLM_LOGGING_LEVEL`/`VLLM_REQUEST_BODY_LOG_LEVEL`), `--max-log-len`, `--enable-log-outputs` (requires `--enable-log-requests`), `--disable-uvicorn-access-log`, `--disable-access-log-for-endpoints` (example `/health,/metrics,/ping`), `--sse-keep-alive-interval`; `--served-model-name` → metrics `model_name` = first name. https://docs.vllm.ai/en/v0.33.0/cli/serve/
126. vLLM docs — Logging Configuration (stable; page dated 2026-11-01, fetched 2026-11-04): built-in `json` formatter = one JSON object per vLLM and Uvicorn record (fields `asctime`, `levelname`, `name`, `processName`, `process`, `message`, `vllm_process_name`); `pylogging_config_file` replaces (not merges) the built-in dictConfig; direct stdout/stderr writes are NOT converted; `--disable-access-log-for-endpoints` example targeting high-frequency probe/scraper noise (exact path match, query params ignored). https://docs.vllm.ai/en/stable/examples/features/logging_configuration/
127. vllm-project/vllm issue #29023 — "[Feature]: Disable logging `/metrics`" (opened 2025-11-19, closed 2026-03-02, state_reason completed): "IGW hits `/metrics` continuously to understand the current load … This leads to an overload of logs. We can disable this with `--disable-uvicorn-access-log`, but lose access to all access logs" → resolved by the per-endpoint filter. https://github.com/vllm-project/vllm/issues/29023
128. vLLM repo — `examples/observability/` @ tag v0.33.0 (fetched 2026-11-04; both dashboard JSONs downloaded, all panel exprs + variables enumerated this session): `prometheus_grafana/` compose example (README: "Prometheus metric logging is enabled by default in the OpenAI-compatible server", import `grafana.json`); `dashboards/grafana/performance_statistics.json` (35,464 B, uid `performance-statistics`, 21 panels: mean/p50/p90/p99 of e2e/TTFT/ITL via `histogram_quantile`, `rate(prompt_tokens_total)`, `rate(generation_tokens_total)`, `rate(iteration_tokens_total_count)`) and `dashboards/grafana/query_statistics.json` (24,773 B, uid `query-statistics4`, 14 panels: `rate(request_success_total)` by `finished_reason`, e2e p50/p90/p99, `request_prompt_tokens` histogram, per-request prompt/generation token averages); `dashboards/perses/`; `metrics/offline.py`. Variables in both: `DS_PROMETHEUS` (type datasource, query `prometheus`), `Deployment_id` = `label_values(vllm:generation_tokens_total, model_name)` / `label_values(vllm:request_success_total, model_name)`, `agg_method`, `rush_hours`; **no `__inputs` block; no dp_rank/engine filters; no KV/queue/preemption panels**. https://github.com/vllm-project/vllm/tree/v0.33.0/examples/observability
129. grafana/k8s-monitoring Helm chart **v4.5.5** (the version pinned in `charts/k8s-monitoring/Chart.yaml`; helm-pulled + template-read 2026-11-04): `feature-annotation-autodiscovery` — default annotation namespace `k8s.grafana.com/{scrape,job,instance,metrics.container,metrics.path,metrics.portName,metrics.portNumber,metrics.scheme,metrics.param,metrics.scrapeInterval,metrics.scrapeTimeout}`; `discovery.kubernetes` role=pod (target per declared container port); `metrics.portNumber` overrides `__address__` to `podIP:<port>` even for undeclared ports; `metrics.portName` requires a matching declared containerPort name; `namespaces: []` = all; `pods.onlyScrapeReadyPods` default true; job fallback `k8s.grafana.com/job` → `app.kubernetes.io/name` → `app` → container. `feature-prometheus-operator-objects` — `prometheus.operator.{podmonitors,servicemonitors,probes}` Alloy components (README: PodMonitor/ServiceMonitor/Probe support), `namespaces` all by default, 60 s default interval, `metricsTuning` include/exclude regex, `global.scrapeNativeHistograms` false, `scrapeProtocols` OpenMetrics-first. `destinations/prometheus` — `prometheus.remote_write` endpoint, `remoteWriteProtocol` default **1** (RW 0.1 `prometheus.WriteRequest`; `remoteWriteProtocol: 2` → `io.prometheus.write.v2.Request`), WAL settings. https://github.com/grafana/k8s-monitoring-helm (charts/k8s-monitoring v4.5.5)
130. Grafana Alloy docs — `prometheus.operator.podmonitors` component (fetched 2026-11-04): discovers PodMonitor CRs via in-cluster service account, scrapes their targets, forwards to receivers; `namespaces` (all if unset), `selector`/`match_expression`, `rule` relabel blocks, `scrape` block args (`default_scrape_interval` 1m, `scrape_native_histograms` false, `convert_classic_histograms_to_nhcb` false, `default_sample_limit`), 5-minute informer refresh. https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.operator.podmonitors/
131. Prometheus docs — Native Histograms (spec page, fetched 2026-11-04): introduced experimental Nov 2022, first server v2.40.0 behind `--enable-feature=native-histograms`; **stable since v3.8.0** with scraping still requiring explicit `scrape_native_histograms` (the flag's only remaining effect in 3.8 is defaulting it; **no-op since v3.9**); remote-write delivery requires `send_native_histograms` in the remote-write config (RW 2.0 protobuf); "From v4 on, both `scrape_native_histograms` and `send_native_histograms` will default to `true`". https://prometheus.io/docs/specs/native_histograms/
132. prometheus-community/kube-prometheus-stack chart **78.1.0** (pinned with renovate directive in `services/monitoring/prod/values.yaml`; `helm show chart`/`values` 2026-11-04): appVersion v0.86.0; `prometheus.prometheusSpec.image` default `quay.io/prometheus/prometheus:v3.6.0` → **central Prometheus = 3.6.0** (lab values set no image override; they do set `enableRemoteWriteReceiver: true`, `retention: 7d`, 50 GiB PVC, and empty `ruleSelector`/`serviceMonitorSelector`/`podMonitorSelector`). https://prometheus-community.github.io/helm-charts (charts/kube-prometheus-stack/78.1.0)
133. AMD Device Metrics Exporter docs (v1.5.3, instinct.docs.amd.com, fetched 2026-11-04): "enables Prometheus-format metrics collection for AMD GPUs and NICs in HPC and AI environments" (temperature, utilization, memory usage, power, PCIe); GPU metrics requirements: **Ubuntu 22.04/24.04**, Docker, "MI2xx or MI3xx platform: ROCm 6.2.0 or later", **"MI350P or Radeon AI platform: ROCm 7.13 or later"**; per-metric platform matrix (most rows tagged `[MI2xx, MI3xx]`; `GPU_AVERAGE_PACKAGE_POWER [MI2xx, Radeon]`; `GPU_TOTAL/USED/FREE_VRAM`, `GPU_TOTAL/USED/FREE_GTT`, `GPU_GFX_ACTIVITY`, `GPU_UMC_ACTIVITY`, `GPU_CLOCK*` families; Radeon notes on `GPU_PROF_*`: core counters GRBM_GUI_ACTIVE/SQ_WAVES/GRBM_COUNT/GUI_UTIL_PERCENT supported, SM_ACTIVE "exported but always returns 0 on Radeon", memory fetch/write "not supported … always return 0 on Radeon (e.g. W7900)", compute-ops not exported); K8s via Helm chart; Slurm; gRPC socket `amdgpu_device_metrics_exporter_grpc.socket`. https://instinct.docs.amd.com/projects/device-metrics-exporter/en/latest/index.html ; https://instinct.docs.amd.com/projects/device-metrics-exporter/en/latest/configuration/metricslist.html
134. ROCm/device-metrics-exporter (GitHub, fetched 2026-11-04): "Device Metrics Exporter exports metrics from AMD devices (GPUs) to collectors like Prometheus"; features: Prometheus-compatible endpoint, rich GPU telemetry (temp/util/memory/power/PCIe/perf), **Kubernetes integration via Helm chart**, Slurm support, configurable ports, container deployment, "**Beta: Kubernetes DRA GPU claim support (Kubernetes 1.34+)**". https://github.com/ROCm/device-metrics-exporter
135. ROCm k8s-device-plugin installation guide (v1.3.1 docs, fetched 2026-11-04): Option 2 "Device Plugin with Health Checks" — "requires the AMD Device Metrics Exporter to be installed. This service provides GPU metrics and health information that the device plugin connects to" (example values: image `docker.io/rocm/device-metrics-exporter:v1.2.0`, ClusterIP port 5000, socket + hostPath `/var/lib/amd-metrics-exporter`); node labeller adds `amd.com/gpu.*` labels (device-id, product-name, vram, simd/cu-count, family, firmware). https://instinct.docs.amd.com/projects/k8s-device-plugin/en/latest/user-guide/installation.html
136. ROCm/gpu-operator (GitHub, fetched 2026-11-04; last push 2026-10-24): "AMD GPU Operator simplifies the deployment and management of AMD Instinct™ and AMD Radeon™ GPU accelerators"; components: operator controller, K8s device plugin, node labeller, K8s DRA driver, Device Config Manager, **Device Metrics Exporter**, device test runner, NFD operator, **kernel module management (KMM)**; K8s 1.29+; chart `rocm/gpu-operator-charts` (v1.4.0 quickstart); "Grafana Dashboards" bundled for exporter metrics. https://github.com/ROCm/gpu-operator
137. NVIDIA/DCGM (GitHub, fetched 2026-11-04): "NVIDIA Data Center GPU Manager (DCGM) is a project for gathering telemetry and measuring the health of **NVIDIA GPUs**" → NVIDIA-only by definition; no DCGM-class node-level exporter exists for RDNA4. https://github.com/NVIDIA/DCGM
138. Kepler — sustainable-computing-io/kepler (CNCF Sandbox; GitHub + metrics docs, fetched 2026-11-04): "Prometheus exporter that measures energy consumption metrics at the container, pod, and node level"; repo topics `nvml`/`nvml-monitoring` (GPU path is DCGM/NVML-based, i.e. NVIDIA); no AMD GPU telemetry path documented; k8s-monitoring exposes a kepler slot (`costMetrics`/energy) which the **lab wrapper leaves disabled** with opencost [repo]. https://github.com/sustainable-computing-io/kepler
139. **[repo]** in-repo grounding (this session, 2026-11-04): `charts/k8s-monitoring/values.yaml` (both `annotationAutodiscovery` and `prometheusOperatorObjects` enabled, `destinations` prometheus→`prometheus.spencerslab.com/api/v1/write` + loki, collectors alloy-metrics/singleton/logs, kepler/opencost disabled); `helm show chart grafana/k8s-monitoring --version 4.5.5` + feature template/values reads [129]; `helm show values prometheus-community/kube-prometheus-stack --version 78.1.0` → prometheus image v3.6.0 [132]; **live MCP probe** (readonly-ai-gpu-kubernetes, 2026-11-04): gpu-ai `default` ns — `grafana/alloy:v1.21.2` collectors (metrics-0 statefulset, logs daemonset, singleton) + alloy-operator 1.14.3 all Running; `amd-gpu-device-plugin-daemonset` (`rocm/k8s-device-plugin:1.31.0.9`) **already mounts hostPath `/var/lib/amd-metrics-exporter`** (unused today — R1[27]); `services/monitoring/prod/values.yaml` — `enableRemoteWriteReceiver: true`, `retention: 7d`, Grafana datasource provisioning (Prometheus uid `prometheus` / Loki / Alertmanager) + `grafana.dashboards.<folder>` `gnetId:`/`url:` + `datasource:` convention (crowdsecurity ×4, seaweedfs, cloudnative-pg, emqx ×5 entries), **no PrometheusRule/Alert template anywhere in the repo** (grep); `services/monitoring/prod/templates/self-monitor.yaml` (ServiceMonitor precedent, monitoring cluster) and `exporter-mikrotik-scrape-config.yaml` (static ScrapeConfig — the actual scrape behind exporter-mikrotik's **inert `prometheus.io/*` annotations**, the repo's only such user); `charts/k8s-monitoring/Chart.yaml` pins `prometheus-operator-crds` 32.0.2 (the CRDs for PodMonitor/ServiceMonitor); kube-state-metrics `deploy: true` via telemetryServices.

### Reliability notes (R5, self-review)

- **High confidence** (primary sources, exact tag, mutually consistent): the v0.33.0
  metrics surface (docs table [120] cross-checked against the v0.33.0 source
  registrations [121][122][123] — the spec-decode family is source-verified because the
  docs table shows only the per_pos counter); endpoint/port facts [124][125]; the
  k8s-grafana.com annotation namespace + port semantics + no-dedup conflict behavior
  (chart templates read from the exact pinned v4.5.5 [129] + feature READMEs + Alloy
  component docs [130]); RW 0.1 classic-histogram integrity + central 3.6.0 version
  (chart values [129][132]); dashboard contents (both JSONs fetched from the v0.33.0 tag,
  every expr enumerated [128]); logging flags + the #29023 fix [125][126][127]; DME/DCGM/
  Kepler/GPU-Operator facts (official repos/docs fetched [133][134][135][136][137][138]).
- **Medium confidence:** (a) the `job="vllm"` label assumption for alert #1 (annotation
  fallback chain read from chart templates [129]; app-template does set
  `app.kubernetes.io/name` — confirm on the live target at deploy); (b) the DME
  "nominally in scope for R9700" read — it rests on the "Radeon AI platform" requirements
  line [133] while the per-metric matrix stays MI-tagged and the host distro is
  Ubuntu-only; (c) the *expected-good* RDNA4 sensor set for the follow-up card (core
  telemetry vs the degraded `GPU_PROF_*` notes).
- **Weakest claim:** "the two official dashboards import cleanly via the repo's `url:`
  convention" — the convention is proven by five other `url:` entries in the same values
  file [139] and the dashboards' variable shape (type-based datasource lookup, no
  `__inputs`) was verified directly [128], but the actual import was not executed (no
  Grafana write tier in this session); the plan's acceptance should include opening both
  dashboards in the central Grafana.
- **Perspective weighting:** the scrape-mechanics evidence is unusually strong (the exact
  pinned chart version was read, not paraphrased from docs), which is where prior
  research (EXPLORE §3) actually contained an error; the GPU-exporter evidence is
  one-directional (AMD docs are MI-centric), so the R9700/8060S applicability claims are
  deliberately framed as "nominally in scope / unverified" rather than "supported".
- **Blind spot** (nothing found): no public end-to-end report of vLLM-on-RDNA scraped by
  k8s-monitoring/Alloy into a central Prometheus (this lab's exact topology); no public
  DME-on-RDNA4-consumer (R9700) or DME-on-APU (8060S) data; no public pairing of the
  exporter with the device-plugin health socket on k3s/openSUSE. All three are the
  follow-up card's on-target tests, not planning blockers.

---

## Post Research — load-bearing assumptions of the approved plan (2026-11-04)

Commissioned after planning (per the card's legacy Research checklist, "After Planning"
timing): verify the five load-bearing assumptions of the approved plan (R1 OQ4, D2, D4,
D5, R1 OQ2, and the C01 plugin leg) BEFORE test-writing or development. Sources 140–156,
all fetched 2026-11-04 against pinned tags/repos (vLLM tag v0.33.0, the GGUF plugin's
tag v0.0.5 + main, HF API, ROCm 10.0.0 docs, in-repo greps).

### TL;DR

- **The GDN-hybrid model family is natively supported in vLLM v0.33.0** —
  `Qwen3_5ForConditionalGeneration` (Qwen3.8-27B's exact architecture) is registered with
  the full GDN implementation and a ROCm-capable GDN kernel path (Triton/FLA prefill port;
  RDNA AITER-Triton decode kernels). The model is not the risk; no vLLM version bump.
- **The C01 plugin leg needs a fix**: the newest released `vllm-gguf-plugin` (v0.0.5)
  CANNOT load the 27B GGUF (no Qwen3.5 adapter); that support exists on the plugin's
  **main only** (PR #98) — and plugin main has a top-level import of a vLLM module that
  vLLM removed BEFORE the v0.33.0 tag, so main is not importable on the pinned base
  as-is. C01 must pin a git ref + a 2-line import patch (strata carry-patch precedent).
- `ROCR_VISIBLE_DEVICES` **is** still the correct chip-targeting variable under ROCm 10
  (value = device index or UUID, not a PCI ID); it already coexists with the amd-gpu
  device plugin on this node (the strata pod runs it). D2 stands as-is.
- The official FP8 checkpoint **exists**: `Qwen/Qwen3.8-27B-FP8`, 28.77 GiB, W8A8 dynamic
  e4m3 — the values-only fallback leg is viable; loadable on gfx1201 with the "young"
  compute path (`--enforce-eager` already in D4).
- Sleep mode is CUDA+ROCm-supported in v0.33.0, but the `/sleep`+`/wake_up` HTTP
  endpoints are **behind `VLLM_SERVER_DEV_MODE=1`** (C02 must set it); GDN state is
  discarded on sleep (regression-tested); a documented ROCm wake-time caveat (unreclaimed
  VRAM, ~2× peak) must go into the C06 runbook sequence.

### V1 — GDN-hybrid GGUF compatibility in vLLM v0.33.0 (highest risk; D1/D4/HR7, C01 plugin leg)

**Model family (vLLM core) — supported in v0.33.0; no version bump required.**

- Tag facts: v0.33.0 tagged 2026-11-01T09:21:10Z → commit `4ba787ec` (2026-10-31) [140].
- Registry (v0.33.0 `vllm/model_executor/models/registry.py`): `Qwen3_5ForConditionalGeneration`
  + `Qwen3_5MoeForConditionalGeneration` → module `qwen3_5` (lines 617–620);
  `Qwen3_5ForCausalLM`/`Qwen3_5MoeForCausalLM` (lines 204–205); MTP classes
  `Qwen3_5MTP`/`Qwen3_5MoeMTP` → `qwen3_5_mtp` (lines 739–740); plus `Qwen3Next*` (line 118)
  and `Qwen4Exp*` (lines 119–121, 622–624) [141]. Qwen3.8-27B's HF config
  (`model_type: qwen3_5`, arch `Qwen3_5ForConditionalGeneration`) [R1-19] maps to a
  registered class.
- Implementation (`qwen3_5.py`, 756 lines @ v0.33.0): `Qwen3_5DecoderLayer(Qwen3NextDecoderLayer)`
  instantiates `QwenGatedDeltaNetAttention` for every `layer_type == "linear_attention"`
  layer — the 48 GDN layers — and full attention for the 16 [142]. The GDN/full-attn split
  R1 read from the HF config is exactly what the model class implements.
- GDN kernels on ROCm: the prefill backend resolves to **"triton"** (Triton/FLA port) for
  any ROCm device; `aiter_flydsl` is opt-in and CDNA3+-gated (lines 204–235) [143].
  AITER RDNA GDN Triton decode kernels exist as an optional path
  (`rocm_aiter_ops.is_rdna_gdn_triton_kernels_available()`, lines 90–103); the fused MTP
  decode is a Triton port on ROCm (lines 113–115) [143]. So on gfx1201 the GDN layers run
  on the Triton path in v0.33.0 — loadable, not CUDA-only; the performance path is the
  "young" one R1 flagged (no RDNA AITER prebuilds in the image [R1-3]).
- Note: vLLM v0.33.0's own `models/qwen3_5.py` imports `Qwen3_5Config` et al. from
  `transformers` — the vendored `vllm/transformers_utils/configs/qwen3_5.py` is NOT in
  v0.33.0 (see the skew below) [142][150].

**GGUF leg (the plugin) — the actual risk; two independent gaps.**

- The plugin's newest release is **v0.0.5 (2026-08-10)**; PyPI carries only 0.0.1–0.0.5
  [147]. Its adapter file list has **no Qwen3.5 support** (base/default/diffusion/gemma3
  only) [148]. The default adapter resolves the GGUF arch by matching
  `gguf.MODEL_ARCH_NAMES` values against `hf_config.model_type` and
  `raise RuntimeError(f"Unknown gguf model_type: {model_type}")` on no match (lines 144–150)
  [148]; the `gguf` package's arch names are `qwen35`/`qwen35moe`/`qwen3next` while the HF
  model_type is `qwen3_5` → **no released plugin version can load the 27B GGUF**.
- The Qwen3.5/3.6 GGUF adapters (`Qwen35GGUFAdapter` + `Qwen35MtpGGUFAdapter`; explicit GDN
  tensor map: `attn_qkv`→`linear_attn.in_proj_qkv`, `attn_gate`→`in_proj_z`,
  `ssm_alpha`→`in_proj_a`, `ssm_beta`→`in_proj_b`, `ssm_conv1d`→`conv1d`,
  `ssm_norm`→`norm`, `ssm_out`→`out_proj`, `ssm_dt.bias`→`dt_bias`,
  `ssm_a.weight`→`A_log`; MTP `nextn` block loaded when present, skipped otherwise) landed
  on **main only — PR #98, merged 2026-08-18** — 8 days *after* v0.0.5 shipped, so **no
  PyPI release contains them** [149][147]. The main-branch README's "tested model coverage"
  rows (Qwen 3.5 Q4_K_M backbone + BF16 projector; Qwen 3.6 UD-IQ2_XXS) are main-only
  statements [147].
- **Version skew (new, critical):** plugin main (HEAD `e454affe`, 2026-10-24) imports
  `from vllm.transformers_utils.configs.qwen3_5 import Qwen3_5Config` (+ `qwen3_5_moe`)
  **top-level** in `weights_adapter/qwen3_5.py`, and `weights_adapter/__init__.py` /
  `loader.py` import it unconditionally [149]. That vLLM module was added in vLLM #34512
  (2026-02-13) and **removed in vLLM #60623 (2026-10-09, "Remove vendored code made
  redundant by Transformers 5.16.1")** — i.e. it is absent from vLLM v0.33.0 (raw 404 +
  zero qwen* files in `vllm/transformers_utils/configs/`, both verified against the tag;
  vLLM's own model file moved the import to `transformers`) [150]. Installing plugin main
  on `vllm/vllm-openai-rocm:v0.33.0-rocm100` → ModuleNotFoundError in the
  `vllm.general_plugins` registration chain → the image cannot serve GGUF at all.
- The plan's C01 task as written ("`pip install vllm-gguf-plugin==<concrete version>`",
  "dev picks the newest plugin release") hits both gaps: the newest release has no
  adapter; main has the adapter but a broken import. **Fix (C01, required):** pin the
  plugin to a **git ref** (main ≥ `e454affe0ca23c9dc8754ec3033270cb30622ed5`, or the first
  release containing #98 plus the import fix) and add a **2-line import-compat patch** in
  the overlay (both config names from `transformers` — exported by the transformers 5.x
  inside the v0.33.0 image; vLLM v0.33.0's own `models/qwen3_5.py` imports them from there
  [142][150]). Precedent: the strata overlay already applies a vendored patch stage
  (`carry/ornith-q36.patch`) [156-context: containers/strata]. Record the ref + patch in
  the tag→digest ledger; update C01 AC#3 and test t5 (regex `vllm-gguf-plugin==\d` →
  accept a `git+https://…@<sha>` pin + patch presence). C06's first engine gate:
  `python -c "import vllm_gguf_plugin"` + GGUF serve load + 1 token.
- MTP note: the live-rung GGUF (unsloth UD-Q4_K_XL) carries **no embedded MTP/nextn block**
  (repo comment: tensor-scan verified [156]) → per the plugin README the backbone "loads
  normally without MTP" when `--speculative-config` is omitted [147] — consistent with
  MTP-on-AMD being under development (R1).
- **Plan impact: none of D1/D4/HR7 change** (base image, Q4-GGUF weight path, overlay shape
  all remain correct); the vLLM pin stays v0.33.0 — the family is in-tree there, so no
  pin bump, no different model, no different weight format is forced. The C01 chunk's
  task/AC/test text must change (above).

### V2 — Chip-targeting env under ROCm 10 (D2, R1 OQ4)

- **`ROCR_VISIBLE_DEVICES` is still the correct variable under ROCm 10.** ROCm 10.0.0
  official "GPU isolation techniques": "`ROCR_VISIBLE_DEVICES` — A list of device indices
  or UUIDs that will be exposed to applications. Runtime: ROCm Software Runtime. Applies
  to all applications using the user mode ROCm software stack" (example
  `ROCR_VISIBLE_DEVICES="0,GPU-<uuid>"`) [151]. HIP env-variables reference: "On Linux,
  use ROCR_VISIBLE_DEVICES" [152].
- **The value is a device index (or UUID) — not a PCI ID** [151]. `HSA_OVERRIDE_GFX_VERSION`
  remains an *arch override* for unsupported cards (R1 Q1) — not chip selection, and not
  needed for gfx1201.
- **Coexistence with the amd-gpu device plugin: yes — it is the lab's live pattern.** The
  plugin advertises `amd.com/gpu` count-only (cannot name chips [R1-27]); a pod requesting
  `amd.com/gpu: 1` receives both chips' `/dev/kfd`+`/dev/dri` and the env picks one. On
  this exact node the strata pod already runs it:
  `charts/llama-swap/templates/configmap-strata.yaml:40–43` renders
  `ROCR_VISIBLE_DEVICES=<dev>` per model from `strata.rocrVisibleDevices` (default `"0"` =
  R9700, `"1"` = 8060S), with runbook §1.9/0.14 gating the index via `rocminfo` [156]. The
  official k8s-device-plugin vllm-serve example matches the plan's pod shape (amd.com/gpu
  "1", seccomp Unconfined, runAsGroup 44, SYS_PTRACE, hostIPC, shm 8Gi, non-privileged) —
  it omits the env only because it assumes a single-GPU node [153].
- Residual on-target fact (already planned): the R9700's index under the
  v0.33.0-rocm100 image's ROCr enumeration → C06 runbook `rocminfo` gate (runbook
  0.14/§1.9 pattern [156]).
- **Verdict: D2 stands as-is** (`ROCR_VISIBLE_DEVICES: "0"` default; values key retargets).

### V3 — PVC weight facts (repo side; D4/HR7, C06)

- **The exact Q4-class GGUF on the 500 GiB PVC**: `Qwen3.8-27B-UD-Q4_K_XL.gguf`
  (**16.35 GiB**) in `unsloth/Qwen3.8-27B-GGUF` [155] — the file the live
  `qwen3.8-27b-q4` rung references (`hf: unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL`,
  `services/gpu-ai/prod/values.yaml:311–320`; the chart family composes the same tag via
  `tagCulture: unsloth-ud`, `charts/llama-swap/values.yaml:219–236`) [156]. The other 27B
  rungs: UD-Q6_K_XL (23.56 GiB), Q8_0 (27.05 GiB), ggml-org BF16 (2 shards, 50.9 GiB)
  [155][156]. HR7's "reuse the existing weights" is literally true for the Q4 file, and its
  exact filename is now known. (R1 §3's "~16 GiB Q4" estimate [R1-3] matches 16.35 GiB.)
- **On-disk path / download mechanism**: the weights were populated by **llama.cpp's `-hf`
  auto-fetch** into the HF cache under `LLAMA_CACHE=/models` (chart env,
  `charts/llama-swap/values.yaml:1011`) in the huggingface_hub layout
  `hub/models--unsloth--Qwen3.8-27B-GGUF/snapshots/<commit>/Qwen3.8-27B-UD-Q4_K_XL.gguf`
  [155][156]. There is no repo download job for the 27B rungs (the strata weights use a
  separate `model-fetch` initContainer, `charts/llama-swap/values.yaml:1153–1197`, runbook
  §2 [156]). Claim facts: 500Gi local-path RWO (`services/gpu-ai/prod/values.yaml:88`),
  `existingClaim: *chartName` → `globalMounts: /models`
  (`charts/llama-swap/values.yaml:1380–1387`) [156]. The vLLM pod mounts the same claim
  read-only and passes the snapshot path as `--model`; the exact snapshot hash resolves on
  target (C06 gate: `find /models -name 'Qwen3.8-27B-UD-Q4_K_XL.gguf'`).
- Side fact: the MTP draft (`ggml-org/Qwen3.8-27B-GGUF:mtp-Qwen3.8-27B-Q8_0.gguf`) is a
  separate file on the PVC [156] — irrelevant to vLLM (no MTP on AMD, R1).

### V4 — FP8 checkpoint fallback exists (R1 OQ2)

- **It exists**: `Qwen/Qwen3.8-27B-FP8` — created 2026-08-13, 4.89M downloads, apache-2.0,
  tags `qwen3_5` / `fp8` / `base_model:quantized:Qwen/Qwen3.8-27B` [154]. Size **28.77 GiB**
  (81 files: 64 per-layer shards ~0.35–0.36 GiB + `outside.safetensors` 5.59 GiB (vision +
  embeddings) + `mtp.safetensors` 0.44 GiB) [154]. Format:
  `quantization_config {quant_method: fp8, fmt: e4m3, activation_scheme: dynamic,
  weight_block_size}` — vLLM's standard W8A8 dynamic-FP8 path; arch
  `Qwen3_5ForConditionalGeneration` [154]. Matches R1's ~28.5 GiB estimate [R1-3]. (An
  AWQ checkpoint is moot — R1 already ruled AWQ ❌ on stock vLLM-AMD [R1-4].)
- **Loadable by vLLM v0.33.0 on ROCm gfx1201**: the load path is stock (no plugin). The
  *compute* path is the "young" one R1 flagged — vllm#28649 (native FP8 WMMA for gfx1201)
  is open, with FP32-dequant fallbacks on untuned shapes and the batched-FP8
  graph-capture NaN bug that D4's `--enforce-eager` already neutralizes [R1-20][R1-21].
  FP8-on-gfx1201 existence proofs: the 2×R9700 32B-FP8 eager measurements (Sep 2026,
  [R1-20]) and the community RDNA4 fork serving 27B-FP8 [R2-40].
- **The fallback leg is values-only**: `--model Qwen/Qwen3.8-27B-FP8` +
  `--language-model-only` (the repo ships vision + MTP files; the flag skips the tower),
  no plugin, no chart change — at the cost of KV headroom: R1 §3 table ~0.9 GiB → ~29k
  fp8-KV tokens ≈ 1 session [R1-3][154].

### V5 — Sleep mode on v0.33.0 ROCm (D5, HR6)

- **Present and ROCm-supported**: `--enable-sleep-mode` (plus `--sleep-mode-backend`,
  `--sleep-mode-offload-cudagraph`, `--sleep-preserve-parameter-names`) in the v0.33.0
  engine args (arg_utils lines 799–803, 1047–1058); the worker implements
  `sleep(level)`/`wake_up(tags)`/`discard` with an explicit ROCm branch (5 s VRAM-free
  grace deadline, gpu_worker line 325) [144]; the docs state "This feature is now supported
  on CUDA and ROCm platform" [145].
- **What survives**: level 1 = weights offloaded to CPU RAM (preserved) + KV cache
  discarded (content forgotten); level 2 = weights + KV discarded (non-quantized buffers
  kept in CPU; weights restored via `collective_rpc("reload_weights")`) [145]. **GDN
  recurrent/conv state is NOT preserved** — it lives in the state-cache pool: the in-tree
  regression test (`tests/models/language/generation/test_gdn_sleep_wake.py`, Qwen3-Next =
  same GDN layer class as qwen3_5) documents "the state-cache tag is discarded on sleep
  and its device memory is re-created on wake" and asserts post-wake generation is neither
  degenerate (single repeated token) nor NaN [146]. For the GGUF-plugin model there is no
  additional obstacle — sleep offloads the loaded GPU parameters through the same backend.
- **The HTTP lever is dev-gated (C02 gap)**: `/sleep`, `/wake_up`, `/is_sleeping`,
  `/release_kv_cache_memory` live in the *dev* router, attached only when
  `envs.VLLM_SERVER_DEV_MODE` is true (default False; launchers/api_server/routers.py
  lines 46–49) [144]. The docs' own usage example runs
  `VLLM_SERVER_DEV_MODE=1 vllm serve … --enable-sleep-mode` [145]. → **C02 must set
  `VLLM_SERVER_DEV_MODE: "1"` in the container env**, or HR6's operator time-sharing has
  no HTTP surface.
- **The caveat that could break HR6 (ROCm wake-time coexistence)**: the GDN sleep/wake
  test docstring warns "On some (notably ROCm/amdgpu) drivers the VRAM discarded by
  sleep() is not returned to the free pool before wake_up() re-creates it, so the woken
  allocation must coexist with the not-yet-reclaimed one (~2x peak). A high
  gpu_memory_utilization then OOMs in cuMemCreate on wake" [146]. With D4's
  `--gpu-memory-utilization 0.95` and a possibly resident Strata arena, a wake-up after a
  level-1 sleep can OOM → the C06 runbook must sequence: sleep → **verify VRAM
  reclamation** (free-VRAM gate) → wake → then allow Strata re-pin. Sleep state is
  observable via `vllm:engine_sleep_state` (R3's `/metrics` inventory).

### Contradictions and how to weigh them (post-research)

1. **Plugin README "tested coverage" (main: Qwen 3.5 GGUF) vs released v0.0.5 (no adapter)
   vs the vLLM v0.33.0 import skew.** All three are true at once: the tested rows are
   main-only (PR #98, 2026-08-18; no release since) [147][149]; v0.0.5 predates #98 by 8
   days [147][149]; the main import was written against a vLLM that still vendored the
   config and has not been updated for #60623 [149][150]. *Weigh*: trust the code, not the
   README — pin a git ref + patch; the on-target probe (C06) decides.
2. **"Supported on CUDA and ROCm platform" (sleep docs) vs the endpoints behind a dev
   flag** [145][144] — both true: the engine feature is platform-supported; the HTTP
   surface is a dev-mode convenience. The C02 env var closes the gap.
3. **R1's "GGUF highly experimental / OOT" [R1-6] vs the model family being fully in-tree**
   — the experimental part is precisely the weight adapter (the plugin), not the model
   class (in-tree since Feb 2026 [150][142]). The risk concentrates exactly where V1 says.

### Implications for the plan (post-research)

- **C01 (required chunk fix — not a replan)**: plugin pin = git ref (main ≥
  `e454affe0ca23c9dc8754ec3033270cb30622ed5`, or the first release containing #98 + the
  import fix) instead of a PyPI release; add the 2-line import-compat patch (→
  `transformers`) in the overlay; record ref + patch in the ledger (strata carry-patch
  precedent); update AC#3 and test t5 to accept the git pin + patch.
- **C02 (small addition)**: `VLLM_SERVER_DEV_MODE: "1"` container env (the sleep/wake HTTP
  surface for the HR6 discipline).
- **C06 runbook gates (on-target, operator-run)**: (1) `python -c "import vllm_gguf_plugin"`
  + GGUF serve load + 1 token (plugin + GDN proof); (2) `find /models -name
  'Qwen3.8-27B-UD-Q4_K_XL.gguf'` to resolve the snapshot path; (3) `rocminfo` index check
  (already planned); (4) sleep → reclaim-verify → wake sequence before Strata re-pin (V5
  caveat); (5) the FP8 fallback procedure (V4).
- **Locked decisions unchanged**: D1 (image + overlay), D2 (R9700 + env), D4 (envelope +
  Q4 GGUF), D5 (sleep-mode ON), D9 (flash stays on Strata), HR7 (Q4_K GGUF reuse) all
  stand. The plan's v0.33.0 pin is confirmed correct — the family is in-tree there; nothing
  forces a pin bump, a different model, or a different weight format.

### Open questions (post-research)

1. **C01 chunk fix (required, not a replan)** — the pin-source + import-patch change per V1
   must land in C01's task/AC/test before dev starts.
2. Whether vllm-gguf-plugin maintainers ship a release containing #98 (v0.0.6?) or fix the
   import for vLLM ≥ #60623 — watch-item; the overlay patch is the meantime path.
3. On-target: does the GGUF + GDN load of qwen3_5 actually work on gfx1201 under the
   patched plugin? Public tested coverage is main-README only (no public RDNA GGUF+GDN run
   found).
4. On-target: the R9700's ROCr index under the v0.33.0-rocm100 image (C06 gate).
5. On-target: VRAM-reclamation behavior after a level-1 sleep on this amdgpu driver
   (the ~2×-peak caveat; C06 measurement).

### Sources (post-research)

All fetched 2026-11-04 via GitHub API / raw at the named tag, HF API, ROCm 10.0.0 docs,
and in-repo greps. Cross-round re-citations: [R1-n], [R2-n], [R3-n].

140. vLLM tag v0.33.0 (GitHub API, fetched 2026-11-04): annotated tag 2026-11-01T09:21:10Z → commit `4ba787ec9959e566d3b587a796dff07673324da5` (committed 2026-10-31T07:15:45Z, "[CI][Bugfix] Pin the ColUltraVBERT test checkpoint…"). https://api.github.com/repos/vllm-project/vllm/git/refs/tags/v0.33.0
141. vLLM v0.33.0 source — `vllm/model_executor/models/registry.py` (fetched from the tag): `Qwen3_5ForCausalLM`/`Qwen3_5MoeForCausalLM` → `qwen3_5` (lines 204–205); `Qwen3_5ForConditionalGeneration`/`Qwen3_5MoeForConditionalGeneration` (lines 617–620); `Qwen3_5MTP`/`Qwen3_5MoeMTP` → `qwen3_5_mtp` (lines 739–740); `Qwen3NextForCausalLM` (line 118); `Qwen4ExpForCausalLM`/`Qwen4ExpForConditionalGeneration`/`Qwen4ExpMTP` (lines 119–121, 622–624, 737). https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/models/registry.py
142. vLLM v0.33.0 source — `vllm/model_executor/models/qwen3_5.py` (756 lines, fetched from the tag): `Qwen3_5DecoderLayer(Qwen3NextDecoderLayer)` — `self.linear_attn = QwenGatedDeltaNetAttention(...)` for `layer_type == "linear_attention"`, full attention for `full_attention` (lines 149–157); `Qwen3_5ForConditionalGeneration(Qwen3VLForConditionalGeneration, IsHybrid)` (line 473); gated-delta-net mamba state dtype/shape/copy functions; `from transformers import (Qwen3_5Config, Qwen3_5MoeConfig, Qwen3_5MoeTextConfig, Qwen3_5TextConfig)` (lines 32–37). https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/models/qwen3_5.py
143. vLLM v0.33.0 source — `vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py` (fetched from the tag): `_resolve_gdn_prefill_backend` — ROCm branch returns `"triton"` (Triton/FLA port) unless `aiter_flydsl` explicitly requested (CDNA3+-gated; lines 204–235); `GDN_AITER_TRITON_AVAILABLE` includes `rocm_aiter_ops.is_rdna_gdn_triton_kernels_available()` (RDNA GDN Triton decode kernels, lines 90–103); `supports_fused_mtp_decode()` = True on ROCm (Triton port; lines 113–115). https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/layers/mamba/gdn/qwen_gdn_linear_attn.py
144. vLLM v0.33.0 source (fetched from the tag, four files): `vllm/engine/arg_utils.py` (lines 799–803 `enable_sleep_mode`/`sleep_mode_backend`/`sleep_mode_offload_cudagraph`/`sleep_preserve_parameter_names`; lines 1047–1058 `--enable-sleep-mode` et al.); `vllm/v1/worker/gpu_worker.py` (`sleep(level=1)`/`wake_up(tags)`/`discard`; level 2 saves parameters + buffers to CPU first; line 325 ROCm 5 s VRAM-free grace deadline); `vllm/entrypoints/serve/dev/sleep/api_router.py` (`POST /sleep?level=0..2&mode=`, `POST /wake_up?tags=`, `GET /is_sleeping`, `POST /release_kv_cache_memory`); `vllm/entrypoints/launchers/api_server/routers.py` (lines 46–49: dev routers attached only when `envs.VLLM_SERVER_DEV_MODE`); `vllm/envs.py` (line 171: `VLLM_SERVER_DEV_MODE` default False). https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/entrypoints/launchers/api_server/routers.py (+ the other four paths)
145. vLLM v0.33.0 docs — `docs/features/sleep_mode.md` (fetched from the tag): "This feature is now supported on CUDA and ROCm platform"; level 1 = offload weights to CPU RAM + discard KV (weights backed up in CPU memory); level 2 = discard weights + KV (buffers kept; restore via `collective_rpc("reload_weights")`); usage example runs `VLLM_SERVER_DEV_MODE=1 vllm serve … --enable-sleep-mode`. https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/docs/features/sleep_mode.md
146. vLLM v0.33.0 source — `tests/models/language/generation/test_gdn_sleep_wake.py` (fetched from the tag): regression test "Hybrid Mamba / gated-delta-net (GDN) models (e.g. Qwen3-Next) keep a persisted conv + recurrent state cache. With sleep mode … the state-cache tag is discarded on sleep and its device memory is re-created on wake …" asserting post-wake generation is neither degenerate nor NaN; ROCm caveat in the docstring: "On some (notably ROCm/amdgpu) drivers the VRAM discarded by sleep() is not returned to the free pool before wake_up() re-creates it, so the woken allocation must coexist with the not-yet-reclaimed one (~2x peak). A high gpu_memory_utilization then OOMs in cuMemCreate on wake." https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/tests/models/language/generation/test_gdn_sleep_wake.py
147. vllm-project/vllm-gguf-plugin (GitHub, fetched 2026-11-04): newest tag **v0.0.5** (release published 2026-08-10; release notes incl. "Fix ROCm 7.x build failure: drop CUDA-only --use_fast_math from hipified nvcc args" → ROCm builds supported); PyPI carries only 0.0.1–0.0.5; main HEAD `e454affe0ca23c9dc8754ec3033270cb30622ed5` (2026-10-24, "[BugFix] Flatten batched inputs in the GGUF linear method (#149)"); README (main): "The plugin uses vLLM's model implementations and a generic GGUF weight adapter, so model compatibility is broader than a fixed allowlist" + tested-coverage rows "Qwen 3.5 | Q4_K_M backbone with BF16 projector" and "Qwen 3.6 | UD-IQ2_XXS backbone with BF16 projector" (main-branch only); MTP: "For a GGUF without a `nextn` block, omit `--speculative-config`; the backbone loads normally without MTP"; install `pip install -e . --no-build-isolation` against vLLM's torch; entry point `vllm.general_plugins` → `vllm_gguf_plugin:register` (quantization config "gguf" + model loader "gguf" + config parser "gguf" + EngineArgs patch: GGUF ref → auto `quantization/load_format/config_format`, model = config source from tokenizer); workflows are pre-commit + release-build only (no vLLM functional test matrix in the workflow names). https://github.com/vllm-project/vllm-gguf-plugin
148. vllm-project/vllm-gguf-plugin @ v0.0.5 — `vllm_gguf_plugin/weights_adapter/default.py` (fetched 2026-11-04): arch resolution `for key, value in gguf.MODEL_ARCH_NAMES.items(): if value == model_type: …; if arch is None: raise RuntimeError(f"Unknown gguf model_type: {model_type}")` (lines 144–150); v0.0.5 adapter file list has no `qwen3_5.py` (base/default/diffusion/gemma3 only). The `gguf` package's arch names for the family are `qwen35`/`qwen35moe`/`qwen3next` (llama.cpp gguf-py `constants.py`, lines 622/627/628, 1535–1541, fetched 2026-11-04) vs the HF model_type `qwen3_5` → no match. https://raw.githubusercontent.com/vllm-project/vllm-gguf-plugin/v0.0.5/vllm_gguf_plugin/weights_adapter/default.py
149. vllm-project/vllm-gguf-plugin — PR #98 "[Models] support Qwen3.5/3.6 multimodal GGUF and MTP" (merged 2026-08-18, commit `4ec8d615`): adds `vllm_gguf_plugin/weights_adapter/qwen3_5.py` (+430; `Qwen35GGUFAdapter` + `Qwen35MtpGGUFAdapter`; `QWEN35_MODEL_TYPES = ("qwen3_5", "qwen3_5_text", "qwen3_5_moe", "qwen3_5_moe_text")`; GDN tensor map `attn_qkv`→`linear_attn.in_proj_qkv`, `attn_gate`→`in_proj_z`, `ssm_alpha`→`in_proj_a`, `ssm_beta`→`in_proj_b`, `ssm_conv1d`→`conv1d`, `ssm_norm`→`norm`, `ssm_out`→`out_proj`, `ssm_dt.bias`→`dt_bias`, `ssm_a.weight`→`A_log`); `weights_adapter/__init__.py` imports it unconditionally (line 16); top-level import at file line 14: `from vllm.transformers_utils.configs.qwen3_5 import Qwen3_5Config` (+ `qwen3_5_moe` line 15) — file history: added by #98, touched once more by #124 "rename" (2026-08-30). https://github.com/vllm-project/vllm-gguf-plugin/pull/98
150. vLLM repo history for `vllm/transformers_utils/configs/qwen3_5.py` (GitHub commits API, fetched 2026-11-04): added by "[Misc] Port Qwen3.5 Configs (#34512)" 2026-02-13; removed by "[Chore] Remove vendored code made redundant by Transformers 5.16.1 (#60623)" 2026-10-09 — i.e. **absent at tag v0.33.0** (raw 404 verified for `qwen3_5.py` and `qwen3_5_moe.py` at the tag; the `configs/` dir listing contains zero qwen* files; vLLM v0.33.0's own `models/qwen3_5.py` imports the configs from `transformers` [142]). https://api.github.com/repos/vllm-project/vllm/commits?path=vllm/transformers_utils/configs/qwen3_5.py
151. ROCm 10.0.0 docs — "GPU isolation techniques" (fetched 2026-11-04): "`ROCR_VISIBLE_DEVICES` — A list of device indices or UUIDs that will be exposed to applications. Runtime: ROCm Software Runtime. Applies to all applications using the user mode ROCm software stack" (example `ROCR_VISIBLE_DEVICES="0,GPU-<uuid>"`); `HSA_VISIBLE_DEVICES`/`CUDA_VISIBLE_DEVICES`/`GPU_DEVICE_ORDINAL` listed as the other isolation variables. https://rocm.docs.amd.com/en/docs-10.0.0/reference/system-optimization/gpu-isolation.html
152. HIP env-variables reference (7.16.0 docs, fetched 2026-11-04): GPU isolation variables table — "On Linux, use ROCR_VISIBLE_DEVICES. On Windows, use HIP_VISIBLE_DEVICES." https://rocmdocs.amd.com/projects/HIP/en/latest/reference/env_variables.html
153. ROCm/k8s-device-plugin @ master — `example/vllm-serve/deployment.yaml` (fetched 2026-11-04): official non-privileged vLLM pod — `resources.{limits,requests}.amd.com/gpu: "1"`, `securityContext.seccompProfile: Unconfined`, `runAsGroup: 44`, `capabilities.add: [SYS_PTRACE]`, `hostIPC: true`, `hostNetwork: true`, shm `emptyDir{Memory, sizeLimit: 8Gi}` at `/dev/shm`; no `ROCR_VISIBLE_DEVICES` (single-GPU-node assumption). https://github.com/ROCm/k8s-device-plugin/tree/master/example/vllm-serve
154. Hugging Face — `Qwen/Qwen3.8-27B-FP8` (API, fetched 2026-11-04): created 2026-08-13, 4,890,540 downloads, apache-2.0, tags `qwen3_5`/`fp8`/`base_model:quantized:Qwen/Qwen3.8-27B`; 81 files totaling 30,890,049,597 B (**28.77 GiB**): 64× `layers-N.safetensors` (~0.35–0.36 GiB each) + `outside.safetensors` 5.59 GiB + `mtp.safetensors` 0.44 GiB; config: `architectures: [Qwen3_5ForConditionalGeneration]`, `model_type: qwen3_5`, `quantization_config {quant_method: fp8, fmt: e4m3, activation_scheme: dynamic, weight_block_size, modules_to_not_convert (visual blocks)}`. https://huggingface.co/Qwen/Qwen3.8-27B-FP8
155. Hugging Face — `unsloth/Qwen3.8-27B-GGUF` (API, fetched 2026-11-04): file list incl. **`Qwen3.8-27B-UD-Q4_K_XL.gguf` (16.35 GiB)** — the exact file of the live `qwen3.8-27b-q4` rung; UD-Q6_K_XL 23.56 GiB; Q8_0 27.05 GiB; Q4_0 14.95 GiB / Q4_1 16.34 GiB; UD-Q5_K_S/M/XL 17.4–19.4 GiB; UD-Q3_K_XL 12.24 GiB; UD-Q2_K_XL 9.15 GiB; UD-IQ1_S…UD-IQ3_S 5.8–11.2 GiB; BF16 2 shards 50.9 GiB; `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` 1.28 GiB; mmproj F16/BF16. https://huggingface.co/unsloth/Qwen3.8-27B-GGUF
156. **[repo]** in-repo grounding (this session, 2026-11-04): `services/gpu-ai/prod/values.yaml:88` (`modelsPvcSize: 500Gi`), `:283` (family enablement), `:308–310` (comment: "The unsloth GGUFs carry no embedded MTP layers (verified: tensor scan of the header)"), `:311–320` (`qwen3.8-27b-q4`: `hf: unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL`, `draft: ggml-org/Qwen3.8-27B-GGUF:mtp-Qwen3.8-27B-Q8_0.gguf`), `:322–331` (q6 UD-Q6_K_XL), `:368–380` (q8 Q8_0), `:402–411` (bf16 ggml-org BF16); `charts/llama-swap/values.yaml:10` (`modelsPvcSize: 300Gi` default), `:219–236` (family `qwen3.8-27b`: `hfRepo: unsloth/Qwen3.8-27B-GGUF`, `tagCulture: unsloth-ud` → q4: UD-Q4_K_XL / q6: UD-Q6_K_XL, q8: Q8_0, bf16: ggml-org BF16), `:1011` (env `LLAMA_CACHE: /models`), `:1153–1197` (strata `model-fetch` initContainer, `STRATA_QUANTS: "q3"`), `:1380–1387` (`persistence.models`: `existingClaim: *chartName` → `globalMounts: - path: /models`); `charts/llama-swap/templates/configmap-strata.yaml:40–43` (renders `ROCR_VISIBLE_DEVICES=<dev>` per model); `.agents/notes/strata-host-prep-gpu-ai.md:41` (gate 0.14 `rocminfo`), `:167–183` (§1.9 ROCm device indices → the two values keys; `rocrVisibleDevices` default `"0"` [VERIFY] gfx1201 index; `"1"` mirrors PR #3636's dGPU-first enumeration), `:185–215` (§2 model-fetch provisioning, `/models/strata` layout); `charts/llama-swap/tests/test_strata_config_schema.py:146–147` (pins `ROCR_VISIBLE_DEVICES=0` default).

### Reliability notes (post-research, self-review)

- **High confidence** (source fetched at the exact tag/ref): registry/model/GDN-kernel
  facts [140][141][142][143]; plugin release/PR/import skew [147][148][149][150] (raw 404s
  + commit dates + file-history check); FP8 + GGUF file facts (HF API with byte sizes)
  [154][155]; repo line cites (in-repo greps) [156]; sleep-mode mechanics + dev gating +
  GDN sleep/wake test + ROCm wake caveat [144][145][146]; ROCm 10 isolation semantics
  [151][152].
- **Medium confidence:** the V1 fix (git pin + 2-line patch) is *designed* to work — the
  `transformers` import is backed by vLLM v0.33.0's own model file [142][150] — but the
  patched plugin was not executed in this session (no docker daemon / no venv build); the
  C06 import + load probe is the acceptance.
- **Weakest claim:** "v0.0.5 fails with `Unknown gguf model_type: qwen3_5`" — the exact
  failure point (config-parser gate vs default-adapter arch lookup) depends on
  `MODEL_FOR_CAUSAL_LM_MAPPING_NAMES` contents in the image's transformers, which was not
  enumerated; either path fails, and the on-target probe shows which error text.
- **Blind spot:** no public RDNA (gfx1201) run of the GGUF + GDN path in any plugin commit
  was found; the plugin repo's workflows are pre-commit + release-build only (no vLLM
  functional matrix in the workflow names) — presumably how the #60623 import skew went
  unnoticed upstream.
