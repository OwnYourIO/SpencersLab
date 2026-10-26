# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Single-chunk ticket: the fixed frontmatter, the two skill docs and the five suites
  pin each other by literal — any split leaves the D21 invariant red between chunks,
  so C01 lands whole (test re-pins red-before-green first, then dev lands sources).
- Historical plan files that contain the `dev_boards` literal (cf-70, board-coord-intake,
  cf-50, cf-52) are append-only records: never re-pinned by this ticket; only live
  sources + live suites change.

## Decisions
- 2026-10-26 plan: ROOT CAUSE = literal action-pattern divergence, not a registration
  fault. OpenCode MCP tool ids are `<config server name>_<tool>` with the hyphen kept
  (opencode.ai/docs/mcp-servers "Glob patterns": `my-mcp*` matches `my-mcp_search`; page
  dated 2026-10-24). Evidence chain: (a) `agent-plan` with broad `dev*` saw all 26
  dev-boards tools in this very planner session 2026-10-26; (b) `agent-board-coord` with
  ONLY `dev_boards*` saw none (cf-70 FRICTION item 1, same day); (c)
  `.opencode/opencode.jsonc` L64-72 registers the server enabled and it answers
  (serverInfo wekan v4.1.3); (d) `rulesync generate --check` passes at 74e4589d9 —
  source↔mirror in sync, no drift. Rejected: project-config fix (the control agent
  proves the config works), stale-generation fix (ruled out by (d)), machine-global
  config (dev-boards is project-local; brief puts global edits out of repo scope anyway).
- 2026-10-26 plan: FIX = re-spell the one rule to `dev-boards*`, keeping D21's narrow
  least-privilege scoping unchanged (single boards allow, no broad `dev*` for
  board-coord). Rejected: broad `dev*` for board-coord (contradicts D21's adjudication
  and grants playwright/renovate/searxng to the coordinator); dual-spelling
  belt-and-suspenders (`dev_boards*` kept as a dead rule — dead rules are how this bug
  hid for a day, and the new A11 check is the real guard); removing the allow to lean on
  global config (agent rules take precedence; the deny-all first would bury the server
  again).
- 2026-10-26 plan: the doctrine fix ships with the code: permissions.md's "dev* matches
  only dev_* names" claim (L51) is the misbelief that produced D21's wrong spelling;
  it is rewritten to the actual tool-id model so no future agent re-derives the
  underscore form. Boards SKILL.md L23 + matrix row L26 follow.
- 2026-10-26 plan: cf-70 FRICTION item 2 (bare `action: opencode` grant + scoped shell
  allows) stays a SIBLING ticket, not C02 here. Superficially the same
  literal-vs-tool-id class, but the observed symptom (exactly `worktree_remove` present)
  does not fit a pure divergence model — it needs its own live coord-catalog
  dissection; folding an ungrounded fix in would repeat the D21 failure mode. C01 T5
  only RECORDS sweep findings for it. Rejected: fold-in; rejected: silently ignore.
- 2026-10-26 plan: live proof (board-coord catalog carries dev-boards tools) is a
  DEFERRED acceptance criterion (AC7), human/coord-owned on the next board-coord
  launch — offline suites can pin literals/positions/shape but cannot test OpenCode's
  matcher. cf-70 FRICTION item 1 re-status to `fixed` rides on that proof and is done
  by cf-70's coord, never by this ticket's agents (cf-70 folder untouched here).
- 2026-10-26 plan: STATE.json carries no kickoff block (standalone ticket, no board
  card, no kickoff answers in the launch message) — coord fills `kickoff`/
  `coord_session` at its own kickoff per pipeline-kickoff, not here.

## Deferred
- AC7 live verification + cf-70 friction write-back (next agent-board-coord launch).
- Sibling ticket for cf-70 FRICTION item 2 (opencode/shell grants on coord variants) —
  recommended to coord immediately after this ticket lands.
- The `playwright_browser_*` rules in hand-managed `.opencode/opencode.jsonc` may be
  dead under the same tool-id model (no server named plain `playwright`); out of scope,
  recorded here as a candidate for the item-2 sibling sweep.
