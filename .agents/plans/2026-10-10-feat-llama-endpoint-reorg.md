# Plan: re-organize llama endpoints — llama → gpu-ai, llama-moe → gpu, cluster-based internal names (feat)

- **Date:** 2026-10-10
- **Branch/worktree:** `gpu-dns`
- **Skills loaded:** helm-chart-creation (incl. references/proxying.md), llama-swap (context)
- **MCP used (readonly):** readonly-gpu-kubernetes, readonly-ai-gpu-kubernetes,
  readonly-proxy-local-kubernetes, readonly-infra-postgres-keycloak

## Goal

1. `llama.spencerslab.com` — externally accessible exactly as today:
   proxy-remote → proxy-local → **gpu-ai** cluster.
2. `llama-moe.spencerslab.com` — NEW public endpoint:
   proxy-remote → proxy-local → **gpu** cluster.
3. Retire the conflicting `llama-cpp.spencerslab.com` internal name (rendered
   by BOTH gpu and gpu-ai, DNS pointed only at gpu). Replace with
   cluster-based names following the `mcp.<cluster>` / `cluster.<cluster>`
   convention: **`llama.gpu.<domain>`** and **`llama.gpu-ai.<domain>`**.
4. Repoint the two in-repo consumers of `llama-cpp.<domain>` (minuspod,
   immich-analyze) at `llama.spencerslab.com` (operator decision 2026-10-10).

## Verified current state (repo + live clusters + DNS, 2026-10-10)

