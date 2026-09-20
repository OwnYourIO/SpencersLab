# Plan: Add MediaManager, LazyLibrarian, AudioBookRequest & MinusPod to the media cluster

## Goal

Deploy four new media apps on the media cluster via this repo's GitOps
standards: **MediaManager** (Sonarr/Radarr/Overseerr replacement, backed by a
new CloudNativePG PostgreSQL 17 cluster), **LazyLibrarian** (ebooks/audiobooks
requests), **AudioBookRequest** (audiobook wishlist layer in front of
Prowlarr + Audiobookshelf), and **MinusPod** (podcast processing / clean RSS
feeds; CPU image with Whisper offloaded to Groq and LLM to Anthropic — the
media node has no GPU). Each is a new custom chart under `charts/` wired
through `services/media/prod/values.yaml` (charts entry + ingress subdomain),
with Bitwarden ExternalSecrets for MediaManager and MinusPod, and
Keycloak OIDC wired for MediaManager (AudioBookRequest gets OIDC via its
Settings UI; LazyLibrarian/MinusPod have no SSO support). The existing *arr stack
(sonarr/radarr/readarr/lidarr/prowlarr/jellyseerr) stays untouched and runs in
parallel. Download clients (qBittorrent/SABnzbd) are explicitly out of scope.

## Skills

The Code agent must load (fresh session):

- `helm-chart-creation` — repo chart/service-wiring workflow (primary)
- `helm-bjw-s-chart` — app-template values API
- `gitops-workflows` — ArgoCD/ApplicationSet/secrets-in-git context
- `kubernetes-skill` — manifest authoring review

## MCP Servers

- `readonly-media-kubernetes` — inspect cluster state (Services, PVCs,
  ApplicationSets, pod status/logs) during and after implementation.
- `admin-media-kubernetes` — ONLY if cluster mutations become necessary
  (e.g. force-sync a stuck Application); the Code agent must ask the user for
  explicit confirmation before using it. GitOps is the preferred path —
  ArgoCD syncs everything.

## Verified context

**Repo recon (all paths read, not guessed):**

- `services/media/prod/values.yaml` — `charts:` map (git-path entries have no
  `version`/`repository`), `ingress.subdomains` consumed by
  `templates/generic-ingress.yaml`; existing *arr config blocks + proxy
  entries (`service: media-<name>`).
- `services/media/prod/Chart.yaml` — media umbrella: bubylou Arr-Stack charts
  + app-template 5.0.1 aliases (jellyfin, audiobookshelf). **Not touched** —
  new apps use the modern `charts:`-entry pattern instead.
- `services/media/prod/templates/generic-ingress.yaml` — per subdomain key
  renders Ingress `<key>-ingress` (host `<key>.<domain>`, mesh-only); if
  `serviceName` is set it renders a SECOND Ingress `<serviceName>-ingress`
  (host `<serviceName>.<domain>`, external-dns published). **If key ==
  serviceName both documents get the same name — collision.** New entries
  therefore omit `serviceName`.
- `charts/base/templates/appset-charts.yaml` — `charts:` entries without
  `version` → git path source `charts/<appName>`; release name
  `<serviceName>-<appName>`; injects helm params `domain`, `clusterName`,
  `serviceName`, `appName`, `namespace`; values slice =
  `merge({shared-storage}, .Values.<appName>)`.
- `charts/tvheadend/` — newest media-category custom chart (reference):
  app-template 5.0.1 dependency, `global.nameOverride`, LSIO env,
  `existingClaim` persistence + `templates/pvc-<name>-default.yaml`, no
  ingress block (umbrella generic-ingress does that).
- `charts/n8n/` — CNPG reference: `templates/pg-n8n.yaml`
  (`postgresql.cnpg.io/v1 Cluster`, `local-path`, initdb owner == Bitwarden
  username), `templates/secret-pg-n8n.yaml` (ExternalSecret, bitwarden-login),
  `templates/secret-n8n.yaml` (templated env secret with domain construction).
- `charts/qdrant/templates/secret-qdrant.yaml` — bitwarden-fields custom-field
  pattern (per-entry `sourceRef.storeRef`).
- `services/grow/prod/values.yaml:71-75` — cloudnative-pg operator as direct
  external chart entry: `version: 0.27.1`,
  `repository: https://cloudnative-pg.github.io/charts`,
  `ServerSideApply: "true"`.
- `.gitignore` — `charts/**/charts` ignored: commit `Chart.lock`, never the
  vendored tarball dir.
- `custom-values/media/prod-values.yaml` — per-app blocks
  (`<appName>: bitwardenIds: ...`); `argocd-mcp: ""` + TODO comment is the
  accepted pattern for not-yet-created Bitwarden items.

**Live media cluster (readonly-media-kubernetes, 2026-09-20):**

- Single node `media`; everything in namespace `default`.
- Services present: `media-prowlarr:9696`, `media-audiobookshelf:8080`,
  `media-jellyfin:8096`, plus sonarr/radarr/readarr/lidarr/jellyseerr/
  tvheadend. → Prowlarr + Audiobookshelf integration targets exist.
