# Plan: Deploy ODK Central (`okd`) on the grow cluster

## Goal

Run ODK Central v2026.3.0 on the grow cluster as a repo-standard bjw-s
app-template chart (`charts/okd`), deployed by the grow ApplicationSet as
release `grow-okd`, exposed at `okd.spencerslab.com` through the grow
cluster's traefik and the proxy-local hub (LAN/mesh only — deliberately NO
proxy-remote edge entry). Includes in-cluster CNPG Postgres, Enketo with its
two Redis instances, pyxform, and SMTP via the repo's smtp-relay chart.

## Skills

Code agent must load (fresh session):

- `helm-chart-creation` — repo chart/service wiring workflow
- `helm-bjw-s-chart` — app-template values API (chart dep is 5.0.1)
- `container-creation` — the new `containers/okd-enketo` image
- `kubernetes-skill` — manifest review discipline

## MCP Servers

- `readonly-grow-kubernetes` — inspect Applications, pods, CNPG cluster,
  ExternalSecrets, Services during/after implementation
- `admin-grow-kubernetes` — ONLY if cluster mutations are required (e.g.
  `kubectl exec` into the backend pod for first-admin creation or debugging).
  Ask the user for confirmation before using it.

## Verified context

Repo recon (all paths read directly in this worktree):

- `services/grow/prod/values.yaml` — grow category: `charts:` map (assistant,
  k8s-monitoring, external-secrets-bitwarden, cloudnative-pg), ingress
  subdomains (cluster/traefik clusterBase only), hivetools block. No
  smtp-relay yet.
- `services/grow/prod/templates/appset.yaml` + `charts/base/templates/appset-charts.yaml`
  — per-app Applications generated from `charts:` entries; internal charts
  (no `version`/`repository`) resolve to git path `charts/<name>`; release
  names `<serviceName>-<appName>` → `grow-okd`; values slice =
  `merge(shared-storage, .Values.<appName>)`; custom-values loaded via the
  cluster annotation `services.grow.customValuesUrls`.
- `charts/n8n/`, `charts/langfuse/` — reference patterns: CNPG Cluster
  (`pg-<name>`, initdb secret `pg-<name>-secret`), ExternalSecrets
  (bitwarden-login + bitwarden-fields, single shared Bitwarden item),
  hand-written PVC templates + `existingClaim`, redis sidecar (langfuse).
- `services/proxy-local/prod/values.yaml` + `templates/proxy/*` — proxy
  entries: `target:` → ExternalName `<target>.<domain>`; `middlewares:` set →
  no hub Keycloak; `ingressRoute.middlewares` covers the LAN ClientIP route.
  Precedent for cluster-level targets: `scifi-farm: target: home-lab`.
- `custom-values/grow/prod-values.yaml` — loaded by the live grow Application
  (verified via `readonly-grow-kubernetes`); smtp-secret shared UUID
  `876515bc-b0d6-43df-b9fa-b0dd000a601e` reused across 6 categories.
- `renovate.json` — ARG-pin custom manager (`# renovate: datasource=github-tags
  depName=...` above `ARG NAME=value`) fits the new Dockerfile.

Live grow cluster (via `readonly-grow-kubernetes`):

- ArgoCD v3.4.5 in `default` ns; `grow-appset`/`grow-charts-appset` present.
- Cluster annotations resolve to `clusterName=grow`, `domain=spencerslab.com`.
- Single node `grow` @ 10.0.3.5 = traefik LB IP (so `grow.spencerslab.com`,
  already used for SSH, reaches the grow traefik — the proxy-local target).
- CNPG operator 1.28.1, external-secrets v0.19.1, bitwarden-cli, cert-manager
  all healthy; `wildcard-cert` + `cluster-wildcard-cert` Ready in default ns.
- Existing CNPG cluster `pg-grow-assistant` confirms local-path + monitoring
  patterns. No reloader deployed (annotation still harmless/standard).
- No Service named `service`, `enketo`, or `pyxform` exists in default ns
  (checked Deployments/Services) — the bare names we need are free.

Upstream verification (fetched from getodk/central at tag v2026.3.0):

- `docker-compose.yml` @ v2026.3.0 pins: `ghcr.io/getodk/pyxform-http:v4.5.0`,
  `redis:8.10.1`, mail `registry.gitlab.com/egos-tech/smtp:2.0.7`.
