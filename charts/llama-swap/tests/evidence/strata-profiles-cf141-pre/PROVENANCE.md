# strata-profile fixtures — cf-141 era-0 anchor (pre-envelope)

Captured 2026-11-10 by the cf-141 agent-test session at plan approval
(plan `2026-11-10-refactor-cf-141-refactor-strata-parallel-tuning.md`,
owner-approved option (a) of Q17) from the default chart `strata-profile`
ConfigMap DATA (render_on path: `helm template gpu-ai-llama-swap
charts/llama-swap --set domain=test.example.com` + the seven strata flags),
branch `cf-141-refactor-strata-parallel-tuning` at clean tree `6a61be630`,
helm v3.16.4+g7877b45.

- File: `strata-q4.json` — sha256
  `70be38a0f71da4e4c44fb2213e32a8dca10dd0ead8b1e539513b24fcea3cd066`
- File: `strata-orca-iq4_xs.json` — sha256
  `c1c5da557abe88ba7987a35f287ad1fb6dc617d19bf021b0560cee1f3d1d6b01`
- Determinism: double-capture diffed clean.

## Why these two rungs get an anchor capture now

The q4 and orca profiles had no frozen-era capture: their preservation arms
were per-line pins (C06/C08-era). cf-141 moves both rungs' `parallel` (C03,
owner Q9) and q4's `env` (C02, owner Q1), and the plan's envelope law (law 7)
requires every rung's era delta to be machine-re-verifiable ("each rung's
delta == its pinned step-set"). A delta can only be verified against a stored
prior state, so the pre-envelope render is anchored here — the same role
`strata-profiles-pre-cf86` plays for the primary/strix chain.

The primary and strix chains need NO new anchor: their current frozen eras
(`../strata-profiles-u14-repin/`, `../strata-profiles-c09-repin/`) already
hold the pre-cf-141 state and the chain arms in `test_strata_strix.py` walk
from them.

## Era chain (cf-141 legs, append-only)

| rung | chain | step dirs (this ticket adds; captured at each landing round) |
| --- | --- | --- |
| q4 | era 0 (here) → `strata-profiles-cf141-l2` (C02: delta exactly `{env}`, `STRATA_MMQ_KQ: "1"` — owner Q1) → `strata-profiles-cf141-q4parallel8` (C03: delta exactly `{parallel}` 4→8 — owner Q9) → `strata-profiles-cf141-bump` (C04: delta exactly `{drafting}` = `"mtp"`, experimental-flagged per Q16) |
| orca | era 0 (here) → `strata-profiles-cf141-orca8` (C03: delta exactly `{parallel}`) → `strata-profiles-cf141-bump` (C04: delta exactly `{drafting}`) |
| primary | u14 (era 3) → `strata-profiles-cf141-rowh` (C03 shape step: delta exactly `{args, env, parallel}`, args move = exactly the `--conversation-cache-mib` 32768→16384 pair — owners Q9/Q10) → `strata-profiles-cf141-bump` (C04: delta exactly `{drafting}`) |
| strix | c09 (era 3) → `strata-profiles-cf141-strix8` (C03: delta exactly `{parallel}`) → `strata-profiles-cf141-bump` (C04 merged bump era: delta `{exe, lib_dirs, drafting}` — the bump arms drafting on every flash-next rung AND moves strix's packaged root in the same state, so per-file step sets pin it: `CF141_ERA_STEP_FILE`) |
| ornith | unmoved (parallel 1 negative pin, no drafting key — q36 surface law) |

Chain law home: `test_strata_cf141_envelope.py::test_cf141_era_steps_are_one_delta_each`
(step sets and per-dir file membership pinned in `strata_testlib`
`CF141_ERA_CHAIN` / `CF141_ERA_STEP` / `CF141_ERA_FILES`). Step dirs are
created by the test session at each chunk's landing round after programmatic
delta verification (the §9.16/§9.25 ritual); the values above are the plan's
rulings (Q1/Q9/Q10/Q16/Q17-(a)), not measurements — the captures prove the
render matched them. Never edit an era file in place; a re-cut adds a step.

This directory carries ONLY the two rungs without an earlier whole-file
capture. The era dirs of later steps carry only the files their step moved.
