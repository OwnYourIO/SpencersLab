# Plan: Self-hosted music stack on the media cluster (Lidarr nightly + plugins · betanin · spotDL · slskd · Explo · AudioMuse-AI)

## Goal

Bring the user-provided "Self-Hosted Music Stack" guide onto the **media
cluster** using repo patterns: Lidarr upgraded to a pinned **nightly** image
(plugin support) with **Tubifarry** + **Brainarr** plugins, **betanin**
(beets write-only tagging) triggered by a Lidarr custom script, a **spotDL**
nightly CronJob (keyless mode), **slskd** for Soulseek (no VPN for now),
**Explo** for ListenBrainz discovery, and **AudioMuse-AI** wired to Jellyfin
with AI provider NONE. Brainarr's LLM backend is the existing **llama-swap**
on the gpu cluster via its OpenAI-compatible endpoint (user decision — no new
Ollama).

Explicitly OUT of scope (user decisions / guide recommendations): pjmeca
wrapper, spotdl-webui, the betanin fork (upstream image instead), gluetun VPN
sidecar (slskd ships without VPN; follow-up plan), a new Ollama deployment,
Navidrome + its AudioMuse plugin (no Navidrome in this lab), Music Assistant
integration.

Everything is GitOps — ArgoCD applies all resources. Imperative steps (PVC
backup, Bitwarden items, Lidarr plugin UI config, Jellyfin token) are USER
steps, presented verbatim, never run by agents.

## Skills

Code agent must load (fresh session):

- `helm-chart-creation` — repo wiring rules; read `references/values-and-appset.md`,
  `references/storage-and-secrets.md`, `references/chart-templates.md` and
  `references/proxying.md` before touching anything.
- `helm-bjw-s-chart` — app-template values API (charts pin **5.0.1** here).
- `gitops-workflows` — ArgoCD/secrets context.
- `kubernetes-skill` — manifest review discipline.
- `traefik` — proxy/ingress entries.

Not needed: `container-creation` (no in-repo image builds), `llama-swap`
(consuming it only, not editing its config).

## MCP Servers

- `readonly-media-kubernetes` — verify Applications, ExternalSecrets, pods,
  PVCs, Services before and after each phase.
- `readonly-gpu-kubernetes` — confirm llama-swap Service/Ingress facts
  (Brainarr endpoint) before wiring plugins.
- No `admin-*` servers needed: ArgoCD applies everything; kubectl steps are
  user-run (no MCP tier grants pod exec).

## Verified context

Repo recon (all paths read, 2026-09-20):

- `services/media/prod/Chart.yaml` — the media service is an **umbrella Helm
  chart**: app-template 5.0.1 (aliases jellyfin/audiobookshelf) + bubylou
  **Arr-Stack** subcharts (jellyseerr 0.2.5, lidarr 0.3.5, prowlarr 0.3.5,
  radarr 0.3.6, readarr 0.3.5, sonarr 0.3.4). Lidarr values flow through the
  `lidarr:` key in `services/media/prod/values.yaml`.
- `services/media/prod/values.yaml` — `charts:` map (per-app Applications via
  base's appset-charts), `ingress.subdomains` (rendered by
  `templates/generic-ingress.yaml`: host `<name>.<domain>` + a second
  `<serviceName>.<domain>` ingress with external-dns when `serviceName` set),
  existing `lidarr:` block uses the bubylou API (`env` list, `volumes`,
  `volumeMounts`).
- `services/media/prod/templates/` — PVC templates per app (RWO, default
  storage class = local-path), `pvc-media-seaweedfs.yaml` = shared **SeaweedFS
  RWX PVC `media`** (50Ti, bucket `/buckets/media`), `generic-ingress.yaml`,
  `secret-argocd-mcp.yaml` (ExternalSecret pattern).
- `charts/tvheadend/` — newest media chart = current pattern: app-template
  **5.0.1** dependency, chart-owned `templates/pvc-<name>-default.yaml`,
  LSIO image with PUID/PGID, wired via `charts:` entry + `ingress.subdomains`
  + proxy-local `proxy.subdomains`.
- `charts/qdrant/templates/secret-qdrant.yaml` — ExternalSecret pattern:
  `bitwarden-login`/`bitwarden-fields` SecretStores, `{{ index .Values
  "bitwardenIds" "<name>" }}`, boilerplate conversion/decoding/metadata
  strategies; `target.template.engineVersion: v2` available for composed
  secret data.
- `custom-values/media/prod-values.yaml` — per-app keys (e.g. `hivetools:
  bitwardenIds: ...`) merge into the umbrella `.Values` and ride the
  charts-appset values slice into each app chart.
