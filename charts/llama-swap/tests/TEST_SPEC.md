# TEST_SPEC — llama-swap config-generation (agent-test session, 2026-10-22)

Feature: `.agents/plans/2026/2026-10-feat-llama-swap-config-generation/`
Scope: tests for ALL chunks C01–C05, written before any dev edit. **These
tests are the immutable contract for `agent-dev` / `agent-review`; a test
judged faulty routes back to this session's owner (coord→user), it is never
edited by the coder.**

## 1. Golden capture (C02 timing constraint — pinned CURRENT chart)

Captured 2026-10-22 from branch tip `b2aa2e4b2` (clean tree, no feature edits)
with helm **v3.16.4**, app-template **5.0.1**, per the plan Commands
extract-and-render pattern (`skills/helm-chart-creation/references/mcp-servers.md`):

```sh
python3 -c "import yaml; d=yaml.safe_load(open('services/gpu/prod/values.yaml'))['llama-swap']; yaml.safe_dump(d, open('/tmp/gpu-vals.yaml','w'))"
helm template llama-swap charts/llama-swap -f /tmp/gpu-vals.yaml \
  --set domain=spencerslab.com --set clusterName=gpu \
  --show-only templates/configmap-llama-swap.yaml \
  | <extract .data["config.yaml"] verbatim> > tests/golden/gpu.config.yaml
# same for services/gpu-ai/prod/values.yaml + clusterName=gpu-ai -> gpu-ai.config.yaml
```

The commands ran verbatim except the data-extraction step (the chunk specifies
"config.yaml data extracted", so the golden is the ConfigMap DATA string
itself, not the manifest). Sizes: gpu 24278 B / 40 models; gpu-ai 33152 B / 55
models. **Re-verified byte-identical to a fresh render 2026-10-22 post-capture
(this session)**; helm's `toYaml` emits no comments, which is why parity is
normalized-token equality (cmd shlex multisets, rightmost-wins flag pairing),
never byte equality — plan "Risks / assumptions".

## 2. Files written

| file | chunks | kind |
|---|---|---|
| `charts/llama-swap/tests/llama_swap_testlib.py` | all | helper (renders, goldens, normalization, matrix DSL, approved ID tables) |
| `charts/llama-swap/tests/golden/gpu.config.yaml`, `gpu-ai.config.yaml` | C02 | immutable parity fixtures |
| `charts/llama-swap/tests/test_config_parity.py` (12 tests/23 cases) | C02 | acceptance 1–5 |
| `charts/llama-swap/tests/test_config_schema.py` (12 tests) | C02 | roster schema + composition contract |
| `charts/llama-swap/tests/test_autogen_wiring.py` (13 tests/26 cases) | C03 | acceptance 1,2(render),3,4(pure),5 + reload |
| `charts/llama-swap/tests/fixtures/scanned_synthetic.yaml` | C03 | scanned-half stand-in (shape source-verified from the pinned generator) |
| `charts/llama-swap/tests/test_autogen_integration.py` (8 tests/cases gated) | C03/C04 | real-tool + fleet-image evidence |
| `charts/llama-swap/tests/test_new_roster.py` (13 tests/30 cases) | C04 | acceptance 1–3,6 (render-level) |
| `charts/llama-swap/tests/hf_check.py` | C04 | manual HF re-verification script (+ gated test wrapper) |
| `charts/llama-swap/tests/test_autogen_image.py` (5 hard + 4 gated) | C01 | Dockerfile/renovate contract + build evidence |
| `charts/llama-swap/tests/evidence/c05_expected_evidence.yaml` | C05 | pre-written expected-evidence grep list (see §5 deviations) |

No source file was touched (`git status` shows only `charts/llama-swap/tests/**`).

## 3. Red/green status at write time (full suite, helm on PATH, gates off)

`pytest charts/llama-swap/tests -v` => **61 failed, 68 passed, 12 skipped**
(existing suite untouched and fully green: 33 passed).

### RED now — all 61 fail with implementation-missing messages (none is a
harness/fixture error; spot-checked)

| file | n | first-error text pattern |
|---|---|---|
| test_config_schema.py | 9 | `config.filterPresets missing — schema not implemented`; `raw cmd outside the escape hatch`; `hf=... but golden -hf=...`; `rendered schema-smoke-* has no cmd — ... C02 schema composition renderer is missing` |
| test_autogen_wiring.py | 21 | `initContainer autogen not found — C03 wiring ... not implemented`; `ConfigMap llama-swap-autogen-base not rendered`; `LLAMA_SWAP_CONFIG_DIR missing`; degrade tests fail at the same initContainer lookup |
| test_new_roster.py | 26 | `roster diverges — missing [approved IDs]`; `KeyError: 'qwen3.8-flash-next-*'`; `not rendered in any cluster`; solo/main membership misses |
| test_autogen_image.py | 5 | `containers/llama-swap-autogen/Dockerfile missing — the C01 autogen image is not implemented` (the renovate-regex test fails at the same read) |

### GREEN now — deliberate preservation/invariant contracts (must stay green)

* all 23 `test_config_parity.py` cases (golden vs current render = the
  pre-change identity; they turn red only if C02–C04 disturb the surface —
  that IS their purpose),
* schema: `macros_matrix_hooks_stay_top_level`, `synthetic_raw_cmd_passthrough_verbatim`
  (escape hatch must keep passing through), `schema_smoke_absent_from_parity_renders` (fixture hygiene),
* wiring: `declared_model_ids_are_colon_free` ×2 + `synthetic_scanned_half_disjoint`
  (merge-namespace invariant holds today), `reloader_annotation` ×2,
* roster: `matrix_closure` ×2 (standing invariant, DECISIONS),
  `no_new_model_preloaded` (preload == pinned already),
  `gpu_ai_only_families_absent_from_gpu` (absence already true).

### SKIPPED (12) — evidence gates, by design never hard in CI (see §4)

## 4. Gating matrix & CI reality

CI (`llama-swap-tools-tests.yaml`, ubuntu-24.04): has helm + python3.12 +
network; runs `helm dependency update` then `pytest charts/llama-swap/tests`;
does **not** build/run docker or install the autogen tool (its 20-min budget
includes torch installs + 4 umbrella renders; pulling the multi-GB fleet
image would be a flaky-by-construction validation). Therefore:

* **Hard in CI**: everything helm-render-based (parity, schema incl. synthetic
  composition, wiring incl. degrade-script execution, roster), the C01
  Dockerfile/renovate parses, and the existing suite. Same gate as
  `test_render.py` (helm binary + app-template tgz, else skip).
* **[CR6 RE-BASELINE, CC1 2026-10-24]** evidence-gate inventory 12 -> 1: the
  sole surviving gate is `RUN_HF_CHECK` (see §7quinquies). `LLAMA_SWAP_EVIDENCE`
  and `LLAMA_SWAP_IMAGE_EVIDENCE` retire entirely with the autogen test scope;
  the bullets below are kept as the historical record.
* **Evidence-gated** (skip with printed reason so review knows RAN vs
  DEFERRED, per chunks/C03.md "Tests"):
  * `LLAMA_SWAP_EVIDENCE=1` — builds the pinned-autogen venv (plan Commands
    verbatim) and runs `generate`/`validate`; docker-dependent cases then
    additionally require a daemon (skips with "docker daemon not reachable").
  * `LLAMA_SWAP_IMAGE_EVIDENCE=1` — `docker build containers/llama-swap-autogen`
    + console-script + uid-65532 checks. The PR's `docker-build.yaml` job
    remains the CI build proof (chunks/C01.md).
  * `RUN_HF_CHECK=1` — `hf_check.py` against the HF API (needs HF_TOKEN for
    the gated orcarouter repo).
* **Local proof this session** (helm v3.16.4 + autogen venv on python3.14):
  gated run with `LLAMA_SWAP_EVIDENCE=1` => 3 FAILED (right reason:
  `ConfigMap llama-swap-autogen-base not rendered`) + 5 skipped (docker/HF
  gates) — i.e. the gate mechanics and the venv fixture both work; the stock
  "No models found" exit-1, the generated-half shape, and `validate` on it
  were verified by hand against the pinned tarball (see §5 item 1 for why
  `validate` was re-expressed).
* To reproduce locally: install helm, `helm dependency update charts/llama-swap`,
  `python3 -m pytest charts/llama-swap/tests -v`.

## 5. Documented adaptations of chunk/plan wording (contract preserved,
implementation made checkable — flag any disagreement to coord NOW, since
these tests are immutable downstream)

