---
targets:
  - '*'
description: Plan and run a WeKan AI-Dev board card through the agent-board-coord pipeline
opencode:
  agent: agent-board-coord
---
Request (card ID, optional): $ARGUMENTS

Current state:
!`state=$(find .agents/plans -mindepth 2 -maxdepth 3 -name STATE.json 2>/dev/null); if [ -z "$state" ]; then echo "no plan yet"; else for f in $state; do echo "== $f"; cat "$f"; done; fi`

Intake is the WeKan AI-Dev board: a card id given in `$ARGUMENTS` is picked up as-is; otherwise take the first card walking Rework → Not Started → Low Priority, each list top-to-bottom (boards skill Card pickup, confirmed via `get_card`). The card description is the request, and its four standard checklists (Services / Type / Model(s) / Research) plus the `slug`/`session` custom fields supply the kickoff answers — the card-driven kickoff replaces the live questions. Research-labelled cards run the iterative research-only loop and exit at Review. If there is no approved plan, start with the card-driven kickoff — no user questions during planning; every genuine gap is recorded and batched into the one plan question round — then start Phase 1 (plan). If `plan_status` is `approved`, resume Phase 2 at the next ready chunk.
