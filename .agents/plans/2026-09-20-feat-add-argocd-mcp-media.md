# Plan: ArgoCD MCP server on the media cluster (read + refresh + sync, 4-layer enforcement)

## Goal

Expose `matthisholleville/argocd-mcp` on the **media cluster** through the lab's
existing ToolHive platform (`charts/hivetools`), reachable at
`https://mcp.media.spencerslab.com/argocd/mcp`. The server allows ONLY ArgoCD
read/refresh operations plus application sync — enforced at four independent
layers:

1. argocd-mcp `ALLOWED_RESOURCES` (tools for other services are never generated)
2. ToolHive Cedar `authzConfig` — default-deny per-tool allowlist (enforced boundary)
3. ToolHive `MCPToolConfig.toolsFilter` — discovery allowlist (hygiene layer)
4. ArgoCD RBAC on a dedicated `mcp-bot` local account token (backstop: 403 even if
   all other layers fail)

This adapts the user-provided deployment guide to repo reality (see Design
decisions for every deviation). Everything is GitOps — ArgoCD applies all
resources; the only imperative steps are one-time token minting + Bitwarden item
creation, which the USER runs (no MCP tier grants pod exec or secret writes).

## Skills

Code agent must load (fresh session):

- `helm-chart-creation` — repo wiring rules; read its `references/mcp-servers.md`
  first (this work follows that recipe exactly)
- `gitops-workflows` — ArgoCD/secrets-in-git context
- `kubernetes-skill` — manifest review discipline

Not needed: `helm-bjw-s-chart` (hivetools and the media umbrella are plain Helm,
not app-template), `container-creation` (upstream image, no in-repo build).

## MCP Servers

- `readonly-media-kubernetes` — verify media cluster state (MCPServer phase,
  ExternalSecret readiness, pods, ingress) before and after.
- No `admin-*` servers needed: all changes ride ArgoCD syncs. Token minting is a
  user-run step (exact commands below).

## Verified context

Repo recon (all paths confirmed by reading):

- `charts/hivetools/Chart.yaml` — pins `toolhive-operator-crds` + `toolhive-operator`
  **0.34.0** (`oci://ghcr.io/stacklok/toolhive`). Deployed on EVERY cluster via
  `charts/base/values.yaml` → `charts: hivetools:`.
- `charts/hivetools/templates/generic-mcpserver.yaml` — renders one
  `toolhive.stacklok.dev/v1beta1 MCPServer` per `mcp.<name>` entry. Currently does
  NOT render `audit`, `authzConfig`, or `toolConfigRef`; `oidcConfigRef.name` is
  hardcoded to `keycloak`. Extended in this plan.
- `charts/hivetools/templates/generic-mcp-ingress.yaml` — auto-adds one
  `path: /<name>` route per enabled server to `mcp-mcp-<name>-proxy:<mcpPort>` on
  host `mcp.<subDomain|clusterName>.<domain>` (media has no subDomain →
  `mcp.media.spencerslab.com`), TLS via `cluster-wildcard-cert`, path-prefix strip
  via `normalize-mcp-path` middleware. No ingress work needed.
- `charts/base/values.yaml` — `argo-cd.configs.cm` is a generic key→data map
  (accepts `accounts.mcp-bot: apiKey` directly); `argo-cd.configs.rbac.policy.csv`
  currently only `g, Admin, role:admin` with `policy.default: ""`.
- `services/media/prod/values.yaml` — top-level `bitwardenIds:` exists but is
  EMPTY (null); no `hivetools:` key yet. Umbrella `templates/` dir exists.
- `custom-values/media/prod-values.yaml` — top-level `bitwardenIds:` +
  `hivetools.bitwardenIds.mcp-sso` already present (plumbing proven on media).
- `services/gpu/prod/templates/secret-grafana-mcp-token.yaml` — the ExternalSecret
  pattern copied for the token secret.

Live cluster state (media, via `readonly-media-kubernetes`, 2026-09-20):

