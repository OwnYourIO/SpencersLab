# strata-profile fixtures — cf-141 C02 era (q4 L2: `STRATA_MMQ_KQ=1`)

Captured 2026-11-11 by the cf-141 validation-wave (test) session from the
default chart `strata-profile` ConfigMap DATA (render_on path: `helm template
gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com` + the seven
strata flags), helm v3.16.4+g7877b45 — the same binary as the era-0 anchor, so
the two renders are directly comparable.

- File: `strata-q4.json` — sha256
  `80a207759844e179b4443c67c6198fcd90ab5d66a9d1ff48c688f187efb1d1ff`
  (digest re-read live off the stored bytes, per provenance_violations)
- Determinism: double-capture diffed clean — two independent `helm template`
  runs byte-compared (full render and CM data) before this file was written.
- Tree state: branch `cf-141-refactor-strata-parallel-tuning` at HEAD
  `0cf2e7a3f`; the capture was taken against the UNCOMMITTED C02 working tree
  (values.yaml/README/service-values/notes carry dev's C02 edits awaiting the
  coordinator's chunk commit) — this directory lands in that same commit-set,
  so HEAD at capture is the pre-commit ref and the delta below is the proof
  of what the working tree rendered.

## §9.16 ritual — verification BEFORE capture

Programmatic delta check against `../strata-profiles-cf141-pre/` (era 0) run
before any file here was written, result:

- q4 delta == exactly `{env}` — `env: {}` → `{"STRATA_MMQ_KQ": "1"}` (JSON
  string value, owner Q1; the C02 doc-truth edits are comments/prose and
  correctly leave the profile data at the one-ruled delta).
- q4 `args` byte-frozen vs the anchor; key membership unchanged.
- orca byte-identical to this anchor (era 0 is its chain tip until C03);
  primary vs `../strata-profiles-u14-repin/`, strix vs
  `../strata-profiles-c09-repin/` likewise canonical-identical; the
  `strata-profile` CM data-key surface unchanged.
- Encoding: the file stores the CM data string verbatim (`json.dumps` with
  `indent=2, sort_keys=True` of the parsed render — asserted equal
  byte-for-byte before writing).

## Era chain (q4 leg)

| era | captured | step dir | sanctioned delta |
| --- | --- | --- | --- |
| 0 | 2026-11-10 @ `6a61be630` | `../strata-profiles-cf141-pre/` | original anchor (q4+orca whole-file) |
| 1 | 2026-11-11 (this directory) | here | `{env}` — `STRATA_MMQ_KQ: "1"` (owner Q1, C02) |
| 2 | pending | `../strata-profiles-cf141-q4parallel8/` | `{parallel}` 4→8 (owner Q9, C03) |
| 3 | pending | `../strata-profiles-cf141-bump/` | `{drafting}` = `"mtp"` (owner Q16, C04) |

Chain law home: `test_strata_cf141_envelope.py::test_cf141_era_steps_are_one_delta_each`
with step sets pinned in `strata_testlib` `CF141_ERA_CHAIN` / `CF141_ERA_STEP`
/ `CF141_ERA_FILES`. This dir carries ONLY the file the C02 step moved
(`CF141_ERA_FILES[CF141_ERA_L2] == {strata-q4.json}`) — purity is checked by
`test_cf141_era_dirs_purity_and_provenance`. Never edit an era file in place;
a re-cut adds a step.
