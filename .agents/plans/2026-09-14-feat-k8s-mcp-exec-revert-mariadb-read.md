# 2026-09-14 feat — Revert k8s MCP exec grant; add k8s.mariadb.com read access

Status: implemented (retrospective plan — no plan file preceded this change).

## Goal

Two RBAC tweaks to the kubernetes MCP tiers (`charts/hivetools`):

1. **Revert the 2026-09-10 `pods/exec` grant** on `kubernetes-mcp-admin` —
   the user decided exec is too much privilege for the agent tiers. Instead,
   the agent context files now instruct agents to present the exact command
   to the user when something needs to run inside a pod.
2. **Add read access for mariadb-operator CRDs** — the community
   mariadb-operator (26.6.0) landed on the grow cluster
   (`2026-09-14-feat-add-mariadb-operator-grow.md`) but the kubernetes MCP
   read tier had no rules for its API group. Verified live on grow: all 12
   `k8s.mariadb.com` resources returned `forbidden` for
   `system:serviceaccount:default:kubernetes-mcp-readonly`.

## Skills / MCP servers

- Skills: `executing-plans`, `kubernetes-skill`.
- MCP servers: `readonly-grow-kubernetes` (confirmed the 403s and the running
  operator pod `grow-mariadb-operator-*`). No admin servers used.

## Verified context

- Upstream chart `oci://ghcr.io/mariadb-operator/charts/mariadb-operator:26.6.0`
  pulled and inspected: the vendored `mariadb-operator-crds` subchart ships
  exactly **12 CRDs**, all in group `k8s.mariadb.com`:
  `backups, connections, databases, externalmariadbs, grants, mariadbs,
  maxscales, physicalbackups, pointintimerecoveries, restores, sqljobs, users`.
- grow cluster: operator pod Running in `default`; every CRD API live
  (RBAC 403, not 404 — the APIs exist, the read tier just couldn't see them).

## Changes

1. `charts/hivetools/templates/rbac-kubernetes-mcp.yaml`
   - Removed the `pods/exec: create` rule from `kubernetes-mcp-admin`
     (restores the pre-2026-09-10 state, header comment restored too).
   - Added to the shared read-tier `define` (both tiers, every cluster),
     after the CloudNativePG block:

     ```yaml
     # MariaDB Operator (community, grow cluster)
     - apiGroups: ["k8s.mariadb.com"]
       resources: [backups, connections, databases, externalmariadbs,
                   grants, mariadbs, maxscales, physicalbackups,
                   pointintimerecoveries, restores, sqljobs, users]
       verbs: ["get", "list", "watch"]
     ```

     Granting read on an API group that doesn't exist on other clusters is
     harmless (rules for absent APIs never match).
2. `charts/hivetools/values.yaml` — tier comment restored
   ("Both: no secrets access, no exec.").
3. `skills/helm-chart-creation/references/mcp-servers.md` — exec restored to
   the denied tier, `pods_exec` restored as a tools/list 403 example, admin
   table row restored, `k8s.mariadb.com` added to the lab-CRD list.
4. `AGENTS.md` + `.agents/agents/code.md` — admin priv description back to
   "restart/scale/patch/delete" plus new guidance: **no tier grants pod
   exec — present the exact `kubectl exec -n <ns> <pod> -- <cmd>` to the
   user and let them run it.** `plan.md` unchanged (read-only agents never
   mutate).
5. Supersede note added to
   `.agents/plans/2026-09-10-feat-add-pods-exec-to-kubernetes-mcp-admin.md`.

## Validation

- `helm lint charts/hivetools` — pass (icon INFO only).
- `helm template` full render — pass; `pods/exec` appears **0** times;
  `k8s.mariadb.com` appears exactly **2** times (once per ClusterRole via the
  shared read define), each with all 12 resources and get/list/watch.

## Rollout

ArgoCD syncs `hivetools` per cluster after merge — additive for the mariadb
read rules, subtractive for exec (immediate 403s for any exec attempt on the
admin servers, which is the intent). Post-sync check on grow: listing
`k8s.mariadb.com/v1alpha1 MariaDB` through `grow-readonly-kubernetes` should
succeed.
