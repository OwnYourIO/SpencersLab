# charts/llama-swap — llama.cpp surface + the internal Strata engine pod

Renders llama-swap supervising the llama.cpp model roster on the gpu boxes.
On gpu-ai the SAME Application can own a second app-template controller —
the internal Strata engine pod (cf-77): one privileged pod whose in-pod
llama-swap supervisor owns `strata serve` (from the `containers/strata`
image) as a supervised child. It is default-OFF and cluster-internal by the
Q4 ruling: no ingress, no host — clients reach it through the gpu-ai
llama-swap `peers:` route (`services/gpu-ai/prod/values.yaml`), which
rewrites the request model to the inner ID on forward. Host prep and
enablement commands live in the operator runbook,
`.agents/notes/strata-host-prep-gpu-ai.md`.

## Strata controller

### Enable flags — seven keys, flipped together

`app-template.controllers.strata.enabled` + `app-template.service.strata.enabled`
+ `app-template.persistence.{strata-config,strata-profile,strata-kfd,strata-dri,strata-shm}.enabled`
— seven keys, chart defaults all `false`, flipped ON together from the gpu-ai
service block. Partial sets fail by design: advancedMounts naming a disabled
controller hard-fails the render ("No enabled controller found with
identifier 'strata'") and the template-side companion guard catches the
reverse gap (controller ON, persistence OFF), so no subset can deploy a
headless or configless pod. With all seven OFF the default render contains
no strata objects at all — byte-identical to a strata-less tree.

### Consolidated identity

The controller renders Deployment + Service `gpu-ai-llama-swap-strata`
(app-template fullname plus the controller key — read it from NOTES, never
guess it). ClusterIP only, and no ingress entry beside it or in the service
values: the deliberate trio-rule deviation of the Q4 internal-only ruling —
a host of its own would publish the pod the peers hop exists to keep
private. The peers proxy is `http://gpu-ai-llama-swap-strata.default.svc.cluster.local:8080`
with NO `/v1` suffix — the request path appends verbatim (RESEARCH §3).
Pod shape: privileged + hostPath `/dev/kfd` + `/dev/dri`, `strategy:
Recreate` (a RollingUpdate overlap would double-pin the arena — the #2257
class), grace 420 s > `unloadTimeout` 180 s + drain 30 s, shm 2 GiB.
Memory is a PAIRED cap, not the DOCKER.md default of none: the pod cgroup and
the engine's `--memory-limit-mib` move as one unit (#1601's informed-limit
posture) — the 2026-10-29 node OOM harvest ended the uncapped-pinning era on a
node the trio also lives on. The pair is PER-RUNG inside the one strata pod:
`limits.memory 96Gi` + `--memory-limit-mib 92160` is the IQ3_S / IQ3_XXS
envelope (arena ~50 GiB), while the `qwen3.8-flash-next-strata-q4` arena
(unsloth UD-Q4_K_XL) raises the pod to `100Gi` with its own `95232` — 71.7 GiB
pinned experts + 8 GiB conversation cache + ~13 GiB worst-case KV — and the
smaller rungs keep their 92160 cap inside the same cgroup. Conversation cache:
32 GiB × 16 slots on the IQ3-class rungs (IQ3_S parks ~3.3 GiB per full 256k
conversation); the Q4 rung trims it to 8 GiB × 16 and round-trips deep
conversations through engine session files under `/models/strata/sessions`
instead of holding them parked in RAM.

### Keyless posture

Engine and inner supervisor run unauthenticated in-cluster, mirroring the
outer llama-swap's own `apiKeys: []`: both run-config profiles ship
`api_key: "none"` and the inner config carries `apiKeys: []`. The engine
binds 127.0.0.1 via serve's `--host`, so the supervisor proxy is its only
client. Because llama-swap passes the client `Host` header through, the
engine's DNS-rebinding guard needs to know the Service name the peers hop
delivers — each model's env carries `STRATA_ALLOWED_HOSTS` with the three
Service-DNS shapes (ports ignored; localhost always passes). This is the
documented keyless counterpart of setting an api_key. No secret exists for
this workload: nothing to create in any secret store, nothing injected into
the pod, no Authorization header anywhere in the chain.

### Image contract (interface freeze)

| Surface | Value |
|---|---|
| serve CLI entry (what the llama-swap `cmd` execs) | `/opt/strata/terminal/bin/strata` |
| Engine exe — primary (R9700 / gfx120x) | `/opt/strata/components/engine/0.1.52-linux-x86_64-hip-rx9070/strata` |
| Engine exe — fallback (Strix / gfx1151) | `/opt/strata/components/engine/0.1.52-linux-x86_64-hip-halo/strata` |
| Engine root layout | both roots live under `/opt/strata/components/engine/<label>/` as **distinct dirs** (same-named binaries per flavor — never merge them) |

