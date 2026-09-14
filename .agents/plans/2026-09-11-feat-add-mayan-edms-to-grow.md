# Plan: Add Mayan EDMS to the grow cluster (proxy-local subdomain `edms`)

## Goal

Deploy Mayan EDMS 4.12.1 as a new custom chart `charts/mayan-edms` on the
**grow** cluster: all-in-one Mayan container (gunicorn + celery workers A–F +
beat) with a pod-local Redis sidecar and a single-instance CloudNativePG
PostgreSQL cluster, exposed through the proxy-local hub as **`edms.<domain>`**
(no proxy-remote/zerotrust-edge entry). The user gets a working document
management system at `https://edms.<domain>` (LAN/mesh access) with admin
login from Bitwarden.

## Skills

The Code agent (fresh session) must load:

- `helm-chart-creation` — repo chart/service-wiring workflow, trio, sentinels
- `helm-bjw-s-chart` — app-template values API (chart uses app-template 5.0.1)
- `verification-before-completion` — run the Verification section and show output before claiming done

## MCP Servers

- `readonly-grow-kubernetes` — inspect pods, CNPG cluster, ExternalSecrets, PVCs after merge/sync
- `readonly-proxy-local-kubernetes` — verify hub ExternalName/Ingress objects render
- `admin-grow-kubernetes` — **only if** a resource gets stuck and needs a manual unstick (delete failed pod/secret); ask the user for explicit confirmation before any admin call. Normal flow needs no admin server — ArgoCD applies everything.

## Verified context

Recon performed 2026-09-11 against this worktree and the live grow cluster
(`readonly-grow-kubernetes`), plus upstream Mayan sources:

**Repo patterns (files read):**
- `charts/n8n/` — reference DB-backed chart: Chart.yaml (app-template 5.0.1),
  `values.yaml` (`bitwardenIds` sentinels, `domain: OVERRIDE_VIA_APPSET`,
  `global.nameOverride` anchor), templates `pg-n8n.yaml` (CNPG Cluster),
  `secret-pg-n8n.yaml` (CNPG bootstrap creds), `secret-n8n.yaml`
  (ExternalSecret v2 template composing app env), `pvc-n8n-default.yaml`.
- `charts/langfuse/values.yaml` — repo-standard Redis = **sidecar container**
  in the same pod, `redis:8.x`, app talks `localhost:6379`.
- `charts/home-assistant/templates/pg-home-assistant.yaml` — CNPG pattern on
  grow (initdb + bootstrap secret + `enablePodMonitor: true`).
- `services/grow/prod/values.yaml` — grow already deploys `cloudnative-pg`
  (chart 0.27.1 / operator 1.28.1), `assistant`, `k8s-monitoring`,
  `external-secrets-bitwarden`; `ingress.subdomains` rendered by
  `services/grow/prod/templates/generic-ingress.yaml` (external-dns target
  annotation commented out — per-app hosts are mesh-only).
- `services/grow/prod/templates/appset.yaml` + `charts/base/templates/appset-charts.yaml`
  — `charts:` entries render one Application `<serviceName>-<appName>`
  (→ release **`grow-mayan-edms`**), values slice = top-level `<appName>:`
  block of service values merged with `custom-values/grow/prod-values.yaml`.
- `services/proxy-local/prod/templates/proxy/proxy-{service,ingress,ingress-local}.yaml`
  — `proxy.subdomains.<name>` renders ExternalName `<name>-service` →
  `<target>.<domain>` + hub Ingress/IngressRoute with default middleware chain
  (crowdsec entrypoint + Keycloak forward-auth `userAuth`) when no
  `middlewares`/`ssoRedirectPath` is set (pictaria pattern for own-auth apps).
- `services/home/prod/values.yaml` paperless wiring — the working cross-cluster
  reference: home ingress entry `documents: {serviceName: paperless, service:
  home-paperless-main, port: 8000}` + proxy-local `documents: {target:
  paperless}`. The ingress key and `serviceName` MUST differ (both render
  Ingress objects named `<key|serviceName>-ingress`; equal values collide).