- StorageClasses: `local-path` (default, RWO — right for SQLite/config) and
  `seaweedfs-storage`. Shared PVC `media` (SeaweedFS CSI, RWX, PV path
  `/buckets/media`) already mounted by jellyfin/audiobookshelf/*arr.
- **No CNPG CRD** (`postgresql.cnpg.io/v1 Cluster` unknown) → operator must be
  added. No qBittorrent/SABnzbd anywhere.
- SecretStores ready: `bitwarden-login`, `bitwarden-fields`,
  `bitwarden-notes`, `bitwarden-uri` (external-secrets.io/v1, all Ready).
- ApplicationSets: `media-appset` (umbrella), `media-charts-appset`
  (per-app) — both live.

**Image tags verified against registries (2026-09-20):**

- `quay.io/maxdorninger/mediamanager:1.12.3` — exists; only semver tag =
  latest stable (rest are sha-/dev-/pr- builds).
- `lscr.io/linuxserver/lazylibrarian:version-58c3b076` — newest
  `version-<sha>` tag (pushed 2026-09-20).
- `markbeep/audiobookrequest:1.10.7` — exists (pushed 2026-08-21), newest
  semver.

**MinusPod additions (second pass, 2026-09-20):**

- Docker Hub `ttlequals0/minuspod`: `2.95.3-cpu` exists (pushed 2026-09-05)
  and matches the current `stable-cpu` channel; edge `-cpu` tags are already
  at 2.97.x and land several per day.
- Media node capacity (readonly inspection): **4 CPU, 30.6Gi allocatable RAM
  (~18.5Gi available)**, node filesystem **75GB total with only ~16.5GB
  available** — container images and all local-path PVCs share it. **No GPU**
  (no nvidia labels) → the guide's GPU topology C is impossible here.
- Existing local-path PVCs are all 1–5Gi; `media` is the SeaweedFS RWX claim.
  rancher local-path does **not enforce** PVC capacity — sizes are advisory on
  the shared disk.
- bjw-s values schema: deployment `strategy` defaults to `Recreate` — setting
  it explicitly just documents the SQLite/single-writer intent.
- app-template stays at **5.0.1** (repo standard — every chart pins it); the
  guide's 5.0.1-vs-5.1.0 caveat is moot for this repo.

**SSO/OIDC support research (upstream docs, 2026-09-20):**

| App | Native OIDC/SSO | Details |
|---|---|---|
| MediaManager | **Yes** | `[auth.openid_connect]` in config.toml (`enabled`, `client_id`, `client_secret`, `configuration_endpoint`, `name`); Keycloak named as supported; redirect URI `<frontend_url>/api/v1/auth/oauth/callback`; all keys also settable via `MEDIAMANAGER_AUTH__OPENID_CONNECT__*` env overrides. |
| AudioBookRequest | **Yes** | Configured in the UI (Settings → Security): well-known endpoint, username claim, group claim (`untrusted`/`trusted`/`admin`), scope, client id/secret; redirect path `/auth/oidc`; Keycloak realm URL form documented; lockout escape hatch `/login?backup=1`. UI-config = stored in its own DB, no chart plumbing. |
| LazyLibrarian | **No** | Local user accounts only (admin/friend/guest, session cookies, email-based provisioning). No OIDC, no proxy-auth-header mode documented. |
| MinusPod | **No** | Full `.env.example` reviewed: app password + session cookies, feed-auth subscriber credentials, setup token. No OIDC/SSO variables exist. |

Lab SSO context: Keycloak runs on the infra cluster (`charts/keycloakx`,
ingress `login.<domain>`, realm `SpencersLab` — already consumed from the
media cluster by hivetools `mcp-sso`); repo convention for app-level SSO is a
`<service>-sso` Bitwarden item + a Keycloak client. Mesh-only ingress keeps
all four apps behind zerotrust mesh access regardless.

**Render checks:** not yet performed — Code agent runs them per Verification.

## Design decisions

1. **Three custom charts + `charts:` entries** (not umbrella dependencies):
   repo direction of travel; matches `tvheadend` (latest media example).
   Umbrella Chart.yaml stays untouched. Releases become `media-mediamanager`,
   `media-lazylibrarian`, `media-audiobookrequest`; Services get exactly those
   names, so ingress `service:` fields use them.
2. **MediaManager DB = CNPG**: repo standard for PostgreSQL. Operator added as
   the same direct external chart entry grow uses (values-only, no secrets →
   allowed per helm-chart-creation rules); the `pg-mediamanager` Cluster lives
   in the mediamanager chart (n8n pattern). PostgreSQL 17 via the repo-proven
   image `ghcr.io/cloudnative-pg/postgresql:17.5-19-bookworm`.
3. **MediaManager config split** (per guide + repo gotchas): non-secret
   settings in a chart-rendered ConfigMap `mediamanager-config` (config.toml;
   `frontend_url`/`cors_urls` built from `.Values.domain` in the template —
   chart templates see the appset-injected `domain` param; same mechanism as
   `charts/okd` configmap-env precedent). Secrets as `MEDIAMANAGER_*` env
   overrides from an ExternalSecret (DB creds from the `mediamanager-db`
   Bitwarden LOGIN item; `token_secret` from custom field `secret_key` on the
   `mediamanager` item via bitwarden-fields). Env overrides take precedence
   over TOML, so the TOML omits password/token_secret entirely.
4. **Storage**: SQLite-bearing apps (LazyLibrarian, AudioBookRequest) get RWO
   `local-path` PVCs (never SeaweedFS/NFS — SQLite corruption). MediaManager
   media + LazyLibrarian books/downloads mount the shared RWX `media` PVC so
   library and downloads share one filesystem (hardlink-friendly, per guide);
   LazyLibrarian uses subPaths `books`/`downloads` of the same claim.
5. **LazyLibrarian security context deviates deliberately**: LinuxServer
   s6-overlay images must start as root and drop to PUID/PGID; dropping ALL
   capabilities / runAsNonRoot breaks them (same precedent as
   `charts/tvheadend`). No `runAsNonRoot`, no capability drop on that
   container — documented in values comments.
6. **Ingress**: subdomain keys `mediamanager`, `lazylibrarian`,
   `audiobookrequest` (user chose app-name hosts), no `serviceName` — avoids
   the duplicate-Ingress-name collision in generic-ingress.yaml and keeps
   these mesh-only for now. Public exposure later = add a distinct key with
   `serviceName` (trackers/prowlarr pattern).
7. **TZ = America/Denver** (repo media convention), not the guide's Chicago.
8. **No secrets for LazyLibrarian/AudioBookRequest** → no bitwardenIds, no
   custom-values entries (config lives in their PVCs; ABR/Prowlarr keys are
   set in the UI post-install).
9. Versions: all four charts start at `1.0.0`; CI bumps on merge. Pinned
   image tags only (repo rule).

10. **MinusPod topology A (CPU image + remote Whisper)**: the media node has
    no GPU (verified), so topology C is out; topology B (local CPU Whisper) is
    discouraged upstream. Whisper → Groq (`openai-api` backend), LLM →
    Anthropic — exactly the guide's recommended shape.
11. **MinusPod image tag `2.95.3-cpu`** (verified on Docker Hub): concrete
    version tag per the repo pinning rule, currently identical to the
    `stable-cpu` channel. Caveat: MinusPod's `-cpu` tags mix stable and edge
    channels, so Renovate will offer edge bumps — the values comment instructs
    merging only bumps that match upstream stable release notes.
12. **MinusPod data PVC = 10Gi, not the guide's 50Gi**: the node disk has
    ~16.5GB free and the ~4.4GB image pull lands on the same filesystem;
    local-path doesn't enforce capacity anyway. Retention in the Settings UI
    is the real storage lever; node-disk expansion is a follow-up if the
    library grows.
13. **MinusPod secrets = one Bitwarden item `minuspod`** with custom fields
    `master_passphrase`, `anthropic_api_key`, `whisper_api_key` (all read via
    the `bitwarden-fields` store; multi-field items have precedent in
    `charts/supabase`). `BASE_URL` is domain-dependent → constructed inside
    the ExternalSecret template (n8n pattern). Optional `PODCAST_INDEX_*`
    vars left out — add field + data entry later if wanted.
14. **MinusPod security context**: repo-standard container hardening
    (`allowPrivilegeEscalation: false`, drop ALL) but **no** `runAsNonRoot`
    and **no** `readOnlyRootFilesystem` — upstream explicitly says deploy
    permissive first and tighten deliberately. If drop-ALL breaks ffmpeg/file
    ops, relax it as a documented exception (tvheadend precedent).
15. **MinusPod exposure + first-boot ordering**: a fresh install is
    unauthenticated. Mesh-only ingress (no `serviceName`) plus the Bitwarden
    gate (the pod cannot start before the secret exists) ensure the UI is
    never publicly reachable before a password is set.
16. **SSO (user decision: wire now)**: MediaManager gets Keycloak OIDC via a
    `mediamanager-sso` Bitwarden item (custom fields `client_id`,
    `client_secret`) injected as `MEDIAMANAGER_AUTH__OPENID_CONNECT__*` env
    overrides in the existing ExternalSecret; the discovery endpoint is built
    from `.Values.domain` — Keycloak ingress `login.<domain>`, realm
    `SpencersLab` (the same realm the media cluster's hivetools `mcp-sso`
    already consumes, so cross-cluster reachability is evidenced).
    AudioBookRequest's OIDC is UI-configured and stored in its own DB →
    manual setup step only, no chart plumbing (record its client secret in a
    Bitwarden item `audiobookrequest-sso` for the record). LazyLibrarian and
    MinusPod have no native SSO (verified) — local auth + mesh-only ingress;
    proxy-level ForwardAuth on the media cluster would be new infra, out of
    scope.

## Changes

Ordered; each step is one file unless noted. Full sketches below are the
implementation spec.

### 1. `charts/mediamanager/Chart.yaml` — CREATE

```yaml
apiVersion: v2
name: mediamanager
version: 1.0.0
appVersion: 1.12.3
dependencies:
  - name: app-template
    version: 5.0.1
    repository: https://bjw-s-labs.github.io/helm-charts/
```

### 2. `charts/mediamanager/values.yaml` — CREATE

```yaml
bitwardenIds:
  # Item `mediamanager`: custom field secret_key ([auth] token_secret).
  mediamanager: OVERRIDE_VIA_CUSTOM_VALUES
  # LOGIN item `mediamanager-db`: username MUST equal the CNPG initdb owner
  # (mediamanager); password = DB password.
  mediamanager-db: OVERRIDE_VIA_CUSTOM_VALUES
  # Item `mediamanager-sso`: Keycloak OIDC client (custom fields client_id,
  # client_secret) — see the Keycloak client steps under Verification.
  mediamanager-sso: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

# MediaManager admin accounts: emails matched against the OIDC email claim.
# Override via the service values slice once the admin email is known:
#   mediamanager:
#     adminEmails: ["you@example.com"]
adminEmails: []

app-template:
  global:
    nameOverride: &chartName mediamanager

  controllers:
    mediamanager:
      annotations:
        # config.toml ConfigMap + ExternalSecret changes restart the pod.
        reloader.stakater.com/auto: "true"
      pod:
        securityContext:
          runAsUser: 1000   # rootless since v1.12.0
          runAsGroup: 1000
          fsGroup: 1000
          fsGroupChangePolicy: OnRootMismatch
      containers:
        app:
          image:
            repository: quay.io/maxdorninger/mediamanager
            tag: 1.12.3
          env:
            TZ: America/Denver
            CONFIG_DIR: /app/config
          envFrom:
            - secretRef:
                name: *chartName   # MEDIAMANAGER_* overrides (see secret-mediamanager.yaml)
          probes:
            liveness:
              enabled: true
            readiness:
              enabled: true
            startup:
              enabled: true
              spec:
                failureThreshold: 30
                periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              memory: 2Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  service:
    app:
      controller: *chartName
      type: ClusterIP
      ports:
        http:
          port: 8000

  persistence:
    config:
      existingClaim: *chartName        # PVC from pvc-mediamanager-default.yaml
      globalMounts:
        - path: /app/config
    config-toml:
      type: configMap
      name: mediamanager-config        # rendered by templates/configmap-mediamanager.yaml
      globalMounts:
        - path: /app/config/config.toml
          subPath: config.toml
          readOnly: true
    images:
      existingClaim: mediamanager-images  # PVC from pvc-mediamanager-images-default.yaml
      globalMounts:
        - path: /data/images
    media:
      existingClaim: media             # shared SeaweedFS RWX media PVC (pre-existing)
      globalMounts:
        - path: /data
```

### 3. `charts/mediamanager/templates/` — CREATE (6 files)

`pvc-mediamanager-default.yaml` (config dir, RWO local-path default SC):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mediamanager
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

`pvc-mediamanager-images-default.yaml`: identical shape, name
`mediamanager-images`, storage `10Gi`.

`pg-mediamanager.yaml` (n8n pattern, PG17, no MCP role/backup):

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-mediamanager
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
      max_connections: "200"
      shared_buffers: 256MB
  bootstrap:
    initdb:
      database: mediamanager
      owner: mediamanager
      secret:
        name: pg-mediamanager-secret
```

`secret-pg-mediamanager.yaml` (copy of n8n's secret-pg-n8n.yaml shape):
ExternalSecret `pg-mediamanager-secret`, store `bitwarden-login`, both
remoteRefs `key: {{ index .Values "bitwardenIds" "mediamanager-db" }}` with
properties `username`/`password`, plus the standard
conversionStrategy/decodingStrategy/metadataPolicy boilerplate lines.

`secret-mediamanager.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mediamanager
spec:
  refreshInterval: 1h
  target:
    name: mediamanager
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        MEDIAMANAGER_DATABASE__HOST: "pg-mediamanager-rw"
        MEDIAMANAGER_DATABASE__PORT: "5432"
        MEDIAMANAGER_DATABASE__USER: "{{ `{{ .username }}` }}"
        MEDIAMANAGER_DATABASE__PASSWORD: "{{ `{{ .password }}` }}"
        MEDIAMANAGER_DATABASE__DBNAME: "mediamanager"
        MEDIAMANAGER_AUTH__TOKEN_SECRET: "{{ `{{ .token_secret }}` }}"
        # Keycloak OIDC (realm SpencersLab on the infra cluster's Keycloak,
        # ingress login.<domain>; redirect URI must be registered there:
        # https://mediamanager.<domain>/api/v1/auth/oauth/callback)
        MEDIAMANAGER_AUTH__OPENID_CONNECT__ENABLED: "true"
        MEDIAMANAGER_AUTH__OPENID_CONNECT__NAME: "SpencersLab"
        MEDIAMANAGER_AUTH__OPENID_CONNECT__CONFIGURATION_ENDPOINT: "https://login.{{ $.Values.domain }}/realms/SpencersLab/.well-known/openid-configuration"
        MEDIAMANAGER_AUTH__OPENID_CONNECT__CLIENT_ID: "{{ `{{ .sso_client_id }}` }}"
        MEDIAMANAGER_AUTH__OPENID_CONNECT__CLIENT_SECRET: "{{ `{{ .sso_client_secret }}` }}"
  data:
    - secretKey: username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "mediamanager-db" }}'
        property: username
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "mediamanager-db" }}'
        property: password
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: token_secret
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "mediamanager" }}'
        property: secret_key
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: sso_client_id
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "mediamanager-sso" }}'
        property: client_id
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: sso_client_secret
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "mediamanager-sso" }}'
        property: client_secret
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

`configmap-mediamanager.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mediamanager-config
data:
  config.toml: |
    # MediaManager config. Secrets ([database] password, [auth] token_secret)
    # arrive as MEDIAMANAGER_* env overrides from the mediamanager
    # ExternalSecret and are intentionally absent here.
    [misc]
    # Must exactly match the ingress URL (no trailing slash) or auth breaks.
    frontend_url = "https://mediamanager.{{ .Values.domain }}"
    cors_urls = ["https://mediamanager.{{ .Values.domain }}"]
    image_directory = "/data/images"
    tv_directory = "/data/tv"
    movie_directory = "/data/movies"
    torrent_directory = "/data/torrents"
    development = false

    [database]
    host = "pg-mediamanager-rw"
    port = 5432
    user = "mediamanager"
    dbname = "mediamanager"

    [auth]
    email_password_resets = false
    session_lifetime = 86400
    admin_emails = {{ .Values.adminEmails | toJson }}

    [indexers.prowlarr]
    enabled = true
    url = "http://media-prowlarr:9696"
    # Set the Prowlarr API key in the MediaManager UI after first boot.

    # Download clients are out of scope for now (no qBittorrent/SABnzbd in
    # the cluster yet); enable here when one lands.
    [torrents.qbittorrent]
    enabled = false

    [torrents.sabnzbd]
    enabled = false
```

### 4. `charts/lazylibrarian/Chart.yaml` — CREATE

Same shape as step 1: name `lazylibrarian`, `version: 1.0.0`, app-template
5.0.1 dependency. (`appVersion` may be omitted or set to the pinned tag.)

### 5. `charts/lazylibrarian/values.yaml` — CREATE

```yaml
domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName lazylibrarian

  controllers:
    lazylibrarian:
      # No reloader annotation: config lives in a PVC, not ConfigMap/Secret.
      pod:
        securityContext:
          fsGroup: 1000
          fsGroupChangePolicy: OnRootMismatch
      containers:
        app:
          image:
            repository: lscr.io/linuxserver/lazylibrarian
            # LinuxServer version-<sha> tags: Renovate cannot order these —
            # bump manually when updating.
            tag: version-58c3b076
          env:
            TZ: America/Denver
            PUID: "1000"
            PGID: "2000"   # shared media group (jellyfin/tvheadend convention)
          # NOTE: LinuxServer s6-overlay images start as root and drop to
          # PUID/PGID internally. runAsNonRoot / drop-ALL would break init —
          # deliberate deviation from the standard security context, same as
          # charts/tvheadend.
          probes:
            liveness: &probes
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /home   # webui lives at /home
                  port: 5299
                initialDelaySeconds: 30
                periodSeconds: 10
            readiness: *probes
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              memory: 1Gi

  service:
    app:
      controller: *chartName
      type: ClusterIP
      ports:
        http:
          port: 5299

  persistence:
    config:
      existingClaim: *chartName   # PVC from pvc-lazylibrarian-default.yaml; SQLite → RWO local-path, never SeaweedFS/NFS
      globalMounts:
        - path: /config
    books:
      existingClaim: media        # shared RWX media PVC
      globalMounts:
        - path: /books
          subPath: books
    downloads:
      existingClaim: media        # same volume as books → hardlinks possible
      globalMounts:
        - path: /downloads
          subPath: downloads
```

### 6. `charts/lazylibrarian/templates/pvc-lazylibrarian-default.yaml` — CREATE

Same shape as tvheadend's: PVC `lazylibrarian`, namespace default, RWO, 1Gi.

### 7. `charts/audiobookrequest/Chart.yaml` — CREATE

Same shape: name `audiobookrequest`, `version: 1.0.0`, app-template 5.0.1.

### 8. `charts/audiobookrequest/values.yaml` — CREATE

```yaml
domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName audiobookrequest

  controllers:
    audiobookrequest:
      pod:
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
          fsGroup: 1000
          fsGroupChangePolicy: OnRootMismatch
      containers:
        app:
          image:
            repository: markbeep/audiobookrequest
            tag: 1.10.7
          env:
            TZ: America/Denver
            ABR_APP__PORT: "8000"
            ABR_APP__CONFIG_DIR: /config
            ABR_APP__LOG_LEVEL: INFO
          probes:
            liveness:
              enabled: true
            readiness:
              enabled: true
          resources:
            requests:
              cpu: 25m
              memory: 128Mi
            limits:
              memory: 512Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  service:
    app:
      controller: *chartName
      type: ClusterIP
      ports:
        http:
          port: 8000

  persistence:
    config:
      existingClaim: *chartName   # SQLite inside → RWO local-path, never SeaweedFS/NFS
      globalMounts:
        - path: /config
```

### 9. `charts/audiobookrequest/templates/pvc-audiobookrequest-default.yaml` — CREATE

PVC `audiobookrequest`, namespace default, RWO, 1Gi.

### 10. `services/media/prod/values.yaml` — MODIFY (two regions)

Under `charts:` (after `tvheadend:`):

```yaml
  # CloudNativePG operator (external chart, values-only — same entry as grow).
  # Needed by charts/mediamanager's pg-mediamanager Cluster.
  cloudnative-pg:
    version: 0.27.1
    repository: https://cloudnative-pg.github.io/charts
    namespace: default
    ServerSideApply: "true"
  mediamanager:
    namespace: default
    ServerSideApply: "true"
  lazylibrarian:
    namespace: default
    ServerSideApply: "false"
  audiobookrequest:
    namespace: default
    ServerSideApply: "false"
```

Under `ingress.subdomains:` (no `serviceName` — see Design decision 6):

```yaml
    mediamanager:
      service: media-mediamanager
      port: 8000

    lazylibrarian:
      service: media-lazylibrarian
      port: 5299

    audiobookrequest:
      service: media-audiobookrequest
      port: 8000
```

### 11. `custom-values/media/prod-values.yaml` — MODIFY

Append (argocd-mcp TODO pattern — empty UUIDs are a visible, accepted failure
mode until the user creates the Bitwarden items):

```yaml
# MediaManager (charts/mediamanager). TODO(user): create THREE Bitwarden
# items, then paste their UUIDs here:
#   - LOGIN item `mediamanager-db`: username=mediamanager (MUST equal the CNPG
#     initdb owner), password=<generated>. Feeds CNPG bootstrap + app DB env.
#   - Item `mediamanager` with custom field secret_key = `openssl rand -hex 32`
#     (MediaManager [auth] token_secret).
#   - Item `mediamanager-sso` with custom fields client_id + client_secret
#     from the Keycloak `mediamanager` client (Verification step 4).
# Until then the mediamanager ExternalSecrets stay unready and the app pod
# stays Pending; pg-mediamanager won't bootstrap.
mediamanager:
  bitwardenIds:
    mediamanager: ""
    mediamanager-db: ""
    mediamanager-sso: ""
```

### 12. Chart dependencies — RUN

```bash
helm dependency update charts/mediamanager
helm dependency update charts/lazylibrarian
helm dependency update charts/audiobookrequest
helm dependency update charts/minuspod
```

Commit the three `Chart.lock` files; the generated `charts/` tarball dirs are
gitignored — do not commit them.

### 13. `charts/minuspod/Chart.yaml` — CREATE

```yaml
apiVersion: v2
name: minuspod
version: 1.0.0
appVersion: 2.95.3
dependencies:
  - name: app-template
    version: 5.0.1
    repository: https://bjw-s-labs.github.io/helm-charts/
```

### 14. `charts/minuspod/values.yaml` — CREATE

```yaml
bitwardenIds:
  # Item `minuspod`: custom fields master_passphrase, anthropic_api_key,
  # whisper_api_key (Groq). The passphrase MUST exist before first boot
  # (otherwise provider keys are stored plaintext) and must be backed up
  # offline — losing it makes stored keys/backups unrecoverable.
  minuspod: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName minuspod

  controllers:
    minuspod:
      annotations:
        reloader.stakater.com/auto: "true"
      # SQLite on RWO + single background worker: never scale above 1.
      # Recreate is app-template's deployment default; explicit for intent.
      strategy: Recreate
      containers:
        app:
          image:
            repository: ttlequals0/minuspod
            # Concrete version tag (repo pinning rule) == current stable
            # channel. CAUTION: MinusPod publishes edge releases as
            # <ver>-cpu tags several times a day — only merge Renovate bumps
            # that match upstream STABLE release notes.
            tag: 2.95.3-cpu
          env:
            TZ: America/Denver
            # LLM (key arrives via the minuspod ExternalSecret)
            LLM_PROVIDER: anthropic
            OPENAI_MODEL: claude-haiku-4-5
            # Whisper via remote API (Groq) — no GPU on this cluster
            WHISPER_BACKEND: openai-api
            WHISPER_API_BASE_URL: https://api.groq.com/openai/v1
            WHISPER_API_MODEL: whisper-large-v3-turbo
            WHISPER_DEVICE: cpu
            # Behind the traefik ingress — real client IPs for rate limits/audit
            MINUSPOD_TRUSTED_PROXY_COUNT: "1"
            # First-boot posture seeds only; stored settings win afterwards —
            # tune later in the Settings UI, not here.
            AUTO_PROCESS_ENABLED: "true"
            FEED_AUTH_ENABLED: "true"
            # NOTE: set no DATA_DIR/DATA_PATH/MINUSPOD_DATA_DIR — the PVC
            # mounts at the default /app/data (2.95.3 path-precedence gotcha).
          envFrom:
            - secretRef:
                name: *chartName   # MINUSPOD_MASTER_PASSPHRASE, API keys, BASE_URL
          probes:
            liveness: &probes
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /api/v1/health
                  port: 8000
                periodSeconds: 30
                timeoutSeconds: 10
                failureThreshold: 5
            readiness: *probes
            startup:
              enabled: true
              spec:
                failureThreshold: 60   # migrations run on boot; be generous
                periodSeconds: 5
          resources:
            requests:
              cpu: 500m
              memory: 4Gi
            limits:
              memory: 12Gi
          # Upstream: deploy permissive, tighten deliberately. Keep root +
          # writable rootfs; repo standard still drops capabilities.
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  service:
    app:
      controller: *chartName
      type: ClusterIP
      ports:
        http:
          port: 8000

  persistence:
    data:
      existingClaim: *chartName   # PVC from pvc-minuspod-default.yaml; SQLite → RWO local-path, never SeaweedFS/NFS
      globalMounts:
        - path: /app/data
```

### 15. `charts/minuspod/templates/secret-minuspod.yaml` — CREATE

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: minuspod
spec:
  refreshInterval: 1h
  target:
    name: minuspod
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # Must exist on FIRST BOOT or provider keys land in the DB plaintext.
        MINUSPOD_MASTER_PASSPHRASE: "{{ `{{ .master_passphrase }}` }}"
        ANTHROPIC_API_KEY: "{{ `{{ .anthropic_api_key }}` }}"
        WHISPER_API_KEY: "{{ `{{ .whisper_api_key }}` }}"
        # Feed enclosure URLs are built from this — must equal the ingress
        # URL exactly (wrong BASE_URL = feed loads but every audio 404s).
        BASE_URL: "https://minuspod.{{ $.Values.domain }}"
  data:
    - secretKey: master_passphrase
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "minuspod" }}'
        property: master_passphrase
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: anthropic_api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "minuspod" }}'
        property: anthropic_api_key
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: whisper_api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "minuspod" }}'
        property: whisper_api_key
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 16. `charts/minuspod/templates/pvc-minuspod-default.yaml` — CREATE

```yaml
# Sized for this cluster's node disk (~16.5GB free of 75GB, shared with
# images and all local-path PVCs) — NOT the upstream 50Gi suggestion.
# local-path does not enforce capacity; manage retention in the Settings UI.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minuspod
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

### 17. `services/media/prod/values.yaml` — MODIFY (MinusPod parts)

Under `charts:` (with the entries from step 10):

```yaml
  minuspod:
    namespace: default
    ServerSideApply: "false"
```

Under `ingress.subdomains:` (mesh-only, no `serviceName` — fresh installs are
unauthenticated; see Design decision 15):

```yaml
    minuspod:
      service: media-minuspod
      port: 8000
```

### 18. `custom-values/media/prod-values.yaml` — MODIFY (append)

```yaml
# MinusPod (charts/minuspod). TODO(user): create Bitwarden item `minuspod`
# with custom fields:
#   master_passphrase = openssl rand -base64 48   (ALSO back this up offline!)
#   anthropic_api_key = sk-ant-...
#   whisper_api_key   = gsk_...                   (Groq)
# Paste its UUID here. Until then the ExternalSecret stays unready and the
# pod stays Pending — visible, accepted failure mode.
minuspod:
  bitwardenIds:
    minuspod: ""
```

### 19. MinusPod chart dependency — RUN

Covered by step 12's `helm dependency update charts/minuspod` (commit the
`Chart.lock`, not the gitignored `charts/` tarball dir).

## Verification

1. **Lint/template each chart** (must pass, no sentinels in output):

   ```bash
   helm lint charts/mediamanager charts/lazylibrarian charts/audiobookrequest
   helm template mediamanager charts/mediamanager \
     --set domain=test.example.com \
     --set bitwardenIds.mediamanager=test-uuid \
     --set bitwardenIds.mediamanager-db=test-uuid > /tmp/mm.yaml
   helm template lazylibrarian charts/lazylibrarian --set domain=test.example.com > /tmp/ll.yaml
   helm template audiobookrequest charts/audiobookrequest --set domain=test.example.com > /tmp/abr.yaml
   helm template minuspod charts/minuspod \
     --set domain=test.example.com \
     --set bitwardenIds.minuspod=test-uuid > /tmp/mp.yaml
   grep -E "OVERRIDE_|test.example.com" /tmp/mm.yaml /tmp/ll.yaml /tmp/abr.yaml /tmp/mp.yaml
   # expect: NO OVERRIDE_* hits; frontend_url/cors rendered as
   # https://mediamanager.test.example.com in the ConfigMap; mediamanager's
   # OIDC endpoint rendered as
   # https://login.test.example.com/realms/SpencersLab/.well-known/openid-configuration;
   # minuspod's BASE_URL rendered as https://minuspod.test.example.com
   ```

2. **Trio check**:

   ```bash
   grep -n "mediamanager\|lazylibrarian\|audiobookrequest\|minuspod\|cloudnative-pg" services/media/prod/values.yaml
   ```

   Expect: 5 `charts:` entries + 4 `ingress.subdomains` entries, and the
   custom-values blocks (`mediamanager:`, `minuspod:`) in
   `custom-values/media/prod-values.yaml`.

3. **Post-merge ArgoCD expectations** (readonly-media-kubernetes):
   - `media-charts-appset` gains Applications `media-cloudnative-pg`,
     `media-mediamanager`, `media-lazylibrarian`, `media-audiobookrequest`.
   - `media-cloudnative-pg` syncs the operator + CRDs first; the
     `pg-mediamanager` Cluster may show OutOfSync/failed until the CRD lands,
     then converges (selfHeal retries). This ordering race is expected.
   - `media-lazylibrarian` + `media-audiobookrequest` should go Healthy with
     Running pods immediately (no secrets).
   - `media-minuspod`: ExternalSecret stays unready and the pod stays Pending
     until the user creates the Bitwarden item and fills the UUID (same gate
     as mediamanager). Once Running, port-forward and check
     `GET /api/v1/health` — expect database/storage/queue_available all true.
     Watch node disk free space during the ~4.4GB image pull.
   - `media-mediamanager`: ExternalSecrets stay unready and the pod stays
     Pending until the user fills the Bitwarden UUIDs (documented gate).
   - Ingresses `mediamanager-ingress`, `lazylibrarian-ingress`,
     `audiobookrequest-ingress` exist with hosts `<name>.<domain>` and
     `wildcard-cert` TLS.

4. **Manual user steps (post-sync, in the plan's handoff notes):**
   - Create the three MediaManager Bitwarden items + the MinusPod item,
     paste UUIDs into `custom-values/media/prod-values.yaml`, merge →
     MediaManager and MinusPod boot.
   - Verify the shared media PVC's folder layout (e.g. `kubectl exec` into
     jellyfin: `ls /media`); if movies/tv live elsewhere, adjust
     `tv_directory`/`movie_directory` in
     `charts/mediamanager/templates/configmap-mediamanager.yaml`.
   - **Keycloak (infra cluster, realm `SpencersLab`) — before MediaManager's
     first boot**: create confidential client `mediamanager` with redirect URI
     `https://mediamanager.<domain>/api/v1/auth/oauth/callback`, and client
     `audiobookrequest` with redirect URI
     `https://audiobookrequest.<domain>/auth/oidc`. Ensure an email claim is
     released for MediaManager admin matching, and add a group-membership
     protocol mapper for ABR's group claim. Copy each client secret into
     Bitwarden items `mediamanager-sso` (custom fields `client_id`,
     `client_secret`) and `audiobookrequest-sso` (record-keeping).
   - Set `mediamanager: adminEmails: ["<your-email>"]` in
     `services/media/prod/values.yaml` so the first OIDC login is admin.
   - First MediaManager login: use the SpencersLab OIDC button; verify the
     account is admin; set Prowlarr API key in the UI.
   - AudioBookRequest UI: first-run wizard (keep the root admin password —
     it is the `/login?backup=1` lockout escape hatch), then add Prowlarr
     (`http://media-prowlarr:9696` + its API key) and Audiobookshelf
     (`http://media-audiobookshelf:8080` + API token). Then Settings →
     Security → OIDC: well-known
     `https://login.<domain>/realms/SpencersLab/.well-known/openid-configuration`,
     username claim (e.g. `preferred_username`), group claim (e.g. `groups`
     — values map to untrusted/trusted/admin), scope `openid` plus whatever
     the claims need, client id/secret from the Keycloak client. Log out to
     test (applying settings doesn't invalidate the current session).
   - LazyLibrarian UI: add Newznab/Torznab indexers via Prowlarr; point
     library paths at `/books`.
   - MinusPod first boot (immediately): open `/ui/` (mesh host or
     port-forward) and SET A PASSWORD — fresh installs are unauthenticated.
     Verify Settings → AI Models shows the seeded model; add one feed and
     process one episode before adding more.
   - MinusPod + Audiobookshelf (optional, later): ABS enforces an SSRF filter
     that blocks private URLs — add the MinusPod host to ABS's
     `SSRF_REQUEST_FILTER_WHITELIST` (separate umbrella-values change) or the
     feed add fails silently. Copy the authenticated feed URL from the
     MinusPod UI (FEED_AUTH_ENABLED=true).
   - MinusPod backups: the 24h auto-backups live inside the PVC and don't
     survive volume loss — an off-cluster copy job is a follow-up.

## Risks & open questions

- **Bitwarden gate**: MediaManager cannot start until the user creates the two
  Bitwarden items and fills the UUIDs (accepted failure mode, same precedent
  as argocd-mcp in this same file).
- **Media share layout unknown**: `tv_directory`/`movie_directory` default to
  `/data/tv` + `/data/movies` (bucket-root `tv/`, `movies/`). If the existing
  library uses different paths, MediaManager will see empty libraries — the
  verify-and-adjust step above is mandatory before heavy use.
- **Hardlinks on SeaweedFS**: the guide warns hardlinks historically fail on
  NFS/CSI filesystems; MediaManager has a copy fallback. Untestable until a
  download client exists (out of scope) — revisit with the qBittorrent
  follow-up.
- **LazyLibrarian write permissions**: PGID 2000 follows the repo's shared
  group convention, but the existing *arr apps' effective UID/GID on the media
  share couldn't be verified without pod exec. If `/books` or `/downloads`
  writes fail, adjust PUID/PGID (visible in pod logs).
- **LSIO tag churn**: `version-<sha>` tags aren't semver — Renovate won't bump
  them; manual updates (comment in values.yaml notes this).
- **MediaManager admin bootstrap**: `adminEmails` defaults to `[]` — set it
  to the admin's email (service-values override) before/at first OIDC login;
  with an empty list, verify who gets admin and correct it.
- **CNPG operator is new on the media cluster**: first-of-kind there; grow's
  identical entry is the evidence it works, but watch the operator pod and
  webhook on first sync.
- **Public exposure deferred**: ingress hosts are mesh-only (no
  `serviceName`). If public access is wanted, add distinct functional keys
  with `serviceName` later — do NOT set serviceName == subdomain key (renders
  duplicate Ingress names in generic-ingress.yaml).

**SSO-specific:**

- **OIDC lockout**: ABR misconfiguration can lock you out — the root admin
  password + `/login?backup=1` is the escape hatch (keep it). For
  MediaManager, if OIDC login misbehaves, set
  `MEDIAMANAGER_AUTH__OPENID_CONNECT__ENABLED: "false"` in the ExternalSecret
  template and restart to fall back to local registration.
- **Keycloak reachability from the media cluster**: evidenced by hivetools
  `mcp-sso` consuming the same realm, but verify during rollout by curling
  the discovery endpoint from a media-cluster pod.
- **ABR group claim**: without a Keycloak group-membership mapper every OIDC
  user lands as `untrusted`; and any user matching the root admin username
  becomes root admin regardless of groups — pick claims deliberately.
- **MediaManager admin_emails × OIDC**: docs say admin_emails match user
  emails; behavior with OIDC-provisioned users is not exhaustively
  documented — verify the first login actually gets admin.

**MinusPod-specific:**

- **Node disk is the binding constraint**: ~16.5GB free of 75GB shared by
  images, etcd, and all local-path PVCs; the ~4.4GB pull plus processed-audio
  growth erode it fast, and local-path enforces no quotas. Monitor
  `kubectl describe node media` (ephemeral-storage) / kubelet DiskPressure;
  plan disk expansion or move audio to the SeaweedFS-backed strategy if usage
  grows (MinusPod itself needs RWO-local only for the SQLite file — a future
  split of DB vs audio dirs is possible but out of scope).
- **Memory pressure**: 12Gi limit + 4Gi request on a 30.6Gi node that also
  runs Jellyfin transcodes. Watch OOMs during concurrent processing; lower
  the limit or whisper model size if needed.
- **Master passphrase**: losing it makes stored provider keys and encrypted
  backups unrecoverable — the Bitwarden item is the backup of record; the
  user should keep an offline copy too. Missing at first boot = plaintext
  keys in the DB (why the secret gates the first start).
- **Fresh install is unauthenticated**: mitigated by mesh-only ingress + the
  secret gate, but the password must be set immediately after first boot.
- **Env vars seed only**: after first boot, stored settings win — later
  tuning happens in the Settings UI, not in values.yaml (per-stage
  DETECTION_*/VERIFICATION_* vars are deliberately unset to keep the UI
  controls writable).
- **Renovate tag churn**: `-cpu` version tags include edge releases (several
  per day upstream); merge bump PRs only against stable release notes.
- **503s while processing are normal** (single background worker +
  Retry-After); liveness stays green on `/api/v1/health` — don't "fix" this
  by loosening probes or adding replicas (single replica is mandatory:
  SQLite + RWO).