- GHCR tags verified via registry API: `ghcr.io/getodk/central-service` and
  `central-nginx` both have `v2026.3.0`; `pyxform-http` has `v4.5.0`;
  `ghcr.io/enketo/enketo` has `7.6.4` (the base of ODK's enketo.dockerfile);
  Docker Hub `redis:8.10.1` exists. Caktus `central-enketo` only reaches
  v2026.1.1 → too stale to mix with v2026.3.0 backend/nginx.
- `files/service/scripts/start-odk.sh` — reads ONLY `/etc/secrets/enketo-api-key`;
  fails fast if `DB_SSL` is set to anything but null (do NOT set DB_SSL);
  waits ~15s for pg_isready, runs migrations, starts cron + pm2. Image has no
  ENTRYPOINT → chart must set `command: ["./start-odk.sh"]`.
- `files/service/config.json.template` — hardcodes `xlsform.host: pyxform` and
  `enketo.url: http://enketo:8005/-`; `files/nginx/odk.conf.template` hardcodes
  `proxy_pass http://service:8383` and `http://enketo:8005`. Hence K8s
  Services must be literally named `service`, `enketo`, `pyxform`
  (forceRename) so upstream templates stay untouched.
- `files/enketo/start-enketo.sh` — asserts secret file sizes 64/32/128 bytes
  at `/etc/secrets/{enketo-secret,enketo-less-secret,enketo-api-key}`,
  templates `config/config.json.template` via `files/shared/envsub.awk`
  (`#!/usr/bin/mawk -f`; errors on any undefined `${VAR}`).
- `files/enketo/config.json.template` — redis hosts hardcoded to compose names
  `enketo_redis_main:6379` / `enketo_redis_cache:6380` (underscores are
  invalid K8s Service names → chart mounts a corrected copy pointing at the
  localhost sidecars).
- `files/nginx/setup-odk.sh` — with `SSL_TYPE=upstream`: strips all ssl_*
  directives, listens on :80, forces `X-Forwarded-Proto https`, removes the
  80→443 redirector. TLS terminates at grow's traefik (wildcard-cert).
- envsub.awk requires every `${VAR}` in each template to be DEFINED (empty is
  fine) — the backend ExternalSecret below sets all of them explicitly.

Render checks performed:

- Pulled `bjw-s/app-template 5.0.1` and rendered a full draft of the okd
  values (4 controllers, forceRename services, secret/configMap/PVC mounts):
  Services render exactly `grow-okd` (80), `service` (8383), `enketo` (8005),
  `pyxform` (80); `strategy: Recreate`, sync-wave annotations, container
  `command`/`args`, per-container `advancedMounts` all render correctly.
  One finding: bjw-s auto-created PVCs name the PVC just `grow-okd` → switched
  to the repo-standard hand-written PVC + `existingClaim`.

## Design decisions

1. **Custom app-template chart, not the Caktus chart.** Repo standard is
   internal charts on bjw-s app-template; the Caktus chart is external,
   assumes its own forked images, and its enketo lags v2026.3.0. User said
   repo standards win over the guide.
2. **CNPG Postgres instead of a raw StatefulSet** (repo standard; grow already
   runs the operator). PG17 image `ghcr.io/cloudnative-pg/postgresql:17.5-19-bookworm`
   (same as charts/n8n); ODK supports modern PG (compose ships 14 only for the
   legacy upgrade path; Caktus runs 18). 10Gi local-path, resize-friendly.
3. **Custom container `containers/okd-enketo`.** getodk publishes no enketo
   image; Caktus's fork is version-lagged. Repo standard: no upstream image →
   build in `containers/`. Dockerfile mirrors getodk's `enketo.dockerfile`
   (base `ghcr.io/enketo/enketo:7.6.4`, fetches the 3 glue files from the
   pinned central tag via ADD; renovate ARG-pin tracks getodk/central).
4. **Enketo secrets via Bitwarden, not a generator container.** One Bitwarden
   item `okd` (Login: username/password = DB creds; custom fields
   enketo-secret/enketo-less-secret/enketo-api-key) → ExternalSecret → K8s
   Secret mounted as files at `/etc/secrets` in backend + enketo (n8n-style
   single item, both stores). Eliminates compose's shared `secrets` volume and
   one-shot generator.
5. **Enketo Redis as sidecars** (langfuse pattern): main (:6379, PVC-backed)
   + cache (:6380 via `args: ["--port","6380"]`, emptyDir) in the enketo pod;
   chart ConfigMap overrides the redis hosts in `config.json.template` to
   127.0.0.1. No redis Services needed.
6. **Bare Service names via `forceRename`** (`service`, `enketo`, `pyxform`)
   because nginx/backend upstream configs hardcode those hostnames; keeps all
   upstream templates byte-identical (zero upgrade drift). Names are free in
   grow's default namespace (verified).
7. **`SSL_TYPE=upstream`**, TLS at grow traefik with `wildcard-cert` — repo
   TLS pattern (cert-manager wildcard already issued on grow).
8. **Sync waves** (repo precedent: hivetools): secrets+configmap −3 → CNPG −2
   → backend/enketo/pyxform 0 → frontend 1, so migrations never race a
   bootstrapping DB on first deploy.
9. **smtp-relay on grow** (user-confirmed) reusing the shared smtp-secret
   UUID; ODK backend EMAIL_HOST=`smtp-relay-mail:587`.
10. **proxy-local `okd: target: grow`, crowdsec-only middlewares** — ODK has
    its own auth; public survey links and ODK Collect mobile clients must not
    hit hub Keycloak. No proxy-remote entry (user directive) → public internet
    access intentionally dead-ends at the VPS edge; LAN/mesh access via
    proxy-local wherever `okd.spencerslab.com` resolves to it.
11. **nginx container keeps default capabilities** (nginx master needs
    SETUID/SETGID/CHOWN to spawn workers) — documented deviation from
    drop-ALL; every other container drops ALL.

## Prerequisites — user action (Bitwarden)

Create THREE Bitwarden Login items (superseded the original single `okd`
item — see Review-round fixes #11):

1. **`enketo`** — username: `odk` (informational; the chart hardcodes the DB
   username), password: strong random (`openssl rand -base64 24`), plus ONE
   custom field:
   - `enketo-secret` = `openssl rand -hex 32` (64 chars — asserted at runtime,
     exact length, no newline)
2. **`enketo-less`** — password: `openssl rand -hex 16` (32 chars)
3. **`enketo-api-key`** — password: `openssl rand -hex 64` (128 chars)

(`openssl rand -hex N` emits N bytes = 2N hex chars; sizes are asserted by
start-enketo.sh.) Copy the three item UUIDs into the `okd.bitwardenIds` block
of `custom-values/grow/prod-values.yaml` (step 10).

## Changes

### 1. `charts/okd/Chart.yaml` — CREATE

```yaml
apiVersion: v2
name: okd
version: 1.0.0
appVersion: "2026.3.0"
dependencies:
- name: app-template
  version: 5.0.1
  repository: https://bjw-s-labs.github.io/helm-charts/
```

Then `helm dependency update charts/okd` (generates Chart.lock).

### 2. `charts/okd/values.yaml` — CREATE

```yaml
bitwardenIds:
  okd: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

# ODK system administrator contact (backend sysadminAccount, CERTBOT_EMAIL,
# enketo SUPPORT_EMAIL).
sysadminEmail: lab@spencerslab.com

app-template:
  global:
    nameOverride: &chartName okd

  controllers:
    # Frontend: central-nginx (frontend baked in). SSL_TYPE=upstream → plain
    # HTTP :80; TLS terminates at grow's traefik (wildcard-cert).
    frontend:
      annotations:
        argocd.argoproj.io/sync-wave: "1"
      containers:
        main:
          image:
            repository: ghcr.io/getodk/central-nginx
            tag: v2026.3.0
          env:
            DOMAIN: "okd.{{ .Values.domain }}"
            SSL_TYPE: upstream
            CERTBOT_EMAIL: "{{ .Values.sysadminEmail }}"
            OIDC_ENABLED: "false"
            # Upstream compose defaults (ODK's own Sentry project).
            SENTRY_ORG_SUBDOMAIN: o130137
            SENTRY_KEY: 3cf75f54983e473da6bd07daddf0d2ee
            SENTRY_PROJECT: "1298632"
            SENTRY_DSN_FRONTEND: ""
          probes:
            liveness: &frontendProbe
              enabled: true
              custom: true
              spec:
                tcpSocket:
                  port: 80
                initialDelaySeconds: 10
                periodSeconds: 10
                timeoutSeconds: 2
                failureThreshold: 3
            readiness: *frontendProbe
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            # NOTE: nginx master runs as root and needs CAP_SETUID/SETGID/CHOWN
            # to spawn workers — do NOT drop ALL here.

    # Backend: runs migrations at startup (start-odk.sh) → Recreate so two
    # pods never migrate concurrently.
    backend:
      strategy: Recreate
      annotations:
        reloader.stakater.com/auto: "true"
        argocd.argoproj.io/sync-wave: "0"
      containers:
        main:
          image:
            repository: ghcr.io/getodk/central-service
            tag: v2026.3.0
          # Image ships no entrypoint; compose runs start-odk.sh (waits for
          # PG, generates local.json, runs migrations, starts cron + pm2).
          command: ["./start-odk.sh"]
          envFrom:
            - secretRef:
                name: okd-backend
          probes:
            liveness: &backendProbe
              enabled: true
              custom: true
              spec:
                tcpSocket:
                  port: 8383
                initialDelaySeconds: 30
                periodSeconds: 10
                timeoutSeconds: 2
                failureThreshold: 5
            readiness: *backendProbe
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1536Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

    # Enketo + its two Redis instances (sidecars, localhost — upstream
    # config.json.template redis hosts are overridden via the enketo-config
    # ConfigMap mount; compose names contain underscores, invalid in K8s).
    enketo:
      strategy: Recreate
      annotations:
        reloader.stakater.com/auto: "true"
        argocd.argoproj.io/sync-wave: "0"
      containers:
        enketo:
          image:
            repository: ghcr.io/ownyourio/okd-enketo
            # New in-repo container: no pinned build exists yet — track the
            # rolling :main tag until docker-build publishes the first
            # :v<run>, then pin it (renovate maintains the pin afterwards).
            tag: main
            pullPolicy: Always
          env:
            DOMAIN: "okd.{{ .Values.domain }}"
            SUPPORT_EMAIL: "{{ .Values.sysadminEmail }}"
            HTTPS_PORT: "443"
          probes:
            liveness: &enketoProbe
              enabled: true
              custom: true
              spec:
                tcpSocket:
                  port: 8005
                initialDelaySeconds: 30
                periodSeconds: 10
                timeoutSeconds: 2
                failureThreshold: 5
            readiness: *enketoProbe
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 768Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
        redis-main:
          image:
            repository: redis
            tag: 8.10.1
          probes:
            liveness: &redisMainProbe
              enabled: true
              custom: true
              spec:
                tcpSocket:
                  port: 6379
                initialDelaySeconds: 5
                periodSeconds: 10
                failureThreshold: 3
            readiness: *redisMainProbe
          resources:
            requests:
              cpu: 50m
              memory: 50Mi
            limits:
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
        redis-cache:
          image:
            repository: redis
            tag: 8.10.1
          # Enketo expects the cache redis on 6380 (upstream conf).
          args: ["--port", "6380"]
          probes:
            liveness: &redisCacheProbe
              enabled: true
              custom: true
              spec:
                tcpSocket:
                  port: 6380
                initialDelaySeconds: 5
                periodSeconds: 10
                failureThreshold: 3
            readiness: *redisCacheProbe
          resources:
            requests:
              cpu: 50m
              memory: 50Mi
            limits:
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

    # XLSForm conversion service.
    pyxform:
      annotations:
        argocd.argoproj.io/sync-wave: "0"
      containers:
        main:
          image:
            repository: ghcr.io/getodk/pyxform-http
            tag: v4.5.0
          probes:
            liveness: &pyxformProbe
              enabled: true
              custom: true
              spec:
                tcpSocket:
                  port: 80
                initialDelaySeconds: 5
                periodSeconds: 10
                failureThreshold: 3
            readiness: *pyxformProbe
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  service:
    # Ingress target: with nameOverride okd + release grow-okd this renders
    # as `grow-okd` (referenced by services/grow ingress.subdomains.okd).
    okd:
      controller: frontend
      ports:
        http:
          port: 80
    # Upstream ODK configs hardcode these hostnames (nginx odk.conf.template:
    # proxy_pass http://service:8383 / http://enketo:8005; backend
    # config.json.template: xlsform host `pyxform`, enketo url
    # http://enketo:8005/-). forceRename keeps upstream templates untouched.
    backend:
      forceRename: service
      controller: backend
      ports:
        http:
          port: 8383
    enketo:
      forceRename: enketo
      controller: enketo
      ports:
        http:
          port: 8005
    pyxform:
      forceRename: pyxform
      controller: pyxform
      ports:
        http:
          port: 80

  configMaps:
    # Verbatim copy of getodk/central files/enketo/config.json.template at
    # v2026.3.0, with ONLY the redis hosts changed to the localhost sidecars.
    # Re-sync from upstream whenever the Central version is bumped.
    enketo-config:
      annotations:
        argocd.argoproj.io/sync-wave: "-3"
      data:
        config.json.template: |
          {
              "app name": "Enketo",
              "base path": "-",
              "encryption key": "${SECRET}",
              "id length": 31,
              "less secure encryption key": "${LESS_SECRET}",
              "linked form and data server": {
                  "api key": "${API_KEY}",
                  "authentication": {
                      "type": "cookie",
                      "url": "${BASE_URL}/login?next={RETURNURL}"
                  },
                  "name": "ODK Central",
                  "server url": "${DOMAIN}"
              },
              "logo": {
                  "source": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=",
                  "href": ""
              },
              "offline enabled": true,
              "payload limit": "1mb",
              "port": "8005",
              "query parameter to pass to submission": "st",
              "redis": {
                  "main": {
                      "host": "127.0.0.1",
                      "port": "6379"
                  },
                  "cache": {
                      "host": "127.0.0.1",
                      "port": "6380"
                  }
              },
              "support": {
                  "email": "support@getodk.org"
              },
              "maps": [ {
                  "name": "street",
                  "tiles": [ "https://tile.openstreetmap.org/{z}/{x}/{y}.png" ],
                  "attribution": "Map data © <a href=\"http://openstreetmap.org\">OpenStreetMap</a> contributors",
                  "referrerPolicy": "origin"
              } ],
              "text field character limit": 1000000,
              "exclude non-relevant": true,
              "hide powered by": true
          }

  persistence:
    # Enketo secrets (ExternalSecret `okd`) mounted as files —
    # start-enketo.sh asserts sizes 64/32/128; start-odk.sh reads
    # enketo-api-key.
    secrets:
      type: secret
      name: okd
      advancedMounts:
        backend:
          main:
            - path: /etc/secrets
              readOnly: true
        enketo:
          enketo:
            - path: /etc/secrets
              readOnly: true
    enketo-config:
      type: configMap
      identifier: enketo-config
      advancedMounts:
        enketo:
          enketo:
            - path: /srv/src/enketo/packages/enketo-express/config/config.json.template
              subPath: config.json.template
    enketo-redis-main-data:
      existingClaim: okd-enketo-redis
      advancedMounts:
        enketo:
          redis-main:
            - path: /data
    enketo-redis-cache-data:
      type: emptyDir
      advancedMounts:
        enketo:
          redis-cache:
            - path: /data
```

### 3. `charts/okd/templates/secret-okd.yaml` — CREATE

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: okd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-fields
    kind: SecretStore
  target:
    name: okd
    creationPolicy: Owner
  data:
    - secretKey: enketo-secret
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "okd" }}'
        property: enketo-secret
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: enketo-less-secret
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "okd" }}'
        property: enketo-less-secret
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: enketo-api-key
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "okd" }}'
        property: enketo-api-key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 4. `charts/okd/templates/secret-okd-backend.yaml` — CREATE

