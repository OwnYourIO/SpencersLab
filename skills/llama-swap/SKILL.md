---
name: llama-swap
description: Write, debug, and reason about llama-swap config.yaml files and its HTTP API. llama-swap is a Go proxy that hot-swaps local inference servers (llama.cpp/llama-server, vLLM, tabbyAPI, stable-diffusion.cpp, whisper.cpp) behind one OpenAI/Anthropic-compatible endpoint. Use this skill whenever the user mentions llama-swap, llama-server model swapping, a config.yaml with a `models:` block and `cmd:` entries, `${PORT}`/`${MODEL_ID}` macros, the `matrix` or `groups` concurrency features, or is trying to serve several local models from a single /v1 base URL — even if they don't name llama-swap directly.
---

# llama-swap

A single Go binary + a single YAML file. On a request to `/v1/chat/completions` (or
any supported endpoint), llama-swap reads the `model` field, starts the matching
upstream server if it isn't running, evicts whatever conflicts, and proxies through.

## Before answering config questions

llama-swap ships fast and the config surface changes between releases. **Fetch the
current reference rather than relying on memory:**

- `https://github.com/mostlygeek/llama-swap/blob/main/config.example.yaml` — the
  authoritative, heavily-commented reference for every option
- `https://raw.githubusercontent.com/mostlygeek/llama-swap/refs/heads/main/config-schema.json` — JSON Schema
- `https://github.com/mostlygeek/llama-swap/blob/main/docs/configuration.md` — prose

If the user has a local checkout or a running instance, prefer those. Ask for their
version (`llama-swap --version`) when a feature's availability is in question.

Always add the schema modeline to configs you write:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/mostlygeek/llama-swap/refs/heads/main/config-schema.json
```

## Minimum viable config

```yaml
models:
  model1:
    cmd: llama-server --port ${PORT} --model /path/to/model.gguf
```

`models` is the only required top-level key. The map key (`model1`) is the ID used
in API requests. Everything else has a default.

## Macros

| Macro | Meaning |
|---|---|
| `${PORT}` | Auto-assigned unique port per model, counting up from `startPort` (default 5800) |
| `${MODEL_ID}` | The model's key in `models:` |
| `${PID}` | Upstream process ID — only valid inside `cmdStop` |
| `${env.VAR}` | System environment variable; substituted first. **Config load fails if unset.** |
| `${custom}` | User-defined in the `macros:` block |

Macro names: `^[a-zA-Z0-9_-]+$`, under 64 chars, may not be `PORT` or `MODEL_ID`.
Macros can reference other macros, but only ones defined earlier. Model-level
`macros:` override globals. Values keep their YAML type — `${PORT}` inside
`metadata:` stays an integer.

## Per-model keys

`cmd` (required) · `cmdStop` · `name` · `description` · `env` (array of `"K=V"`)
· `proxy` · `checkEndpoint` · `ttl` · `unloadTimeout` · `useModelName` · `aliases`
· `unlisted` · `metadata` · `concurrencyLimit` · `sendLoadingState` · `timeouts`
· `filters` (`stripParams`, `setParams`, `setParamsByID`)

Notes that matter in practice:

- **`cmd` with `|`** gives multi-line commands and allows `#` comments inside, which
  are stripped before execution. Use it for anything non-trivial.
- **`proxy` is only needed when you hardcode a port** in `cmd` instead of `${PORT}`.
  Forgetting this is the single most common config bug.
- **`ttl`**: `-1` = inherit `globalTTL`; `0` = never unload; `>0` = seconds idle.
  This tri-state trips people up — `0` means *never*, not *immediately*.
- **`checkEndpoint`** defaults to `/health`, must return 200. Set to `"none"` for
  upstreams with no health route.
- **`aliases`** must be globally unique. Use them to impersonate `gpt-4o-mini` etc.
  for clients with hardcoded model names.
- **`setParamsByID`** auto-creates aliases per key, so `${MODEL_ID}:high` /
  `:low` variants give different sampling without a reload.

## Concurrency: `matrix`

Newer configs use `matrix`; older ones use `groups`. **A config may define one or
the other, never both** — defining both is a hard config error. If the user has
`groups`, don't silently migrate them; ask first.

```yaml
matrix:
  vars:            # short names (alphanumeric, 1-8 chars) → real model IDs, not aliases
    g: gemma-model
    v: voxtral-model
    L: llama-70B
  evict_costs:     # relative cost of losing a running model, default 1
    L: 30
  sets:
    standard: "(g | q | m) & v"   # → [g,v], [q,v], [m,v]
    full: "L"                     # 70B runs alone
```

DSL: `&` = run together, `|` = alternatives, `()` = grouping, `+name` = inline
another set. A set `[a,b,c]` means **any subset is valid**; only the requested model
starts, the rest are not preloaded. A model in no set can only run alone.

Solver: if the model is running, forward. Otherwise find all sets containing it,
score each by the summed `evict_costs` of running models *not* in that set, pick the
cheapest, ties broken by definition order.

## Other top-level keys

`healthCheckTimeout` (default 120s, floor 15s) · `logLevel` · `logTimeFormat` ·
`logToStdout` (`proxy`/`upstream`/`both`/`none`) · `metricsMaxInMemory` ·
`captureBuffer` · `startPort` · `globalTTL` · `unloadTimeout` · `sendLoadingState` ·
`includeAliasesInList` · `apiKeys` · `macros` · `profiles` · `hooks` · `peers` ·
`store` · `performance` · `ui`

