# CB1: contract amendment — display-field relaxation, shorthand-aware ref tests, compensating presence contract
size: M   wave: 6   depends_on: [user CR5 ruling (Option 2 + relax-P2-display + full normalization, 2026-10-24)]
TEST-SESSION-ONLY chunk: agent-test session ses_e9bdebccbffe7bYG46Fm9LO8FG writes this
(tests immutable downstream; CA1-style). Plan states the ruling + bars; the test author
owns expression and MUST verify satisfiability by EXECUTING against a final-shape
fixture (standing §7ter method correction).

## Goal
Rebase the contract for CR5 Option 2 under the user's relaxation ruling:
(1) P2's golden deep-compare stops pinning display text (name/description) — the ONE
user-ratified weakening, replaced (not dropped) by a compensating contract;
(2) the two value-shape schema tests accept repo/tag shorthand rungs (effective refs
computed through the culture maps);
(3) the schema-key strip contract grows to the new values-only keys.
Everything else — IDs (P1), cmd token multisets (P2-cmd), echo byte strings (P3),
removals (P4), echo shapes (P5), matrix (P6), aliases/capabilities/ttl/proxy/filters/
checkEndpoint/env (P2-rest-minus-display) — keeps today's bars UNBENTED.

## Tasks
- [ ] `test_config_parity.py::test_c02_2_per_model_fields_deep_equal`: excise
      `name`/`description` from the compared `rest` dicts (golden + fresh), everything
      else untouched. Docstring names the CR5 ruling (user-ratified 2026-10-24) and
      points at the compensating contract below. §7quater records the deletion-audit
      (this is the only assertion-scope removal in the amendment, and it is
      compensated, not bare).
- [ ] NEW compensating tests (replacing the golden display pin):
  - display PRESENCE: every catalog id in both cluster renders carries a non-empty
    `name` AND `description` (58×2×2) — red if CB2 deletes display text without
    composing it.
  - display GRAMMAR-CONSISTENCY: for chart-composed (non-escape, non-models-overridden)
    rungs, rendered `name` matches `{disp}(…({TAG}…))` shape mechanically: TAG token
    present in the name for hf rungs (the one property consumers/`size`-less review
    can machine-check); description mentions the same TAG for ladder rungs. Deviation
    allowances: models-layer overrides + raw-cmd escape ids (whisper-large-v3,
    qwen38-rana). Keep it SHAPE-only — the exact-text review is the user's
    before/after table, not a test.
- [ ] `test_c02_chart_models_are_composition_or_documented_escape_hatch` offenders
      rule: a rung resolves if it has literal `hf` OR composes from
      (`repo`|`fam.hfRepo`) + (`tag`|culture-map[quant-key]) — read the culture maps
      FROM chart values `config.tagCultures` (single source; no test-side copy).
- [ ] `test_c02_chart_composition_hf_refs_match_golden`: `eff.get("hf")` becomes the
      same effective-ref composition; draft stays full-literal; golden `-hf` token
      compare + B/D/G2 routing UNCHANGED (refs are cmd-side contract — NOT relaxed).
- [ ] `test_fam_key_stripped_from_rendered_output`: extend the strip list to
      dispName/descBase/descTail/size/disp/suffix/hfRepo/tag/tagCulture/repo
      (+ `tagCultures` as a top-level config key) — none may appear in rendered config.
- [ ] TEST_SPEC §7quater: amendments + ruling provenance + zero-OTHER-deletion audit;
      expected-state bars for CB1 handoff and CB2 completion.

## Files in scope
- charts/llama-swap/tests/test_config_parity.py
- charts/llama-swap/tests/test_config_schema.py
- charts/llama-swap/tests/llama_swap_testlib.py (composition helper reading
  config.tagCultures, if needed)
- charts/llama-swap/tests/TEST_SPEC.md

## Acceptance criteria
1. Goldens `git diff` empty. Amendment diff audited: exactly one relaxation (display
   fields out of P2-rest), restated with provenance; all other changes are ADDITIVE or
   shape-tolerant (accept literal AND shorthand refs).
2. Handoff state (CA1 pattern): red set == the shorthand/stripping tests, messages
   naming CB2; display presence/grammar tests GREEN at handoff (they must stay green
   on HEAD AND post-CB2 — they cannot be CB2-named reds; they are the replacement
   contract). If the author instead tightens the offenders/hf tests to shorthand-only,
   those flip to red-naming-CB2 — either posture compliant, recorded in §7quater.
3. Full `pytest charts/llama-swap/tests -v` at handoff: 0f except the CB2-named reds;
   wiring 32, roster 30, image 6P/4S, CI 33, gates 3p/5s all green; P2-cmd + P3
   untouched (review diffs their code).
