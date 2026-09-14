# Plan: Add per-workload `:tags` / `:caption` aliases to llama-swap Qwen3-VL models (Pictaria JSON fix)

Type: feat | Date: 2026-09-14 | Status: implemented (pending commit/merge; post-deploy steps 5-9 remain)

## Goal

Stop Pictaria's malformed-JSON tag output by adding per-workload request aliases
to every Qwen3-VL **Instruct** model in the gpu cluster's llama-swap config. The
`:tags` alias forces `chat_template_kwargs.enable_thinking: false` (llama.cpp
issue #20345: with thinking enabled, JSON-schema grammar enforcement is silently
bypassed — the prime suspect for broken JSON) plus a low temperature for
classification. A `:caption` alias (thinking off, low temp, fixed seed) is added
for Immich captioning. All aliases share one loaded model — no reload between
workloads.

## Skills

- `llama-swap` — config surface, filters/setParamsByID, aliases
- `helm-chart-creation` — chart edit + validation workflow
- `executing-plans`

## MCP Servers

- `readonly-gpu-kubernetes` — verify the live ConfigMap/pod before and after;
  read llama-swap logs post-deploy. No `admin-*` server is needed for the code
  change itself (ArgoCD syncs; the pod restart is a manual user step, see Notes).

## Verified context

- **llama-swap version**: deployed image `ghcr.io/mostlygeek/llama-swap:v240-vulkan-b10015`
  (pod `gpu-llama-swap-74ff6d54fc-tnm7t`, Running 1/1). llama.cpp is b10015
  (≥ b6887 minimum for Qwen3-VL-30B-A3B — guide satisfied).
- **v240 feature checks** (fetched `config-schema.json` at tag `v240`):
  - `filters.setParamsByID` present; description: "Keys support ${MODEL_ID} macro substitution."
  - `includeAliasesInList` present (top-level boolean, default false).
  - The `?` set-if-undefined suffix is **NOT** in the v240 schema (landed later,
    PR #1075) → this plan deliberately avoids it; all keys are hard overrides.
- **v240 behavior proof** (read `internal/config/load.go` + `filters.go` at tag v240):
  - `${MODEL_ID}` is substituted inside `setParamsByID` keys, per model, before
    registration.
  - `setParamsByID` keys are **auto-registered as aliases** (`config.aliases[key] = modelId`),
    skipping the model's own ID; error only if a key collides with another model
    ID or another model's alias. So explicit `aliases:` entries are unnecessary.
  - `model` is the only protected param; `chat_template_kwargs`, `temperature`,
    `seed` are injectable.
- **Repo state**: `charts/llama-swap/values.yaml` has 12 Qwen3-VL Instruct models
  and 6 `-thinking` variants; no `filters` anywhere yet (grep confirmed). Config
  is rendered verbatim into ConfigMap `llama-swap-config` via
  `templates/configmap-llama-swap.yaml` (`toYaml .Values.config`).
- **Cluster lag note**: the live ConfigMap is an older snapshot than the repo
  values.yaml (missing `moe-vl-*`/`flash-and-q8`/`big-ub` from the 2026-09-09
  plan). Irrelevant here — this plan edits the repo; ArgoCD applies on next sync.
- **Consumers**: Pictaria picks its model at runtime (own SQLite settings, not in
  this repo) → it must be re-pointed at a `:tags` alias after deploy (user step).
  `immich-analyze` uses `qwen3-vl-4b-q4` and is left untouched (its `:caption`
  alias becomes available; switching is an optional follow-up).

## Design decisions

- **Mechanism: `filters.setParamsByID` with `"${MODEL_ID}:tags"` / `"${MODEL_ID}:caption"`
  keys** — v240 substitutes `${MODEL_ID}` and auto-registers each key as a unique
  alias per model (source-verified above). One YAML-anchored block is reused
  verbatim on all 12 models (anchors are an established repo pattern, e.g.
  `&chartName`). No explicit `aliases:` entries, no `matrix` changes (aliases
  route to the base model, which already holds the matrix slot).
- **`:tags` params** — `chat_template_kwargs: {enable_thinking: false}` (the
  actual fix: re-enables grammar enforcement for the json_schema Pictaria already
  sends, which llama-swap passes through untouched) + `temperature: 0.2`
  (classification; guide Stage 1). No `max_tokens` override: v240 lacks the `?`
  set-if-undefined suffix and a hard value would clobber Pictaria's own budget —
  Pictaria already sets a generous timeout/token budget client-side.
- **`:caption` params** — thinking off (latency; Instruct models don't need it),
  `temperature: 0.1`, `seed: 42` for reproducible free-text captions (guide
  Stage 2). Deliberately **no** `response_format`/grammar — constraints hurt
  free-text quality (Tam et al., EMNLP 2024) and there is no schema to satisfy.
- **Thinking variants excluded** — `-thinking` weights are trained to think;
  `enable_thinking: false` is unreliable on them. The guide's fix is "use the
  Instruct model", so aliases land on Instruct models only.
- **`includeAliasesInList: true`** — so Pictaria/OpenWebUI can discover the new
  aliases in `/v1/models` (guide Stage 3; schema-confirmed for v240).
- **No `stripParams`** — nothing needs stripping; the guide warns a broad
  stripParams could accidentally drop `response_format`/`grammar`. Not adding it
  keeps those passthroughs safe.

## Changes

### 1. `charts/llama-swap/values.yaml` — [MODIFY] (only file changed)

**a) Add `includeAliasesInList: true`** in the `config:` block, directly after
`sendLoadingState: true` (line ~24):

```yaml
  # Send loading state to clients
  sendLoadingState: true

  # Expose aliases in /v1/models (incl. the :tags/:caption workload aliases
  # below) so clients that enumerate models (Pictaria, OpenWebUI) can see them.
  includeAliasesInList: true
```

**b) Add the anchored workload-filters block to the FIRST Qwen3-VL Instruct
model in document order — `qwen3-vl-4b-q4`** (line ~296). Append after its
`capabilities:` block:

