# RESEARCH.md — AD-140 consolidated research bus (merge of rounds R1–R5)

Ticket AD-140 (`cf-140-feat-agent-card-reconcile`) · merged 2026-11-23 · **this merge pass
added no new research** — every fact below was established by one of the five per-topic
rounds (each ran in its own parallel session per the card) or by the pre-plan review. The
five sibling `RESEARCH-r*-*.md` files are the cited deep sources and stay untouched: this
file is the single briefing the planner and every later dev/test/review session reads at
run start; go to the sibling for full source lists, tables, and the argument behind a fact.

**Read order note:** four scout facts in `EXPLORE-*` are SUPERSEDED by the rounds (see §7
and the "Resolved by research" section of `DECISIONS.md`). Do not re-derive them from the
scout files — they predate the live-build probes.

**Build snapshot everything is graded against:** live host runs opencode **v2.3.2** +
OpenChamber **2.8.0** (two server processes sharing one `opencode.db`); repo plugin
semantics are pinned to **v2.1.4**; deployed WeKan is chart **12.99.0** (tag `v12.99`);
both Forgejos answer **15.0.10+gitea-1.22.0**.

## Round map

| Tag | Sibling file | Topic |
|---|---|---|
| R1 | `RESEARCH-r1-typescript-skills.md` | TS-authoring skills/tooling landscape; the type-check gap |
| R2 | `RESEARCH-r2-opencode-plugin-skills.md` | V2 plugin-API surface (version-resolved), authoring-skill landscape, failure modes |
| R3 | `RESEARCH-r3-session-awareness.md` | session awareness + creation, probed against the LIVE v2.3.2/OC 2.8.0 build |
| R4 | `RESEARCH-r4-card-change-detection.md` | WeKan card-change detection + hand-off primitives (tag-pinned source + live probes) |
| R5 | `RESEARCH-r5-forgejo-linkage.md` | Forgejo access + the card↔PR linkage design |
| RV | `REVIEW-existing-plugins.md` (not merged, cited) | fresh-eyes review of the system being replaced — B1–B3 blockers, M1–M8 majors |

## Evidence-class key (carried with every fact; a probed fact must stay tellable from a documented one)

- **[v12.99]** — WeKan upstream source read at the pinned deployed tag (R4).
- **[src v15]** — Forgejo source read at tag `v15.0.10`, the version both instances answer (R5). Swagger is disabled on both, so the pinned source IS the spec.
- **[live-2.3.2]** — probed today (2026-11-23) against the RUNNING opencode v2.3.2 server on this host: live OpenAPI contract, SSE captures, record reads (R3, R4).
- **[oc-src-2.8]** — OpenChamber 2.8.0 installed server source, read un-minified (R3).
- **[npm-diff]** — npm tarball type surfaces downloaded and diffed across versions (R2).
- **[live-forge]** — live unauthenticated probe of `git.spencerslab.com` / `git.scifi.farm` / GitHub API (R5). No forge writes were made by any round.
- **[live]** — other live-host evidence today: process tables, env probes, `opencode.db`/`.pipeline/` forensics (RV, R2, R4, R5).
- **[repo]** — read from this worktree (all rounds).
- **[doc]** — upstream docs/write-ups: directional practice, not authority for this instance (R1, R4, R5).
- **[inferred]** — marked reasoning from the above (R5).

## TL;DR (≤5 lines)

1. Every scout "can't do it" that mattered is overturned ON THIS BUILD: a pending question
   IS durable data (a Form), `/api/session/active` WORKS (process-local), per-card activity
   history IS cheap (scoped export), session-metadata events DO fire (decomposed). [live-2.3.2][v12.99]
2. Observe with: finished = `execution.*` + out-of-active-map + terminal `outcome` + `time.idle`;
   paused = pending question Form read; changed = snapshot-diff + activity classifier; objective
   met = card board-membership only — never a field, never an LLM judgment. (R3, R4, RV)
3. State lives on the filesystem (`.pipeline/`) and `opencode.db`, NEVER on `ctx.storage`:
   this host runs two server processes, so every single-process read or guard silently lies. (RV, R2, R4)
4. Hand-off = `synthetic` + `delivery:"queue"` + caller-supplied idempotent id, one short line,
   delta in `CARD.yaml` — never a user-message prompt, never a `question`, never session-recreation. (R4)
5. Forge link = branch name + `Card:` commit trailer + PR-body footer; per-card LABELS are
   rejected (their filter silently lies); reads need no token, any writer is owner-mint-gated. (R5)

---

## 1. What the reconciler can actually observe

The four detection questions, each reduced to surfaces that exist on the live build. The
full decision-matrix table is R3 "Detection design summary"; the spawn/deliver matrix is R4 §4.4.

### 1.1 Finished ("run ended") — exact, derived, never one field

- **Turn-end signal (proven live on a clean run):** `session.execution.started` →
  `session.execution.succeeded|failed|interrupted`, then the session leaves
  `GET /api/session/active` and its record gains terminal `outcome` + `time.idle`. **[live-2.3.2]** (R3 §2)
