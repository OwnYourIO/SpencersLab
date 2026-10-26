# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- 2026-10-26 · plan · harness exposed no `worktree_create`/`session_move`/`session_rename`, so the run worktree/branch and the coord session id could not be produced at kickoff · resolution: answered in the 2026-10-26 batched round (Q2) — Execution kickoff orders the coord retry, then a user-owned `git worktree add` from the pinned base; permanent fix is the PLAN-ONLY follow-up ticket now on our base (`2026-10-bug-kickoff-mints-run-branch`, unimplemented) · open
- 2026-10-26 · plan · `pipeline-role-test` still states "there is no global `tests/`" while `tests/agent-board-coord/` and `tests/coord-inwork/` exist and are agent-test-authored (aa529d707) — a doc that misleads the test writer on agent-context tickets · resolution: out of scope here by design; left as the first candidate for this ticket's own follow-up-card flow (DECISIONS D10) · open
