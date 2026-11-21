# PLAN: Compaction and Pipeline Sessions (cf-126, card #126)
feature: 2026/2026-11-cf-126-feat-compaction-pipeline-sessions

## Goal
Move the scheduled board walk into ONE persistent shared session run by a dedicated dispatcher agent (adapted from `agent-board`) that finds the next pickable card and hands it to a fresh `agent-board-coord-local`/`-pr` session — the dispatcher sets the coordinator's model and variant from the card's checklist, the lock release wakes the dispatcher, and the board family's `Deployment` follow-up is its top-level `agent-dev-deploy-pr` spawn. On top: the compaction EVENT triggers a custom handoff instruction for EVERY session in this repo (the plugin hook, repo-wide — the OQ3 ruling 2026-11-17; no agent-facing compaction surface exists — the `*-coord` variants and the dispatcher get the full handoff protocol, the other agents the generic successor-bootstrap leg) that cuts the context to the 15-step-class tail, passes the card + planning folder to a fresh successor that bootstraps like `/pipeline-resume`, and closes; subagents signal context exhaustion via the built-in failure report and are relaunched fresh; the coord family gains full context-file reads + the `global-` MCP servers; and — gated on the owner ruling + the runbook 8-session receipt — the default local model flips to `gpu-ai/qwen3.8-27b-radiance`.

## Out of scope
- `agent-board` (the `/wekan-board-context` collector) — byte-untouched (D2); the `code`/`code-pr`, `dev` family, `ask`/`debug`/`review`/`planner` agents — untouched.
- Non-board `agent-coord` family's 8b subagent deploy launch — unchanged (D18 scopes the change to the board family).
- The lock engine's claim/heartbeat/reap mechanics — untouched except the release-wake leg (C01) and the `handoff` outcome token (C03, no logic branch on it).
- Board structure (lists, checklists, labels, rules) — human-owned, unchanged; the `Timeout` list and board-side cutover steps stand as before.
- The deploy agents' IMPLEMENTATION — definition-only per cf-90; nothing in this ticket executes them; the first fire stays owner-triggered.
- Any merge to `main` / push — the never-advance-`main` law stands; this run's D28 posture binds this run only (D17).

