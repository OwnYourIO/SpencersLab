# RESEARCH — cf-156 feat-actual-budget-mcp-server (Pre Research)

Scope: the MCP/budget-reconciliation half of the ticket (the wuulf instance
change list is fully grounded in `EXPLORE.md` §2 and needs no research).
Method: STORM, 5 perspectives, 26 recorded sources. Numbered citation trail:
`/tmp/opencode/storm/storm-runs/actual-budget-mcp-server-landscape-and-actual-budget-api/sources.md`
(intermediates `perspectives.md`, `contradictions.md`, `outline.md`, `raw/`
alongside). All `[n]` keys resolve there. Repo facts below that are cited as
[12] come from `EXPLORE.md` and were not re-derived.

## Reliability notes (peer review, 2026-11-23)

- "Official programmatic surface is the Node SDK only; no supported HTTP data
  API" — 9/10 (direct quote from official docs [1], architecture of every
  surveyed wrapper [3][13][15]).
- "agigante80 is the only mainstream server with a multi-server budget
  registry" — 9/10 (first-hand from its docs [11]; absence checked across all 7
  surveyed repos).
- "Budget-scoped API keys first ship in 26.12.0, not the lab's 26.10.0" —
  8/10 (release date [4] + merge dates [5] + npm dist-tags [2]; an inference,
  not a release-note citation — verify when 26.12.0 lands).
- "Statement-balance 'lock' (`reconciled`) is not writable in the documented
  surface" — 7/10 (negative claim: field absent from the documented Transaction
  table [6]; UI-only flow [7]; the one third-party impl is archived [23];
  undocumented paths unverified — blind spot B2).
- "s-stefanov pins @actual-app/api 26.10.0 == the lab's server image" — 10/10
  (package.json [14] vs EXPLORE image tag [12]).
- Weakest claim: "password login is disabled on 26.10.0 under
  ACTUAL_OPENID_ENFORCE=true" — sourced from an MCP author's README [13], not
  Actual's docs; the live server config is unverified (B3). Verify against the
  live instance before the plan fixes the auth model.
- Over-weighted perspective: none material; the deployer perspective is
  repo-grounded and kept to fit analysis.
- Angle that would change conclusions: an Actual-maintainer view of the
  HTTP-API/API-key roadmap (publicly nothing found; likely Discord-only). If
  26.12+ documents a `reconciled` setter or a real data API, the
  custom-container argument strengthens.
- Known source drift: s-stefanov's Docker Hub image lags the repo (image
  2026-10-20 vs repo push 2026-11-23 [18]); agigante80's Hub image is current
  (2026-11-23 [17]). jhonderson's image is tagged 26.10.0 [3].

## TL;DR

1. Six real Actual-Budget MCP servers exist; only **agigante80** (82★,
   127k pulls, pushed today) can point one deployment at **multiple Actual
   server instances** and ships the full write surface the ticket needs —
   in-place splits that preserve import-matching, paired transfers,
   import-with-dedupe, budgets, rules, schedules, read-only tier, Bearer auth.
2. Actual's **only** official programmatic surface is the Node SDK
   (`@actual-app/api`, calendar-versioned; the lab's 26.10.0 matches the
   s-stefanov pin exactly); there is **no supported HTTP data API** — every MCP
   server is a wrapper over the SDK, which downloads the budget file and runs
   the engine locally.
3. The owner's workflow is **mostly** API-reachable: import-reconciliation
   (dedupe/merge/cleared), splits, transfers, category assignment, rules,
   ActualQL. The one hard gap: **"lock to statement balance" (the `reconciled`
   flag) is a UI-only feature** — the one server that shipped it is archived;
   and no "grouped-payments export" exists in any source (owner question).
4. The lab's 26.10.0 + OIDC-enforced instances have **no budget-scoped API
   keys** (they land in 26.12.0, merged after 26.11.0 shipped); auth today is
   a **session token** (expiry caveat) — or upgrade all three instances.
5. Recommendation: one `agigante80/actual-mcp-server` ToolHive MCPServer on
   **home** (in-cluster URLs, no new public surface), BUDGET_N registry across
   all three instances, ExternalSecret Bearer, read-only tier first.

## Where these findings land against EXPLORE.md

- **EXPLORE §6.3 (which MCP server, which instances, auth model)** — answered
  here: agigante80 is the only mainstream option spanning multiple instances
  [11][15]; the auth model is session-token-on-26.10.0 or API-key-on-26.12+
  (§2 below), because the lab's instances run `ACTUAL_OPENID_ENFORCE: true`
  (password login disabled per [13]; Keycloak named as an OIDC case by
  jhonderson [3]).
- **EXPLORE §6.4 (home vs gpu for the MCP host)** — evidence now favours
  **home**: all three budget instances are on home, reachable in-cluster
  (`http://home-<name>.default.svc:5006`), no new public exposure, and the
  `mcp.home-lab` ingress/cert already exists [12]. Still a plan decision.
