# API research log — WeKan v9.99 surface for the board-intake redesign

Planner's targeted-verification log (NOT `RESEARCH.md` — that file name is
reserved for coordinator-commissioned `agent-research` output). Every claim
below was verified first-hand 2026-10-24 against the **deployed** WeKan source
at the pinned tag `v9.99` (`ghcr.io/wekan/wekan:v9.99`, confirmed on the live
home cluster pod `home-wekan-6fb9d9c6f9-knlrl`) — repo tree at
`https://github.com/wekan/wekan/tree/v9.99`, cross-checked against
`api.py` and the in-repo OpenAPI spec `public/api/wekan.yml`, both shipped at
that tag. Local copy: `/tmp/opencode/wekan-src/src` (throwaway).

## 1. Custom fields (board-level)

REST routes live in `server/models/customFields.js` (WebApp.handlers; JSON
bodies accepted — `server/apiMiddleware.js` installs `bodyParser.json()`):

- `GET /api/boards/:boardId/custom-fields` → `[{_id, name, type}]` only.
- `GET /api/boards/:boardId/custom-fields/:customFieldId` → full doc
  (name, type, settings incl. `settings.dropdownItems[]`, flags).
- `POST /api/boards/:boardId/custom-fields` — creates. The handler reads
  exactly `name, type, settings, showOnCard, automaticallyOnCard,
  showLabelOnMiniCard, showSumAtTopOfList` via
  `CustomFields.direct.insertAsync`.
  **Gotcha 1: the body's `alwaysOnCard` key is NOT read on REST create.**
  **Gotcha 2: `direct` insert bypasses the collection hooks, so even the
  `after.insert` → `CustomFields.addToAllCards()` backfill does NOT fire for
  REST-created fields.**
- `PUT /api/boards/:boardId/custom-fields/:customFieldId` — per-key
  `$set`s incl. `alwaysOnCard` and `automaticallyOnCard`, also via
  `direct.updateAsync` → after the flag is set this way, the backfill hook
  still does NOT run; it only changes future card-creation behavior.
- `POST/PUT/DELETE .../custom-fields/:id/dropdown-items[/:itemId]` —
  dropdown option maintenance (not needed by this flow; noted for reuse).
- Schema (`models/customFields.js`): `type ∈ {text, number, date, dropdown,
  checkbox, currency, stringtemplate}`; a field can serve multiple boards
  (`boardIds[]`). `checkbox` is a boolean; `dropdown` holds a SINGLE item
  id. **There is no multi-check custom-field type.** (Original OQ3 guess:
  a `models` text field recording the routing — SUPERSEDED by D12: the
  field is dropped entirely, the Model(s) checklist is the sole routing
  input; see §10.)
- `CustomFields.after.insert` / `after.update` call `addToAllCards`
  (`$push {fieldId, value: null}` onto every board card) **only when the
  field doc has `alwaysOnCard: true` AND was inserted/updated through the
  hooked path — i.e. the UI form**, not REST. So a UI-created
  "always on card" field backfills existing + future cards; a REST-created
  one does not.

## 2. Custom-field VALUES on cards

- `POST /api/boards/:boardId/lists/:listId/cards/:cardId/customFields/:customFieldId`
  (`server/models/cards.js`, ~L1546): value = `req.body.value`;
  implementation maps over the card's EXISTING `customFields` array — **a
  field that is not already attached is silently dropped (no-op).** Path
  requires the current `listId` and needs board write access.
- `PUT /api/boards/:boardId/lists/:listId/cards/:cardId` accepts
  `customFields: [{_id, value}]` and `$set`s the WHOLE array
  (`server/models/cards.js` ~L1203, direct update). This is the reliable
  attach-or-update (upsert) primitive; the MCP tool wraps read-modify-write
  on it.
- REST/bulk card CREATE (`server/models/cards.js` ~L866/~L956) auto-attaches
  every board field with `automaticallyOnCard || alwaysOnCard` as
  `{_id, value: null}` — future REST-created cards are covered. UI-created
  cards go through the collection insert (hook fires for the *activity*
  only), so the upsert tool stays the only dependable write path for
  arbitrary cards.

## 3. Card number (for the `cf-<card-number>-` slug prefix)

- `cardNumber` is on the card schema (`models/cards.js` L743) and REST
  create assigns `board.getNextCardNumber()` (~L884/L908; bulk ~L992).
- `GET /api/cards/:cardId` returns the FULL card document
  (`data: card`) — includes `cardNumber`, `customFields`, `labelIds`.
  wekan-mcp's `get_card` uses exactly this route, so exposing
  `card_number`/`custom_fields` in `_slim_card` is free.
