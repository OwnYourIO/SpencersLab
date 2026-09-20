# Plan: Migrate Prowlarr from the deprecated Arr-Stack chart to a custom bjw-s app-template chart

## Goal

Replace Prowlarr's deprecated `bubylou/Arr-Stack` umbrella subchart (k8s-at-home lineage, archived upstream 2022) with a repo-standard custom chart `charts/prowlarr/` built on bjw-s `app-template`, deployed as its own ArgoCD Application via the media service's `charts:` map. The existing PVC `prowlarr` (1Gi, RWO, `local-path` — already SQLite-safe per the Servarr FAQ) is reused in place, preserving `prowlarr.db` and `config.xml` (including `<ApiKey>`, so all downstream *arr App syncs keep working). Scope is Prowlarr only — lidarr/radarr/sonarr/readarr/jellyseerr stay on the Arr-Stack chart for now.

## Skills

The Code agent must load (fresh session — nothing carries over):

- `helm-chart-creation` — repo chart/service-wiring workflow
- `helm-bjw-s-chart` — app-template values API
- `gitops-workflows` — ArgoCD ApplicationSet/sync behavior
- `kubernetes-skill` — manifest review

## MCP Servers

- `readonly-media-kubernetes` — inspect live state before/after (Deployment, PVC, ArgoCD-created objects).
- No `admin-*` server is needed: ArgoCD applies everything (never `kubectl apply`). The two pod-level commands in the rollout (backup + ownership check) are run by the USER — no tier grants pod exec.

## Verified context

Recon performed 2026-09-20 against this worktree + the live media cluster (`readonly-media-kubernetes`):

