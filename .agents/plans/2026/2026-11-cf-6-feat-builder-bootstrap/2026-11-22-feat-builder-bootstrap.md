# PLAN: builder-bootstrap — a public-image dispatch lane that self-mints container calendar tags
feature: 2026/2026-11-cf-6-feat-builder-bootstrap
status: draft — v2 REWORK 2026-11-22: batched owner round RESOLVED (OQ-1 DEVIATED to **NO PEER**,
superseding plan P4; OQ-2/3/4 CONFIRMED; OQ-5 MOOT by the OQ-1 answer — DECISIONS L(2026-11-22
owner round)). P-series kept unedited below with P4′/P7′ supersession entries; `plan_status`
stays draft — coord books final approval on this package.
Model routing: every tier `openrouter/qwen/qwen3.8-flash` (kickoff STATE).

## Goal
Break the bootstrap paradox that has killed every forge container publish since 2026-11-16: add
`.forgejo/workflows/builder-bootstrap.yaml`, a dispatch-driven recovery lane whose jobs run on the
PUBLIC `ubuntu-22.04` label (→ `ghcr.io/catthehacker/ubuntu:act-22.04` — schedulable today and in
the staged run-1 end state) and can (re)publish ANY container's calendar tags — to **ghcr and the
building (prod-role) instance's own registry** (owner ruling: NO peer/cross-host target) — using
the live in-pod dind socket. Owner-wise it replaces run-1's manual L1 laptop build FOR THE INFRA
+ ghcr sides: after the two-commit PR merges, a bootstrap DISPATCH from the infra instance mints
`26.11.1` to ghcr + `git.spencerslab.com/curatedforest`, healing the infra runner. The
dev-registry copy the staged dev labels pin stays an OWNER MANUAL PUSH (fact 13).

## Out of scope
- Re-litigating the human rulings (STATE `human_rulings` + the owner round): general any-container
  lane, two commits one PR, deploy loses manual L1 **on the infra side**, and **NO PEER** — no
  cross-host push capability, no new secrets/variables; a future cross-host arm needs a fresh
  owner ruling (the new suite reddens it). Recorded, not reopened.
- Re-pointing the DEV labels at ghcr/infra refs — owner-REJECTED in the round; NOT re-proposed.
  The manual dev push (OL3) is the accepted cost of the no-peer ruling.
- `containers-build.yaml` + `scripts/forgejo-container-detect.sh` content (41-suite contract text;
  the detector is REUSED UNCHANGED — P6), `charts/**`, `services/**`, `custom-values/**`,
  `.github/**`, and the 11 staged run-1 paths (commit 1's content — untouched).
- Renovate label-pin lane, UA-10 probe card, post-heal re-pin pair — run-1's Deferred set stands
  (the lane card gains the dev-copy automation question, Deferred).
- Any live dispatch/push — post-merge OWNER legs (OL0–OL9). No cluster mutation in any agent
  session; readonly probes only.

## USER-RULED asks (recorded)
1. New workflow uses a publicly available job image to get the building started (CI self-mints;
   manual owner pushes rejected as the standing fallback — infra side; see 4 for the dev-side
   carve-back).
2. GENERAL lane: dispatch names containers, `all` supported; not forgejo-runner-only.
3. Lands as commit 2 on `cf-6-debug-forge-runner-docker-1`; one PR carries labels + bootstrap.
4. **Owner round 2026-11-22 — NO PEER**: builder-bootstrap publishes ghcr + the infra instance
   registry ONLY. The dev-registry copy is an owner manual push now and on every future bump
   (the freshness trap is permanent repo-side and rides the deferred lane card).

## Verified facts (plan session 2026-11-22 ~14:05–14:25Z read-only; 1–12 from the first round
stand, 13 is the rework-round grounding)
1. **Baseline**: branch `cf-6-debug-forge-runner-docker-1` @ `a49003152` == `origin/main` (re-
   fetched, unmoved); the run-1 landing (5 repo files + 6 ticket files) STAGED, untouched by this
   session. Mirrors still frozen: `upstream` HEAD and dev mirror main both `8dc73a71a`
   (`git ls-remote`).
