# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

Carry-over from the origin ticket (2026/2026-10-cf-52-feat-coord-session-inwork, FRICTION.md line 9) — this ticket exists to close it:
- 2026-10-26 · test(C01, cf-52) · agent-test frontmatter grants no edit-allow for tests/** · resolution: wrote through parent-passed grants; follow-up ticket opened · open → tracked here as C01 scope
- 2026-10-26 · plan(C01-amendment) · the first fold-in amendment was authored dirty in the disposable integration worktree /home/coder/.config/openchamber/tmp/oc-integrate-Ozu2FO (per its launch: "do NOT commit") and lost when that temp worktree was cleaned before the user's landing flow picked it up — the amended folder never reached main · resolution: amendment re-applied from the authoring session's context onto the pushed line (main 124fc2ae8) per D12, all evidence claims re-verified live; pipeline lesson for coord: dirty amendment folders in temp/disposable worktrees must be committed or copied to a durable worktree before the temp one is cleaned · open
- 2026-10-26 · test(C01) · bootstrap grants did NOT attach on this launch — agent-test denied every tests/** write by its own unpatched frontmatter (the ticket's defect, reproduced live); cf-52's parent-passed precedent did not survive the session-surface restarts · resolution: D13 grant-first relaunch route (dev lands the allow, fresh agent-test session inherits it); full prepared spec preserved in coord relaunch prompt · open until relaunch succeeds
