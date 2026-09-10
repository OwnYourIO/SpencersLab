# Plan: MCP Servers v2 + Monitoring Updates (port from /home/coder/kubernetes f87e9d1..HEAD)

## Goal
Port the useful pieces of the kubernetes repo's recent commit range into SpencersLab:
fix the two broken ToolHive MCP servers, add read-only Grafana + Postgres + Renovate
MCP servers to `charts/hivetools`, improve `renovate.json`, add 3 Postgres Grafana
dashboards, pin the SearXNG image, add a pinned Coder workspace container (Ubuntu
26.04, no PowerBI/ACR), and bring the non-Windows external-Alloy host configs into
`services/monitoring/prod/`.

## Skills
Code agent must load (fresh session):
- `helm-chart-creation` — chart + service wiring, bitwardenIds conventions, validation
- `helm-bjw-s-chart` — app-template API (searxng chart edit)
- `container-creation` — new images under `containers/`, VERSION auto-bump, GHCR workflow
- `gitops-workflows` — ExternalSecret/Bitwarden patterns, ArgoCD sync verification
- `kubernetes-skill` — manifest authoring/review

## MCP Servers
- `kubernetes` — verify rollouts, pods, ExternalSecrets, rendered MCPServers on the live lab cluster
- `searxng` — web lookups (Docker Hub tags for searxng pin, grafana/mcp-grafana tag check, Ubuntu 26.04 default python check)

## Verified context
Recon performed against this repo (worktree == main) and the live lab cluster:

- `charts/hivetools/` (ToolHive operator 0.34.0, same CRD version as source repo) drives
  all MCPServers from `mcp:` in values via `templates/generic-mcpserver.yaml`
  (supports: image, transport, mcpPort, serviceAccount, oidcConfigRef{audience}, args,
  env, resources, secrets[{name,key,targetEnvName}], podTemplateSpec passthrough).
  Shared `MCPOIDCConfig/keycloak` (clientId `mcp`, realm via values). Existing
  ExternalSecret pattern: `templates/secret-github-mcp.yaml` (SecretStore
  `bitwarden-fields`) and gpu-side `bitwarden-login` SecretStore for LOGIN items
  (username/password properties) — see `services/gpu/prod/templates/pg-coder-secret.yaml`.
- bitwardenIds flow: real UUIDs live in the ArgoCD cluster-secret annotation
  `services.gpu.bitwardenIds`; values files carry `OVERRIDE_VIA_CLUSTER_ANNOTATION` /
  `OVERRIDE_VIA_CUSTOM_VALUES` placeholders (charts also keep placeholder blocks, e.g.
  `charts/n8n/values.yaml`).
- Live cluster (gpu): `searxng-0` ImagePullBackOff 52d — STS still
  `ghcr.io/ihor-sokoliuk/mcp-searxng:v1.11.1` (nonexistent) although main has
  `isokoliuk/mcp-searxng:1.13.0` since commit b9084304 (Aug 5) — never rolled out.
  STS env also points at nonexistent `searxng.default.svc`; real backend Service is
  `gpu-searxng` (default ns). `firecrawl-0` ImagePullBackOff: untagged
  `ghcr.io/mendableai/firecrawl-mcp`; verified no public image exists at
  ghcr.io/mendableai/firecrawl-mcp, ghcr.io/firecrawl/firecrawl-mcp, or Docker Hub.
  Docker Hub `isokoliuk/mcp-searxng` tags verified: 1.13.0 exists (also 2.1.0 latest).
- 6 CNPG clusters on gpu: pg-coder, pg-flowise, pg-langflow, pg-n8n, pg-open-webui,
  pg-supabase; app DBs: coder, flowise, langflow, n8n, open-webui. All have
  `monitoring.enablePodMonitor: true`. CNPG managed-role precedent exists
  (`charts/immich/templates/pg-immich.yaml` uses `managed.roles[].passwordSecret`).
  hivetools runs only on gpu → only these DBs are reachable.
- Grafana: monitoring category (grafana chart 10.1.0, Keycloak OAuth, root URL
  `https://graphs.spencerslab.com`); monitoring ingress adds no auth middleware →
  Grafana SA bearer tokens reach Grafana directly through the public ingress.
  hivetools (gpu cluster) cannot reach monitoring-cluster Services → use public URL.
