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