- **`apiKeys`** is default-allow: an empty list means no auth is checked at all.
- **`hooks.on_startup.preload`** takes a list of model IDs. Preloading several at
  once only works if the matrix permits them concurrently — otherwise they load and
  immediately swap each other out.
- **`peers`** proxies to remote llama-swap instances *or* any OpenAI-compatible
  provider (OpenRouter et al.), with per-peer `apiKey`, `timeouts`, and `filters`.
- **`profiles`** are named model-ID pin sets switchable at runtime via UI or
  `PUT /api/profiles/active`. Pins apply before aliases, filters, and routing. A pin
  target of `~` or `""` disables that ID with a 404.

## Kubernetes

> Upstream ships no official Kubernetes guidance. The notes below follow from how
> llama-swap works (it supervises OS processes, not orchestrated workloads) rather
> than from documented practice — treat them as a starting shape, not gospel.

**llama-swap manages processes, not pods.** `cmd` forks a child process and llama-swap
owns its lifecycle. It has no concept of scheduling a Deployment. That forces a choice:

1. **Co-located (llama-swap swaps).** Run llama-swap and the inference binaries in one
   container — the unified image (`ghcr.io/mostlygeek/llama-swap:unified-cuda`) bundles
   llama-server, ik-llama-server, stable-diffusion.cpp and whisper.cpp for exactly this.
   `cmd` launches siblings inside the pod, `${PORT}` stays pod-local, and swapping
   actually reclaims VRAM. This is the shape that preserves llama-swap's whole point.
2. **Separate Deployments (llama-swap only routes).** Give each model its own
   Deployment + Service and reference them under `peers:` pointing at cluster DNS.
   llama-swap then does routing and a unified `/v1` surface but **no swapping** — every
   model holds its VRAM permanently. Fine for always-on models, wrong if you're using
   llama-swap to fit models into limited GPU memory.

Don't mix the two accidentally. If a user has a `peers:` config and complains that
models never unload, that's the answer.

Deployment notes for shape 1:

- **Config via ConfigMap** mounted at the path passed to `--config`. Mount the
  *directory*, not `subPath` the single file — `subPath` mounts don't receive
  ConfigMap updates at all, which silently kills config reload.
- **Weights on a PVC** (ReadOnlyMany if several replicas) or hostPath on the GPU node.
  Keep the mount path identical to what `cmd` references.
- **`nodeSelector`/GPU resource limits** on the pod; drop `CUDA_VISIBLE_DEVICES` from
  per-model `env` unless the pod actually sees multiple GPUs.
- **Probes**: `/health` returns OK from llama-swap itself, not the upstream, so it
  won't flap mid-swap — safe for both liveness and readiness. Don't point a probe at a
  model endpoint; that triggers loads.
- **`terminationGracePeriodSeconds` must exceed `unloadTimeout`**, or the kubelet kills
  the pod while children are still shutting down.
- **`apiKeys` from a Secret** via `${env.VAR}` — remember an unset env var is a hard
  config-load failure, so the Secret must exist before the pod starts.
- **Replicas > 1 needs thought.** Each replica keeps independent process state, so
  round-robined requests can load the same model on every replica at once. Either pin
  to one replica or use session affinity.

## HTTP surface

OpenAI: `v1/completions`, `v1/chat/completions`, `v1/responses`, `v1/embeddings`,
`v1/models`, `v1/audio/speech`, `v1/audio/transcriptions`, `v1/audio/voices`,
`v1/images/generations`, `v1/images/edits`.
Anthropic: `v1/messages`, `v1/messages/count_tokens`.
llama.cpp passthrough: `v1/rerank`, `/infill`, `/completion`, `/props?model=<id>`.
Management: `/ui`, `/upstream/:model_id`, `/running`, `POST /api/models/unload[/:id]`,
`GET /api/profiles`, `PUT /api/profiles/active`, `/health`, `/metrics`.

Logs: `GET /logs` (buffered), `/logs/stream`, `/logs/stream/proxy`,
`/logs/stream/upstream`, `/logs/stream/{model_id}`. Append `?no-history` to skip the
buffered backlog. Reach for these first when debugging — a failed swap almost always
explains itself in the upstream stream.

## Debugging checklist

1. Model 404s → ID mismatch between request and `models:` key, or an inactive
   profile pin disabling it.
2. Swap hangs or times out → `healthCheckTimeout` too low for a large model, or
   `checkEndpoint` pointing somewhere that never returns 200.
3. Wrong/dead upstream → hardcoded port in `cmd` without a matching `proxy`.
4. Streaming arrives in bursts or not at all → something between client and llama-swap
   is buffering responses, which breaks SSE. llama-swap sets `X-Accel-Buffering: no`
   as a hint, but any ingress controller, service mesh sidecar, or gateway in the path
   may need response buffering explicitly disabled for `/v1/chat/completions` and
   `/api/events`.
5. Config won't load → an unset `${env.VAR}`, an undefined-before-use macro, or
   `matrix` and `groups` both present.
6. Models thrash under load → the matrix has no set containing both, so each request
   evicts the other. Add a set, and raise `evict_costs` on the slow-loading one.