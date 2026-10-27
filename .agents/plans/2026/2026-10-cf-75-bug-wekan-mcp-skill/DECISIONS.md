# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions
- Card-driven run: no run tag; every surface named from the full cf- slug
  (folder `2026/2026-10-cf-75-bug-wekan-mcp-skill`, worktree + branch
  `cf-75-bug-wekan-mcp-skill`); slug FINAL only after the batched round
  (OQ1).
- Evidence stamps on every documented call-shape claim: live-probe vs
  source-only, marked distinctly (docs-ergonomics ticket's convention,
  absorbed).
- server.py cited by FUNCTION NAMES, never line numbers (drift posture).
- Generated surfaces: edit `.rulesync/` sources, `rulesync generate`,
  commit source+output together; `.opencode/plugin/` stays hand-managed.

## Decisions
- 2026-10-27 plan: SKILL SPLIT, not absorb — new `skills/wekan-mcp/` owns
  the agent-side MCP working surface (tiers, call shapes, projections,
  failure playbook, context-block schema); `skills/wekan-api/` keeps raw
  REST semantics, server internals, and `references/wekan-mcp-ops.md`
  (rules-engine + MCP-over-HTTP recipe stay there, referenced not
  copied). Rejected: merging everything into wekan-api (its description
  and eager content are REST-first; the card asked for a generic
  board-MCP skill) and duplicating (two owners of one fact). Extra
  constraint: `tests/wekan-mcp/tools.sh` t5/t9 green-pin wekan-api's
  tool-surface text — edits stay outside those regions.
- 2026-10-27 plan: SUPERSEDE draft ticket `2026/2026-10-docs-wekan-mcp-arg-ergonomics`
  (never executed): its call-shape SKILL-block + reference-table content
  lands inside skills/wekan-mcp (C01), its AGENTS.md skills-list task
  rides C01 too. Rejected: running it as-is after this ticket (it would
  put the same facts in wekan-api — the split decision makes that the
  wrong home). Flagged to the user as OQ2 because its folder + follow-up
  card are the user's to retire/close.
- 2026-10-27 plan: ONE Board context block schema, defined normatively
  once in skills/wekan-mcp; two producers (C03 command manual/schedule-
  paste; C04 plugin auto-inject) and one consumer rule (boards skill,
  C03). On any id-shaped call error the consumer re-resolves live —
  board structure drifts (live probe found a non-pipeline "Test" list in
  In Process that the boards skill's six-list text predates: reported,
  never fixed by agents — board structure is human-owned).
- 2026-10-27 plan: agent-board = thin `mode: primary` worker; grants:
  dev-boards ONLY MCP (no admin-global-wekan fallback — catalog-gap root
  cause fixed by cf-75's sibling 9081717e9), execute allow, question
  allow, everything else (shell/edit/subagent) denied; no pipeline-role
  skills. Rejected: making it a coordinator variant (no subagents, no
  STATE.json ownership) and a variants trio (single-purpose agent).
- 2026-10-27 plan: validation_at_fault new contract (C02): coord routes
  the fix to the test session WITHOUT a question; the functionality ask
  rides the test session's own judgment (a fix that would change
  functionality/contradicts acceptance criteria → NEEDS_INFO → coord
  escalates + possible needs-replan). Rejected: coord pre-judging from
  the reviewer's BLOCKED text (reviewer never edits and may
  under-describe). Card #74's ask is this same change (OQ3).
- 2026-10-27 plan: plugin shipped last + degrade-safe (C04) with
  live-fire proof as an AC; if the command/schedule admission path skips
  prompt hooks the plugin ships default-OFF and the C03 paste path is
  the feature. Docs evidence 2026-10-27: prompt hook runs at admission,
  command prompts via session.prompt run it, synthetic/shell do not.
- 2026-10-27 plan: lifecycle consumption — legacy Research checklist
  "After Planning" = standard Plan+Test+Code+Review + one research round
  after this plan (post-plan RESEARCH.md; C04 dev reads it); no Lifecycle
  stage gate; HITL PR-check honored by -local posture (push/PR user-owned).
- 2026-10-27 plan: chunking — C01+C02 independent wave 1 (disjoint files;
  shared only the rulesync regen, id order); C03 needs C01 (schema +
  skill-name citations); C04 needs C03 (schema + consumer + resolution
  sequence). agent-board+collector kept in ONE chunk (two related Ms,
  same deliverable: the board-context surface) so a descope of either
  item is a user edit of this file + chunk renumber, not surgery.

## Deferred / open questions (best guess recorded; never asked live — no-questions rule)
- OQ1 slug final confirmation (candidates in the plan).
- OQ2 retire docs-ergonomics draft + its follow-up card.
- OQ3 card #74 closed by this ticket's C02.
- OQ4 agent-board in scope (best guess yes).
- OQ5 plugin in scope (best guess yes, degrade-safe).
- OQ6 functionality-change adjudication by the test session (best guess).
- OQ7 agent-board grant breadth: dev-boards only (best guess).

## Batched round — ANSWERED + PLAN APPROVED (2026-10-27, human; folded in by plan session)
- 2026-10-27 human: ALL seven questions confirmed at the recommended best
  guesses; plan APPROVED to execute (approval itself recorded by coord in
  STATE.json — plan session did not touch `plan_status`).
- 2026-10-27 human: slug FINAL = `cf-75-bug-wekan-mcp-skill`.
- 2026-10-27 human+plan: docs-ergonomics draft RETIRED, absorbed by C01.
  Mechanism (planner call, per the user's delegation): coord-owned
  bookkeeping, not a chunk task — dev/test/review permission-wise cannot
  write another ticket's plan folder or the board, so the draft's STATE
  re-status and its follow-up-card close ride the coordinator at C01's
  done gate (spelled out in chunks/C01.md "Coord bookkeeping").
  Rejected: a dev task editing the sibling folder (silent permission
  denial at best).
- 2026-10-27 human: card #74 is covered by C02 here; **coord board-side
  duty at run end: move #74 to Review** (with this card's Review move) —
  never an agent chunk task.
- 2026-10-27 human: validation-fix adjudicator wording is now the C02
  acceptance criterion: mechanical repairs route SILENTLY back to
  `test_session`; the TEST session flags NEEDS_INFO when a fix would
  modify functionality; coord escalates only that.
- 2026-10-27 human: agent-board keeps `dev-boards*` as its only MCP grant
  — no admin-global-wekan fallback.
