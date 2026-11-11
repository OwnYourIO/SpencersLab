# strata-profile fixtures — cf-141 C03 era (q4 step 2: `{parallel}`)

Captured 2026-11-11 by the cf-141 validation-wave (test) session from the
default chart `strata-profile` ConfigMap DATA (render_on path: `helm template
gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com` + the seven
strata flags), helm v3.16.4+g7877b45 — the same binary as the era-0 anchor and
the cf141-l2 capture, so the q4 chain renders are directly comparable.

- File: `strata-q4.json` — sha256
  `be9c0d0ede0125218565741881cef543ce04d2f1b25c2f94049894ec635e94a1`
  (digest re-read live off the stored bytes, per provenance_violations)
- Determinism: double-capture diffed clean — two independent `helm template`
  runs byte-compared (full render and CM data) before this file was written.
- Tree state: branch `cf-141-refactor-strata-parallel-tuning` at HEAD
  `8789f33d4`; the capture was taken against the UNCOMMITTED C03 working tree
  (values.yaml/README/notes carry dev's C03 edits awaiting the coordinator's
  per-rung commit-set — q4's rung commit also replaces the a6e493b78 ruling
  comment with the Q9 verbatim) — this directory lands in that same
  commit-set, so HEAD at capture is the pre-commit ref and the delta below is
  the proof of what the working tree rendered.

## §9.16 ritual — verification BEFORE capture

Programmatic delta check against `../strata-profiles-cf141-l2/` (era 1, the
C02 L2 step) run before any file here was written, result:

- q4 delta == exactly `{parallel}` — 4→8 by owner Q9 superseding a6e493b78's
  4-slot ruling (plan-approved Q17(a)); the shipped arithmetic stays stated as
  authorized overshoot: A' = 71.73 + 9×3.35 + 16 + 6 ≈ 123.9 GiB > the 110Gi
  cgroup — degrade-or-kill expected, the rung-4 revert line and boot-read
  gate pre-written in the runbook ladder.
- Byte-frozen vs the l2 era: `env` == exactly `{"STRATA_MMQ_KQ": "1"}` (C02's
  pin, untouched by this step — the two-step `{env}`→`{parallel}` chain is the
  machine-proof these are TWO separate owner rulings, not one smuggled
  change), all args (103680 cap, conv 16384×16, `--kv int8`/`--kv-resident
  32768`/`--max-context 262144`), paths, aliases, tokenizer.
- Encoding: canonical `json.dumps` (`indent=2, sort_keys=True` + trailing
  newline — the cf141-l2 convention); parse-identity against the live CM data
  string asserted before writing.

## Era chain (q4 leg — continues the l2 table)

| era | captured | step dir | sanctioned delta |
| --- | --- | --- | --- |
| 0 | 2026-11-10 @ `6a61be630` | `../strata-profiles-cf141-pre/` | original anchor (q4+orca whole-file) |
| 1 | 2026-11-11 (cf141-l2) | `../strata-profiles-cf141-l2/` | `{env}` — `STRATA_MMQ_KQ: "1"` (owner Q1, C02) |
| 2 | 2026-11-11 (this directory) | here | `{parallel}` 4→8 (owner Q9 supersedes a6e493b78, C03) |
| 3 | pending | `../strata-profiles-cf141-bump/` | `{drafting}` = `"mtp"` (owner Q16, C04) |

Chain law home: `test_strata_cf141_envelope.py::test_cf141_era_steps_are_one_delta_each`
(plus its explicit two-step q4 leg: anchor→l2 delta == exactly `{env}`,
args-identity across both). This dir carries ONLY `strata-q4.json`
(`CF141_ERA_FILES[CF141_ERA_Q4P8]`). Never edit an era file in place; the
q4 scale-back rung (parallel→4, its own single-value commit under an explicit
in-round owner word, plan law 3) would add era 4 and re-pin the ruling-table
row, not touch this one.
