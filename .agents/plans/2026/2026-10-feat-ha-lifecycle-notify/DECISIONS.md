# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Repo helm-lint validation does not apply (TS plugin change); the plan's
  "Commands" are the deterministic validations (`node --test`, ESM load check,
  greps). Live-server smoke verification is user-owned (service restart).
- Failure policy inherited from the existing plugin: notifications are
  fire-and-forget, stderr logging only, never delay or break the agent.
- 2026-10-27 coord, per final review C01+C02+C03: aislop file-too-large
  warning on the plugin (453 lines) closed as **accepted-by-design** —
  single-file convention (2026-10-24) + chunk ACs forbid new files under
  `.opencode/`; warning severity does not gate CI (errors + score floor only,
  dev state 99/100).
- 2026-10-27 coord, per final review: header :29–35 stale v2.0.32 wording is
  now self-contradicting post-C03 and **due for a one-line historical recast
  before the PR**, together with the AGENTS.md/rulesync question-notify blurb
  (`.rulesync/rules/` source + `rulesync generate`). Offered to the user as
  the PR-hygiene follow-up; non-blocking for this plan.
  CLOSED 2026-10-27 by ticket 2026/2026-10-docs-notify-plugin-hygiene (final
  review APPROVED; header recast + regenerated blurb verified against code).

## Decisions
- 2026-10-24 plan: Extend the existing `.opencode/plugin/question-notify`
  plugin (single file + exported test seam) instead of adding a new plugin
  file. Rejected: separate `lifecycle-notify` plugin — the ha-mcp URL
  discovery, JSON-RPC handshake, truncation and failure policy are all
  shared; a second plugin would duplicate them and add a second load site.
  The launcher explicitly requested extension; doc grounding showed no
  reason to override (event subscription and tool hooks coexist in one
  plugin ctx).
- 2026-10-24 plan: Crash trigger = V2-native terminal event
  `session.execution.failed` (payload `{sessionID, error:{type,message,...}}`),
  NOT a consecutive-error heuristic and NOT the V1-compat `session.error`.
  Rejected: counting `session.retry.scheduled` events per session (heuristic
  unnecessary — retries are separate events and execution.failed fires once
  when the agent actually stops); using V1-compat `session.idle`/
  `session.error` (legacy surface found in the binary's V1-compat block;
  docs define the durable execution events as the contract). Consequence:
  single fatal errors (no retries) also produce exactly one "stopped" push —
  matches intake #2 ("stops running").
- 2026-10-24 plan: Finished trigger = `session.execution.succeeded`
  (fires once per completed agent-loop turn = waiting for user input).
  No extra cooldown/dedup map: the event is terminal per execution by
  semantics. Rejected: `session.status` transient event (multi-state,
  noisier, V1-compat).
- 2026-10-24 plan: Top-level vs subagent discriminator = session topology
  (`Session.Info.parentID` absent ⇒ top-level), NOT the `agent-` name prefix.
  Grounded on the live v2.0.32 server: this child planner session
  (`agent-plan`) has `parentID` = coord session; the user-launched
  `agent-coord` session has none. This satisfies the scope guard (works for
  `build`/default agents in OpenChamber). The existing question notify keeps
  its `agent-*` prefix filter unchanged (acceptance: question behavior
  intact).
- 2026-10-24 plan: Test seam = plugin exports `handleLifecycle(deps, event)`
  plus pure helpers (`isTopLevel`, titles, excerpts, truncate) with injected
  fakes for session lookup + notify, so `node --test` covers the whole
  decision matrix offline. Rejected: black-box testing via a live server
  (non-deterministic, needs restart) and a mock server harness (overkill).
  The plugin keeps its current plain-object default export (user-verified
  working); not switching to `Plugin.define`.
- 2026-10-24 plan: Test file lives at repo-root `tests/opencode/`, outside
  `.opencode/` entirely. Rejected: colocating inside
  `.opencode/plugin/question-notify/` or `.opencode/tests/` — plugin
  discovery scans `.opencode/plugin(s)/` trees (both spellings appear in the
  binary; exact glob unverifiable) and could import a stray `.ts` as a plugin
  entry, risking server startup.
