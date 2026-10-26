# RESEARCH — WeKan v9.99 → v12.64 upgrade + multi-action-rules cutover (AI-Dev board)

Commissioned by the board-coord intake track 2026-10-25. Goal: upgrade the lab
WeKan (wekan.spencerslab.com + boards.spencerslab.com) from v9.99 to v12.64 and
replace the v9.99 checklist rule-cluster with ONE native multi-action rule that
delivers `Model(s)` with `Qwen Flash` + `Local (gpu-ai)` CHECKED at card
creation, deterministically for UI and REST alike. The v9.99 race forensics are
NOT re-derived — see sibling
`.agents/plans/2026/2026-10-feat-board-coord-intake/RESEARCH.md` (cited below as
**[X1]**); this file aligns to its terminology (Std rules, EXP1/EXP2,
RACE-TEST, Design H). Method note: like [X1], the topic is deterministic source
forensics (deployed v9.99 + target v12.64, both read from tags), so the STORM
interview stage is realized as evidence-gathering against primary sources;
contradictions and reliability notes are kept inline. All sources read
first-hand 2026-10-25.

## TL;DR

1. **Pin location:** the image is not pinned in our values at all — it comes
   from the official **Helm chart version**: `services/home/prod/Chart.yaml`
   L39-48 pins chart `wekan: 9.99.0` twice (the `wekan` bot-facing release and
   the `boards` alias, both chart-version-pinned), lockfile `Chart.lock`
   tracked. Bumping both entries to `12.64.0` + `helm dependency update` is the
   image bump. `chart 12.64.0 (appVersion 12.64)` exists in
   `wekan.github.io/charts/index.yaml`; image `ghcr.io/wekan/wekan:v12.64`
   (chart annotation + release published 2026-10-24).
