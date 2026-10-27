# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-27 · coord(plan) · kickoff in-work mark denied: `opencode api get /api/session/<id>` was allowed but every `opencode api patch …` shape (single-quoted with `$(date +%s%3N)` concatenation, and double-quoted) hit `Permission denied: shell` — the session stayed out of OpenChamber's In-work block (pure UI, nothing in the pipeline reads it) · resolution: proceeded with claim; session link + coord_session recorded in STATE.json/claim comment instead · open
- 2026-10-27 · research(plan) · shell tool mangled `$(...)` inline command substitutions to `***` (syntax error) · resolution: single heredoc python blocks instead of inline substitutions · open
- 2026-10-27 · research(plan) · GHCR tags/list pagination returned relative Link URLs; llama-swap's 2000-tag list never surfaced `unified-*` · resolution: direct manifest HEAD is authoritative (digest verified) · open
- 2026-10-27 · research(plan) · issue/PR citations by number alone were unreadable · resolution: fetched via issues API; two plan attributions corrected (STRATA_KV_GROW_HOLD nonexistent; 24576/55 misattribution) · open
- 2026-10-27 · test(plan) · the credit-failed first test launch crashed leaving 11 uncommitted test files with STATE test_session=null — silent-partial-write hazard · resolution: successor test session audited all 11 before extending (caught two false-fail asserts that way), completed and committed them as c375b238b · fixed
- 2026-10-27 · test(plan) · tests/renovate/dockerfile-pins.sh red at branch base (stale uv literal 0.13.1 vs 0.13.5 owned by the coder-workspace ticket) · resolution: proven pre-existing via clean-tree run; left untouched, flagged for its owner — NOT cf-77's gate · open
- 2026-10-27 · test(plan) · scratch-file writes outside the repo denied (correct role boundary) + shell heredocs needed for in-memory JS-engine verification · resolution: python+node heredocs, results recorded in handoff · fixed
