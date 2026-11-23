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
  one artifact, and any lane-count change from D5 lands in that block too.

## Deferred
- The 1M/YaRN factor-4 path — NOT engine-validated (S7: only factor 2, to 524288, is
  validated on this model). Revisit trigger: a fresh YaRN validation pass + an owner ruling.
- The stale jsonc commentary restatement — the owner's prose leg at C04 (parent-D27); the
  legs stay green meanwhile (the needles name both figures).
- `max-num-seqs` 8 → 32 alignment (the upstream S8 profile) — open question 2; 8 is
  FORM-fixed (parent-D46; `FORM_FIXED_FLAGS` testlib :936), so the alignment is a FORM
  change (one chart edit, all four lanes, the wrapper bytes + the FORM legs' re-pin), not
  a values edit; a fresh ruling + a fresh print.
