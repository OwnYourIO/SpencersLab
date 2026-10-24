# PLAN: Expose Forgejo git-over-SSH to LAN/mesh via Gateway API (dev + infra)

feature: 2026/2026-10-feat-forgejo-ssh

## Goal

Expose git-over-SSH for BOTH Forgejo instances — dev (`git.scifi.farm`, dev
cluster) and infra (`git.spencerslab.com` + `forgejo.spencerslab.com` alias,
infra cluster) — to mesh/LAN clients on port **22222**, using the **Gateway
API** path (traefik `kubernetesGateway` provider + a `gitssh` listener +
TCPRoute per instance), repo-managed end to end. Today `dev-forgejo-ssh` /
`infra-forgejo-ssh` are ClusterIP-only and port 22 on the git hosts lands on
the node sshds. RESEARCH.md (this folder, commissioned) is ground truth; the
v1alpha2 CRD correction in "Decisions" below amends it.

## Out of scope

- **Public-internet SSH exposure** — user chose mesh/LAN only; proxy-remote
  stays untouched (its autossh :443 tunnel can't carry raw TCP anyway).
- **Moving node sshd off :22** — user chose to keep it; scp-style
  `git@host` port-22 clone URLs therefore remain impossible (documented, not
  built).
- ServiceLB-direct and IngressRouteTCP designs — rejected by the user's
  mechanism choice (Gateway API now).
- Any Keycloak/Bitwarden/DNS changes — none needed (identity unchanged; the
  git hosts already resolve to the node IPs the traefik ServiceLB advertises).
- Unit tests — none in this repo; validation scripts + helm renders ARE the
  tests (`tests/services/`).

## Decisions (user, 2026-10-23, question round — verbatim answers)

| # | Question | Answer |
|---|---|---|
| Q1 | External SSH port | **22222** (typed answer; not one of the offered options 2222/2200/2223) |
| Q2 | Move node sshd off :22? | **"No, keep sshd on :22 (Recommended)"** — ssh:// URLs with port are permanent |
| Q3 | Network exposure | **"Mesh/LAN only (Recommended)"** |
| Q4 | Mechanism | **"Gateway API now"** (traefik kubernetesGateway provider + Gateway + TCPRoute) |
| Q5 | Instances & ordering | **"Both, dev verified first (Recommended)"** — one shared config, verify dev end-to-end before infra |
| Q6 | Entrypoint gating (implicit in Q4) | Gated to dev+infra via a per-service `gitSshPort` value, `seaweedVolumePort` pattern (planner decision, presented for plan approval) |

Design decisions made by the planner on top of the answers (full rationale +
rejected alternatives in DECISIONS.md):

- **Gate key `gitSshPort: 22222`** set top-level in `services/dev/prod/` and
  `services/infra/prod/` values; everything Gateway-related in the base chart
  renders only when it is set (other clusters untouched — the base chart is
  cluster-wide).
- **Gateway objects come from the k3s-stock traefik chart itself**
  (chart-default `gateway.enabled`/`gatewayClass.enabled` + a `gitssh`
  listener added via the repo-managed HelmChartConfig); the chart's default
  `web` listener is explicitly nulled. Repo templates add only ONE object:
  the TCPRoute, via the forgejo subchart's shipped `tcpRoute` values surface.
- **Vendored CRD**: `tcproutes.gateway.networking.k8s.io`, **experimental
  channel v1.6.3** (serves v1 AND v1alpha2), as a new `gitSshPort`-gated
  template in `charts/base/`. Needed on BOTH clusters: traefik 3.7's gateway
  provider lists TCPRoute at **v1alpha2**, and the k3s standard-channel
  bundle does not serve v1alpha2 (see correction below).
- **Shared forgejo chart config** (both instances, Q5): `SSH_PORT: 22222` +
  `tcpRoute.enabled` in `charts/forgejo/values.yaml`; the ssh Service itself
  stays ClusterIP :22 (the TCPRoute's backend).

## RESEARCH.md correction (planner, 2026-10-23, evidence in DECISIONS.md)

RESEARCH F2/source [4] states the v1.6.3 **standard** TCPRoute CRD serves
v1alpha2 ("served, deprecated"). **False** — verified against the actual CRD
manifests: v1.6.0/1/3 standard all set v1alpha2 `served: false`; only the
**experimental** channel CRD serves it. Combined with traefik v3.7 source
(`client.go` lists `Gateway().V1alpha2().TCPRoutes()`), this means: the
standard CRDs on dev (v1.6.1) are INSUFFICIENT for traefik TCPRoute; both
clusters need the experimental-channel tcproutes CRD, and the forgejo
subchart's v1alpha2 TCPRoute template is exactly what traefik expects.

## Follow-up C04 (2026-10-24, user-directed)

After final review (C01–C03 APPROVED, PR open, unmerged) the user directed a
design change: the vendored raw CRD template is not the desired tracking
form — CRDs must be pinned like chart dependencies ("utilize it as a
chart"). The commissioned follow-up research
(`RESEARCH-gateway-crd-chart.md`, this folder — ground truth for C04) found
the carrier: `gateway-api-crds` **v1.2.5** from
`https://charts.christianhuth.de` — experimental channel, per-CRD scoping
(tcproutes only), rendered CRD spec-IDENTICAL to the vendored v1.6.3
experimental CRD (parsed-spec diff; re-proven in C04 planning: canonical
spec sha256 `c29ee86e…00947e` from both render sources), renovate-trackable
as a standard Chart.yaml dep + Chart.lock (repo precedent: cert-manager in
charts/base ships CRDs via its chart dependency).

C04 therefore swaps `charts/base/templates/gateway-tcproute-crd.yaml` for
that pinned dependency. The design crux it resolves: chart-dependency
rendering is driven by STATIC values, not template gates — the `gitSshPort`
`{{- if }}` cannot wrap a subchart. Replacement gating: base default values
disable the dependency entirely (`condition:` key present and false —
research gotcha, probe-proven: an absent key gives every cluster the chart's
default CRD bundle), dev+infra service values re-enable exactly the
experimental tcproutes CRD (+ resourcePolicy keep) as the companion wiring
next to `gitSshPort: 22222`, and the gitSshPort template gate on the
traefik HelmChartConfig block stays untouched. This section SUPERSEDES the
"Vendored CRD" decision bullet above and the C02 t2/t3 test contract (the
test rewrite spec is in chunks/C04.md). CRD ownership overlap with k3s's
traefik-crd is semantically unchanged — see Risks §1.

## Verified repo/cluster context (2026-10-23, this session)

- `charts/forgejo` — wrapper v1.0.5, subchart forgejo 17.2.0 (OCI,
  `helm dependency build` verified; digest sha256:391648fe…). Subchart
  values: `service.ssh {type: ClusterIP, port: 22}`,
  `gitea.config.server.SSH_PORT: 22` / `SSH_LISTEN_PORT: 2222`,
  `tcpRoute {enabled: false, parentRefs: [], port: }` with a
  **v1alpha2 TCPRoute template** (`<fullname>-ssh` → backend
  `<fullname>-ssh:service.ssh.port`). `_helpers.tpl` SSH_PORT auto-follow is
  dead code once SSH_PORT is set (set it explicitly — confirmed in source).
- Baseline render (this session): `forgejo-ssh` Service ClusterIP :22→ssh;
  inline-config Secret `SSH_PORT=22`, `SSH_LISTEN_PORT=2222`,
  `START_SSH_SERVER=true`. Fix mechanism render-verified via `--set`:
  Service stays ClusterIP, `SSH_PORT=22222` lands in inline-config, TCPRoute
  renders with parentRefs/backendRefs.
- `charts/base/templates/traefik-config.yaml` — HelmChartConfig, the applied
  config surface on dev/infra k3s-stock traefik (live args match it). The
  `seaweedVolumePort` gate pattern (top-level service value → base template
  `{{- if index .Values ... }}`) is the precedent for `gitSshPort`. NOTE: the
  existing `entryPoints:` block in it is chart-ignored dead weight — the
  chart derives entrypoints from `ports.*` (`--entrypoints.<name>.address`
  args, verified in chart `_podtemplate.tpl`).
- k3s-stock traefik chart **40.1.5+up40.1.0** sources (k3s-charts, fetched
  this session): `providers.kubernetesGateway.{enabled,experimentalChannel}`;
  `gateway.yaml` gated on `gateway.enabled AND providers.kubernetesGateway.
  enabled`, default name **traefik-gateway** in Release.Namespace
  (kube-system), each listener's port MUST appear in `ports.*`, listener
  `namespacePolicy` → `allowedRoutes.namespaces`, protocol TCP needs no cert;
  `gatewayclass.yaml` renders GatewayClass **traefik**
  (controllerName traefik.io/gateway-controller) under the same gate;
  ClusterRole adds tcproutes/tlsroutes/gateways RBAC under the same gate;
  Service gains a port per `ports.*.expose.default: true` → ServiceLB hostPort.
- Value flow to base: each service umbrella's `templates/appset.yaml` deploys
  the **base chart from the released chart repo** (`baseChartVersion`, renovate-
  bumped) with the umbrella's whole `values.yaml` + `customValuesUrls` as
  valueFiles — so top-level `gitSshPort` reaches base. Internal charts
  (forgejo) are consumed straight from `main` (no release lag).
- Worktree: DETACHED HEAD at main tip `0fb23dde3`; branch
  `feat-forgejo-ssh-ssh` does not exist yet — C01 creates+attaches it (repo
  hard rule: never commit detached). Untracked `storm-runs/` at the repo root
  = this ticket's research audit trail (perspectives.md; raw/ empty).
- `tests/services/` exists (audit-trail.sh, infra-forgejo.sh,
  dev-forgejo-runner.sh, dev-git-auth.sh — predecessor contracts; stay green
  as regression unless their surfaces are touched by this ticket — they are
  not).
- helm v3.16.4 at `~/.local/bin/helm` (not on default PATH).

## Commands

Dependency builds first (vendored charts are gitignored for these paths):

```
export PATH="$HOME/.local/bin:$PATH"
helm dependency build charts/forgejo        # OCI pull (anonymous, public)
helm dependency build charts/base           # argo-cd + cert-manager + gateway-api-crds (C04)
helm dependency build services/infra/prod   # cloudnative-pg + samba
```

Chart-level (C02/C03/C04 surfaces; C04 replaced the gated CRD template with
the condition-gated gateway-api-crds dependency, so the CRD now renders from
the subchart — no `--show-only` for it, full-render parse asserts instead):

```
helm lint charts/base
helm lint charts/forgejo
# gate CLOSED (default values): no kubernetesGateway / gitssh / Gateway in
# the HelmChartConfig, and NO gateway.networking.k8s.io CRD anywhere
# (condition key default-off skips the gateway-api-crds subchart entirely)
helm template base charts/base --set serviceName=dev --show-only templates/traefik-config.yaml
helm template base charts/base --set serviceName=dev   # parse: 0 CRDs named *.gateway.networking.k8s.io
# gate SEPARATION (C04): gitSshPort alone opens the HelmChartConfig surface
# but renders NO gateway CRD — the CRD needs the static enable values
helm template base charts/base --set serviceName=dev --set gitSshPort=22222
# gate OPEN (real values): full gitssh block + the dependency-rendered
# experimental tcproutes CRD (v1.6.3, v1+v1alpha2, resource-policy keep)
helm template base charts/base -f services/dev/prod/values.yaml --set domain=scifi.farm --set clusterName=dev --set serviceName=dev
helm template charts/forgejo --set domain=test.example.com \
  --set bitwardenIds.forgejo=u --set bitwardenIds.forgejo-admin=u \
  --set bitwardenIds.forgejo-pg=u --set bitwardenIds.forgejo-sso=u
```

Service umbrellas (sentinels resolved via --set; test scripts pin the lists):

```
helm template services/dev/prod --set domain=scifi.farm --set subDomain=dev --set clusterName=dev \
  --set bitwardenIds.cert-manager-solver-token=u --set bitwardenIds.argocd-sso-secret=u \
  --set bitwardenIds.github-pat=u --set bitwardenIds.forgejo-token=u \
  --set hivetools.bitwardenIds.mcp-sso=u --debug
helm template services/infra/prod --set domain=spencerslab.com --set clusterName=infra \
  --set bitwardenIds.keycloak=u --set bitwardenIds.keycloak-pg=u --set bitwardenIds.smtp=u \
  --set hivetools.bitwardenIds.mcp-pg-keycloak=u \
  --set forgejo.bitwardenIds.forgejo=u --set forgejo.bitwardenIds.forgejo-admin=u \
  --set forgejo.bitwardenIds.forgejo-pg=u --set forgejo.bitwardenIds.forgejo-sso=u --debug
```

Sentinel sweep (no new sentinels in this ticket; existing ones stay 1:1 with
custom-values; NO `OVERRIDE_*` in any rendered output):

```
grep -rn 'OVERRIDE_VIA_CUSTOM_VALUES' charts/forgejo services/dev/prod/values.yaml services/infra/prod/values.yaml
```

Service-trio greps (SSH adds NO new ingress/proxy leg — the trio for forgejo
is unchanged; gitSshPort is the new wiring):

```
grep -n 'gitSshPort' services/dev/prod/values.yaml services/infra/prod/values.yaml
grep -n 'SSH_PORT\|tcpRoute' charts/forgejo/values.yaml
```

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Relocate research audit trail + bootstrap branch | S | 1 | [] | — (first dev commit; creates/attaches `feat-forgejo-ssh-ssh`) |
| C02 | Gateway API surface in the base chart (dormant) | L | 1 | [] | adds the interface: HelmChartConfig gitssh block + experimental tcproutes CRD, gated on `gitSshPort`; renders nothing until C03 sets the value |
| C03 | Activate git-SSH on dev+infra (values + forgejo chart) + operator notes | M | 2 | [C02] | consumes C02's surface: `gitSshPort: 22222` in both service umbrellas, `SSH_PORT`+`tcpRoute` in charts/forgejo; parentRefs target C02's Gateway |
| C04 | Swap the vendored tcproutes CRD template for a pinned gateway-api-crds chart dependency (user-directed follow-up) | M | 3 | [C02, C03] | removes C02's CRD template and re-gates CRD rendering through static enable values in C03's two umbrella files; both must be landed so the swap is one atomic commit with no moment dev/infra lack the CRD |

## Wave order

1. C01, C02 — wave 1, independent (no shared files); run in id order so C01's
   commit is the feature's first dev commit (branch bootstrap).
2. C03 — wave 2 after C02: its TCPRoute parentRefs and the gate value only
   make sense against C02's rendered surface, and its render assertions
   validate C02+C03 together.
3. C04 — wave 3 after C02+C03 (added 2026-10-24, user-directed): it deletes
   the CRD template C02 added (flipping C02's t2/t3 test slices) and moves
   CRD enablement into the same umbrella values files C03 created, next to
   `gitSshPort`. Running it after both means the open-gate render for
   dev/infra never loses the CRD mid-branch and the test rewrite has a
   settled surface to assert against.

## User actions

**Before/at merge (none blocking).** No Bitwarden, Keycloak, or DNS changes.

**Post-sync verification (user-run kubectl — the readonly MCP serviceaccount
has no Gateway API RBAC):**

1. Confirm port 22222 was free on both nodes: `ss -tlnp | grep 22222`
   (expect nothing) — if something holds it, svclb stays Pending.
2. Sync order lands: merge → CI releases new base chart → renovate bumps
   `baseChartVersion` in both umbrellas → ArgoCD syncs base (HelmChartConfig +
   CRD) → k3s helm-controller redeploys traefik → forgejo apps sync (may land
   FIRST — a TCPRoute before its Gateway just stays unattached, self-heals).
3. dev: `kubectl -n kube-system get gateway traefik-gateway -o yaml` →
   Accepted/Programmed True; `kubectl get tcproutes -A` → dev-forgejo-ssh
   Accepted; svclb-traefik pods Running with hostPort 22222; traefik args
   contain `--providers.kubernetesgateway` +
   `--providers.kubernetesgateway.experimentalchannel=true`.
4. dev functional: `ssh -p 22222 git@git.scifi.farm` → Forgejo SSH banner
   (NOT the node sshd banner); Forgejo UI clone URLs show
   `ssh://git@git.scifi.farm:22222/...`; a real clone/push over SSH works.
5. infra: repeat 3–4 for `git.spencerslab.com` (and confirm the
   `forgejo.spencerslab.com` UI shows the same ssh:// URLs).
6. If infra's Gateway provider didn't come up (CRD-vs-provider race):
   `kubectl -n kube-system rollout restart deploy/traefik` once.

**Client migration (after verification):**

7. Existing remotes: `git remote set-url origin ssh://git@<host>:22222/<owner>/<repo>.git`,
   OR keep scp-style URLs with an `~/.ssh/config` block:
   `Host git.scifi.farm` / `Port 22222` (also fixes `coder gitssh` in dev
   workspaces, which forwards ssh args incl. `-p`).
8. known_hosts: one-time accept prompt for the new `[host]:22222` entry —
   host keys are unchanged (persisted on the forgejo PVCs).
9. Port 22 on the git hosts remains the NODE sshd — don't git-clone on :22.

## Risks / assumptions

- **CRD ownership overlap (accepted)**: the repo-managed experimental
  tcproutes CRD collides with k3s's `traefik-crd` helm release ownership —
  on dev immediately (k3s ships the standard variant), on infra after its
  next k3s upgrade. k3s re-applies only at boot/chart-change; ArgoCD
  selfHeal restores the experimental variant within one refresh (~3 min).
  Transient TCPRoute breakage only in that window. C04 changes the carrier
  (pinned `gateway-api-crds` chart dependency instead of a vendored
  template), NOT the overlap semantics: still exactly 1 CRD, same selfHeal
  window, and the dependency's `helm.sh/resource-policy: keep` additionally
  keeps a base-release uninstall from cascade-deleting a CRD k3s also owns.
  If ArgoCD SSA hits a field-manager conflict instead, remediate at the
  ArgoCD Application layer — since C04 the CRD renders from the dependency
  chart, so there is no repo template left to annotate with
  `argocd.argoproj.io/sync-options: Replace=true` (the C02-era escape
  hatch; it was never needed).
- **Port 22222 assumed free** on both nodes (nothing known binds it; not
  verifiable via MCP) — verified at rollout by svclb readiness.
- **traefik TCPRoute client is pinned to v1alpha2** in 3.7.x — a future
  traefik/k3s upgrade may switch to v1; the vendored CRD + subchart template
  must be revisited then (follow-up).
- **Base chart release lag**: base changes reach clusters only after the CI
  chart release + renovate `baseChartVersion` bump; the forgejo half lands at
  merge. The interim (TCPRoute present, Gateway absent) is a valid pending
  state, not a failure.
- k3s-stock chart values schema drift on upgrades (the HelmChartConfig block
  targets 40.1.x) — re-check after k3s upgrades.
- Host keys persist on the data PVCs (docs-verified in RESEARCH F4;
  fingerprint check at rollout is cheap).

## Follow-ups (not in this ticket)

- Retire/adjust the vendored tcproutes CRD when (a) k3s bundles
  experimental-channel gateway CRDs or (b) traefik's gateway provider moves
  to v1 TCPRoute — watch both; also resolves the dev ownership overlap.
- Gateway API RBAC for the readonly MCP (hivetools kubernetes-mcp
  ClusterRole: gateways/tcproutes + status) so agents can verify Gateway
  state directly.
- Public-internet git-SSH (needs a new edge design — user deferred, Q3).
- `charts/traefik` wrapper stale appVersion 2.11.10 (RESEARCH adjacent).
- Dead `entryPoints:` block in traefik-config.yaml (chart-ignored; cleanup
  candidate — do NOT bundle into this ticket).
- If node sshd ever moves off :22 (user said no for now): switch the gitssh
  listener + SSH_PORT to 22 for scp-style clone URLs.