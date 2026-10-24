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
- 2026-10-24 human (post-final-review, pre-merge): the vendored raw CRD template (`charts/base/templates/gateway-tcproute-crd.yaml`) is NOT the desired tracking form — CRDs must be pinned like chart dependencies. Directive: swap it for a pinned chart dependency if possible ("utilize it as a chart"); only if pinning requires re-implementation, remove the Gateway entirely (ServiceLB-direct fallback).
- 2026-10-24 cord: research verdict (RESEARCH-gateway-crd-chart.md, companion note): `gateway-api-crds` v1.2.5 from `https://charts.christianhuth.de` is the suitable pinned chart — experimental channel, tcproutes-only scoping possible, rendered CRD spec-IDENTICAL to the vendored v1.6.3 experimental CRD (parsed diff), renovate helms-manager trackable via standard Chart.yaml dep + lock (repo precedent: cert-manager in charts/base ships CRDs via its chart). Ruled out with evidence: k3s's own gateway-api-crd chart (experimental flag only adds x-k8s.io CRDs; tcproutes stays v1alpha2-not-served), wiremind (full 13-CRD bundle, one version behind), all other candidates standard-only or unchartable. → C04: swap the vendored template for the pinned dependency; the Gateway stays. CRD ownership overlap with k3s traefik-crd is unchanged (same selfHeal window / Replace=true escape hatch).
- 2026-10-24 plan: C04 contract written (chunks/C04.md) on the research verdict, design probe-verified with helm v3.16.4 (/tmp renders, worktree untouched): (a) gating replacement — chart deps render from STATIC values, so base defaults carry `gateway-api-crds.{enabled,standard.enabled,experimental.enabled}: false` (the Chart.yaml `condition: gateway-api-crds.enabled` key MUST exist in values: probe without it rendered the chart's 10-CRD default bundle on an uninvolved cluster); dev/infra re-enable exactly the experimental tcproutes CRD + `global.resourcePolicy.keep: true`, as a static block adjacent to `gitSshPort:`; gitSshPort remains the single semantic gate, the HelmChartConfig template gate untouched. (b) spec pin c29ee86ea554c32b83ca8ab6b07651a99e8d72345088f6b4f829b44ad700947e (canonical JSON of the rendered CRD spec — equal from the dependency render and the vendored template render). (c) renovate: NO `# sourceUrl:`/`# changelog:` annotation — built-in helmv3 manager tracks HTTP-repo Chart.yaml deps (argo-cd/cert-manager precedent); the repo's override regex would double-extract. (d) one comment-only fix inside the gate in traefik-config.yaml (stale vendored-template reference, M1-class). Supersedes the "Vendored CRD" convention bullet above and the C02 t2/t3 test contract (rewrite spec in chunks/C04.md); the `Replace=true` escape hatch moves to the ArgoCD Application layer (no repo template left to annotate).
- 2026-10-24 human: **C04 contract APPROVED** via question tool (option "Approve contract (Recommended)") — chunks/C04.md as written: static-values gating (default-OFF block + dev/infra companion block adjacent to gitSshPort), spec sha256 pin, comment-only traefik-config touch, no renovate annotation. Plan file updated (chunk table row, wave 3, Follow-up C04 section, Risks §1 wording, Commands).
- 2026-10-24 cord: C04 final disposition — review APPROVED at e3ca402ca (12/12 criteria; upstream chart fetched to confirm the default-OFF key paths; SPEC_PIN recomputed independently). M1 (stale "vendored tcproutes CRD gate" clause in the two gitSshPort comments) fixed in 2a5922e95 with the reviewer's wording, suite re-greened (67+6); comment-only, no extra review round (C02-M1 precedent). Ticket re-closed.