Every `${VAR}` in getodk's `files/service/config.json.template` must be
defined (envsub.awk fails otherwise) — empty values are fine. Do NOT set
`DB_SSL` (start-odk.sh aborts if it is set to anything but null).

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: okd-backend
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  refreshInterval: 1h
  target:
    name: okd-backend
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # PostgreSQL (CNPG cluster pg-okd) — libpq env consumed by the backend.
        PGHOST: "pg-okd-rw"
        PGDATABASE: "odk"
        PGUSER: "{{ `{{ .username }}` }}"
        PGPASSWORD: "{{ `{{ .password }}` }}"
        PGAPPNAME: "odkcentral"
        # Application config.
        DOMAIN: "okd.{{ $.Values.domain }}"
        SYSADMIN_EMAIL: "{{ $.Values.sysadminEmail }}"
        HTTPS_PORT: "443"
        DB_POOL_SIZE: "10"
        SESSION_LIFETIME: "86400"
        # Mail via the grow smtp-relay (charts/smtp-relay, port 587).
        EMAIL_FROM: "no-reply@okd.{{ $.Values.domain }}"
        EMAIL_HOST: "smtp-relay-mail"
        EMAIL_PORT: "587"
        EMAIL_SECURE: "false"
        EMAIL_IGNORE_TLS: "true"
        EMAIL_USER: ""
        EMAIL_PASSWORD: ""
        # OIDC disabled (ODK's own auth).
        OIDC_ENABLED: "false"
        OIDC_ISSUER_URL: ""
        OIDC_CLIENT_ID: ""
        OIDC_CLIENT_SECRET: ""
        # Upstream compose defaults (ODK's own Sentry project).
        SENTRY_ORG_SUBDOMAIN: "o130137"
        SENTRY_KEY: "3cf75f54983e473da6bd07daddf0d2ee"
        SENTRY_PROJECT: "1298632"
        SENTRY_TRACE_RATE: "0"
        # S3 blob storage unused (local DB-backed storage).
        S3_SERVER: ""
        S3_ACCESS_KEY: ""
        S3_SECRET_KEY: ""
        S3_BUCKET_NAME: ""
  data:
    - secretKey: username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "okd" }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "okd" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 5. `charts/okd/templates/secret-pg-okd.yaml` — CREATE

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: pg-okd-secret
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: pg-okd-secret
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "okd" }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: password
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "okd" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 6. `charts/okd/templates/pg-okd.yaml` — CREATE

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-okd
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5-19-bookworm
  primaryUpdateStrategy: unsupervised
  storage:
    size: 10Gi
    storageClass: local-path
  monitoring:
    enablePodMonitor: true
  postgresql:
    parameters:
      max_connections: "100"
      shared_buffers: 256MB
  bootstrap:
    initdb:
      database: odk
      owner: odk
      secret:
        name: pg-okd-secret
