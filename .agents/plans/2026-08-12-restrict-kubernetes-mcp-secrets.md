# Restrict kubernetes-mcp RBAC: deny Secrets read

## Goal
`charts/hivetools/templates/rbac-kubernetes-mcp.yaml` binds the `kubernetes-mcp` ServiceAccount to the built-in `view` ClusterRole, which includes `get/list/watch` on `secrets`. Restrict it so Secrets are not readable, while keeping everything else `view` grants (including ConfigMaps — user decision).

## Context / Decision
- Kubernetes RBAC is additive-only: you cannot subtract rules from the built-in `view` role. The fix is a chart-defined ClusterRole replicating `view` minus the secrets rule, and binding to it instead.
- ConfigMaps remain readable per user choice.
- No values.yaml changes (hard-coded restriction). Optionally update the comment in `values.yaml` (line ~221) that references the built-in `view` ClusterRole.

## Changes (single file: `charts/hivetools/templates/rbac-kubernetes-mcp.yaml`)
1. Add a chart-defined `ClusterRole` named `kubernetes-mcp-view` (between the ServiceAccount and the ClusterRoleBinding) with the upstream `view` rules, omitting the secrets rule. Rule set (mirrors upstream `view` minus secrets, keeps configmaps):
   - `""` (core): configmaps, endpoints, persistentvolumeclaims, persistentvolumeclaims/status, pods, replicationcontrollers, replicationcontrollers/scale, serviceaccounts, services, services/status — verbs get/list/watch
   - `""`: bindings, events, limitranges, namespaces/status, pods/log, pods/status, replicationcontrollers/status, resourcequotas, resourcequotas/status — verbs get/list/watch
   - `""`: namespaces — verbs get/list/watch
   - `apps`: controllerrevisions, daemonsets, daemonsets/status, deployments, deployments/scale, deployments/status, replicasets, replicasets/scale, replicasets/status, statefulsets, statefulsets/scale, statefulsets/status — get/list/watch
   - `autoscaling`: horizontalpodautoscalers, horizontalpodautoscalers/status — get/list/watch
   - `batch`: cronjobs, cronjobs/status, jobs, jobs/status — get/list/watch
   - `extensions`: daemonsets, daemonsets/status, deployments, deployments/scale, deployments/status, ingresses, ingresses/status, networkpolicies, replicasets, replicasets/scale, replicasets/status, replicationcontrollers/scale — get/list/watch
   - `policy`: poddisruptionbudgets, poddisruptionbudgets/status — get/list/watch
   - `networking.k8s.io`: ingresses, ingresses/status, networkpolicies — get/list/watch
   - `authorization.k8s.io`: localsubjectaccessreviews — create (selfsubjectaccessreviews portion of view)
   - `rbac.authorization.k8s.io`: clusterrolebindings, clusterroles, rolebindings, roles — get/list/watch
   - `metrics.k8s.io`: nodes, pods — get/list/watch
   (Use `helm template` output of the upstream `view` role on the target cluster as reference if unsure: `kubectl get clusterrole view -o yaml`.)
2. Change the ClusterRoleBinding `roleRef.name` from `view` to `kubernetes-mcp-view`.

## Also update
- `charts/hivetools/values.yaml` comment at ~line 221: change "(bound to the built-in 'view' ClusterRole...)" to reference the custom `kubernetes-mcp-view` ClusterRole without secrets access.

## Validation
1. `helm template charts/hivetools` renders without errors and shows the new ClusterRole + updated binding.
2. If a cluster is available: `kubectl auth can-i list secrets --as=system:serviceaccount:<ns>:kubernetes-mcp` → `no`; `kubectl auth can-i list configmaps --as=...` → `yes`; `kubectl auth can-i list pods --as=...` → `yes`.
3. Confirm the kubernetes-mcp-server pod still starts and serves read-only queries (pods/logs/etc.).

## Out of scope
- ConfigMap restriction (user opted to keep).
- Configurable values toggle (not requested).
