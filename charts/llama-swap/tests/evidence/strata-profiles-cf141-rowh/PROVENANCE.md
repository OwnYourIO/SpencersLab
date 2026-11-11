# strata-profile fixtures — cf-141 C03 era (row-H: primary shape step)

Captured 2026-11-11 by the cf-141 validation-wave (test) session from the
default chart `strata-profile` ConfigMap DATA (render_on path: `helm template
gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com` + the seven
strata flags), helm v3.16.4+g7877b45 — the same binary as the era-0 anchor and
the cf141-l2/cf141-pre captures, so the chain renders are directly comparable.

- File: `strata-iq3_s.json` — sha256
  `8008d30f8bd6890f52cea21443ca2c95d128ef0f1614834828c2b49503ee5ab8`
  (digest re-read live off the stored bytes, per provenance_violations)
- Determinism: double-capture diffed clean — two independent `helm template`
  runs byte-compared (full render and CM data) before this file was written.
- Tree state: branch `cf-141-refactor-strata-parallel-tuning` at HEAD
  `8789f33d4`; the capture was taken against the UNCOMMITTED C03 working tree
  (values.yaml/README/host-prep note/tuning runbook carry dev's C03 edits
  awaiting the coordinator's per-rung commit-set) — this directory lands in
  that same commit-set, so HEAD at capture is the pre-commit ref and the delta
  below is the proof of what the working tree rendered.

## §9.16 ritual — verification BEFORE capture

Programmatic delta check against `../strata-profiles-u14-repin/` (era 3, the
primary's chain tip until here) run before any file here was written, result:

- primary delta == exactly the row-H shape-step set `{args, env, parallel}` —
  the ONE sanctioned multi-key step of this ticket (a single owner ruling
  complex: Q9's 8-everywhere + Q10's row-H, plan-approved Q17(a)); inside
  `args` the membership is unchanged and exactly ONE pair moves,
  `--conversation-cache-mib` 32768→16384 (slots stay 16); `env` goes `{}` →
  `{"STRATA_PLE_AUTO_RAM": "0"}` (quoted string [26] — the PLE-direct leg of
  row-H); `parallel` 4→8.
- Byte-frozen (re-verified against the era-3 capture): `--memory-limit-mib`
  110592, `--kv int8`, `--kv-resident 32768`, `--max-context 262144`,
  `--prefill auto:32768`, paths, aliases, exe/lib_dirs — the plan's AC1 list.
- Encoding: the file stores the parsed render canonically (`json.dumps` with
  `indent=2, sort_keys=True` + trailing newline — the cf141-l2 convention);
  parse-identity against the live CM data string asserted before writing.

## Era chain (primary leg)

| era | captured | step dir | sanctioned delta |
| --- | --- | --- | --- |
| 1–3 | 2026-10-29/11-01 | `../strata-profiles-pre-cf86/` → `-t03-repin/` → `-u14-repin/` | the single-flag history (T3 `--prefill`, U14 `--memory-limit-mib`), re-verified byte-true by `test_primary_fixture_era_chain_is_one_owner_ruled_flag_per_step` |
| 4 | 2026-11-11 (this directory) | here | row-H shape step `{args, env, parallel}` — conv 16384 + `STRATA_PLE_AUTO_RAM="0"` + parallel 8 (owners Q9+Q10, C03) |
| 5 | pending | `../strata-profiles-cf141-bump/` | `{drafting}` = `"mtp"` (owner Q16, C04) |

Chain law home: `test_strata_cf141_envelope.py::test_cf141_era_steps_are_one_delta_each`
(step sets pinned in `strata_testlib` `CF141_ERA_CHAIN` / `CF141_ERA_STEP` /
`CF141_ERA_STEP_FILE` / `CF141_ERA_FILES`). This dir carries ONLY the file the
row-H ruling moved (`CF141_ERA_FILES[CF141_ERA_ROWH] ==
{strata-iq3_s.json}`) — purity is checked by
`test_cf141_era_dirs_purity_and_provenance`. Sibling era steps captured the
same day from the same render: `../strata-profiles-cf141-strix8/`,
`-cf141-orca8/`, `-cf141-q4parallel8/`. Never edit an era file in place; a
re-cut (e.g. a rung-4 scale-back under an explicit in-round owner word, plan
law 3) adds a step and re-pins the ruling-table row.
