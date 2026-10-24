# RESEARCH (companion) — Is there a pinnable Helm chart for the experimental-channel Gateway API CRDs (tcproutes v1alpha2)?

Date: 2026-10-24 · Commissioned follow-up to RESEARCH.md §F2 + the plan's
"RESEARCH.md correction" + DECISIONS.md v1alpha2 background. Method: live
ArtifactHub API sweep + `helm pull`/`helm template` inspection of every
candidate's actual CRD manifests (helm v3.16.4), 2026-10-24. This note does
not modify RESEARCH.md.

## TL;DR verdict

**YES — chart `gateway-api-crds`, version `1.2.5`, repository
`https://charts.christianhuth.de`, works, with values
`standard.enabled: false` + `experimental.enabled: true` (plus per-CRD
scoping to `tcproutes` only + `global.resourcePolicy.keep: true`).**

Its rendered experimental-channel tcproutes CRD is **spec-identical** to the
byte-verbatim vendored v1.6.3 experimental CRD in
`charts/base/templates/gateway-tcproute-crd.yaml` (verified by parsing both
renders and diffing `spec` — equal; both serve v1 served+storage and
v1alpha2 served). It is a drop-in replacement that converts the raw vendored
CRD into a `Chart.yaml` dependency + `Chart.lock`, tracked by renovate's
standard helm manager — the repo's cloudnative-pg-style pinning pattern the
user asked for. Runner-up: `wiremind/gateway-api-crds` v1.6.2 (simpler, but
always installs the FULL experimental bundle, no per-CRD scoping, no keep
policy, one bundle behind at v1.6.2).

No fallback needed — the Gateway design can keep its CRD and drop the raw
template.

## Requirement recap (what a candidate must satisfy)

1. Pinnable as a `Chart.yaml` dependency (HTTP/OCI helm repo; renovate-trackable).
2. Ships `tcproutes.gateway.networking.k8s.io` serving **v1alpha2** (traefik
   3.7's gateway provider lists/watches TCPRoute at v1alpha2 — DECISIONS.md
   correction, traefik `client.go`), i.e. the **experimental channel** CRD
   (v1.6.x standard channel sets v1alpha2 `served: false`).

## Candidate evidence

### Viable

| # | Chart | Repo | Latest (checked 2026-10-24) | Channel / bundle | tcproutes v1alpha2 |
|---|-------|------|------------------------------|------------------|--------------------|
| 1 | `gateway-api-crds` (christianhuth) | `https://charts.christianhuth.de` | **1.2.5** (appVersion v1.6.3, released 2026-10-12) | both channels, selectable | **served: true** ✅ |
| 2 | `gateway-api-crds` (wiremind) | `https://wiremind.github.io/wiremind-helm-charts` | **1.6.2** (== bundle version, released 2026-09-10) | experimental only, always | **served: true** ✅ |
| 3 | `gateway-helm` (envoy-gateway) | `oci://docker.io/envoyproxy/gateway-helm` | 1.9.2 (pulled 2026-10-24) | experimental v1.6.1 via `crds` subchart | served ✅ — but see reject reason |

**1. christianhuth/gateway-api-crds v1.2.5 — RECOMMENDED.** Pulled and
inspected: umbrella chart with two vendored subcharts (`standard`,
`experimental`), each gated by `condition:` (`standard.enabled` /
`experimental.enabled`); `templates/validate.yaml` fails the install if both
or neither are enabled. Experimental subchart tcproutes CRD:
`bundle-version: v1.6.3`, `channel: experimental`, versions `v1`
(served+storage) + `v1alpha2` (served, non-storage). Extras: per-CRD toggles
`experimental.crds.<plural>` (render-verified: with all-but-tcproutes false,
exactly one object renders — the tcproutes CRD), `global.resourcePolicy.keep:
true` adds `helm.sh/resource-policy: keep` to every CRD, JSON values schema,
GPG prov-signed, ArtifactHub verified publisher. Provenance: Chart.yaml
`sources: [https://github.com/kubernetes-sigs/gateway-api]`. Maintenance:
tracks every gateway-api release (index history: 1.2.5/v1.6.3 2026-10-12,
1.2.4/v1.6.2 2026-09-04, 1.2.3/v1.6.1 2026-08-17, 1.2.0/v1.6.0 2026-07-14,
1.1.1/v1.5.1, 1.0.0/v1.4.1…). CRDs live in `templates/` (not `crds/`), so
`helm upgrade` rolls the bundle forward. **Drop-in proof**:
`helm template` of the tcproutes-only configuration parsed and compared to
the base-chart render of the vendored CRD → `spec` byte-equivalent (same
channel/bundle annotations, same served/storage matrix).

