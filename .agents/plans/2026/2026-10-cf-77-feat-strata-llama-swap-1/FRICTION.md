# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-28 · plan(r2) · `helm` lives at `~/.local/bin/helm`, absent from the default non-login shell PATH — first render attempts "command not found" · resolution: `export PATH=$HOME/.local/bin:$PATH` per shell before helm invocations; later agents: do it up front, don't rediscover · open
- 2026-10-28 · plan(r2) · design-relevant repo finding: `.github/workflows/release.yaml`'s `Add repositories` loop awk-collapses empty `repository:` fields, so ANY declared subchart dependency in ANY chart makes every future release job exit 1 (repro'd in scratch) — hostile to the chart-dependency pattern outright · resolution: run-2 architecture avoids it (in-chart controller, zero workflow edits); future subchart need = release.yaml fix as its own ticket · open
