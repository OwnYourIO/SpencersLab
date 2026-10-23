# Perspective: HuggingFace GGUF curator

All verified 2026-10-22 via live HF API (`/api/models/<id>`, `/tree/main?recursive=true`,
`?search=`). Sizes summed from shards (incl. the tiny 0.01–0.65 GiB index shards).

## A. "qwen3.8 flash-next" — EXISTS, exact-name match
- Official base: `Qwen/Qwen3.8-Flash-Next` — arch `Qwen4ExpForConditionalGeneration`,
  `model_type qwen4_exp` (`qwen4_exp_text`), 48 layers, hidden 2560,
  **512 experts, top-10 routed, shared expert**, BF16 params 180B total
  (=> an 180B-class sparse MoE; active params not stated in the config fields
  fetched — community forks brand it "125B-A5B" (`azampatti/...-125B-A5B-...`);
  treat active size as unverified).
- Vision: mmproj files published by every GGUF provider ⇒ multimodal.
- MTP/speculative sidecars exist in-repo: unsloth `MTP/mtp-...Q8_0.gguf` (3.85 GiB)
  and `mtp-Qwen3.8-Flash-Next-Q8_0.gguf` at root; ggml-org `mtp-...Q4_0/Q8_0/BF16`
  + `dflash-...` files. Same pattern as the lab's Qwen3.8-27B `-hfd` MTP draft usage.
- GGUF providers (public unless noted):
  - `unsloth/Qwen3.8-Flash-Next-GGUF` (1.05M dl, ungated) — UD dynamic + classic:
    UD-IQ1_S 67.6 / UD-IQ1_M 69.4 / UD-IQ3_XXS 76.3 / UD-IQ4_XS 87.3 /
    UD-Q2_K_XL 73.5 / **UD-Q3_K_XL 83.8** / **UD-Q4_K_XL 103.7** /
    **UD-Q5_K_XL 147.4** / **UD-Q6_K_XL 157.5** / Q8_0 175.3 / BF16 329.7
    (GiB totals; q3–q6 sharded inside `UD-Qx_K_XL/` subdirs). mmproj-BF16 0.85.
  - `bartowski/Qwen3.8-Flash-Next-GGUF` (73.6k dl, ungated) — full K/IQ ladder:
    Q3_K_S 83.3, Q3_K_M 85.6, Q3_K_L 86.8, Q4_K_S 105.4, Q4_K_M 111.4,
    Q4_K_L 129.7, Q5_K_S 119.3, Q5_K_M 125.4, Q5_K_L 140.7, Q6_K 156.6,
    Q8_0 175.3, IQ3_XXS 82.0, IQ4_XS 91.0, IQ4_NL 93.4, Q4_0 93.7, Q4_1 103.6,
    Q2_K 75.4, bf16 329.7, plus `imatrix` file (0.54) and mtp-Q4_0/Q8_0/bf16 +
    mmproj bf16/f16. (Q3_K*/Q4_K_M/Q5_K_M/Q6_K sums recomputed from raw shard
    lines; the rest are per-directory group sums from the same listing.)
  - `ggml-org/Qwen3.8-Flash-Next-GGUF` (48k dl, ungated) — reference builds:
    Q2_K 77.4, IQ4_NL 95.0, Q8_0 151.5 (sharded pairs) + mtp-/dflash-/mmproj-Q8_0.
    (Q8_0 sum here 151.5 vs unsloth 175.3 — ggml-org appears to exclude/ship
    different modules; report as observed, not reconciled. UNRESOLVED discrepancy.)
  - `orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF` (887k dl) — **gated: "auto"**
    (needs HF account approval/token; lab already consumes orcarouter on gpu-ai).
  - Many abliteration/derivative GGUFs exist (huihui-ai, ISTA-DASLab GSQ-RCO,
    ukisai Swift, DavidAU, agentionai Gyro, AtomicChat, dealignai NVFP4...).
