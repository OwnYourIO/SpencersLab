# Proxying & external access (SpencersLab)

How traffic reaches services across the clusters. Verified against
`services/proxy-local/`, `services/proxy-remote/`, `charts/traefik-zerotrust/`
and the per-service `generic-ingress.yaml` templates (2026-09-07).

## The three tiers

```
internet ──► proxy-remote.<domain>          (public edge, zerotrust)
                 │  SSH tunnel (autossh remote port-forward :443)
                 ▼
             proxy-local traefik            (lab hub: auth + routing)
                 │  ExternalName <name>.<domain>  (mesh/split-horizon DNS)
                 ▼
             owning cluster's traefik ──► service/pod
```

1. **Public edge — `proxy-remote` service** (`services/proxy-remote/prod/`,
   chart `charts/traefik-zerotrust`, deployed on the remote/VPS cluster):
   - Host `proxy-remote.<domain>`; **SSH on port 2222** (LinuxServer
     openssh-server container; public key in
     `custom-values/proxy-remote/prod-values.yaml` under `sshd.`).
   - traefik-zerotrust runs the **geoblock** plugin middleware
     (`middleware-geoblock.yaml`: geojs.io lookup, US/CA only,
     `allowLocalRequests: true`) and redirect-to-https.
   - Its `proxy.subdomains` ingresses default their backend to
     `proxy-service` (the sshd pod, port 443).
   - Remote clusters join the lab through this zerotrust edge; the base
     chart's comment trail calls out that `*.proxy-remote.<domain>` DNS must
     resolve for ACME DNS-01 to succeed there.

2. **Lab hub — `proxy-local` service** (`services/proxy-local/prod/`):
   - Deploys the hub cluster's **traefik** (`charts:` entry, kube-system),
     smtp-relay, external-secrets, monitoring, seaweedfs-csi.
   - **`autossh` pod** (camptocamp/autossh) keeps the tunnel up:
     SSH to `proxy-remote.<domain>:2222` as user `proxy` (key from
     Bitwarden NOTES item `autossh-secret` via `secret-autossh.yaml`),
     remote-forwarding `SSH_TUNNEL_PORT: 443` (bound `0.0.0.0` on the
     remote) to `SSH_TARGET_HOST: traefik.kube-system` port 443 — i.e.
     external :443 traffic on proxy-remote exits inside the lab at the
     proxy-local traefik.
   - Per `proxy.subdomains.<name>` entry it renders (templates/proxy/):
     - `proxy-service.yaml` — **ExternalName Service** `<name>-service` →
       `<target|name>.<domain>`. The mesh/split-horizon DNS for that name
       resolves to the owning cluster's traefik, so the hub forwards the
       (already-authenticated) request on to it.
     - `proxy-ingress.yaml` — Ingress for `<name>.<domain>` with the
       middleware chain from `proxy.middlewares` (entrypoint = crowdsec +
       user-allowlist-remote; per entry userAuth or an SSO redirect chain)
       and **external-dns** annotations: label `external-dns: "enabled"` +
       `external-dns.alpha.kubernetes.io/target: proxy-remote.<domain>` →
       public DNS publishes `<name>.<domain>` CNAME → `proxy-remote.<domain>`.
     - `proxy-ingress-local.yaml` — IngressRoute (priority 50) matching
       `Host(...) && ClientIP(10.0.0.0/16, 192.168.0.0/16)` so LAN traffic
       skips the remote-auth chain.
     - `proxy-ingress-sso.yaml` + `proxy-middleware.yaml` — Keycloak SSO:
       on 403 the redirect middleware sends the client to
       `login.<domain>/<authRealm path>`; the `-sso-ingress` (priority 15,
       Exact path) routes the callback.

3. **Per-cluster traefik** — every cluster runs its own traefik and serves
   its own ingresses from the service values `ingress.subdomains` via the
   service-level `templates/generic-ingress.yaml`:
   - **cluster-scoped hosts** use the `clusterBase: true` convention:
     `<name>.<subDomain|clusterName>.<domain>` — e.g. ArgoCD at
     `cluster.gpu.<domain>`, `cluster.home-lab.<domain>` (home sets
     `subDomain: home-lab`). These carry **no external-dns label**: they are
     mesh/internal hosts, reachable through the zerotrust mesh, not
     published publicly.
   - Per-app subdomains (when enabled for external-dns) publish CNAMEs to
     `proxy-remote.<domain>` like the hub entries.

## TLS

The base chart (`charts/base/templates/cert-manager-wildcard-cert.yaml`)
issues two cert-manager Certificates per cluster via the letsencrypt-prod
ClusterIssuer (Cloudflare DNS-01; solver token UUID in each cluster's
custom-values `bitwardenIds.cert-manager-solver-token`):

| Secret | Covers | Used by |
|---|---|---|
| `wildcard-cert` | `*.<domain>` | top-level app subdomains (`player.<domain>`, …) |
| `cluster-wildcard-cert` | `*.<subDomain\|clusterName>.<domain>` | cluster-scoped hosts: `cluster.<…>`, `mcp.<…>` |

## Where MCP fits

The ToolHive MCP platform ingress (`charts/hivetools/templates/generic-mcp-ingress.yaml`)
is a **cluster-scoped host**: `mcp.<subDomain|clusterName>.<domain>` with
`cluster-wildcard-cert`, no external-dns label. Clients reach it through the
zerotrust mesh (mcp.gpu.<domain>, mcp.home-lab.<domain>, …); inside the gpu
cluster, Kilo uses cluster-local service DNS instead
(`mcp-mcp-<name>-{proxy,headless}.default`). See `mcp-servers.md`.

## Gotchas

- **Home naming:** home's cluster-scoped hosts use the subDomain
  (`home-lab`), not the clusterName — `mcp.home-lab.<domain>`,
  `cluster.home-lab.<domain>`. DNS and certs follow the subDomain.
- **external-dns target is always `proxy-remote.<domain>`** for publicly
  published names; cluster-scoped (`clusterBase`) entries must NOT get
  external-dns labels.
- **Don't expose cluster-scoped hosts publicly** (ArgoCD, MCP, traefik
  dashboards): mesh-only by design; OIDC/geoblock assumptions depend on it.
- The autossh tunnel is a single :443 forward — the proxy-local traefik is
  the only lab ingress for tunneled traffic; hub traefik downtime = external
  outage for everything routed through it.
- GPU's `generic-ingress.yaml` currently has the external-dns target
  annotation commented out (per-app public exposure there is disabled).
