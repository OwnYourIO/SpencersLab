# Long-term fix: ToolHive MCP servers (searxng, renovate, postgres-*)

**Date**: 2026-09-27 · **Type**: debug · **Status**: probe fix + searxng/renovate
streamable-http migration applied in working tree (uncommitted); cluster sync
pending (manual-sync app — no blocker, just never synced)

## Problem Summary

All ToolHive-managed stdio-transport MCP servers on the **gpu** cluster are
degraded or non-functional. Two distinct failure modes are active:

| Symptom | Affected servers | Root cause |
|---------|-----------------|------------|
| MCP `initialize` hangs (200 + SSE headers, no body) | `mcp-searxng`, `mcp-renovate` | Proxy lost stdio attach to backend during a kube-apiserver outage (~08:00 UTC 2026-09-27), exhausted 10 re-attach retries, and entered a permanent zombie state. `/health` still returns 200 so Kubernetes never restarts the proxy pod. |
| Backend containers in CrashLoopBackOff (exit 137, thousands of restarts) | `mcp-postgres-coder`, `-flowise`, `-langflow`, `-n8n`, `-open-webui`, `-supabase` | The liveness probe added in hivetools-1.0.62 curls the proxy's `/health` and expects a JSON field `mcp.available`. Proxyrunner **v0.34.0** returns `{"status":"healthy",…}` with no `mcp` key → probe always exits 1 → kubelet SIGKILLs the backend every ~75 s. |

Both failure modes trace back to a single underlying gap: **the gpu cluster is
still running ToolHive operator + proxyrunner v0.34.0**, while the Helm chart
in git (`charts/hivetools/Chart.yaml`, tag `hivetools-1.0.68`) already pins
**v0.50.0**. The Argo CD Application `gpu-hivetools` shows
**Sync Status: OutOfSync** — the upgrade was committed but never applied to
the cluster.

## Evidence

- `mcp-searxng-795f4dc765-n5flx` proxy log (08:00:40 UTC):
  `container stdout closed` → 10× `apiserver not ready / connection refused`
  → `failed to re-attach after all retry attempts`. Every subsequent request:
  `error sending message to container: io: read/write on closed pipe`.
- `mcp-renovate-5f4cc6d785-hds5f`: identical closed-pipe pattern from 08:24 onward.
- `mcp-postgres-langflow-0`: restartCount 6 147; last exit code 137.
- Proxy `/health` (all servers): `{"status":"healthy","version":{"version":"v0.34.0",…},"transport":"streamable-http"}` — no `mcp` key.
- Argo CD: `gpu-hivetools` → `Sync Status: OutOfSync`, `Health Status: Healthy`.
- Operator pod label: `app.kubernetes.io/version: 0.34.0`.

## Root Causes

1. **Argo CD sync gap** – chart 1.0.68 (ToolHive 0.50.0) committed 2026-09-20
   but never synced to the gpu cluster. The operator, CRDs, and proxyrunner
   images are all still v0.34.0.
2. **Probe/version mismatch** – the postgres liveness probe (added in 1.0.62)
   expects a `mcp.available` field in the proxy `/health` response. The
   `mcp` key is gated on a pinger that **only exists for HTTP-transport
   backends** (verified in proxyrunner v0.34.0 *and* v0.51.3 source: the
   pinger lives in `pkg/transport/proxy/httpsse` and `.../transparent` only).
   For stdio servers the key is **never present, on any version** — so the
   probe could never pass on postgres-mcp (stdio). Deployed against 0.34.0 it
   always failed.
3. **Proxyrunner v0.34.0 re-attach fragility** – after a transient API-server
   outage the stdio attach is lost; the proxy retries only 10 times then
   gives up permanently while still reporting healthy. No self-heal path
   exists without a pod restart.
4. **Kube-apiserver instability trigger** – at ~08:00 UTC the API server at
   10.43.0.1:443 was unreachable (connection refused / reset) for ≥ 2 minutes,
   triggering the cascade. The operator pod also restarted around that time
   (34 total restarts over 19 days).