- `services/proxy-local/prod/values.yaml` — hub entries: `music: target:
  lidarr`, `llama: target: llama-cpp` (middlewares crowdsec +
  user-allowlist[-remote], which are **ipAllowList** middlewares allowing
  10.0.0.0/16 — LAN/NAT'd pod traffic passes without SSO).
- `services/gpu/prod/values.yaml` — `ingress.subdomains.llama-cpp` →
  `service: gpu-llama-swap`, port 8080; gpu's `generic-ingress.yaml` applies
  `default-llama-timeouts` ServersTransport to all gpu ingresses; open-webui
  consumes `http://gpu-llama-swap.default.svc.cluster.local:8080/v1`.
- `charts/llama-swap/values.yaml` — llama.cpp models (general: qwen3.6-27b,
  qwen3.6-35b-a3b, qwen3-8b, …), OpenAI-compatible `/v1`, one GPU model at a
  time (matrix), `globalTTL: 0`.

Live cluster state (media, via `readonly-media-kubernetes`, 2026-09-20):

- Single-node k3s **v1.36.2**, node `media`: **4 CPU / 32 GiB RAM, no GPU**,
  amd64. Namespace for all workloads: **`default`**.
- ArgoCD v3.4.5 (in-cluster, ns `default`); Applications: `media` (umbrella,
  currently **Degraded** — pre-existing), media-tvheadend, media-smtp-relay,
  media-external-secrets-bitwarden, media-k8s-monitoring,
  media-seaweedfs-csi-driver, media-hivetools.
- Live Lidarr: Deployment `media-lidarr`, image
  **`ghcr.io/hotio/lidarr:release-2.10.3.4602`**, PVC `lidarr` (1Gi RWO) at
  `/config`, PVC `media` at `/media/`, probes on `/ping`, `resources: {}`.
- ESO v0.19.1 with SecretStores `bitwarden-login` / `bitwarden-fields`;
  cert-manager wildcard certs; **no CNPG operator** (AudioMuse uses its
  chart-bundled Postgres on local-path).
- No navidrome, slskd, betanin, spotdl, explo, audiomuse, ollama anywhere.

Registry verification (queried 2026-09-20, not guessed):

- `docker.io/sentriz/betanin` — pinned tag **`v0.6.3`** exists (2026-05-31;
  amd64 digest `sha256:628dafd3e58faa2b2467229dd31be8843972656d0312ff139ad5b454593ac8f7`).
- `docker.io/spotdl/spotify-downloader` — **`v4.5.2`** exists (2026-07-20).
- `lscr.io/linuxserver/lidarr` — pinnable nightly tags exist; newest
  **`nightly-version-3.1.6.5078`** (2026-09-13, amd64 digest
  `sha256:564498ffe7d25d97974cefa3ada890beb7b99a8a743768cb562183bbf4c7ef0d`).
  Satisfies Tubifarry's minimum Lidarr 3.1.5.0.
- `docker.io/slskd/slskd` — `0.26.0.65534-*` tags current (2026-09-14).
  **Confirm at impl time whether a plain `0.26.0` tag exists; if yes use it,
  else pin `0.26.0.65534-042701b5`.**
- `docker.io/ollama/ollama` — checked for completeness; NOT deployed (user
  decision: Brainarr uses llama-swap).
- AudioMuse-AI chart index (`https://NeptuneHub.github.io/AudioMuse-AI-helm/index.yaml`)
  — chart **`audiomuse-ai` v1.1.6** confirmed.
- Explo chart repo `https://lumepart.github.io/Explo` — **chart version
  UNVERIFIED**; Code agent runs `helm repo add explo https://lumepart.github.io/Explo
  && helm search repo explo --versions` and pins the current one.

## Design decisions

1. **All new services = custom charts under `charts/` + `charts:` entries in
   `services/media/prod/values.yaml`** (the tvheadend pattern), NOT new
   umbrella dependencies. The bubylou umbrella stays untouched except for the
   lidarr values block. Release names `media-<appName>`, Services
   `media-<appName>`, namespace `default`.
2. **Lidarr nightly via image override in the existing bubylou subchart**
   (`lidarr: image: {repository: lscr.io/linuxserver/lidarr, tag:
   nightly-version-3.1.6.5078}` + `PUID/PGID=1000`). Switching image family
   hotio→LSIO is safe here: both are s6/PUID-PGID images and /config files
   are owned 1000:1000 (verify post-rollout). LSIO chosen over hotio because
   LSIO publishes **pinnable** `nightly-version-*` tags (repo pinning rule;
   hotio nightly is rolling-only) and the repo already runs LSIO (tvheadend).
   Nightly is a **one-way DB migration** → mandatory user backup first
   (Change 1a).
3. **Plugins (Tubifarry v2.2.0.5, Brainarr v1.6.1) installed via Lidarr UI**
   into `/config/plugins/` — persisted by the existing lidarr PVC; no GitOps
   artifact exists for plugin installs. Pinned nightly tag keeps plugin/
   `Minimum Lidarr Version` compatibility stable.
4. **Brainarr LLM = llama-swap on gpu** (user decision) via its
   OpenAI-compatible endpoint using Brainarr's OpenAI-compatible provider
   ("LM Studio"-style base URL), NOT the Ollama provider. URL:
   `https://llama-cpp.spencerslab.com/v1` (gpu ingress `llama-cpp` →
   `gpu-llama-swap:8080`, long-timeout ServersTransport already applied;
   ipAllowList middlewares permit 10.0.0.0/16 so NAT'd media pod traffic
   passes). Model: `qwen3.6-35b-a3b-q6` (general-purpose MoE, 3B active).
   UNVERIFIED end-to-end — user-run connectivity test in Change 8f with
   documented fallbacks.
5. **AudioMuse-AI via its official chart wrapped in `charts/audiomuse-ai`**
   (repo rule: external chart + secrets ⇒ wrapper). Chart-bundled Postgres on
   local-path (no CNPG on media). AI provider **NONE** (llama-swap is not
   Ollama-API-compatible; Setup Wizard can change this later). Music server =
   **Jellyfin** at cluster-local `http://media-jellyfin:8096`.
6. **Explo via official chart wrapped in `charts/explo`** (secrets: ListenBrainz
   token + Lidarr API key). `DOWNLOAD_SERVICES=lidarr` (Tubifarry provides the
   actual download clients inside Lidarr).
7. **betanin = upstream `sentriz/betanin:v0.6.3`** (pinnable tag verified;
   fork not needed — quiet mode is set directly in beets config).
   `config.toml` and beets `config.yaml` are rendered by ONE ExternalSecret
   `target.template` (bakes web creds, API key, acoustid/lastfm keys in —
   no envsubst init container, no read-only-config fight for beets).
   `config.toml` is seeded into the PVC by an init container **only if
   missing**, so betanin UI edits keep working afterwards.
8. **slskd without VPN** (user decision; gluetun follow-up). Config file
   `slskd.yml` rendered by ExternalSecret template (Soulseek creds + API key
   for Tubifarry) and mounted into `/app`; state on its own PVC. Runs as the
   image's default user (root) — documented hardening exception until a
   non-root story is verified.
9. **spotDL = official image CronJob, keyless mode** (no Spotify dev app):
   no `--use-official-api`, no cookie file. Playlists = git-managed ConfigMap
   (`playlists.txt`, one URL per line); first run creates
   `/config/playlists.spotdl`, later runs sync it with
   `--sync-without-deleting` (no automated library deletion). Output format
   flac into `/media/Music/automation/{artist}/{album}/{title}.{output-ext}`.
10. **Paths adapt the guide to repo reality:** shared PVC is SeaweedFS `media`
    mounted at `/media` (not NFS `/data`). Music library root:
    **`/media/Music/automation`** (user decision — automation-managed music
    stays under its own subtree). Download landing zone: **`/media/downloads`**
    (slskd downloads/incomplete; Tubifarry remote-path mapping target).
11. **Media-writer group convention = GID 2000** (jellyfin runs gid 2000;
    tvheadend uses PGID 2000): new writers get `supplementalGroups: [2000]`
    (and runAsGroup/fsGroup 2000 where the image allows) so Jellyfin can read
    what they write on the SeaweedFS share.
12. **In-cluster service DNS, namespace `default`:** betanin script →
    `http://media-betanin:9393`; Tubifarry slskd client →
    `http://media-slskd:5030`; Explo → `http://media-lidarr:8686` (the guide's
    `*.media.svc.cluster.local` hosts are wrong for this lab).
13. **Secrets: one Bitwarden item per service** (`betanin`, `slskd`, `explo`,
    `audiomuse-ai`), read through both stores (login password/username +
    custom fields). Sentinels in chart values; UUIDs in
    `custom-values/media/prod-values.yaml` under per-app keys. spotDL has no
    secrets → no bitwardenIds, no custom-values entry.
14. **app-template pinned 5.0.1** (repo standard — umbrella + tvheadend both
    pin it), NOT the guide's 5.2.1. No manual chart version bumps after
    initial `1.0.0` (CI bumps on merge to main).

## Changes

Ordered phases. Each step names exactly one file. Phases 2-6 are independent
charts (can be separate commits); phase order still matters for runtime
dependencies (betanin Secret before Lidarr mounts it; lidarr nightly before
plugins).

### Phase 1 — Lidarr nightly migration

**1a. USER step (mandatory, before 1b merges): back up the lidarr /config PVC.**

Present verbatim (no MCP tier grants exec):

```bash
# From a host with the media kubeconfig:
kubectl -n default cp "$(kubectl -n default get pod -l app.kubernetes.io/name=lidarr -o jsonpath='{.items[0].metadata.name}'):/config" \
  "./lidarr-config-backup-$(date +%Y%m%d)"
tar czf "lidarr-config-backup-$(date +%Y%m%d).tar.gz" "lidarr-config-backup-$(date +%Y%m%d)"
```

Keep this archive outside the cluster. Nightly→master downgrade is impossible
without it.

**1b. `services/media/prod/values.yaml` — MODIFY the `lidarr:` block** (replace
the existing block entirely; keep the two original volumes/mounts):

```yaml
lidarr:
  # Nightly branch REQUIRED for the plugin system (Tubifarry, Brainarr).
  # ONE-WAY DB migration — /config PVC backed up first (plan phase 1a).
  # LSIO publishes pinnable nightly-version-* tags (repo pinning rule);
  # bump tag + plugins together (plugins declare Minimum Lidarr Version).
  image:
    repository: lscr.io/linuxserver/lidarr
    tag: nightly-version-3.1.6.5078
  env:
    - name: TZ
      value: America/Denver
    - name: PUID
      value: "1000"
    - name: PGID
      value: "1000"
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      memory: 2Gi
  volumes:
    - name: lidarr-config
      persistentVolumeClaim:
        claimName: lidarr
    - name: media
      persistentVolumeClaim:
        claimName: media
    # betanin custom script + its API key (phases 2a/2c):
    - name: betanin-script
      configMap:
        name: lidarr-betanin-script
        defaultMode: 0755
    - name: betanin-secret
      secret:
        secretName: betanin
  volumeMounts:
    - name: lidarr-config
      mountPath: "/config"
    - name: media
      mountPath: /media/
    - name: betanin-script
      mountPath: /config/scripts/betanin.sh
      subPath: betanin.sh
    - name: betanin-secret
      mountPath: /config/secrets/betanin/api_key
      subPath: BETANIN_API_KEY
```

Note: if phase 2 lands in a later commit than phase 1, commit 1b WITHOUT the
two betanin volumes/mounts and add them with phase 2 — otherwise the pod
sticks in `CreateContainerConfigError` until the betanin Secret exists
(self-heals, but avoid it).

### Phase 2 — betanin (beets tagging pipeline)

**2a. `charts/betanin/Chart.yaml` — CREATE**

```yaml
apiVersion: v2
name: betanin
description: betanin + beets write-only music tagging pipeline
type: application
version: 1.0.0
appVersion: "0.6.3"
dependencies:
  - name: app-template
    version: 5.0.1
    repository: https://bjw-s-labs.github.io/helm-charts/
```

Then `helm dependency update charts/betanin` (generates Chart.lock).

**2b. `charts/betanin/values.yaml` — CREATE**

```yaml
bitwardenIds:
  betanin: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName betanin

  controllers:
    betanin:
      annotations:
        reloader.stakater.com/auto: "true"
      initContainers:
        # Seed config.toml from the ESO-rendered secret on FIRST boot only;
        # afterwards betanin owns the file on its PVC (UI edits persist).
        config-init:
          image:
            repository: docker.io/sentriz/betanin
            tag: v0.6.3
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -e
              if [ ! -f /b/.config/betanin/config.toml ]; then
                cp /tpl/config.toml /b/.config/betanin/config.toml
              fi
      pod:
        securityContext:
          fsGroup: 1000
          fsGroupChangePolicy: OnRootMismatch
          # Shared-media group (jellyfin/tvheadend convention) so tagged
          # files on the SeaweedFS share stay group-readable.
          supplementalGroups:
            - 2000
      containers:
        main:
          image:
            repository: docker.io/sentriz/betanin
            tag: v0.6.3
          env:
            TZ: America/Denver
            BETANIN_HOST: 0.0.0.0
            BETANIN_PORT: "9393"
            # Image entrypoint adduser's to UID/GID then drops via sudo.
            UID: "1000"
            GID: "1000"
          probes:
            liveness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 9393
                initialDelaySeconds: 30
                periodSeconds: 10
            readiness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 9393
                initialDelaySeconds: 30
                periodSeconds: 10
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              memory: 2Gi
          securityContext:
            # Image entrypoint needs sudo (setuid) to drop from root to
            # UID/GID — documented exception to allowPrivilegeEscalation:false
            # (same class as tvheadend's tuner exception).
            allowPrivilegeEscalation: true
            capabilities:
              drop:
                - ALL

  service:
    betanin:
      controller: *chartName
      type: ClusterIP
      ports:
        http:
          port: 9393

  persistence:
    config:
      existingClaim: betanin-config
      globalMounts:
        - path: /b/.config/betanin
    data:
      # betanin SQLite DB — block storage, never the SeaweedFS share.
      existingClaim: betanin-data
      globalMounts:
        - path: /b/.local/share/betanin
    beetsdb:
      # beets library.db — block storage, never the SeaweedFS share.
      existingClaim: betanin-beets
      globalMounts:
        - path: /b/.config/beets-db
    beetsconfig:
      type: secret
      name: betanin
      globalMounts:
        - path: /b/.config/beets/config.yaml
          subPath: beets-config.yaml
          readOnly: true
    config-tpl:
      type: secret
      name: betanin
      globalMounts:
        - path: /tpl/config.toml
          subPath: config.toml
          readOnly: true
    media:
      existingClaim: media
      globalMounts:
        - path: /media
```

**2c. `charts/betanin/templates/secret-betanin.yaml` — CREATE**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: betanin
spec:
  refreshInterval: 1h
  target:
    name: betanin
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        BETANIN_API_KEY: "{{ `{{ .api_key }}` }}"
        config.toml: |
          [frontend]
          username = "{{ `{{ .username }}` }}"
          password = "{{ `{{ .password }}` }}"

          [clients]
          api_key = "{{ `{{ .api_key }}` }}"

          [server]
          num_parallel_jobs = 1

          [notifications.services]

          [notifications.strings]
          body  = "@ $time. view/use the console at http://127.0.0.1:9393/$console_path"
          title = "[betanin] torrent `$name` $status"
        beets-config.yaml: |
          directory: /media/Music/automation
          library: /b/.config/beets-db/library.db

          import:
            move: no
            copy: no
            write: yes
            quiet: yes
            quiet_fallback: skip
            timid: no
            resume: no

          plugins: chroma fetchart embedart lastgenre replaygain

          chroma:
            auto: yes
          acoustid:
            apikey: {{ `{{ .acoustid_key }}` }}
          fetchart:
            sources: coverart itunes amazon albumart
          embedart:
            auto: yes
          lastgenre:
            auto: yes
            source: album
          lastfm:
            api_key: {{ `{{ .lastfm_key }}` }}
          replaygain:
            backend: ffmpeg
  data:
    - secretKey: username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "betanin" }}'
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
        key: '{{ index .Values "bitwardenIds" "betanin" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "betanin" }}'
        property: api_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: acoustid_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "betanin" }}'
        property: acoustid_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: lastfm_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "betanin" }}'
        property: lastfm_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

