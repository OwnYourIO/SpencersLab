# RESEARCH — cf-97 Get Dev Forgejo Runner working

Feature: `2026/2026-11-cf-97-bug-forgejo-runner` · written by `agent-research` 2026-11-01
STORM run (6 perspectives, live-grounded). Sources are web pages/files I actually fetched
today plus live-cluster reads and repo file:line citations; inference is labelled. Method
audit: perspectives enumerated in the Sources/Contradictions sections below (session
permission rejected writing `storm-runs/` intermediates outside the ticket folder — only
this file lands).

## TL;DR

1. **Root cause found with direct evidence**: the runner container crash-loops (exit 1,
   16 restarts since 15:40 UTC today) logging `invalid configuration: invalid 'server'
   settings: connection "default" is invalid: 'uuid' is empty` — the rendered config.yaml
   has an EMPTY uuid, i.e. the Bitwarden item `d3dafd1a…` has no runner uuid in its
   username field.
2. **Why there is "no runner in the org"**: the declarative (uuid+token) model never
   creates anything server-side — a runner record must FIRST be created on git.scifi.farm
   (UI/API), which is what yields the uuid+token pair. The evidence says that creation was
   never completed, so there is no record anywhere (the org list also shows instance-level
   runners — an empty org page rules out every scope, not just org).
3. Everything else is healthy: ESO syncs (`SecretSynced`), dind sidecar running, ArgoCD app
   `dev-forgejo-runner-dev` applied, server 15.0.10 up with Actions enabled by default,
   `[queue]` default is disk-backed `level` (no Redis), no app.ini change needed.
4. The shipped comments calling the vault password a **"registration token"** are wrong in
   v13/15 terms (it is the runner's long-lived Token shown at record creation; the
   registration-token flow belongs to the deprecated exchange) — likely what misled the
   user ("Thought I gave it credentials").
5. Fix shape: human creates the runner record (decide org vs instance scope — card wording
   says org), pastes uuid+token into the vault item, reloader bounces the pod, verify the
   `declared successfully` log line + online in the UI; repo-side: wording fix in the chart
   comments + repair the stale dind-pin test assertion (29.9.1 vs live 29.9.2).

## Verified live facts (readonly-dev-kubernetes MCP + public endpoints, 2026-11-01)

- STS `dev-forgejo-runner-dev` (default ns): replicas 1, updated 1, **available 0**;
  tracked by ArgoCD app `dev-forgejo-runner-dev` (tracking-id annotation).
- Pod `dev-forgejo-runner-dev-0`: created 15:40:13Z today (old pod killed 15:40:12 — a
  secret-change bounce consistent with the user editing the vault "today"); `dind`
  initContainer Running+ready (`docker:29.9.2-dind`, socket probe passes); `runner`
  container **terminated, exit 1, restartCount 16**; container log:
  `Error: invalid configuration: invalid 'server' settings: connection "default" is invalid: 'uuid' is empty`.
- ExternalSecret `dev-forgejo-runner-dev`: Ready=True `SecretSynced` (the 2026-10-24
  SecretSyncedError incident is over; ESO syncs happily even with an EMPTY Bitwarden
  username — it is not proof the uuid arrived; the crash line is).
- Old two-controller STS `dev-forgejo-runner-runner-dev` is gone (per-instance refactor
  landed). No `forgejo-runner-infra` deployment (un-wired 2026-10-25 by user decision).
- Forgejo server: Deployment pod `dev-forgejo-…`, **15.0.10**, chart `forgejo-17.3.1`,
  Ready 1/1; service `dev-forgejo-http:3000` exists; public ingress
  `https://git.scifi.farm/api/v1/version` → `{"version":"15.0.10+gitea-1.22.0"}` (the
  instance is up and Actions-capable by default).
- NOT reachable from this session: argocd-ns Application CR (RBAC), Secret contents
  (RBAC), Bitwarden item fields (no MCP surface) — hence the vault-state detail below is
  inference from the runner's own error line.

