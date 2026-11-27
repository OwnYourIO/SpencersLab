# EXPLORE — cf-156 feat-actual-budget-mcp-server

Role: `agent-explore` (read-only scout). Ticket AD-156: (1) third Actual Budget
instance for "wuulf", (2) research + host an MCP server giving the agent
exports of Actual Budget data (payments-grouped vs item-level) and
reconcile/split/assign capabilities.
Run posture: uncommitted, in place on `main` in `/home/coder/SpencersLab`
(tree was clean at start; no commits made by this scout).

Everything below is grounded from the repo tree, live cluster state
(readonly k8s MCP), or live Keycloak DB (readonly Postgres MCP). Un-grounded
items are in §8.

---

## 1. The two existing Actual Budget instances (grounded)

### Instance 1 — "budget" (the original; NOT the standalone chart)

- Deployed as an **app-template subchart of the `home` umbrella**, not via the
  `charts:` key. `services/home/prod/Chart.yaml:70-73` —
  `- name: app-template / version: 5.0.1 / alias: actualbudget`.
- Values: `services/home/prod/values.yaml:877-939`, top-level `actualbudget:`
  block — `global.nameOverride: actualbudget`, controller `actual`, container
  `main`:
  - image `ghcr.io/actualbudget/actual-server:26.10.0@sha256:24645e97…860c`
  - env: `TZ: America/Denver`, `ACTUAL_PORT: 5006`, `ACTUAL_DATA_DIR: /data`,
    `ACTUAL_MULTIUSER: "true"`; `envFrom: secretRef actualbudget-sso-secret`
  - **initContainer `01-enable-openid`** (`npm run enable-openid --prefix /app || true`)
    — present here only, NOT in the standalone chart and NOT on bri-budget (live).
  - securityContext: readOnlyRootFilesystem, drop ALL caps,
    pod `runAsNonRoot: 1000`, `fsGroupChangePolicy: Always`.
- SSO ExternalSecret (umbrella template):
  `services/home/prod/templates/secret-actualbudget-sso.yaml` —
  ExternalSecret→Secret `actualbudget-sso-secret` (ns `default`), one
  Bitwarden item, three pulls:
  - `bitwarden-login` `username` → `ACTUAL_OPENID_CLIENT_ID`
  - `bitwarden-login` `password` → `ACTUAL_OPENID_CLIENT_SECRET`
  - `bitwarden-uri` (item URI) → `ACTUAL_OPENID_DISCOVERY_URL`
  - plus rendered constants `ACTUAL_OPENID_SERVER_HOSTNAME: "https://login.{{ .Values.domain }}"`,
    `ACTUAL_OPENID_ENFORCE: "true"`, `ACTUAL_USER_CREATION_MODE: "login"`.
- PVC (umbrella template): `services/home/prod/templates/actualbudget-pvc-default.yaml`
  — `actualbudget-data`, RWO, 5Gi.
- Ingress: `services/home/prod/values.yaml:182-187` — TWO subdomains both
  pointing at `service: home-actualbudget`, `port: 5006`: `budget:` and
  `actualbudget:` (hosts `budget.<domain>`, `actualbudget.<domain>`;
  host built by `services/home/prod/templates/generic-ingress.yaml:14`,
  TLS `wildcard-cert`).
- Proxy-local: `services/proxy-local/prod/values.yaml:210-213` —
  `budget: {target: budget, ssoRedirectPath: "/realms/$.Values.authRealm/protocol/openid-connect/auth?loginStyle=redirect&client_id=actualbudget&response_type=code&redirect_uri=https://budget.$.Values.domain/account/login", loginSubDomain: "login"}`.
  (No `actualbudget:` proxy-local entry exists — only `budget` and `bri-budget`.)
- Proxy-remote: `services/proxy-remote/prod/values.yaml:88-89` — `budget: {enabled: true}`.

### Instance 2 — "bri-budget" (Brianna's; the pattern to copy)

Added by commits `217dae71d` (chart + appset entry + ingress + values block),
`cce60c729` (custom-values + SSO secret template + proxy-local),
`0bcc88d37` (proxy-remote).

