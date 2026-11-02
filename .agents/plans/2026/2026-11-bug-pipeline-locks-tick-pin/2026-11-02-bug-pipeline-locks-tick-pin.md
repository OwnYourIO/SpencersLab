# PLAN: Retire the stale loop-model pin and align the aislop gate/CI version pins
feature: 2026/2026-11-bug-pipeline-locks-tick-pin

## Goal
Two user-ordered hygiene fixes in the pipeline's test/gate machinery: (1) re-pin the tick-loop model assertions to the owner-approved `gpu-ai/qwen3.8-flash-next-strata` so the last persistent red in the combined `tests/opencode` suite goes green (retiring the external-red exception the sibling ticket carried), and (2) make the aislop gate plugin and the CI gate resolve the same pinned CLI version as the ad-hoc `npx aislop` scans agents actually use as final-state authority.

## Out of scope
- The loop files' bytes (`.agents/loops/pipeline-worker*.md`) — they are the ITEM-1 authority and already ship the decided value; this ticket only makes the test mirrors chase them.
- Every other `openrouter/qwen/qwen3.8-flash` occurrence — the legitimate `Qwen Flash` picker option (pipeline-models/kickoff skills) and append-only historical plan/DECISIONS records.
- Rulesync-generated surfaces (AGENTS.md "aislop runs via npx" recipe text), the vendored `.rulesync/skills/aislop` (SHA-pinned), `.aislop/config.yml`, any helm/chart work (none in this ticket), and any WeKan/board-side change (local-only ticket).

## Grounding (verified at plan time, worktree HEAD `4781f56fe` == main)

