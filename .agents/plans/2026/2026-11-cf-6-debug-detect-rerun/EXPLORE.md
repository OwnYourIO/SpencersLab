# EXPLORE — cf-6-debug-detect-rerun (agent-explore, 2026-11-24)

Scout grounding for the report: "for PRs and/or reruns of jobs, the build stops
detecting a change and doesn't build the container." All facts below are read/
measured, marked with their source. The coord's leading hypothesis is PROVEN
DEAD as a live mechanism and the real story is different (§5) — the detector
code on origin/main tip (87d3da0c3) is NOT under-reporting on any live run
examined; the owner's symptom is explained by (A) Forgejo's PR trigger
filter over-firing chart-only PRs, producing a wall of correct-but-alarming
`changed set resolved empty` runs, and (B) genuinely empty sets on
re-run-recoverable builds that nobody re-ran, plus build-stage failures
misread as detection failures.

Artifacts kept for later stages: `/tmp/opencode/cf6-explore/` —
`containers-build.yaml`, `forgejo-container-detect.sh`, `forgejo-containers-build-test.sh`
(verbatim from origin/main), `det/*.json` (all 270 run details with stored
`event_payload`), `ui/*.html` (run pages incl. `data-initial-post-response`
per-attempt job/step JSON), `shas.txt`, and `repro/` — a full git clone
detached at 87d3da0c3 with `refs/pull/{1,2,3,5,12,13,18,31,76,85,87,106}/head`
fetched and a synthetic merge branch `m106` (merge of PR106 into 87d3da0c3,
M=501906b33) for merged-PR shape experiments.

## 1. Current code, precisely (origin/main tip 87d3da0c3)

`scripts/forgejo-container-detect.sh` (143 lines) — `detect()` range resolution:

- PR arm, L33–44: `a="${BASE_SHA:-}"; b="${HEAD_SHA:-}"` then
  `printf 'detect: merge-base of %s and %s ...' >&2` (L43) and
  **`a=$(git merge-base "$a" "$b")`** (L44). Both anchors are PAYLOAD env values,
  never a ref name; the diff (L76) is `git diff --name-only "$a" "$b" -- containers/`
  with `$b` still the payload HEAD_SHA.
- Push arm, L46–66: `before="${EVENT_BEFORE:-}"`; empty → `die` L53 (exit 2);
  all-zero → `::warning::first push ... tip-only` + `a=HEAD^ b=HEAD` L60–62;
  else **`a="$before"; b="${SHA:-HEAD}"`** L64–65. Same payload-pinned rule —
  nothing resolves a live ref here either.
- Both arms share the stderr endpoint echo L71 (`detect: range %s..%s`) and the
  unmasked git call L76 (no `|| true`; a bad range is exit 128, loud).
- Gates L83–89 (name regex + `containers/<n>/Dockerfile` existence + sort -u)
  apply to every source including dispatch.

`.forgejo/workflows/containers-build.yaml` detect job:

- Checkout L100–110: `actions/checkout@v7` with `fetch-depth: 0` (integer) —
  the build jobs' checkouts stay bare (shallow).
- Detect env L118–124 (the payload→shell contract):
  `EVENT_NAME: ${{ forgejo.event_name }}`, `EVENT_BEFORE: ${{ forgejo.event.before }}`,
  `SHA: ${{ forgejo.sha }}`, `BASE_SHA: ${{ forgejo.event.pull_request.base.sha }}`,
  `HEAD_SHA: ${{ forgejo.event.pull_request.head.sha }}`,
  `MANUAL_CONTAINERS: ${{ forgejo.event.inputs.containers }}`.
- Step run L125–149: `changed=$(bash scripts/forgejo-container-detect.sh detect)`
  (assign-before-emit), echo of verdict+endpoints L135,
  `changed-containers=$changed >> ${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}` L138, and
  the warning guard L147–149: every empty set warns **except** dispatch-empty
  and `before == sha` (no-op ref update). A PR empty set always warns.

Re-run-path answer: a re-run executes exactly the same step; the only inputs
are the stored run payload's fields (§5 proves they are frozen).

Forgejo context facts (forgejo.org Actions Reference, fetched 2026-11-24):
`forgejo.event` = "JSON object containing event details of how the workflow was
triggered" (the stored webhook payload; `FORGEJO_EVENT_PATH` = the payload file);
`on.pull_request` defaults to types `[opened, synchronize, reopened]`;
`run_attempt` begins at 1 and increments when the job is re-run. The live
payload dumps (§2) show `pull_request` payloads carry
`base.sha/head.sha/merge_base/action/number` and push payloads carry
`before/after/ref`; `push` payloads do NOT carry `pull_request`, and vice versa.

## 2. Live forensics (git.spencerslab.com, anonymous)

Channels: `GET /api/v1/repos/CuratedForest/SpencersLab/actions/runs/{id}` —
**returns the full stored `event_payload` per run (all 270 runs, ids 19–288,
200 anonymous)**; the run page `GET /{repo}/actions/runs/{idx}/jobs/0/attempt/{a}`
embeds `data-initial-post-response` JSON with per-attempt job lists, step
tables and `allAttempts` (the UI redirect of `/runs/{idx}` reveals the max
attempt). Step LOGS are auth-gated (`logs.stepsLog: []` anonymously;
`/actions/runs/{id}/jobs|logs|annotations` → 404) — consistent with the
family's values-endpoint lesson.

**Payload base.sha is the live main tip at EVENT generation time, then frozen.**
All Nov 24 06:36–06:38 PR runs store `base.sha=87d3da0c35...` (main tip as of
Nov 23 22:02); Nov 21 22:0x batch stores `68aecfc8a`; Nov 19 `b7fc1f92e`;
Nov 23 06:3x `bc4b2a3fa`. The API's *current* PR object also shows
`base.sha=87d3da0c3` for every open PR — it is a live field server-side, and
the payload snapshots it at event time.

**Re-runs exist and were recovered correctly (case b — the inverse of the report):**

