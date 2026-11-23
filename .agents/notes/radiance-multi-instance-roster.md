# Radiance multi-instance roster — the five claimants on the `amd.com/gpu-r9700` pool (gpu-ai)

> **Posture (read first).** This is the ticket `2026-11-feat-radiance-multi-instance`'s
> **single prose authority** for the gpu-ai inference roster: who holds claims on the
> `amd.com/gpu-r9700` pool, what each lane serves, what may run together, and how the
> board routes to all of it. The shipped table below was derived from
> `services/gpu-ai/prod/values.yaml` on 2026-11-22, and `tests/notes/radiance-roster.sh`
> T2 re-derives every claim count and replicas value from that tree at every run — a
> note that drifts from the tree is red by construction, so this document is machine-
> tied to the values file, not to anyone's memory. Sibling docs: the fn acceptance
> runbook (`.agents/notes/radiance-on-target-acceptance.md`), the q27 boot console
> (`.agents/notes/radiance-q27-boot.md`), the second-card plan
> (`.agents/notes/radiance-second-gpu-tp2.md`).
>
> Pool-name law (DECISIONS §Conventions): the only live claim name is
> `amd.com/gpu-r9700` (product field `r9700`, renamed 2026-11-22 per D21). The retired
> `-1`-suffixed pool name is never spelled contiguously in this note — the live name is
> a prefix of the retired one, so any contiguous literal would trip the C01 zero-stale
> sweep on this file itself.

## The roster — five claimants, one pool of two

`radiance`, `radiance-q27`, `radiance-flash-tp1`, `radiance-q27-tp2` (four releases off
the one `charts/radiance` chart, per the roster `chart:` override) plus the claimed,
parked `strata` lane inside the `gpu-ai-llama-swap` Application (C04/D17 made strata a
real claimant; OQ-K parked it at zero replicas in the same wave). Values below
are the shipped renders; the served id rides the `RADIANCE_SERVED_ID` env entry (the
D43 shape — the compose wrapper, not an args list, carries it to the engine).

| Claimant (roster key) | Claim | Replicas | Served id (`RADIANCE_SERVED_ID`) | Memory req / limit | Application · Service | peers hop | UP at what cost |
|---|---|---|---|---|---|---|---|
| `radiance` | 2 | 1 | qwen3.8-flash-next-radiance | 110Gi / 110Gi (held, cf-144 P11) | `gpu-ai-radiance` | http://gpu-ai-radiance.default.svc.cluster.local:8000 | THE live steady state — UP the pair holds BOTH cards, so every other lane Pends while it is UP |
| `radiance-q27` | 1 | 0 | qwen3.8-27b-radiance | 24Gi / 24Gi (cf-144 P05 pin) | `gpu-ai-radiance-q27` | http://gpu-ai-radiance-q27.default.svc.cluster.local:8000 | pod-swap lane: fn DOWN first (2+1=3 over a pool of 2), then UP; 502-loud while parked |
| `radiance-flash-tp1` | 1 | 0 | qwen3.8-flash-next-radiance-tp1 | 110Gi / 110Gi (OQ-F held class) | `gpu-ai-radiance-flash-tp1` | http://gpu-ai-radiance-flash-tp1.default.svc.cluster.local:8000 | fn DOWN first (2+1=3); claim-wise it can stack with claimed strata (2 of 2) but host RAM blocks that co-boot at the held values |
| `radiance-q27-tp2` | 2 | 0 | qwen3.8-27b-radiance-tp2 | 24Gi / 24Gi (OQ-G held class) | `gpu-ai-radiance-q27-tp2` | http://gpu-ai-radiance-q27-tp2.default.svc.cluster.local:8000 | takes BOTH cards alone (c2) — everything else must be DOWN. [2026-11-23 C02, RESEARCH V5/S10 — the second-card cost, corrected]: the host-RAM pin is UNCHANGED (7.89 GiB pinned in BOTH the TP1 and TP2 rows — the "zero extra VRAM" reading is TRUE in that sense; the node fit is unchanged) but the card-VRAM pool grows ~3x (12.48 → 40.08 GiB; ~199k → ~663,600 tokens at the ~64 KiB effective cost) — the second card buys KV headroom and speed at a wiring overhead (1.67x, ~16% short of 2x), not a host-RAM story |
| `strata` | 1 | 0 | — (llama.cpp provider ids, not a radiance serve) | 110Gi requests = 110Gi limits (memory mirrored under D17; Burstable overall — cpu requests 8, no cpu limit, per the D44 correction) | inside `gpu-ai-llama-swap`; own Deployment + Service `gpu-ai-llama-swap-strata` | http://gpu-ai-llama-swap-strata.default.svc.cluster.local:8080 | MoE lane: fn 2 + strata 1 = 3 over a pool of 2, so fn must be DOWN first (the bring-up order below); parked is not deleted — the `gpu-ai-strata` provider stays registered |