- The LIST endpoint `GET /api/boards/:boardId/lists/:listId/cards` returns a
  PROJECTION (`_id,title,description,swimlaneId,receivedAt,startAt,dueAt,
  endAt,assignees,sort`) — **no labelIds / customFields / cardNumber /
  listId**. Consequence for pickup: `list_cards_in_list` identifies order
  only; every candidate must be `get_card`-ed to see label + custom fields.
- Ordering: the list endpoint sorts `{sort: ['sort']}` ascending → response
  order == board order, leftmost/top = first entry. "Top-to-bottom,
  highest-sort first" pickup = walk the response in order.

## 4. Labels (research-only detection)

- Board labels: `GET get_board` already surfaces `labels[{id,name,color}]`
  (verified live on the Projects board via `admin-global-wekan`).
- Card label ids: present in the full card doc from `get_card`
  (`_slim_card.label_ids` already maps them).
- Flow therefore needs NO new tool for research-only detection: resolve the
  "Research" label id from `get_board`, compare with `get_card.label_ids`.
  Label creation + assignment stays a human UI action (agent only reads).

## 5. Checklist items

- `POST .../cards/:cardId/checklists` accepts `items` (array or string) at
  creation (`server/models/checklists.js` ~L270) — matches wekan-mcp's
  existing `add_checklist`.
- `DELETE /api/boards/:boardId/cards/:cardId/checklists/:checklistId/items/:itemId`
  EXISTS (`server/models/checklistItems.js` ~L217; also in the shipped
  `wekan.yml` as `delete_board_card_checklist_item`). wekan-mcp just lacks
  the tool → add `delete_checklist_item`. Post-plan pruning of unchecked
  options needs no other new primitive (`list_checklists` + `get_checklist`
  already enumerate ids/titles/finished state).

## 6. Board automation rules (future-card coverage)

- Rule engine (`server/rulesHelper.js` at v9.99): every activity insert
  (`server/models/activities.js` `after.insert`) → `executeRules`. Trigger
  vocabulary in `server/triggersDef.js` includes `createCard` with
  matchingFields `[boardId, listName, userId, swimlaneName, cardTitle]`;
  REST rule create normalizes omitted matchers to the `'*'` wildcard.
- **`createCard` activity fires for REST-created cards** — the REST create
  route calls `cardCreation(...)` (`server/models/cards.js` L917; bulk
  L999) which inserts `{activityType:'createCard', listName, cardId, ...}`.
  A rule `trigger {activityType:'createCard'} → action
  {actionType:'addChecklistWithItems', checklistName, checklistItems}`
  therefore covers cards created by the agent AND by the UI.
- `addChecklistWithItems` (rulesHelper L499): creates the checklist and
  splits `checklistItems` on **`,`** — item titles MUST NOT contain commas
  (all current option sets comply: 13 service names, 7 types, 4 models, 5
  research scopes). Supports `{variable}` substitution (`{cardnumber}`
  etc.).
- POST /api/boards/:boardId/rules validates only `trigger.activityType` /
  `action.actionType` presence (`server/models/rules.js` ~L150) — no
  action whitelist, so the vocabulary above is exactly what the engine
  implements. wekan-mcp already exposes `create_rule`/`update_rule`/
  `remove_rule`/`list_rules` — **rule-based automation needs NO new tool**.
- Rules do NOT retroactively touch existing cards → backfill is the
  runbook's separate step.
- No custom-field-related rule action exists — custom-field per-card
  coverage relies on §1/§2 (flags + upsert tool), not rules.

## 7. Live board state (2026-10-24, admin-global-wekan)

- `list_boards` (wekan service user) → **only "Projects"**
  (`TrfngHQf8PWj9mnqC`). The AI-Dev board + `ai-dev-bot` membership from the
  upstream ticket's user-owned prerequisites **still does not exist**.
  All board mutations (fields, rules, checklists, backfill) are gated on
  that prerequisite.
- `dev-boards` MCP server: declared in `.opencode/opencode.jsonc` (L387),
  not connected (dev-wekan-boards Bitwarden item still a placeholder) —
  research inspection used gpu-tier `admin-global-wekan` /
  `readonly-global-wekan` as designed.
  **[SUPERSEDED 2026-10-25 re-cut: main wires `dev-boards` to the
  `wekan-mcp` LOGIN item with real UUID via login-mint — see §11 and
  DECISIONS D23.]**

