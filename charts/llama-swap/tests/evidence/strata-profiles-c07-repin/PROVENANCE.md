# strata-profile fixtures — C07 re-pin era (era 2)

Captured 2026-10-31 by the cf-86 agent-test session (C07-fixture-repair
round) from the default chart `strata-profile` ConfigMap DATA (render_on
path: `helm template gpu-ai-llama-swap charts/llama-swap --set
domain=test.example.com` + the seven strata flags), branch
`cf-86-feat-more-strata-models`, dirty tree carrying the C07 dev round 1
(image lift + v0.2.8 / engine 0.1.54 re-pin; lands in the same commit as
this fixture), helm v3.16.4+g7877b45.

- File: `strata-strix-iq3_s.json` — sha256
  `547ba10d8eb8c2f81ffa1b1a7b1e8038ac68ee836d8f4765763ba9512fd2b68f`
- Determinism: double-capture diffed clean.
- This directory carries ONLY the files whose frozen era moved. The primary
  `strata-iq3_s.json` needed NO era move (verified at capture: zero changed
  keys vs its pre-cf-86 capture) — its exe/lib_dirs ride the version-free
  claim-compiled pack root (`/models/strata/Strata/...`), so an engine
  re-pin cannot touch it.

## Era chain

| era | captured | sha256 | reason |
| --- | --- | --- | --- |
| 1 | 2026-10-29 @ `4f7126689` (pre-cf-86, clean tree) — see `../strata-profiles-pre-cf86/` | `28d0ed389d250d1167f46c2975e33cc578990b9236fe8b4fa945904d4ce3a359` | original capture |
| 2 | 2026-10-31 cf-86 C07 (image lift, engine 0.1.52→0.1.54) | `547ba10d8eb8c2f81ffa1b1a7b1e8038ac68ee836d8f4765763ba9512fd2b68f` | sanctioned engine-root re-pin, delta verified before re-capture |

Sanctioned delta vs era 1, verified programmatically BEFORE this re-capture
(render diff vs the era-1 fixture) and guarded forever after by
`test_strata_strix.py::test_c07_strix_fixture_era_delta_is_only_the_engine_root_pair`:
of the 13 keys, exactly `exe` and `lib_dirs` moved, each only in its version
segment — `/opt/strata/components/engine/0.1.52-linux-x86_64-hip-halo/...` →
`0.1.54-linux-x86_64-hip-halo/...`. Every other key is byte-identical to
era 1. Authority: C07 AC3 / U9.4 (the 0.2.8 image ships only the 0.1.54
engine packages — a fixture pinning 0.1.52 is an active false pin pointing
the profile at a nonexistent path), cross-checked by
`containers/strata/tests/test_dockerfile.py::test_c07_engine_package_labels_are_one_fact_across_three_surfaces`.

Strengthened vs era 1 (the launcher's anti-drift requirement):
`test_c07_strix_fixture_ties_to_the_built_halo_root` pins this
fixture's exe/lib_dirs to the halo root the `containers/strata/Dockerfile`
itself COPYs and `test -x`-es — the fixture cannot silently drift back
toward 0.1.52, and a future re-pin reddens it before any render arm goes
stale. A future engine re-pin routes coord → test session (same rule as
era 1's PROVENANCE): re-verify the delta here, add era 3, never edit an era
file in place.

Test-author property: dev NEVER edits this directory; the fixture is
parsed-JSON capture (helm `toPrettyJson` key order is not the contract).