## Long-Term Fix Plan

### Phase 1 – Restore service (immediate, < 5 min downtime per server)

```bash
# Restart the zombied stdio proxies so they re-attach to their backends
kubectl -n default rollout restart deployment/mcp-searxng
kubectl -n default rollout restart deployment/mcp-renovate

# Restart crash-looping postgres backends + proxies
for name in coder flowise langflow n8n open-webui supabase; do
  kubectl -n default rollout restart deployment/mcp-postgres-${name}
  kubectl -n default delete pod mcp-postgres-${name}-0   # STS pod
done
```

> **Note**: This is a stop-gap. Without the version upgrade the postgres
> probes will restart the crash loop within ~75 s.

### Phase 2 – Sync the ToolHive upgrade (the real fix)

1. ~~Investigate why Argo CD `gpu-hivetools` is OutOfSync~~ — **resolved: no
   blocker.** The app's syncPolicy has no `automated:` block (manual-sync
   ApplicationSet); the 2026-09-20 chart bump simply never got synced.
2. Sync the application so the cluster converges on chart 1.0.68:
   - Operator image → `ghcr.io/stacklok/toolhive/operator:v0.50.0`
   - Proxyrunner image → `ghcr.io/stacklok/toolhive/proxyrunner:v0.50.0`
   - CRDs updated to 0.50.0 schema
3. After the operator rolls out, trigger a reconcile of every MCPServer so
   proxy Deployments and backend StatefulSets are recreated with the new
   proxyrunner image.
4. Verify:
   - `POST /mcp` initialize returns a JSON-RPC result within < 5 s on every
     server (searxng/renovate via their `-headless` URLs, postgres/others via
     `-proxy` URLs).
   - Note: proxy `/health` on **stdio** servers never includes an `mcp` key
     (pinger is HTTP-transport only) — do not expect `mcp.available` there.
     For searxng/renovate (now streamable-http) there is no proxyrunner at
     all; the server's own endpoint answers.
   - Postgres backend restart counts stabilise (no new 137 exits).

### Phase 3 – Evaluate bump to v0.51.3

