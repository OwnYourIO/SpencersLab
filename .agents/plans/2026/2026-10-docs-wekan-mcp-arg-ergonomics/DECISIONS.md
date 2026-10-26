# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Standalone docs ticket minted from cf-70's friction item 3 by agent-board-coord;
  non-`cf-` slug per repo convention for friction-follow-up tickets
  (`2026-10-bug-board-coord-dev-boards-allow`, `2026-10-bug-tests-edit-perms`).
- Evidence stamp on every documented claim: `verified 2026-10-26 · wekan-mcp 4.1.3
  · dev boards endpoint`; live-probed vs source-only claims marked distinctly.
- Docs cite `containers/wekan-mcp/wekan_mcp/server.py` by FUNCTION NAME anchors —
  line numbers drift and would make the suite brittle.

## Decisions
- 2026-10-26 plan: EDIT SURFACE = `skills/wekan-api/**` hand-edited directly.
  Diagnosis (verified by listing): skill loads from `skills/wekan-api/`
  (self-written area, `.opencode/opencode.jsonc` `"skills"` paths include
  `skills/`); it is NOT under `.rulesync/skills/` (no rulesync generation to
  regenerate), NOT under `.agents/skills/` (not third-party vendored) and absent
  from `skills-lock.json` (no integrity pin → the re-fetch-at-new-SHA vendoring
  path does not apply). Rejected: routing the fix through rulesync or a
  skills-lock re-vendor — machinery that doesn't own this skill.
- 2026-10-26 plan: GROUND TRUTH = launch-brief live signatures (source material)
  cross-checked against the in-repo server source, which independently confirms
  every fact: `list_checklists(board_id, card_id)` (brief's arrow notation was
  ambiguous — source settles it), `get_checklist` item field `finished`,
  `toggle_checklist_item` arg+response `done` (REST body `isFinished` both ways),
  `add_comment(…, comment)`, `move_card` has NO bare `swimlane_id` param (its
  optional cross-swimlane param is `to_swimlane_id` — source-verified only, not
  live-probed; docs must say so), `set_card_custom_field(…, value)`.
- 2026-10-26 plan: CONTENT AT TWO LAYERS — compact "Call shape" block in
  SKILL.md's MCP section AND full table in references/wekan-mcp-ops.md.
  Rejected: table in the reference file only — the friction happened at intake
  (agents burned round-trips BEFORE thinking to consult a reference); SKILL.md
  is the eagerly-loaded surface where "board_id nearly everywhere" must live.
  Anti-duplication AC (normative text exactly once) keeps the two layers honest.
- 2026-10-26 plan: DRIFT PIN = new statics-only suite `tests/wekan-mcp/arg-surface.sh`
  mechanically greps each documented arg name out of the server.py `def`
  signature (mirrors `tests/wekan-mcp/tools.sh` precedent, incl. its README+
  skills/wekan-api parity-check convention). Rejected: editing tools.sh itself —
  it's a historical contract of the board-coord-intake ticket; sibling script
  keeps one branch, one concern.
- 2026-10-26 plan: C02 (AGENTS.md self-written-skills list += wekan-api) kept IN
  this ticket rather than dropped as hygiene: the discovery friction it removes
  ("where does this skill live, may I edit it?") is this ticket's own first
  diagnostic step; the rulesync generate+idempotence commands ride only here.
  Rejected: folding it into C01 (mixes hand-edit surface with generated-surface
  machinery — different blast radius, different checks); splitting a third
  ticket (S-task with no standalone value).
- 2026-10-26 plan: NO overlap with sibling `2026-10-bug-board-coord-dev-boards-allow`
  (its files: .rulesync/subagents/agent-board-coord.md, agents-sync
  permissions.md, boards SKILL.md + generated mirrors + tests/agent-*). This
  ticket touches none. Cross-reference only; MCP-over-HTTP fallback recipe
  already exists in wekan-mcp-ops.md — not re-planned; cf-70 folder stays
  read-only (its coord re-statuses its friction item when this lands).

## Deferred / open questions (best guess recorded; never asked live — no-questions rule)
- 2026-10-26 plan: Q — mirror the table into `containers/wekan-mcp/README.md` too?
  Best guess NO: single normative home (skill) + machine-checked parity against
  source; README duplication grows drift surface. Impact if human disagrees:
  add rows to README + one grep pair to the suite — 10 minutes, no restructure.
- 2026-10-26 plan: Q — also add a call-shape pointer to `.rulesync/skills/boards/`
  (dev-boards consumers hit the same ergonomics)? Best guess NO for this branch:
  sibling ticket is actively editing that exact file — collision; raise as
  follow-up friction after it lands. Impact: boards-skill agents keep
  discovering args via validation errors until then.
- 2026-10-26 plan: Q — tool count "26 typed tools" in SKILL.md vs sibling probe
  "~26"? Best guess: leave as-is; dev re-checks live catalog if reachable and
  the suite (t3) pins only the 10 documented rows, not the count line. Impact:
  cosmetic if wrong.
