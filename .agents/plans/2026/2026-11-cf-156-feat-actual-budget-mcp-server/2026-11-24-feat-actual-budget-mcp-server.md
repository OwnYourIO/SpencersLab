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
API keys (session-token path rejected). **C03 (the 2026-11-26 owner rework, binding):**
wuulf is no longer exposed on proxy-remote; the two credential items are minted and
renamed to the owner's spelling (`actualbudget-mcp-key` / `actualbudget-mcp-bearer`)
with real UUIDs; the two ExternalSecret templates + the data PVC move from the home
umbrella into `charts/actualbudget/templates/`, gated per instance (the chart is
consumed by the `bri-budget` and `wuulf-budget` Applications — an unconditional move
would render identically-named objects into both releases: the documented sync-fight
hazard). The inert-until-the-key-lands premise is **over**: with C03 the credential
plumbing goes live.

## Out of scope
- Statement-balance "lock" (`reconciled`) — binding #2; no chunk chases it.
- MCP surface on the `budget`/`bri-budget` instances — binding #5 (wuulf only; the other
  two get entries later; deferred asks ride the final summary comment, no follow-up cards).
  C03 (2026-11-26) makes a future `bri-budget` MCP entry **collision-safe** — the moved
  chart templates are release-prefixed and per-instance gated — but C03 itself renders
  nothing for `bri-budget`.
- The `wuulf-budget` **proxy-remote** enable — removed by the 2026-11-26 owner
  instruction ("so I don't want anything on proxy-remote yet"): wuulf stays reachable
  locally (the proxy-local entry stands), the remote exposure is a later owner act.
  C01's AC3 trio is revised accordingly (recorded as a changed requirement — Open
  questions, C03 section).
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

### Verified at C03 replan time (2026-11-26)

- **The C01/C02 surface is branch-only — nothing of it is live** (readonly-home-kubernetes,
  2026-11-26): targeted gets for `actual-budget-mcp-data` PVC, `wuulf-budget-data` PVC,
  ExternalSecrets `actual-budget-mcp` / `actual-budget-mcp-key`, MCPServer
  `mcp-actual-budget` — all five answer **not found** (the branch is unmerged; ArgoCD
  tracks `main`). Consequence for C03's template move: there is **no live object the
  move prunes** — the values-and-appset.md "moving templates" ownership-flip hazard
  (prune-before-adopt credential gaps, orphaned target Secrets) does not fire; every
  C01/C02/C03 object is a pure creation at first post-merge sync.
- **`home-actualbudget` cannot render `charts/actualbudget` templates by construction**:
  `services/home/prod/Chart.yaml` carries seven `app-template` dependencies (one aliased
  `actualbudget`) and **no** `actualbudget` chart dependency (verified 2026-11-26) — the
  instance-1 block is an app-template subchart, not a chart consumer.
- **The appset values merge** (`charts/base/templates/appset-charts.yaml:101-123`): each
  app's chart values = the per-app top-level block (`index $.Values $appName`) merged with
  the service-wide custom-values file's top-level keys (documented precedence: per-app
  custom > service-wide custom > service-level globals > base values). The chart's own
  `bitwardenIds` map (lowest tier) is overridden by `custom-values/home/prod-values.yaml`'s
  top-level `bitwardenIds` — the same injection that resolves `actualbudget-sso-secret`
  today; the per-app belt-and-braces blocks (`wuulf-budget: bitwardenIds: …`) land as a
  nested key, never as the chart's top-level map, so they do not feed chart templates.
- **Gate + naming precedents (read 2026-11-26):** the `shared-storage` conditional-template
  pattern (chart declares the default map; the template uses nil-safe `index` access —
  `storage-and-secrets.md` §2, live example
  `services/gpu/prod/templates/pvc-knowledge-default.yaml`); the `enabled` nil-safe gate
  vocabulary (`charts/hivetools/templates/generic-mcpserver.yaml:2`, referenced by the
  appset opt-out comment at `appset-charts.yaml:17-18`); release-prefixed object names in
  a `chart:`-multi-instance chart (`charts/zigbee2mqtt` — deployed three times via
  `chart:` as `zigbee2mqtt` / `zigbee2mqtt-coord` / `zigbee2mqtt-remote`;
  `templates/secret-zigbee2mqtt.yaml` names `{{ .Release.Name }}` +
  `{{ .Release.Name }}-secret`, `templates/pvc-zigbee2mqtt-default.yaml` names
  `{{ .Release.Name }}`); `deletionPolicy: Delete` on every MCP-credential ExternalSecret in
  the repo (`secret-argocd-mcp.yaml`, `secret-grafana-mcp-token.yaml`,
  `secret-grafana-mcp-admin-token.yaml`, `secret-postgres-mcp.yaml`).