## Key findings (with sources; [n] resolves in Sources)

### F1 — The registration model is two different things; the chart uses the declarative one

- A runner authenticates with a **(uuid, token)** pair sent as `x-runner-uuid` /
  `x-runner-token` headers on every Connect-RPC call to `<instance>/api/actions`
  [S1 interceptor.go, S2 http.go: `baseURL = TrimRight(endpoint,"/") + "/api/actions"` —
  the config `url:` is the **instance base URL**, no `/api/v1` suffix; the chart's
  `http://dev-forgejo-http:3000` shape is correct].
- There are exactly **two ways to obtain that pair** [S10 v15.0 registration docs]:
  1. **Create the record first, then configure the runner**: UI "Create new runner"
     (shows UUID + Token once, copy them into `server.connections`) — or the HTTP API
     `POST /api/v1/orgs/{org}/actions/runners` / `…/repos/{o}/{r}/actions/runners` /
     `/api/v1/user/actions/runners` / `/api/v1/admin/actions/runners` with
     `{name, description?, ephemeral?}` → **201 `{id, uuid, token}`**, token
     server-generated (`GenerateToken`, 40-char hex) [S3 api.go routes, S4 shared/runners.go
     RegisterRunner, S5 structs/runner.go]. The daemon NEVER creates a record — on start it
     calls `Declare`; unknown uuid or token mismatch →
     `CodeUnauthenticated "unregistered runner"` → the daemon **exits** [S1, S6 daemon.go
     createRunner].
  2. **Registration-token exchange (the deprecated flow)**: the `register` CLI sends a
     one-time *registration token* to the server `Register` RPC; the server then creates a
     NEW record with a fresh server-generated uuid+token and writes `.runner`
     [S6 runner.go Register lines 44–110; repo prior research: register CLI deprecated in
     v13]. The `/registration-token` API endpoints exist in 15.0 but are marked
     **deprecated** ("Use the web UI or RegisterRunner instead") [S3, S5 org/action.go:173].
- The token that belongs in `token:`/`token_url:` is the **long-lived runner Token from
  record creation** — NOT the exchange-style "registration token". All `/api/v1/.../runners`
  UI pages + the offline CLI (below) mint it; the label "password = registration token" in
  this repo's comments is a misnomer that invites exactly this card's confusion.
- **Offline registration** (GitOps-friendly, needs shell on the server — not available to
  agents here): `forgejo forgejo-cli actions register --name X --scope myorg --secret
  <40-hex>` creates the record and the uuid is **deterministically derived from the first
  16 hex chars of the secret you chose** [S10]. This is the only scope-flexible path where
  the operator generates the secret themselves.

### F2 — What makes the daemon fail to start, straight from v13.2.1 source

Config validation (`applyTo` per connection, [S2 config.go:444-495]) fails FAST (daemon
exits, container restarts in a loop) with one of:
- - "`url` is empty" / malformed `url` / scheme must be http|https;
- "`uuid` is empty" ← **today's live failure**;
- malformed `uuid` (must parse as RFC-4122 — a placeholder like `test-uuid` fails);
- `token` and `token_url` both empty / mutually exclusive both-set;
- `token contains invalid characters` — pattern `(?i)^[a-z0-9]*$` [S2:672] (a UUID-style
  token with dashes, or base64 with `+/=`, would fail).
