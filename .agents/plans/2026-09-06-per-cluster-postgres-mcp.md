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
| grow      | pg-grow-assistant             | home-assistant       | assistant chart        | TODO |
| grow      | pg-grow-assistant-sensors     | sensors              | assistant chart        | TODO |
| home      | pg-immich                     | immich               | immich chart           | TODO |
| home      | pg-postiz                     | postiz               | postiz chart           | TODO |
| home      | pg-temporal                   | temporal             | postiz chart           | TODO |
| home      | pg-temporal-visibility        | temporal-visibility  | postiz chart           | TODO |
| home      | pg-home-rallly                | rallly               | rallly chart           | TODO |
| home      | pg-paperless                  | paperless            | home service (svc-level)| TODO |
| infra     | pg-keycloak                   | keycloak             | keycloakx chart        | TODO |
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

## Open questions / risks
- Keycloak issuer reachability from grow/home clusters (Keycloak is in infra).
- Whether to expose the remote MCP servers via ingress (they'd be reachable at
  mcp.<domain> per cluster) or keep them cluster-local.
- home-assistant's two clusters share one Bitwarden item; the readonly role needs its own item.
- postiz has 3 clusters (postiz, temporal, temporal-visibility) — temporal/temporal-visibility
  are infrastructure DBs; confirm they should get MCP servers.

## Status
- GPU-cluster MCP servers: DONE (committed).
- Per-cluster hivetools: PLANNED, pending user go-ahead.
