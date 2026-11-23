# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives
rejected, why.

## Conventions
- D-number namespace: THIS ticket's decisions occupy D1 and forward; any citation to another
  ticket's decision (cf-143/cf-144/… the parent ticket `feat-radiance-multi-instance`) MUST
  carry its ticket prefix — bare `D47` means the PARENT's D47 here, because this file has no
  D47 of its own. (The parent's D1-D47 are cited as `parent-D<n>` or with the cf- prefix.)
- Doc-edit law: annotate, never rewrite (dated markers; the cf-144 D48 idiom — a moved or
  corrected line keeps its original citation form; a factual correction is a dated annotation
  with the evidence cite, never a narrative rewrite). Applies to every prose carrier this
  ticket touches (values WHY comment, roster note, boot note, NOTES.txt).
- Test-authority law (parent D30 carry-over): test-file edits are NEVER assignable to dev; a
  test re-pin wave precedes the dev round it greens. C01 (re-pin by ruling) and C03's
  pre-authored split (if triggered) both follow it.
- `export PATH=$HOME/.local/bin:$PATH` before any helm-backed run; pytest per-directory.

## Decisions
- 2026-11-22 human, ruling **D1 (RULING 1 — raise 27b TP2 `RADIANCE_MAX_MODEL_LEN`
  200000 → 262144)**: the two 27b lanes' context bound moves to the TRAINED ceiling.
  Evidence (RESEARCH V1/V3, S1-S3/S10): 262144 is the pack card's "262,144 tokens trained"
  (S1), `config.json max_position_embeddings: 262144` with no `rope_scaling` (S3); the fit
  is MEASURED — 9.68 GiB/card weights, Wilde measured 20.04 GiB KV/card fit-to-available:
  "Full 262144 fits with ~100 MiB of headroom per card" (S10); the 262144 pool is 16.0 GiB
  at the ~64 KiB effective per-token cost (V3). Scope: the two 27b env entries only (q27
  :1367, q27-tp2 :1588); fn :1121 and flash-tp1 :1495 stay 200000 pending OQ1. 200000 was
  TRANSCRIBED (cf-143 D54(1) owner recipe verbatim; the upstream compose profile S8) and
  never measured on our node (V4) — so the move is a ruling, not a correction.
  Alternatives rejected: keep 200000 (the tested bound — but no receipt exists for it either,
  and the 27b card's trained ceiling is the model's own spec); the 1M/YaRN path (S7: only
  factor 2, to 524288, is engine-validated on this model — Deferred with its revisit
  trigger).
- 2026-11-22 human, ruling **D2 (RULING 2 — ATTEMPT TP1 too; the boot print adjudicates)**:
  stated AGAINST the coordinator's recommendation, which is recorded here with the
  coordinator's dissent in full. The coordinator would have held TP1 at 200000: V3/S10
  PREDICT a single 32 GB card caps measured fit near ~199k (Wilde's 12.46 GiB pool →
  199,472 tokens at the ~64 KiB effective cost), and V2/S6/S7 say the engine's behaviour is
  fit-to-available with a WARNING — no crash, no refusal (Wilde's 263k probe) — so a
  non-fit TP1 will likely boot and serve on a TRUNCATED pool rather than fail loudly (the
  warn-not-refuse hazard the ruling accepts). Both outcome paths are pre-agreed in the plan:
  **Outcome A** (boots and serves with the pool funding the 262144 worst case — the `kv:
  pool backs N%` line covers a full 262144 session; the arithmetic was wrong, e.g. the
  single card pays 32 KiB trunk-only with no drafter-cache cost): keep the raise; the
  confirmation is recorded in C04. **Outcome B** (OOM / refusal / truncation — the print
  under-funds the worst case, shows the ~199k cap, or serves truncated): C03 reverts TP1
  to 200000 via the pre-authored contract (test re-pin wave splits the constants — `Q27_PROFILE`
  keeps 200000 for TP1, `q27_tp2_profile()` gains the explicit `--max-model-len 262144`
  override, `Q27_CTX` becomes the per-lane pair — then the dev round makes the one env edit,
  then DECISIONS records the refuting print as the receipt). The TP2 lane stays 262144
  either way (V3 fit, measured). Executor of C03: a follow-up dev session under the
  coordinator, owner-triggered by the refuting print, test re-pin first (parent-D30). The
  32-vs-64 KiB question (RESEARCH open q1/q3) rides on the print's VRAM-split +
  pool-backs lines (receipt items 2-3) — the plan is written for both outcomes.
- 2026-11-22 human, ruling **D3 (RULING 3 — WRITE THE CONFIG NOW; receipts after landing)**:
  stated AGAINST the coordinator's recommendation, with the coordinator's dissent recorded.
  The coordinator's position was the cf-143 D28(6) discipline itself — the boot print
  adjudicates, estimates do not; a value re-pin lands only WITH its print — so merging an
  unobserved 262144 defers a print-gated change. The owner overrides, BY OWNER WORD, and
  the relaxation is recorded with its scope: it applies to the CONTEXT BOUND ONLY; the
  memory re-pin (the held 24Gi/110Gi pairs) stays print-gated (D28(6)/parent-D54(4)/P11;
  OQ3 best guess "only on the print"). The accepted consequence — 262144 merges into git
  unobserved — is bounded by the owner's four-part mitigation design, all pre-agreed:
  (a) **PROVISIONAL in place**: the values carry a dated annotation naming the pending
  receipt + the ruling cites, so an unobserved value is visible, dated, and bounded;
  (b) **pre-agreed revert path + executor**: C03 (D2's outcome B);
  (c) **a contradicting print unwinds the merged config by a FORWARD fix commit** — the
  D28(6) one-edit overlay repair (the refuting print quoted as the receipt; a fresh
  DECISIONS line), never a revert of the merge, never history rewriting (OQ5 pre-agreed);
  (d) **a named closing leg**: C04 closes the PROVISIONAL status by dated annotation naming
  the leg/commit that closes it, so PROVISIONAL cannot silently become permanent.
  Alternatives rejected: gate the merge on the print (the owner's rejected position — the
  receipt sequence is a post-merge follow-up leg, never a gate before the config edit);
  merge unmarked (rejected by design (a)). Scheduling exposure is zero in the meantime:
  the lanes rest at `replicas: 0` in git, so the merged config has no cluster effect until
  the owner's scale act (the fn→0 swap discipline, roster note).
- 2026-11-22 plan, ruling **D4 (the parent-D47 ctx pairing law RESTATED, ANNOTATED — never
  rewritten)**: parent-D47 (2026-11-23: `limit.context 262144` family-wide = the trained
  window the client budgets against, the served 200000 stated separately in prose) is
  restated for the raised 27b lanes as a dated ANNOTATION in this file (the D48 idiom —
  the parent's D47 entry is untouched). Restated law: **`trained >= served` per lane,
  EQUALITY LEGAL** — the raised 27b lanes serve 262144 = the 262144 trained ceiling, so
  their pair COLLAPSES to equality (262144 == 262144) while fn and flash-TP1 keep an
  unequal pair (262144 > 200000). Leg consequences: the M9-A2 VALUE half is UNCHANGED (all
  twelve rows 262144 — already true, no edit); the M8-B fn needle is UNCHANGED (fn stays
  200000; its commentary slice already names both figures — verified green); M9-B (key
  sets) and M8-A/A2 (the priority ladder) are UNCHANGED; the M9-A2 PROSE half is re-pinned
  SEMANTICALLY to the per-lane served figures (flash-TP1 200000; q27/q27-TP2 262144
  post-C02) with the both-figures needle preserved and still green; TEST_SPEC §1 gains the
  per-lane served column. The jsonc COMMENTARY is owner-protected (parent-D27: the catalog
  bytes are the owner's) — its stale half is restated by the OWNER's prose leg at C04,
  recorded in C04, not executed by this ticket's dev scope.
- 2026-11-23 human, ruling **D5 (RULING 4 — the raise is EXTENDED to the flash lanes: fn-TP2 AND
  flash-TP1)**, answered at the batched round against the coordinator's recommendation to leave both at
  200000. Recorded dissent (three grounds, so it stays visible and is not re-litigated silently): (i) the
  whole evidence base for 262144 is **27b-specific** (S1-S3 pack card/config.json; S8 upstream's 27b compose
  profile) and **no flash-pack ceiling had been established**; (ii) fn-TP2 is the LIVE default route for
  every tier plus the hourly runner (parent-D16), so this is a second pod roll on the pipeline's own
  critical path; (iii) flash-TP1's profile is a **verbatim cf-143 TP1-era transcription proof** — moving it
  converts a proof into a deviation-with-ruling, and the parent ticket's whole OQ-F value was transcription
  fidelity. **Consequence I acted on rather than executed:** the plan as approved (C01/C02 scoped to two 27b
  env values) no longer describes the work, so `plan_status` stays `draft` and execution is paused pending
  (a) a flash-lane research round (F1-F5: the flash pack's real ceiling, KV bytes/token for the MoE
  architecture, whether fn's 200000 was MEASURED by a boot print rather than transcribed, worst-case pool at
  262144 x `--max-num-seqs 8`, and what upstream recommends for the flash pack), and (b) a plan fold re-scoping
  C01/C02 to four lanes. **The decisive unknown is whether fn's 200000 is measured**: the 27b's was
  transcribed, so extending was guesswork there too — but fn has actually booted repeatedly, so unlike the
  parked 27b lanes a receipt may exist, and overturning a measurement is a materially different act from
  overriding an assumption.
- 2026-11-23 human, ruling **D6**: `max-num-seqs` **stays 8**. It is FORM-fixed (parent-D46
  `FORM_FIXED_FLAGS`), so changing it is one chart edit moving the worst-case pool sizing for ALL FOUR lanes
  at once — which would invalidate the very receipt this ticket exists to capture. Upstream's 32 for the 27b
  pack is recorded as a legitimate future ruling with its own print, not absorbed here.
- 2026-11-23 human, ruling **D7**: held memory (**24Gi** on the 27b lanes, **110Gi** on fn per
  parent-P11's standing hold) moves **only on a contradicting print**, never pre-emptively. Parent D28(6)
  stands: prints price numbers, estimates do not.
- 2026-11-23 human, ruling **D8 (PROVISIONAL closure mechanism)**: the receipt is a **pre-authored single
  command block** that the owner runs once at the scale act; C04 closes PROVISIONAL **only if every item is
  present** and refuses to close on a partial print — the anti-drift half of parent-ruling D49's lesson that a
  gate which can pass on absence is not a gate. (Chosen over my recommendation of owner-captures/C04-records,
  which leaves closure dependent on a human remembering to come back.) The nine-item receipt set comes from
  RESEARCH implication (e); the block is authored in the C01 test wave so the closing gate and the script are
  one artifact, and any lane-count change from D5/D9 lands in that block too.
- 2026-11-23 human, ruling **D9 (RULING 5 — fn-TP2 IS INCLUDED: "Just raise it everywhere. I know the risk.
  Do it.")**, answering the coordinator's second, evidence-backed objection. Recorded as an **informed**
  decision this time, which is what D5 was not: the owner was shown, before ruling, that (i) **fn's 200000 is
  the one MEASURED value in this ticket** — cf-143 D28(1)/D30(1) record the live boot print that priced it
  (`out of memory` at cgroup 64 GiB vs 71.04 GiB observed pinned, "8.0 sessions at 200000"), and that print is
  what the 110Gi hold still rides; (ii) **upstream publishes no 262144 serve shape at all** — across 57 compose
  files every 27b variant and `flashnext.yaml` ship 200000, and the only 262144 anywhere is a **2-session**
  streaming demo; (iii) because Radiance **warns rather than refuses** on a context bound, an under-funded fn
  would not crash — it would **silently serve fewer than 8 concurrent sessions**, the one property a shared
  default route exists to provide; and (iv) fn is at `replicas: 0` by the owner's own scale act, so **no
  receipt for the new value is obtainable until it is back up**.
  Dissent recorded and NOT re-run: the coordinator's position was that a measured value on the live default
  route deserved its print before the edit. The owner accepts the risk; this ruling supersedes D5's pending
  question, and D5's dissent grounds (ii) (live-route risk) survive as **risk accepted**, not resolved.
  NON-NEGOTIABLE consequences the plan must carry, because the ruling is "raise it" and not "unmonitor it":
  (a) fn's value lands PROVISIONAL with the named adjudicator — the `kv: pool backs N% … M full-length
  sessions` line — and **M ≥ 8 is the pass bar**; fewer than 8 admitted sessions at 262144 is a refutation, and
  the revert path is the pre-agreed forward fix, not a live improvisation; (b) the eight-admitted-sessions
  smoke is part of the pre-authored receipt block (D8), so the silent failure mode has a loud check attached to
  it; (c) fn's raise is a **second pod roll on the pipeline's own critical path** (parent-D16: every tier plus
  the hourly runner route through fn), so the roll window is stated to the owner before landing, not after;
  (d) fn-TP2 has **no transcription leg** — only the `FULL_PROFILE` constant moves — so its test-authority
  change is a constant re-pin, while flash-TP1's is the deviation-with-ruling re-pin (D5/F5) and must be
  authored BEFORE the dev edit per parent-D30.
- 2026-11-23 coord-ruling **D12 (the two red notes legs belong to C02's closure, not to a later chunk —
  assigned by name because "C03/C04 territory" is how the parent ticket lost an orphan)**. C02 merged with
  `radiance-runbook.sh` T2 and `radiance-q27-boot.sh` T2 red, both comparing note-side figures against the
  composed vector. Dev's hand-back said "doc + test re-pin wave (C03/C04 territory)" — but C03 is the
  conditional revert leg and C04 is the receipts close, so **no chunk owned them**, which is precisely the
  parent ticket's D32 failure (FRICTION named an owner, no chunk file carried the task, and a false statement
  nearly survived the ticket by nobody's decision). Assignment: the **doc half** is a C02 follow-up dev round
  (dispatched, `radiance-on-target-acceptance.md` + `radiance-q27-boot.md`), the **test half** is the test
  session's re-pin, and **C02 review does not start until both legs are green.** Consequence I am owning: I
  committed C02 with two known red legs. Defensible as a checkpoint (the config move is atomic and verified
  by 162 green radiance assertions), but it is only defensible if the reds are closed by name on a named
  owner — otherwise HEAD is simply green-debt, and the ticket's own D31 rule is that a red nobody owns is a
  red that will be explained away at review.
- 2026-11-23 coord-note **D13 (capture-tool attestation churn is expected, and running the capture casually is
  not)**. C02's dev ran `capture_c03_fixtures.py` as a baseline sanity check and it refreshed `revalidated_at`
  (2026-11-22 → 2026-11-23) in both committed `pre-move-render-*.yaml` fixtures, payload byte-identical;
  it correctly reverted both rather than commit tool churn. The tool is a **manual re-derivation instrument,
  not a suite-invoked check**, so its only safe uses are: review's step-0 guard, or a deliberate re-derivation
  after a ruling. Rule recorded instead of banning the tool: a fixture's attestation line changing is not a
  payload change — check `git diff -- <fixture>` for the payload before treating attestation churn as drift,
  and never stage it as though evidence moved.
- 2026-11-23 coord-ruling **D14 (C02 APPROVED at review `ses_df9f95f5fffeKbbVKbVuxe3Wm8`; the stale
  `surface.sh:963` message string is assigned its OWN repair round, not folded into C04)**. Two evidentiary
  wins worth preserving, plus one routing decision that follows D12's lesson rather than repeating it.
  **Evidence:** (a) the green came from the tree, not from a moved gate — `git diff 01b6c2ff1..HEAD --
  tests/pipeline-models/surface.sh` is **empty**, while the M8 needle already demanded 262144 against an env
  of 200000 at base; it flipped only when the config moved. That is the difference between a gate passing
  and a gate being shifted out of the way, and unlike most assurances it is *checkable*. (b) D12's debt is
  repaid by name: runbook T2 closed via the test half, and **q27-boot T2 closed with NO test-file change** —
  the doc re-pin alone sufficed, which independently confirms the "stale residue vs real break" diagnosis
  that motivated chain-izing the arm. (c) The reviewer prevented a wrong "fix" of mine: fn's annotation cites
  the **flash** pack ceiling (F1) though the lane is named `radiance` — correct, because fn serves
  `qwen3.8-next-flash-fp8-iq4r-moe.rad` at TP2; the 27b lanes properly cite S1/S3. I had read that as sloppy
  provenance. Lesson: verify which artifact a lane actually serves before annotating its provenance as wrong.
  **Decision:** `surface.sh:963`'s error-message text still describes q27's served ceiling as 200000 in the
  present tense. It is inert (visible only when the leg fails), it is in a TEST file (so neither C02's dev
  scope nor my own), and **C04's restatement leg does not cover it** — that leg names the owner-protected
  jsonc commentary. "Someone will catch it in the close-out leg" is precisely how D12's near-orphan happened,
  so it gets its own named repair round now rather than a sympathetic home later.
- 2026-11-23 coord-ruling **D15 (FINAL WHOLE-PLAN REVIEW: APPROVED_WITH_CONDITIONS — condition 1 was my own
  stale record; and the review's MINOR ships as a gate FIX, not a reword)**. Base verified as the true
  merge-base `9a5f731c7`; 12 commits, 20 files, 2367+/74−; every battery leg the reviewer ran personally
  matched expectation (radiance 162P, llama-swap 517P/9S, amd-gpu 36P, vllm 36P, M1-M9 green with M6 never
  run, five notes suites green, four-lane renders correct, aislop 0/0), and Q1/Q4 came back clean — **no
  premise drift** ("wrong" attaches only to the owner's claim, never to the value) and **C02 orthogonality
  proven** (values delta is exactly the four context lines, chart FORM untouched, `charts/radiance` non-test
  diff empty).
  **Condition 1 (closed).** `STATE.json` still read `"DRAFT … approval pending this fold"` with C01/C02 at
  `pending/0/0/null` and `current_wave: 1` while `plan_status` said `approved` — the D52/D53 class I wrote
  rules for, in the ticket where I had been warned about it twice, and a resume scan would have re-run
  approved waves. The reviewer contrasted it against the parent's STATE.json, which is current: the convention
  existed, I just stopped maintaining it under four scope changes. **My first corrective edit then reproduced
  the very bug** — it *added* `plan_status_note` / `coord_session` / `test_session` / `current_wave` above the
  stale originals instead of replacing them, so last-wins left the stale values governing while the file looked
  fixed. Caught only because I re-read my own edit. Repaired by renaming the superseded note to
  `superseded_note_fold_round` (keeping it as history, per annotate-never-rewrite) and deleting the three stale
  key lines, then verifying by count that each top-level key appears exactly once.
  **F2, elevated past its label.** The review filed as a MINOR with a suggested reword the fact that item 3
  emits `POOL_OK` on mere PRESENCE of the `kv: the pool backs …` line and parses `M >= 8` **only for fn** — so
  `75% … 4 full-length sessions` passes today on a non-fn lane. The lane most likely to be under-funded is
  q27-TP1, the one V3/S10 predict cannot fit a single 32 GB card, and its fit is precisely what the gate does
  not check. A completeness gate certifying the existence of the number it exists to adjudicate is the D49
  failure class living inside the artifact built to catch it. Routed as a gate fix: parse `M` per lane against
  each lane's **configured** seqs — read, not hardcoded 8, so a future FORM ruling cannot silently invalidate
  the bar — refuse on absent or unparseable `M`, and surface `N% < 100` as a visible **warning** rather than
  inventing a machine threshold the evidence does not support. The boundary is stated in the tool itself:
  machine-decided = presence, completeness, per-lane funding against configured concurrency; owner-read =
  whether a funded-but-degraded pool is acceptable. **A PASS must never again be readable as "fit certified."**
  **Ticket state.** C01/C02 landed and approved; C03 armed-not-triggered; C04 owner-triggered and NOT run —
  **PROVISIONAL is OPEN on all four lanes and no agent can close it.** `plan_status: complete` describes the
  AGENT-side work only, and that distinction is written into the note itself, because "complete" and
   "evidenced" are different claims and these values merged on the strength of the first.
- 2026-11-23 coord-ruling **D16 (the receipt gate's fit hole is closed as a gate change; its residual limits are
  recorded as limits, not defects)**. Final review's F2 filed the overstatement as a MINOR with a reword;
  substance required a fix — see D15. Landed at `97d284787`: per-lane `M >= read-configured
  --max-num-seqs` (read from the chart FORM, never defaulted), refusal on absent/unparseable `M`, `N% < 100` as
  a surfaced **owner-read warning** on every lane, fn's D9(a)/D9(b) bars byte-identical, block untouched,
  168 passed with the pre-fix fool pattern reproduced as a genuine PASS first.
  **The three limits I want binding on how this is read.** (1) **`M` is self-reported** — the gate parses the
  grepped line from the boot tail, so a PASS certifies *the print says* the lane is funded, not that the engine
  agrees; a stale line from an earlier boot would parse clean. The first owner run calibrates the greps, and
  until that calibration exists the gate's evidence is one step removed from the hardware. (2) **`N%` has no
  machine bar by design** — a pool backing 1% of the worst case passes if nobody acts on the warning, because
  inventing a funding threshold here would be pricing capacity by estimate, which is the exact thing D28(6)
  forbids. So the warning line in the C04 record *is* the judgment artifact: closing C04 without quoting the
  N% values would be closing on the weaker half. (3) **The eight-session runtime smoke is fn-only by ruling**
  (D9(b) scoped it to the live default route), so the three parked lanes have no independent loud check for
  silent under-funding — their only cover is a boot line the lane cannot produce until someone scales it.
  Net: the gate is now worth trusting for what it checks and must not be read beyond that, and C04's close is
  the owner's act for reasons that are structural, not procedural.
- 2026-11-23 coord-note **D10 (no memory change anywhere in this ticket)** — F2's arithmetic closed the last
  open question about sizing: flash-TP1 at 262144 fits the held 110Gi at BOTH candidate cost rates
  (≈69–89 GiB used; engine rule `110 − 87 = 23 ≥ 4`), fn-TP2's worst-case pool goes 18.3 → **24.0 GiB** trunk
  against 2 × 31.86 GiB usable with the per-sequence recurrent state and checkpoint slots essentially
  unmoved, and the 27b lanes' host band barely shifts. So **no lane's memory value changes** in this ticket —
  memory remains print-gated by cf-143 D28(6) / cf-144 P11, exactly as RULING D7 ruled, and nothing here
  pre-empts those prints.

- 2026-11-23 plan, ruling **D11 (FOLD PROVENANCE — the plan re-filed for FOUR lanes per
  D5/D9/D10; the flash round-2 evidence made durable in the contract)**: D5 and D9 changed
  the scope twice after the 2026-11-22 draft (which scoped C01/C02 to two 27b env values),
  so the draft no longer described the work — `plan_status` stays `draft`, approval pending
  this fold. This fold: (1) re-files the plan of record + `chunks/C01`-`C04` for four
  lanes with the three DIFFERENT kinds of test-authority change (D9(d): fn a constant
  re-pin only — no transcription leg exists; flash-TP1 the deviation-with-ruling re-pin,
  the verbatim leg re-pinned to "exactly TWO values swapped — id + context, per ruling
  D5/D9" and its fidelity claim bounded by ruling — the source commit `e7536b2c9^` is
  immutable, the leg is never again described as verbatim); (2) DISCOVERS THE M8-B RE-PIN
  — the draft's "M8-B verify-only / fn stays 200000" assumption is broken by D9: the fn
  needle at `surface.sh` asserts `str(mm) == "200000"`, so C01 re-pins it to 262144
  (designed red until C02); the both-figures commentary teeth stay green pre- and
  post-C02 (the stale comment names 200000; the window carries 262144); (3) CARRIES the
  flash round-2 evidence (F1-F5 + the five print-pending items, research session
  `ses_dfa43b76cffex5QZ8Vj9E9pGf1`, live fetches 2026-11-23) into the plan's Verified
  facts with attribution — its RESEARCH.md write was denied at the research tier AND at
  the coordinator's (FRICTION round-2 row), so without this fold the evidence lived only
  in FRICTION + the transcript; (4) records the fn-TP2 live fact: `replicas: 0` by the
  owner's own scale act (git carries 1 at :1063) — fn's receipt (the first TP2 print,
  cf-144 P11) is unobtainable until the owner brings fn back up, and C02's landing is a
  second pod roll on the pipeline's own critical path (D9(c), parent-D16) — stated in
  the plan's Risks/Landing, with the roll window owed to the owner BEFORE landing.
  **The D4 lane-equality statement, VERIFIED against the jsonc row census 2026-11-23
  (not assumed)**: the twelve radiance-family rows are all `limit.context 262144`
  (verified at :720/:727/:734 fn trio, :776/:783/:790 q27 trio, :831/:838/:845
  flash-TP1 trio, :852/:859/:866 q27-TP2 trio); post-C02, ALL FOUR radiance lanes end
  with served == trained == 262144 — the D47 pair COLLAPSES to equality on every
  radiance lane; the unequal catalog context figures (131072 `qwen38-humanlike`; 16384
  ×45; 8192 ×2; 1010000 ×2) exist ONLY in non-radiance strata/llama.cpp rows (the
  strata row itself is 262144, equal to its own trained ceiling per its comment) and
  M9-A2's scope is the twelve-row family, which never governs them — the D47 unequal
  pair survives only OUTSIDE the family. Open questions re-filed as PRINT-PENDING (five,
  in the plan — listed so no session invents answers); no open OWNER questions remain
  (D5/D6/D7/D9/D10 settled them; the draft's OQ1/OQ2/OQ3 are retired, not re-asked).
  Superseded by this fold: the draft's two-lane C01/C02 scope, its "fn/flash-tp1 no-op
  proof" task, and its OQ1/OQ2/OQ3 — the superseded draft is preserved verbatim in git
  (`e4c094b43`); the fold's agreements/differences are recorded here, per the parent's
  D13 idiom.
## Deferred
- The 1M/YaRN factor-4 path — NOT engine-validated (S7: only factor 2, to 524288, is
  validated on this model). Revisit trigger: a fresh YaRN validation pass + an owner ruling.
- The stale jsonc commentary restatement — the owner's prose leg at C04 (parent-D27); the
  legs stay green meanwhile (the needles name both figures).
- `max-num-seqs` 8 → 32 alignment (the upstream S8 profile) — open question 2; 8 is
  FORM-fixed (parent-D46; `FORM_FIXED_FLAGS` testlib :936), so the alignment is a FORM
  change (one chart edit, all four lanes, the wrapper bytes + the FORM legs' re-pin), not
  a values edit; a fresh ruling + a fresh print.
