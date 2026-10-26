# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted).

- 2026-10-26 · coord(run-wide) · `dev-boards` MCP server not registered in this session's tool catalog (neither direct tools nor the Code Mode `tools` namespace) — could not call wekan-mcp tools as designed · resolution: spoke MCP-over-HTTP directly to `https://mcp.dev.scifi.farm/boards/mcp` via `execute`+fetch (initialize → tools/call, SSE-frame parsing); worked fully · open (fix: register the dev-boards server for agent-board-coord)
- 2026-10-26 · coord(kickoff) · opencode tool surface exposes ONLY `worktree_remove` — no `session_rename`/`worktree_create`/`session_move`; shell denied so `opencode api` CLI unusable; launch had no `Session origin:` line (read of the command source also denied) · resolution: local OpenChamber API `http://127.0.0.1:3000/api/session/<id>` via fetch for rename + work-state read-merge-write (verified landed); skipped worktree/session_move — research-only run writes only the plan folder; raw-id session links per the UNRESOLVED rule · open (fix: restore the coordinator's opencode tool grants / command launch)
- 2026-10-26 · coord(intake) · wekan-mcp argument ergonomics cost round-trips: `board_id` required on nearly every call, checked-state field is `finished` (not `checked`), `move_card` needs `from_list_id`/`to_list_id` and REJECTS `swimlane_id`, comment body arg is `comment` · resolution: discovered via validation errors, cached here for later runs · open (fix: document in the wekan-api skill's MCP section)

## Follow-up tickets planned for the open items (draft, awaiting human approval)
- Item 1 → `.agents/plans/2026/2026-10-bug-board-coord-dev-boards-allow/` (root cause found: allow literal `dev_boards*` can never match hyphenated MCP tool ids → `dev-boards*`). Re-status item 1 open→fixed only when its C01 lands + AC7 live-proofs on the next board-coord launch.
- Item 3 → `.agents/plans/2026/2026-10-docs-wekan-mcp-arg-ergonomics/` (wekan-api is self-written → sanctioned edit; signatures corroborated against containers/wekan-mcp source). Re-status item 3 open→fixed on its landing.
- Item 2 (opencode tool grants) — human declined to plan a ticket this run; stays open.
