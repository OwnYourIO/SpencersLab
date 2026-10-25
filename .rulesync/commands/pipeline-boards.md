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

Intake is the WeKan AI-Dev board: if a card id is given, pick that card up; otherwise take the highest-sorted card from Rework, falling back to Not Started (boards skill). The card description is the request. If there is no approved plan, start with the boards kickoff — no user questions during planning; every question is recorded and batched into the one plan question round — then start Phase 1 (plan). If `plan_status` is `approved`, resume Phase 2 at the next ready chunk.