(The `{{ `{{ ... }}` }}` double-escaping keeps Helm from evaluating the ESO
template placeholders at render time — same trick as `secret-qdrant.yaml`.)

**2d. `charts/betanin/templates/pvc-betanin-config.yaml`,
`pvc-betanin-data.yaml`, `pvc-betanin-beets.yaml` — CREATE** (three files,
same shape; names/sizes as listed):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: betanin-config   # betanin-data / betanin-beets in the other files
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

**2e. `services/media/prod/templates/configmap-lidarr-betanin-script.yaml` — CREATE**

```yaml
# Lidarr custom script (Settings -> Connect -> Custom Script, On Import /
# On Upgrade): /config/scripts/betanin.sh. Pushes completed album paths to
# betanin's API for beets tagging. API key comes from the betanin
# ExternalSecret mounted into the lidarr pod (see lidarr: volumes in
# services/media/prod/values.yaml).
apiVersion: v1
kind: ConfigMap
metadata:
  name: lidarr-betanin-script
  namespace: default
data:
  betanin.sh: |
    #!/usr/bin/env bash
    # Lidarr -> betanin custom script. Env vars per Servarr wiki:
    # https://wiki.servarr.com/lidarr/custom-scripts
    set -euo pipefail

    [ "${lidarr_eventtype:-}" = "Download" ] || [ "${lidarr_eventtype:-}" = "AlbumDownload" ] || exit 0

    BETANIN_URL="http://media-betanin:9393/api/torrents"
    API_KEY="$(cat /config/secrets/betanin/api_key)"

    TARGET="${lidarr_artist_path:-}"
    [ -n "${lidarr_addedtrackpaths:-}" ] && TARGET="$(dirname "${lidarr_addedtrackpaths%%|*}")"

    curl -fsS --data-urlencode "both=${TARGET}" \
      --header "X-API-Key: ${API_KEY}" \
      "${BETANIN_URL}"
```

