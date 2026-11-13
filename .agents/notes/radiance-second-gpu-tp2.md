# Radiance second-GPU (TP2) expansion — the follow-up card's body

> **Provenance.** cf-143 (`2026-11-11-feat-cf-143-feat-radiance-replaces-strata`,
> card AD-143 "Implement Radiance instead of Strata"), chunk C03, owner ruling
> Q6: this doc feeds follow-up card #1, titled exactly **"Radiance second-GPU
> (TP2) expansion"** — the card body and this file are the same artifact, so
> they cannot drift apart. Every number here resolves to a heading of that
> folder's `RESEARCH.md` (`RQ<n>`, `§R6`, `R6-Q<n>-<row>`, `OQ<n>` citations,
> the T2 resolver's forms). Nothing comes from the card's deployment guide —
> the guide's stale items are called out as stale, do not use.
> Status: **expansion instructions, not shipped config.** Once cf-143 lands
> the repo runs Flash-Next tensor-parallel 1 on one R9700; this doc is what
> changes when a second R9700 lands. The TP2 ticket re-derives the plan.
> Operator law: the cluster's only input is git (ArgoCD applies everything);
> every command below is read-only (`cat`, `rocminfo`, `lspci`, `kubectl get`)
> or owner-executed prose — no step here is a repo-side cluster mutation.

## 1. What TP2 buys, in one paragraph

