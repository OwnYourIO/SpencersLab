# llama-swap operator tools

The `tools` sidecar is disabled in the chart defaults and enabled only on
gpu-ai. It sleeps until an operator invokes the CLI; it has no port and no GPU
allocation. Nothing here runs automatically — no provisioning, no downloads,
no smoke tests at pod startup.

Scripts ship read-only via the `llama-swap-tools` ConfigMap, mounted at
`/app/tools`. All state (venv, staged converter, downloads, conversion
outputs) lives under `/models` so it survives restarts. `llama_tools.py` is
stdlib-only so it runs before `prepare` has built the venv.

## Commands

Run against the **gpu-ai** context after ArgoCD has synced the tools
container. Agents must not run pod exec — these are for the operator:

```sh
kubectl -n default exec deploy/gpu-ai-llama-swap -c tools -- python /app/tools/llama_tools.py status
kubectl -n default exec deploy/gpu-ai-llama-swap -c tools -- python /app/tools/llama_tools.py prepare
kubectl -n default exec deploy/gpu-ai-llama-swap -c tools -- python /app/tools/llama_tools.py convert-cyber
kubectl -n default exec deploy/gpu-ai-llama-swap -c tools -- python /app/tools/llama_tools.py verify
kubectl -n default exec deploy/gpu-ai-llama-swap -c tools -- python /app/tools/llama_tools.py download rana-mtp      # optional, rana also bootstraps itself
kubectl -n default exec deploy/gpu-ai-llama-swap -c tools -- python /app/tools/llama_tools.py smoke-test qwen38-orca
```

| Command | Behavior |
|---|---|
| `status` | No downloads, no model loads. Reports which runtime artifacts (cyber LoRA GGUF, rana MTP draft/mmproj) are present or missing, plus venv/converter/adapter staging state and whether `HF_TOKEN` is set. |
| `prepare` | Creates/reuses the PEP668-safe venv at `/models/.tools/venv` (CPU-only torch + transformers, the large download), stages the vendored b10015 converter from `/app/tools` into `/models/.tools/converter/`, and fetches the cyber PEFT adapter + its base-model config. **No GGUF downloads.** |
| `convert-cyber` | Runs the vendored `convert_lora_to_gguf.py --outtype f16 --base <base config>` against the staged adapter. Publishes `/models/qwen38-cyber-lora-f16.gguf` via temp-file + atomic rename only on success and records its SHA-256. Fails loudly on unsupported tensors; nothing is published on failure. |
| `download <artifact>` | Consent gate: refuses to run without an explicitly named artifact (`rana-mtp`, `rana-mmproj`). Range-resumable `.part` download + atomic rename; `--force` to re-download. |
| `verify` | Size + SHA-256 checks of provisioned artifacts against their recorded `.sha256` sidecars. Missing (not yet provisioned) artifacts are skips, not failures. Does **not** prove inference compatibility. |
| `smoke-test <model>` | Explicit only. Requests pod-local `/v1/models`, then a tiny chat completion from the named model — may trigger a cold load/download. Never runs automatically. |

## Credentials and safety

- `hf-token` is a Bitwarden-backed ExternalSecret (chart template
  `secret-hf-token.yaml`, guarded on `bitwardenIds.hf-token`). On gpu-ai it is
  injected as `HF_TOKEN` into **both** the `main` container (gated `-hf`
  model downloads — llama.cpp b10015 picks the token up from the env) and the
  `tools` container. The gpu cluster has no `bitwardenIds.hf-token`, renders
  no secret, and gets no `HF_TOKEN`.
- The token is used only for `huggingface.co` requests and is never logged;
  error messages redact it.
- Gated repos (orcarouter) additionally require that the HF account has
  accepted the model's license terms — a 401 is reported as such.

## Converter provenance

The vendored converter is the exact script from llama.cpp tag `b10015` (the
image's build) plus the minimal lazy-import subset of the repo-local
`conversion/` and `gguf-py/` packages it needs (PyPI `gguf` is stuck at 0.9.1;
b10015 ships 0.19.0). See `scripts/converter-source.json` for the pinned
commit and per-file sha256s, and `scripts/LLAMA_CPP_LICENSE` for the MIT
license. The ConfigMap embedding ships ~750 KiB of script data — keep the
1 MiB ConfigMap etcd limit in mind when adding files.

## Cyber Phase 2 activation

1. `prepare` → `convert-cyber` → `verify` (commands above; the offline test
   suite validates the converter on a synthetic adapter, not on-GPU load).
2. In `services/gpu-ai/prod/values.yaml`: uncomment the `qwen38-cyber` model
   block and the `q38cyber` matrix var, append `q38cyber` to `sets.main`.
3. After ArgoCD syncs: `smoke-test qwen38-cyber`.