- Live gpu cluster Services — bjw-s naming rule confirmed: when the service
  key equals `global.nameOverride`, the Service name is the release name
  (`gpu-n8n`, `gpu-docling`, `gpu-archon`, …; second keys get `-<key>`
  suffixes, e.g. `gpu-n8n-scrape4ai`). So service key `mayan-edms` →
  Service **`grow-mayan-edms`**.
- `custom-values/grow/prod-values.yaml` — per-app block shape
  (`assistant: bitwardenIds: …`), loaded via cluster-secret annotations
  (proven working: `pg-grow-assistant` clusters run off those UUIDs).
- `renovate.json` — built-in helm-values manager tracks `image.repository` +
  `image.tag` in values.yaml; pinned tags required (repo rule).

**Grow cluster state (live):**
- Single-node k3s (`grow`), everything in namespace `default`; ArgoCD apps
  Healthy/Synced; CNPG operator 1.28.1 running; cert-manager + wildcard certs;
  external-secrets-bitwarden + bitwarden-cli running; k3s traefik in
  kube-system; default StorageClass `local-path` (on the node root disk).
- **Memory:** ~12.5Gi total, ~2.6Gi available (working set 10.6Gi) — tight.
- **Disk:** node root disk 25.7Gi total, **~5.3Gi free**; local-path PVs live
  under `/var/lib/rancher/k3s/storage` on that same disk; quotas are NOT
  enforced (existing 500Gi PVC is nominal). Mayan image pull ≈ 1.5Gi unpacked.
- No Reloader deployed (the `reloader.stakater.com/auto` annotation is a
  repo-standard harmless no-op).

**Mayan ground truth (verified from the actual `mayanedms/mayanedms:v4.12.1`
image config/rootfs layer + GitLab sources, not from the handoff guide):**
- Docker Hub: `v4.12.1` is the newest tag (pushed 2026-08-22, multi-arch).
  Image: ENTRYPOINT `/usr/local/bin/entrypoint.sh`, CMD `run_all`, EXPOSE 8000,
  USER root.
- Entrypoint flow: `wait.py` (MAYAN_DOCKER_WAIT host:port checks) →
  `update_uid_gid` (top-level `chown mayan:mayan /var/lib/mayan`, creates +
  chowns `${MAYAN_MEDIA_ROOT}/tmp`, `groupmod`/`usermod` to MAYAN_USER_UID/GID
  default 1000) → optional apt/pip installs → font cache →
  `initial_setup_or_perform_upgrade` via `runuser --user mayan` →
  `supervisord` (gunicorn on 0.0.0.0:8000 + workers A–F + beat, all
  `user=mayan`). **Requires root + CAP_CHOWN/SETUID/SETGID — `drop: [ALL]`
  alone breaks the container.**
- `MAYAN_SKIP_CHOWN_ON_STARTUP` only takes effect when MAYAN_USER_UID/GID ≠
  1000 — pointless for this deployment; not set.
- SECRET_KEY is generated on first setup and persisted at
  `/var/lib/mayan/system/SECRET_KEY` (on the PVC) — no secret plumbing needed.
- Install flag `/var/lib/mayan/system/SECRET_KEY` decides setup-vs-upgrade;
  `MAYAN_ALLOWED_HOSTS` defaults to `['*']` in the entrypoint (upstream
  compose also leaves it unset).
- `config.env` in the image: `DJANGO_SERIES=5.2` → Django 5.2 → PostgreSQL 17
  is supported; repo-standard CNPG image
  `ghcr.io/cloudnative-pg/postgresql:17.5-19-bookworm` (same as n8n) is safe.
- Upstream master `docker/docker-compose.yml` (fetched live): Mayan env keys
  confirmed incl. two the handoff guide missed —
  `MAYAN_SERVER_SIDE_EVENTS_BACKEND` /
  `MAYAN_SERVER_SIDE_EVENTS_BACKEND_ARGUMENTS` (new `server_side_events` app,
  Redis **db 3**; 4.12 release notes confirm "Redis database count increased
  to 4" and "noeviction maximum memory policy" — the guide's `allkeys-lru`
  advice is outdated and would silently break locks/chords).
- `mayan/apps/autoadmin/settings.py` (master): setting `AUTOADMIN_PASSWORD`
  exists → env var **`MAYAN_AUTOADMIN_PASSWORD`** (guide's VERIFY item
  resolved). Also `AUTOADMIN_LOG_CREDENTIALS` (not used — we set a fixed
  password).
