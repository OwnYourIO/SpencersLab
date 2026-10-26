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

## Grounding (C02 — permission-ask surface; replan 2026-10-26, re-verified against installed v2.1.4)
Sources: installed binary `~/.nvm/versions/node/v26.5.0/lib/node_modules/@opencode/
cli/bin/opencode.exe` (**v2.1.4** — the CLI self-updated after C01 was grounded on
2.0.32; binary-strings technique per FRICTION 2026-10-24 plan entry), the live
server's OpenAPI (`opencode api get /openapi.json`), and opencode.ai V2 plugin
docs. C01's suite re-run green (35/35) on this branch before relying on any of it.

7. **Signal = durable `permission.asked` event on the same `ctx.event.subscribe`
   stream C01 built.** Binary defines `Yt({ type: "permission.asked", schema:
   Permission.Request.fields })` + `permission.replied` as the durable catalog pair;
   the server's Permission.ask service does
   `publish(Tx.Asked, request)` **only when the ruleset effect resolves to
   `ask`** (`allow` passes silently; `deny` errors) and exactly once per request ID
   (duplicate pending-ID guard). Internal consumers prove stream delivery: the
   desktop-notify path subscribes `on("permission.asked")` **on the same event
   source** it uses for `session.execution.succeeded`, and the `run` CLI's
   auto-approve loop iterates the subscribed stream reading
   `t.type === "permission.asked"` + `t.data.sessionID`. Envelope `{type, data}`
   like the lifecycle pair; C01's flat-payload dual read is reused.
8. **Ask payload (`Permission.Request`, from live OpenAPI + binary schema):**
   `{ id: "per…", sessionID, action: string, resources: string[], save?: string[],
   metadata?: object, source?: { type: "tool", messageID, id }, message?: string }`
   — required: `id, sessionID, action, resources`. **No agent name** (`agent` is a
   ruleset-eval parameter server-side only) ⇒ title needs `ctx.session.get`, with
   the existing `"session"` fallback label. `reply` enum (`once|always|reject`)
   lives on `permission.replied`, not needed here.
9. **`action`/`resources` contents (assert call-sites in the binary):** shell ⇒
   `action:"shell"`, resources ⇒ command string(s); edit/write/patch ⇒
   `action:"edit"`, resources ⇒ file-path resources, `metadata` embeds
   filepath/diff/files (too noisy for a phone ⇒ excerpt reads message/action/
   resources only); read ⇒ `action:"read"` + path resource; also observed
   `question`, `grep`, `glob`, `webfetch`, `websearch`,
   `opencode_read_mcp_resource`. So the payload carries plenty: prefer `message`,
   else `action + first ≤3 resources`, never `metadata`.
10. **V1-compat twin, same type string:** a second `permission.asked` definition
    exists with `PermissionV1.Request` fields `{ id:"per…", sessionID, permission,
    patterns[], metadata, always[], tool?: { messageID, callID } }` ⇒ handler
    tolerantly reads `action ?? permission` and `resources ?? patterns`. There is
    **no `permission.updated`** anywhere in the v2.1.4 binary (0 string hits) —
    the pre-2.x bus-event candidate is dead.
11. **Rejected surfaces (verified, not guessed):** `session.permission.*` — those
    strings are SDK/RPC **method** paths (`/api/session/{id}/permission[/reply]`,
    list/get/create/sync/reply), not event types; a `ctx.permission` plugin hook —
    no such plugin-ctx namespace exists (all `permission:{` hits are the HTTP/RPC
    client surface and the TUI's local state cache); `execute.before` — permission
    asks are published by the permission service *inside* a tool's
    `assert(…)` call, never as a tool named permission (and gating a tool never
    executes the hook's notify path for the blocked action); `form.created` —
    the elicitation/question system (the question tool's own user-prompt lands
    there), deliberately NOT subscribed because the plugin's existing
    `execute.before` question hook already pushes for it and subscribing both
    would double-push.
12. **Plugin ctx unchanged in v2.1.4:** binary client exposes
    `event: { subscribe: … GET /api/event … }` exactly as C01 used; the shared
    cooldown lives on the setup-closure `lastNotified` Map — C02 extracts it into
    one gate (`allowPush(key)`) used by both the question hook and the permission
    dispatch (same key namespace, sessionID ⇒ a question push and an immediate
    ask for one session yield a single phone push; intake #2).

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
- **C02** test suite (all files): `node --test 'tests/opencode/*.test.ts'` —
  quoted glob; a bare `tests/opencode` directory argument fails under this Node
  build (treats it as one test file)
- **C02** legacy-test immutability: `md5sum tests/opencode/question-notify.test.ts`
  must equal `8b5d838221f79ad7ced875760752febb` (the 35 shipped tests untouched)
- **C02** load+shape check (extends C01's): same command, with an added clause
  `||typeof m.handlePermission!=="function"` in the exit-1 condition — module
  imports, default keeps `id`/`setup`, and `handlePermission` is a named export
- **C02** grep wiring: `grep -q 'permission\.asked'
  .opencode/plugin/question-notify/index.ts`
- **C02** grep asked-only, no double-push sources: `! grep -qE
  'permission\.replied|permission\.updated|form\.created'
  .opencode/plugin/question-notify/index.ts`
- **C02** regressions: every C01 command above must still pass (AC 6)
- smoke (LIVE, **user-owned** — do not run from the pipeline): restart the
  OpenCode service, open a top-level session, finish one turn → "finished"
  push; finish with a forced provider failure after retries → exactly one
  "stopped" push; run a subagent → no lifecycle pushes. **C02:** trigger a
  permission ask in ANY session (top-level or pipeline child) by invoking a
  tool the ruleset gates with `ask` → one "needs approval" push with the
  action/resource excerpt; several near-simultaneous asks → one push per
  session per 15 s; a question push immediately followed by an ask for the
  same session → one push total (shared cooldown). Watch
  `~/.local/share/opencode/log/opencode.log` for `[question-notify]` lines.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Event subscription + finished/crash notify with testable seam | M | 1 | [] | single chunk: subscription loop, topology filter, both handlers and the test seam are one mergeable change; splitting would leave a chunk that cannot ship alone |
| C02 | Approval-ask push on `permission.asked` (all asking sessions) | M | 2 | [C01] | reuses C01's shipped subscribe loop, cooldown Map, `truncate`/`sendHANotify` plumbing and test-seam conventions; edits the same plugin file + tests dir, so it cannot land before C01 exists |

## Wave order
1. C01 (only chunk) — **done** (2026-10-24; shipped, final review APPROVED).
2. C02 (replan 2026-10-26) — depends only on C01 (wave 1, complete): same-file
   extension of the live loop + shared per-session cooldown + notify helpers.

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
- **C02** version drift: Grounding 1–6 were v2.0.32; C02's #7–#12 are v2.1.4
  (CLI self-updated Oct 26). If the live service still runs an older build at
  smoke time, the tolerant dual reads (V2 fields first, V1 `permission`/`patterns`
  fallback) plus the one-shot envelope-keys debug log cover interpretation.
- **C02** lookup-failure policy intentionally diverges from lifecycle: an
  approval push is emitted even when `session.get` fails (label `session`) —
  dropping a push for a blocked session is worse than an imprecise title
  (DECISIONS 2026-10-26).
