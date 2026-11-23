# EXPLORE (wekan-mcp surface) — cf-140 agent-card-reconcile

Scout grounding for: (1) where a `format: json|yaml` output argument slots into
`containers/wekan-mcp`, (2) what the **deployed** WeKan board supports for
card change detection. Method: repo reads (grep/sed) + read-only probes of the
pinned upstream source at tag **v12.99** (raw.githubusercontent, the exact
version the repo deploys — see §5). Every claim is tagged with its evidence
class:

- **[repo]** — read from this worktree
- **[up12.99]** — read from `wekan/wekan` at tag `v12.99` (fetched 2026-11-23)
- **[doc]** — repo skill/AGENTS documentation; where the doc's own pin is
  older than v12.99 it is flagged (the skill refs anchor on v12.65 / v9.99)

The repo's WeKan chart pin is `12.99.0` **[repo: services/home/prod/Chart.yaml
L39-48, two entries, the second aliased `boards`; Chart.lock generated
2026-11-21]**. Skill docs that were not re-verified against v12.99 are marked
`[doc, pin-lag]`.

## 1. wekan-mcp tool surface [repo: containers/wekan-mcp/]

### 1.1 Registration mechanism

- `server.py` (1798 lines): `mcp = FastMCP("wekan")`; each tool is a plain
  `def` under `@mcp.tool` (18 read tools) or `@_write_tool` (21 write tools).
- The write gate is one line (L76):
  `_write_tool = (lambda fn: fn) if READ_ONLY else mcp.tool` — i.e. in
  `WEKAN_MCP_READ_ONLY` mode the 21 write tools are **defined but never
  registered** (they vanish from the MCP catalog); the 18 read tools are always
  registered. `READ_ONLY` parses L53: `os.environ.get("WEKAN_MCP_READ_ONLY",
  "").strip().lower()` in a truthy set.
- `preload_board` is `@mcp.tool` (L1507) — a read tool, always registered, even
  in READ_ONLY mode. (It is a single GET of the board export, §4.2.)
- Auth/client: `wekan.py` `WekanClient` — base URL from `WEKAN_BASE_URL`,
  bearer from `WEKAN_TOKEN` or minted once via `WEKAN_USERNAME`/`WEKAN_PASSWORD`
  login; a 401 re-mints the token exactly once; a **200 response with an
  embedded error body is detected** (`_embedded_error`, L1036) and raised as
  `WekanError` — several read tools guard for it explicitly.
- Packaging: `pyproject.toml` deps are **only** `fastmcp>=4.1,<5` and
  `httpx>=0.27,<1` (L8-11). `Dockerfile`: `FROM python:3.15-slim`,
  `pip install .`, non-root uid 65532, ENTRYPOINT console script `wekan-mcp`.
  `README.md` still documents the fastmcp pin as `>=3.4,<4` — stale vs
  pyproject.

### 1.2 Tool inventory (39 = 18 read + 21 write)

Read tools (all `@mcp.tool`, signature exact):

