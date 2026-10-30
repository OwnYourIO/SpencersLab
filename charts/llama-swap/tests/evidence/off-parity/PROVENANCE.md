# OFF-parity baseline — provenance

- File: `render-default.yaml` — byte-exact stdout of
  `helm template gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com`
- Current capture: 2026-10-30 on branch `cf-86-feat-more-strata-models` with the
  C03 flash-next-heretic family in the tree (uncommitted at capture; the fixture
  lands in the same commit as the C03 chart edit).
- Tooling: helm v3.16.4+g7877b45 (same generation as the run-1 goldens — see
  `evidence/flashnext-pre-chunk-baseline/PROVENANCE.md`)
- sha256: `0aa2241c2c5ea803fa978c6e462d16e29cde6d1459de92778787e7ed5a998f4a`
- Determinism: double-capture diffed clean (no embedded timestamps)
- Content sanity at capture: 6 rendered kinds, zero objects or strings matching
  "strata"
- Sanctioned delta vs the previous era, verified BEFORE this re-capture by
  `test_c01_off_render_changed_only_by_sanctioned_catalog_growth`: the models map
  gained exactly `qwen3.8-flash-next-heretic-q4` as an id-prefixed fail-fast
  echo, and `matrix.vars` gained exactly the pinned `fnher` letter with every
  set expansion unchanged. No other object, key, or string moved.

## Era chain

| era | captured | sha256 | reason |
| --- | --- | --- | --- |
| 1 | 2026-10-28 @ `44f5f80d2` (run-2 plan approved, dev waves not started) | `451c149ad70c7e48893e7c208d6f76eef95dc9ffbbe6f4f3d93dc7821af6d8aa` | original capture |
| 2 | 2026-10-30 cf-86 C03 (flash-next heretic family) | `0aa2241c2c5ea803fa978c6e462d16e29cde6d1459de92778787e7ed5a998f4a` | sanctioned catalog + matrix growth, structural arm green |

Re-baseline rule (cf-86 churn policy, TEST_SPEC §9.8): cf-86 grows the catalog
on purpose (C04 adds the 27B heretic family; C06 adds no llama.cpp catalog id),
and CR1.4/P5 renders every catalog id in every render, so the OFF render MUST
move at those landings. The test session re-captures here in the landing
chunk's test round — and ONLY while
`test_c01_off_render_changed_only_by_sanctioned_catalog_growth` is green. A red
there means the change is not confined catalog growth: it is a dev change to the
default-OFF render, and re-capturing would bake the leak into the baseline.

Purpose: r2-C01's byte-parity gate (plan "Commands" OFF-parity line; Q-C ruling —
default-OFF is seven DATA flags, so the bare render must not move by a byte
beyond the sanctioned catalog growth above).
`test_strata_off_parity.py` compares against this file.

Ownership: test-session property (single test-asset authority, run-2 DECISIONS
Conventions). Dev NEVER regenerates this file; a re-baseline (e.g. a deliberate
post-consolidation default-render change) is routed through the test session
and re-provenanced here in the same commit.