**ITEM 1 — which side is right: the loop file is.**
- `git show 652ba904c` (on main, 2026-11-01): flips `.agents/loops/pipeline-worker.md` `model: openrouter/qwen/qwen3.8-flash` → `model: gpu-ai/qwen3.8-flash-next-strata`, commit message: *"owner-approved 2026-11-01; the local arena carries the tick's code tier; OpenChamber syncs from the main checkout"*. Live bytes confirm both loop files (`pipeline-worker.md`, `pipeline-worker-local.md`) now ship the gpu-ai id.
- The decision record: `2026/2026-10-cf-86-feat-more-strata-models/DECISIONS.md:102` — *"2026-11-01 housekeeping (owner-approved earlier): the scheduled pipeline-worker loop model moves openrouter/qwen/qwen3.8-flash → gpu-ai/qwen3.8-flash-next-strata … the local arena now carries the tick's code-tier model."* This **supersedes** the cf-76 r2 Q2 ruling (`tests/.../cf-76.../DECISIONS.md:40`: tick model = openrouter) that the red test still cites.
- Repo policy for pins like this, from the very test being fixed (`pipeline-locks-tick.test.ts:160-165`, the `enabled`-field comment): *"The literal tracks the LANDED … value … a future deliberate flip re-pins it rather than deleting the assertion."* 652ba904c is exactly such a deliberate, owner-approved flip → **re-pin (fix (a))**, not weaken.
- AGENTS.md's gpu-ai-churn worry is answered by the sibling pin's own convention (`tests/provider-loops/surface.sh` t3): *"the catalog churns, so the pin moves only by a fresh user ruling"* — the test mirrors the decided literal; serving changes underneath don't move it, an owner flip does (this one did).
- Blast radius = **exactly two mirrors**, both verified red on main today:
  1. `tests/opencode/pipeline-locks-tick.test.ts:158` — T2 "carries exactly the five documented fields…" — reproduced live: `actual 'gpu-ai/qwen3.8-flash-next-strata' - expected 'openrouter/qwen/qwen3.8-flash'`.
  2. `tests/provider-loops/surface.sh:151-152` — t1 pins `$API=".agents/loops/pipeline-worker.md"` (line 44) `model=openrouter/qwen/qwen3.8-flash` — reproduced live: `FAIL: t1[C04 AC1] … frontmatter drifted`. (The sibling's "sole persistent red" claim covered only the node `--test` suite; the bash battery has the same stale mirror.)
- `.opencode/plugin/pipeline-locks/index.ts` carries no model string (TICK_PROMPT, line 63, is model-free) — zero production-code change for ITEM 1.
- Sibling `2026-10-feat-ha-lifecycle-notify` on main has chunks C01–C04 and friction through 2026-10-28; the cited 2026-11-02/C05 entries exist only in the parent session's unmerged worktree (branch tip here lacks them) — treated as relayed evidence; every load-bearing claim above was verified independently from repo state.

**ITEM 2 — the skew is ad-hoc-latest vs both pins, not gate-vs-CI:**
- `.opencode/plugin/aislop-gate/index.ts:30`: `const AISLOP_VERSION = "0.18.1"`; invoked `npx --yes aislop@${AISLOP_VERSION} scan --changes` (lines 58-62). Header comment (14-15): *"Pinned CLI version via npx --yes (repo has no package.json; the CI gate pins the same version)."*
- `.github/workflows/aislop.yaml:28`: `npx --yes aislop@0.18.1 ci --changes --base origin/main --human`; comment (6-8): full-repo debt tracked via `npx aislop@0.18.1 ci` locally; *"The CLI version is pinned here and in .opencode/plugin/aislop-gate/index.ts — bump both together."*
- npm registry (verified live): latest `aislop` = **0.20.0** (0.19.0/0.19.1/0.20.0 published after the 0.18.1 pins were set). So gate and CI agree with each other (0.18.1) but **both** diverge from the repo recipe "aislop runs via npx" — bare `npx aislop` resolves 0.20.0. Sibling friction (relayed, dev C05): findings diverged 99/100 (0.18.1 gate) vs 100/100 (0.20.0 npx) on the same diff; the final-state authority became the npx scan.
- Vendored skill guidance (`.rulesync/skills/aislop/SKILL.md:24-41`): pinned `npx aislop@<version>` is the acceptable form; floating `npx aislop` is last-resort and *"Never in CI"* → **both-floating is rejected**; the fix is bumping both explicit pins to 0.20.0 and machine-enforcing the "bump both together" prose.
- No test currently guards either string (grep `aislop@|AISLOP_VERSION` over `tests/ .aislop/` = 0 hits) — the guard gap that let this drift.

## Commands (deterministic + offline; run from repo root; Node v26 — `node --version` first)
- suite: `node --test 'tests/opencode/*.test.ts'` — quoted glob per FRICTION 2026-10-26 (bare dir arg fails on this Node build). Gate after this ticket: **exit 0, zero failures — the external-red exception is retired, any red here is now a real red.**
- targeted: `node --test tests/opencode/pipeline-locks-tick.test.ts` (T2 must pass).
- bash battery: `bash tests/provider-loops/surface.sh` — zero `FAIL:` lines and exit 0 (t1 must pass; t3/t4 untouched).
- scope-guard battery: `bash tests/agent-perms/surface.sh` — A9 re-run after T-5 widens `tests/agent-board-coord/gate.sh` t14's allow-set (user-ruled approved-scope widen, DECISIONS 2026-11-02 coord entry) → zero `FAIL:` lines, exit 0; proves the t14 window mechanics survive the three admitted literals.
- pin parity (offline, encoded as a test): `node --test tests/opencode/aislop-pin-parity.test.ts`.
- manual parity spot-check: `grep -n 'AISLOP_VERSION' .opencode/plugin/aislop-gate/index.ts; grep -n 'aislop@' .github/workflows/aislop.yaml` → one and the same version string everywhere.
- one-off (network; NOT a permanent gate — registry moves): `npx --yes aislop@0.20.0 scan --changes` on the ticket's diff == what the gate would report (equal versions ⇒ equal scorer). Record the output line in the dev RESULT (`aislop@0.20.0 scan => pass|findings`); per the sibling's accepted precedent, if the worktree is offline, aislop-gate plugin coverage on every write is the accepted shape.
- no helm scope: `helm lint`/`helm template` are N/A for this ticket (no chart files in blast radius).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Re-pin tick-loop model mirrors + align & guard the aislop version pins | S | 1 | [] | — |

## Wave order
1. C01 — single chunk: four S tasks in the same test/gate-machinery neighborhood (two stale-pin re-pins, two pin bumps + one parity guard). Grounding shows no interference with anything else; splitting would only add handoff cost.

## Risks / assumptions
- **GPU catalog churn**: `gpu-ai/qwen3.8-flash-next-strata` may stop being served someday; per the t3 convention the pins move only with a fresh owner ruling — a re-pin ticket then, never a blind weakening here.
- **Newer scorer may flag more**: 0.20.0's findings are not identical to 0.18.1's (sibling saw 99-vs-100 on the *same* diff — this time in the newer scorer's favor). CI gates only PR-changed files, so exposure is bounded; the blast radius here is two test files + two machinery files, all of which will pass a local 0.20.0 scan before hand-off.
- **Detached HEAD worktree**: the branch `bug-pipeline-locks-tick-pin` doesn't exist at plan time (verified `git worktree list`: detached at 4781f56fe). Branch creation + commits are coord-owned (ticket is local-only: dev commits nothing; the coordinator commits after approval).
- The AGENTS.md recipe line ("aislop runs via npx") stays unversioned — pinning human invocations would be a rulesync-surface change; recorded in DECISIONS as a follow-up candidate, deliberately out of this ticket.
- **t14 fail-fast blind spot (test(C01) discovery, 2026-11-02 — resolved by user ruling):** the plan-time verification of `surface.sh`'s blast radius died at the stale t1's FAIL and never reached t6's nested `gate.sh` t14 leg — the scope guard reddens on this ticket's own plan folder and the two aislop pin files T-3 touches (invisible at plan time; retirement of that blind spot noted at chunk AC3). Resolution: T-5 widens t14 with the three ruled literals (cf-85/cf-72/cf-90 own-folder + cf-86 chunk-declared-files precedents; AC6 now six paths). Lesson for later plan rounds: batteries whose legs nest other suites must be re-run to full footprint after fixing the first red before any blast-radius claim is final.
