# Plan: `dev` service — new dev cluster: Coder, Forgejo, GPT Researcher, Keycloak (feat)

- **Date:** 2026-10-12
- **Branch:** `add-dev-server`
- **Agent:** code (requirements gathered as John/PM via `bmad-agent-pm`)
- **Skills loaded:** executing-plans, bmad-agent-pm, helm-chart-creation
  (+ `references/values-and-appset.md`, `references/proxying.md`,
  `references/storage-and-secrets.md`), gitops-workflows. Load additionally at
  implementation time: `helm-bjw-s-chart`, `kubernetes-skill`.
- **Precedent plan:** `.agents/plans/2026-10-06-feat-gpu-ai-and-proxy-backup-services.md`
  (new service category + new cluster, same shape as this change)

## Goal

A new service category **`dev`** for a brand-new **dev cluster**, publicly
identified as `dev.scifi.farm`. Scope of this repo change:

- `services/dev/prod/` — umbrella + appset deploying:
  - **base** (automatic via appset): ArgoCD, cert-manager, **hivetools MCP
    platform (kubernetes readonly+admin servers)**, reloader → *"MCP & ArgoCD
    come by default"* — no extra work.
  - **Coder** (external chart `helm.coder.com/v2`, wiring copied from gpu)
  - **Forgejo** (new wrapper chart around the official OCI chart)
  - **GPT Researcher** ("ResearchGPT" — new custom app-template chart)
  - **Keycloak** (existing `keycloakx` chart + CNPG) — dev's own instance,
    **one shared OIDC client for all of dev**
  - Parity: `cloudnative-pg`, `external-secrets-bitwarden`, `k8s-monitoring`
- `charts/forgejo/`, `charts/gpt-researcher/` — the two new charts
- `custom-values/dev/prod-values.yaml` — the new Bitwarden UUID map

**Explicitly out of scope** (user decisions, 2026-10-12): smtp-relay (no email
on dev for now), `agent-config.jsonc` MCP client entries (follow-up), public
hub routing via proxy-local/proxy-remote (follow-up), Gitea (Forgejo chosen).

## Decisions confirmed with the user (in-session)

1. **ResearchGPT = `assafelovic/gpt-researcher`** (autonomous research agent,
   official Docker Hub images, web frontend).
2. **GPT Researcher backends — no new API keys**: LLM via the lab llama-swap
   endpoint `https://llama.spencerslab.com/v1` (OpenAI-compatible; mesh/LAN
   clients pass the hub ipAllowlist without SSO — same mechanism minuspod and
   immich-analyze already use). Web search via gpu's SearXNG
   `https://searxng.spencerslab.com` (`RETRIEVER=searx`, env var is
   `SEARX_URL` — verified in `gpt_researcher/retrievers/searx/searx.py`; JSON
   format already enabled there since mcp-searxng consumes it).
3. **Forgejo, not Gitea** — official chart is OCI-distributed:
   `forgejo/forgejo-helm` (chart ~17.x at ArtifactHub; package registry
   `code.forgejo.org/forgejo-helm`, migrated from codeberg forgejo-contrib).
   Chart is based on the official Gitea chart, which matches the dormant
   `forgejo:` config block already sitting in `services/infra/prod/values.yaml`
   (good schema reference). `services/infra` leftovers stay untouched in this
   change (separate cleanup follow-up).
4. **GitHub credential = one PAT for dev agents' repo access** (clone/push
   OwnYourIO repos from Coder workspaces/agent tooling). Pattern: gpu's
   `secret-github-mcp.yaml` (Bitwarden custom field `token` via
   `bitwarden-fields` store). No Coder GitHub OAuth, no Gitea mirroring.
