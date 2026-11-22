# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives
rejected, why.

## Conventions
- Pool string law (D24 carry-over): `amd.com/gpu-r9700-1` is the ONLY live name;
  `amd.com/gpu-ai-pro-r9700` appears nowhere claim-shaped (pre-D24 stale). Constant sites:
  bash twin `tests/notes/radiance-tp2.sh:33-35` + `charts/amd-gpu/tests/amd_gpu_testlib.py` +
  `charts/radiance/tests/radiance_testlib.py` — one edit site per language.
- `export PATH=$HOME/.local/bin:$PATH` before any helm-backed run (silent mass-skip law);
  pytest runs per-directory.
- Doc-edit law: annotate, never rewrite (dated SHIPPED/HONORED markers; cf-143 §9/§11 idiom) —
  TP2 note edits must keep `tests/notes/radiance-tp2.sh` T1 (structure) and T2 (citation
  resolver) green; T3 needles re-pin in the same commit as the prose they govern.
- Receipt law (D28(6)/D29/D30): sizing ships at the pin-set recompute, the first-boot printed
  budget finalizes it; never a pre-emptive softening, never a silent retarget — a correction is
  a DECISIONS-shaped owner ruling plus the one-scalar edit.
- No Chart.yaml version hand-bumps (release.yaml owns); ExternalSecret+Bitwarden only (no
  secret work in this ticket — trio law's keyless D8/D54(2) skip persists); ArgoCD applies
  everything, no kubectl from repo; git law: never advance main, push+PR owner-gated
  (pipeline-push-pr).

## Decisions
- 2026-11-21 coord P01 (**RESEARCH DECISION — no agent-research round**): the scout (EXPLORE.md)
  + the cf-143 folder's RESEARCH.md (RQ4, §R6, §R7, §R8-Q5) resolve every figure in this ticket
  to on-disk/live evidence; the scout issued no Needs-research escalation; the remaining
  unknowns are owner-executed on-target receipts (`rocminfo`, per-BDF sysfs pairs, boot startup
  reports under load, P2P bandwidth, power cap) — those are acceptance-runbook legs, NOT web
  research. Alternative rejected: a storm round re-deriving figures that already carry
  citations and live witnesses.
- 2026-11-21 plan P02 (**SHAPE FORK (OQ-A) taken as best guess: shape A — fn TP2, one pod
  claiming both cards**): the card title says TP2; doc §11 step 5 lists fn-TP2 first; shape B
  (fn TP1 + q27 beside-fn) conflicts with the tensor-parallel expansion itself and additionally
  needs a D29-shaped fn-memory ruling down from 110 (≤ ~90 class for the 1+1 RAM envelope).
  Chunk graph is built on A; if the owner rules B, C01 is re-planned (serveArgs untouched,
  scalar re-pin + q27 resting flip). Headline item of the batched round.
- 2026-11-21 plan P03 (**fn TP2 memory best guess: `guaranteedMemoryGi: 48` (OQ-B)**): TP2 pin
  set ≈ 24 (pool 2×12288) + 4 (prefix tier) + slots/tables ≈ 30–35 GiB printed class (§R8-Q5);
  llmkube production witness req 40 / lim 48; +4-slack law ⇒ 48-class ship. Alternative
  rejected: keep 110 until the TP2 boot prints — costs a second owner-ruling round and leaves
  the §12 arithmetic re-open (48+64+6.3≈118.3) undocumented in git; kept 110 also violates doc
  §11.5's own "Guaranteed memory recomputes at the TP2 pin set" step. Receipt gate stands: the
  first boot's printed budget confirms or moves the scalar UP (never below printed+4).
- 2026-11-21 plan P04 (**serveArgs TP2 set (OQ-C)**): §7 verbatim recipe (`--tp 2 --tp-wire
  wht6 --host-pool-mib 12288 --prefix-cache-mib 4096 --max-num-batched-tokens 2048` …) PLUS the
  retained shipped `--checkpoint-interval 4096`, `--ngram-placement disk`,
  `--served-model-name qwen3.8-flash-next-radiance`, `--host ::`, `--port 8000`; `--kv-resident`
  OUT (tier/mirror mutual exclusion — the ABSENT_FLAGS polarity flips: prefix-cache becomes
  absent-banned and kv-resident joins the absence list for fn); `--expert-vs-cache-ratio`
  stale-banned (never ships). Test session re-derives FULL_PROFILE set-equality from this.
- 2026-11-21 plan P05 (**q27 stays pod-swap under shape A, with an EXPLICIT overlay claim pin
  (OQ-F)**): the chart pair flips to 2; the `radiance-q27:` subtree resources today carry ONLY
  the 24Gi memory pair and inherit cpu+claim — after the flip, inheritance would strand q27 at
  claim 2. Fix: explicit `amd.com/gpu-r9700-1: "1"` in both q27 requests and limits (D26 law:
  overlays ADD/UPDATE the same key, never REMOVE — an UPDATE is lawful). `test_q27_lane`'s
  rendered-pair leg (:161-172) re-pins to the overlay-pinned truth. The 502-idle sentence and
  the fn-DOWN-first law survive; the boot note annotates that the swap is now claim-math
  (fn-TP2 holds both cards) rather than pool-capacity-1.
- 2026-11-21 plan P06 (**OQ-D → conditional C04, receipt-gated, rides this ticket**): the card
  says extending product naming to the gpu cluster is part of this card WHEN a second card is
  planned — true (ai-gpu's card 2 is live). But the gpu BOX's card (device,revision) pair is
  UNKNOWN and the minimal patched table would silently bare-fallback it; so C04 executes only
  after the owner's sysfs receipt, and defers (recorded, not red) to a follow-up card if the
  receipt doesn't land in-run. Rejected: pre-committing the shield flip without the receipt
  (stranded-claimant class) and hard-deferring the work item while the card names it.
- 2026-11-21 plan P07 (**OQ-E → conditional C03, rocminfo-gated**): card 2 shifted host GPU
  enumeration today; strata binds silicon by POSITION (`rocrVisibleDevices "0"`, strix `"1"`)
  and would mis-bind on any restore-back — but strata renders replicas 0 live, so nothing is
  broken NOW. Re-pin only on the owner rocminfo receipt; values-key edits only (never the
  template, C04-runbook idiom).
- 2026-11-21 plan P08 (**chunk cohesion — C01 is ONE wave by parity pins, not file count**):
  the serveArgs/claim/scalar flip byte-couples charts/radiance/values.yaml ↔
  radiance_testlib.{SCALARS,FULL_PROFILE,ABSENT_FLAGS} ↔ test_serve_args/test_resource_name_
  identity/test_q27_lane ↔ the runbook's EXACTLY-ONE args block (T2 multiset equality + scalar
  pins BOTH sides) ↔ tests/notes/radiance-runbook.sh needles ↔ the q27 overlay claim pin.
  Splitting any of these lands a red tree; cf-143 C08 precedent. Docs layer (C02) splits out
  because a reviewer can reject owner-facing prose while approving plumbing (C15/C16 precedent).
- 2026-11-21 plan P09 (**catalog/peers/evidence/golden are TP2-inert**): served ids, peer hops,
  timeouts, priority floors, limit.context all unchanged (fn serves the same id at the same
  context ceiling on two cards; q27 unchanged). The `{strata,radiance,radiance-q27}` peers-key
  wave list is NOT re-pinned — no third/fourth peer key is minted by this ticket. If the owner
  later rules q27-TP2 or shape B resting replicas, that's a fresh wave with its own re-pins.
- 2026-11-21 plan P10 (**landing = pipeline-push-pr**): coordinator commits chunks locally on
  `cf-144-feat-radiance-tp2-expansion`; branch push + PR + merge + sync + on-target acceptance
  are owner-gated legs; no agent-initiated main advance ever; the parked swap (fn 0/q27 1/
  strata 0) is git-vs-live divergence by law, and the first TP2 sync's claim-math (fn needs 2
  of 2 ⇒ q27 must be DOWN first) is stated in the plan and the boot note, not mitigated in
  GitOps.
