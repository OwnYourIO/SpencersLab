# Debug: gpu-moe endpoint errors with qwen3.6-35b-a3b-q8 (debug)

- **Date:** 2026-10-11
- **Status:** Root cause identified; fix implemented (option B, gpu-only
  override) — pending merge + live load test
- **Skills loaded:** llama-swap, systematic-debugging
- **MCP used (readonly):** readonly-gpu-kubernetes, readonly-ai-gpu-kubernetes,
  readonly-global-grafana (Loki); plus in-cluster HTTP to
  `gpu-llama-swap.default.svc.cluster.local:8080` (read-only GETs) and
  `https://llama.gpu-ai.spencerslab.com/api/hardware`

## Symptom

Requests for model `qwen3.6-35b-a3b-q8` via the gpu-moe endpoint
(`llama-moe.spencerslab.com` → proxy-local → gpu cluster → `gpu-llama-swap`)
fail. Client retries every ~13 s.

## Evidence trail

1. Loki (`{cluster="gpu", app_kubernetes_io_name="llama-swap"}`), 2026-10-11
   16:36:52–16:47:53 UTC, 22 occurrences:
   - `[WARN] matrix: starting qwen3.6-35b-a3b-q8 failed: upstream command exited prematurely`
   - `[WARN] error processing streaming response: no valid JSON data found in stream, path=/v1/chat/completions`
2. llama-swap buffered model log (`GET /logs/stream/qwen3.6-35b-a3b-q8`,
   text/plain — note: `/logs` redirects HTML clients to the UI; upstream model
   output is NOT in pod stdout because `logToStdout: "proxy,http"`, so it never
   reaches Loki — fetched it via the per-model stream endpoint instead):
   ```
   load_model: loading model 'unsloth/Qwen3.6-35B-A3B-GGUF:Q8_0'
   W common_fit_params: failed to fit params to free device memory: n_gpu_layers already set by user to 99, abort
   radv/amdgpu: Not enough memory for command submission.
   E ggml_vulkan: device lost on Vulkan0
   E llama_model_load: error loading model: vk::Queue::submit: ErrorDeviceLost
   E llama_server: exiting due to model loading error
   ```
   Identical on every attempt; llama-server dies ~3–7 s after start.
3. Hardware (`GET /api/hardware`): gpu cluster = QEMU/KVM VM, Ryzen 9 7940HS,
   Radeon 780M (gfx1102), **8 GiB VRAM**, 64 GiB RAM.
4. This model has **never** loaded on the gpu cluster (7-day Loki: zero
   `Health check passed` for it; first-ever request was 16:36:30 today).
5. The same model ID works on **gpu-ai** (Framework A6, Ryzen AI MAX+ 395 /
   Radeon 8060S, 128 GiB unified): health checks passed 2026-10-10 03:02 and
   21:09 UTC. At 16:36:30 today gpu-ai evicted it to load `qwen3.8-27b-q8` —
   same second the user's request landed on the gpu cluster.
6. Node `gpu` startTime 2026-10-11T16:42:43Z — the VM rebooted mid-failure-storm
   (old llama-swap pods left in Unknown/ContainerStatusUnknown). Failures
   resumed on the new pod until the client stopped retrying at 16:47:53.
   Unclear whether the reboot was operator-initiated or caused by the repeated
   Vulkan device-lost cascade — **question open with operator**.
7. Current state (22:35 UTC): healthy. `/running` = [], no failures in last
   several hours, no warning events, GPU driver detected normally.

## Root cause

`qwen3.6-35b-a3b-q8` cannot fit the gpu cluster's 8 GiB VRAM, ever:

- The `${moe}` macro (`-ngl 99 -ot "\.ffn_.*_exps\.=CPU" --load-mode none`)
  offloads only the expert FFN tensors to CPU. The remaining non-expert
  weights (~4–6B params at Q8_0 ≈ 4.5–6.5 GiB) go to GPU.
