# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-29 · coord(pickup) · first agent-plan launch died instantly on "Provider returned error" (no files written) · resolution: relaunched fresh with the full kickoff payload, no re-asks · fixed
- 2026-10-29 · coord(pickup) · scoped shell allows deny the WHOLE command string once a scoped binary is piped or wrapped (`opencode api get … | head`, `git show … | head`, python heredoc all rejected) · resolution: run scoped commands bare; read files with the Read tool instead of shell · fixed
- 2026-10-29 · plan(plan) · deployed-version ambiguity: docstring stamps say v9.99, live board runs v12.64 · resolution: chart 12.65.0 pins v12.64; lists.js create + move routes re-verified at tag v12.64 · fixed
- 2026-10-29 · plan(plan) · stale "25-tool surface" line in skills/wekan-api/SKILL.md risks a missed parity edit when the surface grows 26→27 · resolution: recorded in plan blast radius + DECISIONS D6; suite t3 asserts its absence; CLOSED by C01 dev (line rewritten to 27-tool wording, t3 green) · fixed
- 2026-10-29 · coord(test) · first agent-test launch "Provider returned error" kill was NOT write-free — ses_e77eec5faffe had written all three suite files but never executed them (create-list.sh invalid bash: missing outer `fi`; t2 could not fail — missing else-fail; t3 `grep -c` set-e silent death; position-key pin mis-scoped) · resolution: retry session audited as sole author, repaired the four defects, ran per-subset red census + mock-clone green proof · fixed
- 2026-10-29 · coord(test) · board-context.sh t4 red at pristine HEAD (cf-75 suite vs drifted live permissions matrix) — pre-existing, out of this plan's Commands, NOT a dev/review failure of this ticket · resolution: baseline noted; do not route as validation_at_fault; board-hygiene owner call deferred · open
- 2026-10-29 · coord(test) · subagent final message showed the handoff summary, verbatim RESULT block truncated at display · resolution: same-session continuation re-emitted the block verbatim before bookkeeping · fixed
- 2026-10-29 · dev-local(C01) · `aislop ci --changes` on server.py surfaced 7 pre-existing decorative-separator warnings inviting `aislop fix` — applying it would delete base lines and break AC7's one-additive-hunk / t5 gate byte-pins · resolution: verified flagged lines are all base content, left untouched, CI rc=0 recorded · fixed