- Health: no dedicated endpoint; `/` returns 302→login, which httpGet probes
  treat as success (matches the image's own urllib-based healthcheck).

## Design decisions

1. **Custom chart `charts/mayan-edms`** (not umbrella alias, not external):
   the official Mayan Helm chart is stale (tops out 4.5.0-2, ~2023 — verified
   in the guide, matches skill guidance to build on app-template). Follows the
   n8n chart shape exactly.
2. **Redis = sidecar container** (repo standard, langfuse pattern) instead of
   the guide's separate Redis deployment: one pod, localhost URLs, no Redis
   password needed. Flags mirror upstream compose: `--databases 4
   --maxmemory 100mb --maxmemory-policy noeviction --save "" --appendonly no`.
3. **PostgreSQL via CloudNativePG** `pg-mayan-edms`, 1 instance, `local-path`,
   image `17.5-19-bookworm` (repo standard; Django 5.2 supports PG 17; grow
   already runs PG17 clusters). DB/owner `mayan`. Parameters adapted from the
   upstream compose flags, scaled down (shared_buffers 256MB) because the node
   is memory-tight.
4. **Secrets: one Bitwarden LOGIN item** (n8n single-item pattern) feeding
   both the CNPG bootstrap ExternalSecret and the app ExternalSecret; the
   initial admin password rides the same item as a custom field
   `autoadmin_password` read via the `bitwarden-fields` store (langfuse
   pattern). `MAYAN_DATABASES` embeds the password in a Python dict literal,
   so it is composed inside the ExternalSecret template — the password must
   not contain single quotes (user is instructed accordingly).
5. **Security context deviation (documented in values):** the mayan container
   runs as root and keeps `CHOWN, SETUID, SETGID, DAC_OVERRIDE` (dropping ALL
   breaks the entrypoint's chown/runuser/supervisord privilege drop — verified
   against the image). Pod gets `fsGroup: 1000` + `OnRootMismatch` so the
   `mayan` user (uid/gid 1000) owns the PVC. The redis sidecar runs as uid
   999 with drop-ALL (no gosu path needed since nothing is persisted).
6. **Single node, non-HA:** `strategy: Recreate` (RWO PVC), 1 replica,
   reduced worker concurrency (A2/B2/C2/D1/E1/F1) and 2 gunicorn workers per
   the guide's tuning, `MAYAN_GUNICORN_TIMEOUT: "300"` for slow-disk uploads.
7. **Exposure — repo trio, not chart ingress:**
   - grow: `charts:` entry + `ingress.subdomains.edms` with `serviceName:
     mayan-edms` (paperless pattern: key ≠ serviceName avoids the
     `<name>-ingress` name collision; renders `edms.<domain>` mesh ingress +
     external-dns-labelled `mayan-edms.<domain>` ingress that the hub's
     ExternalName targets).
   - proxy-local: `proxy.subdomains.edms: {target: mayan-edms}` → ExternalName
     `edms-service → mayan-edms.<domain>`, hub ingress `edms.<domain>` with
     the default crowdsec + Keycloak forward-auth chain (pictaria pattern for
     apps with their own login).
   - **proxy-remote: nothing** (user instruction — no zerotrust-edge/public
     route).
8. **Image pin `v4.12.1`** (repo pinning rule; renovate's helm-values manager
   bumps it; the rolling `s4.12` tag is not trackable).
9. **PVC sizes nominal per user decision:** 20Gi data + 5Gi PG. local-path
   does not enforce quotas; real usage is bounded by the node's ~5.3Gi free
   disk — accepted risk, flagged below.
10. **app-template stays at 5.0.1** (repo standard; the guide's 5.1.0 not
    adopted — every chart pins 5.0.1).
11. Out of scope (YAGNI): Elasticsearch (Whoosh default), RabbitMQ (Redis
    broker), CNPG backups/ScheduledBackup, read-only MCP postgres role for the
    mayan DB, staging/watch folders, extra OCR languages (`MAYAN_APT_INSTALLS`
    hook documented in values comments for later).

## Prerequisite (user, before the secrets can sync)

Create a Bitwarden **LOGIN** item (suggested name `mayan-edms`):
- username: `mayan` (becomes the CNPG DB owner — must match)
- password: strong, **no single-quote characters** (it is embedded in a Python
  dict literal inside `MAYAN_DATABASES`)
- custom field: `autoadmin_password` = the initial Mayan `admin` web password

Hand the item UUID to the Code agent when it asks (step 8).

## Changes

### 1. `charts/mayan-edms/Chart.yaml` — CREATE

```yaml
apiVersion: v2
name: mayan-edms
description: Mayan EDMS - free open source electronic document management system
type: application
version: 1.0.0
appVersion: "4.12.1"
dependencies:
- name: app-template
  version: 5.0.1
  repository: https://bjw-s-labs.github.io/helm-charts/
```

Then run `helm dependency update charts/mayan-edms` to generate
`charts/mayan-edms/Chart.lock` (commit both; no vendored tarball — matches
every other chart in the repo).

### 2. `charts/mayan-edms/values.yaml` — CREATE

```yaml
bitwardenIds:
  mayan-edms: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName mayan-edms

  defaultPodOptions:
    # The Mayan entrypoint starts as root, chowns /var/lib/mayan, then drops
    # to uid/gid 1000 ("mayan") via runuser/supervisord. fsGroup makes the
    # PVC group-writable for the mayan user. Do NOT add runAsNonRoot/runAsUser.
    securityContext:
      fsGroup: 1000
      fsGroupChangePolicy: OnRootMismatch

  controllers:
    mayan-edms:
      # RWO PVC on a single node: never run two pods at once.
      strategy: Recreate
      annotations:
        reloader.stakater.com/auto: "true"
      containers:
        main:
          image:
            repository: mayanedms/mayanedms
            tag: v4.12.1
          # No command/args: image default CMD `run_all` = setup-or-upgrade +
          # gunicorn + celery workers A-F + beat under supervisord.
          env:
            TZ: Etc/UTC
            # Wait for Postgres and the pod-local redis sidecar before setup.
            MAYAN_DOCKER_WAIT: "pg-mayan-edms-rw:5432 localhost:6379"
            # Celery broker / results / locks / server-side-events on the
            # pod-local redis, dbs 0/1/2/3 — upstream 4.12 compose layout.
            MAYAN_CELERY_BROKER_URL: "redis://localhost:6379/0"
            MAYAN_CELERY_RESULT_BACKEND: "redis://localhost:6379/1"
            MAYAN_LOCK_MANAGER_BACKEND: mayan.apps.lock_manager.backends.redis_lock.RedisLock
            MAYAN_LOCK_MANAGER_BACKEND_ARGUMENTS: "{'redis_url':'redis://localhost:6379/2'}"
            MAYAN_SERVER_SIDE_EVENTS_BACKEND: mayan.apps.server_side_events.sse_backends.redis.RedisServerEventStreamBackend
            MAYAN_SERVER_SIDE_EVENTS_BACKEND_ARGUMENTS: "{'url':'redis://localhost:6379/3'}"
            # --- single-node tuning (upstream defaults in parentheses) ---
            MAYAN_GUNICORN_WORKERS: "2"        # (3) async gevent workers
            MAYAN_GUNICORN_TIMEOUT: "300"      # (120) large uploads on slow disk
            MAYAN_WORKER_A_CONCURRENCY: "2"    # (4) interactive/fast tasks
            MAYAN_WORKER_B_CONCURRENCY: "2"    # (8) documents/OCR dispatch
            MAYAN_WORKER_C_CONCURRENCY: "2"    # (4) periodic/downloads
            MAYAN_WORKER_D_CONCURRENCY: "1"    # (2) long-running OCR
            MAYAN_WORKER_E_CONCURRENCY: "1"    # (4) search index/housekeeping
            MAYAN_WORKER_F_CONCURRENCY: "1"    # (1) per-file analysis
            # Optional extras (uncomment as needed):
            # MAYAN_APT_INSTALLS: "tesseract-ocr-deu"  # extra OCR languages
          envFrom:
            - secretRef:
                name: *chartName
          probes:
            startup:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 8000
                periodSeconds: 10
                failureThreshold: 90   # first boot runs migrations/fixtures (~15 min)
            liveness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 8000
                periodSeconds: 30
                timeoutSeconds: 10
            readiness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 8000
                periodSeconds: 15
          resources:
            requests:
              cpu: 250m
              memory: 1Gi
            limits:
              memory: 3Gi   # OCR spikes; node is memory-tight — see plan risks
          securityContext:
            allowPrivilegeEscalation: false
            # DEVIATION from the repo "drop ALL" standard, verified against
            # the v4.12.1 entrypoint.sh: it runs as root and needs to chown
            # the media dir (CHOWN) and drop to the mayan user via
            # runuser/supervisord (SETUID/SETGID). Dropping ALL breaks boot.
            capabilities:
              drop:
                - ALL
              add:
                - CHOWN
                - SETUID
                - SETGID
                - DAC_OVERRIDE
        redis:
          # Pod-local broker/result/lock/SSE store (repo sidecar standard,
          # see charts/langfuse). Flags mirror the upstream 4.12 compose
          # redis service: noeviction because locks/results/chord counters
          # are NOT cache; no persistence (queued tasks are expendable).
          # No password: only reachable inside this pod.
          image:
            repository: redis
            tag: 8.6.0
          args:
            - redis-server
            - --appendonly
            - "no"
            - --databases
            - "4"
            - --maxmemory
            - "100mb"
            - --maxclients
            - "500"
            - --maxmemory-policy
            - "noeviction"
            - --save
            - ""
            - --tcp-backlog
            - "256"
          probes:
            liveness:
              enabled: true
              custom: true
              spec:
                exec:
                  command: ["redis-cli", "ping"]
                periodSeconds: 10
            readiness:
              enabled: true
              custom: true
              spec:
                exec:
                  command: ["redis-cli", "ping"]
                periodSeconds: 5
          resources:
            requests:
              cpu: 10m
              memory: 50Mi
            limits:
              memory: 256Mi
          securityContext:
            # Run as the image's redis user (uid 999) so ALL capabilities can
            # be dropped: as root the image entrypoint would gosu-down, which
            # needs CAP_SETUID that drop-ALL removes. Nothing is persisted,
            # so the redis user needs no volume ownership.
            runAsUser: 999
            runAsGroup: 999
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  service:
    mayan-edms:
      controller: *chartName
      ports:
        http:
          port: 8000

  persistence:
    data:
      existingClaim: *chartName
      globalMounts:
        - path: /var/lib/mayan
```

### 3. `charts/mayan-edms/templates/pvc-mayan-edms-default.yaml` — CREATE

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mayan-edms
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      # Nominal size per user decision: local-path does not enforce quotas.
      # The grow node disk is small (~5.3Gi free) — real usage is bounded by
      # actual free space, not this number. See plan risks.
      storage: 20Gi
```

### 4. `charts/mayan-edms/templates/pg-mayan-edms.yaml` — CREATE

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-mayan-edms
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5-19-bookworm
  primaryUpdateStrategy: unsupervised
  storage:
    size: 5Gi
    storageClass: local-path

  monitoring:
    enablePodMonitor: true

  postgresql:
    parameters:
      # Adapted from the upstream Mayan compose postgres flags
      # (max_connections 150, statistics 200, maintenance_work_mem 128MB),
      # shared_buffers/work_mem scaled down for the memory-tight grow node.
      max_connections: "150"
      shared_buffers: 256MB
      work_mem: 16MB
      maintenance_work_mem: 128MB
      default_statistics_target: "200"
      checkpoint_completion_target: "0.6"

  bootstrap:
    initdb:
      database: mayan
      owner: mayan
      secret:
        name: pg-mayan-edms-secret
```

### 5. `charts/mayan-edms/templates/secret-pg-mayan-edms.yaml` — CREATE

Copy of the n8n shape (`charts/n8n/templates/secret-pg-n8n.yaml`) with the
names swapped:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: pg-mayan-edms-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: pg-mayan-edms-secret
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: {{ index .Values "bitwardenIds" "mayan-edms" }}
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: password
      remoteRef:
        key: {{ index .Values "bitwardenIds" "mayan-edms" }}
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 6. `charts/mayan-edms/templates/secret-mayan-edms.yaml` — CREATE

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mayan-edms
spec:
  refreshInterval: 1h
  target:
    name: mayan-edms
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # MAYAN_DATABASES embeds the password in a Python dict literal
        # (Django parses it with ast.literal_eval) — hence no plain
        # secretKeyRef, and the Bitwarden password must not contain
        # single quotes.
        MAYAN_DATABASES: "{'default':{'ENGINE':'django.db.backends.postgresql','NAME':'mayan','PASSWORD':'{{ `{{ .db_password }}` }}','USER':'{{ `{{ .db_username }}` }}','HOST':'pg-mayan-edms-rw'}}"
        MAYAN_AUTOADMIN_PASSWORD: "{{ `{{ .autoadmin_password }}` }}"
  data:
    - secretKey: db_username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "mayan-edms" }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: db_password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "mayan-edms" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: autoadmin_password
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "mayan-edms" }}'
        property: autoadmin_password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 7. `services/grow/prod/values.yaml` — MODIFY (two insertions)

