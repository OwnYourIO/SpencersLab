# PLAN: Update agents to use strata flash (WeKan card #83)
feature: 2026/2026-10-cf-83-refactor-strata-flash

## Goal
Re-route the pipeline's local-flash combination (kickoff/checklist `Qwen Flash` + `Local`) from `gpu-ai/qwen3.8-flash-next-q3` to the new Strata-served `gpu-ai/qwen3.8-flash-next-strata` in the three contract sources the `agent-*coord` families load (`pipeline-models`, `pipeline-kickoff`, `boards`), regenerate the surfaces, and re-pin the validation suites that pin the old id. Out of scope: the serving stack (chart/service values, provider catalog — cf-77 already landed all of it), the subagent bodies, and this run's own model routing.

## Verified facts (evidence)
- **The real route id is `gpu-ai/qwen3.8-flash-next-strata`.** Provider catalog `.opencode/opencode.jsonc` L695–708: modelID `qwen3.8-flash-next-strata`, name "Qwen 3.8 Flash Next (Strata IQ3_S arena, R9700)", `capabilities.tools: true`, `limit.context: 262144`. The card's loose `strata/qwen3.8-flash-next-strata` spelling is the llama-swap **peer-qualified** model name at the HTTP surface (`<peerID>/<modelID>`, cf-77 RESEARCH O1; `.agents/notes/strata-host-prep-gpu-ai.md` L335–336: "bare inner ID routes per O1; `strata/...` always routes") — not an OpenCode provider/model pair.
- **Serving authority**: outer llama-swap `peers.strata.models = [qwen3.8-flash-next-strata, qwen3.8-flash-next-strata-strix]` (`services/gpu-ai/prod/values.yaml` L450–458, proxy `http://gpu-ai-llama-swap-strata.default.svc.cluster.local:8080`, `timeouts.responseHeader: 1800` — cold start pins the ~47 GiB arena and takes minutes); inner chart catalog `charts/llama-swap/values.yaml` L1411/1450/1505/1544–1545, matrix `(p | s)` (primary/strix alternate, never co-load). Peer models stay OUT of the outer matrix — the flash-next-q3/q4 **SOLO-eviction clause no longer describes the default route** (it describes the legacy q3/q4 rungs, which remain in the outer solo set).
- **Live**: `gpu-ai-llama-swap-strata-58d79d88f9-25w5s` Running 1/1 (age 10 h) and outer `gpu-ai-llama-swap-...` Running 2/2 — `readonly-ai-gpu-kubernetes` pods_list, 2026-10-29.
- **Contract surface = exactly 3 source files, 4 spots**: `.rulesync/skills/pipeline-models/SKILL.md` L31 (combination rule) + L49 (favorited-table row), `.rulesync/skills/pipeline-kickoff/SKILL.md` L26, `.rulesync/skills/boards/SKILL.md` L120–122. No `.rulesync/subagents/agent-*.md`, command, or rules source contains any model id (grep `flash-next|qwen3.8-flash` over `.rulesync/`: only those 3 files) — the coord twins (`agent-coord`/`-local`/`-pr`, `agent-board-coord`/`-local`/`-pr`) share these skills via `/skill` loads, so the skill edit + regenerate IS the twin-synchronous change (one commit, all variants). AGENTS.md / `.rulesync/rules/` carry no flash reference.
- **Generated mirrors** = `.opencode/skills/{pipeline-models,pipeline-kickoff,boards}/SKILL.md` only (full-tree find; no `.agents/skills` copies) — `rulesync generate` owns them. `rulesync` 37.0.0 on PATH in this worktree.
- **Validation surface pinning the old id**: `tests/pipeline-models/surface.sh` M1 (L152–155, L166–167), M2 (L190), M4 (L258 id list), M5 (L283); `tests/agent-board-coord/rulesync-surface.sh` c11 (L495–496). `tests/opencode/pipeline-locks-tick.test.ts` L158 and `.agents/loops/pipeline-worker.md` L5 pin `openrouter/qwen/qwen3.8-flash` (this run's/worker's provider-side model, not the local route) — untouched. `c17`'s byte-freeze of the pipeline skills is a documented no-op (cf-58 re-opened `pipeline-models` the same sanctioned way).
- **Suite baseline on this branch @ eb8a963** (2026-10-29, run here): `surface.sh` M1/M2/M4/M5/M6 green; **M3 structurally red** — its catalog-delta arm requires exactly +2 added entries vs `TB=$(git merge-base main HEAD)` AND a tools-less q4 at base, which self-contradict once cf-58/cf-77 catalog state is in the base itself (output: "added entries are []…; q4: fields other than capabilities changed"). `rulesync-surface.sh` full: 19 ok, ~3 s. `rulesync generate --check` clean.

