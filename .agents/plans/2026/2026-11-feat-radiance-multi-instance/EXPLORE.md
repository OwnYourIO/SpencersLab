# EXPLORE — feat-radiance-multi-instance

Scout record for the owner-directed ticket: (1) route the coord/subagent model
surfaces to `gpu-ai/qwen3.8-flash-next-radiance`, (2) rename the GPU pool
`amd.com/gpu-r9700-1` → `amd.com/gpu-r9700` in one wave, (3) explicit per-release
GPU claim + deterministic visible-device assignment for llama-swap/strata,
(4) restructure `charts/radiance` into a generic shell deployed 4×, (5) land
order vs cf-144.

Posture: read-only. Repo reads + read-only MCP (`readonly-ai-gpu-kubernetes`) +
read-only git + the repo's own validation suites run in their read-only legs.
No `admin-*`, no pod exec, no board writes, no cluster mutations, no commits.
`tests/pipeline-models/surface.sh` M6 and `tests/agent-board-coord/{agents-md c1,
gate t14, rulesync-surface c7}` were NOT run — they execute `rulesync generate`,
which WRITES the generated surfaces. `helm dependency build` was run for the four
chart suites; it writes only gitignored `charts/*/charts/*.tgz` (`.gitignore:3`).

Live reads: `readonly-ai-gpu-kubernetes`, 2026-11-21 ~23:05–23:20Z (re-checked
2026-11-22T00:0xZ). Everything time-sensitive carries that stamp.

---

## 0. Base state (git, verified)

- Branch `feat-radiance-multi-instance`, HEAD `193c12798` == local `main` ==
  `origin/main`. Nothing of this ticket exists on disk yet except this folder.
- **cf-144 is already ON MAIN and pushed** — the whole six-commit chain
  (`0f46b18ae` plan, `3bf2b5a3b` test wave, `e7536b2c9` C01 TP2 core flip,
  `8c171ead1` C02 notes, `eee5f5af2` C03 enumeration, `193c12798` final review)
  sits in `git log`. `git diff --stat cf-144-branch HEAD -- charts/radiance
  charts/llama-swap charts/amd-gpu services/gpu-ai` (branch tip `07916d7e3`,
  worktree `…/e32e19/cf-144-feat-radiance-tp2-expansion`) is **empty**: the
  branch is content-identical, so it is a landing no-op, not a prerequisite.
- DEVIATION from the launch brief: it described cf-144 as unpushed / card in
  Review. Stale. **This ticket's base already contains cf-144** — see §5.

---

## 1. Ask 1 — the headline answer: routing to radiance already WORKS live

`gpu-ai-radiance` is UP and Ready right now, so making `qwen3.8-flash-next-radiance`
the pipeline default is a **docs/routing-surface change, not a serving change**:

| Live object (ai-gpu, ns `default`) | Reading @23:05–00:0xZ |
|---|---|
| Deployment `gpu-ai-radiance` | `1/1` Ready, pod `gpu-ai-radiance-794c7cfd7-fdt42`, started `2026-11-21T23:09:28Z`, 0 restarts, phase Running |
| that pod's container `radiance` | `docker.io/stilldeadcode/radiance:1.17.0`; requests==limits `amd.com/gpu-r9700-1: "2"`, `cpu "8"`, `memory 110Gi`; **no** `ROCR_*`/`HIP_*` env; args = the full cf-144 TP2 set, 34 items (`--model /models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad --port 8000 --host :: --tp 2 --tp-wire wht6 --max-model-len 200000 --max-num-seqs 8 --placement expert_tiered --host-pool-mib 12288 --gpu-headroom-mib 96 --kv-cache-dtype fp8 --prefix-cache-mib 4096 --num-speculative-tokens 3 --max-num-batched-tokens 2048 --checkpoint-interval 4096 --ngram-placement disk --served-model-name qwen3.8-flash-next-radiance`) |
| Deployment `gpu-ai-radiance-q27` | `0/0`. Two lingering pods, `Succeeded`, exit 0 — `gpu-ai-radiance-q27-648bd6886-nwn9k` ran `2026-11-16T23:25:37Z → 2026-11-21T12:44:57Z` with claim pair `amd.com/gpu-r9700-1: "1"`, `24Gi`, cpu 8 |
| Deployment `gpu-ai-llama-swap` | `1/1`; pod `…-vh76k` containers `main` (`llama-swap:unified-vulkan-266`, request `amd.com/gpu-8060s: 1` + `cpu 1` + `4Gi`, limit only `amd.com/gpu-8060s: 1`) and `tools` (`python:3.15.1-slim-bookworm`) |
| Deployment `gpu-ai-llama-swap-strata` | `0/0`, and its `strata` container carries **no GPU claim at all** (by ruling, §3) |
| Node `ai-gpu` | Ready; capacity == allocatable `amd.com/gpu-r9700-1: "2"`, `amd.com/gpu-8060s: "1"`, `amd.com/gpu: "0"`, cpu 32, memory `131150624Ki` (125.08 GiB) |

`gpu-ai-radiance` passes readiness = `httpGet /health:8000`
(`charts/radiance/values.yaml:295` area, `test_render.py::test_ac2_probes_are_plain_health_on_8000`),
so 1/1 Ready is the strongest no-exec proof that the endpoint answers.
The q27 idle law stays as documented: while it rests at 0 the
`peers.radiance-q27` hop answers a **502 peer proxy error** (no endpoints;
llama-swap neither health-checks nor hides peers) — `charts/llama-swap/tests/evidence/radiance-q27-peers-expected.yaml:37-40`,
`services/gpu-ai/prod/values.yaml:693-696`. **Ask 1 must not make q27 a default
route**: `qwen3.8-27b-radiance` is measurement-conditional (`.opencode/opencode.jsonc:758-761`).

