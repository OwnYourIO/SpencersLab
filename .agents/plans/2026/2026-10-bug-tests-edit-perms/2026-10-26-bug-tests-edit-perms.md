# PLAN: Make top-level tests/** visible to the agent-test/agent-dev permission blocks (cf-52 friction follow-up)
feature: 2026/2026-10-bug-tests-edit-perms
amended: 2026-10-26 user-directed fold-in — post-cf-52-landing suite base-posture (DECISIONS D9–D12); plan_status stays approved (fold explicitly directed: "Fold into tests-edit-perms"). Re-applied after the original amendment was lost with its temp worktree (D12). Execution base re-targeted to main at/after 124fc2ae8 (= origin/main); original branch-base refs (b0c975bf6/f11bfcb85/1a6517c81) are history-only.

## Goal
Close the top-level `tests/**` blind spot in the `agent-*` permission blocks: `agent-test` cannot write the validation suites it owns (only `charts/**/tests/**` and `containers/**/tests/**` are allowed under its `edit * deny` baseline — cf-52's test session wrote through parent-passed grants), while `agent-dev` can silently write them (its `edit * allow` denies only the chart/container paths). Fix both halves, move the role-matrix / role-skill texts that describe them, and re-pin the cf-52 suites whose byte-freezes cover `agents-sync/references/`. The 2026-10-26 fold-in (user-directed, D9) extends the re-pin scope to the suites' post-landing base posture: three follow-up ticket folders admitted at t14/c8/c7 and the i4/t17 self-reference class redesigned to the c2 OR-form (D10).

## Out of scope
- AGENTS.md "Where things live" bullet for top-level `tests/` and the "There is no unit-test suite" sentence reword (docs-accuracy ticket; D5).
- The deferred `tests/services/hivetools-kubernetes-mcp-docs.sh` d4 per-ticket allow-set re-pin (separate cf-52 open-friction item).
- Any change to `agent-review`, `agent-fuser`, `agent-coord`, `agent-board-coord`, `agent-plan`, `agent-research` edit allows — audited, none carries a `tests/**` surface (D3).
- The coord-pair shell-grant CONTENT (the two scoped `opencode api` shell allows) — unchanged by this delta in either tree; only the i4/t17 comparison MECHANISM moves in-scope via the fold-in (D10). c2 stays out: already re-pinned in-sequence at landing (2f7bbb873, PORT_REF=916044893 — still reachable and green at HEAD, verified).

## Commands
- test (new suite): `bash tests/agent-perms/surface.sh`
- regression (both-operational-bases convention, re-targeted per D11 — the original `CHUNK_BASE=f11bfcb85` line is void: f11bfcb85 is unrelated pre-landing history, and 916044893 is excluded as a chunk base by the release-bot path, D11):
  `CHUNK_BASE=081b57889 bash tests/agent-board-coord/gate.sh && CHUNK_BASE=081b57889 bash tests/agent-board-coord/rulesync-surface.sh && CHUNK_BASE=081b57889 bash tests/agent-board-coord/agents-md.sh && CHUNK_BASE=081b57889 bash tests/coord-inwork/surface.sh`
  then the same four without `CHUNK_BASE` (default HEAD — on the integrated line this is the COMMITTED-Delta posture and must pass end-to-end post-fold-in; pre-fold-in it fails i4/t17 by the self-reference bug — the designed RED)
- lint: `npx --no-install aislop ci --changes` (gate config `.aislop/config.yml`; every touched file clears)
- generate: `rulesync generate` twice (second must be a no-op), then `rulesync generate --check` clean (c7/t14/i6 skip-with-warn npx ladder applies where the binary is unresolvable)
- grep spot-checks (the new suite encodes these as t1–t3): the `tests/**` allow present in `.rulesync/subagents/agent-test.md` + `.opencode/agents/agent-test.md` after the `edit * deny` pivot; the `tests/**` deny present in `.rulesync/subagents/agent-dev.md` + `.opencode/agents/agent-dev.md` after `edit * allow`

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | tests/** edit allow (test) + deny (dev), matrix/skill text, suite re-pins, new contract suite, post-landing base-posture fold-in | M | 1 | [] | single chunk: one invariant, its docs, its gates; the fold-in lands in the same case blocks T4 already edits and AC7 cannot pass without it (D9) |

## Wave order
1. C01 (test phase writes the failing contract suite + re-pinned gates incl. the i4/t17 OR-form redesign and folder admits; dev phase lands sources + regen + docs)

## Risks / assumptions
- Base (re-targeted by the 2026-10-26 fold-in, D11/D12 — supersedes OQ1's "stack on cf-52 branch HEAD b0c975bf6", which its own approval round made conditional on cf-52 not landing first; it landed, via PR, with new hashes): cf-52 content is on the pushed line as 20ed5dfaf (landing parent 081b57889; the c2 suite re-pin 2f7bbb873 and the three-follow-up-plans commit 124fc2ae8 complete the line — 124fc2ae8 = main = origin/main). The ticket branches from main at/after 124fc2ae8. `tests/coord-inwork/surface.sh` and every re-pin target exist on the integrated line; the refs baked into the original plan (b0c975bf6/f11bfcb85/1a6517c81) and the abandoned pre-push local lineage (9a48c916d/b9a0e23bc/73dabd4a4) are history-only — never CHUNK_BASE values. 916044893 is an ancestor but an invalid chunk base (its child 081b57889 is the release-bot Chart.yaml commit whose path t14/c8/c7 do not admit — D11).
- Bootstrap: the test phase of THIS ticket still runs with a pre-fix `agent-test` frontmatter — its writes to `tests/**` need the parent-passed grants (cf-52 precedent; this remains the LAST bootstrap run — C01's own payload is what retires the need). After C01 lands, later launches are native. (D6)
- Re-pinned t12/i5 carve + i4/t17 OR-form must HOLD in every posture (D10 discipline): all four suites pass at `CHUNK_BASE=081b57889` (delta present in the working tree vs pre-delta base — arm A) AND at default `BASE=HEAD` (committed-delta posture on the integrated line — arm B), both before dev (test-phase edits committed) and after dev. The t12/i5 carve is a path exclusion, not a delta-pin, so posture-stable; the i4/t17 redesign must not weaken the absolute shape pins (fmshape / t17 shape block stay unconditional). Verified live in the re-application session: gate minus {t14,t17} 18 ok at BOTH bases, rulesync-surface minus {c7,c8} 16 ok @081b57889 (c2's PORT_REF=916044893 reachable and green), agents-md minus {c7} 7 ok @081b57889, coord-inwork minus {i4,i6} 4 ok @HEAD, `rulesync generate --check` PASS at HEAD — no surprises hide behind the current aborts.
- `rulesync generate` rewrites only the five generated mirrors implied by the source edits (agent-test, agent-dev, two agents-sync references verbatim-copied, pipeline-role-test SKILL); the scope checks (c7/c8/t14) are widened exactly to those PLUS the three follow-up ticket folders `.agents/plans/2026/2026-10-bug-{kickoff-mints-run-branch,session-origin-no-line,tests-edit-perms}/` introduced by 124fc2ae8 (fold-in; union-of-tickets convention, no `.agents/plans/**` wildcard — a blanket admission would blind the guards for every future ticket).
- Regenerated surfaces + sources must land in ONE commit (repo hard rule; i6/c7/t14 all gate on `--check` + double-generate no-op).
