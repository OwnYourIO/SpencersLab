# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-29 · plan(C01) · tests/pipeline-models/surface.sh M3 catalog-delta arm is structurally red on any post-cf-58 base (TB=merge-base self-contradiction, measured @ eb8a963) — would fail the suite regardless of this ticket's edit · resolution: folded into C01's test scope as a presence-HOLD re-base (DECISIONS D5); red→green closes it with the chunk · open
- 2026-10-29 · dev-local(C01) · first boards/SKILL.md edit missed on oldString — read tool's line-number prefix visually shifts indent (2-space read as 3) · resolution: verified raw bytes with sed -n | cat -A and re-applied (standard recipe) · fixed
