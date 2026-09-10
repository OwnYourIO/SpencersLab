# 2026-09-10 — debug: Traefik proxy-local serving 404s after restarts; healthcheck never fires

Type: debug. Status: chart fix implemented + validated; environmental follow-ups listed below.

## Symptom

After Traefik restarts on proxy-local (notably after node reboots), it serves 404 for
every route that uses a plugin middleware (crowdsec, keycloakopenid, redirect-on-status,
…). Restarting Traefik "fixes" it. The healthcheck added to make the kubelet probe fail
in that state never fails.

## Root causes (all evidenced live)

### 1. The probe can never fail: Traefik's internal ping router shadows the healthcheck route

- Deployed probes (verified in the live pod spec): liveness+readiness
  `httpGet /ping :8080`, `failureThreshold: 1`.
- Traefik v3.6.15 (`pkg/provider/traefik/internal.go:343-351`) auto-creates an internal
  router when ping is enabled: rule `PathPrefix('/ping')` on the `traefik` entrypoint
  (:8080), service `ping@internal`, **`Priority: math.MaxInt`**, no middlewares.
- The healthcheck IngressRoute used the same rule on the same entrypoint → permanently
  shadowed. Verified via the live API: `ping@internal` `priorityStr=9223372036854775807`
  vs healthcheck router `priorityStr=19`; `wget localhost:8080/ping` → 200 OK while the
  instance was broken.
- Internal routers are also excluded from access logs/metrics by default
  (`pkg/server/middleware/observability.go`, `AddInternals=false`) — which is why probe
  traffic leaves no trace in Loki/Prometheus.

### 2. `TRAEFIK_EXPERIMENTAL_ABORTONPLUGINFAILURE=true` was dead code

- The env var was present in the pod spec (verified via `/proc/1/environ`), but paerser's
  loader loop (`cli/commands.go:run`) **stops at the first loader that returns
  `done=true`**. Traefik's loader order is DeprecationLoader → FileLoader → FlagLoader →
  EnvLoader, and the container always runs with CLI flags, so FlagLoader wins and
  EnvLoader never runs. The flag was false at runtime on every startup: the Sep 8 broken
  startup logged "Plugins are disabled because an error has occurred." and continued
  instead of aborting.

### 3. Plugins are re-downloaded from the internet on every startup

- `pkg/plugins/plugins.go SetupRemotePlugins` → `CleanArchives` + `InstallPlugin` →
  unconditional `downloader.Download` from `plugins.traefik.io` (10s client timeout).
  The `/plugins-storage` emptyDir cache does not prevent downloads.
- After a node reboot, egress is not up yet → download times out → all plugins disabled
  → every plugin middleware "does not exist" → every router referencing one is dropped →
  global 404. Observed Sep 8 12:31:18 (keycloakopenid download timeout; all 6 plugins
  disabled; 124+ routers dropped).

### 4. The trigger: the proxy-local node is being rebooted out-of-band

- Sep 8 12:29 and Sep 10 12:23: node-wide container restart waves (59 containers on
  Sep 10, incl. coredns/metrics-server/CSI/crowdsec).
- Journald (via Loki, `unit` label): `12:22:59 New session '15' of user 'root' … type
  'tty'` → `12:23:02 reboot requested from client PID 320672 ('reboot')` →
  `The system will reboot now!`. Something/someone logs in on the console and runs
  `reboot`. Unresolved — needs node-level investigation (audit log / session-15 scope).
- Separately, pods were recreated ~01:4x on Sep 7 and Sep 9 (new pod names) — a second,
  unexplained periodic event.

### 5. Startup race (recurs even when plugins load fine)

- Sep 10 12:24:29-31 (current run): first config build dropped 124 routers with
  `middleware … does not exist` because the ingress provider delivered ingresses before
  the CRD provider's Middleware CRs were processed. Most routers recovered on later
  reloads; anything not reloaded stays dropped until the next provider event.

## Changes made

`charts/traefik/values.yaml` (only file changed):

1. Added `--experimental.abortonpluginfailure=true` to `traefik.additionalArguments`
   (CLI form — the only form that works when args are present). A plugin-load failure now
   aborts startup → crashloop-with-backoff retries the download until egress is up,
   instead of starting permanently broken.
2. Removed the dead `TRAEFIK_EXPERIMENTAL_ABORTONPLUGINFAILURE` env var (replaced with an
   explanatory comment).
3. Moved probes off the shadowed `/ping`:
   - `traefik.ingressRoute.healthcheck.matchRule: PathPrefix('/healthcheck')`
   - `traefik.deployment.livenessPath: /healthcheck` and `readinessPath: /healthcheck`
   The kubelet now probes through the healthcheck IngressRoute and its crowdsec
   middleware: if the middleware is invalid the router doesn't load → 404 → restart
   (with the existing `failureThreshold: 1`).

## Validation

- `helm dependency build charts/traefik` OK (traefik 39.0.9 + crowdsec 0.24.0).
- `helm lint charts/traefik` — 0 failures (the monitoring.coreos.com INFO is the
  ServiceMonitor CRD-absent check, expected locally).
- `helm template charts/traefik` (with serviceMonitor disabled locally): probes render as
  `httpGet /healthcheck :8080` threshold 1; abort flag in args; healthcheck IngressRoute
  on entrypoint `traefik` with crowdsec middleware and `ping@internal` service.

## Known trade-off

With `failureThreshold: 1`, the very first probe (t+2s) can fail during a healthy startup
(healthcheck route not loaded yet, or plugin download still running — entrypoints open
only after plugins load). Worst case: one extra container restart before the pod settles;
for a pod with a fresh plugins cache (emptyDir wiped) it crashloops until the plugin
download succeeds — which is the intended self-heal. If this proves too aggressive in
practice, raise `livenessProbe.failureThreshold` to 2–3 or add a startupProbe.