- **Standalone chart** `charts/actualbudget/`:
  - `Chart.yaml`: `version: 1.0.4`, `appVersion: 26.7.0` (stale vs image tag
    26.10.0 — cosmetic; do NOT hand-bump versions, `release.yaml` owns that).
  - dep: app-template 5.0.1 (`Chart.lock` digest
    `sha256:0ea7893a…b9b`); **no vendored `charts/*.tgz` in git** — local
    `helm template` needs `helm dependency update` first (I did this on a
    /tmp copy, repo untouched).
  - `values.yaml` (60 lines): same image/env/security as instance 1 minus the
    initContainer; `persistence.data.existingClaim: '{{ index .Values "global" "nameOverride" | default .Chart.Name }}-data'`
    (`values.yaml:49`) — this is what makes one chart serve N instances.
  - `templates/pvc-data-default.yaml`: PVC `<nameOverride>-data`, RWO, 5Gi.
  - No secret templates, no bitwardenIds in the chart — SSO rides the shared
    umbrella ExternalSecret via hardcoded `envFrom` name.
- Deploy wiring, all in `services/home/prod/values.yaml`:
  - `charts: bri-budget: {namespace: default, ServerSideApply: "true", chart: actualbudget}`
    (lines 97-100) → ArgoCD Application `home-bri-budget` via the `chart:`
    field branch of `charts/base/templates/appset-charts.yaml:64-70`
    (git path source → `charts/actualbudget` on `main`).
  - Per-instance values block, lines 946-949 — **the entire per-instance
    config is one key**:
    ```yaml
    bri-budget:
      app-template:
        global:
          nameOverride: bri-budget
    ```
  - Ingress, lines 188-190: `bri-budget: {service: home-bri-budget, port: 5006}`.
- custom-values: `custom-values/home/prod-values.yaml:31-33`
  `bri-budget: bitwardenIds: actualbudget-sso-secret: 3f3ebb88-bded-44bf-afc9-b49d00225182`
  (duplicated top-level at :29 and under `actualbudget:` at :35-37 — the
  per-app blocks are belt-and-braces; the only *consumer* of the UUID is the
  umbrella template reading top-level `bitwardenIds.actualbudget-sso-secret`).
- Proxy-local: `services/proxy-local/prod/values.yaml:206-209` —
  `bri-budget: {target: bri-budget, ssoRedirectPath: …client_id=actualbudget…redirect_uri=https://bri-budget.$.Values.domain/account/login…, loginSubDomain: "login"}`.
- Proxy-remote: `services/proxy-remote/prod/values.yaml:90-91` — `bri-budget: {enabled: true}`.

### Render-verified shape of a third instance (I rendered the chart)

`helm template home-wuulf-budget charts/actualbudget --set app-template.global.nameOverride=wuulf-budget`
(passes; app-template 5.0.1) produces: ServiceAccount/PVC/Service/Deployment —
Service+Deployment named **`home-wuulf-budget`** (release name wins because the
release contains the nameOverride), PVC **`wuulf-budget-data`**, labels
`app.kubernetes.io/name: wuulf-budget`, `instance: home-wuulf-budget`.
This exactly matches the live bri-budget resources, so the proxy entry must be
`service: home-wuulf-budget`, `port: 5006`.

### Live cluster state (readonly-home-kubernetes)

- ns `default`: Deployments `home-actualbudget` and `home-bri-budget`, both
  1 replica, same image
  `ghcr.io/actualbudget/actual-server:26.10.0@sha256:24645e97…860c`, same env,
  `envFrom: actualbudget-sso-secret`. `home-actualbudget` has the
  `01-enable-openid` initContainer; `home-bri-budget` does not.
- Services: `home-actualbudget`, `home-bri-budget` (port 5006).
  PVCs: `actualbudget-data`, `bri-budget-data`.
- Ingresses: `budget-ingress`, `actualbudget-ingress`, `bri-budget-ingress`,
  `mcp-multi-server-ingress` (host `mcp.home-lab.spencerslab.com`,
  `cluster-wildcard-cert`, paths `/<name>` → `mcp-mcp-<name>-proxy:8080`).
