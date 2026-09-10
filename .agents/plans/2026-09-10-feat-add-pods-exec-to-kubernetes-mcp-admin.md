# 2026-09-10 feat — Grant pods/exec to the kubernetes-mcp-admin tier

Status: implemented (retrospective plan — no plan file preceded this change).

## Goal

The `<cluster>-admin-kubernetes` MCP servers (one per cluster, backed by the
`kubernetes-mcp-admin` ServiceAccount in `charts/hivetools`) could restart,
scale, and patch workloads but not exec into pods — the `pods_exec` tool
403'd. Grant `pods/exec` to the admin tier only; the readonly tier stays
exec-free.

## Skills / MCP servers

- Skills: `executing-plans`, `kubernetes-skill` (loaded); chart conventions per
  `skills/helm-chart-creation/references/mcp-servers.md` (RBAC access model
  section is the canonical doc for these tiers).
- MCP servers: none needed (pure repo change, validated locally).

## Changes

1. `charts/hivetools/templates/rbac-kubernetes-mcp.yaml`
   - Added to the `kubernetes-mcp-admin` ClusterRole (after the scale rules):

     ```yaml
     # --- Pod exec (pods_exec tool) ---
     - apiGroups: [""]
       resources: [pods/exec]
       verbs: ["create"]
     ```

     `create` is the only verb needed — exec is a POST to the pod's `exec`
     subresource (kubectl/client-go and the MCP server's SPDY/WebSocket
     upgrade both use POST).
   - Header comment updated: admin tier description now includes exec;
     `pods/exec` removed from the all-tiers "Explicitly NOT granted" list and
     re-stated as denied on the readonly tier only.
2. `charts/hivetools/values.yaml` — tier comments updated
   ("read + restart/rollout + pod exec tier"; "Exec: admin tier only").
3. `skills/helm-chart-creation/references/mcp-servers.md` — RBAC access model
   updated: admin table row, new restart-tier bullet for `pods/exec` create
   (admin only, added 2026-09-10), `pods/exec` removed from the denied list
   (still denied on readonly), and the tools/list note no longer cites
   `pods_exec` as a 403 example.
4. `AGENTS.md` + `.agents/agents/code.md` — admin-tier privilege description
   changed from "restart/scale/patch/delete" to
   "restart/scale/patch/delete/exec".

Not touched: historical plan files under `.agents/plans/` (records of past
decisions), Chart.yaml version (CI bumps on merge).

## Validation

- `helm lint charts/hivetools` — pass (pre-existing icon INFO + dependency
  WARNING only; deps fetched with `helm dependency build`, dir is gitignored).
- `helm template hivetools charts/hivetools --set domain=test.example.com
  --set clusterName=testcluster --set bitwardenIds.mcp-sso=test-uuid
  --set keycloak.realm=test` — full render passes (32 resources);
  `pods/exec` appears exactly once, in the `kubernetes-mcp-admin` ClusterRole;
  `kubernetes-mcp-readonly` has no exec rule.

## Rollout

ArgoCD syncs `hivetools` on every cluster after merge — the ClusterRole
update is additive and non-disruptive; no pod restarts required. After sync,
`pods_exec` through any `<cluster>-admin-kubernetes` server works; the
readonly servers still 403 it.