```yaml
      # Per-workload aliases for this loaded model (no reload between workloads).
      # llama-swap v240 substitutes ${MODEL_ID} in setParamsByID keys and
      # auto-registers each key as an alias (verified in upstream load.go), so
      # this single block is reused verbatim on every Qwen3-VL Instruct model:
      #   <model>:tags    -> Pictaria tag extraction. Forces thinking OFF
      #                      (llama.cpp #20345: with enable_thinking=true the
      #                      json_schema grammar is silently bypassed -> broken
      #                      JSON) + low temp for classification. Pictaria sends
      #                      response_format json_schema itself; llama-swap
      #                      passes it through untouched.
      #   <model>:caption -> Immich captioning. Free-text (no schema: constraints
      #                      hurt description quality), thinking off, low temp +
      #                      fixed seed for reproducible captions.
      filters: &vlWorkloadFilters
        setParamsByID:
          "${MODEL_ID}:tags":
            chat_template_kwargs:
              enable_thinking: false
            temperature: 0.2
          "${MODEL_ID}:caption":
            chat_template_kwargs:
              enable_thinking: false
            temperature: 0.1
            seed: 42
```

**c) Add `filters: *vlWorkloadFilters`** (anchor reference, one line, after
`capabilities:`) to each of the remaining 11 Qwen3-VL Instruct models, in file
order:

1. `qwen3-vl-8b-q4`
2. `qwen3-vl-8b-q8`
3. `qwen3-vl-8b-bf16`
4. `qwen3-vl-30b-a3b-q4`
5. `qwen3-vl-30b-a3b-q8`
6. `qwen3-vl-30b-a3b-bf16`
7. `qwen3-vl-2b-q8`
8. `qwen3-vl-2b-q4`
9. `qwen3-vl-2b-bf16`
10. `qwen3-vl-4b-q8`
11. `qwen3-vl-4b-bf16`

```yaml
      filters: *vlWorkloadFilters
```