4. Compensating tests EXECUTE against a final-shape fixture (synthetic shorthand
   overlay mirroring CB2's planned schema) — §7ter method.

## Tests (agent-test writes, review runs)
The amended + new tests above; review re-runs the whole suite at CB2 completion and
audits this amendment assertion-by-assertion.

## Notes for dev
N/A — this IS the test-session round. CB2 dev starts only after CB1 lands.

## Review notes (review agent fills)

### Round 1 — 2026-10-24 (fresh-context review; commit 724d27e3b; verdict: **APPROVED**)

**Validation re-run (all bars met exactly):**
- `pytest charts/llama-swap/tests -v` => **2 failed / 153 passed / 12 skipped**, zero
  collection errors. Red set name-identical to the handoff: `test_cr5_shorthand_composition_render`
  + `test_cr5_unresolvable_rung_fails_render`. Failure bodies read: both precise and
  implementation-missing — U-2 asserts `culture-composed ref wrong: None (CB2)` on a
  rendered-but-uncomposed synthetic (rc=0 at HEAD, entry exists, cmd lacks -hf), U-3
  asserts rc!=0 with the rendered rc=0 output tail quoted. Neither fails for a harness
  reason. Per-file recount: parity 34P/0F, schema 18P/2F, wiring 32P/0F, roster 30P/0F,
  image 6P/4S; CI subset (convert_lora 3 + llama_tools 20 + render 7 + provenance 3) =
  **33P**; skip inventory = the established 12 evidence gates (4 image docker + 8
  integration), no new skip.
- `LLAMA_SWAP_EVIDENCE=1 -k autogen_integration` => **3 passed / 5 skipped** unchanged.
- `git diff 49e977faf..HEAD -- tests/golden` => **0 lines** (acceptance 1 ✓).
- `cmd_tokens` + `model_tokens` extracted full bodies vs `49e977faf` => **byte-identical**
  (the earlier partial-range diff was re-done as whole-function spans).
- `helm lint --strict` + gpu/gpu-ai renders => pass (no chart-side change in a tests-only commit).
- `git show 724d27e3b --name-only` => exactly the 4 in-scope test files; no drift vs parent
  (acceptance scope ✓).
- `aislop scan charts/llama-swap/tests` => **0 errors / 12 warnings**, all pre-existing
  classes (testlib decorative separators — incl. the new CR5 section header, house style;
  size ceiling, testlib now 662 lines, acknowledged as in CA1-r2; hf_check URL;
  chained-get at testlib:164 pre-existing). None in the new parity/schema code.

**Amendment-honesty audit (CA1-Round-1 class), verified mechanically:**
- (a) **P2 display excision is surgically exact.** `rest` = every entry key except `cmd`
  (byte-identical `model_tokens`); `_strip_display` removes ONLY top-level
  `name`/`description` from both sides. Executed probes: a synthetic nested
  `metadata.name` tamper is **still caught** by the excised comparison (over-excision
  impossible — the dict comprehension is top-level-exact-key, no substring matching:
  `useModelName` survives); the top-level display keys always leave. Docstring names the
  user ruling (2026-10-24) and points at S1/S2/S3. Everything else in the loop
  (keys, ordering, `_first_diff_key`, REMOVED-subtraction) byte-unchanged per diff.
- (b) **Replacement coverage vs excision — honest, independently re-derived.** Presence
  58×2×2 zero gaps both clusters. Name-grammar: 0 raw violations pre-exemption (33 live
  gpu / 57 gpu-ai tagged ids — so the exemption never had to absorb a violation at HEAD).
  Desc-TAG escapes re-derived from HEAD values: **1 ladder-scoped violation (fn-orca-q6,
  the documented `DESC_PROSE_EXEMPT_FAMILIES` entry)** + 6 non-ladder-key violations
  (qwen36 heretic/huihui, qwen38 ara/humanlike/orca/rana) — every escapee is one of the
  plan-measured prose classes, each is still presence-pinned and name-grammar-pinned,
  each is an `id × {name,description}` row in the CB2 before/after table (58-ID scope),
  and the CB1 handoff open_question already binds dev to record keep-explicit rows there.
  fn-orca + qwen36/qwen38 coverage is honest: no pair escapes ALL THREE of
  {presence, grammar-shape, table}. Exemptions are data-driven (family/key/model-layer),
  zero per-string exemptions.
- (c) **No test-side culture table.** `rung_effective_ref` reads `chart_cfg["tagCultures"]`
  only — callers pass `L.chart_values()["config"]` (the same file CB2's templates read);
  HEAD has no `tagCultures`, so both amended tests (`T1 offenders`, `T2 hf-refs`) resolve
  to the literals and are GREEN both states — shape tolerance, not a frozen copy. The
  draft leg of T2 stays full-literal per CR5 (comment pins it). `LADDER_QUANT_KEYS` is an
  obligation-scope policy list, not an implementation mirror.
- (d) **Per-cluster models-layer exemptions computed from service values, correctly.**
  gpu exempts 7 ids, gpu-ai 6 (lists diff as expected: gpu ornith×3+vl30b+q36-35b×3,
  gpu-ai qwen3.8-27b×4+q36-35b-q8+rana). Cross-read probe: every gpu-exempted id is
  still grammar-asserted on gpu-ai (and vice versa for qwen3.8-27b on gpu), except
  `qwen3.6-35b-a3b-q8` (models-overridden BOTH clusters → its display is service data
  outside derivation reach by construction) and `qwen38-rana`/`whisper-large-v3`
  (the plan-documented raw-cmd escape pair). Union: **55/58 name-asserted, 58/58
  presence-asserted**; the 3 never-asserted are exactly the documented classes.
- (e) **Forward-satisfiability simulated (throwaway, /tmp/opencode/cb1-review-sim.py).**
  Built a final-shape values mirror from the plan's pinned fit tables (tagCultures
  standard/unsloth-ud, per-family hfRepo, culture + repo/tag exceptions, qwen38/qwen36/
  fn-orca/q8-visual/q8-1m keep literals) and a compliant-render mirror (grammar-composed
  name/desc, models layer merged, refs byte-identical). Results: **0 ref-fidelity
  mismatches** (composed == HEAD literal for all 57 hf rungs ⇒ cmd-token parity and the
  T2 golden-compare cannot be broken by compliant composition), 0 unresolvable rungs
  (T1 clean in final shape), S1 gaps 0, S2 violations 0 over 30/51 asserted, S3 violations
  0 over 27/36 asserted, P2-rest(exc cmd/display) 0 divergence while an alias-tamper is
  still caught, and **all seven U-2 outcome bars pass against the exact pinned grammar**
  ("CR5 Smoke (Q4_K_M) - probe", "CR5 Smoke (Q8_0, MTP)", size-interpolated desc, no
  leaks). U-3's fail mechanism is proven available (the dup-ID render-fail test is green
  today). No KeyError/AttributeError/shlex-opaque class found: every index is guarded or
  on a P1-forced-present path; `cmd_effective_tag` carries the ratified G2 token-boundary
  fallback; echo/no-tag rungs skip via predicate, presence still covers them.