| tool | signature | response shape |
|---|---|---|
| `list_boards` | `() -> list[dict]` | `[{id, title}]` only (endpoint returns pairs; nothing else fetched) |
| `get_board` | `(board_id: str) -> dict` | `_slim_board`: `{id, title, key, permission, color, archived, labels: [{id, name, color}]}` |
| `list_lists` | `(board_id: str) -> list[dict]` | `{id, title, swimlane_id}`; collection endpoint hard-projects `{_id, title}` so `swimlane_id` is hydrated per-list from the single-list endpoint (degrades to `null` on failure, log warning) |
| `list_swimlanes` | `(board_id: str) -> list[dict]` | `{id, title}` |
| `list_cards_in_list` | `(board_id, list_id: str) -> list[dict]` | `_slim_card`, **but the by-list projection strips** `cardNumber`/`customFields`/`labelIds`/`cardDependencies`/`parentId`/`listId` → `card_number: null`, `custom_fields/label_ids/card_dependencies: []`, `parent_id: null` (documented in docstring) |
| `get_card` | `(board_id, card_id: str) -> dict` | `_slim_card` from `GET /api/cards/:cardId` (full document: `card_number`, `custom_fields: [{id, value}]`, `card_dependencies`, `parent_id` all ride); **returns archived cards too** — check `archived`. No `/api/boards/:b/cards/:c` route exists; board access is enforced server-side via the card's own `boardId` |
| `get_card_details` | `(board_id, card_id: str) -> dict` | one-call claim-card shape: `{id, card_number, title, description, list_id, swimlane_id, archived, sort, parent_id, label_ids, labels: {id→name}, custom_fields: {name→value}, slug_stack: [...oldest first], current_slug, checklists: [{id, title, items: [{title, finished}]}], dependencies: [{to_id, type, color}]}`. Several REST reads (card + board + fields + per-checklist); a non-card answer or a failed checklist-items read **fails the call** (an empty details payload must not be readable as an empty card); slug field resolved **by name** `slug`, not id |
| `list_comments` | `(board_id, card_id: str) -> list[dict]` | `_slim_comment`: `{id, comment, author_id, created_at}` |
| `list_checklists` | `(board_id, card_id: str) -> list[dict]` | `[{id, title}]` (headers only) |
| `get_checklist` | `(board_id, card_id, checklist_id: str) -> dict` | `{id, title, items: [{id, title, finished}]}` — item ids required by `toggle_checklist_item` |
| `list_rules` | `(board_id: str) -> list[dict]` | `_slim_rule`: `{id, title, trigger, action, extra_actions, extra_triggers, enabled (default true)}` — trigger/action embedded inline |
| `get_rule` | `(board_id, rule_id: str) -> dict` | same `_slim_rule` shape, one rule |
| `list_custom_fields` | `(board_id: str) -> list[dict]` | `[{id, name, type}]` only (board-level route projects to that trio; [doc, pin-lag: v9.99 note]) |
| `get_custom_field` | `(board_id, custom_field_id: str) -> dict` | `{id, name, type, settings, show_on_card, automatically_on_card, always_on_card}`; `type` ∈ text, number, date, dropdown, checkbox, currency, stringtemplate; dropdown options in `settings.dropdownItems`; `always_on_card` is read-only through this server |
| `list_board_members` | `(board_id: str) -> dict` | `{board_id, title, members: [{user_id, username: null, is_admin, is_active, is_no_comments, is_comment_only, is_worker, is_normal_assigned_only, is_comment_only_assigned_only→(spelling per wire list), is_read_only, is_read_assigned_only}], username_resolution: <note>}` — usernames ride only site-admin-gated routes; the service user is not site admin, so `username: null` + the note is the documented shape (not a silent null) |
| `list_board_dependencies` | `(board_id: str) -> list[dict]` | upstream shape passed through: `[{from, fromTitle, fromCardNumber, to, toTitle, toCardNumber, type, color, icon}]` — **no synthesized inverse**; archived cards excluded upstream |
| `list_card_dependencies` | `(board_id, card_id: str) -> list[dict]` | stored `cardDependencies` passed through: `[{cardId, type, color, icon}]`; `cardId` is the **target** card id; only this card's own edges |
| `preload_board` | `(board_id: str, swimlane_titles: Optional[list[str]] = None, with_checklists: bool = True) -> dict` | **one GET of the board export** with `attachments=false` and a `fields=` trim (vocabulary per upstream `models/lib/exportFields.js`). `{board_id, swimlanes: [{id, title, lists: [{id, title, cards: [<8-key map>]}]}], dependencies: [{from_id, to_id, type, color, icon}], label_names: {id→name}, field_names: {id→name}}`. Each card is **exactly eight keys**: `id, card_number, label_ids, slug, archived, sort, parent_id, checklists` (titles/descriptions deliberately not carried). `checklists` filtered to the kickoff vocabulary (5 standard + legacy `Research`-for-Lifecycle, legacy Lifecycle recognized by item count). `with_checklists=False` **drops the key** (never `[]`). `swimlane_titles=None` = all swimlanes; a filter miss answers empty grouping, not an exception; a non-board-document export answer fails the call. Orphan cards (undeclared parent list) ride a tail group with `swimlane id: None, title: None` — only on the unfiltered read |

