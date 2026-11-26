# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

- 2026-11-24 · explore(explore) · anonymous Actions runs-LIST rows were sparse in earlier family notes — they now carry event_payload per row, making the detail sweep unnecessary · resolution: list-first idiom recorded for all later rounds · fixed
- 2026-11-24 · explore(explore) · urllib.request blocked on Actions HTML pages where curl passed · resolution: curl+xargs for all UI fetches · fixed
- 2026-11-25 · research(research) · /tmp write denial (hereditary) + nav-chrome GitHub HTML + storm-merge renumbering shifted citation ids · resolution: heredoc intermediates; api.github.com/Codeberg JSON instead of HTML; late source appended to LAST sources file keeping [1..34] stable · fixed
- 2026-11-25 · plan(plan/plan-c02) · old branch (cf-6-feat-builder-bootstrap-4) diverged from origin/main in three suite inputs (main-sync.yaml, release.yaml, AGENTS.md — concurrent-session ownership) · resolution: ALL posture measurements expanded from pure origin/main via git-archive; ticket branch subsequently minted fresh from origin/main; lesson: verify `git diff origin/main..<branch> -- <suite-inputs>` before trusting worktree posture · fixed
- 2026-11-25 · test(test_c01) · first SIM rebuild shipped a broken fix (PR-arm unbound base under set -u) — the suite itself reddened it at t14/d3/d14 before handoff · resolution: fix persisted into patch-sim2.py, matrix re-verified — self-catching behavior, kept as evidence of suite quality · fixed
- 2026-11-25 · coord · compaction fired mid-booking; a STATE anchor edit failed (fabricated tail) · resolution: re-grounded in-session per protocol; anchors taken from fresh reads; FRICTION.md found missing at booking time — seeded (third recurrence of the seed-together law; the law now travels with each ticket brief) · fixed
