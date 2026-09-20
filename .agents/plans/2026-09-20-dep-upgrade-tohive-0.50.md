# ToolHive 0.34.0 → 0.50.0 operator upgrade

**Date**: 2026-09-20 · **Type**: dep · **Status**: implemented, pending merge

## Why

The argocd-mcp server on media (see `2026-09-20-feat-add-argocd-mcp-media.md`)
exposed a defect in ToolHive 0.34.0's Kubernetes stdio path: MCP messages
above a modest size are silently dropped between backend and proxy.

Empirical evidence (media, 2026-09-20):

- Backend registered 52 generated tools and answered tools/list with a single
  valid 31,384-byte JSON-RPC line (verified in the backend pod's stdio wire
  dump).
- Clients received an **empty body** for that tools/list; small messages
  (initialize ~300 B, small tool calls) passed fine; large tool responses
  (argocd_application_list) were also swallowed.
- Proxy log shows `error parsing JSON-RPC message` entries around each
  failure (`invalid message version tag`, `cannot unmarshal string into
  wireCombined.error`) — the attach/parse path breaks the message up.

Upstream `main` reads stdio via unbounded `bytes.Buffer` +
`ReadString('\n')` (no fixed token cap); 0.50.0 (2026-09-18) is 16 minors
ahead with many transport/session fixes, so the upgrade is the fix path
chosen (over a standalone non-ToolHive deployment of argocd-mcp).

## Changes

- `charts/hivetools/Chart.yaml` + `Chart.lock`: `toolhive-operator-crds` and
  `toolhive-operator` dependencies `0.34.0 → 0.50.0`
  (`oci://ghcr.io/stacklok/toolhive`).

## Compatibility verification (pre-merge)

- Values schema: 0.34.0 vs 0.50.0 operator chart values are structurally
  identical (only addition: `operator.imageDiscovery`). The subchart values
  hivetools passes (`operator.replicaCount`, `operator.rbac.scope`) are
  valid in both. (Note: hivetools' top-level `toolhive-operator.podAnnotations`
  sync-wave was already inert in 0.34.0 — the key lives under `operator.`;
  left as-is to avoid changing sync ordering during an upgrade.)
- CRDs: v1beta1 remains the storage version; MCPServer fields in use
  (authzConfig.inline, toolConfigRef, oidcConfigRef, secrets,
  podTemplateSpec, mcpPort/proxyPort, sessionAffinity, trustProxyHeaders),
  MCPToolConfig.toolsFilter, and MCPOIDCConfig.kubernetesServiceAccount all
  present in the 0.50.0 CRDs.
- Renders: `helm lint` clean; full `helm template` with media values renders
  operator `ghcr.io/stacklok/toolhive/operator:v0.50.0`, 14 CRDs, and all 3
  media MCPServers; chart-default (no-media) render unchanged
  (kubernetes-readonly/admin, ingress ports 8080).

## Rollout / blast radius

hivetools ships cluster-wide via base's `charts:` list, so every cluster's
hivetools Application picks this up on its next sync. The operator reconciles
all existing MCServers (gpu has the most: ~17). Watch after merge:

1. `toolhive-operator` Deployment rolls to v0.50.0 (check pod Ready).
2. Existing MCPServers stay Ready; their proxy/backends are not recreated
   unexpectedly (some churn is possible on reconcile).
3. media: `mcp-argocd` tools/list returns the 13 allowlisted tools; large
   responses (argocd_application_list) now pass.
4. gpu spot-check: kubernetes-readonly tools/list + one read call.

## Rollback

Revert the Chart.yaml/Chart.lock bump (0.50.0 → 0.34.0), merge, re-sync.
CRDs are additive-compatible in both directions for the fields in use.