Write tools (21, all `@_write_tool`, L578-1728): `create_card` (with the
`default_checked` bounded-poll dance — `_DEFAULT_CHECKED_POLL_ATTEMPTS = 25` ×
0.4 s — because v9.99 rule-cascade checklists land after the create response
flushes), `update_card`, `move_card`, `create_list`, `add_comment`,
`add_checklist`, `toggle_checklist_item`, `add_checklist_item`,
`delete_checklist_item`, `create_rule`, `update_rule`, `remove_rule`,
`create_custom_field`, `set_card_custom_field`, `update_board`, `create_swimlane`,
`create_label`, `add_card_dependency`, `edit_card_dependency`,
`remove_card_dependency`, `set_card_labels`.

### 1.3 Where `format: json|yaml` slots in

1. **Per-tool argument** (the natural slot): each of the 18 read tools gains
   `format: str = "json"` in its `def` signature. FastMCP builds the tool
   schema from the typed signature, so the argument is self-documenting in the
   MCP catalog; validate `format in ("json", "yaml")` and raise `WekanError`
   otherwise (the established error path).
2. **Shared serializer**: the tools already funnel through `_slim_*` shapers
   (L79-163) returning plain dicts — a single `_serialize(obj, format)` helper
   (json: existing path; yaml: `yaml.safe_dump`) at each return site is the
   minimal change; no shaper changes.
3. **Dependency**: add `pyyaml` to `pyproject.toml` `dependencies` (L8) — that
   is the only insertion point; the `Dockerfile` needs no change because it
   `pip install .`s (pyproject is read at build). `python:3.15-slim` has no
   stdlib `yaml` module. Grep evidence [repo]: no `import yaml`/`pyyaml`
   anywhere under `containers/` yet — this would be the repo's first YAML
   dependency.
4. **Repo YAML-machinery context** (all of it is hand-rolled, no YAML lib):
   - `.opencode/plugin/board-context/index.ts` `formatBlock()` **emits** a
     strict YAML document by string construction (JSON-stringified scalars for
     quoting; `cards: []` vs block; `#`-comment footer) — it never parses YAML.
   - `tests/agent-board-coord/gate.sh` extracts YAML frontmatter with a
     **regex** (`re.match(r"^---\n(.*?)\n---\n")`), not a YAML parser.
   - No `yaml`/`js-yaml` import in `scripts/` or the other plugins.
   Implication: `pyyaml` in wekan-mcp is the first real YAML serializer in the
   repo; there is no in-repo precedent to copy, and no existing consumer to
   stay byte-compatible with (the board-context block schema is declared in the
   wekan-mcp skill, but that block is emitted by the plugin, not wekan-mcp).
5. **Deploy path** (unchanged by the format arg): image pinned
   `ghcr.io/ownyourio/wekan-mcp:v162` in **both** dev and gpu values; agent
   sessions have no docker daemon, so the chunk's build gate is the Forgejo
   `containers-build.yaml` on the pushed branch (CI-primary per repo ruling
   cf-77: `docker build => no-daemon, CI-deferred` is the designed passing
   shape); the values pins bump via the Renovate-managed follow-up, and the
   ToolHive server pod (`mcp-boards-0`) must pick the new image
   (`imagePullPolicy: Always`).

## 2. Deployment wiring [repo]

- **dev-boards** (the board MCP this ticket talks to):
  `services/dev/prod/values.yaml` L464-498 `hivetools.mcp.boards` — image
  `ghcr.io/ownyourio/wekan-mcp:v162`, `mcpPort 8080`, streamable-http, OIDC
  block commented out, `envFrom` secret `wekan-mcp` (Bitwarden LOGIN item,
  `bitwardenIds.wekan-mcp`; L67-70), `imagePullPolicy: Always`; ingress
  `https://mcp.dev.scifi.farm/boards/mcp` (client entry
  `.opencode/opencode.jsonc` L75-83, 60 s catalog/execution timeouts). ToolHive
  runs it as a StatefulSet server pod + proxyrunner pod.
- **gpu tiers**: `services/gpu/prod/values.yaml` L732-800 — `wekan-readonly`
  and `wekan-admin`, same `:v162` image, `WEKAN_BASE_URL=https://wekan.spencerslab.com`,
  shared `WEKAN_TOKEN` secret; `WEKAN_MCP_READ_ONLY` on the readonly tier.
  `charts/hivetools/` holds the MCPServer/ingress/OIDC templates.
