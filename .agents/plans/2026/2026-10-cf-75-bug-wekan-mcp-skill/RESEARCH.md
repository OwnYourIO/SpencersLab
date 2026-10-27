# RESEARCH — cf-75-bug-wekan-mcp-skill (post-plan round, C04 focus)

Run by agent-research on 2026-10-27 (STORM method; perspectives: V2-docs
reader, upstream-source forensicist at tag v2.1.4, scheduler-integration
engineer reading the installed `@openchamber/web` 2.5.2, cross-lab pattern
analyst, reliability skeptic). Every claim carries a numbered source from the
Sources section; `VERIFIED-SOURCE` = upstream file read at the tag matching
the installed CLI (`opencode --version` → **v2.1.4**), `DOC` = official V2 doc
page read, `LOCAL` = machine-installed artifact read, `WEB` = external
source. No storm-runs/ intermediates were written (launch constraint: only
RESEARCH.md may be created).

## TLDR

1. **The scheduled launch path runs the `prompt` hook.** Source-proven chain,
   tag v2.1.4: OpenChamber scheduled task → `client.session.command` (slash
   prompts) → `POST /api/session/{id}/command` → `SessionCommand.execute` →
   config-command `execute` (template + shell expansion, `switchAgent`, then
   `ctx.session.prompt`) → `Session.prompt` → `SessionPrompt.prepare` →
   `hooks.trigger("session","prompt")` → attachment/skill resolution → durable
   inbox admission → `execution.wake`. Same admission for interactive and API
   prompts; synthetic/shell/compaction/move submissions are the documented
   non-running set.
2. **Async prompt hooks delay admission and cannot race the first model
   turn** (wake happens strictly after admit), but a hook that **throws or
   hangs blocks admission entirely** — "If preparation fails or is
   interrupted, OpenCode does not admit the prompt." never-throw + a bounded
   fetch timeout are therefore mandatory, not cosmetic.
3. **`instructions.entry.put` is session-lifetime** (DB table keyed per
   session, rendered as `<context key>` blocks, announced at the next step
   boundary, prompt-cache preserving); **not proven to reach subagents** and
   not part of the persisted first user message, so AC6's context-readback
   proof only works with the prompt hook.
4. Residual UNPROVEN legs are deployment-level, not platform-level: the live
   E2E hourly run, and **location plugin discovery** — the hourly run's
   location is the main checkout, so the plugin is loaded there only after
   landing (C04 live-fire nuance below).
5. Verdict: C04's prompt-hook design is sound and docs+source-proven;
   live-fire stays as acceptance gate, now with sharpened failure semantics
   and a per-turn `context`-hook / instruction-entry option as the
   compaction-durability follow-up (degrade-safe, default-OFF fallback
   unchanged).

## Proven / unproven matrix (feeds C04 AC6 wording)

