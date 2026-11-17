# PLAN: cf-139 — Pushes to main auto-sync every cluster (no manual `argocd sync`)
feature: 2026/2026-11-cf-139-feat-argocd-webhook-sync
card: AD-139 "Sync ArgoCD with Webhooks" (Y3vPeX4nhtDbsdwCg)
status: APPROVED 2026-11-17 (batch-2 round) with the re-cut 3-chunk design as-is + two
folded deltas: OQ5 "merge first, fill later" (sentinels ship through merge; the relay app's
crash-loop-until-UUID-PR posture is the ruled, accepted behavior) and OQ7 "wider filter"
(the ref filter is a CONFIG LIST `allowed_refs`, grounded on repo evidence — see Open
questions (resolved)). OQ6 prune=false/never-force confirmed as ruling.
Earlier same-day rework from the batched OQ1–OQ4 answers: OQ1 kill-switch KEPT — no flip;
OQ2 relay IN scope now, hosted proxy-local, one shared HMAC; OQ3 flip-shape recorded for a
future flip only; OQ4 DNS leak note-only. Old single chunk C01 (pre-flip audit + flip
runbook) is void — superseded by the relay design below.

## Goal

Make a push to GitHub `main` land on every cluster automatically, without touching the
`services.<cat>.selfHeal="false"` kill-switch annotations or any appset gate: an
HMAC-verified webhook relay (`argocd-hook`) hosted on the proxy-local hub receives the
GitHub push hook on the single public edge, then drives an ACTUAL SYNC of each cluster's
root app (and of every still-Out-Of-Sync app sourced from the repo) through that cluster's
own ArgoCD REST API using the existing `mcp-bot` apiKey RBAC. The card's manual workflow
("go into each cluster, run argocd sync") is automated; the automated syncPolicy stays off
everywhere.

## Scope decision — why sync-by-API, not the flip or a refresh webhook

- Webhooks alone only REFRESH, never sync (RESEARCH [4][10]); with the gate kept off, a
  refresh would only flip apps to OutOfSync — the user would still sync by hand. So the
  relay calls the sync API instead.
- No flip: the user ruled the kill-switch stays (OQ1). Nothing in this plan edits the 11
  `services/<cat>/prod/templates/appset.yaml` gates, `charts/base/templates/appset-charts.yaml`,
  or `charts/base/values.yaml`.
- Direct GitHub→cluster hooks remain physically impossible (`cluster.*` is mesh-only,
  public NXDOMAIN measured [R Agenda 2]); the one-public-edge relay (shape C) is the chosen
  inbound form, adapted from refresh-fan-out to sync-fan-out.

## Context — verified facts

- **Kill-switch + gate** [E §2, re-verified 2026-11-17]: `services/infra/prod/templates/appset.yaml:126`
  and `charts/base/templates/appset-charts.yaml:124-143` render `automated` only when the
  cluster-secret annotation is absent or `"false"`-free; live root apps carry syncOptions only.
  Kept as-is by ruling. `infra`/`dev`/`gpu`/`home` roots sit OutOfSync today **[E §2 table]**.
- **Root-app syncOptions lack `RespectIgnoreDifferences`** (service appset renders only
  `CreateNamespace` + `ServerSideApply`, verified 2026-11-17 at `services/infra/prod/templates/appset.yaml:131-134`);
  child apps carry it via the charts appset **[E]**. ⇒ the relay MUST use non-force API syncs
  (force could clobber live-owned fields; the 4 shipped argocd-cm `ignoreDifferences`
  customizations incl. the system-upgrade `Plan /status` fix protect detection-level sync
  either way — `charts/base/values.yaml:116-142`, 2026-10-20 incident comment).
- **Sync-capable credentials already exist fleet-wide**: `mcp-bot` local account
  (`charts/base/values.yaml:147`) with RBAC `applications get,sync */*` (lines 157-158,
  re-verified 2026-11-17); tokens minted per-cluster out-of-band into Bitwarden (media
  precedent `argocd-mcp-media` **[E §4]**); `authMode: sso` does not disable apiKey tokens
  (sso includes the apikey mode; mcp-bot is live via argocd-mcp). No RBAC change needed.
