# Move postgres-mcp servers to pg-airman-mcp (streamable-http)

Date: 2026-10-19
Status: IMPLEMENTED (validated locally; ArgoCD syncs on merge — no cluster mutations performed)

## Background

The read-only Postgres MCP servers (`postgresMcp.databases`, one per CNPG
cluster across gpu/grow/home/infra) ran `crystaldba/postgres-mcp:0.3.0` —
unmaintained since 0.3.0 — on the **stdio** transport. ToolHive wraps stdio
backends with a supergateway-style proxy; that process-per-session model has a
cold-start race that deterministically fails the first `tools/call` of every
new MCP session (crystaldba/postgres-mcp#223).

Decision (user): adopt **`enterprisedb/pg-airman-mcp:1.1.1`** (published
2026-05-11), the maintained EDB successor, as one process serving every
session through one shared pool (min 1 / max 5 — airman's built-in default)
on the native streamable-http transport:

- `--transport=streamable-http`
- `--streamable-http-host=0.0.0.0` (upstream default is `localhost`)
- `--streamable-http-port=8080` (upstream default is `8001`)
- `--access-mode=restricted`
- env `ALLOW_COMMENT_IN_RESTRICTED=false` — defaults to `true` upstream and is
  the one place airman's restricted mode is looser than crystaldba 0.3.0
  (it allows `COMMENT ON` writes). Setting it `false` restores strict
  read-only semantics.

## Changes

1. `charts/hivetools/values.yaml` — `postgresMcp` block:
   - `image: enterprisedb/pg-airman-mcp:1.1.1` (was `crystaldba/postgres-mcp:0.3.0`)
   - `transport: streamable-http` (was `stdio`)
   - `mcpPort: 8080` (unchanged — the proxy Service port and client URL
     contract stay identical)
   - `args`: the four flags above
   - new `env:` list with `ALLOW_COMMENT_IN_RESTRICTED: "false"`
   - resources, security context, runAsUser 1000 (matches the airman image's
     `app` user), readOnlyRootFilesystem + /tmp emptyDir: unchanged
2. `charts/hivetools/templates/generic-postgres-mcpserver.yaml`:
   - render `env` on the MCPServer (mirrors `generic-mcpserver.yaml`)
   - secret wiring renamed `DATABASE_URI` → `AIRMAN_MCP_DATABASE_URL`
     (airman's native var; its entrypoint only bridges `DATABASE_URI` with a
     deprecation warning)
3. `charts/hivetools/templates/secret-postgres-mcp.yaml` — ExternalSecret
   target key renamed to `AIRMAN_MCP_DATABASE_URL` (same composed URI:
   `postgresql://readonly:<urlencoded>@pg-<name>-rw.<ns>.svc.cluster.local:5432/<db>`)
4. Comment-only renames (`DATABASE_URI` → `AIRMAN_MCP_DATABASE_URL`) in
   `services/{grow,home,infra}/prod/values.yaml` database-list comments.
5. `skills/helm-chart-creation/references/mcp-servers.md` — read-only Postgres
   recipe updated to the airman security model and transport.

## Deliberately NOT changed

- Client-side MCP config (`.opencode/opencode.jsonc`, machine globals): the
  servers stay reachable at the same URLs — `.../mcp` on
  `mcp-mcp-postgres-<name>-proxy:8080` (in-cluster) /
  `https://mcp.<cluster>.<domain>/postgres-<name>/mcp` (ingress). The
  streamable-http kubernetes servers already prove this path.
- Bitwarden UUIDs / `custom-values/`: unchanged (same `readonly` role
  passwords, same `bitwardenIds` keys).
- CNPG managed roles (`connectionLimit: 5`): still consistent with the shared
  pool max of 5 per server process.
- Liveness probe: unchanged — it polls the ToolHive proxy `/health` and is
  transport-agnostic (missing `mcp.available` treated as healthy).
- `OVERRIDE_VIA_CUSTOM_VALUES` placeholders: none added or removed.
- Historical plan docs under `.agents/plans/20*` keep their crystaldba text.

## Validation performed

- `helm lint charts/hivetools` — pass (INFO icon-only note).
- `helm template charts/hivetools` bare render — pass; no postgres servers
  with the default empty `databases` list.
- Render with a test database entry: MCPServer `mcp-postgres-testdb` shows
  image/transport/mcpPort/args/env/secrets exactly as specified; ExternalSecret
  composes `AIRMAN_MCP_DATABASE_URL`; ingress route `/postgres-testdb` →
  `mcp-mcp-postgres-testdb-proxy:8080`; no `OVERRIDE_*` sentinel in the
  postgres resources.
- Render with the real gpu `hivetools.postgresMcp.databases` overlay: all 6
  servers + secrets render with the composed URI per database.
- Upstream verification: Docker Hub tag `1.1.1` pushed 2026-05-11 (amd64/arm64,
  non-root uid 1000); v1.1.1 README config reference (flag/env names and
  defaults); `docker-entrypoint.sh` (DATABASE_URI bridge, arg passthrough);
  crystaldba/postgres-mcp#223 read to confirm the rationale.
- `aislop scan --changes` — score 100, 0 findings.
- Fusion re-check (2026-10-19): `helm lint` + `helm template` re-run (bare,
  test database entry, real gpu overlay with Bitwarden UUIDs, home overlay);
  `aislop ci --changes` — score 100, 0 errors, 0 warnings.

## Rollout notes (for the user)

- One ArgoCD sync per cluster after merge; ToolHive replaces the stdio
  backend pods with streamable-http ones. Expect a brief MCP downtime per
  server during rollout.
- During the ExternalSecret re-render the target Secret key moves
  `DATABASE_URI` → `AIRMAN_MCP_DATABASE_URL`. A first-start pod that races
  the re-render crash-loops until the Secret lands, then converges without
  intervention (seconds).
- Smoke test after sync: pods Running with 0 restarts
  (`kubectl get pods -n default -l toolhive-name=mcp-postgres-<name>`), then
  `tools/list` through `https://mcp.<cluster>.<domain>/postgres-<name>/mcp`.
- If a rollback is needed: revert the commit — stdio wiring is fully
  described by the pre-change values.
