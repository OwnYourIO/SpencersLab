# Decisions — 2026-10-feat-llama-swap-config-generation

Append-only log of decisions, rejected alternatives, conventions.

## 2026-10-22 — Kickoff (coord)

- Type `feat`, slug `llama-swap-config-generation`. Folder:
  `.agents/plans/2026/2026-10-feat-llama-swap-config-generation/`.
- Models (user choice, overrides `pipeline-models` tier defaults for this run):
  **all roles** use `openrouter/qwen/qwen3.8-flash`.
- Run tag: `openrouter-qwen-qwen3-8-flash`.
- Worktree: reuse the existing session worktree
  `.../worktree/.../llama-swap-config-generation` (branch `llama-swap-config-generation`);
  no new worktree created (user decision at kickoff).
- Landing: commits stay local on the branch; PR/merge is user-owned (repo hard rules).

## Feature constraints (from the user's request)

- Replace hand-edited llama-swap `config.yaml` ConfigMap with generation via
  <https://github.com/shirayu/llama_swap_config_autogen/>, executed right before
  llama-swap starts.
- The tool's native pattern is scan-existing-files → build config; this feature
  inverts it: the desired model list is declared in config, entries land in the
  generated config even when the GGUF is not on disk yet, so llama-swap
  downloads models on demand.
- Convert the **current** models and snippets to the new format — no behavioral
  regressions for existing aliases/flags.
- New models to add:
  - qwen3.8 flash-next @ q3, q4, q5, q6
  - Ornith 1.5 122B @ q3, q4, q5, q6
  - Ornith 1.5 35B @ all sensible quants published on HF (research enumerates;
    plan proposes the final list for user approval).
- Validation/tests run against the **gpu-moe** cluster/box; **gpu-ai is in active
  use — do not disturb its workloads or consume its capacity during this work**.

## 2026-10-22 — Post-research user decisions (coord)

- **Architecture: Path A** — stock `llama_swap_config_autogen` (no fork), two-source
  config via llama-swap v262 `-config-dir` merge: autogen emits the scanned half,
  a declared `-hf` roster half carries all models (RESEARCH.md §2). User chose
  zero-tool-changes despite knowing the current roster is 100% `-hf`-based (the
  scanned half will be ≈empty until models are placed on disk). Planner should
  shape the declared half as the cleanest possible desired-state authoring
  (e.g., compact model list rendered by Helm — no hand-editing of rendered
  config), honoring the user's original goal.
