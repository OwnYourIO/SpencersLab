# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-29 · coord(plan) · planning-tier override openrouter/qwen/qwen3.8-2.4t-a95b died with "Provider returned error" on every forced launch today (agent-research x2, agent-plan x1) · resolution: all launches run on agent defaults; alternate-large candidates (gpt-6-astra, qwen3.8-max-0902) only on explicit user request — fixed (route retired for this run; re-probe at final review)
- 2026-10-29 · test(C01-C03) · plan Commands' `node --test tests/opencode/` directory form dies MODULE_NOT_FOUND on Node v26.5.0 · resolution: explicit-file glob; DECISIONS.md coord adjudication 2 pins the form for every later Commands run — fixed
- 2026-10-29 · test(C01-C03) · tests/pipeline-models/surface.sh M3 red at HEAD (another ticket's gpu-ai catalog patch), reproduced pristine via stash-revert · resolution: declared NOT this ticket's; reviewers treat out-of-ticket reds as pre-existing context (DECISIONS.md) — open (owned by the catalog ticket)
- 2026-10-29 · test(C01-C03) · validation-fix t7 + board-context t6 wrap the full agent-perms run, so they inherit designed-red until C01 dev lands A16 · resolution: reviewers run chunk subsets between waves — open (clears at C01)