**2f. `services/media/prod/values.yaml` — MODIFY** (charts map + ingress):

```yaml
charts:
  # ... existing entries ...
  betanin:
    namespace: default
    ServerSideApply: "false"

ingress:
  subdomains:
    # ... existing entries ...
    betanin:
      serviceName: betanin
      service: media-betanin
      port: 9393
```

**2g. `services/proxy-local/prod/values.yaml` — MODIFY**: add under
`proxy.subdomains` (plain entry = entrypoint middlewares crowdsec +
ipAllowList; betanin has its own web login):

```yaml
    betanin:
      target: betanin
```

### Phase 3 — slskd (Soulseek, no VPN for now)

**3a. `charts/slskd/Chart.yaml` — CREATE** (same shape as betanin's;
`name: slskd`, `appVersion: "0.26.0"`, app-template 5.0.1) +
`helm dependency update`.

**3b. `charts/slskd/values.yaml` — CREATE**

```yaml
bitwardenIds:
  slskd: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName slskd

  controllers:
    slskd:
      annotations:
        reloader.stakater.com/auto: "true"
      pod:
        securityContext:
          fsGroup: 1000
          fsGroupChangePolicy: OnRootMismatch
          supplementalGroups:
            - 2000
      containers:
        main:
          image:
            repository: docker.io/slskd/slskd
            # VERIFY plain `0.26.0` tag exists at impl time; else pin
            # 0.26.0.65534-042701b5 (verified current, 2026-09-14).
            tag: "0.26.0"
          env:
            TZ: America/Denver
          probes:
            liveness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 5030
                initialDelaySeconds: 30
                periodSeconds: 10
            readiness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 5030
                initialDelaySeconds: 30
                periodSeconds: 10
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              memory: 1Gi
          securityContext:
            # slskd image runs as root by default; no setuid needed, so the
            # standard hardening holds. TODO: verify a non-root story later.
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  service:
    slskd:
      controller: *chartName
      type: ClusterIP
      ports:
        http:
          port: 5030
        soulseek:
          port: 50300

  persistence:
    data:
      existingClaim: slskd
      globalMounts:
        - path: /app
    config:
      type: secret
      name: slskd
      globalMounts:
        - path: /app/slskd.yml
          subPath: slskd.yml
          readOnly: true
    media:
      existingClaim: media
      globalMounts:
        - path: /media
```

