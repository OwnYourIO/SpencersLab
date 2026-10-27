# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-27 · coord(plan) · kickoff in-work mark denied: `opencode api get /api/session/<id>` was allowed but every `opencode api patch …` shape (single-quoted with `$(date +%s%3N)` concatenation, and double-quoted) hit `Permission denied: shell` — the session stayed out of OpenChamber's In-work block (pure UI, nothing in the pipeline reads it) · resolution: proceeded with claim; session link + coord_session recorded in STATE.json/claim comment instead · open
- 2026-10-27 · research(plan) · shell tool mangled `$(...)` inline command substitutions to `***` (syntax error) · resolution: single heredoc python blocks instead of inline substitutions · open
- 2026-10-27 · research(plan) · GHCR tags/list pagination returned relative Link URLs; llama-swap's 2000-tag list never surfaced `unified-*` · resolution: direct manifest HEAD is authoritative (digest verified) · open
- 2026-10-27 · research(plan) · issue/PR citations by number alone were unreadable · resolution: fetched via issues API; two plan attributions corrected (STRATA_KV_GROW_HOLD nonexistent; 24576/55 misattribution) · open
