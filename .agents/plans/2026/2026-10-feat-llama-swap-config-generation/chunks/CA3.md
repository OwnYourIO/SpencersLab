# CA3: removals — frozen 13-ID strip, matrix closure, consumer-reference sweep
size: M   wave: 4   depends_on: [CA1 (REMOVED_IDS frozen + P4 parity expectations)]

## Goal
Remove every model the user ruled out, keep the config referentially closed (v262
`matrix.vars`→unknown-model and set-token→unknown-var are HARD load errors, matrix.go:71),
execute the two in-repo consumer fixes the user ruled into this PR, and write the
dangling-consumer report the user needs for the machine-global side. Runs on the CURRENT
values shape (before CA2's catalog conversion).

## Removal list — FROZEN by user ruling 2026-10-24 (REMOVED_IDS = 13)
- `qwen3-coder-next-q6`, `qwen3-coder-next-q8` (chart; live gpu + gpu-ai)
- `coder-next-ablit` (gpu-ai; Qwen3-Coder-Next derivative — ruled in with the coder family)
- `kat-coder-q4`, `kat-coder-q6`, `kat-coder-q8` (chart; gpu golden disabled-echo + gpu-ai live)
- `kat-coder-q4-1m`, `kat-coder-q6-1m`, `kat-coder-q8-1m` (gpu-ai local)
- `qwen3-30b-a3b-q4`, `qwen3-30b-a3b-q8`, `qwen3-8b-q4`, `qwen3-8b-q8` (chart; ruling B —
  "non-vision qwen3.5" meant this older text-only Qwen3 line; NO literal qwen3.5* IDs ever
  existed)
SURVIVES (explicit, do not cut): the entire qwen3.6 line — `qwen3.6-27b-q6/-q8`,
`qwen3.6-35b-a3b-q6/-q8` (incl. gpu's golden-pinned tuned q8 regime), `-1m`, `-bf16`,
`-q8-visual`, `qwen36-heretic`, `qwen36-huihui` — and `qwen3-embedding-0.6b`.

## Tasks
- [x] Strip every REMOVED id from: chart `config.models`, gpu block (kat-trio disabled echoes
      + descriptions go with the family), gpu-ai block (kat 1m trio, ablit), chart
      `matrix.vars` (coderq6, coderq8, katq4, katq6, katq8, q30q4, q30q8, q8bq4, q8bq8) +
      `main` alternation tokens, gpu-ai `matrix.vars` (katq41m, katq61m, katq81m, cnxabl) +
      `main`/`solo` set tokens. gpu-ai `main` references chart-defined vars q30q4/q30q8/q8bq4/
      q8bq8 + coderq6/coderq8 — those tokens MUST come out of gpu-ai's own set strings too
      (dict-merge keeps the replaced set strings as the source of truth there).
- [x] Macros: after cuts, delete any `config.macros` entry no longer referenced in either
      render (expect: none — q36-common/-sampling stay used by heretic/huihui under ruling B;
      verify by grep, record the finding).
- [x] Preload/hooks: assert NO removed id is preloaded (preload = qwen3.8-27b-q8 +
      qwen3-embedding-0.6b — both survive); chart `hooks` absent — assert.
- [x] Matrix closure re-run both clusters (test exists; independent render grep too: every
      var value and set token resolves against merged models).
- [x] In-repo consumer fixes (USER RULING "fix both in this PR", re-read under ruling B):
      1. `charts/minuspod/values.yaml` OPENAI_MODEL `qwen3.6-27b-q6` SURVIVES → NO edit;
         verify + record ("checked, id lives") in this chunk's notes.
      2. `.rulesync/skills/pipeline-models/SKILL.md`: delete the two rows naming removed ids
         (`gpu-ai / kat-coder-q8`, `gpu-moe / kat-coder-q6`); leave surviving rows
         (qwen3.6-35b-a3b-q8 ×2, openrouter row) untouched; do NOT invent replacement rows
         (lab just deleted local coder models). Then `rulesync generate` and commit source +
         generated `.opencode/skills/pipeline-models/SKILL.md` together (AGENTS.md rule; never
         hand-edit the generated file).
- [x] Machine-global dangling list (OUT OF REPO — user handles; produce for C05 runbook;
      verified 2026-10-24 against `~/.config/opencode/opencode.json`): provider `gpu-ai` 13
      modelID entries (qwen3-coder-next×2, coder-next-ablit, kat-coder×6, qwen3-30b-a3b×2,
      qwen3-8b×2), provider `gpu-moe` 9 (same families minus 1m-trio/ablit: coder-next×2,
      kat×3, 30b×2, 8b×2), the kilo twin `~/.config/kilo/kilo.jsonc`, coder-workspace flows.
      All qwen3.6 refs there SURVIVE. Enumerate the exact pairs (provider, modelID) in the
      chunk notes — the runbook copies them mechanically.
- [x] Repo-wide sweep (final evidence): grep each REMOVED id across `services/`,
      `custom-values/`, `charts/`, `skills/`, `.rulesync/`, `.opencode/`, `containers/`,
      `.github/` — after the pipeline-models edit, zero in-repo hits (excluding
      charts/llama-swap/tests/golden — byte-frozen history — and the removal records
      themselves); record greps in this chunk file.

## Files in scope
- charts/llama-swap/values.yaml (config.models + matrix + macros only)
- services/gpu/prod/values.yaml, services/gpu-ai/prod/values.yaml (llama-swap blocks)
- .rulesync/skills/pipeline-models/SKILL.md + regenerated .opencode/skills/pipeline-models/SKILL.md
- chunks/CA3.md (sweep + machine-global evidence record — allowed: named by acceptance 4)

## Acceptance criteria
1. All three plan renders pass; `helm lint --strict` clean.
2. P4 parity test green: zero REMOVED ids in either rendered config (models, matrix vars/sets,
   hooks) — grep the rendered YAML, not just values.
3. P2/P3 golden parity for SURVIVORS stays green — incl. the 3 surviving gpu golden echoes
   (qwen3-vl-30b-a3b-bf16, qwen3.6-35b-a3b-1m, qwen3.6-35b-a3b-bf16) byte-identical, and
   gpu's qwen3.6-35b-a3b-q8 tuned regime token-parity intact; suite reds = exactly CA2+CA4
   scope.
4. Sweep recorded here: zero unexpected in-repo hits (minuspod verified-survivor noted);
   machine-global list written out exact (provider, modelID pairs); pipeline-models rows
   deleted + `rulesync generate` output committed alongside source.
5. Matrix closure tests green both clusters (no dangling var/set token after cuts).
6. `rulesync generate --check` passes after the pipeline-models edit.

## Tests (agent-test writes, review runs)
All CA1-written (P4 + parity survivors + closure). Review re-runs suite + the sweep greps +
renders + rulesync check.

## Notes for dev
- Cut whole `models.<id>` blocks including their comment headers; survivors sharing a comment
  block keep their bytes exactly (golden P3).
- After every edit run the matrix-closure test EARLY (v262 load-error class — the test is the
  only pre-merge guard against a dangling var surviving into main).
- Do NOT touch goldens / any other test file / machine-global configs / minuspod.
- pipeline-models edit = delete-only; if review/user wants replacement rows, that is a new
  ruling, not this chunk.

## Dev record (CA3, 2026-10-24)

### Removals executed (frozen 13)
- chart `config.models`: qwen3-coder-next-q6/-q8, qwen3-30b-a3b-q4/-q8, qwen3-8b-q4/-q8,
  kat-coder-q4/-q6/-q8 (9 entries incl. blank-line separators; whole blocks cut).
- chart `matrix.vars`: coderq6, coderq8, q30q4, q30q8, q8bq4, q8bq8, katq4, katq6, katq8 (9);
  `main` alternation: those 9 tokens dropped from the chart set string.
- gpu block: the 3 kat-coder `disabled:` echo overrides (with descriptions) went with the
  family; shared comment block kept its surviving-3 reasoning, renamed id references rewritten
  family-generic (USER RULING via question tool 2026-10-24: "rewrite family-generic, preserve
  the reasoning, rendered bytes untouched").
- gpu-ai block: kat-coder-q4-1m/-q6-1m/-q8-1m + coder-next-ablit model entries; `matrix.vars`
  katq41m/katq61m/katq81m/cnxabl; `main` tokens coderq6|coderq8|q8bq4|q8bq8|q30q4|q30q8 (the
  chart-var tokens inside gpu-ai's OWN set strings — dict-merge note honored); `solo` tokens
  katq4|katq6|katq8|katq41m|katq61m|katq81m|cnxabl; comments reworded (1M header now "both
  surviving 1m rungs"; main/solo-set notes keep the RAM-budget reasoning, name no id).
- SURVIVORS VERIFIED UNTOUCHED: entire qwen3.6 line (incl. gpu tuned q8 regime), qwen3-embedding-0.6b,
  minuspod `OPENAI_MODEL: qwen3.6-27b-q6` — checked, id lives, NO edit (ruling B).

### Macros finding (task 2): NONE dropped
Rendered-macro usage probe over both renders: every defined macro is referenced post-cut
(gpu: threads/moe/moe-vl-q4/moe-vl-q8/flash-and-q8/ctx-256k/big-ub/server-cmd in live cmds;
`ctx-1m` unreferenced on the GPU render only because its two users are echo-disabled / gpu-ai-local
there — it IS referenced on the gpu-ai render (qwen3.6-35b-a3b-1m + qwen3.8-27b-q8-1m live cmds),
so it is not "no longer referenced in either render" → kept. gpu-ai: q36-common/q36-sampling used
by qwen36-heretic/qwen36-huihui (ruling B survivors), q38-* all used). Zero macro definitions
removed; macros tables byte-identical to HEAD renders (proven below) — golden macro parity
untouched by construction.

### Preload/hooks (task 3)
gpu-ai preload = [qwen3.8-27b-q8, qwen3-embedding-0.6b] — both survive, no removed id (P4
preload leg green both clusters). Chart `hooks`: ABSENT (gpu render hooks=None, golden parity
`g.get("hooks") == f.get("hooks")` green both clusters).

### Matrix closure (task 4) — both clusters PASS
- Tests: `test_c02_3_matrix_referential_closure[gpu/gpu-ai]` green.
- Independent probe over rendered configs: vars→models 0 dangling; set tokens→vars 0 unknown;
  resolved members→models 0 missing; preload ids all present. Renders: gpu 38 models,
  gpu-ai 58 models (= frozen CATALOG size).
- Survivor-impact proof (git-archive HEAD vs now, field-wise JSON-canonical over rendered CMs):
  dropped == exactly (old-models ∩ REMOVED); surviving model entries byte-equal (0 diffs);
  macros/hooks/top-level scalars byte-equal; surviving vars map byte-equal; set names unchanged;
  only dropped tokens were vars whose value ∈ REMOVED. PASS both clusters.

### In-repo consumer fixes (task 5)
1. minuspod: `OPENAI_MODEL: qwen3.6-27b-q6` — checked, id lives under ruling B → NO edit.
2. `.rulesync/skills/pipeline-models/SKILL.md`: rows `gpu-ai / kat-coder-q8` and
   `gpu-moe / kat-coder-q6` deleted (delete-only, no replacement rows invented);
   `rulesync generate` regenerated `.opencode/skills/pipeline-models/SKILL.md` (2-line mirror
   removal); `rulesync generate --check` => "All files are up to date" rc 0 (acceptance 6).
   Source + generated committed together in the companion commit.
3. NEW consumer found by the CA3 sweep that the replan-time sweep missed —
   `charts/gpt-researcher/values.yaml` `FAST_LLM: "openai:qwen3-8b-q8"` (dev-cluster consumer of
   the gpu-ai roster). USER RULING via question tool 2026-10-24: repoint in-PR to
   `openai:qwen3.6-27b-q8` (dense lane on the gpu-ai roster). Applied + validated
   (`helm lint` pass, template renders the new value). Out-of-scope file → listed under RESULT
   deviations; file added to scope by the ruling.

### Machine-global dangling list (task 6 — OUT OF REPO, user-owned; re-verified 2026-10-24 by
read-only grep of the live files; NOTHING edited)
`~/.config/opencode/opencode.json` — provider `gpu-ai` (models block @line 376+), 13 dangling
modelIDs: (gpu-ai, qwen3-coder-next-q6), (gpu-ai, qwen3-coder-next-q8), (gpu-ai, coder-next-ablit)
@1026, (gpu-ai, kat-coder-q4), (gpu-ai, kat-coder-q6), (gpu-ai, kat-coder-q8),
(gpu-ai, kat-coder-q4-1m), (gpu-ai, kat-coder-q6-1m), (gpu-ai, kat-coder-q8-1m),
(gpu-ai, qwen3-30b-a3b-q4), (gpu-ai, qwen3-30b-a3b-q8), (gpu-ai, qwen3-8b-q4), (gpu-ai, qwen3-8b-q8).
Provider `gpu-moe` (@line 1043+), 9: (gpu-moe, qwen3-coder-next-q6), (gpu-moe, qwen3-coder-next-q8),
(gpu-moe, kat-coder-q4), (gpu-moe, kat-coder-q6), (gpu-moe, kat-coder-q8),
(gpu-moe, qwen3-30b-a3b-q4), (gpu-moe, qwen3-30b-a3b-q8), (gpu-moe, qwen3-8b-q4), (gpu-moe, qwen3-8b-q8).
kilo twin `~/.config/kilo/kilo.jsonc`: identical 13+9 pairs (gpu-ai @771-885+1350, gpu-moe @1389+).
All qwen3.6 provider entries there SURVIVE. coder-workspace flows: user-owned, untouched.
(C05 runbook copies these mechanically.)

### Final sweep evidence (task 7)
Per-id grep `grep -rn <ID> services/ custom-values/ charts/ skills/ .rulesync/ .opencode/
containers/ .github/` for all 13 ids: hits ONLY inside `charts/llama-swap/tests/**` —
golden/* (byte-frozen history, excluded by acceptance) and testlib frozen tables + TEST_SPEC §7bis
+ evidence/c05_expected_evidence.yaml (the removal records themselves, excluded).
ZERO in: values/services surfaces, skills/, .rulesync/, .opencode/, containers/, .github/,
custom-values/. Stricter family-prefix + var-name sweep (katq*/coderq*/q30q*/q8bq*/cnxabl,
kat-coder, qwen3-coder-next) over the same dirs: zero outside tests/**.
Rendered-config grep (default/gpu/gpu-ai full docs): all 13 ids => 0 hits in all three renders.
Em-dash-avoidance: all values edits applied via shell-python with exact-match asserts (FRICTION
known workaround); every assert fired zero.

### Validation totals (CA3 dev, PATH=/tmp/opencode/bin helm v3.16.4)
- helm dependency update + lint + `lint --strict` => pass; renders default/gpu/gpu-ai => pass
  (64228/65886/82914 B; was 67832/69632/88739 — delta is the removals).
- full suite `pytest charts/llama-swap/tests -v` => 21f/126p/12s (baseline 25f reproduced
  name-identical at session start; CA3 flipped exactly P4×2 + P1[gpu-ai] + roster-exact[gpu-ai]).
  Remaining 21 reds = CA2 scope 13 (parity P1[gpu], P5[gpu]; schema 9 value-shape+fam_*;
  roster exact[gpu], isolation-flip) + CA4 scope 8 (wiring 7, image 1). Zero new reds.
- preservation bars UNREGRESSED: parity module 26p/2f (P2 cmd-multiset + P3 byte-echo (3
  survivors) + P6-modulo + hooks/macros/scalars + closure + aliases all green), schema 9p (incl.
  rana escape-hatch + composition golden-ref tests), image parse 5p/4s, existing CI 33/33,
  LLAMA_SWAP_EVIDENCE gates 3p/5s, goldens + whole tests tree diff-empty.
- aislop dir scans: 0 errors / 0 warnings on the 5 touched files.
- sentinel hygiene: renders carry OVERRIDE_VIA only in the gpu-ai ExternalSecret key
  (bitwardenIds sentinel by design — resolved at deploy via custom-values; llama-swap-config
  CM itself sentinel-clean, `test_c02_5` green).

## Review notes (review agent fills)

### Round 1 — 2026-10-24, reviewer session (diffs 6b76b7c2d + 111fe0e1c + e671e1c26)

Verdict: **APPROVED**. Environment: helm v3.16.4 (/tmp/opencode/bin), system
python3 pytest 9.1.1 (ag-venv lacks pytest this session — noted under friction).
Working tree = HEAD e671e1c26, code surface clean (only coord-owned .agents/plans
edits uncommitted).

**1. Bars — all reproduced, numbers name-exact**
- helm dependency update + lint + `lint --strict` => pass (0 failed).
- Renders default/gpu/gpu-ai => 64228/65886/82914 B — identical to the Dev
  record (HEAD-pre baseline re-rendered myself: 67832/69632/88739, also identical).
- Full suite `-v` => **21 failed / 126 passed / 12 skipped**. Baseline re-run
  from `git archive ebceb56c7` tree => 25f/122p/12s reproduced in-session;
  name-level comm of the FAILED sets: CA3 flipped EXACTLY the documented four
  (P4[gpu], P4[gpu-ai], P1 `model_id_sets_equal[gpu-ai]`,
  roster-exact `[gpu-ai]` — all four verified PASSED in the current run).
  Zero new reds, zero unintended flips. Remaining 21 = CA2 13 (parity P1[gpu] +
  P5[gpu]; schema 3 value-shape + 6 fam_*; roster exact[gpu] + isolation-flip)
  + CA4 8 (wiring 7: degrade trio 3 + usage + --home + args-not-command ×2;
  image 1). Failure reasons sampled: every red cites CA2/CA4 ownership
  ("awaiting CA2", "CA4 moves it into the image entrypoint"); none names CA3.
  P1[gpu]'s message now shows `unexpected []` — CA3's contribution to that red
  is fully discharged; only the 20 gpu-ai-local IDs (CA2 scope) are missing.
- Parity module 26p/2f: P2 cmd-token-multisets both clusters, P3
  byte-echo/ids-survive/consumer-aliases both, P6-class macros/matrix/hooks/
  scalars both, closure `test_c02_3` both, roster `test_c04_3` closure both —
  all green. Schema 9p/9f. Existing CI files => **33/33**. Evidence gates
  `LLAMA_SWAP_EVIDENCE=1` => **3p/5s** (unchanged).

**2. Removal integrity beyond the tests — independent, zero problems**
- EXACT-13-ID sweep (lesson applied — literal ids, not families): 0 hits in ALL
  three full renders; 0 hits across `services/ custom-values/ charts/
  containers/ .rulesync/ .opencode/ skills/ .github/` outside
  `charts/llama-swap/tests/**`. tests/** residuals = exactly the allowed
  frozen-records files (testlib tables, goldens, evidence yaml, TEST_SPEC;
  plus a pycache artifact). `charts/gpt-researcher` clean.
- Extended sweeps: removed matrix-var tokens (katq*/coderq*/q30q*/q8bq*/cnxabl)
  word-boundary grep in all three values files + all three renders => 0.
  Case-insensitive family strings (kat-coder/qwen3-coder/coder-next/Kwaipilot)
  => single hit: gpu-ai values:127 pre-existing historical PLAN-slug citation
  ("plan 2026-10-11 gpu-ai-uncensored-qwen36-coder-next"), verified identical at
  ebceb56c7 and NOT a model ID — out of scope, see Deferred.
- Matrix closure re-probe (own code, both renders): vars->models 0 dangling;
  set tokens->vars->models 0 unresolved; preload [qwen3.8-27b-q8,
  qwen3-embedding-0.6b] live on gpu-ai; chart/gpu hooks absent (parity
  hooks-leg green). gpu 38 models, gpu-ai 58 = frozen CATALOG size.
- Survivor byte-stability (own `git archive ebceb56c7` renders vs HEAD,
  field-wise canonical-JSON over the rendered ConfigMap): dropped == exactly
  old-models ∩ REMOVED; additions ∅; every surviving model entry byte-equal;
  macros, hooks, all non-matrix top-levels byte-equal; surviving vars
  byte-equal; set names unchanged; only set tokens dropped were vars whose
  value ∈ REMOVED. PROBLEMS: NONE, both clusters.

**3. gpt-researcher repoint — matches the user ruling**
`FAST_LLM: openai:qwen3.6-27b-q8` — survivor, renders live on the gpu-ai config
(real cmd, not disabled/echo); helm lint pass; template renders the new value;
SMART/STRATEGIC untouched; the commit is a single hunk (+4/−1) — no other
drift in that chart. Ruling DECISIONS 2026-10-24 "Repointed in-PR to
qwen3.6-27b-q8 (survivor)" satisfied; comment records the why without naming
the retired id.

**4. rulesync mirror — consistent, committed together**
2 rows deleted from `.rulesync` source + mirror regenerated in the same commit
(e671e1c26, per AGENTS.md). `rulesync generate --check` => "All files are up to
date" rc 0 (covers all generated surfaces — no other drift). Residual source-vs-
mirror delta is rulesync's standard frontmatter normalization (folded
description, quote style, key order) — generated-file convention, not drift.
Surviving rows (qwen3.6-35b-a3b-q8 ×2, openrouter) intact; kat = 0 in both.

**5. Macro/anchor discipline — dev claim verified**
Own reference-graph probe: default render 0 orphan macros; gpu-ai 0 orphans;
gpu render shows `ctx-1m` unreferenced — PROVEN pre-existing: HEAD-pre render
at ebceb56c7 also has ctx-1m unreferenced on gpu (its only users live on the
gpu-ai side, where it IS referenced by 2 live survivors). Task rule is
"no longer referenced in either render" → keeping it is correct, not an
orphan introduced by CA3. Spot-verified moe-vl-q4 (2 users), moe-vl-q8 (2),
big-ub (4), ctx-256k (11/22), q36-common (2: heretic/huihui per ruling B) —
all referenced exclusively by survivors. Zero macro definitions removed
(macros tables byte-equal both clusters, §2); YAML anchors (`*chartName`
region, lines 970/1028) untouched by any CA3 hunk, renders parse.

**6. Fresh eyes**
Reworded comments keep the reasoning (2026-10-18 freeze class, YaRN x4/KV
budget math, 119 GiB RAM arithmetic, solo-eviction mechanics) and name no
removed id. Flat `config.models` shape structurally intact — no `families:`
key, no CA2 surface touched. Tests tree diff ebceb56c7..HEAD = 0 (goldens
byte-untouched, no weakened validations). EOF newlines present on all 6
touched files. aislop 0.18.1: YAML/MD are not analyzed languages; the only
error-severity findings under the touched dirs are `scripts/gguf-py/vocab.py`
(vendored upstream, gate-excluded by `.aislop/config.yml`, untouched by CA3) —
**0 findings attributable to touched files**. Commit scopes via git show:
3 values files / 1 values file / 2 SKILL.md — exactly chunk scope +
user-ruled additions, each message tagged (CA3).

**Findings: none (no blocker/major/minor/nit on the chunk itself).**

Deferred (out of CA3 scope, not gating):
- Pre-existing trailing spaces at charts/llama-swap/values.yaml:65-66 (inside
  the ${moe} macro, present at ebceb56c7, outside every CA3 hunk).
- gpu-ai values:127 historical plan-slug contains the "coder-next" substring —
  a provenance citation, not a model reference; fine to leave.
- Carried CA1 flag for CA4 review: the two drift-behavior probes must be
  re-confirmed green under the NEW args-based guard post-CA4 (§7bis-K).

Friction noted this session: `/tmp/opencode/ag-venv` no longer carries pytest
(the CA3 dev evidently used the system python3 user-site — pytest 9.1.1);
review ran the suite on `python3` with PATH=/tmp/opencode/bin. aislop `scan`
takes exactly one DIRECTORY arg — file-level scoping impossible; dir scan +
findings attribution is the working pattern (matches FRICTION entry).
