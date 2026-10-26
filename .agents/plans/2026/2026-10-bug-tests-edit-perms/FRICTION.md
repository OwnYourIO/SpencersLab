# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

Carry-over from the origin ticket (2026/2026-10-cf-52-feat-coord-session-inwork, FRICTION.md line 9) — this ticket exists to close it:
- 2026-10-26 · test(C01, cf-52) · agent-test frontmatter grants no edit-allow for tests/** · resolution: wrote through parent-passed grants; follow-up ticket opened · open → tracked here as C01 scope
