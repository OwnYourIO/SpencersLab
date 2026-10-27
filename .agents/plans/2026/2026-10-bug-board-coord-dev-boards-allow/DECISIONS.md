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

## Landing record (2026-10-27)
- 2026-10-27 direct-landing (user instruction "fix it in this session" — the ticket ran
  with NO agent-test/agent-dev pipeline: the `code` agent of the cf-75 board session
  landed C01 whole, plan-of-record tasks T1-T6, in one branch commit set on
  `bug-board-coord-dev-boards-allow`): the dead `dev_boards*` re-spelled to
  `dev-boards*` in ALL THREE board-coord sources (alias + `-local` + `-pr` — the plan's
  file list named only the alias; the alias-twin same-commit discipline and the
  t17/A12/coord-inwork/kickoff-branch/session-origin board arms pin the literal on
  every variant, so a one-file fix would have landed a red family) plus their
  generated mirrors via `rulesync generate` (second run no-op, `--check` clean).
- Suite re-pins grew from five to SEVEN: tests/kickoff-branch/surface.sh and
  tests/session-origin/surface.sh had gained `dev_boards*` pins between the plan base
  (74e4589d9) and this landing base (4813c13d3 — the cf-52 SHELL4/cf-58 re-pins);
  grep-enumerated per the chunk's discipline, re-pinned with the others.
- A14 shipped as the new check id in tests/agent-perms/surface.sh (the plan's "A11"
  slot was taken by cf-58's git-rows check at landing time; A14 was free). RED-BEFORE
  EVIDENCE (AC6 posture assertion): the checker run against
  `git show 4813c13d3:.rulesync/subagents/agent-board-coord{,-local,-pr}.md` flagged
  `dev_boards*` in all three files (live-verified 2026-10-27 pre-commit); green after.
  Negative control (fabricated dev_boards* file rejected) ships inside the check.
- T5 SWEEP (record-only): `.rulesync/` is free of further server-name-shaped globs
  with separator divergence (family-wide `dev*`/`readonly*`/`admin*`/`global*` are the
  exempt leading-segment forms). The hand-managed `.opencode/opencode.jsonc` permissions
  array carries ~dozens of `playwright_browser_*` ACTION rows (L1005+) — under the same
  tool-id model those can match no registered server (`dev-playwright`/`global-playwright`
  ids keep the hyphen) — CONFIRMED candidate for the cf-70-item-2 sibling ticket; NOT
  edited here (hand-managed project config, out of scope). The inert
  `action: opencode '*'` anchors (documented by e0d7fb767 as the pin the suites splice
  against) are the same class — left standing per that commit's decision.
- Designed-window red (e0d7fb767 precedent): m4/s4 in kickoff-branch/session-origin
  delta-walk `git show HEAD:` vs worktree, so between source-fix and commit they read
  "extra dev-boards*/missing dev_boards*" — green expected at the landing commit;
  verified post-commit below.
- Live proof (AC7) status: THIS very session proved the hyphen model empirically —
  after the harness reload the Code Mode catalog exposed `dev-boards` as
  `tools["dev-boards"]` (26 tools, snake_case args, called natively for the card
  pickup/claim). A board-coord run on the fixed grants is the formal AC7 turnstile.
