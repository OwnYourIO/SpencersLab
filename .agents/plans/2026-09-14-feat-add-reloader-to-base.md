# Plan: Add Stakater Reloader to base (all clusters)

## Goal

Stop restarting workloads by hand: deploy Stakater Reloader on **every
cluster** via the `charts/base` cluster-wide `charts:` map (the hivetools
pattern). ~30 charts already carry `reloader.stakater.com/auto: "true"`
controller annotations — today they are a verified no-op because no Reloader
is deployed anywhere (checked gpu: no pods, no Deployment, no ClusterRoles).
Once this lands, referenced ConfigMap/Secret changes (incl. ExternalSecrets
rotations) trigger automatic rolling restarts.

## Skills

Code agent must load (fresh session):

- `helm-chart-creation` — repo wiring rules; read its
  `references/values-and-appset.md` "Cluster-wide charts" section.
- `gitops-workflows` — ArgoCD ApplicationSet/diffing context.

## MCP Servers

- `readonly-gpu-kubernetes` — optional post-merge verification only.
- No `admin-*` server needed: ArgoCD applies everything; no manual cluster
  mutations.

## Verified context

Recon (all paths verified against the repo):

- `charts/base/values.yaml` — `charts:` map currently holds only `hivetools`
  (the live cluster-wide-chart example); `argo-cd.configs.cm` already carries
  `resource.customizations.ignoreDifferences` for `apps_Deployment` and
  `apps_StatefulSet` (incl. the exact same trick for the pod-template
  annotation `date/deploy-date`).
- `charts/base/templates/appset-charts.yaml` — renders
  `<serviceName>-charts-appset`; entries with `version:` + `repository:`
  become external-chart Applications; per-app values ride
  `merge $extraValues (index $.Values $appName) | toJson` (line 33), so a
  top-level `reloader:` key in base values becomes the chart values;
  `RespectIgnoreDifferences=true` is already a syncOption (line 139).
- All 8 service appsets pin `baseChartVersion: 1.0.193`; renovate.json has a
  dedicated regex manager bumping it, plus a "Update Charts - key as chart
  name" regex manager that manages `reloader:` / `version:` / `repository:`
  triples in values.yaml files (NO inline renovate comment needed — but the
  three lines must stay adjacent, key first).
- No `reloader` charts entry or top-level `reloader:` key exists in any
  `services/*/prod/values.yaml` (grep-verified) → no transitional-duplicate
  concern; nothing was ever deployed, so nothing to keep.
- Stakater chart repo `https://stakater.github.io/stakater-charts`: latest
  `reloader` chart **2.2.17** (appVersion v1.4.22, published 2026-09-09),
  image pinned in-chart to `ghcr.io/stakater/reloader:v1.4.22`. Chart ships a
  permissive-root `values.schema.json` — the appset's injected helm
  parameters (domain/clusterName/serviceName/appName/namespace) pass
  validation (render-tested).
- Stakater docs ("Use Reloader with Argo CD"): with ArgoCD + selfHeal, use
  `--reload-strategy=annotations` and ignore the pod-template annotation
  `reloader.stakater.com/last-reloaded-from` in diffs. The default
  `env-vars` strategy mutates container specs → ArgoCD selfHeal would revert
  it and cause a second rollout per config change.

Render checks performed (in /tmp harnesses, full YAML available):

- Full base chart render (`helm dependency build` + `helm template
  --set serviceName=gpu --set domain=spencerslab.com --set clusterName=gpu`):
  96 manifests, no errors; `gpu-charts-appset` gains a correct `reloader`
  element; `argocd-cm` carries all three ignoreDifferences customizations.
- External chart render with the exact values slice + injected parameters:
  ServiceAccount, ClusterRole(+Binding), Role(+Binding), Deployment
  `gpu-reloader-reloader` with `--reload-strategy=annotations`,
  runAsNonRoot 65534 + RuntimeDefault, drop-ALL + readOnlyRootFilesystem
  with /tmp emptyDir, resources applied.

## Design decisions

1. **External chart entry in base's `charts:` map** (not a custom/wrapper
   chart): official maintained chart exists; Reloader needs no secrets, PVCs
   or repo-side templates → the documented "values-only external chart" case,
   same as `cloudnative-pg` in grow. Cluster-wide via base (hivetools
   pattern) because the user asked for "the base" and every service already
   renders base's charts-appset.
2. **Namespace `default`**: repo convention — every `charts:` entry (incl.
   hivetools) uses `default`; Reloader watches all namespaces regardless
   (`watchGlobally: true` default) and its RBAC is cluster-scoped.
3. **`reloadStrategy: annotations`** + ArgoCD `ignoreDifferences` for
   `reloader.stakater.com/last-reloaded-from` on Deployment/StatefulSet/
   DaemonSet: one clean rollout per config change, no selfHeal fight, apps
   stay Synced. Implemented via argocd-cm global resource customizations in
   base values (existing mechanism in this chart) — no appset template
   changes, covers all Applications on all clusters.
4. **Keep annotation-driven opt-in** (`autoReloadAll` stays false): only the
   ~30 already-annotated workloads restart; CNPG clusters, ArgoCD itself and
   unannotated workloads are untouched.
5. **Hardening + resources** per repo standards: drop ALL caps,
   allowPrivilegeEscalation false, readOnlyRootFilesystem via the chart's
   `readOnlyRootFileSystem: true` (it adds the /tmp emptyDir correctly),
   requests 10m/128Mi, memory limit 256Mi (README defaults are
   10m/128Mi req, 150m/512Mi limit — ours is lighter; fine for homelab
   scale, tune from observation).
6. **No proxy entry, no custom-values entry**: no web UI, no secrets —
   documented exceptions for cluster-wide charts.

## Changes

