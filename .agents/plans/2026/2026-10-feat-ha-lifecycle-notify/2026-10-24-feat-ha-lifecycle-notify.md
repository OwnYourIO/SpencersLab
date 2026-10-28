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
  filter, 15 s cooldown, title format). *(C04 note: what C04 fixes is the
  SHARED `haMcpUrl` transport underneath all three triggers — the question
  path's own filter/cooldown/title contract stays byte-unchanged, pinned by
  its md5-locked test file; restoring pushes there is the ticket, not a
  scope breach.)*
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

## Grounding (C03 — reply-cancellation surface; replan 2026-10-27, installed v2.1.4 re-verified live)
Sources: `opencode --version` => v2.1.4 (unchanged since the C02 grounding — no new
drift), binary-strings on the same installed `opencode.exe`, live
`opencode api get /openapi.json`. C01+C02 suites re-run green (60/60, md5 pin
holds) on this branch before relying on any of it. The C02 "permission.replied
absent" pins are deliberately inverted by this chunk — they were correct for the
push-on-arrival design C02 shipped; the user's live bug (auto-approve clients get
pushed anyway) shows arrival is not the right push moment.

13. **Cancellation signal = durable `permission.replied` on the same subscribe
    stream.** Binary catalog pair `Tx={Asked,Replied,…}`; internal consumers process
    both from ONE event-dispatch function (`permission.asked` pushes the pending
    list, `permission.replied` filters `s.id !== t.data.requestID`) — stream
    co-delivery with the lifecycle/asked events the plugin already receives is
    proven the same way Grounding #7 proved `asked`. Payload, **identical field
    names in the V2-native and V1-compat twins**: `{ sessionID, requestID, reply }`
    — `requestID` is the asked event's `Permission.Request.id` ⇒ per-request-id
    timers are keyable offline-deterministically. OpenAPI: `Permission.Reply` =
    `once|always|reject`; no reply-with-modification variant exists (a reject may
    carry feedback `message` — same event, same cancel semantics).
14. **Every resolution path emits `replied` ⇒ cancel on ANY reply value.** The
    binary has exactly five `publish(Tx.Replied,…)` sites: the user/client reply
    path (`reply: <decision>`), the reject-with-feedback branch, the save-rule
    batch auto-answer (`reply:"always"` per superseded pending request), and the
    shutdown finalizer (`reply:"reject"` for every still-pending ask). There is no
    resolution of a pending ask that skips the event — so a human answering "no"
    (reject) is also an answered ask and must cancel the push.
