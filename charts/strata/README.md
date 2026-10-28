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

## Validation ladder (post-sync, operator-consented, one-attempt protocol)

Enablement gates 1–6 in `.agents/notes/strata-host-prep-gpu-ai.md` §3 come
first; this ladder runs after the first request has loaded the engine (that
file's step 3.7). The protocol is one attempt per consented session — the
posture inherited from the flash-next OOM ticket (plan Deferred) — and every
fix it discovers returns through a PR to this repo; ArgoCD applies
everything, no step below runs `kubectl apply`.

**1 — Devices and ulimits in the pod.**

```
kubectl -n default exec deploy/gpu-ai-strata -- ls -l /dev/kfd /dev/dri
kubectl -n default exec deploy/gpu-ai-strata -- sh -c 'ulimit -l'
```

`ulimit -l` must read `unlimited` (the §1.5 host drop-in half). The nofile
proof belongs to the engine child, not a fresh exec shell:
`cat /proc/<engine-pid>/limits` → NoFile soft `524288` (runbook §5). Device
targeting proof: the `--plan` JSON (or, if the image ships `rocminfo`, that
under `ROCR_VISIBLE_DEVICES`) must show exactly the one device each profile
bound — gfx1201 for the primary, the 8060S for strix.

**2 — Startup-log fingerprints** (`kubectl -n default logs
deploy/gpu-ai-strata`; `logToStdout: both` is what makes this evidence
trail exist): the expert-cache sizing lines and memory-guard source line
(the `--plan` gate's numbers meeting reality), `nice +5`, and the hipBLASLt
line — `hipBLASLt tuning enabled (… gfx1151 … 100401)` expected on a strix
load; its **absence expected on gfx1201** — no 1201 table exists for
100401 (RESEARCH §6), no action, do not treat silence as failure. The four
bad signs to stop on: LOW VRAM free, health progress unchanged for 60 s,
registration FAILED, oom-kill (host `dmesg`). Strix additionally runs the
#2706 `STRATA_HC_UPMIX` check above.

**3 — Prompt runs 4K/16K/64K through the OUTER surface**
(`llama.<domain>`, e.g. `POST https://llama.spencerslab.com/v1/chat/completions`
with `"model": "qwen3.8-flash-next-strata"`). The authoritative tok/s is
the engine-side number in the pod log — client wall-clock adds two proxy
hops and measures routing, not inference.

**4 — Bench acceptance, `standard-v1`.** Run the PR #3636 protocol
(`strata-qwen38-thinking-v1-draft.1` class) against the inner supervisor —
remote `--url` requires HTTPS, so the loopback form runs in-pod:

```
kubectl -n default exec deploy/gpu-ai-strata -- \
  /opt/strata/terminal/bin/strata bench run --url http://127.0.0.1:8080 \
  --suite standard-v1 --optional-concurrency --track custom
```

Acceptance gate: within **~10%** of RESEARCH §5's **one-at-a-time** column
(batch numbers are not the bar — that posture was rejected, Q2): decode ≈80
tok/s @64K; short 570-token prompts 429–443 tok/s with the CPU share vs 224
control; 64K/128K/200K prompt ≈2,519 tok/s. Provenance: single machine,
2026-10-21 (the fork's `bench/results/2026-10-21-…` dir, RESEARCH §5) — the
PR machine had 124 GiB vs our 128 GB (R3), so drift is expected; the gate
applies to OUR reproduction of the same posture, and where the WeKan card's
table differs from these cited figures the card is superseded.

**5 — Conversation-cache reuse.** Send the same ~30K-token conversation
twice; the second pass must land materially faster (the
`--conversation-cache-mib 24576` × 16-slot budget working, RESEARCH §2/§5 —
not `--prompt-cache`, which is not shipped: #4206 makes it a no-op at the
`--prefill 32768` edge).

**6 — Anthropic smoke + engine-key enforcement.** `POST
/v1/messages` through `llama.<domain>` — routing and SSE are confirmed to
pass the peers hop (RESEARCH §3; the ingress chain already stamps
responseHeaderTimeout 0), so this checks the Strata side, not the plumbing.
It also answers the question C02 parked: the inner hop injects no
Authorization (`apiKeys: []`, peers carries no key material) while the
engine got `STRATA_API_KEY` from the secret. If this first request 401s at
the engine, the documented flip is run-config `api_key: "none"` (RESEARCH
§2): add it under `config.engineProfile` — the profile ConfigMap renders
that block verbatim — re-PR, re-sync. Config-vs-env precedence for the key
is exactly what this rung measures; if `"none"` in the run-config does not
override the env, escalate to coord instead of improvising an env-layer
removal.

**7 — 128K and 200K needle runs.** `--max-context 262144` admits them;
watch host `dmesg` and `free -g` throughout and stop on any bad sign from
rung 2 — the long prompts are where arena + conversation-cache + page-cache
pressure compounds.

**8 — Shared-claim capacity re-check.** Before each session: the
`/models/strata` staging budget (~135–160 GB, GGUF pair + pack + MTP) and
the #1250 page-cache note live in the runbook §2 — the claim doubles as the
IQ3_S page-cache floor, so a slow first pin may be cold cache, not a broken
arena.

## Provenance and cross-links

- Source of every number and gate above/beside: feature folder
  `.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap/` — plan of
  record, `DECISIONS.md`, `RESEARCH.md` §1–§7 (section cites inline),
  `chunks/C04.md`; WeKan card #77. Recipe/bench provenance: PR #3636 fork
  `jiayeZhu/Strata@bench-strix-halo-r9700-022`, bench epoch 2026-10-21.
- Operator runbook (host prep, enablement gates 1–6, RAM law, R4 flip
  recipe, deferred modes, resolved-question ledger Q/O/R):
  `.agents/notes/strata-host-prep-gpu-ai.md`.
- Image pins and upgrades: the tag→digest ledger in
  `containers/strata/README.md` is the bump record. Cadence per the
  coordination ruling: **manual** — built-in renovate extraction will keep
  firing interim PRs with cross-flavor candidate bleed on the shared
  depName; the human closes/ignores those until the flavor-scoping ticket
  (STATE.json `deferred`) and bumps only against the ledger + re-bench
  (plan human step 5).