- **Chart consumers (grep 2026-11-26):** `chart: actualbudget` occurs exactly twice in
  `services/` — `bri-budget` (home values:103) and `wuulf-budget` (home values:107). No
  other category consumes the chart.

## Prerequisites (owner ops / owner-owned legs — never a chunk task)
1. **Keycloak mutation** — add `https://wuulf-budget.spencerslab.com/*` to the
   `actualbudget` client's Valid Redirect URIs **and** Web Origins (realm `SpencersLab`)
   before the wuulf instance is SSO-enabled.
2. **Bitwarden items — SATISFIED (2026-11-26 owner mint; the 2026-11-24 OQ1 split
   stands, the names are the owner's, not the run's guesses):** (a) `actualbudget-mcp-key`
   — LOGIN item; `password` = the wuulf budget-scoped API key → ExternalSecret →
   `ACTUAL_SESSION_TOKEN`; (b) `actualbudget-mcp-bearer` — LOGIN item; `password` = a
   random MCP-side Bearer token → ExternalSecret → `BEARER_TOKEN`. The owner supplied
   both names and UUIDs (DECISIONS 2026-11-26; the item-name → role mapping is
   name-derived — Open questions OQ3); C03 lands them in
   `custom-values/home/prod-values.yaml` (instruction 4). **The inert-until-the-key-lands
   premise is over** — see Risks.
3. **Version leg (26.12.x)** — 26.12.0 is not published yet (Post Research, 2026-11-24;
   earliest signals: the npm `nightly` date stamp + the five `upcoming-release-notes/`
   API-key fragments on master — **re-check early December 2026**). When 26.12.x
   publishes, Renovate proposes the `ghcr.io/actualbudget/actual-server` pin move in the
   two pinned files — `charts/actualbudget/values.yaml` + the `actualbudget:` umbrella
   block in `services/home/prod/values.yaml`; the owner merges (never hand-bump).
   Carried consequence (DECISIONS #4a): the pin move re-renders **all three** instances
   (shared pin) while the MCP surface stays wuulf-only.
4. **API-key minting — SATISFIED (2026-11-26, per the owner's rework instruction: the
   key is minted into `actualbudget-mcp-key`'s `password` field, UUID
   `29e97ab5-db7f-4214-affd-b50e0032788d`).** Scope per OQ2 (answered as the plan
   guessed) stands: the **full documented-workflow scope** — one grant to the wuulf
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
- Grep trio (C01, **revised by the 2026-11-26 owner instruction — changed requirement,
  recorded in Open questions**): `grep -n "wuulf-budget" services/home/prod/values.yaml services/proxy-local/prod/values.yaml custom-values/home/prod-values.yaml`
  — the `charts:` entry, the `ingress.subdomains` entry, the proxy-local entry (with
  `client_id=actualbudget` and a `wuulf-budget` redirect URI), and the custom-values
  UUID mirrors all present; **plus the changed leg**: `grep -c "wuulf-budget" services/proxy-remote/prod/values.yaml`
  → 0 (the C01 proxy-remote `enabled: true` entry is removed by C03; wuulf is not
  exposed remotely)
- /tmp copy of `charts/hivetools` + `helm dependency update` → extract the home `hivetools:`
  block to a temp file (python3/PyYAML) →
  `helm template hivetools <copy> -f <block> --set domain=test.example.com --set clusterName=testcluster --set subDomain=home-lab`
  (the mcp-servers.md Validation recipe) → `MCPServer mcp-actual-budget` (pinned image,
  streamable-http, mcpPort, args `--sse` + `--enable-bearer`, **no `--enable-write`**),
  `secrets:` entries `name: home-wuulf-budget-mcp-key` (key `ACTUAL_SESSION_TOKEN`) and
  `name: home-wuulf-budget-mcp-bearer` (key `BEARER_TOKEN`) — the **release-prefixed**
  names matching the chart's `{{ .Release.Name }}-mcp-*` render (C03) — the data volume
  `claimName: home-wuulf-budget-mcp-data`, ingress `host: mcp.home-lab…` with
  `path: /actual-budget` → `mcp-mcp-actual-budget-proxy`; no `OVERRIDE_*` sentinel in the
  server's rendered resources. (After C03 the two ExternalSecrets no longer render in
  this render — they live in `charts/actualbudget/templates/`; their UUID resolution is
  proven by the wuulf chart render below, per the C02 final review's finding-R1
  substitute-proof pattern.)
