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

## FINAL whole-plan review

Fresh `agent-review` session, 2026-10-29, plain post-landing HEAD
`5ade6c54462fe9da3f709d90ccdfc25f5a9d3654` (base `26e3b7cee0a0…`), branch
`cf-76-feat-parallel-pipeline-loops`, clean tree. Scope: the whole plan —
Goal, Out of scope, every chunk AC, DECISIONS D1–D36 + r5/r6 rulings,
FRICTION resolutions, cross-chunk coherence.

### Validation battery (all run fresh, this session, at plain HEAD)

| Check | Result |
|---|---|
| `node --test tests/opencode/pipeline-locks-core.test.ts` | **30/30 pass** |
| `node --test tests/opencode/pipeline-locks-engine.test.ts` | **34/34 pass** |
| `node --test tests/opencode/pipeline-locks-reap.test.ts` | **20/20 pass** |
| `node --test tests/opencode/pipeline-locks-tick.test.ts` | **12/12 pass** |
| siblings question-notify / permission-ask-notify / board-context / ha-mcp-url | **35/41/28/15 pass** (all 8 files in `tests/opencode/` run — no additions beyond the eight) |
| `bash tests/agent-perms/surface.sh` | **15 ok — A15 GREEN**, no A15 red |
| `bash tests/standalone-agents/surface.sh` | **10 ok** |
| `bash tests/agent-board-coord/rulesync-surface.sh` | **19 ok** (c2 era-gate engaged, non-vacuous) |
| `bash tests/coord-inwork/surface.sh` | **7 ok** |
| `bash tests/kickoff-branch/surface.sh` | **6/6 ok — fully green at plain HEAD** (the documented merge-window red cleared at the landing commit, claim holds) |
| `bash tests/session-origin/surface.sh` | **7/7 ok — fully green at plain HEAD** (same) |
| `npx --yes rulesync@37.0.0 generate` ×2 + `--check` | both generates no-op ("All files are up to date"), `--check` rc=0 |
| `npx aislop ci --changes` | rc=0. CI-parity form (pinned `aislop@0.18.1 --changes --base origin/main`, and `--base 26e3b7cee0`) = **0 errors, 1 warning = D36 `complexity/file-too-large` on index.ts only**, score 99. Note: the bare form (default base=HEAD on a clean tree) now reports 0 warnings — the D36 warning surfaces only with an explicit diff base; the gate passes in every form |
| `helm lint` / `helm template` | n/a — zero chart files in the diff |

### Goal vs shipped reality (item a)

- **Label-derived sets** — `derivePipelineSet` (index.ts:184) implements D17
  exactly (case-sensitive `Pipeline:` prefix, trimmed remainder, empty
  dropped, dedupe, `["default"]` fallback); single-source `LABEL_PREFIX` /
  `DEFAULT_PIPELINE` constants, suite-pinned. ✔
- **All-or-nothing claim** — `acquireSetWithRollback` (sorted-order O_EXCL +
  full rollback, index.ts:424), shared claim identity in every file,
  set-wide lock-lost reaction with the MAJOR-1-closed ownership guard
  (index.ts:637). Core-suite race legs cover it. ✔
- **2 h window** — `DEFAULT_STALE_MS = 7200000` single source (index.ts:98),
  `max(heartbeatAt, mtime)` formula, suite-pinned incl. the wrong-type
  config leg. ✔
- **Timeout + HA alert degrade contract** — Timeout move via the D24
  sequence (index.ts:1364), HA alert title/message per D11, per-card
  grouping — **EXCEPT the degrade's card comment: see Finding F1 (major).**
- **Hourly tick disabled** — loop file `enabled: false` byte-pinned, flash
  model (Q2), alias agent (D15), D30 plain-text body, `/pipeline-tick`
  documented swap target only; tick executor reaps-before-prompt (AC2). ✔