## Open questions — ANSWERED (2026-10-29 batched round, human via coord)
- **Q1 (answered): "Strata default, q3 stays a documented alternate row"** — the Flash+Local combo routes to `gpu-ai/qwen3.8-flash-next-strata` by default in all three rule spots; `qwen3.8-flash-next-q3` is NOT deleted from knowledge: it remains a documented explicit-request alternate **in the combination-rule wording**. Per the single-authority convention (`pipeline-kickoff` "never restate its table", `boards` "reference it, never duplicate its table"), the *named* q3 alternate lives in the `pipeline-models` combination bullet only; kickoff/boards swap the route id and keep the generic "other flash-next quants only on explicit request" escape — q3 is then one of those quants, documented at the authority. The pre-final plan's zero-q3-across-all-six guard is superseded (see C01 AC1).
- **Q2 (answered): "Replace q3 row with strata row"** — the favorited table carries exactly ONE gpu-ai flash-next row, keyed `qwen3.8-flash-next-strata` (no two-row table); its SOLO-eviction clause handling follows the existing plan stance (replaced by the peers/arena cold-start clause). q3's alternate status lives in the rule bullet, never as a table row.
- **Q3 (answered): "Yes, operations clause only"** — `-strix` is named only inside the `pipeline-models` favorited row's operations clause; never a route.
- **Q4 (answered): "No catalog edits"** — `.opencode/opencode.jsonc` and machine-global config stay untouched; cf-77 landed what the route needs.
- **Slug (answered): "Keep cf-83-refactor-strata-flash"** — confirmed, no re-mint; every surface keeps the existing name.
- (Test-internal, never a user question: M3 re-basing design, recorded as DECISIONS D5.)

## Commands
- test: `bash tests/pipeline-models/surface.sh` — full M1..M6, **no env overrides** (green required after C01)
- test: `bash tests/agent-board-coord/rulesync-surface.sh` — full c1..c18 regression gate
- regen: `rulesync generate && rulesync generate --check` — then a second `rulesync generate` must be a no-op (idempotence; sources and mirrors commit together)
- drift-grep: `git grep -n 'qwen3.8-flash-next' -- .rulesync/skills/pipeline-kickoff .rulesync/skills/boards .opencode/skills/pipeline-kickoff .opencode/skills/boards` — after C01 must show **only** `…-strata` hits (kickoff/boards carry no q3 text); `git grep -n 'qwen3.8-flash-next-q3' -- .rulesync/skills/pipeline-models .opencode/skills/pipeline-models` — after C01 must hit **only** in the combination-rule bullet (the documented alternate; never in the favorited table, never co-located with the `assume Qwen Flash Next:` route needle)
- scope: `git diff --name-only eb8a963..HEAD` + untracked check — every path in the C01 files-in-scope list
- quality: `npx aislop ci --changes` (AGENTS.md gate; floor + no error findings on touched files)
No helm validation applies — this ticket touches no chart/service (repo-appropriate agent-machinery validation is generation/diff/`--check`, per AGENTS.md "Pipeline specifics").

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Re-route local-flash combo to Strata + re-pin validation surfaces | M | 1 | [] | — |

Wave 1: C01 only. The ticket is one atomic contract change: the three source edits, their regeneration, and the test re-pins only make sense together — landing sources without the suite re-pin leaves `surface.sh`/`rulesync-surface.sh` red; re-pinning without sources is the designed red-before-dev state (`agent-test` lands it first, `agent-dev-local` greens it). No second dev chunk exists to split into.

## Wave order
1. C01 (agent-test writes the re-pinned suites first — expected red on the old sources; agent-dev-local edits sources + regenerates — suite green; agent-review re-runs all Commands + drift-grep + scope).