- **Current deployment** (namespace `default`, ArgoCD app `media`): Deployment/Service `media-prowlarr` from `prowlarr-0.3.5` (`https://bubylou.github.io/Arr-Stack`, a k8s-at-home fork), image `ghcr.io/hotio/prowlarr:release-1.32.2.4987`, empty securityContext (root), no resource limits, probes on `httpGet /ping :9696`, mounts `/config` ← PVC `prowlarr` and `/media/` ← PVC `media` (50Ti RWX SeaweedFS).
- **PVC `prowlarr`**: 1Gi, RWO, StorageClass `local-path` (default; rancher.io/local-path). Local block storage — satisfies the Servarr "SQLite must not be on network storage" rule. No new PVC or data copy required.
- **Wiring today**: `services/media/prod/Chart.yaml` (prowlarr dep at lines 16-18), old-style values block `prowlarr:` in `services/media/prod/values.yaml` (lines 207-227), PVC template `services/media/prod/templates/pvc-prowlarr-default.yaml`, ingress via `ingress.subdomains.trackers` (+ `serviceName: prowlarr` host) in the same values file → `generic-ingress.yaml`.
- **Repo standard confirmed**: 38 charts pin `app-template 5.0.1` (the guide's "5.1.0" is NOT the repo standard); custom charts deploy via `charts:` entries with git-path source (pattern: `tvheadend` in media, `charts/tvheadend/`); charts have NO `templates/common.yaml` (app-template is an application dependency; config lives under the `app-template:` values key); `Chart.lock` committed, vendored `charts/*.tgz` gitignored (ArgoCD resolves deps at sync).
- **Registry check (2026-09-20)**: the guide's image claim `2.6.3.5592@sha256:8c9ee448…` is WRONG. Actual newest version tag on `ghcr.io/home-operations/prowlarr` is **`2.1.5.5216`**, digest **`sha256:affb671fa367f4b7029d58f4b7d04e194e887ed6af1cf5a678f3c7aca5caf6ca`** (verified via ghcr tags API). Latest alpine: `3.24`.
- **Release naming**: `charts/base/templates/appset-charts.yaml` renders one Application per `charts:` entry; release name `<serviceName>-<appName>` = `media-prowlarr` → app-template fullname/service = `media-prowlarr` (release name contains nameOverride), which is exactly what the existing proxy entry `service: media-prowlarr` expects. No ingress/proxy change needed.
- Cluster state relied on: Deployment/Service/PVC/StorageClass listings above. Render checks: not yet performed (done in Verification).

## Design decisions

1. **Custom chart, not external/wrapper** — Prowlarr needs a PVC + ownership-fix init container + hardened pod spec; per `helm-chart-creation` that belongs in `charts/prowlarr/` (the deprecated arr-stack chart is unmaintained; no official Prowlarr chart exists).
2. **app-template 5.0.1** — repo-standard (38 charts); do NOT introduce 5.1.0 unilaterally (renovate can bump all charts later).
3. **Image: `ghcr.io/home-operations/prowlarr:2.1.5.5216@sha256:affb671f…`** (user-confirmed) — rootless, semver tag that renovate's helm-values manager can track (jellyfin's `tag: X@sha256:Y` proves the pattern works here). Accepted consequence: 1.32.2 → 2.1.5 runs a **one-way SQLite schema migration** on first boot, so the pre-merge `/config` backup is the rollback path.
4. **Reuse PVC `prowlarr` via `existingClaim`; PVC template stays in the media umbrella** — moving the PVC template into the new chart would flip ArgoCD ownership (umbrella prunes / chart adopts — nondeterministic race on a data-bearing object). Leaving it where it is renders the same object under the same Application: zero data risk.
5. **UID/GID 568 + chown init container** — the old pod ran rootful (hotio), so `/config` contents are root-owned; the rootless image runs as 568. A root init container (`alpine`, `CAP_CHOWN+FOWNER` only) does an idempotent `chown -R 568:568 /config`. Documented deviation from "drop ALL everywhere" (precedent: tvheadend's documented privileged exception). `fsGroup: 568` + `fsGroupChangePolicy: OnRootMismatch` alongside. No `PUID`/`PGID` env (that's a LinuxServer convention; home-operations ignores it).
6. **Ownership-flip cutover in a single merge** — both the umbrella and the new Application render a Deployment named `media-prowlarr` but with different (immutable) selectors, so they cannot coexist. One merge: umbrella prunes old Deployment/Service, new app creates them. Expected: brief Prowlarr downtime (~1-3 min) and transient `field is immutable` sync retries on `media-prowlarr` until the prune lands. PVC and ingress are untouched throughout.
7. **Auth env vars deliberately NOT set** — the guide's `PROWLARR__AUTH__METHOD: External` / `PROWLARR__AUTH__REQUIRED: DisabledForLocalAddresses` would override `config.xml` and change login behavior mid-migration. Keep `config.xml` authoritative; only `TZ` + explicit port are set.
8. **`/media` mount dropped** — Prowlarr manages indexers/app-connections only; it never reads media files (the arr-stack chart mounted it uniformly). Removing the 50Ti RWX dependency also removes a startup failure mode.
9. **`readOnlyRootFilesystem: true` + `tmp` emptyDir**, drop ALL capabilities on the app container, seccomp RuntimeDefault, startup probe budget ~150s for the first-boot DB migration.
10. **No secrets → no `bitwardenIds`, no ExternalSecret template, no custom-values entry** (the API key lives in `config.xml` on the PVC; tvheadend is the no-secrets precedent).
11. **Renovate**: add `ghcr.io/home-operations/prowlarr` to the "Non-critical services" auto-merge packageRule (consistent with the other arr apps; the old `release-*` hotio tag was never renovate-trackable — which is why Prowlarr went 267 days unupdated).

## Changes

Ordered steps. Validate at the end (see Verification) before committing.

- [x] **Step 1: `charts/prowlarr/Chart.yaml` — CREATE**

```yaml
apiVersion: v2
name: prowlarr
version: 1.0.0  # initial only — release.yaml auto-bumps patch on merge to main
appVersion: 2.1.5.5216
dependencies:
- name: app-template
  version: 5.0.1
  repository: https://bjw-s-labs.github.io/helm-charts/
```

- [x] **Step 2: `charts/prowlarr/values.yaml` — CREATE** (complete; implement as-is)