- ArgoCD **v3.4.5** (chart argo-cd-10.1.4) in namespace **`default`** (NOT
  `argocd`); `argocd-server` Service port 80→8080, insecure mode (`--insecure`,
  plain HTTP); `argocd-cm` has NO accounts; `argocd-rbac-cm` matches base values.
- ToolHive operator **v0.34.0** Running; `mcp-kubernetes-readonly`/`-admin` Ready.
- CRDs (v1beta1 storage): `MCPServer.spec` has `authzConfig` (type `inline` with
  `policies[]`/`entitiesJson`, or `configMap`), `toolConfigRef`, `oidcConfigRef`
  (audience required, unique per server), `audit.enabled`; `MCPOIDCConfig.spec`
  supports `type: kubernetesServiceAccount` with
  `kubernetesServiceAccount.{serviceAccount,namespace,issuer,useClusterAuth}`;
  `MCPToolConfig.spec.toolsFilter` is a name allowlist.
- Image registry check: `ghcr.io/matthisholleville/argocd-mcp` tags include
  **`1.8.0`** (NO `v` prefix — the guide's `v1.8.0` guess is wrong).

Render checks: not run yet — Code agent runs them in Verification before
committing.

## Design decisions

1. **No operator install/upgrade phase.** The guide's Phase 2 is obsolete here:
   hivetools already ships the ToolHive operator (0.34.0) to every cluster, and
   the live CRDs already expose every field the plan needs. Upgrading to 0.50.0
   would touch every cluster for no capability this server requires. Known delta:
   the `toolsFilter`-blocks-`tools/call` fix landed upstream in v0.42.1, so on
   0.34.0 layer 3 is discovery-only hygiene; Cedar (layer 2) + ArgoCD RBAC
   (layer 4) are the enforced boundaries — same posture the guide assigns them.
2. **Single-cluster beachhead on media (user decision).** Each lab cluster runs
   its OWN ArgoCD (verified: gpu/home/infra/media all have argocd-server in
   `default`), and an argocd-mcp instance can only reach its own cluster's
   ArgoCD. Placement is service-level (`services/media/...`), NOT chart-level —
   a chart-level entry would render sentinel ExternalSecrets on every other
   cluster (anti-pattern per `references/mcp-servers.md`).
3. **Exposure via the existing hivetools ingress**, replacing the guide's Kilo
   peer phase: `https://mcp.media.spencerslab.com/argocd/mcp` with TLS from the
   cluster wildcard cert. No Kilo/NodePort/Traefik-IngressRoute work.
4. **Auth = Kubernetes SA tokens** (guide Option A), not the shared Keycloak
   OIDC: the Keycloak OIDC rollout is temporarily disabled lab-wide
   ("OIDC temporarily disabled (2026-09)" comments in hivetools values), and a
   server that can SYNC should not ship unauthenticated. New generic hivetools
   mechanism: `mcpOidcConfigs:` map renders extra `MCPOIDCConfig` resources;
   `mcp.<name>.oidc.configRef` selects one (defaults to `keycloak`). Client SA
   `argocd-mcp-client`; audience `argocd` (unique per server per CRD security
   note). Cedar policies permit any principal, so the SA identity is authn, not
   per-user authz.
5. **Cedar via `authzConfig.type: inline`** (CRD-verified) instead of the guide's
   ConfigMap — one fewer resource, values-driven. Fallback if the 0.34.0 operator
   mishandles inline: same policies in a ConfigMap + `type: configMap`.
6. **ArgoCD account + RBAC through the base chart (GitOps)**, not `kubectl patch`:
   `accounts.mcp-bot: apiKey` in `configs.cm`; mcp-bot policy lines appended to
   `configs.rbac.policy.csv`. Deviations from the guide: (a) `policy.default`
   stays `""` — the guide's `role:readonly` would grant every SSO user read
   access, out of scope; (b) NO `applications, action/*` and NO `repositories`
   grants — none of the 13 allowlisted tools need them, and omitting them makes
   RBAC a real independent backstop. `applications get` covers the
   `?refresh=normal|hard` parameter; `applications sync` covers dry-run + real.
   NOTE: base is consumed as a PUBLISHED chart (`baseChartVersion` in each
   appset), so the account/RBAC lands only after merge → CI version bump +
   chart-releaser publish → Renovate `baseChartVersion` bump (nightly automerge),
   or a manual `baseChartVersion` bump in `services/media/prod/templates/appset.yaml`.
7. **Token lifecycle:** one-time mint by the user against media's ArgoCD, stored
   as the password of a Bitwarden LOGIN item `argocd-mcp-media`, wired via
   ExternalSecret `argocd-mcp` (`bitwarden-login` store) → `ARGOCD_TOKEN`. Until
   the item exists the ExternalSecret stays unready and the server pod cannot
   start — the repo's accepted visible-failure mode (same as `grafana-admin`).
8. **Server config:** `TOOL_MODE=generated`, `DISABLE_WRITE=false` (sync is a
   POST — write scope comes from layers 2-4), `ALLOWED_RESOURCES=
   ApplicationService,ProjectService,ClusterService,VersionService`,
   `ARGOCD_BASE_URL=http://argocd-server.default.svc.cluster.local` (insecure
   mode → no `ARGOCD_TLS_INSECURE`), rate limit 10/20, audit logging on both
   argocd-mcp (`AUDIT_LOG=true`) and the ToolHive proxy (`audit.enabled`).
9. **Image pinned `1.8.0`** (repo rule: pinned tags; Renovate's image regex
   manager currently only scans `templates/`, not values files — same status quo
   as the gpu MCP entries). No chart version bumps by hand (CI bumps
   hivetools/base on merge to main).

## Changes

Ordered. Steps 1-4 are the hivetools platform extension (generic, reusable);
5 is ArgoCD account/RBAC; 6-9 are the media wiring; 10-11 are user steps.

### 1. `charts/hivetools/templates/generic-mcpserver.yaml` — MODIFY

a) In the `oidcConfigRef` block, replace the hardcoded name:

