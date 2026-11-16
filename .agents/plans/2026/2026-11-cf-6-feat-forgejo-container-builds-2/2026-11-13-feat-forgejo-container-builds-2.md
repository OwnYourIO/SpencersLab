# PLAN: Build and deploy containers — run -2 (pin the detection contract, make the empty outcome loud, close the guard convention)
feature: 2026/2026-11-cf-6-feat-forgejo-container-builds-2
card: 6 (`7dAgENe75dBt2FZY6`)   class: commit-only (`Deployment` unchecked)   claim: derived set `[CICD]`, setId `9cb75b2c-5512-4054-9887-3795a4b8837b`, exclusive (no co-tenants), release = the move to Review
base: **post-merge** — `main` is merged into the branch at `7a82dfb21` (0 behind / 21 ahead); every number below is measured on that tree

**Read order:** `STATE.json` → the chunk file you were given → this file → `DECISIONS.md` (its
"research verdict" + "owner batched-round answers" + "post-merge ground" sections are the factual
baseline — this plan does not re-argue them) → `RESEARCH.md` R1 → `EXPLORE.md` → `FRICTION.md`.

## Goal

Close the two defects the owner's `fetch-depth: 0` review exposed, and land the two follow-on rulings
that came out of the batched round: make the detection contract **pinned** (no leg named `fetch-depth`,
and every d-leg fixture was one commit wide, so deleting L85–88 or narrowing the diff to the tip left
the suite green — both re-proven by mutation this session) and make the empty outcome **loud** (the
port dropped the predecessor's `echo "Changed containers: $RESULT"`; a green run that built nothing
was indistinguishable from one that found nothing). Then, by ruling: move the **PR arm to a
merge-base diff** (B5, hand-rolled — OQ-b) and bring cf-135's
`.forgejo/workflows/renovate.yaml` into the repo's ROLE **membership** convention (OQ-j), which is what
makes this run's own `g1` leg green on the merged tree.

Three chunks: **C01 M** (detection package + 11 red-first/green-pin legs), **C02 S** (the `renovate.yaml`
guard migration + the cf-135 suite bytes that must move with it), **C03 S** (docs prose for the
detection contract + `rulesync` regen + one new docs-pin leg). C02 and C03 exist because the owner's
answers widened the run from "detect-only" to "detect + close the convention + document it"; C01's own
bytes are unchanged in spirit from the draft.

## Baseline facts (settled — do not re-litigate in review)

- `DECISIONS.md` (research verdict, owner answers, post-merge ground) + `RESEARCH.md` R1 §1/§2/§6/§7 +
  `EXPLORE.md` §2–§6: a push payload always carries `forgejo.event.before`; at checkout depth 1 the
  range endpoints are absent and the detect step dies **loud** (`bad object`, exit 128), never a silent
  partial; the trigger's own `paths:` filter walks the whole range (`diff-tree … --root`), so
  dispatch and detection agree endpoint-for-endpoint. `fetch-depth: 0` costs a measured
  **21.23 MiB / 1,849 ms**; the targeted `git fetch --depth 1 origin <before>` fill is 172 ms — and the
  owner declined both B2 and B3 for this run.
- Legibility platform truth: runner v13.2.0 renders `warning`/`error` as **log text**, `::notice::` is
  not interpreted, and Forgejo v15.0.10 has no annotation store and no step-summary render. Nothing in
  this run may be described as a UI chip.
- `forgejo.event.total_commits` reads `0` on ordinary pushes (R1 §4) — nothing here counts commits.
- **Post-merge ground, measured this pass:** containers suite baseline **28 ok / 1 FAIL — `g1` on
  `renovate.yaml`'s `vars.ROLE == 'dev'`** (the file `main` brought in; the suite was 29 ok pre-merge,
  so the draft's 29-based arithmetic is void). `containers-build.yaml`, the detector, the suite and
  `docker-build.yaml` are **byte-identical** to pre-merge (`git diff c5daed362 7a82dfb21` on them:
  empty). `containers/` is still **13 dirs**. `.forgejo/workflows/` is now **3** files (`g1` walks all
  of them, **16** embedded run blocks repo-wide, all `bash -n` clean); `.github/workflows/` is now
  **9** files (cf-141/143's two new render-test workflows sit outside `g1`'s walk and outside `x4`'s
  named six-sibling fence — they land on **no** run -2 leg).