1. **C03 acceptance 2 "rendered base.yaml passes `llama-swap-config-autogen
   validate`" is not literally implementable**: source + empirical runs prove
   the pinned tool's `validate` accepts llama-swap-config-shaped YAML
   (`models:` must be an object) and REJECTS a base.yaml (`models:` is a path
   list; `Schema violation ... is not of type 'object'`). Re-expressed as:
   base.yaml is schema-correct iff the pinned `generate` parses it and fails
   ONLY with the scan-empty error, never a parse error
   (`test_c03_2_3_base_yaml_parses_and_empty_scan_fails_stock`), plus the
   *generated* half passes `validate`
   (`test_c03_4_scanned_half_generates_validates_and_is_disjoint`), plus the
   fleet image's `-validate` covers the merged pair (gated). Also verified
   empirically: `validate` against the CURRENT declared config fails (tool's
   bundled schema predates v262 `logToStdout: "proxy,http"`, `performance`,
   and doesn't expand macros for the `${PORT}` proxy rule) — a test asserting
   that would be red regardless of any implementation; deliberately excluded.
2. **Parity "Model ID sets equal EXACTLY"** became *golden ⊆ fresh, additions
   ⊆ approved C04 table* + exact-sets assertion in C04
   (`roster_is_exactly_golden_plus_approved_table`) — at C02 acceptance time
   the two are identical (no additions exist), and the single immutable suite
   stays valid across waves instead of demanding a test edit at C04.
3. **C02 criterion 3's "16 gpu-ai-local IDs"**: the merged pre-change render
   holds 55 = chart 40 + **15** net-local keys (5 of the block's 20 keys
   override chart IDs). Golden capture is ground truth; the inventory test
   pins 40/55 and names the 15.
4. **C05's "agent-test pre-writes the expected-evidence grep list into this
   chunk"** conflicts with the test role's hard rule (no writes under
   `.agents/plans/`): the list lives at
   `charts/llama-swap/tests/evidence/c05_expected_evidence.yaml`; coord
   should reference it from the chunk at next STATE touch.
5. **C04 conditionals are deliberately NOT asserted** (either outcome is
   compliant, so a hard assert would mis-red one branch): orca-q6 MTP pattern
   (embedded vs `-hfd MTP-draft` vs none), 122B MTP (prithivMLmods filename
   regex), `-ot` regex FIT itself (flash-next accepts `${moe}` OR `${fn-moe}`
   OR an emitted `-ot` token). Those findings belong in chunks/C04.md notes.
6. **Synthetic schema smoke fixtures** (`schema-smoke-*`) are overlay-only
   (`-f` injection in tests) — never present in the parity/golden renders
   (guarded by its own test) so they cannot pollute acceptance comparisons.
7. Degrade-script execution tests run the RENDERED initContainer command in a
   sandbox with pinned-path rewriting (`/app/gen`, `/app/autogen`, `/models`)
   and a stub CLI; this pins the fail-open BEHAVIOR (exit 0 + comment-only
   file) for both dev's quick-find branch and its generate-failure branch —
   either implementation passes, a crashlooping one fails.
8. `use`-macro composition may render as `${macro}` references (golden
   byte-stream shape) or pre-expanded, as long as the resolved token stream
   matches; enforced via `render_macro_or_literal` (macro reference OR all
   expanded tokens present).

## 6. Trace: acceptance criteria -> tests

* C02-1 -> parity `helm_lint_passes` + `cluster_render_produces_configmap`
* C02-2 -> parity `model_id_sets_equal`, `cmd_flag_multisets_parity`,
  `per_model_fields_deep_equal`, `config_layer_macros_matrix_hooks_scalars`
* C02-3 -> parity `golden_baselines_match_plan_inventory`, `ids_survive`,
  `consumer_aliases_survive`, `vl_workload_setparams_by_id_keys`,
  `matrix_referential_closure` (+ absence of colon IDs in wiring)
* C02-4 -> parity `gpu_disabled_entries_byte_identical_echo` (6 entries,
  golden strings; extended by roster `35b_bf16_gpu_disabled_failfast` for the
  new one)
* C02-5 -> parity `no_override_sentinel_in_rendered_config`
* C02 schema tasks -> all of test_config_schema.py
* C03-1 -> [CR6 RETIRED — autogen machinery removed by user ruling, §7quinquies] wiring `initcontainer_autogen_pinned_image/security/mounts`,
  `volumes_gen_emptydir_base_configmap`, `main_env_gains_only_config_dir`
* C03-2 -> [CR6 RETIRED — base.yaml ConfigMap gone] wiring base.yaml 4 tests (render half) + integration
  `base_yaml_parses` (tool half; deviation §5.1)
* C03-3 -> [CR6 RETIRED — no scanned half to generate] integration `base_yaml_parses_and_empty_scan_fails_stock` (stock
  behavior, gated) + wiring `degrade_*` ×3 (script contract, hard)
* C03-4 -> [CR6 RETIRED — two-file merge invariant inert; P1's exact colon-free CATALOG subsumes] wiring `declared_model_ids_are_colon_free`,
  `synthetic_scanned_half_disjoint_from_declared` (pure) + integration
  `scanned_half_generates_validates_and_is_disjoint`,
  `merged_declared_plus_scanned_validates` (gated)
* C03-5 -> [CR6 RETIRED — single-file config, no merge surface] wiring base.yaml forbidden/scalar keys + integration
  `declared_only_with_empty_config_dir_validates` (gated)
* C03 reload task -> RE-HOMED (CC1): schema `test_cr6_reloader_guard_declared_scope` ×2 — the reload mechanism is what CR6 KEEPS (single-CM scope; BASE_CM leg deleted) — was wiring `reloader_annotation_covers_both_configmaps`
* C04-1 -> roster `roster_is_exactly_golden_plus_approved_table`,
  `exact_hf_ref_per_approved_id` ×16, `flashnext_mtp_draft_wired`,
  `gpu_ai_only_families_absent_from_gpu`, `flashnext_matrix_placement`,
  `orca_and_122b_solo`, `35b_ladder_matrix_membership`,
  `no_new_model_preloaded`, `big_family_ttl_300_and_ladder_ttl_0`,
  `vision_capabilities_declared`, `35b_q6_q8_gpu_tuned_regime`,
  `35b_bf16_gpu_disabled_failfast` (+ `hf_repo_tags_resolve` — CR6-RETAINED, re-homed to `test_hf_liveness.py`, RUN_HF_CHECK-only gate)
* C04-2 -> parity tests (old IDs unchanged) + roster exact-set test
* C04-3 -> roster `matrix_closure_after_additions` ×2 (+ parity same-named)
* C04-4 -> [CR6 RETIRED BY USER RULING 2026-10-24 — pod boot on-cluster IS the fleet -validate proof; operator-side -validate demoted to a C05 runbook step] integration `full_roster_declared_validates` ×2 (gated)
* C04-6 -> parity + `helm_lint` (existing green suite is the CI gate)
* C01-1..4 -> [CR6 RETIRED — containers/llama-swap-autogen deleted with the machinery; C01 history stands as the landed record] image `dockerfile_exists`, `fleet_consistent_base_pin`,
  `renovate_gitrefs_pin_matches_repo_custom_manager` (runs the repo's own
  renovate.json regex against the Dockerfile), `immutable_install_from_pinned_commit`,
  `nonroot_uid_and_entrypoint` (hard) + `console_script_on_path*`,
  `runs_as_uid_65532` (gated; PR docker-build job = CI build proof)
* C05 -> `tests/evidence/c05_expected_evidence.yaml` (manual, post-merge;
  no automatable pre-merge test per its chunk text)

## 7. Amendments (test-writer session, user-ratified, 2026-10-23)

Coord routed C02 dev's two `validation_at_fault` claims back to the sole test
author. Both verified against the goldens + the landed implementation
(commit `1bc243e53`) before amending: each was unsatisfiable by any
golden-preserving implementation, i.e. test-faulty, not dev-error.

* **(A) `test_c02_gpuai_block_escape_hatch_is_exactly_rana`** — old
  `count("-hf") == 1` counted the substring, and the golden rana exec line
  (byte-pinned by the green parity multiset test) legitimately contains
  `-hf` twice: standalone plus inside `-hfd`. Amended to whitespace-delimited
  token counting: exactly one `-hf` primary AND exactly one `-hfd` draft —
  the original intent (one primary download + one borrowed-MTP draft, one-physical-line
  exec invariant) is unchanged and now actually expressed.
* **(B) `test_c02_chart_composition_hf_refs_match_golden`** — old loop read
  every chart model's `-hf` from the golden **GPU** render, but the six
  `GPU_DISABLED_IDS` entries' golden GPU cmd is the fail-fast echo (no `-hf`
  token by design). Amended to source those six from the golden **GPU-AI**
  render (where the chart default survives untouched) — full conversion-fidelity
  coverage preserved, no exclusions.
* **Ratified as C02 contract resolution (dev deviation 1):** the `disabled:`
  schema value carries the FULL message that follows the model id, and the
  template composes `/bin/sh -c "echo '<id> <message>' >&2; exit 1"` —
  golden-BYTE-exact beats the chunk sketch (`<id> disabled on this box:
  <reason>.`), which conflicted with acceptance 4's byte-identical echo
  requirement. Verified wording-compatible with C04's
  `test_c04_1_35b_bf16_gpu_disabled_failfast` (asserts fail-fast SHAPE + id +
  "disabled" + "8GiB"/"8 GiB" in the echo body — never the sketch template)
  and with `test_c02_synthetic_precedence_disabled_wins` (both now green).
  Coord/plan: mirror this into DECISIONS.md (test role writes no plan-folder
  files).

Re-run after amending: `test_config_schema.py` 12/12, `test_config_parity.py`
23/23, full suite **47 failed / 82 passed / 12 skipped** — the 47 reds are
exactly 21 C03-wiring + 26 C04-roster (implementation-missing), the 12 skips
are the evidence gates of §4, and all C01 hard parses + the untouched existing
suite are green.

* **(C) `_init_script` off-by-one (amended 2026-10-23, coord-routed after C03
  dev).** The `-c` extraction `argv[len(argv) - 1 - argv[::-1].index("-c")]`
  evaluated to the `"-c"` token itself, so all three degrade-script contracts
  compared `"-c"` against sandbox content (`assert '<tmp>/sb' in '-c'`) and
  were unsatisfiable by any implementation. Fixed to the one-token index
  `argv[len(argv) - argv[::-1].index("-c")]`; assertions and sandbox mechanics
  are untouched, and both extractor branches (argv with `-c`, argv without →
  newline-join) still keep the §7.7 "either implementation passes" promise.
  Verified dev-is-innocent before amending: the rendered initContainer argv is
  `["/bin/sh", "-c", "<script>"]`, the corrected extraction yields the real
  fail-open script, and the contracts now PASS against it — degrade behavior
  (exit 0 + comment-only file on empty scan / on generate failure; generated
  content preserved on success) is genuinely implemented, not papered over.
  Post-fix bars: wiring **26/26**, full suite **26 failed / 103 passed /
  12 skipped** (reds = C04 roster only), `LLAMA_SWAP_EVIDENCE=1` integration
  subset **3 passed / 5 skipped** (docker/HF gates deferred per user waiver —
  merged `-validate` evidence is C05-cluster-side, DECISIONS to mirror).

* **(D) `test_c04_1_exact_hf_ref_per_approved_id[ornith-1.5-35b-a3b-bf16]`
  (amended 2026-10-23, coord-routed with E/F after C04 dev).** The loop read
  the `-hf` ref from the entry's primary cluster render, but the plan itself
  makes that gpu entry a `disabled:` fail-fast echo — mutually unsatisfiable
  with `test_c04_1_35b_bf16_gpu_disabled_failfast` (green), same class as
  ratified B. Fixed by cross-reading the ref from the live cluster when the
  primary render is fail-fast shaped; presence/shape stay pinned by the
  dedicated test. A probe over all 16 approved IDs (§7quinquies carry-fix: '17' was a miscount — C04_HF_REFS holds 16) confirmed exactly one
  fail-fast-shaped primary render (gpu/bf16) — no other ID's routing changed.
* **(E) `test_c02_2_config_layer_macros_matrix_hooks_scalars`** — whole-
  matrix equality vs golden contradicted C04 by design (its tasks add vars and
  main/solo alternation; the three roster placement tests that are GREEN
  require exactly those additions). Re-expressed as additive preservation:
  every golden var maps unchanged, no golden set vanishes or renames, no
  golden membership is dropped. Verified lossless against the C04 render
  first: the delta is pure additions (7 new gpu vars / +7 main members; 14 new
  gpu-ai vars / +6 main +8 solo, zero removals). New-membership exactness
  remains with the roster tests — the originally designed division of labor.
  macros/hooks/scalars assertions untouched.
* **(F) `hf_check.py::_tag_resolves`** — the frozen resolver implemented
  stem-startswith/dir-equal while its docstring promised llama.cpp's loose
  match; the live run reproduced dev's claim exactly: **97/117 false-MISSING**,
  including 12 pre-C04 production refs (`qwen38-orca`, kat trio, VLs) — the
  defect predates C04 (the tool was never exercised against a full render
  before). TEST-FAULTY. Fixed by mirroring the loader from raw source
  (common/download.cpp at 889edf43): `-hf` = `find_best_model` —
  case-insensitive regex `TAG[.-]` over the full path, candidates = `.gguf`
  whose basename lacks the CASE-SENSITIVE sidecar tokens
  (mmproj/imatrix/mtp-/eagle3-/dflash-/dspark-), sharded models via the
  -00001-of-NNNNN primary only, empty tag falls back Q4_K_M->Q8_0->first;
  `-hfd` = the DRAFT path (arg.cpp:411 sets download_mtp;
  `find_best_sibling(primary="", "mtp-", tag)`) — root-level `.gguf`
  containing case-sensitive `mtp-`, with the named sidecar required for churn
  sensitivity (the loader would silently pick a different draft otherwise).
  Live re-run: **117/117 refs resolve, zero problems** — which also
  re-confirms zero true negatives (no repo lookup errors, every wired
  repo:TAG still exists). Adversarial probes confirm no over-resolving:
  absent tags MISS, the `Q2_K`-vs-`Q2_K_XL` boundary is honored, sidecar-named
  files are not selectable as models, uppercase `MTP-…` is NOT a valid `-hfd`
  target (loader keyword is case-sensitive — C05 runbook note if the orca
  `-hfd MTP-draft.gguf` fallback is ever wired), nested mtp files MISS.

Post-D/E/F bar: full suite **0 failed / 129 passed / 12 skipped** (parity 23,
schema 12, wiring 26, roster 30, image 5P/4S, existing CI 33);
`RUN_HF_CHECK=1 LLAMA_SWAP_EVIDENCE=1 -k hf_repo_tags_resolve` **1 passed**;
`LLAMA_SWAP_EVIDENCE=1 -k autogen_integration` **3 passed / 5 skipped**
(docker/HF gates per waiver). No values/source change was demanded or made —
the C04 implementation satisfies the contract after D/E/F.


## 7bis. REPLAN 2026-10-24 rebase — amendments G..M (CA1, test-writer session; user-routed)

Chunk: `chunks/CA1.md`. Ground truth: plan REPLAN sections CR1-CR4 + DECISIONS
2026-10-24 rulings. Goldens: byte-untouched (`git diff -- .../golden` EMPTY,
re-verified). P2 cmd-parity bar: normalization + token-multiset equality code
retained VERBATIM — the loop keys change, the comparison does not.

* **(G) `llama_swap_testlib.py` — frozen replan tables.** NEW: `REMOVED_IDS`
  (13, verbatim CR3/DECISIONS set: coder duo + coder-next-ablit + kat trio +
  kat-1m trio + ruling-B qwen3-30b-a3b duo + qwen3-8b duo), `CATALOG_IDS`
  (58 = golden-union ∪ C04-approved − REMOVED = 38 chart-side + 20 gpu-ai-local),
  `GPUAI_LOCAL_CATALOG_IDS` (20), `GPU_ECHO_IDS` (24), `GPU_ENABLED_IDS` derived
  (34), `ENABLEMENT` {"gpu": 34/24, "gpu-ai": 58/0}, `ENTRYPOINT_FILE`,
  `is_echo_cmd()`. CHANGED: `GPU_DISABLED_IDS` 6 → the 3 ruling-B survivors
  (byte-pinned P3 list; old six preserved as `GPU_DISABLED_IDS_PRE_REPLAN`).
  Arithmetic vs goldens pinned by new table-audit test (green by design —
  acceptance 5 support).
* **(H) `test_config_parity.py` — P1-P6.**
  - old `model_id_sets_equal` (golden-subset + bounded C04 additions) → **P1**:
    rendered set == CATALOG exactly, both clusters [red: CA2/CA3].
  - old per-ID `ids_survive_in_fresh_render` (golden ⊆ fresh) → survivors-only
    (golden − REMOVED ⊆ fresh); strictness preserved by P1.
  - cmd + fields tests: comparison code UNCHANGED verbatim; loop now skips
    REMOVED (they leave the render under P1/P4 — skipping cannot mask a live
    divergence since presence is exact-set-pinned) [P2, green-at-handoff by
    design: preservation bar].
  - old byte-echo test (6 DISABLED) → P3 over the 3 survivors [green-at-handoff].
  - old `_assert_matrix_preserved` (amendment E) → **P6**: additive
    preservation MODULO REMOVED (vars/sets/membership checks now skip ruled
    ids; every SURVIVING mapping must still hold). macros/hooks/top-level
    scalars assertions untouched [green-at-handoff].
  - NEW **P4**: REMOVED ∩ (models ∪ matrix.vars-values ∪ preload) == ∅ per
    cluster [red: CA3].
  - NEW **P5**: catalog ids outside a cluster's golden are echoes (shape +
    id-prefixed, message NOT pinned) where the cluster disables them and live
    cmds where enabled — the isolation-flip expression [red gpu: CA2; gpu-ai
    green-at-handoff (ladder ids live, ENABLEMENT-consistent)].
  - NEW table-audit test (G arithmetic + survivors cross-check) [green].
  - UNTOUCHED: criterion-1 lint/renders, golden-inventory historical audit,
    aliases, VL setParamsByID render-side, closure, sentinel.
* **(I) `test_config_schema.py` — families.**
  - value-shape reads re-pointed `config.models` → `config.families`
    (derivation coverage == CATALOG; per-rung effective `hf`/`draft` vs golden
    with B/D-style live-golden routing; 12 VL rungs reference
    `filters: vl-workload` at family-or-rung level) [red: CA2].
  - NEW family-contract render tests (overlay-injected `smokefam`): ID
    derivation + `id:` override; family<rung field merge (ttl/use);
    enablement flip at either level + `disabled` beats `enabled` + default
    "not enabled" echo (substring only — message not pinned); raw
    `config.models.<id>` merge-OVER-expansion; duplicate derived ID FAILS the
    render (`pytest.raises`); `families` key stripped from rendered output
    [all red: CA2 — HEAD leaks the key and ignores families].
  - gpu-ai block test: the per-entry `assert "hf" in m` loop IS removed
    (round-1's patch silently no-oped here — caught by the review audit as
    Major-3; round 2 executed the ruled intent). NOT a weakening:
    service-layer re-declaration (dev deviation-3) is superseded by
    chart-side families coverage (above) + render-side P2; a post-CA2 partial
    override may legitimately omit hf (CR1.5). Raw set == {rana} and the
    one-line-exec + -hf/-hfd token bars retained verbatim.
  - Round-2 (review majors 1/4 + minors 5): the golden-cross-check skips the
    16 catalog IDs absent from BOTH pre-C04 goldens (their ref coverage stays
    pinned by test_new_roster.test_c04_1_exact_hf_ref_per_approved_id — a
    guaranteed post-CA2 KeyError removed, zero assertions lost);
    `test_fam_derivation_and_id_override` now asserts `id:` REPLACES the
    derived name (`f"{FAM}-q8" not in models`) instead of the old
    `f"{FAM}-off" not in models` clause, which was mutually unsatisfiable
    with the enablement test's CR1.4 echo requirement (Major 4 — the
    enablement test owns `off`); duplicate-ID check uses the shared
    `L.render_rc` (explicit rc + CA2-named message) instead of pytest.raises;
    all four previously message-thin fam tests now name CA2 literally
    (acceptance-1 wording made true, not just sampled-per-file).
  - placement test: models loop made tolerant of CA2 (`config.models` may
    vanish) + extended to families entries [green-at-handoff].
  - UNTOUCHED: per-ID composition/precedence/ttl-proxy/raw passthrough render
    bars (escape-hatch + override layer semantics survive the rebase),
    filterPresets value test, smoke-absent guard.
* **(J) `test_new_roster.py`.**
  - isolation flip: `gpu_ai_only_families_absent_from_gpu` →
    `..._present_as_echo_on_gpu` (present + fail-fast shape + id-prefixed)
    [red: CA2].
  - exact-set test expected → frozen CATALOG (58) both clusters [red: CA2/CA3].
  - per-ID -hf refs: routing generalized from fixed-D fallback to ENABLEMENT
    lookup (read the cluster where the rung is enabled; assert non-echo there)
    [green-at-handoff; CA2-safe by construction].
  - ttl test: presence-assert via ENABLEMENT-consistent `.get` (red would
    name CA2 if a ladder id vanished) [green-at-handoff].
  - UNTOUCHED: matrix placement (flashnext solo/absent, ladder membership),
    preload table, tuned regime, bf16 fail-fast, closure, capabilities.
* **(K) `test_autogen_wiring.py` — entrypoint rebase (CR4).**
  - removed: `_init_script`/`_sandbox` render-extraction machinery (the
    script leaves the yaml under CA4; the C-render-execution promise of §7.7
    transfers to executing the REPO file directly). RETAINED: the
    `_comment_only` predicate (a contract checker the NEW degrade tests use —
    round 1's span-edit dropped it, review Major-2 caught it, round 2
    restored it verbatim from d3e39b237; without it the two degrade contracts
    would NameError post-CA4 regardless of entrypoint.sh).
  - Round-2: the local `_render_rc` moved to testlib as shared
    `render_rc(cluster, overlay)` (schema's duplicate-ID test reuses it);
    duplicate `import os` lines, the no-op `import json`/`del json`, and an
    unused mkdir swept; the command-tripwire probe docstring now matches the
    recorded observation (green at handoff via the C03 script guard — a
    behavioral bar CA4 must keep green under the args guard).
  - degrade trio re-expressed against `containers/llama-swap-autogen/
    entrypoint.sh` invoked with the CR4 flags + stub CLI on PATH; SAME three
    contracts (empty-scan → comment-only + rc0; generate rc≠0 → degrade file
    + rc0; generate rc0 → content preserved) [red: CA4 — file absent; note
    stub constants FAIL_STUB/OK_STUB restored with the original shapes].
  - NEW: usage-error contract (missing --out → rc≠0 + message; degrade-rc0
    reserved for scan-empty/generate-fail ONLY) [red: CA4];
    `--home` drives generator HOME (C03 finding #1 made CLI-explicit)
    [red: CA4]; args-not-command pod shape (no command; --scan-dir set ==
    base.yaml models == scanPaths; --base/--out/--home pinned) [red ×2: CA4].
  - NEW drift probes (render-must-fail): scanPaths-vs-args disagreement; any
    initContainer `command:` (tripwire). OBSERVED STATE AT HANDOFF: both
    GREEN — HEAD's C03-era script-based guard fails these renders for the old
    mechanism reason; they are behavioral bars CA4 must keep green with the
    args-based guard (review re-checks post-CA4; a post-CA4 RED here means
    the guard lost coverage).
  - UNTOUCHED: image/security/mounts/volumes/env/base.yaml/colon-free/
    disjoint/reloader (C03 landed surface — all 25 greens stay).
* **(L) `test_autogen_image.py`.** ENTRYPOINT contract flipped: old
  `ENTRYPOINT .*llama-swap-config-autogen` → exec-form `ENTRYPOINT
  ["/entrypoint.sh"]` + `COPY entrypoint.sh` + repo file exists with `#!/bin/sh`
  shebang + exec bit (in-tree chmod or Dockerfile chmod/--chmod) [red: CA4];
  console-script-on-PATH retained as pip-install-line assertion + gated
  `--entrypoint llama-swap-config-autogen` docker checks stay (unchanged).