- 2026-11-21 owner P11 via fold (**OQ-B OWNER RULING — fn TP2 memory: HOLD 110, re-pin after the
  print; the draft-shipped 48 is REJECTED**): supersedes P03's ship-48 best guess. C01 ships the
  TP2 flip with `charts/radiance` `guaranteedMemoryGi` KEPT at 110; the DOWN re-pin to the
  printed class (~30–35 GiB; the llmkube production witness req 40 / lim 48 stays RECORDED as the
  bracket) becomes a POST-TP2-BOOT owner-receipt leg, never a shipped value. Owner's reason: the
  first-boot PRINT is the budget authority — the D30(2) printed-budget law applied to the TP2
  topology; shipping an estimate would put the plan ahead of the witness it defers to (holding
  the superset is the honest posture until the print exists). Fold consequences: testlib SCALARS
  and the runbook T2 memory needles stay pinned to 110 this wave; the claim pair renders
  `memory: "110Gi"`; the §12 co-existence re-open (~118.3 ≤ 125.08) is CONDITIONAL on the
  post-boot re-pin landing — at the held 110 it stays closed (110+64+6.3 = 180.3 > 125.08).
- 2026-11-21 owner P12 via fold (**APPROVAL PROVENANCE — batched round answered, plan approved by
  owner word**): the batched question round RAN 2026-11-21 and the owner answered — OQ-A "A — fn
  TP2, claim both cards (Recommended)" CONFIRMED (P02's shape-A graph stands); OQ-B → P11; OQ-C
  "Confirm as specced (Recommended)" stands (P04); OQ-D → P13; OQ-E "Receipt now, honest no-op
  close OK (Recommended)" stands (P07) with the coordinator collecting the `rocminfo` paste at
  C03's turn; OQ-F "Accept pod-swap + claim-1 pin (Recommended)" stands (P05); OQ-G "Accept
  2 GiB + receipt (Recommended)" stands. "Approve — run all waves (Recommended)" — the flip of
  `plan_status` to approved is the COORDINATOR's own act (this fold round only encodes the
  rulings; the folder was left `draft` at the owner's pipeline convention).
