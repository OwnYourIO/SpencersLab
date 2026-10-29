# PLAN: agent-board-coord support for parallel loops (lease-lock pipelines)
feature: 2026/2026-10-cf-76-feat-parallel-pipeline-loops

## Goal

Give the WeKan AI-Dev board pipeline lease-lock concurrency: an OpenCode v2
plugin (`pipeline-locks`) owns one lock file per pipeline, where a card's
pipeline set is its board **labels** starting with `Pipeline:` (the trimmed
remainder is the lock name; no such label ⇒ the single `default` pipeline;
one card may block several pipelines and is claimed all-or-nothing). Cards
whose pipeline sets are disjoint run as parallel `agent-board-coord` loops;
overlapping sets stay serialized. An hourly OpenChamber loop file fires a
plugin-owned `/pipeline-tick` command that reaps stale locks (> 2 h without
heartbeat, moving the card to a new **Timeout** list with a Home Assistant
phone alert) and then runs one worker iteration. Along the way: rename the
research handoff's "ralph" naming to "pipeline", reuse the repo's existing
plugin/MCP precedents, document the board additions (**Timeout** list via a
coordinator-created follow-up card; `Pipeline:` labels human-created), and
move git-commit ownership from the pipeline implementers to the coordinators.

The request is card #76's description: the embedded "Ralph Loop Workers on
OpenCode v2 + OpenChamber" handoff document, overridden by the user's four
notes and the 2026-10-29 batched-round rulings (DECISIONS r2: labels instead
of a custom field, 2 h stale window, keep-alive rejected).

## Out of scope

- No changes to the WeKan server, the wekan-mcp container image, or its
  26-tool surface — the missing `create_list` tool is a coordinator-created
  FOLLOW-UP CARD (D22), not work of this run; there is no `create_label`
  tool either and this plan does not ask for one (labels are human-owned,
  D19). Until the follow-up lands, the reaper degrades to
  `.pipeline/timeouts.jsonl` + card comment.
- No creation or mutation of board labels by any agent — `Pipeline:<name>`
  labels are created by the human in the WeKan UI (the Research-label
  posture); the plugin/worker only reads labels.
- No changes to the hourly gate (`scripts/agent-board-coord-gate.sh`,
  `/pipeline-boards-hourly`) — it stays the manual/scheduled fallback through
  the transition (Q5 confirmed); the OpenChamber task re-point is user-owned.
- No worker-slot cap (`maxWorkers`): deferred, config key reserved (Q8 confirmed).
- No OS-level cron reaper (handoff Part C option d) — locks cannot be held
  while the server is down.
- No changes to standalone `dev`/`dev-local`/`dev-pr`/`code`/`debug` agents
  or their contracts — the commit-policy change is scoped to the pipeline
  (`agent-*`) family (Q3 confirmed).
- No docker/helm/chart work; this is agent-context work.

## Verified facts (evidence in DECISIONS.md)

- OpenCode v2.1.4 installed (`opencode --version`); plugins here are plain
  `{ id: "local.<name>", setup(ctx) }` objects in `.opencode/plugin/<name>/index.ts`
  (question-notify, board-context, aislop-gate precedents) — NOT `Plugin.define`.
- Raw MCP JSON-RPC from plugins is proven twice: ha-mcp push
  (question-notify) and dev-boards fetch (board-context) — URL discovery via
  `ctx.mcp.transform` → `ctx.mcp.list()` → project-config-text fallback.
- wekan-mcp has `get_board` (board labels `{id,name}`), `get_card` (card
  `label_ids` + custom fields), `move_card`, `add_comment` but NO
  `create_list` and NO `create_label` (source-checked
  `containers/wekan-mcp/wekan_mcp/server.py` 2026-10-29) → Timeout-list
  creation is a follow-up card (D22); `Pipeline:` labels are human-created
  and only READ here (D19).
- Node v26 type-strips `.ts` directly: plugin test suites run as
  `node --test tests/opencode/<file>.test.ts` (no build step, no deps) —
  existing pattern of the four `tests/opencode/` suites.
