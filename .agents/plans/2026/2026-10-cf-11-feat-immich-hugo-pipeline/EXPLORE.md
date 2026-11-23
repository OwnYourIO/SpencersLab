# EXPLORE — cf-11 C07 resume grounding (agent-explore, 2026-11-23)

Grounded read-only: ticket folder records, SpencersLab git (this worktree +
read-only refs), fresh /tmp/opencode clone of the site repo, unauthenticated
git.spencerslab.com API, readonly-gpu/infra-kubernetes MCP. No writes outside
this file; no cluster mutations; /home/coder/CuratedForest.com untouched.

## STATE-OF-C07 (one paragraph)

Live today: the SpencersLab repo side is fully landed (tip == origin/main ==
`b89acb5df`; `containers/forgejo-host-runner/` + the chart host-mode delta
merged; `ghcr.io/ownyourio/forgejo-host-runner:main` manifest 200), and the
site-repo side is LIVE ON MAIN — the owner pushed commit `380ffc7`
(2026-11-07 15:52 UTC, "Spencer's Bot (Claud)") directly to
`CuratedForest/CuratedForest.com` main, carrying the round-4 `pipeline.yml`
(single file, sync cron `0 6 * * *` UTC, both jobs `runs-on: cf-host`,
`IMMICH_URL` as repo variable `${{ vars.IMMICH_URL }}`) + empty
`sync-albums.yaml` (verified byte-level shape below), on top of the owner's
two previously-local commits (`6b69726`, `9d28781`) which are now also on
main. No site PR was ever opened (pulls API = 0, zero `refs/pull/*`) — C07's
"branch + PR" leg was effectively superseded by the owner's direct push. The
11-07 note's "stuck site run#2 (push/deploy)" is NOT stuck anymore: it was
cancelled 2026-11-08 20:40:41Z; every subsequent daily schedule run
(11-08→11-22) sits waiting→cancelled (each replaced by the next morning's
run, none ever started a job), and today's run #239 is the sole current
`waiting` run — 16 consecutive days with zero started jobs is public evidence
that no `cf-host` runner has come online. The single remaining blocker is the
cf-88 owner pair (second runner record on git.spencerslab.com + its dedicated
Bitwarden item; the round-2 "reuse the existing runner record" ruling was
ruled out by v15.0.10 server evidence per branch commit `4d3b6ea8d`): the
item UUID fills the pinned-red h6 slot, and — NEW this grounding — the branch
also needs a re-land onto current main before merge, because main's
forgejo-runner chart moved 6 commits (cf-55/cf-6, 11-21→11-23) past the
branch's 11-07 base and h7's docker-regression gate is RED on that drift
(also h8 is currently unreachable, the harness stops at h7; on a clean
re-land h1–h5/h7/h8 go green and h6 is the only red until the fill). Repo
secrets (action 8) remain unverifiable from public surface (secrets/variables
endpoints 401; jobs never started, so no leak either way).

## Q1 — Site repo current truth

Clone: `GIT_LFS_SKIP_SMUDGE=1 git clone https://git.spencerslab.com/CuratedForest/CuratedForest.com` → `/tmp/opencode/explore-cf11/CuratedForest.com`.

**Refs** — `git ls-remote origin`:
```
380ffc757826d4992d8cc8600b21ad311c1f6b40  HEAD
380ffc757826d4992d8cc8600b21ad311c1f6b40  refs/heads/main
```
Exactly one ref: `main` @ `380ffc7`. Zero `refs/pull/*`, zero feature branches.
`GET /api/v1/repos/CuratedForest/CuratedForest.com/pulls?state=all` → `pulls: 0`.