```

### 7. `charts/okd/templates/pvc-okd-enketo-redis-default.yaml` — CREATE

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: okd-enketo-redis
  namespace: default
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

### 8. `containers/okd-enketo/Dockerfile` — CREATE

```dockerfile
# ODK Central Enketo. getodk publishes no enketo image (only
# central-service/central-nginx/pyxform-http on GHCR), so this reproduces
# getodk/central's enketo.dockerfile at the pinned Central tag. Consumed by
# charts/okd. When bumping CENTRAL_VERSION, also check that tag's
# enketo.dockerfile FROM line and bump the base image below if it changed.
FROM ghcr.io/enketo/enketo:7.6.4

# renovate: datasource=github-tags depName=getodk/central
ARG CENTRAL_VERSION=v2026.3.0

ENV ENKETO_SRC_DIR=/srv/src/enketo/packages/enketo-express
WORKDIR ${ENKETO_SRC_DIR}

# The three files getodk/central's enketo.dockerfile copies. The chart mounts
# its own config.json.template over the baked one at runtime (redis sidecar
# hosts); the baked copy keeps the image faithful to upstream.
ADD https://raw.githubusercontent.com/getodk/central/${CENTRAL_VERSION}/files/shared/envsub.awk /scripts/envsub.awk
ADD https://raw.githubusercontent.com/getodk/central/${CENTRAL_VERSION}/files/enketo/config.json.template ${ENKETO_SRC_DIR}/config/config.json.template
ADD https://raw.githubusercontent.com/getodk/central/${CENTRAL_VERSION}/files/enketo/start-enketo.sh ${ENKETO_SRC_DIR}/start-enketo.sh

