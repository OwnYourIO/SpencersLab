# Perspectives — exposing Forgejo git-over-SSH on k3s + Traefik (dev/infra clusters)

Derived from the ticket's two gated questions + supporting design questions.
Live cluster evidence already collected (see RESEARCH.md evidence log):
dev/infra are single-node k3s 1.36 clusters; stock traefik chart 40.1.5 (dev,
Traefik 3.7.13) / 40.1.3 (infra, Traefik 3.7.4); Gateway CRDs v1.6.1 dev
(tcproutes present, standard channel) vs v1.5.1 infra (no tcproutes); no
`--providers.kubernetesgateway` arg on either; traefik Service is
LoadBalancer w/ ServiceLB node-IP (10.0.77.12 / 10.0.77.59 — same IPs mesh
DNS points the git hosts at); node sshd owns :22 on those IPs.

## P1 — Gateway API spec maintainer (kubernetes-sigs/gateway-api)
Sees: TCPRoute/TLSRoute channel status per release (v1.5.1 vs v1.6.1), what
"standard channel" CRD bundles contain, listener/protocol semantics for raw
TCP. Misses nothing about spec status; doesn't know Traefik or k3s.

## P2 — Traefik integrator (traefik/traefik + traefik helm chart)
Sees: kubernetesGateway provider support matrix (which Traefik version
supports TCPRoute, experimentalChannel flag), how Gateway listener ports map
to Traefik entryPoints, helm chart values surface for enabling the provider.
Blind spot: k3s's forked chart + ServiceLB.

## P3 — k3s platform engineer (k3s-io/k3s, rancher)
Sees: ServiceLB (klipper-lb) internals — node-IP assignment, svclb DaemonSet
hostPort mechanism, port-collision behavior vs host sshd, lbpool +
proxy-only annotations, NodePort range, the stock traefik HelmChart +
HelmChartConfig customization surface. Blind spot: Gateway API spec nuance.

## P4 — Forgejo administrator (forgejo docs + forgejo-helm chart)
Sees: server.SSH_PORT / SSH_LISTEN_PORT / SSH_DOMAIN semantics, clone-URL
rendering rules, built-in SSH server vs OpenSSH, host-key persistence on the
data PVC, the chart's service.ssh values surface. Blind spot: k8s exposure
mechanics.

## P5 — SpencersLab GitOps operator (this repo)
Sees: which files/values each option touches, whether traefik config is
already repo-managed (it is — charts/base HelmChartConfig), DNS topology
(mesh records for the git hosts currently point at node sshds), known_hosts
continuity for existing clients, coder gitssh usage. Grounded in repo files
+ live cluster, not web.