```yaml
# No bitwardenIds: Prowlarr's API key lives in /config/config.xml on the PVC,
# not in a Kubernetes secret. No ExternalSecret / custom-values entry needed.

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName prowlarr

  controllers:
    prowlarr:
      annotations:
        reloader.stakater.com/auto: "true"
      pod:
        securityContext:
          runAsNonRoot: true
          runAsUser: 568
          runAsGroup: 568
          fsGroup: 568
          fsGroupChangePolicy: OnRootMismatch
          seccompProfile:
            type: RuntimeDefault
      initContainers:
        # Ownership fix: PVC contents were written by the old rootful hotio
        # image; the rootless home-operations image runs as UID/GID 568.
        # Idempotent — intentionally kept (also repairs ownership after a
        # backup restore). Documented deviation: root + CAP_CHOWN/FOWNER.
        init-config:
          image:
            repository: alpine
            tag: "3.24"
          command: ["sh", "-c", "chown -R 568:568 /config"]
          securityContext:
            runAsUser: 0
            runAsNonRoot: false
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
              add:
                - CHOWN
                - FOWNER
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              memory: 128Mi
      containers:
        main:
          image:
            repository: ghcr.io/home-operations/prowlarr
            # Verified 2026-09-20 via ghcr tags API — re-verify before pinning.
            tag: 2.1.5.5216@sha256:affb671fa367f4b7029d58f4b7d04e194e887ed6af1cf5a678f3c7aca5caf6ca
          env:
            TZ: America/Denver
            PROWLARR__SERVER__PORT: "9696"
            # Auth env vars intentionally omitted — config.xml stays
            # authoritative so login behavior is unchanged by the migration.
          probes:
            liveness: &probes
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /ping
                  port: 9696
                initialDelaySeconds: 0
                periodSeconds: 10
                timeoutSeconds: 1
                failureThreshold: 3
            readiness: *probes
            startup:
              enabled: true
              spec:
                # First boot migrates the SQLite schema 1.32.2 -> 2.1.5.
                failureThreshold: 30
                periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              memory: 1Gi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL

  service:
    prowlarr:
      controller: *chartName
      type: ClusterIP
      ports:
        http:
          port: 9696

  persistence:
    config:
      # PVC created by services/media/prod/templates/pvc-prowlarr-default.yaml
      # (kept there on purpose — no ArgoCD ownership flip on a data volume).
      existingClaim: *chartName
      globalMounts:
        - path: /config
    tmp:
      # Required: readOnlyRootFilesystem is true.
      type: emptyDir
      globalMounts:
        - path: /tmp
```

- [x] **Step 3: generate lockfile** — run `helm dependency update charts/prowlarr` (creates `charts/prowlarr/Chart.lock`; commit the lockfile, the vendored `charts/*.tgz` is gitignored).

- [x] **Step 4: `services/media/prod/values.yaml` — MODIFY (two edits)**
  - Under `charts:`, add (mirrors the `tvheadend` entry; commented version/repository lines keep renovate tracking the published chart while the appset uses the git path source):

```yaml
  prowlarr:
    #version: 1.0.0 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
    #repository: https://ownyourio.github.io/SpencersLab/
    namespace: default
    ServerSideApply: "false"
```

  - DELETE the old arr-stack values block: the entire top-level `prowlarr:` key (current lines 207-227: `env`/`volumes`/`volumeMounts`). Do NOT touch `ingress.subdomains.trackers` (its `service: media-prowlarr`, `port: 9696` remains correct for the new release).

- [x] **Step 5: `services/media/prod/Chart.yaml` — MODIFY** — remove the prowlarr dependency (current lines 16-18):

```yaml
  - name: prowlarr
    version: 0.3.5
    repository: https://bubylou.github.io/Arr-Stack
```

Keep all other dependencies (jellyseerr/lidarr/radarr/readarr/sonarr stay on Arr-Stack; both app-template aliases stay). Then regenerate the umbrella lockfile: `helm dependency update services/media/prod` and commit the updated `services/media/prod/Chart.lock`.

- [x] **Step 6: `renovate.json` — MODIFY** — in the `"Non-critical services"` packageRule `matchPackageNames` list, add `"ghcr.io/home-operations/prowlarr"` (next to the other arr entries). `alpine` is already listed, covering the init container.

- [x] **Step 7: Validate locally** (all must pass — see Verification), then commit on the `custom-prowlarr` branch. Do NOT push to main (user merges).

### Rollout (user-gated; include these instructions in the PR description)

**Before merging to main** — the user runs (no agent tier grants pod exec):

