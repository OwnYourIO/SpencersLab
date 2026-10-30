# RESEARCH — cf-89 wekan-mcp v102 board-provisioning surface

Scope (from coord): verify the four must-have routes (update_board, create_swimlane,
create_label, list_board_members) against WeKan GitHub source at the pinned tag and
vs current main; settle PUT semantics, cardNumber preservation, label colors, swimlane
positioning, and member/username publishing. Method: storm run (perspectives →
grounded interviews → contradiction map); every claim cited to
`/tmp/opencode/storm-runs-cf89/wekan-mcp-v102-board-provisioning-rest-surface-update-board/sources.md`
[S#]. Primary evidence = extracted source trees of tags **v9.88** and **v12.65** [1][2]
and raw `v12.74` [5].

## Reliability notes (self-review)

- Confidence 9/10: route inventories, gates, response shapes — read directly from the
  registered handlers in both extracted trees, cross-checked by the project's own
  Playwright e2e specs [21][22][23].
- Confidence 8/10: live-version grounding (server = upstream 12.65) — repo pin + charts
  index; the live pod tag itself was not read from the cluster (no kubectl in scope).
- Weakest claim: "the bot token is not a site admin" — taken from the card's own
  statement; the WEKAN_TOKEN secret value is Bitwarden-held and unreadable here. What
  would verify it: one live `GET /api/user` check of `isAdmin` at chunk time.
- Over-weighted perspective: none; the version-drift analyst ended up decisive because
  the card's pinned version was wrong.

## TL;DR

1. **The card's version premise is wrong.** The live board server is chart-pinned wekan
   chart **12.65.0 = upstream WeKan v12.65** (repo pin, git history 9.99.0 → 12.64.0 →
   12.65.0) [27][20]; upstream has no tag "v9.88.0" (form: `v9.88`) [26]. v9.88 was used
   here only as the low-bound comparison.
2. **`PUT /api/boards/:id` does not exist in any version** (9.88, 12.65, 12.74) — bare
   PUT answers 405 [3][4][5][16]. The sanctioned rename route is the dedicated
   **`PUT /api/boards/:id/title`** (`$set {title}` only): board id AND the cardNumber
   counter survive by construction [3][4][18]. No REST route can change board `color`
   or `permission` at all — drop them from v102 scope.
3. **create_swimlane / create_label routes are exactly as the card hoped**, identical
   logic at v9.88 and v12.65; swimlane POST **honors an explicit `sort`** (#3624) and
   defaults to max(live sort)+1 [6][7][17]; label PUT returns the **label id as a bare
   JSON string** [4][21].
4. **Label colors**: the accepted set is the 25 named colors **including `white` already
   at v9.88**; the server validates and 400s unknown colors (never store hex) [9][8].
5. **Board members**: the board document publishes `members` as objects with `userId` +
   **eight** role booleans (not bare ids, not four flags) [10][14]; **no REST route at
   board-member privilege publishes usernames** — the only user-lookup routes are
   site-admin-only [14].

## 0. Version grounding (decide this before the chunk table)

- Repo pins: `services/home/prod/Chart.yaml` + `Chart.lock` → wekan chart **12.65.0**,
  twice (two chart instances) [27]. Git history: was **9.99.0** (matching the fleet
  skills docs' "lab's deployed version v9.99" [29]), bumped to 12.64.0 then 12.65.0 [27].
- Charts index: chart 12.65.0 → `appVersion: 12.65` / image `wekan:v12.65`; the old
  `appVersion 9.88` belonged to **chart 9.89.0**, which the fleet never pinned [20].
- Upstream tags: `v9.88` exists (sha `ad4dc59…`); **`v9.88.0` 404s**; WeKan tags never
  use the three-component patch form for these releases; current tip is v12.74 [26].
- The MCP consumes the board at `WEKAN_BASE_URL=https://wekan.spencerslab.com` (gpu
  cluster hivetools `wekan-readonly`/`wekan-admin`, shared `WEKAN_TOKEN`) [27].
- Implication: canonical declarations for this ticket are tag **v12.65**; keep v9.88 as
  the documented low bound. The card's "field learnings span v9.99–v12.64" matches the
  pin history and is credible.

## 1. update_board

**Route reality (all versions 9.88 / 12.65 / 12.74):** the boards route table contains
GET, POST, DELETE on the collection/document and PUT only on sub-resources (`/title`,
`/labels`, `/cardSettings`, 12.x adds `/cardFieldOrder`, `/boardViewSettings`). There is
**no `PUT /api/boards/:id`** [3][4][5]. Upstream issue #5299 records exactly the card's
attempt — a bare `PUT /api/boards/:id` with `{"title": …}` → **HTTP 405** — and the
resolution was the dedicated title route [16]. `api.py` confirms at both pinned tags:
`editboardtitle` calls `PUT …/api/boards/<id>/title` with `{"title": …}` [15].

**The route to use — `PUT /api/boards/:boardId/title`:**
- Body: `{"title": "…"}`. Handler: `Boards.direct.updateAsync({_id}, {$set: {title}})` —
  direct (hook-bypass: no activity, no rules), partial `$set` of exactly one field [3][4][5].
- Response: `{"_id": <boardId>, "title": <newTitle>}` (200).
- Gate drift: **v9.88** = `checkBoardWriteAccess` (write member may rename);
  **v12.65 + v12.74** = `checkBoardAdmin` (board admin or site admin only). The 12.65
  e2e asserts a normal member gets **HTTP 403** and the title is unchanged [4][5][11][22].
- Error shapes: v9.88 catch sends **HTTP 200 with the serialized Meteor.Error body**
  (e.g. `{"error":"not-authorized","reason":"Forbidden"}`-style) [3][12]; v12.65+
  `publicErrorData` → real 401/403/404 with `{"error": msg}` [4][13]. Since live = 12.65,
  status-code errors are the normal path; a defensive tool should still verify
  `resp["_id"] == board_id` before declaring success.

**Partial-update & cardNumber-preservation verdict:**
- The card's "if the server's PUT demands the full document, fetch-modify-put internally"
  branch is **void** — there is no full-document PUT to fetch-modify-put into. Do NOT
  build one out of POST+DELETE (that would mint a new `_id` and reset everything).
- The cardNumber **sequence is not on the board document at all**: since v9.82 the next
  number comes from an atomic per-board counter `_id = "cardNumber-<boardId>"` in the
  `Counters` collection, lazy-seeded from max existing cardNumber (#5813/#4743) [18][4].
  A title-only `$set` cannot touch it; `updateAsync` targets `_id`, so the board id (and
  every list/card/swimlane id, every cf-<cardNumber> slug) survives a rename untouched.
  Verdict: **safe**, no extra preservation work needed beyond not deleting the board.
- v12.65 extra nobody documented: board **`key`** (#2449/#2450) — 2–10 capital
  letters/digits, auto-assigned on every insert (server/boardKeys.js after.insert),
  unique, and it makes card numbers DISPLAY as `KEY-7`. No REST route changes it (UI
  only). It rides the board document returned by GET, so the MCP read-back can echo it;
  renaming never changes it.

**color / permission verdict: drop them.** `color` (`allowedValues BOARD_COLORS`) and
`permission` (`public|private`) are set only at POST /api/boards create (defaults
`belize` / `private`) and are read-only over REST in 9.88, 12.65 and 12.74 [3][4][5][10].
If the planner wants any of it, the only REST-adjacent knob is `allowsInstanceEditing`
in neither board-settings route — not worth it; expose title only.

**Tool recommendation:** `update_board(board_id, title)` → PUT …/title; hydrate with
GET /api/boards/:id read-back (`_slim_board` + `card_number_counter` is NOT in the doc —
do not fake it); echo `{id, title, key?, color, permission, renamed: true}`. Because the
live gate is board-admin, document the 403 clearly; `isBoardAdmin` for the bot is visible
from the board doc's own members array (its own userId entry) — good pre-flight or
error-hint material.

## 2. create_swimlane

**Route (identical at v9.88 and v12.65; api.py only documents GET — api.py lag):**
`POST /api/boards/:boardId/swimlanes`, gate `checkBoardWriteAccess` [6][3][4][15].
- Body: `{"title": "…"}` (title required by schema; sort optional) [6].
- Position: `sort: nextSwimlaneSort(existingSorts, req.body.sort)` — **#3624 fix**: an
  explicit finite `sort` in the body is HONORED; otherwise append at
  max(live swimlane sorts)+1, computed over `archived:false` siblings [6][7][17]. The
  issue's original complaint (new swimlane appearing FIRST on non-contiguous sorts) was
  fixed before both pinned tags [18].
- Response: `200 {"_id": <newSwimlaneId>}` only — no title, no sort.

**Read-back / hydration notes:**
- GET collection `…/swimlanes` projects to `{_id, title}` — **no sort** [6].
- GET single `…/swimlanes/:swimlaneId` returns the FULL doc **including `sort`**, but
  filters `archived: false` (fine for fresh creates) [6]. That is the hydrate source
  (precedent: v101 `create_list`'s single-list read-back [28]).
- Because default sort = max+1 over live siblings, sequential creates ARE ordered
  server-side at 12.65; echoing the actual `sort` from read-back (the card's demand) is
  still right, and the optional `sort` pass-through makes placement explicit.

**Error shapes:** wrong board id / non-member → v9.88 = HTTP 200 + serialized error
body; v12.65+ = proper 401/403/404 via `publicErrorData` [3][4][13]. Missing title →
schema insert error: at 12.65 that is a 4xx `{"error": msg}`; at 9.88 it is a crash-proof
`safeJsonStringify` fallback `{"error": "<message>"}` at **HTTP 200** — which wekan.py's
embedded-error test (`"error" in parsed and "reason" in parsed`) does NOT catch [13][28].
Tool must treat "no `_id` in response" as failure regardless.

## 3. create_label

**Route (byte-identical handler at v9.88 and v12.65; unchanged at v12.74):**
`PUT /api/boards/:boardId/labels`, body `{"label": {"name": …, "color": …}}` [3][4][5].
- Gate: inline explicit — board admin (`allowIsBoardAdmin`) OR site admin; responses are
  clean **401 / 404 (Board not found) / 403** with `{"error": …}` bodies at both pinned
  versions (the #5819 hardening predates 9.88) [3][4][19].
- Accepted shapes (`buildBoardLabel`, identical both tags): the documented `{"label":
  {name,color}}`; `{"label": {name}}` (color defaults to **`green`**); `{"label": "name"}`
  string form. Missing/garbage `label` → clean 400 (the #5510 fix; the old handler never
  responded for a body without `label` — it hung) [8].
- **Colors:** `LABEL_COLORS = ALLOWED_COLORS` from `config/const.js` — 25 names:
  `white, green, yellow, orange, red, purple, blue, sky, lime, pink, black, silver,
  peachpuff, crimson, plum, darkgreen, slateblue, magenta, gold, navy, gray, saddlebrown,
  paleturquoise, mistyrose, indigo` — **identical at v9.88 and v12.65, and `white` is
  already there at 9.88** (the card's "live v12+ also accepted white" is off by three
  minor lines) [9]. Unknown/hex color → **400 `Invalid label color '<x>'. Allowed
  colors: …`** [8]. (Board colors are a DIFFERENT set: BOARD_COLORS, 19 at 9.88 → 25 at
  12.65 adding `appleglasspastel`, `cleargreen/orange/pink/purple/red` — relevant only
  if create_board work ever lands) [9][10].
- Idempotency / duplicate semantics: `board.getLabel(name, color)` matches **name AND
  color** (`findWhere({name, color})`) — re-PUT of an existing (name,color) returns the
  EXISTING id (200, idempotent); same name with a DIFFERENT color pushes a SECOND label
  and returns the new id. The tool must not promise "rename by name" [4][10].
- **Response carries the id**: `sendJsonResult(code 200, data: labelId)` where labelId is
  `Random.id(6)` (new) or the existing id — i.e. the body is a **bare JSON string**
  (`"aB3xY9"`), as the e2e helper states [4][21]. Board-label fallback read via
  GET /api/boards/:id (`_slim_board` already surfaces `labels[].id`) exists but is NOT
  needed for id capture [28].
- Downstream fit confirmed: rules `addLabel` action consumes `action.labelId` [4,
  rulesHelper] and bulk card labels `POST /api/boards/:boardId/cards/labels`
  `{cardIds, addLabelIds}` exists at BOTH tags (12.65 e2e asserts 400 for a
  not-on-board label id) — a strong later-v103 surface, not needed now [3][4][21].

**Tool recommendation:** `create_label(board_id, name, color="green")`; client must
handle the bare-string response (wekan.py returns whatever `resp.json()` yields — a
`str` here passes through fine); validate color against the 25-name list client-side
(fails fast with the same list) AND keep the server 400 as authority; echo
`{label_id, name, color, created: bool}` where `created` can be inferred only by a
GET-before/after diff — or drop `created` and document the idempotent semantics.

## 4. list_board_members

**Members shape in the board document (schema + GET /api/boards/:id, both tags):**
GET …/:boardId returns the **raw board doc** (gate `checkBoardAccess`: active ordinary
member or site admin; 404 for missing board at both tags) [3][4][11]. `members[]` is an
array of objects [10]:
- `userId` (string id — **no username anywhere in the board doc**, except the v12.65
  `members.$.grantedBy` provenance array for team/org-granted memberships);
- role booleans: `isAdmin`, `isActive` (required) + `isNoComments`, `isCommentOnly`,
  `isWorker`, `isNormalAssignedOnly`, `isCommentAssignedOnly`, `isReadOnly`,
  `isReadAssignedOnly` (optional) — the fleet overview's four-flag list is stale [29][10];
- the card's "role booleans isAdmin/isNoComments/isCommentOnly/isWorker" is the OLD
  subset; echo all eight plus isActive for a truthful picture. There is no `owner`
  field to harvest — ownership = the members entry with `isAdmin: true` [10].

**Username-resolution verdict:** the ONLY REST routes that publish usernames are
site-admin-gated (`Authentication.checkUserId` → 401/403):
`GET /api/users` (projects `_id` + `username`) and `GET /api/users/:userId` (accepts id
OR username; returns the user doc + per-board role rows; 12.65 strips `services`/
`sessionData` per GHSA-6qpx-x7vr-p9w6) [14]. A complete inventory of user-bearing
routes at both tags shows **no board-member-privilege route publishing usernames**
[3][4][14]. Consequences for v102:
- Keep `list_board_members(board_id)` → GET board doc → `members[]` with `username: null`
  and an explanatory field (e.g. `username_resolution: "requires site-admin token"`).
- Do NOT probe `GET /api/users/:userId` when the bot is not site admin: at a 9.88-style
  server that probe answers HTTP 200 with a serialized Forbidden body (invisible to the
  v101 client); at 12.65 it is a clean 403 but still pointless noise. Gate any probe on
  `self.isAdmin` from the startup `GET /api/user` document (already fetched by
  `validate()`).
- If the fleet ever flips the bot to site admin, the enrichment is a one-call-per-member
  add-on; until then usernames ride the existing rule surfaces (`addMember` actions take
  `username`, so write-side keeps working without resolution).

## 5. Error-shape matrix for the four routes (the HTTP-200 trap)

| Route | v9.88 (low bound) | v12.65 live / v12.74 |
|---|---|---|
| PUT …/title | 200 + serialized Meteor.Error body on 401/403/404 [3] | real 401/403/404, body `{"error": msg}` [4][13]; e2e-verified 403 [22] |
| POST …/swimlanes | 200 + error body on authz/404 [3] | real 4xx via publicErrorData [4] |
| PUT …/labels | clean 401/403/404/400 (inline gate) [3] | same; catch also 4xx [4] |
| GET …/board doc | 200 + error body on authz/404 [3] | real 4xx [4] |
| GET /api/users* | 200 + error body for non-admin [14] | real 401/403 [14] |

Client gap to respect in v102 code: wekan.py raises embedded errors only when the body
is a dict containing BOTH `error` and `reason`; the 12.65 error body has only `error`
(caught via ≥400 status), but the 9.88 fallback `{"error": msg}` arrives at 200 and is
NOT caught [28][13]. Rule for the new tools: never trust 200 alone — assert the expected
key (`_id`, label id string, `members` list) and raise otherwise.

## 6. Deprioritized optionals — verified anyway (cheap, they're adjacent files)

- `update_swimlane`: `PUT …/swimlanes/:swimlaneId` body `{"title": …}`; write-access
  gate; 404 "Swimlane not found" (200-embedded at 9.88, real 404 at 12.65); `direct`
  update but after.update hook still fires `changedSwimlaneTitle` activity [3][4][6].
- `delete_swimlane`: `DELETE …/swimlanes/:swimlaneId` is a **hard**
  `Swimlanes.removeAsync` (not an archive) — must carry the DESTRUCTIVE docstring like
  remove_rule [6].
- `update_list`: `PUT …/lists/:listId` (#5396) edits title/color (color accepts named
  palette OR `#rrggbb` for lists — unlike labels), starred, wipLimit; 404-with-`{"message":
  "Error"}` if the list is gone or no field was accepted [4][lists.js].
- Card "move position parameter": unchanged from v101 doctrine (list move POST exists;
  `repositionSwimlane` is internal, no REST route) [4].

## 7. Contradictions & implications for the plan

1. **Fix the version premise in the plan of record.** Pinned server = upstream
   **v12.65** (chart 12.65.0), not 9.88 [27][20]. Write chunk ACs against v12.65
   handler behavior (real 4xx everywhere, board-admin title gate), keep v9.88 facts as
   documented low bound. If any test/chunk cites "v9.88.0", it's misgrounded — the tag
   form is `v9.88` [26].
2. **update_board shrinks**: title only; NO color/permission (no REST route exists) —
   delete the fetch-modify-put contingency entirely; cardNumber safety is free (Counters
   collection) and worth one AC asserting a card created AFTER the rename gets the next
   sequence number [4][18].
3. **create_swimlane should expose `sort`** (body pass-through, honored since the #3624
   fix at both tags) and hydrate `sort` from the single-swimlane GET (collection route
   lacks it) [6][7].
4. **create_label response parsing needs a str branch** (bare-string id) and must encode
   the (name,color)-idempotency + "same name, different color = new label" semantics;
   client-side color list = the 25 names incl. `white`; keep the server as validator [4][8][9][21].
5. **list_board_members publishes role booleans not usernames**; any username story needs
   a site-admin token the bot doesn't have [10][14]. The tool response should say so
   explicitly rather than silently returning nulls.
6. Fleet `skills/wekan-api/references/rest-api-overview.md` is now known-wrong/stale on:
   missing PUT …/title, missing POST swimlanes body/sort, member role body (4 vs 8),
   label response shape (bare id), bulk card labels route. A docs-refresh line item in
   the same ticket (or a friction-log item) is cheap and prevents the next agent from
   rediscovering this [29].
7. Board `key` (KEY-7 display, auto-assigned, REST-immutable) is a genuine blind spot of
   every doc consulted — mention it once in the plan so nobody builds a "change key"
   wish into v102 [4][25].

## 8. Open questions (batched for coord)

1. Card says pinned upstream "9.88.0"; repo says chart 12.65.0 (= v12.65). Which does
   coord treat as authoritative for ACs? (Research recommends v12.65; everything here
   already covers both.)
2. Is the wekan-mcp bot a **board admin** on the AI-Dev board? (Title-rename and
   label-create both 403 without it at 12.65; verifiable via the board doc's members
   entry for the bot's own userId from `GET /api/user`.)
3. Should `create_label` expose the string-form/`green`-default convenience, or force
   explicit `name`+`color` (recommended: explicit, defaults tool-side)?
4. Should the v102 plan include the cheap docs-refresh for `rest-api-overview.md`
   (item 7.6), or keep scope to the container?

## RESULT
status: DONE
chunk: plan (pre-planning research round)
files_changed: [.agents/plans/2026/2026-10-cf-89-feat-wekan-mcp-v102-tools/RESEARCH.md]
commands_run: [git log services/home/prod/Chart.yaml => pass; tarball extract+grep v9.88/v12.65 route inventories => pass; raw fetch v12.74 boards.js => pass; charts index.yaml appVersion resolution => pass; GitHub API tag lookups => pass; storm init/merge scaffold (/tmp/opencode/storm-runs-cf89) => pass]
deviations: none (no repo files besides RESEARCH.md touched; storm intermediates kept under /tmp/opencode per workspace convention)
friction: raw.githubusercontent served a stale/partial boards.js for one v9.88 fetch (route grep returned 0 hits); resolution: re-fetched via github archive tarballs and verified inventories there — trust only the extracted trees; searxng suggestions endpoint returned empty; used searxng_web_search + GitHub API instead.
open_questions: see §8 (version premise confirmation; bot board-admin status; label default shape; docs-refresh scope)
next_suggested: agent-plan writes the plan of record from v12.65-grounded facts (update_board=title-only via PUT …/title; swimlane sort pass-through; label bare-id response branch; members tool with username-null + note), and confirms the bot's board-admin status as an early chunk AC.
