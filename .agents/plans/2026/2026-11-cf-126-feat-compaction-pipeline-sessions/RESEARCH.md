# RESEARCH.md — cf-126 (card #126, Compaction and Pipeline Sessions)

Pre Research round, 2026-11-17. Scope: capability research for the board-pipeline
session-model restructure, grounded in OpenCode v2 (docs at
https://opencode.ai/docs/, version of record; OpenAPI spec fetched
https://opencode.ai/docs/openapi.json 2026-11-17; source
github.com/anomalyco/opencode @ `d327a9662` (2026-11-16, dev) + upstream issues).
Repo grounds: see EXPLORE.md; this file adds the capability answers.

## TL;DR

- **Session creation + handoff: fully supported.** `POST /api/session` (body:
  `id, parentID, title, agent, model, location, metadata, permissions`) +
  `POST /api/session/{id}/prompt` (first message; `skills`/`agents` attachments
  allowed); plugin `ctx.session.create/prompt/switchAgent/switchModel/command`
  is the same surface in-process (the in-repo `/pipeline-tick` precedent is a
  strict subset). OpenChamber loop tasks are cron-spawned sessions (frontmatter
  model/agent + body prompt), so the "shared session" is a loop task and
  per-card coord sessions are created through the API or a plugin.
- **Compaction: the event is observable and interceptable by plugin, not by
  agent instructions.** Auto (buffer % of window) / manual / overflow-recovery
  triggers; `ctx.session.hook("compaction")` can inject instructions into the
  summary request or replace the summary entirely (`event.result` skips the
  model call). There is NO custom-summary-prompt config knob and NO step-count
  window knob — "last ~15 steps" is a convention (`keep.tokens` is the only
  supported tail-size knob, default 15k tokens).
