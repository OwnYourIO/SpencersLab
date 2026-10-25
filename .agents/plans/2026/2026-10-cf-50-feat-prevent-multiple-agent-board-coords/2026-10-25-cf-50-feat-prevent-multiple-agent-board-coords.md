# PLAN: agent-board-coord debounce gate (WeKan card #50) — FINAL (approval-round resolutions applied)
feature: 2026/2026-10-cf-50-feat-prevent-multiple-agent-board-coords

## Goal
The hourly scheduled launch of `agent-board-coord` is gated before any board action: a deterministic `!`-block script in a NEW scheduled-only command (`/pipeline-boards-hourly`) evaluates the OpenCode-session operand, and the agent evaluates the WeKan-Executing-list operand — via the **dev-boards MCP** (the user's ruling; server-side creds, none in the launch path) — only when the session operand says live. Fail-closed on either operand; manual `/pipeline-boards` runs stay byte-frozen and unguarded.

## Out of scope
- Loop files / `.agents/loops/` artifacts (approval answer: re-point the existing hourly UI task's prompt instead — Landing note).
- Any WeKan credentials in the script or repo (the MCP deployment holds them server-side; no env file, no creds step).
- Scheduler-side "skip-if-running" (verified absent); suppressing the session a SKIP still creates (one reporting turn, zero board actions — D10).
- Guarding `agent-coord` / the manual path / any change to `.rulesync/commands/pipeline-boards.md`, the boards skill flow, or `agent-board-coord` frontmatter (all byte-pinned by tests).
- Killing or interrupting a detected live session.

## Predicate — who evaluates what, when (D11/D16/D17)
| # | Session operand (`!`-block script, deterministic) | Board operand (agent turn, read-only dev-boards MCP) | Verdict | Reading |
|---|---|---|---|---|
| 1 | no live board-coord ⇒ `GATE: RUN` | never evaluated (short-circuit — the GATE itself has zero board dependency) | **RUN** | the common hourly case (the post-gate flow still needs dev-boards for pickup, like any run) |
| 2 | live ⇒ `GATE: LIVE <id>` | Executing empty ⇒ proceed | **RUN** | user's between-cards case; accepted narrow double-claim race (D11) |
| 3 | live ⇒ `GATE: LIVE <id>` | ≥1 card ⇒ stop | **SKIP** | both busy — the overlap this ticket exists to prevent; report names session id + card titles |
| 4 | live ⇒ `GATE: LIVE <id>` | check unavailable (MCP error / unresolvable list) ⇒ stop | **SKIP** | per-operand fail-closed — cannot prove the disjunct |
| 5 | detection failed ⇒ `GATE: SKIP <reason>` | never evaluated | **SKIP** | OQ2 fail-closed (session side can never be rescued by the board side) |
| 6 | crash-resume: no live session (past 15-min window), card stuck in Executing | never evaluated | **RUN** | Executing alone never blocks; intake-D11 resume check continues the folder |
| 7 | one-off manual via `/pipeline-boards` | — | **unguarded** | the guard exists only on the scheduled command; a live MANUAL coord session does count on rows 2–4 for later scheduled fires (past its grace) |

## Commands
- `bash tests/agent-board-coord/gate.sh` — new (agent-test): C01 session-side fixture matrix (t1..t10, `--json` live-envelope fixtures, `GATE_NOW_MS` fixed clock) + C02 surface greps incl. manual-path invariance (t11..t17). Written ONLY from fixture data — agent-test calls NO MCP (pinned; offline-deterministic suite).
- `bash tests/agent-board-coord/rulesync-surface.sh`, `bash tests/agent-board-coord/agents-md.sh` — must stay green; pin breakage ⇒ `validation_at_fault` hand-back, fix routed to the test session.
- `rulesync generate` (37.x PATH / npx ladder, skip-with-warning = intake-ticket t14 precedent) ×2 — second run no-op; sources + generated committed together.
- `npx --no-install aislop ci --changes` — 0 errors on touched files.
- Live controls (manual, recorded in Review notes — never CI): C01 — bare script against the workspace server, exit ∈ {0,1,2} with a valid marker; while this ticket's coord tree is fresh it must return `GATE: LIVE <coord-id>`. C02 — review uses READ-ONLY dev-boards calls (`list_boards` → AI-Dev; lists under `In Process`; `list_cards_in_list` on `Executing`) to confirm the board operand's resolution matches what the human sees on the board. Review has `dev*` MCP allowed (matrix), agent-test/dev do not need any MCP for this design.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Session-side gate: `scripts/agent-board-coord-gate.sh` (RUN/LIVE/SKIP, 15-min staleness + child rule, fail-closed) | S | 1 | [] | — |
| C02 | `/pipeline-boards-hourly` command: gate `!`-block + LIVE-branch dev-boards BOARD CHECK protocol (+ body pointer, rules lines, regenerate, landing note) | M | 2 | [C01] | Interface: the command's decision rule keys on C01's three stdout markers and exit states; the guarded path cannot ship before the detector exists. |

## Wave order
1. C01
2. C02

## Risks / assumptions
- **LLM-relayed decisions, two of them**: the SKIP report (row 3/4/5 after the agent reads the gate/LIVE state) and the board operand itself (rows 2–4) run as agent turns on deterministic evidence — the class D10 already accepted; the session side (row 1/5, the common case) stays fully deterministic. Command text minimizes the judgment: marker-keyed rules, read-only tool allow-list, explicit write-deny list.
- **Board-name drift in two surfaces**: `Executing`/`In Process`/`AI-Dev` now appear in both the boards skill and the hourly command. Mismatch fails CLOSED (unresolvable ⇒ skip), the safe direction; the boards skill remains the flow's authority.
- **Silence gap** (one child tool call > threshold ⇒ not-live ⇒ row 1 RUN during a real overlap) — `--threshold` tunable; residual documented in script + command comments.
- Probes still open (C01 evidence tasks): `GET /api/session` cursor pagination; `/api/session/active` semantics (`{"data":{}}` while busy, unresolved); `opencode api` ↔ the OpenChamber-scheduled server identity confirmation.
- `.rulesync/commands/` + `.rulesync/subagents/` edits and `rulesync generate` are ask-gated for dev — user approval prompts expected mid-C02 (precedent: the completed intake ticket, rulesync 37.0.0 on PATH).
- dev-boards live-status was evidenced this pass (tool catalog answers 25 tools; values `enabled: true` @ `wekan-mcp:v60`); if it drifts down, rows 2–4 fail-closed to SKIP, row 1 passes the gate but its post-gate pickup fails loudly at the MCP — the GATE itself never depends on the board.

## Resolved approval-round questions (no open questions remain)
- Rollout Q1 (creds) → **user override honored via D16/D17**: dev-boards MCP, split gate; no `~/.config/agent-board-coord-gate.env`, no creds anywhere.
- Rollout Q2 (landing) → **re-point the existing hourly UI task's prompt to `/pipeline-boards-hourly`** (hourly cadence, model `openrouter/qwen/qwen3.8-flash`, agent `agent-board-coord` — defaults confirmed keep); no loop file.
- Rollout Q3 (loop defaults) → moot.

## Landing note (user-owned steps, in order)
1. PR merges `cf-50-feat-prevent-multiple-agent-board-coords` → `main` (agent never merges/pushes — repo hard rule).
2. Edit the existing hourly OpenChamber scheduled task: prompt → `/pipeline-boards-hourly`; keep cadence `hourly`, model `openrouter/qwen/qwen3.8-flash`, agent `agent-board-coord`. No other task may keep a `/pipeline-boards` prompt (unguarded double-fire hazard — retire any duplicates).
3. First hour (or **Run now**): confirm the task's last-run session shows either a `GATE: RUN`-started claim, a `GATE: LIVE`→board-check proceed/skip, or a clean `GATE: SKIP` note — and that a manual `/pipeline-boards` session still starts with no gate line at all.
