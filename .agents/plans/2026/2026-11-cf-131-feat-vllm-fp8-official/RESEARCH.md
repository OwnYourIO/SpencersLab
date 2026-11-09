# RESEARCH — cf-131 "vLLM: drop GGUF — serve official FP8 checkpoint"

Pre-research commission, board card #131 (run `cf-131-feat-vllm-fp8-official`),
2026-11-07, by `agent-research`. STORM method, in-session grounded interviews
(five perspectives: vLLM engine source @ exact tag, RDNA4-FP8 performance line,
KV-quant format authors, MTP/spec-decode line, long-context/rope line),
`webfetch` + GitHub/Docker-Hub/HF APIs + in-repo grounding; all web evidence
accessed **2026-11-07** unless stamped otherwise. Citation keys `[n]` resolve in
the Sources section; repo grounding cross-cited as `[EXPLORE §n]`,
`[cf-105 R1-n]`, `[cf-105-V1-n]`.

## TL;DR (5 lines)

1. **Stock-load verdict: GO.** `Qwen/Qwen3.8-27B-FP8` loads on the pinned
   `vllm/vllm-openai-rocm:v0.33.0-rocm100` image on gfx1201 via the in-tree
   `Qwen3_5ForConditionalGeneration` + block-FP8 W8A8 path; the weight GEMM runs
   `TritonFp8BlockScaledMMKernel` (no AITER, no tuned R9700 config JSONs in the
   tree) — measured R9700 32B-block-FP8 eager numbers exist (25.8 tok/s c=1,
   2×R9700, Sep 2026 [28]); `--enforce-eager` stays (graph-capture NaN bug
   [28]). Load risk low; performance "young" [21][28].
2. **KV-q4 exists in v0.33.0 — as real `--kv-cache-dtype` values**, not as a
   TurboQuant/Octave-only fantasy: `int4_per_token_head`, `turboquant_4bit_nc`
   (plus k8v4/k3v4/3bit, `ultraquant_4bit`, `octave_*` = RDNA3-only, dead on
   R9700 [7][8]). ~16.4–16.5 KiB/token each on this model (vs 32 KiB fp8).
   **q8 = today's `fp8` (= fp8_e4m3 on ROCm); `fp8_e5m2` is equally valid**
   (same backends [2][5][6]).
3. **The KV-q4 × MTP interaction is the shape-changer**: the in-tree Octave RFC
   data proves **TurboQuant KV + MTP = garbage on RDNA (GSM8K ~1%)** [27];
   `int4_per_token_head` (served by TRITON_ATTN) is the only 4-bit option with
   no known-broken MTP evidence — it is the MTP-safe q4 default.
4. **"1m heads" = the 1 MTP head (Reading B) is the shippable reading**: in
   v0.33.0 both `qwen3_5_mtp` and `qwen3_next_mtp` are deprecated aliases of
   `method: "mtp"` [3]; the draft loads `mtp.safetensors` from the same FP8
   checkpoint [16]; no arch-level blocker on ROCm [cf-105-V1-143], but the
   official line still says "MTP on AMD under development" [34] and MTP costs
   ~+1 GDN state block/seq [4] — the FP8+vision envelope (below) decides
   enable-now vs head-dormant.
5. **Envelope correction to EXPLORE §6**: the "0.3–0.5 GiB residual at 0.95"
   pre-registration subtracted only weights+overhead; including the measured
   activation peak (0.54 GiB) and the live-calibrated GDN align pool (~0.5 GiB
   @ 4 seqs) the honest residual for attention KV is **≈ −0.2 to −1.2 GiB at
   0.95 (2–4 seqs) — infeasible**; feasibility needs utilization ≥ 0.97–0.98 and
   max-num-seqs 2–3 (or `--kv-cache-memory-bytes`, the exact v0.33 flag name).

---

## LEG 1 — FP8 + KV-cache serving surface (v0.33.0-rocm100, gfx1201, R9700)

### L1.1 — Does v0.33.0-rocm100 load `Qwen/Qwen3.8-27B-FP8` STOCK on gfx1201?

**Yes — the load path is fully in-tree; the compute path is the documented
"young" one.** Chain of evidence (all at tag v0.33.0 unless noted):

- Architecture registration: `Qwen3_5ForConditionalGeneration` +
  `Qwen3_5MTP`/`Qwen3_5MoeMTP` in the v0.33.0 model registry [15][cf-105-V1-141];
  the model class implements the GDN hybrid (48 `QwenGatedDeltaNetAttention`
  + 16 full-attention layers) exactly as the checkpoint's config describes
  [cf-105-V1-142]. The **live GGUF engine is already serving this exact model
  class on this exact image** (EXPLORE §1: pod up since 2026-11-07, engine log
  quoted) — the model layer is not the risk.
- FP8 weight quant: `RocmPlatform.supported_quantization` includes `"fp8"`
  [2]; `supports_fp8()` = `on_cdna() or on_rdna()` → True on gfx1201 [2];
  checkpoint `quantization_config` (W8A8, dynamic, block [128,128], e4m3) is
  the standard compressed-tensors block-FP8 form EXPLORE §3 fetched live.
- **Which linear kernel engages (the startup-log answer):** the block-FP8 GEMM
  dispatch for ROCm is the ordered candidate list
  `[AiterFp8BlockScaledMMKernel, TritonFp8BlockScaledMMKernel]` [18]. AITER
  block kernels require the AITER op stack, which is CDNA-prebuilt-only in
  this image (`VLLM_ROCM_USE_AITER` defaults to **False** in v0.33.0 [22] —
  matching the overlay's baked `=0`, so the overlay-retirement question
  EXPLORE OQ4 loses one env decision: the upstream default is already the
  overlay's value). The survivor on gfx1201 is
  **`TritonFp8BlockScaledMMKernel`** — supported for "CUDA-alike" = CUDA or
  ROCm [19] — running `torch.ops.vllm.w8a8_triton_block_scaled_mm_func`
  [19][20]. At startup it looks up per-shape tuned kernel-config JSONs named
  by device; **the v0.33.0 tree ships ZERO RDNA/Radeon config files** (245
  config JSONs: MI300X/MI325X/MI325_OAM, NVIDIA, Intel Arc only [21]) → every
  GEMM logs `"Using default W8A8 Block FP8 kernel config. Performance might
  be sub-optimal!"` [20]. On gfx1201 the Triton block-scaled GEMM lowers to
  native FP8 WMMA where the Triton ROCm backend can [cf-105 R1-21]; the open
  tracking issue #28649 (still open; last update 2026-10-20: "native FP8 WMMA
  is still not reliably selected for the majority of common linear layer
  shapes… often falls back to FP32 dequantization (or untuned Triton
  configs)") [28] is the standing performance caveat.
- **Known load failures: none on this card.** RDNA4 container failures
  (amdsmi init, arch detection, device_count=0 — issue #40081) were closed
  completed 2026-07-23, i.e. fixed well before v0.33.0 [31]; the live pod
  proves this node+image boots and serves. The gfx1250 (CDNA4) block-FP8 GEMM
  NaN workaround in-tree [20] does not apply to gfx1201.
- The one durable FP8-on-RDNA4 correctness caveat: the batched-FP8
  HIP-graph-capture NaN bug → `--enforce-eager` (already in the D4 recipe,
  keep it) [28][cf-105 R1-20].

**Verdict:** stock-loadable with high confidence; plan acceptance = 1-token
generation + the "default W8A8 Block FP8 kernel config" log line as the
documented performance marker; speed expectation anchor 25.8 tok/s c=1
(32B-block-FP8, 2×R9700 TP2, eager, Sep 2026 [28]).

### L1.2 — The complete `--kv-cache-dtype` table on this card in v0.33.0

The v0.33.0 CLI exposes exactly these choices (fetched versioned docs [23]):
`auto, bfloat16, float16, fp8, fp8_ds_mla, fp8_e4m3, fp8_e5m2, fp8_inc,
fp8_per_token_head, int4_per_token_head, int8_per_token_head, nvfp4,
nvfp4_4over6, nvfp4_ds_mla, octave_k3v3, octave_k3v3_compact, octave_k3v4,
turboquant_3bit_nc, turboquant_4bit_nc, turboquant_k3v4_nc, turboquant_k8v4,
ultraquant_4bit`. v0.33.0 added the pluggable-KV-dtype mechanism (#52670)
behind the turboquant/octave/ultraquant families [32][1].

Per-dtype facts for THIS model (16 full-attention layers, 4 KV heads,
head_dim 256; GDN/linear-attention layers keep their separate Mamba state
pool — see L1.5):

| dtype | bytes/token (derived) | KiB/token | tokens/GiB | serving backend on gfx1201 (v0.33.0) | status |
|---|---|---|---|---|---|
| `fp8` (=fp8_e4m3 on ROCm [2][23]) | 2·16·4·256·1 B = 32,768 | 32 | 32,768 | ROCM_ATTN (auto) or TRITON_ATTN (pin) [5][6] | **live-verified today** (EXPLORE §1: 384,176 tokens @ 12.23 GiB) |
| `fp8_e5m2` | 32,768 | 32 | 32,768 | same as fp8 (both in both backends' `supported_kv_cache_dtypes`) [5][6] | valid; no backend coupling vs e4m3 in v0.33.0 |
| `int8_per_token_head`, `fp8_per_token_head` | (256+256)·1 + 2·4 B scale = 520/head → 33,280 | 32.5 | ~32,263 | TRITON_ATTN [6] | valid; the Octave RFC's MTP-proven 8-bit option [27] |
| `int4_per_token_head` | (128+128)+8 = 264 B/head → **16,896** | **16.5** | 63,550 | TRITON_ATTN [6] (packed 2×int4/byte, RHT + asymmetric zp [4]) | **valid; MTP-safe by negative evidence (L1.4)** |
| `turboquant_4bit_nc` | slot 262 B/head → **16,768** | **16.4** | 64,035 | TURBOQUANT backend (only valid backend for the dtype) [9][10] | valid; upstream quality +2.71% PPL, 3.8× capacity [10]; **garbage with MTP on RDNA [27]** |
| `turboquant_k8v4` | slot 388 B/head → 24,832 | 24.25 | 43,240 | TURBOQUANT [9][10] | valid; +1.17% PPL [10] — the "q6-ish" middle ground |
| `ultraquant_4bit` | slot 272 B/head [12] → 17,408 | 17 | 61,680 | ULTRAQUANT backend; bf16-only model dtype (ours ✓) [11]; block size pinned 64 [11] | valid on selection; fast decode path is CDNA4 (FlyDSL scaled-MFMA [12]); RDNA4 = Triton unified fallback [11]; RFC-era note "gfx950 only" [27] |
| `octave_k3v4 / k3v3 / k3v3_compact` | 248/216/196 B/head [8] → 15.5/13.9/12.5 KiB | — | ~67,650 (k3v4) | **ROCM_OCTAVE: rejected at selection on gfx1201** — `supports_compute_capability` = RDNA3+CDNA3 only [7]; "validated on gfx1100 and gfx942… rejects any other family" [8] | **dead on this card** (7900-XTX-only feature; shipped in v0.33.0, #59774 [32]) |
| `turboquant_k3v4_nc / 3bit_nc` | 230/198 B/head [8][10] → 14.4/12.4 KiB | — | 72,944/84,733 | TURBOQUANT | valid but +10.63%/+20.59% PPL [10] — not quality-safe defaults |
| `nvfp4*` | — | — | — | `get_kv_quant_mode` → NVFP4 [4]; no RDNA backend lists them in the default priority [2] | not viable on this card in v0.33.0 |

Derivation cross-checks: (a) `int4_per_token_head` content per (head,token)
= `(hs_k//2 + hs_v//2)·sizeof(uint8) + 2·4 B scale` [6], storage dtype
uint8 [36] → 264 B ✓; the rocm_attn.py comment citing "qwen3_5 with … 1056"
hybrid block size [5] = 4 heads × 264 B exactly — an in-tree cross-check of
the arithmetic. (b) TurboQuant slot sizes computed from
`TurboQuantConfig` (key: `ceil(256·bits/8)` + 2 B fp16 norm; value:
`ceil(256·bits/8)` + 4 B scale+zero) [10] match the design doc's reference
line ("turboquant_3bit_nc uses 198 bytes and turboquant_k3v4_nc 230") [8].
(c) UltraQuant `slot_size(256)` = 128+8+128+8 = 272 B, documented [12].

### L1.3 — Mapping the owner's "q4 / q8"

- **q8 → `fp8` (i.e. fp8_e4m3).** Today's live value; `fp8` on ROCm resolves
  to e4m3fn storage [2] ("ROCm (AMD GPU) supports fp8 (=fp8_e4m3)" [1]).
  `fp8_e5m2` is a legitimate toggle sibling (same backends, wider exponent
  range, same 1 byte) — the guide's "fp8_e5m2 KV keeps ROCM_ATTN" [36] is
  true and in v0.33.0 trivially applies to `fp8`/e4m3 as well: both dtypes
  keep **both** ROCM_ATTN and TRITON_ATTN valid [5][6]. Best guess for the
  values key: `kvCacheDtype: fp8` default, `fp8_e5m2` available (open Q4).
- **q4 → `int4_per_token_head` (recommended default) or `turboquant_4bit_nc`
  (the higher-quality-ratio alternative, MTP-incompatible on RDNA).** Both
  are ~16.4–16.5 KiB/token on this shape — the 2× capacity the card's
  "KV-q4 default" buys is real and exists in the pinned image. There is no
  "q4" in the GGUF-quantization sense (Q4_K); the mapping above is the vLLM
  native one. If the owner's intent was specifically the TurboQuant scheme
  (4-bit K + 4-bit V + norm correction, upstream's headline 3.8×/+2.71% PPL
  [10]), that is `turboquant_4bit_nc` — viable **only if MTP stays off**
  (L1.4), otherwise `int4_per_token_head`.

### L1.4 — Attention-backend nuance (EXPLORE OQ7): what to pin, and why the KV dtype matters

Facts at tag v0.33.0:

1. **Auto selection on gfx1201 with `VLLM_ROCM_USE_AITER` off (the image
   default [22]):** default priority list =
   `[ROCM_ATTN, TRITON_ATTN, TURBOQUANT, ROCM_OCTAVE, ULTRAQUANT]` (AITER
   entries absent) [2]. For `kv_cache_dtype=fp8` + DECODER: only ROCM_ATTN
   and TRITON_ATTN pass validation → ROCM_ATTN wins by priority — **exactly
   the live log line** ("Found incompatible backend(s) [TURBOQUANT,
   ROCM_OCTAVE, ULTRAQUANT] with AttentionType.DECODER. Overriding with
   ROCM_ATTN out of potential backends: ['ROCM_ATTN', 'TRITON_ATTN']"
   [EXPLORE §1]).
2. **Why #54438 matters at head_dim 256:** ROCM_ATTN's native HIP
   paged-attention kernels exist only for head 64/128 [5] (the RDNA branch of
   `use_rocm_custom_paged_attention` requires `head_size == 128` and
   `kv_cache_dtype == "auto"` [2]); at head 256 ROCM_ATTN runs the same
   class of Triton paged kernel (`kernel_paged_attention_2d`) that
   `chunked_prefill_paged_decode` selects, while TRITON_ATTN runs
   `unified_attention` [5][6]. #54438 (open, 2026-08-30) measured on
   gfx1100: at head 256 the selector-rejected candidate (TRITON_ATTN) is
   **1.28× faster in decode at 500 tokens, 10.74× at 32 K**; even after the
   ROCM_ATTN-decode fix #45916 + TRITON #52684, "the selector's choice still
   costs 15.1 % of decode at 32 K and buys 4.4 % of prefill" [26]. The
   structure (RDNA branch, head-256 exclusion) is arch-common
   gfx11xx/gfx12xx [2].
3. **The fix, #60418 ("Add tuned configs for TRITON_ATTN kernel and swap
   places of TRITON_ATTN and ROCM_ATTN in priority list"), MERGED
   2026-11-03 — after the v0.33.0 tag (2026-11-01 → commit 2026-10-31
   [cf-105-V1-140]) and after the image push (2026-11-02) [25][33]. It is in
   nightly-rocm100 builds from 2026-11-04 on, NOT in our pinned image.**
   The guide's "PR #60418 is still open" statement is stale; its
   consequence (pin explicitly) remains valid for v0.33.0.
4. **What to pin, per KV shape, in v0.33.0:**
   - `fp8`/`fp8_e4m3`/`fp8_e5m2` (the q8 shapes): **`--attention-backend
     TRITON_ATTN`** — the documented decode-speed fix for exactly this model
     shape; TRITON_ATTN is valid for all three dtypes + head ≥ 32 [6]. (Omitting
     the pin is the conservative alternative: today's live engine runs
     ROCM_ATTN and serves; the pin trades 4.4% prefill for up to 10.74×
     decode-at-32K [26] — plan call, recorded here with both numbers.)
   - `int4_per_token_head` (the recommended q4): TRITON_ATTN is the only
     valid backend for the dtype [6] → auto selection already lands there; a
     pin is optional (consistent, no behavior change).
   - `turboquant_*` / `ultraquant_4bit`: the dedicated backends are the only
     valid ones for their dtypes; auto-selection picks them; pinning
     TRITON_ATTN would trigger the per-layer packed-KV fallback (log noise,
     no behavior change — the selection code tolerates exactly this mismatch
     for TQ/UQ runs [2]). Do not pin for these.
   - **The KV dtype does not "gate" ROCM_ATTN on fp8_e5m2 specifically** —
     the guide's phrasing maps onto v0.33.0 source as "both fp8 flavors keep
     both general backends; the 4-bit families keep only their own
     backends" [5][6][7][9][11].
5. **Vision coexistence is clean:** the ViT's 27 attention layers are served
   by the separate `get_vit_attn_backend` path (FLASH_ATTN-Triton on RDNA when
   `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE`, else Torch SDPA [2]) — encoder
   attention never enters the paged-KV backend selection, so **no KV dtype
   (including the 4-bit families) conflicts with vision** [17][2]. (The
   "encoder attention not supported" caveat in [7][8] is about
   encoder-DECODER/cross-attention models, not ViTs.) The TQ/UQ backends
   reject non-DECODER attn types [9][11] which is satisfied since the only
   DECODER layers are the 16 full-attention ones.
6. **Warmup hygiene:** #50603 (gfx1100, vLLM 0.25.1-era Triton paged
   fallback: first-call non-determinism + long-seq corruption) was
   root-caused to two mechanisms — the W4A16 split-K reduction (fixed by
   #54706, merged 2026-10-03 → **in v0.33.0** [30]) and a residual ROCm
   custom paged-attention-path divergence [29]. Our shape (FP8-block
   weights, head 256, RDNA4) does not run the native paged kernel at all
   [2][26], so the residual risk is low; the guide's "run a warmup request"
   is still good runbook hygiene for first serve.

### L1.5 — KV memory arithmetic for this model (the envelope re-derivation input)

Model-side constants (fetched live, EXPLORE §3 [37]; model config
[cf-105 R1-19]): 64 layers = 48 GDN + 16 full-attention
(`full_attention_interval 4`), 4 KV heads, head_dim 256,
`mtp_num_hidden_layers: 1`, vision tower 27 layers, native
`max_position_embeddings` 262144.

- **Attention KV bytes/token** = 2 × 16 layers × 4 heads × 256 dim ×
  dtype-bytes — table in L1.2. Live calibration: today's engine (fp8 KV,
  4 seqs, prefix-caching "align") reports "Available KV cache memory:
  12.23 GiB; GPU KV cache size: 384,176 tokens" [EXPLORE §1] → 12.23 GiB
  = 384,176 × 32 KiB of attention pages (11.72 GiB) **plus** a GDN align
  pool of ~518 MiB (0.51 GiB) — the exact split the arithmetic gives:
  13,131,862,508 B − 12,588,679,168 B = 543,183,340 B. (The
  architecture-derived 144 MiB/seq GDN state [cf-105 R1-19] is the upper
  bound per seq; 4 seqs × 2 align pages × 144 MiB would be 1.125 GiB, more
  than this pool can spare, so the live-aligned reservation is ~1 GDN
  page/seq at this block geometry, ~0.51 GiB total.) **Planning rule:
  use the on-target log lines for the exact split; effective fp8 density
  ≈ 34.2 KiB/attention-token (32 KiB raw + GDN share at 4 seqs); per-seq
  GDN cost ≈ 128–144 MiB (align, MTP-off).**
- **GDN (Mamba) state pool** is a separate KV group with fixed per-seq cost:
  ~128–144 MiB/seq live-calibrated (align, MTP-off; architecture upper bound
  144 MiB/seq fp32 [cf-105 R1-19]); with prefix-caching (`mamba_cache_mode=align`,
  live) vLLM reserves 2 + `num_speculative_blocks` + prefill-checkpoint
  pages/seq [4] — the live run shows ~1 effective page/seq at this block
  geometry (518 MiB @ 4 seqs, above); **MTP adds one speculative block/seq
  (≈ +0.12–0.14 GiB/seq)** — measured anchor from the community RDNA GDN
  work: MTP k=2 ≈ 3× the base state ≈ 0.47 GB/seq [cf-105 R1-23]. Levers:
  `--mamba-cache-dtype bfloat16` (halves state; `auto` = model-config dtype
  = fp32 here [23]); `--mamba-ssm-cache-dtype` (SSM-only variant [23]).
- **The FP8+vision re-derivation (correcting EXPLORE §6 [37]):**
  - Pool P(u) = u × 31.86 GiB visible [EXPLORE §1]: 0.95 → 30.27; 0.97 →
    30.90; 0.98 → 31.22; 0.99 → 31.54.
  - Weights W = 28.77 GiB (all of it: 24.70 B F8_E4M3 + 3.08 B BF16 params
    incl. vision + MTP head + embeddings; [37] usedStorage exact).
  - Non-torch overhead O: measured 1.15 GiB on the TEXT-ONLY GGUF run
    (17.5 − 16.35 [EXPLORE §1]); FP8 adds per-block scale tensors and the
    vision-inclusive non-torch set was never measured → **budget 1.15–1.6
    GiB** (estimate; the on-target "consumed memory" log line is the truth).
  - Peak activations A: 0.54 GiB measured at 4 seqs × 262144 (text-only
    [EXPLORE §1]); with vision requests A rises by the transient encoder
    activations (bounded by `--limit-mm-per-prompt` image count, guide
    precedent `.image=4` [36]); at 2–3 seqs budget 0.3–0.5.
   - GDN pool G (calibrated above, MTP-off): 2 seqs ≈ 0.26; 3 seqs ≈ 0.39;
     4 seqs ≈ 0.51 GiB. MTP k=1 adds ~+0.12–0.14 GiB/seq → 2 seqs ≈ 0.50–0.57;
     3 seqs ≈ 0.63–0.71.
   - **Residual K = P − W − O − A − G:**

| u | 2 seqs, no MTP | 3 seqs, no MTP | 2 seqs, MTP k=1 | 4 seqs (today's shape), no MTP |
|---|---|---|---|---|
| 0.95 | **−0.2 to −0.8 GiB** | −0.4 to −1.0 | −0.5 to −1.1 | −0.6 to −1.2 |
| 0.98 | **+0.1 to +0.75 GiB** | 0 to +0.5 | −0.2 to +0.4 | −0.25 to +0.3 |
| 0.99 | +0.45 to +1.05 | +0.3 to +0.8 | +0.15 to +0.75 | 0 to +0.6 |

  Attention-token capacity of K (int4 = 63,550 tok/GiB; fp8 = 32,768 tok/GiB,
  L1.2): u=0.98–0.99, 2 seqs, no MTP → **~6–67k int4 / ~3–34k fp8
  attention tokens** — i.e. the D4 envelope (384,176-token pool today)
  **collapses to roughly 1/6–1/64 of its token capacity** under FP8+vision.
  Confirmed and sharpened (EXPLORE §6's 0.3–0.5 GiB residual was the
  W+O-only number; A+G consume a further ~0.6–1.1 GiB of it, seq-count dependent).
  - Consequences for the plan (EXPLORE OQ3, plan-owned): the switch forces
    (a) `--gpu-memory-utilization` up to ~0.97–0.99 or an explicit
    `--kv-cache-memory-bytes` sized to K (the flag "ignores
    gpu_memory_utilization" when set [1][23] — note: EXPLORE §1's
    `--kv-cache-memory` is a paraphrase of this name), (b) `--max-num-seqs`
    4 → 2–3 (each seq costs GDN state + activation headroom), (c)
    `--max-model-len` 262144 stays admissible only single-session (preempted
    otherwise — the 1.47× concurrency of today falls to ~0.02–0.26×), or the
    plan drops to a 32–64k-class ceiling for the multi-session target,
    (d) the sleep-mode wake 2×-peak caveat [cf-105-V5-146] gets worse the
    fuller the VRAM is — utilization ~0.98+ with `--enable-sleep-mode`
    is the sharpest edge,
    (e) `--watermark 0.05` (KV-preemption headroom [cf-105-V-followup])
    eats into an already-tiny pool — plan decides whether to keep it.
  - **The KV-q4 default is worth it precisely because K is this small:**
    int4/fp8 KV ≈ 2× the session-token capacity of the residual (~3–34k →
    ~6–67k @ u=0.98–0.99/2-seq); q4-default + q8-toggle is the owner's shape, and
    both fit the same values-key mechanism (anchor splice, EXPLORE §8.2
    [37]).

### L1.6 — What the startup log will show (plan's runbook markers)

- `quantization=fp8, dtype=bfloat16, load_format=auto` (no GGUF lines;
  `load_format=gguf`/`quantization=gguf` disappear).
- `Using fp8 data type to store kv cache…` (quantized-KV info line [1]).
- Per GEMM shape: `Using default W8A8 Block FP8 kernel config. Performance
  might be sub-optimal!` [20] (assert this line appears — it is the
  "untuned RDNA4" marker; a tuned-config `Using configuration from …` line
  would mean the R9700 JSONs were added out-of-band).
- Attention: `Using TRITON_ATTN backend (selected via --attention-backend)`
  when pinned [2], else the `Found incompatible backend(s) … Overriding
  with …` line as live today.
- 4-bit dtypes: `Using turboquant_4bit_nc / int4_per_token_head data type
  to store kv cache…` [1] + (TQ/UQ only) per-layer backend-override notices
  [2].
- Vision: the text-only "All limits of multimodal modalities … set to 0"
  line goes away; mm limits print with `--limit-mm-per-prompt` values [23].
- MTP (if enabled): `method 'qwen3_5_mtp' is deprecated and replaced with
  mtp` warning [3] + `spec_decode_*` metric family registration [cf-105
  R5-122].

---

## LEG 2 — "1m heads"

### L2.1 — The exact speculative-config for `Qwen3_5ForConditionalGeneration` in v0.33.0

- `MTPModelTypes` at v0.33.0 lists `qwen3_next_mtp`, `qwen3_5_mtp`,
  `qwen4_exp_mtp`, … and the generic `mtp` [3]. **Any explicit family name is
  deprecated and normalized:** `if self.method in get_args(MTPModelTypes)
  and self.method != "mtp": logger.warning("method %s is deprecated and
  replaced with mtp"); self.method = "mtp"` [3]. So **both of the guide's
  candidates work** (`qwen3_5_mtp` pearsonkyle-style, `qwen3_next_mtp`
  7900-XTX-RFC-style); the clean v0.33.0 spelling is
  `--speculative-config '{"method": "mtp", "num_speculative_tokens": 1}'`.
- The draft model is **the target checkpoint itself** (method `mtp` with no
  `model` → `self.model = target model` [3]); `hf_config_override` rewrites
  `model_type qwen3_5 → qwen3_5_mtp`, `architectures → ["Qwen3_5MTP"]`,
  `n_predict = mtp_num_hidden_layers` (= 1 for this checkpoint) [3]; the
  `Qwen3_5MTP` loader remaps `mtp.*` tensors → `model.*` and loads them from
  the checkpoint's `mtp.safetensors` (0.44 GiB, inside the 28.77 GiB [37])
  [16]. No second file, no drafter download.
- `n_predict = 1` → `num_speculative_tokens` k=1 is the natural width; k>1
  is accepted (divisibility by 1) but logs "will run multiple times of
  forward on same MTP layer, which may result in lower acceptance rate" [3]
  — and each extra k widens the verification batch (more draft GDN state,
  more activation, L1.5). The Octave RFC ran k=3 [8][27]; pearsonkyle's
  headline number was k=2 [35]; the guide's W7900 manifest uses k=2 [36].
  **Best guess for this card: k=1** (tightest envelope cost, still
  speculative speed; re-tune on target).
- The draft inherits the target's attention backend and KV dtype
  (`_DRAFT_VLLM_CONFIG_OVERRIDES`: `attention_backend`, `kv_cache_dtype`
  [3]) — i.e. the L1.4 pin travels with MTP automatically.
- GDN interaction is in-tree: the GDN layer exposes a fused MTP decode
  (Triton port, ROCm-capable; `supports_fused_mtp_decode()` True on ROCm)
  [cf-105-V1-143]; the Mamba state pool grows by `num_speculative_blocks`
  [4].

### L2.2 — Does MTP work on gfx1201? Reconciling cf-105 R1's "no MTP on AMD"

The two lines:

- **cf-105 R1 (2026-11-04): "vLLM MTP is 'under development' on AMD" [cf-105
  R1-9]** — sourced from the Qwen3.5 recipe docs' standing note "MTP-1
  speculative decoding for AMD GPUs is under development" [cf-105 R1-9].
  **That note is still on the recipe page today** [34] — so the official
  *validation* status of MTP-on-AMD has not moved since cf-105.
- **The guide's gfx1100 proof [36]: "MTP works on gfx1100 in upstream vLLM …
  acceptance 67.6–68.2%"** — traced to the Octave-KV RFC #59773 (4× RX 7900
  XTX, Qwen3.8-27B GPTQ W4A16, TP4, MTP k=3, acceptance 67.6–68.2% with int8
  per-token-head and octave_k3v3 KV [27]) and now embodied in-tree as
  `docs/design/rocm_octave.md`: "All measurements on 4× RX 7900 XTX
  (gfx1100), Qwen3.8-27B W4A16, tensor parallel 4, **MTP k=3**" [8]. The
  RFC also records **TurboQuant + MTP → garbage (GSM8K ~1%)** on that
  hardware [27] (the L1.3 q4-constraint origin).

**Reconciliation: both are true at different layers.** "No MTP on AMD" was
R1's compression of "no official AMD MTP validation + recipe says under
development." The capability evidence as of v0.33.0: (a) in-tree
`Qwen3_5MTP` + config rewrite [3][15][16]; (b) GDN fused-MTP-decode ROCm
Triton port [cf-105-V1-143]; (c) measured MTP k=3 on RDNA3 (gfx1100) in the
upstream dev loop [8][27]; (d) measured 27B-FP8 + MTP-3 on 2×R9700 (gfx1201)
in a community fork of v0.28 (55 tok/s c=1, 315 agg @c16 [cf-105 R2-40]);
(e) roadmap commitment "close … speculative decoding … gaps on ROCm,
prioritizing Qwen3.x" (Q4-2026, #61024) [cf-105 R2-42]. **What is NOT in
evidence: any public stock-vLLM MTP measurement on gfx1201.** So for the
plan: MTP k=1 on R9700 stock v0.33.0 = **works-by-construction,
unverified-by-measurement** → an on-target benchmark item (acceptance-rate
smoke: `vllm:spec_decode_num_drafts/_num_accepted_tokens` [cf-105 R5-122]),
not a blocker. cf-105 R1's counter-line is superseded in substance (the
recipe wording survives as *official-validation* status, not capability).

**The pearsonkyle 1.71×/71.2% figure the guide cites is NOT an AMD
number**: the checkpoint card says "The Quick start command is tuned for a
24 GB card (RTX 3090): 106,496 tokens of context at ~75 tok/s (45 without
MTP)" and "`2` was the optimum on Blackwell (128 tok/s, **1.71×, 71.2%
acceptance**). Re-tune per card" [35] — measured on NVIDIA, vLLM 0.27.1.
Use the gfx1100 67.6–68.2% (k=3 [27][8]) as the RDNA anchor instead.

### L2.3 — MTP's cost to the envelope

k=1 MTP on this model costs: (a) +1 GDN state block/seq (≈ +0.125–0.15
GiB/seq; 3-page vs 2-page align, [4] + L1.5 calibration); (b) draft
activations per step (the MTP module ≈ 0.4B params [37] running over the
verification batch — the `num_speculative_tokens > 1` warning path is
skipped at k=1 [3]); (c) the MTP head weights themselves are already inside
W (mtp.safetensors, 0.44 GiB of the 28.77 [37]) → **zero marginal weight
cost**: with speculative decoding OFF the "1 MTP head" is still *kept* —
loaded, resident, usable later by flipping one flag. This is the
dormant-head option (open Q1): "keep 1m heads" is satisfied at the
weight/definition level either way; the plan decides enable-now (−0.3 to
−0.5 GiB of the residual, L1.5 table) vs enable-later (zero cost).

### L2.4 — The 1M-context reading: mechanism exists, physics says no

- **Mechanism (exists in v0.33.0):** `get_rope()` handles
  `scaling_type == "yarn"` **including the mrope case** — when
  `rope_parameters` carries `mrope_section` it builds the mrope variant with
  `scaling_factor` (YaRN interpolation + mrope sections [24]); injectable
  via `--hf-overrides` (CLI present [23]) into the checkpoint's
  `text_config.rope_scaling {rope_type: yarn, factor: 4,
  original_max_position_embeddings: 262144, mrope_section: [11,11,10]}`.
  So `--max-model-len 1010000`-class serving is mechanically expressible (the
  llama.cpp `ctx-1m` rung's `-c 1010000 --rope-scaling yarn --rope-scale 4
  --yarn-orig-ctx 262144` [EXPLORE §5, repo] is the lab's proven 1M recipe
  on the same model).
- **Physics (decisive, confirms EXPLORE §5 [37]):** one 1M session's
  attention KV = 1,010,000 × bytes/token: fp8 → 30.8 GiB; int4/TQ4 →
  15.8–15.9 GiB; plus ~0.26–0.29 GiB GDN state (1 seq, align, no MTP);
  plus W+O+A ≈ 30.2–30.9 GiB. Total ≈ 46–47 GiB (q4) to ≈ 61–62 GiB
  (q8) vs 31.86 GiB visible — **>1.5× the
  whole card even at q4, with vision resident**. No utilization choice, no
  `--kv-cache-memory-bytes` value, no dtype makes it fit; CPU KV offloading
  (`--kv-offloading-size`) would move it to the 125 GiB node RAM at
  bandwidth cost the lab has not validated. EXPLORE §5's infeasibility is
  **confirmed and made exact**.
- **Verdict for the card:** if "1m heads" meant 1M-context parity, the
  answer is "nothing to keep on the vLLM side — the llama.cpp
  `qwen3.8-27b-q8-1m` rung already owns 1M [EXPLORE §5]" (owner ruling,
  open Q5). The vLLM rung keeps native 262144.

---

## LEG 3 — vLLM v0.33 deltas affecting this card since cf-105 pinned it

cf-105 pinned `vllm/vllm-openai-rocm:v0.33.0-rocm100` (image push
2026-11-02; research 2026-11-04). Deltas relevant to card #131:

1. **The pinned image IS the newest stable.** `latest-rocm100` still
   resolves to digest `sha256:4fcd39b758b660c4e9c345c021e2ea8f0ccdb31e3c32507d676cc3005ae83fba`
   (18,038,402,058 B = 18.04 GB decimal; pushed 2026-11-02T02:45Z) as of
   2026-11-07 [33] — ledger re-verified; no v0.34.x-rocm100 stable exists;
   nightly-rocm100 rolls daily (2026-11-07 build digest
   `sha256:3925835468b4…` [33]). **No image bump is required for the FP8
   switch** (EXPLORE OQ4's retire-overlay plan stays valid: same base).
2. **#60418 merged 2026-11-03** (TRITON_ATTN priority swap + tuned RDNA
   TRITON_ATTN configs) [25] — post-image; first in nightlies 2026-11-04+.
   Implication: the L1.4 explicit `--attention-backend TRITON_ATTN` pin is
   the v0.33.0 answer and becomes optional (but harmless) after any future
   image bump that includes #60418 — the plan should note the pin is
   version-conditional.
3. **`--kv-cache-memory-bytes`** is in v0.33.0 (CacheConfig field
   `kv_cache_memory_bytes`; "when not-None ignores gpu_memory_utilization";
   human-readable values like `2Gi` [1][23]) — the explicit-pool lever
   EXPLORE §1 saw suggested in the live log (EXPLORE's `--kv-cache-memory`
   is a paraphrase; use the exact name in serveArgs).
4. **FP8-on-ROCm in v0.33.0:** per-tensor FP8 W8A8 kernel explicitly
   "restored RDNA4 (gfx12x)" after a refactor dropped it
   (`ROCmFP8ScaledMMLinearKernel.is_supported` [18]); block-128 FP8 =
   Triton path (L1.1) with no RDNA tuned configs [21]; AITER master env
   default moved to **False** [22] (the overlay's `VLLM_ROCM_USE_AITER=0`
   is now the upstream default — one less env decision on overlay
   retirement); `VLLM_ROCM_FP8_PADDING` default True [22].
5. **RDNA4-specific:** #40081's container failure class closed 2026-07-23
   (fixes inside the pinned image) [31]; ROCm_OCTAVE shipped in v0.33.0
   (#59774, "4.6× the KV tokens of fp16 on RX 7900 XTX") but is
   gfx1100/gfx942-only [7][8][32]; gfx1250 (CDNA4) enablement is the
   other RDNA-adjacent v0.33 item (not our arch) [32].
6. **MTP/spec-decode in v0.33.0:** the family-method deprecation → `mtp`
   normalization [3]; "lookahead block hashes for EAGLE/MTP prefix
   caching" (#61589) and "EAGLE/MTP partial tails in align mode" (#61019)
   both landed — MTP + GDN prefix-caching is a first-class v0.33 feature
   [32]; `draft_lm_head_quantization` exists but is "Model Runner V2 only"
   (not needed: the MTP head shares the bf16 lm_head) [3].
7. **KV-quant surface:** pluggable KV cache dtypes (#52670) [32] + the
   full turboquant/octave/ultraquant/int4-pth table (L1.2) are all in the
   pinned image — the q4 default needs **no image change at all**.

---

## Contradictions and how to weigh them (STORM conflict map)

1. **Guide "PR #60418 is still open" [36] vs merged 2026-11-03 [25].**
   The guide predates the merge (its research is W7900-era, ~Oct 2026).
   Weigh: the merge is the source-of-record; but the merge is *after* our
   pinned image, so the operational conclusion (pin TRITON_ATTN explicitly
   on v0.33.0 for head-256 fp8-KV decode speed) stands [25][26][33].
2. **"No MTP on AMD" [cf-105 R1-9] vs "MTP works on gfx1100, 67.6–68.2%
   acceptance" [36][27][8].** Weigh: the former is the official-validation
   status (the recipe line persists [34]); the latter is capability
   evidence inside the upstream dev loop (in-tree design doc [8] + RFC
   [27]). On gfx1201 specifically: capability evidence = fork measurements
   [cf-105 R2-40] + in-tree code paths [3][cf-105-V1-143]; measurement
   evidence = none public. Plan against "works-by-construction, verify on
   target."
3. **pearsonkyle "1.71× decode at 71.2% acceptance" [36] vs "MTP number
   from the author's own hardware, not confirmed for W7900" (guide caveat
   [36]).** Weigh: the card [35] resolves it — the number is NVIDIA
   (RTX 3090-class, k=2, vLLM 0.27.1). Do not carry it as an RDNA
   expectation; carry 67.6–68.2% @ k=3 gfx1100 [27] instead.
4. **Guide "fp8_e5m2 KV keeps ROCM_ATTN" (attributed to #60418 notes [36])
   vs v0.33.0 source.** Weigh: the source is precise — both `fp8`/e4m3 and
   `fp8_e5m2` are in ROCM_ATTN's and TRITON_ATTN's
   `supported_kv_cache_dtypes` [5][6]; there is no e4m3-vs-e5m2 backend
   coupling in v0.33.0. The guide sentence is true but non-distinguishing;
   the real dtype-driven backend coupling is the 4-bit families (each
   served by its own backend only) [7][9][11].
5. **EXPLORE §6 "residual ≈ 0.3–0.5 GiB for KV + activations + GDN states
   at 0.95" [37] vs L1.5 re-derivation (≈ −0.2 to −1.2 GiB, 2–4 seqs).** Weigh:
   EXPLORE's number subtracted W+O only (30.27 − 28.77 − 1.15 = 0.35) and
   left A (0.54 measured) and G (~0.5 calibrated) inside the residual —
   they cannot all fit in 0.35. The corrected band (L1.5 table) is the
   planning number; the on-target log lines will print the exact split.
6. **TurboQuant "3.8×, +2.71% PPL" (upstream's own quality line [10]) vs
   "TQ + MTP → GSM8K ~1%" on RDNA [27].** Not a conflict: quality-without-MTP
   vs correctness-with-MTP. Both hold; the MTP interaction is the plan-
   relevant one for a card that wants to keep the MTP head usable.
7. **Release notes "ROCM_OCTAVE … 4.6× the KV tokens of fp16 on RX 7900
   XTX" [32] vs the R9700.** Architectural exclusion: Octave is
   RDNA3/CDNA3-gated at selection [7], "validated on gfx1100 and gfx942"
   [8]. The release line is gfx1100-scoped by its own wording; no R9700
   claim is implied.

## Implications for the plan

- **The KV toggle is a values-key string mapping to one of L1.2's dtype
  values** — no engine surface beyond serveArgs (the anchor-splice pattern,
  EXPLORE §8.2 [37]). Recommended shape: `kvCacheDtype` default
  `int4_per_token_head` (q4, MTP-safe, TRITON_ATTN-served) with documented
  values `fp8` (q8, live-verified) / `fp8_e5m2` / `turboquant_4bit_nc`
  (q4-alt, no-MTP). If the plan enables MTP, `turboquant_*` is off the
  table for the default (L1.3/L1.4, [27]); if MTP stays dormant the
  TQ-4bit alternative is open (better PPL number [10]).
- **Add `--attention-backend TRITON_ATTN` for the fp8 shapes** (L1.4; the
  pin is v0.33.0-conditional — record it as such, #60418 [25][26]). For the
  4-bit shapes omit the pin (auto-selection is the only consistent answer
  [2]).
- **Drop `--language-model-only`; add `--limit-mm-per-prompt`** (guide
  precedent image=4 [36]; v0.33.0 configurable format [23]); optionally
  `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE` env for the RDNA ViT Triton path
  (else Torch SDPA [2]) — plan call.
- **MTP (if the owner's "1m heads" = enable it):**
  `--speculative-config '{"method":"mtp","num_speculative_tokens":1}'`
  [3] — k=1 (L2.1); budget the GDN/activation cost from L2.3; acceptance
  smoke via `spec_decode_*` metrics [cf-105 R5-122]; **or** dormant-head
  default (zero cost, L2.3) with the flag as a values-key opt-in. The
  envelope table (L1.5) shows why enable-now is expensive on this card.
- **Envelope re-derivation (EXPLORE OQ3) is forced, not optional:**
  utilization → 0.97–0.99 (or `--kv-cache-memory-bytes` [1][23]);
  max-num-seqs 4 → 2–3; keep `--max-model-len 262144` only for
  single-session use (concurrency falls to ~0.02–0.26× vs today's 1.47×);
  re-check the `--watermark 0.05` + sleep-mode 2×-peak interaction
  [cf-105-V5-146] at the new fill level; `--mamba-cache-dtype bfloat16` is
  the GDN-state halving lever if the pool is still starved [23]. The
  catalog rows' `limit.context` (262144) survives only if the plan keeps
  262144 as the per-session ceiling — the four-class priority wiring
  (EXPLORE §4 [37]) is untouched by all of this.
- **Overlay retirement (EXPLORE OQ4) simplifies:** `VLLM_ROCM_USE_AITER=0`
  = upstream v0.33.0 default [22]; the carry patch is GGUF-plugin-only
  [EXPLORE §2]; the only envs to carry into the pod are
  `PYTORCH_ALLOC_CONF=expandable_segments:True` + the cache dirs (plan
  decision). Digest pin `sha256:4fcd39b7…83fba` re-verified [33].
- **1M context (Reading A): do nothing on the vLLM side** (L2.4); the
  llama.cpp `qwen3.8-27b-q8-1m` rung stays the 1M home; record the YaRN×4
  mechanism exists (L2.4 [24]) so the owner's ruling has the full picture.
- **Runbook/acceptance markers to register** (L1.6): the "default W8A8
  Block FP8 kernel config" log line, the TRITON_ATTN selection line, the
  quantized-KV info line, the MTP deprecation warning (if k>0), and the
  exact "Available KV cache memory / GPU KV cache size / Maximum
  concurrency" triple replacing today's 12.23 GiB / 384,176 / 1.47×.

## Open questions (no-questions-rule log — for the coordinator's batched owner round)

- **Q1 — "1m heads" = enable MTP now, or keep the head dormant?** Best
  guess: **dormant now** (weights stay resident at zero marginal cost,
  L2.3; the L1.5 envelope cannot absorb +1 GDN block/seq at the required
  utilization without dropping to 1–2 sessions; re-enable after the
  on-target acceptance smoke + owner benchmark ruling). Impact: serveArgs
  (+`--speculative-config` flag vs none), envelope (−0.3 to −0.5 GiB),
  runbook (acceptance-rate step).
- **Q2 — q4 default: `int4_per_token_head` vs `turboquant_4bit_nc`?** Best
  guess: `int4_per_token_head` (MTP-safe by negative evidence; same
  TRITON_ATTN backend as the q8 shape; upstream TQ+MTP is proven-broken on
  RDNA [27]). Impact: the values-key default string only.
- **Q3 — Confirm the guide's R9700 MXFP4-fork section stays out of scope**
  (EXPLORE OQ8; the fork self-describes "early dev, experimental, not
  production hardened" [36]). Best guess: yes — requirement #1 mandates the
  official stock path. Impact: none if confirmed (already the reading).
- **Q4 — q8 value: keep `fp8` (=fp8_e4m3, live-verified) or move the
  default to `fp8_e5m2`?** Best guess: keep `fp8` (today's value, [5][6];
  e5m2 available as a documented toggle). Impact: cosmetic (same 32 KiB/
  token, same backends).
- **Q5 — If "1m heads" was actually 1M-context parity:** the card-level
  answer is "infeasible on this card under FP8+vision (L2.4); the
  llama.cpp q8-1m rung already provides it — nothing to keep on the vLLM
  side." Best guess: owner confirms Reading B (MTP head), per EXPLORE §5's
  adopted interpretation [37]. Impact: scope-defining; a "yes, we want 1M
  on vLLM too" answer reopens this card's physics (CPU KV offload territory,
  out of today's scope).

## Sources

All web sources accessed 2026-11-07 (tag-pinned files fetched via raw
GitHub at `v0.33.0`; APIs live). `[repo …]` = EXPLORE.md / cf-105
RESEARCH.md / DECISIONS.md / live-cluster facts (cited inline).

1. vLLM v0.33.0 `vllm/config/cache.py` — `CacheDType` literal (all 24 values incl. turboquant_/octave_/ultraquant_/int4_per_token_head/nvfp4*); `kv_cache_memory_bytes` docstring ("when not-None ignores gpu_memory_utilization"); `cache_dtype` docstring ("ROCm (AMD GPU) supports fp8 (=fp8_e4m3)"); `kv_cache_dtype_skip_layers`; `mamba_cache_dtype`/`mamba_ssm_cache_dtype`; `register_kv_cache_dtype` pluggable mechanism — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/config/cache.py
2. vLLM v0.33.0 `vllm/platforms/rocm.py` — ROCm default attention priority `[ROCM_ATTN, (AITER…), TRITON_ATTN, TURBOQUANT, ROCM_OCTAVE, ULTRAQUANT]`; `use_rocm_custom_paged_attention` RDNA gate (`head_size == 128`, `kv_cache_dtype == "auto"`, block 16, gqa 3–16, ≤128k); the exact "Found incompatible backend(s) … Overriding with …" log line; `get_supported_vit_attn_backends` + RDNA ViT path (Flash-Attention-Triton behind `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE`, else Torch SDPA); `supports_fp8 = on_cdna() or on_rdna()`; `fp8_dtype() = e4m3fn` (non-fnuz); `_uses_turboquant/_shares_layout_with_*` packed-KV per-layer fallback tolerance; R9700 in `_ROCM_DEVICE_ID_NAME_MAP` (0x7551) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/platforms/rocm.py
3. vLLM v0.33.0 `vllm/config/speculative.py` — `MTPModelTypes` (qwen3_next_mtp, qwen3_5_mtp, …, "mtp"); deprecation normalization (`method … deprecated and replaced with mtp`); `qwen3_5 → model_type qwen3_5_mtp, architectures ["Qwen3_5MTP"], n_predict = mtp_num_hidden_layers`; method `mtp` + no model → draft = target checkpoint; k>n_predict divisibility + k>1 "same MTP layer … lower acceptance" warning; `_DRAFT_VLLM_CONFIG_OVERRIDES` (attention_backend, kv_cache_dtype inherit) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/config/speculative.py
4. vLLM v0.33.0 `vllm/v1/kv_cache_interface.py` — `KVQuantMode` (INT4_PER_TOKEN_HEAD "packed 2×int4/byte, RHT + asymmetric zp"; TURBOQUANT_* "Hadamard-rotated Lloyd-Max, packed K+V per slot"; ULTRAQUANT_4BIT "packed FP4 values + UE8M0 group scales"; OCTAVE_* "(ROCm)"); `MambaSpec.max_memory_usage_bytes` align = page×(2 + num_speculative_blocks + num_prefill_checkpoint_blocks); `needs_kv_cache_zeroing` (mamba/mixed-precision) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/kv_cache_interface.py
5. vLLM v0.33.0 `vllm/v1/attention/backends/rocm_attn.py` — `supported_kv_cache_dtypes = [auto, f16, bf16, fp8, fp8_e4m3, fp8_e5m2]`; `get_supported_head_sizes` incl. 256 with "native ROCm kernels only 64/128 … remaining served by the Triton fallback"; hybrid-model block-size note ("qwen3_5 with 784 and 1056"); DECODER/ENCODER/ENCODER_ONLY; layouts LHBNC/LBHNC; fp8 cache `.view(fp8_dtype)` in forward — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/attention/backends/rocm_attn.py
6. vLLM v0.33.0 `vllm/v1/attention/backends/triton_attn.py` — `supported_kv_cache_dtypes` incl. `int4_per_token_head, int8_per_token_head, fp8_per_token_head`; `supports_head_size ≥ 32`; `customize_spec` per-token-head content = `(hs_k//2 + hs_v//2)·sizeof + 2·4 B scales`; `unified_attention` kernel; `supports_mm_prefix = True`; ROCm fp8 quant-query gate (gfx11 off, gfx12 on) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/attention/backends/triton_attn.py
7. vLLM v0.33.0 `vllm/v1/attention/backends/rocm_octave_attn.py` — dtypes `octave_k3v4/k3v3/k3v3_compact`; `supports_compute_capability` = ROCm + (RDNA3 or CDNA3) → **rejected on gfx1201**; DECODER-only; head 256 + rope_dim 64 required; "Kernels are native … There is no fallback" (design doc) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/attention/backends/rocm_octave_attn.py
8. vLLM v0.33.0 `docs/design/rocm_octave.md` — slot bytes (k3v4 248 / k3v3 216 / compact 196; "turboquant_3bit_nc 198, turboquant_k3v4_nc 230"); "enabled only on RDNA3 and CDNA3, validated on gfx1100 and gfx942; rejects any other family at selection"; encoder attention / sliding window / sinks unsupported; **all measurements 4× RX 7900 XTX, Qwen3.8-27B W4A16, TP4, MTP k=3** — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/docs/design/rocm_octave.md
9. vLLM v0.33.0 `vllm/v1/attention/backends/turboquant_attn.py` — dtypes (k8v4, 4bit_nc, k3v4_nc, 3bit_nc); DECODER-only; LBNHC-only layout; slot = key_packed + value_packed (per-head); FlyDSL fast path gfx950-only + SoA/AoS Triton decode (portable); prefill via flash_attn_varlen when available else SDPA; module docstring's "value_fp16/612" example is stale vs `TurboQuantConfig` — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/attention/backends/turboquant_attn.py
10. vLLM v0.33.0 `vllm/model_executor/layers/quantization/turboquant/config.py` — preset table + quality: k8v4 "2.6×, +1.17% PPL", 4bit_nc "3.8×, +2.71%", k3v4_nc "~3.5×, +10.63%", 3bit_nc "4.9×, +20.59%"; slot-size formulas (key MSE ceil(D·b/8)+2 B norm; value ceil(D·b/8)+4 B scale); `get_boundary_skip_layers` → hybrid models skip NONE (all 16 full-attn layers quantized) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/layers/quantization/turboquant/config.py
11. vLLM v0.33.0 `vllm/v1/attention/backends/ultraquant_attn.py` — dtype `ultraquant_4bit`; bf16-only supported dtypes; `get_preferred_block_size = 64`; FlyDSL D=256 decode (CDNA4) + `ultraquant_unified_attention` Triton fallback; inherits TQ metadata/layout (LBNHC) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/attention/backends/ultraquant_attn.py
12. vLLM v0.33.0 `vllm/v1/attention/ops/ultraquant/format.py` — AoS slot layout; "D=256 → Gk=8 → 272 B/slot"; "Decode consumes Q as FP8 E4M3 so scaled F8F6F4 MFMA can run natively on CDNA4" — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/attention/ops/ultraquant/format.py
13. vLLM v0.33.0 `vllm/v1/attention/backends/registry.py` — `AttentionBackendEnum` names (TRITON_ATTN, ROCM_ATTN, TURBOQUANT, ROCM_OCTAVE, ULTRAQUANT, …) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/attention/backends/registry.py
14. vLLM v0.33.0 `vllm/v1/attention/selector.py` — `AttentionSelectorConfig` (per-layer kv_cache_dtype, attn_type, …); `get_attn_backend` (global `attention_config.backend` + per-kind override) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/v1/attention/selector.py
15. vLLM v0.33.0 `vllm/model_executor/models/registry.py` — `Qwen3_5ForConditionalGeneration` → `qwen3_5` (L617-620); `Qwen3_5MTP`/`Qwen3_5MoeMTP` → `qwen3_5_mtp` (L739-740) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/models/registry.py
16. vLLM v0.33.0 `vllm/model_executor/models/qwen3_5_mtp.py` — `Qwen3_5MultiTokenPredictor` (draft = target's `mtp.*` tensors remapped to `model.*`; `num_mtp_layers = mtp_num_hidden_layers`; `SupportsMultiModal` MTP) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/models/qwen3_5_mtp.py
17. vLLM v0.33.0 `vllm/model_executor/models/qwen3_vl.py` + `vllm/model_executor/layers/attention/mm_encoder_attention.py` — vision blocks use `get_vit_attn_backend` (non-paged path, independent of `--kv-cache-dtype`) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/models/qwen3_vl.py
18. vLLM v0.33.0 `vllm/model_executor/kernels/linear/__init__.py` — `_POSSIBLE_FP8_BLOCK_KERNELS[ROCM] = [AiterFp8BlockScaledMMKernel, TritonFp8BlockScaledMMKernel]`; `_POSSIBLE_FP8_KERNELS[ROCM]` incl. `ROCmFP8ScaledMMLinearKernel` ("Restore RDNA4 (gfx12x) dropped by the get_cdna_version()>2 refactor … requires CDNA3+ or RDNA4 (gfx12x)" in its `is_supported`) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/kernels/linear/__init__.py
19. vLLM v0.33.0 `vllm/model_executor/kernels/linear/scaled_mm/triton.py` — `TritonFp8BlockScaledMMKernel.is_supported`: "only CUDA-alike and XPU devices are supported" (ROCm = CUDA-alike [see 20]); apply → `torch.ops.vllm.w8a8_triton_block_scaled_mm_func` — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/kernels/linear/scaled_mm/triton.py
20. vLLM v0.33.0 `vllm/model_executor/layers/quantization/utils/fp8_utils.py` — `w8a8_triton_block_scaled_mm`; `get_w8a8_block_fp8_configs` per-device JSON lookup + "Using default W8A8 Block FP8 kernel config. Performance might be sub-optimal!" warning; gfx1250 fp32-upcast NaN workaround (not our arch); `VLLM_ROCM_FP8_PADDING` — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/model_executor/layers/quantization/utils/fp8_utils.py
21. vLLM v0.33.0 tuned-config tree `vllm/model_executor/layers/quantization/utils/configs/` — 245 JSONs; device names: MI300X/MI325X/MI325_OAM, NVIDIA ×9, Intel Arc B70; **zero Radeon/RDNA entries** — https://github.com/vllm-project/vllm/tree/v0.33.0/vllm/model_executor/layers/quantization/utils/configs
22. vLLM v0.33.0 `vllm/envs.py` — `VLLM_ROCM_USE_AITER` default **False** (L138/L1267-1268); `VLLM_ROCM_USE_AITER_LINEAR` default True (master-gated); `VLLM_ROCM_FP8_PADDING` default True — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/envs.py
23. vLLM docs — `vllm serve` CLI, **v0.33.0 versioned** — `--kv-cache-dtype` full choice list; `--kv-cache-memory-bytes` ("ignores gpu_memory_utilization"; human-readable values); `--attention-backend`; `--kv-cache-dtype-skip-layers`; `--mamba-cache-dtype`/`--mamba-ssm-cache-dtype`; `--hf-overrides`; `--limit-mm-per-prompt` (legacy count + configurable `{"image": {"count": …}}` formats); `--enforce-eager`; `--max-model-len` auto — https://docs.vllm.ai/en/v0.33.0/cli/serve/
24. vLLM v0.33.0 `vllm/model_executor/layers/rotary_embedding/` — `get_rope` yarn branch incl. **mrope_section variant** (`MRotaryEmbedding` + `scaling_factor`, `beta_fast/slow`, `mscale`, `truncate` extras) + `YaRNScalingRotaryEmbedding` — https://github.com/vllm-project/vllm/tree/v0.33.0/vllm/model_executor/layers/rotary_embedding
25. vllm-project/vllm **PR #60418** — "[ROCm] [RDNA] [Perf] Add tuned configs for TRITON_ATTN kernel and swap places of TRITON_ATTN and ROCM_ATTN in priority list" — **merged 2026-11-03T18:43Z** (created 2026-10-07; after the v0.33.0 tag 2026-11-01) — https://github.com/vllm-project/vllm/pull/60418
26. vllm-project/vllm **issue #54438** (open) — "[Performance]: gfx1100 ranks ROCM_ATTN above TRITON_ATTN for a custom kernel it does not use at head_size 256" — at head 256 both backends run Triton kernels; rejected candidate (TRITON_ATTN) faster in decode "1.28× at 500 tokens rising to 10.74× at 32 K"; post-#45916/#52684 the ranking "still costs 15.1% of decode at 32 K and buys 4.4% of prefill" — https://github.com/vllm-project/vllm/issues/54438
27. vllm-project/vllm **RFC #59773** (open, updated 2026-10-20) — "Octave KV, a native 3-bit KV cache for AMD GPUs" — 4× RX 7900 XTX, Qwen3.8-27B GPTQ W4A16, TP4, MTP k=3; "With MTP on (qwen3_next_mtp, k=3) [TurboQuant] every preset produced garbage, and GSM8K fell to around 1%. Without MTP it was correct."; MTP acceptance 67.6–68.2% (int8 pth vs octave_k3v3); "Both boxes now serve 512k-token contexts" — https://github.com/vllm-project/vllm/issues/59773
28. vllm-project/vllm **issue #28649** (open) — "upstream this gfx1201/RDNA4 FP8 patch" — 2026-09-05: 2×R9700 TP2, `--enforce-eager`, Qwen3-32B-FP8 block 128×128 with `VLLM_ROCM_USE_AITER=0` → `TritonFp8BlockScaledMMKernel`: 25.8/71.1/182.5 tok/s c=1/3/8; 2026-10-20: "native FP8 WMMA is still not reliably selected for the majority of common linear layer shapes… falls back to FP32 dequantization (or untuned Triton configs)" — https://github.com/vllm-project/vllm/issues/28649
29. vllm-project/vllm **issue #50603** (open) — gfx1100 Triton paged-fallback non-determinism/corruption (vLLM 0.25.1 era); 2026-08-30/31 status: two mechanisms — W4A16 split-K reduction (fix #54706) + residual custom paged-attention path; `--enforce-eager` ruled out as the separator — https://github.com/vllm-project/vllm/issues/50603
30. vllm-project/vllm **PR #54706** — "[ROCm][RDNA3] Fix W4A16 split-K accuracy and determinism" — merged 2026-10-03 (in v0.33.0) — https://github.com/vllm-project/vllm/pull/54706
31. vllm-project/vllm **issue #40081** — RDNA4 (gfx1201) container failures (amdsmi init, circular arch import, device_count 0) — **closed completed 2026-07-23** (fixes #41585/#41596 predate v0.33.0) — https://github.com/vllm-project/vllm/issues/40081
32. vLLM release notes **v0.33.0** (published under tag v0.33.0rc3, 2026-11-02) — AMD ROCm bullet: ROCm 10.0 default image (#58761); "the `ROCM_OCTAVE` 3-4 bit KV cache (4.6× the KV tokens of fp16 on RX 7900 XTX, #59774)"; gfx1250 enablement (#58800); "pluggable KV cache data types (#52670)"; MTP/prefix-caching items (#61589, #61019); AITER default off on RDNA bullets; `vllm/vllm` alias images — https://github.com/vllm-project/vllm/releases/tag/v0.33.0rc3
33. Docker Hub — `vllm/vllm-openai-rocm` tags (live 2026-11-07): `v0.33.0-rocm100` = digest `sha256:4fcd39b758b660c4e9c345c021e2ea8f0ccdb31e3c32507d676cc3005ae83fba`, pushed 2026-11-02T02:45:27Z, 18,038,402,058 B; `latest-rocm100` = same digest (no v0.34 stable as of 2026-11-07); `nightly-rocm100` 2026-11-07 build digest `sha256:3925835468b4…` — https://hub.docker.com/v2/repositories/vllm/vllm-openai-rocm/tags
34. vLLM Recipes — Qwen3.5 (current/stable, fetched 2026-11-07) — example `--speculative-config '{"method": "mtp", "num_speculative_tokens": 2}'`; standing note "**MTP-1 speculative decoding for AMD GPUs is under development**" — https://docs.vllm.ai/projects/recipes/en/stable/Qwen/Qwen3.5.html
35. Hugging Face — `pearsonkyle/Qwen3.8-27B-GPTQ-W4A16` model card (fetched 2026-11-07; lastModified 2026-09-03) — "MTP bundled · 1.71× decode"; quickstart "tuned for a 24 GB card (RTX 3090)… ~75 tok/s (45 without MTP)"; "`num_speculative_tokens: 3` on a 3090 … `2` was the optimum on Blackwell (128 tok/s, 1.71×, 71.2% acceptance). Re-tune per card"; vLLM 0.27.1; vision 3/3; tool-calling bf16-identical — https://huggingface.co/pearsonkyle/Qwen3.8-27B-GPTQ-W4A16
36. WeKan AI-Dev card #131 (`get_card_details`, live 2026-11-07) — owner requirements verbatim + backlinks + the full owner-attached deployment guide (W7900 gfx1100 manifest with `--attention-backend TRITON_ATTN`, `--kv-cache-dtype fp8_e4m3`, MTP `qwen3_5_mtp` k=2; R9700 = GGZ14 MXFP4 fork section "early dev, experimental"; caveats: #60418 open-at-writing, MTP method-name split, pearsonkyle 1.71× hardware disclaimer) — board `TNQJ2BrXenZovngTS`, card `unDxRqcrNTfahp656`
37. [repo] `EXPLORE.md` (cf-131 folder, 2026-11-07) — live pod/args/env/PVCs; live engine log (12.23 GiB / 384,176 tokens / 1.47×, 17.5 GiB consumed, 0.54 GiB activations, ROCM_ATTN override line, "Mamba cache mode is 'align'", `--kv-cache-memory` log suggestion); FP8 checkpoint live fetch (28.77 GiB, mtp.safetensors 0.44 GiB, full multimodal, native 262144, mtp_num_hidden_layers 1, head_dim 256, mrope_section [11,11,10], partial_rotary 0.25); switch-surface inventory; §6 pre-registered envelope; §5 the two "1m heads" readings; §8 gotchas (dual-edit law, anchor splice, test pins)
38. [repo] cf-105 `RESEARCH.md` (R1–R5, Post Research V1–V5, 2026-11-04) — R1[5] fp8-e4m3-on-ROCm KV doc; R1[9] recipe "MTP under development on AMD" line (the cf-105 counter-line); R1[19] model config + 144 MiB/seq GDN derivation; R1[20]/[21] #28649 + RDNA4 FP8 WMMA mechanics; R1[23] GDN MTP k=2 ≈ 3× state ≈ 0.47 GB/seq; R2[40] Capicua25x fork 27B-FP8 + MTP-3 on 2×R9700 (55 tok/s c=1, 315 agg @c16); R2[42] Q4-2026 ROCm spec-decoding roadmap; V1[140]-[143] v0.33.0 tag facts, registry/model/GDN-kernel ROCm paths (fused MTP decode = ROCm Triton port); V5[144]-[146] sleep-mode dev-gate + GDN sleep/wake test + ROCm wake 2×-peak caveat
39. [repo] cf-105-vllm-followup `RESEARCH.md` + `DECISIONS.md` (2026-11-07) — root-cause chain (GID-486 → `runAsUser: 0` live shape; #14764 fmm lead superseded on this node); `--watermark` valid-arg verification; the proven pod/device shape this card must not touch

## Reliability notes (self-review)

- **High confidence (source @ exact tag, mutually consistent):** the
  complete `--kv-cache-dtype` table + backend validity matrix (L1.2) [1][2][5][6][7][9][11][23];
  per-dtype bytes/token (derived from in-tree slot formulas [6][10][12] +
  cross-checked against the design doc's reference line [8] and the live
  engine's 384,176-token@12.23-GiB calibration [37]); MTP method
  normalization + same-checkpoint draft contract [3][15][16]; Octave
  RDNA3-only gate [7][8]; #60418 merge-after-image [25][33]; image ledger
  [33]; RDNA4 zero-tuned-config fact [21]; TritonFp8BlockScaledMMKernel as
  the R9700 block-FP8 path [18][19][28].
- **Medium confidence:** (a) the L1.5 envelope table — W is exact [37],
  O/A/G ranges are estimates anchored on the live GGUF-run log lines
  [37] (O 1.15–1.6, A 0.3–0.5, G 0.25–0.6 GiB); the on-target FP8 run's
  "consumed memory / Available KV cache memory / Mamba pages" log lines
  replace the estimates, and the sign of the 0.95 row (infeasible) is
  robust to ±0.5 GiB of O+A error. (b) "int4_per_token_head + MTP is
  safe on gfx1201" — it is safe by *negative evidence* (the only
  RDNA-documented TQ+MTP garbage result is TurboQuant [27]; int4-pth
  travels the MTP-proven 8-bit-class TRITON_ATTN path [6][27]); no public
  gfx1201 int4+MTP measurement exists. (c) `--attention-backend TRITON_ATTN`
  decode-speed delta on gfx1201 specifically — measured on gfx1100
  [26]; the kernel-structure argument is arch-common [2][5], the R9700
  number is inferred, not measured.
- **Weakest claim:** "TurboQuant + MTP garbage [27] generalizes from
  gfx1100 k=3 to gfx1201 k=1" — it may not (k=1 verification is a
  narrower multi-token path; TQ's host-copy concern was about the
  multi-token path generally). Weigh: it is the only 4-bit option with a
  *documented* MTP failure on RDNA in the pinned tree, so the plan's
  default avoids it; a plan that wants TQ-4bit with MTP on must budget an
  on-target GSM8K-class correctness smoke before shipping.
- **Perspective weighting:** the vLLM-in-tree evidence dominates (exact-tag
  source reads) — appropriate since the card is pinned to one image; the
  community RDNA evidence (#28649 measurements, fork MTP numbers, Octave
  RFC) carries the performance/acceptance expectations, and the owner
  guide [36] is treated as claims-to-verify (its three material errors
  found this round: #60418 open-status [25], pearsonkyle hardware
  [35], fp8_e5m2-keeps-ROCM_ATTN over-reading [5][6]) — all corrected
  above with sources.
- **Blind spot (nothing found):** no public *stock-vLLM* MTP-on-gfx1201
  measurement (the R9700 MTP data points are fork-based [38 R2-40]); no
  public RDNA4 int4-per-token-head KV measurement of any quality; no
  public FP8+vision+MTP combined run on any ROCm card; the exact GDN
  align-page reservation for the FP8+vision engine (the live log will
  print it — it calibrates L1.5's G column).

---

# R2 — MXFP4 fork scope (owner re-scope 2026-11-07)

Round-2 research commission for board card #131, 2026-11-07, by
`agent-research`. The owner rejected the R1 FP8-official plan and ruled:
*"you need to include the MXFP4 fork in the R9700 image. I've dropped the
official checkpoint mandate."* This section grounds the fork path (GGZ14
radiance-vllm-mxfp4 launcher over `stilldeadcode/vllm-radiance:0.9.3`,
vLLM 0.27.1) for a K8s/ArgoCD deployment in THIS repo. R1 above stays as
supporting context (its v0.33.0 dtype table, #60418 pin analysis and
MTP-on-AMD facts are a DIFFERENT engine generation and are re-grounded
here against the v0.27.1 tag; R1's envelope arithmetic and the live-pod /
priority-wiring facts carry over). All web evidence accessed **2026-11-07**
unless stamped; citation keys continue R1's numbering at [40]. The
owner-attached "Production Deployment Guide" (Part 2 = the R9700 fork
section) is embedded in the card description [46] and is treated as
claims-to-verify against the repo source, as in R1.

## TL;DR (5 lines)

1. **Pin = Codeberg main @ `df0af7cf6bacaf9c305102d758d70a408b2cc4dd`
   (2026-10-30)** — canonical host per the guide; the GitHub mirror
   `GGZ14/vllm-mxfp4` is ~2.5 weeks STALE (tip 2026-10-13, and it carries a
   GitHub-only MoE lane that is NOT on Codeberg main). The guide's 0.12.0
   pin has moved: `VERSION` = 0.13.0 (tag 2026-09-12) + 17 main commits
   since, incl. **the TP=1 default flipping to the long-context shape**
   (MAXSEQS 3 / MAXLEN 220000 / CHUNK 2560, 2026-09-18) — the guide's
   measured-throughput shape (8 / 65536 / 4096, the 137.7/416 numbers) is
   now explicit-override territory [42][48][49].
2. **Base image pullable and digest-pinned**: `stilldeadcode/vllm-radiance:0.9.3`
   = `sha256:45694209177a55a1ab3ba6702fe6e978b1b66a6e66ae3fc066f8d579f7bc4c25`
   (Docker Hub tag API **and** the fork's own `Dockerfile.ggz14.top`
   `BASE_DIGEST` ARG agree; registry manifest probe HTTP 200) [55][56][58].
   The Docker Hub page carries a live deprecation warning (owner moved to a
   standalone non-vLLM engine) — the image is frozen, not rotting: it still
   pulls, and it is exactly what the fork's measured stack targets
   (vLLM 0.27.1 / torch 2.11.0 / triton 3.6.0 / AITER 0.1.17 / ROCm 7.14)
   [51][57].
3. **The card's KV requirement changes shape**: under the fork the
   qualified KV dtypes are `fp8` (the default, hardcoded in the launcher),
   `bf16`, `auto` only [51]; the fork's R4D attention backend (the measured
   path) refuses any other KV dtype at startup [45]. `int4_per_token_head`
   EXISTS at the v0.27.1 CLI+TRITON_ATTN level [70][72] but is untested
   under the fork and would require dropping R4D — "q4 default" is not
   available as a qualified shape; q8 = `fp8` stands as the default [L3.1].
4. **The pod shape carries UNCHANGED** — the launcher's own container
   invocation is `--privileged --ipc=host --device /dev/kfd --device
   /dev/dri --security-opt seccomp=unconfined --cap-add SYS_PTRACE`
   [S L1008-1010], i.e. the cf-105 GID-486 proven shape; chip
   targeting is `ROCR_VISIBLE_DEVICES=0` (the node's 8060S would otherwise
   pull auto-detect to a broken TP=2) [50]. The baked-derivative image
   (`Dockerfile.ggz14.top` is the repo's own minutes-scale recipe) removes
   ALL start-time patching: entrypoint + raw `vllm serve` args, no
   runtime prelude, no network [55].
5. **Serving name is an env knob, not a guess**: the launcher transcribes
   `--served-model-name ${SERVED_NAMES:-Qwen3.8 Qwen3.6 Qwen3.8-MXFP4}`
   (v0.27.1 accepts a list) [S L1163][71] — the re-plan passes
   `--served-model-name qwen3.8-27b-vllm` verbatim in serveArgs (source-
   verified), keeping the four-class priority wiring byte-stable [EXPLORE §4].

## L1 — The fork's current state (2026-11-07)

### L1.1 — Repo version, commit pin, what moved since the guide's capture

- **Canonical source: `codeberg.org/ggz14/radiance-vllm-mxfp4`** (the guide's
  own words [46]). main tip = **`df0af7cf6bacaf9c305102d758d70a408b2cc4dd`**,
  "Merge pull request 'Add v032/: Radiance overlay for vLLM 0.32 (plugin +
  text hunks), tested on R9700 (gfx1201)' (#59)", 2026-10-30T14:26+01:00
  [40][41][42]. 312 commits, 2 branches, 4 tags, 2 open issues [40].
- **Tags** [41]: `v1.0` (2026-08-30, "MXFP4 decode stack at 22.66
  ms/step"), `v0.11.0` (2026-09-02), `v0.12.0` (2026-09-07, TP=3 dummy
  heads — the guide's pinned version), `v0.13.0` (2026-09-12, ParoQuant
  int5 W5A8 + int8 per-group activations). **Version drift**: the
  README's Status line still says "Repo version 0.12.0" [45] while the
  `VERSION` file and the v0.13.0 tag say 0.13.0 [41] — the README line is
  stale; the tag is the version of record. Post-v0.13.0 main commits
  (2026-09-12 → 10-30, all on Codeberg main [42]): MXFP6-PARO (09-17/18),
  lazy-GDN revert docs (09-17), drafthead int2-defer + **"serve: make TP=1
  the long-context shape (seqs 3, maxlen 220000, chunk 2560)" (09-18)**
  [48], FASTBOOT.md (09-21), opt-in KV-cache offload `KVCACHE=off|ram|disk`
  (09-26, off by default; the 6 "ram" behavioral patches were **baked into
  the image recipe** 09-29), DRY_RUN-must-not-remove-container fix
  (10-04/06), `RADIANCE_EMBED_HOST` (embed_tokens 2.37 GiB → pinned host
  memory, 10-06), lazy-GDN rx10 fix (10-09), v0.32 forward-port overlay
  `v032/` dir (10-18, contributor), drafthead startup-memory reduction
  (10-19), 5 merge commits (10-30). **None of these change the TP=1 MXFP4
  serve path's numerics** (embed-host defaults OFF; v032 is an unused
  tree; the KVCACHE tier defaults off with a byte-identical command
  [S L935-937]); the 137.7/416 numbers remain the current-main
  defaults' numbers for Shape A (L2.4).
- **GitHub mirror `GGZ14/vllm-mxfp4` is STALE**: main tip
  `d61624250144` (2026-10-13), pushed_at 2026-10-13 [43][44]. Tags are
  shared (identical SHAs for v0.11.0–v0.13.0 + v1.0 [41][44]), but the
  mirror carries a **GitHub-only "MoE lane" history (2026-10-01..13, PRs by
  jkuepker) absent from Codeberg main** — the two hosts evolved in parallel
  after ~09-17 (same-title commits with different SHAs, e.g. the DRY_RUN
  fix) [42][44]. **Build against Codeberg, never the mirror.**
- **Recommended pin: `df0af7cf6bacaf9c305102d758d70a408b2cc4dd`** (main
  tip, 2026-10-30). Alternative: tag `v0.13.0`
  (`5bd83165e0b68a5b8afaf981033153fd5eaac8a1`) — older, misses the TP=1
  long-context default + drafthead-memory + DRY_RUN fixes; the
  measured-throughput shape it targets still requires the same explicit
  overrides, so it buys nothing except a release tag. No release-cadence
  promise exists (the maintainer publishes the *image*
  `ggz14/vllm-radiance-mxfp4:$VERSION-$SHA` scheme per `build.sh` [79] —
  but that image is NOT published: Docker Hub `ggz14/vllm-radiance-mxfp4`
  = "object not found" [56]; the only public images are stilldeadcode's
  base and the two fallbacks below).
- **libr4d pin**: `R4D_PIN=b9e42ab` (codeberg.org/StillDeadcode/libr4d),
  build key `b9e42ab-rx9` at TP=1 (rx9 = rx6 + the narrow-state GDN decode
  kernels the fp16 ssm cache needs; without them the GDN layers decline to
  the FLA fallback) [S L540-571][49]. The baked base image's stock
  libr4d is v0.4.0-class and **NaNs this model's GDN output** (WikiText-2
  PPL 653586) — the pinned rebuild is load-bearing, documented in
  PERFORMANCE.md [53].

### L1.2 — stilldeadcode/vllm-radiance:0.9.3

- **Pullable today**: Docker Hub tag API — `0.9.3`, amd64/linux,
  3,958,552,774 B compressed, pushed 2026-08-25T19:40:57Z, tag_status
  active, last pulled 2026-11-07T22:10Z [56]; anonymous registry manifest
  fetch = HTTP 200 [58]. 11 tags exist (0.1.0…0.9.3); 0.9.3 is the newest
  and the fork's pinned base [56].
- **Digest (pin for the overlay FROM)**:
  `sha256:45694209177a55a1ab3ba6702fe6e978b1b66a6e66ae3fc066f8d579f7bc4c25`
  — corroborated by two independent sources: the Hub tag API `digest`
  field [56] and the fork's `Dockerfile.ggz14.top` `BASE_DIGEST` ARG
  default [55].
- **Deprecation warning (live, verbatim)** [57]: "DEPRECATION WARNING —
  This project is no longer being maintained. I ditched vLLM and moved to a
  standalone inference engine project. That project is available at
  https://hub.docker.com/r/stilldeadcode/radiance. I would suggest you
  migrate to the standalone engine now, it is faster, easier to work on,
  starts faster and has less cpu overhead (and thus lower energy cost).
  DEPRECATION WARNING" (repo page "Updated 2 months ago"). The successor
  `stilldeadcode/radiance` is active (Codeberg repo live [75]; Docker Hub
  40k pulls, last_updated 2026-11-04 [75]) — but it is a standalone engine,
  NOT a vLLM/OpenAI-compatible surface: it cannot replace the stilldeadcode
  image for this card without losing the llama-swap hop's contract.
  Consequence for the plan: the base is frozen (no security/ROCm updates
  will arrive); the deprecation is a maintenance-risk note, not a blocker —
  the fork's whole value proposition sits on this exact image.
- **Stack inside 0.9.3** (from the image's own docs, shipped in the fork
  repo as DOCKERHUB.md [51]): vLLM **0.27.1**, PyTorch 2.11.0, Triton
  3.6.0, torchvision 0.24.1, AITER 0.1.17, transformers 5.14.1 (pinned),
  ROCm userspace 7.14, base `rocm/dev-ubuntu-24.04:7.14.0-full`, Python
  3.12. "Tested so far: KV cache fp8, bf16 or `auto`"; "the MTP head is
  inside the checkpoint… vision-language checkpoints — pass
  `--language-model-only` to skip the vision tower".

### L1.3 — magiccodingman/vllm-radiance (the maintained alternative the guide names)

- GitHub `magiccodingman/vllm-radiance`: "Codeberg fork of StillDeadcode /
  vllm-radiance which is a custom vllm tuned for R9700 GPU's" — actively
  maintained, pushed 2026-10-18, 32 open issues [59][60]. This is the
  successor to the stilldeadcode vLLM work (the stilldeadcode author
  migrated to the standalone engine [57]; magiccodingman's fork continues
  the vLLM line).
- **Current stack: vLLM 0.30.0** (pinned `ced6857afa0ea7b2e3f0846a62e1394e90f15607`),
  AMD PyTorch 2.12 branch, Triton 3.7.1, AITER 0.1.20, libr4d 0.5.0, ROCm
  7.14 [60]. It "retains Radiance's tuned FP8 GEMM and speculative-decoding
  paths", adds native gfx1201 MXFP4/W4A8 + DFlash2, and tracks the upstream
  v0.30 DFlash2/structured-output work. Status banner: "experimental";
  primary qualified env = **2× R9700 TP2, mandatory FP8 KV**; "Speculative
  modes remain opt-in because their strict cross-mode output-equivalence
  gate has not passed"; non-spec is the safe recommendation; MTP K4 "tool
  gate FAIL"; DFlash2 K5/K7 "experimental" [60].
- **Docker Hub** `magiccodingman/vllm-radiance`: 34 tags, sha-pinned pairs
  (`sha-<commit>` + `1.0.<n>` + `latest`). Current: `latest` = `1.0` =
  `1.0.397` = `sha-5b99d66c844f`, digest `sha256:b73bf3e41bc0…`, pushed
  2026-10-18, 4.08 GB [61]. The maintainers pin digests in their docs;
  floating tags exist but the guide's "pin @sha256" rule stands [46].
- **Known issue #6** [59]: "fix(rocm): HSA profiler keeps a CPU core busy
  while Radiance is idle" — **open**. Plus #12 "VLLM::EngineCore busy loop
  takes 100% of one CPU core" (open), #5 TP=2 RCCL "HIP illegal state"
  (open), #13 torch.compile ConstraintViolationError (open).
- **Does it replace the stilldeadcode image?** Functionally yes (same
  project line, newer vLLM), operationally it is the guide's *fallback*
  pin, not the fork's target: the GGZ14 launcher, its patches, its KV
  calibration table and its measured numbers all key on
  stilldeadcode/vllm-radiance:0.9.3 / vLLM 0.27.1 [46][51]. Migrating the
  fork onto 0.30 is the maintainer's own v032-overlay work in progress
  [42] — not something this ticket should ride. **Record: candidate for a
  follow-up ticket if stilldeadcode's deprecation forces a base move.**

### L1.4 — capicua25x/vllm-rocm-rdna4 (the guide's fallback image)

- `capicua25x/vllm-rocm-rdna4` Docker Hub: 13 tags [62]. `0.28.0-rdna4` =
  `latest` = `0.28.0-rdna4-rc12`, digest `sha256:2e95bf5c8bb3…`, 9.95 GB,
  pushed 2026-08-28; **`0.28.0-rdna4-rc13`** (the guide's pin, "needed for
  Gemma-4") digest `sha256:a82273c3663b…`, pushed 2026-09-03; older
  `0.26.1-rdna4-rc10` `sha256:c63cc85862f5…` (2026-08-20). All active.
- GitHub `Capicua25x/vllm-rocm-rdna4` (pushed 2026-09-03): "vLLM for AMD
  RDNA4 (gfx1201): Radeon AI PRO R9700 & RX 9070 XT — native MXFP4 linear
  kernel + spec-decode verify fix, carried as rebased branches" [69].
- **It serves a DIFFERENT checkpoint**: `Capicua25x/Qwen3.8-27B-MXFP4-Quark-RDNA4`
  (public, apache-2.0, 20.74 GiB, 18 shards + `model-kvscales.safetensors`,
  lastModified 2026-08-25 [68]) — their own quantization pass
  (`quant_method: quark`, 231 exclude entries, `model.language_model.layers`
  naming, per-layer attention exclusions, calibrated fp8 KV scales) vs
  AMD's release (127 excludes, `model.layers` naming, 18.41 GiB single
  file [65][63]). Its quickstart (vLLM **0.26.1** rc10 era [69][68]):
  plain `vllm serve` entrypoint, `--attention-backend TRITON_ATTN`
  (stock attention — NO R4D), `--speculative-config
  '{"method":"mtp","num_speculative_tokens":3,"attention_backend":"TRITON_ATTN"}'`
  (MTP-3, no drafter), no start-time patching ("simplest to run in K8s" —
  the guide's own words [46]). Measured on 2× R9700 TP2 vs their FP8 arm:
  "at realistic ≈6k context, C matches the FP8 arm within noise at every
  level; the FP8 arm's advantage lives in compute-bound shapes" [68].
  **Use it only as the degraded fallback** (the guide's "one-flag-swap
  fallback Deployment" recommendation [46]); the R9700 primary ships the
  GGZ14 stack.

### L1.5 — stilldeadcode/radiance (context)

The deprecation points to `stilldeadcode/radiance` [57][75] — a standalone
inference engine (not vLLM, not OpenAI-shaped). It is the base author's own
successor; it changes nothing for this ticket beyond the maintenance-risk
note in L1.2.

## L2 — Checkpoint + setup story

### L2.1 — `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` (~19 GiB): state, contents, licensing

- **Live state (2026-11-07)**: public, `gated: false`, apache-2.0, 42,689
  downloads, created 2026-08-15, **main-branch commit sha
  `93245f7c00f1a8964b66a97c6e02e2fd09080be4`, lastModified 2026-11-03**
  [63][64].
- **Layout**: ONE `model.safetensors` = 19,798,196,184 B = **18.41 GiB**
  (the guide's "~19 GiB" is decimal GB) + tokenizer/preprocessor files +
  `config.json` (10.8 KB) + `chat_template.jinja` [63].
- **Contents**: `model_type qwen3_5`,
  `architectures [Qwen3_5ForConditionalGeneration]`,
  `pipeline_tag image-text-to-text`, `language_model_only: false`,
  `mtp_num_hidden_layers: 1`, native `max_position_embeddings: 262144`
  [65]. `quantization_config.quant_method: quark`, OCP microscaling: fp4
  weights + fp4 dynamic activations, group 32, e8m0 scales, AWQ
  calibration (128 × 512-token pileval samples) [65][66].
- **Vision: YES — the tower ships unquantized bf16.** The exclude list has
  **127 entries: 111 `model.visual.*` modules + 15 `mtp.*` + `lm_head`**
  [65]; the checkpoint README states it explicitly: "Vision tower: left
  unquantized (bf16) — only the language-model decoder is quantized;
  `model.visual.*` is excluded" [66]. Card requirement #3 (keep vision) is
  satisfied by the checkpoint AND the fork's image (head_dim-72 ViT flash
  kernel baked [45]; "MTP drafter multimodal mask alignment" patch so spec
  decode works with image inputs [51]).
- **MTP head: ships bf16; the 2026-11-03 config fix changed what the
  rewrite step guards against.** The commit history [64]: initial upload →
  "Fix: add 15 missing MTP tensors to quantization_config.exclude (were
  correctly unquantized, just missing from the list)" → "Fix: regenerate
  stale CRC32 manifest" → **current main `93245f7c`: "Fix mtp exclude
  entries to use module names instead of parameter names (#4)"**
  (co-authored AMD). The fork's README/MXFP4-NOTES describe the bug as the
  fork found it at capture time: mtp named as TENSOR names
  (`mtp.fc.weight`) among module names, so Quark's module match never
  fired, the mxfp4 scheme landed on a bf16 head, and the load died with
  "Attempted to load weight (torch.Size([5120, 10240])) into parameter
  (torch.Size([5120, 5120]))" [45][54]. **Post-fix, the raw release
  excludes mtp properly as modules — it may now load as-is with a bf16 MTP
  head. No public verification of that exists** (the fork's entire
  measured path uses the `fp8_mtp.py` rewrite output
  `Qwen3.8-27B-MXFP4-mtpfp8`; the rewrite's purpose beyond loadability is
  quality: fp8 e4m3 per-channel holds draft acceptance at 2.60–2.80 vs
  MXFP4's 2.21 [45][54]). Best guess: **keep the rewrite step** (open Q8).

### L2.2 — `tcclaviger/Qwen3.8-27B-DFlash2-FP8` (~2 GiB): the drafter

- **Live state (2026-11-07)**: public, apache-2.0, 3,265 downloads,
  created 2026-08-23, lastModified 2026-09-25; `model.safetensors` =
  2,118,882,784 B = **1.97 GiB** + `config.json` +
  `kv_calibration_report_mtp.json` + `model-kvscales.safetensors`
  (1.3 KB) [67].
- **Role**: `architectures: [DFlash2DraftModel]`, `model_type qwen3`,
  quantized fp8 e4m3 dynamic (most modules; the candidate_selector
  codebooks + norms + conv kernels excluded [67]); base =
  `z-lab/Qwen3.8-27B-DFlash2` (bf16). It is a **block-diffusion drafter**:
  it emits the whole speculative block in ONE graphed pass (vs the MTP
  head's serial draft loop) [S L430-434]. Served via
  `SPEC_METHOD=dflash` (the default; `--speculative-config
  {"method":"dflash","model":"/models/Qwen3.8-27B-DFlash2-FP8","num_speculative_tokens":7,…}`
  — the drafter's own attention runs on `TRITON_ATTN` per the config
  [S L842]) or skipped entirely (`--no-drafter` →
  `SPEC_METHOD=mtp`) [47].
- The drafter is deliberately FP8, not MXFP4 (a settled measurement:
  4-bit costs more acceptance than it saves in bandwidth; AWQ did not
  rescue it) [45][54]. `RADIANCE_FAST_DRAFT=1` (baked) packs the draft
  head to int2 with exact rerank (+5.1% decode) and packs DFlash2's
  decoder projections to signed int4 (4.25 bits/weight) at load — "no
  calibration data, nothing on disk" [51].

### L2.3 — What the one-time K8s setup Job runs (setup-mxfp4.sh steps 3–6, source-verified [47])

The launcher-side script is host-driven: it shells out to the container
runtime, so a K8s Job reproduces its steps as container invocations (or,
with the baked image, inline commands). Exactly:

1. **Step 3 — source checkpoint download**: `snapshot_download(repo_id="amd/Qwen3.8-27B-Quark-AWQ-MXFP4")`
   with the image's own `huggingface_hub`, `HF_HOME=/root/.cache/huggingface`
   bind-mounted → standard `hub/models--amd--Qwen3.8-27B-Quark-AWQ-MXFP4/snapshots/<sha>/`
   layout (~19 GiB; resumes on re-run) [47 L112-139].
2. **Step 4 — MTP rewrite**: `python3 fp8_mtp.py <src-snapshot-dir>
   $MODELS/Qwen3.8-27B-MXFP4-mtpfp8` — requantizes the mtp head to fp8
   per-channel + writes the matching `layer_quant_config`, ~15 min, one
   file rewritten [47 L141-168][54]. Idempotency guard: skips if
   `$SNAP/config.json` exists [47 L143-144].
3. **Step 5 — drafter**: `snapshot_download(repo_id="tcclaviger/Qwen3.8-27B-DFlash2-FP8",
   local_dir="$MODELS/Qwen3.8-27B-DFlash2-FP8")` (~2 GiB, plain local-dir
   layout) [47 L170-185]. Skippable with `--no-drafter` (then serve
   `SPEC_METHOD=mtp`).
4. **Step 6 — libr4d build**: `PREPARE_ONLY=1 serve-mxfp4.sh` [47 L187-192]
   → host-side: `git clone
   https://codeberg.org/StillDeadcode/libr4d.git` + `checkout b9e42ab` +
   `apply r4d_radiance_extras{,_rx9}.patch` (rx9 at TP=1) + `container run
   -v .build:/work:z IMAGE ./build.sh` (hipcc, "a few minutes") +
   `mv .build → $R4D_CACHE/b9e42ab-rx9` [S L572-589]. **With the
   baked overlay image (L4.1) the .so is already at
   `site-packages/r4d.so` (baked from the same pin) — step 6's remaining
   job is only to PRE-SEED `$R4D_CACHE/b9e42ab-rx9/r4d.so` if the runtime
   launcher-side check is kept, or to be skipped entirely if the pod
   command is the bare entrypoint+args transcription (recommended, L4.1).**
   The stock in-image libr4d (v0.4.0) NaNs the GDN — never serve on it
   [53][49].
- **Idempotency**: "Safe to re-run: every step checks whether its output
  already exists and skips it. Nothing here is destructive, and nothing
  writes outside $MODELS, the HF cache and ~/.cache/radiance-libr4d"
  [47 L6-7]. Re-runs are safe; the source download's ~19 GiB is deletable
  afterwards (`rm -rf $HF_CACHE/hub/models--amd--Qwen3.8-27B-Quark-AWQ-MXFP4`
  — the script prints the command) [47 L211-215].
- **What a K8s Job writes where**: on the 500Gi `llama-swap` claim mounted
  rw at `/models`: `/models/Qwen3.8-27B-MXFP4-mtpfp8/` (the served
  checkpoint, ~18.4 GiB) + `/models/Qwen3.8-27B-DFlash2-FP8/` (~2 GiB) +
  the source snapshot under the HF-cache root (~19 GiB, deletable) —
  total transient ~40 GiB, steady ~20.4 GiB on the claim. Network needed:
  huggingface.co + codeberg.org (Job only; the serve pod runs
  `HF_HUB_OFFLINE=1` [S L1011][55]). The serve pod's `/models`
  mount stays read-only (today's shape [EXPLORE §2]).
- **`HOME` cache writes under the Job**: the launcher's defaults put
  R4D_CACHE at `$HOME/.cache/radiance-libr4d` and the local KV table at
  `$HOME/.cache/radiance-mxfp4/kv-profiles.local.tsv` — both
  env-overridable (`R4D_CACHE=`, `KV_TABLE_LOCAL=` [S L546][50
  L134-135]). Under the pod shape (runAsUser 0, HOME=/root) the Job just
  needs a writable volume at those paths: the cache PVC (L4.4) with
  `R4D_CACHE=/cache/r4d` etc. resolves it; no hostPath needed.

### L2.4 — The EXACT serve command (TP=1) — source-verified transcription

**Method note (per the guide's rule [46] and the commission)**: the guide
demands capturing `DRY_RUN=1 ./serve-mxfp4.sh` on target; this round could
NOT execute the launcher (no GPU host, no docker daemon in agent sessions).
What follows is therefore a **reconstruction from the repo source at the
pinned commit** — the launcher builds the command from `${VAR:-default}`
knobs with every default measured-documented [S], so the
transcription is deterministic for the chosen shape. Legs marked
**[S]** = source-verified from `serve-mxfp4.sh`/`serve-tp1.sh`/
`kv-profiles.tsv` @ `df0af7cf6b`; **[G]** = guide-transcribed (cross-
checked against [S] where they overlap); **[T]** = on-target capture
remains a runbook step (the DRY_RUN print + `gpu-detect.sh` output +
startup log).

**Shape A — the measured throughput shape (the guide's R9700 numbers; the
recommendation for this card)** [S][G]: `TP=1 MAXSEQS=8 MAXLEN=65536
CHUNK=4096 SPEC_METHOD=dflash SPEC=7 GPU_UTIL=0.98` → KV pin from
`kv-profiles.tsv` row `1x7551-32624  8  4096  65536  dflash  6535819798`
(~6.09 GiB, ~140k KV tokens; measured 2026-09-16 on the NVFP4 checkpoint =
the largest footprint, i.e. conservative) [49]. Note: this shape is NO
LONGER the `serve-tp1.sh` default since 2026-09-18 (default = Shape B);
`serve-tp1.sh`'s own comment names the exact override set: "pass
`MAXSEQS=8 MAXLEN=65536 CHUNK=4096` for the measured throughput shape
instead" [48].

Container flags (the launcher's `run` line, TP=1/docker branch) [S,
L1008-1010]: `--privileged --ipc=host --network=host --device /dev/kfd
--device /dev/dri --group-add <renderGID> --group-add <videoGID>
--security-opt seccomp=unconfined --cap-add SYS_PTRACE` (podman variant
adds `--replace --group-add keep-groups`; K8s has no keep-groups → the
numeric GIDs from `stat -c %g /dev/kfd /dev/dri/renderD*`, which under our
runAsUser-0 shape are moot [EXPLORE §1]).

In-pod command (transcribed for K8s, Shape A, our served name/port) [S]:

```
/opt/radiance_entrypoint.sh vllm serve /models/Qwen3.8-27B-MXFP4-mtpfp8 \
  --served-model-name qwen3.8-27b-vllm --host 0.0.0.0 --port 8000 \
  --kv-cache-dtype fp8 --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.98 \
  --kv-cache-memory-bytes 6535819798 \
  --max-model-len 65536 --max-num-seqs 8 --max-num-batched-tokens 4096 \
  --attention-backend R4D \
  --speculative-config '{"method":"dflash","model":"/models/Qwen3.8-27B-DFlash2-FP8","num_speculative_tokens":7,"attention_backend":"TRITON_ATTN","disable_padded_drafter_batch":true,"draft_sample_method":"greedy"}' \
  --no-async-scheduling \
  --mamba-cache-dtype bfloat16 --mamba-ssm-cache-dtype float16 \
  --compilation-config {"cudagraph_capture_sizes":[1,2,4,8,16,24,32,40,48,56,64],"pass_config":{"fuse_norm_quant":true,"fuse_act_quant":true}} \
  --enable-prefix-caching --mamba-cache-mode align \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3 \
  --override-generation-config '{"temperature":0.7,"top_p":0.95,"top_k":20}' \
  --chat-template /opt/qwen-fixed-v22.3.jinja
```

Provenance leg-by-leg:
- `--kv-cache-dtype fp8` — hardcoded in the launcher line (not a knob)
  [S L1164]; the single-GPU profile also sets GDN ssm=fp16/conv=bf16 via
  the two `--mamba-*-cache-dtype` flags appended to EXTRA at TP=1 [S
  L713-716].
- `--kv-cache-memory-bytes 6535819798` — the launcher passes
  `--kv-cache-memory` (argparse prefix of `-bytes` at 0.27.1 [71]) with
  the tsv pin; the pin is consulted **only at GPU_UTIL=0.98** [S L875-888];
  Shape B's pin row is `9126805504` (220000/2560/3) — **user-reported, NOT
  calibrate-measured — "re-measure with calibrate-kv.sh before trusting
  it"** [49 row 3].
- `--attention-backend R4D` — `R4D_ATTN=1` default → `ATTN=R4D` [S L797];
  R4D requires "head_dim 256, paged block 16, GQA 6, causal attention,
  bf16/fp8 KV; any other shape is refused at startup with the reason" [45]
  — this model fits (head 256, 24q/4kv = GQA 6, default block 16 [70]).
  `R4D_ATTN=0` falls back to `ROCM_AITER_UNIFIED_ATTN` [S L797].
- `--speculative-config` — dflash branch [S L842]: drafter path
  `/models/…` (container-side), `num_speculative_tokens` = SPEC (7 dflash
  default [S L474]), drafter attention `TRITON_ATTN` [S L451],
  `disable_padded_drafter_batch=true` (the ASYNC=0 default pair [S
  L812-813]), `draft_sample_method=greedy` [S L841]. mtp branch [S L844]:
  `{"method":"mtp","num_speculative_tokens":4,"attention_backend":"<target
  ATTN>","disable_padded_drafter_batch":true}` — no model (the head is
  inside the target checkpoint).
- `--compilation-config` — derived: `cudagraph_capture_sizes` capped at
  `MAXSEQS*(SPEC+1)` = 64 at TP=1 [S L680-686] + `pass_config` (NQF=1
  default [S L748-750]).
- tool-calling + reasoning-parser + chat-template: **fixed by the
  launcher, "not EXTRA-tunable"** [45]: `--enable-auto-tool-choice
  --tool-call-parser qwen3_coder --reasoning-parser qwen3` +
  `qwen-fixed-v22.3.jinja` (baked at `/opt/qwen-fixed-v22.3.jinja` in the
  .top image [55]; the launcher's mount logic serves it from `/patches/…`
  when the template sits in the repo dir [S L527-530]). `qwen3_coder` ≡
  `qwen3_xml` (same engine parser since 2026-06) [45].
- `--override-generation-config '{"temperature":0.7,…}'` — the measured
  sampling config, fixed by the launcher [S L1173].
- Env (the launcher's `-e` list, TP=1 Shape A) [S L1008-1096]:
  `ROCR_VISIBLE_DEVICES=0` `HIP_VISIBLE_DEVICES=0` (the GPUS=0
  re-indexing fix [S L1002-1007]; the 8060S must stay excluded — L4.3),
  `HF_HUB_OFFLINE=1`, `VLLM_LOGGING_LEVEL=INFO`, `VLLM_NO_USAGE_STATS=1`,
  `VLLM_ROCM_USE_AITER=1` + `VLLM_ROCM_USE_AITER_UNIFIED_ATTENTION=1` +
  `_MHA/_MLA/_MOE/_LINEAR/_FP8BMM/_FP4BMM/_RMSNORM=0`, `NCCL_PROTO=Simple`,
  the R4D set (`RADIANCE_USE_R4D=1`, `RADIANCE_USE_R4D_AR=1`,
  `RADIANCE_USE_R4D_AR_QUANT=1`, `RADIANCE_R4D_REPORT=1`,
  `RADIANCE_AR_MAX_KB=45056` = `CHUNK·5120·2/1024+4096` [S L849],
  `RADIANCE_AR_QBITS=6`), the MXFP4 set (`RADIANCE_MXFP4=1`,
  `RADIANCE_MXFP4_W4A8=1`, `_W4A8_MIN_M=0`, `_TN4_MIN_M=2048`,
  `_DECODE_MAX_M=64`, `_DECODE_NT=1`, `_A_TILED_MIN_M=513`, `_WPERM=1`,
  `_EPIFAST=1`, `_HOIST_QUANT=1`, `_TRACED_QUANT=1`, `_SANITIZE=0`,
  `RADIANCE_PRESHUFFLE=1`, `RADIANCE_FUSE_RMS_QUANT=1`), the drafter stack
  (`RADIANCE_FAST_DRAFT=1`, `RADIANCE_DRAFT_TAU=0.20`,
  `RADIANCE_DRAFT_RERANK=80`, `RADIANCE_VERIFY_HEAD=1` [S L506],
  `RADIANCE_VERIFY_HEAD_MAX_M=32`), the GDN set
  (`RADIANCE_GDN_MERGE_INPROJ=1`, `RADIANCE_FP8_STREAM=1`,
  `RADIANCE_FP8_STREAM_TP1=1`, `RADIANCE_GDN_NORM_QUANT=1`,
  `RADIANCE_GDN_STRIDED_GATES=0`, `RADIANCE_GDN_EMPTY_OUT=0`,
  `RADIANCE_GDN_FUSED_UPDATE=1`, `RADIANCE_GDN_FUSED_MAX_ITEMS=48` [S
  L717-722], `RADIANCE_GDN_LAZY=0` [S L305-309 — **the multi-turn
  corruption law**: lazy=1 measured 10/50 healthy turns vs 49/50, 35
  empty replies, a repeat loop — default OFF since 2026-09-17),
  `RADIANCE_EMBED_HOST=0`, `RADIANCE_DYNAMIC_WIDTH=1` (+`DYNW_*`),
  `RADIANCE_SKINNY_GEMM=1`, `RADIANCE_MXFP4_DECODE_MAX_M=64` (8-stream
  band [S L614-619]), `MXFP4_CUMODE=0`, the cache dirs
  `VLLM_CACHE_ROOT=/cache/vllm` `TORCHINDUCTOR_CACHE_DIR=/cache/inductor`
  `TRITON_CACHE_DIR=/cache/triton` `AITER_ROOT_DIR=/cache/aiter`
  `TRITON_CACHE_AUTOTUNING=1` [S L1096-1097].
- The .top baked image already carries **most of that env as image-level
  `ENV`** ("bake the launcher's measured defaults in so a bare `docker
  run` reproduces production" [55]) — the pod env then only needs what
  varies: the device pins, `RADIANCE_GDN_LAZY=0` (law, explicit), and any
  Shape-B/EXTRA deltas. (Which exact subset survives the image ENV vs must
  be re-declared is a build-time check — the .top ENV block is the record
  [55]; **confidence: high**.)
- **What DRY_RUN adds on target [T]**: the launcher's host-side
  resolution lines (`[run] gpus=… sig=1x7551-32624 …`,
  `kv_mem=6535819798(measured)`, `cache=~/.radiance-cache-w4a8-093-gdnm-
  nqft-fp8s-gnq-tp1s`) and the final `echo` of the run command [S
  L893-904, L1008] — the runbook's on-target capture step prints these and
  diffs against this section.

**Shape B — the current `serve-tp1.sh` default (long-context)** [S][48]:
`MAXSEQS=3 MAXLEN=220000 CHUNK=2560` + the same profile, KV pin
`9126805504` (the user-reported row [49]). "65536 is what every
single-card THROUGHPUT measurement was made at" [S L694-698]; 220000 is
the long-context shape leaning on the unmeasured pin [S L700-704].

**Served-model-name** [S L1163]: `${SERVED_NAMES:-Qwen3.8 Qwen3.6
Qwen3.8-MXFP4}` — unquoted expansion → three names, v0.27.1
`served_model_name: str | list[str]` [71]; README: "The served model name
is `Qwen3.8` (`Qwen3.6` and `Qwen3.8-MXFP4` are aliases for the same
one)" [45]. **For this repo: pass a single `--served-model-name
qwen3.8-27b-vllm` in the transcribed serveArgs** (the name the
llama-swap hop, the three catalog rows and the runbook already pin
[EXPLORE §4]) — source-verified as the exact flag position in the
launcher's arg list. The alias trio is dropped deliberately (a stray
`Qwen3.6` name would be a picker-visible surface nobody requested).

## L3 — The fork's capability answers for the card requirements

### L3.1 — KV-cache dtypes on gfx1201 under the fork (vLLM 0.27.1 + patches)

Facts [70][72][73][51][45]:
- v0.27.1 `CacheDType` = 16 values (auto, f16, bf16, fp8, fp8_e4m3,
  fp8_e5m2, fp8_inc, fp8_ds_mla, turboquant_{k8v4, 4bit_nc, k3v4_nc,
  3bit_nc}, int4_per_token_head, int8_per_token_head, fp8_per_token_head,
  nvfp4) — **R1's v0.33.0 table (24 values incl. octave_*/ultraquant_*/
  nvfp4_4over6) does NOT apply to this engine generation**; the octave
  family in particular is RDNA3-gated dead-on-R9700 anyway.
- 0.27.1 stock backend dtype support: TRITON_ATTN lists
  `int4_per_token_head`/`int8_per_token_head`/`fp8_per_token_head` [72];
  ROCM_ATTN and ROCM_AITER_UNIFIED_ATTN list only the fp8 family +
  f16/bf16/auto [72]; stock 0.27.1 default priority on ROCm =
  [ROCM_ATTN, (ROCM_AITER_FA), ROCM_AITER_UNIFIED_ATTN, TRITON_ATTN,
  TURBOQUANT] [73]. R1's #54438/#60418 head-256 selector findings are
  v0.33-era and moot here — the fork never runs that selector: it serves
  on **R4D** (its own HIP paged-attention backend, registered by the patch
  chain [45][51]) with `R4D_ATTN=0` fallback to
  ROCM_AITER_UNIFIED_ATTN [S L797].
- **The fork's qualified KV set is `fp8`, `bf16`, `auto`** — the image
  docs' "Tested KV dtypes" line [51] and the R4D kernel's own gate
  ("bf16/fp8 KV; any other shape is refused at startup" [45]). The
  launcher hardcodes `--kv-cache-dtype fp8` [S L1164].
- **Mapping the card's "KV q4 default / q8 toggle" onto the fork**: q8 →
  `fp8` (the qualified default — the guide's own TP1 profile [46]).
  q4 → **not available as a qualified shape**: `int4_per_token_head`
  exists at the CLI/backend level [70][72] but (i) R4D refuses it at
  startup, (ii) the fallback AITER-unified backend doesn't list it [72],
  (iii) it would need `--attention-backend TRITON_ATTN` (stock, un-tuned
  on this stack) and is unmeasured by the maintainer on any shape. The
  fork instead gets its 2×-KV story from the WEIGHT side (MXFP4 4-bit
  weights free ~8 GiB vs FP8-27B, L3.5) and from the calibrated
  `--kv-cache-memory-bytes` pin (the same explicit-pool lever R1 found at
  v0.33, present at 0.27.1 too [70][71] — int bytes only, "ignores
  gpu_memory_utilization").
  **New requirement shape for the re-plan (open Q5)**: a `kvCacheDtype`
  values key defaulting to `fp8`, documented toggle values `bf16`/`auto`
  (tested [51]) and `int4_per_token_head` (experimental: requires
  `--attention-backend TRITON_ATTN` + `R4D_ATTN=0`, unverified — runbook
  on-target gate before enabling).

### L3.2 — Vision under the fork

- The checkpoint carries the 27-layer ViT unquantized bf16 (L2.1
  [65][66]); the image ships a "native head_dim-72 ViT flash kernel"
  (RDNA4-tuned, baked [45]) and runs the vision tower "on the image's own
  Triton flash kernel" [51].
- Spec-decode × vision is explicitly patched: "MTP drafter multimodal
  mask alignment, so speculative decoding works with image inputs
  (otherwise the vision-placeholder mask outlives the compacted draft
  batch and the engine crashes)" [51].
- **The launcher passes NO `--limit-mm-per-prompt`** — the v0.27.1
  default applies (1 image/prompt). The guide's W7900 precedent is
  `.image=4` [46]; `--limit-mm-per-prompt` exists at 0.27.1 in dict form
  [71] → the re-plan adds `--limit-mm-per-prompt image=4` via the
  EXTRA/passthrough position (the launcher passes unrecognized args
  straight through to `vllm serve` [45]) — plan-owned, no maintainer risk
  (R1's precedent for the same decision on the stock path).
- No known RDNA4-vision issue under the fork is recorded in the repo (the
  open issues are GDN-lazy/VRAM-bound [76]); the capicua25x image's docs
  note "Text and vision both work" for their FP8 model [51-adjacent].
  Confidence: vision-loads-and-serves = high (checkpoint + kernels +
  patches all in-tree); image-4 limit + spec-on-image = medium (on-target
  smoke, runbook 3.4-equivalent).

### L3.3 — Speculative decoding ("1m heads") under the fork

- **Two methods, one knob**: `SPEC_METHOD` (`dflash` default | `mtp`
  without drafter) [S L440][46].
  - `dflash` — the block-diffusion drafter
    `tcclaviger/Qwen3.8-27B-DFlash2-FP8` (2 GiB resident, L2.2), one
    graphed draft pass, SPEC=7 default,
    `disable_padded_drafter_batch=true` single-stream lever [S
    L812-842]. "dflash is the default because it is what production serves
    and what the README's numbers were measured on" [S L435-439].
  - `mtp` — the head INSIDE the target checkpoint (the fp8-rewritten head
    of `Qwen3.8-27B-MXFP4-mtpfp8`; SPEC=4 default — "4 beats 8 at decode,
    acceptance falls faster than the deeper drafts pay for themselves"
    [S L453-455]); no second download; the head stays resident either way
    (it is part of the served checkpoint — the R2 analog of R1 L2.3's
    "dormant head is free").
- **"1m heads" = the 1 MTP head (R1 Reading B, confirmed by the owner's
  OQ-A/OQ-E rulings)**: under the fork that head is (a) present in the
  served MXFP4 checkpoint (bf16→fp8 by the rewrite), (b) usable via
  `SPEC_METHOD=mtp` with zero additional weights, (c) irrelevant to
  `SPEC_METHOD=dflash` (the drafter does the work). Keeping "1m heads" is
  therefore satisfied under EITHER spec default; the owner's choice is the
  DEFAULT spec method (open Q1), not the head's presence.
- **Sane default for a single R9700: `dflash` (Shape A)** — every
  published number on this card is dflash (L3.4); it is the maintained
  production path [S L435]; it costs the 2 GiB drafter + a draft-graph
  capture set (`MAXSEQS*(SPEC+1)` = 64 rows, derived [S L680-686]).
  `mtp` (SPEC=4) is the documented no-drafter fallback (`--no-drafter`
  setup + `SPEC_METHOD=mtp` serve [47]) — cheaper in VRAM, slower in the
  maintainer's measurements (mtp 4-depth single-stream anchors in the
  59–60 t/s class vs dflash 137.7 combined [S L453-455, L3.4]).
  Note the magiccodingman counter-signal for context only: on their 0.30
  stack "MTP K4 — tool gate FAIL", "Non-spec is the safe recommendation"
  [60] — a different engine, not this fork's qualified record.

### L3.4 — The fork's published numbers (Ground for the re-plan)

All from the repo at the pinned commit (maintainer measurements; "the
R9700 numbers are the GGZ14 maintainer's own measurements" [46]):

- **TP=1 throughput shape (2026-09-16, `serve-tp1.sh`-era defaults
  MAXSEQS=8 / 65,536 ctx / lazy-GDN OFF, native MXFP4 checkpoint, 210 W
  cap −75 mV)** [45][53]: combined single-stream decode **137.7 t/s**
  (update p99 **35.7 ms**, TTFT p50 95 ms); concurrency sweep c=1/2/4/8 =
  **116.9 / 207.6 / 319.0 / 416.3 t/s** aggregate (the guide's "137.7 at
  c=1" is the single-stream combined figure; the 48-request sweep's c=1 is
  116.9 — both real, different harness legs [53]); **c=16 at
  MAXSEQS=16 = 486.6 t/s** (TTFT p50 533 ms; re-profiles the KV pin —
  `MAXSEQS=16 ./calibrate-kv.sh` needed to claim the margin [45]);
  prefill **2.5–2.8k t/s** (2k: 2737 → 64k: 2480 [45]). Quality: GSM8K
  250q greedy **97.6–98.4%** on this config [45].
- **TP=2 reference (2026-08-30, BetterBench 0.4.0, dflash SPEC=7,
  GPU_UTIL=0.98, KV pinned)** [45]: weights 9.4 GiB/GPU, KV 943,581
  tokens @ 262,144 ctx (3.60× concurrency), decode step 22.7 ms, c=8
  aggregate 572.8 t/s, WikiText-2 PPL 8.3708, GSM8K 97.8%.
- **TP=1 pre-optimization anchor**: before the 2026-09-16 pass the same
  card served 75.4 t/s combined (64 ms/update) [45] — the single-card pass
  was +81% decode / +20% prefill [42-adjacent].
- **Power-policy caveat**: prefill follows core clock; at 300 W the
  2k/64k prefill rose to 3552/3192 t/s and c=8 to 471 t/s, but
  single-stream decode SLOWED (42 ms/update above 3.3 GHz boost) [45].
  The reference box's two cards differ ~12% on prefill under the same cap
  — "compare prefill same-card only". Our node's power policy is unknown
  (BOCO runtime-PM active on the R9700 [EXPLORE §1]) — treat the numbers
  as the anchor class, not the expectation (R1's same caution for the
  stock path).
- The **current main default (Shape B, 220000 ctx / 3 seqs)** carries no
  maintainer throughput numbers of its own (the pin row is user-reported
  [49]) — another reason Shape A is the re-plan's Ground.

### L3.5 — Envelope at MXFP4 on the 32 GiB R9700 (re-derivation input for the plan)

R1 L1.5's structure carries over with the MXFP4 weight set:
- Weights W = 18.41 GiB (MXFP4-mtpfp8, incl. bf16 vision + fp8 MTP head)
  + 1.97 GiB (dflash drafter) = **≈ 20.4 GiB** at TP=1 (vs 28.77 for
  `Qwen/Qwen3.8-27B-FP8` and 16.35 for today's GGUF).
- Pool at `GPU_UTIL=0.98` (the launcher's own ceiling: "0.99 asks for
  31.54 GiB and fails at startup" in THIS stack [S L422-425]) ≈ 31.2 GiB
  (R1's 0.98 row).
- Residual for KV + GDN + activations ≈ 31.2 − 20.4 − O (1.15–1.6, R1
  estimate class) − A (0.3–0.5) ≈ **7.8–8.9 GiB** — and the
  maintainer's MEASURED pins live inside exactly that band: 6.09 GiB KV @
  MAXSEQS=8 (Shape A, ~140k fp8-KV tokens) / 8.49 GiB @ MAXSEQS=3
  (Shape B, ~220k) [49] — the pin replaces R1's derived arithmetic as the
  planning truth (the pin already accounts for the GDN fp16 pages,
  cudagraph captures and allocator fragmentation on this exact card
  [49-adjacent, L2.4]).
- **`--max-model-len 262144` does NOT fit at TP=1** — the launcher's own
  record: "the two-card default (262,144) does not fit next to a 27B
  target plus the drafter on 32 GiB… the NVFP4 prod checkpoint left 0.89
  GiB of KV at 262144 and 1.14 GiB at 65536 (needs 2.85)" [S L694-698].
  So the catalog `limit.context: 262144` on the three vLLM rows (D9
  byte-stable set, [EXPLORE §4]) MUST move to the shipped MAXLEN (65536
  Shape A, or 220000 Shape B) — an owner ruling at the re-plan's approval
  (open Q3), unlike R1 where 262144 survived.
- MTP-head residency: zero marginal weight under dflash (the head is
  dormant inside the target checkpoint) — the R1 "dormant head is free"
  arithmetic transfers [R1 L2.3].
- The q4-KV capacity question is answered by the weight side instead:
  140k–220k fp8-KV tokens at TP=1 is 2–3× the R1 FP8-envelope's
  9.5k–47.7k-token pool at u=0.99/MTP — the fork's MXFP4 weights buy the
  headroom the card originally wanted from KV quantization.

## L4 — K8s translation for THIS repo

### L4.1 — The baked-derived-image approach (the guide's production recommendation, repo CI-shaped)

The guide: "Baking is recommended for production: `FROM
stilldeadcode/vllm-radiance:0.9.3`, then COPY the pinned repo and run the
patch step at build time" [46]. The repo SHIPS exactly this recipe:
`Dockerfile.ggz14.top` — "sits on the PUBLISHED base image, so it bakes
the patch layer in a few minutes with NO stack rebuild. It bakes in
everything the container would otherwise do at every start… so `docker
run` goes straight to `vllm serve`" [55]. Our overlay transcribes it under
the repo's `containers/` CI law (the `containers/vllm-rocm` overlay is the
structural precedent [EXPLORE §2]; no docker daemon in agent sessions —
the image fact is CI/registry-primary per the cf-77 rule [AGENTS.md]):

- **Name/dir**: `containers/vllm-radiance-mxfp4/` → image
  `ghcr.io/ownyourio/vllm-radiance-mxfp4` (open Q4: new dir+name vs
  reusing the `vllm-rocm` dir/image — best guess: new; the GGUF overlay
  dies with the format and the fork is a different engine class, and the
  container-creation skill's "dir name = image name" law keeps the ledger
  honest). The GGUF `containers/vllm-rocm/` dir is retired (its
  `docker-build.yaml` changed-dir detection stops building it; the
  `vllm-render-tests.yaml` trigger path + the `test_ac6` image pin move).
- **Base**: `FROM docker.io/stilldeadcode/vllm-radiance:0.9.3` with the
  ledger comment + `@sha256:45694209177a55a1ab3ba6702fe6e978b1b66a6e66ae3fc066f8d579f7bc4c25`
  pin (the .top's own `BASE_DIGEST` default [55]; re-probe at build —
  `build.sh`'s live-digest pin is the upstream habit; our repo law is the
  manual ledger like `vllm-rocm`'s [EXPLORE §2]).
- **Repo pin**: `ARG RADIANCE_REPO_SHA=df0af7cf6bacaf9c305102d758d70a408b2cc4dd`
  fetched as the Codeberg tarball (`…/archive/<sha>.tar.gz` — the pruned
  base image has no git; the .top installs it at build time only for the
  libr4d clone [55]). No renovate datasource covers Codeberg; the pin is
  manual-ledger like the base image (the sanctioned `git-refs` directive
  exists only for the GitHub mirror, which is stale — do not pin the
  mirror).
- **Build steps (transcribed from [55], with the one fork-pinned delta)**:
  (1) libr4d builder stage: clone @ `b9e42ab`, apply
  **`r4d_radiance_extras_rx9.patch`** (DEVIATION from .top, which bakes
  rx6 [55 L64-70]: rx9 = rx6 + the TP=1 narrow-state GDN kernels the
  single-GPU profile's fp16 ssm cache requires [S L552-557, L562-567];
  "strict superset of rx6"; our pod is TP=1-only, so rx9 is the gated
  build for our shape), `GFX_ARCH=gfx1201 ./build.sh`;
  (2) stage 2: the 23+6 patch chain [55], the module/config copies [55],
  both hipcc kernel builds (`radiance_mxfp4_fp8.so`,
  `radiance_paroquant_kernel.so` — the ParoQuant one is inert for our
  checkpoint but part of the .top record) [55], sitecustomize
  registration [55], entrypoint+preamble install (the 0.9.3 image's
  entrypoint "loses its +x bit" — the .top fixes it [55]), chat-template
  `COPY` to `/opt/qwen-fixed-v22.3.jinja` [55], the measured-profile ENV
  block [55], the `bake_aiter_core.py` aiter-JIT pre-bake (GPU_ARCHS=
  gfx1201, CU_NUM=64 — "tens of minutes" build cost, every boot otherwise
  paid it [55][52]);
  (3) build-time verification: the four `.so` files exist + all
  `radiance_*.py` import-clean in the venv's python [55] — the CI
  equivalent of the on-target import probe (the cf-105 C06 pattern).
- **What the image removes from the pod**: the entire runtime patch
  prelude (the `bash -lc '<25 patches + hipcc>'` wrapper) [S L1108-1162] —
  the pod command becomes the entrypoint + the raw serve args (L2.4); no
  `/patches` mount; no per-restart hipcc of `radiance_mxfp4_fp8.so`
  (baked once); no aiter first-boot JIT (~7 min, FASTBOOT §1 [52]); the
  root FS still stays WRITABLE (the ~113 other aiter modules keep their
  first-use lazy JIT path [55]) — i.e. `readOnlyRootFilesystem: false` is
  intrinsic, and our privileged shape already allows it.
- **What stays out of the image**: checkpoints (500Gi claim, L4.4) and
  caches (PVC at /cache). The chat template is an exception (baked — it is
  data, not code; the .top bakes `qwen-fixed-v22.3.jinja` [55]).
- **First-run compile cost**: "The first `serve-mxfp4.sh` after setup
  spends several extra minutes compiling Triton and inductor kernels…
  cached in `~/.radiance-cache-w4a8-093…`" [46] — under the baked image
  the caches live at `/cache/{vllm,inductor,triton,aiter}` (image ENV
  [55]) on our cache PVC: FASTBOOT's measured cold-cache boot ≈ 381 s vs
  251 s warm (with the aiter bake; without it ~13 min) [52] → the
  startup probe re-derives to a ~30-min first-deploy envelope (the R1
  OQ10 analog; the guide's own K8s budget was 15 s × 160 = 40 min [46]).

### L4.2 — CI law (no docker daemon in agent sessions)

`docker-build.yaml` unchanged (AGENTS.md + [EXPLORE §2]): push to
main/dev touching `containers/**` → per changed dir `buildx` build
(context `containers/<name>/`, image `ghcr.io/ownyourio/<name>`) → push
`:v<run_number>` (immutable) + `:main` (rolling); PRs build-only. The fork
overlay's Dockerfile fetches its two remote sources (the Codeberg tarball
+ the libr4d repo) at BUILD time in CI (network available there — the
GGUF overlay's `pip install git+https://…` precedent [EXPLORE §2] does the
same class of remote fetch). The agent-session build gate shape is
identical: `docker build => no-daemon, CI-deferred` is the passing gate;
build-critical facts (the base digest, the tarball's SHA existence, the
libr4d pin's reachability) are captured from the registry/Codeberg APIs
and reported honestly in `commands_run` (cf-77 ruling).

### L4.3 — The pod shape: GID-486 law carries UNCHANGED (source-verified)

The launcher's own container invocation [S L1008-1010] is:
`--privileged --ipc=host --device /dev/kfd --device /dev/dri
--security-opt seccomp=unconfined --cap-add SYS_PTRACE` + numeric
render/video group-adds. Against the proven pod shape [EXPLORE §1]
(privileged + hostPath /dev/kfd + /dev/dri + runAsUser 0 + runAsGroup 44
+ hostIPC + SYS_PTRACE + Unconfined + 8Gi shm + NO amd.com/gpu):

- privileged: the launcher runs it unconditionally (the guide's
  "escalation order ro /sys → SYS_PTRACE+Unconfined → privileged
  last-resort" [46] is the guide's K8s-translating opinion for the
  device-plugin case; the launcher itself does not negotiate — it is
  privileged, and our node's GID-486 root-cause chain independently
  demands runAsUser 0 + privileged [EXPLORE §1]). **Carry unchanged.**
- hostIPC: the launcher passes `--ipc=host`; the guide's manifest notes
  "no hostIPC needed at TP1" [46] — the launcher's flag and the guide's
  note conflict; the proven shape has it, TP=1 is our shape, and it costs
  nothing under k3s single-node. **Carry unchanged** (the guide's note is
  recorded, not adopted).
- seccomp Unconfined + SYS_PTRACE: both in the launcher line [S L1010].
  Carry unchanged.
- /dev/kfd + /dev/dri: `--device` in the launcher line [S L1009]. Our
  hostPath pair is the K8s equivalent. Carry unchanged.
- Chip targeting: `ROCR_VISIBLE_DEVICES=0` + `HIP_VISIBLE_DEVICES=0`
  (the launcher's GPUS re-indexing [S L1002-1007]). **New pitfall
  grounded**: `gpu-detect.sh` auto-detect would count BOTH this node's
  AMD render nodes (R9700 0x7551 32624 MiB AND the 8060S gfx1151, which
  clears the 8192-MiB floor [50]) and auto-pick TP=2 across an
  arch-mixed pair the gfx1201-only image cannot run [45]. The
  transcription pins `--tensor-parallel-size 1` + the ROCR/HIP envs
  explicitly — never run the launcher's detect path in-pod. (The pod sees
  `/sys/class/drm` fine; the pin is a command-level constant, not a
  probe.)
- `--network=host` in the launcher line [S L1008] has no K8s analog (the
  service + ClusterIP hop already exist [EXPLORE §1]); the pod keeps its
  own netns, `PORT` moves to 8000 (the launcher's default is 8080 [S
  L238]; the `gpu-ai-vllm` service + peers.vllm hop + probes + catalog all
  sit on 8000 [EXPLORE §4]).
- 8Gi shm emptyDir: the guide's manifest uses 16Gi for the fork pod [46];
  the launcher line carries no `--shm-size` (runtime default) [S
  L1008-1106] — the KV-offload RAM tier (KVCACHE=ram, off by default [S
  L927-928]) is the only documented /dev/shm consumer. **Best guess: keep
  the proven 8Gi** (the tested shape never set shm-size; 16Gi is the
  guide's docker-compose-class headroom) — plan call (open Q7-adjacent).
- Resources: the launcher/guide ask `memory: 48Gi` limit / 24Gi request
  [46] (docker-class, incl. the KVCACHE=ram 16 GiB tier); our node's RAM
  law is 16Gi req / 32Gi limit [EXPLORE §1, cf-105 §8.6]. The fork shape
  (no KV offload tier) needs the 32Gi class; **carry the proven 4 CPU /
  16Gi / 32Gi** (plan re-checks against the drafter's host-side pinned
  memory if `RADIANCE_EMBED_HOST` ever ships on — it defaults off [S
  L314-315]).
- **The setup Job shape**: same privileged/device/GID shape (it runs the
  same image's python + hipcc), node-pinned to `ai-gpu`, rw `/models`
  (the 500Gi claim), rw `/cache` (the cache PVC), HOME=/root writable
  (runAsUser 0 — the `~/.cache/…` defaults land on the /cache PVC via the
  L2.3 env overrides), network = default (HF + Codeberg reachable; no
  ingress exposure, no port), `activeDeadlineSeconds` ≥ 7200 (the guide's
  Job budget [46]; 40 GiB of downloads + 15-min rewrite), restartPolicy
  Never, backoffLimit 1. One-shot; re-runs idempotent (L2.3).

### L4.4 — Cache/volume layout decision (grounded)

- **Models (500Gi `llama-swap` claim, pvc-e4f5adf3…)**: R1's D1 (stage on
  the 500Gi claim, pinned sha, one-time operator/Job staging) carries over
  with a different layout: the Job writes
  `/models/Qwen3.8-27B-MXFP4-mtpfp8/` (~18.4 GiB, the served checkpoint),
  `/models/Qwen3.8-27B-DFlash2-FP8/` (~2 GiB) and the deletable source
  snapshot (~19 GiB) under the HF-cache root; steady-state footprint
  ~20.4 GiB + the llama.cpp caches (tens of GiB) on a 500Gi claim —
  non-binding headroom [EXPLORE §1]. The vllm pod mounts it **ro at
  /models** (the launcher's "only mount" [45]; the Job is the rw writer —
  the in-repo tools-sidecar rw precedent is R1 D1's staging actor, here
  the Job IS the staged actor, so the sidecar is optional).
- **Cache (the `vllm-cache` 10Gi PVC, pvc-f986a778…)**: the fork's
  compile caches are small by FASTBOOT's own measurement (`VLLM_CACHE_ROOT`
  ~400 MB, `TRITON_CACHE_DIR` ~90 MB, inductor empty, aiter pre-baked
  into the image [52]) + `R4D_CACHE` (libr4d build: a git clone + hipcc
  output, tens of MB) + the optional `kv-profiles.local.tsv` (bytes).
  **10Gi is sufficient** — BUT the CACHE rule ("one cache directory per
  (image + model + config); new image → new directory; a reused directory
  replays graphs traced under the old settings" [52 §2][46]) means the
  GGUF-era `/data/triton` + `/data/hf` content is INCOMPATIBLE with the
  fork's first boot: the re-plan either (a) recreates the local-path claim
  (delete+recreate is the local-path way, the OQ5 record [EXPLORE §8.4])
  or (b) keeps the claim and mounts a fresh subtree (e.g. `/cache` = the
  PVC root with `vllm/inductor/triton/aiter/r4d/` created at first boot —
  the image ENV already points at exactly those paths [55]; the old
  `/data` tree simply goes unmounted). Best guess: **(b)** — zero PVC
  churn, the `cachePvcSize: 10Gi` pin + the hand-written claim +
  `test_ac4` all survive [EXPLORE §2], the mount path moves
  `/data → /cache`. The `HUGGINGFACE_HUB_CACHE=/data/hf` env DROPS (the
  fork uses `/root/.cache/huggingface` for tokenizer files only,
  ro-mounted from the 500Gi claim or left to the image default —
  `HF_HUB_OFFLINE=1` makes the mount a no-op for anything but tokenizer
  fetches [S L1011]); `TRITON_CACHE_DIR`/`TORCHINDUCTOR_CACHE_DIR`/
  `VLLM_CACHE_ROOT`/`AITER_ROOT_DIR` move from `/data/*` to `/cache/*`
  per the image ENV [55] (pod-level re-declaration optional if the image
  ENV is trusted — record it in the ledger).
- **"Never share one CACHE across configurations"** [45][46] under this
  single-pod-per-card layout: only ONE vLLM configuration ever runs on the
  R9700 (the llama.cpp side lives on the unified image, separate caches,
  same 500Gi models claim but a disjoint tree) → the rule is satisfied
  structurally; it becomes a runbook note for any future second engine
  (e.g. the capicua25x fallback pod): distinct `/cache` volume, never the
  same mount.
- **libr4d**: baked into the overlay image at `b9e42ab-rx9` (L4.1) — no
  runtime build, no `R4D_SO` mount, no Codeberg access at pod start.

### L4.5 — vLLM 0.27.1 under the fork vs the R1 v0.33 pin: what stays, what re-grounds

| R1 finding (v0.33.0) | Status at 0.27.1 / under the fork |
|---|---|
| `--kv-cache-memory-bytes` explicit-pool lever [R1 L3.3] | **STAYS** — field + flag exist at 0.27.1 (int bytes, "ignores gpu_memory_utilization" [70][71]); the fork USES it (the calibrated pin, L2.4). The flag name is the same; v0.33 added human-readable values (not used here). |
| `--kv-cache-dtype` table [R1 L1.2] | **RE-GROUNDED** — 16-value literal at 0.27.1 [70]; no octave_*/ultraquant_*; the qualified serving set is fp8/bf16/auto [51]; int4 exists CLI-side + on TRITON_ATTN [72] but is unqualified (L3.1). |
| `--attention-backend TRITON_ATTN` pin for head-256 fp8 KV [R1 L1.4/D3] | **DOES NOT CARRY** — R1's pin answered v0.33's #54438/#60418 selector economics; the fork serves on its own R4D backend (head-256/GQA6/block-16/bf16-or-fp8-KV only [45]) and the drafter on stock TRITON_ATTN inside the spec config [S L451, L842]. No `--attention-backend` pin decision for the target: `R4D` is the default [S L797]; the re-plan records `R4D_ATTN=0 → ROCM_AITER_UNIFIED_ATTN` as the documented fallback, not a toggle. |
| `--enforce-eager` (batched-FP8 graph-capture NaN) [R1 L1.1] | **DROPS** — that bug is stock-vLLM block-FP8 GEMM on RDNA4 (#28649 [R1 L1.1]); the fork's measured recipe runs with CUDA/HIP graphs ON (the derived capture-size list; the dflash "whole point is the graphed pass" [S L448-451]); graphs stay on. |
| MTP method spelling `{"method":"mtp"}` [R1 L2.1] | **STAYS valid** — 0.27.1's mtp branch uses the clean `method: "mtp"` [S L844]; R1's 0.33 deprecation-alias discussion is engine-generation noise. `num_speculative_tokens`: 4 (mtp default, measured) [S L474]. |
| `--mamba-cache-mode align` + prefix caching on the GDN hybrid [R1 L1.5] | **STAYS, and is the fork's own default** — the launcher passes `--enable-prefix-caching --mamba-cache-mode align` fixed [S L1172]; "Align mode snapshots and restores the GDN recurrent state at block boundaries (verified bit-identical to full recompute, including under MTP)" [45]. |
| `--limit-mm-per-prompt` [R1 L1.4-5] | **STAYS available** (dict form at 0.27.1 [71]); the launcher does not set it (default 1 image) → plan adds `image=4` passthrough (L3.2). |
| `--watermark 0.05` + `--enable-sleep-mode` + `VLLM_SERVER_DEV_MODE` [current live recipe, EXPLORE §1] | **Flags exist at 0.27.1** (`--watermark` [71]; the sleep-mode flag surface to be spot-checked at C01 — R1 verified both at 0.33) but the fork's measured recipe carries NEITHER (no sleep-mode flag in the serve line [S L1163-1175]). The re-plan: `--scheduling-policy priority` MUST carry (the four-class wiring's engine-side half — flag verified at 0.27.1 [71]); `--watermark 0.05` is a values-only candidate (R1's preemption-headroom rationale transfers; unmeasured under the fork); sleep-mode = DROPPED by default (unqualified under the fork + the calibrated KV pin assumes the non-sleep memory story) — open Q7. |
| Startup log markers [R1 L1.6] | **RE-GROUNDED to the fork's set**: the entrypoint banner (`radiance_preamble.py` [55]), `Using RadianceMxfp4W4A8LinearKernel for MXFP4 GEMM`, `[radiance] native MXFP4 enabled on gfx12x`, the R4D selections table (`RADIANCE_R4D_REPORT=1`, baked on [55][S L1020]), the standard `Available KV cache memory / GPU KV cache size / Maximum concurrency` triple (the pin's ~140k tokens is the expected number), `Graph capturing finished` + `Application startup complete` (FASTBOOT's log-read [52]). The stock-FP8 "default W8A8 Block FP8 kernel config" line [R1 L1.6] does NOT appear (different GEMM path). |
| Runbook smoke metrics [R1 L1.6/implications] | **0.27.1-verified names**: `vllm:kv_cache_usage_perc` (fraction 0–1 — the guide's alert expr is correct [46][74]), `vllm:time_to_first_token_seconds`, `vllm:inter_token_latency_seconds` (R1/v0.33's `time_per_output_token_seconds` successor), `vllm:num_preemptions` (exposition: `vllm:num_preemptions_total`), `vllm:prefix_cache_queries|hits` (+`_total`), `vllm:prompt_tokens|generation_tokens` (+`_total`), `vllm:request_success` [74]. **Spec-decode acceptance**: `vllm:spec_decode_num_drafts_total` / `_num_draft_tokens_total` / `_num_accepted_tokens_total` (+ `_per_pos{position=…}`) registered iff a speculative config is live [80] — BUT 0.27.1 also routes diffusion (dLLM) spec through the same stats under `vllm:diffusion_num_denoising_steps` / `_num_canvas_positions` / `_num_committed_tokens` names [80]; whether the fork's `method: "dflash"` registers under the spec_decode_ or diffusion_ family is NOT resolvable from source here (the method is patch-registered [S L842]) → the runbook smoke asserts "either family increments" (confidence: medium; on-target capture [T]). R1's `vllm:spec_decode_num_drafts/_num_accepted_tokens` (cf-105 R5-122, v0.33-era) is the same counters without the exposition `_total`. |

### L4.6 — The repo surfaces the re-plan re-pins (for the planner's map)

- `charts/vllm/values.yaml` (dual-edit law [EXPLORE §8.1]): `modelPath`
  anchor → `/models/Qwen3.8-27B-MXFP4-mtpfp8` (the rewrite output — plain
  directory, NO HF-snapshot hash segment; the pin is the checkpoint's
  main-sha `93245f7c…` recorded in the runbook, the path itself is stable
  by construction [47 L15]); `serveArgs` → the L2.4 Shape-A
  transcription (+ the carried `--scheduling-policy priority`,
  plan-decided `--watermark`, `--limit-mm-per-prompt image=4`, port 8000
  explicitness); image → `ghcr.io/ownyourio/vllm-radiance-mxfp4`
  (`:main` + PIN-ME first-build shape, the `test_ac6` analog re-pinned to
  the new repo name) [EXPLORE §2]; env → the L4.3/L4.4 delta set (device
  pins + `RADIANCE_GDN_LAZY=0` explicit + cache overrides if not
  image-ENV'd; `VLLM_SERVER_DEV_MODE` drops with sleep-mode); persistence
  → models ro `/models` (claim unchanged), cache mount `/data → /cache`
  (claim + 10Gi pin unchanged), HF-cache ro `/root/.cache/huggingface`
  (the 500Gi claim subpath or dropped — plan call); pod shape/resources/
  annotations/service/ingress ruling → byte-stable per D9 (the
  capabilities marker question re-opens under Q6).
- `services/gpu-ai/prod/values.yaml`: the `vllm:` service block's
  `modelPath` twin re-pin (dual edit) + `rocrVisibleDevices: "0"`
  unchanged; the `peers.vllm` hop UNCHANGED (served name preserved, port
  8000 preserved — L4.3) → golden byte-parity holds [EXPLORE §4, §8.11].
- `.github/workflows/vllm-render-tests.yaml`:
  `containers/vllm-rocm/**` trigger path →
  `containers/vllm-radiance-mxfp4/**` [EXPLORE §2];
  `docker-build.yaml`: unedited (changed-dir detection).
- Tests: `testlib.py` `D4_RECIPE` → the fork recipe (flag order pinned),
  `MODEL_PREFIX`/`MODEL_FILENAME`/`assert_model_path_shape` → the plain
  directory path, `test_ac6` → new image repo + first-build PIN-ME
  shape, `test_render` persistence legs → the `/cache` mount + the
  optional HF leg, `test_trio` → the service-block twin re-pin (the two
  overrides).
- The new **setup Job surface**: a chart-level manifest (app-template or
  hand-written `kind: Job`/once-CronJob — plan call; the guide's Job
  shape [46] is the semantic record: nodeSelector `ai-gpu`, the
  privileged/GID-486 shape, rw models + cache, activeDeadline 7200,
  backoff 1, restartPolicy Never, no probe needed — it exits 0 on
  idempotent completion [47]).
- Runbook (`.agents/notes/vllm-on-target-acceptance.md` +
  `tests/notes/vllm-runbook.sh`): step-1 image/name constants, step-2
  weights `find` target (the MXFP4 tree), step-3 startup markers (L4.5
  table), step-6 pre-registered numbers (L3.4: 137.7 single-stream /
  416.3 c=8 / 486.6 c=16 / 2.5–2.8k prefill / 35.7 ms update p99 /
  ~140k KV tokens at the pin / GSM8K 97.6–98.4% class), the
  spec-decode counters smoke (L4.5), the DRY_RUN capture +
  `gpu-detect` verification step [T], the `calibrate-kv.sh` re-measure
  note for Shape B / MAXSEQS=16 [49].
- Catalog: `limit.context` 262144 → the shipped MAXLEN (Q3); the
  `capabilities`/`tools` question re-opens (Q6 — the fork serves
  `--enable-auto-tool-choice` by DEFAULT, unlike the R1 plan's no-tools
  rows [S L1172][45]).

## Contradictions and how to weigh them (R2 conflict map)

1. **README "Repo version 0.12.0" [45] vs `VERSION` file + tag v0.13.0
   [41][42].** The Status line is stale (the last README rewrite
   2026-10-06 post-dates the 09-12 tag but kept the line). Weigh:
   tag/VERSION are the version of record; the guide's "0.12.0 pin" is the
   same staleness class as R1 found in the guide's #60418 line. Pin the
   COMMIT, not the version string.
2. **The guide's TP=1 profile (MAXLEN 65536 / CHUNK 4096 / MAXSEQS 8)
   [46] vs the current main default (220000 / 2560 / 3) [48].** Not a
   conflict: the 2026-09-18 commit deliberately moved the default to the
   long-context shape and LEFT the throughput shape as a documented
   explicit override ("pass MAXSEQS=8 MAXLEN=65536 CHUNK=4096 for the
   measured throughput shape" [48]). Weigh: the throughput shape is the
   ONLY measured row in `kv-profiles.tsv` (the 220000 row is
   user-reported [49]) → Shape A is the re-plan's Ground; Shape B is the
   documented alternative with its caveat.
3. **README "setup-mxfp4.sh already points at
   ggz14/vllm-radiance-mxfp4:latest" [45] vs the scripts' actual default
   `IMAGE=stilldeadcode/vllm-radiance:0.9.3` [S L236][47 L12] vs
   Docker Hub (no ggz14 image) [56].** Weigh: the scripts are the record —
   the public base is stilldeadcode:0.9.3; the `ggz14/…` image is a
   build-local name (`build.sh`'s tag scheme [79]), never published. The
   README line is aspirational/forward-looking (or refers to a private
   publish). K8s: our own baked overlay replaces the need for either.
4. **AMD release "needs the MTP rewrite" (README/MXFP4-NOTES
   [45][54]) vs the 2026-11-03 config fix "use module names instead of
   parameter names" [64] (which makes the raw release's excludes work).**
   Weigh: the fix post-dates all fork documentation; the raw release MAY
   now load with a bf16 MTP head — but no public verification exists and
   the fork's qualified path is the rewrite output (quality: fp8 head
   holds acceptance 2.60–2.80 [45]). Keep the rewrite in the Job (open
   Q8); record the skip condition (a future release declaring mtp in
   `layer_quant_config`, the launcher's own bypass test [S L782-783]).
5. **Codeberg main (df0af7cf6b, 10-30) vs GitHub mirror main (d6162425,
   10-13) [42][44].** The guide names Codeberg canonical [46]; the mirror
   additionally carries an unmerged-elsewhere MoE lane. Weigh: Codeberg
   main is the build source; the mirror is a read-only convenience that
   LAGS — and its extra history must not leak into a pin (a
   "latest-from-mirror" habit would build code the canonical host never
   merged). No sanctioned automation (no Codeberg datasource for
   renovate) → manual ledger, like the base image.
6. **The 220000 KV pin row "REPORTED by a user … NOT measured here"
   [49] vs the 65536 row (calibrate-measured 2026-09-16) [49].** Weigh:
   the measured row is the planning constant; the reported row rides its
   own disclaimer into the plan (Shape B ships only after
   `calibrate-kv.sh` on target — the runbook step).
7. **Guide "PR #60418 still open" [46] vs R1's merge finding (merged
   2026-11-03, post-v0.33.0 [R1 L3.2])** — still a non-conflict at
   0.27.1: #60418 is a v0.33-era selector fix for STOCK backends; the
   fork's R4D backend predates and replaces the question [45]. No action.
8. **The launcher's `--privileged --ipc=host` [S L1008] vs the guide's
   K8s note "hostIPC not needed at TP1 / privileged not required in
   principle (escalation order)" [46].** Weigh: the launcher is the
   measured artifact and it does not negotiate; the guide's note is the
   docker-compose-class aspiration. Our node's independent GID-486
   root-cause (runAsUser 0 required) [EXPLORE §1] makes the privileged
   shape the only working one anyway → carry the proven shape; the
   escalation-order text stays as the documented de-privatization path if
   a host udev GID fix ever lands (the card backlinks' standing
   condition).

## Implications for the re-plan (what changes vs the R1 plan of record)

- **Requirement #1 (official FP8 checkpoint) is DROPPED by the owner
  ruling** [DECISIONS re-scope]; the served weight set becomes
  `Qwen3.8-27B-MXFP4-mtpfp8` (the amd/ release + the rewrite) + the
  DFlash2-FP8 drafter. R1's D1 (stage on 500Gi @ sha) survives in FORM
  (500Gi claim, one-time Job, pinned source sha `93245f7c…`) with the
  L2.3 layout; R1's D4 envelope (0.99/2seq/int4-KV) is SUPERSEDED by the
  fork's measured shape (0.98 + the calibrated pin + Shape-A constants,
  L3.5) — the `--kv-cache-memory-bytes` explicit-pool lever R1 found stays
  the same mechanism, now with a maintainer-measured value [49].
- **R1's D2 KV toggle re-shapes** (L3.1): default `fp8`; the q4 leg is
  demoted to an experimental value with its two prerequisites (R4D off +
  TRITON_ATTN) documented; `bf16`/`auto` join as the tested toggles [51].
- **R1's D3 attention pin does NOT carry** (L4.5): `R4D` is the fork's
  default; the pin discussion is replaced by the `R4D_ATTN=0` fallback
  record.
- **R1's D5/D6 vision+MTP rulings carry in form, change in substance**:
  vision on + `image=4` (L3.2); "1m heads" = the MTP head inside the
  checkpoint, resident by default, usable via `SPEC_METHOD=mtp`; the
  shipped spec default is dflash (the measured path, open Q1) with mtp as
  the values-key toggle — the `enableMtp` record-key pattern (R1 D6/R2)
  transfers directly (it becomes `specMethod: dflash|mtp` + `specDepth`).
- **R1's D7 overlay-retirement INVERTS**: the overlay is no longer
  retired-for-stock-base — it is REPLACED by the baked fork overlay
  (L4.1), the same `containers/` + CI + ledger machinery, a different
  FROM and a different build body. The `vllm-rocm` GGUF overlay's fate:
  retire (its plugin+patch die with the format, as R1 D7 planned) — now
  because the fork image supersedes the whole engine, not because the
  stock path needs nothing.
- **D8 probe re-derives** from FASTBOOT (L4.1): ~30-min first-deploy
  envelope (the guide's 40-min budget is the class), tighten post first
  warm boot [52][46].
- **D9 byte-stable set breaches exactly once, by the re-scope's nature**:
  the catalog rows' `limit.context` 262144 → the shipped MAXLEN (Q3 owner
  ruling); everything else (served name, priorities, peer floor, pod
  shape, resources, annotations, service, ingress ruling, llama.cpp
  roster) stays — the fork's own serve line ends with
  `--served-model-name` at the same flag position [S L1163], so the
  transcription preserves the name with zero wiring churn.
- **The priority wiring's engine-side half is the one R1-missed flag**:
  the fork recipe has no `--scheduling-policy priority` in its measured
  line — the re-plan ADDS it (flag verified at 0.27.1 [71]; unmeasured by
  the maintainer; low risk: a scheduler-knob, not a kernel path — record
  as an assumption in the plan's Risks).
- **New surfaces R1 didn't have**: the setup Job (L4.3), the
  `containers/vllm-radiance-mxfp4/` dir + its ledger (L4.1-L4.2), the
  `kvCacheDtype`/`specMethod`/`shape` values keys (L3.1/L3.3/L4.6), the
  runbook's DRY_RUN capture + spec-counters families (L4.5), and the
  base-image deprecation watch (L1.2: a follow-up ticket candidate for
  the magiccodingman 0.30 base or the stilldeadcode standalone engine).

## Open questions (no-questions-rule log — for the coordinator's batched owner round)

- **Q1 — Spec default: `dflash` (the measured production path, 2 GiB
  drafter resident) vs `mtp` (SPEC=4, no drafter, the "keep 1m heads"
  purist reading)?** Best guess taken: **dflash** (all published numbers
  are dflash [45]; the launcher's own "production default" record [S
  L435-439]; the drafter's VRAM cost is already inside the measured pin).
  Impact: `--speculative-config` JSON + the drafter download in the Job +
  ~2 GiB of the envelope + the acceptance-smoke family; mtp stays the
  one-key toggle (`SPEC_METHOD` → values key `specMethod`).
- **Q2 — TP=1 shape: A (throughput: 65536/4096/8, measured pin 6.09 GiB)
  vs B (long-context: 220000/2560/3, user-reported pin 8.49 GiB)?** Best
  guess taken: **Shape A** (the only maintainer-measured row [49]; the
  card wants the R9700 as the primary throughput backend per the guide's
  own routing rationale [46]; B's pin is explicitly "re-measure before
  trusting" [49]). Impact: MAXLEN/MAXSEQS/CHUNK constants, the KV pin,
  the capture-size list, the pre-registered numbers (L3.4).
- **Q3 — The catalog `limit.context` re-pin (262144 → 65536 under Shape
  A)** — D9's byte-stable law is breached by the re-scope's nature (L3.5:
  262144 does not fit at TP=1). Best guess taken: **65536** (the shipped
  MAXLEN; the llama.cpp `qwen3.8-27b-q8-1m` rung keeps the long-context
  home, as R1 OQ-E ruled). Impact: the three `opencode.jsonc` rows +
  surface.sh M3 + runbook §5 constants + the peers-hop
  `max_input_tokens` semantics (the llama-swap filter surface, EXPLORE §4).
- **Q4 — Image/container naming: new `vllm-radiance-mxfp4` dir+image, or
  reuse the `vllm-rocm` dir/name for the fork?** Best guess taken: **new
  name** (the dir name is the image name; the GGUF overlay dies; the
  fork is a different engine class; the ledger stays unambiguous).
  Impact: chart image repo, `test_ac6` re-pin, CI trigger paths,
  runbook names block, the `vllm-render-tests.yaml` path.
- **Q5 — Confirm the KV requirement's new shape**: "q4 default / q8
  toggle" → q4 KV is NOT a qualified shape under the fork (L3.1); the
  q8 class = `fp8` becomes the DEFAULT; the toggle values = `fp8`/`bf16`/
  `auto` (+ `int4_per_token_head` documented-experimental). The owner's
  OQ3 note ("the RDNA3 card will eventually have 48 GB — the q4 KV
  default is deliberate for that headroom") — does it attach to THIS
  card's future (i.e. keep the int4 leg warm) or to a future
  stock-FP8/48GB card? Best guess taken: keep the `int4_per_token_head`
  value documented but OFF (no default change), with its two
  prerequisites recorded. Impact: the values key's default + the
  toggle's documented set + the runbook gate.
- **Q6 — Tool-calling surface**: the fork ships
  `--enable-auto-tool-choice --tool-call-parser qwen3_coder
  --reasoning-parser qwen3` FIXED (not EXTRA-tunable) [S L1172][45] —
  unlike R1's stock path (no tools flag, catalog rows without a tools
  key per R4's ruling). Does the owner want the three vLLM catalog rows
  to gain a `tools` capability marker this time (revisiting R4's
  "no-tools-key — unverified, not ruled")? Best guess taken: **no
  marker** (the engine-level parser is a wire detail the llama-swap hop
  passes through; the R4 ruling's "unverified" state is unchanged by the
  re-scope — the tool-call correctness record is magiccodingman's 0.30
  stack's 30/30 required-tool checks [60], not this image's). Impact:
  the catalog rows / surface.sh M3 scope.
- **Q7 — Carried flags**: `--scheduling-policy priority` (best guess:
  CARRY — the wiring's engine half, L4.6), `--watermark 0.05` (best
  guess: CARRY as a values default — R1's preemption-headroom rationale
  [R1 implications] transfers; unmeasured under the fork, low-risk
  scheduler knob), `--enable-sleep-mode` + `VLLM_SERVER_DEV_MODE` (best
  guess: DROP — absent from the fork's measured recipe [S L1163-1175];
  the calibrated KV pin assumes the non-sleep memory story; re-enablement
  is a follow-up if Strata co-timing needs it),
  `--disable-access-log-for-endpoints /health,/metrics,/ping` (best
  guess: DROP — launcher-fixed surface; re-add only on observed log
  noise; flag availability at 0.27.1 to be spot-checked at C01).
  Impact: the serveArgs transcription + the env set + the test pins.
- **Q8 — The rewrite step vs the 2026-11-03 AMD config fix**: keep
  `fp8_mtp.py` in the Job (best guess: KEEP — the qualified path, L2.1)
  or skip it now that the excludes are module-named (raw-release load
  unverified; the head would be bf16)? Impact: Job duration (−15 min),
  the staging layout (no `-mtpfp8` tree), the acceptance-smoke class
  (bf16-head mtp numbers are a different quality band [45]).

## Sources (R2)

All web sources accessed 2026-11-07. `[repo …]` cross-references R1's
numbering and EXPLORE.md as in R1.

40. Codeberg — `ggz14/radiance-vllm-mxfp4` repo page + API (main; 312
    commits, 4 tags, 2 branches; main tip `df0af7cf6bacaf9c305102d758d70a408b2cc4dd`
    2026-10-30T14:26+01:00 "Merge PR #59: Add v032/: Radiance overlay for
    vLLM 0.32…"; API `/api/v1/repos/…/branches/main`) —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4
41. Codeberg API — tags (`v1.0` 3d159924… 2026-08-30; `v0.11.0`
    17596f4a… 2026-09-02; `v0.12.0` 5aeb71bc… 2026-09-07 "TP=3 via
    zero-weight dummy heads…"; `v0.13.0` 5bd83165… 2026-09-12 "int5 W5A8
    ParoQuant…") —
    https://codeberg.org/api/v1/repos/ggz14/radiance-vllm-mxfp4/tags
42. Codeberg API — main commits, 45-entry listing (2026-09-17…10-30:
    MXFP6 merges, TP=1 long-context default 1f8ae584 09-18, FASTBOOT
    docs, KVCACHE offload a5036dc6 09-26 + bake 89a36d43 09-29, DRY_RUN
    fix 0d7a8fca, embed-host 881ecd6b, rx10 fix 2e34e262, drafthead
    2ec647c1, v032 c4d8c9dc, merges df0af7cf) —
    https://codeberg.org/api/v1/repos/ggz14/radiance-vllm-mxfp4/commits?limit=45
43. GitHub API — `GGZ14/vllm-mxfp4` (mirror): pushed_at
    2026-10-13T20:10:37Z, main, not archived, 192 stars, 2 open issues —
    https://api.github.com/repos/GGZ14/vllm-mxfp4
44. GitHub API — mirror commits/tags: main tip `d61624250144` 2026-10-13
    (MoE-lane merges, jkuepker, absent from Codeberg main [42]); tags
    v1.0/v0.13.0/v0.12.0/v0.11.0 identical SHAs to [41] —
    https://api.github.com/repos/GGZ14/vllm-mxfp4/commits
45. `README.md` @ Codeberg main `df0af7cf6b` (fetched raw; 1185-line
    capture: Status "Early dev, experimental. Not production hardened" +
    "Repo version 0.12.0; pinned image stilldeadcode/vllm-radiance:0.9.3";
    Tested KV dtypes fp8/bf16/auto; setup steps 1-6; "Why AMD's
    checkpoint needs a rewrite"; the Configuration tables (MODELS/SNAP/
    DRAFTER/CACHE/SPEC_METHOD/SPEC/MAXSEQS/MAXLEN/CHUNK/GPU_UTIL/KV_MEM/
    SINGLE_GPU_PROFILE/ RADIANCE_GDN_LAZY "DEFAULT OFF… corrupts
    multi-turn chat" with the lazy=1 10/50 vs lazy=0 49/50 measurement;
    R4D_ATTN "+37.8% prefill at 260k against AITER unified attention";
    AUTO_R4D "the shipped kernel NaNs this model's output"; SERVED_NAMES
    "Qwen3.8 (Qwen3.6 and Qwen3.8-MXFP4 are aliases)"; "Tool calling and
    reasoning… fixed, not EXTRA-tunable"; Performance: TP1 137.7
    combined / 35.7 ms update p99 / c1 116.9 / c8 416.3 / c16@MAXSEQS16
    486.6 / prefill 2737→2480 / GSM8K 97.6–98.4% (2026-09-16, 210 W cap,
    −75 mV), TP2 22.7 ms / 572.8 @c8 / 943,581 KV tokens / PPL 8.3708 /
    GSM8K 97.8% (2026-08-30); "What's inside the image" (R4D "needs
    head_dim 256, paged block 16, GQA 6, causal attention, bf16/fp8 KV;
    any other shape is refused at startup"; ViT head_dim-72 kernel; the
    correctness-patch list incl. "MTP drafter multimodal mask
    alignment"); "Building the image from source"; Repository layout;
    the FASTBOOT pointer) —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/README.md
46. WeKan AI-Dev card #131 `get_card` (live 2026-11-07) — the full
    owner-attached "Production Deployment Guide" embedded in the
    description (R1's source [36] is the same card; R2 re-reads Part 2 in
    full: the R9700/fork section, the setup-step list, the TP1 profile,
    the K8s Job+Deployment manifests, the escalation order, the fallback
    table, the V1 metric names, the "capture DRY_RUN=1" rule, the "never
    share one CACHE" rule, the baked-image recommendation, the
    unverified-items list) — board `TNQJ2BrXenZovngTS`, card
    `unDxRqcrNTfahp656`
47. `setup-mxfp4.sh` @ Codeberg main (raw fetch, 215 lines): the six-step
    structure; `IMAGE=${IMAGE:-stilldeadcode/vllm-radiance:0.9.3}`;
    `MODELS`/`HF_CACHE` defaults; the `hf_get` (image-python
    `snapshot_download`, `HF_HOME=/root/.cache/huggingface`,
    `--network=host`); step-4 skip guard `$SNAP/config.json`; the
    fp8_mtp.py invocation (host-python fast path else container-run with
    the repo mounted at /repo); step-5 local_dir download; step-6 =
    `PREPARE_ONLY=1 serve-mxfp4.sh`; the idempotency header ("nothing
    writes outside $MODELS, the HF cache and
    ~/.cache/radiance-libr4d"); the 19 GiB source-deletion hint —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/setup-mxfp4.sh
48. `serve-tp1.sh` @ Codeberg main (13 lines): "TP=1 turns on the
    single-GPU profile automatically: fp16 ssm cache, MAXSEQS 3, MAXLEN
    220000, CHUNK 2560 (the long-context shape…; pass MAXSEQS=8
    MAXLEN=65536 CHUNK=4096 for the measured throughput shape instead)" —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/serve-tp1.sh
49. `kv-profiles.tsv` @ Codeberg main (24 lines): the two `1x7551-32624`
    rows (8/4096/65536/dflash/6535819798 measured 2026-09-16 on NVFP4 =
    largest footprint, "7.00 GiB served 161,057 tokens, 7.60 OOM, backed
    off one step; ~140k KV tokens at the pin"; 3/2560/220000/dflash/
    9126805504 "REPORTED by a user … NOT measured … Re-measure with
    calibrate-kv.sh before trusting it") + the `2x7551-32624` row + the
    "why these are not computed" header —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/kv-profiles.tsv
50. `gpu-detect.sh` @ Codeberg main (176 lines): the sysfs render-node
    scan (`/sys/class/drm/renderD*`, vendor 0x1002,
    `mem_info_vram_total`, MIN_GPU_MIB=8192 floor; "the development box
    reports three AMD render nodes"); the TP allowed set "8 4 2 1" (head-
    count divisibility: 24 q / 16 GDN-k / 48 GDN-v); `RAD_GPU_SIG` =
    `<TP>x<devid>-<MiB>`; `rad_kv_lookup` (shipped table then
    `$KV_TABLE_LOCAL` =
    `${XDG_CACHE_HOME:-$HOME/.cache}/radiance-mxfp4/kv-profiles.local.tsv`)
    —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/gpu-detect.sh
51. `DOCKERHUB.md` @ Codeberg main (369 lines): the stilldeadcode image's
    own description shipped in the fork repo: "Tested so far: KV cache
    fp8, bf16 or auto"; "the vision tower on the image's own Triton flash
    kernel"; "the MTP head is inside the checkpoint, so speculative
    decoding needs no separate drafter"; the stack table (vLLM 0.27.1 /
    torch 2.11.0 / triton 3.6.0 / torchvision 0.24.1 / AITER 0.1.17 /
    transformers 5.14.1 / ROCm 7.14 / rocm-dev-ubuntu-24.04 base); the
    patch list (GPU enumeration amdsmi-init, AITER gfx12x enablement, MTP
    unpad + multimodal draft-mask alignment, tool-parser consistency,
    thinkoff); the kernel-knob reference (R4D_ATTN, RADIANCE_MXFP4,
    RADIANCE_MXFP4_W4A8 "off in the image, on in serve-mxfp4.sh",
    FAST_DRAFT int2-head numbers, the ar_maxkb sizing law) —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/DOCKERHUB.md
52. `FASTBOOT.md` @ Codeberg main (241 lines): the two boot costs (aiter
    JIT ~440 s, cold-cache graph compile ~130 s; "a warm boot of the
    current prod image is 3 min 53 s"; "a 1800 s start period here"); the
    cache sizes (~400 MB VLLM_CACHE_ROOT, ~90 MB triton); "One cache
    directory per (image + model + config). New image, new directory." +
    the stale-graph replay hazard; the log-read markers —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/FASTBOOT.md
53. `PERFORMANCE.md` @ Codeberg main (230 lines): the change-by-change
    ledger (the 2026-09-16 TP=1 pass "+81% decode / +20% prefill", the
    2026-09-17 lazy-GDN ship-then-revert row with the 137.7/416/487 +
    117/208/319/416 + 2737/2720/2778/2651/2480 numbers and the GSM8K
    band; "The gated-delta-net NaN (fixed upstream)": libr4d v0.4.0 PPL
    653586, the three `__expf` overflow sites, why the pinned build is
    load-bearing) —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/PERFORMANCE.md
54. `MXFP4-NOTES.md` @ Codeberg main (115 lines): "PRODUCTION launcher:
    native MXFP4 body on gfx1201 with an FP8 drafter, on radiance 0.9.3";
    the original mtp tensor-name bug record; the drafter-FP8-not-MXFP4
    settled result; the 0.5.8 baseline numbers; the `--kv-cache-memory`
    pin story ("do NOT re-derive it from vLLM's fit line… derive it from
    the card") —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/MXFP4-NOTES.md
55. `Dockerfile.ggz14.top` @ Codeberg main (363 lines): the bake recipe
    (FROM `stilldeadcode/vllm-radiance:0.9.3@sha256:45694209177a55a1ab3ba6702fe6e978b1b66a6e66ae3fc066f8d579f7bc4c25`
    via ARG BASE_DIGEST default; libr4d builder stage @ `R4D_PIN=b9e42ab`
    + `r4d_radiance_extras.patch` (rx6); the 23+6 patch chain; the module
    copies; both hipcc kernel builds; sitecustomize registration;
    entrypoint/preamble install + chmod; the measured-profile ENV block
    (cache dirs at /cache/*, RADIANCE_* defaults); the chat-template
    COPY `/opt/qwen-fixed-v22.3.jinja`; the aiter-JIT pre-bake
    (`bake_aiter_core.py`, GPU_ARCHS=gfx1201 CU_NUM=64, "tens of
    minutes"); the build-time import verification; `/build` drop;
    `ENTRYPOINT ["/opt/radiance_entrypoint.sh"]`, no CMD); "NB: the
    published 0.9.3 base carries vLLM 0.27.1" —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/Dockerfile.ggz14.top
56. Docker Hub — `stilldeadcode/vllm-radiance` tags API (11 tags; `0.9.3`
    digest `sha256:45694209177a55a1ab3ba6702fe6e978b1b66a6e66ae3fc066f8d579f7bc4c25`,
    3,958,552,774 B, pushed 2026-08-25, active, last-pulled
    2026-11-07T22:10Z; `0.7.4`/`0.5.8`/… siblings) —
    https://hub.docker.com/v2/repositories/stilldeadcode/vllm-radiance/tags
57. Docker Hub — `stilldeadcode/vllm-radiance` repo page: the live
    DEPRECATION WARNING (verbatim, L1.2) + "Updated 2 months ago" —
    https://hub.docker.com/r/stilldeadcode/vllm-radiance
58. Docker Hub registry — anonymous pull-scope token +
    `GET /v2/stilldeadcode/vllm-radiance/manifests/0.9.3` = **HTTP 200**
    (pullable at the registry level, 2026-11-07) —
    https://registry-1.docker.io/v2/stilldeadcode/vllm-radiance/manifests/0.9.3
59. GitHub — `magiccodingman/vllm-radiance` repo + issues: "Codeberg fork
    of StillDeadcode / vllm-radiance…"; pushed 2026-10-18; issue #6
    [open] "fix(rocm): HSA profiler keeps a CPU core busy while Radiance
    is idle"; #12 [open] "VLLM::EngineCore busy loop takes 100% of one
    CPU core"; #5 [open] TP=2 RCCL HIP illegal state —
    https://github.com/magiccodingman/vllm-radiance (issues)
60. GitHub — `magiccodingman/vllm-radiance` README @ main: "Status:
    experimental"; "The source platform is vLLM 0.30.0" (commit
    ced6857afa…); the 2026-09-22 publication table (Non-spec 53.9
    weighted / c8 304.1; MTP K4 "tool gate FAIL" 135.6/463.9; DFlash2 K7
    186.7 single-stream / 510.2 c8; "Non-spec is the safe recommendation");
    the component pins (torch 2.12 branch, triton 3.7.1, AITER 0.1.20,
    libr4d 0.5.0) —
    https://github.com/magiccodingman/vllm-radiance/blob/main/README.md
61. Docker Hub — `magiccodingman/vllm-radiance` tags API (34 tags;
    `latest`=`1.0`=`1.0.397`=`sha-5b99d66c844f` digest
    `sha256:b73bf3e41bc0…`, pushed 2026-10-18, 4,079,863,554 B;
    sha-pinned tag convention) —
    https://hub.docker.com/v2/repositories/magiccodingman/vllm-radiance/tags
62. Docker Hub — `capicua25x/vllm-rocm-rdna4` tags API (13 tags;
    `0.28.0-rdna4-rc13` digest `sha256:a82273c3663b…` 2026-09-03;
    `0.28.0-rdna4`=`latest`=`rc12` `sha256:2e95bf5c8bb3…` 2026-08-28;
    `0.26.1-rdna4-rc10` `sha256:c63cc85862f5…`) —
    https://hub.docker.com/v2/repositories/capicua25x/vllm-rocm-rdna4/tags
63. HuggingFace API — `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` (?blobs=true,
    2026-11-07): public/ungated/apache-2.0, 42,689 downloads, created
    2026-08-15; single `model.safetensors` 19,798,196,184 B (18.41 GiB);
    pipeline_tag image-text-to-text; usedStorage 19,811,005,504 B —
    https://huggingface.co/api/models/amd/Qwen3.8-27B-Quark-AWQ-MXFP4?blobs=true
64. HuggingFace — `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` /commits/main (the
    8-entry history: upload → "Fix: add 15 missing MTP tensors to
    quantization_config.exclude" → "Fix: regenerate stale CRC32 manifest"
    → main `93245f7c00f1a8964b66a97c6e02e2fd09080be4` "Fix mtp exclude
    entries to use module names instead of parameter names (#4)"
    co-authored AMD, lastModified 2026-11-03T16:13:02Z) —
    https://huggingface.co/api/models/amd/Qwen3.8-27B-Quark-AWQ-MXFP4/commits/main
65. HuggingFace — `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` config.json @ main
    (the 127-entry exclude list = 111 `model.visual.*` modules + 15
    `mtp.*` + `lm_head`; quark global_quant_config fp4 w/a group-32 e8m0
    PerBlockMXObserver; `qwen3_5` /
    `Qwen3_5ForConditionalGeneration` / image-text-to-text /
    language_model_only false / `mtp_num_hidden_layers: 1` /
    `max_position_embeddings: 262144`; no layer_quant_config) —
    https://huggingface.co/amd/Qwen3.8-27B-Quark-AWQ-MXFP4/resolve/main/config.json
66. HuggingFace — `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` README.md @ main
    (vision-exclusion statement "Vision tower: left unquantized (bf16)…
    `model.visual.*` is excluded"; calibration record; GSM8K recovery
    99.2–101.8%) —
    https://huggingface.co/amd/Qwen3.8-27B-Quark-AWQ-MXFP4
67. HuggingFace API — `tcclaviger/Qwen3.8-27B-DFlash2-FP8` (2026-11-07):
    public/apache-2.0, 3,265 downloads, lastModified 2026-09-25;
    `model.safetensors` 2,118,882,784 B (1.97 GiB); config:
    `DFlash2DraftModel`/`qwen3`, fp8 e4m3 dynamic,
    `base_model z-lab/Qwen3.8-27B-DFlash2`; tags dflash2/
    speculative-decoding/block-diffusion/draft-model/sglang/vllm/fp8 —
    https://huggingface.co/tcclaviger/Qwen3.8-27B-DFlash2-FP8
68. HuggingFace — `Capicua25x/Qwen3.8-27B-MXFP4-Quark-RDNA4` README +
    API (2026-11-07): public/apache-2.0, 274 downloads, 20.74 GiB, 18
    shards + `model-kvscales.safetensors`; config: quark, 231 excludes
    (`model.language_model.layers` naming + per-layer attention
    exclusions), `mtp_num_hidden_layers: 1`, image-text-to-text; the
    quickstart serve command (vLLM 0.26.1 rc10 image,
    `--attention-backend TRITON_ATTN`, MTP-3 speculative config,
    `--served-model-name qwen`, port 8011); "What is 4-bit: MLP/expert
    projections only… Attention (q/k/v/o + norms) [stay bf16]"; "calibrated
    fp8 KV-cache scales ship as a side-file; they only activate under
    --kv-cache-dtype fp8"; the MXFP4-vs-FP8-arm A/B —
    https://huggingface.co/Capicua25x/Qwen3.8-27B-MXFP4-Quark-RDNA4
69. GitHub — `Capicua25x/vllm-rocm-rdna4` (pushed 2026-09-03; "native
    MXFP4 linear kernel + spec-decode verify fix, carried as rebased
    branches") — https://github.com/Capicua25x/vllm-rocm-rdna4
70. vLLM **v0.27.1 release** (published 2026-08-11T10:47:49Z) —
    https://github.com/vllm-project/vllm/releases/tag/v0.27.1
71. vLLM v0.27.1 `vllm/config/cache.py` + `vllm/engine/arg_utils.py` @
    tag (raw GitHub fetches): `CacheDType` 16-value literal (incl.
    `int4_per_token_head`, `turboquant_*`, `nvfp4`; NO octave_*/
    ultraquant_*); `kv_cache_memory_bytes: int | None` ("when not-None
    ignores gpu_memory_utilization", int bytes only); `MambaDType` /
    `MambaCacheMode` ("all"/"align"/"none"); CLI flags
    `--kv-cache-memory-bytes` (L1201; the launcher's `--kv-cache-memory`
    prefix-resolves to it), `--mamba-cache-dtype`/`--mamba-ssm-cache-dtype`
    (L1227/1230), `served_model_name: str | list[str]` (L428),
    `--override-generation-config` (L898), `--limit-mm-per-prompt`
    (dict form, L1293), `--async-scheduling`/`--no-async-scheduling`
    (L1525), `--scheduling-policy` (L1496), `--watermark` (L1515) —
    https://raw.githubusercontent.com/vllm-project/vllm/v0.27.1/vllm/config/cache.py
72. vLLM v0.27.1 attention backends @ tag: `triton_attn.py`
    `supported_kv_cache_dtypes` incl. `int4_per_token_head`/
    `int8_per_token_head`/`fp8_per_token_head`; `rocm_attn.py` +
    `rocm_aiter_unified_attn.py` fp8-family-only —
    https://raw.githubusercontent.com/vllm-project/vllm/v0.27.1/vllm/v1/attention/backends/triton_attn.py
73. vLLM v0.27.1 `vllm/platforms/rocm.py` @ tag: default ROCm attention
    priority `[ROCM_ATTN, ROCM_AITER_FA?, ROCM_AITER_UNIFIED_ATTN,
    TRITON_ATTN, TURBOQUANT]` —
    https://raw.githubusercontent.com/vllm-project/vllm/v0.27.1/vllm/platforms/rocm.py
74. vLLM v0.27.1 `vllm/v1/metrics/loggers.py` @ tag:
    `vllm:kv_cache_usage_perc` (fraction), `vllm:time_to_first_token_seconds`,
    `vllm:inter_token_latency_seconds`, `vllm:num_preemptions`,
    `vllm:prefix_cache_queries|hits`, `vllm:prompt_tokens|generation_tokens`,
    `vllm:request_success` —
    https://raw.githubusercontent.com/vllm-project/vllm/v0.27.1/vllm/v1/metrics/loggers.py
75. Codeberg / Docker Hub — `stilldeadcode/radiance` (the deprecation's
    target: standalone engine, active; Codeberg repo live; Hub image
    40,136 pulls, last_updated 2026-11-04) —
    https://codeberg.org/StillDeadcode/radiance ·
    https://hub.docker.com/r/stilldeadcode/radiance
76. Codeberg API — repo open issues: #58 "lazy GDN: mode-0 materialize
    zeroes a foreign block without a drafter (RADIANCE_GDN_LAZY=1, no
    spec)" [open], #53 "Relaxing vram bound for large context" [open] —
    https://codeberg.org/api/v1/repos/ggz14/radiance-vllm-mxfp4/issues
77. `radiance_entrypoint.sh` @ Codeberg main (114 lines): NUMA-bind
    (off by default), the backgrounded `rocm-bandwidth-test` topology
    sweep (on by default, ~1 s), the `radiance_preamble.py` banner,
    `exec vllm serve "$@"` — the baked image's runtime entry —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/radiance_entrypoint.sh
78. `serve-mxfp4.sh` @ Codeberg main (raw fetch, 1175 lines): cited above
    as "S" (the `-e`/`-v`/flag lists L1008-1175; the knob
    defaults L236-724; the SPEC_CFG construction L817-845; the KV-pin
    resolution L875-900; the R4D build L540-589; the cache-suffix law
    L366-418; the GDN_LAZY corruption record L302-331; the single-GPU
    profile L642-724; the fixed tool-calling/reasoning flags L1172) —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/serve-mxfp4.sh
79. `build.sh` @ Codeberg main (163 lines): the tag scheme
    `ggz14/vllm-radiance-mxfp4:$VERSION-$SHA` + `v$VERSION` + `latest`;
    "pulls the published base, passes its live digest as
    `--build-arg BASE_DIGEST`"; no-GPU builds ("hipcc compiles for gfx1201
    without a device"); the per-recipe gates import every radiance module
    before the image is declared built —
    https://codeberg.org/ggz14/radiance-vllm-mxfp4/src/branch/main/build.sh
80. vLLM v0.27.1 `vllm/v1/spec_decode/metrics.py` @ tag:
    spec-decode counters registered iff `speculative_config` is live:
    `vllm:spec_decode_num_drafts` / `_num_draft_tokens` /
    `_num_accepted_tokens` (+ `_num_accepted_tokens_per_pos{position}`)
    OR, on the diffusion (dLLM) spec path,
    `vllm:diffusion_num_denoising_steps` / `_num_canvas_positions` /
    `_num_committed_tokens` (which family the fork's `method: "dflash"`
    registers under is not resolvable from source — the runbook asserts
    either) —
    https://raw.githubusercontent.com/vllm-project/vllm/v0.27.1/vllm/v1/spec_decode/metrics.py
81. [repo] `EXPLORE.md` (cf-131, 2026-11-07) — the live pod/env/PVC/
    pod-shape facts, the priority-wiring pin set, the
    `containers/vllm-rocm` + `charts/vllm` + `services/gpu-ai` surface
    inventory, the chip map (R9700 = HIP index 0; the 8060S = index 1; no
    amd.com/gpu), the storage map (500Gi/10Gi claims)
82. [repo] R1 above (this file, lines 1–707) — the v0.33.0 generation's
    findings, carried where L4.5 says they carry
83. [repo] `DECISIONS.md` (cf-131 folder) — the re-scope ruling verbatim +
    the D1–D9/R1–R7 plan-decision record the re-plan supersedes in part

## Reliability notes (R2 self-review)

- **High confidence (primary source @ exact ref, mutually consistent):**
  the pin target and its divergence from the mirror [40][41][42][43][44];
  the base image's pullability + digest (three corroborating sources: Hub
  API [56], the fork's own ARG [55], the registry manifest probe [58]);
  the exact serve command shape and every default it depends on
  [78][48][49] (the launcher is `${VAR:-default}` end-to-end with the
  measurement behind each default documented in-file); the checkpoint
  states (single-file 18.41 GiB, vision-in, MTP-in, the 2026-11-03
  config fix [63][64][65]); the drafter state [67]; the v0.27.1
  flag/dtype/metric surface [70]-[74][80]; the baked-image recipe
  [55][77][79] (including that `.top` bakes rx6, which our TP=1 overlay
  must deviate to rx9 [78 L552-571]).
- **Medium confidence:** (a) the Shape-A transcription as a POD command —
  source-verified leg-by-leg [L2.4 provenance list], but never executed
  (no GPU in agent sessions); the on-target DRY_RUN capture [T] is the
  verification the runbook carries; (b) the rx9-bake deviation's safety
  ("strict superset of rx6" is the launcher's own record [78 L552-557],
  ungated at TP≥2 — fine for our TP=1-only pod, but it IS a deviation
  from the shipped recipe); (c) whether `method: "dflash"` registers
  under `spec_decode_*` or `diffusion_*` prometheus families [80] — the
  runbook's either-family assertion covers both; (d) the
  `--scheduling-policy priority` carry (flag exists [71] but is
  unmeasured in the fork's numbers — a scheduler-knob-class risk,
  recorded in the plan's Risks); (e) the O/A overhead band reused from
  R1's GGUF-run measurement for the MXFP4 envelope [L3.5] (the MXFP4
  non-torch set was never measured; the calibrated KV pin — not the
  envelope band — is the planning constant).
- **Weakest claim:** "Shape B's 220000 pin is servable" — it is
  user-reported, not maintainer-measured [49], and its row says so in its
  own note; it is recorded as the documented alternative ONLY, behind
  Shape A, with the calibrate-kv re-measure as the precondition.
- **Perspective weighting:** the repo source at the pinned commit
  dominates (it is the measured artifact's own text); the guide [46] is
  treated as claims-to-verify exactly as R1 did — its three R2-relevant
  deltas found: the TP=1 default moved [48][42], the served-name/aliases
  mechanism is an env knob not a flag mystery [78 L1163], and the "no
  start-time patching needed" claim holds only for the BAKED image [55],
  not the stilldeadcode base (which the launcher still patches at every
  start [78 L1108-1162]).
- **Blind spots (stated, not found):** no on-target DRY_RUN capture (the
  commission's explicit [T] hand-off to the runbook); no pull-and-import
  of the stilldeadcode image (registry manifest probe only — the image
  itself is CI-built, cf-77); the 0.27.1 sleep-mode flag surface
  (spot-check at C01, Q7); the fork's tool-call correctness on THIS image
  (the 30/30 record is magiccodingman's 0.30 build [60], not 0.9.3+fork);
  the node's power policy vs the reference box's 210 W cap [45] (BOCO
  runtime-PM active per [81] — the L3.4 numbers are the anchor class, not
  the expectation).

---

# R3 — magiccodingman/vllm-radiance 0.30 base (owner round-2 Q10 ruling)

Round-3 research commission for board card #131, 2026-11-07, by
`agent-research`. The owner's batched round-2 ruling Q10
(DECISIONS.md "Owner rulings — batched round 2"): **"Migrate to
magiccodingman/vllm-radiance 0.30 as a part of this work"** — the
stilldeadcode/vllm-radiance:0.9.3 base that R2 pinned (vLLM 0.27.1) is NOT
the ship target; the maintained 0.30 stack is THIS ticket's base image, and
R2's 0.27.1-engine groundings are re-grounded here against it. Standing
round-2 rulings grounded against in this round: Q1 dflash default · Q2
Shape B (220000/2560/3, the guide's re-measure gate stands) · Q3 catalog
`limit.context` stays 262144 byte-stable · Q4 the
`containers/vllm-radiance-mxfp4` name · Q5 int4 KV gains an on-target
qualification gate in this ticket · Q6 the tools capability marker lands on
the three catalog rows · Q7 priority+watermark carry /
sleep-mode+dev-mode+access-log drop · Q8 RAW-RELEASE staging (the
`fp8_mtp.py` rewrite is SKIPPED) · Q9 init-container staging actor · Q10
this base move. All web evidence accessed **2026-11-07** unless stamped;
citation keys continue R2's numbering at [84]. R1 above stays supporting
context; its v0.33.0 dtype table and #60418 record are the mapping
references for the 0.30 engine.

## TL;DR (5 lines)

1. **Pin = `magiccodingman/vllm-radiance:1.0.397` (= `latest` = `1.0` =
   `sha-5b99d66c844f`) @
   `sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0`**
   (Docker Hub tag API + registry manifest probe + the image's own OCI
   `org.opencontainers.image.revision` label all agree). 4.08 GB, amd64/
   linux, single-arch, pushed 2026-10-18; built from the repo's `release`
   branch tip `5b99d66c844f` (2026-10-17, "Merge main into release: Qwen
   tool grammar interoperability"); the GitHub `main` tip `1d2e248`
   (2026-10-18, test-only merge) has NO image and is not the pin [84][85]
   [86][87].
2. **Engine = vLLM v0.30.0 exactly**: the pinned commit
   `ced6857afa0ea7b2e3f0846a62e1394e90f15607` IS the `v0.30.0` tag commit
   (git-ref verified; release published 2026-09-22) — no post-release
   follow-ups in the pin. Full stack: AMD torch 2.12.0 / triton 3.7.1 /
   AITER 0.1.20 / transformers 5.15.0 / xgrammar 0.2.3 / **libr4d 0.5.0**
   (`e8de4bc1` + the repo's own extras patch) / ROCm 7.14 [84][90][99].
   The image is a SELF-CONTAINED terminal artifact: entrypoint + 35 source
   overlays + all kernels + tuned R9700 FP8 GEMM configs baked; no
   start-time patching, no build work for us [93][94].
3. **The qualified pairing is the 0.30 image + the magiccodingman recipe
   (its `docker-compose.yml` baseline + `.env.example` knobs), NOT the
   GGZ14 launcher**: the launcher's 23+6 patch chain and its
   `b9e42ab-rx9` libr4d build key key on stilldeadcode:0.9.3 / vLLM
   0.27.1 (source-anchored patches against a tree the 0.30 image already
   carries patched; a rebuilt libr4d would replace the baked 0.5.0 ABI the
   image asserts at build time). Our overlay collapses from R2's `.top`
   transcription to a THIN digest-pinned re-export; the rx9 deviation (D11)
   stops applying [93][95][88].
4. **Q8 (raw release) is grounded at 0.30**: the stack's own qualified
   MTP lane (2026-09-22 publication) ran the PRE-FIX checkpoint revision
   `156be69f` with in-checkpoint BF16 MTP tensors via the baked
   `patch_quark_bf16_mtp` load path, gated by `RADIANCE_QUARK_BF16_MTP=1`
   ("Non-spec and DFlash do not need that override") — our staging pin
   (main @ `93245f7c`, post the 2026-11-03 module-name fix) is strictly
   more loadable; the `fp8_mtp.py` rewrite has NO 0.30 counterpart and
   stays skipped [108][111][107].
5. **Q5/Q6 re-ground**: int4 KV is still UNQUALIFIED at 0.30 (R4D's baked
   gate: KV = auto/bf16/fp8/fp8_e4m3 only, per-(token,head) KV scales
   refused at startup; `int4_per_token_head` exists at the 0.30 CLI +
   TRITON_ATTN level) — the two-edit prerequisites carry verbatim and the
   owner's on-target gate stands [95][101][102]. The **30/30 tool record IS
   the 0.30 stack's own** (non-spec + DFlash K5/K7, 2026-09-22 publication:
   "Required multi-tool schema, temperature 1", `qwen3_coder` + XGrammar
   0.2.3, TP2, the Quark MXFP4 target) — but MTP K4 is **29/30 = tool gate
   FAIL**, and every 0.30 number is TP2: our TP1 pod is not in any
   qualified configuration, so the marker's grounding carries an explicit
   TP2→TP1 caveat plus an on-target tool smoke [108][112].

## L1 — The 0.30 image + its lineage

### L1.1 — Image identity, the pin, and the tag↔commit law

- **Docker Hub `magiccodingman/vllm-radiance`** [85]: 34 tags; current set
  `latest` = `1.0` = `1.0.397` = `sha-5b99d66c844f`, all one digest
  `sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0`,
  amd64/linux, 4,079,863,554 B compressed, `tag_status: active`, pushed
  2026-10-18T06:35Z, last pulled 2026-11-07 (actively used). Predecessor
  pairs: `1.0.394`/`sha-d1535e95465d` @ `sha256:94adfd79…` (2026-10-09),
  `1.0.387`/`sha-1855cd8cdb3b` @ `sha256:c0e8f375…` (2026-09-23), `1.0.16`/
  `sha-f295b9ef51ad` @ `sha256:83a9dc02…` (2026-09-09 — the "production
  1.0.16" the v0.30 docs keep referencing as the standing deployment).
  Repo metadata: 13,005 pulls, description "fork of StillDeadcode /
  vllm-radiance which is a custom vllm tuned for R9700 GPU's", last_updated
  2026-10-18, no deprecation banner (the opposite of the stilldeadcode
  line, L1.5).
- **Registry probe (the R2 method)** [86]: anonymous pull-scope token from
  `auth.docker.io` + `GET /v2/magiccodingman/vllm-radiance/manifests/1.0.397`
  = **HTTP 200**, a single-arch `application/vnd.docker.distribution.manifest.
  v2+json` (no manifest list), and sha256-of-manifest-bytes =
  `b73bf3e41bc0a1cf7aaa…` = the Hub API digest exactly (same result for the
  `sha-5b99d66c844f` tag). The config blob (digest
  `sha256:c8059c55…`, fetched from the registry) records: `Entrypoint:
  ["/opt/radiance_entrypoint.sh"]`, no `Cmd`, `User: null` (root),
  `RADIANCE_VERSION=1.0.397`, the full baked `RADIANCE_*` flag set (L3.1),
  and **`org.opencontainers.image.revision =
  5b99d66c844fd0a54e4a7eb93b40a1ece009a53d`** — the artifact itself names
  its source commit.
- **Tag↔commit law** [87]: the publish job runs ONLY on the `release`
  branch (`$CI_COMMIT_BRANCH == "release"`), stamps
  `VERSION=1.0.${CI_PIPELINE_IID}` → **`1.0.397` = pipeline #397 of the
  release line**, tags each build `1.0.397` + `1.0` + `sha-<short commit>` +
  `latest`, and labels the image with `org.opencontainers.image.revision =
  <commit>`. The two public branches today: `main` @ `1d2e24849c…`
  (2026-10-18T14:21Z, "Merge branch 'test/client-shaped-tool-regressions'
  into 'main'" — the repo's pushed_at) and `release` @ `5b99d66c844f…`
  (2026-10-17T23:40Z, "Merge main into release: Qwen tool grammar
  interoperability", parents = release/`1.0.394` + main/`1d9016bb`
  "fix: guard Qwen tool grammar interoperability and modern fallback").
  **Consequence: the pinned image contains everything in main as of
  `1d9016bb` + the tool-grammar merge; the test-only `1d2e248` merge is NOT
  in any image.** The repo's `VERSION` file on main reads
  `1.1.0-rc1.vllm0.30.0` (the source-track version; the publication docs
  use it as the Radiance identity), while the published tag line is the
  release branch's `1.0.<pipeline>` series — the two version schemes must
  not be conflated in the ledger.
- **Push recency / maintenance state**: last image push 2026-10-18 (20 days
  before this commission); GitHub repo pushed 2026-10-18, updated 2026-11-07
  (issue/PR activity), 160 stars / 9 forks / 32 open issues [59][84].
  Active: issue triage, open fix PRs (#19 docs, #42 experimental runtime),
  contributor hardware-qualification protocol ("the maintainer
  hardware/runtime qualification is required before promoting runtime
  changes or publishing an image" [97]).
- **Lineage (the relationship to stilldeadcode:0.9.3)** [84 L25-29][90]:
  magiccodingman's repo is the vLLM-line continuation of
  StillDeadcode/vllm-radiance (DeadCode's "custom vllm tuned for R9700
  GPU's"): it "tracks and credits DeadCode's vllm-radiance and libr4d work",
  runs the same Radiance runtime + R4D attention family + libr4d kernels,
  and additionally ports GGZ14's native Quark MXFP4/W4A8 work
  (donor frozen at GitHub-mirror commit `31b9a94a`, 2026-09-22 [89]) plus
  "upstream v0.30 DFlash2 and structured-output ownership". StillDeadcode
  himself deprecated the vLLM line for a standalone non-vLLM engine
  (R2 L1.2/L1.5 — the deprecation warning re-verified live today [57]), so
  the 0.30 fork is the maintained home of the vLLM/R9700 story; the
  standalone `stilldeadcode/radiance` successor stays out of scope for this
  ticket (not an OpenAI-shaped surface — the llama-swap hop's contract,
  R2 L1.2). libr4d remains a shared StillDeadcode-repo library: active
  (Codeberg main tip `a3e4833d` 2026-10-04; tags v0.4.0 + v0.5.0),
  `e8de4bc1` (the 0.30 image's libr4d pin, the v0.5.0 line) post-dates the
  GGZ14 `b9e42ab` pin and carries its GDN overflow fixes (b9e42ab = the
  "[FIX] correct the exponent clamp rationale in gdn chunk_scan" commit of
  2026-08-24, i.e. the R2 "fixed upstream" NaN class [88]).
- **What the owner's Q10 pin decision therefore is**: tag `1.0.397` +
  digest `sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0`
  (guide's Part 2.3 rule honored: "pin `@sha256:` — the maintainers' own
  docs pin digests; floating tags are not used" [46]), with the ledger
  recording source commit `5b99d66c844f` (the OCI revision label) and the
  watch line "next `release`-branch publish = new `1.0.<n>` / `sha-<…>`
  pair".

### L1.2 — What is inside the image (the stack + the bake record)

- **Component pins** — three-way agreement between the README Build table
  [84 L394-401], `DOCKERHUB.md`'s source-stack table [91], and the
  machine-readable `.radiance/stack.yaml` [90]: vLLM **0.30.0 @
  `ced6857afa0ea7b2e3f0846a62e1394e90f15607`** (= the v0.30.0 tag commit,
  L2.1) · AMD PyTorch **2.12.0 @ `6bbd26020da1…`** · AMD Triton **3.7.1 @
  `f0b55c07da61…`** · torchvision 0.27.1 · AITER **0.1.20 @
  `fc2e5d57fb5b…`** (built for gfx1201, runtime JIT) · transformers
  5.15.0 · xgrammar 0.2.3 · libr4d **0.5.0 @ `e8de4bc1f3db…`** (build:
  "source-plus-radiance-patch" = the repo root's
  `r4d_radiance_extras.patch`) · ROCm userspace **7.14** (base
  `rocm/dev-ubuntu-24.04:7.14.0-full@sha256:439edaa8…`). Stack policy:
  "Treat as a coordinated compatibility stack; do not independently bump
  members" (atomic group rocm-compiler-stack; "an earlier mismatched
  combination caused sustained TP hangs" [84 L416-417][90]).
- **The release overlays** (35 applied at build time per the V030_UPGRADE
  source audit — "35 release overlays twice, 70 successful operations"; the
  migration matrix [109] registers 45 historical/current rows, of which the
  `UPSTREAM_OWNED` and `OBSOLETE_DELETE` rows are NOT applied in the 0.30
  build), each drift-checked against the pinned vLLM tree:
  R4D integration (`patch_r4d`), Quark MXFP4/W4A8 native routing
  (`patch_quark_mxfp4`, "MECHANICAL_PORT"), **Quark BF16-MTP load
  (`patch_quark_bf16_mtp` — L2.6)** (`RETAIN_UNCHANGED`), MTP unpad +
  multimodal mask alignment (`patch_mtp_loopbreak`, `patch_mtp_mm_mask` —
  the same two classes stilldeadcode's 0.9.3 docs listed [51], now on
  0.30), DFlash fused-KV/W4/selector/dynwidth (`RETAIN`/ports), GDN
  metadata/merge-inproj/shared-build/WMMA (`patch_gdn_*` — the GDN
  hybrid's 0.30 ports), XGrammar spec-termination + reasoning-boundary
  backports (`UPSTREAM_OWNED` rows), Qwen tool-parse / open-object schema /
  **tool-grammar interoperability** (`patch_qwen3_toolparse`,
  `patch_qwen_open_object_schema`, `patch_qwen_tool_grammar` — the last is
  what the pinned image's release merge carries, L3.2), NVFP4→MXFP4
  default-off load-time conversion, the four KV-offload patches,
  verify-head, skinny GEMM, preshuffle, unified-attention LDS guard,
  AR geometry/maxbytes (TP2 compressed all-reduce), conv1d block-N,
  dynamo metrics, topk composite, gfx1201 guards. **`patch_dflash2_v0271_
  backport` is OBSOLETE_DELETE: "v0.28 owns DFlash2 natively" [109]** —
  the 0.27.1-era DFlash source-copy backport (what made the R2 base's
  dflash work) is gone; 0.30's DFlash is stock vLLM (L2.3).
- **Kernels/configs baked** [93]: libr4d 0.5.0 + extras patch compiled with
  the image's own hipcc (build asserts `r4d.__version__ == 0.5.0` and the
  `ar_oneshot_2rank_exact_nq` symbol); `radiance_mxfp4_fp8.so` (the native
  W4A8 MXFP4 GEMM hipcc kernel, import-verified at build); **16
  RDNA4-tuned block-FP8 GEMM config JSONs named
  `device_name=AMD_Radeon_R9700`** copied into vLLM's quantization config
  path (R1's "ZERO RDNA/Radeon config files in the v0.33 tree" gap is
  closed on THIS stack — the tuned-configs log line should NOT appear for
  the fp8 shapes it covers); mxfp4 AITER triton gemm table (gfx1250-table
  override, "the measured WMMA-16 configurations"); MoE configs (inert for
  our dense checkpoint); the amdsmi init-order fix (`radiance_amdsmi.pth` +
  module — the "GPU enumeration (amdsmi init order)" patch class from the
  0.9.3 docs [51], re-verified on 0.30); `rocm-bandwidth-test` binary
  (the backgrounded startup topology sweep).
- **What stays OUT of the image**: checkpoints (our /models), caches
  (compose mounts `/cache`; the image's entrypoint defaults the cache vars
  to `/root/.cache/…` + `/tmp/torchinductor` [94 L88-89] — see L3.1), and
  **chat templates** (the release stage copies only
  `radiance_platform_probe.py` / `radiance_preamble.py` /
  `radiance_entrypoint.sh` [93 L419-421]; the `qwen3.8-enhanced.jinja` /
  `qwen3.6-enhanced.jinja` files are repo-only, supplied by compose's
  `/work` ro mount "in a private override" [91][92]).
- **Release-stage toolchain kept**: g++/hipcc/Python.h stay in the image
  deliberately — "AITER JIT-compiles kernels on first use, inside this
  image" (the first-boot JIT cost remains; the 0.9.3-era `bake_aiter_core.
  py` pre-bake step of R2 L4.1 has NO 0.30 counterpart [93 L319-412]).
  Root FS writable, as on the 0.9.3 line (intrinsic to the AITER JIT).

### L1.3 — The repo-pin question: does the GGZ14 launcher work against 0.30?

**No — and that is the design, not a defect.** The qualified combination at
the 0.30 stack is **image `1.0.397` + this repo's own recipe** (the
`docker-compose.yml` baseline [92] + the `.env.example` knobs [91][113] +
the README serving-mode blocks [84 L149-196]). Grounds:

- **The GGZ14 launcher's value is its start-time machinery, all keyed to
  0.9.3/0.27.1**: the 23+6 patch prelude applies to the stilldeadcode image's
  vLLM 0.27.1 tree (the R2 [S] record); the 0.30 image's tree already
  carries magiccodingman's 35 overlays at different source anchors, and
  every patch "checks for source drift before writing" [93 L253] → the
  launcher's prelude would fail closed, not degrade gracefully.
- **The libr4d build key is incompatible**: R2's D11 baked libr4d
  `b9e42ab` + `r4d_radiance_extras_rx9.patch` (the TP=1 narrow-state GDN
  decode kernels). The 0.30 image builds libr4d **v0.5.0 @ `e8de4bc1` + its
  own `r4d_radiance_extras.patch`** (fused GDN spec-update kernel
  `r4d_gdn_fused_update_w4k128v128`, the TP2 `ar_oneshot_2rank_exact_nq`
  all-reduce epilogue, the FP8 QK/PV prefill legs, the dflash conv
  kernels) [94][88] and asserts that exact ABI at build. Substituting a
  `b9e42ab-rx9` build would replace the r4d.so the runtime modules
  (`radiance_gdn.py`, `radiance_r4d_attn.py`, …) are written against.
- **The KV calibration table is a 0.9.3-stack artifact**: the
  `kv-profiles.tsv` pins (R2 L2.4/L3.5: 6.09 GiB Shape A / 8.49 GiB Shape
  B, both on the `1x7551-32624` signature over the stilldeadcode image)
  measure the 0.27.1 engine's GDN-state + cudagraph + allocator story; they
  carry NO validity to the 0.30 stack (L2.4).
- **The launcher's fixed tail is superseded**: its `--chat-template
  qwen-fixed-v22.3.jinja` + `--override-generation-config
  '{"temperature":0.7,…}'` pair [R2 L2.4] is replaced by the compose
  baseline's checkpoint-native template + `--generation-config auto` +
  `--default-chat-template-kwargs={"reasoning_effort":"xhigh"}` [92]
  ("Qwen3.8 defaults to xhigh reasoning" — the native sampling story,
  not a measured override).
- **What the 0.30 image pairs with instead**: its own entrypoint seams
  (`RADIANCE_WEIGHT_QUANTIZATION`, `RADIANCE_SPECULATIVE_CONFIG`,
  `RADIANCE_COMPILATION_CONFIG`, `RADIANCE_KV_OFFLOADING_SIZE` — env
  JSONs appended to `"$@"` unless the explicit CLI flag wins [94 L182-252])
  + the compose command list [92]. The `IMAGE` env knob in the GGZ14
  scripts [47 L12] was the seam R2 hoped to exploit; the grounded answer is
  that the seam leads into a stack the launcher was not built to patch.
  **Record**: the R2 pin (Codeberg main @ `df0af7cf6b` + stilldeadcode:0.9.3)
  stays in the ticket record as the SUPERSEDED base (the runbook's
  recorded-alternatives section, D21), not as a build input.
- **One correction this pairing makes to R2's transcription** (L3.1):
  the R2 D15 pod-args law "the args list starts `vllm serve <model>`"
  transcribed the GGZ14 entrypoint usage; the 0.30 entrypoint `exec vllm
  serve "$@"` itself [94 L334], and the compose `command:` list starts with
  the model path, no `vllm serve` tokens [92]. Our pod args start with the
  model path.

### L1.4 — Issue #6 (HSA profiler idle spin) + the idle-CPU class

- **Current state [96]**: #6 OPEN (created 2026-09-07 by usaloCKLEnTO).
  After any completed GPU workload, one native CPU thread pins ~99.5% (the
  guide's wording) at idle; the reporter's two-worker deployment shows two
  cores busy, ≈ **31.5 W measured CPU-package** contribution. Repro: one
  visible GPU, no model, no vLLM server, no RCCL init — so **our single-
  R9700 pod is squarely in the affected class**. Attributed to the bundled
  ROCr 7.14 runtime (`libhsa-runtime64.so.1.21.0`, rocm-systems pin
  `2b22ab01…`), upstream symptom ROCm/TheRock#9256; reporter's affected
  image = digest `f728d19a…` (the 1.0.15-era build, 2026-09-02).
- **Documented workaround [96][97]**: `HSA_TOOLS_DISABLE_REGISTER=1` set
  **before process startup** (i.e. a pod env) "eliminates the idle spin in
  our tests"; ordinary vLLM metrics and GPU monitoring continue to work;
  HSA-profiling-hook-dependent tooling would need a separate diagnostic run.
  PR #19 (open, 2026-10-18, docs-only) states both #6 and #12 "document
  confirmations of an explicit `HSA_TOOLS_DISABLE_REGISTER=1` startup
  override, but the repository has no discoverable instructions for
  applying it" — i.e. the workaround is reporter-confirmed on this stack
  lineage but not yet in-repo documentation.
- **#12 (open, 2026-09-17)**: `VLLM::EngineCore` busy loop at 100% of one
  core — the second idle-CPU report; same override confirmation per PR #19.
- **Fix status [98]**: PR #42 (open DRAFT, 2026-10-19) — an experimental
  backport of three upstream ROCr 7.14 idle-spin/async-wake fixes into a
  separately selected experimental image (`Dockerfile.rocr-idle` over a
  digest-pinned Radiance image); CPU/build-qualified only, "the contributor
  has no R9700… **Do not promote the experimental runtime to a production
  default on this evidence**." No fix is in the pinned `1.0.397`.
- **Impact on our pod**: no functional impact (serving, metrics, GPU
  monitoring all unaffected per the reporter); the cost is one sustained
  busy core out of the pod's 4-CPU request class on a shared 32-CPU node +
  the package-power class above. **Mitigation recorded for the plan**:
  `HSA_TOOLS_DISABLE_REGISTER=1` in the pod env (new var vs R2's 9-var law —
  open R3-Q5). Watch line: PR #19 merge (docs) / PR #42 promotion (fix) →
  drop the var. Note: the same ROCm 7.14 userspace class sits under the
  R2 0.9.3 base too — the Q10 move is also an operational improvement on
  this axis (recorded, not measured: no 0.9.3 idle-CPU datum exists in the
  ticket record).

### L1.5 — Keeping the three stacks apart (the card's instruction)

| | stilldeadcode 0.9.3 (R2 base) | magiccodingman 0.30 (THIS pin) | capicua25x rdna4-rc13 |
|---|---|---|---|
| Engine | vLLM 0.27.1 @ `6e448d0e` [110] | vLLM **0.30.0 tag commit** `ced6857a` [84][99] | vLLM 0.28.0 [R2 L1.4] |
| State | DEPRECATED + frozen (live warning [57][58]) | MAINTAINED, release-line publishes (2026-10-18) [85][87] | Maintained fallback (2026-09-03 push) [62] |
| Checkpoint | amd Quark MXFP4 (via GGZ14 rewrite `Qwen3.8-27B-MXFP4-mtpfp8`) [R2 L2.3] | **amd Quark MXFP4 raw** (their qualified rev `156be69f` [108]; ours = main `93245f7c`, L2.6) + tcclaviger DFlash2-FP8 drafter | THEIR OWN quant pass `Capicua25x/Qwen3.8-27B-MXFP4-Quark-RDNA4` [68] — different excludes (231), different naming |
| Attention | R4D (libr4d b9e42ab-rx9 rebuilt by the launcher) [R2 L2.4] | R4D (libr4d 0.5.0 baked) + TRITON drafter [95][91] | stock TRITON_ATTN, no R4D [69] |
| Spec | dflash (patch-registered) / mtp | **native dflash (V2) / mtp** [104][105] | MTP-3 stock [R2 L1.4] |
| Role in this ticket | SUPERSEDED base (Q10) — runbook recorded-alternative | **THE ship base** | degraded fallback only (guide's one-flag-swap [46]) — unchanged |

## L2 — Engine facts at the 0.30 stack (re-grounding R2's 0.27.1 facts)

### L2.1 — v0.30.0 identity + what moved 0.27.1 → 0.30

- **The pin is the tag**: `ced6857afa…` = the `v0.30.0` git ref target
  (verified via the GitHub git-ref API; commit "[CI][Build] Harden triton-
  cpu sleef submodule fetch in CPU image build (#57871)", 2026-09-21; the
  release published 2026-09-22 [99]). stack.yaml's policy string reads
  "stable-release-plus-reviewed-focused-followups", but the pinned commit
  IS the tag — no follow-ups are in the image.
- **Release-class deltas that matter here [100]**: (a) **Model Runner V2**
  (graph-capture gc freeze: init 28.9 s → 8.2 s on H200; MTP + EAGLE3/
  DFlash/DSpark spec under V2; draft `attention_backend` + `moe_backend`
  overrides honored) — the 0.30 dflash/mtp lanes run V2 speculators
  [105]; (b) **native DFlash2** (owned since v0.28 — the 0.27.1 source-copy
  backport is obsolete [109]); (c) XGrammar 0.2.3 structured output in the
  qualified stack; (d) Mamba cache `all` deprecated
  (`align`/`none` remain — our `--mamba-cache-mode align` carries [101]);
  (e) stock ROCm images move to ROCm 10.0 (TheRock bump #55246) — Radiance
  DELIBERATELY retains the qualified ROCm 7.14 + AITER 0.1.20 pair (upstream
  uses AITER 0.1.21.post2 [91]).

### L2.2 — KV-cache dtype qualification (re-grounding R2 L3.1 for the Q5 gate)

- **The 0.30 `CacheDType` literal = 18 values** [101]: 0.27.1's 16
  (`auto, float16, bfloat16, fp8, fp8_e4m3, fp8_e5m2, fp8_inc, fp8_ds_mla,
  turboquant_{k8v4, 4bit_nc, k3v4_nc, 3bit_nc}, int4_per_token_head,
  int8_per_token_head, fp8_per_token_head, nvfp4` — re-fetched verbatim
  today) **plus `nvfp4_ds_mla` and `nvfp4_4over6`**. Mapping against R1's
  v0.33.0 table (24 values): 0.30 is missing the `octave_*` +
  `ultraquant_*` families that R1 found RDNA3-gated/dead-on-R9700 anyway —
  so nothing serviceable moved between 0.30 and 0.33 for this card; the
  int4/int8/fp8 per-token-head values are present in BOTH 0.27.1 and 0.30.
- **The 0.30 backend dtype gates** [102]:
  - `TRITON_ATTN`: `auto, float16, bfloat16, fp8, fp8_e4m3, fp8_e5m2,
    int4_per_token_head, int8_per_token_head, fp8_per_token_head`
    (kernel block sizes = multiples of 16).
  - `ROCM_ATTN`: the fp8 family + f16/bf16/auto only; supported head sizes
    up to 256 (the stock #60418-class economics remain a selector story,
    L2.5).
  - `ROCM_AITER_UNIFIED_ATTN`: the fp8 family + f16/bf16/auto only.
  - **`R4D` (the baked custom backend [95])**: `supported_kv_cache_dtypes =
    ["auto", "bfloat16", "fp8", "fp8_e4m3"]`; the kernel contract is
    "head_dim 256, paged block size 16, 6 query heads per KV head; causal
    decoder attention, bf16 query, bf16 or fp8_e4m3 KV cache; no sliding
    window, no sinks, no soft cap, no alibi, no per-(token,head) scales —
    everything else is refused at startup by `validate_configuration`,
    which prints the reason"; and, when requested by name, it "refuses to
    load" rather than fall back.
- **The qualified serving set at 0.30 = `fp8` (default — the compose
  baseline's literal `--kv-cache-dtype=fp8` [92]; "mandatory FP8 KV" [84]),
  `bf16`, `auto`** (the DOCKERHUB flags table: "fp8, bf16, or auto — fp8 =
  1 byte/elem (most KV capacity); bf16/auto keep full precision"; "bf16 /
  auto KV cache is supported" with the LDS-fit history [91]).
- **Q5 answer at 0.30**: `int4_per_token_head` gains NO qualification —
  the R4D gate above refuses it (per-(token,head) KV scales are an explicit
  refusal class), the AITER-unified fallback doesn't list it [102], and the
  maintainer's own 0.30 records run exclusively on fp8 KV. **The two-edit
  prerequisites carry VERBATIM** from R2 L3.1: (1) the `kvCacheDtype`
  values key → `--kv-cache-dtype int4_per_token_head`, (2) target attention
  off R4D → `--attention-backend TRITON_ATTN` (0.30-verified supported
  value [102]). The owner's on-target qualification gate (round-2 Q5 ruling)
  is unchanged in form; what changed is only the engine under it (0.27.1 →
  0.30, same CLI value, same TRITON leg).
- `--kv-cache-memory-bytes`: present at 0.30, **int bytes only, "when
  not-None ignores gpu_memory_utilization"** [101] — the same explicit-pool
  lever R2 grounded (R1's human-readable-values 0.33 addition is not in
  0.30; the plan keeps integer bytes).
- New at 0.30, adjacent: `--kv-offloading-size` (GiB, total across TP
  ranks) [101] + the entrypoint seam `RADIANCE_KV_OFFLOADING_SIZE` [94] +
  the four baked KV-offload overlays [109] — the 0.9.3-stack `KVCACHE=
  off|ram|disk` tier [R2 L1.1] is superseded by this stock+overlay surface.
  Default off; the one-engine-per-card law (Q7) is unaffected.

### L2.3 — Speculative decoding at 0.30 (re-grounding R2 L3.3 for the Q1 dflash default)

- **Method spellings**: `method: "mtp"` is the clean spelling; the full
  arch-specific set (`qwen3_5_mtp`, `qwen3_next_mtp`, `gemma4_mtp`, …) is
  ALREADY deprecated-and-normalizing at 0.30 ("method `%s` is deprecated and
  replaced with mtp", with a warning [104]). R2 L4.5 called this
  "engine-generation noise" against 0.27.1 — corrected: the alias set
  exists at 0.30 too (it has existed since the MTP generalization), so the
  0.30 recipe uses `mtp` and emits no arch-specific name.
- **`dflash` is NATIVE at 0.30**: `DFlashModelTypes = Literal["dflash"]`
  [104]; the model family `qwen3_dflash.py` (`DFlashQwen3ForCausalLM`,
  `DFlashQwen3Model` — block-diffusion, 5 layers, the drafter's own
  config) + the V2 speculators `DFlash2Speculator` (dflash2/) and
  `MTPSpeculator` (mtp/) [105]; auto-detection: a draft path containing
  "dflash" sets `method="dflash"` [104 L1319-1323]. **No patch-registered
  method anymore** (contrast R2 L2.2: the 0.27.1 fork's dflash was
  patch-registered [S L842]) — the runbook's metric-family uncertainty from
  R2 L4.5 (`spec_decode_*` vs `diffusion_*`) re-opens mildly: `dflash` now
  rides the stock V2 dflash2 speculator path, so the `spec_decode_*`
  counters are the expected family (recorded as expectation, on-target
  capture still the gate).
- **The 0.30 dflash lane requires the V2 runner**: `VLLM_USE_V2_MODEL_RUNNER=
  1` (compose knob; 0.30 default = V1 [92]) + `RADIANCE_COMPILATION_CONFIG=
  {"cudagraph_mode":"PIECEWISE"}` (the measured dflash graph mode [91]; the
  entrypoint appends it as `--compilation-config` unless the CLI wins [94]).
  R2's derived `cudagraph_capture_sizes` list (Shape A's `MAXSEQS*(SPEC+1)=
  64`) is NOT the 0.30 dflash form — the PIECEWISE mode replaces the
  capture-size list in the qualified lane (plan re-pin).
- **Drafter compatibility (Q1's 2 GiB drafter)**: `tcclaviger/
  Qwen3.8-27B-DFlash2-FP8` is the stack's OWN target-matched drafter for
  the Quark MXFP4 target — README: "For AMD's Quark MXFP4 target, use the
  target-matched tcclaviger/… drafter"; `.env.example`: "For
  amd/Qwen3.8-27B-Quark-AWQ-MXFP4, use the target-matched tcclaviger/…
  path in the same JSON instead" [84][91]. The QUALIFIED revision is
  `ee0cb26a8279b7910cc28d82a8a3e15e4728d56f` (2026-08-23, config SHA
  `5b5668a0…`, weight SHA `7dbb99a8…` [108][110]). Current main
  (`f02593d0`, 2026-09-25) is one commit ahead ("kv: calibrated fp8
  kv-cache scales for the draft attention layers" — the
  `model-kvscales.safetensors` sidecar); **the `model.safetensors` etag
  matches between the two revisions** (`7dbb99a8…`, verified by HEAD probe)
  and the `config.json` (incl. `dflash_config`: block_size 8,
  `target_layer_ids [5,19,33,47,61]`, selector_top_k 16) is byte-identical
  [106]. The drafter's native context is **262144** (`max_position_
  embeddings`) — it covers Shape B's 220000 target context natively
  (the "matched context" requirement, L2.4). **Staging pins the qualified
  revision `ee0cb26a`** (a NEW pin decision vs R2's plain main fetch;
  main is file-equivalent today, recorded).
- **The dflash JSON at 0.30 (TP1, Shape B constants)**: all keys native —
  `method`, `model`, `num_speculative_tokens` (7 = the K7 measured lane),
  `attention_backend: "TRITON_ATTN"` (the drafter's own stock attention
  [95][104]), `disable_padded_drafter_batch: true` [104],
  `max_model_len` (the draft context; their profile matches it to the
  target — open R3-Q3), `draft_tensor_parallel_size` (default 1 at TP1 —
  OMITTED; their TP2 profile sets 2 [104]), `draft_sample_method`
  ("greedy" default — explicit in the GGZ14 0.9.3 JSON, optional at 0.30
  [104]).
- **`RADIANCE_FAST_DRAFT=1`** (baked default 0 [86]) is part of the measured
  dflash/mtp lanes: the INT2-g128 exact-rerank draft head (+ W4 runtime
  quantization of eligible draft linears under dflash) [84][91]. The
  graph-cache isolation for fast-draft is automatic (the entrypoint's
  `-fast-draft` cache suffix [94 L82-85]) — R2's one-cache-per-config law
  carries structurally.
- **The MTP toggle (round-2 Q1's "mtp stays the values-key toggle")**:
  the 0.30 form is the .env example block: `RADIANCE_SPECULATIVE_CONFIG=
  {"method":"mtp","num_speculative_tokens":8,"attention_backend":"R4D",
  "disable_padded_drafter_batch":true}` + `RADIANCE_FAST_DRAFT=1` (+ L2.6's
  `RADIANCE_QUARK_BF16_MTP=1` for our raw release) [91]. Depth: the
  PUBLISHED measured MTP lane is **K4** (dynamic controller off, acceptance
  55.79% [108]); the `.env` example's K8 is "a ceiling under dynamic
  drafting" general guidance [84 L169-171] — open R3-Q4 (best guess: keep
  the documented toggle JSON at the measured K4). Note the MTP K4 lane's
  **tool gate FAIL** (29/30, L3.2) — the mtp toggle is not tool-qualified.
- **GDN-lazy law**: R2's `RADIANCE_GDN_LAZY=0` pod env (the multi-turn
  corruption law [S L305-309]) has NO 0.30 counterpart — the lazy-GDN
  feature was deliberately NOT ported into this stack ("Do not import lazy
  GDN; donor itself records multi-turn corruption" [89]). The corruption
  law is satisfied structurally; the var drops from the env set.
- **R4D at TP1**: `RADIANCE_USE_R4D_AR=1` (baked) is "exact TP2 P2P
  all-reduce, with safe RCCL fallback" [91] — at TP1 there is no collective;
  the verify-head story is TP2-full / TP1-approximate ("TP1's approximate
  shortlist remains experimental" [84]; `RADIANCE_VERIFY_HEAD_GLOBAL_TOPK=
  256` the experimental TP1 path, `RADIANCE_VERIFY_HEAD=0` the full head
  [91]) — recorded as a TP1 caveat, not a blocker (FAST_DRAFT default-off
  behavior keeps the full head when the toggle is off).

### L2.4 — Shape B at 0.30: what is stack-verified vs carried (Q2/Q3)

- **The 220000/2560/3 profile is a 0.9.3-stack shape**: the GGZ14
  `serve-tp1.sh` default over stilldeadcode:0.9.3 / vLLM 0.27.1, with the
  user-reported `kv-profiles.tsv` pin `9126805504` B (≈8.49 GiB) [48][49].
  **No 0.30-stack measurement exists at that shape — or at ANY TP1 shape**
  (the stack's qualified configurations are all TP2: the 8K/C8 publication
  [108], the capacity tables [84], the 128K/C4 production profile [91]).
  The owner's Q2 ruling ("the guide's re-measure gate stands") therefore
  binds HARDER at 0.30 than it did at R2: the plan ships Shape B constants
  (MAXLEN 220000 / CHUNK 2560 / MAXSEQS 3) as the PLAN shape, with the
  on-target re-measure as the envelope gate — and **without** an
  authoritative `--kv-cache-memory-bytes` pin (the 8.49 GiB number is
  recorded as carried-and-unverified, not shipped as the pool).
- **What the 0.30 stack contributes to the envelope**: its Quark-MXFP4
  capacity table (TP2, 90% allocation, APC off: 32K:C8..C11, 64K:C6..C7,
  128K:C4, 256K:C2; production 128K/C4 @ APC+align+DFlash-K7, 576,001 KV
  tokens, 5.17 GiB min headroom/GPU [84 L223-240]) is the calibration
  CLASS for the re-measure, not the TP1 constant. GPU_UTIL starting
  points on record: 0.85 (compose baseline default [92]), 0.90 (the 0.30
  Quark capacity allocation [84]), 0.98 (the 0.9.3 launcher's own ceiling
  record [S L422-425] — stack-specific, NOT carried). Open R3-Q2 (best
  guess: 0.90 — the 0.30-class allocation, then the on-target re-measure
  owns the final value).
- **CHUNK 2560**: no 0.30-stack constraint at TP1 — the R4D AR payload
  ceiling record ("48 MiB covers 4,096 × hidden-5,120 BF16" [92]) is a TP2
  all-reduce story; AR is inert at TP1. 2560 carries as the owner-ruling
  Shape-B constant; 4096 is the 0.30 compose default (recorded alternative).
- **MAXSEQS 3 / MAXLEN 220000**: carried owner constants; the 0.30 engine
  accepts them (no arch-level cap found; the drafter's native 262144
  context covers the draft side, L2.3).
- **The Q3 band**: unchanged by the base move — `--max-model-len 220000`
  engine cap vs catalog `limit.context 262144`; the 220000–262144 band is
  engine-capped (oversized sessions reject/preempt) and runbook-
  documented; the llama.cpp q8-1m rung keeps true long context [Q3 ruling].
- **KV bytes/token arithmetic**: the model is unchanged (head 256, 24q/4kv,
  GDN hybrid) — R1/R2's ~32 KiB/token fp8-KV class and ~16.4 KiB/token
  int4 class carry; the GDN-state side of the pool (align-mode mamba states)
  is engine-generation-sensitive → part of the re-measure, not an assumed
  constant.

### L2.5 — The flag surface the round-2 Q7 rulings assume (the 0.30 spot-check)

All verified at the `v0.30.0` tag (R2 commissioned this spot-check against
0.27.1 at C01; it is now done against 0.30):

| R2 Q7 ruling | 0.30 status (source-verified) |
|---|---|
| `--scheduling-policy priority` (CARRY) | **Exists** — `arg_utils.py` L1615 registration + `scheduling_policy` field L697 [103]. Carry stands. |
| `--watermark 0.05` (CARRY) | **Exists** — L1634 registration + L653 field [103]. Carry stands. |
| `--enable-sleep-mode` (DROP) | **Exists** — L952 registration (`ModelConfig.enable_sleep_mode`) [103]. The 0.30 stack does not qualify sleep (no 0.30 record runs it); drop stands — the flag is the documented re-enable surface. |
| `VLLM_SERVER_DEV_MODE` (DROP) | **Still referenced** in 0.30 (`cli_args.py` L177: `log_error_stack_trace = envs.VLLM_SERVER_DEV_MODE`) [103]. Drop stands (no dev-mode routes in the recipe; the sleep-mode drop that motivated it stands). |
| `--disable-access-log-for-endpoints /health,/metrics,/ping` (DROP) | **Exists at 0.30** — moved into the frontend-args module `vllm/entrypoints/launchers/cli_args.py` L283 (`FrontendArgs`) [103]. R2's C01 spot-check question is CLOSED: the flag exists; the drop is a choice, not a flag-surface gap. |
| `--attention-backend` | **Exists** — `arg_utils.py` L731 (`AttentionConfig.backend`) [103]. The value `R4D` is NOT in the stock `AttentionBackendEnum` — it is the custom backend the image's `patch_r4d` overlay registers into the pinned tree (the compose baseline pins it explicitly [92]); `TRITON_ATTN` / `ROCM_AITER_UNIFIED_ATTN` are stock values [102]. |
| TRITON_ATTN-pin non-carry (R2 D3) | **Still does NOT carry** for the same reason as R2: no reliance on the stock auto-selector. 0.30's stock ROCm priority = `ROCM_ATTN → ROCM_AITER_FA (if MHA enabled) → ROCM_AITER_UNIFIED_ATTN → TRITON_ATTN → TURBOQUANT` [102]; **#60418-class fixes are NOT in the v0.30.0 tag** (R1: merged 2026-11-03, after v0.30 and after v0.33.0rc3 — the 0.30 engine is the same generation as R2's 0.27.1 for that question). The target pins R4D by name (its own gate [95]); the int4 leg pins TRITON_ATTN by name (L2.2). `FLASH_ATTENTION_TRITON_AMD_ENABLE` is still the live RDNA gate in 0.30's `rocm.py` [102] — the OQ12 env carry (D17) remains a real surface at 0.30. |
| `--kv-cache-memory-bytes` | **Exists**, int bytes, "ignores gpu_memory_utilization" [101] — the explicit-pool lever carries (now UNPINNED pending the re-measure, L2.4). |
| `--mamba-cache-dtype` / `--mamba-ssm-cache-dtype` | **Exist** (L736/737, default `auto` [103][101]) — the 0.9.3 single-GPU profile's explicit bf16/fp16 GDN-cache flags are available but NOT in the 0.30 qualified lane (TP2 default dtypes); plan-optional for the TP1 envelope (recorded, not assumed). |
| `--limit-mm-per-prompt` (the D5 `image=4` carry) | **Exists** (dict form, L587 [103]) — carry stands (vision: the 0.30 records show "JSON/tool/recompute and two vision requests passed" for Quark [109] and "Text and vision both work" [91]). |
| Compose-baseline flags the 0.9.3 recipe lacked | `--generation-config auto` [103], `--default-chat-template-kwargs` [103], `--trust-remote-code` [103], `--kv-offloading-size` [101] — new recipe surface (L3.1). |

### L2.6 — The checkpoint at the 0.30 stack (Q8 re-grounding: raw release, rewrite skipped)

- **Target**: `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` — re-verified today: main
  sha `93245f7c00f1a8964b66a97c6e02e2fd09080be4`, lastModified
  2026-11-03T16:13Z, public/ungated, 42,689 downloads, 18.41 GiB single
  `model.safetensors` [R2 L2.1][107]. The 0.30 stack is qualified AGAINST
  this exact checkpoint family — but at the **pre-fix revision
  `156be69f`** ("Use own measured base thinking-mode GSM8K…", 2026-08-15;
  config SHA `04c9b07a…`), which BOTH the 0.9.3 continuation [110] and the
  0.30 publication [108] pinned.
- **What the pre-fix revision means**: its `quantization_config.exclude`
  carried the mtp tensors as tensor-names among module names (the R2
  L2.1 bug: Quark's module match never fired, mxfp4 scheme on a bf16 head,
  the shape-assert load death [45][54]). The 0.30 stack's answer to that
  class of checkpoint is baked: **`patch_quark_bf16_mtp.py`** [111] —
  "AMD's Qwen3.8-27B Quark MXFP4 checkpoint declares a global FP4 recipe,
  but its embedded `mtp.*` tensors are ordinary BF16 tensors and are not
  listed in the recipe's exclusions. vLLM therefore constructs packed Quark
  parameters for the MTP linears and later fails the weight-shape
  assertion while loading BF16 data. … Set `RADIANCE_QUARK_BF16_MTP=1`
  only after checking the checkpoint tensors. The target model remains
  Quark MXFP4/W4A8; only the small MTP submodule and its BF16 lm_head are
  constructed unquantized." Baked ENV default 0 [86][91]; the README:
  "The checkpoint's embedded MTP tensors are BF16. Add
  `RADIANCE_QUARK_BF16_MTP=1` **only when selecting its MTP profile.
  Non-spec and DFlash do not need that override.**" [84].
- **The publication proves the mechanism on THIS checkpoint**: the MTP K4
  lane loaded "target-contained BF16 MTP tensors" via V2 `MTPSpeculator` /
  `Qwen3_5MTP` at revision `156be69f` [108] — i.e. the 0.30 stack served
  the raw (un-rewritten) checkpoint's bf16 MTP head successfully; the
  `fp8_mtp.py` rewrite was never part of this stack (no reference to it
  anywhere in the repo; it is a GGZ14 0.27.1-sidecar artifact [111]).
- **Our raw-release pin (`93245f7c`, post the 2026-11-03 module-name fix)
  vs the qualified revision (`156be69f`)**: the 11-03 fix moved the mtp
  excludes to module names so the native Quark loader treats the MTP head
  as excluded-from-recipe (bf16) — strictly MORE loadable than the revision
  the stack was qualified on, which needed the env-gated patch. The plan:
  **dflash default (the shipped recipe): no `RADIANCE_QUARK_BF16_MTP` env
  (README: not needed)**; **mtp toggle: `RADIANCE_QUARK_BF16_MTP=1` + the
  mtp JSON** (the maintainer's documented line for this checkpoint; open
  R3-Q6). The Q8 contingency re-shapes from "re-land the rewrite" to:
  (a) if the mtp profile's bf16-head load fails on target → the env is
  already the documented first step (verify it is set), then (b) the
  rewrite re-land (the 0.27.1 tooling, recorded in the runbook as the
  further fallback, now two generations away from the shipped stack).
- **Drafter**: `tcclaviger/Qwen3.8-27B-DFlash2-FP8` at **revision
  `ee0cb26a`** (L2.3): weight etag `7dbb99a8…` = the 0.9.3 continuation's
  AND the 0.30 publication's weight SHA [110][108] — the drafter is the
  SAME artifact across both stacks; only the staging pin discipline is new
  (revision-pinned, not main-fetched).
- **The MXFP4 target env set** (`.env.example` Quark block [91], README
  target-formats block [84 L111-131]): `WEIGHT_QUANTIZATION=auto` (the
  entrypoint then omits `--quantization` entirely, letting vLLM consume the
  checkpoint's Quark metadata [94 L182-198]) + `RADIANCE_MXFP4=1` +
  `RADIANCE_MXFP4_W4A8=1` + `_W4A8_MIN_M=0` (KEEP 0: "the generic AITER
  W4A4 fallback is numerically incorrect for one of the qualified Qwen GDN
  projections" [84]) + `_DECODE_MAX_M=64` + `_TN4_MIN_M=2048` + the
  qualified RX5-safe decode subset `_WPERM=1` + `_DECODE_NT=1` (EPIFAST=1
  is baked [86]). The RX4/RX5 experimental tiers (NORMQUANT_FUSION,
  HOIST_QUANT, TRACED_QUANT, FP8_STREAM, GDN_NORM_QUANT, A_TILED) stay
  OFF — the entrypoint hard-gates their combinations and the publication
  used them off [94 L26-64][108].

## L3 — The bake + the tool-calling record + performance

### L3.1 — The overlay at the 0.30 base: what survives, what dies

R2 L4.1's bake (transcribed `Dockerfile.ggz14.top` against 0.9.3)
re-derives as follows for the 0.30 base:

- **Dies (already inside the pinned image)**: the 23+6 patch chain
  application [93][109]; the libr4d clone+build (b9e42ab-rx9 → **v0.5.0 +
  the image's own extras patch, baked [88][94]**); the two hipcc kernel
  builds (`radiance_mxfp4_fp8.so` — baked [93]; the ParoQuant one — inert
  for our checkpoint, and NOT in the 0.30 image at all: ParoQuant
  "partition rotations … Not imported; new checkpoint format outside this
  mission" [89]); the sitecustomize/registration steps (the .pth + hooks
  are baked [93]); the aiter-JIT pre-bake (`bake_aiter_core.py` — no 0.30
  counterpart; first-use AITER JIT remains a boot cost [93 L319-412]); the
  entrypoint install + `+x` fix (the image's own entrypoint [86]); the
  `qwen-fixed-v22.3.jinja` bake (the 0.30 default is the CHECKPOINT-NATIVE
  template; the enhanced jinja is a private-override mount [91][92]); the
  measured-profile ENV block (the image ENV carries the current flags
  [86] — the pod re-declares only what varies).
- **Survives (our repo's law, unchanged in form)**: a `containers/
  vllm-radiance-mxfp4/` dir (Q4-confirmed name) with a Dockerfile that is
  now **a thin re-export**: `FROM docker.io/magiccodingman/vllm-radiance:
  1.0.397@sha256:b73bf3e41bc0…` (+ the ledger README: tag→digest table,
  the source-commit `5b99d66c` record, the manual-bump procedure, the
  interface contract; optionally a baked `qwen3.8-enhanced.jinja` if the
  plan adopts the deployment-specific template — best guess: it does NOT,
  the native template + `--generation-config auto` is the 0.30 baseline).
  Build time: minutes (layer copy), not the hours-class full stack build
  [93]. The CI law is unchanged: `docker-build.yaml` changed-dir detection,
  first-build `:v<run>` + `:main` + PIN-ME, no docker daemon in agent
  sessions (cf-77: the registry probe + the tarball/OCI-label corroboration
  are the captured build-critical facts, L1.1).
- **Alternative form (recorded)**: no overlay dir at all — the chart
  references `docker.io/magiccodingman/vllm-radiance:1.0.397@sha256:…`
  directly (the R1 D7 analog: upstream image pin + ledger in the chart
  image comment + runbook step 10). Open R3-Q1 (best guess: keep the thin
  overlay — Q4 confirmed the dir/image name before Q10 invalidated its
  substance, the first-build `:v<run>` law wants an in-repo artifact to
  build, and pulling from docker.io on the cluster is the same wire either
  way; the ledger home stays unambiguous).
- **Pod-args correction (the R2 D15 law re-grounded)**: image Entrypoint
  = `/opt/radiance_entrypoint.sh` [86]; the entrypoint `exec vllm serve
  "$@"` [94 L334] — the pod `args` therefore START WITH THE MODEL PATH
  (the compose shape [92]), not with `vllm serve` (the R2 GGZ14
  transcription's prefix [R2 L2.4] would double the verb on this base).
- **Env re-declarations for the pod** (the image ENV defaults that the
  recipe must override [86][92]): `HIP_VISIBLE_DEVICES=0` (+ `ROCR_
  VISIBLE_DEVICES=0` — our chip-targeting law; the entrypoint's NUMA helper
  reads the HIP/ROCR/CUDA visible-device list [94 L263]); the four cache
  dirs → `/cache/{vllm,inductor,triton,aiter}` (the image defaults to
  `/root/.cache` + `/tmp` without them [94 L88-89] — the R2 D17 cache-law
  carries); `VLLM_USE_V2_MODEL_RUNNER=1` + `RADIANCE_FAST_DRAFT=1` + the
  Quark MXFP4 set (L2.6) — or the same via serveArgs/entrypoint seams
  (the plan's surface choice: explicit CLI where the compose does it
  explicit, env where the compose does it env); the HSA workaround var
  (L1.4, open R3-Q5); `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE` (OQ12
  carry — still a live 0.30 gate [102]); `HF_HUB_OFFLINE=1` (the serve pod
  loads two local directories; the R2 law carries).

### L3.2 — The 30/30 tool-calling correctness record (the Q6 marker's grounding)

**Exactly what it is** (from the 0.30 publication report [108] + the gate
source [112] + the fixtures [112]):

- **The gate**: "Required multi-tool schema, temperature 1" — 30 sampled
  live-server attempts per lane (`BENCH_TOOL_SCHEMA_ATTEMPTS` control [110])
  against the running server, each = a synthetic client-shaped wire
  regression: "never execute generated tools" [112].
- **The fixtures** (`benchmarks/fixtures/tool-schema-multitool.json` + the
  inline `package_probe` [112]): a 3-tool browser-style set
  (`click`/`keypress`/`assert`, each with typed required fields
  `reasoning`/`confidence`/`stepComplete` + per-tool keys/condition/ref);
  case `keypress_auto` (tool_choice=auto, parallel_tool_calls, two
  independent calls); case `keypress_parallel` (tool_choice=required, two
  calls); cases `package_auto`/`package_strict` — a .NET-Int64-exporter-
  shaped schema (`expectedVersion` nullable int with `maximum: 2**63` as a
  FLOAT) demanding typed nested objects, no JSON-stringified sub-objects.
- **The validation** [112]: exact tool names; exact argument equality
  (typed nested for the package); no unexpected fields; `finish_reason` ∈
  {stop, tool_calls}; no SSE error events; complete `[DONE]` stream.
- **The parser stack**: `--enable-auto-tool-choice --tool-call-parser=
  qwen3_coder --reasoning-parser=qwen3` (the compose baseline [92]; the
  `patch_qwen3_toolparse` overlay "required for Radiance tool-call
  qualification" [109]) + XGrammar 0.2.3 structured output + the
  checkpoint-native template + `--generation-config auto`.
- **What it measured, at which identities** [108]: the 0.30 stack (Radiance
  `1.1.0-rc1.vllm0.30.0`, vLLM `ced6857a` = the pin's engine, torch 2.12 /
  triton 3.7.1 / AITER 0.1.20 / libr4d 0.5.0), the **Quark MXFP4 target**
  (= our checkpoint family) at revision `156be69f` (pre-11-03-fix config),
  the tcclaviger DFlash2 drafter at `ee0cb26a` (the lanes that use it),
  FP8 KV, **TP2**, 8K context / C8, 85% allocation, R4D target attention +
  TRITON_ATTN draft attention, BetterBench v0.2.2 corpus v1, 2026-09-22,
  build source `487a62e82` (local `v030-publication-r2` image — the record
  predates the Docker-Hub `1.0.397` artifact by a source commit; every
  tool-relevant overlay is in both, and `1.0.397` ADDS the tool-grammar
  interoperability merge [114]).
- **The results** [108][84 L278-285]: non-spec **30/30 PASS**; DFlash2 K5
  **30/30 PASS**; DFlash2 K7 **30/30 PASS**; **MTP K4 29/30 FAIL** ("one
  unfinished tool JSON entered a whitespace loop and hit its 1,024-token
  limit … retained as experimental measurements, **not successful tool-
  serving qualification**. No gate was relaxed"). The stricter gate (fixed
  greedy outputs vs non-spec) passed only 1/8 for every spec lane (K5 vs K7
  6/8) — recorded, and the reason the spec modes stay "experimental /
  opt-in" [84 L13-14][108].

**The marker's honest grounding statement (for the approval presentation)**:
the tools marker on the three catalog rows rides on a record that is (a)
the 0.30 stack's OWN (not borrowed from 0.9.3 — Q6's consistency condition
is satisfied: "the 30/30 record is the 0.30 stack's" [DECISIONS Q6]); (b)
measured on the SAME checkpoint family + drafter we ship; (c) covering the
SHIPPED default mode (dflash K7: 30/30) and the non-spec fallback (30/30)
— but NOT the mtp toggle (29/30 = tool-gate FAIL class); and (d) measured at
**TP2, not our TP1** — the stack's docs say two GPUs "is the only
configuration tested so far" [91], so no TP1 tool datum exists. The
record is also a synthetic wire gate (typed schemas, stream reconstruction),
not a real-agent tool task. **Confidence: the marker is defensible for the
shipped dflash default + non-spec fallback (high, primary-source record,
strictly-newer tool path in the pinned image [114]); the mtp toggle carries
its 29/30 caveat into the runbook; the TP2→TP1 transfer is the marker's
standing risk — an on-target tool smoke (the keypress-fixture class against
the live pod, runbook step) is the closing gate, exactly as R2's int4 gate
is.**

### L3.3 — Performance: the 0.30 numbers and the TP1 comparison question

- **0.30 publication (TP2, FP8 KV, 8K/C8, 85%, 2026-09-22) [108]**:
  non-spec weighted 53.9 / c1 53.3 / c8 304.1; MTP K4 135.6 / 128.7 /
  463.9 (tool FAIL); DFlash K5 172.3 / 154.2 / **610.4 @ c8**; DFlash K7
  **186.7 / 173.5** / 446.6 / 510.2 (c1-c4 leader); per-request c1:
  non-spec 53.7 → K7 204.5; acceptance MTP 55.79% / K5 51.92% / K7 42.26%
  (DFlash accepted-plus-bonus 3.596/3.958 tokens per draft); prefill
  ~4,040–4,531 t/s (2K/4K/7K class); TTFT p50 ~64–67 ms.
- **The 0.9.3-stack class (record, two measurements) [110][45]**:
  magiccodingman's own 0.9.3/libr4d-0.5.0 continuation (TP2 BetterBench):
  non-spec 43.6 / MTP K4 102.3 / K5 136.2 / **K7 145.4 weighted; K7 c1
  132.4, c8 416.9**; and GGZ14's Shape-A 137.7 c1 / 416.3 c8 (0.27.1, the
  210 W cap, the guide's quoted numbers [45]). The two 0.9.3 measurements
  bracket each other (harness + profile differences) — not a conflict.
- **Same-topology delta (TP2, their two tables)**: 0.30 non-spec c1 53.3 vs
  0.9.3 43.2 (+23%); 0.30 DFlash K7 c1 173.5 vs 0.9.3 K7 c1 132.4 (+31%);
  c8: 0.30 K5 610.4 vs 0.9.3 K5 435.7 / K7 510.2 vs 416.9. The maintainers'
  own caution: "improvements are not uniform across concurrency … no
  causal 'v0.30 +X%' claim" [108] — different Radiance source/profile
  (the 0.9.3 table predates the WPERM/decode-NT safe subset + the V2
  runner).
- **Our pod (TP1)**: **no 0.30-stack TP1 number exists in any published
  form** (the qualification note: "Other geometries may work, but dual
  R9700 TP2 is the primary qualified environment" [90]). The 0.30 TP1
  story on record: the R4D attention/GDN paths run per-rank (TP2 all-reduce
  inert); the verify-head TP1 shortlist is "experimental" [84]; DFlash
  `draft_tensor_parallel_size` defaults to 1 (native field [104]). The
  plan therefore pre-registers the **0.9.3 TP1 class** (Shape-A 137.7/416
  — measured on the SAME card signature `1x7551-32624` [49]) as the ANCHOR
  CLASS for the runbook's step-6 benchmark, with the 0.30 TP1 dflash
  numbers as the ON-TARGET UNKNOWN (the owner's re-measure gate owns it,
  alongside the Shape B envelope). The 0.30 TP2 table serves as the
  cross-stack sanity class only ("same engine family, different topology").
- **Envelope numbers**: the 0.30 records' VRAM headroom (4.41–5.17 GiB
  minimum per GPU at their TP2 capacity profiles [84]) are TP2 classes; the
  TP1 Shape B envelope is the on-target re-measure (L2.4) — no carried
  constant.

## Contradictions and how to weigh them (R3 conflict map)

1. **The guide's "v0.28 → v0.30.0 per README" [46] vs the actual tag
   lineage.** The guide's string is the ENGINE version progression
   (docs/V028_UPGRADE.md → docs/V030_UPGRADE.md); the image tag line is
   `1.0.<pipeline>` (the release branch) with `sha-<commit>` twins. Weigh:
   pin the TAG + DIGEST + source commit (the OCI revision label), record
   the engine version as a ledger fact — the guide's string is a
   description, not a pin.
2. **"No production image was published or deployed; production remains
   stopped by standing instruction" [108] vs live Hub pushes
   `1.0.387`/`1.0.394`/`1.0.397` (09-23 / 10-09 / 10-18) [85].** Weigh:
   the publication report scopes its statement to the BENCHMARK SET (its
   `v030-publication-r2` candidate image, local-only) and to the
   maintainer's own standing deployment (the stopped "production 1.0.16"
   [109]); the GitLab release-branch pipeline [87] is what publishes the
   Hub line. The pinned `1.0.397` is a published, pullable, digest-stable
   artifact (registry probe L1.1) — the "stopped production" note is
   their-deployment context, recorded not blocking.
3. **The qualified checkpoint revision `156be69f` (pre-fix, config
   `04c9b07a`) vs our staging pin `93245f7c` (post the 2026-11-03
   module-name fix) [108][107].** Weigh: the 11-03 fix is strictly
   loadability-additive (mtp excludes become module-named → the native
   Quark loader treats the head as excluded/bf16; the 0.30 stack ALSO
   carries the env-gated bf16-MTP patch for the MTP profile [111][84]);
   the tool/perf records' lanes (non-spec, dflash) never exercise the MTP
   exclude path, and the MTP K4 lane ran the pre-fix revision successfully
   with the patch active. Risk direction: DOWN on load, unchanged on
   numerics for the shipped lanes. Stated assumption, not verified on
   target (the raw-release mtp-profile load is the Q8 on-target gate).
4. **`main` tip `1d2e248` (2026-10-18, repo pushed_at) vs the release pin
   `5b99d66c` (2026-10-17) [87].** The main tip is a test-only merge
   ("client-shaped-tool-regressions"); no image carries it (CI publishes
   the release branch only). Weigh: pin the release line (`1.0.397` /
   `sha-5b99d66c844f`); the watch = the next release-branch publish
   (new `1.0.<n>` + `sha-` pair), NOT main's movement.
5. **R2 D15's pod-args prefix (`vllm serve <model> …`) vs the 0.30
   entrypoint semantics [R2 L2.4] vs [94 L334][92].** The 0.30 entrypoint
   `exec vllm serve "$@"`; the compose command list starts with the model
   path. Weigh: the entrypoint + compose are the shipped pair — the pod
   args start with the model path; the R2 prefix was a transcription of
   the GGZ14 entrypoint usage and would double the verb on this base.
   (Corrected at L3.1, not a silent smooth-over.)
6. **The stack's "two GPUs (TP=2) is the only configuration tested so far"
   [91] vs our TP1 pod + the owner's Shape B ruling (Q2/Q10).** Weigh:
   the owner ruled the shape AND the base; the re-measure gate (Q2's
   standing condition) + the "other geometries may work, but … not the
   same qualification" note are both honored — the plan ships the TP1
   Shape B recipe as PLAN-verified / OWNER-gated, with every 0.30
   measurement recorded as TP2-class evidence, and the on-target
   re-measure + benchmark as the closing gates (no TP1 results guessed,
   L3.3).
7. **libr4d: the GGZ14 `b9e42ab-rx9` build key (R2 D11) vs the 0.30 image's
   baked v0.5.0 + extras [88][94].** Lineage resolves the tension:
   `b9e42ab` (2026-08-24, the GDN overflow-fix class) is the ancestor
   line of the v0.5.0 pin `e8de4bc1` (2026-08-25, + dflash kernels) — the
   NaN-guard fixes R2 called "load-bearing" are inside the 0.30 build;
   the rx9 TP=1 narrow-state GDN-decode additions have no 0.30 counterpart
   (the 0.30 GDN path is qualified at default dtypes, TP2 [108]; the
   single-GPU fp16-ssm trick is a 0.9.3-launcher invention [S L713-716]).
   Weigh: the build key question dissolves into "the base image is the
   build" — the D11 deviation drops; if the TP1 Shape B envelope later
   needs the fp16-ssm trick, it is a 0.30-unverified knob (recorded at
   L2.5), not a rebuild.
8. **The 30/30 tool record (TP2) vs the tools marker on rows that serve TP1
   (Q6).** Weigh: the owner's Q6 ruling explicitly tied the marker to
   "the 30/30 record is the 0.30 stack's" — the record IS the 0.30 stack's
   (L3.2), and it covers the shipped dflash default + the non-spec
   fallback; the TP2→TP1 transfer + the mtp-toggle 29/30 caveat are stated
   at the approval presentation with the on-target tool smoke as the
   closing gate (L3.2 confidence statement).

## Implications for the re-plan (what the base move changes vs the R2-grounded re-plan)

- **D11 INVERTS AGAIN** (second inversion in one ticket): from "the .top
  transcription + the rx9 deviation" to "the THIN digest-pinned re-export
  (or the no-overlay chart pin, open R3-Q1)". The C01 scope shrinks to:
  the dir + the one-line Dockerfile + the ledger README + the `vllm-rocm`
  retirement + the CI path swap (unchanged from R2).
- **The pin set (STATE.json `plan.replan.pin_set`)**: base image →
  `magiccodingman/vllm-radiance:1.0.397` @ `sha256:b73bf3e4…7313e0`
  (source commit `5b99d66c844f`, the OCI revision label) [84-87]; fork repo
  pin `df0af7cf6b` → RETIRED (record only); libr4d pin `b9e42ab` → RETIRED
  (baked 0.5.0 @ `e8de4bc1` [88]); checkpoint pin UNCHANGED (`93245f7c`,
  now staged RAW per Q8 with the `RADIANCE_QUARK_BF16_MTP` mtp-toggle
  record [107][111]); drafter pin GAINS a revision (`ee0cb26a`,
  file-equivalent to main today [106]).
- **D15 recipe re-grounds** on the compose baseline + the MXFP4/dflash
  blocks: args start with the model path (no `vllm serve` prefix, L3.1);
  the 0.30 flag set per L2.5 (Q7 carries/drops unchanged in substance, all
  flags verified at 0.30); the Quark target env set per L2.6; the dflash
  spec JSON per L2.3 (+ `VLLM_USE_V2_MODEL_RUNNER=1` + the PIECEWISE
  compilation config + `RADIANCE_FAST_DRAFT=1` — the three 0.30 dflash
  prerequisites the 0.9.3 recipe did not have); `--generation-config auto`
  + `--default-chat-template-kwargs reasoning_effort=xhigh` +
  `--trust-remote-code` replace the 0.9.3 `--override-generation-config`
  + `--chat-template` pair; the tool trio (`--enable-auto-tool-choice
  --tool-call-parser=qwen3_coder --reasoning-parser=qwen3`) carries (same
  values, now the compose baseline [92]).
- **D17 env law re-derives**: R2's 9-var set → the 0.30 set: device pins
  (`ROCR_VISIBLE_DEVICES=0`, `HIP_VISIBLE_DEVICES=0`), `HF_HUB_OFFLINE=1`,
  the four `/cache/*` re-declarations (the image defaults are
  `/root/.cache`+`/tmp` [94 L88-89]), `FLASH_ATTENTION_TRITON_AMD_ENABLE=
  TRUE` (OQ12, still a live gate [102]), the MXFP4 W4A8 set (7 vars, L2.6),
  `VLLM_USE_V2_MODEL_RUNNER=1`, `RADIANCE_FAST_DRAFT=1`,
  `HSA_TOOLS_DISABLE_REGISTER=1` (new, L1.4, open R3-Q5) — and DROPS
  `RADIANCE_GDN_LAZY=0` (feature absent from the stack [89]). The exact
  count is the plan's test-pinning surface; the entrypoint's combination
  gates (exit 64 on the retired/experimental var mixes [94 L10-64]) are
  the risk control.
- **D14 init container unchanged in form** (Q9): stages (a) the raw
  release @ `93245f7c` and (b) the drafter @ `ee0cb26a` — the sha-keyed
  marker now keys on BOTH shas; step (b)'s rewrite is absent (Q8).
- **D18 probe**: the 0.30 cold-cache boot class is the 0.9.3 FASTBOOT
  MINUS the GDN fp32 autotune ("that path is gone on this stack" [91])
  and with the V2 capture-gc-fasten class [100] — the compose's own
  `start_period: 1800s` (30 min) is the maintainer's generic budget [92];
  the re-plan's 40-min carry is the conservative envelope (plan re-checks
  against the recorded boot classes; on-target first-boot is the datum).
- **D20 invariants**: `limit.context` stays 262144 (Q3 — the base move
  does not touch it; the band note now cites the 0.30 engine cap
  220000); `appVersion` moves 0.27.1 → **0.30.0** (the re-plan D9 row's
  engine-generation fact, re-grounded); the tools marker (Q6) lands with
  the L3.2 confidence statement in the approval presentation; the
  capabilities input [text, image] carry is unchanged (vision: 0.30
  records "two vision requests passed" [109]).
- **D21 runbook**: the image constants block (tag/digest/source-commit +
  the tag↔commit law + the release-branch watch, L1.1); the DRY_RUN-analog
  capture (the pod's rendered args + the entrypoint banner + the `R4D
  report` [91] + the topology-sweep output [94] — the 0.30 startup marker
  set replaces R2's L4.5 marker list); the Shape B re-measure (L2.4 — now
  the 0.30 TP1 envelope: the engine-log triple + the optional
  `--kv-cache-memory-bytes` post-calibration, the 8.49 GiB recorded as
  carried-and-unverified); the int4 gate (L2.2 — the two 0.30 edits +
  acceptance + tool smoke under int4); the tool smoke (L3.2 — the
  keypress-fixture class against the live pod, closing the TP2→TP1
  transfer); the HSA workaround note + the #6/#12/#42 watch (L1.4); the
  recorded alternatives (the 0.9.3 + GGZ14 recipe = the SUPERSEDED base
  with its 137.7/416 record; capicua25x = the degraded fallback;
  stilldeadcode/radiance = out of scope, not OpenAI-shaped).
- **The Q7 "one-engine-per-card static coexistence law"**: unchanged (the
  0.30 KV-offload surface [L2.2] is the documented escape hatch, off by
  default).

## Open questions (no-questions-rule log — round 3, for coord → owner/plan)

- **R3-Q1 — Overlay or direct pin.** Question: does the ticket keep a
  `containers/vllm-radiance-mxfp4/` dir (the Q4-confirmed name) with a
  THIN digest-pinned re-export Dockerfile + ledger, or does the chart pin
  `docker.io/magiccodingman/vllm-radiance:1.0.397@sha256:…` directly (the
  R1 D7 form — the ledger home moves to the chart image comment + runbook
  step 10)? Best guess taken: **keep the thin overlay** (Q4 confirmed the
  dir/image name in round 2 — the owner has already ruled the surface;
  the first-build `:v<run>` + PIN-ME law wants an in-repo artifact; the
  CI changed-dir detection + the test_ac6 re-pin all assume the dir).
  Impact: C01's entire scope (a one-line Dockerfile vs none), the ledger
  home, the image-repo string the chart renders (`ghcr.io/ownyourio/…`
  vs `docker.io/…`).
- **R3-Q2 — The GPU_UTIL starting point for the 0.30 TP1 Shape B
  envelope.** Question: what `--gpu-memory-utilization` ships before the
  re-measure — 0.85 (the compose baseline default [92]), 0.90 (the 0.30
  Quark capacity allocation class [84]), or 0.98 (the 0.9.3 launcher's
  ceiling record — stack-specific, NOT verified at 0.30)? Best guess
  taken: **0.90** (the 0.30-class allocation; the 0.98 record is a 0.9.3
  artifact and the OOM boundary is engine-generation-specific).
  Impact: the C02 serveArgs constant + the re-measure target + the
  first-boot OOM-risk class (the startup probe is the backstop either way).
- **R3-Q3 — The dflash JSON's `max_model_len` (draft context).** Question:
  matched to the target (220000, the README's "matched context"
  requirement [84 L158]) or capped at their profile constant (8192 [91])?
  Best guess taken: **matched (220000)** — the requirement is textual
  ("V2 runner, PIECEWISE graphs, draft TP2, matched context, fast draft"),
  the drafter's native context is 262144 [106], and a capped draft context
  under a 220000 target is an untested combination; the on-target
  DRY_RUN-analog capture + first-serve smoke close it. Impact: the
  spec-config JSON constant (C02) + the draft-side VRAM story (re-measure).
- **R3-Q4 — The MTP toggle's depth.** Question: the documented
  `specMethod=mtp` JSON — `num_speculative_tokens` 4 (the only 0.30-
  MEASURED MTP depth, K4 [108]) or 8 (the .env example's dynamic-ceiling
  guidance [91])? Best guess taken: **4** (the measured lane; K8 is
  general opt-in guidance, unmeasured on this target; the MTP lane is
  already the 29/30 tool-FAIL class — its documented JSON should be the
  one with the record). Impact: the values-comment documented toggle JSON
  (C02), not the shipped default.
- **R3-Q5 — `HSA_TOOLS_DISABLE_REGISTER=1` in the pod env.** Question:
  adopt the reporter-documented idle-spin mitigation now (issue #6/#12,
  L1.4 — one core at ~100% idle + the ≈31.5 W/2-worker package class on a
  shared 32-CPU node), or ship without it and watch for the PR #19/#42
  resolution? Best guess taken: **adopt** (reporter-verified on this stack
  lineage; "ordinary vLLM metrics and GPU monitoring continue to work";
  single pinnable env; no maintenance surface of our own; the Grafana
  PodMonitor scrapes vLLM's `/metrics`, not HSA hooks). Impact: the D17
  env count + the test re-pin; a watch note in the runbook (drop the var
  when the upstream fix lands in a new pin).
- **R3-Q6 — `RADIANCE_QUARK_BF16_MTP` coupling.** Question: ship the env
  OFF with the dflash default and document the ON-flip inside the mtp-
  toggle record (the README's "only when selecting its MTP profile" [84]),
  or ship it ON always (belt-and-suspenders on the raw release's bf16
  head)? Best guess taken: **coupled to the specMethod toggle** (the
  maintainer's own wording; ON-always is an unqualified deviation from
  their baked default 0 [86]; the dflash/non-spec lanes are the shipped
  surface). Impact: the mtp-toggle documentation (C02 comment + C05
  runbook step), not the default recipe.

## Sources (R3)

All web sources accessed 2026-11-07 unless stamped. `[repo …]` cross-
references R1/R2/EXPLORE as in the prior rounds.

84. GitHub — `magiccodingman/vllm-radiance` repo + `README.md` @ main
    `1d2e248` (full tarball capture): Status "experimental" + "The primary
    qualified environment is two R9700s (TP2), native FP8 or AMD Quark
    MXFP4 target weights, and mandatory FP8 KV"; "The source platform is
    vLLM 0.30.0"; the component pin table (vLLM 0.30.0 @
    `ced6857afa…`, torch 2.12 @ `6bbd2602…`, triton 3.7.1 @
    `f0b55c07…`, AITER 0.1.20 @ `fc2e5d57…`, libr4d 0.5.0 @
    `e8de4bc1…`, ROCm 7.14); "This fork tracks and credits DeadCode's
    vllm-radiance and libr4d work … ggz14/radiance-vllm-mxfp4 … is the
    source of the native Quark MXFP4/W4A8 work and the RX3/RX4
    optimization series adapted here"; the Target-formats blocks (Quark:
    `WEIGHT_QUANTIZATION=auto` + the MXFP4 W4A8 env set incl.
    "The checkpoint's embedded MTP tensors are BF16. Add
    RADIANCE_QUARK_BF16_MTP=1 only when selecting its MTP profile.
    Non-spec and DFlash do not need that override"); the Serving-modes
    table (qualified non-spec / fast MTP / experimental DFlash2 "V2
    runner, PIECEWISE graphs, draft TP2, matched context, fast draft");
    the capacity tables (TP2 85% native-FP8 8K..256K; TP2 90% Quark
    32K:C8..256K:C2; "The recommended long-context deployment is 128K/C4 …
    DFlash K7"); the 2026-09-22 publication table (53.9/135.6/172.3/186.7
    weighted; "Non-spec and both DFlash lanes passed 30/30 sampled
    required-tool checks. MTP passed 29/30 … not successful tool-serving
    qualification. No gate was relaxed."); the historical 0.9.3/libr4d-
    0.5.0 table (43.6/102.3/136.2/145.4; K7 c1 132.4 / c8 416.9); "What is
    included" (libr4d 0.5.0 contents; "Spec-safe structured output:
    upstream XGrammar termination and reasoning-boundary fixes"); the
    Build section ("The published image is built entirely from pinned
    source commits"; "Do not independently bump PyTorch, Triton,
    torchvision, or vLLM"); "TP1's approximate shortlist remains
    experimental" — https://github.com/magiccodingman/vllm-radiance
    (README @ `1d2e24849c9d8441b9614acade5252c9937a2bbf`)
85. Docker Hub — `magiccodingman/vllm-radiance` tags API + repository API
    (34 tags; `latest`=`1.0`=`1.0.397`=`sha-5b99d66c844f` digest
    `sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0`,
    amd64/linux, 4,079,863,554 B, pushed 2026-10-18T06:35Z, active, last
    pulled 2026-11-07; sibling pairs `1.0.394`/`sha-d1535e95465d`
    @ `sha256:94adfd79…` 2026-10-09, `1.0.387`/`sha-1855cd8cdb3b`
    @ `sha256:c0e8f375…` 2026-09-23, `1.0.16`/`sha-f295b9ef51ad`
    @ `sha256:83a9dc02…` 2026-09-09; repo: pull_count 13,005, description
    "fork of StillDeadcode / vllm-radiance which is a custom vllm tuned
    for R9700 GPU's", last_updated 2026-10-18) —
    https://hub.docker.com/v2/repositories/magiccodingman/vllm-radiance/tags
86. Docker Hub registry — anonymous pull-scope token + `GET
    /v2/magiccodingman/vllm-radiance/manifests/1.0.397` = HTTP 200 (single-
    arch v2 manifest; sha256 of manifest bytes = `b73bf3e41bc0a1cf7aaa…` =
    the Hub digest; identical for the `sha-5b99d66c844f` tag; config
    digest `sha256:c8059c55…`) + config-blob fetch: `Entrypoint:
    ["/opt/radiance_entrypoint.sh"]`, no Cmd, User null (root),
    `RADIANCE_VERSION=1.0.397`, the baked RADIANCE_* flag set (USE_R4D=1,
    FAST_DRAFT=0, QUARK_BF16_MTP=0, MXFP4=0/W4A8=0/WPERM=0/DECODE_NT=0,
    DYNAMIC_DRAFT=1, DRAFT_TAU=0.28, VERIFY_HEAD=1, RUN_BWTEST=1, …),
    OCI label `org.opencontainers.image.revision =
    5b99d66c844fd0a54e4a7eb93b40a1ece009a53d` + `…version = 1.0.397` —
    https://registry-1.docker.io/v2/magiccodingman/vllm-radiance/manifests/1.0.397
87. GitHub — `magiccodingman/vllm-radiance` branches + commits + CI:
    `main` @ `1d2e24849c…` ("Merge branch 'test/client-shaped-tool-
    regressions' into 'main'", 2026-10-18T14:21Z), `release` @
    `5b99d66c844f…` ("Merge main into release: Qwen tool grammar
    interoperability", 2026-10-17T23:40Z, parents `d1535e95` [the
    release/1.0.394 line] + `1d9016bb` ["fix: guard Qwen tool grammar
    interoperability and modern fallback", 10-17]); `VERSION` file on main
    = `1.1.0-rc1.vllm0.30.0`; `.gitlab-ci.yml` publish rule
    (`$CI_COMMIT_BRANCH == "release"` only), tag scheme
    `VERSION=1.0.${CI_PIPELINE_IID}` → `1.0.397` = pipeline #397, four tags
    per build (`1.0.397` + `1.0` + `sha-<short>` + `latest`), OCI revision
    label from `CI_COMMIT_SHA` —
    https://github.com/magiccodingman/vllm-radiance/blob/main/.gitlab-ci.yml
88. Codeberg — `StillDeadcode/libr4d` history: tags `v0.4.0` + `v0.5.0`;
    main tip `a3e4833d` (2026-10-04, "Update README.md"); the pin line:
    `b9e42ab` (2026-08-24, "[FIX] correct the exponent clamp rationale in
    gdn chunk_scan" — the GGZ14/R2 build key, post the 08-24
    "gdn: guard three exponent overflows on inactive lanes" merge
    `7d50e8a`), `fd221fd` (08-25 "[ADD] dflash kernels"), **`e8de4bc1`
    (08-25, "[ADD] remove dev scripts" = the v0.5.0 pin the 0.30 Dockerfile
    builds)** —
    https://codeberg.org/api/v1/repos/StillDeadcode/libr4d/commits
89. `docs/V030_GGZ14_MXFP4_NVFP4.md` @ main: "Donor:
    https://github.com/GGZ14/vllm-mxfp4 at 31b9a94a7f74eeb3f59e66d16b1b27dfafcd0663,
    resolved at mission start" (2026-09-22); the selective-delta table
    (NVFP4 E2M1 adapt; wider TP1 decode scratch imported; lazy GDN "Do
    not import … donor itself records multi-turn corruption"; TP3 dummy
    heads not imported; ParoQuant not imported); "The converter
    arithmetic originates with Brian … in GGZ14's 20652ec" —
    https://github.com/magiccodingman/vllm-radiance/blob/main/docs/V030_GGZ14_MXFP4_NVFP4.md
90. `.radiance/stack.yaml` + `upstreams.yaml` @ main: the component pins
    (three-way with [84]); the atomic group "rocm-compiler-stack … do not
    independently bump members"; the vllm policy "stable-release-plus-
    reviewed-focused-followups" (current_pin = the tag commit [99]);
    libr4d "build: source-plus-radiance-patch"; the upstream relationships
    (stilldeadcode-vllm-radiance = selective-adaptation/conceptual-watch,
    "Radiance 0.9.3 lineage documented in docs/RADIANCE_093_R4D050_MXFP4.md";
    ggz14 = selective-adaptation, last_audited_ref 31b9a94a) —
    https://github.com/magiccodingman/vllm-radiance/tree/main/.radiance
91. `DOCKERHUB.md` @ main (468 lines): the status banner + "stilldeadcode/
    vllm-radiance:0.9.3 is DeadCode's separate upstream release and the
    external comparison baseline"; the source-stack table; the "Current
    kernel and draft controls" table (RADIANCE_QUARK_BF16_MTP "load AMD's
    embedded BF16 MTP head outside the global Quark recipe"; VERIFY_HEAD
    "approximate TP1 target head, full-head TP2 guard"); the "Historical
    tested configurations" block ("KV cache: FP8 (bf16 / auto also
    supported)"; "two GPUs (TP=2) is the only configuration tested so
    far"; the bf16/auto-KV LDS-fit history); the flags table ("--attention-
    backend: R4D — current tuned target attention path; AITER remains a
    fallback/control"; "--kv-cache-dtype: fp8, bf16, or auto"; "--gpu-
    memory-utilization: 0.85 starting point"); the MTP opt-in two-liner +
    the DFlash2 complete matching profile (VLLM_USE_V2_MODEL_RUNNER=1,
    PIECEWISE, "For the AMD Quark target … use the target-matched
    tcclaviger/Qwen3.8-27B-DFlash2-FP8 drafter path. Stable vLLM 0.28.0
    contains native Qwen3.8 DFlash2"); "Tool-calling and reasoning:
    --enable-auto-tool-choice --tool-call-parser <parser> --reasoning-
    parser <parser>" + "The portable Compose intentionally uses each
    checkpoint's native chat template"; "First run is slower … that path
    is gone on this stack"; the compose example's device/GID note ("The
    image runs as root, so mapped devices do not require host-specific
    supplemental GIDs") —
    https://github.com/magiccodingman/vllm-radiance/blob/main/DOCKERHUB.md
92. `docker-compose.yml` + `.env.example` @ main: the baseline command
    (model path FIRST, no `vllm serve` tokens; `--served-model-name`,
    `--tensor-parallel-size 2`, `--max-num-seqs 8`, `--max-model-len
    16384`, `--gpu-memory-utilization 0.85`, `--max-num-batched-tokens
    4096`, `--kv-cache-dtype=fp8` LITERAL, `--attention-backend=R4D`,
    `--enable-prefix-caching --mamba-cache-mode=align`,
    `--no-async-scheduling`, `--enable-auto-tool-choice --tool-call-
    parser=qwen3_coder --reasoning-parser=qwen3`, `--generation-config=auto`,
    `--default-chat-template-kwargs={"reasoning_effort":"xhigh"}`,
    `--trust-remote-code`, 0.0.0.0:8000); the environment (HIP_VISIBLE_
    DEVICES=0,1; the VLLM_ROCM_USE_AITER=1 + UNIFIED_ATTENTION=1 +
    all-other-AITER-0 set; RADIANCE_USE_R4D=1/_GDN=1/_AR=1/_AR_QUANT=1;
    RADIANCE_MXFP4=0/W4A8=0 defaults; RADIANCE_QUARK_BF16_MTP=0; caches at
    /cache/{vllm,inductor,aiter}; VLLM_USE_V2_MODEL_RUNNER=0 default;
    healthcheck start_period 1800s; cap_add SYS_PTRACE+SYS_NICE; seccomp
    unconfined; ipc host; devices kfd+dri; the R4D AR payload-ceiling
    comment "R4D's measured chunked-prefill/MTP operating point … inside
    the exact TP2 all-reduce payload ceiling"); the .env.example blocks
    (the Quark target: WEIGHT_QUANTIZATION=auto + the MXFP4 W4A8 set +
    "the qualified RX5-safe decode subset … WPERM=1 … DECODE_NT=1"; the
    MTP block; the DFlash2 block with the matched-drafter note "For
    amd/Qwen3.8-27B-Quark-AWQ-MXFP4, use the target-matched tcclaviger/…
    path in the same JSON instead") —
    https://github.com/magiccodingman/vllm-radiance/blob/main/docker-compose.yml
93. `Dockerfile` @ main (423 lines): the four-stage source build (ROCm base
    `rocm/dev-ubuntu-24.04:7.14.0-full@sha256:439edaa8…` digest-pinned;
    builder compiles torch/triton/vision/aiter/vllm for gfx1201 with the
    stack ARGs; rocmprune; assemble installs wheels + transformers 5.15.0
    + xgrammar 0.2.3 + flydsl 0.3.1 + the 35-overlay patch loop (each
    "checks for source drift before writing") + the libr4d build (clone @
    `e8de4bc1` + `git apply r4d_radiance_extras.patch` + `GFX_ARCH=gfx1201
    ./build.sh` + the `r4d.__version__ == 0.5.0` +
    `ar_oneshot_2rank_exact_nq` assertion) + the `radiance_mxfp4_fp8.hip`
    kernel + `COPY fp8-configs/` (the 16 R9700-named JSONs) into
    site-packages + mxfp4/moe config tables + the amdsmi `.pth` fix; final
    = ubuntu:24.04 + venv + pruned ROCm + g++/hipcc/Python.h KEPT for
    first-use AITER JIT (with the JIT-probe build gate); release-stage
    ENV flag block (the [86] set); ENTRYPOINT `/opt/radiance_entrypoint.sh`
    with NO CMD; the chat-template jinja files NOT copied into the image —
    https://github.com/magiccodingman/vllm-radiance/blob/main/Dockerfile
94. `radiance_entrypoint.sh` @ main (334 lines): the startup gates (exit 64
    on the retired `RADIANCE_TOPK_TRITON_MIN_ROWS≠1`; the FP8_STREAM/NQF/
    A-TILED combination locks); the cache-suffix law (`-nogdnm`/`-nqft`/
    `-fp8s`/`-gnq`/`-fast-draft`; defaults `VLLM_CACHE_ROOT=
    ${VLLM_CACHE_ROOT:-/root/.cache/vllm}…` [L88-89]); the TunableOp
    off/collect/serve modes (off by default); the NUMA-bind consumption
    (reads HIP/ROCR/CUDA_VISIBLE_DEVICES [L263]); the compose-friendly
    seams — `RADIANCE_WEIGHT_QUANTIZATION` (`auto` = omit the CLI flag,
    "vLLM reads quantization_config from the checkpoint (required by Quark
    OCP MXFP4)"), `RADIANCE_SPECULATIVE_CONFIG`, `RADIANCE_COMPILATION_
    CONFIG`, `RADIANCE_KV_OFFLOADING_SIZE` (each: explicit CLI wins, WARN
    otherwise); the backgrounded `rocm-bandwidth-test` topology sweep
    (`RADIANCE_RUN_BWTEST=1` baked); the `radiance_preamble.py` banner;
    `exec vllm serve "$@"` —
    https://github.com/magiccodingman/vllm-radiance/blob/main/radiance_entrypoint.sh
95. `radiance_r4d_attn.py` + `patch_r4d.py` @ main: the R4D backend
    contract ("head_dim 256, paged block size 16, 6 query heads per KV
    head; causal decoder attention, bf16 query, bf16 or fp8_e4m3 KV cache;
    no sliding window, no attention sinks, no logits soft cap, no alibi,
    no per-(token,head) scales. Everything else is refused at startup by
    validate_configuration, which prints the reason and the constraint";
    "it cannot silently fall back: it was asked for by name on the command
    line, so it refuses to load"); `supported_kv_cache_dtypes =
    ["auto", "bfloat16", "fp8", "fp8_e4m3"]`; `_KV_DTYPE_NAMES`
    (auto→bf16, fp8→fp8_e4m3); `get_supported_kernel_block_sizes` = exactly
    16; the per-(token,head)-scale refusal (the int4/int8/fp8_per_token_
    head exclusion); patch_r4d: the GDN prologue + the "all fallbacks …
    decline, so the fallbacks — FLA/Triton for the gated delta net …
    exactly as they would in an image built without the library" record —
    https://github.com/magiccodingman/vllm-radiance/blob/main/radiance_r4d_attn.py
96. GitHub issue #6 @ magiccodingman/vllm-radiance (OPEN, created
    2026-09-07, usaloCKLEnTO): "After a tiny completed GPU workload, the
    unmodified published Radiance image leaves one native CPU thread
    continuously busy at idle on an AMD Radeon AI PRO R9700 (gfx1201). In
    our two-worker inference deployment this keeps two CPU cores busy,
    adding approximately 31.5 W of measured physical CPU-package power.
    Setting `HSA_TOOLS_DISABLE_REGISTER=1` before process startup
    eliminates the idle spin in our tests. This disables HSA tool/profiler
    registration; ordinary vLLM metrics and GPU monitoring continue to
    work." — repro with one visible GPU / no model / no server / no
    distributed init; the affected image digest `f728d19a…` (the 1.0.15-era
    tag); torch 2.12.0+rocm7.14; `libhsa-runtime64.so.1.21.0`; rocm-
    systems source pin `2b22ab01…`; upstream symptom ROCm/TheRock#9256 —
    https://github.com/magiccodingman/vllm-radiance/issues/6
97. GitHub PR #19 @ magiccodingman/vllm-radiance (OPEN, 2026-10-18,
    EmilienIT): "docs: document the opt-in ROCm idle CPU workaround" —
    "Refs #6 and #12. Both reports describe CPU threads staying busy after
    GPU work completes. They document confirmations of an explicit
    `HSA_TOOLS_DISABLE_REGISTER=1` startup override, but the repository
    has no discoverable instructions for applying it." + "The contributor
    has no R9700. … qualification remain NOT RUN." —
    https://github.com/magiccodingman/vllm-radiance/pull/19
98. GitHub PR #42 @ magiccodingman/vllm-radiance (OPEN DRAFT, 2026-10-19):
    "experiment: backport ROCr 7.14 idle-spin and async-wake fixes" —
    three upstream repairs (event ages keyed by compacted slot, unthrottled
    forced polling, a missed async-wake notification) imported into the
    bundled `libhsa-runtime64.so` via a separately selected experimental
    image (`Dockerfile.rocr-idle` over a digest-pinned Radiance image);
    CPU/build-qualified; "The pinned ROCm 7.14.0 image contains
    `libhsa-runtime64.so.1.21.0` built from `ROCm/rocm-systems@2b22ab01…`
    — the same runtime our pinned image carries"; "**Do not promote the
    experimental runtime to a production default on this evidence.**" —
    https://github.com/magiccodingman/vllm-radiance/pull/42
99. GitHub — vLLM `git/ref/tags/v0.30.0` resolves to commit
    `ced6857afa0ea7b2e3f0846a62e1394e90f15607` ("[CI][Build] Harden
    triton-cpu sleef submodule fetch in CPU image build (#57871)",
    2026-09-21T22:30Z) = the stack.yaml/README pin EXACTLY; the release
    feed shows `v0.30.0` published 2026-09-22 (between `v0.29.0` 2026-09-09
    and `v0.31.0` 2026-10-05) —
    https://api.github.com/repos/vllm-project/vllm/git/ref/tags/v0.30.0
100. vLLM **v0.30.0 release notes** (published 2026-09-22): Model Runner V2
     ("MTP (#46994) and EAGLE3/DFlash/DSpark (#50514) speculative
     decoding … gc frozen during graph capture, cutting capture from 12s to
     2s and engine init from 28.9s to 8.2s on H200"; "draft attention_
     backend overrides honored"); "Qwen DFlash context keys (#56431)";
     breaking: "the `all` Mamba cache mode deprecated (#55041)"; "ROCm:
     TheRock base bumped to ROCm 10.0 (#55246) … AITER 0.1.21.post2"
     (stock line — Radiance retains the qualified 7.14/0.1.20 pair [91]);
     "a clearer unsupported KV dtype error (#55236)" —
     https://github.com/vllm-project/vllm/releases/tag/v0.30.0
101. vLLM v0.30.0 @ tag — `vllm/config/cache.py`: `CacheDType` = the 18-
     value literal (0.27.1's 16 [70] + `nvfp4_ds_mla` + `nvfp4_4over6`);
     `kv_cache_memory_bytes: int | None` ("when not-None ignores
     gpu_memory_utilization"); NEW `kv_offloading_size: float | None` (GiB,
     "total buffer size summed across all TP ranks"); `MambaDType` =
     auto/f32/f16/bf16 (defaults auto); `MambaCacheMode` all/align/none
     (all deprecated) —
     https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/config/cache.py
102. vLLM v0.30.0 @ tag — the attention surface: `triton_attn.py`
     `supported_kv_cache_dtypes` = auto/float16/bfloat16/fp8/fp8_e4m3/
     fp8_e5m2/**int4_per_token_head**/int8_per_token_head/fp8_per_token_
     head (kernel block sizes = multiples of 16); `rocm_attn.py` = the fp8 family +
     f16/bf16/auto (supported head sizes up to 256; the native-C++ kernel's
     block 16/32 LDS constraint); `rocm_aiter_unified_attn.py` = fp8 family
     + f16/bf16/auto; `platforms/rocm.py` `_get_backend_priorities` =
     ROCM_ATTN → ROCM_AITER_FA (if MHA enabled) → ROCM_AITER_UNIFIED_ATTN
     → TRITON_ATTN → TURBOQUANT + the `FLASH_ATTENTION_TRITON_AMD_ENABLE=
     TRUE` RDNA gate — the raw fetches:
     https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/attention/backends/triton_attn.py
     (+ rocm_attn.py / rocm_aiter_unified_attn.py / platforms/rocm.py)
103. vLLM v0.30.0 @ tag — the CLI surface (`vllm/engine/arg_utils.py` +
     `vllm/entrypoints/launchers/cli_args.py`): `--scheduling-policy`
     (L1615) + `--watermark` (L1634) + `--enable-sleep-mode` (L952) +
     `--attention-backend` (L731) + `--limit-mm-per-prompt` (L587, dict
     form) + `--max-num-batched-tokens` (L556) + `--mamba-cache-dtype` /
     `--mamba-ssm-cache-dtype` / `--mamba-cache-mode` (L736-740) +
     `--kv-cache-memory-bytes` (L555) + `--speculative-config` (L665) +
     `--reasoning-parser` (L662) + `--compilation-config` (L701) +
     `--generation-config` (L723) + `--override-generation-config` (L727)
     + `--trust-remote-code` (L447) + `--async-scheduling` / `--no-async-
     scheduling` (L764) + `--served-model-name` (L439, str|list|None) +
     `--enforce-eager` (L584) + `--kv-cache-dtype` (L459); the frontend
     args: `--chat-template` (L80), `--default-chat-template-kwargs` (L93),
     `--enable-auto-tool-choice` (L105), `--tool-call-parser` (L111),
     `--tool-parser-plugin` (L116), `--disable-access-log-for-endpoints`
     (L283 — the flag MOVED into the frontend-args module at 0.30);
     `VLLM_SERVER_DEV_MODE` still referenced (L177 `log_error_stack_trace`)
     — the raw fetches:
     https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/engine/arg_utils.py
     (+ …/entrypoints/launchers/cli_args.py)
104. vLLM v0.30.0 @ tag — `vllm/config/speculative.py`: the
     `MTPModelTypes` literal (mimo_mtp … qwen3_next_mtp, qwen4_exp_mtp,
     qwen3_5_mtp, …, mtp, gemma4_mtp, …) with the deprecation block ("method
     `%s` is deprecated and replaced with mtp." → `self.method = "mtp"`,
     L1121-1125); `DFlashModelTypes = Literal["dflash"]` (L67) + the
     draft-path auto-detect ("dflash" in the draft model name → method
     dflash, L1319-1323); the spec-config fields `draft_tensor_parallel_
     size` (L395, default None→1), `max_model_len` (L419),
     `attention_backend` (L412), `disable_padded_drafter_batch` (L435),
     `draft_sample_method` (L588, default "greedy"); `VLLM_USE_V2_MODEL_
     RUNNER` env (vllm/envs.py L300) —
     https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/config/speculative.py
105. vLLM v0.30.0 @ tag — the native DFlash2/MTP V2 machinery:
     `vllm/model_executor/models/qwen3_dflash.py` (`DFlashQwen3ForCausalLM`
     L698, `DFlashQwen3Model` L360), `vllm/v1/worker/gpu/spec_decode/
     dflash2/speculator.py` (`DFlash2Speculator` L111), `vllm/v1/worker/
     gpu/spec_decode/mtp/speculator.py` (`MTPSpeculator` L12) — the v0.30.0
     source tree grep
106. HuggingFace — `tcclaviger/Qwen3.8-27B-DFlash2-FP8` commits/main (4
     commits: `ee931c92` initial 08-23; `4127e00c` upload folder 08-23;
     **`ee0cb26a` "Update README.md" 2026-08-23T12:21Z = the qualified
     revision [108][110]**; `f02593d0` "kv: calibrated fp8 kv-cache scales
     for the draft attention layers" 2026-09-25T18:40Z = current main sha
     `f02593d0ea2e3b7eedbb831fb26f465b1e6238bb`) + HEAD probes:
     `model.safetensors` etag `7dbb99a8…` IDENTICAL at `ee0cb26a` and main
     (the kvscales commit is additive-only) + `config.json` byte-identical
     (`architectures: [DFlash2DraftModel]`, `model_type qwen3`,
     `max_position_embeddings 262144`, hidden 5120, 32q/8kv, 5 layers, fp8
     e4m3 dynamic, `dflash_config` block_size 8 / selector_top_k 16 /
     target_layer_ids [5,19,33,47,61]) —
     https://huggingface.co/api/models/tcclaviger/Qwen3.8-27B-DFlash2-FP8/commits/main
107. HuggingFace — `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` commits/main (8
     commits, ids resolved today): `79b076fc` upload 08-15 → `87703029`
     license → `c6066412` README → **`156be69f` "Use own measured base
     thinking-mode GSM8K, recalculate recovery %" 2026-08-15T03:30Z = the
     revision BOTH qualified 0.30-lineage runs pinned [108][110]** →
     `56034359` "Fix: add 15 missing MTP tensors to quantization_config.
     exclude" 08-26 → `5233554c` "Fix: regenerate stale CRC32 manifest"
     08-26 → main `93245f7c` "Fix mtp exclude entries to use module names
     instead of parameter names (#4)" 2026-11-03T16:13Z (re-verified: sha /
     lastModified / public / ungated / 42,689 downloads) —
     https://huggingface.co/api/models/amd/Qwen3.8-27B-Quark-AWQ-MXFP4/commits/main
108. `docs/V030_PUBLICATION_20260922.md` @ main: status
     "PUBLICATION_SET_COMPLETE_WITH_MTP_TOOL_QUALIFICATION_FAILURE"; the
     identity block (runtime build source `487a62e82…`; the local
     `v030-publication-r2` image; Radiance 1.1.0-rc1.vllm0.30.0; the stack
     pins; target `/nvme/…/Qwen3.8-27B-Quark-AWQ-MXFP4-amd` revision
     `156be69f` + config SHA `04c9b07a…`; drafter revision `ee0cb26a` +
     config SHA `5b5668a0…`; the W4A8 + R4D binary SHAs); the BetterBench
     contract ("TP2, FP8 KV, 8,192 context, eight sequences, 4,096 batch
     tokens, 85% GPU allocation, prefix off/Mamba cache none, no async
     scheduling. WPERM/decode-NT on … Fresh per-mode compile caches"); the
     mode table (53.9 / 135.6 (tool FAIL) / 172.3 / 186.7 weighted; c1-c8;
     per-request medians; prefill 4,056.4 / 4,480.0 / 4,367.2 class); the
     acceptance table (MTP K4 55.79% over 100,840 proposed; DFlash K5
     51.92%; K7 42.26%; "exactly 7.0 proposals/draft" for K7); the gate
     table ("Required multi-tool schema, temperature 1": 30/30 / 29/30
     FAIL / 30/30 / 30/30; "Strict fixed output against non-spec": 1/8 all
     lanes, K5 vs K7 6/8); the MTP failure post-mortem (attempt 006:
     unfinished `click` JSON → whitespace loop → 1,024-token limit →
     `finish_reason=length`; "HTTP success alone did not pass the gate";
     "This blocks an all-modes/tool-qualified sign-off"); "MTP used V2
     MTPSpeculator / Qwen3_5MTP, target-contained BF16 MTP tensors and an
     INT2-g128 draft head with exact top-64 reranking. DFlash used V2
     DFlash2Speculator / DFlash2Qwen3ForCausalLM, TRITON_ATTN draft
     attention, the selective-FP8 checkpoint with eligible draft linears
     converted to W4"; "13 source/installed script-level gates PASS"; "All
     four lanes used vllm.v1.worker.gpu.model_runner.GPUModelRunner,
     PIECEWISE, R4D target attention and 304 eligible native W4A8 target
     layers per rank" —
     https://github.com/magiccodingman/vllm-radiance/blob/main/docs/V030_PUBLICATION_20260922.md
109. `docs/V030_UPGRADE.md` @ main: status "V030_CORE_QUALIFIED_WITH_
     OPTIONAL_SPECULATIVE_LIMITATIONS"; the qualification ledger ("resident
     FP8 and Quark MXFP4 gates … parser/structured output, vision and
     bounded performance sanity PASS"); the overlay migration matrix (45
     overlays; `patch_quark_bf16_mtp` RETAIN "Allow the qualified Quark
     checkpoint's BF16 MTP tensors only when explicitly selected";
     `patch_qwen3_toolparse` RETAIN "… required for Radiance tool-call
     qualification"; `patch_dflash2_v0271_backport` OBSOLETE_DELETE "v0.28
     owns DFlash2 natively"); the Quark resident gates ("JSON/tool/
     recompute and two vision requests passed"; "1600-token repeated prefix
     recorded 1568 cache-hit tokens with identical generated IDs"); the
     speculative compatibility ("One existing local FP8 MTP head was
     loaded with method=mtp, two speculative tokens … Both ranks reported
     actual V2 MTPSpeculator … 7 drafts, 14 proposed tokens and 9 accepted");
     the bounded performance table (Quark warm 48.2 [old 1.0.16] → 52.2
     [0.30] t/s, "No material decode regression … not a statistically
     powered speedup claim"); "Production 1.0.16 remains stopped"; the
     "GGZ14 donor frozen at 31b9a94a … from https://github.com/GGZ14/vllm-
     mxfp4 on 2026-09-22" —
     https://github.com/magiccodingman/vllm-radiance/blob/main/docs/V030_UPGRADE.md
110. `docs/RADIANCE_093_R4D050_MXFP4.md` @ main: "This continuation ports
     DeadCode Radiance 0.9.3 and libr4d v0.5.0 onto this fork's stable
     vLLM 0.27.1 and AMD compiler stack, incorporates the latest gfx1201
     MXFP4 work" (vLLM v0.27.1 @ `6e448d0e…`; the target = the amd Quark
     checkpoint, weight SHA `be1d745b…`, config SHA `04c9b07a…` = revision
     `156be69f` [107]; the drafter weight SHA `7dbb99a8…` [106]); the
     BetterBench tables (non-spec 43.6 / MTP K4 102.3 / DFlash K5 136.2 /
     K7 145.4 weighted; K7 c1 132.4 / c8 416.9; MTP K4 acceptance 59.1%);
     "The qwen3_coder required-union tool test passed 30/30 on the final
     K7 configuration with all required fields present"; the deployment
     recommendation ("Enable the MXFP4/W4A8 path only for a compatible
     Quark checkpoint … K7, draft TP2, TRITON_ATTN for the drafter, R4D
     for the target, PIECEWISE, disable_padded_drafter_batch:true,
     mandatory FP8 KV, RADIANCE_FAST_DRAFT=1") —
     https://github.com/magiccodingman/vllm-radiance/blob/main/docs/RADIANCE_093_R4D050_MXFP4.md
111. `patch_quark_bf16_mtp.py` @ main: the bf16-MTP load mechanism (the
     docstring quoted at L2.6: "its embedded mtp.* tensors are ordinary
     BF16 tensors and are not listed in the recipe's exclusions. vLLM
     therefore constructs packed Quark parameters for the MTP linears and
     later fails the weight-shape assertion while loading BF16 data. …
     Set RADIANCE_QUARK_BF16_MTP=1 only after checking the checkpoint
     tensors. The target model remains Quark MXFP4/W4A8; only the small
     MTP submodule and its BF16 lm_head are constructed unquantized.") —
     https://github.com/magiccodingman/vllm-radiance/blob/main/patch_quark_bf16_mtp.py
112. `benchmarks/bin/run_client_tool_gate.py` + `check_client_tool_gate.py`
     + `benchmarks/fixtures/tool-schema-multitool.json` @ main: the gate
     mechanics ("Synthetic client-shaped wire regressions; never execute
     generated tools"; the 3-tool fixture `click`/`keypress`/`assert` with
     the typed required fields; the cases `keypress_auto` [tool_choice=auto,
     parallel 2 calls], `keypress_parallel` [tool_choice=required],
     `package_auto`/`package_strict` [.NET Int64 `2**63` float-boundary
     schema, strict variants, typed nested equality, no JSON-stringified
     sub-objects]; the validation: exact names, exact/typed arguments, no
     unexpected fields, finish_reason ∈ {stop, tool_calls}, SSE-completeness;
     the CPU negative-control suite) —
     https://github.com/magiccodingman/vllm-radiance/tree/main/benchmarks/bin
113. `docs/QWEN_TOOL_GRAMMAR_COMPATIBILITY.md` @ main: the 0.30 /
     XGrammar-0.2.3 tool-grammar interop record (the skip-when-no-strict
     behavior; the float Int64-boundary repair; the Guidance legacy-
     fallback guard; the opt-in `RADIANCE_QWEN_AUTO_TOOL_GRAMMAR` /
     `RADIANCE_QWEN_INT64_BOUND_COMPAT` — both default off, "Publishing an
     image enables neither switch"; "The existing sampled tool-schema and
     open-object wire gates remain required before production
     qualification") — the merge that the pinned image's release commit
     carries [114] —
     https://github.com/magiccodingman/vllm-radiance/blob/main/docs/QWEN_TOOL_GRAMMAR_COMPATIBILITY.md
114. GitHub commit record: `5b99d66c844fd0a54e4a7eb93b40a1ece009a53d`
     "Merge main into release: Qwen tool grammar interoperability"
     (2026-10-17T23:40Z; parents `d1535e95` [release/1.0.394] +
     `1d9016bb` ["fix: guard Qwen tool grammar interoperability and modern
     fallback", 2026-10-17]) — the pin's source commit; `1d2e24849c` (main
     tip, 2026-10-18, "Merge branch 'test/client-shaped-tool-regressions'
     into 'main'") = the post-image test-only merge —
     https://api.github.com/repos/magiccodingman/vllm-radiance/commits
115. [repo] R2 above (this file, L711+) — the 0.9.3/GGZ14 groundings that
     Q10 supersedes (the pin set, the L2.4 transcription, the L3.5
     envelope, the L4.1 .top bake + rx9 deviation, the L4.5 STAY/DROP
     table, the issue-watch record [59][60][61])
116. [repo] R1 above (this file, lines 1–707) — the v0.33.0 dtype table
     (the 0.30 mapping reference, L2.2) + the #60418 merge record (L2.5)
117. [repo] `DECISIONS.md` (cf-131 folder) — the round-2 rulings Q1–Q10
     (the grounded-against set; Q10's verbatim ruling text)

## Reliability notes (R3 self-review)

- **High confidence (primary source @ exact ref, mutually consistent):**
  the pin target and its identity (four corroborating sources: the Hub tag
  API [85], the registry manifest + config probes [86], the CI tag↔commit
  law + branch tips [87], the image's own OCI revision label [86][114]);
  the stack composition (README table + DOCKERHUB table + stack.yaml,
  three-way agreement [84][90][91], plus the Dockerfile's build-time
  version assertions [93]); the v0.30.0 tag identity ([99] — the pinned
  commit IS the tag, no follow-ups); the 0.30 flag/dtype/spec/engine
  surface (tag raw fetches [101]-[105]); the R4D gate (the repo's own
  backend source [95]); the 30/30 record (the publication report [108] +
  the gate source + fixtures [112] + the 0.9.3-era sibling record [110]);
  the checkpoint/drafter revision states (HF API, ids resolved today
  [106][107], the drafter weight-etag identity across revisions [106]);
  the issue #6/#12 state + the documented workaround + the PR #19/#42
  status (GitHub, current [96]-[98]); the libr4d lineage (Codeberg history
  [88] + the Dockerfile's build assertion [93]); the entrypoint/args
  semantics (repo source + the image config blob [86][94][92]).
- **Medium confidence:** (a) the Shape B envelope at 0.30 TP1 — the
  constants are owner-ruled plan shape, NOT stack measurement (every 0.30
  datum is TP2 [84][91][108]); the on-target re-measure (owner Q2 gate)
  owns the truth; (b) the raw-release @ `93245f7c` load on this stack —
  the qualified revision is the PRE-fix `156be69f` [108][107]; the 11-03
  fix is loadability-additive and the MTP profile has the baked bf16
  patch [111], but no public run exists on the post-fix revision with this
  stack (stated assumption, L2.6; the on-target first-serve + the mtp-
  profile gate close it); (c) the `HSA_TOOLS_DISABLE_REGISTER=1` workaround
  persistence at `1.0.397` — the reporter's evidence is on the 1.0.15-era
  digest [96] with the same bundled ROCr runtime pin [98]; PR #19/#42
  confirm the issue pair on the current stack but neither is merged
  (on-target confirmation = a pod CPU-idle probe, runbook step); (d) the
  TP1 tool-calling behavior — the record is TP2-only [108][91].
- **Weakest claim:** "the 0.30 TP1 dflash performance is at least the
  0.9.3-class (137.7/416 anchor)" — UNSUPPORTED: no 0.30 TP1 measurement
  exists in any form; the 0.30 TP2 gains over their own 0.9.3 TP2 table
  [108][110] are topology-confounded against our TP1 pod. The plan must
  pre-register the 0.9.3 TP1 class as the ANCHOR CLASS and treat the 0.30
  TP1 numbers as the on-target unknown (L3.3).
- **Perspective weighting:** the magiccodingman repo at the pinned
  identity dominates (it is the measured artifact's own text + its
  published docs + its CI law); the publication report [108] is treated as
  the qualification of record for the tool/perf claims; the guide's
  Part 2.3 row [46] is claims-to-verify (all four of its cells verified:
  the digest-pinning rule [85][86], the engine lineage "v0.28 → v0.30.0"
  [84][99], "Qualified on 2× R9700 TP2" [84][91], "Known issue #6 …
  99.5% CPU" [96] — the last with the guide's 99.5% figure matching the
  issue's idle-spin description, the reporter's own measurement).
- **Blind spots (stated, not found):** no pull-and-import of the
  `1.0.397` image (registry manifest + config probes only — the cf-77 CI-
  primary law; the image itself is the artifact, not a rebuild input);
  no execution of the 0.30 recipe (the DRY_RUN-analog capture = the
  runbook's on-target step); the `benchmarks/results/20261008-pr8-11-
  production-qualification/` README referenced by the landing page [84]
  is NOT published in the GitHub mirror (the results tree lives on their
  private GitLab [109's artifact links]) — cited via the README pointer
  only; the 0.30 TP1 GDN-state dtype defaults (the publication ran TP2
  defaults [108]) — part of the re-measure, not assumed; the stilldeadcode
  0.9.3 image's idle-CPU behavior (the Q10 move is recorded as an
  operational improvement on the #6 axis, unmeasured on the old base).

---

# R4 — on-target ViT flash-attn crash + exact fix (2026-11-09)

Round-4 research commission for board card #131 (run
`cf-131-feat-vllm-fp8-official`), 2026-11-09, by `agent-research`.
Tightly-scoped: ONE code path, ONE fix. The on-target pod (the C02 shape,
the 0.30 image) crashed at the first multimodal request with:

```
File ".../vllm/model_executor/layers/attention/mm_encoder_attention.py", line 581, in _forward_fa
    output = vit_flash_attn_wrapper(
File ".../vllm/v1/attention/ops/vit_attn_wrappers.py", line 111, in vit_flash_attn_wrapper
    return torch.ops.vllm.flash_attn_maxseqlen_wrapper(
File ".../torch/_ops.py", line 1275, in __call__
File ".../vllm/v1/attention/ops/vit_attn_wrappers.py", line 62, in flash_attn_maxseqlen_wrapper
    output = flash_attn_varlen_func(
File ".../vllm/v1/attention/backends/fa_utils.py", line 59, in flash_attn_varlen_func
    raise ImportError(
ImportError: ROCm platform requires upstream flash-attn to be installed. Please install flash-attn first.
```

Owner on-target note (verbatim): *"magiccodingman's published image bakes
in upstream flash-attn (the ROCm port), which makes (2) importable and lets
the ViT use the FlashAttentionBackend. Our image (a thin re-export of the
same magiccodingman image) should also have flash-attn baked in — but the
on-target crash indicates that in our image either the Triton path is
preferred (head_dim 72 is in the supported set) or flash-attn is missing."*

Method: local clone of the vLLM `v0.30.0` tag (`git rev-parse HEAD` =
`ced6857afa0ea7b2e3f0846a62e1394e90f15607` — the pin's exact commit [99]),
read of the magiccodingman `release`-branch build (the pin's source branch,
`5b99d66c` [114]), live checkpoint `config.json`, and the repo's C02
surface. Every claim carries file + line + ref. Citation keys continue
R3's numbering at [118].

## TL;DR (5 lines)

1. **The exact fix: drop `FLASH_ATTENTION_TRITON_AMD_ENABLE: "TRUE"` from
   the pod env law** (charts/vllm/values.yaml:263 + the tests/vllm_testlib.py:187
   exact-set re-pin; 20-var → 19-var). In v0.30.0 that env var is the SOLE
   gate between the ViT's `FLASH_ATTN` path and the `TORCH_SDPA` fallback
   on RDNA (rocm.py L438, L765-777) — without it the ViT takes
   `TORCH_SDPA` → `F.scaled_dot_product_attention`, the exact path
   magiccodingman's own reference recipe runs (their compose never sets the
   var), and the flash-attn import is never touched. Values-only (C02
   surface); no image change, no engine-arg change.
2. **The owner's premise is refuted on both counts by the build source:**
   magiccodingman/vllm-radiance:1.0.397 does NOT bake upstream flash-attn —
   the release-branch Dockerfile builds torch with `USE_FLASH_ATTENTION=0`
   and has no flash-attn stage/install anywhere — and the reference 2×R9700
   box avoids the crash precisely because its recipe omits the env var
   (ViT = SDPA). "head_dim 72 in the supported set" is also refuted:
   `get_vit_attn_backend`'s `head_size` parameter is UNUSED in 0.30.0 —
   there is no head-dim gate in the ViT selection at all.
3. **The crash chain is line-exact against the tag** (pod trace
   581/111/62/59 == stock `v0.30.0` lines) — the 35 overlays do not touch
   the crash-path files. On gfx1201 the `FLASH_ATTN` ViT path's tail
   (fa_utils.py L52) requires `from flash_attn import
   flash_attn_varlen_func` — the upstream package, absent from the image
   (not in vLLM's ROCm requirements either) → stub raise at first ViT
   forward.
4. **Mechanism:** our D25 20-var env law carries `FLASH_ATTENTION_TRITON_
   AMD_ENABLE=TRUE` (the round-1 OQ12 owner ruling, carried verbatim R1→R2→
   R3) + the image's AITER 0.1.20 provides the Triton-AMD kernel spec →
   `flash_attn_triton_available()` True → ViT = `FLASH_ATTN` → first image
   request hits the stub. The var is read in EXACTLY ONE place in the
   v0.30.0 tree (rocm.py L438) — dropping it touches nothing but the ViT
   path (decoder R4D attention unaffected).
5. **Hardening variant (plan call, R4-Q1):** also pin
   `--mm-encoder-attn-backend TORCH_SDPA` in serveArgs — the 0.30 CLI flag
   (arg_utils L1399-1402) short-circuits the whole env/spec logic
   (rocm.py L741-747) and keeps the OQ12 "pin explicitly" posture in flag
   form. Rejected: installing flash-attn into the re-export (premise
   false; heavy build; stack-atomicity violation), and the
   `TRITON_ATTN` ViT pin (works, but not the stack's qualified vision
   path).

## R4.1 — The exact ViT attention backend selection logic (v0.30.0 @ ced6857a)

The ViT's per-block attention is `MMEncoderAttention` (CustomOp,
"Multi-headed attention without any cache, used for multimodal
encoder"). The Qwen3.5 ViT reaches it via
`Qwen3_5ForConditionalGeneration(Qwen3VLForConditionalGeneration)` (
qwen3_5.py L473) → `Qwen3_VisionBlock` (qwen3_vl.py L449, `self.attn =
Qwen2_5_VisionAttention(` L465) → `Qwen2_5_VisionAttention` (qwen2_5_vl.py
L393-398: `self.attn = MMEncoderAttention(num_heads=…,
head_size=self.hidden_size_per_attention_head, …)`). **The ViT head_dim is
72**, from the served checkpoint's `config.json` (live fetch,
`vision_config`: `hidden_size 1152`, `num_heads 16`, `depth 27` →
1152/16 = 72; `out_hidden_size 5120`) [129] — matching the R2 L3.2
"head_dim-72 ViT" record.

Selection happens ONCE per layer at model init (mm_encoder_attention.py
L353-356):

```
self.attn_backend = get_vit_attn_backend(head_size=head_size, dtype=dtype)
```

`get_vit_attn_backend` (vllm/model_executor/models/vision.py) first reads
the **override** `mm_cfg.mm_encoder_attn_backend` (set by the 0.30 CLI
flag `--mm-encoder-attn-backend`, arg_utils.py L1399-1402), then calls the
platform method. `RocmPlatform.get_supported_vit_attn_backends()` =
`[FLASH_ATTN, ROCM_AITER_FA, TRITON_ATTN, TORCH_SDPA]` (rocm.py L726-732).
`RocmPlatform.get_vit_attn_backend(head_size, dtype, backend=None)` (rocm.py
L734-777) — the EXACT selection logic:

1. **L741-747 — explicit override:** if `backend is not None`: assert it
   is in the four-backend supported list, log `Using backend {backend} for
   vit attention`, return it verbatim. (No availability check of any kind —
   whatever is named is what runs.)
2. **L753-755 — AITER MHA (CDNA only):**
   `rocm_aiter_ops.is_mha_enabled() and on_cdna()` → `ROCM_AITER_FA`
   ("Using AITER Flash Attention backend for ViT model."). **Never fires
   on our gfx1201** (RDNA, not CDNA).
3. **L757-763 — CDNA flash-attn:**
   `on_cdna() and find_spec("flash_attn") is not None and dtype ∈
   {float16, bfloat16}` → `FLASH_ATTN`. **Never fires on gfx1201.**
4. **L765-774 — RDNA "Flash Attention Triton" (OUR branch):**
   `on_gfx1x() and flash_attn_triton_available() and dtype ∈ {float16,
   bfloat16}` → `FLASH_ATTN`, log (L771-773):
   `"Using Flash Attention (Triton backend) for ViT model on RDNA."`
5. **L776-777 — fallback (THE REFERENCE BOX'S branch):** `TORCH_SDPA`, log
   `"Using Torch SDPA backend for ViT model."`

`flash_attn_triton_available()` (rocm.py L415-446, `@cache`) is the whole
RDNA gate:

- L417: `if not on_gfx1x(): return False` (gfx11xx/gfx12xx only — ours ✓);
- L433-436: the Triton-AMD kernels must be locatable —
  `find_spec("flash_attn.flash_attn_triton_amd")` (old flash-attn ROCm
  port layout) **OR**
  `find_spec("aiter.ops.triton._triton_kernels.flash_attn_triton_amd")`
  (the post-`3f94643` AITER layout);
- L438: `if os.environ.get("FLASH_ATTENTION_TRITON_AMD_ENABLE") != "TRUE":
  return False` (+ L439-442 info-once: `"Set
  FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE to enable Flash Attention Triton
  backend on RDNA."`);
- L444: `return True`.

**Answers to the commission's sub-questions:**

- **Is the Triton path selected by head_dim being in a supported set? NO.**
  The `head_size` parameter is accepted by `get_vit_attn_backend` and
  NEVER referenced in its body (L734-777). There is no head-dim "supported
  set" anywhere in the 0.30.0 ViT selection. head_dim 72 passes through
  unexamined. (The owner's hypothesis (2) is refuted at the source.)
- **What env var / condition controls the selection?** On RDNA:
  `FLASH_ATTENTION_TRITON_AMD_ENABLE == "TRUE"` (the exact string) AND the
  Triton-AMD kernel spec present AND the ViT dtype fp16/bf16 → `FLASH_ATTN`;
  otherwise the selection falls to `TORCH_SDPA`. The only reader of this
  env var in the entire v0.30.0 tree is rocm.py L438 (grep of `vllm/` +
  `docs/`: one reader, one log line).
- **Which forward runs per enum** (mm_encoder_attention.py; ROCm dispatches
  through `forward_cuda` because `RocmPlatform.device_type = "cuda"`,
  rocm.py L491; dispatch at L783, `elif self.is_flash_attn_backend:` at
  L795):
  - `FLASH_ATTN` / `ROCM_AITER_FA` → `is_flash_attn_backend = True`
    (L358-361) → `_forward_fa` (L559) → `output = vit_flash_attn_wrapper(
    …, is_rocm_aiter=(self.attn_backend == ROCM_AITER_FA), …)` (L581).
  - `TRITON_ATTN` → `_forward_triton` (L596) → `vit_triton_attn_wrapper`
    (L618) → `context_attention_fwd` (triton_prefill_attention.py L217) —
    pure Triton prefill kernel, NO flash-attn import, no head-dim gate.
  - `TORCH_SDPA` → `_forward_sdpa` (L530) → `vit_torch_sdpa_wrapper`
    (L547) → `torch_sdpa_wrapper` → `F.scaled_dot_product_attention` —
    no flash-attn import; handles head_dim 72 without restriction.

**The FLASH_ATTN tail (where the crash lives):** `vit_flash_attn_wrapper`
(vit_attn_wrappers.py L100) → `torch.ops.vllm.flash_attn_maxseqlen_wrapper`
(L111) → `flash_attn_maxseqlen_wrapper` (L27): `is_rocm_aiter=False` (our
case — the backend is `FLASH_ATTN`, not `ROCM_AITER_FA`) → L44 `from
vllm.v1.attention.backends.fa_utils import flash_attn_varlen_func` →
L62 `output = flash_attn_varlen_func(…)`. `fa_utils.py` resolves that
symbol AT MODULE IMPORT TIME (L38-62, the `current_platform.is_rocm()`
branch): L43 `from vllm.platforms.rocm import on_gfx1250`; L46-54 `try:` —
L47-50 if `on_gfx1250()`: `from aiter.ops.triton.mha import
flash_attn_varlen_func`; **L51-52 else (our gfx1201): `from flash_attn
import flash_attn_varlen_func`** — the UPSTREAM flash-attn package; L54
`_ROCM_FLASH_ATTN_AVAILABLE = True`; L55-62 `except ImportError:` —
installs a stub `flash_attn_varlen_func(*args, **kwargs)` that at first
call raises **L59-61: `ImportError("ROCm platform requires upstream
{package} to be installed. Please install {package} first.")`** with
`package = "flash-attn"` (L58) — the pod's exact message. The
`is_flash_attn_varlen_func_available()` helper (L342+) reports
`_ROCM_FLASH_ATTN_AVAILABLE` — False in our image.

## R4.2 — The magiccodingman/vllm-radiance:1.0.397 image: no flash-attn (owner premise refuted)

The pin's source is the repo's `release` branch @ `5b99d66c` (R3 L1.1,
pipeline #397 [87][114]); the read below is of that branch's
`Dockerfile` + `docker-compose.yml` (fetched 2026-11-09) [126][127]:

- **The 4-stage build has no flash-attn anywhere.** Stage 1 (builder)
  compiles, from source, exactly: torch (`ARG TORCH_COMMIT=6bbd2602…`,
  torch 2.12.0) with the explicit flag set
  **`USE_MAGMA=0 USE_MKLDNN=1 BUILD_TEST=0 USE_NCCL=1 USE_RCCL=1
  USE_FLASH_ATTENTION=0 USE_MEM_EFF_ATTENTION=0 USE_AOTRITON=0`** (the
  file's own comment: "AOTriton off: … vLLM never uses torch SDPA-flash"),
  AMD Triton 3.7.1, torchvision 0.27.1, AITER 0.1.20
  (`ARG AITER_COMMIT=fc2e5d57…`, `GPU_ARCHS=gfx1201 PREBUILD_KERNELS=0`),
  vLLM (`ARG VLLM_COMMIT=ced6857afa0ea7b2e3f0846a62e1394e90f15607`,
  `ARG VLLM_VERSION=0.30.0`), and rocm-bandwidth-test. Stage 3 (assemble)
  installs ONLY those wheels (`pip install --no-deps /wheels/{torch,
  triton,torchvision,aiter}.whl`; `pip install /wheels/vllm-*.whl
  "transformers==5.15.0" "xgrammar==0.2.3"`) plus `flydsl==0.3.1`,
  `/opt/rocm/share/amd_smi`, `pillow`, `pybind11`. **No flash-attn source
  build, no `pip install flash-attn`, no flash-attn wheel** — and
  upstream vLLM never lists it: `flash-attn` is absent from
  `requirements/rocm.txt` AND `requirements/common.txt` at the v0.30.0
  tag (grep: zero matches) [120]. It is an optional out-of-tree dependency
  on ROCm, and this stack deliberately does not carry it (torch itself is
  built with flash-attention integration OFF).
- **The image's own ENV (final stage) carries only the `RADIANCE_*`
  feature flags** (R3 [86]'s config-blob record) — no
  `FLASH_ATTENTION_TRITON_AMD_ENABLE`. So the var in the crashed pod came
  from OUR chart (charts/vllm/values.yaml:263), not the image.
- **Consequence for the owner's note:** "magiccodingman's published image
  bakes in upstream flash-attn" is FALSE at the build source; "our image
  … should also have flash-attn baked in" inherits the error (a thin
  re-export contains exactly the base's component set). The second
  horn — "flash-attn is missing" — is the true half of the note.
- **The AITER half of the gate IS present:** at the image's pinned AITER
  commit `fc2e5d57`, the package tree contains
  `aiter/ops/triton/_triton_kernels/flash_attn_triton_amd/` (GitHub
  directory listing at the pinned commit) [128] — so in our image
  `flash_attn_triton_available()`'s spec half is TRUE, and
  `FLASH_ATTENTION_TRITON_AMD_ENABLE` is the SOLE decider. (The on-target
  crash independently corroborates: it could only have occurred with BOTH
  the spec and the env var true.)

## R4.3 — How the reference 2×R9700 box avoids the crash

The repo's `docker-compose.yml` (release branch — the pin's source)
`environment:` block sets ~60 vars (the full `RADIANCE_*` set, the
`VLLM_ROCM_USE_AITER=1` + `_UNIFIED_ATTENTION=1` + all-other-AITER-0 set,
the cache dirs, `VLLM_USE_V2_MODEL_RUNNER`, …) [127] and **does NOT set
`FLASH_ATTENTION_TRITON_AMD_ENABLE`**. On that box:
`flash_attn_triton_available()` → False at rocm.py L438 → `get_vit_attn_
backend` falls to L776-777 → **`TORCH_SDPA`** → `F.scaled_dot_product_
attention`. The `flash_attn` import is never attempted, so the ABSENCE of
the flash-attn package is inert. Their 0.30 vision qualification
("JSON/tool/recompute and two vision requests passed" [109]; "Text and
vision both work" [91]) is therefore an **SDPA-path record** — the ViT
backend our pod SHOULD run. (The box would crash exactly like ours if
someone added the env var: no flash-attn in the image, same selection
logic.)

## R4.4 — The on-target crash, line-by-line against the tag

| pod trace frame | v0.30.0 @ ced6857a (local clone) | match |
|---|---|---|
| mm_encoder_attention.py L581 `_forward_fa`: `output = vit_flash_attn_wrapper(` | L581, identical | exact |
| vit_attn_wrappers.py L111 `vit_flash_attn_wrapper`: `return torch.ops.vllm.flash_attn_maxseqlen_wrapper(` | L111, identical | exact |
| vit_attn_wrappers.py L62 `flash_attn_maxseqlen_wrapper`: `output = flash_attn_varlen_func(` | L62, identical | exact |
| fa_utils.py L59 `flash_attn_varlen_func`: `raise ImportError(` | L59, identical (`"ROCm platform requires upstream flash-attn to be installed. Please install flash-attn first."`) | exact |

All four frames land on byte-identical stock lines → the image's 35
overlays do not touch these four crash-path files; the on-target tree
IS the tag for this code path. The full causal chain:

1. Pod env `FLASH_ATTENTION_TRITON_AMD_ENABLE: "TRUE"` — shipped by C02's
   20-var env law (charts/vllm/values.yaml:263, pinned at
   tests/vllm_testlib.py:187) — the round-1 **OQ12 owner ruling** ("set
   explicitly — override of the omit best-guess", DECISIONS.md L15),
   carried verbatim R2 (D7-rework L85, D17 L131) → R3 (final D25 L174:
   "OQ12 ViT var carry verbatim"; R3 L2.5: "still the live RDNA gate in
   0.30's rocm.py [102] — the OQ12 env carry stands").
2. gfx1201 + AITER 0.1.20 spec (R4.2) + env `TRUE` → `flash_attn_
   triton_available()` True (rocm.py L415-446).
3. ViT init (27 blocks, head_size 72, dtype bfloat16) → rocm.py L765-774 →
   `FLASH_ATTN` (log: `"Using Flash Attention (Triton backend) for ViT
   model on RDNA."`).
4. fa_utils module import (ROCm, not gfx1250) → L52 `from flash_attn
   import flash_attn_varlen_func` → ImportError → stub installed,
   `_ROCM_FLASH_ATTN_AVAILABLE = False` — silently, at import time.
5. **First multimodal request** → `forward_cuda` (L783) → L795
   `is_flash_attn_backend` → `_forward_fa` (L559→L581) → wrappers
   L111/L62 → stub L59 → the pod's exact ImportError. (Text-only requests
   never touch the ViT — hence "first multimodal request".)

## R4.5 — The exact fix

**(a) PRIMARY (recommended): drop `FLASH_ATTENTION_TRITON_AMD_ENABLE:
"TRUE"` from the pod env law.**

- Mechanism: `flash_attn_triton_available()` → False at rocm.py L438
  (info-once line `"Set FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE to enable
  Flash Attention Triton backend on RDNA."` appears in the startup log) →
  `get_vit_attn_backend` falls to L776-777 → **`TORCH_SDPA`** →
  `_forward_sdpa` → `F.scaled_dot_product_attention` (head_dim 72: no
  restriction; SDPA is the standard Qwen-VL-on-ROCm path). The flash-attn
  import is never attempted. Startup marker becomes `"Using Torch SDPA
  backend for ViT model."`.
- Scope: the var has ONE reader in the tree (rocm.py L438) — the change
  touches nothing but the ViT path; decoder R4D attention, the MXFP4 W4A8
  GEMMs, GDN, dflash — all unaffected. No image rebuild, no base re-pin,
  no engine-arg change.
- Ground: this is EXACTLY the state of the stack's own qualified 2×R9700
  recipe (R4.3) — i.e. the fix makes our pod's ViT path identical to the
  one that passed the 0.30 vision qualification.
- Surfaces (plan amendment, values-only): charts/vllm/values.yaml:263
  (delete the var + amend the comment) and tests/vllm_testlib.py:187
  (20-var exact set → 19) — the C02 surface; runbook C05's ViT-backend
  marker line changes from the OQ12 "Triton" observation to the SDPA log
  line, and the first-multimodal-request smoke (runbook step 3.4 class)
  becomes the crash-gate for this fix (must pass after the drop).
- Note: the OQ12 ruling was an explicit OWNER ruling; dropping the var is
  a formal reversal of it, now source-grounded (R4-Q1 carries it to the
  owner batch).

**(b) HARDENING (plan call, optional): also pin `--mm-encoder-attn-backend
TORCH_SDPA` in serveArgs.** The 0.30 CLI flag exists (arg_utils.py
L1399-1402); the override branch (rocm.py L741-747) short-circuits ALL
env/spec/CDNA logic and returns the named backend verbatim (it is in the
supported list, L726-732) — immune to any future env leak. This keeps the
OQ12 "pin the ViT backend explicitly" posture in FLAG form rather than
env form. Recommend ONLY if the owner wants the explicit pin; the minimal
stack-aligned state is (a) alone (the reference recipe sets neither).

**(c) Rejected — `--mm-encoder-attn-backend TRITON_ATTN` (the "force the
Triton path" option).** It would work mechanically: `_forward_triton`
(L596) → `vit_triton_attn_wrapper` (L618) → `context_attention_fwd`
(triton_prefill_attention.py L217) is a self-contained Triton prefill
kernel — no flash-attn import, no head-dim gate (the ViT selection has
none, R4.1; the kernel takes head_dim as a tensor dimension). But it is
NOT the path the 0.30 stack qualified vision on (their record is SDPA,
R4.3) — i.e. an unqualified numerics change for a performance gain the
ticket has not measured. Keep as the documented future performance
alternative (would need an on-target vision smoke first), not the fix.

**(d) Rejected — install upstream flash-attn (ROCm port) into the image.**
(i) The premise is refuted (R4.2): the base does not carry flash-attn, and
the reference box works fine without it — there is no "should also have
it" state to restore. (ii) It converts the thin digest-pinned re-export
(C01, minutes-scale layer copy, R3 L3.1) into a gfx1201 source build of a
heavy HIP extension — opposite of the owner-ruled D23 collapse. (iii) It
violates the stack's atomicity policy (stack.yaml: "Treat as a coordinated
compatibility stack; do not independently bump members" [90]) and the
image authors' deliberate `USE_FLASH_ATTENTION=0` torch build. (iv) It
would put the ViT on the `FLASH_ATTN` path — an UNqualified vision numerics
path for this stack (the qualification record is SDPA).

## Contradictions and how to weigh them (R4 conflict map)

1. **Owner note "the image bakes in upstream flash-attn (the ROCm port)"
   vs the release-branch Dockerfile.** The build source (the pin's own
   source branch, 4 stages, zero flash-attn stages, torch built with
   `USE_FLASH_ATTENTION=0`) + the reference
   recipe (no env var) + the vision-qualification record (SDPA path)
   outweigh the note. Most plausible provenance of the note: conflation
   with the SUPERSEDED 0.9.3 fork, whose DOCKERHUB/README record a "native
   head_dim-72 ViT flash kernel baked" (R2 L3.2 [45][51]) — that kernel is
   the stilldeadcode fork's OWN Triton ViT kernel (a different artifact,
   in a different image), not the upstream flash-attn package, and it is
   not in the 0.30 image. Weigh: source + box-recipe beat memory; the note
   is recorded as a misattribution, not an error to smooth over.
2. **Owner note "the Triton path is preferred (head_dim 72 is in the
   supported set)" vs the selection source.** `get_vit_attn_backend`
   never references `head_size` (R4.1) — there is no supported set, and
   head_dim 72 is the model's native ViT head dim, handled unconditionally
   by the SDPA and Triton paths. The crash is env-driven, not
   head-dim-driven. Weigh: the source is dispositive.
3. **R3's re-grounding ("FLASH_ATTENTION_TRITON_AMD_ENABLE is still the
   live RDNA gate in 0.30's rocm.py [102] — the OQ12 env carry (D17)
   remains a real surface at 0.30") vs R4.** Not a contradiction — a
   blind spot: R3 verified the GATE EXISTS at 0.30 (correct: rocm.py
   L415-446, L438) but did not trace the FLASH_ATTN path's TAIL
   (fa_utils.py L52's `from flash_attn import …`) against the 0.30 image's
   component set (no flash-attn). R1's L1.4 item 5 described the same
   selection correctly for v0.33.0 and offered the var as an "optional"
   carry without flagging the import requirement; the cross-generation
   check (R4.6) shows the tail is identical at v0.33.0 too — the var was
   never verified on any RDNA image in either generation. Weigh: recorded
   as the re-grounding gap that produced the on-target crash; the plan
   should treat "an env var that exists in the source" and "an env var
   whose downstream path is import-satisfied in the pinned image" as
   different verification classes.

## R4.6 — Cross-generation check (why the carry felt safe; v0.33.0 comparison)

Read of the `v0.33.0` tag (the R1 generation): `rocm.py`
`get_vit_attn_backend` + `flash_attn_triton_available` are
structurally IDENTICAL to 0.30.0 (same four branches, same
`FLASH_ATTENTION_TRITON_AMD_ENABLE == "TRUE"` gate, same "Using Flash
Attention (Triton backend) for ViT model on RDNA." log) [130], and
`fa_utils.py`'s ROCm branch is identical — including `from flash_attn
import flash_attn_varlen_func` + the same stub [130]. The official
`Dockerfile.rocm` at v0.33.0 also has no flash-attn build/install stage
[131]. Conclusion: on the v0.33.0 path the var would have selected the
SAME import-incomplete path — the OQ12 carry was never a verified-safe
state on either engine generation; it only "worked" while the pod served
text-only. (This also means: had the owner kept the R1 official-FP8
plan, the same var would have crashed the first vision request on the
v0.33.0 image too — the bug is in the carried var, not the base move.)

## Implications for the plan (C02/C05 amendment + D25/D17)

- **D25/D17 env law amendment:** the 20-var exact set loses
  `FLASH_ATTENTION_TRITON_AMD_ENABLE` (→ 19 vars). The values.yaml comment
  where L263 sits records the R4 ground in one line: "0.30's RDNA ViT
  FLASH_ATTN path requires the upstream flash-attn package this stack
  deliberately does not carry (Dockerfile `USE_FLASH_ATTENTION=0`, no
  flash-attn stage); the maintainer's own recipe runs the ViT on
  TORCH_SDPA — see RESEARCH R4."
- **C02 surface (values-only re-pin):** charts/vllm/values.yaml:263 delete
  + tests/vllm_testlib.py:187 exact-set re-pin (20→19). No other C02
  surface moves (serveArgs unchanged unless (b) is chosen; C03/C04
  untouched).
- **C05 runbook:** the step-3 ViT-backend marker line becomes
  `"Using Torch SDPA backend for ViT model."` (replacing the OQ12-
  observation leg); the first-multimodal smoke (step 3.4 class) is the
  crash-gate for the fix; the "recorded alternatives" section can carry
  (c) TRITON_ATTN-pin as the documented future performance option (with
  its smoke precondition) and (d) flash-attn install as the rejected
  heavy-build alternative.
- **Owner ruling dimension:** OQ12 was an explicit owner ruling ("set
  explicitly"); R4 (a) reverses it with the build-source ground, and
  (b) offers the flag-form preservation of the "pin explicitly" posture.
  Both go to the owner batch as R4-Q1 (no-questions rule) — the fix
  itself is the same either way (the var goes; the question is only
  whether the explicit pin re-lands as a serveArg).
- **Watch (no action this ticket):** if a future magiccodingman release
  adds a flash-attn build to the base, the var becomes re-evaluable — the
  runbook's recorded-alternatives line notes the condition.

## Open questions (no-questions-rule log — round 4, for coord → owner/plan)

- **R4-Q1 — Formal reversal of the OQ12 ruling: drop
  `FLASH_ATTENTION_TRITON_AMD_ENABLE` from the pod env (fix (a)), and do
  we also pin `--mm-encoder-attn-backend TORCH_SDPA` (fix (b))?** Best
  guess taken: **drop the var (YES — both owner-note horns refuted at the
  build source; the drop makes the pod's ViT path identical to the stack's
  own qualified 2×R9700 recipe); NO to the flag pin** (the reference
  recipe sets neither — the minimal state IS the qualified state; if the
  owner wants the "pin explicitly" posture preserved, (b) is the form).
  Impact: the 20-var→19-var exact set (values.yaml + testlib), the C05
  ViT marker line, and the D25/D17 amendment.
- **R4-Q2 (record, no action expected): SDPA ViT latency on the R9700
  has no datum in this ticket.** The 0.30 stack's vision record is
  correctness-only ("two vision requests passed"); if the owner ever cares
  about ViT prefill latency, the `TRITON_ATTN` ViT pin (fix (c)) is the
  performance alternative and needs its own on-target vision smoke —
  out of scope for this crash fix.

## Sources (R4)

All web/source reads accessed 2026-11-09; `[repo …]` cross-references
R1-R3, EXPLORE.md and the repo surfaces as in prior rounds. vLLM line
numbers are from a local clone of the `v0.30.0` tag (verified
`git rev-parse HEAD` = `ced6857afa0ea7b2e3f0846a62e1394e90f15607`) and
match the pod crash trace frame-for-frame (R4.4).

118. vLLM v0.30.0 @ ced6857a — `vllm/model_executor/layers/attention/mm_encoder_attention.py` — `MMEncoderAttention.__init__` L353-356 `self.attn_backend = get_vit_attn_backend(head_size=head_size, dtype=dtype)`; L358-361 `is_flash_attn_backend = attn_backend in {FLASH_ATTN, ROCM_AITER_FA}`; L372 selection log; L530/547 `_forward_sdpa` → `vit_torch_sdpa_wrapper`; L559 `def _forward_fa`, **L581** `output = vit_flash_attn_wrapper(`; L596/618 `_forward_triton` → `vit_triton_attn_wrapper`; L783 `def forward_cuda`, L795 `elif self.is_flash_attn_backend: return self._forward_fa(…)` — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/model_executor/layers/attention/mm_encoder_attention.py
119. vLLM v0.30.0 @ ced6857a — `vllm/platforms/rocm.py` — L491 `device_type: str = "cuda"`; L415-446 `flash_attn_triton_available()` (`@cache`; L417 `on_gfx1x()`; L433-436 `find_spec("flash_attn.flash_attn_triton_amd")` OR `find_spec("aiter.ops.triton._triton_kernels.flash_attn_triton_amd")`; **L438** `os.environ.get("FLASH_ATTENTION_TRITON_AMD_ENABLE") != "TRUE"` → False; L439-442 the info-once hint); L726-732 `get_supported_vit_attn_backends() = [FLASH_ATTN, ROCM_AITER_FA, TRITON_ATTN, TORCH_SDPA]`; L734-777 `get_vit_attn_backend(head_size, dtype, backend)` — L741-747 override (assert membership, return verbatim); L753-755 AITER-MHA → ROCM_AITER_FA (CDNA only); L757-763 CDNA `find_spec("flash_attn")` → FLASH_ATTN; L765-774 `on_gfx1x() and flash_attn_triton_available() and dtype∈{fp16,bf16}` → **FLASH_ATTN** ("Using Flash Attention (Triton backend) for ViT model on RDNA."); L776-777 fallback → TORCH_SDPA ("Using Torch SDPA backend for ViT model."); **`head_size` parameter unused in the body**; the ONLY tree reader of the env var — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/platforms/rocm.py
120. vLLM v0.30.0 @ ced6857a — `vllm/v1/attention/backends/fa_utils.py` — L38-62 module-import ROCm branch: L43 `on_gfx1250` import; L47-50 gfx1250 → `aiter.ops.triton.mha.flash_attn_varlen_func`; **L51-52 else (gfx1201): `from flash_attn import flash_attn_varlen_func`** (upstream package); L54 `_ROCM_FLASH_ATTN_AVAILABLE = True`; L55-62 `except ImportError` stub; **L58-61 stub raise: "ROCm platform requires upstream flash-attn to be installed. Please install flash-attn first."** (L59 = the pod frame); L342+ `is_flash_attn_varlen_func_available()`; ALSO `flash-attn` absent from `requirements/rocm.txt` + `requirements/common.txt` at the tag (grep: zero matches) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/attention/backends/fa_utils.py
121. vLLM v0.30.0 @ ced6857a — `vllm/v1/attention/ops/vit_attn_wrappers.py` — L27 `def flash_attn_maxseqlen_wrapper`; L40 aiter import (`is_rocm_aiter` branch); L44 `from vllm.v1.attention.backends.fa_utils import flash_attn_varlen_func`; **L62** `output = flash_attn_varlen_func(`; L100 `def vit_flash_attn_wrapper`; **L111** `return torch.ops.vllm.flash_attn_maxseqlen_wrapper(`; `triton_attn_wrapper` → `context_attention_fwd` (no flash-attn import); `torch_sdpa_wrapper` → `F.scaled_dot_product_attention` (no flash-attn import) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/attention/ops/vit_attn_wrappers.py
122. vLLM v0.30.0 @ ced6857a — `vllm/model_executor/models/vision.py` — `get_vit_attn_backend(head_size, dtype)` reads the override `mm_cfg.mm_encoder_attn_backend` → `current_platform.get_vit_attn_backend(head_size, dtype, backend=attn_backend_override)` — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/model_executor/models/vision.py
123. vLLM v0.30.0 @ ced6857a — the ViT construction chain: `vllm/model_executor/models/qwen3_5.py` L473 `class Qwen3_5ForConditionalGeneration(Qwen3VLForConditionalGeneration, IsHybrid)`; `vllm/model_executor/models/qwen3_vl.py` L449 `class Qwen3_VisionBlock`, L465 `self.attn = Qwen2_5_VisionAttention(`; `vllm/model_executor/models/qwen2_5_vl.py` L393-398 `self.attn = MMEncoderAttention(num_heads=…, head_size=self.hidden_size_per_attention_head, …)` — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/model_executor/models/qwen2_5_vl.py
124. vLLM v0.30.0 @ ced6857a — `vllm/v1/attention/ops/triton_prefill_attention.py` — L217 `def context_attention_fwd(` (the TRITON_ATTN ViT path's kernel; takes head_dim as a tensor dimension; no head-dim gate) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/attention/ops/triton_prefill_attention.py
125. vLLM v0.30.0 @ ced6857a — `vllm/engine/arg_utils.py` — L1399-1402 `multimodal_group.add_argument("--mm-encoder-attn-backend", …)` (the 0.30 override flag) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/engine/arg_utils.py
126. magiccodingman/vllm-radiance — `Dockerfile` @ `release` branch (the pin's source branch, `5b99d66c` [114]) — 4 stages; builder: torch 2.12.0 built with `USE_FLASH_ATTENTION=0` (+ `USE_MAGMA=0 USE_MKLDNN=1 BUILD_TEST=0 USE_NCCL=1 USE_RCCL=1 USE_MEM_EFF_ATTENTION=0 USE_AOTRITON=0`), triton 3.7.1, torchvision 0.27.1, AITER 0.1.20 @ `fc2e5d57` (`GPU_ARCHS=gfx1201 PREBUILD_KERNELS=0`), vLLM `ARG VLLM_COMMIT=ced6857afa0ea7b2e3f0846a62e1394e90f15607` / `ARG VLLM_VERSION=0.30.0`; assemble: `pip install --no-deps` the four wheels + `/wheels/vllm-*.whl` + `transformers==5.15.0` + `xgrammar==0.2.3` + `flydsl==0.3.1` + amdsmi + pillow + pybind11 — **no flash-attn stage/install anywhere**; final-stage ENV = RADIANCE_* flags only (no FLASH_ATTENTION_TRITON_AMD_ENABLE) — https://github.com/magiccodingman/vllm-radiance/blob/release/Dockerfile
127. magiccodingman/vllm-radiance — `docker-compose.yml` @ `release` branch — the reference 2×R9700 recipe: `environment:` ≈ 60 vars (RADIANCE_* set, `VLLM_ROCM_USE_AITER=1` + `_UNIFIED_ATTENTION=1` + all-other-AITER-0, caches, `VLLM_USE_V2_MODEL_RUNNER`, …) — **no `FLASH_ATTENTION_TRITON_AMD_ENABLE`** → the box's ViT takes the rocm.py L776-777 TORCH_SDPA fallback (R4.3) — https://github.com/magiccodingman/vllm-radiance/blob/release/docker-compose.yml
128. ROCm/aiter — `aiter/ops/triton/_triton_kernels/` directory listing @ the image's pinned AITER commit `fc2e5d57fb5b8ad8e7e23f7103071dde798ea618` — contains the `flash_attn_triton_amd/` subpackage → the spec half of `flash_attn_triton_available()` is TRUE in the pinned image (the env var is the sole decider) — https://api.github.com/repos/ROCm/aiter/contents/aiter/ops/triton/_triton_kernels?ref=fc2e5d57fb5b8ad8e7e23f7103071dde798ea618
129. Hugging Face — `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` `config.json` @ main (live fetch 2026-11-09) — `vision_config`: `hidden_size 1152`, `num_heads 16`, `depth 27`, `out_hidden_size 5120` → **ViT head_dim = 1152/16 = 72**, 27 attention blocks (matches R2 L2.1/L3.2 [65][45]) — https://huggingface.co/amd/Qwen3.8-27B-Quark-AWQ-MXFP4/resolve/main/config.json
130. vLLM **v0.33.0** @ tag — `vllm/platforms/rocm.py` + `vllm/v1/attention/backends/fa_utils.py` (cross-generation check, R4.6) — `get_vit_attn_backend` / `flash_attn_triton_available` structurally identical to 0.30.0 (same env gate L438-equivalent, same four branches, same log strings); fa_utils ROCm branch identical (same `from flash_attn import flash_attn_varlen_func` + same stub) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/vllm/platforms/rocm.py (+ …/v1/attention/backends/fa_utils.py)
131. vLLM **v0.33.0** @ tag — `docker/Dockerfile.rocm` (official ROCm image) — no flash-attn build/install stage (vLLM installs from the ROCm wheel set; flash-attn remains an out-of-tree optional) — https://raw.githubusercontent.com/vllm-project/vllm/v0.33.0/docker/Dockerfile.rocm
132. [repo] the on-target surface — `charts/vllm/values.yaml:263` `FLASH_ATTENTION_TRITON_AMD_ENABLE: "TRUE"` (C02 20-var env law, D25) + `charts/vllm/tests/vllm_testlib.py:187` (exact-set pin) + `DECISIONS.md` L15 (OQ12 ruling verbatim: "set explicitly — override of the omit best-guess"), L85/L131 (R2 D7-rework/D17 carries), L174 (final D25: "OQ12 ViT var carry verbatim") + R3 L2.5 (the "still the live RDNA gate at 0.30" re-grounding, the blind-spot record) — the fix's amendment targets

## Reliability notes (R4 self-review)

- **High confidence (source @ exact commit, mutually consistent):**
  the selection logic (rocm.py L415-446, L726-777 — read in the local
  clone of the tag, frame-for-frame matching the pod trace [118-121]);
  the import requirement at the FLASH_ATTN tail (fa_utils.py L51-62,
  including the exact error string) [120]; the image's absence of
  flash-attn (release-branch Dockerfile, the pin's own source — [126]
  plus the `flash-attn`-absent-from-requirements grep at the tag [120]);
  the reference recipe's absence of the env var ([127] — the box's crash-
  avoidance is therefore mechanical, not empirical); the ViT head_dim 72
  ([129] + the construction chain [123]); the single-reader fact for the
  env var (tree grep) [119]; the crash-line exactness (R4.4 table — the
  on-target tree for these files IS the tag).
- **Medium confidence:** (a) that AITER 0.1.20's `find_spec` resolves
  the triton-kernels subpackage AT RUNTIME in the image — grounded by the
  directory listing at the pinned commit [128] plus the on-target crash
  itself (which is only possible with spec-true AND env-true) — high in
  practice, recorded medium only because the runtime `find_spec` call was
  not executed here. (b) The v0.33.0 official image's runtime flash-attn
  state [130][131] — the Dockerfile shows no install stage, but the image
  was not unpacked (cf-77 law); the R4.6 conclusion (the OQ12 var was
  never verified-safe on either generation) holds either way, because the
  SELECTION is identical and the 0.30 tail's import requirement is
  established.
- **Weakest claim:** "the box's 0.30 vision qualification ran on the
  SDPA path" [109][91][127] — inferred from (env var absent) + (selection
  logic) + (no flash-attn in the image); the qualification report does not
  name the ViT backend. The inference is airtight given the two source
  facts (it is the ONLY reachable branch), but it is an inference from
  configuration, not a logged observation.
- **Perspective weighting:** the pinned-source reads dominate (they are
  the exact artifact); the owner note is treated as claims-to-verify and
  both of its load-bearing claims refuted at the source — recorded as a
  misattribution (R4 conflict #1), not smoothed.
- **Blind spot (stated, not found):** no execution of the pod's python
  (no GPU session) — the fix's proof is (i) the selection-logic read
  (deterministic given env/arch/dtype) and (ii) the on-target
  first-multimodal smoke after the env drop (the runbook crash-gate,
  C05); no public RDNA4 datum exists for SDPA-ViT latency vs the
  FLASH_ATTN-ViT path (R4-Q2).

## R4 verification addendum — independent re-verification (2026-11-09)

Independent re-verification of the R4 section above (already written
earlier on 2026-11-09 by a prior research pass on this same commission).
Method: fresh reads of the same pinned artifacts — the local clone of the
`v0.30.0` tag (`git rev-parse HEAD` re-verified today =
`ced6857afa0ea7b2e3f0846a62e1394e90f15607`), the local clone of the
magiccodingman `release` branch at the pin's source commit `5b99d66c844f`
(re-verified today), a live GitHub API listing of the AITER tree at the
pinned commit, the live checkpoint `config.json` (cached fetch), and this
branch's C02 repo surfaces. Every load-bearing R4 claim was re-checked
line-for-line; **no correction was needed**. Two new findings — V1
UPGRADES R4.3's weakest claim from inference to logged observation, V2
TIGHTENS R4.4's wording.

### Verified (re-checked 2026-11-09)

1. **Selection logic (R4.1)** — `rocm.py`: `flash_attn_triton_available()`
   L415-446 (`on_gfx1x()` L417; the two `find_spec` locations L433-436;
   env gate **L438** `!= "TRUE"` → False; info-once L439-442; `return
   True` L444); `get_supported_vit_attn_backends()` L726-732 =
   [FLASH_ATTN, ROCM_AITER_FA, TRITON_ATTN, TORCH_SDPA];
   `get_vit_attn_backend` L734-777 — override branch L741-747 (assert
   membership, return verbatim, no availability check), CDNA AITER-MHA,
   CDNA `find_spec("flash_attn")`, RDNA L765-774 → FLASH_ATTN ("Using
   Flash Attention (Triton backend) for ViT model on RDNA."), fallback
   L776-777 → TORCH_SDPA. **`head_size` is never referenced in the body**
   (re-grep: zero uses after the signature) — the "head_dim 72 supported
   set" hypothesis is refuted, re-confirmed.
2. **Single reader of the env var** — tree grep (`vllm/` + `docs/`): one
   reader (rocm.py L438); L440 is the log string, not a read. Re-confirmed.
3. **The crash tail, frame-for-frame (R4.4)** — `fa_utils.py`: L52
   `from flash_attn import flash_attn_varlen_func` (the non-gfx1250
   branch); stub L55-62, the raise at **L59** with the exact pod message
   (L58-61); `vit_attn_wrappers.py` L27/L44/**L62**/L100/**L111**;
   `mm_encoder_attention.py` L353/L358/L530/L547/**L559**/
   **L581**/L596/L618/L783/L795 — all four pod-trace frames land on
   byte-identical stock lines. Re-confirmed (line numbers re-grepped).
4. **The override surface (R4.1/fix (b))** — `vision.py` L85-117
   (`get_vit_attn_backend` reads `mm_cfg.mm_encoder_attn_backend` →
   `current_platform.get_vit_attn_backend(…, backend=override)`); the
   flag registration `arg_utils.py` L1399-1403. Re-confirmed.
5. **The TRITON_ATTN path is import-free (fix (c) ground)** —
   `triton_prefill_attention.py` L217 `context_attention_fwd(` (pure
   Triton kernel; head_dim a tensor dimension; no head-dim gate).
   Re-confirmed.
6. **The ViT construction chain + head_dim 72** — `qwen3_5.py` L473 →
   `qwen3_vl.py` L449/L465 → `qwen2_5_vl.py` L393; the live checkpoint
   `vision_config`: hidden 1152 / heads 16 / depth 27 / out 5120 →
   head_dim 72. Re-confirmed.
7. **The image has no flash-attn (R4.2, the core premise refutation)** —
   the release-branch `Dockerfile` @ `5b99d66c`: 4 stages (builder /
   rocmprune / assemble / final); NO flash-attn stage, NO `pip install
   flash-attn`, NO flash-attn wheel (every `flash` hit is DFlash or the
   torch flag); torch built with **`USE_FLASH_ATTENTION=0`**
   (+`USE_MEM_EFF_ATTENTION=0 USE_AOTRITON=0`); AITER @ `fc2e5d57`
   (`GPU_ARCHS=gfx1201 PREBUILD_KERNELS=0`); vLLM @ `ced6857a` /
   `VLLM_VERSION=0.30.0`; the assemble stage installs exactly: the four
   wheels `--no-deps`, the vllm wheel, `transformers==5.15.0
   xgrammar==0.2.3`, `flydsl==0.3.1`, amd_smi/pillow/pybind11. `flash-
   attn` absent from vLLM's `requirements/rocm.txt` AND `common.txt` at
   the tag (grep: zero matches). **Conclusion re-confirmed: the image —
   and therefore the thin re-export — does NOT carry upstream flash-
   attn. The base never had it; the re-export lost nothing, and the
   owner's "their image bakes in upstream flash-attn" premise is false at
   the build source.**
8. **The reference recipe omits the var (R4.3)** — release-branch
   `docker-compose.yml`: no `FLASH_ATTENTION_TRITON_AMD_ENABLE` (the
   AITER set is `VLLM_ROCM_USE_AITER=1` + `_UNIFIED_ATTENTION=1` +
   all-other-AITER-0). Repo-wide grep: the string appears ONLY in
   captured benchmark server logs (all of them the info-once "Set … to
   enable" lines — i.e. UNSET in every maintainer run); zero hits in any
   config surface (Dockerfile / compose / .env.example / docs) [135].
9. **The gate's spec half is TRUE in the pinned image (R4.2 last bullet)**
   — the AITER tree @ the pinned commit `fc2e5d57` contains
   `aiter/ops/triton/_triton_kernels/flash_attn_triton_amd/` (live
   GitHub API directory listing) → the env var is the SOLE decider.
   Re-confirmed.
10. **The repo surfaces the fix amends (R4.5)** — this branch:
    `charts/vllm/values.yaml:263` = `FLASH_ATTENTION_TRITON_AMD_ENABLE:
    "TRUE"` (with the OQ12 comment); `charts/vllm/tests/vllm_testlib.py`
    `env_want_cf131` = the 20-var exact set INCLUDING the var (L187) —
    the drop is 20→19. Re-confirmed on the current tree.
11. **Cross-generation (R4.6)** — v0.33.0 `rocm.py` + `fa_utils.py`
    (cached reads): `get_vit_attn_backend` structurally identical (the
    AITER-MHA branch gains a dtype check — immaterial on RDNA), same env
    gate, same four branches, same log strings; the fa_utils ROCm branch
    is identical (`from flash_attn import …` + the same stub). Conclusion
    stands.

### New finding V1 — the reference box's SDPA ViT is LOGGED, not inferred

The radiance repo commits its 0.30-publication benchmark logs under
`benchmarks/results/20260922-v030-publication/`. In ALL FOUR runs
(non-spec, dflash-k5, dflash-k7, mtp-k4 — the 2×R9700 TP2 box,
2026-09-22, the same vLLM 0.30.0 the pin builds), the worker log records
at model load [133]:

```
[rocm.py:443] Set FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE to enable Flash Attention Triton backend on RDNA.
[rocm.py:780] Using Torch SDPA backend for ViT model.
[mm_encoder_attention.py:372] Using AttentionBackendEnum.TORCH_SDPA for MMEncoderAttention.
```

The first line fires ONLY when the Triton-AMD spec is present AND the env
var is not `"TRUE"` (the spec-absent path returns before it); the second
is the L776-777 fallback. So the maintainer's own 0.30 qualification runs
LOGGED ViT = TORCH_SDPA — R4.3's "SDPA-path record" (flagged in R4's
reliability notes as the weakest claim, inferred from configuration) is
now a directly logged observation from the reference box. Collateral for
the fix: the post-fix startup marker is literally the string the
qualified runs logged.

### New finding V2 — the overlay's rocm.py line-shift is fully accounted for

The image's rocm.py coordinates run exactly +4 vs the tag (the release
log's L443/L780 vs the tag's L439/L776). `patch_gfx1201.py` (A0) is the
ONLY overlay that touches `vllm/platforms/rocm.py`: it inserts a 4-line
`RADIANCE_GFX_ARCH` env read into `_get_gcn_arch` [134] — which accounts
for the +4 shift exactly, in an unrelated function. The selection logic
and all its log strings are tag-identical, and the pod's four crash
frames match tag line numbers byte-for-byte. R4.4's "the 35 overlays do
not touch the four crash-path files" holds; this refines it: rocm.py IS
touched (4-line unrelated insert), the other three crash-frame files are
not.

### Conclusion (independent verification)

**R4's exact fix stands, verified.** (a) PRIMARY: drop
`FLASH_ATTENTION_TRITON_AMD_ENABLE: "TRUE"` from the pod env law
(`charts/vllm/values.yaml:263` + `tests/vllm_testlib.py` 20→19 re-pin) —
the ViT then takes the TORCH_SDPA fallback (rocm.py L776-777 →
`F.scaled_dot_product_attention`), the flash-attn import is never
attempted, and the pod's ViT path becomes byte-identical to the
reference recipe's — now with the box's OWN logs as the record (V1).
(b) HARDENING (optional): pin `--mm-encoder-attn-backend TORCH_SDPA` in
serveArgs (flag verified at arg_utils L1399-1403; the override branch
short-circuits the whole selection). (c) Rejected: the TRITON_ATTN pin
(works mechanically — verified import-free at triton_prefill_attention
L217 — but unqualified numerics). (d) Rejected: installing upstream
flash-attn (the premise is refuted — the image never had it, V7 above;
heavy gfx1201 HIP build; stack-atomicity violation; torch built with
`USE_FLASH_ATTENTION=0` by design). Direct answer to the commission's
question 4: **our image does NOT have upstream flash-attn, and never
did** — the crash is the carried env var selecting an import-incomplete
path, and the one-line values fix (the var drop) is the exact fix.

### Sources (verification addendum)

133. magiccodingman/vllm-radiance @ `release`/`5b99d66c` —
    `benchmarks/results/20260922-v030-publication/{non-spec,dflash-k5,
    dflash-k7,mtp-k4}/logs/server-ready.log` (the 0.30-publication
    2×R9700 TP2 runs) — the three-line marker quoted in V1 (non-spec
    L233-236; dflash-k5/k7 L251; mtp-k4 L253) — read in the local clone
    `/tmp/opencode/cf131-r4/radiance-src`.
134. magiccodingman/vllm-radiance @ `release`/`5b99d66c` —
    `patch_gfx1201.py` (A0) — the only overlay touching
    `vllm/platforms/rocm.py`; its 4-line `RADIANCE_GFX_ARCH` insert into
    `_get_gcn_arch` accounts for the tag→image +4 line shift (V2).
135. magiccodingman/vllm-radiance @ `release`/`5b99d66c` — repo-wide
    grep `FLASH_ATTENTION_TRITON_AMD_ENABLE`: hits ONLY in captured
    benchmark logs (all info-once "Set … to enable" lines); ZERO hits in
    Dockerfile / docker-compose.yml / .env.example / docs config
    surfaces (V8 re-check).

### R4.7 — coordination addendum (2026-11-09T12:11Z, the coordinator): the on-target trace PAIR
The owner's bring-up produced TWO encoder-failure traces minutes apart on pod `vllm-dev/a0556179-c629-452c-b7d2-114767a9f61d` (source stack `vllm/model_executor/models/utils.py:432` / `vision.py:522 embed_multimodal`):
- **11:56:01** `ValueError in vision.py: ValueError: total_mblocks exceeds MAX_PROGRAM_GRID_SIZE` — the Triton flash-attn kernel's grid guard (the var routes the encoder INTO `flash_attn_varlen_func`, which raises it).
- **11:59:01** `ImportError: ROCm platform requires upstream flash-attn to be installed.` — R4's documented trace (the availability-gate path on the retry).
Both are the SAME crash class: the single var `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE` puts the ViT encoder on the FLASH_ATTN path, which this image cannot serve (kernel grid limit; and no upstream flash-attn import). Dropping the var routes the encoder to TORCH_SDPA, which calls neither — the D33 fix covers BOTH traces. R4's evidence base (written from the second paste) documented only the ImportError; this addendum records the ValueError half so the runbook's "before-fix" symptom row matches the owner's actual first paste.

# R5 — Installing flash-attention on this ROCm stack — the exact ship surface (2026-11-09)

Round-5 research commission for board card #131, 2026-11-09, by
`agent-research`, RE-SCOPED by the owner's ruling (after on-target crash
#3): **"The error is clear, we need to install flash attention, not remove
it."** D33 (the `FLASH_ATTENTION_TRITON_AMD_ENABLE` drop, R4) is OVERTURNED:
the var returns; the fix for the crash-#2b ImportError is a working
flash-attention IN the image. This section keeps R4's source facts
([118]–[135] stand as facts — rocm.py L438/L433-436 gate, fa_utils
L51-52/L59 tail, the maintainer Dockerfile/compose record, torch
`USE_FLASH_ATTENTION=0` [126]) and re-disposes only the DISPOSITION (R4
fix-(d)-rejection → now the chosen path).

Method: local clones re-read at the exact pins — vLLM `v0.30.0` @
`ced6857afa0ea7b2e3f0846a62e1394e90f15607`, ROCm/aiter @ the image's
`fc2e5d57…` (plus main `51ca4216`), jpvillam-amd/flash-attention @ the
vLLM-pinned branch tip `aa743c59…`, ROCm/flash-attention (tridao/main/3.0
branches + releases API), the PyPI `flash-attn` 2.8.3.post2 sdist,
libr4d @ `e8de4bc1…`, magiccodingman/vllm-radiance release @ `5b99d66c`
(unchanged tip) + main @ `1d2e248` + Docker Hub tags API, and the repo
surfaces. Citations continue at [136].

## TL;DR (5 lines)

1. **"Upstream flash-attn" = the separate pip package `flash_attn`** (Dao
   flash-attention 2.8.x lineage; `fa_utils.py` L52 `from flash_attn import
   flash_attn_varlen_func` @ ced6857a [140]). Installing it does NOT
   require rebuilding torch — the package's only deps are `torch`+`einops`
   [144], both already in the image; torch's own `USE_FLASH_ATTENTION=0`
   build flag [126] is an unrelated, orthogonal switch. The whole fix is
   ONE pip layer on the re-export.
2. **The var is the flash-attn package's OWN ROCm switch, and vLLM's
   official gfx1250 image sets it**: `flash_attn/flash_attn_interface.py`
   L11-15 binds `flash_attn_varlen_func` to the pure-Triton AMD port
   (`flash_attn_triton_amd/interface_fa.py`) when
   `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE`, else to the compiled
   `flash_attn_2_cuda` CK extension (which cannot exist for gfx12x);
   `setup.py` L65-66/L321 skips all C compilation at build time when the
   flag is on [144]. Inside vLLM @ ced6857a the ONLY writer is
   `docker/Dockerfile.rocm_base_gfx1250` L37 — the official AMD gfx1250
   base image [136].
3. **vLLM at the pin ships a complete, citable recipe (option e):** build
   `flash-attn` from `jpvillam-amd/flash-attention` branch
   `jpvillam/gfx1250_wip` (@ `aa743c59`, one commit "simple gfx1250
   enablement": adds gfx1250 to the Triton port's arch list) with the flag
   set, producing a NO-KERNEL-COMPILE wheel, and `pip install` it into the
   base [136][146]. No prebuilt ROCm wheel exists anywhere (PyPI has sdist
   only; both forks' release assets are CUDA-named or empty [145][146]);
   no magiccodingman tag newer than 1.0.397 exists and their in-flight
   1.1.0-rc1 still ships torch `USE_FLASH_ATTENTION=0` with no FA stage
   [149][150] — option (a) is DEAD, the pip layer is ours to write.
4. **R5.1 verdict (honest):** the install deterministically kills crash
   #2b (the ImportError stub); for crash #2a the string `total_mblocks
   exceeds MAX_PROGRAM_GRID_SIZE` exists in NO reachable source — not in
   vLLM@ced6857a, not in either flash-attention fork or the PyPI sdist,
   not in aiter (pin or main), not in libr4d, not in the overlays, zero
   GitHub issue hits [143][144][145][146][147][148] — so installing any
   candidate cannot resurrect that exact error; its provenance is an OPEN
   question for the owner (the pinned image as published cannot have
   raised it either). Crash #3's frames do not exist in the pinned stack
   at all (no `vision_utils/transformers.py`, no "CUDA Graph is out of
   memory" text, encoder graphs default-OFF): its mechanism is moot here,
   but that means the paste is of different provenance — R5-Q2 [142][143].
5. **Recommended ship shape:** one `RUN` layer in
   `containers/vllm-radiance-mxfp4/Dockerfile` installing
   `flash-attn @ git+…jpvillam-amd/flash-attention@aa743c59` with
   `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE` inline, `--no-deps
   --no-build-isolation` (stack atomicity), no ENV baked (the var stays
   chart-owned via the 20-var law) — exact lines in R5.4. Verification
   marker under the baked gfx1201 view reverts to `"Using Flash Attention
   (Triton backend) for ViT model on RDNA."` [139].

## R5.1 — What "upstream flash-attn" concretely means for vLLM 0.30 on ROCm

**The exact import vLLM attempts.** `vllm/v1/attention/backends/fa_utils.py`
@ ced6857a, ROCm branch at module-import time (L38-62): after `from
vllm.platforms.rocm import on_gfx1250` (L43) — `if on_gfx1250(): from
aiter.ops.triton.mha import flash_attn_varlen_func` (L47-50); `else: from
flash_attn import flash_attn_varlen_func` (L51-52) — the UPSTREAM pip
package `flash_attn`; on ImportError the stub is installed and raises L59
with the package string branched at L58 (`"aiter" if on_gfx1250() else
"flash-attn"`, stub def L57, raise L59) — so the pod's observed
"…requires upstream **flash-attn**…" message also PROVES
that process had the non-gfx1250 (i.e. spoofed gfx1201) arch view [140].
The ViT call chain to this tail is R4's, unchanged ([118][121] stand).

**Separate package — no torch rebuild.** `flash-attn`'s PKG-INFO requires
only `torch` and `einops` [144]; its setup.py consumes the installed torch
for hipify/detection but never rebuilds it. torch's `USE_FLASH_ATTENTION=0`
in the base build [126] only disables TORCH's internal flash backend — it
says nothing about the `flash_attn` package, which is a distinct module
(`flash_attn/__init__.py` imports its own `flash_attn_interface`) [144].
**The whole fix shape is therefore a pip layer, not a stack rebuild** —
this is the decision the commission asked to confirm.

**What the var changes inside the package.** Three readers, all in the
package, none invented by vLLM:
- `flash_attn/flash_attn_interface.py` L11-15 (2.8.3.post2 / gfx1250_wip):
  `USE_TRITON_ROCM = os.getenv("FLASH_ATTENTION_TRITON_AMD_ENABLE",
  "FALSE") == "TRUE"` → import `flash_attn_triton_amd.interface_fa` as
  `flash_attn_gpu`, else `import flash_attn_2_cuda` [144].
- `setup.py` L65-66: same flag + `SKIP_CK_BUILD` (defaults TRUE when the
  flag is on) → the ROCm branch (L315+) "Skips CK C++ extension
  compilation if using Triton Backend" (comment L320) — the wheel becomes
  pure Python + Triton JIT sources, no hipcc compile at all [144].
- `flash_attn/flash_attn_triton_amd/utils.py` L19 (+ `bench.py` env list).
The flag's ORIGIN is the flash-attention AMD Triton port itself (present
identically in Dao-AILab upstream, the ROCm fork, and jpvillam's branch —
even in `hopper/setup.py` L47 [145]); **the only SETTER inside the vLLM
tree @ ced6857a is `docker/Dockerfile.rocm_base_gfx1250` L37** (`ENV
FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"`, under the comment "TODO: Unset
these when support is available for gfx1250") — i.e. vLLM's own official
gfx1250 launcher image ships the var, exactly what the commission
expected from "launcher scripts" [136][143]. vLLM's only READER is still
rocm.py L438 (the RDNA gate, R4 [119]) — unchanged.

**Runtime arch semantics (decides WHICH source to pin).** The Triton port
keys its own arch lists off TRITON's device target — the REAL silicon —
not off vLLM's `_GCN_ARCH` (which the image spoofs to gfx1201 via
`RADIANCE_GFX_ARCH` [149][151]): PyPI 2.8.3.post2 `utils.py` L768 `is_cdna
= arch in ('gfx908'…'gfx950')` and L772 `is_rdna = arch in ("gfx1030",
"gfx11xx", "gfx1200", "gfx1201")` — **gfx1250 is in NEITHER list**;
jpvillam's `gfx1250_wip` branch is exactly the one-line change adding
`'gfx1250'` to the is_cdna list (branch tip `aa743c59`, 2026-07-13, "Initial
commit for simple gfx1250 enablement"; rest of the tree matches 2.8.3)
[144][146]. If our R9700 enumerates to Triton as gfx1250 (the commission's
"R9700/gfx1250" + vLLM's own gfx1250 image line + AMD's existence of this
fork all point that way), the PyPI wheel runs UNWHITELISTED (neither CDNA
nor RDNA tile settings — untested combo) and the jpvillam branch is the
supported one; if it enumerates gfx1201, PyPI 2.8.3 already whitelists it.
The 30-second arbiter is one pod-side probe (R5-Q3): `python -c "import
triton; print(triton.runtime.driver.active.get_current_target())"`.

**Crash #2a's `ValueError: total_mblocks exceeds MAX_PROGRAM_GRID_SIZE` —
the exhaustive hunt.** Searched for the strings `MAX_PROGRAM_GRID_SIZE` /
`total_mblocks exceeds` / `total_mblocks` in: vLLM @ ced6857a (full tree:
ZERO hits) [143]; ROCm/flash-attention branch `tridao` (tip 54b044c8),
`main`, `3.0`, `flash_attention_for_rocm3` (git-grep: `total_mblocks` only
in the NVIDIA `hopper/flash_api.cpp`/`heuristics.h` split-KV code and the
CUDA-only `flash_attn/cute/config.py`; `PROGRAM_GRID` nowhere) [145];
jpvillam-amd `gfx1250_wip` @ aa743c59 (ZERO) [146]; the PyPI sdist
2.8.3.post2 (ZERO) [144]; ROCm/aiter @ the pin fc2e5d57 AND latest main
51ca4216 (ZERO — including the vendored
`aiter/ops/triton/_triton_kernels/flash_attn_triton_amd/{interface_v2,
interface_v3,fwd_prefill,fwd_decode,bwd,utils}.py` and the
`attention/mha.py:842 flash_attn_varlen_func` wrapper the gfx1250 branch
would call — the wrapper dispatches into the vendored Triton kernels with
`grid=(cdiv(max_seqlen, BLOCK_M), nheads_q, batch)`, dimensions ≤ a few
hundred for our shapes, structurally nowhere near AMD's grid caps, and
containing no such raise) [147]; libr4d @ e8de4bc1 and every radiance
overlay @ 5b99d66c (ZERO) [149]; the vLLM `v0.31.0…v0.34.1`+main tags (no
`vision_utils`, no such text) [143]. GitHub issue-search API: `"MAX_
PROGRAM_GRID_SIZE"` → total 0; `"total_mblocks"` → 12 hits, all NVIDIA
FA3/CuTe split-KV scheduling (unrelated text) [148].
**Determination: the pinned image AS PUBLISHED CANNOT raise that
ValueError** — no code inside it contains the string, and the gfx1201-view
tail fails at the import (which is exactly the #2b trace). The most
plausible provenance of the 11:56:01 trace is an on-pod experiment outside
the published image contents (e.g. an ad-hoc `pip install flash-attn`/
wheel swap during bring-up from a source that DID carry such a guard — the
string's author is unlocatable in any public repo reachable), or a garbled
re-quote. What changes when a full flash_attn install is present: the
package's varlen fwd launch is the grid lambda above — there is no grid
guard in any candidate version to resurrect, and no "ROCm/Triton backend
version bump" is even needed because the limit-in-question exists in
nothing we can inspect.

**HONEST verdict — does install plausibly fix BOTH crash-#2 traces and
retire crash #3?**
- Crash #2b (ImportError): **YES, deterministically** — `from flash_attn
  import flash_attn_varlen_func` stops failing; with the var TRUE the
  binding is the Triton port [140][144]; with the var TRUE, the rocm.py L438
  gate + L433-436 spec (now satisfied by BOTH layouts) keeps ViT = FLASH_ATTN
  [119][139].
- Crash #2a (ValueError): **cannot be made worse by install** (no install
  candidate contains the guard — exhaustive above), and **cannot be
  verified as fixed** either, since its raiser is not in any reachable
  source. Resurrection risk: LOW, honestly labelled un-attributed; R5-Q2
  asks the owner for the full 11:56 traceback + any pip actions taken live.
- Crash #3 (CUDA-graph OOM at `vision_utils/transformers.py`): the pinned
  stack contains neither the file nor the message, and its encoder-graph
  machinery is default-OFF and not enabled by our serveArgs (R5.3) — on
  THIS image there is no graph to fall over; the install is still worth
  doing for #2b, but the owner must confirm crash #3's actual provenance
  before the "SDPA fallback broke, FA fixes it" chain of reasoning gets
  recorded as fact (R5-Q2) [142][143].

## R5.2 — The install surface for `containers/vllm-radiance-mxfp4`

The base re-export (`FROM docker.io/magiccodingman/vllm-radiance:1.0.397@
sha256:b73bf3…`, venv `/opt/vllm`, python 3.12, PATH head `/opt/vllm/bin`
[126][152]) means a plain `pip install` line targets the right interpreter.
Evaluated options:

**(a/d) A newer magiccodingman tag already carrying flash-attn, or an
install-time knob — REFUTED, dead end.** Docker Hub `tags/?ordering=
last_updated`: newest publish = `1.0.397`/`1.0`/`latest`/`sha-5b99d66c844f`
all 2026-10-18 — nothing newer than our pin [150]. The release branch tip
is still `5b99d66c` (fresh fetch) [152-adj]. The `main` branch (tip
`1d2e248`, VERSION `1.1.0-rc1.vllm0.30.0`) still builds torch with
`USE_FLASH_ATTENTION=0` (Dockerfile L101) and has NO flash-attn stage and
no FA knob anywhere (grep) [149]. `radiance-rs/vllm-radiance` does not
exist (GitHub API Not Found) — the org name in the commission is a
mislabel; the source repo remains `magiccodingman/vllm-radiance` [150].
**If a future publish bakes FA, re-evaluate (watch line stands); today the
cheapest legal path does not exist and the layer is ours.**

**(b) AMD fork `ROCm/flash-attention` as the pip source.** Its default
branch `tridao` is the upstream Dao mirror; its release assets are either
empty or CUDA-named wheels (`flash_attn-2.8.0.post2+cu12torch2.4…whl`) —
**no ROCm prebuilt wheel is published there** [145]. Source-install
(`git+https://github.com/ROCm/flash-attention.git@<sha>`) lands on the same
pure-Triton path as (c), but its shipped arch whitelist (PyPI-identical,
no gfx1250) makes it the weaker choice if the silicon is gfx1250 (above).

**(c) Prebuilt wheel from any source — none exists.** PyPI `flash-attn`
2.8.3.post2 ships sdist only; the sdist's own GitHub-release wheel lookup
(`BASE_WHEEL_URL`, Dao releases) is CUDA-only [144]. jpvillam-amd/flash-
attention has ZERO releases [146]. The vLLM-project org ships
`vllm-project/flash-attention` for CUDA only (the bundled
`vllm.vllm_flash_attn`, no ROCm artifact for RDNA) [140-adj]; AMD's
`repo.radeon.com/rocm/manylinux/` probe (rocm-rel-6.4 listing) surfaced no
flash-attn asset — partial probe, recorded as "not found at the index
class we checked" [ref [136] index: the vLLM gfx1250 base itself pulls
torch/triton from `rocm.devreleases.amd.com/whl-multi-arch/`, not FA]
[136]. **A wheel-only install is not currently possible; source-layer it
is.**

**(e) vLLM's own ROCm recommendation @ ced6857a — THE citable recipe.**
Two artifacts, both at the pin:
- `docker/Dockerfile.rocm_base_gfx1250`: `ARG FA_BRANCH="jpvillam/
  gfx1250_wip"`, `ARG FA_REPO="…/jpvillam-amd/flash-attention.git"` (L11-12);
  base `rocm/vllm-dev` family, `ENV PYTORCH_ROCM_ARCH=gfx1250` (L28-29);
  `ENV FA_GPU_ARCHS=gfx942;gfx950;gfx1250` (L36); **`ENV
  FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"` (L37)** under "TODO: Unset these
  when support is available for gfx1250"; the `build_fa` stage clones the
  branch and builds `GPU_ARCHS=<list minus gfx1xxx> python3 setup.py
  bdist_wheel` (L236-246) — the flag makes setup.py skip CK compilation,
  so the "wheel" is the pure-Python Triton port; the `final` stage `pip
  install /install/*.whl` (L302-304) and records FA_REPO/FA_BRANCH in
  `/app/versions.txt` (L309-321) [136]. The `padroute` triton fork clone
  (L39-40, L169-176, `TRITON_KERNELS_SRC_DIR` = `python/triton_kernels/`)
  is the OpenAI `triton_kernels` MoE library patched — NOT a prerequisite
  for the FA Triton port [136].
- `docs/getting_started/installation/gpu.rocm.inc.md` L266-274: "Optionally,
  if you choose to use CK flash attention, you can install flash attention
  for ROCm … (v2.8.0) … git clone https://github.com/Dao-AILab/
  flash-attention.git" — the CK variant (compiled hip kernels, CDNA-class);
  not our route (no RDNA device code; radiance's own kernel docstring says
  the same [138][149]).
What their tooling pip-installs: exactly the branch-built wheel — no PyPI
flash-attn, no separate triton fork install for FA [136].

**RECOMMENDED SHIP LAYER** (repo container-creation conventions: ARG pins
with a renovate comment where a datasource exists; `git` availability in
the base is proven — the base image's own build uses it, and the runtime
image ships it for the entrypoint helpers; if the CI build turns up no
`git` in the final image the line still works via pip's git+https only if
git exists — first CI run is the authority, cf-77 law):

```dockerfile
# flash-attn for the ViT FLASH_ATTN path (owner ruling 2026-11-09, D33
# overturned — RESEARCH R5): the pure-Triton AMD port, the SAME source the
# official vLLM ROCm gfx1250 base image builds
# (docker/Dockerfile.rocm_base_gfx1250 @ v0.30.0: jpvillam-amd/
# flash-attention, branch jpvillam/gfx1250_wip) — chosen over the PyPI
# wheel because the PyPI 2.8.3 arch list omits gfx1250 (the R9700's
# enumeration per the commission; the gfx1201 probe result would equally
# license `flash-attn==2.8.3.post2`). With FLASH_ATTENTION_TRITON_AMD_
# ENABLE=TRUE at build time the package compiles NO extension (setup.py
# SKIP_CK_BUILD default) — kernels JIT via Triton at runtime; the flag is
# deliberately inline-only, the runtime var stays chart-owned (20-var law).
# --no-deps --no-build-isolation protect the stack-pinned torch/triton
# (stack.yaml atomicity law); setup.py imports torch+packaging+setuptools
# +wheel, hence the prep. No tag exists upstream → no auto datasource;
# manual bump with the base-pin law (D12-amended shape).
ARG FLASH_ATTN_REPO=https://github.com/jpvillam-amd/flash-attention.git
ARG FLASH_ATTN_REF=aa743c5933560d097d8aa5e833ca10153ed7f6bb
RUN python3 -m pip install --no-cache-dir setuptools wheel packaging \
 && FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE python3 -m pip install \
      --no-cache-dir --no-deps --no-build-isolation \
      "flash-attn @ git+${FLASH_ATTN_REPO}@${FLASH_ATTN_REF}"
```

Placement: after `FROM` (and its ledger comment), before `EXPOSE 8000` —
the layer is change-invalidating-cheap above the static EXPOSE [152].
**Compile-time cost on CI:** no HIP/CK compilation (flag skips it) — the
expensive part is the git fetch of a ~200 MB-class repo working tree (no
submodule needed on the Triton path); estimate **minutes**, not the
hours-class of a CK build — CI measurement owns the final number
(`docker-build.yaml` on the branch, build-only on PRs). **Image size
delta:** pure-Python package ≈ low tens of MB (the `flash_attn/` tree incl.
`flash_attn_triton_amd/*.py`; the sdist itself is ~1 MB compressed) —
again CI-verified. **Renovate note:** branch heads on a `_wip` branch must
NOT be auto-tracked (`git-refs` datasource would follow churn — wrong
here); keep the commit pin + manual bump, optionally a
`datasource=github-tags depName=Dao-AILab/flash-attention` pin ONLY if the
PyPI/Dao variant (`flash-attn==2.8.3.post2`) is chosen after R5-Q3 resolves
gfx1201.

## R5.3 — Verification law + crash #3's fate

**The startup marker.** Exact @ ced6857a strings, rocm.py
`get_vit_attn_backend` (L753-777) [139]: CDNA branch (gfx1250-VIEW only,
and its gate is `find_spec("flash_attn")`, not the var): `"Using Flash
Attention backend for ViT model."` (L762). RDNA Triton branch (OUR branch
— the image's baked `RADIANCE_GFX_ARCH=gfx1201` view): `"Using Flash
Attention (Triton backend) for ViT model on RDNA."` (L771-773). Fallback:
`"Using Torch SDPA backend for ViT model."` (L776). So the runbook
step-3 marker REVERTS to the Flash-(Triton)-on-RDNA line (the OQ12-era
line R4 replaced), NOT the bare "Using Flash Attention backend" line the
commission quoted — that wording belongs to the CDNA branch and is only
reachable if someone un-spoofs `RADIANCE_GFX_ARCH` to gfx1250 (then
branch 3 + the installed package would log it and run AITER's Triton mha
via the alias finder [147] — a different, unqualified config — record as
barred). Per-layer confirm line (unchanged mechanism): `"Using
AttentionBackendEnum.FLASH_ATTN for MMEncoderAttention."` (mm_encoder_
attention.py L372 [118][133]). The runbook "a Flash line means the var
leaked back" row (C05 L152-158 post-D33 wording) must flip to "the Flash
line is REQUIRED; its absence = package missing or var dropped".

**Does the FLASH_ATTN encoder path go through `forward_with_cuda_graph`?**
**The wrapper the commission cites does not exist in this stack.**
`vllm/model_executor/models/vision_utils/` is not a path in vLLM @
ced6857a, nor v0.31.0/0.32.0/0.33.0/0.34.0/v0.34.1, nor `main` (raw 404 +
API tree listing + local greps) [143]; nor in the radiance overlay set
(repo-wide grep) [149]; and the message text "CUDA Graph is out of
memory. Try to lower number of frames or resolution, or disable CUDA
graphs for ViT or encoder models." greps zero in 0.30, 0.33 and the 0.33
main-line clone. In 0.30 the encoder-CUDA-graph machinery exists but is
gated OFF-by-default: `cudagraph_mm_encoder: bool = False`
(compilation.py L550), enabled only via `--compilation-config`; the V2
runner gates `not enforce_eager AND cudagraph_mm_encoder AND
supports_encoder_cudagraph(model)` (model_states/interface.py L69-76) —
Qwen3.5 DOES implement `SupportsEncoderCudaGraph` (qwen3_vl.py L1794,
protocol methods L1972+) but our `-cc` is `{"cudagraph_mode":"PIECEWISE"}`
(values.yaml L290), which does NOT set `cudagraph_mm_encoder` → encoder
graphs are never captured, and `compile_mm_encoder` (L542, same default
False, the `enable_if` on the ViT's `@support_torch_compile` decorators
qwen3_vl.py L365-370/decorators.py L53-55) → the ViT runs EAGER. Proven:
no graph wrapper on the pinned stack ⇒ the SDPA-vs-FA "graph capture
memory profile for {"image":4}" question is undefined here — nothing to
bite, nothing to moot. ASSUMED (labelled): that the owner's 11:54:54
trace came from some other build (an rc1 candidate or another image) —
R5-Q2. One genuine memory note survives either way: the base's torch is
built `USE_FLASH_ATTENTION=0 USE_MEM_EFF_ATTENTION=0 USE_AOTRITON=0`
[126], so the TORCH_SDPA fallback resolves to torch's MATH-form SDPA
(segment-materialized attention matrices); the FLASH_ATTN Triton port is
tiled and never materializes them — the install is memory-FAVOURABLE for
the ViT regardless of graphs [144][149].

**The real 0.30 knob for "disable CUDA graphs for ViT or encoder models":**
`--compilation-config '{"cudagraph_mm_encoder": false}'` — already the
default in our law; `--mm-encoder-attn-backend` is confirmed NOT a graph
switch (it only overrides the attention-backend choice, arg_utils L1399-
1403 [125], via vision.py→rocm.py L741-747 [119][122]). Related shape
budgets if a future build enables encoder graphs:
`encoder_cudagraph_token_budgets` / `encoder_cudagraph_max_vision_items_
per_batch` / `encoder_cudagraph_max_frames_per_batch` (compilation.py
L555-575) — the "lower number of frames or resolution" half of the quoted
message maps to these [142].

## R5.4 — Options table, the owner question, the proposed diff

| Option | Shape | Evidence | CI cost | Verdict |
|---|---|---|---|---|
| (a) newest magiccodingman tag w/ FA | base re-pin | none newer than 1.0.397; 1.1.0-rc1 still `USE_FLASH_ATTENTION=0`, no FA stage [149][150] | — | **does not exist** — re-check every base bump (watch) |
| (b) ROCm/flash-attention source layer | pip layer, git-pinned | same pure-Triton code; arch whitelist lacks gfx1250 [145] | minutes | viable IF the R5-Q3 probe says gfx1201; else (e) |
| (c) prebuilt ROCm wheel | pip layer, wheel URL | **no ROCm wheels exist** (PyPI sdist-only; both forks' releases CUDA/empty) [144][145][146] | — | not currently possible |
| (e) vLLM-official gfx1250 recipe ported | pip layer: jpvillam branch `aa743c59`, flag-inline, `--no-deps --no-build-isolation` | exactly the official `Dockerfile.rocm_base_gfx1250` FA stage + install, minus their torch/aiter stack [136][146] | minutes; low-tens-of-MB (CI-measured) | **RECOMMENDED** |
| (d') keep SDPA + disable encoder CUDA graphs | values-only | encoder graphs are ALREADY off in our law; the quoted crash-#3 text/file is not in this stack at all [142][143] | zero | priced, rejected on evidence: it disables nothing that exists — and the owner already ruled for install |

**R5-Q1 (the single owner question, with recommendation):** install
flash-attention into `containers/vllm-radiance-mxfp4` as the ONE pure-
Triton pip layer of option (e) — the same source branch vLLM's own gfx1250
image pins (`jpvillam-amd/flash-attention @ aa743c59`) — together with the
D33 reversion (var back into the 20-var law) — **recommendation: YES, (e)
as written; substitute `flash-attn==2.8.3.post2` from PyPI only if R5-Q3's
pod probe reports gfx1201.** Best guess taken per alternative: (a) would
have been cheapest but is empty [150]; (c) does not exist [144-146];
(d') addresses a mechanism absent from the pinned stack [142][143].
**R5-Q2:** the provenance of the two traces the re-scoping rests on —
the owner's FULL 11:56:01 ValueError traceback (its raiser string exists
in no public artifact of this stack — was an ad-hoc package installed in
the running pod first?) and the 11:54:54 CUDA-graph OOM frames
(`vision_utils/transformers.py` is not in this image or any vLLM tag) —
which image was the pod running at 11:54:54? **R5-Q3:** run on the pod:
`python3 -c "import triton; print(triton.runtime.driver.active.
get_current_target())"` (and, post-install, `pip show flash-attn`) —
gfx1250 vs gfx1201 selects between (e) and (b).

**Exact proposed container diff (recommended option):**

```dockerfile
# containers/vllm-radiance-mxfp4/Dockerfile — insert between FROM(+ledger) and EXPOSE:
ARG FLASH_ATTN_REF=aa743c5933560d097d8aa5e833ca10153ed7f6bb
RUN python3 -m pip install --no-cache-dir setuptools wheel packaging \
 && FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE python3 -m pip install \
      --no-cache-dir --no-deps --no-build-isolation \
      "flash-attn @ git+https://github.com/jpvillam-amd/flash-attention.git@${FLASH_ATTN_REF}"
```
(comment block above it as in R5.2). Companion reversion surfaces the
coordinator owns (NOT written by this section): `charts/vllm/values.yaml`
re-add `FLASH_ATTENTION_TRITON_AMD_ENABLE: "TRUE"` at the (8) slot (after
`AITER_ROOT_DIR`, values.yaml L258 region) with the R5-ground comment (var
+ package are BOTH required: the var is the selector, the package is the
payload); `charts/vllm/tests/vllm_testlib.py` `env_want_cf131` 19-var
re-pin → 20-var AND the L205-211 "barred entry" comment/`
FLASH_ATTENTION_TRITON_AMD_ENABLE` list item removed (the exact-set now
must CONTAIN it); `chunks/C05.md` step-3 marker → the RDNA-Triton Flash
line (REQUIRED), step-3.4 first-multimodal smoke = the crash-gate for the
install, and the "var leaked back" row inverted; `README.md` ledger note:
the re-export is no longer a pure digest-copy (D23 collapses to "copy +
FA layer"; on every base bump re-verify the FA layer still imports and the
marker line still logs), plus DECISIONS entry recording D33 OVERTURNED by
the owner ruling and R4's fix-(d) rejection re-disposed by R5.

## Contradictions and how to weigh them (R5 conflict map)

1. **Commission/owner frame "crash #3 = the SDPA fallback's HIP-graph
   capture failure" vs the pinned tree** — the file, message and (default)
   mechanism do not exist in this stack [142][143]. Weight: the tree is
   dispositive for what CAN have happened on 1.0.397; the ruling to
   INSTALL is honoured regardless (it stands on #2b alone), but the
   causal sentence "graph capture failed under SDPA, FA will moot it"
   cannot be recorded as verified — R5-Q2.
2. **Coordinator note "MAX_PROGRAM_GRID_SIZE lives in flash_attn's triton
   code" vs the exhaustive greps** — present in no reachable flash-
   attention tree (PyPI 2.8.3.post2, ROCm fork ×4 branches, jpvillam
   branch), no aiter, no vLLM, zero GitHub issue hits [143-148]. Weight:
   recorded as an unverified premise; the install options were evaluated
   so that NO candidate introduces the string — the "resurrection" worry
   is answered "not by these sources", which is the strongest defensible
   statement without the owner's full traceback.
3. **Commission "R9700/gfx1250" vs the image's own law "gfx1201 (R9700 /
   RDNA4)"** [149] — resolved as TWO arch views of the SAME card: the
   radiance ENV spoofs vLLM's PYTHON view to gfx1201, while the package/
   Triton view keys off real silicon enumeration (gfx1250-class per the
   commission, the reason AMD shipped the gfx1250_wip FA branch and vLLM
   shipped a gfx1250 base line). Weigh: act on both — pin the fork source
   that whitelists gfx1250 and keep the gfx1201 ENV untouched; settle the
   fact with the R5-Q3 probe.
4. **R4's rejection of install ("stack-atomicity violation; overrides
   the authors' design") vs the owner ruling** — R4's FACTS stand (no FA
   in the base, authors build torch without flash); its DISPOSITION is
   overturned by the owner, who outranks the design-alignment argument.
   The atomicity concern is mitigated (not voided) by `--no-deps
   --no-build-isolation` + a commit-pinned pure-Python layer that touches
   no stack member [144][146]; the authors' `USE_FLASH_ATTENTION=0` remains
   irrelevant to the separate package (§R5.1).

## Implications for the plan

- C01 surface grows from pure digest-copy to digest-pin + ONE pip layer;
  the README ledger/bump-procedure text must record the FA re-verify duty
  on base bumps; the pin `FLASH_ATTN_REF` is manual-bump (no datasource)
  unless (b)+gfx1201 lets it move to `github-tags depName=Dao-AILab/
  flash-attention`.
- D33 formally OVERTURNED (owner ruling — coord records); the D25 20-var
  law is restored exactly as it was (the var is REQUIRED WITH the package:
  it is simultaneously the selector (rocm.py L438) and the package's own
  Triton-binding switch (§R5.1) — the "var alone was the bug" story was
  only true BECAUSE the package was missing).
- The C05 crash-gate (step 3.4) now proves THREE things at once: the
  Flash-Triton marker line, the first-multimodal success (no ImportError,
  no grid ValueError on {"image": 4}), and ViT numerical sanity (the
  Triton port pads head_dim 72 → 128-wide tiles — the exact "padding
  waste" radiance wrote r4d to avoid [149]; correctness yes, efficiency
  NOT claimed — this is now the QUALIFIED-for-CI path, not the
  maintainer-qualified one: R4.3's "SDPA is the qualified path" sentence
  stays TRUE historically; the owner accepted the trade).
- `pip install` does NOT touch decoder behaviour: R4D stays pinned in
  serveArgs; only three code sites import/gate `flash_attn` in the tree
  (§R5.1 blast radius; qwen2_5_omni_thinker is a different model) [140].

## Open questions (no-questions-rule log — round 5, for coord → owner/plan)

- **R5-Q1** — approve the (e) container diff above (single FA layer,
  jpvillam branch `aa743c59`, inline flag, `--no-deps
  --no-build-isolation`) as the ship surface for the owner's install
  ruling? Best guess taken: YES (it is vLLM's own gfx1250 recipe,
  gfx1250-safe and gfx1201-safe in one pin).
- **R5-Q2** — provenance of the 11:56:01 ValueError and the 11:54:54
  CUDA-graph frames (full tracebacks; which image the pod ran at 11:54:54;
  any on-pod pip installs during bring-up). Both strings/files are absent
  from the published stack; the re-scoping premise needs this grounding
  before the narrative is written into DECISIONS.
- **R5-Q3** — one pod-side probe decides (e)-vs-(b) pin choice:
  `triton.runtime.driver.active.get_current_target()`.

## Sources (R5)

All reads 2026-11-09, at the exact pins. vLLM line numbers re-verified in
the local `v0.30.0` clone (`git rev-parse HEAD` = `ced6857a…`).

136. vLLM v0.30.0 @ ced6857a — `docker/Dockerfile.rocm_base_gfx1250` — L1-3 `BASE_IMAGE=ubuntu:24.04` + `ROCM_WHEEL_INDEX=https://rocm.devreleases.amd.com/whl-multi-arch/` (L2) + `ROCM_SDK_VERSION=7.14.0a20260623` / `TRITON_VERSION=3.7.1+git110cd8e2.rocm7.14…`; L11-12 `ARG FA_BRANCH="jpvillam/gfx1250_wip"` `ARG FA_REPO="https://github.com/jpvillam-amd/flash-attention.git"`; L28-36 `PYTORCH_ROCM_ARCH=gfx1250`, `FA_GPU_ARCHS=gfx942;gfx950;gfx1250`; **L34-37 "TODO: Unset these when support is available for gfx1250" + `ENV FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"`**; L39-40 `TRITON_KERNEL_BRANCH="padroute"` / `TRITON_KERNEL_REPO=jpvillam-amd/triton`; L169-176 the padroute clone = `python/triton_kernels/` (MoE lib, `TRITON_KERNELS_SRC_DIR` set-only-never-consumed-for-FA); L228-246 `build_fa`: `GPU_ARCHS=$(… sed strips gfx1[0-9]{3} …) python3 setup.py bdist_wheel`; L279-304 debs/final `pip install /install/*.whl`; L309-321 `/app/versions.txt` records FA_REPO/FA_BRANCH — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/docker/Dockerfile.rocm_base_gfx1250
137. vLLM v0.30.0 @ ced6857a — `docker/Dockerfile.rocm_gfx1250` — `ARG BASE_IMAGE=rocm/vllm-dev:base`, `ARG PYTORCH_ROCM_ARCH=gfx1250` (the vLLM layer atop the gfx1250 base) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/docker/Dockerfile.rocm_gfx1250
138. vLLM v0.30.0 @ ced6857a — `docs/getting_started/installation/gpu.rocm.inc.md` L266-274 — "Optionally, if you choose to use CK flash attention, you can install flash attention for ROCm … (v2.8.0) … git clone https://github.com/Dao-AILab/flash-attention.git" — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/docs/getting_started/installation/gpu.rocm.inc.md
139. vLLM v0.30.0 @ ced6857a — `vllm/platforms/rocm.py` — L207 `_ON_GFX1X=any(gfx11/gfx12)`; L217 `_ON_GFX1250`; **L219-221 `_ON_CDNA = any(…["gfx9","gfx1250"])` + "RDNA = gfx11/gfx12 minus the CDNA-classified gfx1250"**; L296-297 `on_gfx1x() = _ON_GFX1X and not _ON_CDNA`; L316-317 `on_gfx1250`; L353-361 `get_cdna_version()` (gfx1250→5); L415-446 `flash_attn_triton_available()` (L417 gfx1x-only, L433-436 both specs, L438 var gate); ViT selector exact logs: L753-755 `"Using AITER Flash Attention backend for ViT model."` / L757-763 `on_cdna() and find_spec("flash_attn")` → **`"Using Flash Attention backend for ViT model."`** / L765-774 → **`"Using Flash Attention (Triton backend) for ViT model on RDNA."`** / L776-777 `"Using Torch SDPA backend for ViT model."` — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/platforms/rocm.py
140. vLLM v0.30.0 @ ced6857a — `vllm/v1/attention/backends/fa_utils.py` — L38-42 the ROCm comment block ("On ROCm we use AITER's Triton flash-attention; the upstream flash-attn package is not installed/available"); L43 `from vllm.platforms.rocm import on_gfx1250`; L47-50 gfx1250 → `from aiter.ops.triton.mha import flash_attn_varlen_func`; L51-52 else → `from flash_attn import flash_attn_varlen_func`; L55-62 `except ImportError` — L57 stub def, **L58 `package = "aiter" if on_gfx1250() else "flash-attn"`**, L59 raise (the pod message branch-proves the gfx1201 view) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/attention/backends/fa_utils.py
141. vLLM v0.30.0 @ ced6857a — `vllm/v1/attention/ops/vit_attn_wrappers.py` — L27 `flash_attn_maxseqlen_wrapper`; **L38-41 `is_rocm_aiter` → `from aiter import flash_attn_varlen_func`** (NOT exported by the pinned aiter — dead branch here, R5.1); L43-46 else `from …fa_utils import flash_attn_varlen_func`; L48-62 cu_seqlens/max_seqlen `.item()`/L62 call; L100/L111 the vit wrapper; L234 `apply_sdpa` / L255 `torch_sdpa_wrapper` (the surface radiance swaps, R5.3 note); L152-161 `triton_attn_wrapper` → `context_attention_fwd` — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/attention/ops/vit_attn_wrappers.py
142. vLLM v0.30.0 @ ced6857a — the encoder-CUDA-graph machinery — `vllm/config/compilation.py` **L542 `compile_mm_encoder: bool = False`**, **L550 `cudagraph_mm_encoder: bool = False`**, L555-575 `encoder_cudagraph_token_budgets`/`encoder_cudagraph_max_vision_items_per_batch: int = 0`/`encoder_cudagraph_max_frames_per_batch`; `vllm/v1/worker/gpu/model_states/interface.py` L69-76 `enable_encoder_cuda_graph = not enforce_eager and cudagraph_mm_encoder and supports_encoder_cudagraph(model)`; `vllm/v1/worker/gpu_model_runner.py` L6625-6635 same gate; `vllm/v1/worker/gpu/model_runner.py` L997-1009 capture gating + skip-warning; `vllm/config/vllm.py` L1310-1321 `language_model_only`×`cudagraph_mm_encoder` conflict; `vllm/compilation/decorators.py` L53-55 `should_torch_compile_mm_encoder` = `compile_mm_encoder`; `vllm/model_executor/models/qwen3_vl.py` L365-370 ViT `@support_torch_compile(enable_if=should_torch_compile_mm_encoder, is_encoder=True)`, L1794 + L1972-2090 `SupportsEncoderCudaGraph` implementation (present, but never engaged at our `-cc`) — greps: the strings "CUDA Graph is out of memory" / "Try to lower number of frames" ABSENT (0 hits) in this tag, in the v0.33-line clone @4ba787ec, and on `main` (`vllm/compilation/cuda_graph.py`, `vllm/v1/worker/gpu/model_runner.py`)
143. vLLM @ ced6857a + upstream tags — negative tree facts — `vllm/model_executor/models/vision_utils/` does not exist in v0.30.0 (dir listing), nor raw paths at `v0.31.0/v0.32.0/v0.33.0/v0.34.0/v0.34.1/main` (HTTP 404 ×6), nor the models-dir listing on `main` (GitHub contents API); `MAX_PROGRAM_GRID_SIZE`/`total_mblocks`: 0 hits across the v0.30.0 tree; `FLASH_ATTENTION_TRITON_AMD_ENABLE` setter: exactly `docker/Dockerfile.rocm_base_gfx1250:37` (grep of the full repo incl. docs/.buildkite/tools); `flash_attn` import/gate sites: exactly 3 (rocm.py L759, fa_utils L52, qwen2_5_omni_thinker L112)
144. PyPI `flash-attn` **2.8.3.post2** sdist (latest; sha-fetched + unpacked) — PKG-INFO Requires-Dist: `torch`, `einops` ONLY; no pyproject.toml (legacy setuptools backend → build isolation would break on `import torch`; hence `--no-build-isolation`); `flash_attn/__init__.py` L3-10 interface exports; **`flash_attn/flash_attn_interface.py` L11-15 `USE_TRITON_ROCM = getenv("FLASH_ATTENTION_TRITON_AMD_ENABLE")=="TRUE"` → `from .flash_attn_triton_amd import interface_fa` ELSE `import flash_attn_2_cuda`**; `setup.py` L28-51 IS_ROCM via `torch.version.hip`/`BUILD_TARGET`, **L65-66 flag + `SKIP_CK_BUILD` (default TRUE when flag on)**, L315-321 "Skips CK C++ extension compilation if using Triton Backend" (ck_tile codegen + hipcc path L322+ skipped entirely), GPU_ARCHS `--offload-arch` CK path (skipped); `flash_attn/flash_attn_triton_amd/` file tree (interface_fa, fwd_prefill, fwd_decode, bwd*, utils, …); **`utils.py` L759-775 `get_arch()` from `triton.runtime.driver.active.get_current_target()`, `is_cdna` list `gfx908…gfx950` (NO gfx1250), `is_rdna` list incl. `gfx1200, gfx1201`**; `interface_fa.py` L592-601 `grid = (triton.cdiv(max_seqlens_q, BLOCK_M), nheads_q, batch)`; guard string: 0 hits — https://pypi.org/project/flash-attn/
145. ROCm/flash-attention — default branch `tridao` @54b044c8 + `origin/main` + `origin/3.0` + `origin/flash_attention_for_rocm3` (git greps) — flag readers identical (interface L12, setup L71 `ROCM_BACKEND = "triton" if …flag… else "ck"`, hopper copies); `total_mblocks` ONLY in NVIDIA hopper C++ + `flash_attn/cute/config.py` (FA4 CuTe, CUDA); `PROGRAM_GRID` nowhere; releases API: `v2.8.4.1-cktile`/`v2.8.4-cktile`/`v2.7.4-cktile`/`v2.7.0-cktile` = **no assets**, `v2.8.0-cktile`/`v3.0.0.r1-cktile`/`v2.7.3-cktile`/`v2.6.*-cktile` assets all `flash_attn-…+cu12torch…`/`+cu118…` CUDA-named wheels — no ROCm wheel exists — https://github.com/ROCm/flash-attention (+ api.github.com/repos/ROCm/flash-attention/releases)
146. jpvillam-amd/flash-attention — branch `jpvillam/gfx1250_wip` @ `aa743c5933560d097d8aa5e833ca10153ed7f6bb` (2026-07-13, "Initial commit for simple gfx1250 enablement"; the source vLLM's gfx1250 base pins) — `diff -r` vs the PyPI 2.8.3.post2 sdist: `flash_attn_triton_amd/utils.py` **L768 the ONLY semantic triton_amd change: is_cdna list + `'gfx1250'`** (plus a `bwd_prefill_fused.py` tweak and added local Dockerfile/README); `__init__.py` `__version__ = "2.8.3"`; releases: **zero** (API) — https://github.com/jpvillam-amd/flash-attention/tree/jpvillam/gfx1250_wip
147. ROCm/aiter @ `fc2e5d57…` (the image's AITER 0.1.20 pin; depth-fetch clone; plus latest main `51ca4216` re-grep) — `aiter/ops/triton/attention/mha.py` L842 `flash_attn_varlen_func` (wraps the vendored `_triton_kernels/flash_attn_triton_amd/{interface_v2,interface_v3,fwd_prefill,fwd_decode,bwd,common,utils}.py`, listing); **`aiter/ops/triton/__init__.py` L97-100 alias map `"mha": "attention.mha"` + L153-189 `__getattr__` + L189 `sys.meta_path.insert(0, …_backward_compat_find_spec)` → `from aiter.ops.triton.mha import …` RESOLVES at the pin**; top-level `from aiter import flash_attn_varlen_func` does NOT resolve (no export — the ROCM_AITER_FA wrapper path is import-dead at this pin, moot on our view); guard strings: 0 hits in BOTH pin and main — https://github.com/ROCm/aiter
148. GitHub issues search API — `q="MAX_PROGRAM_GRID_SIZE"` → `total_count: 0`; `q="total_mblocks" in:body` → 12, all NVIDIA FA3/CuTe split-KV scheduling items (vllm #64058, Dao #2445/#2920/#2926/#2406/#2503, sgl-project #46/#29551, …) — no ROCm/RDNA hit, no such ValueError text anywhere public — https://api.github.com/search/issues
149. magiccodingman/vllm-radiance @ release `5b99d66c` + main `1d2e248` (fresh fetches: release tip UNCHANGED since the pin) — `patch_gfx1201.py` docstring **"gfx1201 (R9700 / RDNA4) platform discovery patch"** + "Do not widen the CDNA AITER gate: that would expose gfx1201 to CK/MFMA/ASM kernels without RDNA device code" + the A0 `RADIANCE_GFX_ARCH`/`VLLM_ROCM_GCN_ARCH` insert into `_get_gcn_arch` ("amdsmi's asic_info 'target_graphics_version' is empty for gfx1201"); `Dockerfile` L228-232 the ENV law `RADIANCE_GFX_ARCH=${GFX_ARCH}` (+PYTORCH/HIP/AMDGPU/GPU_ARCHS), L352 `RADIANCE_USE_R4D=1`; `radiance_vit_attn.py` L1-13 ("On RDNA4 the CK / aiter flash-attention kernels are unavailable … torch SDPA falls back to a non-tiled path that runs at a small fraction of peak"; the r4d head_dim-72 kernel; padding-waste quote) + `install()` L186-209 (gfx12x-gated swap of `vit_attn_wrappers.apply_sdpa`); `patch_r4d.py` L30-36 (the "Triton kernel for vision attention" is radiance's own r4d-era fallback naming; libr4d @ `e8de4bc1` `codeberg.org/StillDeadcode/libr4d` — guard strings 0 hits there too); main VERSION `1.1.0-rc1.vllm0.30.0`, main Dockerfile L101 still `USE_FLASH_ATTENTION=0`, no FA stage/knob in either branch (grep)
150. Docker Hub tags API — `hub.docker.com/v2/repositories/magiccodingman/vllm-radiance/tags/?ordering=last_updated`: `latest`, `sha-5b99d66c844f`, `1.0`, `1.0.397` ALL 2026-10-18T06:35Z (= our pin), next `1.0.394` 2026-10-09 → **no publish newer than the pin**; GitHub API `repos/radiance-rs/vllm-radiance` → `Not Found`
151. magiccodingman/vllm-radiance @ release — `benchmarks/results/20260830T0424Z_mxfp4-rx3/*/manifest.json` (the 0.9.3-era candidates, read locally) — baked container config shows the ENV law in force verbatim (`RADIANCE_GFX_ARCH=gfx1201`, `PYTORCH_ROCM_ARCH=gfx1201`, `GPU_ARCHS=gfx1201`) and the OCI labels `org.opencontainers.image.description = "vLLM inference server for AMD Radeon AI PRO R9700"`, source `gitlab.sayou.io/lance-wright/vllm-radiance` (private) — the publish mirror we read is GitHub
152. [repo] the post-D33 surfaces this round reverses — `charts/vllm/values.yaml` env block L255-296 (19-var law; the FLASH slot absent; `RADIANCE_COMPILATION_CONFIG: '{"cudagraph_mode":"PIECEWISE"}'` L290); `charts/vllm/tests/vllm_testlib.py` L174-211 (`env_want_cf131` = "the D25 19-var … amended by D33"; **L205-211 the exact-set BARS `FLASH_ATTENTION_TRITON_AMD_ENABLE` as a regression entry** — must invert to require it); `chunks/C05.md` L152-158 (marker law `Using Torch SDPA backend for ViT model.` + "a Flash-Attention-Triton line now means the var leaked back" — inverts) and L196 ("its FLASH_ATTN tail needs the upstream flash-attn the…" — becomes satisfied); `chunks/C02.md` L18/L170/L214/L314-317/L378 (19-var exact-set legs — re-pin 20); `containers/vllm-radiance-mxfp4/Dockerfile` (FROM digest + EXPOSE 8000 only — the FA layer inserts above EXPOSE)

## Reliability notes (R5 self-review)

- **High confidence (source @ exact pin):** the tail's binding and
  stub-message branch (fa_utils L47-58 — the "aiter"-vs-"flash-attn"
  message discriminator is a NEW, self-consistent fact: the pod's
  flash-attn wording proves the gfx1201-view at 11:59) [140]; package
  independence from torch + flag semantics + no-compile build (sdist +
  both forks read in-tree) [144][145][146]; the gfx1250 recipe of the
  official base [136]; the 0.30 encoder-graph/compile default-OFF gates
  and Qwen3.5's implement-but-ungated status [142]; the aiter pin's
  backward-compat finder [147]; no-newer-tag / no-FA-in-either-branch
  [149][150].
- **Medium confidence:** the R9700's real Triton-enumerated arch (the
  commission says gfx1250; the image says gfx1201-for-vLLM; both can be
  true of one card — resolved by the 3-line R5-Q3 probe, and the
  recommended pin is safe under either outcome); crash-#2a "cannot be
  resurrected" (strong negative search — five repos, four branches, the
  sdist, both aiter states, plus 0 GitHub issue hits — but absence across
  REACHABLE sources is not metaphysical certainty; if the owner's
  experiment used a private wheel the answer changes — R5-Q2).
- **Low confidence / explicit gaps:** crash #3's provenance (the cited
  file+message exist nowhere public at any vLLM line we could reach —
  including main; we could NOT inspect the maintainer's private
  gitlab.sayou.io tree, and the 1.1.0-rc1 image does not exist publicly
  yet); the exact CI minutes and size delta of the FA layer (no docker
  daemon — `docker-build.yaml` on the pushed branch is the authority,
  cf-77 law); that the Triton-AMD fwd kernel is numerically/
  performance-good at head_dim 72 on our silicon (no public RDNA4 datum;
  the runbook's first-multimodal gate owns it — and radiance's own docs
  call the padded-Triton approach slower than their r4d kernel, which
  runs the SDPA-labelled path — a performance footnote, not a correctness
  one) [149].
- **Weakest claim of the round:** "install deterministically kills #2b"
  rests on the pod's view staying gfx1201 (baked ENV [149][151]) AND the
  var staying TRUE (the 20-var law restoration); either surface drifting
  flips which branch runs (gfx1250-view ⇒ AITER's Triton mha, a DIFFERENT
  unqualified path [139][147]) — the runbook marker lines in R5.3 are the
  guard rail.
- **Perspective weighting:** the pinned trees dominate all secondary
  accounts (R4's method preserved); the owner ruling is authoritative on
  WHAT to do (install) and non-authoritative on the causal story (crash
  #3 framing), which is why R5-Q2 exists.
- **Blind spots (stated):** no GPU session executed anything here — every
  verdict is code-static; the private GitLab candidate line
  (gitlab.sayou.io) is unreadable; `rocm-rel-*` manylinux index probing
  was one-release-deep.

---

# R6 — The KV quant mandate vs the shipped fp8 — the numbers, the real q4 surface, the pool arithmetic (2026-11-09)

Commission: round 6, the fourth on-target crash (crash #4). Post-D35 deploy,
the engine core died AT STARTUP on the vllm-dev pod:
`vllm/v1/core/kv_cache_utils.py:899 _check_enough_kv_cache_memory → ValueError:
To serve at least one request with the model's max seq len (262144), 9.51 GiB
KV cache is needed, which is larger than the available KV cache memory
(1.09 GiB). Try increasing gpu_memory_utilization (which also controls CPU
memory on the CPU backend) or decreasing max_model_len when initializing the
engine` — installed path `/opt/vllm/lib/python3.12/site-packages/vllm`, the
radiance image's prefix, @ vLLM 0.30 @ `ced6857a` [155]. The owner's verbatim
expectation (ruling-grade): **"But on a 32GB GPU, I'm expecting ~18GB for the
model (Q4) and another 4GB per 256k KV (again q4). What I'm seeing is that
you've implemented Q8 and I _need_ q4."**

## TL;DR (5 lines)

- The crash message IS the dtype proof: 9.51 GiB = 8.00 GiB of fp8 KV
  (exactly 262144 tok × 32 KiB at the checkpoint's 16×4×256 GQA geometry) +
  ~1.50 GiB GDN align-mode state + ~0.02 GiB drafter window — the shipped
  `--kv-cache-dtype fp8` was honored; the "Q8" the owner sees is fact [155][156][166][167].
- fp8 KV at 262144 is **arithmetically impossible on this card even with a
  perfect 4-bit load**: best-case pool 28.67 − 20.4 ≈ 8.3 GiB < the 9.51 GiB
  one max-length request demands — D31's live risk, concrete; and the C05 3.6
  int4 gate could NEVER run because boot refuses first (the plan's
  boot-order trap, R6.0) [157].
- 1.09 GiB back-calculates ~27.58 GiB of non-KV consumption vs the ~21.9–22
  "weights + normal overhead" expectation → favors hypothesis (a): weights
  ARE 4-bit, ~5.5–5.7 GiB extra went to profiling peak + CUDA-graph estimate +
  spec/mm extras — a bf16-dequant (b) would have died at LOADING, not at the
  KV check [157][159][160]; the two settling log lines are on the R6.2
  ask-for list.
- The real q4 surface at our pins is STOCK `int4_per_token_head` (16,896
  B/token = 4.125 GiB attention — the owner's "4GB" is exactly the attention
  leg) served ONLY by TRITON_ATTN: R4D refuses it AND `fp8_e5m2` [171]; the
  radiance fork ships NO q4 KV kernel (its NVFP4 program is a weights
  converter [174]); upstream carries three OPEN int4_pth defects, one of them
  the SWA-crash class our 5-layer sliding drafter sits in [168][169].
- Even q4 needs pool surgery: demand 5.63 (4.93 with
  `--mamba-ssm-cache-dtype bfloat16`) vs 1.09 observed → the honest ship
  candidate is the four-edit combo (int4 + TRITON_ATTN + ssm-bf16 + util
  0.95/0.98) + recovering 1.3–3.0 GiB of the mystery overhead; R6-Q1 asks the
  owner to rule the package before the dev pass.

## R6.0 — How fp8 became the ship state (the mandate trace)

1. **Original card (requirement #2):** "KV-q4 default / q8 toggle" — recorded
   verbatim in DECISIONS (Re-scope ruling: "requirements 2 … stand unless the
   re-scope's evidence says otherwise"). The round-1 plan honored it: D2 =
   `kvCacheDtype` default `int4_per_token_head` (the R1 L1.2 v0.33.0 table,
   16.5 KiB/token) on the official-FP8 stock path.
2. **The re-scope to the MXFP4 fork (2026-11-07):** R2 L3.1 — the 0.27.1
   fork's R4D backend **refuses per-(token,head) KV scales at startup**. The
   re-plan's D2-AMEND flipped the default to `fp8` and DEMOTED int4 to
   documented-experimental with the two-edit prerequisites (dtype value +
   `--attention-backend TRITON_ATTN`). The q4 mandate was not dropped — it was
   parked behind an on-target qualification, because the qualified backend
   could not carry it.
3. **Round-2 Q5 ruling (owner override): "QUALIFY INT4 NOW"** → D27 landed the
   int4 acceptance gate into THIS ticket as a day-one runbook step (C05 3.6):
   the two values edits, then startup/1-token/mm/acceptance/quality/tool legs;
   "int4 stays non-default until the gate passes on target … Revert to the
   default after the gate either way (the fp8 default is the ship state — the
   gate is a measurement step, not a config flip)."
4. **Round-3 Q11 override → D31:** engine `--max-model-len` ships at 262144
   (the true axis) with the LIVE owner-ruled risk — "the pool at the 0.90
   start may be small or the engine may compute a degenerate pool" — the
   day-one re-measure gate (3.5) + the 40-min probe + the startup contingency
   as named backstops.
5. **Crash #4 is that risk, in a shape no backstop anticipated:** the engine
   never reaches the day-one gates — the KV BOOT check refuses
   (`needed 9.51 > available 1.09`) and the engine core dies before serving.
   The int4 gate could not be run because running it required booting the
   engine, and booting required the fp8 default it was supposed to replace.
   **The gate design silently assumed the fp8 boot survives; at 262144 on
   32 GiB it mathematically cannot** (R6.1.4). D31's contingency (lower
   max-model-len) is the fp8 path and breaks Q11; the owner's fresh verbatim
   names the other path — q4 — as the requirement, not the experiment.

## R6.1 — The formula, the geometry derivation, the 9.51/1.09 arithmetic

### R6.1.1 — The formula @ ced6857a (the owner's :899 verified)

At the v0.30.0 tag commit (`ced6857a`, tagged 2026-09-21 [178]),
`vllm/v1/core/kv_cache_utils.py` [155]:

- `_check_enough_kv_cache_memory` is DEFINED at L872; the owner's message text
  is assembled at L898–910, and line 899 lands inside that raise block — the
  installed radiance tree carries the overlay's earlier top-of-file edits
  (±few-line drift, the same fully-accounted class as R4 verification-addendum
  V2). The pasted sentence matches the tag's construction modulo truncation.
- `needed_memory = get_needed_memory()` = `max_memory_usage_bytes(vllm_config,
  kv_cache_spec.values())` (L912) = **sum over every layer's spec** of what
  ONE request of `max_model_len` needs — grouped with per-group block
  round-ups. The per-class formulas [156][164][165]:
  - `FullAttentionSpec`: `cdiv(max_model_len, block) × page`,
    page = `num_kv_heads × block × (head_size + head_size_v) × dtype_size`
    ⇒ **attention bytes/token (16 layers) = 2 × 16 × 4 × 256 × dtype_size**;
    at fp8 (1 B) that is 32,768 B/token → 262144 × 32,768 = **8.000 GiB
    exactly** (the block size cancels).
  - `MambaSpec`, align mode (shipped `--mamba-cache-mode align`):
    `page × (2 + num_speculative_blocks + num_prefill_checkpoint_blocks)` —
    **request-FIXED, length-independent**. Page = the GDN state pair at TP1:
    conv `(2·2048 + 6144 = 10240) × (kernel−1 + num_spec = 3+7 = 10)` bf16 =
    204,800 B + recurrent `(48,128,128)` **fp32** (`mamba_ssm_dtype:
    float32` in the checkpoint [166]; `_mamba_state_dtype` auto→float32
    [164]) = 3,145,728 B ⇒ 3,350,528 B per layer-block. `num_spec = 7` is
    read straight from the shipped spec JSON (`GDNAttentionMetadataBuilder`
    [165]) — the number itself proves the dflash K7 config parsed and
    engaged.
  - `SlidingWindowSpec` (the drafter's 5 layers, window 2048 [167]): capped
    at window + in-flight terms, ≈ 129–130 blocks × 32,768 B × 5 layers ≈
    **0.02 GiB**.
- On failure the check runs `estimate_max_model_len` (binary search L925) and
  adds "the estimated maximum model length is X" **only when X > 0** [155].

### R6.1.2 — The forensic detail inside the owner's own paste

The pasted ValueError carries **no** estimated-max-length clause ⇒ the binary
search returned 0 ⇒ **even a 1-token request does not fit**: the fixed floor
(GDN 48 × 3,350,528 × 10 blocks + drafter ≈ 1.51 GiB) already exceeds the
1.09 GiB pool. The pool fell below the model's admission FLOOR, not merely
below the 262144 requirement — the most severe shape of this failure class,
readable for free from the paste. It also means: with `--mamba-ssm-cache-dtype
bfloat16` (floor → ≈0.81 GiB) a q4 boot would finally PRINT the engine's own
capacity estimate — a free probe for the re-measure (R6.3-1).

### R6.1.3 — Which 9.51 proves which dtype AND which geometry

Naive division (9.51 GiB ÷ 262144 = 38.0 KiB/token) misleads — the needed sum
is not linear. Decomposed at the shipped recipe (C02) + fetched configs
[166][167]:

| component | math | GiB |
|---|---|---|
| 16 full-attn layers × 4 KV heads × head 256, **fp8 = 1 B/elem** | 262144 × 32,768 B | **8.000** exact |
| 48 GDN layers, align, fp32 ssm, blocks (2 + 7 + 1) | 48 × 3,350,528 × 10 | 1.498 |
| 5 drafter sliding layers (window 2048, 8 heads, head 128, fp8) | ≈130 × 32,768 × 5 | 0.020 |
| **predicted** | | **9.50–9.52** (±: in-flight term, conv orientation, display rounding) |
| **observed** | | **9.51 ✓** |

Every alternative dtype is off by whole GiB: `auto/bf16` → 16.00 + 1.52 =
**17.52**; `int8_per_token_head`/`fp8_per_token_head` (33,280 B/token) →
**9.64**; `int4_per_token_head` (16,896) → **5.63**; and the naive
"bf16-geometry-only" reads would demand ≥16. So the message uniquely selects
{fp8 at 1 B/elem} × {16×4×256 GQA full attention + 48 GDN fp32-state layers ×
(2+K7+ckpt) + 5×2048-window drafter} — exactly the shipped checkpoint +
shipped DFlash2 drafter + shipped spec config. **The crash message is
therefore machine-level evidence that (i) `--kv-cache-dtype fp8` was HONORED —
the owner's "you've implemented Q8" is correct; (ii) the model geometry loaded
is the one in the staged trees — the MXFP4 checkpoint's own `config.json`
(`num_hidden_layers 64`, `full_attention_interval 4`, `head_dim 256`,
`num_key_value_heads 4` [166]) and the drafter's (`5 × sliding_attention`,
`sliding_window 2048`, 8×128 [167]).**

The full per-token/demand table at this geometry with the flag-existence
columns (CacheDType literal @ ced6857a [161]; TRITON_ATTN
`supported_kv_cache_dtypes` + the 264 B/head packing re-verified in-tree
[163]; R4D list at the fork pin [171]):

| `--kv-cache-dtype` | B/token (16 L) | attn GiB @262144 | total demand | parses @0.30 | R4D (shipped) | TRITON_ATTN |
|---|---|---|---|---|---|---|
| `auto`/`bfloat16` | 65,536 | 16.00 | 17.52 | yes | yes | yes |
| **`fp8`/`fp8_e4m3`** | **32,768** | **8.00** | **9.51 ← the crash** | yes | **yes** | yes |
| `fp8_e5m2` | 32,768 | 8.00 | 9.51 | yes | **refused** [171] | yes |
| `int8_per_token_head`, `fp8_per_token_head` | 33,280 | 8.13 | 9.64 | yes | refused | yes [163] |
| **`int4_per_token_head`** | **16,896** | **4.125** | **5.63** | yes | **refused** | **yes** [163] |
| `turboquant_4bit_nc` | 16,768 [R1 10] | 4.09 | ~5.60 | yes | refused | own backend only |
| `nvfp4*` / `nvfp4_4over6` | — | — | — | literal | no RDNA backend (R1 L1.2) | no |

The GDN/drafter aux is KV-dtype-INDEPENDENT (it is a separate mamba pool at
its own dtypes) — hence the "~4 GB per 256k q4" the owner expects (correct for
attention) carries a hidden +1.5 GiB hybrid-state tax that no KV dtype shrinks
(except by the mamba-ssm-dtype lever below, which halves the GDN half).

### R6.1.4 — The pool side: what 1.09 GiB says was consumed

Worker math @ ced6857a: `requested = ceil(total × util)` [158] =
ceil(31.86 × 0.90) = **28.67 GiB** (the 31.86 visible / 31.46 free constants
are EXPLORE §1's measured pair — and they independently re-derive the 0.9.3
launcher's record that **0.99 asks for 31.54 > 31.46 free and fails at
startup** [158][R2 S L422-425]: on this card 0.98 is the ceiling, not a
choice). `available = requested − non_kv_cache_memory −
cudagraph_estimate_applied − mm_ipc_reserve` [157]; the mm-IPC reservation is
**0 at default** [180] (excluded as a suspect);
`VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS` defaults to **1** — the CUDA-graph
pool is subtracted from the KV budget BEFORE the check [157][159]. Observed
1.09 ⇒ **non-KV ≈ 27.58 GiB**.

| account | expectation | evidence |
|---|---|---|
| MXFP4 target weights, resident-as-packed | 18.41 | the raw-release file [R2 L2.1]; the checkpoint stores `export.weight_format: real_quantized` fp4-group32-e8m0 with ONLY visual/lm_head/mtp/embed bf16-excluded [166] — the file size IS the resident layout (embed 2.36 + lm_head 2.36 + vision ≈0.6 + mtp ≈0.4 bf16 islands inside the 18.41; "pure 4-bit" would be ~13.5 — the owner's 18GB expectation matches the file) |
| DFlash2 drafter | 1.97 | C05 envelope; fp8 e4m3 blockwise [167] |
| non-torch (HIP/ROCm ctx) | 1.15–1.6 | EXPLORE §1 measured class (text-only, pre-spec) |
| profile-run peak + graph estimate | **≈5.5–5.7 (residual)** | unmeasured; candidates below |
| **sum** | **~27.6 = observed** | |

Candidate consumers of the ~5.7 GiB residual (named for the re-measure, none
yet priced): the CUDA-graph ESTIMATE under PIECEWISE + dflash V2 lanes
(real capture happens AFTER sizing — the estimate is a pre-tax [157]); the
multimodal profiling dummy with `{"image": 4}` (ViT peak, bf16 tower); the
`RADIANCE_FAST_DRAFT=1` INT2 head + draft-linear W4 runtime-requant staging
(buffers duplicating the source tensors during conversion [172][175]); the
W4A8 dynamic-activation workspaces; the K7 spec dummy-run itself. **Decisive
regardless of attribution: fp8@262144 needs pool ≥ 9.51 ⇒ non-KV ≤ 19.16 GiB
— less than the weights alone. The fp8 shape is over the cliff even in the
perfect case; the owner's q4 demand is the only dtype class with a path at
the Q11 cap** (bf16 is worse by design; int8/fp8-per-head sits in the same
dead zone as fp8; only the ~16.5-KiB classes go under water-line).

## R6.2 — The weights-residency check: (a) vs (b), and the two lines that settle it

- **(b) in its strong form — "AWQ/Quark dequant landing bf16" — is refuted by
  the failure's LOCATION:** a ~50 GiB bf16 weight set cannot load; the loader
  raises "Failed to load model - not enough GPU memory…" [160] or the startup
  assert fires [158] — the KV check is never reached. Reaching
  `_check_enough_kv_cache_memory` bounds weights+overhead at 27.58 with the
  non-torch+peak floor (≥ ~1.7) ⇒ resident weights ≤ ~25.9 GiB; a
  full-"fp8-intermediate" loader (24.5+2 = 26.5) is already over that bound;
  full bf16 dequant exceeds the card. Also: `quark` and `mxfp4` are both
  REGISTERED quant methods at the tag — an unknown-quant path would RAISE,
  not silently dequant [162]; `RADIANCE_WEIGHT_QUANTIZATION: "auto"` omits
  `--quantization` so the checkpoint's `quant_method: quark` drives loading
  [166]; the MXFP4 W4A8 engagement marker (C05 step-3) rides the same pod log.
- **(b) survives only as loader-duplication variants** (requant/permute
  staging that leaves 21–24 GiB resident) — behaviorally an (a)-neighbour:
  the model is 4-bit, the POOL is small because of loader/profiler mechanics.
- **Which hypothesis 1.09 favors: (a)** — weights ARE 4-bit-ish, the
  overhead ate the pool — at medium-high confidence, one paste short of proof.
- **ASK-FOR list — the owner pastes from the crashed pod's log; every line
  below is emitted BEFORE the ValueError (existence verified at the tag):**
  1. `Model loading took <X> GiB memory and <Y> seconds` — INFO-once,
     `gpu_model_runner.py` L5416 [160]. THE weights datum: ~20.5–21.5 ⇒ (a)
     confirmed; ≳23 ⇒ the (b)-variant loader investigation opens; the drafter
     may emit a second occurrence — paste all.
  2. `Available KV cache memory: <Z> GiB` — INFO-once, `gpu_worker.py` L641
     [157]. THE pool-side datum immediately preceding the crash (expect the
     pasted 1.09 to appear in this very line).
  3. Free same-log corroboration (no re-run): the `non-default args` dump
     (confirms `kv_cache_dtype='fp8'`, `max_model_len=262144`,
     `gpu_memory_utilization=0.9`, the spec JSON), the entrypoint banner +
     the MXFP4 W4A8 GEMM engagement line, and the fork's own
     `[radiance] kv cache groups:` line [172].
  4. For the exact split (weights / non_torch / torch_peak / graph-estimate —
     the `MemorySummary` dataclass carries every field but logs at DEBUG
     [159]): ONE diagnostic re-boot with pod env
     `VLLM_LOGGING_LEVEL: "DEBUG"` added (values-side, removable, NOT ship
     shape) — fold it into the 3.5 gate day.
  5. Optional host-side, owner-run (the repo's no-agent-pod-exec rule):
     `rocm-smi --showmeminfo vram` sampled during the load window; and the
     read-only staged-tree dtype check inside the container — parse the
     safetensors header of `/models/Qwen3.8-27B-Quark-AWQ-MXFP4/model.safetensors`
     and print the distinct dtype set: packed fp4/uint8 payloads + fp8/e8m0
     scales + BF16 for exactly the 127 excluded tensors [166]; any surprise
     large BF16 *linear* set = the (b)-variant on disk (not loader).

## R6.3 — The honest options to deliver q4-KV at 262144 on 32 GiB

Demand recap: `needed = attn + aux`, aux = 1.52 GiB (GDN fp32 + drafter) or
0.81 GiB with `--mamba-ssm-cache-dtype bfloat16` [161][164]. Supply recap
(observed non-KV held): pool(u) = ceil(31.86·u) − 27.58 → **1.09 @0.90, 2.69
@0.95, 3.64 @0.98** (0.99 fails at startup [158]).

### Option 1 — the real q4: `int4_per_token_head` on TRITON_ATTN (D27's two-edit, promoted to the default)

- **Ship-surface literals** (`charts/vllm/values.yaml`, the sanctioned
  values-only pair of C05 3.6 + its T3/testlib/AC8 re-pins, exactly the D27
  documented surface):
  - `kvCacheDtype: &kvCacheDtype int4_per_token_head`
  - serveArgs: `- "--attention-backend" - "TRITON_ATTN"` (replacing `"R4D"`;
    the CLI's named backend wins over the baked seam [171], GDN kernels stay)
  - stack-mate: `- "--mamba-ssm-cache-dtype" - "bfloat16"` (aux −0.71)
  - stack-mate: `- "--gpu-memory-utilization" - "0.95"` (0.98 for the last
    1.6 GiB; the R3-Q2 start + the recorded 0.85/0.98 alternatives make this
    a values decision, not a flag-surface risk)
- **Flags exist:** int4_pth parses @ 0.30 [161]; TRITON_ATTN lists it
  (264 B/head packing verified in-tree [163]). R4D refuses it AND `fp8_e5m2`
  [171] — the values comment "bf16/auto/fp8 qualified on R4D" survives; the
  per-token-head family + e5m2 are TRITON-only territory (comment correction
  rides).
- **Arithmetic:** demand 5.63 (or 4.93 w/ ssm-bf16) vs 1.09 observed — does
  NOT boot at today's overhead; pool-vs-cap: @0.95 int4 boots to ≈75k ctx
  (120k w/ ssm-bf16); @0.98 ≈135k (≈180k) — below the 262144 cap, so the
  engine would PRINT its estimate instead of dying silently [155]. To boot AT
  262144: recover 1.3–3.0 GiB of the R6.1.4 residual (ssm-bf16 + 0.98 are 2.0
  of it; the rest = a cheaper profile: `{"image": 4}`→`{"image": 1}` for the
  profile day, or `RADIANCE_FAST_DRAFT=0`, or the mtp lane) — the day-one 3.5
  re-measure owns the verdict.
- **Support state (ROCm/RDNA) + accuracy/perf:** upstream int4_pth is BETA —
  three OPEN defects at our tag: write-kernel wrong-values flakers (#53086,
  filed pre-tag, unfixed; head-64/128 shapes fail, head-256 unenumerated)
  [168]; the **SWA crash class** (#48721 open; fix PR #48842 UNMERGED — our
  drafter IS 5 sliding layers) [169]; the RHT first-use sync guard (#62946
  unmerged, enforce-eager trigger — inert for our PIECEWISE pod) [170]. AMD's
  own 4-bit-KV productionization is CDNA/LMCache, not RDNA4 in-engine
  [176][177]. The fork adds NO q4 KV kernel [174][175]. Accuracy: per-token
  fp32 scale + RHT 4-bit (R1 L1.2 [4]); the gemma-4 fix-PR's own eval shows a
  −9.2pp gsm8k move at a 256-dim head [169] — the C05 3.6 quality leg (GSM8K
  class) and tool leg (the 30/30 record is fp8-KV-only [108]) were written
  for exactly this promotion and bind. Perf: R4D→TRITON_ATTN moves the target
  attention onto Triton's unified kernel — #54438-class data measured TRITON
  +1.28–10.74× vs ROCM_ATTN at head 256 on RDNA [26], but vs radiance's
  hand-written R4D the delta is UNMEASURED; the 186.7 tok/s anchor is an
  R4D+fp8 lane — re-bench at step 6, expect movement.
- **Risk ladder:** startup refusal persists (loud, probe-gated, the
  estimated-length line prices the fallback); the SWA-int4 class crashes at
  layer-build (also startup-loud — 3.6 leg-1 catches it); accuracy/tool drift
  (3.6 legs). **Best guess: the option** — the only dtype class under the
  physical ceiling at 262144, the owner's literal mandate, and this ticket
  already ships its acceptance gate verbatim.

### Option 2 — fp8 KV + reduced max-model-len (CONTRADICTS the Q11/D31 ruling — priced honestly)

- At the observed non-KV: **no ctx fits @0.90** (pool < fixed floor — exactly
  the silent-rejection shape seen); @0.95 fp8 boots to ≈**38k**; @0.98
  ≈**70k**; ssm-bf16 buys fp8 only ≈ +20k (aux 1.52→0.81, attention unchanged
  at 32 KiB/token).
- Shipping it = the D31 "only legs that move": the serveArgs max-model-len +
  the dflash JSON `max_model_len` + the testlib pair + the T3 d12 dict — and
  the catalog 262144 advertisement goes FALSE again (the D28 band-law
  resurrection; the true-axis note dies; a fresh owner ruling per D31(e)).
- **Best guess: rejected as the primary** — ≤70k on a card the owner is
  asking to serve 262144, while the owner's own q4 demand exists verbatim.
  It is the D31 contingency shape ONLY if Option 1's boot math refuses.

### Option 3 — weights-side fixes (lives or dies on the R6.2 paste)

- Paste ≈ 20–21 ⇒ (b) CLOSED; nothing weights-side; the residual is
  profile/graph/spec-side and Option 1's stack-mates own it.
- Paste ≳ 23 ⇒ loader investigation on the fork's seams (W4A8 runtime-requant
  staging, `RADIANCE_MXFP4_WPERM` permute copies, fast-draft buffers
  [172][175]) — upstream maintainer territory; could recover the 1.3–3 GiB
  without util or ssm surgery and make int4@262144 comfortable.
- **Best guess: 4-bit residency confirmed — keep the ask, expect closure.**

### Option 4 — util raise 0.90 → 0.95/0.98 (a contributor, never a solution)

- Buys exactly 0.05/0.08 × 31.86 = **1.59/2.55 GiB**; 0.99 is startup-dead on
  this card [158]; alone fits nothing (fp8 needs +8.4 over observed pool,
  int4 +4.5). As an Option-1 stack-mate it is essential; the startup assert
  keeps any over-commit loud (pod fails at startup — the D31 backstop class
  intact).

### Option 5 — adjacent surfaces, priced and NOT the answer

- `--kv-offloading-size` / `RADIANCE_KV_OFFLOADING_SIZE`: the fork's own 256K
  baseline says it is an **external prefix-cache tier, not extra live GPU KV
  capacity** [173] — the boot check is GPU-side, so it cannot even silence
  crash #4; it makes admitted long prefixes cheap to restore (58.1 vs 60.2
  tok/s). Keep as the runbook's post-boot relief valve.
- mtp K4 lane (drop the 1.97 GiB drafter; num_spec 7→4 shrinks the GDN page +
  blocks): non-KV −~2.0–2.3, demand −0.45 — a real margin donor for Option 1
  at the price of the 29/30 tool-gate-FAIL caveat [108] + the
  `RADIANCE_QUARK_BF16_MTP=1` coupling; values-only.
- `turboquant_4bit_nc`: 4.09 GiB attention — same capacity class, needs its
  own TURBOQUANT backend (in 0.30's ROCm priority list [102] but with zero
  radiance qualification and CDNA-centric upstream work [176][177]) — more
  unknowns than Option 1, no capacity win. Not recommended.

## R6.4 — The ONE owner question

**R6-Q1 — the q4 package ruling (one question, three answers).** fp8@262144 is
proven arithmetically dead on 32 GiB (9.51 needed > the ~8.3 GiB best-case
pool — and the observed pool is 1.09). Which ship shape do you rule?
**(A — recommended):** q4-default = the Option-1 combo (int4_per_token_head +
TRITON_ATTN + ssm-cache bfloat16 + util 0.95-or-0.98), boot at 262144 and let
C05's 3.5 re-measure + the 3.6 int4 gate (whose legs were written for exactly
this promotion) qualify on target — residual risk: the three open upstream
int4 defects + the unrecovered-overhead margin question, both loud-at-startup
classes;
**(B):** same q4 edits, but pre-emptively cap `--max-model-len` at the engine
estimate (the likely ~120–180k without overhead recovery) — re-breaks the
Q11/D31 true axis (your call on the catalog);
**(C):** keep fp8 as the default ONLY at a ≤70k cap (the D31 contingency
branch) and move the q4 mandate to the future 48 GiB card (the OQ3 ledger
note).
Recommendation: **(A)**, falling through to **(B)** on the engine's own
printed estimate; and please send the R6.2 paste (items 1–2) first so the
weights-side is closed on evidence, not on arithmetic bounds.

## Contradictions and how to weigh them (R6 conflict map)

1. **Owner's arithmetic model vs the hybrid engine's:** "4GB per 256k KV
   (again q4)" is right for the attention pool; the GDN hybrid state (+1.5
   GiB/request, KV-dtype-independent) + the drafter window are invisible to a
   transformer-only reading. Weigh: the engine formula at the shipped pin
   [155][156] + the fetched configs [166][167] are the authority — the demand
   is satisfiable, but at ~4.9–5.6, not 4.0.
2. **C05's ship law ("the fp8 default is the ship state — the gate is a
   measurement step") vs crash #4:** the boot check inverts the dependency —
   measurement requires boot, fp8 boot at 262144 cannot happen. The plan text
   is superseded by physics + the fresh ruling-grade demand; Option 1 makes
   the gate the boot config.
3. **Round-2 Q5's "int4 stays non-default until the gate passes" vs "QUALIFY
   INT4 NOW":** the ruling always intended a day-one flip on PASS; crash #4 is
   the gate's leg-0 failing for FP8 (startup acceptance), not for int4. Weigh
   Option 1 as the sanctioned continuation, not a scope break.
4. **R1's int4-quality comfort (v0.33 table, "MTP-safe by negative evidence")
   vs R6's three open defects:** the upstream state DEGRADED between the two
   reads (#53086 Aug, #48721 Jul, fix PRs unmerged). Weigh: pinned-source
   truth at our tag [163] + open-issue state [168][169][170]; the 3.6 quality
   leg is the local authority — the round-1 comfort note is historical.
5. **radiance publishes a working 256K-fp8 reference; our TP1 dies on it:**
   their runs are TP2 (weights + state + attention all halve per GPU) [173] —
   nobody has published this shape at TP1 (R3 L2.4 law persists). Weigh as:
   their numbers are calibration-class, never a TP1 feasibility promise.
6. **"Model resident ≈18GB (owner) vs 27.58 consumed (log)" is NOT
   contradiction #5 but the whole R6.2 open loop — pending the paste.**

## Implications for the plan

- An R6-Q1 answer of (A)/(B) is a fresh values+test pass, not a re-scope: it
  moves exactly the D27/D31-marked surfaces — the `kvCacheDtype` default, the
  `--attention-backend` pair, a new `--mamba-ssm-cache-dtype` pair, the util
  literal, the testlib recipe pairs + the C05 T3 d12 dict + AC8/AC7 comments
  (fp8 demotes to "documented toggle"), the kvCacheDtype key comment (int4
  promoted, the gate legs reworded from "flip and measure" to "shipped and
  qualify"), and DECISIONS entries superseding D27's default posture + D31's
  risk statement resolution. The coordinator/plan own those surfaces — this
  round wrote nothing outside RESEARCH.md.
- The 3.5 gate acquires a hard PASS/FAIL bar derivable from public code:
  pool ≥ demand-by-dtype (the R6.1.3 table) — and the engine now prints its
  own estimate whenever the fixed floor fits (ssm-bf16 changes silence into a
  number [155] — free calibration).
- The runbook's util story gains a verified ceiling fact: 0.99 is
  startup-dead on this card (31.54 > 31.46 free) [158]; 0.98 is the recorded
  max-start.
- The tool-accuracy story: if q4 ships as the default, the C04 `tools: true`
  marker's grounding sentence ("the 30/30 record is fp8-KV-only") becomes a
  live re-qualification dependency, not a caveat footnote — 3.6's tool smoke
  gate is the marker's lease.

## Open questions (no-questions-rule log — round 6, for coord → owner/plan)

- **R6-Q1** (the single question, with options + recommendation) — see R6.4.
- Not blocking it: the R6.2 ask-for paste items 1–2 (settle (a) vs (b)),
  item 4 (decompose the 27.58), item 5 (close the on-disk format story).
- Carried: R5-Q2 (the crash-#2a ValueError provenance) stays OPEN untouched;
  R5-Q3 CLOSED (D35). D35's "day-one gates 3.5/3.6/3.7 unchanged" provision is
  what this round reports as UNEXECUTABLE in the fp8 order — the gate order
  itself (boot first, then flip) is the process finding.

## Sources (R6)

All reads 2026-11-09 at the exact pins: vLLM @ v0.30.0 = `ced6857a` (tag
commit 2026-09-21T22:32Z [178]); radiance @ `5b99d66c844fd0a54e4a7eb93b40a1ece009a53d`;
HF revisions `93245f7c…` (target) / `ee0cb26a…` (drafter).

155. vLLM v0.30.0 @ ced6857a — `vllm/v1/core/kv_cache_utils.py` — `_check_enough_kv_cache_memory` L872, message assembly L898–910 (the owner's :899 lands in the raise; overlay line-drift class of R4-V2), `estimate_max_model_len` clause gated on > 0; `check_enough_kv_cache_memory` L976–1009 (null-block reservation, per-layer spec sum); `max_memory_usage_bytes` L912; `estimate_max_model_len` binary search L925–968; second call site L2737 — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/core/kv_cache_utils.py
156. vLLM v0.30.0 @ ced6857a — `vllm/v1/kv_cache_interface.py` — `KVQuantMode` L39–134; `num_states = block_size // tokens_per_state` L192–198; `AttentionSpec` page algebra L479–537; `FullAttentionSpec.max_memory_usage_bytes` L559–566; `SlidingWindowSpec.max_admission_blocks_per_request` (window + extra_retained + in-flight) L620+; `MambaSpec` L993–1052 — align: `page × (2 + num_speculative_blocks + num_prefill_checkpoint_blocks)`; `tp_replicated` (GDN shards) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/kv_cache_interface.py
157. vLLM v0.30.0 @ ced6857a — `vllm/v1/worker/gpu_worker.py` — `requested_memory` L452; `determine_available_memory` L528–685: `available = requested − non_kv_cache_memory − cudagraph_estimate_applied` (L621), `kv_cache_memory_bytes` skip-profiling branch L542–561 (the D24 lever: "does not respect gpu_memory_utilization"), ROCm profiling fallback L596–611, `Available KV cache memory: %s GiB` INFO-once L641, graph-estimate util-equivalence advisories L645–683 — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/worker/gpu_worker.py
158. vLLM v0.30.0 @ ced6857a — `vllm/v1/worker/utils.py` — `request_memory` L534–554: `requested = ceil(total_memory × util)` + the "Free memory on device (X/Y GiB) on startup is less than desired GPU memory utilization" raise. Cross-check: 0.99 × 31.86 = 31.54 > 31.46 free ⇒ the 0.9.3 launcher's "0.99 asks 31.54 and fails at startup" record re-derives on identical constants — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/worker/utils.py
159. vLLM v0.30.0 @ ced6857a — `vllm/utils/mem_utils.py` + `vllm/envs.py` — `MemorySnapshot` (non_torch = cuda − torch, L159), `MemorySummary` fields + `format_gib = round(b/GiB, 2)` L31 + the summary line L219–224 (weights/non-torch/peak decomposition, DEBUG-level); `VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS` default **1** (envs.py L317, L2109) — the graph pool is pre-deducted from the KV budget — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/utils/mem_utils.py + …/vllm/envs.py
160. vLLM v0.30.0 @ ced6857a — `vllm/v1/worker/gpu_model_runner.py` — `Model loading took %s GiB memory and %.6f seconds` INFO-once at L5416–5418 (`model_memory_usage` = loader torch delta); the OutOfMemory except-branch "Failed to load model - not enough GPU memory…" L5405 — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/worker/gpu_model_runner.py
161. vLLM v0.30.0 @ ced6857a — `vllm/config/cache.py` — `CacheDType` = the 18-value literal L39–58 (auto/float16/bfloat16/fp8/fp8_e4m3/fp8_e5m2/fp8_inc/fp8_ds_mla/nvfp4_ds_mla/turboquant_{k8v4,4bit_nc,k3v4_nc,3bit_nc}/int4_per_token_head/int8_per_token_head/fp8_per_token_head/nvfp4/nvfp4_4over6) — re-verified identical to R3's [101]; `MambaDType auto|float32|float16|bfloat16` L61; `MambaCacheMode all|align|none` L62; `KVOffloadingBackend native|lmcache` L64 — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/config/cache.py
162. vLLM v0.30.0 @ ced6857a — `vllm/model_executor/layers/quantization/__init__.py` — registered methods L16–48 include `quark` AND `mxfp4`/`gpt_oss_mxfp4`; unregistered names RAISE at L112–113 — no silent-dequant fallback exists at this tag — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/model_executor/layers/quantization/__init__.py
163. vLLM v0.30.0 @ ced6857a — `vllm/v1/attention/backends/triton_attn.py` — `customize_spec` L275–288: INT4_PER_TOKEN_HEAD ⇒ `(hs_k//2 + hs_v//2) + 2·fp32-scale` = 264 B/head at head 256 (the R1 L1.2 derivation in-tree); `supported_kv_cache_dtypes` L294–304 incl. int4/int8/fp8_per_token_head; `supports_head_size ≥ 32` L351; kernel `triton_reshape_and_cache_flash_per_token_head_quant` import L40 + decode branch L609; no ROCm exclusion on the quant path (the aiter rope-and-cache branch is AITER-env-gated, L804/827) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/attention/backends/triton_attn.py
164. vLLM v0.30.0 @ ced6857a — `vllm/model_executor/layers/mamba/mamba_utils.py` + `.../mamba/gdn/qwen_gdn_linear_attn.py` — `gated_delta_net_state_shape` L274–296 (conv_dim = 2·key_dim + value_dim = 10,240 @TP1; conv slots = kernel−1+num_spec; temporal (48,128,128)); `gated_delta_net_state_dtype` L122+ (`auto` ssm → float32); model wiring reads `linear_num_key_heads/linear_num_value_heads/linear_key_head_dim/linear_value_head_dim/linear_conv_kernel_dim` + `num_spec` — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/model_executor/layers/mamba/mamba_utils.py + …/qwen_gdn_linear_attn.py
165. vLLM v0.30.0 @ ced6857a — `vllm/v1/attention/backends/gdn_attn.py` — `GDNAttentionMetadataBuilder` L97–116: `num_spec = speculative_config.num_speculative_tokens` (the K7 → the conv+spec-block inflation inside 9.51; the spec JSON demonstrably parsed); `decode_cudagraph_max_bs = max_num_seqs × (K+1)` (the graph-estimate's spec shape) — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/v1/attention/backends/gdn_attn.py
166. HF `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` @ `93245f7c00f1a8964b66a97c6e02e2fd09080be4` — `config.json` (fetched) — `num_hidden_layers 64`, `full_attention_interval 4`, `head_dim 256`, `num_attention_heads 24`/`num_key_value_heads 4`, `linear_num_key_heads 16`/`linear_num_value_heads 48`, `linear_{key,value}_head_dim 128`, `linear_conv_kernel_dim 4`, `mamba_ssm_dtype float32`, `mtp_num_hidden_layers 1`, vocab 248320, `tie_word_embeddings false`; `quantization_config`: `quant_method: quark`, fp4 weights group32 + `scale_format e8m0` (MXFP4), `export.weight_format: real_quantized`, `export.pack_method: reorder`, `kv_cache_quant_config {}` (no baked KV scales), `exclude` = 127 entries: all `model.visual.*` + `lm_head` + `mtp.*` + embeds (the bf16 islands ≈ 5.7 GiB inside the 18.41 GiB file; "pure 4-bit" would be ≈13.5 — the owner's "~18GB" matches the file, both readings reconcile) — https://huggingface.co/amd/Qwen3.8-27B-Quark-AWQ-MXFP4/raw/93245f7c00f1a8964b66a97c6e02e2fd09080be4/config.json
167. HF `tcclaviger/Qwen3.8-27B-DFlash2-FP8` @ `ee0cb26a…` — `config.json` (fetched) — `DFlash2DraftModel`: `num_hidden_layers 5`, `layer_types = sliding_attention ×5`, `sliding_window 2048`, `num_key_value_heads 8`, `head_dim 128`, `max_position_embeddings 262144`, fp8 e4m3 blockwise [128,128], `dflash_config {block_size 8, target_layer_ids [5,19,33,47,61], selector_top_k 16}` — https://huggingface.co/tcclaviger/Qwen3.8-27B-DFlash2-FP8/raw/ee0cb26a8279b7910cc28d82a8a3e15e4728d56f/config.json
168. vLLM issue **#53086** — OPEN, filed 2026-08-20 (one month BEFORE the v0.30.0 tag; still open at this read): "int4 per-token-head KV cache: triton_reshape_and_cache_flash_per_token_head_quant returns wrong values" — deterministic 54.7% round-trip mismatch at [int4, block16, head64, 1kv, 42tok] + flaky combos (NVIDIA-H200 repro on main; all int8/fp8 pass; head-256 unenumerated) — https://github.com/vllm-project/vllm/issues/53086
169. vLLM issue **#48721** (OPEN, 2026-07-15): "v0.25.1 int4_per_token_head crashes with SWA models" + fix PR **#48842** (created 2026-07-16, **UNMERGED** — `merged_at: null` at this read; authored against gemma-4's head dims 256/512 + the stride-mismatch crash; its eval table shows gsm8k bf16 0.6535 → int4-pth 0.5618, a −9.2pp datum) — bears directly on our 5 sliding drafter layers and the 3.6 quality leg — https://github.com/vllm-project/vllm/issues/48721 + https://github.com/vllm-project/vllm/pull/48842
170. vLLM PR **#62946** (created 2026-10-21, **UNMERGED** — post-v0.30.0): "[Bugfix][Attention] Allow the one-time sync when building INT4 RHT signs" — the `_get_rht_signs` CPU→GPU first-use copy trips `VLLM_GPU_SYNC_CHECK` under enforce-eager; seen in **amd-ci** (MI300X); inert for our non-eager PIECEWISE pod — https://github.com/vllm-project/vllm/pull/62946
171. magiccodingman/vllm-radiance @ `5b99d66c844f` — `radiance_r4d_attn.py` **L220**: `supported_kv_cache_dtypes = ["auto", "bfloat16", "fp8", "fp8_e4m3"]` — R4D at the shipped pin refuses int4_pth AND **fp8_e5m2** (the R3 L2.2 record re-verified at source); `patch_r4d.py` docstring — backend opt-in by name; `RADIANCE_USE_R4D=0` declines every hook (GDN prologue included); `--attention-backend TRITON_ATTN` therefore moves ONLY the target attention, the GDN kernels stay — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/radiance_r4d_attn.py + …/patch_r4d.py
172. Same pin — `patch_kv_group_size.py` docstring — the fork's own bucket table: "**48 linear_attention (GDN, MambaSpec) / 16 full_attention / 5 drafter (SlidingWindowSpec, window 2048)**"; per-request group costs "a full-attention group costs 160 blocks, a GDN group costs **2 + num_speculative_blocks = 9**, and the drafter's sliding-window group costs 8" (their TP2 frame — R6.1.3 is the TP1 translation); live-log witnesses `kv_cache_utils.py:1261 Add 2/4 padding layers…` + `:2235 GPU KV cache size: 739,544 tokens`; knobs `RADIANCE_KV_GROUP_OPT/SIZE/MAX_GROUPS` — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844f/patch_kv_group_size.py
173. Same pin — `docs/ROCM_KV_OFFLOAD_LONG_CONTEXT_BASELINE.md` — native CPU KV offload is "a fast **external prefix-cache tier, not extra live GPU KV capacity**"; the reference envelope is **TP2, 90% allocation, FP8 KV, 256K limit** (why the maintainers never met crash #4 — weights+state+attention all halve per GPU); restore 58.10 vs local-hit 60.20 tok/s; "`max-num-seqs=4` is an admission ceiling, not a promise that four maximum-length sequences fit on GPU" — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844f/docs/ROCM_KV_OFFLOAD_LONG_CONTEXT_BASELINE.md
174. Same pin — `docs/V030_GGZ14_MXFP4_NVFP4.md` — the fork's NVFP4 program is a WEIGHTS converter (`RADIANCE_NVFP4_MXFP4=1`, default-off, fail-closed A16, both-R9700 native fixtures); **no 4-bit KV kernel surface exists in the fork**; `.env.example` L23–38 — `RADIANCE_KV_OFFLOADING_SIZE` "Keep disabled unless long-context", `RADIANCE_FP8_KV_SCALES` (calibrated FP8 sidecar) — their quality investment is fp8-KV, not q4; the full entrypoint `RADIANCE_*` list carries no KV-dtype knob — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844f/docs/V030_GGZ14_MXFP4_NVFP4.md + …/.env.example + …/radiance_entrypoint.sh
175. [carry] ship-state ground audited: C02 serveArgs/env (fp8 default, R4D, 262144, util 0.90, dflash K7 JSON, `{"image": 4}`, PIECEWISE, the 20-var law), C03 staging (the two revision pins), C05 3.5/3.6/3.7 gate text + the startup contingency, DECISIONS D2/D2-AMEND/D24/D25/D27/D31, R1 L1.2/L1.5 (per-token table + the 31.86/1.15/0.54 measured classes), R2 L3.1 + [S L422-425] (the 0.98/0.99 launcher records), R3 [101][102][103][108]
176. AMD ROCm blogs — "Productionizing TurboQuant on AMD GPUs for KV-Cache Agentic Workloads" (TurboQuant KV on AMD, fork snapshot `3cc38a1b`, MI-series) + "4-bit KV Caching in LMCache … on AMD MI355X" (offload-connector 4-bit KV) — AMD's public 4-bit-KV maturation is CDNA + LMCache-connector territory, not RDNA4 in-engine — https://rocm.blogs.amd.com/artificial-intelligence/turboquant-vllm-agentic/README.html + https://rocm.blogs.amd.com/software-tools-optimization/4bit-KV-LMcache/README.html
177. vLLM issue **#38171** (the TurboQuant support thread) + the #53299 docs thread — upstream TQ dtype-family status context; third-party TQ ports (NVIDIA GB10 forum, Intel 32-GB blog) corroborate the 16.4-KiB class exists; no RDNA4 in-engine qualification anywhere public — https://github.com/vllm-project/vllm/issues/38171
178. GitHub API — `repos/vllm-project/vllm/git/ref/tags/v0.30.0` → `ced6857afa0ea7b2e3f0846a62e1394e90f15607`; commit date **2026-09-21T22:32:49Z** — fixes the timeline reads on #53086 (pre-tag-open) and #62946/#48842 status — https://api.github.com/repos/vllm-project/vllm/git/ref/tags/v0.30.0
179. GitHub search API — `repo:vllm-project/vllm int4_per_token_head` → total_count 38; the family's live-beta texture at this moment: #51691 (offload-certification for per-token-head layouts, open PR), #65815 (quantized-cache KL benchmark, open PR), #63081 (first-layer key-bias startup warning, open PR), #59674 (int4 key-bias fix, open) — https://api.github.com/search/issues
180. vLLM v0.30.0 @ ced6857a — `vllm/config/multimodal.py` L244 (`mm_ipc_gpu_memory_gb: Field(default=0)`) + `vllm/multimodal/gpu_ipc_memory.py` `reserve_mm_ipc_gpu_memory` L155–185 — the frontend mm reservation is **0 at default**: the pool shrink is NOT mm-IPC — https://raw.githubusercontent.com/vllm-project/vllm/v0.30.0/vllm/multimodal/gpu_ipc_memory.py
181. magiccodingman/vllm-radiance @ `5b99d66c844f` — `Dockerfile` (fetched fresh at this write, R6.5) — L195 "Only the resulting /opt/vllm venv is carried into the release image", **L205 `ENV VIRTUAL_ENV=/opt/vllm`**, L206 `RUN python3 -m venv /opt/vllm`, L207 `ENV PATH=/opt/vllm/bin:$PATH`, **L208 `ENV SP=/opt/vllm/lib/python3.12/site-packages`**, L302 the `.so` pruning law inside that venv — the paste path of crash #4 is this tree; the D34/D35 flash-attn pip layer lands in the same SP — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/Dockerfile

## Reliability notes (R6 self-review)

- **High confidence (source @ exact pins):** the needed-memory formula and the
  fp8/geometry attribution of 9.51 [155][156][164][165][166][167] — the
  decomposition is predicted from public code + fetched configs and lands on
  the observed value at display precision while every alternative dtype is
  off by whole GiB (robust discrimination); the missing-estimated-length
  forensic [155]; R4D's dtype refusals incl. the `fp8_e5m2` surprise [171];
  int4_pth exists at the CLI + TRITON_ATTN [161][163]; the dequant-(b)
  refutation-by-failure-location [160]; the 0.99-ceiling re-derivation [158];
  the fork's 48/16/5 bucket table [172]; "offload = tier, not capacity"
  [173]; graph-estimate pre-deduction default-ON [157][159].
- **Medium confidence:** the exact 1.52-aux split (±0.02 GiB: in-flight term,
  conv orientation — immaterial to the verdict); the (a)-lean at 1.09
  (bounded arithmetic, not measurement — the R6.2 paste closes it); the
  pool-vs-cap table (it holds non-KV constant at 27.58; changing the spec
  lane/mm limit/backend moves it — directionally right, magnitudes pending
  re-measure); int4 accuracy at THIS model (the −9.2pp datum is a different
  model class [169]; the 3.6 quality leg owns ours).
- **Low confidence / explicit gaps:** whether the SWA+int4 crash class still
  bites at v0.30.0 with our drafter (unverified claim; the 3.6 startup leg is
  the detector); whether 1.3–3.0 GiB of overhead is recoverable in practice
  (zero measured decomposition; the DEBUG re-boot is the cheap step);
  TRITON_ATTN-vs-R4D perf at head 256 (no public datum; step 6 re-bench owns
  it); no GPU session executed anything — every verdict is code-static; the
  private GitLab radiance line stays unreadable [R5 precedent].
- **Weakest claim of the round:** "q4@262144 is achievable at ALL" — it
  rests on overhead recovery to a 4.9–5.6 GiB pool AND the int4 write path
  being correct at head_dim 256 on gfx1201 with sliding draft layers; two of
  the three legs have open upstream defects and zero public RDNA4 data.
  Stated plainly: the honest ship sentence is "q4-default per the owner's
  ruling; 262144 is the BOOT GOAL and the day-one gate's pool line is the
  verdict; ~120–180k is the arithmetic-blessed fallback band at 0.95–0.98
  without further surgery."
- **Perspective weighting:** the engine's own formula + the fetched configs
  outrank every narrative (the owner's mental model, the plan's gate design,
  the fork's TP2 publications); the owner's ruling is authoritative on WHAT
  (q4), the sources on whether-physics (R6.1.3/4).
- **Blind spots (stated):** the measured non-KV decomposition at our shape
  (graph estimate vs mm profile vs fast-draft staging — the DEBUG re-boot);
  the TP1 drafter-group accounting (the fork's cost table is TP2-framed
  [172]); int4-pth numerical behavior on GDN-hybrid + spec-recompute paths
  (only the on-target 3.6 legs answer); prefix-caching's
  `num_prefill_checkpoint_blocks` term folded into the 10-block estimate
  without a source-verified assignment site.

### R6.5 — coordination addendum (2026-11-09T16:1xZ, the coordinator): D35 landed by the owner on main; the pod path prefix is the base image's

- **(a) The R6 evidence arrived with the owner's FIRST post-D35 deployment
  already running.** The D35 flash-attn install is LANDED on main by the
  owner's own hand: `ac8a65c98`, authored Spencer 2026-11-09T15:40:58Z, the
  single squash carrying the run's shipped files including the records
  commit's (run tip `4936564b6`; byte-identity verified at this write —
  `git diff 4936564b6 ac8a65c98` EMPTY over every cf-131 shipped surface:
  the container dir, the chart, the container + runbook suites, the service
  values twin, the catalog file; the 29-file tree delta sits wholly in other
  tickets' main-side drift). CI republished `:main` with the FA layer: the
  D35 amendment review's container-suite run 2 showed the LIVE t7 MATCH —
  the AC6 flash-attn-import bar discharged on registry evidence.
- **(b) Crash #4's stack path is the BASE IMAGE's own vLLM prefix.** The
  pasted `/opt/vllm/lib/python3.12/site-packages/vllm` is the magiccodingman
  base image's install tree — its Dockerfile builds the venv explicitly
  there: `ENV VIRTUAL_ENV=/opt/vllm`, `RUN python3 -m venv /opt/vllm`,
  `ENV SP=/opt/vllm/lib/python3.12/site-packages` [181] — the radiance fork
  ships vLLM unpackaged at `/opt/vllm`, NOT a system pip vLLM. Every fork
  patch operates inside that same tree (`sysconfig.get_paths()["purelib"]`
  anchors, [172]), and the D34/D35 flash-attn pip layer installs into that
  same SP — so the paste independently corroborates the D34/D35 install
  stack it was produced by.
- **(c) Consequence for R6's verdict:** the "shipped fp8 honored" finding —
  and the whole 9.51/1.09 arithmetic it anchors — was tested on the CURRENT
  image. No stale-artifact doubt attaches to crash #4: the pod that died
  was running the post-D35 `:main`.

---

# R7 — F1: the kv-cache grouping

## R7. F1 — the kv-cache grouping: where the 8 comes from, what it wastes, what knob is real

(The owner's directive round: crash #4's `[radiance] kv cache groups: size 8, 9 groups,
378 blocks/request (upstream would pick size 5)` @ `kv_cache_utils.py:1477` and
`WARNING kv_cache_utils.py:1617 Add 3 padding layers, may waste at most 60.00% KV
cache memory` are ACCEPTED REAL MECHANICS; this round is C05 3.5(f1) — the named
investigation, executed off the pinned trees, no GPU session.)

### R7.0 TL;DR (5 lines)

- Both pasted strings are reproduced EXACTLY from the pinned trees: the fork's
  `patch_kv_group_size.py` helper + upstream's un-padded warning math on our
  [48 GDN, 16 FA, 5 drafter-SWA] bucket mix — and the line numbers themselves
  (`:1477`, `:1617`) match a reconstructed installed tree (upstream @ ced6857a
  + the two overlay edits) to the line, proving which code the crashed pod ran [182][189][190][191][195].
- The 60.00% is a per-bucket headline, not a pool quantity: the three dummy
  slots ride ONLY the drafter's 4 blocks/request, so the paid tax is 12 dead
  slot-pages = **0.038 GiB (fp8) / 0.021 GiB (int4)** per max request — and
  the engine's demand line INCLUDES it (the paste's 9.51 is exactly the
  grouped sum 9.5054 at bs 1648; the un-grouped sum would print 9.47)
  [183][195].
- `size 8` is the fork search's own optimum at our shape, and the search's
  objective (`group_size × blocks/request`) is exactly what the boot check
  spends: **every** legal alternative is worse (upstream's 5: +1.08 GiB int4
  demand) or ~0.4% better with 69 block tables (1); the 24-group cap
  (`RADIANCE_KV_GROUP_MAX_GROUPS`, default 24) is what excludes the latter —
  the fork's own rejection, on our numbers too [189][195].
- f1's standalone boot contribution at 262144/0.98 is **≤ 0.021 GiB against a
  1.40 GiB gap: no S makes the boot hold.** The grouped-demand correction
  also moves the 3.5 gate bar: the engine will print ~**5.06 GiB** (S=8,
  predicted bs 1696), not D36's raw 4.93 — the f2 (graph-estimate ≈1.27)
  half alone is now provably ~0.12 GiB short; the B fall-through's
  engine-estimate lands ≈171k tokens (R6's 120–180k band, S=8 shape) [184][187][195].
- There IS a real env surface — `RADIANCE_KV_GROUP_OPT/SIZE/MAX_GROUPS`,
  baked `OPT=1` in the image ENV — but its only positive-valued settings
  recover 0.02 GiB at bookkeeping prices, so the honest ship-surface literal
  is: **no edit; close f1 as "S=8 optimal at the pins; OPT=0 recorded as the
  anti-lever (+1.08 GiB if set); the 1.4 GiB question is f2/donors/B's"**
  [191][192][193].

### R7.1 — the mechanism @ ced6857a: what grouping is, the 3-and-60% arithmetic, where 8 comes from

**The uniform-group rule (upstream, un-patched).** `_get_kv_cache_groups_uniform_page_size`
is defined at `vllm/v1/core/kv_cache_utils.py:1435`; its docstring states the
assumptions that force grouping: physical memory per block must be identical
across all KV cache groups (assumption 1, L1465-1467), one `block_size` for all
layers (assumption 2, L1468-1471), and **"Number of layers per group:
Currently assumed the same"** (assumption 4, L1476-1478) [182]. Layers are first
bucketed by identical `KVCacheSpec` (L1500-1526) — for our served shape the
buckets are exactly the fork's documented table, re-verified against the two
fetched configs: **48 linear_attention (GDN, MambaSpec) / 16 full_attention
(FullAttentionSpec; 64 layers ÷ `full_attention_interval 4` [166]) / 5 drafter
(SlidingWindowSpec, window 2048, 8 heads × 128 [167])** — 69 layers total.

**Upstream's group-size pick.** L1540-1551:

```python
min_num_layers = min([len(layers) for layers in layer_buckets])   # = 5
group_size = min_num_layers
max_num_layers = max([len(layers) for layers in layer_buckets])   # = 48
if max_num_layers < min_num_layers * 1.5:                          # 48 < 7.5? NO
    group_size = max_num_layers
```

with the FIXME at L1533-1539 admitting the rule is an n:1-pattern heuristic
("Gemma3 5:1, LLaMA4 3:1 … Need a better strategy if we want to support more
complex patterns"). Our mix is 48:16:5 — not n:1 — so the 1.5 escape (written
for gpt-oss-20b + eagle drafter cases, L1546-1550) does not fire and **upstream
picks `group_size = 5`** — exactly the fork log's "(upstream would pick size 5)"
parenthetical [182][189].

**The padding + warning arithmetic.** Per bucket, L1553-1560:

```python
num_padding_layers = group_size - len(layers) % group_size
if num_padding_layers != group_size:      # only if the last group is partial
    logger.warning("Add %d padding layers, may waste at most %.2f%% KV cache memory",
                   num_padding_layers, num_padding_layers / len(layers) * 100)
```

Plugging our buckets at the fork's `S = 8` (the patched path — see below):
GDN `48 % 8 = 0` → skip (pad would read 8 == group_size); FA `16 % 8 = 0` →
skip; SWA `5 % 8 = 5` → `pad = 8 − 5 = 3`, waste = `3 / 5 × 100 = 60.00`.
**Reproduced string-for-string: `Add 3 padding layers, may waste at most 60.00%
KV cache memory`** [182][195]. The denominator is the PADDED BUCKET's layer
count (3 dummy slots on top of 5 real drafter layers), not the pool — the
percentage can read absurdly (at S=16 it says 220.00%, S=48 says 860.00%) —
which is the first half of why the headline ≠ the damage (R7.2).
And the string is upstream's own text (the fork patch does not add it) — the
padded slots materialize on the supply side, in the pool's uniform blocks, not
as layer entries: `create_kv_cache_group_specs` receives the real layer names
(`grouped_layers.append(layers[i::num_groups])`, L1573-1574), and
`get_kv_cache_configs` asserts every layer lands in exactly one group (L2748,
"Some layers are not assigned to any group") — so a group of 5 layers lives in
blocks sized to the 8-layer MAX group (`_get_kv_cache_bytes_per_block` =
`max(sum of per-layer pages over groups)`, L1588-1611): the 3 dummies are dead
bytes per block of the drafter group [182][183].
Under upstream's own S=5 the same formula emits the fork docs' witnessed pair:
GDN `5 − 48%5 = 2` → `2/48 = 4.17%`, FA `5 − 16%5 = 4` → `4/16 = 25.00%`, SWA
exact — `Add 2 padding layers, may waste at most 4.17%` + `Add 4 … 25.00%`
— which is verbatim the [172] live witnesses [182][189][195].

**Where 8 comes from — the fork patch, in full.** `patch_kv_group_size.py` @
5b99d66c (157 lines, read in full [189]): a build-time, anchor-exact source
patch (its `_patchlib.apply()` replaces three unique anchor strings in the
installed `kv_cache_utils.py` and refuses to write a file that fails
`ast.parse`; unique-anchor-or-die semantics [190]) that (i) threads
`vllm_config` into `_get_kv_cache_groups_uniform_page_size` (anchor at
upstream L1435-1437 — the CALL anchor at L2318 `groups =
_get_kv_cache_groups_uniform_page_size(filtered_spec)` re-verified
character-exact [182][189]); (ii) inserts the helper `_radiance_pick_group_size`
which searches every `g` in `1..max(bucket)` and keeps only CANONICAL sizes
(`max(cdiv(L, cdiv(L,g))) == g`, so the returned value equals the group size the
allocator recomputes downstream); costs each candidate by
`g × Σ_b cdiv(L_b,g) × cost_b` where `cost_b = max(cdiv(spec.max_memory_usage_bytes(vllm_config), page))`
— the per-request BLOCK footprint, i.e. exactly what the boot check later
spends; caps at `RADIANCE_KV_GROUP_MAX_GROUPS` (default 24); and
`logger.info("[radiance] kv cache groups: size %d, %d groups, %d blocks/request
(upstream would pick size %d)", …)`; (iii) env exits: `RADIANCE_KV_GROUP_OPT=0`
restores upstream, `RADIANCE_KV_GROUP_SIZE=<n>` forces a size (bypassing both
the search and its canonical/cap guards), everything default-OFF → the search
runs. The Dockerfile bakes `RADIANCE_KV_GROUP_OPT=1` into the image ENV at L363
— the optimization is ON by construction on our pod, and our entrypoint/chart
set none of the three [191][193]; the fork's own docker-compose passes
`RADIANCE_KV_GROUP_OPT: "${RADIANCE_KV_GROUP_OPT:-1}"` [192].

**The 378 is the search's own ledger, reproduced.** At the crash-boot shape
(fp8, R4D, ssm-fp32, K7, batched-2560, no-async, 262144): the platform raises
the attention `block_size` to 1648 (R7.3) so one FA/SWA page = 3,375,104 B ≥
the GDN page 3,350,528 B; `page` in the search = 3,375,104 for every spec
after unification; costs (blocks per group per max request, from the pinned
`max_memory_usage_bytes` implementations [187]): FA `cdiv(262144, 1648) = 160`;
GDN align-mode `2 + num_speculative_blocks(7) + num_prefill_checkpoint_blocks(0)
= 9` [156→187]; SWA `cdiv(window−1 + extra + in-flight(2560), 1648) + 1 = 4`
(the +1 straddle rule of `max_admission_blocks_per_request` [187]). Candidate
keys (`S × blocks`, group-capped at 24): S=1→3012 (69 gr, capped out),
S=2→3016 (35 gr, capped out), S=3→3336, **S=4→3024 (18 gr), S=8→3024 (9 gr)**
— tie broken by fewer groups → **S=8, groups = 6+2+1 = 9, blocks =
6×9 + 2×160 + 1×4 = 378** — the pasted INFO triple, re-derived from source and
confirmed by a scripted sweep of the exact patch formula [195]. (The fork's own
TP2 measurement — "full-attention group costs 160 blocks, a GDN group 2+spec =
9, the drafter 8", 382 blk/req — is the same computation in a TP2 frame with a
different in-flight term [172→189]; the paste's GDN=9 also settles R6's
blind-spot on `num_prefill_checkpoint_blocks`: at the crashed boot it evaluated
to **0**, not the 1 R6's demand decomposition assumed — 48×10×3,350,528 = 1.498
GiB was really 48×9×… = 1.35, see R7.2's exact fit.)

**The line numbers themselves — the strongest corroboration of the round.**
Reconstructing the installed tree (raw `kv_cache_utils.py` @ ced6857a + the
three `patch_kv_group_size` string replacements, the same order and semantics
the Dockerfile applies them in — L266, before the `kv_offload` patches whose
insertion points sit BELOW both statements [191]) puts the `logger.info(` of
the radiance line at **line 1477** and the padding `logger.warning(` at
**line 1617** — matching the pasted `@ kv_cache_utils.py:1477` and
`kv_cache_utils.py:1617` exactly, on this machine, from the pins, without
fitting [195]. (Upstream-unpatched positions: the helper insert nets +54 lines
at the def anchor L1435 with `logger.info(` its 42nd line → 1435+42 = 1477;
the tail insert nets +7 before the warning at L1556 → 1556+54+7 = 1617.) The paste's `WARNING … (×2)` = two grouping passes in the log
window — one `get_kv_cache_groups` call emits one pair; the pinned v0.30.0
boot flow calls it once per `get_kv_cache_configs` pass (L2687 global; the
per-worker projection at L2692 reuses it, no re-emit) [183], so ×2 says two
passes (restart/re-attempt class) — immaterial to the verdicts, flagged as a
minor open residue.

### R7.2 — the waste: is the 60% actually paid, and does DEMAND include the tax?

**Demand includes it — and the paste proves it numerically.** There are two
need-check paths at the pin: (1) the raw per-layer sum
`max_memory_usage_bytes(vllm_config, kv_cache_spec.values())` feeding
`_check_enough_kv_cache_memory` via `check_enough_kv_cache_memory` (L912-918,
L975-1009) — no groups, no padding; (2) the engine-core path inside
`get_kv_cache_configs`: `check_memory = avail − _pool_bytes_per_block(groups)`
(one uniform block reserved for the pool's null block, L2725-2728) then
`_check_enough_kv_cache_memory(check, _max_memory_usage_bytes_from_groups…)`
(L2737-2743), where `_max_memory_usage_bytes_from_groups` — docstring verbatim:
**"This correctly accounts for padding in hybrid models"** — returns
`bytes_per_block × Σ_groups blocks_per_request`, i.e. **grouped demand =
blocks(S) × S × page**, padding slots included [183]. Which path printed
crash #4? Both formats live in the same message function (L899-909, the
owner's `:899`), so decide by arithmetic at `format_gib = round(x, 2)` [159]:

| path | bytes | GiB | prints | paste |
|---|---|---|---|---|
| raw per-layer sum (fp8 boot) | 10,159,069,… | 9.4677 | `9.47` | ✗ |
| grouped sum, S=8, blocks=378, page 3,375,104 | 10,206,314,496 | **9.5054** | **`9.51`** | ✓ [195] |
| available (worker line 1.12 − null block 0.0252) | — | 1.0908 | `1.09` | ✓ |

The crashed message's BOTH numbers (9.51 needed, 1.09 available) land on the
GROUPED path simultaneously — the 1.12-vs-1.09 delta the D36 record called a
"display/rounding class" is actually the null-block reservation, and the
9.51-vs-R6's-9.518 is not noise but the S=8 grouped sum at GDN=9/SWA=4/FA-160,
block-rounded. **Verdict: f1 moves DEMAND (the boot gate quantity), not only
supply.** The pool side (worker `available = requested − non-KV − graph-estimate`
[157]) is S-independent; the gate `needed(S) ≤ pool − S×page` is decided by
`needed(S) = S × blocks(S) × page`.

**What the tax is, in GiB, at our shapes.** The S=8 dummy slots are 3 pages ×
the drafter group's 4 blocks/request = 12 dead slot-pages: **0.0377 GiB fp8,
0.0206 GiB int4** (page 1,845,248 B at the predicted int4 bs, R7.3). The same
tax at upstream's 5 is 640 dead FA slot-pages (4 pad layers riding the 160
blocks of four FA groups) + 18 dead GDN pages: **11.536 GiB vs 9.505 fp8
(+2.03), 6.135 vs 5.059 int4 (+1.08)** — 21.3% worse per request, matching the
fork's measured "+20.7% tokens" when their patch replaced 5 with 8 (739,544 →
892,799 tokens is exactly the reciprocal of this footprint ratio)
[189][195]. The headline's inversion is the whole story: **60.00% sounds
catastrophic because the % is per-drafter-bucket; the pool-fatal pattern was
the 25% (FA-bucket) one, and the fork default already kills it** — "Padding
count is not the objective; where the padding lands is" [189]. The
un-padded absolute floor (S=1, 69 groups: 3012/2932 slot-pages) sits only
0.4%/0.7% below S=8: our pasted 3024-slot footprint is within 12 slots of the
zero-padding optimum [195].

### R7.3 — the knobs at the pins (existence law: a knob that does not exist @ ced6857a is worth nothing)

**(a) `--mamba-block-size` / any CLI that controls group size. `--mamba-block-size`
EXISTS** at 0.30 (`arg_utils.py` field L738, parser L1306, plumbing L2113) — and
is **dead for our purposes**: the platform's hybrid alignment
(`Platform._align_hybrid_block_size`, `vllm/platforms/interface.py:778-965`)
runs before specs are built; under `mamba_cache_mode == "align"` it FORCES
`cache_config.mamba_block_size = cache_config.block_size` (L939-940) after
computing the attention block size as the kernel-aligned cover of the mamba
page: `attn_block_size = align × cdiv(mamba_page, align × attn_bytes_per_token)`
(L923-925), `align = max(min supported kernel block, DEFAULT_BLOCK_SIZE=16)`
— TRITON_ATTN supports `MultipleOf(16)` (L307-308 of triton_attn.py) and R4D
"Exactly 16" (fork file L235-238 [194]) → **bs = 1648 for the fp8 crash boot
(16 × cdiv(3,350,528, 32,768) = 16×103) — reproducing the fork's measured 1648
— and bs = 1696 predicted for the shipped int4 boot (16 ×
cdiv(1,777,664, 16,896) = 16×106)**, with the INFO markers "Setting attention
block size to %d tokens" (L934) and "Padding mamba page size by %.2f%%" (L958;
0.73% fp8 / 0.75% int4) printed in every boot log [184][195]. Group size S is
in NO CacheConfig field and no CLI at this pin — the only 0.30 CLI that could
name it, `--min-kv-cache-group-layers`, is PR #58207's addition and does NOT
exist at ced6857a (searched arg_utils/envs/kv_cache_utils: zero hits; the PR is
still open) [188][197]. `--block-size` exists (L1268) but the alignment may
only RAISE it (interface L930-936 "if cache_config.block_size <
attn_block_size") — any value ≥ 1696 grows every attention page ∝ bs while the
GDN pool is SSM-state-fixed, so raising it can only ADD demand; lowering is a
no-op. `--mamba-block-size` + prefix caching-off is a hard ValueError
(config/vllm.py L3197-3207) — irrelevant either way. **Verdict (a): no CLI
group-size knob exists; bs is platform-derived and already at its minimum.**
**(b) `--kv-cache-metrics` EXISTS (L1543) — observability only** (an
ObservabilityConfig sampling flag threaded to the coordinator's metrics
collector); zero effect on grouping or bytes. Non-knob [188].
**(c) radiance ENVs — the real f1 surface.** `RADIANCE_KV_GROUP_OPT`
(baked `=1` in image ENV, Dockerfile L363 [191]; compose passthrough
`${RADIANCE_KV_GROUP_OPT:-1}` [192]), `RADIANCE_KV_GROUP_SIZE`,
`RADIANCE_KV_GROUP_MAX_GROUPS` (defaults as per-helper). None appears in
`radiance_entrypoint.sh` or `.env.example` (zero matches — the entrypoint's
RADIANCE_* list carries no group var [193]); our chart sets none — so today's
effective state is the search itself. These are ADDITIVE env: a pod that sets
one re-opens the D25 20-var exact-law amendment (same class as f2's
"PRICED NOT SHIPPED" env), so every value below is a values-surface event with
a byte-stability cost. **Legality law: forcing a NON-canonical S is a trap —
`RADIANCE_KV_GROUP_SIZE=9` builds groups the allocator then RE-derives to 8
(max group layer-count), so the forced value does not survive to the block
math; the patch's own comment (L44-46) restricts its search to canonical sizes
for exactly this consistency. Canonical set for [48,16,5]:
{1,2,3,4,5,6,7,8,10,12,16,24,48}** — the whole sweep [195] (non-canonical:
9,11,13,14,15,17..23,25..47). TRITON page compatibility is S-independent (the
+1-straddle and MultipleOf(16) laws bind at bs, not at S); the drafter group is
the same SlidingWindowSpec packing at any S; the HYBRID-packaging question the
docs flag ("HybridKVCacheCoordinator handles exactly two groups" —
hybrid_kv_cache_manager page) is STALE at our pin: the pinned coordinator
class builds per-group managers for N groups (L615-699; the multi-group
asserts that bite are DCP-only, dcp=1 for us) [196][198].
**(d) Forking the patch in our overlay — BARRED, and the bar is structural,
not cosmetic.** Our container is the C01 thin re-export: "The upstream image
is a SELF-CONTAINED terminal build … the overlay adds NOTHING" apart from the
one sanctioned flash-attn PIP layer (D34/D35) — the sanctioned injection is
installing PACKAGES into `/opt/vllm`, not editing the vLLM sources the radiance
patch chain owns [199]. An overlay source-edit would (i) sit as a FOURTH-order
editor of a file three radiance patches already anchor-edit (the kv_offload
restore patch edits the same `kv_cache_utils.py` after L266-268 [191]) — every
future `1.0.<n>` bump risks silent anchor drift in OUR layer, which `_patchlib`'s
ast/unique guards exist to catch in THEIRS and nothing catches in ours; (ii)
re-implement a constant the maintainers already exposed as an env (SIZE/OPT/
MAX_GROUPS) — the env IS the sanctioned fork-the-patch surface [189][192];
(iii) break the container-suite byte-stability ACs (C01 law). Cost-benefit
against the recovery it would enable: 0.02 GiB (S=1 at MAX_GROUPS=69 — a
trade the FORK itself declines in writing: "0.8% over group size 8… so
RADIANCE_KV_GROUP_MAX_GROUPS caps the search" [189]). Barred [199].
**(e) Downsides of "clean-dividing" sizes + the upstream threads.** Enumerated
legally-possible S for our exact geometry at the shipped int4 shape
(costs 155/9/4, predicted bs 1696, page 1,845,248; `needed = S×blocks×page`;
Δ = vs S=8; pads per [GDN,FA,SWA] bucket with their warning strings) [195]:

| S | canonical | groups | blk/req | pads | warning text | needed GiB | Δ vs S=8 |
|---|---|---|---|---|---|---|---|
| 1 | ✓ | 69 (>cap) | 2932 | [0,0,0] | none | 5.039 | −0.021 |
| 2 | ✓ | 35 (>cap) | 1468 | [0,0,1] | 20.00% | 5.046 | −0.013 |
| 3 | ✓ | 24 | 1082 | [0,2,1] | 12.50%+20.00% | 5.578 | +0.519 |
| 4 | ✓ | 18 | 736 | [0,0,3] | **60.00%** | 5.059 | ±0 |
| 5 | ✓ | 15 (upstream) | 714 | [2,4,0] | 4.17%+**25.00%** | 6.135 | **+1.076** |
| 6 | ✓ | 12 | 541 | [0,2,1] | 12.50%+20.00% | 5.578 | +0.519 |
| 7 | ✓ | 11 | 532 | [1,5,2] | 2.08%+31.25%+40% | 6.400 | +1.341 |
| **8** | ✓ | **9 ← chosen** | 368 | [0,0,3] | **60.00%** | **5.059** | — |
| 9,11 | ✗ | — | — | — | forced ≠ allocator-recomputed | — | trap |
| 10 | ✓ | 8 | 359 | [2,4,5] | 4.17%+25%+100% | 6.170 | +1.111 |
| 12 | ✓ | 7 | 350 | [0,8,7] | 50%+140% | 7.218 | +2.159 |
| 16 | ✓ | 5 | 186 | [0,0,11] | 220% | 5.114 | +0.055 |
| 24 | ✓ | 4 | 177 | [0,8,19] | 50%+380% | 7.300 | +2.241 |
| 48 | ✓ | 3 | 168 | [0,32,43] | 200%+860% | 13.858 | +8.799 |

Why "divides cleanly" misleads: what must divide is the LAYER MIX, and 69-layer
mixes like ours (48/16/5, pairwise gcd(48,16,5)=1) make EVERY size above 1 pad
someone (S=2 by one slot, S=8 by three, upstream's 5 by six) — the question is
only WHO pays (FA pads ×160 blocks =
fatal; GDN pads ×9 = annoying; SWA pads ×4 = noise). S=16 "looks" cleaner than
S=8 (zero GDN/FA pad) yet still lands +0.055 GiB (its 11 SWA pads cost 11×4 =
44 slots vs S=8's 12); S=4 ties S=8 exactly and loses the tiebreak on group
count (18 vs 9). Upstream is converging on precisely our fork's position but
none of it is IN our pin: **#46462** (closed, 2026-06-23 — the origin bug:
"DFlash+Qwen3.6-35B-A3B, invalid gpu kv cache usage", exactly our model family
+ drafter), **#56445** (OPEN PR 2026-09-11, unmerged — `math.gcd(*counts)` fix
"eliminat[ing] KV cache dummy padding", body verbatim cites "up to 60% KV
cache memory waste on dummy padding layers" and the FIXME — **even merged it
would not move us: its gcd(48,16,5)=1 falls back to the 1.5 logic → still
size 5**), **#58207** (OPEN PR 2026-09-22, unmerged — bytes-based search +
`--min-kv-cache-group-layers`: the upstream shape of the fork patch),
**#65490** (OPEN PR 2026-11-03, unmerged — exclude draft-only buckets from
min_num_layers), **#59117** (OPEN RFC 2026-09-29 — "KV-cache pool collapse
when a draft model introduces a new cache spec type (hybrid GDN + DFlash)" —
the crash-class RFC, verbatim our shape: draft's spec type "fragments grouping,
inflates per-request block demand"), **#58638** (OPEN RFC 2026-09-25, grouping
for hybrid+drafters), **#64401** (OPEN RFC 2026-10-29, "one KV cache group per
spec" — the endgame design), **#66451** (OPEN 2026-11-09, drafter pool waste at
DCP), **#52895** (align-branch comment clarification) — and the stable docs
page itself: case 3's padding example ends "The solution has some memory waste
and is not perfect. Please report any cases where padding overhead becomes
unacceptable" + case 4 documents the bs-raise/pad algorithm verbatim (with its
own "work in progress" caveat) [197][198]. **Adjacent (not f1, recorded):**
`--disable-hybrid-kv-cache-manager` (exists, L655) promotes the SWA specs to
FullAttention (window caps LOST → +5 layers of full-length KV) and pads to
[0,0,15]-style groups — measured strictly worse (+~30% footprint, no sliding
economy) — anti-lever, never [182][188].

### R7.4 — the price at our shape, and the boot question

Pool/demand recap at the shipped combo (int4_pth + TRITON_ATTN + ssm-bf16 +
0.98, D36): pool(0.98) ≈ 3.67 GiB held-constant-non-KV [D36]; predicted
grouped demand at the default S=8: **5.06 GiB** (1696-bs assumption;
5.04–5.06 across the bs-uncertainty variants; the boot log's
`Setting attention block size to N` + `[radiance] … X blocks/request` lines
re-pin it exactly: `needed = blocks × S × (bs × 1088)`).

| S | needed GiB | recovered vs S=8 | boot 262144 @0.98 | risk |
|---|---|---|---|---|
| **8 (default, shipped)** | 5.059 | — | **FAIL** (gap 1.40 vs pool−null 3.656) | none — today's behavior |
| 4 | 5.059 | 0.000 | FAIL | 18 tables for zero bytes |
| 16 | 5.114 | −0.055 | FAIL | worse |
| 1 (forced, or MAX_GROUPS≥69) | 5.039 | **+0.021** | FAIL | 69 block tables + per-step Python bookkeeping; fork's own rejection |
| 5 (OPT=0 = upstream) | 6.135 | −1.076 | FAIL | the anti-lever: also halves concurrency (734-blk requests) |
| 3/6/7/10/12/24/48 | 5.58–13.86 | −0.52…−8.80 | FAIL | strictly worse |

**The honest sentence the brief asked for: `size 8` is (near-)optimal given
constraints we cannot move — the [48,16,5] layer mix (fixed by checkpoint +
drafter), the platform bs ≥ mamba-page-cover (1648/1696), the canonical-rule
and the ≤24-group cap — and the entire recoverable distance from it to the
absolute zero-padding bound is 0.021 GiB, paid in 69 block tables. NO legal S
makes 262144 boot at 0.98 without the fall-through.** f1's standalone boot
contribution is ≈ 0 GiB; D36's "the 262144 boot still needs ~1.3 GiB out of
(f1)/(f2) or a named margin donor" re-shapes on this round's numbers: the
donor need is ~**1.40 GiB** (the gate bar moves up 0.13 by the grouped-demand
correction faster than any S moves it down), of which **f2's graph-estimate
half (~1.26-1.27 GiB nominal) is now provably insufficient ALONE** (3.67+1.27
= 4.94 < 5.06) — it converts the refusal from silent to printed, not to booted;
closing still needs a real donor from the D36 ledger (mtp-K4 ≈ −2.0 non-KV at
the 29/30 caveat; the `{"image":1}` profile-day knob) or the sanctioned B
fall-through. B-path calibration: at S=8 the engine's own estimate line would
print ≈ **171k** at pool 3.67 (R6's 120–180k band, top third — the S-choice
bends this by only ~±4%: 176k at S=1, 141k at upstream-5, rough linear reads
[195]). Capacity after boot (the concurrency view): S=8 maximizes usable
tokens/block among legal ≤24-group values by the same table (each max request
reserves 368 of `pool/14.08 MiB` blocks; at a f2+donor pool of 6.2 GiB that is
~1.2 concurrent 262k sessions vs 0.9 at S=5) [195].

### R7.5 — options, the verification law, and the ONE owner question (R7-Q1)

- **Option F1-0 (recommended) — CLOSE f1 with NO ship-surface edit.** The
  best f1 move is the one already running: keep the baked `RADIANCE_KV_GROUP_OPT=1`
  default, add NOTHING to serveArgs/env — **the ship-surface literal is the
  empty diff** (values byte-stable everywhere, the D25 20-var law and the D36
  recipe untouched). The 3.5 runbook f1-row gains the resolution text:
  PASS-marker pair = `[radiance] kv cache groups: size 8, 9 groups, N
  blocks/request (upstream would pick size 5)` present AND the absence of the
  4.17%/25.00% upstream pair (the single 60.00% line is EXPECTED and priced at
  0.021 GiB — do not treat it as a defect), plus the re-pin law
  `engine demand GiB = blocks × S × bs × 1088` read live from the boot lines
  ("Setting attention block size to N tokens" → bs; the grouped refusal or the
  `GPU KV cache size` line → capacity). Anti-lever recorded (never set):
  `RADIANCE_KV_GROUP_OPT=0` = +1.08 GiB demand/+21% footprint at our shape.
- **Option F1-1 — force `RADIANCE_KV_GROUP_SIZE=1` (or `MAX_GROUPS=69`):**
  recovers 0.021 GiB of demand and 0.4% footprint; costs 69 per-request block
  tables and a new env var against the 20-var law; the fork declines this
  exact trade in writing; verdict: NO.
- **Option F1-2 — `MAX_GROUPS` in the 24-68 window:** no legal S appears
  between (S=2 is the only sub-24 canonical at 35 groups — still above 24;
  values 25..34 change nothing, 35+ admits S=2 for −0.013 GiB): no.
- **Option F1-3 — overlay-patch the constant:** barred — R7.3(d).
- **Option F1-4 — wait for upstream (#56445/#58207/#65490/#64401):** none is
  merged at the pin (and #56445's GCD rule does not help THIS shape); the
  fork env already implements the #58207 direction; no schedule to build on.
- **The transferred question.** f1 closes at ≈0 — so the owner's real
  decision stays what D36 framed: the 262144 boot is f2+donor arithmetic
  (≈1.40 GiB now), with the B fall-through printed-estimate ≈171k as the
  designed path. **R7-Q1 (one question, one recommended answer):** ratify
  closing f1 as NO-OP (F1-0: no edit, the marker pair + grouped-demand
  re-pin enter the 3.5 runbook row, OPT=0 enters the recorded anti-levers) —
  or direct one of F1-1..F1-4 (each priced above; each recovers ≤ 0.021 GiB
  or costs ≥ 1.076 GiB). Best guess: ratify F1-0 — there is no knob here that
  moves the boot verdict, and manufacturing one (SIZE=1) pays in scheduler
  bookkeeping for a twenty-megabyte rebate.

### Contradictions and how to weigh them (R7 conflict map)

1. **D36/C05's "4.93 GiB demand" vs the grouped 5.06:** the round-1/R6 numbers
   were the raw per-layer sums; the engine's actual gate at our pin is the
   grouped sum (proven by the exact 9.51/1.09 paste fit). Weigh: pinned source
   + paste arithmetic — the 3.5 bar re-pins to the grouped print (the
   boot-day marker reads it from the log; the correction also refits R6's own
   GDN 1.498 to 1.35+pad and SWA 0.020 to 0.063 at bs-1648 rounding).
2. **"60% waste" (fork log, scary) vs "≈0.02 GiB waste" (this round):** both
   true; different denominators (bucket layers vs pool slot-pages). Weigh the
   slot-page math — it is what the allocator charges, and it is the fork's OWN
   stated position ("where the padding lands", "the wasted slots are the
   small half of the cost") [189].
3. **compose's "block size 1664 + one extra state block" comment [192] vs the
   boot-fitted 1648/GDN-9 (fp8 paste) and the formula-predicted 1696/GDN-9
   (int4):** the paste's own numbers (378 exact, 9.51/1.09 exact) beat the
   prose comment; the comment may describe their current build/dtype mix.
   Weigh: arithmetic from the pinned code, and let the boot log's two INFO
   lines arbitrate on the day.
4. **Upstream docs "exactly two groups" coordinator caveat vs the pinned
   multi-group HybridKVCacheCoordinator:** the docs page self-flags as
   commit-dated ("may change"); the pin's code is authority [196][198].
5. **R6's "pool 1.12 vs check 1.09 = display/rounding class" vs null-block
   reserve:** this round identifies the mechanism (one uniform block reserved
   before the check, L2725-2728) — a resolution, not a contradiction.

### Implications for the plan

- C05 3.5 f1-provision: closes with **no values edit**; the runbook gains the
  marker-pair law + the `needed = blocks×S×bs×1088` re-pin formula + the
  OPT=0 anti-lever note (the f1-row of the 3.5 gains the f1-resolution, as the
  commission frames). No env-law amendment (nothing ships).
- The D36 gap sentence tightens: 1.3 → **~1.40 GiB** (grouped bar 5.06), f2
  alone now provably ~0.12 short; the donor ledger (mtp-K4 / `{"image":1}`)
  and the sanctioned B remain THE answer path — unchanged in kind, corrected
  in magnitude, with the B printed estimate ≈171k (S=8).
- DECISIONS: D36's paste-quants stand; this round adds the f1 verdict (an
  R7 entry when the coordinator logs it) and the two corrections above; no new
  question to the owner besides R7-Q1's ratification.

### Open questions (no-questions-rule log — round 7, for coord → owner/plan)

- **R7-Q1** (ratify F1-0 close, else F1-1..4 priced) — see R7.5.
- Minor residue (not blocking): the paste's `WARNING … (×2)` — one pair per
  grouping pass at the pin, so ×2 = two passes in the log window; a restart
  class, flagged for whoever re-reads the full pod log (the f3 log-TOP ask
  already pending covers it).
- The `num_prefill_checkpoint_blocks` assignment site was NOT located in the
  fetched tree (grep-near miss); its VALUE at our boots is pinned by arithmetic
  (GDN cost 9 ⇒ 0 at the fp8 boot; re-check at the int4 boot via the printed
  blocks/request — 368 ⇒ 0, 374 ⇒ 1).

### Sources (R7)

All raw-fetches 2026-11-09 at the exact pins (method: the fetched trees + a
local reconstruction script; the reconstruction applies the fork's three
string replacements to raw @ ced6857a in Dockerfile order and reads the
statement lines — the numbers below include its outputs [195]).

182. vLLM v0.30.0 @ ced6857a — `vllm/v1/core/kv_cache_utils.py` L1435-1575 — `_get_kv_cache_groups_uniform_page_size`: docstring assumptions L1464-1493 (uniform block bytes / one block_size / layers-per-group "currently assumed the same"); spec-bucketing L1500-1526; the n:1 FIXME L1533-1539 ("Need a better strategy"); min-bucket + 1.5-max heuristic L1540-1551; **padding + warning L1553-1560** (`pad = group_size − len%group_size`, skip-if-full-mod rule, `%.2f%% = pad/len(layers)`); strided layer-slicing `layers[i::num_groups]` L1571-1574 — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/v1/core/kv_cache_utils.py
183. Same file — the check/capacity machinery: `_check_enough_kv_cache_memory` L872-909 (shared message, format_gib both numbers); raw `max_memory_usage_bytes` L912-918 + `check_enough_kv_cache_memory` L975-1009 (groups a COPY + null-block reserve — raw path, no callers found in the boot flow at the pin); `unify_kv_cache_spec_page_size` L1365-1427 (bs-ratio branch L1411-1414, MambaSpec page-pad branch L1399-1408, non-MLA strided pad L1415-1418); `_get_kv_cache_bytes_per_block` L1588-1611 (pool block = MAX group layer-page sum); `get_kv_cache_groups` dispatcher L2252-2344 (L2312 unify, L2318 the patched call — anchor verified character-exact); `get_kv_cache_configs` flow L2617-2760: extra_retained tagging L2672-2682 (`num_spec−1` iff multi-module MTP else 0), GLOBAL grouping L2687, per-worker projection L2692 (no re-emit), `num_gpu_blocks_override` L2703-2716, **null-block `check_memory` L2725-2728**, **the grouped boot check L2737-2743** (`_max_memory_usage_bytes_from_groups` — "correctly accounts for padding" L2412-2417, `bytes_per_block × Σ cdiv(group usage, page)` L2449-2461), layer-coverage assert L2748; the `Maximum concurrency` INFO ~L2395-2402 — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/v1/core/kv_cache_utils.py
184. vLLM v0.30.0 @ ced6857a — `vllm/platforms/interface.py` — `update_block_size_for_backend` L609-651 (Phase 1 backend-preferred bs, Phase 2 hybrid align "may override user settings", Phase 3 skip-layer align); `_align_hybrid_block_size` L778-965: attn 1-token page via `backend_cls.customize_spec` L~850, mamba page L868-881, `kernel_block_alignment_size` = max(min supported, CacheConfig.block_size) L889-896, align-mode bs formula L923-925, **"Setting attention block size to %d tokens" L934**, **align forces `mamba_block_size = block_size` L939-940**, **"Padding mamba page size by %.2f%%" L958** — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/platforms/interface.py
185. vLLM v0.30.0 @ ced6857a — `vllm/config/cache.py` — `DEFAULT_BLOCK_SIZE = 16` L71; `user_specified_block_size/_mamba_block_size` derived flags L76-79; `mamba_page_size_padded` L158-159; `mamba_block_size` field L166; align-mode docstring L178-186 ("only cache the mamba state of the last token of each scheduler step and when the token is at position i * block_size. This is the default when prefix caching…"); fine-grained-prefix flag L187-191 — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/config/cache.py
186. vLLM v0.30.0 @ ced6857a — `vllm/config/vllm.py` — `max_concurrent_batches` L589-599 (async/V2 → 2 else PP=1 → 1; our `--no-async-scheduling` pins in-flight to ONE batch), `max_in_flight_tokens` L601-610 (`= concurrent × max_num_batched_tokens` = 2560 — the term that makes the drafter group cost 4), `validate_mamba_block_size` L3196-3208 (--mamba-block-size REQUIRES prefix caching) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/config/vllm.py
187. vLLM v0.30.0 @ ced6857a — `vllm/v1/kv_cache_interface.py` — `num_states = block_size // tokens_per_state` L191-198; `AttentionSpec` page algebra (unpadded page = heads×states×cell) L477-537; `FullAttentionSpec.max_memory_usage_bytes` L559-566 [carry 156]; **`SlidingWindowSpec` L807-856**: `extra_retained_tokens` field + `max_admission_blocks_per_request = cdiv(window−1+extra+in_flight, block_size) + 1` (the "+1 straddle") + `max_memory_usage_bytes = max_blocks × page`; `MambaSpec` L993-1053 (align: `page × (2 + num_speculative_blocks + num_prefill_checkpoint_blocks)` L1040-1043; `page_size_padded` L1025-1028) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/v1/kv_cache_interface.py
188. vLLM v0.30.0 @ ced6857a — `vllm/engine/arg_utils.py` — `--block-size` L1268, `--mamba-block-size` L738/L1306/L2113, `--kv-cache-metrics(_sample)` L682-684/L1543 (observability), `disable_hybrid_kv_cache_manager` L655-656; **negative search: no group-size flag at the pin** (`--min-kv-cache-group-layers` matches ZERO in arg_utils/envs/kv_cache_utils @ ced6857a; it is PR #58207's unmerged addition) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/engine/arg_utils.py
189. magiccodingman/vllm-radiance @ 5b99d66c — `patch_kv_group_size.py` (157 lines, read in full) — the docstring: bucket table 48/16/5 + "upstream picks 5, which divides neither 48 nor 16, and pads to 10+4+1 = 15 groups holding 75 layer slots" + live witnesses `:1261 Add 2/4 padding layers (4.17%/25.00%)` + TP2 cost table (160/9/8, 382 blk/req, +20.7% tokens, "group size 1 is the true optimum — 0.8% over size 8 so MAX_GROUPS caps the search", "Padding count is not the objective; where the padding lands is", canonical-size restriction L44-46) — and the CODE: `_radiance_pick_group_size` search L70-121 (OPT=0 exit L75-76, SIZE force L77-79, cost = `max(cdiv(spec.max_memory_usage_bytes(vllm_config), page))` L89-92, key `(g×blocks, ngroups)` L107, cap default 24 L96, the `:1477` INFO format L113-120); anchors SIG L65-69 / TAIL L131-135 / CALL L150 — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/patch_kv_group_size.py
190. Same pin — `_patchlib.py` — `apply()`: unique-anchor-or-fatal, sentinel-skip idempotence, `ast.parse` write guard — the semantics our overlay could never inherit — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/_patchlib.py
191. Same pin — `Dockerfile` — patch order L256-269: `patch_kv_group_size` at L266 (after `patch_ar_maxbytes`, before `patch_kv_offload_*` — whose `patch_kv_offload_restore` edits the SAME `kv_cache_utils.py` at `def _annotate_eagle_groups` = upstream L2126, i.e. BELOW both pasted statements → the 1477/1617 line math is set by the group_size patch alone); **ENV default bake `RADIANCE_KV_GROUP_OPT=1` L363**; the venv/SP lines [carry 181] — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/Dockerfile
192. Same pin — `docker-compose.yml` — L160 `RADIANCE_KV_GROUP_OPT: "${RADIANCE_KV_GROUP_OPT:-1}"`; L38-47 the prefix-caching+align comment ("raises the attention block size to 1664 tokens and uses one extra state block per linear-attn layer" — weighed vs the paste-fitted 1648/GDN-9 at conflict-map #3); L48 `${PREFIX_CACHING_FLAG:---enable-prefix-caching}` — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/docker-compose.yml
193. Same pin — `radiance_entrypoint.sh` + `.env.example` — zero `KV_GROUP` matches in either (entrypoint passes the baked ENV; .env.example lists no group var; only L119 `# MAMBA_CACHE_MODE=none` commented) — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/radiance_entrypoint.sh + …/.env.example
194. Same pin — `radiance_r4d_attn.py` L235-238 — `get_supported_kernel_block_sizes: Exactly 16, not a multiple of it… how this works alongside the 2240-token pages a GDN hybrid needs for --mamba-cache-mode=align` — the kernel alignment that produced bs 1648 at the crash boot — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/radiance_r4d_attn.py
195. Reconstruction + sweep artifact (this round, /tmp/opencode/cf131-r7): raw @ ced6857a + the three [189] replacements → `logger.info(` = 1477, `logger.warning(` = 1617 (paste-exact); costs (FA cdiv(262144,bs); GDN 2+7+0; SWA cdiv(2047+2560+~6, bs)+1) at bs 1648 (fp8, 160/9/4) and bs 1696 = 16×⌈1,777,664/(16×1,056)⌉ (int4, 155/9/4); fork search reproduces `size 8 / 9 groups / 378` (fp8) and predicts `size 8 / 9 groups / 368` (int4); grouped demand fp8 S=8 = 378×8×3,375,104 = 10,206,314,496 B = **9.5054 → prints 9.51 ✓ paste**, raw = 9.4677 → 9.47 ✗; available 1.12−0.0252 = 1.0908 → **1.09 ✓ paste**; int4 S=8 = 368×8×1,845,248 = **5.059 → "5.06"**; S-table + pads + warning-%s per R7.3(e)/R7.4 (S=1 5.039, S=5 6.135, …); B-estimates ≈176k/171k/141k at S=1/8/5 (pool 3.67, rough)
196. vLLM v0.30.0 @ ced6857a — `vllm/v1/core/kv_cache_coordinator.py` — `get_kv_cache_coordinator` L1014-1058 + `HybridKVCacheCoordinator` L615-770: N-group managers, cacheable-block/hash divisibility asserts L660-673, DCP-only spec-type restriction L675-684, align partial-hash path L685-704 — the multi-group + prefix-caching shape our 9-group config lands on; the docs' "exactly two groups" caveat is stale at the pin (conflict-map #4) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/v1/core/kv_cache_coordinator.py
197. GitHub API (issue records, read 2026-11-09): **#46462** closed 2026-06-23-origin (DFlash+Qwen3.6-35B-A3B A800: "invalid gpu kv cache usage, low decode speed"); **#56445** OPEN unmerged (GCD-of-layer-counts; body cites the FIXME + "up to 60% KV cache memory waste on dummy padding layers"; gcd(48,16,5)=1 → falls back to the 1.5 logic → size 5 for US even if merged); **#58207** OPEN unmerged 2026-09-22 (bytes-based search + `--min-kv-cache-group-layers`; flags the min-bucket→1 collapse "Qwen3.6-35B-A3B + DFlash ends up with 46 groups"); **#65490** OPEN unmerged 2026-11-03 (exclude draft-only buckets from min_num_layers); **#59117** OPEN RFC 2026-09-29 "KV-cache pool collapse when a draft model introduces a new cache spec type (hybrid GDN + DFlash)" — "the draft's spec type fragments grouping, inflates per-request block demand" (verbatim our crash class); **#58638** OPEN RFC 2026-09-25 (grouping for hybrid + speculative drafters); **#64401** OPEN RFC 2026-10-29 (one group per spec — endgame); **#66451** OPEN 2026-11-09 (drafter pool waste under DCP); **#52895** (align-branch comment clarification); **#45238** (align-mode prefix-hit 0 — adjacent) — https://api.github.com/repos/vllm-project/vllm/issues/{n} + search endpoint
198. docs.vllm.ai (stable, page-dated 2026-10-13) — `design/hybrid_kv_cache_manager/` — case 3 (min-count grouping + "Group 6: 2 sw + 8 padding"; "The solution has some memory waste and is not perfect. Please report any cases where padding overhead becomes unacceptable"; the "eagle speculative decoding which introduce one full attention layer" instance), case 4 (the mamba bs-raise/pad algorithm + ">400 block_size" caveat + "work in progress"), Memory Layout (m buffers shared by n groups — the uniform-block model our math assumes); `api/vllm/config/cache/` — mamba_block_size / mamba_page_size_padded prose — https://docs.vllm.ai/en/stable/design/hybrid_kv_cache_manager/ + …/api/vllm/config/cache/
199. Repo artifacts at this run's worktree — `charts/vllm/values.yaml`: the shipped serveArgs (TP1, 262144, util 0.98, int4_pth, TRITON_ATTN, `--enable-prefix-caching`, `--mamba-cache-mode align`, `--mamba-ssm-cache-dtype bfloat16`, `--no-async-scheduling`, batched 2560, watermark 0.05, `{"image": 4}`; NO --block-size/--mamba-block-size/--disable-hybrid); env section (VLLM_CACHE_ROOT et al. — no RADIANCE_* re-declared, the image-baked profile stays authority); `containers/vllm-radiance-mxfp4/Dockerfile` L1-30 (the thin re-export law: "the overlay adds NOTHING" beyond the D34/D35 flash-attn PIP layer) — the R7.3(d) bar ground — repo paths as cited

### Reliability notes (R7 self-review)

- **High confidence (source @ exact pins, paste-fitted):** the group-size
  mechanism + warning arithmetic + the 1477/1617 reconstruction (both strings
  and both line numbers reproduce from the pinned trees with zero free
  parameters [182][189][190][191][195]); demand-includes-padding (the 9.51/1.09
  double fit is decisive vs the raw 9.47 alternative [183][195]); the fork env
  surface + baked OPT=1 [189][191][192][193]; TRITON/R4D kernel alignment 16 →
  bs 1648 fp8 exact, 1696 int4 formula-derived [184][194]; the legality table
  (canonical set, cap semantics, force-bypasses-guard but canonical-only is
  consistent) [189][195]; upstream threads' merged-at status re-read today
  [197]; coordinator multi-group at the pin [196].
- **Medium confidence:** int4 bs 1696 + blocks 368 (the compose 1664 note and
  any dtype-mix we did not model could move ±3% — the boot log's two INFO
  lines arbitrate; all verdicts invariant across the 1648/1664/1712 sweep);
  GDN cost 9 (ckpt term 0) at the FUTURE int4 boot (proven 0 at the fp8 boot
  by 378-fit, re-verification is one log read on the day); the rough B-band
  estimates (141–176k, linear-in-slots); "the ×2 pair = two boot passes"
  reading of the paste (restart-class, not traced to a second caller).
- **Low confidence / explicit gaps:** the exact 9.5054→"9.51" vs any
  alternative page assumption we did not model (the fit is to the display
  pair, not a re-measurement); the checkpoint-block assignment site (grep-miss;
  value inferred from arithmetic); every number is code-static — no GPU run
  (the 3.5 day's boot lines re-pin all of it in one read).
- **Weakest claim of the round:** "no legal S makes the 262144 boot hold" —
  it is arithmetic, but it inherits R6's held-constant pool (3.67 @ 0.98 with
  non-KV 27.55). If the int4 boot's non-KV differs (TRITON_ATTN's compile
  profile ≠ R4D's, the f2 estimate interaction), pool moves — yet the
  required move is ~1.4 GiB, and no grouping value contributes more than
  0.02; the direction of the conclusion is robust even under ±0.3 pool
  uncertainty.
- **Perspective weighting:** the engine's own code at the pin + the pasted
  numbers outrank both prose layers we found (the fork's compose comment,
  the stale docs caveat); the upstream RFC/PR cluster confirms the mechanism
  reading rather than adding new authority.
- **Blind spots (stated):** the runtime block-table bookkeeping cost at
  S=1/2 (why 24 groups is "the right cap" — the fork asserted, nobody
  measured); whether dflash's own kernels assume S-uniformity beyond the
  allocator (none found; the drafter KV is plain SlidingWindowSpec pages);
  the `--watermark 0.05` interaction with the grouped admission floor
  (scheduler-side 5% reserve — f2/donor-round scope, one-line adjacent note
  here); radiance's internal patch for GLM-5.3-Flash kpool tail exclusions
  (seen in the coordinator's comment, not in our path).

---

# R8 — The donor ledger, priced

(The owner's second on-target round: the D36 combo BOOTS-to-the-check and PRINTS — boot data
`needed 5.06 GiB / available 3.47 GiB / estimated maximum model length 164,512`, the D37
B-on-print materializing exactly as ratified. Owner question: ~1.6 GiB freed so the 262144
boot holds — "Maybe drop vision? Is there anything else we can do?" This round prices every
named donor and several that turn out not to be donors, against the pinned trees and the
now-boot-pinned arithmetic. No GPU session executed; everything is source-static except where
marked measured.)

## R8.0 — TL;DR (5 lines)

- Vision is NOT a weight donor at our pins: `--language-model-only` and `{"image": 0}` exist
  but only zero the modality limits — the shipped `Qwen3_5ForConditionalGeneration` builds and
  loads the visual tower unconditionally; exact tower residency **0.858 GiB bf16** stays put.
  What dropping vision frees is the encoder REHEARSAL peak (≈1.5–2.2 GiB, estimate) — and the
  catalog marker's truth [200][201][203][204][206][211].
- `{"image": 1}` frees **0.0 GiB**: the warmup profiles ONE maximum-feature-size dummy item no
  matter the limit, because the encoder budget is exactly one max item at our constants — the
  boot log prints "profiled with **1** image items of the maximum feature size." D36's
  profile-day `{image:1}` donor is RETIRED [202][203][205].
- The drafter file is exactly **1.9735 GiB** (2,118,882,784 B [213]) — but we ship
  `RADIANCE_FAST_DRAFT=1`, which runtime-packs the draft linears fp8→W4 and keeps an INT2 head
  (0.33 GiB at TP1): effective drafter residency ≈ **1.2–1.5 GiB, not 1.97 + extras**. mtp-K4 is
  therefore margin-NEGATIVE (its 17th full-attention layer RAISES grouped demand 5.06→5.27), and
  only full no-spec is a real donor (+~1.4 GiB, demand −0.66 → boots with nothing else, at the
  OQ-A mandate's price) [218][219][220].
- The R7 law is now boot-confirmed to the byte: `needed = (58 + 2·⌈L/1696⌉) × 8 × 1,845,248 B`
  reproduces BOTH pasted numbers — 5.06 at 262144 and the printed 164,512 ↔ pool 3.465 [195→209].
  f2 at the measured pool buys the full estimate (+≈1.27, NOT estimate−real) → 4.74: still
  **−0.32 short** of 5.06 (R7 predicted −0.12 at the 3.67 pool; the pool landed 0.2 low).
- The smallest-sacrifice combo that CLEARS 262144 with vision and dflash TRUE is
  **f2 + `--mm-processor-kwargs {"max_pixels": 4194304}`** (pool ≈ 6.0 vs 5.06 boot ✓, 0.95·pool
  vs 5.06 admission ✓, scheduler self-consistent by construction); the zero-quality-sacrifice
  alternative stays on D37's B-on-print track: **f2 alone re-prints the cap at ≈ 243k** [201][207][209].

## R8.1 — VISION decomposed

### R8.1(a) — Does ANY 0.30 flag skip LOADING the visual tower? NO. (verified @ ced6857a + fork)

| flag | exists @ the pin | what it actually does | tower loaded? |
|---|---|---|---|
| `--language-model-only` | YES — `arg_utils.py` field L586, registered L1367, threaded L1855 → `ModelConfig` InitVar L395/L528/L796 → `MultiModalConfig.language_model_only` | docstring verbatim: "If True, **disables all multimodal inputs by setting all modality limits to 0**. Equivalent to setting `--limit-mm-per-prompt` to 0 for every modality" (`config/multimodal.py` L91-93; `get_limit_per_prompt` returns 0 L483-484) | **YES — unchanged** |
| `--limit-mm-per-prompt '{"image": 0}'` | YES (JSON dict, D32 law) | same zero-limit surface; validator accepts `count=0` (`BaseDummyOptions count ≥ 0`, L23-27, L255-277) | **YES — unchanged** |
| `--convert` | YES (`arg_utils.py` L879) | task conversion (embed/classify…), not a modality switch | YES |
| `--skip-mm-profiling` | YES — L621 field, L1424 registered → `MultiModalConfig.skip_mm_profiling` (L208) | skips the ENCODER + ENCODER-CACHE **memory profiling** only (`profile_run` guard, V2 `gpu/model_runner.py` L941: "Skipping memory profiling for multimodal encoder and encoder cache.") — admission and real serving untouched | YES |
| radiance fork surface | none | the repo carries NO qwen3_5 overlay file (tree scan: zero `qwen3_5` paths [216]); the 35-patch chain + runtime modules never gate the tower; entrypoint/`.env.example` mention no vision switch [214][215] | YES |

Mechanism, cited: `Qwen3_5ForConditionalGeneration.__init__` builds
`with self._mark_tower_model(vllm_config, {"image","video"}): self.visual = Qwen3_VisionTransformer(...)`
unconditionally (`model_executor/models/qwen3_5.py` L513-519), and its `load_weights` is a bare
`AutoWeightsLoader(self).load_weights(weights, mapper=hf_to_vllm_mapper)` (L438-440) whose mapper
drops ONLY `mtp.*` (`orig_to_new_prefix={"mtp.": None}`, L478 / L322) — no limit or LMO check
anywhere in the module. The capability EXISTS in the tree for other classes and was not applied
here: `vllm/models/qwen4_exp/{amd,nvidia}/model.py` L877-878/900/954/1016 build the tower
conditionally and map `{"visual.": None}` under `language_model_only`, and `qwen3_next.py` L365
reads `text_only = mm_config is None or mm_config.language_model_only` — the contrast confirms
the switch's real semantic (input zeroing + per-class opt-in), and qwen3_5 simply never opted in
[206][208].

One incompatibility guard to know before reaching for `--language-model-only`: with
`cudagraph_mm_encoder=True` it raises a ValueError ("incompatible … since it disables all
multimodal inputs and the multimodal encoder is never run", `config/vllm.py` L1311-1321 [208]) —
inert for our PIECEWISE-no-encoder-graphs posture but binding if encoder graphs are ever enabled.

**Verdict: the 0.858 GiB tower (exact, R8.1-b header) is not liberable by any flag at our pins.**
"Drop vision" prices as a REHEARSAL-PEAK donor (≈1.5–2.2 GiB estimate, next subsection) plus the
C04 marker flip — never as a weights donor.

### R8.1(b) — The profile-dummy: what the warmup materializes, and the limit's real effect

Chain @ ced6857a (V2 runner, ours): `Worker.determine_available_memory` →
`profile_run` (V2 `gpu/model_runner.py` L938) → `MultiModalBudget` →
`get_dummy_encoder_profile_inputs` → `encoder_runner.profile_encoder_cache(dummy_inputs, budget)`
(`gpu/mm/encoder_runner.py` L111-148) → `execute_mm_encoder` on the dummy batch → outputs held
in the encoder cache (`tmp_i`) until the reset [204][205][203].

The COUNT is not the limit — it is the encoder budget [202][203]:
- max tokens per image item = the checkpoint's own geometry: `preprocessor_config.json`
  `size.longest_edge = 16,777,216 px`, patch 16, merge 2, temporal 2 [212] →
  max image = **16,384 merged tokens** (px/(16²·2²) = px/1024), 65,536 pre-merge patches;
- `compute_mm_encoder_budget`: `compute = max(max_num_batched_tokens=2560, 16384) = 16384`,
  `cache = max(2560, 16384) = 16384`, budget = min = 16384 tokens [202];
- `_get_max_items`: `items_per_batch = max(1, min(16384//16384 = 1, max_num_reqs(3) × items_per_prompt))`
  = **1**, and `get_dummy_encoder_profile_inputs` repeats that ONE dummy item
  `max_items_per_batch` times — one copy, once, at any limit ≥ 1 [203];
- the decoder-side dummy materializes no mm data on our path
  (`_dummy_mm_kwargs` early-returns unless raw-input-only, V1 L1736-1747; the V2 `_dummy_run` is
  token-only [204][205]).

**So `{"image": 4}` vs `{"image": 1}` costs the SAME ~1 max-item rehearsal peak, and the
`{"image":1}` saving = 3×that is 0×that = 0.0 GiB.** The boot-day marker line settles it on
evidence: `Encoder cache will be initialized with a budget of 16384 tokens, and profiled with
1 image items of the maximum feature size.` [205] (log this from the pod's TOP on boot day —
it is the f3-window paste's next neighbor).

Per-image peak price from the checkpoint's `vision_config` (depth 27, hidden 1152, heads 16 →
head_dim 72, MLP 4304, out_hidden 5120, bf16 [211]) at the 65,536-patch dummy [ESTIMATE class —
input and output terms are arithmetic, activation coexistence is not code-pinned]:

| term | bytes | GiB |
|---|---|---|
| pixel_values input (65,536 × 3·2·16·16=1536, bf16) | 201,326,592 | **0.19** |
| ViT activations, per-layer worst set (hidden 0.134; qkv 0.40; fc1+gelu 0.50×2; out 0.134) | — | ≈ **1.2–1.8** |
| encoder-cache output embeds (16,384 × 5120 bf16) | 167,772,160 | 0.16 |
| **max-item rehearsal peak** | | **≈ 1.5–2.2, mid ≈ 1.9** |

(No N² score buffers in either attention path at this shape: the r4d `attn_vit_h72_bf16` kernel
— active when `RADIANCE_USE_R4D=1`, which is image-baked — processes per-segment flash-style
[221], as does the Triton port whose 72→128 tile padding may add ~0.3 of operand slack.)

### R8.1(c) — Capabilities fallout (the C04 honesty law)

- `{"image": 0}` (≡ `--language-model-only`): the engine refuses image inputs at validation →
  the catalog rows' `capabilities.input.image` marker goes **FALSE** — the C04 honest-grounding
  law (the marker reflects what the engine serves) forces the three-row re-pin + the `surface.sh`
  M3 re-pin, retires runbook 3.4 (the owner-visible requirement-#3 proof), orphans the D34/D35
  flash-attn install layer (the ViT it qualifies is never executed), and contradicts card
  requirement #3 ("keep vision") — an owner-ruling-grade trade, which is exactly what was asked.
  Also a distinct boot marker to expect: `WARNING … All non-text modalities supported by the
  model have been explicitly disabled via limit_mm_per_prompt. Encoder cache will not be
  initialized.` [202]
- `{"image": 1}`: marker stays TRUE — and buys nothing (R8.1b).
- `--skip-mm-profiling` / max_pixels cap (R8.4): marker TRUE, 3.4 smoke intact — the cost is
  elsewhere (unaccounted or capped runtime peak, respectively).

## R8.2 — The drafter, priced

**Exact residency of `tcclaviger/Qwen3.8-27B-DFlash2-FP8` @ `ee0cb26a…`:** single
`model.safetensors` = **2,118,882,784 B = 1.9734 GiB** (no index file — a whole-file repo),
payload = BF16 params 194,254,080 (×2 B) + F8_E4M3 params 1,730,150,400 (×1 B) = 2,118,658,560 B
+ 224,224 header; plus `model-kvscales.safetensors` 1,324 B (the fp8-KV calibration sidecar —
inert for int4) [213]. R6's 1.97 GiB guess was right as a FILE datum; as a RESIDENCY datum it is
wrong under our shipped `RADIANCE_FAST_DRAFT=1`:

**What FAST_DRAFT actually does to residency** [219][220]:
- draft linears: "radiance_w4 packs block-fp8 weights to 4 bits from inside
  `process_weights_after_loading`, which is the only point where the fp8 weight exists" —
  i.e. at load the F8_E4M3 bulk (1.61 GiB of the file) is REPLACED by W4 + g128 scales
  (≈ 0.81 + ~0.015 GiB) [220];
- draft head: INT2 head 0.167 GiB/RANK at TP2's half-vocab shard; TP1 full 248,320 cols ≈
  **0.33 GiB** (the D36-quoted figure — now sourced: `radiance_drafthead.py` docstring L4-7)
  [219];
- the FAST=0 alternative is NOT cheaper: the stock path keeps the fp8 linear bulk (1.61, not
  0.81) and shares the target's bf16 lm_head (zero residency but 1.18 GiB READ per draft slot,
  ~2002 µs/call vs INT2's ~473 µs) [219]. **`RADIANCE_FAST_DRAFT=0` is an ANTI-LEVER: net
  residency +≈0.5 GiB (estimate: 1.61−0.83−0.33) plus an unmeasured draft lane (every published
  DFlash/MTP number is the "Fast" lane [218]) and a `-fast-draft` graph-cache-namespace change
  (full Triton/AITER recompile on the next boot, entrypoint L22-24/L82-85 [216]).**

**Donor arithmetic at the shipped int4 shape, via the boot-pinned R7 law**
(`needed = blocks × S × page`, page = bs × 1088; the law reproduces the boot paste:
`368 × 8 × 1,845,248 = 5.06 GiB` needed AND `252 × 8 × 1,845,248 = 3.465 → "3.47"` at L = 164,512
— the printed estimate is the same grouped sum solved backwards [195][209]):

| spec lane | buckets | num_spec | GDN page | bs | groups/S | blocks/req @262144 | needed @262144 | Δ resident (vs shipped dflash-K7-fast) |
|---|---|---|---|---|---|---|---|---|
| **dflash-K7 (shipped)** | 48/16/5 | 7 | 1,777,664 | **1696** (boot ✓) | S=8, 9 gr | 368 | **5.06** (boot ✓) | — |
| dflash-K5 | 48/16/5 | 5 | 1,736,704 | 1648 | S=8, 9 gr | 366 | **4.89** | ±0 (same drafter; acceptance 51.92% > K7's 42.26%, weighted 172.3 vs 186.7 [218]) |
| dflash-K4 | 48/16/5 | 4 | 1,716,224 | 1632 | S=8, 9 gr | 362 | **4.79** | ±0 — not a published lane [218] |
| **mtp-K4 (the recorded donor JSON)** | 48/**17**/0 | 4 | 1,716,224 | 1632 | S=6, 11 gr | 531 | **5.27 — RAISES the bar** | ≈ −0.2…−0.7 (drop 1.25-1.5 of packed drafter, ADD the +1 mtp layer resident: the checkpoint's `mtp.*` bf16 island = **0.791 GiB** [211], today DROPPED by the mapper's `"mtp.": None` [206]) |
| no-spec (spec flag absent) | 48/16/0 | 0 | 1,634,304 | 1552 | S=16, 4 gr, **zero padding layers** | 175 | **4.40** | −1.25…−1.6 (drafter pack + INT2 head; mtp island stays unloaded) |

**The mtp-K4 donor is margin-NEGATIVE at int4@262144** — the D36 ledger ("mtp-K4 −2.0, demand
−0.45") is corrected by two facts R6 could not see: (i) the shipped FAST_DRAFT pack already
shrank the drafter, and (ii) the MTP head's own full-attention layer lands in the FA bucket
(48:17:0 mix) and costs 0.21 GiB of grouped demand — the docs' "eagle introduces one full
attention layer" case [198→195] — while its GDN/SWA savings (9→6 blocks, −4) buy back less.
Pool-wise it adds ≤0.7 (estimate) against +0.21 demand: even with f2 (3.47+1.27+0.46 = 5.20)
the 262144 boot still misses 5.27. And the lane carries the whole caveat stack:
- **29/30 scope**: the tool-gate FAIL is the **MTP-K4 lane only** — the publication's 30/30 row
  set: Non-spec 30/30 PASS, MTP K4 **29/30 FAIL** (attempt 006: unfinished `click` JSON object),
  DFlash K5 30/30, DFlash K7 30/30 — all at TP2/FP8-KV/8K/C8/85%/prefix-off [218]. Our shipped
  lane is a 30/30-record lane; switching to mtp-K4 breaks the C04 tools marker's grounding
  sentence directly (the marker's lease is 3.7's tool smoke either way, but the toggle would be
  choosing the record's FAILING lane).
- the recorded donor JSON needs two further edits to even boot at int4: `attention_backend`
  R4D→**TRITON_ATTN** (R4D refuses int4_pth outright [171→R6]) and the
  `RADIANCE_QUARK_BF16_MTP=1` env flip (D25/R3-Q6 coupling) — an env-law amendment + the C03
  drafter-skip re-stage (D26) [R6][STATE].
- (the baked `patch_mtp_mm_mask` fix DOES qualify mtp+vision — "Enables multimodal serving with
  MTP speculative decoding" under `disable_padded_drafter_batch` [222] — that leg is not the
  blocker; the arithmetic is).

**no-spec is the only demand-AND-residency donor**: needed 4.40 (−0.66) and pool +1.3…1.6
(estimate) → boots at 262144 **without** f2 (~4.9–5.1 ≥ 4.40; admit-check 0.95·4.9 = 4.65 ≥ 4.40
✓ thin; with f2 6.2 vs 4.40 = solid). Its price: the measured-lane speed collapse (weighted
186.7 → 53.9, c1 per-request 204.5 → 53.7, the published TP2 table [218]) and the OQ-A owner
mandate ("the 1 MTP head ships active from day one" — the re-scope kept it as spec-on, Q1 chose
dflash). Note the one upside: non-spec is the PUBLISHED 30/30 tool lane [218], so the tools
marker's grounding improves (subject, as always, to int4-KV + TP1 re-qualification at 3.6/3.7).

Decode-speed summary for the donor menu (TP2-published, TP1-transfer labelled estimate):
drop K7→K5 costs ~−8% weighted (172.3) and RAISES acceptance; K4-mtp −27% (135.6) + the 29/30;
no-spec −71% (53.9). Prefill is flat across lanes (4.0-4.5k tok/s [218]) — the donors only
tax decode.

## R8.3 — Mechanics: f2 re-arbitrated at pool 3.47; allocator env sweep

### f2 — `VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=0`, re-arbitrated on measured numbers

Code path @ ced6857a (exact) [209]: `determine_available_memory` runs `profile_cudagraph_memory()`
whenever the mode ≠ NONE (the estimate is COMPUTED regardless — V2 `gpu/cudagraph_utils.py`
L847+: throwaway graph pool, minimal KV, sampled FULL + measured PIECEWISE/spec captures,
discarded), then:

```
peak_activation = transient_peak_headroom + est_applied          (est_applied = est if ENV=1 else 0)
available_kv    = requested − non_kv_cache_memory − est_applied
```

so turning the env OFF adds the FULL estimate to the check-time pool — it does NOT buy
"estimate − real": the real capture happens LATER (`compile_or_warm_up_model` → `capture_model`,
gpu_worker L816) and lands on whatever physical/allocator slack remains, which is exactly why
the engine's own disabled-branch prints the WARNING: "CUDA graph memory is not accounted for
during KV cache allocation, which may require lowering --gpu-memory-utilization to avoid OOM"
(L672-680 [209]).

At the measured boot: requested = ceil(31.86·0.98) = 31.22 GiB; pool 3.47 ⇒ **held ≈ 27.75** ✓
(the commission's 27.76). Estimate at the int4 boot: the fp8 boot's advisory pinned
Δutil 0.0395 → 1.2585 GiB with real capture "took 1.26 GiB" (D36 record); the int4/TRITON boot's
estimate is read live from its own advisory line (`equiv 0.9800 → 0.86xx`) — same capture set
(PIECEWISE, K7 spec, 3-seq decode), assume ≈ 1.26 ± 0.05 [evidence-adjacent estimate]:

- pool@check with f2 ≈ **4.73–4.79**; needed 5.06 → **f2 alone STILL FAILS — by ≈ 0.28–0.33,
  not 0.12**: R7's 0.12 was computed at the predicted 3.67 pool; the real pool landed 0.2 low.
  It converts the silent refusal into the printed ≈243k estimate (law: L = 1696·(4.74 GiB ÷
  14,761,984 − 58) ÷ 2 ≈ **243.4k**), never a boot.
- Post-boot arithmetic if f2 ships: engine footprint at steady state ≈ resident (~20.6–21.5:
  weights 18.438 [211] + packed drafter ~1.25 + INT2 0.33 + HIP ctx 1.2–1.6) + KV pool + graphs
  1.26 + real activation peaks ≤ (measured headroom − est… the est-OFF lane bets the capture on
  the allocator's reserved-unallocated slack + the 0.24 outside-requested). Labelled: the capture
  itself would ride cached blocks the dummy phase already reserved — the risk is the COMBINATION
  (capture + real peak), which the engine explicitly warns about. Moderate risk, not reckless;
  the 3.4 smoke + first long session are the detectors.
- 21-var amendment class: same "PRICED NOT SHIPPED → additive env" shape D36 already framed
  (testlib env pair, T3 dict, AC8 window, runbook 3.5-f2 row promotion).

### PYTORCH_HIP_ALLOC_CONF / expandable_segments — what the evidence says HERE

- Sweep for allocator env in the shipped surfaces: the fork's compose, `.env.example` and both
  Dockerfiles carry **NO** `PYTORCH_*ALLOC*` variable anywhere [214][215][216]; our 20-var law
  carries none either (the retired stock-era overlay's `PYTORCH_ALLOC_CONF=expandable_segments:True`
  died with D7/D25 — cf-105 R1 Q5.5 recorded it as "material on this allocator").
- vLLM's own position @ the pin: (i) the engine DOES bracket weight loading with a
  fragmentation guard `_scoped_allocator_max_split(20 MiB)` — and it early-returns
  `if not current_platform.is_cuda(): yield; return` → **ROCm gets no weight-load allocator
  guard** (gpu_worker L336-341, L505 [209]); (ii) the expandable×KV-connector hard reject reads
  only the `PYTORCH_CUDA_ALLOC_CONF` NAME (config/vllm.py L1091-1108 [209]) — the unified-name
  fix is PR #54351, **OPEN, not in the tag** [223]; (iii) the known incompatibility axes are the
  CuMem allocator / sleep mode (pytorch #147851: expandable + MemPool unsupported; vLLM
  historically error-ed the combo, PR #14189) — **both inert for us** (no sleep mode shipped, Q7
  drop) — and KV connectors (none shipped).
- PyTorch on ROCm: the HIP OOM runtime hint itself prescribes
  `PYTORCH_HIP_ALLOC_CONF=expandable_segments:True` (torch's own message text in vLLM ROCm OOM
  reports [223]); upstream vLLM ROCm OOM threads (#6512 et al.) show the standard fragmentation
  signature (GBs reserved-but-unallocated) that expandable segments reclaim.
- Bearing on THIS ledger: the boot check is arithmetic (pool = requested − measured − est), and
  expandable segments changes neither the weights nor the estimate — it reduces
  allocator RESERVE waste, which is partially what `total_consumed`/`transient_peak_headroom`
  measure (the ROCm fallback path sizes from `torch_memory` = RESERVED [209]). So it can
  recover pool GiB ONLY to the extent real fragmentation waste exists at our boot — unmeasured
  here; no datum says how much (the fp8 paste's "5.7 MiB split-KV scratch" line argues small,
  the missing DEBUG MemorySummary is the only way to know). **Verdict: legitimate boot-day
  experiment (f5 candidate: `PYTORCH_HIP_ALLOC_CONF=expandable_segments:True`, additive env,
  values-side removable), evidence class: mechanism = cited, GiB = pure estimate, no public RDNA4
  datum; do NOT pre-count it in any combo below.**

## R8.4 — THE COMPOSE DIFF (fork-published 256K recipe @ 5b99d66c vs our shipped list)

Their published "working 256K" — stated plainly first [214][215][217]: docker-compose.yml ships
FP8-KV/R4D non-spec TP2 @ **GPU_UTIL 0.85**, seqs 8, len 16384, batched 4096, APC+align; the
header comments record the measured 256K rows:
- `FP8+DFlash @0.85`: **256K:1** seq (the "8K:8 … 256K:1" conservative pair list);
- `MXFP4+DFlash @0.90, APC OFF (+mamba none, K5, batched 4096)`: **256K:2**, min physical
  headroom **5.28 GiB PER GPU** (COMPOSE_CAPACITY requalification on OUR exact checkpoint —
  "amd/…(18.44 GiB) + tcclaviger drafter (1.97 GiB)") [217];
- recommended production profile: **128K:4** with APC+align (576,001 KV tokens reported at TP2).
**Every row is TP2** — two cards halve weights (9.22/GPU), state and attention pages; at
0.85–0.90 they carry 5+ GiB/GPU physical headroom, the regime where none of R8's donors is
needed. Their 256K recipe imports to TP1 as an ARITHMETIC DEAD END: nothing in the compose frees
GiB for us that we do not already have — the diff is instructive about WHAT NOT to expect.

Full env/flag delta list (their compose defaults + `.env.example` vs our 20-var + 45-token ship):

| delta | theirs @ 5b99d66c | ours shipped | what it would free for us |
|---|---|---|---|
| `--tensor-parallel-size` | 2 | 1 | n/a — the caveat, restated |
| `--gpu-memory-utilization` | 0.85 default; 0.90 at the 256K rows | **0.98** | their numbers were never tight; nothing |
| `--max-num-batched-tokens` | 4096 | 2560 | raising ours grows the profile dummy + spec in-flight (demand UP) — never a donor |
| `--max-num-seqs` | 8 (capacity rows: 1-4) | 3 | raising grows nothing at the check (fixed-floor uses 3); lowering barely moves `items_per_batch` — no donor |
| `--kv-cache-dtype` / `--attention-backend` | fp8 / R4D | int4_pth / TRITON_ATTN | shipped D36 — the dtype IS our donor |
| **`--limit-mm-per-prompt`** | **ABSENT** (→ defaults 999/modality [201]) | `{"image": 4}` | removing it frees NOTHING (profile = 1 item at both limits, R8.1b); keeping 4 is fine — our cap is already tighter than their recipe's 999 |
| `--scheduling-policy priority` / `--watermark 0.05` | absent | present (Q7 carries) | watermark −0.05 does not raise the pool (it is admission reserve — see R8.5's admit column); policy priority costs nothing |
| `--swap-space` | **does not exist at 0.30** — zero `swap_space`/`--swap-space` matches tree-wide [200] | n/a | nothing — the V0-era flag is gone; commission question CLOSED as flag-absent |
| `VLLM_ROCM_USE_AITER` + `…_UNIFIED_ATTENTION` (+7 siblings 0) | compose-SET (not baked [216]) | unset → default False [envs L134/L148] | 0 GiB; a kernel-path delta we should know about: their triton-quant/GDN-prefill legs ride the AITER env; our TRITON_ATTN+int4 lane has never been published under their AITER combo — boot-day marker row (3.3) arbitrates |
| `RADIANCE_FAST_DRAFT` | compose default **0**; their DFlash/MTP blocks and ALL published numbers use 1 | 1 | FAST=0 = anti-lever (R8.2 — net +≈0.5 GiB estimate) |
| `RADIANCE_VERIFY_HEAD=1 (+GLOBAL_TOPK=256)` | compose-set, baked 1 | unset (baked 1 reaches us) — ACTIVE via FAST=1 | their own text: "TP2 retains full head; **TP1 shortlist is experimental**", "Global selection is not certified lossless" [214] — our TP1 pod runs the experimental verify path at zero memory cost; `RADIANCE_VERIFY_HEAD=0` is the conservative flip (sampling-aware fallback documented) |
| `RADIANCE_DYNAMIC_DRAFT=1` + SCHEDULE/TAU | baked/compose | unset (baked reaches us) | inert for dflash ("MTP only and inert for DFlash" [214]) — no action |
| AITER/NCCL/CPU-side: `NCCL_PROTO=Simple`, `TORCHINDUCTOR_COMPILE_THREADS=4`, `HIP_FORCE_DEV_KERNARG=0`, `TORCH_BLAS_PREFER_HIPBLASLT=0`, `RADIANCE_FUSE_RMS_QUANT=1`, `TRITON_CACHE_AUTOTUNING=1` | compose-set or baked | image-baked where it matters [216] | 0 GPU GiB each |
| `RADIANCE_AR_MAX_KB=49152` (+AR_QNT/QNB baked) | TP2 staging buffers | unset | TP1: R4D-AR path unused (single rank) — ≈0 |
| `RADIANCE_KV_OFFLOADING_SIZE` | off by default ("keep disabled unless long-context") | unset | NOT live-KV capacity (R6 Option 5 — their own doc); post-boot relief valve only |
| `RADIANCE_FP8_KV_SCALES` sidecar | optional (fp8 lane quality) | unset | inert at int4 |
| `RADIANCE_SPECULATIVE_CONFIG`/`RADIANCE_COMPILATION_CONFIG` env seams | how they pass spec/graph JSON | our CLI-splice + env seam equivalents | transport only |
| healthcheck `start_period: 1800s` | 30 min | probe 40 min | budget parity ✓ |
| **max_pixels / mm-processor-kwargs** | absent from the recipe | absent from ours | **the sweep's real find** [207]: `--mm-processor-kwargs '{"max_pixels": P}'` is honored on BOTH sides of the mm machinery at the pin — the dummy builder (`get_image_size_with_most_features` merges `max_pixels`/`min_pixels`/`size` into the processor's `longest_edge`, qwen2_vl.py L969-998, inherited by Qwen3_5ProcessingInfo via Qwen3VLProcessingInfo [207]) AND real request processing (`_get_vision_info`, qwen3_vl.py L957-963) — so the rehearsal peak, the encoder budget and the runtime worst case all shrink CONSISTENTLY with the cap: dummy = ⌈P/1024⌉ tokens, self-compatible (no stall), marker TRUE. At P = 4,194,304 (2048×2048): mm peak 1.9 → ≈0.5 ⇒ **frees ≈ 1.3 GiB of insurance (estimate)** with the sacrifice "images larger than 2048² are auto-downscaled". P = 1,048,576 (1024²): frees ≈1.6, cap 1 MP. |
| `ImageDummyOptions` width/height (`{"image": {"count": 4, "width": W, "height": H}}`) | n/a (they set no limit at all) | n/a | shrinks ONLY the dummy — and thereby re-derives the encoder budget DOWN to `max(2560, W·H/1024)`, while real images up to 16,384 tokens still arrive → the single oversized item exceeds the derived cache budget and **risks never being schedulable** (code-static hazard read of `compute_mm_encoder_budget`'s max-guard being fed the shrunk dummy [202][203]). FLAGGED UNTESTED — do not ship without boot-day proof. The safe expression of the same intent is max_pixels. |

`RADIANCE_GFX_ARCH`, the MXFP4 W4A8 seven-var block, `RADIANCE_WEIGHT_QUANTIZATION=auto`,
V2-runner, PIECEWISE — already byte-matched in our law (D25/D34/D36); no further delta exists
between the shipped env and the published recipe.

## R8.5 — The combo table + the ONE owner question

Bar re-pinned from the boot: pool 3.47, needed 5.06 → the 262144 boot needs **+1.59 GiB**; the
gate below is `pool ≥ 5.06` (check) AND `0.95·pool ≥ 5.06` (watermark admission of one full
session — the printed 164,512 does NOT include the watermark reserve: today's pool admits a
max session of ≈ 0.95-law → **~154k**, a one-line correction to D37's B-cap ruling source).

| # | combo | class of each Δ | pool | needed | boot 262144 | full-session admit | sacrificed | evidence |
|---|---|---|---|---|---|---|---|---|
| 0 | shipped as-is (D37 running path) | — | 3.47 (measured) | 5.06 | ✗ → prints 164,512 (measured) | ≈154k @0.95 | cap (B) | measured |
| 1 | **f2 alone** | estimate pre-tax | ≈4.74 | 5.06 | ✗ → prints **≈243k** | ≈231k | cap (B, better) | est (law-based) |
| 2 | `{"image":1}` | — | 3.47 | 5.06 | ✗ | — | multi-image prompts, **for 0 GiB** | evidence [203][205] |
| 3 | `{"image":0}` / `--language-model-only` alone | rehearsal-peak | ≈5.1–5.7 | 5.06 | borderline ✗/✓ | ✗ without f2 | **vision FALSE** + req#3/C04/M3/3.4/D34-orphan | est [201][202][203] |
| 4 | f2 + `{"image":0}` | estimate+peak | ≈6.4–7.0 | 5.06 | ✓ | ✓ | vision FALSE | est |
| 5 | f2 + `--skip-mm-profiling` | estimate+peak | ≈6.4–7.0 | 5.06 | ✓ | ✓ | insurance OFF: a real full-size (16.7 MP) image arrives with ~1.9 GiB unreserved — first-large-image runtime-OOM exposure, vision TRUE | evidence of the skip [204]; risk = estimate |
| 6 | **f2 + `--mm-processor-kwargs {"max_pixels": 4194304}`** ← recommended | estimate+cap | ≈**6.0–6.3** | 5.06 | ✓ | ✓ (5.9 ≥ 5.33) | image-resolution ceiling 2048² (larger auto-downscaled); scheduler self-consistent; vision TRUE; K7/tools TRUE | evidence that the cap flows to both dummy+real [207]; GiB = estimate |
| 7 | f2 + no-spec | estimate+resident | ≈6.0–6.4 | **4.40** | ✓ | ✓ ✓ 1.6 margin | **spec decode off** (−71% c1 [218]; OQ-A mandate); 20-var law unchanged (specConfig splice out), drafter dir inert | law-computed needed; est resident |
| 8 | f2 + mtp-K4 | mixed | ≈5.0–5.5 | **5.27** | ✗/borderline | ✗ | −27% c1 + the 29/30 TOOL-FAIL lane + 2 extra edits (JSON backend re-pin, BF16_MTP env) — **the worst trade on the board; retire it as a boot donor** | law-computed [195][209][218][219] |
| 9 | `RADIANCE_FAST_DRAFT=0` | ANTI-lever | −0.4…−0.8 | 5.06 | ✗ worse | — | +fp8-vs-W4 residency, unpublished lane, graph-cache recompile | est [219][220] |
| 10 | `PYTORCH_HIP_ALLOC_CONF=expandable_segments:True` (+f2) | allocator waste | +0…+? | 5.06 | unpriced | — | none intrinsic; mechanism cited, magnitude unmeasured on RDNA4 — f5 experiment, same day as the DEBUG re-boot (f3) | cited mechanism [209][223], GiB = no datum |
| 11 | K5 depth swap (values-only JSON) | needed −0.17 | 3.47 | 4.89 | ✗ | — | −8% weighted, acceptance UP (55.79 class) [218]; a companion to #6/#7, not a standalone | law-computed |
| 12 | compose imports (all rows of R8.4) | — | 0 | — | ✗ | — | the published recipe frees nothing for TP1 — the 256K rows live on TP2's halved residency | evidence [217] |

**The "donors + higher-B-cap package" leg (owner's parenthetical):** if ANY 262144 sacrifice is
too expensive, the pure-B ladder rises with the donors: no donor → cap 164,512 (measured print);
f2-only → cap ≈ 243k (estimated print, zero surface sacrifice except the f2 env + its capture
bet); f2+max_pixels → 262,144 itself holds (row 6), i.e. the cap ladder reaches the true axis
before any vision or spec sacrifice. There is no reason to accept 164,512 if the owner wants
262144 — but the cap choice is now a priced menu.

### R8-Q1 — the one owner question (one answer requested)

**"Which donor package do you rule for the 262144 boot?"** (bar: pool 3.47 → 5.06, +1.59 GiB;
the "drop vision?" instinct is priced: it does NOT free the 0.858 GiB tower — only the ≈1.9 GiB
rehearsal — and it kills requirement #3, so it is row 4, not a shortcut):

- **(A — recommended): f2 + `--mm-processor-kwargs {"max_pixels": 4194304}`** — boots 262144,
  keeps vision + dflash-K7 + tools + the 262144 advertisement TRUE; pays a 2048×2048 image
  ceiling (larger images downscale — pick the cap with the owner's actual photo use; 2 MP and
  1 MP variants free ≈1.0/≈1.3) + the f2 capture-bet; ship surface = 21-var env + 47-token
  serveArgs (testlib + T3 + AC8 + runbook re-pins — the standard amendment loop).
- **(B): f2 + `--skip-mm-profiling`** — same boot math with NO quality cap, but the first
  full-resolution image can OOM the running pod (insurance off). Vision TRUE on paper, risky on
  the wire.
- **(C): f2 + `{"image": 0}`** — the owner's literal "drop vision": boots clean (≈6.4–7.0),
  but the marker flips FALSE, requirement #3 falls, the flash-attn install is orphaned, 3.4
  retires.
- **(D): no donor, cap at the print** — today's designed path (D37): cap = the printed number,
  ≈154k effective after the watermark (or lower `--watermark` to make the print honest).
- **(E): f2 alone + cap on the re-print** — ≈243k effective ~231k (estimated print), only the
  f2 env ships, no quality or vision sacrifice, the cap stays below the true axis.
- (Row 7 — f2 + spec-off — is on the board but named-ugly: −71% decode against the whole "1m
  heads" mandate; listed for completeness.)

Best guess: **(A)** — it is the only combo that clears 262144 with every card requirement TRUE
and no runtime-OOM exposure; if the owner refuses the resolution cap, (E) buys ~243k for one env
var and no other edit.

## Contradictions and how to weigh them (R8 conflict map)

1. **D36/D37 ledger ("`{"image":1}` profile-day knob", "INT2 head 0.33", "mtp-K4 −2.0")** vs
   this round's encoder-budget clamp, FAST_DRAFT-packed residency, and mtp-K4 demand-raise: the
   earlier entries were reasonable at their information state (they priced the FILE and assumed
   the limit scaled the dummy). Weigh: the pinned code + the fork's own drafthead docstring —
   `{image:1}` saves 0, `FAST_DRAFT=0` is negative, mtp-K4 is boot-irrelevant. The D36 ledger
   sentence "the donors stay named-not-shipped" survives only for no-spec and image:0.
2. **"Drop vision" as a weight story (owner framing; R6's "vision ≈0.6" figure)** vs the
   header-exact 0.858 GiB that NO flag unloads: both under-count what the owner expects and
   over-count what is liberable — the real vision-side donor is the ≈1.9 GiB rehearsal, not the
   weights at all. Weigh: safetensors header read + qwen3_5 source [206][211] are the authority;
   the Qwen4Exp conditional-tower precedent shows upstream CAN do the skip — qwen3_5 at our tag
   simply does not [208].
3. **The fork publishes a working 256K row** vs our TP1 arithmetic dead end: TP2 halves
   weights/state/pages and they run 0.85-0.90 with 5.28 GiB/GPU physical headroom — no
   contradiction, different planet (R6 conflict #5 carried and re-confirmed by COMPOSE_CAPACITY's
   own conditions [217]).
4. **Engine printed 164,512 vs R7's predicted ~171k**: the law fit is exact at the measured
   pool (252 blocks × 14,761,984 = 3.465 ↔ 3.47); the −7% miss is the pool landing 3.47 not
   3.67, not the grouping model. The grouping/geometry verdict stands re-confirmed on target.
5. **"expandable_segments helps on ROCm" (torch hint, cf-105 era)** vs zero datum at our shape:
   mechanism cited, magnitude none — kept out of every combo total.

## Implications for the plan (coord/plan own these; this round wrote only RESEARCH.md)

- **(A)-answer follow-on** is a one-pair+one-var values amendment (same leg shape as D36's
  named-not-shipped f2 promotion + a new `--mm-processor-kwargs` token pair): values serveArgs +
  env, testlib env_want/serveArgs pairs, C02 AC7/AC8 comment windows, T3 dict + T5 needles, C05
  3.5 f2-row rewrite ("f2 + max_pixels shipped, boot arithmetic: pool ≈6.0 vs 5.06") and the
  envelope block's mm row; the runbook gains the 4-MP image ceiling as a documented behavior and
  the 3.4 smoke keeps full force. No C01/C03/C04 change (marker TRUE, tower story unchanged).
- The D36 "donors named" ledger line is SUPERSEDED on two entries: `{image:1}` → 0 GiB;
  mtp-K4 → demand-negative. Replace with the R8.5 table.
- f3's ask GAINS a second settling line: the `Encoder cache will be initialized with a budget of
  16384 tokens, and profiled with 1 image items…` INFO [205] — one paste closes both the weights
  datum AND the mm-peak class.
- B-print honesty law: the engine's estimated-max-length is PRE-watermark — the cap ruling
  should target ~0.90–0.95× the print or drop `--watermark` at the capped shape (row 0/D math).
- The TP1 verify-head shortlist discovery (`RADIANCE_VERIFY_HEAD=1` baked + our FAST=1 →
  experimental global-256 TP1 path live in our pod [214][215][216]) is a NEW adjacent
  qualification note for the 3.6/3.7 gate day (zero memory; correctness-path note — it self-
  falls-back for grammar-constrained/logprobs steps per the .env comment).
- renovate/CI/no-surface laws unaffected; every row above is values-side.

## Open questions (no-questions-rule log — round 8, for coord → owner)

- **R8-Q1** (one question, options (A)-(E) + recommendation) — see R8.5.
- Non-blocking asks carried: the f3 paste pair (Model-loading line + the encoder-budget INFO) and,
  if (D)/(E) is chosen, one fresh engine-print capture at the f2 shape before the cap ruling.
- Carried untouched: R5-Q2 (crash-#2a ValueError provenance) still open; D37 running path stands
  until R8-Q1 answers.

## Sources (R8)

All reads 2026-11-09 at the exact pins: vLLM @ `ced6857afa0ea7b2e3f0846a62e1394e90f15607` (= the
v0.30.0 tag commit; whole-tree tarball fetched + extracted this session), radiance @
`5b99d66c844fd…` (tree + compose + docs + overlay sources), HF revisions `93245f7c…` /
`ee0cb26a…` (safetensors HEADERS read by HTTP Range — tensor tables, not guesses).

200. vLLM @ ced6857a — `vllm/engine/arg_utils.py` — `--language-model-only` L586/L1367/L1855; `--limit-mm-per-prompt` L587/L1370; `--mm-processor-kwargs` L595/L1379; `--skip-mm-profiling` L621/L1424/L1860; `--convert` L879; **negative sweep: `--swap-space` / `swap_space` zero matches tree-wide incl. this file — the flag does not exist at 0.30** — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/engine/arg_utils.py
201. Same — `vllm/config/multimodal.py` — `language_model_only` L91-93 verbatim ("…by setting all modality limits to 0. Equivalent to `--limit-mm-per-prompt` to 0 for every modality"); `BaseDummyOptions/VideoDummyOptions/ImageDummyOptions/AudioDummyOptions` L23-52; configurable limit format L103-108; validator L255-277; `get_limit_per_prompt` L478-492 (0 under LMO; **999 default for an absent modality** — the fork's unset-limit posture); `skip_mm_profiling` L208; `mm_ipc_gpu_memory_gb` default 0 [180-carried] — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/config/multimodal.py
202. Same — `vllm/v1/core/encoder_cache_manager.py` L293-339 — `compute_mm_encoder_budget`: the all-limits-0 WARNING + `return 0,0`; `budget = max(max_num_encoder_input_tokens, max_tokens_per_mm_item)` with both scheduler fields = `max_num_batched_tokens` (`vllm/config/scheduler.py` L284-285), the disable-chunked-mm ValueError guard — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/v1/core/encoder_cache_manager.py
203. Same — `vllm/multimodal/encoder_budget.py` (read in full) — `MultiModalBudget`: tower vs embed-only modality sets, `mm_counts = fromkeys(active, 1)` max-token derivation, `_get_max_items` (`items_per_prompt = max(1, min(limit, seq//max_item))`, `items_per_batch = max(1, min(enc//max_item, reqs×prompt))` — **the clamp that makes 4 ≡ 1 for the profile batch**); `get_dummy_encoder_profile_inputs` (one item × items_per_batch copies) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/multimodal/encoder_budget.py
204. Same — `vllm/v1/worker/gpu/model_runner.py` L938-975 — **V2 runner** `profile_run`: `skip_mm_profiling` guard → MultiModalBudget(enable_cache=False) → get_dummy_encoder_profile_inputs → `profile_encoder_cache` → `_dummy_run(max_num_tokens, skip_attn=True, is_profile=True)` — the exact path our V2 pod runs; `profile_cudagraph_memory` delegating to cudagraph_utils L983 — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/v1/worker/gpu/model_runner.py
205. Same — `vllm/v1/worker/gpu/mm/encoder_runner.py` L111-155 — `profile_encoder_cache`: budget≤0 early return, the embedding-only skip line, the boot-day INFO marker `"Encoder cache will be initialized with a budget of %s tokens, and profiled with %s %s items of the maximum feature size."`, execute + cache tmp_i; V1 counterparts `_dummy_mm_kwargs` raw-input-only guard (L1736-1747), V1 profile_run same text (`gpu_model_runner.py` L6464-6560) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/v1/worker/gpu/mm/encoder_runner.py
206. Same — `vllm/model_executor/models/qwen3_5.py` — `Qwen3_5ForConditionalGeneration.__init__` L486-528: tower built UNCONDITIONALLY inside `_mark_tower_model(vllm_config, {"image","video"})` (L513-519); `load_weights` L438-440 bare AutoWeightsLoader; `hf_to_vllm_mapper` drops ONLY `mtp.` (L322, L478); zero `language_model_only` references in the module; registry: `Qwen3_5ForConditionalGeneration → ("qwen3_5", …)` (`models/registry.py` L597) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/model_executor/models/qwen3_5.py + …/registry.py
207. Same — `vllm/model_executor/models/qwen2_vl.py` L969-1000 + `qwen3_vl.py` L940-1200 — `get_image_size_with_most_features(max_pixels=None)`: merges ctx mm-kwargs `size/min_pixels/max_pixels` over `image_processor.size` (both the dummy path L1128-1129 AND the real `_get_vision_info` L957-963 honor the override → **self-consistent cap**); `get_dummy_mm_data` builds at the max-feature size; `Qwen3_5ProcessingInfo(Qwen3VLProcessingInfo)` (qwen3_5.py L106); `vllm/multimodal/processing/dummy_inputs.py` `_get_dummy_images`: ImageDummyOptions width/height = shrink-only, dummy-time ONLY (with the R8.4 budget-coupling hazard note) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/model_executor/models/qwen2_vl.py + qwen3_vl.py + …/processing/dummy_inputs.py
208. Same — `vllm/config/vllm.py` L1311-1321 (LMO × `cudagraph_mm_encoder` ValueError); `vllm/models/qwen4_exp/{amd,nvidia}/model.py` L877-954 + L1016/1047 (`language_model_only` conditionally building the tower and mapping `{"visual.": None}`) + `qwen3_next.py` L365 `text_only` — the existence-proof that the skip-load pattern exists upstream but not for qwen3_5; `config/model.py` L395/477/528/796 LMO plumbing (hash factor + config threading only) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/config/vllm.py + model trees
209. Same — `vllm/v1/worker/gpu_worker.py` L113-140, L330-365, L455-700, L773-905 — `maybe_rocm_profiling_fallback` (ROCm sizes from torch RESERVED on measured release, #45490); `_scoped_allocator_max_split` (20 MiB max_split during `load_model` L505) **CUDA-only early-return L338-341**; `determine_available_memory`: estimate computed when mode≠NONE (ROCm included, #44825 comment), `est_applied = est if VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS else 0`, `available = requested − non_kv − est_applied`, `peak_activation = headroom + est_applied`, enabled-advisory INFO (equiv/suggested util lines) and the DISABLED-branch WARNING ("may require lowering --gpu-memory-utilization to avoid OOM"); `compile_or_warm_up_model`: capture AFTER sizing, the actual-vs-estimated INFO line, the 150 MiB redundancy note + the consumed/peak/CUDAGraph breakdown msg — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/v1/worker/gpu_worker.py
210. Same — `vllm/v1/worker/gpu/cudagraph_utils.py` L847-925 — `profile_cudagraph_memory`: throwaway-pool estimate, "PIECEWISE, encoder and speculator graphs are measured in full", FULL sampled+extrapolated, captures discarded — the estimate is a faithful pre-capture of the SAME set that captures later (why est ≈ real 1.26 on this lane) — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/v1/worker/gpu/cudagraph_utils.py
211. HF `amd/Qwen3.8-27B-Quark-AWQ-MXFP4` @ `93245f7c…` — `config.json` full fetch: `architectures ["Qwen3_5ForConditionalGeneration"]`, **top-level `language_model_only: false`**, `vision_config {depth 27, hidden 1152, num_heads 16 (=head_dim 72), intermediate 4304, out_hidden 5120, patch 16, merge 2, temporal 2, dtype bfloat16, deepstack []}`; `text_config` re-verified (64 layers/interval 4/head 256/kv 4/linear 16-48×128/conv 4/ssm float32/mtp layers 1/vocab 248320/untied); QUANT `exclude` 127 — plus the **safetensors header HTTP-Range read of `model.safetensors`**: total 19,797,976,544 B = 18.438 GiB; buckets: `model.visual.*` 333 tensors **921,460,192 B = 0.858 GiB**; `mtp.*` 15 tensors **849,398,784 B = 0.791 GiB**; `lm_head` 2,542,796,800 B (2.368 GiB); embed 2,542,796,800 B; dtypes {BF16 703, U8 992 (packed fp4 + e8m0 scales)} — https://huggingface.co/amd/Qwen3.8-27B-Quark-AWQ-MXFP4/raw/93245f7c…/config.json + …/resolve/93245f7c…/model.safetensors (bytes 0-219,639 range-read; header length 219,632)
212. Same repo/revision — `preprocessor_config.json` — `Qwen2VLImageProcessorFast`, patch 16, merge 2, temporal 2, `size {longest_edge: 16,777,216, shortest_edge: 65,536}` → max image = 16,384 merged vision tokens — https://huggingface.co/amd/Qwen3.8-27B-Quark-AWQ-MXFP4/raw/93245f7c…/preprocessor_config.json
213. HF `tcclaviger/Qwen3.8-27B-DFlash2-FP8` @ `ee0cb26a…` (repo sha f02593d0, weight etag-identity carried [R3]) — model API `?blobs=true` + tree: `model.safetensors` **2,118,882,784 B** single file (sha256 7dbb99a8…), `model-kvscales.safetensors` 1,324 B, `kv_calibration_report_mtp.json`, config 3,256 B; safetensors metadata: BF16 194,254,080 params + F8_E4M3 1,730,150,400 (total 1,924,404,480) = 2,118,658,560 B payload; `DFlash2DraftModel` config geometry carried [167] — https://huggingface.co/api/models/tcclaviger/Qwen3.8-27B-DFlash2-FP8?blobs=true + …/tree/ee0cb26a…
214. magiccodingman/vllm-radiance @ 5b99d66c — `docker-compose.yml` (read in full) — args block: TP `${TP:-2}`, seqs 8, len 16384, util `${GPU_UTIL:-0.85}`, batched 4096, kv fp8, backend R4D, APC+align (+ the 1664-bs-note comment — R7 conflict #3 carrier), no-async, tool trio, generation auto + xhigh, trust, host/port, **no `--limit-mm-per-prompt` and no `--swap-space` anywhere**; env: measured pair tables ("8K:8 … 256K:1" FP8; "32K:8 64K:6 128K:4 256K:2" MXFP4@0.90-APC-off), AITER family (9 vars), RADIANCE_USE_R4D master + siblings, DYNAMIC_DRAFT=1 (MTP-only, inert dflash), FAST_DRAFT `${:-0}`, VERIFY_HEAD=1/GLOBAL_TOPK 256 ("TP1 shortlist experimental"), AR trio, KV-offload trio, FP8_KV_SCALES, V2-runner `${:-0}`, PIECEWISE seam, NCCL_PROTO/COMPILE_THREADS/caches, start_period 1800s, zero `PYTORCH_*ALLOC*` — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/docker-compose.yml
215. Same pin — `.env.example` (read in full) — MXFP4 block (auto + W4A8 set), **MTP block: `RADIANCE_SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":8,"attention_backend":"R4D","disable_padded_drafter_batch":true}'` + FAST_DRAFT=1 + BF16_MTP "only when selecting its MTP profile"**, DFlash2 block: heretic-ara + `draft_tensor_parallel_size:2` + `max_model_len:8192` reproduction ("the measured dual-R9700 K7 lane"), target-matched tcclaviger pointer for Quark checkpoints, PREFIX_CACHING_FLAG/MAMBA_CACHE_MODE benchmark-override notes, selector-topk, tool-grammar flags 0 — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/.env.example
216. Same pin — `Dockerfile` + git-tree API — pins (TORCH 2.12.0@6bbd2602, TRITON 3.7.1@f0b55c07, AITER 0.1.20@fc2e5d57, R4D v0.5.0@e8de4bc1, VLLM ced6857a/0.30.0); ENV L342-347 (gfx/arch/`SAFETENSORS_FAST_GPU`/autotuning — NO allocator env, NO AITER env) and the baked flags block L352-366 (`RADIANCE_USE_R4D=1 … RADIANCE_KV_GROUP_OPT=1 … RADIANCE_DYNAMIC_DRAFT=1 … RADIANCE_DRAFT_RERANK=64 RADIANCE_VERIFY_HEAD=1 R4D_ATTN_FP8=0 RADIANCE_FAST_DRAFT=0 RADIANCE_RUN_BWTEST=1`); the 35-patch application order incl. `patch_mtp_mm_mask`; COPY list (`radiance_vit_attn.py`, `radiance_drafthead.py`, `radiance_w4.py`…); tree scan: NO qwen3_5 overlay files — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/Dockerfile + api.github.com git/trees
217. Same pin — `docs/COMPOSE_CAPACITY.md` — the qualification conditions (TP2 2×R9700; MXFP4 continuation on `amd/Qwen3.8-27B-Quark-AWQ-MXFP4 (18.44 GiB)` + `tcclaviger DFlash2 (1.97 GiB)`, **K5 drafts, draft TP2, TRITON_ATTN, mandatory FP8 KV, 90% alloc, APC-off + mamba-none for the high-capacity sweep**; 256K:2 burst 1,969.6 total TPS, **min physical headroom 5.28 GiB/GPU**; recommended production 128K:4 with APC+align, "576,001 usable KV tokens / 4.39x"; the 12.8× prefix-TTFT datum; "DFlash2 remains experimental … strict greedy-equivalence fails" + non-transferability warning) — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/docs/COMPOSE_CAPACITY.md
218. Same pin — `docs/V030_PUBLICATION_20260922.md` — mode comparison (Weighted/c1/c8: non-spec 53.9/53.7/304.1; MTP K4 135.6/140.6/463.9 **tool FAIL 29/30** — attempt 006 unfinished `click` JSON; DFlash K5 172.3/182.4/610.4; K7 186.7/204.5/510.2); acceptance table (K4 55.79% log-scope, K5 51.92%, K7 42.26%, 3.596/3.958); prefill 4.0-4.5k flat; conditions (TP2, FP8 KV, 8K/C8, 85%, 4096, prefix off, WPERM/NT-safe, FAST lanes: MTP = V2 MTPSpeculator/Qwen3_5MTP + INT2-g128 exact-top-64); "PUBLICATION_SET_COMPLETE_WITH_MTP_TOOL_QUALIFICATION_FAILURE"; the four-MODE lane list incl. `mtp-k4` [108-carried, re-read] — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/docs/V030_PUBLICATION_20260922.md
219. Same pin — `radiance_drafthead.py` — FAST gate docstring: "0: nothing installs; stock bf16 head shared with the target (`_maybe_share_lm_head` … costs no extra memory) reads **1.18 GiB/rank** per draft slot, ~2002 µs/call; 1: INT2 head **0.167 GiB/rank** @ the TP2 half-vocab W[5120,124160] → TP1 full 248,320 cols ≈ 0.33 GiB, ~473 µs incl. exact rerank"; RERANK default 32 (image bakes 64); the DFlash top-k hard-ceiling datum (R=32: acc/draft 1.904→1.804, 2R too tight for K=16); the shared-lm_head packing-reuse note (L287-289) — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/radiance_drafthead.py
220. Same pin — `patch_dflash_w4.py` — "radiance_w4 packs block-fp8 weights to 4 bits from inside process_weights_after_loading, **the only point where the fp8 weight exists**"; the `set_model_tag("dflash_head")` bracket (drafter-only discriminator) — the W4-replaces reading for the R8.2 residency delta — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/patch_dflash_w4.py
221. Same pin — `radiance_vit_attn.py` — the head-dim-72 native ViT attention kernel, "installed as a drop-in for the ViT SDPA per-segment apply … **Active on gfx12x with RADIANCE_USE_R4D on**"; fall-through rules — the tower-attention route on our pod (R8.1b peak-shape corroboration) — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/radiance_vit_attn.py
222. Same pin — `patch_mtp_mm_mask.py` — the MTP + disable_padded_drafter_batch mm-placeholder-mask crash fix, "Enables multimodal serving with MTP speculative decoding" — the vision-on-mtp capability leg — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c…/patch_mtp_mm_mask.py
223. Allocator web cluster (read today): vLLM issue **#6512** (ROCm docker; the HIP-OOM text "…4.72 GiB is reserved by PyTorch but unallocated. If reserved but unallocated memory is large try setting `PYTORCH_HIP_ALLOC_CONF=expandable_segments:True`…"); issue **#27706** (Qwen3-VL profile_run OOM 256 GiB on the torch-SDPA ViT fallback — the no-flash-attention peak class, closed by flash-attn/aiter installs — our D34 posture's cousin); vLLM **PR #54351** **OPEN** (created 2026-08-29, `merged_at: null`; "the two safeguards inspect only `PYTORCH_CUDA_ALLOC_CONF`" → the unified `PYTORCH_ALLOC_CONF`/`PYTORCH_HIP_ALLOC_CONF` names are invisible to them at our tag); pytorch **#147851** (expandable_segments × CUDAPluggableAllocator/MemPool unsupported — the sleep-mode/cumem axis, inert for us); vLLM PR #14189/commit 71c4b40 (the historic sleep-mode × expandable error-out) — https://github.com/vllm-project/vllm/issues/6512 + /issues/27706 + /pull/54351 + https://github.com/pytorch/pytorch/issues/147851
224. Boot data (the commission's given pair, the owner's live paste): `needed 5.06 / available 3.47 / estimated maximum model length 164,512` @ the D36 int4 boot — law-fitted: 368×8×1,845,248 = 5.06 GiB (bs 1696 confirmed) and 252×8×1,845,248 = 3.465 → "3.47" at L = 164,512 = 1696×97 exactly [195-continuation; repo: C02 values at HEAD, D36/D37 records, STATE d36/d37 legs]

## Reliability notes (R8 self-review)

- **High confidence (source @ exact pins, read this session end-to-end):** no flag skips the
  tower LOAD for qwen3_5 — unconditional build + bare loader + mapper-drops-mtp-only, triple-
  cited [206][208][211]; `{"image":1}` ≡ `{"image":4}` for the profile batch (the budget chain
  is mechanical: 16384/16384 = 1 item [202][203][205]); the f2 formula and ordering (est
  computed-then-not-applied; capture after sizing [209][210]); the drafter file bytes and param
  split [213]; FAST_DRAFT's W4-replaces + INT2 sizes [219][220]; the compose's 256K-rows-all-TP2
  and absent mm/swap/allocator flags [214][215]; the max_pixels override flowing to BOTH dummy
  and real paths [207]; the published speed/tool table incl. the 29/30 lane-scope [218]; the
  boot paste fitting the grouped law exactly (both numbers) [195][224].
- **Medium confidence:** the ≈1.9 GiB max-item rehearsal peak (input/output terms pinned;
  activation coexistence is a modelling estimate ±0.4 — one DEBUG re-boot prices it exactly);
  the no-spec/mtp-K4 residency deltas (the W4-replaces reading is a docstring, not a memory
  trace: ranges given, f3's Model-loading line arbitrates); the mtp-K4 48:17:0 bucketing (the
  docs' eagle-+1-full-attn pattern + the fetched mtp geometry; boot log settles it); f2's
  estimate ≈1.26 at the int4 boot (the fp8 measurement transfers; the advisory line is the
  check); the cap-ladder numbers (243k/154k/231k — linear-law reads, ±3% with bs).
- **Low confidence / explicit gaps:** the ImageDummyOptions width/height STALL hazard is a
  code-static read (no test executed — flagged "do not ship unproven"); zero measured
  fragmentation datum for the expandable_segments row (mechanism cited only); the int4+TRITON
  engine estimate was never pasted; no GPU session — every GiB is arithmetic or estimate; the
  radiance internal line stays unreadable [R5 precedent].
- **Weakest claim of the round:** the R8.5 row-6 (recommended) margin — pool ≈6.0 depends on
  the mm-peak estimate (1.5-2.2 range → pool 5.7-6.4 vs bar 5.06; clears across the whole
  range, which is why (A) pairs f2 — row 3's alone column flips sign inside that range).
  Stated plainly: (A) is robust; single-lever image-0 is not.
- **Perspective weighting:** the pinned code + the boot paste outrank the records we are
  correcting (D36's ledger priced the FILE and assumed the limit scaled the dummy — reasonable
  then, superseded now); the fork's own docs/compose decide WHAT their 256K was, the arithmetic
  decides whether it transfers (it does not).
- **Blind spots (stated):** the V2 spec-drafter's own profile path (the drafter dummy-run peak
  is inside the measured held, unseparately priced — the f2 estimate covers its graphs); the W4
  requant's transient staging (load-window, folded into "±"); the `patch_dflash_fused_kv_fp8`
  overlay's interaction with our int4 pool (3.6's startup leg is the detector);
  `--enable-mm-embeds` as the limit-0 escape (exists [201], not relevant at our surface); the
  exact encoder-cache tmp-tensor lifetime inside the peak measurement; whether the fork's AITER
  default differs from the stock False inside the entrypoint preamble (grep-clean, assumed no).

---

# R8b — image-0 verification: does dropping vision actually clear 5.06 — and what the boot gate does WITHOUT the mm rehearsal

(The owner ruled **C — drop vision** from R8-Q1. This round closes the one arithmetic class R8
left open — the mm rehearsal is a TRANSIENT peak inside the insurance term, so the question is
not "what is the dummy worth" but "does removing it move the binding max". Verdict lines first,
mechanics after.)

**VERDICT LINES** — (1) the encoder dummy IS skipped at image-0, but ONLY if the flag zeros
EVERY supported modality — qwen3_5 supports {image, video} [227], so bare `{"image": 0}` leaves
video at its 999 default and the rehearsal PROFILES A VIDEO MAX-ITEM INSTEAD (same class, same
cost); ship `--language-model-only` (or the explicit `{"image": 0, "video": 0}` pair) [226][227].
(2) The KV group composition is mm-INDEPENDENT: needed stays **5.06** (the encoder cache is
activations, not KV [229]). (3) C-pure lands pool = 3.47 + δ with δ bounded ≈[0.16, 2.1] and
binding-uncertain → a COIN FLIP (clears only if the encoder phase is the binding profile peak
by ≥1.59); **the minimum pairing that likely clears is C + f2** (needs only δ ≥ 0.32; worst-case
δ still misses 5.06 by ~0.16), and the only δ-certain pairing keeps dflash dropped (C+no-spec).
δ closes in ONE boot line. (4) Fallout is a clean values-scope amendment; the 0.858 GiB tower
stays resident — C buys insurance, never weight (restated for exact owner expectation).

## R8b.1 — Does profile_run still create the mm dummy at limit-0? NO — via the text-only short-circuit (exact chain, V2 runner = ours)

- `supports_mm_inputs = mm_registry.supports_multimodal_inputs(model_config)` — V2 runner
  `gpu/model_runner.py` L262-264; the V2 `profile_run` mm block opens
  `if self.supports_mm_inputs and self.is_first_pp_rank:` (L938-941 [204]).
- `registry.py` L108-149 [226]: docstring "Returns True if the model is multimodal with any
  non-zero supported modalities, otherwise returns False, **effectively running in text-only
  mode**"; the check is
  `if all(mm_config.get_limit_per_prompt(m) == 0 for m in info.supported_mm_limits)` →
  `return False` (unless `enable_mm_embeds`), logging the true boot marker
  `All limits of multimodal modalities supported by the model are set to 0, running in text-only mode.`
  (INFO-once, L146-149). **R8.1c's marker note is CORRECTED here**: the
  `compute_mm_encoder_budget` WARNING [202] does NOT fire on this path — the whole
  MultiModalBudget build is skipped before it; the INFO above is the line to grep on boot day.
- **The flag choice twist** — `supported_mm_limits` for our arch: `Qwen2VLProcessingInfo.get_supported_mm_limits()`
  returns **`{"image": None, "video": None}`** (`qwen2_vl.py` L869-870), inherited verbatim
  through `Qwen3VLProcessingInfo` (`qwen3_vl.py` L910 [207]) and `Qwen3_5ProcessingInfo`
  (`qwen3_5.py` L106) — video IS a supported modality. An absent modality in the user limit
  dict defaults to **999** (`config/multimodal.py` get_limit_per_prompt L487-492 [201]), so
  `{"image": 0}` alone is NOT all-zero → supports stays TRUE → the budget runs on
  `tower_modalities = {video}` (the `>0` filter, `encoder_budget.py` L80-88 [203]), and
  `get_dummy_encoder_profile_inputs` builds the max video dummy — the qwen3_vl dummy path
  spreads the whole `longest_edge` budget over ≥2 frames (`qwen3_vl.py` L1162-1190 [207]) →
  the SAME ≈16,384-token max-item class, ≈ the same peak, **and the C04 fallout still applies
  to image while the memory saving is zero-effectiveness-adjacent (you freed the image dummy
  and replaced it with a video one)**. `--language-model-only` zeroes EVERY modality at the
  getter (L483-484 [201]) → all-zero → text-only, dummy skipped, `{"image": 0, "video": 0}` is
  the equivalent explicit pair. **Ship `--language-model-only`.** (Video is NOT advertised in
  our catalog rows — R8b.4b — so dropping it costs nothing beyond the image ruling itself.)
- With the block skipped, the remaining profile peak = the pure-LLM phases:
  `_dummy_run(max_num_tokens=2560, is_profile)` — note: **2560, not 262k** (no 262k-token dummy
  ever runs; 262144 lives only in the check formula) — INCLUDING the V2 drafter's full dummy
  `speculator.propose(..., dummy_run=True)` (L860-912 [228]) and the sampler run
  (`_dummy_sampler_run`, rows = `hidden_states[logits_indices]`, L916-930 [228]); encoder
  inputs/activations/cache-outputs are simply never allocated.

## R8b.2 — KV group composition at image-0: needed UNCHANGED at 5.06

The kv-cache spec dict is built from the language-side attention layers only — 16 FA
(FullAttentionSpec) + 48 GDN (MambaSpec) + 5 drafter (SlidingWindowSpec) [155][156][172]; the
vision encoder contributes NO KV spec anywhere (its output embeddings are ACTIVATIONS merged
into inputs_embeds per step; the encoder cache is a scheduler-budgeted activation store,
`encoder_cache_size` in tokens [202][226]). The `bs = 1696` derivation is mamba-page vs
attention-bytes only (interface.py L923-925 [184]) — mm-independent. The 58-block fixed floor
(6 GDN groups × 9 + 1 SWA × 4) contains no mm term. Therefore the boot gate at image-0:
`needed = (58 + 2·⌈262144/1696⌉) × 8 × 1,845,248 B = **5.06 GiB — unchanged**, S=8/9-groups/
60.00%-padding marker pair unchanged, watermark behavior unchanged. (The 0.858 GiB tower keeps
sitting in `total_consumed` regardless [206][211] — permanent, unfreed.)

## R8b.3 — The boot arithmetic: what the pool actually gains, and the minimum pairing

Exact accounting @ ced6857a (`utils/mem_utils.py` L283-321 [229], worker side [209]):
- `total_consumed = free_before − free_after` (physical, permanent: weights incl. tower + HIP
  ctx + persistent buffers); `transient_peak_headroom = torch_peak − torch_allocated` AT THE
  END of profile_run (peak reset at profile start L286; the peak is the MAX over the SEQUENTIAL
  phases: encoder-run → LLM-dummy+drafter-propose → sampler); `non_kv = total_consumed +
  transient_peak_headroom`; `available = requested − non_kv − est_applied`.
- ⇒ the mm rehearsal lives in the **headroom term as a phase-max competitor**, not an additive
  line: dropping it removes δ = (peak_with_mm − peak_without_mm), with
  - **upper bound** δ ≈ the encoder phase itself, **1.5–2.1 GiB** (R8.1b table [211][212]:
    pixel 0.19 + per-layer acts 1.2–1.8 + embeds) — reached only if the encoder phase was the
    binding peak;
  - **floor** δ ≈ 0.164 GiB — the encoder-cache tmp outputs [225-carry: encoder_runner
    L144-146] stay allocated through the drafter/sampler phases (reset at profile_run's end,
    V2 L971-973 [204]), so they inflate every other phase's peak by ≈ their size;
  - which bound applies is NOT decidable statically: the K7 drafter's full dummy propose over
    2560 tokens is exactly the competing peak R8's reliability notes flagged blind. Estimate-class,
    range-bounded, **one boot line settles it: `Available KV cache memory: X` vs the shipped
    3.47 ⇒ δ = X − 3.47.**
- Pool arithmetic at C: requested 31.22 held 27.75 pool 3.47 ⇒ pool_C = **3.47 + δ ∈
  [3.63, 5.57]**; boot needs δ ≥ **1.59** — possible, NOT guaranteed: **C-pure is a coin flip.**
- Pool at C+f2 = 4.74 + δ ∈ [4.90, 6.84]: needs δ ≥ 0.32 — clears on any realistic
  encoder-near-binding case, misses by ≈0.16 only in the pathological sampler/drafter-binding
  tail; full-session admission (0.95·pool ≥ 5.06 [R8.5]) wants δ ≥ 0.85 — likely with f2, not
  certain. **⇒ MINIMUM PAIRING (verdict): C + f2**, both in one amendment (f2 was already the
  D36-priced companion; the owner's C ruling does not remove the need for it).
- δ-certain pairings require the spec drop: **C + no-spec** clears at ANY δ (needed 4.40 ≤
  worst pool 4.93 + the freed drafter/INT2 resident 1.3–1.6 [R8.2]) — the one combination that
  needs no f2, no hope, and no boot-day arithmetic. If C+no-spec is the fall-through, say so
  before the ship pass.

## R8b.4 — C-scenario fallout, record-grade

- **(a) ship form**: `--language-model-only` as a single token REPLACES the
  `("--limit-mm-per-prompt", '{"image": 4}')` pair (values.yaml L200-201, shipped 45-token
  serveArgs → 44) — bool flag at the pin (arg_utils L1367 [200]), so the D32 JSON law is simply
  not exercised; the L147-148 "vision tower serves" comment block is a re-pin target (it now
  states the opposite), and the `kvCacheDtype`/48GB-RDNA3 comment (L45) gains the vision-drop
  rider (R8b.4e).
- **(b) C04 catalog**: the three vLLM rows `.opencode/opencode.jsonc` L795-813 carry
  `capabilities: {input:["text","image"], output:["text"], tools:true}` (L798/805/812, verified)
  → `input` drops to `["text"]` on all three (the image leg goes FALSE by the honest-grounding
  law — engine refuses images); **no audio/video legs exist** to change; **`tools:true` STAYS**
  (tool parsing/serving is text-side: the `qwen3_coder` parser + tool trio ride unchanged; the
  3.7 smoke remains the marker's lease). `tests/pipeline-models/surface.sh` M3 capability asserts
  re-pin (C04 surface); `limit.context 262144` untouched. Requirement #3 ("keep vision") is
  superseded BY THE OWNER'S OWN RULING — the DECISIONS entry must carry the verbatim.
- **(c) runbook rows killed/re-pinned** (`.agents/notes/vllm-on-target-acceptance.md` + the
  `vllm-runbook.sh` L488-490 needles): step-3 **ViT backend marker row L344** (the RDNA FA
  literal + the MMEncoderAttention per-layer confirm) → ABSENT by design, its "absence = drift"
  reading INVERTS (absence becomes the expected state; the new positive marker is the registry
  INFO "running in text-only mode" [226]); **3.4 multimodal smoke L440-444** + the 3.6-legs list
  "2. The 3.3 and 3.4 smokes" (L594) → 3.4 retired, 3.3/1-token stays; the D34/D35 flash-attn
  pip layer + the (8)-slot env var become **decorative-but-harmless** (the package has no
  caller — the ViT never runs; the 20-var law stays byte-identical, the var goes inert);
  crash-#2's whole ViT-FA class is dead by absence (footnote in the 3.4 retirement line). The
  **f1 marker pair is unaffected** (R8b.2), the KV triple + estimate rows unchanged in kind,
  the mm-IPC reserve stays 0 [201 L253].
- **(d) what the owner does NOT get**: no weight bytes — the staged 18.438 GiB file is what it
  is, the loader builds and loads the visual island anyway [206][211]: **0.858 GiB resident
  dead weight persists** and the ONLY C-side memory effect is the δ slice of the insurance term
  (R8b.3). Expectation sentence: "dropping vision frees boot-time insurance (≈0.2–2.1 GiB of
  the held), never the tower."
- **(e) reversibility**: the full drop-and-restore is values-side — the serveArgs token pair,
  the three catalog rows, the M3 asserts, the runbook rows; a future 48 GB card (the OQ3/
  48GB-RDNA3 ledger note, values L45 + D36's rider) restores the exact removed lines — record
  them VERBATIM in the amendment (the `{"image": 4}` pair + L344 marker row text) so the
  re-enable is a copy-back, not an archaeology.

## R8b-Q1 (one line, for the coordinator to put to the owner)

**"C ships PAIRED with f2 (`VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=0`) — pure-C boots a coin
flip (δ ∈ [0.16, 2.1], bar δ ≥ 1.59), C+f2 needs only δ ≥ 0.32 and any refusal still prints a
fresh cap (≥243k + δ) — or go certain with C+no-spec (−71% decode, δ-immune)?"** (No second
question; the δ answer arrives with the boot's `Available KV cache memory:` line either way.)

## Sources (R8b)

225. Carried R8 artifacts re-read at this round's line targets: `vllm/v1/worker/gpu/mm/encoder_runner.py`
  L111-155 (profile_encoder_cache; tmp outputs stored into `encoder_cache.encoder_outputs`
  L144-146) + V2 `gpu/model_runner.py` profile_run L938-973 (encoder-cache reset AFTER the LLM
  dummy + sampler runs — the coexistence that floors δ at ≈0.164 GiB) — ced6857a tree [204][205].
226. vLLM @ ced6857a — `vllm/multimodal/registry.py` L108-149 — `supports_multimodal_inputs`:
  docstring "effectively running in text-only mode" L112-113; the **all-supported-modalities-
  zero check** L137-141 (`all(get_limit_per_prompt(m) == 0 for m in info.supported_mm_limits)`),
  the enable_mm_embeds exemption, the INFO-once text-only marker L146-149 — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/multimodal/registry.py
227. Same — `vllm/multimodal/processing/context.py` L455-491 (`supported_mm_limits`/`allowed_mm_limits`
  definitions: omitted modality = unsupported, `None` = unlimited → user limit wins) +
  `qwen2_vl.py` L869-870 (`get_supported_mm_limits → {"image": None, "video": None}`) +
  `qwen3_vl.py` L910 / `qwen3_5.py` L106 (the inheritance chain that gives OUR arch a video
  modality) — the bare-`{"image":0}`-profiles-a-video-dummy finding — https://raw.githubusercontent.com/vllm-project/vllm/ced6857a…/vllm/multimodal/processing/context.py + …/qwen2_vl.py
228. Same — `vllm/v1/worker/gpu/model_runner.py` L262-264 (supports_mm_inputs ← registry call),
  L860-912 (V2 `_dummy_run` runs the FULL `speculator.propose(..., dummy_run=True, is_profile=…)`
  inside the profile — the competing peak), L916-930 (`_dummy_sampler_run`, rows = logits_indices,
  the NOTE that profile-time sampling skips top_k/top_p/logprobs = less memory than real) — [204-file, line-targeted re-read].
229. Same — `vllm/utils/mem_utils.py` L283-321 — `memory_profiling`: peak-stats reset at profile
  start L286; `after_profile.measure()` at context exit; `total_consumed = before_create.free −
  after_profile.free` L312-314; **`transient_peak_headroom = torch_peak − torch_allocated`**
  L316-319 ("add only the transient peak headroom to avoid double-counting");
  `non_kv_cache_memory = total_consumed + transient_peak_headroom` L321 — the formula that makes
  the mm rehearsal a phase-max competitor, not an additive donor.
230. Repo at HEAD (re-verified at this write): `charts/vllm/values.yaml` L200-201 (the shipped
  `--limit-mm-per-prompt '{"image": 4}'` pair), L147-148 (the "vision tower serves" comment —
  re-pin target), L45 (48GB-RDNA3 note); `.opencode/opencode.jsonc` L795-813 (the three vLLM
  rows, capabilities L798/805/812 = `{input:["text","image"],output:["text"],tools:true}`,
  context 262144); `.agents/notes/vllm-on-target-acceptance.md` L344 (ViT marker row) / L440-444
  (3.4 smoke) / L594 (3.6 legs "3.3 and 3.4"); `tests/notes/vllm-runbook.sh` L488-490 (the 3.4/
  multimodal/data-URL needles) — repo paths as cited.

## Reliability notes (R8b self-review)

- High: the text-only short-circuit + all-limits check [226]; the video-supported inheritance
  chain → the flag-choice twist [227]; headroom = phase-max formula [229]; needed/bs/group
  mm-independence [226][155][184 re-applied]; the boot-marker correction (INFO, not WARNING)
  [226]; the repo-side re-pin inventory [230].
- Medium: the δ bounds [0.164, ~2.1] (coexistence floor + encoder-peak ceiling — both
  mechanism-cited, exact value boot-pending); the C+f2 "likely clears" read (needs the encoder
  phase within ~0.3 of binding — the K7 drafter-propose peak is its only plausible rival).
- Low: nothing new; no GPU run (again) — δ, the estimate line, and the rival peak all close on
  the first image-0 boot paste.
- Weakest claim: the δ floor 0.164 assumes the tmp embeds were allocated at full 0.164 during
  the later phases (true at image:4 max-item; self-correcting once the `Model loading` +
  `Available KV` pair arrives). If the drafter phase binds, C-pure fails nearly the FULL 1.59 —
  stated plainly: **do not ship C without f2.**

## R9. int4-per-token-head × per-seq-causal: the assert, the trigger, and the three escape routes priced

Decision brief on the D38-boot paste [252]: pool X=5.73 GiB, 262,144 sizing **PASSED** (`GPU KV cache size: 297,049 tokens`, `Maximum concurrency 1.13x`) — then EngineCore died: `AssertionError: INT4_PER_TOKEN_HEAD only supports causal attention`, fired in the DFlash2-speculator territory right after the radiance VERIFY_HEAD banner. The f2 WARNING + the 60.00% pairing warnings printed exactly as D38 priced; the LMO text-only path was accepted (`model_type=qwen3_5_text`) — the D38 package itself is VINDICATED; this is a new, third int4 defect class.

### R9.1 — The assert: located, and the trigger NAMED (it is the drafter's CAUSALITY — not per-seq, not SWA)

- Site @ `ced6857a`: `vllm/v1/attention/ops/triton_unified_attention.py` — `unified_attention` L807; L857-859 resolve causal (`use_per_seq_causal = isinstance(causal, torch.Tensor)`; `use_causal = bool(causal)`); the INT4 branch L863-866: `assert use_causal and not use_per_seq_causal, "INT4_PER_TOKEN_HEAD only supports causal attention"` then dispatches to the bespoke `int4_per_token_head.unified_attention_int4` [231]. The assert is STRUCTURAL: the int4 sub-kernel takes no `causal` parameter at all — `window_size` yes (SLIDING_WINDOW compiled in, L728/799), causality hardcoded [232]. It is a kernel-capability statement, not a config-validation warning.
- The flag plumbing: `CommonAttentionMetadata.causal: bool | torch.Tensor` (backend.py L416 [234]) → TRITON builder pass-through verbatim (triton_attn.py L236, impl call L666; the backend advertises `supports_non_causal=True` L319-321 [233]) → a non-causal request sails through config validation and meets the assert at the FIRST KERNEL CALL. The Tensor branch has exactly ONE producer in-tree — diffusion_gemma's per-request causal buffer (L1000-1018) [235]. Our arch is not it: **the clause that failed is `use_causal` being False (plain bool), not per-seq** — the brief's "per-seq-causal" title names the assert's second clause, the crash is the first.
- Who asks non-causal: the DRAFTER. The V2 dflash speculator builds per-KV-group causality from the draft model (`_group_causal = {gid: layer_causal}` via `model.get_draft_attn_causal()` — dflash/speculator.py L221+L233-237, applied at L162/L458 [236]; `attn_utils.py` L435-438: "Per-group causal for hybrid drafters" [235]). `get_draft_attn_causal` returns per-layer `self_attn.causal` (qwen3_dflash.py L751); DFlash2 inherits the layer classes unchanged (qwen3_dflash2.py L16-18/L104/L235/L269) [237][238].
- The smoking gun — the drafter's own config: `tcclaviger/Qwen3.8-27B-DFlash2-FP8` `config.json` (raw-fetched today): **`"is_causal": false`**, `layer_types` = `sliding_attention`×5, `sliding_window: 2048`, `num_key_value_heads: 8`, `head_dim: 128` [239]. `_dflash_layer_causal` (qwen3_dflash.py L59-64) checks `is_causal` FIRST — it OVERRIDES the all-SWA layer_types default (SWA would be True): all 5 draft groups resolve causal=False [237]. This is intended DFlash semantics — block diffusion emits the whole K-block non-causally in one pass; the in-tree table lists "standard DFlash, all full attn, assumes non-causal" [237] and `SpeculativeConfig.attention_backend`'s docstring says verbatim "DFlash needs a backend that supports non-causal attention" [240].
- Therefore the crash path: global `--kv-cache-dtype int4_per_token_head` is INHERITED by the draft (docstring verbatim [240]) → the 5 drafter groups are int4 → first drafter attention call (profile/warmup or spec graph-capture — pre-serving, startup-loud, deterministic) → causal=False × INT4 → assert. **Trigger = spec-config presence × the global dtype; K-depth irrelevant** [236][237].
- Record correction to R6.3's support framing: this assert is the GUARD that shielded us from the #48721 SWA×int4 crash — our 5-SWA-layer drafter never reached that broken kernel path (#48842's fix branch would have been the NEXT wall [169][246]). And the drafter's head_dim 128 is inside #53086's wrong-values failing-shape class [168][246]: int4-on-drafter is the single worst landing of all three open defects — the target FA groups (head 256, causal, non-SWA) exercise NONE of the three.

### R9.2 — Escapable by CONFIG @ the pin? (a) NO · (b) YES — two sanctioned expressions · (c) NO · (d) NO

- **(a) `num_spec_tokens: 1`** — no. Causality resolves from the checkpoint config only; no K coupling anywhere in `_dflash_layer_causal` [237]. The K1 drafter still runs non-causal → same assert. Verdict: not an escape.
- **(b) per-drafter/per-group KV dtype** — YES. R6's "dtype is global" held for `--kv-cache-dtype` itself but was INCOMPLETE at the pin — two first-class surfaces exist:
  - **(b1) spec-JSON key**: `SpeculativeConfig.kv_cache_dtype: CacheDType | None` — "When `None`, the draft inherits the target model's `--kv-cache-dtype`" (speculative.py L416 [240]); the dflash loader consumes it verbatim: `cache_config=replace(..., cache_dtype=speculative_config.kv_cache_dtype)` when non-None (dflash/utils.py L31-39 [241]). Ship diff = add `"kv_cache_dtype":"auto"` to the existing `specConfig` string — drafter groups go bf16, the 16 target FA groups stay int4. The docstring just above (`moe_backend`: "quantized generator with unquantized drafter") proves this mixed posture is a designed use case [240].
  - **(b2) top-level flag**: `--kv-cache-dtype-skip-layers` — live at the pin (cache.py L155-158: "Accepts layer indices … or attention type names (e.g. 'sliding_window')" [242]; CLI arg at arg_utils.py L1294 [243]; matcher at attention.py L297-318 → matched layers force `kv_cache_dtype="auto"` [244]). Our target has ZERO SWA layers (GDN×48 + full-FA×16 [EXPLORE §3]) so `sliding_window` matches exactly the 5 drafter layers — and this route additionally gets the purpose-built mixed-page machinery: Phase-3 `_align_heterogeneous_kv_block_size` (interface.py L650-657 + L700-760: `skip_page_size_padded`, the `Setting attention block size to %d tokens so the quantized primary KV page covers the higher-precision padded-spec page` INFO) [245].
  - Cost, both variants: drafter group per-token KV 5×1,088 B (int4, head-128) → 5×4,096 B (bf16) = ×3.77 on its SLICE (~4 blocks/request of the 368 ≈ 0.11 GiB of the 5.06 bar) → grouped demand ≈ **5.4–5.5 vs the MEASURED 5.73** — boot expected, margin ~0.25; D37's live-law (the engine's grouped print, the bs INFO, the padding percentages) arbitrates, and any refusal still prints a cap. Verdict: the only config route that keeps BOTH mandates — and it structurally sidesteps ALL THREE int4 defects (#48721/#53086/#62946) since they all live on the drafter side.
- **(c) the fork carries its own patch** — NO. Tree-wide grep @ `5b99d66c` for `INT4_PER_TOKEN|per_seq_causal|only supports causal` = zero hits; the 35-patch application list has no int4-KV/causal entry [250]. `patch_dflash_fused_kv_fp8.py` is despite its name about the draft's WEIGHTS (fused context-KV GEMM via identity-dequant [250]) — not the KV cache. Their 256K qualification is fp8-KV+R4D only [214]: on int4×spec the fork's silence is absence, not knowledge.
- **(d) reordering / shape surgery** — NO. The assert keys on the causal flag, not on the SWA-vs-full group assignment; a full-attn DFlash variant assumes non-causal too ("standard DFlash … assumes non-causal" [237]), so no spec-JSON/`--mamba-cache-mode` shape removes the non-causal ask short of removing the drafter (= route A). The 378/368 no-SWA re-prices are moot against this assert.

### R9.3 — The routes priced (owner's ruling menu — the brief's A/B/C plus the pin-surfaced A′)

| Route | Ship diff | Mandates | Boot odds @262144 | Effort |
|---|---|---|---|---|
| **A′ (b1): spec-JSON `"kv_cache_dtype":"auto"`** | ONE key inside `specConfig` (+ testlib/T3/AC8 JSON re-pins; the old JSON verbatim-recorded) — values-only | q4 KEPT (target axis) + dflash KEPT | GOOD — est demand 5.4–5.5 vs pool 5.73 measured; assert class structurally gone; mixed-page bump risk = the only unknown (Phase-3/unify, D37-law reads it) | LOW — one JSON key + suite re-pins + owner boot |
| A: drop the spec config | remove the `("--speculative-config", *specConfig)` pair; JSON verbatim-recorded for re-enable (the D38 mm-pair precedent); specMethod record key survives | q4 KEPT, **dflash DROPPED** — −71% decode class (186.7→53.9 c1 [218]) | BEST — needed 4.40 [R8.5 row 7] < 5.73 with 1.33 margin BEFORE the resident credit (drafter −1.25–1.6 GiB) row 7 books — δ-immune by construction | LOW — one pair-out |
| B: keep spec, revert kv dtype fp8 | `kvCacheDtype` re-pin | dflash KEPT, **q4 BROKEN** ("I _need_ q4") | **DEAD at 262144 — arithmetic**: fp8 demand 9.51 (crash #4's grouped print) > pool 5.73; the only spec-keeping fp8 shape is capped ≈ 5.73/9.51×262144 ≈ 158k (same-class print expected) — off-mandate twice over | moot (owner-ruled against) |
| C: base re-pin to a newer radiance build | C01 thin-overlay digest chain (Dockerfile + ledger + Hub probe + CI) + values pin | both, eventually | **NOT-VIABLE TODAY, twice**: (1) Docker Hub latest is STILL 1.0.397 = our pin (verified today, no tag since 2026-10-18 [248]); (2) even at v0.33/main the assert SURVIVES verbatim (main L998-1000 [247]) and no int4×causal fix is filed anywhere (search total 0 [246]) — C would NOT fix this crash. Note: fork main merged `codex/vllm-033-rdna4-upgrade` TODAY (Dockerfile@main VLLM 0.33.0@4ba787ec + fresh dflash fixes — UNPUBLISHED [249]): the watch trigger fires when the next `1.0.<n>`/`sha-` pair publishes. | HIGH (fresh round + CI + boot) — a re-bench, not a fix |

### R9.4 — The two free wins recorded regardless of route

1. **The δ law is CLOSED: δ=0.99 measured.** X=5.73 = 4.74 + 0.99 ∈ R8b's [0.16, 2.1] [229][252]; 297,049 = 1.133×262,144 ✓; watermark check 0.95×5.73 = 5.44 ≥ 5.06 → a FULL 262144 session admits. The D38 boot arithmetic is DONE — and the pool is dtype-INDEPENDENT (printed before sizing), so A/A′ inherit 5.73 exactly; the remaining boot question is only the grouped NEEDD line.
2. **ssm-bf16 STAYS — and the GDN fused-path loss is older than this crash.** The warning is the fork's: `radiance_gdn.py` L225/L438 — the fused all-R4D GDN path rejects foreign ssm state dtypes, our `--mamba-ssm-cache-dtype bfloat16` trips exactly that gate, and the step falls back to the op-level seams; what the fused path is worth is documented: the conv output (34 MB per layer per rank) never reaches HBM [251]. Reverting ssm-bf16 costs +0.71 on the demand bar → 5.73−0.71 = 5.02 < 5.06 — **MISSES by 0.04**: the flag is load-bearing for 262144, keep it, price the perf loss on the bench day, not the boot day. Ordering note: `_fb` prints once at the FIRST GDN step = warmup = before the sizing lines the pastes carried — so it must have fired on every D36-package boot (crashes #5+) unseen-in-window, and could NOT have fired on the pre-D36 crash-#4-era boots (fp32 ssm then [D36 record]).

### R9.5 — R9-Q1 (the ONE owner question, with the recommendation)

**"int4 landed on the drafter, and the drafter by design asks non-causal attention — the assert is structural at the pin AND still stands on today's upstream main, so no re-pin fixes it. Take A′ — add the single key `"kv_cache_dtype": "auto"` to the dflash spec JSON, keeping BOTH mandates (q4 KV on the target axis AND dflash-K7), expected to boot at 262144 (est. demand 5.4–5.5 vs the measured 5.73 pool), and it sidesteps all three open int4 defects at once (SWA-crash #48721 with its unmerged fix, the head-128 wrong-values flaker #53086 — the drafter IS head 128 — and the RHT sync guard #62946), with route A (drop the spec pair, −71% decode, JSON verbatim-recorded) as the designed fall-through if the grouped print disagrees? Route C stays ledger'd: fork main merged a vLLM-0.33 RDNA4 upgrade TODAY but published nothing — the next 1.0.<n> tag is the watch trigger, and even then it re-benches, it does not fix this crash."**

## Sources (R9)

231. vLLM @ `ced6857a` — `vllm/v1/attention/ops/triton_unified_attention.py` — `unified_attention` L807; causal resolution L857-859; INT4 branch + assert L863-866; `unified_attention_int4` dispatch (no causal arg); `USE_PER_SEQ_CAUSAL` constexpr L1135 — https://raw.githubusercontent.com/vllm-project/vllm/ced6857afa0ea7b2e3f0846a62e1394e90f15607/vllm/v1/attention/ops/triton_unified_attention.py
232. Same pin — `vllm/v1/attention/ops/int4_per_token_head.py` — `window_size` L678/728, `SLIDING_WINDOW` L799, wrapper L892-929; no `causal` parameter anywhere — the bespoke kernel is causality-hardcoded.
233. Same pin — `vllm/v1/attention/backends/triton_attn.py` — L236 (builder passes `common_attn_metadata.causal`), L666 (impl call), L294-304 (`supported_kv_cache_dtypes` incl. int4/int8/fp8_per_token_head), L319-321 (`supports_non_causal=True`); re-read of [163].
234. Same pin — `vllm/v1/attention/backend.py` — `CommonAttentionMetadata` L385; `causal: bool | torch.Tensor = True` L416; `unpadded()` per-seq slice L530-540.
235. Same pin — `vllm/v1/worker/gpu/attn_utils.py` L412/L435-438/L467 (`build_attn_metadata`, "Per-group causal for hybrid drafters"); `vllm/model_executor/models/diffusion_gemma.py` L1000-1032 — the ONLY in-tree Tensor-causal producer.
236. Same pin — `vllm/v1/worker/gpu/spec_decode/dflash/speculator.py` — L62-65 (`dflash_has_any_non_causal` import), L118 (`use_non_causal` into backend selection), L221 (`_group_causal` default), L233-237 (per-group map via `get_draft_attn_causal`), L162/L458 (applied to capture + draft runs); `dflash2/speculator.py` L13 (inherits `DFlashSpeculator`).
237. Same pin — `vllm/model_executor/models/qwen3_dflash.py` — `_dflash_layer_causal` L59-70 (`is_causal` config wins over the SWA default), `dflash_has_any_non_causal` L71-77, the layer-type/causal table + checkpoint precedents L92-150 (MiMo `use_swa` non-causal row; "z-lab/Qwen3.5-9B-DFlash — standard DFlash, all full attn, assumes non-causal"), `get_draft_attn_causal` L751-755.
238. Same pin — `vllm/model_executor/models/qwen3_dflash2.py` — L16-18/L104/L235/L269: DFlash2 layers/model/head subclass the DFlashQwen3 chain (causal logic unchanged).
239. HuggingFace raw fetch 2026-11-09 — `tcclaviger/Qwen3.8-27B-DFlash2-FP8` `config.json`: `is_causal:false` · `layer_types` sliding_attention×5 · `sliding_window:2048` · `num_attention_heads:32`/`num_key_value_heads:8` · `head_dim:128` · `dflash_config` {block_size 8, target_layer_ids [5,19,33,47,61], selector_top_k 16} · fp8-dynamic weights with selector/norms/conv excludes — https://huggingface.co/tcclaviger/Qwen3.8-27B-DFlash2-FP8/raw/main/config.json (staged revision `ee0cb26a` is config-byte-identical to main [106]).
240. vLLM @ `ced6857a` — `vllm/config/speculative.py` L411-418 — `attention_backend` docstring ("DFlash needs a backend that supports non-causal attention") + `kv_cache_dtype: CacheDType | None = None` ("When `None`, the draft inherits the target model's `--kv-cache-dtype`") + `moe_backend` sibling ("quantized generator with unquantized drafter").
241. Same pin — `vllm/v1/worker/gpu/spec_decode/dflash/utils.py` L14-40 — `load_dflash_model`: `use_non_causal=dflash_has_any_non_causal(hf_config)` + `cache_config=replace(vllm_config.cache_config, cache_dtype=speculative_config.kv_cache_dtype)` iff non-None.
242. Same pin — `vllm/config/cache.py` L155-158 (`kv_cache_dtype_skip_layers`: indices or `sliding_window` name) + L161-166 (`skip_page_size_padded`, "set during block-size alignment so unquantized skip layers pad up to the quantized primary's page").
243. Same pin — `vllm/engine/arg_utils.py` L733-734/L1294/L2109-2118 — `--kv-cache-dtype-skip-layers` is a REAL CLI flag at the pin, wired into CacheConfig.
244. Same pin — `vllm/model_executor/layers/attention/attention.py` L295-318 — the skip matcher: name `sliding_window` iff `sliding_window is not None`, or `extract_layer_index(prefix)`; a match → `kv_cache_dtype="auto"`.
245. Same pin — `vllm/platforms/interface.py` L644-657 (Phase-3 gated on the skip list) + L700-760 (`_align_heterogeneous_kv_block_size`: `required_page`, the block-size bump INFO, `skip_page_size_padded = shared_page`) + `vllm/v1/core/kv_cache_utils.py` L1365-1427 (`unify_kv_cache_spec_page_size` — the generic path the spec-JSON variant would take).
246. GitHub API 2026-11-09 — vllm-project/vllm: #48721 OPEN (issue), #48842 OPEN/unmerged (fix PR), #53086 OPEN, #62946 OPEN/unmerged; `search/issues repo:vllm-project/vllm INT4_PER_TOKEN_HEAD causal` → **total_count 0** — the assert class is not even filed upstream.
247. vLLM `main` raw fetch 2026-11-09 — `triton_unified_attention.py` L998-1000: the identical assert STILL stands on current main → any v0.33+/main base re-pin inherits this crash unchanged.
248. Docker Hub API 2026-11-09 — `magiccodingman/vllm-radiance/tags`: `latest`=`1.0`=`1.0.397`=`sha-5b99d66c844f` all 2026-10-18 (= our pin), nothing newer; GitHub tags/releases API: empty (the release-branch publish law, D12/D23, holds).
249. GitHub API commits 2026-11-09 — `magiccodingman/vllm-radiance` main since the pin: `codex/vllm-033-rdna4-upgrade` merged TODAY (`38669dffa7`), `Dockerfile@main` `ARG VLLM_VERSION=0.33.0`/`VLLM_COMMIT=4ba787ec…`, fresh dflash fixes (`79c6df027b` 033-installer port, `3d4cc7c985` DFlash KV-weights materialization, `2dd48aa434` INT2-head fallback, `dbcfbf10ef` INT2/INT4 packing gate) — all UNPUBLISHED (no tag) [248].
250. Radiance fork @ `5b99d66c` — `patch_dflash_fused_kv_fp8.py` full read (the fused context-KV GEMM for QUANTIZED DRAFT WEIGHTS via identity dequant; KV-cache dtype untouched) + Dockerfile patch list + tree grep: zero int4-KV/causal/per-seq patches.
251. Same pin — `radiance_gdn.py` — L190-198 (the fused path's value: conv output 34 MB/layer/rank never reaches HBM; the narrow deliberate gate), L223-225 (`_fb`: once-per-reason WARNING "step not handled by the fused path"), L438/L141 (state-dtype gates — `torch.bfloat16` ssm_state fails the fused gate by design; the fallback is correctness-preserving).
252. Owner's D38-boot paste (this round's kickoff text, 2026-11-09): `Available KV cache memory: 5.73` / `GPU KV cache size: 297,049 tokens` / `Maximum concurrency 1.13x` / the assert + its location after VERIFY_HEAD / the f2 WARNING and the 60.00% pairing warnings / the LMO text-only acceptance — boot evidence.

## Reliability notes (R9 self-review)

- High: the assert site, the causal-resolution chain and the trigger (`is_causal:false` in the drafter config) — every link re-read at the pin trees TODAY [231-241]; both per-group dtype surfaces real at the pin [240-245]; no-newer-tag and assert-on-main for C [246-249]; δ=0.99 arithmetic (5.73−4.74, 297049/262144, 0.95×5.73) closes D38's bracket [229][252].
- Medium: the A′ demand estimate 5.4–5.5 (×3.77 on the drafter slice at bs 1696 — the grouped print is the authority, and which of unify-vs-Phase-3 paths the spec-JSON variant takes was NOT re-derived); the ssm-bf16 revert math (0.04 miss) shares the same single-δ-sample caveat.
- Weakest claim: if the drafter bf16 page forces a pool-wide page inflation beyond +0.44, A′ misses and prints a cap — exactly the D37 B-on-print fall-through absorbs it, with A one values-pair behind; the next owner boot line settles it either way.

## R10. Route C audited: the fork's unpublished 0.33 line, how to consume it pre-publication, and what vLLM 0.33 itself costs

Kickoff ruling (owner, 2026-11-09, verbatim): "Can you follow up on C and research what it'd take to use what they have already? I'd like a link to the repo and for you to see if I can expect any issues with 0.33." A′/A declined; this round audits the R9.3 row-C object against every surface live-read TODAY [253-275].

**TL;DR (5 lines)**
- THE REPO: **https://github.com/magiccodingman/vllm-radiance** — public, browsable, 163★, active; the same owner/repo name the Hub images carry; the 0.33/RDNA4 upgrade merged to its `main` TODAY at 18:39:01Z (`38669dffa7`, GitLab MR !49) plus four follow-on fix PRs (head now `07e4ed5c`), and the `release` branch merged main at 19:13:43Z (`fc9d4a26`) — yet the registry is STILL empty of it: live tag-lists this read (twice) show latest = `1.0.397` = `sha-5b99d66c844f` = our pin [253-259].
- Their 0.33 base is vLLM **v0.33.0 @ `4ba787ec…`** — the exact commit the `v0.33.0` annotated tag resolves to [255]. The int4×causal assert **stands verbatim in that commit** (`triton_unified_attention.py` L884-888), the int4 kernel still has NO causal parameter (0 hits), and none of their 37 active overlays touches it — **route C does NOT fix our crash; it modernizes the base** [262-264].
- Consuming "what they have" pre-publication: (a) WAIT for their next Hub tag — zero OUR-work now, the existing C01 base-bump duty fires on the tag; (b) BUILD their main ourselves = compiling torch 2.13/ROCm 10 from source (hours-class; no prebuilt wheels at their pins; our `docker-build.yaml` has no `timeout-minutes` → the 360-min job cap is the wall); (c) "pin an artifact from their CI" is a DEAD channel — their GitHub publish workflow is `.disabled`, the GitLab project is not on gitlab.com (404), no GHCR, candidate images live only on their host [260][261][272-274].
- Issues to expect with 0.33 (verified at the tag + their own upgrade doc): `--mamba-cache-mode` is **ignored** (deprecation warning) — our pair drops; `AITER_ROOT_DIR` is **dead** (→ `AITER_JIT_DIR`) — our env law + exact-set test churn; f1 marker line-numbers move; the D35 flash-attn layer needs a re-smoke on torch 2.13/triton 3.8. Everything else of ours survives: TRITON_ATTN, int4 dtype, spec-JSON `kv_cache_dtype` (A′-b1), `--kv-cache-dtype-skip-layers` (A′-b2), LMO, ssm-bf16, f2=0, watermark, native DFlash2 K7 (their smoke PASSED on our exact drafter fixture revision!) [266][268].
- Honest package: **C+A′, not C** — and A′ is valid at BOTH pins, so ship A′ today on 1.0.397 and let C ride its watch trigger; when the tag lands, execute the recorded base-bump recipe with the R10.4 amendment list [264][268].

### R10.1 — The repo and the merge (the owner's links)

- **Canonical public repo: `https://github.com/magiccodingman/vllm-radiance`** (GitHub API record: public, `fork:false` — pushed mirror, not a GitHub-fork object; created 2026-08-22; default branch `main`; `pushed_at` 2026-11-09T19:14:50Z; 163 stars; 5 open issues; `license: null` — **no LICENSE file in the tree**, a provenance note for our ledger, the contents it patches are Apache-2.0/MIT upstreams [253][264]). Same owner/repo name as the Docker Hub image (`magiccodingman/vllm-radiance`); the R5-side guess `radiance-rs/vllm-radiance` stays refuted (404 [150]). The repo description self-describes "Codeberg fork of StillDeadcode / vllm-radiance" — and the libr4d maintainer RETIRED the old `vllm-radiance`/`libr4d` repos in favor of `codeberg.org/StillDeadcode/radiance`, whose commit `451b136…` the 0.33 build now merges in via `tools/prepare_r4d.py`; **magiccodingman's line is the live one that backs the Hub images** [256][266].
- **The merge: `38669dffa756c14e8ffc5f07a50a43783d9d83bb`** — "Merge branch 'codex/vllm-033-rdna4-upgrade' into 'main' / Upgrade to vLLM 0.33, maintained RDNA4 kernels and native LFM3 / See merge request lance-wright/vllm-radiance!49", Lance Wright, **2026-11-09T18:39:01Z**, 300 files. The GitLab-MR commit shape + `sync-gitlab.yml` (GitHub main → fast-forward GitLab main over SSH) + gitlab.com API 404 → development happens on a self-managed GitLab; GitHub is the public mirror + PR/issues surface [254][261].
- **What it moved:** vLLM `0.30.0@ced6857a` → **`0.33.0@4ba787ec9959e566d3b587a796dff07673324da5`** — and `4ba787ec` is EXACTLY the commit the upstream `v0.33.0` annotated tag resolves to (tag object `3a4d82f5…`, tagger khluu, 2026-11-01T09:21:10Z) [255][256][266]. Stack pair: ROCm `7.14.0-full@sha256:439edaa8…` → **`10.0.0-full@sha256:a90cf047…`**; torch 2.12.0 → **2.13.0+rocm10.0** (ROCm/pytorch `0e8e47fd…`, release/2.13); triton 3.7.1 → **3.8.0** (`669b31ac…`); AITER 0.1.20@fc2e5d57 → **0.1.26** (`84077b3c…`); transformers 5.15.0 → 5.16.1; xgrammar 0.2.3 → 0.2.8; flydsl 0.3.1 → 0.4.0; rust 1.95; libr4d **same `e8de4bc1`** commit + maintained-upstream graft; banner `RADIANCE_VERSION=1.2.0-rc1.vllm0.33.0` [256].
- **Then main kept moving TODAY** (R9's read caught only the first): PR **#45 `b190772353`** 18:59:37Z — "Fix native device dispatch, vision padding and draft tail widths" (contributor PRs #25/#27-#29/#38-#40 re-adapted by Lance Wright's committer); PR **#46 `d416a5a1`** 19:00:56Z — "Preserve Qwen tool literals and referenced schema closure"; PR **#47 `eba3ec86`** 19:04:58Z — "**Port DFlash KV materialization and lazy INT2 fallback to vLLM 0.33**", carrying `79c6df027b` (033-installer port of #36), `3d4cc7c985` (KV-weights materialization under 0.33's all-layer quant-method guard + idempotent migration for installed overlays), `2dd48aa434` (lazy INT2-head fallback, #37-adapt), `dbcfbf10ef` ("Exercise complete INT2 and INT4 groups in the packing gate"); PR **#48 `51d865d1`** 19:05:01Z — "Preserve the stock forward and TP reduction at FP8 stream boundaries"; head **`07e4ed5c` 19:13:13Z** ("Install NumPy for GitLab CPU validation") [257].
- **State: merged to `release`, NOT published.** `release` tip `fc9d4a26` = "Merge branch 'main' into 'release' / Bound draft-head startup memory without changing quantization / MR !50", 2026-11-09T19:13:43Z; `VERSION`@release = `1.2.0-rc1.vllm0.33.0` [258]. Publish law verified live: GitLab `workflow.rules` = MR events + `release` branch only (a push to main builds NOTHING); `publish_docker` tags `1.0.<CI_PIPELINE_IID>` + `1.0` + `sha-<first-12>` + `latest`, `--provenance=false`, OCI revision label [260]. Docker Hub NOW (two probes this round): 34 tags, newest four = `latest`/`1.0`/`1.0.397`/`sha-5b99d66c844f` all 2026-10-18T06:35Z = our pin; **nothing of 0.33 is on any registry** (GitHub: 0 tags, 0 releases [259]). The watch trigger is armed: the next `1.0.<n>`+`sha-fc9d4a26…` pair (or a newer release-tip sha) is the publish.

### R10.2 — What the 0.33 line carries, and the assert verdict

- **Patch list main vs our 5b99d66c:** the apply-loop moves 36→37 lines (35→36 `patch_*.py` + `install_radiance_hooks`): **added `patch_lfm3_backport`, `patch_dflash_quant_exclusions`; retired `patch_gdn_shared_build`** (0.33 makes the V2 GDN metadata reuse upstream-owned); everything else — `patch_r4d`, `patch_mtp_mm_mask`, `patch_dflash_fused_kv_fp8`, `patch_verify_head`, `patch_kv_group_size`, the quark/mxfp4 family, the qwen tool/schema pair, the kv-offload trio, `patch_fp8_kv_sidecar`, and `patch_unified_attention_lds` (already at our pin — R9's "new" framing superseded) — is carried forward, re-anchored [256][264][266][275]. Entrypoint seams: all our read variables still read at main (`RADIANCE_WEIGHT_QUANTIZATION` L185-196, `RADIANCE_SPECULATIVE_CONFIG` L200-213, `RADIANCE_COMPILATION_CONFIG` L223-233 with CLI-wins logic, `RADIANCE_FAST_DRAFT` cache-namespace L82-83, the exit-64 gate family); new baked defaults appear in the Dockerfile ENV block (`RADIANCE_DYNAMIC_DRAFT/DRAFT_SCHEDULE/DRAFT_TAU/DRAFT_RERANK/VERIFY_HEAD`, `RADIANCE_KV_GROUP_OPT=1` L387 unchanged, MXFP4 family OFF, new opt-in `RADIANCE_QWEN_AUTO_TOOL_GRAMMAR/INT64_BOUND_COMPAT` in compose L70-71, default 0) [256][267][275]. gfx stance: still **gfx1201-only** (`ARG GFX_ARCH=gfx1201`); upstream 0.33 gained gfx1250 enablement (#58800 [32]) but their image remains one-arch. Compose deltas: `--mamba-cache-mode` line REMOVED (comment: "In vLLM 0.33 … --mamba-cache-mode is ignored"), `AITER_ROOT_DIR`→`AITER_JIT_DIR`, `--kv-cache-dtype=fp8` stays hard-coded, defaults unchanged (MAX_MODEL_LEN 16384, GPU_UTIL 0.85, TP 2, MAX_NUM_SEQS 8, MBT 4096); new seams: KV-offload trio, tunableop, FP8-KV scale sidecar [267].
- **The four "fresh dflash fixes" are draft-WEIGHTS work, not KV** — `patch_dflash_fused_kv_fp8.py`@main still targets `vllm/model_executor/models/qwen3_dflash.py` (L11); `radiance_drafthead.py` L13 "Weights are int2 … per-(row, group-of-128) scale" (the FAST_DRAFT lm_head re-rank); the new `check_draft_head_packing.py` gate prints "INT2/INT4 draft-head bounded packing… PASS (CPU only)"; `patch_dflash_quant_exclusions` backports upstream PR 61010 `c9cf9d5e` for draft-projection quant exclusion; MR !50 bounds draft-head load-time memory. None touches the KV-cache dtype path [265][258].
- **The assert at THEIR pin (v0.33.0@4ba787ec), re-verified tag-exact:** `vllm/v1/attention/ops/triton_unified_attention.py` — `unified_attention` def L828; causal resolution L877-879 (`use_per_seq_causal = isinstance(causal, torch.Tensor)` / `use_causal = bool(causal)…`); INT4 branch L884-888: `assert use_causal and not use_per_seq_causal, "INT4_PER_TOKEN_HEAD only supports causal attention"` — verbatim, same two-clause shape as our pin's L863-866, inside a heavily-refactored file (tensor-descriptor path, R-SWA, Gemma4 clamp, `KVQuantMode` enum) [262]. `int4_per_token_head.py` @0.33: **zero `causal` occurrences** in 1,167 lines — the bespoke kernel still hardcodes causality (same structural statement as [232]) [263].
- **Does their fork patch it? NO.** `.radiance/patches.yaml`@main greps empty for int4/causal targets except the `patch_unified_attention_lds` NAME — whose body targets `aiter/ops/triton/utils/unified_attention_utils.py` (a 64-KiB LDS clamp on the config reader), not the vLLM wrapper; the 37-loop has no int4-KV entry; their int4 lane isn't even exercised — every 0.33 qualification record runs **fp8 KV** ("Quark/W4A8+FP8KV/R4D", "native FP8 DFlash2 K7 smoke") [264][266]. Upstream still has NO issue filed for the assert class (search `INT4_PER_TOKEN_HEAD causal` → total 0, re-run today) [269].
- **Honest verdict: route C does NOT fix our crash.** The exact int4×non-causal assert rides the 0.33 tag unchanged; `is_causal:false` in the drafter config still wins (`_dflash_layer_causal` L62-66 @0.33 [268]), so a base re-pin today would reproduce crash #6 verbatim. What C DOES carry is real modernization: native DFlash2 in stable 0.33 ("no DFlash source backport is applied"), our checkpoint family qualified on 0.33 by the maintainers (their validation used `Qwen3.8-27B-Quark-AWQ-MXFP4-amd/`, 304 W4A8 layers zero fallback, V1 AND V2 profiles, 1,568-token prefix hit), the draft-head packing/materialization fixes, and the FP8-stream/schema fixes merged hours ago — but production-readiness is their own banner: "**bounded GPU0 … qualification passes; not qualified for production**", TP2/capacity/perf "explicitly deferred", and their dflash memory case shows the same refuse-and-print law we live under (80% budget refused 1.29 vs 1.58 GiB at 4K, retry 83%) [266].

### R10.3 — Consuming "what they have already" pre-publication — the three paths priced

- **(a) WAIT for their 0.33 Hub tag — the RECOMMENDED leg.**
  - Steps on OUR surfaces: none until the tag lands; then the EXISTING C01 law executes verbatim (README ledger re-row — digest/size/date/push-time/source-sha/engine identity — Dockerfile `FROM` re-pin, Hub+GitHub probes, suite re-runs, chart image re-pin, owner boot). The base-bump re-verify duty is already written into the ledger; no new machinery.
  - Effort: LOW — one amendment round, values+containers, the D37 print-law arbitrates the boot.
  - Risk: schedule is external — but the trigger moved sharply TODAY: `release` merged at 19:13:43Z and their pipeline is a full source build on a deliberate 2-job/8-GiB runner [260], so a `1.0.<n>`+`sha-fc9d4a26…` pair is days-class (their 1.0.394→1.0.397 spacing was 9 days; today's same-day main+release double-merge reads like publish-prep). A first tag may also carry a NEWER release sha if more lands first.
  - Time-to-boot: theirs to give; ours = one PR + one owner boot after it.
- **(b) BUILD their main ourselves — priced NOT-worth-it against (a).**
  - Reality of the artifact: their Dockerfile is a four-stage full-stack source build — torch 2.13 from ROCm/pytorch source (still `USE_FLASH_ATTENTION=0 USE_MEM_EFF_ATTENTION=0 USE_AOTRITON=0`), triton 3.8, torchvision, aiter 0.1.26, vLLM@4ba787ec, libr4d-hipcc, the MXFP4 HIP ext, the 19 GB ROCm prune — "**No prebuilt component wheels and no checked-in binaries**"; their own CI pins `BUILD_JOBS=2` because the runner has 8 GiB RAM [256][260].
  - No shortcut exists: download.pytorch.org/whl stops at rocm-7.x (the `rocm10.0` torch listing is empty), `repo.radeon.com/…/rocm-rel-10.0/` is 404, PyPI `amd-aiter` is 0.1.7.dev ≠ their 0.1.26@84077b3c pin [272]; and BOTH cheap-overlay Dockerfiles presuppose the already-built base ("this overlay cannot upgrade the old 0.30 foundation"; `assert vllm == 0.33.0`) [273].
  - Steps on OUR surfaces: new `containers/vllm-radiance-base/` (their repo @pinned main-sha cloned INTO our build context — their tree is not ours, so the Dockerfile itself becomes a fetched artifact we record the digest of), a `docker-build.yaml` matrix/paths entry [274], then our thin overlay `FROM` that new digest — the provenance chain grows from 1 hop (Hub digest) to 2 (their sha → our base digest → our overlay digest), and the D35 flash-attn layer lands on an unqualified torch 2.13/triton 3.8 (R10.4 churn row).
  - Effort: HIGH — the multi-hour build meets our 360-min default job cap head-on (no `timeout-minutes` in the workflow [274]); their ccache `--mount=type=cache` gains nothing on ephemeral runners; the 19 GB base pull + prune layers strain runner disk; every CI re-run pays the pull again.
  - Time-to-boot: days, with a real will-it-finish-within-the-cap failure mode. **Only rational use: if (a) stalls past the owner's horizon.**
- **(c) Their CI as a prebuilt artifact we pin — DEAD CHANNEL, confirmed today.**
  - Evidence: the GitHub publish workflow ships `.disabled` (active workflows are CPU PR-checks, the ROCr-idle experiment, and the GitLab sync [261]); no GHCR repo; the GitLab project is not on gitlab.com (API 404 — self-managed, pipelines not publicly readable); the candidate images the doc names (`sha256:0544917…`, `b2c1f2fe…`) were built on their own GPU host and never pushed [266]. The ONLY public channel is (a) — (c) collapses into (a), no separate price.

### R10.4 — Issues to expect with 0.33 itself (the owner's ask): stays / churns / breaks

| Our surface | @v0.33.0 (`4ba787ec`, verified at the tag) | Class |
|---|---|---|
| `--attention-backend TRITON_ATTN` | enum + default wiring alive (`arg_utils.py` L2746); `supported_kv_cache_dtypes` still lists `int4_per_token_head` (L333); `supports_non_causal=True` (L351) | STAYS |
| int4 dtype + the crash | cache literal `cache.py` L62; **assert L884-888 verbatim**; int4 kernel causal-arg-free; drafter `is_causal` override law unchanged (`qwen3_dflash.py` L62-66) | **BREAKS (unchanged)** — C alone never clears crash #6 |
| A′-b1 spec-JSON `"kv_cache_dtype":"auto"` | `SpeculativeConfig.kv_cache_dtype` field + `("kv_cache_dtype","cache_config","cache_dtype")` map at L448/L402; dflash in `DFlashModelTypes` (L69, L679); V2 supports dflash natively (parallel-drafting carve-out, `config/vllm.py` L3069-3076) | STAYS — **A′ survives the C move** |
| A′-b2 `--kv-cache-dtype-skip-layers` | flag L1416, `cache.py` L282 + `skip_page_size_padded` L288 | STAYS |
| `--mamba-cache-mode align` | **IGNORED**: `arg_utils.py` L2304-2305 logs `_MAMBA_CACHE_MODE_DEPRECATION_MESSAGE` (L462) when passed; help text L1441; their compose deleted the line ("hybrid conv/recurrent cache state follows explicit APC") | **BREAKS (values edit)** — drop the pair on a base bump |
| `--mamba-ssm-cache-dtype bfloat16` / LMO / watermark | flags L1428 / L1497 / watermark-forces-V2 `config/vllm.py` L740-746 | STAYS |
| `VLLM_USE_V2_MODEL_RUNNER: "1"` | honored (`envs.py` L2149) but **no longer load-bearing**: 0.33 auto-selects V2 (`config/vllm.py` L748-750 + unsupported-list L3053-3080); their compose keeps an explicit `0` only to preserve their V1-lane defaults; our "1" stays valid | STAYS (posture note) |
| f2 `VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS: "0"` | exists, default `"1"` (`envs.py` L2219-2220) | STAYS |
| **`AITER_ROOT_DIR: /cache/aiter`** | **DEAD**: their own deprecation record — "AITER 0.1.26 uses `AITER_JIT_DIR` … `AITER_ROOT_DIR` is an internal constant, not an effective env override" | **BREAKS** — swap the var; testlib 21-var exact-set re-pin |
| `FLASH_ATTENTION_TRITON_AMD_ENABLE` + D35 layer | package-side var (not vLLM); layer is pure-Python onto torch **2.13/triton 3.8** — never qualified by anyone; inert at LMO serving anyway (D38) | CHURNS (re-smoke) |
| f1 markers / grouped sizing | their `patch_kv_group_size` survives (baked `RADIANCE_KV_GROUP_OPT=1` L387) but is classed "migration / equivalence review required" in their own 0.33 audit; upstream warning/print line-prefixes move (`kv_cache_utils.py:1261/:2235` cited in their doc vs our `:147x` reads); group-size search result MUST be re-read at first 0.33 boot (D37 law: the print is the authority) | CHURNS (runbook T5 re-pin) |
| The grouping PRs the f1 ledger tracks | **none landed in 0.33**: #46462 was an ISSUE, closed 2026-10-22 with no code PR; #56445 OPEN; #58207 and #65490 are OPEN PRs (#65490 filed 11-03, after the 11-01 tag — could not land); the min-bucket selection is intact at the tag (`kv_cache_utils.py` L1093 `return min(limits)`), and the Phase-3 mixed-page machinery survives at moved lines (`interface.py` L793/L826-933 vs 0.30's L650-760 [245]) — the bs/page law the D37 arithmetic rides is the SAME law, just renumbered | STAYS (markers renumber) |
| Quark MXFP4 target ckpt | `QuarkW4A8_MXFP4_FP8` scheme alive (`quark.py` L33/L575-600/L873-911) + their live proof: 304 W4A8 layers, 0 fallback, V1+V2, prefix-hit, tool gates 30/30 + 40/40 | STAYS (qualified!) |
| DFlash2 drafter ckpt | native in stable 0.33; their FP8 DFlash2 K7 smoke pinned fixture revision `f02593d0` = OUR staged drafter revision [213]; the HF card still advertises the pre-native `vllm@PR-52816` recipe [271] | STAYS (card is stale, engine is not) |
| `--limit-mm-*` / mm-processor | moot — LMO shipped (R8b/D38) | n/a |
| `ROCR_VISIBLE_DEVICES` / `HIP_VISIBLE_DEVICES` | AMD runtime selectors, not vLLM vars; the entrypoint's NUMA/visible-device helper still reads them at main — ROCm 7.14→10.0 is the layer underneath, boot-check class | STAYS |
| `HF_HUB_OFFLINE: "1"` | huggingface_hub-side var (transformers 5.16.1); the serve pod still loads two local dirs — unchanged posture | STAYS |
| `VLLM_CACHE_ROOT` / `TORCHINDUCTOR_CACHE_DIR` / `TRITON_CACHE_DIR` | their compose @main keeps the identical `/cache/*` paths — our env-to-mount coupling (C03) carries | STAYS |
| `RADIANCE_WEIGHT_QUANTIZATION: "auto"` | entrypoint main L185-196 — the `auto`→omit-`--quantization` law byte-identical [275] | STAYS |
| `RADIANCE_MXFP4` family (×8: `MXFP4`, `_W4A8`, `_W4A8_MIN_M`, `_DECODE_MAX_M`, `_TN4_MIN_M`, `_WPERM`, `_DECODE_NT` + module readers) | all named in the baked ENV block @main (defaulted off; our pod sets them); the RX5 lane's live proof = their "304 W4A8 layers, zero reported fallback" run [256][266] | STAYS |
| `RADIANCE_FAST_DRAFT: "1"` | entrypoint seam alive (L82-83 cache-namespace law); the int2-head path got TODAY's bounded-packing fixes and remains opt-in [257][265][275] | STAYS |
| `RADIANCE_COMPILATION_CONFIG: '{"cudagraph_mode":"PIECEWISE"}'` | entrypoint merge logic L135-233 unchanged in law (explicit CLI wins); their dflash smoke ran PIECEWISE on 0.33 natively [266][275] | STAYS |
| `HSA_TOOLS_DISABLE_REGISTER: "1"` | ROCm 10 runtime knob (never in either compose — our adoption rides their issues #6/#12, both STILL OPEN on the 0.33 line) → keep, verify at boot | STAYS (boot-check) |
| Known-issues watch (0.33-era, RDNA4) | **#65963 OPEN PR** "Snap the gfx1201 TRITON_ATTN decode split-K threshold to a capture size" — our backend×arch×graph lane, post-tag, not in 4ba787ec; **#65734 OPEN issue** "[ROCm] Dense attention output allocated with torch.empty — CUDA-graph padding rows poison…" (our PIECEWISE lane); #65034 (Quark `exclude` weight-names — their dflash_quant_exclusions backport covers); RFC class #66130 FlyDSL-MXFP4 / #66491 packed-INT4 GEMM (future upside); gfx1201 issues filed since 10-20: 32 total. Fork-local: #5 TP2 RCCL (moot TP1), #7 batch throughput, #13 FP8_STREAM torch.compile (flag OFF for us) | WATCH |
| Their own 0.33 negative evidence | compiler pair is NEW: upstream's short pin `733fca1` unresolved → their torch `0e8e47fd` is "not a claim that upstream qualified"; 2.13 TP2 hang retained as negative evidence; LFM3 batch-greedy non-equivalence (extra model, not ours); dflash 80%-budget planner refusal (retry 83%); "not qualified for production" header | WATCH |

### R10.4b — Record deltas vs R9 (refines, all of them conservative in R9's favor)

- R9 wrote "fork main merged `codex/vllm-033-rdna4-upgrade` TODAY… UNPUBLISHED" and named four fresh dflash-fix commits — this round confirms all of it and adds what happened in the ~2.5 h since: PRs #45-#48 landed, head moved to `07e4ed5c`, and **`release` merged main** (`fc9d4a26`, MR !50) — the publish leg is now armed, not merely queued [257][258].
- R9's "assert survives on main TODAY (L998-1000)" was the *main-branch* read; this round verifies it at the **exact `v0.33.0` tag they pin** — `4ba787ec` L884-888 — the stronger form the brief demanded [262]. Weight-of-evidence note: those four "dflash fixes" are draft-WEIGHTS work (packing/materialization), not KV — calling them "fresh dflash fixes" without that qualifier is superseded [265].
- Correction to my own R10.2 first-draft framing: `patch_unified_attention_lds` is NOT new in 0.33 — it exists in the pin's loop too (read Dockerfile@5b99d66c); the actual loop delta is +`lfm3_backport`, +`dflash_quant_exclusions`, −`gdn_shared_build` [256][264].
- R9.3 priced C as "NOT-VIABLE TODAY, twice… a re-bench, not a fix" — R10 leaves that verdict standing with the tag-exact proof and the consumption mechanics the owner asked for; nothing in R9 is overturned, only pinned harder.

### R10.5 — The C-route package and the decision sequence

- **Cheapest C-variant that actually clears the int4 assert: NONE EXISTS.** At their exact pin the assert is verbatim (L884-888), the int4 kernel is causal-blind, their 37 overlays don't touch it, and the bug class is unfiled upstream — C alone reproduces crash #6 [262-264][268-269]. **The honest C package is C + A′** (or C + A), said plainly. The saving fact: A′'s single spec-JSON key is alive at 0.33 too [268], so nothing A′ costs today is re-spent at the bump.
- **Decision sequence (owner's next rulings):** ① **A′-now** on the 0.31-pinned image (values-only edit + suite re-pins, R9-priced: drafter groups bf16 → est. demand 5.4-5.5 vs the measured 5.73 pool; clears all three int4 defect classes structurally). ② **Watch-armed C** — the C01 ledger duty already covers it; the trigger (next `1.0.<n>`+`sha-…` publish) plausibly lands within days since release merged today; a publish that fails to materialize within the owner's horizon re-prices (b) (build-our-own, HIGH) as a fallback. ③ **On the publish, run the base-bump with the R10.4 amendment list**: drop `--mamba-cache-mode align` (2-line pair-out), swap `AITER_ROOT_DIR`→`AITER_JIT_DIR` (values (7)-slot + testlib exact-set 21-var re-pin), re-pin T5/runbook line-number markers + re-read the grouped print + block-size INFO (D37 law), re-smoke the flash-attn layer import at torch 2.13/triton 3.8 (and consider retiring the D35 layer entirely if upstream #60418-style ViT lanes or their next publish ships flash support — currently they don't: their 0.33 build STILL compiles torch `USE_FLASH_ATTENTION=0` and carries no flash-attn stage [256]), boot-bench the int4+A′ shape at 262144 (expect the same pool law — dtype-independent; δ=0.99 carried). ④ Never (c); (b) only on (a)-staleness.
- **R10-Q1 (the one owner question, with recommendation):** *"Route C audited: the repo is github.com/magiccodingman/vllm-radiance, the vLLM-0.33/RDNA4 upgrade merged to main AND release TODAY (38669dffa → fc9d4a26) but nothing is published yet — and their 0.33 does NOT fix our int4 crash: the assert stands verbatim at their exact v0.33.0 pin and none of their patches touches it. So the cheapest package that boots today is still A′ — one JSON key, which stays valid at 0.33 too. Recommend: ship A′ on 1.0.397 now, let the ledger watch fire when the next `1.0.<n>` tag lands (likely days), and bump then with the two recorded 0.33 edits (`--mamba-cache-mode` now ignored, `AITER_ROOT_DIR`→`AITER_JIT_DIR`) plus marker re-pins — we never build their stack ourselves unless their publish stalls (their CI is not public and no prebuilt wheels exist at their pins — a self-build is a compile-torch-from-source, ~3-6 h class against our 6-h CI cap). Proceed A′ now, C on the watch trigger?"*

### Adjacent (recorded this round, out of scope — no action)

- Their 0.33 line carries a **CPU-KV-offload family** (3 patches + `RADIANCE_KV_OFFLOADING_SIZE`/`_PIN_POLICY`/`_REGISTER_CHUNK_GIB` compose seams + three dedicated docs incl. `ROCM_KV_OFFLOAD_LONG_CONTEXT_BASELINE.md`) — mmap-backed host KV tiering is a future capacity lever for the 262144-on-32GiB ledger (and the OQ3/48GB rider), but it is "not qualified on the new stack" by their own audit and touches nothing currently shipped [266][267].
- `RADIANCE_DYNAMIC_DRAFT`/`DRAFT_SCHEDULE 1:8,2:7,4:6,8:5,16:4`/`DRAFT_TAU`/`DYNAMIC_WIDTH`/`DRAFT_RERANK` baked ON at main [256] — an adaptive-K draft lane that could re-price the −71%-drop-vs-K7 axis on a bench day; research-class for us, recorded only.
- The maintainer's `--provenance=false` build flag means their Hub images carry no SLSA attestations — our digest-pin law remains the only anchor, unchanged [260].
- LFM3 model support rides the merge (their owner's request) — irrelevant to our qwen3_5 serving, one reason their next publish bundles more surface than our crash needs.

### Open questions (logged, no action expected — batch into the plan round if the owner rules C-watch)

- **R10-Q2 (record):** does the future 0.33 lane need an explicit `VLLM_PLUGINS` env (their migration note: "An explicit `VLLM_PLUGINS` allowlist must include radiance", while the entrypoint/compose carry none)? Resolves itself at the first 0.33 boot — the R4D banner lines are the marker [266].
- **R10-Q3 (record):** whether the D35 PyPI flash-attn layer still imports cleanly on torch 2.13/triton 3.8 (R10.4 churn row). Inert at LMO serving; the honest gate is an image-build smoke, not a GPU run [256].

### Implications for the plan (if the owner takes A′-now + C-on-the-watch)

- C01: add the armed-watch note (release merged `fc9d4a26` today; next publish = the trigger — no other edit); on the bump, the ledger re-row carries the `4ba787ec` engine identity and the ROCm-10/torch-2.13/aiter-0.1.26 stack record [255][256].
- C02: pre-record the two 0.33 serve-law edits in the values comments (mamba-cache-mode pair becomes VOID; `AITER_ROOT_DIR` becomes `AITER_JIT_DIR` at the same slot, testlib exact-set re-pin follows) so the bump is a copy-back, not archaeology [266][268][276].
- C05 runbook: marker re-pins (kv_cache_utils/interface line numbers), the grouped-print re-read law already covers the sizing churn; add the two WATCH issues (#65963, #65734) to the bench-day reading list [269][276].

## Sources (R10)

253. GitHub API repo record — `magiccodingman/vllm-radiance`: public, `fork:false`, "Codeberg fork of StillDeadcode / vllm-radiance which is a custom vllm tuned for R9700 GPU's", created 2026-08-22, `pushed_at` 2026-11-09T19:14:50Z, default branch main, 163 stars, 10 forks, open_issues 5, `license: null` — https://api.github.com/repos/magiccodingman/vllm-radiance + https://github.com/magiccodingman/vllm-radiance (root listing has no LICENSE file).
254. Merge commit `38669dffa756c14e8ffc5f07a50a43783d9d83bb` (author/committer Lance Wright, 2026-11-09T18:39:01Z; "Merge branch 'codex/vllm-033-rdna4-upgrade' into 'main' … See merge request lance-wright/vllm-radiance!49"; 300 files incl. Dockerfile +62/-38, VERSION, docs/V033_UPGRADE.md added, `.radiance/patches.yaml` +298/-66, the 20261106/07-v033 benchmark-result trees) — https://github.com/magiccodingman/vllm-radiance/commit/38669dffa756c14e8ffc5f07a50a43783d9d83bb
255. vLLM tag resolution — `refs/tags/v0.33.0` → tag object `3a4d82f569a9f57054ba81633e9b6c73b34b51fe` (tagger khluu, 2026-11-01T09:21:10Z) → commit `4ba787ec9959e566d3b587a796dff07673324da5` — https://api.github.com/repos/vllm-project/vllm/git/ref/tags/v0.33.0 + https://api.github.com/repos/vllm-project/vllm/git/tags/3a4d82f5…
256. Fork `Dockerfile` @ main (`07e4ed5c`) — full read: `ARG ROCM_BASE=rocm/dev-ubuntu-24.04:10.0.0-full@sha256:a90cf047…`, `GFX_ARCH=gfx1201`, `TORCH_COMMIT=0e8e47fd…`/2.13.0, `TRITON_COMMIT=669b31ac…`/3.8.0, `AITER_COMMIT=84077b3c…`/0.1.26, `VLLM_COMMIT=4ba787ec…`/`VLLM_VERSION=0.33.0` ("Stable vLLM 0.33 with native DFlash2; no DFlash source backport is applied"), TRANSFORMERS 5.16.1, XGRAMMAR 0.2.8, FLYDSL 0.4.0, R4D e8de4bc1 + R4D_UPSTREAM 451b136, torch build flags `USE_FLASH_ATTENTION=0 USE_MEM_EFF_ATTENTION=0 USE_AOTRITON=0` (no flash-attn anywhere), 37-line patch loop, baked ENV block (`RADIANCE_KV_GROUP_OPT=1` L387, `RADIANCE_DYNAMIC_DRAFT=1 … RADIANCE_FAST_DRAFT=0` L389-395), `RADIANCE_VERSION=1.2.0-rc1.vllm0.33.0`, 4-stage "No prebuilt component wheels" header, gfx1201 AITER MXFP4 config installs — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/main/Dockerfile. Contrast @ pin `5b99d66c`: `ROCM_BASE=…7.14.0-full@sha256:439edaa8…`, `TORCH_VERSION=2.12.0`, `VLLM_COMMIT=ced6857a…`/0.30.0, 36-line loop — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/5b99d66c844fd0a54e4a7eb93b40a1ece009a53d/Dockerfile
257. Fork commits/branches @ today — main head `07e4ed5c66193daff70c5abaa8f27a2e3da4a0f3` (19:13:13Z); merges PR #45 `b190772353433ff5613b5bdeb79b0b7cf01ae3e6` 18:59:37Z, #46 `d416a5a1…` 19:00:56Z, #47 `eba3ec8635871f3510d2bb05c7e608d0f055c42a` 19:04:58Z ("Port DFlash KV materialization and lazy INT2 fallback to vLLM 0.33"), #48 `51d865d1…` 19:05:01Z; component commits `79c6df027b` (033-installer port of #36), `3d4cc7c985` (KV-weights materialization under 0.33's all-layer quant-method guard), `2dd48aa434` (lazy INT2-head fallback, #37-adapt), `dbcfbf10ef` ("Exercise complete INT2 and INT4 groups in the packing gate"); branch list incl. `release` @ `fc9d4a263df92df2af205473048728ffd58f7fbf` — https://api.github.com/repos/magiccodingman/vllm-radiance/commits?per_page=20 + /branches?per_page=100
258. Release tip record `fc9d4a26` — "Merge branch 'main' into 'release' / Bound draft-head startup memory without changing quantization / See merge request lance-wright/vllm-radiance!50", 2026-11-09T19:13:43Z; `VERSION` @ both main and release = `1.2.0-rc1.vllm0.33.0` — https://api.github.com/repos/magiccodingman/vllm-radiance/commits/fc9d4a26… + https://raw.githubusercontent.com/magiccodingman/vllm-radiance/release/VERSION
259. Docker Hub tags API, TWO live reads this round — `count: 34`; newest four `latest`/`sha-5b99d66c844f`/`1.0`/`1.0.397` all 2026-10-18T06:35Z (= our pin), next tier `1.0.394`/`sha-d1535e95465d` 2026-10-09; **no 0.33 artifact**; GitHub `tags` → `[]` — https://hub.docker.com/v2/repositories/magiccodingman/vllm-radiance/tags/?ordering=last_updated + https://api.github.com/repos/magiccodingman/vllm-radiance/tags
260. `.gitlab-ci.yml` @ main — `workflow.rules`: `merge_request_event` + `CI_COMMIT_BRANCH == "release"`, else `when: never` (main pushes build nothing); `publish_docker`: `VERSION="${VERSION_SERIES}.${CI_PIPELINE_IID}"` (VERSION_SERIES `1.0`), tags `1.0.<n>`/`1.0`/`sha-<12>`/`latest`, `docker buildx build --push --provenance=false`, OCI revision label = `$CI_COMMIT_SHA`, DOCKERHUB creds, `RADIANCE_BUILD_JOBS: "2"` — "Keep compiler parallelism deliberately low for the 8 GiB RAM runner"; "Physical R9700/candidate-image qualification remains explicit in .radiance/tests.yaml" — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/main/.gitlab-ci.yml
261. GitHub Actions state — active workflows: "Radiance PR checks (CPU)", "Experimental ROCr idle backport (CPU build)", "Sync main to GitLab" (`workflow_dispatch` + push-to-main fast-forward over SSH); the tree ships `.github/workflows/publish-docker.yml.disabled` (not in the active list) → no GitHub-side docker publication; GitLab project probe `https://gitlab.com/api/v4/projects/lance-wright%2Fvllm-radiance` → **404** (self-managed instance, pipelines not public) — https://api.github.com/repos/magiccodingman/vllm-radiance/actions/workflows + tree listing [253]
262. vLLM v0.33.0 @ `4ba787ec` — `vllm/v1/attention/ops/triton_unified_attention.py`: `unified_attention` def L828; causal resolution L877-879; INT4 branch L884-888 — `assert use_causal and not use_per_seq_causal, "INT4_PER_TOKEN_HEAD only supports causal attention"` — verbatim vs our pin's L863-866 [231] inside a refactored file (tensor descriptors, R-SWA, `KVQuantMode` enum) — https://raw.githubusercontent.com/vllm-project/vllm/4ba787ec9959e566d3b587a796dff07673324da5/vllm/v1/attention/ops/triton_unified_attention.py
263. Same tag — `vllm/v1/attention/ops/int4_per_token_head.py` — 1,167 lines, `grep -c causal` = **0**: the bespoke int4 kernel still takes no causal parameter (structure unchanged vs [232]) — https://raw.githubusercontent.com/vllm-project/vllm/4ba787ec…/vllm/v1/attention/ops/int4_per_token_head.py
264. Fork @ main — no int4×causal patch anywhere: `.radiance/patches.yaml` grep for `int4|causal|unified_attention|triton_attn` → only the `patch_unified_attention_lds` name (L488), whose body targets `aiter/ops/triton/utils/unified_attention_utils.py` with a "RADIANCE LDS fit" 64-KiB clamp (full 38-line read); patch-loop delta main-vs-pin = `+patch_lfm3_backport`, `+patch_dflash_quant_exclusions`, `−patch_gdn_shared_build`; their own audit classes `patch_kv_group_size` "migration / equivalence review required" — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/main/.radiance/patches.yaml + /patch_unified_attention_lds.py
265. Same branch — the "fresh dflash fixes" are draft-WEIGHTS work: `patch_dflash_fused_kv_fp8.py` target `vllm/model_executor/models/qwen3_dflash.py` (L11, still "KV-weights"/fused-GEMM posture per [250]); `radiance_drafthead.py` L13-14 "Weights are int2 with an asymmetric per-(row, group-of-128) scale…" (the FAST_DRAFT lm_head path, GROUP=128 L71); `benchmarks/bin/check_draft_head_packing.py` — "INT2/INT4 draft-head bounded packing and reuse: PASS (CPU only)"; `patch_dflash_quant_exclusions` = backport of upstream PR 61010 commit `c9cf9d5e…` — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/main/radiance_drafthead.py + /patch_dflash_fused_kv_fp8.py + /benchmarks/bin/check_draft_head_packing.py
266. `docs/V033_UPGRADE.md` @ main — full read (302 lines): status "**bounded GPU0 Quark V1/V2 qualification passes; not qualified for production**"; base `1d2e2484`, target `v0.33.0`→`4ba787ec` ("the GitHub release URL retains an rc3 tag"); validation boundary (no TP2/capacity/perf inferred from TP1); 37 overlays apply, idempotent (source evidence); 19 CPU/image checks; eight native gates; the Quark TP1 serving table (V2 4K + V1 8K, 304 W4A8 layers 0 fallback, 1,568-token prefix hit, tool 30/30, open-object 40/40); "Actual FP8 DFlash smoke" — native DFlash2 K7, PIECEWISE, 4K/2seqs, `FAST_DRAFT=0`, **fixture revision `f02593d0`**, 148 draft/80 accepted tokens; `dflash-memory-failure` — "The initial 80% budget was refused by the native cache planner (1.29 GiB available versus 1.58 GiB required)", retry 83%; deprecations block (mamba-cache-mode ignored; AITER_JIT_DIR; V2 auto-select with their explicit V1 default kept; `VLLM_PLUGINS` allowlist note); compiler-pin discrepancy (`733fca1` unresolved → `0e8e47fd` is "a new candidate pair, not a claim that upstream qualified"); LFM3 batch-equivalence negative evidence; candidate image shas `b2c1f2fe…`/`0544917…` local to their host — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/main/docs/V033_UPGRADE.md (+ serving/lfm3/installed-native results trees at the merge [254])
267. `docker-compose.yml` @ main vs @ `5b99d66c` — main: serve-args L20-41 (`--max-model-len=${MAX_MODEL_LEN:-16384}`, `--gpu-memory-utilization=${GPU_UTIL:-0.85}`, `--kv-cache-dtype=fp8` hard-coded, `${ATTENTION_BACKEND:-R4D}`, TP `${TP:-2}`, capacity-law comments); L43-45 comment "In vLLM 0.33 hybrid conv/recurrent cache state follows this flag; `--mamba-cache-mode` is ignored" and the pin's `${MAMBA_CACHE_MODE:-align}` line GONE; env L194 `VLLM_USE_V2_MODEL_RUNNER:-0` + comment "DFlash2 requires V2 … upstream 0.33 now auto-selects V2 when this override is absent"; `AITER_ROOT_DIR: /cache/aiter` (pin L213) → `AITER_JIT_DIR: /cache/aiter` (main L203); `RADIANCE_QWEN_AUTO_TOOL_GRAMMAR/INT64_BOUND_COMPAT` L70-71 (default 0); new KV-offload/tunableop/FP8-KV-scales seams; `RADIANCE_GDN_SHARED_BUILD` removed; HSA_TOOLS_DISABLE_REGISTER appears in NEITHER compose (our adoption rides issue #6/#12 guidance, not their file) — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/main/docker-compose.yml + …/5b99d66c…/docker-compose.yml
268. vLLM v0.33.0 @ `4ba787ec` — the stays: `vllm/config/cache.py` L62 (`"int4_per_token_head"` literal) + L282 `kv_cache_dtype_skip_layers` + L288 `skip_page_size_padded`; `vllm/v1/attention/backends/triton_attn.py` L326-333 (`supported_kv_cache_dtypes` incl. int4) + L351 (`supports_non_causal`); `vllm/config/speculative.py` L69 `DFlashModelTypes`, L402 rename map `("kv_cache_dtype","cache_config","cache_dtype")`, L448 `kv_cache_dtype: CacheDType | str | None`, L679 method list, L1163 `dflash_config {"causal": False}` precedent; `vllm/model_executor/models/qwen3_dflash.py` L62-66 (`_dflash_layer_causal` — `is_causal` config wins → our drafter stays non-causal at 0.33); `vllm/engine/arg_utils.py` L1114/L2746 (TRITON_ATTN), L1416, L1428, L1441+L2304-2305+L462 (mamba-cache-mode deprecation), L1497 (LMO); `vllm/envs.py` L2149 (V2), L2219-2220 (f2 default "1"); `vllm/config/vllm.py` L740-746 (watermark forces V2), L748-750 (env override), L3053-3080 (V2 unsupported list — dflash/dspark parallel-drafting native, our shape absent); `vllm/model_executor/layers/quantization/quark/quark.py` L33/L575-600/L873-911 (`QuarkW4A8_MXFP4_FP8`) — raw fetches under `https://raw.githubusercontent.com/vllm-project/vllm/4ba787ec…/`
269. GitHub search API, re-run today — `repo:vllm-project/vllm INT4_PER_TOKEN_HEAD causal` → **total_count 0** (assert class still unfiled); `#56445` still open (grouping min-bucket fix NOT in 0.33); `#65963` [Bugfix][ROCm][RDNA4] "Snap the gfx1201 TRITON_ATTN decode split-K threshold to a capture size" — PR, OPEN, created 2026-11-05 (post-tag, our backend×arch); `#65734` "[Bug][ROCm]: Dense attention output allocated with torch.empty — CUDA-graph padding rows poison the…" — issue, OPEN, created 2026-11-04; `repo:vllm-project/vllm gfx1201 created:>2026-10-20` → 32, incl. #66130 (FlyDSL MXFP4 RDNA4 backend RFC), #66491 (packed-INT4 GEMM W4A16/W4A8 RFC), #65034 (Quark `exclude` weight-names — overlaps their PR-61010 backport [265]) — https://api.github.com/search/issues + /repos/vllm-project/vllm/issues/{65963,65734,56445}
270. Fork open issues @ main — #13 "FP8_STREAM / NORMQUANT_FUSION profile: torch.compile ConstraintViolationError on gfx1201", #12 "EngineCore busy loop takes 100% of one CPU core", #7 "Aggregate throughput at 6k context × batch saturates", #6 "fix(rocm): HSA profiler keeps a CPU core busy while Radiance is idle", #5 "TP=2 fails: RCCL collective launch returns HIP illegal state on gfx1201" — none int4-KV related; #6/#12 = the lane our HSA_TOOLS_DISABLE_REGISTER mitigation still rides — https://api.github.com/repos/magiccodingman/vllm-radiance/issues?state=open
271. HF `tcclaviger/Qwen3.8-27B-DFlash2-FP8` raw README — "FP8 block-128 version … from incoai/Qwen3.8-27B-DFlash2"; install recipe still `pip install -U "vllm @ git+…refs/pull/52816/head"` (the pre-native PR pin) — card claim predates 0.33 native DFlash2; the fork's 0.33 smoke runs the same checkpoint natively (fixture revision `f02593d0` = [213]) — https://huggingface.co/tcclaviger/Qwen3.8-27B-DFlash2-FP8/raw/main/README.md
272. Prebuilt-wheel probes (route-(b) pricing) — `https://download.pytorch.org/whl/` index lists ROCm flavor dirs only to rocm-7.x (6.3/6.4/7.0/7.1/7.14/7.2); `…/whl/rocm10.0/torch/` returns a page with NO `torch-2.*cp312…rocm10…whl` entries; `https://repo.radeon.com/rocm/manylinux/rocm-rel-10.0/` → **HTTP 404**; PyPI `amd-aiter` → latest `0.1.7.post2.dev18` (1 release) ≠ their 0.1.26@`84077b3c` pin → the 0.33 stack has NO public prebuilt-wheel route — https://download.pytorch.org/whl/ + https://pypi.org/pypi/amd-aiter/json
273. Fork `Dockerfile.dev` + `Dockerfile.patch` @ main — dev: "Fast iteration on the candidate ROCm 10 / AMD Torch 2.13 / Triton 3.8 stack. **Build Dockerfile first; this overlay cannot upgrade the old 0.30 foundation**"; patch: "does not rebuild torch, Triton, AITER, or vLLM" + `assert m.version("vllm") == "0.33.0"`; both `ARG BASE_IMAGE=vllm-radiance:1.2.0-rc1.vllm0.33.0` ("Supply BASE_IMAGE by digest") — the cheap overlays presuppose the hours-class base, unpublished — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/main/Dockerfile.dev + /Dockerfile.patch
274. OUR CI surface — `.github/workflows/docker-build.yaml`: `runs-on: ubuntu-latest` (L37, L90), build matrix (L94), **no `timeout-minutes` anywhere** → the GitHub-hosted 360-min default job cap applies; ghcr `ownyourio` push — repo file, this worktree.
275. Fork `radiance_entrypoint.sh` @ main — seam map: exit-64 gate block L12-63+, FAST_DRAFT cache-namespace L82-83, cache-path defaults, `RADIANCE_WEIGHT_QUANTIZATION`→`--quantization` L185-196 (auto omits it — our D25 "auto" posture), `RADIANCE_SPECULATIVE_CONFIG` L200-213 (explicit CLI wins), `RADIANCE_COMPILATION_CONFIG` merge logic L135-233 (explicit CLI wins), background bandwidth sweep L303 — https://raw.githubusercontent.com/magiccodingman/vllm-radiance/main/radiance_entrypoint.sh
276. Upstream v0.33.0 @ `4ba787ec` — grouping-law reads: `vllm/v1/core/kv_cache_utils.py` (min-bucket selection intact — the `return min(limits)` search region at L1093; padding-warning INFO lines cited by the fork doc at `:1261`/`:2235`) + `vllm/platforms/interface.py` L793 (Phase-3 call) / L826 (`_align_heterogeneous_kv_block_size`) / L925 ("Setting attention block size to %d tokens so the quantized …" INFO) / L933 (`skip_page_size_padded` assignment) — survives, moved vs the 0.30 L650-760 reads [245]; PR/issue status API re-reads today: **#46462 ISSUE closed 2026-10-22 with no code PR · #56445 OPEN · #58207 PR OPEN (created 2026-09-22, unmerged through the tag) · #65490 PR OPEN (created 2026-11-03 — post-tag, could not land)** → the 0.33 grouping arithmetic is the 0.30 arithmetic; only line numbers move — https://raw.githubusercontent.com/vllm-project/vllm/4ba787ec…/vllm/v1/core/kv_cache_utils.py + …/vllm/platforms/interface.py + https://api.github.com/repos/vllm-project/vllm/issues/46462 (+58207, +65490)

## Reliability notes (R10 self-review)

- High: the repo/merge/publish state and every 0.33-pin claim — each read live TODAY from the exact commits (main `07e4ed5c`, release `fc9d4a26`, vLLM `4ba787ec`; Hub tag-listed twice), assert line-verified at the tag, patch-absence verified at loop + manifest + file level [253-269].
- Medium: the route-(b) time estimate ("3-6 h class / CI-cap risk") is a build-class inference from their runner notes + file structure, not a timed run; the "publish within days" cadence is inference from their 1.0.394→397 spacing, not a promise; a first `1.0.398` could land with a NEWER release sha than `fc9d4a26`.
- Weakest claim: that A′ at a future 0.33 pin behaves exactly as at our pin — the config law is verified (spec-JSON key + skip-layers alive), but the page-alignment/block-size outcome at 0.33 was NOT re-derived (their own audit classes kv-group-size "equivalence review required"); the D37 print-is-the-authority law already absorbs this.
