---
description: >-
  Provision or update the AI-Dev board structure (Backlog→Planning list mirror,
  Bucket labels + per-list rule pairs, Provider labels, Inbox ensure) through
  the wekan-board-provision skill
---
Scope note (optional): $ARGUMENTS

Load the `wekan-board-provision` skill and run its four-step procedure
against the AI-Dev board: collect the snapshot through read-only
`dev-boards` calls, run `python3 scripts/provision-board.py --fixture
<snapshot> --dry-run` and present the printed action plan for my explicit
confirmation BEFORE any apply, then apply in plan order (tool-probe the
live dev-boards catalog first; raw-REST fallback recipes where a tool is
absent), and verify with a re-collect + engine re-run expecting zero
actions.

Hard rules: dry run first, nothing applied without my confirmation of the
printed plan; additive-only — never delete or rename an existing list,
label, or rule; `Inbox` stays a Backlog-only parking list (never mirrored
into Planning, never Bucket-labeled or ruled). Anything the plan does not
cover stays untouched; report anomalies in the second verify run instead
of improvising around them.
