# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

Carry-over from the origin ticket (2026/2026-10-cf-52-feat-coord-session-inwork, FRICTION.md line 8) — this ticket exists to close it:
- 2026-10-26 · coord(kickoff, cf-52) · manual `/pipeline-boards`-style launch carried no `Session origin:` line, so SESSION_URL_BASE was undefined by the copy-verbatim rule · resolution: coord improvised a live `$VSCODE_PROXY_URI` derivation + probe (out of contract; see this folder's DECISIONS D1/D5) · open → tracked here as C01 scope

Carry-over affecting this ticket's phases (no scope fold):
- 2026-10-26 · test (cf-52) · agent-test has no `tests/**` edit allow — this ticket's test phase bootstraps via parent-passed grants (cf-52 precedent); permanent fix owned by sibling 2026/2026-10-bug-tests-edit-perms · open
- planning pass 2026-10-26 · none new — investigation ran on repo artifacts + read-only dev-boards calls (field-shape notes already logged on cf-52 line 7: `list_comments` items carry `comment`, `created_at: null`).
- 2026-10-27 · review(C02)+coord · pipeline-overview coord/board-coord shell rows stale (four scoped allows) + permissions.md trailing-space rationale prose factually wrong (V2 docs: "cmd *" matches bare cmd too; shipped no-space grant unaffected) · resolution: both fold into the next ticket legitimately re-opening agents-sync references (NQ2/overview-parity duty now mirrored from kickoff-mints FRICTION; see D20) · open