* **(M) `tests/evidence/c05_expected_evidence.yaml`** rebased wholesale onto
  CR2/CR3/CR4 expectations: counts 47/71 → 58 both (34 live + 24 echoes gpu;
  58 live gpu-ai); /v1/models superset + echo spot-proof step; args-driven
  initContainer + usage-vs-degrade distinction; removal grep list (13);
  CA3 consumer-sweep diff check (minuspod survivor verified-not-edited,
  pipeline-models rows delete-only + regenerated mirror); machine-global
  13+9 dangling enumeration (user-owned); runbook addenda (measure-on-cluster,
  uppercase-MTP caveat, picker widenings, rollback).

Handoff bars (CA1, 2026-10-24, helm v3.16.4 + app-template 5.0.1 from
/tmp/opencode): full suite **25 failed / 122 passed / 12 skipped**. Red set:
parity 5 (P1×2 → CA2/CA3, P4×2 → CA3, P5×1 gpu → CA2); schema 9 (value-shape
families 3 + family-contract renders 6 → CA2); roster 3 (exact-set ×2 →
CA2/CA3, isolation flip ×1 → CA2); wiring 7 (degrade trio 3 + usage 1 +
--home 1 + args-not-command 2 → CA4); image 1 (entrypoint relocation → CA4).
The two drift-behavior probes are GREEN at handoff via the C03 script-based
guard and must stay green post-CA4 under the args guard (review re-checks).
12 skips = unchanged evidence gates; existing CI files 33 green — zero
collateral. Every red message names its owning chunk (CA2/CA3/CA4), sampled
per file.


**Round-2 addendum (review r1, 2026-10-24, CHANGES_REQUESTED -> fixed same
session):** majors 1-4 + minors 5-6 + nit 7 all applied tests-only: (1)
golden-absent skip in the hf-cross-check (16 ids; roster keeps coverage); (2)
`_comment_only` restored verbatim; (3) the `assert "hf" in m` service-layer
loop actually removed (choice: execute the ruled intent, as §7bis-I and
CR1.5 already recorded — chart-side + P2 coverage strictly supersedes); (4)
derivation-test `off` clause replaced by the `id:`-replaces assertion (the
enablement test owns the echo, resolving the mutually-unsatisfiable pair);
(5) four schema reds gained literal CA2-named assertion messages; (6)
tripwire-probe docstring reconciled with §7bis-K's recorded observation; (7)
nits swept (`fam and ''` f-string -> plain derivation, shared render_rc into
testlib, duplicate imports/no-op json/unused mkdir removed; testlib soft
line-count ceiling acknowledged, no action). Post-fix bars: full suite
**25 failed / 122 passed / 12 skipped — red set NAME-IDENTICAL to the round-1
handoff**, zero NameErrors, goldens diff empty, integration gates 3p/5s
unchanged.


## 7ter. CA2 contract fixes — amendments N/G1 + O/G2 (test-writer session, 2026-10-24, user-routed)

CA2 dev (bda8c992a + 0602a2f49) landed the family catalog at 2f/145p/12s and
raised the two survivors as validation_at_fault. Both independently verified
BEFORE amending — both TEST-FAULTY, no dev error (dev's values satisfy every
bar once the test-side defects are corrected; dev is credited with a
compliant implementation, incl. the inert-but-documented rana chart rung
carrying the real hf/draft, deviation 1).

* **N (=G1) `test_c02_chart_models_are_composition_or_documented_escape_hatch`
  offender loop** — OLD: `for fam, spec in cfg["families"].items(): fam = fam
  or {}; for quant, rung in (fam.get("quants")...) ; merged = {**(fam or {}),
  **(rung or {})}` — read `.get`/`**` off the family KEY string: guaranteed
  `AttributeError: 'str' object has no attribute 'get'` for ANY families
  implementation (masked at handoff because the `assert cfg.get("families")`
  line above short-circuited first, and my round-1/-2 satisfiability sims
  never executed the loop against a real families dict). NEW: loop reads the
  SPEC dict (`spec.get("quants")`, `{**(spec or {}), **(rung or {})}`); the
  key stays only for the CR1.1 `f"{fam}-{quant}"` derivation. Intent and
  assertions unchanged — same rule, now actually executable; verified 0
  offenders against dev's chart values before applying.
* **O (=G2) `test_c02_chart_composition_hf_refs_match_golden` golden-`-hf`
  assert vs opaque bootstraps** — OLD: `assert cmd_flag_value(golden, "-hf")`
  for every rung. qwen38-rana's golden cmd is the raw `/bin/sh -c`
  multi-curl bootstrap: shlex keeps the quoted script ONE opaque token
  (correctly — that is llama-swap's SanitizeCommand shape), so no standalone
  `-hf` token can exist, while P1 + CR1 make rana a chart-side family rung
  with a real `hf` field. No compliant implementation could pass — structural
  contradiction, same class as ratified defect A (and it was MY round-1
  re-expression that moved rana into this loop without generalizing the
  extraction). NEW: when the token search finds no `-hf`, route through the
  token-boundary regexes `(?:^|\s)-hf\s+(\S+)` / `(?:^|\s)-hfd\s+(\S+)`
  over the raw text, rightmost match (llama.cpp effective-flag semantics,
  consistent with `cmd_flag_value`); the loud assert stays if NEITHER
  mechanism finds a ref. Verified: golden rana exec-line refs
  (`mradermacher/Qwen3.8-27B-RANA-abliterated-GGUF:Q6_K` +
  `ggml-org/Qwen3.8-27B-GGUF:mtp-Qwen3.8-27B-Q8_0.gguf`) == dev's chart rung
  hf/draft exactly; 41 routed ids green. Coverage strictly grows (ana's rung
  refs are now checked where previously the loop would have crashed or
  skipped).
* **Method correction (adopting CA2 dev's friction finding):** satisfiability
  simulation for amendments that rewrite value-shape loops must EXECUTE
  against a live implementation fixture (or a synthetic fixture of the final
  shape), not just mental/py-mini sims over goldens — the G1 str-attribute and
  G2 shlex-opacity classes both hid behind "the loop would run after CA2".
  Recorded for all future amendments; review audits amended loops against
  executed fixtures.
* **Carry-forward closed (§7bis-K):** both drift probes re-verified green at
  0602a2f49 UNDER CA4's new args-based guard (chart autogen container is
  command-free; the line-1045 `command:` belongs to the tools sidecar, outside
  the tripwire's scope), and `RUN_HF_CHECK=1` live verification passes against
  the post-CA2 renders.

Bars after N/O: full suite **0 failed / 147 passed / 12 skipped — the first
fully-green suite of the ticket** (parity 28/28, schema 18/18, wiring 32/32,
roster 30/30, image 6P+4S, existing CI 33, gates 8S; LLAMA_SWAP_EVIDENCE=1
autogen_integration 3P/5S; goldens diff empty). No assertion was weakened in
either amendment; G1 restored an intended-execution crash, G2 added a routing
branch with the loud assert retained.


## 7quater. CR5 contract amendment — CB1 (test-writer session, 2026-10-24)

Ground truth: plan "REPLAN ROUND 2 (CR5)" + user rulings (Option 2; RELAX P2
for display fields; free-16 full normalization) in DECISIONS 2026-10-24.
Goldens byte-untouched (diff empty, re-verified). cmd-token machinery
(`cmd_tokens`/`model_tokens`) untouched by this amendment — mechanically
diffed clean, the un-bent bar.

Assertions old-vs-new (deletion audit — exactly ONE scope removal, compensated):

* **P (user-ratified relaxation, the only one):**
  `test_c02_2_per_model_fields_deep_equal` — OLD: every non-cmd key incl.
  `name`/`description` deep-equal vs golden. NEW: those two keys excised from
  both sides before the compare (`_strip_display`). REPLACED BY (not bare):
  S1/S2/S3 below + the CR5 per-id before/after display table the user reviews
  pre-PR (plan bar 2). All other non-cmd fields (ttl/proxy/aliases/
  capabilities/filters/checkEndpoint/env) keep the golden deep-equal UNBENTED;
  P1/P2-cmd/P3/P4/P5/P6 untouched.
* **S1 `test_cr5_display_presence[2]`** — every catalog id on both cluster
  renders carries non-empty name AND description (58×2 ids × 2 fields).
  GREEN at CB1 handoff (probed: zero gaps), must stay green post-CB2 — the
  anti-vanishing bar for CB2 deleting display lines.
* **S2 `test_cr5_display_name_grammar[2]`** — non-exempt ids with an effective
  `-hf` ref (opaque-script fallback per ratified G2 machinery) must carry
  "(...TAG...)" in the name. Exemptions: raw-cmd escape ids {whisper, rana}
  and the cluster's models-layer name/description overrides (computed from
  service values, not hardcoded). Echo ids without a ref: name rule skipped
  (P5 owns echo shape; S1 covers their text). GREEN at handoff against HEAD's
  explicit text (probed: zero violations) AND guaranteed by the CB2 grammar.
* **S3 `test_cr5_ladder_descriptions_mention_tag[2]`** — desc-TAG obligation
  scoped to LADDER rungs: quant key ∈ {q3,q4,q5,q6,q8,bf16} via
  `id_family_index(chart values)`; live cmd; not models-overridden/escape;
  family not in `DESC_PROSE_EXEMPT_FAMILIES` =
  {qwen3.8-flash-next-orca} (gated-repo/HF_TOKEN caveat is prose data the
  grammar cannot carry — ruling 3 normalizes its NAME, the before/after table
  is the human review of its desc). GREEN at handoff (probed: HEAD clean once
  fn-orca exempted); CB2 grammar `{descBase}, {TAG} quant` satisfies by
  construction. Scope is family/key-DRIVEN data, no per-string exemptions.
* **T1 offenders rule (`test_c02_chart_models_are_...escape_hatch`)** — OLD:
  `hf` literal required. NEW: resolves via `L.rung_effective_ref` (literal OR
  repo|hfRepo + tag|tagCultures[tagCulture][quant]; maps read ONLY from chart
  values `config.tagCultures` — single source, no test-side copy; absent at
  HEAD ⇒ resolves to literals ⇒ shape-tolerant, GREEN both states).
* **T2 `test_c02_chart_composition_hf_refs_match_golden`** — eff comparison now
  uses the same `rung_effective_ref` vs golden `-hf` (B/D/G2 routing
  unchanged; refs are cmd-side contract — NOT relaxed). `draft` stays
  full-literal per CR5. GREEN both states (HEAD literals; CB2 shorthand must
  resolve to the same strings — that IS the fidelity bar).
* **U-1 `test_fam_key_stripped_from_rendered_output` extended** — banned
  top-level now {families, filterPresets, tagCultures}; banned per-entry keys =
  `NEW_SCHEMA_KEYS` (dispName/descBase/descTail/size/disp/suffix/hfRepo/
  tagCulture/tag/repo). GREEN at handoff on the real+SMoke render (keys
  absent today); CB2 must keep it green while introducing them values-side.
* **U-2 `test_cr5_shorthand_composition_render`** — synthetic FINAL-SHAPE
  family (§7ter method executed: fixture mirrors CB2's prescribed schema —
  hfRepo + tagCulture + culture map + repo/tag exceptions + size/suffix/draft/
  spec slots): asserts composed `-hf` refs, `(TAG)` name, MTP marker derives
  from draft/spec ONLY, suffix + size carried as data, no schema-key leak.
  RED at CB1 handoff naming CB2 (probed HEAD behavior: no composition, vocab
  keys leaked, rc=0 — the red is implementation-missing, verified message
  `culture-composed ref wrong: None (CB2)`).
* **U-3 `test_cr5_unresolvable_rung_fails_render`** — loud-offender rule (G1
  precedent): unresolvable rung (no ref/cmd/disabled) must fail the render.
  RED at handoff naming CB2 (probed: HEAD renders rc=0).

Classification per CB1 acceptance 2: red set == {U-2, U-3} (CB2-owned,
shorthand/stripping machinery); {P-modified, S1-S3, T1-T2, U-1} GREEN at
handoff by design (relaxation-restatement + replacement + shape tolerance).
Handoff bars (2026-10-24, helm v3.16.4): full suite **2 failed / 153 passed /
12 skipped**; per file: parity 34P, schema 18P/2F, wiring 32P, roster 30P,
image 6P/4S, existing CI 33P; gates `LLAMA_SWAP_EVIDENCE=1` 3P/5S; goldens
diff empty; no assertion outside P's two display keys was removed — review
audits this entry assertion-for-assertion (A–O precedent). CB2 completion bar:
0 failed / 155 passed / 12 skipped (§7quinquies carry-fix: '159' was a miscount) with the CR5 render-invariance + display
table bars (plan "CR5 controlling bars").


## 7quinquies. CC1 retirement ledger — CR6 autogen scope deleted (test session, 2026-10-24)

Ruling of record: DECISIONS 2026-10-24 "CR6" + plan "CR6 user rulings" — the user
removed the autogen machinery entirely and ADDITIONALLY ruled
`test_c04_4_full_roster_declared_validates` retired (superseding the planner's
keep-c04_4 posture: pod boot on-cluster is the only fleet -validate proof; C05
keeps the config-load observation). Every retirement below maps old -> WHY;
nothing kept was weakened (audit note at the end).

Retired files (chunk-origin; why = CR6 declared-only ruling):
* `test_autogen_wiring.py` — 32 cases retired (C03/CA4 wiring): init image /
  securityContext / mounts / volumes, CONFIG_DIR env, base.yaml ×4, degrade trio,
  usage-error, --home, args-not-command, drift probes ×2, synthetic-scanned
  disjoint, colon-free-ID ×2 (invariant exists only under the two-file merge; P1's
  exact colon-free CATALOG subsumes it). RE-HOMED ×2: reloader guard -> schema
  `test_cr6_reloader_guard_declared_scope[gpu|gpu-ai]` (auto-annotation OR explicit
  match naming `llama-swap-config` ONLY — BASE_CM leg deleted with the second CM).
* `test_autogen_image.py` — 10 cases (6P/4S): parses the Dockerfile CC2 deletes;
  `LLAMA_SWAP_IMAGE_EVIDENCE` retires with the file.
* `test_autogen_integration.py` — retired: `c03_2_3_base_yaml_*` ×2,
  `c03_4_scanned_half_*`, `c03_4_merged_declared_plus_scanned_validates`
  (final-4 nit-3 ledger-completion: was covered by file-level retirement + §6
  C03-4 trace; named explicitly so the item-by-item enumeration is complete),
  `c03_5_declared_only_empty_config_dir`,
  `c04_4_full_roster_declared_validates` ×2 (USER-RULED), `autogen_cli` venv +
  `fleet_image` fixtures. RE-HOMED: `test_c04_1_hf_repo_tags_resolve` ->
  `test_hf_liveness.py`, gated RUN_HF_CHECK ALONE (needs only helm + network;
  decouples the C04-friction accidental LLAMA_SWAP_EVIDENCE coupling).
  `hf_check.py` KEPT verbatim (roster-liveness machinery, CR6 brief).
* `fixtures/scanned_synthetic.yaml` — sole consumer was the disjoint test
  (grep-proven: only reference in the retired file) before deletion.
* Env-gate inventory: 12 evidence skips -> 1 (RUN_HF_CHECK).

testlib prune — every symbol zero-consumer-grepped AFTER the file retirements
(keeper set = parity/schema/roster/hf_liveness/hf_check + lib): removed
`AUTOGEN_REPO/COMMIT/TARBALL_URL/AUTOGEN_IMAGE`, `FLEET_IMAGE`, `docker_ready`,
`ENTRYPOINT_FILE`, `pod_spec`, `container`, `init_container`, `env_map`,
`mount_paths`, `FIXTURES_DIR` (−70 lines). Kept (consumers re-grepped):
`is_echo_cmd`, `render_rc`, render/golden machinery, `cmd_tokens`/`model_tokens`
(byte-verified unchanged — the un-bent P2-cmd bar), matrix helpers, ALL frozen
tables, CR5 resolution machinery, `TESTS_DIR` (consumed by test_hf_liveness.py).

Evidence yaml re-balance (dropped-vs-kept, item-by-item):
DROPPED: prereq "containers/llama-swap-autogen rebuilt WITH entrypoint.sh (CA4)";
gpu_box "pod initContainer state (CA4 shape)", "entrypoint degrade log",
"scanned half content", "reloader coverage of the new ConfigMap".
REPLACED BY: one gpu_box line "declared-CM watch-config hot-reload observation"
(single-CM scope: kubelet sync ~1min -> -watch-config in-place reload, or reloader
auto-roll as coarse backstop; bad reload keeps old config — v262).
REWORDED: "merged config load" -> "config load + model count (single declared
file, CR6)" with POD-BOOT-IS-THE-FLEET-PROOF wording + operator `-validate`
demoted to a runbook step; "/v1/models completeness" expect gains the CR5
picker-vs-display-table check. ADDED: runbook line retiring the autogen
:main->:v<run> pinning obligation; registry cleanup is N/A, not cosmetic-pending
(CC2 measurement: the image was NEVER PUSHED — the containers path never
triggered a push build on main/dev, PR builds are build-only; the stale
"optional cleanup" line in the plan-folder C05.md is coord's to annotate).
KEPT VERBATIM: PR/version prereq, CA3 sweep prereq, ArgoCD health, echo
spot-proof, serve-smoke approval gate, gpu-ai config-level confirmation, q5/q6
routable-unpreloaded-set-less, REMOVED(13) + matrix-closure sweeps, machine-global
13+9, first-load measures, uppercase-MTP caveat, enlarged-picker note, rollback.

Carry digit-fixes applied this touch (next-test-touch convention): §7quater 159 ->
155; §7bis-D "17 approved IDs" -> 16.

FROZEN BARS (CR6 user-ruling restated): CC1 completion == CC2 completion ==
**0 failed / 119 passed / 1 skipped**. Arithmetic: passed 155 − wiring 32 +
reloader re-home 2 − image 6 = 119; skips 12 − image 4 − integration 8 + re-homed
HF keeper 1 = 1. Per-file recount: parity 34, schema 22 (20+2), roster 30,
CI-existing 33, hf_liveness 1S (120 collected). THE CC1 INVARIANT: the bar passes
against the UNMODIFIED source (autogen still wired at HEAD) — no surviving test
references it; CC2 then removes source against an already-green shrunk suite.
Gate bars: `RUN_HF_CHECK=1` alone => 1p WITHOUT docker/venv/LLAMA_SWAP_EVIDENCE;
direct `hf_check.py` => all refs OK exit 0. CC2 adds: declared-CM byte-equal ×3
renders, pod-delta removals-only, residual sweep clean.

Audit note (acceptance 5): zero assertion-scope change to KEPT surface —
test_config_parity.py and test_new_roster.py untouched by this session's round
(diff-verified); schema additions are the two re-homed guards only; every other
ledger line is a retirement or re-home.


## 7sexies. C01 boot-safety contract — macros.go port-rule simulation + amendments (test session, 2026-10-25)

Ticket: `.agents/plans/2026/2026-10-bug-llama-swap-echo-proxy-port/` — C01 is
executed ONLY by this ticket's agent-test session (immutable-tests rule, DECISIONS
conventions). Verified baseline on main @90e660569 (re-run this session,
helm v3.16.4 + app-template 5.0.1): **1 failed / 118 passed / 1 skipped** —
the single red is `test_render.py::test_gpu_ai_tools_container_enabled_with_token`
(renovate drift), matching the plan's verified baseline.

