# RESEARCH-r4 — detecting human card edits and forwarding them to a live run

Ticket AD-140 (`cf-140-feat-agent-card-reconcile`) · research topic R4 · 2026-11-23
Scope (from the card): *what is actually detectable about WeKan card changes on our deployed instance,
and the best practice for a reconcile loop that forwards human edits to a running agent.*
Prior grounding: `EXPLORE-wekan-mcp.md` §4, `EXPLORE-session-api.md`, `EXPLORE-plugins.md`,
`REVIEW-existing-plugins.md` (M1, M6, M8 rulings — this file is written to serve them, not re-litigate them).

Method: WeKan claims are read from the **pinned tag `v12.99`** (the deployed chart is `12.99.0`), fetched
2026-11-23 into `/tmp/r4` (`server/models/cards.js`, `models/cards.js`, `server/models/boards.js`,
`models/activities.js`, `server/models/activities.js`, `server/notifications/outgoing.js`,
`models/export.js`, `models/exporter.js`, `models/lib/exportFields.js`, `server/models/cardComments.js`,
`server/models/checklistItems.js`, `server/lib/restCardHelpers.js`, `server/apiMiddleware.js`,
`server/authentication.js`, `models/lib/webhookPayload.js`). OpenCode/opencode claims are read from the
**live server on this host (v2.3.2)** via `GET /openapi.json` and read-only `opencode api` probes, plus
`anomalyco/opencode@dev` `specs/v2/session.md` and `packages/schema/src/session-inbox.ts`.

Evidence classes: **[v12.99]** upstream at the pinned tag · **[live-2.3.2]** probed on this host today ·
**[repo]** read from this worktree · **[doc]** third-party/write-up (directional, not authoritative).
**Nothing here is a memory claim.**

## TL;DR (≤5 lines)

1. Both load-bearing scout claims **verified true**, and the real picture is sharper: on our instance the
   WeKan activity log records **human** edits to title/description/checklists/custom-fields and is
   **silent** on exactly those fields when the agent writes them. **[v12.99]**
2. Per-card activity history **is** readable over REST after all — scoped export (`?fields=activities&
   cardId=…`), which corrects the scout's "full-board fetch cost" assumption. **[v12.99]**
3. `updatedAt` **does not exist** on the card document; the ask's field list is wrong. Use `modifiedAt` /
   `dateLastActivity` — and know they bump on UI edits only. **[v12.99]**
4. Ranked: **snapshot-diff is the floor (required), activities are the precision layer (cheap, per-card),
   timestamps are a free "human was here" hint, webhooks stay cut** — the coord's M8 cut is independently
   confirmed, not merely convenient.
5. Hand-off has a first-class answer the scout did not find: the **v2 session inbox** (`steer`/`queue`,
   `synthetic`, instruction entries) is live on v2.3.2, and `/api/session/active` — written off as unusable
   on v2.0.32 — **works** but is **process-local**, which is the one trap that can silently break it. **[live-2.3.2]**

---

## 1. Verified vs assumed — the capability table

### 1.1 Claim 1 — "no per-card activity REST endpoint in v12.99" → **CONFIRMED** **[v12.99]**

The complete `WebApp.handlers` route inventory in `server/models/cards.js` is: swimlane card listing,
by-list card listing, `GET /api/cards/:cardId`, board-scoped single card, bulk get, create (single + bulk),
two `cards_count`, PUT, DELETE (single + bulk), `cardsByCustomField`, custom-field POST, archive,
unarchive, members ×2, assignees ×2, copy, `POST cards/labels`, `GET /api/user/cards`.
**No route contains `activit`.** `server/models/boards.js` registers none either. The only activity-bearing
read path in the whole API surface is the board export (`models/export.js` → `models/exporter.js`).

Corroborated independently: `wekan-mcp` exposes no activity tool (**[repo]** `containers/wekan-mcp/
wekan_mcp/server.py` — grep for `activit` hits only rule-trigger vocabulary, never an activity read), and
the skill's `rest-api-overview.md` lists none.

**Consequence for the design:** "read the card's activity feed" is not a capability you can assume. It has
to be reached through the export route (§1.3) or a new tool that wraps it.

### 1.2 Claim 2 — "`modifiedAt`/`dateLastActivity` do not bump on API writes" → **CONFIRMED**, with the mechanism nailed **[v12.99]**

- Schema (`models/cards.js`): `modifiedAt.autoValue()` fires on `isInsert || isUpsert || isUpdate`;
  `dateLastActivity.autoValue()` returns `new Date()` unconditionally. Schema autoValues run in the
  **validated collection write path**, not on a raw query update.
- The REST PUT (`server/models/cards.js`, the `/api/boards/:boardId/lists/:listId/cards/:cardId` handler)
  performs **every** write as `Cards.direct.updateAsync` — 23 call sites in that handler — and the handler
  region contains **zero** `modifiedAt` / `dateLastActivity` mentions.
- The 22 explicit `modifiedAt: new Date(), dateLastActivity: new Date()` stamps in that file all live
  inside the `Meteor.methods({...})` block (the DDP/UI path).
- Upstream says the bypass in its own words, three times: *"`#6793: .direct skips the Cards.after.update
  hook…`"*, *"`#5681: .direct skips the hook that carries linked custom fields`"*,
  *"`#1587: Cards.direct.removeAsync bypasses Cards.before.remove`"*.

