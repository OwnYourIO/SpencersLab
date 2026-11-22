# PLAN: forge runner job image — per-release instance-registry labels (infra default + dev slice)
feature: 2026/2026-11-cf-6-debug-forge-runner-docker-1
status: draft — family B USER-RULED 2026-11-22 (round 1); batched round 2 RESOLVED same day
(DECISIONS L21): OQ-1 DEVIATED to **per-release labels** (supersedes plan R1), OQ-5 DEVIATED to
a follow-up lane card, OQ-2/3/4 CONFIRMED. Rework applied 2026-11-22 (this file + C01);
plan_status stays draft — coord books final approval. Model routing: every tier
`openrouter/qwen/qwen3.8-flash` (standing directive 2026-11-21).

## Goal
Make every runner pull its baked job image from its OWN instance registry: the chart default's
four act-24.04-family labels re-point from `ghcr.io/ownyourio/forgejo-runner:26.11.1` (exists
nowhere — EXPLORE §2/§3) to `git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` (the
gpu/infra release inherits it), and the dev release gains a full five-entry `runner.labels`
override in the `forgejo-runner-dev:` ApplicationSet values slice naming
`git.scifi.farm/curatedforest/forgejo-runner:26.11.1`. Same-change teeth: t2/g2 re-pins, the
new t17 slice-render leg, the t14 record flip, and the g7 re-arm (chart label classes + the
sanctioned dev-hunk class). Owner legs (two bootstrap pushes → two probes → merge → GitHub
hand-push → sync/verify) break both circularities and revive the instance-wide outage.

## Out of scope
- Re-litigating A/A′/D or the single-vs-per-release fork — **both human-ruled** (rounds 1 and
  2; DECISIONS L10/L21). The v1 single-reference ruling and the cross-instance-pull shape are
  dead options, recorded unedited per append-only.
- Label law: NO CHANGE (Q2 ruling). No AGENTS.md / `.rulesync/` / `containers/` / skills edits
  — grounded (Verified facts 3): the law text is registry-neutral and the containers docs name
  the unchanged dual-publish lane.
- The `/data/.docker/config.json` dind auth-mount (A′) — NOT in this landing; a BLOCKER riding
  the UA-10 probe card only if any probe FAILs (R3).
- The Renovate label-pin LANE — deferred to a follow-up card by round-2 ruling (Deferred seed);
  the manual-bump law stands until that card lands.
- ghcr absent-vs-private settle — owner-only, MOOT under B (Deferred record).
- `custom-values/**`, `.forgejo/**`, `.github/**`, `services/gpu/**` content: untouched — the
  override must NOT land in custom-values (g7 gate + trio exemption, round-2 directive). No
  hand chart-version bump (release.yaml does it post-heal). No board moves (card 6 stays Review).

