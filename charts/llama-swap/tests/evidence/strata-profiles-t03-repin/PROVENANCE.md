# strata-profile fixtures — T0/T3 re-pin era (primary era 2)

Captured 2026-11-01 by the post-first-boot tuning round from the default chart
`strata-profile` ConfigMap DATA (render_on path: `helm template
gpu-ai-llama-swap charts/llama-swap --set domain=test.example.com` + the seven
strata flags), branch `bug-strata-claim-venv-heal` at `3b6a200b8` + this
round's uncommitted chart edit, helm v3.16.4+g7877b45 (same binary version as
the era-1/2/3 strix captures, so renders are directly comparable).

- File: `strata-iq3_s.json` — sha256
  `ce1f66a8fe1d357bd1c5ed0d37d38dd779bc5c283372b622facc35f939d4ceb3`
- Determinism: double-capture diffed clean; re-render equals the file on disk.
- Encoding: `json.dumps(indent=2, sort_keys=True) + "\n"`, verified by
  reproducing the era-1 capture byte-for-byte before writing this one.

## Why the primary's era moves at all

The preservation arm is a whole-file deep-equal against the frozen era
(`test_strata_q4_rung.py::test_c06_existing_profiles_stay_byte_unchanged_iq3_s_keeps_92160`,
since renamed `…_caps_are_per_rung` when U14 moved the flagship's cap),
and it is deliberately blind to *why* a byte changed: any drift is red until a
human re-pins. This is that re-pin. The change is owner-ruled (DECISIONS U13,
2026-11-01: "go for T0 and T3") and RESEARCH R6 supplies the sourced authority:
bare `--prefill auto` on gfx12 Linux means 16,384-token chunks, while PR #3636
ran **this node class** at 32,768 (~2,519 tok/s @64–200K — the ladder rung-4
bar), the strix progression row scored `auto:32768` at +23 % @74K, and chunks
above 8,192 are bit-exact on gfx12 — a rate knob with no numerics cost.

## Era chain (primary)

| era | captured | sha256 | reason |
| --- | --- | --- | --- |
| 1 | 2026-10-29 @ `4f7126689` (pre-cf-86, clean tree) — see `../strata-profiles-pre-cf86/` | `a8de596cd95bcfd38e7e9c87acf4343c5758800a7ae9a8174202b8d3b8a4ce62` | original capture |
| 2 | 2026-11-01 cf-86 post-boot T0/T3 round (this directory) | `ce1f66a8fe1d357bd1c5ed0d37d38dd779bc5c283372b622facc35f939d4ceb3` | sanctioned prompt-chunk re-pin, delta verified before re-capture |
| 3 | 2026-11-01 U14 round — see `../strata-profiles-u14-repin/` | `f1a8d6c869e5936e3fb386f9b3e078e34e76116672d11fe3606afda175aed1c6` | sanctioned declared-cap re-pin (92160 → 110592); era 2 is append-only history |

The two steps are guarded as a chain by
`test_strata_strix.py::test_primary_fixture_era_chain_is_one_owner_ruled_flag_per_step`
(written as `test_t03_primary_fixture_era_delta_is_only_the_prefill_line` for
era 2 alone, widened when U14 added the second step).

## Sanctioned delta (verified programmatically BEFORE re-capture)

Changed top-level keys: exactly `["args"]`. Within `args`, one element moved:

```
- --prefill auto          →    --prefill auto:32768
```

No memory-envelope key moved AT THIS ERA (`--memory-limit-mib` stays 92160 here;
U14 moved it to 110592 in era 3 — see `../strata-profiles-u14-repin/`,
`--conversation-cache-mib` stays 32768×16 — the U12 pair law is untouched), no
path key moved, `env` stays `{}` at the profile layer (T0's
`STRATA_REQUEST_LINES=1` rides the llama-swap **model** env, which this ConfigMap
capture does not carry — the model-env arm lives in
`test_strata_config_schema.py`).

The `auto:N` form (not a bare `N`) is intentional: the engine silently re-picks
a smaller chunk when the prompt buffers do not fit (upstream #4164), so the cap
stays a ceiling that auto-shrink may lawfully reduce. The on-target startup line
`prompt chunk …` is the verification gate for this round (RESEARCH R6 T1).
