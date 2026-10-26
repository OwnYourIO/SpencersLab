# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known problems are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-26 · dev(C02) · references/pipeline-overview.md coord/board-coord shell summary rows still read "none" — stale since cf-52, doubly since C02's third grant; C02.md scoped the matrix duty to permissions.md only, so the row was left as-is by rule · resolution: follow-up — fold overview-row parity into the next ticket legitimately re-opening agents-sync references (session-origin C02's NQ2 already plans the matrix cells; extend it to the overview pair) · open