15. **Which world we live in (the reported bug's mechanism, confirmed):** the
    server has ONE `publish(Tx.Asked, …)` call-site, gated only by ruleset
    effect=`ask`, a duplicate-pending-id guard, and a shutdown flag — it knows
    nothing about the client's auto-approve setting. The `run` CLI's auto-approve
    loop reads `t.type==="permission.asked"` from the subscribed stream and answers
    it afterwards: exactly OpenChamber's "Permissions: accept everything" — the
    ask IS published, the client replies in milliseconds, and C02's
    push-on-arrival fired before that reply. If a ruleset instead resolves
    `allow`, there is no `asked` at all and no timer starts. The pending-only
    timer design is correct in both worlds.
16. **Asked payload carries the request `id`** — required field per live OpenAPI
    (`Permission.Request` required `[id, sessionID, action, resources]`,
    `Permission.ID` pattern `^per`); Grounding #8 re-confirmed unchanged in
    v2.1.4. Timer keying needs no new payload reads.
17. **Redelivery is server-guarded** (duplicate pending ID ⇒ error, not a second
    publish), so plugin-side replace-on-same-id is belt-and-sequencing for stream
    reconnects rather than a correctness requirement.

## Grounding (C04 — ha-mcp URL discovery via the MCP config view; replan 2026-10-28, installed v2.1.4 re-verified live)
Sources: binary-strings on the installed `~/.nvm/versions/node/v26.5.0/lib/node_modules/
@opencode/cli/bin/opencode.exe` (**v2.1.4**, re-checked 2026-10-28 — no drift since
C02/C03), the live server's OpenAPI (`opencode api get /openapi.json`), the shipped
`@opencode/plugin@2.1.2` dist types (unpkg: `dist/promise/mcp.d.ts`,
`registration.d.ts`; the docs pages remain useless for v2 ctx — Grounding method
per FRICTION 2026-10-24), and live config files. C03's 76/76 suite + both md5 pins
re-run green in THIS worktree before relying on any of it.

18. **Plugin ctx exposes the MCP CONFIG view**: the binary's plugin-host ctx
    assembly is `mcp:{list:t(b["mcp.list"],e.mcp.list),transform:M(e.mcp),reload:…}`
    with `M=(o)=>(r)=>I(o.transform((n)=>{r(n)}))` — i.e.
    `ctx.mcp.transform(callback)` runs `callback(editor)` over the MCP state and
    resolves `Promise<{dispose}>`. The shipped types name the editor surface
    exactly: `MCPEditor{list():[name,ServerConfig][], get(name):ServerConfig|
    undefined, set, update, remove}`, `MCPDomain{list; transform:
    Transform<MCPEditor>; reload}` with `Transform<I>=(cb:(i:I)=>void)=>
    Promise<{dispose():Promise<void>}>`. Binary MCP state:
    `Sl({name:"mcp", initial:()=>({servers:new Map(…)}), editor:(s)=>({list:()=>
    Array.from(s.servers), get:n=>s.servers.get(n), set, update, remove}))}` —
    map VALUES ARE THE FULL CONFIG (`set` stores `structuredClone(config)`).
19. **Remote config shape carries the url**: live OpenAPI `Mcp.RemoteConfigEncoded`
    = `{type,url,headers,oauth,disabled,codemode,timeout,protocol}`,
    additionalProperties:false (`Mcp.ServerConfig` = tagged union local|remote).
    So the config view can answer what the status view never can.
20. **Why the shipped chain died (incident mechanism, schema-pinned live)**:
    `ctx.mcp.list()` (endpoint `GET /api/mcp` → service `MCP.servers`, built
    from the LIVE connection map) returns `Mcp.Server{name,status,integrationID}`
    additionalProperties:false — NO url, so `typeof cfg?.url === "string"` never
    matches on any v2.1.4 server; and the fallback regex-parses
    `<location>/.opencode/opencode.jsonc`, which since the 2026-10-25 fleet split
    (5dcc99dab) has 0 `admin-global-homeassistant` hits (HA lives only in the
    machine-global `~/.config/opencode/opencode.json`, re-verified 2026-10-28:
    entry `{type:"remote", url:"http://mcp-mcp-homeassistant-admin-headless.default:8080/mcp",
    disabled:false}`). Result: 94× "no URL found" in the coder pod stdout while
    the endpoint itself was live/connected.
21. **Transform callback semantics (load-bearing for the seam)**: registering a
    state transform immediately invalidates + recomputes, and the recompute
    invokes every registered callback with a fresh editor over state rebuilt
    from `initial()` — callbacks PERSIST and re-fire on later recomputes until
    disposed (that is exactly how `ConfigMCPPlugin` keeps repopulating config
    entries after `reload`). Two consequences: (a) the callback has fired before
    the transform promise resolves when no batch is active (plugin setup is not
    in a batch — the boot-time internal `ConfigMCPPlugin` transform works the
    same way and demonstrably populates state), (b) **a callback that throws
    fails the whole registration group** (`A(group,…)` removes all its
    registrations; a failed group then makes future transforms a no-op) ⇒ the
    plugin's callback must catch inside itself. Capture must be idempotent
    across re-fires; always dispose after reading.
22. **The config view includes machine-global servers — the fix's whole point**:
    internal plugin `opencode.config.mcp` (`ConfigMCPPlugin.register`) enumerates
    ALL config documents (`entries().filter(type==="document")` — global then
    project layers), merges each doc's `info.mcp.servers` into a Map (first
    doc wins per name) and writes them into the MCP state via `editor.set(name,
    {...config, timeout})`. Every server the running server KNOWS about is
    therefore visible through `ctx.mcp.transform` regardless of which file
    declares it; the status-only `list()` cannot be the source of truth for a
    URL, the state can. Corroborated by the incident evidence itself: `list()`
    DID return `admin-global-homeassistant` (status connected) — the same state
    feed — so the config view necessarily contains its entry.
23. **Docs are not the authority for the v2 ctx (recorded again)**:
    opencode.ai/docs/plugins, fetched 2026-10-28 ("Last updated: Oct 27, 2026"),
    still documents only the V1 plugin ctx (`{project, client, $, directory,
    worktree}`) — there is NO docs page for `ctx.mcp.transform`. Grounding =
    binary strings + live OpenAPI + shipped dist types, same method as
    Grounding #7–#17.
24. **No-caching is a feature, cost bounded**: resolving per push (register →
    capture → dispose) means a fleet config edit (URL move, tier rename) takes
    effect on the NEXT push without a service restart. Cost = one state
    recompute per resolution, bounded by the cooldown (≤ 1 push per session per
    15 s). Rejected alternative: memoizing the URL (stale forever on config
    change — DECISIONS 2026-10-28).