RUN cp config/config.json.template config/config.json \
    && chmod +x /scripts/envsub.awk start-enketo.sh

EXPOSE 8005
ENTRYPOINT ["./start-enketo.sh"]
```

Runs as the base image's default user (faithful to upstream); do not add a
USER directive — start-enketo.sh must write config.json into the image's
config dir.

### 9. `services/grow/prod/values.yaml` — MODIFY

a) Add under `charts:` (internal-chart pattern, matching `assistant`):

```yaml
  okd:
    #version: 1.0.10 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
    #repository: https://ownyourio.github.io/SpencersLab/
    namespace: default
    ServerSideApply: "true"
  smtp-relay:
    #version: 1.0.13 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
    #repository: https://ownyourio.github.io/SpencersLab/
    namespace: default
    ServerSideApply: "true"
```

b) Add under `ingress.subdomains:`:

```yaml
    okd:
      service: grow-okd
      port: 80
```

(No top-level `okd:` config block is needed — chart defaults + custom-values
cover everything.)

### 10. `custom-values/grow/prod-values.yaml` — MODIFY

Append:

```yaml
okd:
  bitwardenIds:
    okd: <UUID-OF-BITWARDEN-ITEM-FROM-PREREQUISITES>

smtp-relay:
  bitwardenIds:
    smtp-secret: 876515bc-b0d6-43df-b9fa-b0dd000a601e
