# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

- 2026-11-22 · plan(plan) · a transient grep-batch tool abort mid-grounding · resolution: retried, clean · fixed
- 2026-11-22 · dev(C01) · a transient "location shut down" abort on a parallel read pair · resolution: immediate retry, no data loss · fixed
- 2026-11-22 · coord(hygiene) · the same "location shut down" class cancelled a two-edit STATE batch mid-run · resolution: edits are atomic — verified nothing partial landed, retried single · fixed
- 2026-11-22 · test(test) · suite depends on `git rev-parse --show-toplevel`, so /tmp throwaways need `git init` before the battery driver runs · resolution: standard pattern, applied by review too · ignored
- 2026-11-22 · final-review(final) · final review found TWO coord-hygiene defects in STATE.json: a DUPLICATE `"plan"` key (the planner's thin block shadowed the coord's detailed RESULT — json last-wins silently) and a MISSING FRICTION.md (this run's friction only lived in RESULTs) · resolution: duplicate removed (thin block dropped, detailed kept), FRICTION.md seeded from the RESULT-recorded items; lesson: every run folder gets its FRICTION.md at seeding, and STATE key-uniqueness is part of the json.load check, not just parseability · fixed