- 2026-11-21 owner P13 via fold (**OQ-D OWNER RULING — C04 leaves this run: "Defer C04 to a
  follow-up card"**): supersedes P06's "conditional C04 rides this ticket". C04 does NOT execute
  in cf-144 — removed from the plan's chunk table and wave order; STATE.json records it
  `deferred`; the sysfs `(device,revision)` receipt prerequisite and the full spec stay preserved
  in `chunks/C04.md` under a dated supersession note for whoever cards it. NO ONE creates the
  follow-up card in this run — the card does not check "Follow-up cards created"; the deferral
  rides the plan's Deferred section + the final summary comment, and carding it is the OWNER's
  leg.

- 2026-11-21 coord P16 (**C03 ORACLE-LEG CONFLICT — mechanical re-scope routed to the test
  lane**): the C03 values move (strix "1"→"2", receipt P15) is inherently one render line at
  odds with cf-143's `test_strata_render_byte_equal_to_pre_ticket_baseline` (frozen pre-ticket
  oracle byte-pins the strix `ROCR_VISIBLE_DEVICES=1` env injection; dev proved the divergence
  is EXACTLY that one line — profile/Deployment/Service stay equal). The leg's INTENT (strata
  docs unchanged by cf-144 beyond the receipt-driven enumeration) survives its re-scope; the
  letter cannot coexist with a correct C03. Route: silent mechanical repair to the author
  session (ses_e004c659…) — expected shape per the chunk's own "golden ONLY if the render
  moves" clause: a dated cf-144-sanctioned-divergence carve-out for exactly the strix ROCr
  line, zero softening elsewhere; re-pin proof = the whole-directory suite, not a three-file
  simulation (dev's friction lesson: designed-red sets cannot reach era-oracle legs).
- 2026-11-21 coord P17 (**receipt retires the enumeration question, NOT the runbook posture**):
  the rocminfo receipt settles host GPU ordinals; the strata runbook's on-target [VERIFY]
  posture (live pod-visible re-check of rocrVisibleDevices after syncs) stays OPEN as an owner
  leg — P15's "formal gates remain" line governs. Notes stale-index cells (doc §4-era "1"/
  dGPU-first story): C02's TP2-SHIPPED annotation already covers the doc sweep-row posture;
  further dated annotation only where a needle can pin it — no unbound prose churn (audit
  routed to the test lane with the oracle re-scope).