```yaml
  oidcConfigRef:
    name: {{ $config.oidc.configRef | default "keycloak" }}
```

b) Append after the existing `volumes` block (still inside the per-entry range):

```yaml
  {{- if $config.audit }}
  audit:
    {{- toYaml $config.audit | nindent 4 }}
  {{- end }}
  {{- if $config.authz }}
  authzConfig:
    {{- toYaml $config.authz | nindent 4 }}
  {{- end }}
  {{- if $config.toolsFilter }}
  toolConfigRef:
    name: mcp-{{ $name }}-tools
  {{- end }}
```

### 2. `charts/hivetools/templates/generic-mcptoolconfig.yaml` — CREATE

```yaml
{{- /* One MCPToolConfig per mcp entry that defines toolsFilter (discovery
     allowlist). Referenced via toolConfigRef rendered by generic-mcpserver.yaml. */}}
{{- range $name, $config := .Values.mcp }}
{{- if and $config (ne ($config.enabled | toString) "false") $config.toolsFilter }}
---
apiVersion: toolhive.stacklok.dev/v1beta1
kind: MCPToolConfig
metadata:
  name: mcp-{{ $name }}-tools
  namespace: {{ $.Values.namespace | default "default" }}
spec:
  toolsFilter:
    {{- toYaml $config.toolsFilter | nindent 4 }}
{{- end }}
{{- end }}
```

### 3. `charts/hivetools/templates/generic-mcpoidcconfig.yaml` — CREATE

```yaml
{{- /* Extra MCPOIDCConfig resources beyond the shared Keycloak one
     (mcpoidcconfig-keycloak.yaml). Keyed by MCPOIDCConfig name; the value is
     the full spec (type + matching block). Reference from an mcp entry via
     oidc.configRef. */}}
{{- range $name, $config := .Values.mcpOidcConfigs }}
{{- if $config }}
---
apiVersion: toolhive.stacklok.dev/v1beta1
kind: MCPOIDCConfig
metadata:
  name: {{ $name }}
  namespace: {{ $.Values.namespace | default "default" }}
spec:
  {{- toYaml $config | nindent 2 }}
{{- end }}
{{- end }}
```

### 4. `charts/hivetools/values.yaml` — MODIFY

After the `keycloak:` block, add:

