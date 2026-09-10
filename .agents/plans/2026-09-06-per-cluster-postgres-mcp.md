# Per-cluster Postgres MCP servers + cross-cluster access

Date: 2026-09-06
Status: PLANNED (implementation pending user go-ahead on the per-cluster hivetools approach)

## Background

Read-only Postgres MCP servers (crystaldba/postgres-mcp) were added for the 6 GPU-cluster
databases (coder, flowise, langflow, n8n, open-webui, supabase). They run via the hivetools
chart, which is deployed ONLY in the GPU cluster, and reach their databases over cluster-local
DNS (`pg-<name>-rw.<ns>.svc.cluster.local`).

The remaining Postgres databases live in OTHER clusters (grow, home, infra) and are unreachable
from the GPU cluster. The user chose the **per-cluster hivetools** approach: deploy hivetools in
each cluster so the MCP servers run next to their databases (no cross-cluster DB exposure).

## Complete PG cluster inventory (verified)

| Cluster   | PG cluster                    | Database             | Deployed by            | MCP? |
|-----------|-------------------------------|----------------------|------------------------|------|
| gpu       | pg-coder                      | coder                | gpu service (svc-level)| done |
| gpu       | pg-open-webui                 | open-webui           | gpu service (svc-level)| done |
| gpu       | pg-flowise                    | flowise              | flowise chart          | done |
| gpu       | pg-langflow                   | langflow             | langflow chart         | done |
| gpu       | pg-n8n                        | n8n                  | n8n chart              | done |
| gpu       | pg-supabase                   | supabase             | supabase chart         | done |
| grow      | pg-grow-assistant             | home-assistant       | assistant chart        | done |
| grow      | pg-grow-assistant-sensors     | sensors              | assistant chart        | done |
| home      | pg-immich                     | immich               | immich chart           | done |
| home      | pg-postiz                     | postiz               | postiz chart           | done |
| home      | pg-temporal                   | temporal             | postiz chart           | skip (user) |
| home      | pg-temporal-visibility        | temporal-visibility  | postiz chart           | skip (user) |
| home      | pg-home-rallly                | rallly               | rallly chart           | done |
| home      | pg-paperless                  | paperless            | home service (svc-level)| done |
| infra     | pg-keycloak                   | keycloak             | keycloakx chart        | done |
| (n/a)     | pg-langfuse / pg-langgraph    | langflow/langgraph   | NOT deployed           | skip |

Note: home-assistant's two clusters share one Bitwarden item (`home-assistant-pg`); the sensors
cluster bootstraps from the same `pg-<release>-secret`.

## Approach: per-cluster hivetools

Deploy the hivetools chart in the grow, home, and infra services, but enable ONLY the postgres
MCP servers for that cluster's databases (disable the other MCP servers: playwright, git, github,
homeassistant, kubernetes, fetch, filesystem, sequential-thinking, firecrawl, searxng, wekan,
grafana, renovate).

### Per-cluster requirements
- hivetools subcharts bring the toolhive-operator + CRDs automatically.
- external-secrets-bitwarden is already deployed in grow/home/infra (bitwarden-login SecretStore).
- cloudnative-pg is already a chart dependency in home/infra; grow deploys it too.
- Keycloak OIDC: MCPOIDCConfig points at Keycloak (infra cluster). Remote clusters need the
  Keycloak issuer reachable. NOTE: Keycloak runs in infra; grow/home MCP servers authenticate
  against it over the network. Confirm the issuer URL is reachable cross-cluster.

### Per-database wiring (same pattern as the 6 GPU ones)
For each database:
1. CNPG `managed.roles` readonly entry (pg_read_all_data, connectionLimit 5,
   passwordSecret `pg-<cluster>-mcp-secret`) in the cluster's pg-*.yaml.
2. `pg-<cluster>-mcp-secret.yaml` ExternalSecret (bitwarden-login, username hardcoded `readonly`,
   password from the Bitwarden item) in the owning chart's templates/.
