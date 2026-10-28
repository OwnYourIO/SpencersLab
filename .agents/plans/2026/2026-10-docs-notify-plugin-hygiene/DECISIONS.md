# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Carried over from the sibling `2026-10-feat-ha-lifecycle-notify` run: quoted glob `node --test 'tests/opencode/*.test.ts'` for the suite (bare dir arg fails on this Node build); counts read from the reporter summary block (tap fallback if summary lines ever go missing); aislop CLI not installed here = ignored FRICTION, aislop-gate plugin scans every write (final state 0 errors); 453-line file-too-large gate warning = accepted-by-design, never "fix" by splitting (single-file convention, 2026-10-24 sibling DECISIONS).
- No commits by any stage-role — coord/user land the branch and open the PR.
- Generated surfaces (`AGENTS.md`, `.opencode/agents|commands|skills`) are never hand-edited; the only writer is `rulesync generate` from `.rulesync/` sources.

## Decisions
- 2026-10-27 plan: One chunk (C01) for both hygiene items. Rejected: two chunks (one per item) — both are S docs touches landing on one branch pre-PR; splitting buys no independent reviewable risk boundary. Size S by the role's grouping rule (group unrelated S tasks freely).
- 2026-10-27 plan: Validation is snapshot-diff based (`/tmp/opencode/qn-hygiene-before.ts` copy + md5 anchor `3129d1d9…`), not `git diff` vs HEAD. Rejected: `git diff -U0` comment-line inspection — this worktree carries C03's UNCOMMITTED plugin/test edits, so every git hunk mixes C03 code with hygiene comments; the launch suggestion works only post-commit and the plan must not assume a commit ordering (FRICTION lesson: verify from live state — C03 is dirty here at plan time).
- 2026-10-27 plan: Skip agent-test; no new or edited tests. Rejected: a third test file pinning comment wording (brittle — prose is not a behavior contract) and edits to the two pinned files (out of scope by the user-fixed ticket; both md5s are ACs). The 76-test suite + md5 pins + grep/diff battery give the review agent runnable proof of zero behavior change.
- 2026-10-27 plan: Recast wording = tense fix only ("at first shipping" / "re-grounded on the v2.1.4 binary"); drop "installed" everywhere in the header (3 live occurrences, verified :32/:34/:40) while keeping every version string and the DECISIONS.md link. Rejected: deleting the historical version notes (they carry the trade-off the keep-table protects) and removing the `ctx.session.get` fallback or re-testing `event.agent` sufficiency (behavior change — hard out-of-scope). This matches the sibling's prescribed "one-line historical recast" and AGENTS.md comment rules (state why, historically, not a rotting present-tense snapshot of a self-updating CLI).
- 2026-10-27 plan: AGENTS.md blurb updated via `.rulesync/rules/overview.md` :55–57 + `rulesync generate` (v37.0.0, global binary, offline no-op behavior verified at plan time). Rejected: hand-editing `AGENTS.md` (hard repo rule) and deferring to the user (generation provably runs here; the "hand the step to the user" fallback in the launch brief is not needed — recorded as verified capability).
- 2026-10-27 plan: The `@opencode/plugin 2.1.2 types` line and the :26–27 DECISIONS.md link stay untouched. Rejected: broadening into a full header comment-slop sweep — scope discipline; the sibling DECISIONS entry prescribes only the version-wording recast.

## Deferred
- Unchanged from the sibling ticket (out of scope here): silent-skip stderr log when `ctx.event?.subscribe` is absent; `"session"` fallback-label nit. No new deferrals.