After validation passes: `configCheck` requires a running Docker iff labels use the docker
schema [S6 daemon.go:161]; **`daemon` refuses an ephemeral server record**
("connection … requires an ephemeral runner, which is not supported in daemon-mode")
[S6:81] — create the record with `ephemeral: false` (UI default); `Declare` first, then
poll (`fail to invoke Declare` + `unregistered runner` = record missing/wrong token =
the NEXT failure you'd hit once uuid is filled but the record still doesn't exist);
healthy line = `runner: <name>, with version: …, declared successfully` [S6:104].
`CREDENTIALS_DIRECTORY` substitution for `token_url: file:…` is confirmed in source
[S2:646-649] and the chart wires it correctly (mount path == env value == token file).
**`.runner` file is not part of this design at all**: only `register` /
`create-runner-file` write it; a `.runner` alongside `server.connections` is a hard
conflict error [S2 registration.go:37-39, SaveRegistration callers only in those CLIs] —
so **no PVC is needed for registration persistence** (the data PVC serves cache/workdir;
identity lives in Bitwarden). The brief's `GITHUB_SERVER_ADDRESS` / `RUNNER_CONFIG` env
vars **do not exist in runner v13** (source-wide `os.Getenv` sweep returned only
DOCKER_HOST, FORGEJO_CLIENT_TIMEOUT, CREDENTIALS_DIRECTORY, ACTIONS_RUNTIME_*, etc.).
Version skew guard: against a server without the Declare method the runner logs
"Because the Forgejo instance is an old version, skipping declaring…" and continues
[S6:96-99]; Forgejo **15.0.10 implements Declare** (actions-proto v0.7.0) [S6-server],
so 13.2.x ↔ 15.0.10 is a supported pairing; runner 13.x latest is **13.2.1 (2026-10-29,
dependency bumps only — no behavior change)** [S8].

### F3 — Scope model and the exact card symptom ("there isn't any runner in the org")

- Four registration locations and their visibility, per the v15.0 docs [S10]:
  instance (`/admin/actions/runners`, serves all repos), **org**
  (`/org/{org}/settings/actions/runners`), user (`/user/settings/actions/runners`),
  repo (`/{owner}/{repo}/settings/actions/runners`).
- Crucially: **"Each of these pages will display any existing runners … including runners
  from higher level registrations"** — an instance-wide runner DOES appear on the org's
  runner list [S10]. So an org page showing NOTHING means **no runner record exists at any
  scope** — it is not a scope/visibility artifact. Combined with F2's crash line (uuid
  empty ⇒ the daemon never even reached the server), the chain closes: **the record was
  never created on git.scifi.farm; the vault item therefore has no real uuid/token to
  hold** ("Thought I gave it credentials" — credentials were generated nowhere).
- The prior ticket's B3 ruling (2026-10-21) was **instance-admin scope, created once via
  UI** [repo DECISIONS] — consistent with the design, but the *creation step was a human
  to-do that evidently never completed for the dev item d3dafd1a…; the live crash proves
  the config side arrived empty, not the vault shape.

### F4 — Kubernetes deployment shapes (2026-11 state)

- **No official Forgejo runner Helm chart**: the `forgejo` org repos list contains only
  `runner` (no `*-helm`) [S9 API]; the official forgejo-helm is server-only. **The brief's
  "official/`forgeops/forgejo-runner` image and its Helm chart" premise is false** — no
  forgeops repo surfaced by any search; the official image path is
  `code.forgejo.org/forgejo/runner` ≡ docs host `data.forgejo.org/forgejo/runner` [prior
  RESEARCH C2; README build refs S7].
- Community charts (not used here, shape reference only): **dtechvision/forgejo-runner-helm-chart**
  v0.0.1, self-declared untested; its CURRENT values shape is `forgejo.url` +
  `forgejo.existingSecret` (token in a Secret), `runner.{name,labels,ephemeral,capacity}`,
  `dind.{enabled,repository,tag,rootless,extraArgs}`, `kubernetesBackend.enabled` (spawns
  job pods — the experimental backend, off by default), `replicaCount: 2`,
  `persistence.enabled: false`, `customConfig` raw-YAML merge [S11 fetched today]. None of
  this matches the brief's `config.RUNNER_REGISTRATION_TOKEN`/`RUNNER_CACHES` env shape —
  those names belong to gitea/act_runner-era examples. **wrenix** chart still lists 0.7.6
  on ArtifactHub but remains absent from its repo main (prior research); **jkline/
  forgejo-runner** is another community chart [S12 search].
