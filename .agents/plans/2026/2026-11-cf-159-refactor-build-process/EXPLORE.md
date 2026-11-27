# EXPLORE — cf-159 Improve build process (card AD-159)

Written by `agent-explore` 2026-11-27 (workspace clock). Read-only grounding for the
planner: the six-workflow build/sync thread in `.forgejo/workflows/`, the
`ci/last-built` marker mechanism, the `cf-55-feat-helm-builds-to-forgejo-rebuilt`
branch state, the live dev+gpu runner breakage (observed, not fixed), the Forgejo
instance topology, and the `set -e`/DEBUG question. No solution design, no plan.

Feature folder: `.agents/plans/2026/2026-11-cf-159-refactor-build-process/`
Run posture: **uncommitted, in place** on `main` (Worktree Creation unchecked).
Caveat for every later stage: the local checkout's `main` is **2 commits behind
`origin/main`** — `e5a816295` and `1d46d1c84`, both `chore(release): bump coder
forgejo-runner` CI commits (03:57Z / 04:28Z today), which the local tree does not
carry. `origin/main` tip == the `ci/last-built` marker (verified, §2.3).

## 0. The three card asks, grounded up front

1. **"The cf-55 … rebuilt changes broke dev and gpu's runners."** Confirmed live
   (§3): 0/10 runner pods ready on **both** clusters, main `runner` container
   crashing with `Error: runner: 0 server connections configured, terminating`.
   The breakage is the C17 chart shape (on `main`) with empty config leaves on
   the runner PVCs; the fix (C18) sits **unmerged** on the rebuilt branch (§2).
2. **"Logs are overchatty, likely because of set -e — make it conditional on
   DEBUG=true."** `set -e` (as `set -euo pipefail`) appears in **43 workflow run
   blocks** + 3 scripts (§1.4). Note for the plan: **`set -e` does not produce
   log output** (there is no `set -x` anywhere in `.forgejo/`); the actually
   chatty sources are named in §1.4. Also, gating *errexit* itself on DEBUG
   changes failure semantics in load-bearing steps (push/bump) — flagged in §5.
3. **"main-sync.yaml rebuilds the helm charts on every run."** The *detection* is
   marker-anchored and already touched-only (§1.3); what is **not**
   touched-scoped is the packaging/publish leg (`cr package charts/*/` when any
   chart changed) and the full-tree lock self-heal — plus renovate chart-dep
   churn makes `has_changes=true` frequent (§1.3, §5.2). What the user is seeing
   is real work, not a detection bug; the plan must decide which of those legs
   to narrow.

## 1. The build/sync thread (`.forgejo/workflows/`, 6 files)

All six files carry **no repo URL and no token literal** — destinations and
credentials are instance-side repo vars/secrets, so the files are identical-safe
to host on both Forgejo instances. Instance selection is the repo-scoped `ROLE`
var (comma list over `{dev, prod}`, no spaces); every guard tests membership
with `contains()`. Substring caveat (documented in-file): no future role word may
contain `dev`/`prod` as a substring.

