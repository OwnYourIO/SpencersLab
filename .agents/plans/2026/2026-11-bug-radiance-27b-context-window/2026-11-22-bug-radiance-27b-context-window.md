# PLAN: Radiance context window — raise ALL FOUR lanes' `--max-model-len` to the trained ceiling 262144 by owner ruling
feature: 2026/2026-11-bug-radiance-27b-context-window

## Goal
Move every radiance lane's `RADIANCE_MAX_MODEL_LEN` from 200000 to the model's trained
ceiling 262144 — `radiance` (fn-TP2, D5/D9), `radiance-q27` (27b-TP1, D1/D2),
`radiance-q27-tp2` (27b-TP2, D1), `radiance-flash-tp1` (D5) — an owner ruling recorded
with the PROVISIONAL-in-place annotation (D3(a)), a pre-agreed both-path adjudication
per lane (D2/D9), the pre-authored receipt command block (D8), and the receipt sequence
as a post-merge follow-up leg, never a gate before the config edit (D3). **No memory
value changes anywhere in this ticket** (D7/D10) — the held 24Gi/110Gi pairs stay
print-gated. `max-num-seqs` stays 8 (D6).

## Premise check (carried honestly — RESEARCH 2026-11-22 + flash round 2 2026-11-23)
The owner's premise — "200000 should be the fully supported value" — is **FALSE as a fact
claim** for both models (V1/F1): 262144 is the TRAINED ceiling for the 27b pack (pack
card "262,144 tokens trained; 200K **tested**" S1; `config.json max_position_embeddings:
262144`, no `rope_scaling` S3) AND for the flash pack (config.json `max_position_embeddings:
262144`, `rope_type: "default"`, no `rope_scaling` — 48 layers = 12 full-attention + 36
linear, 2 KV heads, head_dim 256; pack card "262,144 tokens trained; **served at 200K**"
F1 — note the asymmetry: the 27b's 200K was an empirical BOUND, the flash's 200K is a
serving CHOICE). The 200000 values are NOT receipts: the 27b's was TRANSCRIBED (cf-143
D54(1) owner recipe verbatim; upstream compose profile S8) and never measured on our node
(V4 — both 27b lanes rest at `replicas: 0` in git; no boot print exists), while **fn's
200000 was MEASURED** (F3: cf-143 D28(1)/D30(1) record the live boot print — container
printed its budget and died `out of memory` at cgroup 64.00 GiB vs **71.04 GiB observed
pinned** — that print is what the 110Gi hold rides — "200K funded ON-CARD (`kv cache
4.49 GiB a card: 1600000 tokens, 8.0 sessions at 200000` ≈ 2.94 KiB/token), host term is
the eager `--kv-resident` mirror — PROVEN eager because boot died with zero sessions
arrived"; caveat: a TP1-era print, the first TP2 print is still owed, cf-144 P11). So
this ticket OVERRIDES an assumption on the parked lanes and OVERTURNS a measurement on
the live default route — the latter is D9's informed risk. Upstream publishes **NO
262144 serve shape at all** (F4: of 57 compose files every 27b variant ships 200000; the
only 262144 anywhere is the guide's §4.4.1 streaming-KV demo at **2 sessions** plus one
third-party production witness, llmkube 62 GiB host). And the engine **WARNS, it does not
refuse**, past the trained/rotary bound (V2; verified round 2 at `YARN.md` @v1.17.0
:104-105) — refusals are HOST-budget cases (guide :1092-1093: at `--tp 1` the host copy
for 2×262k "does not fit beside the weights, and **the start is refused**" — that is
flash-TP1's scale-up failure mode: loud, unlike fn's silent under-funding).

## Out of scope (ruled, 2026-11-23)
- `max-num-seqs` 8 → 32 (upstream S8) — **D6 RULING: stays 8**. FORM-fixed (parent-D46;
  `FORM_FIXED_FLAGS` testlib :936); a change is one chart edit moving the worst-case pool
  sizing for ALL FOUR lanes at once — it would invalidate the very receipt this ticket
  exists to capture. Upstream's 32 recorded as a legitimate future ruling with its own
  print.
- Memory values (the held 24Gi/110Gi pairs, `guaranteedMemoryGi`) — **D7/D10 RULING: NO
  memory value changes anywhere in this ticket.** F2's arithmetic closed the last sizing
  question (flash-TP1 fits held 110 at BOTH cost rates ≈69–89 GiB used; engine rule
  `110 − 87 = 23 ≥ 4`; fn-TP2 worst-case pool 18.3 → 24.0 GiB trunk against 2 × 31.86
  GiB usable; the 27b host band barely shifts), so nothing pre-empts the prints. Memory
  moves only on a contradicting print (D28(6)/cf-144 P11 discipline stands; D7).
- Catalog row edits — `.opencode/opencode.jsonc` is parent-D27 owner-protected and the
  twelve family rows are ALREADY 262144 (the owner's `b3d7fada8`); the stale jsonc
  COMMENTS are the owner's prose leg at C04 (Deferred), not this ticket's dev scope.
- Chart version bumps — `charts/radiance` is not touched by this ticket.
- The 1M/YaRN path — Deferred with revisit trigger (a fresh YaRN validation pass + owner
  ruling; S7: only factor 2, to 524288, is engine-validated on this model).
- fn's first TP2 print (cf-144 P11) — OWED by the owner's scale act, not by this ticket
  (fn is at `replicas: 0` by the owner's own scale act — see Landing shape).

## Verified facts (fold 2026-11-23 re-reads at `f31c40d41`; RESEARCH 418 lines + parent rulings + flash round 2)
1. **The 27b trained ceiling is 262144** (S1/S2/S3, live 2026-11-22); 1M = SUPPORTED-WITH-
   SCALING, not native (S2/S7). [V1]
2. **200000 was transcribed, never measured, on the 27b lanes** (V4): cf-143 D54(1) recipe
   verbatim, the upstream profile S8, consistent with Wilde's measured single-card fit cap
   (~200k, fit-to-available, S10) — a fit cap, not a "fully supported" statement.
3. **Engine semantics** (S6/S7, V2; round-2 verified): `--max-model-len` = worst-case pool
   bound, no per-request reservation; the engine WARNS (never refuses) past the trained
   length (`YARN.md` @v1.17.0 :104-105); refusals are HOST-budget cases (guide :1092-1093
   — `--tp 1` at 2×262k: "the start is refused"); `rope-scaling: yarn:FACTOR` is
   first-class, factor 2 validated on 27B to 524288, factor 4 / 1M is not.
4. **27b fit arithmetic** (V3, S3/S6/S10): 32 KiB/token trunk (16 full-attention × 4 KV
   heads × 256 head_dim × 2 × 1 B); ~64 KiB/token effective (the in-pack DFlash2
   drafter's own paged cache — INFERRED 2×, confirmed only by Wilde's 12.46 GiB →
   199,472 cap). 262144 pool = 16.0 GiB: **fits TP2** (9.68 GiB/card weights; Wilde
   measured 20.04 GiB KV/card fit-to-available, "Full 262144 fits with ~100 MiB of
   headroom per card"); **does NOT fit one 32 GB card** (18.07 GiB weights + 16.0 GiB
   pool; Wilde: one card caps around 200k, no crash, no refusal).
5. **Host side barely shifts** (V3): checkpoint slots log-scaled (9–10 per 200K-class
   session, same class at 262144); the 80-slot × 144 MiB = 11.25 GiB store barely moves;
   the 24Gi band legs (24 ≥ 20 + 4; 24 − 8.5 = 15.5 ≥ 4) untouched; node fit
   24 + 4.125 + 1.158 = 29.3 ≤ 125.08 GiB unchanged.
6. **"Zero extra usable VRAM" verdict** (V5, S10): TRUE for the host pin (7.89 GiB pinned
   in BOTH the TP1 and TP2 rows — TP collectives stage through pinned host memory), FALSE
   for card VRAM (pool 12.48 → 40.08 GiB; ~199k → ~663,600 tokens at 64 KiB). The phrase
   is absent verbatim from the notes (RESEARCH open q4) — the carriers are the values
   "not a memory story" comment (:1570) + the roster "UP at what cost" column.
7. **The flash ceiling IS 262144** [round 2, F1 — research round 2, session
   `ses_dfa43b76cffex5QZ8Vj9E9pGf1`, live fetches 2026-11-23]: `Qwen/Qwen3.8-Flash-Next`
   `config.json` `max_position_embeddings: 262144`, `rope_type: "default"`, no
   `rope_scaling`; 48 layers = 12 full-attention + 36 linear, 2 KV heads, head_dim 256.
   Pack card wording: "262,144 tokens trained; **served at 200K**" — a serving CHOICE,
   not an empirical bound (the 27b card says "200K **tested**").
8. **fn's 200000 was MEASURED, unlike the 27b's** [round 2, F3, same session/fetches]:
   cf-143 D28(1)/D30(1) record the live boot print — container printed its budget and died
   `out of memory` at cgroup 64.00 GiB vs **71.04 GiB observed pinned** (that print is
   what the 110Gi hold rides), "200K funded ON-CARD (`kv cache 4.49 GiB a card:
   1600000 tokens, 8.0 sessions at 200000` ≈ 2.94 KiB/token), host term is the eager
   `--kv-resident` mirror — PROVEN eager because boot died with zero sessions arrived".
   Caveat: a TP1-era print; the first TP2 print is still owed (cf-144 P11). Raising fn
   OVERTURNS a measurement on our hardware — D9's informed risk (the measurement's
   provenance is preserved in prose, not erased — fact 16(c)).
9. **Upstream publishes NO 262144 serve shape** [round 2, F4]: of 57 compose files every
   27b variant ships `--max-model-len 200000`; `flashnext.yaml` ships `--tp 2
   --max-num-seqs 8 --max-model-len 200000 … --host-pool-mib 12288 --gpu-headroom-mib 96
   --prefix-cache-mib 4096 --num-speculative-tokens 3 --max-num-batched-tokens 2048`;
   `flashnext-tp1.yaml` ships `--tp 1 --max-num-seqs 4 --max-model-len 200000
   --host-pool-mib 43000` with the prefix tier and NO kv-resident; `flashnext-bf16.yaml`
   ships 32768. The only 262144 anywhere is the guide's §4.4.1 streaming-KV demo at
   **2 sessions** plus one third-party production witness (llmkube, 62 GiB host).
10. **Flash/fn arithmetic (config-derived + guide-corroborated)** [round 2, F2]: trunk
    12 KiB/token (12 layers × 2 KV heads × 256 × 2 × 1 B); the guide's published 6.00
    KiB/rank at TP2 reproduces the 12-layer trunk exactly and EXCLUDES the MTP drafter
    (so the drafter cost is UNVERIFIED: +1–2 KiB/token → 26.0–28.0 GiB). Worst case =
    seqs × bound. fn-TP2: 18.3 → **24.0 GiB** trunk against 2 × 31.86 GiB usable.
    flash-TP1 at held 110: ≈69–89 GiB used at both cost rates, engine rule
    `110 − 87 = 23 ≥ 4` → **fits**. Per-sequence recurrent state 54 MiB/copy/card × 2 ×
    8 = 864 MiB/card (unchanged); checkpoint slots 113.5 MiB, log-scaled (barely moves).
11. **Per-lane isolation, no FORM touch**: `RADIANCE_MAX_MODEL_LEN` is a per-lane env
    entry in ALL FOUR lanes (fn :1121, q27 :1367, flash-tp1 :1495, q27-tp2 :1588 — all
    "200000" in git, verified this fold); the chart wrapper reads it from env
    (`charts/radiance/values.yaml:218`); the FORM fixes only port/host/`max-num-seqs 8`/
    `kv-cache-dtype fp8` (parent-D46; `FORM_FIXED_FLAGS` testlib :936) — D6: 8 stays.
    The four env moves touch no FORM, no fn chart parameterisation — the D28(6) one-edit
    overlay law holds.
12. **Test-authority inventory (verified this fold, four lanes)**: `Q27_CTX` (testlib
    :332 — defined, referenced by no other leg — contract carrier); `Q27_PROFILE` (:282,
    `--max-model-len "200000"`, provenance comment claims "the D54-ratified serving
    profile … byte-for-byte" — the claim the raise DEVIATES from, by ruling);
    `q27_tp2_profile()` (:985, derived from `Q27_PROFILE` + the TP pair + its served id —
    inherits any parent move); `flash_tp1_profile()` (:966, DERIVED from git
    `e7536b2c9^` — the IMMUTABLE source, exactly ONE value swapped today — the served id;
    `FLASH_TP1_TRANSCRIPTION` :663 = `("e7536b2c9^", "charts/radiance/values.yaml")`);
    **the flash verbatim leg** (`test_resting_lanes.py:218-244`,
    `test_c05_flash_tp1_profile_is_the_cf143_tp1_array_verbatim_except_the_id`): diffs
    `git show e7536b2c9^:charts/radiance/values.yaml` (serveArgs) with EXACTLY one value
    swapped — re-pins to TWO (id + context) by ruling; `FULL_PROFILE` (fn, :120 —
    **no transcription leg**; its provenance is the comment at `values.yaml:1070-1072`,
    the cf-144 §7 recipe "byte-for-byte as the retired args array shipped it");
    `COMPOSITION_LANES` (:1003, all four lanes); `M8-B` (`surface.sh:1030-1073`: **the fn
    needle `assert str(mm) == "200000"` — D9 breaks it: C01 re-pins to 262144, designed
    red until C02**; the commentary slice names both figures via the stale comment —
    green pre- and post-C02); `M9-A2` (`surface.sh:1345-1515`: value half — all twelve
    family rows 262144, UNCHANGED by this ticket; prose half — the new-family commentary
    must name BOTH figures, the stale comment at :810-816 supplies 200000 — green pre-
    and post-C02, the restatement is the owner's C04 leg; `SERVED_FIGURE = 200000` gets
    the dated per-lane re-pin annotation); pre-move fixtures pinned at `8f3d5bbad`
    (HEAD-independent guard — the context move is a D43 MOVABLE path; no fixture leg
    legitimately fails; the fixture's 200000 argv stays the true pre-move fact).
13. **D47 lane-equality statement (VERIFIED, not assumed — the jsonc row census this
    fold)**: the twelve radiance-family rows are all `limit.context 262144` (verified at
    jsonc :720/:727/:734 fn trio, :776/:783/:790 q27 trio, :831/:838/:845 flash-TP1
    trio, :852/:859/:866 q27-TP2 trio). Post-C02, ALL FOUR radiance lanes end with
    **served == trained == 262144** — the D47 pair COLLAPSES to equality on every
    radiance lane. The unequal catalog context figures (131072 `qwen38-humanlike`; 16384
    ×45; 8192 ×2; 1010000 ×2) exist ONLY in non-radiance strata/llama.cpp rows (the
    strata row itself is 262144, equal to its own trained ceiling per its comment);
    M9-A2's scope is the twelve-row family and never governs those — the D47 unequal
    pair survives only OUTSIDE the family.
14. **Parent rulings that bind**: D28(6) (prints price numbers; estimates do not — the
  repair is the one-edit overlay; relaxed BY OWNER WORD for the context bound only, D3);
  D30 (test-file edits are never assignable to dev — the re-pin wave precedes the dev
  round); D35(2) (a changed fn pod spec rolls the default route — ~grace 180s + model
  load 502 window); D43 (env is the sizing channel; the wrapper composes argv — the boot
  echo is the receipt in place of argv); D46 (FORM-fixed flags); D47 (the ctx pairing
  law — restated here as D4, ANNOTATED, equality legal); D49 (the wrong-reason-red law —
  the receipt gate must assert the diagnostic names the reason); parent-D52/53 (state-
  file key discipline).
15. **Base state**: the parent ticket is COMPLETE and its work is MERGED (owner-confirmed
  2026-11-22; not re-litigated — FRICTION #1). Work continues in the EXISTING
  worktree/branch `feat-radiance-multi-instance`; the ticket's docs commits are
  `e4c094b43` (this plan, the two-lane draft) / `484ee8f31` (D5-D8) / `f31c40d41` (the
  flash round-2 evidence persistence — HEAD).
16. **Live-cluster fact (not a git fact)**: fn-TP2 is at `replicas: 0` by the OWNER'S
  SCALE ACT (git carries `replicas: 1` at :1063 — the hand scale sticks until that
  Application's next manual sync, the runbook's restore step). Consequences: (a) fn's
  receipt — the first TP2 print (cf-144 P11) — **cannot be captured until the owner
  brings fn back up**; the ask about fn was made BEFORE its value was written (FRICTION
  round-2 row); (b) C02's landing is a **second pod roll on the pipeline's own critical
  path** (parent-D16: every tier plus the hourly runner route through fn; D9(c)) — the
  roll window is stated to the owner BEFORE landing, per the parent-D35(2) shape.

## Commands (validation battery — every session exports PATH first)
- `export PATH=$HOME/.local/bin:$PATH` (without it the helm-guarded legs skip silently)
- `python3 -m pytest charts/radiance/tests -v` (per-directory; post-C01 the four lanes'
  composed-argv + M8-B + flash-transcription legs are DESIGNED-RED naming C02; all green
  after C02)
- `python3 charts/radiance/tests/capture_c03_fixtures.py` (the review tier's first step —
  the fixture guard re-derives at the pin; must pass: the context move is outside the
  fixtures' scope, fact 12)
- `bash tests/pipeline-models/surface.sh` (read-only run; M8-B green only AFTER its C01
  re-pin AND C02's env move; M9-A2 both halves green throughout — the value half is
  untouched, the prose half's stale commentary names both figures until the owner's C04
  leg; M9-B/M8-A/A2 green)
- `bash tests/notes/radiance-roster.sh` (the roster prose leg — T2 re-derives claims/
  replicas from the tree; the C02 annotations are prose, not claim cells; the D10 no-
  memory-change is what keeps T2 green)
- `helm lint charts/radiance && helm template charts/radiance` (chart sanity — the chart
  is NOT touched; guards against an accidental chart edit)
- `grep -n "RADIANCE_MAX_MODEL_LEN" services/gpu-ai/prod/values.yaml` (the four-lane env
  audit: exactly 262144 ×4 after C02)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Test-authority re-pin BY RULING for FOUR lanes, three DIFFERENT kinds: (1) 27b — `Q27_CTX`/`Q27_PROFILE`/`q27_tp2_profile()` → 262144, the q27 provenance record becomes a **deviation-with-ruling** (recorded, not pretended verbatim); (2) flash-TP1 — the **verbatim transcription leg changes shape** (the testlib `flash_tp1_profile()` + `FLASH_TP1_TRANSCRIPTION` comment + `test_resting_lanes.py:218-244`: "EXACTLY one value swapped" → "exactly TWO values swapped — id + context, per ruling D5/D9"; the fidelity claim is now bounded by ruling — the source commit is immutable, so the leg must never again be described as verbatim); (3) fn — a **constant re-pin only** (`FULL_PROFILE` — no git-diff leg exists; the provenance is the comment at `values.yaml:1070-1072`, the cf-144 §7 recipe — fn's change is CHEAPER in test terms and MORE expensive in risk terms, D9). Plus: the M8-B fn needle re-pin 200000 → 262144 (designed red until C02); the M9-A2 `SERVED_FIGURE` dated per-lane annotation (value half untouched; prose half preserved); TEST_SPEC §1 the per-lane served column for FOUR lanes; the D4 equality table (fact 13) written into the spec; the pre-authored **receipt command block** (D8) authored here — all four lanes enumerated, the nine-item set (RESEARCH implication (e)) + the eight-admitted-sessions smoke (D9(b)), the closing gate (close only if every item is present) and the script are ONE artifact | M | 1 | [] | the test wave runs before any dev (parent-D30); its designed reds name C02; the D8 block is one artifact with its gate so a lane-count change lands in both |
| C02 | The config move + prose plane — the FOUR env values 200000 → 262144 (fn :1121, q27 :1367, flash-tp1 :1495, q27-tp2 :1588), each with a dated PROVISIONAL annotation naming the pending receipt + ruling cites (D3(a); D1/D2 the 27b lanes, D5/D9 flash-TP1 + fn); the values WHY comment (:1344-1352) annotated with the V3 correction + the flash/fn F2/F3 framing; the "not a memory story" comment (:1570) + the roster "UP at what cost" column annotated with the V5 verdict (host-pin TRUE / card-VRAM FALSE 12.48 → 40.08 GiB); the fn block comment (:1070-1072) reads **superseded by ruling D9, the measurement provenance PRESERVED** (the cf-143 D28(1)/D30(1) print stays quoted — the reason fn's raise is risky is precisely that a measurement existed); the boot note's "honest envelope" section (:300) annotated as pre-D47 history; the **fn roll consequence stated** (D9(c): second pod roll on the pipeline's own critical path — parent-D16; the roll window stated to the owner BEFORE landing; the boot echo is the receipt of what the engine received, parent-D43(2)); the one-home table + roster §3 + NOTES.txt re-checked UNCHANGED with the proof (D10: no memory value moved — claims/replicas/cgroup pairs are orthogonal; fact 5/11) | M | 2 | [C01] | greens C01's designed reds (the four profiles and the rendered envs must meet at the composed vectors); the prose pins the values it governs in the same commit (cf-144 C02 precedent) |
| C03 | The pre-agreed revert leg — CONDITIONAL, PER-LANE triggers: **27b-TP1** (PREDICTED not to fit — V3/S10 ~199k cap; warn-not-refuse → a truncated-pool serve: OOM/refuse/truncate, the `kv: pool backs N%` line under-funding, or the ~199k cap) and **flash-TP1** (PREDICTED to fit per F2 — its scale-up failure mode is the LOUD start-refusal, guide :1092-1093, unlike 27b-TP1's silence) and **fn-TP2** (D9(a): **M < 8** in the pool-backs line is the refutation — the silent failure mode, the eight-admitted-sessions smoke is its loud check, D9(b)). Pre-authored per-lane contracts: 27b — the existing Q27_PROFILE split (Q27_PROFILE keeps 200000 for TP1; `q27_tp2_profile()` gains the explicit override; `Q27_CTX` per-lane pair); flash-TP1 — `flash_tp1_profile()` drops the context override (back to the single-swap derivation) and the transcription leg re-pins to "one value swapped"; fn — `FULL_PROFILE` re-pins to 200000 + the M8-B needle back. The dev round makes the per-lane env edit(s); DECISIONS records each refuting print as the receipt (the D28(6) one-edit overlay repair — FORWARD fix commit, never a revert of the merge). If a lane's print CONFIRMS, that lane's leg retires as a no-op, the confirmation recorded in C04. Executor: a follow-up dev session under the coordinator, owner-triggered by the refuting print, test re-pin first (parent-D30) | S | 3 | [C02] | the revert must follow the landed config; the test re-pin wave precedes the dev round (D30) |
| C04 | The receipts-close leg — ALWAYS (post-merge follow-up, the owner runs the D8 command block once at the scale act): records the FOUR-LANE receipt set (the nine-item set per lane + the eight-admitted-sessions smoke for fn, D9(b)) in DECISIONS + the boot note; closes PROVISIONAL **only if every item is present** (the D8 anti-drift gate — parent-D49: a gate that can pass on absence is not a gate), by dated annotation naming the leg/commit that closes it (D3(d)); retires the parent-D47 dissent by item 9 (a near-262144 session accepted — for fn, the M ≥ 8 bar, D9(a)); records the owner-prose jsonc commentary restatement as the OWNER's leg (parent-D27 — not executed by this ticket); **states explicitly, per D10, that NO memory value moved in this ticket** (the held 110/24/110Gi pairs are untouched; nothing here pre-empts those prints — the guard against a "helpful" re-pin during this leg) | S | 3 | [C02, C03] | C03 if any lane triggered (the refutation must be recorded before the close); otherwise the no-op confirmations are recorded here |

## Wave order
1. **C01** (the test wave — four lanes, three authority kinds + the D8 block; designed
   reds: the four lanes' composed-argv legs, the M8-B fn needle, the flash transcription
   leg — all naming C02; everything else green, fact 12).
2. **C02** (the config move + prose plane; the designed reds green; full battery green;
   the fn roll window stated to the owner BEFORE landing — D9(c)).
3. **C03** (conditional, per-lane — the owner's prints adjudicate; a confirming print
   retires that lane's leg as a no-op, recorded in C04) → **C04** (the receipts close —
   the D8 gate; the PROVISIONAL status closes here, the named leg/commit). C03 and C04
   are POST-MERGE follow-up legs — the owner's receipt sequence is a follow-up leg, never
   a gate before the config edit (D3).

## The four-lane authority table (fold 2026-11-23 — what moves where, and what adjudicates)
| Lane | What changes in tests (C01) | What changes in config (C02) | The adjudicating print |
|---|---|---|---|
| `radiance` (fn-TP2) | `FULL_PROFILE` constant re-pin only (`--max-model-len` 200000 → 262144 — NO transcription leg exists; the provenance comment at `values.yaml:1070-1072` is superseded by ruling D9, the measurement provenance preserved); the M8-B fn needle re-pins 200000 → 262144 (designed red until C02) | env :1121 200000 → 262144, PROVISIONAL (D5/D9) | the `kv: pool backs N% … M full-length sessions` line — **M ≥ 8 is the pass bar (D9(a)); M < 8 is the refutation** (C03); the first TP2 print (cf-144 P11, still owed — fn is at 0 live, fact 16); the VRAM-split lines (the 2.94 vs 12 vs ~60 KiB/token on-card basis); the eight-admitted-sessions smoke (D9(b)) |
| `radiance-q27` (27b-TP1) | `Q27_PROFILE` + `Q27_CTX` → 262144, the provenance record becomes a **deviation-with-ruling** (recorded with the D1/D2 cites, not pretended verbatim) | env :1367 200000 → 262144, PROVISIONAL (D1/D2) | the pool-backs line vs the PREDICTED ~199k cap (V3/S10); the VRAM-split (the 32-vs-64 KiB question); the ~199k cap line if it appears |
| `radiance-q27-tp2` (27b-TP2) | `q27_tp2_profile()` inherits by derivation (dated derivation note — no second literal); `COMPOSITION_LANES` verified under the moved constants | env :1588 200000 → 262144, PROVISIONAL (D1) | the pool-backs line (the V3 fit is MEASURED — ~100 MiB headroom/card, S10); the eight full 262144 sessions |
| `radiance-flash-tp1` | the **verbatim leg changes shape** (testlib `flash_tp1_profile()` + `FLASH_TP1_TRANSCRIPTION` comment + `test_resting_lanes.py:218-244`: "EXACTLY one value swapped" → "exactly TWO values swapped — id + context, per ruling D5/D9"; the fidelity claim is bounded by ruling — the source commit is immutable, the leg is never again described as verbatim) | env :1495 200000 → 262144, PROVISIONAL (D5) | the start-refusal vs boot (guide :1092-1093 — flash-TP1's failure mode is LOUD); if it boots: the pool-backs line (F2: fits held 110 at both cost rates, ≈69–89 GiB used, `110 − 87 = 23 ≥ 4`) |

## Scope seams → chunk (with the ruling authority)
1. **Lane values** `RADIANCE_MAX_MODEL_LEN` — all four: fn :1121, q27 :1367, flash-tp1
   :1495, q27-tp2 :1588 → **C02**; authority: D1 (27b-TP2, V3 fit) + D2 (27b-TP1, the
   print adjudicates) + D5/D9 (flash-TP1 + fn-TP2 — the informed ruling, the M ≥ 8 bar).
   Verified per-lane isolation, no FORM touch (fact 11).
2. **Test authorities** — the three kinds (fact 12; the table above) → **C01**; authority:
   D1/D2 BY RULING (the q27 provenance DEVIATES, recorded with the cites); D5/D9 (the
   flash verbatim leg becomes a deviation-with-ruling — the source `e7536b2c9^` is
   immutable, the lane MOVES, the fidelity claim is bounded by ruling); the fn constant
   re-pin (no leg to convert — the provenance is the comment, superseded by ruling D9,
   the measurement preserved); the M8-B fn needle (D9 breaks the draft's "verify-only"
   assumption — the fold's correction); the pre-move fixtures UNTOUCHED (no fixture leg
   legitimately fails — the pinned baseline, the D43 movable path, the true pre-move
   history). The only legitimate reds are C01's designed reds until C02.
3. **D47's ctx pairing law** (M8-B/M9-A2/TEST_SPEC §1) → **C01** (+ the D4 DECISIONS
   annotation, plan tier): restated law `trained >= served` per lane, EQUALITY LEGAL —
   the VERIFIED consequence (fact 13): post-C02 ALL FOUR radiance lanes end with served
   == trained (262144 == 262144); the D47 unequal pair survives only OUTSIDE the family
   (the strata/llama.cpp rows: 131072/16384/8192/1010000 — M9-A2 never governs them).
   Unchanged legs: the M9-A2 value half (twelve rows 262144 — already true), M9-B (key
   sets), M8-A/A2 (the priority ladder). Changed legs: the M8-B fn needle (200000 →
   262144, designed red until C02); the M9-A2 `SERVED_FIGURE` annotation; TEST_SPEC §1
   (the per-lane served column, four lanes). D47 is ANNOTATED, never rewritten (the
   D48 idiom).
4. **Prose carriers** (annotate-never-rewrite; the authority is this ticket's DECISIONS —
   the parent's files are approved): (a) the roster "UP at what cost" column + the
   values "not a memory story" comment (:1570) — the "zero extra VRAM" claim (absent
   verbatim, RESEARCH open q4) corrected with the V5 verdict (host-pin TRUE 7.89 GiB
   both rows; card-VRAM FALSE 12.48 → 40.08 GiB) → **C02**; (b) the boot note's "honest
   envelope" section (:300) — annotated as pre-D47 HISTORY (the print is the authority;
   the number stays as history) → **C02**; (c) the fn block comment (:1070-1072) —
   reads **superseded by ruling D9, the TP2 print pending** — the measurement's
   provenance (the cf-143 D28(1)/D30(1) print) is PRESERVED, not erased → **C02**.
5. **One-home table + roster §3 co-boot arithmetic + NOTES.txt shell law** → **C02**
   re-checked: UNCHANGED, with the proof — claims and replicas are orthogonal to the
   context bound (fact 11); the bound touches GPU pool sizing + log-scaled checkpoint
   slots (fact 10: the 11.25 GiB store barely moves; 113.5 MiB slots); the host pin is
   identical (V5); the held 24Gi/110Gi cgroup pairs are UNMOVED (**D10: no memory value
   changes anywhere in this ticket**); the node fit 29.3 ≤ 125.08 and the
   110 + 24 + ~5.3 > 125.08 co-boot arithmetic rest on the cgroup pairs, which do not
   move; `charts/radiance` is not touched.
6. **Out-of-scope seams (ruled)**: `max-num-seqs` (D6: stays 8 — a FORM change, its own
   future ruling + print); memory values (D7/D10: print-gated, no change here); catalog
   rows (parent-D27 owner-protected, already 262144); chart version bumps (chart
   untouched); the 1M/YaRN path (Deferred + revisit trigger).

## The TP1 both-path design (D2/D9 — written in advance, PER-LANE)
The owner directs the raise be ATTEMPTED on the TP1 lanes too and the boot prints
adjudicate, AGAINST the coordinator's recommendation (the dissent is recorded in
DECISIONS D2/D9 in full). The two TP1 lanes have DIFFERENT predictions and DIFFERENT
failure modes:
- **27b-TP1 — PREDICTED not to fit** (V3/S10: a single 32 GB card caps measured fit
  near ~199,472 tokens at the ~64 KiB effective cost), and the engine is fit-to-
  available with a WARNING — no crash, no refusal (V2; Wilde's 263k probe) — so a
  non-fit 27b-TP1 will likely boot and serve on a TRUNCATED pool rather than fail
  loudly (the warn-not-refuse hazard). **Outcome A** (boots and serves with the pool
  funding the 262144 worst case — the pool-backs line covers a full 262144 session):
  keep; the confirmation is recorded in C04. **Outcome B** (OOM / refusal / truncation —
  the print under-funds, shows the ~199k cap, or serves truncated): C03 reverts 27b-TP1
  to 200000 via the pre-authored contract (the Q27_PROFILE split; test re-pin first,
  parent-D30); the refuting print is quoted as the receipt.
- **flash-TP1 — PREDICTED to fit** (F2: ≈69–89 GiB used at held 110 at both cost rates;
  engine rule `110 − 87 = 23 ≥ 4`), and its scale-up failure mode is the LOUD start-
  refusal (guide :1092-1093: at `--tp 1` the host copy for 2×262k "does not fit beside
  the weights, and the start is refused") — unlike 27b-TP1's silence. **Outcome A**
  (boots and the pool-backs line funds the worst case): keep; confirmation in C04.
  **Outcome B** (the start is refused, or the pool under-funds): C03 reverts flash-TP1
  to 200000 — `flash_tp1_profile()` drops the context override (back to the single-
  swap derivation), the transcription leg re-pins to "one value swapped", the env edit
  reverts; the refusing print is quoted as the receipt.
- **fn-TP2** is not a TP1 case, but D9 makes its refutation explicit: **M < 8** in the
  pool-backs line is the refutation (the silent failure mode — an under-funded fn
  serves fewer than 8 concurrent sessions without crashing; the eight-admitted-
  sessions smoke, D9(b), is the loud check). The revert path is the pre-agreed forward
  fix (C03's fn contract: `FULL_PROFILE` re-pins to 200000, the M8-B needle back),
  never a live improvisation.
Executor of C03: a follow-up dev session under the coordinator, owner-triggered by the
refuting print, test re-pin first (parent-D30). The 32-vs-64 KiB / on-card-basis
question (the 2.94 vs 12 vs ~60 KiB/token) rides on the prints' VRAM-split + pool-backs
lines — the plan is written for both outcomes.

## Landing shape (the receipt sequence is a POST-MERGE follow-up leg, not a gate)
- C01 + C02 land locally on the existing branch `feat-radiance-multi-instance` (one
  commit per chunk); **push/PR/merge are OWNER legs** (never advance main from a
  session; a plan step that says otherwise is void).
- The 262144 values MERGE before any print supports them — the D3 consequence, recorded
  in DECISIONS D3: the four values are marked **PROVISIONAL in place** (dated annotation
  naming the pending receipt + the ruling cites), so an unobserved value in git is
  visible, dated, and bounded.
- **The fn roll (fact 16(b), D9(c))**: fn is the live default route for every tier plus
  the hourly runner (parent-D16) — but fn is at `replicas: 0` by the owner's own scale
  act (git carries 1). What the owner should expect: C02's landing changes fn's pod
  spec, so the next time the owner brings fn back up (or re-syncs the Application) the
  fn pod ROLLS — ~grace 180s + model load 502 window (the parent-D35(2) shape) — and
  that boot is the receipt of the new value: the wrapper's startup echo of the composed
  argv is the receipt in place of the argv (parent-D43(2)), and the first TP2 print
  (cf-144 P11, still owed) lands on that boot. The roll window is stated to the owner
  BEFORE landing, per D9(c). The 27b and flash-TP1 lanes rest at `replicas: 0` in git —
  the merged config has ZERO scheduling impact on them until the owner's scale act.
- **fn's receipt is unobtainable until fn is back up** (fact 16(a)): the ask about fn
  was made BEFORE its value was written (FRICTION round-2 row) — this is the D9
  informed-risk sequence, not a defect.
- Post-merge follow-up legs (owner-triggered, the receipt sequence): (1) the owner's
  scale acts (the swap order: fn DOWN first is no longer the constraint — fn is already
  0 — then the lane(s) UP); (2) the owner runs the D8 command block once (the
  pre-authored single command block, authored in C01 — all four lanes, the nine-item
  set + the eight-admitted-sessions smoke); (3) the prints speak (per-lane
  adjudication); (4) C03 (any refuted lane — the pre-agreed forward fix) → C04 (the
  D8 gate closes PROVISIONAL only if every item is present; the named leg/commit,
  D3(d)). A later contradicting print unwinds an already-merged config by a FORWARD fix
  commit (the D28(6) one-edit overlay repair; the refuting print quoted as the receipt;
  a fresh DECISIONS line) — never a revert of the merge, never history rewriting (D3(c)).

## Risks / assumptions
- **Warn-not-refuse means a silent bad raise — and fn is the live default route** (V2;
  D9's core hazard): an under-funded fn would not crash — it would SILENTLY serve fewer
  than 8 concurrent sessions, the one property a shared default route exists to provide.
  Mitigation: the M ≥ 8 pass bar is the named adjudicator (D9(a)); the eight-admitted-
  sessions smoke is the loud check (D9(b)); C03's fn contract is pre-authored; the
  receipt is mandatory before C04 closes the PROVISIONAL. The owner's risk acceptance is
  recorded in D9, informed (the four grounds shown before the ruling).
- **A provisional value merging before its print** (D3's accepted consequence): 262144
  is in git unobserved on four lanes. Mitigation: (a) the PROVISIONAL annotation in
  place (dated, naming the pending receipt + ruling cites); (b) the pre-agreed per-lane
  revert path + named executor (C03); (c) the contradicting-print unwind pre-agreed
  (forward fix, one-edit overlay — D3(c)); (d) the named close leg (C04, the D8 gate)
  so PROVISIONAL cannot silently become permanent. The D28(6) relaxation is recorded in
  DECISIONS D3 BY OWNER WORD and scoped to the context bound ONLY — the memory re-pin
  stays print-gated (D7/D10: nothing to pre-empt — F2's arithmetic closed the sizing
  question).
- **fn's roll on the pipeline's own critical path** (fact 16(b), D9(c)): the owner is
  stated the roll window BEFORE landing; fn is at 0 live by the owner's scale act, so
  the roll happens on the owner's next bring-up/re-sync — the 502 window is bounded by
  grace 180s + model load, and that boot doubles as the first TP2 print (cf-144 P11).
- **The invariance gate's expected behaviour**: the context move is a MOVABLE path
  (env); the pre-move fixtures stay the immutable pinned baseline (`8f3d5bbad`) with
  their 200000 argv as true history; the per-property legs (image/probes/
  securityContext/claim/memory/cpu/replicas/grace) stay GREEN and are the proof
  NOTHING ELSE moved (the D10 no-memory-change is what keeps the claim/memory legs
  green); the only legitimate reds are C01's designed reds until C02. A red fixture leg
  would be the guard working (a hand-edited fixture or a dependency-borrow failure),
  not the raise.
- **The on-card basis is unsettled** (the 2.94 vs 12 vs ~60 KiB/token — RESEARCH open
  q1/q3 + round-2): the coordinator's INFERRED reconciliation is that the measured 2.94
  ≈ the INDEXER cache (12×1×128×2×1 B = 3,072 B), with bulk attention on the host-
  mirror side — an INFERENCE, not evidence; the MTP layer's paged-cache cost is
  UNVERIFIED (+1–2 KiB/token → 26.0–28.0 GiB on the fn worst case). The prints'
  VRAM-split + pool-backs lines settle it (Open questions below — listed so no session
  invents answers).
- **Stale owner-protected commentary**: after C02 the jsonc comments ("Served admission
  is the other number … 200000" for the new family; "Context 200000 is what the pod
  serves" at the fn rows) are half-stale; the legs stay GREEN (the needles name both
  figures); the restatement is the owner's prose leg at C04 (parent-D27) — recorded,
  not executed.

## Open questions (PRINT-PENDING — listed so no session invents answers; no open OWNER questions remain — D5/D6/D7/D9/D10 settled them all)
1. **Does the MTP layer paged-cache?** — the drafter cost is UNVERIFIED (+1–2 KiB/token
   → 26.0–28.0 GiB on the fn worst case). Answered by: the VRAM-split lines (receipt
   item 2, all lanes).
2. **The first TP2 print (cf-144 P11, still owed)** — fn's 200000 measurement is a
   TP1-era print (fact 8); the TP2-era print lands on the owner's next fn bring-up
   (the roll, fact 16(b)). Answered by: that boot's full print.
3. **Does the TP2 pool fund 8 full 262144 sessions?** — the `kv: pool backs N% … M
   full-length sessions` line adjudicates (the M ≥ 8 bar, D9(a)). Answered by: receipt
   item 3 (all lanes).
4. **The 2.94 vs 12 vs ~60 KiB/token on-card basis** — the coordinator's INFERRED
   reconciliation (2.94 ≈ the indexer cache 12×1×128×2×1 B = 3,072 B, bulk attention
   on the host-mirror side) is an INFERENCE, not evidence. Answered by: the VRAM-split
   + on-card kv lines (receipt items 2–3).
5. **The ngram/indexer contribution to the worst case** — Answered by: the VRAM-split
   lines (receipt item 2).

## Deferred (recorded, not planned)
- The 1M/YaRN factor-4 path — NOT engine-validated (S7: only factor 2, to 524288, is
  validated on this model). Revisit trigger: a fresh YaRN validation pass + an owner ruling.
- The stale jsonc commentary restatement — the owner's prose leg at C04 (parent-D27
  owner-protected; the legs stay green meanwhile — the needles name both figures).
- `max-num-seqs` 8 → 32 — D6: a FORM change (parent-D46; `FORM_FIXED_FLAGS`); a fresh
  ruling + a fresh print (upstream's 32 recorded as a legitimate future ruling).
