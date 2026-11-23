# EXPLORE (scoped): session/runtime observability + session creation, as used in THIS repo

Scout: `agent-explore` · ticket AD-140 `cf-140-feat-agent-card-reconcile` · 2026-11-23
Worktree HEAD: `2345be369` (clean tree) · live probe host: `coder-9539094a-…-62msf`

Live version probes (read-only, this session, 2026-11-23):
- `opencode --version` → **v2.3.2** · `openchamber --version` → **2.8.0**
- `opencode api get /api/info` → `{"data": {version: "2.3.2", hostname: "coder-…"}}` — envelope `{"data": …}` confirmed live.
- Caveat: repo `charts/coder/coder-templates/kubernetes/terraform.tfvars` still pins `opencode_version = "2.0.22"` / `openchamber_version = "2.1.0"` — stale vs the live host (the owner updated the server-side Coder template variables outside this repo's state, cf. `2026-10-04-dep-update-opencode-openchamber.md` plan). Plugin semantics in this repo are **pinned to v2.1.4** with capability-gated seams for newer builds; some facts were live-verified on v2.3.0/v2.3.2 by the cf-126 run.

---

## 1. The session HTTP API as this repo already exercises it

All traffic goes through the `opencode api` CLI (carries the TUI's server discovery + auth; the gate script explicitly holds no credentials for this reason — `scripts/agent-board-coord-gate.sh` L14-15). Response envelope: **`{"data": …}`** (the gate validates `.data | type == "array"` on the listing, L181/L199; single-record reads are read under the same envelope — `pipeline-kickoff` L36, `boards` L215: "the get returns the record under a `{"data": …}` envelope — unwrap it before reading metadata, because a top-level `.metadata` read silently returns nothing").

| Call (repo form) | Purpose / caller | Shape evidence |
|---|---|---|
| `opencode api get /api/session?limit=N&order=desc[&cursor=…]` | list sessions; pagination via `cursor` (object with `previous`/`next`; gate walks `cursor.next`, L202-208). Live probe: cursor is base64 JSON `{order, anchor:{id,time,direction}}`. | gate L193-194, L202-208 |
| `opencode api get /api/session/<id>` | single record (read-merge-write reads; fuser verification; board-preload-probe `fetch_record`) | kickoff L36; fuser skill L38; probe L183-187 |
| `opencode api get /api/session?search=<slug>` | fuser's fallback lookup when `coord_session` is gone; pick by title **contains** slug + `location.directory` match | fuser skill L38; cf-52 DECISIONS D5 |
| `opencode api get /api/session/<id>/context` | message array (first-prompt injection checks, tool audit); messages: user/system carry top-level `text`; assistant carry `content` parts `{type: "text"|"reasoning"|"tool"}` with tool parts `state: {status, input, …}` (live v2.0.32 surface, copied into fixtures) | probe L177-181, L189-261; question-notify.test.ts header |
| `opencode api patch /api/session/<id> -d '{"metadata": <full merged object>}'` | metadata write — **PATCH replaces `metadata` whole; a partial write deletes the siblings (proven 2026-10-26)** — the read-merge-write rule exists for exactly this | kickoff L36-38; boards L209-217; probe LF4 sentinel proof L365-368, L401-403 |
| `opencode api patch /api/session/<id> -d '{"archived": true}'` | archive a session — "OpenCode's native archive, the very route OpenChamber's own archive sends (live-verified)"; a NEW single-key PATCH after the marker write, never a rewrite of it | boards L236-249 |
| `opencode api post /api/session -d '{"title":…,"location":{"directory":…}}'` | create session (LF4 leg); answer nests id under `data` (`json["data"]["id"]`) | probe L352-359; cf-126 STATE C05 result ("POST /api/session {data:{id}} nesting") |
| `POST /api/session` with `{agent, model, location, metadata}` | **the dispatcher's spawn contract**: "create the coord session with `agent` + `model` + `location` (project root) + `metadata` (the card id, `cardNumber`, the slug, `parent` = the dispatcher's own session id, the provider answer, the variant), and send the first prompt as the card-driven-kickoff launch text" | boards L166 (Dispatcher section) |
| `opencode api post /api/session/<id>/prompt --data '{"text": "…"}'` | post a prompt into an existing session — fuser hand-back, dispatcher proxy-forward (`pipeline-dispatch.md` L31), pipeline-locks `say()` (plugin-side `ctx.session.prompt({…base, sessionID, text, delivery})` — the probe's live envelope carries prompt as an **object** `{text, files, …}`, L2288-2295) | fuser skill L38-39; loop L31; pipeline-locks L2288-2295 |
| `opencode api get /api/info` | server identity; cf-50 probes: v2.0.32 on 127.0.0.1:49374, scheduled sessions appear in the same listing (they do — `metadata.openchamber.kind:"scheduled"`). Live here: v2.3.2. | cf-50 DECISIONS L39 |
| `opencode api get /api/agent/<name>` (with `x-opencode-directory: <repo>` header) | read an agent's rules against the server that owns the repo location; `--standalone` may answer before agents load (empty list) | pipeline-overview L46 |
| `opencode api get "/api/location?location[directory]=<dir>"` then `GET /api/debug/location` | **boot-if-missing + verify** a location before `session_move` (the warm leg); loaded-list check greps `"directory":"<dir>"` | kickoff-warm-location.sh L75-90; kickoff L40 |
| `GET /api/session/active` | **probed and REJECTED**: returned `{"data":{}}` while a coord+review tree was demonstrably mid-flight (bare AND with `x-opencode-directory`) — "unusable as a busy-signal; staleness stays primary" | cf-50 chunks/C01 L73, DECISIONS L17 |

The `opencode` Code-Mode tool namespace (distinct from the `opencode api` shell) is used for `worktree_create` / `worktree_list` / `worktree_remove` / `session_move` / `session_rename` (kickoff L33-34; `session_rename` **returns the caller's own sessionID** — the sanctioned id source for `coord_session`).

### The exact read-merge-write rule (kickoff L35-39, single authority)
1. `opencode api get /api/session/<sessionID>` → **unwrap `{"data": …}`**.
2. Keep **ALL** current metadata (notably `openchamber.kind`).
3. Set the new key (e.g. `metadata.openchamber.work = {state:"open", openedAt:<epoch-ms>, openedBy:"auto"}` — OpenChamber's zod schema: `state open|done`, `openedBy auto|jev|user`, `doneAt` ms on done; never write `suggestDoneAt`/`reviewOffer`, Jev-owned).
4. `opencode api patch … -d '{"metadata": <full merged object>}'` — only the fully merged object may go back.
Idempotent skip when the read already shows `work.state == "open"` (chat runs auto-open; scheduled runs are the real target — OpenChamber **excludes scheduled runs** from auto-open).
Proven hazard: a whole-`metadata` replace loses untouched siblings — LF4's sentinel leg exists to prove the merge live (probe L365-368, L401-403: `openchamber.probeSentinel` must survive the marker write).

Known session-record metadata keys (evidence): `openchamber.kind` (`"scheduled"` — app-owned namespace, run only reads; live-confirmed on 20/200 recent records), `openchamber.work` (170/200 set), `openchamber.*` (app-owned — the run "only reads `openchamber.kind` there", boards L195-196), `pipelineNoop = {at, reason}` (top-level, six reason tokens: `no-cards | no-claimable-cards | gate-skip | gate-live | board-check-unavailable | delegated`), `pipelineDispatcher = true`, `parent` (dispatcher spawn marker), `probeSentinel` (test-only).

---

## 2. What a session record carries + how finished/idle/busy/error are inferable

Live probe 2026-11-23, `GET /api/session?limit=200&order=desc` (opencode v2.3.2):

**Record key union (live):** `agent, cost, id, location, metadata, model, outcome, parentID, projectID, time, title, tokens`

- `id` — `ses_` + base64-ish, e.g. `ses_df66abeffffeeQPISFQ74gBMG8` (probe scripts mint `ses_bpp…` ids for standalone runs).
- `parentID` — native parent link; 179/200 records carry one; top-level sessions lack it (`isTopLevel` = `!info.parentID`, question-notify L142-145).
- `agent` — exact agent id (`agent-explore`, `agent-board-coord`, …) — the gate's filter key.
- `model` — `{id, providerID, variant}`.
- `tokens` — `{input, output, reasoning, cache:{read,write}}`; `cost` — number (e.g. `9.287195606`).
- `time` — **active** record: `{created, updated, busy}` (ms); **terminal** record adds `idle` and `viewed` (live sample: `{created, updated, busy, idle, viewed}`).
- `outcome` — the terminal-state field; live distribution over the 200 most recent: `None` ×18, `succeeded` ×172, `failed` ×7, `interrupted` ×3. The 18 `None` rows' `time.updated` ages: 0, 0, 1, 1, 14, 123, 126, 127, 127, 128, 141, 143, 144, 144, 144, 829, 2716, 2719 minutes — so `outcome == None` is NOT by itself an "active" signal (two rows are >13h/45h old without a terminal outcome); freshness of `time.updated` (± the child tree, below) is the primary liveness signal the repo already relies on.
- `archived` — absent on all 200 recent records (the archive PATCH route is live-verified separately, boards L239-240); expect it to appear only when set.
- `projectID`, `location.directory` — scoping (fuser matches on `location.directory`).

**Inference available locally today:**
- *busy* ≈ `time.busy` fresh (7/200 within 15 min) or `time.updated` fresh (8/200).
- *finished* = `outcome` terminal (`succeeded`/`failed`/`interrupted`) — but no "objective met" semantics exist in the record; the repo infers completion from the **events** below plus metadata markers (`pipelineNoop`), never from a single field.
- *error* = `outcome: "failed"` or the `session.execution.failed` event (carries `error: {type, message}`; `crashExcerpt` reads `message` then `type`, question-notify L238-241).
- There is **no status field** (no `busy`/`idle`/`pending` enum on the record beyond the timestamps), and `/api/session/active` is proven unusable (cf-50 C01).

### OpenCode events + hooks this repo's plugins actually handle
Events (via `ctx.event.subscribe({signal})`, whole stream, no `types` filter — the option needs `@opencode/plugin` ≥ 2.2.0 and would silently drop everything on 2.1.4; filtering is in-handler):

| Event name | Handler | Grounding |
|---|---|---|
| `session.execution.succeeded` | question-notify finished push (top-level only, no-work-marker suppression); pipeline-locks: clear `executing` (bookkeeping only — "turn end is not iteration end") | qn L105, L263-310; pl L212, L1390-1399 |
| `session.execution.failed` | question-notify crash push (never suppressed by the marker); pipeline-locks: root failure → `state:"failed"` lock mark (or release when `releaseOnFailure`) | qn L106, L293-304; pl L213, L1399-1408 |
| `session.execution.interrupted` | pipeline-locks terminal set (same failure path) | pl L213 |
| `session.execution.started` | pipeline-locks: add to `executing` + force beat | pl L211, L1380-1388 |
| `session.created` / `session.updated` | pipeline-locks: child mapping (child `parentID` under a claimed root → `sessToRoot` + durable `child/<id>` row + force beat) and dispatcher tracking (agent == `agent-board-dispatch` AND `metadata.pipelineDispatcher === true`). **`session.updated` never fires on v2.1.4 (D31)** — the leg stays armed, degrading to hourly-tick self-heal; cf-126 FRICTION: live v2.3.0 records carry flat top-level `agent`/`metadata` — the dual-read tracking leg handles it (delivery on the running build was a verify duty) | pl L208-210, L1344-1378; cf-126 FRICTION L15 |
| `session.compaction.failed` | pipeline-locks **record only** (audit row `ev:"compaction_failed"` + logNote; no push, no dedupe, no filter — D32). Live v2.3.2 envelope proven by cf-126 C05 probe: **flat under `data`: `{sessionID, reason, error:{type,message}}`, NO agent field** (induced reason `compaction.unavailable`; the wedge-class reason not reproduced live) | pl L1410-1445; cf-126 C05 result + STATE L230 |
| `permission.asked` | question-notify: arms a per-request-id 15 s pending timer (only publishes when ruleset effect resolves `ask`, once per request id); pending-only — arrival pushes nothing | qn L67-79, L316-391 |
| `permission.replied` | question-notify: cancels the pending timer for that request id (any reply value) | qn L108, L328-337 |
| `session.idle`, `session.error`, `session.status`, `message.updated`, `permission.updated`, any `question.*` | **NOT handled anywhere** — `session.idle`/`session.error` "stay ignored on purpose" (legacy, qn L38); the v2.1.4 probe found `session.updated\|idle\|status` **never emitted** (cf-76 C01, [CF76-1]); no `question.*` event exists — "the question path rides the tool hook" (board-tick-cleanup RESEARCH L559) | — |

Hooks:
| Hook | Handler | Grounding |
|---|---|---|
| `ctx.tool.hook("execute.before")` | question-notify: the **question tool lifecycle** — fires when the agent's `question` tool starts executing; event carries `{tool, sessionID, agent, messageID, id, input}` (verified against @opencode/plugin 2.1.2 types, qn L30-33); filter: `tool === "question"` → agent starts with `agent-` → cooldown → claim on tool-call id (`event.id ?? event.messageID`) → immediate HA push (excerpt from `input.questions[0].question` or `.header`) | qn L567-583, L393-433 |
| `ctx.tool.hook("execute.before" / "execute.after")` | pipeline-locks: activity beats + strict lock-lost guard (a `before` throw blocks the tool call; "execute.after never fires for before-blocked calls" — C01 fact 2) | pl L2653-2674 |
| `ctx.session.hook("compaction")` | pipeline-locks: ONE process-wide compaction hook — re-writes the summary draft as a compact pointer (full form for the 7 coord/dispatch agent names, generic for everything else) and puts a keyed note via `ctx.session.instructions.entry.put({sessionID, key, value})` — **capability-gated: absent on pinned v2.1.4, live-fired on v2.3.0** (event carries `{sessionID, agent, system[], messages, model, tools, options}`; the adapter pushes the draft back as one mutable text part); dispose on unload | pl L2676-2700, L1491-1515, L2525-2543 |
| `ctx.session.hook("prompt")` | board-context: injects the Board context block into the first prompt (agent-gated); replies via `ctx.session.prompt` | board-context L789 |
| `ctx.session.prompt(…)` | the plugin-side prompt-post seam (pipeline-locks `say()`; dispatcher wake `sessionPrompt`) — degrades to a log line when absent | pl L2518-2524 |
| `ctx.session.get({sessionID})` / `ctx.session.context({sessionID})` | record read / message list (question-notify `getSession`/`getMessages`; board-context `getAgent`) | qn L596-597; bc L784 |
| `ctx.session.update` | **proven-but-unwired**: "the v2.1.4 plugin context carries `ctx.session.update`, a typed session write whose input accepts `metadata` and `archived` in one call, so a plugin may write and archive session records from inside the server process" (boards L258-267, the honest-limit note — the engine-side marker is a shippable, DECISIONS-ruled future addition) | boards L258-267 |
| `ctx.storage` (kv, plugin-id-scoped, shared across worktree locations), `ctx.mcp.transform` (URL discovery), `ctx.tool.transform` (tool registration), `ctx.command.transform` (command registration), `ctx.session.instructions.entry` | pipeline-locks / question-notify / board-context infrastructure | pl L2429-2473; qn L443-488 |

**What a reconciler needs but does NOT have today (event-side):** no `question.*` events; no `message.updated` handling; `session.idle`/`status` never emitted (v2.1.4); `session.updated` delivery unverified on the running build (degrades to tick self-heal); `GET /api/session/active` proven empty; no record field for "busy" beyond timestamps. These are the items the upstream research round must settle (see §8).

---

## 3. How a QUESTION is observable from outside the session

Lifecycle (all in-repo):
1. **Raise:** the agent calls the built-in `question` tool; input shape `{questions: [{question, header, …}]}` (question-notify `firstQuestion` reads `input.questions[0].question ?? .header`, L393-400).
2. **Observe (the only in-repo observation point):** the `execute.before` tool hook fires at tool start (qn L567-583). The plugin reads `event.tool`, `event.sessionID`, `event.agent` (with a `ctx.session.get` fallback), `event.id`/`event.messageID` (claim key) and `event.input`. It pushes **immediately** — there is no 15 s pending for questions; the 15 s pending constant (`PENDING_NOTIFY_MS = 15_000`, deliberately decoupled from the 15 s burst `COOLDOWN_MS`) exists **only for `permission.asked`** (qn L92-97).
3. **Answer:** no `question.replied`/`question.answered` event exists in the repo (grep: zero); the only question-adjacent event names that appear anywhere are the *absence* facts (board-tick-cleanup RESEARCH L559: "No `question.asked` event exists — the question path rides the tool hook").
4. **Is a pending question recorded on the session/message as data?** **Not proven in-repo.** Indirect evidence: the context endpoint returns tool parts with `state: {status, input, …}` (board-preload-probe `ctx_tool_audit` reads `part.state.status`, L218-231; fixtures show `status:"completed"`). A pending `question` tool call would presumably surface as such a part with its `input` — but the **pending status vocabulary, whether/when an answer mutates the part, and any per-question timestamp are not established anywhere in this repo** (no fixture, no probe, no test pins it). This is the load-bearing unknown for the 15-minute unanswered-question rule.
5. Per-message/per-question **timestamps**: the session record's `time.{created,updated,busy[,idle,viewed]` exist and are live-verified; message-level timestamps are NOT evidenced (context fixtures carry ids and content only). A 15-minute rule can be built on `time.updated` freshness (the gate's proven pattern) but the precise "question asked at T" stamp needs an upstream answer.

Global plugin config: `~/.config/opencode/opencode.json` (machine-global, not version-controlled) carries **no plugin entries at all** (probed 2026-11-23). All plugins are project-local under `.opencode/plugin/` (discovered by directory scan — pipeline-locks header: "plugin discovery loads every module under .opencode/plugin/"). The project config `.opencode/opencode.jsonc` carries `"plugins": ["-local.question-notify"]` — the `-` prefix **removes** a discovered plugin by declared id: **question-notify is owner-disabled 2026-11-21** (the file stays on disk; the config entry alone is the toggle). `board-context`, `pipeline-locks`, `aislop-gate` load by discovery.

`.openchamber/project.json` (tracked): `magicPrompts."session.summary.instructions"` — the non-destructive "Do NOT compact or mutate session history" summary instruction, with the compaction-pointer law appended ("When this request carries hook-injected compaction instructions, follow them as the law… The non-destruction rule above always stands."). Whole-replacement resolution by key presence: an incomplete override voids that clause (tests/openchamber-project/). This bears on the reconciler's compaction-driven relaunch: the keyed note from the pipeline-locks hook lands here.

---

## 4. Subagent / child-session status: addressing and relaunch

- **Native addressing:** every session has its own `id`; the **`parentID`** field links child → parent (live: 179/200 recent records carry it). The gate's liveness rule uses it: a coord counts as live when its own `time.updated` **or any child's** (`parentID == coord.id`) is fresh (gate L217-241 — "the child rule closes the coordinator's silence while blocked in a subagent launch", D2).
- **Custom marker:** the dispatcher sets **`metadata.parent`** = its own session id in the spawned coord's metadata (boards L166 spawn contract; live: 15/200 recent records carry `metadata.parent`). Distinct from the native `parentID` — both coexist.
- **Subagent status inside a session:** the `subagent` tool's error report (e.g. `<subagent state="error">` carrying a compaction-failure shape) is the in-band signal the launcher reads (boards Context-handoff L276); pipeline-locks child mapping (from `session.created` with `parentID`, durable `child/<id>` rows, restart-resume scan) maps each child session to its root for lock beats (pl L1344-1378, L2628-2651).
- **Relaunching out-of-context children (today's doctrine):**
  - **Wedge detector:** the pipeline-locks `session.compaction.failed` listener — record-only (audit row + logNote); "the record is the whole in-repo signal".
  - **Subagent relaunch-FRESH doctrine (boards L276):** a child whose `<subagent state="error">` report carries the compaction-failure shape (or whose RESULT reports context exhaustion) is **relaunched FRESH with the full launch brief** — chunk file + read order + skills — "never a follow-up: a follow-up re-triggers the same failing compaction". Upstream failure classes: #56784 (wedge: doomed summary retried forever), #57187 (dead-end at the context limit), #59110 (reasoning budget eats the summary). "The relaunch decision is the coord's — the listener detects and records, it never decides."
  - **The compaction hook (cf-126 C03, D8/D9, Ruling OQ3 — repo-wide, one process-wide hook):** summary re-written as a compact pointer (agent selects variant, never gates); keyed note at the next step via `ctx.session.instructions.entry.put` (capability-gated per §2). The coord protocol (boards L273): make plan-folder state current, **spawn the successor through the session-creation rows** (same agent + model, this run's location, metadata carrying card/slug/parent), send the `/pipeline-resume`-style bootstrap, then `pipeline_release(outcome:"handoff")` and close. The dispatcher's fresh start: spawn a FRESH dispatcher carrying the running facts, then end (boards L277).
  - Fresh-start bootstrap convention (this session's own summary pointer): "re-read the ticket folder in the pipeline read order, load the MUST-load skills, act on the brief" — files are the bus.

---

## 5. Scheduled tasks / loops: how `.agents/loops/*.md` actually runs

- **Two loop files** in `.agents/loops/`: `pipeline-worker.md` (agent `agent-board-coord`, model `gpu-ai/qwen3.8-flash-next-radiance`, cron `0 * * * *`, enabled: true in the file) and `pipeline-dispatch.md` (agent `agent-board-dispatch`, model `gpu-ai/qwen3.8-flash-next-strata-q4`, cron `0 * * * *`, enabled: true in the file). Frontmatter: `{name, schedule (cron string), enabled, model, agent}`; **body = the task prompt** (the whole loop text; the plugin's `TICK_PROMPT` constant is the body minus the comment, D30 parity-pinned).
- **OpenChamber sync (live-probed 2026-11-23):** loop files sync **per project** into `~/.config/openchamber/projects/path_<base64(absolute project path)>.json` (e.g. `path_L2hvbWUvY29kZXIvU3BlbmNlcnNMYWI.json` = `/home/coder/SpencersLab` — the MAIN checkout; this worktree has no project file of its own). The synced task shape:
  ```json
  { "id": "loop:project:<name>", "name", "enabled",
    "schedule": { "kind": "cron", "cron": "0 * * * *", "timezone": "UTC" },
    "execution": { "prompt": "<the ENTIRE loop file text>", "providerID": "gpu-ai", "modelID": "qwen3.8-flash-next-strata-q4", "agent": "agent-board-dispatch" },
    "state": { "createdAt", "updatedAt", "lastStatus" },
    "loopFile": "/home/coder/SpencersLab/.agents/loops/pipeline-dispatch.md" }
  ```
  plus top-level `loopApprovals`: map of loop-file **absolute path → sha256** (SpencersLab currently pins `pipeline-worker-local.md` — stale, that file no longer exists — and `pipeline-worker.md`).
- **Approval law (loop-file comment, verbatim):** "Body edits rotate this task's approved loopApprovals fingerprint; a fingerprint-mismatched task sits `loopApproval:"outdated"` with `enabled` forced false until the owner re-approves it. Scheduler decisions stay human-owned."
- **Live state (probed today):** all four SpencersLab tasks are `enabled: false` — `Check cluster statuses` (weekly, agent `plan`), `Hourly Pipeline call` (daily 16:05 America/Denver, agent `agent-board-coord-local`, prompt "Please take the next card and start processing it." — runs NO gate), `pipeline-worker`, `pipeline-dispatch`. So the scheduler is currently off owner-side; a new `agent-card-reconcile` loop lands in the same shape and is owner-toggled.
- **Session-on-schedule vs spawn-from-plugin:** the scheduler **creates the session before prompting it** (the gate's grace-window design, D3: "a coord session created inside this window IS this run"); scheduled sessions carry `metadata.openchamber.kind = "scheduled"` (live-confirmed, 20/200 recent records; board-tick-cleanup C02: "the kind discriminator rides OpenChamber scheduled launches"). Plugin-side creation is the `POST /api/session` shape in §1 (LF4: `{title, location:{directory}}` → `data.id`; dispatcher contract: `+ agent, model, metadata`). `POST /api/session/<id>/prompt` then starts the turn.
- Model routing for loops: the frontmatter `model` line is an owner-ruled literal (moves only by fresh owner ruling — the loop comments pin this for both files).

---

## 6. `scripts/agent-board-coord-gate.sh` — today's only session-awareness mechanism

- **Verdicts (machine-readable first stdout line; exit codes):** `GATE: RUN <basis>` → exit 0 (no live coord; proceed to card pickup; board operand never evaluated — short-circuit); `GATE: LIVE <id> (<age>s) <title>` → exit 2 (a live coord was found; the agent MUST run the BOARD CHECK before anything else); `GATE: SKIP <reason>` → exit 1 (session detection **failed; fail-closed** — the run must not start).
- **Liveness rule (D2/D9):** a coord session (agent **exactly** one of `agent-board-coord`, `agent-board-coord-local`, `agent-board-coord-pr`, `agent-board-dispatch` — explicit enumeration, never prefix matching) minus `--self`, minus anything created within `--grace` (default 5 min — the scheduler creates the session before prompting), is live when the **newest `time.updated` across its tree** (its own OR any child session's, matched by `parentID`) is within `--threshold` (default **15 minutes**). A missing/zero `time` reads as maximally old. `--threshold 0` is the forced-through escape (human-rerun path).
- **Listing mechanics:** paginated `opencode api get /api/session?limit=500&order=desc[&cursor=…]`, envelope-validated (`.data | type == "array"`), page cap 40, CLI timeout 20 s; any miss (dependency, CLI, malformed, exhausted pages, bad fixture) → `GATE: SKIP <sanitized-reason>` — "detection can never 'rescue' itself into a start". No directory/project scoping (D11: interactive + worktree launches must count; cross-repo serialization is the deliberate single-writer posture, OQ-A3).
- **Board operand:** deliberately NOT in the script (a bash script cannot hold an MCP session) — the agent's own read-only `dev-boards` turn on a LIVE verdict (D16).
- **Why the pivot must supersede it:** it answers only "is another board-coord session working right now?" from `time.updated` staleness — it has no notion of finished-with-objective-met, unanswered questions, card changes, or child topology beyond the tree-age rule. The reconciler inherits its proven primitives (the listing walk, the envelope contract, the fail-closed posture, the tree-age rule) while replacing its single question with the reconcile decision.

---

## 7. Capability → exists today (evidence) → gap

| Reconciler capability | Exists in-repo today (path/evidence) | Gap |
|---|---|---|
| List all sessions + record fields (agent, model, time, tokens, cost, outcome, parentID, location, metadata) | `opencode api get /api/session` listing walk (gate L190-211); live record shape probed §2 | None — live on v2.3.2 |
| Read one session record under the `{"data":…}` envelope | gate L196-201; kickoff L36; fuser L38; probe `fetch_record` | None |
| Read a session's messages (tool parts incl. `state.status`) | `GET /api/session/<id>/context` (probe L177-181; fixtures from live v2.0.32) | Pending-`question` part shape + status vocabulary unproven → **Needs research** |
| Mark sessions (metadata) without clobbering siblings | read-merge-write rule (kickoff L36; boards L209-217); `ctx.session.update` proven present but unwired (boards L258-267) | None for agent-side; plugin-side is a shippable addition (DECISIONS-ruled) |
| Archive sessions | `PATCH {"archived": true}` live-verified route (boards L236-249); `ctx.session.update` also accepts `archived` | None |
| Create a session (agent+model+location+metadata) | LF4 `POST /api/session` (probe L352-359); dispatcher spawn contract (boards L166) | None — the `model` field on POST is the cf-126-probe learning (`/model {model:{id}}`), documented in that run's probe artifact, not re-verified here |
| Post a prompt into a session | `POST /api/session/<id>/prompt` (fuser L38; loop L31; plugin `ctx.session.prompt`, pl L2288-2295) | None |
| Detect "run finished" | `session.execution.succeeded` event (qn L105; pl L212); `outcome` terminal field on the record (live §2) | No "objective met" semantics in the record — the reconcile must combine finished + card state itself |
| Detect "busy / idle" | `time.busy`/`time.updated` freshness (live §2); gate tree-age rule (gate L217-241); `/api/session/active` **proven unusable** (cf-50 C01 L73) | No status enum on the record; no `session.idle`/`status` events emitted (v2.1.4 probe; [CF76-1]) → **Needs research** (does v2.3.2 emit them? is there a reliable busy flag?) |
| Detect "error" | `session.execution.failed` event with `error{type,message}` (qn L106, L238-241); `outcome:"failed"` live | None |
| See when a question is raised | `execute.before` hook on the `question` tool (qn L567-583; event `{tool, sessionID, agent, messageID, id, input}` verified on 2.1.2 types) | **No `question.*` event exists**; no record field for a pending question proven → **Needs research** (is a pending question persisted on the session/message, with what timestamp? is there an answer event/state change?) |
| Measure "question unanswered > 15 min" | 15 s pending mechanism exists ONLY for `permission.asked`/`permission.replied` (qn L92-97, L316-391); `time.updated` freshness is the proven 15-min-scale clock (gate) | No per-question ask-timestamp evidenced anywhere in-repo → **Needs research** (tool-part timestamp? message timestamp? event?) |
| See a pending permission approval | `permission.asked` (durable, once per request id) + `permission.replied` cancel (qn L67-79) | None — fully proven on v2.1.4 |
| Track parent/child sessions | native `parentID` (live §2; gate child rule); `metadata.parent` dispatcher marker (boards L166; live §2); pipeline-locks child mapping + durable restart-resume (pl L1344-1378, L2628-2651) | None |
| Relaunch an out-of-context child | relaunch-FRESH doctrine (boards L276); compaction hook + keyed note (pl L2676-2700, L1491-1515); successor spawn via the creation rows (boards L273) | None for the doctrine; the reconciler would formalize the "never a follow-up" rule |
| Detect a failed compaction | `session.compaction.failed` listener, record-only, live envelope proven on v2.3.2 (pl L1410-1445; cf-126 C05) | None |
| Scheduled tick driving the reconciler | `.agents/loops/*.md` → OpenChamber `scheduledTasks` sync (per-project, `loopFile` + `loopApprovals` sha256; task shape §5; live: all tasks currently `enabled:false`, owner-owned toggle) | A new `agent-card-reconcile` loop file follows the exact same shape; owner enables it. Note: `loopApprovals` currently pins a **stale** `pipeline-worker-local.md` path |
| Know which launches are scheduled | `metadata.openchamber.kind == "scheduled"` (live §2; question-notify suppression conjunction L154-161) | None |
| Suppress alerts on no-op ends | `pipelineNoop` marker (six reason tokens, boards L191-234) + reader conjunction (qn L154-161) — **note: question-notify is owner-disabled 2026-11-21** (`.opencode/opencode.jsonc` `plugins: ["-local.question-notify"]`) | If the reconciler must push "question unanswered" alerts, the phone channel is currently off owner-side; a new push path is a fresh decision |
| Board decision context (card changes since last reconcile) | out of this scout's scope — sibling territory (`dev-boards` MCP: `get_card_details`, `preload_board`, list/label/checklist reads per boards skill) | n/a here |

---

## 8. Items that MUST be settled by upstream research (do not guess)

1. **Pending-question persistence:** when an agent's `question` tool call is awaiting the user, is it recorded as data on the session or the message (tool part with a pending `state.status` vocabulary? a per-question timestamp? a per-message `time` field?) and what changes when the user answers (event? part mutation? a `question.replied`-class event in v2.3.2?) — this decides the 15-minute rule's clock. In-repo: no `question.*` event exists and no pending-question fixture/probe is pinned.
2. **Busy/idle on the running build (v2.3.2):** the repo's emission facts are v2.1.4-pinned (`session.updated|idle|status` never emitted; `session.idle`/`session.error` ignored on purpose). Whether v2.3.2 emits `session.idle`/`session.status` or exposes a reliable busy flag (beyond `time.busy`/`time.updated` freshness, beyond the proven-empty `/api/session/active`) is unverified here.
3. **POST /api/session with `model`:** the cf-126 probe recorded `/model {model:{id}}` learnings in a probe artifact that no longer exists on this host (`/tmp/opencode/cf126-probe/` absent); re-prove the exact create-with-model request shape (top-level `model` object vs nested) before the reconciler mints sessions.
4. **`session.updated` delivery on the running build** — cf-126 left it as a verify-on-running-build duty; the dispatcher-tracking leg degrades to hourly-tick self-heal meanwhile.
5. **`archived` field visibility:** absent on all 200 most-recent live records — confirm whether it appears as `false` or is omitted, so the reconciler's "archive this session" bookkeeping can read it back.

---

## 9. Other grounded facts worth carrying into the plan

- **Two OpenCode servers share one `opencode.db`** in this deployment (question-notify fan-out debug, 2026-11-07): each location plugin loads once per active checkout per server; every instance subscribes to the whole public event stream; `ctx.storage`'s kv namespace is keyed by plugin id alone (visible fleet-wide) — a new `card-runner` plugin must assume the same multi-instance fan-out and use consume-once claims (qn L53-66 precedent) for any event-driven dedup.
- **Plugin loading:** every `.ts` under `.opencode/plugin/` is loaded as a plugin entry (tests must live outside `.opencode/` for this reason); a plugin that throws in `setup` wedges an ephemeral location load (D31) — the whole setup body sits in try/catch, degrade-never-throw is the house style.
- **Code Mode transport:** on the pinned v2.1.4, plugin tools (e.g. `pipeline_*`) are reachable ONLY through Code Mode `execute` calls, never as native provider tools (D29, live-restamped 2026-10-29).
- **Lock/wake machinery:** `pipeline-locks` release wakes the tracked dispatcher via `ctx.session.prompt` ("a lock set was released… check for the next pickable card") — the reconciler's "start the next available task" is a generalization of this existing wake (pl L858-878), with the hourly tick as the self-heal fallback.
- **OpenChamber run-state file** `~/.config/openchamber/run/openchamber-3000.json` holds loopback bind only (cf-50 D19 probe) — no public URL; the browser-facing origin is Coder-rendered (`$VSCODE_PROXY_URI` → the `Session origin:` command block, verbatim copy rule).
- **`opencode run --standalone`** (worktree-rooted private instance, explicit `--session <id> --agent <name>`) and **`opencode run --session <id>`** (continue a pre-created background-service session) are the two CLI launch shapes the probe script uses (probe L147-175) — relevant if the reconciler ever needs to verify a spawn from outside the plugin process.
