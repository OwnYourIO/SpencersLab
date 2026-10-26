# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Repo helm-lint validation does not apply (TS plugin change); the plan's
  "Commands" are the deterministic validations (`node --test`, ESM load check,
  greps). Live-server smoke verification is user-owned (service restart).
- Failure policy inherited from the existing plugin: notifications are
  fire-and-forget, stderr logging only, never delay or break the agent.

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
