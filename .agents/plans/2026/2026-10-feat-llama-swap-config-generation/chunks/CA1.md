# CA1: contract rebase — superset parity, family schema, isolation flip, entrypoint wiring
size: M   wave: 3   depends_on: [user approval of the 2026-10-24 replan — GRANTED: removal set ruled (B + coder-next-ablit), in-repo consumers fixed in-PR, architecture approved]

EXECUTED ONLY BY THE TEST-WRITER SESSION ses_e9bdebccbffe7bYG46Fm9LO8FG (the suite is the
immutable contract; no other session may edit charts/llama-swap/tests/**). Tests-only: writes
no implementation. Ground truth: plan REPLAN 2026-10-24 sections CR1–CR4 (post-ruling text).

## Goal
Re-express the test contract for the replanned surface — family-keyed catalog with
default-disabled rungs, removals, and the relocated image entrypoint — WITHOUT touching the
goldens (byte-untouched) and WITHOUT bending the cmd-parity bar for live models. Every
amendment records old-vs-new in TEST_SPEC.md §7 (append-only), as done for A–F.

## Tasks
- [ ] Freeze new tables in `llama_swap_testlib.py` from the APPROVED replan:
      `REMOVED_IDS` (frozen 13 — plan CR3: coder trio incl. ablit, kat trio + 1m trio,
      qwen3-30b-a3b×2, qwen3-8b×2; the qwen3.6 line SURVIVES under ruling B),
      `CATALOG_IDS` (58 = golden ∪ approved-new minus REMOVED; gpu-side 38 + gpu-ai-local 20),
      `ENABLEMENT[cluster]` (gpu: 34 enabled + 24 echo — enabled = surviving chart ids minus
      the 4 `disabled:` overrides (qwen3-vl-30b-a3b-bf16, qwen3.6-35b-a3b-1m,
      qwen3.6-35b-a3b-bf16, ornith-1.5-35b-a3b-bf16); gpu-ai: ALL 58 enabled, zero echoes),
      keep `GPU_DISABLED_IDS` narrowed to the surviving 3 golden echoes, keep `C04_HF_REFS`.
- [ ] `test_config_parity.py` re-express (per plan P1–P6): P1 rendered-ID set == CATALOG_IDS
      exactly; P2 live-model cmd token-multiset equality for golden ∩ enabled (bar UNCHANGED);
      P3 golden-surviving echo IDs byte-identical echo (narrow
      `gpu_disabled_entries_byte_identical_echo` to survivors); P4 REMOVED_IDS absent from both
      renders; P5 catalog-new IDs off-cluster match the fail-fast SHAPE (id-prefixed echo,
      message not pinned); P6 matrix "additive preservation modulo REMOVED" — every surviving
      golden var maps unchanged, no surviving golden set vanishes, membership preserved minus
      REMOVED tokens; macros/hooks/top-level-scalar assertions untouched.
- [ ] `test_config_schema.py`: family-contract tests (new): ID derivation
      `<family>-<quant>`, `id:` override, family<rung field merge, `enabled` flip at either
      level, `disabled` beats `enabled`, duplicate derived ID fails render, raw
      `config.models.<id>` merge-over-expansion (escape hatch + override layer stays),
      synthetic overlay fixtures re-pointed at `config.families` where they read values-shape
      (render-shape tests stay).
- [ ] `test_new_roster.py`: isolation flip — `gpu_ai_only_families_absent_from_gpu` becomes
      present-as-echo on gpu (shape P5); every `-hf`-ref assertion cross-reads the live cluster
      when the primary render is fail-fast shaped (ratified B/D pattern generalized);
      approved-ID tables unchanged (IDs are unchanged); preload assertion unchanged.
- [ ] `test_autogen_wiring.py`: degrade trio re-expressed to execute the REPO-side
      `containers/llama-swap-autogen/entrypoint.sh` directly with flags
      (`--scan-dir/--base/--out/--home`, stub CLI on PATH, sandboxed paths) — same three
      contracts (empty scan → comment-only + rc0; generate rc≠0 → degrade file + rc0; generate
      rc0 → generated content not clobbered); wiring render assertions flip: initContainer has
      image + `args` matching `autogen.scanPaths`/paths contract and NO `command`; drift-guard
      probes re-based: args-scan-dir set ≠ scanPaths fails render; a `command:` (any, esp.
      `/bin/sh`) fails render (shell tripwire).
- [ ] `test_autogen_image.py`: entrypoint contract flips (Dockerfile: `COPY entrypoint.sh`,
      exec-form `ENTRYPOINT ["/entrypoint.sh"]`, file present + mode +x + `#!/bin/sh`),
      gated docker console-script checks stay valid via `--entrypoint llama-swap-config-autogen`
      (the script must remain on PATH).
- [ ] `tests/evidence/c05_expected_evidence.yaml` rebased onto the new enabled sets (model
      counts, echo-shape greps, entrypoint log strings, `/v1/models` superset note).
- [ ] Prove redness for the right reasons (all new/re-expressed tests fail as
      implementation-missing against HEAD, never as harness errors) and re-run the unaffected
      subsets for zero collateral change; full-suite baseline at handoff =
      greens(unchanged) + reds(CA2/CA3/CA4 scope) + 12 evidence gates.

## Files in scope
- charts/llama-swap/tests/** ONLY (testlib, parity, schema, roster, wiring, image, evidence yaml,
  TEST_SPEC.md §7 amendment entries G… appended). Goldens: byte-untouched (hard rule).

## Acceptance criteria
1. `pytest charts/llama-swap/tests -v` collection error-free; every amended/new test fails
   with an implementation-missing message naming its chunk (CA2/CA3/CA4), sampled per file.
2. Goldens diff-empty vs baseline (`git diff -- charts/llama-swap/tests/golden` empty).
3. No assertion weakening: diff audit shows the live-model cmd bar (P2) retains the existing
   normalization + multiset equality verbatim; the amendment list in TEST_SPEC §7 states, for
   each old assertion, exactly what replaced it (superset semantics, not slack).
4. Unchanged-scope tests (existing CI 33, integration gates, hf_check gated) still green/skip
   as before at HEAD (no implementation landed in CA1).
5. Frozen tables match the user-approved removal list + enablement matrix verbatim (review
   diffs them against DECISIONS).

## Tests (agent-test writes, review runs)
This chunk IS the test work; review re-runs the suite and audits the amendment diffs (no
deleted assertions without a TEST_SPEC §7 entry).

## Notes for dev (test writer)
- Keep `hf_check.py` and gated integration harness untouched except entrypoint-related skips.
- Em-dash edit flakes: known FRICTION — patch via shell python if the edit tool mismatches.
- `/tmp/opencode` may be empty: rebuild helm v3.16.4 + ag-venv per FRICTION before running.

## Review notes (review agent fills)

### Round 1 — 2026-10-24 (fresh-context review; commit 066322e70; verdict: CHANGES_REQUESTED)

CA1 is unusual — the implementer was the test session itself — so this review was the
acceptance-3 audit it was designed to be: superset-honesty of the amendment diff, bar
by bar, plus re-execution of every gate.

**Validation re-run (all bars met exactly):**
- `pytest charts/llama-swap/tests -v` => **25 failed / 122 passed / 12 skipped**, zero
  collection errors; red decomposition matches §7bis handoff bars to the name: parity 5
  (P1×2, P4×2, P5×1 gpu), schema 9 (3 value-shape + 6 fam_*), roster 3, wiring 7, image 1.
- `LLAMA_SWAP_EVIDENCE=1 -k autogen_integration` => **3 passed / 5 skipped** (gates unchanged).
- Existing CI 4 files => **33 passed** (zero collateral). Skips = the same 12 evidence gates.
- `git diff 49e977faf..HEAD -- charts/llama-swap/tests/golden` => **empty** (acceptance 2 ✓).
- Commit scope: 8 files, all under `charts/llama-swap/tests/**`; `git diff d3e39b237..066322e70`
  over charts-values/templates/services/containers/custom-values/.rulesync/.opencode => zero
  drift (acceptance 4 precondition ✓).
- `aislop scan charts/llama-swap/tests` => **0 errors**, 11 warnings (file-size + decorative
  separators, mostly pre-existing classes; testlib crossed the 400-line soft limit at 586).

**Superset-honesty audit (acceptance 3), verified mechanically:**
- (a) P2 bar: `cmd_tokens` + `model_tokens` (testlib 195–235 old vs new) are **byte-identical**;
  the parity tests' comparison bodies unchanged — the only edits are loop-key subtraction of
  `REMOVED_IDS` (safe: presence is exact-set-pinned by P1/P4, so a live divergence cannot hide)
  and a table-audit cross-check. The "retained VERBATIM" claim holds.
- (b) Deleted-assertion sweep: every old assertion removed in the diff maps to a §7bis G–M
  entry (old id-set-equality→P1, byte-echo-6→P3, matrix E→P6, ids_survive→survivors,
  _init_script/_sandbox machinery→K, old ENTRYPOINT regex→L, isolation absent→present-as-echo→J,
  gpuai placement loop tolerance→J). One entry claims a deletion that did not happen → Major-3.
- (c) Narrower-but-equivalent: golden-gpu echo-shaped ids computed = exactly the pre-replan
  DISABLED 6; minus REMOVED (kat trio) = exactly the 3 ruling-B survivors;
  `GPU_DISABLED_IDS_PRE_REPLAN − REMOVED == GPU_DISABLED_IDS` is pinned by the new table-audit
  test. P6 modulo is a pure removal-of-REMOVED-tokens: surviving golden var mappings, sets and
  memberships are still required verbatim. ✓
- (d) Frozen tables vs DECISIONS/CR3 verbatim: REMOVED_IDS = the 13 ruled (set-equality check
  against the DECISIONS text passed); CATALOG_IDS = 58 = (golden-union 55 ∪ C04-new 16) − 13
  (computed equal); partition gpu 34/24 disjoint-and-covers, gpu-ai 58/0; GPU_ECHO_IDS =
  20 gpu-ai-local + the 4 chart-side `disabled:` overrides named in CA1.md. GPU_ENABLED_IDS is
  DERIVED (`CATALOG − ECHO`), so enabled/echo cannot drift silently. ✓
- (e) P5 pins the fail-fast SHAPE (`_ECHO_CMD` regex) + id-prefix, never the message text
  (`"not enabled"` substring in fam_enablement is the documented §7bis-I wording). ✓
- (f) The two §7bis-K drift probes: `test_c04_drift_probe_*` => 2 passed at HEAD, confirmed
  passing via the OLD C03 script-based guard. Their post-CA4 re-check under the args guard
  belongs to the CA4 review — flagged here and in STATE for that reviewer.

**FINDINGS** (severity order; all four majors are latent forward-satisfiability defects —
green-at-CA1 bars unaffected, but each makes a later chunk's "full suite green" gate
unsatisfiable or mis-recorded; same class as ratified A–F, so each routes back to the
test session, not to dev):

1. **major** `test_config_schema.py:120` (`test_c02_chart_composition_hf_refs_match_golden`)
   — post-CA2 **guaranteed KeyError**: `src = "gpu" if mid in goldens["gpu"] else "gpu-ai"`
   then `goldens[src][mid]`. The 16 C04-approved-new ids (flash-next×5, 122B×4, ladder×7) are
   in NEITHER golden (goldens were captured pre-C04), and a compliant CA2 MUST carry them as
   family rungs (the sibling composition test asserts `derived_family_ids == CATALOG_IDS`).
   Proof: simulated over all 57 non-escape/non-removed catalog ids — 16 crash. Any CA2
   implementation fails this test for the wrong reason. Fix: skip rungs absent from both
   goldens (their refs stay pinned by the roster `test_c04_1_exact_hf_ref_per_approved_id`
   parametrization — coverage preserved), and note the skip rationale in §7bis-I.
2. **major** `test_autogen_wiring.py:272,287` — `_comment_only(...)` is called but its `def`
   was dropped in the rebase (grep: 0 definitions; only `import llama_swap_testlib as L`, no
   from-import — bare name ⇒ **NameError post-CA4** in the two degrade contracts, whatever
   entrypoint.sh does). Masked today because `_require_entrypoint` asserts first. §7bis-K
   records removing `_init_script`/`_sandbox` but not this helper (it is a predicate the NEW
   tests use, not removed machinery). Fix: restore the 6-line def (verbatim at
   `d3e39b237:charts/llama-swap/tests/test_autogen_wiring.py`) and note under K.
3. **major** §7bis-I vs code drift: the entry states the per-entry `assert "hf" in m` loop in
   `test_c02_gpuai_block_escape_hatch_is_exactly_rana` was "dropped" (deviation-3 supersession +
   CR1.5 "a post-CA2 partial override may legitimately omit hf") — the loop is still in the
   committed file (`test_config_schema.py:198-202`). A legit post-CA2 override without `hf`
   fails it, and the amendment record misleads the CA2 coder either way. Fix: actually remove
   the loop (the ruled intent — raw-set=={rana}, one-line exec, -hf/-hfd token bars all stay),
   or amend §7bis-I if keeping it was deliberate (then CR1.5 wording needs the same fix).
4. **major** `test_config_schema.py:367` (`test_fam_derivation_and_id_override`) asserts
   `f"{FAM}-off" not in models`, while `test_fam_enablement_and_disabled_beats_enabled`
   (same file, :395-396) asserts the same overlay rung is **present and echo-shaped**
   ("not-enabled rung vanished instead of echoing (P5 contract)") — mutually unsatisfiable
   pair by any compliant CA2 (CR1.4: not-enabled → echo; P1/P5: catalog pattern renders all
   rungs). Fix: make the derivation test assert the echo shape for `off` (or drop the clause —
   the enablement test owns it).
5. **minor** Acceptance-1 wording ("fails with an implementation-missing message naming its
   chunk") is only partly literal: 4 of 9 schema reds (`fam_fields_merge` bare KeyError,
   `fam_models_merge`, `fam_duplicate` DID-NOT-RAISE, `fam_enablement` whose message cites the
   P5 contract, not CA2) lack the literal "CA2" in the pytest repr; the handoff's blanket "all
   red messages name their owning chunk" is overstated. They are unambiguously
   implementation-missing (docstrings name CR1.x) so sampling-per-file passes — while fixing
   majors 3/4, add chunk-named assertion messages to these four.
6. **minor** `test_c04_drift_probe_command_reintroduction_fails_render` docstring says "expected-red
   until CA4 lands" but the probe is GREEN at handoff via the old script guard (§7bis-K's
   recorded observation is the correct state). Misleading for the CA4 coder — reword to match K.
7. **nit** `test_config_schema.py:78` odd `f"{fam and ''}{fam}-{quant}"` (harmless, but the
   shared `derived_family_ids` helper already spells it correctly — reuse it);
   `test_autogen_wiring.py:260` duplicate `import os` (line 20 already imports it) and
   `_render_rc`'s no-op `import json`/`del json`; unused `sb/scanned` mkdir in the usage test;
   testlib now past aislop's 400-line soft ceiling (586 lines, 0 errors — CI gate unaffected).

**Carry-forward for CA4 review** (per 7bis-K + handoff open_questions): re-verify both drift
probes green UNDER the new args-based guard, and that `--base/--out` path pinning +
`--home` export semantics are what the probes exercise post-relocation.

**Deferred:** none out of scope; everything found is inside the tests/** tree CA1 owns.

Verdict mapping: majors 1–4 violate the chunk Goal ("re-express the test contract for the
replanned surface") + acceptance 3 (amendment list must state exactly what replaced each old
assertion, superset semantics) — the contract as committed is superset-honest on the bars
that matter (P2/P3/P6 frozen tables all verified above) but not yet downstream-satisfiable
on four edges. All fixes are small, surgical, tests-only, same-session. Re-run after the
amendment expects the same 25f/122p/12s (plus zero new reds; fam_derivation may go
red→red-with-message only after CA2).

### Round 2 — 2026-10-24 (re-review of delta commit ebceb56c7; verdict: **APPROVED**)

All 7 Round-1 findings verified resolved mechanically; the r1 bars are reproduced exactly
and the red contract is now downstream-satisfiable on every edge audited. No new defects.

**Delta audit (verifications, not trust-the-diff):**
- `git show ebceb56c7 --stat` => 4 files, all under `charts/llama-swap/tests/**`
  (TEST_SPEC, testlib, wiring, schema) — tests-only scope ✓. Removed-line sweep: every
  deletion maps to addendum item 1–7 or is hygiene-equivalent (message-only rewrites,
  pytest.raises→explicit-rc same semantics, unused mkdir) — zero assertions weakened.
- **Major-1**: `test_c02_chart_composition_hf_refs_match_golden` now skips rungs absent
  from BOTH goldens. Simulated post-CA2 over `CATALOG − REMOVED − escape`: skips exactly
  the 16 C04-new ids, all 16 covered green by `test_c04_1_exact_hf_ref_per_approved_id`
  (C04_HF_REFS); echo-rerouted 3 survivors found in the opposite golden; **zero residual
  KeyError paths**.
- **Major-2**: `_comment_only` def (wiring:196) is **byte-identical** to d3e39b237's
  (diff empty); 2 callsites live ahead of `_require_entrypoint` masks → NameError class gone.
- **Major-3**: grep-proved the per-entry `assert "hf" in m` loop is ACTUALLY gone from the
  rana test (only a comment references it); raw-set=={rana}, one-line-exec and
  token-boundary -hf/-hfd bars retained verbatim. Round-1's silent no-op is honestly
  self-reported in the code comment, §7bis-I and the addendum.
- **Major-4**: derivation now asserts `id:`-replaces (`{FAM}-q8 not in`); no assertion
  anywhere demands `{FAM}-off` absent; enablement owns the off-echo — pair satisfiable
  under CR1.1/CR1.4/P5.
- **minor-5/6/7**: all 25 red bodies carry literal CA2/CA3/CA4 (scripted check — the r1
  overstatement is now literally true); tripwire docstring matches §7bis-K's recorded
  observation (green-at-handoff via C03 script guard, behavioral bar for CA4); nits swept
  (`fam and ''` f-string, duplicate `import os`, `import json`/`del json`, unused mkdirs;
  `render_rc` promoted to testlib:143, 3 callers, identical body).
- §7bis I/K + Round-2 addendum re-read against the actual files: doc now states code
  truth (r1's doc-vs-code drift class did not recur); addendum maps findings 1–7 + bars.

**Bars re-run (HEAD = ebceb56c7):**
- `pytest charts/llama-swap/tests -v` => **25 failed / 122 passed / 12 skipped**; FAILED
  name set **diff-empty** vs the Round-1 log — and the log's provenance was independently
  re-established by re-running the archived 066322e70 tree (same 25 names). Zero
  NameError/KeyError/ImportError/AttributeError in any red body; decomposition
  parity 5 / schema 9 / roster 3 / wiring 7 / image 1 unchanged.
- Goldens: `git diff 49e977faf..HEAD -- tests/golden` => **0 lines** (acceptance 2 intact).
- `LLAMA_SWAP_EVIDENCE=1 pytest -k autogen_integration` => **3 passed / 5 skipped**.
- Pre-feature CI files (test_convert_lora, test_llama_tools, test_render,
  test_vendored_provenance) => **33 passed**, zero collateral.
- `aislop scan charts/llama-swap/tests` => **0 errors** / 11 warnings (same classes as
  r1: size-ceiling + separators + pre-existing hf_check URL; testlib 604 lines,
  acknowledged no-action).

**Carry-forward (unchanged, now STATE-flagged for CA4 review):** both drift probes are
green at handoff via the C03-era script guard — CA4 review must re-verify them green
under the args-based guard, incl. `--base/--out` pinning and `--home` export semantics.

Verdict: contract rebased, superset-honest, downstream-satisfiable. CA1 **APPROVED**;
CA3/CA4 (wave 4) may proceed.