- **No `home-bri-budget` on the gpu cluster** → home-category Applications
  materialize only on the home cluster, despite the `clusters: {}` matrix
  generator in `services/home/prod/templates/appset.yaml:11-23`. A third
  instance lands on **home** by copying the pattern.

### Keycloak (live, via readonly-infra-postgres-keycloak)

Realm `SpencersLab` (id `26f36bde-fc64-40ac-9840-3fc8c5d1cfb2`) has client
`actualbudget` (id `1cdd3b08-8b53-426d-acda-cfe101f1775e`) with
`redirect_uris` + `web_origins` = exactly
`https://budget.spencerslab.com/*` and `https://bri-budget.spencerslab.com/*`.
**A third host needs a live Keycloak mutation** (add
`https://wuulf-budget.spencerslab.com/*` to Valid Redirect URIs + Web Origins)
— out of repo, and I only have readonly DB access. No repo file manages this
client (grep of `services/infra/`, `charts/` found nothing).

---

## 2. Exact change list for a third instance (mirror of bri-budget)

| File | Change |
|---|---|
| `services/home/prod/values.yaml` | `charts: wuulf-budget: {namespace: default, ServerSideApply: "true", chart: actualbudget}`; `ingress.subdomains.wuulf-budget: {service: home-wuulf-budget, port: 5006}`; top-level `wuulf-budget: {app-template: {global: {nameOverride: wuulf-budget}}}` |
| `custom-values/home/prod-values.yaml` | `wuulf-budget: {bitwardenIds: {actualbudget-sso-secret: <same UUID 3f3ebb88-…>}}` (mirror of `bri-budget`) |
| `services/proxy-local/prod/values.yaml` | `wuulf-budget: {target: wuulf-budget, ssoRedirectPath: "…client_id=actualbudget…redirect_uri=https://wuulf-budget.$.Values.domain/account/login", loginSubDomain: "login"}` (copy lines 206-209) |
| `services/proxy-remote/prod/values.yaml` | `wuulf-budget: {enabled: true}` (next to `bri-budget:`, :90-91) |
| (out-of-repo) | Keycloak `actualbudget` client: add third redirect URI + web origin |
| NOT needed | chart changes (nameOverride mechanism already exists), new Bitwarden item, new umbrella templates |

Precedent for the `chart:` multi-instance pattern is also documented in
`services/gpu-ai/prod/values.yaml:80-96` (cf-143 radiance-q27 comment:
"precedents chart: zigbee2mqtt / actualbudget").

## 3. MCP platform grounding (part 2 of the ticket)

- ToolHive = `charts/hivetools`, deployed cluster-wide via base's `charts:`
  list (`charts/base/values.yaml:35-39`); **no per-service ApplicationSet or
  proxy entry needed for MCP** — `charts/hivetools/templates/generic-mcp-ingress.yaml`
  renders one shared Ingress per cluster at
  `mcp.<subDomain|clusterName>.<domain>` (home: live host
  `mcp.home-lab.spencerslab.com`), path `/<name>` per server, TLS
  `cluster-wildcard-cert`, path-normalizing middleware.
- Adding a server = one `mcp.<name>:` entry under `hivetools:` in
  `services/<cat>/prod/values.yaml` (fields: `image`, `transport: streamable-http`,
  `mcpPort: 8080`, `env`, `secrets[]`, `resources`, `podTemplateSpec` with the
  `mcp`-named container + uid 65532 securityContext). Optional
  `secrets[].name/key/targetEnvName` pairs with an ExternalSecret template in
  `services/<cat>/prod/templates/` + sentinel in service
  `bitwardenIds:` + real UUID in `custom-values/<cat>/prod-values.yaml`.
  Full recipe: `skills/helm-chart-creation/references/mcp-servers.md`.
- **Home's current hivetools block** (`services/home/prod/values.yaml:1128-1149`)
  has ONLY `postgresMcp.databases` (immich, postiz, home-rallly, paperless) —
  **no custom `mcp:` entries on home today**. The MCP servers live on home
  (verified): `mcp-kubernetes-readonly`, `mcp-kubernetes-admin`,
  `mcp-postgres-{home-rallly,immich,paperless,postiz}`.
