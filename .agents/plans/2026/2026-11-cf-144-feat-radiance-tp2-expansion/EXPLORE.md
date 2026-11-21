# EXPLORE.md — cf-144 feat-radiance-tp2-expansion (board card AD-144)

Scout grounding by `agent-explore`, 2026-11-21, worktree branch
`cf-144-feat-radiance-tp2-expansion` @ tip `7886e20b4` (clean tree, == main).
All repo paths relative to the worktree root. Live reads via
`readonly-ai-gpu-kubernetes` / `readonly-gpu-kubernetes` (read-only tier only),
taken 2026-11-21 ≈16:00 UTC.

## 0. THE FORK ANSWER — does the box have a second card TODAY? **YES (live).**

The plan forks on this; it is the headline finding.

- **Node `ai-gpu` capacity/allocatable (live, v1 Node status):**
  `amd.com/gpu-r9700-1: "2"`, `amd.com/gpu-8060s: "1"`, `amd.com/gpu: "0"`,
  memory `131150624Ki` (≈125.08 GiB allocatable — matches the doc's node sum).
- **Device-plugin witness (pod `gpu-ai-amd-gpu-device-plugin-daemonset-b79lf`,
  container restarted `12 (3h18m ago)`, log tail 2026-11-21 12:57:54):**
  `Found 3 AMDGPUs`; devices map = BDF `0000:c3:00.0` deviceID **7551 rev C0**
  renderD128, BDF `0000:c7:00.0` deviceID **7551 rev C0** renderD129 (the NEW
  second R9700), BDF `0000:c8:00.0` deviceID 1586 rev C1 (APU);
  `Reporting 2 devices as gpu-r9700-1`.
- **Consequence for the §6 RE-VERIFICATION LAW:** the second card is the SAME
  `(7551, C0)` pair as the first → its row already carries in the chart's
  patched minimal `amdgpu.ids` (`charts/amd-gpu/values.yaml:225`) → it joined
  the same pool automatically. The fallback-to-bare trap did NOT fire (the
  only pool growth observed is `gpu-r9700-1: 2`). Gate-(a) sysfs receipts and
  the ROCm `rocminfo` sweep (§4) still want owner confirmation, but the
  repo-side prerequisite is satisfied WITHOUT a table edit.
- **Physical-mount timing (inferred, honest):** device-plugin restart ≈3h18m
  ago + a fresh llama-swap pod + fresh q27 pod all at ~12:57–12:58 UTC + two
  dead older pod husks (4d16h, 5d) — consistent with a node (re)boot shortly
  after the second card landed, today. Owner-side facts (OCuLink path, link
  width, ReBAR per card, power cap) are NOT repo-visible.

The expansion is therefore **repo-shippable now** for the pool/scheduling
half; the acceptance half (P2P under load, ReBAR receipts, ~120 W power class)
stays owner-executed host receipts (§10 of the doc, runbook law).

## 1. Live serving state — fn/q27/strata (git vs live differ BY DESIGN)

Git resting pair vs live at read time:

| Release | git renders | live (2026-11-21) |
|---|---|---|
| `gpu-ai-radiance` (fn TP1) | replicas 1 (chart default) | **Deployment spec.replicas = 0**, no pods |
| `gpu-ai-radiance-q27` (pod-swap) | `replicas: 0` (`services/gpu-ai/prod/values.yaml:891`) | **spec.replicas = 1**, pod `gpu-ai-radiance-q27-648bd6886-dndd6` Running 1/1, age 3h6m (created 2026-11-21T12:57:55Z), args exactly the shipped TP1 q27 list, `amd.com/gpu-r9700-1: 1`, mem 24Gi pair |
| `gpu-ai-llama-swap-strata` | enabled 1 (overlay flips the seven flags) | **spec.replicas = 0** |
| `gpu-ai-llama-swap` (router) | 1 | Running 2/2, age 3h6m (stale siblings: one Unknown 5d, one `UnexpectedAdmissionError` 4d16h) |

- The owner is MID-SWAP-WINDOW right now: fn DOWN, q27 UP, strata DOWN
  (console recipe: `.agents/notes/radiance-q27-boot.md:118,133` — `kubectl
  scale`; the "don't-sync law" at its :151-159). Anything that syncs
  `gpu-ai-radiance` while parked re-applies git (fn back to 1).
- **Scheduling math for the TP2 fork (live pool = 2 cards, still NOT
  co-resident-capable):** fn at the shipped `110Gi` request + q27 `24Gi` +
  router `4.125` + system `1.158` = 139.3 > 125.08 → fn would sit Pending
  ("Insufficient memory"), loud, not OOM, even with the pool at 2. The GPU
  pool no longer blocks two single-card pods; **host RAM does — until the
  TP2-era fn memory re-pin** (doc §11.5, RESEARCH §R8-Q5: ~30–35 GiB pins,
  llmkube witness req 40 / lim 48). At ~48 GiB: 48+24+4.125+1.158 ≈ 77 ≤
  125.08 — q27 beside fn becomes arithmetically possible; and strata's
  restore-back re-opens only per §12's ~104 ≤ 125.08 forward-look (recorded
  for the CUTOVER ticket, not this one).
