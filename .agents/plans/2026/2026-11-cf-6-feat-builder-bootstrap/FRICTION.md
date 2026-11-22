# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

- 2026-11-22 · plan(plan) · the anonymous infra Actions API reports `status: success` on old rows whose UI runs failed, and its id space ≠ UI run numbers (run-1 gotcha re-encountered) — a "did anything heal?" read through it misleads · resolution: registry-side probes (all three lines empty, `pkg-api []`) + the runner-pod death-line log tail are the authoritative outage evidence; recorded as Verified facts 2–3.
- 2026-11-22 · plan(plan) · `vars.PUSH_URL_DEV` already exists for main-sync's git mirror — a same-name registry-host variable would have silently collided (repo-scoped vars are shared across workflows) · resolution: peer host named `FORGE_DEV_REGISTRY`; collision guard pinned in the new suite (b2/b6 greps).
- 2026-11-22 · plan(plan-rework) · the NO-PEER owner ruling evaporated that collision's subject (no peer variable ships at all) — the b6 leg re-purposed as the closed credential-set pin (`secrets.*` ⊆ {GHCR_PUSH_PAT, FORGE_PUSH_TOKEN}, `vars.*` ⊆ {ROLE}) · the underlying law (repo-scoped vars are shared across workflows — name-check any new `vars.X` before minting it) still governs future surfaces · ignored (accepted, guard re-pointed)