- **EXPLORE §6.5 (do the export/reconcile/split/assign verbs map to
  Actual's API?)** — answered with one gap: split/assign/import-reconcile are
  documented and reachable (§2); "reconcile" in the bank-lock sense is NOT in
  the documented surface (§2, C2); the "exports" the owner means are not
  defined anywhere (B1 — owner question).
- **EXPLORE §1 (two existing instances, SSO shape)** — confirmed the auth
  consequence: with `ACTUAL_USER_CREATION_MODE: login` + OIDC enforce, the MCP
  container needs a session token or a post-26.12 API key per budget, not a
  server password [1][3][13]. The repo's SSO ExternalSecret
  (`actualbudget-sso-secret`) feeds the *server's* OIDC client, not a usable
  login credential for the MCP container [12] — a **new** credential (token or
  API key) needs a new Bitwarden item + ExternalSecret per repo convention.
- **EXPLORE §3 (hivetools mechanics, wekan-mcp precedent)** — unchanged; the
  upstream images can ride the same `mcp.<name>:` entry shape (env +
  ExternalSecret secret + `mcp`-named container), with a data volume added for
  the SDK budget cache [11][15][12]. B6: upstream images' non-root/65532 fit
  is unverified — check in dev.

## Key findings

### 1. The MCP landscape (real options only)

| Server | Activity | Transport | Write model | Auth to Actual | Multi-server | Container image |
|---|---|---|---|---|---|---|
| **s-stefanov/actual-mcp** [13][14][18][19][21] | 294★, pushed 2026-11-23; e2e gate vs real server | stdio + streamable-http (`--sse`) | opt-in `--enable-write` | password or **session token** (OIDC-enforce aware) [13] | no (1 budget) | Docker Hub (59k pulls; image 2026-10-20 — lags repo [18]); npm; official MCP registry |
| **agigante80/actual-mcp-server** [15][16][17][20] | 82★, pushed 2026-11-23; 127,880 pulls (2026-11-23) | stdio + HTTP (`:3600`, `MCP_BRIDGE_PORT`) | per-toolset; `MCP_READ_ONLY` tier; deletes/merges never retried [15] | password or session token; Bearer/OIDC on the MCP side [15] | **yes — `BUDGET_N_SERVER_URL` spans servers** [11] | Docker Hub + GHCR (current [17]); npm; Unraid app |
| **henfrydls/actual-budget-mcp** [25][26] | 21★, pushed 2026-11-11; listed in the **official Actual community projects** [25] | stdio + HTTP | delete-preview + confirm; `ACTUAL_READ_ONLY=1` tier [25] | password (+ session-token/keychain variant) [25] | no (1 `ACTUAL_BUDGET_ID`) | npm + Claude-Desktop extension; no public container documented |
| type0labs-dev/actual-mcp [22] | 2★ | stdio only | 3-tier risk model; delete confirm-tokens; `readOnlyHint`/`destructiveHint` [22] | password only | no | npm |
| KazeFreeze/actual-budget-mcp [24] | 1★, v2 | stdio + streamable-http + SSE (deprecated) | full; multi-key Bearer with entropy enforcement; `MCP_STRICT_VERSION_CHECK` [24] | password only | no | GHCR multi-arch [24] |
| **guitarbeat/Actual-MCP-Server-Legacy** [23] | **ARCHIVED 2026-08**; README: work "moved to … agigante80/actual-mcp-server" [23] | stdio + HTTP | full incl. **`reconcile-account`** (statement balance) [23] | password or session token | switch-budget, one server | compose only |

Long tail (≤2★, no registry/image signal, from a 27-repo GitHub search):
3stacks, trek-boldly-go, dattmavis, Jacob-Tate (Claude.ai OAuth), cubicecho,
Saikumarmohan (the only Python one), mweichert, aaryan-rampal, jmlavoier
(wraps the official CLI), jwke21 (Rust), and index listings (Glama [19],
mcpservers.org [20], LobeHub [21]).

**Non-MCP surfaces:** `@actual-app/api` — the official Node SDK (npm latest
**26.11.0**, nightly 26.12.0; calendar versioning aligned to server releases;
MIT; maintained by the Actual team [2]); `@actual-app/cli` — official CLI
(Node 22; JSON/table/**CSV** output; ActualQL with group-by/limit/offset;
`_FILE` secret variants suited to Docker secrets; `bank-sync` subcommand [10]);
`jhonderson/actual-http-api` — 262★ REST wrapper over the SDK (public
version-matched images; Swagger; `EXPERIMENTAL_OPERATIONS_ENABLED` default-on
for endpoints that "rely on Actual internals" [3]).

### 2. What Actual's surface can and cannot do for the owner's workflow

Official stance, verbatim [1]: "Actual **does not** expose HTTP endpoints that
can be called. We do, however, offer a NPM package — API … the server does not
have the functionality for analyzing details of or modifying your budget … the
API client … will work on a local copy. … Other languages are not supported at
this point." The SDK downloads the budget file (SQLite) to a local data dir
and runs the full engine; writes sync back [1]. Consequently every MCP server
is a thin wrapper, and **breakage risk = SDK/server version drift** (KazeFreeze
built `MCP_STRICT_VERSION_CHECK` for exactly this [24]; henfrydls built
`repair_sync` for it [25]).

**API-reachable today (documented [6][7][8][9][10]):**
- **Import-reconciliation**: `importTransactions` — dedupe by `imported_id`,
  else amount + similar date + similar payee; "It will always favor the
  imported transaction" and resyncs the manual tx's date [8][6]; opts
  `defaultCleared` (default true), `dryRun`, `reimportDeleted`,
  `payeeNameNormalization` [6]; rules run on import [9].
- **Merging duplicates**: `mergeTransactions` (exactly two, same account/amount;
  imported preferred; survivor cleared if either was) [6] — the documented path
  for "bank-imported duplicate + manual entry" (agigante80 `merge` [16]).
- **`cleared` flag**: documented writable Transaction field [6]; rules can
  condition on and set it [9]; `importTransactions` marks imports cleared by
  default [6].
- **Splits**: `subtransactions` on create (children need amount/account/date/
  parent_id/is_child; parent `is_parent: true`); **the API does not validate
  the sum** — "the API call will succeed but an error will be displayed within
  the app" [6] — so the wrapper must enforce it (agigante80 does, and can split
  a plain tx **in place, preserving id / imported_id / cleared** so a
  bank-synced tx can be split without breaking import matching [16]).
- **Transfers**: via transfer payees (`transfer_acct`); import creates both
  sides; `transfer_id` must not be changed [6]; agigante80 `transfers_create`
  creates the paired debit+credit atomically [16].
- **Category/group assignment**: `updateTransaction({category})`, payee-level
  default category, full rules CRUD (pre/default/post stages, auto-learning
  from user behavior, per-payee/global opt-out [9]) — "assign items" is fully
  reachable.
- **Budgets**: amounts/carryover/hold/reset + experimental category templates
  [6]; schedules CRUD + computed dates [6][10]; batch updates [6][16].
- **Reads/queries**: `runQuery` — arbitrary ActualQL [6]; agigante80 exposes it
  SELECT-only as `run_query` [16]; CLI gives JSON/CSV/ActualQL from the
  terminal [10].
- **Exports**: `exportBudget()` → budget .zip (db.sqlite + metadata.json) [6]
  (agigante80 `budgets_export` [16]); CLI transaction list → CSV [10]. **There
  is no documented transaction-level "export" endpoint, and no "grouped
  payments" export in any surveyed source** (B1).
- **Bank sync**: `runBankSync` (GoCardless/SimpleFIN; Pluggy.ai named in
  import docs [8]) returns new/matched/updated [6].

**NOT API-reachable in the documented 26.10.0 surface:**
- **Statement-balance lock**: the UI flow (enter statement balance, mark txs
  cleared until the cleared total matches, "Lock transactions" → locked/
  `reconciled`; unlock reverts to cleared; "Create reconciliation transaction"
  for off-budget asset valuation [7]). `reconciled` is *queryable*
  (agigante80 filter [16]) and a tested rules *condition* [16], but it is
  **absent from the documented writable Transaction fields** [6]. The only
  surveyed server that shipped a `reconcile-account` tool is **archived** [23].
  Whether it can be set via undocumented SDK/DB paths is unverified (B2).
- **Budget-scoped API keys on 26.10.0**: the feature's commits
  ("budget API key lifecycle endpoints #9343", "authenticate budget downloads
  and sync with API keys #9344", "manage budget API keys in settings #9345",
  plus bank-sync key access #9485/#9486) merged **2026-11-08..21** — *after*
  v26.11.0 published 2026-11-02 [4][5]; npm's latest is 26.11.0, nightly
  26.12.0 [2]. API keys: per-budget scope, configurable permissions, revocable
  without signing out, passed as `sessionToken` [1]; "the better choice where
  available", but scoped keys may be refused for operations beyond an existing
  budget (e.g. importing a new budget) [3].
- **Auth on the lab's instances today**: `ACTUAL_OPENID_ENFORCE: true` [12] →
  "password login is disabled, so ACTUAL_PASSWORD can't be used" [13] (B3:
  verify live). Practical path: **session token** (`ACTUAL_SESSION_TOKEN` [13]
  / `ACTUAL_SERVER_SESSION_TOKEN` [3] / `ACTUAL_SESSION_TOKEN` for the CLI [10])
  — a `user-token` minted **after** the Keycloak login (enabling OpenID clears
  all sessions [3]), whose validity follows `ACTUAL_TOKEN_EXPIRATION` ("use
  never or a long duration for an unattended service" [3]); or **upgrade all
  three instances to 26.12+** (renovate-managed pin, routine bump flow [12])
  for API keys. Note: the repo's `actualbudget-sso-secret` ExternalSecret feeds
  the server's OIDC *client*, not a usable login for the MCP container [12] —
  the MCP credential is a new Bitwarden item + ExternalSecret per repo
  convention.

### 3. Deployment fit

- **Upstream image as a ToolHive MCPServer on home** [12]: any of the
  streamable-HTTP servers fits the `mcp.<name>:` entry shape (image,
  `transport: streamable-http`, `mcpPort: 8080` via `MCP_BRIDGE_PORT` [15] /
  `--sse --enable-bearer` [13] / `MCP_TRANSPORT=http` [24], Bearer via
  ExternalSecret). All need a **data volume for the SDK budget cache**
  (`MCP_BRIDGE_DATA_DIR` / `ACTUAL_DATA_DIR` / `MCP_DATA_DIR` [15][13][24]).
  The shared `mcp.home-lab` ingress + wildcard cert already exist [12]. B6:
  whether upstream images satisfy the hivetools non-root/65532 podTemplateSpec
  is unverified — check in dev (wekan-mcp sets its own user [12]).
- **Multi-tenancy**: (a) **one agigante80 deployment, `BUDGET_DEFAULT` +
  `BUDGET_1/2` with `BUDGET_N_SERVER_URL` per instance** — the documented
  "Budget 2 (different server)" case [11]; per-client static tokens can name
  their budgets [11]; caveat: one budget open per process — alternating budgets
  serialises on reload ("for heavy concurrent use of different budgets run one
  server per budget" [11]; unquantified, B5 — fine for single-agent use).
  (b) single-budget servers (s-stefanov [13], KazeFreeze [24], henfrydls [25])
  need **one deployment per instance** (3× surfaces/tokens). (c) an **in-repo
  custom container** (wekan-mcp shape [12]): the SDK is process-global [23], so
  it either switches in-process (reload per switch, as agigante80 does) or
  runs 3 SDK workers; it buys custom export shapes + a real
  reconcile-to-balance tool, at the cost of owning the code.
- **Cluster**: home is favoured by the evidence (all three budget instances on
  home; in-cluster `http://home-<name>.default.svc:5006`; no new public
  surface; `mcp.home-lab` cert pre-exists [12]). gpu (wekan-mcp's home [12])
  remains the plan's alternative.

## Contradictions and how to weigh them

- **C1 — "Does Actual have an API?"** Official docs deny any callable HTTP
  endpoints [1]; a 262★ REST wrapper [3] and curl-able endpoints
  (`/account/validate` [13]) exist, and jhonderson defaults ON "experimental
  endpoints that rely on Actual internals" [3]. Weighing: both are true at
  different layers — the SDK is the documented, versioned contract; the HTTP
  protocol is internal/unsupported. Don't build on raw endpoints; pin and track
  the SDK.
- **C2 — Is bank reconciliation a first-class API capability?** The archived
  guitarbeat server shipped `reconcile-account` + transfer-linking and its work
  "moved to" the agigante80 engine [23] — yet the current agigante80 surface
  has import/merge/bank_sync but **no** reconcile-to-balance tool [16], and the
  official docs keep `reconciled` out of the writable fields [6]. Weighing:
  import-reconciliation is first-class [6][8]; statement-balance locking is
  UI-only in the official surface [7]. The owner's "reconcile" must be
  disambiguated (decision point 2).
- **C3 — When do API keys exist?** npm latest 26.11.0 [2] vs feature merged
  2026-11-08..21 [5] vs v26.11.0 published 2026-11-02 [4]: keys land in
  **26.12.0**. jhonderson's "newer servers can create API keys" [3] is true
  but version-gated; the lab's 26.10.0 predates the feature.
- **C4 — Rules condition fields:** UI docs list `cleared` but not
  `reconciled`/`transfer`/`parent` [9]; agigante80's condition map — unit-
  tested against the installed Actual every run [16] — includes them. Weighing:
  trust the tested map [16] for what the engine accepts.
- **Agreements across all perspectives (likely true):** the Node SDK is the only
  official surface and every serious server wraps it [1][3][13][15][22][24][25];
  writes are opt-in/confirmed everywhere (genre safety convention [13][15][22][25]);
  splits + import dedupe are well-supported [6][8]; multi-budget support is thin
  outside agigante80 [11]; "lock transactions" is a UI feature [7].
- **Blind spots:** B1 the exact "payments grouped together" vs "item-level but
  not bank-balanced" export shapes — **no source covers them; owner question,
  not invented here**. B2 whether `reconciled` is settable via undocumented
  paths (needs a live test). B3 live `ACTUAL_TOKEN_EXPIRATION` and whether
  26.10.0 truly disables password login under OIDC enforce (repo doesn't pin
  it). B4 agigante80's OIDC per-user budget ACL vs the lab's
  `ACTUAL_USER_CREATION_MODE: login` (static-token mode sidesteps it). B5 the
  runtime cost of budget switching (documented caveat, unquantified [11]). B6
  upstream images' non-root/65532 fit (check in dev).

## Implications for the plan

**Recommended option:** deploy **`agigante80/actual-mcp-server`** (GHCR image,
current [17]; MIT [15]) as **one** ToolHive MCPServer on the **home** cluster,
configured with the `BUDGET_N` registry spanning the three in-cluster instances
[11], Bearer auth (`MCP_SSE_AUTHORIZATION`) from a new ExternalSecret, a data
volume for the SDK cache [15], `MCP_READ_ONLY=true` (or `MCP_TOOLSETS=chat`)
as the conservative first tier [15]. Rationale: the only mainstream server that
spans multiple servers in one deployment [11]; the complete write surface the
ticket names — in-place splits preserving import-matching, paired transfers,
import-with-dedupe, budgets, rules, schedules, ActualQL reads [16]; per-client
static tokens + read-only tier [15]; actively maintained (pushed 2026-11-23,
127,880 pulls [17]). henfrydls is the credible alternative if the owner prefers
the official-community-listed server [25] — but it is single-budget (3
deployments) and has no public container documented. An in-repo custom
container (wekan-mcp shape [12]) becomes justified **only if** the owner's
export/reconcile semantics (decision points 1–2) can't be met by the upstream
tools — decide that after the owner answers, not before.

**Decision points the planner must put to the owner:**
1. **Export shapes** — what exactly are "payments grouped together" vs
   "item-level but not bank-balanced" (format, source of the grouping)? Actual
   has no named such export (budget .zip [6], transaction CSV [10], ActualQL
   [6] are all it has); the answer decides whether upstream tools suffice or a
   custom container is needed (B1).
2. **Reconcile semantics** — is import-reconciliation (dedupe/merge/cleared,
   all API-reachable [6][8]) enough, or is statement-balance "lock" required
   (UI-only in the documented surface [7][6]; would need custom code over an
   undocumented flag — B2)?
3. **Auth/version** — stay on 26.10.0 with a session token (expiry caveat;
   minted after the Keycloak login [3][13]) vs upgrade all three instances to
   26.12+ for revocable budget-scoped API keys [1][3][4][5]?
4. **Target scope + tier** — one deployment covering all three instances
   (`BUDGET_N` [11]) vs wuulf-only, and read-only-first vs full writes as the
   default tier [15].

## Open questions (owner-only; not already answered by EXPLORE.md)

1. The exact "exports" the owner means — "payments grouped together" vs
   "item-level but not bank-balanced": which format, and what produces the
   grouping? (B1 — flagged, not invented.)
2. For "reconcile the lists": import-reconciliation (dedupe/merge/cleared) vs
   bank reconciliation (lock to statement balance — not in the documented API
   surface; would be custom code or UI work).
3. Auth: session tokens on 26.10.0 (one per instance, expiry caveat) vs
   upgrading all three instances to 26.12+ for budget-scoped API keys.
4. Scope: does the MCP cover all three instances (default/bri/wuulf) or wuulf
   only, and read-only-first vs full writes as the starting tier?

---

# Post Research (2026-11-24)

Scope: a targeted verification round on the Pre Research's five plan-critical
inferences (the coord's questions) — not a fresh multi-perspective STORM run;
each answer was fact-checked against primary sources (registry APIs, release
artifacts, repo source at master/tags, live cluster logs). Citation trail: the
same `sources.md` — [27]–[55] appended after the Pre Research's [1]–[26]. The
Pre Research sections above are untouched; where live evidence disagrees, this
section supersedes it (marked C-post-1..3).

## Q1 — Is 26.12.0 published? (confidence: 10/10 "not shipped"; 9/10 cadence)

**Verdict: NOT published (2026-11-24).** Four independent live sources agree:
GitHub releases top out at `v26.11.0` (published 2026-11-02T01:54:02Z) [27];
GitHub tags top at `v26.11.0`, no 26.12.0 or rc tag in the top 30 [28]; npm
`@actual-app/api` `latest` = 26.11.0 [29]; the live 26.11.0 blog release notes
list 22 PRs, zero of them API-key [30] — the API-key feature (merged
2026-11-08..21 [32]–[36]) is NOT in 26.11.0. The plan's gate (lines 27–33)
holds as written.

- **Earliest credible signals:** npm `nightly` = `26.12.0-nightly.20261124`
  (today's build) [29], plus the five `upcoming-release-notes/` API-key
  fragments on master (api-key-lifecycle, budget-api-key-access,
  api-key-settings, api-key-bank-sync, api-key-shared-bank-sync — the pending
  26.12.0 feature set, quoted verbatim in [31]).
- **Re-check cadence:** releases run ~monthly, early-month (26.8.1 Aug 7 →
  26.9.0 Sep 1 → 26.10.0 Oct 2 → 26.11.0 Nov 2 [30]) → **re-check early
  December 2026** (GitHub releases API [27]; the npm nightly date stamp rolls
  daily [29]).
- **Consequence (as planned):** the MCP pod stays **inert** until the owner
  merges the Renovate pin move (plan Prerequisite 3, lines 48–53); no
  session-token fallback (owner rejected the interim path, binding #4).

## Q2 — Budget-scoped API-key shape (confidence: 9/10)

9/10: mechanism verified against master source + release-note fragments + live
official docs; the 26.12.0 *published build* is presumed to match master —
unverified, it does not exist yet.

- **Minting:** per budget, in the UI (Settings → General → Security → API keys
  → Add key) [37][34]; the key is owned by the minting user and granted to
  selected budget files (`api_keys` + `api_key_budgets` schema [32]).
- **Format:** `/^actual_[A-Za-z0-9_-]{43}$/` [33].
- **Auth mechanism:** stateless per request (token → sha256 → key row → user +
  granted file ids; no stored session) [33]. API-key routes:
  `GET /sync/{list-user-files,get-user-file-info,download-user-file}`,
  `POST /sync`, `/user-get-key` [33].
- **Permission axes:** the per-budget-file grant is the hard scope — ungranted
  file → 403 `file-access-not-allowed`; `list-user-files` filtered to grants
  [33]. The only opt-in permission is `bank-sync-global` (SHARED bank
  connections; `api_key_permissions` table [36]); per-budget bank credentials
  (SimpleFIN/Pluggy) need no extra permission [35]. **There is NO read/write
  axis, NO per-account axis, NO per-operation axis** — a granted file = full
  read+write within that budget ("download and update selected budgets" [31]).
- **Passing:** `sessionToken` to `api.init()` — CONFIRMED in the official docs
  (live [37]); SDK error code `token-expired` [38].
- **Expiry: none** — the schema has no `expires_at` [32]; the UI docs list none
  [37]. Revocation: individual [31][37]. Wipe triggers:
  `enableOpenID`/`disableOpenID` delete **all** `api_keys`; a password change
  deletes the password user's keys [32].
- **Refusal beyond an existing budget:** mechanically = file-grant 403 +
  filtered file list [33] (a new budget = a new ungranted file id). The Pre
  Research third-party quote (jhonderson [3]: scoped keys "may be refused for
  operations beyond an existing budget (e.g. importing a new budget)") is
  consistent with the mechanism but is NOT an official-docs statement — neither
  the docs page nor the error table carries that sentence [37][38].
- **OQ2 verdict: the "full documented-workflow scope" IS mintable** — one grant
  to the wuulf budget file covers reads + every in-file write of the documented
  workflow, no extra permission (wuulf does not use shared bank connections).
  **No conflict with the owner's answer.**

## Q3 — Does agigante80 accept a budget-scoped API key? (confidence: 10/10 —
source + tag + docs + tracker agree) — **the central finding**

**Verdict: NO. Current upstream (0.35.2, pushed 2026-11-24T04:01:48Z [40])
authenticates to Actual PASSWORD ONLY.**

- Zero `sessionToken`/`SESSION_TOKEN` in src, `.env.example`, README, docs, or
  git history [43]. Config reference, verbatim [44]: "This server always signs
  in to Actual with a password, so upstream password login must stay enabled."
  The `v0.4.2` tag's `.env.example` is also password-only. No open issue in
  the tracker requesting API-key/session-token support [40].
- The plan's C02 "per-budget API-key env var" (line 14) and the
  `BUDGET_<name>_SESSION_TOKEN` convention guess (lines 48–54) **DO NOT EXIST
  upstream** [43][45]. The only Actual-credential vars are `ACTUAL_PASSWORD`
  (required) / `BUDGET_N_PASSWORD` (falls back to `ACTUAL_PASSWORD`) [45][46].
- Pre Research's "password or session token" for agigante80 ([11][15]) is
  **SUPERSEDED** — the multiple-budgets guide documents `BUDGET_N_PASSWORD`
  only [45]; no session-token var was ever documented. (C-post-1: correction,
  not contradiction.)
- **Compound:** a password login requires a password auth row on the server.
  `ACTUAL_OPENID_ENFORCE` does **NOT** close the password `/login` endpoint
  (source [39]: the flag filters the UI method list only when ≥2 auth rows
  exist; `POST /login` with `loginMethod: 'password'` stays in
  `allowedLoginMethods` by default and passes when a password row exists) —
  this REFUTES the s-stefanov README claim [13] carried as unverified B3
  (C-post-2). What kills password login is the ABSENCE of a password row: a
  fresh server bootstrapped with OIDC envs only is openid-only —
  `bootstrap({openId}, forced)` preserves an existing password row but never
  creates one [39]. C01's wuulf is a FRESH PVC + the bri-budget pattern (OIDC
  envs, no password row created) → **openid-only → `loginWithPassword` returns
  `invalid-password` → the current agigante80 cannot connect to wuulf at all**
  — regardless of the 26.12.0 gate.
- **Live (2026-11-24, home cluster):** the existing instances' main containers
  show the app.ts auto-bootstrap path ("OpenID configuration found. Preparing
  server to use it" → "OpenID configured!" → listening [52]); the `budget`
  instance's `01-enable-openid` initContainer **fails on every start** — `npm
  error Missing script: "enable-openid"` (the 26.10.0 image has
  `disable-openid`, not `enable-openid`; the chart's `|| true` swallows it)
  [52]. → Whether the lab's EXISTING instances carry a password row is
  history-dependent and not resolvable from read-only surfaces (dev/owner live
  check; only relevant if a password path is ever revisited — the binding
  rejects it, so recorded for completeness).
- **MCP-side auth is unaffected** (the plan is correct there):
  `MCP_SSE_AUTHORIZATION` static Bearer (≥32 chars) / `MCP_STATIC_TOKENS`
  per-client / `AUTH_PROVIDER=oidc` [46].
- **`MCP_READ_ONLY` semantics:** a DOUBLE boundary — both a tool-exposure
  filter AND a hard server-side refusal: `.env.example` [46]: "true" hides
  **AND** refuses every write-capable tool (including `actual_bank_sync`,
  `actual_budgets_export`, `actual_budgets_switch`, `actual_session_close`).
  README [47]: the compact surface publishes 6 tools under read-only
  (`get_context`, `list_entities`, `search_transactions`,
  `summarize_transactions`, `list_budget_months`, `run_query`); legacy
  publishes 37 of 85.
- **Workflow → tool map** [48] (tier 1 = blocked; flag flip = unblocked):
  import-with-dedupe → `actual_transactions_import`; merge duplicates →
  `actual_transactions_merge`; in-place split preserving imported_id/cleared →
  `actual_transactions_update` with `subtransactions`; transfer pairing →
  `actual_transfers_create`; category assignment →
  `actual_transactions_update`/`_batch`/`categories_*`; rules →
  `actual_rules_create_or_update`/`_batch`; budgets →
  `actual_budgets_set_amount`/`transfer`/`set_carryover`/`hold`/`updates_batch`;
  schedules → `actual_schedules_create`/`update`/`delete` (all writes blocked at
  tier 1; the matching reads survive). **Caveat: the flag flip alone unblocks
  the tools, but with the current upstream the CREDENTIAL path to pass an API
  key does not exist — the flag flip alone does NOT make the workflow usable;
  the credential is the gate (see the Effect section).**

## Q4 — Version-match hazard (confidence: 10/10 bundled versions — lockfile;
8/10 symptom list)

- **0.4.2 (the plan pin, published 2025-12-31 [55]):** bundles
  `@actual-app/api` **25.12.0** + crdt 2.1.0 (lockfile at the tag [42]);
  **no server-version guard in that build** [42][50].
- **0.35.2 (current, 2026-11-22 [40][41]):** bundles **26.11.0** + crdt 3.1.4
  [42]; an **advisory-only** version guard (#276: warn-once, fail-open, "never
  fails startup and never blocks an operation"; the real compatibility contract
  is the migration check `@actual-app/api` runs at `downloadBudget`) [50];
  range `minVersion 25.0.0 / testedMaxMajor 26` → 26.12.x falls INSIDE the
  tested major range, so NO warning fires.
- `package.json` is `^26.11.0` at HEAD with an `npm ci` lockfile build: the
  **next upstream image build after 26.12.0 publishes picks up the new SDK
  automatically** [42][43] — the image pin self-heals one release after the
  server pin move.
- No compatibility matrix published [50]. Upstream's release process gates its
  e2e stacks to the claimed server version (the 26.11 adoption: the gates had
  run against 26.7.0 since July; #618 fixed the scripts [51]).
- **Concrete drift (8/10 — the mechanism is documented; the 26.12-specific
  delta is unenumerable until the release notes exist):** 0.4.2 image vs
  26.12.x server = SDK 25.12 vs 26.12 (two calendar majors, no runtime guard
  in 0.4.2) → observable symptoms: login or budget-download failure,
  out-of-sync-migrations-class sync rejections, or silent drift in query
  results [38][50]. 0.35.2 vs 26.12.x = one major, same symptom surface. The
  plan's canary (server startup log + `tools/list`) is the check.
- **Stale pin:** the latest stable versioned tag is **0.35.2** (963 tags,
  0.2.0..0.35.2 [41]; npm latest 0.35.2; GitHub release v0.35.2 published
  2026-11-22T18:19:16Z [40]; 0.4.2 published 2025-12-31 [55]). The plan's
  "verified newest stable versioned GHCR tag 2026-11-24" was **factually wrong
  on that date** — 0.35.2 had topped the registry two days earlier.
  (C-post-3.)

## Q5 — Container runtime fit (confidence: (a) 10/10 — Dockerfile + entrypoint
source; (b) 9/10 — exhaustive docs grep)

- **(a) B6 resolved:** the image **starts as ROOT by design** (Dockerfile: no
  `USER` line — "the container starts as ROOT … then drops to the non-root
  `app` user via su-exec"; `adduser -u 1001`). The entrypoint handles a
  forced non-root orchestrator user: "When not started as root (the
  orchestrator forced a user), it execs the app directly without adjustments.
  … PUID/PGID ignored" [49]. Under the repo-standard 65532 block [53] (which
  carries **no `fsGroup`**) the app therefore runs as 65532 — but the
  image-baked `/app/data` (`MCP_BRIDGE_DATA_DIR` default) is uid-1001-owned
  (**not writable** by 65532) and the CWD `/app` is root-owned (a
  CWD-relative default "would fail with EACCES" [44]). The 65532 block works
  **only when `MCP_BRIDGE_DATA_DIR` points at the PVC mount AND the pod sets
  `fsGroup: 65532`** (an addition — the repo-standard block has no fsGroup).
  The evidence-backed adjustment: **KEEP 65532, ADD `fsGroup: 65532`, POINT
  `MCP_BRIDGE_DATA_DIR` AT THE MOUNT** (record in DECISIONS) — or run as
  root (deviating from the repo-standard block). The C02 note's "adjust the
  securityContext to match the image" is the wrong direction. Logs:
  `MCP_BRIDGE_STORE_LOGS` defaults false → `/app/logs` unused.
- **(b) Data-dir size:** the docs require a persistent PVC at `/app/data`
  [54] but carry **no size guidance anywhere** (exhaustive grep of docs/,
  README, docker-compose) — 5Gi stays a plan assumption (parity with the
  budget instances' 5Gi data PVCs); undersized → budget sync fails at runtime
  (visible).

## Contradictions and corrections vs Pre Research

- **C-post-1 — "agigante80 auth = password or session token" [11][15]:
  SUPERSEDED.** Password-only, no token var (source + tag + docs + tracker
  [40]–[46]).
- **C-post-2 — "password login is disabled under ACTUAL_OPENID_ENFORCE=true"
  [13] (B3, unverified): REFUTED at the endpoint level [39].** The flag is a
  UI-method-list filter; the password `/login` endpoint stays open when a
  password row exists. What kills password login is the ABSENCE of a password
  row (openid-only bootstrap [39]), which is PVC-history-dependent on the lab
  instances (live: the `enable-openid` initContainer never ran [52]).
- **C-post-3 — "0.4.2 = newest stable versioned GHCR tag" (plan verification
  claim): STALE.** 0.35.2 has been newest since 2026-11-22 [40][41].
- **Reconfirmed agreements:** the SDK is the only official surface and every
  serious server wraps it [1][3][13][15]; budget-scoped keys are the 26.12.0
  feature set [31]–[38]; `MCP_READ_ONLY` is a dual boundary (filter + refusal)
  [46][47]; agigante80's multi-server registry is the only mainstream
  multi-instance option [11][45].

## Effect on the approved plan

The plan was approved as written with C02 inert at first fire by design. The
Post Research verdict: **the plan's 26.12.x gate is NECESSARY BUT NOT
SUFFICIENT** — after 26.12.0 publishes and the owner merges the pin move, the
current upstream agigante80 image still cannot authenticate with an API key
(Q3). No binding is re-opened (the owner's 26.12+ API-key decision stands;
what is new is that the chosen server cannot consume such a key yet). Lines
that must move (the plan folds this delta per the DECISIONS rework sequence;
the owner decides: wait for upstream support — no ETA, no open issue [40] — or
re-evaluate the server/credential path):

1. **C02 line 12 + line 14 + lines 48–54 (credential design) + plan lines
   27–33, 48–55 (the gate):** the "per-budget API-key env var" /
   `BUDGET_<name>_SESSION_TOKEN` convention **does not exist upstream**
   [43][45][44]. The unlock condition must name **upstream session-token /
   API-key support** beside the 26.12.x gate. Flagged as a conflict with the
   plan's premise (C02 was written assuming the key can be handed to the
   server via an env var) — evidence: the config reference "always signs in …
   with a password" [44]. Compound blocker: even the one credential upstream
   supports (password) cannot reach wuulf — a fresh wuulf PVC + OIDC envs →
   openid-only bootstrap, no password row [39]; the existing instances'
   password-row state is inconclusive from read-only surfaces (the
   `enable-openid` initContainer never ran [52]).
2. **C02 line 12 (image pin) + plan lines 34–37 ("Verified at planning
   time"):** `0.4.2` → `0.35.2` (live GHCR 2026-11-24: 963 tags,
   0.2.0..0.35.2 [41]; 0.35.2 published 2026-11-22 [40]; 0.4.2 published
   2025-12-31 [55]). The pin line's "(verified newest stable versioned GHCR
   tag 2026-11-24)" was factually wrong on that date (C-post-3).
3. **C02 lines 55–57 (B6 check) + plan lines 134–136 (B6 risk) → RESOLVED in
   research** (no dev-time check needed): the image starts root by design;
   the entrypoint handles a forced non-root [49]. The evidence-backed
   adjustment: **KEEP 65532, ADD `fsGroup: 65532`, POINT `MCP_BRIDGE_DATA_DIR`
   AT THE PVC MOUNT** — or run root; record the chosen option in DECISIONS.md
   (touches C02 line 12's data-dir env, line 16's securityContext block).
4. **C02 line 15 + plan lines 137–139 (5Gi PVC):** no documented size
   guidance upstream [54] — 5Gi stays an assumption; the "undersized → sync
   fails at runtime (visible)" note stands.
5. **Plan OQ2 (lines 120–125) → resolved, no conflict:** the full
   documented-workflow scope IS mintable — one grant to the wuulf budget file
   = reads + every in-file write; no extra permission needed
   (`bank-sync-global` is only for shared bank connections, which wuulf does
   not use [35][36]); no TTL, individually revocable [32][31][37]; the
   `sessionToken` pass-through is the docs-confirmed path [37].
6. **Plan lines 128–133 (version-drift risk) — updated with concrete
   numbers:** 0.4.2 bundles SDK 25.12.0 (two majors behind; no guard in that
   build); 0.35.2 bundles 26.11.0 (one major behind; advisory-only warn-once
   fail-open guard, 26.12.x in-range → no warning; the real contract is the
   SDK's `downloadBudget` migration check) [42][50]. Upstream's `^26.11.0` +
   `npm ci`: the next upstream image build after 26.12.0 publishes picks up
   the new SDK automatically [42].
7. **C02 lines 58–64 (inert + tier notes):** the first tier is read-only
   `MCP_READ_ONLY=true` — confirmed the dual boundary (hides AND refuses
   [46]); the 6 surviving compact tools are enumerated [47]; the workflow →
   tool map is verified [48] — the write tier is a values flip, but **the
   credential is the gate, not the flag** (item 1).
8. **Re-check cadence (plan lines 27–33, 48–53):** 26.12.0 NOT shipped;
   earliest credible signals = the npm `nightly` date stamp [29] + the
   `upcoming-release-notes/` API-key fragments [31]; **re-check early December
   2026** (~monthly early-month cadence [30]). The MCP pod stays inert until
   the owner merges the Renovate pin move — unchanged.