- The repo's own hand-rolled app-template chart (`charts/forgejo-runner`, STS + privileged
  dind sidecar + declarative config via ESO template) already matches the source-verified
  v13 contract; the only live-breaking gap is the empty vault uuid, not the chart.
  Labels: the chart's 5-label set (`ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`,
  `docker`, `node22` → catthehacker/node images) is valid label grammar
  `<name>:<schema>://<image>` with optional `?platform=` options [S13]; there are **no
  reserved `cache:` / `private` runner labels in v13** — cache is a `cache:` CONFIG section
  (`enabled`, `dir=$HOME/.cache/actcache`, `external_server`, `secret`/`secret_url`,
  `proxy_port`), not a label, and jobs wait for a matching label until
  `ABANDONED_JOB_TIMEOUT` (24h default) [S14 cheat sheet actions section, S2 cache struct].

### F5 — Server-side app.ini: nothing to change

- `[actions] ENABLED = true` and `DEFAULT_ACTIONS_URL = https://data.forgejo.org` are
  defaults [S14 v15.0 cheat sheet]; the dev values set no `[actions]` keys [repo
  charts/forgejo/values.yaml] → Actions live. `[queue] TYPE` default is **`level`**
  (disk-backed LevelDB under APP_DATA_PATH), `channel`/`redis`/`dummy` are the other
  options — **Redis is NOT required** for Actions at single-instance scale [S14]; the
  brief's "redis requirement" is a Gitea-era doc artifact. Job pickup is Connect-RPC
  poll-based (FetchTask), queue type is invisible to the runner [S15 poller.go].
- Runner maintenance: server marks `last_online` on every authenticated call [S1]; a
  `cron.cleanup_offline_runners` task exists but is not enabled by default [S14 TOC].

### F6 — What this repo already has (no rediscovery)

- Chart + wiring: `charts/forgejo-runner/{values.yaml (runner 13.2.0, dind 29.9.2-dind),
  templates/secret-runner.yaml (ESO uuid←username, token←password, config.yaml template)}`,
  deployed once for dev via ApplicationSet alias `charts.forgejo-runner-dev` +
  **top-level** `forgejo-runner-dev:` slice (the only values path that flows — FRICTION F02
  rule), URL `http://dev-forgejo-http:3000`, sentinel `bitwardenIds.runner-token` ↔
  `custom-values/dev/prod-values.yaml` UUID `d3dafd1a-3d88-454e-88d4-b4ec010ae2c2`.
