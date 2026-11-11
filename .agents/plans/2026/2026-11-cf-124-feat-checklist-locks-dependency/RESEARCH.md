# RESEARCH — can the owner's card defaults be real in deployed upstream WeKan, and by which mechanism?

Pre-Research round for cf-124, run 2026-11-10/11 by `agent-research`. Reads EXPLORE.md first (repo-side ground truth, cited as [L8] etc.). Nothing was mutated: upstream reads are raw-file/API fetches, the one cluster read is the readonly home MCP, the board itself was not touched.

## Method note

1. **Pin established first** (the launch's "believed v12.6x" is stale): `services/home/prod/Chart.yaml` pins the WeKan Helm chart `12.77.0` for both frontends (`wekan` + alias `boards`) with `Chart.lock` matching; the bump chain is 12.64.0 → 12.65.0 (`c96a6a824`) → **12.77.0 (`d8b12fd0f`, 2026-11-01)**, Renovate PRs [1]. A live read of the home cluster shows both deployments `home-wekan` and `home-boards` on image **`ghcr.io/wekan/wekan:v12.77`**, ready 1/1 [2]. Upstream's latest release is **v13.06** [3]. So: pin = live = v12.77; master ≈ v13.06.
2. **Byte-level upstream verification at five refs** — v9.99 (the lab's pre-upgrade version), v12.65, v12.77 (the pin), v13.06, `master` — for every file that answers a sub-question: `server/rulesHelper.js`, `server/notifications/storedRulePlans.js`, `server/triggersDef.js`, `imports/reactiveCache.js`, `models/checklists.js`, `models/checklistItems.js`, `server/models/checklists.js`, `server/models/checklistItems.js`, `server/models/cards.js`, `server/models/customFields.js`, `server/models/rules.js`, `server/models/dependencies.js`, `models/metadata/dependencies.js`, `models/lib/checklistTemplateCopy.js`, the rules-import client, and the v12.77 `docs/API/*` + `docs/Features/*` docs. Line numbers quoted below are the file at the ref stated. Notable: `server/rulesHelper.js` is **md5-identical between v12.65 and v12.77** (`b80afdcb014cc9f2b33afbc885f7921d`) — the rules engine did not move across the lab's 65→77 upgrade [4][5].
3. **Upstream issue/PR discovery** — GitHub issue-search API (14 keyword sets: `checkListId`, `checkItem`, `uncheckItem`, "check item" rule, rule action checklist item, custom field rule, custom field default, …), direct fetches of every candidate issue (#1396, #3195, #6806, #6816, #1037, #6544, #4017, #3392, #4294), and a SearxNG sweep as a non-GitHub cross-check [29][32].
4. **Lab-side cross-checks** — the v12-upgrade ticket's own forensics [7], the wekan-api skill ops doc [9], and the deployed wekan-mcp source [10] for what our engine actually speaks today.
Where a claim could not be sourced it is marked **unverified**.

---

## 0. Headline

The pin is v12.77 (not v12.6x). On it and through upstream `master` (v13.06 era, 2026-11-11):

* the rule `checkItem`/`uncheckItem` actions are **still dead** — same `checkListId` typo, **still unfixed and apparently still unfiled upstream**;
* rules have **never had and still lack** any custom-field write action, and WeKan has no default-value concept for custom fields at all;
* checklist structure on existing cards is fully mutable **per card** over REST (rename ✓, add item with explicit sort ✓), with **no cross-card / "all cards carrying checklist X" API** at any layer;
* Red Strings dependency types are a **fixed closed set**, stored **only on the source card**, with **zero server-side semantics** — all gating in the lab is consumer-side doctrine, which the plan is free to redefine.

---

## 1. Rule-driven checklist defaults at card creation

### (a) Does a working "check checklist item" action exist on the pin / on current main?

The action **exists in the vocabulary and in the UI wizard** at v12.77 and at `master` — `checkItem`/`uncheckItem` are listed in the official action table in `docs/API/Rules.md` @v12.77 [12] and implemented in `server/rulesHelper.js` `performAction` (`checkItem` v12.77 L1045-1054, `uncheckItem` L1056-1066; master L1048-1070) and selectable in the rules wizard (`client/components/rules/actions/checklistActions.jade` @v12.77, `check-item-action` block) [13].

But the action is **100% inert** on both refs. Its item lookup queries `{title: <item>, checkListId: <id>}` (capital L, v12.77 L1049 checkItem / L1060 uncheckItem; v13.06 and master L1052/L1063) while `ChecklistItems` documents store `checklistId` (lowercase, schema `models/checklistItems.js` @v12.77 L44-48) [5][6][14]. `ReactiveCache.getChecklistItem` is a **pass-through** — it hands the selector straight to `ChecklistItems.findOneAsync` (`imports/reactiveCache.js` @v12.77 L127-130), no key normalization anywhere — so the query targets a field that never exists and can never match [15]. The asymmetry with the working bulk actions is real: `checkAll`/`uncheckAll` resolve items via `getChecklistItems({checklistId})` (correct spelling, v12.77 rulesHelper L1031-1043, and `models/lib/checklistBulkCheck.js` filters on `item.checklistId`) [16]. The lab's own discriminating probes on the live board (addComment→checkItem silent no-op vs addComment→checkAll FIRED) already proved this empirically on v12.64 [7].

**Verdict:** a working `checkItem` action does not exist in v12.77 nor in current `master`.

### (b) What exactly is the known bug; is it filed; is it fixed; in which release?

**Exactly:** the field-name typo `checkListId` vs stored `checklistId`, in **three** places, each verified present at **v9.99, v12.65, v12.77, v13.06 and `master`** (fetched 2026-11-11):

| spot | v9.99 | v12.65 | v12.77 | master |
|---|---|---|---|---|
| `server/rulesHelper.js` `checkItem` | L463 | L1049 | L1049 | L1052 |
| `server/rulesHelper.js` `uncheckItem` | L474 | L1060 | L1060 | L1063 |
| `server/notifications/storedRulePlans.js` (durable-plan capture for the sync/checklist path — `targetIds` stays empty, so the saved command checks nothing) | — | L1665 | L1665 | L1665 |

[4][5][6][17] The typo predates the v12 line entirely (v9.99 carries it), so the defaults have never worked on any version this lab has run.

**Filed?** **No — not found.** GitHub issue+PR search over `wekan/wekan` (2026-11-11) for `checkListId`, `checkItem`, `uncheckItem`, "check item" rule, "rule action" checklist item — 14+ hits, **none about this bug** (closest are #6816 "Deleting a checklist leaves its items behind", fixed 2026-10-27, and the 2017 route copy-paste #1396 — neither this) [29]. A SearxNG sweep found nothing outside GitHub either [32]. Consistent: the upgrade ticket left "file the upstream issue/PR" as an open user decision (2026-10-26) [7] and nobody filed it since.

**Fixed?** **No** — not in v12.77 (the pin), not in v13.06 (latest release), not in `master`; no open PR touches those lines. **Fix version: none exists.** The v12.77→master diff of `rulesHelper.js` is one unrelated date-clear fix (#2474) [5].

### (c) Is the dormancy instead the historical race? Does upstream order rule actions?

**No — the race is not the explanation, and rule actions ARE ordered where it matters.** Three separate facts, all re-verified at v12.77:

1. **Within one rule, actions run strictly sequentially.** `executeRulesAtDepth` awaits the rule's primary action, then `await`s each extra in stored order (`server/rulesHelper.js` @v12.77 L392-410; the L402 comment cites #4294 "further actions run in order after the rule's own action"). The multi-action rule (`extraActionIds`, ≤10) landed with #4294 (closed 2026-10-08; the upgrade ticket's tag probe dated availability from v12.10, depth guard from v12.20) [7][11][28]. Since `addChecklistWithItems` awaits its checklist AND item inserts before returning (v12.77 rulesHelper L1090-1108), a `checkItem` extra placed after it in the **same** rule runs with the items already present. The lab's dense single-rule artifact has the right shape already.
2. **Across rules, order remains undefined** — trigger selection still fetches **unsorted** (`imports/reactiveCache.js` @v12.77 `getTriggers` L310-316). The owner's remembered race is real but belongs to the v9.99 era of five separate one-action createCard rules + the separate checkItem rule (ops-doc finding, reproduced on the live board then) [9]. It cannot explain today's dormancy, and the probes settle it: `checkItem` no-ops even against a **pre-existing** checklist on a human-triggered card — no creation involved [7].
3. **Two-stage "check the item when it appears" rules can never fire, still:** checklist-item inserts emit activityType `addChecklistItem` (`models/checklistItems.js` @v12.77 L180) while the trigger definition only knows `addedChecklistItem` (`server/triggersDef.js` @v12.77 L70; the docs/API trigger table repeats it) [18][12]. The v9.99-era dead-code note in the ops doc stands unchanged on the pin [9].

Also confirmed on the pin, for the artifact question: rules fire for **REST- and bulk-created** cards too — the REST/bulk create routes call `cardCreation()` which inserts the `createCard` activity (`server/models/cards.js` @v12.77 L1560, bulk ~L1671), and `Activities.after.insert` runs `RulesHelper.executeRules` (with the `deferSyncActivity('rules')` skip for plan-written activities) (`server/models/activities.js` @v12.77 L58-66) [26].

---

## 2. Rule-driven custom-field defaults (Priority = 5 on create)

### (a) Can a rule set a custom-field value on card creation in v12.6x / current main? If not, what are the real paths?

**No, at neither ref.** The complete `actionType` vocabulary of the engine — enumerated from `performAction` at `master` and cross-checked against `docs/API/Rules.md` @v12.77 — is: `moveCardToTop/Bottom, sendEmail, setDate, updateDate, removeDate, setDateRelative, archive, unarchive, setColor, addLabel, removeLabel, removeAllLabels, addMember, removeMember, addAssignee, removeAssignee, checkAll, uncheckAll, checkItem, uncheckItem, addChecklist, removeChecklist, addSwimlane, addChecklistWithItems, createCard, dispatchBot, addComment, copyCard, linkCard, markCardComplete, markCardIncomplete, sortList, moveAllCardsInList` [12][19]. **There is no custom-field write action.** Custom fields appear in the engine only as **read-only substitution variables** (`{customField:Name}`, `vars.customfield` built by `buildCustomFieldsWD`, rulesHelper @v12.77 L141-176) — a rule can put a field's current value into a comment/title/list name, never set one. The engine's own `createCard` action inserts only `{title, listId, swimlaneId, sort, boardId}` (rulesHelper @master L1110-1119) — no fields, no checklists.

The real paths on the pin (v12.77 `server/models/cards.js`):

1. **Attach-at-creation is automatic, value-less.** Both REST create routes build `customFields: [{_id, value: null}]` for every board field flagged `automaticallyOnCard || alwaysOnCard` at insert (L1496-1502 single, L1607-1613 bulk `POST …/cards/bulk`, #4743, ≤500) — **the create body's own `customFields` is ignored** (insert sets `customFields: customFieldsArr`, L1528-1556) [26]. So "the field is on every new card" is achievable purely by the field flag (REST-mutable: `PUT /api/boards/:boardId/custom-fields/:id` accepts both flags @v12.77 `server/models/customFields.js` L195-199; POST accepts `automaticallyOnCard` L139 [27]) — but the value lands `null`.
2. **Value = a per-card write after creation.** `PUT /api/boards/:boardId/cards/:cardId` with a full `customFields` array `$set`s it directly (`server/models/cards.js` @v12.77 L1905-1913, with linked-field propagation #5681) — the documented write shape (`docs/API/Custom-Fields.md` §4: `{"customFields":[{"_id":…,"value":…}]}`) [33]. Our MCP's `set_card_custom_field` is exactly this upsert, attach-if-missing [10]. The dedicated value route `PUT …/cards/:cardId/customFields/:customFieldId` (L2388) only rewrites **already-attached** entries [26].
3. **No platform default-value concept exists.** The `CustomFields` schema (@v12.77 `models/customFields.js`) has `automaticallyOnCard`/`alwaysOnCard`/`showOnCard`/`readOnly`/`adminOnly`/… and **no `defaultValue` field** [27]. Card templates: a copied card keeps custom-field values (`Cards.copy()` maps them to the target board, `models/cards.js` @v12.77 L1253/L1321) — but that is the UI/Meteor `copyCard` path (`server/models/cards.js` L835), not a REST rule; template boards themselves are group-shared board blueprints (`docs/Features/All-Boards/Templates.md`), not per-card defaults [23].
4. **Coercion caveat:** values are written as given — for the NUMBER `Priority`, the write must send a number, not `"5"` (ops-doc learning, unchanged; the PUT handler does no coercion) [9][26].

Note for the plan's framing (EXPLORE §4 [8]): unset already resolves to the default serving class (vLLM priority 5), so "default 5" is visibility/bookkeeping, not behavior.

### (b) Upstream issues/PRs for custom-field defaults in rules?

* **#3195 "{question/feature} Custom field values for rule values"** (opened 2020-06-27) — **closed as completed 2026-09-29**; the completed scope is the **read** side (`{customField:Name}` substitution, #3195/#4294 cited verbatim in rulesHelper @v12.77 L262/L956). Not a write action [30][19].
* **#6806 "v12.65: Option to always show selected empty fields on opened cards (board-wide default)"** — **closed completed 2026-10-26**; resolved as a **display**-default only (which empty sections an opened card shows), not field values [30].
* Searches for "custom field rule action", "custom field default value" + rules, and a web sweep found **no open FR** for rule-set field values [29][32].

---

## 3. Bulk mutation of EXISTING cards' checklists (the 90-card backfill)

### (a) v12.77 REST/MCP capabilities for checklist structural change; any "board-level checklist" propagation?

Full REST surface at v12.77 (`server/models/checklists.js` + `server/models/checklistItems.js`, route strings at L180/214/251/319/374 and L106/135/195/258; auth = board write access): [20][21]

| change | route | notes |
|---|---|---|
| rename checklist (structure-preserving!) | `PUT /api/boards/:b/cards/:c/checklists/:cl` body `{title}` (+optional `dueAt`) | the #1037 addition ("Before this a client had to delete and re-create it, losing the checklistId and its items" — the in-code comment); present since ≤v12.65 [20][28] |
| create checklist with items | `POST …/checklists` `{title, items:[strings], dueAt?}` | v12.77 items are a **string array** (historical `{title}` objects in `docs/API/Checklists.md` are called out as outdated) [22] |
| add item | `POST …/checklists/:cl/items` `{title, sort?, dueAt?}` | append by default; **explicit `sort` wins** (#6544 comment: "for a caller that is rebuilding a checklist in a known order") [21][28] |
| edit item title / tick | `PUT …/items/:item` `{title?, isFinished?, dueAt?}` | **no `sort` accepted — there is no reorder API** [21] |
| delete item | `DELETE …/items/:item` | |
| delete checklist | `DELETE …/checklists/:cl` | **cascades all items** via `Checklists.after.remove` (#6816, fixed 2026-10-27, present at v12.77) [20][30] |

**No cross-card / board-level checklist exists.** Checklists are per-card documents only; there is no board-level checklist entity, no propagation from checklist to board, no bulk-checklist REST endpoint (the only bulk endpoint is cards — `POST …/cards/bulk` #4743 [26]). Closest things upstream:

* **"Copy Checklist From Template" (#4017, closed 2026-09-10)** — appends ALL of a source/template card's checklists onto **one** existing card: fresh ids, placed after the card's own checklists, existing ones untouched, and **items always copied UNCHECKED** ("a template being applied should never pre-check its target") (`models/lib/checklistTemplateCopy.js`, `Checklists.copyAllFromCardToCard` @v12.77 L354; UI popup wiring `client/components/cards/checklists.js` L925-947). **UI/client-side only — no REST route**, and it duplicates rather than merges, so it is useless for expanding an existing 11-item Lifecycle on 90 cards [24][25].
* **"Edit items as text" (#4218)** — one checklist, whole item list edited as a `[x] title` textarea (`models/lib/checklistItemsAsText.js` @v12.77 header) — a human convenience (90 popups), not an API [31].
* Trello-compat API checklists are card-scoped proxies over the same routes (`server/compatApi/trello.js` @v12.77 L204-216) — nothing new [34].

**MCP surface (deployed, 39 tools)** covers per-card work: `add_checklist(title, items[])`, `add_checklist_item` (title only — **no sort param**, appends), `toggle_checklist_item`, `delete_checklist_item` (`server.py` L789-858) [10]. **Rename/delete-checklist and item-`sort` are NOT exposed** — those legs need raw REST (the same token/auth `_wekan` uses) or a wekan-mcp tool extension.

→ Backfill on 90 cards = **a per-card REST loop**: per card, locate the Lifecycle/HITL checklist ids, `POST …/items` twice with `sort:-2`/`-1` for the two new leading items, per-item `PUT` for any reword, `set_card_custom_field` for Priority. No single-call bulk exists; the loop is the designed path.

### (b) Item ORDER control (new items must be FIRST) — what exists, and what does it key on?

Order is the numeric `sort` field on checklist items (schema `sort` Number, `models/checklistItems.js` @v12.77 L19-23), and consumers render `sort`-ascending (`Checklists.items()` sorts `['sort']`, `models/checklists.js` @v12.77 L207-210) [14]. Controls at the pin:

* **At insert**: `POST …/items` honors an explicit body `sort` — including negatives (only non-finite falls back to append) (#6544 fix, v12.77 `server/models/checklistItems.js` L150-170) [21][28]. **This is the backfill answer: insert `Session Rename`/`Worktree Creation` with `sort:-2`/`-1` and they render before the existing `sort:0..10` items, per card, no rebuild.**
* **No reorder API**: item `PUT` accepts only `title`/`isFinished`/`dueAt` (L195+); dragging is a client-side collection write; "edit as text" rebuilds client-side [21][31].
* Checklist-level order (checklist vs checklist) has the same shape: `Checklists` carries `sort`, REST create pins `sort:0`, and template-copy appends after the last (`firstAppendSort`) [14][24].

### (c) Delete/re-add a checklist: what happens to per-item tick state on the 90 cards?

**All tick state (and item ids, dueAt, assignees) is destroyed.** `DELETE …/checklists/:cl` runs the `#6816` `after.remove` hook that removes every item (`ChecklistItems.direct.removeAsync({checklistId})`, v12.77 `server/models/checklists.js` L170-178); the re-added checklist is a new document whose items arrive unchecked (that is also the invariant every template-copy path enforces). Before #6816 deletion orphaned the rows — equally no recovery. **Rule for the plan: mutate in place (rename + sorted inserts + toggles), never delete-and-re-add.**

### (d) Do card templates / swimlane or list defaults offer a cleaner path?

No. Templates are **template boards**, group-shared (Orgs/Teams/Domains), used at board-creation or whole-board copy (`docs/Features/All-Boards/Templates.md`, #2209; the doc's "Copy Checklist Template to Many Cards" bullet is the UI copy flows above, and "Import and Export Checklists" #904 is listed as **unfunded/not implemented**) [23]. Card copy preserves checklists and field values but is UI/Meteor-only (§2a.3). There are no swimlane/list defaults in WeKan at all (lists carry no checklist/field payload — `docs/API/Lists.md` surface). For agent- and engine-driven maintenance the per-card REST loop stays the only path.

---

## 4. `checklist` vs `checkList` naming drift — what each surface actually accepts

Verified spellings at v12.77 (same at master):

| surface | spelling | evidence |
|---|---|---|
| Stored item schema | `checklistId` (lowercase l) | `models/checklistItems.js` L44 [14] |
| REST paths + params | `/checklists/:checklistId/…` | route strings [20][21] |
| Rule action payloads (accepted + stored + what the wizard writes) | `checklistName`, `checklistItems`, `checkItemName` — all lowercase; NO id field is part of an action payload | dense artifact reads back live [3]; rulesHelper reads `action.checklistName`/`action.checkItemName` [5]; docs [12] |
| The broken internal selector | `checkListId` (capital L) — **exists nowhere except** the 3 typo'd lookups (§1b) and harmless JS locals inside `addChecklistWithItems` (a local var named `checkListId` that correctly writes `checklistId:` fields) | [5][17] |
| Activities/triggers | trigger name `addedChecklistItem` vs emitted `addChecklistItem` (dead trigger, §1c) | [18] |
| Trello-compat API | `checklists`/`checklistId` (Trello style) | [34] |
| Lab MCP tools | snake_case `checklist*`/`add_checklist_item` | [10] |

**For the plan:** everything the engine or an artifact *sends* must use lowercase-`l` keys — and note the trap: a `checkItem` action written with correct payload keys is STILL inert, because the bug is inside the server (sending `checkListId` in a payload would not fix anything; inventing an id-keyed payload just fails schema-free storage differently). Cheap regression for the suites: assert the literal `checkListId` appears **nowhere** in any generated rules artifact (cf-96-style grep), and remember `addChecklistWithItems` items are split on `,` with **no trim** (ops doc; still true, v12.77 rulesHelper L1100 `split(',')`) [9][5].

---

## 5. Dependency ("Red Strings") edges

### (a) Fixed types or free text?

**Fixed closed set of seven**, in shared metadata `models/metadata/dependencies.js` @v12.77: `related-to, blocks, is-blocked-by, fixes, is-fixed-by, duplicates, is-duplicated-by`, each with `directed`/`forward` display flags; defaults `related-to / #eb144c / link` (#3392) [22']. The REST POST **rejects an unknown type with 400** (`type must be one of: …`, v12.77 `server/models/dependencies.js` L352-354) while stored legacy/unknown types are silently normalized to `related-to` (`normalizeDependency`) — so type is NOT free text in either direction [22].

### (b) Can the API create an edge with a chosen type? (route contract)

Confirmed at the pin — `server/models/dependencies.js` header L21-30 + handlers [22]:

* `POST /api/boards/:boardId/cards/:cardId/dependencies` body `{cardId, type?, color?, icon?}` — **upsert** keyed on (source, target): existing pair → `$set` its type/color/icon (L371-380), else `$push` (L384-385); target must be same-board; omitted `type` keeps the existing one or defaults `related-to`.
* `PUT /api/boards/:boardId/cards/:cardId/dependencies/:targetId` — re-type/edit (`cardDependencies.$` positional update, L424-431).
* `DELETE …/dependencies/:targetId` — `$pull` from source (L460-461).
* `GET /api/boards/:boardId/dependencies` — board-wide aggregation of every card's stored array (L283-286); `GET …/cards/:cardId/dependencies` — the card's own array (L315).

Our `add_card_dependency`/`edit_card_dependency`/`remove_card_dependency` map 1:1 onto these [10] — the lab's "already known to work" stands, now sourced upstream.

### (c) Does `related-to` (or any type) have upstream semantics — gating?

**None. Dependency lines are pure visualization.** `related-to` is even undirected (`directed:false` → no arrowhead) [22']. There is **no server- or client-side check anywhere** that a move/edit respects a dependency — not for `blocks` either; the only behavior attached to edges is *cleanup*: a cross-board move clears the moved card's own edges and an `after.update` hook `$pull`s the inbound references on the old board (#3392/#6572, `server/models/cards.js` @v12.77 L1070-1098 + test header) [26'][35]. The v12.77 feature doc states the design in one line: a dependency "changes nothing on the board" (that sentence is about the private My-Dependencies layer, #6732, stored in user profiles, dashed lines — the Board layer is the same semantics, just shared) [23']. **Conclusion: the lab's dependency gate is entirely consumer-side; "gate on `related-to` instead of `blocks`" is a lab doctrine change with zero upstream interaction. But `related-to` carries no direction upstream (`related-to↔related-to` is its own inverse, one stored entry), so the plan must define which end "has the dependency" and handle the live mutual #126↔#140 pair — a naive both-ends gate deadlocks it (EXPLORE live edges [8]).**

### (d) Does upstream ever store the inverse twin?

**No — only the source card's `cardDependencies` array is ever written** ($push/$set/$pull above; no twin anywhere in the create path), matching the lab's belief. The `DEPENDENCY_TYPE_INVERSE` map exists purely so the UI can **display** a stored `blocks` as `is-blocked-by` from the far end's perspective ("used when remapping a dependency onto the other card… for showing", `models/metadata/dependencies.js`) [22']. The board-wide GET is the only place both directions become visible (aggregation over all cards' arrays) — which is why the preload's board-wide `dependencies` list is the right gate input. Two further storage facts for the plan: edges die silently on cross-board moves (both halves), and `parent_id` lineage stays separate from edges (nothing upstream writes an edge for a parent).

---

## What this means for the plan

Per capability, in the owner-ask vocabulary (A–F of EXPLORE's anchors):

| capability asked | status on our pin (v12.77, live) | mechanism / owner |
|---|---|---|
| Rule adds the five checklists + items on create (B, vocabulary part) | **works today** | `addChecklistWithItems` extras, sequential within one rule (#4294 engine, unchanged v12.65≡v12.77). Artifact re-issue is just data. |
| Rule PRE-CHECKS items (Models→Qwen Dense, the card's Lifecycle/HITL sets) | **broken upstream, no fix version** — typo `checkListId` since ≤v9.99, still in v13.06/master, **unfiled**; ordering/race is NOT the cause | keep extras DORMANT or drop them; checks via agent-side `create_card default_checked` (working, deployed) + human runbook for human-created cards; optional: file the upstream issue/PR (3 tokens, the upgrade ticket's parked user decision) — do NOT change artifact spelling, the payload keys are already right |
| Rule sets Priority=5 at create | **not a rule capability** (no custom-field action in v12.6x or master; none planned) | field attach-at-create is automatic when `automaticallyOnCard` (verify the live flag — see unknowns); value = per-card API write (`set_card_custom_field`, number not string) — needs the coord to lift the "board fields are input-only, never written back" ban for this one field, or make it a human runbook |
| Backfill 90 cards: expand Lifecycle/HITL (2 new FIRST items, new Services items), keep ticks | **works today, per-card REST loop** | `POST items` with explicit `sort:-2/-1` (negative sorts render first; #6544), `PUT title` for rewords, `PUT title` (checklist) for renames (#1037); **no** cross-card API exists — MCP gaps (rename/delete-checklist, item sort) → raw REST leg or a wekan-mcp extension; execution sanction per the boards L58 wall (owner-directed, backup first) |
| Delete+re-add a checklist during backfill | **works but destructive** — cascade wipes all items/ticks (#6816 hook at pin) | forbidden by this research: mutate in place |
| Card templates / list defaults as the defaults mechanism | **not a real path** | template boards = group board-blueprints; checklist-from-template = UI-only, append-duplicating, always-unchecked (#4017); no list/swimlane defaults exist |
| Priority display default vs behavior | unset already = default class = vLLM 5 (pipeline-models table) | the ask is cosmetic; say so in DECISIONS when ruling |
| Gate on `related-to`, drop `blocks` (F) | **purely lab-side** — zero upstream semantics on any type | doctrine change: define direction for undirected `related-to`, add mutual-pair tie-break (the #126↔#140 deadlock is live today), keep consuming the board-wide edge list (one-sided storage confirmed) |
| Auto `fixes` edge child→parent at creation (F) | **no upstream create-time edge hook**; **API-side it works** | engine flow: `POST cards` with `parentId` (accepted at v12.77, parent-visibility-checked) → `POST dependencies {type:"fixes"}`; this reverses the boards L375/L426 "parent_id only, no edge" ruling — plan must amend it explicitly (keep `parent_id` too; the preload carries it) |
| Naming for the new engine + rules artifact | lower-`l` everywhere externally | golden rule: payloads use `checklistName/checklistItems/checkItemName`, paths `checklists/:checklistId`; assert `checkListId` appears nowhere in generated artifacts; item strings comma-split with no trim; avoid `addedChecklistItem`-triggered rules (never fire) |

**Residual unknowns (not resolvable from sources):**

1. Whether the live `Priority` field currently carries `automaticallyOnCard`/`alwaysOnCard` — decides whether UI-created cards already attach it; live-readable via `list_custom_fields`/get on the field (not read this round beyond names).
2. Whether the owner wants the upstream issue/PR filed (public GitHub action, parked since 2026-10-26).
3. If upstream ever fixes the typo, whether the lab will upgrade into it (v13.x line is ~30 releases ahead with unrelated behavior churn — e.g. the #2474 date-clear change); the dormant-extra "fix lands free" hope stays alive but has no ETA.
4. First-release bracketing of #6544 item-sort and #1037 checklist-PUT (both present at v12.65 already; their earliest tags not probed — irrelevant to the pin).
5. Exact client behavior of "edit items as text" save (id reuse on unchanged lines) — UI-only convenience, unverified.
6. Whether ArgoCD's live `home-boards` pods are on the newest v12.77 ReplicaSet at every future moment (read once: spec image v12.77, ready 1/1).

## Sources

(Upstream URLs at the stated ref; fetched 2026-11-10/11.)

1. Repo pin: `services/home/prod/Chart.yaml` L39-48 + `Chart.lock` L26-31 (`wekan` 12.77.0 ×2); `git log` `d8b12fd0f` "Update Helm release wekan to v12.77.0" (2026-11-01), `c96a6a824` v12.65.0.
2. Live cluster read 2026-11-10, `readonly-home-kubernetes resources_list` apps/v1 Deployment: `home/home-wekan` and `home/home-boards` → `ghcr.io/wekan/wekan:v12.77`, 1/1.
3. https://api.github.com/repos/wekan/wekan/releases/latest → `v13.06`.
4. https://raw.githubusercontent.com/wekan/wekan/v9.99/server/rulesHelper.js (L463/474 typo).
5. https://raw.githubusercontent.com/wekan/wekan/v12.65/server/rulesHelper.js and …/v12.77/server/rulesHelper.js (md5-equal `b80afdcb014cc9f2b33afbc885f7921d`; typo L1049/L1060; checkAll via `checklistId` L1031-1043; `addChecklistWithItems` L1090-1108; executeRules depth guard L378-390; extras loop L392-410) and …/master + …/v13.06 (identical content; typo L1052/L1063; diff vs v12.77 = only the #2474 `isTimingClear` fix).
6. https://raw.githubusercontent.com/wekan/wekan/v12.65/server/notifications/storedRulePlans.js, …/v12.77/… and …/master/… (L1665 `checkListId` capture; `checkAll` sibling path correct).
7. `.agents/plans/2026/2026-10-dep-wekan-v12-upgrade/RESEARCH.md` (Q4 §; ROOT CAUSE 2026-10-26 + probe table; v12.64 lines; tag-probe for #4294 availability).
8. `.agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/EXPLORE.md` (live board facts, edges, tools, pre-existing reds).
9. `skills/wekan-api/references/wekan-mcp-ops.md` (v9.99-era races, no-whitelist, comma-split, trigger-name dead code, custom-field coercion, never-retroactive).
10. `containers/wekan-mcp/wekan_mcp/server.py` L789-858 (`add_checklist`, `add_checklist_item` no-sort, `toggle/delete_checklist_item`), L862-909 (`create_rule`/`update_rule` single-action), L964+ (`set_card_custom_field`), L1272-1275 (7-type tuple), L1391-1487 (dependency tools), L578-656 (`create_card` `default_checked`+`parent_id`).
11. Issue #4294 "Make Rules less clunky" — closed 2026-10-08. https://github.com/wekan/wekan/issues/4294
12. https://raw.githubusercontent.com/wekan/wekan/v12.77/docs/API/Rules.md (action vocabulary incl. `checkItem`/`uncheckItem`; trigger table; REST rules contract; `enabled` pause; `*` wildcard).
13. https://raw.githubusercontent.com/wekan/wekan/v12.77/client/components/rules/actions/checklistActions.jade (`check-item-action` wizard block).
14. https://raw.githubusercontent.com/wekan/wekan/v12.77/models/checklistItems.js (schema: `checklistId` L44, `sort`, `isFinished`, `dueAt`, `assigneeId`) and …/models/checklists.js (`items()` sort `['sort']` L207-210).
15. https://raw.githubusercontent.com/wekan/wekan/v12.77/imports/reactiveCache.js (`getChecklistItem` pass-through L127-130; `getTriggers` unsorted L310-316).
16. https://raw.githubusercontent.com/wekan/wekan/v12.77/models/lib/checklistBulkCheck.js (#2473, per-checklist bulk check).
17. `server/notifications/storedRulePlans.js` at three refs (same as [6]) — durable capture keeps the typo; `targetIds` stays empty ⇒ stored command checks nothing.
18. https://raw.githubusercontent.com/wekan/wekan/v12.77/server/triggersDef.js L58-71 (`addedChecklistItem`) vs …/models/checklistItems.js L180 (`activityType: 'addChecklistItem'`).
19. rulesHelper @master complete `actionType` set (L809-1183) — no custom-field write; `{customField:Name}` read vars (v12.77 L141-176, `#3195/#4294` comments).
20. https://raw.githubusercontent.com/wekan/wekan/v12.77/server/models/checklists.js (routes L180/214/251/319/374; PUT-rename #1037 comment; `after.remove` item cascade #6816 L170-178; POST items = string array).
21. https://raw.githubusercontent.com/wekan/wekan/v12.77/server/models/checklistItems.js (GET L106, POST L135 with explicit-sort #6544 comment, PUT L195 = title/isFinished/dueAt only, DELETE L258).
22. https://raw.githubusercontent.com/wekan/wekan/v12.77/server/models/dependencies.js (header L21-30 contract; POST upsert L337-390; unknown type 400; source-only writes; PUT L424-431; DELETE L460-461; board GET L283).
22'. https://raw.githubusercontent.com/wekan/wekan/v12.77/models/metadata/dependencies.js (7 fixed types, defaults `related-to/#eb144c/link`, `directed/forward`, `DEPENDENCY_TYPE_INVERSE` for display, `normalizeDependency` coercion).
22''. https://raw.githubusercontent.com/wekan/wekan/v12.77/docs/API/Checklists.md (historical routes + dueAt note).
23. https://raw.githubusercontent.com/wekan/wekan/v12.77/docs/Features/All-Boards/Templates.md (template boards group-only; checklist-template copy bullet; #904 export-unfunded).
23'. https://raw.githubusercontent.com/wekan/wekan/v12.77/docs/Features/General/Editor/RedStrings/Board-And-My-Dependencies.md (#6732 two layers; "changes nothing on the board").
24. https://raw.githubusercontent.com/wekan/wekan/v12.77/models/lib/checklistTemplateCopy.js (#4017 semantics: append after, fresh ids, `resetChecked`).
25. https://raw.githubusercontent.com/wekan/wekan/v12.77/client/components/cards/checklists.js L925-947 (popup → `Checklists.copyAllFromCardToCard(sourceCardId, targetCardId)`, client-side).
26. https://raw.githubusercontent.com/wekan/wekan/v12.77/server/models/cards.js (auto-attach `automaticallyOnCard||alwaysOnCard` value-null L1496-1502 + bulk L1607-1613; insert ignores body `customFields`, `parentId` accepted + visibility-checked; bulk endpoint ≤500 #4743; PUT `customFields` full-array `$set` L1905-1913; dedicated value route L2388-2418 only touches attached fields; `copyCard` L835; cross-board dependency cleanup L1070-1098).
26'. https://raw.githubusercontent.com/wekan/wekan/v12.77/server/models/activities.js L58-66 (`after.insert` → `executeRules`, `deferSyncActivity('rules')` skip); REST create calls `cardCreation` (L1560) → rules fire for REST/bulk-created cards.
27. https://raw.githubusercontent.com/wekan/wekan/v12.77/models/customFields.js (schema — no `defaultValue`; flags list) and …/server/models/customFields.js (REST POST `automaticallyOnCard` L139; PUT both flags L195-199).
28. Issue dates via GitHub API: #1037 closed 2026-09-10 ("Roadmap for REST-API features"), #6544 closed 2026-07-28 ("REST API cannot create new checklist items"), #4017 closed 2026-09-10, #3392 closed 2026-06-15, #6816 closed 2026-10-27.
29. GitHub issue-search API (repo:wekan/wekan), 2026-11-11: `checkListId` → 14 (none about the rule-action dormancy), `checkItem` in title/body → 2 (unrelated), `uncheckItem` → 0, `"check item" rule` → 5 (unrelated), custom-field-rule title → 0. Direct checks: #1396 (2017, different copy-paste), #6816 (cascade delete).
30. #6816 body (cascade fix patch attached); #3195 closed **completed 2026-09-29** (custom-field values *read* into rules); #6806 closed **completed 2026-10-26** (display default only).
31. https://raw.githubusercontent.com/wekan/wekan/v12.77/models/lib/checklistItemsAsText.js (#4218 header).
32. SearxNG sweeps (`global-searxng`, 2026-11-11): no public report/fix of the checkItem rule dormancy or of rule-set custom-field defaults outside GitHub.
33. https://raw.githubusercontent.com/wekan/wekan/v12.77/docs/API/Custom-Fields.md (documented `{"customFields":[{"_id","value"}]}` card write).
34. https://raw.githubusercontent.com/wekan/wekan/v12.77/server/compatApi/trello.js L204-216 (card-scoped checklist routes).
35. https://raw.githubusercontent.com/wekan/wekan/v12.77/server/lib/tests/cards.dependencies.move.tests.js header (#3392/#6572 move-time edge cleanup, no gating).
36. `.rulesync/skills/boards/SKILL.md` L20/L21 (the DORMANT claims this round re-verified) and `skills/wekan-board-provision/SKILL.md` L119-130 (extras = human import only) — consistent with upstream findings: v12.77 `server/models/rules.js` still destructures only `{title, trigger, action}` (L157) and PUT only title/enabled/trigger/action (L220-235), extras readable at L79-80; import/export client `client/components/rules/rulesImportExport.js` L31-34/L80-81 remains the only extras path.

RESULT
status: DONE
chunk: pre-research
files_changed: [.agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/RESEARCH.md]
commands_run: [pin resolution (Chart.yaml/lock/git log + readonly-home-kubernetes deployment read => v12.77 live+pin) => pass; raw-file fetches at v9.99/v12.65/v12.77/v13.06/master of rulesHelper, storedRulePlans, reactiveCache, triggersDef, checklist model+route files, cards/customFields/rules/dependencies server+model files, checklistTemplateCopy/bulkCheck/itemsAsText, docs API+Features => pass (one transient 404 on the `master` tree ref re-confirmed via per-file fetches); GitHub issues+PR searches (14 keyword sets) + direct issue fetches => pass; curl-based tag feature probes (checklist PUT, #6544 sort, template copy, bulk check present since v12.65) => pass; global-searxng sweeps => pass; local reads (EXPLORE, upgrade RESEARCH, dense artifact, boards skill, wekan-mcp-ops, server.py) => pass; zero writes outside this file]
deviations: none (ask executed as scoped; no user questions per launch)
friction: GitHub `master` git-tree API returned 404 once while v12.77 succeeded (transient/rate behavior) — worked around with per-file raw fetches; SearxNG tool name guessed wrong once (`searxng_search_web` vs catalog `searxng_web_search`) — resolved via search; compound bash grep initially masked the storedRulePlans typo line (re-run cleanly before trusting).
open_questions: 1) Does the live `Priority` field carry automaticallyOnCard/alwaysOnCard (live-readable; decides UI attach)? 2) Does the owner want the upstream issue/PR for the `checkListId` typo filed (parked user decision since cf-upgrade 2026-10-26 — 3-token fix, still unfixed in master)? 3) Given unset-Priority already = default class (vLLM 5), does the owner still want the cosmetic raw=5 backfill, and through agent write (needs lifting the boards L269-271 input-only ban) or human runbook? 4) Should the plan's rules artifact keep the DORMANT checkItem extras in place (the upgrade ticket's posture) or drop them? 5) Backfill execution shape: raw-REST leg vs wekan-mcp tool extension (rename/delete-checklist, item sort) — both need an owner-directed sanction against the board-write wall.
next_suggested: plan — treat rule-pre-check and rule-custom-field-default as NOT available upstream (agent-side default_checked + human import/runbook + per-card REST backfill loop), adopt the sorted-insert backfill recipe (sort:-2/-1, rename-not-rebuild), and gate the `related-to` redesign on the direction/tie-break decision before any gate wording lands.