- Lab Grafana already has the official CloudNative-PG dashboard (monitoring values
  `dashboards.data`). User chose to add the 3 postgres_exporter-style dashboards anyway.
- `charts/searxng/values.yaml` floats `searxng/searxng:latest` (running fine as
  gpu-searxng); source repo pins immutable date-commit tags.
- `services/monitoring/prod/` is itself a Helm chart (Chart.yaml + templates +
  values) deployed as the `monitoring` app; raw templates land there directly.
- k8s-monitoring remote-writes to `https://prometheus.spencerslab.com/api/v1/write`
  and `https://loki.spencerslab.com/loki/api/v1/push` with NO auth today → the
  external-Alloy config is ported without OAuth (matches current posture; OAuth
  hardening is future work).
- Containers build pattern: `containers/<name>/{Dockerfile,VERSION}` +
  `.github/workflows/docker-build.yaml` (REGISTRY=ghcr.io → ghcr.io/ownyourio/<name>).
- Renovate runs on this repo (merged renovate/* PRs exist); config is root
  `renovate.json` (GitHub app style; no self-hosted runner).

## Design decisions
1. **Broken MCPs first (workstream A)** — the searxng fix already merged to main was
   never rolled out; correct SEARXNG_URL (`gpu-searxng`) and force the rollout.
   Firecrawl has no public image anywhere → disable it (documented in values) rather
   than build a container now.
2. **Grafana MCP (B)** — same shape as source repo: `grafana/mcp-grafana` with
   `--disable-write` + Viewer service-account token. Read-only enforced twice
   (flag + Viewer role). Token via Bitwarden LOGIN item (password field) →
   ExternalSecret → MCPServer secret. GRAFANA_URL = `https://graphs.spencerslab.com`
   (cross-cluster; SA bearer token authenticates at Grafana regardless of OAuth).
   `--allowed-hosts "*"` required (ToolHive proxy rewrites Host; DNS-rebinding check
   would 403 otherwise — lesson from source repo).
3. **Postgres MCP (C)** — `crystaldba/postgres-mcp:0.3.0` (FINAL upstream release;
   pin forever, revisit quarterly), `--access-mode=restricted` + genuinely read-only
   CNPG role as the real boundary: managed role `mcp` with `inRoles: [pg_read_all_data]`,
   password from Bitwarden via `passwordSecret` (lab precedent: immich). DATABASE_URI
   composed by an ESO-templated ExternalSecret (URL-escaped password chain copied from
   source repo) with deterministic in-cluster host `pg-<name>-rw.default.svc.cluster.local:5432`
   and explicit app dbname. Scope per user: all gpu clusters EXCEPT pg-supabase (5 servers).
4. **Renovate MCP (D)** — single custom container `containers/renovate-mcp`
   (node:24-bookworm-slim + git + `renovate-mcp@1.4.9`, uid 1000) built to GHCR; the
   same image serves as clone initContainer (git-clones OwnYourIO/SpencersLab using the
   EXISTING `github-mcp` PAT secret — no new secret plumbing). stdio transport like
   other lab stdio servers; no proxyMode/sessionAffinity fields needed (lab template
   doesn't render them; existing stdio servers work without).
5. **Renovate config (E)** — port PR hygiene + the `image:` line custom manager scoped
   to chart/service templates (values.yaml images are intentionally left to the
   built-in helm-values manager to avoid duplicate PRs).
6. **Dashboards (F)** — add gnetId 18316/9628/24298 to `dashboards.data` with CORRECT
   renovate depName comments (source repo had copy-paste "Container Log Dashboard").
7. **SearXNG pin (G)** — replace `tag: latest` with a verified immutable tag.
8. **Coder workspace image (H)** — `containers/coder-workspace`: port of source
   Dockerfile pinned to **Ubuntu 26.04** per user, with PowerBI (pbir-utils,
   libssl3t64) and all ADO/ACR references dropped; restricted-PSS design kept.
   Wiring the image into a Coder template is a platform-side task, out of scope.
9. **External Alloy (I)** — only the non-Windows, non-postgres "standard host" config
   + setup doc, adapted to spencerslab.com endpoints, no OAuth (see context). Windows
   and postgres variants dropped (lab postgres is in-cluster CNPG).

## Changes

### Workstream A — fix broken MCP servers
1. `charts/hivetools/values.yaml` — [MODIFY]
   - `mcp.searxng.podTemplateSpec.spec.containers[0].env` SEARXNG_URL:
     `http://searxng.default.svc.cluster.local:8080` → `http://gpu-searxng.default.svc.cluster.local:8080`
   - `mcp.firecrawl`: set `enabled: false` and add comment: no public image exists
     (ghcr.io/mendableai/firecrawl-mcp is untagged/private; nothing on Docker Hub);
     rebuild as a custom container under containers/ if wanted later.
   - Optional small fix in `templates/generic-mcpserver.yaml`: the proxyPort condition
     reads `{{- if $config.targetPort }}` but prints `proxyPort` — change condition to
     `{{- if $config.proxyPort }}`.

### Workstream B — Grafana MCP server
2. `charts/hivetools/templates/secret-grafana-mcp-token.yaml` — [CREATE]
```yaml
# Grafana service-account bearer token (Viewer) for the grafana MCP server.
# Bitwarden LOGIN item (password field = SA token) -> ExternalSecret -> Secret
# "grafana-mcp-token" -> MCPServer secrets[] -> GRAFANA_SERVICE_ACCOUNT_TOKEN.
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: grafana-mcp-token
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: grafana-mcp-token
    creationPolicy: Owner
    deletionPolicy: Delete   # token Secret must go when the ExternalSecret is pruned
  data:
    - secretKey: token
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "grafana-mcp-token" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```
3. `charts/hivetools/values.yaml` — [MODIFY] add to `bitwardenIds:`
   `grafana-mcp-token: OVERRIDE_VIA_CLUSTER_ANNOTATION`; add under `mcp:`:
```yaml
  # Grafana MCP Server - read-only dashboards/Prometheus/Loki/alerting access.
  # Read-only enforced twice: --disable-write (server side) + Viewer-only SA token.
  # GRAFANA_URL is the public ingress (monitoring stack lives on another cluster);
  # the SA bearer token authenticates at Grafana regardless of the Keycloak OAuth.
  # Repo: github.com/grafana/mcp-grafana
  grafana:
    enabled: true
    image: grafana/mcp-grafana:1.3.0
    transport: streamable-http
    mcpPort: 8000
    oidc:
      audience: grafana
    # --allowed-hosts '*' is REQUIRED: mcp-grafana validates Host/Origin
    # (DNS-rebinding protection) and the ToolHive proxy rewrites Host to the
    # backend ClusterIP, which would otherwise be rejected with 403.
    args:
      - "--transport"
      - "streamable-http"
      - "--address"
      - "0.0.0.0:8000"
      - "--allowed-hosts"
      - "*"
      - "--disable-write"
    env:
      - name: GRAFANA_URL
        value: https://graphs.spencerslab.com
    secrets:
      - name: grafana-mcp-token
        key: token
        targetEnvName: GRAFANA_SERVICE_ACCOUNT_TOKEN
    resources:
      limits:
        cpu: '200m'
        memory: '256Mi'
      requests:
        cpu: '50m'
        memory: '64Mi'
    podTemplateSpec:
      spec:
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          fsGroup: 1000
        containers:
          - name: mcp
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop: [ALL]
              readOnlyRootFilesystem: true
            volumeMounts:
              - mountPath: /tmp
                name: tmp
        volumes:
          - name: tmp
            emptyDir: {}
```

### Workstream C — Postgres MCP servers (5 DBs, no pg-supabase)
4. CNPG managed read-only role — [MODIFY] these 5 files, adding the same block
   (`charts/flowise/templates/pg-flowise.yaml`, `charts/langflow/templates/pg-langflow.yaml`,
   `charts/n8n/templates/pg-n8n.yaml`, `services/gpu/prod/templates/pg-coder.yaml`,
   `services/gpu/prod/templates/pg-open-webui.yaml`):
```yaml
  managed:
    roles:
      # Read-only role for the postgres-<name> ToolHive MCP server.
      # pg_read_all_data = read everything, write nothing (PG14+ predefined role).
      # Password lives in Bitwarden (pg-<name>-mcp-secret ExternalSecret).
      - name: mcp
        ensure: present
        login: true
        inherit: true
        inRoles:
          - pg_read_all_data
        connectionLimit: 5
        passwordSecret:
          name: pg-<name>-mcp-secret
```
   (none of the 5 currently has a `managed:` block — add fresh; for pg-open-webui
   verify spec first since it lives in the gpu service templates)
5. Role-password ExternalSecrets — [CREATE] 5 files, one per cluster, next to the
   existing app secret templates (`charts/flowise/templates/pg-flowise-mcp-secret.yaml`,
   `charts/langflow/templates/pg-langflow-mcp-secret.yaml`,
   `charts/n8n/templates/pg-n8n-mcp-secret.yaml`,
   `services/gpu/prod/templates/pg-coder-mcp-secret.yaml`,
   `services/gpu/prod/templates/pg-open-webui-mcp-secret.yaml`). Pattern = existing
   `secret-pg-n8n.yaml` / `pg-coder-secret.yaml` (SecretStore `bitwarden-login`,
   username+password properties), with remoteRef key
   `{{ index .Values "bitwardenIds" "<key>" }}` where `<key>` is:
   `mcp-pg-coder`, `mcp-pg-flowise`, `mcp-pg-langflow`, `mcp-pg-n8n`, `mcp-pg-open-webui`;
   target secret name `pg-<name>-mcp-secret`.
6. `charts/hivetools/templates/secret-postgres-mcp.yaml` — [CREATE] (adapted from
   source repo `postgres-mcp.yaml` ExternalSecret half; lab bitwardenIds indirection):
```yaml
{{- /*
Postgres MCP credentials: one ExternalSecret per entry in .Values.postgresMcp.databases.
Composes DATABASE_URI from the Bitwarden LOGIN item (username/password) plus the
deterministic in-cluster CNPG host and the app database name. Password is URL-escaped
(escape chain copied from the source repo). The matching read-only role `mcp` is
declared in each CNPG Cluster spec (pg_read_all_data).
*/}}
{{- range .Values.postgresMcp.databases }}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: postgres-mcp-{{ .name }}
  namespace: {{ $.Values.namespace | default "default" }}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: postgres-mcp-{{ .name }}
    creationPolicy: Owner
    deletionPolicy: Delete
    template:
      engineVersion: v2
      data:
        # Inner {{ "{{ ... }}" }} braces are ESO template syntax, escaped from Helm.
        DATABASE_URI: "postgresql://{{ `{{ .username }}` }}:{{ `{{ .password | replace \"%\" \"%25\" | replace \"@\" \"%40\" | replace \":\" \"%3A\" | replace \"/\" \"%2F\" | replace \"#\" \"%23\" | replace \"?\" \"%3F\" | replace \"&\" \"%26\" | replace \"=\" \"%3D\" | replace \"+\" \"%2B\" | replace \" \" \"%20\" | replace \"$\" \"%24\" }}` }}@pg-{{ .name }}-rw.{{ $.Values.namespace | default "default" }}.svc.cluster.local:5432/{{ .database }}"
  data:
    - secretKey: username
      remoteRef:
        key: '{{ index $.Values "bitwardenIds" .bitwardenIdKey }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: password
      remoteRef:
        key: '{{ index $.Values "bitwardenIds" .bitwardenIdKey }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
{{- end }}
```
7. `charts/hivetools/values.yaml` — [MODIFY]
   - add to `bitwardenIds:` (all `OVERRIDE_VIA_CLUSTER_ANNOTATION`):
     `mcp-pg-coder`, `mcp-pg-flowise`, `mcp-pg-langflow`, `mcp-pg-n8n`, `mcp-pg-open-webui`
   - add top-level block:
```yaml
# Postgres MCP servers (crystaldba/postgres-mcp, read-only). One ExternalSecret per
# entry is rendered by templates/secret-postgres-mcp.yaml; the MCPServer entries are
# mcp.postgres-<name> below. Each Bitwarden LOGIN item (username=mcp) backs the CNPG
# managed role password AND the composed DATABASE_URI. Host is deterministic:
# pg-<name>-rw.default.svc.cluster.local:5432. Adding a database = entry here +
# bitwardenIds key + mcp.postgres-<name> block + CNPG managed role in the Cluster spec.
postgresMcp:
  databases:
    - name: coder
      bitwardenIdKey: mcp-pg-coder
      database: coder
    - name: flowise
      bitwardenIdKey: mcp-pg-flowise
      database: flowise
    - name: langflow
      bitwardenIdKey: mcp-pg-langflow
      database: langflow
    - name: n8n
      bitwardenIdKey: mcp-pg-n8n
      database: n8n
    - name: open-webui
      bitwardenIdKey: mcp-pg-open-webui
      database: open-webui
