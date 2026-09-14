# Plan: Add mariadb-operator to the grow cluster + MariaDB/MySQL context docs

## Goal

Deploy the community mariadb-operator (26.6.0, `github.com/mariadb-operator/mariadb-operator`
— MIT-licensed, NOT the enterprise operator) on the grow cluster as its own
wrapper chart `charts/mariadb-operator/`, wired through the grow ApplicationSet
as a single ArgoCD Application (operator + CRDs in one release). Then update
the agent context docs (helm-chart-creation skill) so any future MariaDB/MySQL
database is implemented via this operator's CRDs instead of sidecar containers.
No MariaDB instances are created in this change — the docs define how to add
them later.

## Skills

- `helm-chart-creation` — chart creation, service wiring (`charts:` entry),
  validation levels, sentinel rules.
- `gitops-workflows` — ArgoCD Application/sync behavior context.

## MCP Servers

- `readonly-grow-kubernetes` — optional post-merge verification (Application
  Synced/Healthy, operator pods Running, CRDs present). No `admin-*` servers
  needed: ArgoCD applies everything.

## Verified context

Recon performed 2026-09-14 against this worktree and the live grow cluster:

- **Version**: 26.6.0 is the latest community release. ghcr.io OCI registry
  lists only `26.3.0` and `26.6.0` (checked via registry tags API) — the
  hand-off guide's "26.6.1 not yet published" caveat holds; nothing newer.
- **Charts**: `oci://ghcr.io/mariadb-operator/charts/mariadb-operator:26.6.0`
  and `.../mariadb-operator-crds:26.6.0` both pull successfully. The operator
  chart VENDORS the CRDs subchart, gated by `crds.enabled` (default `false`).
  Chart warning: with `crds.enabled: true`, uninstalling the release deletes
  the CRDs and cascade-deletes ALL MariaDB instances (CRDs have no
  `preserveOnDelete`; 12 CRDs, 788 KiB raw, largest single CRD 379 KiB).
- **Render prototype** (built in /tmp): wrapper chart with OCI dependency
  resolves (`helm dependency update`), `helm lint` passes, `helm template`
  renders 38 resources: 12 CRDs, 3 Deployments (controller, webhook,
  cert-controller, all `ghcr.io/mariadb-operator/mariadb-operator:26.6.0`),
  3 ServiceMonitors, ValidatingWebhookConfiguration, RBAC, Services.
- **grow cluster**: single-node k3s (node `grow`), ArgoCD v3.4.5 (OCI-capable),
  only storage class is `local-path` (default, `AllowVolumeExpansion: false`),
  cert-manager v1.19.3 present, prometheus-operator CRDs present and consumed
  (CNPG PodMonitors live), external-secrets + Bitwarden live. Everything runs
  in namespace `default`.
- **Repo precedents**: wrapper charts `charts/k8s-monitoring/`,
  `charts/seaweedfs-csi-driver/`, `charts/keycloakx/` (Chart.yaml + Chart.lock
  + values.yaml, no templates; vendored `charts/` gitignored via
  `charts/**/charts`; ArgoCD resolves deps from git-path source). Renovate
  bumps wrapper deps AND maintains Chart.lock (commit c26f6083 proves it).
  Operator-as-chart-entry precedent: `cloudnative-pg` in
  `services/grow/prod/values.yaml`. Internal-chart entries use commented
  `#version:`/`#repository:` lines (git-path source from `main`).
- **CNPG DB pattern** (model for docs): `charts/home-assistant/templates/pg-home-assistant.yaml`
  + `secret-pg-home-assistant.yaml` (ExternalSecret from `bitwarden-login`).