```

### 11. `services/proxy-local/prod/values.yaml` — MODIFY

Add under `proxy.subdomains` (e.g. after `scifi-farm`):

```yaml
    # ODK Central (grow cluster). ODK has its own auth; public survey links
    # and ODK Collect mobile clients must not hit hub Keycloak → crowdsec only.
    # target `grow` = grow cluster traefik (grow.<domain> resolves to it).
    okd:
      target: grow
      middlewares: "kube-system-crowdsec@kubernetescrd"
      ingressRoute:
        middlewares:
          - "kube-system-crowdsec@kubernetescrd"
```

### 12. NOT changed: `services/proxy-remote/prod/values.yaml`

Deliberately no entry (user directive). Public requests for
okd.spencerslab.com dead-end at the VPS edge; LAN/mesh access goes through
proxy-local.

## Verification

Chart (run from repo root):

1. `helm dependency update charts/okd` → Chart.lock created.
2. `helm lint charts/okd`.
3. `helm template grow-okd charts/okd --set domain=spencerslab.com --set bitwardenIds.okd=test-uuid > /tmp/okd-render.yaml`
   — must succeed; then:
   - `grep -c "OVERRIDE_" /tmp/okd-render.yaml` → 0
   - Service names present: `grep -E "^  name: (service|enketo|pyxform|grow-okd)$" /tmp/okd-render.yaml`
     → all four.
   - Deployments: `grow-okd-backend` (strategy Recreate, command
     ./start-odk.sh), `grow-okd-enketo` (3 containers), `grow-okd-frontend`,
     `grow-okd-pyxform`; CNPG Cluster `pg-okd`; 3 ExternalSecrets; PVC
     `okd-enketo-redis`; ConfigMap with redis hosts 127.0.0.1.
4. `docker build containers/okd-enketo -t okd-enketo:test` — builds (needs
   network for the ADD fetches).

Integration:

5. `grep -rn "okd" services/grow/prod/values.yaml services/proxy-local/prod/values.yaml custom-values/grow/prod-values.yaml`
   — charts entry + ingress entry + proxy entry + custom-values UUID all
   present (the service trio + secrets tier).

Post-merge (ArgoCD, watch via `readonly-grow-kubernetes`):

6. `docker-build.yaml` builds `ghcr.io/ownyourio/okd-enketo:main` +
   `:v<run>` (the chart may sit in ImagePullBackOff until the first build
   completes — self-heals; optionally pin the `:v<run>` tag afterwards).
7. Application `grow-okd` syncs wave-by-wave: ExternalSecrets Ready →
   `pg-okd` Cluster Ready → backend runs migrations (check logs: "running
   migrations..") → frontend. All pods Ready in default ns.
8. First admin (user action, needs `admin-grow-kubernetes` or a terminal):
   `kubectl exec -n default deploy/grow-okd-backend -it -- odk-cmd --email lab@spencerslab.com user-create`
   then `... user-promote`.
9. Smoke test from LAN/mesh: https://okd.spencerslab.com → ODK login page;
   log in as the admin; create a project + form (exercises pyxform + enketo);
   open a web form preview (exercises enketo redis + iframe path).

## Risks & open questions

- **First-sync image race**: ArgoCD may create the enketo Deployment before
  `docker-build.yaml` publishes `okd-enketo:main` → transient
  ImagePullBackOff; resolves when the build lands.
- **nginx capabilities**: central-nginx container keeps default capabilities
  (nginx master needs SETUID/SETGID/CHOWN) — deviation from drop-ALL,
  commented in values.yaml.
- **Bare Service names** `service`/`enketo`/`pyxform` in the default
  namespace are required by hardcoded upstream configs; they are free today
  (verified) but any future chart must not claim them.
- **Upgrade drift**: on Central version bumps, renovate opens independent PRs
  for the three GHCR image tags, redis, the enketo base image, and the
  Dockerfile `CENTRAL_VERSION` ARG. When bumping `CENTRAL_VERSION`, re-sync
  the chart's `config.json.template` ConfigMap from the new tag and check the
  new tag's `enketo.dockerfile` FROM line (base image may move too).
- **ODK downgrades are unsupported**; read every release note between current
  and target version before upgrading (some releases need extra downtime).
- **Backups**: no CNPG barman schedule (matches n8n); enketo secrets live in
  Bitwarden. A pg_dump CronJob is sensible follow-up work, out of scope here.
- **Access model**: no proxy-remote route → no public internet access
  (intended). LAN/mesh clients need `okd.spencerslab.com` to resolve to the
  proxy-local traefik via the lab's split-horizon DNS (same mechanism as the
  cluster.* hosts). The proxy-local ingress still publishes a public CNAME
  okd→proxy-remote (harmless dead-end).
- **SMTP**: relay sends unauthenticated from within the cluster; if the relay
  ever requires auth, add EMAIL_USER/EMAIL_PASSWORD to the okd-backend
  ExternalSecret.

## Implementation deviations (2026-09-12)

1. **Domain env moved out of values.yaml** — the plan's frontend/enketo
   `env:` used `okd.{{ .Values.domain }}` / `{{ .Values.sysadminEmail }}`
   inside the `app-template:` subtree. Verified against the live gpu cluster:
   bjw-s tpl-evaluates env strings in the SUBCHART context, where the
   appset's top-level `domain` parameter is invisible — searxng renders
   `SEARXNG_BASE_URL: https://` in production today (same latent bug the
   immich-analyze chart documents). Fix: new parent-context template
   `charts/okd/templates/configmap-okd-env.yaml` (sync-wave −3) renders
   DOMAIN/CERTBOT_EMAIL/SUPPORT_EMAIL; frontend + enketo consume it via
   `envFrom: configMapRef`. Backend DOMAIN was already safe (ExternalSecret
   template = parent context). Re-render verified: `DOMAIN:
   okd.spencerslab.com` in okd-env, envFrom wired on both containers.