- UI run **240** (id 257, push `8227e8f29`, stored `before=bc4b2a3fa`): att1
  (≈17:53) detect failed at *Set up job* (runner-down era); att2 18:26:00 and
  att3 18:29:20 GREEN with jobs `detect-changes 7s` + `release forgejo-runner
  1m27s success` + pr skipped. The re-run reproduced the range
  bc4b2a3fa..8227e8f29 (which contains `3303b711d fix(containers): forgejo-runner
  bake... [cf-6]`) and published — push re-runs are payload-faithful, live.
- UI runs **104,108,110,112,113,128,129,130,131,184** — PR runs from Nov 21
  that attempt-2'd at Nov 23 19:36–19:43 after the fleet heal. EVERY one
  re-detected and re-ran the pr-build: e.g. 112 (PR12 music-assistant)
  `detect 7s + pr music-assistant 2m51s success (att2)`; 110 (PR10 enketo)
  `pr okd-enketo 1m59s success`; 130 (PR32) `pr forgejo-host-runner 2m2s
  success`; 131 (PR33) `pr traefik-mqtt-allowlist 28s success`. Stored
  payloads (base 68aecfc8a / heads 2b9c609dc, fe60e8ba4, …) were still the
  Nov-21 values at Nov-23 re-run time → **Forgejo does NOT regenerate the
  PR payload on re-run** (this is the direct refutation of the coord
  mechanism, §5).
- UI run **244** (id 261, workflow_dispatch, stored `"inputs": {}`): att1
  18:05:53 failed at setup; att2 18:24:56 green detect, no build jobs — correct
  no-op for an empty dispatch list. Run 245 (id 262) same shape (inputs {}).
  Run 246 (id 263) carried `"inputs": {"containers": "coder-workspace"}` →
  detect OK → `release coder-workspace` RAN and failed at 1m15s (dind-daemon
  era, cf-6-debug-forge-runner-docker, not detection). Dispatch inputs survive
  storage and fire the build arm end-to-end.

