# strata-profile fixtures — C09 re-pin era (era 3)

Captured 2026-10-31 by the cf-86 agent-test session (C09-landing round)
from the default chart `strata-profile` ConfigMap DATA (render_on path:
`helm template gpu-ai-llama-swap charts/llama-swap --set
domain=test.example.com` + the seven strata flags), branch
`cf-86-feat-more-strata-models`, dirty tree carrying the C09 dev round
(0.2.9 flavor bump + engine 0.1.54→0.1.55 re-pin + ornith arena +
vendored carry; lands in the same commit as this fixture), helm
v3.16.4+g7877b45.

- File: `strata-strix-iq3_s.json` — sha256
  `b0a35bcd95ecfb0ecfa1a8be3ec6a5a4e5866ae7bfe4bd8cc71af0e1bc45d89d`
- Determinism: double-capture diffed clean.
- This directory carries ONLY the files whose frozen era moved. The primary
  `strata-iq3_s.json` needed NO era move (verified at capture: zero changed
  keys vs its pre-cf-86 capture) — its exe/lib_dirs ride the version-free
  claim-compiled pack root (`/models/strata/Strata/...`), and since C09 that
  checkout is refreshed by the driver's marker-keyed migration step, so an
  engine re-pin cannot touch the file without moving the path itself.

## Era chain

| era | captured | sha256 | reason |
| --- | --- | --- | --- |
| 1 | 2026-10-29 @ `4f7126689` (pre-cf-86, clean tree) — see `../strata-profiles-pre-cf86/` | `28d0ed389d250d1167f46c2975e33cc578990b9236fe8b4fa945904d4ce3a359` | original capture |
| 2 | 2026-10-31 cf-86 C07 (image lift, engine 0.1.52→0.1.54) — see `../strata-profiles-c07-repin/` | `547ba10d8eb8c2f81ffa1b1a7b1e8038ac68ee836d8f4765763ba9512fd2b68f` | sanctioned engine-root re-pin, delta verified before re-capture |
| 3 | 2026-10-31 cf-86 C09 (0.2.9 flavor bump, engine 0.1.54→0.1.55) | `b0a35bcd95ecfb0ecfa1a8be3ec6a5a4e5866ae7bfe4bd8cc71af0e1bc45d89d` | sanctioned engine-root re-pin, delta verified before re-capture |

Sanctioned delta vs era 2, verified programmatically BEFORE this re-capture
(render diff vs the era-2 fixture: of the 13 keys, exactly `exe` and
`lib_dirs` moved, each only in its version segment —
`/opt/strata/components/engine/0.1.54-linux-x86_64-hip-halo/...` →
`0.1.55-linux-x86_64-hip-halo/...`) and guarded forever after by
`test_strata_strix.py::test_c07_strix_fixture_era_delta_is_only_the_engine_root_pair`
(now a chain guard over both adjacent era steps). Every other key is
byte-identical to era 2 — and through era 2's own guard, to era 1.
Authority: C09 chunks/C09.md (0.2.9 image rides engine packages 0.1.55 —
the README pin ledger re-read the [C2] flavor digests live 2026-10-31 and
records the 0.1.55 exe rows; a fixture pinning 0.1.54 points the profile at
a nonexistent packaged dir), cross-checked by
`containers/strata/tests/test_dockerfile.py::test_c07_engine_package_labels_are_one_fact_across_four_surfaces`
and the strix-region arms in `test_strata_thin_init.py`. (§9.21 later widened
this cross-check arm to four surfaces — the chart README table joins as the
fourth, the FINAL3 §2 drift root cause — under the name
`test_c07_engine_package_labels_are_one_fact_across_four_surfaces`.)

Anchor law carried forward unchanged:
`test_c07_strix_fixture_ties_to_the_built_halo_root` pins this fixture's
exe/lib_dirs to the halo root the `containers/strata/Dockerfile` itself
COPYs and `test -x`-es (single label per era — it now reads
`0.1.55-linux-x86_64-hip-halo`). A future engine re-pin routes coord → test
session: re-verify the delta, add era 4, never edit an era file in place.

Test-author property: dev NEVER edits this directory; the fixture is
parsed-JSON capture (helm `toPrettyJson` key order is not the contract).