```bash
# 1. Ownership check (informational — the init container fixes it either way):
kubectl -n default exec deploy/media-prowlarr -- ls -lan /config | head -20

# 2. Backup /config (MANDATORY — the 1.32.2 -> 2.1.5 SQLite schema migration
#    on first boot is one-way; this directory is the rollback source):
POD=$(kubectl -n default get pod -l app.kubernetes.io/name=prowlarr -o name | head -1)
kubectl -n default cp "${POD#pod/}:/config" ./prowlarr-config-backup
ls ./prowlarr-config-backup   # confirm prowlarr.db + config.xml are present
```

(Alternative: Prowlarr UI → System → Backup → Backup Now, download the zip — but keep the raw copy too.)

**After merging** — ArgoCD does everything: `media` prunes the old Deployment/Service; `media-charts-appset` generates Application `media-prowlarr` from `charts/prowlarr` on `main`; the init container chowns `/config`; Prowlarr starts, migrates the DB, and comes up on the same Service/hosts with the same API key.

## Verification

Local (Code agent, before committing):

1. `helm lint charts/prowlarr` — no errors.
2. `helm template prowlarr charts/prowlarr --set domain=test.example.com` — valid manifests; Deployment/Service `prowlarr` render (on-cluster the release is `media-prowlarr`, so names become `media-prowlarr`) with: init container `init-config` (root, CHOWN/FOWNER), main container UID 568 + digest-pinned image, probes on `:9696 /ping`, PVC mount `/config` from existing claim `prowlarr`, tmp emptyDir. Then `grep -r "OVERRIDE_"` over the rendered output — must return nothing (no template in this chart references `.Values.domain`; any `OVERRIDE_VIA_CUSTOM_VALUES` in output = failure).
3. `helm lint services/media/prod && helm template media services/media/prod --set domain=test.example.com --set clusterName=test --set serviceName=media` — renders WITHOUT any prowlarr Deployment/Service (umbrella no longer owns them) while lidarr/radarr/sonarr/readarr/jellyseerr still render; `pvc-prowlarr-default.yaml` still renders the PVC.
4. Trio grep: `grep -n "prowlarr" services/media/prod/values.yaml` → `charts:` entry present, old top-level block gone, ingress entries intact; `grep -n "prowlarr" services/media/prod/Chart.yaml` → no matches.
5. `git status` → only the intended files changed (new chart dir, two media files, renovate.json, two Chart.lock files).

Cluster (after user merges; verify with `readonly-media-kubernetes`):

6. ApplicationSet `media-charts-appset` generated Application `media-prowlarr`; app reaches Healthy/Synced (allow a few minutes of transient `field is immutable` retries on the Deployment while the old one prunes).
7. `kubectl -n default get deploy media-prowlarr -o jsonpath='{.spec.template.spec.containers[0].image}'` (via resources_get) shows the home-operations image; pod Running with init container completed.
8. User verifies (exec/UI — agent cannot): `kubectl -n default exec deploy/media-prowlarr -- grep ApiKey /config/config.xml` returns the SAME key as before; Prowlarr UI shows all indexers; Settings → Apps → Test All Apps passes for Sonarr/Radarr/Lidarr; `trackers.`/`prowlarr.` hosts behave exactly as pre-migration.

## Risks & open questions

- **One-way DB migration** — after first boot on 2.1.5, rollback = git-revert + restore `/config` from the backup taken above. If the backup step is skipped, rollback options are gone. (Mitigation is a hard merge gate in the rollout section.)
- **Ownership assumption unverified** — we could not inspect file ownership (no pod exec). The chown init container makes this self-healing regardless; if the pod instead crash-loops on DB writes, check `kubectl -n default logs deploy/media-prowlarr` and the init container logs first.
- **Brief downtime + transient sync errors** during the ownership flip are expected (Design decision 6), not a failure signal.
- **Auth unchanged by design** — if the user later wants the guide's `External`/`DisabledForLocalAddresses` auth mode, that's a separate, deliberate values change.
- **Known gap left as-is (user decision)**: proxy-local still lacks a `trackers` fan-out entry (`# TODO: Prowlarr works but not trackers?` in media values) — pre-existing, unaffected by this migration.
- **Chart version/image tag freshness**: `1.0.0` is correct only because this is a brand-new chart (CI bumps it thereafter); re-verify the `2.1.5.5216` digest at implementation time (tags published since recon are possible).
- Remaining arr apps on the deprecated Arr-Stack chart are follow-up plans (same pattern, one app each).