- The engine binaries are referenced **from each profile's run-config `exe`
  key, NOT from the `cmd`** — `serve` picks its engine from the run-config
  (RESEARCH §2), so switching flavor = switching profile file, not image.
- The `cmd` wraps serve in `ulimit -n 524288; exec …`: no 0.2.x release
  self-raises the nofile soft limit (PR #2399 open, #2398 closed unmerged)
  and HIP pinned-memory creation fails at ~1k FDs (RESEARCH §2).
- `/usr/local/bin/strata` on PATH is the base image's shim into the
  terminal; the explicit `/opt/strata/terminal/bin/strata` path keeps this
  contract standing across any upstream wrapper change.
- **`strata update` must never run inside the container** — the engine
  lives in the image and an in-place update silently invalidates the pin
  ledger below. Upgrading is a commit: change both FROM tags + the ledger,
  CI rebuilds.
- Nothing secret, no model weights, no prepared packs are baked: weights
  mount at runtime from the shared llama-swap claim under `/models/strata/`.

### Bump cadence — manual, against the tag→digest ledger

The tag→digest ledger is the table in `containers/strata/README.md` and is
the bump record; #3421 (the silent-engine-swap class — mutable GHCR tags
rebuilt in place under everyone's feet) is why each flavor tag carries a
recorded digest instead of trust. Cadence per the coordination ruling:
**manual** — built-in renovate extraction keeps firing interim PRs with
cross-flavor candidate bleed on the shared depName; the human closes/ignores
those until the flavor-scoping ticket (STATE.json `deferred`) lands, and
bumps only against the ledger + a re-bench (plan human step 5). Releases and
images are not in lockstep (0.2.4–0.2.6 shipped releases with NO images) —
the GHCR tag list is the only truth. Bump procedure: inspect the new tag's
digest → record tag+digest as a pair → one commit changes both FROM tags →
on-target `strata serve --plan` re-check (runbook §3.4) → re-bench.

### Inner models

| ID | Engine | Device | Residency |
|---|---|---|---|
| `qwen3.8-flash-next-strata` | checkout-compiled gfx1201 engine | R9700 via OCuLink | lazy, `ttl: 3600` — time-shared (unloads 1h idle; set `ttl: 0` to pin for dedicated windows) |
| `qwen3.8-flash-next-strata-strix` | gfx1151 (`hip-halo` root) | 8060S iGPU | lazy, `ttl: 1800` — idle-released |

The inner `matrix` set `main: "(p | s)"` makes the two **alternatives**: the
solver evicts the resident arena before starting the other, so they are
never co-loadable (arenas are additive on the 128 GB node).

### Strix-alone fallback (`qwen3.8-flash-next-strata-strix`)

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
that one env key to `"0"` in `strata.config.engineProfileStrix.env` if the
hazard reproduces. Look for the gfx1151 hipBLASLt tuning-table line
(`… gfx1151 … 100401`) and the expert-cache sizing lines — they are the
same evidence set the `--plan` gate reviews.

**Device targeting.** `strata.rocrVisibleDevicesByModel` pins the fallback
to the chip (default `"1"`, PR #3636's dGPU-first enumeration); on a
chip-only node the chip is index 0 — the same on-target `rocminfo` gate
that retargets the primary covers both keys. Unset values inherit
`strata.rocrVisibleDevices`.

**Unloading.** Unlike the primary's pinned residency, the fallback
defaults to `ttl: 1800` — the LPDDR5X arena comes back after 30 quiet
minutes. Manual escape is the same: `POST /api/models/unload/qwen3.8-flash-next-strata-strix`
on the inner instance, bounded by `unloadTimeout: 180`.

### Validation ladder (post-sync, operator-consented, one-attempt protocol)

Enablement gates §3.1–§3.6 in `.agents/notes/strata-host-prep-gpu-ai.md`
come first; this ladder runs from the first request that has loaded the
engine (that file's step 3.6) onward. The protocol is one attempt per
consented session — the posture inherited from the flash-next OOM ticket
(plan Deferred) — and every fix it discovers returns through a PR to this
repo; ArgoCD applies everything, no step below runs `kubectl apply`.

**1 — Devices and ulimits in the pod.**

```
kubectl -n default exec deploy/gpu-ai-llama-swap-strata -- ls -l /dev/kfd /dev/dri
kubectl -n default exec deploy/gpu-ai-llama-swap-strata -- sh -c 'ulimit -l'
```

`ulimit -l` must read `unlimited` (the §1.5 host drop-in half). The nofile
proof belongs to the engine child, not a fresh exec shell:
`cat /proc/<engine-pid>/limits` → NoFile soft `524288` (runbook §5). Device
targeting proof: the `--plan` JSON (or, if the image ships `rocminfo`, that
under `ROCR_VISIBLE_DEVICES`) must show exactly the one device each profile
bound — gfx1201 for the primary, the 8060S for strix.

**2 — Startup-log fingerprints** (`kubectl -n default logs
deploy/gpu-ai-llama-swap-strata`; `logToStdout: both` is what makes this
evidence trail exist): the expert-cache sizing lines and memory-guard
source line (the `--plan` gate's numbers meeting reality), `nice +5`, and
the hipBLASLt line — `hipBLASLt tuning enabled (… gfx1151 … 100401)`
expected on a strix load; its **absence expected on gfx1201** — no 1201
table exists for 100401 (RESEARCH §6), no action, do not treat silence as
failure. The four bad signs to stop on: LOW VRAM free, health progress
unchanged for 60 s, registration FAILED, oom-kill (host `dmesg`). Strix
additionally runs the #2706 `STRATA_HC_UPMIX` check above.

**3 — Prompt runs 4K/16K/64K through the OUTER surface**
(`llama.<domain>`, e.g. `POST https://llama.spencerslab.com/v1/chat/completions`
with `"model": "qwen3.8-flash-next-strata"`). The authoritative tok/s is
the engine-side number in the pod log — client wall-clock adds two proxy
hops and measures routing, not inference.

**4 — Bench acceptance, `standard-v1`.** Run the PR #3636 protocol
(`strata-qwen38-thinking-v1-draft.1` class) against the inner supervisor —
remote `--url` requires HTTPS, so the loopback form runs in-pod:

```
kubectl -n default exec deploy/gpu-ai-llama-swap-strata -- \
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

**6 — Anthropic smoke + keyless posture confirmation.** `POST
/v1/messages` through `llama.<domain>` — routing and SSE are confirmed to
pass the peers hop (RESEARCH §3; the ingress chain already stamps
responseHeaderTimeout 0), so this checks the Strata side, not the plumbing.
The same request answers the parked precedence question as a CHECK, not a
secret: the inner hop injects no Authorization (`apiKeys: []`, peers carries
no key material) and the engine ships `api_key: "none"` in the run-config,
so an unauthenticated round trip must succeed end to end. A 401 at the
engine means the shipped key posture drifted — escalate to coord instead of
improvising an env-layer removal.

**7 — 128K and 200K needle runs.** `--max-context 262144` admits them;
watch host `dmesg` and `free -g` throughout and stop on any bad sign from
rung 2 — the long prompts are where arena + conversation-cache + page-cache
pressure compounds.

**8 — Shared-claim capacity re-check.** Before each session: the
`/models/strata` staging budget (~135–160 GB, GGUF pair + pack + MTP) and
the #1250 page-cache note live in the runbook §2 — the claim doubles as the
IQ3_S page-cache floor, so a slow first pin may be cold cache, not a broken
arena.

### Deferred modes and escalation record (not built; facts so nobody re-derives)

- **Split mode (8060S + R9700)** — deferred (STATE.json; plan Deferred).
  Flags: `--gpu-roles`, `--layer-split auto`; STRIX_HALO §5 role assignment
  (discrete card = Main, chip = Off); needs ≥0.2.1; `STRATA_HC_UPMIX` off
  per #2706 in that mode. The fork carries a working `split-0.2.2.json`
  config (RESEARCH §5). Trigger to reopen: short-prompt-dominated traffic —
  the guide's split win is only ≤4K uncached.
- **2B source-build container path** — escalation only if the bundled image
  fails on-target (RESEARCH §6; `containers/strata/README.md`, Escalation):
  `therock-dist-linux-gfx120X-all-7.14.1.tar.gz` exists on repo.amd.com
  (2.336 GB, no published sha — record the digest on download); against
  TheRock 7.14.1 the repo ships no gfx1201 hipBLASLt tuning table for
  100401, so a source build runs plain-dense prompt matmuls or self-tunes
  via `tools/hip/tune_hipblaslt.cpp`; PR #3636 ran gfx1201 on
  7.14.1/hipBLASLt 1.4.1 fine without a table — table ABSENCE on this arch
  is expected, no action (ladder rung 2).

### Provenance and cross-links

- Source of every number and gate above/beside: cf-77 feature folders
  `.agents/plans/2026/2026-10-cf-77-feat-strata-llama-swap/` (plan of
  record, `DECISIONS.md`, `RESEARCH.md` §1–§7 — section cites inline,
  `chunks/C04.md`) and `2026/2026-10-cf-77-feat-strata-llama-swap-1/`
  (keyless + in-chart-consolidation rulings); WeKan card #77. Recipe/bench
  provenance: PR #3636 fork `jiayeZhu/Strata@bench-strix-halo-r9700-022`,
  bench epoch 2026-10-21.
- Operator runbook (host prep, enablement gates, RAM law, R4 flip recipe,
  deferred modes, resolved-question ledger):
  `.agents/notes/strata-host-prep-gpu-ai.md`.
- Image pins, interface freeze, and upgrades: `containers/strata/README.md`
  — the tag→digest ledger and the full contract notes.