| # | Admission path | Hook runs? | Grade | Evidence |
|---|---|---|---|---|
| a | Interactive chat prompt (TUI/web composer → `session.prompt`) | **yes** | PROVEN (docs) | DOC [1]: hook "intercepts incoming user prompts before attachment and skill resolution and durable inbox admission"; exclusions are synthetic/shell/compaction/move only. Route `POST /api/session/{id}/prompt` "Send message" [3] hits the same `Session.prompt` code [6]. |
| b | Command-expanded prompt (`/pipeline-boards-hourly` typed or submitted) | **yes** | PROVEN (docs + source) | DOC [2]: "Commands expand arguments and shell blocks before submitting a durable user prompt"; frontmatter `agent` is applied "before submitting the prompt". VERIFIED-SOURCE [8][9]: config-command `execute` ends in `ctx.session.prompt({...input.prompt, sessionID, text, delivery})`; DOC [1]: "Commands that submit through `session.prompt` run the hook." |
| c | API/scheduled submission via `POST /api/session/{id}/command` (OpenChamber slash path) | **yes** | PROVEN (source chain; one leg UNPROVEN live) | LOCAL [12]: slash-style task prompt → `client.session.command({sessionID, name, text: arguments})` (fall-back: plain `client.session.prompt`). VERIFIED-SOURCE [9] route → `SessionCommand.execute` → definition `execute` → `ctx.session.prompt` → hooks [5][6][7]. UNPROVEN leg: this lab's live task config + location plugin load at run time (see Implications 4). |
| c' | API/scheduled plain-text submission via `POST /api/session/{id}/prompt` | **yes** | PROVEN (code path identity) | Same `Session.prompt` function serves the route [3][6]; the OpenChamber goal-briefing preceding it is `session.synthetic` which does **not** run hooks [1][12] — C04's once-guard must not treat the synthetic as "first prompt seen". |
| d | `session.command` with `subagent: true` command | child gets prompt via `sessions.prompt` → hook runs on the **child** sessionID | SOURCE-VERIFIED, not doc-stated | [8]: subagent branch creates child and submits with the child's sessionID. C04's agent filter (session lookup → the three board-coord ids) decides what matters here; hourly command has no `subagent` field. |
| — | Hook is awaited before admission, ordering across plugins | **yes, sequential** | PROVEN (docs + source) | [1]: "Hooks run in registration order after the session's location plugins are ready"; "Multiple plugins … later hooks see changes made by earlier hooks." [7]: trigger loops callbacks in registration order, `yield* result` per entry — callbacks may be async (signature `=> Promise<void> | void` [1]); prompt hooks have no providerID scoping (`options?: never`) [1][7]. |
| — | No race with first model turn | **yes** | PROVEN (source) | [6]: `wake(sessionID)` runs only after `admit`, which runs only after `prepare` (hooks + attachment/skill resolution). The MCP round-trip delays the admission HTTP response; it cannot interleave with the model loop. |
| — | Retries / double-runs | **possible** → guard required | PROVEN (docs) + source nuance | [1]: "Retrying an ID already pending or delivered returns the original admission without rerunning hooks. Concurrent submissions can run hooks more than once, but only the first successful admission wins." [6]: a fresh `messageID` is minted per call when the body carries no `id` — and the command/config path mints fresh ids [8], so the id-dedup does NOT protect the command path: the once-per-session flag + the `Board context (collected` header idempotence check are both load-bearing. |
| — | Failure of a hook blocks admission | **yes** | PROVEN (docs) + source-consistent | [1]: "If preparation fails or is interrupted, OpenCode does not admit the prompt." [7]: session-hook failure channel is typed `never` ("Only tool execute.before may fail") — a throwing Promise-plugin hook is an untyped defect escaping `prepare`, so admission never happens. Treat C04's try/catch-everything posture as a correctness requirement, not a style rule. |
| — | Edits persist as canonical user input | **yes** | PROVEN (docs) | [1]: "Edits become the canonical persisted user input." → AC6 readback via `GET /api/session/{id}/context` [3] is the right proof primitive (matches C04's pinned command). |
| — | `context` hook as per-turn fallback | reaches every agent-loop model call incl. tool continuations; event carries `sessionID` + `agent` | PROVEN (docs); subagent-loop coverage source-consistent but not doc-stated | [1] (model-request hooks), [5][6]. Caveat [1]: "Changes affect only the outgoing model call, not persisted history" → invisible to AC6 readback. |

## Key findings

### F1 — Exact V2 prompt-hook semantics (Q1)

- Event shape (VERIFIED-SOURCE [10] `packages/plugin/src/promise/session.ts`
  + DOC [1]): `{ readonly sessionID, readonly messageID, prompt:
  DeepMutable<Prompt>, metadata?, delivery }`. **No `agent` field** — the
  trigger predicate must be `ctx.session.get({sessionID})` (question-notify's
  dual-read pattern), which is exactly what chunks/C04.md planned.
- `prompt` contains `text`, `files`, `agents` mentions, `skills`; hook-added
  files/skills follow normal resolution; when rewriting `text`, stale
  attachment/`mention` offsets must be updated or removed [1]. Appending
  after the expanded hourly-gate text keeps existing offsets valid (append
  only) — note it.
- `delivery` defaults `"steer"` and is hook-changeable to `"queue"`; "Agent
  mentions do not switch the session's active agent"; session/message ids are
  readonly; "Provider scoping is unavailable because model resolution happens
  after admission" [1].
- Not an exactly-once side-effect boundary (docs) — see matrix row "Retries".
  No typed rejection API: a hook cannot cleanly veto admission; the only
  veto-ish lever is failing preparation, which drops the prompt — so
  degrade-silent (leave prompt untouched + stderr) is the *only* correct
  failure policy for C04 [1][7].
- Async timing: callbacks may return Promises; the trigger awaits each in
  order [1][7]. Admission (and the first model turn) strictly follows, so an
  8 s MCP round-trip delays the client's `prompt`/`command` HTTP response —
  bounded by `AbortSignal.timeout` per AC4; OpenChamber awaits the dispatch
  call itself before bookkeeping (LOCAL [12]) and wraps runs in a 30-min
  watchdog, so a bounded delay is operationally safe.

### F2 — Command/schedule path runs the hook end-to-end (Q1, plan Risk #2)

The disambiguation of "Commands that submit through `session.prompt` run the
hook" was resolved in upstream source at tag v2.1.4 (installed CLI version):

1. `POST /api/session/{sessionID}/command` — "Execute a slash command
   callback immediately." (OpenAPI [4]; route inventory [3]).
2. → `SessionCommand.execute` (`packages/core/src/session/command.ts` [9]):
   awaits plugin activation (`Plugin.awaitActivation` — hooks are registered
   before any command executes), resolves the session's location, then
   `commands.execute({name, invocation})` with `delivery ?? "steer"`.
3. → the config-command plugin's definition (`packages/core/src/config/plugin/command.ts`
   [8]), which registers every `.opencode/commands/**/*.md` file:
   `evaluateTemplate` (expands `$ARGUMENTS`/`$n` and runs the `!`...`` shell
   blocks — outside the tool-permission flow, matching the hourly command's
   own note), then for a current-session command: if the frontmatter binds an
   agent and `session.agent !== agent` → `ctx.session.switchAgent`, optional
   `switchModel`, finally `ctx.session.prompt({...input.prompt, sessionID,
   text: expanded, delivery})`.