**6b69726 IS reachable** — `git merge-base --is-ancestor 6b69726 origin/main` → YES.
`git log -3`:
```
380ffc7 2026-11-07 15:52:05 +0000 feat: add pipeline workflow, sync config, and home assistant skill updates   (author: Spencer's Bot (Claud) <bot-and-reviewed@spencerslab.com>)
6b69726 2026-09-27 02:19:17 +0000 Move .opencode to a real folder so that it works correctlty
9d28781 2026-09-26 22:44:11 +0000 Update agent context files to be more consistent and support OpenCode/OpenChamber
```
`git diff 6b69726..origin/main --stat`:
```
 .forgejo/workflows/pipeline.yml                    | 179 +++++++++++++++++++++
 .../cutting-big-tech/index.md                      |  10 ++
 .../home-assistant/label-based-features/SKILL.md   | 134 +++++++++++++++
 .../button-label-mapping/index.md                 |  20 +--
 .../label-based-features/production-objects.md     |  95 +++++++++++
 hugo.yaml                                        |  10 ++
 sync-albums.yaml                                 |  15 ++
 7 files changed, 453 insertions(+), 10 deletions(-)
```
**Verdict: the workflow files landed DIRECTLY on main** — `380ffc7` is the
single commit between the 11-06 record's `6b69726` [ahead 2] and today's tip,
authored by the owner's bot, pushed 2026-11-07 15:52 UTC. The four extra files
are owner-side maintenance (content-page edits + the label-based-features agent
skill docs + a `hugo.yaml` `ignoreFiles` block for those skill docs — NOT
pipeline work). The owner's two September local commits also landed with it.
The site repo has been quiet since 11-07 (380ffc7 is HEAD).

**Workflow files on main** — `git ls-tree origin/main .forgejo/workflows/` →
only `pipeline.yml` (blob a1b6b337). `git cat-file -e
origin/main:.forgejo/workflows/{deploy,sync}.yml` → both ABSENT (superseded by
the round-3 combine). `sync-albums.yaml` on main = the schema-doc header +
`albums: []` (ships empty, `page:` required — N3 shape intact).

**Effective shape (extracted verbatim from `origin/main:.forgejo/workflows/pipeline.yml`)** — matches the ticket record's round-4 expectation on every point:
- one workflow, two event-gated jobs; `on:` = push[main] + pull_request[main, opened/synchronize/reopened] + schedule + workflow_dispatch
- sync job `if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'`, `cron: "0 6 * * *"`, `runs-on: cf-host`, `timeout-minutes: 30`, `concurrency: group: immich-sync, cancel-in-progress: false`; dispatch inputs `albums` (string) + `force` (boolean)
- deploy job `if: github.event_name == 'push' || github.event_name == 'pull_request'`, `runs-on: cf-host`, `concurrency: group: ${{ github.event_name }}-deploy, cancel-in-progress: false`; prod leg `hugo --gc --minify -b https://curatedforest.com` + `netlify deploy --prod --no-build` on push; farm leg `hugo -D --gc --minify -b https://curatedforest.farm` + `netlify deploy --prod --no-build` on PR
- env/secret names: job env `IMMICH_URL: ${{ vars.IMMICH_URL }}` (repo VARIABLE — placeholder gone from file), `NETLIFY_AUTH_TOKEN`/`NETLIFY_SITE_ID`/`NETLIFY_SITE_ID_FARM` (`${{ secrets.* }}`), `HUGO_CACHEDIR: /data/hugo-cache`; step env `IMMICH_API_KEY`, `ALBUMS_FILE`, `ALBUMS`, `FORCE`, `STATE_DIR: /data/state`, `BRANCH: immich-sync`, `FORGEJO_URL: https://git.spencerslab.com`, `FORGEJO_REPO: CuratedForest/CuratedForest.com`, `FORGEJO_PAT: ${{ secrets.FORGEJO_SYNC_PAT }}`, `GIT_IDENTITY_NAME/EMAIL: immich-sync@curatedforest.com` — the five repo secrets + one variable, exactly user action 8's set
- checkout: sync leg `fetch-depth: 1, lfs: false` + `git lfs install --local`; deploy leg `fetch-depth: 0, lfs: true`
- file header comment cites the round-3 combine + IMMICH_URL variable ruling; cadence comment pins 06:00 UTC = Denver midnight, no watchdog, dispatch as manual override