**Do NOT touch** the six `-thinking` models (`qwen3-vl-4b-thinking-{q8,q4,bf16}`,
`qwen3-vl-30b-a3b-thinking-{q8,q4,bf16}`), the non-VL models, the `macros:`
block, or the `matrix:` (aliases reuse their base model's matrix slot).

**YAML rules that matter here:**
- The `&vlWorkloadFilters` definition must appear before any `*vlWorkloadFilters`
  reference in document order (it does — `qwen3-vl-4b-q4` is the first VL model).
- The `setParamsByID` keys MUST be quoted (`"${MODEL_ID}:tags"`) — an unquoted
  `:` breaks YAML key parsing.
- Do not bump the chart `version` (CI does it on merge).

### 2. Nothing else

No ApplicationSet entry, no proxy entry, no custom-values entry — this modifies
an existing service's chart values only. No secrets involved.

## Validation

Pre-commit (Code agent):

1. `helm dependency update charts/llama-swap` (app-template subchart is not
   vendored in the worktree).
2. `helm lint charts/llama-swap` — must pass.
3. `helm template gpu-llama-swap charts/llama-swap --show-only templates/configmap-llama-swap.yaml > /tmp/ls-render.yaml`
   then check the rendered ConfigMap:
   - `grep -c 'setParamsByID:' /tmp/ls-render.yaml` → **12** (anchor fully
     resolved, one per Instruct VL model — a count of 1 or 0 means the anchor
     did not resolve).
   - `grep -c 'MODEL_ID}:tags' /tmp/ls-render.yaml` → **12** (quote-style
     agnostic: the literal `${MODEL_ID}` must survive Helm rendering —
     llama-swap substitutes it per model at config load, not Helm).
   - `grep -c 'MODEL_ID}:caption' /tmp/ls-render.yaml` → **12**.
   - `grep -c 'includeAliasesInList: true' /tmp/ls-render.yaml` → **1**.
   - `grep -c 'filters:' /tmp/ls-render.yaml` → **12** — exactly the 12 Instruct
     VL models. More than 12 means a `filters:` block leaked onto a `-thinking`
     variant or a non-VL model (toYaml emits keys alphabetically, so a
     fixed-offset spot-check is unreliable; the count is the invariant).
   - `grep -c 'OVERRIDE_' /tmp/ls-render.yaml` → **0**.
4. Optional sanity (python/yq): parse `/tmp/ls-render.yaml`'s `config.yaml` as
   YAML to prove the anchor expansion produced valid YAML for llama-swap.

Post-deploy (user — after merge to main + ArgoCD sync of `gpu-llama-swap`):

5. **Delete the llama-swap pod manually** (`kubectl delete pod -n default -l app.kubernetes.io/name=llama-swap -A`
   style) — the gpu cluster has **no reloader**, and the config is subPath-mounted,
   so only a restart picks up the new ConfigMap (same as the 2026-09-09 plan).
6. Watch logs for a config-load failure (`kubectl logs -n default <llama-swap-pod>`):
   any "duplicate alias" / "conflicts with an existing model ID" error means an
   alias collision → revisit keys.
7. `curl -s https://llama-cpp.spencerslab.com/v1/models | jq -r '.data[].id'`
   → should list base models **plus** `<model>:tags` / `<model>:caption` entries
   (proves auto-registration + `includeAliasesInList`).
8. Smoke test the fix end-to-end (loads the model, ~1-2 min cold):
   ```bash
   curl -s https://llama-cpp.spencerslab.com/v1/chat/completions -H 'Content-Type: application/json' -d '{
     "model": "qwen3-vl-30b-a3b-q8:tags",
     "messages": [{"role":"user","content":"Return tags for: a beach at sunset."}],
     "temperature": 0.2,
     "response_format": {"type":"json_schema","json_schema":{"name":"tags","strict":true,"schema":{
       "type":"object","properties":{"tags":{"type":"array","items":{"type":"string",
       "enum":["beach","forest","mountain","city","portrait","food","animal","sunset"]},"maxItems":5}},
       "required":["tags"],"additionalProperties":false}}}
   }' | jq .
   ```
   Expect syntactically valid JSON. If it is still malformed, grep the upstream
   logs for `failed to parse grammar` (fail-open, #19051) and confirm the request
   did not carry `enable_thinking: true`.
9. Re-point **Pictaria**'s AI-provider model setting at the new alias (e.g.
   `qwen3-vl-30b-a3b-q8:tags`) — runtime config in Pictaria's UI, not this repo.
   Keep the tag vocabulary described in Pictaria's system prompt (the schema is
   never injected into the prompt by llama.cpp).

## Notes / risks

- **Fallback if `${MODEL_ID}`-in-keys misbehaves despite the source read** (very
  unlikely — code path is explicit in v240): replace the anchored block's keys
  with explicit per-model keys (`qwen3-vl-4b-q4:tags`, …). Everything else stays.
- `setParamsByID` hard-overrides: if a client sends its own `chat_template_kwargs`
  on a `:tags`/`:caption` request, the alias's `{enable_thinking: false}` replaces
  it wholesale (no deep merge). That is the intent here.
- `includeAliasesInList` doubles the `/v1/models` list with alias duplicates —
  cosmetic; clients that hardcode model names are unaffected.
- immich-analyze still calls base `qwen3-vl-4b-q4` (unchanged behavior). Switching
  it to `qwen3-vl-4b-q4:caption` is an optional follow-up
  (`charts/immich-analyze/values.yaml` → `config.modelName`).
- If a `:tags` alias is requested while another model is loaded, normal matrix
  eviction applies (aliases are not matrix members; their base model is).
- After merge: CI bumps chart version; ArgoCD syncs; pod restart required (no
  reloader on gpu — see step 5).
