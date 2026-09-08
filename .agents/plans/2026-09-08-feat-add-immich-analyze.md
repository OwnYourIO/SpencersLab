# Plan: Add immich-analyze with Qwen3-VL models on llama-swap

## Goal
Deploy `immich-analyze` (https://github.com/timasoft/immich-analyze) as a background worker in the **home** cluster so it can generate AI image descriptions for the existing Immich deployment. It will use Immich API mode and point at the existing gpu-cluster llama-swap service. Also add three Qwen3-VL vision models to llama-swap: 4B, 8B, and 30B-A3B, each paired with its matching F16 mmproj projector. Set analysis concurrency to 2.

## Skills
- `helm-chart-creation`
- `helm-bjw-s-chart`
- `kubernetes-skill`

## MCP Servers
- `home-readonly-kubernetes` — verify Immich service and post-deploy pod/secret state
- `gpu-readonly-kubernetes` — verify llama-swap service/ingress and post-deploy model config
- No admin servers are needed for planning; implementation only writes repo files and lets ArgoCD sync.

## Verified context
- Existing Immich deployment:
  - Chart: `charts/immich/` wraps upstream `immich` chart `0.12.0`.
  - Service on home cluster: `home-immich-server` port `2283` (confirmed via live Service list).
  - Ingress: `pictures` subdomain in `services/home/prod/values.yaml` maps to `home-immich-server:2283`.
- Existing llama-swap deployment:
  - Chart: `charts/llama-swap/`.
  - Service on gpu cluster: `gpu-llama-swap` port `8080` (confirmed via live Service list).
  - Ingress: `llama-cpp` subdomain in `services/gpu/prod/values.yaml` maps to `gpu-llama-swap:8080`; also `llama` serviceName ingress exists.
  - GPU ingress template applies long-timeout ServersTransport: `default-llama-timeouts@kubernetescrd`.
  - Current llama-swap config has text models only; no vision models.
- Cross-cluster pattern confirmed: gpu workloads already call home services via public/mesh hostname, e.g. `https://wekan.spencerslab.com`.
- Domain templating confirmed: `--set app-template.domain=...` renders into env values such as `SEARXNG_BASE_URL`.
- `ghcr.io/timasoft/immich-analyze` currently publishes only rolling tags `main` and `nightly`; no pinned version tags observed. Latest GitHub release is `v0.4.3`.
- Qwen3-VL GGUF repos verified on Hugging Face:
  - `unsloth/Qwen3-VL-4B-Instruct-GGUF` has `Qwen3-VL-4B-Instruct-Q4_K_M.gguf` and `mmproj-F16.gguf`.
  - `unsloth/Qwen3-VL-8B-Instruct-GGUF` has `Qwen3-VL-8B-Instruct-Q4_K_M.gguf` and `mmproj-F16.gguf`.
  - `unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF` has `Qwen3-VL-30B-A3B-Instruct-Q4_K_M.gguf` and `mmproj-F16.gguf`.

## Design decisions
1. **Custom chart**: No official Helm chart found for immich-analyze, so create `charts/immich-analyze/` using the repo-standard bjw-s `app-template` dependency.
2. **Home cluster placement**: immich-analyze runs in `services/home/prod` because Immich is on home. This keeps Immich API calls cluster-local (`http://home-immich-server:2283`) and only sends inference requests cross-cluster to gpu llama-swap.
3. **API mode**: Use `IMMICH_ANALYZE_DATA_ACCESS_MODE=immich-api`. Database mode is deprecated upstream and would require direct DB credentials plus filesystem access.
4. **AI backend**: Use existing llama-swap with `IMMICH_ANALYZE_INTERFACE=llamacpp` and `IMMICH_ANALYZE_HOSTS=https://llama-cpp.{{ .Values.domain }}`. llama-swap currently has no vision model, so add Qwen3-VL models.
5. **Models**: Add all three requested Qwen3-VL Instruct GGUF models with matching F16 mmproj:
   - `qwen3-vl-4b` for ~8–12 GB VRAM.
   - `qwen3-vl-8b` for ~12–16 GB VRAM.
   - `qwen3-vl-30b-a3b` for 24 GB+ VRAM; use existing `${moe}` macro to offload experts to CPU if needed.
6. **Default model**: Default immich-analyze to `qwen3-vl-4b` because it is the most likely to fit and matches the small-model recommendation. The other models are available by changing `config.modelName` or service-level override.
7. **Concurrency**: Set `IMMICH_ANALYZE_MAX_CONCURRENT=2` as requested.
8. **Secrets**: Immich API key is stored in Bitwarden and consumed via ExternalSecret using the `bitwarden-fields` store and custom field `api_key`.
9. **No ingress/proxy entry**: immich-analyze is a background worker; no public web UI is needed. Only container probes use its local health port.
10. **Image tag**: Use `ghcr.io/timasoft/immich-analyze:main` with `pullPolicy: Always` because upstream publishes no versioned container tag. Add comment noting to pin once upstream publishes version tags.

## Changes

### 1. `charts/llama-swap/values.yaml` — MODIFY
Add three vision models under `config.models` and include them in the matrix.

Add under `config.models`:

```yaml
    qwen3-vl-4b:
      cmd: |
        ${server-cmd}
        ${threads}
        -hf unsloth/Qwen3-VL-4B-Instruct-GGUF:Q4_K_M
        --mmproj hf://unsloth/Qwen3-VL-4B-Instruct-GGUF/mmproj-F16.gguf
        -c 16384
      name: "Qwen3 VL 4B Instruct"
      description: "Vision-language model for Immich image analysis, Q4_K_M quant"
      proxy: http://localhost:${PORT}
      ttl: 0
      capabilities:
        in:
          - text
          - image
        out:
          - text

    qwen3-vl-8b:
      cmd: |
        ${server-cmd}
        ${threads}
        -hf unsloth/Qwen3-VL-8B-Instruct-GGUF:Q4_K_M
        --mmproj hf://unsloth/Qwen3-VL-8B-Instruct-GGUF/mmproj-F16.gguf
        -c 16384
      name: "Qwen3 VL 8B Instruct"
      description: "Vision-language model for Immich image analysis, Q4_K_M quant"
      proxy: http://localhost:${PORT}
      ttl: 0
      capabilities:
        in:
          - text
          - image
        out:
          - text

    qwen3-vl-30b-a3b:
      cmd: |
        ${server-cmd}
        ${threads}
        -hf unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF:Q4_K_M
        --mmproj hf://unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF/mmproj-F16.gguf
        ${moe}
        -c 16384
      name: "Qwen3 VL 30B A3B Instruct"
      description: "Vision-language MoE model for Immich image analysis, Q4_K_M quant, CPU-offloaded experts"
      proxy: http://localhost:${PORT}
      ttl: 0
      capabilities:
        in:
          - text
          - image
        out:
          - text
```

Add matrix vars:

```yaml
      vl4b: qwen3-vl-4b
      vl8b: qwen3-vl-8b
      vl30b: qwen3-vl-30b-a3b
```

Replace the existing `sets.main` expression with:

```yaml
      main: "(q27bq6 | q27bq8 | coderq6 | coderq8 | q35q6 | q35q8 | q35bf16 | q35b1m | q30q4 | q30q8 | q8bq4 | q8bq8 | katq4 | katq6 | katq8 | homegpu | vl4b | vl8b | vl30b) & homecpu"
```

### 2. `charts/immich-analyze/Chart.yaml` — CREATE

```yaml
apiVersion: v2
name: immich-analyze
description: AI-powered image description generator for Immich
type: application
version: 1.0.0
appVersion: "0.4.3"
dependencies:
  - name: app-template
    version: 5.0.1
    repository: https://bjw-s-labs.github.io/helm-charts/
```

### 3. `charts/immich-analyze/values.yaml` — CREATE

```yaml
bitwardenIds:
  immich-analyze: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

# App-level tunables; overridable from service values or custom-values.
config:
  # llama-swap model ID to use for image analysis.
  modelName: qwen3-vl-4b
  # Number of concurrent AI requests.
  maxConcurrent: "2"
  # combined = process existing library then keep monitoring for new assets.
  mode: combined
  # missing-ai = process assets that do not already have an [AI]...[/AI] block.
  overwritePolicy: missing-ai
  # Preserve human-written text outside [AI]...[/AI] blocks.
  preserveHuman: "true"
  # Poll interval for Immich API mode, seconds.
  apiPollInterval: "10"
  # Request timeout for AI calls, seconds.
  timeout: "300"
  # Health endpoint port inside the container.
  healthPort: "3000"

app-template:
  global:
    nameOverride: &chartName immich-analyze

  controllers:
    immich-analyze:
      annotations:
        reloader.stakater.com/auto: "true"
      containers:
        main:
          image:
            # Upstream currently publishes only rolling :main / :nightly tags.
            # Pin to a version tag if upstream starts publishing one.
            repository: ghcr.io/timasoft/immich-analyze
            tag: main
            pullPolicy: Always
          env:
            TZ: Etc/UTC
            IMMICH_ANALYZE_DATA_ACCESS_MODE: immich-api
            IMMICH_API_URL: http://home-immich-server:2283
            IMMICH_API_KEY:
              secretKeyRef:
                name: *chartName
                key: api_key
            IMMICH_ANALYZE_INTERFACE: llamacpp
            IMMICH_ANALYZE_HOSTS: "https://llama-cpp.{{ .Values.domain }}"
            IMMICH_ANALYZE_MODEL_NAME: "{{ .Values.config.modelName }}"
            IMMICH_ANALYZE_MODE: "{{ .Values.config.mode }}"
            IMMICH_ANALYZE_OVERWRITE_POLICY: "{{ .Values.config.overwritePolicy }}"
            IMMICH_ANALYZE_PRESERVE_HUMAN: "{{ .Values.config.preserveHuman }}"
            IMMICH_ANALYZE_MAX_CONCURRENT: "{{ .Values.config.maxConcurrent }}"
            IMMICH_ANALYZE_API_POLL_INTERVAL: "{{ .Values.config.apiPollInterval }}"
            IMMICH_ANALYZE_TIMEOUT: "{{ .Values.config.timeout }}"
            IMMICH_ANALYZE_HEALTH_PORT: "{{ .Values.config.healthPort }}"
            RUST_LOG: info
          probes:
            liveness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /health
                  port: 3000
                initialDelaySeconds: 30
                periodSeconds: 30
                timeoutSeconds: 10
                failureThreshold: 3
            readiness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /health
                  port: 3000
                initialDelaySeconds: 10
                periodSeconds: 10
                timeoutSeconds: 5
                failureThreshold: 3
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              memory: 1Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            runAsNonRoot: true
```

### 4. `charts/immich-analyze/templates/secret-immich-analyze.yaml` — CREATE

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: immich-analyze
spec:
  refreshInterval: 1h
  target:
    name: immich-analyze
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        api_key: "{{ `{{ .api_key }}` }}"
  data:
    - secretKey: api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "immich-analyze" }}'
        property: api_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 5. Generate chart lockfile
