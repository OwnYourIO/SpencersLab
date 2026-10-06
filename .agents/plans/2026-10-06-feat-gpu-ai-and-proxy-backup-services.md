# Plan: gpu-ai + proxy-backup services (feat)

- **Date:** 2026-10-06
- **Branch:** `feat/gpu-ai-proxy-backup-services`
- **Agent:** code
- **Skills loaded:** executing-plans, helm-chart-creation, helm-bjw-s-chart
  (+ `references/values-and-appset.md`, `references/proxying.md`,
  `references/storage-and-secrets.md`)

## Goal

Two new service categories for two brand-new clusters:

1. **gpu-ai** (cluster `ai-gpu`) — dedicated AI inference service, carved out
   of gpu. Charts: `llama-swap`, `amd-gpu` (external rocm device plugin),
   `external-secrets-bitwarden`, `k8s-monitoring`.
   URLs: `cluster.ai-gpu.<domain>`, `mcp.ai-gpu.<domain>` (rendered
   automatically by hivetools via base), `ai-llama-swap.<domain>`.
2. **proxy-backup** (cluster `proxy-backup`) — consolidates the
   download/archive/media workloads (name is a historical misnomer, per user).
   Charts: `qbittorrent`, `metube`, `pinchflat-ngx` (new charts), `jellyfin`,
   `prowlarr` (existing charts), `seaweedfs-csi-driver`,
   `external-secrets-bitwarden`, `k8s-monitoring`.
   URLs: `cluster.proxy-backup.<domain>`, `mcp.proxy-backup.<domain>`,
   `backup-torrents.<domain>` (qbittorrent), `backup-player.<domain>`
   (jellyfin), `backup-stream.<domain>` (metube), `backup-streams.<domain>`
   (pinchflat-ngx), `backup-prowlarr.<domain>` (prowlarr).

## Decisions confirmed with the user (in-session)

- **pinchflat-ng → `pinchflat-ngx`**: the image is
  `ghcr.io/thebadfella/pinchflat-ngx:2026.9.28` (active fork of pinchflat:
  Material 3 UI, SQLite default, disk staging). The communitymaintained fork
  images turned out to be gone (GHCR denies pulls, pulled off Docker Hub,
  repos archived) — verified before charting.
