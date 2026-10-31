# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- 2026-10-31 · research(plan) · deployed dev-boards surface lags the repo (pin :v87 in services/dev values): create_label/create_list/create_swimlane/update_board/list_board_members absent from the live tool catalog — the OQ1 board-admin probe failed with "Unknown tool 'dev-boards.create_label'" · resolution: provisioning command ships a raw-REST fallback + tool-probe-before-apply; ledger card L4 tracks the pin bump that makes the MCP path whole · open
- 2026-10-31 · coord(kickoff) · stale residue of an earlier aborted run forced the `-2` suffix on this run's worktree/branch (cf-90-feat-board-coord-improvements-2) · resolution: run proceeds from the -2 surfaces; C03 lands the work-complete worktree cleanup so residue stops accumulating · open
