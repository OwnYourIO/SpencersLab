# PLAN: agent-board-coord's `dev-boards` MCP allow never matches — dead `dev_boards*` spelling

feature: 2026/2026-10-bug-board-coord-dev-boards-allow
origin: card #70 run, FRICTION item 1 — "`dev-boards` MCP server not registered in this
session's tool catalog (neither direct tools nor the Code Mode `tools` namespace) — could
not call wekan-mcp tools as designed · resolution: spoke MCP-over-HTTP directly … · open
(fix: register the dev-boards server for agent-board-coord)"
(2026/2026-10-cf-70-debug-wekan-enter-submit/FRICTION.md; read-only source, not touched here)

## Goal
Restore the WeKan board MCP surface to `agent-board-coord` by repairing its single MCP
permission: the action pattern `dev_boards*` (underscore) cannot match the tool ids
OpenCode exposes for the `dev-boards` server (server-name prefix keeps its hyphen,
`dev-boards_<tool>`), so every board tool falls through to the agent's leading
`* * deny` rule and vanishes from its catalog. Re-spell the allow to `dev-boards*`,
re-pin every literal pin that baked in the wrong spelling (4 test suites, 2 skill docs),
and add an offline regression check for the whole pattern-vs-tool-id divergence class.

## Diagnosis (verified 2026-10-26, base 74e4589d9 — NOT the server, NOT the project config)
1. **Docs**: opencode.ai/docs/mcp-servers ("Glob patterns", page dated 2026-10-24) —
   MCP tools are registered with the **server name as prefix** and the documented glob
   `my-mcp*` matches `my-mcp_search` / `my-mcp_list`: the hyphen in the server name is
   part of the tool id and matches literally. `dev_boards*` therefore matches nothing for
   server `dev-boards`.
2. **Empirical contrast, same repo, same day**: `agent-plan` (this session's role, broad
   `dev*` allow in frontmatter) DOES see the 26-tool `dev-boards` namespace live;
   `agent-board-coord` (only narrow `dev_boards*`) saw none. The `*` in `dev*` matches
   `dev-boards_…` (any char after `dev`); `dev_boards*` requires a literal `_` exactly
   where the tool id has `-` — the one difference between the working and failing agents.
3. **Config healthy, not the fault**: `.opencode/opencode.jsonc` L64-72 registers
   `dev-boards` (remote, enabled, `https://mcp.dev.scifi.farm/boards/mcp`); the server
   itself answers (wekan v4.1.3, ~26 tools — cf-70 live probe). Machine-global
   `~/.config/opencode/opencode.json` is not involved in this server at all (it is
   project-local).
4. **Generation healthy**: `rulesync generate --check` passes at base (✓ All files are
   up to date); source L85 and generated mirror L82 are in sync — this is a wrong-literal
   bug, not drift.
5. **Where the misbelief came from**: `.rulesync/skills/agents-sync/references/`
   `permissions.md` L51 claims "`dev*` matches only `dev_*` names" — an incorrect
   generalization that survived because `dev*`/`admin*`/`readonly*`/`global*` work under
   BOTH spellings (their prefixes contain no separator). D21's narrow per-server allow was
   then spelled to the (wrong) underscore form and died silently. The boards skill L23
   and the 4 test suites repeat the literal.

## Out of scope
- FRICTION item 3 (wekan-mcp arg ergonomics — `board_id`, `finished`, `from_list_id`…) —
  sibling follow-up already documents it (cf-49 lane). Do not duplicate.
- FRICTION item 2 (coord's `action: opencode` grant exposing only `worktree_remove`,
  scoped shell allows denied). Superficially the same class, but the built-in tool-id
  model doesn't fit a pure divergence explanation (why would `worktree_remove` survive?)
  — needs its own live dissection. Recommend a sibling ticket; this plan only sweeps for
  further dead literals and RECORDS findings (see C01 T6).
- The D21 policy itself: narrow boards-only MCP for board-coord STAYS; only its spelling
  is amended. No broad `dev*`, no permissive deny-all changes.
- `.opencode/opencode.jsonc`, machine-global config, charts, versions, any `kubectl`/
  deploy action. No file under the cf-70 folder is edited by this ticket.

## Commands (this repo's validation = rulesync surfaces + the literal-pin suites)
- generate: `rulesync generate` — run TWICE, the second must be a no-op (idempotence)
- check: `rulesync generate --check` (exit 0)
- test: `bash tests/agent-board-coord/rulesync-surface.sh`
- test: `bash tests/agent-board-coord/gate.sh`
- test: `bash tests/agent-board-coord/agents-md.sh`
- test: `bash tests/coord-inwork/surface.sh`
- test: `bash tests/agent-perms/surface.sh` (incl. its new MCP-shape check, T5)
- pin-grep: `grep -c 'dev-boards\*' .opencode/agents/agent-board-coord.md` == 1 AND
  `grep -c 'dev_boards' .opencode/agents/agent-board-coord.md .rulesync/subagents/agent-board-coord.md` == 0 (both files, exit 1 on no match)