**Also corrected:** there is **no `updatedAt` field on the card document at all**. The card's date fields
are `createdAt`, `modifiedAt`, `dateLastActivity`, `listEnteredAt` ("*When this card entered its current
board/list. Unrelated edits do not reset it*"), `archivedAt`. Any plan text naming `updatedAt` is wrong
and should be fixed at planning, not inherited.

### 1.3 The finding that changes the design: the activity log is **asymmetric in our favour** **[v12.99]**

Activity creation lives in `Cards.before/after.update` hooks (`updateActivities`, and the
`a-changedTitle` / `a-changedDescription` after.update hooks) — so it is skipped by `.direct` — **except**
where a REST handler calls the activity inserter explicitly. The resulting matrix:

| Card change | Human edits it (UI → DDP) | Agent writes it (REST via `wekan-mcp`) |
|---|---|---|
| title | `a-changedTitle` activity, old + new value | **no activity** (direct) |
| description | `a-changedDescription` activity, old + new value | **no activity** (direct) |
| custom-field value | `setCustomField` / `unsetCustomField` via `cardCustomFields` after.update | **no activity** (direct) |
| labels | `addedLabel` / `removedLabel` via `cardLabels` — **but only when the write uses `$addToSet`/`$pull`**, which is what the UI's add/remove label helpers do | **no activity** (the bulk route is `direct` *and* writes `$set: {labelIds}`, which `cardLabels` ignores even if the hook ran) |
| checklist item tick | `checkedItem` / `uncheckedItem` | **no activity** — `server/models/checklistItems.js` PUT is `direct.updateAsync`, and the repo already recorded this |
| due/start/end date | `a-<field>` activity, old + new | no activity (direct) |
| **move list / swimlane** | `moveCard` activity | **activity DOES land** — the REST move branch calls `cardMove(req.userId, …)` explicitly |
| **archive / unarchive** | `archivedCard` / `restoredCard` | **activity DOES land** — the archive route calls `card.archive()`, which uses `Cards.updateAsync` (not `.direct`) |
| **delete card** | activity | **activity DOES land** — explicit `buildDeleteCardActivity` (the `#1587` comment) |
| **comment** | `addComment` activity | **activity DOES land** — explicit `commentCreation(req.userId, …)` |

Two consequences the plan should build on:

1. **For the four fields this ticket actually cares about** — title, description, checklists, custom
   fields, i.e. the kickoff vocabulary the card carries — **the activity log is a human-only channel**.
   Reading it answers "did the human change the brief?" almost directly, and for title/description it even
   supplies the old and new values — without needing a self-change filter at all.
2. **The four rows where both paths log** (move, archive, delete, comment) are exactly the rows where a
   self-change filter is mandatory — and the reconciler's own board leg writes moves and comments every
   run, so those rows would otherwise loop.

**How much "before" each activity actually carries** (this decides whether the export can rebuild a diff on
its own — it partly cannot):

| Activity type | Before/after in the payload? |
|---|---|
| `a-changedTitle`, `a-changedDescription` | **both** — `oldValue` + `value` |
| `a-receivedAt` / `a-dueAt` / `a-startAt` / `a-endAt` | **both** — `timeKey` / `timeValue` / `timeOldValue` |
| `setCustomField`, `unsetCustomField` | **after only** — `value` is stored; `oldValue` is computed inside the hook purely for the no-op check and is *not* written to the activity |
| `checkedItem` / `uncheckedItem` | neither needed — the activity **type** is the transition; payload carries `checklistItemId` + `checklistItemName` |
| `addedLabel` / `removedLabel` | neither needed — type is the transition; payload carries `labelId` (no label name) |
| `moveCard` / `moveCardBoard` | `oldListId` / `oldSwimlaneId` / `oldBoardId` + destination ids and names, plus `moveReason` |
| `archivedCard` / `restoredCard` | type is the transition; carries `cardTitle` + list/swimlane ids |

Practical reading: **the export gives full before/after for prose and dates, after-only for custom-field
values, and for tick/label changes the event type itself *is* the delta.** So a custom-field *previous*
value must come from the reconciler's own stored projection — a second, independent reason the snapshot
(Rank 1) has to exist and cannot be replaced by the activity feed.


### 1.4 Per-card activity history IS readable — correcting the scout's cost claim **[v12.99]**

`GET /api/boards/:boardId/export` takes `?fields=` (allow-listed) and a **scope** through
`parseExportScope`, whose keys are `EXPORT_SCOPE_KEYS = ['swimlaneId','listId','cardId','checklistId']`
(`models/lib/exportFields.js`). With `cardId` set, `_scopedCardSelector` pins `_id = cardId`, and the
streaming exporter sets `activitySelector = { cardId: { $in: cardIds } }` for a scoped export — its own
comment: *"A scoped export's activities are its cards', not the board's."*

So `GET /api/boards/:id/export?fields=activities&cardId=<card>&attachments=false` is a **per-card activity
feed over one cheap request**, not the full-board fetch the scout assumed. Two caveats:

- The exporter appends a `users[]` section **unconditionally** (ungated by `fields=people`), carrying
  `_id`, `username`, `profile.fullname/initials/avatarUrl` for every referenced user — and it inlines
  **local avatars as base64** unless the admin `disableExportAvatars` setting is on. For a per-card poll
  this is the payload's dominant term, so it is a real cost lever, not a nit.
- `activities` is a valid `fields=` section (`BOARD_EXPORT_FIELDS`), and the admin "disable all exports"
  switch refuses the route (`refuseDisabledExport`) — a global kill switch the reconciler must degrade on,
  not assume.

`preload_board` already rides this exact route with
`&fields=board-header,labels,custom-fields,dependencies,sort,checklists` — **activities are simply not in
the list**. Reading per-card history is therefore an additive change to a call that is already proven live
on this instance, not new infra.

### 1.5 The identity signal for the self-change filter is **unspoofable** **[v12.99]**

`server/apiMiddleware.js` sets `req.userId = user._id` **only** from the bearer token's resolved user
(`activeUserByToken`); there is no body-sourced override. Where a body `authorId` differs from the session,
`noteAuthorSpoof` (`server/models/cards.js`) records it as `spoofing.author / ignored` and uses
`req.userId` anyway. Activities are inserted with that `userId`.

So `activity.userId` is a trustworthy actor identity. `wekan-mcp` already knows its own: it calls
`GET /api/user` once at startup and keeps `WekanClient.user_id` (**[repo]** `wekan_mcp/wekan.py:validate`,
called from `server.py` startup). **It does not expose it as a tool** — a one-line read tool closes that.

For webhooks specifically the actor is present too, but identity can be **redacted**: `models/lib/
webhookPayload.js` declares `actor: ['user','username','userId']` as a hideable field group, so a
`hideIdentity` board setting can strip exactly the fields the self-change filter needs. Another reason the
webhook path is the weak one.

### 1.6 What the current MCP surface exposes for a diff — **no timestamps at all** **[repo]**

`_slim_card` and `get_card_details` project **zero** date fields; the only `created_at` in the file is the
comment shaper's. So today a snapshot-diff through MCP is content-only, which is *fine and actually
better* (§2). If a timestamp is ever wanted, it is a projection addition to `_slim_card`
(`modifiedAt`, `dateLastActivity`, `listEnteredAt`) — a shaper change, not a new tool.

### 1.7 OpenCode / opencode hand-off surface — verified live **[live-2.3.2]**

Probed on this host (`opencode v2.3.2`, two live server processes: pid 895 on `127.0.0.1:4096`, pid 28770
on `127.0.0.1:49374`):

| Surface | Status today | Contract |
|---|---|---|
| `POST /api/session/{id}/prompt` | live | body `{text (req), id?, files?, agents?, skills?, metadata?, delivery?, resume?}`; `delivery ∈ "steer"\|"queue"`; **404** `SessionNotFoundError`, **409** `ConflictError` |
| `GET /api/session/{id}/inbox` | live, answered `{"data":[]}` | pending, undelivered items oldest-first |
| `PATCH /api/session/{id}/inbox/{inboxID}` | live | `{delivery}` only; *steering wakes execution* |
| `DELETE …/inbox/{inboxID}` | live | cancel a pending item |
| `POST /api/session/{id}/synthetic` | live | `{text (req), description?, metadata?, delivery?, resume?, id?}` — an inbox item that is **not** a user message |
| `PUT /api/experimental/session/{id}/instructions/entries/{key}` | live | body `{value}`; announced at next step boundary **without queueing a message turn** |
| `GET /api/session/active` | **live and populated** (16 entries on 49374, 5 on 4096) | `{ [sesId]: {type:"running"} }` |
| `GET /api/session?directory=&archived=true&parentID=&search=&cursor=` | live | server-side filters now exist (the gate's hand-rolled tree walk is no longer mandatory) |

**Two corrections to `EXPLORE-session-api.md` that matter to this ticket:**

1. **`/api/session/active` is NOT unusable.** It was probed empty on v2.0.32 (cf-50) and written off.
   On v2.3.2 it returns a populated map. But it is **process-local**: my own demonstrably-running session
   appeared in the **4096** process's answer and was **absent from 49374's**, and the upstream V2 contract
   states it plainly — *"`sessions.active()` snapshots busy periods currently owned by this process…
   Durable execution events and claims are historical and recovery records, not proof that this process is
   still live."* With two servers sharing one `opencode.db`, **absence from one server's answer means
   "not running here", never "idle"**. A reconciler that reads only one process gets false "idle" verdicts.
2. **`archived` is not echoed on the record.** An archived session read back returned
   `agent, cost, id, location, metadata, model, outcome, projectID, time, title, tokens` — **no `archived`
   key**, even though `?archived=true` selected it. Archive state is **filterable, not readable**; the
   archive-bookkeeping design must use the filter, not the record.

**Delivery semantics that decide the hand-off design** **[doc: `specs/v2/session.md`, `session-inbox.ts`]**
— quoted because the behaviour is subtle and load-bearing:

- `steer` (the **default**) *"delivers before the agent's next model call, even mid-work"* — promoted at
  the next safe step boundary of the **current** turn.
- `queue` *"waits until the agent finishes its current work, then delivers one queued item at a time."*
- `resume: false` *"records the input without scheduling execution"* — durability without a wake.
- **Idempotency is built in**: *"Reusing a user or synthetic inbox item ID is idempotent when Session and
  type match: the first admission wins, and retried payload, metadata, and delivery are ignored."*
  A caller-supplied `id` is therefore a **free dedupe key** for a repeated reconcile tick.
- **The known footgun:** *"`session.interrupt` with `resume: true` … resumes pending steer items … Queued
  next-turn prompts stay parked"* — a `steer` admitted just before a human hits Esc **runs anyway**.
  Upstream's own guidance for a loop driver is *"Use `delivery: "queue"` for continuation prompts."*
- Plugin ctx parity: `ctx.session.prompt/synthetic/…` carry `delivery`, and
  `ctx.session.instructions.entry.{list,put,remove}` is exposed on both plugin APIs (added ~v2.2.0, so
  **capability-gate** it — this repo pins v2.1.4 semantics with gated seams). **Inbox list/update/cancel are
  NOT on the plugin ctx** — those need HTTP.

### 1.8 Still assumed, not verified (declare these in the plan)

- **Everything in §1.1–1.5 is tag-pinned source, not a live probe of the running pod.** The deployed chart
  is `12.99.0` and the scout read the matching tag, so this is the strongest evidence short of probing; the
  probe (does a REST card edit bump `modifiedAt` on *our* pod; does `?fields=activities&cardId=` answer)
  is a **credential leg** — no bearer exists in a pipeline session (the scout's §6 says the same). It is
  user-owned per the cf-77 precedent, and it is cheap: two requests.
- `disableExportAvatars`, "disable all exports", and `disableActivities` are **admin settings** that flip
  cost and feasibility; none was read from the live instance.
- Whether rule-driven writes (`deferSyncRecording`) also log — only matters if board rules mutate cards,
  which the provision spec does for checklists on create.
- `list_comments` returning `created_at: null` is a **recorded live observation**, not re-verified here;
  it is the reason §2 ranks comment-id set-difference over timestamp diffing.
- v2.3.2 emission of `session.idle`/`session.status` and pending-**question** persistence are **R3's scope**
  (OQ-R4) — deliberately not answered here to avoid two rounds disagreeing.

---

## 2. Ranked detection design

Cost/reliability reasoning, then the ranking. The loop runs per-tick from a plugin; the board is one board
with ~116 cards, of which only the claimed/executing set is interesting — that bound is what makes the
cheap option cheap.

### Rank 1 — content-hash snapshot-diff of the tracked cards (the floor; required)

Hash a canonical projection of the card and compare against the stored hash. **Correct on every write
path**, needs zero WeKan features, and — the point the scout under-weighted — it is the **only** option
that sees the agent-blind, hook-blind edits at all (labels and custom-field writes via REST produce
neither an activity nor a timestamp).

Fields to include, corrected against the real schema:

| Include | Why |
|---|---|
| `title`, `description` | the brief itself; the highest-value signal |
| `listId`, `swimlaneId` | the owner's named worst case, and it **is** reliably visible in a snapshot |
| `sort` | **exclude from the delta, include in the hash is wrong — exclude entirely.** `sort` churns on every insertion (a card moved into a list re-inserts at the top and siblings' sort shifts); diffing it produces false "changed" noise from *other* cards' moves. |
| checklist item `(title, finished)` pairs, ordered by stored order | the kickoff vocabulary — Lifecycle stage ticks, Model(s) answers |
| custom-field values keyed by field **name** (`slug`, `Priority`) | name-keyed so a field re-add does not read as a change |
| `labelIds` **as a sorted set** | array order is not semantic |
| `archived` | a human shelving a card is a real signal |
| comment **id set + count**, and the newest id | timestamps are unreliable here (§1.8), ids are |
| `parent_id`, dependency edges (`to_id` set) | lineage/dependency edits |
| `modifiedAt`, `dateLastActivity` | **hash them but classify them separately** — see Rank 3 |

Cost: one `get_card`-class call per tracked card per tick. Scoped to executing cards (a handful), this is a
few requests per tick. A whole-board `preload_board` already costs one export call and carries
checklists + labels + custom fields + sort for **all** cards, so a board-wide tick is one request — at
116 cards that is the cheaper total, and it is the call that is already proven live on this instance.

Reliability: **highest**. Immune to the hook-bypass asymmetry, to admin feature flags, to webhook loss,
and to the two-process `ctx.storage` flap. Weakness: it tells you *that* and *what*, never *who* — so it
cannot by itself separate human from agent (§3).

### Rank 2 — per-card activities via scoped export (the precision layer, cheap)

`GET /api/boards/:id/export?fields=activities&cardId=<card>&attachments=false` (§1.4). Gives **who, when,
and for prose/date fields the old→new values** of every human title/description/checklist/custom-field/
date edit — which is exactly "the history of the card changes for a more precise update" the card asked
for — and it arrives pre-filtered to human edits for those fields (§1.3). Payload precision per type is in
the table at the end of §1.3; the one gap is the custom-field *previous* value, which only the stored
projection can supply.

Use it as a **classifier over Rank 1's delta**, not as the detector: when a snapshot delta fires, one scoped
export explains it, attributes it, and (absent an agent-attributed activity for that field) tells you it
was human. On the four card-move rows where both paths log, it is also the self-change filter itself.

Cost: one export per card **only on a tick where the hash changed** — normally zero. Watch the
`users[]`/avatar term (§1.4).

### Rank 3 — `modifiedAt` / `dateLastActivity` as a free human-hint (never as the signal)

Because these bump on DDP writes and **not** on REST writes (§1.2), a bump with no agent action is a strong,
zero-cost "a human touched this in the UI" marker, and it is already inside the snapshot you fetched. It is
also the only signal for edits the snapshot projection happens not to include. It must **never** be the
primary detector: it is silent on every agent write, so as a detector it is precisely inverted from what
someone will assume. Hash them, compare them, classify them separately, and label them in the code so the
next reader cannot misuse them.

### Rank 4 — webhooks: **stay cut** (M8 confirmed on evidence, not convenience)

Independent reasons this is the wrong layer here, all from source:
- **Coverage is exactly as holey as the activity feed** — webhooks fire from `Activities.after.insert`, so
  they inherit every `.direct` blind spot (no REST title/description/checklist/custom-field/label event
  exists to deliver). The webhook path cannot see the edits we most need to see.
- **No delivery guarantee, no retry, no ordering**, and *"not every activity fires a webhook"*; a slow
  receiver stalls WeKan's activity processing unless it answers 200 immediately.
- **New infra**: an endpoint reachable from the WeKan pod (SSRF-guarded against private/loopback by
  default), board-admin rights, an `activities` allow-list per integration.
- **Identity can be redacted** — `hideIdentity` strips the `actor` group, i.e. the self-change filter's key
  (§1.5).

Every pattern surveyed for webhook reliability converges on the same prescription: webhooks are a latency
optimisation over a **reconciliation poll that is the actual source of truth** — *"treat a webhook as
evidence that something may have changed, not as the only copy of truth"* and *"the reconcile job converts
webhooks' worst property, silent permanent loss, into 'up to N minutes stale'."* A tick-driven snapshot
loop already **is** that reconcile job, and we already own its scheduler. Adding the webhook leg buys
latency we don't need (a card brief is not a payment) for a second, weaker detector and a new secret.

**The one place webhooks beat polling** is latency-critical preemption (stop a run *now*). If the owner
ever wants that, the right shape is a webhook that only **wakes** the reconciler tick early — never one
that carries the decision — and the snapshot diff stays the authority. Note it as the extension point; do
not build it.

### Combined recommendation

**Snapshot-diff (Rank 1) as the detector + activity export (Rank 2) as the classifier + timestamps (Rank 3)
as a hint, all inside the per-tick reconcile loop.** That is the textbook hybrid minus the webhook, which
is the correct subtraction here because the fast path and the recovery path would share the same blind
spot.

---

## 3. The self-change filter (mandatory — the loop is otherwise a feedback oscillator)

The reconciler's own run writes to the card constantly (card moves, comments, checklist ticks, `slug`
field writes, post-plan write-back), and the reaper/registry legs write moves too. Without a filter, every
agent write becomes a "human changed the card" forward to the agent, forever.

**Recommendation: actor identity as the primary filter, generation marker as the backstop.**

1. **Primary — actor id, from the activity where one exists.** `activity.userId ≠ agentUserId` ⇒ human.
   Unspoofable (§1.5). `agentUserId` is `wekan-mcp`'s own startup `user_id`, already computed; expose it
   through a trivial read tool (`whoami`) rather than hardcoding a Mongo id in a plugin. This is complete
   for move/archive/delete/comment — the four fields that log on both paths.
2. **Free pass — the four hook-blind fields.** Title, description, checklists, custom-field values and
   labels write **no activity when the agent writes them** (§1.3). So a snapshot delta in these fields with
   **no corresponding agent-attributed activity** is human. Do not over-claim this: it is sound because
   *our* writes to those fields always go through `.direct`, and it stops being sound the moment a future
   write path uses a hook-preserving route. Encode the assumption in a code comment that names the
   mechanism (`.direct` bypasses `Cards.before/after.update`), not in tribal knowledge.
3. **Backstop — a generation marker the reconciler owns.** Store, per card, the exact content the agent
   last wrote (the same canonical projection it hashes). A delta is agent-made if the new snapshot equals
   a projection the run itself published. This is the Kubernetes discipline — a controller compares against
   the last state **it** authored (`observedGeneration`) rather than reacting to "something changed" — and
   it is the only filter that works for a field where the identity signal is unavailable. It also makes the
   loop idempotent: *"a successful `Reconcile` should be able to run hundreds of times without producing a
   write."*
4. **Explicitly rejected: body `authorId`.** It is the obvious knob and it is dead — WeKan ignores a body
   `authorId` that differs from the session (`noteAuthorSpoof`), so it cannot be used to tag agent writes
   as a different actor. (Ironically `create_custom_field` in `wekan-mcp` still sends it; that is inert for
   the identity purpose.)
5. **Also rejected: timestamp-window "ignore the last N seconds".** A window that is short enough to catch
   a human editing while the agent works will drop a genuine human edit made seconds after an agent write —
   the exact failure this ticket exists to prevent. Windows are for reducing cost, never for correctness.

**Fail-open on ambiguity, but forward at most once.** If actor cannot be determined, treat as human
(the unsafe direction is silently ignoring a human's instruction, matching the repo's fail-loud law) — and
the dedupe in §4 guarantees one misclassification costs one forward, not a stream.

---

## 4. Delivering the change to the live run (and satisfying M6)

### 4.1 The state store — canonical-root file, **not** `ctx.storage` (M1)

`REVIEW-existing-plugins.md` rules this already: *"never rebuild this guard on `ctx.storage` capability —
use the shared-db session record or a canonical-root file."* The live root cause was a storage-binding flap
× two-server topology: 15 of 17 long-lived board-coord sessions re-injected, and the durable mark simply
never advanced on the storage-less process. **The same guard class must not be rebuilt on the same surface
for the same reason.** A card-state store sitting on `ctx.storage` would inherit exactly that bug: two
processes, each believing it already forwarded.

Recommendation:

- **Home: `.pipeline/cards/<cardId>.json`** at the **canonical repo root** — the established
  plugin-owned, git-ignored runtime dir that already holds `locks/`, `events.log`, `timeouts.jsonl`,
  `meta/lastReap`, and whose path resolution (`resolveLockRoot`, the D10 chain) is proven and already
  handles worktrees → canonical root. It is a *generated projection*, which is precisely what a card-state
  store is.
- **Record shape:** `{cardId, slug, sessionID, hash, projection, lastHumanChangeAt, lastForwardedHash,
  forwardedIds[], agentPublishedHashes[], updatedAt}` — one file per card, written **tmp-sibling +
  rename** (the `writeLockAtomic` precedent; the repo already knows a torn file is *"unreadable state, not
  free state"*), plus a JSONL audit append to `events.log` using the existing `at: localIso(...)` stamp
  convention.
- **Do not use `ctx.storage`** for any guard whose correctness is cross-process. It is fine for
  same-process niceties; it is not fine here.
- **JSONL, not SQLite** — consistent with the existing `events.log` / `timeouts.jsonl` vocabulary, and it
  keeps the dep footprint at zero. A per-card JSON *projection* + an append-only JSONL *audit* mirrors the
  two surfaces the repo already runs.
- **Bound the store's life.** A card that leaves the pipeline (Finished, Cancelled, moved out of the
  tracked swimlane, or its run released) should have its record **retired**, not accumulate. The scout's
  note that unclaimed cards never expire in `timeouts.jsonl` is a live hoard at 116 cards; don't repeat it.

### 4.2 The bound M6 demands: **re-write the dump, forward one line**

The review's ruling is the right one and the design should adopt it verbatim:
*"Prefer RE-WRITING the YAML dump and notifying in one line ('card updated — re-read CARD.yaml') over
pasting diffs into prompts."* Measured justification: this ticket's own first prompt was 8,310 chars of
which **99.6% was injected card mechanics**. Change-forwarding is that bug wearing a new hat.

Concrete bound:

- The **delta lives in the file, never in the prompt.** The plugin rewrites `CARD.yaml` (the authoritative
  projection) and, on a human-attributed change, delivers **one line**: the changed field names, the actor,
  and "re-read CARD.yaml". Target: well under 300 chars, in the spirit of the existing
  `MAX_OUTBOUND_MESSAGE = 240` ceiling.
- **Dedupe by content, not by tick.** Only forward when `hash ≠ lastForwardedHash`. Use the inbox's
  caller-supplied `id` as the idempotency key — *"retried payload, metadata, and delivery are ignored"* —
  so a crashed tick replaying is free.
- **Coalesce, don't stream.** Multiple pending edits for one card collapse into one forward (the survey's
  *"several quick changes can then collapse into one refresh"*), and **cap forwards per card per session**
  (a small number, e.g. 3, then stop forwarding and mark the card for a human-visible nudge) so an actively
  editing owner cannot flood the run. This is the "context injector" failure made structurally impossible.
- **Never forward a delta the agent itself produced** (§3) — that is the oscillator.

### 4.3 The delivery primitive — prefer `synthetic` + `queue`

Three live options on v2.3.2, with a clear winner for this use:

| Option | Verdict |
|---|---|
| `POST /session/{id}/prompt` | Works, but admits a **user** message — it renders as if the human spoke. For a machine-detected notice that is a lie in the transcript, and it invites the model to treat a plugin-written delta as a human instruction. |
| **`POST /session/{id}/synthetic`** | **Recommended.** Same inbox, `type: synthetic`, `text` + `description` + `metadata` + `delivery`. It is a first-class non-user input, carries `metadata` so the forward is self-describing (`{source:"card-reconcile", cardId, changed:[…]}`), and participates in the same idempotent-inbox dedupe. |
| `PUT /experimental/session/{id}/instructions/entries/{key}` | Wrong tool for a *change notice*: it is durable, keyed context with **no wake** — it announces at the next step boundary but does not start one. Correct for *"here is the card's current authoritative brief"*, wrong for *"the card changed"*. Keep it as the complement (below). |

**Delivery mode:** `queue` for the change notice — the run is mid-chunk, and a `steer` interrupts at the
next step boundary. Upstream's explicit advice for exactly this caller shape: *"Use `delivery: "queue"` for
continuation prompts."* Two specific reasons: (a) a `steer` admitted just before a human presses Esc
**runs anyway**, which is the wrong way to deliver a stale card delta; (b) `queue` gives the natural
coalescing point — several edits, one idle-boundary delivery.

**Use both, for different halves.** A clean split with each mechanism's grain:
- instruction entry (`key: "card-state"`) = the card's **current authoritative state**, rewritten in place,
  durable across compaction and revert, costing **no extra model turn**;
- `synthetic` + `queue` = the **event** "it changed, and here is the one-line summary".
That gives a run that was compacted the state for free, and a run that's live the notification.

### 4.4 When the run is idle, gone, or wedged — the safe behaviour

Decide state first, then choose the action. Note the two-process caveat from §1.7: `active` is
per-process, so **absence means "not running here"**; query every server process, or use presence-union
and never infer idle from one answer.

| Run state | Evidence | Correct action |
|---|---|---|
| **Running** | in some process's `session.active`, or `time.busy`/`time.updated` fresh | `synthetic` + `queue`. Idempotent via supplied `id`. |
| **Idle, resumable** | terminal `outcome`, **no** `pipelineNoop` marker | Same call — an inbox item on an idle session starts an execution. This is the desirable case, not an error. |
| **No-op ended** | `metadata.openchamber.kind === "scheduled"` **and** `metadata.pipelineNoop.reason` non-empty | **Do not wake it.** That session ended deliberately with nothing to do; waking it resurrects an exit the owner designed. Leave the state file; the next real pickup picks the change up. |
| **Handoff successor exists** | successor session carrying the run's card/slug/`parent` | Deliver to the **successor**, exactly once. The review flags this as a mandatory discrimination (a handoff-successor otherwise reads as "run ended" and double-spawns). |
| **Gone / archived** | 404 `SessionNotFoundError`; archive is filter-only (`?archived=true`) | **Do not recreate a session.** Persist the pending notice in the card-state file, mark it undelivered, and surface it on the human-visible path. Recreating a run from a card edit is a spawn decision and spawn ownership is the coordinator's, not the plugin's. |
| **Wedged** | `session.compaction.failed` rows repeating | Do not pile prompts on it — that is the #56784 wedge class. Record; relaunch-FRESH is the coordinator's call, never the plugin's. |

**Never make a card-change notice a `question`.** The question path is a human-blocking gate; a change
notice is informational. If the change is large enough to require a human decision, the run should raise
that itself on the next step.

**Alerting:** the phone path is `question-notify`, **owner-disabled since 2026-11-21**. Do not design a
human-visible fallback that assumes it; land undeliverable notices in the card-state file plus the JSONL
audit (the `timeouts.jsonl` pattern — *"the row is the triage mechanism"*). OQ-R1 already tracks re-enabling
it.

---

## 5. Contradictions and how to weigh them

| Conflict | Weight |
|---|---|
| Scout: activities mean "full-board fetch cost" vs source: `cardId` is a first-class export scope key. | **Source wins.** Per-card activity reads are cheap. The scout read `exporter.js`'s non-streaming `build()` path, which is board-wide; the streaming path is the one the route uses and it scopes by card. |
| Scout: "`/api/session/active` proven unusable" vs live v2.3.2: populated, but process-local. | **Both right at their own version.** The cf-50 probe was v2.0.32. Use it, but union across processes and never infer idle from one server. |
| `EXPLORE-session-api` §8 lists "busy/idle emission" as needing research vs this round finding `session.active` live. | Narrow it: the open question is no longer *does an endpoint exist* but *which process owns the session* — and that is answerable by querying each server, not by upstream research. |
| Ask's field list (`updatedAt`) vs schema (`modifiedAt`/`dateLastActivity`, no `updatedAt`). | **Schema wins.** Fix at planning. |
| Webhooks as the "event-driven, modern" choice vs the survey's own consensus. | **Survey is unanimous against webhooks-as-authority** and unanimous that a reconcile poll is the correctness layer. Since the poll is the only path that sees the hook-blind fields, the usual "webhook for speed + poll for safety" argument collapses into "poll alone" here. |
| `steer` is the platform default (immediately visible) vs `queue` is safer for this caller. | `queue`, on upstream's own advice for loop drivers and the Esc-interaction footgun. Keep `steer` only if the owner later asks for preemption-on-card-edit and accepts the interrupt. |

**Agreement across every perspective (likely true):** poll-and-diff against a stored projection is the
correct core; the self-change filter is the hard part, not the detection; a change notice should be one
line plus a re-read pointer.

**Blind spot none of the sources covered (and neither did the scout):** the **two-server topology** as a
correctness hazard for *any* liveness or guard read. It is already biting symptom (a) via `ctx.storage`, and
it now bites `/api/session/active`. The plan should treat "which process am I asking?" as a first-class
question for every reconciler read.

---

## 6. Implications for the plan

1. **Detector = snapshot content-hash** over the tracked cards; **classifier = scoped per-card activity
   export**; **hint = `modifiedAt`/`dateLastActivity`, hashed but classified separately**. Webhooks stay
   cut (M8 now evidence-backed, not just scoped out).
2. **Fix the field list**: no `updatedAt`; drop `sort` from the delta; labels as a sorted set; comments by
   id-set + newest id, not timestamp.
3. **Two small, additive `wekan-mcp` read changes** replace the "new subsystem" framing: (a) include
   `activities` in the export `fields=` for a scoped per-card read (or a dedicated
   `list_card_activities(board_id, card_id)`), (b) a `whoami` read returning `user_id`. Both are
   credential-free reads on routes already in use; the Forgejo CI build stays the AC gate.
4. **State store = `.pipeline/cards/<cardId>.json`** (canonical root, atomic write, JSONL audit, bounded
   lifetime). **`ctx.storage` is ruled out** by M1 for anything cross-process.
5. **Self-change filter = actor id (primary) + hook-blind-field property (free) + agent-published-hash
   backstop.** Never body `authorId`, never a time window.
6. **Hand-off = `synthetic` + `delivery: "queue"` + caller-supplied `id` for idempotency**, one short line,
   **delta in `CARD.yaml` not in the prompt**, with a per-card forward cap (M6). Optionally mirror card
   state into an instruction entry (`key: "card-state"`) for compaction-free durability.
7. **Liveness across two servers**: query every server process's `session.active`; absence ≠ idle. `archived`
   is filter-only — read it with `?archived=true`, never from the record.
8. **Never wake** a `pipelineNoop`-marked, handoff-superseded, or archived run; **never recreate** a
   session from a card edit; **never** use the `question` path for a change notice.
9. **Add one cheap live-probe leg** (user-owned, 2 requests): confirm on the deployed pod that a REST card
   edit does not bump `modifiedAt`, and that `?fields=activities&cardId=` returns the scoped array. Also
   read the `disableExportAvatars` / disable-exports / disable-activities admin flags, since §1.4 and §2
   cost claims depend on them.

## 7. Open questions

- **OQ-R4a (owner, credential leg):** the two live probes in §6.9 — cheap, and they retire the last
  assumed-not-verified cells in §1.
- **OQ-R4b (owner):** are `disableExportAvatars` / "disable all exports" / `disableActivities` off on the
  live instance? Each flips a cost or feasibility assumption.
- **OQ-R4c (plan):** is per-card `CARD.yaml` rewritten by the **plugin** (needs slug → folder resolution
  outside the run — the review flags this as workable but undefined) or by the **run**? This research
  assumes the plugin may rewrite it; if it cannot, the forward line must carry a folder pointer instead.
- **OQ-R4d (plan):** the per-card forward cap value, and what happens on exhaustion (silent stop + audit
  row vs a human-visible nudge) — this is the M6 bound's only real tuning knob.
- **OQ-R4e (sibling R3 boundary):** pending-question persistence is R3's; if R3 finds a durable
  pending-question read, the "is this run blocked on a human?" test in §4.4 should adopt it rather than the
  timestamp heuristic used here.

## 8. Adjacent (out of core scope, recorded because it saved a wrong assumption)

`GET /api/session` now supports `directory`, `archived`, `parentID`, `search` and `cursor` **server-side**
(live-verified). The gate script's hand-rolled paged tree walk exists because those filters did not; the
reconciler can use them directly, and the gate's walk is now redundant machinery rather than a necessary
primitive. Not this topic's deliverable, but it changes what a `card-runner` liveness leg should look like.

---

## Sources

**WeKan v12.99 (pinned tag, fetched 2026-11-23)** — read in full or in the cited regions:
1. `wekan/wekan@v12.99 server/models/cards.js` — REST route inventory; PUT handler `.direct.updateAsync`
   write branches (title, description via `scalars.set`, sort, parentId, assignees, swimlane, moves);
   `a-changedTitle` / `a-changedDescription` after.update hooks; `updateActivities`; `#6793`/`#5681`
   `.direct`-bypass comments; `noteAuthorSpoof`; bulk-labels route; archive route; delete `#1587` activity.
2. `wekan/wekan@v12.99 models/cards.js` — schema autoValues `modifiedAt`, `dateLastActivity`,
   `listEnteredAt`, `createdAt`, `archivedAt` (and the absence of any `updatedAt`); `cardMove`, `cardState`,
   `cardLabels` (`addedLabel`/`removedLabel`, `$addToSet`/`$pull` only), `cardCustomFields`
   (`setCustomField`/`unsetCustomField`, `value` stored but `oldValue` not), `archive()`/`restore()`.
3. `wekan/wekan@v12.99 server/models/boards.js` — no activity route.
4. `wekan/wekan@v12.99 models/activities.js` — no schema (server-trusted); `before.insert` timestamps;
   `disableActivities` flag; `{cardId,createdAt:-1}` / `{boardId,createdAt:-1}` indexes.
5. `wekan/wekan@v12.99 server/models/activities.js` — `Activities.after.insert` → notification +
   webhook fan-out; `params.userId` / `params.username`.
6. `wekan/wekan@v12.99 models/export.js` — `GET /api/boards/:boardId/export`, `parseExportFields`,
   `parseExportScope`, `refuseDisabledExport`, public/private auth.
7. `wekan/wekan@v12.99 models/exporter.js` — `_scopedCardSelector` (cardId scope), streaming
   `activitySelector = {cardId:{$in}}` vs board-wide, `streamArray('activities',…)`, ungated `users[]`
   with base64 avatars, `disableExportAvatars`.
8. `wekan/wekan@v12.99 models/lib/exportFields.js` — `BOARD_EXPORT_FIELDS` includes `activities`;
   `EXPORT_SCOPE_KEYS = ['swimlaneId','listId','cardId','checklistId']`; `parseExportFields` semantics.
9. `wekan/wekan@v12.99 server/models/integrations.js` + `models/integrations.js` — webhook CRUD,
   `activities` allow-list, `bot` flag.
10. `wekan/wekan@v12.99 server/notifications/outgoing.js` — `deliverActivityWebhook`, fire-and-forget.
11. `wekan/wekan@v12.99 server/models/cardComments.js` — `commentCreation` explicit activity on REST insert.
12. `wekan/wekan@v12.99 server/models/checklistItems.js` + `models/checklistItems.js` — REST PUT is
    `direct.updateAsync` (isFinished / title / dueAt) with **no activity**; the model side is where
    `checkedItem` / `uncheckedItem` / `addChecklistItem` / `completeChecklist` are inserted on the DDP path.
13. `wekan/wekan@v12.99 server/apiMiddleware.js` — `req.userId` from bearer token only.
14. `wekan/wekan@v12.99 models/lib/webhookPayload.js` — `actor: ['user','username','userId']` hideable group.
15. `wekan/wekan@v12.99 server/lib/restCardHelpers.js` — `parseCardScalarFields` (sort/isOverTime/description).

**OpenCode (live v2.3.2 on this host, 2026-11-23, + upstream `dev`)**
16. Live `GET /openapi.json` (458 KB) — `session.prompt`, `session.inbox.{list,update,cancel}`,
    `session.synthetic`, `session.active`, `experimental.session.instructions.entry.*`, `session.wait`,
    `session.list` filters; exact request-body schemas and status codes.
17. Live read-only probes: `GET /api/session/active` (16 entries on pid 28770:49374; 5 on pid 895:4096,
    including this session on 4096 only); `GET /api/session/{id}/inbox` → `{"data":[]}`; session records
    incl. an archived one (no `archived` key); process inventory (`ps`, `ss -ltnp`).
18. `anomalyco/opencode@dev specs/v2/session.md` — prompt admission precedes execution; `steer`/`queue`
    semantics; `resume`; inbox id idempotency; **`sessions.active()` is process-local**; execution is
    process-local; write-ahead claims.
19. `anomalyco/opencode@dev packages/schema/src/session-inbox.ts` — `Delivery = ["steer","queue"]` with the
    authoritative description; `User`/`Synthetic`/`Compaction`/`Move` item shapes.
20. `anomalyco/opencode` issues #62208 (ACP has no steer door; core has both verbs), #32157 (queue-vs-steer
    feature, closed as done on v2), #16102 (mid-run injection history), #46842.
21. opencode docs: Effect + Promise plugin API (`ctx.session.prompt/synthetic/wait/instructions.entry`,
    `CommandInvocation.delivery`, prompt-hook `delivery`); PR #56550 (instruction entries on plugin ctx,
    *"without enqueuing inbox work"*); V1→V2 plugin migration gist (instruction entries v2.2.0+,
    support-floor caveat); jczhu.com "OpenCode Session Framework Internals" (admission-vs-execution).

