# Plan: MCP platform on every cluster — hivetools wired into base (+ kubernetes-mcp RBAC upgrade)

## Goal

Every cluster gets the ToolHive MCP platform by having the `base` chart deploy
`charts/hivetools` through its generic `charts:` list. By default each cluster
presents only the **kubernetes** MCP server at
`https://mcp.<clusterName>.<domain>` (or `mcp.<subDomain>.<domain>` where a
service sets `subDomain`, matching the `cluster-wildcard-cert`). Clusters can
add Postgres DBs (`postgresMcp.databases`) and extra MCP servers, and disable
servers, through the normal values mechanism. The gpu cluster keeps all 12 of
its current extra servers + 5 Postgres DB servers as **service-level** config.
The gpu `mcp-sso` Bitwarden item is reused on every other cluster.

Additionally, the kubernetes MCP server's ServiceAccount RBAC is upgraded from
strict read-only to **read + restart/rollout** (user-confirmed scope): secrets
list (names only), cluster-wide pod delete, workload patch/scale for rollout
restarts, plus filled read gaps (nodes, PVs, storageclasses). ArgoCD resources
stay read-only. The privilege model is documented agent-facing in
`skills/helm-chart-creation/references/mcp-servers.md`.

## Skills

Code agent must load (fresh session):

- `helm-chart-creation` (plus `references/mcp-servers.md`,
  `references/values-and-appset.md`, `references/storage-and-secrets.md`)
- `gitops-workflows` (ApplicationSet template change in base)
- `kubernetes-skill` (manifest/RBAC review hygiene)

## MCP Servers

- `kubernetes` — verify live state (gpu cluster reachable; confirm
  gpu-hivetools health before/after; post-sync `kubectl auth can-i` matrix).

## Verified context

- `charts/hivetools` = the whole MCP platform today: ToolHive operator+CRDs
  deps (0.34.0), `mcp:` map → `generic-mcpserver.yaml`, `postgresMcp` →
  `generic-postgres-mcpserver.yaml` + `secret-postgres-mcp.yaml`, shared
  `Ingress` at `mcp.{{ .Values.domain }}` + `normalize-mcp-path` middleware,
  `MCPOIDCConfig keycloak` + `mcp-sso` ExternalSecret, `rbac-kubernetes-mcp.yaml`,
  and 4 gpu-specific secret templates (`secret-github-mcp`, `secret-grafana-mcp-token`,
  `secret-homeassistant-mcp`, `secret-wekan-mcp`) + `pvc-knowledge-default.yaml`.
- `charts/base` is deployed by **every** service appset (8 services, pinned
  `baseChartVersion`: gpu 1.0.191, all others 1.0.183). Base renders
  `<serviceName>-charts-appset` (`templates/appset-charts.yaml`) which ranges
  `.Values.charts` → one Application per entry; per-app values =
  `merge(dict "shared-storage" …, index $.Values $appName)`. One cluster runs
  one service (base contains ArgoCD), so a base `charts:` entry deploys
  exactly once per cluster. Helm deep-merges chart values < service values <
  custom-values, so a service can add/override `charts:` and `hivetools:` keys.
- Live gpu cluster: `clusterName=gpu`, `domain=spencerslab.com`,
  `gpu-hivetools` Synced/Healthy; MCP currently at `mcp.spencerslab.com`.
  Live check confirmed the SA currently **cannot list secrets**.
- `charts/base/templates/cert-manager-wildcard-cert.yaml` issues
  `cluster-wildcard-cert` for `*.<subDomain|clusterName>.<domain>`;
  `services/home/prod/values.yaml` sets `subDomain: home-lab` and home's
  appset builds cluster-scoped hosts as `dig "subDomain" clusterName .values`
  — the repo convention for cluster-scoped hostnames is
  **subDomain-if-set-else-clusterName**.
- `subDomain` is NOT currently propagated into the per-chart values slice in
  `appset-charts.yaml` (only `shared-storage` is).
- Values flow for hivetools on gpu: chart `values.yaml` < valuesObject built
  from `$.Values.hivetools` (gpu service values + `custom-values/gpu/prod-values.yaml`
  nested `hivetools:` block). Lists replace, maps merge.
