---
targets:
  - '*'
description: Scheduled hourly WeKan AI-Dev board launch — the gated variant of /pipeline-boards for agent-board-coord
opencode:
  agent: agent-board-coord
---

The Gate output below was produced when this command expanded — before your first turn, outside the tool-permission flow — and it decides what you do next.

!`bash scripts/agent-board-coord-gate.sh || true`

<!-- Root-relative path is deliberate: the shell block runs from the active project location — after landing, the main checkout that the hourly scheduled task owns. '|| true' keeps a non-zero verdict exit from blanking the inserted output. -->

Request (card ID, optional): $ARGUMENTS

Current state:
!`state=$(find .agents/plans -mindepth 2 -maxdepth 3 -name STATE.json 2>/dev/null); if [ -z "$state" ]; then echo "no plan yet"; else for f in $state; do echo "== $f"; cat "$f"; done; fi`

Decision rule — key on the FIRST line of the Gate output above, not on the exit code (the `|| true` masks it). It starts with one of three markers:

- `GATE: SKIP <reason>` — session detection failed; the run is skipped fail-closed (an unproven guard is a stopped guard). Reply with ONE short line quoting that verdict, then stop: no board calls at all (not even reads), no mint, no worktree, no `session_rename`, no subagent launch, no STATE.json/DECISIONS.md/FRICTION.md writes, no skill loading.
- `GATE: RUN <basis>` — no other live board-coord session; continue exactly as `/pipeline-boards` does — card-driven kickoff, batched-question protocol, chunk loop; the flow authority stays in the boards skill.
- `GATE: LIVE <id> (<age>s) <title>` — another board-coord session is live; run the BOARD CHECK below before anything else.

BOARD CHECK (LIVE branch only, read-only dev-boards calls): `list_boards` → the board **AI-Dev**; its lists under swimlane **In Process** → the list titled **Executing**; `list_cards_in_list` on it → count the cards.

- Executing empty → continue exactly as `/pipeline-boards`.
- ≥1 card → stop with ONE short line quoting the LIVE verdict (session id + age) and the card titles (max 5, then a truncation marker). No board WRITES ever on this path.
- Any call failure, ambiguous board/list resolution, or unexpected output → board-check unavailable → stop with ONE short line (run skipped, fail-closed like the session gate: the empty-card disjunct cannot be proven).

Until an Executing-empty verdict, the ONLY allowed dev-boards operations on the LIVE branch are reads: `list_boards`, `get_board`, `list_cards_in_list`, `get_card`, `list_comments`, checklist reads. Banned outright until that verdict: `move_card`, `add_comment`, `set_card_custom_field`, `delete_checklist_item`, `toggle_checklist_item`, and card creation.

Notes:
- Manual one-off launches use `/pipeline-boards` and are ungated by design — the guard lives only on this scheduled path.
- A session shown LIVE here may be an interactive or worktree run — that it counts is deliberate: this launch asks "is anything running, however started".
- A human-instructed forced-through launch: re-run the gate command above with `--threshold 0` and let its verdict steer this turn.
- The board, swimlane and list names above must match the boards skill — on drift the check fails CLOSED (a skip); the boards skill remains the flow authority.
