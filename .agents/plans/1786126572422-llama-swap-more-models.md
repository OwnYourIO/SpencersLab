# Plan: Add models to llama-swap chart + migrate routing to matrix

## Scope

Single file change: `charts/llama-swap/values.yaml` (the `config:` block). The ConfigMap
template (`templates/configmap-llama-swap.yaml`) blindly renders `.Values.config` to YAML,
so no template changes are needed. No ApplicationSet/proxy/service changes — the chart is
already deployed via the GPU service ApplicationSet.

**Dropped from the original request** (user confirmed): `OHF-Voice/piper1-gpl` and
`Kokoro-82M`. Neither is servable by `llama-server` (Piper is a Python TTS package, not a
GGUF model; the Kokoro GGUF needs the Kokoro ggml runtime). Out of scope.

## New models (all GGUF, downloaded via `-hf` at runtime, cached on the `models` PVC)

### GPU-exclusive set (one at a time)

| Model ID | `-hf` ref (verified on HF) | Notes |
|---|---|---|
| `qwen3-30b-a3b-q4` | `unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF:Q4_K_M` | MoE → use `${moe}` macro (experts on CPU; ~18GB Q4 won't fit 8GB card otherwise) |
| `qwen3-30b-a3b-q8` | `unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF:Q8_0` | MoE → `${moe}` |
| `qwen3-8b-q4` | `unsloth/Qwen3-8B-GGUF:Q4_K_M` | dense; `${ctx-256k}` + `${flash-and-q8}` |
| `qwen3-8b-q8` | `unsloth/Qwen3-8B-GGUF:Q8_0` | dense; same flags |
| `home-3b-v3-gpu` | `acon96/Home-3B-v3-GGUF:Q8_0` | `-ngl 99` (GPU) |
| `kat-coder-q4` | `bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF:Q4_K_M` | MoE (qwen3_5_moe) → `${moe}` |
| `kat-coder-q6` | `bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF:Q6_K` | MoE → `${moe}` |
| `kat-coder-q8` | `bartowski/Kwaipilot_KAT-Coder-V2.5-Dev-GGUF:Q8_0` | MoE → `${moe}` |

### CPU, lazy-loaded, parallel with GPU models

| Model ID | `-hf` ref | Notes |
|---|---|---|
| `home-3b-v3` | `acon96/Home-3B-v3-GGUF:Q4_K_M` (~1.7GB) | `-ngl 0` forces CPU; small ctx (`-c 8192` is plenty for Home-3B) |

Every new model entry follows the existing shape: `cmd` (`${server-cmd}` + `${threads}` +
`-hf …` + flags), `name`, `description`, `proxy: http://localhost:${PORT}`, `ttl: 0`.

## Routing: migrate `groups` → `matrix` (user confirmed)

Remove the entire `config.routing` block (`router.use: group` … `scheduler.use: fifo`)
and replace with a top-level `config.matrix`:

```yaml
matrix:
  vars:
    q27bq6:  qwen3.6-27b-q6
    q27bq8:  qwen3.6-27b-q8
    coderq6: qwen3-coder-next-q6
    coderq8: qwen3-coder-next-q8
    q35q6:   qwen3.6-35b-a3b-q6
    q35q8:   qwen3.6-35b-a3b-q8
    q35bf16: qwen3.6-35b-a3b-bf16
    q35b1m:  qwen3.6-35b-a3b-1m
    q30q4:   qwen3-30b-a3b-q4
    q30q8:   qwen3-30b-a3b-q8
    q8bq4:   qwen3-8b-q4
    q8bq8:   qwen3-8b-q8
    katq4:   kat-coder-q4
    katq6:   kat-coder-q6
    katq8:   kat-coder-q8
    homegpu: home-3b-v3-gpu
    homecpu: home-3b-v3
  sets:
    main: "(q27bq6 | q27bq8 | coderq6 | coderq8 | q35q6 | q35q8 | q35bf16 | q35b1m | q30q4 | q30q8 | q8bq4 | q8bq8 | katq4 | katq6 | katq8 | homegpu) & homecpu"
```

Var names are constrained by the matrix DSL to alphanumeric, 1–8 chars, so the full
model IDs can't be used in set expressions directly — the names above are the most
descriptive form that fits (family + quant/variant, e.g. `coderq6`, `q35bf16`,
`homegpu`/`homecpu`).

Semantics of the set expression: a set `[x, homecpu]` means any subset is valid, so
- any **one** GPU model runs at a time (`|` alternatives),
- `homecpu` (CPU) may run alone or **alongside** whichever GPU model is loaded,
- requesting a different GPU model evicts only the GPU model, not `homecpu`.

`matrix` and `groups` may not coexist — deleting `routing.groups` is mandatory, not
optional.

## Task list (implementation order)

1. Edit `charts/llama-swap/values.yaml`:
   a. Add the 9 new model entries under `config.models` (keep the 8 existing entries
      unchanged).
   b. Replace `config.routing` with the `config.matrix` block above.
2. Validate rendering:
   - `helm lint charts/llama-swap`
   - `helm template charts/llama-swap --set domain=test.example.com` and confirm the
     rendered `llama-swap-config` ConfigMap contains valid llama-swap YAML (all model
     IDs in `matrix.vars` exist under `models:`; no `groups:` key remains).
   - Optional: extract the rendered `config.yaml` and validate against
     `https://raw.githubusercontent.com/mostlygeek/llama-swap/refs/heads/main/config-schema.json`.
3. Report the runtime risks below to the user (nothing more to commit — ArgoCD syncs).

## Risks / things to verify at runtime (post-deploy, not blockers for the edit)

1. **Matrix support in the pinned image** (`ghcr.io/mostlygeek/llama-swap:v240-vulkan-b10015`).
   Matrix is a newer feature than groups. If the container fails config load with a
   matrix-related error, bump the image tag to the latest llama-swap release.
2. **KAT-Coder arch (`qwen3_5_moe`)** must be supported by llama-server build b10015.
   It is a very recent (July 2026) architecture; if b10015 predates support, the model
   will fail to load and the image tag must be bumped.
3. **`acon96/Home-3B-v3-GGUF` quirks**: filenames use lowercase suffixes
   (`Home-3B-v3.q4_k_m.gguf`), so if `-hf repo:QUANT` matching fails, switch to explicit
   `-hfr acon96/Home-3B-v3-GGUF -hff Home-3B-v3.q4_k_m.gguf`. Also `stablelm_epoch` is an
   old architecture — confirm llama-server b10015 still loads it; the model also ships
   without a chat template (Home-Assistant clients usually provide one — acceptable for
   the intended HA use).
4. **VRAM fit**: all MoE models (30B-A3B Q4/Q8, KAT Q4/Q6/Q8, 35B-A3B variants) rely on
   `${moe}` expert-CPU-offload to fit the 8GB card; expect reduced tokens/sec, especially
   at Q8.
5. `home-3b-v3` on CPU uses the pod's CPU/memory requests (currently 1000m/4Gi) —
   fine for a 1.7GB Q4 model, but watch memory if several CPU-resident models are added
   later.