## Q2 — Forgejo Actions surface (public endpoints only)

Probes (all unauthenticated):
- `GET /api/v1/repos/CuratedForest/CuratedForest.com/actions/runs` → **http 200** (17 runs)
- `GET .../actions/runs/{id}` → http 200 (ids 239/212/2)
- `GET .../actions/tasks` → 200, `total_count: 0` (task queue empty)
- `GET .../actions/runners` → **401 "token is required"** (boundary — runner registration not visible publicly)
- `GET .../actions/secrets` / `.../actions/variables` → **401** (boundary — seed state not visible publicly)
- instance-wide `GET /api/v1/actions/runners` → 404 (not in this API surface); the `/CuratedForest/CuratedForest.com/actions/runs/17` HTML page → 307 (login redirect — UI page auth-gated)

Run history (id, status, created, stopped):
```
2   cancelled 2026-11-07T15:58:03Z  2026-11-08T20:40:41Z   (the 11-07 "stuck site run#2" — the workflow commit's own push run)
9   cancelled 2026-11-08T06:00:15Z  2026-11-09T06:00:41Z
13  cancelled 2026-11-09T06:00:41Z  2026-11-10T06:00:27Z
32  cancelled 2026-11-10T06:00:27Z  2026-11-11T06:00:50Z
… (one per 06:00 UTC, 11-11 → 11-22, each stopped exactly when the next was created)
212 cancelled 2026-11-22T06:00:26Z  2026-11-23T06:00:26Z
239 waiting   2026-11-23T06:00:26Z  — (sole current waiting run; branch/head_branch null, title "pipeline" — the schedule-run shape)
```
**Findings:**
1. **Run #2 is no longer stuck** — it was cancelled 2026-11-08 20:40:41Z (28.7 h after creation; the stop time is NOT a 06:00 schedule trigger, so it was a manual/scheduled cancellation, consistent with the 11-07 note's follow-up). It sits on `workflow_id: pipeline.yml`, event push (the workflow commit itself).
2. **No job has ever started.** All 16 pre-today runs are waiting→cancelled with `duration: null`; the only current run (#239) is `waiting` with an empty task queue. With `cancel-in-progress: false` the morning run's creation cancels the still-waiting predecessor — a 16-day waiting→cancelled cascade is the public signature of "no runner with the `cf-host` label has ever been online." If a runner had registered, each daily run would have STARTED (status running/failure with a duration, first secret use failing loud per the designed shape) instead of waiting.
3. **No `pull_request`-event run exists** — consistent with the immich-sync PR never having opened (the sync job could not run without a runner anyway).
4. Runner/secret/variable state is NOT publicly observable (401/404 boundaries recorded, not failures).

## Q3 — Cluster surface (readonly-* MCP)

**gpu cluster** (`readonly-gpu-kubernetes`):
- `resources_list apps/v1 StatefulSet` (21) → exactly one forgejo-related: `default/gpu-forgejo-runner-gpu` 1/1, age 18d, image `data.forgejo.org/forgejo/runner:13.2.0`
- `resources_list apps/v1 Deployment` (53) → no forgejo/runner deployments (only mcp toolhive proxyrunners match)
- `resources_list v1 Pod` (89) → `default/gpu-forgejo-runner-gpu-0` 2/2 Running (177m)
- STS detail: pod command `["/usr/bin/dumb-init","/bin/forgejo-runner","daemon","-c","/data/config/config.yaml"]`, initContainer `dind` `docker:29.9.2-dind` — the docker-mode (DinD) shape from main's chart; job-routing labels live in the runner config (act set by chart default), not in pod labels
- **NO `gpu-forgejo-runner-gpu-host` StatefulSet/Deployment/Pod exists — the unmerged cf-88 slice has not landed on the cluster (confirmed, not assumed)**
- ArgoCD: `argoproj.io/v1alpha1 Application` list (20 apps) → the only runner app is `gpu-forgejo-runner-gpu` = **Healthy + Synced** (synced 2026-11-23T18:19 by tms@spencerslab.com at repo revision `bc4b2a3fa` — in origin/main history, 16 commits behind tip `b89acb5df`; the gap is post-sync commits incl. the 20:46 release bump, so the app is current as of its last sync); **no `gpu-forgejo-runner-gpu-host` Application exists**

**infra cluster** (`readonly-infra-kubernetes`):
- namespaces: `default kube-node-lease kube-public kube-system system-upgrade`
- forgejo-related pods: `default/infra-forgejo-55c7666785-5zbrl` 1/1 (2d) + `default/pg-forgejo-1` 1/1 (29d) — **no act runner pod of any kind on the infra cluster**
- ArgoCD `infra-forgejo` app = **Healthy but OutOfSync** — inspected: the single drifted resource is `TCPRoute infra-forgejo-ssh` (gateway.networking.k8s.io/v1alpha2) OutOfSync; the forgejo secret + `pg-forgejo` cnpg Cluster are Synced. Instance image `code.forgejo.org/forgejo/forgejo:15.0.10-rootless`; valuesObject carries `bitwardenIds.forgejo-s3` (the cf-104 S3-backed LFS store) — the cf-104 LFS work is live on the instance
- cf-97 work: the `gpu-forgejo-runner-gpu` release above (docker mode, 18d) is the landed runner rollout

## Q4 — cf-88 branch readiness

All via read-only git in this worktree (branch refs; no worktree edits).

**Branch inventory** — `git for-each-ref refs/heads/cf-88*`:
```
cf-88-feat-gpu-host-runner 4d3b6ea8d 2026-11-07 17:57  cf-88 r2: owner rulings — (1) runner url now derived from the pipeline's domain value: chart seam urlFromDomain -> https://git.{{ .Values.domain }} … (2) runner-record reuse NOT implemented — v15.0.10 server source: one ActionRunner row per uuid, Declare overwrites agent_labels last-declares-wins … second record + item still the owner leg (h6 pinned red)
cf-88-feat-gpu-prod-forgejo-runner cd5862e81 2026-11-03 19:58  cf-88 test layer: gpu-forgejo-runner-prod.sh contract (t01-t02 probe re-check, t1-t9 wiring, deferred-red t8) + home-immich-transport.sh contingent C04 gate
```
- `git worktree list`: host branch checked out at `/home/coder/SpencersLab/.agents/worktrees/cf-88-feat-gpu-host-runner`; prod branch at `.../cf-88-feat-gpu-prod-forgejo-runner`
- `git ls-remote origin 'refs/heads/cf-88*'` → EMPTY (neither branch pushed); `git branch -r --merged origin/main | grep cf-88` → NEITHER merged
- Neither is an ancestor of the other (`merge-base --is-ancestor` both ways → NO); merge-base(host, prod) = `eb1ede821`

**`cf-88-feat-gpu-prod-forgejo-runner` = SUPERSEDED.** 28 commits not in origin/main, 567 commits BEHIND origin/main (branched from an old main; its tail = the original 11-02/03 card-#88 planning/rework/test commits + pre-main-era cf-93/mosquitto work that landed on main under different SHAs). Card #88 was CANCELLED with its work riding the cf-11 follow-up (DECISIONS 2026-11-23), so this branch is the orphan of the cancelled plan. It carries TWO files absent from origin/main — `tests/services/gpu-forgejo-runner-prod.sh` (1346 lines; the ORIGINAL docker-mode prod-runner contract) and `tests/services/home-immich-transport.sh` (527 lines) — plus 18 commits of ticket bookkeeping. Nothing unique worth merging (the surviving work is the host branch); the two test files are orphaned artifacts of the cancelled plan (candidate for owner cleanup, like the worktree).

**`cf-88-feat-gpu-host-runner` (the branch of record, `4d3b6ea8d`)** — `git diff --stat origin/main...cf-88-feat-gpu-host-runner`:
```
.../2026-10-31-feat-immich-hugo-pipeline.md        |    2 +
.../STATE.json                                     |   29 +-
charts/forgejo-runner/templates/secret-runner.yaml |    8 +
services/gpu/prod/values.yaml                      |  58 ++
tests/services/gpu-forgejo-host-runner.sh         | 1035 ++++++++++++++++++++
```
- chart seam (the 8-line delta): `{{- if .Values.runner.urlFromDomain }} url: https://git.{{ .Values.domain }} {{- else }} url: {{ index .Values "runner" "url" }} {{- end }}` in `secret-runner.yaml`
- ExternalSecret mapping (branch chart, lines 153–167): `secretKey: uuid ← property: username` and `secretKey: token ← property: password`, both `remoteRef.key: bitwardenIds.runner-token` — i.e. the owner's Bitwarden item is **username = runner uuid, password = registration token**
- `services/gpu/prod/values.yaml` slice `forgejo-runner-gpu-host:` = `urlFromDomain: true`, `backend: host`, `labels: ["cf-host:host"]`, image `ghcr.io/ownyourio/forgejo-host-runner:main` pullPolicy Always, 20Gi RWO /data VCT, docker-only null-outs (dind initContainer etc.), app block under `charts:` with the trio-exemption comment

**The EXACT pending slot** (suite leg h6, read verbatim from `tests/services/gpu-forgejo-host-runner.sh` on the branch, `KEY = 'forgejo-runner-gpu-host'`):
- file: `custom-values/gpu/prod-values.yaml`
- required shape: a NEW **top-level** `forgejo-runner-gpu-host:` block with `bitwardenIds:` → `runner-token: <36-char lowercase UUID>` = the Bitwarden ITEM uuid (suggested item name `forgejo-runner-gpu-host`; username = the runner-record uuid, password = its registration token)
- current state: block **MISSING** (h6 prints `slot state: MISSING (no top-level forgejo-runner-gpu-host block yet)`)
- h8 constrains the edit: `custom-values/gpu` diff must be **exactly** the new `bitwardenIds` entry and nothing else (no other lines added/removed)

**Suite re-run after the fill** — `bash tests/services/gpu-forgejo-host-runner.sh` (repo root; helm via `PATH=$HOME/.local/bin:$PATH`; renders on /tmp scratch). Leg order h1–h5, h7, h8, then h6 LAST (pinned red by design; the harness stops at the first failing leg).
- GOTCHA (observed, not assumed): `DIFF_BASE="${GPU_HOST_RUNNER_DIFF_BASE:-$(git rev-parse --verify origin/main || git rev-parse --verify main || true)}"` — in the owner's worktree `origin/main` is correct (b89acb5df); in a fresh clone of THIS worktree, `origin/main` resolves to the worktree's STALE local `main` (217c49ad7) and the h7 diff base is wrong. My /tmp-clone runs used `GPU_HOST_RUNNER_DIFF_BASE=b89acb5df` explicitly.
- **Live suite state TODAY (my run, /tmp clone of the branch, DIFF_BASE=b89acb5df):** h1–h5 all OK (slice shape complete: app entry + trio comment, `urlFromDomain: true` with no host literal/banned URL form, `backend: host` + verbatim `labels: ["cf-host:host"]`, 20Gi RWO /data VCT no storageClass override, `forgejo-host-runner:main` + Always), then **FAIL h7** — `the docker-mode defaults render moved vs the b89acb5df chart — the url-derivation edit must be byte-transparent for the docker path`. h8 and h6 were NOT reached (harness stops at first failure).

**h7 red adjudicated: main-side chart drift, not a branch defect.** `git log 6f64e30f..origin/main -- charts/forgejo-runner` (branch merge-base = `6f64e30f` 2026-11-07 17:05; branch commits 11-07 17:26/17:57):
```
b89acb5df 2026-11-23 20:46 chore(release): bump forgejo-runner
3303b711d 2026-11-23 18:00 fix(containers): forgejo-runner bake takes tools from digest-pinned OCI stages, not get.helm.sh [cf-6]
8ef4545fe 2026-11-23 03:17 fix(containers,chart): D33 egress hardening — retry budget on bake fetches + dind --mtu=1450 both releases [cf-6]
f236be07f 2026-11-22 17:07 cf-6-debug(run-1): per-release runner job-image labels — each instance registry serves its own runner
1a99f7629 2026-11-22 00:57 feat(cf-6): complete forge runner docker socket contract — enable job containers to docker build
1a99f7629 2026-11-21 22:00 feat(cf-55 fix round): C06 runner labels -> baked image — r1 APPROVED
```
The retained h7 diff (`/tmp/opencode/gpu-forgejo-host-runner.aVlvU9/docker-diff`, 94 lines) is exactly the main-side additions — `dind --mtu=1450` initContainer args, `docker_host: unix:///var/run/docker.sock` mount + comment, and the job-image label map re-pinned from `ghcr.io/catthehacker/ubuntu:act-*` to `git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` (baked-image per-release labels) — with matching comment blocks. The connection `url:` line is byte-identical in both renders (`http://dev-forgejo-http.default.svc:3000` chart default) — the branch's own `urlFromDomain` seam is byte-transparent on the docker path as designed. Consequence: **the branch must be re-landed onto current main (same procedure as the 2026-11-06 cf-11 re-land, FRICTION entry 21) before h7 can go green; on a clean re-land h1–h5/h7/h8 are green and h6 is the sole red until the owner's UUID fill.**

## Q5 — Other material changes to the C07 resume picture

1. **C07's deliverable was satisfied by the owner's direct push, not a PR.** `380ffc7` (11-07 15:52, the owner's bot) is the single commit between the 11-06 record and today's site main, and it carries the exact round-4 shape (Q1). The site repo's 2026-11-07 push predates the cf-88 r2 ruling commit (11-07 17:57) by ~2 h — same owner session. Practical effect: C07's "branch + PR" tasks are void (no PR to open; the artifacts are already on main and reviewed-by-construction via the owner's own push); the cutover checklist that the PR body was meant to carry now lives in the commit + this ticket record. `sync-albums.yaml` on main ships EMPTY as designed.
2. **No runner has ever come online (public inference).** 16 daily waiting→cancelled runs (Q2) + empty task queue + no `gpu-forgejo-runner-gpu-host` workload/ArgoCD app on gpu (Q3) ⇒ the cf-88 owner pair is still the gate; the branch's h6 red + h7 drift (Q4) are the full repo-side state.
3. **Secret/variable seeding (user action 8) is unverifiable from the public surface** — `.../actions/secrets`, `.../actions/variables`, `.../actions/runners` all 401, and the jobs never started (waiting, not failing), so run history leaks nothing either way. Whether the owner has already seeded the five secrets + IMMICH_URL must come from the owner (NEEDS).
4. **The image the host slice will consume is published** — `ghcr.io/v2/ownyourio/forgejo-host-runner/manifests/main` → 200 (anonymous pull token flow); `:latest` → 404 (the chart references `:main` + pullPolicy Always, so this is consistent, not a gap).
5. **The existing docker-mode gpu runner is healthy** (Q3) and its act-label set is disjoint from `cf-host` by the chart's docker default — nothing on the cluster can run the site's jobs today, so no partial/ambiguous state exists.
6. The infra-forgejo ArgoCD OutOfSync is only the `infra-forgejo-ssh` TCPRoute (Q3) — cosmetic to this ticket, but a live drift worth a human look.

## NEEDS (facts only the owner can supply)

1. The SECOND runner record on git.spencerslab.com (org-scoped per the ruling) — its **uuid + registration token**. (The round-2 "reuse the existing runner record" ruling is ruled out by the v15.0.10 server evidence in `4d3b6ea8d`: one ActionRunner row per uuid; Declare overwrites `agent_labels` last-declares-wins; two daemons on one record would flap routing between the act set and `cf-host` and share one task cursor.)
2. The dedicated Bitwarden item for that record (suggested name `forgejo-runner-gpu-host`; username = the record uuid, password = the registration token) — its **item UUID**, which fills `custom-values/gpu/prod-values.yaml` top-level `forgejo-runner-gpu-host.bitwardenIds.runner-token` (the h6 slot; h8 constrains the edit to exactly that entry).
3. Confirmation of the one-shot manual seed (user action 8): the five repo secrets (IMMICH_API_KEY, NETLIFY_AUTH_TOKEN, NETLIFY_SITE_ID, NETLIFY_SITE_ID_FARM, FORGEJO_SYNC_PAT) + the `IMMICH_URL` repo variable (gpu value `https://immich.spencerslab.com` per the cf-88 probe) — not observable from any public surface (Q2 boundaries).
4. (Record question, low stakes) acknowledgment that the 11-07 direct owner push (`380ffc7`) to site main is the accepted final shape, closing C07's PR leg — the live bytes match the round-4 record exactly (Q1), so this is confirmation, not verification.

RESULT
status: DONE
chunk: explore-c07-resume
files_changed: [.agents/plans/2026/2026-10-cf-11-feat-immich-hugo-pipeline/EXPLORE.md]
commands_run: [git for-each-ref/log/diff/merge-base/show (cf-88 branches, origin/main) => pass; git clone (site repo, LFS smudge off, /tmp/opencode) => pass; git log/diff/ls-tree/cat-file on the clone (6b69726..380ffc7) => pass; curl unauth Forgejo API: actions/runs + runs/{id} + tasks => pass (200); actions/runners + secrets + variables => 401 (boundary); /actions (instance) => 404 (boundary); actions HTML page => 307 (login gate); ghcr manifest probes (main 200, latest 404) => pass; readonly-gpu-kubernetes resources_list StatefulSet/Deployment/Pod + Application, resources_get STS + Application => pass; readonly-infra-kubernetes namespaces_list, resources_list Pod, resources_get Application => pass; bash tests/services/gpu-forgejo-host-runner.sh (fresh /tmp clone of cf-88-feat-gpu-host-runner, GPU_HOST_RUNNER_DIFF_BASE=b89acb5df) => h1-h5 ok, h7 FAIL (main-side chart drift — cf-55/cf-6 6 commits past the branch's 11-07 base; diff adjudicated, branch seam byte-transparent), h8/h6 not reached]
deviations: none
friction: fresh-clone artifact: the suite's `origin/main` diff base resolves to the SOURCE worktree's stale local main (217c49ad7) in a clone — first run failed h7 on the wrong base; re-ran with GPU_HOST_RUNNER_DIFF_BASE=b89acb5df, which is the true origin/main tip (b89acb5df is 16 commits past the last ArgoCD sync revision bc4b2a3fa only by post-sync commits)
open_questions: (1) the cf-88 branch needs a re-land onto current main before h7 goes green (h8 then reachable, h6 sole red) — owner UUID fill + merge sequence: re-land → h1-h5/h7/h8 green + h6 green → merge → ArgoCD sync → runner registers cf-host:host → today's waiting run #239 (or the next morning's) auto-pick-up; (2) NEEDS 1-3 are the owner's; (3) NEEDS 4 is a record confirmation; needs research: none
next_suggested: present the 2-leg owner batch (NEEDS 1-2, with the exact h6 slot shape) + the re-land plan for the cf-88 branch (agent-dev-local on the cf-88 worktree, same procedure as the 2026-11-06 cf-11 re-land), then merge + observe the first started run go loud on any unseeded secret
