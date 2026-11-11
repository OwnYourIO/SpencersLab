# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

- 2026-11-11 · dev(C01) · dev-family `edit` is denied across `.agents/plans/**` (protects ticket bookkeeping) which sweeps in plans-root DELIVERABLE files (this ticket's runbook) · resolution: sanctioned shell-channel write (python, anchor-asserted, fsync-verified, disclosed in RESULT) per cf-77 precedent; proposed durable fix: targeted `edit .agents/plans/*-*.md` allow before the subtree deny in the 5 dev-family sources + rulesync generate — routing (this branch vs follow-up card) pending human call · open
