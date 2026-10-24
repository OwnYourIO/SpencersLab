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
* C03-1 -> wiring `initcontainer_autogen_pinned_image/security/mounts`,
  `volumes_gen_emptydir_base_configmap`, `main_env_gains_only_config_dir`
* C03-2 -> wiring base.yaml 4 tests (render half) + integration
  `base_yaml_parses` (tool half; deviation §5.1)
* C03-3 -> integration `base_yaml_parses_and_empty_scan_fails_stock` (stock
  behavior, gated) + wiring `degrade_*` ×3 (script contract, hard)
* C03-4 -> wiring `declared_model_ids_are_colon_free`,
  `synthetic_scanned_half_disjoint_from_declared` (pure) + integration
  `scanned_half_generates_validates_and_is_disjoint`,
  `merged_declared_plus_scanned_validates` (gated)
* C03-5 -> wiring base.yaml forbidden/scalar keys + integration
  `declared_only_with_empty_config_dir_validates` (gated)
* C03 reload task -> wiring `reloader_annotation_covers_both_configmaps`
* C04-1 -> roster `roster_is_exactly_golden_plus_approved_table`,
  `exact_hf_ref_per_approved_id` ×16, `flashnext_mtp_draft_wired`,
  `gpu_ai_only_families_absent_from_gpu`, `flashnext_matrix_placement`,
  `orca_and_122b_solo`, `35b_ladder_matrix_membership`,
  `no_new_model_preloaded`, `big_family_ttl_300_and_ladder_ttl_0`,
  `vision_capabilities_declared`, `35b_q6_q8_gpu_tuned_regime`,
  `35b_bf16_gpu_disabled_failfast` (+ gated `hf_repo_tags_resolve`)
* C04-2 -> parity tests (old IDs unchanged) + roster exact-set test
* C04-3 -> roster `matrix_closure_after_additions` ×2 (+ parity same-named)
* C04-4 -> integration `full_roster_declared_validates` ×2 (gated)
* C04-6 -> parity + `helm_lint` (existing green suite is the CI gate)
* C01-1..4 -> image `dockerfile_exists`, `fleet_consistent_base_pin`,
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
  dedicated test. A probe over all 17 approved IDs confirmed exactly one
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