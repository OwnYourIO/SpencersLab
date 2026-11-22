# PLAN: builder-bootstrap-1 — reduce the recovery lane to its single purpose: the build image
feature: 2026/2026-11-cf-6-feat-builder-bootstrap-1
status: draft — v1, the scope-reduction run of the merged base lane (cf-6-feat-builder-bootstrap,
merged 2026-11-22 as f236be07f/ae7c7e64b/1d6d56dc0).
Model routing: every tier `openrouter/qwen/qwen3.8-flash` (kickoff STATE, standing directive).

## Goal
Per the human ruling of 2026-11-22, reduce `.forgejo/workflows/builder-bootstrap.yaml` to the ONE
thing the lane is responsible for: on a `prod`-role instance, a bare dispatch (no input — the
silent-empty trap the owner hit becomes structurally impossible) (re)mints the lab's BUILD IMAGE
`containers/forgejo-runner` — the baked job image whose absence IS the paradox — to ghcr + the
building instance's own registry under the surviving calendar law. The dispatch input, the detect
step and the matrix go away; the workflow, its contract suite and the law/docs surfaces move in
ONE change so nothing on any live surface still claims the lane serves "any named container".

## Out of scope
- Re-litigating the ruling or the surviving base rulings: dispatch-only (OQ-3), the
  `ubuntu-22.04` public-label paradox guard, the narrow bare `contains(vars.ROLE, 'prod')` guard
  (no widening), the calendar law (both walks before push, union max, `yy.mm.N`, no
  skip-if-exists — re-dispatch mints N+1, gaps-by-design), targets ghcr→own in that push order,
  the P4' closed credential surface, the NO-PEER ruling (dev copy stays the owner manual push),
  the detector + `containers-build.yaml` byte-untouched law. Recorded, not reopened. The general
  any-container lane (base OQ-2) is SUPERSEDED — do not re-offer it.
- `charts/**`, `services/**`, `custom-values/**`, `.github/**`, the 11 run-1 paths, and every
  `tests/**` file EXCEPT `tests/services/forgejo-builder-bootstrap.sh` — in particular
  `forgejo-ci-surface.sh` (five-set UNCHANGED: the file persists) and
  `containers/forgejo-runner/README.md` (already single-purpose-true — byte-untouched expected,
  proven in the bar).
- Any live dispatch/push/merge — post-merge OWNER legs (OL0–OL9 below); readonly probes only in
  agent sessions.

## USER-RULED ask (recorded)
1. 2026-11-22 human: "the bootstrapper doesn't work when blank is entered. It should really only
   be responsible for building the build image anyway." → lane = `containers/forgejo-runner` only,
   NO dispatch input at all. Blank-dispatch no-op was verified SHIPPED-CORRECT (family
   silent-empty law, b8-proven) — this is design removal, not bug repair.

## Verified facts (plan session 2026-11-22 ~17:10–17:25Z, read-only; branch @ 1d6d56dc0 == origin/main tip)
1. **Baseline**: clean tree at `1d6d56dc0` (untracked: this ticket folder only). The base lane
   SHIPPED today; `origin/main`'s `builder-bootstrap.yaml` is the file this reduction rewrites.
2. **Registries STILL empty (re-probed live this session, curl works in this agent env — the
   coord-floor curl denial does NOT extend here)**: ghcr token exchange
   `?scope=repository:ownyourio/forgejo-runner:pull` → **403** (the absent-vs-private shape);
   `git.spencerslab.com` and `git.scifi.farm` both answer `/api/v1/packages/curatedforest?type=container`
   → 200 `[]` (org has ZERO container packages) and `/v2/curatedforest/forgejo-runner/tags/list`
   → 401 anonymously (package absent). ⇒ the owner's earlier dispatch minted NOTHING publishable;
   the first dispatch of the reduced lane legitimately mints **26.11.1** (this month) — the tag
   the merged run-1 labels pin.
3. **Actions-API gap CLOSED as far as the anonymous surface allows**: `runs?workflow_id=builder-bootstrap.yaml`
   → total_count **1** (id 222, the only run since the file reached main), anonymous row sparse
   (run_number/event/created_at/head_sha null, `status` unreliable per base FRICTION) and the jobs
   sub-endpoint is not anonymously readable. Whether run 222's input was blank or `all` is
   INCONCLUSIVE and design-irrelevant: the outcome (zero publishes, fact 2) is registry-proven,
   the input surface is going away. Not spinning further (launch instruction).