5. **Parity extras**: external-secrets-bitwarden + k8s-monitoring yes;
   smtp-relay no. Consequence: the dev `secrets-coder.yaml` drops the
   `CODER_EMAIL_*` env vars (gpu's copy has them), and Forgejo mailer config
   stays off.
6. **One shared Keycloak OIDC client for all of dev** (ArgoCD SSO, Coder OIDC,
   Forgejo OAuth, hivetools MCP SSO). Documented deviation from the repo's
   one-item-per-consumer secret rule — explicit user choice. All four
   `bitwardenIds` keys point at ONE Bitwarden item `dev-keycloak-client`.
7. **Monitoring prod→dev**: nothing changes in the monitoring service.
   `charts/base/templates/appset-charts.yaml` already injects
   `k8s-monitoring.cluster.name = <serviceName>` — dev automatically reports
   as cluster `dev` to prometheus.spencerslab.com / loki.spencerslab.com.
   Optionally add a stage label via the grafana k8s-monitoring chart's
   `cluster.metadata` (verify exact key against upstream v3.8.0 while
   implementing; if present set `stage: dev` in the dev service values).
8. **Cluster bootstrap is user-owned** (gpu-ai precedent): K3s install, base
   `initialInstall`, ArgoCD cluster-secret + annotations, bootstrap
   Application, mesh/split-horizon DNS, bitwarden-cli unlock. Exact annotation
   spec in "User actions" below. The repo never hardcodes the domain.

### Hostname layout (recommended cluster annotations — user-owned)

Convention follow the `home` cluster (`subDomain: home-lab` →
`cluster.home-lab.<domain>`, `mcp.home-lab.<domain>`):

- Cluster annotations: `domain: scifi.farm`, `clusterName: dev`
- Service values top-level: `subDomain: dev`
- Cluster-scoped hosts (all `clusterBase: true` ingress entries, mesh-only,
  covered by `cluster-wildcard-cert` = `*.dev.scifi.farm`):
  `coder.dev.scifi.farm`, `git.dev.scifi.farm`, `research.dev.scifi.farm`,
  `cluster.dev.scifi.farm` (ArgoCD), `mcp.dev.scifi.farm` (hivetools renders
  this automatically from subDomain).
- **Keycloak exception**: `charts/keycloakx/templates/secret-keycloak-admin.yaml`
  hardcodes `KC_HOSTNAME: https://login.{{ .Values.domain }}` → dev Keycloak
  claims **`login.scifi.farm`** (top-level, not under `dev.`). Give it a
  non-clusterBase `login` ingress entry (covered by `wildcard-cert` =
  `*.scifi.farm`). If `login.dev.scifi.farm` is wanted instead, that's a
  keycloakx chart change — parked as a follow-up.
- Public internet exposure (hub entries with `domain:` override in
  proxy-local/proxy-remote) is a follow-up: note the hub's explicit-domain
  entries expect a `<name>-cert` TLS secret and nothing in the repo currently
  renders one (the existing `scifi-farm` hub entry's `scifi-farm-cert` is not
  repo-managed). Dev access starts mesh/LAN-only, which matches how cluster
  hosts are protected today.

## Bitwarden items — complete list (the explicit user ask)

Create in the Bitwarden org vault; paste the UUIDs into
`custom-values/dev/prod-values.yaml` (placeholders `OVERRIDE_NEEDED` until
then). Items marked REUSE need no new entry.

| # | Item name | Type | Contents | Consumed by (`bitwardenIds` key) |
|---|---|---|---|---|
| 1 | `dev-keycloak-client` | LOGIN | username = **client-id**, password = **client-secret**, URI = `https://login.scifi.farm/realms/<dev-realm>` (Coder reads the issuer from the item URI via the `bitwarden-uri` store!), custom field `issuer` = same realm URL (text; ArgoCD reads it via `bitwarden-fields`) | `argocd-sso-secret` (base), `coder-sso-secret` (coder), `forgejo-oauth` (forgejo wrapper), `hivetools.bitwardenIds.mcp-sso` — **same UUID, 4 keys** |
| 2 | `dev-keycloak` | LOGIN | Keycloak admin username + password | `keycloakx.bitwardenIds.keycloak` |
| 3 | `dev-keycloak-pg` | LOGIN | username = `keycloak`, password = DB password | `keycloakx.bitwardenIds.keycloak-pg` (+ reuse for `mcp-pg-keycloak` if postgres-MCP parity is wanted later) |
| 4 | `dev-keycloak-mqtt` | LOGIN | **deliberately non-working creds** (see risk below) | `keycloakx.bitwardenIds.keycloak-mqtt` — chart requires the key unconditionally |
| 5 | `dev-coder-pg` | LOGIN | username = `coder`, password = DB password | `coder-pg` (+ reuse for `mcp-pg-coder`) |
| 6 | `dev-forgejo` | LOGIN | password = Forgejo `SECRET_KEY` (generate `openssl rand -hex 32`; username arbitrary e.g. `forgejo`) | `forgejo.bitwardenIds.forgejo` |
| 7 | `dev-forgejo-admin` | LOGIN | initial admin username + password | `forgejo.bitwardenIds.forgejo-admin` |
| 8 | `dev-forgejo-pg` | LOGIN | username = `forgejo`, password = DB password | `forgejo.bitwardenIds.forgejo-pg` (+ reuse for `mcp-pg-forgejo`) |
| 9 | `dev-github` | LOGIN (or NOTE) | custom field `token` = fine-grained PAT (Contents read/write on the OwnYourIO repos dev agents need) | `github-pat` (dev service values) |
| 10 | Cloudflare solver token | — | **REUSE the shared lab item `0f8504eb-1339-4a32-861b-af440002801e`** — proxy-local's external-dns already publishes scifi.farm records with it, so the token very likely covers both zones. VERIFY by watching the dev wildcard certs issue after bootstrap; only if issuance fails create a new `dev-cloudflare` LOGIN item (password = CF API token, Zone:DNS:Edit for scifi.farm) and point `cert-manager-solver-token` at it | `cert-manager-solver-token` (base) |

**Not a repo UUID (manual cluster step):** the `bitwarden-cli` Secret created
by external-secrets-bitwarden on the dev cluster is blank by design — edit it
in-cluster so the CLI pod can unlock the vault (same as every other cluster).

**Keycloak MQTT risk (item 4):** keycloakx always configures the MQTT event
listener (`KC_SPI_EVENTS_LISTENER_MQTT_*`) pointing at
`tcp://mqtt.{{ .Values.domain }}:1883` on topic `keycloak`. With
`domain: scifi.farm` that host won't resolve (fine — the chart's watchdog
probe passes when the broker is unreachable), BUT if the shared lab
`keycloak-mqtt` creds were reused and mesh DNS for `mqtt.scifi.farm` ever
appears, dev login events would land on the prod HA automation topic. Hence a
dedicated item with dead creds: events fail auth and stay off the lab broker.
Long-term fix (chart makes broker/topic cluster-aware) is a follow-up.

## Changes

### 1. `charts/gpt-researcher/` — new custom chart (app-template)

- `Chart.yaml`: name `gpt-researcher`, **version 1.0.0** (CI bumps from here),
  app-template dependency at the current repo standard (check an existing
  chart, e.g. `charts/qdrant`, for the exact version in use — 5.0.1 era).
- Two containers in one controller pod (localhost communication is allowed
  intra-pod):
  - `backend`: `gptresearcher/gpt-researcher:<newest pinned tag>` — look the
    tag up on Docker Hub at implementation time (pin per the image-tag rules;
    if only `latest` exists, use it with `pullPolicy: Always` + comment).
    Port 8000.
  - `frontend`: `gptresearcher/frontend:<matching pinned tag>` — port 3000,
    `NEXT_PUBLIC_GPTR_API_URL` pointed at the backend. **Implementation-time
    verification:** the browser (not the frontend pod) calls the API, so
    verify how the frontend image wires the API URL at runtime; fallback =
    expose backend-only or a second ingress entry (`research-api`) — decide
    during render/test, keep the plan's single-`research` ingress if possible.