- Device-plugin Allocate lines at 12:58:02: APU `c8:00.0` → llama-swap, `c3:00.0`
  → q27. `c7:00.0` (the new R9700) currently unallocated.

## 2. Radiance serving surface (charts/radiance + services + custom-values)

`charts/radiance/values.yaml` (app-template 5.0.1, Chart.yaml version 1.0.0 /
appVersion 1.17.0):

- sizing scalars — `guaranteedMemoryGi: 110` (:72, D29 owner-ruling block with
  the 71.04-printed-budget story at :40-47 and the either/or restore sums at
  :60-64), `hostPoolMib: 43000` (:73), `maxModelLen: 200000` (:74),
  `maxNumSeqs: 8` (:75), `cpuCores: 8` (:83). NOTE: **no `tp` scalar exists** —
  `--tp "1"` is a literal in `serveArgs` (:148). Doc §11.5's "move the C02
  single-source scalars — tp 1→2" therefore implies either a new scalar or an
  in-chart list edit; the scalars-only override law binds the SERVICE overlay,
  the chart's own list edits chart-side (:133-143 absence-law block).
- `serveArgs` (:144-160): `--tp 1`, `--host-pool-mib 43000`, `--gpu-headroom-mib 96`,
  `--kv-resident 32768`, `--max-num-batched-tokens 4096`,
  `--checkpoint-interval 4096`, `--ngram-placement disk`,
  `--served-model-name qwen3.8-flash-next-radiance`. The doc's TP2 recipe
  (§7) is `--tp 2 --tp-wire wht6 … --host-pool-mib 12288 … --prefix-cache-mib
  4096` + chunk 2048, `--kv-resident` OUT (mutual exclusion :76-82);
  `--checkpoint-interval` / `--ngram-placement disk` are not re-listed in §7
  — the test session must re-derive the FULL_PROFILE set-equality pin
  (`charts/radiance/tests/test_serve_args.py:46-60`, values :131-143).
  `--tp-wire wht6` appears NOWHERE in today's args — pure add.
- claim pair (:298-305): requests==limits `cpu "8"`, `memory "110Gi"`,
  `amd.com/gpu-r9700-1: "1"` (Guaranteed law; extended resource requires the
  equal integer pair — TP2 shape flips the claim to `"2"`, doc §11.5).
- supplementalGroups `[486]` (:204, render-node GID precedent);
  seccomp Unconfined (:209-210); no ROCR/HIP env anywhere (C02 absence law
  :117-119 — the §4 checklist row 4: "nothing to re-pin" for this chart).
- persistence: weights ride `existingClaim: llama-swap` (500Gi shared claim,
  :437-445); shm emptyDir 2Gi (:449-452). TP2 two-rank shm/host-staging
  envelope is receipt-land, not a repo constant today.
