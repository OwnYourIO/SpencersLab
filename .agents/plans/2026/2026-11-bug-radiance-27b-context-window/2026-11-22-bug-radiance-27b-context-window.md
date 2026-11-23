# PLAN: Radiance 27b context window — raise the two 27b lanes' `--max-model-len` to the trained ceiling 262144 by owner ruling
feature: 2026/2026-11-bug-radiance-27b-context-window

## Goal
Move the two 27b lanes (`radiance-q27` TP1, `radiance-q27-tp2` TP2) from the transcribed
`RADIANCE_MAX_MODEL_LEN 200000` to the model's trained ceiling `262144` — an owner ruling
recorded with a provisional-in-place annotation, a pre-agreed both-path adjudication, and the
receipt sequence as a post-merge follow-up leg, never a gate before the config edit (RULING 3).
fn (`radiance`) and `radiance-flash-tp1` stay at 200000 (open question 1 decides).

## Premise check (the ticket's premise, carried honestly — RESEARCH 2026-11-22)
The owner's premise — "200000 should be the fully supported value" — is **FALSE as a fact
claim** (V1): 262144 is the TRAINED ceiling (pack card "262,144 tokens trained; 200K
**tested**" S1; `config.json max_position_embeddings: 262144`, no `rope_scaling` S3; README
"262,144 natively" S2), 200000 is a TESTED conservative bound, and 1,000,000 is a YaRN
factor-4 recipe that is NOT engine-validated (S7: only factor 2, to 524288, is validated on
this model). V4: 200000 was TRANSCRIBED (cf-143 D54(1) owner recipe verbatim; matches the
upstream-published compose profile S8 `--tp 2 --max-num-seqs 32 --max-model-len 200000
--kv-cache-dtype fp8`) and was **never measured on our node** (both 27b lanes rest at
`replicas: 0` in git; no boot print exists) — so neither value carries a receipt, which is
why the raise is a ruling, not a correction. V2: Radiance treats `--max-model-len` as the
worst case the KV pool is sized against (not a per-request reservation; `0` = training
context) and **WARNS, it does not refuse**, past the trained/rotary bound — a raise that
does not fit will not fail loudly.

## Out of scope
- Catalog row edits — `.opencode/opencode.jsonc` is D27 owner-protected and the rows are
  ALREADY 262144 (owner's `b3d7fada8`); the stale jsonc COMMENTS are an owner prose leg at
  C04 (Deferred), not this ticket's dev scope.
- Claim counts (the one-home table's claims: fn 2, q27 1, flash-TP1 1, q27-TP2 2, strata 1
  over a pool of 2) — orthogonal to the context bound; verified unchanged (fact 7).
- Memory values (`24Gi`/`110Gi` pairs, `guaranteedMemoryGi`) unless a print forces a NEW
  ruling — the re-pin stays print-gated (D28(6)/D54(4)/P11); best guess OQ3.
- Chart version bumps — `charts/radiance` is not touched by this ticket.
- The 1M/YaRN path — Deferred with a revisit trigger (a fresh YaRN validation pass + owner
  ruling; S7 shows only factor 2 is engine-validated on this model).
- `max-num-seqs` alignment to upstream's 32 (S8) — OPEN QUESTION 2; 8 is FORM-fixed (D46;
  `FORM_FIXED_FLAGS` testlib :936) so it is a FORM change, not bundled here.

## Verified facts (plan-session re-reads at branch tip `9a5f731c7`; RESEARCH 418 lines + parent rulings)
1. **The trained ceiling is 262144** (S1/S2/S3, live 2026-11-22); 1M = SUPPORTED-WITH-
   SCALING, not native (S2/S7). [V1]
2. **200000 is transcribed, never measured here** (V4): cf-143 D54(1) recipe verbatim, the
   upstream profile S8, and consistent with Wilde's measured single-card fit cap (~200k,
   fit-to-available, S10) — a fit cap, not a "fully supported" statement.
3. **Engine semantics** (S6/S7, V2): `--max-model-len` = worst-case pool bound, no
   per-request reservation; `rope-scaling: yarn:FACTOR` is first-class, factor 2 validated on
   27B to 524288; the engine WARNS (never refuses) past the trained length.