2. **Docker build skipped** — no docker daemon in the agent environment;
   instead all three `ADD` URLs were curl-verified HTTP 200 at tag
   v2026.3.0. CI (`docker-build.yaml`) builds the image on merge.

## Review-round fixes (2026-09-14, post `/review`)

All 4 WARNINGs + 6 SUGGESTIONS from the local review applied:

1. **UUID placeholder guarded** — DO-NOT-MERGE comment above the okd block in
   `custom-values/grow/prod-values.yaml` explaining the wave −3 stall if
   merged before the Bitwarden item exists.
2. **Dockerfile supply chain** — `CENTRAL_VERSION` now pinned to the immutable
   commit SHA of v2026.3.0 (`c008e6904efdb3d2b2ac6a84f4ba18b74c310dda`,
   lightweight tag resolved via GitHub API; all three SHA URLs curl-verified
   200). Renovate `github-tags` ARG-pin maintained.
3. **Backend startupProbe** — tcpSocket 8383, 30 × 10s (5 min first-boot
   migration budget); liveness/readiness only arm after startup succeeds.
4. **CNPG resources** — pg-okd gets requests 128m/512Mi, memory limit 1Gi
   (Burstable, not eviction-first; no CPU limit — throttling hurts DBs).
5. **Dead `&chartName` anchor removed.**
6. **Sentry constants hoisted** to top-level `sentry:` value; rendered into
   both the frontend okd-env ConfigMap and the backend ExternalSecret from it.
