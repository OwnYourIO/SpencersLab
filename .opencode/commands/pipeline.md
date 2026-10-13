---
description: Plan and run a change through the agent-* pipeline
agent: agent-cord
---
Request: $ARGUMENTS

Current state:
!`state=$(find .agents/plans -mindepth 2 -maxdepth 3 -name STATE.json 2>/dev/null); if [ -z "$state" ]; then echo "no plan yet"; else for f in $state; do echo "== $f"; cat "$f"; done; fi`

If there is no approved plan, start Phase 1 (plan). If `plan_status` is `approved`, resume Phase 2 at the next ready chunk.