4. **Shipped bytes (the reduction surface)**: input block L54–61 (`on.workflow_dispatch.inputs.containers`);
   `detect` job L67–111 (guard, diag, `pick` step: `all`-expansion + detector `detect` call +
   job outputs); `publish` job L113–322 (matrix over the detect output, `!= '[]'` skip clause,
   `name:` templating, fail-fast, diag + 2 logins + 2 walks + build&push). 7 embedded run blocks.
   The walks consume `scripts/forgejo-container-detect.sh next-n` (L174, L242) — month math.
   Push trio `$month.$n` + `latest` + `main` per side, ghcr-then-own — byte-parity with
   containers-build's release arm (its L338–339, re-read).
5. **Suite baselines on this tree**: `forgejo-builder-bootstrap.sh` PASS 20 ok against the shipped
   file (run this session); `forgejo-ci-surface.sh`: t1 five-set GREEN, red ONLY at t4 (two FAIL
   lines, carried deferral — run this session). `GPU_RUNNER_DIFF_BASE` defaults to `main`/
   `origin/main` and SKIPS g7 without a resolvable ref (its L69/L690) ⇒ the bar pins the literal
   sha with a resolve-check (vacuous-green trap law).
6. **Residue inventory for "any named container" / "any container's" / "name the containers"**:
   LIVE lane surfaces = `AGENTS.md` L513 + `.rulesync/rules/overview.md` L511 (twin pair), `SKILL.md`
   L114+L119, workflow header L1, suite header L3 — all six move or die in this change. Two
   scoped exclusions found by running the bar grep early: `containers-build.yaml` L78 says "name
   the containers" about ITS OWN dispatch input — true, FORBIDDEN path, exempt; and the rewritten
   SUITE will legitimately carry the phrases inside b9's prohibition tuples (teeth, not lies). The
   residue pin therefore greps exactly the five lane surfaces (builder-bootstrap.yaml, the twin
   pair, SKILL, containers/, AGENTS.md). History
   folders (`.agents/plans/2026/2026-11-cf-6-feat-builder-bootstrap/**`, this ticket's DECISIONS)
   keep the wording as dated record — append-only history, not a lie; the residue pin is scoped to
   live surfaces (R9). `containers/forgejo-runner/README.md` is ALREADY single-purpose-true
   ("it is what mints this image when the baked reference is missing") — untouched.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | single-purpose builder-bootstrap (no input, no matrix, fixed build image) + suite rewrite + law/docs twin in one change | M | 1 | [] | — |

ONE chunk (same-change law: rewriting the workflow without the suite/docs leaves a lying surface
either way — the suite would pin the dead general shapes or the docs would still say "any named
container"). Validation folds into the Commands bar (run-1/base precedent); owner legs are never
chunks.

## Wave order
1. C01 — TEST first (REWRITE `tests/services/forgejo-builder-bootstrap.sh` to the target leg list
   in the chunk — designed-RED against the still-general shipped file; `forgejo-ci-surface.sh`
   byte-untouched), then DEV (workflow rewrite + `.rulesync/rules/overview.md` lane sentence +
   `rulesync@37.0.0 generate` → `AGENTS.md` twin + `skills/container-creation/SKILL.md` paragraph).
   Chunk review re-runs the bar; the final whole-plan review re-runs everything + the owner-legs
   package.

## Commands (the validation bar — landing tree)
```bash
export PATH=$HOME/.local/bin:$PATH
BASE=1d6d56dc0   # ALWAYS resolve-check first: git cat-file -t $BASE => commit (vacuous-green law)
bash tests/services/forgejo-builder-bootstrap.sh   # PASS: forgejo-builder-bootstrap checks (20 ok) — rewritten suite, new shapes
bash tests/services/forgejo-ci-surface.sh          # t1 FIVE-set green; red ONLY at t4 (two FAIL lines, carried)
bash tests/services/forgejo-containers-build.sh    # 41 ok — untouched
bash tests/services/forgejo-main-sync.sh           # 8 ok
bash tests/services/forgejo-renovate.sh            # 8 ok (+ t9 default-off skip)
bash tests/renovate/forgejo-move-config.sh         # 8 ok
bash tests/services/dev-forgejo-runner.sh          # 58 ok
GPU_RUNNER_DIFF_BASE=$BASE bash tests/services/gpu-forgejo-runner.sh   # 19 ok — RESOLVE-CHECK $BASE first
bash tests/containers/forgejo-runner.sh            # 8 ok — README untouched (proven in the diff below)
# unchanged-surface byte-proofs (each must be EMPTY vs BASE):
git diff $BASE --exit-code -- .forgejo/workflows/containers-build.yaml scripts/forgejo-container-detect.sh
git diff $BASE --exit-code -- tests/services/forgejo-ci-surface.sh containers/forgejo-runner/README.md
# input-surface absence (accessor-level, comment-safe; each grep EMPTY):
grep -nE 'forgejo\.event\.inputs|inputs\.|MANUAL_CONTAINERS|matrix\.' .forgejo/workflows/builder-bootstrap.yaml
grep -nE 'forgejo-container-detect\.sh[[:space:]]+detect' .forgejo/workflows/builder-bootstrap.yaml
# single-purpose pins:
grep -cE '^[[:space:]]*docker build ' .forgejo/workflows/builder-bootstrap.yaml  # => 1 (the command line; comment prose is excluded by the line-anchor; its final arg is "containers/forgejo-runner" — b8 pins parsed)
grep -rlE "any named container|any container's|name the containers" \
  .forgejo/workflows/builder-bootstrap.yaml .rulesync/rules skills/container-creation AGENTS.md containers  # EMPTY (lane-wording surfaces ONLY; the suite embeds the banned phrases inside b9's prohibition tuples — teeth, not lies — and is exempt by design, its truth-pinning is b9 itself; containers-build.yaml L78 "name the containers" describes ITS OWN dispatch input, is true there, and the file is FORBIDDEN; history folders excluded)
npx --yes rulesync@37.0.0 generate --check          # sources moved + twin current
python3 - <<'PY'                                    # five .forgejo workflows parse + True-key probe each
import glob, yaml
for p in sorted(glob.glob('.forgejo/workflows/*.yaml')):
    d = yaml.safe_load(open(p)); assert (d.get(True) or d.get('on')) , p
PY
# b10 recount: 5 extracted run blocks (was 7), each bash -n clean — the suite prints it; local mirror:
# yaml-extract all `run:` bodies of builder-bootstrap.yaml to /tmp/opencode and bash -n each => 5 files rc 0
npx --yes aislop ci --changes                       # quality gate (score floor, zero errors)
# docker build => no-daemon, CI-deferred (the lane's own live build proof is owner OL2)
```
No helm render moves (nothing under charts/ or services/ changes). No cluster mutation, no
dispatch, no push in any agent session.

## Rulings (planner; the launch brief's design forks ruled here)
- **R1 NO-INPUT TRIGGER**: `on: workflow_dispatch` with NO `inputs:` section anywhere (b1 parses
  the keyset AND walks the doc for any `inputs` mapping; accessor greps stay EMPTY). The anti-trap
  leg: the owner's silent-empty failure mode is structurally impossible AND the battery re-probes
  it (bt9 = "restore the dispatch input" ⇒ b1 red). Rejected: keeping `containers` defaulting to
  `forgejo-runner` — a default input is still the trap's door left ajar.
- **R2 SINGLE JOB**: one job `publish` (name kept — it is b5/b6/b10's anchor, minimal honest move),
  guard = the bare prod membership ONLY (no `!= '[]'` clause — no matrix to skip), no detect job,
  no strategy/matrix/needs/outputs, no fromJSON anywhere (b3/b4).
- **R3 DETECTOR CONSUMPTION**: the `detect` mode call DIES (no list exists to gate); the shared
  script's `next-n` month math STAYS (two calls, YYMM env) — it is part of the SURVIVING calendar-
  law mirror ("both walks… union max") and re-inlining the arithmetic would fork the month math
  away from containers-build's proven single source (P6 reuse law). The b7 leg flips to pin BOTH
  halves: next-n present ×2, detect-mode call FORBIDDEN (its return is the general-lane sneak-in).
  This is the one genuinely owner-forkable call — best-guess ruled here, surfaced as OQ-1.
- **R4 FIXED TARGET**: `containers/forgejo-runner` is the ONLY build context (b8 — repurposed from
  the dead behavioral leg: context pin + the two image refs naming `forgejo-runner` + NO name
  variable/list/expansion of any shape). b2's old raw-text ban on `ownyourio/forgejo-runner`
  COLLIDES with the legitimate literal refs and MOVES: the paradox is pinned on the SCHEDULING
  surface (every `runs-on` == ubuntu-22.04, none contains `forgejo-runner` or a baked-family
  label; zero `docker://` raw).
- **R5 ROLLING TAGS: YES** — the trio per side (`:yy.mm.N` + `:latest` + `:main`) survives
  unchanged: byte-parity with containers-build's release arm (fact 4). The lane re-mints exactly
  what the release arm would have.
- **R6 WALK ARMS**: ghcr + own only — the NO-PEER ruling and b6's closed credential surface are
  byte-stable (no `FORGE_*_DEV`/`PUSH_*_DEV`/second-instance name; exactly two logins, two push
  chains, ghcr-then-own).
- **R7 F1 ABSORBED** (the base review's deferred lexical-skip-ban advisory): this suite rewrite
  re-opens `tests/**` — its stated natural home — and b5 gains the SEMANTIC pin: every
  `docker push` sits unconditionally in its attributed `for` chain (no if/while/case wrapper
  with `continue` around any push; battery probe wraps one ⇒ b5 red). F1 closes as
  adopted-with-reason (DECISIONS); the shipped file is already push-unconditional, so DEV is
  unaffected.
- **R8 FENCE SURFACES: NOTHING moves** — ci-surface t1's five-set is UNCHANGED (file persists;
  re-verified green this session) and the suite file is byte-proofed in the bar; x4/agent-board-
  coord suites: no `.forgejo` family-count claims (base fact 7, unchanged); g1 re-sweeps the
  rewritten file from day 1 (URL/ban substrings, comment zone counts).
- **R9 DOCS**: `.rulesync/rules/overview.md`'s lane sentence ("(re)mints any named container…")
  reworded to the single-purpose truth (dispatch, no input, mints the lab's build image,
  ghcr + own, public act-22.04, prod-role narrow guard); the five-workflow + narrow-class ROLE
  enumeration paragraph SURVIVES UNCHANGED (still five, still narrow); `rulesync generate` moves
  the AGENTS.md twin in the same change; `SKILL.md`'s Bootstrap-lane paragraph reworded (the
  "name the containers, or `all`; an empty list builds nothing" clause dies); README byte-kept
  (already true). The residue pin (fact 6) is scoped to live surfaces — plan-record history
  stays append-only and is not a lie. b9 re-pins the new truth: lane blocks must NOT claim
  any-container/all/empty-list service, and must state the no-input dispatch.
- **R10 COMMIT/RECORD SHAPE**: one new commit on `cf-6-feat-builder-bootstrap-1` @ 1d6d56dc0
  (no staged-set to protect this time); coord commits (compact `-m` shape per the standing
  ruling — long bodies get floor-rejected); push/PR/merge stay owner-owned (repo hard rules).
  PR-body caveats: (i) the lane is now SINGLE-PURPOSE — the base run's OQ-2 general-lane ruling
  is SUPERSEDED by this change and its doc sentence moves here; (ii) the run-1 freshness prose
  caveats inherited from the base final review (values/slice "both registries" duty wording +
  values L122 "no job requests it") STILL ride — lane-card home, unchanged.

## Owner legs (re-sequenced — the recovery story, this time FOR REAL; every one user-owned)
- **OL0** infra repo Settings presence check: `FORGE_PUSH_TOKEN` + `GHCR_PUSH_PAT` (no new
  config; base OL0 unchanged — the credential surface is byte-stable under R6).
- **OL1** merge THIS reduction PR (the base lane already merged; one commit rides).
- **OL2** `workflow_dispatch` of builder-bootstrap on INFRA, ref main — **NO INPUT, just
  "Run workflow"** (the trap is gone: a dispatch does the one thing) ⇒ mints `26.11.1` (fact 2;
  `26.12.x` on month-cross) at 3 tags × {ghcr, infra registry}; make the packages PUBLIC once
  (org UI + ghcr) if defaults differ. A timeout red is retry-safe (gaps-never-clobbers; each
  retry resumes warm).
- **OL3** owner manual dev-copy build+push (the standing NO-PEER cost, base OL3 unchanged): tag
  `git.scifi.farm/curatedforest/forgejo-runner:<literal OL2 ACTUALLY minted>` + `:latest`/`:main`,
  DEV-instance non-admin `write:package` PAT, package PUBLIC on the dev org. NEVER a predicted
  literal — OL2 first, OL3 second.
- **OL4** the two anonymous probes, PASS-ALL gates (infra verifies OL2, dev verifies OL3):
  token+manifest curls + un-logged pull belts on both hosts for the minted tag. NOTE: anonymous
  registry probes ARE executable from agent sessions (curl worked this session, fact 2) — the
  owner may have an agent run the probe half, but the JUDGEMENT and all mutating legs stay
  owner-owned.
- **OL5** GitHub-main hand-push (plain non-force FF of the merged forge tip; the backlog breaker).
- **OL6** ArgoCD syncs + both runner StatefulSets restart (quiet window; the dev side ONLY with
  OL4's dev probe green — never deploy the dev runner into pull-death).
- **OL7** gpu-side verification: a dead PR run re-runs ⇒ jobs pull the baked label refs and
  `docker build` works inside; optionally re-run the push ⇒ containers-build's release arm now
  LEGITIMATELY mints `26.11.2` to ghcr+infra — dev copy does NOT follow (every bump repeats
  OL3; the lane card owns the automation question).
- **OL8** main-sync heals: one healed run fans GitHub + dev mirror; check `git ls-remote dev main`.
- **OL9** dev-side verification: a dev PR touching `containers/**` publishes `pr-<branch>-<sha>`
  on the dev runner pulling its OWN registry copy (OL3's).

## Risks / merge caveats
- **MONTH-CROSS COUPLING**: today's ruling assumed the dispatch lands in November ⇒ mint `26.11.1`
  == exactly what the MERGED run-1 per-release labels pin (both sites). If OL1+OL2 slip into
  December, the walk mints `26.12.1` and the PINNED LABELS (already on main from f236be07f) need
  the paired amend PR to the SAME literal at both sites — same coupling law as the base plan,
  owner-owned; OL3 targets the actually-minted literal regardless.
- **Dev runner stays dead until OL3** (unchanged base risk): OL4's dev probe is the loud gate —
  forgotten OL3 surfaces RED, never a silent half-heal.
- **First-cold-mint physics**: act-22.04 (~10GB-class base) has never been pulled by this daemon;
  several GB onto the 10Gi docker-data PVC (cf-55 prune-escape rides its retest seed); the 30-min
  ceiling is survivable by law (gaps, not clobbers; retries resume warm).
- **Renovate churn on the paradox line**: the b2 runs-on pin + human-merge posture fence it
  (base risk carried, teeth re-pinned by the rewritten b2).
- **Dispatch-on-dev is inert by design** (narrow guard; recovery is prod-role-only).
- **No-suite-lies**: after this change no live surface may describe any-container service (fact 6
  residue grep EMPTY); a doc line naming `docker-build.yaml` must co-name `workflow_dispatch`
  (x3); b9 is the doc pin, not a suggestion.
- The one anonymous-API fact (run 222, no publish) cannot bind the earlier run's input value —
  deliberately not chased (fact 3); nothing in the plan depends on it.

## Deferred (follow-up card seeds — inherited set, unchanged minus F1)
- Lane-design card: per-registry pin reads, published-not-predicted guard, DEV-COPY AUTOMATION
  question (the permanent manual OL3), run-1 freshness-prose alignment (values/slice wording).
- UA-10 probe card; run-1 carried set: post-heal `26.11.2` re-pin pair, ghcr absent-vs-private
  settle, cf-55 retests (94/97/101/106), ci-surface t4, t9-exemption retirement.
- F1 REMOVED from this list — absorbed by C01 (R7, adopted-with-reason in DECISIONS).

## Open questions
- **OQ-1 (best-guess-first, non-blocking)**: R3 keeps the shared detector's `next-n` month-math
  consumption (two walk calls) while killing the `detect`-mode gating — RECOMMENDED, it holds the
  calendar-law mirror byte-honest to containers-build and avoids forking the arithmetic. The
  alternative (inline the month math, zero shared-script calls) is recorded; adopt only on the
  owner's word — nothing else about the reduction turns on it.
No other genuine forks: rolling tags (R5 YES), walk arms (R6), fixed path (R4), suite shape and
F1 (R7) are ruled above per the launch's recommendations; coord books approval on this package.

## RESULT handoff
Plan file + chunks/C01.md authored; DECISIONS appended (rulings R1–R10 + rejected alternatives +
F1 adoption); STATE.json: chunk table {C01 pending, wave 1}, `plan_status: draft`,
`updated_at` via `date -Iseconds`, F1 moved from deferred to recorded-adopted.
