# PLAN: agent-coord marks its OpenChamber session In-work at initialization (WeKan card #52) — REWORKED after batched round
feature: 2026/2026-10-cf-52-feat-coord-session-inwork

## Round-2 pivot (user answers, verbatim)
The first draft read "mark the session as in work" as a title convention — REPLACED by the user's batched answers: (1) "openchamber has an idea of marking a session 'in-work' and done. It only impacts where it sits in the lists"; (2) "Move to done when the user indicates it's complete"; (3) "You have to use what openchamber accepts. It's not our choice."; (4) "We should not be hanging anything off in-work. It's a purely UI feature"; (5) fuser NOT touched, exact title-match stays; (6) slug stands; (7) AGENTS.md unchanged. Title-convention elements (D1–D5 round 1) are withdrawn — see DECISIONS D8+.

## Goal
Coordinators (`agent-coord` AND `agent-board-coord`) mark their own OpenChamber session **In work** as part of initialization, using OpenChamber's native state, and mark it **done** only when the user explicitly indicates the ticket is complete. Today the state auto-opens on a sent user message, but scheduled task runs (`metadata.openchamber.kind: "scheduled"`) are deliberately EXCLUDED from auto-open (session-work DOCUMENTATION invariants) — so hourly board-coord sessions never enter the In-work block. Evidence this gap is real: this run's own coord session record carries `metadata = {"openchamber":{"kind":"scheduled"}}` and no `work` record (live GET, 2026-10-26).