**2. wiremind/gateway-api-crds v1.6.2 — runner-up.** Pulled and inspected:
zero-values chart; templates are the upstream `config/crd/experimental`
v1.6.2 files byte-verbatim (README documents the curl-from-upstream update
procedure; Chart.yaml `sources` → wiremind repo + kubernetes-sigs/gateway-api).
Rendered tcproutes: `channel: experimental`, bundle **v1.6.2**, v1
served+storage + v1alpha2 served ✅. Also ships the safe-upgrades
ValidatingAdmissionPolicy + x-k8s.io CRDs. ArtifactHub verified publisher
(Wiremind, French OSS-maintaining company), unsigned. History: 1.6.2
2026-09-10, 1.6.0 2026-07-09, 1.5.1 2026-03-25… (chart version == gateway-api
version — clean semver). Limitations vs christianhuth: always the FULL
13-CRD experimental bundle (no per-CRD scoping → ownership-overlap surface
with k3s traefik-crd grows from 1 CRD to 10), no `resource-policy: keep`,
and no v1.6.3 release yet (latest is v1.6.2, 6 weeks old at check time).

**3. envoy-gateway `gateway-helm` — viable CRDs, rejected as carrier.** The
chart's bundled `crds` subchart (gated on `crds.enabled`, default true)
contains the **experimental** bundle v1.6.1 — tcproutes serves v1alpha2 ✅.
But the CRDs are inseparable from a full Envoy Gateway control plane:
Deployment, certgen Job, RBAC, config — none of it gatable off (values +
templates inspected). Using it purely for CRDs would install an unwanted
second gateway controller. Also OCI-only. ❌ for this use.

### Not viable — standard channel only (confirmed on the actual CRD manifests, not assumed)

| Chart | Where | Evidence |
|-------|-------|----------|
| `gateway-api-crd` **k3s project** v1.6.301 (appVersion v1.6.3, released 2026-10-08) | **`https://k3s.io/k3s-charts`** — yes, k3s-charts IS a published helm repo (k3s-io.github.io 301→k3s.io) | Pulled 1.6.301: `values.yaml` = only `experimental.enabled: false`; templates glob `crdfiles/` (always) + `experimentalcrds/` (when enabled). `crdfiles/..._tcproutes.yaml`: `channel: standard`, v1 served+storage, **v1alpha2 served: false**. `experimental.enabled: true` ONLY adds the three `gateway.networking.x-k8s.io` CRDs — the core CRDs stay standard ❌. (Also: DECISIONS.md's rejection of it as a k3s HelmChart stands for that mechanism; as an ArgoCD dependency it would additionally overlap the WHOLE gateway CRD set with k3s's traefik-crd release.) |
| `gateway-api-crds` (spnngl) v1.6.6, OCI `oci://ghcr.io/spnngl/charts/gateway-api-crds`, verified+cosign, 2026-10-07 | ArtifactHub | Pulled: tcproutes `channel: standard`, v1 served+storage, v1alpha2 served: false ❌ (has `keepOnUninstall: true` default — nice, wrong channel) |
| `gateway-api-crds` (peterweissdk) v1.6.3, `https://peterweissdk.github.io/helm`, GPL-3.0, prov-signed, 2026-10-18 | ArtifactHub | Pulled: single `templates/crds.yaml`, all 10 CRDs `channel: standard` ❌ |
| `gateway-api-crds` (quenchworks) v0.0.1, OCI `oci://ghcr.io/quenchworks/charts/gateway-api-crds`, 2026-08-20 | ArtifactHub | Pulled: `templates/crds-standard.yaml` — "Ships the upstream Standard-channel release asset byte for byte" (their description, confirmed in-file) ❌ |
| `gateway-api-crds` (deimosfr) v1.6.1, `https://deimosfr.github.io/deimosfr-charts/`, 2026-08-04 | ArtifactHub | Pulled: tcproutes `channel: standard`, bundle v1.6.1, v1alpha2 served: false ❌ |
| `gateway-api-crds` (portefaix) v1.2.1 (app 1.2.0), `https://charts.portefaix.xyz/`, updated **2025-03-21** | ArtifactHub | Pulled: only 5 CRDs (gatewayclasses, gateways, grpcroutes, httproutes, referencegrants) — **no tcproutes at all** ❌ + stale 19 months |

### No chart exists

- **Upstream `kubernetes-sigs/gateway-api`**: publishes no Helm chart. Install
  docs (gateway-api.sigs.k8s.io guides page, fetched 2026-10-24) are
  `kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/vX/{standard,experimental}-install.yaml`
  (or `kubectl kustomize config/crd`); CRD management otherwise delegated to
  gateway controllers. The ArtifactHub sweep above is the complete set of
  third-party chart wrappers.