3. hivetools values: `postgresMcp.databases[]` entry + `bitwardenIds.mcp-pg-<name>`.
4. custom-values/<cluster>/prod-values.yaml: `mcp-pg-<name>` UUID (reuse the app-DB item UUID,
   matching the GPU approach) under the hivetools block.
5. Bitwarden LOGIN item `mcp-pg-<name>` (username=readonly) — user creates these.

## Open questions / risks — RESOLVED (2026-09-06)
- Keycloak issuer reachability from grow/home clusters: verified login.spencerslab.com
  returns 200 cross-cluster; moot while OIDC is disabled.
- Ingress exposure: YES — resolved by the mcp-platform-to-base refactor (merged to
  main): hivetools deploys on every cluster via base's charts: list, ingress at
  mcp.<subDomain|clusterName>.<domain> + cluster-wildcard-cert.
- home-assistant's shared Bitwarden item: REUSE it for both readonly roles
  (user decision); swap to dedicated username=readonly items later.
- temporal/temporal-visibility: NO MCP servers (user decision).
- OIDC: NOT implemented yet — oidcConfigRef commented out chart-wide on main
  ("Disable oidc for now"); per-cluster servers ship without OIDC.

## Architecture note (supersedes "Per-cluster requirements" above)
Main's `.agents/plans/2026-09-06-mcp-platform-to-base.md` refactor landed: base
deploys hivetools everywhere (default server: kubernetes). Per-cluster postgres
servers are added purely via values — service `hivetools:` block
(`postgresMcp.databases` + `bitwardenIds` sentinels) + custom-values UUIDs. No
charts: entry needed. gpu's transitional charts:hivetools entry removed (Phase 2).

## Status
- GPU-cluster MCP servers: DONE (committed; supabase included).
- Per-cluster postgres MCP: IMPLEMENTED on update-mcp-servers-v2, pending merge to main.
  - grow: grow-assistant (db home-assistant), grow-assistant-sensors (db sensors)
  - home: immich, postiz, home-rallly (db rallly), paperless
  - infra: keycloak
  - All reuse the app-DB Bitwarden items (temporary, documented per entry).
  - baseChartVersion bumped 1.0.183 -> 1.0.192 in all 7 non-gpu appsets
    (delivers the platform + these servers once merged).
- Validated: helm lint + helm template on all touched charts/umbrellas;
  per-cluster hivetools renders MCServers + ExternalSecrets + ingress routes
  (home host: mcp.home-lab.spencerslab.com).

## Rollout (after merge to main)
1. ArgoCD syncs: <svc>-hivetools Applications appear on grow/home/infra;
   CNPG reconciles the readonly roles; ExternalSecrets ready once Bitwarden
   items/passwords match (reused items already exist).
2. Out-of-repo: verify *.grow. / *.home-lab. / *.infra. wildcard DNS resolves
   to each cluster's traefik.
3. Client config: point MCP clients at
   https://mcp.<cluster>.<domain>/postgres-<name>/mcp
   (grow: mcp.grow., home: mcp.home-lab., infra: mcp.infra.).
4. Later: dedicated username=readonly Bitwarden items per DB; OIDC re-enable
   (uncomment oidcConfigRef in generic-postgres-mcpserver.yaml + per-server
   oidc blocks).

## MCPServer rename (2026-09-06, user decision)
All ToolHive MCPServers get the `mcp-` prefix: `kubernetes` → `mcp-kubernetes`,
`postgres-<db>` → `mcp-postgres-<db>`, gpu extras (playwright, homeassistant,
searxng, wekan, grafana, renovate) → `mcp-<name>`. Scope: ALL servers
(generic-mcpserver.yaml + generic-postgres-mcpserver.yaml).
- Ingress PATHS are unchanged (`/<name>`, `/postgres-<name>`) — external URLs
  stay stable; only resource names change.
- ToolHive derives Service names as `mcp-<serverName>-{proxy,headless}`
  (verified upstream: controllerutil.CreateProxyServiceName), so services
  become `mcp-mcp-*`; ingress backends updated accordingly.