- Env (backend, all non-secret — no `bitwardenIds` in this chart):
  - `OPENAI_BASE_URL: https://llama.spencerslab.com/v1`
  - `OPENAI_API_KEY: dummy` (llama-swap ignores it)
  - `FAST_LLM` / `SMART_LLM` / `STRATEGIC_LLM`: `openai:<model-id>` — pick
    ids from the gpu-ai roster (`curl https://llama.spencerslab.com/v1/models`
    at implementation time; e.g. a q38-class model for smart/strategic, a
    small fast one for fast).
  - `RETRIEVER: searx`, `SEARX_URL: https://searxng.spencerslab.com`
  - **Embeddings risk:** llama-swap serves no embedding model and gpt-researcher
    defaults `EMBEDDING` to OpenAI. Verify behavior with embeddings
    unavailable at implementation time (content compression / similarity
    filtering may degrade or error); options then: set `COMPRESSION_THRESHOLD`
    high, or add an embedding model to llama-swap (separate change).
- Service: port 3000 (frontend) as `main`. Persistence: emptyDir scratch for
  report outputs (no PVC initially — dev workload is ephemeral; note as
  optional follow-up). Probes: TCP/HTTP on both containers. Resources: backend
  req 250Mi/lim 2Gi, frontend req 50Mi/lim 256Mi. Standard security context
  (drop ALL, non-root where the images allow — verify image users; gpt-researcher
  images may run root by default, adjust fsGroup/runAsUser if they permit).
  `reloader.stakater.com/auto: "true"` not needed (no secrets) but harmless to
  skip.
- `templates/`: none beyond what app-template renders (no secrets).

### 2. `charts/forgejo/` — new wrapper chart (erp-next precedent)

Official chart needs secrets + CNPG DB → wrapper, per helm-chart-creation
rules.

- `Chart.yaml`: name `forgejo`, **version 1.0.0**; dependency `forgejo`
  version ~`17.x` (resolve latest at implementation), repository
  `oci://code.forgejo.org/forgejo-helm`. `helm dependency update` must work
  anonymously (public OCI registry); commit the generated `Chart.lock`.
- `values.yaml`:
  - `bitwardenIds:` — `forgejo`, `forgejo-admin`, `forgejo-pg`,
    `forgejo-oauth`: all `OVERRIDE_VIA_CUSTOM_VALUES`.
  - `domain: OVERRIDE_VIA_APPSET`
  - Subchart config under `forgejo:` — start from the dormant block in
    `services/infra/prod/values.yaml` (`gitea.config`, `gitea.admin`,
    `gitea.oauth` schema) and adapt:
    - `gitea.config.database.DB_TYPE: postgres`, host `pg-forgejo-rw:5432`
      (CNPG), user/db `forgejo`; password injection per the chart's mechanism
      (verify at implementation: `gitea.config.database.PASSWD` via an env
      bridge or the chart's `existingSecret` support — the forgejo chart's
      values docs govern).
    - `gitea.config.server.ROOT_URL` / `DOMAIN`: prefer the chart's
      ingress-driven defaults; if explicit values are required, set them in
      the dev SERVICE values block (literal `git.dev.scifi.farm` is acceptable
      there — this service only ever deploys to the dev cluster).
    - OAuth: one openidConnect source, `autoDiscoverUrl:
      https://login.scifi.farm/realms/<dev-realm>/.well-known/openid-configuration`,
      key/secret from the shared `dev-keycloak-client` item.
    - `gitea.admin.existingSecret: forgejo-admin-secret`; registration
      disabled (`DISABLE_REGISTRATION: true` parity with the infra intent).
    - Redis subchart disabled (built-in caching is fine at dev scale); bundled
      PostgreSQL disabled if the chart still ships one (CNPG instead) — verify
      what 17.x still bundles.
  - Ingress: enabled inside the wrapper OR via the dev service's
    `ingress.subdomains` (pick whichever the chart's ingress values make
    trivial; the generic-ingress route keeps it consistent with every other
    dev app — default choice: generic-ingress, chart ingress disabled).
  - Persistence: data PVC `forgejo` 10Gi `local-path`, created by a wrapper
    template with `resource-policy: keep`.
- `templates/`:
  - `pg-forgejo.yaml` — CNPG Cluster (`postgresql.cnpg.io/v1`), storageClass
    `local-path`, initdb owner `forgejo`, `enablePodMonitor: true` (copy the
    shape of `services/gpu/prod/templates/pg-coder.yaml` or
    `charts/keycloakx/templates/pg-keycloak.yaml`).
  - `secret-forgejo-db.yaml` — ExternalSecret `pg-forgejo-secret`
    (username/password from `forgejo-pg` item).
  - `secret-forgejo.yaml` — ExternalSecret `forgejo-secret`: `SECRET_KEY`
    (login password of the `forgejo` item) + OAuth `key`/`secret`
    (username/password of the shared `forgejo-oauth` item →
    `dev-keycloak-client` UUID).
  - `secret-forgejo-admin.yaml` — ExternalSecret `forgejo-admin-secret`
    (username/password from `forgejo-admin` item).
  - `pvc-forgejo-data.yaml` (or chart-native PVC if the forgejo chart's
    persistence handles it cleanly with an existingClaim created here).

### 3. `services/dev/prod/` — new service (copy `services/gpu-ai/prod/` shape)

- `Chart.yaml` — umbrella: name `dev`, version 1.0.0, no dependencies.
- `templates/appset.yaml` — copy gpu-ai's: `name: dev-appset`,
  `serviceName: dev`, `baseChartVersion: 1.0.196` (or the base chart's current
  version at implementation time — it must match `charts/base/Chart.yaml`),
  renovate annotation kept.
- `templates/generic-ingress.yaml` — copy gpu-ai's (includes the
  serviceName-block wildcard-cert fix from the llama endpoint reorg).
- `templates/pg-coder.yaml`, `templates/pg-coder-secret.yaml` — copy gpu's
  (CNPG cluster `pg-coder`, ExternalSecret from `coder-pg` item).