- **Red on arrival, and which reds are ours:** `forgejo-renovate.sh t8` and `forgejo-move-config.sh m5`
  both pin `packageRules == 9` and answer `has 10` on this branch (run -0's calendar rule is the 10th)
  — **C02 re-pins them to 10**. Pure `main` is green there. The other reds on the merged tree are
  pre-existing upstream and are **not** run -2's to fix (OQ-o asks whether to card them):
  `kubernetes-mcp-version-floor.sh k2` (expects 8, red on `main` too), `chart-yaml-legs.sh` k5 + k10
  (red on `main`), `forgejo-ssh-gateway.sh` / `forgejo-ssh-audit-trail.sh` (their own
  `storm-runs/`-move and main-side Chart.lock clauses, red on `main`).
- **Prototypes measured this pass** (scratch `git archive` copies, `git init`ed): the blind spot is
  real — deleting the checkout `with:` block, and rewriting the range to
  `"${SHA:-HEAD}~1" "${SHA:-HEAD}"`, each still answer **28 ok** (only the pre-existing `g1` red).
  The C01 package is additive — the B4 echo line, the detector's stderr range/`::warning::` lines and
  an A5 `die` guard change nothing else (still **28 ok**, and the guard turns an empty `before` into
  exit **2** with a named message). The B5 merge-base variant leaves **d1–d8 all green** (a PR whose
  base is an ancestor resolves to merge-base == base). The C02 migration variant turns
  `forgejo-renovate.sh` to **8 ok / t9 default-OFF skip / PASS** and `forgejo-move-config.sh` to
  **6 ok / PASS**, and `g1` green.
- No `containers-build.yaml` run has ever executed on either instance; the branch has never been
  pushed. Anything provable only by a live run is an **owner leg**, never an agent AC.

## Scope

- **C01** — detector: **A5** (empty `before` ⇒ `die`, red; all-zero keeps the first-push fallback),
  **A4** (the fallback announces itself on **stderr** with a `::warning::` naming the narrowing), a
  range/endpoint line on stderr for every git arm, and **B5** (PR arm ⇒ hand-rolled
  `git merge-base "$BASE_SHA" "$HEAD_SHA"` then two endpoints; no `--merge-base` flag, so no git ≥ 2.43
  dependency and OQ-g is moot). Workflow `detect-changes` only: **B1** (`fetch-depth: 0` byte-intact,
  comment says why), **B4** (echo `changed containers: <set>` + event + endpoints on stdout,
  `::warning::` on an empty push/PR set, dispatch exempt), header-comment sentence for the detection
  range. Plus **11 legs**: `t12–t15`, `d9–d15`. Cosmetic close-out: the detector header's two stale
  "ghcr" words (run -1's carried C02 nit).
- **C02** — `.forgejo/workflows/renovate.yaml`: `if: vars.ROLE == 'dev'` → `if: contains(vars.ROLE, 'dev')`
  (membership, **narrow-on-unset preserved** — the `main-sync.yaml` class), header gloss re-worded
  **without** the literal token `vars.ROLE`; plus the cf-135 suite bytes that must move in the same
  commit: `GUARD` constant (L53), the header's `t3` line (L10–12), and the two `packageRules == 9`
  count constants (`forgejo-renovate.sh` **t8** and `forgejo-move-config.sh` **m5**, both
  `need(len(rules) == 9, …)`) → 10.
- **C03** — docs prose for the detection contract in `skills/container-creation/SKILL.md` (Build
  pipeline section) and `.rulesync/rules/overview.md`, then `rulesync generate` + `--check` (AGENTS.md
  regenerated, never hand-edited), plus the **x5** docs-pin leg.

## Out of scope

- Run -1's shipped decisions: ROLE **semantics** beyond the shape (no new role words, no new variables),
  the dual-registry push, calendar/rolling tag math, arm order, `pr-` tag shape, the registry PAT legs
  (H3). The **containers suite's** legs (`t3/t5/t7/t8/t9/t11`, `r1–r5`, `x1–x4`, `d1–d8`) stay
  byte-stable and green — that `t8`/`t11` are the *containers* calendar/push-chain legs; the identically
  named `t8` in cf-135's `forgejo-renovate.sh` is a **different suite**, and only its count constant is
  re-pinned by C02 (never its logic). `main-sync t3` is untouched too — C02 migrates `renovate.yaml`,
  not `main-sync.yaml`.
- The detector's push-arm range math, `next-n`, `sanitize`, the guards on `containers-build.yaml`, the
  matrix, both build jobs' bare checkouts, every login/derivation/push block.
- **Other people's red bytes:** `kubernetes-mcp-version-floor.sh k2`, `chart-yaml-legs.sh` k5/k10,
  the two `forgejo-ssh-*` suites (all red on `main` independently of run -2) — surfaced as OQ-o, not
  fixed here. cf-141/143's charts, render-test workflows, `.rulesync/skills/pipeline-models`,
  `.opencode/opencode.jsonc` — untouched, and the model-routing detour needs no rule change (main's
  rule already documents `openrouter/qwen/qwen3.8-flash` as the fallback when the local route is
  unavailable, which is exactly this run's situation).
- Card 55's co-tenant surface, and anything pushed: `Deployment` is unchecked → commit-only, PR is
  owner-owned.
- **No live validation is promised.** The guard/detect posture has never executed on either instance;
  no docker daemon in agent sessions (`docker build => no-daemon, CI-deferred`, cf-77). This run ships
  offline contracts + docs.

## Commands

Re-measured on the post-merge tree (`7a82dfb21`). There is **no unit-test suite and no docker daemon**
in this repo's agent sessions — "tests" means these offline contract suites plus parse/lint legs. Run
from anywhere in the worktree; each suite `cd`s to its own toplevel.

- **run gate (all three chunks in):** `bash tests/services/forgejo-containers-build.sh` → **41 ok**
  (baseline 29 + `t12–t15` + `d9–d15` + `x5`; `g1` green only once C02 lands).
- **C01 gate:** `bash tests/services/forgejo-containers-build.sh t d` → **30 ok** (t1–t15 + d1–d15).
- **C02 gate:** `bash tests/services/forgejo-containers-build.sh g1` → 1 ok, **and**
  `bash tests/services/forgejo-renovate.sh` → **8 ok + t9 skip, PASS** (9 legs, **fail-fast** — a red
  leg aborts the suite, so t8's red today hides nothing but does stop t9 running), **and**
  `bash tests/renovate/forgejo-move-config.sh` → **6 ok, PASS**.
- **C03 gate:** `bash tests/services/forgejo-containers-build.sh x` → **5 ok** (x1–x5), plus
  `npx rulesync generate && npx rulesync generate --check` (both must pass; `--check` alone is clean at
  planning time: "All files are up to date"), plus the docs greps below. **Never** `rulesync gitignore`.
- **Selector forms (proven this session):** groups are **separate argv words** —
  `bash tests/services/forgejo-containers-build.sh t d` works; the quoted single-argv form dies:
  `bash … 't d'` → `FAIL: unknown check id t d (expected t1..t11, d1..d8, x1..x4, r1..r5, g1, or
  groups t d x r g c02)` and exits 2. Per-leg ids work (`… t12 d9`). The legacy alias `c02` (= `t d r`)
  stays as run -1's and is **not** a run -2 gate. Note the parser's help text itself needs widening for
  the new ids (see Tests).
- **Syntax — script:** `bash -n scripts/forgejo-container-detect.sh`
- **Syntax — every embedded `run:` block** (all three `.forgejo` workflows, **16 blocks** today):
  ```
  python3 - <<'PY'
  import glob, subprocess, sys, tempfile, yaml
  bad = n = 0
  for p in sorted(glob.glob('.forgejo/workflows/*.yaml')):
      d = yaml.safe_load(open(p))
      for j, v in (d.get('jobs') or {}).items():
          for i, s in enumerate((v or {}).get('steps') or []):
              if isinstance(s, dict) and 'run' in s:
                  n += 1
                  f = tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False)
                  f.write(s['run']); f.close()
                  r = subprocess.run(['bash', '-n', f.name], capture_output=True, text=True)
                  if r.returncode:
                      bad += 1; print(f'bash -n FAIL {p} {j} step {i}: {r.stderr.strip()}')
  print(f'embedded run blocks checked = {n}, failures = {bad}')
  sys.exit(1 if bad else 0)
  PY
  ```
- **YAML parse:** `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))'` over
  `.forgejo/workflows/containers-build.yaml`, `.forgejo/workflows/renovate.yaml` and
  `.github/workflows/docker-build.yaml`.
- **Neighbours — green must stay green:** `bash tests/services/forgejo-main-sync.sh` (8 ok),
  `bash tests/pipeline-push-pr/surface.sh` (10 ok), `bash tests/wekan-mcp/tools.sh` (10 ok),
  `bash tests/pipeline-models/surface.sh` (9 ok), `bash tests/renovate/dockerfile-pins.sh` (36 ok).
- **Agent-surface suites (`tests/agent-board-coord/{agents-md,gate,rulesync-surface}.sh`,
  `tests/agent-perms/surface.sh`) are NOT run -2 gates, and their redness is two different things:**
  (i) while the plan folder is **uncommitted**, their scope-fence legs read it as an out-of-scope change
  (`FAIL: c7: path outside C04's in-scope set: .agents/plans/…/chunks/C01.md`) — proven by replaying
  the same files in a scratch repo **with** a commit, where those legs pass; so the coordinator's
  commit, not an agent, clears that class; and (ii) with that gone, what remains is `main`'s own
  pre-existing staleness (`c11` runner-model pairing, `t17` coord-family contract, `c19` custom-field
  count — all red on a pure-`main` replay too). Neither class is run -2's to fix, and nobody should
  "repair" a scope fence by editing another ticket's rule source.

- **Not ours to clear (record, don't fix):** `kubernetes-mcp-version-floor.sh` (1 ok / k2 red),
  `chart-yaml-legs.sh` (10 ok / k5 + k10 red), `forgejo-ssh-gateway.sh`, `forgejo-ssh-audit-trail.sh`
  — each red on `main` too; run -2 must not make them worse and must not "fix" them silently (OQ-o).
- **Docs greps (C03):** the detection sentence present in
  `grep -n 'Detects changed container dirs' skills/container-creation/SKILL.md` (its neighbourhood gains
  the range/merge-base/loud-empty sentences) and `grep -n 'containers-build' AGENTS.md
  .rulesync/rules/overview.md`; x3's per-line rule holds — every gated-doc line naming
  `docker-build.yaml` must co-name `workflow_dispatch`. `AGENTS.md` is generated from
  `.rulesync/rules/overview.md`: edit the source, regenerate, commit both.
- **Quality gate:** `npx aislop ci --changes` → 0 errors / 0 warnings (branch-range posture,
  re-verified this pass: 0/0 over 106 files).
- **Renovate (MCP):** the DECISIONS-pinned **inline `configContent` route only** —
  `tools["dev-renovate"].check_setup` then `validate_config` / `test_package_rules` on the `renovate.json`
  text read from disk. That server has **no worktree visibility**; any leg needing path resolution is
  reported **NOT-RUN**, never as a pass. Run -2 changes no `renovate.json` byte (C02 edits the two
  *suites'* count constants, not the config), so this is a regression line; `x2` is the offline half.
- **`docker build => no-daemon, CI-deferred`** — the designed passing shape (cf-77). The live Forgejo
  run on a pushed branch would be the real build test and this run pushes nothing.
- helm lint/template: N/A (no chart touched).

## Chunks

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | Detection contract: pinned range, separated empty/first-push, merge-base PR arm, loud empty set (+ legs t12–t15, d9–d15) | M | 1 | [] | edits only `scripts/forgejo-container-detect.sh` + the `detect-changes` job; run -1's bytes it touches are comments/additions, so t/r/d/x/g ride unregressed |
| C02 | Close the ROLE convention: `renovate.yaml` guard → `contains(vars.ROLE,'dev')` + the cf-135 suite bytes that move with it (`GUARD`, its header line, the two `packageRules == 9` count pins → 10) | S | 1 | [] | independent of C01 (different files, different suites); it is what turns the merged tree's own `g1` red off — the full-suite 41-ok gate needs C01 **and** C02 |
| C03 | Docs: the detection contract in prose + the closed ROLE-convention sentence + `rulesync generate` + the x5 docs pin | S | 2 | [C01, C02] | the prose describes C01's shipped range/merge-base bytes **and** the repo-wide guard claim — that sentence names three `.forgejo` workflows and is a lie until C02's byte lands; x5 pins sentences that only exist after both |

## Wave order

1. **C01**, then **C02** (independent — C01 touches the detector + `detect-changes` + the containers
   suite's t/d groups; C02 touches `renovate.yaml` + cf-135's two suites + `g1`'s expectation; no file
   or leg overlaps; run in id order).
2. **C03** (docs after both behaviour chunks are final — its guard sentence needs C02's byte, its
   detection sentence needs C01's).
Final whole-plan review re-runs the full Commands list, including `bash
tests/services/forgejo-containers-build.sh` = 41 ok and both cf-135 suites green.

## Tests (agent-test authors every chunk's legs in one session before any dev; review re-runs first)

Containers suite 29 → **41**: `t12–t15`, `d9–d15` (C01), `x5` (C03). The leg-id parser's `case`
patterns and `group_t()`/`group_d()`/`group_x()` enumerations **must** be extended in the same commit
that adds the legs, and the usage/help string widened (it today reads `expected t1..t11, d1..d8,
x1..x4, r1..r5, g1`) — an id outside the enumeration is a **silently vacuous** leg and the printed
count is the only proof it ran (Risks R4).

| leg | invariant | asserts | what must go red |
|-----|-----------|---------|------------------|
| t12 | 1 | the `detect-changes` job's checkout step parses to `with: {'fetch-depth': 0}` (integer zero exactly; `1`, `'2'`, or an absent `with:` all red); the two build jobs' checkouts stay bare — the depth-0 cost is paid exactly once | **delete L85–88** (the owner's literal ask) or set any non-zero depth |
| t13 | 7 | the six `env:` accessor lines byte-exact as constants (`EVENT_NAME`/`EVENT_BEFORE`/`SHA`/`BASE_SHA`/`HEAD_SHA`/`MANUAL_CONTAINERS` ⇄ their `${{ forgejo… }}` sources), r1's discipline — and its ok line states the limit: a textual pin cannot prove the payload carries the field (R1 §1's source chain, and the optional H-P1 probe, do that) | a typo'd `forgejo.event.before` — today a silent tip-only green |
| t14 | 6 | the detect step echoes the assigned set on **stdout** with the marker `changed containers:`, names the event and the endpoints it holds, never re-inlines `$(…)` (t10), and emits `::warning::` when a push/PR resolves to `[]` — the empty **dispatch** list exempt; log-line claim only, no UI-chip wording | dropping the echo again (a port silently did exactly that — `EXPLORE` §5) |
| t15 | 5 | in `detect()` no git call carries a `\|\| true` / `2>/dev/null` / masking pipe and `set -eu` stays at the top; `next-n`'s tolerated `grep … \|\| true` (L88) stays exempt and the leg's text says so | re-adding the predecessor's silencing to the range diff |
| d9 | 2 | wide fixture **fix3** (A creates `containers/alpha`+`beta` with Dockerfiles + README → B changes **beta** → C changes **alpha**, tip): `EVENT_BEFORE=A SHA=C` ⇒ `["alpha","beta"]` — the non-tip commit IS detected | narrowing to `$SHA~1..$SHA` ⇒ `["alpha"]` — **the owner's fear shape, red offline** |
| d10 | 3 | fix3 **plus a tip-only commit E** (README), so `HEAD=E` while `SHA=C` (racing push): ⇒ still `["alpha","beta"]` — the range is the event's endpoints, never the checkout's | `HEAD^..HEAD` ⇒ `[]` |
| d11 | 4, 6 | all-zero `before` on the three-commit fix3 state ⇒ the chosen first-push posture byte-exact (`["alpha"]` = `HEAD^..HEAD`), **and** the stderr annotation naming it tip-only, **and** stdout still exactly one JSON line | a silent change of the fallback shape; any diagnostic on stdout (it would corrupt the `$GITHUB_OUTPUT` carrier) |
| d12 | 4 (A5) | **empty** `before` ⇒ non-zero exit + a message naming `before`, no JSON emitted (prototype: `die`, exit 2 — the number is dev's choice, "non-zero" is the pin) | reverting A5 (today: exit 0 + tip-only, the masking shape) |
| d13 | 5 | unreachable/garbage `before` (40 hex, not an object) ⇒ git's exit **128** propagates, stdout emits nothing | soft-pedalling the range failure back to green |
| d14 | 8 (**B5**) | PR fixture **fix4** (A creates `alpha`+`beta`; base then moves — `M` modifies `containers/alpha/Dockerfile`; head `H` branched at A modifies `beta`; `H` is the checked-out tree, so both Dockerfiles pass the existence gate): `BASE_SHA=M HEAD_SHA=H` ⇒ **`["beta"]`** — the merge-base posture, measured; adjacency parity also pins the no-op case: `BASE_SHA=A HEAD_SHA=H` ⇒ **`["beta"]`** (a base that *is* an
ancestor resolves to itself, so the d3/d1–d8-style adjacent cases do not move) | a revert to the raw
two-dot diff (⇒ `["alpha","beta"]`) — and this is why d3/d1–d8 stay green: verified under the
merge-base variant |
| d15 | 8 | PR degenerate shapes: empty `BASE_SHA` ⇒ exit **128**; empty `HEAD_SHA` ⇒ exit **128**; a genuinely **unrelated** base/head pair ⇒ non-zero exit (measured: **1** from `git merge-base`) — in every case no JSON emitted | a soft-fallback added to the PR arm, or `2>/dev/null` hiding the merge-base error |
| x5 | docs (C03) | the gated docs carry the detection contract: the SKILL/overview text names the pushed **range** (`before..sha`), the PR **merge-base**, the **loud empty** set and the **annotated first push**; and no line claims a UI annotation/run-page chip. Line-number-independent, keyed on stable markers, x3-shaped | a docs re-pin that drops the contract, or prose that over-claims the platform |

**Hand-off posture, stated honestly (not "all 12 red").** Of the 12 new legs, **6 are red-by-design** —
`t14` (no echo today), `d11` (no fallback annotation), `d12` (an empty `before` is green today),
`d14` and `d15` (the shipped two-dot arm answers `["alpha","beta"]` where the merge-base pin demands
`["beta"]`, and exits **0** with `["beta"]` on an unrelated base/head pair where the pin demands
non-zero) and `x5` (C03's prose does not exist yet). The other **6** (`t12`, `t13`, `t15`, `d9`, `d10`,
`d13`) are **green-at-authoring regression pins**: the contract they pin is present but unpinned, which
is exactly this run's thesis. Measured arithmetic on the merged tree (`7a82dfb21`):

| point | `t d` subset | full containers suite |
|---|---|---|
| today (29 ids, no new legs) | 19 ok | **28 ok / 1 FAIL** — the red is `g1` on `renovate.yaml` |
| after `agent-test` (41 ids) | **25 ok / 5 red** (`t14`, `d11`, `d12`, `d14`, `d15`) | **34 ok / 7 red** (+ `x5`, + `g1`) |
| after **C01** dev | **30 ok** | 39 ok / 2 red (`x5`, `g1`) |
| after **C02** dev | 30 ok | 40 ok / 1 red (`x5`) |
| after **C03** dev | 30 ok | **41 ok / 0 red** (`x` subset = 5 ok) |

Every green-at-authoring pin must be proven reddening by the mutation column — a pin no mutation can
redden is a vacuous leg: report it, do not ship it. The reviewer re-runs the mutations on a scratch
copy (the `/tmp/opencode` fixture-tree precedent — every scratch tree needs `git init`, FRICTION).

## Human legs (owner; enumerated, not implemented)

- **H-P1 (optional, live-only):** one-dispatch `toJSON(forgejo)` payload probe on a scratch branch, to
  upgrade "`before` is always present" from *proven at tag v15.0.10* to *observed on this instance*.
  Not a precondition — A5 makes a wrong payload self-announcing on the first real run.
- **H-P2 (live-only):** at the first real run, confirm the new log lines appear (the `changed
  containers:` echo, the first-push `::warning::`) and that the merge-base PR arm behaves as pinned.
  Log text is the expected outcome; annotation rendering is not owed by this build.
- **H-P3 (new, config):** the cf-135 live probe leg `t9` is default-OFF
  (`FORGEJO_RENOVATE_PROBE=1`) and network-gated — leave it off in agent sessions; if the owner ever
  runs it, it belongs to cf-135's card, not to run -2.
- **Unchanged and still standing from run -1 (this run touches none):** **H1** infra `ROLE` →
  `dev,prod` only *after* cf-6's C04 has merged — and read it together with Risks R5: with C02's
  migration, a `dev,prod` instance **also starts running the daily Renovate pass** where `== 'dev'` did
  not (that consequence is OQ-p). **H2** dev `ROLE=dev` before that runner ever picks up a task.
  **H3** the two non-admin `write:package` PATs + per-instance `FORGE_PUSH_TOKEN`. **H7** the
  two-registry live smoke. **H8** Cleanup Rules strictly `pr-.*`. Lead-the-hand-off fact, unchanged:
  until H3 lands, **any** `containers/**` merge to `main` goes loudly red at the login step.

## Deferred shapes (considered, declined or parked by ruling — each returns only as a plan amendment)

- **A2 / A3** (first push fail-wide vs the empty tree / merge-base against `origin/main`) — **deferred
  by ruling**; A2 would enqueue up to 13 matrix builds on a capacity-1 runner for a shape that is
  unreachable behind `branches: [main]`. d11 is the pin that keeps the chosen posture honest.
- **B2 / B3** (depth-1 + targeted fill; `filter: blob:none`) — **declined / parked by ruling**, with the
  numbers kept (172 ms fill; 5.8 MiB blobless; 21.23 MiB / 1,849 ms for depth-0).
- **B6** (cadence/rebuild-all hatch) — declined: `workflow_dispatch` already names its list; a scheduled
  full rebuild starves the capacity-1 runner.
- **`--merge-base` flag form** — declined in favour of hand-rolling (no git ≥ 2.43 dependency; OQ-g
  moot). A future runner-image fact could reverse it, and that is a re-pin, not a silent switch.
- **`g1` relaxation** — rejected outright: the answer to the merged `renovate.yaml` collision is
  migrating the byte (C02), never weakening the repo-wide sweep.

## Risks / assumptions

1. **Co-tenancy, and now on the docs too.** This run holds `[CICD]` **exclusively** (setId `9cb75b2c`),
   but card 55 (`Move GitHub parallel helm builds to Forgejo`) still sits in **Executing** with no live
   lock, and its kind of work collides on `.forgejo/workflows/` **and** — since OQ-l put docs in this
   run — `overview.md`/`AGENTS.md`/`skills/container-creation/SKILL.md`. Landing order stays as ruled in
   run -1 (OQ-11: cf-6 first, 55 rebases). Mitigation: one concern per commit; C03 is the only docs
   chunk, and `rulesync generate --check` is the arbiter that the generated surfaces match their source.
2. **The merged tree's own `g1` is red until C02 lands.** The 41-ok gate needs C01 **and** C02; a review
   of C01 alone sees `28 ok / 1 FAIL (g1)` and must read that as C02's pending byte, not a C01
   regression (the chunk files say so).
3. **Red-on-arrival beyond us.** Two cf-135 count legs (`forgejo-renovate t8`, `forgejo-move-config m5`)
   are red because *our* branch carries the 10th `packageRule`; C02 re-pins them by ruling. The rest
   (`kubernetes k2`, `chart-yaml k5/k10`, the `forgejo-ssh-*` suites) are red on `main` too. If a later
   leg-widening by another card lands, re-check this list rather than assuming run -2 broke it.
4. **Vacuous-green enumeration trap.** The full set runs only what `group_*()` enumerates; a new id
   without a `case`/group entry never executes (it would print a green count 12 short). AC4/Commands
   pin the printed totals (30 / 41) as the proof.
5. **C02 changes *who runs the Renovate job*.** `contains(vars.ROLE,'dev')` fires on a `dev,prod`
   instance where `== 'dev'` did not. Infra (`prod`) and dev (`dev`) behave exactly as before and unset
   stays narrow/fail-safe (the `main-sync` class), so nothing today moves — but run -1's **H1** flip
   (`dev,prod` on infra) would now also turn on the daily Renovate pass there. Surfaced as **OQ-p**
   with the accept-best-guess; not decided silently, and not acted on in code beyond the migration.
6. **B5 trades a benign waste for a new loud failure.** Over-detection (base-side changes rebuilt into a
   PR tag) disappears; a PR branch with rewritten/unrelated history now exits non-zero
   (`git merge-base` → 1) where the two-dot diff quietly produced a set. Accepted by ruling and pinned
   by d15 — but it is a real behaviour change on a workflow that has **never executed**, so the first
   observation is live (H-P2).
7. **A5 is this run's only green→red** (empty `before`): source-proven unreachable for git-push and
   mirror events, so red is the honest answer to its appearance; rejected alternative was
   warn-and-scan-the-tip, which *is* the defect. Zero live runs have ever documented the old shape
   (`EXPLORE` §8), so nothing observed breaks.
8. **The channel split is load-bearing.** Detector diagnostics go to **stderr only** — stdout is the
   captured JSON carrier for `changed=$(…)` → `changed-containers=` (t10). d11 pins the purity.
9. **Annotation over-claim risk.** No surface (chunk, RESULT, docs, C03 prose) may call the new lines
   UI chips or run-page summaries; on this build they are log text. x5 pins the absence of such wording.
10. **cf-135's `t3` sweep constrains C02's comment text.** The literal token `vars.ROLE` may appear only
    in the job `if:` and the diag echo — a header gloss naming it reddens `t3` (proven this pass). The
    migration therefore re-words the header without that token; the alternative (relaxing cf-135's leg)
    is rejected as weakening another card's contract.
11. **No live `docker build`, no daemon, no push.** `docker build => no-daemon, CI-deferred` is the
    designed passing shape (cf-77); C01 has no build AC and none is faked.

## Open questions — ANSWERED by the owner batched round (2026-11-13); two new ones surfaced

Authoritative record: `DECISIONS.md` "owner batched-round answers". One line each, with the impact the
plan now carries:

- **OQ-a — ANSWERED A1+A4+A5:** first push stays `HEAD^..HEAD` with an announced narrowing; empty
  `before` exits red via `die()`, exit number dev's choice. Impact: d11/d12; A2/A3 deferred with
  reasons (B5's merge-base is *not* A3 — it is the PR arm).
- **OQ-b — ANSWERED ADOPT B5, hand-rolled:** PR arm diffs `git merge-base` → head. Impact: d14 flips to
  `["beta"]`, d15 gains the unrelated-history case, the merge-base error text must stay visible on
  stderr, and **OQ-g closes as moot** (no `--merge-base` flag, so no git ≥ 2.43 dependency to verify).
- **OQ-c — ANSWERED keep `fetch-depth: 0` (B1):** B2/B3 declined for this run with the measured numbers
  on the record. Impact: t12 pins the byte; the comment carries the causality.
- **OQ-d — ANSWERED park (blobless).** Impact: none; recorded as considered-and-declined.
- **OQ-e + OQ-k — ANSWERED BOTH:** always echo set + event + endpoints; `::warning::` on an empty
  push/PR set; `before == sha` and an empty dispatch list stay un-annotated. Impact: t14; the platform
  log-only truth travels with it (RESEARCH §7).
- **OQ-f — ANSWERED optional owner leg (H-P1), not a precondition.** Impact: Human legs section.
- **OQ-g — CLOSED AS MOOT by the OQ-b ruling** (hand-rolling removes the version dependency; no probe
  owed). Impact: nothing to run; recorded so nobody re-opens it.
- **OQ-h — ANSWERED fact only:** `total_commits` reads `0` here; no code change, and the header-comment
  sentence in C01 keeps it visible to the next reader.
- **OQ-i — ANSWERED fact:** mirror `v6` byte-equality resolved by research; the residual unknown
  (checkout's ref-race drift guard on the act containers) stays unstated.
- **OQ-j — ANSWERED MIGRATE HERE:** cf-135's `renovate.yaml` joins the membership convention in C02,
  with its suite's `GUARD`/header/count bytes moving in the same commit. Impact: the run's own `g1`
  green; the merge-before-flip sequencing of R1 §2's truth table preserved; **this supersedes the
  draft's "gate on the pre-merge base, no rebase" deviation** — `main` is in at `7a82dfb21`.
- **OQ-l — ANSWERED docs NOW:** C03 owns the prose (SKILL.md + overview.md + `rulesync generate` +
  `--check`) and the **x5** docs pin; `AGENTS.md` changes only as generated output.
- **OQ-m — ANSWERED as "dev's choice":** `d12` pins **non-zero**, not a number, so A5's failure channel
  stays with the implementer (the `die()` exit-2 route is the prototype's shape, not a requirement).
  Impact: none on the leg text.

**NEW, still open (best guess taken, plan written to it):**

- **OQ-p (renovate semantics):** `contains(vars.ROLE,'dev')` means a `dev,prod` instance starts running
  the **daily Renovate pass**, which `== 'dev'` withheld — i.e. run -1's H1 flip would add infra as a
  second PR-opening writer. *Best guess: accept* — the membership convention is the repo's stated rule,
  infra is the box with the proven runner, and cf-135's own intent line reads as a role test, not an
  identity test. Alternatives: a dedicated `vars.RENOVATE_HOST`-style flag (OQ-8 already rejected new
  per-instance variables) or re-confirming H1's value at flip time. Impact if you disagree: C02's guard
  byte changes shape and its docs sentence changes; no C01 work moves.
- **OQ-o (whose reds are these?):** `kubernetes-mcp-version-floor.sh k2` (expects `packageRules == 8`,
  sees 9 on `main`, 10 here), `chart-yaml-legs.sh` k5/k10, and the `forgejo-ssh-gateway.sh` /
  `forgejo-ssh-audit-trail.sh` legs are red on `main` independently of run -2. *Best guess: leave them,
  record, and card separately* — run -2 already owns exactly the two count re-pins its own merge broke
  (C02's t8/m5). Impact if you say fix-them-here: +1 chunk of other tickets' suite bytes, which widens
  the co-tenancy surface for no run -2 benefit.