- **Istio**: docs ("Kubernetes Gateway API" task, fetched 2026-10-24) tell
  users to install the CRDs manually (`kubectl kustomize
  github.com/kubernetes-sigs/gateway-api/config/crd`); istio's charts ship no
  Gateway API CRDs ❌.
- **kgateway (solo.io Gloo successor)**: `kgateway-crds` chart (OCI
  `cr.kgateway.dev`) contains only `gateway.kgateway.dev` CRDs; the main
  chart has no `gateway.networking.k8s.io` CRD templates (pulled + grepped
  2026-10-24) ❌.
- **Cilium**: chart has `gatewayAPI.enabled` but ships no Gateway API CRD
  templates (grep of pulled chart found none) ❌.
- **Traefik chart**: k3s-stock 40.1.5 (the dev/infra chart, pulled from
  k3s.io/k3s-charts 2026-10-24) has **no `crds/` directory at all** and no
  CRD-install values flag — `templates/gateway.yaml`/`gatewayclass.yaml` are
  Gateway/GatewayClass *objects*; the gateway CRDs come from k3s's separate
  `traefik-crd` chart, which is standard-channel only (RESEARCH.md F2/[6]).
  Upstream traefik-helm-chart removed Gateway API CRDs entirely
  (RESEARCH.md [7], verified 2026-10-23). ❌ No experimental-CRD surface.

## Recommended wiring (if adopted)

Drop `charts/base/templates/gateway-tcproute-crd.yaml` and instead:

```yaml
# charts/base/Chart.yaml — third dependency alongside argo-cd + cert-manager
- name: gateway-api-crds
  version: 1.2.5
  repository: https://charts.christianhuth.de
  condition: gateway-api-crds.enabled   # per-cluster gate
```

```yaml
# charts/base/values.yaml — default OFF (helm loads a conditioned subchart
# when the condition path is ABSENT, so the key must exist here, or every
# base-managed cluster would get the CRDs and hit the chart's
# neither-channel-enabled fail)
gateway-api-crds:
  enabled: false
  standard:
    enabled: false
  experimental:
    enabled: false
```

```yaml
# services/dev/prod/values.yaml AND services/infra/prod/values.yaml
# (replaces the gitSshPort gating of the CRD template; the gitSshPort gate
# on the traefik HelmChartConfig block stays)
gateway-api-crds:
  enabled: true
  standard:
    enabled: false
  experimental:
    enabled: true
    crds:
      # experimental tcproutes ONLY — everything else stays owned by k3s's
      # traefik-crd release, keeping the ownership-overlap surface at 1 CRD
      backendtlspolicies: false
      gatewayclasses: false
      gateways: false
      grpcroutes: false
      httproutes: false
      listenersets: false
      referencegrants: false
      tlsroutes: false
      udproutes: false
      xbackends: false
      xbackendtrafficpolicies: false
      xlistenersets: false   # no template today; explicit for forward-compat
      xmeshes: false
  global:
    resourcePolicy:
      keep: true   # uninstall of the release must not cascade-delete the CRD
```

Mechanics that match existing repo practice:

- Value flow to base is unchanged (umbrella `values.yaml` → appset
  valueFiles → base chart; same as the existing `cert-manager:` /
  `argo-cd:` subchart overrides in `charts/base/values.yaml`).
- `charts/base` already installs CRDs via a chart dependency
  (`cert-manager.crds.enabled: true`) — the ArgoCD-handles-CRDs-in-deps
  pattern exists; the released-base-chart packaging (chart-releaser with
  `helm dependency build`) already vendors dep charts into the tgz
  (argo-cd, cert-manager), so gateway-api-crds needs no CI change.
- renovate: standard helms manager tracks `Chart.yaml` deps from HTTP repos
  with zero config changes (same as argo-cd/cert-manager/cloudnative-pg);
  christianhuth's Chart.yaml `sources` field points at
  kubernetes-sigs/gateway-api, so changelog linking works without the repo's
  `# sourceUrl:` override manager.

## Caveats

1. **CRD ownership overlap — unchanged by this switch.** k3s's `traefik-crd`
   helm release still owns `tcproutes.gateway.networking.k8s.io` (standard
   variant on dev today; on infra after its next k3s upgrade). The ArgoCD
   selfHeal ~3-min restore window and the `Replace=true` escape hatch from
   DECISIONS.md carry over verbatim. tcproutes-only scoping keeps the
   footprint at exactly 1 CRD, same as the vendored design. (Choosing the
   FULL experimental bundle instead — one less values block — would extend
   the overlap to all 10 standard-channel CRDs and add the 3 x-k8s.io ones;
   not recommended.)