## 8. Deploy reality (wekan-mcp)

- `.github/workflows/docker-build.yaml`: merge to `main` touching
  `containers/**` pushes `:v<run_number>` (immutable) + `:<branch>`
  (rolling); PRs build but never push. `containers/wekan-mcp/README.md`'s
  "VERSION file / semver tags" description is STALE — fix in C01.
- Live entries run `image: ghcr.io/ownyourio/wekan-mcp:main` +
  `imagePullPolicy: Always` with a standing comment "pin to `:v<run>` once
  published" (`services/gpu/prod/values.yaml` ~L594/L631,
  `services/dev/prod/values.yaml` ~L182). A pin cannot be set pre-merge
  (tag doesn't exist yet) → keep `:main`, redeploy = pod restart after
  merge. `tests/dev-mcp-fleet/boards.sh` c5 pins `:main` + Always — stays
  green. Renovate does not track this image.
- No pytest harness in `containers/wekan-mcp/` — validation = static
  (py_compile + tool-registry grep) + CI build + live check post-merge.
  **[SUPERSEDED 2026-10-25 re-cut: main added
  `tests/containers/wekan-mcp-login.sh` (mock-server contract) and the
  fleet tests moved to `tests/services/dev-mcp-fleet.sh` — see §11,
  DECISIONS D24/D25.]**

## 9. Repo surface being reworded (verified this branch @ 09696ae57)

- `.rulesync/skills/boards/SKILL.md`: lists are
  Not Started/Executing/Ready for Review/Rework/Finished (no Low Priority);
  pickup id→Rework→Not Started; no checklists-as-answers, no custom fields,
  no research-only branch; lifecycle lacks the post-plan card update.
- `.rulesync/subagents/agent-board-coord.md`: `dev_boards*` wildcard
  already permits future wekan-mcp tools (whole-value wildcard, coord
  ruling 2026-10-24) — frontmatter needs NO change; only the `## Boards`
  body section rewords. MUST-loads already include pipeline-kickoff /
  pipeline-models / agent-research.
- `.rulesync/commands/pipeline-boards.md`: intake line encodes the old
  pickup order.
- `tests/agent-board-coord/rulesync-surface.sh` c4 greps the boards skill
  for the five section titles + board-fact strings; the redesign must keep
  those (superset) or the test session extends them.
- `pipeline-kickoff` Q1–Q3 (slug/models/run tag) and the worktree naming
  `<slug>-<run tag>` are agent-coord surfaces; card-driven runs replace the
  questions with card reads — the boards skill gains a "Card-driven
  kickoff" section that explicitly overrides kickoff Q1–Q3 for board runs.
  **Decision: pipeline-kickoff/pipeline-models files stay untouched**
  (agent-coord keeps run tags; kickoff data declares run tags retired for
  THIS flow only).

## 10. OQ-round resolutions + session-URL discovery (2026-10-24)

Batched round returned (full record in DECISIONS D10–D19): OQ1/2/5/7/9/10
confirmed the best guesses; **OQ3 dropped the `models` custom field
entirely** (board fields = `slug` + `session` only; Model(s) checklist is
the sole routing input); **OQ4 requires a full URL** for `session`;
**OQ6 makes research-only iterative** (initial research → one batched
follow-up question round → further research → comment + write-back →
Ready for Review); **OQ8 pins `:v<run>` immediately** as a sequenced
post-merge step (M1 merge → M2 pin-bump → M3 verify), not an open-ended
`:main` end state.

Session-URL scheme (targeted investigation, per ticket allowance):

- The lab's session UI is **OpenChamber** (`@openchamber/web`), installed
  and served in every Coder workspace:
  `charts/coder/coder-templates/kubernetes{,-hardened}/main.tf` —
  `openchamber serve --port 3000 --host 127.0.0.1` + `coder_app
  "openchamber" { subdomain = true, share = "owner",
  url = "http://127.0.0.1:3000" }`.
- Coder moved to the **dev** cluster (`custom-values/dev/prod-values.yaml`
  carries the live `coder.bitwardenIds`; the gpu one is commented out).
  `charts/coder/templates/secret-coder.yaml`:
  `CODER_ACCESS_URL = https://coder.dev.scifi.farm`, wildcard
  `CODER_WILDCARD_ACCESS_URL = *-coder.dev.scifi.farm` (dev values set
  `subDomain: dev`).
- OpenChamber deep-link router (`github.com/openchamber/openchamber`,
  `packages/electron/main.mjs` L3011–3021): session links are
  `<instance-url>/?session=<sessionID>` (optionally `&message=<id>`);
  `parseSessionRoute(url.searchParams.get('session'), …)`. The GitHub/
  Linear integration posts exactly this URL shape when the instance has a
  public address (docs/integrations).
- ⇒ Canonical value for the `session` custom field:
  `https://<openchamber-app-host>/?session=<coordSessionID>` where the app
  host is the Coder subdomain label for the workspace. CLOSED at approval
  (D20): the user confirmed the browser origin — label order is
  `{app}--{workspace}--{user}`, giving
  `https://openchamber--dev-thehackmeister-coder.dev.scifi.farm` (my
  guessed `{app}--<user>--<workspace>` was wrong; fetch probe confirmed the
  wildcard is live but `share=owner` auth makes the exact 200
  un-fetch-verifiable). Recorded verbatim as the boards skill's
  `SESSION_URL_BASE`.
- Consequence for runbook M2: after the pin-bump merges, ArgoCD sync
  recreates the ToolHive MCPServer pods (`image` field change → new
  StatefulSet) — the earlier "manual pod restart" step is superseded;
  `imagePullPolicy: Always` stays correct for an immutable tag.


## 11. New-base verification (2026-10-25, origin/main 5e35ba6da → branch 8ef6a8056)

- wekan-mcp: `grep -c '^@mcp.tool' == 11`, `'^@_write_tool' == 9` → **20
  tools** (README + wekan-api SKILL say 20; re-cut launch said 27 — false,
  D22). Zero `customField` occurrences. `_slim_card` at server.py L96;
  READ/WRITE section headers at L146/L258 — C01's insertion points.
- `wekan.py`: login-mint (precedence WEKAN_TOKEN > USERNAME+PASSWORD;
  POST /users/login; bounded refresh-on-401; credentials never echoed);
  client verbs get/post/put/delete + `user_id` unchanged (L225-228) → C01
  interface pins hold on the newer client. New gate:
  `tests/containers/wekan-mcp-login.sh` (mock http.server, imports only
  wekan.py — keep green; C01 doesn't edit wekan.py).
- dev boards entry (`services/dev/prod/values.yaml` ~L409): image
  `wekan-mcp:main` + Always; env entirely from Secret `wekan-mcp`:
  `WEKAN_BASE_URL`+`WEKAN_USERNAME`+`WEKAN_PASSWORD` — ExternalSecret
  `services/dev/prod/templates/secret-wekan-mcp.yaml` reads ONE LOGIN item
  (`bitwardenIds.wekan-mcp` = d8e2b2ca…, REAL in
  `custom-values/dev/prod-values.yaml` L35) via `bitwarden-login` (username/
  password) + `bitwarden-uri` (URI field = instance URL, "data not config"
  user decision 2026-10-24). gpu stays token-only. `boards-mcp`/
  `dev-wekan-boards` artifacts no longer exist (superseded).
- tests layout: `tests/dev-mcp-fleet/` + `tests/agent-board-coord/` GONE;
  fleet now `tests/services/dev-mcp-fleet.sh` (t7 pins dev-boards image ==
  `wekan-mcp:main` strictly — D24 generalization target) + container login
  contract `tests/containers/wekan-mcp-login.sh`. Old agent-board-coord
  scripts reachable: `git show 09696ae57:tests/agent-board-coord/...`.
- pipeline agents main-side convention: broad `dev*` allow
  (agent-plan L78 etc.); ported agent-board-coord L76 `dev_boards*` —
  adjudicated keep (D21).
- `permissions.md`: grep `board-coord` == 0 (row lost in the re-cut);
  `overview.md`: same — C04 merges back (D25). AGENTS.md's MCP table now
  carries the combined `dev-<service> (playwright, renovate, searxng,
  boards)` row — keep verbatim.
- Live dev cluster (readonly-dev-kubernetes, 2026-10-25): MCPServer CRDs =
  kubernetes×2, playwright, renovate, searxng (pods 5 min old); **no
  mcp-boards**, no mcp-github CRD; wekan-mcp image pins `:main` on gpu +
  dev. Home cluster: wekan still `ghcr.io/wekan/wekan:v9.99` (deployed-tag
  claim re-confirmed). admin-global-wekan `list_boards` → still only
  "Projects" — AI-Dev absent (unchanged gate).
- README on main: credential bullet updated for login-mint; the
  "Image: bumps the VERSION file … `:<version>` + `:latest`" bullet and
  the layout `VERSION` line are STILL stale (README L32-33, L48-53) —
  C01 task stays valid.
