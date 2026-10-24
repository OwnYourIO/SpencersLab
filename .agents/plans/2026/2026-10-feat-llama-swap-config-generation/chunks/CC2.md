# CC2: source removal — containers/ dir, base-CM template, helpers defines, values autogen sections
size: M   wave: 9   depends_on: [CC1] (the frozen bar is the CC1-shrunken suite; removal-first would red-light the surviving scope)

## Goal
Delete the autogen machinery from the repo, landing the chart on the DECLARED-ONLY
single-`-config` shape verified against the pre-ticket chart. The rendered declared
ConfigMap must not change by a single byte; the pod spec changes by EXACTLY the
autogen removals. Services/custom-values/CI/renovate need no edits (verified by the
CR6 sweep).

## Tasks
- [ ] Delete `containers/llama-swap-autogen/` (Dockerfile + entrypoint.sh) whole.
- [ ] Delete `charts/llama-swap/templates/configmap-autogen-base.yaml` (sole
      consumer of the autogenBase helper).
- [ ] `_helpers-llama-swap.tpl`: remove `llama-swap.autogenBase` +
      `llama-swap.firstMountPath` defines (zero-consumer grep after CC1; keep
      declaredConfig/modelCmd/deriveHf/deriveDisplay byte-identical) and REWORD the
      header comment: the v262 two-file merge rationale (identity maps, duplicate
      children, matrix-in-both-halves) is retired history — state only the CURRENT
      invariant (macros/matrix/hooks are top-level config keys; families/
      filterPresets/tagCultures are chart-values concepts, stripped). No
      history-narrating comments (comment-slop rules).
- [ ] `charts/llama-swap/values.yaml`: delete the Path-A comment block + `autogen:`
      section; delete `controllers.llama-swap.initContainers.autogen` (whole);
      delete the `LLAMA_SWAP_CONFIG_DIR: /app/gen` env entry + its comment (keep
      LLAMA_SWAP_CONFIG + LLAMA_SWAP_WATCH_CONFIG + their comment verbatim — they
      ARE the restored single-file mechanism); delete persistence `gen`,
      `autogen-base`, `autogen-home` (keep the `config` directory-mount rationale
      comment as the authoritative reload text; verify it still reads true
      standalone). If any surviving comment references the scanned half, trim that
      clause only.
- [ ] No CI edits (docker-build autodetects + guards on Dockerfile existence;
      tools-tests has no autogen steps), no renovate edits (generic git-refs
      manager), no services edits.
- [ ] Residual sweep (plan command): zero `autogen|LLAMA_SWAP_CONFIG_DIR|/app/gen|
      10-scanned` hits outside plan-folder history + TEST_SPEC/7quinquies ledger
      mentions.

