# Chart Templates — Custom vs External, Chart.yaml, values.yaml, Template Bodies

Reference material for the `helm-chart-creation` skill. Read the sections you
need; don't load this whole file upfront.

## Custom vs external chart (critical decision)

**Before implementing anything, decide:** is this a custom chart or an external
chart?

```
Is there an official Helm chart?
├─ NO  → Create custom chart (charts/<name>/)
└─ YES → Use external chart (entry under charts: in the service values.yaml)
```

### Path 1: Custom chart (`charts/` folder)

When no official chart exists:

1. `mkdir -p charts/<service>/templates`
2. Create `Chart.yaml` (pattern below) — name, `version: 1.0.0` (initial only;
   `release.yaml` auto-bumps patch on every merge to main and chart-releaser
   tags `<chart>-<version>` — never bump it by hand), `appVersion`
   (latest from Docker Hub), app-template dependency at the repo-standard
   version (check an existing chart; currently `5.0.1`).
3. Create `values.yaml` from the template below — inject service-specific env
   vars, preserve standard security contexts and resource limits, modify image
   repository/tag/ports.
4. Create templates as needed: `secret-<service>.yaml` ALWAYS;
   `pg-<service>.yaml` + `secret-db-<service>.yaml` if PostgreSQL;
   `pvc-<service>-default.yaml` if persistent storage.
5. Wire the service trio (ApplicationSet `charts:` entry, proxy entry,
   custom-values entry) — see `values-and-appset.md`.

### Path 2: External chart (no `charts/` directory)

When an official/maintained chart exists, there are two wiring mechanisms —
follow the pattern already used in the target category:

1. **Umbrella dependency** — add to `services/<category>/prod/Chart.yaml`
   dependencies (name/version/repository, renovate picks up bumps), then
   configure under a top-level `<name>:` key in the service values.yaml. Used
   for e.g. mosquitto, wekan, cloudnative-pg, and the published
   ownyourio.github.io charts.
2. **`charts:` key entry** — add to `services/<category>/prod/values.yaml`:

   ```yaml
   charts:
     <chart-name>:
       version: <version> # renovate: datasource=helm registryUrl=<repo-url>
       repository: <repo-url>
       namespace: default
       ServerSideApply: "true"
   ```

   Rendered as its own Application by `charts/base/templates/appset-charts.yaml`.

Either way:

- Chart-specific configuration goes under a top-level `<chart-name>:` key in
  the service values.yaml. Disable the chart's own ingress
  (`ingress.enabled: false`) — SpencersLab routes via its own proxy config.
- Service-level resources (PG clusters, ExternalSecrets, PVCs, ConfigMaps) go
  in `services/<category>/prod/templates/` if needed (example:
  `services/home/prod/templates/pg-paperless.yaml`).
- Add the proxy entry (`ingress.subdomains`) in the same values.yaml.

### How the two deployment mechanisms compare

| Aspect | Umbrella dependency | `charts:` key entry |
|---|---|---|
| Declared in | `services/<category>/prod/Chart.yaml` | `services/<category>/prod/values.yaml` |
| Rendered by | the service chart itself (`templates/appset.yaml` deploys it) | `charts/base/templates/appset-charts.yaml` (one Application per entry) |
| Source | any Helm repo; app-template aliases; published ownyourio charts | git path `charts/<name>` (no `version:`) or Helm repo (with `version:` + `repository:`) |
| Version bump | renovate via Chart.yaml | renovate via inline `# renovate:` comment |
| Config location | top-level `<alias>:` key in service values.yaml | top-level `<appName>:` key, injected per-Application |

Notes:

- Local `charts/` charts deploy via the `charts:` key with the version
  commented out (`# version: ... # renovate: datasource=helm
  registryUrl=https://ownyourio.github.io/SpencersLab/`) — the commented line
  keeps renovate tracking the published chart while the appset uses the git
  path source from `main`.
- The appset template branches on `hasKey . "version"` to pick Helm-repo vs
  git-path sources.
- When unsure which mechanism to use, match what the target category already
  does for similar services.

## Chart.yaml pattern

```yaml
apiVersion: v2
name: <service-name>
version: 1.0.0  # initial only — release.yaml bumps patch on every merge to main
appVersion: <latest-version>  # research from Docker Hub
dependencies:
- name: app-template
  version: 5.0.1  # check latest stable / an existing chart — don't blindly copy
  repository: https://bjw-s-labs.github.io/helm-charts/
```

Then `helm dependency update charts/<service>` to generate `Chart.lock`.

## values.yaml — full single-container template

```yaml
bitwardenIds:
  <service-name>: OVERRIDE_VIA_CUSTOM_VALUES
  <service-name>-db: OVERRIDE_VIA_CUSTOM_VALUES  # only if database

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName <service-name>

  controllers:
    <service-name>:
      annotations:
        reloader.stakater.com/auto: "true"
      containers:
        main:
          image:
            repository: <docker-image>
            tag: <version>
          env:
            # RESEARCH: service-specific environment variables
            TZ: Etc/UTC
          envFrom:
            - secretRef:
                name: *chartName
          probes:
            liveness:
              enabled: true
            readiness:
              enabled: true
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              memory: 2Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  service:
    <service-name>:
      controller: *chartName
      ports:
        http:
          port: <app-port>

  persistence:
    config:
      existingClaim: *chartName
```

