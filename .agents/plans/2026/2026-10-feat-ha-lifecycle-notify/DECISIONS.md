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
