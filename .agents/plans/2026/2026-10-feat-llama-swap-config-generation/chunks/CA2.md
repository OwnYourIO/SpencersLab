# CA2: family-keyed schema + quant-ladder expansion + full-catalog default-disabled conversion
size: L   wave: 5   depends_on: [CA1 (contract + frozen tables), CA3 (removals land first so the conversion edits the reduced surface — same values files), CA4 (same _helpers file + same values.yaml autogen/app-template sections — file-conflict dependency, no semantic coupling)]

## Goal
Author the roster as families (`config.families.<family>.quants.<rung>`, rendered ID
`<family>-<quant>`, `id:` override) with the chart values.yaml carrying the COMPLETE catalog
(every family incl. flash-next/orca/122B/35B ladder/qwen38 derivatives/visual+1m rungs) in
which EVERY rung is default-disabled, and gpu / gpu-ai service values flip `enabled: true`
on their subset. Preserve: golden cmd token-parity for live models, byte-exact legacy echo
messages, `disabled > cmd > hf-composition` precedence, deviation-1 wording, per-quant
overrides (gpu's tuned regime, per-quant capabilities, per-quant matrix membership).

## Tasks
- [ ] `_helpers-llama-swap.tpl`: new `llama-swap.expandFamilies` (or inline in
      `declaredConfig`): for each family×rung build the model entry (family fields merged
      down, rung fields override; rendered ID = `rung.id | family + "-" + quant`; duplicate
      ID → `fail`). Not-enabled rung → echo path (set synthesized `disabled` with the
      catalog default message "is not enabled on this cluster - see the chart catalog";
      a cluster `disabled:` override wins — this keeps the gpu golden echoes byte-exact).
      Enabled rung → existing `modelCmd` unchanged. Merge the raw `config.models` map OVER
      the expansion (deep, per-ID) so per-cluster tuned overrides keep today's exact shape.
      Strip `families` from the rendered config (chart-values concept, like filterPresets).
- [ ] Convert `charts/llama-swap/values.yaml`: replace `config.models` with `config.families`
      = FULL catalog (all families × rungs, every family `enabled: false` default, full per-rung
      data as today: hf/draft/spec/use/flags/name/description/ttl/aliases/capabilities/filters/
      checkEndpoint). gpu-ai-local families (qwen38 derivatives, flash-next, fn-orca `q6`,
      122B, qwen36 heretic/huihui, embedding `0.6b`, visual/`q8-1m` rungs, `home-3b-v3-gpu`
      rung) move chart-side. `home-3b-v3` is the ONE rung needing `id:` override (derivation
      rule in plan CR1.1); whisper = raw-cmd rung passthrough stays.
- [ ] `services/gpu/prod/values.yaml`: add `config.families.<f>.enabled: true` (and
      `quants.<q>.enabled: true` where only some rungs enable) for the frozen gpu set —
      34 enabled (CA1 `ENABLEMENT[gpu]`; plan CR3 counts, ruling B); KEEP the surviving
      legacy echo entries as `models.<id>.disabled:` + `description:` byte-pinned overrides
      (golden P3 survivors: qwen3-vl-30b-a3b-bf16, qwen3.6-35b-a3b-1m, qwen3.6-35b-a3b-bf16)
      plus the C04 ornith-1.5-35b-a3b-bf16 message; KEEP the surviving tuned regimes
      (qwen3.6-35b-a3b-q8 — the golden-pinned one — and ornith q6/q8 use/flags) in the
      models/raw-override layer.
- [ ] `services/gpu-ai/prod/values.yaml`: enable ALL 58 surviving rungs (zero echoes there —
      today's gpu-ai block disables nothing); keep tuned variants + hooks.preload + matrix +
      macros exactly (ids unchanged).
- [ ] matrix: chart `matrix.vars`/`main` extended with one var per surviving catalog rung
      (echo IDs still exist in every render, so closure holds; catalog-rungs-not-in-any-set get
      run-alone semantics on that cluster); gpu-ai keeps its own `main`/`solo` replacements
      (dict-merge: its vars merge over chart vars, its sets replace). Per-quant membership
      therefore remains per-cluster values (flash-next q5/q6 stay var-less/set-less everywhere
      — user ruling preserved). CA1's E-modulo + roster placement tests pin exact memberships.
- [ ] No CA1-owned test may be edited; iterate renders until the CA1-rebased suite passes
      (parity P1–P6, schema family tests, roster isolation-flip, plus everything previously
      green: existing CI 33, wiring, image).

## Files in scope
- charts/llama-swap/values.yaml
- charts/llama-swap/templates/_helpers-llama-swap.tpl
- charts/llama-swap/templates/configmap-llama-swap.yaml (only if the helper signature moves)
- services/gpu/prod/values.yaml, services/gpu-ai/prod/values.yaml (llama-swap blocks)

## Acceptance criteria
1. `helm dependency update` + `helm lint --strict` + the three plan renders pass.
2. Parity (CA1-rebased suite): P2 live golden IDs cmd-token-equal; P3 surviving golden echoes
   byte-identical; P5 new catalog IDs render fail-fast echoes on the cluster that doesn't
   enable them; P1 rendered-ID set == CATALOG_IDS both clusters.
3. Schema family tests green: derivation, override (`id:`), merge layering family<rung<models,
   enabled flip, disabled>enabled, duplicate-ID fail.
4. Isolation flip green: gpu render CONTAINS flash-next/122B/orca/qwen38 IDs as echoes (zero
   `-hf` tokens for echo cmds there); gpu-ai render has the real `-hf` cmds.
5. Matrix closure + preload + hooks byte-equal semantics to golden modulo REMOVED;
   `disabled > cmd > composition` precedence test green.
6. No OVERRIDE_* sentinel in rendered ConfigMap data; trio greps intact; no version/tag edits.
7. Full `pytest charts/llama-swap/tests -v` => 0 failed (12 evidence gates may skip).

## Tests (agent-test writes, review runs)
All CA1-written (superset parity P1–P6, schema family tests, roster isolation flip). Review
re-runs the full suite + independent render greps (echo counts per cluster vs ENABLEMENT
table; spot byte-compare the surviving golden echoes).

## Notes for dev
- Load `llama-swap` + `helm-bjw-s-chart` + `helm-chart-creation` skills.
- Helm deep-merge subtlety: lists REPLACE across value layers — per-rung `use`/`flags`
  overrides are full replacements by design (same as C02's ratified behavior).
- Keep values comments (the rationale layer) — relocate them with their entries.
- `qwen3.6-35b-a3b-q8-visual`, `qwen3.8-27b-q8-visual/-q8-1m`: rung keys derive IDs exactly;
  no `id:` overrides needed. Only `home-3b-v3` (base rung) uses `id:`.
- If any CR1 rule turns out unsatisfiable under v262/Helm semantics, STOP and route back to
  coord (do not improvise a different schema).

## Review notes (review agent fills)

### Round 1 — 2026-10-24 (fresh-context review; diffs bda8c992a + 0602a2f49 + 117848712; verdict: **APPROVED**)

The flagship replan chunk. Bars first, then the before/after snapshot the dev's
surgery demanded, then fresh-eyes on the machinery, deviation adjudication, and
the contract-fix audit.

**1. Bars re-run (all exact — FIRST FULL-GREEN independently reproduced):**
- `helm dependency update` + `helm lint` + `helm lint --strict` => pass (standing icon INFO).
- `helm template` x3 extract-and-render => default 71796 / gpu 74939 / gpu-ai 81162 B, rc0.
- `pytest charts/llama-swap/tests -v` => **0 failed / 147 passed / 12 skipped**; per-module
  recount parity 28 + schema 18 + wiring 32 + roster 30 + image 6P/4S + CI 33 = 147;
  skips = the established 8 integration + 4 image evidence gates, zero new, zero FAILED
  lines in the log.
- Existing CI files standalone => **33/33**. `LLAMA_SWAP_EVIDENCE=1` autogen_integration =>
  **3p/5s**. `RUN_HF_CHECK=1 LLAMA_SWAP_EVIDENCE=1 -k hf_repo_tags_resolve` => **1p**;
  direct `hf_check.py` => **98 refs across both HEAD renders, OK, rc0** (chart-side
  family refs now live-verified — count 117->98 follows the 13-ID removal, not a
  coverage drop).
- Goldens `git diff 49e977faf..HEAD -- tests/golden` => **0 lines**.
- Drift probes x2 re-run directly against helm at HEAD: scanPaths-superset => fail-render
  "…disagree - edit both or neither"; initContainer `command:` reintroduced => fail-render
  tripwire message. **§7bis-K/§7ter carry-forward CLOSED at review too**: the only
  surviving `command:` in chart values (:1045) is `containers.tools`
  (["sleep","infinity"]) — the tripwire dig-scopes `controllers.llama-swap.
  initContainers.autogen` only, exactly as §7ter claims.

**2. Before/after render snapshot (my own git-archive renders, duplicate-key class):**
- **gpu-ai**: HEAD vs **601073581** (CA4 tip = CA2 parent) => **BYTE-IDENTICAL** full
  render. HEAD vs e671e1c26 (CA3 tip) => the ONLY delta is CA4's init command->args
  relocation (out of CA2's hands). The "full-structural-identical" claim re-derived, true.
- **gpu** vs e671e1c26: additions = **exactly the 20** frozen GPU_ECHO_IDS (gpu-ai-local
  move-ins), each a pure fail-fast echo, id-prefixed, catalog-default message; matrix
  vars **+18/-0** (fnq3/fnq4/o122q*/q38*/… — no fnq5/fnq6, q5/q6 var-less ruling
  preserved); sets, macros, hooks, all non-models/non-matrix top-levels **equal**;
  all **38 pre-existing entries dict-identical** (stronger than token-multiset).
  Full-render doc diff touches only the llama-swap-config ConfigMap.
- **default render**: 58 models, 58 echoes (every catalog ID, every one fail-fast) ✓.
- gpu echoes recount 24 = 20 move-ins + 4 legacy byte-pinned (3 P3 survivors + C04
  ornith-bf16); gpu live = 34; gpu-ai echo = 0 — ENABLEMENT 34/24 and 58/0 hold mechanically.

**3. Schema machinery, fresh eyes (`_helpers-llama-swap.tpl`):**
- Merge precedence proven live, not read-only: probe family ttl 111 < rung ttl 222 <
  models-layer flags overlay (`probefam-r1/r2` rendered exactly that).
- Duplicate derived ID => fail-render with message naming **"CA2 family expansion"**
  (probed: two families deriving the same id via `id:` override — fires).
- `disabled:` beats enablement probed: models-layer `disabled` on an enabled-family rung
  => echo carrying the override's own message (deviation-1 composition, byte-path
  `echo '<id> <message>'` — ratified wording; chunk-sketch wording nowhere).
- Rung-level `enabled: false` beats family-level `true` (probed: pfam-r2 echoes) —
  matches the CA1-pinned contract (`test_fam_enablement…` docstring names CR1.3 for
  exactly this; see minor-1 on the plan prose).
- `id:` used **exactly once** repo-wide (values.yaml:376, home-3b-v3 cpu rung) —
  matches CR1.1's ratified exception; no service uses `id:`.
- Schema-key stripping: own grep over all three rendered ConfigMaps — zero
  `hf/draft/spec/use/flags/enabled/id/families` leakage; zero unresolved `${q38-*}`
  on gpu (echo path composes no macros — comment claim mechanically true; only
  MODEL_ID/PORT built-ins present).
- **No Go-template injection surface**: `tpl` grep = 0 hits in all templates; expansion
  is dict-math + `mergeOverwrite` + `toYaml` (C02 idiom). `deepCopy` at every mutation
  point (family fields, rung, raw, model entry) — no values-tree bleed between rungs.
- `llama-swap.modelCmd` full define block (35 lines) **byte-identical 1bc243e53 -> HEAD**;
  `firstMountPath`+`autogenBase` sections byte-identical 601073581 -> HEAD — CA4/CA1
  machinery untouched.
- Chart catalog: 18 families x 58 rungs; derived-id sweep == rendered ids == frozen
  `CATALOG_IDS` exactly; every family `enabled: false`; all-false default verified in code.
- Alias integrity under the catalog pattern (my own probe, v262 global-uniqueness):
  5 aliases, no dup aliases, no alias==other-model-ID collision in any render.

**4. Deviation adjudication (dev 1-6): ALL ACCEPTED.**
1. **rana inert hf/draft/spec/use/flags** — ACCEPT. Not decoration: CHART_RAW_CMD_IDS is
   frozen {whisper-large-v3} and the post-G1 offender rule demands schema fields per
   composition rung; the fields are *asserted* against golden by G2's routed loop, and
   precedence cmd>composition keeps them inert at render. Documented at the site
   (values.yaml:615-620 why-comment).
2. **home base/cpu layout + `id:` override** — ACCEPT: CR1.1's own ratified exception
   ("home-3b-v3 is the ONE rung needing id:"); rung keys are ladder keys not
   quantizations (CR1.2), cpu/gpu naming legitimate; renders match pre-CA2 ids exactly.
3. **18 matrix vars moved chart-side; gpu-ai sets-replacement only** — ACCEPT (and the
   delivered shape is what the chunk's own matrix task prescribed). Note: the chunk line
   "one var per **surviving catalog rung**" read literally would add ~40 set-unreferenced
   vars — matrix sprawl contradicting CR1.6's per-cluster matrix; vars exist to be
   referenced by set expressions, and the executed move (exactly the 18 gpu-ai's sets
   name) is the only contract-consistent reading. Closure re-probed on the DEFAULT render
   too: 0 dangling vars, 0 unknown set tokens.
4. **2-commit split** — ACCEPT; clean chart/services separation, tests untouched by both.
5. **gpu-ai EOF restored** — verified (\n at 4/4 touched files).
6. **no version/tag edits** — verified (diff grep rc=1; Chart.yaml outside scope diff).

**5. Contract-fix audit (117848712, G1/G2):**
- G1 restores intended execution, does NOT weaken: same offenders rule, loop keys
  corrected (spec dict read, fam key kept for derivation); I re-executed the corrected
  rule independently over the chart values — 58 rungs swept, **zero offenders** (was a
  guaranteed AttributeError for any families impl — verified TEST-FAULTY class myself).
- G2 fallback-only routing: `cmd_flag_value` token search stays the PRIMARY path for all
  token-shaped goldens (their behavior is byte-unchanged); the token-boundary regex fires
  ONLY when no `-hf` token exists; the loud `assert want_hf` stands when NEITHER
  mechanism finds a ref — coverage strictly grows (rana's chart refs now checked vs
  golden, previously unsatisfiable). Rightmost-match semantics consistent with
  llama.cpp/cmd_flag_value. §7ter N/O old-vs-new match code read: no assertion removed.
- Method correction honored: both amended loops execute against the final-shape fixture
  (chart values + live renders) — green-at-HEAD is the proof.

**6. Consumer sweep re-run + new removed-rung check:**
- Exact-13-ID sweep over all three HEAD renders + repo-wide (outside tests frozen
  records): **0 residual** — CA2's conversion re-introduced nothing.
- NEW: every service models-layer key, matrix var value and preload entry checked ∈
  CATALOG: 0 offenders both clusters; 0 unknown family names; 0 removed-FAMILY string
  hits in gpu values; the 2 `coder-next` substring hits (chart values:582, gpu-ai:127)
  are the historical plan-slug provenance citation class CA3 reviewed and left — not
  exact IDs, not model references. No tuned override targets a removed/re-introduced
  rung (would have dup/missing-ID'd anyway).

**7. Scope & aislop:**
- `git diff --name-only 601073581..HEAD` = the 4 declared impl files + TEST_SPEC +
  test_config_schema.py (routed fix round ONLY; `git diff ebceb56c7 0602a2f49 -- tests`
  empty — dev touched no contract). `configmap-llama-swap.yaml` untouched (helper
  signature stayed). custom-values/, containers/, charts/base: untouched; OVERRIDE_VIA
  placeholder counts unchanged (gpu 7 / gpu-ai 1); rendered output sentinel-clean.
- aislop 0.18.1 dir scans: charts (166 pre-existing vendored-scripts diagnostics, **0
  attributable** to touched files), services/gpu 0, services/gpu-ai 0.

**FINDINGS** — nothing blocking:
1. **minor (contract-prose observation, no code/test change)**: plan CR1.3 "effective-enabled
   = rung.enabled **OR** family.enabled" contradicts the CA1-pinned merge semantics (an
   explicit rung `enabled: false` BEATS family `true` — proven live and asserted by the
   enablement test's own docstring citing CR1.3). Implementation + contract agree; the
   plan sentence is the outlier. Coord may mirror a one-line clarification in DECISIONS
   so C05/future readers don't re-derive it.
2. **nit (carried class)**: `_helpers` echo composes `disabled:` into a single-quoted
   shell string unescaped (final-review nit-1, already in the post-wave hardening
   bundle). CA2's catalog default is apostrophe-free, but future cluster `disabled:`
   strings are a new entry point to that class — the bundle item now has added reason.
3. **nit (sweep hygiene)**: chart values:582 newly reproduces the `…coder-next`
   plan-slug substring in a comment (moved with its entry, sanctioned by the
   "relocate comments with their entries" rule). Fine to leave — exact-ID sweeps
   unaffected.

Verdict: **APPROVED** — all 7 acceptance criteria met, each covered by a validation I
re-executed; the first fully-green 0f/147p/12s of the ticket reproduced independently;
gpu-ai provably untouched by the conversion (byte-identical), gpu provably additive-only.
