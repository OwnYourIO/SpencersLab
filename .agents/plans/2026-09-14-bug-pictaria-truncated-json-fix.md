# Plan: Fix Pictaria truncated/malformed JSON — max_tokens cap + json_schema response format

Type: bug | Date: 2026-09-14 | Status: implemented (pending commits + image build)

## Goal

Pictaria enrichment against `qwen3-vl-30b-a3b-q8:tags` (via llama-swap) still
produced malformed JSON after the `:tags` aliases landed. Diagnosis of the
captured request/response showed the `:tags` alias IS applied
(`chat_template_kwargs.enable_thinking:false` + `temperature:0.2` present), but
two different defects in Pictaria's `openai_compatible` adapter broke the output:

1. **Truncation** — response `finish_reason:"length"` with
   `completion_tokens == max_tokens == 2400`. The JSON is cut mid-string inside
   `subjects`. The adapter hardcodes `max_tokens: 2400` (constructor default;
   no env knob existed). This alone explains "bad JSON": `json_object` grammar
   guarantees syntactically valid JSON unless generation hits the token cap.
2. **No schema grammar** — the adapter deliberately sends
   `response_format:{type:"json_object"}` (portability decision documented in
   `providers.mjs`), embedding the schema only as prompt text. So llama.cpp
   enforced "any valid JSON", not Pictaria's schema: the model emitted ~61
   `candidate_tags` (schema allows `maxItems:50`) with verbose reasons, which
   both blows the token budget and would fail Pictaria's `validateAiOutput`
   even if it completed.

Answer to "is response_template being put in the request correctly?": the
schema rides in the prompt text (working as designed), but the
`response_format` json_schema path was never invoked — the adapter only ever
sent `json_object`.

## Skills

- `helm-chart-creation` — chart edit + validation workflow (charts/pictaria)

## MCP Servers

- none required (no cluster inspection needed; diagnosis from captured
  request/response + source reading)

## Changes

### 1. Pictaria fork (`/home/coder/pictaria-server`, remote CuratedForest/pictaria-server)

Follows the established pattern of commit 827522f (OPENAI_COMPATIBLE_TIMEOUT_MS):

- `src/enrich/providers.mjs`
  - `OpenAiCompatibleProvider` constructor: `maxTokens` default 2400 → **8192**
    (matches the cloud OpenAI budget; a ceiling, not a target); new option
    `jsonSchemaResponseFormat = false`.
  - `analyzeImages`: accepts `schemaName` (default
    `'pictaria_photo_enrichment'`; referee passes `'pictaria_group_referee'`);
    when `jsonSchemaResponseFormat` is set, sends
    `response_format:{type:"json_schema", json_schema:{name, strict:true, schema}}`
    (same shape as the LM Studio adapter); otherwise keeps `json_object`.
    Schema text still rides in the prompt in both modes (grammar constrains
    shape; the prompt is how the model sees field meanings).
  - `enrichmentProviderConfiguration` snapshot: exposes
    `jsonSchemaResponseFormat`, `adapterContractVersion` bumped 1 → 2
    (fixed request options changed).
- `src/config.mjs` — `openai_compatible` block gains
  `maxTokens: parseOptionalInteger(env.OPENAI_COMPATIBLE_MAX_TOKENS, 8192)`
  (`none` disables) and
  `jsonSchemaResponseFormat: parseBoolean(env.OPENAI_COMPATIBLE_JSON_SCHEMA)`.
- `.env.example`, `docker-compose.yml`, `docs/CONFIGURATION.md`, `CHANGELOG.md`
  (Unreleased/Added) — document both new variables.
- Tests: `test/config.test.mjs` (tunable cap + fallback + `none`; opt-in flag;
  updated exact-shape assertion), `test/enrich/providers.test.mjs`
  (default max_tokens now 8192; json_schema mode sends name/strict/schema,
  respects schemaName, keeps schema in prompt).

### 2. GitOps (`charts/pictaria/values.yaml`)

Added to the container env (next to `OPENAI_COMPATIBLE_TIMEOUT_MS`):

```yaml
OPENAI_COMPATIBLE_MAX_TOKENS: "8192"
OPENAI_COMPATIBLE_JSON_SCHEMA: "true"
```

### 3. llama-swap chart — no further changes

The `:tags`/`:caption` aliases from the earlier 2026-09-14 plan stay as-is:
they still supply `enable_thinking:false` (llama.cpp #20345: thinking bypasses
the grammar) + workload temperatures. `response_format`/`max_tokens` now come
from Pictaria itself, avoiding taxonomy/schema duplication drift between the
two charts.

## Validation

- Pictaria: `node --test` over `test/config.test.mjs`,
  `test/enrich/*.test.mjs`, `test/settings.test.mjs` (493 pass),
  `test/enrich/providers.test.mjs` + `runConfiguration` (72 pass),
  `test/voice/*.test.mjs` (87 pass). Full `npm test` not run to completion in
  this environment (10-min timeout on unrelated slow suites); all suites that
  import the changed modules pass.
- GitOps: `helm dependency update charts/pictaria`, `helm lint charts/pictaria`
  (pass), `helm template` renders the Deployment with both env vars
  (`OPENAI_COMPATIBLE_JSON_SCHEMA="true"`, `OPENAI_COMPATIBLE_MAX_TOKENS="8192"`),
  no `OVERRIDE_` sentinels.

## Deploy sequence (user)

1. Commit the Pictaria fork changes and build/push the patched image
   (`ghcr.io/curatedforest/pictaria-server:latest` — the chart tracks
   `:latest` with `pullPolicy: Always`).
2. Merge the GitOps worktree branch (charts/pictaria + charts/llama-swap) to
   main; ArgoCD syncs. The new env vars are inert on the old image (unknown
   env vars are ignored), so ordering is safe either way.
3. Restart the Pictaria pod to pull the new image (home cluster has reloader,
   but the image tag is unchanged `:latest` — delete the pod manually to force
   a re-pull).
4. Re-run an enrichment job; expect `finish_reason:"stop"`, complete valid
   JSON, and `candidate_tags` bounded to the schema's `maxItems:50`.

## Notes / risks

- `max_tokens` is a ceiling: json_schema grammar bounds output size
  (`maxItems:50`, enum-only tags), so realistic outputs (~3-4k tokens) fit
  well inside 8192.
- `OPENAI_COMPATIBLE_JSON_SCHEMA` is opt-in upstream-style: default off keeps
  the portable `json_object` path for generic servers; the chart enables it
  because the endpoint is llama.cpp behind llama-swap (known json_schema
  support).
- If a future Pictaria taxonomy change alters the schema, no llama-swap change
  is needed — the same code that builds the schema sends it.
