# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Docs and tests cite `server.py` **function names, never line numbers** (the
  wekan-mcp skill rule; the call-shapes t4 check greps out `L<digits>`).
- New docstring/doc facts stamp the version they were source-checked against —
  the deployed WeKan is **v12.64** (chart 12.65.0, `services/home/prod/Chart.yaml`);
  stale "v9.99" stamps elsewhere are historical and not this ticket's job.
- "Tests" here are statics-only bash suites (`ast` + greps, no fastmcp import,
  no network, no pytest harness) — the repo's established container-suite posture.

## Decisions
- 2026-10-29 plan: D1 — tool arg is `title`, not the card sketch's `list_title`.
  Every other create tool takes `title` (create_card, create_rule, add_checklist);
  no consumer is wired yet (#76 plugin does not call create_list), so the sketch
  wording is descriptive. Rejected: `list_title` — would make the registry
  arg-naming inconsistent for zero benefit.
- 2026-10-29 plan: D2 — include optional `position` (0-based, from left), applied
  as a second REST leg (`POST .../lists/:listId/move` without `toBoardId` =
  same-board reposition; verified present on the deployed v12.64 tag). The card
  ask names "sort placement" as an option. Failure of the leg reports
  `positioned:false` + `position_error`, never fails the create — precedent
  create_card's default_checked outcome buckets. Rejected: append-only tool
  (contradicts the ask); exposing raw `sort` (the create route has no sort param;
  the move leg is the only REST-able placement control).
- 2026-10-29 plan: D3 — response hydrates from the single-list GET
  (`{id,title,swimlane_id,sort,positioned}`; degrade-to-null on read-back failure,
  precedent list_lists). Needed because a caller that omitted `swimlane_id` must
  learn which swimlane WeKan actually bound (default = board's first swimlane),
  and reaper-style target resolution matches on (title, swimlane_id).
- 2026-10-29 plan: D4 — privilege posture is the existing gate: decorate
  `@_write_tool`, add zero tier-specific code; readonly never registers write
  tools. Verified in server.py (`_write_tool = (lambda fn: fn) if READ_ONLY else mcp.tool`).
- 2026-10-29 plan: D5 — NO reaper/plugin wiring and NO board mutations in this
  ticket. Per card Notes + #76 D22/D19: creating the actual "Timeout" list is
  human-owned board structure; the interim timeouts.jsonl degrade ships regardless.
  Rejected: auto-creating the list from the reaper (would silently take over
  human-owned board structure).
- 2026-10-29 plan: D6 — the doc/test count flips (26→27) ride in the same chunk
  as the tool. tools.sh t2/t5 and skill-surface.sh t4 hard-pin the registry, so
  a tool-only commit turns the suite red; "one shippable unit" forces parity into
  C01. Includes fixing wekan-api SKILL's pre-existing stale "full 25-tool
  surface" wording.
- 2026-10-29 plan: D7 — live `tools/list` probe is post-merge/user-owned
  (image :v87 pins until renovate bumps); the call-shapes row ships stamped
  `source-only` with an inline v12.64/2026-10-29 note. Docs are claims, the
  live catalog is fact — recorded, not hidden.
- 2026-10-29 coord: D8 — the batched plan-question round ratified every best
  guess: Q1 `title` (=D1), Q2 position leg included (=D2), Q3 hydrated
  response (=D3), Q4 pins flip 26→27 in this change (=D6), Q5 source-only
  stamp now (=D7); slug `cf-68-feat-wekan-mcp-create-list` kept (surfaces
  already named from it — no re-mint). User APPROVED the plan as drafted
  (2026-10-29T14:25Z) — plan_status approved, no plan rework round needed.

## Deferred
- Reaper calling create_list / human creating the "Timeout" list via the new tool
  — follow-up against card #76 / board owners, not this ticket (D5).
- Image-pin bump `wekan-mcp:v87 -> :v<run>` after merge — renovate's job per the
  container-creation convention.
- Sweeping stale "v9.99" stamps in other docstrings to v12.64 — out of scope
  (only this tool's facts are re-stamped).