- `templates/secrets-coder.yaml` — copy gpu's with these deltas:
  - `CODER_ACCESS_URL: https://coder.dev.scifi.farm` → template it as
    `https://coder.{{ $.Values.subDomain }}.{{ $.Values.domain }}` (subDomain
    is a top-level service value; external-chart values slices aren't
    templated, which is exactly why gpu parks the wildcard host in
    custom-values — keep that pattern for `coder.coder.ingress.host`).
  - `CODER_WILDCARD_ACCESS_URL: *-coder.{{ subDomain }}.{{ domain }}`
  - `CODER_OIDC_EMAIL_DOMAIN`: use the keycloak realm's email domain
    (`{{ $.Values.domain }}` works if dev users get `@scifi.farm` emails —
    decide at Keycloak setup).
  - **Drop** `CODER_EMAIL_SMARTHOST/FROM/HELLO/TLS_SKIPVERIFY` (no smtp-relay
    on dev).
- `templates/secret-github.yaml` — copy gpu's `secret-github-mcp.yaml`
  (ExternalSecret `github-pat`, custom field `token`, store `bitwarden-fields`,
  key `bitwardenIds.github-pat`). Rename target secret to `github-pat` (drop
  the historical `-mcp` misnomer).
- `values.yaml`:
  - Top: `subDomain: dev`, `domain: OVERRIDE_VIA_APPSET`,
    `clusterName: OVERRIDE_VIA_APPSET`.
  - `bitwardenIds:` sentinels (`OVERRIDE_VIA_CUSTOM_VALUES`):
    `cert-manager-solver-token`, `argocd-sso-secret`, `coder-sso-secret`,
    `coder-pg`, `github-pat`.
  - `charts:` — internal: `forgejo`, `gpt-researcher`, `keycloakx`,
    `external-secrets-bitwarden`, `k8s-monitoring`; external:
    `cloudnative-pg` (`0.27.1`, https://cloudnative-pg.github.io/charts),
    `coder` (`2.35.2` matching gpu today, https://helm.coder.com/v2, renovate
    annotation; ServerSideApply settings copied from gpu: coder `false`,
    CNPG `true`, es-bitwarden `true`, k8s-monitoring `true`).
  - `ingress.subdomains`:
    ```yaml
    coder:    {clusterBase: true, service: coder, port: 80}
    git:      {clusterBase: true, service: <forgejo service name from render>, port: 3000}
    research: {clusterBase: true, service: dev-gpt-researcher, port: 3000}
    login:    {service: dev-keycloakx-http, port: 80}   # NOT clusterBase → login.scifi.farm (verify service name/port against keycloakx render; infra uses infra-keycloakx-http:80)
    cluster:  {clusterBase: true, service: argocd-server, port: 80}
    ```
  - `coder:` block — copy gpu's (env: GitHub default provider off, signups
    off, telemetry off, prometheus on; `envFrom: coder-secrets`;
    `envUseClusterAccessURL: false`; ingress enable + tls `wildcard-cert` —
    note: on dev the wildcard host `*.dev.scifi.farm` is NOT covered by
    `wildcard-cert` (`*.scifi.farm`), it needs `cluster-wildcard-cert`; set
    `secretName: cluster-wildcard-cert` in custom-values'
    `coder.coder.ingress.tls.secretName` alongside the host) + service
    ClusterIP.
  - `keycloakx:` block — `bitwardenIds:` sentinels (`keycloak`, `keycloak-pg`,
    `keycloak-mqtt`, `mcp-pg-keycloak`); realm bootstrap values per infra's
    usage; accept the MQTT watchdog quirk (item 4 dead creds + probe passes
    when broker unreachable).
  - `forgejo:` / `gpt-researcher:` blocks — minimal service-level overrides
    (forgejo: oauth autoDiscoverUrl with the dev realm, ingress host literals
    if the wrapper needs them; gpt-researcher: the LLM model ids chosen at
    implementation time).
  - `hivetools:` block — `bitwardenIds.mcp-sso: OVERRIDE_VIA_CUSTOM_VALUES`,
    `keycloak.realm: <dev-realm>` (gpu/infra shape). No extra MCP servers in
    this change — the base defaults (kubernetes readonly+admin) are the
    "MCP by default" ask; postgres-MCP entries for the three dev DBs are a
    follow-up once the DBs exist.
- `custom-values/dev/` directory is new; do NOT touch the existing empty
  `custom-values/*/dev-values.yaml` files (those belong to the unused
  `stage: dev` mechanism).

### 4. `custom-values/dev/prod-values.yaml` — new

Shape mirrors `custom-values/gpu-ai/prod-values.yaml` + gpu's coder nesting:

```yaml
bitwardenIds:
  cert-manager-solver-token: 0f8504eb-1339-4a32-861b-af440002801e  # REUSE shared lab item; verify scifi.farm zone access
  argocd-sso-secret: OVERRIDE_NEEDED   # dev-keycloak-client UUID
  coder-sso-secret: OVERRIDE_NEEDED    # dev-keycloak-client UUID (same item)
  coder-pg: OVERRIDE_NEEDED            # dev-coder-pg
  github-pat: OVERRIDE_NEEDED          # dev-github

base:
  bitwardenIds:
    argocd-sso-secret: OVERRIDE_NEEDED        # same dev-keycloak-client UUID
    cert-manager-solver-token: 0f8504eb-...   # same reuse as above

coder:
  coder:
    ingress:
      host: "*.dev.scifi.farm"
      tls:
        secretName: cluster-wildcard-cert

keycloakx:
  bitwardenIds:
    keycloak: OVERRIDE_NEEDED          # dev-keycloak
    keycloak-pg: OVERRIDE_NEEDED       # dev-keycloak-pg
    keycloak-mqtt: OVERRIDE_NEEDED     # dev-keycloak-mqtt (dead creds, see risk)

forgejo:
  bitwardenIds:
    forgejo: OVERRIDE_NEEDED           # dev-forgejo
    forgejo-admin: OVERRIDE_NEEDED     # dev-forgejo-admin
    forgejo-pg: OVERRIDE_NEEDED        # dev-forgejo-pg
    forgejo-oauth: OVERRIDE_NEEDED     # dev-keycloak-client UUID (same item)

hivetools:
  bitwardenIds:
    mcp-sso: OVERRIDE_NEEDED           # dev-keycloak-client UUID (same item)
  keycloak:
    realm: <dev-realm>                 # e.g. dev — decided at Keycloak setup
```

