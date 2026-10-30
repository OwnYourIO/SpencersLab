# PLAN: Single `slug` custom field carrying `[slug](session-link)`
feature: 2026/2026-10-cf-85-refactor-wekan-slug-session-link
card: 85 (`DNoEkqdDJ3YJjuwbg`, AI-Dev board) — kickoff + live board ids recorded in STATE.json
Round 2 (2026-10-29): batched question round completed — all four OQs ANSWERED by the user and folded in; plan is at the approval gate.

## Goal
Refactor the board-coord card write-back contract from two custom-field writes (`slug` + `session`) to ONE `slug` custom field whose value is the markdown link `[<slug>](<session link>)` — exactly the card's request. Update every contract surface that carries the two-field wording (boards skill, the three `agent-board-coord*` subagent twins, the two board commands, the repo rules → AGENTS.md), regenerate the rulesync mirrors, and re-pin the test suites that pin the old wording.

## Out of scope
- Live-board maintenance: deleting the legacy `session` custom field from the AI-Dev board, backfilling or re-pointing any existing card's fields — owner-owned (boards skill posture). This run only RAISES the removal-request card (Run close-out, below); it never deletes a field or touches an old card.
- `containers/wekan-mcp` and the `wekan-mcp`/`wekan-api` skills: tool-shape docs (`set_card_custom_field` upsert), not the roster contract — untouched.
- Claim-comment / research-comment session lines, `session_rename`, STATE.json `kickoff.session_origin` (claim-once record): unchanged — they are not custom fields.
- `pipeline-kickoff` / `pipeline-models` / `pipeline-role-coord` skills: authoritative for `agent-coord`, carry no custom-field text — untouched.
- PR/push: Human-in-the-Loop `PR` checked + `local: true` — the run ends at local commits; landing is user-owned.

## Commands
No unit-test suite in this repo — validation is these concrete checks (dev runs while implementing, review re-runs first):
- `rulesync generate` then `rulesync generate --check` => exit 0 (drift check; local rulesync 37.0.0 = the CI pin in `.github/workflows/rulesync.yaml`).
- `bash tests/agent-perms/surface.sh`
- `bash tests/agent-board-coord/gate.sh`
- `bash tests/agent-board-coord/rulesync-surface.sh`
- `bash tests/agent-board-coord/agents-md.sh`
- `bash tests/session-origin/surface.sh` (default `BASE=HEAD` is green post-commit; mid-chunk proof of the designed-red blocks: `CHUNK_BASE=<pre-chunk commit> bash tests/session-origin/surface.sh` per its header convention)
- Parity greps (exact needles per C01 Tests): the single-field write-back sentence present with identical count in each source↔generated pair; `grep -rn '`slug` + `session`' .rulesync .opencode AGENTS.md` => empty; `grep -rn '`session` custom' .rulesync .opencode AGENTS.md` => empty.
- `npx aislop ci --changes` => no error findings on touched files (AGENTS.md quality gate).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Contract flip: sources + regenerate + suite re-pins in one commit | M | 1 | [] | — |

## Wave order
1. C01 (alone — the contract flip is one indivisible commit, see DECISIONS D5).

## Run close-out (coord-owned board step — not a chunk task, not a commit)
Folded in per the user's OQ3 answer (DECISIONS D12). After the final whole-plan review passes, before or together with the final summary comment on #85 and the `move_card` to Review (Card lifecycle), the coordinator creates ONE follow-up card requesting the owner delete the legacy `session` custom field from the AI-Dev board — the Friction follow-up (board override) shape: Review is the destination, these cards await the owner's call, the pickup walk never visits Review.
- Mechanics (coord, via `dev-boards`): `create_card` into **Review** — the board's createCard rule adds the five standard checklists automatically, do NOT `add_checklist` (it duplicates them); the rule's checkItem extras are dormant, so check the known answers via `toggle_checklist_item`: Services `agent context`, Type `chore`, Model(s) `Qwen Flash`. The closing session claims nothing, moves nothing out of Review, and sets no fields beyond the card's own.
- Title: `Delete the legacy session custom field from the AI-Dev board (retired by cf-85)`.
- Description (disposition rationale): cf-85 retired the `session` custom field from the board contract — since the flip commit the flow writes only `slug` = `[<slug>](<session link>)` and never reads or writes `session` (plan folder `2026/2026-10-cf-85-refactor-wekan-slug-session-link`, DECISIONS D3/D12). Deleting the board-level field is owner-owned work; existing cards' field values are frozen history — no backfill is requested. Owner's call: Review → Finished (done/declined) or → Rework.
- Friction follow-up cards required by FRICTION.md at run close (if any) ride the same posture as separate cards; #85's own close sequence is unchanged: summary comment + Review move → `pipeline_release(outcome:"done")`.

## Risks / assumptions
- The cf-76 A15 guard (`agent-perms/surface.sh` ~1276–1279: "Custom fields: exactly two" + `` `slug`…`session` `` pairing) exists to fence a third field sneaking in. The flip MUST re-pin it to the one-field roster with the intent intact (roster named + count pinned + the `create_custom_field` negative loops untouched), not delete it.
- `tests/session-origin/surface.sh` s2 byte-pins the write-back step-2 block against `$BASE`: designed-red only inside the edit window; one commit containing tests+sources+generated turns it green (cf-50 posture, documented in that suite's header).
- The three s2 consumer byte-pins (claim-comment bullet "claiming the card: … plan folder path.", research-only step-7 session-link sentence, and the s3 UNRESOLVED-holder windows) must NOT be edited — they resolve through the amended definition.
- `rulesync generate` could surface unrelated drift; dev reverts/never commits out-of-scope generated changes (scope guards t14/c8/c7 would red).
- WeKan text custom fields may display the literal `[slug](url)` string rather than a clickable link — display is runtime, not repo-fixable; the user CONFIRMED the literal form as requested (batched round OQ4; DECISIONS D13).

## Open questions — ALL ANSWERED by the user (batched round, 2026-10-29); settled, work proceeds on these answers
- **OQ1 — final slug: CONFIRMED `cf-85-refactor-wekan-slug-session-link`.** No renames — folder/worktree/branch/session stand as minted (DECISIONS D10).
- **OQ2 — UNRESOLVED fallback shape: ADOPTED the combined `[<slug>](<raw session id>)`** — raw id in the link half, uniform resume parsing; the Config-constants bullet, the write-back sentence and the s3 test windows follow C01 as written (DECISIONS D11; D2's best guess is now user-rulled).
- **OQ3 — legacy `session` field: NON-DEFAULT ANSWER — retire in the contract AND this run raises the removal-request card.** The "Run close-out" section above is the normative step (coord-owned, Review-destination card); the board deletion itself stays owner-owned. Supersedes D3's deferral (DECISIONS D12).
- **OQ4 — literal markdown vs rendered link: CONFIRMED proceed** with literal `[slug](link)` exactly as the card requests (DECISIONS D13).
