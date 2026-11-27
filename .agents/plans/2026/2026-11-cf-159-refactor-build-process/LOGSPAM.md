# LOGSPAM — Forgejo CI log-volume ground truth (cf-159, scout)

Sampled live logs from the **prod instance** `git.spencerslab.com` (Forgejo 15.0.10,
public repo, no login) via the UI's `logCursors` POST endpoint, for the recent runs of
each workflow family. Dev instance `git.scifi.farm` is reachable but its runner is down
(see Caveats). Line counts are full-log counts; "share" is within the run/job stated.

## Ranked sources (by workflow)

### 1. `main-sync.yaml` fan — #337 success (16m56s, commit a91627e06e), 4,851 lines total

| Source | Lines (approx) | Share of run | Ours / platform | DEBUG-gateable |
|---|---|---|---|---|
| **build-charts job, total** | 3,462 | 71% | mixed | — |
| — `git fetch` ref enumeration (`* [new branch]` ×636 + `* [new tag]` ×~340) | ~976 | 28% of job (20% of run) | **ours** (5 full-depth `actions/checkout@v7` fetches + explicit `git fetch --tags` at `build-charts.yaml:447` and `:507`) | **yes** — `git fetch --tags -q` / scoped checkout refspecs suppress the per-ref listing |
| — `helm dependency update` / `helm repo add` chatter (`already exists with the same configuration, skipping` ×220, `Saving N charts` ×77, `Deleting outdated charts` ×77, `...Successfully got an update from the chart repository` ×77, `Extracting chart metadata` ×75, `Getting updates for unmanaged Helm repositories` ×72, `Downloading app-template from repo` ×57, plus ~500 scattered per-chart/per-repo sub-lines) | ~700 | 20% of job | **ours** (3 legs × ~77 repos) | **yes** — capture stdout, emit one summary line per leg |
| — `cr` package/publish echo per chart (`Successfully packaged chart ... saved to` ×150 + per-chart upload/index/digest lines) | ~250 | 7% of job | **ours** | **yes** — one summary line per leg |
| — act runner platform noise (emoji/docker lines ×246, `##[debug]`/`[command]`/`##[endgroup]` markers ×~300, `Complete job` block ×36, checkout-action internals incl. `hint:` ×~78, `Temporarily overriding HOME` ×12, `git version` ×12) | ~730 | 21% of job | **platform (act)** | **no** — not gateable from workflow YAML |
| — real work + intentional echoes (detect outputs, `ROLE=`, `event=`, `CHARTS=`/`HAS_CHANGES`, marker, lint results) | ~30–60 | 1–2% of job | ours | keep ungated |
| checkout block in the 6 other jobs (187–212 lines each: 17–18 `##[]` markers + 40–51 action internals + up to 112 ref-listing lines) | ~1,250 | 26% of run | platform (action); ref-listing leg is ours (full-depth config) | partially — scoped fetch reduces the ref-listing part |
| `Complete job` cleanup block ×7 (incl. repeated `/tmp/git-credentials-*.config` path lines) | ~250 | 5% | platform | no |
| `diag` steps (push-gh 1, push-dev 1, build-containers caller 6, sync-fanout 1) | ~10 | 0.2% | ours | yes (C02) but negligible |

Cross-check: canceled #335 (build-charts failed at 15m31s, 1,969 lines) shows the same
shape — 550 `new branch` + 565 helm-dep + 76 cr-package + 194 act + 85 markers.

### 2. `build-containers.yaml` — PR runs #313 (5m10s) and #328 (4m18s): 1,277 / 1,261 lines; failed dispatch #334 (40s): 403 lines

| Source | Lines (approx) | Share | Ours / platform | DEBUG-gateable |
|---|---|---|---|---|
| buildkit build output (PR leg) | ~1,100 | ~86% of PR job | platform (buildkit; already quiet by default) | n/a — real work |
| `diag` step | 2 (PR leg: `ROLE=` + `event=`) / **72** (dispatch release leg: 6 `ACTIONS_*` env lines + 19 `docker info` lines + buildx/docker version + `ROLE=`/`event=`/`FORGEJO_ACTIONS_RUNNER_VERSION` echoes) | 0.2% / 18% | **ours** (C02 target) | **yes** — but the biggest single diag is only 72 lines; smallest C02 target |
| `actions/checkout@v7` (83 / 71) + `Set up job` (13) + `Complete job` (~36) | ~130 | ~10% | platform | partially (scoped fetch) |
| push leg (registry login, `The push refers`, digests) | ~40 | 3% | platform | n/a |

The Nov 26 renovate-PR burst produced ~15 additional build-containers runs (7–33s each)
while the runner was flapping — those are near-empty and were excluded from counts.

### 3. `builder-bootstrap.yaml` — #219 dispatch (13m10s): 248 lines