Run:

```bash
helm dependency update charts/immich-analyze
```

This creates `charts/immich-analyze/Chart.lock` and vendors `charts/immich-analyze/charts/app-template-5.0.1.tgz`.

### 6. `services/home/prod/values.yaml` — MODIFY
Add the new app under `charts:` near the existing `immich:` entry:

```yaml
  immich-analyze:
    namespace: default
    ServerSideApply: "true"
```

No `ingress.subdomains` entry is needed because the service is not user-facing.

### 7. `custom-values/home/prod-values.yaml` — MODIFY
Add the app-specific Bitwarden UUID block after the existing `immich:` block:

```yaml
immich-analyze:
  bitwardenIds:
    immich-analyze: REPLACE_WITH_REAL_BITWARDEN_ITEM_UUID
```

The real UUID must be inserted only in the private/custom-values layer after the user creates the Bitwarden item.

## Manual prerequisites for the user

### 1. Create the Immich API key in the Immich UI
1. Open the Immich web UI, e.g. `https://pictures.spencerslab.com`.
2. Click your user avatar in the top-right corner.
3. Open **Account Settings** / **User Settings**.
4. Go to **API Keys**.
5. Click **Create new API key**.
6. Name it something like `immich-analyze`.
7. Grant the permissions needed to read assets and update asset descriptions/metadata; if in doubt, use the broad/all permission option.
8. Copy the generated key immediately; Immich will not show it again.