```
   - add 5 entries under `mcp:` — identical shape, one per name (sketch shows one):
```yaml
  # Postgres MCP - read-only SQL access to the pg-<name> CNPG cluster (app db: <db>).
  # crystaldba/postgres-mcp 0.3.0 is the FINAL upstream release — pin, don't float.
  # Security: --access-mode=restricted (app layer) + pg_read_all_data role (real boundary).
  postgres-coder:
    enabled: true
    image: crystaldba/postgres-mcp:0.3.0
    transport: stdio
    mcpPort: 8080
    oidc:
      audience: postgres-coder
    args:
      - "--access-mode=restricted"
    secrets:
      - name: postgres-mcp-coder
        key: DATABASE_URI
        targetEnvName: DATABASE_URI
    resources:
      limits:
        cpu: '200m'
        memory: '512Mi'
      requests:
        cpu: '50m'
        memory: '128Mi'
    podTemplateSpec:
      spec:
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          fsGroup: 1000
        containers:
          - name: mcp
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop: [ALL]
              readOnlyRootFilesystem: true
            volumeMounts:
              - name: tmp
                mountPath: /tmp
        volumes:
          - name: tmp
            emptyDir: {}
```
   (repeat for postgres-flowise/langflow/n8n/open-webui with matching names/audiences)
8. `services/gpu/prod/values.yaml` — [MODIFY] add to the `bitwardenIds:` placeholder
   block: `grafana-mcp-token`, `mcp-pg-coder`, `mcp-pg-flowise`, `mcp-pg-langflow`,
   `mcp-pg-n8n`, `mcp-pg-open-webui` — all `OVERRIDE_VIA_CLUSTER_ANNOTATION`.

### Workstream D — Renovate MCP server
9. `containers/renovate-mcp/Dockerfile` — [CREATE] copy of source repo
   `/home/coder/kubernetes/containers/renovate-mcp/Dockerfile` with: node base digest
   re-resolved at implementation time (multi-arch index), keep git + ca-certificates,
   keep `npm install -g renovate-mcp@1.4.9` (add renovate comment annotation per
   container-creation skill so renovate can bump it), keep USER 1000:1000 +
   ENTRYPOINT ["renovate-mcp"]. No ACR references.
10. `containers/renovate-mcp/VERSION` — [CREATE] `0.0.1`
11. `charts/hivetools/values.yaml` — [MODIFY] add under `mcp:`:
```yaml
  # Renovate MCP - design-time Renovate config tooling (validate/dry-run renovate.json).
  # The pod init-clones this (private) repo from GitHub using the existing github-mcp
  # PAT secret; the mcp container itself needs no GitHub auth. stdio transport is
  # single-connection by design (one session at a time).
  renovate:
    enabled: true
    image: ghcr.io/ownyourio/renovate-mcp:0.0.1
    transport: stdio
    mcpPort: 8080
    oidc:
      audience: renovate
    env:
      - name: RENOVATE_MCP_REQUIRE_CLI
        value: "true"
      - name: RENOVATE_BASE_DIR
        value: /cache
      - name: HOME
        value: /tmp   # writable path under uid 1000 / readOnlyRootFilesystem
    resources:
      limits:
        cpu: '2'
        memory: '4Gi'
      requests:
        cpu: '500m'
        memory: '1Gi'
    podTemplateSpec:
      spec:
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          runAsGroup: 1000
          fsGroup: 1000
        initContainers:
          - name: clone
            image: ghcr.io/ownyourio/renovate-mcp:0.0.1  # same image ships git
            env:
              - name: HOME
                value: /tmp
              - name: GITHUB_PERSONAL_ACCESS_TOKEN
                valueFrom:
                  secretKeyRef:
                    name: github-mcp
                    key: GITHUB_PERSONAL_ACCESS_TOKEN
            command: ["/bin/sh", "-c"]
            args:
              - |
                git clone --depth 1 --branch main \
                  "https://x-access-token:${GITHUB_PERSONAL_ACCESS_TOKEN}@github.com/OwnYourIO/SpencersLab.git" \
                  /workspace/SpencersLab
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop: [ALL]
              readOnlyRootFilesystem: true
              runAsNonRoot: true
              runAsUser: 1000
              runAsGroup: 1000
            volumeMounts:
              - mountPath: /workspace
                name: workspace
              - mountPath: /tmp
                name: tmp
        containers:
          - name: mcp
            resources:   # Renovate dry-runs are CPU/memory heavy
              requests:
                cpu: '500m'
                memory: '1Gi'
              limits:
                cpu: '2'
                memory: '4Gi'
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop: [ALL]
              readOnlyRootFilesystem: true
              runAsNonRoot: true
              runAsUser: 1000
              runAsGroup: 1000
            volumeMounts:
              - mountPath: /workspace
                name: workspace
              - mountPath: /tmp
                name: tmp
              - mountPath: /cache
                name: cache
        volumes:
          - name: workspace
            emptyDir: {}
          - name: tmp
            emptyDir: {}
          - name: cache
            emptyDir: {}
