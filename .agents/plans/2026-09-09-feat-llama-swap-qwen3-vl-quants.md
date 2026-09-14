# Plan: Add Qwen3-VL quant variants to llama-swap

Type: feat | Date: 2026-09-09 | Status: implemented (pending merge to main)

## Goal

Expand the llama-swap vision-model menu on the gpu cluster per user request
(sourced from Pictaria's vision-provider docs): complete Qwen3-VL coverage —
every family (2B Instruct, 4B Instruct, 4B Thinking, 8B Instruct, 30B-A3B
Instruct, 30B-A3B Thinking) in Q8 (preferred), Q4_K_M, and BF16 — with the
quant in every model ID.

## Skills

- `llama-swap` — config surface, macros, matrix DSL
- `executing-plans`

## MCP Servers

- `gpu-readonly-kubernetes` — verify live ConfigMap/pod accept the config shape

## Verified context

- HuggingFace repos confirmed via HF API (all files exist):
  - `unsloth/Qwen3-VL-2B-Instruct-GGUF` — Q8_0, Q4_K_M, BF16, mmproj-F16.gguf
  - `unsloth/Qwen3-VL-4B-Instruct-GGUF` — Q8_0, Q4_K_M, BF16, mmproj-F16.gguf
  - `unsloth/Qwen3-VL-4B-Thinking-GGUF` — Q8_0, Q4_K_M, BF16, mmproj-F16.gguf
  - `unsloth/Qwen3-VL-8B-Instruct-GGUF` — Q8_0, Q4_K_M, BF16, mmproj-F16.gguf
  - `unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF` — Q8_0, Q4_K_M, BF16 (split
    shards under `BF16/` subdir), mmproj-F16.gguf
  - `unsloth/Qwen3-VL-30B-A3B-Thinking-GGUF` — Q8_0, Q4_K_M, BF16 (split
    shards under `BF16/` subdir), mmproj-F16.gguf
- BF16-in-subfolder pattern already proven in this config:
  `qwen3.6-35b-a3b-bf16` uses `-hf unsloth/Qwen3.6-35B-A3B-GGUF:BF16` and that
  repo also keeps BF16 in a `BF16/` subfolder.
- Live gpu cluster: ConfigMap `llama-swap-config` already carries the
  `capabilities` + `matrix` config shape; pod `gpu-llama-swap` Running 1/1 →
  llama-swap v240 accepts this shape.

## Changes (implemented)

### `charts/llama-swap/values.yaml`

1. **Renamed the 3 pre-existing VL models so every ID carries its quant**,
   each with a back-compat `aliases:` entry for the old ID (protects
   runtime-configured consumers such as Pictaria's AI-provider settings):
   - `qwen3-vl-4b` → `qwen3-vl-4b-q4` (alias `qwen3-vl-4b`)
   - `qwen3-vl-8b` → `qwen3-vl-8b-q4` (alias `qwen3-vl-8b`)
   - `qwen3-vl-30b-a3b` → `qwen3-vl-30b-a3b-q4` (alias `qwen3-vl-30b-a3b`)
2. **15 new model entries**, following the existing VL pattern
   (`${server-cmd}` + `${threads}` + `-hf <repo>:<quant>` +
   `--mmproj hf://<repo>/mmproj-F16.gguf` + `-c 16384`, `ttl: 0`,
   `capabilities: in [text, image] / out [text]`); the 30B entries also use
   the `${moe}` macro (CPU-offloaded experts):
   - `qwen3-vl-2b-q8` / `qwen3-vl-2b-q4` / `qwen3-vl-2b-bf16`
   - `qwen3-vl-4b-q8` / `qwen3-vl-4b-bf16`
   - `qwen3-vl-4b-thinking-q8` / `qwen3-vl-4b-thinking-q4` / `qwen3-vl-4b-thinking-bf16`
   - `qwen3-vl-8b-q8` / `qwen3-vl-8b-bf16`
   - `qwen3-vl-30b-a3b-q8` / `qwen3-vl-30b-a3b-bf16`
   - `qwen3-vl-30b-a3b-thinking-q8` / `qwen3-vl-30b-a3b-thinking-q4` /
     `qwen3-vl-30b-a3b-thinking-bf16`
3. **Matrix**: vars renamed to match (`vl4b→vl4bq4`, `vl8b→vl8bq4`,
   `vl30b→vl30bq4`) plus 15 new vars; all 35 vars resolve and appear in the
   `main` set alternatives (`... & homecpu`).

### `charts/immich-analyze/values.yaml`

- `config.modelName`: `qwen3-vl-4b` → `qwen3-vl-4b-q4` (only in-repo
  consumer of the old ID; the alias also keeps the old ID working).

## Validation performed

- `helm lint` + `helm template` pass for both charts.
- Rendered llama-swap config cross-checked: 35 models; all 6 VL families
  complete across {q8, q4, bf16}; no VL ID without a quant suffix; all 35
  matrix vars resolve to real IDs, valid names, present in the `main` set;
  aliases unique and non-colliding; every VL model has `--mmproj` + image
  capabilities.
- immich-analyze renders `IMMICH_ANALYZE_MODEL_NAME=qwen3-vl-4b-q4`, zero
  sentinels with test values.
- Live-cluster shape check confirms the deployed llama-swap version accepts
  `capabilities`/`matrix`/`aliases`.

## Post-deploy fixes (same day)

1. **healthCheckTimeout 500 → 3600** — first loads died with "health check
   timed out after 8m20s" mid-download of the 32 GB Q8 file. Landed on main
   as `480bb21d`.
2. **Pod restart required to pick up ConfigMap changes** — the gpu cluster has
   **no reloader deployment**, so `reloader.stakater.com/auto` does nothing
   there; the llama-swap pod had to be deleted manually after the timeout fix
   synced. (Follow-up: deploy reloader on gpu.)
3. **Removed `--mmproj hf://...` from all 18 VL model cmds** — the deployed
   llama.cpp (b10015) treats the `--mmproj` value as a literal path
   (`params.mmproj.path = value` in common/arg.cpp), so it died with
   `failed to open GGUF file 'hf://...' (No such file or directory)` right
   after the model download finished. b10015's `-hf` download planner
   auto-picks the mmproj sibling from the same repo
   (`find_best_mmproj` in common/download.cpp; arg help: "if -hf is used,
   this argument can be omitted"), so dropping the flag is the fix. Each cmd
   carries a comment noting this.
4. **Added `${flash-and-q8}` to the 6 vision MoE models** (30B-A3B instruct
   q4/q8/bf16 + thinking q4/q8/bf16), matching the text-MoE pattern
   (`${moe}` + `${flash-and-q8}`). Kept `-c 16384` (not `${ctx-256k}`) —
   vision requests are small and a 256k KV allocation would waste VRAM.

   Safety evidence for FA on multimodal in the deployed build (b10015):
   - `tools/mtmd/mtmd.cpp` explicitly maps the server's `flash_attn_type`
     into the clip/vision context (`mtmd_get_clip_flash_attn_type`) — FA is
     wired through to the vision tower by design.
   - `tools/mtmd/clip.cpp` implements it via `ggml_flash_attn_ext` and
     degrades gracefully when unsupported: AUTO falls back to disabled with a
     warning; forced-ON logs "falling back to CPU". Either way it loads, and
     warmup logs "flash attention is enabled/disabled" for verification.
   - Vulkan FA + q8_0 KV is already proven in this deployment by the text MoE
     models running with the same macro on the same build.

   Expected effect: faster vision-tower + prompt prefill, KV cache halved
   (q8_0 vs f16 at 16k ctx for 30B-A3B: ~1.6 GB → ~0.8 GB). Does NOT change
   the dominant cost — CPU-expert decode speed — so 30B still won't fit
   Pictaria's hardcoded 300 s client timeout on this hardware.
5. **Tuned MoE expert placement for the 8GB gpu card** (user confirmed VRAM):
   replaced the blanket all-experts-on-CPU `${moe}` with per-quant
   `--n-cpu-moe N` macros on the Q4/Q8 vision MoE models, plus `${big-ub}`
   (-b 2048 -ub 2048; b10015's default ubatch is only 512).

   Research basis:
   - b10015 ships `--n-cpu-moe N` (keeps experts of N layers on CPU) and
     `-fit` auto-fit (default on); the canonical `--cpu-moe` equals our old
     `-ot "\.ffn_.*_exps\.=CPU"` (common/common.h `llm_ffn_exps_cpu_override`).
   - Doctor-Shotgun's MoE-offload guide (HF, 2026-01) ranks the levers:
     FA (done) > bigger ubatch (done) > KV q8 (done) > expert placement.
   - "The 8 GB Vanguard" archive + Poor GPU Club measurements:
     Qwen3-30B-A3B Q4 on 8GB cards runs at 20–34 t/s with ncmoe ~28–34
     (most experts ON GPU); all-experts-on-CPU is the slow floor of the
     curve. The archive's model-fit ladder names Qwen3-VL-30B-A3B
     explicitly at "ncmoe ~28–34" for 8GB.

   Applied values (conservative starts, NOT yet swept on hardware):
   - `moe-vl-q4`: `-ngl 99 --n-cpu-moe 38 --no-mmap` (10 expert layers on GPU)
   - `moe-vl-q8`: `-ngl 99 --n-cpu-moe 44 --no-mmap` (4 expert layers on GPU)
   - BF16 variants keep `${moe}` — no expert headroom on 8GB.
   - Text MoE models untouched (scope: vision MoE per user request).

   Follow-up: sweep N downward per quant (more experts on GPU) while
   load-time VRAM allows — the archive calls this "the single highest-value
   hour in the playbook"; each step needs a model load to verify (evicts the
   running model). Too-low N fails loudly at load (Vulkan OOM), not silently.

## Notes / risks

- **30B BF16 variants (instruct + thinking) are ~61 GB, split across 2
  shards** in a `BF16/` subfolder; relies on the same `-hf repo:BF16`
  resolution as the existing `qwen3.6-35b-a3b-bf16`. If llama.cpp's HF
  resolver fails on them at runtime, drop those two entries (Q8/Q4 remain).
- All VL models are in the single GPU alternation group — loading one evicts
  the others (expected llama-swap behavior; `globalTTL: 0` keeps them resident
  until swapped).
- Models download on first use (`-hf`) and cache on the models PVC
  (`LLAMA_CACHE=/models`); first load of each will be slow.
- After merge: ArgoCD syncs `gpu-llama-swap`, reloader restarts the pod on
  ConfigMap change (config is subPath-mounted, so the restart is what picks
  the new config up).