- init `radiance-fetch`: fn pack ledger (:348-351, 113.6 GiB, lfs
  `0af5e962…`), BusyBox-grammar equality gate (:370-381).

`services/gpu-ai/prod/values.yaml`:

- roster `charts:` — `radiance` (:78-80), `radiance-q27` with the
  `chart: radiance` override (:98-101, D56(1) one-chart-two-releases; the
  appset lever is `charts/base/templates/appset-charts.yaml` — the
  `hasKey "chart"` branch cited at :83), `amd-gpu` internal entry (:59-66,
  ServerSideApply "true"), `llama-swap` (:22).
- `peers.radiance` hop (:658-667): proxy `http://gpu-ai-radiance.default.
  svc.cluster.local:8000`, NO `/v1`, models `[qwen3.8-flash-next-radiance]`,
  timeouts 1800/30, `filters.setParams "priority?": 5`.
- `peers.radiance-q27` hop (:697-706): floor 4 (D56(5); trio 8/4/0, fn keeps
  9/5/1 — D58 names the legs urgent/default/low), idle-502 caveat (:693-696,
  D57 source).
- `radiance:` overlay (:820-837): modelPath dual-edit re-pin (:828); sizing
  scalars deliberately NOT re-pinned (:829-837 — the TP2 ladder stays ONE
  chart-value edit).
- `radiance-q27:` subtree (:876-1036): the switch-discipline header (:848-875,
  the three independent both-up blockers — pool capacity-1 at ship time, VRAM
  30.55>29.30 claimable, host RAM 9.80 free), `replicas: 0` (:891), whole-list
  q27 args (:932-943), `24Gi` pair with the non-subtractable chart-inherited
  cpu/gpu claim note (:944-968, D26 overlays ADD never REMOVE), whole-script
  init fetch (:997-1036, q27 pack ledger :971-981). **TP2 changes here: once
  the pool is 2, the "capacity-1, non-subtractable" blocker is lifted by the
  pool count, not by a removal — D26 still says the overlay cannot subtract
  the claim line, so the beside-fn topology rides per-pod claims of 1+1 and
  only the fn memory re-pin unblocks scheduling. Record this precisely in the
  plan.**
