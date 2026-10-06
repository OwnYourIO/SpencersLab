# 2026-10-06 bug — cluster health follow-ups: qbit OOM limit, ilias probe, SSO ingress TLS, chart disables

Operator-requested follow-ups from the 2026-10-06 7-day crash/memory audit
(all 7 clusters via readonly k8s MCP + Grafana Prometheus/Loki).

## Changes

1. **`services/proxy-local/prod/values.yaml` — qbittorrent `limits.memory` 3Gi → 4Gi.**
   Audit evidence: 179 kernel memcg OOM kills of `qbittorrent-nox`
   (09-30 → 10-06), peak WSS 3.22 GiB against the 3Gi cgroup limit. Node
   `cloud-proxy` has 17.9 GiB total / ~5 GiB free — the container limit,
   not VM RAM, was the constraint. 4Gi per operator choice (covers the
   observed peak; headroom is thin, revisit if OOMs return under heavier
   load).

2. **`charts/ilias/values.yaml` — `Host: localhost` header on ilias liveness,
   readiness, and startup probes.**
   ILIAS (`components/ILIAS/Init/src/Environment/HttpPathBuilder.php`)
   rejects any request whose Host header is not `localhost`, the
   `http_path` host, or the DB `allowed_hosts` setting → HTTP 500. Kubelet
   probes dial the pod IP and default to `Host: <podIP>` → 500 → ~1,000
   restarts/week crash loop. Kubelet's `NewRequestForHTTPGetAction` sets
   `req.Host` from probe `httpHeaders` (Host-header-only override; the dial
   target stays the pod IP), and `localhost` is in ILIAS's default allowed
   list, so the probes now pass. All three probes fixed because liveness
   would kill the container shortly after startup succeeded.

3. **`services/proxy-local/prod/templates/proxy/proxy-ingress-sso.yaml` —
   added `secretName: wildcard-cert` to the `-sso-ingress` TLS block.**
   The 10 BadConfig events (`spec.tls[0].secretName: Required value` —
   posts/polls/player/pictures/llama/graphs/budget/bri-budget/boards/
   audiobook-player) all came from this one template; same secret the main
   `proxy-ingress.yaml` uses for subdomains.

4. **Disabled readarr + jellyseerr (media) and archon (gpu).**
   - media: Arr-Stack subcharts have no `enabled` gate, so the deps were
     commented out of `services/media/prod/Chart.yaml` and `Chart.lock`
     regenerated with `helm dependency update` (digest
     `7a57b82c…`). Precedent: prowlarr move (2026-09-20).
   - Ingress entries commented out (precedent: neo4j/qdrant 2026-09-07):
     media `requests` (jellyseerr), media `ebooks` + `audiobooks` (readarr),
     proxy-local hub `ebooks` + `audiobooks` (fan-out to hosts media no
     longer serves). Hub `requests` (targets `requestarr`, a different app)
     left untouched.
   - gpu: `charts.archon` entry + `ingress.subdomains.archon` commented out.
   - PVCs (`jellyseerr`, `readarr`), hub `requests` entry, and dormant
     values blocks left in place for re-enable (noted in comments).

## Validation

- `helm lint` + `helm template` pass for: `charts/ilias` (probes render with
  `httpHeaders: Host: localhost` on all three; YAML parses),
  `services/proxy-local/prod` (all 10 `-sso-ingress` objects now carry
  `secretName: wildcard-cert`; qbit Deployment renders 8Gi limit;
  ebooks/audiobooks ExternalName services gone), `services/media/prod`
  (no jellyseerr/readarr Deployment/Service/Ingress; lidarr/radarr/sonarr
  unaffected; PVCs retained), `services/gpu/prod` (no archon
  Deployment/Ingress).
- Pre-existing `cluster-OVERRIDE_VIA_APPSET-ingress` lint warnings in
  media/gpu are sentinel-name artifacts (clusterName injected by the
  appset at deploy), not caused by this change.
- ArgoCD applies on sync; no `kubectl apply`.

## Notes / out of scope

- Hub `requests` → `requestarr` ExternalName has no matching ingress
  anywhere (pre-existing dangling entry) — left as-is.
- grow `mcp-postgres-grow-assistant-*` probe crash loops, grow ilias
  allowed_hosts DB setting, monitoring node disk (86%), and the 4 node
  reboots (10-01 ×3, 10-05 ×1) were identified in the audit but not in
  this batch of changes.