- All `custom-values/*/dev-values.yaml` are empty (0 bytes) — nothing to do.
- `renovate.json` has a dedicated manager bumping `baseChartVersion` in all
  service appsets after each base chart release.
- Umbrella `services/gpu/prod` already renders ExternalSecrets
  (`pg-coder-mcp-secret.yaml` etc.) reading `.Values.bitwardenIds.*` — the 4
  moved secret templates use the same pattern.
- **kubernetes-mcp-server (upstream, v0.0.65 image):** `--read-only` blocks
  ALL write tools; there is no per-verb tool gating (RBAC is the real
  boundary). Mutating tools: `pods_delete` (delete pods), `resources_delete`,
  `resources_create_or_update` (Server-Side Apply → needs `patch`),
  `resources_scale` (needs the `scale` subresource). `pods_exec`/`pods_run`
  exist but stay RBAC-denied. Default toolsets = config+core (helm toolset
  off). Node tools (`nodes_log`, `nodes_stats_summary`) go through the
  kubelet API proxy → need `nodes/proxy`.
- **Prior decision being partially reversed:** plan
  `2026-08-12-restrict-kubernetes-mcp-secrets.md` removed Secrets access from
  this ClusterRole. User now re-adds **list/watch only** (names, no contents).
- Current ClusterRole `kubernetes-mcp-view` read gaps found during recon: no
  core `nodes`, no `nodes/proxy`, no `persistentvolumes`, no `storageclasses`.

## Design decisions

1. **hivetools stays its own chart; base references it in `charts:`** (user
   decision). No ToolHive deps move into base; no `initialInstall` CRD
   complications (hivetools deploys as its own Application with
   `ServerSideApply: "true"`, exactly as gpu does today).
2. **Default = kubernetes MCP server only** (user decision). The other 12
   server definitions move verbatim into `services/gpu/prod/values.yaml` under
   an `hivetools:` key — they are gpu environment-specific (in-cluster URLs,
   knowledge PVC, external-service tokens).
3. **Host = `mcp.<subDomain|clusterName>.<domain>`** with TLS from
   `cluster-wildcard-cert`. Literal `clusterName` would break TLS on home
   (`subDomain: home-lab` → cert covers only `*.home-lab.*`); this matches the
   cert template and home's ArgoCD URL convention. On gpu it renders
   `mcp.gpu.spencerslab.com` as requested.
4. **`subDomain` propagation**: `appset-charts.yaml` adds `subDomain` to the
   per-app values slice when the service values set it (same mechanism as
   `shared-storage`).
5. **gpu-specific templates leave hivetools**: the 4 secret templates +
   knowledge fallback PVC move to `services/gpu/prod/templates/` (they'd
   render broken sentinel ExternalSecrets on other clusters if they stayed).
6. **Transitional gpu `charts: hivetools:` entry is KEPT in Phase 1.** The gpu
   cluster runs pinned base 1.0.191 until renovate bumps `baseChartVersion`;
   removing gpu's entry in the same PR would prune `gpu-hivetools` (charts-appset
   is automated prune) and drop gpu MCP until the bump lands. Remove it in
   Phase 2 after all clusters run the new base.
7. **Secrets rollout** (user decision): reuse gpu's `mcp-sso` UUID
   `2c3ac9dd-636a-4c3e-ba1e-b498002ed133` + `keycloak.realm: SpencersLab` in
   every other service's `custom-values/<svc>/prod-values.yaml` (one shared
   Keycloak client `mcp` for all clusters).
