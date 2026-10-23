# PLAN: llama-swap config autogen adoption + desired-state roster (Path A)
feature: 2026/2026-10-feat-llama-swap-config-generation

## Goal
Stop hand-editing the llama-swap `config.yaml`: render the whole declared `-hf`
roster from compact per-model entries in Helm values (the desired-state half),
wire `shirayu/llama_swap_config_autogen` (pinned SHA, stock, no fork) as an
initContainer generating the disk-scanned half into an emptyDir, and merge both
via llama-swap v262 `-config` + `-config-dir`. Convert all existing models and
snippet-macros with zero model-ID changes, and add the flash-next / Ornith
1.5 122B / Ornith 1.5 35B / orcarouter-uncensored roster.

## Out of scope
- Path B (fork with `hf_models:`) — user chose stock tool (DECISIONS 2026-10-22).
- Renaming any existing model ID/alias (consumers: OpenWebUI, Pictaria, Immich, HA, agent routing).
- Serve-testing on gpu-ai (busy; config-level validation only there).
- Changing the llama-swap image (`unified-vulkan-262`) or chart version bumps (release.yaml owns).
- profiles/peers/apiKeys changes; tools sidecar; proxy wiring (already exists, unchanged).

## Architecture (locked, from DECISIONS.md + verified against v262 source)
Two config sources merged natively:
1. **Declared half** — ConfigMap `llama-swap-config`, key `config.yaml`, directory-
   mounted at `/app/config` (unchanged paths). Helm renders it from a compact
   roster schema in values (`config.models.<id>: {hf, draft, use[], flags, cmd,
   disabled, name, description, ttl, aliases, capabilities, filters,
   checkEndpoint, ...}`). Precedence `disabled > cmd > hf-composition`. All
   macros, matrix, hooks, filterPresets live ONLY here.