- **Commit policy end-to-end** — pipeline implementers carry explicit
  `git add *` / `git commit *` denies (agent-dev-local/-pr sources +
  mirrors); coords keep the allows; role-dev never-commit rule + role-coord
  sole-committer rewrite landed; the branch history itself obeys it: 8
  commits = 7 chunk commits (each message carries chunk id + review verdict
  + APPROVED) + 1 routed test-round commit, all coordinator-made (dev
  commit attempts were hard-denied in-run per FRICTION). ✔
- **ralph→pipeline rename, precedent reuse, board-addition docs, commit
  ownership move** — all present; "ralph" survives only as the historical
  reference in this plan file + DECISIONS conventions. ✔
- **Out of scope held** — zero diff on `containers/`, the hourly gate
  script, the `pipeline-boards*` commands, `pipeline-models`/`pipeline-gates`
  skills, standalone `dev*`/`code`/`debug` agents, plain `agent-coord*`
  agents; `maxWorkers` reserved-not-wired (configDefaults + parsed, never
  read); no docker/helm work. ✔

### Cross-chunk consistency (item b)

- **TICK_PROMPT three-way** — byte-verified in this session: plugin constant
  (index.ts:63) == loop-file body == boards-skill section intro == tick
  suite `D30_BODY` literal. ✔
- **D29 flat names everywhere** — flat `spec.name` on all four tools
  (double-prefix rationale commented), Code-Mode call shape in every tool
  description, boards-skill Transport bullet, AGENTS.md worker line,
  permission-row actions; the live Code-Mode catalog of THIS session lists
  exactly `tools.pipeline_*`. ✔
- **D30 plain-text body everywhere** — shipped body contains no slash
  command (suite asserts `!prose.includes("/pipeline-tick")`); every
  `/pipeline-tick` mention repo-wide is doc/swap-target. ✔
- **D22 follow-up card** — card `Wg93SkHZ7bMLWJYBA` LIVE-VERIFIED in Not
  Started with the exact specified title and D22-quoting description;
  references consistent across C07.md, STATE.json, boards skill;
  `create_list`/`create_label` confirmed absent from the live dev-boards
  toolset (26 tools). ✔
- **D17/D19 label posture** — boards skill (Board facts + Parallel section +
  prerequisites bullet), AGENTS.md worker section, C07 chunk and DECISIONS
  all agree: human-created, agent-read-only, exactly-TWO custom fields,
  no `pipeline` field reintroduced (`create_custom_field` = 0 hits in every
  touched file, suite-pinned). ✔

### Leftovers / hygiene (item c)

- No probe/scratch/mock artifacts committed; `/tmp` appears only as
  evidence pointers inside plan documents (the sanctioned C01 evidence-log
  shape). No untracked files. `.pipeline/` gitignored with the D10
  why-comment; the canonical-root `.pipeline/` dir is empty (benign residue
  per C05/C06 live notes, no `reaper.lock` leak). ✔
- `maxWorkers` reserved-not-implemented as Q8 ruled. ✔
- Frozen surfaces zero-diff: commands dirs, gate script, models/gates pairs
  (kickoff-branch m6 re-verified green at plain HEAD). ✔
- Stale comments: C06's pending-repair note adjudicated historical (D33);
  NIT-1 duplicate chunk-map sentence fixed in C07; D11's "3h" is
  append-only history superseded by D21 (shipped texts all say 2h). Two
  cosmetic carry-overs: chunks/C06.md lacks its trailing newline (OBS-2)
  and the index.ts header wrap "ACTIVITY only / (D20):" reads awkwardly.
  ✔ (nits only)

### Human prerequisites (item d)

Both genuinely surfaced and live-verified: (1) `Pipeline:` labels are
human-created (zero exist on the live board → every card derives
`default`, the serialized today-behavior — nothing fails); (2) the Timeout
list arrives via follow-up card Wg93SkHZ7bMLWJYBA — until then the reaper
degrades to `timeouts.jsonl` and never hard-fails (code path verified:
`moveCardToTimeout` catch → `queueTimeoutRow`, suite R3 pins every arm). ✔

### STATE.json honesty (item e)

