# Plan: ILIAS on grow — redesigned onto mariadb-operator (+ review fixes)

## Goal

Supersedes `.agents/plans/2026-09-11-feat-add-ilias-to-grow.md` (sidecar
design). After that plan was implemented and reviewed, main gained
`charts/mariadb-operator` (commit `4fe41567`) whose skill docs make the
operator the canonical way to run MariaDB. This change:

1. Replaces the MariaDB sidecar in `charts/ilias` with operator CRDs
   (`MariaDB` + `Database` + `User` + `Grant` + `Connection`).
2. Applies all four findings of the 2026-09-13 local code review.

## Skills

`helm-chart-creation` (incl. the new "MariaDB instance" section in
`references/chart-templates.md`), `helm-bjw-s-chart`, `kubernetes-skill`,
`gitops-workflows`.

## MCP Servers

- `readonly-grow-kubernetes` — post-merge verification only.

## Changes implemented

### charts/ilias/values.yaml — rewritten

- **Sidecar removed**: no `mariadb` container, no `db` Service, no
  `mysql-data` persistence. DB env now arrives via `envFrom` on the
  operator-rendered Connection secret `mariadb-ilias-conn` (both ilias and
  cron containers) — no `ILIAS_DB_HOST` override anywhere.
- **bitwardenIds**: `ilias` (unchanged), `ilias-mariadb-root`,
  `ilias-mariadb` (operator pattern naming; sentinels).
- **publicSubdomain: OVERRIDE_VIA_APPSET** — injected by the grow appset
  entry's `values:` block (review fix #4: subdomain co-located with ingress
  wiring, no silent desync on rename).
- **startup probe** on the ilias container (httpGet :80, 10s × 60 ≈ 10 min)
  so first-boot `setup.php install` / later `ILIAS_AUTO_UPDATE` migrations
  aren't killed mid-flight by liveness (review fix #2).