2. **Scanned half** — initContainer runs `llama-swap-config-autogen generate`
   from a rendered `base.yaml` ConfigMap into emptyDir `/app/gen/10-scanned.yaml`;
   `LLAMA_SWAP_CONFIG_DIR=/app/gen`. Empty scan dir (today's steady state) →
   degrade to a comment-only file (skipped by the loader — verified in v262
   `merge.go` `parseSource`/`listYAMLFiles`).
Merge facts verified at `v262` (`internal/config/merge.go`, `matrix.go`, `docker/unified/run.sh`):
identical scalars across sources OK, differing scalars hard-error; `models`/
`groups`/`matrix` are identity maps — duplicate children hard-error, so
generated IDs (`<dir>:<QUANT>` namespace) never collide with declared dash-IDs;
`matrix` in two files = hard error (its children `vars`/`sets` are identity keys)
→ matrix in declared half only; `matrix.vars` referencing a missing model is a
load error (matrix.go:71); empty config-dir is valid when `-config` is set.
Refinement of RESEARCH §5: it proposed passing matrix/hooks through base.yaml —
invalid in the two-file world (see DECISIONS append).

## Commands
- `helm dependency update charts/llama-swap`
- `helm lint charts/llama-swap`
- `helm template llama-swap charts/llama-swap --set domain=spencerslab.com --set clusterName=gpu`
- per-cluster render (extract `llama-swap:` subtree from service values, render with `-f`,
  pattern in skills/helm-chart-creation/references/mcp-servers.md):
  `python3 -c "import yaml; d=yaml.safe_load(open('services/gpu/prod/values.yaml'))['llama-swap']; yaml.safe_dump(d, open('/tmp/gpu-vals.yaml','w'))"`
  → `helm template llama-swap charts/llama-swap -f /tmp/gpu-vals.yaml --set domain=spencerslab.com --set clusterName=gpu`
  (same for `services/gpu-ai/prod/values.yaml` + `--set clusterName=gpu-ai`)
- golden capture (pre-conversion, for C02 parity):
  `mkdir -p charts/llama-swap/tests/golden && helm template llama-swap charts/llama-swap -f <extracted-gpu> --show-only templates/configmap-llama-swap.yaml > charts/llama-swap/tests/golden/gpu.config.yaml` (same gpu-ai)
- `pytest charts/llama-swap/tests -v` (existing CI harness, workflow llama-swap-tools-tests.yaml already triggers on all touched paths)
- autogen pinned install + runs (evidence for the "No models found" failure and for generate/validate against the rendered base.yaml, empty + synthetic GGUF fixture scan sets built with the chart's vendored `scripts/gguf-py`):
  `python3.12 -m venv /tmp/ag && /tmp/ag/bin/pip install "llama-swap-config-autogen @ https://github.com/shirayu/llama_swap_config_autogen/archive/c7357e68c755b54557f5b0f88b0507bf1c981500.tar.gz"`
  → `/tmp/ag/bin/llama-swap-config-autogen validate <rendered base.yaml>`; `generate --config base.yaml -o out.yaml`
- merged-config validation with the fleet image (run.sh execs args; `-validate` exists — llama-swap.go:126):
  `docker run --rm -v $PWD/rendered:/c ghcr.io/mostlygeek/llama-swap:unified-vulkan-262 -config /c/config.yaml -config-dir /c/gen -validate`
- `docker build containers/llama-swap-autogen` (PR CI also builds via docker-build.yaml)
- trio/sentinel greps: `grep -rn "OVERRIDE_VIA" charts/llama-swap/templates services/gpu*/prod/values.yaml | grep -v custom-values` renders empty for these keys via custom-values; `grep -n "llama-swap" services/gpu/prod/values.yaml services/gpu-ai/prod/values.yaml` chart entries intact; `grep -n "llama" services/gpu/prod/values.yaml services/gpu-ai/prod/values.yaml` proxy entries intact.
- cluster checks (post-merge, gpu box only): readonly-gpu-kubernetes — Application Synced/Healthy, initContainer Ready, pod logs show merged config load + model count; `GET /v1/models` completeness. NEVER kubectl apply; no gpu-ai disturbance; admin-* MCP only with explicit user approval.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | containers/llama-swap-autogen image (pinned SHA) | S | 1 | [] | — |
| C02 | declared-half render: roster schema + Helm templates + convert chart & gpu & gpu-ai values (golden parity) | L | 1 | [] | — |
| C03 | autogen wiring: base.yaml ConfigMap, initContainer, /app/gen emptyDir, degrade path, reload semantics | M | 2 | [C01, C02] | C01 supplies the image reference; C02 defines the values layout base.yaml renders from + the merged-config surface `-validate` checks |
| C04 | new model roster: flash-next q3–q6 + orca, Ornith-122B q3–q6 (gpu-ai), Ornith-35B ladder (chart, gpu-tuned), matrix/preload additions | M | 2 | [C02] | entries are data in the C02 schema; independent of C01/C03 machinery (new models all ride the declared half) |
| C05 | post-merge gpu-box verification + reload/rollback runbook (user-gated) | S | 3 | [C01–C04] | needs everything synced via ArgoCD (main); verification per AGENTS.md is GitOps-only |

## Wave order
1. C01, C02 (independent; C01 image, C02 config layer)
2. C03, C04 (C03 ⟂ C04; both need C02; C03 also needs C01)
3. C05 (after user lands the PR)

## Delivery decisions (summary; full log in DECISIONS.md)
- Autogen delivery = self-built `containers/llama-swap-autogen` (python:3.12.15-slim-bookworm,
  pip-install from the pinned tarball URL at build, renovate `git-refs` ARG pin, uid 65532).
  Rejected: runtime pip from tarball (boot egress/latency, non-immutable), vendored source
  ConfigMap (still needs pydantic/gguf/jsonschema from PyPI at boot). First chart reference:
  `:main` + `pullPolicy: Always` (no `:v<run>` exists pre-merge), pin to first immutable tag
  after landing — documented new-container exception.
- Degrade path: empty scan set OR generate failure → comment-only `10-scanned.yaml`, exit 0
  (fail-open, logged): the scanned half only ever adds models; crashing the pod costs the lab's
  live consumers (Immich/HA/OpenWebUI) against no upside.
- New IDs (gpu-ai-only): `qwen3.8-flash-next-q3/-q4/-q5/-q6`, `qwen3.8-flash-next-orca-q6`
  (gated, HF_TOKEN), `ornith-1.5-122b-q3/-q4/-q5/-q6`. Chart-wide: `ornith-1.5-35b-a3b-`
  `iq2xxs/q3/q4/q5/q6/q8/bf16`. flash-next q5/q6: declared ENABLED, no matrix membership
  (runs-alone semantics), never preloaded (user-accepted risk).
- 35B ladder proposed for approval: official 5 (Q4_K_M/Q5_K_M/Q6_K/Q8_0/BF16)
  + bartowski Q3_K_XL + bartowski IQ2_XXS; rejected Q*_K_L/IQ3/IQ4 tiers as redundant IDs.

## Risks / assumptions
- `${moe}`'s `-ot "\.ffn_.*_exps\.=CPU"` regex may not match the Qwen4Exp (flash-next)
  tensor naming → C04 must verify against real GGUF headers via HF range-fetch before wiring
  the macro (mismatch → new `fn-moe` macro with corrected regex).
- 122B/flash-next repos churn (122B GGUF updated 2026-10-21) → re-verify exact `repo:TAG`
  refs at implementation (C04 has an API-check step).
- gpu-ai RAM fit for q3/q4-class residents is measure-on-cluster territory (RESEARCH 7/10):
  mitigated by no preload + solo/absent-from-matrix for everything above the 35B tier.
- stakater reloader must pick up the new base.yaml ConfigMap (mounted volume → auto mode);
  if not, add `reloader.stakater.com/match`. C03 acceptance covers it.
- `hooks`/`filters`/`env` key shapes preserved verbatim through rendering — parity test is
  normalized-token equality (cmd flag sets), not byte equality (comments/anchors expand).
