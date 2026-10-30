# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-30 · research(cf-89 pre-plan) · interim `mv storm-runs` briefly swept ANOTHER ticket's tracked storm-runs folder out of the worktree · resolution: `git restore` from HEAD, repo verified byte-identical; intermediates moved to /tmp/opencode — fixed
- 2026-10-30 · research(cf-89 pre-plan) · raw.githubusercontent served a stale/partial boards.js once (route grep 0 hits); searxng suggestions endpoint empty · resolution: github archive tarballs + searxng_web_search + GitHub API — fixed
- 2026-10-30 · test(C01+C02) · pre-existing aged pins red at HEAD/main and hit by the plan's regression line: board-context.sh t4 (TB=merge-base default; agent-board row in BOTH base and now — "adds exactly one row" unpassable post-cf-70) and create-list.sh t2 (single-additive-hunk pin vs 0-hunk today) · resolution: coord waived t4 as known-red for cf-89 (follow-up card planned at close); t2 kept green by ruling C01 lands one contiguous additive hunk — open (follow-up card pending)
- 2026-10-30 · coord(cf-89 kickoff) · worktree directory keeps legacy basename cf-89-feat-wekan-mcp-v102-tools after the user's slug swap — `git worktree move` denied in the coord's git-only shell · resolution: branch/session/folder/card carry the new slug; path recorded in kickoff.worktree — ignored (cosmetic, ruled in DECISIONS)
