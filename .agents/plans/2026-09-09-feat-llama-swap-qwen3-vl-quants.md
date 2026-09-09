# Plan: Add Qwen3-VL quant variants to llama-swap

Type: feat | Date: 2026-09-09 | Status: implemented (pending merge)

## Goal

Expand the llama-swap vision-model menu on the gpu cluster per user request
(sourced from Pictaria's vision-provider docs): add Qwen3-VL 2B Instruct,
4B Thinking, 30B-A3B Thinking, and Q8/BF16 variants of the existing 4B
Instruct — preferring Q8 quants, also including Q4_K_M and BF16.

## Skills

- `llama-swap` — config surface, macros, matrix DSL
- `executing-plans`

## MCP Servers

- `gpu-readonly-kubernetes` — verify live ConfigMap/pod accept the config shape

## Verified context

- HuggingFace repos confirmed via HF API (all files exist):
  - `unsloth/Qwen3-VL-2B-Instruct-GGUF` — Q8_0, Q4_K_M, BF16, mmproj-F16.gguf
  - `unsloth/Qwen3-VL-4B-Thinking-GGUF` — Q8_0, Q4_K_M, BF16, mmproj-F16.gguf
  - `unsloth/Qwen3-VL-30B-A3B-Thinking-GGUF` — Q8_0, Q4_K_M, BF16 (split into
    2 shards under `BF16/` subdir), mmproj-F16.gguf
  - `unsloth/Qwen3-VL-4B-Instruct-GGUF` — Q8_0, BF16 (Q4_K_M already wired as
    the existing `qwen3-vl-4b` model)
- BF16-in-subfolder pattern already proven in this config:
  `qwen3.6-35b-a3b-bf16` uses `-hf unsloth/Qwen3.6-35B-A3B-GGUF:BF16` and that
  repo also keeps BF16 in a `BF16/` subfolder.
- Live gpu cluster: ConfigMap `llama-swap-config` already carries the
  `capabilities` + `matrix` config shape with the three existing VL models;
  pod `gpu-llama-swap` Running 1/1 → llama-swap v240 accepts this shape.

## Changes (implemented)

Single file: `charts/llama-swap/values.yaml`

1. **11 new model entries** under `config.models`, following the existing VL
   pattern (`${server-cmd}` + `${threads}` + `-hf <repo>:<quant>` +
   `--mmproj hf://<repo>/mmproj-F16.gguf` + `-c 16384`, `ttl: 0`,
   `capabilities: in [text, image] / out [text]`):
   - `qwen3-vl-2b-q8` / `qwen3-vl-2b-q4` / `qwen3-vl-2b-bf16`
   - `qwen3-vl-4b-instruct-q8` / `qwen3-vl-4b-instruct-bf16`
     (existing `qwen3-vl-4b` stays as the 4B Instruct Q4_K_M)
   - `qwen3-vl-4b-thinking-q8` / `qwen3-vl-4b-thinking-q4` / `qwen3-vl-4b-thinking-bf16`
   - `qwen3-vl-30b-a3b-thinking-q8` / `qwen3-vl-30b-a3b-thinking-q4` /
     `qwen3-vl-30b-a3b-thinking-bf16` — these three also use the `${moe}`
     macro (CPU-offloaded experts), matching the existing `qwen3-vl-30b-a3b`
2. **Matrix**: 11 new vars (`vl2bq8 vl2bq4 vl2bbf vl4bq8 vl4bbf v4tq8 v4tq4
   v4tbf v30tq8 v30tq4 v30tbf`, all ≤8 alphanumeric chars) added to the
   `main` set alternatives (`... | <new>) & homecpu`).

## Validation performed

- `helm dependency build` + `helm lint charts/llama-swap` — pass
- `helm template` renders; ConfigMap config.yaml parsed and cross-checked:
  31 models, all 31 matrix vars resolve to real model IDs, all vars present
  in the `main` set, every new model has `--mmproj`, `-hf`, and image
  capabilities; no duplicate `-hf` targets.
- Live-cluster shape check (above) confirms the deployed llama-swap version
  accepts `capabilities`/`matrix`.

## Notes / risks

- **30B Thinking BF16 is ~61 GB split across 2 shards** in a `BF16/`
  subfolder; relies on the same `-hf repo:BF16` resolution as the existing
  `qwen3.6-35b-a3b-bf16`. If llama.cpp's HF resolver fails on it at runtime,
  drop that one entry (Q8/Q4 remain).
- All new models are in the single GPU alternation group — loading one evicts
  the others (expected llama-swap behavior; `globalTTL: 0` keeps them resident
  until swapped).
- Models download on first use (`-hf`) and cache on the models PVC
  (`LLAMA_CACHE=/models`); first load of each will be slow.
- After merge: ArgoCD syncs `gpu-llama-swap`, reloader restarts the pod on
  ConfigMap change (config is subPath-mounted, so the restart is what picks
  the new config up).