**Patterns (directional practice, not authority for this instance)**
22. Kubernetes controller practice: `GenerationChangedPredicate` / `observedGeneration` as the structural
    fix for self-triggered reconciles; "status writes must not re-trigger"; `Reconcile` answers "what is
    different now", not "what event happened"; *"a successful Reconcile should be able to run hundreds of
    times without producing an API write"*.
23. Webhook-vs-poll consensus set: *"treat a webhook as evidence that something may have changed, not as
    the only copy of truth"*; webhook = latency path, reconcile poll = correctness path; both must funnel
    through **one** idempotent apply function; instrument how often the reconcile finds what the webhook
    missed. (mehdi.cz recovery-first design; AnyHook failure-mode framing; Kinetivy decision matrix;
    Hook0; GitHub/Stripe documented delivery properties; WebiU GitHub-sync drift post-mortem.)

RESULT
status: DONE
chunk: plan
files_changed: [.agents/plans/2026/2026-11-cf-140-feat-agent-card-reconcile/RESEARCH-r4-card-change-detection.md]
commands_run: [read EXPLORE-{wekan-mcp,plugins,session-api,agents} + STATE.json + DECISIONS.md + REVIEW-existing-plugins.md => pass, curl+grep wekan@v12.99 {cards.js(server+model),boards.js,activities.js(server+model),export.js,exporter.js,exportFields.js,integrations.js,cardComments.js,checklistItems.js,restCardHelpers.js,apiMiddleware.js,authentication.js,webhookPayload.js,outgoing.js} => pass, grep full WebApp.handlers route inventory for any activities route => pass (none), grep PUT-handler region for modifiedAt/dateLastActivity => pass (zero; all writes .direct.updateAsync), read GitHub v12.99 tree for apiMiddleware/bearer handling => pass, live opencode api read-only probes (/api/info, /openapi.json, session/active on BOTH server processes, session/{id}/inbox, session list filters, archived record readback) => pass, python schema extraction of prompt/inbox/synthetic/instructions-entry contracts => pass, web research (session inbox/steer/queue, OpenChamber scheduled tasks, k8s reconcile self-trigger, webhook-vs-poll reliability) => pass]
deviations: Wrote RESEARCH-r4-card-change-detection.md, not RESEARCH.md, per the launch brief and the DECISIONS.md per-round convention. Went beyond the brief's Option C framing and CORRECTED three scout/ask assumptions with source: (1) per-card activity reads ARE possible via scoped export (`cardId` is a first-class export scope key) — the scout's "full-board fetch cost" read the non-streaming build() path; (2) the activity log is human-only for title/description/checklists/custom-fields/labels because those REST writes bypass the hooks, which is a usable free signal; (3) `/api/session/active` is live and populated on v2.3.2 (written off as unusable on v2.0.32) but is process-local, and `archived` is filter-only, not readable on the record. Also corrected the ask's field list — the card document has no `updatedAt` field at all.
friction: the v2 hand-off primitive (session inbox / synthetic / steer-vs-queue) is documented only in opencode's `specs/v2/session.md` and the live OpenAPI, not in any repo doc — the scouts recorded its absence as a gap rather than as solved upstream, so it took reading the live /openapi.json to find; resolution: probed the running server directly rather than trusting the recorded gap list. Second item: the two-server topology makes single-process reads (`ctx.storage`, `session.active`) silently wrong, and neither the review nor the scouts named it as a liveness hazard (only as a storage hazard); resolution: called both server ports to prove process-locality rather than reasoning it out.
open_questions: OQ-R4a (owner, credential leg — 2 requests) live-probe that a REST card edit does not bump modifiedAt on the deployed pod and that ?fields=activities&cardId= answers scoped; OQ-R4b (owner) read the disableExportAvatars / disable-all-exports / disableActivities admin flags — they gate the per-card activity export's cost and feasibility; OQ-R4c (plan) who rewrites CARD.yaml — plugin (needs slug→folder resolution outside the run) or the run itself; OQ-R4d (plan) the per-card forward cap value and its exhaustion behaviour, the only real M6 tuning knob; OQ-R4e (sibling R3 boundary) adopt R3's pending-question read for the "blocked on a human?" test if it finds one.
next_suggested: merge the five RESEARCH-rN files into RESEARCH.md; planner should adopt snapshot-diff + scoped-activity-classifier as one detection chunk, put the card-state store on `.pipeline/cards/` (never ctx.storage, per M1), and specify the synthetic+queue+idempotent-id forward as a bounded one-liner per M6, with the wekan-mcp additions kept as two additive read tools rather than a new subsystem.
