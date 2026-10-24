# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-24 · plan(C00-plan) · webfetch rewrote api.github.com / registry.npmjs.org URLs through an OSS file-proxy; first responses arrived as saved files, later ones 404ed · resolution: shell `curl` directly for registry/docs; later agents need not use webfetch for these hosts · fixed
- 2026-10-24 · test(all) · pipeline-role-test names no traceability-spec filename, no sibling precedent · resolution: TEST-SPEC.md at ticket root (uppercase convention of DECISIONS/FRICTION/RESEARCH) · fixed
- 2026-10-24 · test(all) · aislop CLI not installed locally · resolution: `npx aislop` (skill-sanctioned fallback) · fixed
