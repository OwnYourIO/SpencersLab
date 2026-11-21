# PLAN: Radiance second-GPU (TP2) expansion (AD-144)
feature: 2026/2026-11-cf-144-feat-radiance-tp2-expansion
Drafted 2026-11-21 by `agent-plan` from the card body (`.agents/notes/radiance-second-gpu-tp2.md`,
third refresh — verbatim), EXPLORE.md (scout, live 2026-11-21), and the cf-143 authority
(RESEARCH RQ4/§R6/§R7/§R8-Q5, DECISIONS D21/D24/D29/D30/D54/D56/D57/D58). `plan_status: draft` —
the batched question round below MUST answer OQ-A before approval; the coordinator owns the flip
to approved only after that round + the owner's word. [FOLD: that round HAS run and the owner
answered + approved — see the stamp below; the flip stays coordinator-owned.]

**FOLDED 2026-11-21 (fold-only round)**: the batched question round RAN and the owner answered —
OQ-A "A — fn TP2, claim both cards" CONFIRMED · OQ-B "Hold 110, re-pin after the print" OVERRIDES
the draft-shipped 48 · OQ-C "Confirm as specced" stands · OQ-D "Defer C04 to a follow-up card"
OVERRIDES (C04 does NOT execute in this run) · OQ-E "Receipt now, honest no-op close OK" stands ·
OQ-F "Accept pod-swap + claim-1 pin" stands · OQ-G "Accept 2 GiB + receipt" stands. Approval:
"Approve — run all waves" (owner word, recorded DECISIONS P12) — the coordinator performs the
flip itself; `plan_status` stays `draft` (coordinator-owned). Provenance: this round rewrote no
scope and re-planned nothing; it only encoded the rulings below.

## Goal
Ship the repo-side half of tensor-parallel 2 for the Flash-Next lane: flip `charts/radiance` fn
to the TP2 recipe (docs §7/§11.5) claiming BOTH R9700s (`amd.com/gpu-r9700-1: "2"`, pool live at
2 — no `amdgpu.ids` table edit needed on ai-gpu, the 7551/C0 row already carries), hold the
Guaranteed memory scalar at 110 for this wave (OQ-B ruled: the first-boot print is the budget
authority — the DOWN re-pin rides post-TP2-boot, not this flip) and re-pin the rest of the TP2
pin set, and keep the q27 pod-swap lane correct under the flip (its
overlay must explicitly pin claim 1 — the chart flip would otherwise strand it at 2). Second
cards' acceptance (P2P under load, ReBAR receipts, rocminfo, power cap) stays owner-executed
host receipts — runbook law, not repo edits.

**Shape taken (OQ-A — ANSWERED, owner ruled "A — fn TP2, claim both cards", 2026-11-21):** shape
A, fn TP2 one pod claiming both cards; q27 stays pod-swap. Had the owner ruled shape B (fn TP1 +
q27 beside-fn co-residency), C01 would be re-planned — B does NOT touch serveArgs (fn stays TP1)
but re-pins `guaranteedMemoryGi` ≤ ~90 class and flips q27 resting replicas; the chunk graph
would change materially. B is moot on this ruling.

## Out of scope
- Strata cutover / restore-back co-existence re-opening (§12 forward look — ONLY after the
  post-TP2-boot DOWN re-pin lands does the sum reach ≈ 118.3 ≤ 125.08; at the shipped-held 110 it
  stays CLOSED, 110+64+6.3 = 180.3 > 125.08) — rides the CUTOVER ticket, recorded only.
- q27 TP2 (§envelope row exists, not on the card); IQR-V4 adoption; the DRA alternative lane
  (§6, recorded not planned); the runner-model literal; Grafana.
- Host mutations of any kind (OCuLink path, ReBAR, kernel, power cap) — owner-side; the repo
  side is NOT blocked by them.
- Any sync during the owner's parked swap window (fn 0 / q27 1 / strata 0 live; the don't-sync
  law in `.agents/notes/radiance-q27-boot.md:151-159`). Git resting state stays fn 1 / q27 0;
  TP2 decides NEW git resting state values, not live scale.
- Chart.yaml version hand-bumps (release.yaml owns; charts/radiance stays 1.0.0).

## Key pinned facts (authority: cf-143 RESEARCH + card doc, live facts from EXPLORE.md)
- Pool string is **`amd.com/gpu-r9700-1`** — `amd.com/gpu-ai-pro-r9700` is the PRE-D24 stale
  name; every chunk string uses the canonical constant sites (bash twin
  `tests/notes/radiance-tp2.sh:33-35` + `amd_gpu_testlib.py`; one edit site per language).
