# PLAN: agent-* context → standalone agents, coord/dev -pr/-local variants, Lifecycle checklist, local model defaults
feature: 2026/2026-10-cf-58-feat-standalone-agent-merge
card: WeKan AI-Dev #58 (`En98XdBL255NgRpAx`) — "Merge agents-* useful pieces into stand alone planner, dev, and investigate"
status: reworked 2026-10-26 after the batched question round (9/9 answered) — awaiting plan approval

## Goal
Fold the `agent-*` pipeline's maturity (contracts, quality gates, git/permission posture) back into the standalone agents — a NEW standalone `dev` family (`dev`/`dev-local`/`dev-pr`) for one-session-sized changes (still able to run pipeline work), `planner` upgraded, `debug` FULLY rewritten with the agent-* guidance, and `code` explicitly WITHOUT pipeline context — and give `agent-coord`/`agent-board-coord`/`agent-dev` `-pr` (pushes work to be built/tested remotely, per the repo's explicit-request rule) and `-local` (commits only, never pushes) variants, with the unsuffixed coord agents KEPT as aliases of their `-local` variants. Same change: replace the WeKan "Research" card checklist with a "Lifecycle" checklist (Pre Research / Plan / Post Research / Test / Code / Review / Deploy / Single Session) whose checked items are the only stages coord runs, and re-cut the local model defaults (27b+Local → q4; Flash+Local ⇒ Qwen Flash Next q3).

## Out of scope
- Mutating the live WeKan board (renaming the checklist on the board, its items, the multi-action createCard rule): human/runbook-owned. C05 documents the board-maintenance steps and builds the agent-side transition so both checklist shapes work until the board flips.
- `ask`, standalone `review`, `agent-fuser`, the `0-pipeline` SDLC stages: untouched. `debug` keeps its name (Q8 resolved) — but its role skill gets a full rewrite, not a patch.
- Openrouter `Qwen Large` local-q6 mapping verification (pre-existing assumption; only 27b + flash routing change now).
- Landing this ticket: no merge to main, no push — PR stop point per HITL=PR; landing is user-owned.
- Chart/container/service work — this ticket touches agent machinery only (`.rulesync/**`, generated surfaces, `scripts/`, `tests/`, `.opencode/opencode.jsonc`).

## Commands
- generate: `rulesync generate` — run TWICE per chunk; the second run must be a no-op (idempotence)
- check: `rulesync generate --check` (generated surfaces current)
- surface suites (every chunk — they pin the contracts this ticket rewrites): `bash tests/agent-board-coord/rulesync-surface.sh`, `bash tests/agent-board-coord/gate.sh`, `bash tests/agent-board-coord/agents-md.sh`, `bash tests/coord-inwork/surface.sh`, `bash tests/agent-perms/surface.sh` (+ the new `tests/standalone-agents/surface.sh` from C04 onward)
- quality gate: `npx --no-install aislop ci --changes`
- alias integrity: for each kept alias pair, parsed permission lists of `<name>.md` and `<name>-local.md` identical (dict+order compare) — pinned by the surface suites
- git: `git status` clean after each chunk commit; sources + generated mirrors + re-pinned tests commit together

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | `pipeline-push-pr` skill — how work gets pushed to be built/tested remotely | S | 1 | [] | |
| C04 | Standalone agents: new `dev` family (`dev`/`dev-local`/`dev-pr` + `role-dev`) and planner/debug(full rewrite)/code fold-in | L | 1 | [] | independent of C01 (disjoint files) |
| C02 | `agent-dev` → `agent-dev-pr` / `agent-dev-local` | M | 2 | [C01] | `-pr` MUST-loads the C01 skill; its name must exist first |
| C03 | Coord family: `-pr`/`-local` variants + unsuffixed aliases, new `-pr` commands, gate script | L | 3 | [C02] | coord rosters grant `subagent` on the new dev variant ids |
| C05 | "Research" checklist → "Lifecycle" (boards skill + coord contracts + transition) | M | 4 | [C03] | edits the board-coord variant bodies C03 creates |
| C06 | `pipeline-models` local defaults (27b+Local→q4; Flash+Local⇒flash-next q3) + provider catalog | M | 5 | [C05] | both edit boards `SKILL.md` — serialized to avoid rework |