## Risks / assumptions
- Assumes Strata keeps serving (verified live today). If ArgoCD reverts cf-77, the M4 HOLD invariant (routed id present in the serving authority) goes red — correct behavior, not this ticket's failure mode.
- Cold-start cost shifts to every local-flash subagent launch (first request pins the ~47 GiB arena, minutes; outer `responseHeader: 1800` accommodates). Accepted operational trade per the card's intent; recorded in DECISIONS.
- `rulesync generate` may rewrite surfaces beyond the three mirrors if committed output has drifted; dev must verify `git status` against the expected file list and stop on anything else (agents-sync "diff after generate" rule).
- The machine-global `~/.config/opencode/opencode.json` (`gpu-moe` fleet copy) is outside repo management (AGENTS.md); if it routes a local-flash variant, that is a machine-local edit the user owns — flagged here, not touched.
- `tests/agent-board-coord/rulesync-surface.sh` c8 scope-allow list predates this ticket: without widening, the new plan folder reads as a scope violation when the suite runs against an uncommitted tree (cf-58/cf-75 landing-widening precedent; in C01's test scope).

## HITL
`PR` checked + plan-approval pause: after C01's final review, the branch is handed off for a user-created PR (never merged/pushed by the run unless the user explicitly asks; AGENTS.md git-safety rules apply unchanged).

## Final review (whole plan) — 2026-10-29, agent-review(chunk: final) — VERDICT: APPROVED

Scope: the complete change is the single commit `ea9a3daf2` against base `eb8a963` (chunk table: C01 only, wave 1 — this is the whole plan). Fresh tree at HEAD, clean before and after all runs.

Validation (full Commands block, this session, `PATH=$HOME/.local/bin:$PATH`, no env overrides):
- `bash tests/pipeline-models/surface.sh` (M1..M6) → PASS 6 ok, exit 0. M1/M2/M5 subset re-verified under `env -i` → PASS 3 ok, exit 0 (no hidden env dependency).
- `bash tests/agent-board-coord/rulesync-surface.sh` (c1..c18) → PASS 19 ok, exit 0.
- `rulesync generate && rulesync generate --check && rulesync generate` → PASS: check clean, both generates no-op; `git status --porcelain` empty afterwards (tree byte-identical; AC5). The suites' own M6/c7 run the same generate gates in-suite.
- drift-grep pair → exact Commands-stated shapes: kickoff/boards (src+mirror) show only `…-strata` hits with zero q3 text; PM `qwen3.8-flash-next-q3` hits only in the combination bullet (src L31 / mirror L32).
- scope: `git diff --name-only eb8a963..ea9a3daf2` = 5 plan-folder files + 3 sources + 3 mirrors + 2 suites ⊆ C01 Files in scope; no untracked files; every FORBIDDEN-list path untouched (`.opencode/opencode.jsonc`, subagents/commands/rules, AGENTS.md, charts/services, `.agents/loops`, `tests/opencode`) (AC6).
- `npx aislop ci --changes` → PASS, exit 0, score 100, 0 errors / 0 warnings / 0 fixable, 53 files (AC7).
- No helm validation applies (no chart/service touched — confirmed by the scope list).

AC walkthrough: AC1–AC8 all met, each covered by a passing validation (suite AC-trace header maps them). Coherence sweeps beyond the suite set: (a) old route string `assume Qwen Flash Next: \`gpu-ai/qwen3.8-flash-next-q3\`` survives only in the two absence-guard needles inside `surface.sh` (the guard itself) and in historical/plan documentation (cf-58's own folder, this ticket's C01 task text + STATE handoffs) — none is a contract surface; (b) repo-wide `flash-next` over `.rulesync`/`.opencode`/agents/commands/AGENTS.md hits only the 3 sources + 3 mirrors + the provider catalog — the plan's "exactly 3 source files, 4 spots" verified fact holds; no fourth contract surface fell between chunks; (c) remaining `qwen3.8-flash-next-q3` presences are all sanctioned: the PM bullet's documented-alternate sentence (Q1), the catalog entry (Q4/D7: no catalog edits; M3 HOLD keeps it honest), and the serving authorities' legacy q3 rungs (M4 invariant proves the alternate routes to a served id). Strata clause carries `peers` + `arena`, SOLO-eviction claim dropped, `-strix` confined to the one clause (src L49 / mirror L50 only, never route form), four-option picker + `Default selection: Qwen Flash` byte-stable, `strix`-absence guards pass on kickoff/boards (AC2/AC3, Q2/Q3).

User rulings + decisions: Q1–Q4 and slug honored (verified above); D1–D8 each implemented as recorded — D5's TB/CF58_BASE residue in `surface.sh` is comment-only provenance notes (grep confirms no code reference), the c17 byte-freeze arm remains the documented no-op the plan predicted.

Findings: no blocker, no major, no minor, no nit. No new chunk-specific comments for `chunks/C01.md` (its Round 1 APPROVED notes stand; re-validation this round reproduced them).

Handoff notes (human/coord-owned, not findings):
- HITL: branch `cf-83-refactor-strata-flash` carries the work as local commit `ea9a3daf2`; no upstream configured, nothing pushed. The PR is user-created. Stack topology: the branch sits on 11 unmerged cf-76-series commits above `origin/main` (`62bd3fa8b`) — a PR from this branch carries both series; landing order is the user's decision (cf-76's own closeout already sits at board Review).
- Coord bookkeeping (not reviewer-writable): FRICTION.md line 8 (surface.sh M3 structural-red, status `open`) can be re-statused `fixed` this run — M3 green measured here without env overrides; and STATE.json plan_status → complete on acceptance of this verdict.