2. **Registries still empty** (owner has NOT run manual pushes): ghcr `ownyourio/forgejo-runner`
   token exchange → 403 DENIED (absent-vs-private, run-1 §3 shape); BOTH instance registries,
   anonymous bearer token → tags/list 404 NAME_UNKNOWN and
   `/api/v1/packages/curatedforest?type=container` → 200 `[]`. All calendar lines provably
   empty ⇒ the first publish walks to `<yy.mm>.1` = **26.11.1 today** (the tag the staged labels
   pin). Month-cross rule: the walk follows the PUBLISHING month, so a December dispatch mints
   `26.12.1` and the owner amends both pin sites in one follow-up PR BEFORE judging the probes —
   and the OL3 manual dev push then targets that SAME literal (all pin sites + all minted copies
   move together).
3. **Outage live**: the infra daemon (gpu pod, started 00:59:39Z, Running 2/2 restart-0, declared
   with all five labels) is still eating every job — `detect-changes`/`pr`/`push-gh`/`push-dev`/
   `changes`/`renovate` network-cleanup death lines through 06:32Z (tasks 386–404+); newest
   containers-build PR runs `failure`/`waiting` (API ids 214–216). API id space ≠ UI run numbers
   and old-row `status` is unreliable (run-1 gotcha) — fact 2's registry emptiness is the
   authoritative "no publish ever succeeded" proof. Dev runner pod Running 12d (pre-C06 cached
   map; falls identically on its next sync — run-1 story unchanged).
4. **The public hook is byte-stable by design**: `ubuntu-22.04:docker://ghcr.io/catthehacker/
   ubuntu:act-22.04` appears verbatim in HEAD's chart default, the staged chart default and the
   staged dev slice (grep 3 sites); t2/t17 five-set + g7's 22.04 clause pin it. The live runner
   config ALREADY advertises the label, so `runs-on: ubuntu-22.04` schedules TODAY on either
   instance — the lane has no dependency on the labels landing first. The pull itself is the
   daemon's strictly-anonymous path (run-1 §4): same daemon, same dind, same public-ghcr lane
   that served act-24.04 for months.
5. **The socket fix is live**: `charts/forgejo-runner/templates/secret-runner.yaml` L116 renders
   `docker_host: unix:///var/run/docker.sock` on HEAD (`8dc73a71a`, deployed — job containers
   spawn and reach dind). `docker build`/`push` work inside any job container, on any image.
