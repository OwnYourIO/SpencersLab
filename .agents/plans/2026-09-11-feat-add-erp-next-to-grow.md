# Plan: Deploy ERPNext (erp-next) to the grow cluster via proxy-local

## Goal

ERPNext v16 runs on the grow cluster as app `erp-next` (release
`grow-erp-next`), deployed from the official `frappe/erpnext` Helm chart
(8.0.79) through the existing grow ApplicationSet wiring, and is published at
`https://erp.spencerslab.com` via the proxy-local hub (subdomain `erp`).
Nothing is added to proxy-remote (lab traffic reaches grow through the
existing autossh tunnel automatically). Secrets come from Bitwarden via
ExternalSecrets — no plaintext passwords in Git. Login: user `Administrator`,
password from Bitwarden.

## Skills

Code agent must load (fresh session):

- `helm-chart-creation` — external-chart wiring, sentinel/custom-values
  conventions, umbrella ExternalSecret pattern, validation steps.
- `gitops-workflows` — ArgoCD Application/ApplicationSet + Job behavior.

## MCP Servers

- `readonly-grow-kubernetes` — verify pods/jobs/PVC/ingress on grow.
- `readonly-gpu-kubernetes` — ArgoCD runs on gpu (default namespace); inspect
  the generated `grow-erp-next` Application / `grow-charts-appset` if needed.
- `admin-grow-kubernetes` — ONLY if remediation is required (e.g. delete a
  failed Job or stuck pod); ask the user for explicit confirmation first.

## Verified context

Repo recon (all paths read in this worktree):

- `services/grow/prod/values.yaml` — grow already deploys external charts the
  same way (`cloudnative-pg`: `version:` + `repository:` under `charts:`).
  Top-level `bitwardenIds:` uses `OVERRIDE_VIA_CLUSTER_ANNOTATION` /
  `OVERRIDE_VIA_CUSTOM_VALUES` sentinels; real UUIDs live in
  `custom-values/grow/prod-values.yaml` (loaded via the grow cluster secret's
  `services.grow.customValuesUrls` annotation — proven working: argocd-sso /
  cert-manager UUIDs there are live today).
- `charts/base/templates/appset-charts.yaml` — per-app Applications:
  `hasKey "version"` → Helm-repo source (`chart:` defaults to appName, so the
  `chart:` field is required because appName `erp-next` ≠ chart `erpnext`);
  release name `<serviceName>-<appName>` = `grow-erp-next`; values slice =
  top-level `erp-next:` block of the grow values (+ custom-values merge);
  helm params `domain/clusterName/serviceName/appName/namespace` are passed
  (ignored by the erpnext chart — harmless).
- `services/grow/prod/templates/generic-ingress.yaml` — renders
  `<key>.<domain>` Ingress with `wildcard-cert` TLS, backend
  `$config.service:$config.port`; external-dns target is commented out on
  grow (mesh-only publish; the proxy-local hub does the public CNAME).