8. **kubernetes-mcp RBAC = read + restart, no exec, no ArgoCD writes**
   (user-confirmed answers to the three scope questions):
   - Secrets: **list/watch only — no `get`** (names/metadata visible,
     contents stay private; partial reversal of the 2026-08-12 decision).
   - Pod delete **cluster-wide** + `pods/eviction` create (PDB-safe eviction).
   - Rollout restart/undo/scale: `patch`+`update` on deployments,
     statefulsets, daemonsets, replicasets, replicationcontrollers +
     get/patch/update on their `scale` subresources. No create/delete on
     workloads — git stays source of truth, ArgoCD owns lifecycle.
   - ArgoCD (argoproj.io) stays **read-only** — a literal `argocd app sync`
     needs ArgoCD's own API/token anyway; revisit later if wanted.
   - Read gaps filled: `nodes` + `nodes/proxy` (nodes_log/stats tools),
     `persistentvolumes`, `storageclasses`.
   - `--read-only` flag is dropped from the server args (with it set, RBAC
     grants would be useless — all write tools are hidden).
   - ClusterRole/Binding renamed `kubernetes-mcp-view` → `kubernetes-mcp`
     (no longer view-only; name must not mislead auditors).
   - Explicitly NOT granted (documented): secrets get, pods/exec,
     pods/portforward, pods create (`pods_run`), workload create/delete,
     argoproj.io writes, helm toolset (server default toolsets only).
   - Agent-facing documentation lives in
     `skills/helm-chart-creation/references/mcp-servers.md` (new section) +
     the RBAC template header comment.

## Changes — Phase 1 (single PR, single commit)

Order matters only within the commit: everything lands together.

1. `charts/base/values.yaml` — [MODIFY] replace the empty `charts:` (line ~33)
   with:

   ```yaml
   charts:
     # MCP platform for every cluster (ToolHive operator + MCP servers).
     # Default server: kubernetes (see charts/hivetools). Services extend via
     # their own values under `hivetools:` and can add `charts:` entries.
     hivetools:
       namespace: default
       ServerSideApply: "true"
   ```

2. `charts/base/templates/appset-charts.yaml` — [MODIFY] the list element's
   `values:` line (~line 29). Replace:

   ```yaml
   values: {{ merge (dict "shared-storage" (index $.Values "shared-storage")) (index $.Values $appName)  | toJson }}
   ```

   with:

   ```yaml
   {{- $extraValues := dict "shared-storage" (index $.Values "shared-storage") }}
   {{- if hasKey $.Values "subDomain" }}
   {{- $_ := set $extraValues "subDomain" (index $.Values "subDomain") }}
   {{- end }}
                 values: {{ merge $extraValues (index $.Values $appName) | toJson }}
   ```

   (keep the existing indentation of the `values:` key inside the `- ` element).

3. `charts/hivetools/templates/generic-mcp-ingress.yaml` — [MODIFY] host +
   cert. Compute the cluster host segment once and use it for both TLS host
   and rule host; switch secretName:

   ```yaml
   {{- $hostBase := .Values.clusterName }}
   {{- if hasKey .Values "subDomain" }}
   {{- $hostBase = .Values.subDomain }}
   {{- end }}
   ...
     tls:
       - hosts:
           - "mcp.{{ $hostBase }}.{{ .Values.domain }}"
         secretName: cluster-wildcard-cert
     rules:
       - host: "mcp.{{ $hostBase }}.{{ .Values.domain }}"
   ```

   Everything else (annotations, middleware ref, path routing) unchanged.

4. `charts/hivetools/values.yaml` — [MODIFY] trim to the generic platform:
   - `bitwardenIds:` → keep ONLY `mcp-sso: OVERRIDE_VIA_CUSTOM_VALUES`; delete
     the other 9 keys (github-mcp, homeassistant-mcp, grafana-mcp-token,
     mcp-pg-coder/flowise/langflow/n8n/open-webui, wekan-mcp).
   - `postgresMcp:` → keep the shared block (image pin `crystaldba/postgres-mcp:0.3.0`,
     transport, mcpPort, args, resources, podTemplateSpec) and set
     `databases: []`.
   - `mcp:` → keep ONLY the `kubernetes` entry; delete playwright, git,
     github, homeassistant, fetch, filesystem, sequential-thinking, searxng,
     wekan, grafana, renovate, firecrawl. On the kubernetes entry:
     - `args:` → REMOVE `"--read-only"` (keep `--port 8080 --stateless`).
     - Rewrite the comment block: no longer read-only; access model =
       read + restart, NO secrets access (post-review: list/watch also expose
       contents), no exec, no ArgoCD writes — see
       `templates/rbac-kubernetes-mcp.yaml` and the mcp-servers skill
       reference.
   - Keep: `namespace`, `domain`, `keycloak` (realm sentinel + clientId mcp),
     `toolhive-operator-crds`/`toolhive-operator` blocks. (The `shared-storage`
     default was dropped post-review: its only consumer moved to the gpu
     umbrella, leaving it dead.)
   - Update the file-header comments: hivetools is deployed on every cluster
     via base's `charts:` list; default server kubernetes; services add
     servers under their own `hivetools:` values key.

