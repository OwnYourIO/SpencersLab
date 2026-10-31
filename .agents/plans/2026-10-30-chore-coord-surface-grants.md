# 2026-10-30-chore-coord-surface-grants — grant the coords their own kickoff-surface verification

Type: chore (agent machinery) · Services: `agent context` · no ticket folder — standalone follow-up to
cf-76 C06 live-smoke, triggered by the card #88 scheduled-loop iteration false-block.

## Problem

The first scheduled `pipeline-worker` loop run (card #88, 2026-10-30) executed the boards flow correctly
through pickup, lock-availability filtering, claim (with the guarded reap of a stale `Local` set) and the
full card-driven kickoff, then **abandoned itself on a fiction**: a handful of denied verification probes
(`ls`, `pwd`, `echo` compounds, reading `.agents/loops/…` and `.opencode/agents/…`) hit the coord
family's deliberate `* * deny` baseline and were misread as the sanctioned `session_move` having
"poisoned" the session's permissions. The board comment posted that diagnosis (since corrected with a
second comment). Root cause is two-sided:

1. The coord genuinely lacked the privileges to verify its own kickoff surfaces — worktree/branch
   presence, session location, the loop file it was launched from, its own permission block. A worker
   that cannot check its grants can misdiagnose any denial as environmental.
2. Nothing in the contract said what a `permission.rejected` actually means for a coord — so a denied
   out-of-contract probe looked identical to a broken environment.

## Change

Grants (identical on all six coord sources — alias-twin parity rule):

- shell: `ls`, `ls *`, `pwd`, `pwd *` (bare+spaced pairs: `ls *` never matches the bare form, `ls*`
  would shadow lsof/pwdx-style tools) — five-allow SHELL5 grew to nine-allow SHELL9 (27 literal lines).
- read: `.agents/loops/**`, `.opencode/agents/**` — the loop file the launch text comes from and the
  agent's own permission block, for diagnosis.

Contract prose (`pipeline-role-coord` SKILL, source + mirror): the grants bullet now names the new
surface; a new Hard rule states that a `permission.rejected` on a probe outside the scoped list is the
firewall doing its job — drop the out-of-scope probe and continue; only a failed **in-contract** step
may drive the blocked/abandon exit.

Matrix (`agents-sync` references/permissions.md, source + mirror): coord + board-coord shell cells
updated; new drift-incident entry (2026-10-30) recording the false-block and the same-commit re-pin
obligation it exercised.

Suite re-pins (the standing "permission-block change is only done when every pin moved too"):

- `tests/coord-inwork/surface.sh` — i4 sanctioned-shell-row set + WANT ladder (SHELL9 rung).
- `tests/agent-board-coord/gate.sh` — t17 same two arms.
- `tests/kickoff-branch/surface.sh` — m4: `sanctioned()` membership, `DIAG`/`READDIAG` projection
  strips + at-most-once-whole admits, WANT ladder, diff-shape arms (`75-23` src / `75-18` mirror),
  control strings.
- `tests/session-origin/surface.sh` — s4: same treatment; also fixed the `atpos4` continuation walk's
  hardcoded `k = at + 15` → `k = at + 3 * len(WANT)`.
- Scope guards widened with a dated inline literal for this change's root plan doc
  (c8 in `rulesync-surface.sh`, c7 in `agents-md.sh`, t14 in `gate.sh`) — the cf-72/cf-85 admit precedent;
  c8 additionally already carries the cf-76 `.agents/loops/*` admit.

Generated surfaces refreshed via `rulesync@37.0.0 generate` (6 subagent mirrors + 2 skill files);
`generate --check` clean, second run a no-op. AGENTS.md unchanged (it does not enumerate coord shell
rows).

## Validation (commands run)

- `bash tests/coord-inwork/surface.sh` => PASS 7 ok
- `bash tests/kickoff-branch/surface.sh` => PASS 6 ok
- `bash tests/session-origin/surface.sh` => PASS 7 ok
- `bash tests/agent-perms/surface.sh` => PASS 15 ok
- `bash tests/agent-board-coord/rulesync-surface.sh` => PASS 20 ok
- `bash tests/standalone-agents/surface.sh` => PASS 10 ok
- `bash tests/agent-board-coord/gate.sh` => red at t14 ONLY on `.agents/loops/pipeline-worker.md` —
  the owner's uncommitted loop-enablement in the same working tree (pre-existing, owned separately);
  `tests/agent-board-coord/agents-md.sh` + `tests/pipeline-gates/validation-fix.sh` likewise red on
  that single path (c7).
- `node --test tests/opencode/pipeline-locks-tick.test.ts` => 11/12, the single failure being the
  `enabled: false` byte-pin against the owner's loop flip — external to this change.
- `npx --yes rulesync@37.0.0 generate --check` => up to date; `npx --yes aislop ci --changes` => 0
  errors 0 warnings.

## Follow-ups (owner-side, not this change)

- Land the loop enablement with the tick-suite `enabled`-pin re-pin (C06 item 9) — same commit.
- Re-run the hourly loop: the next card #88 pickup should now reach plan approval without the
  false-block; the live-smoke item 3 needs one clean full iteration.
- The empty `cf-88-feat-provider-pipeline-runners` worktree + branch (0 commits) — remove or reuse.