- **Subagent context exhaustion = a documented failure class**, not one shape:
  `session.step.failed`/`execution.failed` with
  `{"type":"compaction.failed","message":"Compaction summary reached the output
  token limit"}` (plus a `session.compaction.failed` event), and the session
  dead-ends (upstream #57187) or wedges (upstream #56784). The parent is
  signaled by a synthetic `<subagent state="error">` inbox message; follow-up by
  sessionID is supported, but for a compaction-dead session the design answer is
  relaunch-fresh with context files.
- **Doctrine (D54(4))**: 27b-radiance is written as NEVER a default route until
  "measurement ON THIS BOX"; per the 2026-11-17 owner ruling the receipt is the
  runbook 8-session gate (8 concurrent sessions at 262144 depth via the peer
  hop, PASS = 8 admitted without refusal-class errors + the read-only receipt
  list). The exact-name lists (gate L227, board-context L117-121) are
  hand-maintained triples — a new shared-session agent name must be appended to
  both to stay inside the hourly gate and the board-context prefetch.

## 1. Session creation + handoff

### 1.1 HTTP API (opencode api / openapi.json)

`POST /api/session` **exists** (operationId `session.create`, "Create a session
at the requested location. A parentID creates a linked child session at its
parent's location."). Request body (required=true, all fields optional):

| field | type | meaning |
|---|---|---|
| `id` | Session.ID \| null | client-chosen session id |
| `parentID` | Session.ID \| null | "Set parentID to create a subagent session at the parent's location; set agent to choose its agent (otherwise it uses the default) and start it with session.prompt. After each completed round, the child sends a `<subagent>` report to the parent's inbox and wakes the parent unless it has a staged revert." |
| `title` | string \| null | session title |
| `agent` | Agent.ID \| null | **target a specific agent at creation** |
| `model` | Model.Ref \| null | `{id, providerID, variant?}` — **target a specific model at creation** |
| `location` | Location.PublicRef \| null | `{directory}` — **set the session's working directory (worktree) at creation** |
| `metadata` | object \| null | free-form session metadata (Session.Metadata = bare object) |
| `permissions` | Permission.Ruleset \| null | `[{action, resource, effect}]` — session-scoped rules at creation |

Response `data` = Session.Info, which carries `id, parentID, fork, projectID,
agent, model, cost, tokens, outcome (succeeded|failed|interrupted), time, title,
subpath, metadata, permissions, revert, location`.
Source: openapi.json (fetched 2026-11-17), `paths."/api/session".post` and
`components.schemas["Session.Info"]`.

**The first message is NOT in the create body.** It is a second call:
`POST /api/session/{sessionID}/prompt` — body
`{id?, text (required), files?, agents? (Prompt.AgentAttachment), skills?
(PromptInput.SkillAttachment = {id: Skill.ID, mention?}), metadata?, delivery?
("steer"|"queue"), resume?}`. So: create (agent+model+location+metadata) →
prompt (text + optional skill pre-attachment) is the sanctioned two-call
handoff. Also supported on the new session: `POST .../command` (run a command,
e.g. a /pipeline-resume-style bootstrap, body `{name, text, files?, agents?,
skills?, delivery?}`), `POST .../synthetic` (synthetic message, `resume?`),
`POST .../agent` / `.../model` (switch agent/model after the fact), `PATCH
/api/session/{id}` (title/metadata/permissions/archived), `POST .../fork`
(body `{before: messageID}`; boundary schema `{type:"before"|"through",
messageID}`), `GET .../context` ("Retrieve the active context messages for a
session (all messages after the last compaction)").

`@opencode/client` (TS, generated from the same contract) exposes
`client.session.create({location: {directory}})` + `client.session.prompt`
(https://opencode.ai/docs/build/client/); `@opencode/sdk` embeds the server
in-process with the same `sessions.create/prompt` shape
(https://opencode.ai/docs/build/sdk/). `Service.ensure()`/`Service.headers()`
resolve the local background service for a Node process. The `opencode api
post <path> --data` CLI is the shell-side equivalent (opencode skill API
section) — the coord agents' existing `opencode api get/patch /api/session*`
shell rows (EXPLORE.md §4, L64-69) would need `post /api/session` +
`post /api/session/*` rows to gain this surface agent-side.

### 1.2 Plugin context (ctx.session)

The plugin context "is essentially an OpenCode server client"
(https://opencode.ai/docs/build/plugins/server/). `SessionContext` (verbatim
reference block) provides: `create(input?)`, `get`, `remove`, `context`
(messages after last compaction), `instructions.entry.{list,put,remove}` (keyed
instruction entries rendered as `<context key=…>` blocks, "updates or removals
are announced at the next step boundary without queuing a message turn"),
`switchAgent`, `switchModel`, `update` (title/metadata/permissions/archived),
`move`, `prompt`, `generate`, `command`, `compact` ("returns the admitted inbox
item, not a completed summary; compaction runs at the next step boundary by
default"), `synthetic`, `interrupt(resume)`, `wait`. Plus session hooks:
`fork`, `prompt` (pre-admission, can add files/skills, change delivery),
`context`, **`compaction`** (see §2), `generate`, `title`,
`experimental.model.resolve` (per-request model override), `model.request`,
`http.request/response`, ws hooks, `retry`. In-repo precedent:
`/pipeline-tick` (`.opencode/plugin/pipeline-locks/index.ts` L2189-2211) wakes a
session via `ctx.session.prompt` (L2126-2136) — the proven "plugin prompts a
session" pattern; `ctx.session.get`/`update` are used live by
question-notify (L596) and the boards No-op marker recipe.

**What a plugin/created session CANNOT do:**
- A created session does **not inherit the parent's agent permission grants.**
  Agent-level permissions belong to the agent definition ("The parent agent's
  `subagent` permissions control which agents it may launch; **the child uses
  its own configured permissions**" — https://opencode.ai/docs/agents/, Modes).
  What IS inherited: session-scoped rules — "Replace the session-scoped
  permission rules. They are evaluated after the agent's rules, and the last
  matching rule wins. **Child sessions inherit the rules in effect when they
  are created**" (plugins/server docs, Permissions). An explicit ruleset can be
  passed at creation (POST body `permissions`).
- **A new session re-runs its agent's MUST-load skills — as a convention, not a
  server mechanism.** The agent's system prompt is the markdown body and is
  freshly in context for the new session; skills are "advertised" to the model
  at each step (id/name/description only) and the model loads them via the
  `skill` tool (https://opencode.ai/docs/skills/, Loading). The MUST-load
  contract lives in the agent prompt, so a fresh session with that agent re-
  executes it on its first turn. Supported reinforcements: `skills` attachment
  on the first prompt (admission-time skill selection), `@skill-id` mentions in
  the prompt text, `POST /api/experimental/session/{id}/skill` ("Activate a
  skill for a session by appending a skill message and resuming execution",
  body `{id, resume?}`), and plugin `ctx.skill.transform`
  (`autoinvoke: true/false`).
- A prompt hook cannot redirect admission (IDs readonly); a session's model
  "is stored separately" and "selecting a primary agent by ID does not change
  that model" (agents docs, Model).

### 1.3 OpenChamber (the lab's scheduled-task layer)

OpenChamber (github.com/openchamber/openchamber) is "an agentic development
environment based on OpenCode" (docs: https://docs.openchamber.dev/). "When it
runs, **OpenChamber starts a new session and sends the prompt on its own**"
(https://docs.openchamber.dev/scheduled-tasks). Loop files
(`.agents/loops/*.md`, project scope) are cron-only: frontmatter
`name/schedule/enabled/model/agent/timezone`, body = the execution prompt —
exactly the shape of `.agents/loops/pipeline-worker.md` (EXPLORE.md §2).
"A loop that came with a repository also **waits until you turn it on … and
again after a change to its schedule, model or prompt**" — this is the
`loopApprovals` fingerprint/owner-re-approval mechanic the in-repo loop file's
comment describes (`.agents/loops/pipeline-worker.md` L22-26): **editing the
loop body rotates the fingerprint and forces `enabled: false` until the owner
re-approves.** "Tasks only fire while the OpenChamber server is running."
Loop "Run as goal" (Session Goals) makes a run pursue its prompt to completion
instead of stopping after one reply.

**Consequence for ask (a):** a "shared session" in OpenChamber terms is one
loop task (cron + dedicated agent + model + body prompt). The loop does not
spawn per-card sessions by itself — the **session it runs** does: the adapted
agent-board (the loop's `agent:`) reads the board (dev-boards MCP, per the
agent's own definition) and creates each card's coord session via the
`opencode api post /api/session*` shell (or a plugin `ctx.session.create`).
Everything needed is supported: `agent`+`model` at creation (default `-local`;
`Deployment` checked → `-pr` + `agent-dev-deploy-pr` after final review — a
pure data decision from the card's Lifecycle checks), `location` = the ticket
worktree directory, `metadata` = card/slug/parent ids, first prompt = the
standard board-coord kickoff text with `skills` attachments. Two naming
surfaces ride along: the new agent must be added to the gate's exact-name
filter (§4.2) and, if it reads the board, to `BOARD_COORD_AGENTS` (§4.2).

### 1.4 Schedules & automations (alternatives / complements)

- `POST /api/experimental/schedule` — `Schedule.CreatePayload = {sessionID,
  name, when: {In|At|Every|Cron}, if: Condition (Shell|Code), until: Condition,
  ends, prompt}`; "The message the Session receives when the schedule wakes."
  (openapi.json). An experimental-route, server-side cron that wakes a NAMED
  session with a prompt, optionally gated by a shell/code condition — usable as
  a "check for unlocked cards" poller, but the release-handler-direct-prompt
  below is simpler and already in-process.
- Built-in **automation tools** (source
  `packages/schema/src/automation.ts` @ d327a9662): triggers `at`/`every`/
  `cron`/`event` (MCP server push event: `{server, event, args?}`); actions
  `prompt` (to an existing session id OR a new subagent child per run) and
  `code` (confined Code Mode, no model call, can return
  `{state, done, send: {prompt, to: {subagent}}}`). `watch_mcp_event` tool
  wakes a session on MCP push events. **Flag-gated: `automations` and
  `mcp_events` default ON only in local/dev builds — OFF in release builds**
  (`packages/schema/src/config/flag.ts`: "Flags default to on in local and dev
  builds and off in releases"); enable via `experimental.automations` /
  `OPENCODE_FLAGS`. `experimental.subagent_depth` (default 1) caps nesting —
  a coord (top-level) launching one subagent layer is fine; a subagent
  launching further subagents would exceed the default.

## 2. Compaction mechanics

Canonical docs: https://opencode.ai/docs/compaction/ (fetched 2026-11-17).

- **When it fires:** automatic compaction is ON by default; it "starts once the
  conversation reaches the rest" after keeping `buffer` free of the window —
  default `"15%"` (minimum 16k), i.e. 128k window + 20% buffer compacts at
  ~102k (80% full). Accepts `"1%"`–`"99%"` or a token count (a count ≥ the
  window is ignored). `compaction.auto: false` disables auto + overflow
  recovery; **manual compaction always works** (`POST
  /api/session/{id}/compact`, body `{id?, delivery?}` — repeats merge; runs at
  the next safe point; `id` makes a retry idempotent). Overflow recovery: "a
  request rejected as too long is compacted and retried once. A second
  rejection is returned as an error" — source: `packages/core/src/session/
  runner/llm.ts` @ d327a9662 (`recoverOverflow` one-shot per turn;
  `compaction.compact({reason:"overflow"})`); a **failed auto-compaction is
  terminal for that turn**: `if (compacted.status === "failed") return yield*
  new StepFailedError({ error: compacted.error })`.
- **What a summary replaces:** "replacing older conversation with a summary …
  also keeps the most recent conversation, about **15,000 tokens by default**
  (`keep.tokens`) beside the summary"; the summary covers objective/
  requirements, decisions, completed/active work, blockers, next moves,
  relevant files — "structured so another agent could pick the work up from
  it". "After compaction, the current versions of your instruction files become
  the session's baseline." Earlier messages stay stored but are no longer sent
  to the model. Compaction messages carry `reason: "auto"|"manual"`, status
  running/completed/failed (`Session.Message.Compaction.*`, openapi.json);
  durable events `session.compaction.started/ended/failed` carry `sessionID,
  reason, inputID, error` (openapi.json event schemas).
- **Config knobs — the complete list** (config.json schema,
  https://opencode.ai/config.json fetched 2026-11-17): `compaction.auto`
  (bool), `compaction.keep.tokens` (int ≥0), `compaction.buffer` (percent
  string or int). Plus `agents.compaction.model` (a different model for the
  summary; "falls back to the session's model" if unresolvable — hidden
  `compaction` agent, agents docs Built-ins), per-provider/model
  `settings.compaction.type: "native"|"summary"` (native = provider-side
  compaction, OpenAI Responses models), `experimental.background_compaction`
  (experimental pre-summary, warning-callout: "may change, break, or be
  removed"). The schema also lists `prune`, `tail_turns`,
  `preserve_recent_tokens`, `reserved` — all **deprecated** V1 fields (per the
  opencode skill: never recommend deprecated fields). **There is no config
  field for custom summary instructions, and no step-count window.**
- **Custom compaction instructions — the supported surface is the plugin
  `compaction` hook** (plugins/server docs, Hooks → Model requests): "
  `compaction` runs for checkpoint summaries. `messages` is the transcript
  being summarized; **OpenCode appends its summary prompt after hooks run**.
  Set `result` to record the compaction yourself and skip the model call; it
  takes the same fields as a completed compaction message" (`event.result =
  { summary, native?, metadata?, tokens? }` — `SessionCompactionResult`). The
  hook also receives mutable `system`/`messages`/`tools`/`options`, so a plugin
  can **inject** lab-specific summary instructions (e.g. "summarize as the
  pipeline handoff: card, plan folder, open questions, next chunk") into the
  summary request, or **replace** summary generation entirely (file-backed or
  rule-based summary; source confirms the path: `fromHook` — "A request hook
  supplied the summary itself, so no model call happens",
  `packages/core/src/session/compaction.ts` @ d327a9662). **An agent's own
  instructions cannot trigger or intercept compaction** — the docs expose no
  agent-facing compaction-instruction surface. An agent-side "detect context
  pressure and self-handoff" protocol (write the handoff file, then fresh
  session + /pipeline-resume-style bootstrap) is therefore **convention-only**,
  but it rides fully supported primitives: manual `compact` (or let auto fire),
  the `session.compaction.started` (reason `auto` = threshold crossed) event a
  plugin can watch, `ctx.session.hook("prompt")`/`synthetic` to force a
  handoff write, and `ctx.session.create` + `prompt` to start the successor.
- **The lab-observed failure shape (context exhaustion) is a documented
  upstream class** — error
  `{"type":"compaction.failed","message":"Compaction summary reached the
  output token limit"}` thrown from the compaction stream on
  `finish_reason == "length"` (`packages/core/src/session/compaction.ts` L823
  area @ d327a9662). Upstream issues: #54820 (summary request clamped at
  max_tokens=1024 ignoring `limit.output`), #56784 (**wedge**: provider-clamped
  summary → unbounded retry of the identical doomed compaction; "the session
  becomes unusable — including mid-/handoff writes"), #57187 (**dead-end**:
  near the context limit the summary budget collapses (max_tokens = context −
  prompt); a reasoning model spends it all on reasoning → "no retry and no
  input truncation … the session permanently dead-ends at the context limit";
  manual compaction hits the same wall), #59110 (**v2.1.4 — the version of
  record**: `compaction.buffer` doubles as the summary completion budget and
  reasoning tokens consume it, leaving zero for the summary), plus
  Niko1221/Strata#5006 (server-side OUTPUT_CAP 4096 truncates the summary;
  log line `Session.StepFailedError: Compaction summary reached the output
  token limit` at `SessionRunner.runStep`). A distinct terminal shape:
  `{"type":"output-limit","message":"Response still truncated after two output
  token limit continuations"}` (`packages/core/src/session/runner/llm.ts` —
  after two continuation injections). For a 27b model served at 200000/262144
  with a small output cap, the #54820/#59110 variants are the realistic ones —
  the design's "compaction → handoff" protocol must treat compaction FAILED as
  the primary signal, not success.

## 3. Subagent out-of-context signaling

- **What the launcher sees:** subagents (agents with `mode: subagent`,
  launched via the built-in `subagent` tool or `POST /api/session` with
  `parentID`) "always run in the background: the parent receives a report when
  a child goes idle, and again after each later round of work" (agents docs,
  Modes; tool text: "The subagent is working in the background (sessionID:
  …). You will receive a `<subagent>` message when it goes idle" —
  `packages/core/src/tool/plugin/subagent.ts` @ d327a9662). The delivery is a
  **synthetic message into the parent's inbox** (`packages/core/src/session/
  subagent-completion.ts`): `<subagent sessionID="<child>" state="completed" |
  "error" | "cancelled" | "running" description="…">\n<body>\n</subagent>` with
  `metadata: {source: "subagent", childID, agent, state}` — on error, body =
  the job's error text (or "Subagent failed"). **The parent (coordinator) is
  woken with the failure in-band.**
- **A plugin additionally sees the child's events** on the stream
  (`ctx.event.subscribe({types: [...]})`, plugins/server docs Events):
  `session.step.failed` / `session.execution.failed` (each carry
  `Session.StructuredError {type, message, status?, response.body?,
  retryAfterMs?}` for the child `sessionID`), `session.compaction.failed`,
  `session.retry.scheduled` (provider retries: `{attempt, at, error}`). There is
  **no dedicated "context limit reached" event**; the closest signals are
  `session.compaction.started` with `reason: "auto"` (the threshold crossing —
  context pressure detected) and the failure events above. question-notify
  (`.opencode/plugin/question-notify/index.ts` L105-107, L609-611) already
  subscribes `session.execution.succeeded/failed` + `permission.asked` and
  pushes Home Assistant alerts — a compaction-failure alert is a three-line
  addition (one more event type + the error-text mapping).
- **Continuability:** `subagent` tool input `sessionID` — "Send a follow-up to
  an existing subagent, **running or finished**. Omit to start a new one."
  Follow-up to a running child joins its current run; a new child "start[s]
  with fresh context, so include all relevant context and instructions". The
  session record persists after failure (Session.Info `outcome:
  succeeded|failed|interrupted`; `interrupt` with `resume` semantics;
  `subagent-job.ts` resumes via `execution.resume(id)`), so a follow-up by
  sessionID is a supported primitive — **but** for a compaction-failed
  (dead-end/wedged) session, a new prompt re-triggers the failing
  auto-compaction (#56784/#57187), so the design answer stands: **treat the
  child's compaction failure as a relaunch signal — fresh child session,
  context = the plan folder + handoff file (files are the bus), not the
  failed history.** Subagent model inheritance: "A subagent uses its configured
  model, or inherits the parent session's model when none is configured"
  (agents docs, Model) — a created session can pin the model explicitly
  instead.
- **Is "Compaction summary reached the output token limit" the only shape?** No
  — it is the compaction-failure shape. The full set observed for context
  pressure: (1) overflow-recovery-then-fail → step/execution failed with
  `compaction.failed`; (2) `session.compaction.failed` event with the same
  error; (3) `compaction.interrupted` ("Compaction was interrupted", stale
  settlement, `packages/core/src/session/runner/llm.ts` `settleStaleCompactions`);
  (4) the `output-limit` continuation terminal (response truncation, not
  compaction); (5) provider-rejection retry paths (`session.retry.scheduled`)
  for transient failures. A subagent that exhausts context normally should show
  (1)+(2) with the state="error" report to the parent; the wedge (#56784)
  means the error may repeat while the session appears alive but never
  completes — a plugin watching `session.compaction.failed` on child
  sessionIDs can detect the repeat and force the relaunch.

## 4. Doctrine + mechanics gaps (in-repo)

### 4.1 The D54(4) default-model doctrine + the minimal "measurement ON THIS BOX"

The doctrine as written: `.rulesync/skills/pipeline-models/SKILL.md` L63 —
`qwen3.8-27b-radiance` is "a measured opt-in candidate … **NEVER a default
route and no runner tier points here: q27 joins the runner pool only after
measurement ON THIS BOX (D54(4))** — the table above and the runner-model
literal stay fn/27b-q4 as written". Its three written defaults: blank Model(s)
→ `gpu-ai/qwen3.8-27b-q4` both tiers (L37); Priority default class →
`gpu-ai/qwen3.8-flash-next-radiance` (L46); runner literal
`qwen3.8-flash-next-strata-q4` (`.agents/loops/pipeline-worker.md` L5, owner
ruling 2026-11-09, moves "only by a fresh owner ruling", L10-13). D54 itself
(cf-143 DECISIONS.md L1661ff): the owner's 2026-11-15 "add 27b to radiance"
rulings — (1) pod-swap shape, git renders `radiance-q27` at `replicas: 0`,
scale fn DOWN then q27 UP (one card, one engine); (4) the catalog trio ships
with `limit.context` = the served per-session ceiling (200000 =
`--max-model-len`). "Measurement ON THIS BOX" per the 2026-11-17 owner ruling
(the 8-session runbook gate as the deciding receipt) minimally requires, on the
q27 lane: (a) the pod-swap (scale fn down, q27 up — the one-card/one-engine
law); (b) the runbook step-6 fill — `.agents/notes/
radiance-on-target-acceptance.md` L480ff: "the profile must START and then
HOLD 8 CONCURRENT 200K-class sessions on THIS host … drive 8 concurrent
sessions to the 200K-class depth while `/stats` shows running/waiting fill;
**PASS = eight admitted without refusal-class errors and decode steady**" —
run against the 262144 depth the `fix-radiance-context` branch retargets
(UNMERGED; main = 200000 is the source of record, EXPLORE.md L5); (c) the
read-only receipt list (L527ff, "the receipt decides, never the rate"): cgroup
`memory.peak` at the lane cap, `memory.events oom_kill = 0`, cgroup `file` ≈ 0,
node `MemAvailable` ≥ 8 GiB at peak, `/proc/buddyinfo` + `compact_stall`/
`compact_fail` deltas across the ramp, the engine's `pinned by this process`
inside its budget window (q27's is the 24 GiB pod class, D54(3) — the fn-
specific "≤ 100 / 71-78 GiB" numbers do not port). This run itself (running on
`gpu-ai/qwen3.8-27b-radiance` all run per the 2026-11-17 ruling) is in-progress
evidence, not the receipt. Making 27b-radiance the default therefore conflicts
with three written surfaces at once — the pipeline-models L63 doctrine, the
L37/L46 default rows, and the pipeline-worker.md runner literal — and each
moves only by owner ruling; the plan should treat the 2026-11-17 ruling as the
governing ruling and the step-6-on-q27 run as the recorded receipt, plus the
`fix-radiance-context` merge as a dependency of any 262144 claim.

### 4.2 The exact-name lists — what a new shared-session agent name must change

Two hand-maintained, exact-name, case-sensitive lists, both currently the
triple `agent-board-coord` / `-local` / `-pr`:

1. **Hourly gate** — `scripts/agent-board-coord-gate.sh` L227: `map(select(
   .agent == "agent-board-coord" or .agent == "agent-board-coord-local" or
   .agent == "agent-board-coord-pr"))`. The script pages `GET /api/session`,
   keeps sessions whose own OR child (`parentID`) `time.updated` is within the
   15-min threshold minus the 5-min grace (L213-250), and verdicts
   `GATE: LIVE` (skip the tick) vs `GATE: RUN`/`GATE: SKIP` (fail-closed). If
   the new shared-session agent does the card walk (ask (a) — "on timer runs
   finds the next card"), it MUST be added here or the hourly tick can start a
   second board run while the shared session is walking/claiming (the lock
   surface prevents double-claim of one card, but the gate is the documented
   de-duplication surface, and a non-counted dispatcher would also escape the
   "LIVE" status the board-coord runs rely on). The liveness rule then applies
   naturally: the shared session counts while active (own `time.updated` fresh),
   and falls out after 15 min idle.
2. **Board-context prefetch** — `.opencode/plugin/board-context/index.ts`
   L117-121: `BOARD_COORD_AGENTS = ["agent-board-coord",
   "agent-board-coord-local", "agent-board-coord-pr"]` (gate via
   `isBoardCoordAgent`, L123-125). An adapted agent-board that reads the board
   on its first prompt wants the structural board block injected (and the
   claim-time card-details hook keys on `pipeline_claim`, so it rides along
   automatically once the agent claims). The name must be appended here or the
   shared session re-resolves all ids top-down (the documented degrade, not a
   failure).

Both are plain array/list edits (gate: one jq disjunction; plugin: one array
entry) — but neither is rulesync-generated, so they are direct repo edits that
must land in the same change as the new agent definition
(`.rulesync/subagents/` + `rulesync generate` for the agent file itself). Note
for the plan: adding a name to the gate's list changes what `GATE: LIVE`
means (a dispatcher session now suppresses ticks) — that is the intended
behavior for ask (a), and the board skill's "one scheduled walk" posture
(`boards` skill, Provider filtering section) should be reworded in the same
wave to name the dispatcher leg. The no-op marker recipe (boards skill, No-op
marker section) applies unchanged to the shared session's no-cards exit
(scheduled kind + `pipelineNoop` marker + archived, via `opencode api
patch`).

## 5. Contradictions & how to weigh them

- **Docs happy-path vs upstream failure class.** The compaction docs describe
  the summary mechanism and the "recovered once" overflow path; issues #56784 /
  #57187 / #59110 (the lab's own observed error is #59110's v2.1.4 variant
  class) show that when the summary request itself cannot fit (output cap,
  reasoning budget, near-limit collapse) the session wedges or dead-ends with
  no escalation. Weigh: the docs govern the designed behavior; the issues
  govern the failure behavior the design must assume. The card's ask (d) is
  exactly the mitigation these issues argue for (handoff + fresh session
  instead of fighting a failed compaction) — and the `compaction` hook is the
  supported lever for keeping the summary request small/custom.
- **Version of record vs box binary.** Repo probe facts pin plugin-tool
  behavior to v2.1.4 (`.opencode/plugin/pipeline-locks/index.ts` L2106-2108);
  `opencode --version` on this box now answers **v2.2.6**. All doc/OpenAPI
  citations are current-release; nothing I cited is marked version-sensitive
  except the experimental surfaces (background_compaction, schedule routes,
  model.resolve hook — all warning-callout or flag-gated). Weigh: cite the
  docs as the contract, but treat flag-gated and experimental surfaces as
  "verify on the running version before shipping".
- **`keep.tokens` (15k) vs "last ~15 steps".** The one documented window knob
  is token-based; "steps" are not a window unit anywhere in the docs, schema,
  or source. Weigh: the card's ask (e) window is a convention (tune
  `keep.tokens` to roughly what ~15 steps cost, or treat the kept tail + the
  summary + the files-are-the-bus re-read as the window), marked
  convention-not-support below.
- **Config schema deprecated fields vs docs.** `prune`/`tail_turns`/
  `preserve_recent_tokens`/`reserved` are in the schema but marked
  `deprecated: true`; the docs' migration section says V2 uses summary +
  `keep.tokens`. Weigh: per the opencode skill's field policy, plan against
  `auto`/`keep.tokens`/`buffer` only; never emit the deprecated keys.

## 6. Implications for the plan (ask-item verdicts)

- **(a) Shared session + per-card handoff — SUPPORTED.** OpenChamber loop task
  (cron, dedicated agent, model) + `POST /api/session {agent, model, location,
  metadata}` + `POST /prompt {text, skills?}` (or plugin `ctx.session.create` +
  `prompt`). Agent/model at creation; `Deployment`-based `-pr`/
  `agent-dev-deploy-pr` selection is a data decision. Requires: a new shell row
  `opencode api post /api/session*` on the shared agent (coord rows today cover
  get/patch only, EXPLORE.md §4), the two exact-name list additions (§4.2),
  and a loop-file decision (repurpose `pipeline-worker.md` → fingerprint
  rotation + owner re-approval, or a second loop file).
- **(b) Lock-release trigger — SUPPORTED.** `releaseLockSet`
  (`.opencode/plugin/pipeline-locks/index.ts` L835-894; insertion point between
  L881 and L882) calls `ctx.session.prompt({sessionID: <shared>, text})` — the
  `/pipeline-tick` pattern (L2189-2211) is the proven precedent. Alternatives
  (schedule API, automation `event` trigger) exist but are experimental/
  flag-gated; the direct prompt is the minimal design.
- **(c) Coord read-priv widening — SUPPORTED, repo-internal.** Widen the
  read-allow list in `.rulesync/subagents/agent-coord*.md` (currently only
  `.agents/plans/**`, `.opencode/skills/**`, `.agents/skills/**`, `skills/**`,
  `.agents/loops/**`, `.opencode/agents/**` — EXPLORE.md §4) plus new
  `readonly-global-*`/`global-*` MCP rows (no agent carries them today);
  created sessions may also carry an explicit session-scoped ruleset
  (`permissions` at creation / PATCH). Keep the last-match-wins ordering intact
  (agents-sync hand-managed-array lesson: a trailing `* *` ask masks the
  denies).
- **(d) Custom compaction instructions — CONVENTION-PLUS-SUPPORTED-HOOK.**
  No agent-instruction surface exists; the supported intercept is
  `ctx.session.hook("compaction")` (inject `system` text into the summary
  request, or set `event.result` to replace the summary entirely — "no model
  call happens"), plus `agents.compaction.model`. The "coord passes the card +
  planning folder to a new session" leg is fully supported (files are the bus;
  `location` at creation; first-prompt skills). Agent-side self-restart on
  context pressure is convention-only (detect via the `compaction.started`
  auto event / the failed-compaction signal, write the handoff, create the
  successor). The subagent side: the `<subagent state="error">` report is the
  signal; relaunch-fresh (not follow-up) is the robust path (§3).
- **(e) Sliding window "last ~15 steps" — CONVENTION-ONLY.** No step-count
  knob (contradiction §5); supported primitives: `keep.tokens` (the only
  tail-size knob), `buffer` (how early), `POST /fork {before}` /
  `Session.ForkBoundary {before|through, messageID}` (a windowed copy from a
  message boundary), `GET /context` (messages after the last compaction).
  "Fresh context reads plan + context files, then skills, like
  /pipeline-resume" is the existing pipeline convention and needs no new
  mechanism (first prompt + `skills` attachments + `skill` tool).
- **(f) 27b-radiance default — BLOCKED UNTIL RULING+RECEIPT (owner ruling now
  exists: 2026-11-17).** The 2026-11-17 ruling supplies the owner gate and
  names the 8-session runbook gate (on the q27 lane, 262144 depth) as the
  receipt; the plan must also sequence: `fix-radiance-context` merge
  (unmerged; 200000→262144), the pod-swap scale-up (q27 `replicas: 0` in git —
  defaulting the model while the pod rests = 502 peer-proxy refusals,
  EXPLORE.md gotcha), and the three written doctrine surfaces (pipeline-models
  L37/L46/L63, pipeline-worker.md L5) — each a doctrine text change in
  `.rulesync/skills` / `.agents/loops` in the same wave.

## 7. Open questions

1. **Loop vehicle** — repurpose `pipeline-worker.md` (fingerprint rotation,
   owner re-approval, body rewrite) or a second loop file for the dispatcher?
   "One scheduled walk" doctrine wording needs an amendment either way.
2. **Gate semantics** — should the shared session count as LIVE only while
   actively walking/claiming (naturally, via `time.updated` freshness), or does
   the design want it counted for the whole hour (which would need a
   heartbeat, e.g. a periodic no-op tool call)?
3. **Compaction hook scope** — one repo plugin for all sessions (global
  `compaction` hook that inspects the session's agent) vs per-agent; the hook
  is session-wide, so the "coord variants get their own compaction
  instructions" wording maps to a single plugin keyed on agent id (supported:
  the hook event carries `agent`).
4. **Summary model for 27b-radiance sessions** — `agents.compaction.model` can
  point summaries at a smaller model (e.g. the flash lane) to dodge the
  #59110 reasoning-budget failure; is that in scope, or do summaries stay on
  the session model?
5. **262144 vs 200000 for the receipt** — the runbook gate says "200K-class";
   does the D54(4) receipt run at 262144 (per the 2026-11-17 retarget) or
   200000 (the runbook's written class) — the two branches (main vs
   fix-radiance-context) differ.

## Adjacent

- `POST /api/session/{id}/interrupt` (`resume: false`) +
  `subagent-job.ts` `execution.resume(id)` show the server's own
  restart-recovery primitive (orphaned-claim sweep at boot) — a coord session
  that dies mid-chunk is resumable on server restart by design; the compaction
  dead-end is the one class that is NOT recoverable by resume.
- `ctx.session.instructions.entry.put` (keyed instruction entries, announced at
  the next step boundary without a message turn) is a supported way to push
  late-arriving context (e.g. "card X was just released") into a live session
  without a full prompt turn.
- `experimental.subagent_depth` (default 1) and the `subagent` permission
  rows together bound the pipeline's launch tree to coord → one subagent layer;
  the shared-session design does not change that bound.

---

## 2026-11-22 C06 follow-up probe — the "OpenChamber compaction prompt" question (D35 revision evidence)

Focused re-ask after the owner's 2026-11-22 direction: the remembered "compaction
prompt" was checked against OpenChamber's magic-prompts family (standing probe clone
`/tmp/opencode/cf126-c06-probe/openchamber` @ `cb45f2f`, 2026-11-21), a FRESH OpenCode
config-schema fetch (https://opencode.ai/config.json, 2026-11-22), and OpenCode source
`anomalyco/opencode` @ `4c7ef3e12` (dev, 2026-11-21, re-cloned to
`/tmp/opencode/cf126-probe2/oc`). Read-only; no live-instance probes.

### 1. Magic-prompt enumeration — no compaction entry exists; the /compact leg carries NO text

- `packages/ui/src/lib/magicPrompts.ts` defines **46 prompt ids** (grep `id: '`: 72-933);
  **none contains "compact"** (27 are `session.*`). The summary pair is
  `session.summary.visible` (L355-363, template `Summarize this session{{topic_line}}.`)
  and `session.summary.instructions` (L365-391) — the owner's remembered prompt. Its
  default opens: "**Produce a non-destructive summary of this conversation. Do NOT
  compact or mutate session history** — your output is an additional assistant message
  the user will read and may use to hand off to a new session." — then sections for
  completed/in-progress work, files, open questions, carry-forward constraints,
  decisions, formatting rules (this is the do-not-mutate safety line the risk flag
  below protects).
- Command dispatch (`packages/ui/src/components/chat/composer/submit/slashCommands.ts`):
  `/summary` IS a `MAGIC_PROMPT_COMMANDS` entry (L33-40: `visiblePrompt:
  'session.summary.visible'`, `instructionsPrompt: 'session.summary.instructions'`,
  `topic_block` variables L19-26); the rendered instructions ride the request as a
  **synthetic message part** (`useComposerSubmission.ts` L527-528, L537:
  `{ text: instructionsText, synthetic: true }`). `/compact` is instead a
  `LOCAL_ACTION_COMMANDS` member (L114-121, `compact` at L119) — an ACTION, no prompt
  template at all: `runComposerActionCommand.ts` L93-101 calls
  `sessionActions.compactSession(sessionId, model?, directory?)`, and
  `packages/ui/src/sync/session-actions.ts` L451-468 optionally switches the model, then
  calls `opencodeClient.compactSession(sessionId, directory)` — OpenCode's compaction
  operation. **No magic-prompt text can feed the compaction request via OpenChamber, and
  nothing from the summary prompts leaks into the /compact leg.**
- Edited-prompt persistence (`packages/web/server/lib/magic-prompts/DOCUMENTATION.md`,
  Ownership + Invariants): TWO scopes, both **OpenChamber server storage — never the
  OpenCode config file**: global overrides in `<data dir>/magic-prompts.json`
  (`magic-prompts/routes.ts` L51; data dir = `$OPENCHAMBER_DATA_DIR` else
  `~/.config/openchamber` — `packages/web/server/runtime.ts` L438-441), project
  overrides in the checkout's `<repo>/.openchamber/project.json` `magicPrompts` key
  (owned by `../projects`; `projects/DOCUMENTATION.md` L14 personal vs L27-29 shared:
  "`version: 1`; `setupWorktree`, …, `plansDir`, and `magicPrompts`, which
  `../magic-prompts` owns"). The DOCUMENTATION states the shared file is "**hand-edited
  and committed**" — i.e. OpenChamber itself designs for a REPO-COMMITTED override
  route. API: `GET/PUT/DELETE /api/magic-prompts[/:id]` (`routes.ts` L62-65), scope
  selected by query (`scope`/`projectId`), project owner resolved by deepest registered
  project (worktrees: the primary checkout's file wins). Settings UI page:
  `packages/ui/src/components/sections/magic-prompts/MagicPromptsPage.tsx`.

### 2. OpenCode config schema — no summary/compaction INSTRUCTION text; numbers only

Fresh fetch 2026-11-22. `compaction` object properties, complete: `auto`, `background`
(new boolean — OpenCode 2.3.1 moved background compaction out of
`experimental.background_compaction` to `compaction.background`, on by default, per
`CompactionSettings.tsx` L26; corrects §2's knob list from 2026-11-17), `buffer`, `keep`,
plus the four DEPRECATED keys (`prune`, `tail_turns`, `preserve_recent_tokens`,
`reserved`). **No prompt/instructions/summary-text field.** Top-level scan: the only
text-bearing keys are `instructions` (array — "Additional paths or URLs supplying
ambient instructions"), `commands.<name>` (`Config.CommandEncoded`: `template` required,
+ `description/agent/model/subagent`), and per-agent `Config.AgentEncoded.system`
(string). None governs the compaction prompt:
- `agents.compaction.system` settable in schema, but **NEVER consumed** — the compaction
  code reads the hidden agent ONLY for `.model`: `yield* agents.get(Agent.ID.make(
  "compaction"))` then `agent?.model && models.resolve(...)` (
  `packages/core/src/session/compaction.ts` L278-291 @ 4c7ef3e12).
- The real compaction instruction is INTERNAL, assembled by `buildPrompt`
  (`compaction.ts` L211-224: the "Summarize only what the user and the assistant said…"
  rule + `SUMMARY_TEMPLATE` (L170) + `SUMMARY_RULES` (L203-208, incl. "Do not mention
  the summary process or that context was compacted")), and appended as a user message
  AFTER hooks: "Hooks saw the request without the summary prompt, so it is appended
  here" (L484-485, `Message.user(prompt)` at L489). Only two levers exist: pre-append
  context into the request the hook sees (the shipped D9 mechanism — the hook can push
  `event.system` parts / supply `event.result` outright, §2 of the 2026-11-17 round).
- Command-template mechanics: a config `commands.*` entry's `template` is ordinary PROMPT
  text sent to the model on invocation — it can never reach the internal SUMMARY prompt
  of a compaction request; and in OpenChamber the `/compact` slash never hits OpenCode's
  command registry at all (LOCAL_ACTION above), so a `/compact`-named config command
  cannot carry instructions into the lab's compaction path even by shadowing.
- ADJACENT (numeric knobs): OpenChamber's Compaction settings UI (`CompactionSettings.tsx`
  L39-42 reads, L145 `PUT /api/config/compaction`) does NOT keep values in its own
  storage — `web/server/lib/opencode/routes.ts` L554 → `websearch-config.ts` L43-50
  (`setCompactionSettings` → `getJsonWriteTarget(layers, USER)`) → `config-v2.ts`
  L706-724 writes `compaction.{auto,background,buffer,keep.tokens}` INTO the OpenCode
  config file itself (user scope `~/.config/opencode/opencode.json(c)`; custom-path wins
  if set — `config-files.ts` L669-681). So the compaction NUMBERS are
  opencode.jsonc-settable, and the repo's own `.opencode/opencode.jsonc` can carry them
  per the UI's own note ("A project whose own OpenCode config sets these keeps its own
  values" — `compaction-settings.i18n.ts`). The TEXT never is.

### 3. Verdict table — the three candidate landing routes for the artifact line

| Route | Verdict | Evidence |
|---|---|---|
| (a) owner pastes the artifact line into the OpenChamber magic-prompt UI field | **SUPPORTED (with scope limit + replace-risk)** — edits `session.summary.instructions`, persisted at global scope to `~/.config/openchamber/magic-prompts.json` (machine-local, human-owned — D35's posture holds for this route). It governs the **/summary leg only**; it can NEVER touch /compact/auto compaction (no prompt leg there, §1) | slashCommands.ts L33-40 + useComposerSubmission.ts L527-537; persistence magic-prompts/DOCUMENTATION.md Ownership + routes.ts L51 + runtime.ts L438-441 |
| (b) repo sets it via `.opencode/opencode.jsonc` | **NOT-SUPPORTED as stated** — no schema key carries summary/compaction instruction text; `agents.compaction.system` is settable-but-unread (§2); command templates don't reach compaction (§2). **REVISED: a repo-committed route exists via a DIFFERENT file** — `<repo>/.openchamber/project.json` `magicPrompts: { "session.summary.instructions": "<full default + artifact line>" }` — OpenChamber's own team-shared, hand-edited-and-committed project file; the repo does not track `.openchamber/` today (git ls-files: no hits), so this is a new tiny file. It resolves by project ownership incl. worktrees (primary-checkout wins) | absence: config.json 2026-11-22 full key scan; presence: magic-prompts/DOCUMENTATION.md Ownership ("the `magicPrompts` map of a project file is hand-edited and committed") + projects/DOCUMENTATION.md L27-29 |
| (c) the true governing instruction is OpenCode's internal compaction prompt; hook-injection into the system array (shipped D9) is the only influence lever | **SUPPORTED — and it is the shipped design** — `buildPrompt` internal + appended post-hooks (compaction.ts L211-224, L484-491); the pipeline-locks hook already injects the pointer-summary law + the `instructions.entry` handoff note (plugin L97, L1448-1490, D9 in DECISIONS.md L21). The owner's artifact line is NOT the obey-trigger for compaction — the D9 note already is; the magic prompt only shapes the /summary output | compaction.ts @ 4c7ef3e12; .opencode/plugin/pipeline-locks/index.ts @ the ticket branch; DECISIONS.md D9 |

**RECOMMENDED ROUTE:** keep (a) as the live owner-paste path (USER step 7 stands), with
(a)+(b′) composed — but any paste/override MUST re-emit the FULL default template with
the artifact line appended, because resolution is whole-replacement by key presence
(`resolveMagicPromptTemplate`, magicPrompts.ts L1149-1155: project→global→builtin, first
hit wins; DOCUMENTATION invariant "An empty string is a value and wins") — a short
one-line override would **REPLACE the default and LOSE the "Do NOT compact or mutate
session history" safety line** and the handoff format. That is the flagged composition
risk. If the owner prefers the repo to carry it, route (b′) is real and cheap (one
tracked JSON file); its own fragility: one wrong entry makes the whole project scope
`invalid` (refused wholesale, DOCUMENTATION invariant), so a committed file deserves a
validation needle (parse + key-presence test) in the same wave.

### 4. Implications for the ticket (D35 / C06 revision)

D35's clause "no repo surface sets it" is **half-refuted**: true for opencode.jsonc
(schema + source prove no text path), FALSE in general — OpenChamber itself commits to
`<repo>/.openchamber/project.json` as the hand-edited, version-controlled place for
exactly this map, so the C06 artifact CAN become a tiny repo leg (add the file with the
full default text + the one-line append) instead of paste-only — a C06 round-2 option
for the owner to choose; if the owner keeps it a paste, D35 and USER step 7 stand
unchanged for route (a). Either way the plan wording must now say precisely what the
line governs: the **/summary handoff leg**, not compaction (the compaction obey-trigger
is already the D9 `instructions.entry` note, and the pointer-summary law the D9 hook
injection — both shipped and unaffected); and C03's §2 knob list should absorb the
2.3.1 drift (`compaction.background` replaces `experimental.background_compaction`; the
numbers are UI-writable into the user config, the repo's own config may hold them).
No changes to the ask-item verdicts §6 (a)-(f) beyond this compaction-text nuance.
