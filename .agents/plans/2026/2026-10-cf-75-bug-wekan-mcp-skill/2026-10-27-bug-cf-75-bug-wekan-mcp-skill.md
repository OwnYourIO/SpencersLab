# PLAN: Better context for WeKan/Boards MCP — wekan-mcp skill, board-context collector, agent-board, coord test-fix auto-routing

feature: 2026/2026-10-cf-75-bug-wekan-mcp-skill
origin: WeKan AI-Dev card #75 `BhukC6WP3t5MfX2Gr` (board-driven run; the card
description is the request). Third claim — two earlier claims went stale
without a plan folder; slug `cf-75-bug-wekan-mcp-context` is TAKEN by a
landed sibling fix (`2026/2026-10-bug-board-coord-dev-boards-allow`,
plan_status complete). APPROVED 2026-10-27 after the batched question
round — every open question confirmed at its recommended answer (plan
file, Open questions section); coordinator records the approval state
plus its board-side duties (draft-ticket retirement at C01 done, card
#74 → Review at run end) in STATE.json.

## Goal
Stop agents from rediscovering the wekan-mcp/dev-boards call surface by
shipping a generic `skills/wekan-mcp/` skill (call shapes, projections,
failure modes — mined from the FRICTION evidence below), a
`/wekan-board-context` collector command whose output block can be pasted
into the OpenChamber scheduled-job prompt so a board-coord run starts with
board/swimlane/list/custom-field/label IDs resolved, an `agent-board`
worker that owns that surface, and (last, degrade-safe) an OpenCode plugin
that injects the same block ahead of a board-coord session's first prompt.
Separately: coord agents stop asking the user before routing a test fix
back to its authoring session — mechanical repairs route **silently** to
the `test_session`; the TEST session flags NEEDS_INFO when a fix would
change functionality and only then does coord escalate to the user
(adjudicator rule confirmed 2026-10-27, OQ6).

## Verified facts (evidence, this planning pass 2026-10-27)
- **Tool surface:** `containers/wekan-mcp/wekan_mcp/server.py` registers 13
  read + 13 write `@mcp.tool` functions (grep of `@mcp.tool` defs). Cite
  function names, never line numbers.
- **Live dev-boards probe (reads only, 2026-10-27):** board AI-Dev
  `TNQJ2BrXenZovngTS`; swimlanes In Process `jLzy39L7djCRr67SF`, Up Next,
  Farm; In Process lists = the six pipeline lists (Not Started
  `XhDyShvuwhGWzWH2z`, Executing `qZ9CLZqCRbv7NQQ6R`, Review
  `2B6wWGJ8Tetp5QWDJ`, Rework `y9tsvb3AguKWhzCoF`, Finished
  `DHw56fMKy3qyfudz4`, Low Priority `M4JS9LfaypJbB97At`) **plus a non-pipeline
  "Test" list** `jNYNdCPPkX8Bs95s4`; custom fields exactly `slug`
  `RaNeqvh9YoT4bnkZ8` + `session` `zZw4PwMoLeodJy3eT` (`list_custom_fields`
  items carry `{id, name, type}` — `name`, not `title`); `get_board` carries
  labels (Research `ysSmS5`, Ready for Work `mkbxeo`). `list_lists` items
  carry `swimlane_id` — the collector filters by swimlane.
- **FRICTION evidence base** (skill content input): cf-70 items 1/3
  (catalog absent → MCP-over-HTTP workaround; arg ergonomics:
  `board_id` nearly everywhere, checklist item state is `finished`,
  `move_card` from/to list ids + no bare `swimlane_id`, comment body arg
  `comment`); cf-52 L7 (field names `comment`, `created_at: null`;
  `list_cards_in_list` needs both ids) + L15 (`move_card` 404 on stale
  `from_list_id` — card relocated); cf-58 exit (tools/call timeouts —
  verify board state before reposting); cf-49 (deployed wekan-mcp can lag
  repo source — `default_checked` rejected on v4.1.3); lidarr L10
  (rejection posture); dev-boards-allow L9 (run-start catalog gaps class +
  scheduled launch spawning agent `code` instead of `agent-board-coord` —
  user-side schedule check, not repo-fixable).
- **Existing surface:** `skills/wekan-api/` (self-written, hand-edited)
  already hosts `references/wekan-mcp-ops.md` (143 lines: MCP-over-HTTP
  recipe, slim projections, rules engine, move-top semantics) and its
  SKILL.md MCP-tool-list text is pinned green by `tests/wekan-mcp/tools.sh`
  t5/t9 — keep those regions intact. The draft ticket
  `2026/2026-10-docs-wekan-mcp-arg-ergonomics` (plan_status draft, never
  executed) planned the same call-shape docs for wekan-api — superseded by
  this ticket (OQ2, resolved 2026-10-27: C01 absorbs it; the draft's STATE
  re-status + its board follow-up-card close are coord-owned bookkeeping —
  DECISIONS). Coord test-fix "ask the user" text lives in
  `.rulesync/skills/pipeline-role-coord/SKILL.md` (step 2.d),
  `pipeline-gates/SKILL.md`, `pipeline-role-review/SKILL.md` (final
  sentence), `agents-sync/references/{pipeline-overview,plan-and-result,permissions}.md`,
  and `.rulesync/rules/overview.md` (→ AGENTS.md). All coord variants
  (plain + `-local`/`-pr` + board family + alias twins) load these shared
  skills — no per-variant agent edits (alias rule unaffected).
- **Plugin feasibility:** OpenCode V2 server plugins expose
  `ctx.session.hook("prompt", …)` (mutable prompt draft at admission;
  "commands that submit through `session.prompt` run the hook") and
  `ctx.session.instructions.entry.put` — docs 2026-10-27. Precedent for
  raw MCP-over-HTTP from a plugin: `.opencode/plugin/question-notify/`;
  precedent for seam tests: `node --test tests/opencode/question-notify.test.ts`.
- Command frontmatter binds an agent (`.rulesync/commands/pipeline-boards.md`:
  `opencode: agent: agent-board-coord`); MCP grants use whole-name patterns
  (`- action: dev-boards*` in the board-coord sources).

## Out of scope
- Changes to `containers/wekan-mcp/` server code, its README, or any
  deployed image/values.
- The live board itself (lists/labels/checklists/rules are human-owned per
  the boards skill; the "Test" list drift is reported, not fixed).
- Machine-local config (`~/.config/opencode/`, OpenChamber schedule-job
  text edits — user-owned landing steps).
- Merge/push/PR of any kind; `-local` run: branch work stays local, PR is
  user-owned.
- Re-status of other tickets' FRICTION items (their coords' job).