**3c. `charts/slskd/templates/secret-slskd.yaml` — CREATE**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: slskd
spec:
  refreshInterval: 1h
  target:
    name: slskd
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        slskd.yml: |
          directories:
            downloads: /media/downloads
            incomplete: /media/downloads/incomplete
          shares:
            directories:
              - /media/Music/automation
          web:
            authentication:
              api_keys:
                tubifarry:
                  key: {{ `{{ .api_key }}` }}
                  role: readwrite
                  cidr: 0.0.0.0/0
          soulseek:
            username: {{ `{{ .username }}` }}
            password: {{ `{{ .password }}` }}
            listen_port: 50300
  data:
    - secretKey: username
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "slskd" }}'
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
        key: '{{ index .Values "bitwardenIds" "slskd" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: api_key
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "slskd" }}'
        property: api_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

**3d. `charts/slskd/templates/pvc-slskd-default.yaml` — CREATE** (PVC `slskd`,
RWO, 1Gi — shape identical to 2d).

**3e. `services/media/prod/values.yaml` — MODIFY**:

```yaml
charts:
  slskd:
    namespace: default
    ServerSideApply: "false"

ingress:
  subdomains:
    slskd:
      serviceName: slskd
      service: media-slskd
      port: 5030
```

**3f. `services/proxy-local/prod/values.yaml` — MODIFY**:

```yaml
    slskd:
      target: slskd
```

### Phase 4 — spotDL CronJob (keyless)

**4a. `charts/spotdl/Chart.yaml` — CREATE** (`name: spotdl`,
`appVersion: "4.5.2"`, app-template 5.0.1) + `helm dependency update`.

**4b. `charts/spotdl/values.yaml` — CREATE**

```yaml
# No secrets: keyless spotDL mode (Spotify's 2026-03 policy makes dev-app
# credentials Premium-gated; revisit if the user gets a client id/secret).
domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName spotdl

  controllers:
    spotdl:
      type: cronjob
      cronjob:
        schedule: "0 4 * * *"
        concurrencyPolicy: Forbid
        ttlSecondsAfterFinished: 3600
        backoffLimit: 1
      pod:
        restartPolicy: OnFailure
        securityContext:
          # v4.5.x images run non-root; gid 2000 = shared-media group so
          # Jellyfin can read what spotDL writes on the SeaweedFS share.
          runAsUser: 1000
          runAsGroup: 2000
          fsGroup: 2000
          fsGroupChangePolicy: OnRootMismatch
          supplementalGroups:
            - 2000
      containers:
        main:
          image:
            repository: docker.io/spotdl/spotify-downloader
            tag: v4.5.2
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              cd /config
              OUT='/media/Music/automation/{artist}/{album}/{title}.{output-ext}'
              COMMON="--output $OUT --format flac --sync-without-deleting --threads 4 --cache-dir /config"
              if [ -f playlists.spotdl ]; then
                spotdl sync playlists.spotdl $COMMON
              else
                # First run: bootstrap the sync file from the URL list.
                spotdl sync $(tr '\n' ' ' < /playlists/playlists.txt) --save-file playlists.spotdl $COMMON
              fi
          env:
            TZ: America/Denver
            HOME: /config
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              memory: 4Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  persistence:
    config:
      # .spotdl sync file + cache — block storage.
      existingClaim: spotdl
      globalMounts:
        - path: /config
    playlists:
      type: configMap
      name: spotdl-playlists
      globalMounts:
        - path: /playlists
    media:
      existingClaim: media
      globalMounts:
        - path: /media
```

