# PLAN: vLLM Priority follow-up — four-class priority (1/5/9 on vLLM, 10 off-vLLM)

feature: 2026/2026-11-cf-105-vllm-followup

## Goal

Amend the landed cf-105 Priority wiring from three classes to four: vLLM request
priorities **1** (urgent), **5** (default — the class unset/`null` now lands in; it
was 10), and **9** (new least-urgent ON-vLLM class) as three OpenCode catalog rows
over one wire model, plus priority **10** as the off-vLLM background class on
llama.cpp `qwen3.8-27b-q4` (replacing today's `4+` background routing). The
llama-swap peer floor follows the default class 10 → 5, and every contract surface
that states the class values (the single-authority class table, the favorited rows,
the runbook, the test pins, the golden) re-pins in lockstep. This is an amendment of
an existing, deployed wiring (cf-105, merged fcd5e35e3) — not a greenfield build;
the intake ruling (2026-11-06) supersedes cf-105 D6/HR2.

## The amended contract (supersedes cf-105 D6 / HR2)

| Card `Priority` | Class | Model row (this lab) | vLLM `body.priority` |
|---|---|---|---|
| `1`–`3` | urgent | `gpu-ai/qwen3.8-27b-vllm-urgent` | 1 |
| unset / `null`, `4`–`7` | default | `gpu-ai/qwen3.8-27b-vllm` | 5 |
| `8`–`9` | low | `gpu-ai/qwen3.8-27b-vllm-low` (NEW row) | 9 |
| `10`+ | background | `gpu-ai/qwen3.8-27b-q4` (llama.cpp — off vLLM, keeps KV headroom) | n/a |

- The four discrete values 1/5/9/10 are the modes (the four OpenChamber picker
  options — three vLLM catalog rows + the existing `qwen3.8-27b-q4` row). The board
  `Priority` field is a free NUMBER, so intermediate values snap to the class
  interval with midpoint boundaries (1–3→1, 4–7→5, 8–9→9, 10+→10), preserving
  cf-105's urgent range 1–3 verbatim. [OQ1]
- Polarity unchanged: lower = more urgent (vLLM's own convention, cf-105 R4). The
  peer floor `peers.vllm.filters.setParams "priority?"` is set-if-undefined and
  follows the DEFAULT class: 10 → 5 (non-priority clients land in the default
  class, never outrank it; a client-sent `priority` still wins).
- All three vLLM class rows share one wire `modelID` (`qwen3.8-27b-vllm`, the cf-105
  D10 pattern); only the row KEY + `body.priority` differ. New row key:
  `qwen3.8-27b-vllm-low` [OQ2].

## What changes vs what stays (cf-105 — read its folder first)

Amended: cf-105 **D6** (3-class table + floor 10) and **D10** (two class rows) by
the contract above; **HR2** stays on record as the superseded ruling.

Unchanged — verified live at branch tip 28a64cfe1:
- `charts/vllm` — NO change: `--scheduling-policy priority` already ships in
  serveArgs (charts/vllm/values.yaml L48-49); priority is per-request body, there is
  no engine-side constant to move.
- The `qwen3.8-27b-q4` catalog row and everything llama.cpp/Strata-side — the 10
  class is engine SELECTION (off vLLM), not a priority value.
- `.rulesync/skills/boards/SKILL.md` + `.rulesync/skills/pipeline-kickoff/SKILL.md`
  — cite-only: their priority text (roster bullet, kickoff bullet, launch prompt,
  `{raw, class}` record slot) is class-name-agnostic — no values, no `4+` — so it
  stays byte-identical (M7's boards/kickoff needles + the single-authority absence
  guard prove the absence).
- `.opencode/opencode.jsonc` outside the gpu-ai class rows (the `-urgent` row, the
  `q4` row, ~70 other rows), the machine-global config (no vllm rows there — gpu-ai
  is project-local; picker surface = this repo's catalog only), the `strata` peer,
  the matrix.

## Verified at plan time (branch cf-105-vllm-followup @ 28a64cfe1)

- Catalog rows: `.opencode/opencode.jsonc` L795-806 — `qwen3.8-27b-vllm`
  (body.priority 10, limit.context 262144), `qwen3.8-27b-vllm-urgent`
  (body.priority 1); `qwen3.8-27b-q4` at L553 (no body).
- Peer floor: `services/gpu-ai/prod/values.yaml` L556 `"priority?": 10` (block
  L536-556, comment L540 names "floor 10"); the rendered golden carries
  `priority?: 10` (charts/llama-swap/tests/golden/gpu-ai.config.yaml L1374); the
  testlib single-source literal `L.PEER_VLLM` pins the block
  (llama_swap_testlib.py L830); T1 asserts the floor (test_vllm_peer.py L30/L69).
- Class table: `.rulesync/skills/pipeline-models/SKILL.md` L43-49 (3 rows +
  polarity/floor sentence), favorited rows L59-61; generated twin in sync.
- Surface suite `tests/pipeline-models/surface.sh`: M3 pins the two catalog rows
  (L375 pair, L406 text); M4 pins the wire id in the serving authority (L419 —
  UNCHANGED here: the wire id is not new); M7 pins the table rows + floor 10 +
  catalog pairs + the `4+` single-authority guard (L620-682); M1's favorited-table
  order pin is structural (local rows first, L274-287) — an added gpu-ai row cannot
  break it.
- Runbook `.agents/notes/vllm-on-target-acceptance.md`: names block L38-39, §5
  preamble L270-274 (floor 10; urgent 1 / default 10), 5.1 explicit `priority: 5`
  (L276-286), 5.3 two-class preemption proof (L303-317); its suite
  `tests/notes/vllm-runbook.sh` pins T3 `for v in ("1", "10")` + `floor != 10`
  (L217-223) and T5 needles `priority: 5` / `qwen3.8-27b-vllm-urgent` (L356-360).
- cf-105 record: plan D6/D10/HR2 + Commands, RESEARCH R4 (vLLM priority mechanics:
  int64 body field, lower = earlier, forced-recompute preemption victim =
  lowest-priority runner, `?` set-if-undefined filters, model-row `body` carrier),
  chunks C03/C04 (the exact test contracts + the cf-83 re-pin posture), final
  review (constants branch-wide consistent: 1/10 + floor 10, 262144, wire name).

## Out of scope

- Any `charts/vllm` change (verified unnecessary).
- Any llama.cpp/Strata config, matrix, or the `strata` peer block.
- The `X-Vllm-Priority` header carrier (cf-105 R4 chose the body carrier; the
  header is an alternative, not a second surface to wire).
- OpenChamber-side configuration (it surfaces the provider catalog — the catalog
  rows ARE the surface, per the intake ruling).
- The cf-105 follow-up cards (GPU exporter, alerts, 8060S, selectors) — untouched.
- Board ops of any kind (chat run — no board card exists for this ticket; no
  card write-back, no `priority: {raw, class}` record).

## Commands

`export PATH=$HOME/.local/bin:$PATH` first (helm v3.16.4; without it the
helm-guarded pytest mass-skips silently). No unit-test suite exists for engine
behavior — these are the repo validations (cf-105 Commands precedent); the
on-target runbook stays operator-run post-merge.

```
# C01 (the wire)
python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml'))['llama-swap']; yaml.safe_dump(d, open('/tmp/gpu-ai-vals.yaml','w'))"
helm template llama-swap charts/llama-swap -f /tmp/gpu-ai-vals.yaml --set domain=spencerslab.com --set clusterName=gpu-ai --set bitwardenIds.hf-token=test-uuid --show-only templates/configmap-llama-swap.yaml
python3 -m pytest charts/llama-swap/tests -v
bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M6   # C01 subset — M7 stays C02's designed-red (cf-83 posture)

# C02 (the contract text)
rulesync generate                # only the pipeline-models twin may change
rulesync generate --check
bash tests/pipeline-models/surface.sh            # full M1..M7 after C02

# C03 (the runbook)
bash tests/notes/vllm-runbook.sh                 # T1-T5 after C03

# final whole-plan review re-runs the whole set
python3 -m pytest charts/llama-swap/tests -v
bash tests/pipeline-models/surface.sh
bash tests/notes/vllm-runbook.sh
npx aislop ci --changes            # repo quality gate (CI runs it on the PR)
```

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | the wire — peer floor 10→5 + catalog rows (default 10→5, NEW low row 9) + golden re-capture | M | 1 | [] | — |
| C02 | the contract text — pipeline-models 4-class table + favorited rows + rulesync + M7 re-pin | M | 2 | [C01] | the single-authority table must equal C01's carriers cell-for-cell (row ids, values, floor) — the cf-105 C04-on-C03 reason |
| C03 | the runbook — 4-class constant sync + vllm-runbook.sh re-pin | S | 2 | [C01] | its constants are C01's wire values; independent of C02 (different files, different suite, no coupling) |

## Wave order

1. C01 (the wire lands first — the contract text and the runbook describe it)
2. C02, C03 (independent of each other; run in id order)

Test Writing is ONE `agent-test` session after planning, re-pinning every chunk's
test pins (test_vllm_peer.py T1, llama_swap_testlib.py `L.PEER_VLLM`, surface.sh
M3 + M7, vllm-runbook.sh T3 + T5) BEFORE any dev runs — cf-83 re-pin posture:
after the test session, M3/M7/T3 are designed-red until C01/C02/C03 land; a test
judged faulty routes back to the test session, never to the reviewer.

## Risks / assumptions

- **Intended behavior change:** the default class now sends `body.priority` 5
  instead of 10, and the peer floor is 5 — non-priority clients (no `priority` in
  the body) now land in the default class at 5 instead of 10. Under KV exhaustion
  vLLM's preemption victim order becomes low(9) → default(5) → never urgent(1);
  the old most-preemptible-on-vLLM value 10 no longer exists. This is the user's
  ruling (DECISIONS).
- **Legacy board values re-classify:** an existing card `Priority` 4–9 (the old
  `4+` background range) resolves to ON-vLLM classes on its next run (4–7 →
  default, 8–9 → low); the true off-vLLM tier is now 10. [OQ1]
- **Golden churn (C01):** the rendered gpu-ai config changes by exactly one line
  (`priority?: 10` → `5`); the golden re-capture is the designed response (cf-105
  C03 precedent); the gpu-cluster golden stays byte-identical.
- **Deploy effect:** the llama-swap ConfigMap content changes ⇒ ArgoCD redeploys
  the llama-swap pod on sync (no kubectl, no chart change). The vLLM pod is
  untouched.
- **No engine re-verification in-session:** the priority mechanics rest on
  cf-105 R4 (int64 field, no 0–100 range, non-zero legal under
  `--scheduling-policy priority` — 1/5/9 all legal). If dev/review surfaces a
  value-range constraint R4 did not cover, it is reported, not guessed.

## Open questions — ANSWERED (2026-11-06 approval round; rulings land in
DECISIONS)

- **OQ1 — legacy/intermediate board values (2, 3, 4, 6, 7, 8).** **MIDPOINT
  SNAP, CONFIRMED by the user:** 1–3→urgent(1), 4–7→default(5), 8–9→low(9),
  10+→background(10) (D4 stands as written; the alternative — legacy 4–9 stays
  off vLLM at 10 — was offered and not chosen). The picker offers exactly the
  four discrete values either way.
- **OQ2 — new row/class naming.** **As written:** row key
  `qwen3.8-27b-vllm-low`, class `low`, catalog name "… - low priority"
  (approved as written; alternatives `-least` / `-background-vllm` rejected —
  "background" is reserved for the off-vLLM 10 tier).
- **OQ3 — runbook 5.3 saturation proof.** **As written:** keep the two-class
  (urgent vs default) proof, add one line stating the four-class victim order
  (low → default, never urgent) (approved as written).

## Locked decisions (full evidence log in DECISIONS.md)

- **D1 — four classes** per the intake ruling: 1 urgent / 5 default / 9 low /
  10 background-off-vLLM. Supersedes cf-105 D6 + HR2.
- **D2 — default class value + peer floor = 5** (the floor follows the default
  class — set-if-undefined).
- **D3 — NEW catalog row** `qwen3.8-27b-vllm-low` (shared wire `modelID`,
  body.priority 9, limit.context 262144 — the sibling row shape).
- **D4 — snap intervals** 1–3 / 4–7 / 8–9 / 10+ (the OQ1 best guess).
- **D5 — `charts/vllm` untouched** (verified: the scheduling-policy flag already
  ships; priority is per-request body).
- **D6 — boards + pipeline-kickoff skills untouched** (cite-only; verified
  class-name-agnostic); only pipeline-models carries the mapping.
- **D7 — chunking:** 3 chunks, 2 waves (C01 wave 1; C02/C03 wave 2, independent).

## Run protocol (chat run — no board card)

- Worktree + branch `cf-105-vllm-followup` PRE-EXIST (branch on the main tip with
  cf-105 merged, fcd5e35e3); not re-minted, not moved (coord ruling).
- Models: both tiers `openrouter/qwen/qwen3.8-27b` (local: false) — the blank-card
  default `gpu-ai/qwen3.8-27b-q4` answered 503 "no available server" twice at
  launch; the run falls back to the hosted dense route per pipeline-models (the
  same route cf-105's own run used). Recorded in DECISIONS; this plan's RESULT
  says so.
- The plan-approval pause (this presentation) is the user-facing gate; on approval
  `plan_status` flips to approved. PR + merge are human-owned; ArgoCD applies
  everything — no kubectl.
- Exploration stage SKIPPED (coord ruling — the ground is fully scouted by the
  cf-105 artifacts above); no research commissioned (cf-105 R4 already covers the
  vLLM priority mechanics this amendment rides).