- **The precedent for "MCP server that wraps an external app's HTTP API" is
  `wekan-mcp`**: in-repo Python container `containers/wekan-mcp/`
  (fastmcp + httpx, streamable-http :8080, non-root 65532, credential in env
  from ExternalSecret `wekan-mcp`, `WEKAN_MCP_READ_ONLY` readonly/admin tier
  split) + `hivetools.mcp.wekan-{readonly,admin}` entries in
  `services/gpu/prod/values.yaml:738-804` +
  `services/gpu/prod/templates/secret-wekan-mcp.yaml` (bitwarden-login
  `password` → `WEKAN_TOKEN`) + UUID in `custom-values/gpu/prod-values.yaml`
  (`hivetools.bitwardenIds` for chart templates; top-level `bitwardenIds` for
  service-umbrella templates — the wekan one is top-level, line 37).
  Image `ghcr.io/ownyourio/wekan-mcp:v162`, built by
  `.forgejo/workflows/containers-build.yaml` (builds every changed
  `containers/<name>` dir on push, `yy.mm.N` calendar tags, ROLE=prod-gated;
  PR builds push `pr-<branch>-<sha>` to local registry only).
- There is **no Actual-Budget MCP server anywhere in the repo yet** (grep of
  all `services/*/prod/values.yaml` mcp entries; `containers/` inventory has
  wekan-mcp, renovate-mcp, gpt-researcher, music-assistant, etc. — no actual).
- Per-server OIDC is currently **disabled everywhere** (commented
  `oidc:` blocks; shared `mcp` Keycloak client exists but unused) — a new
  entry ships without OIDC, same as wekan.
- In-cluster reachability: an MCP server running on **home** could call the
  budget instances at `http://home-bri-budget.default.svc:5006` /
  `http://home-actualbudget.default.svc:5006` with no public ingress. The
  gpu-hosted wekan-mcp instead calls the public URL
  (`https://wekan.spencerslab.com`) — precedent for either option.

## 4. Actual Budget API/export surface in-repo (thin — research needed)

- Repo evidence only: data dir `/data` on a 5Gi PVC per instance
  (`ACTUAL_DATA_DIR`), multiuser mode on, SSO-enforced auth
  (`ACTUAL_OPENID_ENFORCE: true`, user creation `login`). No repo code
  consumes Actual's REST/HTTP API, and no export tooling exists here.
  Whatever the MCP server needs (export endpoints, token auth, schedules,
  "payments grouped" vs "item-level" export shapes) is **upstream
  Actual-Budget knowledge → research stage (agent-research), not grounded here**.
- `custom-values/home/prod-values.yaml:111-114` — `trustedIPs`
  ("For actualbudget") feeds `charts/base/templates/traefik-config.yaml`
  forward-auth `trustedIPs`; a new instance behind the same proxy needs no
  change here (proxy pod subnets already covered).

## 5. Drift / pitfalls relevant to the plan