**Scout correction to a recorded friction:** cf-144's FRICTION says ArgoCD
Application state is *not* readable through `readonly-ai-gpu-kubernetes`.
It is — the Applications live in namespace **`default`** on ai-gpu (the ArgoCD
control plane runs there: `argocd-server`, `argocd-repo-server`,
`argocd-applicationset-controller` deployments). `resources_get/list` with
`apiVersion: argoproj.io/v1alpha1, kind: Application, namespace: default` works
(the earlier scout queried `argocd`). Applications present: `gpu-ai`,
`gpu-ai-radiance`, `gpu-ai-radiance-q27`, `gpu-ai-llama-swap`, `gpu-ai-amd-gpu`,
`gpu-ai-hivetools`, `gpu-ai-k8s-monitoring`, `gpu-ai-reloader`,
`gpu-ai-external-secrets-bitwarden`, `gpu-ai-external-secrets-bitwarden`,
`system-upgrade-controller`. Statuses read: `gpu-ai`, `gpu-ai-radiance`,
`gpu-ai-radiance-q27`, `gpu-ai-amd-gpu` = **Synced/Healthy**;
`gpu-ai-llama-swap` = **OutOfSync/Healthy**. **None** of the four carries
`syncPolicy.automated` — only `syncOptions` (`CreateNamespace=true`,
`ServerSideApply=<per-app>`, `RespectIgnoreDifferences=true`) → **every sync in
this wave is a manual/owner act** (the base appset renders `automated` only when
the `services.<svc>.selfHeal` annotation is not `"false"` —
`charts/base/templates/appset-charts.yaml:132-138`; live apps show it off).

### 1a. The routing edit sites (ask 1's real scope)

Authority = `.rulesync/skills/pipeline-models/SKILL.md` (generated twin
`.opencode/skills/pipeline-models/SKILL.md`, +1-line offset; never hand-edit the
twin — `rulesync generate`, and CI `.github/workflows/rulesync.yaml` runs
`npx --yes rulesync@37.0.0 generate --check` on every PR).

| Surface | Line | Today | Notes for the move |
|---|---|---|---|
| `.rulesync/skills/pipeline-models/SKILL.md` | 16, 17 | both tiers default `gpu-ai/qwen3.8-27b-q4` | the plan/research row and the test/dev/review row |
| ″ | 20 | "the table above … is the local dense route for both tiers" | prose says *dense*; re-word if the default becomes a Flash MoE |
| ″ | 34 | `Qwen Flash`+`Local` → `gpu-ai/qwen3.8-flash-next-strata-q4` | the combination route |
| ″ | 35 | `Local` + Dense → `27b-q4` | a checked-Dense ROUTE — probably stays |
| ″ | 36, 37 | Local-only default and blank-Model(s) default → `27b-q4` | both are defaults → in scope |
| ″ | 43-50 | Priority class table: radiance trio 9/5/1 for 1–9, `27b-q4` for `10+` background | the 10+ leg is a deliberate llama.cpp leg (`surface.sh:750-751` requires it) |
| ″ | 61-64 | favorited rows: strata row = "the Flash+Local default"; radiance row = "opt-in for now"; q27 row = "NEVER a default route and no runner tier points here … the runner-model literal stays fn/27b-q4 as written" | all three carry the *current* default prose + a runner-literal claim; they must move with the table |
| `.rulesync/skills/pipeline-kickoff/SKILL.md` | 26-27 | cites pipeline-models; "Only `Local` … or nothing checked → default `gpu-ai/qwen3.8-27b-q4`…" | cite-don't-restate, but the literal IS here |
| `.rulesync/skills/boards/SKILL.md` | 260-264 | the same three route strings (`strata-q4`, `27b-q4` ×2) + the temporary `Qwen 27b` alias sentence | boards is the alias home |
| `.rulesync/rules/overview.md` | 304 | "runner model `gpu-ai/qwen3.8-flash-next-strata-q4` (owner ruling 2026-11-09)" | regenerates `AGENTS.md:306` |
| `.agents/loops/pipeline-worker.md` | 5, 11 | `model: gpu-ai/qwen3.8-flash-next-strata-q4` + the ruling comment | **the live hourly runner** |

**Runner literal ≠ subagent default.** `AGENTS.md:306` says the runner literal
"moves only by a fresh user ruling", and `.agents/loops/pipeline-worker.md:9-11`
records the 2026-11-09 ruling. The launch brief asks for the *coord/subagent*
surfaces. Treat the runner as **out of scope unless the owner rules it in the
kickoff round** (open question OQ-A), but note the drift either way:

### 1b. Pre-existing RED baselines the plan inherits (measured at HEAD)

| Suite | State | Why |
|---|---|---|
| `tests/provider-loops/surface.sh` t1 (and t3 by the same pin) | **FAIL** | pins the loop model line to `gpu-ai/qwen3.8-27b-q4` (`:182`, `:220`); the loop file says `strata-q4`. Message: `model: 'gpu-ai/qwen3.8-flash-next-strata-q4' != pinned 'gpu-ai/qwen3.8-27b-q4'`. The 2026-11-09 ruling moved the literal and never re-pinned this suite. |
| `tests/agent-board-coord/agents-md.sh` c11 | **FAIL** | `:587` requires the pair `loop` + `gpu-ai/qwen3.8-27b-q4` within 900 chars in the rules source and `AGENTS.md`; both now say `strata-q4` → `missing needle: gpu-ai/qwen3.8-27b-q4` |
| `tests/opencode/pipeline-locks-tick.test.ts:163` | green (15/15 via `npx --yes tsx --test …`) | byte-pins `gpu-ai/qwen3.8-flash-next-strata-q4` as "single authority" for the tick's model field |

