# Plan: Fix alloy-metrics OOM kills (k8s-monitoring chart, all clusters)

## Goal
Stop the recurring OOM kills of the `alloy` container in the k8s-monitoring
chart's `alloy-metrics` StatefulSet by raising its memory limit from 512Mi to
1Gi. Chart-wide fix — the limit lives in the shared chart, and OOMKills are
confirmed on at least two clusters.

## Skills
Code agent runs in a fresh session — load:
- `helm-chart-creation` — chart values conventions and helm lint/template
  validation.

## MCP Servers
- `kubernetes` (readonly tier) for the **media** and **monitoring** clusters —
  post-sync confirmation that OOM kills have stopped.

## Verified context
Recon 2026-09-07 via media/monitoring readonly MCP + repo reads:
- `media-k8s-monitoring-alloy-metrics-0`: alloy container lastState
  `OOMKilled` (exit 137) at the 512Mi limit, **248 restarts**, kills recurring
  every few minutes; pod flaps CrashLoopBackOff 1/2.
- `monitoring-k8s-monitoring-alloy-metrics-0`: same signature — `OOMKilled`
  16:35:53Z, **161 restarts**. Other clusters' alloy-metrics also show elevated
  restart counts (gpu 48, home 171, grow 166, proxy-local 233 over ~220d).
- Limit source: `charts/k8s-monitoring/values.yaml` →
  `alloy-metrics.alloy.resources.limits.memory: 512Mi` (requests cpu 100m /
  memory 128Mi). No service values.yaml on any cluster overrides k8s-monitoring
  resources (grep across services/*/prod/values.yaml found none).
- Chart wraps upstream `grafana k8s-monitoring 3.8.0` and is deployed on all 7
  clusters (gpu, grow, home, infra, media, monitoring, proxy-local).
- Precedent in the same values file: `alloy-logs` already runs with
  `limits.memory: 1Gi`.

## Design decisions
- **Raise the limit chart-wide, not per-cluster**: the OOM is a property of the
  shared chart config; every cluster gets the same 512Mi limit and several are
  affected. A chart edit rolls all clusters on next sync — desired here.
- **1Gi, requests unchanged**: matches the chart's own alloy-logs limit; limits
  don't reserve node memory, so scheduling is unaffected. If OOM recurs at 1Gi,
  next step is 2Gi (or investigate metric cardinality growth).
- **No version bump** — `release.yaml` bumps chart versions on merge to main.

## Changes
1. [MODIFY] `charts/k8s-monitoring/values.yaml` — in the `alloy-metrics:` block
   (lines ~147–159), change `limits.memory` from `512Mi` to `1Gi` and add a
   short note:
   ```yaml
     # Alloy metrics instance
     alloy-metrics:
       enabled: true
       alloy:
         clustering:
           enabled: false
         mounts:
           dockercontainers: true
         resources:
           requests:
             cpu: 100m
             memory: 128Mi
           limits:
             # 2026-09-07: 512Mi caused recurring OOMKills (media 248 restarts,
             # monitoring 161). Matches alloy-logs below.
             memory: 1Gi
   ```

## Verification
Config-level (pre-commit):
1. `helm lint charts/k8s-monitoring` → pass.
2. `helm template charts/k8s-monitoring` → exit 0 (run `helm dependency build
   charts/k8s-monitoring` first if the upstream chart isn't vendored; network is
   available in this environment).
3. Grep proof: `limits.memory: 1Gi` under `alloy-metrics`, requests unchanged,
   `alloy-logs`/`alloy-singleton` blocks untouched; `git diff` shows only this
   one hunk.

Live (post-merge — Code agent commits to its branch/worktree only; user merges):
4. ArgoCD syncs k8s-monitoring on each cluster; alloy-metrics StatefulSet rolls
   (brief metrics-collection gap per cluster — expected).
5. On media + monitoring (readonly MCP): alloy container running with the new
   1Gi limit, no new `OOMKilled` lastState, restart count stable over time.

## Risks & open questions
- **Rolling restart on all 7 clusters** when the chart syncs — short, expected
  gaps in metrics collection.
- If memory usage keeps growing past 1Gi, the limit bump is a mitigation, not a
  cure — investigate alloy's scrape cardinality (media has the largest target
  set) before bumping again.