- `llama.<domain>` chain works today: proxy-remote `llama-ingress` → SSH
  tunnel → proxy-local `llama` entry (ExternalName → `gpu-ai.<domain>`) →
  gpu-ai `llama-ingress` (host `llama.<domain>`, rendered from the
  `llama-cpp` entry's `serviceName: llama`) → `gpu-ai-llama-swap:8080`.
- Conflict: gpu AND gpu-ai both render an Ingress for host
  `llama-cpp.<domain>`; DNS (10.0.22.205) reaches only gpu. gpu-ai's copy is
  dead weight.
- gpu serves `llama-small.<domain>` publicly; proxy-local `llama-small`
  targets `llama-cpp.<domain>`. No proxy-remote entry (not externally
  reachable).
- Consumers of `llama-cpp.<domain>`: `charts/minuspod` (media — OPENAI +
  whisper endpoints) and `charts/immich-analyze` (home — VL models).
  `agent-config.jsonc` already uses `llama.<domain>` — unaffected.
- Keycloak `traefik` client redirect URIs are explicit per subdomain;
  `llama` is registered, `llama-moe` is NOT (verified via Keycloak DB).
- Auth on the public llama path: `user-allowlist[-remote]@file` are traefik
  ipAllowList middlewares (base `sourceRange: 10.0.0.0/16` + Keycloak-login
  IPs maintained by the traefik-mqtt-allowlist sidecar, 30-day expiry). LAN
  clients pass without SSO → headless consumers (minuspod, immich-analyze)
  work via mesh DNS → 10.0.77.54 (proxy-local).
- Cluster-scoped TLS: base issues `cluster-wildcard-cert`
  (`*.<clusterName>.<domain>`) on every cluster ✓.
- DNS records for cluster-scoped hosts (`mcp.gpu`, `cluster.gpu[-ai]`) are
  manually managed, individual records (no wildcard).
- Pre-existing: `gpu` and `proxy-local` ArgoCD umbrella apps are OutOfSync
  (Healthy) — gpu still carries an orphan `llama-ingress`, proxy-local orphan
  `ai-llama-swap-*`. gpu-ai is Synced.

## Changes

### 1. `services/gpu/prod/templates/generic-ingress.yaml` + `services/gpu-ai/prod/templates/generic-ingress.yaml`

The `serviceName` (public) ingress must always use `wildcard-cert` — its host
is always `<serviceName>.<domain>`, never cluster-scoped. Today it inherits
`cluster-wildcard-cert` when the entry sets `clusterBase: true`, which breaks
TLS for a public host. One-line change per file (serviceName block only; the
key-derived internal ingress keeps the conditional). Safe: no existing entry
combines `clusterBase` + `serviceName`. Required so one entry can render both
the cluster-based internal hop and the public host.

### 2. `services/gpu/prod/values.yaml`

Replace the `llama-cpp` ingress entry:

```yaml
llama:
  clusterBase: true
  serviceName: llama-moe
  service: gpu-llama-swap
  port: 8080
```

Renders: `llama-gpu-ingress` (host `llama.gpu.<domain>`,
cluster-wildcard-cert, llama-timeouts transport) + `llama-moe-ingress`
(host `llama-moe.<domain>`, wildcard-cert, external-dns label — inert on gpu,
no external-dns there).

### 3. `services/gpu-ai/prod/values.yaml`

Replace the `llama-cpp` ingress entry:

```yaml
llama:
  clusterBase: true
  serviceName: llama
  service: gpu-ai-llama-swap
  port: 8080
```

Renders: `llama-gpu-ai-ingress` (host `llama.gpu-ai.<domain>`) +
`llama-ingress` — byte-identical to the live public ingress (host
`llama.<domain>`, wildcard-cert): zero disruption to the existing chain.

### 4. `services/proxy-local/prod/values.yaml`

- **Add** `llama-moe` — exact mirror of `llama` (ssoRedirectPath →
  `https://llama-moe.<domain>/ui/`, `loginSubDomain: login`, crowdsec +
  user-allowlist-remote middlewares, IngressRoute middlewares crowdsec +
  user-allowlist), with `target: gpu` (ExternalName → `gpu.<domain>`,
  resolves to gpu traefik 10.0.22.205).
- **Remove** the `llama-small` block — its target `llama-cpp.<domain>` ceases
  to exist; `llama-moe` supersedes it. Its public CNAME record is auto-pruned
  by proxy-local's external-dns (`policy: sync`).
- Update the `llama` entry comment.

### 5. `services/proxy-remote/prod/values.yaml`

Add `llama-moe: enabled: true` next to `llama`. Renders `llama-moe-ingress`
(geoblock + redirect-to-https, backend `proxy-service`, cert-manager
`llama-moe-cert` via DNS-01). Note: the `enabled` flag is a no-op in the
current template (guard dropped 2024-12); the entry renders either way — same
as every existing entry.

### 6. `charts/minuspod/templates/secret-minuspod.yaml`

`OPENAI_BASE_URL` / `WHISPER_API_BASE_URL`: `llama-cpp.<domain>` →
`llama.<domain>` (+ comment update). Lands on gpu-ai via the proxy-local hop;
LAN ipAllowlist passes the pod without SSO. whisper-large-v3 (`wsp`) is in
gpu-ai's merged roster.

### 7. `charts/immich-analyze/values.yaml`

`aiHosts: "https://llama.spencerslab.com"` (was llama-cpp). `qwen3-vl-4b-q4`
is in gpu-ai's merged roster via chart defaults.

No llama-swap chart changes (chart embeds no hostnames). No custom-values
changes (no new secrets).

## Operator steps (outside repo — BEFORE/at merge)

1. Keycloak admin: add `https://llama-moe.spencerslab.com/*` to the
   `traefik` client redirect URIs (else browser SSO bootstrap fails).
2. DNS create (Cloudflare + LAN split-horizon):
   - `llama.gpu.spencerslab.com` → 10.0.22.205 (gpu traefik)
   - `llama.gpu-ai.spencerslab.com` → 10.0.99.151 (gpu-ai traefik)
   - LAN override `llama-moe.spencerslab.com` → 10.0.77.54 (proxy-local;
     mirrors `llama`). Public record appears automatically: proxy-local
     external-dns publishes CNAME → proxy-remote.<domain>.
3. DNS delete: `llama-cpp.spencerslab.com` (public + LAN override).
4. Ordering: Keycloak + DNS first, then merge — minuspod/immich-analyze lose
   `llama-cpp.<domain>` the moment the gpu cluster syncs.

## Validation

Pre-merge (all done in scratch copy during planning, re-run against repo
after edits):
- `helm template` gpu umbrella (`--set domain=… --set clusterName=gpu`) →
  `llama-gpu-ingress` + `llama-moe-ingress`, zero `llama-cpp`.
- `helm template` gpu-ai umbrella → `llama-gpu-ai-ingress` + `llama-ingress`
  (host/cert/labels unchanged vs live).
- `helm template` proxy-local umbrella → `llama-moe-{service,ingress,
  sso-ingress,local-ingress,local-sso-ingress}` + `redirect-llama-moe`;
  zero `llama-small`.
- `helm template` proxy-remote umbrella → `llama-moe-ingress`.
- `helm lint` + `helm template` charts/minuspod and charts/immich-analyze.

Post-merge (user-driven):
- ArgoCD sync gpu, gpu-ai, proxy-local, proxy-remote umbrellas; confirm
  orphan prunes (`llama-cpp-ingress` on both clusters, `llama-small-*` on
  proxy-local + gpu). Watch the pre-existing OutOfSync on gpu/proxy-local —
  if they stay stuck the new values won't apply.
- End-to-end from LAN: `curl https://llama-moe.spencerslab.com/v1/models`
  (SSO redirect for unknown IPs expected; 200 from allowlisted LAN),
  `curl https://llama.spencerslab.com/v1/models` unchanged.
- minuspod transcription + LLM calls; immich-analyze logs (pod restarts via
  reloader on secret/values change).

## Risks / notes

- gpu-ai matrix runs one GPU model at a time: minuspod whisper / immich-analyze
  VL loads now share the gpu-ai GPU with the Qwen3.8 daily drivers (normal
  llama-swap eviction churn; ttl 300).
- The public `llama`/`llama-moe` ingresses do NOT carry the llama-timeouts
  ServersTransport (only key-derived ingresses do) — parity with today;
  entrypoint timeouts are 650s. The template's "scope this to llama-swap"
  TODO remains.
- gpu + proxy-local umbrellas were OutOfSync before this change (orphan
  resources live there). Pre-existing; monitor during rollout.