* **(N1) NEW `test_boot_safety.py` — invariant + echo pin (5 cases).**
  - `test_c01_port_rule_invariant[default|gpu|gpu-ai]`: deterministic offline
    python simulation of the deployed binary's `internal/config/macros.go`
    port rule (byte-identical v262–v266 — tarballs diffed this session) over
    the FULL rendered config of each leg: StripComments on cmd/cmdStop,
    **default-proxy injection**, mergeModelMacros (MODEL_ID first + global +
    entry-level overrides in place), substituteMacroList (reversed
    declaration order), then the `${PORT}` test on the EXPANDED strings
    (macros.go:182-184). Go stops at the first violator; the test enumerates
    EVERY violating id (plan requirement; diagnosability of a 24-entry
    crash-loop). This is the pre-merge boot proof that replaces the never-run
    docker `-validate` (plan "Acceptance caveat").
  - `test_c01_echo_entries_proxy_is_port_free[gpu|gpu-ai]` (the plan's
    "proxy-absent" leg, re-expressed — see FIDELITY NOTE): every echo-shaped
    entry (`testlib is_echo_cmd`) must carry a macro-EXPANDED proxy with NO
    `${PORT}`. This is the compensating leg of the N2 excision (an excision
    is never bare — §7quater P precedent), scoped to exactly the golden∩fresh
    echo set's superset (24 gpu echoes ⊇ the 3 golden survivors).

* **FIDELITY NOTE (plan impact — recorded for coord/user; the contract pins
  the PROPERTY, the plan owns the mechanism).** `macros.go:127-129`
  (byte-identical in ALL of v262–v266) injects `MODEL_CONFIG_DEFAULT_PROXY =
  "http://localhost:${PORT}"` (model_config.go:11) into every model WITHOUT a
  `proxy` key BEFORE the port rule — and upstream's own test
  `config_test.go:228` ("Proxy value required if no ${PORT} in cmd", present
  in v262 AND v266) proves a key-less model whose cmd lacks `${PORT}` fails
  with exactly the incident error. Consequences:
  - the planned C02 mechanism ("echo entries render WITHOUT a proxy key")
    leaves the config unloadable: key absent → default proxy injected →
    `${PORT}` in proxy, none in cmd → the same crash-loop. A simulation
    that skipped the injection would certify a still-broken box; the
    invariant (N1) includes the injection precisely so that cannot ship
    green.
  - the echo pin therefore asserts the binary-acceptable property — an
    explicit, post-expansion `${PORT}`-FREE proxy on every echo entry —
    instead of key absence, which is the one state the rule rejects
    unconditionally for a portless cmd. The literal choice (e.g.
    `proxy: "none"` — url.Parse-safe at load.go:188, runtime-inert:
    doStart runs the cmd first, so the fail-fast echo UX is preserved) is
    plan-owned; the test is satisfiable by any such choice and by no
    other state.
  - plan wording needing update to match (bars unchanged): C02 acceptance 4
    ("exactly 24 proxy lines removed" → 24 proxy lines REPLACED with an
    explicit `${PORT}`-free value) and the C02 note "Dropping proxy from
    echo entries also stops llama-swap allocating ports … matches
    pre-check intent" (allocation stops only via the explicit value —
    absence re-triggers the default).
  - DECISIONS should record the disproven assumption 3 (planned shape
    insufficient) alongside 1 and 2 when coord touches it.

* **(N2) `test_config_parity.py::test_c02_2_per_model_fields_deep_equal` —
  golden-proxy supersession carve.** OLD: every non-cmd key except display
  text (ttl/PROXY/aliases/capabilities/checkEndpoint/filters/env) deep-equal
  vs golden. NEW: for EXACTLY the entries whose fresh render is echo-shaped,
  `proxy` is excised from both sides; everything else is VERBATIM — every
  other field on every entry, the proxy deep-equal on LIVE entries, the P2
  cmd-token machinery (`cmd_tokens`/`model_tokens`), and the P3
  byte-identical-echo test (diff-audited: the sole hunks sit inside this one
  function; zero bytes changed elsewhere in the file). Scope at handoff: the
  3 golden survivors GPU_DISABLED_IDS ⊂ GPU_ECHO_IDS —
  qwen3.6-35b-a3b-bf16, qwen3.6-35b-a3b-1m, qwen3-vl-30b-a3b-bf16 — the only
  golden∩fresh entries where the golden pins `proxy: http://localhost:${PORT}`
  on an echo (the other 3 pre-replan golden echoes left with REMOVED_IDS;
  the gpu-ai golden has no echoes). This is the EXPLICIT RECORDED
  SUPERSESSION (DECISIONS falsified-assumption 2): the golden's echo proxy
  lines encode the pre-check binary's tolerance, not a validator-checked
  truth; the carve is compensated by the N1 echo pin, which asserts the
  post-expansion property on all 24 gpu echoes — a strict superset of the 3.
  The chunk's "fresh-side absent-assert leg RED in this loop on gpu" is
  allocated to the dedicated N1 pin instead: under that allocation the
  loop stays green at handoff (the carve is a no-op while fresh proxy ==
  golden proxy), which is the ONLY allocation consistent with the plan's
  handoff bar (3 reds, none named this test); same "red names the owning
  chunk" pattern as §7bis P5.

* **(N3) `test_render.py::test_gpu_ai_tools_container_enabled_with_token` —
  stale python tag.** OLD: `assert tools["image"] ==
  "python:3.12.15-slim-bookworm"` — out-dated by renovate bump dbaaadced
  (values carry `python:3.15.1-slim-bookworm`); the verified main-branch red.
  NEW: the assertion reads the chart's managed pin — `f"{repository}:{tag}"`
  from `values.yaml →
  app-template.controllers.llama-swap.containers.tools.image` — so a future
  renovate bump cannot re-out-date the test (DECISIONS 2026-10-25: renovate
  is the source of truth for managed tags; the test follows the chart, never
  the reverse). Intent unchanged: the tools sidecar uses the chart-pinned
  python image. Grep of the suite: this was the ONLY hardcoded image tag;
  NO test pins the main llama-swap image (grep-verified, as C03's chunk
  states), so C03's tag change cannot reopen a red.

RED/GREEN classification at handoff (verified by full-suite run, gates off):
  RED — all three implementation-missing, all naming C02, zero harness errors:
  - `invariant[default]` — 58 violators == CATALOG_IDS (the full-catalog
    default-disabled render: every entry an echo)
  - `invariant[gpu]` — 24 violators == GPU_ECHO_IDS exactly
  - `echo-pin[gpu]` — the same 24, enumerated
  GREEN:
  - `invariant[gpu-ai]` — 58 live: 56 composed cmds carry `${server-cmd}`
    whose value holds `--port ${PORT}`; whisper-large-v3 + qwen38-rana raw
    cmds carry literal `--port ${PORT}` (probed this session)
  - `echo-pin[gpu-ai]` — vacuous (no echo entries)
  - `deep-equal[gpu|gpu-ai]` — preservation (carve is a no-op at handoff)
  - `test_gpu_ai_tools_container_enabled_with_token` — amended (N3)
  - every other baseline green — zero collateral

Exact post-amendment arithmetic (plan invariants: verified baseline, zero
new skips, C02-done == 0 failures):
  baseline        1f / 118p / 1s          (120 collected; verified this session)
  + N1            +3 invariant, +2 echo-pin (F: invariant[default],
                                            invariant[gpu], echo-pin[gpu];
                                            P: invariant[gpu-ai], echo-pin[gpu-ai])
  + N3            baseline 1f → 1p
  handoff (C01)   **3f / 121p / 1s**      (125 collected — MATCHES THE PLAN)
  C02 done        the 3 reds flip         **0f / 124p / 1s** (== C02
                                            acceptance-1 bar, unchanged by
                                            the FIDELITY NOTE)

Goldens: `git diff -- charts/llama-swap/tests/golden` EMPTY (re-verified
this session). P3 byte-pin + P2 token machinery byte-identical (diff
audited). Files touched: `test_boot_safety.py` (NEW),
`llama_swap_testlib.py` (additions only — default-render helper + simulation;
148 insertions / 0 deletions), `test_config_parity.py` (N2),
`test_render.py` (N3). No source file touched; nothing under
`.agents/plans/`.

---

## 8. debug-flash-next-vulkan-oom — C01/C03/C04 contracts (test session, 2026-10-26)

Ticket: `.agents/plans/2026/2026-10-debug-flash-next-vulkan-oom` (branch
`debug-flash-next-vulkan-oom-openrouter-qwen3-8-flash`). C02 was SKIPPED by
the operator (debug-live, DECISIONS 2026-10-26) — no tests written for it.
Assertions encode the chunk acceptance criteria; RESEARCH.md informed
structure only (coord scope letter rule).

### 8.1 Files written

* `test_flashnext_regime.py` — C03 AC1/AC4 render contract + AC5 flag-audit
  evidence gate. Regime asserted on the EXPANDED cmd
  (`llama_swap_testlib.effective_cmd`, new helper: the macros.go-port
  `_expanded` pipeline reused from the §7sexies simulation) because chart
  composition may legitimately relocate placement under any macro name —
  the contract is the token stream llama-swap executes.
* `test_flashnext_blast_radius.py` — C03 AC2/AC3 vs the frozen pre-chunk
  baseline (§8.3): `${moe}` byte-frozen, macro-ADD-only policy with
  containment (a new macro may be referenced by flash-next cmds only), all
  non-flash-next models/matrix/hooks/scalars identical, gpu render identical
  with one documented exemption (§8.4), echo strings exact + macro-free.
* `test_c01_evidence.py` — C01 AC1-7 + the chunk's grep addenda as artifact
  validators over `EVIDENCE.md` (module-level gate: absent file = loud skip —
  TEST_SPEC §4 style, the artifact is ticket-internal and the C03-era CI must
  not red before wave 1 lands; once the file exists every check is HARD).
* `test_c04_verification.py` + `evidence/c04_verification_procedure.yaml` —
  the plan-Commands "command lists" artifact (readonly MCP/HTTP steps
  `run_by: agent-readonly`, pod/host exec `run_by: user` — repo grants no
  exec). Layer A audits the procedure's own completeness (four journal
  patterns exact, freeze-protocol flags, user-run attribution, no /sys
  writes, fingerprint contract, MTP disjunction, B conditional). Layer B
  validates the EVIDENCE.md post-fix record vs AC1-5 — skipped until the
  section exists (C04 is post-merge work).
* `llama_swap_testlib.py` — `effective_cmd`, `FLASHNEXT_FAMILY_IDS`,
  `baseline_raw/baseline_config`, and the `C04_FLASHNEXT_DRAFT` comment
  re-homed from "unconditional" to "gate-2 candidate" (supersession §8.2).
  Additions only; no frozen table moved.