- **CRD API fields verified against the rendered 26.6.0 CRDs**: MariaDB
  (`rootPasswordSecretKeyRef{name,key}`, `image`, `replicas`,
  `storage{size,storageClassName}`, `metrics{enabled,serviceMonitor}`,
  `connection`, `bootstrapFrom`, `tls`, `suspend`), Database
  (`mariaDbRef` required, `name`), User (`mariaDbRef` required,
  `passwordSecretKeyRef`, `maxUserConnections`), Grant (`mariaDbRef`,
  `privileges`, `username` required, `database`, `table`), Connection
  (`username` required, `mariaDbRef`, `secretName`, `secretTemplate`,
  `passwordSecretKeyRef`), PhysicalBackup (`mariaDbRef`, `storage` required,
  `schedule`, `compression`, `maxRetention`).
- **Existing MariaDB usage**: only `charts/playsms` (MariaDB as a sidecar
  container — legacy pattern, stays grandfathered).

## Design decisions

1. **Wrapper chart `charts/mariadb-operator/`** (user asked for "its own
   chart"). Official upstream chart exists, so the wrapper has no templates —
   same shape as `charts/k8s-monitoring/`. Gives a future home for
   operator-related templates and deploys via git-path source from `main`.
2. **Single release, `crds.enabled: true`** (user chose the repo pattern over
   a separate CRDs Application). Consistent with CNPG/cert-manager/
   external-secrets in this repo. Within one ArgoCD Application, CRDs are
   sorted before Deployments on every sync, so install/upgrade ordering is
   deterministic. Documented trade-off: pruning the `grow-mariadb-operator`
   Application deletes the CRDs and cascade-deletes every MariaDB instance —
   never remove the entry while instances exist (warning lives in values.yaml
   and the docs).
3. **Namespace `default`** — repo convention; every grow workload (argocd,
   cert-manager, CNPG, external-secrets) is in `default`. The guide's
   `mariadb-system` is deliberately not used.
4. **Webhook certs via built-in cert-controller** (chart default, guide
   recommendation). cert-manager exists on grow but integration stays off
   (`webhook.cert.certManager.enabled: false`) — fewer moving parts.
5. **Metrics + ServiceMonitors enabled** — grow runs the k8s-monitoring stack
   and consumes prometheus-operator CRDs (CNPG PodMonitors are live).
6. **All operator config in the wrapper's values.yaml**, nested under the
   `mariadb-operator:` subchart key (k8s-monitoring precedent). No top-level
   config block needed in the grow service values.
7. **Standalone-only guidance for instances**: grow is single-node with
   `local-path` (no volume expansion) → `replicas: 1`, no Galera/replication,
   no PITR (needs replication topology + MariaDB >= 10.8), size PVCs up front,
   backups later via `PhysicalBackup` to S3/MinIO (no MinIO on grow today).
8. **Renovate**: the built-in helm manager tracks the OCI dependency in
   `charts/mariadb-operator/Chart.yaml` and maintains Chart.lock (proven by
   k8s-monitoring). One dependency line = CRDs and operator always bump
   together (they ship in the same chart version), so no grouping rule needed.
   Upgrade discipline from the guide (never skip intermediate versions) is
   satisfied by one-version-per-PR renovate bumps.
9. **Rollout to other clusters later**: the chart lives in `charts/`, so any
   other category needs only the same `charts:` entry in its values.yaml.
   Not part of this change.

## Changes

### 1. `charts/mariadb-operator/Chart.yaml` — [CREATE]

```yaml
apiVersion: v2
name: mariadb-operator
description: MariaDB operator (community) - run and operate MariaDB in a cloud native way
type: application
version: 1.0.0
appVersion: "26.6.0"
dependencies:
  - name: mariadb-operator
    version: 26.6.0
    repository: oci://ghcr.io/mariadb-operator/charts
    # sourceUrl: https://github.com/mariadb-operator/mariadb-operator
```

(`version: 1.0.0` — initial; `release.yaml` auto-bumps on merge. The
`# sourceUrl:` comment feeds the repo's renovate changelog-override custom
manager.)

### 2. `charts/mariadb-operator/values.yaml` — [CREATE]

Render-verified content (lint + template pass; no sentinels):

```yaml
# Wrapper values for the upstream mariadb-operator chart (community).
# All config is nested under the `mariadb-operator:` subchart key.
mariadb-operator:
  # CRDs are managed by THIS release (initial-deployment mode).
  # WARNING: uninstalling/pruning this release deletes the 12
  # k8s.mariadb.com CRDs, which cascade-deletes EVERY MariaDB instance in the
  # cluster (no preserveOnDelete). Never remove the mariadb-operator
  # Application while MariaDB instances exist.
  crds:
    enabled: true

  image:
    repository: ghcr.io/mariadb-operator/mariadb-operator
    pullPolicy: IfNotPresent
    # tag defaults to Chart appVersion (26.6.0)

  # Operator controller metrics + ServiceMonitors (grow scrapes
  # prometheus-operator objects via the k8s-monitoring stack).
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true

  resources:
    requests:
      cpu: 10m
      memory: 64Mi
    limits:
      memory: 256Mi

  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL

  webhook:
    # Built-in cert-controller issues/rotates the webhook serving cert.
    # cert-manager integration stays off even though cert-manager exists.
    cert:
      certManager:
        enabled: false
    resources:
      requests:
        cpu: 10m
        memory: 64Mi
      limits:
        memory: 256Mi
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL

  certController:
    resources:
      requests:
        cpu: 10m
        memory: 64Mi
      limits:
        memory: 256Mi
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
```

### 3. `charts/mariadb-operator/Chart.lock` — [GENERATE]

Run `helm dependency update charts/mariadb-operator`. Commit the generated
`Chart.lock` only — the vendored tarball under `charts/mariadb-operator/charts/`
is gitignored (`charts/**/charts`) and must NOT be staged (verify with
`git status --ignored` / `git check-ignore`).

### 4. `services/grow/prod/values.yaml` — [MODIFY]

Add one entry to the `charts:` map, after `external-secrets-bitwarden` and
before the `# External charts` comment (internal-chart convention — git-path
source from `main`, commented published-chart lines like `assistant`/
`k8s-monitoring`):

```yaml
  mariadb-operator:
    #version: 1.0.0 # renovate: datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/
    #repository: https://ownyourio.github.io/SpencersLab/
    namespace: default
    ServerSideApply: "true"
```

No top-level `mariadb-operator:` config block is needed (config lives in the
wrapper chart). No proxy/ingress entry (operator has no web UI). No
custom-values entry (no Bitwarden secrets in the operator itself).

### 5. `skills/helm-chart-creation/SKILL.md` — [MODIFY]

In "Known gotchas (CRITICAL)", directly after the CloudNativePG bullet, add:

```markdown
- MariaDB/MySQL instances use the **mariadb-operator**
  (`k8s.mariadb.com/v1alpha1 MariaDB`) — operator wrapper chart
  `charts/mariadb-operator` (deployed on grow). Standalone single-instance
  only on single-node clusters; never sidecar a MariaDB container for new
  services. Templates in `references/chart-templates.md`.
```

### 6. `skills/helm-chart-creation/references/chart-templates.md` — [MODIFY]

a) After the "### PostgreSQL cluster" section, add:

````markdown
### MariaDB instance — `templates/mariadb-<service>.yaml` (mariadb-operator)

Use for ANY new MariaDB/MySQL database. Requires the mariadb-operator chart
(`charts/mariadb-operator`, currently deployed on grow — add the same `charts:`
entry to another category's values.yaml to deploy it elsewhere). Never run
MariaDB as a sidecar container in new charts (legacy example: playsms).

Credentials come from Bitwarden via two `bitwarden-login` items:
`<service>-mariadb-root` (root password) and `<service>-mariadb` (app user
username/password). Add `OVERRIDE_VIA_CUSTOM_VALUES` sentinels for both in the
service values.yaml and real UUIDs in `custom-values/<category>/prod-values.yaml`.

```yaml
# templates/secret-mariadb-<service>.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mariadb-<service>-root
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: mariadb-<service>-root
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: {{ index .Values "bitwardenIds" "<service>-mariadb-root" }}
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mariadb-<service>-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: mariadb-<service>-app
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: {{ index .Values "bitwardenIds" "<service>-mariadb" }}
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

```yaml
# templates/mariadb-<service>.yaml
apiVersion: k8s.mariadb.com/v1alpha1
kind: MariaDB
metadata:
  name: mariadb-<service>
spec:
  rootPasswordSecretKeyRef:
    name: mariadb-<service>-root
    key: password
  image: mariadb:11.8.8        # pin an LTS patch tag (11.8 line); don't rely on operator defaults
  replicas: 1                  # standalone — single-node clusters can't run Galera/replication
  port: 3306
  storage:
    size: 10Gi                 # local-path CANNOT expand — size adequately up front
    storageClassName: local-path
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
  metrics:
    enabled: true              # mysqld-exporter sidecar + ServiceMonitor
---
apiVersion: k8s.mariadb.com/v1alpha1
kind: Database
metadata:
  name: <service>
spec:
  mariaDbRef:
    name: mariadb-<service>
  name: <service>
---
apiVersion: k8s.mariadb.com/v1alpha1
kind: User
metadata:
  name: <service>
spec:
  mariaDbRef:
    name: mariadb-<service>
  name: <service>
  passwordSecretKeyRef:
    name: mariadb-<service>-app
    key: password
  maxUserConnections: 20
---
apiVersion: k8s.mariadb.com/v1alpha1
kind: Grant
metadata:
  name: <service>
spec:
  mariaDbRef:
    name: mariadb-<service>
  privileges:
    - ALL PRIVILEGES
  database: <service>
  table: "*"
  username: <service>
---
# Connection secret the app mounts/reads (analogous to CNPG's connection handling)
apiVersion: k8s.mariadb.com/v1alpha1
kind: Connection
metadata:
  name: <service>
spec:
  mariaDbRef:
    name: mariadb-<service>
  username: <service>
  passwordSecretKeyRef:
    name: mariadb-<service>-app
    key: password
  database: <service>
  secretName: mariadb-<service>-conn
  healthCheck:
    interval: 30s
```

The app chart then consumes `mariadb-<service>-conn` (keys: `host`, `port`,
`username`, `password`, `database`, plus `url`-style keys via
`spec.secretTemplate` if the app wants a DSN) — construct `DATABASE_*` env
vars from it in the app's secret template, e.g.
`DATABASE_HOST: "{{ "{{ .host }}" }}"`.

Operational constraints (single-node k3s + local-path):

- Standalone only: Galera needs >= 3 nodes, async replication >= 2 pods;
  PITR needs the replication topology + MariaDB >= 10.8 — none apply.
- `local-path` has `allowVolumeExpansion: false` — grow the DB by restoring
  into a larger fresh instance, not by resizing the PVC.
- Backups: scheduled `PhysicalBackup` (mariadb-backup, preferred) or logical
  `Backup` to S3/MinIO with `compression` + `maxRetention`; restore via a
  `Restore` CR or `spec.bootstrapFrom`. No MinIO endpoint is wired on grow
  yet — add credentials/CA secrets first when backups are implemented.
- Operator lifecycle: the operator release owns the CRDs; deleting it
  cascade-deletes all instances. Upgrades: never skip intermediate operator
  versions (renovate bumps one version per PR — merge in order).
- Field reference: `apiVersion` for all CRDs is `k8s.mariadb.com/v1alpha1`;
  validate exact fields against the operator's API reference when
  implementing (docs linked in `.agents/plans/2026-09-14-feat-add-mariadb-operator-grow.md`).
````

b) In "## Integration points", extend the DATABASE block:

```yaml
DATABASE:
  - PostgreSQL: CloudNativePG operator — pg-<service>-rw for read-write access
  - MariaDB/MySQL: mariadb-operator (charts/mariadb-operator, grow) —
    MariaDB/Database/User/Grant/Connection CRDs (k8s.mariadb.com/v1alpha1),
    app reads the Connection secret mariadb-<service>-conn
```

c) In "## Worked examples in this repo", add:

```markdown
- External-chart wrapper (operator): `charts/mariadb-operator/` — Chart.yaml
  with one OCI dependency (upstream chart, CRDs via `crds.enabled: true`),
  config nested under the subchart key; wired via the `charts:` key in
  `services/grow/prod/values.yaml` (git-path source).
```

### 7. `skills/helm-chart-creation/references/values-and-appset.md` — [MODIFY]

In "## Integration points (summary)", replace the DATABASE block:

```yaml
DATABASE:
  - PostgreSQL: CloudNativePG operator; read-write endpoint pg-<service>-rw
  - MariaDB/MySQL: mariadb-operator (charts/mariadb-operator, grow);
    Connection secret mariadb-<service>-conn
```

### 8. `skills/helm-chart-creation/references/storage-and-secrets.md` — [MODIFY]

In "Common environment variables by application type" → "Database-backed
applications", prepend:

```markdown
- Postgres comes from CloudNativePG; MariaDB/MySQL comes from the
  mariadb-operator (`MariaDB` + `Database`/`User`/`Grant` + `Connection` CRs —
  see `chart-templates.md`). Never sidecar a database container in new charts.
```

## Verification

1. `helm lint charts/mariadb-operator` — passes.
2. `helm dependency update charts/mariadb-operator` — Chart.lock generated;
   `git status` shows only Chart.yaml/values.yaml/Chart.lock (vendored tarball
   ignored).
3. `helm template grow-mariadb-operator charts/mariadb-operator` — renders 38
   resources: 12 CRDs (`*.k8s.mariadb.com`), 3 Deployments
   (`grow-mariadb-operator`, `-webhook`, `-cert-controller`) with image
   `ghcr.io/mariadb-operator/mariadb-operator:26.6.0` and drop-ALL security
   contexts, 3 ServiceMonitors, 1 ValidatingWebhookConfiguration; no
   `OVERRIDE_*` sentinels in output.
4. `grep -n "mariadb-operator" services/grow/prod/values.yaml` — the `charts:`
   entry exists with `namespace: default` and `ServerSideApply: "true"`.
5. Docs grep: `grep -rn "mariadb-operator" skills/helm-chart-creation/` shows
   SKILL.md gotcha + chart-templates.md section + both integration-points
   blocks + storage-and-secrets.md note.
6. Post-merge (user merges to main; internal chart deploys from git `main`
   immediately — no chart publication needed): ArgoCD Application
   `grow-mariadb-operator` goes Synced/Healthy; pods `grow-mariadb-operator*`
   (3) Running in `default`; `kubectl get crd | grep k8s.mariadb.com` lists 12
   CRDs. Verify via `readonly-grow-kubernetes`.

## Risks & open questions

- **Cascade-delete hazard (accepted by user)**: the release owns the CRDs;
  pruning `grow-mariadb-operator` deletes every MariaDB instance. Mitigated by
  the values.yaml WARNING comment and the docs; same risk profile as the
  existing CNPG deployment.
- **Helm release size**: 820 KB rendered (788 KB CRDs) — gzipped well under
  Helm's 1 MB release limit (upstream slimmed the CRD bundle specifically for
  this); ServerSideApply avoids kubectl annotation limits regardless.
- **First-sync ordering**: within one Application ArgoCD applies CRDs before
  Deployments (same mechanism cert-manager/CNPG rely on) — no crashloop window.
- **Upgrade discipline**: never skip intermediate operator versions; renovate
  bumps one version per PR, and CRDs travel with the operator chart version so
  they can't drift apart.
- **Out of scope (documented for later)**: MariaDB instances, backups to
  MinIO/S3 (no MinIO on grow today), rollout of the operator to other
  clusters, playsms sidecar migration.
- **Renovate OCI tracking**: helm-manager support for `oci://` Chart.yaml deps
  with Chart.lock maintenance is the same mechanism k8s-monitoring uses for
  https repos; if the first renovate run doesn't pick up the OCI dep, fall
  back to manual bumps (low impact — operator upgrades are deliberate).
