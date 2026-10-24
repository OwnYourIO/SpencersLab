# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · open
- 2026-10-24 · plan(C00-plan) · webfetch rewrote api.github.com / registry.npmjs.org URLs through an OSS file-proxy; first responses arrived as saved files, later ones 404ed · resolution: shell `curl` directly for registry/docs; later agents need not use webfetch for these hosts · fixed
- 2026-10-24 · test(all) · pipeline-role-test names no traceability-spec filename, no sibling precedent · resolution: TEST-SPEC.md at ticket root (uppercase convention of DECISIONS/FRICTION/RESEARCH) · fixed
- 2026-10-24 · test(all) · aislop CLI not installed locally · resolution: `npx aislop` (skill-sanctioned fallback) · fixed
- 2026-10-24 · dev(C01) · `$?` after `cmd | tail` reflects tail's status, masking the validation script's real exit code · resolution: re-ran redirecting output to a file and checked the real exit code; later agents should avoid `$?` through pipes in validation runs · open
- 2026-10-24 · review(C01) · `helm` not on PATH in agent sessions · resolution: call `/home/coder/.local/bin/helm` directly (also: fresh worktrees need `helm dependency build charts/coder` before `helm template` — pre-existing gitignored dep tarball) · fixed
- 2026-10-24 · review(C01) · `npx aislop scan --changes --base origin/main` prints "0 changed" on a commits-ahead branch and scores 0 files for Dockerfile/sh diffs — PASS is non-informative for container diffs · resolution: recorded; rely on the suite gates for container/script work · ignored
