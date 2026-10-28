# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-27 · dev(hygiene C01) · aislop-gate reports the plugin at 454 lines vs the sibling ticket's accepted-by-design note saying 453 · informational — warning accepted either way; line count unchanged by this chunk (comment recast added no lines); sibling DECISIONS wording left as-recorded per append-only rule · ignored
- 2026-10-27 · coord(hygiene) · aislop CLI absent + coord shell denied continue from the sibling ticket (both ignored there) · resolution: same workarounds applied — aislop-gate coverage; commit landing handed to the user · ignored