```yaml
# Additional MCPOIDCConfig resources (rendered by generic-mcpoidcconfig.yaml),
# keyed by MCPOIDCConfig name. The shared Keycloak config lives in
# mcpoidcconfig-keycloak.yaml; use this map for other OIDC source types (e.g.
# kubernetesServiceAccount). An mcp entry references one via oidc.configRef.
mcpOidcConfigs: {}
```

### 5. `charts/base/values.yaml` — MODIFY (argo-cd subchart config)

a) In `argo-cd.configs.cm`, add the local account key (any position in the map):

```yaml
      # Local account for argocd-mcp (token auth only: apiKey = can mint API
      # tokens, cannot log in interactively). RBAC below; tokens minted
      # per-cluster out-of-band and stored in Bitwarden.
      accounts.mcp-bot: apiKey
```

b) Replace `argo-cd.configs.rbac.policy.csv` with (keeps the existing Admin
line, appends mcp-bot; `policy.default` stays `""`):

```yaml
      policy.csv: |
        g, Admin, role:admin
        # mcp-bot (argocd-mcp server): read + refresh + sync ONLY. Deliberately
        # no create/update/delete/override/action permissions — ArgoCD RBAC is
        # the backstop layer if the ToolHive Cedar/tool-filter layers ever fail.
        p, mcp-bot, applications, get, */*, allow
        p, mcp-bot, applications, sync, */*, allow
        p, mcp-bot, logs, get, */*, allow
        p, mcp-bot, projects, get, */*, allow
        p, mcp-bot, clusters, get, */*, allow
```

### 6. `services/media/prod/values.yaml` — MODIFY

a) Top of file — make the empty `bitwardenIds:` a map:

```yaml
bitwardenIds:
  # Consumed by templates/secret-argocd-mcp.yaml (media ArgoCD API token for
  # the argocd-mcp server). Real UUID lives in custom-values/media.
  argocd-mcp: OVERRIDE_VIA_CUSTOM_VALUES
```

b) Append at the end (complete entry — implement verbatim):

```yaml
# ToolHive MCP platform extension (base deploys hivetools on every cluster):
# argocd-mcp gives read + refresh + sync access to THIS cluster's ArgoCD,
# exposed at mcp.media.<domain>/argocd. Four enforcement layers:
#   1. argocd-mcp ALLOWED_RESOURCES (only these services become tools)
#   2. ToolHive Cedar authzConfig below (default-deny allowlist, enforced)
#   3. MCPToolConfig toolsFilter below (discovery allowlist / hygiene)
#   4. ArgoCD RBAC on the mcp-bot account token (backstop, see charts/base)
hivetools:
  mcpOidcConfigs:
    argocd-k8s-sa:
      type: kubernetesServiceAccount
      kubernetesServiceAccount:
        serviceAccount: argocd-mcp-client
        namespace: default
  mcp:
    argocd:
      enabled: true
      image: ghcr.io/matthisholleville/argocd-mcp:1.8.0
      transport: streamable-http
      mcpPort: 8080
      # SA-token auth (MCPOIDCConfig above): clients send a projected token for
      # SA argocd-mcp-client with audience "argocd" as Authorization: Bearer.
      oidc:
        configRef: argocd-k8s-sa
        audience: argocd
      env:
        - name: MCP_TRANSPORT
          value: "http"
        - name: MCP_ADDR
          value: ":8080"
        # media's ArgoCD runs insecure (server --insecure): plain HTTP on :80.
        - name: ARGOCD_BASE_URL
          value: "http://argocd-server.default.svc.cluster.local"
        - name: AUTH_MODE
          value: "token"
        - name: TOOL_MODE
          value: "generated"
        # MUST stay false — sync is an HTTP POST; write scope is controlled by
        # the Cedar allowlist + toolsFilter + ArgoCD RBAC instead.
        - name: DISABLE_WRITE
          value: "false"
        - name: ALLOWED_RESOURCES
          value: "ApplicationService,ProjectService,ClusterService,VersionService"
        - name: RATE_LIMIT
          value: "10"
        - name: RATE_LIMIT_BURST
          value: "20"
        - name: AUDIT_LOG
          value: "true"
      secrets:
        - name: argocd-mcp
          key: token
          targetEnvName: ARGOCD_TOKEN
      # ToolHive proxy audit logging (denied tool calls show up here).
      audit:
        enabled: true
      # Layer 2 — Cedar default-deny allowlist (enforced on every tools/call).
      # KEEP IN SYNC with toolsFilter below.
      authz:
        type: inline
        policies:
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_get");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_list");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_resource_tree");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_managed_resources");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_list_resource_events");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_pod_logs");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_get_manifests");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_revision_metadata");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_project_get");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_cluster_list");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_cluster_get");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_version");'
          - 'permit(principal, action == Action::"call_tool", resource == Tool::"argocd_application_sync");'
          - 'permit(principal, action == Action::"get_prompt", resource);'
      # Layer 3 — discovery allowlist (renders MCPToolConfig mcp-argocd-tools).
      toolsFilter:
        - argocd_application_get
        - argocd_application_list
        - argocd_application_resource_tree
        - argocd_application_managed_resources
        - argocd_application_list_resource_events
        - argocd_application_pod_logs
        - argocd_application_get_manifests
        - argocd_application_revision_metadata
        - argocd_project_get
        - argocd_cluster_list
        - argocd_cluster_get
        - argocd_version
        - argocd_application_sync
      resources:
        limits:
          cpu: '500m'
          memory: '256Mi'
        requests:
          cpu: '50m'
          memory: '64Mi'
      podTemplateSpec:
        spec:
          volumes:
            - name: tmp
              emptyDir: {}
          containers:
            # Container name MUST be "mcp" (ToolHive requirement).
            - name: mcp
              securityContext:
                runAsNonRoot: true
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop:
                    - ALL
              volumeMounts:
                - name: tmp
                  mountPath: /tmp
```