4. → `Session.prompt` (`packages/core/src/session/session.ts` [6]) →
   `SessionPrompt.prepare` (`packages/core/src/session/prompt.ts` [5]) →
   `hooks.trigger("session","prompt", …)` → attachment/skill resolution →
   inbox `admit` → `wake`.

Consequences for C04: at hook time `ctx.session.get` already reflects the
**command-bound agent** (`agent-board-coord` from the frontmatter / session
created with that agent) [8]; the hook sees the **fully expanded** prompt
text, so the block appends after the gate output (fine — and the
idempotence-header check must scan the whole expanded text, which can be
long); and the once-flag cannot rely on message-id dedup (fresh ids per
attempt, F1).

Interactive `/pipeline-boards-hourly` in a TUI/GUI chat hits the same server
expansion ("OpenCode submits … as a user prompt", DOC [2]) — same chain.

### F3 — OpenChamber scheduled dispatch (Q1c, LOCAL [12], `@openchamber/web` 2.5.2)

Per run: `waitForOpenCodeReady(10s)` → `client.session.create({title,
location:{directory}, metadata:{openchamber:{kind:"scheduled"}}, model?,
agent?})` (agent from task config; comment: "Agent, model and variant belong
to the session in v2: a scheduled run fixes them here") → optional
permission auto-accept → optional goal (`session.synthetic` briefing first —
does NOT run hooks [1]) → `resolveScheduledCommand`: `parseScheduledCommandPrompt`
= prompt starts with `/`; if the parsed name is present in
`client.command.list({location})`, dispatch via `client.session.command`
(`{name, text: arguments}`), **else** fall back to `client.session.prompt`
with the raw text (snippet-expanded). **Both legs land in the
hook-running admission path.** Docs agree: scheduled task "starts a new
session and sends the prompt"; "The prompt can be a slash command" (WEB
[13]). The repo's earlier friction ("scheduled launch spawning agent `code`")
was a task-config reality, not an admission-path fact — the session's agent
is whatever the task pins, and the hook fires regardless, so the plugin must
gate on the *session's* agent, never on the transport.

