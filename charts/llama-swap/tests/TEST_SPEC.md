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