4. **Fit arithmetic** (V3, S3/S6/S10): 32 KiB/token trunk (16 full-attention × 4 KV heads ×
   256 head_dim × 2 × 1 B); ~64 KiB/token effective (the in-pack DFlash2 drafter's own
   paged cache — INFERRED 2×, confirmed only by Wilde's 12.46 GiB → 199,472 cap).
   262144 pool = 16.0 GiB (64 KiB): **fits TP2** (9.68 GiB/card weights; Wilde measured
   20.04 GiB KV/card fit-to-available, "Full 262144 fits with ~100 MiB of headroom per
   card"); **does NOT fit one 32 GB card** at 64 KiB (18.07 GiB weights + 16.0 GiB pool;
   Wilde: one card caps around 200k, fit-to-available, no crash, no refusal).
5. **Host side barely shifts** (V3): checkpoint slots log-scaled (9–10 per 200K-class
   session, same class at 262144); the 80-slot × 144 MiB = 11.25 GiB store barely moves;
   the 24Gi band legs (24 ≥ 20 + 4; 24 − 8.5 = 15.5 ≥ 4) untouched; node fit
   24 + 4.125 + 1.158 = 29.3 ≤ 125.08 GiB unchanged.
6. **"Zero extra usable VRAM" verdict** (V5, S10): TRUE for the host pin (7.89 GiB pinned in
   BOTH the TP1 and TP2 rows — TP collectives stage through pinned host memory), FALSE for
   card VRAM (pool 12.48 → 40.08 GiB; ~199k → ~663,600 tokens at 64 KiB).
7. **Per-lane isolation** (RESEARCH (d), verified this session): `RADIANCE_MAX_MODEL_LEN` is
   a per-lane env entry in all four lanes (fn :1121, flash-tp1 :1495, q27 :1367,
   q27-tp2 :1588 — all "200000"); the chart wrapper reads it from env
   (`charts/radiance/values.yaml:218`, verified); the FORM fixes only port/host/
   `max-num-seqs 8`/`kv-cache-dtype fp8` (D46; `FORM_FIXED_FLAGS` testlib :936); upstream
   `common.yaml` carries no context flag (S9). Raising the two 27b env entries touches no
   FORM, no fn lane, no chart parameterisation — the D28(6) one-edit overlay law holds.
8. **Test-authority inventory** (verified this session): `Q27_CTX` (testlib :332 — defined,
   not referenced by any leg — contract carrier); `Q27_PROFILE` (:282, `--max-model-len
   "200000"`, provenance comment claims "the cf-143 D54-ratified profile byte-for-byte as
   the retired args array shipped it" — the claim the raise DEVIATES from, by ruling);
   `q27_tp2_profile()` (:985, derived from `Q27_PROFILE` + the TP pair + its served id —
   inherits any parent move); `flash_tp1_profile()` (:967, derived from git
   `e7536b2c9^` — an IMMUTABLE source at 200000, lane ruled to stay); `FULL_PROFILE` (:120,
   fn, 200000); `COMPOSITION_LANES` (:1003); pre-move fixtures pinned at `8f3d5bbad`
   (`capture_c03_fixtures.py:158-200` — the guard re-derives the PIN, independent of HEAD);
   invariance legs (`test_c03_generic_shell.py:401-447` — image/probes/securityContext/
   claim/memory/cpu/replicas/grace; env/args are MOVABLE paths by the D43 wave law);
   `surface.sh` M8-B (:1030-1073: fn env 200000 + the commentary names both figures) and
   M9-A2 ctx half (:1347-1511: all twelve rows 262144 + the new-family commentary names
   both figures, planted teeth on both); `TEST_SPEC.md` §1.
9. **Parent rulings that bind**: D43 (env is the sizing channel; the wrapper composes argv —
   the boot echo is the receipt in place of argv); D46 (FORM-fixed flags); D47 (2026-11-23:
   `limit.context 262144` family-wide = the trained window the client budgets against, the
   served 200000 stated separately; the reviewer's loud-400 dissent recorded); cf-143 D28(6)
   (boot prints price numbers; estimates do not; the repair is the one-edit overlay);
   D54(4)/cf-144 P11 (the memory re-pin is deferred to the print); D27 (jsonc owner-
   protected); D30 (test-file edits are never assignable to dev).
10. **Base state**: the parent ticket `feat-radiance-multi-instance` is COMPLETE and its
    work is MERGED (owner-confirmed 2026-11-22 via `git branch -a --contains`; not
    re-litigated — FRICTION #1). Work continues in the EXISTING worktree/branch
    `feat-radiance-multi-instance` at `9a5f731c7` (the research commit). The local `main`
    ref in this worktree lacks the branch's last three commits — a statement about the
    local ref, not the merge state (FRICTION #1).

## Commands (validation battery — every session exports PATH first)
- `export PATH=$HOME/.local/bin:$PATH` (without it the helm-guarded legs skip silently)
- `python3 -m pytest charts/radiance/tests -v` (per-directory; the radiance suite — post-C01
  the q27/q27-tp2 composed-argv + env-authority legs are DESIGNED-RED naming C02; all green
  after C02)
- `python3 charts/radiance/tests/capture_c03_fixtures.py` (the review tier's first step —
  the fixture guard re-derives at the pin; must pass: the context move is outside the
  fixtures' scope, fact 8)
- `bash tests/pipeline-models/surface.sh` (read-only run; M8/M9 must stay green through
  C01 and C02 — fn unchanged, catalog unchanged, the commentary needles name both figures)
- `bash tests/notes/radiance-roster.sh` (the roster prose leg — T2 re-derives claims/
  replicas from the tree; the C02 annotations are prose, not claim cells)
- `helm lint charts/radiance && helm template charts/radiance` (chart sanity — the chart is
  NOT touched; guards against an accidental chart edit)
- `grep -n "RADIANCE_MAX_MODEL_LEN" services/gpu-ai/prod/values.yaml` (the four-lane env
  audit: exactly fn 200000 / flash-tp1 200000 / q27 262144 / q27-tp2 262144 after C02)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Test-authority re-pin BY RULING — `Q27_CTX`/`Q27_PROFILE`/`q27_tp2_profile` to 262144 with the deviation + ruling cite (the transcription provenance deviates by ruling, recorded — not pretended verbatim), the D47 pairing-law re-pin (M8-B/M9-A2 + TEST_SPEC §1, the restated `trained >= served`, equal legal), the flash-TP1 transcription proof STAYS verbatim (immutable git source, lane unchanged), the pre-move fixtures' expected behaviour recorded | M | 1 | [] | the test wave runs before any dev (repo law); its designed reds name C02 |
| C02 | The config move + prose plane — the two 27b env values 200000 → 262144 with dated PROVISIONAL annotations naming the pending receipt + ruling cites (RULING 3(a)); the values "WHY the two shipped context numbers" comment annotated (the 335–409K trunk-only correction, V3/contradiction #2); the "not a memory story" comment + the roster note's cost ledger annotated with the V5 verdict (host-pin TRUE / card-VRAM FALSE); the boot note's "honest envelope 200000" annotated as pre-D47 history; fn/flash-tp1 no-op proof; the one-home table + roster §3 + NOTES.txt shell law re-checked against the raised window and stated UNCHANGED with the proof (fact 5/7) | M | 2 | [C01] | greens C01's designed reds (the profile and the rendered env must meet at the composed vector); the prose pins the values it governs in the same commit (cf-144 C02 precedent) |
| C03 | The pre-agreed TP1 revert leg — CONDITIONAL, trigger = the owner's boot print REFUTES the TP1 fit (RULING 2 outcome B: OOM/refuse/truncate — the `kv: pool backs N%` line shows the pool under-funding the 262144 worst case, or the ~199k cap) | S | 3 | [C02] | the revert must follow the landed config; the test re-pin wave precedes the dev round (D30) |
| C04 | The receipts-close leg — ALWAYS (post-merge follow-up, the owner's print in hand): record the nine-item receipt set (RESEARCH implication (e)) in DECISIONS + the boot note, close the PROVISIONAL status by dated annotation (the leg/commit that closes it — RULING 3(d)), the D47 dissent retired by item 9, the owner-prose jsonc comment restatement recorded as the owner's leg | S | 3 | [C02, C03] | C03 if triggered (the refutation must be recorded before the close); otherwise C03 retires as a no-op with the confirmation recorded here |

## Wave order
1. **C01** (the test wave — re-pin by ruling; designed reds: the q27/q27-tp2 composed-argv
   + env-authority legs naming C02; everything else green, fact 8).
2. **C02** (the config move + prose plane; the designed reds green; full battery green).
3. **C03** (conditional — the owner's print adjudicates; if the print CONFIRMS, C03 retires
   as a no-op with the confirmation recorded in C04) → **C04** (the receipts close; the
   PROVISIONAL annotations close). C03 and C04 are POST-MERGE follow-up legs — the owner's
   receipt sequence is a post-merge follow-up leg, not a gate before the config edit
   (RULING 3).

## Scope seams → chunk (with the ruling authority)
1. **Lane values** `RADIANCE_MAX_MODEL_LEN` (q27 :1367, q27-tp2 :1588; fn :1121 and
   flash-tp1 :1495 STAY 200000 pending OQ1; verified per-lane isolation, fact 7, RESEARCH (d)
   + S8/S9) → **C02**; authority: RULING 1 (TP2, V3 fit) + RULING 2 (TP1, the print
   adjudicates).
2. **Test authorities** `Q27_CTX`, `Q27_PROFILE`, `COMPOSITION_LANES`, the q27-TP2 derived
   profile, the transcription proofs → **C01**; authority: RULING 1+2 BY RULING — the
   q27 provenance record DEVIATES by ruling (recorded with the cite, not pretended
   verbatim); the flash-TP1 git transcription STAYS verbatim (the source `e7536b2c9^` is
   immutable, the lane is unchanged); the pre-move fixtures (`pre-move-render-*.yaml`, pinned
   `8f3d5bbad`) are UNTOUCHED and no fixture leg legitimately fails — the fixture is the
   pinned-commit baseline independent of HEAD, the invariance legs exclude env/args (the
   context move is a MOVABLE path), and the fixture's 200000 argv stays the true historical
   pre-move fact. The only legitimate red is C01's designed reds until C02.
3. **D47's ctx pairing law** (M8-B/M9-A2: catalog 262144 vs served 200000, BOTH named) →
   **C01** (+ the DECISIONS annotation, plan tier); for the raised 27b lanes served becomes
   262144 ⇒ the pair COLLAPSES to equality there while fn/flash-TP1 keep an unequal pair.
   Restated law: `trained >= served` per lane, **equal legal**. Restated legs: the M9-A2
   prose half (the commentary names the PER-LANE served figure — flash-TP1 200000, 27b-TP2
   262144 — the both-figures needle stays, green) + TEST_SPEC §1 (the per-lane served
   column). Unchanged legs: the M9-A2 value half (all twelve rows 262144 — already true),
   M8-B (fn stays 200000; the commentary names both), M9-B (key sets), M8-A/A2 (the
   priority ladder). D47 is ANNOTATED (this ticket's DECISIONS entry), never rewritten
   (the D48 idiom).
4. **Prose corrections research proved wrong in the parent's already-approved files**:
   (a) the roster cost ledger's "both TP2 lanes buy ZERO extra VRAM" (the exact phrase is
   absent verbatim — RESEARCH open q4; the carriers are the roster note's "UP at what cost"
   column + the values "not a memory story" comment + the second-gpu-tp2 note) → corrected
   with the V5 verdict (TRUE of the host pin 7.89 GiB both rows; FALSE of card VRAM
   12.48 → 40.08 GiB) — **C02** (dated annotation, annotate-never-rewrite; the authority is
   this ticket's DECISIONS ruling, the parent's files being approved — the annotation is the
   sanctioned mechanism); (b) `radiance-q27-boot.md`'s "honest envelope 200000" (pre-D47
   historical prose, RESEARCH V4/contradiction #4) → **C02** annotated as history (the print
   is the authority, the number stays as history).
5. **One-home table + roster §3 co-boot arithmetic + NOTES.txt shell law** → **C02**
   re-checked: UNCHANGED, and here is the proof — claims and replicas are orthogonal to the
   context bound (fact 7); the bound touches GPU pool sizing plus log-scaled checkpoint
   slots (V3: the 11.25 GiB store barely moves); the host pin is identical (V5: 7.89 GiB
   pinned both rows — TP collectives stage through pinned host memory); the held 24Gi/110Gi
   cgroup pairs are UNMOVED (print-gated, D28(6)/OQ3); the node fit 29.3 ≤ 125.08 and the
   110 + 24 + ~5.3 > 125.08 co-boot arithmetic rest on the cgroup pairs, which do not move;
   `charts/radiance` (NOTES.txt's home) is not touched by this ticket.
6. **Out-of-scope seams** — catalog rows (D27 owner-protected, already 262144), claim
   counts (fact 5/7 proof), memory values (print-gated — a NEW ruling only), chart version
   bumps (chart untouched), the 1M/YaRN path (Deferred + revisit trigger), `max-num-seqs`
   (OQ2; 8 FORM-fixed).

## The TP1 both-path design (RULING 2, written in advance)
The owner directs that the raise be ATTEMPTED on TP1 too and the boot print adjudicate,
AGAINST the coordinator's recommendation. The coordinator's dissent is recorded in
DECISIONS D2: V3/S10 PREDICT a single 32 GB card caps measured fit near ~199k (Wilde's
12.46 GiB pool → 199,472 tokens at the ~64 KiB effective cost), and the engine's behaviour
is fit-to-available with a warning — no crash, no refusal (V2, S6/S7; Wilde's 263k probe)
— so a non-fit TP1 will likely boot and serve on a TRUNCATED pool rather than fail loudly.
Both outcome paths are pre-agreed:
- **Outcome A — boots and serves with the pool funding the 262144 worst case** (the
  `kv: pool backs N%` line shows the pool covering a full 262144 session; the arithmetic was
  wrong — e.g. the single card pays 32 KiB trunk-only, no drafter-cache cost): keep the
  raise; the confirmation is recorded in C04.
- **Outcome B — OOM / refusal / truncation** (the print shows the pool under-funding the
  worst case, or the ~199k cap, or a truncated serve): **revert TP1 to 200000** via C03
  (the pre-authored contract: the test re-pin wave splits the constants — `Q27_PROFILE` keeps
  200000 for TP1, `q27_tp2_profile()` gains the explicit `--max-model-len 262144` override,
  `Q27_CTX` becomes the per-lane pair — then the dev round makes the one env edit, then
  DECISIONS records the refuting print as the receipt). The TP2 lane stays 262144 (V3 fit
  with ~100 MiB headroom/card, measured).
Executor of C03: a follow-up dev session under the coordinator, owner-triggered by the
refuting print, test re-pin first (D30).

## Landing shape (the owner's receipt sequence is a POST-MERGE follow-up leg, not a gate)
- C01 + C02 land locally on the existing branch `feat-radiance-multi-instance` (the worktree
  continues; one commit per chunk); **push/PR/merge are OWNER legs** (never advance main from
  a session; a plan step that says otherwise is void).
- The 262144 value MERGES before any print supports it — the RULING 3 consequence, recorded
  in DECISIONS D3: the values are marked **PROVISIONAL in place** (dated annotation naming
  the pending receipt + the ruling cites), so an unobserved value in git is visible, dated,
  and bounded.
- The lanes rest at `replicas: 0` in git, so the merged config has ZERO scheduling impact
  until the owner's scale act — the unobserved value runs on the cluster only when the owner
  scales (the fn→0 swap discipline, roster note).
- Post-merge follow-up legs (owner-triggered, the receipt sequence): (1) the owner's scale
  act (the swap order: fn DOWN first, then the 27b lane(s) UP); (2) the first boot → the
  owner captures the nine-item receipt set (RESEARCH implication (e)); (3) the owner
  adjudicates (the print speaks); (4) C03 (if the TP1 print refutes — the pre-agreed revert)
  → C04 (the receipts close; the PROVISIONAL status closes here — the named leg/commit,
  RULING 3(d)). A later contradicting print unwinds an already-merged config by a FORWARD
  fix commit (the D28(6) one-edit overlay repair; the refuting print quoted as the receipt;
  a fresh DECISIONS line) — never a revert of the merge, never history rewriting (OQ5).

## Risks / assumptions
- **Warn-not-refuse means a silent bad raise** (V2; RULING 2's core hazard): a non-fit TP1
  will not fail loudly — it serves on a truncated pool (Wilde: "no crash, no refusal, just
  fit-to-available"). Mitigation: the both-path design above is written in advance; the
  `kv: pool backs N%` line is the named adjudicator; C03's contract is pre-authored; the
  receipt is mandatory before C04 closes the PROVISIONAL.
- **A provisional value merging before its print** (RULING 3's accepted consequence):
  262144 is in git unobserved. Mitigation: (a) the PROVISIONAL annotation in place (dated,
  naming the pending receipt + ruling cites); (b) the pre-agreed revert path + named
  executor (C03); (c) the contradicting-print unwind pre-agreed (OQ5 — forward fix, one-edit
  overlay); (d) the named close leg (C04) so PROVISIONAL cannot silently become permanent.
  The D28(6) relaxation is recorded in DECISIONS D3 BY OWNER WORD and scoped to the context
  bound only — the memory re-pin stays print-gated (V3: the band barely shifts, so there is
  nothing to pre-empt; OQ3).
- **The invariance gate's expected behaviour**: the context move is a MOVABLE path (env);
  the pre-move fixtures stay the immutable pinned baseline (`8f3d5bbad`) with their 200000
  argv as true history; the per-property legs (image/probes/securityContext/claim/memory/
  cpu/replicas/grace) stay GREEN and are the proof NOTHING ELSE moved; the only legitimate
  red is C01's designed reds until C02. A red fixture leg would be the guard working (a hand-
  edited fixture or a dependency borrow failure), not the raise.
- **The 32-vs-64 KiB question is unsettled** (RESEARCH open q1/q3): the TP1 fit prediction
  rides on it; the boot's VRAM-split + pool-backs lines (receipt items 2–3) settle it — the
  plan is written for both outcomes.
- **Stale owner-protected commentary**: after C02 the jsonc comments ("Served admission is
  the other number ... 200000" for the new family; "Context 200000 is q27's PER-SESSION
  ceiling" for the q27 trio) are half-stale; the legs stay GREEN (the needles name both
  figures); the restatement is the owner's prose leg at C04 (D27) — recorded, not executed.

## Open questions (the batched round — one question, best guesses stated)
1. **fn + flash-TP1 in or out?** — best guess: **OUT**. The ruling is scoped to the 27b
   pack (the 262144 trained ceiling is a 27b fact, S1–S3); flash-next is a different family
   with its own card, and flash-TP1's 200000 is a VERBATIM transcription of the cf-143
   TP1-era fn recipe (`FLASH_TP1_TRANSCRIPTION`) — moving it would break the verbatim
   proof for no 27b-class evidence; the upstream profile S8 is 27b-specific. If in: a fresh
   ruling + the transcription proof re-aimed + the flash family's own card fact.
2. **`max-num-seqs` 8 → 32 (the upstream S8 alignment)?** — best guess: **HOLD at 8**. 8 is
   FORM-fixed (D46) — a change is a FORM change (one chart edit for all four lanes, D43(3))
   plus the FORM legs' re-pin and the wrapper bytes; a higher seqs count moves the worst-
   case pool sizing (the guide's own "a bf16×32-seq budget startup warns that a longer one
   would be refused" class); the value is held with its print pending. A fresh ruling +
   fresh print if the owner wants 32.
3. **Does the held 24Gi move pre-emptively, or only on the print?** — best guess: **only on
   the print** (D28(6)/D54(4)/P11: the boot print adjudicates; a pre-emptive re-pin is the
   exact thing D28(6) forbids; V3: the band barely shifts — checkpoint slots log-scaled,
   host pin identical (V5) — so pre-empting buys nothing).
4. **Who reads which exact log line as the receipt?** — best guess: the OWNER captures the
   print at the scale act (the cf-144 P11 / OQ-R1 paste pattern); the coordinator's C04
   session transcribes + records the nine-item set (the `/diagnostics` config echo; the
   VRAM-split lines; the `kv: the pool backs N% of the worst case ... M full-length
   sessions` line; the pinned line vs the held 24Gi; the checkpoint-slot count; the
   prefix-cache tier warning; `memory.peak` + `oom_kill=0`; the peer-hop smoke; ONE
   near-262144 session accepted) into DECISIONS + `radiance-q27-boot.md`; the owner also
   restates the stale jsonc comments (D27) at that leg.
5. **How does a contradicting print unwind an already-merged config?** — pre-agreed (RULING
   2(c)): the owner's ruling triggers C03 (or the TP2 analogue, a fresh ruling) — a FORWARD
   fix commit, not a revert of the merge: the one-edit overlay repair (D28(6) idiom) moves
   the env value back, the test re-pin precedes the dev round (D30), a fresh DECISIONS line
   quotes the refuting print as the receipt, the PROVISIONAL annotation is annotated closed
   by refutation. Merged history is never rewritten; the fix is forward.

## Deferred (recorded, not planned)
- The 1M/YaRN factor-4 path — NOT engine-validated (S7: only factor 2, to 524288, is
  validated on this model). Revisit trigger: a fresh YaRN validation pass + an owner ruling.
- The stale jsonc commentary restatement — the owner's prose leg at C04 (D27 owner-
  protected; the legs stay green meanwhile — the needles name both figures).
- `max-num-seqs` 8 → 32 — open question 2; a FORM change; a fresh ruling + fresh print.