v0.51.3 (released 2026-09-26) includes:
- Security fix GHSA-2gjv-f568-6cxp (OAuth callback binding).
- vMCP session-drain fix (#6715).
- SSE proxy response routing fix (#6702, in v0.51.1).

If the 0.50.0 sync stabilises the cluster, a follow-up Renovate PR (already
tracked on branches `renovate/toolhive-operator-0.x` /
`renovate/toolhive-operator-crds-0.x`) can bump to 0.51.3.

### Phase 4 – Harden against recurrence

| Action | Detail |
|--------|--------|
| **Make the postgres liveness probe version-tolerant** | ✅ **Done** – `generic-postgres-mcpserver.yaml` probe script updated: a missing `mcp` key is now treated as healthy (exit 0); only an explicit `"available": false` triggers a restart. Note: since stdio proxies never report `mcp` (any proxyrunner version), on 0.34.0/0.50.0 the probe effectively only guards proxy reachability + timeouts — it no longer crash-loops the backends. |
| **Add a synthetic MCP initialize probe** | Deploy a lightweight CronJob or external monitor that POSTs an `initialize` request to every `-proxy` service every 60 s and alerts (e.g. via Grafana/Prometheus) if no JSON-RPC result arrives within 10 s. This catches the zombie-proxy state that `/health` misses on v0.34. |
| **Alert on proxy re-attach failure** | Ship proxy logs to Loki and alert on the string `"failed to re-attach after all retry attempts"`. Page on-call so the pod is restarted within minutes, not discovered hours later. |
| **Investigate apiserver stability** | The 08:00 UTC outage (connection refused on 10.43.0.1:443) triggered the whole cascade. Check k3s server logs / etcd health on the gpu node for that window. 34 operator restarts in 19 days also suggests recurring control-plane pressure. |
| **Pin Argo CD auto-sync policy** | The `gpu-charts-appset` template only emits `automated: {prune, selfHeal}` when the `services.<svc>.selfHeal` annotation is truthy — gpu's per-chart apps (incl. `gpu-hivetools`) have no `automated.sync`, so chart bumps sit in OutOfSync indefinitely (that's how 0.50.0 aged a week). Consider adding `automated: {sync: true, prune: true, selfHeal: true}` for chart apps, or a standing "sync after chart bump" step in the release runbook. |

### Phase 5 – Reduce stdio-transport exposure (✅ done for searxng + renovate)

The stdio proxy pattern (proxyrunner attaches to a backend pod's stdin/stdout)
is inherently fragile across API-server interruptions. Where possible, servers
now run native **streamable-http** (no proxyrunner attach hop):

- ✅ **`mcp-searxng`** – image ≥ 1.13.0 supports `MCP_HTTP_PORT` /
  `MCP_HTTP_HOST` for native HTTP mode. `services/gpu/prod/values.yaml`:
  `transport: streamable-http` + those two env vars. **Client URL changed** in
  `agent-config.jsonc`: `global-searxng` now points at
  `mcp-mcp-searxng-headless.default:8080/mcp` (headless service hits the mcp
  pod directly; the `-proxy` service remains for the external ingress path).
- ✅ **`mcp-renovate`** – `renovate-mcp` is stdio-only upstream, so
  `containers/renovate-mcp` now also installs **supergateway 4.0.0** (stdio →
  Streamable HTTP bridge). The MCPServer podTemplateSpec overrides the
  container entrypoint: `supergateway --stdio renovate-mcp
  --outputTransport streamableHttp --port 8080` (stateless by default —
  renovate's state lives in /workspace, not MCP sessions). The image
  `ENTRYPOINT ["renovate-mcp"]` is unchanged, so `transport: stdio` is still a
  one-line revert. **Client URL changed**: `global-renovate` →
  `mcp-mcp-renovate-headless.default:8080/mcp`.
- ⏸ **`postgres-mcp` 0.3.0** – supports `--transport sse` (verified in
  v0.3.0 source) but SSE is the deprecated MCP HTTP transport and 0.3.0 is
  the pinned final release; left on stdio. The probe fix + 0.50.0 upgrade
  stop the crash loop; the synthetic probe + Loki alert below cover the
  residual zombie-stdio risk. Revisit if a newer postgres-mcp with
  streamable-http ever ships.

**Deployment order (important):**

1. Merge the branch → `.github/workflows/docker-build.yaml` rebuilds
   `ghcr.io/ownyourio/renovate-mcp:main` **with supergateway**.
2. Only after that build is pushed, sync `gpu-hivetools`. If the app syncs
   first, the renovate MCPServer switches to streamable-http against the old
   image (no supergateway) and the pod fails.
3. The sync applies the ToolHive 0.50.0 operator/CRD/proxyrunner upgrade in
   the same change (the app was OutOfSync since the 2026-09-20 bump —
   manual-sync app, no blocker found).

**Rollback per server:** flip `transport` back to `stdio` (+ drop
`MCP_HTTP_PORT`/`MCP_HTTP_HOST`/`command`/`args`), restore the `-proxy`
client URL in `agent-config.jsonc`, sync. Image changes are additive.

## Validation Checklist (post-fix)

- [ ] `curl POST /mcp` to every server returns a valid JSON-RPC initialize
      result within 5 s.
- [ ] OpenCode / agent config connects to all `enabled: true` MCP servers
      without timeout.
- [ ] Postgres backend pods show restartCount frozen (no new increments).
- [ ] MCPServer CR status: all `phase: Ready`.
- [ ] No `closed pipe` or `failed to re-attach` entries in proxy logs for
      24 h post-fix.
- [ ] Argo CD `gpu-hivetools` shows `Sync Status: Synced`.

## Rollback

If the 0.50.0 upgrade introduces regressions:
1. Revert `Chart.yaml` dependencies to 0.34.0 (tag `hivetools-1.0.61`).
2. Sync Argo CD → operator rolls back.
3. Re-apply the immediate restart commands from Phase 1.