## Commands
- regen (any `.rulesync/` touch): `npx --no-install rulesync generate` run
  twice — second must be a no-op — then `npx --no-install rulesync generate --check`
  => pass (c7 ladder precedent: binary is ask-gated in subagent shells)
- existing suites (must stay green): `bash tests/wekan-mcp/tools.sh` ·
  `bash tests/agent-board-coord/rulesync-surface.sh` ·
  `bash tests/agent-board-coord/agents-md.sh` ·
  `bash tests/agent-board-coord/gate.sh` · `bash tests/agent-perms/surface.sh` ·
  `bash tests/standalone-agents/surface.sh` ·
  `node --test tests/opencode/question-notify.test.ts`
- new per-chunk suites (agent-test writes; dev/review run):
  `bash tests/wekan-mcp/skill-surface.sh` (C01) ·
  `bash tests/pipeline-gates/validation-fix.sh` (C02) ·
  `bash tests/wekan-mcp/board-context.sh` (C03) ·
  `node --test tests/opencode/board-context.test.ts` (C04)
- live smoke (C03 dev+review, read-only dev-boards): run the collector
  sequence `list_boards → get_board → list_swimlanes → list_lists →
  list_custom_fields` and check the emitted block matches the schema and
  the IDs above
- scope caveat (cf-50 friction precedent): rulesync-surface/agents-md c8/c7
  allow-lists go red on any new ticket folder — widening them is
  agent-test's prerogative, never dev's
