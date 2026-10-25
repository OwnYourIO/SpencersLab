# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- 2026-10-24 · plan · `dev-boards` MCP server not connected in this session (ExternalSecret placeholder) — could not inspect the AI-Dev board through the flow's own server; live board state also absent (list_boards => only "Projects"). · resolution: used gpu-tier `admin-global-wekan`/`readonly-global-wekan` for all live checks (same instance), per ticket guidance · partially fixed 2026-10-25: `dev-boards` is now connected (20 tools live in the coord session) after the dev-mcp-fleet fix-round landed; the AI-Dev board itself is still absent (list_boards => only "Projects") and remains the user-owned prerequisite · open (board prerequisite)
- 2026-10-24 · plan · carried from the stacked branch: `helm` not on the default PATH (`~/.local/bin/helm`); fresh worktrees need `helm dependency update charts/hivetools` before renders. · resolution: known workaround, apply as needed · open
- 2026-10-24 · plan · `containers/wekan-mcp/README.md` describes a VERSION/semver tag scheme that `docker-build.yaml` does not implement (stale docs). · resolution: fixed by C01 task list · fixed (C01 landed on-branch 64ffa8b9b — README now documents the real `:v<run_number>` + `:<branch>` scheme)