- Prior decisions NOT to re-litigate: B3 instance-admin UI creation + item never the
  `forgejo-token` item; decision B1 one-identity-one-replica; 2026-10-25 infra-runner
  un-wire (relocation pending, vault item `dev-forgejo-prod-runner` stays out of dev);
  k3s MTU warning (forgejo/runner#1779) in the chart header + RESEARCH-dind-supplement.
- **Contract drift found while reading**: `tests/services/dev-forgejo-runner.sh` t2 asserts
  `docker:29.9.1-dind` but renovate commit `975b9d89d` bumped values to `29.9.2-dind`
  (live pod runs 29.9.2) — the suite goes RED on the next run [repo file:line values.yaml:95
  vs dev-forgejo-runner.sh:293]. Mechanical test repair (coord routes to a test session per
  repo rules).
- `charts/forgejo/Chart.yaml` appVersion still reads 15.0.9 while live is 15.0.10 — stale
  annotation only, the OCI dep 17.3.1 is what deployed 15.0.10.

## Contradictions and how to weigh them

1. **Brief's `forgeops` chart + `config.RUNNER_*` env shape vs reality** — nothing like it
   exists officially (F4); weigh the org-repo API + today-fetched dtechvision values.
   Plan impact: don't chase the brief's item-2 naming; the repo chart already implements
   the correct v13 shape.
2. **"Registration token" (shipped comments) vs "Token at creation" (docs/API)** —
   docs + server source win; the comments are legacy wording from the pre-refactor ticket
   [repo chart secret-runner.yaml:3, custom-values:84]. Fix wording in the same ticket.
3. **Card's org-scope expectation vs prior B3 instance-scope ruling** — not blocking:
   instance runners ARE listed on the org page [S10], so either scope clears the symptom;
   org scope additionally limits blast radius. Planner should present the choice (Open Q2)
   with best-guess = **create it org-scoped** given the card wording, unless the user's
   answer says otherwise.
4. **ESO `SecretSynced` vs empty uuid** — ESO readiness is NOT proof the identity fields
   arrived; the daemon's own crash line is the authority. Tests/chunks must verify via pod
   logs + the `declared successfully` line, never via ESO condition alone.
5. **Test pin 29.9.1 vs values/live 29.9.2** — renovate vs hand-written contract; values+
   live win, test needs the mechanical amendment.

## Root cause (most likely, with the evidence grading)

**Verified**: runner exits on `uuid is empty` (log line read today) — config rendered from
the vault item's `username`. **Strong inference (cannot read the vault here)**: the
`dev-forgejo-dev-runner` item has an empty (or non-UUID) username because **the server-side
runner record was never created** — the only source of that uuid — matching the card's
"Thought I gave it credentials, but there isn't any runner in the org". The 2026-10-24
SecretSyncedError incident is NOT the current cause (ESO synced since; the incident's
deferred debug follow-up can be closed by this ticket's evidence).

## Recommended fix shape (for the planner)

1. **Human one-time step (blocks success, cannot be a repo chunk)**: on git.scifi.farm,
   Org → Settings → Actions → Runners (or Admin → Actions → Runners if the user keeps the
   B3 instance scope) → *Create new runner* (persistent, NOT ephemeral) → copy the shown
   **UUID + Token** into Bitwarden item `d3dafd1a…` (username=UUID, password=Token). ESO
   refresh ≤1h or immediate on resync + stakater reloader bounces the pod.
   (Alternative fully-offline secret: `forgejo-cli actions register --scope <org> --secret
   <40hex>` on the server host — derives uuid deterministically; requires shell the agents
   don't have → still a human step. Do NOT use `/runners/registration-token` endpoints —
   deprecated, incompatible with this chart's declarative model.)
2. **Repo chunk — comments/wording truthfulness**: `password = registration token` →
   `password = runner token (from record creation)` at the three shipped sites
   (charts/forgejo-runner/values.yaml header, templates/secret-runner.yaml header,
   custom-values/dev comment); note that the vault **username must be a valid UUID** and
   the daemon fail-fasts otherwise (this ticket's failure mode), so an empty/placeholder
   username is a known-bad state worth documenting.
3. **Chunk — test contract repair**: t2 dind assertion 29.9.1→29.9.2 (or the suite goes
   red for unrelated reasons); route per repo "faulty test" rule.
4. **Verification ACs for the post-fix chunk**: resources_list/resources_get (readonly MCP,
   `resources_list` names come back redacted — use `resources_get` per name) →
   STS availableReplicas=1; pod `runner` container ready, restarts not climbing;
   `pods_log` contains `declared successfully`; org UI shows the runner online; optional
   smoke: a tiny `.forgejo/workflows/*.yml` with `runs-on: docker` completes.
5. **Optional hygiene chunk (separate concern, likely a `dep` ticket)**: runner pin
   13.2.0→13.2.1 (dep-only changelog [S8]); stale `appVersion: 15.0.9` in
   charts/forgejo/Chart.yaml.
6. **Explicitly NOT the fix**: app.ini `[queue]`/redis changes, chart topology changes,
   `.runner` PVC persistence, `GITHUB_SERVER_ADDRESS`/`RUNNER_CONFIG` env (nonexistent in
   v13), scope/visibility explanations (an empty org list rules them out — F3).

## Open questions (would have asked the user; best guesses taken, do NOT re-ask mid-run)

1. **Q: Is the Bitwarden item `dev-forgejo-dev-runner` (d3dafd1a…) currently empty in the
   username field, or does it hold a uuid from some never-created/lost record?**
   Best guess: never populated because no server record exists (crash line + empty org
   page). Impact: if instead it holds a *stale* uuid (record deleted in the 2026-10-24
   flap), the fix is still "create record, paste new uuid+token" — same steps, so low risk.
2. **Q: Which registration scope do you want now — org (your card wording) or the
   previously ruled instance-admin?** Best guess: **org-scoped on the org that owns the CI
   work** (matches the card); note instance still appears on org pages, so switching is
   cosmetic for usage but changes which admin page manages it. Impact: which settings page
   the human uses + future labels strategy.
3. **Q: Which org name on git.scifi.farm?** Best guess: whichever org hosts the repos that
   need runners (not enumerable via anonymous API). Impact: none on repo chunks; the human
   knows where they clicked.
4. **Q: Should the 2026-10-24 deferred debug (app recreation + SecretSyncedError root
   cause) ride this ticket or stay separate?** Best guess: stay separate — today's ESO is
   synced and the failure is fully explained by the empty uuid. Impact: chunk count.
5. **Q: Do you want the infra-instance runner relocation (b1add65b item) folded into this
   card?** Best guess: no — Services=dev, relocation was explicitly deferred 2026-10-25.
   Impact: scope creep guard.
6. **Q: May the smoke test push a workflow file to a dev repo once the runner is online?**
   Best guess: yes on a scratch repo (the pipeline normally validates via renders; this is
   the only end-to-end proof). Impact: final-AC shape.
7. **Q: Is the `forgejo-token` vault item's token site-admin capable (could automate the
   POST)?** Best guess: no (it is the Coder workspace git token) → keep the human UI step;
   automation would need a new admin-scoped item, more secret sprawl. Impact: whether a
   chunk can script registration.

## Adjacent

- Forgejo latest line moved to **17.0 / LTS 15.0.11**; dev on 15.0.10 is one patch behind
  LTS (docs switcher evidence [S10]); OCI chart dep bumps stay manual (Chart.yaml NOTE).
- The dtechvision chart's `kubernetesBackend` marketing again reflects the experimental
  plugin (unmerged upstream per prior RESEARCH C6) — still not production.
- dind `--mtu` mitigation (forgejo/runner#1779) already documented in the chart header;
  first real workflow run may surface it — that is job-execution scope, not registration.

## Sources

- [S1] https://forgejo.org/docs/v15.0/admin/actions/registration/ — fetched 2026-11-01:
  four registration locations + inherited visibility; UUID+Token shown at Create; copy into
  `server.connections`; offline `forgejo-cli actions register --secret` (uuid = first 16
  hex chars); persistent vs ephemeral; register CLI deprecated.
- [S2] Go module `code.forgejo.org/forgejo/runner/v13@v13.2.1` via
  https://proxy.golang.org (zip fetched 2026-11-01): internal/pkg/config/config.go
  (connection validation lines 444-495, validTokenPattern line 672,
  CREDENTIALS_DIRECTORY substitution 646-649), registration.go (.runner conflict,
  SaveRegistration callers), internal/pkg/client/http.go (`/api/actions` base, headers,
  FORGEJO_CLIENT_TIMEOUT).
- [S3] https://codeberg.org/forgejo/forgejo/raw/branch/v15.0/forgejo/routers/api/v1/api.go
  — org/repo runner routes via addActionsRoutes (`…/actions/runners`), user
  `/api/v1/user/actions/runners`, admin `/api/v1/admin/actions/runners`,
  `/registration-token` endpoints nolint:staticcheck-deprecated.
- [S4] …/routers/api/v1/shared/runners.go — RegisterRunner: 201 `{id,uuid,token}`,
  ownerID/repoID exclusivity, ephemeral flag.
- [S5] …/routers/api/v1/org/action.go + modules/structs/runner.go — org RegisterRunner
  wrapper; RegisterRunnerOptions{name,description,ephemeral}/Response fields; GetRegistra-
  tionToken deprecation comment line 173.
- [S6] …/routers/api/actions/runner/interceptor.go + runner.go (v15.0/forgejo) — x-runner-
  uuid/x-runner-token auth, `unregistered runner` Unauthenticated (unknown uuid OR token
  mismatch), last_online stamp, Register=registration-token exchange creates new record,
  Declare handler present (actions-proto v0.7.0 in go.mod).
- [S7] runner v13.2.1 README.md (zip) — amd64/arm64 support; official image/CI pointers.
- [S8] https://data.forgejo.org/api/v1/repos/forgejo/runner/releases?limit=6 +
  releases/tags/v13.2.1 — fetched 2026-11-01: v13.2.1 2026-10-29 (dependency bumps only);
  13.2.0/13.1.0/13.0.0 as prior research.
- [S9] https://data.forgejo.org/api/v1/orgs/forgejo/repos?limit=100 — no helm-chart repo
  in the forgejo org (no official runner chart).
- [S10] = [S1] (docs v15.0 = lab's 15.0.10 LTS line; docs switcher shows Latest v17.0.1,
  LTS v15.0.11).
- [S11] https://raw.githubusercontent.com/dtechvision/forgejo-runner-helm-chart/main/values.yaml
  — fetched 2026-11-01: current values shape (F4).
- [S12] https://artifacthub.io/packages/helm/forgejo-runner/forgejo-runner (wrenix 0.7.6
  listing) + https://codeberg.org/jkline/forgejo-runner — via global-searxng 2026-11-01.
- [S13] runner zip internal/pkg/labels/labels.go — label grammar + `?platform=` options.
- [S14] https://forgejo.org/docs/v15.0/admin/config-cheat-sheet/ — [queue] TYPE default
  level (+redis/dummy options), [actions] ENABLED=true/DEFAULT_ACTIONS_URL/
  ABANDONED_JOB_TIMEOUT=24h/LOG+ARTIFACT retention, cron.cleanup_offline_runners.
- [S15] runner zip internal/app/poll/poller.go — FetchTask idempotent poll loop (no queue
  coupling), shutdown limiter path.
- [S16] https://git.scifi.farm/api/v1/version → `15.0.10+gitea-1.22.0` (fetched 2026-11-01).
- [S17] Live dev cluster via readonly-dev-kubernetes MCP 2026-11-01:
  resources_get StatefulSet/ExternalSecret/Pod `dev-forgejo-runner-dev*`, pods_log runner
  container (uuid-empty error), events_list (15:40 recreation, BackOff 16:35), Service
  dev-forgejo-http, forgejo pod labels (15.0.10, chart forgejo-17.3.1);
  StatefulSet dev-forgejo-runner-runner-dev = not found (pruned).
- [S18] Local repo (verified 2026-11-01, this worktree @ main tip 6796aa50d):
  charts/forgejo-runner/{values.yaml:1-212, templates/secret-runner.yaml:1-77,
  Chart.yaml}, charts/forgejo/{values.yaml, Chart.yaml:13-14},
  services/dev/prod/values.yaml:96-145, custom-values/dev/prod-values.yaml:82-89,
  tests/services/dev-forgejo-runner.sh:293, git log 975b9d89d; prior tickets
  2026-10-feat-forgejo-infra-and-runner/{RESEARCH.md, DECISIONS.md B3/B4,
  RESEARCH-dind-supplement.md}, 2026-10-refactor-forgejo-runner-per-instance/
  {plan, DECISIONS.md, FRICTION.md}, 2026-10-feat-forgejo-auth-support/chunks/C06.md.