### 7. `services/media/prod/templates/secret-argocd-mcp.yaml` — CREATE

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-mcp
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: bitwarden-login
    kind: SecretStore
  target:
    name: argocd-mcp
    creationPolicy: Owner
    deletionPolicy: Delete
  data:
    - secretKey: token
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "argocd-mcp" }}'
        property: password
        # Boiler plate needed for ArgoCD to not complain about a mismatch.
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

### 8. `services/media/prod/templates/sa-argocd-mcp-client.yaml` — CREATE

```yaml
# Client identity for the argocd-mcp ToolHive proxy: MCPOIDCConfig
# argocd-k8s-sa (services/media/prod/values.yaml hivetools.mcpOidcConfigs)
# validates projected tokens for this SA. Mint client tokens with:
#   kubectl -n default create token argocd-mcp-client --audience argocd --duration 24h
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-mcp-client
  namespace: default
```

### 9. `custom-values/media/prod-values.yaml` — MODIFY (needs the user's UUID)

Under the existing top-level `bitwardenIds:` add:

```yaml
  argocd-mcp: <UUID-of-Bitwarden-LOGIN-item-argocd-mcp-media>
```

This can only be filled after user steps 10a-10c. Until then the ExternalSecret
stays unready and the server pod stays Pending — visible, accepted failure mode.

### 10. USER steps (one-time, media cluster) — present these, do not run them

a) Wait for the account to land in media's ArgoCD (base chart publish cycle, see
   Design decision 6), then verify:

```bash
kubectl --context <media-context> -n default get cm argocd-cm \
  -o jsonpath='{.data.accounts\.mcp-bot}'; echo        # -> apiKey
kubectl --context <media-context> -n default get cm argocd-rbac-cm \
  -o jsonpath='{.data.policy\.csv}'                    # -> includes mcp-bot lines
```

b) Mint the mcp-bot token — either:
   - UI: `https://cluster.media.spencerslab.com` → Settings → Accounts →
     `mcp-bot` → generate token (no expiry or long expiry recommended), or
   - CLI:
     ```bash
     kubectl --context <media-context> -n default port-forward svc/argocd-server 8080:80
     argocd login localhost:8080 --plaintext --name mcp-setup   # SSO or admin creds
     argocd account generate-token --account mcp-bot --id argocd-mcp-media-$(date +%Y%m%d)
     ```

