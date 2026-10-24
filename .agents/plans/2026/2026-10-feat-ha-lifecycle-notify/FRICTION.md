# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-24 · plan(C01) · V2 docs page /v2/docs/build/plugins truncates mid-stream on fetch, and V2 event payload schemas are documented on no docs page — blocked pure-docs grounding · resolution: extracted authoritative event definitions from the installed opencode binary's embedded JS (v2.0.32) and verified session topology live via `opencode api get /api/session` and `/context` · fixed
- 2026-10-24 · test(C01) · aislop CLI not installed in this worktree, `aislop ci --changes` cannot run · resolution: relied on the aislop-gate plugin (scanned every write, 100/100, 0 findings); package install out of remit for the offline/no-deps contract · open
- 2026-10-24 · test(C01) · `node --test` spec reporter prints no '# tests' summary in this environment, hiding counts · resolution: use `--test-reporter=tap` · ignored (did not reproduce — review(C01) and final review both saw the summary printed fine)
- 2026-10-24 · dev(C01) · transient aislop-gate 'agent is not defined' error when a signature change landed a beat before its call site · resolution: fixed in the immediately following edit, same turn — inherent to multi-edit TS refactors, no workaround needed · ignored
- 2026-10-24 · review(C01) · reporter friction item did not reproduce — default `node --test` printed the count summary fine in this worktree · resolution: sibling item re-statused ignored at close · fixed
