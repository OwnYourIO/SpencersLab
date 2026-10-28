# OFF-parity baseline — provenance

- File: `render-default.yaml` — byte-exact stdout of
  `helm template gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com`
- Captured: 2026-10-28 at branch commit `44f5f80d2` (run-2 plan approved, dev waves NOT started; the chart tree equals merged run-1 = the plan's "today's baseline")
- Tooling: helm v3.16.4+g7877b45 (same generation as the run-1 goldens — see `evidence/flashnext-pre-chunk-baseline/PROVENANCE.md`)
- sha256: `451c149ad70c7e48893e7c208d6f76eef95dc9ffbbe6f4f3d93dc7821af6d8aa`
- Determinism: double-capture diffed clean (no embedded timestamps)
- Content sanity at capture: 6 rendered kinds, zero objects or strings matching "strata"

Purpose: r2-C01's byte-parity gate (plan "Commands" OFF-parity line; Q-C ruling —
default-OFF is seven DATA flags, so the bare render must not move by a byte).
`test_strata_off_parity.py` compares against this file; it must stay green
through every run-2 dev wave.

Ownership: test-session property (single test-asset authority, run-2 DECISIONS
Conventions). Dev NEVER regenerates this file; a re-baseline (e.g. a deliberate
post-consolidation default-render change) is routed through the test session
and re-provenanced here in the same commit.