- **Renovate**: image pin `ghcr.io/actualbudget/actual-server:26.10.0@sha256:…`
  is managed (precedent PR "Update ghcr.io/actualbudget/actual-server Docker
  tag to 26.x"); it appears in TWO files (chart values + umbrella values) —
  a new container image (`containers/actual-budget-mcp`?) would be
  `ghcr.io/ownyourio/*` and get the calendar-tag versioning rule
  (`renovate.json` `matchPackageNames: ghcr.io/ownyourio/*`).
- **Never hand-bump** `Chart.yaml` versions (release.yaml owns bumps on main);
  `appVersion: 26.7.0` in the chart is already stale vs the 26.10.0 image —
  leave it.
- Local validation: `helm lint charts/actualbudget` + `helm template` require
  `helm dependency update` first (no vendored tgz in git; `helm` at
  `~/.local/bin`). Rendered output must contain no `OVERRIDE_*` sentinels once
  custom-values are applied (they resolve at deploy time, so template-level
  checks use `--set` substitutions, per repo convention).
- **No unit test suite** exists for this surface; validation convention is
  helm lint/template + grep for the service trio (chart entry + appset values
  entry + proxy values entry) + 1:1 sentinel↔custom-values matching, plus
  optional `tests/services/*.sh` hermetic scripts (see
  `tests/services/home-dead-image-refs.sh` for the style: literal
  `want_count` greps + python3/PyYAML structure asserts).
- `appset-charts.yaml` runs `goTemplateOptions: ["missingkey=error"]` —
  optional fields need `hasKey` guards (existing entries don't need new
  guards; the `chart:`/`version`/`repository` keys are already guarded).
- Home umbrella `hivetools:` block comment says MCP host is
  `mcp.home-lab.<domain>` — if the plan adds a home `hivetools.mcp.<name>`
  entry, no ingress/proxy/DNS work is needed (generic templates + wildcard
  cert cover it; cert pre-exists since 4 postgresMcp servers already render
  the same Ingress).

## 6. What I could NOT ground (→ research/plan questions)

1. **Who/what "wuulf" is** — zero occurrences in the repo; instance name
   `wuulf-budget`, host `wuulf-budget.spencerslab.com`, and target cluster
   `home` are extrapolations from the `bri-budget` precedent, to confirm.
2. **Keycloak redirect URI for the new host** — live mutation on
   infra/Keycloak (readonly access here); owner action or an admin-tier step.
3. **Which Actual Budget MCP server to run** (upstream/community vs in-repo
   `containers/` build à la wekan-mcp), which instance(s) it targets
   (wuulf only? all three?), and the auth model (Actual API token per
   instance?) — web research needed → `agent-research`.
4. **Host cluster for the MCP server**: home (co-located, in-cluster URLs,
   no new public exposure) vs gpu (where wekan-mcp/renovate-mcp live and the
   MCP surface `mcp.gpu…` agents already use) — a plan decision.
5. Whether the "payments-grouped vs item-level, then reconcile/split/assign"
   workflow maps to Actual's native export endpoints vs custom logic inside
   the MCP container — research.

---

## RESULT

```
RESULT
status: DONE
chunk: plan
files_changed: [.agents/plans/2026/2026-11-cf-156-feat-actual-budget-mcp-server/EXPLORE.md]
commands_run: [grep actualbudget/bri/wuulf across repo => pass; git log -S bri-budget (found 217dae71d, cce60c729, 0bcc88d37) => pass; helm dependency update + helm template (charts/actualbudget copy in /tmp, release home-wuulf-budget, --set nameOverride) => pass; readonly-home-kubernetes resources_get/list (deployments, services, pvcs, ingresses, MCPServers) => pass; readonly-gpu-kubernetes resources_get home-bri-budget => expected not-found (confirms home-only); readonly-infra-postgres-keycloak execute_sql (client/redirect_uris/web_origins; 1st attempt failed on schema guess, fixed via information_schema) => pass]
deviations: none (one /tmp render copy for helm; repo tree left unmodified)
friction: keycloak postgres uses KC-26-style schema (no client.attributes column; redirect URIs in separate redirect_uris/web_origins tables keyed by client.id UUID) — resolved via information_schema probe; MCP k8s resources_list returns kubectl-formatted rows (Name, not metadata.name) while resources_get returns full objects
open_questions: "Who/what is wuulf (confirm instance name wuulf-budget, host wuulf-budget.spencerslab.com, cluster home)?"; "Keycloak: add https://wuulf-budget.spencerslab.com/* to client 'actualbudget' redirect URIs + web origins — who does this live mutation?"; "Needs research: yes — which Actual Budget MCP server to run (upstream vs in-repo containers/ build à la wekan-mcp), which instance(s) it targets, token/auth model, and how 'payments-grouped vs item-level exports' + reconcile/split/assign map to Actual's API"; "Which cluster hosts the new mcp.* server (home co-located vs gpu like wekan-mcp)?"
next_suggested: agent-research on Actual Budget MCP options + API/export surface (open question 3/5), then agent-plan drafting 2 chunks: C1 wuulf-budget instance (pure bri-budget copy, §2 table) and C2 MCP server (hivetools entry + container), with the Keycloak redirect-URI change flagged as an owner ops step
```