- **Validation target: the `gpu` box** (`services/gpu`, Radeon 780M, 8 GiB VRAM /
  64 GiB RAM = the lab's `gpu-moe` LLM provider). `gpu-ai` is in active use —
  do not disturb or load-test there. Serve-tests only what fits the gpu box
  (35B tier and smaller); all bigger entries validated at config level
  (`llama-swap -validate`, helm template) only.
- **flash-next q5/q6 (125–158 GiB, over gpu-ai's RAM budget): declared ENABLED
  anyway** — user accepted the load-failure/OOM-churn risk knowingly (repo has
  node-freeze history). Mitigations allowed in plan: never preload them, keep
  out of matrix/groups; but entries must be live in config.
- **Orcarouter gated uncensored flash-next: INCLUDE** — HF_TOKEN exists only on
  gpu-ai (gpu box has none), so gated entries are gpu-ai-overlay-only or
  fail-fast elsewhere; planner decides placement.
- Naming note (fact): "gpu-moe" = the `gpu` cluster / `services/gpu` deployment.
  Use "gpu (services/gpu)" in artifacts to avoid re-litigating this.

## 2026-10-22 — Test-contract ratifications (coord)

- User instructed "Continue" after the ratification question was interrupted;
  coord applied the recommended options (each evidence-backed). If the user
  disagrees with either, say so before C02 review closes and it is reopened.
- **C03 criterion 2 RE-EXPRESSED** (controlling wording): rendered base.yaml
  must be parsed by the pinned autogen `generate` (fails only with the stock
  "No models found" on an empty scan set); `validate` applies to the GENERATED
  half; merged-config correctness is checked by fleet `llama-swap -validate`
  (docker-gated evidence). Rationale: pinned tool's `validate` rejects base.yaml
  shape AND today's declared config — original wording is unsatisfiable
  (TEST_SPEC.md §5.1, crash-proof probe evidence).
- **C02 local-ID count: golden is ground truth — 15 gpu-ai-local IDs** (the
  chunk's "16" was a planning miscount: 5 of the block's 20 keys override
  existing chart IDs instead of adding).
- **C05 expected-evidence list** lives at
  `charts/llama-swap/tests/evidence/c05_expected_evidence.yaml` (test-writer
  role could not edit chunks/C05.md); C05 dev/review MUST treat that file as
  the chunk's evidence checklist.
- **Standing rule**: HF tag churn found during C04 ⇒ `C04_HF_REFS` frozen
  tables in `llama_swap_testlib.py` are updated ONLY through the test-writer
  session (ses_e9bdebccbffe7bYG46Fm9LO8FG), never by dev.
- Commit policy for dev agents: commit locally on this branch per AGENTS.md
  (test-contract files committed as their own baseline commit by the first dev
  session); NEVER push/merge (user-owned).

## 2026-10-22 — C02 contract fix + deviation ratifications (coord)

- User routed validation_at_fault fixes A+B back to the original test session
  (ses_e9bdebccbffe7bYG46Fm9LO8FG) per the gates rule. Test writer VERIFIED both
  claims before amending (both confirmed TEST-FAULTY; dev not at fault) and
  committed tests-only amendment `b6fe26e0c`: (A) rana `-hf` substring count →
  whitespace-token count (one `-hf` primary + one `-hfd` draft); (B) hf-refs for
  the 6 gpu-disabled IDs cross-checked against golden gpu-ai instead of
  gpu-golden fail-fast echoes. Contract intent unchanged.
- **Deviation 1 RATIFIED** (mirrors TEST_SPEC.md §7): values carry
  `disabled: "<full message after id>"`; the template composes the byte-exact
  golden echo `/bin/sh -c "echo '<id> <message>' >&2; exit 1"`. The chunk-sketch
  wording is VOID. C04's bf16 gpu fail-fast is confirmed compatible.
- Post-fix suite baseline: 47 red (21 C03 + 26 C04, all implementation-missing)
  / 82 green / 12 evidence-gated skips.

## 2026-10-23 — Docker-gated evidence waived (user decision)

- No docker daemon in the worktree. User chose: **waive the
  `LLAMA_SWAP_IMAGE_EVIDENCE=1` gates for C01/C03 acceptance** — the
  pip-venv substitution stands as the local image-contract evidence. The
  daemon-free `LLAMA_SWAP_EVIDENCE=1` autogen-venv gates (generate/validate
  against rendered base.yaml, degrade-path) STILL RUN and must pass.
- The real image execution is exercised in C05 on-cluster (initContainer runs
  the built image via ArgoCD-synced workload); a regression there is a C05
  blocker per the expected-evidence file.

## Deferred

- (none yet)

## 2026-10-22 — Planning decisions (agent-plan)

- **Autogen delivery: self-built `containers/llama-swap-autogen`** (python:3.12.15-slim-bookworm,
  pip-install of the pinned tarball `https://github.com/shirayu/llama_swap_config_autogen/archive/c7357e68c755b54557f5b0f88b0507bf1c981500.tar.gz`
  at build, `# renovate: datasource=git-refs` ARG pin, uid 65532). Rejected: initContainer
  pip-from-tarball at boot (PyPI egress + latency per restart, non-immutable) and vendored
  source ConfigMap (still needs pydantic/gguf/jsonschema at boot). First chart reference is
  `:main` + `pullPolicy: Always` (no `:v<run>` exists pre-merge; new-container exception,
  pin first immutable tag after landing). SHA re-verified 2026-10-22: still repo `main` HEAD.
- **Degrade path for the empty-scan failure mode**: stock `generate` with zero GGUFs exits
  nonzero ("No models found" — RESEARCH reliability note 8/10; C03 makes it test evidence).
  initContainer: empty scan set OR generate failure → write a comment-only
  `/app/gen/10-scanned.yaml` and exit 0 (fail-open). Grounded in v262 `merge.go`: comment-only
  files are skipped by `parseSource`, an empty `-config-dir` alongside `-config` is valid, and
  `-watch-config` reload failure keeps the old config running. Rationale: the scanned half
  only ever ADDS models; crashlooping the pod costs live consumers (Immich/HA/OpenWebUI)
  against zero upside; the initContainer log line carries the failure evidence.
- **Two-file layout**: `-config /app/config/config.yaml` (ConfigMap dir mount, unchanged
  paths) + `-config-dir /app/gen` (emptyDir; initContainer output) via run.sh envs
  `LLAMA_SWAP_CONFIG`/`LLAMA_SWAP_CONFIG_DIR` (mapping verified in v262 `docker/unified/run.sh`).
- **Merge-semantics refinement vs RESEARCH §5** (verified in v262 `internal/config/merge.go`
  + `matrix.go`, upgrades RESEARCH's 9/10 note to source-proven): identical scalars across
  sources OK, differing scalars hard-error; identity maps (`models`, `groups`, `matrix`, …)
  hard-error on duplicate CHILD keys — and `matrix`'s structural children (`vars`, `sets`)
  count as such, so **matrix in both halves is a load error**. Therefore: macros, matrix,
  hooks and all top-level scalars live ONLY in the declared half; `base.yaml` carries only
  scan paths + binary path + the macros the generator references. RESEARCH §5's "matrix/
  hooks → base.yaml passthrough" applied to a single-file world and is NOT used.
- **`matrix.vars` referencing an unknown model = hard load error** (v262 matrix.go:71 —
  answers RESEARCH §7-Q7's unverified edge). Adopted as a standing invariant test in C02/C04.
- **Declared-half authoring (user's desired-state goal)**: compact schema under chart
  `config.models.<id>` (`hf`/`draft`/`spec`/`use[]`/`flags`/`cmd` escape hatch/`disabled` +
  passthrough fields), Helm-rendered into the llama-swap YAML; per-cluster overrides keep
  today's Helm deep-merge mechanism. `&vlWorkloadFilters` anchor → named `filterPresets`.
  Precedence `disabled > cmd > hf-composition`; `proxy` defaults `http://localhost:${PORT}`.
  No hand-editing of rendered config anywhere in steady state.
- **Reload semantics statement** (RESEARCH §5 blocker 6): ConfigMap data changes roll pods
  via the existing stakater reloader annotation (both CMs mounted; add explicit
  `reloader.stakater.com/match` if auto mode misses the new one); declared half additionally
  hot-reloads via watch-config (~1 min kubelet sync); generated half is restart-to-reload
  only. C05 records observed behavior on the gpu box.
- **Placement decisions (answers RESEARCH §7-Q6/Q7)**: gated `orcarouter/Qwen3.8-Flash-Next-
  Uncensored-GGUF` (`gated:auto`, live-checked 2026-10-22, `Q6_K` present) and the whole
  flash-next + 122B families are **gpu-ai service values only — absent from the gpu render**
  (absence over fail-fast: these IDs have no consumers on the gpu box; the token is gpu-ai-only).
  35B-tier Ornith rides the chart (both clusters) with gpu-tuned/`disabled:` entries mirroring
  the evidence-backed `qwen3.6-35b-a3b-q8` pattern.
- **New model IDs (long-form per lab convention; pending user approval)**:
  `qwen3.8-flash-next-q3/-q4/-q5/-q6`, `qwen3.8-flash-next-orca-q6`,
  `ornith-1.5-122b-q3/-q4/-q5/-q6`,
  `ornith-1.5-35b-a3b-iq2xxs/-q3/-q4/-q5/-q6/-q8/-bf16`.
  flash-next q5/q6: declared ENABLED, in NO matrix set (run-alone), never preloaded (user
  risk accepted). q3/q4/q5/q6 unsloth UD ladder chosen over bartowski (one repo per family =
  shared snapshot cache; RESEARCH §4 guidance). MTP: flash-next via in-repo
  `mtp-Qwen3.8-Flash-Next-Q8_0` `-hfd`; orca mirrors the proven embedded-`--spec-type
  draft-mtp` pattern (header-check fallback in C04); 122B MTP optional pending prithivMLmods
  filename verification.
- **35B quant list PROPOSED for user approval** (§4C superset reduced): official 5
  (Q4_K_M/Q5_K_M/Q6_K/Q8_0/BF16) + bartowski Q3_K_XL + bartowski IQ2_XXS = 7 entries.
  Rejected: the `_K_L` rungs and IQ3/IQ4 tiers (marginal deltas, ID sprawl) and 2-shard
  BF16 duplicates. On approval, append the decision here; C04 executes the approved list.
- Fit gate for new MoE families: `-ot` regex match against real GGUF tensor names verified
  by HF range-fetch at C04 time (Qwen4Exp arch may differ from qwen35moe/qwen3_5_moe).
- C05 (on-cluster gpu verification) is user-gated: ArgoCD syncs `main` only; the chunk
  stays `blocked: awaiting user landing` until the PR merges. gpu-ai gets log-level
  confirmation only; admin-* MCP requires explicit user approval per run.

## 2026-10-22 — Plan approval (user, via agent-plan question tool)

- **Approved: plan, chunk table, wave order** (C01+C02 → C03+C04 → C05), the
  `containers/llama-swap-autogen` delivery, the fail-open degrade path, the
  declared-half-only matrix/macros/hooks merge rule, and the C04 MTP/`-ot`-fit gates.
- **Approved: 35B ladder = the 7-entry proposal** (official Q4_K_M/Q5_K_M/Q6_K/Q8_0/BF16
  + bartowski Q3_K_XL + bartowski IQ2_XXS; `_K_L` and IQ3/IQ4 tiers rejected).
- **Approved: long-form new IDs** (`qwen3.8-flash-next-q3…q6`,
  `qwen3.8-flash-next-orca-q6`, `ornith-1.5-122b-q3…q6`, `ornith-1.5-35b-a3b-…`).
- `plan_status: approved` in STATE.json. Pipeline may proceed: agent-test first
  (golden capture + failing tests), then dev per waves.

## 2026-10-23 — C03 escalations (coord; user-approved)

- **Docker-waiver scope CONFIRMED to cover C03's docker-gated merged-config
  `-validate` cases** (c03_4-merge/c03_5). On-cluster real-image proof happens
  in C05. Daemon-free `LLAMA_SWAP_EVIDENCE=1` gates remain mandatory.
- **validation_at_fault (3 degrade-path tests)** routed to the original test
  session per user decision: `_init_script` `-c` extraction off-by-one
  (`argv[len(argv)-1-argv[::-1].index("-c")]` ⇒ `argv[len(argv)-argv[::-1]
  .index("-c")]`). Dev's implementation proven against corrected extraction.

## 2026-10-23 — C04 escalations D/E/F resolved (coord; user-routed batch)

- Defects D/E/F confirmed **TEST-FAULTY** by the test writer (each reproduced
  before amending; C04 dev innocent); tests-only commit `e9a2d1d1e`.
  Post-fix bars: full suite **0f/129p/12s**, live `hf_check` **117/117 OK**.
- F's fix spans BOTH loader rules (`-hf` find_best_model + `-hfd`
  find_best_sibling sidecar matching); the sidecar check is deliberately
  stricter than llama.cpp's silent-fallback loader — requiring the named
  sidecar file IS the churn signal we want.
- C04 dev findings mirrored (no test/source change needed): fit gate re-proved —
  `-ot "\.ffn_.*_exps\.=CPU"` matches qwen4exp (144), qwen35moe-122B (147),
  qwen35moe-35B (123/753) => `${moe}` wired everywhere, **fn-moe fallback not
  needed**; orca-q6 uses embedded MTP (no `-hfd`), header check 401-blocked
  anonymously, fallback recorded in entry comment.
- **C05 runbook addendum**: orca's `MTP-draft.gguf` filename is UPPERCASE;
  llama.cpp's `mtp-` sidecar keyword match is case-SENSITIVE — if the `-hfd`
  orcarouter fallback line is ever wired, it will NOT resolve as named
  (TEST_SPEC §7(F)). First gpu-ai load of the >125 GiB-class entries
  (flash-next q5/q6, orca-q6, 122B-q6) and the q3 regime is
  measure-on-cluster; C05 must observe, not assume.

## 2026-10-24 — User review round: replan requests (coord)

After reviewing the landed C01–C04 surface, the user requested changes
(pre-C05; plan reopened):

1. **Family-based definitions**: model entries keyed by FAMILY (e.g.
   `qwen3.8-27b`) with the quant ladder built in (like `use:` composition);
   llama-swap IDs (`qwen3.8-27b-q4`) are GENERATED from family+quant. Rendered
   cmd parity per quant must hold vs today.
2. **Catalog pattern**: chart values.yaml defines ALL model families, default
   DISABLED (ratified deviation-1 fail-fast wording); `services/gpu` and
   `services/gpu-ai` enable their subset. Consequence for the contract:
   per-cluster isolation assertions change from "ID absent" to "ID present +
   fail-fast disabled" — test writer must rebase parity/isolation bars
   (superset semantics), coord-routed.
3. **Removals**: qwen3-coder* + all kat-coder* + "all non-vision-handling
   qwen3.5" (exact inventory list to be presented for approval; matrix
   var/set referential closure must be kept — v262 load-errors on dangling
   vars). User WILL handle downstream consumer configs (agent-model fallbacks
   gpu-ai/kat-coder-q8|q8-1m, gpu-moe/kat-coder-q6, coder-workspace flows)
   themselves; runbook must flag them.
4. **No inline script in k8s yaml**: the autogen degrade/generate shell moves
   INTO `containers/llama-swap-autogen` (entrypoint); manifests invoke with
   args only. Degrade-path test sandboxing must re-express against the
   repo-side entrypoint file (daemon-free, still sandbox-executable).
5. flash-next/orca: no additions — user's "research and add" was a visibility
   miss during review; entries exist and stay (folded into the catalog).

## 2026-10-24 — Replan decisions + user rulings (agent-plan; replan of C01–C04 surface)

**User rulings (question tool, 2026-10-24 — ground truth):**
- Removals: certain set (qwen3-coder-next×2 + kat-coder×6) APPROVED; `coder-next-ablit`
  RULED IN with the coder family; "non-vision qwen3.5" RULED as **Option B** — the older
  text-only Qwen3 line `qwen3-30b-a3b-q4/-q8` + `qwen3-8b-q4/-q8` (no literal qwen3.5* IDs
  ever existed; grep-proven). **The entire qwen3.6 line SURVIVES** (incl. gpu's golden-pinned
  tuned 35B-q8 regime, the -1m/-bf16 golden echoes, -q8-visual, qwen36-heretic/huihui).
  Frozen REMOVED_IDS = **13**.
- In-repo consumers: **fix both in this PR** — minuspod's `OPENAI_MODEL: qwen3.6-27b-q6`
  turns out to be a SURVIVOR under ruling B (CA3 verifies, no edit); the two
  `pipeline-models` kat-coder rows (gpu-ai/q8, gpu-moe/q6) are DELETED in-PR from the
  `.rulesync` source + `rulesync generate` mirror (delete-only, no invented replacements).
- Machine-global provider configs stay USER-OWNED: enumerated 13 dangling modelIDs under
  provider `gpu-ai` + 9 under `gpu-moe` (+ kilo twin, coder-workspace flows) → C05 runbook.
- Architecture (family schema, catalog default-disabled, superset parity P1–P6, entrypoint
  relocation, waves CA1→CA3∥CA4→CA2→C05): **APPROVED as planned.**

**Planner decisions (rejected alternatives in parentheses):**
- Family schema = `config.families.<family>.quants.<rung>` with ID derivation
  `<family>-<quant>`, per-rung `id:` override (only `home-3b-v3` needs it), merge layering
  family < rung < raw `config.models.<id>` (Helm deep-merge stays the per-cluster override
  channel — per-quant overrides survive with today's exact mechanism: gpu tuned regimes,
  `disabled:` messages, capabilities). (Rejected: replacing `models:` entirely — would break
  the schema escape-hatch tests and rana/whisper raw-cmd passthrough.)
- Precedence unchanged `disabled > cmd > hf-composition`; expansion converts `not-enabled`
  to the deviation-1 echo path (ratified wording preserved per-quant); NEW catalog-default
  message ("is not enabled on this cluster …") is NOT golden-pinned — legacy golden messages
  stay byte-exact via the clusters' `models.<id>.disabled:` overrides. (Rejected: per-rung
  `cmd:` duplication for every rung — defeats the compact-catalog goal.)
- Duplicate rendered ID fails the render; `families` key stripped from rendered output
  (chart-values concept, like filterPresets).
- Ordering CA3 (removals) BEFORE CA2 (catalog conversion): strip dead weight first so the
  conversion moves less data and the catalog diff stays reviewable; CA2 additionally carries a
  file-conflict dep on CA4 (shared `_helpers` + values sections), no semantic coupling.
- Parity rebase P1–P6 (plan REPLAN/CR2): rendered-ID set == frozen CATALOG (58 IDs); live
  golden cmds keep token-multiset equality UNBENTED; 3 surviving golden echoes byte-exact;
  removed IDs absent; new off-cluster IDs fail-fast shaped; matrix assertion amendment E
  re-expressed "additive preservation modulo REMOVED" (CA3 legitimately removes vars).
  Goldens byte-untouched (user). Isolation flips absent→echo (user-requested consequence).
- Entrypoint contract: flags `--scan-dir/--base/--out/--home`; fail-open rc0 semantics ported
  verbatim; usage errors exit ≠0 (wiring bugs loud — degrade rc0 reserved for scan-empty /
  generate-fail only); `--home` makes the C03 writable-cache fix EXPLICIT (supersedes the
  accepted passwd-fallback deviation-1 reasoning with a pinned arg); drift guard re-armed
  args-driven (scan-dir set == scanPaths, both directions) + any initContainer `command:`
  fails the render (shell-reintroduction tripwire). Degrade tests re-expressed against the
  repo-side entrypoint.sh (daemon-free), routed through CA1/test session.
- No separate CA5 chunk: the C05-tasking rebase (enabled sets, removals, runbook addenda,
  dangling list) was executed IN-PLACE in chunks/C05.md as a planner artifact of this replan.
- v262 feasibility: all five CRs verified compliant (echo models in matrix = established
  pattern; colon-namespaced scanned half unaffected; preload ids survive; matrix closure is
  the standing rule CA3 re-proves). No STOP condition hit.
- `plan_status: approved`; next wave = CA1 (test session only); C05 remains pending,
  user-gated on PR landing (wave 6).

## 2026-10-24 — CA3 execution rulings (coord)

- In-session user ruling (during CA3 dev): `charts/gpt-researcher/values.yaml`
  FAST_LLM pinned a removed ID (`qwen3-8b-q8`) — missed by the replan sweep.
  **Repointed in-PR to `qwen3.6-27b-q8`** (survivor); own commit; helm-validated.
  Lesson recorded: sweeps must grep EXACT IDs, not family patterns only.
- Incident-history comment blocks mentioning removed IDs reworded
  family-generic (reasoning preserved); rendered bytes untouched (proven).
- No macro deletions (all still referenced across the two renders).
- CR1.3 merge semantics PINNED as implemented+tested (per CA2 review observation):
  family<rung<models precedence; rung `enabled: false` beats family `enabled: true`;
  `disabled:` beats `enabled:`. The plan's "OR" wording is superseded by this entry.