### Redis sidecar

Add a second container alongside `main`; the app connects via
`localhost:6379` (same pod):

```yaml
containers:
  main:
    # ... main app container above ...
  redis:
    image:
      repository: redis
      tag: 8.2.0
    resources:
      requests:
        cpu: 10m
        memory: 50Mi
      limits:
        memory: 256Mi
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
```

### Complex multi-container layout (Supabase-style)

```yaml
containers:
  kong:          # API gateway
  auth:          # authentication (GoTrue)
  rest:          # PostgREST REST API
  realtime:      # WebSocket / realtime
  storage:       # file storage
  imgproxy:      # image processing
  redis:         # caching / queues
```

Each container has its own `image`, `env`, `envFrom`, `resources`, and
`securityContext`. Inter-container comms use `localhost:<port>` (shared pod).

## Template bodies

### PVC — `templates/pvc-<service>-default.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <service-name>
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: <size>Gi  # 1Gi config, 5-10Gi apps, 20Gi+ databases
```

### PostgreSQL cluster — `templates/pg-<service>.yaml`

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-<service-name>
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5-19-bookworm  # check current
  primaryUpdateStrategy: unsupervised
  storage:
    size: 5Gi
    storageClass: local-path

  monitoring:
    enablePodMonitor: true

  postgresql:
    parameters:
      max_connections: "600"
      shared_buffers: 512MB

  bootstrap:
    initdb:
      database: <service-name>
      owner: <service-name>
      secret:
        name: db-<service-name>-secret
```

### Application ExternalSecret — `templates/secret-<service>.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <service-name>
spec:
  refreshInterval: 1h
  target:
    name: <service-name>
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # App-specific env vars constructed from the remoteRef values below.
        # Domain references go HERE, e.g.: WEBHOOK_URL: "https://<svc>.{{ $.Values.domain }}"
        DATABASE_HOST: "pg-<service-name>-rw"          # if PostgreSQL is used
        DATABASE_NAME: "<service-name>"
        DATABASE_USER: "{{ `{{ .db_username }}` }}"
        DATABASE_PASSWORD: "{{ `{{ .db_password }}` }}"
  data:
    # Database credentials (only if PostgreSQL is used)
    - secretKey: db_username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "<service-name>-db" }}'
        property: username
        # Boilerplate needed so ArgoCD doesn't report a mismatch:
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: db_password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "<service-name>-db" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    # Application field secrets (API keys, JWT secrets, ...)
    - secretKey: api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "<service-name>" }}'
        property: api_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

**Go template escaping:** `"{{ `{{ .db_username }}` }}"` escapes the outer Helm
template so the inner `{{ .db_username }}` passes through as an ExternalSecrets
v2 template literal (evaluated at secret assembly time, not Helm render time).

### Database credentials ExternalSecret — `templates/secret-db-<service>.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: db-<service-name>-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: db-<service-name>-secret
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: {{ index .Values "bitwardenIds" "<service-name>-db" }}
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: password
      remoteRef:
        key: {{ index .Values "bitwardenIds" "<service-name>-db" }}
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

## Integration points

```yaml
APPLICATIONSET:
  - file: services/<category>/prod/values.yaml   # charts: key entry
  - rendered by: charts/base/templates/appset-charts.yaml

PROXY:
  - file: services/<category>/prod/values.yaml
  - pattern: ingress.subdomains.<name> with service + port

SECRETS:
  - bitwarden-login: username/password pairs
  - bitwarden-fields: custom fields (API keys, tokens)

DATABASE:
  - CloudNativePG: pg-<service>-rw for read-write access

SERVICE_VALUES:
  - file: services/<category>/prod/values.yaml
  - purpose: service-wide defaults for all charts in the category
  - hierarchy: chart defaults < service values < custom values
```

## Worked examples in this repo (read these files)

- Custom chart (n8n): `charts/n8n/` — full app-template chart with PG cluster,
  two ExternalSecrets, PVC. Wired via the `charts:` key in
  `services/gpu/prod/values.yaml`.
- app-template alias (karakeep): `services/home/prod/Chart.yaml`
  (`alias: karakeep`) + top-level `karakeep:` config in
  `services/home/prod/values.yaml`. No `charts/karakeep/` directory exists.
- External chart via umbrella: `mosquitto`, `wekan` deps in
  `services/home/prod/Chart.yaml`.
- External chart via `charts:` key: `external-secrets-bitwarden` in
  `services/home/prod/values.yaml` (live `version:` + `repository:`).
- Multi-deploy via `chart:` field: `scifi-farm` in
  `services/home/prod/values.yaml` uses `chart: hugo` (release `home-scifi-farm`
  from `charts/hugo`).
- Service-level PG cluster: `services/home/prod/templates/pg-paperless.yaml` +
  `pg-paperless-secret.yaml`.