7. **Subdomain hoisted** to `subdomain: okd`; DOMAIN/EMAIL_FROM composed from
   it in the two parent-context templates (single source for the prefix).
8. **Reserved Service names documented** — `service`/`enketo`/`pyxform` in
   `default` recorded in `skills/helm-chart-creation/SKILL.md` gotchas, plus
   the app-template-subchart-cannot-see-top-level-values gotcha (the
   searxng `SEARXNG_BASE_URL` latent bug).
9. **Dead baked `config.json` dropped** from the Dockerfile (start-enketo.sh
   regenerates it every boot; upstream's cp served a client build step this
   image doesn't run).
10. **Email env vars removed entirely** (user request): CERTBOT_EMAIL
    (certbot path never runs with SSL_TYPE=upstream) and SUPPORT_EMAIL
    (v2026.3.0 enketo hardcodes its support address) are consumed by nothing;
    okd-env now carries only DOMAIN + the three Sentry constants.

Also on 2026-09-14: merged `main` (fast-forward; brought mayan-edms +
mariadb-operator), resolved the services/grow values.yaml conflict (all
entries kept). The user's follow-up idea of running ODK's DB on the new
mariadb-operator was withdrawn after confirming ODK Central is
PostgreSQL-only (pg_isready wait, PG* libpq env, PG-only config template) —
CNPG stays.

11. **Secrets restructured to three named Bitwarden items** (user request):
    `enketo` (Login: username odk + DB password + custom field
    `enketo-secret`), `enketo-less` (password = less-secure key),
    `enketo-api-key` (password = API key). The DB username is structurally
    fixed (must equal the CNPG initdb owner `odk`, mayan-edms precedent), so
    it is now HARDCODED in `secret-okd-backend.yaml` (PGUSER) and
    `secret-pg-okd.yaml` (templated `username: odk`); only the password is
    fetched. `bitwardenIds` now has three keys (`enketo`, `enketo-less`,
    `enketo-api-key`); `secret-okd.yaml` mixes stores per key
    (bitwarden-fields for the custom field, bitwarden-login for the two
    passwords). K8s Secret/key names unchanged (`okd` secret with
    enketo-secret/enketo-less-secret/enketo-api-key files). Also synced the
    updated `helm-chart-creation` SKILL.md (wrapper-chart guidance) from the
    main checkout and re-added the two okd gotcha bullets.
12. **Bitwarden UUIDs set** (2026-09-14): user created the three items; real
    UUIDs now in `custom-values/grow/prod-values.yaml` (enketo
    1aa10dd1-…, enketo-less 86239b0f-…, enketo-api-key 4c8ef2ef-…).
    End-to-end render with the custom-values slice verified: 0 sentinels,
    all five remoteRefs resolve to the right item/property.
13. **Public name renamed okd → forms** (2026-09-14, post-merge, user
    request): proxy-local entry key renamed `okd:` → `forms:` (hub serves
    forms.spencerslab.com, crowdsec-only, target grow; old okd-* hub objects
    prune on sync). Grow keeps the internal name: `ingress.subdomains.okd`
    gains `serviceName: forms` (erp-next/erp dual-host pattern) → renders
    `okd-ingress` (okd.<domain>, no DNS record) AND `forms-ingress`
    (forms.<domain>, external-dns enabled), both → grow-okd:80, because the
    hub preserves the Host header when forwarding. Chart unchanged: release,
    Services, and DOMAIN stay okd.spencerslab.com — if user-facing links
    should say forms.spencerslab.com instead, set `subdomain: forms` in
    charts/okd/values.yaml (one line; affects DOMAIN + EMAIL_FROM).