- **Media storage**: SeaweedFS-backed PV/PVC named `media` on the
  proxy-backup cluster, reusing the existing **`backup-gpu` collection**
  (same collection proxy-local's backup-gpu-qbittorrent writes to).
- **Extras on proxy-backup**: `k8s-monitoring` + `external-secrets-bitwarden`
  added (parity with every other cluster).
- **Clusters**: two NEW clusters (`ai-gpu`, `proxy-backup`); cluster
  bootstrap (K3s install, ArgoCD cluster-secret annotations incl.
  `services.<svc>.customValuesUrls`, the bootstrap Application pointing at
  `services/<category>/prod`, and mesh DNS records for `ai-gpu.<domain>` /
  `proxy-backup.<domain>` → each cluster's traefik) is user-owned.
- **Hub auth**: default crowdsec + Keycloak forward-auth on all six new
  public subdomains (no app-side SSO wiring).
- **Existing services stay untouched**: proxy-local's inline
  qbittorrent/metube/pinchflat deployments are NOT converted. The new charts
  are consumed only by proxy-backup; the user will convert the existing
  services after testing. The only edit to proxy-local is the six new hub
  routing entries (required for the new URLs).

## Changes

### New charts

- `charts/qbittorrent/` — converted from proxy-local's inline app-template
  block: onedr0p/qbittorrent:5.0.4, `QBITTORRENT__PORT 8080` /
  `QBITTORRENT__BT_PORT 58462`, LoadBalancer BT service
  (`externalTrafficPolicy: Local`), config PVC (`existingClaim: qbittorrent`,
  created by the service umbrella) + `media` PVC. No secrets.
- `charts/metube/` — converted from proxy-local's inline block, refreshed:
  image pinned `ghcr.io/alexta69/metube:2025-05-01` (inline ran a 2024-05-28
  digest pin), `/media/Streams` download/state/temp layout kept, TCP probes
  added, dropped the dead `donwloads` emptyDir and the legacy `nfsMount`
  label. No secrets.
- `charts/pinchflat-ngx/` — new: `ghcr.io/thebadfella/pinchflat-ngx:2026.9.28`,
  port 8945, `MEDIA_PATH=/media` (SeaweedFS-backed), `DOWNLOAD_STAGING_PATH=/staging`
  (emptyDir — finishes downloads on local disk before moving to the network
  library), `/healthcheck` probes, config PVC `pinchflat-ngx`. **One secret:**
  `SECRET_KEY_BASE` via ExternalSecret (`templates/secret-pinchflat-ngx.yaml`,
  `bitwarden-login` store, property `password`) — required for an
  internet-facing deployment per NGX docs. OIDC env left for a later change
  (hub forward-auth gates access meanwhile).

### Existing chart cleanup

- `charts/jellyfin/` (currently referenced by NO service — safe to shape):
  removed dead `bitwardenIds.samba-users: OVERRIDE_NEEDED` (nothing consumed
  it), service `LoadBalancer → ClusterIP`, removed the `jellyfin.local`
  ingress + `JELLYFIN_PublishedServerUrl` hardcode (both now set by the
  consuming service), `existingClaim: media-shared → media` (repo-wide PVC
  naming convention). Probes/resources/security kept.

### New services

- `services/gpu-ai/prod/` — `Chart.yaml` (umbrella, no deps), `values.yaml`
  (`charts:` = llama-swap, external-secrets-bitwarden, k8s-monitoring,
  amd-gpu external 0.21.0 @ rocm; `ingress.subdomains` = `ai-llama-swap` →
  `gpu-ai-llama-swap:8080`, `cluster` clusterBase → argocd-server;
  `llama-swap:` empty block, no overrides), `templates/appset.yaml`
  (`gpu-ai-appset`, `baseChartVersion: 1.0.194`), `templates/generic-ingress.yaml`
  (gpu style incl. llama ServersTransport annotation),
  `templates/servicestransport-llama.yaml`.
- `services/proxy-backup/prod/` — `Chart.yaml` (umbrella, no deps),
  `values.yaml` (`charts:` = the 8 charts above; `ingress.subdomains` =
  backup-torrents → `proxy-backup-qbittorrent-main:8080` (two-service chart
  renders the `-main` suffix), backup-player → jellyfin:8096, backup-stream →
  metube:8081, backup-streams → pinchflat-ngx:8945, backup-prowlarr →
  prowlarr:9696, cluster + traefik clusterBase; `jellyfin:` service-level
  env (TZ, `JELLYFIN_PublishedServerUrl: https://backup-player.spencerslab.com`);
  `pinchflat-ngx: bitwardenIds` sentinel), `templates/appset.yaml`
  (`proxy-backup-appset`, `baseChartVersion: 1.0.194`),
  `templates/generic-ingress.yaml` (media style + clusterBase cert fix),
  PVC templates (`pvc-{qbittorrent,pinchflat-ngx,jellyfin,prowlarr}-default.yaml`
  1Gi each; `pvc-media-seaweedfs.yaml` PV+PVC `media` on collection
  `backup-gpu`; `seaweedfs-volume-0-service.yaml` ExternalName).

### custom-values

- `custom-values/gpu-ai/prod-values.yaml` — base IDs (cert-manager solver
  token, argocd-sso-secret; shared lab-wide UUIDs) + hivetools
  (`mcp-sso`, `keycloak.realm: SpencersLab`).
- `custom-values/proxy-backup/prod-values.yaml` — same base/hivetools blocks
  + `seaweedfs-csi-driver` (`volume-count: 8` nested per the home-cluster
  regression note, filer endpoints) + `pinchflat-ngx.bitwardenIds.pinchflat-ngx:
  OVERRIDE_NEEDED` (user creates the Bitwarden LOGIN item and fills the UUID).

### Hub routing (proxy-local values — existing service, entries only)

- `services/proxy-local/prod/values.yaml` → `proxy.subdomains` gains
  `ai-llama-swap: {target: ai-gpu}` and `backup-{torrents,player,stream,
  streams,prowlarr}: {target: proxy-backup}`. Renders ExternalName services
  → `ai-gpu.<domain>` / `proxy-backup.<domain>` + public ingresses with
  crowdsec + Keycloak forward-auth (default middleware chain).

## Validation performed

- `helm dependency build` + `helm lint` — all 4 new/edited charts + both
  service umbrellas: 0 failures.
- `helm template` render checks:
  - charts: Service/Deployment/ExternalSecret names correct
    (`proxy-backup-qbittorrent-main` suffix caught and wired); no
    `OVERRIDE_*` sentinels in chart renders (test UUID for pinchflat-ngx).
  - umbrellas: gpu-ai → 2 ingresses (`ai-llama-swap.<domain>` wildcard-cert,
    `cluster.ai-gpu.<domain>` cluster-wildcard-cert) + appset +
    ServersTransport; proxy-backup → 7 ingresses (hosts/backends/TLS table
    verified), 5 PVCs + media PV + seaweedfs-volume-0 ExternalName + appset.
  - appset generator `values:` blobs parsed: charts lists complete
    (4 gpu-ai / 8 proxy-backup), per-app slices present (jellyfin env,
    pinchflat-ngx sentinel).
  - proxy-local umbrella re-rendered after the edit (216 docs parse OK);
    the 6 new hub entries verified: ExternalName targets, hosts,
    middleware chain (crowdsec + oidc-keycloak), backend `:443`.
- Remaining `OVERRIDE_*` occurrences are only inside appset generator
  `values:` JSON (resolved by cluster annotations/custom-values at deploy
  time — identical to gpu/proxy-local production behavior).

## User actions before the new clusters sync

1. Bootstrap both clusters like the existing ones: K3s + base install,
   ArgoCD cluster-secret annotations (`domain`, `clusterName`,
   `services.repo`, `values.repo`, `chart.repo`, `stage`,
   `services.<svc>.customValuesUrls` → the two new custom-values files),
   bootstrap Application → `services/<category>/prod`.
2. Mesh DNS records: `ai-gpu.<domain>` and `proxy-backup.<domain>` → the
   respective cluster's traefik LB (same mechanism as `grow.<domain>`);
   split-horizon records for the 6 public subdomains if LAN-direct access is
   wanted (public path goes via proxy-remote → hub automatically through
   external-dns).
3. Bitwarden: create LOGIN item `pinchflat-ngx` (password =
   `openssl rand -hex 64`) and put its UUID into
   `custom-values/proxy-backup/prod-values.yaml` (replaces `OVERRIDE_NEEDED`).
4. On each new cluster, edit the `bitwarden-cli` Secret created by
   external-secrets-bitwarden (blank by design) so the CLI pod can unlock
   the vault.
5. llama-swap's model roster rides from the chart defaults (tuned for the
   current gpu box's 8GB AMD card) — override per-hardware via a `llama-swap:`
   block in services/gpu-ai/prod/values.yaml when the ai-gpu hardware differs.

## Follow-ups (not in this change)

- Convert proxy-local's inline qbittorrent/metube/pinchflat to the new
  charts once the proxy-backup deployment is tested (user-owned decision).
- pinchflat-ngx OIDC SSO (Keycloak client `pinchflat-ngx`) if app-side SSO
  is wanted later; hub forward-auth covers access until then.
