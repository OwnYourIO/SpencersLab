# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions

- Port literals (`22222`) appear in exactly two places and must stay equal:
  `gitSshPort` in the service umbrella values (dev + infra) and
  `forgejo.gitea.config.server.SSH_PORT` in `charts/forgejo/values.yaml`.
- Gateway surface lives in `charts/base` (HelmChartConfig + vendored CRD),
  gated on `gitSshPort`; app-side Gateway objects (TCPRoute) live with the
  app (forgejo subchart's `tcpRoute` values surface).
- The pipeline artifacts of this folder are committed by coord; C01's commit
  carries ONLY the relocated storm-runs trail.

## Decisions

- 2026-10-23 human (question round, verbatim): Q1 port = **"22222"**
  (typed answer — not one of the offered options 2222/2200/2223). Note for
  the record: 22222 < 30000 (below the k3s NodePort range), free of the
  proxy-remote edge-sshd 2222 confusion, assumed free on both nodes
  (verify at rollout: svclb readiness).
- 2026-10-23 human (verbatim): Q2 move node sshd off :22 = **"No, keep sshd
  on :22 (Recommended)"**. Consequence: `ssh://git@host:22222/...` clone
  URLs are the permanent shape; scp-style port-22 URLs stay impossible.
- 2026-10-23 human (verbatim): Q3 network exposure = **"Mesh/LAN only
  (Recommended)"**. proxy-remote untouched; public SSH needs a new edge
  design → follow-up, not this ticket.
- 2026-10-23 human (verbatim): Q4 mechanism = **"Gateway API now"**.
  Rejected: ServiceLB direct on the forgejo-ssh Service (research baseline,
  smallest diff) and traefik IngressRouteTCP — user chose the strategic
  Gateway API path despite it adding no capability over the alternatives for
  a single fixed port.
- 2026-10-23 human (verbatim): Q5 instances & ordering = **"Both, dev
  verified first (Recommended)"** — one shared config in charts/forgejo;
  verify dev end-to-end after sync, then infra.
- 2026-10-23 plan: Q6 entrypoint/gateway gating = **per-service `gitSshPort`
  value flag** (the `seaweedVolumePort` precedent in
  `charts/base/templates/traefik-config.yaml`), set only in dev + infra
  umbrellas. Rejected: cluster-wide default (would open port 22222 via
  ServiceLB and render Gateway/GatewayClass objects on every base-managed
  cluster with no backend).
- 2026-10-23 plan: Gateway + GatewayClass come from the **k3s-stock traefik
  chart's own templates** (defaults `gateway.enabled`/`gatewayClass.enabled`
  fire once the provider is enabled), configured via the repo-managed
  HelmChartConfig: listener `gitssh` (TCP, port = gitSshPort,
  `namespacePolicy.from: All`), chart-default `web` listener explicitly
  nulled, Gateway name `traefik-gateway` in kube-system. Rejected:
  repo-rendered Gateway/GatewayClass templates + `gateway.enabled: false`
  (duplicates chart machinery; disabling `gateway.enabled` also kills the
  chart's GatewayClass render, forcing both objects into the repo).
- 2026-10-23 plan: TCPRoute via the **forgejo subchart's shipped `tcpRoute`
  values block** (`enabled: true`, parentRefs → traefik-gateway/kube-system/
  sectionName gitssh, port default = service.ssh.port 22). Rejected: own
  TCPRoute template per service umbrella (the subchart surface is exactly
  sufficient; fewer repo templates).
- 2026-10-23 plan (RESEARCH CORRECTION, evidence below): the vendored CRD is
  the **experimental-channel** `tcproutes.gateway.networking.k8s.io` v1.6.3,
  applied to BOTH clusters via a `gitSshPort`-gated base template.
  Evidence (all fetched 2026-10-23):
  1. gateway-api standard CRDs v1.6.0/v1.6.1/v1.6.3
     (`config/crd/standard/gateway.networking.k8s.io_tcproutes.yaml`) all set
     v1alpha2 `served: false, storage: false` (v1 served+storage) —
     RESEARCH.md F2/source [4] claim "v1alpha2 still served (deprecated)"
     for the standard CRD is WRONG (that describes the experimental bundle).
  2. traefik v3.7 source `pkg/provider/kubernetes/gateway/client.go`
     lists/watches TCPRoute at **v1alpha2**
     (`Gateway().V1alpha2().TCPRoutes().Informer()`, `ListTCPRoutes` via
     `GatewayV1alpha2()`), while TLSRoute uses v1 — so traefik 3.7 REQUIRES
     a tcproutes CRD that serves v1alpha2.
  3. gateway-api v1.6.3 experimental CRD
     (`config/crd/experimental/...`) serves v1 (storage) + v1alpha2
     (served, deprecated) — the only variant that satisfies (2).
  4. Consequence: dev's k3s-provided standard tcproutes CRD (v1.6.1) is
     INSUFFICIENT for traefik TCPRoute too — both clusters need the
     repo-vendored experimental CRD. The forgejo subchart's v1alpha2 TCPRoute
     template matches traefik's client exactly.
  RESEARCH.md itself is not edited (research-owned artifact); this entry is
  the correction of record.
- 2026-10-23 plan: CRD ownership overlap ACCEPTED — k3s's `traefik-crd`
  helm release owns the same CRD object (standard variant on dev today; on
  infra after its next k3s upgrade). ArgoCD selfHeal restores the
  experimental variant within one refresh (~3 min) after any k3s re-apply
  (boot/chart-change only); transient TCPRoute watch breakage in that window
  accepted. Escape hatch if SSA field-manager conflicts instead:
  `argocd.argoproj.io/sync-options: Replace=true` annotation on the CRD.
  Rejected: k3s `gateway-api-crd` HelmChart (overlaps traefik-crd on the
  WHOLE CRD set → two k3s helm releases fighting), waiting for k3s upgrades
  (standard bundles never serve v1alpha2 — would never fix it).
- 2026-10-23 plan: chunking = C01 audit-trail move (S, branch bootstrap) /
  C02 base Gateway surface dormant (L) / C03 activation + notes (M, wave 2).
  Rejected: single mega-chunk (base blast radius deserves its own L review
  gate); per-instance custom-values activation (Q5 said both instances, one
  shared config).
- 2026-10-23 plan: forgejo-ssh Service stays **ClusterIP :22** (TCPRoute
  backend); NO LoadBalancer on the forgejo Service in this design (the LB is
  traefik's, gaining port 22222). Rejected: `service.ssh.type:
  LoadBalancer` (that is the ServiceLB-direct design the user rejected in
  Q4).

- 2026-10-23 human: **plan APPROVED** via question tool (option "Approve
  (Recommended)") — plan file 2026-10-23-feat-forgejo-ssh.md with chunks
  C01/C02/C03 as summarized in the approval prompt; STATE.json plan_status
  set to "approved".

## Deferred

- Public-internet git-SSH exposure (new edge design; user Q3 = mesh/LAN only).
- Node-sshd-off-:22 → port-22 clone URLs (user Q2 = no).
- Gateway API RBAC for the readonly MCP serviceaccount (hivetools
  ClusterRole; today 403 on gateway resources).
- Retire/adjust the vendored tcproutes CRD when k3s or traefik closes the
  v1alpha2 gap (watch item; resolves the dev ownership overlap).
- Dead `entryPoints:` block cleanup in traefik-config.yaml; stale
  `charts/traefik` wrapper appVersion.- 2026-10-24 cord (final whole-plan review, two non-blocking findings dispositioned): M1 (inaccurate clause "that no entrypoint in this config matches" in the web:null why-comment, charts/base/templates/traefik-config.yaml) — routed to dev, fixed in a8d3116ff (clause dropped, verified rationale kept; suite 49+6 re-greened, closed-gate byte-identity re-verified). M2 (plan User actions §3 said `--providers.kubernetesgateway=true`; the rendered arg has no `=true`) — plan-file wording fixed inline by coord. No further review round: the fix was comment-only and the full test suite re-walks the file structurally.
