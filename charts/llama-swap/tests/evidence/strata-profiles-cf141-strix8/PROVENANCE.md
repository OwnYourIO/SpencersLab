# strata-profile fixtures — cf-141 C03 era (strix8: `{parallel}` step)

Captured 2026-11-11 by the cf-141 validation-wave (test) session from the
default chart `strata-profile` ConfigMap DATA (render_on path: `helm template
gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com` + the seven
strata flags), helm v3.16.4+g7877b45 — the same binary as every cf-141 step
dir, so the strix chain renders are directly comparable.

- File: `strata-strix-iq3_s.json` — sha256
  `5aba0847420e08fde518827dd03dcc3790f1bcb9b538ad2b13c64277cfca1c75`
  (digest re-read live off the stored bytes, per provenance_violations)
- Determinism: double-capture diffed clean — two independent `helm template`
  runs with the parsed `strata-profile` ConfigMap DATA compared equal at
  object level (all five data keys) before this file was written; the stored
  file is that data's canonical encoding, re-verified against the render.
- Tree state: branch `cf-141-refactor-strata-parallel-tuning` at HEAD
  `8789f33d4`; the capture was taken against the UNCOMMITTED C03 working tree
  (values.yaml/README/notes carry dev's C03 edits awaiting the coordinator's
  per-rung commit-set) — this directory lands in that same commit-set, so HEAD
  at capture is the pre-commit ref and the delta below is the proof of what
  the working tree rendered.

## §9.16 ritual — verification BEFORE capture

Programmatic delta check against `../strata-profiles-c09-repin/` (era 3, the
strix chain tip until here) run before any file here was written, result:

- strix delta == exactly `{parallel}` — 4→8 by owner Q9's 8-everywhere ruling
  (plan-approved Q17(a): shipped at the pin, knowingly beyond the chip's own
  arithmetic; the runbook's strix row states its boot-read gate subject).
- Byte-frozen: the `STRIX_EIGHT_SET` profile env, the halo `exe`/`lib_dirs`
  roots, every args member (the VERIFY-marked `--expert-cache 24576` /
  `--resident-budget-gib 55` pair included), `--mtp-window 8192`.
- Encoding: canonical `json.dumps` (`indent=2, sort_keys=True` + trailing
  newline — the cf141-l2 convention); parse-identity against the live CM data
  string asserted before writing.

## Era chain (strix leg)

| era | captured | step dir | sanctioned delta |
| --- | --- | --- | --- |
| 1–3 | 2026-10-29/31 | `../strata-profiles-pre-cf86/` → `-c07-repin/` → `-c09-repin/` | two engine re-pins, each exactly `{exe, lib_dirs}`, the halo tether green throughout |
| 4 | 2026-11-11 (this directory) | here | `{parallel}` 4→8 (owner Q9, C03) |
| 5 | pending | `../strata-profiles-cf141-bump/` | `{exe, lib_dirs, drafting}` — the merged C04 bump step (the 0.1.59 halo root + the drafting pin move in one render state; per-file step set in `CF141_ERA_STEP_FILE`) |

Chain law home: `test_strata_strix.py::test_c07_strix_fixture_era_delta_is_only_the_engine_root_pair`
(now walks the cf-141 step kinds beside the engine pairs) plus
`test_strata_cf141_envelope.py::test_cf141_era_steps_are_one_delta_each`;
membership per `CF141_ERA_FILES` (this dir carries ONLY the file the C03
strix step moved). The engine-re-pin no-primary-file law survives untouched:
it constrains re-pin eras (c07/c09), and this dir carries no primary file.
Never edit an era file in place; a re-cut adds a step.
