# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-27 · plan(plan) · No aislop PATH check in the planning session (plan-only writing); the `aislop ci --changes` ladder in the plan's Commands assumes resolvable via `npx --no-install` fallback. · resolution: verification deferred to dev/review chunks which must run the Commands for real; if the binary is absent there, that chunk blocks and escalates rather than skipping the gate. · open
- 2026-10-27 · plan(plan) · The `boards` skill text says the AI-Dev board has six lists, but the live In Process swimlane carries an extra non-pipeline "Test" list (plus other swimlanes' lists) — skill-vs-reality drift agents hit when reasoning about board structure. · resolution: captured as a plan risk; board structure is human-owned, pickup walk unchanged (only Rework/Not Started/Low Priority are consulted); a boards-skill text fix may ride C03. · open
- 2026-10-27 · coord(plan) · dev-boards MCP absence in older scheduled sessions (cf-70 item 1) made the two earlier claims of this card stale; this run's catalog has dev-boards live and the probe passed. · resolution: none needed here — the fix is the in-flight cf-75-bug-wekan-mcp-context branch; re-verify at C03/C04 dev time. · fixed
- 2026-10-27 · research(C04-research) · `glob` silently hides dot-directories (`.rulesync/**` returned nothing) — easy to misread as "no sources". · resolution: shell `ls`; any agent surveying rulesync/hidden surfaces must not trust glob alone. · open
- 2026-10-27 · research(C04-research) · OpenCode docs dead-ends: the plugins Overview page lacks hook details (they live under /docs/build/plugins/server) and a bare docs-index fetch echoes llms.txt. · resolution: fetch exact subpage URLs; recorded in RESEARCH.md sources. · open
