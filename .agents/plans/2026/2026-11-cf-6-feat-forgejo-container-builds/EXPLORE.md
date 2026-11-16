# EXPLORE — cf-6 Forgejo container builds (card 6, "Build and deploy containers")

Written by `agent-explore` 2026-11-09 (workspace clock). Read-only grounding for the
planner; DECISIONS.md rulings (model routing, pre-existing reds) are taken as given,
not re-decided. Facts carry their evidence. Companion ticket: cf-119's EXPLORE.md
(`.agents/plans/2026/2026-11-cf-119-feat-forgejo-push-main/EXPLORE.md`, 2026-11-06)
is still accurate on most Forgejo surface — this file updates it where state moved
(§2: its "no `.forgejo/`" finding is now STALE) and adds the container-build legs.

Card request (verbatim): Forgejo pipeline that builds+deploys containers like the
existing `.github` action (changed-folder detection, build-only-what-changed);
main → `latest` + a tag in `yy.mm.1++` shape; PR branches build with a tag of
branch-name + build hash. Checklist: Services=dev, Type=feat.

## 1. GitHub precedent — `.github/workflows/docker-build.yaml` (read in full)

The file the card says to replicate (154 lines). Behaviors a Forgejo port must match
or consciously drop:

| Concern | GitHub behavior (evidence: file lines) |
|---|---|
| Triggers | `push` to `main`/`dev` paths `containers/**`; `pull_request` to `main`/`dev` same paths; `workflow_dispatch` with a free-text `containers` input for manual rebuilds (L8–29) |
| Change detection | `detect-changes` job: `fetch-depth: 0` checkout, then raw `git diff --name-only BASE HEAD -- containers/` — base = `github.event.before` for pushes (all-zero → `HEAD^` fallback), `base.sha..head.sha` for PRs; NOT `dorny/paths-filter` or `tj-actions/changed-files` (L46–85) |
| Name gate | `cut -d'/' -f2` → `grep -E '^[a-z0-9]+(-[a-z0-9]+)*$'` (strict DNS-safe) → keep only names with `containers/<n>/Dockerfile`; emits a JSON array output (L74–84) |
| Build | `build-and-push` job, `strategy.matrix` `fromJson` of that array, `fail-fast: false`; `docker/setup-buildx-action@v4` + `docker/build-push-action@v7` with `cache-from/to: type=gha,mode=max` (L87–154) |
| Tags | `Compute tags` step: `v<github.run_number>` (immutable, monotonic) + branch name with `/`→`-`; `docker/metadata-action@v6` composes labels; image `ghcr.io/ownyourio/<container>` (`REGISTRY` env + `github.repository_owner`) |
| Push policy | PR runs NEVER push (`push: ${{ github.event_name != 'pull_request' }}`, login step skipped) — comment: a PR branch named `dev` must not clobber the rolling `:dev` (L6–7, L107–114, L148–150) |
| Auth | `docker/login-action@v4` with `github.actor` + `secrets.GITHUB_TOKEN`, job `permissions: packages: write` (L96–114) |

Port-must-replicate list: changed-dirs detection (Forgejo also supports native
`on.push.paths:` §3, but per-container matrix still needs the diff job), DNS-safe +
Dockerfile gate, matrix + no-fail-fast, PR-never-overwrites-rolling-tags discipline,
manual-dispatch rebuild escape hatch. Port-cannot-copy: `GITHUB_TOKEN` (no
per-run GitHub token exists on Forgejo), `type=gha` cache backend (see §7 caveats),
`docker/*` actions resolution (see §7).

Also relevant: origin (GitHub) currently has **only the `main` branch**
(`git ls-remote --heads origin` → `refs/heads/main` alone) — the workflow's `dev`
trigger is currently dead surface, and the forge's `main` is what cf-119's sync keeps
even. No `dev` branch exists to build on the forge either.

## 2. `containers/` inventory (13 dirs) + name gate + renovate pins

