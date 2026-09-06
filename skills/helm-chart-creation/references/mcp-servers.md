# MCP Servers on the ToolHive Platform (`charts/hivetools`)

How to add an MCP server to the lab's ToolHive platform. **MCP servers are
NOT standalone charts and NOT kubectl-applied manifests.** They are entries in
the `mcp:` map of `charts/hivetools/values.yaml`, rendered into ToolHive CRDs
and synced by ArgoCD like everything else in this repo.

## When to use

Use this recipe whenever you need to expose a new MCP server (upstream image
or an in-repo image from `containers/`) at `https://mcp.<domain>/<name>`.

Do not:

- Create a new chart under `charts/<mcp-server>/` for an MCP server.
- Ship `k8s/` manifests meant for `kubectl apply` — ArgoCD applies everything.
- Add ApplicationSet entries or `ingress.subdomains` proxy entries — the
  hivetools chart already owns routing for every `mcp.<name>` entry.

## Architecture recap

All pieces live in `charts/hivetools/`:

| File | Role |
|---|---|
| `templates/generic-mcpserver.yaml` | Renders one `toolhive.stacklok.dev/v1beta1 MCPServer` per enabled `mcp.<name>` entry. |
| `templates/generic-mcp-ingress.yaml` | Single shared Traefik `Ingress` on host `mcp.{{ .Values.domain }}`; adds one `path: /<name>` route per enabled server to `mcp-<name>-proxy:<mcpPort>`. |
| `templates/mcp-middleware.yaml` | Traefik middleware `normalize-mcp-path` — strips the `/<name>` prefix (`^/[^/]+(/.*)$` → `$1`) before the request reaches the server. |
| `templates/mcpoidcconfig-keycloak.yaml` | Shared `MCPOIDCConfig` named `keycloak` (issuer `https://login.<domain>/realms/<realm>`, client `{{ .Values.keycloak.clientId }}`, client secret from ExternalSecret `mcp-sso`). Referenced per server via `oidcConfigRef`. |
| `templates/secret-<name>.yaml` | Per-server ExternalSecret when the server needs credentials (see Secrets recipe). |

At runtime the ToolHive operator creates, per server:

- a StatefulSet pod `<name>-0` (the MCP server itself; labels
  `toolhive-name=<name>`, `toolhive-transport=<transport>`), and
- a proxy Deployment `<name>-<hash>` plus Service `mcp-<name>-proxy` that
  the ingress routes to.

The server container runs inside the pod alongside ToolHive's proxy; the
container in any `podTemplateSpec` you supply **must be named `mcp`**.

## `mcp.<name>` entry fields

Add an entry under `mcp:` in `charts/hivetools/values.yaml`:

```yaml
mcp:
  <name>:
    enabled: true                 # both templates accept true; see gotcha below
    image: <registry>/<image>:<pinned-tag>   # REQUIRED, never :latest in prod
    transport: streamable-http    # REQUIRED; or stdio
    mcpPort: 8080                 # REQUIRED; container port == proxy Service port
    oidc:
      audience: <name>            # unique per server, usually the entry name
    env:                          # plain (non-secret) env vars
      - name: SOME_URL
        value: "https://..."
    args: []                      # optional container args
    secrets:                      # optional; see Secrets recipe
      - name: <externalsecret-name>
        key: <key-in-target-secret-data>
        targetEnvName: <ENV_VAR_NAME>
    serviceAccount: <sa-name>     # optional, for in-cluster API access
    resources:
      limits: { cpu: '200m', memory: '256Mi' }
      requests: { cpu: '50m', memory: '64Mi' }
    podTemplateSpec:              # optional pod/container overrides
      spec:
        containers:
          - name: mcp             # MUST be named "mcp"
            securityContext:
              runAsUser: 65532
              runAsGroup: 65532
              runAsNonRoot: true
              allowPrivilegeEscalation: false
              capabilities:
                drop: [ALL]
```

Field notes:

- **`transport`**: `streamable-http` for servers that already speak HTTP MCP
  (set `mcpPort` to the server's listen port). `stdio` servers get ToolHive's
  proxy wrapper (the common `mcp/*` images use this).
- **`mcpPort`** is both the container port and the port of the generated
  `mcp-<name>-proxy` Service that the ingress targets. `proxyPort` is rendered
  by `generic-mcpserver.yaml` only when it is set explicitly — normally you
  only need `mcpPort`.
- **`oidc`**: presence of the block opts the server into the shared Keycloak
  `MCPOIDCConfig` (`oidcConfigRef.name: keycloak`) with the given `audience`.
  Omit `oidc` (or set it null) to opt out of OIDC — only do this for
  deliberately public servers.
- **`secrets[].key`** refers to a key in the ExternalSecret's *target* Secret
  data (e.g. `WEKAN_TOKEN` after templating), not the Bitwarden field name.
- **`enabled`**: both `generic-mcpserver.yaml` and `generic-mcp-ingress.yaml`
  check `ne ($config.enabled | toString) "false"`, so a server is rendered
  unless it is explicitly `enabled: false` (which removes both its MCPServer
  and its ingress route). Keep `enabled: true` explicit for clarity.

## Secrets recipe (ExternalSecret + Bitwarden)

If the server needs credentials:

1. Create `charts/hivetools/templates/secret-<name>.yaml` — an ExternalSecret
   in `namespace: default` (the templates hardcode the namespace) pulling from
   the appropriate Bitwarden store:

   - `bitwarden-login` — username/password items; use `property: password`
     (and `property: username` if needed). Example: `secret-wekan-mcp.yaml`,
     `secret-homeassistant-mcp.yaml`.
   - `bitwarden-fields` — custom fields on an item (`property: <field-name>`).
     Example: `secret-github-mcp.yaml`.
   - `bitwarden-uri` — the item's URI value. Example: the `HA_URL` half of
     `secret-homeassistant-mcp.yaml`.

   Template shape (copy the boilerplate lines verbatim — they keep ArgoCD
   from reporting a diff):

   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: <name>
     namespace: default
   spec:
     refreshInterval: 1h
     target:
       name: <name>
       creationPolicy: Owner
       template:
         engineVersion: v2
         data:
           <ENV_VAR_NAME>: "{{ `{{ .token }}` }}"
     data:
       - secretKey: token
         sourceRef:
           storeRef:
             name: bitwarden-login
             kind: SecretStore
         remoteRef:
           key: '{{ index .Values "bitwardenIds" "<name>" }}'
           property: password
           # Boiler plate needed for ArgoCD to not complain about a mismatch.
           conversionStrategy: Default
           decodingStrategy: None
           metadataPolicy: None
   ```

2. Add the sentinel under `bitwardenIds:` in `charts/hivetools/values.yaml`:

   ```yaml
   bitwardenIds:
     <name>: OVERRIDE_VIA_CUSTOM_VALUES
   ```

3. Add the real Bitwarden item UUID under `hivetools.bitwardenIds` in
   `custom-values/gpu/prod-values.yaml`. The Bitwarden item must exist first —
   until it does, the ExternalSecret stays unready and the server pod cannot
   start (a visible failure, not a silent one).

4. Wire the secret into the server entry via `secrets:` (single/few keys,
   github pattern) or `podTemplateSpec` `envFrom.secretRef` (many keys,
   homeassistant pattern).

## What is NOT needed (vs a normal service)

Adding an MCP server skips the usual service trio because hivetools is already
wired into `services/gpu/prod/values.yaml`:

- No ApplicationSet entry.
- No `ingress.subdomains` proxy entry — `generic-mcp-ingress.yaml` adds the
  `mcp.<domain>/<name>` route automatically for every enabled server.
- No `custom-values/` entry unless the server has secrets (then only the
  `hivetools.bitwardenIds.<name>` UUID).

## In-repo images (`containers/<name>`)

If the MCP server is built in this repo (see the `container-creation` skill),
the docker-build workflow is tag-based: each build on `main` pushes an
immutable `:v<run_number>` tag plus the rolling `:main` tag.

- **Pin `mcp.<name>.image` to the newest published `:v<run_number>` tag** —
  the repo standard (see "Image tag pinning" in the helm-chart-creation
  skill). Renovate proposes the bump when a newer tag is published.
- **Brand-new container with no build yet**: reference the rolling `:main`
  tag and add `imagePullPolicy: Always` to the `podTemplateSpec` `mcp`
  container (the MCPServer top level does not render a pull policy), with a
  note to pin to a `:v<run_number>` once the first build lands. Expect a
  transient ImagePullBackOff until the workflow publishes the image — see
  `mcp.renovate` in `charts/hivetools/values.yaml` for this pattern.
- **Ordering dependency**: the container change must merge and the workflow
  must complete before the pin resolves. Verify the actual tag via GHCR
  (`https://ghcr.io/v2/ownyourio/<name>/tags/list` with an anonymous pull
  token) rather than assuming the run number.