## Deferred
- Shape B co-residency (OQ-A answer-dependent; P02).
- Strata restore-back co-existence arithmetic at the TP2 class (~118.3 ≤ 125.08 re-opens) —
  CUTOVER ticket decision (doc §12; P03 records the number only).
- q27-TP2 row (envelope exists, not on the card); IQR-V4 pack adoption; DRA alternative lane.
- shm 2Gi two-rank envelope + prefix-tier survival under load — first-boot receipt items
  (OQ-G; runbook capture list carries them).
- ~120 W OCuLink power-cap question — owner measurement in the acceptance run (doc §3 OPEN).
- 2026-11-21 fold: C04 gpu-cluster product-naming extension — DEFERRED BY OWNER out of this run
  to a follow-up card (OQ-D ruling, P13); spec + sysfs-receipt prerequisite preserved in
  `chunks/C04.md`; carding is the owner's leg, nothing creates it in-run.

## Coordinator round records
- 2026-11-21 coord P14 (**C02 RIDER LAWFUL-IN-WAVE**): C01 review r1's two non-blocking nits were
  folded into C02's note pass as coordinator-directed riders (N1: dated qualifier appended inside
  the acceptance-note sizing-row paren, original wording byte-identical; N2: missing comma
  restored at services/gpu-ai/prod/values.yaml:883, comment-only). C02 review r1 ruled both
  lawful in-wave — the executed form matches its own round-1 fold suggestion verbatim,
  byte-preservation proven (933/934 lines untouched), every needle stayed green unedited.
  Audit line recorded per the reviewer's recommendation.
- 2026-11-21 coord P15 (**C03 RECEIPT LANDED — VERDICT MOVED (strix leg)**): owner pasted the
  ai-gpu host `rocminfo`. GPU-agent ordinals: 0=R9700 (Chip ID 0x7551 Rev 1, Uuid
  GPU-f14f913b0a98ad15, BDFID 49920), 1=R9700 (0x7551 Rev 1, Uuid GPU-d34663795f09a76f,
  BDFID 50944), 2=APU gfx1151 8060S (0x1586 Rev 0, BDFID 51200, Memory Properties APU).
  Shipped strata primary `rocrVisibleDevices: "0"` STILL names an R9700 — hide-the-APU intent
  kept, no move. Shipped strix lane `rocrVisibleDevicesByModel` value `"1"` now names the
  SECOND R9700, not the APU (the second discrete card inserted ahead of it) — ordinal 2 is the
  APU today. Mechanical re-pin route engaged per the receipt law: testlib ROCr constants
  (`ROCR_STRIX` — the one site) + the values pair in ONE wave; the equality arm would otherwise
  correctly block any half-move. Primary leg closes as an honest no-op; strix leg re-pins "1"→"2"
  with the dated rocminfo-provenance sentence the suite's one-way arm demands.