- **C03 three-way render proof** (chart /tmp copy + `helm dependency update`):
  (i) **wuulf, gate open, real injection** — extract the top-level `bitwardenIds` map from
  `custom-values/home/prod-values.yaml` to a temp file (python3/PyYAML) →
  `helm template home-wuulf-budget <copy> -f <bitwardenIds file> --set app-template.global.nameOverride=wuulf-budget --set mcp.enabled=true --set bitwardenIds.actualbudget-sso-secret=test-uuid`
  → ExternalSecret `home-wuulf-budget-mcp-key` with `remoteRef.key` =
  `29e97ab5-db7f-4214-affd-b50e0032788d` (the **real UUID resolved through the post-move
  custom-values injection path**, not a sentinel) + target data key `ACTUAL_SESSION_TOKEN`
  + `deletionPolicy: Delete`; ExternalSecret `home-wuulf-budget-mcp-bearer` with
  `remoteRef.key` = `075f18ca-a137-415a-9296-b50e0033589c` + `BEARER_TOKEN` +
  `deletionPolicy: Delete`; PVC `home-wuulf-budget-mcp-data` (RWO 5Gi); the C01 legs
  intact (Service+Deployment `home-wuulf-budget`, 0 `initContainers`, `envFrom` SSO);
  **0 `OVERRIDE_*`** in the render
  (ii) **bri, gate closed (the chart default)** —
  `helm template home-bri-budget <copy> --set app-template.global.nameOverride=bri-budget --set bitwardenIds.actualbudget-sso-secret=test-uuid`
  (no `mcp` key set) → Service/Deployment/PVC/ServiceAccount `home-bri-budget` with the
  standing legs intact (0 `initContainers`, `envFrom` SSO, 0 `OVERRIDE_*`) and **zero**
  objects named `*mcp-key` / `*mcp-bearer` / `*mcp-data` (grep the render: 0 hits) —
  **`bri-budget` renders NONE of the MCP resources**; the gate-closed confirmation is the
  full-render absence (or the `--show-only templates/secret-actualbudget-mcp-key.yaml`
  "could not find template" error — the empty-render gate proof, the helm v3.16 gotcha
  in the skill)
  (iii) **home-actualbudget (the umbrella)** — home-umbrella /tmp copy + deps,
  `helm template home <copy> --set bitwardenIds.actualbudget-sso-secret=test-uuid …` →
  **zero** `*mcp-key` / `*mcp-bearer` / `*mcp-data` objects (grep 0; `home-actualbudget`
  is an app-template subchart, not a chart consumer — `services/home/prod/Chart.yaml`
  carries no `actualbudget` dependency, verified 2026-11-26); the `home-actualbudget`
  Deployment **still carries** the broken `01-enable-openid` initContainer (instance 1
  untouched); `home-bri-budget`'s render byte-unchanged (C01/C02/Final-review parity)
  (iv) **collision-safety proof (the gate enabled on two instances)** —
  `helm template home-bri-budget <copy> --set mcp.enabled=true --set app-template.global.nameOverride=bri-budget --set bitwardenIds.actualbudget-mcp-key=test-uuid-1 --set bitwardenIds.actualbudget-mcp-bearer=test-uuid-2 --set bitwardenIds.actualbudget-sso-secret=test-uuid`
  → the MCP objects render as `home-bri-budget-mcp-key` / `home-bri-budget-mcp-bearer` /
  `home-bri-budget-mcp-data` — **no object name shared** with the wuulf release's
  `home-wuulf-budget-mcp-*` (release-prefixed names: a second instance enabling the gate
  cannot sync-fight the first)
- 1:1 sentinel↔custom-values (C03 shape): every `OVERRIDE_VIA_CUSTOM_VALUES` in the home
  service values **and** in `charts/actualbudget/values.yaml` (the two MCP sentinels now
  live in the chart: `actualbudget-mcp-key` / `actualbudget-mcp-bearer`; the home
  top-level map returns to the 8 pre-existing) has a real-UUID (not a sentinel)
  counterpart in `custom-values/home/prod-values.yaml`'s top-level `bitwardenIds`.
  **Expected GREEN after C03** — the owner's two UUIDs are landed (the deliberate red
  state of the 2026-11-24 ruling ends with C03)