- 2026-10-24 plan: No per-location/event filtering — every top-level session
  finishing on this shared server gets a push (single-user homelab; matches
  "the main agent in OpenChamber"). Rejected: filtering events by
  `event.location.directory === ctx.location.directory` (would miss the
  user's sessions in other worktrees/machines sharing the service).
- 2026-10-24 plan: `session.execution.interrupted` (user/shutdown/superseded/
  inactivity) never notifies. Rejected: notifying on `shutdown`/`inactivity`
  — not requested; user-initiated interrupts must stay silent.
- 2026-10-26 plan(C02): Approval-ask trigger = durable `permission.asked` event
  on the existing `ctx.event.subscribe` stream (v2.1.4 grounding, plan
  Grounding #7–#12). Rejected: V1-compat `permission.updated` bus event (zero
  string hits in the installed binary — pre-2.x surface, gone); a
  `ctx.permission` plugin hook (no such plugin-ctx namespace exists; all
  `permission:{` hits are the HTTP/RPC client and the TUI state cache);
  `session.permission.*` events (those strings are SDK method paths for
  list/get/create/sync/reply, not event types); `execute.before` (asks are
  published inside a tool's `assert(…)` by the permission service, never by a
  permission-named tool — the hook fires on executes, not on blocks);
  `form.created` (the elicitation system the question tool already covers via
  the existing tool hook — subscribing both would double-push; AC 5 grep-pins
  the absence). Server-side precision proven: publish happens only when the
  ruleset effect resolves to `ask`, once per request ID (duplicate-ID guard).
- 2026-10-26 plan(C02): Scope = ALL asking sessions (pipeline `agent-*` children
  included), deliberately diverging from lifecycle's top-level-only filter.
  Rationale: a session blocked on approval is waiting for a human regardless of
  parentage — suppressing child asks re-creates exactly the gap the user
  reported ("privs aren't triggered" during pipeline runs). The top-level-only
  rule exists to damp per-turn finish noise; approval asks are rare and
  actionable, and the 15 s cooldown bounds burst volume. Intake #1
  (user-confirmed).
- 2026-10-26 plan(C02): Cooldown = the SAME per-session `lastNotified` Map as
  the question path, extracted into one `allowPush(key)` gate inside `setup`,
  same key namespace (sessionID). Consequence: a question push and a
  near-simultaneous approval ask for one session yield a single phone push —
  accepted intentionally (intake #2: burst → one push; the phone cares about
  the session, not the trigger class). Rejected: separate per-trigger maps
  (double-pushes on question+ask races) and per-trigger key namespacing
  (`question:<id>` vs `permission:<id>` defeats the stated burst requirement).
- 2026-10-26 plan(C02): Lookup-failure policy = PUSH with the existing
  `"session"` fallback label, unlike lifecycle's suppress-on-unknown. That
  suppression exists to avoid pinging about unverifiable TOPOLOGY; approval
  pushes need no topology decision, and silently dropping a push for a blocked
  session is the worst failure mode for this feature. Stderr log on the failed
  lookup preserves diagnosability.
- 2026-10-26 plan(C02): Excerpt contract = `message` → `action + first ≤3
  resources` → V1 twin (`permission + patterns`) → `"permission request"`;
  `metadata` never rendered (edit asks embed whole diffs — noise on a phone).
  The payload lacks a tool display name; `action` IS the permission category
  (shell/edit/read/…), the best available degrade per intake #3. Cap stays at
  the notify boundary (`truncate`, 240).
- 2026-10-26 plan(C02): Grounding re-pinned against the INSTALLED v2.1.4 (the
  CLI self-updated from the 2.0.32 C01 was planned against — discovered live at
  replan). C01's full suite re-run green (35/35) on this branch first; C01's
  shipped text and greps are untouched. Both payload variants (V2 native,
  V1-compat twin sharing the `permission.asked` type string) get tolerant reads
  because the service build live at smoke time is user-owned.
- 2026-10-27 plan(C03): Pending-only approval-push semantics — `permission.asked`
  starts a per-request-id timer; a `permission.replied` matching that id cancels
  the push; the push fires only if the ask is STILL PENDING when the timer
  expires. Grounded (plan #13–#17): the server's single Asked publish-site is
  oblivious to client auto-approval (the observed bug = OpenChamber's "accept
  everything" answers milliseconds after `asked`, on the client side); every
  resolution path emits `replied` (once/always/reject, save-rule batch,
  shutdown-reject), so the plugin cancels on ANY reply value without filtering
  the outcome — a human saying "no" is a human who answered. Rejected:
  push-on-arrival + a follow-up "resolved" push (double noise, the exact bug
  reported); keeping arrival-push with a shorter delay (still spams
  accept-everything users); re-grounding the ruleset to `allow` server-side
  (not the user's config to change from this repo, and it would disable the
  approval UI the user wants).
- 2026-10-27 plan(C03): Timer window = 15 s, module constant
  `PENDING_NOTIFY_MS = 15_000` kept SEPARATE from `COOLDOWN_MS` (same literal
  number, different concepts — pending-detection vs burst-suppression; merging
  them couples two user-visible behaviors). 15 s is the user's explicit choice
  ("Actually, make that 15s" — second answer in intake). Offline determinism:
  seam-level tests inject fake `schedule`/`cancel`/`timers`/`pendingMs` into
  `handlePermission`'s deps; setup-level tests use an
  `OPENCODE_NOTIFY_PENDING_MS` env override read INSIDE `setup()` (not at module
  load) so loop/cleanup wiring is provable without any test sleeping ≥15 s.
  Rejected: real-timer waits (suite runtime + flakiness), ctx.options plumbing
  (no v2.1.4 options surface grounded), injecting timers only at seam level and
  leaving setup-level P4/P5 rewritten into vacuous green (they must still prove
  the shared Map and loop dispatch).
- 2026-10-27 plan(C03): Cooldown stamp moves to the actual push attempt — the
  `allowPush` gate is consulted inside the timer callback, not at asked arrival;
  a cancelled ask consumes nothing. Consequences accepted: a cancelled ask does
  not suppress the next same-session push, two overlapping unanswered asks both
  fire but the gate admits only the first (one push per session per 15 s
  preserved), and C02's P3 "gate-first-before-lookup" ordering survives verbatim
  INSIDE the deferred path. Question-path behavior is observably UNCHANGED (it
  already stamped on attempt); the deferral applies only to the approval path.
  Rejected: stamping at arrival (cancelled asks burn the cooldown — the user
  would get silence exactly when the phone should ring).
- 2026-10-27 plan(C03): C02's grep pin `! grep permission.replied` (asked-only
  subscription, AC 5) is INVERTED by design — `permission.replied` must now be
  present (cancellation wiring), while `permission.updated` and `form.created`
  stay absent. Recorded here because chunks/C02.md (done) is kept verbatim and
  its AC 5 text now describes the pre-C03 contract; the plan Commands and
  chunks/C03.md AC 4–5 are the authority for C03 reviews.
- 2026-10-27 plan(C03): Wording decision (coord left it to plan, pinned by
  tests): the fired push keeps the EXISTING byte-pinned title `OpenCode:
  <agent> needs approval` — the ask genuinely needs approval when the timer
  fires; "still waiting" was rejected (changes four shipped title strings for
  zero phone-side information gain, and P1's shipped assertion survives
  unedited). The excerpt contract (P2 precedence, 240 cap) is unchanged,
  rendered from the asked payload captured at scheduling time (replied carries
  no excerpt-worthy content beyond the request id).
- 2026-10-28 plan(C04): ROOT CAUSE recorded — all triggers went silent after
  the 2026-10-25 fleet split (5dcc99dab): `ctx.mcp.list()` on v2.1.4 returns
  the status view `Mcp.Server{name,status,integrationID}` (additionalProperties
  false — can never carry a url), and the project-jsonc fallback parses a file
  with 0 HA hits (94× "no URL found" in coder-pod stdout; endpoint itself live
  — FRICTION 2026-10-28 diagnostic). Fix = resolve the URL through the plugin
  ctx's MCP CONFIG view (plan Grounding #18–#25: `ctx.mcp.transform(editor =>
  editor.get(MCP_SERVER_KEY)?.url)`; the state is fed by `ConfigMCPPlugin` from
  ALL config documents, so machine-global servers appear). Merging C03 alone
  would NOT restore pushes — `haMcpUrl` is byte-identical in C03.
- 2026-10-28 plan(C04): Rejected URL-discovery alternatives (user intake
  decisions, recorded per launch instruction): parsing the machine-global
  `~/.config/opencode/opencode.json` (duplicates a machine-local file read and
  drifts with every fleet edit — the file is deliberately NOT version
  controlled); a plugin-option URL hardcode (violates the plugin's founding
  no-hardcode principle and pins an environment detail into repo config);
  keeping `list()` as primary (schema-proven dead on v2.1.4); adding per-trigger
  URL logic (rejected by design: every push path already shares the ONE
  `sendHANotify`/`haMcpUrl` chain, so one fix restores question, lifecycle and
  approval together — AC 10 pins the single boundary).
- 2026-10-28 plan(C04): Discovery-chain composition — config view PRIMARY,
  the existing tolerant `list()` scan DEMOTED to a compat fallback (kept
  verbatim: zero cost, covers builds where a list-shaped view might carry
  config, pinned by test H4), the project-jsonc parse RETIRED entirely (it only
  saw the project file — exactly the blind spot that hid the HA server; the
  config view is a strict superset; also drops the `node:fs` dynamic import).
  `haMcpUrl` becomes a NAMED EXPORT test seam (injected fake ctx ⇒ `node
  --test` covers resolution offline; the discovery function has no transport,
  so no socket stubs exist).
- 2026-10-28 plan(C04): No caching of the resolved URL — re-register/resolve/
  dispose per push (H9 pins it). Cost = one state recompute per push attempt,
  bounded by the cooldown (≤1 push/session/15 s); benefit = a fleet config
  edit takes effect on the NEXT push with no restart. Rejected: memoization
  (a moved URL would stay broken until a service restart — the very failure
  class that made this incident silent for days).
- 2026-10-28 plan(C04): Editor-callback hardening rules (from binary Grounding
  #21, not style): the transform callback must NEVER throw — a throwing
  registered callback fails the plugin's whole state registration group for
  the process lifetime ⇒ in-callback try/catch pinned by H6; capture must be
  idempotent across callback re-fires (recomputes re-run live registrations —
  that is how `ConfigMCPPlugin` itself works); Registration is always disposed
  in a finally, dispose rejection swallowed (H7). `disabled: true` entries
  still resolve (raw JSON-RPC bypasses the server's connection state — H8
  pins); `headers`/`oauth` passthrough explicitly out of scope (endpoint is
  unauthenticated cluster-internal DNS — Grounding #25).
- 2026-10-28 plan(C04): Validation-pin split for C04 (launch instruction): the
  sibling hygiene ticket's comment-only snapshot anchor on the plugin file
  (`3129d1d9…`) is EXPLICITLY RETIRED — C04 changes code by definition (live
  plan-time value `b081f4ed3733a2ae6477a7e7c9b69dac`, 453 lines). The pins that
  REMAIN and bind C04: 76-test suite green (legacy exactly 35 + permission
  exactly 41), legacy test byte-identical md5 `8b5d8382…`, and
  `tests/opencode/permission-ask-notify.test.ts` md5 `0a522f0f…` stays
  byte-identical because C04's new coverage goes to a NEW file owned by
  agent-test (`tests/opencode/ha-mcp-url.test.ts`) — the permission file is
  agent-test's to edit only if its setup-level expectations break, and by
  design they cannot: those fakes pass ctx objects WITHOUT any `mcp` property,
  and the new chain must still resolve exactly to `null` ⇒ the same
  "no URL found" push-counting boundary (AC 8/H5 pins this at the seam; the
  untouched 41-green permission file under AC 2 pins it end-to-end). The
  `no URL found` marker wording is therefore byte-pinned (AC 6): the
  permission tests count pushes through it.

## Deferred
- Per-agent or quiet-hours configuration for lifecycle pushes (options via
  plugin `options` in opencode.jsonc) if push volume becomes noisy.
- Broadening the question notify to all top-level sessions (currently
  `agent-*` only) — out of scope for this ticket; decide after the lifecycle
  discriminator is proven in production.
- 2026-10-24 review(C01) minor: silent skip when `ctx.event?.subscribe` is
  absent — add a one-line stderr log so the user-owned live smoke stays
  diagnosable. Non-blocking; fold into a later plugin touch or close as accepted.
- 2026-10-24 review(C01) nit: `"session"` fallback string for an unknown agent
  name in the push title. Cosmetic.
- 2026-10-26 final(C01+C02) minor: plugin header comment (index.ts:31) still
  says "the installed CLI (v2.0.32) predates the checked types" while the
  v2.1.4 re-grounding note sits at :38–39 — behavior-neutral stale wording;
  fix on the next plugin touch.
- 2026-10-26 final(C01+C02) doc: AGENTS.md question-notify blurb (rulesync
  source `.rulesync/rules/`) now understates the plugin (lifecycle + approval
  pushes). Update the source and `rulesync generate` alongside the PR, or as
  a separate hygiene ticket.
- 2026-10-28 dev(C04): plugin header :52–54 "watch opencode.log" note points
  at the wrong file — plugin stderr goes to server stdout → coder-pod pipe
  (readonly-gpu-kubernetes pods_log, ns default) per FRICTION 2026-10-28.
  One-line correction owed on the next plugin touch.
- 2026-10-28 dev(C04): docs-vs-binary conflict — v2 docs say plugins reload on
  config save, C04 Grounding #23 (binary) pins restart-required. Implementation
  followed the binary grounding; the user's AC 12 smoke settles it (if pushes
  work pre-restart after a config edit, re-word the AC 12/restart note).
- NOTE 2026-10-28 coord: the two 2026-10-26 deferred doc items above (stale
  v2.0.32 header wording; AGENTS.md blurb) are CLOSED — done and APPROVED in
  sibling ticket 2026/2026-10-docs-notify-plugin-hygiene (uncommitted here,
  lands in the same PR).