### 8.2 Re-expression (ledger, per §7 style)

* `test_new_roster.py::test_c04_1_flashnext_mtp_draft_wired` — the ONLY
  existing test modified. Old contract (prior ticket DECISIONS: "in-repo MTP
  draft unconditional for the unsloth ladder", -hfd pinned on q3/q4) is
  superseded by this ticket DECISIONS 2026-10-26 "MTP is a two-gate path —
  off for the first load"; leaving the old asserts in place would make C03
  AC1 (no spec/draft first cut) and AC7 (suite passes) mutually
  unsatisfiable — the plan resolves the contradiction THROUGH the test
  session ("goldens/contracts move via the agent-test session"), so this is
  a RE-EXPRESSION, not a weakening: draft/-hfd/spec must now be ABSENT
  family-wide (q3/q4/q5/q6/orca — the orca rung's per-rung `spec:` is part
  of the same first cut), and the expert-offload leg is re-checked on the
  expanded stream (macro-name-agnostic) instead of the raw
  `${moe}`/`${fn-moe}` token set. Function name kept for cross-ticket grep
  continuity; docstring carries the provenance. `C04_FLASHNEXT_DRAFT` stays
  as the gate-2 sidecar ref.
* 2026-10-26 GATE-2 FOLLOW-ON to the entry above (operator GO per DECISIONS;
  chart commit eb0a0cf92 — the flip this entry anticipated): both absence
  contracts re-expressed back to the WIRED shape, read against the exact
  re-added render. `test_c04_1_flashnext_mtp_draft_wired` now pins `-hfd`
  == `C04_FLASHNEXT_DRAFT` + `--spec-type draft-mtp` +
  `--spec-draft-n-max 2` on q3/q4/q5/q6, spec ALONE on orca-q6 (embedded-MTP
  expectation kept; what resolves at runtime stays deliberately unasserted);
  the expert-offload clause is unchanged.
  `test_flashnext_regime.py::test_c03_ac1_first_cut_has_no_mtp_draft_or_spec`
  becomes `test_c04_gate2_mtp_draft_spec_readded` (same 5-way parametrize,
  same expanded-stream read), adding the `--spec-draft-p-min` ABSENCE pin —
  gate 2 restored the exact lines C03 removed (EVIDENCE.md §13.7), which
  carry no p-min. Renamed rather than kept under a wrong-label name; the
  first-cut window stays documented here and in §8.5, and git history keeps
  the old name greppable. Blast-radius contracts are untouched — the gate-2
  diff lies inside `FLASHNEXT_FAMILY_IDS` and the `, MTP` display marker
  returns to the §8.4-exempted shape (both verified green by dev's render
  audit at eb0a0cf92).

### 8.3 Baseline capture (the "approved pre-chunk table", plan Commands)

`tests/evidence/flashnext-pre-chunk-baseline/{gpu,gpu-ai}.config.yaml` —
verbatim ConfigMap `config.yaml` DATA strings captured 2026-10-26 at commit
`561d0559e`, CLEAN TREE (no ticket edits existed; C02 skipped means the
service layer carries no containment), helm **v3.16.4** + app-template
5.0.1, via the harness extract-and-render path; round-trip byte-identical
verified at capture (PROVENANCE.md). Why not the 2026-10-22 goldens: they
predate the flash-next/ornith catalog, so golden-era parity cannot pin the
surface C03 must preserve; goldens themselves are UNTOUCHED
(`git diff -- charts/llama-swap/tests/golden` empty).

### 8.4 Documented interpretations (contract preserved)

Satisfiability self-test: both artifact-validator modules take an optional
`FLASHNEXT_EVIDENCE=<path>` override; run against a synthetic fully-compliant
fixture (/tmp, outside the repo) all 22 checks pass, and they correctly red on
a fixture missing the tensor-name proof — the validators are satisfiable, not
permanently-red, and negative-direction discrimination holds.

* AC1 "contains no `--load-mode none`" read STRICTLY: a rightmost-wins
  shadow (`none` still in the stream, `mmap` after it) FAILS — the pinned
  dry-load path must be gone from the expanded stream, not outranked. The
  pair form `--load-mode X` and the `--load-mode=X` form are both parsed.
* AC3 "gpu byte-identical": enforced structurally on the parsed config +
  EXACTLY on every cmd string, with one exemption — the derived display
  fields (`name`/`description`) of the five gpu-echoed flash-next ids. The
  `, MTP` name marker derives from family draft/spec presence, so C03's
  sanctioned removal legitimately re-composes those two strings on gpu too.
  Same display-excision lineage as ratified amendment P (§7); every other
  byte, echo cmd strings included, is strict.
* AC4 (C02-skipped branch): the chunk's "un-disable q3" step is vacuous; the
  durable check is that NO flash-next id gains a `disabled:` stub and both
  families keep `enabled: true` in the gpu-ai `config` layer.
* `--no-host` is NOT asserted either way (C03: "evaluate, default OFF ...
  decision + reason in the PR/DECISIONS" — a reasoned add is a recorded
  outcome, not a contract violation).

### 8.5 Red/green at write time (helm on PATH, gates off)

Baseline this session pre-edit: **124 passed / 1 skipped / 0 failed** (green
HEAD preserved — nothing existing was weakened except the §8.2 re-expression,
which flips red by design).

Handoff state: **16 failed / 142 passed / 8 skipped** (166 collected).

* RED — 16, all naming the missing C03 regime (implementation-missing, none
  is an error): `regime load_mode[5]` (stream carries `--load-mode none`),
  `fit_off[5]` (flag absent), `first_cut_no_mtp[5]` (-hfd/spec present),
  roster `flashnext_mtp_draft_wired[1]` (re-expressed, §8.2).
  Dev flips all 16 by landing branch A; review re-runs.
* GREEN — new passes 19: regime ×7 (the offload-leg param ×5 already hold
  under ${moe}, q3 rung specifics, the YAML-only enablement audit),
  blast-radius ×5 (equal today BY CONSTRUCTION — they turn red only when
  C03/C04 steps outside the family zone), C04 procedure self-audit ×7
  (hard pre-flight contract). Prior suite: 123 passed (the 124-head minus
  the re-expressed roster pin, red by design) — nothing existing was
  otherwise weakened.
* SKIPPED — 8: prior §7sexies gate (1), new C01 artifact gate (1 module),
  C04 post-fix record gates (5), RUN_FLAG_AUDIT (1). RUN_FLAG_AUDIT=1 is the
  plan-Commands b11810 flag-existence audit — C03 dev must run it BEFORE
  using the flags (AC5: absent flag = hard chunk fail).
* HELMLESS degradation verified: with `helm` off PATH the 27 new render
  tests skip loudly ("helm binary not on PATH") and the YAML-only enablement
  test still RUNS (green) — a clearly-reported skip, never a false pass.

STEADY STATE after the gate-2 contract re-expression (§8.2 follow-on),
measured 2026-10-26 with helm v3.16.4 on PATH (/tmp/opencode/bin,
app-template 5.0.1 vendored): **173 passed / 0 failed / 2 skipped**; the two
skips are the opt-in network evidence gates (RUN_FLAG_AUDIT, RUN_HF_CHECK —
reasons shown by -rs). Armed re-runs both pass: RUN_FLAG_AUDIT=1 => 174/0/1,
RUN_HF_CHECK=1 => liveness 1 passed (the re-added -hfd sidecar ref resolves
live). History preserved: the 16 write-time REDs went green with C03 dev
(5ea66f17d: 168/0/7), then the gate-2 re-add eb0a0cf92 flipped the 5×
first-cut absence + 1× roster re-expression red BY DESIGN (6 failed / 167
passed / 2 skipped, dev stage-2 run) — the §8.2 follow-on re-greened them
against the wired shape. The 5 C04 post-fix validators now run HARD (the
EVIDENCE.md §13 section they gate on has landed).

### 8.6 Trace: acceptance criteria -> tests (this ticket)

* C01-1 -> evidence `ac1_buffer_split_fingerprint_or_absent_statement`
* C01-2 -> evidence `ac2_gtt_budget_measured`, `ac2_required_vs_budget_verdict`
* C01-3 -> evidence `ac3_lockup_timeout_recorded_no_change`
* C01-4 -> evidence `ac4_ik_presence_verdict`
* C01-5 -> evidence `ac5_tensor_name_dump_verdicts`, `ac5_mtp_hc_layout_verdict_exact_tensor_name`
* C01-6 -> evidence `ac6_pod_mesa_version`
* C01-7 -> evidence `ac7_sources_timestamps_and_user_run_attribution`
* C01 tasks 17-19 -> evidence `task_timeline_and_comparison_and_host_snapshot`
* C03-1 -> regime `ac1_load_mode_mmap_and_never_none`[5], `ac1_fit_off_present`[5],
  `ac1_first_cut_has_no_mtp_draft_or_spec`[5] (superseded post-gate-2 by
  `test_c04_gate2_mtp_draft_spec_readded`[5], §8.2), `ac1_ngl99_and_expert_offload_leg`[5],
  `ac1_q3_rung_specifics` (+ roster re-expression §8.2, gate-2 follow-on)
* C03-2/3 -> blast `ac2_moe_macro_byte_frozen`, `ac2_non_flashnext_models_identical_gpu_ai`,
  `ac2_matrix_hooks_scalars_identical`, `ac3_gpu_render_preserved`,
  `ac3_gpu_flashnext_echoes_stay_macro_free`
* C03-4 -> regime `ac4_service_layer_carries_no_flash_next_disable`
* C03-5 -> regime `ac5_flags_exist_in_b11810` (RUN_FLAG_AUDIT)
* C03-6 -> blast policy notes (B/C1 outcomes are DECISIONS/coord-owned; a
  C1 rung ADDITION deliberately reds `ac2_non_flashnext_models_identical_gpu_ai`
  and is re-baselined via the test session, never patched in dev/review)
* C03-7 -> the whole suite + goldens untouched (§8.3)
* C04-1..5 -> procedure A-layer ×7 (hard now) + post-fix B-layer validators ×5
  (gated) — the recorded-attempt half is exactly "review re-runs criteria 1-5
  read-only against recorded artifacts"

## 9. cf-86 feat-more-strata-models — C01..C06 contracts (test session, 2026-10-29/30)

Ticket: `.agents/plans/2026/2026-10-cf-86-feat-more-strata-models` (branch
`cf-86-feat-more-strata-models`). Two ablated Strata arenas (C01 SC117
abliterated IQ3_XXS, C02 gated orcarouter IQ3_XXS), two llama.cpp heretic
rungs (C03 flash-next Q4_K_M, C04 27B Q4_K_M-MTP), the provider catalog
(C05) and the FINAL Shape-A-tweak Strata Q4 arena (C06). Frozen ids/files come
from DECISIONS "Renumap + final-shape decisions" + the C06 FINAL pin block;
the peers evidence and every golden/frozen table are test-writer property —
dev edits surfaces, never these files.

### 9.1 Files written

* `test_strata_abliterated_rung.py` (C01) — arena + residency-contract
  equality with the primary, serve-flag surface ⊆ {--profile,--host,--port},
  matrix ⊇ {p,s,c} with the no-two-arenas-per-combo law, profile ConfigMap
  key set == the profiles the served arenas name, run-config shape
  (`model_name: qwen3.8-flash-next-abliterated-iq3_xxs`, `api_key "none"`,
  `user_args []`, exe/cwd/backend identity = primary's), envelope equality
  with the primary (#1601 pair + conversation-cache arms), Strata-data path
  SHAPE + distinctness from the IQ3_S pair, node-bleed flag absence
  (--ple-io/--batch/--layer-split/--prompt-cache/--vision), strip-list arm,
  keyless-serve guard, peers-wave equality.
* `test_strata_orca_rung.py` (C02) — arena + contract, inner alias
  `qwen3.8-flash-next-orca` unique across model aliases AND profile
  `swappabel_alias` and never equal to the outer `…-orca-q6`, matrix `o` +
  alternation, four-profile ConfigMap + IQ3_XXS-orca shape with the primary's
  memory declaration verbatim, pack-path shape/distinctness, **token-placement
  law** (`HF_TOKEN` via `secretKeyRef: hf-token` on the model-fetch init — and
  ONLY there; serve path/inner `apiKeys`/every profile stays keyless),
  manual-pack invariants (`.pack-orca` marker named, `fail()` helper kept, no
  `rm -rf` of Strata-data), peers four-id wave.
* `test_heretic_rungs_flashnext.py` (C03) — exact expansion id
  `qwen3.8-flash-next-heretic-q4` (no sibling variant), mmap-regime legs
  compared against the DONOR's rendered legs (`-ngl 99`, the byte-exact `-ot`
  string, `--load-mode mmap`, `--fit off`) rather than restated, 262144 only,
  gate-verified `-hf`, draft-mtp n-max 2 (the pack carries MTP), no preload and
  no services models-layer override, `fnher` in `solo` only, the two-mmap-
  rungs-never-co-load law, gpu echo macro-free, chart-default render family-
  off, RUN_HF_CHECK-armed liveness for BOTH cf-86 refs in one network pass.
* `test_heretic_rungs_27b.py` (C04) — exact id `qwen38-heretic`, dense regime
  (-ngl 999 / --load-mode none / -np 1, compared against sibling `qwen38-ara`)
  with the MoE/mmap legs asserted ABSENT (the regime-difference proof the chunk
  demands), `-c 262144`, gate-verified `-hf`, embedded-MTP (no `-hfd` draft)
  with draft-mtp n-max 2, ttl 300, `q38her` in `main` only + never-two-dense-
  per-combo, no preload / no models-layer entry, gpu echo, no second raw-cmd
  escape hatch.
* `test_catalog_contract.py` (C05) — a comment-respecting JSONC loader (URLs
  carry `//`), presence+shape (modelID==key, `limit.context` 262144,
  `capabilities.tools: true`, no invented `limit.output`) for the cf-86 new
  ids; the hygiene half read from the RENDER (enabled `ornith-1.5-122b-*` +
  `qwen3.8-flash-next-orca-q6` + `qwen3.6-35b-a3b-q6`), the card's already-
  served asks verified, the **no-phantom arm** (catalog key ⊆ render models ∪
  render aliases ∪ peers-routed arenas ∪ `:tags`/`:caption` workload aliases —
  the allow-list is explicit so review counts it), the ruled 13 never return,
  trio grep (chart+service+catalog) per new id, provider settings/
  `default_agent: plan` byte-stable, the Q6-default absence guard (§9.4), and
  the ornith Shape-B absence-arm.
* `test_strata_q4_rung.py` (C06) — arena + contract + five-way alternation
  (no combo with two arenas, all five reachable), the FINAL pin block verbatim
  (`--conversation-cache-mib 8192`, `…-slots 16`,
  `--slot-save-path /models/strata/sessions`, `--memory-limit-mib 95232`),
  UD-Q4_K_XL path markers (shape + "Q4" class marker, names never guessed),
  negative pins (--batch / --layer-split / --prompt-cache 0 / --ple-io absent,
  session path present), four earlier profiles byte-unchanged with IQ3_S
  keeping 92160, the 100Gi↔95232 lockstep (requests stay 64Gi, grace stays
  420), peers five-id final order, init `q4` token + `STRATA_MODEL_Q4:
  unsloth/UD-Q4_K_XL` + idempotent `mkdir -p /models/strata/sessions`, and no
  new Secret consumer (unsloth ungated).
* `evidence/strata-profiles-pre-cf86/{strata-iq3_s.json,
  strata-strix-iq3_s.json}` + `PROVENANCE.md` — the pre-cf-86 run-config
  captures the "existing profiles byte-unchanged" arms compare against
  (branch tip `4f7126689`, parsed-JSON equality: helm re-wrap is not behavior).
* `evidence/strata-peers-expected.yaml` — re-authored with `models_states`:
  the wave table (2→3→4→5 ordered peer lists) that keeps the SAME immutable
  suite correct between chunks. `models_allowed` stays the C06-final five.
* `strata_testlib.py` — cf-86 constants (ABL/ORCA/Q4 ids, profile files,
  `INNER_MATRIX_VARS`, `ORCA_PACK_MARKER`, the Q4 envelope + negative-pin
  tuple) plus `strata_peers_evidence`/`expected_strata_peers` (the wave law,
  validated on load), `INNER_PROFILE_FILES`/`expected_profile_files`/
  `profile_files`/`profile_file_of`, and `serve_path_secret_hits` (the
  keyless law scoped to the serve path, §9.2). Additions only.
* `llama_swap_testlib.py` — `CF86_NEW_IDS`/`CF86_NEW_FAMILY`/`CF86_HF_REFS`
  (the two refs verified against the live HF API by this session) /
  `CF86_MATRIX_VARS` (letter→id) / `CF86_SET_ADDITIONS` /
  `CF86_MOE_OFFLOAD_LEG`, and the frozen roster tables grown by exactly the
  two new ids (CATALOG 58→60, GPU_ECHO 24→26, GPUAI_LOCAL 20→22 — partition
  60 = gpu 34+26 / gpu-ai 60+0).

### 9.2 Amendments to existing files (never weaken; re-expression ledger)

Author-side validation faults found by the C01 dev round (and the mechanical
repairs applied to them, incl. the latent C02/C06 twins) are ledgered in §9.6;
the C02 test round's additive pack arms and its one author-fault repair
(`test_c02_peers_carries_the_orca_arena_once` unpack) are in §9.7.

* `test_config_parity.py::test_repl_tables_match_frozen_decisions` — the
  frozen-table identity is now golden-union − REMOVED + `CF86_NEW_IDS` (the
  two rungs postdate the byte-untouched goldens, which stay byte-untouched)
  and the partition assertion moves to 34+26. New arm: a cf-86 id may not
  predate the goldens.
* `test_config_parity.py::_assert_strata_peers` and
  `test_flashnext_blast_radius.py::_cf77_peers_carved` and
  `test_strata_wiring.py` peers arms — subset-of-final semantics replaced by
  exact ordered equality against a sanctioned `models_states` wave (a subset
  of the five would let a phantom or a dropped `strix` through).
* `test_strata_wiring.py::test_c03_extract_and_render_yields_on_shape_keyless`
  and the outer-shadow/preload arms — pinned pair {primary,strix} → the wave
  law / `S.INNER_IDS` (five arenas), so the guards cover C01/C02/C06 without
  being re-written per chunk.
* `test_flashnext_blast_radius.py` — cf-86 delta allowances: the gpu-ai model
  additions must be exactly `CF86_NEW_IDS` (each live, not echo), the gpu
  roster may gain exactly those two as fail-fast echoes, and `matrix` moves
  from byte-equality to `_cf86_matrix_violations`: baseline vars byte-equal,
  new vars ⊆ the pinned letters with pinned ids, no baseline DNF combo lost,
  and every NEW combo must actually pair a cf-86 rung (a re-pairing of
  existing rungs changes co-residency for models this ticket does not own).
  Everything else in that file stays strict.
* `test_strata_render.py::test_c01_memory_cgroup_and_engine_cap` — the 96Gi
  pin becomes the sanctioned PAIR set {96Gi ↔ 92160, 100Gi ↔ 95232} with an
  explicit lockstep assertion (C06 raises both legs together; either leg
  alone is what #1601 exists to prevent). The exact final pair is pinned
  again in `test_strata_q4_rung.py`.
* C01's "no HF_TOKEN/secretKeyRef anywhere in the strata pod chain" is
  re-expressed as two arms, not relaxed: the SERVE path (containers, inner
  config, profiles) is keyless unconditionally (`serve_path_secret_hits`),
  and while the orca arena is unserved the init chain must be token-free too.
  From C02 on, `test_strata_orca_rung.py` owns the R-d download-only
  exception and pins its placement. Contract preserved; scope made explicit.
* Model-dir/pack dir NAMES are not pinned (C01/C02/C06 gates parameterize
  them: "never guessed"). The executable part is path SHAPE (under
  `/models/strata/Strata-data/`, Q4-class marker) + distinctness from the
  IQ3_S primary's files — an arena pointing at another arena's weights is the
  failure those arms catch.

### 9.3 Red/green at write time (helm on PATH, gates off) — superseded by §9.6

`python3 -m pytest charts/llama-swap/tests -q` → **59 failed, 274 passed,
3 skipped** (baseline before this session's work: 264 passed / 2 skipped — no
previously green test was weakened).

RED (implementation-missing; each message names its chunk/id): C01 7,
C02 8, C03 6, C04 7, C06 7, C05 13 (5 new-id presence + 5 trio greps +
hygiene + no-phantom + removed-13), and 11 from pre-existing files that the
frozen-table growth turns red by design: `test_config_parity`
model-id-sets/echo-shape/CR5-display ×8, `test_new_roster` roster-exactness
×2, `test_config_schema` families-composition audit ×1 — all clear when
C03/C04 land the rungs (AC3 "roster/schema approved-ID tables").

GREEN (preservation, must stay green): pre-cf-86 profile deep-equality (C01/
C02/C06), serve-path keyless (C01/C02/C06), inner-config strip list, profile/
arena agreement, peers-wave law at the current two-arena state, matrix no-co-
load laws, chart-default family-off, gpu echo macro-free, no-preload and no-
models-layer arms, catalog card-ask greps (27B Q4/Q6, flash-next Q4 at
262144 — already served today), provider-settings stability, the Q6-default
absence guard and the ornith Shape-B absence arm.

ARMED evidence (run by this session, not in the default suite):
`RUN_HF_CHECK=1 pytest test_heretic_rungs_flashnext.py::test_c03_hf_pack_
resolves_live` → passed (both cf-86 refs resolve through the loader mirror:
`spiritfather/Qwen3.8-Flash-Next-heretic-2-GGUF:Q4_K_M`,
`0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF:Q4_K_M-mtp`);
`RUN_HF_CHECK=1 pytest test_hf_liveness.py` → passed (no existing ref moved).

### 9.4 Conditionals NOT executed

* C05's Q4-default routing flip (U6): no user approval recorded, so the arm
  is a non-asserted conditional (§5.5 lineage). Its executable half is the
  absence guard: the pipeline-models combination bullet and the gpu-ai
  favorites row must still route to `gpu-ai/qwen3.8-flash-next-strata`. If
  the user rules the flip in, the re-pin of `tests/pipeline-models/surface.sh`
  + `tests/agent-board-coord/rulesync-surface.sh` + `rulesync generate` is a
  test-session step — those two scripts were not touched or run by this
  session.
* C06's UD-IQ4_XS fallback (conv 32768 / 108Gi / 102400) is deliberately NOT
  a second passing shape: it triggers only from the on-target HIP session
  save/restore gate, and the revert is a test-session re-pin with the
  DECISIONS citation.
* On-target human gates stay out of the suite (never agent commands): the
  `strata serve --plan` PLE-mmap confirmation, the models-PVC capacity spot
  check, the first HIP save/restore round-trip, and the `--pack`/native path
  existence on the claim.

### 9.5 Trace: acceptance criteria -> tests

* C01-2/-3/-4/-5/-6 -> `test_strata_abliterated_rung.py` (entry/matrix,
  profile+envelope, strip list, keyless, peers wave) +
  `evidence/strata-peers-expected.yaml` states.
* C02-2/-3/-4/-5/-6 -> `test_strata_orca_rung.py` (arena/alias/matrix/
  profiles, token placement both directions, pack-step invariants, peers).
* C03-1/-2/-3/-4 -> `test_heretic_rungs_flashnext.py` (id/legs/-hf/MTP,
  fnher-solo-only, mmap co-load law, gpu echo + chart-default off); C03-5 ->
  the armed liveness arm.
* C04-1/-2/-3/-4 -> `test_heretic_rungs_27b.py` (id/regime-difference proof/
  -hf/embedded MTP/ttl, q38her-main-only + dense co-load law, no preload or
  models-layer entry, gpu echo, rana escape hatch intact).
* C05-1/-2/-3/-5 -> `test_catalog_contract.py` (presence+shape, no-phantom +
  removed-13, card-ask greps, trio grep + provider stability); C05-4 ->
  §9.4 conditional guard.
* C06-1/-2/-3/-4/-5/-6 -> `test_strata_q4_rung.py` (arena + five-way
  alternation, FINAL pins + negative pins, lockstep + grace + requests, init
  token/dir/no-new-secret, peers five-id) + `test_catalog_contract.py`
  (q4 entry via the C05 presence list, no-phantom, ornith absence-arm).

### 9.6 Coord-ordered validation repair (C01 dev round 1, 2026-10-30)

C01 dev round 1 returned NEEDS_INFO(validation_at_fault): the implementation
was complete and render-verified, two §9 arms were author-side faults. Both
verified against the pinned-checkout vocabulary before editing — mechanical
(ACs and intent unchanged), so the test session repaired them rather than
re-opening the chunk.

Faults + resolutions:

* `arenas = set(S.INNER_MATRIX_VARS)` collects the matrix LETTERS while
  `strata_testlib.matrix_expansions` returns combos of resolved MODEL IDs →
  the no-co-load arm was vacuous and the reachability arm unsatisfiable for
  any render. Fixed to `set(S.INNER_MATRIX_VARS.values())` in
  `test_strata_abliterated_rung.py`, and in the latent twins
  `test_strata_orca_rung.py` / `test_strata_q4_rung.py` (those files were red
  for other reasons, so the fault was invisible until C02/C06).
* `--tokenizer` is not an engine arg. The run-config vocabulary
  (setup.py@v0.2.7 `SETUP_KEYS`) and both serving profiles spell `tokenizer`
  as a TOP-LEVEL profile key beside `args`, resolving to the tokenizer
  DIRECTORY inside each pack. Re-expressed in C01 + the C02 twin as: the
  profile-level `tokenizer` exists, is under `/models/strata/Strata-data/`,
  appears in NO engine arg, and differs from the IQ3_S primary's — same
  resolution law, now pinned on the right surface.
* Proactive same-class latent fix (no dev round needed yet): the inner alias
  surface is the profile's `aliases` LIST (the shipped primary/strix pair both
  declare the family alias `qwen3.8-flash-next`; there is no `swappabel_alias`
  key in this chart). `test_c02_inner_alias_unique_and_not_the_outer_orca_id`
  now reads model-level and profile-level `aliases` and pins per-key
  uniqueness of the FROZEN alias (one route key → one arena) plus the ≠
  outer-`…-orca-q6` law; global alias uniqueness is NOT the shipped shape and
  was never the chunk's intent.
* Coverage gaps closed in the same pass (additive, AC-backed):
  `test_c01_inner_alias_is_frozen_and_does_not_shadow_the_family` pins the
  frozen alias `qwen3.8-flash-next-abliterated` present on the new arena and
  `qwen3.8-flash-next` NOT claimed by it (chunk C01 task 2 — the two serving
  arenas already share that key);
  `test_c01_init_env_stages_the_abliterated_set` pins AC6's other half — the
  model-fetch init renders `STRATA_QUANTS` carrying `abl` and a non-empty
  `STRATA_MODEL_ABL`, both as literal scalars (no `valueFrom`), so an arena
  that routes but never stages its pack cannot pass C01.

Post-repair posture (helm on PATH, gates off, dev's C01 implementation in the
tree UNCOMMITTED): `python3 -m pytest charts/llama-swap/tests -q` → **52
failed, 283 passed, 3 skipped** (was 59/274/3). `test_strata_abliterated_rung.py`
is fully green (14 passed, including the two new arms) and exactly the 7 C01
reds §9.3 listed are gone; the residual 52 are the §9.3 designed pendings
unchanged — C02 8, C03 6, C04 7, C05 13, C06 7 = 41 new-file reds, plus the
11 frozen-table-growth reds (`test_config_parity` ×8, `test_new_roster` ×2,
`test_config_schema` ×1) that clear when C03/C04 land the rungs. No
previously green test moved (test total 336 → 338 = the two added arms; skips
unchanged at 3); the repaired C02/C06 reds now fail with their designed
"chunk not landed" messages instead of harness-shaped ones;
`RUN_HF_CHECK=1` arms still pass; `npx aislop ci --changes` clean
(0 errors / 0 warnings).

### 9.7 C02 test round — pack-script arms (C01 review deferral, 2026-10-30)

C01 reached APPROVED (r2, f0b29ccc7) with one deferred item: no suite arm pinned
the manual-pack script's invariants — downloader mechanism, byte pins, marker
ordering. C02 stages its 85.20 GB gated pack through that same init and the same
downloader, so a regression there is C02 acceptance. Six additive arms landed in
`test_strata_orca_rung.py`; no existing arm was touched.

Pinned literals, read 2026-10-30 with no credential in the request:

| object | bytes | source |
| --- | --- | --- |
| SC117 …-abliterated IQ3_XXS shard 1 / 2 | 47342144896 / 28800138432 | `/api/models/…/tree/main/IQ3_XXS` → 200 |
| orcarouter …-Uncensored IQ3_XXS shard 1 / 2 | 44637691008 / 40564977024 | `/api/models/…/tree/main` → 200 (sum 85202668032 = RESEARCH [S23]'s 85.20 GB) |

Measured with the same anonymous requests: the orcarouter **tree metadata** is
public, while `resolve/main` on the shard answers **401 + `WWW-Authenticate:
Bearer`** (repo `gated: "auto"`) — that is the fact AC3's download-only token
rests on, and SC117's equivalent answers 206 with a Range header (why C01 stays
keyless). C02 dev: the gate is on the bytes, not the listing.

New arms (`test_strata_orca_rung.py`, law → posture before C02 dev):

* `test_c02_downloader_reuses_the_venv_urllib_path_not_a_shell_client` — no
  `curl`/`wget`/`aria2c`/`axel` invocation on any executable script line (the
  rationale comments name curl to forbid it, hence the comment-stripped scan),
  and the fetch stays `$SRC/.venv/bin/python` + stdlib `urllib.request` — the
  mechanism C01 review finding 1 forced. GREEN today.
* `test_c02_abliterated_stage_keeps_the_byte_pins_the_orca_stage_copies` — both
  SC117 literals present and every `resolve/main` invocation carries a ≥8-digit
  byte pin. GREEN today; it is the shape C02 must copy, so dropping a pin is
  caught even if only the C01 half is edited.
* `test_c02_reuse_source_marks_the_pack_only_after_it_builds` — C01's
  `.setup-$TOK` marker sits behind a `-f` skip guard and is `touch`ed only after
  `abl_pack` returns (variable name derived from the assignment, so a rename
  cannot false-fail it). GREEN today; it pins the pattern C02 copies.
* `test_c02_orca_stage_pins_the_orcarouter_byte_sizes` — the init names
  `orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF` and pins both IQ3_XXS sizes on
  the invocation lines. RED until C02 lands (designed pending).
* `test_c02_orca_marker_is_touched_only_after_the_pack_completes` — the chunk's
  `/models/strata/.pack-orca` marker (or a variable assigned to it) needs a `-f`
  skip guard, a `touch`, and the touch must follow the byte-pinned downloads in
  script order — a marker written early would make a partial 85 GB pack
  permanent. RED until C02 lands.
* `test_c02_pack_pins_still_match_the_live_hf_trees` (`RUN_HF_CHECK=1`, skipped
  by default) — re-reads both trees anonymously and asserts the literals still
  match, plus the 401-on-`resolve/main` gating fact. It deliberately never reads
  `HF_TOKEN`: an arm that sent the token could not tell a public repo from a
  gated one.

Also repaired in this pass (author fault, §9.6 class): `test_c02_peers_carries_
the_orca_arena_once` did `docs, _raw = _service_docs()`, but the local wrapper
already indexes `[0]`, so the arm died on `ValueError: too many values to
unpack` and was counted among C02's designed reds for the wrong reason. Now
`docs = _service_docs()`; it fails with its designed "C02 not landed" message.
No other file carries that mistake (grep over the suite).

Deliberately NOT pinned: C01's two r2 nits — read the declared total
(`Content-Range`/`Content-Length`) and exit before re-downloading on a pin
mismatch, and size-check the `[ -s … ]` skip arm. Both are laws over
already-APPROVED C01 code; pinning them now would put an approved chunk in the
red and reopen it. If coord wants them, they are a C01-scoped follow-up change
that C02's reuse benefits from — not C02 acceptance.

Post-repair posture (helm on PATH, gates off): `python3 -m pytest
charts/llama-swap/tests -q` → **54 failed, 286 passed, 4 skipped** (was
52/283/3; 338 → 344 collected = the six new arms). `test_strata_orca_rung.py` =
10 failed / 5 passed / 1 skipped, i.e. its designed reds 8 → 10 by exactly the
two orca-specific arms; `test_strata_abliterated_rung.py` still 14/14; every
other file's red count is unchanged (catalog 13, parity 8, q4 7, heretic-27B 7,
heretic-fn 6, new_roster 2, schema 1). Skips 3 → 4 = the new `RUN_HF_CHECK`
arm. Armed pass: `RUN_HF_CHECK=1 pytest test_strata_orca_rung.py::
test_c02_pack_pins_still_match_the_live_hf_trees test_hf_liveness.py …
test_c03_hf_pack_resolves_live` → 3 passed. `npx aislop ci --changes` clean.

### 9.8 C03 test-repair round — four routed arms + the OFF-fixture cadence (2026-10-30)

C03 dev round 1 cleared its 6 designed reds (44/296/4 → 42/298/4) and routed
four previously-green arms back as authorship faults. All four verified against
primary sources first; all four MECHANICAL — no AC in `chunks/C03.md` weakened,
re-expressed or dropped, so the test session repaired them rather than
re-opening the chunk. Dev touched no test file.

Adjudication (claim → verification → ruling):

1. `test_c03_chart_default_render_has_no_heretic_rung` — UNSATISFIABLE as
   written, confirmed from the chart's own established law: CR1.4/P5 renders
   EVERY catalog id in EVERY render as the id-prefixed fail-fast echo
   (`test_boot_safety.py` documents the bare render as entirely echo entries,
   and this file's gpu-echo positive arm requires echo existence). Absence is
   not the chart's mechanism for "not enabled". Re-expressed as
   `test_c03_chart_default_render_keeps_the_rung_echo_only`: entry present,
   `is_echo_cmd`, id-prefixed, macro- and flag-free. Same intent (no servable
   process chart-side), executable shape.
2. `test_c03_ac2_matrix_hooks_scalars_identical` — real author fault:
   `_cf77_peers_carved` demanded `others == {models, macros, peers}`, so the
   sanctioned cf-86 `matrix` key disabled the peers carve-out and guaranteed
   red for ANY sanctioned matrix growth. Fix: `matrix` joins the carve only
   while `_cf86_matrix_violations(base, cur) == []`, so the peers wave and the
   matrix wave stay ONE change and any matrix edit outside the pinned additive
   shape still refuses the carve and goes red together with it. Negative cases
   verified live: wrong letter value, unpinned letter, rewritten `sets` — all
   three still refuse the carve and name the violation.
3. `test_c03_ac3_gpu_render_preserved` — same class, gpu side. Verified diff is
   exactly `matrix.vars` + `fnher` with every set expansion identical. New
   shared helper `llama_swap_testlib.cf86_matrix_growth_violations` confines the
   allowance: existing vars byte-equal, additions only the pinned
   `CF86_MATRIX_VARS` letters at their pinned ids, and every set's DNF
   EXPANSION unchanged (expansions, not expressions — helm re-wrapping cannot
   hide a pairing change). The gpu set expressions never grow: only the gpu-ai
   overlay puts a new letter into a set, so co-residency must not move
   anywhere else.
4. `test_c01_off_render_byte_identical_to_baseline` — legit catalog growth, and
   the sanctioned PROVENANCE route (test-session re-capture) taken. Because
   C04 grows the default render again, the file now splits the gate: the new
   chunk-independent structural arm
   `test_c01_off_render_changed_only_by_sanctioned_catalog_growth` pins what may
   move — object set identical, every non-config object byte-identical, config
   identical outside `models`/`matrix`, gained ids ⊆ `CF86_NEW_IDS` arriving as
   id-prefixed echoes, existing entries frozen, matrix confined by the same
   helper — and the byte arm stays pinned to the fixture. **Cadence (authorship
   call, recorded in PROVENANCE.md):** the test session re-captures the fixture
   in the LANDING chunk's test round, and only while the structural arm is
   green; red there means dev changed the default-OFF render and re-capturing
   would bake the leak into the baseline. Era chain 1 `451c149ad…` (run-2 base)
   → era 2 `0aa2241c2c…` (C03), delta verified before re-capture: models gained
   exactly `qwen3.8-flash-next-heretic-q4` as an echo, `matrix.vars` gained
   exactly `fnher`, nothing else moved (double-capture diff clean, 6 kinds, zero
   "strata" strings).

New arms (additive):

* `test_c03_hf_pack_bytes_still_match_the_source_gate` (`RUN_HF_CHECK=1`) —
   answers the C03 friction that the source gate's byte evidence was recorded
   but not pinned. Anonymous tree reads only (no `Authorization` header on
   purpose: an ungated pack's evidence must stay re-checkable without a token):
   `Q4_K_M` trunk a complete 1..5 shard set at 10945472 / 682434912 /
   54400261312 / 47643214976 / 37673027808 (sum 140409884480 = the gate's
   130.8 GiB) and `mtp/mtp-…-Q8_0.gguf` at 4137429280. Re-upload or
   re-organization goes red instead of silently changing what the node pulls.
* `test_c02_orca_profile_serves_exactly_the_staged_paths` — the C02 review
   path-pairing deferral. Derives `dir`/`pack`/`stem`/`s1`/`s2` from the
   rendered `orca_pack` body and the tier from the rendered
   `STRATA_MODEL_ORCA`, then requires the arena's `--pack`, `--native`,
   `--ple-gguf` and `tokenizer` to be exactly those staged paths (this pack's
   PLE table rides in shard 1 per ORCA.md, so `--native == --ple-gguf == s1`),
   and that both shard halves are actually `orca_dl` destinations with a byte
   pin in `ORCA_SHARD_BYTES`. Derived on both sides, so a rename on one side
   goes red instead of a literal drifting with it.
* C04-era message class (deferred §9.6 item): the 5 bare-`KeyError` arms in
   `test_heretic_rungs_27b.py` (via a new `_model()` guard) and the 4 in
   `test_config_parity.py` (`test_cr5_display_presence`,
   `test_cr5_display_name_grammar` now assert absent ids "— awaiting CA2/CA3")
   fail with their designed message. A count-only residual map cannot tell a
   KeyError arm from suite breakage — the C02 round showed that costs a dev
   round to untangle.

Recorded, NOT asserted: the `-hf` loader hazard. `Q4_K_M/MTP/` holds only
shards 1+6-of-6 and spells them uppercase `-MTP-`, which defeats hf_check's
case-sensitive `-mtp-` skip and sorts ahead of the trunk, so llama.cpp's
`find_best_model` first-hit (case-insensitive `Q4_K_M[.-]`) would pick an
incomplete 2/6 set. It is a live-loader behavior question (MTP also needs
unmerged llama.cpp PR #27836), outside AC5's "resolves" wording — filed for
coord, asserted nowhere.

Posture (helm on PATH, gates off, C03 implementation UNCOMMITTED in the tree):
`python3 -m pytest charts/llama-swap/tests -q` → **38 failed, 304 passed,
5 skipped** (was 42/298/4; 344 → 347 collected = the two new always-on/gated
arms plus the orca pairing arm). Exactly the four routed arms moved red→green;
the counts differ from the coord's quoted 38/302/4 only by the added arms.
Fully green: `test_heretic_rungs_flashnext.py` 9+2sk (11 armed),
`test_flashnext_blast_radius.py` 5/5, `test_strata_off_parity.py` 3/3,
`test_strata_orca_rung.py` 16+1sk. Residual 38, all designed pendings, every
message read: C04 7 (`test_heretic_rungs_27b`), C04-era frozen-table growth 11
(`test_config_parity` 8, `test_new_roster` 2, `test_config_schema` 1), C05 13
(`test_catalog_contract`), C06 7 (`test_strata_q4_rung`). Armed pass
`RUN_HF_CHECK=1 pytest test_heretic_rungs_flashnext.py test_strata_orca_rung.py
test_hf_liveness.py` → 29 passed, 0 skipped. `npx --yes aislop@latest ci
--changes` clean.

### 9.9 C04 test round — source gate, loader-pick guard, C04-era matrix law (2026-10-30)

Run before C04 dev starts; covers STATE deferred[0] items (a)–(d). No existing
arm weakened.

**(a) C04 source gate re-verified live, no re-pin needed.** Anonymous recursive
tree read of `0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF`
(`gated: False`, 182 files): the ladder is FLAT and SINGLE-FILE, MTP embedded in
the file name — `RVN-Q4_K_M-mtp.gguf` **16,998,720,736 B** (exactly the number
recorded in `CF86_HF_REFS`' comment and RESEARCH [S22]), so the ref
`…:Q4_K_M-mtp` is correct and C04 needs no `draft:` sidecar and no split-family
exposure. Two neighbours are pinned alongside it because they are what makes the
suffix load-bearing: `RVN-Q4_K_M.gguf` = 16,547,399,968 B and
`Qwen3.8-27B-Heretic-Q4_K_M.gguf` = 16,547,400,032 B — a suffix-less ref does not
resolve to a slightly different build, it resolves to a *different file*. New
arm: `test_c04_hf_pack_bytes_still_match_the_source_gate` (`RUN_HF_CHECK=1`).

**(c) Loader-ordering churn guard, with the C03 finding as its provenance.**
`find_best_model`/`get_gguf_split_info`/`get_split_files` read from
`common/download.cpp@889edf43`: the sidecar filter is a **case-sensitive** name
test (`mmproj`, `imatrix`, `mtp-`, `eagle3-`, `dflash-`, `dspark-`), the QUANT
search is **case-insensitive over the full path** (a directory name can satisfy
it), only shard 1 of a split family is ever picked, and `get_split_files`
collects whatever shards exist **without checking the declared count**.
`llama_swap_testlib.hf_tree/hf_split_info/hf_is_model_file/hf_pick/hf_split_family`
mirror that faithfully; `test_c04_hf_pick_resolves_to_a_complete_file_set`
(`RUN_HF_CHECK=1`) runs the pick for every cf-86 ref:

* `qwen38-heretic` → `RVN-Q4_K_M-mtp.gguf`, single file, complete ✓ (this is the
  arm that, run against spiritfather at C03 authoring time, would have caught
  the hazard).
* `qwen3.8-flash-next-heretic-q4` → `Q4_K_M/MTP/…-MTP-00001-of-00006.gguf`,
  family = shards **1+6 of 6** — the C03 hazard, reproduced live and pinned as
  the known-broken shape (`C03_PACK_PICK`: exact pick path + exact family +
  declared count). Upstream fixing or re-shuffling that tree turns the arm red
  and re-pins through the test session, which is also the signal that coord can
  retire the C03 runbook note. The C03 file's hazard comment now points here
  instead of saying "needs verification".

Probes: helper faithfulness (split parsing, `mtp-` skip vs uppercase `-MTP-`
non-skip, shard-1-only pick), and the arm's non-vacuity — mutating the pinned
family, or pointing `qwen38-heretic`'s ref at the heretic-2 repo, both go red
with named messages.

**(b) `test_strata_off_parity` NameError repaired.** The §9.8 structural arm's
ConfigMap-metadata assertion referenced the deleted local `target`, so that
failure path raised `NameError` instead of the designed message. Now
`the {name} ConfigMap metadata diverged` (verified by mutating a copied fixture:
designed AssertionError). Suite-wide re-scan for the same class: symtable walk
over all 29 files flagging global lookups absent from the module namespace and
builtins → only `__file__`/`__conditional_annotations__` (runtime/compiler
dunders). Detector non-vacuity proven by re-injecting `{target}` into a scratch
copy: reported at the exact function and line.

**(d) C04-era matrix law corrected — the §9.8 version would have blocked C04.**
`cf86_matrix_growth_violations` forbade ALL combo change and asserted "only the
gpu-ai service overlay may put a letter into a set". False for C04: `q38her`
joins the **chart-level** `sets.main` (chunk task 3), which the gpu box and
every default-OFF render ride, so a sanctioned C04 render would have gone red
there and in `test_c03_ac3_gpu_render_preserved` — a false red costing a dev
round. Confined replacement, driven by `CF86_SET_ADDITIONS`
(`solo` ← fnher, `main` ← q38her):

* no baseline combo may disappear;
* a set may only gain letters its `CF86_SET_ADDITIONS` entry names;
* each gained combo must contain exactly one cf-86 id, and it must be one that
  this set is allowed to gain;
* the gained combo must be a baseline combo with exactly one member swapped for
  that id — the new rung takes an existing alternation slot and never opens a
  new co-residency class.

Probes (in-memory on the parsed OFF config): sanctioned C04 delta → clean;
`fnher` into chart main → named refusal; unpinned letter → refusal; pinned
letter with the wrong id → refusal; baseline combo dropped → refusal; `q38her`
gaining a `vl2bq4` partner → refusal.gpu-ai's own
`_cf86_matrix_violations` keeps its looser "new combo must pair a cf-86 rung"
rule: it guards the overlay's surface, it is green, and tightening it now is
churn, not a repair — the asymmetry is deliberate.

Cadence through C04 (for review): **no fixture re-capture before C04 lands** —
the structural arm is green today and must still be green immediately after the
C04 commit; the byte arm going red at that commit is expected and is the trigger
for the test-session re-capture, never for a dev edit. Expected C04-era delta of
the default-OFF render, and nothing else: `models` +`qwen38-heretic` as an
id-prefixed fail-fast echo (~17 lines), `matrix.vars` +`q38her: qwen38-heretic`
(1 line), `matrix.sets.main` expression +`| q38her` (same line, expansions gain
only `{qwen38-heretic, home-3b-v3}`-shaped pairs). The structural arm cannot be
exercised end-to-end before the chart edit exists (it renders the chart itself),
so the law was verified at helper level by simulation; the arm runs for real in
C04's round. Goldens: `tests/golden/{gpu,gpu-ai}.config.yaml` stay
byte-untouched — the approved-ID arms derive `golden-union − REMOVED_IDS +
CF86_NEW_IDS` (`test_config_parity::test_c02_1`) and the blast-radius arms allow
gained ids ⊆ `CF86_NEW_IDS`, so C04 requires no golden re-pin under this
lineage (chunk AC4's "goldens re-pinned" wording is flagged to coord).

Authorship-internal dedup (no assertion changed): the §9.8 C03 byte arm fetched
its own HF listing; it now calls `llama_swap_testlib.hf_tree`, so every cf-86
evidence arm reads the same listing the pick guard reasons about. Re-ran that arm
unarmed (skip), armed (pass) and negative (mutation still red).

Posture (helm on PATH, gates off, C04 not yet landed): `python3 -m pytest
charts/llama-swap/tests -q` → **38 failed, 304 passed, 7 skipped** — identical
failure set to §9.8 (C04 7 + frozen-table 11 + C05 13 + C06 7, every message
read), skips +2 = the two new `RUN_HF_CHECK` arms. Armed: `RUN_HF_CHECK=1
test_heretic_rungs_flashnext.py test_strata_orca_rung.py test_hf_liveness.py` →
29 passed; the two C04 evidence arms → 2 passed. `npx --yes aislop@latest ci
--changes` clean.

### 9.10 C04 test-repair round — census-key fault class + era-3 OFF re-capture (2026-10-30)

C04 dev round 1 cleared 17 reds (38/304/7 → 22/320/7, implementation complete
and uncommitted) and routed one validation fault back. Verified against the
landed render before editing; ruling MECHANICAL — the AC2 law and its intent are
unchanged, only the census discriminator was wrong.

**Fault 1 — `test_c04_never_two_dense_rungs_in_one_combo` census.** The arm
classed dense rungs by `-np 1`, which `${q36-common}` also injects, so
`qwen36-heretic`/`qwen36-huihui` (MoE: `-ngl 99` + `-ot "\.ffn_.*_exps\.=CPU"`)
joined the dense census and the law became unsatisfiable: 18 sanctioned
dense×q36 co-loads exist on the landed render (16 on HEAD, legal since
2026-10-18). Re-keyed on `-ngl 999`, the leg AC2 names: census = 12 ids, exactly
the `qwen38` dense family, `qwen38-heretic` included, MoE overlap empty, 0
clashes across all 165 combos. `NEW_ID ∈ dense_ids` and the ≤1-dense-per-combo
law are kept, and the arm now refuses to pass vacuously (census non-empty,
combos present, at least one combo actually containing a dense rung) — the
green side had never been exercised at authoring because the `NEW_ID` guard
aborted first.

**Fault class named, second instance.** *Domain-mismatched census* — instance 1
is §9.6's `arenas = set(INNER_MATRIX_VARS)` (matrix LETTERS collected where the
DNF parser yields model IDs: one arm vacuous, its twin unsatisfiable); instance
2 is this macro-shared flag. Its enabling class, the *early-abort guard that
masks the green side* (§9.8 FRICTION), recurs here too: an arm that stops at a
"chunk not landed" assert never runs the loop whose unsatisfiability would have
exposed the census fault while the file was still unwritten.

Discipline this implies, and the guard that now enforces it —
`test_c04_regime_censuses_are_mutually_exclusive`: a census key must (a) belong
to one regime family only — check the rendered `macros` map, where `-np 1` is in
BOTH `q36-common` and `q38-common` while `-ngl 999` is only in `q38-common`;
(b) be substring-safe against longer values (`-ngl 99` is a prefix of `-ngl 999`
and must never be a census key; `-ngl 999` is the longest `-ngl` value and also
catches the raw-cmd hatch `qwen38-rana`, which token-exact matching via
`cmd_flag_value` would miss); (c) be paired, in the same file, with a
mutual-exclusion assert over the two regimes so the misclassification goes red at
the census, not as an unsatisfiable law elsewhere; (d) sit in an arm that asserts
its own non-vacuity. Suite sweep for other censuses
(`grep 'in L.effective_cmd'` → 3 sites): the C03 file's `--fit off` census is
clean (that leg appears in no macro).

Probes: injecting a real `qwen38-heretic × qwen3.8-27b-q4` combo → named clash;
reverting the key to `-np 1` → the law goes red AND the new guard catches it
("the census keys are not regime-exclusive").

**Era-3 OFF re-capture (authorized by the §9.9 cadence).** Structural arm green
on the landed render (dev verified, re-verified here), so the byte fixture moved.
Delta verified before capture and again line-by-line at capture: models gained
exactly `qwen38-heretic` as an id-prefixed echo (15 lines), `matrix.vars` gained
exactly `q38her: qwen38-heretic`, `matrix.sets.main` gained exactly the `q38her`
alternative — one gained pair `{qwen38-heretic, home-3b-v3}`, a baseline pair
with one member swapped; every other object, entry and key byte-identical,
double-capture deterministic, 6 kinds, zero "strata" strings. Capture artifact
worth knowing when reading the diff: the `main` line shows 5 lines removed / 5
added because the inserted token moved helm's YAML fold — the expression string
differs only by `| q38her` (string-compare and expansion-compare both confirm).
Era chain: `451c149ad…` → `0aa2241c2…` → `dba1c075d2582b7512b073461d95c85b2d0f66ab0867d43a048f0037737e045f`.
C06 adds no llama.cpp catalog id, so era 3 should be this ticket's last
catalog-driven move.

Posture (helm on PATH, gates off, C04 implementation uncommitted in the tree):
`python3 -m pytest charts/llama-swap/tests -q` → **20 failed, 323 passed,
7 skipped**. The residual is exactly the two pending chunks — `test_catalog_contract`
13 (C05) + `test_strata_q4_rung` 7 (C06), every message read; parity 34/34,
roster 30/30, schema 22/22, blast-radius 5/5, off-parity 3/3, heretic-27B
10 passed + 2 gated skips. Armed: `RUN_HF_CHECK=1` across the four HF-bearing
files → 41 passed / 0 skipped; `RUN_FLAG_AUDIT=1 test_flashnext_regime.py` → 23
passed. Passed count is 323, not the projected 322, because of the one new guard
arm. `npx --yes aislop@latest ci --changes` clean (0 errors / 0 warnings); the
undefined-global symtable scan re-run over 29 files → dunder hits only.

### 9.11 Same round, second repair — C05 trio-scope (found by test-side sweep, not by dev)

While reading the C05 residual messages, the trio arm was found over-scoped at
authoring: `test_c05_trio_grep_three_surfaces` was parametrized over
`CF86_NEW_CATALOG_IDS` (5), but the plan Commands line and chunk C05 AC5 both
scope the trio grep to the NEW **Strata** ids (chart `strata.config.models` +
service `peers.strata.models` + catalog). The two llama.cpp family ids have no
service surface BY DESIGN — the gpu-ai overlay enables families, carrying matrix
letters (`q38her`) rather than ids; chunk C05 FORBIDS `services/**`, and C04's
own AC1 arm bans a models-layer entry for `qwen38-heretic` there. Left as
written, C05 dev would have been forced to violate C04 to go green — a third
instance of the unsatisfiable-law class (§9.6 letter-vs-ID census, §9.10
macro-shared census key; this one is scope, not membership, and it was latent:
the two params were red at the catalog assert, so the unsatisfiable service
assert had never been reached).

Repair: `CF86_TRIO_IDS` (3 Strata ids) drives the trio arm; registration for all
five ids stays AC1's job (`test_c05_new_ids_registered` already parametrizes the
full 5-id list, so no coverage is lost), and the family ids' live-serve side is
pinned by the C03/C04 gpu- render arms. New guard
`test_c05_trio_scope_is_strata_ids_only` pins the split — moving an id between
the lists now requires a law amendment. Probe: appending `qwen38-heretic` to the
trio list → guard red ("trio scope moved").

Posture after the repair: **18 failed, 324 passed, 7 skipped** — residual
exactly C05 11 (5 registration + hygiene + phantom + removed-return + 3 trio,
every message read; trio arms red at the catalog/chart assert = correct
pre-dev posture) + C06 7. Earlier §9.10 counts (20/323) include the 2 unsatisfiable
trio params and predate the +1 guard arm: 20−2=18, 323−2+1=324.

### 9.12 C06 test round — keys-vs-values (class instance 3), the per-arena pairing selector, and the scope-guard widening (2026-10-30)

C06 dev round 1 landed the implementation (4 files) and routed two reds as
validation faults. Both verified against the landed render before editing; both
MECHANICAL — the AC and its intent survive, only the validation expression was
wrong. Off-parity 3/3 green on the C06 render: no era-4 OFF re-capture is owed
(the q4 arena is a Strata inner arena; CR1.4/P5 echoes llama.cpp catalog ids
only, and the OFF byte arm proves the render did not move).

**Repair 1 — `test_c06_negative_pins_absent_from_the_q4_arm` (keys vs values).**
The arm asked `S.Q4_SLOT_SAVE_PATH in dict(S.arg_pairs(_profile()))`:
`arg_pairs` yields `(flag, value)` pairs, so the dict's KEYS are flags, and a
path value can never be a member — the arm was unsatisfiable for any correct
profile (`--slot-save-path /models/strata/sessions` renders exactly as pinned).
Repaired to assert the pair itself (`pairs.get("--slot-save-path") ==
Q4_SLOT_SAVE_PATH`) and added the self-non-vacuity assert the arm lacked
(`tokens` non-empty, else every negative pin in it passes on an empty profile).
Census-class instance 3: instance 1 §9.6 (matrix letters collected where the
parser yields model ids), instance 2 §9.10 (macro-shared flag as census key),
instance 3 this one (value tested for membership in a key set). All three are
the same underlying slip — a collection read at the wrong side of a pair — and
all three were invisible at authoring because an earlier guard aborted first.
Probes: session path removed from the profile → red naming the value; the old
keys-form re-tested on the landed render → still False.

**Repair 2 — `test_c01_memory_cgroup_and_engine_cap` (per-arena pairing).**
The pairing table read the engine cap from `PROFILE_PRIMARY_FILE`
unconditionally, so once the sanctioned cgroup pair moved to 100Gi it demanded
the IQ3_S arena grow to 95232 — contradicted by the per-pair law in
`test_c06_existing_profiles_stay_byte_unchanged_iq3_s_keeps_92160` and by the
byte-frozen pre-cf-86 capture of `strata-iq3_s.json`. Three arms, mutually
unsatisfiable under C06's five-arena shape. Repaired by keying the pair leg on
the cgroup: the profile that must equal the pair value is the arena the cgroup
was sized for (`PROFILE_Q4_FILE` under 100Gi, `PROFILE_PRIMARY_FILE` under
96Gi), and the law's real subject — containment — is now asserted directly for
every cap the render states (`cap <= cgroup MiB`).
Scope of the containment law matters: a universal "every profile must state a
cap" version of the intent would have been its own unsatisfiable arm — the
strix run shape states `--expert-cache`/`--resident-budget-gib` instead of
`--memory-limit-mib`, and its file is byte-frozen by the pre-cf-86 capture, so
adding a cap there is not this ticket's call. Probes: 96Gi + IQ3_S 92160 shape
still legal (selector covers both pair shapes); q4 cap forced to 92160 under
100Gi → "lockstep broken"; an IQ3_XXS cap of 103000 under 100Gi → containment
red; IQ3_S byte-pin vs the pre-cf-86 capture → green (92160 unmoved).

**Additive arms written this round (no AC changed).**
`test_c06_pack_profile_carries_no_ple_gguf_line` — setup.py@v0.2.7 emits
`--ple-gguf` only for ≤2-shard packs; the unsloth family has four shards, so a
hand-written sidecar would be wrong weights. Probe: injected sidecar → red.
`test_c06_q4_shard_family_is_the_four_shard_pack_it_stages_from`
(RUN_HF_CHECK) — no such arm existed: the q4 file had no live-HF coverage, so
the pack source was unpinned while the C03/C04 llama.cpp packs are pinned. It
reads the live HF tree with no credential (the anonymous listing IS the evidence
behind AC4's "no new secret material") and pins the four shard names+bytes, the
total, a complete 4-of-4 pick under the mirrored loader rule, and that the
profile's `--native` is that primary shard. Probes: shard 4 removed → red; one
shard's bytes shifted → red.

**Byte-total discrepancy (dev handoff vs live tree).** Dev's round-1 ledger
reports "Live tree: exactly 4 files, 111,334,256,784 B == setup pins
byte-identical". The live tree read here gives per-shard sizes
10,946,624 / 49,859,583,136 / 49,376,141,504 / 12,087,983,520 — all four match
the chart's pack comment — summing to **111,334,654,784**, i.e. 398,000 B above
the total the chart comment cites (values.yaml ~L2406). So the per-shard facts
hold and the cited SUM is a transcription slip (the 111.3 GB figure is setup's
rounded `download_gb`), not upstream churn. The suite pins the per-shard values
and the true total; the comment waits on the deferred docs round (README L41
96Gi + the host-prep note are stale for the Q4 pair too, and
`test_strata_runbook.py` pins that literal — docs and arm must move together).
Restating dev's own lesson: a baseline/live claim in a ledger carries the proof
triple (ref, tree state, verbatim numbers) or it is a citation, not a
measurement.

**Scope guards: c8 widened, and its twins were red too.** c8 admits no serving
surface at all, so any dirty chart/services tree reddened it mid-chunk, and a
range base (`CHUNK_BASE=merge-base`) reddened it on cf-86's own committed test
tree. Chosen design: **literal per-file admits** for exactly what cf-86's
chunks declare (`charts/llama-swap/values.yaml`,
`charts/llama-swap/templates/configmap-strata-profile.yaml`,
`services/gpu-ai/prod/values.yaml`, `charts/llama-swap/tests/*`) — no directory
admits — behind a `c8_admits()` function plus a **standing negative probe loop**
(`containers/strata/Dockerfile`,
`charts/llama-swap/templates/deployment.yaml`, `charts/home-assistant/values.yaml`,
`services/home/agents/prod/values.yaml`, `.github/workflows/ci.yaml` must stay
outside), so a widening cannot silently become a catch-all. **Manifest-driven
admits rejected**: the plan folder is itself admitted and rewritten mid-run, so
reading "Files in scope" would let the scoped party grow its own allow-list, and
agent-perms A9 window-greps literal admits inside the if-want block, which a
parsed loop cannot satisfy without re-pinning A9.
Same-class reds the routed item did not name, found by running the family:
`gate.sh` t14 and `agents-md.sh` c7 lack the same admits (dirty C06 tree: both
red on the cf-86 plan folder; `pipeline-gates/validation-fix.sh` t7 then fails
transitively because it runs agents-md.sh). Widened identically — plan folder +
the three serving files + the chart tests tree, literals only, gate.sh's "infra
dirs stay OUTSIDE the allow-set" sentence amended to name the exception. The
standing probe loop lives in c8 only (one copy of the machinery; t14/c7 keep
their own A9-windowed literals).
Probe evidence for all three: dirty C06 tree → rc 0 (rulesync-surface 19 ok,
gate 22 ok, agents-md 9 ok); dirty unadmitted `configmap-strata.yaml` → all
three rc 1; tampered c8 admit to `charts/**` → the probe loop itself fires
("a serving widening grew into a catch-all"); whole-ticket range
(`CHUNK_BASE=617e18488`) → all three rc 0; clean HEAD with the edited gate files
→ 19/22/9 ok and agent-perms 15 ok (A9 window-pins intact).
Environment note for anyone repeating the clean-HEAD comparison: a fresh
worktree cannot run the strata pytest suites — the `app-template` subchart
dependency is absent there and every render errors ("found in Chart.yaml, but
missing in charts/ directory"), so clean-HEAD pytest numbers are meaningless;
the gate suites do not render and do compare.

**Posture (helm on PATH; C06 implementation uncommitted in the tree).**
Per-file: q4_rung 11 passed + 1 gated skip, strata_render 25, blast-radius 5,
off-parity 3, catalog contract 18, orca 16+1, abliterated 14, heretic-27B
10+2, heretic-flashnext 9+2, config parity 34, new_roster 30, config_schema 22.
FULL plain: **343 passed, 8 skipped, 0 failed**. FULL armed
(`RUN_HF_CHECK=1 RUN_FLAG_AUDIT=1`): **351 passed, 0 failed, 0 skipped** — the
first fully-armed zero-red run of the ticket. The 2 above dev's projected 349
are the additive arms in this section, not a counting difference.