2. **Maintainer risk.** christianhuth is a single independent maintainer
   (bus factor 1); the chart is thin (vendored upstream CRDs + toggles +
   schema), GPG-signed, ArtifactHub-verified, and has tracked every
   gateway-api release since v1.4.1 without a missed one. Fallbacks exist:
   wiremind (org-maintained, verified) or re-vendoring. A pinned version +
   Chart.lock (index.yaml digest-verified pulls) bounds supply-chain drift.
   Chart.yaml has no `license` field (ArtifactHub shows none); the vendored
   CRDs themselves are upstream Apache-2.0.
3. **Upgrade story when traefik moves off v1alpha2** (plan follow-up
   already tracks this): the chart makes it a values flip —
   `experimental.enabled: false` + `standard.enabled: true` (both bundles
   ship in every chart version) — or delete the dependency entirely once
   k3s's standard bundle suffices. No re-vendoring. Bundle bumps arrive as
   renovate chart-version PRs.
4. Cosmetic: christianhuth re-indents the upstream YAML (spec-equivalent,
   proven above) and does not ship the safe-upgrades
   ValidatingAdmissionPolicy (wiremind/quenchworks/deimosfr do; k3s's bundle
   doesn't either — not a regression).

## Alternative pinning mechanisms (sanity check, item 4)

- **Raw vendored YAML + renovate regex** (the shipped design): the repo DOES
  have regex-manager precedent for pinning non-helm artifacts
  (`k3s-version.yaml` github-releases manager, Dockerfile `# renovate:` ARG
  pins), so a `# renovate:` comment tracking the bundle-version annotation
  would be implementable — but it is precisely the "raw vendored CRD" the
  user objected to, plus a new custom manager.
- **kustomize-pinned upstream YAML**: no kustomize anywhere in the repo
  (ArgoCD + Helm umbrellas only); adopting it for one CRD is a new pattern.
- **Flux/helm-controller-style CRD references**: no Flux. The one
  helm-controller lever native to this stack (k3s HelmChart consuming the
  published k3s `gateway-api-crd` chart) cannot work regardless: that chart
  is standard-channel for the core CRDs (verified above) and would fight
  `traefik-crd` under k3s's own helm-controller (DECISIONS rejection stands).
- → **A `Chart.yaml` dependency is the only repo-consistent mechanism that
  satisfies the user's "pinned like a chart dependency" requirement — and
  with christianhuth v1.2.5 (+ wiremind as backup) a suitable chart exists.**

## Sources (all fetched/pulled 2026-10-24 unless noted)

- S1 ArtifactHub search API `ts_query_web=gateway-api-crds&kind=0` — 7 distinct
  publishers enumerated (wiremind, portefaix, spnngl, peterweissdk,
  quenchworks, christianhuth, deimosfr) + envoy-gateway/kgateway hits.
- S2 helm pulls + template renders of: christianhuth/gateway-api-crds 1.2.5;
  wiremind/gateway-api-crds 1.6.2; deimosfr 1.6.1; peterweissdk 1.6.3;
  spnngl 1.6.6 (OCI); quenchworks 0.0.1 (OCI); portefaix 1.2.1; k3s
  gateway-api-crd 1.6.301 (repo https://k3s.io/k3s-charts); envoy-gateway
  gateway-helm 1.9.2 (OCI docker.io); kgateway + kgateway-crds (OCI
  cr.kgateway.dev); cilium/cilium (helm.cilium.io); traefik
  40.1.5+up40.1.0 tgz from k3s.io/k3s-charts.
- S3 Repo index histories: https://charts.christianhuth.de/index.yaml,
  https://wiremind.github.io/wiremind-helm-charts/index.yaml,
  https://k3s.io/k3s-charts/index.yaml.
- S4 gateway-api.sigs.k8s.io "Getting started / Installing Gateway API" —
  no official chart; release-YAML install only.
- S5 istio.io "Kubernetes Gateway API" task doc — manual CRD install, no
  chart surface.
- S6 Semantic diff: `helm template` of christianhuth tcproutes-only render vs
  base-chart render of `charts/base/templates/gateway-tcproute-crd.yaml`
  (both parses, `spec` equal, channel/bundle/served matrix equal).
- S7 RESEARCH.md F2/[6][7] + DECISIONS.md (2026-10-23) for the v1alpha2
  requirement and prior verifications (traefik client.go v1alpha2 watch;
  traefik chart CRD removal; k3s traefik-crd standard bundle).