### 2. Store the API key in Bitwarden
Create or choose a Bitwarden item for immich-analyze, then add a custom field:

- Field name: `api_key`
- Field value: the Immich API key

Then put that item UUID into `custom-values/home/prod-values.yaml` under:

```yaml
immich-analyze:
  bitwardenIds:
    immich-analyze: <item-uuid>
```

## Verification

1. Lint and template the new chart:

```bash
helm dependency update charts/immich-analyze
helm lint charts/immich-analyze
helm template immich-analyze charts/immich-analyze \
  --set domain=spencerslab.com \
  --set app-template.domain=spencerslab.com \
  --set bitwardenIds.immich-analyze=test-uuid \
  --set app-template.bitwardenIds.immich-analyze=test-uuid
```

Confirm:
- Deployment renders.
- ExternalSecret renders.
- `IMMICH_API_URL` is `http://home-immich-server:2283`.
- `IMMICH_ANALYZE_HOSTS` is `https://llama-cpp.spencerslab.com`.
- `IMMICH_ANALYZE_MAX_CONCURRENT` is `2`.
- No `OVERRIDE_VIA_CUSTOM_VALUES` or `OVERRIDE_VIA_APPSET` strings remain in rendered output.

2. Lint and template llama-swap:

```bash
helm lint charts/llama-swap
helm template llama-swap charts/llama-swap --set domain=spencerslab.com
```

