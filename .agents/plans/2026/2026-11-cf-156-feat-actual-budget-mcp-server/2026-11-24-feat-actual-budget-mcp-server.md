# PLAN: Third Actual Budget instance (wuulf) + s-stefanov/actual-mcp MCP server
feature: 2026/2026-11-cf-156-feat-actual-budget-mcp-server

## Goal
Add a third Actual Budget instance (`wuulf-budget`) on home as a pure copy of the live
`bri-budget` pattern — which comes up **without the broken `01-enable-openid` initContainer**
(R2 criterion: the step exists only in the umbrella's own instance-1 `actualbudget:` block;
the shared chart defines no initContainers, so the `chart:`-field copy avoids it by
construction; SSO enablement rides the server's auto-bootstrap path, live-verified) — and
expose an `sstefanov/actual-mcp` ToolHive MCP server on home giving the agent
import-reconciliation / split / assign access to the wuulf budget (read-only tier first =
the absence of `--enable-write`, scoped by a wuulf budget-scoped API key passed through
`ACTUAL_SESSION_TOKEN`). Plan rides the binding owner answers (DECISIONS 2026-11-24, incl.
the replan rulings 2026-11-24): server = s-stefanov/actual-mcp (agigante80 **dropped** —
password-only, no `sessionToken` slot), reconcile = IMPORT-reconciliation only, exports =
statement-vs-Actual with upstream tools, scope = WUULF ONLY, auth = 26.12+ budget-scoped
API keys (session-token path rejected).

## Out of scope
- Statement-balance "lock" (`reconciled`) — binding #2; no chunk chases it.
- MCP surface on the `budget`/`bri-budget` instances — binding #5 (wuulf only; the other
  two get entries later; deferred asks ride the final summary comment, no follow-up cards).
- Custom in-repo container — the custom-container branch is closed by binding #3.
- agigante80/actual-mcp-server — **DROPPED, not postponed** (the owner's replan ruling
  2026-11-24, R1): it is password-only with no `sessionToken` slot, so it could never
  carry the owner's chosen budget-scoped API key credential; the s-stefanov/actual-mcp
  surface replaces it wholesale (no shared-chart change in either direction).
- The 26.12.x image pin move itself — a Renovate PR leg the owner merges (never hand-bump);
  the Keycloak redirect-URI + web-origin mutation for `wuulf-budget.spencerslab.com` —
  owner ops (DECISIONS external step).
