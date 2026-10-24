# PLAN: HA lifecycle notifications — finished & crash-out
feature: 2026/2026-10-feat-ha-lifecycle-notify

## Goal
Extend the existing `.opencode/plugin/question-notify` plugin so the user's
phone also gets a Home Assistant push when a TOP-LEVEL (user-driven) OpenCode
session finishes its assistant turn (waiting for input), and exactly one push
when such a session stops running due to a terminal model/execution failure.
Subagent sessions (pipeline `agent-*` children) must never trigger these two
notifications; the existing question notification keeps its current behavior
unchanged.

## Out of scope
- Any change to the existing question-tool notify path (its `agent-*` prefix
  filter, 15 s cooldown, title format).
- Home Assistant side: same `notify.mobile_app_pixel_6` service over the same
  `admin-global-homeassistant` ha-mcp JSON-RPC path.
- New plugin files/packages, new npm dependencies, chart/ApplicationSet/
  custom-values changes (this is a TS plugin change — helm-lint conventions
  do not apply).
- Notifications on `session.execution.interrupted` (user/shutdown/superseded/
  inactivity) and on intermediate retries (`session.retry.scheduled`).
- Restarting the OpenCode background service — user-owned verification step.

## Grounding (V2 event semantics — verified, not guessed)
Sources: opencode.ai V2 plugins guide (`/v2/docs/build/plugins`), the live
server's OpenAPI (`opencode api get /openapi.json`, CLI **v2.0.32**), and the
installed binary's embedded JS (`strings` on
`~/.nvm/.../@opencode/cli/bin/opencode.exe`). Docs describe `@opencode/plugin`
2.1.2 types; every claim below was additionally confirmed against the
installed v2.0.32 surface.

1. **Event stream is available to plugins**: plugin ctx exposes
   `event: { subscribe(...) }` in v2.0.32 (binary); guide pattern:
   `for await (const event of ctx.event.subscribe({ signal }))`; server
   endpoint `/api/event` ("native events … across all server locations").
2. **Finished trigger = `session.execution.succeeded`** (durable V2-native
   event; payload data = `{ sessionID }`). One terminal event per completed
   agent-loop execution = "assistant turn done, waiting for user input". The
   V1-compat `session.idle`/`session.status` events also exist in the binary
   but are the legacy compatibility surface — not used (DECISIONS).
3. **Crash trigger = `session.execution.failed`** (terminal, once per run;
   data = `{ sessionID, error: Session.StructuredError }` where
   `Session.StructuredError = { type, message, status?, response?: { body } }`).
   Intermediate provider failures emit
   `session.retry.scheduled` (`{ sessionID, assistantMessageID, attempt, at,
   error }`) instead — so the retry-then-give-up semantics are explicit and NO
   consecutive-error heuristic is needed (intake #2 satisfied by the native
   signal). Consumers (TUI, `run` CLI) treat execution.failed as the single
   terminal error.
4. **Top-level vs subagent = session topology via `parentID`**, not agent
   name: live OpenAPI `Session.Info` has optional `parentID`; confirmed on the
   running server — this planner session (child, agent `agent-plan`) carries
   `parentID = coord session`, the coord session (`agent-coord`, user-launched
   in OpenChamber) has none. Child sessions emit the same execution events, so
   the handler must look up each event's session and skip it when `parentID`
   is set.
5. **Context excerpt source**: `ctx.session.context({ sessionID })` returns
   the message array; last entry is `type:"assistant"` with `content` parts of
   `type: "text" | "reasoning" | "tool" | ...` (verified live against the
   coord session). Excerpt = last `text` part of the last assistant message,
   `.slice(0, 240)` (same cap as question notify).
6. Session lookup for name: `ctx.session.get({ sessionID })` → `agent`,
   `title`, `parentID`.

## Commands
All deterministic and offline (Node v26 executes/imports TS natively via type
stripping; no tsc/package deps available or needed):

- test: `node --test tests/opencode/question-notify.test.ts` (repo-root
  `tests/` — the test file must live OUTSIDE `.opencode/`, whose plugin
  discovery loads every `.ts` it scans; a test file could be imported as a
  plugin entry)
- load+shape check: `node --input-type=module -e 'const m=await import(new URL("file://"+process.cwd()+"/.opencode/plugin/question-notify/index.ts")); if(m.default?.id!=="local.question-notify"||typeof m.default.setup!=="function"||typeof m.handleLifecycle!=="function")process.exit(1)'`
- grep wiring: `grep -q 'session\.execution\.succeeded' .opencode/plugin/question-notify/index.ts && grep -q 'session\.execution\.failed' .opencode/plugin/question-notify/index.ts && grep -q 'event\.subscribe' .opencode/plugin/question-notify/index.ts`
- grep question path intact: `grep -q 'event.tool !== "question"' .opencode/plugin/question-notify/index.ts`
- grep no per-retry notify (crash fires only on terminal event): `! grep -q 'session\.retry\.scheduled' .opencode/plugin/question-notify/index.ts`
- smoke (LIVE, **user-owned** — do not run from the pipeline): restart the
  OpenCode service, open a top-level session, finish one turn → "finished"
  push; finish with a forced provider failure after retries → exactly one
  "stopped" push; run a subagent → no lifecycle pushes. Watch
  `~/.local/share/opencode/log/opencode.log` for `[question-notify]` lines.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Event subscription + finished/crash notify with testable seam | M | 1 | [] | single chunk: subscription loop, topology filter, both handlers and the test seam are one mergeable change; splitting would leave a chunk that cannot ship alone |

## Wave order
1. C01 (only chunk).

## Risks / assumptions
- Plugin ctx `event.subscribe` is confirmed in the v2.0.32 binary, but its
  per-event envelope (`event.type` / `event.data.sessionID`) must be verified
  at runtime; dev keeps the existing one-shot `console.error` debug-log
  convention for the first lifecycle event received (log keys only) so the
  live smoke can confirm it. Defensive dual-read `event.data?.sessionID ??
  event.sessionID` allowed, one line.
- A top-level pipeline `agent-coord` session goes through many turns; the
  user gets one "finished" push per completed turn of a top-level session —
  this is the requested semantics (intake #1), accepted as noise risk.
- `session.execution.failed` also covers immediate fatal errors (no retries)
  — still one push per stopped run, consistent with intake #2 ("stops
  running").
- V1-compat `session.idle`/`session.error` are ignored deliberately; if a
  future OpenCode removes the compat layer nothing breaks; if it removes the
  V2 native events the grep commands pin the contract.
- Failure policy unchanged: every notify path is fire-and-forget with stderr
  logging; a session-lookup rejection suppresses the push (never crash the
  event loop, never ping with unknown topology).