- **Proxy-local hub is the correct relay host — verified 2026-11-17**: it owns the public
  edge hop (RESEARCH Agenda-2 q6, shape C), hosts its own crowdsec-only public exceptions
  (`forms`, `git`, `forgejo`, `paste` entries in `services/proxy-local/prod/values.yaml:102-131`)
  and local-hosted charts via its `charts:` block (`smtp-relay` precedent, lines 55-59);
  public DNS for hub subdomains is published by external-dns from these entries (comment
  at line 119). From proxy-local the relay reaches every cluster's existing
  `cluster.<name>.spencerslab.com` argocd-server route over mesh DNS (10.x split-horizon
  **[R]**) — zero new cluster-side exposure.
- **Fan-out target roster**: 11 root apps `dev, gpu, gpu-ai, grow, home, infra, media,
  monitoring, proxy-local, proxy-backup, proxy-remote` (named `<cat>`; `backups`/`personal`
  have no root app **[E]**). `proxy-remote`/`proxy-backup` have no readonly MCP for probes
  (manual-preflight rows **[E §5]**).
- **Tracked revisions (OQ7 grounding, grepped 2026-11-17)**: every root appset source
  resolves `targetRevision` via `$targetRevision := (eq $stage "prod") | ternary "main" $stage`
  (e.g. `services/infra/prod/templates/appset.yaml:40`) — `main` for prod stage, the cluster's
  `stage` annotation verbatim otherwise; repo-sourced children default `dig "version" "main"`
  (`charts/base/templates/appset-charts.yaml:65`). Every live `version:` entry in `charts:`
  blocks carries an external `repository:` (helm index, NOT a git ref). The revisions in use
  as BRANCHES are therefore `{main}` plus any future non-prod `stage` branch; no
  `services/<cat>/<non-prod>` dir and no origin stage branch exist. ⇒ relay filter is a
  config list (`allowed_refs`), not a hardcoded ref and not blanket any-ref.
- **Root-vs-child automated tension is now moot by design**: the relay syncs root + every
  still-Out-Of-Sync repo-sourced app per cluster, so it works whether or not children carry
  automated. C03's preflight records the observed state, it gates nothing.
- Repo standard re-checked 2026-11-17: app-template `5.0.1` (charts/qdrant), custom-values
  per-chart `bitwardenIds:` blocks (`custom-values/proxy-local/prod-values.yaml`), test
  harness = per-area bash scripts `tests/<area>/*.sh` with t1..tn checks traced to chunk ACs
  (in-process stdlib mock precedent: `tests/containers/wekan-mcp-login.sh`).
- CI moved to Forgejo since the first draft: `.forgejo/workflows/containers-build.yaml` is
  build-authoritative (prod-role main/dispatch → `:yy.mm.N` + `:latest` + `:main` to ghcr +
  instance registry; PR on dev-role → `pr-<branch>-<sha>` local registry only); GitHub
  `docker-build.yaml` is workflow_dispatch fallback. New container ⇒ `docker build =>
  no-daemon, CI-deferred` is the designed passing AC shape.

## Out of scope (ruling-backed)

- Flipping/editing `services.<cat>.selfHeal` annotations or ANY appset gate; adding
  automated policies anywhere (OQ1: kill-switch kept).
- Edits to `charts/base` (values or templates) — including ignoreDifferences additions: the
  old C01 hardening served the flip; under relay-driven non-force syncs the shipped
  entries suffice. Dropped from plan; kept only as runbook risk context.
- `cluster.proxy-local` public-A-record leak — **note-only** per OQ4 (recorded in
  DECISIONS.md; no follow-up card, no fix here).
- Human actions scripted in the runbook, never executed by agents: GitHub webhook creation,
  Bitwarden item creation, per-cluster token minting, cluster-secret edits (none needed).
- ArgoCD `/api/webhook` refresh fan-out (pointless with automated off), argocd-notifications,
  ApplicationSet webhook, poll-interval tuning, per-cluster public exposure, GitHub Actions
  direct sync (all rejected in RESEARCH Agenda 2).

## Commands (base checks verified 2026-11-12; chart/container checks land with C01/C02)

- `export PATH=$HOME/.local/bin:$PATH` (helm lives in `~/.local/bin`).
- New chart (C02): `helm dependency update charts/argocd-hook` → `helm lint charts/argocd-hook`
  → `helm template charts/argocd-hook --set domain=test.example.com --set
  bitwardenIds.argocd-hook-secret=test-uuid --set bitwardenIds.argocd-hook-tokens=test-uuid`
  ⇒ valid manifests, Service name matches the proxy entry, 0 `OVERRIDE_` leakage.