- Live node `ai-gpu`: `amd.com/gpu-r9700-1: "2"` (plugin witness: card1 `c3:00.0` + card2
  `c7:00.0`, both 7551 rev C0, + APU `c8:00.0` 1586). Gate-(a) repo-side prerequisite satisfied
  WITHOUT a table edit; owner sysfs/rocminfo receipts still wanted (C03 in-run rocminfo gate;
  the C04 leg rides the deferred follow-up card — OQ-D ruling).
- TP2 serve profile (doc §7, verbatim-corrected): `--tp 2 --tp-wire wht6 --max-num-seqs 8
  --max-model-len 200000 --placement expert_tiered --host-pool-mib 12288 --gpu-headroom-mib 96
  --kv-cache-dtype fp8 --prefix-cache-mib 4096 --num-speculative-tokens 3
  --max-num-batched-tokens 2048` + retained `--checkpoint-interval 4096`, `--ngram-placement
  disk`, `--served-model-name qwen3.8-flash-next-radiance`, `--host ::`, `--port 8000`,
  `--model` anchor. `--kv-resident` OUT (mutual exclusion: tier back, mirror gone).
  `--expert-vs-cache-ratio` is STALE — never ship; `28.07`/`54.7 GB/s` direction-only.
- fn TP2 host pins: **`guaranteedMemoryGi` HELD at 110** (OQ-B ANSWERED, owner ruled "Hold 110,
  re-pin after the print", 2026-11-21 — the draft-shipped 48 is REJECTED, P11 supersedes P03). The
  printed-budget class ≈ 30–35 GiB (2×12288 pool + 4 tier + slots + tables, §R8-Q5) with the
  llmkube witness req 40 / lim 48 stays RECORDED as the bracket for the eventual re-pin; the DOWN
  re-pin to that class is a POST-TP2-BOOT OWNER-RECEIPT leg, never a shipped value. The first-boot
  PRINT is the budget authority (D30(2) printed-budget law applied to the TP2 topology; same
  discipline as D29/D30; 110 remains the single-card superset held until the print — §12).
- Claim math: requests==limits integer pair, extended resource, Guaranteed law; TP2 flips the
  CHART pair to `"2"` (chart-side — D26: overlays ADD/UPDATE, never REMOVE; an overlay UPDATE of
  the same key merges fine, and that is how q27 keeps its 1).
- Scheduling arithmetic at TP2 with memory HELD at 110 (node 125.08 GiB allocatable): fn 110 +
  router 4.125 + system 1.158 = 115.3 ≤ 125.08 ✓; beside-fn q27 does NOT fit RAM-side at the
  held 110 (110+24+4.125+1.158 = 139.3 > 125.08 — it would fit only at the post-re-pin class,
  48+24+4.125+1.158 = 77.28; shape B is moot under the OQ-A ruling and q27-TP2 is out of scope —
  the number is arithmetic context only), and shape A's claim-2 makes q27 Pending while fn is UP
  anyway — pool-arithmetic, not RAM; pod-swap law survives (fn DOWN first,
  then q27 UP — D54(1); under shape A that is now claim-math, annotate not rewrite).
- `charts/radiance/values.yaml` carries ONE chart, TWO releases (D56(1)); the q27 pod truth
  lives in the service `radiance-q27:` subtree (services/gpu-ai/prod/values.yaml:876-1036) —
  the subtree's resources currently hold ONLY the 24Gi memory pair (:965-968), cpu+claim
  chart-inherited. C01 adds the explicit claim pin.
- Parity pins binding C01's same-wave set: runbook T2 = the EXACTLY-ONE args block in
  `.agents/notes/radiance-on-target-acceptance.md` must multiset-equal the chart serveArgs and
  pin the scalars BOTH sides (43000/200000/8/110 today → TP2 values; under the OQ-B ruling the
  memory scalar's TP2 value IS the held 110 — only hostPoolMib/tp/chunk move this wave, P11);
  `testlib.SCALARS/
  FULL_PROFILE/ABSENT_FLAGS` set-equality; `test_q27_lane` rendered pair `claim 1`
  (:161-172); `test_resource_name_identity` fn claim leg. Peers/evidence/catalog/golden are
  TP2-inert (served ids, timeouts, floors, contexts unchanged — no peer or model-key move).
- Enumeration law (doc §4): strata `rocrVisibleDevices "0"` / strix `"1"`
  (`charts/llama-swap/values.yaml:1504,1517`) name HOST POSITION, and position moved when card
  2 landed — `rocminfo` receipt gates any re-pin (C03, OQ-E). radiance itself is immune
  (plugin Allocate injects devices, env absent by C02 absence law).
- D21 shield / gpu cluster (OQ-D): the gpu cluster stays external single-naming 1.31.0.9 BY
  DESIGN; extending product naming there is "part of this card WHEN a second card is planned" —
  true for ai-gpu now, but the gpu BOX's card (device,revision) pair is UNKNOWN (8 GiB class);
  with the minimal table it would fall back to bare `amd.com/gpu` → C04 (DEFERRED out of this run
  by the OQ-D owner ruling, 2026-11-21 — see the chunk table) ships ONLY behind the
  owner sysfs receipt (+ likely a table row ADD + the APU-rows-carry twin + runbook step-0
  receipts re-run at the new row count + the D21 shield test legs moving).

## Commands (validation battery — every agent exports PATH first)
`export PATH=$HOME/.local/bin:$PATH` (without it helm-guarded pytest silently mass-skips).
- chart suites (per-directory, basenames duplicate across suites):
  `python3 -m pytest charts/radiance/tests -v` · `python3 -m pytest charts/amd-gpu/tests -v` ·
  `python3 -m pytest charts/llama-swap/tests -v`
- note/service contracts: `bash tests/notes/radiance-runbook.sh` · `bash tests/notes/radiance-tp2.sh` ·
  `bash tests/notes/radiance-q27-boot.sh` · `bash tests/notes/radiance-host-tuning.sh` (IMMUTABLE
  witness — must stay green untouched) · `bash tests/services/amd-gpu-naming.sh` (C04-only — C04
  DEFERRED out of this run (OQ-D owner ruling), this leg belongs to the follow-up card) ·
  `bash tests/pipeline-models/surface.sh` (M7/M8 witnesses — unchanged)
- plain validation: `helm lint charts/radiance` ·
  `helm template radiance charts/radiance --set domain=spencerslab.com --set clusterName=gpu-ai` ·
  `helm lint charts/amd-gpu && helm template charts/amd-gpu` (C04 — DEFERRED out of this run
  (OQ-D owner ruling), not a wave-1 leg here) · service-overlay extraction
  legs per `.github/workflows/radiance-render-tests.yaml:57-77`
- witnesses: fn render claims `{amd.com/gpu-r9700-1: "2"}` pair, q27 render claims `: "1"` pair
  at 24Gi; `grep -rn "gpu-ai-pro-r9700"` = zero live claim-shaped hits (law-carriers/deferred
  history only, per the C08 zero-stale idiom); no `OVERRIDE_*` sentinel in renders;
  `npx aislop ci --changes` clean.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | TP2 core flip — chart profile + claim 2 + memory HOLD (110; DOWN re-pin deferred post-boot) + q27 overlay claim pin + same-wave test/runbook re-pins | L | 1 | [] | the serveArgs/claim/scalar change forces testlib SCALARS/FULL_PROFILE/ABSENT_FLAGS, test_q27_lane, test_resource_name_identity AND the runbook's byte-equality args block into ONE cohesive wave (parity pins; cf-143 C08 precedent) |
| C02 | Notes layer — TP2 doc dated SHIPPED annotations + q27-boot pool=2 arithmetic + tp2.sh T3 re-pin | S | 2 | [C01] | the annotations quote the SHIPPED TP2 numbers (profile, scalar, claim counts) — they must exist first; annotate-never-rewrite law keeps the doc structure T1/T2-green |
| C03 | strata enumeration re-pin (OQ-E) — VALUES-GATED | S | 1 | [] | independent (different chart, different owner); runs ONLY after the owner `rocminfo` receipt names the new indices (the coordinator collects the paste at C03's turn — OQ-E ruling); honest no-op close if the receipt says nothing moved |

> **C04 REMOVED from this plan's table and waves by the OQ-D owner ruling ("Defer C04 to a
> follow-up card", 2026-11-21, fold round).** It does NOT execute in this run. The full spec —
> including the owner sysfs `(device,revision)` receipt prerequisite — is preserved in
> `chunks/C04.md` under a dated supersession note for whoever cards it. NO ONE creates that
> follow-up card in this run (the card does not check "Follow-up cards created"); the deferral
> rides this plan's Deferred section + the final summary comment, and carding it is the OWNER's
> leg.

## Wave order
> FOLD 2026-11-21 (OQ-D owner ruling): C04 is deferred out of this run (see the note under the
> chunk table); wave 1 = C01 + C03-at-receipt; wave 2 = C02.

1. C01 (the ticket's core) · C03 runs WHEN its owner rocminfo receipt lands — the coordinator
   collects the paste at C03's turn (OQ-E ruling); if the receipt has not landed by the final
   review, the chunk closes DEFERRED (recorded, not red) — the owner's call, per the card's own
   gate-(a) law.
2. C02 (after C01's numbers are real).
The batched question round is ANSWERED (2026-11-21 — owner approval "run all waves", P12;
folded above). No further owner pause until Final Review (both are
HITL stages for this card).

## Landing shape (Deployment is a checked stage — pipeline-push-pr discipline)
- Dev commits land locally on branch `cf-144-feat-radiance-tp2-expansion` (coordinator is the
  sole committer). **Pushing the branch + opening the PR are owner-gated legs** — never main,
  never force, never agent-initiated. Post-merge ArgoCD applies; the on-target acceptance
  (runbook step-0 TP2 receipts → fn TP2 boot → startup-report capture under load → rocminfo →
  P2P/power-cap measurements) is OWNER-executed.
- Parked-window truth: the live swap (fn 0 / q27 1) survives until the owner syncs (don't-sync
  law). At the held 110 the RAM math still fits fn alone (110 + 4.125 + 1.158 = 115.3 ≤ 125.08) — the
  binding constraint in a parked window is GPU claim-math, not RAM: fn TP2 needs 2 of the 2-card
  pool, so with q27 still UP at claim-1 the fn pod Pends until q27 scales down. The swap
  discipline (fn DOWN first, then q27 UP) becomes claim-math under shape A; sync timing is the
  owner's call, git resting state stays fn 1 / q27 0. Recorded in C01's notes.
- Receipt-gated numbers (the memory DOWN re-pin from the held 110 to the printed class,
  prefix-tier survival, shm 2Gi two-rank envelope) move by a fresh owner ruling after the first
  boot, D29-shaped — never a pre-emptive softening, never a silent retarget. The held 110 is not
  a softening: it ships the existing superset untouched until the print makes the re-pin a
  witnessed value (P11).

## Open questions & rulings (batched round ANSWERED 2026-11-21 — owner's chosen strings recorded per entry; fold-only round, no re-planning)
- **OQ-A (HEADLINE, topology fork — changes the chunk graph) — ANSWERED: "A — fn TP2, claim both
  cards (Recommended)" → CONFIRMED, shape A stands.** Draft framing kept for the record: shape A
  (fn TP2 claiming both
  cards, q27 stays pod-swap — shipped guess) vs shape B (fn TP1 + q27 beside-fn co-residency —
  pool=2 unlocks GPU-side, RAM-blocks until fn's 110 re-pins ≤ ~90 class; also needs a D29-shaped
  memory ruling and conflicts with the card title's TP2). Impact: B rewrites C01 (no serveArgs
  change, different scalar, q27 resting replicas 1) and strands `--tp-wire`/P2P receipts.
  Recommendation: A first; B remains arithmetically open at ~48+24+5.3 = 77.28 only if fn were
  later re-ruled TP1 — not this card's shape. (That 48 was the draft's rejected ship class —
  context only after the OQ-B ruling; B moot under A.)
- **OQ-B (fn TP2 guaranteedMemoryGi) — ANSWERED: "Hold 110, re-pin after the print" → OVERRIDE of
  the draft-shipped 48.** C01 ships the TP2 flip with `charts/radiance` `guaranteedMemoryGi` KEPT
  at 110; the DOWN re-pin (~30–35 GiB printed class, llmkube lim-48 witness stays recorded) is a
  POST-TP2-BOOT OWNER-RECEIPT leg, not a shipped value — the first-boot PRINT is the budget
  authority (D30(2) printed-budget law applied to the TP2 topology). Recorded P11 (supersedes
  P03's ship-48). Draft text kept for the record: shipped 48 (llmkube lim class; ~30–35 printed
  estimate +
  4 slack law). Alternative: keep 110 until the TP2 boot prints its budget, then re-pin DOWN
  (strictest "never pre-emptive softening" reading — costs: 110+q27-24 still fits RAM but the
  §12 co-existence arithmetic stays dead until the second edit). Impact: one scalar + its test
  legs either way. Owner ruling, D29-shaped.
- **OQ-C (serveArgs TP2 exact set) — ANSWERED: "Confirm as specced (Recommended)" → stands.**
  Draft: shipped the §7 recipe + retained checkpoint-interval /
  ngram-disk / served-name / host:: / port; kv-resident OUT, prefix 4096 IN, chunk 2048,
  tp-wire wht6; test session re-derives FULL_PROFILE set-equality + ABSENT polarity flip.
  Impact: none beyond confirmation — flag any flag the owner wants added/dropped.
- **OQ-D (gpu-cluster naming extension IN this ticket?) — ANSWERED: "Defer C04 to a follow-up
  card" → OVERRIDE: C04 does NOT execute in this run.** Removed from the chunk table and wave
  order; spec + sysfs-receipt prerequisite preserved in `chunks/C04.md` under a dated supersession
  note; NO ONE creates the follow-up card in this run (the card does not check "Follow-up cards
  created" — the deferral rides the plan's Deferred section + the final summary comment, OWNER's
  leg). Draft text kept for the record: card says part-of-this-card when a
  second card is planned (true now), but it is gated on an owner sysfs receipt of the GPU BOX's
  card pair (unknown; minimal-table fallback trap). Shipped guess: C04 rides this ticket
  receipt-gated, and if the receipt doesn't land in-run it defers to a follow-up card. Impact:
  C04 executed here vs new card; zero effect on C01–C02.
- **OQ-E (strata enumeration re-pin urgency) — ANSWERED: "Receipt now, honest no-op close OK
  (Recommended)" → C03 stays receipt-gated; the coordinator collects the rocminfo paste at C03's
  turn.** Draft text kept for the record: card 2 shifted host GPU indices today; strata
  renders replicas 0 live, so nothing is mis-bound NOW, but any strata restore-back after this
  lands binds silicon by stale POSITION (the 307/310 crash-loop class). Shipped guess: owner
  `rocminfo` receipt first, C03 re-pins `rocrVisibleDevices`/strix only if indices moved.
  Impact: C03 executed here vs deferred; strata scale-up meanwhile is owner-risk either way.
- **OQ-F (q27 under fn-TP2) — ANSWERED: "Accept pod-swap + claim-1 pin (Recommended)" → stands.**
  Draft: shipped: q27 stays pod-swap at replicas 0, overlay EXPLICITLY
  pins claim 1 (chart flip to 2 would otherwise strand q27's inheritance at 2), boot note
  annotated (swap now claim-math, not just arithmetic). Alternative ruling q27-TP2 is out of
  scope on the card. Impact: none — recorded so the owner can veto silently.
- **OQ-G (shm 2Gi two-rank envelope) — ANSWERED: "Accept 2 GiB + receipt (Recommended)" →
  stands.** Draft: EXPLORE §2 calls TP2 two-rank shm/host staging
  "receipt-land". Shipped guess: keep 2Gi, list it as a first-boot receipt item in the
  runbook; move only if the boot contradicts. Impact: one persistence value + contract legs.
- **Approval — ANSWERED: "Approve — run all waves (Recommended)".** Fold recorded; the flip to
  `plan_status: approved` is the COORDINATOR's own act (this fold round left it `draft`),
  provenance in DECISIONS P12.

## Risks / assumptions
- Git-vs-live divergence is law: this plan changes git resting state only; the owner's parked
  swap survives until they sync (don't-sync law).
- TP2 relieves card-side contention, NOT the RAM dance (doc §11.8/§12: 110+64+6.3 > 125.08 was
  the single-card truth; the TP2 re-pin re-opens the co-existence arithmetic only in the
  CUTOVER ticket's decision).
- The rejected draft-48 assumed printed-budget ≈ 30–40 GiB at TP2 pins; under the OQ-B ruling
  NOTHING ships at that class — fn holds 110 until the first boot PRINTS its budget, then the
  DOWN re-pin lands as an owner-receipt leg (P11). The OOM-at-64 precedent (D29: engine printed
  71.04 > cgroup) is the class being guarded at the re-pin; the receipt, not this plan, finalizes
  sizing.
- `--tp-wire wht6` appears nowhere in today's args — pure add, verified verbatim against
  flashnext.yaml/HF card per RQ4; the engine binary owns validation at boot.
- C04 (DEFERRED out of this run — OQ-D owner ruling) carries its own off-parity fixture risk:
  D21's "moves ZERO lines" today MOVES if the shield flips — that leg re-baseline is the
  deferred chunk's own test-wave duty, enumerated in `chunks/C04.md` for the follow-up card.

## Deferred (post-fold 2026-11-21)
- **C04 — gpu-cluster product-naming extension (OQ-D "Defer C04 to a follow-up card")**: does NOT
  execute in this run; removed from the chunk table and wave order. Its full spec + owner sysfs
  `(device,revision)` receipt prerequisite live in `chunks/C04.md` for whoever cards it. NO ONE
  creates that follow-up card in this run (the card does not check "Follow-up cards created");
  carding it is the OWNER's leg, riding this section + the run's final summary comment.