a) Under `charts:` (after `external-secrets-bitwarden:`, before the
   `# External charts` comment), add the internal-chart entry:

```yaml
  mayan-edms:
    #version: 1.0.0 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
    #repository: https://ownyourio.github.io/SpencersLab/
    namespace: default
    ServerSideApply: "true"
```

b) Under `ingress.subdomains:` (alongside the existing `cluster:`/`traefik:`
   entries), add — key `edms` ≠ serviceName `mayan-edms` (paperless pattern;
   equal values would collide on the rendered `<name>-ingress` object names):

```yaml
    edms:
      serviceName: mayan-edms
      service: grow-mayan-edms
      port: 8000
```

### 8. `custom-values/grow/prod-values.yaml` — MODIFY

Add a per-app block (same shape as the existing `assistant:` block). Ask the
user for the Bitwarden item UUID (prerequisite above) — e.g. via the
`question` tool during implementation; do NOT invent a UUID:

```yaml
mayan-edms:
  bitwardenIds:
    mayan-edms: <UUID-of-the-mayan-edms-Bitwarden-LOGIN-item>
```

### 9. `services/proxy-local/prod/values.yaml` — MODIFY

Under `proxy.subdomains:`, in the own-auth group (next to `pictaria:`), add:

```yaml
    # Own auth (Mayan admin login) + hub Keycloak forward-auth (default userAuth).
    edms:
      target: mayan-edms
```