- `custom-values/gpu-ai/prod-values.yaml` — NO radiance/radiance-q27 entry
  (trio law's documented skip, keyless D8/D54(2)); only base/hivetools/
  llama-swap (hf-token `2ebdd082-4996-440b-a8c1-b4de01130738`).

`charts/llama-swap/values.yaml` peers seam + enumeration:

- the peers hops are SERVICE-overlay data (`config.peers`), chart-side only
  the strata machinery; evidence single-sources live in
  `charts/llama-swap/tests/evidence/radiance-peers-expected.yaml` and
  `radiance-q27-peers-expected.yaml` (D13 per-peer-key law; dev conforms
  values to evidence, never the reverse — headers verbatim).
- strata `rocrVisibleDevices: "0"` (:1504) +
  `rocrVisibleDevicesByModel.strix: "1"` (:1517-1518) — **these host-index
  assumptions are exactly what card 2 shifted (§4 checklist rows 1–2, 5).**
  strata's 110Gi limit block (:1319-1341) is the owner's "container must die
  BEFORE the node" source cited by radiance's D29.
- strata privileged hostPath posture (:1342-1363): per-CLUSTER product-naming
  prose; strata holds no plugin claim (§6, R6-Q4 row 3).

## 3. amd-gpu plugin surface + "extend product naming to the gpu cluster"

`charts/amd-gpu/values.yaml`: product-naming ledger :26-47; image
`rocm/k8s-device-plugin:1.31.0.12` + digest :95-104; `command: [/root/k8s-
device-plugin]` + args incl. `-resource_naming_strategy=product` :127-132;
`/sys` hostPath (product naming reads sysfs) :154-158; the MINIMAL patched
`amdgpu.ids` ConfigMap :178-225 (rows: nine 1586 + `7551, C0, r9700-1`;
TP2 re-verification law prose :195-198; hot-reload law :203-207). Object-name
rename-set enumeration :20-24. `tests/evidence/` holds the pre-c08 oracle
(DS yaml, ids rows, image-config receipt).

- **Shipped pool string is `amd.com/gpu-r9700-1`** (D24 patched-table rename).
  The launch prompt's `amd.com/gpu-ai-pro-r9700` and RESEARCH R6-Q4 row 1's
  `amd.com/gpu-ai-pro-r9700` are the PRE-D24 (C07-era) name — superseded;
  `tests/notes/radiance-tp2.sh:33-35` and `amd_gpu_testlib.py` carry the
  canonical constants block (one edit site; future lane moves edit both
  bash+py).
- **gpu cluster today (live node `gpu` via `readonly-gpu-kubernetes`):**
  capacity `amd.com/gpu: "1"` (bare single naming), cpu 6, mem ~28.6 GiB — the
  external chart entry `amd-gpu: version 0.22.0, repository
  https://rocm.github.io/k8s-device-plugin/` (`services/gpu/prod/
  values.yaml:135-139`) with the C10 bare-claim ADD for llama-swap at :437-453
  (`limits: amd.com/gpu: 1`, limits-only, kubelet mirrors). This is D21's
  per-cluster shield BY DESIGN (charts/llama-swap/values.yaml:1348-1362).
- **What extending product naming there concretely changes** (D21: "rides the
  TP2 follow-up CARD #1"; the card says WHEN a second card is planned — which
  it now is, live):
  1. `services/gpu/prod/values.yaml` `charts.amd-gpu` entry: drop
     version/repository → internal git-path entry (mirror
     `services/gpu-ai/prod/values.yaml:59-66` shape).
  2. The patched `amdgpu.ids` table: the gpu box's card (8 GiB class —
     `services/gpu/prod/values.yaml:430-436` says "8GiB gpu box") has an
     UNKNOWN (device,revision) pair; with the CURRENT minimal table that card
     would fall back to bare `amd.com/gpu` (loud Pending trap if a named claim
     referenced it). A product-named pool there requires ADDING the row (owner
     sysfs receipt first — §6 gate-(a) idiom) and re-running the
     runbook-step-0 receipts at the new row count; the APU-rows-carry law's
     twin applies (dropping rows strands claimants).
  3. `services/gpu/prod/values.yaml:446-453` claim ADD → named pool once the
     row lands (or keep bare if the fallback is accepted — plan decision).
  4. Tests: `charts/llama-swap/tests/test_cf143_naming_flip.py` (the gpu-
     cluster render arms assert bare `amd.com/gpu: 1` INTACT as the shield's
     executable proof — a flip re-pins these legs),
     `tests/services/amd-gpu-naming.sh` (n3 whole-repo census),
     `charts/amd-gpu/tests/` (render parity/provenance), the
     `charts/llama-swap/tests/evidence/off-parity/` fixture (D21: "moves ZERO
     lines" — a flip makes it move). CI legs: `.github/workflows/
     amd-gpu-render-tests.yaml`, `radiance-render-tests.yaml`.
  5. ArgoCD one-time: the internal-chart swap renames the DaemonSet object on
     that cluster too (same prune+create swap doc as gpu-ai's C08).

## 4. Card numbers vs shipped state (where each lives)

- **110 GiB pod memory (D29):** chart values :37-72 (owner ruling, superseding
  D28's 96 ceiling as THE VALUE ONLY); testlib SCALARS comment
  (`radiance_testlib.py:50-60`) restates the 71.04 boot OOM story;
  `charts/llama-swap/values.yaml:1319-1325` is the strata source of 110.
- **71.04 printed budget:** chart values :41-46 ("parts sum 77.88 against
  whole 71.04 — bounded residual, never re-add", D30(2)); llmkube witness in
  RESEARCH §R8.
- **Either/or restore truth:** chart values :60-64 (110+64+6.3=180.3>125.08 →
  designed Pending handshake; "the cutover is now a real either/or"); restated
  doc §11.8/§12 and RESEARCH §R8-Q5:1839-1845. **TP2 does NOT end it** (doc
  §12.8 verbatim) — the shrink to ~30–35 GiB class is what RE-OPENS the
  arithmetic (§R8-Q5: 48+64+6.3≈118.3≤125.08), riding the CUTOVER ticket.
- **~3× host-answer shrink:** RESEARCH §R8-Q5 (folder
  `.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/
  RESEARCH.md:1817-1848`) — per-rank 12288×2≈24 GiB, kv-resident mirror gone,
  prefix tier back ⇒ ~30–35 GiB class, witness llmkube req 40/lim 48 at
  262144 ctx. Serving envelope fn-TP2 row :726-731; RQ4 :455-510; §R6 :852+;
  §R7 :1277+.
- **TP2 recipe corrections (stale-flag law):** doc §7:199-203 —
  `--expert-vs-cache-ratio 0.82` is stale/nonexistent, never ship it;
  `28.07`/`54.7 GB/s` are direction-only. T3 absence bars in
  `tests/notes/radiance-tp2.sh:242-254` red any use.

## 5. Validation surfaces (locate-only; NOT run — scout is read-only)

Suites a TP2 change touches, all per-directory pytest (no unit suite exists;
"tests" = render contracts), with the AGENTS.md PATH law (`export
PATH=$HOME/.local/bin:$PATH` before any helm-backed run, else silent mass-skip):

- `charts/radiance/tests/` — test_serve_args (FULL_PROFILE set-equality +
  scalar-splice + dual-edit leg), test_resource_name_identity (cross-chart
  pool-name equality vs the amd-gpu ledger), test_render, test_contract
  (digest/pack/renovate ledgers), test_renovate_ledger, test_peers_stability
  (served-id single authority), test_q27_lane (overlay arms; chart-zero-diff
  law), `radiance_testlib.py` (SCALARS/FULL_PROFILE constants — TP2 re-pin
  epicenter). Run: `python3 -m pytest charts/radiance/tests -v`.
- `charts/amd-gpu/tests/` — test_render (parity legs), test_provenance,
  `amd_gpu_testlib.py` (canonical GPU-name constants). Run:
  `python3 -m pytest charts/amd-gpu/tests -v`.
- `charts/llama-swap/tests/` — test_cf143_naming_flip (per-cluster shield
  arms), test_radiance_peer, test_strata_wiring (:177 peers-key wave law
  `{strata}` / `{strata,radiance}` / `{strata,radiance,radiance-q27}` — a TP2
  second-peer key set change RE-PINS this sanctioned-wave list),
  test_flashnext_blast_radius (:203-235 same wave law + evidence carve),
  golden/ + evidence/ single-sources. CI leg for the gpu-ai service overlay:
  extract `d.get('radiance') or {}` / `d.get('radiance-q27') or {}` and
  `helm template` — `.github/workflows/radiance-render-tests.yaml:57-77`.
- `tests/notes/radiance-tp2.sh` (T1..T3 doc contract; bash, run from repo
  root; DOC/RESEARCH overridable via env :26-27) and siblings
  `radiance-runbook.sh`, `radiance-q27-boot.sh`, `radiance-host-tuning.sh`.
- `tests/services/amd-gpu-naming.sh` (n1..n3 census/sweep).
- `tests/pipeline-models/surface.sh` M7/M8 (catalog trio + floor pins,
  D58-cited).
- Plain-validation: `helm lint charts/radiance`, `helm template radiance
  charts/radiance --set domain=spencerslab.com --set clusterName=gpu-ai`
  (workflow lines 52-55), same pair for amd-gpu/llama-swap suites' CI twins.

## 6. Gotchas (grounded, with sources)

1. **Git-vs-live divergence is law, not drift:** fn0/q27-1/strata-0 live is a
   parked owner swap (q27-boot note "don't-sync law"). A TP2 plan that syncs
   during a parked window parks fn Pending (RAM math §1) — loud, designed.
   Resting state in git stays fn 1 / q27 0; TP2 decides NEW git resting state.
2. **The two-shape fork is now live-real (doc §11.5):** shape A fn-TP2 (one
   pod claims both cards → q27 can only pod-swap against fn); shape B
   beside-fn co-residency fn TP1 + q27 TP1 (unlocked by the pool=2 GPU-side,
   RAM-blocked until fn's 110Gi pair re-pins down). The plan must pick/phase;
   owner's current live posture (q27 UP, strata DOWN) suggests they're
   actively using the q27 lane — ask via plan questions, don't assume.
3. **D26 non-subtractability:** service overlays can ADD/UPDATE the claim map
   but never REMOVE the chart-baked `amd.com/gpu-r9700-1: 1` or cpu 8. A TP2
   claim of 2 or a memory re-pin is CHART-SIDE (the ladder's "one chart-value
   edit" design, services overlay :829-837), or an overlay UPDATE of the same
   key (map merge updates fine).
4. **Enumeration sweep is overdue, not future tense:** §4's "when GPU #3
   lands" table assumes a third card; host enumeration today ALREADY has
   three GPUs (plugin map: card1 c3, card2 c7, APU c8). strata's
   `rocrVisibleDevices "0"` and strix `"1"` (charts/llama-swap :1504/:1517)
   name POSITION, and "1" plausibly now points at the second R9700, not the
   APU. strata's git shape renders at replicas 0 live, but any strata
   restore-back after the flip is the moment that mis-naming bites (engine
   binds wrong silicon — the vllm 307/310 crash-loop class, chart comment
   :108-109). ROCm `rocminfo` receipt = owner-side gate before any values
   re-pin; the re-pin itself is a values edit.
5. **D57 posture (502, not 503):** idle-peer 502-`peer proxy error`-`no
   endpoints`-loud-never-silent sentence is token-pinned across evidence +
   carriers (`git grep -nw 503` sweep leg); under shape B q27 is no longer
   idle so the sentence still governs only the fn-idle direction. Status codes
   ship with sources only.
6. **q27 pod-swap law survives TP2-adjacency:** "fn DOWN first, then q27 UP"
   (D54(1)) is a SAME-card law; beside-fn co-residency removes it for shape B
   but the doc insists "annotate, never rewrite" (SHIPPED notes §9/§11) — TP2
   doc edits re-pin `tests/notes/radiance-tp2.sh` T3 arms (§14 contract).
7. **Hardware path stays owner-side:** OCuLink switch/PEX/Option-M, ReBAR=32G
   per card, `HSA_AMD_P2P`/`PCI_P2PDMA` kernel checks,
   `rocm-bandwidth-test`, the ~120 W power-cap question (§3 OPEN), the 7.3.3
   kernel-snapshot caution (node kernel today `7.3.0-1-default`, live
   nodeInfo — the caution is about FUTURE kernel moves). None are repo edits;
   the plan's dev chunks must be values/tables/tests, acceptance = owner
   receipts. The repo side is NOT blocked by them; the shipped TP2 values are
   receipt-gated for final sizing (D28(6) class law) — ship the shape, pin the
   numbers per §4's ladder discipline "never a pre-emptive softening".
8. **Node `amd.com/gpu: "0"` nuance:** the chart prose (:111-113) says bare
   amd.com/gpu "disappears"; live shows the key PRESENT with count 0 (plugin
   deregistration residue) — a stray bare claim still pends forever, prose
   conclusion unchanged; don't let a test write a capacity-absent assertion
   that this breaks.
9. **Pre-D24 name traps:** any chunk text carrying `gpu-ai-pro-r9700` is
   stale (superseded by `r9700-1` via the patched table; D24). Constants live
   in exactly one place per language (bash twin + py testlib).
10. **Anchors resolve per-document:** the overlay `modelPath` re-pin does not
    reach serveArgs (dual-edit law, chart :21-25, overlay :822-827); the q27
    subtree's `modelPath` is DECORATIVE (render-inert, D57 adjudication (1))
    but the three-way sync law stays.
11. **release.yaml owns version bumps** — TP2 edits to charts/radiance +
    charts/amd-gpu + services must NOT hand-bump Chart.yaml versions (repo
    hard rule; charts/radiance stays 1.0.0).

## 7. Open questions for the plan (guesses recorded; NO questions asked — scout law)

- **OQ-A (topology):** TP2 shape first — fn TP2 (claim 2, q27 stays pod-swap)
  or fn TP1 + q27 beside-fn co-residency (both claim 1, needs fn memory
  re-pin ≤ ~48 GiB before scheduling)? Best guess: the card title says TP2 ⇒
  fn goes TP2 first; co-residency is the §9 unlock the second card enables
  but q27-beside-fn only pays after fn's re-pin AND conflicts with TP2
  (both cards then belong to fn's pod). Phase them; ask owner.
- **OQ-B (fn TP2 memory):** TP2-era `guaranteedMemoryGi` value — doc says
  recompute at the TP2 pin set (~24 pool + 4 tier + slots + tables ⇒ ~30–35
  GiB pins; llmkube 40/lim 48 witness; +4 slack law ⇒ a 48–64 GiB class).
  Best guess: ship 48 (witness-class, ≥ printed + 4 once receipts confirm);
  receipt-gated, owner-ruling shaped like D29.
- **OQ-C (serveArgs TP2 exact set):** §7 recipe + retained
  `--checkpoint-interval 4096` + `--ngram-placement disk` +
  `--served-model-name`; drop `--kv-resident`; `--host-pool-mib 12288`
  (per-rank), chunk 2048. Test session re-pins FULL_PROFILE accordingly.
- **OQ-D (gpu-cluster naming extension IN this ticket?):** card says WHEN a
  second card is planned (true). Best guess: scope a chunk to it ONLY after
  the owner sysfs-receipts the gpu box card's (device,revision) pair; the
  fallback-to-bare outcome makes it optional for TP2 itself (TP2 is gpu-ai).
- **OQ-E (strata enumeration re-pin):** owner `rocminfo` first; values edits
  are one-key ops (strata `rocrVisibleDevices`, strix lane
  `rocrVisibleDevicesByModel`) — gate any strata restore-back on this.
- **OQ-F (q27 during fn-TP2):** with fn claiming 2, q27 pods forever Pending
  while fn is up — the pod-swap law already enforces fn DOWN first, so no
  chart change strictly required; document the pool-arithmetic (1 free card
  during swap ⇒ q27 TP1 unchanged; q27 TP2 would need BOTH cards while fn is
  parked — §envelope's q27-TP2 row exists but is not on the card).

## 8. Provenance pointers

Card body = `.agents/notes/radiance-second-gpu-tp2.md` (432 lines, read fully;
status line :11-13 "expansion instructions, not shipped config … The TP2
ticket re-derives the plan"). cf-143 folder:
`.agents/plans/2026/2026-11-cf-143-feat-radiance-replaces-strata/`
(RESEARCH.md RQ4 :455, Serving envelope :685 (fn-TP2 row :726), §R6 :852
(R6-Q4 table :1130), §R7 :1277, §R8-Q5 :1817; DECISIONS.md D21 :212,
D57 :1819, D58 :1866; EXPLORE/STATE/FRICTION/chunks all present). Live reads
this scout session: `readonly-ai-gpu-kubernetes` (Node ai-gpu; Deployment
gpu-ai-radiance / gpu-ai-radiance-q27 / gpu-ai-llama-swap-strata; Pod list +
q27 pod spec; device-plugin pod log) and `readonly-gpu-kubernetes` (Node gpu).
ArgoCD Application health/sync state NOT read (Application CRDs not exposed
through the readonly tier here) — live replica counts above are the
Deployment specs, which is what scheduling obeys.