All 13 directories carry a `Dockerfile` (shell listing 2026-11-09):
`brother-ptouch-automation, coder-workspace, forgejo-host-runner, gpt-researcher,
gpt-researcher-frontend, music-assistant, okd-enketo, renovate-mcp, snapcast, strata,
traefik-mqtt-allowlist, vllm-rocm, wekan-mcp`. All names already pass the DNS-safe
regex. `gpt-researcher-frontend` is the only hyphen-compound case exercising the gate
besides `traefik-mqtt-allowlist`/`forgejo-host-runner`.

Renovate `ARG` pins to keep intact (`grep -n "renovate:" containers/*/Dockerfile`):
brother-ptouch-automation (github-tags), coder-workspace (node/golang/helm/k8s/uv/
forgejo-cli/opencode/openchamber), forgejo-host-runner (docker runner + hugo/go/
netlify-cli ARG pins with build-time digest checks), gpt-researcher(+frontend)
(git-refs), okd-enketo (github-tags), renovate-mcp (2 npm ARGs), vllm-rocm (git-refs).
Repo rule (AGENTS.md): these comments bind Renovate — a ported workflow must not
rewrite Dockerfiles that carry them. `music-assistant`, `snapcast`, `strata`,
`traefik-mqtt-allowlist`, `wekan-mcp` carry no renovate pin.

## 3. Forgejo surface — instances, repo, runner, and what is LIVE now (probed 2026-11-09)

Repo identity on the forges: **`CuratedForest/SpencersLab` on both instances** — the
same repo path everywhere, so instance-level job guards are mandatory (cf-119 EXPLORE
§2/§7; live confirmation: runner log line `task 15 repo is CuratedForest/SpencersLab
https://git.spencerslab.com`, MCP `pods_log` gpu runner 2026-11-09T00:36Z).

`.forgejo/workflows/` **exists on main now** — cf-119's
`.forgejo/workflows/main-sync.yaml` + `tests/services/forgejo-main-sync.sh` are merged
(`git log --oneline main -- .forgejo` → `ea9e97f64`; file read in this worktree at
`cccedad84`). Consequences for cf-6:
- The GitHub-workflows **fallback is already flipped**: Forgejo no longer treats the
  seven `.github/workflows/*.yaml` as candidates on either instance (cf-119 EXPLORE §2,
  docs "absence of `.forgejo/workflows`" rule).
- **A live precedent workflow file exists to imitate**: `main-sync.yaml` shows the
  house style — `startsWith(forgejo.server_url, '<instance>')` job guards,
  `runs-on: ubuntu-24.04`, `actions/checkout@v6` with `fetch-depth: 0`, diag step
  echoing `forgejo.server_url`, `set -euo pipefail` in every run block, secret
  references confined to the job that needs them.
- **Actions execute live on the infra instance**: the gpu runner log shows tasks 15
  and 16 dispatched ~2026-11-09T00:36Z with job `push-main` (run outcome not readable
  from the workspace — the forges are unreachable from here, cf-119 §3; still true:
  remotes `dev`/`prod` refused, only `origin` answers).

Live topology (readonly k8s MCP probes, `default` ns, 2026-11-09 ~01:50Z):

| Surface | State | Evidence |
|---|---|---|
| `infra-forgejo` (infra cluster, canonical `git.spencerslab.com`, Forgejo 15.0.10 / chart forgejo-17.3.1) | **Running 1/1** | `readonly-infra-kubernetes` pods list |
| `gpu-forgejo-runner-gpu-0` (gpu cluster, dials `https://git.spencerslab.com`) | **Running 2/2** (dind + runner); tasks seen today | `readonly-gpu-kubernetes` pods list + runner log tail |
| `dev-forgejo` (dev cluster, `git.scifi.farm`) | **DOWN — CrashLoopBackOff**, 379 restarts, 35 h; container `forgejo` dies at boot | `readonly-dev-kubernetes` pods list |
| `dev-forgejo-runner-dev-0` | **CrashLoopBackOff 1/2**, 411 restarts (downstream of the server) | same pods list |