**4c. `charts/spotdl/templates/configmap-spotdl-playlists.yaml` — CREATE**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: spotdl-playlists
  namespace: default
data:
  # One Spotify URL per line (playlist / album / artist). Consumed by the
  # spotdl cronjob on FIRST run only to bootstrap /config/playlists.spotdl;
  # afterwards edit via the .spotdl file semantics or delete the PVC file to
  # re-bootstrap. OVERRIDE_NEEDED: replace the example before enabling.
  playlists.txt: |
    # https://open.spotify.com/playlist/<id>
```

**4d. `charts/spotdl/templates/pvc-spotdl-default.yaml` — CREATE** (PVC
`spotdl`, RWO, 2Gi).

**4e. `services/media/prod/values.yaml` — MODIFY**:

```yaml
charts:
  spotdl:
    namespace: default
    ServerSideApply: "false"
```

(No ingress entry — headless cronjob. No proxy-local entry.)

### Phase 5 — Explo (ListenBrainz discovery)

**5a. VERIFY chart version first:**

```bash
helm repo add explo https://lumepart.github.io/Explo
helm search repo explo --versions
helm show values explo/explo --version <current>   # confirms env/key names
```

**5b. `charts/explo/Chart.yaml` — CREATE** (wrapper):

```yaml
apiVersion: v2
name: explo
description: Explo - ListenBrainz discovery for self-hosted music stacks (wrapper)
type: application
version: 1.0.0
dependencies:
  - name: explo
    version: <VERIFIED in 5a>
    repository: https://lumepart.github.io/Explo
```

+ `helm dependency update charts/explo`.

**5c. `charts/explo/values.yaml` — CREATE** (subchart keys MUST be reconciled
with `helm show values` output — the exact env plumbing is chart-specific):

```yaml
bitwardenIds:
  explo: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

explo:
  # VERIFY key paths against `helm show values explo/explo`.
  # Intent: ListenBrainz discovery -> album requests downloaded via Lidarr
  # (Tubifarry provides the actual download clients inside Lidarr).
  env:
    LISTENBRAINZ_DISCOVERY: playlist
    DOWNLOAD_SERVICES: lidarr
    LIDARR_URL: http://media-lidarr:8686
  # Wire LISTENBRAINZ_TOKEN + LIDARR_API_KEY from the explo Secret via the
  # subchart's envFrom/extraEnv mechanism (verified in 5a).
```

**5d. `charts/explo/templates/secret-explo.yaml` — CREATE**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: explo
spec:
  refreshInterval: 1h
  target:
    name: explo
    creationPolicy: Owner
  data:
    - secretKey: LISTENBRAINZ_TOKEN
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "explo" }}'
        property: listenbrainz_token
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: LIDARR_API_KEY
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "explo" }}'
        property: lidarr_api_key
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

**5e. `services/media/prod/values.yaml` — MODIFY**:

```yaml
charts:
  explo:
    namespace: default
    ServerSideApply: "true"
```

(No ingress/proxy entries — Explo is headless.)

### Phase 6 — AudioMuse-AI (Jellyfin integration, AI provider NONE)

**6a. `charts/audiomuse-ai/Chart.yaml` — CREATE** (wrapper):

```yaml
apiVersion: v2
name: audiomuse-ai
description: AudioMuse-AI - AI music discovery for Jellyfin (wrapper)
type: application
version: 1.0.0
dependencies:
  - name: audiomuse-ai
    version: 1.1.6   # verified in the chart index 2026-09-20
    repository: https://NeptuneHub.github.io/AudioMuse-AI-helm
```

+ `helm dependency update charts/audiomuse-ai`, then
`helm show values charts/audiomuse-ai` (or the repo) to confirm
`postgres.existingSecret`/`existingSecretKeys`, `image.tag`, `config.*` and
`jellyfin.*` key paths before finalizing 6b.

**6b. `charts/audiomuse-ai/values.yaml` — CREATE** (reconcile keys per 6a):

```yaml
bitwardenIds:
  audiomuse-ai: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

audiomuse-ai:
  image:
    # Chart default is `latest` — repo rule forbids it. VERIFY current 1.1.x
    # tag at ghcr.io/neptunehub/audiomuse-ai and pin it here.
    tag: "<VERIFIED 1.1.x tag>"
  config:
    mediaServerType: jellyfin
    # NONE for now: llama-swap (the lab's LLM proxy) speaks OpenAI/Anthropic
    # APIs, not Ollama's native API, so the OLLAMA provider can't use it.
    # Reconfigure later via the AudioMuse Setup Wizard if desired.
    aiModelProvider: NONE
  jellyfin:
    url: http://media-jellyfin:8096
    # userId + token come from the audiomuse-ai Secret (6c) — wire via the
    # subchart's secret/env mechanism verified in 6a.
  postgres:
    enabled: true          # chart-bundled Postgres; no CNPG on media cluster
    existingSecret: audiomuse-ai
    # existingSecretKeys: remap to the Secret's key names (verified in 6a)
```

**6c. `charts/audiomuse-ai/templates/secret-audiomuse-ai.yaml` — CREATE**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: audiomuse-ai
spec:
  refreshInterval: 1h
  target:
    name: audiomuse-ai
    creationPolicy: Owner
  data:
    - secretKey: postgres-password
      sourceRef:
        storeRef:
          name: bitwarden-login
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "audiomuse-ai" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: jellyfin-user-id
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "audiomuse-ai" }}'
        property: jellyfin_user_id
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: jellyfin-token
      sourceRef:
        storeRef:
          name: bitwarden-fields
          kind: SecretStore
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "audiomuse-ai" }}'
        property: jellyfin_token
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

**6d. `services/media/prod/values.yaml` — MODIFY**:

```yaml
charts:
  audiomuse-ai:
    namespace: default
    ServerSideApply: "true"

