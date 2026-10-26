# PLAN: Make top-level tests/** visible to the agent-test/agent-dev permission blocks (cf-52 friction follow-up)
feature: 2026/2026-10-bug-tests-edit-perms

## Goal
Close the top-level `tests/**` blind spot in the `agent-*` permission blocks: `agent-test` cannot write the validation suites it owns (only `charts/**/tests/**` and `containers/**/tests/**` are allowed under its `edit * deny` baseline — cf-52's test session wrote through parent-passed grants), while `agent-dev` can silently write them (its `edit * allow` denies only the chart/container paths). Fix both halves, move the role-matrix / role-skill texts that describe them, and re-pin the cf-52 suites whose byte-freezes cover `agents-sync/references/`.

## Out of scope
- AGENTS.md "Where things live" bullet for top-level `tests/` and the "There is no unit-test suite" sentence reword (docs-accuracy ticket; D5).
- The deferred `tests/services/hivetools-kubernetes-mcp-docs.sh` d4 per-ticket allow-set re-pin (separate cf-52 open-friction item).
- Any change to `agent-review`, `agent-fuser`, `agent-coord`, `agent-board-coord`, `agent-plan`, `agent-research` edit allows — audited, none carries a `tests/**` surface (D3).
- The coord-pair shell-grant pins (t17/i4/c2) — untouched by this delta, hold as written.

## Commands
- test (new suite): `bash tests/agent-perms/surface.sh`
- regression (both-bases convention, cf-52 dev precedent):
  `CHUNK_BASE=f11bfcb85 bash tests/agent-board-coord/gate.sh && CHUNK_BASE=f11bfcb85 bash tests/agent-board-coord/rulesync-surface.sh && CHUNK_BASE=f11bfcb85 bash tests/agent-board-coord/agents-md.sh && CHUNK_BASE=f11bfcb85 bash tests/coord-inwork/surface.sh`
  then the same four without `CHUNK_BASE` (default HEAD = worktree posture)
- lint: `npx --no-install aislop ci --changes` (gate config `.aislop/config.yml`; every touched file clears)
- generate: `rulesync generate` twice (second must be a no-op), then `rulesync generate --check` clean (c7/t14/i6 skip-with-warn npx ladder applies where the binary is unresolvable)
- grep spot-checks (the new suite encodes these as t1–t3): the `tests/**` allow present in `.rulesync/subagents/agent-test.md` + `.opencode/agents/agent-test.md` after the `edit * deny` pivot; the `tests/**` deny present in `.rulesync/subagents/agent-dev.md` + `.opencode/agents/agent-dev.md` after `edit * allow`

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | tests/** edit allow (test) + deny (dev), matrix/skill text, suite re-pins, new contract suite | M | 1 | [] | single chunk: one invariant, its docs, its gates |

## Wave order
1. C01 (test phase writes the failing contract suite + re-pinned gates; dev phase lands sources + regen + docs)

## Risks / assumptions
- Base: this ticket stacks on cf-52's branch HEAD (b0c975bf6) — `tests/coord-inwork/surface.sh`, the `f11bfcb85` base ref and the re-pin targets exist only there. If cf-52 lands to main first, branch from main instead; the Commands stay identical. (OQ1)
- Bootstrap: the test phase of THIS ticket still runs with a pre-fix `agent-test` frontmatter — its writes to `tests/**` need the parent-passed grants (cf-52 precedent). After C01 lands, later launches are native. (D6)
- Re-pinned t12/i5 must HOLD in every posture: base `f11bfcb85` with the delta absent (pre-dev) and present (post-dev), and default HEAD with uncommitted work — the carve is a path exclusion, not a delta-pin, so it is posture-stable.
- `rulesync generate` rewrites only the five generated mirrors implied by the source edits (agent-test, agent-dev, two agents-sync references verbatim-copied, pipeline-role-test SKILL); the scope checks (c7/c8/t14) are widened exactly to those.
- Regenerated surfaces + sources must land in ONE commit (repo hard rule; i6/c7/t14 all gate on `--check` + double-generate no-op).