### F4 — `instructions.entry.put` semantics (Q2)

- DOC [1]: keyed entries "render as `<context key="...">` blocks in the
  session's instructions, and updates or removals are announced at the next
  step boundary without queuing a message turn." Instructions assembly puts
  them last ("Session-specific instruction entries supplied through the API",
  DOC [11] ordering list).
- VERIFIED-SOURCE: entries live in a DB table **keyed by `session_id`**
  [12-core]; keys must be `[a-z0-9][a-z0-9._-]*`, server namespaces them to
  `api/<key>`, value is JSON capped at **256 KiB** (413 on overflow) [13].
  Public HTTP surface: `PUT/DELETE/GET
  /api/experimental/session/{id}/instructions/entries/{key}` [3] — marked
  experimental.
- Release intent (WEB [17]): "Instead of editing the system prompt and
  busting the prompt cache, each change is added as a small update at the
  next step boundary" — entries are the prompt-cache-friendly seam.
- **Session-lifetime, not per-turn** — it is durable per-session state
  re-rendered into instructions, and updates reach the model at the next
  step boundary (so a `put` from inside the prompt hook is already in place
  for turn 1). **Not proven to reach subagents**: nothing in docs or source
  propagates a parent's entries to child sessions; the only explicitly
  inherited child property is session-scoped permissions ("Child sessions
  inherit the rules in effect when they are created", DOC [1]). Grade:
  parent-session PROVEN; subagent propagation UNPROVEN — assume NO.
- Not visible to AC6's persisted-message readback (entries are instructions,
  not messages) — keep the prompt-hook as the injectable-into-prompt
  mechanism; entries are the alternative, with its own proof shape
  (`GET …/instructions/entries`).

### F5 — Alternative seams for pre-first-prompt context (Q3)