Single file: `charts/base/values.yaml` — three edits. Do NOT touch
`charts/base/Chart.yaml` `version` (CI bumps it on merge).

### 1. Add the `reloader` entry to the `charts:` map (after `hivetools`)

```yaml
charts:
  # MCP platform for every cluster ... (existing hivetools comment + entry)
  hivetools:
    namespace: default
    ServerSideApply: "true"
  # Stakater Reloader on every cluster: rolling-restarts Deployments/
  # StatefulSets/DaemonSets when a referenced ConfigMap/Secret changes.
  # Charts already carry reloader.stakater.com/auto: "true". Renovate
  # manages the version via the "key as chart name" regex manager: keep
  # version: directly under the key and repository: on the next line.
  reloader:
    version: 2.2.17
    repository: https://stakater.github.io/stakater-charts
    namespace: default
    ServerSideApply: "true"
```

### 2. Add the top-level `reloader:` values block

Place it right after the `charts:` map (before `cert-manager:`). Outer key =
appName (values-slice key); inner `reloader:` = the stakater chart's own
top-level values key.

```yaml
# Values for the cluster-wide stakater/reloader chart (charts entry above) —
# rides the charts-appset values slice into every <serviceName>-reloader
# Application. annotations reload strategy restarts via a pod-template
# annotation excluded from ArgoCD diffs below, so selfHeal never fights it.
reloader:
  reloader:
    reloadStrategy: annotations
    readOnlyRootFileSystem: true
    deployment:
      resources:
        requests:
          cpu: 10m
          memory: 128Mi
        limits:
          memory: 256Mi
      containerSecurityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
```

### 3. Extend ArgoCD ignoreDifferences in `argo-cd.configs.cm`

In `resource.customizations.ignoreDifferences.apps_Deployment`, add after the
`.spec.template.spec.hostUsers` line:

```yaml
          - '.spec.template.metadata.annotations?["reloader.stakater.com/last-reloaded-from"]'
```

In `resource.customizations.ignoreDifferences.apps_StatefulSet`, add after
the `date/deploy-date` line (same expression).

Add a new key directly after the StatefulSet block (before `rbac:`):

```yaml
      resource.customizations.ignoreDifferences.apps_DaemonSet: |
        jqPathExpressions:
          - '.spec.template.metadata.annotations?["reloader.stakater.com/last-reloaded-from"]'
```

## Verification

Pre-merge (Code agent):

1. `helm dependency build charts/base` (fetches argo-cd + cert-manager into
   the gitignored `charts/base/charts/`).
2. `helm lint charts/base` — must pass. (The `-charts-appset` naming warning
   is pre-existing: lint runs without `--set serviceName`.)
3. `helm template test charts/base --set serviceName=gpu --set
   domain=spencerslab.com --set clusterName=gpu` and confirm:
   - `gpu-charts-appset` contains a `reloader` element with `version: 2.2.17`,
     `repository: https://stakater.github.io/stakater-charts`,
     `namespace: default`, and a `values` JSON containing
     `"reloadStrategy":"annotations"`;
   - `argocd-cm` data has the reloader annotation line in all three
     `ignoreDifferences` keys (Deployment, StatefulSet, DaemonSet);
   - no `OVERRIDE_*` sentinels anywhere in the output.
4. Render the external chart with the exact slice (proves schema + flags):
   extract the element's `values` JSON to a temp file, then
   `helm template gpu-reloader stakater/reloader --version 2.2.17 -f <slice>
   --set domain=spencerslab.com --set clusterName=gpu --set serviceName=gpu
   --set appName=reloader --set namespace=default` (after
   `helm repo add stakater https://stakater.github.io/stakater-charts`).
   Expect Deployment `gpu-reloader-reloader` with
   `--reload-strategy=annotations`, ClusterRole/Binding, drop-ALL +
   readOnlyRootFilesystem security contexts.

Post-merge (user; rollout is staged):

1. CI releases base 1.0.194 on merge to main; renovate opens a PR bumping
   `baseChartVersion` in all 8 `services/*/prod/templates/appset.yaml`
   (automerge window 01:00–06:00 America/Denver). Clusters only get Reloader
   once their pin is bumped — expect a lag of up to ~a day.
2. On each cluster after its bump: ArgoCD Application `<svc>-reloader`
   appears Synced/Healthy; Deployment `<svc>-reloader-reloader` Running in
   `default` (verify on gpu via `readonly-gpu-kubernetes`).
3. Functional test: change any value in a Bitwarden item backing an
   ExternalSecret of an annotated workload (e.g. gpu's qdrant or searxng);
   ExternalSecrets syncs the Secret; within ~1 min the workload's pods roll
   and the ArgoCD app stays Synced (annotation ignored in diffs).

## Risks & open questions

- **Rollout lag**: not instant — gated on CI release + renovate
  baseChartVersion bumps (per-cluster). Expected and normal for base changes.
- **Restart storms**: a Secret/ConfigMap referenced by many annotated
  workloads restarts all of them at once (e.g. a shared secret would fan
  out). Current charts use per-service secrets, so fan-out is limited.
  Per-workload escape hatch exists if ever needed:
  `deployment.reloader.stakater.com/pause-period` annotation.
- **Frequent churn**: if a referenced ConfigMap is rewritten repeatedly
  (e.g. a templated config that changes every ArgoCD sync), the workload
  restarts repeatedly. None of the current annotated charts do this; watch
  after rollout.
- **jqPathExpressions key quoting**: the annotation key contains `.` and `/`;
  the bracket-quoted form used here is proven by the existing
  `date/deploy-date` entry.
- Out of scope (deliberately): Reloader metrics/PodMonitor (the k8s-monitoring
  stack could scrape it later via `reloader.podMonitor.enabled`), HA mode
  (single replica is fine at homelab scale).
