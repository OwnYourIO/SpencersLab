# CB2: template-side derivation machinery + chart catalog conversion (CR5 Option 2, ruled regime)
size: M   wave: 7   depends_on: [CB1] (amended contract first — CA1→CA2 precedent)

## Goal
Implement the CR5 grammar in `_helpers-llama-swap.tpl` and convert `charts/llama-swap/
values.yaml` to derived form: display text composed template-side (uniform grammar,
prose rungs normalizing to it per the user ruling, `size`/`descTail`/`suffix`-style
slots carrying real data), hf refs composed from family `hfRepo` + culture/`tag`
shorthand with per-rung `hf:` literals as the honest exceptions (qwen38/qwen36).
Services values get ZERO edits; rendered output may differ from HEAD ONLY in model
`name`/`description` VALUES, and every such change goes to the user as a before/after
table BEFORE the PR (plan CR5 bars 1–2).

## Tasks
- [ ] `_helpers-llama-swap.tpl` — new defines wired into the CA2 expansion loop in the
      pinned ORDER (compose hf → derive display from the rung-level hf → merge raw
      `config.models` over the top):
  - effective-hf composition: rung `hf` literal > `{repo | fam.hfRepo}:{tag |
    config.tagCultures[fam.tagCulture][quant-key]}`; unresolvable + no cmd + no
    disabled → `fail` naming the rung (loud-offender rule, G1 precedent).
  - display derivation (derive-if-absent — explicit rung `name:`/`description:`
    always beat it): NAME `{disp | fam.dispName} ({TAG}{, MTP iff draft or spec})
    { - suffix}`; DESC `{descBase}, {TAG} quant` / `{descBase}, {TAG} (no quant)` +
    `{descTail}` (family default, rung override) with `{size}` interpolation. Raw-cmd
    / no-hf rungs are never decorated (whisper stays explicit by construction).
  - strip the new schema keys (plan list) from every rendered entry; extend the
    existing unset list; keep the deepCopy discipline (no values bleed between rungs —
    CA2 lesson) and the `tpl`-free dict-math idiom (helm 3.16: no regexFindString,
    dig cannot descend slices).