2. **App-side jump is supported in one step:** v9.99→v12.64 adds NO removed
   REST routes (117 v9.99 routes all present in v12.64's 149), env vars are
   stable (WITH_API, OIDC/OAUTH2_*, ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS,
   METEOR_REACTIVITY_ORDER all still read), and startup schema-migrations are
   version-gated, idempotent and non-destructive (v12.64 adds 4 repair steps to
   v9.99's 9). Live DB is MongoDB 7.0.34 (`home-mongodb-0`) — v12.64 supports
   MongoDB 6–9, so **no MongoDB bump is required**. mongodump-first is still
   mandatory.
3. **The real risk is chart-level, not app-level:** chart 12.64 **removed the
   bundled MongoDB subchart** (dropped at chart 10.86.0; the chart now ships
   FerretDB by default, `ferretdb.enabled: true`). Our `home-mongodb`
   StatefulSet+Service were rendered by the 9.99 chart's subchart under ArgoCD
   app `home` — after the bump they are no longer in the desired manifest. The
   app has no automated sync today (so no silent prune), but any future pruned
   sync deletes the DB service. Mitigation options in §Runbook step 0.
4. **wekan-mcp survives the upgrade:** every route it uses exists unchanged on
   v12.64, login wire-shape identical, Bearer auth unchanged. Two flags: REST
   rule **writes now demand board admin** (v9.99: write access) — promote the
   service account; and MCP `_slim_rule` hides the new `extraActions`, so MCP
   is blind to the merged rule's insides until a one-line passthrough patch.
5. **Multi-action rule (v12.10+; present in v12.64):** one `createCard` rule,
   primary action `addChecklistWithItems{Model(s)}` then ordered extras
   `[checkItem×2, addChecklistWithItems×3]` — executed strictly in order via
   `executeRulesAtDepth` (5 extras ≤ cap 10). Extras are creatable ONLY via UI
   wizard ("Add another action") or Rules→Import JSON (DDP `rules.createRule` +
   `rules.addPart`, board-admin), never via REST. Exact JSON in §Q4.

## Q1 — Where the deployment is pinned (repo + cluster)

**Repo files to touch for the image bump:**

| File | Lines | What |
|---|---|---|
| `services/home/prod/Chart.yaml` | L39-41 (`wekan` dep) and L44-48 (`wekan` dep aliased `boards`) | `version: 9.99.0` ×2 → `12.64.0`. Repository `https://wekan.github.io/charts/`. **Both must bump together** (two frontends, one DB). |
| `services/home/prod/Chart.lock` | tracked; two `- name: wekan … version: 9.99.0` entries | refresh with `helm dependency update services/home/prod` |
| `services/home/prod/values.yaml` | `wekan:` block L268-313, `boards:` block L314-349 | see below — values edits needed for chart 12.64 |
| `custom-values/home/prod-values.yaml` | L102-105 | only `wekan.root_url` / `boards.root_url` — untouched by the bump |
| `services/home/prod/templates/secret-wekan-sso.yaml` | whole file | OAUTH2_*/MAIL_* keys fed via `extraEnvFrom` — all names still valid on v12.64 (§Q2 env check) |
| `services/proxy-local/prod/values.yaml` | L164-165 | ingress only, no version |

No `image:` override exists in our values — the chart's own
`image.repository: ghcr.io/wekan/wekan` + `image.tag` (v9.99 / v12.64) is the
pin. (Per AGENTS.md, hand-bumping a chart *app* version is forbidden, but here
the chart version IS the pin and its bump is the whole upgrade; our own
`Chart.yaml version: 1.0.0` is untouched, so no `release.yaml` interaction.)

**Values that must change in `services/home/prod/values.yaml`:** the lab keys
`root_url, env, secretEnv, extraEnvFrom, resources, autoscaling, ingress,
mongodb` — every one still exists in chart 12.64's values (diff: 12.64 is a
strict superset, only `ferretdb` + `externalDatabase` added). Required edits:

- `wekan.mongodb` (L307-313) and `boards.mongodb` (L338-344): legacy
  nameOverride/replicaset keys are **inert** on chart 9.99 too (groundhog2k
  subchart ignores those key shapes) and inert on 12.64 (`mongodb.enabled`
  "no longer installs anything", chart values comment). Remove them, and add
  **`ferretdb.enabled: false` to BOTH blocks** — else the chart deploys its new
  FerretDB StatefulSet (default `enabled: true`), and BOTH subcharts render
  `<release>-ferretdb` (helpers compute the name from `.Release.Name`, not the
  alias) → duplicate-colliding DB objects under one umbrella.
- Keep `secretEnv.MONGO_URL: mongodb://home-mongodb:27017` — chart 12.64's
  deployment template (#6289 guard, `deployment.yaml` L66-81) only emits its
  computed MONGO_URL when the user has NOT supplied one via `env`/`secretEnv`,
  so our external DB keeps winning deterministically. `externalDatabase.url`
  stays `""` (would otherwise append `?directConnection=true`, which we do not
  want against the plain service).

**Live cluster (verified read-only 2026-10-25, `readonly-home-kubernetes`):**

- Deployment `home-wekan` (ns `default`, Argo app `home`): image
  `ghcr.io/wekan/wekan:v9.99`, 196 d old, 1/1 Ready.
- Deployment `home-boards`: same image, labels `chart=boards-9.99.0`.
- `home-mongodb`: StatefulSet + Service, ns `default`,
  `helm.sh/chart=mongodb-0.7.6` (groundhog2k subchart pulled in by the wekan
  chart), pod `home-mongodb-0` image **`docker.io/mongo:7.0.34`** (the service
  label `app.kubernetes.io/version=8.0.16` is stale subchart metadata — the
  image tag is authoritative; the 9.99 wekan chart's values pin
  `mongodb.image.tag: 7.0.34`). PVCs: `mongodb-volume-home-mongodb-0` (data)
  and `home-wekan-shared-data` (attachments /data, `WRITABLE_PATH=/data` baked
  into both images' Dockerfiles — v9.99 Dockerfile L166, v12.64 L372).
- ArgoCD `Application home` (ns `default` on the home cluster):
  `syncOptions=[CreateNamespace=true, ServerSideApply=true]`, **no automated
  sync block** → upgrades land only via explicit sync; pruning is not
  currently automatic. Both wekan and boards point at the same DB via
  secretEnv MONGO_URL (two pods, one data plane — "split wekan into 2 pods to
  handle 2 urls", values L267).

**Renovate:** `renovate.json` L205 lists `wekan` under "Non-critical services"
(matchUpdateTypes `minor,patch`, automerge in a Tuesday window). A 9.99.0 →
12.64.0 chart bump is a **major** — outside that rule, so no auto-PR will fire
or auto-merge this; the upgrade is intentionally human/agent-driven.

## Q2 — Upgrade path v9.99 → v12.64

Nominally 3 majors; in practice one year of high-frequency xet7 releases (374
chart versions in the index between 1.0.0 and 12.64.0; v12.64 release published
2026-10-24, GitHub API).

**Direct single-step image/chart bump is the supported route. Evidence:**

- **Startup schema migrations, auto-run:** both versions carry
  `server/startupSchemaUpgrade.js` → `server/lib/schemaUpgradeSteps.js`
  (header docs): a `_wekan_migration` marker stores the WeKan version; after a
  version change one re-check pass runs, "migrates ONLY what is missing",
  every step idempotent, resume-safe, and "a step failure never blocks WeKan
  from starting". v12.64's step list vs v9.99's: same base nine
  (`archived-flag-backfill`, `swimlane-structure`, `merge-per-swimlane-lists`,
  `checklist-items-embedded`, `customfields-boardIds`, `board-allows-defaults`,
  `board-members-isactive`, `board-permission-lowercase`, `fs-path-heal`) plus
  four new backfill/repair steps: `attachment-kind-flags`,
  `nonfinite-sort-repair`, `checklist-minicard-unset`, `card-children-boardid`
  (`schemaUpgradeSteps.js` v12.64 L625/737/773/811). All additive/defaulting —
  none deletes or rewrites user content destructively. Force knob:
  `WEKAN_FORCE_SCHEMA_UPGRADE=true`.
- **MongoDB compatibility:** `docs/Databases/Supported.md` (v12.64): MongoDB 6,
  7, 8, 9 all "Works" (conformance runs on 7.0.43 / 8.0.32 / 9.0.2; FerretDB
  v1+SQLite is the new default platform story). `docker-compose-mongodb-v7.yml`
  still pins `mongo:7` in v12.64 (same file/pin as v9.99). **Live 7.0.34 stays;
  no DB bump required.** (Note the doc's kernel-6.19/MongoDB caveat — homelab
  nodes unaffected; and MongoDB majors themselves upgrade one-at-a-time —
  irrelevant here.)
- **Meteor:** `.meteor/release` 3.5 → 3.6-rc.0 — internal to the image, no
  operator action.
- **Env vars: no renames affecting us.** All of `WITH_API`,
  `ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS`, `OIDC_REDIRECTION_ENABLED`,
  `METEOR_REACTIVITY_ORDER` still read in v12.64 server/imports; the
  `OAUTH2_*` set used by `secret-wekan-sso.yaml` is a strict superset of
  v9.99's (adds `OAUTH2_DEFAULT_ORGANIZATION`, `OAUTH2_REQUEST_PERMISSIONS`,
  `OAUTH2_ID_TOKEN_WHITELIST_FIELDS` …). `MAIL_URL` still honored
  (`server/lib/mailTransport.js`).
- **Behavioural deltas to know (none blocking):**
  - REST gate (`apiMiddleware.js`): WITH_API=false now refuses with an explicit
    message instead of a 301 to `/` (lab runs WITH_API=true — unchanged).
  - `POST /users/login` gains brute-force throttling (GHSA-2g94-9x3m-hv37 cited
    in-code): `server/lib/loginAttemptThrottle.js` 60 s sliding window, 60 s
    lockout on repeated failures + per-account delay
    (`accountLoginDelay.js`); success bodies identical (`{id, token,
    tokenExpires}`, `apiAuthRoutes.js` v9.99 L235-256 vs v12.64 L235-255);
    error body `{error, reason}` plus `Retry-After` header on 429. wekan-mcp
    mints a token once per pod start (`containers/wekan-mcp/wekan_mcp/wekan.py`
    `login()` L104-144) → safe; a wrong password now surfaces as 429 on the
    second attempt instead of endless 401s.
  - Long-lived tokens: new `POST /api/users/logout` revocation route (fixes
    #1437); the 10950-day expiration env still governs the bot token.
  - Rule REST writes require board admin (§Q3) — the one operational change
    that MUST be done before/with the upgrade if MCP keeps managing rules.
  - Rules page is board-admin-only in the UI (docs `Rules/Rules/Rules.md`
    L22-31: opt-in "show rules to members" toggles), members just lose the
    rules view by default.

**Stepped upgrades:** not required. The DB shape is forward-migrated by the
startup steps above; the chart's own values comments state the supported
upgrade route for existing data ("Nothing here deletes it… keep using them —
ferretdb.enabled=false + externalDatabase.url"; and "To move onto FerretDB
instead, dump from MongoDB and restore into it — mongodump/mongorestore work
unchanged"). The only stepped-ness is at the **chart** level (mongodb subchart
gone since chart 10.86.0, replaced by FerretDB templates) — one values edit
handles it.

**Backup/rollback story** (official, `docs/Backup/Backup.md` + wekan.fi/upgrade
fetched 2026-10-25): for a MongoDB deployment like ours = `mongodump` of the
`wekan` DB against `home-mongodb` before the sync (plus the `/data` PVC is
untouched by the bump — attachments stay). v12 also ships an Admin Panel
backup/continuous-backup subsystem (Backup.md) usable post-upgrade. Restore =
`mongorestore` into MongoDB 6-9. Because no pod-exec is granted by MCP policy,
the dump/restore commands are **user-run** — exact commands in the runbook.

## Q3 — wekan-mcp compatibility on v12.64

Method: extracted every `WebApp.handlers.{get,post,put,delete}('<path>')`
registration under `server/` at both tags — v9.99: **117 routes, v12.64: 149;
the removal set is EMPTY** (pure addition: ActivityPub, admin/problems,
inbound-email, boardViewSettings, cardFieldOrder, archive list endpoints,
attachment delete/restore, bot-runs, passwordless, sqrl, exports…). Then each
route actually called by `containers/wekan-mcp/wekan_mcp/server.py` was
checked against v12.64 individually:

| MCP call | Route | v12.64 verdict |
|---|---|---|
| login | `POST /users/login` | same body/response; + 429 throttling (Q2) |
| validate | `GET /api/user` | present |
| list_boards | `GET /api/users/:userId/boards` | present |
| get_board | `GET /api/boards/:boardId` | present (adminOnly custom-field values now redacted for non-admins — board fields `slug`/`session` are plain text, verified via dev-boards `get_custom_field`; no effect) |
| lists/swimlanes/cards | `GET /api/boards/:b/lists[/:l]`, `/swimlanes`, `/lists/:l/cards`, `/api/cards/:c` | present; GET single-card still the `/api/cards/:cardId` path (server enforces board access) |
| create_card | `POST …/lists/:l/cards` | present, same body fields; response unchanged (rules still run async after the 200) |
| update/move_card | `PUT …/lists/:l/cards/:c` | present |
| comments | `GET/POST …/cards/:c/comments` | present |
| checklists | `GET/POST …/cards/:c/checklists[/:cl]` | present; POST body accepts `title`+`items` as before |
| checklist items | `POST …/items`, `PUT …/items/:i`, `DELETE …/items/:i` | present. PUT still writes `isFinished` via `ChecklistItems.direct.updateAsync` (L231-234, hook-bypass — the Design H tool's checks stay rule-silent, as [X1] proved). POST items NEW behaviour (#6544): items now append by `sort` instead of all getting `sort: 0` — a fix, not a break (MCP `add_checklist_item` ordering becomes stable). |
| custom fields | `GET/POST …/custom-fields[/:cf]`, `PUT …/cards/:c/customFields/:cf` (cards.js v9.99 L1546 / v12.64 L2284), whole-array PUT fallback | present, same shapes |
| rules read | `GET …/rules`, `GET …/rules/:r` | present; member access (`checkBoardAccess`); responses now also carry `extraTriggers`/`extraActions` when set (`serializeRule`, rules.js L76-80) |
| rules write | `POST/PUT/DELETE …/rules[/:r]` | **present but auth changed: `Authentication.checkBoardAdmin`** (v12.64 rules.js L156/212/257) vs v9.99's `checkBoardWriteAccess` (L142/190/228). REST create/update still only handle a SINGLE inline trigger+action — extras cannot be created via REST even on v12.64. PUT gains the `enabled` pause flag (L222-226). |

**Flags / follow-ups:**
1. **The wekan-mcp service accounts must be promoted to board admin** on the
   AI-Dev board (UI: Members → role) before the cutover, or MCP
   `create_rule/update_rule/remove_rule` all start returning 401 after the
   upgrade. (Both tiers share one token: `services/gpu/prod/values.yaml`
   L670-727 `wekan-readonly`/`wekan-admin` + `services/dev/prod/values.yaml`
   L400-435 `dev-boards` → same `wekan.spencerslab.com` instance.)
2. `containers/wekan-mcp/wekan_mcp/server.py` `_slim_rule` (L141-150) keeps
   only `trigger`/`action` — after the cutover the merged rule's extras are
   invisible to the agents (`list_rules`/`get_rule` will show only the
   primary action). One-line passthrough of `extraTriggers`/`extraActions` is
   an MCP image follow-up (own chunk/ticket; v60 image bump).
3. `update_rule` (L618-637) doesn't expose the new `enabled` field — worth
   adding in the same patch (useful for future rule maintenance windows).
4. AdminPanel note: v12.64 redacts `adminOnly` custom-field VALUES from REST
   responses for non-board-admins (`sendJsonResult` → `adminOnlyCustomFields`
   redaction, apiMiddleware.js L153+, models/lib/adminOnlyCustomFields.js).
   Our board's fields are not adminOnly → no current impact; if someone later
   marks `slug`/`session` adminOnly, MCP card reads go blind — do not do that.

No auth-mechanism change (Bearer login-token hashing identical in
`apiMiddleware.authenticateByToken` at both tags).

## Q4 — The multi-action rule on v12.64: shape, semantics, creation

**Confirmed at tag v12.64** (#4294 landed; [X1] probed availability from
v12.10, depth-guard from v12.20; v12.64 is well inside):

- Storage (`models/rules.js` L48-66 + `models/lib/ruleParts.js`): one Rule doc
  = `{triggerId, actionId}` + optional `extraTriggerIds[]` / `extraActionIds[]`
  (`maxCount: 10` each) — arrays of **document IDs** into the Triggers/Actions
  collections, NOT inline bodies. "It fires when ANY of its triggers fires,
  once per activity, and runs its actions in order — the original first."
  A rule matched by several triggers is deduped (`uniqueRules`).
- Execution (`server/rulesHelper.js` L378-410): `executeRules` depth-guards at
  `MAX_RULE_DEPTH = 5` (L16), then per matching rule: `await
  performAction(primary)`, then `for (const extraId of
  ruleActionIds(rule).slice(1)) await performAction(extra)` — strictly
  sequential within a rule, on fresh server reads. **Cross-rule order remains
  unordered** (v12.64 `imports/reactiveCache.js` L309-313 `getTriggers` still
  sorts nothing — [X1]'s Q1 conclusion stands unchanged): everything that
  must be ordered belongs inside ONE rule, which is exactly our case.
- Action bodies unchanged from v9.99: `addChecklistWithItems
  {actionType, checklistName, checklistItems:"a,b,c"}` (items inserted exactly
  as split on `,` — no trim; leading-space item titles mismatch, [X1] lesson;
  rulesHelper v12.64 L1087-1106) and `checkItem {actionType, checklistName,
  checkItemName}` (lookup by exact checklist title then exact item title;
  L1042-1050). `checkItem` does NOT run `substituteVars` on its names — keep
  literals (ours are).

**SUPERSEDED 2026-10-26** — the import JSON below reflects the 2026-10-25
item sets; the current sets (Research uppercased + `None`, Model(s) default
Qwen Flash only, Research default Agent Decides, HITL default Plan, Human
in the Loop checklist) live in `board-rules-v12.64.json` beside this file —
import THAT file. The shape/semantics findings below still apply.

**Exact rule for the AI-Dev board** (import JSON; the board's current live
item sets are copied verbatim from `dev-boards list_rules` 2026-10-25):

```json
[{
  "title": "Std checklists + Model(s) defaults (Qwen Flash, Local)",
  "trigger": {"activityType": "createCard"},
  "action":  {"actionType": "addChecklistWithItems",
              "checklistName": "Model(s)",
              "checklistItems": "Qwen Large,Qwen 27b,Qwen Flash,Local (gpu-ai)"},
  "extraActions": [
    {"actionType": "checkItem", "checklistName": "Model(s)", "checkItemName": "Qwen Flash"},
    {"actionType": "checkItem", "checklistName": "Model(s)", "checkItemName": "Local (gpu-ai)"},
    {"actionType": "addChecklistWithItems", "checklistName": "Services",
     "checklistItems": "backups,dev,gpu,gpu-ai,grow,home,infra,media,monitoring,personal,proxy-backup,proxy-local,proxy-remote,home-assistant,agent context"},
    {"actionType": "addChecklistWithItems", "checklistName": "Type",
     "checklistItems": "feat,bug,debug,dep,refactor,chore,docs"},
    {"actionType": "addChecklistWithItems", "checklistName": "Research",
     "checklistItems": "before planning,after planning,agent decides"}
  ]
}]
```

Primary + 5 extras = 6 actions (≤ 10 cap). The two `checkItem`s are positions
2-3, immediately after the Model(s) checklist (+its items) is awaited by the
primary — deterministic for UI- and REST-created cards alike ([X1] §Q4
semantics, now confirmed at the v12.64 tag). Omitted trigger matchers are
fine: the importer defaults all `TRIGGER_MATCHING_FIELDS` to `'*'`
(`client/components/rules/rulesImportExport.js` L43-60, the #6472 fix —
without every field present as `'*'` the server's `$in` matcher could never
match, so hand-written JSON MUST import through this path or through REST
(normalization exists there too). Ordering = array order; `rules.addPart`
`$push`es IDs, so extras keep the exact sequence.

**Creation paths (extras are DDP/UI-only — REST can't):**
- UI wizard: board → hamburger → **Rules** (board admin) → add rule with
  trigger *card created* + first action (Model(s) checklist); then open the
  rule and use **“Add another action”** repeatedly — each save calls
  `rules.addPart` in order (`rulesSaveHelper.js` L6-26, `rulesMain.js` L154).
  Manual, tedious, 6 steps — use only as a fallback.
- **Rules → Import JSON** (same popup: Export JSON / Export CSV / Import JSON /
  Import CSV, plus Trello/n8n/Node-RED best-effort parsers in v12.64): paste
  the array above → each entry goes through `Meteor.call('rules.createRule')`
  + chained `rules.addPart` (rulesImportExport.js L61-92). Both methods
  require `board.hasAdmin(this.userId)` (`server/rulesButton.js` L72-82,
  L286). **Import is reproducible**: Export JSON round-trips extras —
  `collectBoardRules` embeds `extraTriggers`/`extraActions` (L22-36) and the
  exported form (minus `_id/boardId/timestamps`) re-imports cleanly. The
  exported file is the board automation's source of truth; check it into the
  ticket folder.
- Not via REST / not via wekan-mcp `create_rule`: single-action only (§Q3). An
  upstream feature-request candidate (adjacent, matches [X1]).

`enabled`: new schema field (`models/rules.js` L101) + REST PUT support —
defaults to enabled; skipped by the engine when `enabled === false`
(`rulesHelper.js` L568). A paused rule keeps its parts — the right instrument
for future maintenance windows.

## Q5 — Cutover runbook (ordered)

**Phase 0 — before anything touches the cluster (still v9.99):**

1. `U` = **user-owned**, no repo MCP grants it: backup dump —
   `kubectl -n default exec home-mongodb-0 -- mongodump --db wekan --out /tmp/dump-$(date +%F)`
   then copy out: `kubectl -n default cp home-mongodb-0:/tmp/dump-<date> .`
   (presented as commands; AGENTS forbids agent pod-exec). Verify a
   `mongorestore --dryRun`-equivalent listing (`mongodump … && ls`).
2. Board automation snapshot: on the board, Rules → **Export JSON** (exists on
   v9.99 too — `rulesImportExport.js` verified in the v9.99 tree) → save to
   the ticket folder as `board-rules-v9.99.json`.
3. **Promote the wekan-mcp service account to board admin** on AI-Dev
   (Members → role) — otherwise every MCP rule write 401s post-upgrade.
4. Decide the DB-retention strategy and pre-annotate (recommended minimal):
   user patches the two DB objects so a future pruned sync can never delete
   the data plane —
   `kubectl -n default annotate statefulset/home-mongodb service/home-mongodb argocd.argoproj.io/sync-options=Prune=false`
   (SSA caveat: annotation via `kubectl patch`). Alternatives: (B) add
   `mongodb` groundhog2k 0.7.6 as a direct dependency of
   `services/home/prod/Chart.yaml` reproducing the effective 9.99-chart values
   (`image.tag: 7.0.34`, storage 2Gi) so the STS stays IN the manifest —
   verify render-equality with `helm template` first; (C) chart-sanctioned
   FerretDB migration: let the app create its FerretDB, `mongodump` →
   `mongorestore` into it, drop `home-mongodb` — most aligned with upstream
   direction but biggest lift (single-writer SQLite FerretDB, `:latest`-tag
   image would want digest-pinning here). Runbook below assumes (A)+keep-Mongo,
   the smallest change; B/C stay open as user decisions.

**Phase 1 — upgrade (GitOps):**

5. PR: `Chart.yaml` both wekan deps → `12.64.0`; `Chart.lock` regenerated;
   `values.yaml`: delete the two `mongodb:` blocks, add `ferretdb: {enabled:
   false}` to BOTH `wekan:` and `boards:` blocks; everything else untouched.
   Validate locally: `helm dependency update services/home/prod && helm
   template services/home/prod` — assert: no `ferretdb`/`mongodb` objects
   rendered, `home-mongodb` NOT in output (expected — Phase-0 annotation is
   what protects it in-cluster), both wekan containers env
   `WITH_API=true`, `MONGO_URL=mongodb://home-mongodb:27017` (secret), probes
   unchanged.
6. Merge + ArgoCD sync app `home` (manual sync, no auto-prune configured —
   verify again at sync time the resource diff lists NO deletions of
   home-mongodb objects). Pods roll: boot logs show the schema-upgrade recheck
   pass; the boards frontend shares the same DB, both come up within a couple
   of minutes. WeKan reachable at both URLs.
7. Smoke (§Q6 V1).

**Phase 2 — rule cutover (board mutations; user go per D5; pause
`agent-board-coord` card creation first — no other agent should be creating
cards in this window):**

8. Import the merged rule (§Q4 JSON) via Rules → Import JSON as a board-admin
   human. The four Std rules still exist for the moment — a card created in
   this ~1-minute window would get duplicate checklists; hence the pause.
9. `list_rules` to confirm the new rule exists and its `_id`; then delete the
   nine superseded rules: Std×4 (`KyhZnoxhKs6nBSiBX`, `NKqcv5hmatKtumtby`,
   `jN9SzDtuyGaNRP43F`, `SCCBtZR928JuMAQBh`), EXP1×2 (`83nHaNGLCw6acBgHH`,
   `HetrcQWy5aEF3NXso`), EXP2×2 (`SBzh8tmdW35p59fxo`, `NFHadZs7XZcJsmS27`),
   RACE-TEST (`4mXDQz3SGXAmXZyrY`). **Keep** `pLeNsHmFzFrnY3yJx`
   (moveCard→addLabel — still valid, unaffected). [X1]'s sequencing lesson
   applies in reverse: land the replacement BEFORE removing the old ones, and
   only then create test cards.
10. Post-cutover export: Rules → Export JSON → `board-rules-v12.64.json` into
    the ticket folder (repo becomes the source of truth for re-creation).
11. Verify (§Q6 V3/V4). Then resume `agent-board-coord`.

**Rollback plan:**
- Rule layer: delete the merged rule, re-Import `board-rules-v9.99.json`
  (works on v12 too — single-action rules are unaffected: extras-less rules
  run the primary action exactly as on v9.99). The Design-H belt (MCP
  `create_card default_checked`) keeps working throughout, so the agent path
  never depends on the rollback finishing instantly.
- App layer: revert the PR and re-sync (image back to v9.99). Downgrade data
  impact is minimal: extra Action docs are inert on v9.99 (its
  `findMatchingRules` ignores triggers not pointed at by a rule's `triggerId`;
  our merged rule has NO extra triggers, only extra actions, and v9.99
  dispatch reads only `rule.getAction()`); the additive backfill fields are
  already part of v9.99 schemas. Any new v12 collections (rule history,
  active-login-tokens, security-log/canary) are simply ignored by v9.99.
- Catastrophic (DB damaged): `mongorestore` the Phase-0 dump into a rebuilt
  `home-mongodb` (user-run). PVC survives a deleted STS (StatefulSet
  claimTemplates aren't garbage-collected by default) and Argo didn't track
  the PVC (no tracking-id on controller-created claims), so even the worst
  documented failure mode leaves the data intact.

## Q6 — Verification plan

1. **V1 post-upgrade smoke (read-only):** ghcr pull + pod Ready;
   `dev-boards validate` path = list_boards/get_board round-trip through MCP;
   login 200 with token (throttle untouched); `GET /api/boards/:b/rules` with
   the bot token still 200 (member read unchanged); boot log shows the
   schema-upgrade pass without errors; existing boards visible to a human over
   OIDC (both URLs).
2. **V2 merged-rule red:** after import but before deleting old rules, one
   disposable card (`DISPOSABLE-v12-import`, delete after) via REST (MCP
   `create_card` WITHOUT `default_checked`) → expect FOUR checklists
   duplicated by the co-existing old rules (this proves the new rule fired —
   the Model(s) one arriving twice with both copies' items unchecked) —
   messy by design; the old rules go immediately after; do V2 as a *combined*
   step: create, delete the nine old rules, then create V3 cards.
   (If a clean pre-delete proof is wanted instead, `update_rule enabled:false`
   via raw REST/curl with the admin token first pauses the new rule.)
3. **V3 determinism, REST path:** create 5 disposable cards back-to-back via
   MCP `create_card` (no `default_checked`), sleep ~3 s, then per card
   `list_checklists` + `get_checklist Model(s)`: ALL five arrive with exactly
   one of each of the four checklists and both defaults checked. Repeat once
   **after the order-flip experiment** from [X1]: add 5 junk `createCard`
   rules (e.g. setColor variants), re-run the 5-card batch, assert identical
   results, delete the junk. Cross-rule cursor order is still unspecified on
   v12.64 (§Q4), so the only contract is *within-rule* — the junk rules prove
   our single rule's outcome is order-independent.
4. **V4 UI path (human):** create a card in the UI in Not Started → same
   assertions (checked-on-arrival, no first move needed — closing the v9.99
   "never-moved UI card" gap [X1]). Then move it once → still exactly the two
   defaults checked (no rule re-fire artifacts); auto-label rule still works
   when dragged into Research.
5. **V5 belt regression:** MCP `create_card` WITH `default_checked` (the
   current agent flow) → returns fast, `defaults_pending` absent,
   first poll resolves immediately (rule already landed) — confirming the
   hybrid keeps working during the cutover window.
6. **V6 visibility audit:** raw `GET /api/boards/:b/rules/:id` (admin curl or
   browser devtools) shows `extraActions` in order; `dev-boards get_rule`
   shows ONLY the primary action (expected, §Q3 flag 2) — do not trust MCP
   for post-cutover rule state until the `_slim_rule` patch lands.
7. Cleanup: user deletes DISPOSABLE cards; friction log any 429/throttle
   surprises.

## Risks

- **Mongo pruning (top risk):** chart 10.86+ renders no MongoDB; the live
  `home-mongodb` STS/Service become extraneous to app `home`'s desired state.
  Today's app has no automated sync/prune, so the bump itself shouldn't delete
  them — but a later `--prune`/automation-enable would. Phase-0 annotations
  (or dependency re-hosting) are mandatory before trusting the state; verify
  the Argo diff at sync time shows no deletions.
- **Two frontends, one DB:** both deployments roll to v12.64 together; a
  half-upgrade (one pod v9.99, one v12.64) is transient but keep the sync
  atomic (one umbrella app does this).
- **Bot-admin promotion forgotten** → MCP rule writes 401 after upgrade
  (breaks any rule-maintenance automation, not board operation itself).
- **Duplicate-checklist window** during cutover if card creation isn't paused
  (mitigated by the sequence + pause).
- **Item-title drift:** the merged rule's `checklistItems` strings are the
  live strings incl. the trailing-space item `agent context` in Services;
  `checkItem` matching is exact-title — if the runbook/boards-skill item sets
  drift (§Adjacent, [X1]), update BOTH the rule JSON and the boards skill in
  one change.
- Login throttling: a misconfigured MCP password now yields 429 + 60 s
  lockouts (mildly noisier failure, bounded).
- `ferretdb` image `ghcr.io/wekan/ferretdb:latest` with `pullPolicy: Always`
  (only relevant if option C is taken — floating tag should be digest-pinned
  per repo norms).
- v12.64 is 24 h old (published 2026-10-24) and its own message is a
  conformance-test release — low churn risk, but pin 12.64 (not a moving
  `main`/`:latest`) and expect the next bump to be independent.

## Contradictions / corrections

- The launch brief's "ruleParts … in executeRulesAtDepth" matches the code
  except that the persisted form is `extraTriggerIds`/`extraActionIds` **ID
  arrays**, with the human-friendly `trigger/action/extraActions` object shape
  existing only in the import/export JSON layer — plan wording should use both
  names precisely (docs elsewhere call the object form ruleParts loosely).
- [X1]'s "v12.64 REST rule writes require board admin" — confirmed at the tag
  itself; and we now pin the exact line numbers (rules.js L156/212/257).
- Chart values claim ("the MongoDB StatefulSet and its PVC are left exactly as
  they are when you upgrade") is about the PVC/data, and is **true only
  because our DB runs under Argo without auto-prune**; read as a general
  Helm-safety statement it is wrong (Helm/Argo prune removed resources from a
  manifest). Weigh: follow Phase 0 anyway.
- The stale service label `app.kubernetes.io/version=8.0.16` on home-mongodb
  vs the pod's actual `mongo:7.0.34` — label is subchart metadata, image wins.

## Implications for the plan

- Chunk the work as: (1) Phase-0 user steps (dump, export, bot→admin,
  Prune=false annotations) — all user-owned per D5; (2) repo PR (Chart.yaml ×2
  deps + Chart.lock + values: `mongodb:` removal, `ferretdb.enabled:false` ×2)
  with `helm dependency update`/`template` validation asserts; (3) sync + V1
  smoke; (4) rule import + retire-9 + V2-V6; (5) repo docs: replace the
  v9.99-rule-cluster sections of the boards skill / wekan-mcp-ops reference
  with the merged rule + v12 semantics, commit `board-rules-v12.64.json`;
  (6, separate ticket) wekan-mcp `_slim_rule` extras passthrough +
  `update_rule enabled` param → new image tag.
- The user's infra decision (A keep-Mongo+annotate vs B re-host dependency vs
  C FerretDB migration) gates chunk 2's exact values edits — get it explicitly.
- Do NOT also plan an MCP `create_rule`-based rule sync: REST can't manage
  extras; the board JSON + repo file is the reproducible artifact.
- Keep Design H's `default_checked` tool path (belt-and-braces) through the
  cutover window; optional to retire later, zero cost to keep ([X1] §Q5).

## Adjacent findings

- Upstream issue candidates (in addition to [X1]'s trigger-naming bug): the
  chart values-comment's blanket "nothing deletes it" about removed subchart
  DBs (prune nuance above); ghcr.io/wekan/ferretdb `:latest` default tag in a
  chart claiming "the tag deliberately tracks each release".
- v12.64 adds: `dispatchBot` action + board Bots page (future pipeline-trigger
  direction instead of card polling), rule history (`withRuleHistory` — every
  REST/DDP rule change recorded), inbound-email routes, passwordless
  admin endpoints, cron-expression scheduled triggers, Trello/n8n/Node-RED
  rule import parsers (a Wrike-import DDP method too — `rulesButton.js` L145).
- The live Services/Research item sets already drifted from the runbook table
  ([X1] §Adjacent) — the merged rule JSON above bakes in the CURRENT live
  strings; reconcile the runbook to it.

## Sources (all read 2026-10-25)

- [S1] wekan@v12.64 source tarball — local `/tmp/opencode/wekan-v12/wekan-12.64`
  (codeload). Cited: `server/models/rules.js`, `server/models/cards.js`,
  `server/models/checklistItems.js`, `server/models/checklists.js`,
  `server/models/customFields.js`, `server/apiAuthRoutes.js`,
  `server/apiMiddleware.js`, `server/rulesHelper.js`, `server/rulesButton.js`,
  `server/triggersDef.js`, `server/lib/schemaUpgradeSteps.js`,
  `server/startupSchemaUpgrade.js`, `server/lib/adminOnlyCustomFields.js`,
  `server/lib/loginAttemptThrottle.js`, `models/rules.js`,
  `models/lib/ruleParts.js`, `models/lib/adminOnlyCustomFields.js`,
  `client/components/rules/rulesImportExport.js`,
  `client/components/rules/rulesSaveHelper.js`,
  `client/components/rules/rulesMain.js`, `imports/reactiveCache.js`,
  `.meteor/release`, `Dockerfile`, `docker-compose-mongodb-v7.yml`,
  `docs/Databases/Supported.md`, `docs/Backup/Backup.md`,
  `docs/Features/Rules/{Bots,Rule-Suggestions,Rules/Rules}.md`, `CHANGELOG.md`.
- [S2] wekan@v9.99 source tarball — `wekan-9.99` (same tree for diffs; route
  extraction both versions: 117 vs 149, zero removals).
- [S3] Helm index `https://wekan.github.io/charts/index.yaml` (374 versions;
  `wekan-9.99.0.tgz` + `wekan-12.64.0.tgz` fetched and compared:
  Chart.yaml/lock, values.yaml incl. ferretdb/externalDatabase sections,
  `deployment.yaml` #6289 guard, `_helpers.tpl` `mongodb.url` + ferretdb
  fullname, `secret.yaml`, `data-pvc.yaml`, NOTES.txt).
- [S4] GitHub API: release `v12.64` (published 2026-10-24, body). ghcr tag
  existence corroborated by chart annotation `artifacthub.io/images` + [X1]'s
  ghcr probe.
- [S5] wekan.fi/upgrade page (general upgrade steps, Bitnami note,
  mongodump/groundhog2k #45 pointer).
- [S6] This repo: `services/home/prod/{Chart.yaml,Chart.lock,values.yaml,templates/secret-wekan-sso.yaml}`,
  `custom-values/home/prod-values.yaml`, `services/gpu/prod/values.yaml`
  (wekan-mcp tiers), `services/dev/prod/values.yaml` (dev-boards),
  `renovate.json` L190-220, `containers/wekan-mcp/wekan_mcp/{server.py,wekan.py}`
  (current tool surface incl. the already-implemented `default_checked`).
- [S7] Live cluster (`readonly-home-kubernetes`): deployments home-wekan /
  home-boards (image ghcr.io/wekan/wekan:v9.99), service/statefulset/pod
  home-mongodb (mongo:7.0.34), PVCs, Application `home` (syncPolicy,
  SSA option, Synced/Healthy), pod home-mongodb-0 spec.
- [S8] Live board `TNQJ2BrXenZovngTS` (`dev-boards` read-only): full 10-rule
  inventory with exact trigger/action bodies + rule IDs; custom fields
  slug/session (text, no adminOnly).
- [X1] Sibling `2026-10-feat-board-coord-intake/RESEARCH.md` — v9.99 race
  forensics, Design H, verification ladder; terminology inherited.

## Reliability notes (peer review)

- Route surface preserved / MCP-compat — **10/10** (exhaustive regex extraction
  on both tags + per-route confirmation; residual: non-route changes like
  response-body redaction checked per-route where relevant).
- Single-step upgrade safe (app+DB) — **8/10** (all evidence primary;
  untested here: the actual first-boot migration pass on our data — V1 covers;
  and 12.64 is one day old).
- home-mongodb prune-risk characterization — **9/10** (chart/manifest logic
  certain; the "Argo won't auto-prune" leg rests on today's observed app spec
  — re-verify at sync time).
- Merged rule deterministic for both paths — **9/10** (ordering code read at
  the tag; import chain read; live proof = V3/V4; residual: exact
  `performAction` card-resolution on createCard activities assumed proven by
  the currently-working Std rules, unchanged code path).
- Import JSON shape — **9/10** (field names + normalization + ID-array
  mechanics all read in source; not executed live — read-only mandate; V2/V3
  close it).
- Weakest claim: rollback "extra action docs inert on v9.99" — **7/10**:
  reasoned from v9.99's `getAction`/trigger-lookup code, not tested; a
  downgrade rehearsal on a restored dump would settle it.

```
RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-10-dep-wekan-v12-upgrade/RESEARCH.md]
commands_run: [wekan v9.99+v12.64 tarballs (codeload) + source forensics => pass; REST route extraction/diff both tags => pass; helm index + chart 9.99.0/12.64.0 download & diff => pass; GitHub release probe v12.64 => pass; dev-boards list_rules/list_custom_fields/get_custom_field read-only => pass; readonly-home-kubernetes deployments/statefulset/pod/PVC/Application inspection => pass; live-board mutations => NOT RUN (read-only mandate); cluster mutations => NOT RUN]
deviations: STORM interviews realized as primary-source forensics (deployed tags + chart + live inspection), matching the sibling [X1] precedent for this topic class; no board/cluster mutations; runbook presents user-owned steps (dump, admin promotion, Prune=false annotations, rule import) rather than executing them.
friction: readonly-home-kubernetes resources_get returns the object at top level (not under .body) and resources_list items are pre-slimmed (Images/Labels keys) — first parses failed; dev-boards _slim_rule hides extraActions by design, so the live extras inventory must come from raw REST post-upgrade (documented as V6); home-mongodb service label claims 8.0.16 while the pod runs mongo:7.0.34 (stale subchart metadata — image treated as authoritative).
open_questions: (1) user's DB-retention choice A(annotate Prune=false + external) / B(re-host groundhog2k dependency) / C(migrate to chart FerretDB via dump/restore) — gates the exact values edits; (2) confirm the wekan-mcp service account will be promoted to board admin on AI-Dev before the cutover (D5 mutation go); (3) schedule of the card-creation pause window for Phase 2 (coord to sequence with agent-board-coord); (4) should the _slim_rule/update_rule MCP patches ride this ticket or their own chunk/ticket.
next_suggested: agent-plan folds §Q5 into chunks (Phase-0 user steps → repo PR + helm template asserts → sync + V1 → rule import + retire-9 + V2-V6 → docs/skill update + board-rules JSON committed), with the user's A/B/C decision taken first.
```
