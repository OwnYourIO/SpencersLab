# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction`; cord appends (its own items included).

- 2026-10-29 · plan · values.yaml cites "cf-78 arena-math" but no cf-78 plan folder exists in this worktree (stale/foreign reference; the conclusion was independently reproduced by RESEARCH [S1]). · resolution: plan treats the ruling as sourced from Strata docs, not the missing folder · open
- 2026-10-29 · plan · the checkout's setup.sh model catalog (exact `--model` ids for the Strata candidates: abliterated IQ3_XXS, unsloth/orcarouter Q4 rungs) is not inspectable from the repo — the pinned checkout lives on the on-cluster claim, but the same checkout is embedded in the image at `/opt/strata/src/Strata`, so the inventory IS capturable from the image layer. · resolution: C01/C02/C06 carry explicit catalog-inventory gates instead of guessed ids · open
- 2026-10-29 · plan · the answer round renumbered all pending chunks (draft C01 Coder deleted; shifts per the plan-file renumber map) — anyone holding draft chunk ids must re-read. · resolution: map recorded in the plan file + DECISIONS renumap entry · ignored
