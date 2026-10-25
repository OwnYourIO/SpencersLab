# RESEARCH — reliable default-CHECKED checklist items on WeKan card creation (v9.99 rule-race resolution)

Commissioned by agent-coord 2026-10-25. Question: make every new AI-Dev card's
Model(s) checklist arrive with `Qwen Flash` + `Local (gpu-ai)` checked, via
automation — the claim-time workaround was rejected. Method note: the topic is
deterministic source forensics (deployed v9.99 + current main), so the STORM
interview stage was realized as candidate-design evaluation against code
evidence; the contradiction map and reliability notes are kept (§Contradictions,
§Reliability). All sources read first-hand 2026-10-25; see §Sources for the
local copies (`/tmp/opencode/wekan-src/src` = v9.99 tarball,
`/tmp/opencode/wekan-main-src/wekan-main` = main tarball).

## TL;DR

1. v9.99 rule dispatch is **sequential, not parallel** — but the sequence order
   is *unspecified* (unordered Mongo cursor over triggers), so a same-activity
   `checkItem` after a same-activity `addChecklistWithItems` is order-luck, never
   a guarantee. The repo's "dispatch in parallel" note is mechanistically wrong;
   the operational conclusion (can't rely on it) stands.
2. The two-stage idea (`item-created activity → checkItem`) is **impossible on
   v9.99 and on current main**: item inserts emit `activityType:
   'addChecklistItem'` but `TriggersDef` only knows `'addedChecklistItem'` —
   a naming bug; no rule can ever fire on item creation. The `addChecklist`
   activity IS triggerable but fires *strictly before* any item exists
   (after-hooks are awaited) → EXP1-style rules are a deterministic no-op.
3. v9.99 has **no ordering/priority/delay control** at all (no sort field;
   scheduledTrigger = 1-minute cron that re-runs on matching cards every minute
   — activity-spam, disqualified).
4. **No version** (v9.99 or v12.64) has a rule action that creates checked items,
   and the REST card-create body accepts no checklists. The real native fix is
   **main/v12.x's multi-action rules** (#4294: one rule, actions run in order):
   `createCard → [addChecklistWithItems, checkItem, checkItem]` — deterministic,
   covers UI + REST; but extra actions are only creatable via the UI's
   rule-details/**Import JSON** (DDP methods), **not via REST**, even on v12.64.
5. Recommendation (hybrid now, native on upgrade): extend **wekan-mcp**
   `create_card` with a `default_checked` option (create → bounded poll for the
   rules-created checklist → PUT the two items `isFinished` — race-free by
   construction for the agent path), keep the four createCard checklist rules,
   delete EXP1/EXP2/RACE-TEST from the board, add a deterministic
   `moveCard → checkItem ×2` safety-net layer for UI-created cards; on any
   upgrade to v12.64+ replace all of it with one imported multi-action rule
   (JSON provided below).

## Q1 — Dispatch model (v9.99)

Chain: every activity write → `Activities.after.insert` →
`await RulesHelper.executeRules(activity)` (`server/models/activities.js:29-36`).
A *second* after.insert hook does notifications + outgoing webhooks for the same
activity (`server/models/activities.js:58`, webhook dispatch L388-416).

`executeRules` (`server/rulesHelper.js:89-97`) = `for` loop over
`findMatchingRules(activity)`, **each `await performAction(...)` before the next**
→ strictly sequential for one activity. Rule selection
(`rulesHelper.js:98-116`): bail immediately when
`TriggersDef[activity.activityType] === undefined` (L100-102); otherwise build
`{field: {$in: [activityValue, '*']}}` per matching field (L117-161) and query
the triggers collection. `ReactiveCacheServer.getTriggers` is
`Triggers.find(selector).fetchAsync()` **with no sort**
(`imports/reactiveCache.js:291-297` — "Server isn't reactive, so search for the
data always": server-side ReactiveCache = live Mongo reads, never stale). The
only Triggers index is `{modifiedAt:-1}` (`server/models/collectionBootstrap.js:145`),
so the $in query runs a collection scan whose order is **unspecified by contract**
(≈ insertion order while documents are never deleted/re-created; random `_id`
strings mean an index-driven order would be arbitrary). One rule = one action in
v9.99 (`getAction` → `Actions.findOne({actionId})`, `models/rules.js:70-71`; no
`extraActionIds` field exists anywhere in v9.99 — grep empty).

Async after-hooks are **awaited before the insert call resolves**: the vendored
hooks package is `matb33:collection-hooks@2.1.0` (`.meteor/versions`), whose
maintained lineage (Meteor-Community-Packages/meteor-collection-hooks, v2.1.0
tag) wraps insert so `insertAsync` returns only after
`for (const hookEntry of hooks.after) { await hookEntry.fn(...) }` completes
(`packages/meteor-collection-hooks/insert.js:56-57, 70-72` [S6]). Consequences:

- The whole rule cascade (including nested activities an action inserts —
  `addChecklist`, `addChecklistItem`, …) completes inside the originating
  insert's await chain; **effects are visible to any rule action that runs
  later in the same loop** (fresh server reads). The failure mode is purely
  *ordering*, not staleness or parallelism.
- The REST `POST /cards` handler flushes its 200 response **before** awaiting
  `cardCreation` (route at `server/models/checklists… cards.js`: `sendJsonResult`
  precedes `await cardCreation(...)`), so from the client's view the whole
  cascade still lands asynchronously after the response (~1–2 s observed —
  consistent with prior field notes [S8]).

Why the earlier experiment lost: the `createCard → checkItem{Model(s), Qwen
Flash}` rule ran while the Model(s) checklist was absent because its trigger
document was fetched before the Model(s) `addChecklistWithItems` trigger's
(unordered cursor). "Created after" ≠ "runs after". The failed rule pair has
been deleted from the board, so the alternative cause (action-string mismatch,
e.g. a `', '`-joined item list producing ` Qwen Flash` with a leading space that
never equals `checkItemName`) can no longer be separated — both are
"unreliable-by-contract", which is what matters.

## Q2 — Can a checklist-item insert trigger a rule? (two-stage)

**No — broken in v9.99 AND current main/v12.64.** `ChecklistItems.after.insert`
→ `itemCreation` inserts an activity with `activityType: 'addChecklistItem'`
(present tense) — `server/models/checklistItems.js:62-64` →
`models/checklistItems.js:113-131` (field set incl. `cardId`, `boardId`,
`checklistId`, `checklistItemId`, `checklistItemName`). `TriggersDef` keys it as
`'addedChecklistItem'` (past tense) — `server/triggersDef.js:51-54`.
`findMatchingRules` looks up the **activity's** string (`TriggersDef['addChecklistItem']
→ undefined → []`), so *no rule can ever fire on item creation*, regardless of
how the trigger doc was written (a REST trigger with `activityType:
'addedChecklistItem'` is created fine — normalization exists for it — but matches
nothing). Same mismatch at main: `models/checklistItems.js:180` vs
`server/triggersDef.js:70` — upstream-bug candidate, §Adjacent. The UI wizard
never offers the item-added trigger (`client/components/rules/triggers/checklistTriggers.js`
offers only addChecklist / removeChecklist / completeChecklist /
uncompleteChecklist / checkedItem / uncheckedItem), consistent with it being dead.

Adjacent truths that matter for chains:

- `addChecklist` IS emitted-and-triggerable (`server/models/checklists.js`
  after.insert → activity with `cardId`, `checklistId`, `checklistName`;
  `TriggersDef` has `addChecklist`). But because after-hooks are awaited, it
  fires **during** `Checklists.insertAsync`, i.e. *before* the
  `addChecklistWithItems` loop inserts even one item
  (`server/rulesHelper.js:499-516`). A `checkItem`/`checkAll` on that trigger is
  a **deterministic no-op** — explains why live-board EXP1×2 can never work.
- `checkedItem` / `uncheckedItem` ARE emitted (`publishCheckActivity`,
  `models/checklistItems.js:139-164`, via hooked `after.update`,
  `server/models/checklistItems.js:53-56`) and ARE in `TriggersDef`
  (`server/triggersDef.js:45-48`) → they work as triggers, but nothing at card
  creation ever *checks* an item, so they can't bootstrap defaults.
- The **REST item toggle** (`PUT .../items/:itemId` isFinished) writes through
  `ChecklistItems.direct.updateAsync` (`server/models/checklistItems.js:195-199`)
  — hook-bypass → **no activity, no rule re-trigger, no outgoing webhook**.
  (a) external checks never loop; (b) board automation is blind to MCP/REST
  checks — only UI checks / rule `checkItem` actions produce `checkedItem`
  activities. Asymmetry to keep in mind for any future rules on checked state.
- `checkItem`'s action fields are `{checklistName, checkItemName}`
  (`server/rulesHelper.js:456-466`) and REST persists action bodies
  un-whitelisted (`...strip(action)` spread, `server/models/rules.js:157`) →
  the live rules (get_rule shows them) are correctly shaped; their failure is
  ordering, not schema.

## Q3 — Ordering / priority / delay controls (v9.99)

- **None supported.** No sort/priority/sequence field on Triggers/Actions/Rules
  (schemas: `models/triggers.js`, `models/actions.js`, `models/rules.js`);
  dispatch order is the unordered trigger cursor (Q1). The only "control" is
  luck-of-the-draw document position; re-creating rules to fish for a favorable
  scan order is undocumented, silently broken by any later rule churn, and is
  rejected here as a design.
- `scheduledTrigger` is not activity-driven at all — evaluated by SyncedCron
  **every minute** (`server/scheduledRules.js:142-164`); kinds are calendar
  (`once/daily/weekday/weekly/monthly` at `atTime`), due-date (`set/soon/overdue` +
  days window) and aging (`daysInList ≥ days`, fractional days accepted since
  it's just a number comparison) — and `runDueTrigger` acts on **every selected
  card on every cron pass**, with dedup only per minute-slot (`lastRunKey`). A
  periodic `checkItem` therefore re-updates already-checked items every minute
  forever (hooked update → `checkedItem` activity each pass → unbounded activity
  feed/webhook growth). Disqualified as a delay mechanism.
- No `editCard` trigger exists on v9.99 — not in `TriggersDef` at all; the
  field-change activities a card edit emits (`'a-changedTitle'`,
  `'a-changedDescription'`, `server/models/cards.js`) are not triggerable either.
  (The trigger vocabulary line in `wekan-mcp-ops.md` [S8] is wrong — §Contradictions.)
- `moveCard` works and is proven on this board (the auto-label rule fires).
  `moveCard → checkItem ×2` is **deterministic** for any card whose checklists
  were created earlier (the checklist/items are long committed by first move;
  guarded lookup succeeds; repeat-moves are idempotent — re-checking a checked
  item just re-fires a `checkedItem` activity). It is the reliable native layer
  that "checking happens on first board interaction", not at creation.

## Q4 — Alternatives, and newer WeKan

- **Pre-checked creation via rules: none.** `addChecklistWithItems` hardcodes
  unchecked items (`server/rulesHelper.js:499-516`; `isFinished` defaults false,
  `models/checklistItems.js:26-32`). Full v9.99 action vocabulary
  (`rulesHelper.performAction` L162-609): moveCardToTop/Bottom, sendEmail,
  setDate/updateDate/removeDate/setDateRelative, archive/unarchive, setColor,
  addLabel/removeLabel, addMember/removeMember, checkAll/uncheckAll,
  checkItem/uncheckItem, addChecklist/removeChecklist/addChecklistWithItems,
  addSwimlane, createCard, linkCard, markCardComplete/Incomplete, sortList,
  moveAllCardsInList. No checked-items variant at either version; main adds
  `addComment`, `copyCard`, `dispatchBot`, `addAssignee/removeAssignee`,
  `removeAllLabels` (main `rulesHelper.js` grep) — still none checks items on
  add.
- **REST card create accepts no checklists** — the POST `/cards` body reads only
  title/description/swimlaneId/authorId/members/assignees/date fields
  (`server/models/cards.js`, POST `/api/boards/:boardId/lists/:listId/cards`).
  Checklists only via the separate hooked `POST .../checklists` (accepts `items`
  array or string — `server/models/checklists.js` POST route ≈L243; items arrive
  unchecked).
- **moveCard-triggered checkItem** (Q3): covers UI-created cards deterministically
  *at first move*; `editCard` cannot (no such trigger). On v9.99 a card that is
  never moved keeps unchecked defaults.
- **Outgoing-webhook listener (external, covers everything at creation):**
  `addChecklistItem` activities DO fire outgoing webhooks with
  `params.cardId`, `params.checklist` (title), `params.checklistItem` (title)
  (resolved in the notification hook, `server/models/activities.js:139-166,
  279-291, 388-416`) and — because after-hooks are awaited — the item is
  committed before its activity/webhook exists → a listener (e.g. the lab's
  deployed **n8n**) that resolves ids via GET checklists/items and PUTs
  `isFinished=true` is **deterministic for both UI- and REST-created cards**.
  Costs: board integration config, listener availability in the correctness
  path, title→id resolution per event, and the "receiver must 200 fast"
  contract (`wekan-api` skill; delivery is fire-and-forget — `safeDeliver`,
  `server/models/activities.js:398-415` — so a missed/no-retry delivery leaves
  the card unchecked).
- **Newer WeKan (main ≈ v12.64):** the genuine fix is **#4294 "Make Rules less
  clunky"** (closed 2026-10-08 by commit `f735eba`): rules gained
  **multi-trigger + multi-action documents with ordered action execution** —
  `models/lib/ruleParts.js`: "runs its actions in order — the original first"
  (`extraActionIds`, cap 10); `executeRules` → depth-guarded
  `executeRulesAtDepth` which awaits the primary action, then
  `for (const extraId of ruleActionIds(rule).slice(1)) { await performAction(...) }`
  (main `server/rulesHelper.js:~390-410`). Within one rule,
  `addChecklistWithItems → checkItem → checkItem` is **sequential and
  race-free** (the primary awaits the checklist + every item insert before
  extras run; server reads are fresh) → deterministic creation-time defaults,
  UI + REST alike, zero client code. Availability probed: `ruleActionIds` usage
  present by **v12.10**, depth guard by v12.20; latest tag **v12.64** (API tags),
  ghcr images present incl. `v12.64` (ghcr token probe). Constraints/changes on
  upgrade: REST rule endpoints still accept only ONE inline trigger+action
  (main `server/models/rules.js:153-195`); extras are creatable via
  **DDP-only** `rules.createRule` + `rules.addPart` methods
  (`server/rulesButton.js:72, 276-312`, board-admin required) — i.e. the UI rule
  editor or the board Rules→**Import JSON** flow (`client/components/rules/rulesImportExport.js:30-34,
  66-96` supports `extraTriggers`/`extraActions` in the JSON). wekan-mcp is a
  REST client → cannot create multi-action rules by API even on v12.64. Also:
  main's REST rule create/update/delete now demand **board admin**
  (`checkBoardAdmin`) where v9.99 demanded write access
  (`checkBoardWriteAccess`, v9.99 `server/models/rules.js:142,190,228`) → the
  `ai-dev-bot` must be promoted to board admin before upgrade-time rule
  maintenance. Bonus on main: cron-expression scheduled triggers, rule
  `enabled` pause flag, `textContainsTrigger`/`advancedFilterTrigger`/
  `moveCardDirection` pseudo-triggers (note: advanced-filter rules are
  re-evaluated on *every* card activity — beware repeated actions).

## Q5 — RECOMMENDATION (hybrid: robust now, native after upgrade)

**Design H (adopt now):**

1. **wekan-mcp composite (agent path, exact requirement "checked on arrival")**
   — extend `create_card` (`containers/wekan-mcp/wekan_mcp/server.py:312`) with
   an optional defaults parameter; all sequencing happens inside one awaited
   tool call, so there is no rule race at all:

   ```python
    @_write_tool
    def create_card(board_id, list_id, swimlane_id, title, description="",
                    default_checked: dict[str, list[str]] | None = None):
        # 1) POST /api/boards/{b}/lists/{l}/cards  (unchanged; rules start async)
        # 2) if default_checked: poll (0.4s x ~25)
        #      GET /api/boards/{b}/cards/{c}/checklists -> find "Model(s)" checklist
        #      GET .../checklists/{cl}                  -> items by exact title
        #    then for each wanted item: PUT .../items/{id} {"isFinished": true}
        #    (direct-update path: no activities, no rule cascade, idempotent)
        # 3) timeout -> still return the card, "defaults_pending": true in result
        #    (never self-add the checklist -- the createCard rules own creation;
        #     adding here would duplicate when rules land late)
        ...
    ```
   Failure modes: rules engine misconfigured/deleted → timeout surfaces
   `defaults_pending` (visible, alertable) instead of silent wrong state;
   WeKan restart mid-poll → same; exact-title drift between rule item list and
   the tool's `default_checked` values → maintenance coupling (both live in
   this repo: runbook table + boards skill; keep one source, assert in tests).

2. **Board rules (v9.99 as deployed):** keep the four
   `createCard → addChecklistWithItems` rules (proven, cover UI+REST item sets).
   **Remove** EXP1×2 (deterministic no-op, Q2), RACE-TEST (order-luck, Q1), and
   EXP2×2 (currently *probably works* — the Model(s) rule lands before the
   Research rule in scan order because the runbook created them in that order —
   but that is insertion-order luck with no contract; keeping it means defaults
   silently stop on any rule churn; remove, and replace with:)
   **`moveCard → checkItem ×2`** rules:

   ```json
   {"title":"Defaults: check Qwen Flash on move",
    "trigger":{"activityType":"moveCard","boardId":"*","listName":"*","oldListName":"*","userId":"*","swimlaneName":"*","cardTitle":"*"},
    "action":{"actionType":"checkItem","checklistName":"Model(s)","checkItemName":"Qwen Flash"}}
   // + twin for {"checkItemName":"Local (gpu-ai)"}
   ```

   Deterministic for any card that ever moves (pipeline cards all move; UI
   cards move on the first drag). Side effect: repeat moves re-fire harmless
   idempotent checks + one `checkedItem` activity each. Cards never moved and
   never agent-created stay unchecked until moved — the accepted v9.99 gap
   (closing it natively = upgrade; closing it now = optional n8n listener, Q4).

3. **Upgrade track (the real "automation fix", both paths at creation):** when
   the home WeKan moves from v9.99 to v12.64+ (two majors — its own ticket;
   check `ghcr.io/wekan/wekan:v12.64` digest + migration notes), create ONE
   rule via board Rules → Import JSON (user-owned, board admin; the bot is not
   needed for this step):

   ```json
   [{
     "title": "Std checklists: Model(s) + defaults",
     "trigger": {"activityType": "createCard"},
     "action":  {"actionType": "addChecklistWithItems", "checklistName": "Model(s)",
                  "checklistItems": "Qwen Large,Qwen 27b,Qwen Flash,Local (gpu-ai)"},
     "extraActions": [
       {"actionType": "checkItem", "checklistName": "Model(s)", "checkItemName": "Qwen Flash"},
       {"actionType": "checkItem", "checklistName": "Model(s)", "checkItemName": "Local (gpu-ai)"}
     ]
   }]
   ```

   (Omitted trigger matchers normalize to `'*'` client-side on import
   (`TRIGGER_MATCHING_FIELDS` defaulting, `rulesImportExport.js:59-84`) and
   server-side on REST — either path safe.) Then retire the per-checklist rules
   into the same rule's `extraActions` if desired (cap 10 extras: 4 checklists +
   2 checks fits). Post-upgrade, delete the moveCard safety-net rules and drop
   `default_checked` from the agent flow (or keep the tool parameter as a
   zero-cost belt — the first poll resolves instantly). Verify via `list_rules`
   / GET rule that `extraActions` are present and ordered (serialization in main
   `server/models/rules.js:79-93` exposes them read-only).

Rejected candidates, with reason: same-activity `createCard→checkItem` rule
(order luck, Q1); EXP1/`addChecklist→checkItem` (deterministic pre-item fire,
Q2); two-stage `addedChecklistItem` trigger (activityType naming bug, dead in
both versions, Q2); scheduled/aging trigger as a delay (minute-level,
repeat-forever side effects, Q3); claim-time pipeline check (user-rejected);
vendor-patching the image (out of policy).

**Why the composite is acceptable even for "real automation":** the checklist
*content* stays automation-owned (board rules, both creation paths); the tool
only resolves the checked state it created cards for — no consuming-flow logic
(pickup/pruning/model routing unchanged; D12 routing reads checklist state
regardless of who checked it).

## Implications for the plan (what the planner should do differently)

- Correct `skills/wekan-api/references/wekan-mcp-ops.md` (via its owning track):
  "dispatch in parallel" → "sequential, unspecified order"; drop `editCard` from
  the trigger vocabulary; record the `addChecklistItem` vs `addedChecklistItem`
  naming bug and the EXP1 deterministic-failure proof.
- Plan new chunks: C-boards-intake — (a) wekan-mcp `create_card` `default_checked`
  + container test (extend `tests/containers/wekan-mcp-login.sh` pattern /
  `tests/wekan-mcp/tools.sh`), (b) board mutation step in the runbook: remove
  EXP1/EXP2/RACE-TEST, add moveCard→checkItem×2 (user go per D5 — board
  mutations stay deferred/user-owned until approved), (c) boards-skill note:
  agent-created cards arrive with the two defaults pre-checked; the claim-side
  model-pruning already keeps checked survivors (no change needed — verify
  against D12 wording).
- STATE/DECISIONS: record that the live AI-Dev board NOW EXISTS
  (`TNQJ2BrXenZovngTS`, 10 rules inventoried 2026-10-25) — several friction/
  prerequisite notes (board absent) are stale.
- Upgrade consideration: v12.64 multi-action rule is the long-term fix; if the
  user prefers to skip the hybrid, an accelerated WeKan upgrade + the Import-JSON
  rule achieves the requirement natively for both paths — that's a user infra
  decision, not a pipeline chunk.

## Contradictions / corrections to earlier notes

- **[S8] "Rules matching one activity dispatch in parallel"** vs source:
  sequential (`rulesHelper.js:91-96` awaits each action; hooks awaited, [S6]).
  Weighted: the empirical outcome ("can't rely on same-activity check") holds;
  the mechanism is *unordered sequence*, which changes what fixes exist (order
  roulette works-but-is-luck; no staleness excuse).
- **[S8] trigger vocabulary incl. `editCard`** vs `TriggersDef@v9.99` (no
  editCard; `scheduledTrigger`/`button` intentionally non-activity —
  `server/triggersDef.js:1-5` header comment). REST accepts any activityType
  (no whitelist) — inert for unknown ones (Q1 selection gate L100).
- Prior empirical "never fired" (created-after ⇒ runs-after assumption) —
  corrected: creation order does not imply dispatch order; exact failed-rule
  diagnosis unrecoverable (deleted before this snapshot).
- All-agree points (high confidence): same-activity unreliability; no v9.99
  native creation-time checked-item path; v12 multi-action ordering is the
  native fix; REST cannot create pre-checked state.
- Blind spot checked late but covered: hook-await semantics ([S6] v2.1.0 tag
  matches deployed `.meteor/versions`), which is what proves EXP1 is
  deterministic-dead rather than racy.

## Risks

- **v9.99 rule-order luck is load-bearing elsewhere:** the four Std checklist
  rules don't depend on order (each inserts a distinct checklist; duplicate
  titles would only confuse later `getChecklist{title}` lookups if a rule were
  duplicated), but any FUTURE same-activity chaining is unsafe — encode as a
  DECISIONS entry.
- EXP2×2 currently live: if they have been "working", removing them removes
  defaults until the new layers land — sequence the board mutations
  (add moveCard rules + merge the tool FIRST, then delete EXP rules) and
  verify with one disposable card between steps.
- Tool timeout policy: `defaults_pending` is a silent-ish degradation — the
  boards skill should treat pending as re-check-on-claim fallback (belt), which
  the user tolerated as a safety net vs. as the primary mechanism.
- Upgrade path: v9.99→v12.64 crosses majors (Meteo 3/DB migrations; FerretDB
  variant); rule REST writes need bot board-admin; `extraActions` are UI/DDP-
  only creations — any MCP `create_rule`-based automation of them is
  impossible today; if we later want MCP-managed multi-action rules, that's an
  upstream REST feature request (adjacent).
- n8n-listener option (if ever taken): delivery is fire-and-forget (`safeDeliver`)
  — missed events leave cards unchecked (no replay); receiver must 200 instantly
  or activity processing stalls.

## Verification plan (live board; mutations = disposable cards, clearly marked, user go-ahead per D5)

1. **V0 read-only (done):** rule inventory snapshot this run (10 rules: 4 Std
   createCard incl. Model(s) items `Qwen Large,Qwen 27b,Qwen Flash,Local (gpu-ai)`;
   1 moveCard→addLabel Research; EXP1×2 `addChecklist{Model(s)}→checkItem`;
   EXP2×2 `addChecklist{Research}→checkItem{Model(s)}`; RACE-TEST
   `createCard→checkItem`). Re-run `list_rules` after each change step.
2. **V1 baseline (1 disposable card, REST path):** create card
   `DISPOSABLE-research-baseline (delete after)` in Not Started; sleep ~3 s;
   `list_checklists` + `get_checklist Model(s)`: expect 4 checklists, 4 exact
   item titles (byte-check leading spaces), and record whether the two defaults
   are checked (this exposes the current EXP2 luck-order — a positive here is
   NOT evidence of reliability, only of current cursor order).
3. **V2 mutation-order test (proves Q1):** `update_rule`-recreate only the
   RACE-TEST rule (new random `_id`/record position); re-run V1; compare checked
   state. Flipping outcomes across recreations demonstrate non-contractual
   ordering without touching the Std rules. (Delete the recreated rule after.)
4. **V3 composite tool (post-implementation, dev-boards):** call
   `create_card` with `default_checked` → on return, immediately `get_checklist`:
   both items checked (tool returns only after PUTs land) → create twice → assert
   exactly one Model(s) checklist (no duplication) and still-checked (idempotent).
   Force timeout path (temporarily pause Std Model(s) rule — needs `enabled` on
   v12 or rule delete/re-add on v9.99 — optional) → assert `defaults_pending`.
5. **V4 UI leg (human):** create card in the UI (board Settings → Rules visible)
   → move it once → both defaults checked (moveCard layer); move again → still
   exactly checked (idempotency).
6. **V5 upgrade-era (v12.64):** GET rule JSON shows `extraActions` ordered;
   disposable UI-created card → defaults checked at creation, no move needed;
   delete/retire safety-net rules last.
   No side effects: cards never named like real tickets, prefixed
   `DISPOSABLE-*`, removed by the user afterwards.

## Adjacent findings (out of scope, worth logging)

- **Upstream bug candidates** (file-able): (1) `addChecklistItem` vs
  `addedChecklistItem` naming mismatch makes the checklist-item-added trigger
  family dead in v9.99→main (`models/checklistItems.js` vs `server/triggersDef.js`
  at both refs); (2) `TriggersDef`'s `addedChecklistItem` key + `checklistItemName`
  matcher exist but nothing emits that activityType; (3) wizard/`checklistTriggers.js`
  offers `checkedItem`-style triggers that work — the dead one is invisible in UI.
- v12.64 rule engine additions to know before an upgrade ticket: rule `enabled`
  pause; DDP `rules.createRule/addPart/removePart/setEnabled` (board-admin);
  rule history (`server/lib/ruleHistory`); `dispatchBot` action (integration-
  based bot dispatch — could one day replace board→pipeline polling);
  cron-expression schedules; REST rule writes now require board admin.
- The live Services rule's items grew beyond the runbook table (now 15 items,
  incl. `home-assistant`, `agent context`) and Research items changed to
  `before planning,after planning,agent decides` — runbook/boards-skill drift;
  fix in the owning chunk, not here.

## Sources (all read 2026-10-25)

- [S1] wekan@**v9.99** source — `codeload` tarball, local
  `/tmp/opencode/wekan-src/src`. Cited: `server/models/activities.js`,
  `server/rulesHelper.js`, `server/triggersDef.js`, `server/models/rules.js`,
  `server/models/checklistItems.js`, `server/models/checklists.js`,
  `models/checklistItems.js`, `models/triggers.js`, `models/actions.js`,
  `imports/reactiveCache.js`, `.meteor/packages`, `.meteor/versions`.
- [S2] wekan@**main** (2026-10-25) — tarball `/tmp/opencode/wekan-main-src/wekan-main`
  + raw fetches: `server/triggersDef.js`, `server/rulesHelper.js`,
  `server/models/rules.js`, `server/rulesButton.js`, `models/rules.js`,
  `models/checklistItems.js`, `models/lib/ruleParts.js`,
  `client/components/rules/{ruleDetails,rulesImportExport,triggers/checklistTriggers}.js`,
  `server/scheduledRules.js`, `docs/Features/Rules/Rules/Rules.md`,
  `docs/DeveloperDocs/Open-Issue-Completion-Audit-2026-09.md`.
- [S3] GitHub API — tags list (latest **v12.64**), issue **#4294** (closed
  2026-10-08, commit `f735eba`), issue-search (`addedChecklistItem` → no hits),
  `contents`/`compare`/`commits` probes; tag-anchored presence probe:
  `models/lib/ruleParts.js` absent@v9.99, `ruleActionIds` usage@v12.10,
  `executeRulesAtDepth`@v12.20.
- [S4] ghcr.io anonymous token + tags/list probe: `wekan/wekan` has 780 tags
  incl. `v9.99` and `v12.64`.
- [S6] Meteor-Community-Packages/meteor-collection-hooks @ tag **v2.1.0** (==
  `matb33:collection-hooks@2.1.0` in v9.99 `.meteor/versions`):
  `packages/meteor-collection-hooks/insert.js:8-72` — after-hooks awaited.
- [S7] live AI-Dev board `TNQJ2BrXenZovngTS` — `dev-boards` MCP
  `list_boards`/`list_rules` (read-only) 2026-10-25.
- [S8] repo prior art: `skills/wekan-api/references/wekan-mcp-ops.md` (race
  observation — refined here), ticket
  `2026-10-24-…-research.md`/runbook/DECISIONS (D5, D12), containers/wekan-mcp
  `wekan_mcp/server.py` (tool surface: create_card L312, add_checklist L388,
  toggle_checklist_item L403, create_rule L461).
- [S9] wekan.fi/install (current WeKan Server line v12.6x) — corroborates [S3]/[S4].

## Reliability notes (peer review)

- Same-activity dispatch = sequential, unordered — **9/10** (direct code,
  multiple files; only the *reason* of the original failure is inferred).
- `addChecklistItem`/`addedChecklistItem` mismatch ⇒ item-added trigger dead at
  both refs — **10/10** (grep-complete: single emitter, single def key; selection
  gate provable).
- EXP1 deterministically no-op (addChecklist fires pre-items) — **8/10**
  (rests on [S6] awaited-after-hooks; residual: hooks version drift between the
  2.1.0 tag and the exact built artifact — deployable to re-prove live via V1/V2).
- v12 multi-action rule is deterministic — **9/10** (code-verified ordering; not
  live-tested here; V5 closes).
- Weakest claim: "moveCard→checkItem covers UI cards" — true but *only on first
  move*; a never-moved UI card shows unchecked defaults. The claim "composite
  tool makes agent path fully reliable" — **8/10**: relies on rules eventually
  creating the checklist (timeout+pending covers the rest). A 6th angle (card
  *templates*/`copyCard`-from-template preserving `isFinished`) was not pursued:
  v9.99 lacks both; on main, `copyCard` duplicates the card rather than applying
  a template to it — dead end for arrival-state of the created card.