6. **General-lane feasibility grounded**: all 14 `containers/*/Dockerfile` FROM lines pull PUBLIC
   bases only (docker.io library, `ghcr.io/catthehacker|enketo|niko1221|mostlygeek|
   music-assistant`, `data.forgejo.org`, `docker.io/magiccodingman`; music-assistant's ARG
   defaults to the public `ghcr.io/music-assistant/server`). ZERO private-registry bases ⇒ no
   auth dependency reintroduced; build contexts are repo-local. The act images carry the docker
   CLI + buildx + git + curl that every lane step uses (README's act-24.04 inventory, same
   publisher family; act-22.04's exact CLI version is not live-verified — UA note, non-blocking).
7. **Fence inventory (grounded by reading every leg that can move)**:
   (a) `forgejo-ci-surface.sh` **t1** hard-compares the `.forgejo/workflows` set to the FOUR-file
   `FJ_SET` (L62) + header L7 + fail/ok prose — THE 4→5 move, in this change, TEST-owned;
   (b) ci-surface **t6** carries `WIDEN_OK={'containers-build.yaml'}` — a narrow-guard new file
   passes UNCHANGED (P3 makes that true; widen would force a second teeth move);
   (c) `forgejo-containers-build.sh` **g1** sweeps every discovered `.forgejo/workflows/*.yaml`
   RAW text: no `git.spencerslab.com`/`git.scifi.farm`/`github.com/`/`@github.com` substrings
   (comments included), no `startsWith(forgejo.server_url`, no `forgejo.server_url` in any `if:`,
   ROLE only via `vars.ROLE` membership, no string-equality — the new file must comply from day 1
   (it also re-pins via the new suite, b3/b6);
   (d) **x4**'s cutover-sibling fence is `.github`-ONLY (five gate files) — a fifth `.forgejo`
   file does not touch it (leg body read);
   (e) `tests/agent-board-coord/{rulesync-surface,gate,agents-md}` enumerate `.forgejo` paths only
   as per-ticket admit lists / twin-ban patterns — no family-count claim, no move;
   (f) `infra-forgejo.sh`, `forgejo-release.sh` (t5/t19 read release.yaml only), main-sync/
   renovate/move-config/containers suites — zero `.forgejo` enumeration;
   (g) **x3/x5** read the gated docs (`SKILL.md`, `.rulesync/rules/overview.md`, `AGENTS.md`):
   every `docker-build.yaml` line must co-name `workflow_dispatch`, the detection-marker
   vocabulary must survive, banned annotation-render phrases stay banned — my doc moves respect
   all three (CI leg re-runs prove it).
8. **Doc-count surfaces**: "all four `.forgejo` workflows" lives at `.rulesync/rules/overview.md`
   L465 with its generated twin `AGENTS.md` L467 — the sentence is FALSE the moment the file
   exists ⇒ source edit + `rulesync generate` (pinned 37.0.0 via `npx --yes`, CI-proven) + the
   regenerated mirror in the ONE change. `containers/forgejo-runner/README.md` L21 ("all four
   `.forgejo/workflows/` already assume") becomes a lie the same way — amend with the dated
   pointer (the bootstrap lane rides the PUBLIC act-22.04 deliberately). No test pins the literal
   "four"; `pipeline-push-pr` SKILL (source+mirror) states push/PR/dispatch law with no family
   count — it stays (minimal-scope ruling P7).
9. **Naming collision live**: `vars.PUSH_URL_DEV` exists (main-sync's dev-mirror GIT url,
   repo-scoped) ⇒ had the peer design shipped, the registry host needed a distinct name.
   Superseded by the NO-PEER ruling (fact 13) — the finding re-purposes as the suite's no-peer
   grep: builder-bootstrap may reference NO `PUSH_*_DEV`/peer name at all (b6).
10. **Family law, mirrored exactly** (containers-build release arm, read in full): per-side walks
    named `ghcr_*`/`forge_*`; tolerated absence = 401/403/404 on list/token, anything else fatal;
    200-without-token fatal; every walk done before the first push; union max; month fixed per job
    (`calendar.env` family); ghcr-first push order ("gap lands on the side the fleet has not
    pinned"); `concurrency: cancel-in-progress: false`; no `timeout-minutes` restatement (runner's
    30m ceiling is the law — renovate.yaml comment). Re-run law: there is NO skip-if-exists mode —
    every successful publish mints a fresh N (registry-max-walk + 1); identical-content
    re-dispatch mints N+1 too, by design ("gaps, never clobbers"). Cross-workflow double-mint
    races are structurally impossible on the lab's capacity-1 runner (every job of every workflow
    serializes through one pod).
11. **Suite baselines on this tree (post run-1 landing, this session)**: run-1's bar governs the
    staged files (dev 58, gpu 19 with `GPU_RUNNER_DIFF_BASE=a49003152` — verified resolvable,
    the run-1 sha-typo lesson honored); ci-surface red ONLY at t4 (prints two FAIL lines for its
    one deferred leg — bar-reading fact); containers-build 41 unchanged by anything here.
12. **Cold-run physics**: `forgejo-runner` is a ~10GB-class act derivative; the first dispatch
    pulls its base into the dind store (PVC persists across jobs), builds a small delta, then
    pushes ~2× the image (LAN to the infra registry + WAN to ghcr) inside the runner's 30-minute
    ceiling (v2: the third push target is gone with NO PEER — the physics got friendlier). A
    timeout red is survivable-by-law (gap, not clobber) and each retry resumes warm; the 10Gi
    `docker-data` PVC stays the prune-escape caveat (cf-55, owner-run).
13. **OWNER-ROUND GROUNDING of the NO-PEER consequence (re-verified repo-side, this round)**:
    nothing in CI ever mints the dev-registry copy — containers-build's `build-release` guard is
    prod-membership (a dev-role instance never runs the calendar arm; only `pr-*`), and per the
    ruling builder-bootstrap has no peer arm ⇒ `git.scifi.farm/curatedforest/forgejo-runner`
    (which the STAGED dev labels pin at `26.11.1`) can only ever be created by an owner hand push.
    Fact 2 proves it absent NOW. Therefore: **the dev runner is dead from its first C06-sync
    until that push lands** — and the OL4 dev probe (which runs BEFORE the OL5 hand-push / OL6
    syncs, run-1's PASS-ALL gate) is the structural guard: dev copy missing ⇒ dev probe RED ⇒
    deploy holds; the dev-side breakage can never reach a deployed-but-broken state by accident.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | builder-bootstrap workflow (ghcr+own) + new suite + t1 five-set move + law/docs in one change | M | 1 | [] | — |

ONE chunk (the same-change law: the file appearing reddens ci-surface t1 and falsifies the
"all four" rule text; a split ships a red intermediate). The launch's C02 validation chunk folds
into the Commands section (run-1 precedent); owner legs are never chunks.

## Wave order
1. C01 — TEST first (author `tests/services/forgejo-builder-bootstrap.sh` red-first while the
   workflow file does not exist + move ci-surface t1/header to the five-set), then DEV
   (`.forgejo/workflows/builder-bootstrap.yaml` + `.rulesync/rules/overview.md` + `rulesync
   generate` → `AGENTS.md` + `skills/container-creation/SKILL.md` + README pointer). Chunk review
   re-runs the bar; the final whole-plan review re-runs everything + the owner-legs package.

## Commands (the validation bar)
```bash
export PATH=$HOME/.local/bin:$PATH
BASE=a49003152   # ALWAYS resolve before use (run-1 sha-typo lesson): git cat-file -t $BASE
bash tests/services/forgejo-builder-bootstrap.sh     # NEW suite — designed-red until the file lands;
                                                     # green + battery-red after DEV (per-leg below)
bash tests/services/forgejo-ci-surface.sh            # t1 FIVE-set green; red ONLY at t4 (carried)
bash tests/services/forgejo-containers-build.sh      # 41/41 — file + detector byte-untouched (proof next)
bash tests/services/forgejo-main-sync.sh             # 8/8
bash tests/services/forgejo-renovate.sh              # 8/8 (+t9 default-off skip)
bash tests/renovate/forgejo-move-config.sh           # 8/8
bash tests/services/dev-forgejo-runner.sh            # 58 legs (run-1 state, unaffected by this commit)
GPU_RUNNER_DIFF_BASE=$BASE bash tests/services/gpu-forgejo-runner.sh   # 19 legs (run-1 state)
bash tests/containers/forgejo-runner.sh              # unaffected (README prose is unpinned — verified)
# unchanged-surface proof (must be EMPTY diffs vs BASE; run-1's staged content excluded via --cached):
git diff $BASE --exit-code -- .forgejo/workflows/containers-build.yaml scripts/forgejo-container-detect.sh
# all five workflows parse + the new file's embedded run blocks pass bash -n (41-suite extraction idiom):
python3 - <<'PY'
import glob, yaml
for p in sorted(glob.glob('.forgejo/workflows/*.yaml')): yaml.safe_load(open(p))
PY
grep -nE 'git\.spencerslab\.com|git\.scifi\.farm|github\.com/|@github\.com|docker://' \
  .forgejo/workflows/builder-bootstrap.yaml          # EMPTY (g1's raw-text bans + paradox guard)
grep -nE 'FORGE_DEV_REGISTRY|FORGE_PUSH_TOKEN_DEV|PUSH_URL_DEV|PUSH_TOKEN_DEV' \
  .forgejo/workflows/builder-bootstrap.yaml          # EMPTY (the NO-PEER ruling pinned, P4′/fact 9)
npx --yes rulesync@37.0.0 generate --check           # overview twin + AGENTS.md current (sources moved)
npx --yes aislop ci --changes                        # quality gate (score floor, zero errors; YAML/bash engine-skips fine)
# docker build => no-daemon, CI-deferred (AC11 shape; the lane's own build proof is owner OL2, live)
```
No helm render moves here (nothing under charts/ or services/ changes). NO cluster mutation, no
dispatch, no push in any agent session — the dispatch itself is owner OL2.

**Red-first doctrine**: the new suite is RED from authoring on every "file exists" clause
(b1..b8 can't pass against a nonexistent workflow — the t17 precedent), green after DEV.
ci-surface t1: flips GREEN→RED→GREEN inside the change window (TEST moves the fence BEFORE the
file exists — red between the two staging steps is the designed order, coord sequences within
one commit). The x3/x5/t6/g1 legs of existing suites: green before, green after, never moved.

## Rulings (planner; P1–P3, P5–P10 stand as ruled; P4′/P7′ are the rework-round supersessions)
- **P1 TRIGGER: dispatch-only.** Rejected the auto-push-arm filtered to containers/** "self-heal"
  (launch alt): after the paradox breaks, containers-build's matrix KEEPS every container incl.
  forgejo-runner and builds the baked image LEGITIMATELY on its own pushes — a second auto arm
  would double-publish on every bump merge and needs a per-run existence check anyway.
  Collision check: the lanes can never race a publish — bootstrap fires only on human dispatch
  and the capacity-1 runner serializes all jobs of all workflows (fact 10). CONFIRMED by the
  owner round (OQ-3).
- **P2 DISPATCH INPUT**: one `containers` string (comma/space), default `''` = the family's
  silent-empty law ("an empty list builds nothing" — containers-build's documented no-op intent,
  the 41-suite pins the shape there; mirroring keeps one law across lanes). A literal `all`
  expands IN THE WORKFLOW to every `containers/<name>` dir carrying a Dockerfile, then the
  SHIPPED detector gates the names (P6). `ref` stays the dispatch picker (no input — family).
  CONFIRMED by the owner round (OQ-2).
- **P3 ROLE GUARD: narrow, prod-only, on every job**: `if: contains(vars.ROLE, 'prod')` (bare,
  no null-widen). This lane MINTS CALENDAR TAGS ⇒ it belongs to main-sync/renovate/release's
  fail-safe class ("a bump/publish pipeline even less so" may fire unconfigured), NOT to
  containers-build's builder-class widen. Grounded consequences: an UNSET ROLE on the dev
  instance would widen a dev-role server into minting calendar tags — the exact role-law
  violation the launch pre-rejected; a DISPATCH on the dev instance (ROLE=dev) is INERT by
  guard, not by accident. ci-surface t6's WIDEN_OK stays containers-build-only — no second
  teeth move. Rejected: widen-on-unset (role-law hazard + t6 churn); no guard at all.
- **P4′ (SUPERSEDES P4 per owner ruling 2026-11-22 — NO PEER) TARGETS/ARMS**: matrix over the
  detector's JSON; per container the SAME tag set to TWO targets — `ghcr.io/ownyourio/<name>`
  (secrets.GHCR_PUSH_PAT, already present per the release arm's use) + the building instance's
  own registry (host derived from `forgejo.server_url`, secrets.FORGE_PUSH_TOKEN). Two per-side
  walks (`ghcr_*`/`forge_*`) → one union-max → calendar + `:latest` + `:main` on both; push
  order ghcr→own (fact 10). **NO peer arm, NO new variables/secrets**: `FORGE_DEV_REGISTRY`,
  `FORGE_PUSH_TOKEN_DEV` and any `PUSH_*_DEV` reference are BANNED in the file, pinned by the
  suite's no-peer leg (b6) — a future cross-host arm goes RED first and forces a fresh owner
  ruling. Rejected/evaporated with this supersession (recorded, P4 stays on file unedited):
  the infra-dispatch cross-host push (owner vetoed), dev-role minting (role law),
  per-release labels re-pointed at ghcr/infra refs (owner-rejected — one-line note only: the
  manual dev push OL3, now and every bump, is the ACCEPTED COST of this ruling).
- **P5 CALENDAR LAW, mirrored verbatim**: registry-max-walk + 1 per successful publish, all
  walks before the first push, every target gets the same N, failures leave gaps never clobbers.
  A re-dispatch with UNCHANGED content mints N+1 (that IS how containers-build behaves on re-run
  — the 41-suite pins it; no skip-if-exists mode is added). Mutable `:latest`/`:main` repoint
  unconditionally. State it once more for the record: the walk never returns a taken tag, so
  the "different content, same tag" overwrite the immutable-calendar law forbids is structurally
  impossible on this lane too.
- **P6 DETECTOR REUSE, ZERO EDITS**: `scripts/forgejo-container-detect.sh` is already the
  read-only shared mode the launch asked about — its `detect` dispatch path (MANUAL_CONTAINERS +
  EVENT_NAME=workflow_dispatch) gates names (`^[a-z0-9]+(-[a-z0-9]+)*$` + Dockerfile existence)
  and `next-n` does the month math; both are consumed as-is. Rejected: adding an `all`/`list`
  subcommand — it would move the usage-string surface the d-legs pin for nothing the workflow
  cannot do in one line (P2's expansion sits in the detect step, before the call).
  `containers-build.yaml` stays byte-untouched (41-suite text pins).
- **P7′ (EXTENDS P7 — OQ-4 set stands MINUS the peer sentence) FENCE + DOC MOVES, one change
  (teeth-move-with-docs)**: TEST — new suite + ci-surface t1 five-set/header/fail-msg; DEV —
  `.rulesync/rules/overview.md`'s "all four" enumeration to five naming builder-bootstrap in the
  NARROW class (+ one lane sentence in the container-builds paragraph: dispatch-driven recovery
  lane, public act-22.04 job image, prod-role, publishes **ghcr + the instance's own registry**),
  `rulesync generate` (DEV runs it — run-0 precedent) so `AGENTS.md` carries the twin,
  `skills/container-creation/SKILL.md` gains a short "Bootstrap lane" paragraph in its Build
  pipeline section, `containers/forgejo-runner/README.md` L21 gets the dated five-workflow
  correction. `pipeline-push-pr` SKILL + its mirror: NO change (no count claim — fact 8).
  x3/x5/t4/t5 constraints honored (fact 7g): never name `docker-build.yaml` in a moved line
  without `workflow_dispatch`, keep every marker, add no banned token.
- **P8 JOB IMAGE**: both jobs `runs-on: ubuntu-22.04` — the only label guaranteed public in the
  live config AND the end state (fact 4). The new suite's paradox-guard makes ANY other
  runs-on, or any `docker://` literal, or the baked refs in any form, RED (the battery proves
  the probe). No job-level `container:` (the act image IS the environment; a `container:` would
  change the mount model for zero need).
- **P9 VISIBILITY/PROBE INTERLOCK (run-1 policy preserved)**: the lane pushes regardless of
  package visibility (writes need only the PAT); the DEPLOY still gates on OL4's anonymous
  probes (UA-10) + ghcr public-once owner UI. The bootstrap lane does not weaken the gate; if
  UA-10 fails, the instance copies exist but the anonymous daemon cannot pull them — labels stay
  dead, the A′ auth-mount blocker rides the probe card (run-1 R3′), and the hand-push (OL5)
  does not happen.
- **P10 CHUNK SHAPE**: one chunk (above). Dev floor denies `tests/**` ⇒ the new suite + t1 move
  are TEST's; the workflow, `.rulesync` source, generated twin, SKILL and README are DEV's.

## Owner legs (re-sequenced — every one user-owned; v2 under NO PEER. run-1's L1 manual
## build+push is DELETED for ghcr/infra — the dispatch replaced it — and RETAINED, reduced to the
## dev copy alone, as OL3)
- **OL0 (infra repo Settings check, any time)**: `FORGE_PUSH_TOKEN` + `GHCR_PUSH_PAT` present on
  the infra repo (not anonymously readable — run-1 §7.2). NO new variables or secrets (P4′).
- **OL1** merge the two-commit PR on the forge (labels + bootstrap; deploy-inert — ArgoCD reads
  GitHub).
- **OL2** `workflow_dispatch` of `builder-bootstrap` on INFRA, ref main,
  `containers=forgejo-runner` (or `all`) ⇒ mints `26.11.1` (fact 2 month rule) at 3 tags ×
  {ghcr, infra registry}. Afterwards (once, if defaults differ): make the packages PUBLIC (infra
  org UI if needed + ghcr — visibility is not push-settable, run-1 fact). A timeout red is
  retry-safe (fact 12). **OL2 before OL3**: the dispatch tells the owner the literal the walks
  actually minted — under month-cross (fact 2) OL3 and the pin-amend PR must target the SAME
  literal, never a predicted one.
- **OL3 (the first DEV-SIDE leg after merge; the accepted cost of NO PEER)** owner manual
  build+push of the DEV copy ONLY: on any docker machine, from the forge tip (Dockerfile
  unchanged since `b150b4f60`), `docker build containers/forgejo-runner`, tag
  `git.scifi.farm/curatedforest/forgejo-runner:<literal OL2 minted>` (+ `:latest`/`:main` for
  convention parity), `docker login` with a DEV-instance non-admin `write:package` PAT
  (owner-minted, outside CI — this is exactly the credential shape the no-peer ruling keeps off
  the repo), push, and set the package PUBLIC on the dev org. **The dev runner is dead (will
  fall into the same pull-death once OL6 syncs its labels) until this push lands** — OL4's dev
  probe is the structural guard, so never let OL6 run with the dev probe red.
- **OL4** the two anonymous probes, run-1 L2 shape (token+manifest curl on BOTH hosts for the
  minted tag + un-logged pull belts; the infra probe verifies OL2, the dev probe verifies OL3) —
  PASS-ALL gates; ANY FAIL ⇒ STOP before OL5; the A′ auth-mount becomes a blocker riding the
  probe card (and gates the lane's whole instance-registry value — P9). A skipped OL3 surfaces
  HERE as a red dev probe — loud by design, not a silent half-heal.
- **OL5** GitHub-main hand-push (the breaker; plain non-force FF of the merged forge tip;
  carries the whole `8dc73a71a..` backlog — run-1 R4/OQ-3 unchanged). NEVER an agent.
- **OL6** ArgoCD syncs + both runner StatefulSets restart (reloader; run-0 fallback commands
  stand; quiet window — the label flip and the `26.11.1` pulls land together, once each side).
- **OL7** gpu-side verification: re-run the dead PR run (#184's build-pr — task-389 shape) ⇒
  jobs pull `git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` and `docker build` works
  inside; optionally re-run push #186 ⇒ containers-build's release arm now LEGITIMATELY mints
  26.11.2 to ghcr + infra — **dev copy does NOT follow (no peer, no dev-role arm): every future
  bump needs OL3's manual dev push again + the pin moves. This is the permanent, owner-ruled
  cost; the freshness trap rides the deferred lane card (Deferred).**
- **OL8** main-sync heals: one healed run (re-run #193's twin or the next push) fans GitHub +
  the dev mirror full-range; check `git ls-remote dev main` moved.
- **OL9** dev-side verification: a dev PR touching containers/** ⇒ the dev runner pulls its OWN
  registry copy (OL3's) and publishes `pr-<branch>-<sha>` there (run-1 L8 shape, unchanged).

## Risks / merge caveats
- **THE DEV RUNNER IS DEAD UNTIL OL3** (first, under NO PEER): the staged dev labels pin a copy
  only a human hand can create; the OL4 dev probe before OL5/OL6 is what keeps "dead" from
  becoming "deployed dead" — infra heals via merge+dispatch (OL1→OL2), dev heals only when the
  owner pushes (OL3). And on EVERY future bump the same manual leg repeats (OL7 note) — the
  lane card owns the automation question (Deferred).
- **The last single point (infra side)**: the paradox breaks only once (a) the file reaches the
  instance and (b) the daemon's dind pulls `act-22.04` anonymously — that exact ref has never
  been requested (the lane's own first real pull, several GB onto the 10Gi docker-data PVC —
  cf-55 prune escape owner-run). The shape is proven (same daemon/dind/public-ghcr path served
  act-24.04 for months), this instance of it is not.
- **30-minute ceiling vs the first cold 2-target mint** (fact 12): a timeout leaves a gap, the
  retry resumes warm; if retries keep failing, raising the chart `runner.timeout` is a deferred
  owner decision (NOT this ticket).
- **act-22.04 staleness/egress**: catthehacker's tag is rolling-upstream — digest drift is
  accepted (the lane builds FROM public bases regardless; only the base-pull egress matters); a
  ghcr outage ⇒ red runs, retry (gaps-not-clobbers law covers partial runs by design).
- **Renovate churn hazard on the paradox line**: the renovate workflow's own header notes its
  built-in manager proposes repo-wide `runs-on` bumps — an auto-PR flipping builder-bootstrap to
  `ubuntu-24.04` would re-arm the paradox. The b2 paradox-guard reddens it and the human-merge
  posture (no automerge for label bumps) is the outer fence — record in the file's comment.
- **Dispatch-on-dev is inert by design** (P3): the recovery story is infra-only; the dev
  instance can mint `pr-*` on its own once its labels work — no calendar power, per the role
  law; documented in the workflow header.
- **Month-cross now couples three surfaces**: OL2's minted literal, OL3's manual tag, and the
  label pins must agree (fact 2) — dispatch first (OL2), push second (OL3), amend both pin sites
  in one follow-up PR if the literal moved.
- **Two-commit PR**: the bootstrap commit touches ZERO files the labels commit touches
  (disjoint file sets — review check), so PR review can reason about each independently.
- Merged-but-undeployed stays non-regressive (run-1 law): nothing OL1–OL4 changes today's dead
  state; queue backlog during the window stays re-runnable post-heal.
- ci-surface stays red ONLY at t4 (carried deferral, prints two FAIL lines for one leg — fact
  11); containers-build 41/41 with byte-proof; run-1 suites' baselines unchanged.

## Deferred (follow-up card seeds)
- run-1's set STANDS verbatim: Renovate label-pin lane card (published-not-predicted guard's
  sole home), UA-10 probe card, post-heal `26.11.2` re-pin pair, ghcr absent-vs-private settle,
  run-0 carried seeds (cf-55 retests 94/97/101/106, ci-surface t4, t9-exemption retirement).
- **LANE CARD SEED WIDENED (v2)**: the label-pin lane card now also owns the **dev-copy
  automation question** — under the NO-PEER ruling the `git.scifi.farm` calendar copy is
  hand-pushed at every bump forever; any future automation (a re-ruling on peer publication,
  a per-release ghcr/infra label re-point, or another shape) starts there. Do NOT re-propose
  here: the cross-host push was owner-vetoed this round and the suite's b6 no-peer leg reddens
  any sneak-in.
- **Comment-truth note (recorded, not edited — the run-1 staged paths are commit 1's content)**:
  the staged values/slice freshness comments phrase the manual duty as pushing BOTH registries
  per bump; post-landing the INFRA copy is auto-minted by the merge fire and the hand-push duty
  shrinks to the DEV copy alone. A future touch (or the lane card) aligns the wording; lying
  upward is worse than being conservative.
- NEW seeds: (a) post-push verification leg for the lane (manifest-200 after push — today the
  push exit code is the proof; nice-to-have, not law); (b) runner-timeout raise decision if a
  first cold dispatch times out.

## Open questions
**CLOSED — the batched owner round 2026-11-22 consumed every fork**: OQ-1 **DEVIATED — NO PEER**
(cross-host push + new secret/variable REJECTED; dev copy = owner manual push, OL3, now and
every bump; folded as P4′ + Risks line 1 + OL7/lane-card seeds), OQ-2 CONFIRMED (empty default +
explicit `all`), OQ-3 CONFIRMED (dispatch-only), OQ-4 CONFIRMED (doc set minus the peer
sentence — P7′), OQ-5 **MOOT — EVAPORATED with the OQ-1 supersession** (warn-and-skip was
peer-shape behavior; there is no peer to skip — the ruling above replaces it, the option stands
recorded unedited, and the b6 leg re-purposes as the NO-PEER pin). The rework
introduced NO new gaps: every design surface (targets, walks, push order, owner-leg coupling,
suite pins) is now either human-ruled or grounded by the two sessions' reads/probes. Expected:
no second owner round; coord books final approval on this package.

## RESULT handoff
Plan file + C01 rewritten to v2 (NO-PEER targets, OL0–OL9 re-sequenced, fact 13, P4′/P7′,
b6 no-peer leg); DECISIONS appended (owner round + rework rulings + rejected alternatives,
append-only — the P-series stands unedited); FRICTION appended; STATE.json: chunk table
unchanged (C01 pending, wave 1), `plan_status` stays `draft` for coord's approval booking,
`updated_at` refreshed.