```
    Verify after sync that ToolHive preserves initContainers through its pod merge;
    if the PAT secret isn't mounted into the init container by the merge, fall back to
    referencing the secret via `envFrom.secretRef` on the initContainer.

### Workstream E — Renovate config improvements
12. `renovate.json` — [MODIFY]
    - top level: add `"labels": ["dependencies"]`, `"prHourlyLimit": 2`,
      `"prConcurrentLimit": 5`, `"semanticCommits": "disabled"`
    - add custom manager (JSON form of the source repo's; appset path adapted to this
      repo's `services/<category>/<env>/templates/` layout):
```json
{
  "customType": "regex",
  "description": "Plain image: lines in chart/service templates (ToolHive MCPServer specs, raw Deployments). Helm-templated and commented lines don't match; untagged/latest images yield no updates.",
  "managerFilePatterns": [
    "/(^|/)charts/[^/]+/templates/[^/]+\\.ya?ml$/",
    "/(^|/)services/[^/]+/[^/]+/templates/[^/]+\\.ya?ml$/"
  ],
  "matchStrings": [
    "(^|\\n)[ \\t]*image:[ \\t]+(?<depName>[A-Za-z0-9._/-]+):(?<currentValue>[A-Za-z0-9._-]+)"
  ],
  "datasourceTemplate": "docker"
}
```
    - do NOT add the azure-pipelines manager, workload-identity-webhook, renovate-mcp
      npm, or pipx managers from the source config (Azure-specific or covered by
      existing lab managers). The npm renovate-mcp manager may be added later pointing
      at `containers/renovate-mcp/Dockerfile` if the default dockerfile manager doesn't
      pick up the `npm install -g` line.

### Workstream F — Postgres Grafana dashboards
13. `services/monitoring/prod/values.yaml` — [MODIFY] under `grafana.dashboards.data:`
    (existing CNPG dashboard stays; fix source repo's copy-paste depNames):
```yaml
      pg-overview:
        # renovate: depName="PostgreSQL Overview"
        gnetId: 18316
        revision: 1
        datasource: Prometheus
      postgresql-database:
        # renovate: depName="PostgreSQL Database"
        gnetId: 9628
        revision: 8
        datasource: Prometheus
      postgresql-monitoring-dashboard:
        # renovate: depName="PostgreSQL Monitoring Dashboard"
        gnetId: 24298
        revision: 11
        datasource: Prometheus