## Wave order
1. C01, C04 (independent; run in id order)
2. C02
3. C03
4. C05
5. C06

Coord runs one chunk at a time (waves only encode ordering here; every later chunk touches files an earlier one created).

## Risks / assumptions
- The surface suites pin contract text and file paths byte-wise (`agent-dev.md` paths, the Research-checklist passage, the gate's agent filter). They go RED by design when the contracts change; `agent-test` re-pins them per chunk (test session owns test edits, never dev/review).
- **Alias drift is the new silent-failure mode**: `agent-coord`/`agent-board-coord`/`dev` stay as byte-identical copies of their `-local` twins (save name + description tag). Any later edit to a `-local` agent that skips its alias silently diverges them — every chunk that touches a `-local` agent touches the alias in the same commit, and the surface suites pin parsed-equality of each pair.
- `scripts/agent-board-coord-gate.sh` filters `.agent == "agent-board-coord"`: C03 widens it to all THREE board-coord names (alias + both variants); missing one silently blinds the hourly gate (double-launch risk) — acceptance criterion, not a footnote.
- Provider catalog (C06): `qwen3.8-27b-q4` exists but WITHOUT `capabilities.tools: true`; `qwen3.8-flash-next-q3/q4` are served by llama-swap (chart + gpu-ai values verified) but absent from the catalog. User accepted adding all three now WITH tools despite unverified flash-next tool-calling (Q7) — if flash-next tool calls fail live, the fix is a catalog flag flip, recorded in this ticket's final report.
- This run's coord session has read/write/shell denied (scheduled-launch friction, FRICTION.md item a): commits land via the dev subagents' own permissions; an `ask`-blocked commit in an unattended session escalates to the user.
- Every chunk keeps sources + generated + tests consistent, so any chunk can merge alone; `rulesync.jsonc` has `delete: true`, so retiring a source file removes its mirror on generate.

## Resolved open questions (batched round, 2026-10-26 — all 9 answered)
1. **Slug** — KEEP `cf-58-feat-standalone-agent-merge`. No change.
2. **Dev variant target** — BOTH families split: `agent-dev` → `agent-dev-pr`/`agent-dev-local` (C02) AND the standalone `dev` ships as variants (C04). Rosters wire coord variants to their matching agent-dev variant.
3. **Unsuffixed coord agents** — KEPT as aliases of their `-local` variants (= today's commit-only behavior). The four existing commands keep their plain targets untouched; NEW `/pipeline-pr`, `/pipeline-resume-pr`, `/pipeline-boards-pr` target the `-pr` variants.
4. **"Single Session"** — confirmed best guess: Plan still runs if checked, then ONE session of the coord's dev variant implements the whole approved plan (no chunk fan-out, no separate test session; dev runs the plan's Commands), then ONE final `agent-review`.
5. **Lifecycle nothing checked** — confirmed: full standard loop (Plan + Test + Code + Review; Pre/Post Research and Deploy off) = today's behavior; Research-labelled cards keep their own loop.
6. **Qwen Flash Next** — user override: NO fifth option. Rule: **if `Qwen Flash` and `Local` (gpu-ai) are selected together, route to `gpu-ai/qwen3.8-flash-next-q3`** ("assume it's Qwen Flash Next"). Exact expression (C06 pins this wording): `Qwen Flash` alone → `openrouter/qwen/qwen3.8-flash` (unchanged); `Flash + Local` → flash-next q3 — there is no "plain flash on gpu-ai" route (never served; the old `qwen3.8-flash-q6` mapping is dropped, not kept as fallback); other flash-next quants (q4/q5/q6/orca) only via explicit request in the card text or at approval — the same "unless something else is requested" escape as 27b.
7. **Provider catalog** — add NOW: tools:true on `qwen3.8-27b-q4`; new `qwen3.8-flash-next-q3` + `-q4` entries with tools + 262k ctx; unverified flash-next tool-calling accepted (risk above).
8. **"investigate"** — `debug` keeps its name; C04 does a FULL rewrite of `role-debug` folded with the agent-* guidance, not a minimal patch.
9. **Deploy** — confirmed best guess: `-pr` pushes the ticket branch + opens the PR under the explicit-user-request rule; `-local` reports "ready — commits local"; merge to main + ArgoCD sync stay human-owned.

## Final whole-plan review — 2026-10-27, fresh agent-review session — VERDICT: APPROVED

Scope: `git diff e25919a2a..HEAD` (HEAD d3c92ff2f; 19 commits; merge-base =
e25919a2a, the base the user-ruled rebase landed on; main has since advanced to
e27b83825 with the cf-52 stack — see landing note below). No chunk-level
findings: every chunk's acceptance criteria re-verified against the diff and
all five card asks are visibly shipped.

**Validation (run fresh this session, full ids, not subsets):**
- tests/pipeline-push-pr/surface.sh => 6 ok PASS
- tests/standalone-agents/surface.sh => 10 ok PASS
- tests/pipeline-models/surface.sh => 6 ok PASS
- tests/agent-perms/surface.sh => 13 ok PASS
- tests/coord-inwork/surface.sh => 7 ok PASS (the two "missing needle: pre
  research" lines are i7's NEGATIVE window arm working — proves role-coord
  cites the stage map without restating it)
- tests/agent-board-coord/gate.sh => 22 ok PASS (t1 shellcheck
  skip-with-warning per its AC5 convention)
- tests/agent-board-coord/rulesync-surface.sh => 19 ok PASS (c11/c18 fully
  flipped — C05+C06 windows green)
- tests/agent-board-coord/agents-md.sh => 9 ok PASS
- rulesync generate x2 => both no-ops; --check clean; tree stays clean
- npx --no-install aislop ci --changes => 0 errors / 0 warnings, 37 files

**Cross-chunk coherence (the between-chunks sweep):** boards Stage map ↔
pipeline-role-coord loop (5a/5c/8 dev variants, citation-only stage-gate
bullet) ↔ kickoff derivation ↔ pipeline-models routing ↔ boards routing
paragraph — one consistent contract (checked-stages-only; nothing checked =
Plan+Test+Code+Review; Deploy = -pr push per pipeline-push-pr / -local
report-and-stop; Single Session = one dev-variant session + one final review).
All three alias pairs (agent-coord, agent-board-coord, dev) byte-identical to
their -local twins save name+description tag, in source AND mirrors; rosters
wire -local→agent-dev-local / -pr→agent-dev-pr in all six coord sources; the
four plain commands still target the aliases, the three new -pr commands the
-pr variants, hourly never -pr; gate enumerates exactly the three board-coord
names; AGENTS.md matches the generated surfaces (all era-correct); the
permissions.md matrix rows match the live frontmatter blocks. No bare
`agent-dev` survives in any binding surface; Research-checklist semantics
survive ONLY in the transition rule + the untouched LABEL trigger.

**Hard rules across the whole history:** `git ls-remote origin
'refs/heads/cf-58*'` empty (never pushed); branch contains no commit outside
the 19, zero merge commits, sole committer, reflog clean of force/reset; main
never advanced by this branch; no secrets in the diff (pattern scan =
false-positive prose only); zero files under `charts/` touched, no version
bumps.

**Minor (record hygiene, non-blocking):**
- m1: FRICTION.md item 3 (provider catalog drift) still `open` although C06
  shipped the patch — re-status to `fixed` at plan-complete (the Q7
  unverified-tool-calling question is a separate open item).
- m2: plan file line 4 still reads "awaiting plan approval" while
  STATE.json/DECISIONS record the 2026-10-27 approval — cosmetic status line.
- m3: STATE.json shows C06 `review_rounds: 0` — C06 never had a dedicated
  chunk review; this final review covered its ACs directly (M1–M6 + catalog
  diff + serving-fact greps). The launch brief's "all six chunks
  review-approved" slightly overstated; the substance is now reviewed.

**Deferred ledger for the final report (out of verdict):** five user-approved
test re-pins, all escalation-clean and test-files-only (P4 → 4e12c97f; A11/A13
→ 833da163; classifier+t14 → 6fe3fc8e; window.py/_DEV → e7bcf999; pattern:
latent helper defects surfaced only when later content satisfied earlier arms
— probe-runs with real content belong in test authoring). Unowned hygiene
candidates: pipeline-role-test:12 stale `agent-dev` prose;
tests/services/dev-mcp-fleet.sh AGENT_SOURCES:51 retired path (other ticket's
suite); NEW finding this review — agents-sync references prose naming the
retired id (plan-and-result.md:75 chunk loop, pipeline-overview.md:46 api
example, syncing-to-other-repos.md:59 spot-check example; SKILL.md:30 /
pipeline-overview.md:6 / permissions.md:7 are historical naming-scheme
illustrations, permissions.md:87 deliberately historical) — never in any
chunk's Files-in-scope and A13's sweep judgment deliberately exempted skill
prose; group into one hygiene card. C04-recorded: role-code/role-dev MCP
paragraph `<cluster>-<priv>-<service>` word-order drift (globs correct);
pipeline-push-pr "only on merge to main" optional wording drop;
pipeline-push-pr/surface.sh:8 intro sentence. User decisions: rebase-pickup
has NO `git rebase` grant for any pipeline role (verified: 0 grant lines —
fails closed, pickup stays human-run); flash-next catalog entries declare
`input: ["text"]` while the llama-swap chart family declares image input too
(plan-pinned q8 shape; hygiene call); Q7 flash-next tool-calling unverified
(accepted risk; failure mode = catalog flag flip). Machine-local global
config flash-next entries + Openrouter Large/Flash q6 assumptions:
DECISIONS-deferred. User-owned chores: delete the uncommitted main-checkout
draft folder; the copy of this folder on main (draft, from the landed docs
commit at e25919a2a) is coherently superseded by this branch's records —
append-only respected, no content lost, plan file + C06.md byte-identical,
landing overwrites it cleanly. Landing note: main has moved (cf-52 stack);
a read-only `git merge-tree` probe shows the next pickup rebase will conflict
in 11 shared files (coord/board-coord alias pairs, permissions.md,
pipeline-role-coord, gate.sh, rulesync-surface.sh, coord-inwork/surface.sh) —
expected pickup work under the rebase rule, not a defect of this branch.
Harness friction (roster freeze, coord shell denial, session losses, STATE
rebuild): follow-up-card candidates per FRICTION.md.

### Residual notes (non-blocking, derived — veto at approval if wrong)
- R1: the standalone `dev` also ships a plain alias (`dev` = alias of `dev-local`), derived from the Q3 rationale (plain name = safe commit-only default; ergonomics for direct user launches). Unlike the coord aliases this preserves nothing existing (dev is new) — it is pure ergonomics; dropping it is a two-file delete.
- R2: the hourly scheduled launch stays on the plain `agent-board-coord` (the alias) — scheduled runs are `-local` semantics by construction; `agent-board-coord-local` exists for explicit local-variant launches and parity with the coord family.
- R3: with no Flash Next picker option, there is no checklist way to request a non-q3 flash-next quant; the escape hatch is free text (card description/comment or approval round), documented in pipeline-models.