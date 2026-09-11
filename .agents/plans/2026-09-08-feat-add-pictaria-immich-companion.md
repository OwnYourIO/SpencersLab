# Plan: Add Pictaria Server (Immich companion) to home services

## Goal

Deploy [Pictaria Server](https://github.com/pictaria-ai/pictaria-server) v1.1.0
on the home cluster as release `home-pictaria`, connected to the existing Immich
library, reachable at `pictaria.spencerslab.com` — through the proxy-local hub
(Keycloak forward-auth + crowdsec for remote/zerotrust traffic) and directly via
the home cluster ingress on the LAN. Pictaria is a single-container Node app
(photo insights, AI enrichment, curation, smart albums for Immich); all state
lives in one `/data` volume. It authenticates with its own shared
`APP_PASSWORD` (no SSO support) and talks to Immich via API key.

## Skills

Code agent must load (fresh session):

- `helm-chart-creation` — repo chart/service wiring workflow, sentinels, validation
- `helm-bjw-s-chart` — app-template v5 values API

## MCP Servers

- `home-readonly-kubernetes` — verify Application, pod, ExternalSecret, PVC, logs
- `home-admin-kubernetes` — only if remediation is needed (delete/restart pod);
  requires explicit user confirmation before use
- `global-searxng` — only if upstream docs (CONFIGURATION.md, GETTING-STARTED.md)
  need re-checking

Note: the home cluster API was intermittently flaky during planning
(`apiserver not ready` on one read). Retry transient failures before concluding
anything is broken.

## Verified context

Recon performed 2026-09-08 against this worktree + live home cluster:

- **Upstream** (fetched from GitHub):
  - Latest release **v1.1.0** (2026-09-04). Image
    `ghcr.io/pictaria-ai/pictaria-server:1.1.0` (image tags omit the `v`;
    multi-arch amd64/arm64, verified digest
    `sha256:a82cb5f318dc3bef32fd0457c8b23615edc3baee1909b663e483227c52b711c9`).
  - Dockerfile: `USER node` (UID/GID 1000), `EXPOSE 4080`, `VOLUME /data`, all
    state paths pre-set to `/data/*` via ENV, HEALTHCHECK `GET /api/health`.
  - `.env.example`: required `IMMICH_BASE_URL`, `IMMICH_API_KEY`;
    `APP_PASSWORD` required to boot (refuses start without it unless
    `ALLOW_INSECURE_OPEN=true`); optional reverse-proxy hardening
    `BROWSER_ALLOWED_HOSTS`, `TRUSTED_PROXY_IPS`, `SESSION_COOKIE_SECURE`.
  - Requires Immich ≥ 2.0. Home chart pins immich `v3.1.0`
    (`charts/immich/values.yaml`); live Service labels still show v2.6.3 —
    either satisfies the floor.
  - Reverse-proxy guidance: preserve the browser-facing `Host` header (traefik
    does this by default), set `BROWSER_ALLOWED_HOSTS` for public custom
    domains, `SESSION_COOKIE_SECURE=true` when HTTPS-only, `TRUSTED_PROXY_IPS`
    to the proxy's narrow network for per-client login lockout.
- **No official Helm chart** — ArtifactHub search for "pictaria" returns
  nothing → custom chart (decision tree in helm-chart-creation).
- **Live home cluster** (`home-readonly-kubernetes`): Service
  `home-immich-server` exists in `default`, port `2283/TCP` →
  `IMMICH_BASE_URL=http://home-immich-server:2283`. Immich's public subdomain
  is `pictures` (`services/home/prod/values.yaml` ingress + proxy-local
  `pictures: target: immich`) → `IMMICH_PUBLIC_URL=https://pictures.<domain>`.
- **Wiring patterns confirmed by reading**:
  - `charts/` entries in `services/home/prod/values.yaml` become standalone
    Applications named `home-<appName>` (charts-appset in base); proxy entries
    reference `service: home-<appName>`.
  - Secret pattern: `charts/qdrant/templates/secret-qdrant.yaml` +
    `charts/langfuse/templates/secret-langfuse.yaml` (bitwarden-login for
    password, bitwarden-fields for custom fields, helm-rendered static keys in
    `target.template.data`).
  - PVC pattern: `charts/qdrant/templates/pvc-qdrant-default.yaml` —
    plain PVC, namespace default, RWO, no storageClassName (local-path).
  - proxy-local hub: bare `proxy.subdomains.<name>` entry renders ExternalName
    `<name>-service` → `<target|name>.<domain>` + public ingress with default
    middlewares crowdsec + Keycloak forward-auth (`userAuth`) + LAN
    IngressRoute (templates/proxy/*). Same shape as `sms:`/`git:`.
  - `custom-values/home/prod-values.yaml` carries per-app `bitwardenIds` blocks
    (e.g. `rallly:`, `playsms:`) that merge into the app's values slice.
  - Home trusted-proxy convention: `trustedIPs: ["10.42.0.0/24", "10.0.77.0/24"]`
    (single-node K3s pod subnet + LAN), already used by actualbudget.
- **Render checks**: performed during implementation per Verification section
  (chart does not exist yet).

## Design decisions

1. **Custom chart `charts/pictaria`** — no official chart exists; app is a
   single container, so a thin app-template wrapper (qdrant tier) suffices. No
   PostgreSQL (Pictaria uses SQLite files in `/data`).
2. **Category: home, standalone Application** via `charts:` key (like immich,
   rallly), not an umbrella dependency — release `home-pictaria`, service name
   `home-pictaria`, matching proxy convention.
3. **Immich connection**: cluster-local `http://home-immich-server:2283`
   (verified Service) for API traffic; browser deep links go to
   `https://pictures.<domain>` via `IMMICH_PUBLIC_URL`. Domain-derived values
   live in the ExternalSecret template (repo rule: domain refs in secret
   templates, `.Values.domain` injected by the appset).
4. **Auth posture (user-confirmed)**: Keycloak forward-auth at the proxy-local
   hub (default `userAuth` middlewares — bare entry, like `sms:`/`git:`) plus
   Pictaria's own `APP_PASSWORD` as second layer. LAN traffic bypasses the hub
   (mesh DNS → home traefik) and is gated by the app password alone.
   Consequence: non-browser clients (e.g. a future Pictaria Frame connecting
   from outside the LAN) cannot pass Keycloak — revisit only if that happens.
5. **Secrets**: ONE Bitwarden Login item `pictaria` — its password field is
   `APP_PASSWORD`, custom field `immich_api_key` holds the Immich API key.
   ExternalSecret reads `bitwarden-login` (property `password`) and
   `bitwarden-fields` (property `immich_api_key`) from the same item UUID.
6. **Proxy hardening env**: `SESSION_COOKIE_SECURE=true` (every path is HTTPS:
   hub TLS + home ingress wildcard-cert), `BROWSER_ALLOWED_HOSTS=pictaria.<domain>`
   (DNS-rebinding allowlist), `TRUSTED_PROXY_IPS=10.42.0.0/24` (home traefik
   pod subnet; repo's established trustedIPs convention; keeps login-lockout
   per-client instead of one shared bucket behind the proxy).
7. **Storage**: new 5Gi RWO PVC `pictaria` at `/data` (app-data tier; SQLite
   DBs + settings + built-in backup snapshots). Off-volume `BACKUP_DIR`
   (docs/BACKUP.md recommendation) is a future enhancement, out of scope.
8. **Security context**: pod runAsUser/runAsGroup/fsGroup 1000 (image `node`
   user owns `/data`), `fsGroupChangePolicy: OnRootMismatch`; container drops
   ALL caps, `readOnlyRootFilesystem: true` with an emptyDir `/tmp` (all app
   writes target `/data`). If the app misbehaves with a read-only rootfs, drop
   that flag — noted in Risks.
9. **Image pinning**: `tag: 1.1.0` with renovate docker-datasource annotation
   (`depName=ghcr.io/pictaria-ai/pictaria-server`) — image tags have no `v`
   prefix, so the github-releases datasource would mismatch.
10. **Subdomain**: `pictaria` → `pictaria.spencerslab.com` (name == app ==
    target, so no `serviceName` alias needed, unlike immich's `pictures`).

## Changes

Ordered; each step is one file.

### 1. `charts/pictaria/Chart.yaml` — CREATE

```yaml
apiVersion: v2
name: pictaria
version: 1.0.0
appVersion: 1.1.0
dependencies:
- name: app-template
  version: 5.0.1
  repository: https://bjw-s-labs.github.io/helm-charts/
```

### 2. `charts/pictaria/values.yaml` — CREATE

```yaml
bitwardenIds:
  pictaria: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

# Pictaria Server — photo insights/enrichment/curation companion for Immich
# (pictaria-ai/pictaria-server). Single Node container; ALL state lives in
# /data (SQLite DBs, settings, frame DB, wake-word models, backup snapshots).
app-template:
  global:
    nameOverride: &chartName pictaria

  controllers:
    pictaria:
      annotations:
        reloader.stakater.com/auto: "true"
      pod:
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
          runAsNonRoot: true
          fsGroup: 1000
          fsGroupChangePolicy: OnRootMismatch
      containers:
        main:
          image:
            # renovate: datasource=docker depName=ghcr.io/pictaria-ai/pictaria-server
            repository: ghcr.io/pictaria-ai/pictaria-server
            tag: 1.1.0
          env:
            TZ: America/Denver
            HOST: 0.0.0.0
            PORT: "4080"
            # Cluster-local Immich server endpoint (same namespace, verified
            # Service home-immich-server:2283). Browser-facing deep links use
            # IMMICH_PUBLIC_URL from the ExternalSecret instead.
            IMMICH_BASE_URL: http://home-immich-server:2283
            # Pictaria is only ever reached through HTTPS reverse proxies
            # (hub traefik + home traefik), so mark the session cookie Secure.
            SESSION_COOKIE_SECURE: "true"
            # Home cluster pod subnet (single-node K3s) — the direct peer is
            # the home traefik pod. Same convention as custom-values
            # trustedIPs. Enables per-client login lockout behind the proxy.
            TRUSTED_PROXY_IPS: 10.42.0.0/24
          envFrom:
            - secretRef:
                name: *chartName
          probes:
            liveness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /api/health
                  port: 4080
            readiness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /api/health
                  port: 4080
            startup:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /api/health
                  port: 4080
                failureThreshold: 30
                periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 1Gi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL

  service:
    main:
      controller: *chartName
      ports:
        http:
          port: 4080

  persistence:
    data:
      existingClaim: *chartName
      globalMounts:
        - path: /data
    tmp:
      type: emptyDir
      globalMounts:
        - path: /tmp
```

### 3. `charts/pictaria/templates/secret-pictaria.yaml` — CREATE

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: pictaria
spec:
  refreshInterval: 1h
  target:
    name: pictaria
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        APP_PASSWORD: "{{ `{{ .app_password }}` }}"
        IMMICH_API_KEY: "{{ `{{ .immich_api_key }}` }}"
        # DNS-rebinding allowlist: only the public custom domain may serve the
        # browser UI. Domain is injected by the ApplicationSet.
        BROWSER_ALLOWED_HOSTS: "pictaria.{{ .Values.domain }}"
        # Browser-facing Immich URL for deep links (the server itself uses the
        # cluster-local IMMICH_BASE_URL from values.yaml).
        IMMICH_PUBLIC_URL: "https://pictures.{{ .Values.domain }}"
  data:
    - secretKey: app_password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "pictaria" }}'
        property: password
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: immich_api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "pictaria" }}'
        property: immich_api_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 4. `charts/pictaria/templates/pvc-pictaria-default.yaml` — CREATE

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pictaria
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

### 5. Generate `charts/pictaria/Chart.lock`

Run: `helm dependency update charts/pictaria`

### 6. `services/home/prod/values.yaml` — MODIFY (two insertions)

Under `charts:` (alphabetical position is not enforced; place near `immich:`):

```yaml
  pictaria:
    #version: 1.0.0 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
    #repository: https://ownyourio.github.io/SpencersLab/
    namespace: default
    ServerSideApply: "true"
```

Under `ingress.subdomains:` (e.g. after `pictures:`):

```yaml
    pictaria:
      service: home-pictaria
      port: 4080
```

No top-level `pictaria:` values block is needed — chart defaults carry
everything; the custom-values block (step 8) supplies the Bitwarden UUID.

### 7. `services/proxy-local/prod/values.yaml` — MODIFY

Under `proxy.subdomains:` (with the other own-auth apps, e.g. after `sms:`):

```yaml
    # Own auth (APP_PASSWORD) + hub Keycloak forward-auth (default userAuth).
    pictaria:
      target: pictaria
```

Bare entry = default middlewares (crowdsec + Keycloak forward-auth) on both
the public ingress and the LAN IngressRoute; ExternalName `pictaria-service` →
`pictaria.<domain>`; external-dns publishes `pictaria.<domain>` CNAME →
`proxy-remote.<domain>`.

### 8. `custom-values/home/prod-values.yaml` — MODIFY (gated on user input)

Append (real UUID — this file is where sentinels get resolved):

```yaml
pictaria:
  bitwardenIds:
    pictaria: <UUID of the Bitwarden item "pictaria">
```

**Prerequisites the USER must complete before this step** (the Code agent
cannot create Bitwarden items or Immich API keys — ask the user for the UUID
and stop here if not yet available):

1. Create Bitwarden item `pictaria` (type **Login**):
   - password field = a strong `APP_PASSWORD` (this is the password typed at
     the Pictaria login screen),
   - custom field `immich_api_key` = the Immich API key.
2. Create the Immich API key: Immich web UI → Account Settings → API Keys.
   Least-privilege permissions: follow the checklist in Pictaria's
   `docs/GETTING-STARTED.md` (full access is not required).

## Verification

1. **Chart**: `helm lint charts/pictaria` and
   `helm template charts/pictaria --debug` pass.
2. **Rendering**:
   `helm template pictaria charts/pictaria --set domain=test.example.com --set bitwardenIds.pictaria=test-uuid`
   — valid manifests; grep the output for `OVERRIDE_` → zero hits; confirm
   `BROWSER_ALLOWED_HOSTS: "pictaria.test.example.com"` and
   `IMMICH_PUBLIC_URL: "https://pictures.test.example.com"` rendered.
3. **Integration trio (+secrets)**:
   `grep -rn "pictaria" services/home/prod/values.yaml services/proxy-local/prod/values.yaml custom-values/home/prod-values.yaml`
   shows: `charts:` entry, home ingress entry (`home-pictaria`/4080),
   proxy-local entry, and the custom-values UUID block.
4. **File presence**: Chart.yaml, Chart.lock, values.yaml,
   templates/secret-pictaria.yaml, templates/pvc-pictaria-default.yaml.
5. **After merge + ArgoCD sync** (home-readonly-kubernetes):
   - Application `home-pictaria` Synced/Healthy; PVC `pictaria` Bound;
     ExternalSecret `pictaria` Ready; Secret `pictaria` exists with 4 keys.
   - Pod Running 1/1, no restarts; logs show successful Immich connection
     (no `IMMICH_API_KEY`/boot errors).
   - `GET /api/health` on the pod/service returns
     `{"ok":true,...,"authRequired":true}`.
   - Browser: `https://pictaria.spencerslab.com` → Keycloak login (remote
     path) → Pictaria password prompt → Insights dashboard loads; Immich deep
   - links point at `pictures.spencerslab.com`.

## Risks & open questions

- **readOnlyRootFilesystem**: assumed all writes target `/data` or `/tmp`
  (Dockerfile sets every state path under `/data`). If the pod crash-loops on
  file writes, remove `readOnlyRootFilesystem: true` (keep the `/tmp` mount).
- **TRUSTED_PROXY_IPS=10.42.0.0/24** assumes the home traefik pod sits in the
  single-node pod subnet (same convention as the existing `trustedIPs` used by
  actualbudget). If home ever gains nodes, widen to the new node's pod subnet.
- **Immich version skew**: chart pins v3.1.0, live labels show v2.6.3 — both
  satisfy Pictaria's ≥2.0 floor, but check
  `docs/IMMICH-COMPATIBILITY.md` before future Immich upgrades.
- **Remote non-browser clients blocked by design**: Keycloak forward-auth on
  the hub path stops anything that can't do browser SSO (relevant only if a
  Pictaria Frame later needs WAN access — switch the entry to
  `middlewares: "kube-system-crowdsec@kubernetescrd"` + matching
  `ingressRoute.middlewares` at that point, per user decision).
- **Backups**: automatic snapshots land in `/data/backups` (same PVC).
  Off-volume `BACKUP_DIR` (recommended upstream) is a follow-up, not in scope.
- **Home cluster API flakiness** observed during planning (transient
  `apiserver not ready`) — retry reads before treating them as failures.
- AI enrichment providers (Ollama/OpenAI/etc.), voice, weather, geocoding are
  all runtime-configurable in Pictaria's web UI (Settings → AI Providers) —
  deliberately NOT wired via env; out of scope for deployment.

## Implementation note (2026-09-08)

**Deviation from design decision #5 (user-directed):** Instead of one combined
Bitwarden Login item, the user provided TWO separate Login items:
- `pictaria` (a2dae3be-43c3-4881-8172-b4bf0031366d) — password field = APP_PASSWORD
- `pictaria-immich` (8ef66a15-3efb-4854-85b1-b4bf0030a214) — password field = Immich API key

The ExternalSecret template was updated accordingly: both `data` entries use
`bitwarden-login` store with `property: password`, each referencing its own
`bitwardenIds` key. The `bitwardenIds` map in values.yaml now has two entries.

## Post-deploy fix: job runs cancelled by probe kills (2026-09-09)

Symptom: kicking off a Pictaria enrichment job showed no activity and the run
was cancelled; pod had 3 restarts. Events proved the cause:
`Liveness probe failed: ... context deadline exceeded` →
`Container main failed liveness probe, will be restarted` — each container
lived ~3 min (job duration) and exited 0 on SIGTERM.

Root cause: during a job the Node process stalls (Immich asset download +
image processing), so `/api/health` could not answer within the default probe
`timeoutSeconds: 1`; three failures in 30s → kubelet kills the container
mid-job → run cancelled. The 1-CPU limit amplified the stalls.

Fix in `charts/pictaria/values.yaml`:
- liveness + readiness: `timeoutSeconds: 10`, `periodSeconds: 15`,
  `failureThreshold: 8` (tolerates ~2 min of event-loop stall)
- CPU limit `1` → `2` (requests unchanged)

This change alters the pod template, so ArgoCD rolls the Deployment
automatically — no manual restart needed. llama-swap side verified healthy at
the time: `qwen3-vl-30b-a3b-q8` running/ready, `/v1/models` reachable
unauthenticated from outside the cluster.

## Post-deploy fix 2: v1.1.0 blocks the event loop at job start (2026-09-11)

Symptom persisted after the probe fix: enhance job kicked off → no activity →
run cancelled. The pod (new ReplicaSet with the lenient probes + 2 CPUs)
still restarted: previous container ran 4h idle, then was killed ~2-3 min
after the job started (liveness failures at 04:47:30, exit 137). The previous
container's log contained ONLY the startup line — v1.1.0 logs nothing about
jobs, and /api/health stayed unresponsive for the entire >2 min probe window,
i.e. the Node event loop is hard-blocked from job start.

Root cause: v1.1.0 walks the whole Immich library synchronously at the start
of every sweep; on a large library that blocks the event loop for minutes,
which no realistic liveness config can survive.

Fix: **upgrade to pictaria-server 1.2.0** (released 2026-09-11):
- "Faster library sweeps: a resumable local inventory avoids repeatedly
  walking already-enriched photos" — directly targets this stall.
- Adds a performance inspection page (run/photo timings, timeouts, retries) —
  replaces the total log silence for future debugging.
- Chart changes: `tag: 1.1.0 → 1.2.0`, `appVersion: 1.2.0` (chart `version`
  untouched — CI bumps it). Lenient probes kept: the first inventory build
  may still take a while.

**Upgrade caveat (from release notes):** v1.2.0 migrates stored data
(schema 7→12, settings 6→7, contract 8→15). Startup creates a complete
pre-migration recovery snapshot automatically; rollback requires restoring
that snapshot with the older build. A verified Pictaria backup before the
rollout is recommended.