(`OVERRIDE_NEEDED` = user fills real UUIDs after creating the Bitwarden items;
the cluster only boots its secrets once they're real — same workflow as
pinchflat-ngx in the gpu-ai plan.)

### 5. Repo hygiene included in the change

- AGENTS.md skills/MCP tables: no edit needed now (no new skills/MCP servers
  used); if implementation consumes anything unlisted, add the row.
- `renovate.json`: untouched — the existing helm regex managers pick up the
  new `# renovate:` annotations in the dev service values. OCI-hosted forgejo
  dependency may not be renovate-trackable with the current managers; accept
  manual bumps for now (note in follow-ups).

## Validation (at implementation time)

1. `helm dependency update/build` + `helm lint` + `helm template` for
   `charts/gpt-researcher`, `charts/forgejo`, and the `services/dev/prod`
   umbrella. OCI dep pull must succeed anonymously.
2. Render checks:
   - dev umbrella: appset generator `values:` blob parses; ingress table
     renders exactly the five hosts above with correct cert secrets
     (cluster-wildcard-cert for clusterBase, wildcard-cert for `login`);
     no `OVERRIDE_*` sentinels outside the expected generator JSON.
   - forgejo wrapper: CNPG cluster, three ExternalSecrets, PVC; subchart
     renders StatefulSet/Deployment with postgres config + OAuth source.
   - gpt-researcher: two-container pod, service 3000, env complete
     (OPENAI_BASE_URL, RETRIEVER=searx, SEARX_URL), no secrets.
   - secrets-coder template with test UUIDs: access/wildcard URLs come out as
     `coder.dev.scifi.farm` / `*-coder.dev.scifi.farm` when rendered with
     `--set domain=scifi.farm --set subDomain=dev`.
3. Sentinel sweep: `grep -r OVERRIDE_ charts/forgejo charts/gpt-researcher`
   shows only values.yaml placeholders.

## User actions before the dev cluster syncs

1. **Bootstrap the dev cluster** like gpu-ai/proxy-backup: K3s + base
   `helm install --set initialInstall=true`, then ArgoCD on it.