Statuses/verdicts/handoffs match the git log chunk-for-chunk (C04's two
review rounds incl. CHANGES_REQUESTED → MAJOR-1 fix → APPROVED are all
there; test session's five handoffs map to the test-round commits). ✔
except F2 below.

### Findings

**F1 — major: the degrade-path card comment is promised but not shipped
(fell between chunks).** Plan Out of scope: "the reaper degrades to
`.pipeline/timeouts.jsonl` + card comment"; plan Risks: "reaped cards queue
in `.pipeline/timeouts.jsonl` + card comment"; DECISIONS D22 (user's Q4
ruling): "the reaper uses the `.pipeline/timeouts.jsonl` fallback + the card
comment (C05 degrade)"; boards skill Human-stops bullet: "queues
`.pipeline/timeouts.jsonl` plus a card comment: that degrade is the shipped
interim". Shipped reality: `moveCardToTimeout`'s catch path runs
`queueTimeoutRow` ONLY (jsonl row + `board_move_err` audit) — no
`add_comment` is attempted on any degrade arm, including the
Timeout-list-absent arm where the board leg is fully up (get_card +
list_lists succeeded). The `queueTimeoutRow` header comment even claims
"The D22 interim contract in code". C05's Tasks/AC4 and the reap suite R3
defined the degrade without the comment, dev implemented that, and every
review approved against AC4 — nobody cross-checked the ruling/plan/skill
prose against the chunk contract, so the gap is unadjudicated. Impact:
until the D22 follow-up lands (it sits in Not Started, so this arm is the
LIVE path, not a corner case), a reaped card stays in Executing with no
on-card marker of what happened — HA push + jsonl row still fire, so this
is a visibility gap, not a correctness/safety one; nothing hard-fails.
Fix options (coord/owner picks): (a) implement the comment — C05 seam,
best-effort `add_comment` in the degrade arm whenever cardId + board client
are reachable (isolate it so a failed comment still falls to
`queueTimeoutRow`; R3 stays green as pinned), routed to a C05-era dev
session via coord; or (b) owner ruling to correct the four prose sites to
the shipped degrade (jsonl + audit + HA alert; card stays put). Recommended:
(a) — it is the faithful reading of D22 and keeps the boards skill's
"shipped interim" sentence true.

**F2 — minor: STATE.json bookkeeping staleness.** `current_wave: 4` and
`updated_at: 2026-10-29T02:45:00Z` while all seven chunks are done through
wave 6 with handoffs to 10:40. Exactly the C06-review NIT-2 routed to coord
and never applied. Resume readers would misread the wave. Coord-owned fix,
two fields.

**F3 — minor (shape note, no action required): the test-round-2 commit**
`346573276` is a tests-only coord commit between C05 and C06 without a
review verdict in the message (every other commit carries one). It honors
"coord sole committer" and its pins were battiered in the C06 review; it
deviates benignly from the "one commit per chunk (code + tests + state)"
wording. Recorded for history.

**Nits:** chunks/C06.md trailing-newline absence (OBS-2 carry-over);
index.ts header comment wrap (cosmetic); DECISIONS D11 "3h" is append-only
history superseded by D21 (shipped texts correct).

### Deferred (not defects of this branch)

- **Board drift observed during this review:** the live In Process swimlane
  now has SEVEN lists — a human-created `Test` list appeared after the C07
  review's live read; `Timeout` is still absent. The boards skill's "six
  today" inventory line is stale against the live board. Zero functional
  impact (the pickup walk visits only Rework/Not Started/Low Priority; the
  Timeout resolution is title + swimlane-echo exact, and the board-context
  re-resolve protocol covers id drift). Human-owned board hygiene; the next
  boards-surface ticket should refresh the inventory line.

### Verdict

**CHANGES_REQUESTED** — the battery is fully green and every other Goal
claim, cross-chunk contract and hygiene check holds; the single major (F1)
blocks marking the plan complete: the shipped degrade does not post the
card comment the plan, the D22 ruling and the boards skill promise, and the
operative skill text currently describes behavior the code lacks. Route F1
per the finding (coord → C05-era seam fix, or owner ruling to amend the
prose); F2 is a two-field coord bookkeeping fix. F3/nits/deferred do not
block.