## Files in scope
- containers/llama-swap-autogen/** (deleted)
- charts/llama-swap/templates/configmap-autogen-base.yaml (deleted)
- charts/llama-swap/templates/_helpers-llama-swap.tpl (defines + comment)
- charts/llama-swap/values.yaml (sections above)
- proof-only, must stay EMPTY in the diff: services/**, custom-values/**,
  charts/base/**, .github/**, renovate.json, charts/llama-swap/tests/** (CC1 owns
  that tree — CC2 touches ZERO test files)

## Acceptance criteria
1. FROZEN BAR UNCHANGED after removal: `pytest charts/llama-swap/tests -v` =>
   **0f/119p/1s** (the CC1 suite passes against the SOURCE-REMOVED chart — closes
   the invariant from both sides). Sole skip = re-homed RUN_HF_CHECK liveness gate.
2. DECLARED-CM INVARIANCE: `llama-swap-config` ConfigMap data byte-equal CC1-tip vs
   CC2 completion, all three renders (default/gpu/gpu-ai extract-and-render). The
   removal must not touch a byte of the rendered config.
3. POD-SPEC DELTA = removals only: initContainers.autogen, volumes + mounts
   gen/autogen-base/autogen-home, LLAMA_SWAP_CONFIG_DIR env line, and the
   llama-swap-autogen-base ConfigMap document vanishing; main + tools containers
   otherwise byte-identical; zero additions; volume count 6->3.
4. helm dependency update + `helm lint --strict` + three renders pass; trio/sentinel
   greps intact; goldens 0-diff; `git diff` scope = exactly the 4 paths above.
5. `RUN_HF_CHECK=1` => 1p; direct `hf_check.py` => 98/98 OK (refs untouched). No
   docker/venv evidence gates remain in the contract (user ruling) — pod boot
   on-cluster is the fleet -validate proof, recorded as a C05 runbook step.
6. aislop 0 attributable on touched trees; EOF/sentinel hygiene; no version/tag
   edits (Chart.yaml untouched — release.yaml owns bumps).

## Tests (agent-test writes, review runs)
None new — CC2 is pure removal validated by the frozen CC1 suite + the invariance/
delta bars above (review re-runs everything independently, CA2/CA4 precedent).

## Notes for dev
- Load `helm-chart-creation` + `helm-bjw-s-chart` + `llama-swap`; read TEST_SPEC
  §7quinquies first (the retirement ledger — do not re-live a retired contract
  "for safety").
- Snapshot the three renders at CC1 tip BEFORE editing (CA2 duplicate-key-class
  lesson) and re-diff after every commit.
- If any surviving test unexpectedly reds, STOP — that means CC1 missed a consumer;
  route back to the test session; dev never edits tests.
- ghcr.io/ownyourio/llama-swap-autogen stays published (registry cleanup is the
  user's; C05 runbook carries the optional-cleanup note).

## Review notes (review agent fills)

### Round 1 — commit 123f1cb55 (5 files, +6/-414) — verdict APPROVED

Bars (all re-run independently; helm v3.16.4 via /tmp/opencode/bin, system pytest):
- `pytest charts/llama-swap/tests -v` => **0 failed / 119 passed / 1 skipped** EXACT.
  Per-module recount: parity 34, schema 22, roster 30, CI-existing 33 (tools 20 +
  render 7 + lora 3 + prov 3); sole skip = `test_c04_1_hf_repo_tags_resolve`
  (RUN_HF_CHECK gate) — frozen-bar arithmetic closes against the source-removed
  chart, invariant proven from the removal side.
- helm dependency update + `helm lint --strict` => pass. Renders x3 =>
  68859/72002/77297 B (dev record byte-matched by my own runs).
- `RUN_HF_CHECK=1` alone => 1p. Direct `hf_check.py` => 98 refs OK, exit 0.
- Goldens 0-diff (worktree clean vs 49e977faf last-touch). Trio greps intact;
  the one `OVERRIDE_VIA_CUSTOM_VALUES` occurrence in the gpu-ai render is the
  hf-token ExternalSecret key, IDENTICAL in my before-render (pre-existing
  deploy-time pattern, resolved 1:1 by custom-values/gpu-ai :22 — not a CC2 leak).
- aislop 0.18.1 on charts/llama-swap: 135 warnings/2 errors all in vendored
  scripts/** (established pre-existing set) — zero attributable to the 5 touched
  files. Chart.yaml/Chart.lock: 0-line diff (release.yaml owns bumps).

Independent byte-equality (my own git-archive 0e7eafd36 renders vs HEAD):
- My before-renders reproduce the CC1-tip record exactly (71855/74998/81221 B =
  final-3 numbers) — archive provenance confirmed.
- Declared CM `llama-swap-config` data config.yaml sha256-prefix equal x3:
  4a8934101e35 / c3a8e3297c89 / 9f359249cee7 — dev's cited shas reproduced exactly.
- Pod-spec name-keyed deep diff (every leaf compared): **0 added, 0 changed**
  outside the contracted set; removed = 43/43/45 leaves, all inside it —
  initContainers.autogen whole, volumes gen/autogen-base/autogen-home,
  main mounts for gen (+ gpu-ai's tools gen-mounts from the C03 globalMounts
  spill), env LLAMA_SWAP_CONFIG_DIR. Volumes after = exactly {config, models,
  tools} x3. `llama-swap-autogen-base` CM document: present before (x3),
  vanished after (x3). Pod-template labels identical before/after.
- Pre-ticket shape SPOTTED, render-vs-render vs b2aa2e4b2: env pair
  (LLAMA_SWAP_CONFIG=/app/config/config.yaml, WATCH_CONFIG="true"), directory
  config mount at /app/config, deployment-level `reloader.stakater.com/auto:
  "true"`, zero initContainers, 3 volumes — all EQUAL to HEAD. Values-file
  proof: env-pair comment block and persistence.config rationale comment are
  BYTE-IDENTICAL to b2aa2e4b2 (the restored single-file mechanism is restored,
  not reconstructed).

Removal-surface audit vs CC2.md:
- numstat: helpers 6/119, base-CM 0/14, values 0/139, Dockerfile 0/26,
  entrypoint.sh 0/116 — ALL 6 insertions are the two helpers-header rewords;
  every other hunk is pure subtraction. Proof-only trees (services,
  custom-values, .github, renovate, charts/base, tests, Chart.yaml): EMPTY diff.
- defines: exactly autogenBase + firstMountPath removed, zero added; the 4 kept
  defines (declaredConfig/modelCmd/deriveHf/deriveDisplay) BYTE-IDENTICAL before/
  after (function-span compare). Repo-wide grep: zero residual consumers of
  either removed define outside plan-folder history.
- values parse clean; controller keys now {annotations, containers}; env now
  {TZ, LLAMA_CACHE, LLAMA_CONFIG pair} minus CONFIG_DIR; persistence exactly
  {config, models, tools}; zero `autogen|/app/gen|10-scanned|config-dir|Path A|
  halves` tokens anywhere in values/templates. configmap-autogen-base.yaml +
  containers/llama-swap-autogen/ deleted whole (git tree + disk).
- Reword truth, checked against the code (comment-slop 3-clause):
  (1) dup-ID sentence — guard confirmed `hasKey $derived` + fail; counterfactual
  (set-overwrite silently drops one entry from the chart's model map) true at
  this layer; no merge history. (2) macros/matrix/hooks sentence — strip list
  confirmed to be exactly filterPresets/tagCultures/families(+rebuilt models);
  the three keys pass through unchanged; matrix-vars-name-model-ids matches the
  pinned matrix-closure contract. Both rewords state current invariants only,
  no "we removed" narration — passes why-grade + no-history; the surviving
  comment reads true standalone as the authoritative reload text (no scanned-
  half clause needed trimming — none survived).

Sweep classification (with the CC1-enumerated exclusion list):
- Functional trees (charts minus tests, containers, services, custom-values,
  .github, skills, AGENTS.md, renovate.json, .rulesync, .opencode): ZERO hits.
- tests/**: hits in EXACTLY the 4 ledger files — test_hf_liveness.py:1 and
  test_config_schema.py:563 (provenance header comments), evidence yaml
  (history header + the truthful pin-retirement runbook line), TEST_SPEC
  (§4/§6/7quinquies ledger). No functional code references. Matches the CC1
  review's exclusion list; nothing else hit.
- __pycache__ deviation ACCEPTED: .gitignore:14 `__pycache__/` present already
  at parent 0e7eafd36; `git ls-files` zero pycache ever tracked — the cleared
  files were untracked+ignored build residue, no tracked deletion.
- docker-build.yaml re-read: detect matrix-gates on `[ -f containers/$c/
  Dockerfile ]` (:80) and pushes only on non-PR events — deletion inert, edit-free
  confirmed. llama-swap-tools-tests.yaml full step inventory: no autogen/venv/
  docker/evidence steps; paths filter references only surviving paths — edit-free
  confirmed.
- ghcr "never pushed" VERIFIED on repo-side evidence (the decisive kind):
  containers/llama-swap-autogen appears in NO origin/main and NO origin/dev
  commit or tree, and the only push trigger is push:main|dev (PR builds never
  push; login gated). Anonymous manifest probe => 403 (indeterminate alone,
  consistent). Recorded conclusion: never pushed, registry cleanup n/a.

Reload story end-to-end: values comments + annotation + configMount describe
hot-reload only (kubelet ~1 min -> -watch-config in-place; reloader = coarse
backstop); evidence yaml :38-43 replaces the two-CM reloader item with the
single-Mechanism observation and explicitly says "no second ConfigMap, no
restart-to-reload generated half"; chunks/C05.md CR6 addendum supersedes the
body (initContainer/entrypoint/scanned/CA4-prereq/cache-observation duties
explicitly dropped). minor-1 (evidence yaml :51 "startup merged load") is
unchanged and ledgered for the next test touch — CC2 touched zero test files,
confirmed by numstat. nit-2/nit-3 likewise ledgered, nothing worse found.

Deviations by reviewer: none. Dev's 4 declared deviations (1-4) all ACCEPTED;
deviation 4 is the instructed task itself and verified true at code level.

Findings:
- nit-1: chunks/CC2.md:79 "ghcr stays published + optional-cleanup note" and
  C05.md addendum / evidence-yaml runbook line assume a published image —
  measurement shows never-pushed. Harmless no-op wording on test/plan-owned
  artifacts; fix at next test touch: annotate the runbook line "cleanup n/a —
  CI never pushed (path never on main/dev)". Dev's handoff already recorded it.
- Deferred (pre-existing, not CC2): planning-artifact citations surviving in the
  helpers header ("CA2, plan REPLAN CR1", "DECISIONS 2026-10-24 CA3 precedence
  ruling", "G1 precedent") — outside the sanctioned reword scope, pre-CC2 text;
  bundle into the post-wave hardening chore if the user wants comment-only prose
  in template headers.

next_suggested: final whole-plan review round 4 (CR6 increment = CC1+CC2 vs the
declared-only end state), then user PR; C05 wave 10 vs the re-balanced evidence
yaml (with minor-1/nit-2/nit-3 test touch folded in per CC1 handoff).