Dev crash cause (log tail, not diagnosed — separate workstream): LFS init against
the **public** S3 route times out — `Creating Minio storage at s3.spencerslab.com:
git-lfs ... context deadline exceeded`. Note the drift: `custom-values/dev/prod-values.yaml`
today declares dev LFS **local** (no `[lfs]` section), while the running pod boots
`initLFS type: minio` — stale app.ini on the PVC or a slice mismatch; owner/ops leg,
not cf-6's. Until dev recovers, **any cf-6 workflow validates on the infra instance
only** (same posture cf-119 OQ-4 recorded).

Topology facts a plan needs (chart/values evidence):
- Runner deployment `charts/forgejo-runner`: docker backend = privileged DinD
  sidecar (`docker:29.9.2-dind`) + `data.forgejo.org/forgejo/runner:13.2.0` pod,
  jobs themselves unprivileged (`container.privileged: false`) with `DOCKER_HOST`
  to the in-pod socket; runner config renders `cache: enabled: true`; **
  `capacity: 1`** (one concurrent job per runner record — matrix fans out queue up);
  job timeout 30 m; VCT caches 2 Gi workdir + 10 Gi docker-data (`values.yaml` +
  `templates/secret-runner.yaml` read in full).
- Advertised labels (both releases, chart default): `ubuntu-latest`, `ubuntu-24.04`,
  `ubuntu-22.04`, `docker`, `node22` → `ghcr.io/catthehacker/ubuntu:act-24.04`/
  `act-22.04`. `ubuntu-26.04`-style GitHub labels route nowhere
  (`charts/forgejo-runner/values.yaml:107–112`; cf-119 §2).
- A **host backend** exists in the chart (`runner.backend: host`,
  `ghcr.io/ownyourio/forgejo-host-runner` image, labels must override to a
  non-act set) but **no host release is deployed** — gpu's slice sets only
  `runner.url` (`services/gpu/prod/values.yaml:271–273`), no `backend: host` or
  `cf-host` label slice anywhere (`grep backend|cf-host services/ custom-values/`
  empty). cf-6 should plan against the docker/DinD shape.
- Registration is scope-agnostic (instance/org/repo record in the Admin UI, chart
  consumes a (uuid, token) Bitwarden pair); scaling = MORE runner records, never
  replicas (`charts/forgejo-runner/values.yaml:1–68`, NOTES.txt via cf-119 §5).