- Deployment stage (unchecked) — no deploy fixer, no PR push leg. The run works uncommitted,
  in place on `main`; the coordinator makes ZERO commits, so chunk reviews read the
  WORKING DIFF (`git status --porcelain` + `git diff`, plus each chunk's untracked files
  enumerated from the dev's hand-back list) — there is no commit range.

## Verified at planning time (2026-11-24)
- **26.12.0 is NOT published** — confirmed by the Post Research round (2026-11-24): GitHub
  releases top out at `v26.11.0` (published 2026-11-02); npm `@actual-app/api` `latest` =
  26.11.0, `nightly` = 26.12.0-nightly.20261124. Earliest credible signals the API-key
  feature is near: the npm `nightly` date stamp + the five `upcoming-release-notes/`
  API-key fragments on master. **Re-check early December 2026.** Consequence: API-key
  wiring is **gated on 26.12.x publication**. No fallback is invented (the owner rejected
  the session-token path) — until the gate clears, the credential plumbing lands inert
  and the ExternalSecret stays unready (a visible failure, not a silent one).
- **s-stefanov image pin policy (replan ruling R1):** the image name
  `sstefanov/actual-mcp` (Docker Hub) is README-verified at planning time (2026-11-24);
  the **tag comes from a live registry query at implementation time** (C02 Notes item 1)
  — never from memory or lexicographic order. Research: the Docker Hub image **lags the
  repo** (image 2026-10-20 vs repo push 2026-11-23). Cautionary precedent from this
  run's own round-1 mistake: `0.4.2` (published 2025-12-31, bundles SDK 25.12.0) sorts
  lexicographically *above* `0.35.2` (newest since 2026-11-22, bundles SDK 26.11.0) yet
  is the OLDER build. The image line stays Renovate-trackable under the existing
  plain-image custom manager (same `image:` string shape in the service values, docker
  datasource); the chosen name+tag + query time are recorded in DECISIONS.md.
- **R2 grounded by construction (2026-11-24):** `charts/actualbudget/values.yaml` defines
  **no** initContainers — the broken `01-enable-openid` step (`npm run enable-openid
  --prefix /app || true`; the pinned 26.10.0 image has no `enable-openid` script, so it
  fails `Missing script: enable-openid`) exists ONLY in the umbrella's own instance-1
  `actualbudget:` block (`services/home/prod/values.yaml:912-919`). The wuulf
  `chart:`-field copy inherits only the chart's values → no initContainers; the SSO
  `envFrom` wiring is hardcoded in the chart values (lines 22-24) and enablement rides
  the server's auto-bootstrap path (live-verified: "OpenID configuration found.
  Preparing server to use it" → "OpenID configured!"). **No per-instance route was
  needed** — the round-1 "blocking owner question" fallback therefore never fires, and
  `charts/actualbudget/values.yaml` is untouched by this plan.

## Prerequisites (owner ops / owner-owned legs — never a chunk task)
1. **Keycloak mutation** — add `https://wuulf-budget.spencerslab.com/*` to the
   `actualbudget` client's Valid Redirect URIs **and** Web Origins (realm `SpencersLab`)
   before the wuulf instance is SSO-enabled.
2. **Bitwarden items — SPLIT per the OQ1 ruling (2026-11-24, answered as the plan
   guessed):** (a) `actual-budget-mcp` — LOGIN item; `password` = a random MCP-side
   Bearer token (**mintable today**, independent of 26.12.x) → ExternalSecret →
   `BEARER_TOKEN`; (b) `actual-budget-mcp-key` — LOGIN item; `password` = the wuulf
   budget-scoped API key (**mintable only after 26.12.x publishes** — keys are minted
   in the budget UI, which needs the 26.12+ UI) → ExternalSecret →
   `ACTUAL_SESSION_TOKEN`. Until item (b) exists its ExternalSecret stays unready → the
   server pod cannot start (visible failure, not silent).
3. **Version leg (26.12.x)** — 26.12.0 is not published yet (Post Research, 2026-11-24;
   earliest signals: the npm `nightly` date stamp + the five `upcoming-release-notes/`
   API-key fragments on master — **re-check early December 2026**). When 26.12.x
   publishes, Renovate proposes the `ghcr.io/actualbudget/actual-server` pin move in the
   two pinned files — `charts/actualbudget/values.yaml` + the `actualbudget:` umbrella
   block in `services/home/prod/values.yaml`; the owner merges (never hand-bump).
   Carried consequence (DECISIONS #4a): the pin move re-renders **all three** instances
   (shared pin) while the MCP surface stays wuulf-only.
4. **API-key minting** — after leg 3, mint a revocable budget-scoped key for the wuulf
   budget into `actual-budget-mcp-key`'s `password` field. Scope per OQ2 (answered as
   the plan guessed): the **full documented-workflow scope** — one grant to the wuulf
   budget file = reads + every in-file write; the key has **NO read/write axis**
   (Post Research Q2), so no scope change is needed when the write tier is flipped
   later.

## Commands
`export PATH=$HOME/.local/bin:$PATH` first — without it, helm-guarded checks silently
mass-skip. This repo has no unit-test suite: "tests" are these render/grep validations.
Render checks run on a /tmp copy of the chart with `helm dependency update` (no vendored
tgz in git) so the in-place tree stays clean (EXPLORE precedent).

Repo-wide set (dev runs while implementing; review re-runs as the first step of every review):
- `helm lint charts/actualbudget`
- /tmp copy of `charts/actualbudget` + `helm dependency update` →
  `helm template home-wuulf-budget <copy> --set app-template.global.nameOverride=wuulf-budget --set bitwardenIds.actualbudget-sso-secret=test-uuid`
  → Service+Deployment `home-wuulf-budget`, PVC `wuulf-budget-data`, no `OVERRIDE_*` in output
- R2 validation line: `grep -c "enable-openid" charts/actualbudget/values.yaml` → 0 (the
  chart defines no initContainers; the broken `01-enable-openid` step exists only in the
  umbrella's instance-1 `actualbudget:` block) + the wuulf render above shows **no
  `initContainers`** on the rendered Deployment while `envFrom: secretRef` →
  `actualbudget-sso-secret` is present (SSO wiring intact; enablement rides the
  auto-bootstrap path)
- Grep trio (C01): `grep -n "wuulf-budget" services/home/prod/values.yaml services/proxy-local/prod/values.yaml services/proxy-remote/prod/values.yaml custom-values/home/prod-values.yaml`
  — the `charts:` entry, the `ingress.subdomains` entry, the proxy-local entry (with
  `client_id=actualbudget` and a `wuulf-budget` redirect URI), proxy-remote `enabled: true`,
  and the custom-values UUID mirror all present
- /tmp copy of `charts/hivetools` + `helm dependency update` → extract the home `hivetools:`
  block to a temp file (python3/PyYAML) →
  `helm template hivetools <copy> -f <block> --set domain=test.example.com --set clusterName=testcluster --set subDomain=home-lab --set bitwardenIds.actual-budget-mcp=test-uuid-1 --set bitwardenIds.actual-budget-mcp-key=test-uuid-2`
  (the mcp-servers.md Validation recipe) → `MCPServer mcp-actual-budget` (pinned image,
  streamable-http, mcpPort, args `--sse` + `--enable-bearer`, **no `--enable-write`**),
  **two** `ExternalSecret`s (`actual-budget-mcp`, `actual-budget-mcp-key`) each carrying its
  test UUID, ingress `host: mcp.home-lab…` with `path: /actual-budget` →
  `mcp-mcp-actual-budget-proxy`; no `OVERRIDE_*` sentinel in the new server's rendered
  resources
- 1:1 sentinel↔custom-values: every `OVERRIDE_VIA_CUSTOM_VALUES` in the home service values
  (including **both** new `actual-budget-mcp` and `actual-budget-mcp-key` sentinels) has a
  real-UUID (not a sentinel) counterpart in `custom-values/home/prod-values.yaml`
- `bash tests/services/actual-budget-wuulf-mcp.sh` — the hermetic structure suite (the Test
  Writing stage writes it in one session before any dev; dev runs it while implementing,
  review re-runs it)
- Container-build leg: **not applicable** — there is no `docker build` in this plan (the
  upstream GHCR image is used; the custom-container branch is closed), so the
  `docker build => no-daemon, CI-deferred` gate shape never fires.

## Skills (named per stage — a fresh session loads these)
- C01: `helm-chart-creation` (the service trio + custom-values plumbing;
  `references/values-and-appset.md` — the `chart:` multi-instance pattern), `helm-bjw-s-chart`
  (app-template 5.0.1), `gitops-workflows` (ArgoCD applies everything; never `kubectl apply`)
- C02: `helm-chart-creation` (`references/mcp-servers.md` — the primary recipe;
  `references/storage-and-secrets.md` — ESO/Bitwarden shapes), `helm-bjw-s-chart`,
  `gitops-workflows`
- Test Writing stage: `helm-chart-creation` (Validation section) + the
  `tests/services/home-dead-image-refs.sh` hermetic-script style
- Post Research round: verifies the 26.12.x publication + the budget-scoped API-key surface
  (the plan's gate; no session-token fallback exists)
- Chunk reviews + Final Review: the `## Commands` set above + each chunk's acceptance
  criteria, reading the working diff (no commit range in this posture)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | wuulf-budget — the third Actual Budget instance (pure `bri-budget` copy; R2: comes up without the broken initContainer) | S | 1 | [] | — |
| C02 | s-stefanov/actual-mcp MCP server on home (wuulf-only, read-only tier = absence of `--enable-write`, API-key credential) | M | 2 | [C01] | data: `ACTUAL_SERVER_URL` resolves against C01's in-cluster Service `home-wuulf-budget`; sequential waves also keep the working-diff review clean under the uncommitted posture |

## Wave order
1. C01
2. C02

## Open questions (resolved at the plan-approval pause 2026-11-24; rework fold 2026-11-24)
- **OQ1 (Bitwarden item name + shape) — resolved as the plan guessed:** two items,
  `actual-budget-mcp` (LOGIN `password` = a random MCP-side Bearer token, mintable
  today) + `actual-budget-mcp-key` (LOGIN `password` = the wuulf budget-scoped API key,
  mintable only after 26.12.x publishes), one ExternalSecret per item, server entry
  `hivetools.mcp.actual-budget` (the `wekan-mcp` naming precedent). Recorded in plan
  Prerequisites 2.
- **OQ2 (API-key permission scope at minting) — resolved as the plan guessed, with the
  premise changed by the server swap:** the s-stefanov key has **NO read/write axis**
  (a granted budget file = full read+write *within that budget only*, Post Research Q2;
  the only opt-in permission, `bank-sync-global`, is not needed — wuulf has no shared
  bank connections) → mint with the **full documented-workflow scope**. The first
  tier's boundary is the absence of `--enable-write`; the credential caps blast radius
  if the flag flips (the defense-in-depth pairing recorded in C02 AC5; the
  write-tier flip is a values change with no re-mint). The round-1 `MCP_READ_ONLY`
  flag wording was an agigante80 artifact, stripped by R1.
- **No new blocking open questions from the rework.** R2 is resolved by construction
  (the shared chart defines no initContainers — verified 2026-11-24), so the round-1
  "no per-instance route" fallback (a blocking owner question with candidate shapes +
  blast radius) never fires. The remaining C02 unknowns (tag, default port, read-only
  flag, image entrypoint/user, Bearer wiring) are dev-time verification items, each
  with its check to run (C02 Notes) — not blockers.

## Risks / assumptions
- **SDK/server version drift** (RESEARCH C1, updated by R1): the upstream MCP image
  bundles its own `@actual-app/api` — a server upgrade (leg 3) can outpace the image's
  SDK, and the ticket's research does not enumerate which SDK version a given image tag
  bundles → dev records the bundled SDK version from the chosen tag's lockfile/
  package.json (a C02 dev-time item). Renovate tracks both pins (the image line and
  the server line); the post-sync canary = `--test-resources` (connection errors
  reported immediately at startup, README) + a `tools/list` through
  `https://mcp.home-lab.spencerslab.com/actual-budget/mcp` — the same standing hazard
  as every hivetools image (the kubernetes-mcp TOML incident precedent).
- **securityContext is a dev-time check, not a conclusion (updated by R1):** the
  round-1 agigante80 finding (root-by-design image + `fsGroup: 65532` workaround) is
  **NOT inherited** by `sstefanov/actual-mcp`. Check to run: the image's
  entrypoint/user (the repo `Dockerfile` + the registry manifest's `config.User` for
  the chosen tag); the podTemplateSpec securityContext is derived from the real user
  and the chosen shape is recorded in DECISIONS.md — never invented.
- **PVC size 5Gi** for the SDK budget cache — assumption (no size guidance anywhere in
  s-stefanov's docs — exhaustive grep; parity with the budget instances' 5Gi data
  PVCs): wuulf-only, one budget, cache = the downloaded `db.sqlite` + metadata.
  Undersized → budget sync fails at runtime (visible); oversized → costs nothing
  (local-path).
- **One shared connection, serialized budget operations** (README "Connection
  lifecycle"): the server keeps one Actual connection for its lifetime; fine for
  wuulf-only single-agent use (binding #5); `SIGINT`/`SIGTERM` drain in-flight work.
- **The credential is the gate, not the flag** (Post Research Q2) + **inert until the
  key lands** (the replan ruling's reframed cause, DECISIONS "replan rulings" block):
  a budget-file grant is full read+write *within that budget only* — the key has no
  read/write axis. The first tier's boundary is the absence of `--enable-write`; if
  the flag flips, the credential caps the blast radius (C02 AC5). The 26.12.x gate is
  the only thing between this plan and a working server: the `ACTUAL_SESSION_TOKEN`
  slot exists but has nothing revocable to hold until 26.12.x publishes + the pin
  merge + the key mint; the ExternalSecret stays unready → the pod cannot start — a
  designed visible failure, no session-token stopgap (owner rejected).
- **No follow-up cards** (stage unchecked): the deferred asks (MCP entries for
  default/bri; the write-tier flip) ride the final summary comment.