## USER-RULED end state (recorded, not re-litigated)
1. **Family B** (round 1) + **PER-RELEASE LABELS** (round 2, supersedes plan R1): the dev runner
   pulls from its own instance registry `git.scifi.farm/curatedforest/forgejo-runner:<cal>`,
   NOT cross-instance from the infra host. Owner bootstrap = TWO pushes; UA-10 settle = TWO
   probes; plumbing = per-release values override at the ApplicationSet-values surface
   (`services/dev/prod/values.yaml`'s top-level `forgejo-runner-dev:` slice), chart default
   stays the infra reference for the gpu release.
2. **Label law: NO CHANGE** (round 1 Q2) — no probe-leg law, no doc-law edit.
3. **UA-10** (round 1 Q3, round 2 OQ-2 CONFIRMED): the settle is one anonymous manifest curl
   per registry immediately after the pushes (R3): PASS-ALL ⇒ proceed; ANY FAIL ⇒ DO NOT
   hand-push GitHub main (landing stays merged-but-undeployed; no regression vs today) and the
   auth-mount amendment becomes a BLOCKER riding the probe card, re-escalated to the owner.
4. **Breaker** (OQ-3 CONFIRMED): owner hand-pushes GitHub main (non-force FF of the merged
   forge tip — carries the whole `8dc73a71a..` backlog itself; OQ-4 carried).

## Verified facts (plan session 2026-11-22 read-only; 1–10 from the v1 session stand;
11–14 are the rework round's groundings)
1. Baseline: `origin/main` (prod forge) tip `a49003152`; GitHub + dev mirrors frozen at
   `8dc73a71a`; remotes `upstream`=GitHub, `dev`=git.scifi.farm mirror (scout's §1/§6 + this
   session's `git remote -v`).
2. Suite baseline at the tip (temp worktree, removed): dev 57/18/41/8/8/8 all rc=0, ci-surface
   red ONLY at t4. Re-measured this session — numbers stand for v2 as the pre-change state.
3. String surface: `ownyourio/forgejo-runner` lives in exactly six live files (chart values ×3
   sites, chart template record, dev suite, gpu suite, containers Dockerfile L1 + README L50);
   ZERO hits in AGENTS.md/.rulesync — the job-image law (AGENTS.md L457–461) is registry-neutral
   ⇒ rulesync move N/A. Containers docs describe the DUAL-PUBLISH lane — unchanged by B ⇒ stay.
4. Today no release overrides labels: the dev slice (services/dev L178–180) carries only
   `runner.url: http://dev-forgejo-http:3000`, the gpu slice (services/gpu L271–273) only
   `url: https://git.spencerslab.com`; `grep labels services/ custom-values/` → nothing.
5. g7 reds the re-point on BOTH clauses (L712–716: removed side only act-24.04, added side only
   the ghcr `ownyourio/` calendar regex) ⇒ re-arm mandatory, chart leg (body read L656–782).
6. Renovate reads no label line (mgr0 requires the literal `image:` prefix; no packageRule
   matches) — lane question now HUMAN-ANSWERED: defer, design card (Deferred).
7. Calendar walk: both registries provably EMPTY of calendar tags (EXPLORE §3) ⇒ empty-max ⇒
   first tag = `<yy.mm>.1` of the publish month = **26.11.1 today**; month-cross ⇒ owner pushes
   `date +%y.%m.1` and BOTH pin sites amend to the same literal (UA-8 precedent, per-registry).
8. main-sync body: `fetch-depth: 0` + plain `git push HEAD:refs/heads/main` ⇒ one healed run
   (or the hand-push) fans the whole frozen range; dev mirror heals identically (facts 8 v1).
9. Deployment chain (run-0, stands): both StatefulSets ns `default` (`gpu-forgejo-runner-gpu` /
   `dev-forgejo-runner-dev`), reloader-annotated, Secret-via-subPath ⇒ restart mandatory;
   fallback `kubectl -n default rollout restart statefulset/<release>`; ArgoCD renders both
   from GitHub main — hence the hand-push breaker.
10. The job pull is the in-pod dind daemon, strictly anonymous (v13.2.0 auth order, EXPLORE §4)
    — under per-release B each daemon hits its OWN instance registry's anonymous read path
    (UA-10, both hosts).
11. **REWORK GROUND — the values path the releases actually thread**: the ApplicationSet
    (`charts/base/templates/appset-charts.yaml`) merges ONLY the CONTENTS of the top-level
    `<appName>:` key into each release's values (the comment blocks at services/dev L175–177
    and services/gpu L265–269 state it; the live `runner.url` rides exactly this path). So the
    dev override = `runner.labels` added inside the existing `forgejo-runner-dev:` slice — the
    same mechanism, one key deeper. **Verified by render this session** (temp worktree at
    `a49003152`, chart copy + `helm dependency update`, `/tmp/opencode/cf61-sim`, worktrees
    removed after): a five-entry slice overlay rendered via `helm template dev-forgejo-runner-dev
    $CHART -f <slice-contents>` produced config.yaml labels == the four
    `git.scifi.farm/curatedforest/forgejo-runner:26.11.1` refs + plain act-22.04, url ==
    `http://dev-forgejo-http:3000`, and the run-0 `container:` block
    `{privileged: false, docker_host: unix:///var/run/docker.sock}` intact.
    **LIST-REPLACEMENT TRAP (proved)**: Helm replaces lists wholesale — a FOUR-entry overlay
    silently DROPPED the `ubuntu-22.04` label (render count = 4). ⇒ the dev override must
    re-declare ALL FIVE entries, the act-22.04 line byte-identical to the chart default's;
    t17 pins the exact five-set so this can never ship silently.
12. **REWORK GROUND — harness shapes, exact (the launch asked)**: `dev-forgejo-runner.sh` t2
    renders BOTH releases STANDALONE — `helm template <release> <chart-copy> --set
    bitwardenIds...` only (L226–234) — so its `ACT_LABELS` equality (L475–476) asserts the
    CHART DEFAULT, never a services slice. `gpu-forgejo-runner.sh` g2 overlays only the
    **custom-values** slice (`extract_slice "$GPU_CV" …` L195 — the bitwardenIds block; the
    url is simulated by `--set runner.url=$GPU_URL`) and asserts the same chart-default set
    (L272–273). NEITHER suite consumes a services runner-labels path today. ⇒ v2 pin shapes:
    t2/g2 stay chart-default legs re-pinned to the INFRA strings; the per-release truth gets a
    NEW dev-suite leg (**t17**) that extracts the top-level `forgejo-runner-dev:` CONTENTS from
    `services/dev/prod/values.yaml` (the extract_slice pattern, L155–173 precedent), renders
    `-f` that overlay, and asserts the DEV five-set + slice url + container block + zero
    `OVERRIDE_*`; plus a static five-entry/22.04-byte-equality check (fact 11 trap) and a
    **gpu-slice inheritance guard** in g3 (asserts the `forgejo-runner-gpu:` slice has NO
    `runner.labels` key — the gpu release rides the default; kills a third fork site).
    g2's header comment ("both releases deploy one chart default — the slices override only
    url/identity") becomes FALSE post-landing ⇒ TEST re-words it in the same change (teeth-
    docs parity; a lying comment is a run-0-class finding).
