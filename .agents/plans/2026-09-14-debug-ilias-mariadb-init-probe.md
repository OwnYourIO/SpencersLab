# Debug: ILIAS first deploy — MariaDB init killed by operator's startup probe

Date: 2026-09-14. Follows `2026-09-14-feat-ilias-mariadb-operator-redesign.md`.

## Symptoms after first sync of grow-ilias / grow-mariadb-operator

- `mariadb-ilias-0` CrashLoopBackOff; logs show MariaDB reaching
  `ready for connections`, then repeated
  `Access denied for user 'root'@'localhost' (using password: YES)` from the
  probes, then kubelet kill.
- `grow-ilias` Deployment + cron Job pods stuck in `CreateContainerConfigError`.
- ArgoCD `grow-ilias` Degraded; MariaDB CR OutOfSync.
- Transient node crisis during the same window: `no space left on device`
  image-pull failures, two evictions at ~142MiB free ephemeral storage
  (recovered on its own; root fs back to ~72GiB free).

## Root cause (evidence: Loki `{cluster="grow", service_name="mariadb"}`)

1. 13:31:28–13:32:42 — first-boot `mariadb-install-db` takes ~75s (slowed by
   the concurrent disk-pressure event).
2. 13:32:42 — entrypoint finishes datadir init, starts its TEMPORARY server
   to apply the init SQL (root password from `mariadb-ilias-root`, users).
3. 13:32:45 — kubelet kills the container: the operator's default startup
   probe budget is only initialDelay 20s + 3×10s ≈ 50s.
4. Every subsequent start: entrypoint sees an initialized datadir → SKIPS
   the init SQL permanently → root password never set → probes (which auth
   with the secret's password) fail forever → CrashLoopBackOff.
5. Downstream: Connection CR never healthy → `mariadb-ilias-conn` secret
   never created → ilias/cron pods `CreateContainerConfigError` (envFrom on
   a missing secret).

Not a password-content problem; not a chart-rendering problem.
`mariadb-erp-next-0` (NOT from this repo) shows the identical failure plus
datadir damage from the disk-full window ("Installation of system tables
failed!").

Secondary independent defect found: the rendered ExternalSecret contained
`ILIAS_HTTP_PATH: "https://OVERRIDE_VIA_APPSET.spencerslab.com"` — the
`charts.ilias.values:` injection from services/grow values never reached the
chart (Application valuesObject only carried `bitwardenIds`). The published
base chart 1.0.193 does not propagate `charts.<app>.values:` into the
per-app valuesObject; only the custom-values per-app block flows through.

## Fixes applied (repo)

1. `charts/ilias/templates/mariadb-ilias.yaml` — explicit `startupProbe` on
   the MariaDB CR: same exec as the operator default
   (`mariadb -u root -p"${MARIADB_ROOT_PASSWORD}" -e "SELECT 1;"`) with
   `failureThreshold: 60` × `periodSeconds: 10` ≈ 10 min budget, covering
   install + temporary-server phases. Liveness/readiness stay operator
   defaults (they gate on the real server with the correct password).
   Also corrected the stale securityContext comment (operator runs the
   instance pod non-root UID 999; init works fine as the mysql user).
2. `publicSubdomain` rerouted: removed the dead `values:` block from
   `services/grow/prod/values.yaml` `charts.ilias`; added
   `publicSubdomain: training` to the `ilias:` block in
   `custom-values/grow/prod-values.yaml` (the proven per-app path, same as
   `bitwardenIds`). Chart keeps the `OVERRIDE_VIA_APPSET` sentinel so a
   missing injection fails visibly.

Validated: `helm lint` clean; render contains the startupProbe and zero
sentinels; all touched YAML parses.

## Cluster actions still required (order matters)

1. Merge to main; sync `grow-ilias` in ArgoCD so the MariaDB CR gains the
   new startupProbe (operator updates the StatefulSet; updateStrategy is
   OnDelete, so the pod must be recreated to pick it up — step 2 does that).
2. Wipe the half-initialized datadir (EMPTY database — no data loss):
   delete pod `mariadb-ilias-0` and PVC `storage-mariadb-ilias-0`
   (default ns). The StatefulSet recreates the PVC from its
   volumeClaimTemplate and the entrypoint runs the full init again, this
   time with the 10-minute probe budget.
3. Watch: init completes → MariaDB Ready → Database/User/Grant/Connection
   reconcile → `mariadb-ilias-conn` secret appears → ilias + cron pods
   leave CreateContainerConfigError → ILIAS install runs under the app's
   own startup probe.

## Notes / follow-ups

- **mariadb-erp-next-0** (external to this repo) needs the same treatment:
  generous startupProbe + datadir wipe (its datadir was additionally damaged
  by the disk-full init failure).
- **Disk headroom**: root fs is 107GiB with mayan-edms already at ~30GiB
  growth within its first hour; ilias adds up to 40GiB more PVC claim.
  local-path does not enforce limits — monitor.
- The operator's default probe budget is a latent trap for every future
  MariaDB instance on slow/disk-pressured nodes → the startupProbe override
  should be added to the skill-doc instance template
  (skills/helm-chart-creation/references/chart-templates.md) — follow-up.