- `services/proxy-local/prod/templates/proxy/` — per `proxy.subdomains`
  entry: ExternalName Service `<name>-service` → `<target|name>.<domain>`
  (lab split-horizon DNS resolves that name to the owning cluster's traefik),
  public Ingress with external-dns → `proxy-remote.<domain>` CNAME, LAN
  IngressRoute (10.0.0.0/16, 192.168.0.0/16 skips remote auth). Default
  middleware chain when `middlewares:`/`ssoRedirectPath:` unset = crowdsec +
  Keycloak forward-auth (`pictaria` pattern — user chose this).
- Umbrella ExternalSecret pattern: `services/gpu/prod/templates/secrets-open-webui.yaml`
  (external chart + Bitwarden login store, `{{ index .Values "bitwardenIds" "<key>" }}`).

Chart recon (frappe/erpnext 8.0.79 pulled to /tmp and rendered):

- Chart 8.0.79, appVersion v16.34.2; `image.tag: v16.34.2` default.
- `mariadb-sts` (built-in MariaDB 10.6 StatefulSet) and `valkey-cache` /
  `valkey-queue` (valkey 0.9.3 subcharts, standalone, no persistence, no auth)
  are the current backing services; bitnami subcharts are legacy/off.
- With `fullnameOverride: grow-erp-next` all resources render as
  `grow-erp-next*`; the main nginx Service is named exactly `grow-erp-next`
  (port 8080) — matches the repo `service: <category>-<appName>` convention.
  Verified via `helm template grow-erp-next . -f test-values.yaml` (26
  resources; rendered copy at /tmp/kilo/erpnext/rendered.yaml).
- DB root password flow: mariadb StatefulSet + create-site Job both read
  Secret `<fullname>` key `mariadb-root-password`. The chart renders that
  Secret itself ONLY when `mariadb-sts.rootPassword` is truthy — setting
  `rootPassword: ""` suppresses it (verified in render: no Secret) so an
  ExternalSecret-owned Secret of the same name supplies the password instead.
- `jobs.createSite` supports `jobName`, `annotations`, `adminExistingSecret`
  + `adminExistingSecretKey` (default key `password`). Default Job name uses
  `{{ now }}` (ArgoCD drift) for configure/createSite/migrate/backup — every
  enabled job MUST get a static `jobName`.
- create-site init container waits ≤600s for `common_site_config.json`
  (written by the configure job) and ≤180s for DB reachability — no
  sync-wave ordering needed.
- `persistence.worker.storageClass` is `required` — must be set; default
  accessModes RWX must be overridden to RWO (grow is single-node; only
  `local-path` exists, WaitForFirstConsumer — verified live).
- `ingress.enabled: false` by default — keep it; grow's generic-ingress
  serves the host instead.
- Only `job-create-site.yaml` passes annotations through (configure/migrate
  don't) — so no ArgoCD hooks; static-name plain resources instead.

Cluster state relied on (readonly MCP):

- grow: single node `grow` (10.0.3.5), 2 CPU / 12959620Ki allocatable,
  ~2.1Gi memory free at planning time; only StorageClass `local-path`
  (default, RWO); IngressClass `traefik` in use (existing ingresses show
  Class: traefik); domain `spencerslab.com` (live ingress
  `cluster.grow.spencerslab.com`); namespaces: everything in `default`.
- ArgoCD v3.4.5 runs on gpu (default namespace) and manages grow; public
  Helm repos need no registration (grow already pulls cloudnative-pg, gpu
  pulls open-webui/coder from external repos).

Render checks performed: full `helm template` of erpnext 8.0.79 with the
planned values (exit 0; names, PVC RWO/local-path, suppressed chart Secret,
adminExistingSecret wiring all confirmed).

## Design decisions

1. **Official external chart, not a custom chart.** Repo rule: maintained
   official chart → values-only `charts:` entry, no `charts/` directory.
   Chart `erpnext` from `https://helm.erpnext.com`, pinned `8.0.79`.
2. **appName `erp-next` + `chart: erpnext`.** The user's name (`erp-next`)
   differs from the upstream chart name; the `chart:` field exists for this.
   It also makes Renovate's "explicit chart field" custom manager track the
   chart version (regex requires `chart:` → `version:` → `repository:` line
   order — keep that order).
3. **`fullnameOverride: grow-erp-next`.** Makes the nginx Service
   `grow-erp-next` (repo convention `service: <category>-<appName>`), keeps
   all names ≤63 chars, and keeps the chart's internal name references
   consistent (verified by render).
4. **Site name = public host `erp.spencerslab.com`.** Frappe routes by Host
   header; the host is preserved across hub ExternalName → grow traefik →
   chart nginx (`FRAPPE_SITE_NAME_HEADER: $host`), so one name works end to
   end. Grow ingress key is therefore `erp` (host `erp.<domain>` must equal
   the site name), backend `grow-erp-next:8080`.
5. **RWO sites volume on local-path** (guide Option A; single-node cluster,
   chart README blesses RWO there). `persistence.logs.enabled: false`
   (emptyDir logs — avoids a second PVC).
6. **Secrets via ExternalSecret + Bitwarden (repo standard).** Two login
   items → two ExternalSecrets in `services/grow/prod/templates/`
   (umbrella-level, reads top-level `.Values.bitwardenIds` like gpu's
   open-webui template): target `grow-erp-next` (key
   `mariadb-root-password`, consumed by mariadb-sts + create-site) and
   target `grow-erp-next-admin` (key `password`, consumed via
   `adminExistingSecret`). `mariadb-sts.rootPassword: ""` suppresses the
   chart's own plaintext Secret (verified).
7. **Jobs: static names, plain resources, no hooks.** `configure.jobName`
   and `createSite.jobName` set (both default to `{{ now }}` timestamps →
   ArgoCD drift). create-site stays `enabled: true` — re-applying a
   completed, unchanged Job is a no-op and the script tolerates "site
   already exists". `migrate` stays disabled (no annotations passthrough in
   the template, so it can't be a PostSync hook; upgrade runbook below).
   `backup` out of scope (the chart Job is one-shot, not scheduled).
8. **Proxy auth: default hub chain (crowdsec + Keycloak forward-auth)** —
   user's choice (`pictaria` pattern). Known trade-off: Frappe API/mobile
   token clients will hit the OIDC redirect; revisit by switching to the
   crowdsec-only `paste` pattern if API access is needed later.
9. **No proxy-remote changes.** Lab services tunnel through automatically;
   proxy-remote entries are only for remote-cluster-hosted services.
10. **Chart security defaults kept** (`CAP_CHOWN`, root fixVolume
    initContainer) — required by the upstream image; documented deviation
    from the repo drop-ALL standard since this is an external chart.

## Changes

Ordered; each step names one file.

1. `services/grow/prod/values.yaml` — [MODIFY]
   - Top-level `bitwardenIds:` — add two sentinels:
     ```yaml
     bitwardenIds:
       home-assistant-pg: OVERRIDE_VIA_CLUSTER_ANNOTATION
       erp-next: OVERRIDE_VIA_CUSTOM_VALUES
       erp-next-admin: OVERRIDE_VIA_CUSTOM_VALUES
     ```
   - `charts:` — add under the "External charts" comment, after
     `cloudnative-pg` (KEEP LINE ORDER chart → version → repository for
     Renovate's regex):
     ```yaml
       erp-next:
         chart: erpnext
         version: 8.0.79
         repository: https://helm.erpnext.com
         namespace: default
         ServerSideApply: "true"
     ```
   - `ingress.subdomains:` — add:
     ```yaml
         erp:
           service: grow-erp-next
           port: 8080
     ```
   - Append the app values block at the end of the file (this whole block
     rides the appset values slice into the Application):
     ```yaml
     # ERPNext v16 via the official frappe/erpnext external chart.
     # Site name MUST equal the public host (Frappe routes by Host header).
     # DB root + admin passwords come from ExternalSecrets (see
     # templates/secret-erp-next.yaml); mariadb-sts.rootPassword is emptied
     # so the chart does NOT render its own plaintext Secret.
     erp-next:
       fullnameOverride: grow-erp-next
       image:
         repository: frappe/erpnext
         tag: v16.34.2
         pullPolicy: IfNotPresent
       persistence:
         worker:
           enabled: true
           storageClass: local-path
           accessModes:
             - ReadWriteOnce
           size: 8Gi
         logs:
           enabled: false
       mariadb-sts:
         enabled: true
         rootPassword: ""
         persistence:
           storageClass: local-path
           size: 8Gi
         resources:
           requests:
             cpu: 100m
             memory: 512Mi
           limits:
             memory: 2Gi
       valkey-cache:
         enabled: true
         resources:
           requests:
             cpu: 10m
             memory: 50Mi
           limits:
             memory: 256Mi
       valkey-queue:
         enabled: true
         resources:
           requests:
             cpu: 10m
             memory: 50Mi
           limits:
             memory: 256Mi
       nginx:
         resources:
           requests:
             cpu: 10m
             memory: 32Mi
           limits:
             memory: 256Mi
       socketio:
         resources:
           requests:
             cpu: 20m
             memory: 100Mi
           limits:
             memory: 512Mi
       worker:
         gunicorn:
           resources:
             requests:
               cpu: 100m
               memory: 400Mi
             limits:
               memory: 1Gi
         default:
           resources:
             requests:
               cpu: 40m
               memory: 200Mi
             limits:
               memory: 1Gi
         short:
           resources:
             requests:
               cpu: 40m
               memory: 200Mi
             limits:
               memory: 1Gi
         long:
           resources:
             requests:
               cpu: 40m
               memory: 200Mi
             limits:
               memory: 1Gi
         scheduler:
           resources:
             requests:
               cpu: 20m
               memory: 100Mi
             limits:
               memory: 512Mi
       jobs:
         configure:
           enabled: true
           # Static name — chart default uses {{ now }} (ArgoCD drift).
           jobName: grow-erp-next-conf-bench
         createSite:
           enabled: true
           # Static name — chart default uses {{ now }} (ArgoCD drift).
           jobName: grow-erp-next-create-site
           siteName: erp.spencerslab.com
           adminExistingSecret: grow-erp-next-admin
           adminExistingSecretKey: password
           dbType: mariadb
           installApps:
             - erpnext
     ```
2. `services/grow/prod/templates/secret-erp-next.yaml` — [CREATE]
   ```yaml
   # ERPNext secrets from Bitwarden (umbrella-level template: reads the
   # TOP-LEVEL .Values.bitwardenIds; sentinels in values.yaml, UUIDs in
   # custom-values/grow/prod-values.yaml).
   # Target name `grow-erp-next` is the exact Secret name the frappe chart's
   # mariadb StatefulSet and create-site Job read (key mariadb-root-password)
   # when mariadb-sts is enabled — the chart's own Secret is suppressed via
   # mariadb-sts.rootPassword: "".
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: erp-next-secrets
   spec:
     refreshInterval: 1h
     target:
       name: grow-erp-next
       creationPolicy: Owner
     data:
       - secretKey: mariadb-root-password
         sourceRef:
           storeRef:
             name: bitwarden-login
             kind: SecretStore
         remoteRef:
           key: '{{ index .Values "bitwardenIds" "erp-next" }}'
           property: password
           # Boiler plate needed for ArgoCD to not complain about a mismatch.
           conversionStrategy: Default
           decodingStrategy: None
           metadataPolicy: None
   ---
   # Administrator password for bench new-site (jobs.createSite.adminExistingSecret).
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: erp-next-admin-secret
   spec:
     refreshInterval: 1h
     target:
       name: grow-erp-next-admin
       creationPolicy: Owner
     data:
       - secretKey: password
         sourceRef:
           storeRef:
             name: bitwarden-login
             kind: SecretStore
         remoteRef:
           key: '{{ index .Values "bitwardenIds" "erp-next-admin" }}'
           property: password
           # Boiler plate needed for ArgoCD to not complain about a mismatch.
           conversionStrategy: Default
           decodingStrategy: None
           metadataPolicy: None
   ```
3. `services/proxy-local/prod/values.yaml` — [MODIFY] add under
   `proxy.subdomains`, next to `pictaria` (own-auth section):
   ```yaml
       # ERPNext own auth (Frappe Administrator/users) + hub Keycloak
       # forward-auth (default userAuth). Note: forward-auth blocks Frappe
       # API token clients — switch to the crowdsec-only `paste` pattern if
       # API/mobile access is needed.
       erp:
         target: erp
   ```
4. `custom-values/grow/prod-values.yaml` — [MODIFY] add the real UUIDs under
   the existing top-level `bitwardenIds:` (values provided by the user — see
   Risks):
   ```yaml
   bitwardenIds:
     cert-manager-solver-token: 0f8504eb-1339-4a32-861b-af440002801e
     argocd-sso-secret: 6bc8ead2-faf6-4548-9831-b1a501646625
     erp-next: <UUID of Bitwarden login item "erp-next">
     erp-next-admin: <UUID of Bitwarden login item "erp-next-admin">
   ```

User prerequisites (outside this repo — do before/with the merge):

- Create two Bitwarden LOGIN items: `erp-next` (username `root`, password =
  new strong MariaDB root password) and `erp-next-admin` (username
  `Administrator`, password = ERPNext admin password); put their UUIDs into
  step 4.
- Add split-horizon/internal DNS record `erp-next.spencerslab.com` → `10.0.3.5`
  (grow's traefik) in the lab DNS, same mechanism used for
  `budget/documents.<domain>` — without it the hub ExternalName cannot
  resolve to grow. (Updated in tweak round 2: record follows the ExternalName
  target `erp-next`, not the public name `erp`.)

## Verification

Pre-merge (Code agent):

1. Extract the `erp-next:` block to a temp file and render against the
   pulled chart to prove the values slice works end-to-end:
   ```bash
   helm repo add frappe https://helm.erpnext.com
   helm pull frappe/erpnext --version 8.0.79 --untar   # creates ./erpnext/
   python3 -c "import yaml;d=yaml.safe_load(open('services/grow/prod/values.yaml'));yaml.safe_dump(d['erp-next'],open('/tmp/erp-next-values.yaml','w'))"
   helm template grow-erp-next ./erpnext -f /tmp/erp-next-values.yaml -n default > /tmp/rendered.yaml
   ```
   Expect: exit 0; `Service grow-erp-next` port 8080; PVC `grow-erp-next`
   RWO/local-path; Jobs `grow-erp-next-conf-bench` /
   `grow-erp-next-create-site`; NO `kind: Secret` from the chart; ADMIN_PASSWORD
   from `grow-erp-next-admin`; DB_ROOT_PASSWORD from Secret `grow-erp-next`.
2. Trio grep:
   ```bash
   grep -n "erp-next" services/grow/prod/values.yaml        # charts entry + erp: ingress + values block
   grep -n "erp:" services/proxy-local/prod/values.yaml     # proxy entry
   grep -n "erp-next" custom-values/grow/prod-values.yaml   # UUIDs present
   grep -rn "OVERRIDE_" services/grow/prod/templates/secret-erp-next.yaml  # none — template reads resolved values
   ```
3. Validate the grow umbrella renders (sentinels resolve only with
   custom-values, so render with dummy UUIDs):
   ```bash
   helm template services/grow/prod --set domain=spencerslab.com --set clusterName=grow \
     --set bitwardenIds.erp-next=test-uuid --set bitwardenIds.erp-next-admin=test-uuid \
     --show-only templates/secret-erp-next.yaml
   ```
   Expect: both ExternalSecrets with `key: test-uuid` (no sentinels left).

Post-merge (after user merges to main; ArgoCD syncs automatically):

4. `readonly-gpu-kubernetes`: Application `grow-erp-next` exists under
   `grow-charts-appset` and is Synced/Healthy.
5. `readonly-grow-kubernetes`:
   - Pods Running: `grow-erp-next-{nginx,gunicorn,socketio,scheduler,worker-d,worker-s,worker-l}`,
     `grow-erp-next-mariadb-sts-0`, `grow-erp-next-valkey-{cache,queue}`.
   - Jobs Complete: `grow-erp-next-conf-bench`, `grow-erp-next-create-site`
     (logs: "Site ... created" or "already exists").
   - PVC `grow-erp-next` Bound; Secret `grow-erp-next` exists (ExternalSecret Ready).
   - Ingress `erp-ingress` host `erp.spencerslab.com`.
6. `readonly-proxy-local-kubernetes`: `erp-service` ExternalName +
   `erp-ingress` exist.
7. End-to-end: browse `https://erp.spencerslab.com` → Keycloak login →
   ERPNext login screen → log in as `Administrator` with the Bitwarden
   password. (Requires the DNS record from prerequisites.)
8. Renovate: confirm the dependency dashboard picks up `erpnext` (chart,
   via the `chart:` field regex) and `frappe/erpnext` (image tag). If the
   image isn't tracked, add an inline renovate comment per repo convention.

## Risks & open questions

- **Node headroom is tight.** grow: 2 CPU / ~12.4Gi allocatable with ~2.1Gi
  free and 2 cores shared. This plan adds ~9 pods with ~1.2Gi requests /
  ~5Gi limits. Watch for Pending pods (requests) or OOM kills (limits) after
  sync; first levers are dropping `worker.long` resources or trimming
  gunicorn/mariadb limits. Do NOT add replicas.
- **RWO multi-attach on rolling updates** (known single-node gotcha): a new
  pod can wait for the old one to release the sites PVC. Replicas are 1 and
  everything is co-located, so this is transient — delete the stuck pod if
  it happens.
- **Failed create-site Job recovery:** Jobs are immutable; if
  `grow-erp-next-create-site` fails, delete it (admin MCP, with user OK) and
  let ArgoCD re-apply.
- **Bitwarden UUIDs are a hard gate.** Until step 4 lands, the ExternalSecrets
  stay NotReady and mariadb pods sit in CreateContainerConfigError —
  everything else renders fine; pods recover automatically once UUIDs exist.
- **Split-horizon DNS record missing → hub 404/502** even when the cluster
  is healthy. Verify `erp.spencerslab.com` resolves to 10.0.3.5 from inside
  the lab before browser testing.
- **Keycloak forward-auth blocks Frappe API/token clients** (accepted by the
  user). Escape hatch: crowdsec-only `middlewares:` override à la `paste`.
- **Upgrade runbook (future):** Renovate bumps the chart dependency
  (`charts/erp-next/Chart.yaml`) and the image tag
  (`charts/erp-next/values.yaml` — `erpnext.image.tag` AND the two
  `jobs.custom` image strings marked "keep in sync") independently. Before
  ANY such bump syncs, delete the completed Jobs `grow-erp-next-conf-bench`
  and `grow-erp-next-create-site` (admin action) — Job `spec.template` is
  immutable, so ArgoCD apply fails with "field is immutable" until they are
  gone. After ANY image tag bump, enable `jobs.migrate: {enabled: true,
  jobName: grow-erp-next-migrate, siteName: erp.spencerslab.com}` for one
  sync, then disable it (the migrate template has no annotations
  passthrough, so it cannot be a permanent PostSync hook).
- **Chart security posture:** upstream chart adds CAP_CHOWN and runs a root
  fixVolume init container — kept as-is (external chart requirement),
  deviating from the repo drop-ALL standard by design.

## Implementation addendum (2026-09-12, code agent)

Two deviations from the plan above, both caught/confirmed at implementation:

1. **`dbRootUser: root` added to the `erp-next:` values block.** Pre-merge
   render verification showed `DB_ROOT_USER: ""` in the create-site Job: with
   `mariadb-sts` enabled the chart falls through to the plain `.Values.dbRootUser`
   value (the "root" literal only applies to the bitnami mariadb subchart),
   which the plan's values block did not set — `bench new-site
   --mariadb-root-username=` would have failed. The built-in mariadb-sts
   always creates user `root`, so `root` is the correct fixed value.
2. **Usernames are pulled from Bitwarden too** (user requirement): both
   ExternalSecrets now also fetch `property: username` — Secret
   `grow-erp-next` gains key `mariadb-root-username`, Secret
   `grow-erp-next-admin` gains key `username`. The chart only consumes the
   password keys; the username keys make the Secrets complete and auditable.

UUIDs landed in `custom-values/grow/prod-values.yaml` as provided by the user:
`erp-next: 880ce9a1-ce6b-42f4-bbf0-b4c300308383`,
`erp-next-admin: f7b628ec-2544-4c28-a476-b1a501487d99`.

All pre-merge verifications passed, including the extra appset-level render
(`charts/base` appset-charts element for `erp-next` carries
`chart: erpnext`/`version: 8.0.79`/`repository` + the exact values slice) and
the proxy-local render (`erp-service` ExternalName → `erp.spencerslab.com`,
public `erp-ingress` with crowdsec+Keycloak forward-auth, LAN IngressRoute).

### Tweak round 2 (user-requested renames + routing)

1. **Bitwarden-ids keys renamed:** admin item key `erp-next-admin` →
   `erp-next`; DB item key `erp-next` → `erp-next-db` (sentinels in
   `services/grow/prod/values.yaml`, remoteRefs in
   `templates/secret-erp-next.yaml`, UUIDs in
   `custom-values/grow/prod-values.yaml`). The DB ExternalSecret resource was
   also renamed `erp-next-secrets` → `erp-next-db-secret` for consistency.
   Target Secret names (`grow-erp-next`, `grow-erp-next-admin`) are chart
   contract and unchanged.
2. **Routing renamed:** grow ingress subdomain key `erp` → `erp-next` with
   `serviceName: erp` (documents/paperless pattern) so grow serves BOTH
   `erp-next.spencerslab.com` and `erp.spencerslab.com` — required because
   the hub preserves the Host header when forwarding (verified against every
   live key≠target example: player→jellyfin, documents→paperless, etc. all
   serve both hosts on the owning cluster).
3. **proxy-local:** `erp: {target: erp-next}` — public URL stays
   `erp.spencerslab.com`, ExternalName now `erp-next.spencerslab.com`.
   Consequently the split-horizon DNS prerequisite changes: the lab DNS record
   must be **`erp-next.spencerslab.com` → 10.0.3.5** (the ExternalName target).

### Restructure round 3 (code review findings + user direction)

The `/review` of the uncommitted wiring found one CRITICAL and several
deploy-safety issues; the user additionally directed a structural change.
Everything above about external-chart wiring in `services/grow/prod` is
SUPERSEDED by this round:

1. **Wrapper chart `charts/erp-next/`** instead of a direct external-chart
   entry. `Chart.yaml` depends on `erpnext 8.0.79` from
   `https://helm.erpnext.com`; the grow service now carries an INTERNAL
   `charts.erp-next` entry (commented version/repository, git-path source).
   All app config moved to `charts/erp-next/values.yaml` under the
   `erpnext:` dependency key. Bitwarden sentinels moved into the chart
   values; the real UUIDs moved from top-level `bitwardenIds:` in
   `custom-values/grow/prod-values.yaml` to an app-scoped `erp-next:` block
   (assistant pattern — merged into the app values slice, overrides the
   chart sentinels).
2. **Secrets split, one file per secret**, now chart templates:
   `charts/erp-next/templates/secret-erp-next.yaml` (Administrator creds,
   item `erp-next` → target `grow-erp-next-admin`) and
   `secret-erp-next-db.yaml` (MariaDB root creds, item `erp-next-db` →
   target `grow-erp-next`). The umbrella template
   `services/grow/prod/templates/secret-erp-next.yaml` was deleted.
3. **CRITICAL review fix — password leak:** the chart's `jobs.createSite`
   script runs `set -x` before `bench new-site`, xtracing the admin + DB
   root passwords into pod logs. Site creation now runs via
   `jobs.custom` (`grow-erp-next-create-site`) with the same init/wait
   logic and "already exists" tolerance but NO xtrace; `DB_ROOT_USER` is
   read from Secret `grow-erp-next` key `mariadb-root-username` (the
   username synced from Bitwarden) instead of the plain `dbRootUser`
   value (kept for chart jobs like migrate).
4. **WARNING review fix — retries:** `jobs.configure.backoffLimit: 5` and
   `jobs.custom.backoffLimit: 5` (chart default 0 = one-shot; ArgoCD never
   re-runs a Failed Job whose manifest matches).
5. **PVC:** owned by the wrapper chart
   (`charts/erp-next/templates/pvc-erp-next.yaml`), named
   `{{ .Release.Name }}-erp-next` (= `grow-erp-next-erp-next`) and
   annotated `argocd.argoproj.io/resource-policy: keep` (data-loss review
   finding — local-path reclaimPolicy Delete would otherwise destroy the
   site if the Application were pruned). The subchart consumes it via
   `erpnext.persistence.worker.existingClaim` (must stay in sync with the
   rendered name).
6. **Job-immutability runbook:** upgrade runbook above updated — delete
   both completed Jobs before any image/chart bump.
7. **Skill update:** `skills/helm-chart-creation` now codifies the
   preference for including a chart in the service (wrapper chart for
   external charts that need repo templates/secrets/PVCs) over configuring
   an external chart directly in the service values.

Validation performed: `helm lint charts/erp-next` clean; chart render with
resolved slice (base-appset element values) shows no sentinels, both
ExternalSecrets on the real UUIDs, PVC with keep annotation, both Jobs
backoffLimit 5, no chart Secret, no `set -x`; both job scripts pass
`bash -n`; grow umbrella renders the two erp ingresses unchanged.

### Round 4 — database moved to mariadb-operator (main merged 2026-09-14)

`origin/main` brought `charts/mariadb-operator` (community operator 26.6.0,
CRDs in-release) plus the skill pattern "MariaDB instance
(templates/mariadb-<service>.yaml)". The built-in `mariadb-sts` StatefulSet
is replaced by an operator-managed instance:

1. **New `charts/erp-next/templates/mariadb-erp-next.yaml`** — `MariaDB` CR
   (`k8s.mariadb.com/v1alpha1`): image pinned `mariadb:10.6.28` (10.6 LTS =
   the series the frappe chart ships for ERPNext v16; operator best practice
   is a pinned patch tag), replicas 1, port 3306, 8Gi local-path (cannot
   expand — sized up front), resources as before (100m/512Mi req, 2Gi lim),
   drop-ALL securityContext, metrics enabled, `rootPasswordSecretKeyRef` →
   Secret `grow-erp-next` key `mariadb-root-password` (the existing
   ExternalSecret; no new Bitwarden items needed).
2. **Deviation from the full operator pattern:** no Database/User/Grant/
   Connection CRs — `bench new-site` bootstraps the site database and user
   itself via root credentials (same flow the chart's mariadb-sts used).
   Documented in the template comment.
3. **`charts/erp-next/values.yaml`:** `erpnext.mariadb-sts.enabled: false`;
   external-DB coordinates `erpnext.dbHost: mariadb-erp-next` (the
   operator's Service, named after the CR) + `dbPort: 3306` — the chart's
   configure Job picks these up automatically; `jobs.custom` init/container
   DB_HOST env updated to match. With mariadb-sts off and dbRootPassword
   unset the chart renders no Secret at all (gate verified in
   `templates/secret.yaml`).
4. Migrate job needs only SITE_NAME (no DB creds) — upgrade runbook
   unaffected.

Validation: render shows MariaDB CR + no StatefulSet + no Secret; configure
and create-site Jobs both point at `mariadb-erp-next:3306`; scripts pass
`bash -n`; lint clean; umbrella renders. Deploy order at sync time needs no
waves: create-site init retries (backoffLimit 5) cover operator provisioning
latency.

### Round 5 — drop the `grow-` prefix from object names (user direction)

Service-prefixed names made the chart grow-specific. All rendered objects
are now bare/generic:

- `erpnext.fullnameOverride: erp-next` (was `grow-erp-next`) — nginx
  Service `erp-next`, Deployments `erp-next-{gunicorn,socketio,scheduler,
  nginx,worker-d,worker-s,worker-l}`, ServiceAccount, test Pod.
- Valkey subcharts render `<release>-<alias>` by default — pinned
  `fullnameOverride: erp-next-valkey-cache` / `erp-next-valkey-queue`
  (covers their Deployments, Services, ServiceAccounts, init ConfigMaps).
- Jobs: `erp-next-conf-bench`, `erp-next-create-site`.
- ExternalSecret targets: `erp-next-db` (was grow-erp-next) and
  `erp-next-admin` (was grow-erp-next-admin); MariaDB CR
  rootPasswordSecretKeyRef and jobs.custom env secretKeyRefs follow.
- Sites PVC: renamed from `{{ .Release.Name }}-erp-next` to bare `erp-next`
  (qdrant precedent: PVC named after the app) — the release-derived name
  rendered `grow-erp-next-erp-next` and forced a hardcoded `grow-` coupling
  in `existingClaim`; the wrapper keeps ownership + resource-policy keep.
- Grow ingress backend: `service: erp-next`.

Validation: render shows 26 resources, zero `grow-` names, zero `grow-`
strings in chart sources, no sentinels; both grow ingresses backend
`erp-next:8080`; lint clean.