| workflow | trigger | ROLE guard / unset | marker | detection | publishes |
|---|---|---|---|---|---|
| `main-sync.yaml` | `push: [main]` + dispatch | `contains(prod)`, **narrow** (silent) | **writes** (sole writer, D54) | — (aggregate gate) | plain non-force push → GitHub + dev Forgejo; ArgoCD syncs via `scripts/argocd-fanout.py` (org-level `ARGOCD_SYNC_TOKENS`) |
| `build-charts.yaml` | `workflow_call` only (push arm retired C15/D56) | `contains(prod)`, narrow | reads | `marker..sha -- charts/` → `before..sha` → `HEAD^` (first push, all-zero before, warns) → **fatal** on empty before; DNS-safe dir name + `Chart.yaml` present | FF-only bump commit to **Forgejo main** (calendar `Y.M.N`), then DUAL: GitHub Releases + gh-pages index (`cr upload --skip-existing`) and the instance Helm package registry (skip-if-in-index via same-indent name/version awk pairing) |
| `build-containers.yaml` | `pull_request [main]` paths `containers/**` + dispatch (free-text `containers`) + `workflow_call` | `vars.ROLE == null \|\| contains(dev) \|\| contains(prod)` — **widens on unset** (the deliberate opposite polarity) | reads (call-side only) | `marker..sha` (call) / `before..sha` / tip-only (all-zero before, warns) / `merge-base..head` (PR) — via `scripts/forgejo-container-detect.sh` | `ghcr.io/ownyourio/<img>` + instance registry `curatedforest/<img>`, calendar `yy.mm.N` (union-max of both registries' walked N, bounded 50) + `:latest` + `:main`; PRs: `pr-<branch>-<sha>` to instance registry only |
| `coder-template-push.yaml` (cf-56 C04, AD-56) | dispatch (free-text `templates`) + `workflow_call` | `contains(dev) \|\| contains(prod)`, narrow | reads (read-only; never writes it) | `marker..sha` (call) / `before..sha` / manual list — via `scripts/coder-template-detect.sh` | Coder instance of the executing Forgejo (`CODER_URL` var + `CODER_SESSION_TOKEN` secret; warn-and-skip green when unconfigured) |
| `renovate.yaml` | `schedule 06:17 UTC` + dispatch | `contains(dev)`, narrow | — | full-repo pass (container job, image pin `ghcr.io/renovatebot/renovate:44.181.5-full`, `LOG_LEVEL: info`, `RENOVATE_BINARY_SOURCE: global`) | dependency PRs against the repo (instance-side `RENOVATE_TOKEN` + `RENOVATE_GITHUB_COM_TOKEN`, `RENOVATE_GIT_AUTHOR` var) |
| `builder-bootstrap.yaml` | dispatch only (no input) | `contains(prod)`, narrow | — | — | instance registry only, single-registry calendar walk (ruling OQ-1=B), no ghcr arm |

### 1.1 The `ci/last-built` marker mechanism (D53/D54, C14/C15)

- One **shared** marker ref, read by all three builders, written by exactly one
  job: `main-sync.yaml`'s `advance-marker` (`needs: [build-containers,
  build-charts, push-coder-templates]` — the needs-gate IS the aggregate rule).
- Endpoint law (D53): the marker advances to the **charts bump commit** if the
  fan's range minted one (`needs.build-charts.outputs.bump_sha`), else the event
  sha — so a bump's own `charts/**` edits never re-enter the next detection
  (idempotence = loop guard; a re-fire of the same range reads `marker..sha`
  empty and mints nothing).
- Push is plain (never force). On refusal the job **classifies**:
  `merge-base --is-ancestor TARGET FETCH_HEAD` → "already advanced" calm-green;
  otherwise red naming both sides + owner verbs ("reset the marker ref to a
  reachable commit or delete it"). A red fan leaves the marker put, so the next
  fan's `marker..sha` re-covers the failed range by construction.
- The marker is **Forgejo-local**: `main-sync` mirrors `refs/heads/main` alone,
  so GitHub never receives it; the push uses the checkout's same-repo credential
  (no PAT).
- Builder-side resolver shape (all three, inline in build-charts / in the detect
  scripts for the other two): `git ls-remote origin refs/heads/ci/last-built`,
  sha-shape check, `git cat-file -e "<marker>^{commit}"` reachability pre-check —
  an orphaned marker (history rewrite) **stops the run red with owner verbs**,
  never silently downgrades to `before..sha`. Non-call events emit an empty
  `sha=` output key (missing-key vs empty distinction is load-bearing).
- **Live state (verified):** `refs/heads/ci/last-built` on `origin` ==
  `1d46d1c84` == `origin/main` tip — the last fan's bump commit. The next
  prod-main push's detection resolves verified-empty unless the range carries
  real `charts/` changes.

### 1.2 Fan shape (main-sync)

Job graph: `push-gh`, `push-dev`, `build-containers`, `build-charts`,
`push-coder-templates` (all `contains(prod)`; the three builders are CALLED via
`uses:`, `secrets: inherit`) → `advance-marker` (needs the three builders) →
`sync-fanout` (needs `push-gh` + the two release builders — **deliberately NOT**
`push-coder-templates`: a red coder leg blocks the aggregate/marker but not the
fleet release, D59). The sync-fanout job IS the webhook: it drives every
cluster's ArgoCD API directly with per-cluster bearer tokens
(`scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref $REF`;
`--check`/`--dry-run` flags; unset vault = warn-and-skip green by design, setup
errors go red, per-target runtime failures stay soft inside the script's
contract). The fleet's app sources read **GitHub**, so the fan fires only after
`push-gh` succeeded AND the builders came back green (ordering = the race
resolution, cf-139 R1 option (c)).

### 1.3 Chart change detection (build-charts) — and why a run can look like a full rebuild

Detection (the `changes` job, `fetch-depth: 0` — a shallow clone silently
empties the diff, the V-6-1 law): `git diff --name-only <marker> <sha> --
charts/` → second path segment, DNS-safe name + `Chart.yaml` present → JSON
array → `CHARTS`/`HAS_CHANGES`. Empty-set law: marker-anchored empty = one plain
info line ("verified empty"); empty `before..sha` on a real range =
`::warning::`; no-op push (`before == sha`) stays silent.

What is **NOT** touched-scoped, and what a "rebuilds everything" log impression
is really composed of:
- `test-build`: matrix **over the changed charts only** (patch-bump the version,
  `helm dependency update` + lint + package smoke).
- `bump` (single writer, 5-attempt FF loop, one clock stamp `Y.%-m` per run):
  before bumping it runs `helm dependency update` over **every**
  `charts/*/Chart.lock` (D47.1 full-tree lock self-heal — deliberate: one
  drifted lock outside the changed set would poison the `cr package charts/*/`
  publish legs). So every fire touches every chart's lock, even when one chart
  changed.
- `release` + `forgejo-publish` (both gated `has_changes == 'true'`): run
  `cr package charts/*/` — **all** charts get repackaged whenever any chart
  changed; uploads are de-duplicated (`--skip-existing` on GitHub,
  skip-if-in-index on the instance registry), so unchanged charts cost a
  package + an index read, not a republish.
- Churn driver: `renovate.yaml`'s daily pass (dev instance, 06:17 UTC) opens
  chart-dep PRs; merges land on main → next fan sees `charts/` changes →
  `has_changes=true`. Observed today: two bump commits within 31 minutes
  (`e5a816295` 03:57Z, `1d46d1c84` 04:28Z, both "bump coder forgejo-runner").
- Calendar bump law (owner R-Q1, D47.4): `N` derives from the tree + clock stamp
  (same-month N+1; below the month floor → `Y.M.1`; ahead of the clock → fail
  loud). The published index guards **only** skip-when-already-published; the
  walk is bounded 50.
- **Versions are CI-only** (Hard rule): this pipeline is the single chart-version
  authority (prod instance); never hand-bump. `version: Y.M.1` (current stamp)
  only on a brand-new chart.

### 1.4 `set -e` inventory and the DEBUG question

- `set -euo pipefail` opens **every** `run:` block: build-charts 15,
  build-containers 11, main-sync 7, coder-template-push 5, builder-bootstrap 3,
  renovate 2. Scripts: `forgejo-container-detect.sh` `set -eu` (:28),
  `coder-template-detect.sh` `set -eu` (:26), `coder-template-push.sh`
  `set -euo pipefail` (:16). `argocd-fanout.py` is python (no shell flags;
  prints a per-target line as each worker settles, `::warning::` when all
  targets skipped).
- **No `set -x`, no `DEBUG` variable anywhere** in `.forgejo/`, `scripts/*.sh`,
  or `scripts/*.py`. The user's "set -e makes logs chatty" hypothesis does not
  hold on the evidence: errexit emits nothing. The actually chatty sources:
  - `docker info` (full dump) + `env | grep ACTIONS_` + `docker buildx version`
    in the `diag` steps of `build-containers.yaml:231-243` and
    `builder-bootstrap.yaml:83-95` (both `|| true`-guarded);
  - `renovate` job: `LOG_LEVEL: info` + the full run's stdout;
  - `helm dependency update` chatter (index fetches) in the full-tree self-heal
    and per-chart smokes; `cr package`/`cr upload`/`cr index` output;
  - per-step `diag` echoes (`ROLE=…`, `event=…`, `run=…`) in main-sync,
    build-containers, coder-template-push, builder-bootstrap, renovate;
  - the detection steps' endpoint lines (`changed containers: … (event …
    before=… sha=… marker=…)`) and the empty-set info/warning lines — deliberate
    by design (a green nothing-built run must read differently from a silent
    empty).
- Where a DEBUG gate would go mechanically: a conditional at each script top,
  e.g. `if [ "${DEBUG:-false}" = "true" ]; then set -euo pipefail; fi` (unset
  → false, per the card). **Gotcha for the plan:** making *errexit* off by
  default weakens the failure gate in load-bearing steps (a refused `git push`
  in the bump loop, a failed `cr upload`, a failed `docker push` would no longer
  stop the script; the 5-attempt loop and the "staged-content guard" logic
  assume `set -euo pipefail`). The safer reading of the card is: keep `-e`
  always, gate the **verbose output** on DEBUG (the `docker info` line,
  `LOG_LEVEL`, optionally a `set -x` trace). Which reading to adopt is a plan
  decision — flag to the user in the batched round.

### 1.5 Where the "different approaches" diverge (the unification surface)

1. **Marker gate condition drift**: build-charts' resolver skips on
   `EVENT_NAME != push && != workflow_call` (the `push` arm is retired — legacy
   belt), while build-containers' and coder-template-push' resolvers skip on
   `EVENT_NAME != workflow_call` only. Behavior is equivalent today; the shapes
   differ.
2. **Guard polarity**: build-containers widens on unset ROLE (builder-class),
   everything else narrow/fail-safe — documented per-file, deliberate, but the
   one file that is the exception.
3. **Context naming**: build-charts reads the `github.*` event context (the
   Forgejo compatibility family), the others read `forgejo.*`; all use the
   `${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}` output idiom.
4. **Detection placement**: build-charts inlines its detection in the workflow;
   build-containers and coder-template-push delegate to `scripts/*.sh` detectors
   (which the test suites contract against).
5. **Registry walk**: build-containers = two-registry union walk;
   builder-bootstrap = single-registry walk (ruling OQ-1=B, accepted divergence);
   chart publish = GitHub `--skip-existing` + instance index-skip (different
   dedup mechanics per registry).
6. **Exit postures**: unset-vault warn-and-skip green (sync-fanout,
   coder-template-push script) vs red-on-setup-error — two halves, same doctrine;
   the marker resolver's red-on-orphan is shared.
7. **Concurrency**: `cancel-in-progress: false` (queue) on build-containers and
   coder-template-push (a cancelled matrix would publish half a set); bump job
   has an opportunistic `concurrency: group: release-bump-main` (best-effort
   only — the idempotent re-check loop is the real safety).

## 2. The `cf-55-feat-helm-builds-to-forgejo-rebuilt` branch

### 2.1 Existence and delta

- Exists **locally** (`git branch`), tip `dfc03d369`, forked from `00a5f3745`
  (which is on `main`). **6 commits ahead of `main`, unmerged:**
  `a51b18138` (probe verdict + owner C18 ruling), `ee36c0bde` (C18 delta, D66),
  `5cef0f6c6` (plan-delta records), `3d2159dca` (C18 contracts red-first),
  `67569ebfe` (C18 feat: Force+Replace sync-options + content-validation guard,
  review r1 APPROVED), `dfc03d369` (round-7 close, final-review ruling recorded).
- Code delta vs main: **`charts/forgejo-runner/values.yaml`** (the C18 chart
  change) + the C18 red-first contract additions in
  `tests/services/dev-forgejo-runner.sh` / `gpu-forgejo-runner.sh` (both files
  pre-exist on main from C16/C17) + plan-folder docs.
- The old pre-rebuild branch `cf-55-feat-helm-builds-to-forgejo` also exists
  locally, untouched as history (D31).

### 2.2 What the branch changes (C18, `charts/forgejo-runner/values.yaml`)

- Adds `argocd.argoproj.io/sync-options: "Force=true,Replace=true"` to the
  runner StatefulSet annotations: STS spec fields outside the update-exempt
  list (incl. `podManagementPolicy`) are **immutable for PATCH and PUT alike** —
  "the C17 rollout froze on exactly that"; the pair makes ArgoCD
  delete-and-recreate the STS on sync (pods bounce, PVCs persist, the guard
  re-attaches).
- Replaces the init `register` container's existence-only guard
  (`[ -f /data/config/config.yaml ] && exit 0`) with a **content-validation
  guard** (D66(5)): skip only a content-valid identity — file exists, parseable
  `url:` line, `uuid:` line that is not the `__RUNNER_UUID__` placeholder,
  non-empty token file. Kubelet auto-creates missing subPath targets, so the
  C17 PVCs carry **empty** `config.yaml` leaves; the existence-only guard read
  them as registered and booted an empty config — "the silent second failure
  class" (the one now observed live, §3). An invalid leaf re-registers (the
  write path replaces); a config-valid/token-lost half-write re-mints and the
  dead row goes stale-offline for owner-side deletion — cleanup cron STAYS OFF
  (D63).
- Background (C17, already on `main` via `944eaf8b9` + `226aecb86`): single
  registration token per instance, 10 self-registering runner pods
  (replicas 10 via `services/{dev,gpu}` slices, D57; capacity 1 per pod, chart
  default 1), per-ordinal retained PVCs (`data` 2Gi, `docker-data` 10Gi,
  `local-path`), `podManagementPolicy: Parallel`, init containers `dind` +
  `register`, main container `runner` (image
  `data.forgejo.org/forgejo/runner:13.2.0`), `reloader.stakater.com/auto`
  annotation, re-register mints an independent server-side row (G1, Forgejo
  v15.0.10). Stale-row runbook (D63): scale-down leaves rows; the client has no
  deregistration call; recovery is owner-side.

### 2.3 Plan folder state

`.agents/plans/2026/2026-11-cf-55-feat-helm-builds-to-forgejo/` (the folder on
`main`, i.e. pre-C18): `STATE.json` shows C13–C17 done (C17 wave-6 close,
2026-11-26); `DECISIONS.md` carries the decision spine — D31 (rebuild onto main
2026-11-16), D33 (first-fire failure: helm download ECONNRESET → the baked
`containers/forgejo-runner` job image with helm+cr baked in, D33/D47), D53/D54
(shared marker + advance topology, round-5), D57 (replicas 10 via slices,
2026-11-26), D62 (C17 design A′ + rejected alternatives), D63 (lifecycle
posture, cleanup cron off), D66 (C18 delta). `EXPLORE.md` (2026-11-10) and
`RESEARCH.md` (STORM, 37 sources) in the same folder ground the pre-move GitHub
topology (7 GitHub workflows) and Forgejo action-mirror availability (the
`dorny/paths-filter`/bump-action class is NOT in the default Forgejo mirror —
why detection moved to pure git diff). `RESEARCH.md` TL;DR item 4 is a standing
warning: Forgejo auto-token pushes do not re-trigger the repo's own workflows
(bump-back → sync interaction).

## 3. Runner state on dev and gpu (observed 2026-11-27 ~05:30Z, not fixed)

### 3.1 MCP surface used

- Servers: `readonly-dev-kubernetes`, `readonly-gpu-kubernetes` (13 tools each;
  read-only surface: `namespaces_list`, `pods_list`, `pods_get`, `pods_log`,
  `pods_top`, `nodes_log`, `nodes_top`, `events_list` — **no generic-CR/STS
  tools**, so the live chart revision is not directly observable from here).
- Namespace on both clusters: **`default`**.
  - dev: StatefulSet `dev-forgejo-runner-dev` (release `forgejo-runner-dev` via
    `services/dev/prod/values.yaml` `charts:`, dials in-cluster
    `dev-forgejo-http:3000`); the forgejo server pod `dev-forgejo-*` and
    `pg-forgejo-1` are Running 1/1 (17d/32d).
  - gpu: StatefulSet `gpu-forgejo-runner-gpu` (release `forgejo-runner-gpu` via
    `services/gpu/prod/values.yaml`, `chart: forgejo-runner`, dials the infra
    instance over HTTPS at `https://git.spencerslab.com` — gpu has no
    in-cluster Forgejo).

### 3.2 Observed failure (identical failure signature on both clusters)

- **dev** (single node `dev`): `dev-forgejo-runner-dev-0,1,2,3,9`
  CrashLoopBackOff / Init:CrashLoopBackOff (restarts 11–14, pod age ~39m);
  `dev-forgejo-runner-dev-4..8` **Pending** (`FailedScheduling`: "0/1 nodes are
  available: 1 Insufficient cpu, 1 Insufficient memory" — node capacity, the
  C17/D62 known class, "node CPU full"). **0/10 ready.**
- **gpu** (node `gpu`): all 10 `gpu-forgejo-runner-gpu-0..9` CrashLoopBackOff /
  Error (restarts 10–11, pod age ~32m). **0/10 ready.**
- Main `runner` container (previous-terminated logs, exit code 1, both clusters):
  ```
  time="2026-11-27T05:30:2xZ" level=info msg="Starting runner daemon"
  Error: runner: 0 server connections configured, terminating
  ```
  i.e. the act runner starts with an **empty `config.yaml`** (no `server:`
  entry). Init containers `dind` + `register` complete (`Initialized: True`);
  the `register` init "has not logged any message yet" — consistent with the
  C17 existence-only guard silently skipping an empty-but-present file.
- Events (gpu): the usual `BackOff`/`Killing` cycle; image
  `data.forgejo.org/forgejo/runner:13.2.0` already present on the node.

### 3.3 The breakage chain (grounded inference, matches C18's own comments)

1. C17 (on `main`, 2026-11-26) changed the STS spec (`podManagementPolicy:
   Parallel`, VCTs, reloader annotation) → the STS rollout froze on the
   immutable-spec validator (the exact class C18's annotation comment names).
2. Pods were (re)created around 04:5xZ today — after the two CI chart bumps
   (`e5a816295`/`1d46d1c84`, 03:57Z/04:28Z, `charts/forgejo-runner/Chart.yaml`
   in both) — ArgoCD applying the bumped chart revision.
3. The PVCs carry **empty** `/data/config/config.yaml` leaves (kubelet
   auto-creates subPath targets); the C17 existence-only guard treated them as
   registered and skipped the re-registration POST.
4. `runner` boots with zero configured server connections and terminates →
   crash loop, 0/10 on both clusters.
- The C18 fix on the branch (Force+Replace recreate + content-validation guard)
  is the designed remedy and is **unmerged**; nothing in the live tree fixes
  this. Whether the C18 chart has already been applied out-of-band to the
  clusters is **not observable from this session's read-only surface** (no
  STS/ArgoApp MCP tools; `register` init silence is consistent with both the
  C17 guard and a failed C18 init) — open question §6.
- Secondary, dev-only: 5/10 pods unschedulable on the single dev node
  (Insufficient cpu/memory) — a capacity problem independent of the config
  failure (the C17/D62 "node CPU full" class that froze gpu at 3/10).

## 4. Forgejo instance topology

- **`origin` = `https://git.spencerslab.com`** — the **prod** Forgejo on the
  **infra** cluster (in-cluster: `infra-forgejo-http:3000`, `git` is the
  canonical DOMAIN/ROOT_URL host per `services/infra/prod/values.yaml`).
  `ROLE=prod` repo var. Source of truth; the workflows' prod lanes run here;
  org-level `ARGOCD_SYNC_TOKENS` secret.
- **`dev` = `ssh://git@git.scifi.farm:22222/CuratedForest/SpencersLab.git`** —
  the **dev** Forgejo on the **dev** cluster (in-cluster
  `dev-forgejo-http:3000`; git-over-SSH exposed at port 22222 via the
  Gateway API `tcproutes` CRD, `gitSshPort: 22222` in
  `services/dev/prod/values.yaml`). `ROLE=dev` (a non-prod value). Receives the
  main-sync `push-dev` fan.
- **`upstream` = `git@github.com:OwnYourIO/SpencersLab.git`** — GitHub mirror
  (`push-gh` fan target) and the consumer-contract host: the gh-pages index
  (`https://ownyourio.github.io/SpencersLab/index.yaml` — the published-index
  guard in the bump leg + the `renovate: datasource=helm` annotations) and the
  fleet's ArgoCD app sources.
- **`spencerslab-dev` = `https://git.scifi.farm/CuratedForest/SpencersLab-Dev.git`**
  — a dev-fork repo; **`proxy-backup`** — the separate Proxy-Backup repo (not
  part of this thread).
- Both Forgejo instances host the same repo (main-sync mirrors `main` to both);
  the `ci/last-built` marker is Forgejo-local (never reaches GitHub).
- Repo config relevant to the thread: `renovate.json` (root;
  `config:recommended`, `timezone: America/Denver`, `gitIgnoredAuthors:
  [bot-and-reviewed@spencerslab.com]`, `constraints.helm 3.22.1`, customManagers
  for chart/service `image:` lines + `k3s-version.yaml`); `.forgejo/` contains
  **only** `workflows/` (no repo-level Forgejo settings file — repo vars/secrets
  like `ROLE`, `PUSH_URL_*`, `PUSH_TOKEN_*`, `FORGE_PUSH_TOKEN`,
  `RENOVATE_TOKEN`, `RENOVATE_GIT_AUTHOR`, `CODER_URL`, `CODER_SESSION_TOKEN`
  are instance-side, documented in-file only). Forgejo version pin: 15.0.10+
  (cf-55 RESEARCH).
- The runner job image `containers/forgejo-runner` (helm + cr baked, D33;
  per-release job-image labels, cf-6) is minted by `build-containers.yaml`
  (automatic) and `builder-bootstrap.yaml` (dispatch recovery lane,
  single-registry).

## 5. Notes for the planner

### 5.1 Existing per-chart/per-container change-detection mechanisms

- Charts: `build-charts.yaml` `changes` job — marker-anchored `git diff
  marker..sha -- charts/` (DNS-safe + `Chart.yaml` filter), payload fallbacks
  (`before..sha`, first-push `HEAD^`, fatal empty before), empty-set law
  (§1.3). The retired GitHub shape was `dorny/paths-filter` over `charts/**`
  (cf-55 EXPLORE §1a) — the pure-git marker diff is its replacement.
- Containers: `scripts/forgejo-container-detect.sh` (marker-first decision tree,
  PR `merge-base..head`, dispatch manual list, tip-only announces) — contract
  covered by `tests/services/forgejo-build-containers.sh`.
- Templates: `scripts/coder-template-detect.sh` (same marker-aware shape,
  `charts/coder/coder-templates/` + `main.tf`, `cut -d/ -f4`).
- The shared marker + single-writer aggregate is the cross-domain coupling: a
  red builder holds the marker, the next fan re-covers.
- Validation surface for chart work (no unit-test suite in this repo):
  `helm lint charts/<name>` + `helm template charts/<name>`, the service-trio
  grep checks, `OVERRIDE_VIA_CUSTOM_VALUES` 1:1 matching, plus the contract
  suites under `tests/services/` (`forgejo-main-sync.sh`, `forgejo-build-charts.sh`,
  `forgejo-build-containers.sh`, `forgejo-builder-bootstrap.sh`,
  `forgejo-renovate.sh`, `forgejo-packages.sh`, `forgejo-ci-surface.sh`,
  `forgejo-lfs.sh`, `forgejo-ssh-audit-trail.sh`, `dev-forgejo-runner.sh`,
  `gpu-forgejo-runner.sh`). `PATH=$HOME/.local/bin:$PATH` before helm runs
  (AGENTS.md); `helm` at `~/.local/bin`; pytest per-directory.
- `docker build` ACs are CI-primary (no daemon in agent sessions): the forge's
  `build-containers.yaml` on the pushed branch; a `docker build => no-daemon,
  CI-deferred` line is the designed gate shape (ruled 2026-10-28, cf-77).

### 5.2 Standing constraints for the unification work

- **Never hand-bump versions or image tags** (Hard rule): chart `Chart.yaml`
  bumps are minted by `build-charts.yaml` alone (prod instance, calendar law,
  FF-only); container tags by `build-containers.yaml` (+ the bootstrap lane);
  brand-new charts get `version: Y.M.1` only.
- **ArgoCD applies everything — never `kubectl apply` from this repo.** The
  runner chart reaches the clusters via the published chart (helm repo) +
  appset (prod stage `targetRevision: main` — `services/*/prod/templates/
  appset.yaml`); instance-side repo vars/secrets are owner-minted (the in-file
  "runbook" placements).
- ROLE guard shape law: `contains()` membership on the repo-scoped `ROLE` var;
  per-file polarity (widening only for build-containers, documented); no
  instance-URL guards; substring caveat for future role words.
- The three builders' detection is intentionally duplicated in three shapes
  (inline vs two scripts); any "unification" change must keep the
  `fetch-depth: 0` law, the `${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}` idiom, the
  marker-orphan red-with-owner-verbs law, and the per-file guard polarity —
  or explicitly re-rule them.
- Forgejo auto-token pushes do NOT re-trigger the repo's own workflows (cf-55
  RESEARCH TL;DR 4) — the bump-back → sync coupling is structural.
- Prior decision context: cf-6 (containers move to Forgejo, dual registries,
  `ROLE` law), cf-119 (main-sync landing + UA3 ROLE vars), cf-55 (the chart
  move, D33 bake, D53/D54 marker, D57 scale, D62/D63/D66 runner), cf-56/AD-56
  (coder-template fan member, shared-marker read-only), cf-77 (no-daemon
  docker-build gate shape; the empty-`repository:` subchart `helm repo add`
  gotcha in the repo-add loop), cf-97 (runner securityContext `runAsGroup`;
  deferred: runner `13.2.0→13.2.1` pin + stale `appVersion` — a separate dep
  ticket), cf-135 (renovate move to Forgejo).
- The live runner breakage (§3) is the most urgent open state: C18 on the
  rebuilt branch is the designed fix but is unmerged; landing it (or the
  unification work that supersedes it) is a plan-stage + owner-leg decision
  (merge/PR is user-owned; the runner needs an STS recreate, which ArgoCD does
  once the C18 chart is live).

## 6. Open questions (for the batched round)

1. Which reading of the `set -e`/DEBUG ask: gate **errexit itself** on
   `DEBUG=true` (weakens failure semantics in bump/push/publish steps —
   `set -euo pipefail` at 43 sites + 3 scripts), or keep `-e` always and gate
   only the **verbose output** (the `docker info` diag line, renovate
   `LOG_LEVEL`, optionally a `set -x` trace)? The card's wording is the former;
   the chatty-log diagnosis points at the latter.
2. "Only build the touched charts": detection is already touched-only. Confirm
   the intended scope of the fix: narrow the `cr package charts/*/` publish leg
   to the changed set, the full-tree `helm dependency update` lock self-heal
   (D47.1 deliberately full-tree), both, or leave the mechanics and instead
   reduce renovate chart-dep churn? (Each narrowing has a named reason for
   being full-tree in DECISIONS — D47.1: one drifted lock outside the changed
   set poisons the publish legs.)
3. Was the C18 chart already applied out-of-band to the dev/gpu clusters (the
   `register` init's no-log state is consistent with both C17-skip and a
   failed C18 init)? Needs an owner-side `kubectl`/ArgoCD check (no STS/ArgoApp
   tool in the read-only MCP surface): `kubectl -n default get sts
   dev-forgejo-runner-dev -o yaml | grep -A3 sync-options` (and the gpu
   counterpart) + `argocd app get` source revision.
4. The dev node capacity (5/10 runner pods unschedulable, Insufficient
   cpu/memory on the single dev node) — in scope for this ticket (the card
   names Services dev+gpu+infra), or a separate capacity ticket?
5. The local checkout's `main` is 2 commits behind `origin/main` (the two
   CI bump commits, §0). This in-place run works on the local tree — should
   the run (or the owner) first fast-forward local `main` to `origin/main`
   before planning chunks, so the work lands on the true tip?

## Appendix — probes run (all read-only)

- repo: `git status/branch/log/rev-parse/diff/show/fetch(ci/last-built, main)/ls-remote`,
  `.forgejo/workflows/*.yaml` (all six, full read), `scripts/{forgejo-container-detect,coder-template-detect,coder-template-push}.sh` + `argocd-fanout.py`
  (set -e / DEBUG greps), `renovate.json`, `services/{dev,gpu,infra}/prod/values.yaml`
  + `services/dev/prod/templates/appset.yaml`, `charts/forgejo-runner/values.yaml`
  (main vs branch diff), `.agents/plans/2026/2026-11-cf-55-…/` (STATE/DECISIONS/EXPLORE/RESEARCH).
- MCP `readonly-dev-kubernetes` / `readonly-gpu-kubernetes`: `namespaces_list`,
  `pods_list(namespace=default)`, `pods_get` (runner STS pod, container status),
  `pods_log` (runner previous-terminated + register init), `events_list(default)`.