```

### Workstream G — pin SearXNG backend image
14. `charts/searxng/values.yaml` — [MODIFY] `tag: latest` → verified current immutable
    tag. Query Docker Hub (`searxng/searxng` tags) at implementation time; prefer the
    date-commit form (e.g. `2026.9.4-15b0c8ef3` style used by the source repo) over
    bare date tags; bump `appVersion` in `charts/searxng/Chart.yaml` to match.

### Workstream H — Coder workspace container (Ubuntu 26.04, no PowerBI/ACR)
15. `containers/coder-workspace/Dockerfile` — [CREATE] adapted from source repo
    `/home/coder/kubernetes/containers/coder/Dockerfile`:
    - `FROM ubuntu:26.04@sha256:<resolve current multi-arch digest at implementation>`
    - DROP: `pbir-utils` pipx install, `libssl3t64` apt package, every ADO/ACR/
      aerofarms comment or reference, the `pbir` PATH bashrc entry
    - KEEP: restricted-PSS design (uid/gid 1000, no sudo, runtime writes to $HOME//tmp),
      git-core PPA + git-lfs, Node.js LTS with strict npm version check (re-verify the
      bundled npm version for the chosen LTS), pipx installed via pip (not apt),
      XDG/TMPDIR steering, no ENTRYPOINT (Coder template supplies bootstrap)
    - VERIFY during implementation (searxng/web search): Ubuntu 26.04's default
      python3 version. If it is already 3.14+, drop the deadsnakes PPA and the
      update-alternatives dance entirely (install pipx with the distro python); if it
      is older, keep the deadsnakes flow adapted from the source Dockerfile. Keep the
      "apt tooling must precede python switch" ordering constraint if the switch stays.
16. `containers/coder-workspace/VERSION` — [CREATE] `0.0.1`
    (Image becomes ghcr.io/ownyourio/coder-workspace via docker-build.yaml. Updating
    the Coder workspace template to use it is a manual platform-side step, out of scope.)

### Workstream I — external Alloy host configs (non-Windows)
17. `services/monitoring/prod/templates/configmap-alloy-external-config.yaml` — [CREATE]
    Port of source repo `configmap-alloy-external-config.yaml` (standard hosts only) with:
    - endpoints: `https://prometheus.spencerslab.com/api/v1/write` and
      `https://loki.spencerslab.com/loki/api/v1/push` (same destinations as
      charts/k8s-monitoring)
    - NO oauth2 blocks (lab remote-write is unauthenticated today; add Keycloak
      client-credentials later if/when the ingress enforces oidc-m2m)
    - keep: hostname identity, unix node exporter with systemd collector, 60s scrape,
      node metric allowlist — align it with charts/k8s-monitoring node-exporter
      includeMetrics (node_cpu_seconds_total, node_memory_.*, node_filesystem_.*,
      node_disk_.*, node_network_.*, node_load.*) plus node_time_seconds,
      node_boot_time_seconds, node_uname_info, node_context_switches_total, up
    - keep journald source (12h max_age, unit/level relabel) and /var/log file tailing
    - external_labels: instance=hostname, cluster=sys.env("CLUSTER"), job="integrations/unix"