Peer URLs are the Application-name Service routes without a `/v1` suffix (request paths
append verbatim); the public chain stays `https://llama.spencerslab.com/v1` through the
outer llama-swap only. The fn lane's keyless posture (cf-143 D8) is every radiance
lane's posture — no key, no ExternalSecret, no ingress on any lane.

## Steady-state claim table (the single authority for combination questions)

Labels below name the roster rows above. The overlay's strata-region comment in
`services/gpu-ai/prod/values.yaml` keeps the short claim-count mirror C04 landed (D44
completed its two strata combination rows there); this table is the full prose
authority, and the two cross-cite. Plan of record: the same seven rows under
"Steady-state claim table after (b)" in the ticket's plan file.

| UP set | claims on 2 | verdict |
|---|---|---|
| fn TP2 alone | 2 | YES — the approved live steady state |
| fn + any other lane | >2 | NO — every other lane Pends while fn is UP |
| Strata alone | 1 | YES — lands on the lowest-KFD-NodeId card (RESEARCH R-Q1 determinism class, receipt-pending) |
| flash TP1 + Strata | 2 | YES claim-wise — claim-1 lanes stack in NodeId order and the lower card goes to whoever is admitted first (scheduling order, NEVER model identity); RAM-wise NO at held values (110 + 110 + ~5.3 > 125.08) |
| q27 + Strata | 2 | pool-wise YES; RAM-wise NO at held values (110 + 24 + ~5.3 > 125.08) — never co-boot |
| flash TP1 + q27 TP2 (+ Strata) | >2 | NO — 1 + 2 already exceeds the pool |
| q27 TP2 alone | 2 | YES — takes both cards |

The RAM column of reality: the node owns 125.08 GiB allocatable and every held 110-class
lane plus strata's mirrored 110 requests is more than the node, so "schedulable" on
claims alone never means "co-boots" — the boot print adjudicates held numbers
(cf-143 D28(6)/D30(2)); OQ-F/OQ-G values move only by a fresh owner ruling. The claim
decides WHO may be scheduled beside a lane; it never pins which card a pod's process
enumerates (the `/dev/dri` hostPath half sits outside plugin accounting — container-leg
law, C04/D17).

## MoE bring-up and restore (owner scale acts only)

MoE bring-up is one owner scale act in order: scale fn → 0, wait for the fn pod to be gone, then scale strata → 1 — the reverse restores fn, both directions ruled by the 2026-11-22 parked posture (OQ-K). Any other order boots a Pending pair: fn's
claim pair (2) plus strata's claim (1) is 3 over a pool of 2, and even claim-free the
host RAM of fn's held 110 beside strata's mirrored 110 exceeds the node. These are
OWNER scale moves (the Q10 law: the strata dance is never GitOps-ized); with git at
`replicas: 0` for strata, a hand scale sticks until that Application's next manual sync
— scale and sync timing stay the owner's call, sequenced per the runbook's restore
step.

## Board and runner routing as shipped (the routing wave, 2026-11-22)