**Do NOT touch `services/proxy-remote/prod/values.yaml`** — the user
explicitly excluded the zerotrust edge.

### 10. Commit

`git add` the new chart directory + the three modified values files and commit
on the current branch (`add-mayan-edms-to-grow`). Never push to main; never
bump `version:` (release.yaml does that on merge).

## Verification

Run and show output for each (evidence before claims):

1. `helm dependency update charts/mayan-edms` → `Chart.lock` created.
2. `helm lint charts/mayan-edms` → no errors.
3. `helm template mayan-edms charts/mayan-edms --set domain=test.example.com --set bitwardenIds.mayan-edms=test-uuid`
   → renders; then pipe through `grep -c OVERRIDE` → must be **0** (sentinels
   resolved by the test values). Confirm in the output: Deployment with both
   containers + `strategy: Recreate`, Service port 8000, CNPG Cluster
   `pg-mayan-edms`, both ExternalSecrets, PVC 20Gi, and the
   `MAYAN_DATABASES` template line intact.
4. Trio grep checks:
   - `grep -n "mayan-edms" services/grow/prod/values.yaml` → charts entry + ingress entry
   - `grep -n "edms" services/proxy-local/prod/values.yaml` → proxy entry
   - `grep -n "mayan-edms" custom-values/grow/prod-values.yaml` → UUID block
   - `grep -rn "mayan-edms" services/proxy-remote/` → **no matches**