## Pattern recipes

Concrete, reusable patterns built on this platform. Each has a live example in
`charts/hivetools/` you can copy.

### Read-only Postgres MCP (CNPG)

Expose read-only SQL access to a CloudNativePG database as an MCP server,
without handing the MCP pod the app's write-capable credentials. It is a
list-driven pattern: one `postgresMcp` block renders N servers + N secrets.
Live examples: `postgres-coder`, `postgres-flowise`, `postgres-langflow`,
`postgres-n8n`, `postgres-open-webui`.

**Security model (defense in depth):**

- *DB layer — the real boundary:* a dedicated `readonly` role granted only the
  PG14+ predefined `pg_read_all_data` role (read everything, write nothing).
  The app's write credentials never reach the MCP pod.
- *App layer:* `crystaldba/postgres-mcp` runs with `--access-mode=restricted`.
  **`0.3.0` is the final upstream release — pin it, don't float it.**

**Three cooperating pieces, all driven by one list:**

| Piece | Where | What |
|---|---|---|
| `postgresMcp.databases` | `values.yaml` | One entry per DB (`name`, `bitwardenIdKey`, `database`); the shared server settings live once in the `postgresMcp` block. |
| `generic-postgres-mcpserver.yaml` | `templates/` | Ranges the list → one `MCPServer postgres-<name>` per entry (audience `postgres-<name>`, secret `postgres-mcp-<name>`). |
| `secret-postgres-mcp.yaml` | `templates/` | Ranges the same list → one ExternalSecret per entry composing `DATABASE_URI`. |

**Add a database in 3 steps:**

1. **CNPG managed role** in the cluster manifest
   (`charts/<app>/templates/pg-<app>.yaml` or
   `services/gpu/prod/templates/pg-<name>.yaml`):

   ```yaml
   managed:
     roles:
       - name: readonly
         ensure: present
         login: true
         inherit: true
         inRoles:
           - pg_read_all_data
         connectionLimit: 5
         passwordSecret:
           name: pg-<name>-mcp-secret
   ```

2. **Role-password ExternalSecret** next to the cluster. The username is
   hardcoded to the role name; only the password comes from Bitwarden (see the
   "hardcode + fetch" technique below). The LOGIN item's username must equal
   the role name (`readonly`):

   ```yaml
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   metadata:
     name: pg-<name>-mcp-secret
   spec:
     refreshInterval: 1h
     secretStoreRef: { name: bitwarden-login, kind: SecretStore }
     target:
       name: pg-<name>-mcp-secret
       creationPolicy: Owner
       template:
         engineVersion: v2
         data:
           username: readonly
           password: '{{ `{{ .password }}` }}'
     data:
       - secretKey: password
         remoteRef:
           key: {{ index .Values "bitwardenIds" "mcp-pg-<name>" }}
           property: password
           conversionStrategy: Default
           decodingStrategy: None
           metadataPolicy: None
   ```

3. **Wire it up:** add the entry to `postgresMcp.databases`, the sentinel
   `mcp-pg-<name>: OVERRIDE_VIA_CUSTOM_VALUES` under `bitwardenIds`, and the
   real UUID in `custom-values/gpu/prod-values.yaml`.

`DATABASE_URI` is composed in `secret-postgres-mcp.yaml`; the host is
deterministic: `pg-<name>-rw.<ns>.svc.cluster.local:5432`. Password escaping
is covered in Techniques below.

**Credential reuse (temporary):** until a dedicated readonly item exists, the
role's `bitwardenIdKey` may point at the app's own DB LOGIN item (same
password). Swap in a dedicated item/UUID when it's created.

### Grafana MCP (service-account token)

`grafana/mcp-grafana` authenticates to Grafana with a **Viewer**
service-account bearer token (read-only), not the Keycloak OAuth. Two gotchas:

- **`--allowed-hosts '*'` is required.** mcp-grafana validates Host/Origin
  (DNS-rebinding protection); the ToolHive proxy rewrites Host to the backend
  ClusterIP, which is otherwise rejected with **403**.
- **`--disable-write`** enforces read-only server-side, belt-and-braces with
  the Viewer-only token.

The token is the `password` field of a Bitwarden LOGIN item
(`bitwarden-login` store), wired via `secrets[]` →
`GRAFANA_SERVICE_ACCOUNT_TOKEN`. `GRAFANA_URL` is the public Grafana ingress
(the monitoring stack may live on another cluster). See `mcp.grafana` +
`templates/secret-grafana-mcp-token.yaml`.

### Private-repo access via initContainer clone

For an MCP server that needs the repo's contents but no runtime GitHub auth
(e.g. `renovate`, which validates/dry-runs `renovate.json`): an initContainer
git-clones the private repo into a shared emptyDir using an existing PAT; the
`mcp` container reads the clone and needs no GitHub credentials itself.

- Reuse an existing PAT secret (e.g. `github-mcp`'s
  `GITHUB_PERSONAL_ACCESS_TOKEN`) via `secretKeyRef` in the initContainer.
- Clone `--depth 1 --branch main` into `/workspace` (an emptyDir shared with
  the `mcp` container).
- stdio transport is single-connection by design (one session at a time).
- Heavy tools (Renovate dry-runs) need real resources (~2 CPU / 4Gi limit) and
  writable scratch dirs (`HOME=/tmp`, `RENOVATE_BASE_DIR=/cache` emptyDirs)
  under `readOnlyRootFilesystem: true`.

See `mcp.renovate` in `charts/hivetools/values.yaml`.

## Techniques & gotchas

- **ESO template inside Helm → backtick-escape it.** ExternalSecret
  `target.template.data` values are Go templates evaluated by ESO at sync time,
  *not* by Helm. Pass them through literally by wrapping in a Helm raw string:
  `password: '{{ `{{ .password }}` }}'`. Without the backticks, Helm evaluates
  `{{ .password }}` itself and renders it empty.
- **Hardcode a value next to a fetched one.** Put the literal in
  `target.template.data` (`username: readonly`) and reference fetched keys with
  the backtick technique; only fetched fields need a `data[].remoteRef`.
- **Percent-encode passwords for URIs.** In an ESO template,
  `{{ .password | urlquery | replace "+" "%20" }}` percent-encodes every
  non-unreserved character — the full charset, unlike a hand-rolled `replace`
  chain. `urlquery` renders spaces as `+` (query-string style), so normalize
  them back to `%20` for the URI userinfo component.
- **`imagePullPolicy` belongs on the pod container, not the MCPServer.** The
  MCPServer top level doesn't render a pull policy; set `imagePullPolicy: Always`
  on the `mcp` container (and any initContainer) in `podTemplateSpec` when the
  tag is mutable (e.g. `:main`).
- **`deletionPolicy: Delete`** on credential/token ExternalSecrets so the target
  Secret is removed when the ExternalSecret is pruned — no orphaned credential.

## Validation

1. `helm lint charts/hivetools`
2. Render and inspect:

   ```
   helm template hivetools charts/hivetools \
     --set domain=test.example.com \
     --set bitwardenIds.<name>=test-uuid \
     --set keycloak.realm=test
   ```

   Confirm: the `MCPServer <name>` renders (image, transport, mcpPort,
   `oidcConfigRef` with audience, env/secrets), the `ExternalSecret <name>`
   renders with your test UUID, and the ingress contains `path: /<name>` →
   `mcp-<name>-proxy`. Grep the output for `OVERRIDE_`: no sentinel may
   appear in the new server's rendered resources (hits from other servers'
   sentinels are expected in an isolated render and are resolved by
   `custom-values/` at deploy time).
3. Post-sync (gpu cluster): `kubectl get pods -l toolhive-name=<name>` shows
   `<name>-0` and the `<name>-*` proxy Running; check the server log for its
   startup line; exercise `tools/list` through
   `https://mcp.<domain>/<name>/mcp` with a Keycloak token for client `mcp`
   carrying the server's audience.

Worked example of a full in-repo MCP server wired this way: `wekan`
(`containers/wekan-mcp` + `mcp.wekan` in `charts/hivetools/values.yaml` +
`templates/secret-wekan-mcp.yaml`).