- Regression on base (untouched, must still pass): `helm dependency build charts/base &&
  helm lint charts/base && helm template charts/base` ⇒ `grep -c
  'resource.customizations.ignoreDifferences'` ≥ 4, 0 `OVERRIDE_` hits (the silent
  zero-render trap without dep-build is in FRICTION.md — always build deps first).
- Service trio (grep trio + 1:1 sentinel check):
  `grep -n 'argocd-hook' services/proxy-local/prod/values.yaml` ⇒ BOTH a `charts:` entry and
  an `ingress.subdomains.argocd-hook` entry;
  `grep -n 'argocd-hook-secret\|argocd-hook-tokens' custom-values/proxy-local/prod-values.yaml`
  ⇒ every `OVERRIDE_VIA_CUSTOM_VALUES` placeholder in the chart has exactly one UUID line.
- Gate-untouched check: `git diff --name-only` must show NO `services/*/templates/appset.yaml`,
  NO `charts/base/**` files.
- Container (C01): `python3 -m py_compile containers/argocd-hook/*.py`; relay `--check`
  self-test (config load + HMAC round-trip, no network); `bash tests/containers/argocd-hook-relay.sh`
  (agent-test authored); `docker build => no-daemon, CI-deferred` — Forgejo
  `containers-build.yaml` on the pushed branch is authoritative; capture base-image layer
  facts from GHCR tar-listings.
- No unit-test suite; "tests" = the above + `tests/<area>/*.sh` harness files per chunk.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | `containers/argocd-hook` relay: HMAC verify → `allowed_refs` config-list filter → 202-async fan-out of API syncs | M | 1 | [] | — (defines the image + config/secret interface C02 bakes) |
| C02 | `charts/argocd-hook` + proxy-local trio wiring (ApplicationSet entry, crowdsec-only subdomain, ExternalSecret secrets + custom-values 1:1) | M | 2 | [C01] | chart consumes C01's image name, ports, `/health`, `/config` + `/secrets` file contract |
| C03 | Human runbook + live preflight: GitHub webhook creation, Bitwarden + token minting, bootstrap, smoke test, verification, rollback | M | 3 | [C02] | runbook pins exact chart paths/values, service name, item names and rollout sequence shipped by C02 |

## Wave order

1. C01 → 2. C02 → 3. C03 (serial: interface → consumer → docs-parity). C03's live probe
rows are read-only and could run any time; kept in C03 so the runbook ships as one
reviewable artifact.

## Relay behavior (outcome-level)

- Ingress: GitHub repo webhook (user-created) → `https://argocd-hook.spencerslab.com/`;
  `application/json` + `X-Hub-Signature-256` HMAC, verified against one shared fleet secret
  (OQ2). Invalid → 401. Ref filter: push `ref` must be in the `allowed_refs` CONFIG LIST
  (OQ7 ruling; seeded `["refs/heads/main"]` — the evidence-grounded in-use revision set,
  widened per-cluster by a future `stage` branch entry with zero code change);
  non-matching push → 200 no-op; `refs/tags/*` never fire. `ping` → 200.
- Answer 202 immediately after verification (GitHub 10s budget), fan out asynchronously.
- Per target cluster (remote clusters first, proxy-local LAST — self-sync may restart the
  relay mid-fan-out): list applications → sync root app `<cat>` **only if it tracks the
  fired ref** (live `spec.targetRevision` match — the ruling-compliant widening: a stage-ref
  push syncs stage-tracking roots, never prod ones) → settle delay → list again → sync each
  app whose source repo matches ∧ `targetRevision` equals the fired ref ∧ is OutOfSync
  (skipping the just-synced root). `prune=false`, never force on every sync (ruled, OQ6;
  root syncOptions note in Context). HTTP 409 / "operation already running" counts as
  success; per-target timeout; one target's failure never aborts the others (partial
  fan-out logged per target).