- [ ] `charts/llama-swap/values.yaml`: add `config.tagCultures:` (standard =
    {q4 Q4_K_M, q5 Q5_K_M, q6 Q6_K, q8 Q8_0, bf16 BF16}; unsloth-ud =
    {q3..q6 UD-Q{n}_K_XL}; exact map contents = the plan's measured fit, as DATA).
    Per family add `dispName`/`descBase` (+`descTail`) and `hfRepo` where single-repo;
    convert rung bodies per the fit tables:
  - collapse to shorthand/bare rungs: 6 VL families (culture standard, aliases stay on
    q4 rungs), qwen3.6-27b, qwen3.6-35b-a3b {q6 (tag exception UD-Q6_K), q8, 1m, bf16},
    qwen3.8-27b {q4,q6,q8 via culture/exception tags, bf16 per-rung repo exception},
    ornith-1.5-35b-a3b {official rungs via culture; iq2xxs/q3 repo+tag exceptions; all
    with `size:`}, ornith-1.5-122b + qwen3.8-flash-next (unsloth-ud; `size:` rungs),
    home-3b-v3 (per-rung tag + `suffix` data), qwen3-embedding (per-rung tag).
  - remove ALL derivable name/description lines (ruled regime — text COMPOSES from
    grammar; survivor strings may now differ from golden — table records it);
    qwen38×5 + qwen36×2 keep full `hf:` literals (multi-repo fan-out) with
    display via `disp`/`suffix`/`descTail` slots where the grammar fits and explicit
    `description:` where prose carries data the grammar cannot (mirror provenance,
    experimental-draft caveats) — dev records each keep-explicit as a table row.
  - NEW-ID NORMALIZATION (ruling 3): flash-next/122b/fn-orca names + descriptions
    recompose to the uniform grammar ("…, MTP" derives from the family `draft`/`spec`
    presence; over-budget warnings ride `descTail`-style rung data; "Orca"/"reference"
    paren-prefixes drop — recorded in the before/after table).
- [ ] `draft:` refs stay full literals everywhere (not ladder fields).
- [ ] Produce the DISPLAY-TEXT BEFORE/AFTER TABLE: every 58 ids × {name, description}
      old vs new, both clusters where they differ; append to this chunk's Dev findings
      and to RESULT for the user's pre-PR review (CR5 bar 2).

## Files in scope
- charts/llama-swap/templates/_helpers-llama-swap.tpl
- charts/llama-swap/values.yaml
- proof-only, no edits: services/gpu/prod/values.yaml, services/gpu-ai/prod/values.yaml
  (enablement flips, tuned regimes, `models.<id>.hf/name/description/disabled`
  overrides MUST keep working unchanged through derivation — if any would not, STOP
  and route back to coord; CA2 rule).

## Acceptance criteria
1. REST-INVARIANCE: excising only model `name`/`description` values from the three
   renders (default / gpu / gpu-ai extract-and-render) before and after the edit, the
   comparison is BYTE-EQUAL (cmd tokens, ttl/proxy/aliases/capabilities/filters/
   checkEndpoint/env, macros/matrix/hooks/scalars, echo strings, ConfigMap structure —
   all untouched). Mechanically: yaml-load both, delete the two keys, deep-equal.
2. `helm dependency update` + `helm lint --strict` + three renders pass; `pytest
   charts/llama-swap/tests -v` fully green per the CB1-rebased contract (147 + CB1's
   new tests, 12 evidence skips); `LLAMA_SWAP_EVIDENCE=1` gates 3p/5s;
   `RUN_HF_CHECK=1 LLAMA_SWAP_EVIDENCE=1` 1p; direct `hf_check.py` all refs OK both
   renders (refs are byte-unchanged — this run proves the composition fidelity live).
3. CB1's extended strip test green; no new schema key in any rendered ConfigMap data.
4. `git diff --name-only HEAD -- services/ custom-values/ containers/ charts/base/
   charts/gpt-researcher/` empty; no version/tag edits; trio/sentinel greps intact;
   goldens untouched.
5. Precedence probes (dev-side, recorded): derived text beats nothing that is
   explicit (rung, then models layer); a models-layer `hf` override does NOT
   re-derive display text; the rana/whisper escape hatches render byte-unchanged;
   rung-level `enabled`/`disabled` semantics unchanged (deviation 1 wording intact);
   `home-3b-v3` id: override still the ONLY `id:`.
6. The before/after display table exists in this chunk + RESULT (user review gate for
   the PR).

## Tests (agent-test writes, review runs)
All CB1-written (relaxed P2-rest, shorthand-aware value-shape tests, presence +
grammar-shape tests, extended strip) + the entire pre-existing suite. Review re-runs
criterion-1's rest-invariance diff independently, the display table vs renders, and
criterion-5 probes (CA2 machinery-probe precedent).

## Notes for dev
- Load `llama-swap` + `helm-bjw-s-chart` + `helm-chart-creation`; read TEST_SPEC
  §7/§7bis/§7ter/§7quater + chunks/CA2.md review notes first.
- Whole-section YAML surgery: take the render snapshot BEFORE editing and re-diff
  after every commit (CA2 duplicate-key-class friction lesson — mechanical proof,
  not eyeballs).
- Keep the rationale comments layer (values comments relocate with entries;
  comment-slop rules apply).
- Any CB2-discovered validation_at_fault routes to ses_e9bdebccbffe7bYG46Fm9LO8FG
  (A–O precedent); dev never edits tests. Any grammar rule that turns out
  unsatisfiable → STOP, route to coord; do not improvise a different schema.

## Dev findings (CB2 dev, 2026-10-24 — commit "feat(llama-swap): template-side name/description + repo:tag derivation (CR5 grammar) (CB2)")

### Grammar spelling chosen (outcome bars per plan "CR5 grammar"; dev owns spelling)
- `llama-swap.deriveHf` (dict model/quant/cultures): rung `hf` literal >
  `{repo | hfRepo}:{tag | config.tagCultures[tagCulture][quant]}`; empty = unresolvable.
- `llama-swap.deriveDisplay` (dict model/ref/id, mutates the merged rung map):
  NAME `{disp | dispName | id} ({TAG}{, MTP iff draft or spec}){ - suffix}`;
  DESC `{descBase | NAME-part}, {TAG} quant` / `{TAG} (no quant)` for BF16/F16,
  then descTail appended VERBATIM — the tail's leading punctuation is DATA, which
  kept 46/58 catalog rows byte-identical to HEAD (e.g. vl-30b ", CPU-offloaded
  experts" vs the 2b "; faster processing..." tails). `{size}` in the tail
  interpolates the rung `size` datum; size without an explicit tail composes
  the default tail "; <size> weights" (the U-2 outcome bar).
- Derive-if-absent is PER FIELD: an explicit `name:`/`description:` at family or
  rung level beats its derived counterpart independently. Derivation reads the
  RUNG-level effective ref and runs BEFORE the raw `config.models` merge, so
  models-layer hf/name/description overrides win without ever re-deriving text
  (probe1). No-hf rungs (whisper) and models-only IDs (synthetic smoke fixtures)
  are never decorated. Echo (not-enabled) rungs still derive: the deviation-1
  static catalog message and P3 legacy echo bytes are untouched.
- Unresolvable enabled rung fails the render in the final assembly loop, naming
  the id AND the family/quant pair (G1 loud-offender precedent); models-layer
  hf/cmd/disabled count as resolutions because the check runs after the merge.
- Strip: `config.tagCultures` unset alongside filterPresets/families/models;
  per-entry unset list extended with dispName/descBase/descTail/size/disp/
  suffix/hfRepo/tagCulture/tag/repo (the U-1 NEW_SCHEMA_KEYS set).

### Conversion ledger (58 rungs)
- culture-composed: 26 standard + 10 unsloth-ud; per-rung repo/tag composed
  exceptions: 10 (q38-27b q8 tag + bf16 repo/tag; q36-35b q6 UD-Q6_K + 1m
  Q8_0; ornith-35b iq2xxs/q3 bartowski repo+tag; home gpu/cpu tags;
  embedding 0.6b tag) => 46 shorthand rungs.
- full hf: literals kept: 11 (qwen38 x5 multi-repo fan-out, qwen36 x2,
  q38-27b q8-visual/q8-1m prose pair, q36-35b q8-visual, fn-orca gated repo)
  — honest exceptions per the plan fit tables; no universal regex invented.
- `draft:` refs stay full literals everywhere (3 sites unchanged).
- 147 literal rung lines collapsed (55 name:, 46 description:, 46 hf:) into the
  shorthand + family vocabulary; every keep-explicit name/description row is
  flagged in the table below; 12 normalized rows per the free-16 +
  prose-rung rulings (Orca/reference paren-prefixes drop; flash-next/122b
  descs recompose to `{TAG} quant; {size} weights...` with the "MTP draft"
  duplication folded into the name marker; embedding descBase rebuilt to carry
  the model identity the old prose duplicated).
- `home-3b-v3` `id:` remains the ONLY id: repo-wide (probe5); whisper/rana
  entries render byte-unchanged (probe4); tuned gpu overrides and gpu-ai
  re-compositions ride the models layer unchanged (11 per-cluster text diffs,
  byte-stable before==after on gpu-ai — generator asserts).

### Verification (all re-run by review; bars exact)
- helm dependency update + lint --strict pass; three renders (extract-and-
  service-values, plan method) OK.
- pytest charts/llama-swap/tests -v => 0 failed / 155 passed / 12 skipped
  (parity 34 + schema 20 + wiring 32 + roster 30 + image 6p/4s + existing CI
  33 = 155p/12s). CB2's two reds (U-2 shorthand composition, U-3 unresolvable
  fail-render) green; S1-S3 stayed green throughout.
- LLAMA_SWAP_EVIDENCE=1 gates 3p/5s; RUN_HF_CHECK=1 LLAMA_SWAP_EVIDENCE=1 =>
  1p; hf_check.py direct => 98 refs OK exit 0 (composition resolved live,
  zero changed refs).
- REST-INVARIANCE (/tmp/opencode/cb2-rest-invariance.py): before/after renders
  with name/description excised are deep-equal on all three clusters, incl.
  every other ConfigMap and every non-ConfigMap document.
- schema-key strip greps: 0 leak lines in all three rendered ConfigMap bodies.
- values diff: only name:/description:/hf: lines removed (mechanical grep);
  duplicate-key-checked YAML load at every mapping level; EOF newline intact.
- git diff HEAD -- services/ custom-values/ containers/ charts/base/
  charts/gpt-researcher/ => empty; tests tree diff => 0 lines; goldens => 0.
- aislop 0.18.1 charts/llama-swap dir scan: 166 pre-existing vendored-scripts
  diagnostics, 0 attributable to the touched files.

### The display table (CR5 bar 2 — human contract replacing the golden display pin; 58 rows)

Total rows: 58 (58 catalog ids x both fields; gpu render is the base row - gpu-ai rows differ only where the services models layer carries explicit text, flagged).
Display-text changes vs HEAD: 12 ids (ornith-1.5-122b-q3, ornith-1.5-122b-q4, ornith-1.5-122b-q5, ornith-1.5-122b-q6, qwen3-embedding-0.6b, qwen3.8-flash-next-orca-q6, qwen3.8-flash-next-q3, qwen3.8-flash-next-q4, qwen3.8-flash-next-q5, qwen3.8-flash-next-q6, qwen38-orca, qwen38-orca-f16). All 58 refs (-hf/-hfd tokens) are byte-identical - see rest-invariance.

| id | state | name before | name after | description before | description after | keep-explicit/keep-literal flag + reason |
|---|---|---|---|---|---|---|
| home-3b-v3 | IDENTICAL | Home 3B v3 (Q4_K_M) - CPU | Home 3B v3 (Q4_K_M) - CPU | Home Assistant 3B v3 model on CPU, Q4_K_M quant; runs in parallel with GPU models | Home Assistant 3B v3 model on CPU, Q4_K_M quant; runs in parallel with GPU models |  |
| home-3b-v3-gpu | IDENTICAL | Home 3B v3 (Q8_0) - GPU | Home 3B v3 (Q8_0) - GPU | Home Assistant 3B v3 model on GPU, Q8_0 quant | Home Assistant 3B v3 model on GPU, Q8_0 quant |  |
| ornith-1.5-122b-q3 | CHANGED | Ornith 1.5 122B (UD-Q3_K_XL) | Ornith 1.5 122B (UD-Q3_K_XL) | Ornith 1.5 122B MoE (qwen35moe, 256 experts/top-8, ~92% routed), UD-Q3_K_XL, 55.7 GiB weights; experts on CPU, 256k ctx; SOLO; no MTP draft published (see the C04 family note) | Ornith 1.5 122B MoE (qwen35moe, 256 experts/top-8, ~92% routed), UD-Q3_K_XL quant; 55.7 GiB weights, experts on CPU, 256k ctx; SOLO; no MTP draft published (see the C04 family note) |  |
| ornith-1.5-122b-q4 | CHANGED | Ornith 1.5 122B (UD-Q4_K_XL) | Ornith 1.5 122B (UD-Q4_K_XL) | Ornith 1.5 122B MoE (qwen35moe, 256 experts/top-8, ~92% routed), UD-Q4_K_XL, 74.2 GiB weights; experts on CPU, 256k ctx; SOLO; no MTP draft published (see the C04 family note) | Ornith 1.5 122B MoE (qwen35moe, 256 experts/top-8, ~92% routed), UD-Q4_K_XL quant; 74.2 GiB weights, experts on CPU, 256k ctx; SOLO; no MTP draft published (see the C04 family note) |  |
| ornith-1.5-122b-q5 | CHANGED | Ornith 1.5 122B (UD-Q5_K_XL) | Ornith 1.5 122B (UD-Q5_K_XL) | Ornith 1.5 122B MoE (qwen35moe, 256 experts/top-8, ~92% routed), UD-Q5_K_XL, 88.1 GiB weights; experts on CPU, 256k ctx; SOLO; no MTP draft published (see the C04 family note) | Ornith 1.5 122B MoE (qwen35moe, 256 experts/top-8, ~92% routed), UD-Q5_K_XL quant; 88.1 GiB weights, experts on CPU, 256k ctx; SOLO; no MTP draft published (see the C04 family note) |  |
| ornith-1.5-122b-q6 | CHANGED | Ornith 1.5 122B (UD-Q6_K_XL) | Ornith 1.5 122B (UD-Q6_K_XL) | Ornith 1.5 122B MoE (qwen35moe, 256 experts/top-8, ~92% routed), UD-Q6_K_XL, 106.4 GiB weights; marginal against the ~125 GiB budget - SOLO only; no MTP draft published (see the C04 family note) | Ornith 1.5 122B MoE (qwen35moe, 256 experts/top-8, ~92% routed), UD-Q6_K_XL quant; 106.4 GiB weights, marginal against the ~125 GiB budget - SOLO only; no MTP draft published (see the C04 family note) |  |
| ornith-1.5-35b-a3b-bf16 | IDENTICAL | Ornith 1.5 35B A3B (BF16) | Ornith 1.5 35B A3B (BF16) | DISABLED on 8GiB gpu (cannot fit) — use the tuned q8/q6 entries or gpu-ai | DISABLED on 8GiB gpu (cannot fit) — use the tuned q8/q6 entries or gpu-ai | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| ornith-1.5-35b-a3b-iq2xxs | IDENTICAL | Ornith 1.5 35B A3B (IQ2_XXS) | Ornith 1.5 35B A3B (IQ2_XXS) | Ornith 1.5 35B with 3B active parameters (MoE), IQ2_XXS quant; 9.6 GiB weights, experts on CPU, 256k ctx | Ornith 1.5 35B with 3B active parameters (MoE), IQ2_XXS quant; 9.6 GiB weights, experts on CPU, 256k ctx |  |
| ornith-1.5-35b-a3b-q3 | IDENTICAL | Ornith 1.5 35B A3B (Q3_K_XL) | Ornith 1.5 35B A3B (Q3_K_XL) | Ornith 1.5 35B with 3B active parameters (MoE), Q3_K_XL quant; 16.6 GiB weights, experts on CPU, 256k ctx | Ornith 1.5 35B with 3B active parameters (MoE), Q3_K_XL quant; 16.6 GiB weights, experts on CPU, 256k ctx |  |
| ornith-1.5-35b-a3b-q4 | IDENTICAL | Ornith 1.5 35B A3B (Q4_K_M) | Ornith 1.5 35B A3B (Q4_K_M) | Ornith 1.5 35B with 3B active parameters (MoE), Q4_K_M quant; 20.2 GiB weights, experts on CPU, 256k ctx | Ornith 1.5 35B with 3B active parameters (MoE), Q4_K_M quant; 20.2 GiB weights, experts on CPU, 256k ctx |  |
| ornith-1.5-35b-a3b-q5 | IDENTICAL | Ornith 1.5 35B A3B (Q5_K_M) | Ornith 1.5 35B A3B (Q5_K_M) | Ornith 1.5 35B with 3B active parameters (MoE), Q5_K_M quant; 23.6 GiB weights, experts on CPU, 256k ctx | Ornith 1.5 35B with 3B active parameters (MoE), Q5_K_M quant; 23.6 GiB weights, experts on CPU, 256k ctx |  |
| ornith-1.5-35b-a3b-q6 | IDENTICAL | Ornith 1.5 35B A3B (Q6_K) | Ornith 1.5 35B A3B (Q6_K) | Ornith 1.5 35B A3B (MoE), Q6_K; 8GiB-gpu fit: experts on CPU, q8_0 KV, no vision, cache_reuse 256, 1 slot (np pinned: pool = np x ctx), 256k ctx (slow) | Ornith 1.5 35B A3B (MoE), Q6_K; 8GiB-gpu fit: experts on CPU, q8_0 KV, no vision, cache_reuse 256, 1 slot (np pinned: pool = np x ctx), 256k ctx (slow) | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| ornith-1.5-35b-a3b-q8 | IDENTICAL | Ornith 1.5 35B A3B (Q8_0) | Ornith 1.5 35B A3B (Q8_0) | Ornith 1.5 35B A3B (MoE), Q8_0; 8GiB-gpu fit: experts on CPU, q8_0 KV, no vision, cache_reuse 256, 1 slot (np pinned: pool = np x ctx), 256k ctx (slow) | Ornith 1.5 35B A3B (MoE), Q8_0; 8GiB-gpu fit: experts on CPU, q8_0 KV, no vision, cache_reuse 256, 1 slot (np pinned: pool = np x ctx), 256k ctx (slow) | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3-embedding-0.6b | CHANGED | Qwen3 Embedding 0.6B (Q8_0) | Qwen3 Embedding 0.6B (Q8_0) | Text embeddings via /v1/embeddings; Qwen3-Embedding 0.6B Q8_0, always-ready sidecar | Qwen3-Embedding 0.6B text embeddings via /v1/embeddings, Q8_0 quant; always-ready sidecar |  |
| qwen3-vl-2b-bf16 | IDENTICAL | Qwen3 VL 2B Instruct (BF16) | Qwen3 VL 2B Instruct (BF16) | Vision-language model for Immich image analysis, BF16 (no quant); faster processing for simpler descriptions | Vision-language model for Immich image analysis, BF16 (no quant); faster processing for simpler descriptions |  |
| qwen3-vl-2b-q4 | IDENTICAL | Qwen3 VL 2B Instruct (Q4_K_M) | Qwen3 VL 2B Instruct (Q4_K_M) | Vision-language model for Immich image analysis, Q4_K_M quant; faster processing for simpler descriptions | Vision-language model for Immich image analysis, Q4_K_M quant; faster processing for simpler descriptions |  |
| qwen3-vl-2b-q8 | IDENTICAL | Qwen3 VL 2B Instruct (Q8_0) | Qwen3 VL 2B Instruct (Q8_0) | Vision-language model for Immich image analysis, Q8_0 quant; faster processing for simpler descriptions | Vision-language model for Immich image analysis, Q8_0 quant; faster processing for simpler descriptions |  |
| qwen3-vl-30b-a3b-bf16 | IDENTICAL | Qwen3 VL 30B A3B Instruct (BF16) | Qwen3 VL 30B A3B Instruct (BF16) | DISABLED on 8GiB gpu (cannot fit) — use the q4/q8 variants | DISABLED on 8GiB gpu (cannot fit) — use the q4/q8 variants | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3-vl-30b-a3b-q4 | IDENTICAL | Qwen3 VL 30B A3B Instruct (Q4_K_M) | Qwen3 VL 30B A3B Instruct (Q4_K_M) | Vision-language MoE model for Immich image analysis, Q4_K_M quant, CPU-offloaded experts | Vision-language MoE model for Immich image analysis, Q4_K_M quant, CPU-offloaded experts |  |
| qwen3-vl-30b-a3b-q8 | IDENTICAL | Qwen3 VL 30B A3B Instruct (Q8_0) | Qwen3 VL 30B A3B Instruct (Q8_0) | Vision-language MoE model for Immich image analysis, Q8_0 quant, CPU-offloaded experts | Vision-language MoE model for Immich image analysis, Q8_0 quant, CPU-offloaded experts |  |
| qwen3-vl-30b-a3b-thinking-bf16 | IDENTICAL | Qwen3 VL 30B A3B Thinking (BF16) | Qwen3 VL 30B A3B Thinking (BF16) | Reasoning vision-language MoE model for Immich image analysis, BF16 (no quant), CPU-offloaded experts; higher accuracy for complex images | Reasoning vision-language MoE model for Immich image analysis, BF16 (no quant), CPU-offloaded experts; higher accuracy for complex images |  |
| qwen3-vl-30b-a3b-thinking-q4 | IDENTICAL | Qwen3 VL 30B A3B Thinking (Q4_K_M) | Qwen3 VL 30B A3B Thinking (Q4_K_M) | Reasoning vision-language MoE model for Immich image analysis, Q4_K_M quant, CPU-offloaded experts; higher accuracy for complex images | Reasoning vision-language MoE model for Immich image analysis, Q4_K_M quant, CPU-offloaded experts; higher accuracy for complex images |  |
| qwen3-vl-30b-a3b-thinking-q8 | IDENTICAL | Qwen3 VL 30B A3B Thinking (Q8_0) | Qwen3 VL 30B A3B Thinking (Q8_0) | Reasoning vision-language MoE model for Immich image analysis, Q8_0 quant, CPU-offloaded experts; higher accuracy for complex images | Reasoning vision-language MoE model for Immich image analysis, Q8_0 quant, CPU-offloaded experts; higher accuracy for complex images |  |
| qwen3-vl-4b-bf16 | IDENTICAL | Qwen3 VL 4B Instruct (BF16) | Qwen3 VL 4B Instruct (BF16) | Vision-language model for Immich image analysis, BF16 (no quant) | Vision-language model for Immich image analysis, BF16 (no quant) |  |
| qwen3-vl-4b-q4 | IDENTICAL | Qwen3 VL 4B Instruct (Q4_K_M) | Qwen3 VL 4B Instruct (Q4_K_M) | Vision-language model for Immich image analysis, Q4_K_M quant | Vision-language model for Immich image analysis, Q4_K_M quant |  |
| qwen3-vl-4b-q8 | IDENTICAL | Qwen3 VL 4B Instruct (Q8_0) | Qwen3 VL 4B Instruct (Q8_0) | Vision-language model for Immich image analysis, Q8_0 quant | Vision-language model for Immich image analysis, Q8_0 quant |  |
| qwen3-vl-4b-thinking-bf16 | IDENTICAL | Qwen3 VL 4B Thinking (BF16) | Qwen3 VL 4B Thinking (BF16) | Reasoning vision-language model for Immich image analysis, BF16 (no quant); good balance of speed and accuracy | Reasoning vision-language model for Immich image analysis, BF16 (no quant); good balance of speed and accuracy |  |
| qwen3-vl-4b-thinking-q4 | IDENTICAL | Qwen3 VL 4B Thinking (Q4_K_M) | Qwen3 VL 4B Thinking (Q4_K_M) | Reasoning vision-language model for Immich image analysis, Q4_K_M quant; good balance of speed and accuracy | Reasoning vision-language model for Immich image analysis, Q4_K_M quant; good balance of speed and accuracy |  |
| qwen3-vl-4b-thinking-q8 | IDENTICAL | Qwen3 VL 4B Thinking (Q8_0) | Qwen3 VL 4B Thinking (Q8_0) | Reasoning vision-language model for Immich image analysis, Q8_0 quant; good balance of speed and accuracy | Reasoning vision-language model for Immich image analysis, Q8_0 quant; good balance of speed and accuracy |  |
| qwen3-vl-8b-bf16 | IDENTICAL | Qwen3 VL 8B Instruct (BF16) | Qwen3 VL 8B Instruct (BF16) | Vision-language model for Immich image analysis, BF16 (no quant) | Vision-language model for Immich image analysis, BF16 (no quant) |  |
| qwen3-vl-8b-q4 | IDENTICAL | Qwen3 VL 8B Instruct (Q4_K_M) | Qwen3 VL 8B Instruct (Q4_K_M) | Vision-language model for Immich image analysis, Q4_K_M quant | Vision-language model for Immich image analysis, Q4_K_M quant |  |
| qwen3-vl-8b-q8 | IDENTICAL | Qwen3 VL 8B Instruct (Q8_0) | Qwen3 VL 8B Instruct (Q8_0) | Vision-language model for Immich image analysis, Q8_0 quant | Vision-language model for Immich image analysis, Q8_0 quant |  |
| qwen3.6-27b-q6 | IDENTICAL | Qwen 3.6 27B (Q6_K) | Qwen 3.6 27B (Q6_K) | Qwen 3.6 27B general purpose model, Q6_K quant | Qwen 3.6 27B general purpose model, Q6_K quant |  |
| qwen3.6-27b-q8 | IDENTICAL | Qwen 3.6 27B (Q8_0) | Qwen 3.6 27B (Q8_0) | Qwen 3.6 27B general purpose model, Q8_0 quant | Qwen 3.6 27B general purpose model, Q8_0 quant |  |
| qwen3.6-35b-a3b-1m | IDENTICAL | Qwen 3.6 35B A3B (Q8_0) - 1M | Qwen 3.6 35B A3B (Q8_0) - 1M | DISABLED on 8GiB gpu (1M KV off-card) — available on gpu-ai | DISABLED on 8GiB gpu (1M KV off-card) — available on gpu-ai | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3.6-35b-a3b-bf16 | IDENTICAL | Qwen 3.6 35B A3B (BF16) | Qwen 3.6 35B A3B (BF16) | DISABLED on 8GiB gpu (cannot fit) — use the tuned q8 entry or gpu-ai | DISABLED on 8GiB gpu (cannot fit) — use the tuned q8 entry or gpu-ai | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3.6-35b-a3b-q6 | IDENTICAL | Qwen 3.6 35B A3B (UD-Q6_K) | Qwen 3.6 35B A3B (UD-Q6_K) | Qwen 3.6 35B with 3B active parameters (MoE), UD-Q6_K quant | Qwen 3.6 35B with 3B active parameters (MoE), UD-Q6_K quant |  |
| qwen3.6-35b-a3b-q8 | IDENTICAL | Qwen 3.6 35B A3B (Q8_0) | Qwen 3.6 35B A3B (Q8_0) | Qwen 3.6 35B A3B (MoE), Q8_0; 8GiB-gpu fit: experts on CPU, q8_0 KV, no vision, cache_reuse 256, 1 slot (np pinned: pool = np x ctx), 256k ctx (slow) | Qwen 3.6 35B A3B (MoE), Q8_0; 8GiB-gpu fit: experts on CPU, q8_0 KV, no vision, cache_reuse 256, 1 slot (np pinned: pool = np x ctx), 256k ctx (slow) | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3.6-35b-a3b-q8-visual | IDENTICAL | Qwen 3.6 35B A3B (Q8_0) - Visual | Qwen 3.6 35B A3B (Q8_0) - Visual | Qwen 3.6 35B A3B (MoE), Q8_0; vision on (auto mmproj), experts on CPU, 256k ctx; cache_reuse disabled by llama.cpp in multimodal mode | Qwen 3.6 35B A3B (MoE), Q8_0; vision on (auto mmproj), experts on CPU, 256k ctx; cache_reuse disabled by llama.cpp in multimodal mode | keep-literal hf+display: visual prose rung: keeps hf literal + explicit description |
| qwen3.8-27b-bf16 | IDENTICAL | Qwen 3.8 27B (BF16) | Qwen 3.8 27B (BF16) | Qwen 3.8 27B dense model, BF16 (no quant) | Qwen 3.8 27B dense model, BF16 (no quant) | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3.8-27b-q4 | IDENTICAL | Qwen 3.8 27B (UD-Q4_K_XL) | Qwen 3.8 27B (UD-Q4_K_XL) | Qwen 3.8 27B dense model, UD-Q4_K_XL quant | Qwen 3.8 27B dense model, UD-Q4_K_XL quant | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3.8-27b-q6 | IDENTICAL | Qwen 3.8 27B (UD-Q6_K_XL) | Qwen 3.8 27B (UD-Q6_K_XL) | Qwen 3.8 27B dense model, UD-Q6_K_XL quant | Qwen 3.8 27B dense model, UD-Q6_K_XL quant | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3.8-27b-q8 | IDENTICAL | Qwen 3.8 27B (Q8_0) | Qwen 3.8 27B (Q8_0) | Qwen 3.8 27B dense model, Q8_0 quant | Qwen 3.8 27B dense model, Q8_0 quant | gpu-ai text differs (services models-layer name/description override - data outside derivation reach, byte-stable across clusters both before and after) |
| qwen3.8-27b-q8-1m | IDENTICAL | Qwen 3.8 27B (Q8_0) - 1M | Qwen 3.8 27B (Q8_0) - 1M | Plain Qwen 3.8 27B, Q8_0; 1M ctx (YaRN x4), KV in system RAM | Plain Qwen 3.8 27B, Q8_0; 1M ctx (YaRN x4), KV in system RAM | keep-literal hf+display: vision/1m prose pair: keeps hf literal + explicit description (YaRN/KV-in-RAM data) |
| qwen3.8-27b-q8-visual | IDENTICAL | Qwen 3.8 27B (Q8_0, MTP) - Visual | Qwen 3.8 27B (Q8_0, MTP) - Visual | Plain Qwen 3.8 27B, Q8_0; MTP draft, vision on (auto mmproj), 256k ctx; cache_reuse disabled by llama.cpp in multimodal mode | Plain Qwen 3.8 27B, Q8_0; MTP draft, vision on (auto mmproj), 256k ctx; cache_reuse disabled by llama.cpp in multimodal mode | keep-literal hf+display: vision/1m prose pair: keeps hf literal + explicit description (cache_reuse/mmproj caveats) |
| qwen3.8-flash-next-orca-q6 | CHANGED | Qwen 3.8 Flash Next Uncensored (Orca Q6_K, MTP) | Qwen 3.8 Flash Next Uncensored (Q6_K, MTP) | orcarouter uncensored Flash Next (gated, HF_TOKEN), 156.1 GiB weights; experts on CPU; over the ~125 GiB node budget like flash-next q6 - SOLO, never preloaded, may OOM; embedded-MTP per the qwen38-orca pattern | orcarouter uncensored Flash Next (gated, HF_TOKEN), 156.1 GiB weights; experts on CPU; over the ~125 GiB node budget like flash-next q6 - SOLO, never preloaded, may OOM; embedded-MTP per the qwen38-orca pattern | keep-literal hf+display: gated orcarouter repo keeps full hf literal; desc stays explicit (HF_TOKEN/embedded-MTP caveats); name derives (Orca prefix drops) |
| qwen3.8-flash-next-q3 | CHANGED | Qwen 3.8 Flash Next (UD-Q3_K_XL, MTP) | Qwen 3.8 Flash Next (UD-Q3_K_XL, MTP) | Qwen 3.8 Flash Next 180B-class MoE (512 experts/top-10), UD-Q3_K_XL, 83.8 GiB weights; experts on CPU; MTP draft, 256k ctx; SOLO - largest resident this node has attempted (RESEARCH §4A regime test) | Qwen 3.8 Flash Next 180B-class MoE (512 experts/top-10), UD-Q3_K_XL quant; 83.8 GiB weights, experts on CPU, 256k ctx; SOLO - largest resident this node has attempted (RESEARCH §4A regime test) |  |
| qwen3.8-flash-next-q4 | CHANGED | Qwen 3.8 Flash Next (UD-Q4_K_XL, MTP) | Qwen 3.8 Flash Next (UD-Q4_K_XL, MTP) | Qwen 3.8 Flash Next 180B-class MoE (512 experts/top-10), UD-Q4_K_XL, 103.7 GiB weights; experts on CPU; MTP draft, 256k ctx; tight against the ~125 GiB node budget - SOLO only | Qwen 3.8 Flash Next 180B-class MoE (512 experts/top-10), UD-Q4_K_XL quant; 103.7 GiB weights, experts on CPU, 256k ctx; tight against the ~125 GiB node budget - SOLO only |  |
| qwen3.8-flash-next-q5 | CHANGED | Qwen 3.8 Flash Next (UD-Q5_K_XL, MTP) | Qwen 3.8 Flash Next (UD-Q5_K_XL, MTP) | Qwen 3.8 Flash Next 180B-class MoE (512 experts/top-10), UD-Q5_K_XL, 147.4 GiB weights; OVER the ~125 GiB node budget - enabled by accepted operator decision 2026-10-22, may OOM on load; run-alone (no matrix), never preloaded | Qwen 3.8 Flash Next 180B-class MoE (512 experts/top-10), UD-Q5_K_XL quant; 147.4 GiB weights, experts on CPU; OVER the ~125 GiB node budget - enabled by accepted operator decision 2026-10-22, may OOM on load; run-alone (no matrix), never preloaded |  |
| qwen3.8-flash-next-q6 | CHANGED | Qwen 3.8 Flash Next (UD-Q6_K_XL, MTP) | Qwen 3.8 Flash Next (UD-Q6_K_XL, MTP) | Qwen 3.8 Flash Next 180B-class MoE (512 experts/top-10), UD-Q6_K_XL, 157.5 GiB weights; OVER the ~125 GiB node budget - enabled by accepted operator decision 2026-10-22, may OOM on load; run-alone (no matrix), never preloaded | Qwen 3.8 Flash Next 180B-class MoE (512 experts/top-10), UD-Q6_K_XL quant; 157.5 GiB weights, experts on CPU; OVER the ~125 GiB node budget - enabled by accepted operator decision 2026-10-22, may OOM on load; run-alone (no matrix), never preloaded |  |
| qwen36-heretic | IDENTICAL | Qwen3.6 35B A3B heretic (Q4_K_M, MTP) | Qwen3.6 35B A3B heretic (Q4_K_M, MTP) | llmfan46 heretic abliteration, native MTP preserved; mradermacher mirror; experts-on-CPU; 256k ctx | llmfan46 heretic abliteration, native MTP preserved; mradermacher mirror; experts-on-CPU; 256k ctx | keep-literal hf+display: multi-repo family (2 repos): full hf literal stays; name derives via disp slot |
| qwen36-huihui | IDENTICAL | Qwen3.6 35B A3B huihui abliterated (Q4_K, MTP) | Qwen3.6 35B A3B huihui abliterated (Q4_K, MTP) | huihui-ai classic abliteration, dedicated MTP GGUF; experts-on-CPU; 256k ctx | huihui-ai classic abliteration, dedicated MTP GGUF; experts-on-CPU; 256k ctx | keep-literal hf+display: multi-repo family: full hf literal stays; name derives via disp slot |
| qwen38-ara | IDENTICAL | Qwen3.8 27B heretic-ara (Q6_K-MTP) | Qwen3.8 27B heretic-ara (Q6_K-MTP) | Max-quality/coding build; draft-MTP n-max 3, 256k ctx | Max-quality/coding build; draft-MTP n-max 3, 256k ctx | keep-literal hf+display: multi-repo family + TAG itself embeds MTP (Q6_K-MTP): grammar would compose "(Q6_K-MTP, MTP)"; name AND desc stay explicit |
| qwen38-humanlike | IDENTICAL | Qwen3.8 27B Humanlike-Chat 2.0 (Q6_K) | Qwen3.8 27B Humanlike-Chat 2.0 (Q6_K) | Text-only humanlike chat; low reasoning effort, 128k ctx | Text-only humanlike chat; low reasoning effort, 128k ctx | keep-literal hf+display: multi-repo family: full hf literal stays; name derives via disp slot |
| qwen38-orca | CHANGED | Qwen3.8 27B Uncensored (Orca Q6_K, MTP) | Qwen3.8 27B Uncensored (Q6_K, MTP) | Qwen3.8 27B daily driver; draft-MTP speculative decoding, 256k ctx | Qwen3.8 27B daily driver; draft-MTP speculative decoding, 256k ctx | keep-literal hf+display: multi-repo family (4 repos): full hf literals stay honest |
| qwen38-orca-f16 | CHANGED | Qwen3.8 27B Uncensored (Orca F16 reference, MTP) | Qwen3.8 27B Uncensored (F16, MTP) | Reference F16 build; ttl 180 so it evicts fast | Reference F16 build; ttl 180 so it evicts fast | keep-literal hf+display: multi-repo family: full hf literal stays; name derives (Orca/reference prefixes drop) |
| qwen38-rana | IDENTICAL | Qwen3.8 27B RANA abliterated (Q6_K, MTP) | Qwen3.8 27B RANA abliterated (Q6_K, MTP) | mradermacher mirror; borrowed ggml-org official MTP draft (experimental), 256k ctx | mradermacher mirror; borrowed ggml-org official MTP draft (experimental), 256k ctx | keep-literal hf+display: raw-cmd escape-hatch rung: hf/name/description all stay explicit (gpu-ai byte-pins its entry via models layer) |
| whisper-large-v3 | IDENTICAL | Whisper Large v3 | Whisper Large v3 | Audio transcription (whisper.cpp ggml-large-v3) for podcast processing | Audio transcription (whisper.cpp ggml-large-v3) for podcast processing | keep-literal hf+display: raw-cmd escape: no hf at all, never decorated - name/description explicit by construction |

## Review notes (review agent fills)

### Round 1 — 2026-10-24 (fresh-context review; commit 5299f82b1; verdict: **APPROVED**)

**1. Bars re-run (all exact):**
- `helm dependency update` + `helm lint --strict` => pass (INFO icon only; no tracked-file churn from dep update).
- Three plan-method renders (default / gpu extract-and-render / gpu-ai extract-and-render) => rc 0, clean stderr.
- `pytest charts/llama-swap/tests -v` => **0 failed / 155 passed / 12 skipped** — corrected CB1 finding-1 bar, exact. Per-file recount reconciled to dev's decomposition: parity 34P, schema 20P, wiring 32P, roster 30P, image 6P/4S, integration 0P/8S; CI subset 33P (convert_lora 3 + llama_tools 20 + render 7 + provenance 3); 34+20+32+30+6+33 = 155, skips 4+8 = 12. U-2/U-3 green; targeted run `-k "cr5 or display or ladder_descriptions or fam_key"` => **9 passed** (S1/S2/S3 ×2 clusters + U-1 + U-2 + U-3 — the CB1 carry-forward "never acceptable as CB2-reds" set is green, verified directly not just by suite total).
- `LLAMA_SWAP_EVIDENCE=1` gates => **3 passed / 5 skipped** unchanged; `RUN_HF_CHECK=1 LLAMA_SWAP_EVIDENCE=1` => **1 passed**.
- **Live-HF bar (load-bearing post-conversion):** my own direct `python3 hf_check.py` => "checking 98 -hf/-hfd refs across both cluster renders / OK", exit 0. Reads the LIVE renders (refs_from_renders → testlib), i.e. composition resolved 98/98 refs with zero changed.

**2. Independent rest-invariance** (fresh script `/tmp/opencode/cb2-rev/cb2-rest-invariance-review.py`, git-archive `724d27e3b` tree re-rendered, NOT the dev's script): all 3 clusters => **0 rest-diffs**. Every non-`llama-swap-config` document (incl. autogen-base CM + tools CM + Deployment/Service/PVC/ExternalSecret) deep-equal as whole docs; inside config.yaml: model ID sets identical (58), every entry's keys except top-level `name`/`description` deep-equal (nested metadata compared — no nested exemption; `_strip`-equivalent is exact top-level two-key), `cmd` additionally shlex-parsed: 0 token-list diffs (1 gpu cmd is shlex-opaque from an apostrophe in an echo message — unparseable-but-byte-equal on both sides; lens limitation, flagged in-script, not an artifact). Changed name/desc ids: **exactly 12, identical set on all three renders** = the table's CHANGED set; whisper/rana and all other 46 ids byte-unchanged → nothing exempt outside the ratified derive-if-absent regime.

**3. Display-table audit** (fresh script `/tmp/opencode/cb2-rev/cb2-table-audit.py`) — automated **full 58-row** check against the REAL renders, superseding the required 8-row spot audit:
- 58 rows, table id-set == render id-set, zero duplicates; every `name/description` before-cell == the 724d27e3b render and every after-cell == the HEAD render, byte-exact (58×2×2).
- State column ≡ mechanically-derived changed set (12 CHANGED = 12 actual).
- Both-cluster coverage: the 11 "gpu-ai text differs" rows verified byte-stable on gpu-ai (before==after, service models-layer text) AND actually differing from the gpu base row (flag truthful); every unflagged row verified gpu-ai-after == gpu-after with no undocumented cluster divergence (pre-CB2 cross-cluster check: 0 warnings).
- Keep-explicit audit: 12 flagged rows all carry flag+reason, claims reconciled against values: 11 full-`hf:` literals kept (qwen38×5, qwen36×2, q38-27b {q8-1m,q8-visual}, q36-35b-q8-visual, fn-orca) + whisper (no-hf by construction), 3 explicit `name:` kept (ara, rana, whisper), 12 explicit `description:` kept — arithmetic ties to HEAD (58−55 removed names, 58−46 removed descs, 57−46 removed hf). "name derives" rows verified rung has NO `name:`; qwen38-ara reason honest (grammar would compose "(Q6_K-MTP, MTP)" — confirmed spec/draft present and literal TAG embeds MTP).
- Required spot classes individually confirmed in-render: ara & q36-q8-visual (golden keep-explicit survivors), flash-next-q5 & 122b-q6 (normalized; q6 rung `descTail` override with budget prose), embedding rebuild, home-3b-v3 id-override row (`id:` remains the ONLY one — grep values:401), whisper & rana raw rows untouched, qwen3.6-35b-a3b-q8 tuned-override row proving models-layer wins (rendered desc = gpu services "8GiB-gpu fit…" text, not the derived "…with 3B active parameters… quant").
- Header claim "all 58 refs byte-identical" — proven by (2).

**4. Machinery fresh-eyes** — synthetic probes rendered (not mirrored in python):
- Precedence `deriveHf`: pA — rung `hf:` literal beats a co-present `tag:` (cmd `-hf lit/eral:WEIRD_TAG`), family `hfRepo`+culture composes q5→`fam/repo:Q5_K_M`, rung `repo:`+`tag:` exception composes q9. Loud offender: pB (enabled rung, uncomposable quant key) => **render rc=1**, message names BOTH the model id and the family-rung pair (`model cr5-probe-b-q7 (family rung cr5-probe-b-q7) resolves no -hf ref…`) — G1 class honored; disabled/cmd escape paths proven via pD-family-E.
- Models-merge-LAST: pC — models-layer `hf: models/layer:NEW_TAG` rewrites `-hf` in cmd while name/description stay composed from the RUNG-level ORIGTAG → no re-derivation (CA3 precedence ruling holds end-to-end, exactly the CB1 carry-forward probe class).
- Grammar vs plan pinning: pD — MTP leg iff draft or spec (drafty ✓ specky ✓ plain none ✓), F16→"(no quant)" ✓, `{size}` interpolated globally in the VERBATIM tail (both placeholders replaced; leading punctuation preserved byte-exact — the 46/58 mechanism), size-without-tail default "; 7 GiB weights" ✓ (U-2 bar), suffix " - Special" ✓, descBase→disp fallback ✓. Echo rungs derive (E-q4 carries derived text + deviation-1 static echo bytes intact; render echo-count: default 58/58 echo, gpu 34 live/24 echo, gpu-ai 58 live — CR1.3/CA2 enablement semantics untouched; rung enabled:false beats family true, models-layer disabled beats enablement — both re-probed).
- Strip: plan-literal grep over all three rendered config bodies (dispName|descBase|descTail|hfRepo|tagCulture|tagCultures|tags|tag|repo|size) => **0 hits ×3**; `tagCultures` top-level unset proven (rest-invariance would show it as an ADDED key; it did not); no unreplaced `{size}` in any rendered description.
- Duplicate-key load check: custom SafeLoader dup-constructor over the full values tree (all mapping levels) => clean. `tpl` count in helpers => 0; new defines are pure dict-math, output reaches config only via `toYaml` (no new injection surface).
- No surface drift: `git diff 724d27e3b..HEAD` = exactly the 2 in-scope files; all other chart templates + base.yaml CM render + goldens + whole tests tree => 0 diff. modelCmd/autogenBase/firstMountPath byte-untouched (CR1.3 + CA4 machinery intact).

**5. Honesty checks:**
- `git diff --name-only HEAD -- services/ custom-values/ containers/ charts/base/ charts/gpt-researcher/` => **empty** (re-verified at worktree AND commit level).
- Values-diff removals re-classified mechanically: **147 removed lines = 55 `name:` + 46 `description:` + 46 `hf:` — zero removals in any other class** (matches the dev ledger digit-for-digit; additions are the shorthand/vocab/culture/comment shape, proven behavior-neutral by rest-invariance).
- Deviation (5) stray-tool-call: `git show --name-only 5299f82b1` => only the 2 scope files; uncommitted worktree deltas are coord-owned `.agents/plans/` docs only. Nothing was actually touched outside scope.
- aislop 0.18.1 `scan charts/llama-swap --json` => **166 diagnostics, all in `scripts/`** (vendored converter/gguf-py; 2 errors in vendored `vocab.py` — pre-existing, provenance-pinned files, not CB2 scope); **0 attributable to the touched files**; before-tree scan identical profile.
- Trio/sentinel: chart + proxy entries intact (services files untouched since CA2). The one `OVERRIDE_VIA_CUSTOM_VALUES` line inside the gpu-ai *render* (ExternalSecret `remoteRef.key`) is pre-existing deployment-resolution behavior — byte-identical line in the before-render, 0-diff on `secret-hf-token.yaml`; not CB2-attributable, recorded for the ledger only.

**FINDINGS** (no blocker/major):
1. **nit** `_helpers-llama-swap.tpl` deriveDisplay: the `{size}` placeholder in a descTail is only interpolated when the rung (or family) carries `size` — a future `{size}` tail on a size-less rung renders the literal placeholder in picker text. Zero occurrences today (mechanically asserted over values: every `{size}` tail site carries a size); hardening candidate for the test session's values-shape guard on next touch, not a CB2 defect.
2. **nit** MTP leg is `hasKey`-based while modelCmd's legs are truthiness-based — a null-valued `draft:`/`spec:` would compose ", MTP" with no spec/draft flags. Scanned all family/rung/models sites: no null/false draft|spec anywhere. Same test-session-guard class as nit-1; spellings otherwise match the plan pinning exactly.
3. **observation** dev's NAME spelling adds `| default .id` beyond the plan's pinned `{disp | fam.dispName}` — inside "dev owns spelling"; never exercised by the real catalog (all families carry dispName or rung disp — verified via renders), and it strengthens S1 presence. No action.

**Verdict: APPROVED.** All six acceptance criteria met with independent evidence: bars exact (155/12, gates, 98/98 live HF), rest-invariance re-proven on real renders with my own comparator (12-id × 3-field changed set exactly = the table), full 58-row table == real renders byte-for-byte incl. both-cluster coverage and keep-explicit flag truth, machinery probed synthetically at the fail-render/precedence/grammar edges, honesty ledger clean (removals class-exact, scope empty, aislop 0-attributable). The table is user-accurate for the PR gate.
