# PLAN: boards skill — the board-structure description matches the live AI-Dev board
feature: 2026/2026-10-docs-boards-skill-list-drift

## Goal
Rewrite the `boards` skill's lists bullet so it describes the AI-Dev board as it
actually is: six **pipeline** lists inside the **In Process** swimlane, that
swimlane also carrying non-pipeline lists humans use for their own work, and the
board holding other swimlanes with their own lists — plus the rule that this set
is human-owned and drifts, so ids come from live resolution, never from this
enumeration.

Pure documentation + generated-mirror change, with the mechanical guard-suite
re-pin that admits this ticket's plan folder. The pickup walk
(Rework → Not Started → Low Priority) is a semantic contract and does NOT move.

## Source friction (why this ticket exists)
`.agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/FRICTION.md`, checked by the
user at cf-75's friction follow-up round 2026-10-28, status `open`:

> 2026-10-27 · plan(plan) · The `boards` skill text says the AI-Dev board has six
> lists, but the live In Process swimlane carries an extra non-pipeline "Test"
> list (plus other swimlanes' lists) — skill-vs-reality drift agents hit when
> reasoning about board structure. · resolution: captured as a plan risk; board
> structure is human-owned, pickup walk unchanged (only Rework/Not Started/Low
> Priority are consulted); a boards-skill text fix may ride C03. · open

It did not ride C03 (2bc2946d4 added the Board-context consumer section to the
same file and left the lists line untouched), so it becomes its own ticket here.

## Out of scope
- **Any board mutation.** No `move_card`, `add_list`, rename, archive or delete —
  board structure is human-owned (cf-75 DECISIONS); the agent fixes TEXT, never
  the board. At most read-only `dev-boards` calls.
- The pickup walk, the Stage map, the five checklists, the Lifecycle rules, the
  Config constants, the Card lifecycle, the write-back steps — untouched.
- `skills/wekan-mcp/SKILL.md` (already carries the drift fact and owns the Board
  context schema — one owner per fact, no second copy) and `skills/wekan-api/*`.
- The board-context collector command, `agent-board`, the prefetch plugin.
- Other tickets' deferred business, except the one admit-list line A9 needs to
  stay in lockstep (see C01).

## Verified facts (evidence, this planning pass 2026-10-28)
- **Live dev-boards probe (reads only, this planning session):** board AI-Dev
  `TNQJ2BrXenZovngTS`; swimlanes In Process `jLzy39L7djCRr67SF`, Up Next
  `MoZHQz3C4dSW4Atya`, Farm `BkNBQgMLJBvmCgMAQ`; **21 lists board-wide**. In
  Process holds **seven** lists — the six pipeline lists (Not Started
  `XhDyShvuwhGWzWH2z`, Executing `qZ9CLZqCRbv7NQQ6R`, Review `2B6wWGJ8Tetp5QWDJ`,
  Rework `y9tsvb3AguKWhzCoF`, Finished `DHw56fMKy3qyfudz4`, Low Priority
  `M4JS9LfaypJbB97At`) **plus non-pipeline "Test"** `jNYNdCPPkX8Bs95s4`. Up Next:
  Context, Features, Research, Outside Process, Dev Env, Home Assistant, CICD,
  Wekan. Farm: Context, Home Assistant, Dev Env, "Outside Proccess" (sic),
  Research, Features.
- **Source-only (greps, 2026-10-28):** the frozen-count claim is ONE sentence
  repo-wide outside `.agents/plans/` — `.rulesync/skills/boards/SKILL.md:14`
  (`- Lists (six): …`), mirrored at `.opencode/skills/boards/SKILL.md:23`. No
  other doc repeats it.
- **No guard pins the count.** `grep -rn "Lists (six)" tests/` => zero hits, and no
  list-count needle anywhere in `tests/**`, so the prose fix needs no wording
  re-pin — only the surrounding pins must keep holding: rulesync-surface **c4**
  (the six names, incl. the bold literal `**Review**`, plus
  `AI-Dev`/`In Process`/`dev-boards`/`wekan-api` and five section titles),
  **c10** (`Low Priority` + the pickup order inside the `Card pickup` section),
  **c9** (the `MUST-loaded by agent-board-coord` literal, which lives in the
  frontmatter `description`), **c12** (`neg12.py` D12 check, run on the generated
  mirror), board-context **t3** (`board_context` spelled EXACTLY once per boards
  file), gate **t19**, coord-inwork **i3** (carry-strings) + **i6**
  (source↔mirror pair-sync), kickoff-branch **m2/m3** (carry-strings + "cites,
  never restates the mint command"), pipeline-models **m5** (the Model(s) option
  line byte-stable), session-origin **s1/s2/s3** (s2 byte-compares three passages
  vs base — all outside `## Board facts`) + **s6** (pair-sync).
- **Frozen pairs this ticket must not touch:** kickoff-branch **m6** no-touch set =
  AGENTS.md, `.rulesync/rules`, both commands dirs, the gate script,
  pipeline-models/pipeline-gates pairs (boards is NOT in it); rulesync-surface
  **c17** is a documented no-op since cf-75 C02.
- **Baseline suite run, 2026-10-28, `BASE=HEAD`, folder NOT yet present:**
  rulesync-surface (19 ok), agents-md (9), gate (22), agent-perms (14),
  coord-inwork (7), kickoff-branch (6), session-origin (7),
  wekan-mcp/board-context (6), wekan-mcp/skill-surface (8), wekan-mcp/tools (9),
  standalone-agents, `node --test tests/opencode/board-context.test.ts`,
  `tests/pipeline-gates/validation-fix.sh` — all rc=0.
  `tests/pipeline-models/surface.sh` is RED at **M3** ("red before C06": the
  flash-next catalog work, not boards); `bash tests/pipeline-models/surface.sh m5`
  (its boards check) => PASS.
- **Full-range base:** `git merge-base main HEAD` =
  `ca0a40669f97605c92cdd593f9907dbc32f9d354` (same base cf-75 gated on).
- **Folder-admit reddening (this planning session, measured with this ticket's
  folder on the branch):** the scope blocks collect untracked paths too
  (`git ls-files --others`), so the red is NOT base-dependent — it appears at the
  DEFAULT `BASE=HEAD` as well as at the merge base. Three entry points fail
  directly (rulesync-surface c8, agents-md c7, gate t14) and two more fail by
  PROPAGATION because they child-run the first three with `env -u CHUNK_BASE`
  (wekan-mcp/board-context t6 → gate.sh; pipeline-gates/validation-fix t7 →
  rulesync-surface.sh). Full table + the exact red reasons are in `chunks/C01.md`
  "Red-before evidence". `agent-perms a9` stays green throughout — which is the
  point of widening it in the same pass.

## Commands
- regen (any `.rulesync/` touch): `npx --no-install rulesync generate` run twice —
  the second must be a no-op — then `npx --no-install rulesync generate --check`
  => pass (both binaries resolve here: rulesync 37.0.0, aislop 0.18.1, verified
  2026-10-28 via `npx --no-install <tool> --version`)
- new chunk suite (agent-test writes; dev/review run):
  `bash tests/agent-board-coord/boards-lists.sh`
- existing suites that read the boards skill or child-run the three scope blocks
  (must stay green; note that `validation-fix t7` re-runs rulesync-surface and
  `board-context t6` re-runs gate.sh, so a scope red in the trio surfaces in five
  entry points):
  `bash tests/agent-board-coord/rulesync-surface.sh` ·
  `bash tests/agent-board-coord/agents-md.sh` ·
  `bash tests/agent-board-coord/gate.sh` ·
  `bash tests/agent-perms/surface.sh` ·
  `bash tests/coord-inwork/surface.sh` ·
  `bash tests/kickoff-branch/surface.sh` ·
  `bash tests/session-origin/surface.sh` ·
  `bash tests/wekan-mcp/board-context.sh` ·
  `bash tests/wekan-mcp/skill-surface.sh` ·
  `bash tests/wekan-mcp/tools.sh` ·
  `bash tests/pipeline-gates/validation-fix.sh` ·
  `bash tests/standalone-agents/surface.sh`
- pipeline-models scoped (M3 is a pre-existing, unrelated red — never "fix" it
  here): `bash tests/pipeline-models/surface.sh m5`
- boards-pin spot checks (the exact guards this bullet must not break; all pass at
  HEAD on 2026-10-28), one command per line:
  `bash tests/agent-board-coord/rulesync-surface.sh c4 c9 c10 c12` ·
  `bash tests/wekan-mcp/board-context.sh t3` ·
  `bash tests/coord-inwork/surface.sh i6` ·
  `bash tests/session-origin/surface.sh s6` ·
  `bash tests/kickoff-branch/surface.sh m2 m3` ·
  `bash tests/agent-board-coord/gate.sh t19`
- full-range guard shape (the scope re-pin's own proof):
  `CHUNK_BASE=$(git merge-base main HEAD) bash tests/agent-board-coord/rulesync-surface.sh c8`
  · same base for `agents-md.sh c7` · `gate.sh t14` ·
  then `bash tests/agent-perms/surface.sh a9`
- quality gate: `$aislop`, or `npx --no-install aislop ci --changes --base <chunk
  base>` => rc=0, 0 errors
- surface check: `git diff --name-only "$(git merge-base main HEAD)"..HEAD` ⊆ the
  chunk's declared files; every `.opencode/` edit lands in the SAME commit as its
  `.rulesync/` source; `git status` proves no board-side change (this ticket writes
  no cards — nothing on the board to diff, so the check is "no board write call was
  made")

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | boards skill lists description + mirror regen + scope admits | S | 1 | [] | — (single chunk; the test phase lands its admits before dev touches the skill) |

## Wave order
1. C01

## Ownership split inside C01 (pipeline convention, not extra chunks)
- `agent-coord` / `agent-board-coord`: approves (sets `plan_status`), commits this
  plan folder as bookkeeping, and appends the cf-75 FRICTION re-status at the done
  gate (OQ1) — the only role with write grants outside this ticket's own folder.
- `agent-test` (pre-dev, one session): writes `tests/agent-board-coord/boards-lists.sh`
  AND widens the folder admits — gate t14, rulesync-surface c8, agents-md c7
  case-lists + the agent-perms A9 slug loop. Widening scope allow-lists is
  agent-test's prerogative, never dev's (cf-75's scope caveat; its final review
  had to route two such reds back to the test session).
- `agent-dev-local` / `agent-dev-pr`: edits `.rulesync/skills/boards/SKILL.md`,
  runs `rulesync generate`, commits source + mirror together.
- `agent-review`: re-runs every command above as its first step.

## Risks / assumptions
- **Prose-pinning treadmill.** The new suite pins required CONTENT (facts
  present/absent), never a whole sentence's bytes — the repo's own doctrine
  (coord-inwork i5's comment: "delta-pinning prose across every future ticket is
  a treadmill"). Dev may reword freely as long as the content checks pass.
- **The board drifts again before execution.** The replacement text must NOT swap
  one frozen count for another: it names the six pipeline lists (the contract set)
  and describes everything else as human-owned and drift-prone, with live
  resolution as the rule. If dev re-probes live, it may name `Test` as the current
  example but must keep the "resolve live" clause.
- **Interim red until the admits land (measured, not theorised).** The scope blocks
  collect untracked paths too, so this ticket's folder alone reddens THREE entry
  points directly — `rulesync-surface c8`, `agents-md c7`, `gate t14` — and TWO more
  by propagation through their child-runs (`wekan-mcp/board-context t6` runs gate.sh;
  `pipeline-gates/validation-fix t7` runs rulesync-surface.sh), at the DEFAULT
  `BASE=HEAD` as well as at the merge base. Sequencing duty for coord: land the test
  phase's admit commit as early as possible (before dev), and until it exists, treat
  reds naming `2026-10-docs-boards-skill-list-drift` in those five entry points as
  this ticket's known state — never dodge them by weakening an unrelated assertion
  (cf-75's final-review doctrine: attribute propagated reds before triaging; every
  run owes one full-range guard pass before a chunk is called done).
- **No board card.** This ticket is friction-minted (like the retired
  docs-ergonomics draft), so it has no `cf-<cardNumber>-` slug and no card
  write-back; a board-driven coord run may later attach it to a card of its own
  making — not this plan's assumption.
- **Branch residency.** This plan of record lives on branch
  `cf-75-bug-wekan-mcp-skill` (unmerged), not on `main`. The run that executes it
  must work on that branch (or one cut FROM it) — a worktree cut from `main` would
  not contain this folder, and the admits it schedules are pinned to the suites as
  they stand on this branch. Nothing here advances `main`; landing the branch is the
  user's call (repo hard rule).
- Single-model S ticket: no research round anticipated; if the guard inventory
  turns out deeper than recorded here, `agent-test` reports NEEDS_INFO rather than
  silently rewriting the contract.

## Open questions (for the future coord's batched round — best guess recorded, work proceeds on it)
- OQ1: re-status cf-75's FRICTION item `open → fixed` at this ticket's done gate?
  Best guess: yes, but as **coord bookkeeping in cf-75's folder**, never a dev task
  (dev/test/review cannot write another ticket's plan folder).
- OQ2: should the boards bullet carry a dated probe stamp? Best guess: no date in
  the enumeration (dates rot and read as contract); the drift clause carries it.
- OQ3: land the docs-only change under `pipeline-push-pr` (a PR) or local commits?
  Best guess: `-local` posture — the user opens the PR (repo hard rule: main moves
  only by the user).