- Config: files, never env secrets — `targets.json` (ConfigMap: top-level
  `allowed_refs` list (default `["refs/heads/main"]`) + roster `[{name, url, rootApp,
  tokenKey, repo, local?}]`; fan-out matches each live app's `spec.targetRevision` against
  the fired ref, so per-target syncs only touch apps tracking that branch) and a secrets dir
  (GitHub HMAC + per-cluster `mcp-bot` tokens). Stateless, no queue — missed deliveries
  fall back to today's manual sync (documented limitation, no silent loss: logged).
- Secrets lifecycle (OQ5 ruling, "merge first, fill later"): the chart ships
  `OVERRIDE_VIA_CUSTOM_VALUES` sentinels and `custom-values/proxy-local/prod-values.yaml`
  ships `OVERRIDE_NEEDED` UUID lines **through the merge**; `proxy-local-argocd-hook`
  crash-loops visibly until the owner fills the real Bitwarden item UUIDs in a follow-up
  commit at their convenience — ruled-in, designed behavior, not an incident.

## Human-owned list (never agent-executed)

Plan approval (batch-2 round, done 2026-11-17) · Bitwarden item creation (`argocd-hook`
HMAC, `argocd-hook-tokens` per-cluster fields) + custom-values UUID fill post-merge at the
owner's convenience (OQ5 ruling) · per-cluster `mcp-bot` token minting (admin `argocd
account generate-token`) · GitHub repo webhook creation + secret placement · first-time
bootstrap syncs (root `proxy-local` + relay app) · verification push · PR open/merge
(Deployment stage unchecked: commits stay local) · card Review→Finished.

## Risks / assumptions

- **Self-mutating hub**: syncing root `proxy-local` re-renders the hub (its own relay app
  included). Mitigated by self-last ordering + redelivery tolerance; a restart mid-fan-out
  drops only that push's tail → manual sync fallback, logged.
- **First sync after long OutOfSync periods applies real drift** (e.g. `infra-seaweedfs`,
  SSA=false — `.agents/notes/2026-11-10-seaweedfs-incident-findings.md`): identical to what
  the user's manual sync button does today; preflight table records it, runbook tells the
  human to glance first. Non-force + shipped ignoreDifferences keep the k3s-incident class
  of spurious re-applies out of scope; a future chart bump re-verifies key shapes (argo-cd
  10.11.6 = v3.5.6 only verified).
- **Hub exposure**: `argocd-hook.spencerslab.com` is a new public POST surface, crowdsec-
  fronted, no SSO (GitHub can't do OIDC — same exception class as forms/git). Blast radius
  of a leaked shared HMAC: attacker can trigger syncs of git-main state (no writes to git,
  no prune, no force) — refresh/sync of already-trusted content. Per-cluster HMAC re-sign
  was declined (OQ2: shared).
- No readonly MCP for proxy-remote/proxy-backup **[E §5]**; token mint + verification rows
  for them are manual in the runbook.
- gpu-ai/dev appset variant drift **[E §2]** — cosmetic, untouched.

## Open questions (resolved in the batch-2 round — none remain)

- **OQ5 RESOLVED — "Merge first, fill later":** the branch merges with `OVERRIDE_NEEDED`
  UUID lines; owner fills real Bitwarden item UUIDs post-merge at convenience; the relay
  app's crash-loop-until-filled is ruled-in designed behavior (visible, non-destructive).
- **OQ6 RESOLVED — prune=false confirmed:** status-quo mirror, never force, no prune; git-
  removed resources need an occasional manual prune sync by choice.
- **OQ7 RESOLVED — "Wider filter":** ref matching is the `allowed_refs` CONFIG LIST
  (O(1) change, no hardcoded main); seeded `["refs/heads/main"]` per the Context
  revision-grounding (main is the only branch revision in use; non-prod `stage` branches
  enter by config when such a cluster exists); blanket any-ref rejected (feature-branch
  pushes track nothing — would sync-fire for nothing).
- Rulings recorded in DECISIONS.md (2026-11-17 batch-2 block). No genuine new gaps; the
  runbook (C03) documents the filter-widening procedure.

## Rejected alternatives (kept from research, reaffirmed by the ruling)

Annotation flip (OQ1 "no"); N public cluster webhooks (mesh-only, NXDOMAIN measured);
GitHub Actions sync fan-out (same reachability wall + write-token sprawl); centralizing
ArgoCD; argocd-notifications (outbound-only); refresh-only webhook fan-out (does not land
pushes with automated off — the exact hole this relay fills).