5. After the user merges (user-only step), watch ArgoCD via
   `readonly-grow-kubernetes`:
   - Application `grow-mayan-edms` Synced/Healthy
   - `pg-mayan-edms-1` pod Running, CNPG Cluster ready
   - `grow-mayan-edms-*` pod Running 2/2 — **first boot takes 5–15 minutes**
     (wait.py → initial setup → migrations → supervisord); the startup probe
     allows it. Check logs for `Executing initial_setup`, then gunicorn +
     worker_a..f + beat starting.
   - ExternalSecrets `mayan-edms` and `pg-mayan-edms-secret` Ready
   - `readonly-proxy-local-kubernetes`: Service `edms-service` (ExternalName →
     `mayan-edms.<domain>`), Ingress `edms-ingress`, IngressRoute
     `edms-local-ingress` exist.
6. Functional: browse `https://edms.<domain>` (LAN/mesh) → Mayan login page;
   log in as `admin` with the `autoadmin_password` value; upload a PDF and
   confirm preview + OCR text appear within a couple of minutes (exercises
   workers B/C/D and the lock manager).

## Risks & open questions

1. **Node resources are tight.** Memory: ~2.6Gi available of 12.5Gi; limits
   here (3Gi mayan + 1Gi PG implied + 256Mi redis) could OOM-kill under full
   OCR load — concurrency is already reduced; lower `limits.memory` to 2Gi if
   the node gets pressure. Disk: only ~5.3Gi free on the root disk backing
   local-path; the nominal 20Gi/5Gi PVCs are not enforced, real document
   capacity is a few GB until the grow VM disk is expanded (VM-level task,
   out of repo scope). Watch for node `DiskPressure`; the Mayan image pull
   itself consumes ~1.5Gi.