- **Cron uses `args`, not `command`** (review fix #1): the image entrypoint
  must run first to regenerate `ilias.ini.php`/`client.ini.php` from env
  (it writes them to `/var/www/html`, container layer — not on any PVC);
  k8s `command` would replace the entrypoint and every cron run would die
  at bootstrap (`class.ilInitialisation.php` requires `ilias.ini.php`).
- **Cron podAffinity** to the ilias pod (review fix #3): `ilias-data` is
  RWO and shared by Deployment + CronJob pods; RWO is per-node, so without
  co-scheduling a future second node would Multi-Attach-fail and, with
  `concurrencyPolicy: Forbid`, wedge all later cron runs silently.

### charts/ilias/templates/

- `mariadb-ilias.yaml` — NEW: `MariaDB mariadb-ilias` (mariadb:11.8.8 pinned
  + renovate annotation, replicas 1, 10Gi local-path, metrics enabled,
  `myCnf` server-level utf8/utf8_general_ci), `Database ilias`
  (characterSet utf8 / collate utf8_general_ci — tables ILIAS creates
  inherit the DB default), `User ilias` (password from `mariadb-ilias-app`),
  `Grant ilias` (ALL PRIVILEGES on ilias.*), `Connection ilias`
  (secretName `mariadb-ilias-conn`, `secretTemplate` renames keys straight
  to `ILIAS_DB_HOST/PORT/USER/PASSWORD/NAME`, healthCheck 30s).
  Deliberate deviation from the skill-doc template: NO restrictive
  securityContext on the MariaDB CR — the official mariadb image entrypoint
  bootstraps as root (datadir chown) before gosu drops privileges;
  drop-ALL would break it (same rationale as playsms). The doc template's
  drop-ALL has not been runtime-verified against an instance.
- `secret-mariadb-ilias.yaml` — NEW: ExternalSecrets `mariadb-ilias-root`
  and `mariadb-ilias-app` (bitwarden-login, `password` property each),
  exactly the doc pattern.
- `secret-ilias.yaml` — slimmed to `ILIAS_ROOT_PASSWORD` +
  `ILIAS_HTTP_PATH` (DB keys removed; they come from the Connection secret).
- `secret-ilias-db.yaml`, `pvc-ilias-mysql.yaml` — DELETED (obsolete).
- `pvc-ilias-data.yaml` — unchanged (30Gi).

### services/grow/prod/values.yaml

- `charts.ilias` gains `values: {publicSubdomain: training}` (appset merges
  the entry's `values:` into chart values — verified in
  `charts/base/templates/appset-charts.yaml`).
- `ingress.subdomains.training` unchanged.
- (main merge also brought `mayan-edms` + `mariadb-operator` entries;
  conflict resolved keeping both.)

### services/proxy-local/prod/values.yaml

- `proxy.subdomains.training: target: ilias` unchanged (main merge brought
  `edms` alongside; conflict resolved keeping both).

### custom-values/grow/prod-values.yaml

```yaml
ilias:
  bitwardenIds:
    ilias: f7b628ec-2544-4c28-a476-b1a501487d99          # existing item
    ilias-mariadb: 14a6639d-eb30-48db-8554-b4c3002ef0d9   # existing "ilias-db" item (username ilias)
    ilias-mariadb-root: 14a6639d-eb30-48db-8554-b4c3002ef0d9  # SAME item reused for root (user decision)
```

User decision: reuse the `ilias-db` item's password for the MariaDB root
password instead of creating a dedicated root item. Swap
`ilias-mariadb-root` to a dedicated UUID later to split them.

## Verification performed

- `helm lint charts/ilias` — clean.
- `helm template grow-ilias charts/ilias --set domain=spencerslab.com
  --set publicSubdomain=training --set bitwardenIds.*=<real UUIDs>` —
  renders: Deployment (1 container, 2× envFrom, startup probe), CronJob
  (args not command, podAffinity, 2× envFrom), Service grow-ilias:80 only,
  PVC ilias-data only, 3 ExternalSecrets, MariaDB/Database/User/Grant/
  Connection CRs. Zero `OVERRIDE_*` sentinels.
- CRD field validation against the vendored 26.6.0 CRDs: Connection
  `secretTemplate{hostKey,portKey,usernameKey,passwordKey,databaseKey}`,
  Database `characterSet`/`collate`, MariaDB `myCnf`/`storage`/`metrics`,
  User/Grant fields — all exist as used.
- Trio grep: chart entry + grow ingress + proxy entry + custom-values all
  present.

## Post-merge verification (user merges; ArgoCD syncs)

1. `grow-mariadb-operator` Application Synced/Healthy first (operator must
   be live before the instance CRs can reconcile).
2. `grow-ilias` Application Synced; PVC `ilias-data` Bound; operator creates
   StatefulSet/Pod `mariadb-ilias` + Service `mariadb-ilias`; `mariadb-ilias-root`,
   `-app` secrets ready; Database/User/Grant/Connection become Ready;
   `mariadb-ilias-conn` secret contains `ILIAS_DB_*` keys.
3. Deployment `grow-ilias` Ready (startup probe tolerates the install);
   logs show DB connection + `ILIAS installed successfully!`.
4. CronJob `grow-ilias-ilias-cron` — first successful job after install.
5. `https://training.spencerslab.com` from mesh/LAN → Keycloak forward-auth
   → ILIAS login (`root` / password from the `ilias` Bitwarden item).
6. Collation: `SHOW VARIABLES LIKE 'collation_server'` → `utf8_general_ci`
   and DB `ilias` collation `utf8_general_ci`.

## Risks / notes

- **Operator dependency**: the ilias instance CRs only reconcile once
  `grow-mariadb-operator` is healthy; both deploy from the same merge, and
  ArgoCD retries reconcile, so ordering self-heals.
- **Root/app password shared** (user decision) — rotating one rotates both.
- **No restrictive securityContext** on MariaDB CR and ilias/cron containers
  — documented above; hardening is a follow-up if desired.
- **Disk**: 10Gi (operator PVC) + 30Gi (ilias-data) on the grow data disk;
  local-path cannot expand.
- **Cascade-delete hazard** (inherited from the operator deployment):
  pruning `grow-mariadb-operator` deletes CRDs → all instances.