- **WeKan itself**: `services/home/prod/values.yaml` L267-367 — two WeKan
  instances (one per URL), one shared MongoDB, `WITH_API=true`.

## 3. Board/flow ids reused by repo flows [repo]

- AI-Dev board id **`TNQJ2BrXenZovngTS`** (board key `AD`) — live since
  2026-10-25; appears in `.agents/plans/2026/2026-10-dep-wekan-v12-upgrade/
  RESEARCH.md` [S8], `tests/wekan-board-provision/fixtures/`, and
  `tests/opencode/board-context.test.ts`.
- `tests/wekan-board-provision/fixtures/ai-dev-live-2026-10-31.json`
  (`schema: wekan-board-snapshot/1`, `collected_at: 2026-10-31`): swimlane
  map `In Process = jLzy39L7djCRr67SF` (real id); `Backlog`/`Farm`/`Planning`
  are `…FIXTUREID…` placeholders; label keys `Research, Ready for Work,
  Pipeline: Local, Pipeline: CICD, Pipeline: Context, Bucket Color`.
- Custom fields are resolved **by name at runtime** (`slug`, `session`,
  `Priority`) — `scripts/provision-board.py` and
  `scripts/board-checklist-backfill.py` use name→id snapshot maps; no hardcoded
  field ids in repo scripts. `scripts/board-preload-probe.sh` carries
  `PICKUP_LISTS=("Not Started" "Rework" "Low Priority")` + the In Process
  swimlane and the payload-shape legs.
- `board-checklist-backfill.py` consumes the board-export contract
  (`wekan-board-export/1`) — the same `?fields=` vocabulary verified in
  §4.2, so the export surface the backfill already leans on is proven live.

## 4. Change detection on the DEPLOYED board (v12.99) [up12.99, ranked]

**Hard fact first: there is no per-card activity REST endpoint in v12.99.**
Evidence: the complete `WebApp.handlers` inventory in
`server/models/cards.js` (listings, single-card GET/PUT/POST, bulk delete,
labels, counts, `/api/user/cards` …) contains no `/activities` route, and
`server/models/boards.js` registers no activities route either. The skills'
`rest-api-overview.md` [doc] agrees (no per-card activity endpoint listed).

Ranked by what the deployed board actually supports:

### Option A — snapshot-diff the card document (works regardless of write path)
- `GET /api/cards/:cardId` returns the **full card document** wrapped by
  `cardWithChecklists` (`server/lib/checklistDeadlines.js`, v12.99):
  `return { ...card, checklists: [...] }` — so every stored card field rides,
  including `modifiedAt`, `createdAt`, `dateLastActivity`, `listEnteredAt`.
- Cost: one GET per card per poll (the `get_card`/`get_card_details` shape
  already exists in wekan-mcp). No WeKan-side feature required; immune to the
  gap in Option D below. This is the floor.

