# PARALLEL-DRAFT — captured sibling plan artifacts (NOT the plan of record)

Provenance: planning for this ticket launched twice in parallel (the coordinator's own FRICTION
rows, 2026-11-22: "planning launched twice, both hand-backs reported cancelled"). The sibling
session wrote a FOUR-chunk plan + its C01/C02 chunk files; the coordinator ruled this re-launch
owns the fold ("planner owns the plan file; the coordinator does not edit it"). This file captures
the sibling's three clobbered artifacts VERBATIM so the record survives (annotate-never-rewrite,
applied to a colleague's work); the kept plan of record
(`2026-11-22-feat-radiance-multi-instance.md`, 6-chunk shape) absorbs its verified facts, its
sanitizer-port proof, its word-boundary grep pattern, the TEST_SPEC.md history-site finding, and
its OQ-A/OQ-I/OQ-K framings. The two plans agreed on: rename atomicity, routing-site inventory,
four-lane roster mechanism, never-default law, owner-receipt legs, landing shape. The differences
(chunk order rename-vs-routing-first; wave-1 independence; the 4-vs-6 chunk split) are recorded in
DECISIONS D12. This capture is a RECORD, not a plan file; the plan of record stays singular.

---

## [sibling] 2026-11-22-feat-radiance-multi-instance.md (as it stood 2026-11-22 ~00:31Z)

# feat-radiance-multi-instance — Radiance routing, pool rename, four-lane fleet

- Plan of record. Planner session `ses_e012e8e56ffeAZSKwAKhGDCoL3`, 2026-11-22. Base `193c12798` (= main = origin/main, cf-144 landed).
- Ground: `EXPLORE.md` (scout) + `RESEARCH.md` (researcher) in this folder. Prior law: cf-143 `DECISIONS.md` D1–D29, cf-144 `DECISIONS.md` P01–P17 (annotate, never rewrite).
- Owner-directed in-session ticket (no board card). Deployment legs (push/PR/merge/sync) are owner-only; nothing in this plan lands `main`.

## Goal

Five owner asks, landed as one ticket in four chunks:

1. **Routing surface → Radiance**: route all coordinator/subagent model surfaces to `gpu-ai/qwen3.8-flash-next-radiance` (the dense-local + flash-local default rows of the `pipeline-models` skill family), matching what this run actually does.
2. **Pool rename**: `amd.com/gpu-r9700-1` → `amd.com/gpu-r9700` in ONE atomic GitOps wave (ids-table row + every live claim + tests/docs together — the plugin reads its table once at startup, so a split wave means nodes with mismatched names).
3. **Explicit per-release GPU assignment** for the llama-swap/strata engine — shaped as owner-ruling options, because specific-card pinning is structurally impossible in the device-plugin path (RESEARCH R-Q1/R-Q4: the plugin allocates lowest-KFD-index-first, no per-pod card choice; only pool membership + advisory UUID env exist).
4. **Four-lane fleet**: restructure `charts/radiance` into a fully generic shell (args/settings from per-instance config) deployed 4×: flash-TP2 (replicas 1 — the live fn lane), flash-TP1 (0), 27b-TP2 (0), 27b-TP1 (0 — the live q27 lane).
5. **Landing order vs cf-144**: its TP2 chart-arg literals become per-instance DATA in this restructure; its notes/DECISIONS are annotated, never rewritten.

## Verified facts (planner checks at base `193c12798`)