- **Poll-path rule (process-agnostic floor):** finished ⇔ not in the active map **∧**
  terminal `outcome` **∧** `time.idle` present; busy ⇔ in the active map **or**
  `time.busy`/`time.updated` fresh (the gate's tree-age rule stays the floor). No
  busy/idle/pending enum exists on the record — status is always derived. **[live-2.3.2]** (R3 §2)
- **`session.idle` / `session.status` exist in the vocabulary but DID NOT FIRE viewer-less**
  (two live turns; they are classified `durability:"ephemeral"`; OpenChamber's auto-review
  consumes `session.status` on viewer hosts and desktop hosts demonstrably emit duplicates).
  **Nothing may depend on them**; timestamps stay primary. (R3 §2 [live-2.3.2], R2 §3 [npm-diff], RV)
- **`GET /api/session/active` is live and populated on v2.3.2** — refuting the cf-50
  v2.0.32-era "returns `{}`" finding carried in `EXPLORE-session-api.md` — **but it is
  PROCESS-LOCAL**: the host runs two opencode servers (proven: pid 895:4096 + pid
  28770:49374 sharing one db; the same running session appeared on one port and was absent
  from the other). A single-port read silently under-reports; **absence means "not running
  here", never "idle"**. (R3 §2 + R4 §1.7 [live-2.3.2])
- **Await primitive:** `POST /api/experimental/session/:id/wait` long-polls until the agent
  loop is idle — exactly what OpenChamber's scheduler uses; cross-check settle with the
  active map + `GET /api/shell` + running background jobs. (R3 §2, §3 [live-2.3.2][oc-src-2.8])
- **Enumeration gotchas:** archived sessions drop out of the default list entirely — there
  is no top-level `archived` boolean on the record at all; archive state is `time.archived`
  (epoch-ms) and archived rows are found with `?archived=true` only. **[live-2.3.2]** (R3 §5;
  R4 §1.7 phrased it "filter-only" — both agree the boolean does not exist and the stamp
  under `time` does). The `{"data":…}` envelope, paginated walk + `cursor.next`, and
  read-merge-write for metadata are proven primitives to KEEP (R3).
- **Server-side list filters now exist** (`GET /api/session?directory=&archived=&parentID=&search=&cursor=`):
  the gate script's hand-rolled tree walk is redundant machinery for new code. **[live-2.3.2]** (R4 §1.7, §8)
- `outcome:None` rows include 13 h-old dead sessions — `outcome` alone is not liveness either
  (RV §4.3 [live]).

### 1.2 Question-paused — durable data, the real 15-minute clock

- **A pending question IS persisted session data:** the `question` tool creates a **Form**
  (`metadata.kind === "question"`), readable at `GET /api/session/:id/form` with
  `state.status ∈ pending|answered|cancelled`; `form.created/replied/cancelled` events fire.
  No `question.*` events exist in any version (V1's question endpoints unified into Forms).
  **[live-2.3.2]** (R3 §1; R2 §3 [npm-diff])
- **This dissolves RV risk B1** (paused run reads as dead): a session blocked on a question
  stays **busy/active forever** and never self-times-out (proven live; upstream #63376: an
  orphaned question suspends a resumed run indefinitely). The 15-min rule therefore has a
  real clock. Kept as a **gating acceptance criterion**: the reconciler must READ the Form,
  never infer a pause from tree-age (R3 §1; DECISIONS "Resolved by research").
- **The event stream is volatile by contract** (slow consumer drops events; misses are
  silent — #61658: a missed `form.created` hides the question until reload). So the
  **durable form read is the truth; `form.created` is only the timestamp accelerator**
  (`askedAt` = event `created` epoch-ms stored when observed — the Form record itself
  carries no ask-time; fallback stamp is `time.busy`, which a question pins). **[live-2.3.2]** (R3 §1)
- Practical shape: each tick, list forms per active/recently-busy session, keep
  `metadata.kind==="question"`; use the session-scoped route (the location-scoped
  `GET /api/form` only answers with the session's own `location[directory]` — #63376).
  Real question answers use field keys `q0,q1,…`; multiselect = string arrays; question text
  rides the form/field `title`. (R3 §1 [live-2.3.2][doc])
- On breach: record the question, then settle it so the run cannot suspend forever —
  `DELETE /form/:formID?message=…` (fires `form.cancelled`), optionally
  `interrupt?resume=false`. Whether to cancel is **plan decision P6** (research lean: cancel
  with message). (R3 §1, OQ-B)
- **Discriminator for "blocked on a human?":** adopt this Form read — NOT the `question`
  tool's `execute.before` hook (the only in-repo signal, and its plugin is owner-disabled),
  and never a timestamp heuristic (R4 §4.4 OQ-R4e deferred to R3; R3 §1 answers it).

### 1.3 Card-changed — human edits are the loud channel; agent edits are silent by design

- **The card document has NO `updatedAt` field at all.** Date fields are `createdAt`,
  `modifiedAt`, `dateLastActivity`, `listEnteredAt`, `archivedAt`. Any plan text naming
  `updatedAt` is wrong. **[v12.99]** (R4 §1.2)
- **`modifiedAt`/`dateLastActivity` bump on UI/DDP writes only** — every REST write goes
  through `.direct.updateAsync`, bypassing the `Cards.before/after.update` activity hooks and
  the schema autoValues. **[v12.99]** (R4 §1.2)
- **Per-card activity history IS readable over REST** via the scoped board export:
  `GET /api/boards/:id/export?fields=activities&cardId=<card>&attachments=false` — `cardId`
  is a first-class `EXPORT_SCOPE_KEYS` entry and the streaming exporter scopes
  `activitySelector` to the export's cards. This **corrects the scout's "full-board fetch
  cost" read** (which measured the non-streaming `build()` path). Still no per-card
  activities REST ROUTE exists (full route inventory checked). **[v12.99]** (R4 §1.1, §1.4)
- Cost caveats on that export: it appends an ungated `users[]` section and inlines local
  avatars as base64 unless the admin `disableExportAvatars` is on (payload-dominant term for
  a per-card poll); the "disable all exports" admin switch is a kill switch to degrade on.
  Admin-flag states were NOT read from the live instance — owner probe leg O6. **[v12.99]** (R4 §1.4, §1.8)

### 1.4 Objective-met — a board fact, never a session field

- **No session field means "objective met".** Authoritative signal: the card's list ⇒
  **Review / Finished** (board membership; dev-boards read). Run-ended is necessary, never
  sufficient. (R3 Extra-1; RV §4.3/M2 ruling: scope DOWN to explicit signals —
  **never an LLM judgment of "did the run achieve the card"**)
- Opt-in session-side corroborators exist, both app-computed on `metadata`:
  **goal mode** `metadata.openchamber.goal.status ∈ active|paused|blocked|budgetLimited|complete`
  (a classifier settles `complete`; the scheduler waits while `active`) and **work mode**
  `metadata.openchamber.work.state ∈ open|done` (auto-open EXCLUDES scheduled runs;
  `done` ≠ objective). Goal mode is currently off on live records. **[oc-src-2.8]** (R3 Extra-1)
- **The decision matrix (RV §4.3, adopted by R3/R4):** run-ended + card ∈ Review/Finished ⇒
  objective met; run-ended + card ∈ Executing + a fresh successor (parentID chain / slug-stack
  newest line naming a live session) ⇒ compaction handoff — do nothing; run-ended + Executing +
  no successor ⇒ crashed/abandoned ⇒ triage/relaunch. A handoff successor otherwise reads as
  "run ended" and double-spawns — resolving the successor chain before any spawn is mandatory
  (handoffs are frequent, not rare). **[live]** (RV) + (R4 §4.4 delivery-side twin)

### 1.5 The two-server topology — a first-class question for EVERY read

R4's named blind spot (RV saw it only as a storage hazard): two opencode processes share one
`opencode.db`. It silently corrupts three read classes: `ctx.storage` (guards never advance
on the storage-less process — §2.1), `/api/session/active` (§1.1), and any consume-once
event claim (§6: `setup()` fan-out). The plan must treat "which process am I asking?" as a
first-class question and read every server, or use only process-agnostic surfaces. (R4 §5; R3 "Verify live" 2)

---

## 2. Where state must live, and why

### 2.1 Ruled OUT: `ctx.storage` for any cross-process guard

- Symptom (a)'s root cause was **proven** to be a storage-binding capability flap ×
  two-process topology: 15 of 17 long-lived board-coord sessions re-injected the board block
  (worst 12/34 prompts); the kv once-mark rows existed but the serving process never
  advanced them — bind-level absence, not a read-shape bug. **Never rebuild such a guard on
  `ctx.storage`.** (RV §2(a) [live]; DECISIONS 2026-11-23)
- R2 corroborates: the docs specify storage "scoped by this plugin's ID" but say NOTHING
  about project/location scoping, and the repo carries two conflicting readings (D26
  "+project-id" vs question-notify "fleet-wide") — an unresolved live-probe item (P-list
  probe, R2 §4.5/OQ-R2-4). Do not bet cross-process correctness on an underdetermined surface.
- Tolerant-decode law (from the once-mark family): storage round-trips can return
  stringified values; `claimOnce`'s tolerant read is the proven shape,
  board-context's `typeof === "number"` is the failed one. (RV §1.15)

### 2.2 Ruled IN: filesystem at the canonical root + the shared db

- **`.pipeline/` at the canonical repo root is proven cross-process today** (lock beats and
  kv rows land from both processes). R4's concrete store: `.pipeline/cards/<cardId>.json`,
  record `{cardId, slug, sessionID, hash, projection, lastHumanChangeAt, lastForwardedHash,
  forwardedIds[], agentPublishedHashes[], updatedAt}`, written **tmp-sibling + rename**
  (the `writeLockAtomic` precedent — a torn file is "unreadable state, not free state"),
  plus JSONL audit rows with the existing `localIso` stamp convention. JSONL, not SQLite
  (zero-dep posture; matches the `events.log`/`timeouts.jsonl` vocabulary). **Bound the
  store's life** — retire records when a card leaves the tracked set (the `timeouts.jsonl`
  unbounded-hoard lesson). (R4 §4.1; RV §1.2 template)
- **The durable per-card run registry** (replaces pipeline leases as "which session runs
  which card"): restart-surviving via a setup scan rebuild, visible to both server
  processes, consulted before ANY spawn and by the re-keyed zombie firewall; carries the
  one-card-per-session (`already_held`) posture. RV blocker B3. The DECISIONS 2026-11-23
  ruling repeats: the `card-runner` state store is filesystem-backed, never `ctx.storage`.
- **Session-record metadata** is a legitimate state home (durable, compaction-surviving,
  readable via `/api/session/:id`) with two hard rules: **PATCH replaces metadata whole ⇒
  read-merge-write is mandatory**, and there is a **~3.0 KB session-metadata PATCH body limit**
  already observed to truncate a dispatcher write — reconciler bookkeeping on the session
  record MUST stay small. (RV §1.14 [live]; R3 §3)
- **Instruction entries** (`PUT /api/experimental/session/{id}/instructions/entries/{key}`,
  or `ctx.session.instructions.entry.*` — capability-gate, absent in 2.1.4 types, present
  2.3.2): durable keyed context announced at the next step boundary **without queueing a
  model turn**. The verified v2.3.0 write shape is `{sessionID, key, value}` — `{key,text}`
  throws. Correct home for "the card's current authoritative state"; wrong home for
  "the card changed" (no wake). (R3 §3 [live-2.3.2]; R4 §1.7, §4.3; RV §1.12 [live])
- **kv-namespace permanence:** the storage namespace is derived from the DECLARED plugin id
  — renaming `local.pipeline-locks` → `local.card-runner` silently orphans claims/child
  maps/once-marks and breaks restart-resume at cutover. That is plan decision P1. (RV §1.10; R2 §4.5)
- **Forge facts** live in the run registry / plan folder (one bounded record per run:
  `{forge, repo, pr_number, pr_url, head_sha, state, merged_sha, checked_at}`), plugin-read;
  the card gets one human-readable line in its existing summary comment; **PR/issue content
  never enters coordinator context and is never mirrored onto the board**. (R5 F4.1)
- **`~3.0 KB` cap + metadata merge law also bounds the no-op marker / spawn records** the
  reconciler writes on session records (RV m3).

---

## 3. Hand-off primitives for forwarding context into a live session

All live on v2.3.2 unless noted. (R3 §3, R4 §1.7, §4.3–4.4)

### 3.1 The verbs

- **Create:** `POST /api/session {agent, model:{providerID,id,variant?},
  location:{directory}, metadata, title}` → `{data:{id}}`; metadata survives creation and
  later merged PATCHes; children use `parentID` (and get the `<subagent>`-report wiring);
  reconciler spawns stay TOP-LEVEL. **Prompt:** `POST /api/session/:id/prompt`
  `{text, …, delivery, resume}` runs **unattended** — proven to completion with no viewer.
  **[live-2.3.2]** (R3 §3)
- **Three input doors, one winner per purpose** (R4 §4.3):
  | Door | Verdict |
  |---|---|
  | `prompt` (user message) | works but **renders as if the human spoke** — a lie in the transcript for a machine-detected notice |
  | **`synthetic`** | **recommended for change-notices**: first-class non-user inbox item, carries `metadata` (`{source:"card-reconcile", cardId, changed:[…]}`), participates in the same idempotent inbox dedupe |
  | instruction entry (`key:"card-state"`) | the complement: durable authoritative state, no wake, no extra turn — NOT for change notices |
- **Delivery:** `steer` (default) delivers before the next model call, even mid-work;
  `queue` waits for the current turn to finish, delivering one item at a time. **Use
  `queue` for change-forwards** — upstream's own advice for loop drivers, plus the footgun
  that a `steer` admitted just before a human hits Esc **runs anyway** (interrupt
  `resume:true` resumes pending steers; queued items stay parked). `resume:false` records
  input without scheduling execution. **[doc: upstream `specs/v2/session.md` + live schema]** (R4 §1.7)
- **Idempotency is built in:** reusing a caller-supplied inbox-item `id` with matching
  session+type is idempotent ("first admission wins; retried payload/metadata/delivery
  ignored") — a **free dedupe key** for replaying ticks. (R4 §1.7, §4.2)
- **Plugin-ctx parity:** `ctx.session.prompt/synthetic` carry `delivery`;
  `ctx.session.instructions.entry.{list,put,remove}` exist (capability-gate ~v2.2.0);
  **inbox list/update/cancel are NOT on the plugin ctx — those need HTTP**. (R4 §1.7 [live-2.3.2][doc])
- The wake path for scheduled/external drivers stays `ctx.session.prompt` on the tracked
  session; RPC (`ctx.rpc.register`) is the documented door for plugin-exposed methods, with
  two laws to respect: event subscriptions are **live-only** (disconnected subscribers miss
  events) and external clients see events from every location (check `event.location`). (R2 §3)
- There is **no `ctx.prompt`/`ctx.summarize`**: the surfaces are `ctx.session.prompt` /
  `.compact` / `.generate` and `ctx.experimental.generate.text` (`ctx.generate.text`
  deprecated). (R2 §3 [npm-diff][doc])

### 3.2 Decide the run's state FIRST, then act (R4 §4.4 matrix, adopted)

| Run state | Evidence | Action |
|---|---|---|
| Running | in SOME process's active map, or `time.busy/updated` fresh | `synthetic` + `queue`, idempotent `id` |
| Idle, resumable | terminal `outcome`, no no-op marker | same call (an inbox item on an idle session starts it — desirable, not an error) |
| No-op ended | `metadata.openchamber.kind==="scheduled"` **∧** `metadata.pipelineNoop.reason` non-empty | **do not wake** — that exit was designed; leave the state file |
| Handoff successor | successor carrying the run's card/slug/`parent` | deliver to the SUCCESSOR, once |
| Gone / archived | 404; archive found via `?archived=true` | **never recreate** — persist the notice undelivered; spawn ownership is the coordinator's |
| Wedged | repeating `session.compaction.failed` rows | never pile prompts (#56784 wedge class); relaunch-FRESH is the coord's call |

Plus: **a change notice must never use the `question` path** (human-blocking gate), and a
change-forward must never paste card payloads into prompts. (R4 §4.4)

### 3.3 The M6 bound (the forward must not become the new context injector)

RV measured this ticket's own first prompt at 8,310 chars, 99.6 % injected card mechanics;
R4 adopts the ruling verbatim: **re-write `CARD.yaml`, forward ONE line** — changed field
names + actor + "re-read CARD.yaml", target well under 300 chars (the 240-char
`MAX_OUTBOUND_MESSAGE` precedent); dedupe by content (`hash ≠ lastForwardedHash`) with the
inbox `id` as the replay-safe key; **coalesce** multiple edits into one forward; **cap
forwards per card** (small N, then stop + human-visible flag). Plan decides the cap value (P3). (R4 §4.2; RV §4.1)

---

## 4. Board + forge linkage, and the card-dump surface

### 4.1 WeKan detection stack (R4 §2–3) — ranked, combined into one loop

1. **Snapshot-diff (the floor, required):** content-hash a canonical projection per tracked
   card. The ONLY detector that sees the hook-blind fields (REST label / custom-field
   writes produce no activity and no timestamp). Hash fields: title, description,
   `listId`/`swimlaneId`, checklist `(title, finished)` pairs in stored order, custom-field
   values **name-keyed** (`slug`, `Priority`), `labelIds` as a **sorted set**, `archived`,
   comment **id-set + newest id** (timestamps on comments are unreliable), `parent_id` +
   dependency-edge set, and `modifiedAt`/`dateLastActivity` **hashed but classified
   separately**. **Exclude `sort` entirely** — it churns when OTHER cards insert. Cost: one
   read per tracked card per tick; a board-wide tick is the ONE already-proven
   `preload_board` export call. **[v12.99]** (R4 §2 Rank 1)
2. **Scoped activity export (the classifier, cheap):** per-card export (§1.3) explains any
   delta with **who + when + old→new for prose/dates** — and it arrives **pre-filtered to
   human edits** for title/description/checklists/custom-fields, because **every REST write
   path bypasses the activity hooks** (`.direct.updateAsync`; upstream comments #6793/#5681
   admit it). For title/description and dates the activity carries `oldValue`+`value`;
   custom-field activities carry the AFTER value only (previous value must come from the
   stored snapshot — a second reason Rank 1 exists); tick/label changes are typed
   transitions. The four rows that log on BOTH paths (move, archive, delete, comment) are
   exactly where the self-change filter is mandatory — and the reconciler's own leg writes
   moves and comments every run. **[v12.99]** (R4 §1.3, §2 Rank 2)
3. **Timestamps (the free hint, never the detector):** a `modifiedAt`/`dateLastActivity`
   bump with no agent action = "a human was in the UI" (DDP-only bump). Precisely INVERTED
   from what a naive reader assumes — label it in code. **[v12.99]** (R4 §2 Rank 3)
4. **Webhooks: stay cut** — independent, source-grounded reasons: webhook coverage inherits
   every `.direct` blind spot (it cannot see the edits we most need), delivery is
   fire-and-forget with no retry/ordering, `hideIdentity` can strip the actor field the
   self-change filter needs, and an in-cluster receiver is refused by default (new infra).
   The surveyed consensus (webhook = latency path over a reconcile poll = truth) collapses
   to poll-alone here because the poll is the only path that sees the blind-spot fields.
   Extension point if preemption-on-edit is ever wanted: a webhook that only WAKES the tick,
   never carries the decision. **[v12.99][doc]** (R4 §2 Rank 4; confirms RV M8 on evidence)

**Self-change filter (mandatory, or the loop oscillates):** primary = **actor identity** —
`activity.userId` is unspoofable (`req.userId` comes only from the bearer token; a body
`authorId` mismatch is recorded as spoofing and ignored), and the agent's own id is already
computed inside wekan-mcp (`GET /api/user` at startup) — expose it as a `whoami` read tool
rather than hardcoding. Free pass = the hook-blind fields (a delta there with no
agent-attributed activity ⇒ human — sound ONLY while our writes keep using `.direct`; name
the mechanism in a code comment). Backstop = **agent-published-hash** (Kubernetes
`observedGeneration` discipline: compare against the last state the run itself authored; a
clean reconcile writes NOTHING). Rejected: body `authorId` (dead), time-window ignores
(drop genuine human edits). Fail-open on ambiguity (treat as human) but the forward dedupe
makes a misclassification cost exactly one forward. **[v12.99][doc]** (R4 §3)

### 4.2 The card-dump surface (`CARD.yaml`)

- `get_card_details` already returns the whole structured card (every checklist with items
  and tick state, custom fields raw, labels named, edges, slug stack) — the YAML dump needs
  **NO new wekan-mcp capability**; the `format: yaml` tool-argument ask stays CUT (separate
  container-build chain, different card). (RV §5 scope cut)
- Mid-session staleness is unsolvable by construction: accept **snapshot-at-subagent-launch**
  semantics and stamp it in the file header (the board block's "snapshot, never a freeze" posture). (RV §4.2)
- Undefined homes the plan MUST name one rule for: Worktree-unchecked runs (no plan folder),
  grouped siblings (one dump per sibling card), Rework re-picks (slug `-1` changes the
  folder). Who writes it (plugin, needing slug→folder resolution outside the run, vs the
  run) is plan decision P2. (RV §4.2/M5; R4 OQ-R4c)
- The claim-time card-details block belongs OUT of tool answers going forward (it landed in
  the `pipeline_claim` answer and degraded anyway — the coord paid the fan-out in its own
  context); the dump is its home. (RV §4.1)
- Two ADDITIVE wekan-mcp read changes replace the "new subsystem" framing: (a) per-card
  `activities` via the scoped export (or a `list_card_activities(board_id, card_id)`),
  (b) `whoami`. Both credential-free reads on routes already in use; Forgejo CI build stays
  the validation gate. (R4 §6.3)

### 4.3 Forgejo linkage (R5)

- **Landscape:** two Forgejos, one repo, both serving `CuratedForest/SpencersLab`
  **publicly** — prod/canonical `git.spencerslab.com` (ROLE=prod; the only main-fan-out
  writer via `.forgejo/workflows/main-sync.yaml`, non-force to GitHub + dev) and dev
  `git.scifi.farm` (ROLE=dev; runs the daily Renovate pass). Both `15.0.10+gitea-1.22.0`;
  swagger disabled → pinned source is the spec. **No Forgejo MCP server exists in the
  fleet**, and none is mature upstream. **[live-forge][repo]** (R5 F1)
- **Credentials today: ZERO reach agent sessions.** `FORGEJO_*` is absent in this workspace;
  the `forgejo-token` Bitwarden item renders only under the dev umbrella and points at the
  DEV forge. Reads work unauthenticated (public repo); **any writer is gated behind an
  owner-minted PAT** (mirror the `FORGE_PUSH_TOKEN` precedent: dedicated bot account,
  least scope — `read:repository`+`read:issue`; `write:issue` only if label/comment writes
  are adopted). Scope trap worth repeating: **on a public repo a wrongly-scoped token fails
  where no token succeeds** — attach tokens only to families they satisfy.
  **[live][src v15]** (R5 F1.3–F1.4, F2.1, F5.2)
- **Polling shape (deployed API is built for this):**
  `GET /repos/{o}/{r}/issues?state=all&type=pulls&since=<RFC3339>` covers issues AND PRs in
  one cheap delta (note: `/pulls` alone has NO `since` — do not build the naive variant);
  `GET /pulls/{base}/{head}` is the zero-write branch→PR lookup (live-proven);
  `/pulls/{index}/pull` does NOT exist at this tag (404s deceptively); `/merge` 404 ⇒
  not merged; `/commits/{sha}/pull` is best-effort only. **[src v15][live-forge]** (R5 F2.2)
- **The card↔PR join — three layers, NO labels:**
  1. **Branch name = the slug** (`cf-<cardNumber>-<type>-<desc>`, re-picks `-N`) — already
     law, already mints the branch; read back via `/pulls/{base}/{head}`, fallback
     `since=`-delta + `head.ref` prefix match. (Linear's mechanism.)
  2. **Commit trailer `Card: AD-<n> <slug>`** on chunk commits via `git interpret-trailer` —
     git-only, survives squash-merge, answers "landed?" with `git log --grep` and no API.
     The coordinator is the sole chunk committer ⇒ exactly one writer obeys it.
  3. **PR-body footer** `wekan-card: AD-<n> · <slug> · card=<_id> · <url>` — accelerator
     only (humans won't type it); carries the card `_id` because `card_number` re-counters
     on board moves and is display-only, never a join key.
  **[src v15][live-forge][doc: Linear/Jira/GitHub/GitLab prior art]** (R5 F3)
- **Per-card LABELS ARE REJECTED** (the card's literal "tag the PR" ask): label CREATION is
  repo-writer-gated; `GET /labels` is `[]` on both instances despite `renovate.json` asking
  for `dependencies` (the lab has never landed a label via API — the one hypothesis, token
  scope, needs one run-log line or a live-fire probe); and decisively, **a `labels=` filter
  naming a non-existent label silently returns UNFILTERED results** — a label-based join
  fails silently, the same silent-drift class as the `Repo:` label-spelling law. If the
  owner wants a visible badge, ONE static owner-created label (e.g. `agent-run`) marks
  agent PRs; the card identity stays in branch/trailer/body. (R5 F3.3, F5.1)
- **Forgejo webhooks also stay dropped:** outbound-only, repo-hook routes are
  `reqToken()+reqAdmin()+reqWebhooksEnabled()`, `ALLOWED_HOST_LIST=external` refuses an
  in-cluster receiver without a config change, `DELIVER_TIMEOUT=5s`, no retry knobs at this
  tag — and the reconciler's question ("landed?") is a STATE question the poll answers in one
  call. Sanctioned low-latency seam if ever needed: `POST …/actions/workflows/{file}/dispatches`
  (`write:repository`), not a webhook. **[src v15]** (R5 F5.3; sibling ruling holds)
- **No new WeKan custom field for the link** — the board roster is exactly two fields
  (`slug`, `Priority`) and adding a third drags the provision engine, fixtures, roster law,
  and backfill scripts; board structure is human-owned. Forge truth stays on disk, never
  mirrored onto the card beyond one summary-comment line. (R5 F4.1)
- **Forge context bound (R5 F4.2, six points for the plan):** one forge read per card per
  tick (+ at most one repo-wide `since=` delta per tick); cross-process once-mark on the
  same cross-process surface as everything else (§2), NEVER `ctx.storage`; forward a ≤3-line
  delta (`landed|pending|none|unknown` + URL + state/sha), never payloads/bodies/timelines;
  TTL staleness, not per-prompt re-reads; failures recorded as `{state:"unknown", reason}`
  — recorded, never a stall; no board mirroring.

### 4.4 The canonical-PR-home split-brain (must be RULED before any "did it land?" logic ships)

`pipeline-push-pr` pushes the ticket branch to `origin` = **Forgejo prod** but opens the PR
with **`gh pr create`** on **GitHub**, where that branch was never pushed — while GitHub
carries a live `renovate[bot]` lane (PR #927 @ 2026-11-19; 7 merges since 2026-11-01) and
the forge lane is new (111 objects: 110 pulls + 1 Renovate Dashboard issue). A reconciler
that guesses a forge answers "nothing landed" for PRs that exist on the other side.
R5's lean: **Forgejo prod is the card-link canonical surface** (where branches, CI, and
`origin` live); GitHub stays a main-mirror; the reconciler reads exactly ONE forge.
Rule is owner-gated (O6/O2 below) because it also changes a MUST-load contract
(`pipeline-push-pr`). **[repo][live-forge]** (R5 F1.5, F5.4)

---

## 5. TypeScript / plugin-authoring posture, and the real validation gap

### 5.1 No skill to adopt; don't author one inside the ticket

- The `/opencode` skill is official and **binary-embedded** in `@opencode/cli` v2.3.2; its
  Plugins section is an index of three doc URLs — an index, not an authoring guide. [live]
  Upstream, **every mature plugin-authoring skill teaches the V1 API that does not run in
  V2**; exactly one V2-targeted skill exists (thin, pinned 2.0.20). **Recommendation
  adopted: do NOT author a plugin-writing skill in AD-140** — plugin chunks load `/opencode`
  and fetch the V2 server/RPC/plugins-config pages as their API ground; the repo-specific
  plugin law already lives in `EXPLORE-plugins.md` §0/§6 (the bus carries it). A vendored
  `opencode-plugin-v2` reference skill is a follow-up-card idea for when a SECOND ticket
  touches plugin code. (R2 §1–2, Recommendation)
- One cheap import now: verify API surfaces against the **installed build's `.d.ts`** (the
  community skills' best meta-pattern — R2 itself did exactly that via npm tarball diffs). (R2)

### 5.2 Version posture — author against 2.3.2, capability-gate everything else

- Live build **v2.3.2**; npm `@opencode/plugin` latest **2.4.1** (docs describe the 2.4.x
  superset); repo semantics pinned **v2.1.4**. Event vocabulary 2.1.4→2.3.2: **+5 events,
  0 removals** (2.4.1: +1). Per-tool `codemode` option and `ctx.experimental.automation`
  are **2.4.x-only → ABSENT**; `instructions.entry` is present on 2.3.2 (absent 2.1.4) — the
  repo's capability-gated seams cover the real deltas. **[npm-diff]** (R2 §3)
- **D29 holds on the live build:** plugin tools are catalog/Code-Mode-only on 2.3.2 (no
  per-tool direct-tool path exists pre-2.4) — the "reachable ONLY through Code Mode"
  phrasing is the designed default, not a bug. **[npm-diff][doc]** (R2 §3)
- **`session.updated` NEVER EXISTED** in the V2 vocabulary — it is decomposed into
  `session.metadata.updated` / `session.renamed` / `session.archived` / `session.unarchived`
  / `session.viewed`, which **all fired live** on the matching PATCH. The pipeline-locks
  "dispatcher tracking" leg that today degrades to hourly self-heal becomes live-able.
  The subscribable `types` server-side filter works on 2.3.2 (the 2.1.4 silent-drop hazard
  is gone). **[live-2.3.2][npm-diff]** (R2 §3; R3 §4)
- Hook/API shape worth pinning in chunks: default export `{id, setup(ctx)}` (`Plugin.define`
  adds typing, not magic); discovery loads BOTH `.opencode/plugin/` and `.opencode/plugins/`
  (plural is the docs' V2 recommendation — singular-vs-plural is a decide-once free choice,
  P4); configured local plugin paths must be DIRECTORIES; `-<id>` disables by declared id;
  plugin files **hot-reload into live sessions** (editing plugin source is a live change);
  missing package deps ⇒ plugin `failed` (visible via `GET /api/plugin`); unknown event
  `types` names are ignored with a log warning; multiple registrations of the same hook are
  allowed and run in plugin order — the repo's "one compaction hook" is a blast-radius
  RULING, not an API limit; import only leaf functions out of live plugin files
  (dual-registration law, repo-discovered). (R2 §3, §4.2)
- Scheduled-loop delivery (for the reconcile loop's own scheduling): a project-scope
  `.agents/loops/*.md` parses frontmatter `{name, schedule, model, agent?, timezone?,
  enabled?}`; `enabled` defaults FALSE; fingerprint = sha256 over name+schedule+execution
  (NOT `enabled`/path) ⇒ any body edit re-locks; a project-scope loop with
  fingerprint≠`loopApprovals` is FORCED disabled; scheduler creates the session
  (`metadata.openchamber.kind="scheduled"`) then prompts the loop body. **The repo ships
  the file; enabling + first approval is a one-time owner UI act** — the plan's final task
  is "create the loop file + hand over the approval step", never "enable the schedule".
  **[oc-src-2.8]** (R3 Extra-2; DECISIONS 2026-11-23)

### 5.3 The TypeScript validation gap — and its cheap fix

- **The gap:** Node v26 **type-strips with ZERO type-checking** (ignores `tsconfig.json`);
  aislop is static, not type-aware; the 393-test `node --test` suite pins runtime — so a
  pure type error in `card-runner` is invisible until runtime. That is the whole R1 ask.
  **[doc][repo]** (R1 TL;DR, F4)
- The fix shape (if the owner rules yes — owner question O1): pinned
  **`npx --yes --package=typescript@<pin> -- tsc --noEmit -p <tsconfig>`** + a hand-written
  Node-shaped tsconfig (`noEmit`, `nodenext`, `allowImportingTsExtensions`,
  `erasableSyntaxOnly`, `verbatimModuleSyntax`, `strict`, `types:["node"]` + `@types/node`).
  TS 7.0 (native port, 8–12× faster) makes a full check ~1 s. **The `npx tsc` stub trap is
  real** (deprecated npm `tsc` 2.0.4 package — never bare `npx tsc`). This is the repo's
  FIRST npm dev surface: `.gitignore` gains `node_modules/`; that is exactly why it is
  owner-gated. Weakest claim (10-second probe before freezing chunk Commands): bare
  `tsc --noEmit` fails without `@types/node` — follows from the docs, NOT executed here. (R1 F5, C3, Reliability)
- The plugin already lives under Node's contract — erasable-syntax-only (`enum`/runtime
  `namespace`/parameter-properties/`import alias`/decorators are hard errors), **`.ts`
  extensions mandatory in local imports**, `type` keyword mandatory for type-only imports,
  `node:` prefixes. Keep it. (R1 F4 [repo])
- Vendor candidate: **`microsoft/typescript-skills`** (MIT, TS team; `typescript-strict`
  = baseline-first, no-opt-outs-to-get-green, `@ts-expect-error` over `@ts-ignore`, the
  stub-trap warning). Young/niche (124 installs) but vendored-and-audited beats the
  install-count heuristic (contradiction C1); the anonymous review-skill tail stays skipped.
  Vendoring home (`.rulesync/skills`+VENDORED.md vs `.agents/skills`+skills-lock) and
  CI-vs-plan-Commands placement are open plan items; `marius-townhouse` (license "Other")
  and unlicensed Metabase skill fail the bar. (R1 F2, C1, ADOPT/SKIP)
- **Skip** (settled): OpenCode `lsp`/`formatter` enablement (dep-gated on a package.json the
  repo does not have; V2 docs are LSP-silent; OpenCode's own docs recommend the CLI-loop
  posture — "run lint, typecheck … directly … document those commands in instruction files
  or skills"); eslint; prettier auto-formatting (byte-pin hazard); deno/bun (absent). (R1 F3, C2)
- Keep the existing gates unchanged and teach the skill they exist: `aislop-gate` (auto,
  pinned npx), `aislop ci --changes` (CI floor 80 + no error-severity), `node --test`
  runtime pins, `comment-slop`. Adjacent: aislop pin drift 0.20.0 → 0.22.3 = follow-up
  card, not AD-140 (Lifecycle leaves follow-up cards unchecked → rides the final summary). (R1 F1, F6, OQ4)

---

## 6. Scope rulings the research settled

Settled BY research (the plan inherits; the argument is in the sibling):

1. **Webhooks dropped on BOTH platforms, independently** — WeKan (coverage inherits the
   `.direct` blind spot; fire-and-forget; identity redactable) and Forgejo (admin-gated,
   default host allow-list, no retries, state question). RV's M8 cut is now evidence-backed. (R4 Rank 4; R5 F5.3)
2. **`format: yaml` wekan-mcp argument dropped** — the dump needs no new tool arg (RV §5; R4 §4.2 corroborates: `get_card_details` is already structured).
3. **"Objective completed" scoped to explicit signals** (card membership + release comment
   + successor-chain discrimination); **LLM-judged objective-completion dropped** (RV §4.3/M2; R3 Extra-1).
4. **Pipeline leases CAN be retired** — Executing-membership + `already_held` was always the
   card-level guard; what MUST survive into `card-runner`: re-keyed zombie firewall (run
   registry), durable cross-process per-card run registry with restart-resume, dead-run
   alerting/forensics, the wake contract, the compaction contract, the no-op marker
   (writer predicate re-defined — it references `pipeline_claim`, M4), `localIso`, the
   never-throw law, consume-once dedupe. Dropping leases makes single-scheduler an
   OWNER-enforced invariant — state it (RV §3, the trade the owner must see; DECISIONS 2026-11-23).
5. **No plugin-authoring skill inside the ticket** (R2 Recommendation); **no TS skills
   beyond the one vendor candidate + one small repo-local "plugin-lanes TS" skill** (R1 ADOPT).
6. **Per-card forge labels rejected; per-card WeKan custom field rejected** (R5 F3.3/F4.1).
7. **Forge posture: plugin-direct REST via `fetch` (zero deps), reads credential-free;**
   MCP tier deferred (payload-in-context is the very symptom being retired; upstream
   options immature — one active MIT 103-tool TS server, one GPL "mirror-only" with a
   context-overflow report, one stale, one unlicensed); CLI (`gt`, tea's official successor)
   for humans/probes only; the only sanctioned inbound poke is the workflow-dispatch API. (R5 F2.4, Ranked recommendation)
8. **The loop ships disabled and stays owner-enabled** (R3 Extra-2; DECISIONS).
9. **AGENTS.md/`.rulesync` regeneration drift repair lands in the FIRST commit** (RV §5 —
   verified red at HEAD; pre-existing, not research, but it gates everything).
10. **Detection design settled:** snapshot-diff floor + scoped-activity classifier +
    timestamp hint, one apply function, filesystem state, bounded forwarding (R4 combined
    recommendation — the plan should carry it as ONE detection chunk, not a subsystem).

## 7. Contradictions — resolved, with the winner (do not re-derive these)

| # | Clash | Winner & surviving caveat |
|---|---|---|
| X1 | `GET /api/session/active` "proven unusable" (`EXPLORE-session-api.md`, a v2.0.32/cf-50-era finding) vs **populated on v2.3.2** | **Live build wins: it works** [live-2.3.2] — BUT it is **process-local** (two servers proven; same session visible on one port only). Read every process; absence ⇒ "not here", never "idle". (R3 §2; R4 §1.7) |
| X2 | Scout: per-card activities cost a full-board fetch vs source: `cardId` is a first-class export scope key | **Pinned source wins: per-card activity reads are cheap** [v12.99]. The scout read the non-streaming `build()` path; the route uses the streaming path, which scopes. Still no per-card activities REST ROUTE. (R4 §1.4, §5) |
| X3 | Activity log silent on REST writes = obstacle vs **the free agent-vs-human discriminator** | **Discriminator.** For title/description/checklists/custom-fields the log is human-only — "did the human change the brief?" is answered without a self-change filter; the four both-path rows (move/archive/delete/comment) are where the filter is mandatory. Confirms the `modifiedAt`-no-bump scout finding and turns it into the mechanism. [v12.99] (R4 §1.3) |
| X4 | RV risk B1: a question-paused run reads as dead (frozen `time.updated`, no question events, hook-plugin disabled) vs a pending question is a **durable Form** | **R3 dissolves it:** `GET /session/:id/form` (`kind==="question"`, `state.status==="pending"`) IS the clock; the paused session stays busy/active forever. Surviving gate: reconciler must READ the Form, never infer from tree age; events are accelerators only (volatile stream, #61658). (R3 §1; DECISIONS) |
| X5 | Docs teach `session.idle` as the completion signal (and desktop hosts emit it ×5–7, #65834) vs **it did not fire viewer-less here** | **Neither generalizes: emission is host/version dependent.** The reconciler must not depend on `session.idle`/`session.status` [ephemeral class, npm-diff]; use `execution.*` + active map + `outcome` + `time.idle`. Re-probe with a viewer attached before ever supplementing. (R3 §2; R2 §3) |
| X6 | Card's literal ask "tag the PR with the card ID" (labels) vs prior art + this deployment's traps | **Branch name + `Card:` trailer + body footer wins; labels rejected** — creation repo-writer-gated, zero labels ever landed on either instance, and `labels=` on a missing label **silently returns unfiltered results** [live-forge]. (R5 F3.3, F5.1) |
| X7 | Ask's field list names `updatedAt` vs schema | **Schema wins: there is NO `updatedAt` on the card document** [v12.99]; and `sort` must be EXCLUDED from change detection entirely. Fix at planning, not inherited. (R4 §1.2, §2) |
| X8 | `session.updated` listener (repo-era assumption) vs vocabulary | **`session.updated` never existed in V2** [npm-diff, all three versions probed]; the decomposed events fire live on 2.3.2 [live-2.3.2]. (R2 §3; R3 §4) |
| X9 | Live docs (2.4.1) feature set vs live runtime (2.3.2) | **Live build wins: author to 2.3.2, capability-gate the 2.4.x deltas** (`codemode` per-tool, `experimental.automation` ABSENT; `instructions.entry` PRESENT). (R2 §3) |
| X10 | `steer` is the platform default vs `queue` safer here | **`queue`**, on upstream's own loop-driver advice + the Esc/resume footgun; `steer` only for an owner-requested preemption later. (R4 §1.7, §4.3) |
| X11 | `find-skills` install-count heuristic vs the TS-team skill | **Vendored-and-audited (MIT, pinned, deviation-noted) outranks the count**; the count still vetoes the anonymous tail. (R1 C1) |
| X12 | Docs examples use `.opencode/plugins/` (plural) vs the repo's working `.opencode/plugin/` | **Both load [doc, migrate guide]; decide once for card-runner (P4)** — cosmetic, zero re-pin either way. (R2 §3) |
| X13 | Upstream #65842: plugin tools missing from catalogs since 2.3.2 vs **this ticket's own `pipeline_claim` working today** | **Unresolved upstream vs live tension → a shipping-build verification duty (R-1 below), not a design veto.** Trust the live counter-evidence for THIS host; re-prove every card-runner tool leg. (R2 §4.3) |
| X14 | `ctx.storage` scope: docs "scoped by ID" vs repo D26 "+project-id" vs question-notify "fleet-wide" | **Genuinely underdetermined upstream — live-probe item, not a doc question (R-9).** Either way the namespace rides the declared plugin id ⇒ the id keep-vs-rename decision (P1) is load-bearing. (R2 §4.5; RV §1.10) |
| X15 | "Webhooks are the modern event-driven choice" vs survey consensus + this instance | **Poll alone.** The reconcile poll is the correctness layer AND the only path that sees the hook-blind fields; a webhook would share the blind spot it is meant to cover. (R4 Rank 4; R5 F5.3) |

## 8. Owner-gated — the batched question round (NOT plan decisions)

Each with research's recommended answer first, per the batched-question protocol. Pool is
STATE.json `open_question_pool_for_batched_round` plus the forge legs.

- **O1 — npm dev surface** (R1 OQ1): adopt the pinned `tsc --noEmit` gate (+ `@types/node`,
  tsconfig, `.gitignore` +1 line — the repo's FIRST npm surface), or stay zero-dep and let
  type errors surface at runtime? **Recommend: adopt** (TS7 makes the check ~free; the gap
  is exactly what R1 was asked about). If adopted, run the 10-second bare-tsc probe (R-11)
  before freezing Commands.
- **O2 — `question-notify`: re-enable vs absorb** (RV OQ-R1; R3 OQ-C): the phone channel is
  **owner-disabled since 2026-11-21** while the Awaiting-Answers alert path assumes it. The
  research law stands either way: `card-runner` owns the question detection via the durable
  Form read, independent of question-notify's state. Owner must rule (a) re-enable vs absorb
  the three legs, and (b) whether the >15-min alert pushes via the admin HA tier (like the
  reap alert) or stays silent. **Recommend: absorb into card-runner; push via HA only if the
  phone channel returns.** Do not design alerts that assume the disabled channel.
- **O3 — provision the `Awaiting Answers` + `Timeout` lists, or accept the jsonl degrade as
  permanent** (RV OQ-R2/m1): the reaper's board leg has NEVER succeeded in production (every
  `timeouts.jsonl` row is a degrade; the Timeout list does not exist on the live board).
  Provisioning is owner-executed through the provision engine (lists are human-owned).
- **O4 — forge PAT minting** (R5 OQ-R5a): mint the bot account + scoped PAT
  (`read:repository`+`read:issue`; `write:issue` only if writes are adopted)? Which
  Bitwarden item, and which location receives it (the PLUGIN, not the workspace — gpu
  template carries no `FORGEJO_*` at all)? Gates ANY forge writer.
- **O5 — canonical PR home** (R5 OQ-R5b + the split-brain trap, §4.4): rule **Forgejo prod**
  vs the GitHub mirror; if Forgejo, the `pipeline-push-pr` `gh pr create` leg changes —
  owner-owned because it edits a MUST-load contract. Pre-existing GitHub-mirror main
  divergence (OQ-R5e) is informational, out of scope.
- **O6 — live-fire probe legs needing credentials/admin access** (no agent session has
  them today; each is cheap and retires the last assumed-not-verified cells):
  - WeKan (R4 OQ-R4a, 2 requests): a REST card edit does NOT bump `modifiedAt` on the
    deployed pod; `?fields=activities&cardId=` answers scoped.
  - WeKan admin flags (R4 OQ-R4b): read `disableExportAvatars` / "disable all exports" /
    `disableActivities` — they gate the activity-export cost/feasibility.
  - Forgejo (R5 Ranked step 1): public read + `/pulls/{base}/{head}` lookup + the label
    probe (create→add→read→remove on a throwaway PR) against prod — required before any
    label/writer code is trusted; also settles the Renovate zero-label hypothesis.

## 9. Plan decisions (planner/coord rule these; do NOT defer to the human round)

- **P1 — plugin id:** keep `local.pipeline-locks` inside `card-runner` (zero kv migration —
  the state namespace rides the declared id) vs rename + migrate rows at setup (RV §1.10/B3; R2 §4.5).
- **P2 — `CARD.yaml` writer:** plugin (needs slug→folder resolution outside the run —
  workable via the `cf-<cardNumber>-…` convention + `.agents/plans/<yyyy>/` scan) vs the run
  itself; plus ONE rule covering the three undefined homes (Worktree-unchecked run, grouped
  sibling, Rework re-pick) (RV M5/§4.2; R4 OQ-R4c).
- **P3 — per-card forward cap** value + exhaustion behaviour (silent stop + audit row vs
  human-visible nudge) — the only real M6 tuning knob (R4 OQ-R4d).
- **P4 — plugin dir:** singular `.opencode/plugin/` (zero re-pin) vs plural (docs-preferred)
  — both load; decide once, pin in DECISIONS (R2 OQ-R2-2).
- **P5 — objective detection:** board-only (card ∈ Review/Finished) vs also enable goal mode
  on spawns for a `goal.status==="complete"` corroborator. **Research lean: board-only** —
  goal mode adds a small-model auditor and is currently off on this host (R3 OQ-A).
- **P6 — on 15-min breach:** cancel the pending Form (with message) vs leave it pending and
  only move the card. **Research lean: cancel** — otherwise the orphaned question suspends
  the run forever (#63376) (R3 OQ-B).
- **P7 — forge record home:** `STATE.json.forge` vs the run-registry row — ONE record,
  plugin-owned; two copies recreate drift (R5 OQ-R5f).
- **P8 — forge-issue scope:** is forge ISSUE state in scope at all (exactly 1 pure issue
  live) — if unused, the read surface halves to pulls/branch lookups (R5 OQ-R5d). Labels
  adopted vs dropped is research-recommends-**dropped**; note label CREATION would be an
  owner act anyway (repo-writer-gated + human-owned doctrine) (R5 OQ-R5c).
- **P9 — TS-skill mechanics (if O1 lands):** vendoring home for `typescript-strict`
  (`.rulesync/skills`+VENDORED.md vs `.agents/skills`+skills-lock.json) and whether `tsc`
  joins CI or stays plan-Commands-only (R1 OQ2/OQ3).
- **P10 — wave split confirmation:** the card as written is ≥3 tickets; carry the review's
  split (W1 context hygiene incl. AGENTS.md drift repair in commit 1 → W2 question flow →
  W3 lock retirement only after W1-2 prove out) or cut further (RV §5; STATE pool #8).

## 10. What must be RE-PROVEN on the shipping build (before each leg flips on)

Docs and this merge cannot settle these — they are verification duties of the implementation
waves, per the house capability-gate posture:

- **R-1 — plugin tool legs vs #65842** (OPEN upstream): registered plugin tools reportedly
  absent from model catalogs since 2.3.2 (desktop + headless) while passive hooks keep
  working — **contradicted by this run's own working `pipeline_claim` on 2.3.2 today**.
  Re-prove every `card-runner` tool leg (`tools.*` via Code Mode) on the exact shipping
  build. (R2 §4.3/OQ-R2-5)
- **R-2 — multi-instance fan-out vs #56290** (OPEN): `setup()` runs once PER loaded
  location/client connection in one long-lived process; every instance's `ctx.event.subscribe`
  receives every event ⇒ N× side effects; desktop/long-lived hosts observed 6–15 setups
  (#65834). Verify the fan-out factor on the deploy host; every event-driven leg needs
  consume-once claims (globalThis map within a process + durable claim across processes)
  and `location` filtering. (R2 §4.1; RV §1.15)
- **R-3 — Code-Mode call identity vs #65742/#64324**: since **2.3.1** each nested call inside
  a Code-Mode program gets its OWN call id in tool hooks (was the outer `execute` id). Every
  dedup/claim key that rides tool-call ids must tolerate BOTH shapes; re-key the claim-time
  card-details leg on (sessionID, tool, nested-call-id) — today's degraded "no block on the
  claim answer" is consistent with id-shape breakage. (R2 §3, §4.4)
- **R-4 — deploy-runtime version drift**: `terraform.tfvars` still pins
  `opencode_version=2.0.22` / `openchamber_version=2.1.0` while the host runs
  **2.3.2 / 2.8.0** (owner bumped the Coder template out-of-band). EVERY leg above was
  proven on 2.3.2; re-prove on whatever the deploy actually runs after each template move. (R3 "Verify live" 4)
- **R-5 — `session.idle`/`session.status` with a viewer attached**: they did not fire
  headless; OpenChamber's auto-review consumes them. Attach a viewer and re-capture before
  they may SUPPLEMENT (never replace) `execution.*`. (R3 "Verify live" 1)
- **R-6 — active-map process inventory on the deploy host**: enumerate how many opencode
  processes share `opencode.db` and which answers the reconciler's calls; the active map is
  authoritative only for its own process. (R3 "Verify live" 2; R4 §1.7 two-port probe)
- **R-7 — `/api/event` drop rate under the reconciler's own load** before making events
  load-bearing (volatile-by-contract; #61658 precedent: misses are silent). (R3 "Verify live" 3)
- **R-8 — Form/goal surface on the deploy build**: `form.metadata.kind==="question"` and
  `q0,q1,…` keys on a REAL agent question; `ctx.session.form.{list,get,reply,cancel}`
  presence (landed via PR #59655 — capability-gate); `goal.status` transitions if P5
  enables goal mode. (R3 "Verify live" 5)
- **R-9 — `ctx.storage` scope probe** (two projects, one server): settles D26
  "+project-id" vs "fleet-wide" (X14). Decides nothing load-bearing IF §2's filesystem rule
  is followed, but settle it before any same-process nicety uses storage. (R2 OQ-R2-4)
- **R-10 — plugin `console.*`/stderr visibility** in `opencode.log` (`role=server`) on the
  host serving live board runs — settle before relying on degrade-line sighting (the
  board-context lesson: the stderr line was never sightable, forensics had to substitute). (R2 §4.7/OQ-1)
- **R-11 — bare-`tsc` dependency claim** (only if O1 adopts the gate): the
  fails-without-`@types/node` inference was reasoned, not executed — run the 10-second
  probe before freezing chunk Commands. (R1 Reliability)
- **R-12 — the owner live-fire queue (O6)** is the WeKan/Forgejo half of this list: those
  cells are tag-pinned/inferred, not pod-probed — they retire when O6 runs. (R4 §1.8; R5 F5.1)

## Adjacent (recorded, not core)

- Server-side session-list filters make the gate script's hand-rolled tree walk redundant
  for new code (R4 §8) — a `card-runner` liveness leg should use them.
- `pipeline-push-pr` SKILL.md is stale relative to the repo's remotes — fold the doc fix
  into whatever chunk touches the PR leg (R5 Adjacent).
- The dev coder template hard-codes `FORGEJO_HOST=git.scifi.farm`; any future `FORGEJO_*`
  trio must be parameterised per cluster (R5 Adjacent).
- 2.4.x future doors to watch after a host upgrade: `ctx.experimental.automation`
  (first-class scheduling) and `session.hook("experimental.idle")` (hook-shaped idle). (R2 Adjacent)
- After startup, plugin-supplied tool catalogs may be partial (async plugin loading, 2.4.0);
  long-lived clients refresh on `*.updated` events — relevant to wake timing only. (R2 Adjacent)

---

RESULT
status: DONE
chunk: research-merge
files_changed: [.agents/plans/2026/2026-11-cf-140-feat-agent-card-reconcile/RESEARCH.md]
commands_run: [read STATE.json => pass, read DECISIONS.md => pass, read REVIEW-existing-plugins.md => pass, read RESEARCH-r1-typescript-skills.md => pass, read RESEARCH-r2-opencode-plugin-skills.md => pass, read RESEARCH-r3-session-awareness.md => pass, read RESEARCH-r4-card-change-detection.md (full, incl. 619-620) => pass, read RESEARCH-r5-forgejo-linkage.md (full) => pass, write RESEARCH.md (merge pass — no new research, no sibling touched) => pass]
deviations: none — pure merge pass per the launch brief; the five sibling files, STATE.json, DECISIONS.md, FRICTION.md and all EXPLORE-*/REVIEW-* files are byte-untouched; no new web research performed
friction: R4's file needed a second read for its tail (harness truncation at 618 lines — the full 620-line RESULT block was already noted complete in STATE.json); STATE.json classifies OQ-R5c (labels) as plan while R5's own file classifies it owner — resolved into P8 with the owner-side dependency (label creation is repo-writer-gated) stated inline
open_questions: none new — the owner round is §8 (O1–O6), the plan-decision list is §9 (P1–P10), the shipping-build duties are §10 (R-1–R-12); all carried verbatim from the rounds/review
next_suggested: launch agent-plan with RESEARCH.md + REVIEW-existing-plugins.md as inputs — wave split per P10, B1–B3 as gating acceptance criteria, the §1 detection matrix and §4.1/§4.3 detection+linkage designs as the two design cores, AGENTS.md drift repair in commit 1