- Plugins load per directory and one server process hosts several locations
  (opencode.log shows the main checkout and worktree plugins loading in one
  process) → lock design must stay cross-process safe (O_EXCL + reaper lock).
- OpenChamber loop files: `.agents/loops/*.md`, frontmatter
  `name|schedule(cron)|enabled|model|agent|timezone`, body = prompt (may be a
  slash command), off by default, repo loops wait for local enablement
  (docs.openchamber.dev/scheduled-tasks, fetched 2026-10-29).
- AI-Dev board lists (boards skill): Not Started, Executing, Review, Rework,
  Finished, Low Priority in swimlane "In Process"; Review is the agent's
  final destination, Finished is human-owned; custom fields today: `slug`,
  `session`.
- Coord agents ALREADY carry `git add *`/`git commit *` allows and commit
  each chunk (pipeline-role-coord §git); pipeline implementers carry the same
  allows today (permissions.md role matrix, agent-dev-local source).
- CI drift gate: `npx --yes rulesync@37.0.0 generate --check`
  (`.github/workflows/rulesync.yaml`).

## Commands

Validation contract for test/dev/review (agent-context work — no helm):

- test (per file, basenames duplicate across suites):
  - `node --test tests/opencode/pipeline-locks-core.test.ts`
  - `node --test tests/opencode/pipeline-locks-engine.test.ts`
  - `node --test tests/opencode/pipeline-locks-reap.test.ts`
  - `node --test tests/opencode/pipeline-locks-tick.test.ts`
  - existing siblings must stay green: `node --test tests/opencode/question-notify.test.ts`,
    `permission-ask-notify.test.ts`, `board-context.test.ts`, `ha-mcp-url.test.ts`
- surface suites (bash, after any `.rulesync/` edit):
  - `bash tests/agent-perms/surface.sh`
  - `bash tests/standalone-agents/surface.sh` (unchanged rows stay green)
  - `bash tests/agent-board-coord/rulesync-surface.sh`
  - `bash tests/coord-inwork/surface.sh`, `bash tests/kickoff-branch/surface.sh`,
    `bash tests/session-origin/surface.sh` (splice projections strip the git
    block — expect green; run as regression)
- rulesync: `npx --yes rulesync@37.0.0 generate --check` (must pass; run
  `npx --yes rulesync@37.0.0 generate` twice — second run no-op)
- quality gate: `npx aislop ci --changes` (CI parity) + the aislop/
  comment-slop skills per AGENTS.md
- plugin syntax: covered by the node --test imports (Node strips types; a
  syntax error fails the import)
- grep pins (chunk ACs cite the exact patterns)
- NOT applicable: `helm lint`/`helm template` (no chart touched)
- Human/deferred (need the live OpenChamber+OpenCode server; checklist lives
  in chunks/C06.md): loop-file Run-now dispatch, overlapping ticks, crash
  recovery, subagent heartbeat, location isolation.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Verify the OpenCode v2 plugin-platform facts ([VERIFY] list) | M | 1 | [] | none — independent fact-finding |
| C02 | Commit policy: coord owns commits, pipeline implementers lose commit | M | 1 | [] | none — independent of the plugin (agent-context note 4) |
| C03 | pipeline-locks plugin core: lock files + the four tools (all-or-nothing set claim) | L | 2 | [C01] | tool names, storage/instruction API shapes come from C01 evidence |
| C04 | heartbeat & lifecycle engine: hooks, events, timers, lock-lost | L | 3 | [C03] | builds on C03's lock store + module seams |
| C05 | reaper + dev-boards move + HA alert + reap/status commands | L | 4 | [C04] | reaper mutates C03/C04 lock state; shares module seams |
| C06 | `/pipeline-tick` + loop file + config + AGENTS section + live-smoke runbook | M | 5 | [C05] | tick executor calls the reaper; ships the runtime surface |
| C07 | board wiring: boards skill, board-coord tool permissions, labels + follow-up card | M | 6 | [C06] | skill text + permission rows pin the final tool/command names |

## Wave order

1. C01, C02 (independent — no shared files; run in id order, the pipeline is serial anyway)
2. C03
3. C04
4. C05
5. C06
6. C07