2. **Redis sidecar uid assumption (999).** Standard for debian-based redis
   images, but unverified for `redis:8.6.0` specifically. If the sidecar
   crashloops with permission errors, fall back to the langfuse shape (remove
   the sidecar `securityContext` block entirely).
3. **Bitwarden item must exist before secrets go Ready.** If the ExternalSecrets
   stay `SecretSyncedError`, the item/UUID/custom-field name is wrong — the
   password must also contain no single quotes.
4. **Mesh DNS for `mayan-edms.<domain>`** relies on the same (infra-level)
   mechanism that resolves `paperless.<domain>` for the hub ExternalName. If
   `edms.<domain>` 404s from the hub while the grow ingress exists, compare
   DNS behavior with `paperless.spencerslab.com` and mirror whatever record
   exists for it (may need a manual DNS entry — flag to the user, do not
   improvise infra).
5. **No public access by design** (no proxy-remote entry). External users get
   nothing at `edms.<domain>`; LAN/mesh users get hub Keycloak forward-auth +
   Mayan's own login.
6. First-boot duration and upgrade path: image tag bumps run migrations
   automatically under `Recreate`; Mayan minor releases occasionally require
   stepping through intermediate versions — read release notes before
   accepting future renovate bumps.

## Implementation addendum (2026-09-12, code agent)

Implemented as planned with ONE deviation, required by the user's
instruction that the DB username must come from the Bitwarden item ("use
whatever is in bitwarden" — the item's username is not guaranteed to be
`mayan`):

**Deviation: CNPG bootstrap uses `postInitSQLRefs` instead of
`owner:` + bootstrap secret.**

- Verified in CNPG source (1.28): the initdb job creates the owner role from
  the STATIC `spec.bootstrap.initdb.owner` field (`pkg/specs/jobs.go` passes
  `--app-user <Owner>`), and the instance controller's `reconcileUser`
  hard-fails with `wrong username '%v' in secret, expected '%v'` when the
  bootstrap secret's username differs from `owner`
  (`internal/management/controller/instance_controller.go`). A static owner
  therefore cannot satisfy "whatever username is in Bitwarden".
- Replacement (implemented):
  - `templates/pg-mayan-edms.yaml`: `bootstrap.initdb` sets no
    database/owner/secret; instead `postInitSQLRefs.secretRefs` →
    `pg-mayan-edms-initdb-sql` / `init.sql`. CNPG's defaulting webhook adds
    an unused `app` db/user alongside (harmless, documented in the template).
  - `templates/secret-pg-mayan-edms-initdb-sql.yaml` (replaces the planned
    `secret-pg-mayan-edms.yaml`): ExternalSecret (bitwarden-login,
    username+password) rendering
    `CREATE ROLE "<user>" LOGIN PASSWORD '<pw>'; CREATE DATABASE mayan OWNER "<user>";`
    executed once as superuser during bootstrap. Multi-statement execution
    verified safe (CNPG e2e fixture `cluster_post_init_secret.yaml` runs a
    multi-statement file through the same code path; argument-less pgx Exec
    uses the simple protocol → per-statement autocommit, which CREATE
    DATABASE requires). The initdb job pod waits for the secret (volume
    mount) until external-secrets syncs it — same ordering semantics as a
    bootstrap secret.
  - Constraints documented in the templates: Bitwarden username must not
    contain a double quote; password must not contain a single quote (the
    latter was already required for the MAYAN_DATABASES dict literal).
  - Trade-off: CNPG does not manage the mayan role afterwards — rotating the
    Bitwarden password will NOT auto-sync to the PG role (it does re-render
    MAYAN_DATABASES). Acceptable: Reloader is not deployed on grow, so app
    secret rotation already needs a pod restart anyway.