- `${ctx-256k}` allocates a 262144-token KV cache with
  `--cache-type-k/v q8_0` (~10+ GiB for this architecture) on GPU.
- llama.cpp's auto-fit cannot save it: `common_fit_params` aborts because
  `n_gpu_layers` is explicitly pinned to 99.
- radv then fails the over-budget allocation ("Not enough memory for command
  submission") and the Vulkan device is lost, killing the process. Each client
  retry repeats the device-lost cycle; seven minutes of this preceded the node
  reboot.

The entry was added 2026-07-15 (commit 3250ffb8d "Fix up llama models") in the
shared chart roster; gpu-ai can serve it, the 8 GiB gpu box never could. The
sibling entries `qwen3.6-35b-a3b-q6` (no `${moe}` at all), `-bf16`, and `-1m`
are equally unloadable on gpu.

### Architecture note (why 256k is achievable at all)

Qwen3.6-35B-A3B is a Qwen3-Next-style hybrid (GGUF arch `qwen35moe`, parsed
from the file header: 733 tensors, 54 metadata kvs): 40 layers =
10 × (3× Gated DeltaNet + 1× Gated Attention; `full_attention_interval = 4`),
256 routed experts (8 active + 1 shared), expert FFN 512, hidden 2048,
KV heads 2 × 256 dim. The `-ot` regex `\.ffn_.*_exps\.` matches exactly the
120 fused expert tensors = **31.88 GiB → CPU**; GPU-resident weights are only
**2.48 GiB** (embd+output 1.03 GiB, DeltaNet+attn ~1.3 GiB, shared
experts/router ~0.2 GiB). KV at 262144 tokens (q8_0, 10 attention layers) =
**2.66 GiB**; DeltaNet recurrent state ~60 MiB (fixed).

### Why the chart-default cmd still OOMed (refined root cause)

llama.cpp's `common_fit_params` (common/fit.cpp, b11515) runs a no-alloc probe
load before every start and warned each time on gpu — "failed to fit params to
free device memory: n_gpu_layers already set by user to 99, abort" — while it
never warned on gpu-ai. Full GPU budget at load time:

| Item | Size |
|---|---|
| non-expert weights (Q8_0) | 2.48 GiB |
| KV cache, 262144 tok, q8_0 | 2.66 GiB |
| compute buffer (ub 2048; measured 753 MiB on gpu-ai) | ~0.75 GiB |
| DeltaNet/conv state | ~0.06 GiB |
| **mmproj-BF16 (auto-loaded: HF repo ships a vision projector)** | ~0.7–1 GiB |
| radv/driver overhead | ~0.3–0.5 GiB |
| **Total** | **~7.0–7.5 GiB** |

vs ~7.4 GiB usable of the 8 GiB carve-out → radv fails at command submission,
device lost, process exit. gpu-ai's capture of a successful load also shows
`Vulkan_Host compute buffer` (experts did run on CPU there; 25–27 t/s gen),
confirming `-ot` works in this build — the failure is capacity, not placement.

## Fix implemented (operator decisions 2026-10-11)

Operator requirements: keep **256k ctx**, keep **q8_0 KV cache types**, keep
**expert-only offload**, leave FA + cache types in the existing
`${flash-and-q8}` macro (**chart untouched** — a first draft folded them into
`${moe}` but was reverted at operator request).

### `services/gpu/prod/values.yaml` (gpu-only override)

```yaml
llama-swap:
  config:
    models:
      qwen3.6-35b-a3b-q8:
        cmd: |
          ${server-cmd}
          ${threads}
          -hf unsloth/Qwen3.6-35B-A3B-GGUF:Q8_0
          --no-mmproj
          --ctx-size 262144
          -b 2048
          -ub 1024
          ${moe}
          ${flash-and-q8}
        description: "...8GiB-gpu fit: experts on CPU, q8_0 KV, no vision, 256k ctx (slow)"
```

Reclaims VRAM two ways, keeping q8_0 KV + 256k ctx + expert-only offload:
- `--no-mmproj` (flag exists since well before b11515; verified in
  common/arg.cpp): skips the auto-loaded vision projector → **−0.7–1 GiB**.
  Trade-off: this model is text-only on gpu; image input still works via
  gpu-ai (`llama.<domain>`) where the chart default (with mmproj) remains.
- `-ub 1024` (vs 2048): smaller compute buffer → **−0.3–0.4 GiB**; slower
  prompt processing only (accepted: "expect slow").

Budget after fix ≈ 2.48 + 2.66 + ~0.45 + 0.06 + ~0.4 ≈ **6.0 GiB** → ~1.3 GiB
margin. Only `cmd` + `description` overridden; name/proxy/ttl merge from the
chart default.

### Validation

- `helm lint charts/llama-swap` + `helm template` → pass.
- `helm lint services/gpu/prod` + `helm template` (--set domain/clusterName)
  → pass, 66 resources.
- Merge simulation: `helm template charts/llama-swap -f <extracted gpu
  override>` → q8 cmd/description overridden; name, proxy, ttl preserved
  from chart default; macros and sibling models untouched.
- Dup-flag check across all 40 rendered cmd blocks: 0 duplicated
  `--flash-attn`/`--cache-type-*` (macro + explicit never co-occur).
- `pytest charts/llama-swap/tests/` → 33 passed.
- `--no-mmproj` verified present in b11515 (common/arg.cpp line ~2597).

### Rollout / live test (user-driven)

1. Merge → ArgoCD syncs gpu; reloader restarts gpu-llama-swap on the
   ConfigMap change. gpu-ai is unaffected (chart untouched, its rendered
   config does not change → no restart there).
2. ONE request for `qwen3.6-35b-a3b-q8` via llama-moe (avoid retry loops —
   each failed start hammers the Vulkan driver).
3. Watch: `GET /logs/stream/qwen3.6-35b-a3b-q8` (curl with `Accept:
   text/plain` from in-cluster) or Loki
   `{cluster="gpu", app_kubernetes_io_name="llama-swap"} |~ "35b-a3b-q8"`.
   Success = no `failed to fit params` warning, then `Health check passed`
   after a multi-minute load (weights already cached on PVC). First load
   holds ~32 GiB of experts in RAM — node has ~39 GiB available; watch for
   OOM-kill. If it still OOMs, remaining levers: embd/output tensors to CPU
   via extra `-ot`, `-np 1`, or ctx 192k/128k.

## Options presented to operator

1. **Use the right endpoint:** request `qwen3.6-35b-a3b-q8` via
   `llama.spencerslab.com` (gpu-ai) — proven working.
2. **Make a gpu-cluster variant that fits:** keep 256k ctx + expert offload,
   reclaim VRAM elsewhere — **chosen (2026-10-11)**: q8_0 KV kept (FA +
   cache types stay in `${flash-and-q8}`, chart untouched), `--no-mmproj` +
   ub 1024, gpu-only override in `services/gpu/prod/values.yaml`.
3. **Remove/guard the unloadable entries on gpu** so requests fail fast with
   a clear 404 instead of crashing the Vulkan device (and possibly the VM).
   Not done — deferred; note the sibling 35B q6/bf16/1m entries and other
   big-roster models remain unloadable on gpu and would fail the same way.

## How to re-check (runbook)

- Proxy-level errors: Loki
  `{cluster="gpu", app_kubernetes_io_name="llama-swap"} |~ "(?i)error|fail"`.
- Model crash output (not in Loki): from any pod inside the gpu cluster,
  `curl -sN -H 'Accept: text/plain' http://gpu-llama-swap.default.svc.cluster.local:8080/logs/stream/<model-id>`
  (returns buffered history, then SSE — cut with `timeout`).
- Running models: `GET /running`; hardware snapshot: `GET /api/hardware`.