1. **`ctx.session.hook("context", …)`** — runs for *every* agent-loop model
   call including tool continuations; mutable `system` array [1]. Strongest
   durability property: immune to compaction loss and works however the
   prompt got admitted; can refresh the block every turn (staleness cure).
   Costs: not persisted (no readback proof), re-arms each turn (cache:
   block text is appended per assembled request; identical text keeps prompt
   caches warm only if stable — vary it and you bust the cache; note F4
   [17]'s cache framing), and per-subagent coverage is source-consistent but
   not doc-stated.
2. **`instructions.entry.put`** — durable, cache-preserving, next-step-
   boundary delivery; experimental API surface; AC6 proof shape differs.
3. **Event-driven (`session.created` → put entry)** — events exist (issue
   [18] confirms `session.created` "is emitted normally" for fresh sessions)
   but the same issue documents miss scenarios (resume path), and ordering
   against a fast first prompt is unspecified. UNPROVEN and racy — not
   recommended as the primary.
4. **OpenChamber-native pre-seed** — scheduled-task prompt text supports
   `#hashtag` **snippets** expanded client-side at dispatch (LOCAL [12]
   `expandSnippets`, WEB [14]): a project snippet could carry the C03
   collector's block without touching OpenCode admission at all — but it is
   static text (staleness = whoever regenerates the snippet file), machine-
   local/user-owned (out of scope here), and the `runPrompt` fallback is the
   only leg that expands snippets (slash-command dispatch does NOT run
   `expandSnippets`). Good Adjacent option, not a C04 replacement.
5. `Plugin.define` vs the hand-written default-export shape: the two shipped
   plugins match the current shape (`{id, async setup(ctx)}` plain object —
   same shape the docs example expands to [1]); C04 keeps the shipped
   plugins' working shape per the chunk note.

### F6 — Cross-lab patterns (Q4)

- **Claude Code hooks** (WEB [15]): `UserPromptSubmit` →
  `hookSpecificOutput.additionalContext` — "String added to Claude's context
  **alongside the submitted prompt**" — the near-exact analog of OpenCode's
  prompt-hook text append. `SessionStart` fires before the first user
  message and documents the durability trick C04 should borrow: a `compact`
  matcher ("use a SessionStart hook with a `compact` matcher to re-inject
  critical context after every compaction") — i.e. the ecosystem norm is
  *inject-once-then-refresh-on-loss*, matching F5-1's compaction warning.
  Its own bug reports (#49063, #52876) show injection seams can silently
  drop content in some harnesses — independent evidence that C04's
  live-fire acceptance gate is the right posture, not paranoia.
- **OpenAI Codex** (WEB [16]): same `additionalContext` shape on
  `SessionStart`/`UserPromptSubmit`/`SubagentStart`; after compaction,
  `SessionStart` hooks with `source: "compact"` re-run before the next model
  request; AGENTS.md-style instruction chains are **rebuilt every run**
  ("no cache to clear manually") — and a real staleness incident
  (issue #39899) shows a scheduled job's cached prompt view diverging from
  the persisted `automation.toml` after update — the canonical lesson:
  *dispatch-time re-read beats cached views*.
- **LangGraph/e2b sandbox example** (WEB [20]): "Context is not
  checkpointed, so a resume must rebuild it. After `interrupt()` the only
  thing the checkpoint kept is `sandbox_id` (a string in state)" — the
  structured-ID pre-seed pattern: carry IDs in the seeded context, resolve
  the objects live, exactly the Board-context-block doctrine.
- **Context-engineering practice** (WEB [21]): store references/IDs + replay
  metadata; TTL-bound caches; session-scoped working-set treated as
  ephemeral — supports the plan's risk wording "on any id-shaped call error,
  re-resolve" over TTL-only refresh (a TTL cannot know the board moved;
  an id-shaped 404/400 can).

## Contradictions and how to weigh them

- **DOC [1] phrasing vs route identity**: "Commands that submit through
  `session.prompt` run the hook" could be misread as excluding the
  `/command` route (a different endpoint). Source at the installed version
  resolves it: the command definition's executor literally calls
  `ctx.session.prompt` [8]. Weigh: source > docs prose; grade PROVEN-SOURCE.
- **OpenChamber main-branch docs** describe "Session create + **prompt_async**
  execution" while the installed 2.5.2 uses awaited `session.command` /
  `session.prompt` (LOCAL [12]): version drift. Weigh: the installed build,
  since the live scheduler runs it; note the C03/C04 docs must not hardcode
  which dispatch leg fires.
- **question-notify header** still cites installed CLI v2.0.32 while
  `opencode --version` now reports **v2.1.4** (and the plugin's later header
  lines were re-grounded against 2.1.4): consistent, but C04 must target
  2.1.4 types (`SessionPrompt` shape above), not the older notes.
- **"retry returns original admission without rerunning hooks" vs "hooks can
  run more than once"**: both true — the first is id-keyed client retries,
  the second concurrent submissions; the command path mints fresh ids so
  neither protection applies. Resolve: once-guard + header idempotence stay.

## Implications for the plan (C04 wording changes to adopt)

1. **Keep the prompt hook as the injection seam; live-fire remains required**
   but its scope narrows from "does the hook fire at all?" (PROVEN: yes,
   all three legs) to "does this deployment's hourly task + main-checkout
   location exhibit it end-to-end?" (UNPROVEN: task config content, plugin
   presence at the run's location, MCP reachability from the server process).
   AC6's degraded outcome stays correctly risk-priced either way.
2. **Sharpen AC4's justification**: never-throw + bounded timeout are
   correctness requirements — a rejected/hanging hook means the prompt is
   *never admitted* (the scheduled run dies at dispatch), not merely slow.
   Every code path in the hook must be wrapped; the 8 s `AbortSignal.timeout`
   is the admission-latency budget (it delays the dispatch HTTP response
   only; no model-turn race exists [6][7]).
3. **Once-guard must not be fooled by the goal synthetic message**: if the
   lab ever enables session goals on the hourly task, `session.synthetic`
   precedes the real prompt and does not run hooks [1][12] — so counting
   "first prompt seen" inside the hook is safe (synthetic never enters it),
   but the plugin must never treat a per-session *event* as the trigger.
4. **Location-plugin nuance for the live-fire**: plugin discovery is
   location-scoped ("location plugins", DOC [1]) and the hourly run's
   location is the main checkout after landing (its own command text says
   so). Pre-landing, C04's live-fire must create the test session in a
   directory where `.opencode/plugin/board-context/` actually loads (this
   worktree), and the post-landing scheduled proof is inherently a
   user-owned step (branch lands via PR — plan already marks PR user-owned).
5. **Compaction durability (new finding)**: the injected block lives in the
   first persisted user message; compaction summarizes history and the block
   may not survive long runs — Claude/Codex both solve this by re-injection
   at compact. Recommended wording: C04 may, cheaply, also write the block
   via `ctx.session.instructions.entry.put({sessionID, key:
   "board-context", value: …})` from the same hook (session-lifetime,
   cache-preserving, ≤256 KiB [13]), making the block durable across
   compaction and step boundaries; the consumption rule (C03) then reads
   entries first, prompt block second, and re-resolves on any id-shaped
   error. If not adopted in C04, record as follow-up — do not ship a
   half-proof.
6. **Subagents**: entries are not proven to reach children (F4) — the
   pipeline's file-bus already re-seeds children via launch messages; no
   change needed, but the boards skill consumption rule should say the
   block is a **starting** context, re-resolve on id-shaped errors, and
   never trust it after drift (cross-lab consensus F6).
7. C04's `GET /api/session/<id>/context` readback is confirmed as the right
   AC6 proof [1][3]; expected shape: expanded hourly text **plus** the
   appended block as the canonical persisted user input.

## Open questions

- Whether `ctx.session.hook("context")` fires inside **child** sessions'
  agent loops from the parent location's plugin instance (source-consistent
  — hooks are location-scoped and every model call triggers — but not
  doc-stated). Only matters if the plan later wants per-turn injection for
  subagents; live-fire it if adopted.
- OpenChamber-side timeout on `session.command` dispatch responses (client
  default unknown; watchdog is 30 min run-level). The 8 s hook budget is
  comfortably inside the observed pattern (`waitForOpenCodeReady(10_000)`),
  but a formal bound is unverified.
- Whether the hourly task pins `agent: agent-board-coord` in its OpenChamber
  config or relies on the command frontmatter `switchAgent` — both paths end
  with the right agent at hook time (F3), but only the live run knows which
  leg this lab uses.

## Adjacent (out of the four questions, worth a line)

- Fresh upstream issue #59135 (2026-10-26): prompts to freshly-created child
  sessions of `subagent`-bound commands can be **silently dropped** —
  relevant background for the pipeline's subagent launches; C04 is not on
  that path (current-session command leg), but keep it in FRICTION view if
  board-coord launches ever go `subagent: true`.
- OpenChamber registers a native `openchamber` agent tool for
  project/session/scheduled-task orchestration when it owns the OpenCode
  server — a future route to *write* scheduled-task text programmatically
  (C03 paste path automation) without touching machine-local config by hand.

## Sources

- [1] DOC — OpenCode V2 Server plugin guide, "Hooks"/"Prompt admission"/
  "Sessions"/"Permissions" sections.
  https://opencode.ai/v2/docs/build/plugins/server (read 2026-10-27)
- [2] DOC — OpenCode V2 Commands guide (Execution, Shell, Background).
  https://opencode.ai/v2/docs/commands (read 2026-10-27)
- [3] DOC — OpenCode V2 HTTP API overview (session route inventory incl.
  `/api/session/{sessionID}/prompt|command|synthetic|shell`,
  `/context`, experimental instructions-entries, `/api/event`).
  https://opencode.ai/v2/docs/api (read 2026-10-27)
- [4] DOC — OpenAPI: `session.command` operation
  ("Execute a slash command callback immediately."; body
  `{name,text,files,agents,skills,delivery}`). https://opencode.ai/v2/openapi.json
  (fetched + parsed 2026-10-27)
- [5] VERIFIED-SOURCE — `packages/core/src/session/prompt.ts` @ v2.1.4
  (`SessionPrompt.prepare`: `hooks.trigger("session","prompt", …)` before
  attachment/skill resolution).
  https://raw.githubusercontent.com/anomalyco/opencode/v2.1.4/packages/core/src/session/prompt.ts
- [6] VERIFIED-SOURCE — `packages/core/src/session/session.ts` @ v2.1.4
  (`Session.prompt`: reconcile → prepare → admit → `execution.wake`).
  https://raw.githubusercontent.com/anomalyco/opencode/v2.1.4/packages/core/src/session/session.ts
- [7] VERIFIED-SOURCE — `packages/core/src/plugin/hooks.ts` @ v2.1.4
  (sequential awaited trigger; session hooks' failure channel `never`).
  https://raw.githubusercontent.com/anomalyco/opencode/v2.1.4/packages/core/src/plugin/hooks.ts
- [8] VERIFIED-SOURCE — `packages/core/src/config/plugin/command.ts` @ v2.1.4
  (markdown-command execute: evaluateTemplate → subagent branch →
  switchAgent/switchModel → `ctx.session.prompt`).
  https://raw.githubusercontent.com/anomalyco/opencode/v2.1.4/packages/core/src/config/plugin/command.ts
- [9] VERIFIED-SOURCE — `packages/core/src/session/command.ts` @ v2.1.4.
  https://raw.githubusercontent.com/anomalyco/opencode/v2.1.4/packages/core/src/session/command.ts
- [10] VERIFIED-SOURCE — `packages/plugin/src/promise/session.ts` @ v2.1.4
  (`SessionPrompt` event interface: no `agent`; callback
  `=> Promise<void> | void`; prompt hook `options: never`).
  https://raw.githubusercontent.com/anomalyco/opencode/v2.1.4/packages/plugin/src/promise/session.ts
- [11] DOC — OpenCode V2 Instructions guide (assembly order; entries
  position 6). https://opencode.ai/v2/docs/instructions (read 2026-10-27)
- [12-core] VERIFIED-SOURCE — `packages/core/src/session/instruction-entry.ts`
  @ v2.1.4 (entries table keyed by `session_id`).
- [12] LOCAL — installed `@openchamber/web` 2.5.2,
  `server/lib/scheduled-tasks/runtime.js` + `DOCUMENTATION.md` +
  `server/lib/opencode/snippets.js` (scheduled dispatch chain, read
  2026-10-27).
- [13] VERIFIED-SOURCE — `packages/schema/src/instruction-entry.ts` @ v2.1.4
  (key pattern, `api/<key>` namespacing, JSON value, `MaxValueBytes =
  256*1024`, 413 error).
- [14] WEB — OpenChamber docs: Commands & Snippets.
  https://docs.openchamber.dev/commands-snippets/ (read 2026-10-27)
- [15] WEB — Claude Code hooks guide + hooks reference (`additionalContext`,
  `SessionStart` `compact` matcher, `UserPromptSubmit`).
  https://code.claude.com/docs/en/hooks-guide ·
  https://code.claude.com/docs/en/hooks (read 2026-10-27)
- [16] WEB — OpenAI Codex hooks (developers.openai.com/codex/hooks:
  `SessionStart`/`source:"compact"`; AGENTS.md rebuild-per-run,
  developers.openai.com/codex/agent-configuration/agents-md; stale scheduled
  prompt issue github.com/openai/codex/issues/39899) (read 2026-10-27)
- [17] WEB — OpenCode releases notes (instructions entries added "as a small
  update at the next step boundary … instead of … busting the prompt
  cache"). https://github.com/anomalyco/opencode/releases (read 2026-10-27)
- [18] WEB — anomalyco/opencode issue #39711 (`session.created` emitted for
  fresh sessions; missed on `--session` resume) (read 2026-10-27)
- [19] WEB — anomalyco/opencode issue #59135 (subagent-bound command prompts
  silently dropped; open 2026-10-26) + anthropics/claude-code issues #49063,
  #52876 (silent `additionalContext` drops) (read 2026-10-27)
- [20] WEB — e2b-cookbook LangGraph plan-and-execute notes (checkpoint keeps
  ids; resume must rebuild context).
  https://github.com/e2b-dev/e2b-cookbook/tree/main/examples/langgraph-plan-and-execute-python
- [21] WEB — Jeremy Daly, Context Engineering for Commercial Agent Systems
  (replay-with-ids baseline, TTL caches). https://www.jeremydaly.com/context-engineering-for-commercial-agent-systems
- [22] LOCAL — repo surfaces: `opencode --version` = v2.1.4;
  `.opencode/plugin/question-notify/index.ts`;
  `.opencode/plugin/aislop-gate/index.ts`;
  `.rulesync/commands/pipeline-boards-hourly.md`; `.opencode/commands/`
  registry contents.

Reliability notes: F1–F3 confidence 8–9/10 (docs + installed-version source
agree; weakest link is this deployment's live task config). F4 confidence
8/10 on parent-session semantics (source + docs), 3/10 on any subagent
propagation assumption (absence-of-evidence, treated as NO). F5-1/2 7/10
(doc-stated behavior, unproven interaction with compaction summaries). F6 is
directional, single-source per pattern, 5–6/10 — used for design posture,
not for C04 acceptance.

```
RESULT
status: DONE
chunk: C04-research
files_changed: [.agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/RESEARCH.md]
commands_run: [webfetch opencode.ai V2 docs (plugins/server, commands, instructions, api, llms.txt) => pass; curl GitHub tree v2.1.4 + raw core/plugin sources + grep/read => pass; curl opencode.ai/v2/openapi.json + parse session.command => pass; read installed @openchamber/web 2.5.2 scheduled-tasks runtime => pass; opencode --version (v2.1.4) => informational; websearch OpenChamber/Claude-Code/Codex/LangGraph cross-lab => pass]
deviations: storm intermediates (perspectives.md/raw/… and report.md under storm-runs/) not written — the launch hard-forbade any file other than RESEARCH.md; multi-perspective method applied in-session with the contradiction map and reliability notes folded into RESEARCH.md.
friction: glob hides dot-directories (.rulesync/** returned nothing) — resolved with shell ls; first webfetch of the docs index URL echoed llms.txt content — resolved by fetching the exact page URLs; docs-page fetch of /v2/docs/build/plugins returned Overview only (admission details live on the /server subpage) — resolved by fetching the subpage.
open_questions: none for C04's go/no-go — the three remaining unknowns are recorded in RESEARCH.md "Open questions" (subagent context-hook coverage, OpenChamber dispatch timeout bound, which agent-pinning leg the live task uses) and none gate the design; live-fire items are folded into Implications 4.
next_suggested: proceed to agent-test (all chunks) then C01/C02 wave 1; C04 dev must read this RESEARCH.md and adopt Implications 1–7 (esp. mandatory never-throw posture, once-guard rationale, location-plugin live-fire nuance, optional instructions-entry durability add-on).
```
