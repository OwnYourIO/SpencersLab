# EXPLORE-plugins.md — the four hand-written plugins, file by file

Ticket AD-140 (`cf-140-feat-agent-card-reconcile`) · scout grounding · 2026-11-23
Scope: `.opencode/plugin/{pipeline-locks,board-context,question-notify,aislop-gate}` + their tests and
every pin family that references them. All four are single-file `index.ts` modules. Evidence style:
`file: symbol`. No bare line numbers.

## 0. Plugin registry, install pattern, config wiring

- **Shape**: each plugin is one `index.ts` default-exporting a plain object
  `{ id: "local.<name>", async setup(ctx) }` — **not** `Plugin.define`, so there is no runtime
  `@opencode/plugin` resolution dependency (`.opencode/plugin/aislop-gate/index.ts: header`;
  `.opencode/plugin/pipeline-locks/index.ts: header` "the plain `{ id, async setup(ctx) }` default-export
  object those two ship"). All four set the same `local.` id prefix
  (`local.pipeline-locks`, `local.board-context`, `local.question-notify`, `local.aislop-gate`).
- **Discovery**: OpenCode server auto-loads every module under `.opencode/plugin/` (`.opencode/plugin/
  pipeline-locks/index.ts: header` cites `opencode.ai/docs/plugins` "From local files";
  `.opencode/plugin/pipeline-locks/index.ts: default.export setup` — "one server process loads this
  plugin once per location dir (D27, probed on v2.1.4)"). Consequence recorded in-repo: a cross-plugin
  import registers the imported plugin a **second time** as a dependency entry — hence the "duplicated,
  never imported" precedent for the raw-MCP transport (`.opencode/plugin/pipeline-locks/index.ts:
  makeCallTool` header block "Raw MCP-over-HTTP mechanics: … Duplicated, never imported").
- **The one sanctioned cross-plugin import**: `.opencode/plugin/board-context/index.ts: localIso import`
  (`import { localIso } from "../pipeline-locks/index.ts"`) — a leaf function, "importing a leaf
  function registers nothing a second time" (both headers carry the justification). **card-runner gotcha:
  if it imports from a plugin file it is replacing/removing, that import re-registers the removed
  plugin** — the replacement must be self-contained or import only leaf functions from files that stay.
- **Enable/disable**: `.opencode/opencode.jsonc: "plugins" array` — the only entry is
  `"plugins": ["-local.question-notify"]`: the `-` prefix removes a discovered plugin by its declared
  ID; the comment records **owner-disabled 2026-11-21**, the file under `.opencode/plugin/` stays
  untouched, and this one entry is the whole toggle. The other three plugins (pipeline-locks,
  board-context, aislop-gate) have no entry — they load by discovery alone. A `card-runner` plugin will
  likewise need no config entry to load; disabling it is a `"-local.card-runner"` entry.
- **Compaction config**: `.opencode/opencode.jsonc: "compaction"` — the repo's only compaction knob is
  `keep.tokens = 15000` (a ~15-step-class convention, no step-count window in the schema); the comment
  pins that "the auto threshold + the pipeline-locks compaction hook are the only triggers" and NO
  per-turn manual compaction.
- **Tool visibility (v2.1.4)**: `.opencode/plugin/pipeline-locks/index.ts: buildToolSpecs` — "On
  OpenCode v2.1.4 plugin tools are reachable ONLY through Code Mode: call `tools.<name>` from the
  execute tool (probe fact, D29) — never as a native provider tool." Visible name is the flat
  `pipeline_*` id (no namespace option; adding `options.namespace` on a prefixed name double-prefixes).
- **ctx.storage semantics**: the kv namespace is keyed by **plugin id alone**, shared across
  worktree locations and server processes (`.opencode/plugin/question-notify/index.ts: header` fan-out
  block; `.opencode/plugin/pipeline-locks/index.ts: CLAIM_KEY_PREFIX` comment "ctx.storage is plugin-id
  + project-id scoped and shared across worktrees — D26").
- **ctx surfaces used, all capability-gated with a degrade line**: `ctx.session.hook("prompt")` and
  `ctx.session.hook("compaction")` (board-context/pipeline-locks setup), `ctx.tool.hook("execute.before"/
  "execute.after")` (all four), `ctx.tool.transform` + `editor.add` (tools), `ctx.command.transform` +
  `editor.add` (commands: `reload-board-context`, `pipeline-reap`/`pipeline-status`/`pipeline-tick`),
  `ctx.event.subscribe({signal})` (event streams), `ctx.session.get` / `ctx.session.context` /
  `ctx.session.prompt`, `ctx.mcp.transform` (config view — the only one whose entries carry full server
  configs) and `ctx.mcp.list()` (status view; v2.1.4 answers name+status only, no url). Every missing
  surface degrades to a stderr line, never a setup throw (`pipeline-locks: setup` header "D31: the whole
  body sits inside try/catch").
- **MCP access from plugins**: raw JSON-RPC over streamable HTTP — plugins run in the server process
  outside any agent session, so the session's MCP tools are not available (all four headers).
  `dev-boards` and `admin-global-homeassistant` authenticate server-side / by tier; the plugins hardcode
  no ingress host and discover the URL at runtime (see per-plugin sections).
- **`~/.local/share/opencode/log/opencode.log` on this host**: checked 2026-11-23 — the 2194
  "board-context" hits are other sessions' shell invocations (sweep drivers, test runs); **none of the
  known degrade lines** ("degraded: no usable ctx.storage", "prompt hook degraded", "claim-time card
  details degraded", "claim hook failed", "no ctx.tool.hook") appears in the current log window. The
  live board-coord runs execute on the OpenChamber host, so which degrade path fires there is not
  provable from this repo (open question OQ-1 below).

## 1. `pipeline-locks` (`.opencode/plugin/pipeline-locks/index.ts`, 2767 lines)

Lease locks for parallel board-coord loops. One lock file per pipeline at the **canonical repo root**
under `.pipeline/locks/<pipelineKey>.json`, so worktree sessions of one repo serialize on shared
pipelines (`resolveLockRoot` — D10 chain: `ctx.location.project.canonical` → git worktree `.git`
`gitdir:` parse (only the `.git/worktrees/<name>` suffix strips) → start dir; never throws).

### 1.1 Exported constants (parity-grepped, each exactly once)
`LABEL_PREFIX = "Pipeline:"`, `DEFAULT_PIPELINE = "default"`, `DISPATCHER_AGENT =
"agent-board-dispatch"`, `TOOL_NAMES = [pipeline_claim, pipeline_release, pipeline_heartbeat,
pipeline_status]`, `RELEASE_OUTCOMES = ["done","abandoned","handoff"]` (no engine logic branches on the
outcome value), `TICK_PROMPT` (the loop-file body verbatim; pinned by `pipeline-locks-tick.test.ts` and
the boards skill), `PIN_KEY = "pipeline-lock"`, `HANDOFF_ENTRY_KEY = "pipeline-handoff"`.

### 1.2 Lock record format (v2, `newLockRecord`)
`{ version: 2, pipeline, pipelineSet: <sorted>, state: "live"|"failed", claimedAt, heartbeatAt, holders:
[{ cardId, sessionID, setId, claimedAt, heartbeatAt, cardTitle? }], takeover?: "after_reap" }`.
- Key derivation: `sanitizePipelineKey` — `[^A-Za-z0-9._-]` → `-`, 100-char bound, empty → `default`;
  `derivePipelineSet` — case-sensitive `Pipeline:` prefix, trimmed remainder, deduped+sorted,
  **no labels → `["default"]`** (D17).
- **All files of one claim carry the shared identity** (sessionID + cardId + setId + full pipelineSet)
  (D18); `setId = randomUUID()` per claim.
- v1 tolerance: `viewHolders` — a record with flat identity fields (pre-co-tenancy) is read as one
  synthetic holder; the synthetic row is never written back.
- Co-tenancy: one lock file holds N holders; **file-level `claimedAt`/`heartbeatAt` are
  last-writer-wins** (owner-accepted "stomp" surface), while every holder carries its OWN stamps so a
  silent co-tenant still ages out (`newLockRecord` comment; `beatRecord`).
- Writes: `writeLockAtomic` — tmp sibling + rename, then `utimes` moves mtime (the reaper's staleness
  formula is `max(heartbeatAt, mtime)`); parse error / missing file → `null` via `readLock` (older-schema
  tolerance: unknown keys survive).
- `TornLockError`: a file that names no holder is "unreadable state, not free state" — claims refuse to
  merge into it (`acquireSetWithRollback`).

### 1.3 Claim semantics (`claimLockSet` / `acquireSetWithRollback`)
- **All-or-nothing over the card's whole pipeline set, keys acquired in sorted order** (the deadlock
  argument) with rollback of everything taken on first contention (D18).
- New key: `fs.open(path, "wx")` — **O_EXCL create**; the race loser re-reads and answers with the
  winner's holder rows (`readHolder` with `HOLDER_READ_DELAYS_MS = [0,2,5,15,40]` retry so the loser
  names the real winner).
- Contended key with live foreign holders and no `shared: true` → `OccupiedError` → refusal
  `reason:"occupied"` with `holderReport` rows `{cardId, sessionID, age, cardTitle}` — "the emptiness
  rule, asked of the engine" (C08 AC1). **This is the mechanism behind owner symptom (b)**: cards
  without a `Pipeline:` label all map to the single `default` lock file, so only one board-coord run
  can hold a claim at a time; a second run on another unlabeled card gets `occupied` and the worker
  must ask the human for the `shared: true` override (a per-claim human input — "nothing here may widen
  it into a deployment-wide setting").
- `shared: true` appends the claim's holder to the existing file (`appendLockHolder`, with a
  re-read-after-write retry loop so a dropped co-tenant would take a false lock-lost); the co-tenant
  list rides the answer.
- `already_held` refusal: one card per iteration — a session holding a claim (checked against both the
  in-process map and durable storage, "because a server restart empties the in-process cache while the
  disk locks persist") cannot claim again.
- **Reap-before-claim**: every claimant sweeps through the guarded reaper first (`claimLockSet` →
  `env.reapStale({trigger:"claim"})`).
- Card-id takeover (C09): a claim whose whole set is exactly the card's own id, backed by a `.reaped/`
  record naming that card (`hasReapRecordFor`), is tagged `takeover:"after_reap"` — **evidence, never a
  permission** (C09 AC3/AC4).
- Claim bookkeeping: in-process `env.claims` map + durable `claim/<sessionID>` storage row
  `{setId, cardId, pipelineSet, sessionID}`; child mappings `child/<sessionID>`; both rebuilt on setup
  via `storage.scan` (restart-resume, D26). Disk locks stay the truth on any storage miss.
- Capability-gated instruction pin (`bindPin` — `ctx.session.instructions.entry`); on v2.1.4 `env.pin`
  is null and **the tool responses themselves are the primary lock-identity channel (D28)**.

### 1.4 Release + dispatcher wake (`releaseLockSet` / `wakeDispatcher`)
- Idempotent quiet success when the session holds nothing. Whole-set owner check **per holder** before
  touching anything (a mismatch touches nothing); then only OUR holder rows are removed; a file
  disappears once its holder list empties (the last co-tenant's own release).
- Audit row `release` (with outcome); storage + pin cleanup.
- **Wake leg runs AFTER cleanup, BEFORE return, only on a non-empty released set**: every non-empty
  release prompts the tracked dispatcher session (`env.sessionPrompt` → `ctx.session.prompt`) with the
  wake text "pipeline-locks: a lock set was released (card=… outcome=…). Check for the next pickable
  card and spawn a coord session if one is eligible…". No branch on the outcome value. A failed or
  undeliverable wake costs only the wake — "the hourly tick self-heals".
- Dispatcher tracking (`handleEvent` CREATED leg, which sits ABOVE the parentID early-return): a session
  is tracked as the dispatcher only when **both** legs agree — exact agent id `agent-board-dispatch`
  AND `metadata.pipelineDispatcher === true` (sibling marker in the session metadata namespace, the same
  namespace as the no-op marker).
- Terminal events: `session.execution.succeeded` is bookkeeping only ("turn end is not iteration end,
  B.9 — the release rides the card's move to Review, D6"); `failed`/`interrupted` on the ROOT session
  either release (`releaseOnFailure: true`, config) or `markSetFailed` (file-level `state:"failed"`,
  no further beats, ages out to the reaper).

### 1.5 Heartbeat engine (C04)
- **Activity-only (D20)**: `runBeatTick` (timer, default `timerMs` 300000 = 5 min) beats only while
  the root or a mapped descendant is executing; idle roots deliberately receive nothing — that is what
  lets a human stop point age into staleness. `handleEvent` tracks `execution.started` / terminal
  events in `env.executing`, maps children to roots (`resolveRoot` — deferred parent walk, 16 hops max,
  60 s negative cache, durable child map), and forces a beat on `child_mapped` / `execution_started`.
- `heartbeatSet`: verifies **every member before touching any** (a per-file half-beat would keep a
  doomed set alive — state is set-wide, D18); `missing`/`stolen` → `handleLockLost` set-wide;
  `unreadable` → beat skipped (transient read failures never trigger the lost path).
- Per-(pipeline, session) throttle (default 30000 ms = 30 s, `hookThrottleMs`); forced beats (manual,
  child_mapped, execution_started) skip the throttle; audit: every 10th ordinary beat + all forced.
- Hook beats: `toolBefore`/`toolAfter` (execute.before/after on every tool EXCEPT the four
  `pipeline_*` tools — "hooking them here would double-write") — the before-hook also **is the strict
  lock-lost guard** (below).
- `pipeline_heartbeat` tool (manual, forced): answers `{ok:false, reason:"lock_lost", note:
  LOCK_LOST_STOP}` when the engine's beat just took the lost path.

### 1.6 Lock-lost stop (D16/D18, C09)
- `handleLockLost`: losing ANY member loses the WHOLE claim; ownership-guarded cleanup (a member that
  already belongs to a FRESH healthy claim is left untouched — "a live new claimant" must not be
  cascaded); member holding only our row is deleted, shared members are rewritten without our rows;
  stop marker `env.lockLost` armed **until this root makes its OWN new claim** (no self-reclaim, ever);
  `LOCK_LOST_STOP` (the single stop text, suites pin the literal) carries the sanctioned resume: one
  question to the user; on yes, a FRESH claim under the card-id key with `pipelines:[<cardId>]`,
  tagged `after_reap` when a reap record backs it; on no/silence, the blocked/abandoned exit.
- Guard: `toolBefore` throws `LOCK_LOST_STOP` on `GUARDED_TOOLS = ["edit","write","bash"]` when a stop
  marker is armed (or the beat just detected a loss); read-side tools stay open; the throw text IS the
  stop signal on v2.1.4 because `execute.after` never fires for before-blocked calls (C01 fact 2).
- `pinLostStop` writes the stop + reap stamp (read from `.reaped/` via `reapedStampFor`) to the
  instruction pin when the API exists.

### 1.7 Reaper (C05, `reapStale` / `reapOneLock`)
- Cadence: timer default 600000 ms (10 min) + claim-time + `/pipeline-reap` + `/pipeline-tick` triggers;
  **cross-process guard**: `mkdir .pipeline/reaper.lock` as atomic test-and-set; a guard older than
  300000 ms is stolen once (a killed reaper).
- Staleness: `staleMs` default 7200000 (2 h, D21); stale iff `now − max(heartbeatAt, mtime) ≥ staleMs`;
  older-schema tolerance (missing heartbeatAt → mtime; parse error → reaps by mtime, cardId unknown).
- **Co-tenancy / holder-granularity prune** (C08 AC5): with >1 holders, only the silent holders
  (`now − holder.heartbeatAt ≥ staleMs`) are pruned from the file (`pruneStaleHolders`) while the file
  and busy co-tenants stay; all-silent → the whole file goes.
- The reap itself: **rename to `locks/.reaped/<pipeline>.<now-ts>.json` — the rename is the atomic
  claim** (two reapers cannot both move one file); then re-read the moved copy — a heartbeat that
  landed between check and rename shows as fresh → `restoreRacedLock` (rename back only while the
  destination is proven vacant; occupied/unreadable → the copy stays under `.reaped` for forensics,
  audit `restored:false`).
- `reapedAt` stamp written onto the copy (the pin evidence `reapedStampFor` reads back); per-holder
  audit rows `reaped`; `clearDeadHolders` frees the dead holder's claim cache (only when the reaped
  setId matches — a session with a FRESH claim keeps its caches); beat throttle stamps cleared.
- `meta/lastReap` written (`{at, trigger, reaped: [unique pipeline names]}`).
- **Per-card board leg** (`runReapCardLegs` / `moveCardToTimeout`, D18/D24): reaped members of one
  claim group into ONE timeout event; sequence `get_card → list_lists → move_card → add_comment`; the
  `Timeout` target resolves **against the card's own swimlane echo** (titles repeat across swimlanes);
  no target → move skipped but the comment still lands, plus a `timeouts.jsonl` row (the D22 interim
  — every failure arm appends the full row `{at, cardId, setId, pipelines, sessionID, reason,
  takeover: TAKEOVER_HINT}` and audits `board_move_err`; "the row is the triage mechanism").
  Comment text: `TIMEOUT_COMMENT` ("Timed out: no heartbeat for 2h") + session/pipelines +
  `TAKEOVER_HINT`, sliced to `MAX_OUTBOUND_MESSAGE = 240` (shared ceiling with question-notify).
- HA alert leg (`sendHaReapAlert`): fire-and-forget via the **admin** HA tier (`HA_SERVER_KEY =
"admin-global-homeassistant"` — the readonly ha-mcp rejects service calls); runs AFTER the file move
  and the board leg; gated by `haNotify !== false` (the no-op marker never reaches it).
- Board leg degrades: no `dev-boards` client / no `Timeout` list / any MCP failure → `timeouts.jsonl`
  row, the reap itself never fails on a leg.

### 1.8 Compaction contract (cf-126 C03, D8/D9/D32)
- **ONE process-wide compaction hook**: `ctx.session.hook("compaction", …)` registered in setup (the
  blast radius is ruled: every session in this repo gets the pointer-shaped summary + note; "the agent
  selects the instruction variant, never gates").
- `handleCompaction`: appends to the summary draft text in place (`request.text`); variant selection —
  `HANDOFF_FULL_AGENTS` (the six coord names + dispatcher) get the pipeline handoff pointer (plan-folder
  path, open questions, current chunk id + state; card id woven in when the session holds a claim) vs
  the generic context-pointer leg. The pointer law **omits what's-done/what's-next on purpose** (files
  are the bus; "Keep this summary small").
- Keyed note under `HANDOFF_ENTRY_KEY = "pipeline-handoff"` (sibling key to the claim pin, so the handoff
  note never overwrites the lock identity) via `ctx.session.instructions.entry.put({sessionID, key,
  value})` — capability-gated; a v2.3.0 live-fire note in the setup binder records `entry.put` takes
  `{sessionID, key, value}` — **a `{key,text}` input throws "Missing key"**; the binder maps text→value.
  On v2.1.4 the seam is absent and the summary leg carries the law.
- **`session.compaction.failed` listener** (`handleEvent` → `recordCompactionFailure`): RECORD ONLY —
  the repeat IS the #56784 wedge signal, so nothing dedupes and nothing filters; audit row
  `compaction_failed {sessionID, agent (fallback "unknown"), error (500-char excerpt), cardId, setId}`;
  the live v2.3 envelope is `{sessionID, reason, error}` flat under data with no agent field.
- Disposal: the returned setup cleanup disposes the compaction hook registration.
- **Creep-back guard**: `tests/opencode/question-notify.test.ts: T15` pins that question-notify carries
  NO compaction leg (strings and dispatch gone — cf-126 C05 moved the leg here); a scanner catches any
  restored dispatch. A `card-runner` that absorbs both plugins must keep this pin pointed at the right
  file (or re-pin it deliberately).

### 1.9 Config loader (`loadConfig`, D8)
`.pipeline/config.json` ONLY (optional file at the runtime dir; read at setup through the seam —
module-scope sync fs is banned, the tick suite pins it): number keys `staleMs/timerMs/reapEveryMs/
hookThrottleMs` (finite positive), booleans `releaseOnFailure/strictLockLoss/haNotify`, `maxWorkers`,
`board.{boardTitle,swimlaneTitle,timeoutListTitle}` (defaults `AI-Dev` / `In Process` / `Timeout`).
Wrong-typed values fall back per key WITHOUT coercion (a typo cannot quietly rewrite a cadence into NaN);
malformed file = one log line, never a throw. Baked defaults: stale 7200000, timer 300000, reap 600000,
hookThrottle 30000, `releaseOnFailure: false`, `strictLockLoss: true`, `haNotify: true`.

### 1.10 Commands (`buildCommandSpecs`)
`/pipeline-reap` (one guarded pass now, answers the summary; `skipped` when the guard is held
elsewhere), `/pipeline-status` (groups per claim with holder list when shared + lastReap),
`/pipeline-tick` (**reap-before-prompt** — `reapStale({trigger:"tick"})` first, then prompts the
session with `TICK_PROMPT` — the D30 plain-text loop body; a broken reap still hands the work prompt).
Commands answer through `ctx.session.prompt` on the invocation's own envelope (C01 fact 4's proven
shape).

### 1.11 Audit JSONL (`appendEvent`, `.pipeline/events.log`)
Fire-and-forget (a broken path logs one line and resolves). Rows: `claim` (+ shared/coTenants/
takeover), `claim_rollback`, `release`, `beat` (throttled), `child_mapped`, `exec_failed`, `lock_lost`,
`reaped` (per holder, `pruned: true` for prunes), `reap_raced` (restored true/false), `board_move_err`,
`compaction_failed`, `tick`. Every row carries `at: localIso(...)`.

### 1.12 `localIso` stamp helper (exported)
The single formatter behind every displayed ISO stamp (locks, audit, timeouts, reap-meta, board-context
collection stamp): workspace-local ISO-8601 WITH offset while `$TZ` resolves (Intl `longOffset`), the
UTC `Z` spelling of the same instant otherwise (unset/blank/unresolvable all fall back; `Z` is the zero
offset's own designator — "one spelling per instant"); milliseconds ride through so
`Date.parse(localIso(x)) === x`; a bad `$TZ` costs a shape, never a write. Pinned by
`tests/cf96-tz/surface.sh` (single implementation; exactly one `localIso` definition; board-context's
`collectedAt` must reference it).

## 2. `board-context` (`.opencode/plugin/board-context/index.ts`, 856 lines)

Ahead of the FIRST prompt of a board-coord session, fetches the AI-Dev board context block from
`dev-boards` and appends it; plus a claim-time single-card leg; plus `/reload-board-context`.

### 2.1 The prompt-hook leg (where the block is produced and injected)
- Registered in setup: `ctx.session.hook("prompt", createPromptHandler(...))` — **the host fires this
  hook on every prompt; the plugin's own once-mark is the only dedup** (there is no host-side
  "first prompt only" filter — the header records the same: "the command path mints a fresh messageID
  per attempt, so server-side id-dedup never protects the prompt hook — the guard keys the sessionID").
- `BOARD_COORD_AGENTS = [agent-board-coord, agent-board-coord-local, agent-board-coord-pr,
  agent-board-dispatch]`; `isBoardCoordAgent` filters (agent from the event, else `ctx.session.get`).
  The dispatcher "never claims and rides the roster only (AC4)".
- **The once-mark (the guard that is supposed to stop re-injection)** — `createPromptHandler`:
  ```
  const seen = await readOnce(sessionID);
  if (seen !== undefined && Date.now() - seen < ONCE_TTL_MS) return;
  ```
  with `readOnce` reading `once/<sessionID>` from ctx.storage:
  `return typeof value === "number" ? value : undefined;` (catch → fall through to the per-process
  `attempted` Map), and `writeOnce` writing the epoch-ms stamp to **both** the map and storage;
  `ONCE_TTL_MS = 6 h` ("a plan-approval pause can hold one session for hours, while a mark left by a
  dead session must expire").
- The canonical-header scan (`CANONICAL_HEADER = "Board context (collected"`): a prompt already
  carrying a pasted block (the `/wekan-board-context` collector path) or the refresh command's reply
  is marked WITHOUT injecting; a stale mark (≥ 6 h) is removed and re-stamped (re-inject by design for
  abandoned sessions).
- Injection is append-only: `event.prompt.text = text + "\n\n" + block`; the fetch races
  `withinBudget(..., FETCH_TIMEOUT_MS = 8000, "prompt board context")`; a missed/bad block degrades to
  an **untouched prompt + one stderr line** — "a prompt hook that throws or hangs blocks admission
  outright … the scheduled run would die at dispatch" (never-throw is a correctness requirement).
- **`bindOnceMarkStorage`** requires `storage.get/set/remove` to be functions, else the setup logs
  `"[board-context] degraded: no usable ctx.storage — the once-mark keeps its per-process in-memory
  fallback"`.
- **Why a follow-up message re-receives the block (the guard that is NOT firing)** — three code-grounded
  failure modes:
  1. **Storage round-trip shape**: `readOnce` only accepts `typeof value === "number"`. If the durable
     store answers the stamp as a string/object (or the `get` call throws — the catch falls to the
     per-process map), the mark is invisible; in the SAME process the in-memory map rescues, but
  2. **two live server processes** (the header's own recorded hazard: "two live opencode server
     processes load this plugin independently and share only the durable store, so an in-memory guard
     sees only the prompts its own process served and re-injects on a follow-up riding the other" — the
     shared dev server serves main-checkout sessions while a worktree-rooted session runs on another
     server/instance);
  3. **TTL expiry** (≥ 6 h) re-stamps and re-injects by design.
  The "every follow-up message" symptom = mode 1/2 (the mark never visible across the prompts'
  processes). Which one fires on the live host is not provable from this repo — the setup degrade line
  (mode 1 entry) and the two-process topology are the two things a live log check can settle (OQ-1).
- `resolveBoardContext` — the six-leg resolution (the `preload` leg): `list_boards` (title `AI-Dev`) →
  `get_board` (labels + board key, the card_number prefix source) → `list_swimlanes` (title `In
  Process`) → `list_lists` filtered **client-side** by swimlane id (server-side title filter would
  answer an empty grouping on a renamed swimlane; "every list rendering cards: [] reads as an empty
  board — the throw here degrades to no block instead") → `list_custom_fields` (keyed on `name`) →
  `preload_board` asked lean `{board_id, with_checklists: false}` with exactly ONE build-tolerant
  board_id-only retry (a pre-bump build answers the unknown lean arg with a deterministic validation
  error, measured cf-123 R2 D14; the fence never renders checklist state). `formatBlock` mirrors the
  "Board context block schema" section of `skills/wekan-mcp/SKILL.md` byte-for-byte (one strict YAML
  document; `card_number` quoted in both derive states; footer `#` comment lines; the no-board-key
  degrade footnote). Unknown titles throw → untouched prompt.
- URL discovery `resolveMcpUrl`: `ctx.mcp.list()` first, then parsing `.opencode/opencode.jsonc`
  (locate the quoted `"dev-boards"` key, take the first `"url"` after it); null = no URL → degrade.
  dev-boards authenticates server-side (login-mint) — the plugin handles no credentials.
- `DEFAULT_ENABLED = true` with the live-fire proof citation in the header (LF1/LF2/LF4/LF5/LF6/LF7
  legs, 2026-10-29 worktree probes; LF6 pinned degraded pre-merge).

### 2.2 The claim-time card-details leg (cf-106 C07)
- Registered: `ctx.tool.hook("execute.after", …)` — **execute.after, never before** ("blocking a claim
  call would take the lock down with the card read (pipeline-locks C01 fact 2)").
- `createClaimHandler` predicate: tool in `CLAIM_TOOLS = {pipeline_claim, tools.pipeline_claim}` (both
  spellings — flat registry vs Code Mode); board-coord agent filter; **only amendable when the claim
  SUCCEEDED** — `claimAnswer`: refusals are `{ok:false, reason}` and the no-card walk is
  `{ok:true, reason:"no_work"}` (pipeline-locks), so `answer.ok !== true || answer.reason !== undefined`
  → untouched; once per claimed card via the in-process `claimed` Set (not durable — a server restart or
  a second process re-reads the card: "a re-read would pay the fan-out again for the same bytes" is the
  within-run law only).
- Fetch: `get_card_details {board_id (cached per process via `resolveBoardId` — "re-resolving it per
  claim pays a list_boards round trip for a value that does not move"), card_id}` under
  `CARD_DETAILS_BUDGET_MS = 12000` (deliberately NOT the 8 s admission budget — "that 8 s constant is a
  ruling about prompt-ADMISSION latency, and this leg runs after admission … breaching it may only
  cost the block — never the claim answer, which is the lock-identity channel (D28)").
- `formatCardBlock(payload, {collectedAt?})`: one line per field (`card_details:`, `id:`, `card_number:`,
  `title:`, `description:`, `list_id:`, `swimlane_id:`, `archived:`, `sort:`, `parent_id:`,
  `label_ids:`, `labels:`, `custom_fields:`, `slug_stack:`, `current_slug:`, `checklists:`, per-checklist
  `item: … [x| ]` rows, `dependencies:`, per-dependency rows, `collected: <stamp>, from get_card_details`)
  — mirrors the "Card details block" section of `skills/wekan-mcp/SKILL.md`; `oneLine` collapses
  multi-line/padded values; `collectedAt` is a per-payload WeakMap stamp so re-rendering the same read
  is byte-stable.
- Delivery `amendAnswer`: the amended answer goes into **whichever field the original answer already
  sits in** (content string / content array / output / fallback) — "which field the host renders for a
  tool answer is not settled on v2.1.4".
- The offline suites cannot prove the hook fires for a Code Mode `execute` of another plugin's tool —
  "probe leg LF10 proves the deployed tool exists, and the first real board-coord claim proves the
  hook; the degrade path (no block, one stderr line) is what an unreachable hook costs".

### 2.3 The `/reload-board-context` command
`buildReloadCommand` — a manual refresh of the once-per-session block: re-runs the same six-leg
resolve under the 8 s budget, posts the block (or the failure text) into the session via
`ctx.session.prompt` on the invocation's own envelope; the executor never marks — a failed fetch leaves
the attempt intact, a successful reply is marked by the hook's header scan.

## 3. `question-notify` (`.opencode/plugin/question-notify/index.ts`, 658 lines) — **currently DISABLED**

**Current state: owner-disabled 2026-11-21 via `.opencode/opencode.jsonc: "plugins":
["-local.question-notify"]`** (the `-` prefix removes it by declared id; the source file stays
untouched, the config entry is the whole toggle). Re-enabling = removing that one entry. The
reconcile design's dependence on unanswered-question + finished-session detection therefore currently
rests on a disabled plugin.

### 3.1 The three detection legs
1. **Pending question**: `ctx.tool.hook("execute.before")` on `tool === "question"` →
   `handleQuestion` (exported seam, cf-106 hook-arm law): filter order exactly — tool filter, agent
   from the event with session-record fallback, `agent-` prefix, burst cooldown (`allowPush`,
   `COOLDOWN_MS = 15000`, keyed on sessionID alone, shared with the approval path), consume-once
   claim `claim/question:<callID>` (a question event with no call id dedups to nothing — loud), push.
2. **Session finished / failed**: event stream (`ctx.event.subscribe`), `FINISHED_EVENT =
   "session.execution.succeeded"` / `CRASH_EVENT = "session.execution.failed"` → `handleLifecycle`
   (exported seam): dual read (payload under `data` or flat), top-level filter `isTopLevel`
   (`!info.parentID` — a missing session record is unknown topology, not top-level: suppress on
   doubt); finished push has exactly ONE suppression (the no-op marker, below) and runs BEFORE
   getMessages and before any push attempt ("the suppression consumes nothing"); excerpt = newest
   assistant `content` part text (`lastAssistantExcerpt` — top-level `text` on user/system records
   would echo the user's own prompt back); dedup claim `claim/finished:<sessionID>:<turnID>` (fallback
   identity = last assistant message id) / `claim/crash:<sessionID>:<evID>` — **a crash push is never
   suppressed**; dedup requires a real event identity, "every delivery stays loud — a muted crash
   without proof of a sibling push is the one failure this leg never ships".
3. **Approval pending 15 s**: `PERMISSION_ASK_EVENT = "permission.asked"` (published only when the
   ruleset effect resolves to `ask`, exactly once per request id) arms a per-request-id timer
   (`PENDING_NOTIFY_MS = 15000`, overridable per setup via `OPENCODE_NOTIFY_PENDING_MS` — "read the
   pending window per setup, never at module load"); `PERMISSION_REPLY_EVENT = "permission.replied"`
   for the request id (field name `requestID` vs `id` — "the field names stay unharmonized on
   purpose") cancels the pending push whatever its reply value (every server resolution path emits
   it); **pending-only** — no push on arrival (the arrival-time push rang clients that had already
   answered, the live bug behind C03); the cooldown gate + claim run in the timer callback at the
   actual push attempt ("a cancelled ask consumes no stamp"). No topology filter — "every session that
   blocks on an approval needs a human, whatever its parentage".

### 3.2 Session metadata reads (what the reconcile design leans on)
- `deps.getSession(sessionID)` = `ctx.session.get({ sessionID })` → reads `info.parentID` (top-level
  filter), `info.agent` (titles), `info.metadata` — **`noWorkSuppressed` dual-reads bare or
  `{data: …}` envelope**:
  ```
  const metadata = info?.metadata ?? info?.data?.metadata;
  if (!metadata || typeof metadata !== "object") return false;
  if (!metadata.openchamber || metadata.openchamber.kind !== "scheduled") return false;
  const marker = metadata.pipelineNoop;
  return typeof marker === "object" && marker !== null && typeof marker.reason === "string" &&
         marker.reason !== "";
  ```
  i.e. the **no-op/archive predicate is the conjunction**: `metadata.openchamber.kind === "scheduled"`
  AND `metadata.pipelineNoop.reason` a non-empty string. The writer's vocabulary is the five (six
  after the cf-126 re-pin: + `delegated`) marked-exit reason values `no-cards`, `no-claimable-cards`,
  `gate-skip`, `gate-live`, `board-check-unavailable`, `delegated` — **the reader stays
  token-agnostic** (any non-empty string reason); well-formedness is the non-empty `reason` alone
  (`at` is the writer's audit stamp, never a gate, OQ2); any other shape returns false so the caller
  pushes (fail-loud — "a mis-marked manual run still alerts and the unsafe 'missed real alert'
  direction is confined to scheduled ticks").
- `deps.getMessages(sessionID)` = `ctx.session.context({ sessionID })` for the excerpt.
- The writer authority is the boards skill's "No-op marker" subsection (both no-op exits cite it;
  cf-90 C03: both no-op ends PATCH the session `{"archived": true}` after the marker write —
  rename → get → merge → patch whole-metadata; PATCH failure still ends cleanly).

### 3.3 Push mechanics
- `sendHANotify` → raw MCP JSON-RPC to `admin-global-homeassistant` (`call_service`,
  `notify.mobile_app_pixel_6`, title + `truncate`d message, `MAX_MESSAGE = 240` — the same ceiling
  pipeline-locks' reap texts share); URL discovery `haMcpUrl` — leg 1 `ctx.mcp.transform` editor.get
  (the only ctx view whose entries carry full server configs; a fresh register/dispose per call keeps
  fleet config edits live without a restart), leg 2 `ctx.mcp.list()` compat scan; never rejects.
- Fleet-wide dedup: `claimOnce` over ctx.storage (kv namespace keyed by plugin id alone — "visible
  fleet-wide"; every degrade path returns true — "the claim mutes copies, never the alert itself";
  `CLAIM_TTL_MS = 10 min`; `sweepExpiredClaims` on load; the get→set non-atomicity is "an improvement
  bound, not a bug").
- The loop must not be awaited in setup; each event dispatched fire-and-forget; the cleanup aborts the
  subscription and disarms pending timers.

## 4. `aislop-gate` (`.opencode/plugin/aislop-gate/index.ts`, 78 lines) — the install-pattern precedent

- Shape: plain `{ id: "local.aislop-gate", async setup(ctx) }` default export (NOT `Plugin.define` —
  "so there is no runtime @opencode/plugin resolution dependency"); single `index.ts` under
  `.opencode/plugin/aislop-gate/`; auto-discovered like the others; no separate config file — all
  tuning is in-file constants: `AISLOP_VERSION = "0.20.0"` (pinned via `npx --yes`), `EDIT_TOOLS =
  {edit, write, multiedit, patch, apply_patch}`, `CODE` extension regex, `DEBOUNCE_MS = 1500`,
  `MAX_CHARS = 4000`, 120 s exec timeout, 8 MiB maxBuffer.
- Behavior: `ctx.tool.hook("execute.after")` on completed edit/write-class tools with a code-extension
  path → runs `npx --yes aislop@<pin> scan --changes` in `ctx.location.directory` → appends
  `appendText(event.result, "aislop findings (changed files). …")` into whichever result field
  exists (content string / content array / output / fallback — the same field-shape tolerance as
  board-context's `amendAnswer`); debounce + dedupe on the identical report; aislop missing or
  crashed → silent, "never break the edit".
- CI parity: the version pin must resolve to ONE value across the plugin constant and
  `.github/workflows/aislop.yaml` (`npx --yes aislop@0.20.0 ci --changes --base origin/main --human`),
  machine-guarded by `tests/opencode/aislop-pin-parity.test.ts`; `.aislop/config.yml` is the gate
  config. **card-runner follows the same install pattern** (single index.ts, plain export, discovery,
  no config file).
- Accepted debt note: the cf-124 final review record (this host's log) shows `aislop ci --changes
  --base main` = 1 warning = pre-existing `complexity/file-too-large` on the 2767-line pipeline-locks
  plugin (accepted as a shipped-file fact; warnings do not gate CI — errors + the score floor do).
  A merged pipeline-locks + board-context replacement file will very likely emit the same warning
  class.

## 5. Tests / validation that already exist

### 5.1 The offline node suite (the primary pin family)
- **Runner: `node --test tests/opencode/*.test.ts` from the repo root** (node v26.5.0 on this
  worktree; type-strips the `.ts` directly — "no build step, no npm deps, no network", per the
  card-details test header; no package.json at repo root). Measured 2026-11-23 on this worktree:
  **tests 393, pass 393, fail 0** (~8 s). `tests/cf96-tz/surface.sh` records the 2026-11-01 baseline
  ("233 pass") — the suite has grown since; per-file runs are the canonical command
  (`node --test tests/opencode/<file>.test.ts`, also used as a validation command by
  `tests/agent-perms/surface.sh: A15`).
- The ten files:
  - `pipeline-locks-core.test.ts` (cf-76 C03: set derivation D17, lock store, all-or-nothing claim D18,
    release/status/atomic primitives, lock-root chain D10, degrade-never-throw setup shape)
  - `pipeline-locks-engine.test.ts` (cf-76 C04: 30 s throttle, set-wide lock-lost D18, strict guard
    D16, child mapping, idle-stale/execution lifecycle D12/D20, cleanup — offline via injected deps +
    fake clock/timers)
  - `pipeline-locks-reap.test.ts` (cf-76 C05: stale detection `max(heartbeatAt, mtime)` 2 h, mkdir
    guard, race restore, board move + comment + HA alert, timeouts.jsonl degrade, reap/status command
    routing, credential-free constants)
  - `pipeline-locks-tick.test.ts` (cf-76 C06: /pipeline-tick reap-before-prompt + worker prompt pins,
    `.pipeline/config.json` loader D8, loop-file bytes, TICK_PROMPT parity; AC 6 + live smoke are the
    human/deferred gate, "deliberately NOT encoded here")
  - `board-context.test.ts` (cf-75 C04 block contract + cf-123 C01 strict-YAML fence + C03 durable
    once-mark + refresh command; formatBlock/resolveBoardContext/createPromptHandler/isBoardCoordAgent/
    resolveMcpUrl/unwrapToolResult/parseSseData + `FETCH_TIMEOUT_MS`/`DEFAULT_ENABLED`; "exactly one
    prompt hook and the one /reload-board-context command")
  - `card-details.test.ts` (cf-106 C07: hook predicate matrix, prompt-hook path untouched, formatter
    doc-parity, degrade law)
  - `question-notify.test.ts` (lifecycle seam battery + T9/T10 no-work suppression matrix + T12 claim
    gates + T13 real-setup two-instance fan-out + **T15 creep-back guard: question-notify carries no
    compaction leg**)
  - `permission-ask-notify.test.ts` (C03 pending-only approval push contract)
  - `ha-mcp-url.test.ts` (H1–H9 URL-discovery battery — the silent-pushes incident fix)
  - `aislop-pin-parity.test.ts` (pin parity across the plugin and CI workflow homes)

### 5.2 Shell contract suites (offline text pins over the trees)
- `tests/wekan-mcp/board-context.sh` — t1..t6 (agent-board permissions, collector command,
  boards-skill consumer rule, hourly-gate negative; t6 runs nested suites as id-subsets) —
  `bash tests/wekan-mcp/board-context.sh [t1 t5 …]`.
- `tests/wekan-mcp/card-details.sh` — t1..t5 (tool existence + read-only, exact response key set,
  slug-stack parser parity, doc home, fail-the-call ruling).
- `tests/noop-marker/surface.sh` — N1..N8 (N1 pins question-notify's conjunction reader + suppression
  audit line + exported seam; N2 the boards-skill writer authority; **N3 single-home grep counts —
  `pipelineNoop` exists in the skill pair + the plugin ONLY, no third normative copy**; N4 scheduler
  docs truth incl. the two-loop-file shape; N5 RESULT posture; N6 archive-on-no-cards exit; N7
  five/six-token closure + plugin comment parity + gate script marker-blind; N8 dispatcher loop file
  shape). `bash tests/noop-marker/surface.sh [N2 …]`.
- `tests/cf96-lifecycle/surface.sh` — pins the boards skill + question-notify/permission-ask-notify
  test names (t1..t7).
- `tests/cf96-tz/surface.sh` — pins the single `localIso` implementation in pipeline-locks + the
  board-context import (t1..t4, incl. the `.rulesync/commands/wekan-board-context.md` stamp wording).
- `tests/cf106-noop/readback.md` — the no-op marker contract readback.
- `tests/agent-perms/surface.sh: A15` — the pipeline-locks surface (plugin exists → parity greps
  across plugin / boards skill / subagent sources) + runs `node --test tests/opencode/
  pipeline-locks-core.test.ts` as a validation command.
- `tests/pipeline-models/surface.sh` — pins the loop-file runner model literal + the tick test.
- `tests/agent-board-coord/{gate.sh,rulesync-surface.sh,agents-md.sh}` — scope-admit lists that
  **name the plugin directories** (`.opencode/plugin/{pipeline-locks,board-context,question-notify,
  aislop-gate}/*`) — a `card-runner` replacement must be admitted into these lists (the cf-124/cf-143
  merge-round union-line machinery in `gate.sh` shows the admit-line shape).

### 5.3 Live-fire runbooks (not CI; agent- or user-owned)
- `scripts/board-preload-probe.sh` — the AGENT-OWNED live-fire capability for the board-context
  prefetch (invoked ONLY argument-bearing, `all` or leg names); legs LF1 (block read back in the
  first prompt, zero structural dev-boards reads), LF2 (plain-text loop door fires the hook), LF4
  (no-op marker recipe live, sentinel intact), LF5 (conjunction keeps alerting, user confirms the
  phone receipt), LF6 (pinned degraded pre-merge), LF7 (no 8 s budget breach in instance logs).
- `scripts/agent-board-coord-gate.sh` — the scheduled-launch gate: counts the four
  scheduled-surface agent names (alias + -local/-pr + dispatcher) via the local `opencode api` CLI
  with the ACTIVE-ONLY freshness rule (no heartbeat machinery, the OQ2 ruling); GATE: RUN
  short-circuits the board side.
- `.agents/loops/pipeline-dispatch.md` — the dispatcher loop body (the plain-text equivalent of
  `TICK_PROMPT`, D30): check for a live `agent-board-dispatch` + `metadata.pipelineDispatcher`
  session → proxy-forward the tick text and end with the `delegated` marker + archived exit, or
  self-mark and run exactly one Parallel pipeline loops iteration; frontmatter: hourly `0 * * * *`,
  enabled true, model `gpu-ai/qwen3.8-flash-next-strata-q4` (owner-ruled runner literal).

### 5.4 CI
- `.github/workflows/aislop.yaml` is the ONLY workflow: `npx --yes aislop@0.20.0 ci --changes --base
  origin/main --human` on ubuntu-26.04 / node 24 (PR-gated; per-touched-file score floor +
  error-severity rule; the aislop-pin-parity test guards the pin). No Forgejo or GitHub workflow runs
  the plugin test suites — the plan Commands section (per ticket) is their runner.

### 5.5 Other surfaces that reference the plugins (re-pin / update targets for card-runner)
- `.rulesync/skills/boards/SKILL.md` + the generated `.opencode/skills/boards/SKILL.md` mirror — the
  no-op marker subsection (writer authority), the `pipeline_*` tool posture (Code-Mode only), the
  co-tenancy / `shared` claim posture, the lock-lost stop sentence, the Dispatcher section (wake
  contract).
- `.rulesync/subagents/agent-board-coord.md`, `agent-board-coord-local.md`,
  `agent-board-coord-pr.md`, `agent-board-dispatch.md` and `.rulesync/rules/overview.md` (→
  AGENTS.md) — reference the `pipeline_*` tools and the plugin behavior (AGENTS.md "Pipeline worker
  iterations" + "Compaction & fresh-start" sections; the `pipeline-conventions` skill's "Compaction &
  fresh-start" section names the `pipeline-locks` hook as the compaction mechanism's home).
- `tests/cf90-ledger/readback-runbook.md` — cites the board-context prefetch.

## 6. Grounded facts / gotchas

### What a `card-runner` replacement must preserve
1. **Lock semantics**: O_EXCL all-or-nothing sorted-set acquisition with rollback; `occupied` refusal
   naming the live foreign holders (the emptiness rule as an engine answer, not a status guess);
   `shared: true` as a per-claim human override (never a deployment setting) appending holder rows;
   `already_held` (one card per iteration); card-id takeover claims tagged `after_reap` only with a
   `.reaped/` evidence record; the stop marker clearing only on the session's OWN new claim (no
   self-reclaim).
2. **Lock file contract**: v2 record shape (holders list with per-holder stamps; file-level last-
   writer-wins stamps; `pipelineSet`; `state`), `sanitizePipelineKey` naming, `default` fallback,
   atomic tmp+rename + mtime write, canonical-root `.pipeline/` layout, older-schema tolerance on
   read.
3. **Heartbeat**: activity-only beats (idle roots age out — the staleness mechanism the reaper
   depends on), per-(pipeline, session) throttling, set-wide verify-before-beat, the strict
   `LOCK_LOST_STOP` guard on edit/write/bash, the stop text verbatim (suites pin the literal), the
   sanctioned single-question resume.
4. **Reaper**: 2 h default stale window + `max(heartbeatAt, mtime)` formula, holder-granularity
   pruning, the rename-as-atomic-claim + race-restore + `reapedAt` forensics under `.reaped/`,
   per-card Timeout board leg (swimlane-echo resolution), the `timeouts.jsonl` degrade row (with the
   takeover hint), the HA alert (admin tier, fire-and-forget), the `reaper.lock` cross-process guard,
   claim-time pre-reap, `meta/lastReap`.
5. **Dispatcher wake**: the dual-leg dispatcher tracking (exact agent id AND the `pipelineDispatcher`
   metadata marker), the wake on every non-empty release (outcome-blind, self-healing on failure),
   and the no-op/archive exit contract (`pipelineNoop.reason` non-empty + `openchamber.kind ===
   "scheduled"` conjunction, six-token writer vocabulary, token-agnostic reader, archived PATCH).
6. **Compaction contract**: the one process-wide `session.hook("compaction")` (pointer-shaped summary
   rewrite + keyed `pipeline-handoff` note; the v2.3.0 `entry.put` takes `{sessionID, key, value}` —
   `{key,text}` throws), the `session.compaction.failed` record-only listener (no dedupe — the repeat
   is the wedge signal), and the creep-back guard (whatever file ends up owning the compaction leg,
   question-notify's T15 pin must point at it correctly).
7. **The never-throw degrade law**: every arm degrades to "untouched payload + one stderr line"; a
   prompt hook that throws/hangs blocks admission outright (the scheduled run dies at dispatch); setup
   bodies in try/catch; event loops never awaited inline; all timers disarmed on unload.
8. **The once-per-session context injection** (board-context's whole purpose): first-prompt board
   block + claim-time card block + manual refresh — with the guard fixed so follow-ups do not
   re-receive the block (see below).
9. **`localIso` as the single stamp formatter** (imported by board-context; pinned by cf96-tz) —
   card-runner keeps one implementation.
10. **Storage/audit continuity**: the `claim/*`/`child/*`/`once/*`/`claim/*`-dedup kv rows (plugin-id-
    keyed namespace — a plugin rename changes the namespace; decide whether card-runner keeps the
    `local.pipeline-locks`-style id or migrates), the `.pipeline/events.log` JSONL vocabulary, and the
    Code-Mode-only tool reachability (flat names, `tools.<name>` call form, the description text that
    tells the model so).

### What is provably broken / degraded today (owner symptoms, code-grounded)
1. **Symptom (a) — the board block re-injects on follow-up messages**: the only guard is
   `readOnce` (`typeof value === "number"` over the durable `once/<sessionID>` mark) + `ONCE_TTL_MS`;
   when the storage round-trip is non-numeric (or the storage binding degrades to the per-process
   `attempted` map — setup logs the degrade line), or across two live server processes (the header's
   own recorded hazard), the guard does not fire and EVERY prompt re-runs the fetch and re-appends
   the block. The 6 h TTL expiry is a third, by-design re-injection. Which leg fires on the live
   host is open (OQ-1).
2. **Symptom (b) — locks "stomp on each other" / repeated sharing questions**: every card without a
   `Pipeline:` label derives the single `default` key, so all unlabeled cards serialize on ONE lock
   file; the second claimant gets `reason:"occupied"` and the worker must ask the human for the
   `shared: true` override — repeatedly. File-level last-writer-wins stamps (co-tenant beats
   overwriting the file stamp) are the accepted "stomp" surface; a stopped (unreleased) session holds
   the key for up to the 2 h stale window before the reaper frees it, moves the card to Timeout and
   rings the phone. The release wake (outcome-blind, per release) compounds the churn: each release
   immediately re-wakes the dispatcher into the walk that meets the next contention.
3. **question-notify is disabled** (`"plugins": ["-local.question-notify"]`, owner-disabled
   2026-11-21): the finished/crash/alert legs the reconcile design leans on are not running; the
   `.pipeline` reap alert is the only HA push still live (it is gated only by `haNotify` and "the
   marker never reaches it").
4. **Duplicated, non-shared transport**: the raw-MCP JSON-RPC mechanics are copy-pasted verbatim
   between board-context and pipeline-locks (the "duplicated, never imported" precedent) — card-runner
   is the first plugin to own both legs and can de-duplicate them into one module.
5. **Non-durable claim-time dedup**: the card-details leg's once-per-card `claimed` Set is
   per-process in-memory only — a restart or a second process re-pays the fan-out.
6. **Accepted debt**: the 2767-line pipeline-locks file carries a standing `complexity/file-too-large`
   aislop warning (CF-124 final review record) — a merged replacement inherits the risk; keep the file
   under the complexity bar or accept the warning as a recorded fact.
7. **Unverified delivery legs** (recorded, not proven offline): whether v2.1.4 fires tool hooks for a
   Code Mode `execute` of another plugin's tool (the claim-time leg); which result field the host
   renders (both plugins ship field-shape-tolerant writers); the live v2.3.0 compaction envelope
   (`{sessionID, agent, system[], messages, model, tools, options}`). A card-runner design should
   re-verify these on the pinned runtime before shipping the legs ON.

### Open questions
- **OQ-1 (live verification, not web research)**: which board-context degrade leg fires on the
  OpenChamber host — the setup degrade line ("degraded: no usable ctx.storage") vs a numeric
  round-trip miss vs the two-process fallback. Settle with `grep -iE "board-context.*(degrad|once)"
  <host log>` on the host that serves the live board-coord sessions. (The log on THIS host shows no
  degrade lines — but the live runs execute elsewhere.)
- **OQ-2 (design input for the plan)**: does the owner want `card-runner` to KEEP the `pipeline_*`
  tool names (all subagent sources, the boards skill, AGENTS.md and the A15 parity greps reference
  them) or rename? Keeping them minimizes the re-pin blast radius (the subagent/skill/AGENTS.md pin
  families stay green); renaming is a repo-wide re-pin.
- **OQ-3 (design input)**: whether the `default`-pipeline collapse (root of symptom (b)) is fixed by
  labeling cards `Pipeline:`-individually (owner-side board work) or by card-scoped locks in
  card-runner (code). The lock engine itself refuses correctly; the collision is a key-derivation
  consequence, not an engine bug.
- No web/upstream research need identified: the runtime-behavior questions (OQ-1, the unverified
  delivery legs) are live probes, and the v2.1.4/v2.3.0 facts are already recorded in-repo
  (plugin headers + live-fire legs). `Needs research: no`.
