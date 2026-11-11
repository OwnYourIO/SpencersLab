# strata-profile fixtures — cf-141 C03 era (orca8: `{parallel}` step)

Captured 2026-11-11 by the cf-141 validation-wave (test) session from the
default chart `strata-profile` ConfigMap DATA (render_on path: `helm template
gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com` + the seven
strata flags), helm v3.16.4+g7877b45 — the same binary as the era-0 anchor, so
the orca chain renders are directly comparable.

- File: `strata-orca-iq4_xs.json` — sha256
  `49d74c558fe354d64b4901d9bb04b66489284bf1709de9db01ed234310f9af44`
  (digest re-read live off the stored bytes, per provenance_violations)
- Determinism: double-capture diffed clean — two independent `helm template`
  runs byte-compared (full render and CM data) before this file was written.
- Tree state: branch `cf-141-refactor-strata-parallel-tuning` at HEAD
  `8789f33d4`; the capture was taken against the UNCOMMITTED C03 working tree
  (values.yaml/README/notes carry dev's C03 edits awaiting the coordinator's
  per-rung commit-set) — this directory lands in that same commit-set, so HEAD
  at capture is the pre-commit ref and the delta below is the proof of what
  the working tree rendered.

## §9.16 ritual — verification BEFORE capture

Programmatic delta check against `../strata-profiles-cf141-pre/` (era 0, the
whole-file anchor this ticket laid down for orca) run before any file here was
written, result:

- orca delta == exactly `{parallel}` — 4→8 by owner Q9's 8-everywhere ruling
  (plan-approved Q17(a)); the C03 brief states the shipped arithmetic plainly:
  57.7 + 9×3.35 + 8 + 6 ≈ 101.9 GiB against the untouched 92160 declaration
  — authorized overshoot, park refusals the expected first symptom, the
  runbook's orca boot-read gate and rung-4 revert line the control.
- Byte-frozen: `--memory-limit-mib 92160` (U9.2's zero-growth law survives —
  the raise touched slot count only, no cap), `--conversation-cache-mib 8192`
  × `-slots 16`, `--kv int8`/`--kv-resident 32768`/`--max-context 262144`,
  paths, aliases, tokenizer.
- Encoding: canonical `json.dumps` (`indent=2, sort_keys=True` + trailing
  newline — the cf141-l2 convention); parse-identity against the live CM data
  string asserted before writing.

## Era chain (orca leg)

| era | captured | step dir | sanctioned delta |
| --- | --- | --- | --- |
| 0 | 2026-11-10 @ `6a61be630` | `../strata-profiles-cf141-pre/` | original anchor (q4+orca whole-file) |
| 1 | 2026-11-11 (this directory) | here | `{parallel}` 4→8 (owner Q9, C03) |
| 2 | pending | `../strata-profiles-cf141-bump/` | `{drafting}` = `"mtp"` (owner Q16, C04) |

Chain law home: `test_strata_cf141_envelope.py::test_cf141_era_steps_are_one_delta_each`
(step sets from `CF141_ERA_CHAIN` / `CF141_ERA_STEP` / `CF141_ERA_FILES`; the
byte-freeze consumption arms in `test_strata_orca_rung.py` /
`test_strata_c08_rung_shifts.py` read the chain tip automatically). This dir
carries ONLY `strata-orca-iq4_xs.json`. Never edit an era file in place; a
re-cut adds a step.
