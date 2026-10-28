# charts/strata — internal Strata engine pod (gpu-ai)

One privileged pod whose in-pod llama-swap supervisor owns `strata serve`
(from the `containers/strata` image). Cluster-internal by the Q4 ruling: no
ingress, no host — clients reach it through the gpu-ai llama-swap `peers:`
route (`services/gpu-ai/prod/values.yaml`), which rewrites the request model
to the inner ID on forward. Host prep and enablement commands live in the
operator runbook, `.agents/notes/strata-host-prep-gpu-ai.md`.

## Inner models

| ID | Engine | Device | Residency |
|---|---|---|---|
| `qwen3.8-flash-next-strata` | gfx1201 (`hip-rx9070` root) | R9700 via OCuLink | lazy, `ttl: 0` — permanent once warm |
| `qwen3.8-flash-next-strata-strix` | gfx1151 (`hip-halo` root) | 8060S iGPU | lazy, `ttl: 1800` — idle-released |

The inner `matrix` set `main: "(p | s)"` makes the two **alternatives**: the
solver evicts the resident arena before starting the other, so they are
never co-loadable (arenas are additive on the 128 GB node).

## Strix-alone fallback (`qwen3.8-flash-next-strata-strix`)

**When to use it:** the OCuLink link is dead or degraded, the R9700 is
absent, or an operator explicitly wants a secondary/spot session while the
dGPU path is unsuitable. Select it by model ID on the same surface as the
primary (`strata/qwen3.8-flash-next-strata-strix`, or the bare inner ID
while exactly one peer serves it and nothing outer shadows it). It is not
part of the outer llama-swap roster or matrix — peer models are invisible
to the outer solver, so choosing it is operator-discipline, like every
other Strata request against the RAM law.

**RAM — the 8060S shares LPDDR5X with everything else on the machine.** The
strix arena is page-locked in the same memory the OS, the llama.cpp trio's
page cache, and the conversation buffers live in. Budget it inside
MemAvailable or the #1715 failure class returns: on a 128 GB Strix Halo,
`--expert-cache auto` without a resident budget drove a global OOM (guide
Step 5 math). This is the reason the profile ships the explicit
`--expert-cache 24576 --resident-budget-gib 55` pair — and also why that
pair is unverified: the numbers have no upstream source, and the
`strata serve --profile … --plan --output json` gate (human step 3 of the
host-prep runbook) finalizes both before the first accepted request. Treat
them as hypotheses until that output is read on this node.

**Perf expectations — cite the epoch, not just the number.** The
STRIX_HALO History row of 1,265 prompt / 59.1 decode tok/s @8K is
engine-0.1.40-era (measured with no §5 env switches); the bundled engine is
0.1.52-era. The current-epoch §6 row (0.2.3 class, Windows) reads 685/783/749
prompt tok/s @4K/8K/64K — same order of magnitude, different machine class.
The §5 fast-config is KL-gated: decoded rounds differ from the primary
profile's output, so never diff the two token-for-token; compare on
`strata bench run` instead.

**Startup log gates.** `STRATA_HC_UPMIX=1` ships in the eight-set despite
its #2706 history — on 0.2.2 it was a split-mode hazard, and §5 keeps it
for single-device use. Check the startup log for UPMix anomalies and flip
that one env key to `"0"` in `config.engineProfileStrix.env` if the hazard
reproduces. Look for the gfx1151 hipBLASLt tuning-table line
(`… gfx1151 … 100401`) and the expert-cache sizing lines — they are the
same evidence set the `--plan` gate reviews.

**Device targeting.** `rocrVisibleDevicesByModel` pins the fallback to the
chip (default `"1"`, PR #3636's dGPU-first enumeration); on a chip-only
node the chip is index 0 — the same on-target `rocminfo` gate that
retargets the primary covers both keys. Unset values inherit
`rocrVisibleDevices`.

**Unloading.** Unlike the primary's pinned residency, the fallback
defaults to `ttl: 1800` — the LPDDR5X arena comes back after 30 quiet
minutes. Manual escape is the same: `POST /api/models/unload/qwen3.8-flash-next-strata-strix`
on the inner instance, bounded by `unloadTimeout: 180`.