## Commands
Repo validation for this agent-context surface (no unit-test suite; "commands" = validation, per the repo contract):
- regenerate: `rulesync generate` — run TWICE; the second must be a no-op — then `rulesync generate --check`
- quality gate: `npx aislop ci --changes` (gate config `.aislop/config.yml`; score floor + zero error-severity findings on every touched file)
- plugin suites (repo root, Node v26 type-strips — no build, no deps, no network): `node --test tests/opencode/pipeline-locks-core.test.ts`, `node --test tests/opencode/pipeline-locks-engine.test.ts`, `node --test tests/opencode/pipeline-locks-reap.test.ts`, `node --test tests/opencode/pipeline-locks-tick.test.ts`, `node --test tests/opencode/board-context.test.ts`, `node --test tests/opencode/question-notify.test.ts`
- contract suites: `bash tests/agent-board-coord/gate.sh`, `bash tests/agent-board-coord/agents-md.sh`, `bash tests/agent-board-coord/rulesync-surface.sh`, `bash tests/agent-perms/surface.sh`, `bash tests/pipeline-models/surface.sh`, `bash tests/noop-marker/surface.sh`, `bash tests/cf106-noop/surface.sh` (per-chunk re-pins per each chunk's Tests section; the pre-existing reds stay byte-identical — the cf-124 two-tree sweep posture)
- config edits (C03/C04): JSONC parse of `.opencode/opencode.jsonc` (the repo's `strip_jsonc` → `json.loads` idiom, `tests/agent-perms/surface.sh` L1707) + `opencode models` (catalog resolvable; the q27 rows present)
- charts: `helm lint charts/radiance` + `helm template charts/radiance` ONLY if C04 leg 6 touches the chart (`export PATH=$HOME/.local/bin:$PATH` first)
- two-tree control: per-chunk, a detached worktree at the chunk's base re-runs the affected suites — only the chunk's designed reds flip; everything else byte-identical

## Verified facts (evidence at plan time, 2026-11-17)
1. `.agents/loops/pipeline-worker.md` L1-7: frontmatter `schedule: 0 * * * *`, `enabled: true`, `model: gpu-ai/qwen3.8-flash-next-strata-q4` (owner ruling 2026-11-09, L10-13), `agent: agent-board-coord` (verified this run).
2. `scripts/agent-board-coord-gate.sh` — the jq filter `map(select(.agent == "agent-board-coord" or .agent == "agent-board-coord-local" or .agent == "agent-board-coord-pr"))` (EXPLORE L227) — exact-name triple (verified this run).
3. `.opencode/plugin/board-context/index.ts` L117-121 — `BOARD_COORD_AGENTS` = the same triple (verified this run).
4. `.opencode/plugin/pipeline-locks/index.ts` — `releaseLockSet` L835-894: owner-check → holder removal → audit `ev: "release"` (carries `outcome`) → cleanup → `return {ok, released, setId}`; insertion point = after cleanup, before return (verified this run).
5. Same file L2122-2136 — the `/pipeline-tick` `say()` helper: `ctx.session.prompt({sessionID, text, delivery})` with a `logNote`-on-failure posture (verified this run — the proven "plugin wakes a session" pattern).
6. `.opencode/opencode.jsonc` L772-792 — the q27 trio: `qwen3.8-27b-radiance` (default priority, `body.priority: 4`), `-urgent` (8), `-low` (0); all wire `modelID: "qwen3.8-27b-radiance"`; the served-context 200000 comment block L748-752 (verified this run). No top-level `agents` key in the file (verified this run — the OQ4 ruling 2026-11-17 keeps it absent).
7. `.rulesync/subagents/agent-coord.md` — the six context read rows (L13-30: plans, `.opencode/skills`, `.agents/skills`, `skills`, `.agents/loops`, `.opencode/agents`) — the `.agents/**`-beyond-plans / `.opencode/**`-beyond-skills+agents / `.rulesync/**` / `AGENTS.md` gap confirmed; the own-session rows are get (L64-66) + patch (L67-69) only — no `post`; the `execute` allow + five `tools.opencode.*` pins (L373-390) include NO session-create tool; the subagent roster (L331-365) = plan/test/dev-local/code/review/research/explore/dev-deploy (verified this run).
8. `.rulesync/subagents/agent-board-coord.md` L391-411 — the board family adds `dev-boards*` + the four inert `pipeline_*` rows over the coord shape (verified this run); `agent-board.md` L66-75 — the collector's contract: board-MCP worker, writes no files, never a coordinator, `ls *`-only shell, MUST-loads `/wekan-mcp` + `/boards` (verified this run).
9. `.rulesync/skills/pipeline-models/SKILL.md` — blank Model(s) → `gpu-ai/qwen3.8-27b-q4` both tiers (L37 area); the Priority class table default row → `gpu-ai/qwen3.8-flash-next-radiance` (priority 5); the D54(4) clause "NEVER a default route … only after measurement ON THIS BOX" (L63 area); the favorited-models q27 row "NEVER a default route and no runner tier points here … the trio rides 8/4/0" (verified this run).
10. `.rulesync/rules/overview.md` L292 — the "## Pipeline worker iterations" section is the AGENTS.md section source; `rulesync.jsonc`: target opencode-only, features rules/subagents/commands/skills, `delete: true` (verified this run).
11. `tests/opencode/` — the node suites incl. `pipeline-locks-{core,engine,reap,tick}.test.ts`, `board-context.test.ts`, `question-notify.test.ts`; run `node --test <suite>` from the repo root (Node v26 type-strips; no build, no deps — the suites' own header, verified this run). `opencode --version` on this box = v2.2.6 (verified this run — the RESEARCH §5 drift fact).
12. OpenChamber docs (fetched 2026-11-17, direct): a scheduled task "starts a new session and sends the prompt on its own"; a loop that came with a repository waits for owner re-approval "after a change to its schedule, model or prompt" (the `loopApprovals` fingerprint — matches the loop file's own comment L22-26).
13. `.rulesync/subagents/agent-dev-deploy-pr.md` exists (the definition-only deploy fixer, cf-90 — verified this run); `fix-radiance-context` branch UNMERGED (EXPLORE L5 — the plan's C04 gate fact 2).

## Ask → chunk map
| Card ask | Chunk |
|---|---|
| (a) one shared session on a dedicated agent (adapt `agent-board`); timer runs find the card and hand it to a fresh `agent-board-coord` with the card info; evaluate removable coord logic | C01 (the dispatcher + the D5 evaluation answer) |
| (b) lock-release step triggers the shared session; the dispatcher sets the coordinators' model + agent (`-local` default; `Deployment` checked ⇒ `-pr` + the `agent-dev-deploy-pr` follow-up after final review) | C01 (the wake + the spawn contract + the D18 follow-up), C03 (the handoff wake nuance) |
| (c) + (f) coord agents: privs to read the context files (`.agents`, `.opencode`, and others) and the `global-` MCP servers | C02 |
| (d) compaction-event-triggered handoff instructions; the dispatcher starts as fresh as the mechanism allows; the coord variants pass the card + planning folder to a new session (with the needed privs — C02); subagents notify the coordinator of context exhaustion and get relaunched | C03 |
| (e) the `*-coord` sliding window (last ~15 steps, no per-turn clearing, pass context files + skills, fresh context bootstraps like `/pipeline-resume`); the coord triggers the shared session at lock clear and checks for other work | C03 (the window + the bootstrap law), C01 (the trigger doctrine — D6) |
| (f-model) the default model flips to `gpu-ai/qwen3.8-27b-radiance` | C04 (GATED — the owner ruling + the fix-radiance-context merge + the q27 pod scale-up + the runbook 8-session gate receipt) |

## Chunks
| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | The shared-session dispatcher (agent + loop vehicle + exact-name lists + release wake + Deployment-row/8b doctrine) | L | 1 | [] | — |
| C02 | Coord-family surface widening (read grant + global- MCP rows + session-creation rows, six variants) | M | 2 | [C01] | the coord rows mirror the dispatcher's shape (C01 is the template); the `agent-perms` + `rulesync-surface` re-pins land sequentially to keep the two-tree sweep clean |
| C03 | Compaction + handoff protocol (the repo-wide plugin hook — every agent, the OQ3 ruling — + `handoff` outcome + subagent relaunch doctrine + `keep.tokens`; the OQ4 conditional rows dropped — the session model) | L | 3 | [C02] | the handoff protocol points at the session-creation rows C02 lands; the `handoff` outcome's wake leg rides C01's trigger |
| C04 | 27b-radiance default-model flip (three doctrine surfaces + the runner literal) | L | 4 | [C01] | the runner literal lives in the loop file C01 creates (the frontmatter `model:` flip against C01's shipped shape); the USER gate facts are a plan-level precondition, not a chunk dependency |

## Wave order
1. C01
2. C02 (after C01 — shared test-surface re-pins + the row-shape template)
3. C03 (after C02 — the handoff needs the session-creation rows in place; C01's wake leg is its transport)
4. C04 (after C01 — the runner-literal leg; otherwise independent of C02/C03 — its ordering is the USER gate, not code)

## USER-owned steps (owner actions, never agent-executed)
1. (after C01) Create the new OpenChamber scheduled task from `.agents/loops/pipeline-dispatch.md` — `agent: agent-board-dispatch`, `model: gpu-ai/qwen3.8-flash-next-strata-q4` (the runner literal as written in the file), `schedule 0 * * * *`, `enabled: true` (the OQ1 ruling — a NEW task; the old `pipeline-worker` task/loop stays untouched, no re-approval).
2. (after C01, the cutover — the owner's timing) Delete the old `pipeline-worker` scheduled task (scheduler hygiene per the OQ1 ruling; during the overlap window the lock surface + the **Executing** membership dedupe the double walk — no card is lost).
3. (C04 gate) Merge `fix-radiance-context` (the 200000 → 262144 retarget; carries the runbook line's update to 262144 — OQ5).
4. (C04 gate) Scale the q27 pod up — fn DOWN first, then q27 up (the one-card/one-engine law; git renders `replicas: 0`).
5. (C04 gate) Run the runbook 8-session gate on the q27 lane at depth 262144 (OQ5) and supply the receipt (PASS = eight admitted without refusal-class errors + the read-only receipt list).
6. (after C04) Re-approve the `pipeline-dispatch` task on the `model:` frontmatter change (the docs' model-change re-approval — verified fact 12).

## Risks / assumptions
- The proxy indirection (D1): every tick pays one session spawn (today's cost — unchanged); a live dispatcher exists ⇒ the spawn forwards and ends (the `delegated` no-op exit). If the live-dispatcher lookup races a dispatcher death, the tick's own walk runs (self-healing; the lock surface dedupes).
- The availability pre-check (dispatcher) → claim (coord) race: a rare occupied claim ends the coord `NEEDS_INFO`; the next tick re-walks — the card is never lost (a dead coord still rides the 2 h staleness → **Timeout** triage, human-owned).
- The compaction hook + `instructions.entry.put` ride the plugin API on the running build (box v2.2.6, plugin pins v2.1.4 semantics) — C03 verifies the contract on the running server BEFORE landing (RESEARCH §5: verify flag-gated/experimental surfaces on the running version; a hook failure must degrade to the default compaction, never fail the session).
- A `handoff` release frees the lock for a short window; the card's **Executing** membership keeps it out of the walk — no double-claim path (membership alone means owned).
- C04 before the pod scale-up routes default traffic to a resting pod = 502 peer-proxy refusals (loud, never silent) — the gate order is strict (merge → scale → receipt → flip).
- `read *` on the coord family exposes `.opencode/opencode.jsonc` (provider config) — the owner's explicit ask; the `*.env*` deny stays the only read exclusion (D12).
- The pre-existing red pins (the test ledger) stay byte-identical in every chunk's two-tree sweep (the cf-124 posture).
- The cutover overlap window (the OQ1 ruling): until the owner deletes the old `pipeline-worker` task (USER step 2), both the old walk and the dispatcher walk are scheduled — a same-card double pick is deduped by the lock surface (a free-at-check, occupied-at-claim race ends the coord `NEEDS_INFO` → re-walk) and the **Executing** membership (a claimed card is out of the walk) — no card is lost; the window is bounded by the owner's hygiene step, not by this plan.
- The summaries run on the session's own model (the OQ4 ruling — no `agents.compaction.model`): the 27b-radiance sessions inherit the #59110 reasoning-budget failure class (a 27b model with a small output cap) — an ACCEPTED exposure (the ruling's recorded consequence); the mitigations are the hook's small-pointer summary shape (D9 deliberately omits what's-done/what's-next) and a FAILED compaction being the primary-signal path (the relaunch-fresh doctrine, C03), never a silent success.

## Open questions — CLOSED (owner rulings 2026-11-17; the batched round resolved; the rulings' verbatim text with rejected alternatives is in DECISIONS.md)
- **OQ1 — The loop vehicle.** Ruling: SECOND DISPATCHER FILE — a new `.agents/loops/pipeline-dispatch.md` (the plan's naming); `pipeline-worker.md` stays byte-untouched (no fingerprint rotation, no re-approval of the old loop). The owner's USER steps: create the new OpenChamber scheduled task (frontmatter model/agent per the plan) + the later deletion of the old task as scheduler hygiene. (The best guess — repurpose in place — was rejected by the ruling.)
- **OQ2 — The dispatcher's gate semantics.** Ruling: ACTIVE-ONLY gate semantics (as planned — the best guess held).
- **OQ3 — The compaction hook scope.** Ruling: ALL AGENTS — the plugin covers every agent in this repo, not just the six `*-coord` variants + the dispatcher (the event carries the agent id and selects the instruction variant — the coord/dispatcher full protocol vs the other agents' generic leg; the instructions apply repo-wide). Accepted blast radius (the ruling's recorded consequence): every session's compaction summaries in this repo are re-shaped. The subagent leg stays as doctrine (built-in failure report + relaunch-fresh + HA alert — no per-subagent hook).
- **OQ4 — `agents.compaction.model`.** Ruling: SESSION MODEL — no `agents.compaction.model`, no new top-level `agents` map in `opencode.jsonc`; summaries run on the session's own model; C03's conditional rows for the flash lane dropped (the #59110 failure class stays documented in Risks as the accepted exposure).
- **OQ5 — The D54(4) receipt depth.** Ruling: 262144 (the runbook line updates with the `fix-radiance-context` merge; C04 cites 262144).
- **OQ6 — The session-creation mechanism.** Ruling: agent-side shell rows (as planned — the best guess held).
- **OQ7 — The mid-project handoff lock release.** Ruling: the new `handoff` outcome token (as planned — the best guess held).
- **OQ8 — The read-widening shape.** Ruling: `read *` + the `*.env*` denies after it (as planned — the best guess held).
- **OQ9 — The `global-` MCP grant set.** Ruling: the six global- MCP rows, `admin-global-*` denied (as planned — the best guess held).
- **OQ10 — The `delegated` no-op token.** Ruling: the sixth `delegated` no-op token (as planned — the best guess held).

## Decisions (summary — the full log with rejected alternatives is in DECISIONS.md)
D1 the SECOND dispatcher loop file `.agents/loops/pipeline-dispatch.md` (the old `pipeline-worker.md` byte-untouched — supersedes the in-place D1 per the OQ1 ruling) · D2 new `agent-board-dispatch` (collector untouched) · D3 top-level spawned coord · D4 the dispatcher walks up to the claim; the coord claims · D5 the walk stays in the coord as the fallback (the evaluation answer) · D6 the plugin-side release wake (every non-empty release) · D7 the `handoff` outcome token · D8 the compaction hook covers EVERY agent in this repo (repo-wide; the event carries the agent id; the accepted blast radius — supersedes the agent-set D8 per the OQ3 ruling) · D9 summary injection + the `instructions.entry` note (the coord/dispatcher full protocol; the other agents the generic leg) · D10 the `/pipeline-resume` bootstrap (no new mechanism) · D11 the agent-side session-creation rows · D12 `read *` + the env denies · D13 the six global- MCP rows · D14 the runner literal unchanged in C01 (the new file's frontmatter), flipped in C04 · D15 the dispatcher's no-op exits + the `delegated` token · D16 the vacuous `Deployment` HITL stop (a fact) · D17 this run's D28 posture binds this run only · D18 the board family's top-level deploy follow-up · D19 the `keep.tokens` convention + the no-per-turn law.
Rulings 2026-11-17 (the batched OQ round — verbatim in DECISIONS.md): OQ1 second dispatcher file (`.agents/loops/pipeline-dispatch.md`; the old loop byte-untouched; the owner creates the new task + deletes the old) · OQ2 active-only gate · OQ3 all agents (repo-wide hook; the accepted blast radius) · OQ4 session model (no summary-model rows) · OQ5 262144 receipt depth (the runbook line updates with the merge) · OQ6 agent-side shell rows · OQ7 the `handoff` token · OQ8 `read *` + the env denies · OQ9 the six global- MCP rows (admin denied) · OQ10 the `delegated` token.

## Plan approval
- [x] Owner approval LANDED 2026-11-17T03:42 (the plan-approval gate — the truthful approval instant; a later 2026-11-19 date in the coordinator's records is the `plan_status` flip entry, not the approval itself). The batched OQ1–OQ10 round had LANDED (owner rulings 2026-11-17 — recorded in DECISIONS.md with the rejected alternatives; the plan re-worked on them) before approval.