- quality gate: `$aislop` (or `npx --no-install aislop ci --changes`; if
  absent from PATH per known friction, apply the comment-slop rules
  manually to every touched file and record that in RESULT)
- surface check: `git diff --name-only $(git merge-base main HEAD)..HEAD` ⊆
  the chunk's declared files; `.opencode/` edits may only ever appear in
  the same commit as their `.rulesync/` source

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | skills/wekan-mcp — the generic MCP board skill | M | 1 | [] | — |
| C02 | coord routes validation fixes automatically | M | 1 | [] | independent of C01 — disjoint files; shares only the rulesync regen (run in id order) |
| C03 | agent-board + /wekan-board-context collector + consumption rule | M+M | 2 | [C01] | command + agent bodies cite the skill by name and emit the Board context block schema the skill defines (interface) |
| C04 | board-context prefetch plugin | M | 3 | [C03] | plugin injects the exact block C03's consumption rule defines and reuses the collector's resolution sequence (data + format) |

## Wave order
1. C01, C02 (independent; id order — both regenerate AGENTS.md)
2. C03
3. C04

## Post-plan research round (card legacy checklist "After Planning")
Per the boards transition rule the checked item times an `agent-research`
round AFTER this plan (coordinator launches it; RESEARCH.md lands next to
this file). Suggested focus if approved: OpenCode V2 prompt-hook admission
semantics for scheduled/command launches (C04 assumption) and other
labs' board-context injection patterns. Nothing in C01–C03 waits on it;
C04 dev must read RESEARCH.md if it exists.

## Risks / assumptions
- `tests/wekan-mcp/tools.sh` pins wekan-api SKILL.md tool-surface text —
  C01 edits only outside the pinned regions; if a pin still breaks, the
  test is faulty (route per C02's new contract, ironically).
- The prompt hook may not fire for the OpenChamber scheduled launch path
  (docs say command prompts run hooks; schedule submission leg unproven).
  C04 treats live-fire proof as an acceptance gate with a defined
  degraded outcome (ship collector, plugin documented-not-deployed).
- Board IDs are structural but not frozen (a "Test" list already appeared):
  the consumption rule must say "on any id-shaped call error, re-resolve".
- Deployed wekan-mcp may lag repo source (cf-49): skill teaches probing
  `tools/list` over trusting docs; the new docs stamp evidence dates.

## Open questions — RESOLVED (2026-10-27 batched round; plan APPROVED)
1. **Final slug: `cf-75-bug-wekan-mcp-skill`** — user-confirmed. Names
   folder/branch/worktree/session for the run (`-context` stays taken by
   the landed sibling fix).
2. **Draft ticket `2026/2026-10-docs-wekan-mcp-arg-ergonomics` superseded** —
   user-confirmed absorbed by C01. Retirement mechanism (planner call,
   recorded in DECISIONS): the draft's STATE status write + its board
   follow-up card close are **coord-owned bookkeeping steps** — dev/test/
   review never touch another ticket's plan folder or the board.
3. **Card #74 covered by C02** — user-confirmed; moving #74 to Review is
   a **coord board-side duty at the end of the run**, not an agent task
   (DECISIONS).
4. **agent-board in scope (C03)** — user-confirmed.
5. **Prefetch plugin in scope (C04)** — user-confirmed: last wave,
   degrade-safe, default-OFF fallback, live-fire proof stands as AC.
6. **Auto-routing adjudicator** — user-confirmed as the best guess and
   now AC wording: mechanical validation repairs route **silently** back
   to `test_session`; the TEST session flags NEEDS_INFO when a fix would
   change functionality; coord then escalates to the user (and marks
   needs-replan if the plan itself moves).
7. **agent-board grants: `dev-boards*` ONLY** — user-confirmed, no
   admin-global-wekan fallback.