18. `services/monitoring/prod/templates/configmap-alloy-external-setup.yaml` — [CREATE]
    Port of source repo `configmap-alloy-external-setup.yaml` adapted: namespace
    `default` (this chart's ns), no Keycloak env — the generated env file carries only
    `CLUSTER=<label>`; keep the backup-before-write behavior for existing configs and
    the paste-friendly one-liner structure. Drop the PostgreSQL-host step entirely.
    Drop all Windows variants (per user scope).

## Manual steps (user, outside the repo — do after merge, before/with sync)
1. Grafana (`graphs.spencerslab.com`): Service Accounts → create account `mcp` with
   **Viewer** role → generate token → Bitwarden LOGIN item `grafana-mcp-token`
   (password field = token).
2. Bitwarden LOGIN items (username `mcp`, generated password): `mcp-pg-coder`,
   `mcp-pg-flowise`, `mcp-pg-langflow`, `mcp-pg-n8n`, `mcp-pg-open-webui`. Use the
   SAME passwords when CNPG applies the roles (they flow automatically via the
   pg-*-mcp-secret ExternalSecrets).
3. ArgoCD gpu cluster secret: add to annotation `services.gpu.bitwardenIds`:
   `grafana-mcp-token`, `mcp-pg-coder`, `mcp-pg-flowise`, `mcp-pg-langflow`,
   `mcp-pg-n8n`, `mcp-pg-open-webui` → the 6 UUIDs.
4. Keycloak (login.spencerslab.com, realm SpencersLab): extend the `mcp` client's
   audience mapping with `grafana`, `postgres-coder`, `postgres-flowise`,
   `postgres-langflow`, `postgres-n8n`, `postgres-open-webui`, `renovate` (same
   mechanism used for the existing server audiences).
5. Sync the affected ArgoCD apps after merge (gpu service apps incl. hivetools,
   flowise, langflow, n8n; monitoring app). If gpu-hivetools shows Synced but the
   searxng STS still runs the old image, investigate ToolHive operator reconciliation
   (operator logs; it has 123 restarts) before force-recreating anything.

## Verification
1. Render checks (hard rule): `helm lint` + `helm template` for `charts/hivetools`
   (set dummy bitwardenIds/domain/keycloak.realm), `charts/searxng`, `charts/n8n`,
   `charts/flowise`, `charts/langflow`, and `helm template services/gpu/prod` +
   `services/monitoring/prod` with dummy values. All must pass.
2. `renovate.json` must stay valid JSON (`python3 -m json.tool renovate.json`).
3. Post-merge, on the live cluster (kubernetes MCP):
   - `searxng-0` Running with `isokoliuk/mcp-searxng:1.13.0` and SEARXNG_URL
     `gpu-searxng`; firecrawl resources pruned/gone; new pods Running:
     `grafana-*`, `postgres-{coder,flowise,langflow,n8n,open-webui}-*`, `renovate-*`
     (each = toolhive STS pod + proxy deployment).
   - ExternalSecrets `grafana-mcp-token`, `postgres-mcp-*`, `pg-*-mcp-secret` Ready;
     CNPG clusters show role `mcp` (check cluster status / no role-sync errors in
     CNPG operator logs).
   - Smoke tests through the MCP ingress (see charts/hivetools/templates/generic-mcp-ingress.yaml
     for host pattern): grafana server lists tools and has NO write tools; one postgres
     server answers a simple `SELECT` in its app db (e.g. n8n); renovate server can
     `validate` the cloned repo's renovate.json.
4. Grafana: 3 new dashboards appear in the Data folder (may render empty until a
   postgres_exporter exists — accepted by user). Existing CNPG dashboard shows data.
5. Renovate: watch the first run after merge — expect image-update PRs for template
   `image:` lines and NO duplicate PRs for values.yaml images.
6. ConfigMaps: `kubectl -n default get cm alloy-external-config alloy-external-setup`
   exist after monitoring app sync (on the monitoring cluster).

## Risks & open questions
- **Stale searxng rollout root cause unknown**: the Aug 5 image fix never reached the
  cluster. If ArgoCD was synced all along, the ToolHive operator (123 restarts) may
  not be reconciling MCPServer→STS changes; the plan's sync step must confirm which.
- **ghcr.io/ownyourio pull access**: renovate-mcp image must be pullable by ToolHive
  pods. wekan-mcp precedent exists; if the registry package is private, add an
  imagePullSecret to the renovate podTemplateSpec.
- **crystaldba/postgres-mcp is unmaintained** (0.3.0 final): pinned deliberately;
  revisit quarterly per source-repo guidance.
- **pg_read_all_data exposes all data read-only to agents** — accepted posture (same
  as source repo); the role boundary is what makes restricted mode safe.
- **Ubuntu 26.04 python/node specifics** for the coder image are verified at
  implementation time, not now; the Dockerfile adaptation depends on that check.
- **External Alloy endpoints are unauthenticated** (matches current lab posture).
  Anyone who can reach prometheus/loki.spencerslab.com can write; Keycloak oidc-m2m
  hardening is future work for both in-cluster and external writers.
- **renovate image manager overlap**: if the built-in helm-values manager already
  covers `image:` strings in values.yaml, the new custom manager is scoped to
  templates only and won't duplicate; verify in the first PR cycle.
- Coder template wiring (using the new workspace image) is out of scope — user action.