c) Create Bitwarden LOGIN item **`argocd-mcp-media`** with the JWT as its
   password; note the item UUID and hand it to the Code agent for step 9.

### 11. Client configuration (documentation, after everything is up)

```bash
TOKEN=$(kubectl --context <media-context> -n default create token \
  argocd-mcp-client --audience argocd --duration 24h)
claude mcp add --transport http argocd \
  https://mcp.media.spencerslab.com/argocd/mcp \
  --header "Authorization: Bearer $TOKEN" --scope user
```

Tokens expire (24h default) — re-mint as needed, or script it. Kilo/Workstation
peering is NOT required: the ingress host is reachable wherever the lab domain
resolves (mesh/LAN).

## Verification

Pre-merge (Code agent runs all of these and fixes failures):

1. `helm lint charts/hivetools`
2. Extract the media `hivetools:` block to a temp values file
   (`python3 -c "import yaml,sys; print(yaml.dump(yaml.safe_load(open('services/media/prod/values.yaml'))['hivetools']))" > /tmp/ht-media.yaml`
   — wrap under a top-level `hivetools:` key isn't needed; the block IS the
   hivetools values, but note it contains `mcpOidcConfigs`/`mcp` at top level of
   the extracted file) and render:

   ```bash
   helm template hivetools charts/hivetools \
     --set domain=spencerslab.com --set clusterName=media \
     --set bitwardenIds.mcp-sso=test-uuid --set keycloak.realm=test \
     -f /tmp/ht-media.yaml
   ```

   Confirm: `MCPServer mcp-argocd` (image/transport/mcpPort, env incl.
   ALLOWED_RESOURCES, secrets[] ARGOCD_TOKEN, oidcConfigRef name
   `argocd-k8s-sa` audience `argocd`, audit.enabled, authzConfig inline with 14
   policies, toolConfigRef `mcp-argocd-tools`); `MCPToolConfig mcp-argocd-tools`
   with exactly the 13 names; `MCPOIDCConfig argocd-k8s-sa`
   (kubernetesServiceAccount); ingress host `mcp.media.spencerslab.com` with
   `path: /argocd` → `mcp-mcp-argocd-proxy:8080`. Grep output for `OVERRIDE_` —
   no sentinel in the new resources. Also render WITHOUT `-f` to prove existing
   servers are unchanged: `helm template hivetools charts/hivetools --set ... `
   still renders kubernetes-readonly/admin exactly as before (diff the output).
3. Umbrella render for the two new media templates (run
   `helm dependency update services/media/prod` first if `services/media/prod/charts/`
   is empty):

   ```bash
   helm template media services/media/prod -f services/media/prod/values.yaml \
     --set domain=spencerslab.com --set clusterName=media \
     --set bitwardenIds.argocd-mcp=test-uuid \
     --show-only templates/secret-argocd-mcp.yaml \
     --show-only templates/sa-argocd-mcp-client.yaml
   ```

   (If the umbrella needs other values to render, add minimal `--set`s; a
   `--show-only` "could not find template" error means the gate is closed, which
   is a failure here — both templates must render.)
4. Base chart: `helm dependency update charts/base` if `charts/base/charts/` is
   empty, then

   ```bash
   helm template base charts/base --set domain=test.example.com \
     --set clusterName=media --set serviceName=infra \
     --set bitwardenIds.argocd-sso-secret=test --set bitwardenIds.cert-manager-solver-token=test
   ```

   Confirm `argocd-cm` contains `accounts.mcp-bot: apiKey`, `argocd-rbac-cm`
   policy.csv contains the 5 mcp-bot lines, and `policy.default` is still `""`.
5. Service-trio grep (adapted for an MCP server — no appset/proxy entries
   needed): `grep -rn argocd-mcp services/media/prod/values.yaml
   services/media/prod/templates/ custom-values/media/prod-values.yaml` shows
   the values entry, ExternalSecret template, SA template, and (after user
   provides it) the custom-values UUID.

Post-merge (ArgoCD applies; verify with `readonly-media-kubernetes`):

