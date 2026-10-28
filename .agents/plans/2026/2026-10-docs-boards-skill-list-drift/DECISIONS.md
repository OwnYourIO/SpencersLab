# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions
- Friction-minted ticket (no board card): folder `.agents/plans/2026/2026-10-docs-
  boards-skill-list-drift/`, plan file `2026-10-28-docs-boards-skill-list-drift.md`,
  `<type>` = `docs` (the deliverable is prose + a generated mirror + test admits,
  not behavior). Sibling precedents: `2026-10-docs-wekan-mcp-arg-ergonomics`,
  `2026-10-bug-*` follow-ups.
- Evidence stamps distinguish **live-probe** from **source-only** facts (cf-75's
  convention, absorbed from the docs-ergonomics draft).
- Sources in `.rulesync/`, mirror in `.opencode/` via `rulesync generate`, both in
  one commit; never hand-edit the mirror.
- Suites pin CONTENT, never sentence bytes (the coord-inwork i5 "prose treadmill"
  doctrine).

## Decisions
- 2026-10-28 plan: **the agent fixes TEXT, never board structure.** The live In
  Process swimlane holds seven lists (six pipeline + a non-pipeline `Test`
  `jNYNdCPPkX8Bs95s4`) and the board holds three swimlanes / 21 lists
  (live probe, 2026-10-28, reads only). The ticket rewords the skill's description
  to match; it does not delete, rename, archive or move anything on the board.
  Rejected: (a) "fixing" the board by removing the stray `Test` list — board
  structure is human-owned (cf-75 DECISIONS 2026-10-27 plan: drift is reported,
  never fixed by agents; the labels/checklists/rules posture says the same);
  (b) leaving the drift as a standing plan risk again — cf-75 already captured it
  twice (plan risk + FRICTION) and the user checked it as an open follow-up.
- 2026-10-28 plan: the replacement text keeps the six pipeline lists as the named
  contract set and states everything else as human-owned, drift-prone, and
  live-resolved. Rejected: swapping the frozen count for the current one
  (`Lists (seven):`) — that is the same bug re-rolled the next time a human adds a
  list; and rejected: dropping the enumeration entirely (agents need the six names
  and the "only these take part" boundary to reason about pickup and card moves).
- 2026-10-28 plan: the pickup walk is out of the edit's blast radius. Rework →
  Not Started → Low Priority is a semantic contract and stays byte-identical.
- 2026-10-28 plan: ONE chunk (S). Tasks: prose + regen (dev) and the new suite +
  scope admits (test). Rejected: splitting admits into a C02 — same files, same
  gate, no independent reviewable deliverable.
- 2026-10-28 plan: **allow-list widening is agent-test's job, not dev's** (cf-75's
  scope caveat; its run had to route two such reds back to the test session under
  the `validation_at_fault` contract). The test phase lands the admits BEFORE dev
  touches the skill, so dev never sees a scope violation it cannot legally fix.
- 2026-10-28 plan: the four interlocking sites widen in one pass — gate t14,
  rulesync-surface c8, agents-md c7 case-lists + agent-perms A9's slug loop
  (cf-75 FRICTION: "half-way widening silently reddens a suite"). A9 also gains
  `2026-10-docs-wekan-mcp-arg-ergonomics`, whose admit has been in the three blocks
  since cf-75's bookkeeping commit but unpinned by A9 — this closes cf-75's
  deferred note ("add the sixth slug when agent-test next touches those suites").
  Rejected: leaving the second slug out to keep this ticket strictly single-concern
  — it is one word on one line and it is the exact site the deferred note names.
- 2026-10-28 plan: no new prose pin on the neighbouring bullets; the guard
  inventory is recorded in the chunk file's "Forbidden in the new text" list with
  the check id that owns each (c4/c10/c12/t3/t19/i3/m3/m5/s2), so dev learns the
  blast radius without the plan restating those suites.
- 2026-10-28 plan: single owner per fact — `skills/wekan-mcp/SKILL.md` keeps the
  Board context schema and its drift note; `boards` keeps the board-structure
  description and cites the schema. Rejected: restating the re-resolve rule or the
  list-id table in `boards` (a second owner of one fact drifts on its own).

## Deferred
- 2026-10-28 plan: cf-75's FRICTION item 2 stays `open` in cf-75's folder until
  this ticket's done gate, where **coord** re-statuses it `fixed` with this folder
  as the reference (OQ1) — no other role may write another ticket's plan folder.
- 2026-10-28 plan: `tests/pipeline-models/surface.sh` M3 is red at this branch's
  baseline (its own "red before C06" flash-next catalog work). Untouched here; the
  commands that need that suite scope to `m5`. Whoever lands C06 owns M3.

## Measured during planning (2026-10-28) — facts, not decisions
- The scope blocks collect `{ git diff --name-only "$BASE"; git ls-files --others }`,
  so an untracked plan folder trips them at the DEFAULT `BASE=HEAD` too, and the
  child-runners (`wekan-mcp/board-context` t6 → gate.sh, `pipeline-gates/validation-fix`
  t7 → rulesync-surface.sh) multiply three cause sites into five visible reds. Plan
  consequence: the coord commits this folder, and the test phase's admits land
  before dev.
- The executable bit is inconsistent across this guard tree — `gate.sh`,
  `pipeline-gates/validation-fix.sh` and `standalone-agents/surface.sh` are
  mode 644 while `rulesync-surface.sh`/`agents-md.sh` are 755. Every suite in the
  plan's Commands is therefore written `bash <suite>`; a bare path invocation of a
  644 one dies with rc=126 and reads like a defect.
- `tests/standalone-agents/surface.sh` does not child-run the scope trio: green with
  this folder present. It stays in the regression list because the plan's Commands
  mirror cf-75's set, not because this edit needs it.