- q3/q4/q5/q6 best-match (user's ask): unsloth UD-Q{3,4,5,6}_K_XL — the lab's
  exact existing convention for Qwen3.8-27B (`:UD-Q4_K_XL` etc., proven working).
- **Feasibility**: even Q3_K_XL (83.8 GiB weights) exceeds the 8-GiB-VRAM/64-GiB-RAM
  `gpu` box. On `ai-gpu` (~128 GiB RAM measured 2026-10-22 via kubelet stats;
  "125 GiB node budget" per repo comments): routed experts are ≈ 512×3×2560×640×48
  ≈ 121B of the 180B params (~67% by my config-derived estimate — the remaining
  ~59B of non-expert weight mass is not accounted for by the config fields
  fetched, so expert-offload cannot be assumed to relieve everything: UNVERIFIED
  regime). q3/q4 could *maybe* solo-offload like today's 80B-A3B entries; q5/q6
  (125–157 GiB) exceed node RAM outright. The planner must treat flash-next fit
  as measure-first, and q5/q6 as infeasible on this cluster as published.

## B. "Ornith 1.5 122B" — EXISTS
- Official `ornith-ai/Ornith-1.5-122B` arch `Qwen3_5MoeForConditionalGeneration`
  (`qwen3_5_moe`), 48L, hidden 3072, **256 experts, top-8**, 125.09B BF16 params.
  So "Ornith 1.5" is a Qwen3.5-MoE-derivative family (also 9B dense, 35B-A3B MoE,
  397B in the family).
- Official GGUF `ornith-ai/Ornith-1.5-122B-GGUF` (ungated, updated 2026-10-21):
  single-file **Q4_K_M 70.64 / Q5_K_M 82.62 / Q6_K 95.35 / Q8_0 123.45 /
  BF16 232.24**, + `mmproj-Ornith-1.5-122B-BF16.gguf` 0.85 (vision).
  **NO Q3 in the official repo.**
- `unsloth/Ornith-1.5-122B-GGUF` (ungated): UD-Q2_K_XL 41.5, UD-IQ3_XXS 46.1,
  root files UD-IQ1_M 37.6 / UD-IQ2_XXS 39.1; sharded **UD-Q3_K_XL 55.7 /
  UD-Q4_K_XL 74.2 / UD-Q5_K_XL 88.1 / UD-Q6_K_XL 106.4**, Q8_0 123.5, BF16 231,
  mmproj-BF16/F16. (No plain Q5_K_M/Q6_K — UD-XL only.)
- `bartowski/Ornith-1.5-122B-GGUF` (ungated): full ladder incl. Q3_K_S 53.5 /
  Q3_K_M 56.5 / Q3_K_L 59.8, Q4_K_M 73.5, Q5_K_M 88.4, Q6_K 101.8, Q6_K_S 97.2,
  Q8_0 123.5, bf16 232.3, IQ1–IQ4 variants, imatrix (beware: autogen chokes on
  `*imatrix.gguf` names — no quant token), mmproj bf16/f16.
- Derivatives: `prithivMLmods/Ornith-1.5-122B-MTP-GGUF` (MTP heads, single-file
  Q3_K_L 60.22/Q4_K_M 70.64/Q5_K_M 82.62 + bf16 shards), dealignai UNCENSORED,
  AtomicChat, FP8/NVFP4 (non-GGUF), EXL3, DFlash2.
- q3–q6 recommendation basis (sizes): q3 → unsloth UD-Q3_K_XL 55.7 or
  bartowski Q3_K_M 56.5; q4 → official Q4_K_M 70.6 (single file, simplest) or
  unsloth UD-Q4_K_XL 74.2; q5 → official Q5_K_M 82.6 / unsloth UD-Q5_K_XL 88.1;
  q6 → official Q6_K 95.4 / unsloth UD-Q6_K_XL 106.4 / bartowski Q6_K_S 97.2.
- **Feasibility**: experts dominate (~2.4B params/layer × 48 ≈ 115B of 125B are
  routed experts): on ai-gpu, q4 (70.6) and q5 (82.6) are RAM-plausible SOLO
  (~75–90 GiB with system+KV); q6 (95.4) is marginal (~105+ GiB); q8 (123.45)
  and BF16 impossible; `gpu` box (64 GiB RAM): impossible at all K-quants —
  smallest useful (UD-IQ3_XXS 46.1) still busts 64 GiB with KV/system.

## C. "Ornith 1.5 35B" — EXISTS as `Ornith-1.5-35B-A3B` (MoE, 3B active)
- Official `ornith-ai/Ornith-1.5-35B-A3B-GGUF` (ungated, 3.85M dl):
  **Q4_K_M 20.22 / Q5_K_M 23.61 / Q6_K 27.20 / Q8_0 35.21 / BF16 66.19**,
  + mmproj-BF16 0.84 (vision). Single files, all `-hf`-friendly.
- `bartowski/Ornith-1.5-35B-A3B-GGUF` (44.8k dl, ungated) — the broad menu the
  user asked to enumerate (all single-file except bf16 subdir):
  IQ2_XXS 9.55, IQ2_XS 10.50, IQ2_S 10.70, IQ2_M 11.68, Q2_K 12.19, Q2_K_L 12.65,
  Q3_K_S 14.89, Q3_K_XL 16.58, Q3_K_M 15.55, Q3_K_L 16.16, IQ3_XXS 14.29,
  IQ3_XS 15.54, IQ3_M 16.18, Q4_K_S 19.62, IQ4_XS 17.95, IQ4_NL 18.94,
  Q4_0 19.01, Q4_K_M 20.36, Q4_K_L 20.71, Q4_1 20.91, Q5_K_S 22.94, Q5_K_M 23.74,
  Q5_K_L 24.03, Q6_K 28.43, Q6_K_L 28.66, Q8_0 35.22, bf16 66.18 (2 shards),
  + imatrix 0.18 + mmproj bf16/f16 0.84.
- No unsloth GGUF repo for 35B (searched `search=Ornith-1.5-35B filter=gguf`);
  `peculiar-ragdoll/Unsloth-Ornith-1.5-35B-A3B` is a copy, not unsloth-org.
- MTP-preserving variants: `mudler/Ornith-1.5-35B-A3B-APEX-MTP-GGUF` (449k dl),
  `mudler/...-APEX-GGUF` (309k), `SC117/...-Heretic-MTP-APEX-GGUF`,
  `EryriLabs/...BigBang-MTP...`, `gbuzhf/...MTPv2-ICE...` — if MTP spec-decode
  matters (as on the q38/q36 roster), mudler APEX-MTP is the adopted channel.
- Abliterations: `dealignai/...-UNCENSORED-GGUF` (47.5k), `0xKitkat/...Uncensored`,
  `huihui-ai/Huihui-...abliterated` (no GGUF), `mradermacher/...` mirrors.
- "All sensible quants" short-list for the plan: official Q4_K_M/Q5_K_M/Q6_K/
  Q8_0/BF16 + bartowski IQ3_XXS/Q3_K_XL/Q4_K_L/Q5_K_L/Q6_K_L (+ IQ2 tier if the
  gpu box is ever wanted — see sizes vs 8 GiB VRAM + 64 GiB RAM: the 35B-A3B
  family fits the trio regime like qwen3.6-35b-a3b already does).
- `35B-A3B` naming: llama.cpp `-hf` tag must be the FILE token (`Q4_K_M` etc.);
  repo id is `...-35B-A3B-GGUF` but filenames say `35B` (official) /
  `35B-A3B` (bartowski) — matters for autogen-style name-derived IDs and for
  `-hf ornith-ai/Ornith-1.5-35B-A3B-GGUF:Q4_K_M` (tag regex matches
  `-Q4_K_M.gguf` ✓).

## Gated / auth summary
- Ungated: unsloth, bartowski, ggml-org, atomicchat, prithivMLmods, dealignai,
  mudler, SC117, ornith-ai (all checked `gated: false`).
- Gated: `orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF` — `gated: "auto"`
  (login+approval; gpu-ai has HF_TOKEN, `gpu` box does NOT — see chart values
  note "clusters without bitwardenIds.hf-token (gpu) have no hf-token secret").