- surface: `git diff --name-only` shows ONLY the files in C01 "Files in scope"

Baseline posture at 74e4589d9 (measured 2026-10-26 by the planner): `rulesync generate
--check` pass; `tests/agent-perms/surface.sh` pass; `tests/coord-inwork/surface.sh` pass;
`agents-md.sh` FAILs at c7 and `rulesync-surface.sh` FAILs at c8 — both ONLY because the
main checkout carries another session's in-flight dirty files (cf-49 plan-folder edits)
that the scoped-allow windows don't admit. Dev/review MUST run from the ticket worktree
(clean base + merge main in), and the test session admits this ticket's paths into the
c7/c8/t14 windows anyway (the A9 windowed-admission precedent, tests/agent-perms).

## Chunks
| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | Re-spell the narrow MCP allow + literal re-pins + divergence regression check | M | 1 | [] | single chunk: source, skill docs and suite literals pin each other byte-for-byte — any split lands with a red invariant between chunks |

## Wave order
1. C01 (only chunk).

## Acceptance criteria (detail in chunks/C01.md)
1. `.rulesync/subagents/agent-board-coord.md` and its generated mirror carry exactly one
   `- action: dev-boards*` allow in the same list position (after the `execute` allow,
   before the three `edit` allows); no `dev_boards` remains in either file.
2. All five suites pass from the ticket worktree; `rulesync generate` twice = no-op;
   `generate --check` exit 0.
3. D21 shape held: no broad `dev*` on board-coord, deny-all stays first, five subagent
   allows + three edit allows + `question` allow intact (gate t17 invariants).
4. `permissions.md` (source + mirror) no longer contains the "only `dev_*` names"
   misbelief; boards SKILL.md (source + mirror) carries the corrected spelling.
5. `tests/agent-perms/surface.sh` gains an offline check that rejects any MCP action glob
   whose literal prefix diverges (hyphen/underscore) from a server name actually defined
   in `.opencode/opencode.jsonc` — red before C01's frontmatter fix, green after.
6. LIVE (deferred, human/coord-owned): the next `agent-board-coord` launch shows the
   `dev-boards` tools in its catalog (direct or Code Mode); only then may cf-70 FRICTION
   item 1 be re-statused `fixed` (that write-back is that run's coord's action, not a
   dev task here). If the catalog is still empty, this ticket is NOT fixed — reopen and
   dissect harness-side (v2 tool-id naming, config merge), do not force the literal fix.

## Risks / assumptions
- **Assumption**: OpenCode v2 keeps the documented `<server-name>_<tool>` id form with
  hyphens literal. Evidence: docs glob section + the plan/board-coord contrast. Cheap
  pre-edit re-verification for dev: read the live tool-id names from any agent's catalog
  (e.g. `agent-test` sees `dev-` namespaces) — do NOT re-derive from memory. AC6 is the
  final proof; the offline suites cannot test the matcher itself.
- **Pin contact surface**: the suites are cross-ticket artifacts (board-coord-intake,
  cf-50, cf-52, tests-edit-perms, coord-inwork). Editing them risks flipping unrelated
  HOLD pins red (t12/t15 byte-freezes). Discipline: re-pin ONLY `dev_boards*`/scope-window
  occurrences (grep-enumerated in C01); any other red = `validation_at_fault` → ask user,
  route to the test session, never "fix" collateral pins in dev.
- boards SKILL.md is NOT byte-frozen (t12 carve since cf-50 r2) — the doc edit is safe;
  `pipeline-boards*` commands are untouched by this ticket (they already spell `dev-boards`).
- Landing (PR/merge) is user-owned per AGENTS.md hard rules; the plan contains no
  merge/push step.

## Open questions (no-questions protocol: best guess chosen, impact stated)
- OQ1 (best guess: YES, include it): extend the T5 regression check to ALL server-name
  action globs (`readonly-`/`admin-`/`global-` prefixed rules in agent sources), not just
  `dev`. Impact: a few more lines in agent-perms; same guarantee class; zero behavior
  change since those prefixes are separator-free and match under both readings.
- OQ2 (best guess: leave item 2 to a sibling ticket as planned): should cf-70 FRICTION
  item 2 be folded in as C02? Impact: would roughly double scope and needs a live
  coord-catalog dissection this planner cannot ground from files; folding an unfounded
  fix in would repeat the D21 failure mode.
- OQ3 (best guess: amend the D21 text in place — "spelling corrected by this ticket",
  history preserved append-only in cf-5… i.e. cf-70-intake DECISIONS files are NOT
  edited, only THIS folder's DECISIONS records the amendment). Impact: none if approved;
  the four suite re-pins already assume it.

## Commands recap for agent-test: every "test" line above is a suite it owns; it writes
## the re-pins + T5 (red-before-landing by design), dev then lands C01 sources (green).