```
RESULT
status: DONE
chunk: research
files_changed: [.agents/plans/2026/2026-10-feat-board-coord-intake/RESEARCH.md]
commands_run: [wekan v9.99+main source forensics (tarballs + raw API) => pass; GitHub API tags/issues/compare probes => pass; ghcr tags probe => pass; dev-boards list_rules read-only snapshot => pass; live-board mutations => NOT RUN (read-only mandate)]
deviations: STORM interviews realized as candidate-design evaluation against primary source (code-forensics topic); no board mutations, verification left as a plan (V1–V5) with disposable-card markers per D5.
friction: launch notes said GitHub raw blocked — it is reachable via curl (raw + codeload), enabling full tarballs (used as ground truth); wekan-mcp-ops.md's trigger vocabulary/parallel-dispatch lines proved wrong (corrected, needs upstream doc fix).
open_questions: (1) user go-ahead for the board-mutation sequence in Design H (remove EXP1/EXP2/RACE-TEST, add moveCard→checkItem×2) — and whether to run V1's disposable card now; (2) accept the v9.99 UI-card gap until first move, or commission the n8n webhook listener / accelerate WeKan v12.64 upgrade; (3) confirm wekan-mcp `create_card default_checked` extension is in-scope for this ticket or its own chunk/ticket.
next_suggested: planner folds Design H into the plan as new chunks (tool + runbook step + boards-skill note); coord runs the V1 baseline with the user before board mutations; file the upstream trigger-mismatch issue separately if the user wants it tracked.
```