- k3s gotcha: runner ≥12.5 intermittently fails action clones on k3s
  (forgejo/runner#1779, MTU/overlay) — workflow authors' workaround `network: host`
  per job, dockerd mitigation `--mtu 1450` (`charts/forgejo-runner/values.yaml:70–75`).
- Actions are enabled by default on this Forgejo line — no `[actions]`/`ENABLE_ACTIONS`
  key exists anywhere in the repo config (`grep ENABLE_ACTIONS|ACTIONS_|[actions]`
  across charts/services/custom-values → none), and live tasks prove it (cf-97
  RESEARCH:23 "Actions enabled by default" + today's task log).

Instance topology recap (values evidence): dev instance = `services/dev/prod/values.yaml`
(`forgejo:` app, `ingress.subdomains.git → dev-forgejo-http:3000`, runner dial
`http://dev-forgejo-http:3000`); infra instance = `services/infra/prod/values.yaml`
(`git` + `forgejo` hosts → `infra-forgejo-http`, canonical `git.spencerslab.com` —
the `forgejo.` alias is banned for machine use, cf-104 R3); gpu hosts infra's runner
(`forgejo-runner-gpu` → `https://git.spencerslab.com`). SSH for git over :22222.

## 4. Forgejo Actions syntax facts (pinned upstream: v15.0 LTS reference)

Fetched `codeberg.org/forgejo/docs/raw/branch/v15.0/docs/user/actions/reference.md`
(matching the 15.0.10 instances; cf-119 verified the same doc line earlier):

- Contexts: `forgejo` (aliases `forge`, `github`); `FORGEJO_*` env vars mirror the
  context and each also exists as `GITHUB_*`. Fields that matter here: `run_number`
  ("a unique id for the current workflow run **in the repository**" — monotonic per
  repo since creation, NOT per month; live example `run_number: "9384"`), `run_id`
  (instance-wide), `run_attempt`, `sha`, `ref`, `ref_name`, `head_ref`/`base_ref`
  (PR only), `event_name`, `server_url` (the guard key), `event` (full webhook
  payload JSON — `forgejo.event.pull_request` available for PR metadata).
- Triggers: `on.push` supports `branches:` AND `paths:` (`paths` per-container
  filtering can happen at trigger level, but the matrix still needs a diff job);
  `on.pull_request` (`opened/synchronize/reopened` defaults);
  `on.workflow_dispatch.inputs` incl. `choice`/`string`; `on.schedule` with optional
  `timezone:`.
- Matrix: `strategy.matrix` + `fromJson(needs.<job>.outputs…)` documented pattern;
  outputs via `$FORGEJO_OUTPUT`.
- **Concurrency default is a trap for build pipelines**: with no `concurrency:` key,
  a new push/PR-synchronize **cancels any in-flight run of the same workflow** —
  matrix builds get killed (cf. docker-build.yaml's dispatch comment about cancelled
  builds). For release-tag pushing set `concurrency: { cancel-in-progress: false }`
  or a group.
- PR-from-fork rule: secrets empty + token read-only for forked heads — irrelevant
  while PRs stay same-repo, worth one plan note.
- Known divergences (cf-119 §2 + reference): job-level `permissions:` ignored (no
  GITHUB_TOKEN permission model at all); step-level `continue-on-error` works;
  `jobs.<job_id>.container.image` supported (once pulled, images never update on the
  runner — pin by digest); actions resolve against `DEFAULT_ACTIONS_URL` =
  `https://data.forgejo.org` (runner log proves it), fully-qualified `uses:` URLs
  recommended, commit-SHA pinning advised (CVE-2025-30066 tag-compromise note).

## 5. Registry target and credentials

- **Target stays `ghcr.io/ownyourio`**: consumers are 12 image refs across
  charts/services (`grep -rl ghcr.io/ownyourio charts services` → 13 files; images
  `coder-workspace, forgejo-host-runner, gpt-researcher(-frontend),
  llama-swap-autogen, okd-enketo, renovate-mcp, snapcast, strata,
  traefik-mqtt-allowlist, vllm-rocm, wekan-mcp`). No cluster registry exists — no
  harbor/gitea-packages/registry chart or values anywhere (`grep harbor|registry|
  packages` over charts/ — only false positives). Forgejo's Packages feature is a
  possible alternative but would migrate every consumer, need pull secrets, and
  break the Renovate docker datasource wiring for zero card gain — record, don't
  pick.
- Runner egress to **ghcr.io is proven** (every job container image IS pulled from
  ghcr by the dind daemon — the labels prove it works daily, 2/2 pod).
- Push auth: a **GitHub PAT with `write:packages`** (ghcr has no per-run token for
  foreign forges; the `ownyourio` namespace belongs to the GitHub account; existing
  images pull anonymously = public). Delivery pattern is the established one:
  **Bitwarden item + human-entered Actions secret on the infra instance** (cf-119
  DECISIONS "secret-key names" + NOTES.txt one-time-user-action precedent). The
  repo's ExternalSecret+Bitwarden hard rule binds K8s objects, NOT instance-DB
  Actions secrets — the workflow file itself must contain no secret material.
  Existing related vault items (existence evidence, `custom-values/dev/prod-values.yaml`):
  `forgejo-token`, `github-pat` (dev-github item) — a NEW dedicated ghcr-PAT item is
  cleaner; minting it is a human leg (cf-119 UA pattern).

## 6. Tag scheme — "main → latest + `yy.mm.1++`", PR → branch + build hash

Options for the incrementing third component (grounded inputs: `run_number` semantics
§4, ghcr anonymous tag-list recipe from skills/container-creation, `git rev-list`):

1. `yy.mm.<run_number>` — one context lookup (`forgejo.run_number`), collision-free
   forever, monotonic. But it is the repo-wide counter (~16 today on infra, every
   workflow run of every kind bumps it), so it is sparse, not a "build #3 this
   month"; re-runs increment rather than collide. Simplest port.
2. Registry-derived `yy.mm.<N>` — query the image's tag list with the anonymous pull
   token (`GET https://ghcr.io/token?scope=repository:ownyourio/<name>:pull` +
   `GET .../tags/list` — the documented recipe in `skills/container-creation/SKILL.md`
   "pin by default"), pick max within `yy.mm.*`, +1. True per-image monthly sequence,
   the literal card reading. Costs: per-image API work, pagination, and **re-runs
   collide** (same computed tag → either silently overwrite an "immutable" tag or
   fail). Needs `concurrency cancel-in-progress:false` + serialization to be safe;
   with capacity-1 runners that's mostly given.
3. `git rev-list --count --since=<YYYY-MM-01> HEAD` — deterministic per-commit
   monthly commit count; stable across re-runs of the same commit (which then
   RE-tag = overwrite on re-run), resets naturally each month; can tie (two
   different containers pushed same-day share a number) — acceptable if tags are
   per-image, since each image gets one tag per commit anyway.
4. Timestamp (`yy.mm.dd.HHMM`) — collision-safe but not the requested `1++` shape;
   record only as fallback.

**The Renovate ordering hazard (load-bearing).** Consumers pin `:v<run_number>`
(skills/container-creation "change loop": merge → workflow pushes → **Renovate** bumps
the pin → ArgoCD syncs) and Renovate's docker datasource picks the **highest tag by
semver** (v prefix stripped). `26.11.1` parses as semver 26.11.1 — **numerically lower
than the legacy `v84`/`v162` pins** (major 26 < 84), so from any pinned chart the
calendar line never looks "newer" and the loop stalls; worse, from a 26.x pin the old
`v162` looks NEWER and Renovate would propose downgrading back. Mitigations with
in-repo precedent (renovate.json `kubernetes-mcp-server` floor, `llama-swap`
`versioning: regex:` entries): a `packageRule` per ownyourio image (or one for the
org) with an `allowedVersions`/`versioning` restricting to the calendar line, plus a
one-time human/dev pin-bump onto the first calendar tag at cutover. This must be a
named plan decision + its own validation, not an afterthought.

Other scheme facts for the planner:
- `:latest` is currently a **legacy** tag ("a real tag that on some images is a legacy
  pre-tag-scheme publish", skills/container-creation) — the card's "main → latest"
  makes `:latest` live and mutable going forward; that is NEW behavior (GitHub today
  pushes `:v<run>` + `:<branch>` only).
- The rolling `:main` tag IS a documented cluster contract (`:main` + `pullPolicy:
  Always` is the sanctioned reference for brand-new containers; AGENTS.md hard rule
  + skill). Whether the Forgejo pipeline keeps pushing `:main` (in addition to
  `:latest`) or the card's `latest` replaces it is an open decision (OQ-4).
- PR tag shape `branch-name + build hash`: `${{ forgejo.head_ref }}` (PR-only) with
  the established `/`→`-` sanitize (docker-build.yaml L126–132) + `forgejo.sha` short
  form (`git rev-parse --short` — no `${{ ... }}` truncation helper in expressions
  beyond what actions give; a run-step computation is the house way). Note the card
  says PR builds should be TAGGED — unlike the GitHub precedent which never pushes PR
  builds (its rationale: PR branches must not clobber rolling tags; distinct PR-only
  tag names sidestep that, but a push-per-PR is a deliberate departure to confirm —
  OQ-5).

## 7. Build mechanics on the Forgejo runner (what ports cleanly)

- DinD works for docker builds BY DESIGN: the dind sidecar is privileged, jobs get
  the socket (supplementalGroup 2375 ruling), chart header documents the socket +
  gid contract (`charts/forgejo-runner/values.yaml:140–275`).
- `runs-on: ubuntu-latest|ubuntu-24.04|docker|node22` → act containers on DinD.
  `type=gha` buildx cache: the runner config enables `cache:` (an Actions-cache
  server), so `actions/cache` works (the forgejo-host-runner image even ships zstd
  "actions cache" for it, Dockerfile L6), and buildx's gha backend rides the same
  GitHub-compatible cache env (`ACTIONS_CACHE_URL`/token) — **but this exact pairing
  is unverified**; first-fire smoke step + fallback to `type=registry` cache under
  `ghcr.io/ownyourio/<name>-cache` or dropping cache. Flagged for research.
- The act images (nektos/act "medium" images) are expected to carry docker CLI +
  buildx, but the pinned inventory page could not be fetched through the workspace
  proxy (403/404 on raw + moved blob paths) — treat "buildx available in act image"
  as UNVERIFIED and put a `docker buildx version || docker version` diag step in the
  first smoke run (house pattern: main-sync's diag step; same posture as the chart's
  "verify `git lfs version` inside a job" note, secret-runner.yaml L123–127).
- Action sourcing: `actions/checkout@v6` resolves via `data.forgejo.org` (proven by
  the live runner log). The `docker/setup-buildx-action`, `docker/login-action`,
  `docker/metadata-action`, `docker/build-push-action` set is a GitHub-org set —
  resolution on data.forgejo.org is not guaranteed; options: fully-qualified
  `uses: https://github.com/docker/...` (needs runner egress to github.com —
  main-sync pushes there, outcome unverified) or **skip the actions entirely**:
  `docker login` + `docker buildx build --push` shell steps (or even plain
  `docker build`+`push`), which is the least-movable-parts port. The `aislop`
  note from cf-119 applies: keep workflow comments terse/why-only.
- Runner serialization: `capacity: 1` + one infra runner pod → a 5-container push
  builds serially, 30-min job timeout each; fine for correctness, worth stating in
  the plan (scaling = extra runner records, per chart header).

## 8. "Deploy" meaning — publishing IS the deploy

Grounded loop (skills/container-creation "Build pipeline" + "change loop", renovate.json
customManagers incl. the `image:`-line docker regex at lines 12–24, ArgoCD-everywhere
rule in AGENTS.md): merge → CI builds+pushes tags to ghcr → **Renovate opens the
pin-bump PR** → merge → chart-releaser/ArgoCD syncs → cluster pulls the pinned tag.
No ArgoCD Image Updater is wired for containers (grep surfaced none). So the pipeline
does NOT perform a deploy step: it publishes tags into the existing consume loop.
The deploy leg stays Renovate + ArgoCD + human PR merge — unless the tag-scheme change
(§6 hazard) forces a one-time migration PR. The card's "deploy" is ambiguous enough to
state this explicitly as OQ-6 (likely resolved: build+push is the whole job).

## 9. Validation surface (this workspace)

- No docker daemon: `/usr/bin/docker` CLI exists but `docker info` fails —
  `docker build => no-daemon, CI-deferred` is the designed passing shape (repo rule
  cf-77, AGENTS.md "Pipeline specifics"). On the pushed branch the live Forgejo run
  itself is the authoritative build test (and post-merge on infra, since GitHub will
  no longer run these files once the workflow is forge-only — see OQ-1).
- Local: `python3` + pyyaml YAML parse (cf-119 precedent); `bash -n` for any
  detection-script helper; offline **contract suite** in the house shape —
  `tests/services/forgejo-main-sync.sh` is the exact template (red-first, ok/fail
  counters, run-from-anywhere, no network, mutation teeth-checks; read its sibling
  conventions via cf-119 STATE.json commands). `tests/services/` already holds
  `dev-forgejo-runner.sh`, `gpu-forgejo-runner.sh`, `infra-forgejo.sh` fleet probes.
  A changed-dirs detector written as a shell/Python helper is unit-testable locally
  in a scratch git repo — the mutation-teeth pattern applies.
- NOT available: `actionlint`, `hadolint`, `yamllint` (all MISSING on PATH;
  `npx actionlint` has no npm target). helm lives at `~/.local/bin` (export PATH) —
  only needed if the plan touches charts (e.g. a new runner slice).
- Live-fire: infra instance only (dev down, §3); from this worktree both forge
  remotes are unreachable (cf-119 §3 re-verified by inheritance — only `origin`
  answers `git ls-remote`), so live validation is post-merge/user-owned.

## 10. Open questions for the planner (no user questions asked, per launch)

- **OQ-1 Cutover — replace or coexist (biggest).** Once cf-6's workflow exists on the
  forge, a containers/** change reaching infra `main` also syncs to GitHub
  (main-sync), where `.github/workflows/docker-build.yaml` still fires and pushes
  `v<run>` + `main` tags — while the Forgejo pipeline pushes `latest` + calendar tags.
  Two builders, two tag namespaces, double CI minutes on the same images. The card
  reads like a replacement; deleting/trimming the GitHub workflow is a repo-file
  decision (and interacts with the Renovate migration, §6). Needs an explicit ruling.
- **OQ-2 Which instance builds.** Same repo on both forges → guard with
  `startsWith(forgejo.server_url, …)` exactly like main-sync; infra (live runner) is
  the only workable choice today, but decide whether the guard should be infra-pinned
  forever or dev included when it recovers. Also: PRs — do they even get opened on
  the forge today, or stay a GitHub-side workflow? (Grounding: cf-119 OQ-1 topology —
  today humans land PRs on GitHub; the forge's `main` arrives via sync. If PRs remain
  GitHub-only, the card's PR-branch builds only fire for forge-side PRs — ask.)
- **OQ-3 Increment scheme pick** (§6 options 1–3) + the **Renovate versioning/
  allowedVersions mitigation** for the `v<run>` → `yy.mm.N` crossing, and the
  one-time pin migration. Needs-research: yes (cheap web round on Renovate docker
  datasource ordering + act_runner cache↔buildx-gha compatibility would de-risk
  two flagged facts; everything else is repo-grounded or owner-decision).
- **OQ-4 `latest` vs the rolling `:main` contract.** Keep pushing `:main`, or retire
  it for `:latest` and migrate the documented `:main`+Always consumers
  (wekan-mcp/dev hivetools comment trail, container-creation skill).
- **OQ-5 PR builds actually push?** Card says tag PR builds with branch+hash
  (implies pushing PR tags to ghcr); the GitHub precedent's rule is PR-never-push.
  Pushing is safe only if PR tag names can never shadow rolling/calendar tags —
  needs a naming rule (`pr-<branch>-<shashort>`) and a delete/retention stance.
- **OQ-6 Deploy scope** — §8 reading (publish = deploy, no ArgoCD-side step) should
  be stated in the plan for confirmation rather than assumed silently.
- **OQ-7 Manual-dispatch parity + `dev` branch.** Keep the `workflow_dispatch`
  container-list escape hatch (GitHub has it, cancelled-build recovery argument in the
  file comment)? GitHub's `dev` branch no longer exists — drop the dev leg on the
  forge or mint a dev flow (open; likely drop).
- **OQ-8 Runner capacity / cache behavior at first fire** — capacity-1 serialization
  (§7) and the unverified cache/buildx facts (OQ-3 research leg) argue for a
  deliberately small first smoke build (one cheap container, e.g. traefik-mqtt-
  allowlist) before the full matrix is trusted.
- Human legs the plan must enumerate (not implement), cf-119-style: mint ghcr PAT
  (write:packages) as a Bitwarden item; enter it as an Actions secret on the infra
  instance repo (`CuratedForest/SpencersLab`); bootstrap the workflow onto infra
  `main` (whatever OQ-1's landing flow is); dev-instance repair stays its own
  workstream (drift note §3).

## 11. Implications (files likely in scope)

`.forgejo/workflows/<containers-build>.yaml` (new, sibling of main-sync.yaml);
likely an offline suite `tests/services/<name>.sh`; possible helper script for the
detection/tag logic if the plan wants it unit-testable; `.github/workflows/docker-build.yaml`
edit/delete ONLY per OQ-1; `renovate.json` packageRule per OQ-3; no chart/service
changes needed for the pipeline itself (runner + instances exist) — and note
`aislop ci --changes` does NOT scan `.sh`/`.yaml` (cf-119 friction), so comment
discipline is manual. Do not touch: runner chart, both instance values, the main-sync
workflow.