**Case (a) — PR runs that detected empty: all were chart-only PRs, and the
emptiness was CORRECT.** The Nov 23 06:36 + Nov 24 06:36 Renovate waves fired
containers-build for dozens of PRs whose file lists (API `/pulls/N/files`)
contain ZERO `containers/**` files: PR18 (charts/seaweedfs-csi-driver), PR22
(charts/neo4j/values.yaml), PR36 (services/home/prod/values.yaml), PR43, PR48
(.forgejo/workflows/renovate.yaml!), PR66/67/69/73/74/75/82/87 (charts/*).
UI: `detect-changes 6-8s success`, NO build job rows at all (matrix `[]` → both
arms skip), run green — each carrying the step's
`::warning::changed set resolved empty for event pull_request`. That warning
wall is the observable behind "for PRs … stops detecting a change".

Meanwhile the SAME Nov 24 wave's real container PRs DID detect and build:
idx 253 (PR3 → containers/renovate-mcp) 719s success; idx 254 (PR12
music-assistant) 723s; idx 252 (PR106 → containers/forgejo-runner) 624s with
`pr forgejo-runner 1m42s success`; idx 250 (PR1) 234s / 251 (PR2) 528s /
257 (PR31) 778s — those FAILED **in the build step** (job rows exist:
`pr gpt-researcher 1m1s failure` beside `pr gpt-researcher-frontend 3m44s
success` inside the same run), i.e. detection worked and the daemon/build
layer is a separate live-failing surface (fleet heal was mid-flight).

**Under-build that is NOT detection:** PR13 (strata), PR5 (golang), PR90/91/98
and the Nov 23 batch (UI idx 224–239) fired 0-second failures at Nov 23 06:36
(runner down — they never reached detect). All are still attempt/1 — never
re-run. Their stored head shas (934758157, 449ba27d2, 1e60e3847, e9f652542,
f88e11241, 039c0f567, f376376cc, 3635e3493, a3cc8e064, ba0767108, 2b9c609dc)
were all measured **still fetchable by full OID** from the forge (§3), so
those runs CAN be re-run today and would detect per §3 shapes.

## 3. Local reproduction (real objects, the SHIPPED script, not a reimplementation)

Harness: `/tmp/opencode/cf6-explore/repro` — full clone (file:// from the
session worktree + `git fetch forge` from https://git.spencerslab.com),
detached at 87d3da0c3, `refs/pull/*/head` fetched (all fetched OK — PR refs
ARE anonymously fetchable despite `receive.hideRefs`, matching RESEARCH run-2
§6). Invocation exactly as the job does it: `EVENT_NAME=… BASE_SHA=… …
bash scripts/forgejo-container-detect.sh detect`.

| shape | inputs | result |
|---|---|---|
| PR1 first-run (Nov 24 payload) | `BASE_SHA=87d3da0c3 HEAD_SHA=90c305c30` | `["gpt-researcher","gpt-researcher-frontend"]`, range echo resolved `87d3da0c3..90c305c30` (head had been rebased ONTO main tip — merge-base == base.sha) |
| PR106 first-run | `BASE_SHA=87d3da0c3 HEAD_SHA=a1c0e5a44` | `["forgejo-runner"]` |
| PR12 Nov 23 stored-payload re-run | `BASE_SHA=bc4b2a3fa HEAD_SHA=1e60e3847` (branch since force-pushed to b3f1c95f8) | `["music-assistant"]` — re-runs reproduce the original set; force-push does not break the stored head (object fetchable) |
| PR87 chart-only re-run shape | `BASE_SHA=87d3da0c3 HEAD_SHA=9e3415fbe` | `[]` — CORRECT (PR touches only services/home/prod/Chart.yaml) |
| merged PR, payload PINNED | `BASE_SHA=87d3da0c3 HEAD_SHA=a1c0e5a44` after merging PR106 locally into `m106` (M=501906b33) | `["forgejo-runner"]` — re-running a merged PR still detects |
| merged PR, payload REGENERATED (hypothetical) | `BASE_SHA=M HEAD_SHA=a1c0e5a44` | `[]` — merge-base resolves to the head itself (`detect: range a1c0e5a44..a1c0e5a44`), the coord's feared shape — only reachable if a future Forgejo regenerates PR payloads; it does not today |
| push no-op echo | `EVENT_BEFORE=SHA=87d3da0c3` | `[]` silently — designed exemption (L147 guard) |
| push garbage before | `EVENT_BEFORE=dead…beef` | `fatal: bad object`, rc=128 — loud, unchanged posture (d13 class) |
| push re-run shape (run 240) | `EVENT_BEFORE=bc4b2a3fa SHA=8227e8f29` | `["forgejo-runner"]` — matches the live att3 build |

Trigger over-fire repro (the A-mechanism): for PR87 at the Nov 24 event,
payload `merge_base=bc4b2a3fa` (server-tracked, stale) while the true
`git merge-base 87d3da0c3 9e3415fbe` = **87d3da0c3** (Renovate had rebased).
`git diff --name-only 87d3da0c3 9e3415fbe -- containers/` → empty; but
`git diff --name-only bc4b2a3fa 9e3415fbe -- containers/` →
`containers/forgejo-runner/Dockerfile README.md` (the MAIN-SIDE run-4 change
appearing via the stale base). Same measured for PR18 (`68aecfc8a..d56e3519a`
→ forgejo-runner + wekan-mcp files) and the push-side sanity case run 186
(`68aecfc8a..6c16aad4a` legitimately contains containers changes — cf-55
C05's baked-image commits — so its firing was real, its att-3 detect death
was the runner era). Conclusion: the platform's PR paths filter evaluates the
PR diff from the **stale stored merge base** (visible as the payload's
`merge_base` field lagging the rebase), so after ANY main-side containers/**
change, every rebased open PR re-fires containers-build and then correctly
detects empty.

## 4. Payload/ref facts relevant to the fix

- Stored payloads survive re-runs verbatim (push `before/sha`, PR
  `base.sha/head.sha`, dispatch `inputs` — all measured across attempts 2/3,
  §2). `run_attempt` increments; the run row's payload does not refresh.
- The PR payload also carries `merge_base` — but it is server-tracked and
  **provably stale vs the true merge-base after a rebase** (PR1: payload
  bc4b2a3fa, true 87d3da0c3; PR87 same pattern). Do not anchor the fix on it
  without acknowledging that; anchoring on it would reproduce the trigger's
  over-detection inside the detector.
- Old force-pushed heads remain server-fetchable by FULL OID (11/11 measured);
  shortened OIDs fail (git needs the full 40) — a dev/test harness must not
  be written with abbreviated fetches.
- `default_merge_style: merge`, `default_delete_branch_after_merge: false`,
  `allow_squash_merge/rebase(_explicit/fast_forward_only): true` (repo API
  fields) — merged heads land as ancestors of main only under merge-style;
  squash/rebase-merge leaves the old head non-ancestor (merge-base stays the
  old fork) → even a hypothetical regenerated payload would only go empty for
  merge-style merges.

## 5. Mechanism verdict

1. **Coord hypothesis (mutable-ref merge-base / re-run-after-merge ⇒
   merge-base==head ⇒ silent empty): KILLED as the live cause.** The code
   anchors strictly on payload env shas (script L33–35, L44, L64–65; YAML
   L118–124) and Forgejo's re-runs reuse the STORED payload (attempt-2 payload
   fields measured unchanged, §2). The failure shape is reproducible ONLY by
   injecting a regenerated `base.sha` (§3 row 6) — no live run did that.
2. **What actually happened, class by class:**
   - *"PRs don't build"*: (a) chart-only PRs re-fire the workflow after every
     main-side containers change (platform trigger filter on a stale merge
     base) and print `changed set resolved empty` — a misleading wall of
     green-empty runs, correct detection but wrong optics; (b) container PRs
     whose Nov 23 06:36 runs died at 0s (runner-down) were never re-run, so
     their PR images genuinely don't exist — availability, not detection;
     (c) container PRs that DID detect failed in the BUILD step (idx 250/251/257
     Nov 24) — daemon/build layer, another ticket's territory.
   - *"Re-runs don't build"*: false for every observed re-run (push 240, PRs
     104–184, dispatch 244) — all reproduced their first-attempt sets; where
     attempt 1 had never gotten past setup, the re-run did the whole job.
     No re-run produced an empty set that its attempt 1 didn't also produce.
   - No sanitize/first-push/before-staleness bug surfaced: all measured
     `before`s are real oids, no re-run hit the all-zero rule, no force-pushed
     head was GC'd (measured), dispatch inputs stored intact.
3. The one REAL code-visible fragility (not a live failure): if a future
   Forgejo ever regenerates PR payloads on re-run, the PR arm silently
   resolves merge-base==head→`[]` for merge-style merges (§3). Cheap to
   harden (§5-fix-C3 below); currently theoretical.

## 6. Fix candidates (grounded, NOT decided — plan/owner choose)

- **C1 — Legibility, the minimum honest fix.** Distinguish "empty because the
  platform re-fired a PR whose true merge-base..head contains no containers/**"
  (routine noise) from the anomaly the L147 warning was written for. The
  detect step can already compute both (it has payload base/head; it could
  also echo `forgejo.event.pull_request.merge_base` for diagnosis). Shape:
  keep the warning only for the anomaly class, or add a second, quieter line
  naming the noise class; the family has ruled warning-scope before (owner
  exemptions of dispatch/before==sha), so this is an owner-ruling item.
- **C2 — Trigger-noise containment.** The over-fire itself lives in Forgejo's
  paths filter (stale stored merge base), not in this repo's code — options
  range from accepting the 6-8s runs, to filing an upstream Forgejo issue
  (evidence package ready: PR18/PR87 payload merge_base vs true merge-base +
  run lists), to (heavier) dropping `on.pull_request.paths` and gating
  build-pr on the detector only — which changes nothing observable today
  (detect already empties them) except run-list noise. Needs-research: the
  exact server-side filter code path (gact `changedPRFiles`/stored
  `pr.MergeBase` semantics) was NOT source-verified here — inference from
  behavior + RESEARCH run-2 F15 references.
- **C3 — Re-run idempotency insurance (optional hardening).** The merged-PR
  regeneration hole (§5.3): the PR arm could detect the degenerate shape
  `merge-base == head.sha` with a payload that claims an open PR and turn it
  into a loud `die` (like the empty-before A5 rule) instead of silently
  answering `[]`. Costs one script branch + one new leg; kills the entire
  hypothesis-class permanently. Plan must rule whether a theoretical-only
  hardening earns text-pin churn (t13/d-legs stay green — the change would be
  purely additive inside the PR arm).
- **C4 — Not-a-fix to record:** do NOT switch the PR base to the payload's
  `merge_base` field — it is demonstrably stale after rebases (§3/§4) and
  would import the trigger's over-fire into the detector (rebuilding
  main-side containers on every chart PR — the exact thing owner ruling B5
  forbids).
- **Backlog the real under-builds:** re-run (or dispatch, or let next
  Renovate synchronize re-fire) the dead-at-0s Nov 23 container-PR runs —
  heads still fetchable, payloads pinned, proven to reproduce (§3 row 3).
  Zero code needed; it's an owner UI leg.

## 7. Teeth map (tests/services/forgejo-containers-build.sh, 41 legs — `ok` count measured 41)

Legs pinning the detect surface (fix-change surface per candidate):
- **t12** L809–855: detect checkout `fetch-depth: 0` integer pin — untouched by C1–C3.
- **t13** L858–905: the six env accessors byte-pinned (incl.
  `BASE_SHA='${{ forgejo.event.pull_request.base.sha }}'` L888,
  `HEAD_SHA=…head.sha` L889) — a fix changing env mapping MUST re-pin here.
- **t14** L907–1045: executes the shipped step body in 5 env shapes and pins
  WHICH arms warn (the `before==sha`+dispatch exemptions vs empty push/PR
  warnings) — **C1 lands here first** (behavioral half; add shapes for the
  new quiet/noise posture).
- **t15** L1048–1101: no `|| true`/masking on git calls (loud-failure posture) —
  C3's extra die-branch stays green under it (it adds loudness, never masks).
- **d1–d15** L1617–1902 (fixtures ~1561–1902): script behavior — d1/d9/d10/d11
  push range+first-push postures, **d14** (PR arm diffs merge-base..head,
  L1865–1877) / **d15** (PR degenerate shapes die loud 128/unrelated-pair 1,
  L1879–1902) are the PR-arm pins; C3 adds a d16-class leg (merge-base==head
  with open-PR payload → red), C1 changes none of d.
- **x5** L2103–~2170: detection-contract DOC pins (vocabulary markers) across
  `skills/container-creation/SKILL.md` + `.rulesync/rules/overview.md` +
  `AGENTS.md`, with the banned-UI-chip list — any wording change to the
  Detection. contract or the warning posture must land on all three doc
  surfaces in the same change (rulesync twin law).
- No other suite reads the detector's text: `tests/services/forgejo-release.sh`,
  `forgejo-packages.sh`, `forgejo-ci-surface.sh`, `forgejo-main-sync.sh` do not
  reference it (grep); **`tests/services/forgejo-builder-bootstrap.sh` (the
  lane b-suite) pins NON-USE** of `forgejo-container-detect.sh detect` in the
  bootstrap lane (L755) with mutation fixtures (L1100/L1154) — must stay
  byte-untouched by this fix. `tests/containers/forgejo-runner.sh` L13 only
  cites the gating comment as prose.

## 8. Boundary facts (unobservable anonymously — owner legs, not guesses)

- Job step LOGS (the exact `changed containers: … (event … base=… head=…)`
  echo lines and which container failed): auth-gated. Owner command:
  `curl -H 'Authorization: token <PAT>' https://git.spencerslab.com/api/v1/repos/CuratedForest/SpencersLab/actions/jobs/<job_database_id>/logs`
  or the per-run zip from the UI; run pages: `…/actions/runs/{250,251,257}`
  (build failures), `{224..239}` (Nov 23 dead-at-0s), `{104,108,110,112,113,128,129,130,131,184}` (attempt-2 recoveries), `{240,244,245,246}` (push+dispatch).
  (Job ids visible: detect job of run 240 = 783, release = 797, pr = 798.)
- Whether dispatch runs 244/245 were INTENTIONALLY dispatched empty (payload
  says `inputs:{}` stored — the runs are correct no-ops; only the owner knows
  what they typed).
- The ROLE variable value per instance (diag echoes are in the gated logs).
- Root causes of the Nov 24 BUILD failures (idx 250 gpt-researcher 1m1s,
  251/257 coder-workspace ~1m14s) — outside this ticket's scope until owner
  fetches those logs; same fingerprint family as cf-6-debug-forge-runner-docker.
- Exact gact code path of the PR paths-filter stale-merge-base behavior —
  inferred from payload `merge_base` staleness + observed firings; a
  needs-research item if the plan wants the upstream-issue route (C2).

## Forensics: AD-133 re-integration push (2026-11-25)

Targeted delta probe on the owner's 2026-11-25 report: they re-integrated (replayed/rebased)
the AD-133 chain onto main and pushed; containers were involved somewhere, **no container
detected as needing a build**; their guess was "because it wasn't in the last commit".

**Verdict: detection was CORRECT — nothing is broken.** The chain's only containers/**
change, `containers/argocd-hook/` (the cf-139 webhook-sync relay), was ADDED
(`e67e9f07b feat(cf-139): add argocd-hook webhook sync relay`) and DELETED
(`7a303d24e chore(cf-139): C07 disposals - relay layer git rm'd ... [P2] never-deployed
proof - no deregistration owed`) **inside the same pushed range**, so the range law's
two-dot tree diff (`git diff before sha -- containers/`, script L76) resolves NET-ZERO:
no container file differs between the two endpoint trees. The owner's "not in the last
commit" guess maps to no live code path — the tip-only rule (L55–62) fires only on an
all-zero `before` (branch creation), and every push today was a fast-forward with a real
before (`87d3da0c3` is a direct ancestor of the tip). The correct mental model is the
mirror statement of the range law: mid-range changes DO count, but only as their NET
effect between endpoints — an add-then-remove leaves no net effect and nothing at the tip
tree to build (the `[ -f containers/argocd-hook/Dockerfile ]` gate at L86 would drop the
name even if it surfaced). The container was never built from main and never needed to
be (sub-question b: no prior build — argocd-hook never existed on main before today and
was disposed the same day).

**Push decomposition (all measured, 2026-11-25):** origin/main moved
`87d3da0c3 → 537d46655` (replay chain, ct 00:33:37) `→ 7c550f23c` (traefik PR113 merge,
00:33:58) `→ d3043751e` (argo-cd PR112 merge) `→ 3f21e85e8` (cf-11/cf-55 records,
01:10:26) `→ 7fb41e5d0` (cf-145 radiance-grafana merge, 01:38:29; charts/monitoring only).
Actions run list confirms the pushes: new runs are ids 289–296 ONLY — main-sync + release
arms (each fired per its own filters), **zero containers-build runs** → the
`on: push: paths: ['containers/**']` filter itself matched nothing on every push, which
is exactly right for net-zero ranges. Sub-question (c) (force-push orphaning a container
commit into a red range): ruled out — FF-only movement (no orphaned pushes, no cb runs,
no 128/red detect today), and the mid-range trees DO show the directory
(`git ls-tree 6d7fcaaa4 containers/` → `containers/argocd-hook`) yet each push's endpoint
pair nets empty.

**Reproduction (shipped script, real objects, /tmp/opencode/cf6-explore/repro @ tip):**

```
P1-chain   before=87d3da0c3 sha=537d46655 -> [] (add e67e9f07b + delete 7a303d24e inside)
P2-traefik before=537d46655 sha=7c550f23c -> []
P3-argocd  before=7c550f23c sha=d3043751e -> []
P4-records before=d3043751e sha=3f21e85e8 -> []
whole-day  before=87d3da0c3 sha=3f21e85e8 -> []   (+ 87d3da0c3..7fb41e5d0 net: empty)
```

(`env EVENT_NAME=push EVENT_BEFORE=<before> SHA=<sha> bash
scripts/forgejo-container-detect.sh detect` — stderr endpoint echo confirms the push arm.)

**One doctrine note for the plan round (feeds R3/R4, not a gap; lives in this section,
not §7's teeth map):** if an integration EVER
lands the add of a real (non-disposed) container in the same range as its build-motivation,
the tree-diff posture means the fleet sees the container only from the endpoint tree — a
partially-replayed push (chain lands WITHOUT its disposal commit) would net-show the added
Dockerfile and build it correctly; an add+remove netting zero is the designed silence, and
should stay silent. No failing line exists — no fix candidate needed for this event; §5's
verdict stands unchanged.

RESULT
status: DONE
chunk: explore
files_changed: [.agents/plans/2026/2026-11-cf-6-debug-detect-rerun/EXPLORE.md]
commands_run: [git fetch origin (+main) => pass; git log origin/main since 11-24 => pass (5 pushes decomposed); git merge-base --is-ancestor 87d3da0c3 tip => pass (FF, not orphaned); git diff --name-only per push range -- containers/ => pass (all net-empty); git log --name-status range => pass (argocd-hook A/M/D trio); GET /actions/runs (278 total; ids 289-296 all main-sync/release, zero containers-build) => pass; shipped detector over 5 real ranges in repro clone => pass (all [] as expected)]
deviations: none — delta appended as its own section under the same file.
friction: none new.
open_questions: none — owner report on this event is fully explained (correct net-zero detection); their "not in the last commit" model should be corrected to "added-and-removed within the same push range nets zero".
next_suggested: fold the §7 doctrine note into the plan round as confirmation that the range law behaved as designed; no code delta from this event.
commands_run: [git fetch origin main => pass; git show origin/main:<3 files> => pass; curl api/v1/version => pass (15.0.10+gitea-1.22.0); GET /actions/runs + /actions/runs/{19..288} => pass (all 270 stored payloads, anonymous); GET /pulls?state=all + /pulls/{N}/files => pass; UI /actions/runs/{idx} redirect+attempt pages => pass (per-attempt job/step JSON via data-initial-post-response); GET /actions/runs/{id}/jobs|logs|annotations anon => fail-404 (auth-gated, as lesson said); git clone file:// + fetch refs/pull/*/head => pass; fetch by full OID 87d3da0c3 + 11 old heads => pass (all fetchable; shortened OIDs => fail, expected); bash scripts/forgejo-container-detect.sh detect over 9 real shapes in the repro clone => pass (all reproduced live behavior); local merge m106 + regeneration-shape repro => pass; grep teeth map (41 ok legs, non-use pins in builder-bootstrap, x5 doc pins) => pass]
deviations: Used a standalone /tmp/opencode clone (kept, with refs + synthetic merge branch m106) instead of an in-repo temp worktree, so the session repo stayed byte-clean; re-run case (b) exists for push/dispatch/PR-recoveries but NO live run contradicts first-attempt detection — the requested empty-on-rerun pair does not exist in 270 runs, documented as such rather than manufactured.
friction: The runs LIST API returns ~25KB of nested repo object per run with attempt/event hidden (detail endpoint carries event_payload; attempt truth lives only in UI redirects + allAttempts JSON) — first-pass field extraction mis-read durations as seconds (they are ms after //1e6 from ns); the abbreviated-sha fetch "GONE" false alarm cost one re-measure (git fetch needs full OIDs).
open_questions: 1) Owner ruling — is the PR `changed set resolved empty` warning to be re-scoped per C1 (the current shape is noise-magnified by the platform's stale-merge-base trigger)? 2) C3 hardening (merge-base==head ⇒ die) worth the added leg, given no live trigger for it? 3) Upstream route (C2) for the trigger over-fire — needs a source-level research pass (gact changedPRFiles / stored pr.MergeBase) if the owner wants it filed. Needs research: yes for (3). 4) Owner legs: dispatch 244/245 typed inputs + Nov 24 build-failure logs (commands in §8).
next_suggested: Plan around C1 (legibility re-scope of the PR empty-warning) + the no-change finding that detection/re-runs are payload-faithful (kill the hypothesis, record §5 as the evidence section); optionally C3 insurance and an owner re-run/dispatch leg for the dead-at-0s Nov 23 container PRs; leave the b-suite and t12/t13 pins untouched.

## Bucket-C investigation (2026-11-25)

Classification of the three Nov-24 build-red runs (DECISIONS approval entry, bucket C;
B1/B2 gate). Channels re-verified per the newer API note: the runs LIST endpoint
(`/actions/runs?limit=50&page=N`, anonymous, 278 rows, max id 296) NOW embeds
`event_payload` per row — the detail-per-id loop is no longer needed. UI `idx` ↔ API `id`
offsets differ per run (idx 270 = id 288, idx 240 = id 257), so every claim below carries
both. Step LOGS remain auth-gated (`state.run.jobs[]` carries job-level
name/status/duration only; per-job pages redirect to login; `logs` empty). All probes ran
from the **Coder-workspace egress**, not the cluster runner egress — the family lesson
(get.helm.sh TLS-blocked from cluster, 200 from workspace) means registry/URL liveness
proves the artifact exists, not what a runner saw at 06:36. Artifacts:
`/tmp/opencode/cf6-explore/bc/` (`all.json` = 278 list rows w/ payloads, `pages/*.html` =
all 153 cb run pages, `pr*.json`) and the kept `repro` clone (new `bc/pr1,pr2,pr31,pr3,
pr12,pr106,pr5,pr13,pr90,pr91,pr98` + `bc/main` branches; fetched refs, no history
rewrite). No temp worktrees created; repo untouched.

### C.1 Re-verify the planner's forensics

| claim | verdict | evidence |
|---|---|---|
| last containers-build = id 288, Nov 24 06:38, nothing after | PROVEN, with a nuance | id 288 = idx 270 = PR87 (wekan Helm chart), created 06:35:08Z, stopped 06:38:58Z, status success — **but it was a chart-only empty-detect run (6s detect, zero build jobs)**. The last runs that actually PUBLISHED builds are the 06:20–06:33 trio: idx 252/id 270 (PR106 forgejo-runner, pr job 1m42s green), idx 253/id 271 (PR3 renovate-mcp, 719s), idx 254/id 272 (PR12 music-assistant, 723s). No cb run > id 288 at 03:31Z Nov 25 (max id still 296 = main-sync/release arms only). |
| idx 240 success (push) | PROVEN | id 257, push `bc4b2a3fa..8227e8f29` (created 18:00:42), att2/att3 green per §2 (release forgejo-runner 1m27s) — §2 stands. |
| idx 246 fail (dispatch) | PROVEN | id 263, `inputs={"containers":"coder-workspace"}` by tms, Nov 23 19:41→20:05, job 805 `release coder-workspace` failure **1m15s** (list-row `event` empty for dispatch — payload confirms shape). |
| idx 250/251/257 build-red | PROVEN, names corrected | idx 250/id 268 = **PR1** head 90c305c30 `Update assafelovic/gpt-researcher digest to 9d39a2f`; idx 251/id 269 = **PR2** head ba005048e `Update debian:13-slim Docker digest to 8aa5a7b`; idx 257/id 275 = **PR31** head 799011ace `Update dependency @opencode/cli to v2.4.1`. There is **no `containers/opencode`** — PR31 touches `containers/coder-workspace/Dockerfile` (`ARG OPENCODE_VERSION`), so the UI job name on idx 257 is `pr coder-workspace`. Two of the three reds are the same container. All three are attempt/1 (redirect targets), never re-run; PR heads unchanged since (API `/pulls/{1,2,31}` heads == failing commits ⇒ **NOT auto-healed by any later push**; all three still open, base now a28e53189). |

### C.2 Per-run diffs and what each PR actually changed (read locally from fetched PR refs)

- PR1: `ARG GPTR_VERSION=5cdad9cb4… → 9d39a2f8…` (datasource=git-refs, an **assafelovic/gpt-researcher
  git commit** cloned at build, not a base image) in BOTH `gpt-researcher/Dockerfile` and
  `gpt-researcher-frontend/Dockerfile`. Base lines untouched: backend `FROM python:3.15-slim-bookworm`
  (unpinned tag), frontend `FROM node:24-bookworm-slim`.
- PR2: single line — `FROM debian:13-slim@sha256:62bd423a… → @sha256:8aa5a7bf…` in `containers/coder-workspace/Dockerfile`.
- PR31: single line — `ARG OPENCODE_VERSION=2.1.4 → 2.4.1` in the same file; base stays @62bd423.

### C.3 The coder-workspace verdict: PROVEN structural content bug (class c) — predates all three reds

`containers/coder-workspace/Dockerfile` L127–131 (the node stage, identical on every failing
head, on `8227e8f29`, and on current main): the URLs interpolate a **bare semver into a
path that requires the `v` prefix** —
`https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz` with
`ARG NODE_VERSION=26.12.1` (renovate `datasource=node-version` emits bare versions by design).
Measured from workspace egress: `…/dist/26.12.1/node-26.12.1-linux-x64.tar.xz` → **404**;
`…/dist/v26.12.1/node-v26.12.1-linux-x64.tar.xz` → 200 (nodejs.org has never hosted
v-less dist dirs ⇒ time-invariant, was 404 on Nov 19–25 too). Three more spots in the same
layer need `v`: the SHASUMS256.txt fetch, the grep pattern (`grep " node-${NODE_VERSION}-…$"`
— real lines are ` node-v26.12.1-…`; empty grep + `sha256sum -c -` is **vacuous-green**, the
family's own d-c1 vacuity class), and the assertion `test "$(node --version)" = "${NODE_VERSION}"`
(node prints `v26.12.1`). Introduced by `3713c83d1 feat(coder): rebuild workspace image on Debian
slim + hardened template` (2026-10-20) — git-lore: the pre-rebuild file used a correct hardcoded
`v26.8.1` URL; the ARG-ization dropped the `v`. No later commit touched the line (`git log -L`).
Consistent with history: **0 green / 15 red since containers-build existed**, and the red shape
splits into the runner-down 5–6s era (Nov 16–21 14:46) and the deterministic **1m13s–1m16s**
era (Nov 21 21:41 ×3, Nov 23 dispatch, Nov 24 PR2 + PR31) — same duration despite different
bases (62bd423 vs 8aa5a7b) and different npm pins (2.1.4 vs 2.4.1): the death is in the
unchanged node layer, right after the ~1-minute apt layer. The last published image,
`ghcr.io/ownyourio/coder-workspace:v68`, was created 2026-10-25T12:56Z (GitHub builder, before
main-sync existed) — CI has never produced a new one. **PR2 and PR31 cannot fix this** (both
changes are orthogonal to the bug); re-running them as-is reddens again.

Everything else in that Dockerfile checks out live: debian **both** digests + tag 13-slim → 200
(docker.io token flow; class (a) RULED OUT — PR2's new pin is real and current), go.dev go1.27.3
200, get.helm.sh helm-v3.22.1 200 (workspace-only claim — cluster egress blocked that host in the
run -4 era, so its verdict on the runner is NEEDS-LOG), dl.k8s.io v1.36.5 200, uv
`releases/download/0.13.5/…` 200 (uv tags are v-less; my first v-prefixed probe was a test
artifact — the Dockerfile URL is correct), codeberg forgejo-cli v0.7.0 200 **and its
hardcoded `FJ_SHA256=6803c12e…` matches the fetched tarball byte-for-byte**, npm
@opencode/cli 2.1.4/2.4.1 and @openchamber/web 2.5.1 all exist. ⇒ coder-workspace has exactly
ONE defect: the node layer's missing `v` (three-line fix, same fix also needed on top of
PR5/PR90's future bumps — the bug is Renovate-orthogonal and will outlive every pin bump).

### C.4 The gpt-researcher verdict: class UNKNOWN — only-with-logs (needs an owner leg), but (a)/(c)/(e) are eliminated

Same run, sibling leg green: idx 250 jobs = detect 6s green, `pr gpt-researcher-frontend` **success
3m44s**, `pr gpt-researcher` failure **1m1s** (job 880). The frontend proves, for the same minute
of the same runner pool: docker.io pull works (`node:24-bookworm-slim` by tag), apt/bookworm works,
GitHub clone works, and **the very commit PR1 pinned checks out** — so PR1's content is not the
killer. Independently verified: commit `9d39a2f86d55…` exists on GitHub (200); `python:3.15-slim-bookworm`
manifest 200 on docker.io (class (a) ruled out); download.pytorch.org, pypi.org, and the baked HF
model (`all-MiniLM-L6-v2/config.json`) all 200 from workspace egress (class (c)-dead-URL ruled out
for every RUN fetch target). What remains is (d) transient fetch (the backend-specific stages —
torch wheel from download.pytorch.org, PyPI, huggingface — sit in exactly that 1m1s window after
base+apt+clone) or (b) docker.io per-repo anonymous ceiling (run -4's P2 question;
`toomanyrequests` has a distinct wire string — visible only in logs). NEVER-GREEN note: the
backend has **0 green / 3 red** in CI (the two earlier reds were 5–6s runner-down era), so unlike
coder-workspace there is no deterministic signature; and unlike coder-workspace the same commit
+ base built GREEN for the frontend. Minimal next probe, in order: **re-run idx 250** (attempt 1,
head 90c305c30 still fetchable — §3 law; transient class ⇒ green, deterministic class ⇒ same
1m1s, which then makes the log fetch decisive). Owner log commands for the gated step lines (§8
shape, job ids measured this round): `curl -H 'Authorization: token <PAT>'
https://git.spencerslab.com/api/v1/repos/CuratedForest/SpencersLab/actions/jobs/{880|883|891|805|614}/logs`
(= gpt-researcher, PR2-coder, PR31-coder, dispatch-coder, strata-Nov21).

### C.5 Candidate-class scoreboard (per the launch's five classes)

- (a) base tag moved/died: **not this wave** — debian@8aa5a7b, debian@62bd423, python:3.15-slim-bookworm,
  node:24/26, alpine:3.24, rust:slim-bookworm, ghcr strata 0.2.13/0.2.20 tags, llama-swap
  unified-vulkan-266/275, enketo 7.6.4, vllm-radiance@b73bf3e all live. The "debian base" report
  was PR2's *title*, and PR2's digest is valid.
- (b) docker.io anonymous ceiling: **not proven anywhere this window**; the same-window docker.io pulls
  green (node:26@3fcc460 06:21–06:33, node:24 06:36–06:40) argue against it as the coder/gpt killer;
  stays open only as the gpt-researcher minority branch (per-repo variant), log-visible.
  The lane itself (bootstrap id 260 pulling docker.io alpine/helm@digest, Nov 23 18:01) was GREEN.
- (c) content broken in the PR diff itself: **no** for all three — each pin is real. But YES in the
  broader sense for coder-workspace: the diff inherits a **main-side structural bug** (node `v`).
- (d) transient fetch: the honest open class for gpt-researcher (and the Nov 21 55s strata death —
  job 614, siblings green around it); retry-safety of lane→PVC means re-runs are cheap discriminators.
- (e) infra/daemon window: **ruled out** — the three reds' ~1m1x clustering is queue serialization
  (one runner; the Nov-24 06:36 cluster starts the moment PR3/PR12's 12-minute builds free it), and
  the SAME 1m13–1m16s coder deaths happened on Nov 21 and Nov 23 while sibling builds went green
  around them (idx 108 vllm 9m40s, 110 okd 1m59s, 130 host-runner 2m2s, 131 traefik 28s green at
  21:40–21:42).

### C.6 Run-4 exoneration + fleet-sweep for B1

All four red `builder-bootstrap` dispatches (ids 224/231/235/256, Nov 22–23) ran shas that do NOT
contain the run-4 fix `3303b711d` (2026-11-23T18:00:15Z); the first post-fix dispatch id 260, one
minute after the merge, is **green**, and the post-fix forgejo-runner push (idx 240) + PR (idx 252)
builds are green. No lane bake failure indicting run-4 exists anywhere in the data. Per-container CI
history (153 cb runs): green-ever — forgejo-runner 2, renovate-mcp 2, music-assistant 2, okd-enketo 1,
vllm-radiance-mxfp4 1, traefik-mqtt-allowlist 1, forgejo-host-runner 1, gpt-researcher-frontend 1;
**never green** — coder-workspace 0/15 (proven bug), gpt-researcher 0/3 (open), strata 0/5 (last
real try Nov 21 55s red, job 614, all pins live, last image v202 Nov 11 from the GitHub builder),
wekan-mcp 0/1 (5s, runner era, never retried), snapcast and brother-ptouch-automation: **never
built by this CI at all** (no PR touched them; all their pins live-checked: snapcast v0.28.0 zip,
roc v0.4.0 ×3 debs, 200s; bases python/rust/debian/node 200s).

**B1 aggregate: NO — a full-fleet dispatch cannot go fully green today, and the gate is one commit.**
(1) coder-workspace is PROVEN red until the node-layer `v` fix lands on main (any B1 leg for it
reddens deterministically); (2) gpt-researcher-backend and strata are unverified-likely-red classes
whose cheapest discriminator is an owner re-run of idx 250 and the PR13/PR98 re-runs (heads all
still fetchable: e9f652542, a47df58a1, 90c305c30); (3) snapcast/brother/wekan-mcp have zero CI
history — B1 is their first real try (pins live from here, but the runner-egress view of their
fetch hosts is unproven). (4) The dead-at-0s Nov 23 batch, re-verified with per-PR containers
diffs: PR5 (go 1.27.4 — live) hits the node bug on the coder-workspace leg regardless; PR13/PR98
(strata) + PR90/PR91 (bump pins, all live) are safe to re-run; PR90's frontend base moves
node:24→26 (tag live). C01 (marker waves) stays independent of all of this, per the plan's own
B3 ruling. The bucket-C sequencing law from RESEARCH is now MEASURED, not assumed: one fix commit
(node `v`) + three re-run legs + (if the re-runs redden) five log fetches — the commands are in
C.4 — and B1 can proceed.

RESULT
status: DONE
chunk: explore
files_changed: [.agents/plans/2026/2026-11-cf-6-debug-detect-rerun/EXPLORE.md]
commands_run: [GET /actions/runs?limit=50 x6 pages => pass (278 rows, event_payload embedded in LIST rows per the newer note, ids 1-296); GET /pulls/{1,2,31,106,12,3} => pass (heads unchanged vs failing commits); UI runs/{250,251,257}+attempt pages => pass (job-level rows; per-job pages auth-redirect, logs gated — as expected); git fetch refs/pull/{1,2,3,5,12,13,31,90,91,98,106}/head + main into kept repro clone => pass; git diff/merge-base per PR (containers/) => pass; git log -L nodejs.org line => pass (bug since 3713c83d1); curl nodejs.org/dist 26.12.1 vs v26.12.1 => 404 vs 200; curl go/get.helm.sh/dl.k8s.io/uv/codeberg/snapcast/roc/strata-tag URLs => pass; curl -I api.github.com commit 9d39a2f + harteWired b3fa5f0 => 200; docker.io token+manifests (debian x3 digests/tag, python 3.13/3.14/3.15-slim-bookworm, node 26, alpine 3.24, rust, bookworm-slim, vllm-radiance digest) => all 200; ghcr token+manifests (strata x4, llama-swap x2, enketo, coder-workspace/gpt-researcher/strata tag lists + v68 config blob created-date) => pass; sha256sum of fj v0.7.0 tarball => matches FJ_SHA256; 153 cb UI pages fetch+parse => pass (per-container job history); git merge-base --is-ancestor 3303b711d x6 bootstrap shas => pass (all 4 reds pre-fix, 260 post-fix green)]
deviations: none — appended to the same EXPLORE.md; no repo writes outside the ticket folder; no temp worktrees (reused the established /tmp repro clone); probes labeled workspace-egress.
friction: none new — known lessons reused (list-row payload now richer, step logs still gated, urllib blocked on the forge HTML where curl passed — used curl/xargs).
open_questions: 1) Owner leg — re-run idx 250 (PR1 gpt-researcher, head 90c305c30 fetchable, attempt/1) as the transient-vs-deterministic discriminator; if it reddens at ~1m1s again, fetch job 880's log (command in C.4). 2) Owner/dev leg — the coder-workspace node-layer `v` fix (three interpolation sites incl. the vacuous SHASUMS grep + the node --version assertion) must land BEFORE B1; it is orthogonal to PR2/PR31, which may then be closed or re-run trivially. 3) Strata: re-run PR13 or dispatch strata from main as the cheap probe (its 55s red predates the heal-wave sibling greens). Needs research: no — everything decisive is either proven or log-gated (owner commands given).
next_suggested: hand B0's gate to the owner as one commit (node v-fix) + three re-run legs; B1 stays gated on the v-fix landing, B2 follows the publish; C01 unaffected.