- `bash tests/services/actual-budget-wuulf-mcp.sh` — the hermetic structure suite (the Test
  Writing stage writes it in one session before any dev; dev runs it while implementing,
  review re-runs it). **C03: the suite is re-pinned by a FRESH Test Writing session before
  C03 dev** (s2's proxy-remote leg → asserts ABSENCE; s5 → the new chart template paths,
  the owner's item names, the release-prefixed hivetools `secrets[].name`/claimName, the
  gate keys; s6 → the chart sentinel source, both files' 1:1, the real UUIDs going
  green) — the designed 29/2 shape is **RETIRED**; the new expected outcome is the
  re-pinned suite passing in full (**0 failures**): the two s6 reds were red for the
  2026-11-24 ruling's reason (the UUID mirrors absent), and the mirrors now land with
  the owner's real UUIDs. **A live MCP pod may now actually start and connect** (the
  ExternalSecrets resolve the real UUIDs → the target Secrets exist → the pod starts,
  connecting to wuulf through the budget-scoped key in the `ACTUAL_SESSION_TOKEN` slot);
  the read-only boundary is still the **absence of `--enable-write`**
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
- C03: `helm-chart-creation` (`references/values-and-appset.md` — the "Moving templates
  between a chart and a service umbrella" section + the `chart:` multi-instance pattern +
  the appset values-merge; `references/mcp-servers.md` — the ExternalSecret shape + the
  `deletionPolicy: Delete` technique; `references/storage-and-secrets.md` — the
  `shared-storage` conditional-template pattern), `helm-bjw-s-chart`, `gitops-workflows`
  (ArgoCD applies everything; the ownership-flip notes)
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
| C03 | Owner rework (2026-11-26): proxy-remote removal, item rename to the owner's names + real UUIDs, the two ExternalSecret templates + the data PVC moved into `charts/actualbudget/templates/` behind a per-instance gate (wuulf renders, `bri-budget` + `home-actualbudget` render NONE), release-prefixed collision-safe names | M | 3 | [C01, C02] | data + interface: the templates being moved are C02's output; the gate key lands in C01's `wuulf-budget:` block; C03's custom-values task is the 2026-11-24 ruling's close-out leg 1 that unblocks C02's `dev_done_blocked` state |

## Wave order
1. C01
2. C02
3. C03

## Open questions (resolved at the plan-approval pause 2026-11-24; rework fold 2026-11-24; C03 replan 2026-11-26)
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

**Open questions — C03 replan (2026-11-26).** The owner's four instructions are binding
requirements, not re-litigated. The open items:

- **C01's AC3 is a CHANGED requirement (recorded).** Instruction 1 removes the
  `wuulf-budget` proxy-remote leg from C01's grep trio (C01 is already `done`, so this
  is a post-hoc revision of a delivered chunk's criterion, recorded here rather than
  re-opening the chunk). The suite's s2 proxy-remote leg must be re-pinned to an
  **absence** assertion by the Test Writing session, and the plan's `## Commands` trio
  is updated accordingly (see above).
- **OQ3 (item-name → role mapping) — resolved by best guess, impact named.** The owner
  supplied `actualbudget-mcp-key: 29e97ab5-…` and `actualbudget-mcp-bearer: 075f18ca-…`
  without restating which role each item holds. The plan wires them by **name
  semantics**: `actualbudget-mcp-key` = the budget-scoped API key (→
  `ACTUAL_SESSION_TOKEN` — the "key" naming is this plan's own: binding #4 /
  Prerequisite 4 / C02 all call it "the key"; the old `actual-budget-mcp-key` item is
  its direct successor, dash-normalized) and `actualbudget-mcp-bearer` = the MCP-side
  Bearer token (→ `BEARER_TOKEN`; the old `actual-budget-mcp` item, now explicitly
  named). If the owner minted the items with the roles swapped, the fix is a two-line
  `secrets:`/`remoteRef` swap in the values + templates — **no re-mint, no item change** —
  and the failure mode is visible, not silent (the pod 401s at the MCP-side or the
  Actual-side auth on startup; `--test-resources` surfaces it immediately).