## Follow-ups (not done)

1. **Find what reboots cloud-proxy** (root TTY `reboot`, ~daily; also the ~01:4x
   pod-recreation events). Check `journalctl`/audit on the node, `session-*.scope`
   origins, cron/timers, backup tooling.
2. **Disable the k3s bundled traefik addon**: `HelmChart traefik/traefik-crd`
   (kube-system) fights the ArgoCD-managed chart; its klipper job
   `helm-install-traefik-*` crashloops forever ("Required CRDs are missing"). Add
   `--disable traefik --disable traefik-crd` to the k3s server config (not managed by
   this repo today) or delete the HelmChart resources.
3. **Consider vendoring plugins** (`experimental.localPlugins` or baking
   `/plugins-storage` into the image) to remove the every-startup internet dependency
   entirely — the most robust fix for reboot windows.
4. **Orphaned DNS/routing**: `git.spencerslab.com` → 10.0.77.59 (infra LB) but infra has
   no git ingress and gitea is deployed nowhere (no chart in this repo; DNS for
   gitea.spencerslab.com absent) — git via proxy-local works when forced
   (`--resolve …:10.0.77.54`). `help.spencerslab.com` has a circular ExternalName
   (help-service → help.spencerslab.com) and 404s via every path. Both are stale config,
   unrelated to the middleware bug.
5. Pre-existing noise: TLS secrets `kube-system/cluster-wildcard-cert` and
   `default/scifi-farm-cert` missing → errors on every config reload.

## Not committed

Changes are in the `troubleshoot-traefik` worktree only; commit/merge is the user's call.

## Follow-up incident (same day, ~14:31): the v1 probe config crashlooped

After the v1 fix merged (efa67306) and synced, the new ReplicaSet
crashlooped: liveness `/healthcheck` with `failureThreshold: 1` and
`initialDelaySeconds: 2` is an unwinnable race — entrypoints open only after
plugins load (>2s) and the healthcheck route answers only after the first
provider config build (another 1-3s), so the first probe always failed and
kubelet killed every start (9 restarts in 15 min, runs of 2-8s; rollout
stuck; MCP ingress down; boards 404).

### Correction (v2)

- Added a `startupProbe` on the internal `/ping` (port 8080, period 2s,
  failureThreshold 30 ≈ 60s) to cover plugin download + provider sync;
  liveness/readiness are suspended while it runs.
- Raised liveness/readiness `failureThreshold` to 2 (detects a broken
  middleware within ~20s; threshold 1 cannot survive a healthy startup).
- Kept: `/healthcheck` probe path through the crowdsec-gated IngressRoute and
  `--experimental.abortonpluginfailure=true`.

Validated again with helm lint/template. Recovery path: merge → ArgoCD sync
creates a new ReplicaSet with the v2 probes; pods boot through the
startupProbe and roll out cleanly.

## Final root cause (v3): the dashboard catch-all router shadows the healthcheck route

The v2 crashloop was NOT a provider/informer problem (that trail was a
capture-timing red herring — informers sync in <5s and the router table is
complete). Exec-based testing showed the healthcheck router present and
`status: enabled` on EVERY instance, yet `/healthcheck` → 404 everywhere,
while `/ping` → 200.

Traefik v3.6.15 `pkg/provider/traefik/internal.go:286-305`: with
`--api.insecure` + `--api.dashboard` (both in additionalArguments), the
internal provider creates on the `traefik` entrypoint:

- router `api`: rule `PathPrefix('/api')`, priority MaxInt-1
- router `dashboard`: rule `PathPrefix('/')` (catch-all), priority MaxInt-2

The upstream healthcheck IngressRoute gets default priority = rule length
(26) and cannot set one (its template has no priority support), so every
`/healthcheck` request was captured by the dashboard catch-all
(MaxInt-2 >> 26) and answered with its 404. Only `/ping` survived because
its internal router has priority MaxInt. This also retroactively explains
why the May-era /ping-based healthcheck never worked (ping router MaxInt).

### Fix (v3)

- New wrapper template `charts/traefik/templates/ingressroute-healthcheck.yaml`
  renders the healthcheck IngressRoute with explicit
  `priority: 9223372036854775806` (MaxInt-1: beats the dashboard catch-all;
  doesn't collide with the ping MaxInt `/ping` or api MaxInt-1 `/api` rules).
- `ingressRoute.healthcheck.enabled: false` (upstream variant is unusable).
- Probes unchanged from v2 (startupProbe /ping; liveness+readiness
  /healthcheck threshold 2). Deployment template unchanged → no new
  ReplicaSet; the existing crashlooping pod recovers as soon as ArgoCD
  patches the IngressRoute.

Validated: helm lint OK, helm template renders one healthcheck IngressRoute
with the priority, probes intact.

### Expected post-merge behavior

1. ArgoCD syncs: IngressRoute `proxy-local-traefik-healthcheck` gains
   priority (same object name, in-place update).
2. Crashlooping pod's next liveness passes → Ready → rollout completes,
   old-template pod terminated.
3. Future reboot-with-egress-down: abort flag crashloops until plugin
   download succeeds; runtime middleware death detected via /healthcheck
   within ~20s.

### Still open (separate from this fix)

- `proxy-local-hivetools` app OutOfSync → `normalize-mcp-path` middleware
  missing → MCP ingress router dropped (why agent cluster access was down).
- Orphaned git.spencerslab.com DNS (points at infra; gitea deployed nowhere)
  and circular help ExternalName.
- Missing TLS secrets `kube-system/cluster-wildcard-cert`,
  `default/scifi-farm-cert` error on every config build.