25. **Cluster-internal endpoint needs no headers**: the resolved url is a
    headless-service DNS (`http://mcp-mcp-homeassistant-admin-headless.default:
    8080/mcp`) reachable from inside the coder pod (where the server process —
    and this plugin — runs); the global config entry carries no `headers`/auth,
    matching the plugin's header-free JSON-RPC path. `headers` passthrough and
    `disabled`-filtering are explicitly OUT of scope (plan Risks).

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
  .opencode/plugin/question-notify/index.ts` — **SUPERSEDED by C03 for the
  `permission.replied` half only (see the C03 pins below); `permission.updated`
  and `form.created` must STAY absent.**
- **C02** regressions: every C01 command above must still pass (AC 6)
- **C03** grep pin INVERTED — replied wiring must now be present:
  `grep -q 'permission\.replied' .opencode/plugin/question-notify/index.ts`
- **C03** grep still-absent (the surviving half of C02's pin): `! grep -qE
  'permission\.updated|form\.created'
  .opencode/plugin/question-notify/index.ts`
- **C03** test suite: `node --test 'tests/opencode/*.test.ts'` exits 0 — legacy
  file still contributes exactly 35 (md5 pin unchanged); the permission file's
  timer matrix (rewritten P-series + new D-series) covers pending/cancel
  semantics WITHOUT any real ≥15 s sleep: seam-level tests inject fake
  `schedule`/`cancel`/`timers` deps into `handlePermission`, and setup-level
  tests use the `OPENCODE_NOTIFY_PENDING_MS` env override that `setup()` reads
  when building its deps (set → `openSetup` → unset, so the knob cannot leak)
- **C03** load+shape: C02's extended command unchanged (`handlePermission` must
  remain a named export; no new REQUIRED exports — the timer deps are an
  internal contract the tests pass through the existing deps object)
- **C03** regressions: every C01 command and every surviving C02 command
  (asked-present grep, md5 pin, lifecycle/load+shape) must still pass
- **C04** seam tests: `node --test tests/opencode/ha-mcp-url.test.ts` exits 0
  (H1–H9 — `haMcpUrl` is a NAMED EXPORT in C04, injected-fake ctx; discovery
  is pure, so no fetch/socket stubs exist in the battery)
- **C04** combined suite: `node --test 'tests/opencode/*.test.ts'` exits 0 =
  legacy 35 (md5 pin unchanged) + permission 41 (md5 pin unchanged — C04
  touches neither file; new coverage lives only in the seam file) + seam count
- **C04** load+shape (extends C03's again): add clause
  `||typeof m.haMcpUrl!=="function"` — module imports, `haMcpUrl` is a named
  export taking one `ctx` param, all previous clauses still pass
- **C04** grep pins: `grep -q 'no URL found'` (marker byte-kept — the
  permission setup-level tests count pushes through it, and it is the
  incident's diagnostic line) and `grep -q 'transform'` (config-view wiring);
  retired-leg gone: `! grep -qE 'readFileSync|opencode\.jsonc|node:fs'
  .opencode/plugin/question-notify/index.ts` (covers the header prose too)
- **C04** regressions: every C01 command + `permission.asked`/`permission.replied`
  present + `! grep -qE 'permission\.updated|form\.created'` must still pass
- **C04** anchor retirement (explicit): the sibling hygiene ticket's
  comment-only snapshot anchor on the plugin file (`3129d1d9…`) is SUPERSEDED —
  C04 changes CODE by definition. The plugin md5 moves (plan-time value
  `b081f4ed3733a2ae6477a7e7c9b69dac`, 453 lines, uncommitted C03+hygiene state
  in this worktree); the guards are the grep/test matrix, never a snapshot diff.
- smoke (LIVE, **user-owned** — do not run from the pipeline): restart the
  OpenCode service, open a top-level session, finish one turn → "finished"
  push; finish with a forced provider failure after retries → exactly one
  "stopped" push; run a subagent → no lifecycle pushes. **C02:** trigger a
  permission ask in ANY session (top-level or pipeline child) by invoking a
  tool the ruleset gates with `ask` → one "needs approval" push with the
  action/resource excerpt; several near-simultaneous asks → one push per
  session per 15 s; a question push immediately followed by an ask for the
  same session → one push total (shared cooldown). Watch for
  `[question-notify]` lines — **location superseded by C04 (FRICTION
  2026-10-28): the opencode log is the WRONG file** (`~/.local/share/opencode/
  log/opencode.log` never carries plugin stderr — it goes to the server's
  stdout → container pipe), so read the **coder pod stdout** via
  `readonly-gpu-kubernetes` `pods_log` (GPU cluster, ns `default`).
  **C03 (changes the C02 expectations above):** with "Permissions: accept
  everything" checked, a gated tool must produce NO push; with it unchecked, an
  ask left unanswered for 15 s gets one "needs approval" push (~15–20 s after
  arrival), while a manual reply/reject/always within 15 s stays silent; two
  near-simultaneous unanswered asks for one session → one push.
  **C04 (the live fix check — user-owned, after a service restart because
  plugins load at server start):** trigger ANY push path (question / finish /
  fired approval) and confirm NO NEW `[question-notify] no URL found` lines in
  that pod stdout — the single fix in `haMcpUrl` restores all three triggers
  at once (they share `sendHANotify`).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Event subscription + finished/crash notify with testable seam | M | 1 | [] | single chunk: subscription loop, topology filter, both handlers and the test seam are one mergeable change; splitting would leave a chunk that cannot ship alone |
| C02 | Approval-ask push on `permission.asked` (all asking sessions) | M | 2 | [C01] | reuses C01's shipped subscribe loop, cooldown Map, `truncate`/`sendHANotify` plumbing and test-seam conventions; edits the same plugin file + tests dir, so it cannot land before C01 exists |
| C03 | Pending-only approval push: 15 s per-request timer, `permission.replied` cancels | M | 3 | [C02] | rewrites C02's `handlePermission` in place (asked→schedule instead of push; replied→cancel), extends its deps object and the loop cleanup; cannot land before C02's asked dispatch + shared cooldown gate exist |
| C04 | ha-mcp URL discovery via the ctx MCP config view (live-incident fix) | M | 4 | [C03] | edits the same plugin file's `haMcpUrl` (currently the C03 working-tree version, uncommitted in this worktree) and adds a third test file next to the two C01–C03 pinned ones; landing before C03 would conflict on the file and the shared `sendHANotify` boundary its tests pin |

## Wave order
1. C01 (only chunk) — **done** (2026-10-24; shipped, final review APPROVED).
2. C02 (replan 2026-10-26) — depends only on C01 (wave 1, complete): same-file
   extension of the live loop + shared per-session cooldown + notify helpers.
3. C03 (replan 2026-10-27) — depends only on C02 (wave 2, complete, landed on
   this branch): same-file rewrite of C02's push-on-arrival into a pending-only
   push, plus the replied-cancellation and timer cleanup in the same setup.
4. C04 (replan 2026-10-28) — depends on C03 (wave 3, complete; its code is
   UNCOMMITTED in this worktree alongside the sibling hygiene ticket's comment
   edits — all three land in the same PR): replaces the broken ha-mcp URL
   discovery with the grounded v2.1.4 MCP config view, adds the `haMcpUrl`
   named-export seam + `tests/opencode/ha-mcp-url.test.ts`. The agent-test
   stage is REQUIRED for C04 (behavioral code change), unlike the hygiene
   ticket's doc-only run. FRICTION 2026-10-28's diagnostic entry closes only
   when C04 lands and the user restarts the service.

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
- **C03** a `permission.replied` lost in an event-stream gap (reconnect window)
  means the timer fires and an already-answered ask gets one spurious push ~15 s
  late; bounded and self-limiting (the cooldown gate suppresses a follow-up), and
  the failure direction is deliberate: never silently drop a genuinely-unanswered
  ask. Accepted for a single-user homelab phone push.
- **C03** unanswered asks now notify 15 s after arrival instead of immediately —
  the user's explicitly chosen window ("Actually, make that 15s"), accepted as the
  core behavior change, pinned by the new timer tests.
- **C03** the deferral can silently VACUATE C02's setup-level P4/P5 tests (a
  pending timer simply hasn't fired within the old test window, which looks like
  "correctly suppressed"); agent-test must rewrite them against the fake-timer
  deps / env knob so they still prove the cooldown sharing and loop wiring.
- **C04** version risk re-weighted: this fix keys on the v2.1.4 plugin ctx
  (`ctx.mcp.transform`), verified in the installed binary + shipped 2.1.2 dist
  types; if the live service ever runs a build WITHOUT that ctx surface, leg 2
  (list scan) and the null ⇒ stderr path keep today's failure mode (loud,
  harmless) — strictly no regression versus the shipped code. The transform
  promise resolving before the callback fired (registration inside an active
  state batch) would degrade one push attempt to the stderr path, never a
  crash; plugin setup is not such a batch (the boot-time internal
  `ConfigMCPPlugin` transform runs under identical conditions and works).
- **C04** a throwing editor callback would poison the plugin's state
  registrations for the process lifetime (Grounding #21) — mitigated by the
  in-callback catch pinned by test H6, not by convention alone.
- **C04** `headers`/`oauth` fields exist on remote configs but the plugin keeps
  its header-free raw JSON-RPC path (the admin HA endpoint is unauthenticated
  cluster-internal DNS — Grounding #25); if auth is ever added, that is a
  separate ticket, as is any `disabled`-entry filtering (H8 pins: disabled
  entries DO resolve).
- **C04** the fix is inert until the user restarts the OpenCode service
  (plugins load at server start) — AC 12 is user-owned verification; merging
  C03+C04 without this chunk would NOT restore pushes (`haMcpUrl` unchanged),
  which is exactly why the incident stayed silent after the deployed C02 code.