- **OQ4 (the shared-credential limitation of the two-instance gate — design note, not
  blocking).** The chart reads one top-level `bitwardenIds` map fed by the service-wide
  custom-values injection, so if a second instance ever enables the gate, both instances
  resolve the **same** UUID pair — a `bri-budget` instance would carry wuulf's
  credentials (functionally wrong, *not* a sync-fight: the release-prefixed names keep
  the objects distinct). The future `bri-budget` MCP ticket (the deferred "MCP entries
  for default/bri" ask) needs its own dedicated item(s) plus a per-app UUID injection
  path (the per-app `bitwardenIds` belt-and-braces blocks do not feed the chart's
  top-level map as the appset merge stands). C03 is the prerequisite, not the solution,
  for that follow-up: it makes it collision-safe.

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
- **Sync-fight hazard the C03 gate exists for (the instruction-3 hazard).**
  `charts/actualbudget` is consumed by **more than one deployment** — `bri-budget` +
  `wuulf-budget` via `chart:` entries (verified: the only two `chart: actualbudget`
  consumers in `services/`, 2026-11-26); `home-actualbudget` comes from the umbrella
  `actualbudget:` alias block, which does **not** consume the chart (verified by
  `Chart.yaml` — no `actualbudget` dependency). Templates moved in **unconditionally**
  would render a second copy of the same-named `ExternalSecret` (and PVC) objects into
  the **bri** release: two Applications owning identically-named objects is this repo's
  documented sync-fight hazard, and a `bri`-scoped ExternalSecret pointing at wuulf's
  MCP credentials is simply wrong. C03's per-instance opt-in gate (chart default
  `mcp.enabled: false`; the wuulf block sets `true`; the templates `if` on
  `index .Values "mcp" "enabled"` — the `shared-storage` conditional-template pattern
  with the hivetools/appset `enabled` vocabulary, precedents in the Verified section)
  is the answer, proven by the three-way render AC (wuulf renders the MCP resources;
  **bri-budget renders NONE**; **home-actualbudget renders NONE**) + the collision
  proof (the gate on bri renders `home-bri-budget-mcp-*` — distinct names).
- **Template-move ownership-flip hazard — assessed benign for this move (verified
  2026-11-26).** `values-and-appset.md` documents the cross-Application prune/adopt
  ordering hazard for moves of this kind (a `deletionPolicy: Delete` credential gap,
  orphaned target Secrets). It does not fire here: **none of the C01/C02 objects
  exist live** (all five targeted gets = not found — the branch is unmerged, the
  delivery is branch-only), so the move prunes nothing; the old-name target Secrets
  never materialized in the first place (the sentinel inert shape — the C02 review's
  "visible NotReady → the target Secret is not created" finding), and every object
  (new release-prefixed names) is a pure creation at first post-merge sync. One
  residual, self-healing window: at first sync the mcp pod can start (the Secrets
  resolve the real UUIDs) before `home-wuulf-budget-mcp-data` exists → the pod is
  Pending until the `wuulf-budget` Application syncs the PVC; the next ArgoCD loop
  recovers it. No action needed.
- **The inert premise is over (2026-11-26 owner rework) — a changed requirement,
  recorded.** The two items are minted with real UUIDs (Prerequisites 2 and 4
  satisfied), so the 1:1 sentinel check goes **GREEN** with C03, the suite's designed
  29/2 shape is **no longer the expected outcome** (the re-pinned suite passes in
  full, 0 failures), and a live MCP pod **may now actually start and connect** the
  moment C03 lands (the ExternalSecrets resolve the real UUIDs → the target Secrets
  exist → the pod starts, connecting to wuulf through the budget-scoped key in the
  `ACTUAL_SESSION_TOKEN` slot). The credential-is-the-gate mechanism stands (Post
  Research Q2: a budget-file grant is full read+write *within that budget only*; the
  key has no read/write axis); the first tier's boundary is unchanged — the
  **absence of `--enable-write`** (if the flag flips, the credential caps the blast
  radius — C02 AC5 pairing). The remaining owner legs are Prerequisite 3 (the 26.12.x
  pin move + the attached `@actual-app/api` **exactly-26.10.0** re-check — `v1.15.1`
  bundles the SDK as a pin, the image does not self-heal) and Prerequisite 1 (the
  Keycloak redirect URIs + web origins for the wuulf host).
- **No follow-up cards** (stage unchecked): the deferred asks (MCP entries for
  default/bri; the write-tier flip) ride the final summary comment.