- Bitwarden item UUID used: `f7b628ec-2544-4c28-a476-b1a501487d99`
  (custom-values/grow/prod-values.yaml, `mayan-edms:` block, assistant shape).

Verification evidence (all fresh, 2026-09-12):
- `helm lint charts/mayan-edms` → 0 failed (icon INFO only).
- `helm template grow-mayan-edms charts/mayan-edms --set domain=… --set
  bitwardenIds.mayan-edms=…` → exit 0; resources: ServiceAccount, PVC
  `mayan-edms` 20Gi, Service `grow-mayan-edms`:8000, Deployment
  `grow-mayan-edms` (strategy Recreate, containers main+redis, fsGroup 1000,
  redis uid 999, capabilities as specified), Cluster `pg-mayan-edms`,
  ExternalSecrets `mayan-edms` + `pg-mayan-edms-initdb-sql`;
  `grep -c OVERRIDE_VIA` = 0.
- Render with the real custom-values slice (`mayan-edms:` block as values
  file) → all 5 remoteRefs carry the real UUID, 0 sentinels.
- Trio greps: grow charts entry + `edms` ingress entry present; proxy-local
  `edms: target: mayan-edms` present; custom-values block present;
  `grep -rn mayan-edms services/proxy-remote/` → no matches.
- Custom-values plumbing confirmed against the live mechanism: grow-appset
  loads custom-values/grow/prod-values.yaml as a values file for the base
  chart; appset-charts.yaml feeds `index $.Values "mayan-edms"` to the
  chart's Application (same path as the working `assistant` block).

## Implementation addendum 2 (2026-09-13, user code review)

User review directed a redesign that supersedes addendum 1's
postInitSQLRefs approach:

1. **Secret split** (new repo naming pattern `<service>` / `<service>-db` /
   `<service>-sso`, codified in the helm-chart-creation skill):
   - `mayan-edms` item (`f7b628ec-…`, shared admin item, per user): its
     regular LOGIN password is the initial Mayan admin password —
     `MAYAN_AUTOADMIN_PASSWORD` now reads `bitwarden-login`/`password`,
     no custom field.
   - `mayan-edms-db` item (`6257199f-e9fe-458e-b247-b4c50004a3b0`,
     dedicated): DB credentials; username must be `mayan-edms`.
2. **Init script removed**: CNPG bootstrap reverted to the standard repo
   pattern — `initdb: {database: mayan-edms, owner: mayan-edms,
   secret: pg-mayan-edms-secret}` (database/owner named after the chart,
   like n8n/langfuse/home-assistant). This also resolves the review's
   SQL-injection-sink and stuck-bootstrap findings (CNPG handles
   credential quoting/validation natively).
3. Chart changes: `values.yaml` bitwardenIds has two entries;
   `templates/secret-pg-mayan-edms-initdb-sql.yaml` deleted;
   `templates/secret-pg-mayan-edms.yaml` recreated (reads mayan-edms-db);
   `templates/secret-mayan-edms.yaml` reads db creds from mayan-edms-db
   and the autoadmin password from mayan-edms; `MAYAN_DATABASES` NAME is
   now `mayan-edms`.
4. Remaining review item NOT yet addressed: `max_connections: 150`
   (pg-mayan-edms.yaml) vs ~25 real clients — flagged WARNING in the
   branch review; left as-is pending user decision.

Verification (fresh, 2026-09-13): helm lint 0 failed; helm template with
both test UUIDs renders all resources, 0 OVERRIDE_VIA sentinels, CNPG
bootstrap database/owner/secret correct, ExternalSecret refs split
correctly (db creds ← mayan-edms-db, autoadmin ← mayan-edms password).
