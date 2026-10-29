# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-29 · test(C01–C07) · rulesync-surface c8 goes red on ANY in-flight ticket's untracked plan folder until the ticket widens its scope allow-set · resolution: test session widened the c8 allow-set in the same change — repeat tickets will hit this too · fixed (in-run)
- 2026-10-29 · test(C02) · plan C02 AC4 said standalone-agents/surface.sh stays "unchanged green", but its S3 dynamic arm pinned pipeline-dev permission lists EQUAL to the standalone trio — mathematically incompatible with C02's deliberate allow→deny delta · resolution: delta-aware re-pin by the test session, accepted by coord (DECISIONS D23) · fixed
- 2026-10-29 · dev(C01) · the chunk probe recipe's port 4096 is owned by the production serve · resolution: `opencode run --standalone` private server + local SSE mock provider, never touched production · fixed (recipe amended below)
- 2026-10-29 · dev(C01) · `pkill -f` self-matched its own shell cmdline and killed two tool calls · resolution: pidfile-based kill in separate steps · open (future probe work beware)
- 2026-10-29 · dev(C01) · the 2.1.4 openai-compatible driver ALWAYS streams — a JSON mock body caused provider.invalid-output retry storms · resolution: scripted SSE mock · open (document in probe recipes)
- 2026-10-29 · dev(C01) · chunk fact-list assumed `data.id`/`data.info.id` for session.created; runtime emits flat `data.sessionID` — first pass scheduled nothing · resolution: fixed mid-run, correct shape pinned in DECISIONS D31 · fixed
