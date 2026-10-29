# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction`; cord appends (its own items included).

- 2026-10-29 · plan · values.yaml cites "cf-78 arena-math" but no cf-78 plan folder exists in this worktree (stale/foreign reference; the conclusion was independently reproduced by RESEARCH [S1]). · resolution: plan treats the ruling as sourced from Strata docs, not the missing folder · open
- 2026-10-29 · plan · the checkout's setup.sh model catalog (exact `--model` ids for Coder IQ1_M and any abliterated entry) is not inspectable from the repo — the pinned checkout lives on the on-cluster claim. · resolution: C01/C02 carry an explicit catalog-inventory gate (`./setup.sh --help` output recorded via the init path) instead of guessed ids · open