- The hourly pipeline runner literal is `gpu-ai/qwen3.8-flash-next-radiance`. Its full
  ruling chain, so nobody re-picks a model: cf-106 OQ-14 raised the runner-model
  question, the 2026-11-09 owner ruling set `gpu-ai/qwen3.8-flash-next-strata-q4`
  ("moves only by a fresh user ruling"), and the 2026-11-22 owner ruling D16 moved it
  to radiance. Consequence accepted at ruling time: the fn lane is now the scheduled
  runner's single point of failure — fn down also stalls the hourly loop.
- The `Qwen Dense + Local` card routes to `gpu-ai/qwen3.8-27b-radiance` (D20,
  superseding the kept-27b-q4 row) — an explicit card choice, with the accepted
  consequence recorded at ruling time: that lane rests at `replicas: 0`, so the
  explicit route answers the 502 peer-proxy error until someone scales it up.
- The `10+` background leg stays `gpu-ai/qwen3.8-27b-q4` — that is the llama.cpp
  outer-swap lane inside llama-swap, not a radiance release; this ticket's surface leg
  (surface.sh) REQUIRES it and it is not part of the D20 row.
- Catalog classes per D19's full-trio registration, on the higher-wins ladder: fn
  9/5/1, q27 8/4/0, flash-TP1 7/3/2, q27-TP2 6/2/1 — each pod schedules its own queue,
  so the ranks are per-lane class identity, never a cross-pod order.
- **The never-default law.** Three of the five claimants rest at `replicas: 0`, and a
  parked lane's peers hop answers a loud 502 peer-proxy error (llama-swap neither
  health-checks nor hides peers — cf-143 D57). A resting lane is never a default and
  nothing ever fails over into one: 502 means the lane is parked and you asked it
  explicitly — the refusal is the design, not an outage.

## Where lane facts live (the convention reconciliation, ask 4)

`custom-values/` stays the repo's SECRETS-ONLY carrier — `OVERRIDE_VIA_CUSTOM_VALUES`
keeps exactly that meaning and no radiance lane has a bitwardenIds leg (the keyless
cf-143 D8 posture has no secret to carry). The "generic shell + exact settings per
instance" pattern is carried instead by the per-release service blocks in
`services/gpu-ai/prod/values.yaml`: the appset `index $.Values $appName` channel makes
each block the per-instance DATA home — pack, served env specifics, memory, claim,
replicas. The chart is MECHANISM plus FORM: image pin and digest ledger, probe law,
Recreate + grace, securityContext, the shared models claim, the Service shape, and both
script FORMs on the one mounted ConfigMap carrier (D35 established the fetch FORM, D43
added the serve-compose FORM). The cf-143/cf-144 "one chart-value home" (cf-143 D15)
single-source law is therefore DELIBERATELY superseded for `charts/radiance` — recorded
with cross-cites in this ticket's `DECISIONS.md` §Conventions (carrier law) and here;
the claims cross the appset→Application chain as POSITIVE ADD/UPDATE only (cf-143 D26).

Consequence of the D43 shape, for anyone reading a running pod: `kubectl describe pod`
and the Argo diff show the wrapper invocation plus the env list — never the final
argv — so the render is not the receipt. The engine's startup print echoes the
COMPOSED argv (the wrapper booted on the lane env); that echo is the boot receipt of
what the engine actually received, and the suite law makes an extra or missing env
entry as red as a drifted value.

## Per-lane first-boot budget law

Every held number above is adjudicated by ITS boot print, not by this table
(cf-143 D28(6)/D30(2)): the first boot of any parked lane captures the printed budget
lines, pins the held value against them, and UP moves only by a fresh owner ruling —
the same discipline cf-144's post-boot DOWN re-pin leg carries for fn (cf-144 P11).
The step-by-step capture lives in the runbook's per-lane acceptance step
(`.agents/notes/radiance-on-target-acceptance.md`, Step 12).

[2026-11-23 C06] The `32 GB dGPU` patched-table ledger tag in
`charts/amd-gpu/values.yaml` was deliberately NOT restored with this wave — cf-143's
review judged it non-required and D32(iii) authorized the drop; the sizing facts live
in `.agents/notes/radiance-host-tuning.md` (`mem_info_vram_total` 34208743424 B).