## Mechanism — VERIFIED (discovered, not invented)
Source of truth: `@openchamber/web` v-installed on this host at `/home/coder/.nvm/versions/node/v26.5.0/lib/node_modules/@openchamber/web`.
- **State**: `session.metadata.openchamber.work`, zod schema (`server/lib/session-work/state.js`): `state: "open"|"done"` (required); `openedAt` ms-number, `openedBy: "auto"|"jev"|"user"`, `doneAt` ms-number, `suggestDoneAt` ms-number — all optional. `jev` is legacy; `user` = the human's Track click; `auto` = system-open. `suggestDoneAt`/`reviewOffer` are Jev-owned — never written by us.
- **Storage/writes**: state lives in the OpenCode session record, set via `PATCH /api/session/{sessionID}` (`operationId session.update`, accepts `title`/`metadata`; server ≥ 2.0.15 — this host runs **v2.0.32**, live). `metadata` is **replaced whole** — proven by a controlled probe (2026-10-26, on this planner's own non-top-level sub-session): a PATCH carrying only `{openchamber:{work:...}}` dropped the sibling `kind` key; a full-object rewrite restored and round-tripped cleanly (rc=0, 204). OpenChamber's own store documents the same ("OpenCode replaces the whole object on PATCH… the store reads the record, merges, and writes the result back"). ⇒ the agent-side recipe is **read-merge-write**: GET the session, keep ALL current metadata, add/replace only `openchamber.work`, PATCH the full object back.
- **Carriers**: `opencode api get/patch` CLI — carries server discovery+auth (cf-50 D1 verified class); works from any cwd against the one background server (probe). OpenChamber needs NO extra auth leg for us.
- **Eligibility side-effect**: kind-exclusion gates BOTH auto-open and Jev turn-end asks — preserving `openchamber.kind` in the merge keeps scheduled coord sessions out of Jev evaluation. Purely UI, as the user ruled (residual: observation at landing).

## The init/done contract (what the skills will state)
- **In-work mark at initialization** (both variants): after kickoff's `session_rename` yields the sessionID, read-merge-write `openchamber.work = {state:"open", openedAt:<epoch-ms>, openedBy:"auto"}`; idempotent — skip the write when the read shows `state=="open"` already (mirrors OpenChamber's `openPatch` null rule; manual runs auto-opened by their first message are then no-ops). Never disturb sibling metadata. Single authority: `pipeline-kickoff`; `pipeline-role-coord` step 0 wires it (re-established on resume, when the resume's rename re-captures the sessionID); `boards` adds the one-line step to card-driven kickoff citing the authority.
- **Done mark**: ONLY when the user explicitly indicates the ticket is complete (never automatically at final-review approval or at the step-9 report; on board runs this mirrors the human Review→Finished call but is driven by the user's in-session indication, not by reading the board). Write `{state:"done", openedAt/openedBy kept, doneAt:<epoch-ms>}` via the same read-merge-write. A run that stops blocked leaves the session open.

## Out of scope
- cf-50 gate script + `/pipeline-boards-hourly`/`/pipeline-boards` commands: byte-frozen — nothing hangs off the marker (user answer 4).
- `pipeline-role-fuser`: byte-frozen — titles stay bare slugs so exact title-match survives (user answer 5).
- `agents-sync` references, `pipeline-models`, `pipeline-gates`, AGENTS.md (answer 7), `.agents/plans/templates/`, STATE.json schema.
- No title decoration, no `sessions-archive.json` (archive ≠ done), no `suggestDoneAt`/`reviewOffer` writes, no board→work bridge.

## Commands
- `bash tests/coord-inwork/surface.sh` — new (agent-test): i1..i6 (see C01 Tests). Offline-deterministic; red before C01 (i1–i4, i6), i5 freeze-guard green throughout.
- `bash tests/agent-board-coord/rulesync-surface.sh` — c10–c16 HOLD (boards text edit keeps every pinned substring; `session_rename` still present); **c17 RE-PINNED** (pipeline-kickoff + pipeline-role-coord leave the byte-unchanged set — this ticket legitimately re-opens them, cf-50 D21 posture; pipeline-models + pipeline-gates stay byte-pinned); **c8 allow-set widened** (8 touched surfaces + tests/coord-inwork/* + this plan folder).
- `bash tests/agent-board-coord/gate.sh` — t11/t13 HOLD (commands untouched); t12 HOLD (agents-sync untouched); **t14 allow-set widened**; **t17 RE-PINNED**: agent-board-coord frontmatter is no longer byte-identical — its diff vs base is exactly the two new scoped shell allows; `dev_boards*` line and everything else hold; agent-coord.md gains the same two-line pin.
- `bash tests/agent-board-coord/agents-md.sh` — content pins HOLD (AGENTS.md byte-stands); **c7 allow-set widened**.
- `rulesync generate` ×2 (PATH/npx ladder, skip-with-warning precedent) — 2nd run no-op; `rulesync generate --check` clean; sources + generated (`.opencode/agents/agent-coord.md`, `.opencode/agents/agent-board-coord.md`, `.opencode/skills/{pipeline-kickoff,pipeline-role-coord,boards}/SKILL.md`) committed together. Never hand-edit `.opencode/`.
- `npx --no-install aislop ci --changes` — 0 errors on touched files.
- Review step: run the agents-sync permission audit (`references/permissions.md`) — this ticket adds the only shell grants to the coord pair; last-match ordering and deny-baseline must be re-verified by the reviewer, not assumed.
- Live controls (manual, Review-notes recorded, never CI): after landing, first scheduled board run — its coord session GET shows `openchamber.work {state:"open", openedBy:"auto"}` while `openchamber.kind:"scheduled"` SURVIVES, and the OpenChamber sidebar In-work block lists it; a manual `/pipeline` run reads already-open and writes nothing (no churn).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Native In-work/done contract: two scoped shell grants on the coord pair + kickoff authority + role-coord wiring + boards one-liner + regenerate + re-pins | M | 1 | [] | — |

## Wave order
1. C01

## Risks / assumptions
- **Grant blast radius**: `opencode api patch /api/session/*` pattern (fuser-precedent shape) allows patching any session's metadata; containment is contract-text (own coord session only, `openchamber.work` key only) + the reviewer's audit. Residual accepted; same class agent-fuser already carries.
- **Race**: no per-session write queue on our side — a user Track/Done between our read and write loses to last-writer-wins. Narrow window (init turn is quiet); OpenChamber's store has the same class internally; documented.
- **openedAt via `$(date +%s%3N)` inside the matched command string**: the shell resource glob matches the whole command; the skill recipe must show a single self-contained command line (dev wording task; t17/i4 pin the grant lines, not the data payload).
- **Jev silence on agent-opened scheduled sessions** rests on the kind-preserving merge (eligibility gates the ask path). If the installed build behaves otherwise, the marker is still purely UI per the user's ruling — landing observation records it; no code path hangs off it.
- **Frontend done-patch shape** (`setSessionWorkState` in `packages/ui`) is not in the server package on this host; `state:"done" + doneAt` rest on the server DOCUMENTATION's field list + the zod schema (accepts it, proven shape-legal). Low risk; free-form `Session.Metadata` schema (`{"type":"object"}`) never rejects.

## Open questions (batched round 2 — ALL RESOLVED by the user 2026-10-26)
RESOLVED: Q1/Q2/Q3 all confirmed on the plan's best guesses (`auto`; in-session user message only; unconditional in both variants) and Q4 the user APPROVED the plan — `plan_status: approved`. The resolutions below are recorded for the implementers; the contract text already reflects them.
- Q1 `openedBy` for the agent's init write: enum is `auto|jev|user`. BEST GUESS: `"auto"` — it is an automated part of initialization (jev is legacy, `"user"` would misattribute a human click). Impact: one value in the contract; trivially re-pinnable if the user prefers `user`. RESOLVED: `auto`.
- Q2 What counts as "the user indicates it's complete" on a scheduled board run (no live chat mid-run)? BEST GUESS: only an explicit in-session user message closing the ticket (e.g. a reply to the completion report); the card's Review→Finished move alone never triggers the write (no board polling, nothing hangs off it). If no such message arrives, the session simply stays open — acceptable per "purely UI".
- Q3 Uniform instruction on manual runs (where the first message already auto-opened the session, making the init write an idempotent no-op): BEST GUESS: keep the mark step in both variants unconditionally — cheap, covers loop/API-launched plain runs, and the already-open check prevents churn.

## Landing note (user-owned)
1. PR merges `cf-52-feat-coord-session-inwork` → `main` (agent never merges/pushes).
2. First hourly `/pipeline-boards-hourly` run after merge: confirm its coord session appears in the OpenChamber sidebar In-work block and its GET keeps `openchamber.kind`.
3. Tell the coord session "done" (or move the card Finished + say so) when a ticket wraps, if you want the In-work block closed by the agent rather than by your own click.