The single-card build this run ships (cf-143) serves the Flash-Next fn lane
TP1 on one R9700 with `--kv-resident 32768` (the QSA KV group's host mirror),
because the card cannot hold both the weights and 8×200K-token KV. A second
R9700 doubles the tensor-parallel width — the engine recipe drops to a
per-rank host pool of 12288 MiB, the idle-session host tier becomes
affordable again, prefill funds its card↔host staging from two ranks
instead of one — and it
frees a whole card for a second lane: the retired vLLM 27B lane can return
as radiance q27. It also dissolves the radiance-vs-strata one-card
contention the owner ruled to merely observe (Q11). Sources: RESEARCH RQ4
(second-GPU expansion), the Serving envelope fn-TP2 row, and §R6 for the
scheduler side.

## 2. Hardware path — the switch fabric, and what the guide's numbers are

The lab's OCuLink port is a closed-ended x4 slot. Two physical paths put a
second R9700 on it (RQ4):

- **A PEX88048/88096 external Gen4 switch** in that slot; the switch's
  downstream ports carry both cards. (The family split is community-
  corroborated: 88XXX chips are Gen4, 89XXX are Gen5; connectors matter
  [S19].) Both cards then share the one x4 uplink to the host, so card→host
  traffic contends, but card↔card P2P is real through the switch fabric:
  **fabric-bound at the ~13.4 GB/s symmetric class** — "bottlenecked by the
  external switch's P2P fabric, not the connection; a twice-as-wide link
  would still be fabric-bound" [S19].
- **"Option M": two M.2→OCuLink links.** This doubles *host* bandwidth (one
  x4 per card) but P2P then crosses the Strix root complex instead of a
  switch — the config the guide calls unverified.

Why the root-complex risk is bounded for radiance specifically: the kernel's
p2pdma permits AMD root complexes nearly unconditionally [S9], and radiance
probes per-pair at launch and **falls back to host-memory mailboxes
automatically** — same bytes, messages cross two links instead of one; the
measured penalty is "within run-to-run noise for decode at 1–4 streams, and
2–10% on a 23.6K-token prefill" (RQ4, the engine's own GUIDE.md §4.7).
`--p2p off|on|auto`
overrides the probe. The RCCL/hipIpc collective-crash class the guide cites
is a **vLLM-lineage** concern — radiance uses no RCCL/hipIpc, so that crash
family cannot fire here (see §13's disambiguation law).

The guide's precise switch numbers — "L1T 28.07 GB/s / doug.sh 54.7 GB/s
aggregate" — are **UNVERIFIABLE**: not located in any fetched post (RQ4,
Guide-corrections row). They are recorded here **direction-only**: expect
real switch-fabric P2P in the ~13.4 GB/s symmetric class, under the x4-host-
link aggregate. Do not quote 28.07 or 54.7 as verified fact.

## 3. Power caveat — the ~120 W Strix norm

Strix-Halo boards commonly cap an AMD dGPU on OCuLink/M.2 at ~120 W
(community wiki, RQ4 [S19]). The "capped at the minimum 210 W is fine, <1%
of decode" measurement applies to **slot-mounted** cards [S16], not this
path. Whether the lab's board actually caps is a decode-relevant unknown
until measured on-target (expectation, not claim: decode falls with the
power ceiling; prefill mostly not). Mark it OPEN — measure in the TP2
acceptance run. The live single-card re-read of this caveat belongs to the
C12 host-tuning note's POWER-CLOCKS family
(`.agents/notes/radiance-host-tuning.md`): the radiance boot's 300 W
`power_cap` is NOT the ~120 W OCuLink cap class of this section — read
sclk ramp + `power_cap_usd` under load there before assuming this box caps
the card.

## 4. Re-enumeration checklist — the rocrVisibleDevices index law

A third GPU shifts **every** `rocrVisibleDevices`/`ROCR_VISIBLE_DEVICES`
index in the repo — host enumeration is today 0 = R9700, 1 = 8060S (the
dGPU-first record lives in the strata values comment block; EXPLORE §7).
The 8060S is not necessarily index 1 anymore once a second discrete card
exists. Sweep this table on the TP2 day before trusting any engine boot:

| # | Surface | Index today | Action when GPU #3 lands |
|---|---|---|---|
| 1 | `charts/llama-swap/values.yaml` — strata `rocrVisibleDevices` | `"0"` (R9700) | re-run host `rocminfo`, re-pin via the values key (never the template) |
| 2 | same file — `rocrVisibleDevicesByModel` strix lane | `"1"` (8060S) | the APU may move to `"2"` — re-pin from the same receipt |
| 3 | `charts/vllm/values.yaml` — dormant vllm-radiance lane | `"0"` | only if that lane is ever re-enabled — re-check first |
| 4 | `charts/radiance` (shipped engine) | no env at all | nothing to re-pin — the named pool injects devices, env is absent by C02's absence law |
| 5 | host privileged hostPath pods (strata today) | env naming, 0 = R9700 | the same `rocminfo` receipt gates any env-based chip choice |

The radiance engine pod itself is immune by construction (plugin `Allocate`
injects `/dev/kfd` + the chosen card/render and sets no env — §R6-Q1), but
the repo-wide index law above is why the checklist exists: the other engines
still name cards by position, and position is exactly what the third GPU
changes.

## 5. APU hiding is not a drive-by — the interdependency

Under the pre-C07 single-strategy world, the card guide's §4.3
headless-iGPU idea —
bind the APU to `vfio-pci` (ids `1002:1586,1002:1640`; 1640 is its audio
function) to remove it from host amdgpu/KFD — would make `amd.com/gpu`
R9700-only, but the same vfio bind kills the outer llama-swap pod's 8060S
unified-vulkan GGUF serving class (and the catalog's `-strix` fallback with
it): not a drive-by change [RQ3, RQ4]. Under the shipped product naming the
harm is even louder — `amd.com/gpu-8060s` is the pool llama-swap is
scheduled from, so its next restart becomes unschedulable. The lab's proven
idioms (privileged hostPath + env naming, or the named pools radiance uses)
sidestep hiding entirely; the owner ask (APU stays llama-swap's, by name)
is already met by the naming wave (§R6-Q4 row 2).

## 6. Scheduling the second card in the shipped product-naming world (post-C07)

Under the first-party `charts/amd-gpu` with `-resource_naming_strategy=product`
(§R6-Q1) and the D24 patched table, resources are bucketed per **sanitized
marketing name** from the `amdgpu.ids` ConfigMap the chart mounts over the
image's baked file, and the plugin runs one kubelet pool per
name. Consequences for a second R9700 (the shape the TP2 ticket inherits):

- A second card with the **same (device, revision) pair** — `7551/C0`, an
  R9700 (not an R9700S) — resolves to the same product name and **joins the
  same pool**: the node advertises `amd.com/gpu-r9700-1: 2`. Extended
  resources are integer counts with no overcommit, so one TP2 radiance pod
  simply raises its claim to `amd.com/gpu-r9700-1: 2` and the scheduler
  hands it both R9700s — same-name pooling is the product of the strategy;
  the per-name pools keep the llama-swap APU assignment untouched.
- A **different revision is out of the shipped table by construction**: the
  patched `amdgpu.ids` is MINIMAL (this node's ten rows only — the 7551/C0
  renamed row plus the nine carried 1586 rows), so an R9700S (`7551/C1`) or
  any other (device, revision) pair is absent and the card falls back to
  bare `amd.com/gpu` (the trap §R6-Q4 row 5 gates repo-side) — it would NOT
  count toward the `gpu-r9700-1` pool the TP2 claim needs.
- **THE TP2 RE-VERIFICATION LAW (D24 era):** before trusting TP2
  scheduling with a second/third card, VERIFY its (device, revision) pair
  carries in the chart's patched `amdgpu.ids` — and if it does not, ADD
  the row (its product string is what the sanitizer turns into the pool
  name, §R6-Q1) BEFORE the flip wave lands; the bare-fallback is silent.
  The concrete first shape: the same 7551/C0 pair simply joins the pool
  (row already carries); any other pair is an explicit table edit + the
  runbook step-0 receipts re-run at the new row count.
- Therefore **the runbook's sysfs revision receipt carries to the new card
  before trusting TP2 scheduling**: read `device`+`revision` per BDF under
  `/sys/module/amdgpu/drivers/pci:amdgpu/` and match the patched-table
  rows (`7551 C0` expected), exactly C06 step-0 gate (a) — the same receipt
  that gates the naming wave (R6 OQ1). Then assert node status:
  `amd.com/gpu-r9700-1: 2`, `amd.com/gpu-8060s: 1`, and `amd.com/gpu`
  still ABSENT (present = a fallback fired — the gate-(a) decision tree,
  not improvisation).
- Strata needs no naming change: its privileged hostPath pod never held a
  plugin claim (`amd.com/gpu`, `amd.com/gpu-8060s` or `gpu-r9700-1`) —
  R6-Q4 row 3. It keeps hitting cards by host enumeration, which is §4's
  checklist, not §6's pool arithmetic.
- **Alternative lane, recorded not planned:** R6 ranked the ROCm DRA driver
  (`k8s-gpu-dra-driver` v1.0.1) #2 — claim-based selection with zero
  llama-swap churn, and its production witness already ships the TP2 shape:
  dsluo's `r9700-x2` **ResourceClaimTemplate** — CEL `deviceID == "0x7551"`
  with `allocationMode: ExactCount, count: 2` (R6-Q3, R6-Q4 DRA-variant
  row). If the owner ever prefers claims over named pools for TP2, that is
  the documented path; this run's Option-1 ruling stands until they say
  otherwise.

## 7. Engine recipe — fn TP2 (corrected)

The fn HF-card TP2 compose flags, corrected against v1.17.0 (RQ1's recipe
table, RQ4's verbatim check; and the invocation law from RQ0 — the binary
takes `radiance --model <file.rad|checkpoint-dir|hf/repo-id> --port N
<flags>`, there is no `serve` verb — that token belongs to Strata and to
vLLM, and the card guide mis-spoke because of it):

```
--tp 2 --tp-wire wht6 --max-num-seqs 8 --max-model-len 200000
--placement expert_tiered --host-pool-mib 12288 --gpu-headroom-mib 96
--kv-cache-dtype fp8 --prefix-cache-mib 4096 --num-speculative-tokens 3
--max-num-batched-tokens 2048
```

- `--host-pool-mib 12288` is **per rank** — two ranks pin 2 × 12288 MiB ≈
  24 GiB of host RAM, pinned per card and unswapable [S1 via RQ1]; compare
  the one-card pool of 43000. TP2 moves most of that funding onto the cards.
- The VRAM freed by the second card is exactly what lets this shape choose
  the **prefix-cache host tier AGAIN**: `--prefix-cache-mib 4096` (finished
  conversations demote to RAM and restore instead of re-prefilling) — and
  the one-card build is forced onto `--kv-resident` instead, because the
  tier and `--kv-resident` are mutually exclusive: while a group streams,
  the host tier is off and prefix hits work from VRAM only [RQ1]. The
  shipped single-card profile therefore drops `--kv-resident 32768` on the
  TP2 move and adds the tier back — one lever or the other, never both.
  Tier caveat carried from RQ1: demotions land as *pinned* bursts (Wilde's
  OOM class) — a pinned host tier survives only with ≥15 GiB genuinely
  free, keep that headroom real, and `--prefix-cache-mib 0` is the escape
  hatch.
- `--expert-vs-cache-ratio 0.82` appears in the guide's TP2 recipe and is
  **stale — do not use it**: no such flag exists in v1.17.0; the weights/
  cache split is engine-derived and the startup receipt prints every term
  [RQ1]. Everything else above verified verbatim against flashnext.yaml and
  the fn HF card (RQ4).
- Host staging (no P2P) costs only decode noise / prefill −2–10%, so the
  recipe stands whether the cards P2P through the switch or fall back to
  mailboxes [RQ4].
- The pack's 47.68 GiB n-gram table keeps the shipped `--ngram-placement
  disk` — it is not in the TP2 recipe lists, and the disk tier is what the
  one-card build runs today [RQ1]. The `ram=DIR` shared-table form (§10
  item 4) is the one the two-engines-different-cards setup could later
  adopt — OPEN — measure on the TP2 receipts.

## 8. Expected envelope on TP2 — receipts, not constants

Community-class receipts for exactly this shape (RQ4, Serving envelope
fn-TP2 row). Expectations to pre-register for the TP2 acceptance run, with
attribution, and the standing law from RQ1: **pin to the startup receipt,
not to any per-token constant** —

| Quantity | Creator rig (Gen5 x8/x8 P2P) | Wilde Gen4-class | llmkube production |
|---|---|---|---|
| Single-stream decode | ~160 t/s (~15 ms step) | 142–146 t/s follow-up | — |
| Prefill | ~6,400 tok/s @26K | 2,816–3,552 tok/s | — |
| KV pool | — | ~15.7 GiB total (~60 KB/token): one 262k whale or ~4×64k [S8] | runs 262144 ctx on a 62 GiB host, pool 8192 [S11] |
| 8×64k aggregate | — | 252 t/s (278 with spec off) [S8] | — |

The lab sits in the Gen4-x4-switch class, so plan against the Wilde column
and treat the creator column as the ceiling. Open receipt items on TP2 day:
this build's per-token cost across ALL paged groups, the link/P2P lines of
the startup report sampled under load (idle links park at Gen1 — RQ3), and
the real decode under §3's power cap.

## 9. Second-lane unlock — fn and q27 as two peer pods

With one card the honest choices were one resident lane or a swap-child,
because fn TP1 alone consumes ~28–30 GiB of the ~31.86 GiB usable card and
**two peer pods on one GPU is NOT feasible for fn+q27** — capacity-ruled,
"do not plan it" (RQ5, Structural options D). That single-card ruling lifts
with a second card: two peer pods, one card each, each claiming 1 from the
same `gpu-r9700-1` pool. The concrete unlock: the retired vLLM 27B lane
(C01's commented disable) can return as **radiance q27** on the second
card — pack `qwen3.8-27b-mxfp4.rad`, 18.05 GiB (19,377,119,232 B), lfs
`a4908940…`, ungated, with the z-lab DFlash2 drafter merged in-pack (no
`--draft-model`, it is a parse error) [RQ0, RQ5]. Attribution hygiene from
RQ5: the "62–88% MTP drafts accepted" figure is the **swift1.5 card's**
pre-upload smoke run on flash-next TP1, not a sustained benchmark. q27 TP1
fits one 32 GiB
card outright (weights ~18.07 + KV ~12.48 receipt class; host side ≈8.5 GiB)
— the session-capable lane it replaces is the same shape on one card today.
Priority stays higher-wins 9/5/1 across BOTH pods — radiance honors the body
field on every engine, opposite polarity to the retired vLLM table (RQ2).
Host-RAM honesty: TP2 relieves VRAM contention, not the RAM pin ceiling —
pins still sum against the ≈120.6 GiB cap formula with the 4-GiB-free rule,
and the ngram table is per-process unless `ram=DIR` sharing (§10) [RQ1].

## 10. Host-prep deltas vs the single-card list

The single-card host gates (C06 step-0(e): ReBAR, CWSR=1, ECC-off,
`amd_iommu=off` (posture corrected by C12/§D6.6 — the old gate's
`iommu=pt` expectation was the wrong one), zram-off, O_DIRECT ≥5
GB/s for the disk ngram tier, kernel caution) stay; TP2 adds or sharpens:

1. **ReBAR `size=32G` on BOTH cards** — TP2-critical: P2P needs the large
   BAR (at TP1 the no-ReBAR tax is only 0.4–1.8% decode; it is "critical
   only for TP2", and `lspci -d 1002:7551 'Region 0'` per card is the
   receipt) [Guide corrections, RQ3].
2. **P2P kernel configs**: `HSA_AMD_P2P` + `PCI_P2PDMA` checked in the
   running kernel (`/proc/config.gz`), then `rocm-bandwidth-test` card↔card
   as the P2P witness under load [RQ3].
3. **Kernel snapshot caution**: the 7.3.3 `mem_info_vram_vis_total`
   regression (reported after a Tumbleweed move; the lab sits at 7.3.0) —
   snapshot the receipt numbers before adopting any 7.3.3+ kernel [S9].
4. **`amdgpu.no_system_mem_limit=1`** — only if two engines share one
   pinned ngram table via the `ram=DIR` tmpfs form: the driver counts the
   shared page once per pinning process, and without it the second pin is
   refused [RQ1]. Not needed on the default `disk` placement of §7.

## 11. Adoption steps — the runbook skeleton the TP2 ticket walks

Read-only or owner-executed steps only (runbook law); every "edit" is a
values change that reaches the cluster through ArgoCD alone:

1. **Physical** (owner): mount the second R9700 via §2's switch path or
   Option M; record per-card BDFs and the link widths the BIOS negotiated.
2. **Host-prep deltas**: walk §10 items 1–3; item 4 only if a `ram=DIR`
   sharing plan is actually adopted.
3. **Enumeration sweep**: apply §4's checklist from a fresh `rocminfo`;
   values re-pins go through each engine's documented key, never a template.
4. **Revision receipts + pool assert**: §6's gate — sysfs pair per BDF
   against the patched table (the TP2 RE-VERIFICATION LAW: the new card's
   (device,revision) pair must carry in `charts/amd-gpu`'s minimal
   `amdgpu.ids` ConfigMap or be ADDED before trusting TP2 scheduling), then
   node status shows
   `amd.com/gpu-r9700-1: 2`; a mismatch is the fallback-trap decision
   tree, not improvisation.
5. **Chart change, same chart — two shapes:**
   - *fn goes TP2 (one pod, two cards):* move the C02 single-source scalars
     — tp 1→2, `hostPoolMib` 43000→12288 (per rank), `--kv-resident` out /
     `--prefix-cache-mib 4096` in, chunk 4096→2048 — and the claim count
     `amd.com/gpu-r9700-1` 1→2 (request==limit pair kept, Guaranteed
     law). Guaranteed memory recomputes at the TP2 pin set (~24 GiB pool +
     tier + slots + tables) — receipt-gated, same ladder discipline as C06
     step-6, never a pre-emptive softening.
   - *Second lane (q27 pod beside fn):* a second release of the same chart.
     SKETCH — the TP2 ticket resolves the exact appset plumbing (how one
     internal chart yields two Applications, the sibling service-values
     subtree, and the second peer key) against `charts/base`'s appset
     shapes; do not copy this sketch blind:
     `charts: { …, radiance-tp2: {namespace: default, ServerSideApply: "false"} }`
     · `radiance-tp2:` top-level block, scalars only (deep-merge REPLACE
     law), `modelPath` re-pin to the q27 `.rad` · peer addition as a
     `peers.radiance-tp2` block beside the existing two (proxy to the new
     service on 8000, NO `/v1` suffix, timeouts 1800/30, `priority?` floor
     5) · its own per-peer evidence file joins the D13 per-key law.
6. **Catalog second row**: for a q27 lane, add rows under the honest-id law
   (e.g. `qwen3.8-27b-radiance` + `-urgent`/`-low` wire-siblings sharing the
   modelID, `body.priority` 9/5/1, `limit.context` = that pod's served
   truth) via the rulesync source, `generate --check` clean — mirroring the
   radiance trio C05 lands.
7. **Acceptance re-run**: re-run the cf-143 on-target acceptance runbook
   (`.agents/notes/radiance-on-target-acceptance.md`, C06) at the TP2
   shape — its step-0 naming gates now including the new card's §6 receipt,
   its 8-session gate at §7's sizing, its startup-report capture reading
   the P2P/wire lines under load, and its priority live check per pod.
8. **Owner posture note**: with radiance on its own card(s), §12's
   coexistence relief applies — the Q10 strata scale-down dance may stop
   being required for the CONTENTION; it does not end the restore-back
   arithmetic (§12's either/or caveat: host RAM, not VRAM, is what a
   110-scheduled radiance holds); that stays the owner's call, observed
   not auto-mitigated (Q11 law).

## 12. Coexistence relief — the Q11 contention dissolves

During coexistence the shipped world has radiance and strata sharing ONE
physical R9700: strata's privileged hostPath arenas sit inside the same
card the `gpu-r9700-1` pool books exclusively for the radiance pod
(naming is scheduler bookkeeping, not VRAM arbitration — the plan's Q11
one-engine-per-card contention, ruled "observe, no auto-mitigate", plus the
owner's Q10 manual scale-down handshake). A second R9700 lets radiance hold
one card while strata keeps the other — the contention **dissolves without
touching the naming scheme**: strata still holds no plugin claim (§6),
llama-swap still schedules from the named APU pool, and the
Pending-handshake arithmetic on host memory gets a second card of
breathing room ONLY on the engine side: at the shipped 110 (D29) strata
can never co-reside beside a scheduled 110-radiance —
110 + 64 + 6.3 = 180.3 > 125.08, and a second card adds VRAM, not host
RAM. Record for the card: TP2 is the cleanest RELIEF of the card-side
contention, not an exit from the scale-down dance — exiting the dance is
the cutover decision itself (the runbook's step 10 either/or, restated
by C12). Forward look (D30(5), §R8): TP2 SHRINKS the host answer ~3× —
per-rank `--host-pool-mib 12288` × 2 ≈ 24 GiB, the `--kv-resident` mirror
gone, the prefix tier affordable ⇒ ~30–35 GiB class (witness: llmkube runs
262144 ctx at req 40 / lim 48). So the shipped 110 is the SINGLE-CARD
SUPERSET that TP2 re-pins DOWN — and at that smaller number strata
co-existence may arithmetically RE-OPEN (~35 + 64 + 4.1 + 1.2 ≈ 104 ≤
125.08): a decision that rides the CUTOVER ticket, recorded here so nobody
rediscovers it. Pointer and sums only — TP2's recipe re-derivation is that
ticket's job (cite D29/D30(5)).

## 13. Three-way naming law — what this doc's engine is

"Radiance" in cf-143 and on the follow-up card means the **StillDeadcode/
radiance engine** — the standalone C++/HIP inference server (RQ0). It is NOT
the `magiccodingman/vllm-radiance` vLLM FORK behind `charts/vllm` (the
lane C01 disabled; its `RADIANCE_*` env vars belong to that fork), and it is
unrelated to `Niko1221/Strata`, which stays live beside radiance per Q5.
Consequence for this doc: the guide's TP2 "RCCL/hipIpc crash class" warning
belongs to the **vLLM lineage only** — radiance uses no RCCL, and its own
P2P fallback is the measured mailbox path of §2, not a crash.

## 14. Provenance, citations, and status

- Citations: `RQ0`–`RQ5`, `§R6` with `R6-Q1`–`R6-Q5` (`R6-Q4-<row>` table
  rows), main-list `OQ1`–`OQ7` and `R6 OQ1`–`OQ4`, plus `[S#]` source ids —
  all resolve in `.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-
  strata/RESEARCH.md` (Sources + §R6-S tables); plan law from the folder's
  plan file, DECISIONS D17/D18/D21 (naming wave) plus D23/D24 (the C08
  first-party conversion + the patched-table rename) and the Q5/Q6/Q10/Q11
  rulings; contract: `tests/notes/radiance-tp2.sh` (T1 structure/provenance,
  T2 this doc's citation resolver, T3 the needle set).
- Status of every number: community-recipe class (RQ1/RQ4 attributions are
  explicit — creator rig vs Wilde Gen4 vs llmkube, never blended), and the
  standing receipt law: the engine's startup receipt decides sizing.
- The doc is the follow-up card's ONLY content source — written
  self-contained so an owner reading the card needs nothing from this
  folder. Card creation itself is a coordinator run-end action (Q6).