6. `media-hivetools` Application Synced; `MCPServer mcp-argocd` phase Ready;
   pods `mcp-argocd-0` + the `mcp-argocd-*` proxy Running (after the Bitwarden
   item exists); `ExternalSecret argocd-mcp` Ready=True; ServiceAccount
   `argocd-mcp-client` present; ingress `mcp-multi-server-ingress` has `/argocd`.
7. Functional tests (need the client SA token; user or agent via curl):

   ```bash
   TOKEN=$(kubectl -n default create token argocd-mcp-client --audience argocd --duration 1h)
   H=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "Authorization: Bearer $TOKEN")
   # initialize, capture mcp-session-id header
   curl -sD- https://mcp.media.spencerslab.com/argocd/mcp "${H[@]}" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
   # tools/list with the session id -> exactly 13 tools, no *_delete/_create/_rollback
   ```

   - Call `argocd_application_delete` → JSON-RPC error (Cedar deny); proxy audit
     log shows the denial.
   - Same request without `Authorization` → 401.
   - `argocd_application_get` with `{"name":"<media-app>","refresh":"hard"}` →
     app JSON, `status.reconciledAt` updates (refresh works).
   - `argocd_application_sync` with `{"name":"<media-app>","dryRun":true}` → 200,
     nothing persisted. Real sync only on explicit user approval of a throwaway app.
   - If any allowlisted tool returns ArgoCD `PermissionDenied`, RBAC is missing a
     grant — identify the action from the error and add a narrow `p, mcp-bot, ...`
     line (do NOT widen beyond read+sync).
   - If tools/list names differ from the 13 (swagger drift on ArgoCD 3.4.5),
     update BOTH `toolsFilter` and the Cedar policies to the live names.

## Rollback

- Remove `hivetools.mcp.argocd` + `hivetools.mcpOidcConfigs.argocd-k8s-sa` from
  `services/media/prod/values.yaml`, delete the two media templates, drop the
  `argocd-mcp` lines from media values/custom-values — ArgoCD prunes the
  MCPServer, MCPToolConfig, MCPOIDCConfig, ExternalSecret (+target secret via
  `deletionPolicy: Delete`) and SA.
- Revert the base chart lines to remove the account everywhere; revoke the token:
  `argocd account delete-token --account mcp-bot <token-id>`.
- The hivetools template extensions are additive/no-op for existing entries; they
  can stay even if the argocd server is removed.

## Risks & open questions

- **0.34.0 runtime behavior of inline Cedar + kubernetesServiceAccount authn** is
  CRD-verified but not runtime-proven in this lab. Functional tests 7 cover it.
  Fallbacks: Cedar via ConfigMap (`type: configMap`); worst case ship briefly
  without `oidcConfigRef` (layers 1/3/4 remain) and fix forward.
- **readOnlyRootFilesystem**: argocd-mcp fetches/caches the ArgoCD swagger spec
  at boot; `/tmp` emptyDir is mounted. If it crashloops on a write path, check
  the log for the path and add an emptyDir mount (or drop readOnlyRootFilesystem
  as last resort).
- **runAsNonRoot without runAsUser**: if the image defaults to root the pod
  fails with a clear `CreateContainerConfigError`; fix by setting
  `runAsUser`/`runAsGroup: 65532` in the podTemplateSpec.
- **Base chart publish delay** (Design decision 6): token minting is blocked
  until media's ArgoCD has the mcp-bot account. Expedite by manually bumping
  `baseChartVersion` in `services/media/prod/templates/appset.yaml` to the
  freshly published version instead of waiting for Renovate.
- **Tool names** are derived from the naming rule `argocd_<service>_<operation>`
  for ArgoCD 3.4.5 swagger — confirm from live `tools/list` (test 7) before
  trusting the allowlists.
- **Client token expiry** (24h default) is an operational annoyance, not a
  blocker; longer bound tokens depend on kube API token-expiration settings.
- **Renovate coverage**: `image:` lines in values.yaml files are not matched by
  the current regex manager (templates only) — same as all existing gpu MCP
  entries; leave as-is unless the user wants a renovate.json change separately.