2. **ArgoCD cluster-secret annotations** (in the dev cluster's own ArgoCD):
   `domain: scifi.farm`, `clusterName: dev`, `stage: prod`, `services.repo`,
   `values.repo`, `chart.repo`, `chart.repo.path` (copy values from an
   existing cluster secret), and
   `services.dev.customValuesUrls: ["https://raw.githubusercontent.com/OwnYourIO/SpencersLab/refs/heads/main/custom-values/dev/prod-values.yaml"]`.
3. **Bootstrap Application** → `services/dev/prod`.
4. **DNS**: mesh record `dev.spencerslab.com` → dev traefik LB (hub
   convention, needed if hub routing is added later); split-horizon records
   `*.dev.scifi.farm` and `login.scifi.farm` → dev traefik LB for LAN/mesh
   clients.
5. **Bitwarden**: create items 1–9 from the table above; paste UUIDs into
   `custom-values/dev/prod-values.yaml` (replacing `OVERRIDE_NEEDED`).
6. **bitwarden-cli Secret** on the dev cluster: edit it so external-secrets
   can unlock the vault.
7. **Dev Keycloak** (once keycloakx is up at `login.scifi.farm`): create the
   dev realm + ONE client (e.g. `dev-clients`), standard flow, redirect URIs:
   `https://cluster.dev.scifi.farm/auth/callback`,
   `https://coder.dev.scifi.farm/*`,
   `https://git.dev.scifi.farm/*`; store client-id/secret in
   `dev-keycloak-client` (username/password + URI + `issuer` custom field =
   `https://login.scifi.farm/realms/<realm>`); create user account(s).
8. **Verify certs**: `wildcard-cert` (`*.scifi.farm`) and
   `cluster-wildcard-cert` (`*.dev.scifi.farm`) issue — this is also the
   verification that the reused Cloudflare token covers the scifi.farm zone
   (if not: create the `dev-cloudflare` item per table row 10 and swap the
   UUID).

## Follow-ups (not in this change)

- `agent-config.jsonc` MCP client entries for dev
  (`readonly-dev-kubernetes`, `admin-dev-kubernetes`, later
  `readonly-dev-postgres-{coder,forgejo,keycloak}` once postgres-MCP servers
  are added) — needs the dev MCP ingress reachable first.
- Postgres-MCP (hivetools `postgresMcp.databases`) for the three dev DBs.
- Public exposure via proxy-local/proxy-remote hub entries with
  `domain:` overrides — includes solving the `<name>-cert` Certificate gap
  for explicit-domain hub entries.
- keycloakx chart: make `KC_HOSTNAME` and the MQTT broker/topic cluster-aware
  (would allow `login.dev.scifi.farm` and real event routing later).
- GPT Researcher embeddings (llama-swap embedding model or alternative) if
  report quality needs it.
- Clean up the dormant gitea/forgejo leftovers in `services/infra` (bitwardenIds
  keys, ExternalSecret templates, `forgejo:` values block).
- Renovate coverage for the OCI forgejo dependency.
- hivetools MCPOIDCConfig issuer is templated as `login.{{ domain }}` — dev renders
  `login.scifi.farm` (no Keycloak there). Fix when the MCP OIDC rollout reaches dev
  (issuer must come from values/config, like the keycloakx cluster-aware follow-up).

## Code Review

### 2026-10-12

**Code review complete.** 4 decision-needed, 7 patch, 1 defer, 9 rejected.
Lenses: blind-hunter, edge-case-hunter, verification-gap, intent-alignment (bmad-code-review).
Verified against: repo wiring (base appset-charts, gpu/gpu-ai/infra values, keycloakx chart),
Docker Hub tag dates, upstream `assafelovic/gpt-researcher` at commit `393697a` (the state the
published images were built from), and local `helm lint`/`helm template` renders.

**Decisions resolved with the user (2026-10-12, in-session):**
1. gpt-researcher → build current upstream master via `containers/` (patch P1 below).
2. Keycloak → **removed from dev entirely**; OIDC consumers rewired to the lab Keycloak
   pattern (patches P2/P3): ArgoCD SSO + hivetools mcp-sso reuse the lab-wide shared items
   (`6bc8ead2…`, `2c3ac9dd…`, realm `SpencersLab` at `login.spencerslab.com` — same as every
   other cluster); Coder + Forgejo keep their OIDC wiring with `OVERRIDE_NEEDED` UUIDs until
   dev-specific clients (`dev-coder-sso`, `dev-forgejo-oauth`) are created in the lab
   `SpencersLab` realm (gpu's coder pattern: issuer read from the Bitwarden item URI).
   Plan Bitwarden items 2–4 (dev-keycloak, dev-keycloak-pg, dev-keycloak-mqtt) and user
   action 7's "create the dev realm" are therefore VOID; item 1 becomes two items
   (dev-coder-sso + dev-forgejo-oauth) plus the two reused lab-wide UUIDs.
3. github-pat → kept as-is; workspace consumption is user-owned Coder config (patch P4).
4. OIDC icon → keep gpu parity (`gitlab.alexsaphir.com`) — moved to Rejected, user's choice.

- [x] [Review][Patch] P1 (major) Build gpt-researcher images from pinned upstream master + rewire chart [containers/gpt-researcher, charts/gpt-researcher/] — the published Docker Hub images are from March 2025 and lack everything the chart assumes (no CONTEXT_FILTER, nginx static frontend with no /api handlers or rewrites, no-op NEXT_PUBLIC_BACKEND_URL); the deployed backend unconditionally calls OpenAI embeddings which llama-swap can't serve. Fix per the containers/ mechanism: Dockerfiles building upstream `assafelovic/gpt-researcher` at a renovate-pinned git ARG (backend + frontend), published as ghcr.io/ownyourio images; chart switches to those images and aligns env/ingress with master's verified topology (CONTEXT_FILTER=keyword becomes real; verify master's frontend routing before finalizing ingress paths).
- [x] [Review][Patch] P2 Remove keycloakx from the dev service [services/dev/prod/values.yaml, custom-values/dev/prod-values.yaml] — drop the `keycloakx:` charts entry, the `keycloakx:` values block, the `login:` ingress subdomain, and the custom-values `keycloakx:` block. Dev has no Keycloak, no `login.scifi.farm`, no dev realm; the MQTT watchdog crashloop finding dies with it.
- [x] [Review][Patch] P3 Rewire dev OIDC to the lab Keycloak pattern [custom-values/dev/prod-values.yaml, charts/forgejo/values.yaml, charts/coder/values.yaml] — argocd-sso-secret (top-level + base:) = `6bc8ead2-faf6-4548-9831-b1a501646625` (lab-wide shared, all clusters); hivetools.bitwardenIds.mcp-sso = `2c3ac9dd-636a-4c3e-ba1e-b498002ed133` (lab-wide shared) with `hivetools.keycloak.realm: SpencersLab` (chart default clientId `mcp` already matches); forgejo `autoDiscoverUrl` → `https://login.spencerslab.com/realms/SpencersLab/.well-known/openid-configuration`; retire the "one shared dev-keycloak-client" comments — coder-sso-secret / forgejo-oauth stay `OVERRIDE_NEEDED` until the dev-specific clients exist in the lab realm, with comments saying so.
- [x] [Review][Patch] P4 Document github-pat consumption as user-owned [services/dev/prod/templates/secret-github.yaml] — no in-repo consumer exists (verified: coder chart doesn't mount it, dev deploys no github initContainer, coder-templates/main.tf has no references); decision #4's consumption path is user-owned Coder workspace/agent config. Say that in the file's comment.

- [x] [Review][Patch] P5 CNPG clusters pg-coder/pg-forgejo deploy with client-side apply [charts/coder/templates/pg-coder.yaml, charts/forgejo/templates/pg-forgejo.yaml] — `charts.coder.ServerSideApply: "false"` / `charts.forgejo.ServerSideApply: "false"` were copied from gpu's external-coder entry, but the CNPG `Cluster` objects moved INTO those wrapper charts; every other CNPG cluster in the repo is server-side applied (gpu service app `ServerSideApply: "true"` renders gpu's pg clusters, keycloakx `"true"`, cloudnative-pg `"true"`; the plan itself said "CNPG `true`"). The CNPG mutating webhook's defaulted fields drift against the last-applied-configuration annotation → perpetual OutOfSync/selfHeal flapping. Fix: add `annotations: argocd.argoproj.io/sync-options: ServerSideApply=true` to both Cluster manifests (surgical — keeps the coder/forgejo subchart resources client-side like gpu).
- [x] [Review][Patch] P6 Nothing pins the ingress-backend ↔ Service name contract [charts/gpt-researcher/templates/ingress-backend.yaml:35] — `{{ $.Release.Name }}-backend` matches the rendered Service today (verified: `helm template dev-gpt-researcher` → Service `dev-gpt-researcher-backend`), but renaming the `backend` service identifier in values.yaml silently breaks `/ws` + friends in-cluster with lint/template/ArgoCD all green (Kubernetes doesn't validate Ingress backends). Filed by the verification-gap lens; repo precedent: `charts/llama-swap/tests/test_render.py` + the path-scoped workflow. Fix: add a render test asserting every rendered Ingress path's backend service+port exists among rendered Services (plus container env), wired into a PR-triggered workflow.
- [x] [Review][Patch] P7 coder-templates Terraform ships inside the published chart [charts/coder/] — `charts/coder/coder-templates/{main.tf,terraform.tfvars}` (pre-existing at HEAD, commit c9f49bc1c) now sit inside a publishable chart; `release.yaml`'s chart-releaser will package them into the public `coder-1.x.tgz`, and there is no `.helmignore` (precedent: `charts/llama-swap/.helmignore`). Fix: add `charts/coder/.helmignore` excluding `coder-templates/`.
- [x] [Review][Patch] P8 ingress-backend host built from subDomain, generic-ingress from clusterName [charts/gpt-researcher/templates/ingress-backend.yaml:9-12] — both render `research.dev.scifi.farm` today (subDomain=clusterName=dev), but the two sources diverge if the cluster annotation and the service value ever differ; the generic-ingress clusterBase host is `<name>.<clusterName>.<domain>`. Fix: build `$hostBase` from `.Values.clusterName` to match.
- [x] [Review][Patch] P9 Coder DSN interpolates the raw Bitwarden password [charts/coder/templates/secret-coder.yaml:14] — a `pg_password` containing `: @ / %` malforms `CODER_PG_CONNECTION_URL`. Same pattern as gpu (pre-existing convention), but this is new code. Fix: `{{ .pg_password | urlquery }}` in the ExternalSecret template.
- [x] [Review][Patch] P10 All 20 new files lack trailing newlines — every file in the diff ends with `\ No newline at end of file`; the gpu/gpu-ai files they were copied from end with one. Fix: add trailing newlines.
- [x] [Review][Patch] P11 Forgejo OCI dependency has no maintainer note [charts/forgejo/Chart.yaml] — renovate's helm managers can't resolve `oci://` (verified: no OCI handling in renovate.json); the plan tracks the renovate gap as a follow-up, but Chart.yaml carries nothing reminding maintainers to bump manually. Fix: comment above the dependency. (ArgoCD-side risk verified low: base ships argo-cd chart 10.10.0 → ArgoCD 3.1, which supports OCI chart dependencies natively; registry is public/anonymous.)

- [x] [Review][Defer] gpt-researcher model IDs are unguarded against the gpu-ai llama-swap roster [charts/gpt-researcher/values.yaml:41-43] — deferred: verified-correct today (qwen3-8b-q8 / qwen38-orca / qwen38-ara all resolve against services/gpu-ai/prod/values.yaml:127,143 + charts/llama-swap/values.yaml:292), but nothing ties consumer to provider — routine roster churn would silently break dev research with the llama-swap test suite green (it asserts sidecar/PVC/sentinels, never the model list). Filed by the verification-gap lens with patch-or-defer disposition; add a cross-render roster assertion with the next llama-swap suite change.

#### Rejected

#### User review comments — round 2 (2026-10-13)

All applied and re-validated (helm lint 4/4, pytest 5/5):

- [x] [Review][Patch] coder wildcard host — subchart ingress DISABLED; wrapper-owned `charts/coder/templates/ingress-coder.yaml` bridges `*.dev.scifi.farm` → Service `coder:80` with `cluster-wildcard-cert`.
- [x] [Review][Patch] forgejo `DOMAIN`/`ROOT_URL` — searched the chart: `gitea.config` already renders into a Secret (`<fullname>-inline-config`) and `additionalConfigFromEnvs` supports `secretKeyRef` sources, but the values must live in a values file either way → moved the literals to `custom-values/dev/prod-values.yaml` (`forgejo.forgejo.gitea.config.server`), chart stays host-free.
- [x] [Review][Patch] gpt-researcher `OPENAI_BASE_URL` + `SEARX_URL` now come from a Secret — `charts/gpt-researcher/templates/secret-endpoints.yaml`, env via `secretKeyRef` (new render test pins this).
- [x] [Review][Patch] `github-pat` ExternalSecret reads the item's **password** field (bitwarden-login store), not a custom `token` field.
- [x] [Review][Patch] No reused prod/lab UUIDs on dev — cert-manager-solver-token, argocd-sso-secret, and hivetools mcp-sso are all `OVERRIDE_NEEDED` for NEW dev items (same contents as prod); hivetools `clientId: dev-mcp` set explicitly.

**Bitwarden items to create (all NEW dev items, org vault):**

| # | Item name | Type | Contents (★ = field beyond username/password) |
|---|---|---|---|
| 1 | `dev-argocd-sso` | LOGIN | username = client-id, password = client-secret, ★ custom text field `issuer` = `https://login.spencerslab.com/realms/SpencersLab` |
| 2 | `dev-cloudflare` | LOGIN | password = Cloudflare API token (Zone:DNS:Edit for scifi.farm) |
| 3 | `dev-mcp-sso` | LOGIN | username = client-id (`dev-mcp`), password = client-secret |
| 4 | `dev-coder-sso` | LOGIN | username = client-id, password = client-secret, ★ URI = `https://login.spencerslab.com/realms/SpencersLab` |
| 5 | `dev-coder-pg` | LOGIN | username = `coder`, password = DB password |
| 6 | `dev-forgejo` | LOGIN | password = SECRET_KEY (`openssl rand -hex 32`; username arbitrary) |
| 7 | `dev-forgejo-admin` | LOGIN | username + password = initial Forgejo admin |
| 8 | `dev-forgejo-pg` | LOGIN | username = `forgejo`, password = DB password |
| 9 | `dev-forgejo-oauth` | LOGIN | username = client-id, password = client-secret |
| 10 | `dev-github` | LOGIN | password = fine-grained GitHub PAT |

**Keycloak clients to create on the LAB Keycloak** (login.spencerslab.com, realm `SpencersLab`): `dev-argocd` (redirect `https://cluster.dev.scifi.farm/auth/callback`), `dev-coder` (redirect `https://coder.dev.scifi.farm/*`), `dev-forgejo` (redirect `https://git.dev.scifi.farm/*`), `dev-mcp` (no redirects — MCP SSO is dormant repo-wide).

Note: hivetools' MCPOIDCConfig templates its issuer as `login.{{ domain }}` → dev would render `login.scifi.farm` (nonexistent). Harmless while the per-server OIDC blocks stay commented out; needs a keycloakx/hivetools chart fix when the MCP OIDC rollout reaches dev (added to follow-ups).

- CODER_OIDC_ICON_URL points at third-party `gitlab.alexsaphir.com` — user chose to keep gpu parity (identical to gpu's login page today); no change.
- Plan file is stale about Coder (external chart + service templates vs the charts/coder wrapper) — fix would be editing the plan under review; the wrapper matches the helm-chart-creation skill rule (external chart needing secrets + CNPG gets wrapped) and is render-equivalent (verified via helm template).
- Plan claims services/dev/prod/templates contains pg-coder/secrets-coder — same plan-edit rule.
- Shared Keycloak client redirect-URI list omits the MCP consumer — fix would be a plan edit; hivetools OIDC is deliberately dormant repo-wide (mcpoidcconfig-keycloak.yaml is UNREFERENCED, per-server oidc blocks commented out "OIDC rollout pending"), so MCP SSO needs no redirect URIs yet.
- Plan's "e.g. dev-clients" contradicts custom-values `clientId: mcp` — plan-edit rule; the code is internally consistent (hivetools chart default clientId `mcp`; the custom-values comment states the requirement explicitly).
- dev service skips the proxy values entry (AGENTS.md "all three") — low, intentional: public hub routing is an explicit user-decided out-of-scope item tracked in the plan's follow-ups; mesh/LAN-only is the intended state; adding hub entries is a design change, not a direct correction.
- GitHub PAT absent from the verbatim Goal — false: documented as user-confirmed decision #4 in the same plan (the intent-alignment auditor received only the Goal section).
- Coder placement diverges from the verbatim scope ("the two new charts") — not a defect: the wrapper matches the repo's helm-chart-creation rule and renders equivalently; knock-on effects (renovate tracks 2.35.2 via Chart.yaml deps; wildcard host lives in the chart) are documented in code comments. Informational.
- Delegated decisions concretized at implementation time (gptr-nextjs image, NEXT_PUBLIC_GPTR_API_URL unset + backend ingress fallback, chart-native forgejo PVC, realm/clientId pinned, mcp-pg-keycloak sentinel) — informational: all trace to explicit plan delegations.
- Deploy-time expectations no test can exercise (cluster annotations, Bitwarden items, DNS, realm creation, certs) — informational: user-owned by decision #8, encoded as sentinels + the User actions section.

#### User review round 3 — UUIDs + shared SSO item (2026-10-13)

Supersedes the round-2 item table: ONE shared dev SSO item serves all four
SSO consumers, the DB items are shared, and all UUIDs are now filled.

- [x] [Review][Patch] base argocd-sso issuer rewired from the Bitwarden custom field `issuer` (bitwarden-fields) to the item **URI** (bitwarden-uri) — same pattern as coder, so the shared SSO item needs no custom fields. **Base-chart change: affects every cluster** — the existing shared lab item (6bc8ead2…) must have its URI set (user is updating it). (`charts/immich` still reads `property: issuer` from its own item — untouched.)
- [x] [Review][Patch] ONE shared dev SSO item `d07b1bec-d02c-4580-8544-b4e2000e1783` wired into all four consumers: argocd-sso-secret (top + base), coder-sso-secret, forgejo-sso (renamed from forgejo-oauth in chart values/template/custom-values), hivetools mcp-sso. hivetools `clientId` override removed (MCPOIDCConfig dormant) — comment says to set it to the shared client's id when the MCP OIDC rollout reaches dev.
- [x] [Review][Patch] Shared dev DB item `47d1d689-b615-4461-8b57-b4e20015ae75` used for coder-pg, forgejo (SECRET_KEY), forgejo-admin, forgejo-pg: pg ExternalSecrets hardcode the username to the CNPG initdb owner (`coder` / `forgejo`) and read only the password; the coder DSN hardcodes the `coder` user (pg_username remoteRef dropped).
- [x] [Review][Patch] Remaining UUIDs filled: dev-cloudflare `918d3521-f584-45f9-8113-b4e2000d1d64` (cert-manager-solver-token, top + base), dev-github `522b1cc4-2c74-4399-887d-b4e20014b2d2`. No OVERRIDE_NEEDED remains in custom-values/dev/prod-values.yaml.

Re-validated: helm lint 5/5 (base, coder, forgejo, gpt-researcher, dev umbrella);
base argocd-sso render shows issuer via bitwarden-uri; pg secrets render the
hardcoded usernames; pytest 5/5.

#### User review round 4 — ingress placement + endpoint composition (2026-10-13)

- [x] [Review][Patch] Deleted charts/coder/templates/ingress-coder.yaml — the wildcard
      ingress is driven generically by the consuming service: services/dev/prod/values.yaml
      sets `coder.coder.coder.ingress.{enable,host,tls}` (slice key → wrapper subchart key →
      official chart key; comment explains the triple), which renders the official coder
      chart's own Ingress — same mechanism gpu uses from custom-values. Render verified:
      host *.dev.scifi.farm, TLS cluster-wildcard-cert.
- [x] [Review][Patch] gpt-researcher endpoints now composed from .Values.domain
      (https://llama.{{domain}}/v1, https://searxng.{{domain}}). Kept as a plain Secret:
      ESO's validating webhook rejects ExternalSecrets with no data/dataFrom
      (external-secrets#3478 — "ExternalSecrets is not a templating engine"); a true
      ExternalSecret would need a Bitwarden item to fetch. Rationale recorded in the
      template comment. NOTE: on dev (domain=scifi.farm) the URLs resolve to
      llama.scifi.farm/searxng.scifi.farm — those hosts must exist for dev when this
      ships (user's DNS/proxy plan).
- Test updated (composed URLs); helm lint 4/4, pytest 5/5.