13. **REWORK GROUND — the host-backend render moves** (contrary to v1's AC4 wording, caught by
    this session's sim renders): BOTH template branches render `.Values.runner.labels`
    (secret-runner.yaml L151/L154), so re-pointing the chart default changes the host-mode
    render's four label lines TOO (verified: the simulated host render's diff vs today ==
    exactly those 4 docker:// lines; structural keys stay [cache, host, runner, server], no
    container key). The record block lives INSIDE the docker `if` (L125–155) — its rewrite
    never reaches the host render (verified). ⇒ AC4: host render diff = the four label lines
    ONLY, everything else byte-stable; t16's key-set assertion unaffected (stays green).
14. **REWORK GROUND — g7 dev-leg filter scope**: `dev_lines` (L681–684) inspects only diff
    lines containing `forgejo-runner` — the dev hunk's `labels:` key line and the re-declared
    act-22.04 line (no `forgejo-runner` substring) are INVISIBLE to it (pre-existing fence
    shape). The sanction class therefore bounds the visible lines (each added
    `…forgejo-runner…` line must be a `git.scifi.farm/curatedforest/` calendar ref) and t17's
    static five-entry check closes the invisible-scaffold gap; hunk-size cap + dated requirement
    stay. custom-values/dev: zero moved lines (clause byte-preserved).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Per-release labels: infra-default re-point + dev-slice override + law/record comments + t2/t14/g2/t17/g3 + g7 re-arm (one change) | M | 1 | [] | — |

Still ONE chunk (M→borderline-L, cohesive): the same-change law fuses labels, slice, comments
and teeth; splitting ships a red intermediate; no C-final chunk (the bar is the final whole-plan
Commands re-run); owner legs are not agent chunks.