So **whichever way the runner literal goes, these three must be re-pinned in the
same wave** — to radiance if the owner rules the runner moves, to `strata-q4` if
only the pre-existing drift is being cleared. Leaving them red silently is not an
option (the repo's gate is "tests pass" per chunk).

### 1c. Model-routing test coupling (`tests/pipeline-models/surface.sh`)

Legs run fail-fast (`fail()` exits, `:175`), so a red leg hides the rest; run
legs individually when triaging. Selection: `bash tests/pipeline-models/surface.sh
M1 … M8` (no args = M1–M7 only; **M8 must be named explicitly**).

- M1 (`:291-372`) pins the four-option picker, `27b-q4` 27b+Local route with the
  `unless` escape, Local-only `q4`, blank-Model(s) `q4` both tiers, one
  `strata-q4` favorited row (`:322`), the `-strix` single-mention rule (`:338`).
- M2 (`:382-406`) kickoff: `:392` requires `qwen3.8-27b-q4`, `:394` requires
  `gpu-ai/qwen3.8-flash-next-strata-q4`.
- M4 (`:512`) every contract id must appear in a **serving authority**
  (`charts/llama-swap/values.yaml` or `services/gpu-ai/prod/values.yaml`) —
  `27b-q4`, `flash-next-strata-q4`, `flash-next-q3`.
- M5 (`:541-581`) boards routing paragraph windows; `:570` the strata 'assume'
  window, `:579` the 27b+Local `q4` window.
- M6 mirror/`rulesync generate` — **writes; scout-skipped**.
- M7 (`:649-769`) Priority field + the class table; `:750-751` the
  `10+`/`27b-q4` background row; `:767-769` the background rung must exist in a
  serving authority.
- M8 (`:790-1067`) cf-143 radiance legs: two-trio catalog pins (fn 9/5/1,
  q27 8/4/0, `modelID` shared, `limit.context 200000`, `["text","image"]`,
  `tools: true`) `:804-838`; peers↔evidence cross-check (floors 5 / 4); the
  **re-frozen catalog delta** `:868-874` (`CF143_C15_BASE_KEYS` +
  `wantAdded == q27 trio`); the **strata KEEP needles** `:1013`, `:1030`, `:1037`
  (strata-q4 must survive in kickoff + boards); the class/favorited-table parse
  `:977-1012`; and the env-gated diff inventory `:1059-1064`
  (`CF143_BASE_SHA`) which **FAILS if `.rulesync/rules/overview.md` or
  `.agents/loops/pipeline-worker.md` are touched** — i.e. M8-H is a designed bar
  against moving the runner literal without re-authoring the leg.

**The M8-F KEEP needles (`:1030`, `:1037`) are the direct conflict with ask 1**:
they require `gpu-ai/qwen3.8-flash-next-strata-q4` present in kickoff+boards as
*the default route string*. Retiring strata as the Flash+Local default turns them
red; they are test-session-owned re-authoring, not a dev edit.

### 1d. Catalog rows (already exist — probably no edit needed)

`.opencode/opencode.jsonc`: fn trio `:716-736`, q27 trio `:772-790` (shared
`modelID`, only `body.priority` differs; `limit.context 200000`), strata-q4
`:684`, `27b-q4` `:553`. Ask 1 changes no row. **But any NEW wire id** (a second
flash lane from ask 4, e.g. a TP1 sibling id) must join as a trio and then the M8
frozen-delta leg + `charts/llama-swap/tests/evidence/*-peers-expected.yaml`
`models_states` (APPEND-ONLY) both need a test-wave re-author, plus a
`peers:` entry (`services/gpu-ai/prod/values.yaml:658-667` / `:697-706` shape).

---

## 2. Ask 2 — the pool rename `gpu-r9700-1` → `gpu-r9700` is REACHABLE, and it is a one-wave sweep

### 2a. How the name is produced (mechanism authority)

The pool name is not a config string — it is `gpu-` + the sanitizer's output of
the **product field** of the patched `amdgpu.ids` row, because the plugin runs
`-resource_naming_strategy=product` with the patched table mounted over the
plugin's const `IDsPath`:

- `charts/amd-gpu/values.yaml:127-131` — `command: ["/root/k8s-device-plugin"]`,
  args exactly `-logtostderr=true`, `-stderrthreshold=INFO`, `-v=5`,
  `-resource_naming_strategy=product` (no `--visible-devices-strategy` today).
- `charts/amd-gpu/values.yaml:167-174` — the `ids-table` configMap persistence
  (`identifier: amdgpu-ids`, `subPath: amdgpu.ids`, readOnly) mounted at
  `/usr/share/libdrm/amdgpu.ids`; `charts/amd-gpu/values.yaml:176-190` the
  configMap `amdgpu-ids` with its laws; `:225` the row `7551,	C0,	r9700-1`.
- Ledger text (`:180-186`): the sanitizer keeps a token that is lowercase,
  `[a-z0-9.-]`, not a filler word → node advertises `gpu-` + `r9700-1` =
  `amd.com/gpu-r9700-1`. **`amd.com/r9700-1` is impossible** — the `amd.com`
  namespace and the `gpu-` prefix are code constants, and a test bars the
  rejected string by assembly: `charts/amd-gpu/tests/test_provenance.py:358`.
  → For `amd.com/gpu-r9700`, set the product field to exactly `r9700`.
- APU rows **must carry verbatim** (`1586` × 9 rows, `:213-224`): dropping any
  1586 row silently falls the APU to bare `amd.com/gpu` and strands the live
  `llama-swap` consumer. Minimality law: any absent (device,revision) pair falls
  back to bare `amd.com/gpu`.
- Hot-reload law (`:191-195`): kubelet `subPath` never live-updates and the
  plugin reads the table once at startup (`LoadProductIndex`) — a table edit
  propagates only as the DaemonSet rollout (library configMap-checksum annotation).

### 2b. The ordering law (why this cannot be a two-step)

Live today the plugin advertises the OLD name (`amd.com/gpu-r9700-1: 2`,
node allocatable above; device-plugin log class "Reporting 2 devices as
gpu-r9700-1", cf-144 receipt `.agents/notes/radiance-second-gpu-tp2.md:184-194`).
Renaming only the git claims lands pods on a pool that does not exist →
`Pending`, and the bare `amd.com/gpu` key sits at **count 0** on this node, so
there is no fallback to catch them (`charts/radiance/tests/radiance_testlib.py:182`
calls a stray bare claim "Pending-forever"). **Table + claims move in ONE wave**;
and note kubelet accounting: pods already allocated under the old name keep
running, but any pod *recreation* between the two halves of a split wave is
unschedulable. That is the argument for one sync containing ids-table + claims.

### 2c. The name needles — the sanctioned single edit sites

`charts/amd-gpu/tests/amd_gpu_testlib.py:44-62` is the canonical block (its own
header, `:38-43`, states it plus the bash twins are "the ONLY name needles
ticket-wide: any future lane change edits HERE, never needle archaeology"):

```
:45 GPU_RESOURCE_PREFIX = "amd.com/"
:46 R9700_POOL_NAME     = "gpu-r9700-1"
:47 APU_POOL_NAME       = "gpu-8060s"
:48 BARE_GPU_CLAIM      = "amd.com/gpu"
:53 R9700_CLAIM / :54 APU_CLAIM
:56 HISTORICAL_R9700_POOL_NAME = "gpu-ai-pro-" + "r9700"   # assembled on purpose
:62 R9700_PRODUCT_STRING = "r9700-1"
```

Bash twins (marked blocks): `tests/services/amd-gpu-naming.sh:66-73`,
`tests/notes/radiance-runbook.sh:64-65`, `tests/notes/radiance-tp2.sh:33-35`
(`R9700_POOL="${R9700_CLAIM#amd.com/}"`). Cross-chart consumers that resolve
this module rather than restate it: `charts/radiance/tests/radiance_testlib.py:170-183`
(`GPU_CLAIM`/`GPU_CLAIM_BARE`/`APU_CLAIM` = `AMDNAMES.*`),
`charts/llama-swap/tests/test_cf143_naming_flip.py`.

Data + claim sites that must move with it (`git grep -n "r9700-1"` outside
plans/notes returns 18 non-plan files / 214 total occurrences overall — the
counts below are the live-shape ones):

- `charts/amd-gpu/values.yaml`: ids row `:225`, ledger comment block `:176-190`,
  ledger name rows (`EXPECTED_NAME_LEDGER` counterpart, asserted at
  `charts/amd-gpu/tests/test_provenance.py:326` + the `n4` leg), WATCH line.
- `charts/radiance/values.yaml`: claim pair `:348-353` (`amd.com/gpu-r9700-1: "2"`
  in requests AND limits), pool-name prose `:133-159`.
- `charts/radiance/templates/NOTES.txt:25` — "the pod claims the R9700's named
  product pool, `amd.com/gpu-r9700-1` … the scheduler can land it on exactly one
  device" (prose also stale under cf-144's claim-2 — no leg pins it; fix the
  sentence in the same wave).
- `services/gpu-ai/prod/values.yaml`: `:50` (pools prose), `:852`, `:878`, `:896`
  (q27 prose), live overlay lines `:992` + `:995` (q27 claim pin `"1"`).
- `charts/llama-swap/values.yaml:1352` — comment-only mention.
- `.agents/notes/radiance-on-target-acceptance.md` (8), `radiance-second-gpu-tp2.md`
  (12), `radiance-q27-boot.md` (4), `radiance-host-tuning.md` (2) — notes are
  sweep-scoped (see 2d) but history is annotate-never-rewrite per repo law.
- Runbook suites' needles move through the constants blocks above;
  `tests/notes/radiance-*.sh` grep the notes for the *resolved* value.

### 2d. Two sweeps guard the rename, and both interact with the new string

1. **AC4 zero-stale + placement** — `charts/amd-gpu/tests/test_provenance.py:369-434`:
   scans scopes `charts`, `services`, `tests`, `.agents/notes` (NOT `.agents/plans`),
   fails if the *historical* name survives anywhere and fails if the *current*
   pool name appears outside `_NEW_NAME_ALLOW` (`:369-381`: `charts/amd-gpu/`,
   `charts/radiance/`, `charts/llama-swap/values.yaml`, `charts/llama-swap/tests/`,
   `services/gpu-ai/prod/values.yaml`, `.agents/notes/radiance-`, `tests/`),
   with a teeth probe (`:436`) that proves the list is a placement rule.
   - **Substring trap:** the OLD name `gpu-r9700-1` CONTAINS the NEW name
     `gpu-r9700`. Any surviving `-1` occurrence reads as a stray placement hit,
     and the new historical constant MUST be assembled the way `:56` assembles
     its predecessor, or the suite trips its own needle.
   - The allow-list itself must gain whatever new path the generic shell (ask 4)
     introduces.
2. **n3 carrier-law sweep** — `tests/services/amd-gpu-naming.sh:280-310`: live
   R9700 claims may exist **only** under `charts/radiance/`; bare claims only in
   `services/gpu/`; APU name only in the gpu-ai overlay. A new live claim site
   anywhere else (a second chart dir, a llama-swap strata claim from ask 3)
   reddens n3 and AC4 together.

### 2e. Claims are carrier-law restricted (constrains asks 3 and 4)

The chart default ships **NO GPU claim at all**: each cluster ADDs its own in its
service overlay — nulls die in the ApplicationSet→Application `valuesObject`
chain and extended resources take positive integers only, so `0` is no escape
(`tests/services/amd-gpu-naming.sh:5-16`, `charts/llama-swap/values.yaml:1041-1050`).
Overlay ADD/UPDATE of a claim is lawful, REMOVE is not; q27's `claim: "1"` pin
against the chart's moved-to-2 pair is the precedent
(`services/gpu-ai/prod/values.yaml:980-995`).

---

## 3. Ask 3 — per-release GPU claim and "deterministic visible-device assignment" split into two regimes

**Regime A — plugin-scheduled pods (radiance).** Selection is BY POOL NAME +
COUNT; the plugin's `Allocate` injects `/dev/kfd` + the chosen card/render and
**sets no env** (`.agents/notes/radiance-second-gpu-tp2.md:105-109`). The radiance
suite *bars* visibility env: `charts/radiance/tests/radiance_testlib.py:143`
`ABSENT_ENV = ("ROCR_VISIBLE_DEVICES","HIP_VISIBLE_DEVICES")` +
`test_render.py::test_ac2_no_rocr_hip_env`. Consequence: a claim can make *which
cards* deterministic (pool + count), but per-rank assignment inside a `--tp 2`
pod is the engine's ordering of injected devices — nothing in the repo pins it,
and nothing in GitOps can. Live confirmation: the fn pod carries no
`ROCR_*`/`HIP_*` env (§1).

**Regime B — hostPath/privileged pods (llama-swap strata).** By the 2026-10-27
device-access ruling strata is `privileged: true` with hostPath `/dev/kfd` +
`/dev/dri`, **NOT** the device plugin, and chip choice happens inside via
`ROCR_VISIBLE_DEVICES` (`charts/llama-swap/values.yaml:1342-1363`; the pod spec
confirms no claim). Law quoted there: "per-name pools settle cross-card choice,
never VRAM arbitration … hostPath sits outside plugin accounting entirely".
`.agents/notes/radiance-second-gpu-tp2.md:171-174` repeats it: "Strata needs no
naming change: its privileged hostPath pod never held a plugin claim". So an
"explicit GPU claim for the strata release" **contradicts a standing ruling** and
would redden the strata wiring legs — surface it as a decision, not an edit
(OQ-B).

The index law and its full sweep table are `.agents/notes/radiance-second-gpu-tp2.md:89-117`
(§4, "the rocrVisibleDevices index law"): 5 rows — strata `rocrVisibleDevices`;
`rocrVisibleDevicesByModel` strix lane; the dormant `charts/vllm` lane; radiance
(no env, nothing to re-pin); host privileged pods. Values:
`charts/llama-swap/values.yaml:1507` `rocrVisibleDevices: "0"`,
`:1521` `rocrVisibleDevicesByModel` (strix → `"2"`, re-pinned 1→2 by cf-144 C03
from the owner's 2026-11-21 `rocminfo` receipt: ordinals **0/1 = the two R9700s,
2 = the 8060S APU**). Test constants:
`charts/llama-swap/tests/strata_testlib.py:113-124` (`ROCR_PRIMARY="0"`, `ROCR_STRIX="2"`,
`ROCR_HOST_GPU_COUNT=3`, `ROCR_PRE_CARD2_PAIR=("0","1")`) with the explicit note
that **the suite cannot substitute the receipt** — a pair that silently matches a
stale story is repo-invisible by design; the dated `rocminfo`-provenance sentence
in the values comment is the owner-side gate
(`test_strata_enumeration.py` header posture). Injection render path:
`charts/llama-swap/templates/configmap-strata.yaml:40-43` (per-model env
`ROCR_VISIBLE_DEVICES=<dev>`, `rocrVisibleDevicesByModel` overriding the default).

Determinism caveat the plan must own: an ordinal is **host enumeration order**.
It moved once already (the second discrete card inserted AHEAD of the chip —
`strata_testlib.py:100-105`), and the repo has NO mechanism that pins ordinals;
it has receipts. Two real alternatives exist and are recorded, not planned:
- the plugin's own device-visibility strategy flag — **not shipped** today
  (args are the four at `charts/amd-gpu/values.yaml:127-131`); whether
  `rocm/k8s-device-plugin` at `1.31.0.12` supports a
  `--visible-devices-strategy`-style flag (index|uuid|topology) and what env it
  injects is **Needs research: yes**;
- the ROCm **DRA** driver lane: `k8s-gpu-dra-driver` v1.0.1, ranked #2, with the
  production witness `r9700-x2` `ResourceClaimTemplate` — CEL
  `deviceID == "0x7551"` with `allocationMode: ExactCount, count: 2`
  (`.agents/notes/radiance-second-gpu-tp2.md:175-182`). Device-ID claims are the
  only repo-recorded path to *per-card* determinism; it replaces the pool model
  rather than extending it.

Also record: BDFs are already witnessed — `0000:c3:00.0` + `0000:c7:00.0` (the
two R9700s), `0000:c8:00.0` (APU) — cf-144's device-plugin receipt.

---

## 4. Ask 4 — four releases of one chart: the mechanism is live-proven, the cost is in the seams

### 4a. Mechanism (verified live + in source)

`charts/base/templates/appset-charts.yaml`:
- roster `charts:` → one list element per key (`:16-38`), opt-out
  `enabled=false` (`:19`), Application name = `{{ .serviceName }}-{{ .appName }}`
  (`:42`) → key `radiance-flash-tp1` ⇒ Application `gpu-ai-radiance-flash-tp1`;
- `chart: <name>` re-points the source path to an existing chart dir (`:67-70`)
  — **this is the same-chart-N-releases lever** (q27 uses `chart: radiance`);
- per-app values come from `index $.Values $appName` (`:36`) merged into
  `valuesObject` with order app-customValues > service-customValues > base
  values (`:114-123`);
- destination namespace per roster entry (`:30`, `:47-49`).

Live proof: Applications `gpu-ai-radiance` and `gpu-ai-radiance-q27` both have
`sources[1].path: charts/radiance`, `targetRevision: main`,
`valueFiles: ["values.yaml"]`, and their own `helm.valuesObject` whose only
top-level key is `app-template`. The parent `gpu-ai` Application carries
`chart: base @ 1.0.198` (from `https://ownyourio.github.io/SpencersLab/`) whose
`valuesObject.charts` = `[amd-gpu, external-secrets-bitwarden, k8s-monitoring,
llama-swap, radiance, radiance-q27]` — **so a new roster key is pure values: no
base-chart bump** (the deployed base already carries the lever).
`services/gpu-ai/prod/templates/appset.yaml:34` pins `baseChartVersion: 1.0.198`
(renovate-managed).

Roster entries to clone: `services/gpu-ai/prod/values.yaml:78-101`
(`namespace: default`, `ServerSideApply: "false"`, `chart: radiance`).
The comment at `:85` cites the lever at `appset-charts.yaml:83` — **stale cite**
(the lever is `:67-70` today); re-derive cites by content, not line number.

### 4b. Feasibility arithmetic (the hard constraint)

Two R9700s exist; the fn lane claims **both** (`2` + `--tp 2`, live-verified).
Extended-resource accounting counts running pods' requests, so at most one
TP2-class lane can be UP at a time ⇒ **of the four releases, three must render
`replicas: 0`** and the UP one is an owner swap. Precedent + law: q27 rests at 0
(`services/gpu-ai/prod/values.yaml:898-995`), the swap discipline is claim-math
(fn UP holds both cards ⇒ the other lane schedules only with fn DOWN), and the
idle hop answers 502 (loud, never silent). `charts/radiance/values.yaml` has **no
`replicas:` key** (app-template default 1) — `replicas: 0` is an overlay value per
release. Memory: node allocatable 125.08 GiB; fn is 110Gi; q27 is 24Gi; the fn
coexistence handshake (110 + 64 + 6.3 > 125.08) is documented in
`charts/radiance/templates/NOTES.txt:28-33`.

### 4c. Per-release surface that today needs a whole-array override

`charts/radiance/values.yaml` is already a thin shell — `templates/` contains
ONLY `NOTES.txt`; the pod renders entirely from the app-template dependency
(`Chart.yaml` deps: `app-template 5.0.1`, single-dep idiom). Per-release knobs
today, and what each release must re-author:

| Knob | Chart default | Notes / guards |
|---|---|---|
| pack + path | `modelPath` anchor `:26` = `/models/radiance/qwen3.8-next-flash-fp8-iq4r-moe.rad`; pack ledger `:15-25` | YAML anchors resolve per document, so a service-block re-pin does NOT reach the chart render → **dual-edit guard** `test_serve_args.py::test_dual_edit_guard_model_path_matches_service_repin`. Both existing releases use the `/models/radiance/` dir (fn `:397-399`, q27 overlay `:1030`), on the SHARED 500Gi `gpu-ai-llama-swap-models` PVC |
| serve args | `serveArgs` alias `:187-204` (34 items — byte-identical to the live pod args) | a lane change replaces the WHOLE array (q27 does: `services/…:954-965`); `TP2_LEDGER_KEYS` (`radiance_testlib.py:150-156`) + `test_ac3_*` legs red any half-move of a scalarized key |
| served id | `--served-model-name qwen3.8-flash-next-radiance` is a literal in `serveArgs` (`:204`), NOT derived from `.Chart.Name` | honest-id law (D7); `test_peers_stability.py` pins `SERVED_ID == evidence` |
| GPU claim / memory | `:348-353` pair `amd.com/gpu-r9700-1: "2"` / `110Gi` | overlay ADD/UPDATE only (§2e); `FN_GPU_CLAIM_COUNT = "2"` at `radiance_testlib.py:161` |
| context | `maxModelLen: 200000` `:92` | also pinned in the catalog `limit.context` (M8) |
| pack fetch | init `radiance-fetch` with the BusyBox-portable sha gate (`:372-430`) | q27 REPLACES the whole `command` (`services/…:1024-1063`) and hard-codes PACK/MARKER/URL — which makes its overlay `radianceFetch.sourceDir` **inert** (a generic shell should parameterize PACK/LFS_SHA/URL/MARKER instead of replacing the script; D27/§D3b grammar law must survive) |
| staging image | `curlimages/curl` pin `:383` + digest ledger | `test_ac2_staging_*` legs; `BUSYBOX_FAMILY_REPOS` (`radiance_testlib.py:199`) |
| pod law | `Recreate`, grace 180, probes `/health:8000`, no ingress/secret | `test_render.py` legs (`:166`, `:185`, `:202`, `:215`) |

Peer/route + catalog seams each new served id must join (three places, in this order):
1. `charts/llama-swap/tests/evidence/<lane>-peers-expected.yaml` — test-authored,
   **dev must not edit**; `models_states` is APPEND-ONLY and explicitly anticipates
   new states/keys (`radiance-peers-expected.yaml:1-46`,
   `radiance-q27-peers-expected.yaml:1-59`);
2. `services/gpu-ai/prod/values.yaml` `config.peers` (`:658-667` fn,
   `:697-706` q27): proxy = `http://<Application-name>.default.svc.cluster.local:8000`,
   NO `/v1` suffix, explicit `models:`, `filters.setParams "priority?"` floor, no
   apiKey; the id stays OUT of the outer `models:`/matrix (peers are invisible to
   the solver);
3. `.opencode/opencode.jsonc` trio + `.rulesync/skills/pipeline-models/SKILL.md`
   favorited/class tables (+ M8 re-pin).

Trio law: the documented SKIP for each internal radiance lane lives at
`services/gpu-ai/prod/values.yaml:103-134` (no ingress host per D7/Q4) — each new
lane adds a skip paragraph, not a host. Secrets: none (keyless D8 → no
`bitwardenIds`, no `custom-values/` leg; `custom-values/gpu-ai/prod-values.yaml`
carries only bitwardenIds and has no pool-name occurrence).

### 4d. Test + CI shape for four lanes

- Suite idiom: one file per lane — `charts/radiance/tests/test_q27_lane.py` has
  22 legs (roster/chart-override, renders-at-0, args set-equality, absence set,
  Guaranteed pair + overlay pin, "claim does not track the chart count", kinds
  banned, name dedup, sentinel-free render, four pack literals, grammar, image
  family, ledger comment verbatim, switch discipline comments, headroom arithmetic,
  subtree model-path == args, 503-swept, keyless grep, CI step exists,
  extraction works pre-land). Clone that shape per new lane, or parameterize.
- CI: `.github/workflows/radiance-render-tests.yaml` has one extraction+render
  leg per release (`:61-64` fn, `:74-77` q27), and
  `test_contract.py::test_ac6_workflow_exists_parses_and_triggers` requires the
  trigger paths to be EXACTLY `{charts/radiance/**, services/gpu-ai/prod/values.yaml,
  .github/workflows/radiance-render-tests.yaml}` (`:113-119`) — adding STEPS is
  fine, changing PATHS reddens it. `d.get(key) or {}` yields `{}` pre-land by
  design (gotcha-14 hardening).
- Four lanes ⇒ four `charts.<key>` + four service subtrees ⇒ four extraction legs
  (or a loop) in that workflow, and `test_contract`'s path-set leg stays green.
- Touching `services/gpu-ai/prod/values.yaml` fires FOUR chart workflows plus
  rulesync-drift plus aislop: `radiance-render-tests`, `vllm-render-tests`,
  `amd-gpu-render-tests`, `llama-swap-tools-tests` (their `paths:` filters).

---

## 5. Ask 5 — relationship to cf-144 and landing order

cf-144 (TP2 expansion) is **already landed on main and pushed** (§0), so it is
not a prerequisite — it is the BASE. What it fixed, and therefore what ask 4/ask 2
must respect rather than re-open:

| cf-144 decision (main) | Survives | Subsumed / must move if this ticket proceeds |
|---|---|---|
| fn flips to TP2: `--tp 2 --tp-wire wht6` + claim `2` + memory HOLD 110 (shape A / OQ-A, `e7536b2c9`; `charts/radiance/values.yaml:191-192`, `:348-353`) | the shape of a TP2 lane; the q27 claim-1 overlay pin; `test_resource_name_identity.py::test_c144_q27_claim_stays_one_under_the_tp2_flip` | a *generic shell* would move claim-count/tp to per-release values — the `TP2_LEDGER_KEYS` scalar carriers + set-equality legs are the sanctioned carrier, not a new parameter |
| strix ROCr `1→2` + dated provenance comment (`eee5f5af2`; `values.yaml:1507/1521`, `strata_testlib.py:113-124`) | the receipt-pinned ordinals 0/1/2 and the one-way provenance arm | a rename/claim wave for strata would fight it (§3) |
| notes layer annotated TP2-SHIPPED, insert-only (`8c171ead1`) | the annotate-never-rewrite law; `tests/notes/radiance-*.sh` pin the dated markers (all three suites GREEN at HEAD) | markers naming the pool string re-resolve through the bash constants → they follow the rename automatically |
| C04 (sysfs re-verification leg) DEFERRED to a follow-up card (P13, OQ-D) | still deferred — an owner/on-target leg | this ticket does not inherit it unless the owner says so |
| FRICTION: heartbeat attribution flapped (open, 2 sightings) | machinery note for the coordinator: re-read `pipeline_status` + `pipeline_heartbeat` before committing | — |

Landing order (all syncs manual — §1): a claim/pool rename wave must land as ONE
sync set — `gpu-ai-amd-gpu` (ids table + args) and the radiance-lane apps in the
same window; if they cannot be simultaneous, prefer plugin-first (new name
advertised) while claims still say the old name → lanes go Pending loudly, rather
than the reverse where pods that were mid-recreation are unschedulable and the
bare pool is at 0. The owner syncs `gpu-ai` (base) first to materialize any new
Application, then the children.

---

## 6. Validation battery (measured at HEAD `193c12798`, PATH must include `~/.local/bin`)

```
export PATH=$HOME/.local/bin:$PATH                 # else helm-guarded pytest mass-skips silently
helm dependency build charts/{radiance,amd-gpu,llama-swap,vllm}   # writes only gitignored charts/*/charts
python3 -m pytest charts/radiance/tests -q         # 70 passed, 1 skipped
python3 -m pytest charts/amd-gpu/tests   -q        # 29 passed
python3 -m pytest charts/llama-swap/tests -q       # 507 passed, 9 skipped
python3 -m pytest charts/vllm/tests -q             # 36 passed
bash tests/services/amd-gpu-naming.sh              # PASS (n1,n2 skip+ok,n3,n4,n5) — n2 re-runs with AMD_GPU_FLIP_COMMIT at review
bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M7 M8   # PASS (9 ok) — M6 WRITES, never run it read-only; M8 needs explicit naming
bash tests/notes/radiance-runbook.sh               # PASS (5 ok)
bash tests/notes/radiance-tp2.sh                   # PASS (3 ok)
bash tests/notes/radiance-q27-boot.sh              # PASS (6 ok)
bash tests/cf106-noop/surface.sh                   # PASS (8 ok)
bash tests/noop-marker/surface.sh                  # PASS (9 ok)
bash tests/provider-loops/surface.sh               # RED t1 (pre-existing, §1b)
bash tests/agent-board-coord/agents-md.sh c11      # RED (pre-existing)
npx --yes tsx --test tests/opencode/pipeline-locks-tick.test.ts  # 15 pass (pins strata-q4 at :163)
helm lint charts/radiance && helm template radiance charts/radiance --set domain=spencerslab.com --set clusterName=gpu-ai
```

Review-only inputs these suites expect: `AMD_GPU_FLIP_COMMIT` (n2),
`CF143_BASE_SHA` (`surface.sh:1059-1064`), `CHUNK_BASE` for the three
`tests/agent-board-coord/*` admit-set whitelists (`agents-md.sh` ~420-463,
`rulesync-surface.sh` ~595-630, `gate.sh` ~970-1005) — each carries a per-ticket
path whitelist that must gain this ticket's plan folder + the serving surfaces it
touches (they only bite when `CHUNK_BASE` is set).

CI on a PR: `rulesync.yaml` (drift, every PR), `aislop.yaml` (`aislop ci --changes`),
and the four chart workflows per §4c.

---

## 7. Gotchas for the plan/dev/test sessions

1. **Do not run M6** (`tests/pipeline-models/surface.sh` default set) or
   `agents-md.sh c1` / `gate.sh t14` / `rulesync-surface.sh c7` in any read-only
   session: they execute `rulesync generate` and rewrite `AGENTS.md` +
   `.opencode/{agents,commands,skills}`.
2. **Fail-fast bash suites**: `fail()` exits — a red leg hides all later legs.
   Re-run per-leg ids when triaging, and never read a single FAIL as "the only
   problem".
3. **M8 is not in the default set** and its H leg (`CF143_BASE_SHA`) *fails on
   touch* of `overview.md` / `pipeline-worker.md` — moving the runner literal
   requires re-authoring M8-H in the test session.
4. **The strata-q4 KEEP needles** (`surface.sh:1030`, `:1037`) require the strata
   route string to survive in kickoff + boards; ask 1's default move reddens them
   until re-authored.
5. **Two pre-existing reds** (provider-loops t1/t3, agents-md c11) pin the OLD
   runner literal `gpu-ai/qwen3.8-27b-q4`. They are not caused by this ticket;
   the plan must either re-pin them deliberately or carry them as an explicit,
   named exception.
6. **Substring trap in the rename sweep**: `gpu-r9700` is a prefix of
   `gpu-r9700-1`; assemble the new historical constant (`"gpu-r9700" + "-1"`) and
   expect AC4's placement sweep to flag any surviving `-1` occurrence.
   `.agents/plans/**` is OUTSIDE the sweep scopes, so plan text is safe.
7. **`amd.com/r9700-1` is an impossible string** and is test-barred
   (`test_provenance.py:358`) — the same shape applies after the rename:
   `amd.com/r9700` is unreachable, `gpu-` is a code constant.
8. **`amd.com/gpu` sits at count 0 on this node** — a stray bare claim is
   Pending-forever, and there is no fallback capacity.
9. **Carrier law**: ship claims as positive overlay ADD/UPDATE only; nulls and
   `0` do not retire a claim through the appset→Application chain. New live claim
   sites outside `charts/radiance/` redden n3 + AC4's allow-list.
10. **Strata is hostPath/privileged by ruling and holds no claim** — "explicit
    claim per release" is a ruling change for that lane, not a values edit
    (`charts/llama-swap/values.yaml:1342-1363`).
11. **`radianceFetch.sourceDir` in the q27 overlay is inert** — the overlay
    replaces the init `command` wholesale (`services/…:1024-1063`). A generic
    shell that parameterizes the script must keep the BusyBox-portable equality
    gate (D27/§D3b) and the image-identity legs.
12. **`test_contract` pins the workflow trigger paths exactly**; add steps, not
    paths. Extraction legs are `d.get(key) or {}`-safe pre-land.
13. **Stale line cites exist in comments** (e.g. the roster comment cites
    `appset-charts.yaml:83` for a lever now at `:67-70`); verify by content.
14. **`replicas: 0` is the only way three of four lanes coexist** — extended
    resources count running pods, the node has two cards, fn claims both.
15. **A new served id is a three-surface change** (evidence YAML → peers entry →
    catalog trio) and the evidence file is test-owned, dev-must-not-edit;
    `models_states` is append-only.
16. **Applications ARE readable** via `readonly-ai-gpu-kubernetes` in namespace
    **`default`** (cf-144's FRICTION row saying otherwise is superseded — see §1).
17. **All gpu-ai apps are manual-sync**; `gpu-ai-llama-swap` is already
    OutOfSync/Healthy at HEAD (limited to `Deployment/gpu-ai-llama-swap-strata`),
    so "OutOfSync after my sync" needs that pre-existing delta netted out.
18. **MCP output truncates long container `args`** (this scout got bitten: a
    30-item slice hid `--ngram-placement` and `--served-model-name` and briefly
    read as a live/chart divergence). When receipts matter, re-read with
    `pods_get` and count/index the array (`c.args.length`,
    `c.args.indexOf("--served-model-name")`) instead of eyeballing a preview.

---

## 8. Open questions (coordinator routing)

- **OQ-A (owner ruling, not research):** does ask 1 move the *hourly runner*
  literal too (`.agents/loops/pipeline-worker.md:5`, `AGENTS.md:306`), which
  AGENTS.md says moves only by a fresh user ruling, or only the coord/subagent
  defaults? Best guess: **defaults only**; the runner stays `strata-q4` and the
  three stale pins get re-pinned to `strata-q4`, clearing the pre-existing drift.
- **OQ-B (owner ruling):** does ask 3 mean "give the strata release a real GPU
  claim" — contradicting the 2026-10-27 hostPath ruling (§3) — or "make the
  existing per-release device selection explicit (values + receipts)"? Best
  guess: the latter: keep hostPath, keep `rocrVisibleDevices*` as the single
  carrier, add the dated-receipt discipline, and leave claims to the radiance
  lanes.
- **Needs research: yes** — deterministic per-card selection mechanisms the repo
  cannot answer from disk: (a) whether `rocm/k8s-device-plugin` at the pinned
  `1.31.0.12` exposes a visible-devices strategy (index|uuid|topology) and what
  env it injects into containers (which would let a plugin-scheduled pod get
  stable per-rank device identity); (b) whether `ROCR_VISIBLE_DEVICES` accepts
  bus-ID/UUID forms (making strata's choice hardware-stable rather than
  ordinal-based); (c) maturity/fit of `k8s-gpu-dra-driver` v1.0.1 +
  `ResourceClaimTemplate` CEL `deviceID` claims as a replacement for named pools.
  Route (a)-(c) to `agent-research`; they gate any "deterministic assignment"
  acceptance criterion in ask 3.
- **Needs research: no** — the four-lane roster shape, the rename wave, and the
  routing-surface move are fully groundable here (this file).