C03→C04→C05→C06 all edit `.opencode/plugin/pipeline-locks/index.ts` — kept
strictly sequential (interface growth: store → engine → reaper → commands).
C02 and C07 both touch `.rulesync/` sources but disjoint files; C07 still
waits for the tool names C01 proves and C03–C06 ship.

## Risks / assumptions

- **v2.1.4 gaps.** `ctx.event.subscribe({types})` needs ≥2.2.0 per the
  handoff → subscribe without the filter and filter in code (question-notify
  precedent). `ctx.command.transform`, `ctx.session.instructions.entry.put`,
  `ctx.storage`, `ctx.location.project.canonical` are all C01 [VERIFY] items
  with degraded fallbacks recorded per chunk — none may hard-block shipping.
- **Plugin command dispatch from a loop file is unproven** (handoff B.6) —
  C06 ships a fallback plain-text loop body; determinism then rides on
  claim-time + timer reaping.
- **Human stops consume the stale window (D20).** Plan-approval pauses idle
  the session; the clock keeps ticking by design. Answer within the 2 h
  window and ordinary tool/turn heartbeats resume the lock; past it, the
  reaper reaps → Timeout → HA alert like any other stale lock. The run stops
  at its next PIPELINE LOCK LOST signal; no waiting-detection machinery, no
  re-claim dance.
- **Multi-instance safety:** one server process loads the plugin per location
  (log evidence); O_EXCL claims + `mkdir`-based reaper lock keep it safe.
  Overlapping claims on intersecting pipeline SETS resolve by sorted-order
  acquisition + rollback (D18) — no deadlock, no partial holds.
- Lock dir `.pipeline/` resolves against the canonical repo root so worktree
  sessions share it (fallback chain in C03); `.pipeline/` gitignored. Until
  this branch lands, locks in the main checkout are merely untracked.
- The old hourly gate still fails closed on ANY live board-coord session; it
  is not on the new tick path, and the two entry points must not run side by
  side against the same card — transition is user-owned (Q5 confirmed).
- Board structure: `Pipeline:<name>` labels are human-created (D19) and the
  **Timeout** list lands via the coordinator's follow-up card (D22). Until
  labels exist, every card reads as the single `default` pipeline
  (serialized — today's behavior); until the Timeout list exists, reaped
  cards queue in `.pipeline/timeouts.jsonl` + card comment and the flow
  degrades, never blocks. A mis-named label (typo'd `Pipeline:` prefix)
  silently falls back to `default` — the claim comment records the derived
  set so drift is visible on the card.

## Open questions

All questions from the 2026-10-29 batched round are ANSWERED and recorded as
decisions (DECISIONS.md r2: D17–D22) — no open question blocks any chunk:

1. **Slug** — RESOLVED: keep `cf-76-feat-parallel-pipeline-loops` (no renames).
2. **Tick model** — RESOLVED: `openrouter/qwen/qwen3.8-flash` (C06 constant).
3. **Commit policy** — RESOLVED: confirmed as planned (C02 stands; D7).
4. **Timeout list** — RESOLVED via follow-up card: coord creates a Not
   Started card requesting a `create_list` tool in `containers/wekan-mcp`;
   until then the reaper uses `timeouts.jsonl` + card comment (D22; C05/C07).
5. **Transition** — RESOLVED: keep gate + `/pipeline-boards-hourly` as
   fallback; loop ships `enabled:false`; user re-points after live smoke.
6. **Human stops** — RESOLVED (keep-alive REJECTED): the clock keeps ticking
   through stop points; stale window lapses reap like any other stale lock
   (D20). Stale window = 2 h (D21).
7. **Failure policy** — RESOLVED: `releaseOnFailure:false` confirmed (D12).
8. **Concurrency cap** — RESOLVED: `maxWorkers` deferred, config key reserved.

**User directive (label-based pipelines):** pipeline identity is board
LABELS starting `Pipeline:` (remainder = lock name; a card may block several
pipelines; no such label ⇒ the single `default` pipeline). Labels are
human-owned and only READ by the worker (D17–D19).