- Deleted-assertion sweep: **all 12 removed diff lines map 1:1** to §7quater entries
  (P ×4 incl. docstring, T1 ×2, T2 ×3 — one is a cosmetic reflow of the draft-leg message,
  U-1 ×3 — the old single-key assert replaced by a strict superset ban list). Exactly one
  assertion-scope reduction (display fields), compensated, user-ruling provenance in both
  code docstring and §7quater-P. No weakening anywhere else; T2/U-1 became supersets.

**FINDINGS** (no blocker/major):
1. **minor** `TEST_SPEC.md:614` — "CB2 completion bar: 0 failed / **159 passed** / 12
   skipped" is an arithmetic slip: 147 pre-CB1 + CB1's 8 new tests (6 parity + 2 schema)
   = **155** (167 collected − 12 skips; evidently 147+12 was summed instead). The
   authoritative bars elsewhere are correct (CB2.md "(147 + CB1's new tests)" and
   §7quater's own per-file recount imply 155), so CB2 dev is unaffected — but a literal
   recount at CB2 review would false-alarm "4 tests missing" (C04-review "7(D) says 17,
   is 16" nit precedent). Fix: one digit on the next TEST_SPEC touch; coord should task
   CB2 with the corrected bar **0f/155p/12s** when kicking it off.
2. **nit** `llama_swap_testlib.py:633` `rung_effective_ref(chart_cfg, fam, spec, quant)` —
   `fam` parameter unused in the body (callers pass it positionally; harmless, but it
   reads like the G1 str/dict hazard shape it replaced).
3. **nit** `test_config_schema.py:160-161` — the draft-leg `problems.append(...)` reflow
   puts the `# draft stays full-literal (CR5)` comment inside the call parens with the
   closing paren on its own line; valid but reads like a truncated expression — fold onto
   one line on next touch.

**Carry-forward for CB2 review** (this chunk's §7quater-class obligations):
- The replacement tests are **never acceptable as CB2-named reds**: presence,
  name-grammar and ladder-desc must be green at CB2 completion (they pin the post-derivation
  surface; a legit CB2 prose escape is only via the documented exemption classes).
- CB2 review must independently re-run the rest-invariance diff (acceptance 1: three
  renders before/after with only name/description excised => byte-equal), the
  new-schema-key grep over ALL THREE rendered ConfigMaps (U-1 pytest covers the gpu+smoke
  render; the plan's grep command is the three-render bar), the display-table row count
  (58 × {name,description} × both clusters, every keep-explicit row present), and
  corrected-suite recount 0f/155p/12s per finding 1.
- Models-layer precedence probe (CB2 acceptance 5) covers the class this review could
  only mirror in python: a models-layer `hf` override must NOT re-derive display text.

**Deferred:** none out of scope; everything found is inside the tests/** tree CB1 owns.

Verdict: all four acceptance criteria met with evidence; the amendment is superset-honest
(the one relaxation is exactly the user-ratified display excision, compensated four ways),
downstream-satisfiable on every simulated edge, and both reds are precise implementation-
missing gates on CB2. Findings 1-3 are record-hygiene, non-blocking. **APPROVED.**