## Wave order
1. C01 — TEST first (re-pins + t17 authoring + g3 guard + g7 re-arm, red-first), then DEV
   (charts/** + services/dev slice hunk), chunk review re-runs the bar; final whole-plan
   review re-runs the full Commands + the owner-legs package.

## Commands (the validation bar — v2; all forms verified working this session on `a49003152`)
```bash
export PATH=$HOME/.local/bin:$PATH
bash tests/services/dev-forgejo-runner.sh        # 58 legs post-landing: t2 re-pinned (infra
                                                 # default), t14 flipped, NEW t17 (slice-render)
bash tests/services/gpu-forgejo-runner.sh        # 18: g2 re-pinned, g3 gains the no-labels
                                                 # inheritance guard, g7 re-armed both legs
bash tests/services/forgejo-containers-build.sh  # 41 — unaffected (label NAMES unchanged)
bash tests/services/forgejo-main-sync.sh         # 8 — unaffected
bash tests/services/forgejo-renovate.sh          # 8 (+t9 default-off skip) — unaffected
bash tests/renovate/forgejo-move-config.sh       # 8 — unaffected
bash tests/services/forgejo-ci-surface.sh        # t3 green; red ONLY at t4 (carried deferral)
# Direct render bar (plumbing choices verified via exactly these shapes this session):
W=/tmp/opencode/cf61-verify; rm -rf $W; mkdir -p $W
cp -R charts/forgejo-runner $W/chart && (cd $W/chart && helm dependency update .)   # COPY build
helm lint $W/chart
U=d3dafd1a-3d88-454e-88d4-b4ec010ae2c2
# (a) chart default (the LIVE gpu shape): four git.spencerslab.com refs + plain act-22.04,
#     container block {privileged: false, docker_host: unix:///var/run/docker.sock}, url default
helm template gpu-forgejo-runner-gpu $W/chart --set "bitwardenIds.runner-token=$U"
# (b) dev-slice overlay (the LIVE dev shape): extract the top-level forgejo-runner-dev: CONTENTS
#     from services/dev/prod/values.yaml -> $W/dev-slice.yaml -> render -f; labels must equal the
#     DEV five-set (git.scifi.farm refs + byte-identical act-22.04; count EXACTLY 5 — fact 11 trap)
python3 -c "import yaml; d=yaml.safe_load(open('services/dev/prod/values.yaml')); \
  yaml.safe_dump(d['forgejo-runner-dev'], open('$W/dev-slice.yaml','w'))"
helm template dev-forgejo-runner-dev $W/chart -f $W/dev-slice.yaml \
  --set "bitwardenIds.runner-token=$U"
# (c) host backend: keys [cache, host, runner, server], NO container key; diff vs the
#     pre-landing host render = the FOUR docker:// label lines ONLY (fact 13)
helm template host-probe $W/chart --set "bitwardenIds.runner-token=$U" \
  --set runner.backend=host \
  --set 'app-template.controllers.runner.initContainers.dind=null' \
  --set 'app-template.controllers.runner.containers.runner.env.DOCKER_HOST=null' \
  --set 'app-template.persistence.socket=null'
# rulesync generate --check: N/A — no .rulesync source moves (facts 3; re-verify via git status).
# aislop: npx aislop scan --changes on the staged landing — expect 100, YAML/bash engine-skips.
# grep bars post-landing:
#   git grep -l 'ownyourio/forgejo-runner' -- charts services  => EMPTY (services/dev's new
#     lines name git.scifi.farm; act-22.04's ghcr.io/catthehacker line is a different string)
#   grep -c 'docker://git.spencerslab.com/curatedforest/forgejo-runner:26.11.1' \
#     charts/forgejo-runner/values.yaml  => 4 (label lines; comment sites may add more hits)
#   grep -c 'docker://git.scifi.farm/curatedforest/forgejo-runner:26.11.1' \
#     services/dev/prod/values.yaml      => 4 (slice label lines)
#   the labels key appears ONLY under the top-level forgejo-runner-dev: slice in services/dev,
#   NEVER under forgejo-runner-gpu in services/gpu (g3's inheritance guard mirrors this)
```
**Red-first doctrine, v2 per leg** (test-before-dev order):
- t2 labels-equality + g2: pin TODAY's chart default (ghcr strings) → green on main, **RED after
  TEST re-pins to the infra set**, green after DEV moves values.yaml L121–125.
- t14 naming clause (ownyourio → `curatedforest/forgejo-runner`): green → **RED after TEST's
  flip**, green after DEV's record rewrite.
- **t17 (new, standalone red-first per the t14/t15 precedent)**: RED from authoring (the slice
  has no labels today → the overlay render shows the chart default ≠ DEV five-set) → green after
  DEV's services/dev hunk. It is the only leg that cannot be green pre-DEV — exactly the point.
- g3 gpu-slice inheritance guard (absence check): green now, green after (nothing adds labels to
  the gpu slice) — non-vacuity: probe it by temporarily adding a labels key → RED.
- g7: green pre-DEV (empty charts + services/dev diffs) → green post-DEV **only via the
  two-class re-arm** → RED under every battery probe (chart shapes AND dev-hunk shapes, below).
- Every other leg: green before, green after. `GPU_RUNNER_DIFF_BASE` resolves to the pre-landing
  tip (coord check at staging: local main == origin/main).

## Rulings (planner; round-1 items confirmed or superseded as marked)
- **R1′ (SUPERSEDES R1 per round-2 ruling) — per-release plumbing = literal label lists, chart
  default (infra) + full five-entry override in the `forgejo-runner-dev:` slice.** Evaluated
  against the labels-param/template-composition alternative and REJECTED: composing
  `docker://<param>:<tag>` in `secret-runner.yaml` means non-comment template content lines
  (g7 chart leg reds a whole extra class), changes BOTH branches' rendering shape against the
  C03 host-render doctrine, and t15/t16 parse expectations churn; a values-level anchor cannot
  concatenate strings (`name:docker://*anchor` is invalid YAML). The slice list is the minimal
  edit class g7 can sanction cleanly: template byte-stable (comments only), one content hunk in
  its canonical override surface. Consequences folded: two bootstrap pushes / two probes (legs
  L1–L2), bootstrap-only dev-registry freshness trap (Risks + lane card), dev hunk in g7's
  dev-leg sanction class (R2′).
- **R2′ (EXTENDS R2) — g7 re-arm, TWO sanctioned classes, same change, TEST-owned:**
  (i) CHART leg: removal side additionally accepts
  `ghcr.io/ownyourio/forgejo-runner:[0-9]{2}\.[0-9]{2}\.[0-9]+` (act-24.04 out-shape clause
  kept); added side accepts ONLY
  `git.spencerslab.com/curatedforest/forgejo-runner:[0-9]{2}\.[0-9]{2}\.[0-9]+`. Cap-8 (this
  landing is exactly 4+4), ubuntu-22.04 byte-stability, the cf-6 socket sanction incl. the
  review-r1 compound guard, nonlab clause, umbrella gate: byte-preserved.
  (ii) DEV leg: on top of the cf-6 dated-comment tolerance, a DATED labels-override hunk under
  the top-level `forgejo-runner-dev:` slice is sanctioned file-scoped: every added
  `…forgejo-runner…` line must be a `git.scifi.farm/curatedforest/` calendar ref, hunk capped
  at the exact five-entry list + scaffolding + its dated comment. NEGATIVE probes (each RED):
  a `git.spencerslab.com` or ghcr-ownyourio ref inside the dev hunk (cross-instance/default-
  copy shapes are the rejected design); rolling refs; the hunk undated; `url:` line moved;
  labels added under the `charts:` block or anywhere outside the top-level slice; ANY other
  services/dev content line; any custom-values/dev line. (iii) future-bump GREEN-sim: chart
  default AND dev slice both moved `26.11.1→26.11.2` (8 lines, both hunks dated) walks green —
  no third re-arm needed for the next bump.
- **R3′ (EXTENDS R3, policy unchanged) — two probes, land only on PASS-ALL.** L2 runs
  token+manifest curls on BOTH hosts (+ un-logged `docker pull` belts); any FAIL ⇒ hold the
  deploy, auth-mount blocker rides the UA-10 probe card, re-escalated.
- **R4 (CONFIRMED by round 2, OQ-3/OQ-4):** hand-push breaker = one non-force FF push of the
  merged forge tip to GitHub main (carries the backlog); no separate catch-up push; merge on
  forge is deploy-inert so C01 may complete independently of the probe gate.
- **R5 (v1, stands, reworded for per-release)** — record-block rewrite: names BOTH refs
  (default infra + dev slice override), keeps every t14-pinned clause (git-lfs↔labels,
  helm+cr-baked, act-22.04 installer caveat, no sha256), documents that the dev override re-
  declares all five entries because Helm replaces lists (fact 11).
- **R6 (round 2, OQ-5 answer adopted)** — NO Renovate lane in this landing; the manual law
  stands; the lane card (Deferred) designs per-registry reads + published-not-predicted.

## Post-landing owner legs (ordered — every one user-owned; v2)
- **L1 TWO bootstrap build+pushes** (owner, any docker machine): clone/fetch the prod forge
  repo, checkout the tip (Dockerfile unchanged since `b150b4f60`);
  `docker build -t git.spencerslab.com/curatedforest/forgejo-runner:26.11.1 containers/forgejo-runner`;
  `docker tag …:26.11.1 git.scifi.farm/curatedforest/forgejo-runner:26.11.1`;
  `docker login git.spencerslab.com` then `docker push` BOTH refs, `docker login git.scifi.farm`
  (each with a non-admin `write:package` PAT on that instance) and push the dev ref too;
  then set the package PUBLIC on BOTH instances (org CuratedForest → Packages → forgejo-runner;
  visibility is not push-settable). Optional `:latest`/`:main` on both for convention parity.
  Month-cross now applies PER-REGISTRY — both pushes and BOTH pin sites move to the same
  `date +%y.%m.1` literal (UA-8 precedent, one amend PR).
- **L2 TWO UA-10 settle probes** (owner, immediately after L1; the gate, R3′) — per host H ∈
  {git.spencerslab.com, git.scifi.farm}:
  `TOK=$(curl -s "https://$H/v2/token?scope=repository:curatedforest/forgejo-runner:pull" | jq -r .token)`;
  `curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOK"
  "https://$H/v2/curatedforest/forgejo-runner/manifests/26.11.1"` ⇒ 200; belt: un-logged-in
  `docker pull $H/curatedforest/forgejo-runner:26.11.1` ⇒ success. **PASS-ALL ⇒ proceed. ANY
  FAIL ⇒ STOP (no L4/L5), the auth-mount (A′) rides the probe card as blocker, re-escalate.**
- **L3 merge the label PR on the forge** (owner; harmless pre-L2-result, deploys nothing).
- **L4 GitHub-main hand-push** (owner; ONLY after L2 PASS-ALL — the breaker):
  `git fetch origin && git push upstream origin/main:refs/heads/main` — plain non-force
  fast-forward (GitHub main `8dc73a71a` is an ancestor), so the merged backlog rides it in the
  same push. NEVER an agent (AGENTS.md git law; user-owned by name).
- **L5 ArgoCD syncs + restarts** (owner): both Applications follow GitHub main; reloader rolls
  the pods; fallback (run-0, commands stand): `kubectl -n default rollout restart
  statefulset/gpu-forgejo-runner-gpu` (gpu) and `kubectl -n default rollout restart
  statefulset/dev-forgejo-runner-dev` (dev). The dev release renders the slice override ⇒ its
  new config names the git.scifi.farm refs.
- **L6 gpu-side verification** (owner): re-run a dead PR run (e.g. #184's build-pr — task-389
  shape) ⇒ the job container starts on `git.spencerslab.com/curatedforest/...` and `docker
  build` works inside it (run-0 contract). Optionally re-run push run #186 ⇒ the release arm
  genuinely builds and mints `26.11.2` DUAL (ghcr + INFRA registry only — see freshness trap);
  labels then sit one bump behind the manual law until the next re-pin PR — by design.
- **L7 backlog fan check** (owner): one healed main-sync run (re-run #193 or the next push)
  fans GitHub + dev mirror full-range (fact 8); confirm the mirror moved: `git ls-remote dev
  main` past `8dc73a71a`.
- **L8 dev verification — STRONGER under per-release refs** (owner): after L5 the dev runner
  pulls `git.scifi.farm/curatedforest/forgejo-runner:26.11.1` — its own instance, the same host
  its daemon already dials for registration ⇒ **no cross-instance egress dependency at all**
  (v1's residual-risk class is structurally gone). Re-run/open a dev PR job touching
  `containers/**` ⇒ pull succeeds, `pr-<branch>-<sha>` publishes to the DEV registry.

## Risks / merge caveats (for the PR)
- **UA-10** (15.0.10 anonymous public-org container reads) is B's one unproven behavior — now
  gated twice, per registry (L2), with a named failure path (R3′). No silent dead-end deploy
  exists: hand-push precedes nothing else.
- **DEV-REGISTRY FRESHNESS TRAP (new, per round-2 ruling)**: the dev instance's containers-build
  release arm NEVER runs (ROLE dev ⇒ prod guards false; only `pr-<branch>-<sha>` tags publish
  there) ⇒ the git.scifi.farm `26.11.1` copy is BOOTSTRAP-ONLY. Every future bump requires the
  owner to push the new calendar tag to BOTH registries by hand AND move BOTH pin sites — else
  the dev runner rides a stale-but-working image (immutable tag; jobs keep running on 26.11.1
  content forever, silently behind the infra half). Rides the lane-design card (Deferred);
  values/slice comments must say so (C01 ACs).
- **LIST-REPLACEMENT TRAP**: a partial override silently drops labels (proved: 4-entry overlay
  lost ubuntu-22.04 — fact 11). Guarded by t17's exact five-set + byte-equality of the 22.04
  re-declaration; never shorten the dev list without moving t17.
- Deploy ordering IS the fix: nothing between L1 and L5 changes today's dead state (no
  regression); merges landing in the window queue as doomed runs, all re-runnable post-heal.
- Both runner pods restart once (capacity-1 blip, 30m/5m + 300s grace shape — run-0 caveat);
  schedule L5 in a quiet window.
- First multi-GB pulls land on the 10 Gi `docker-data` PVCs (both clusters; cf-55 prune escape
  stays owner-run).
- Credentials: L1 needs a `write:package` PAT on EACH instance (owner-minted); `GHCR_PUSH_PAT`
  presence only matters for L6's optional #186 re-run (per-registry push legs).
- Host-mode releases (card #88 territory) will inherit the new defaults — the host-slice
  override law (values header) is untouched; no live host release exists today.

## Deferred (follow-up card seeds)
- **RENOVATE LABEL-PIN LANE CARD (round-2 ruling, OQ-5)**: design a customManager reading the
  PER-RELEASE refs against THEIR OWN registries (chart default → `git.spencerslab.com`, dev
  slice → `git.scifi.farm`; datasource/registry mapping for the Forgejo container registries),
  and ENFORCE published-not-predicted (the cf-55 D42 trap this ticket exists for — the owner
  VETOED a test-leg guard in round 1, so the guarantee rides THIS card alone). Until it lands,
  every bump stays manual-by-law across both pin sites AND both registries (freshness trap).
- **UA-10 probe card** (round-1 Q3 home): carries L2 evidence either way; on FAIL the auth-mount
  (A′: mount `/data/.docker/config.json` via the chart — new g7 class + secret-render teeth)
  lands there first.
- Post-heal label re-pin `26.11.1 → 26.11.2` (both sites, both registries) — next manual-bump PR.
- ghcr absent-vs-private settle (`gh api /orgs/ownyourio/packages/container/forgejo-runner`) —
  owner-only, MOOT under B; record.
- run-0's carried seeds unchanged (cf-55 release retest 94/97/101/106; ci-surface t4;
  t9-exemption retirement — close-out-sweep card).

## Open questions
**CLOSED — the batched round resolved all five** (DECISIONS L21): OQ-1 per-release labels
(superseding plan R1 — reworked here), OQ-5 lane deferred to a card (folded to Deferred),
OQ-2/3/4 confirmed as ruled. The rework introduced NO new gaps: every design surface (plumbing
choice, g7 classes, pin shapes, leg order) is now either human-ruled or grounded by this
session's renders/probes (facts 11–14). Expected: no second batched round; coord books final
approval on this package.

## RESULT handoff
Plan file + C01 rewritten to v2; DECISIONS appended (rework rulings + rejected alternatives,
append-only); STATE.json touched only `updated_at` (chunk table unchanged — C01 pending, wave
1). `plan_status` stays `draft` for coord's approval booking.