- **Rename mechanism** (not archaeology — the derivation is ported in tests): `charts/amd-gpu/values.yaml:225` carries the patched-table row `7551, C0, r9700-1`; the plugin sanitizer maps the product field → `gpu-<tokens>`, so the node advertises `amd.com/gpu-r9700-1`. Verified port runs: `sanitize('r9700') == 'gpu-r9700'` (the target name IS reachable by the mechanism — change the row's product field to `r9700`), `sanitize('AMD Radeon AI PRO R9700') == 'gpu-ai-pro-r9700'` (the HISTORICAL constant's derivation stays intact). Canonical needle home: `charts/amd-gpu/tests/amd_gpu_testlib.py:45-62` + the marked block in `tests/services/amd-gpu-naming.sh:60-71` (`R9700_CLAIM="amd.com/gpu-r9700-1"`).
- **Rename blast radius** (`git grep -c "r9700-1" -- ':!.agents/plans'` = 19 files): charts/amd-gpu (values + testlib + test_provenance + evidence), charts/radiance (values + test_q27_lane + test_resource_name_identity + NOTES.txt), charts/llama-swap (1 comment line + TEST_SPEC.md history), services/gpu-ai/prod/values.yaml (7), tests/notes (radiance-runbook 4, radiance-tp2 3, radiance-q27-boot 2), tests/services/amd-gpu-naming.sh (1), .agents/notes (27 lines across 4 docs).
- **AC4 zero-stale + n3 carrier law interact with the rename**: `test_provenance.py:326-434` asserts the rejected name appears nowhere via an ASSEMBLED literal (`impossible = "amd.com/" + "r9700-1"` style — post-rename the assembly target flips to the retired name) and an allow-list (`_NEW_NAME_ALLOW`); `amd-gpu-naming.sh` n3 (`:280-310`) pins which files may carry the pool name claim-shaped. Both flip in C02.
- **Routing surface sites** (EXPLORE §1): `.rulesync/skills/pipeline-models/SKILL.md` (blank-default :16-17, combination rows :34-37, favorited :43-50, class table :61-64), `pipeline-kickoff` (:20-27), `boards` (:252-270 default-checked line), `.opencode/opencode.jsonc` catalog (fn trio :553/:684 area, q27 trio :716-790), mirrored `.opencode/skills/**` (rulesync-generated — edit sources, regenerate).
- **Pre-existing reds at base** (measured 2026-11-22): `tests/provider-loops/surface.sh` t1 and `tests/agent-board-coord/agents-md.sh` c11 are RED — they pin runner literal `gpu-ai/qwen3.8-27b-q4` while `.agents/loops/pipeline-worker.md:5` carries `gpu-ai/qwen3.8-flash-next-strata-q4` (the 2026-11-09 owner ruling moved the loop but not these two pins; cf-144 STATE records the ruling). `tests/opencode/pipeline-locks-tick.test.ts:163` pins strata-q4 and is GREEN. All three sit in C01's disposition set.
- **M8-H anti-sync leg** (`tests/pipeline-models/surface.sh:1056-1068`): env-gated on `CF143_BASE_SHA`; fails if `.rulesync/rules/overview.md` or `.agents/loops/pipeline-worker.md` were touched. Under the OQ-A best guess (runner literal NOT moved) C01 touches neither, so it stays honest; under a full-sweep ruling it must be re-shaped (C01 test spec covers both shapes).
- **Roster mechanism** (`charts/base/templates/appset-charts.yaml:15-70`): each `charts:` key yields one Application named `<serviceName>-<appName>`; a `chart:` key (appset-charts.yaml:67-70; q27 precedent `:96-105`) renders a second release from an existing chart dir — **the 3rd/4th lane are pure values entries, no base-chart change**. Top-level block named as the key ships as that release's values (`values: merge $extraValues (index $.Values $appName)`); release name → Service DNS → the peers proxy hop.
- **Per-instance args today**: q27 already does WHOLE-LIST replacement of `controllers.radiance.containers.radiance.args` + its own init fetch script (`services/gpu-ai/prod/values.yaml:900-1063`); the fn lane keeps chart-side literals (`charts/radiance/values.yaml: serveArgs anchor :187-204, fetch env LFS_SHA/PACK/URL :396-399, claims `amd.com/gpu-r9700-1: "2"` :346-353, `tp: 2` :100, `guaranteedMemoryGi: 110` :90 — P11 HOLD-110). App-template list-merging = replacement, which is exactly the generic-shell mechanism already proven on this chart.
- **Resource identity**: releases `gpu-ai-radiance` / `gpu-ai-radiance-q27` coexist in ns `default` today with the chart's `nameOverride: radiance` (:207); `charts/radiance/tests/test_resource_name_identity.py` pins per-release object uniqueness. New lanes need no new chart dir and no override churn — the two-branch law extends to four.
- **Served ids (exact)**: fn `qwen3.8-flash-next-radiance` (charts/radiance/values.yaml:204), q27 `qwen3.8-27b-radiance` (services file :964; evidence `radiance-peers-expected.yaml` / `radiance-q27-peers-expected.yaml` pin both).
- **Claim math (node has exactly 2 R9700s)**: pool capacity is 2 after the rename wave (the rename changes the NAME only; count stays 2). fn TP2 claims 2 → while fn is UP, zero cards remain: every other lane scaling to 1 Pends (loud, by design — D57 idle-honesty law). The scale order law survives verbatim: "fn DOWN first, then the other lane UP".
- **Card pinning is impossible in this path** (RESEARCH R-Q1/R-Q4): the plugin hands out the lowest-KFD-NodeId card deterministically (advisory, source-pinned v1.31.0.12); `ROCR_VISIBLE_DEVICES` (KFD indices or `GPU-<16hex>` UUID prefixes, SILENT truncation on bad tokens) is the only per-container lever and only in the hostPath path — strata's 2026-10-27 hostPath ruling is why strata holds NO claim today. UUID pinning is gated on OQ-R1 (nonzero `unique_id` on this silicon).
- **CI shape**: `charts/radiance/tests/` already runs in `.github/workflows/radiance-render-tests.yaml` whose trigger paths `test_contract.py` pins exactly — new lane coverage lands as suite files inside `charts/radiance/tests/` (no trigger-path additions; `tests/` sibling dirs would fire NO workflow).

## Design rulings (planner drafts; owner confirms via the batched round — DECISIONS.md P02–P10)

1. **Generic shell = scalars + per-release whole-list blocks, no template magic**: the chart keeps structure (image/pack ledgers as PARAMETERIZED scalars — PACK/LFS_SHA/URL/MARKER per instance — probes, persistence, security, BusyBox-portable hash gate) and lane-NEUTRAL defaults; every lane's block in `services/gpu-ai/prod/values.yaml` carries its own args list, fetch-script env, claims count, replicas, memory scalars (P03). The fn/q27 renders must be BYTE-IDENTICAL across C03 (the anchor trap dies with the anchor).
2. **Four lanes / four releases / one chart dir** (extends D56(1)): roster keys `radiance` (fn TP2, replicas 1, claim 2), `radiance-flash-tp1` (0, claim 1), `radiance-27b-tp2` (0, claim 2), `radiance-q27` (0, claim 1 — as today). Proposed served ids for the two new wires: `qwen3.8-flash-next-radiance-tp1`, `qwen3.8-27b-radiance-tp2` (OQ-G).
3. **Rename is a pure mechanism change** (row product field `r9700-1` → `r9700`), not a manual override — the sanitizer port stays the derivation engine (P04).
4. **Sequencing: routing → rename → shell → fleet** (validates the scout hint with reasons): the routing wave is skill/test-only and touches nothing GPU-shaped; the rename wave must be ONE sync and must land before the fleet wave so the fleet's four new claim blocks are authored once against the FINAL name (authoring them pre-rename would plant four more stale-needle sites); the shell restructure precedes the new lanes so the lanes are born generic. The two pre-existing reds ride the routing wave (their subject is the runner literal — same semantic surface), not the rename.

## Chunk table

| Chunk | Wave | Subject | Main files | Predecessor |
|---|---|---|---|---|
| C01 | 1 | Routing-surface re-author to `gpu-ai/qwen3.8-flash-next-radiance` + pre-existing-red disposition | `.rulesync/skills/{pipeline-models,pipeline-kickoff,boards}/SKILL.md` + regenerate; `tests/pipeline-models/surface.sh` (M1/M2/M4/M5/M8 needles); `tests/provider-loops/surface.sh` (t1/t3); `tests/agent-board-coord/agents-md.sh` (c11) | — |
| C02 | 2 | GPU pool rename wave `amd.com/gpu-r9700-1` → `amd.com/gpu-r9700`, atomic | `charts/amd-gpu/values.yaml` (row :225); `charts/amd-gpu/tests/{amd_gpu_testlib.py,test_provenance.py,test_render.py}`; `charts/radiance/{values.yaml,tests/test_q27_lane.py,tests/test_resource_name_identity.py,templates/NOTES.txt}`; `services/gpu-ai/prod/values.yaml` (7); `charts/llama-swap/values.yaml` (comment); `tests/{services/amd-gpu-naming.sh,notes/*.sh}`; `.agents/notes/*` docs | C01 |
| C03 | 3 | Generic-shell restructure of `charts/radiance` (byte-preserving) | `charts/radiance/values.yaml` (args/claims/fetch-env genericized); `services/gpu-ai/prod/values.yaml` (fn + q27 blocks carry lane data); `charts/radiance/tests/*` re-pin | C02 |
| C04 | 4 | Four-lane fleet: 2 new Applications + peers + catalog + evidence + contract suite + docs | `services/gpu-ai/prod/values.yaml` (roster + 2 lane blocks + 2 peers hops); `charts/llama-swap/tests/evidence/*` (2 new floors); `.opencode/opencode.jsonc` (2 catalog trios + favorited rows); `charts/radiance/tests/test_lanes.py` (new); notes/runbook annotation pass | C03 |

Each chunk: agent-test writes its suite updates BEFORE dev (one test session), dev implements + runs the battery, review re-runs it. Coordinator commits each approved chunk on branch `feat-radiance-multi-instance` (worktree already in place; no Worktree-Creation stage — worktree `feat-radiance-multi-instance` exists).

## Commands (validation battery — run with `export PATH=$HOME/.local/bin:$PATH`)

Global gates (every chunk's dev + review run these; a suite unrelated to the chunk's edits must also stay green):

1. `bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M6 M7 M8` (M8 must be named explicitly; leave `CF143_BASE_SHA` unset except at final review, where the reviewer sets it to the merge-base and re-runs M8).
2. `bash tests/provider-loops/surface.sh` — RED at base (t1); GREEN from C01 on.
3. `bash tests/agent-board-coord/agents-md.sh` — c11 RED at base; GREEN from C01 on (after `npx rulesync generate` if the rules source moved).
4. `npx rulesync generate && npx rulesync generate --check` (C01; sources + generated committed together).
5. `helm lint charts/amd-gpu && helm template charts/amd-gpu >/dev/null && python3 -m pytest charts/amd-gpu/tests -q` (C02+).
6. `helm lint charts/radiance && helm template charts/radiance >/dev/null && python3 -m pytest charts/radiance/tests -q` (every chunk touching the chart).
7. `bash tests/services/amd-gpu-naming.sh` (C02+: n1–n5 re-pinned; also run bare — it's the bash-side naming carrier law).
8. `bash tests/notes/radiance-tp2.sh && bash tests/notes/radiance-runbook.sh && bash tests/notes/radiance-q27-boot.sh` (docs-needle legs ride their chunk).
9. `python3 -m pytest charts/llama-swap/tests -q` (peers/evidence law; C01 catalog-adjacent prose must not break it; C04 extends it).
10. `git grep -n "gpu-r9700-1" -- ':!.agents/plans'` → after C02, only allow-listed historical evidence/annotated history lines (C02's AC4 sweep is the authority; grep is the quick mirror).
11. C03 byte-preservation: capture `helm template` pod args/init-env/claims for both live lanes at the C02 tip vs the C03 tip and diff → EMPTY (test-writer encodes this as a suite leg, harness its choice).
12. C04 lane battery: four `helm template` renders (one per roster key, `-f` block extracted from the services file exactly as appset-charts.yaml does it) pinning per-lane args equality, claims {flash-tp1,q27}: "1", {fn,27b-tp2}: "2", replicas {1,0,0,0}, served-model-name uniqueness across the four, and `grep -c "chart: radiance" services/gpu-ai/prod/values.yaml` == 3.

No unit-test suite exists; items 1–12 ARE the tests. Docker builds: n/a (no container chunks). No chart version bumps — `release.yaml` owns versions (hard rule).

## Owner legs inside this ticket (not agent-executable)

- **OQ-R1 receipt** (gates ask-3 acceptance): on ai-gpu, `grep -H . /sys/class/kfd/kfd/topology/nodes/*/properties | grep unique_id` (or `rocm-smi --showuniqueid`) — UUID pins are asserted only if unique_id is nonzero on both R9700s. Lands inside C01's question round; the values-UUID-pin follow-on (if any) is a separate owner-approved leg.
- **OQ-R2 receipt**: KFD-index ↔ UUID ↔ PCIe mapping for both cards (`rocminfo` block per node) — the evidence that makes ROCR-index comments true on THIS host.
- **Deployment**: push of `feat-radiance-multi-instance`, PR creation, merge, and the gpu-ai SYNC (manual-sync apps) are owner-only. The rename's atomicity property to preserve through deploy: ONE sync carries ids-table row + all claims (the plugin table reads once at pod start; claims against a name the plugin no longer advertises leave pods Pending).

## Risks

- **Rename mid-window straggler**: between the sync that renames the table and the DaemonSet rollout finishing, a pod could request a stale name and sit Pending (loud, self-healing at rollout completion). Accepted, documented in the runbook (C02 doc pass).
- **Anchor trap in reverse** during C03: YAML anchors in the chart values resolve per-document; a half-genericized shell could ship fn args carrying a q27 path or vice versa. Byte-preservation leg (Command 11) is the fence.
- **Pinned-needles sprawl**: the four-lane fleet multiplies M8 frozen sets (evidence floors, catalog trio HOLD, peers set-equality). C04's test-writer extends the freezes deliberately; never loosen them silently.
- **Board vocabulary drift**: `boards` SKILL Model(s) option strings name `gpu-ai/qwen3.8-27b-q4` / `-strata-q4`; the WeKan card checklist itself is provisioned from `scripts/provision-board.py` and is NOT edited here — option strings stay board-vocabulary, mapping authority moves in pipeline-models. Flagged for owner (OQ-H includes the board-vocabulary follow-on).
- **Routing to 0-replica lanes**: catalog rows for TP1/27b-TP2 lanes route to a 502 peer proxy while parked (D57 idle honesty, same as q27 today). Loud by design; priorities (OQ-I) keep live lanes preferred.
- **M8-H under a full-sweep OQ-A answer**: if the owner moves the runner literal too, M8-H flips from "never touched" to a pairing leg and `pipeline-locks-tick.test.ts:163` re-pins; C01's test spec pre-authorizes that rewrite shape so no second planning round is needed.

## OPEN QUESTIONS (batched round — answers ride the plan-approval word; each carries the planner best guess)

- **OQ-A (runner literal)**: Does "route everything to Radiance" move the hourly-loop runner literal (`.agents/loops/pipeline-worker.md`, currently `gpu-ai/qwen3.8-flash-next-strata-q4` by the owner's 2026-11-09 ruling) too? *Best guess: NO* — that literal is owner-ruled separately ("moves only by a fresh user ruling") and "coord/subagent surfaces" means the routing skills; C01 instead re-pins the three stale test pins to the live strata-q4 byte. *If wrong*: C01 additionally edits the loop file + rules source + regenerates AGENTS.md, re-shapes M8-H, re-pins the TS test — one extra commit, same chunk.
- **OQ-B (ask-3 shape)**: Accept option (a) for strata's explicit GPU assignment — keep hostPath, spell the ROCR assignment explicitly in values with comment receipts, no claims — pending the OQ-R1 receipt before any UUID pin is asserted? *Best guess: YES* (option (b) real claims = a DECISIONS reversal of the 2026-10-27 ruling; option (c) DRA is a watch-list, RESEARCH R-Q6).
- **OQ-R1 (owner exec)**: `unique_id` nonzero on both R9700s? (Command above; the gate for `GPU-<uuid>` pins — never asserted blind.)
- **OQ-R2 (owner exec)**: KFD-index ↔ UUID ↔ PCIe map for both cards (rocminfo receipt) — makes index-vs-UUID comments verifiable.
- **OQ-R3 (rename wave shape)**: one in-ticket wave (C02) rather than a separate ticket? *Best guess: YES* (RESEARCH recommendation; the atomicity requirement argues against splitting across tickets).
- **OQ-R4 (DRA)**: keep DRA as a watch-list note only (revisit triggers in the runbook: multi-card pin demand or driver UUID support)? *Best guess: YES, no code.*
- **OQ-G (lane names/ids)**: releases `gpu-ai-radiance-flash-tp1` / `gpu-ai-radiance-27b-tp2`; served ids `qwen3.8-flash-next-radiance-tp1` / `qwen3.8-27b-radiance-tp2`; existing fn/q27 ids unchanged. *Best guess: as proposed* (pattern-consistent, honest TP suffix per D7).
- **OQ-H (pre-existing reds + board vocabulary)**: disposition = re-pin t1/t3/c11 (and keep the TS pin) to the live runner byte, WITHOUT touching the loop/rules bytes themselves; the WeKan card checklist vocabulary (option strings naming the old ids) gets a separate owner-owned provisioning follow-on, not an in-ticket board write. *Best guess: YES.*
- **OQ-I (catalog priorities for new lanes)**: two new catalog trios registered NOW (lanes parked at 0 — routing gives loud 502s) with strictly-below-live priorities, unique per class column across the radiance family (proposal: flash-tp1 7/3/2, 27b-tp2 6/2/1 — test author resolves uniqueness)? *Best guess: register now* (deploy-ready parity with q27's precedent). Alternative: park rows commented until the lanes boot.
- **OQ-K (explicit Dense+Local row)**: the BLANK default moves to Radiance for both tiers; when a card explicitly checks `Models → Qwen Dense`, does Dense+Local keep routing to `gpu-ai/qwen3.8-27b-q4` (strata, up with capacity) or move to `gpu-ai/qwen3.8-27b-radiance` (q27, parked at 0 → loud 502 until scaled)? *Best guess: keep strata's live 27b-q4 row* — "everything → Radiance" is read as the defaults/blank path, and an explicit Dense request that 502s until a manual scale is a trap. If the owner wants radiance-for-dense-too, it is a one-line needle change in the same suite.
- **OQ-J (claim/scale math confirmation)**: steady state replicas {fn-TP2: 1, flash-TP1: 0, 27b-TP2: 0, 27b-TP1(q27): 0}; claims {fn: 2, 27b-TP2: 2, flash-TP1: 1, q27: 1}; while fn is UP every scale-up of any other lane Pends until fn scales down ("fn DOWN first" law). *Best guess: owner accepts this as the designed steady state* (it is the arithmetic of a 2-card node, not a defect).

## Landing shape

Coordinator commits C01→C04 locally on `feat-radiance-multi-instance` (one commit per chunk + generated artifacts with their source; nothing pushed, nothing merged — owner's PR is the landing vehicle). Plan status: `draft` until the owner's batched answers; post-approval write-back is the coordinator's leg. Final whole-plan review runs the full battery incl. M8 with `CF143_BASE_SHA` set to the merge-base.

---

## [sibling] chunks/C01.md (Routing) — as it stood

# C01 — Routing-surface re-author to Radiance + pre-existing-red disposition

Wave 1. Predecessor: none. Skills edited in `.rulesync/` sources ONLY, regenerated with `npx rulesync generate` (generated mirrors committed in the same commit — hard rule).

## Goal

Every coordinator/subagent routing default resolves to `gpu-ai/qwen3.8-flash-next-radiance`; the two pre-existing red suites (provider-loops t1/t3, agents-md c11) are dispositioned per the OQ-A/OQ-H answers so the suite floor is fully green after this chunk.

## Scope / files

- `.rulesync/skills/pipeline-models/SKILL.md`:
  - blank-Model(s) default (both tiers) → `gpu-ai/qwen3.8-flash-next-radiance`;
  - combination rows: Flash+Local → `gpu-ai/qwen3.8-flash-next-radiance` (was `-strata-q4`); Dense+Local keeps its explicit dense row `gpu-ai/qwen3.8-27b-q4` (the dense-local route still exists — strata serves it and q27 serves `qwen3.8-27b-radiance`; the row is an explicit-request route, not a default) UNLESS the owner's answer to OQ-A widens the sweep;
  - favorited row (Radiance lane) → re-point to `qwen3.8-flash-next-radiance` priority-coherent with the catalog;
  - class table value column stays engine-scoped; radiance rows' ids unchanged (they are catalog ids, C04 touches them).
- `.rulesync/skills/pipeline-kickoff/SKILL.md`: the Flash+Local restatement (:20-27) re-pins to `qwen3.8-flash-next-radiance`; "never restate its table here" law respected — only the literal moves.
- `.rulesync/skills/boards/SKILL.md`: default-checked Model(s) line (:263) → the Radiance option; `Qwen Dense (gpu-ai/qwen3.8-27b-q4)` stays as the named alternate (:264 pattern). Board option STRINGS are not rewritten (board vocabulary, OQ-H follow-on).
- NOT touched under the OQ-A best guess: `.agents/loops/pipeline-worker.md`, `.rulesync/rules/overview.md`, `AGENTS.md`, `.opencode/opencode.jsonc` (catalog ids are lane ids, not routing defaults — C04 owns catalog rows).
- Tests re-authored (test session FIRST):
  - `tests/pipeline-models/surface.sh`: M1 blank-default needles, M2 combination needles, M4 favorited needles, M5/M8 legs that quote the moved strings, and the M8-F strata-KEEP needles re-scoped to what SURVIVES (the explicit dense row + any strata mention kept by ruling). Under an OQ-A full-sweep answer: additionally M8-H becomes a pairing leg (loop byte == rules byte == pinned literal), `pipeline-locks-tick.test.ts:163` and the t1/t3/c11 pins move to the new literal, and the loop + rules sources join the file set.
  - `tests/provider-loops/surface.sh` t1 (:183-187) + t3: re-pin `model=` needle `gpu-ai/qwen3.8-27b-q4` → `gpu-ai/qwen3.8-flash-next-strata-q4`, message records the 2026-11-09 ruling chain (cf-86 → cf-106 OQ-14 → 2026-11-09) and this re-pin's reason.
  - `tests/agent-board-coord/agents-md.sh` c11 (:580-595): same re-pin against `.rulesync/rules/overview.md`'s existing strata-q4 byte.

## Acceptance criteria

1. `bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M6 M7 M8` fully green (M8 bare, `CF143_BASE_SHA` unset).
2. `bash tests/provider-loops/surface.sh` green (base: t1 RED — the suite exits 0 today by `set -e`-less tail; require exit 0 AND zero FAIL lines).
3. `bash tests/agent-board-coord/agents-md.sh` green incl. c11.
4. `npx rulesync generate --check` clean; `git diff` shows source+mirror pairs together; the four generated mirrors of the three edited skills contain the new literals.
5. `python3 -m pytest charts/llama-swap/tests -q` and `python3 -m pytest charts/radiance/tests -q` stay green (byte-untouched, regression fence).
6. No GPU-pool string, loop file, or catalog row changed in this chunk's diff.

## Commands

See plan §Commands 1–5, 9. PATH export mandatory.

## Owner legs inside C01

- Batched plan-questions round (plan OQ-A/B/R1/R2/R3/R4/G/H/I/K/J) — coordinator collects before chunk dev starts; answers fold into DECISIONS.md as P-rows.
- OQ-R1/OQ-R2 receipts may arrive later; they gate C04's UUID-pin decisions, not this chunk's code.

---

## [sibling] chunks/C02.md (Rename) — as it stood

# C02 — GPU pool rename wave: `amd.com/gpu-r9700-1` → `amd.com/gpu-r9700` (atomic)

Wave 2. Predecessor: C01. One commit = one GitOps wave: the ids-table row and EVERY live claim ship together, because the plugin reads its patched table once at startup (subPath ConfigMap mount never live-updates — EXPLORE §2) and claims against a name nobody advertises sit Pending.

## Goal

The ai-gpu node advertises `amd.com/gpu-r9700` (count 2) and nothing claim-shaped anywhere in the repo still says `amd.com/gpu-r9700-1`. Pure derivation change — the row's product field becomes `r9700` so the plugin sanitizer produces the new name (verified at planning: `sanitize('r9700') == 'gpu-r9700'`, `amd_gpu_testlib.py:181-202` port); no manual-override escape hatch is added.

## Scope / files

- `charts/amd-gpu/values.yaml`: row `7551, C0, r9700-1` → `7551, C0, r9700` (:225); the header/derivation comments (:32-47, :182-202) updated with a dated rename line (annotate style — the D24 history stays readable); `amd.com/gpu-8060s` and the bare-`amd.com/gpu` fallback law UNTOUCHED (D24 scope freeze).
- `charts/amd-gpu/tests/amd_gpu_testlib.py` (:45-62 block): `R9700_POOL_NAME` → `"r9700"`; `HISTORICAL_R9700_POOL_NAME` stays `"ai-pro-r9700"` (its sanitizer-derivation leg must still hold); NEW retired-name constant ASSEMBLED (`RETIRED_R9700 = "gpu-" + "r9700-" + "1"`-style) so the zero-stale sweep's own file cannot smuggle the literal; every derived needle (`R9700_CLAIM` etc.) recomputes from the constant.
- `charts/amd-gpu/tests/test_provenance.py` (:326-434): data-row assertion `r9700-1` → `r9700`; `impossible`/zero-stale assembly flips target to the RETIRED name and `_NEW_NAME_ALLOW` is re-scoped: pre-rename historical evidence (`charts/amd-gpu/tests/evidence/pre-c08-amdgpu-ids-rows.txt`) joins the allow-list as an immutable snapshot; plan/notes folders stay out of sweep scope (they are git-excluded or annotated).
- `charts/amd-gpu/tests/test_render.py`: any rendered-name needle rides the testlib constants — verify, re-pin only literals.
- `charts/radiance/values.yaml`: claims pair :346-353 to `amd.com/gpu-r9700: "2"`; the stale "each pool holds one device" comment :157 corrected while passing through; any `r9700-1` comment mention re-pinned (7 hits).
- `charts/radiance/tests/`: `radiance_testlib.py` claim constants; `test_q27_lane.py:165,226,258` overlay-pin prose+needles; `test_resource_name_identity.py:40,141` docstrings+needles; `templates/NOTES.txt` 1 hit.
- `services/gpu-ai/prod/values.yaml` (7 hits): the amd-gpu roster comment :52-55, the q27 overlay claims (both maps) and the switch-discipline header comments — historical dated bullets get a one-line appended rename note (annotate, never rewrite), live claim bytes flip.
- `charts/llama-swap/values.yaml` (1 comment hit) — re-pin. `charts/llama-swap/tests/TEST_SPEC.md` :3762/:3792 are HISTORY prose → append a dated rename footnote, do not rewrite the recorded verdicts.
- `tests/services/amd-gpu-naming.sh:71` `R9700_CLAIM="amd.com/gpu-r9700"` + the AC4/n3 carrier-law prose (:270-310): carrier set after this chunk = `charts/radiance/values.yaml` (chart default 2) + `services/gpu-ai/prod/values.yaml` (q27 pin "1" both maps) — the law text names them; the zero-stale bash leg flips to grep the RETIRED name with word-boundary care (`gpu-r9700` is a prefix of the retired `gpu-r9700-1` — the grep must not false-green a straggler `gpu-r9700-1` as a `gpu-r9700` hit: patterns anchor the trailing boundary, e.g. `r9700([^0-9-]|$)`).
- `tests/notes/radiance-runbook.sh` (4), `tests/notes/radiance-tp2.sh` (3), `tests/notes/radiance-q27-boot.sh` (2): needles re-pin to the new name; the runbook's re-enumeration checklist gains the rename-window straggler note (plan Risks).
- `.agents/notes/*` (27 lines, 4 docs): operational prose re-pinned to the new name; DATED historical entries annotated ("pool since renamed — see this ticket"), not rewritten.
- `charts/radiance/templates/NOTES.txt` + docs pass under the runbook: a dated deploy-order note: sync = table+claims atomically; DaemonSet rollout straggler window is loud-Pending and self-heals.

## Acceptance criteria

1. `git grep -n "gpu-r9700-1" -- ':!.agents/plans' ':!charts/amd-gpu/tests/evidence'` → empty OR annotated-history-only lines pre-approved into the suite's allow-list (the AC4 leg is the authority; dev reports the residual list verbatim).
2. `python3 -m pytest charts/amd-gpu/tests -q` green INCLUDING the flipped zero-stale leg (it asserts the RETIRED name's absence and the new name's 1:1 presence), the sanitizer-derivation leg (`sanitize('r9700') == 'gpu-r9700'`, historical leg intact), and minimality (rows stay exactly the node's two 7551/C0 + the carried 1586 set).
3. `python3 -m pytest charts/radiance/tests -q` green; both live-lane claim renders read `amd.com/gpu-r9700` with counts 2 (fn) / 1 (q27, both maps).
4. `bash tests/services/amd-gpu-naming.sh` green (n1–n5, prefix-boundary zero-stale semantics proven by a planted-string self-check if the test-writer arms one).
5. `helm lint charts/amd-gpu charts/radiance && helm template` both clean.
6. `bash tests/notes/radiance-runbook.sh && bash tests/notes/radiance-tp2.sh && bash tests/notes/radiance-q27-boot.sh` green.
7. No chart version bump anywhere; no `amd.com/gpu` bare-name or `gpu-8060s` byte changed.

## Commands

Plan §Commands 5–8, 10. PATH export mandatory. pytest per-directory (basenames duplicate across suites).