- ExternalSecret/secret names (`postgres-mcp-<name>`) and RBAC names
  (`kubernetes-mcp`) unchanged.
- baseChartVersion bumped 1.0.192 → 1.0.193 in all 8 appsets; charts/base
  comment updated in the same merge so the release pipeline publishes
  base 1.0.193 (brief chart-not-found window between merge and release is
  accepted).
- kilo.jsonc: gpu cluster-local URLs updated to mcp-mcp-* service names;
  they resolve only after merge + ToolHive rollout (expect gpu MCP blip).

## Kubernetes tier split + external naming (2026-09-07, user decisions)
1. The single kubernetes server is replaced by TWO servers on every cluster:
   - `mcp-kubernetes-readonly` — SA/ClusterRole `kubernetes-mcp-readonly`,
     read tier only, `--read-only` flag (write tools hidden).
   - `mcp-kubernetes-admin` — SA/ClusterRole `kubernetes-mcp-admin`, the
     SAME role contents as the old single server (read + restart tier);
     user may extend it later. NOT cluster-admin.
   RBAC template split with a shared read-rules define; both tiers keep
   no-secrets/no-exec boundaries.
2. MCP ingress host follows the repo cluster-scoped convention
   `mcp.<subDomain|clusterName>.<domain>`. Initially switched home to
   `mcp.home.<domain>` (external clusterName), but DNS landed for the
   subDomain instead → REVERTED to `mcp.home-lab.<domain>` (2026-09-07).
   No base cert change needed (cluster-wildcard-cert already covers
   `*.<subDomain>`).
3. kilo.jsonc: kubernetes entries split into readonly/admin pairs (gpu
   cluster-local + per-cluster external); home entries on
   `mcp.home-lab.spencerslab.com`.

## Global utility servers + HA/Grafana tier split (2026-09-07, user decisions)
1. Client-config naming: shared utility servers use the `global-` prefix
   instead of `gpu-`: wekan, grafana, searxng, playwright, renovate,
   homeassistant. Cluster-scoped servers (kubernetes, postgres) keep their
   cluster prefix.
2. Home Assistant split into `homeassistant-readonly` / `homeassistant-admin`
   (MCPServers mcp-homeassistant-*). Both use the SAME homeassistant-mcp
   secret (HA tokens have no roles); the readonly tier sets ha-mcp's native
   `READ_ONLY_MODE=true` (hides write tools + blocks writes at call time).
3. Grafana split into `grafana-readonly` / `grafana-admin` (MCPServers
   mcp-grafana-*). Readonly keeps `--disable-write` + the existing Viewer
   token (grafana-mcp-token). Admin drops `--disable-write` and uses a NEW
   `grafana-mcp-admin-token` secret (ExternalSecret template added to
   services/gpu/prod/templates/; sentinel in gpu bitwardenIds). The admin
   server cannot start until the user creates the Grafana Admin SA token +
   Bitwarden item and adds its UUID to custom-values/gpu.
4. AGENTS.md registry + agent files updated to the new names/tiers.
5. Grafana admin token landed: Bitwarden item UUID
   d37bc58e-ab95-4935-83bc-b4be01021699 wired in custom-values/gpu
   (top-level bitwardenIds.grafana-mcp-admin-token).

## Final client-config naming convention (2026-09-07)
Kilo config entry names settled on `<cluster>-<priv>-<service>` (priv first):
`gpu-readonly-kubernetes`, `home-readonly-postgres-immich`,
`global-readonly-homeassistant`. Untiered servers stay `<cluster>-<service>`
(`global-searxng`). Server-side names are unaffected — MCPServer resources
stay `mcp-<name>`, ingress paths `/<name>`, hivetools values keys
`<name>`/`<name>-readonly`/`<name>-admin`.
Agent privilege rules recorded in AGENTS.md + agent definitions: planning
agents (plan, dependency-map, read-only stages) use `*-readonly-*` only;
code agent uses `*-readonly-*` freely and asks the user before any
`*-admin-*` server.