ingress:
  subdomains:
    audiomuse:
      serviceName: audiomuse
      service: media-audiomuse-ai   # VERIFY rendered Service name via
      port: 8000                    # helm template; adjust to the chart's web svc
```

**6e. `services/proxy-local/prod/values.yaml` — MODIFY**:

```yaml
    audiomuse:
      target: audiomuse
```

### Phase 7 — custom-values UUIDs (needs the user's Bitwarden items)

**7a. USER steps — create Bitwarden items** (one per concern, per repo
convention):

| Item (type) | Username | Password | Custom fields |
|---|---|---|---|
| `betanin` (Login) | betanin web login name | betanin web password | `api_key` (generate any strong random string; must match what Lidarr sends — it reads the same field), `acoustid_key` (acoustid.org API key), `lastfm_key` (Last.fm API key) |
| `slskd` (Login) | Soulseek username | Soulseek password | `api_key` (strong random string for Tubifarry) |
| `explo` (Login or Note) | — | — | `listenbrainz_token` (ListenBrainz profile → token), `lidarr_api_key` (Lidarr → Settings → General → Security → API Key) |
| `audiomuse-ai` (Login) | — | Postgres password for AudioMuse | `jellyfin_user_id` + `jellyfin_token` (Jellyfin → user profile → API Keys; user id from the key details/user page) |

**7b. `custom-values/media/prod-values.yaml` — MODIFY**: add per-app keys
(top-level, same level as the existing `hivetools:` block — these ride the
charts-appset values slice into each chart's `bitwardenIds`):

```yaml
betanin:
  bitwardenIds:
    betanin: <UUID-of-Bitwarden-item-betanin>
slskd:
  bitwardenIds:
    slskd: <UUID-of-Bitwarden-item-slskd>
explo:
  bitwardenIds:
    explo: <UUID-of-Bitwarden-item-explo>
audiomuse-ai:
  bitwardenIds:
    audiomuse-ai: <UUID-of-Bitwarden-item-audiomuse-ai>
```

Until UUIDs are filled, the ExternalSecrets stay unready and the pods stay
Pending — the repo's accepted visible-failure mode.

### Phase 8 — USER configuration steps (after ArgoCD syncs)

a) **Lidarr nightly verification**: UI loads → **System → Plugins** page
   exists. If `/ping` probes fail on LSIO nightly (pod restarts), report —
   the bubylou chart hardcodes the probe path and would need a chart fix.
b) **Install plugins** (System → Plugins → paste URL → Install, then restart
   Lidarr when prompted):
   - `https://github.com/TypNull/Tubifarry` (v2.2.0.5, min Lidarr 3.1.5.0 ✓)
   - `https://github.com/RicherTunes/Brainarr` (v1.6.1)
c) **Tubifarry settings**:
   - slskd download client: URL `http://media-slskd:5030`, API key = the
     `slskd` item's `api_key` field. Verify the auto-fetched download path
     resolves to `/media/downloads` (add a Remote Path mapping if not).
   - YouTube download client: download path under `/media/downloads`;
     cookies/Trusted Session Generator only if bot detection appears.
   - Spotify playlist import list via the Spotify catalog indexer if wanted.
   - Optional: Codec Tinker (Settings → Metadata), Lyrics Fetcher + `lrc`
     under Media Management → Import Extra Files.
   - ListenBrainz ImportLists: enable + paste the ListenBrainz token.
d) **Brainarr import list**: Provider = the OpenAI-compatible option ("LM
   Studio"-style), Base URL `https://llama-cpp.spencerslab.com/v1`, Model
   `qwen3.6-35b-a3b-q6`. Tune Discovery Mode / MinConfidence later.
e) **Lidarr custom script**: Settings → Connect → Custom Script → path
   `/config/scripts/betanin.sh`, triggers On Import / On Upgrade.
f) **llama-swap connectivity test** (run from the media cluster before
   trusting (d)):

   ```bash
   kubectl -n default exec deploy/media-lidarr -- curl -fsS -m 30 \
     https://llama-cpp.spencerslab.com/v1/models
   ```

   Expect a JSON model list. If DNS/auth fails: fallback 1 — resolve via
   `llama.spencerslab.com`; fallback 2 — add a dedicated gpu ingress for
   llama-swap; fallback 3 — reopen the Ollama-on-media discussion.
g) **betanin UI** (`https://betanin.<domain>`): log in with the `betanin`
   item's credentials; confirm Settings shows the same API key; test with a
   completed album path POST.
h) **spotDL playlists**: edit `charts/spotdl/templates/configmap-spotdl-playlists.yaml`
   `playlists.txt` with real Spotify URLs (remove OVERRIDE_NEEDED), commit.
   Manual first run: `kubectl -n default create job --from=cronjob/media-spotdl spotdl-bootstrap`.
i) **AudioMuse-AI** (`https://audiomuse.<domain>`): complete the Setup Wizard
   (Jellyfin creds already injected; AI provider stays NONE). Verify the
   media node has AVX2 (`grep -o avx2 /proc/cpuinfo | head -1` on the media
   host) — AudioMuse crashes without it.
j) **Lidarr root folder**: ensure `/media/Music/automation` is a Lidarr root
   folder (Settings → Media Management) and matches betanin/beets
   `directory` + slskd/Tubifarry import paths.

## Verification

Pre-merge (Code agent runs all, fixes failures):

1. Per new chart: `helm lint charts/<name>` and
   `helm template charts/<name> --set domain=spencerslab.com --set bitwardenIds.<name>=test-uuid`
   (spotdl: no bitwardenIds set needed). Grep output for `OVERRIDE_` — zero
   hits.