### Option B — webhook (integration) for event-driven detection
- All REST, verified in `server/models/integrations.js` v12.99:
  - `GET /api/boards/:boardId/integrations` (list)
  - `GET /api/boards/:boardId/integrations/:intId`
  - `POST /api/boards/:boardId/integrations` (body `url`; board-admin gated;
    SSRF-guarded against private/loopback/link-local destinations unless a site
    admin allow-lists them — GHSA-hc3x-hq3m-663q)
  - `PUT /api/boards/:boardId/integrations/:intId` (sets `enabled`, `title`,
    `url`, `token`, `notificationDelivery`, **`activities`** = array of
    activityType strings; wrong-board id answers 404 via `integrationOr404`)
  - `POST /api/boards/:boardId/integrations/:intId/activities` (`$addToSet`
    on the integration's `activities` array)
  - `DELETE /api/boards/:boardId/integrations/:intId/activities`
    (`$pullAll` — the delivered-activities log is managed through these two)
  - `DELETE /api/boards/:boardId/integrations/:intId`
- Delivery is `deliverActivityWebhook` (v12.99 `server/models/activities.js`
  startup section) with a rich param set: `userId`/`username`, `boardId`,
  `listId`/`oldListId`, `cardId`, `commentId`, `customFieldId`/`customField`/
  `customFieldValue`, `labelId`/`label`, `checklistId`, `checklistItemId`,
  `value`/`oldValue`, `timeKey`/`timeValue`/`timeOldValue`, `description` —
  the emitted field vocabulary is documented in `skills/wekan-api/
  references/webhook-data.md` [doc: `act-*` catalog; **no delivery guarantee —
  at-most-once posture, no retry/ack contract**].
- Requirements: board-admin rights + a URL reachable from the WeKan pod; the
  integration's `activities` array must enumerate the activityTypes you care
  about (card move/edit/comment/custom-field/label/checklist events).

### Option C — board export `?fields=activities` (the historical per-card log, one full-board fetch)
- Live REST route verified in v12.99 `models/export.js:80`:
  `GET /api/boards/:boardId/export` — reads `?attachments=false`, `?fields=`
  through `parseExportFields(..., BOARD_EXPORT_FIELD_KEYS)`, and `?` scope via
  `parseExportScope` (scope keys per `models/lib/exportFields.js`:
  swimlaneId/listId/cardId/checklistId); public boards export unauthenticated,
  private boards take `authToken` (Bearer) — plus `GET
  /api/boards/:boardId/export/<format>` and `exportZip`.
- `activities` **is** a valid `?fields=` section (`models/lib/exportFields.js`
  v12.99 `BOARD_EXPORT_FIELDS` alongside `board-header, labels, custom-fields,
  checklists, subtasks, comments, attachments, dependencies, sort`).
- Shape (v12.99 `models/exporter.js` L268-280): `result.activities =
  ReactiveCache.getActivities({ $or: [{ boardId }, { cardId: { $in: cardIds } }] })`
  — a **flat array of full Activity documents, not keyed per card**; each
  document carries its `cardId`, so per-card history means filtering/grouping
  client-side. Unselected sections come back as empty arrays (the same
  behavior `preload_board` already relies on). Activities collection has no
  schema (server-only, trusted) with indexes `{cardId, createdAt: -1}` and
  `{boardId, createdAt: -1}`.
- Cost: one full-board export per poll (mitigate with `fields=activities` +
  `attachments=false` + scope keys). Note the global "disable all exports"
  admin setting can refuse the route (`refuseDisabledExport`).

### Option D — the card's `modifiedAt` / `dateLastActivity` timestamps (NOT reliable for API-driven edits)
- v12.99 `models/cards.js` schema: `modifiedAt.autoValue()` fires on
  `isInsert || isUpsert || isUpdate`; `createdAt` on insert/upsert;
  `listEnteredAt` only on list entry (unrelated edits do not reset it);
  `dateLastActivity` autoValue is unconditional on document save.
- **But** the REST card-PUT handler (`server/models/cards.js`
  `WebApp.handlers.put('/api/boards/:boardId/lists/:listId/cards/:cardId')`)
  performs every write as `Cards.direct.updateAsync` — and the v12.99 source
  itself documents the consequence (L2124 comment): *"``.direct` skips the
  Cards.after.update hook…`"*; grep of the whole PUT region (L1790-2210) finds
  **zero** `modifiedAt` mentions, and the only explicit `modifiedAt:
  new Date()` stamps in the file live in the DDP `Meteor.methods` block
  (L535-828). Mongoose schema-level `auto` values do not apply to query-update
  operations, and the `Cards.before/after.update` hooks (L994-1339) are
  skipped by `.direct`.
- Net: `modifiedAt`/`dateLastActivity` bump on **UI (DDP) edits and card
  creation**, but **not on REST/mcp-driven card edits** — exactly the writes a
  reconcile loop performs. Use it only as a UI-activity hint, never as the
  change signal for API writes. (Live confirmation that the deployed pod
  matches v12.99 behavior is an open item — §6.)
- `showActivities` is a per-board flag on the card document; the card model
  also exposes an `activities()` helper (`ReactiveCache.getActivities({ cardId
  }, { sort: { createdAt: -1 } })`) — useful in-app only, no REST route.

**Ranking for "detect that a card changed since we last saw it":**
1. **A — snapshot-diff** (correct for every write path; zero WeKan features).
2. **B — webhook** (event-driven, rich per-activity payload, but needs an
   externally reachable lab endpoint + board-admin + activityType allow-list;
   at-most-once delivery).
3. **C — export `fields=activities`** (gives the full per-card history for a
   diff of "what changed and by whom", at full-board fetch cost).
4. **D — `modifiedAt`** (only if the board is edited through the UI).

## 5. Upstream pin & doc lag

- Anchor: deployed chart `12.99.0` [repo] ⇒ all [up12.99] claims above were
  read from tag `v12.99` on 2026-11-23 (files: `models/cards.js`,
  `server/models/cards.js`, `server/models/boards.js`,
  `server/models/integrations.js`, `models/export.js`, `models/exporter.js`,
  `models/lib/exportFields.js`, `models/activities.js`,
  `server/lib/checklistDeadlines.js`, `server/models/activities.js` delivery
  section).
- Path gotcha: the export-field vocabulary lives at top-level
  `models/lib/exportFields.js` — `server/models/exportFields.js` 404s.
- `[doc, pin-lag]` items (rely on the skill's older pin until re-verified):
  the `v12.65 route facts (source-checked 2026-10-30)` docstring in
  `list_board_members` and `v12.65` in `list_board_dependencies` (2026-11-01),
  the `v9.99` notes in `list_custom_fields` / `create_card` /
  `create_custom_field` — none of these were re-verified against v12.99 in
  this scout pass; they read as low-risk (route existence + shape) but the
  200-embedded-error low-bound note is v9.99-era.
- `rest-api-overview.md` is explicitly version-lagged outside its re-verified
  sections; the only route facts used from it (webhook CRUD, export route)
  were re-verified against v12.99 above.

## 6. Open items (not scouted — need a live probe or the dev variant)

- Live confirmation that the deployed pod (chart 12.99.0, 2026-11-21) answers
  `GET /api/boards/TNQJ2BrXenZovngTS/export?fields=activities` with the flat
  activities array, and that a REST card edit does **not** bump `modifiedAt`
  (the code says so; the probe would). Post-deploy live probing of any new
  wekan-mcp surface is user-owned per repo precedent (cf-77 shape).
- The launch brief named "the 12 tools"; that list did not survive
  compaction. All 18 read tools are documented in §1.2 (superset), so any 12
  of them are covered; if the plan needs a narrower set, the board-flow
  consumers are `preload_board`, `get_board`, `list_boards`, `list_lists`,
  `list_swimlanes`, `list_cards_in_list`, `get_card`, `get_card_details`,
  `list_comments`, `list_checklists`, `get_checklist`, `list_custom_fields`.

RESULT
status: DONE
chunk: plan
files_changed: [.agents/plans/2026/2026-11-cf-140-feat-agent-card-reconcile/EXPLORE-wekan-mcp.md]
commands_run: [read containers/wekan-mcp/{server.py,wekan.py,pyproject.toml,Dockerfile,README.md} => pass, grep wekan-mcp tool defs/shapers/_write_tool gate => pass, sed services/dev/prod/values.yaml L464-498 + .opencode/opencode.jsonc L75-83 + services/home/prod/Chart.yaml L39-48 + services/gpu/prod/values.yaml L732-800 => pass, curl+grep wekan v12.99 {models/cards.js,server/models/cards.js,server/models/boards.js,server/models/integrations.js,models/export.js,models/exporter.js,models/lib/exportFields.js,models/activities.js,server/lib/checklistDeadlines.js} => pass, grep scripts/ tests/ .opencode/plugin/ for yaml machinery => pass, python3 fixture swimlane map => pass]
deviations: none
friction: none
open_questions: [live probe of export ?fields=activities + REST-write modifiedAt no-bump is user-owned post-deploy (repo precedent cf-77); "the 12 named tools" list lost in compaction — §1.2 documents all 18 read tools as a superset]
next_suggested: plan the format: json|yaml arg as one chunk — `format` param on the read tools + `_serialize` helper + `pyyaml` in pyproject.toml, with the Forgejo CI build as the AC gate