5. `charts/hivetools/templates/` — [DELETE → MOVE] these 5 files move to
   `services/gpu/prod/templates/` (use `git mv`, content unchanged —
   `.Values.bitwardenIds.*` resolves identically in the umbrella chart):
   `secret-github-mcp.yaml`, `secret-grafana-mcp-token.yaml`,
   `secret-homeassistant-mcp.yaml`, `secret-wekan-mcp.yaml`,
   `pvc-knowledge-default.yaml`.

6. `charts/hivetools/templates/rbac-kubernetes-mcp.yaml` — [MODIFY] rename +
   extend (RBAC is additive — append new rule entries, keep all existing
   read rules):
   - Rename ClusterRole AND ClusterRoleBinding `kubernetes-mcp-view` →
     `kubernetes-mcp` (binding's `roleRef.name` updated with it). Keep the
     `{{- if ne (.Values.mcp.kubernetes.enabled | toString) "false" }}` gate.
   - Rewrite the header comment: this is the access model for the kubernetes
     MCP server (read + restart; secrets names-only; no exec; no ArgoCD
     writes) — documented fully in
     `skills/helm-chart-creation/references/mcp-servers.md`.
   - Add rules:

   ```yaml
     # --- Secrets: names only. No get — contents stay private. ---
     - apiGroups: [""]
       resources: [secrets]
       verbs: ["list", "watch"]
     # --- Node observability (nodes_top/nodes_log/nodes_stats_summary) ---
     - apiGroups: [""]
       resources: [nodes]
       verbs: ["get", "list", "watch"]
     - apiGroups: [""]
       resources: [nodes/proxy]
       verbs: ["get"]
     # --- Storage read (PVC debugging: local-path, seaweedfs) ---
     - apiGroups: [""]
       resources: [persistentvolumes]
       verbs: ["get", "list", "watch"]
     - apiGroups: ["storage.k8s.io"]
       resources: [storageclasses]
       verbs: ["get", "list", "watch"]
     # --- Restart by pod delete (+ PDB-safe eviction) ---
     - apiGroups: [""]
       resources: [pods]
       verbs: ["delete"]            # get/list/watch already granted above
     - apiGroups: [""]
       resources: [pods/eviction]
       verbs: ["create"]
     # --- Rollout restart/undo: patch pod template (incl. SSA) ---
     - apiGroups: ["apps"]
       resources: [deployments, statefulsets, daemonsets, replicasets]
       verbs: ["patch", "update"]   # get/list/watch already granted
     - apiGroups: [""]
       resources: [replicationcontrollers]
       verbs: ["patch", "update"]
     # --- resources_scale tool ---
     - apiGroups: ["apps"]
       resources: [deployments/scale, statefulsets/scale, replicasets/scale]
       verbs: ["get", "patch", "update"]
     - apiGroups: [""]
       resources: [replicationcontrollers/scale]
       verbs: ["get", "patch", "update"]
   ```

   - Do NOT add: secrets get, pods/exec, pods create, workload create/delete,
     argoproj.io update/patch (see Design decision 8).

7. `services/gpu/prod/values.yaml` — [MODIFY]
   - `charts:` → KEEP the existing `hivetools:` entry but add a comment:
     `# Transitional duplicate of base's charts.hivetools; remove once every
     cluster's baseChartVersion includes it (Phase 2).` (Prevents a gpu MCP
     outage during the renovate bump window — see Design decision 6.)
   - Top-level `bitwardenIds:` → add sentinels consumed by the moved
     ExternalSecret templates:

     ```yaml
       github-mcp: OVERRIDE_VIA_CUSTOM_VALUES
       homeassistant-mcp: OVERRIDE_VIA_CUSTOM_VALUES
       grafana-mcp-token: OVERRIDE_VIA_CUSTOM_VALUES
       wekan-mcp: OVERRIDE_VIA_CUSTOM_VALUES
     ```

   - Add a new top-level `hivetools:` block (flows to the hivetools Application
     via the charts-appset values slice). Move 6 server definitions VERBATIM
     from `charts/hivetools/values.yaml` under `mcp:` — playwright,
     homeassistant, searxng, wekan, grafana, renovate — and move the 5
     `postgresMcp.databases` entries verbatim. (Post-review decision: git,
     github, fetch, filesystem, sequential-thinking and firecrawl were dropped
     entirely instead of moved; the github-mcp ExternalSecret stays because
     renovate's repo-clone initContainer consumes it.):

      ```yaml
      hivetools:
        # gpu-specific MCP servers + Postgres DBs on top of base's defaults
        # (kubernetes server ships from charts/hivetools/values.yaml).
        mcp:
          # The 12 entries below moved VERBATIM from charts/hivetools/values.yaml
          # (full definitions live in services/gpu/prod/values.yaml; wekan shown
          # as a representative example of the shape):
          wekan:
            enabled: true
            image: ghcr.io/ownyourio/wekan-mcp:0.0.2
            transport: streamable-http
            mcpPort: 8080
            oidc:
              audience: wekan
            env:
              - name: WEKAN_BASE_URL
                value: "https://wekan.spencerslab.com"
            secrets:
              - name: wekan-mcp
                key: WEKAN_TOKEN
                targetEnvName: WEKAN_TOKEN
            resources:
              limits:
                cpu: '200m'
                memory: '256Mi'
              requests:
                cpu: '50m'
                memory: '64Mi'
            podTemplateSpec:
              spec:
                containers:
                  - name: mcp
                    securityContext:
                      runAsUser: 65532
                      runAsGroup: 65532
                      runAsNonRoot: true
                      allowPrivilegeEscalation: false
                      capabilities:
                        drop:
                          - ALL
          # ... plus, each verbatim: homeassistant, searxng, grafana, renovate
        postgresMcp:
         databases:
           - name: coder
             bitwardenIdKey: mcp-pg-coder
             database: coder
           - name: flowise
             bitwardenIdKey: mcp-pg-flowise
             database: flowise
           - name: langflow
             bitwardenIdKey: mcp-pg-langflow
             database: langflow
           - name: n8n
             bitwardenIdKey: mcp-pg-n8n
             database: n8n
           - name: open-webui
             bitwardenIdKey: mcp-pg-open-webui
             database: open-webui
     ```

8. `services/gpu/prod/templates/` — [CREATE, via git mv from step 5] the 5
   moved files. No content changes.

9. `custom-values/gpu/prod-values.yaml` — [MODIFY]
   - Top-level `bitwardenIds:` → add the 4 UUIDs now consumed by the umbrella
     templates (values already present under `hivetools:`):
     `github-mcp: f4938da9-3260-42c7-9787-b38100023fc3`,
     `homeassistant-mcp: 84d06d73-da27-4066-9da1-b498002d69b5`,
     `grafana-mcp-token: 7e393c36-5b11-4806-a05f-b4bd00e613f5`,
     `wekan-mcp: e6761f4a-9813-4073-b539-b4bd002bc4b1`.
   - `hivetools.bitwardenIds:` → remove those same 4 keys (now dead); keep
     `mcp-sso` + the 5 `mcp-pg-*`. Keep `keycloak.realm`.

10. `custom-values/{grow,home,infra,media,monitoring,proxy-local,proxy-remote}/prod-values.yaml`
    — [MODIFY] append to each (same UUID/realm as gpu — shared Keycloak client):

    ```yaml
    hivetools:
      bitwardenIds:
        mcp-sso: 2c3ac9dd-636a-4c3e-ba1e-b498002ed133
      keycloak:
        realm: SpencersLab
    ```

    (All `dev-values.yaml` files are empty — leave them.)

11. Docs/skills kept current (AGENTS.md requirement):
    - `skills/helm-chart-creation/references/mcp-servers.md` —
      (a) rewrite for the new architecture: hivetools deployed on every
      cluster via base's `charts:` list; default server kubernetes; ingress
      host `mcp.<subDomain|clusterName>.<domain>`; service-specific servers
      live in `services/<svc>/prod/values.yaml` under `hivetools:` with their
      secrets in `services/<svc>/prod/templates/`; "What is NOT needed"
      section updated (hivetools wiring is now in base, not gpu).
      (b) NEW section **"Kubernetes MCP server: access model (RBAC)"** — the
      agent-facing documentation of the privilege list:
        * Read tier: view-equivalent get/list/watch + secrets **list/watch
          only (no get)** + nodes/nodes-proxy + PVs + storageclasses.
        * Restart tier: pods delete (+ eviction create); patch/update on
          deployments/statefulsets/daemonsets/replicasets/replicationcontrollers;
          scale subresources.
        * Denied tier (explicit): secrets get, pods/exec, pods create
          (pods_run), workload create/delete, argoproj.io writes, helm
          toolset. Note: `pods_exec`/`pods_run` etc. still APPEAR in the MCP
          tool list (server has no per-verb tool gating) but 403 — RBAC is
          the boundary.
        * GitOps mechanics: prefer restart-by-pod-delete (controllers recreate
          pods; no git drift). `rollout restart`-style workload patches add a
          pod-template annotation that ArgoCD selfHeal sees as drift and
          reverts → expect a second roll when it does; not harmful, but
          document it.
        * ArgoCD syncs cannot be triggered via the k8s API (needs ArgoCD's
          own API/token) — deliberately out of scope, revisit later.
    - `skills/helm-chart-creation/references/storage-and-secrets.md` (~L172) —
      knowledge worked example: `pvc-knowledge-default.yaml` path →
      `services/gpu/prod/templates/`.
    - `skills/wekan-api/SKILL.md` (L26) — URL → `https://mcp.gpu.spencerslab.com/wekan/mcp`.
    - `containers/wekan-mcp/README.md` — secret template path →
      `services/gpu/prod/templates/secret-wekan-mcp.yaml`; ingress note →
      `mcp.<cluster>.<domain>`.
    - `skills/helm-chart-creation/SKILL.md` (L30/L75) — note hivetools is
      cluster-wide via base's `charts:` list.

## Changes — Phase 2 (separate follow-up PR, AFTER merge + release + renovate)

Wait until: CI publishes the new base version, the renovate PR bumping
`baseChartVersion` in all 8 `services/*/prod/templates/appset.yaml` files is
merged, and every cluster's `<svc>-hivetools` Application exists and is
Healthy. Then:

1. `services/gpu/prod/values.yaml` — [MODIFY] delete the transitional
   `charts: hivetools:` entry (base provides it). Verify `gpu-hivetools`
   remains Synced (same ApplicationSet element, now sourced from base values).

## Verification

Pre-merge (hard rules):

1. `helm lint charts/base charts/hivetools`
2. `helm template charts/hivetools --set domain=test.example.com --set clusterName=testcluster --set bitwardenIds.mcp-sso=test-uuid --set keycloak.realm=test`
   → exactly ONE MCPServer (`kubernetes`) whose args contain `--stateless`
   but NOT `--read-only`; ClusterRole named `kubernetes-mcp` with the new
   rules (secrets list/watch; pods delete; pods/eviction create; workload
   patch/update; scale subresources; nodes+proxy; PVs; storageclasses) and
   NO secrets-get/exec/workload-create rules; ingress host
   `mcp.testcluster.test.example.com` with `secretName: cluster-wildcard-cert`
   and one route `/kubernetes`; no gpu-only servers; no OVERRIDE_ sentinels.
3. Same command + `--set subDomain=test-lab` → host
   `mcp.test-lab.test.example.com`.
4. Extract the new `hivetools:` block from `services/gpu/prod/values.yaml` to
   a temp file and render
   `helm template charts/hivetools -f <temp> --set domain=… --set clusterName=gpu --set keycloak.realm=SpencersLab`
   → 7 MCServers (6 gpu + kubernetes) + 5 `postgres-*` servers + matching
   ingress routes.
5. `helm template charts/base --set serviceName=test --set clusterName=testcluster --set domain=test.example.com`
   → `test-charts-appset` list includes a `hivetools` element
   (`ServerSideApply: "true"`); with `--set subDomain=test-lab` the element's
   `values` JSON contains `"subDomain":"test-lab"`.
6. `helm lint services/gpu/prod` + `helm template services/gpu/prod` (with
   dummy values for required keys) → the 5 moved templates render
   (ExternalSecrets with `index .Values "bitwardenIds" …`, knowledge PVC gated
   off by `shared-storage.knowledge`).
7. Greps: no `playwright|wekan|grafana|renovate|searxng` server definitions
   left in `charts/hivetools/values.yaml`; no `read-only` left in
   `charts/hivetools/`; `charts/base/values.yaml` contains `charts: hivetools:`;
   all 7 non-gpu custom-values files contain the `mcp-sso` UUID.

Post-merge (rollout watch):

1. CI releases new base chart; renovate PR bumps all 8 `baseChartVersion`
   pins; merge it.
2. gpu: `gpu-hivetools` stays Synced/Healthy throughout (transitional entry);
   ingress host flips to `mcp.gpu.spencerslab.com` immediately on merge —
   update MCP client configs (Kilo etc.) accordingly.
3. RBAC live checks on gpu (as the SA):
   `kubectl auth can-i list secrets --as=system:serviceaccount:default:kubernetes-mcp` → yes;
   `get secrets` → **no**; `delete pods` → yes; `create pods/exec` → **no**;
   `patch deployments.apps` → yes; `update applications.argoproj.io` → **no**;
   `get nodes` → yes. Old ClusterRole `kubernetes-mcp-view` is gone.
4. Optional user-chosen smoke test: delete one expendable pod (controller
   recreates it) and/or `resources_scale` round-trip on a non-critical
   deployment through the MCP endpoint.
5. Other clusters: `<svc>-hivetools` Applications appear, ToolHive operator
   pods start, `mcp-sso` ExternalSecret readies, `kubernetes` MCPServer pod +
   proxy run, ingress at `mcp.<cluster>.<domain>` (home: `mcp.home-lab.…`).
6. Smoke test: `tools/list` through
   `https://mcp.<cluster>.<domain>/kubernetes/mcp` with a Keycloak token for
   client `mcp`, audience `kubernetes`.
7. Then execute Phase 2.

## Risks & open questions

- **DNS prerequisite (out of repo):** `*.<clusterName>.<domain>` (and
  `*.home-lab.<domain>`) must resolve to each cluster's proxy/traefik. gpu
  already works this way for `cluster.gpu.…`; verify per cluster during
  rollout.
- **Breaking URL change on gpu:** `mcp.spencerslab.com` →
  `mcp.gpu.spencerslab.com` at merge time (ingress change is not gated by the
  base version bump). All MCP clients need reconfiguring then.
- **home host naming:** renders `mcp.home-lab.<domain>` (not `mcp.home.…`)
  because the cluster-wildcard-cert covers `*.<subDomain>` — repo convention,
  flagged here for awareness.
- **ExternalSecret ownership flip on gpu:** the 4 moved ExternalSecrets change
  owning Application (hivetools → gpu umbrella) at merge. `grafana-mcp-token`
  has `deletionPolicy: Delete`, so a prune-before-create ordering could
  briefly delete its target Secret (self-heals on next sync). If desired,
  force-sync the `gpu` umbrella app before `gpu-hivetools`.
- **Elevated RBAC ships to every cluster** (base → hivetools → kubernetes
  server), gated by Keycloak OIDC audience `kubernetes`. Secret NAMES +
  metadata (labels/annotations/type) become visible to audience-token holders
  cluster-wide — accepted trade-off (user decision).
- **Tool list vs permissions:** the server exposes `pods_exec`, `pods_run`,
  `resources_delete`, etc. in its tool list even when RBAC denies them (no
  per-verb tool gating upstream). RBAC is the enforcement boundary; documented
  in the skill reference.
- **Rollout-restart drift:** workload patch (restartedAt annotation) is drift
  vs git; ArgoCD selfHeal reverts it → second rolling update. Prefer
  restart-by-pod-delete (documented).
- **ToolHive operator footprint** on small clusters (e.g. proxy VPS) — watch
  memory after rollout.
- **Renovate lag:** other clusters get MCP only after the `baseChartVersion`
  bump merges (expected, phased rollout; gpu is protected by the transitional
  entry).
- **ArgoCD sync triggering remains impossible** via this server (read-only on
  argoproj.io + ArgoCD API needs its own token) — revisit as a separate
  concern if wanted later.