Confirm the rendered `llama-swap-config` ConfigMap contains:
- `qwen3-vl-4b`
- `qwen3-vl-8b`
- `qwen3-vl-30b-a3b`
- matching `--mmproj hf://.../mmproj-F16.gguf` lines
- updated matrix set including `vl4b | vl8b | vl30b`

3. Integration grep:

```bash
grep -n "immich-analyze" services/home/prod/values.yaml custom-values/home/prod-values.yaml
grep -n "qwen3-vl" charts/llama-swap/values.yaml
```

4. After ArgoCD sync:
- `home-immich-analyze` Application is Healthy/Synced.
- `gpu-llama-swap` Application is Healthy/Synced.
- immich-analyze pod is Running.
- ExternalSecret is Ready and creates Secret `immich-analyze`.
- Pod logs show it can reach Immich API and llama-swap.
- Request `qwen3-vl-4b` from llama-swap and confirm model loads.
- Confirm at least one Immich asset receives an `[AI]...[/AI]` description block.

## Risks & open questions
1. **GPU VRAM**: The existing llama-swap values contain a comment referring to an 8GB card. If the GPU is still 8GB, `qwen3-vl-4b` is the realistic default. `qwen3-vl-8b` may be tight, and `qwen3-vl-30b-a3b` will rely heavily on CPU expert offload via `${moe}` and may be slow. If the GPU is 24GB+, all three are more comfortable.
2. **mmproj fetch syntax**: The plan uses `--mmproj hf://.../mmproj-F16.gguf`. If the deployed llama.cpp build does not accept `hf://` for `--mmproj`, fallback is to remove explicit `--mmproj` and test whether `-hf` auto-fetches the projector, or pre-download mmproj files into the models PVC and reference local paths.
3. **Model support in llama.cpp build**: `v240-vulkan-b10015` should be recent enough for Qwen3-VL, but verify by loading `qwen3-vl-4b` first.
4. **GPU contention**: llama-swap matrix allows one GPU model at a time plus the CPU home model. When immich-analyze loads a vision model, it may evict a currently loaded text model used by other services.
5. **Rolling image tag**: `ghcr.io/timasoft/immich-analyze:main` is mutable. This is accepted because no pinned container tags are published; revisit if upstream publishes versioned tags.
6. **Immich API key permissions**: If Immich key permissions are too narrow, analysis may read assets but fail to write descriptions. Create the key with sufficient metadata/update permissions.

## Implementation notes (2026-09-08)

- Implemented all planned file changes:
  - `charts/llama-swap/values.yaml`: added `qwen3-vl-4b`, `qwen3-vl-8b`, `qwen3-vl-30b-a3b`, matrix vars `vl4b`, `vl8b`, `vl30b`, and updated `sets.main`.
  - `charts/immich-analyze/`: created `Chart.yaml`, `values.yaml`, `templates/secret-immich-analyze.yaml`, and generated `Chart.lock` via `helm dependency update`.
  - `services/home/prod/values.yaml`: added `immich-analyze` under `charts:` with `namespace: default` and `ServerSideApply: "true"`.
  - `custom-values/home/prod-values.yaml`: added `immich-analyze.bitwardenIds.immich-analyze: 8ef66a15-3efb-4854-85b1-b4bf0030a214` (user-provided UUID).
- Deviation 1: moved the `config:` tunables under `app-template:` instead of top-level. The bjw-s app-template renders env values in the subchart scope, so top-level `{{ .Values.config.* }}` templates fail (`nil pointer`) during lint/template.
- Deviation 2: replaced `IMMICH_ANALYZE_HOSTS: "https://llama-cpp.{{ .Values.domain }}"` with `app-template.config.aiHosts: "https://llama-cpp.spencerslab.com"`. Live inspection of `gpu-searxng` showed `SEARXNG_BASE_URL: "https://"` because the appset only sets top-level `domain`, which is not visible inside the `app-template` subchart. Hardcoding matches existing repo precedent for cross-service hostnames and avoids a broken AI endpoint.
- Validation: `helm lint` passes for both charts; rendered `immich-analyze` manifests contain no `OVERRIDE_*`/`REPLACE_WITH` sentinels; rendered llama-swap ConfigMap contains all three Qwen3-VL models, mmproj lines, and updated matrix.
- Plan file renamed from epoch-based `.kilo/plans/1788830429537-add-immich-analyze.md` to repo convention `.agents/plans/2026-09-08-feat-add-immich-analyze.md` (`.kilo` is a symlink to `.agents`).