2. Umbrella render (run `helm dependency update services/media/prod` first):

   ```bash
   helm template media services/media/prod -f services/media/prod/values.yaml \
     --set domain=spencerslab.com --set clusterName=media \
     --set bitwardenIds.argocd-mcp=test-uuid \
     --show-only templates/configmap-lidarr-betanin-script.yaml
   helm template media services/media/prod -f services/media/prod/values.yaml \
     --set domain=spencerslab.com --set clusterName=media \
     --set bitwardenIds.argocd-mcp=test-uuid \
     --show-only charts/lidarr/templates/deployment.yaml
   ```

   Confirm the lidarr Deployment shows the LSIO nightly image, PUID/PGID,
   betanin script + secret mounts; confirm the betanin script ConfigMap
   renders.
3. Service trio grep:

   ```bash
   for app in betanin slskd spotdl explo audiomuse-ai; do
     grep -n "$app" services/media/prod/values.yaml custom-values/media/prod-values.yaml
   done
   grep -n "betanin\|slskd\|audiomuse" services/proxy-local/prod/values.yaml
   ```

   Every app: charts entry present; betanin/slskd/audiomuse have ingress +
   proxy entries; all four secret-bearing apps have custom-values UUID
   placeholders filled (or explicitly empty pending user items).
4. File presence: Chart.yaml + Chart.lock + values.yaml + templates/ for each
   new chart.

Post-merge (ArgoCD applies; verify with `readonly-media-kubernetes`):

5. Applications `media-betanin`, `media-slskd`, `media-spotdl`, `media-explo`,
   `media-audiomuse-ai` Synced/Healthy (Pending pods accepted until Bitwarden
   UUIDs land); umbrella `media` Synced.
6. ExternalSecrets `betanin`, `slskd`, `explo`, `audiomuse-ai` Ready=True
   after UUIDs are set; target Secrets exist with the rendered file keys
   (`config.toml`, `beets-config.yaml`, `slskd.yml`).
7. Pods Running: media-lidarr (LSIO nightly image confirmed in
   `spec.containers[].image`), betanin, slskd, explo, audiomuse-ai stack;
   CronJob `media-spotdl` present with schedule `0 4 * * *`.
8. Ingresses `betanin-ingress`, `slskd-ingress`, `audiomuse-ingress` exist
   with hosts `<name>.spencerslab.com`.
9. Functional tests (user-run where noted): phase 8 items — plugin pages,
   betanin API POST test, spotdl bootstrap job logs, llama-swap curl from
   media, AudioMuse wizard completion.

## Rollback

- **Any single service**: remove its `charts:` entry + ingress/proxy entries
  + custom-values block; delete `charts/<name>/`. ArgoCD prunes everything
  except PVCs (Retain) — data survives.
- **Lidarr nightly**: restore the phase-1a `/config` backup into the `lidarr`
  PVC, then revert the `lidarr:` block to the pre-change image (remove
  `image:` override → chart default hotio release). Do NOT revert the image
  without restoring the backup — nightly's DB cannot downgrade.
- **betanin script in lidarr**: drop the two betanin volumes/mounts from the
  lidarr block; delete the ConfigMap template. betanin itself can stay.
- Wrapper charts (explo/audiomuse-ai): removing the charts entry prunes the
  deployments; bundled Postgres PVCs survive (data retained).

## Risks & open questions

- **Lidarr nightly migration is one-way** — backup (phase 1a) is the only
  rollback. LSIO `/ping` probe support on nightly is expected (app-level
  endpoint, hotio chart already probes it) but unverified on LSIO; if probes
  fail, the bubylou chart offers no probe override → needs chart patch or
  image fallback.
- **Brainarr ↔ llama-swap is UNVERIFIED end-to-end**: Brainarr must have an
  OpenAI-compatible provider (its "LM Studio"/custom provider) and llama-swap
  must be reachable from the media cluster through lab DNS + the hub
  ipAllowList (10.0.0.0/16 covers NAT'd pod traffic). Phase 8f tests this;
  fallbacks listed there. Also expect first-request latency: llama-swap runs
  one GPU model at a time and will swap models if Brainarr's model isn't
  loaded.
- **slskd tag**: plain `0.26.0` unconfirmed in the first page of registry
  results; pinned fallback `0.26.0.65534-042701b5` verified.
- **slskd without VPN**: Soulseek connectivity may be restricted/flaky
  depending on the network; gluetun sidecar is a documented follow-up
  (needs VPN provider credentials + NET_ADMIN exception).
- **spotDL keyless mode** is less reliable for playlist/album metadata at
  scale (guide's caveat); Spotify's 2026-03 policy (Premium-gated dev apps,
  5 users, 1 client id) applies if official API is ever added.
- **Explo chart values are unverified** — phase 5a reconciles env/key names
  before commit; if the chart can't consume an existing Secret for its env,
  fall back to the chart's own secret mechanism fed by the same Bitwarden
  item.
- **AudioMuse-AI**: chart `image.tag` default is `latest` (must pin a real
  1.1.x tag); `postgres.existingSecret` support claimed by the guide but
  unverified (phase 6a); AVX2 requirement on the media node unverified
  (phase 8i); Redis still deployed by the chart although optional — harmless.
- **SeaweedFS write permissions** for new writers (betanin/beets, spotdl,
  slskd) rely on the gid-2000 convention; verify Jellyfin can read new files
  after the first imports (scan library).
- **lidarr PVC is only 1Gi** — plugins + nightly DB growth may pressure it;
  local-path PVCs can't be resized in place, so watch usage and migrate to a
  larger PVC (backup/restore) if needed.
- **Pre-existing**: umbrella Application `media` is currently Degraded for
  unrelated reasons — don't confuse with this work's effects.
