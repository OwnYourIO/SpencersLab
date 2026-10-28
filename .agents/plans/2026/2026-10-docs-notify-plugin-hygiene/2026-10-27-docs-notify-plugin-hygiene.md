# PLAN: question-notify doc/comment hygiene — header historical recast + AGENTS.md blurb
feature: 2026/2026-10-docs-notify-plugin-hygiene

## Goal
Close the two deferred doc-hygiene items from the finished `2026/2026-10-feat-ha-lifecycle-notify` ticket before that ticket's PR opens: recast the plugin header's now self-contradicting version claims into historical wording (comment-only, zero behavior change), and update the understated `question-notify` blurb in the rulesync rules source + regenerate. Both edits land on the existing `feat/ha-lifecycle-notify` surface.

## Out of scope
- Any behavior change, constant change, or code-line change in `.opencode/plugin/question-notify/index.ts` (only `//` comment lines may move).
- Tests: no new test files, no edits to the two existing ones (both md5-pinned untouched).
- The accepted-by-design aislop file-too-large warning (453 lines) — do NOT split the file.
- The deferred nits from the sibling DECISIONS.md: `"session"` fallback-label nit; silent-skip log when `ctx.event?.subscribe` is absent (stays deferred).
- Commits/PR — coord/user-owned landing.

## Commands
All deterministic + offline. Verified at plan time on this worktree (2026-10-27): suite 76/76 exit 0, `rulesync generate --check` exit 0, plain `rulesync generate` a true no-op.

Pre-edit md5 anchors (worktree state — note C03's plugin/test edits are UNCOMMITTED, these pins are that final C03 state):
- `.opencode/plugin/question-notify/index.ts` = `3129d1d92015f953581bbf7332b860d2`
- `tests/opencode/question-notify.test.ts` = `8b5d838221f79ad7ced875760752febb` (must be unchanged)
- `tests/opencode/permission-ask-notify.test.ts` = `0a522f0f8091eb278db88e7de3153392` (must be unchanged)

- test: `node --test 'tests/opencode/*.test.ts'` => `tests 76 / pass 76 / fail 0`, exit 0 (~4 s). Quoted glob mandatory (bare dir arg fails on this Node build, FRICTION 2026-10-26). If the summary lines ever go missing, `--test-reporter=tap` and read the count block.
- pins: `md5sum tests/opencode/question-notify.test.ts tests/opencode/permission-ask-notify.test.ts` => the two values above, byte-identical.
- comment-only proof (item 1; snapshot-based because `git diff` vs HEAD mixes uncommitted C03 code into every hunk):
  - before editing: `cp .opencode/plugin/question-notify/index.ts /tmp/opencode/qn-hygiene-before.ts`
  - `diff /tmp/opencode/qn-hygiene-before.ts .opencode/plugin/question-notify/index.ts | grep -E '^[<>]' | grep -vE '^[<>] //' | wc -l` => `0` (every added/removed line is a `//` comment)
  - `diff <(grep -v '^//' /tmp/opencode/qn-hygiene-before.ts) <(grep -v '^//' .opencode/plugin/question-notify/index.ts)` => empty (all code lines byte-identical, order intact)
- recast greps (item 1): `! grep -qF 'installed' .opencode/plugin/question-notify/index.ts` (all three present-tense "installed v2.x" claims go historical) and `grep -q 'at first shipping' .opencode/plugin/question-notify/index.ts`; `v2.0.32` and `v2.1.4` must still appear (history kept, not deleted); `@opencode/plugin 2.1.2` line untouched.
- rulesync (item 2): edit `.rulesync/rules/overview.md` only, then `rulesync generate` => exit 0 and the only newly-changed generated file is `AGENTS.md`; then `rulesync generate --check` => exit 0; running `rulesync generate` a second time adds no further diff (idempotence, agents-sync rule).
- blurb greps: `grep -q 'approval is still pending' AGENTS.md` and `! grep -q 'whenever an' AGENTS.md` (the old phrase existed exactly once).
- aislop: `which aislop` => not installed (carried-over ignored FRICTION: the aislop-gate plugin scans every write — final edit state must show 0 errors; the 453-line file-size warning is accepted-by-design, do not "fix").

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | header recast + rulesync blurb (one-shot doc touch) | S | 1 | [] | — |

## Wave order
1. C01 (only chunk; single fresh dev+review pair)

## Risks / assumptions
- C03 remains uncommitted when this runs. All validations are snapshot/md5-based and commit-agnostic; if coord commits C03 first, the pins still hold (they are the post-C03 content). Landing both hygiene items into the PR is coord/user-owned.
- `rulesync.jsonc` has `delete: true` — generation could theoretically sweep orphans. Mitigated: `generate --check` is green at plan time (no orphans exist), and the AC pins that after regeneration `git status` shows no deleted files beyond the pre-run dirt.
- Comment re-wrap inside the header block may shift line numbers of untouched comment lines — allowed (they are comment lines); the code-identity diff is the hard guard.
- aislop CLI absence FRICTION applies and is covered by aislop-gate (recorded in Conventions of DECISIONS.md so nobody re-litigates it).
- Pipeline deviation for coord: skip `agent-test` launch for C01 (tests are out of scope; the existing 76-test suite + md5 pins are the regression net). Dev → review only.
