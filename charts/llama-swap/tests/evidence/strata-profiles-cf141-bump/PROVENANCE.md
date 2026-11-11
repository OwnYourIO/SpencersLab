# strata-profile fixtures — cf-141 C04 era (the merged bump step)

Captured 2026-11-11 by the cf-141 validation-wave (test) session from the
default chart `strata-profile` ConfigMap DATA (render_on path: `helm template
gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com` + the seven
strata flags), helm v3.16.4+g7877b45 — the same binary as every cf-141 step
dir, so the chain renders are directly comparable.

- File: `strata-iq3_s.json` — sha256
  `eba8ec38e986bd25d4a7470a67ba34e8cad800f2fcf387a8dc57f808e2998e6f`
- File: `strata-strix-iq3_s.json` — sha256
  `7eb9d6057f30af184666fccfa4412e9cfb7c0904c655078570460b43eee2c008`
- File: `strata-orca-iq4_xs.json` — sha256
  `bc9d8c86008d121f4084785706df4eac82c7ff9ace76bf6ab154513540ff297a`
- File: `strata-q4.json` — sha256
  `447ef920209be01b278f8a9f4a6a719d15ffe9f377c2c64e31efd022d029fc36`
  (digests re-read live off the stored bytes, per provenance_violations)
- Determinism: double-capture diffed clean — two independent `helm template`
  runs with the parsed `strata-profile` ConfigMap DATA compared equal at
  object level (all five data keys) before this file was written; the stored
  file is that data's canonical encoding, re-verified against the render.
  (A first back-to-back pair differed at raw-stdout level — reproduced once,
  retried deterministically equal on the next two pairs and recorded here
  rather than papered over: the object-level law held on every run.)
- Tree state: branch `cf-141-refactor-strata-parallel-tuning` at HEAD
  `1e20b574c`; the capture was taken against the UNCOMMITTED C04 working tree
  (values.yaml/Dockerfile/containers-README/fetch_models.sh/carry patch/notes
  carry dev r2's bump edits awaiting the coordinator's ledger commit — the
  digest rows are that round's live re-reads) — this directory lands in that
  same commit-set, so HEAD at capture is the pre-commit ref and the deltas
  below are the proof of what the working tree rendered.

## §9.16 ritual — verification BEFORE capture

Programmatic delta checks against each rung's prior era, run before any file
here was written (the C04 dev round pre-simulated the same sets; re-verified
independently against the live render here):

- primary (`../strata-profiles-cf141-rowh/` → here): delta == exactly
  `{drafting}` = `"mtp"`.
- strix (`../strata-profiles-cf141-strix8/` → here): delta ==
  `{exe, lib_dirs, drafting}` — the per-file widening
  (`CF141_ERA_STEP_FILE`): the merged bump era moves the packaged halo root
  to `0.1.59-linux-x86_64-hip-halo` AND arms drafting in one render state
  (the §9.28 design-call; an engine-only capture would need a state that
  never exists). env (the eight-set) byte-frozen.
- orca (`../strata-profiles-cf141-orca8/` → here): delta == `{drafting}`.
- q4 (`../strata-profiles-cf141-q4parallel8/` → here): delta ==
  `{drafting}`; env stays exactly C02's `{"STRATA_MMQ_KQ": "1"}` (Q16:
  present, experimental-flagged in the values source — render carries the
  key, source carries the word).
- ornith: NO key moved; the q36 surface gets no drafting (closed-world
  check) and this dir carries no ornith file.
- `parallel`, `args`, `env`, caps, conv: frozen across all four files — the
  bump touches no envelope (plan law 6 / C04 AC4).

## Era chain (continues the per-rung tables)

| rung | step | dir | sanctioned delta |
| --- | --- | --- | --- |
| q4 | era 3 (final cf-141 step) | here | `{drafting}` (owner Q16 + RESEARCH [79], C04) |
| orca | era 2 (final) | here | `{drafting}` |
| primary | era 5 (final) | here | `{drafting}` |
| strix | era 5 (final) | here | `{exe, lib_dirs, drafting}` (merged bump step) |

Chain law home: `test_strata_cf141_envelope.py::test_cf141_era_steps_are_one_delta_each`
(step sets from `CF141_ERA_CHAIN` / `CF141_ERA_STEP` / `CF141_ERA_STEP_FILE` /
`CF141_ERA_FILES` — this dir carries EXACTLY the four flash-next files). The
halo-label tether `test_c07_strix_fixture_ties_to_the_built_halo_root` now
binds this fixture to the single 0.1.59 halo root the re-cut Dockerfile
COPY/verify-lines name; a mid-bump half-edit reddens by design. This closes
the cf-141 era chain: any future re-cut or scale-back adds a step. Never edit
an era file in place.