- **mcp-bot lands in every cluster's ArgoCD** (base chart is global) — intended
  and harmless; no token is minted anywhere but media. Repeating this setup for
  another cluster later = steps 6-11 for that category only.

## Post-merge correction (2026-09-20)

First deploy attempt (media-hivetools sync at revision af5e6753) failed with:
`failed to create typed patch object (default/mcp-argocd; ...): .spec.authzConfig.policies: field not declared in schema`.

The ToolHive 0.34.0 MCPServer CRD nests inline policies one level deeper than
step 6b assumed — `authzConfig` requires (CEL-enforced):

```yaml
authzConfig:
  type: inline
  inline:
    policies: [...]   # NOT authzConfig.policies
```

Fixed in `services/media/prod/values.yaml` (`hivetools.mcp.argocd.authz` now
carries the nested `inline:` block). The "Verified context" recon line
"authzConfig (type inline with policies[]/entitiesJson …)" was right about the
fields but elided the nesting. Future Cedar work on this platform: always
check the live CRD's `x-kubernetes-validations` before authoring inline authz.

## Post-merge correction #2 (2026-09-20, transport)

With secrets wired, the backend pod crash-looped:

```
fatal: configuration errors:
  - MCP_TRANSPORT must be 'stdio' or 'http', got "streamable-http"
```

The ToolHive 0.34 operator force-injects its own env into direct-transport
backend containers — `MCP_TRANSPORT=<spec.transport>`, plus `MCP_PORT`,
`MCP_HOST`, `FASTMCP_PORT` — and the injected `MCP_TRANSPORT` REPLACES the
`spec.env` value. argocd-mcp validates MCP_TRANSPORT against `stdio|http`, so
`transport: streamable-http` is unusable for it (v1.8.0 is latest; no
streamable-http acceptance upstream). The existing kubernetes/grafana servers
survive the injection only because they ignore that env var.

Fix (media values): `transport: stdio` — the proxyrunner drives the server
over stdio and still serves streamable-http externally. Dropped `mcpPort`
(stdio servers have no HTTP port) and the `MCP_TRANSPORT`/`MCP_ADDR` env.

Chart changes this forced in `charts/hivetools/templates/`:

- `generic-mcpserver.yaml`: `mcpPort` no longer `required` — gated behind
  `if` (the CRD treats it as optional; stdio servers omit it).
- `generic-mcp-ingress.yaml`: ingress backend port is now
  `proxyPort | default 8080` instead of `mcpPort`. The ingress routes to the
  operator's proxy Service, which always exposes proxyPort — using mcpPort
  was wrong whenever the two differ, and impossible for stdio servers.
  Side effect (fix): gpu's `/playwright` (8931) and `/grafana-*` (8000)
  routes pointed at ports their proxy Services don't expose — live probes
  returned 404 vs 406 for healthy routes. They re-point to 8080 on the next
  gpu hivetools sync. All other fleet routes render unchanged (8080).

## Post-merge correction #3 (2026-09-20, client auth dropped)

The SA-token client auth (kubernetesServiceAccount OIDC) was dropped to match
the fleet-wide posture: every other server's `oidc:` block is commented out
("OIDC temporarily disabled (2026-09)") and the proxies run unauthenticated —
verified live: an auth-less POST initialize to gpu's kubernetes-readonly
returns HTTP 200. Enforcing a 24h-expiring projected SA token on argocd-mcp
alone made it the only server needing per-client credentials, with no
longer-lived compatible option (kubectl create token is capped by
--service-account-max-token-expiration, default 24h; legacy SA secret tokens
carry no `aud` claim and the kubernetesServiceAccount validator requires the
audience).

Change: `oidc:` commented out in the media argocd entry (same fleet
convention). MCPOIDCConfig `argocd-k8s-sa` and ServiceAccount
`argocd-mcp-client` stay in place for a future fleet-wide OIDC re-enable.
Enforcement layers unchanged: Cedar allowlist + toolsFilter + ArgoCD RBAC on
the mcp-bot token; the network perimeter (zerotrust edge) is the client
boundary, as for all other servers.