| Source | Lines (approx) | Share | Ours / platform | DEBUG-gateable |
|---|---|---|---|---|
| `diag` step | **72** (6 `ACTIONS_*` + 19 `docker info` + buildx 1 + docker version + 44 other env/version lines) | 29% | **ours** (C02 target) | **yes** |
| `actions/checkout@v7` | 71 | 29% | platform | partially |
| buildkit (13m7s of runtime → only 50 lines; buildkit is quiet) | 50 | 20% | platform | n/a |
| registry login (incl. `WARNING! Your credentials are stored unencrypted`) | 7 | 3% | platform (docker CLI) | no |
| `Set up job` + `Complete job` | 48 | 19% | platform | no |

Note: #219's log ends `Job 'publish' failed` — a failed run; volume shape still valid.

### 4. `renovate.yaml` — #279 (34m3s run / 18m15s job) and #249 (18m15s): 258 / 214 lines

| Source | Lines (approx) | Share | Ours / platform | DEBUG-gateable |
|---|---|---|---|---|
| JSON `stats`/resolved-config dump (`"managers": {`, per-manager `fileCount`/`depCount` blocks) | 131–155 | 55–60% | platform (renovate, `LOG_LEVEL=info` default) | **yes — `LOG_LEVEL=warn` collapses both buckets to ~0–10 lines** |
| `INFO:` lines (start, repo started, extraction complete, PR events) | 70–90 | 30–35% | platform | **yes** (LOG_LEVEL) |
| `diag` (2) + `Set up job` (10) + `Complete job` (1) | 13 | 5% | ours (2) + platform | partial |

### 5. `coder-template-push.yaml`

Never invoked standalone (0 runs on the workflow filter); it runs only as the main-sync
fan job — the #337 caller job is 276 lines in one merged step: ~106 `* [new branch]`
ref-listing lines + 78 checkout internals + 50 act lines + 18 markers. Same checkout
story as row 1.

## Verdict

Log volume is dominated by the **main-sync fan** (4,851 lines per push), and within it
by the `build-charts` leg (71% of the run). The two biggest *ours* sources are the
`git fetch` ref enumeration — 5 full-depth checkouts plus two explicit
`git fetch --tags` calls (`build-charts.yaml:447`/`:507`) producing ~976 lines
(~28% of the job) — and `helm dependency update`/`repo add` chatter across 3 legs ×
~77 repos (~700 lines, ~20%); both are straightforwardly gateable (quiet fetch /
output capture with one-line summaries), and `cr` package/publish echoes add ~250 more.
Renovate's daily run is small in absolute terms (≤258 lines) but ~95% of it is
`LOG_LEVEL=info` artifacts that `LOG_LEVEL=warn` removes. The C02 diag dumps
(`env | grep ACTIONS_`, `docker buildx version`, `docker info`) are real but the
**smallest** target at ≤72 lines worst case (2 lines in PR legs), and act-runner
platform noise (~21% of the biggest job, plus a ~26% checkout block and 5% cleanup
block across the fan) is not gateable from workflow YAML. Per-run multiplication is the
real volume driver: one push costs the full 4,851-line fan, and a renovate-PR burst
costs ~15 more ~1,300-line build-containers runs.

## Caveats

- **Dev instance degraded**: `git.scifi.farm` is public and reachable, but all 13
  scheduled renovate runs since Nov 16 show 0s — the dev runner has been offline the
  whole sample period (consistent with EXPLORE §3, 0/10 runner pods). No dev-side logs
  were sampled; for the dev side, workflow-file inference applies (identical workflow
  files, so prod numbers are the best available proxy). If the owner wants dev-side
  confirmation, the pages to check are `git.scifi.farm/CuratedForest/SpencersLab/actions`
  (workflow filter `renovate.yaml` and `main-sync.yaml`) once the runner is back.
- **Sample size**: main-sync #337 (+ #335 canceled as cross-check), build-containers
  #313/#328 (PR) + #334 (failed dispatch), builder-bootstrap #219 (failed), renovate
  #279/#249. 1–3 runs per family, most recent completed runs; today's scheduled
  renovate #338 was still "Waiting" at probe time and is unsampled.
- Ref-listing counts (636 branches / ~340 tags) are specific to #337's repo state:
  branch count scales with open renovate PR branches, tag count with total release
  tags (~340+, growing with each chart bump).
- Runner-down runs (the Nov 26 7–33s burst) have near-empty logs and were excluded
  from all counts; they are a separate (zero-volume) failure mode per EXPLORE §3.
- #219 and #334 are failed runs; their volume shapes were still valid for the diag
  and checkout buckets, which run before the failure point.
- "Share" figures are within-run approximations from pattern counts on the full log;
  per-chart sub-lines were bucketed by prefix, not byte-perfect.
