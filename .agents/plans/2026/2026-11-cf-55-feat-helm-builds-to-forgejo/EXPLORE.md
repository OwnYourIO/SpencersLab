# EXPLORE — cf-55 Move GitHub parallel helm builds to Forgejo (card #55)

Written by `agent-explore` 2026-11-10 (workspace clock). Read-only grounding for
the planner: the seven GitHub workflows and their parallel shapes, the Forgejo
hosting state of THIS repo, the lab runner inventory and labels, the live GitOps
source chain, the validation surface, and the publish/tag/renovate couplings the
move must not silently break. The card description is EMPTY — everything here is
grounded from disk, live readonly probes, and prior ticket folders. No solution
design, no plan.

Feature folder: `.agents/plans/2026/2026-11-cf-55-feat-helm-builds-to-forgejo/`
Branch: `cf-55-feat-helm-builds-to-forgejo` minted at `a6e493b78` — which IS
`main` on both the prod-Forgejo remote (`origin`) and GitHub (`upstream`)
(verified 2026-11-10 by `git ls-remote --heads`, §3).

## 0. Topology in one paragraph (all live-verified this run)

The repo is hosted on THREE forges with a defined authority chain:
**infra/prod Forgejo** (`git.spencerslab.com/CuratedForest/SpencersLab`, remote
`origin`) is the source of truth; `.forgejo/workflows/main-sync.yaml` (already
landed, cf-119) fans `main` non-force to **GitHub** (`github.com/OwnYourIO/
SpencersLab`, remote `upstream`) and to **dev Forgejo** (`git.scifi.farm/
CuratedForest/SpencersLab`, remote `dev`), guarded by instance-side repo variable
`ROLE == 'prod'` (set on the infra instance; `ROLE=dev` on dev — cf-119 plan
UA3). GitHub Actions still does ALL the building (helm release + chart version
bumps, container matrix builds, render tests, two quality gates). ArgoCD pulls
the GitOps repo from **GitHub** (§5 — live Application sources), and published
charts install from the **GitHub Pages index backed by GitHub Releases** (§5).
Two docker-backend lab runners are live (§4): one registered on the prod
instance (serving gpu cluster work), one on the dev instance. `ubuntu-26.04`,
which every GitHub workflow here runs on, is NOT a lab label (§6).

## 1. `.github/workflows/` inventory (7 files — the move surface)

| File | Trigger | Parallel shape | Publishes | Credentials |
|---|---|---|---|---|
| `release.yaml` ("Release Charts") | `push: branches:[main] paths:[charts/**]` (:4-8) | `strategy.matrix.chart` over changed chart dirs (:57-58, :114-115), jobs `test-build`/`bump` serialized by `concurrency` groups (:63-65, :120-123) | GitHub Releases `<chart>-<version>` + `gh-pages` index (chart-releaser default; verified §5), and commits Chart.yaml patch bumps back to the repo | `permissions: contents: write` + `secrets.GITHUB_TOKEN` (:59-61, :108, :187) |
| `docker-build.yaml` | `push` main/dev on `containers/**`, `pull_request` same paths, `workflow_dispatch` with free-text `containers` input (:8-30) | `detect-changes` job → `strategy.matrix.container` `fail-fast: false` (:87-95) | `ghcr.io/<owner>/<name>:v<run_number>` (immutable) + `:<branch>` (rolling); PRs build only, never push (:6-7, :107-114, :123-132, :148-151) | `permissions: contents: read, packages: write`, docker/login to ghcr.io via `${{ github.actor }}` + `secrets.GITHUB_TOKEN` (:96-114) |
| `aislop.yaml` | `pull_request` (:11-12) | single job | nothing | none (`npx aislop@0.20.0 ci --changes --base origin/main --human`, :29) |
| `rulesync.yaml` | `pull_request` (:6-8) | single job | nothing | none (`npx rulesync@37.0.0 generate --check`, :24) |
| `vllm-render-tests.yaml` | push-main + PR, path-gated (`charts/vllm/**`, `containers/vllm-radiance-mxfp4/**`, `services/gpu-ai/prod/values.yaml`, itself) (:9-23) | single job | nothing | `permissions: contents: read` (:25-26) |
| `gpt-researcher-render-tests.yaml` | same shape (:9-27) | single job | nothing | contents: read |
| `llama-swap-tools-tests.yaml` | same shape (:13-31) | single job | nothing | contents: read |

### 1a. `release.yaml` — the helm pipeline, job by job

- `changes` (:11-51): checkout `fetch-depth: 0`, `dorny/paths-filter@v4` over
  `charts/**`, unique second path segment → JSON array `CHARTS`, `HAS_CHANGES`
  gate. This is the "parallel" detection to replicate.
- `test-build` (:53-108): per-chart matrix; `EMAsphere/bump-helm-chart-action@main`
  (patch bump, `app_version: false`) :77-83; `Add repositories` step (:86-98) —
  the cf-77 r2 hardened `helm dependency list | awk` loop that skips `oci://`
  URLs (comment at :89-92 documents the empty-REPOSITORY-column failure mode);
  `helm/chart-releaser-action` pinned at SHA `3e001cb8…` (:103) with
  `skip_existing: true, skip_upload: true` — build-and-lint test only.
  `concurrency: ${{ github.ref }}-test-build` serializes the matrix "so that they
  get bumped correctly" (:63-65).
- `bump` (:110-147): per-chart matrix again, `concurrency: ${{ github.ref }}`
  (:120-122); re-bumps and commits via `EndBug/add-and-commit@v11.1.1` (:146-147)
  — this commits Chart.yaml version bumps **onto GitHub `main`**. Known-broken
  TODO inline at :144-145: "Multi chart building breaks here because the commits
  step on each other… maybe loop instead of matrix". Runs `git pull` before
  (:134).
- `release` (:149-188): single job, same repo-add loop (:168-180),
  `helm/chart-releaser-action@v1.7.0`, `skip_existing: true` (:181-186) —
  creates the GitHub Release per new chart version and updates the Pages index.
  `CR_TOKEN: secrets.GITHUB_TOKEN` (:187). (The `CHART:` env at :140/:188 is
  vestigial — `matrix.chart` does not exist in the `release` job.)

### 1b. `docker-build.yaml` — the container pipeline

- Change detection (:46-85): pure `git diff --name-only` (no third-party
  filter): PR range `BASE_SHA..HEAD_SHA`, push range `github.event.before..
  github.sha` with all-zero-`before` fallback to `HEAD^`, `workflow_dispatch`
  manual list wins (:57-60). Container name = 2nd path segment, strict DNS-safe
  regex `^[a-z0-9]+(-[a-z0-9]+)*$` AND `Dockerfile` present (:74-83) — the
  ADO-legacy validation (`matches ADO validation`, :74).
- Build (:100-154): checkout, `docker/setup-buildx-action@v4`, login,
  `docker/metadata-action@v6`, `docker/build-push-action@v7` with context
  `containers/<name>/`, `type=gha` cache (:143-154). Tags: `run_tag=v${RUN_NUMBER}`
  from `github.run_number` (:116-125) — **the tag semantics are GitHub run-number
  based**; branch tag sanitized `/`→`-` (:126-132).
- 12 container dirs exist today: brother-ptouch-automation, coder-workspace,
  forgejo-host-runner, gpt-researcher, gpt-researcher-frontend, music-assistant,
  okd-enketo, renovate-mcp, snapcast, strata, traefik-mqtt-allowlist,
  vllm-radiance-mxfp4, wekan-mcp (`ls containers/`).

## 2. Is the repo on Forgejo? YES — two instances, one `.forgejo/` workflow today

- `git remote -v`: `origin` = `https://git.spencerslab.com/CuratedForest/SpencersLab.git`
  (prod), `dev` = `ssh://git@git.scifi.farm:22222/CuratedForest/SpencersLab.git`,
  `upstream` = `git@github.com:OwnYourIO/SpencersLab.git`, plus unrelated
  `proxy-backup` and `spencerslab-dev` (`CuratedForest/SpencersLab-Dev` — a
  different repo, cf-119 EXPLORE §3).
- `git ls-remote --heads upstream` (2026-11-10): GitHub has `main` @ `a6e493b78…`
  AND a **`gh-pages`** branch @ `c27e45f…` — the chart index branch chart-releaser
  pushes (cf-77/AGENTS chart-releaser tags live alongside).
- `git ls-remote --heads origin` (prod Forgejo): `main` @ `a6e493b78…` — same SHA,
  so the fan-out is currently green.
- `.forgejo/` in THIS repo: exactly ONE file, `find .forgejo -type f` ⇒
  `.forgejo/workflows/main-sync.yaml` (64 lines; read fully). cf-11's site
  workflows (deploy.yml/sync.yml, `runs-on: cf-host`) landed on the
  **CuratedForest repo**, not here — verified: not present under this
  `.forgejo/`.
- `main-sync.yaml` shape (the repo's only Forgejo-workflow precedent, and the
  contract its suite enforces): triggers `push: branches: [main]` +
  `workflow_dispatch`; both jobs guard `if: vars.ROLE == 'prod'` (:25, :46);
  `runs-on: ubuntu-24.04` (:26, :47); destinations/credentials are instance-side
  repo vars `PUSH_URL_GH`/`PUSH_URL_DEV` + secrets `PUSH_TOKEN_GH`/
  `PUSH_TOKEN_DEV` (:36-43, :57-64); plain non-force `git push … HEAD:refs/
  heads/main` (:43, :64); every run block starts `set -euo pipefail`.
  cf-119's plan §User-actions records `ROLE=prod`, `PUSH_URL_GH=https://github.com/
  OwnYourIO/SpencersLab.git`, `PUSH_URL_DEV=https://git.scifi.farm/CuratedForest/
  SpencersLab.git` on the infra repo; `ROLE=dev` on the dev repo
  (`2026-11-06-cf-119-feat-forgejo-push-main.md:289-295`).
- **The `.github` fallback flip has already happened** (cf-119 EXPLORE §2 docs
  quote): Forgejo looks up workflows in `.github/workflows` only when no
  `.forgejo/workflows` exists — since main-sync exists, the seven GitHub files
  are inert on both Forgejo instances, and adding a moved workflow under
  `.forgejo/workflows/` changes nothing about them. Conversely the GitHub copies
  still fire on GitHub whenever main-sync pushes main there (path filters match).

## 3. Instance identities (from disk, unchanged since cf-119)

| | dev instance | infra/prod instance |
|---|---|---|
| Host | `git.scifi.farm` (custom-values/dev/prod-values.yaml:77-78 `DOMAIN/ROOT_URL`) | `git.spencerslab.com` (custom-values/infra/prod-values.yaml:63-64) |
| Release | `dev-forgejo` (dev cluster, ns `default`) | `infra-forgejo` (infra cluster, ns `default`) |
| SSH | `ssh://git@git.scifi.farm:22222/...` | `ssh://git@git.spencerslab.com:22222/...` (.agents/notes/2026-10-23-forgejo-git-ssh.md:11-14; :22 stays node sshd) |
| Notes | `forgejo.spencerslab.com` is a UI alias **banned** for runner/LFS URLs (public-edge TLS name mismatch — cf-104 §R3, gpu-forgejo-runner.sh:23-28,58) | |

Live state probed 2026-11-10 via readonly k8s MCP (`resources_get`):
`dev-forgejo` Deployment 1/1 ready, `infra-forgejo` Deployment 1/1 ready,
`dev-forgejo-runner-dev` STS 1/1 ready, `gpu-forgejo-runner-gpu` STS 1/1 ready —
the cf-119-era dev outage (`forgejo-s3-secret`) is resolved.

## 4. Runners — who can execute a moved workflow (charts/forgejo-runner)

Chart law (values.yaml header :1-75, read fully): one release = one registration
= one pod (`uuid`+`token` from a Bitwarden item via ExternalSecret, :77-89);
backends `docker` (privileged DinD sidecar + act images) and `host` (jobs run in
the runner container `ghcr.io/ownyourio/forgejo-host-runner`); the host mode's
slice must null out docker-only keys and the template FAILS the render if any
docker key survives `backend: host` (secret-runner.yaml:25 + values.yaml:30-44 —
ArgoCD strips nulls from inline values, argo-cd#16312). Registration scope is
owner-side UI; **cross-runner job hijacking is prevented by labels, which are
instance-scoped** (values.yaml:45-52).

| Release | Cluster | Registers to | Backend | Labels advertised | Status today |
|---|---|---|---|---|---|
| `forgejo-runner-dev` (`charts.forgejo-runner-dev` + slice `runner.url: http://dev-forgejo-http:3000` — services/dev/prod/values.yaml:114-117,176-178) | dev | dev instance | docker | act set below | STS ready 1/1 |
| `forgejo-runner-gpu` (`charts.forgejo-runner-gpu` `chart: forgejo-runner` + slice `runner.url: https://git.spencerslab.com` — services/gpu/prod/values.yaml:119-122,271-273; token item on the INFRA instance — custom-values/gpu/prod-values.yaml:109-118) | gpu | **prod instance** | docker | act set below | STS ready 1/1 |
| host-mode dev release | — | — | host | `cf-host` (values.yaml:52) | **REMOVED** by owner review 2026-11-06 — the MODE ships in the chart, inert; "dev-runner = separate ask" (cf-11 STATE.json:183) |
| infra-cluster runner | infra | prod | — | — | **un-wired** pending relocation (values.yaml:3-6; 2026-10-25 user decision, tests/services/dev-forgejo-runner.sh:14-19) |

The act label set (charts/forgejo-runner/values.yaml:107-112; asserted verbatim
in tests/services/gpu-forgejo-runner.sh:223-229 and
tests/services/forgejo-main-sync.sh:189):

```
ubuntu-latest  / ubuntu-24.04 / ubuntu-22.04 / docker / node22
  → docker://ghcr.io/catthehacker/ubuntu:act-24.04   (act-22.04 for ubuntu-22.04)
```

Implications grounded for the planner: the prod instance has exactly ONE runner
today (the gpu-hosted docker one) and the dev instance one; `runs-on:
ubuntu-24.04` / `ubuntu-latest` / `node22` route to them (main-sync uses
ubuntu-24.04 and is live — evidence the action-clone path works for
`actions/checkout@v6` on the prod instance). The cf-104 C04 ruling put every
label on the LFS-capable act family (gpu-forgejo-runner.sh:219-222). Jobs needing
docker-in-job (the `docker/build-push-action` legs) get it only via the DinD
sidecar + `DOCKER_HOST` (values.yaml:219-223); host-mode `cf-host` currently has
**no live runner anywhere**.

Runner toolchain caveat grounded from tests: the act images are the job
containers (not GitHub-hosted VMs) — none of the GitHub workflows installs
`helm`, they rely on GitHub's ubuntu image preinstall (vllm-render-tests.yaml:44
runs `helm dependency update` with no setup step; same for lint/template).
Whether `ghcr.io/catthehacker/ubuntu:act-24.04` carries `helm`/`python3`/`jq` at
the versions these steps assume is **not verifiable from this workspace** —
first-fire risk; main-sync's live runs only prove `git`+`bash`+`actions/checkout`
work there. (cf-119 EXPLORE OQ-3 flagged the same for action egress; partially
answered since — main-sync is live.)

## 5. GitOps constraints — where ArgoCD actually pulls from (LIVE evidence)

Shared appset law (charts/base/templates/appset-charts.yaml:54-69 + per-service
copies, e.g. services/infra/prod/templates/appset.yaml:78-102): every Application
source resolves `repoURL` from cluster-secret annotations `services.repo`
(git source, `targetRevision: main`), and for versioned charts
`repository`/`chart` (§ appset-charts :64). The cluster Secrets themselves are
out-of-repo (argocd ns; the readonly MCP identity is RBAC-denied list/secrets
there — probed, `forbidden`). Resolved values proved from live Application
objects (`resources_get`, ns `default`, 2026-11-10):

- `infra-forgejo` → sources: `https://github.com/OwnYourIO/SpencersLab.git`@main
  (values leg) + same repo `path: charts/forgejo` (chart leg).
- `gpu-forgejo-runner-gpu` → same: GitHub git repo @main, `path:
  charts/forgejo-runner`.
- `infra-external-secrets-bitwarden` → values leg GitHub git @main; chart leg
  `repoURL: https://ownyourio.github.io/SpencersLab/`, `chart:
  external-secrets-bitwarden`, `targetRevision: 1.0.10` (matches
  services/infra/prod/values.yaml:11-12).

So **ArgoCD consumes this repo's GitOps content from GITHUB `main`** — today
that content reaches GitHub only via the prod-Forgejo `main-sync` fan-out.
**Published charts install from the GitHub Pages index**, and the live index
(webfetch `https://ownyourio.github.io/SpencersLab/index.yaml`, 2026-11-10)
shows EVERY package `urls:` entry as
`https://github.com/OwnYourIO/SpencersLab/releases/download/<chart>-<version>/<chart>-<version>.tgz`
— GitHub Releases are the artifact store, gh-pages branch is the index (exists on
`upstream`, §2). Latest entries are recent (actualbudget 1.0.4 dated
2026-10-25; archon 1.0.18 2026-02-16), i.e. the pipeline is alive. The internal
charts with NO `version:` (forgejo, forgejo-runner, llama-swap, vllm…) deploy
straight from the git path — they are "versioned by CI, not renovate"
(services/infra/prod/values.yaml:15).

## 6. The three publish/consume surfaces a moved CI must keep coherent

1. **Git**: work lands on prod-Forgejo `main` (branch mint §0; AGENTS: PR to main
   is user-owned); GitHub main is a non-force sync target; ArgoCD reads GitHub
   (§5). A moved `release.yaml` that bumps Chart.yaml must bump on the FORGEJO
   main side (or its GitHub-side commits will make the next main-sync push
   non-fast-forward — main-sync is deliberately non-force, header :8-10 +
   forgejo-main-sync.sh t4). This desync hazard is ALREADY latent today (GitHub
   bump commits advance GitHub main past Forgejo main; whether today's main-sync
   runs are green through bumps is live-instance state, unverifiable here —
   OQ-2).
2. **Chart artifacts**: chart-releaser today writes GitHub Releases + gh-pages
   index; renovate's helm datasource reads `https://ownyourio.github.io/
   SpencersLab/` (values-file annotations, e.g. services/infra/prod/values.yaml:11,
   services/gpu/prod/values.yaml:146-147; managers #7/#8 in renovate.json:55-75
   plus the `baseChartVersion` manager :101-109 and the changelog/sourceUrl
   override manager :121-129). Moving chart publishing changes WHO can mint
   versions and where the index lives → AGENTS hard rule "Never bump versions or
   image tags by hand… release.yaml bumps Chart.yaml version (patch) on every
   merge to main and chart-releaser tags `<chart>-<version>`" pins the coupling
   this ticket must re-establish on the new builder.
3. **OCI images**: builder today pushes `ghcr.io/ownyourio/*` with
   `GITHUB_TOKEN`+`packages: write`; consumers pin `:v<run_number>` (charts pin
   `ghcr.io/ownyourio/wekan-mcp:v162` services/gpu/prod/values.yaml:715,752;
   `renovate-mcp:v84` services/dev/prod/values.yaml:298; helm-chart-creation's
   Image tag pinning rule). `:v<run_number>` is the GitHub Actions run counter —
   Forgejo Actions exposes `github.run_number`/`forgejo.run_number` aliases (cf-119
   EXPLORE §2 context table) but it is a PER-REPO counter that starts at 1 on the
   new host: the first Forgejo build would tag `:v1` and the monotonic-global
   property ("registry maximum is not automatically the right bump target" —
   container-creation skill) breaks across the two numbering spaces unless the
   plan decides a scheme. No Forgejo Packages/Container registry config exists in
   charts/forgejo (grep `packages|registry|FORGEJO__` — only LFS/S3 env legs,
   values.yaml:100,124-188), so a moved builder pushing to ghcr needs an external
   credential (repo secret with a GitHub PAT for `ghcr.io/ownyourio` — the
   fine-grained-PAT shape cf-119 §5 documented for pushes: Contents R/W +
   Workflows… for packages it is "write:packages" scope) or a new registry
   decision — DESIGN, planner's call.

## 7. Validation commands available to a plan (probed this session)

- Agent shell (Coder workspace, PATH needs `export PATH=$HOME/.local/bin:$PATH` —
  AGENTS recipe): `helm v3.16.4` ✓, `pytest 9.1.1` ✓, `node v26.5.0` ✓,
  `hadolint 2.15.1` ✓, `docker` **NO daemon** ✓(confirmed) — the AGENTS/cf-77
  "CI-primary" build rule applies unchanged; `yq` ✗ (suites use python3+PyYAML
  instead).
- Repo-standard chart validation: `helm lint charts/<name>`,
  `helm template charts/<name> --debug`, trio greps, `OVERRIDE_*` 1:1 sweep
  (AGENTS "Pipeline specifics"; worked command set in the three render-test
  workflows and in tests/services/gpu-forgejo-runner.sh:84-126 helm
  discovery/download harness, which a new suite can copy — it also encodes the
  registry-unreachable ⇒ SKIP rule).
- `aislop` gate: `npx --yes aislop@0.20.0 ci --changes --base origin/main
  --human` (aislop.yaml:29; the pin parity with the plugin is machine-guarded —
  §8). Friction precedent (cf-119 dev report): aislop scans only 7 languages —
  `.sh`/`.yaml` workflow/test files pass it vacuously.

## 8. Tests already bound to workflow files (a move edits these or they redden)

- `tests/services/forgejo-main-sync.sh` (236 lines, t1-t8) — static contract
  suite over `.forgejo/workflows/main-sync.yaml`; THE template for a new
  `.forgejo/workflows/<moved>.yaml` contract suite (bash+python3, no network,
  mutation teeth per cf-119 STATE results).
- `tests/opencode/aislop-pin-parity.test.ts:30` — `WORKFLOW =
  ".github/workflows/aislop.yaml"`, binds the aislop version pin between the
  workflow, the plugin, and CI. Moving/duplicating aislop.yaml breaks this test
  (or must be re-pointed in the same change).
- `charts/vllm/tests/test_contract.py:518,528` — asserts
  `.github/workflows/vllm-render-tests.yaml` exists (and references its own
  path in triggers). Moving that workflow redden this pytest leg unless updated
  together.
- `charts/llama-swap/tests/test_strata_untouched.py:26` — asserts
  `.github/workflows/release.yaml` stays pristine (a Q-C constraint from the
  strata ticket). A cf-55 change to that file interacts with this guard.
- `tests/agent-board-coord/gate.sh:877,961` + `tests/agent-board-coord/
  rulesync-surface.sh:620` — pipeline allow-sets name
  `.github/workflows/aislop.yaml` / `ci.yaml` paths.
- `tests/containers/forgejo-host-runner.sh` t10 (lines 225-240) — codifies the
  designed `docker build => no-daemon, CI-deferred` passing shape and names
  `docker-build.yaml` on merged main as build authority; moving the builder must
  keep that observable (AC6-style CI evidence).
- `tests/renovate/chart-yaml-legs.sh` (header) + `dockerfile-pins.sh` — execute
  the renovate.json manager regexes against real files (RE2-safety convention);
  any datasource/registryUrl move lands here.
- Per-directory pytest law (AGENTS): basenames duplicate across chart suites;
  `PATH=$HOME/.local/bin:$PATH` or helm-guarded tests silently mass-skip.

## 9. Gotchas and divergences for the Forgejo-side moved workflows

1. **Labels**: every GitHub job here runs `ubuntu-26.04` (aislop, rulesync,
   release, all three render-tests) or `ubuntu-latest` (docker-build) —
   `ubuntu-26.04` routes to NO lab runner; a move must re-label to the act set
   (§4). forgejo-main-sync.sh t7 even gates that allowed-label set (LABELS list
   line 189) — extend deliberately.
2. **`GITHUB_TOKEN` on Forgejo is a DIFFERENT thing**: the automatic
   `FORGEJO_TOKEN` (alias `github.token`) is same-repo-write, cannot reach other
   repos/registries, and its pushes **do not re-trigger** that repo's workflows
   (cf-119 EXPLORE §2 docs quote). The moved `bump` job's commit-back and any
   release-asset upload work per-instance, and the recursion guard changes the
   "sync re-triggers GitHub" dynamics (§2 last row, §6 item 1).
3. **Job-level `permissions:` and `continue-on-error` are IGNORED** by Forgejo
   Actions (divergence list quoted in cf-119 EXPLORE §2); docker-build's
   `packages: write` block has no effect there — auth is purely by the secret you
   hand the login step.
4. **Third-party actions** (`dorny/paths-filter@v4`,
   `EMAsphere/bump-helm-chart-action@main`, `helm/chart-releaser-action`,
   `EndBug/add-and-commit@v11.1.1`, `docker/*`) resolve via the runner's
   `DEFAULT_ACTIONS_URL` on Forgejo — egress/availability was flagged unverified
   (cf-119 OQ-3) and only `actions/checkout@v6/7`-class clones are proven by
   main-sync's live runs. `EMAsphere…@main` floating ref + `chart-releaser` SHA
   pin both need a Forgejo-side mirror decision. (Design, not scouting.)
5. **act-image toolchain gap**: no workflow installs helm/python/jq — GitHub
   ubuntu images preinstall helm, python3, jq; the catthehacker act images carry
   node/docker-client, not necessarily helm (release.yaml:29 even `apt-get
   install`s jq, showing jq is NOT assumed on `ubuntu-latest` either… GitHub
   ubuntu runners ship jq preinstalled; the step is belt-and-suspenders). A moved
   workflow must add explicit setup or ship a custom image (forgejo-host-runner
   is hugo/go/netlify-oriented, tests/containers/forgejo-host-runner.sh t5).
6. **`v<run_number>` monotonicity** across the move (§6 item 3) + the
   container-creation rule "check that the newest is YOURS" becomes doubly true
   when two counters feed one registry, plus the anonymous GHCR tag-enumeration
   recipe in that skill presumes ghcr stays the store.
7. **Concurrency semantics**: Forgejo Actions supports `concurrency` but the
   release.yaml design already fights job-cancellation limits (comment :123);
   the bump-collides TODO (:144) is the one known-broken leg the owner may expect
   the move to fix (loop-instead-of-matrix hint inline).
8. **Single-runner serialization**: prod-instance jobs all land on the one
   gpu-hosted runner pod (one concurrent job set unless the chart releases
   scale — values.yaml:117-121 "one pod per registration"; scaling = more runner
   RECORDS). The "parallel" the card names will queue behind main-sync pushes on
   a single DinD box; `fail-fast: false` matrix parallelism becomes
   runner-capacity-bound. Fact, not design.
9. **k3s MTU / action-clone flakiness** (runner values header :70-75,
   forgejo/runner#1779) — moved workflows that clone many actions are exposed to
   the known intermittent clone failure class; mitigations documented there.
10. **Workflow fallback flip is done** (§2 end): new `.forgejo/workflows/*.yaml`
    files are inert on GitHub and GitHub files inert on Forgejo; until each moved
    workflow is green on Forgejo, deleting its `.github` twin loses the gate —
    but keeping BOTH means bump commits collide from two directions (§6 item 1).
    This is the plan's central tension to resolve.
11. Runner **egress to ghcr.io** for act images already works (pods pulling
    `catthehacker/ubuntu` are live), but egress from jobs to
    `ghcr.io token auth` + `github.com` releases API is a different path —
    unproven (§4/§9-4).
12. aislop gate + plugin pin parity (§8) means an aislop move touches
    `.opencode/plugin/aislop-gate/index.ts` — generated-surface rules don't apply
    (plugin is hand-managed) but the parity test does.

## 10. Prior scout folders to read before planning (richest ground truth)

- `.agents/plans/2026/2026-11-cf-119-feat-forgejo-push-main/EXPLORE.md` —
  instance table, runner table, Forgejo Actions syntax/divergences, credential
  law, loop analysis (§1-§8).
- Same folder `DECISIONS.md` + plan §User-actions/§Live-verification (lines
  280-320 read): ROLE/PUSH_* provisioning, non-force fan-out design, first-fire
  evidence expectations.
- `.agents/plans/2026/2026-11-cf-104-feat-forgejo-lfs/EXPLORE.md` (LFS endpoints
  per instance; act-set node22 swap provenance) and
  `2026-11-cf-97-bug-forgejo-runner/DECISIONS.md` (gid/fsGroup/identity rulings,
  referenced from chart values :241-243, :266-275).
- `.agents/plans/2026/2026-10-cf-11-feat-immich-hugo-pipeline/chunks/C03.md` +
  DECISIONS.md R1/R3 — the host-backend mode + `cf-host` label law.

## 11. What is NOT in this repo / not verifiable from here (instance state)

- The ArgoCD cluster-secret annotations' raw values (RBAC-denied) — resolved
  sources proven from live Applications instead (§5).
- Whether GitHub Actions `release.yaml` bump commits currently make main-sync's
  `push-gh` fail non-FF (and how the owner habitually resolves it); whether
  Actions is enabled repo-level on both instances beyond the main-sync evidence;
  per-instance Actions variables/secrets beyond cf-119's UA3 record; existence of
  any GitHub→Forgejo pull mirror (cf-119 OQ-1 answer: manual flow, no mirror).
- Whether `catthehacker/ubuntu:act-*` carries helm — first-fire or a docs probe.

## Fix-round scout (2026-11-21)

Written by `agent-explore` for the D33 fix round (first-fire failure: runner
"Set up helm" → read ECONNRESET downloading `helm-v3.16.4-linux-amd64.tar.gz`
from get.helm.sh, 3 retries, exitcode 1; owner ruling = bake helm into a custom
act-runner image built by our own containers-build pipeline, served by the
instance registry). Worktree at `origin/main` `b80fae102`. Everything below is
grounded from disk reads + readonly MCP probes run this session; §F0 marks what
is NOT provable from here.

### F1. Helm/tool runtime-install surfaces (`.forgejo/workflows/`)

- `azure/setup-helm@v4` with `version: v3.16.4` — exactly three steps, all in
  `release.yaml`: job `test-build` (`.forgejo/workflows/release.yaml:101-105`),
  job `release` (`:289-293`), job `forgejo-publish` (`:377-381`). Every comment
  on them cites "The act job image carries no helm (RESEARCH C1)". There is NO
  `get.helm.sh` literal in any workflow — the download happens inside the
  action (RESEARCH C2 remedy-1 [30]: mirrored action, node24, get.helm.sh
  default, checksums automatic).
- Other runtime DOWNLOADS in the same family (all `release.yaml`):
  - `Install cr` steps: `curl -fSL --retry 3` of `chart-releaser_1.10.1_linux_amd64.tar.gz`
    from `https://${RELEASES_HOST}/helm/chart-releaser/releases/download/...`
    (`RELEASES_HOST: github.com`, env `:32-34`), sha256-verified — job `release`
    `:294-308` and job `forgejo-publish` `:382-396`. Same egress-fragility class
    as the helm download (github.com from the job container); the file's own
    comment names it "unproven-egress class, first-fire-checked (UA-5)".
  - bump leg fetches the published index: `curl -fsSL -o /tmp/published-index.yaml
    $PUBLISHED_INDEX` where PUBLISHED_INDEX = `https://ownyourio.github.io/SpencersLab/index.yaml`
    (`:168`, `:188`) — GitHub-Pages egress, same class.
  - `forgejo-publish` instance curls (`:452`, `:474`) target the instance's own
    host (LAN-side, different path); containers-build curls hit ghcr.io +
    `GITHUB_SERVER_URL` registries (API reads, not tool installs).
- NO tool installs at run time in the other three files: `main-sync.yaml` is
  git+checkout only (`:32-47`, `:53-68`); `renovate.yaml` has ZERO `uses:` steps
  and runs all tools inside its container image (`:50-70`); `containers-build.yaml`
  installs nothing — its tool curls are registry `/v2/` reads
  (`:208-284`). (The `.github/workflows` family runs on GitHub-hosted runners
  with helm preinstalled — outside this fix's scope, RESEARCH C1 helm row.)
- First-fire survival, as far as the evidence reaches: `test-build` is the FIRST
  setup-helm in the needs chain (`changes → test-build → bump →
  release/forgejo-publish`, `:84-85`, `:150-151`, `:269-270`, `:366-367`), so a
  "Set up helm" failure means: job `changes` PASSED (actions/checkout@v7 cloned,
  full-depth git negotiation worked, `jq` present — `:73` — and the
  `GITHUB_OUTPUT` write worked), and inside `test-build` the Checkout step and
  the `azure/setup-helm@v4` CLONE both passed before the action's own download
  died. `bump`, `release`, `forgejo-publish` never executed (unmet needs) — no
  bump commit, no release, no registry push (consistent with main @ b80fae102
  carrying no `<chart>-<version>` activity). Steps sharing the fragility that
  never got to prove themselves: every `curl github.com` above, plus
  `helm repo add`/`helm dependency build` chart-repo egress (`:123-147`,
  `:326-339`, `:406-419`), cr's API uploads/index push (`:340-363`), and the
  registry curls in containers-build (`:208-355`).
- Agent-side get.helm.sh fallbacks exist in many tests/services suites
  (`tests/services/dev-forgejo-runner.sh:140-160`, `gpu-forgejo-runner.sh:106-126`,
  plus dev-git-auth, dev-mcp-fleet, forgejo-lfs, forgejo-ssh-gateway,
  gpu-coder-sso, hivetools-kubernetes-mcp-toml, infra-forgejo,
  media-lidarr-betanin-mount...) — different class (Coder-workspace egress, with
  skip-on-failure semantics), listed only so a de-helm sweep does not confuse
  them for runner-side installs.

### F2. Act-runner deployment

- Chart: `charts/forgejo-runner` (ONE release = one registration = one pod;
  declarative v13 registration via the ExternalSecret-rendered `config.yaml` —
  values.yaml:54-68). Aliased twice: `forgejo-runner-dev`
  (`services/dev/prod/values.yaml:114-117`) and `forgejo-runner-gpu`
  (`services/gpu/prod/values.yaml:119-122`). No infra-cluster deployment:
  `services/infra/prod/values.yaml` has no forgejo-runner entry (grep empty;
  infra runner un-wired per values.yaml:2-6 + DECISIONS 2026-10-25).
- Default job image = the LABEL→IMAGE map, not a separate "default image" key:
  `runner.labels` (`charts/forgejo-runner/values.yaml:107-112`), rendered
  verbatim into `server.connections.default.labels`
  (`charts/forgejo-runner/templates/secret-runner.yaml:138-143`):
  `ubuntu-latest|ubuntu-24.04|docker|node22 → docker://ghcr.io/catthehacker/ubuntu:act-24.04`,
  `ubuntu-22.04 → act-22.04`. NO `:free`-style labels exist in this deployment.
- Daemon + dind pins: runner `data.forgejo.org/forgejo/runner:13.2.0`
  (values.yaml:197-203, renovate helm-values-tracked per comment :200-202);
  dind sidecar `docker:29.9.2-dind` privileged initContainer (values.yaml:158-165);
  `DOCKER_HOST: unix:///var/run/docker.sock` + `CREDENTIALS_DIRECTORY` env
  (values.yaml:219-223).
- config.yaml (secret-runner.yaml:86-118): `capacity: 1`, `timeout: 30m`,
  `shutdown_timeout: 5m`, `cache.enabled: true` (docker mode: NO `cache.dir` —
  it lands in `~/.cache/actcache` under `HOME=/data` on the 2Gi `data` VCT,
  values.yaml:126-132), `container.privileged: false` (:109-110). VCTs:
  `data` 2Gi + `docker-data` 10Gi local-path (values.yaml:124-147) —
  docker-data is the job-image store ("without it every job re-pulls its
  images", :136-137).
- URL + identity slices (the ONLY things overridden):
  `services/dev/prod/values.yaml:176-178` (`url: http://dev-forgejo-http:3000`),
  `services/gpu/prod/values.yaml:271-273` (`url: https://git.spencerslab.com`);
  Bitwarden ids `custom-values/dev/prod-values.yaml:92-98`
  (`runner-token: d3dafd1a-…`, item `dev-forgejo-dev-runner`) and
  `custom-values/gpu/prod-values.yaml:109-118` (`22a71ee4-…`, item
  `forgejo-runner`, an INFRA-instance record).
- Live probe 2026-11-21 (readonly MCP): gpu pod `gpu-forgejo-runner-gpu-0`
  Running since 2026-11-05T21:09:43Z, runner container
  `data.forgejo.org/forgejo/runner:13.2.0`, STS VCTs data 2Gi + docker-data
  10Gi local-path; dev pod `dev-forgejo-runner-dev-0` Running since
  2026-11-09T15:15:58Z, runner `:13.2.0`, init `docker.io/library/docker:29.9.2-dind`.
  Secrets list/get RBAC-denied on both clusters ("kubernetes-mcp-readonly cannot
  list secrets"), infra STS list returns RBAC-masked empties — same posture as
  §11 of the original EXPLORE.
- Job-level `container:` in this deployment: `renovate.yaml:50-51` USES it
  (`container.image: ghcr.io/renovatebot/renovate:44.181.5`) on the same
  `runs-on: ubuntu-24.04` act-label runner. Authored + statically contracted
  (cf-135, plan complete, `.agents/plans/2026/2026-11-cf-135-feat-renovate-forgejo/STATE.json`
  plan_status "complete"); its header (:21-23) records the measured law "these
  runners never re-pull a tag they have already cached — a floating tag or a
  minor rollup would stick at its first-pull content forever" (same finding as
  RESEARCH C2 remedy-3 citing docs: "container images, once downloaded, are
  never updated"). Whether a `container:` job ran GREEN live is not provable
  from the repo (cf-135 UA5 "first-fire watch" stayed an open owner action;
  card #135's infra-flip continuation was live at 2026-11-21 per D34).

### F3. containers/ shape

- Existing images (`ls containers/`): brother-ptouch-automation,
  coder-workspace, forgejo-host-runner, gpt-researcher, gpt-researcher-frontend,
  music-assistant, okd-enketo, renovate-mcp, snapcast, strata,
  traefik-mqtt-allowlist, vllm-radiance-mxfp4, wekan-mcp (13).
- Standard parts: `Dockerfile` REQUIRED (every dir has one); README.md optional
  (forgejo-host-runner, strata, vllm-radiance-mxfp4, wekan-mcp); build-context
  extras by name — `files/` + `carry/` (strata), `sync/` + `.dockerignore`
  (forgejo-host-runner; strata has none); per-image python test dirs under
  `containers/<img>/tests/` exist for forgejo-host-runner (pytest t01-t13 for
  the bundled sync tooling) and strata (`tests/test_dockerfile.py`) — NO
  workflow runs them (grep of .github/.forgejo finds no reference; they are
  executed by the owning ticket's agent sessions).
- Renovate pins in Dockerfiles: `# renovate: datasource=… depName=…` comment
  directly above an `ARG` line (forgejo-host-runner/Dockerfile:14,22,31,39;
  coder-workspace/Dockerfile:40-74) — claimed by the customManagers at
  `renovate.json:112` (git-pin ARGs) and `:134`
  ("Pinned tools in containers/*/Dockerfile", node-version|golang-version|
  forgejo-releases|npm). THE existing bake-helm precedent:
  `containers/coder-workspace/Dockerfile:49-50`
  (`# renovate: datasource=github-releases depName=helm/helm` +
  `ARG HELM_VERSION=v3.22.1`) installed at build time from
  get.helm.sh + sha256sum -c + version assert (`:142-149`).
- Detection (`scripts/forgejo-container-detect.sh:24-90`): push diffs the whole
  `before..sha` range under `containers/` (:76), name = 2nd path segment,
  gates = DNS-safe regex `^[a-z0-9]+(-[a-z0-9]+)*$` AND
  `[ -f containers/<n>/Dockerfile ]` (:84-86); PR = merge-base..head (:33-44);
  first push (all-zero before) = tip-only + ::warning:: (:55-62); dispatch list
  shares the gates (:27-30, :80-82). THERE IS NO REGISTRATION LIST anywhere —
  a new `containers/<name>/Dockerfile` touched by a push to main on the prod
  instance is built automatically (workflow paths
  `.forgejo/workflows/containers-build.yaml:71-77`; build context = the dir,
  :347). Caveat the fix round must know: the detector's header (:3-5) claims
  "the runner image ships no jq or python" (RESEARCH C1 contradicts — act
  images DO ship both; the script stays coreutils-only, which is what
  containers-build.yaml:267 actually relies on).
- Tags + push targets (containers-build.yaml:13-20, :331-355): calendar
  `yy.mm.N` union-max across BOTH registries (walk :184-245 forge, :247-319
  ghcr), plus `:latest` + `:main` rolling; push to `ghcr.io/ownyourio/<name>`
  (login :177-183, `GHCR_PUSH_PAT`) and `<host-from-forgejo.server_url>/curatedforest/<name>`
  (login :184-198, `FORGE_PUSH_TOKEN`, lowercase namespace literal). PR on a
  dev-role instance: `pr-<branch>-<sha>` local registry only (:357-405).
  Host is derived in-workflow, never a literal (:189-197) — so on the prod
  (infra) instance the local registry is `git.spencerslab.com/curatedforest/…`,
  reachable by the gpu-hosted runner which dials that same host (F2).

### F4. Runner-pull path (can the runner start jobs from the instance registry?)

- Today job images come from PUBLIC ghcr (labels, F2) and are pulled by the
  in-pod dind dockerd over `DOCKER_HOST` (values.yaml:158-165, :219-223); the
  pull is anonymous — nothing in the rendered config.yaml carries registry
  credentials (secret-runner.yaml:86-143 has no auth key at all; chart is
  host-free by design, values.yaml:54-59).
- In-step `docker login` (containers-build.yaml:180-198) writes the config of
  the docker CLIENT inside the job container — that authenticates PUSHES from
  steps; it does not and cannot authenticate the daemon-side pull of the job
  image itself (the pull precedes every step).
- The runner daemon process runs in the runner container with `HOME=/data` on
  the persistent `data` VCT (values.yaml:126-132, donor image declares it too —
  containers/forgejo-host-runner/Dockerfile:121-124 echoes the fact) — the
  plausible anchor point for a future client-side docker config
  (`/data/.docker/config.json`), but NOTHING in the repo writes such a file
  today (grep: no `.docker/config` surface).
- Instance-registry pull auth: per cf-6 the `curatedforest` packages inherit
  the org's PUBLIC visibility ⇒ credential-free pull "by anything that can
  reach the host" (`.agents/plans/2026/2026-11-cf-6-feat-forgejo-container-builds-1/RESEARCH.md:620-626`,
  marked [LIVE] via `/api/v1/orgs/CuratedForest` → 200 on BOTH instances),
  gated on `service.REQUIRE_SIGNIN_VIEW` (unset anywhere in
  charts/forgejo/values.yaml or custom-values/infra — grep empty; app.ini is
  owner-side, not readable here). `skills/container-creation/SKILL.md:291-293`
  restates it ("allow anonymous pull ... a valid manual pull source"). So the
  pull can plausibly work WITHOUT auth — but no run has ever pulled an instance
  registry image as a JOB image (the first such label would be this fix's
  subject); app-level REQUIRE_SIGNIN_VIEW and host-reachability from the gpu
  cluster (`git.spencerslab.com` — the runner already dials it, F2 slice) are
  the unverified links, marked in §F0.

### F5. Tool needs per workflow (what a baked image must carry)

- `release.yaml` `changes`: bash, git (full-depth), `jq -c` (:73), grep/cut/sort
  (:68-69). `test-build`: checkout (node action runtime), python3 (:109),
  helm (:131-147), awk/tail/head (:131), bash (`[[ ]]` :132). `bump`: git,
  curl (:188), python3 heredoc (:189-249), seq, date-free. `release`: curl,
  sha256sum, tar, chmod (:302-308), git, helm, cr, awk, remote-add/fetch
  (:360-363), `cr package/upload/index` (:351-363). `forgejo-publish`: same
  cr install pair (:390-396), curl POST upload/index read (:452-474),
  basename/awk (:462-471).
- `containers-build.yaml`: bash + coreutils + the detector (pure shell, sed/tr
  :107-124), curl (:208-284), `date +%y.%m` (:200), git, docker CLI (build/push
  /login, :180-355) + `docker buildx version`/`docker info` diag (:171-175) —
  the act image ships the docker CLI + buildx plugin, daemon comes from dind
  (RESEARCH C1/C2). `main-sync.yaml`: git + bash only. `renovate.yaml`: nothing
  beyond its container image's `renovate` binary (:62-70).
- Base images used by the repo's own container builds (pattern to follow):
  `data.forgejo.org/forgejo/runner:13.2.1` as BINARY DONOR +
  `docker.io/library/node:22-bookworm-slim` base (forgejo-host-runner/Dockerfile:14-17);
  `debian:13-slim@sha256:…` (coder-workspace:29); `python:3.15-slim-bookworm`
  (brother-ptouch:1, gpt-researcher:13, traefik-mqtt-allowlist:1,
  wekan-mcp:14); `ghcr.io/...` donors for rebuild-on-upstream
  (okd-enketo:6, vllm-radiance-mxfp4:37, strata:26-57).
- Act-image inventory baseline (what is ALREADY present, so what the baked
  image must not regress) — RESEARCH C1 table (:329-361): git (+`safe.directory`),
  git-lfs, jq, python3.12 + pip/venv/pipx, node 20+24 with tool-cache dirs,
  yq, docker CLI + buildx + compose, sudo/apt; ABSENT: helm (the whole point),
  gh, go, cosign.

### F6. Test surfaces the fix must touch or extend

- `tests/services/dev-forgejo-runner.sh` pins of the runner config (docker-mode
  contract): ACT_LABELS constant :257-262 (image refs embedded), labels-set
  equality leg :466-467, dind image `docker:29.9.2-dind` :312-324 (+t13 gid
  :1508, :1561, :1605), runner image `data.forgejo.org/forgejo/runner:13.2.0`
  + command/env/mount consistency :330-377, renovate helm-values extraction of
  both pins :605-612, LFS-capability comment beside the labels map :615-689
  (labels: key location is asserted — :658-660). ANY label→image re-point
  reddens :466-467 (and the constant); a labels-map restructure additionally
  reddens t14.
- `tests/services/gpu-forgejo-runner.sh`: same ACT_LABELS equality :223-229 +
  :269-271; VCT/local-path/replica shape :243-260; URL pin :55 + banned hosts
  :58; blast-radius g7 :660-671 — pins the charts/forgejo-runner diff at AT
  MOST 2 changed `docker://` lines vs the diff base :668-670 — written for
  cf-104 C04's single-line swap, it is a live tripwire: a 5-label re-point (10
  docker:// lines touched) reddens it against any base predating the swap, so
  the fix round must plan for this leg (it reads `GPU_RUNNER_DIFF_BASE`, :65).
- `tests/services/forgejo-release.sh` (setup-helm pins): t4 label whitelist
  :163-179 (LABELS :167); t5 action allow-list — `ALLOWED = ('actions/checkout@',
  'azure/setup-helm@')` :187, per-step membership check :198-205,
  setup-helm-must-carry-version :206-208, retired-wrapper bans :209-212. NOTE
  (what-the-evidence-shows): t5 only REQUIRES uses-membership, never the
  presence of setup-helm — retiring the three steps does not redden t5 by
  itself; it survives as an over-permissive allowance until the leg is amended
  to ban the action (and the t5 message :217 still names it). The legs that DO
  bind helm availability are the behavior ones: t6 (helm loops :219-242),
  t12 checkout/tag ordering :502-548, and t19's cr-runtime-download contract
  :984-1022 (the same egress class as helm — CR_VERSION/CR_SHA256/RELEASES_HOST
  env pins :1004-1009, both-leg composed-URL + sha256 checks :1010-1017) —
  if cr is also baked or re-sourced, t19 is the carrier to amend.
- `tests/services/forgejo-ci-surface.sh` (whole-state fence): pins
  `.forgejo/workflows/` holding EXACTLY the four-workflow family (header
  :8-11) and the GitHub-side inventory (:12-14) — a new workflow FILE under
  .forgejo or resurrecting a .github twin reddens it; edits inside the four
  files are its intended companion (250 lines; run-battery in cf-55 STATE).
- New-image suite placement (the pattern a `containers/forgejo-runner` suite
  follows): `tests/containers/<name>.sh` — `tests/containers/forgejo-host-runner.sh:1-27`
  is the template (static Dockerfile contract + hadolint + per-leg subset argv,
  the `docker build => no-daemon, CI-deferred` designed-passing shape t10,
  AGENTS "Pipeline specifics"; `.dockerignore` exclusion leg t7; FROM-pin and
  renovate-annotation legs t1/t2). In-image `containers/<img>/tests/` python
  suites are for shipped tooling only (forgejo-host-runner sync tools) — CI
  never runs either kind; agent sessions + the first real build run are the
  executors (same CI-primary law that made this first fire the authoritative
  helm-install test).
- Validation-command shapes for the planner: `bash tests/services/forgejo-release.sh`,
  `bash tests/services/forgejo-ci-surface.sh`, `bash tests/services/dev-forgejo-runner.sh`,
  `bash tests/services/gpu-forgejo-runner.sh`,
  `bash tests/services/forgejo-containers-build.sh` (41-ok full battery, header
  subset discipline :24-30), `bash tests/containers/<new-image>.sh`, plus the
  detector fixtures the run-2 legs execute verbatim (forgejo-containers-build.sh:31-36).

### F0. Not verifiable from this seat (hand-offs)

- Per-job/per-step run logs of the failed fire: the instance Actions API answers
  404 anonymously (`GET /api/v1/repos/CuratedForest/SpencersLab/actions/...`,
  probed 2026-11-21) — the "which jobs survived" reasoning in §F1 is chain
  logic on the owner-reported step name, not a fetched log.
- Whether the instance registry serves anonymous `/v2/` PULLS end-to-end today
  (cf-6 proved org visibility [LIVE], never a pull from a runner-side daemon —
  §F4); whether `REQUIRE_SIGNIN_VIEW` is set in the live app.ini (owner-side).
- Whether a job-level `container:` has ever gone GREEN on either lab runner
  (cf-135 UA5 stayed an open owner action; §F2).
- The exact contents of the deployed runner Secret's config.yaml (RBAC-denied;
  §F2) — pinned indirectly by the two runner suites' render legs.
- What `ghcr.io/catthehacker/ubuntu:act-24.04` carries TODAY at the rolling tag
  (RESEARCH C1 is upstream-source proof, and no renovate manager reads the
  label lines — values.yaml:127-129 records "a bump is manual").

## Fix-round-2 scout (2026-11-23)

Written by `agent-explore` for fix round 2 (worktree `119687225` = main `8227e8f29`
+ plans commit). Trigger: on the owner's instance, the release job's
`Publish GitHub Releases and the Pages index` step packed 389ds/actualbudget/
amd-gpu/archon/audiobookrequest/audiomuse-ai, then died —
`Error: no repository definition for https://charts.jetstack.io,
https://charts.christianhuth.de` (exitcode 1). The baked image works (cf-55
fix round 1 achieved its goal); this round grounds the NEXT failure.

**ROOT CAUSE (grounded + reproduced end-to-end, §A0/A4).** The release job does
NOT lack an `Add repositories` step — it carries the hardened loop three times
(`release.yaml:117-130`, `:300-313`, `:360-373`), and the step RAN GREEN in the
failed fire. The hardened loop itself is the defect: cf-77 r2's
`awk '{ ...; print $1, $i; exit } }'` (`:125`/`:308`/`:368`) uses awk program
`exit`, which TERMINATES the awk program after the first emitted row instead of
`next`, which skips to the next row. The step therefore registers ONLY the
FIRST URL-shaped dependency row of every chart. `cr package` (v1.10.1) runs
`downloader.Manager.Build()` per chart before packaging
(`pkg/packager/packager.go` CreatePackages at tag v1.10.1: explicit
`downloadManager.Build()` + `action.NewPackage()` with
`DependencyUpdate = true`), and Build resolves every Chart.lock
`repository:` URL against the repositories file — undefined ones surface as
exactly the owner's error, with the already-defined repos NOT listed. For
`charts/base` (deps order argo-cd → cert-manager → gateway-api-crds) only the
argo URL is added, and cr dies naming the other two. Alphabetically `base` is
the 7th chart under `charts/*/` and the first multi-row-dependency chart — the
six that packaged fine are single-row charts whose sole row is row 1.

### A0. Reproduction battery (all local, /tmp only; helm 3.16.4 workspace CLI + freshly downloaded 3.22.1)

| Test | Command shape | Result |
|---|---|---|
| A | `helm package charts/base-copy` (fresh HOME, zero repos) | `Error: found in Chart.yaml, but missing in charts/ directory: argo-cd, cert-manager, gateway-api-crds` — exit 1. Plain `helm package` never says "no repository definition": that string is the DOWNLOADER's (Manager.Build), i.e. cr's call. |
| B | `helm dependency list charts/base/` through the SHIPPED awk (`exit`) | emits ONE pair (`argo-cd https://argoproj.github.io/argo-helm`) out of 3 rows — the incompleteness proven |
| B' | same rows through `next` instead of `exit` | all 3 pairs emitted; helm 3.22.1 identical (list output keeps the trailing blank row at 3 deps: `wc -l` 5, header+3+blank — `tail +2 \| head -n -1` arithmetic is CORRECT in both versions; only `exit` is wrong) |
| C | `helm dependency build` base-copy (fresh HOME, zero repos) | `Error: no repository definition for https://argoproj.github.io/argo-helm, https://charts.jetstack.io, https://charts.christianhuth.de. Please add the missing repos via 'helm repo add'` — exit 1 (cr's exact code path, CLI wording; 3.22.1 CLI wording identical) |
| D | same with ONLY argo added (= shipped loop's state) | `Error: no repository definition for https://charts.jetstack.io, https://charts.christianhuth.de` — **the owner's error reproduced verbatim** (URL set, joiner, order) |
| E | `helm package --dependency-update` (fresh HOME, zero repos) | SUCCESS — the full-UPDATE path resolves URLs ad hoc; so the failure is specifically cr's explicit lock-driven `Build()`, which REQUIRES the repositories file to define every lock URL (cr 1.10.1's go.mod links `helm.sh/helm/v3 v3.22.1` — the message carrier is cr's OWN library, not the runner's helm CLI) |
| F | FIXED loop (`next`) adds 3 repos → `helm dependency build` → | all 3 indexes updated, all 3 tgz downloaded (argo-cd-10.18.2, cert-manager-v1.21.3, gateway-api-crds-1.2.5), exit 0 — fix shape end-to-end PROVEN reachable from this seat for all 5 newly-added hosts |

### A1. Current release.yaml anatomy (`.forgejo/workflows/release.yaml`, 429 lines)

- `changes` (:36-80): checkout fetch-depth 0 (:43-49); pure-git range detection
  (:50-80) → `CHARTS` JSON + `HAS_CHANGES`. No helm.
- `test-build` (:82-141): matrix over CHANGED charts (:90-91); checkout
  fetch-depth 0 (:93-99); local patch-bump (:100-116); **Add repositories
  (:117-130) — hardened loop copy #1, buggy `exit` at :125**; Lint and package
  smoke (:131-141): `helm dependency build charts/<chart>` (:139) + lint (:140)
  + package (:141) — per CHANGED chart only.
- `bump` (:143-260): checkout fetch-depth 0 (:153-158); the single-writer
  FF-only loop (:159-260): fetch/reset to origin/main, `curl --retry 3` the
  published index (:182), python version-pair rewrites (:183-244),
  add/commit/push up to 5 attempts (:249-258). **Runs NO helm at all** — the
  launch brief's premise ("bump ran helm operations across all charts") is
  false by evidence: bump has no helm step to succeed or fail.
- `release` (:262-337): env CR_TOKEN=PUSH_TOKEN_GH / PUSH_URL=PUSH_URL_GH
  (:266-273); checkout fetch-depth 0 (:275-282); Configure Git (:283-289);
  Pick up bump commits + `git fetch --tags` (:290-299); **Add repositories
  (:300-313) — copy #2, `exit` at :308**; Publish step (:314-337,
  `if has_changes == 'true'`): `cr package charts/*/` (:325 — iterates ALL 74
  charts via glob, NOT the changed set), `cr upload --owner OwnYourIO
  --git-repo SpencersLab --package-path .cr-release-packages --skip-existing`
  (:326), `git remote add publish` + `git fetch publish .../gh-pages`
  (:334-336), `cr index ... --push --remote publish` (:337). THE OWNER'S
  DEATH SITE: :325.
- `forgejo-publish` (:339-429): checkout (:344-350); pickup+tags (:351-359);
  **Add repositories (:360-373) — copy #3, `exit` at :368**; Package charts
  (:374-380): `cr package charts/*/` (:380) — would die identically (own fresh
  job container, own empty repositories file); curl POST upload loop
  (:381-429).
- URL-list DERIVATION: dynamic in all three copies — `helm dependency list
  <dir>` per `charts/*/` (reads Chart.yaml dependency rows), awk picks the
  first URL-shaped field per printed record; NO static list, NO Chart.yaml
  grep; and after the exit bug, at most one record per chart. The oci://
  rows are skipped by `[[ ! "$url" =~ ^oci:// ]]` (:126/:309/:369). Cross-job
  persistence law: fresh job container ⇒ fresh repositories file, hence the
  three copies (each job that resolves deps re-adds in-job) — that topology
  is correct; only the per-chart completeness is broken.

### A2. Dependency-repo INVENTORY (20 unique http(s) URLs + 3 oci, from all charts/*/Chart.lock — every lock committed, none missing; NO chart vendors committed tgz — `.gitignore:3 charts/**/charts` (services/**/charts too); working-tree tgz exist only under charts/llama-swap + charts/vllm (untracked agent residue, invisible to a checkout). So EVERY chart's deps resolve from repos at cr Build time; a repo is registered iff it appears as the FIRST URL row of some chart.)

| URL | declaring chart(s) (row position) | registered by shipped loop? | fate |
|---|---|---|---|
| https://bjw-s-labs.github.io/helm-charts/ | 55 charts (row 1 `app-template` everywhere) | YES | ok |
| https://argoproj.github.io/argo-helm | base (row 1) | YES | ok |
| https://charts.jetstack.io | base (row 2, cert-manager v1.21.3) | NO | **VICTIM — owner's error** |
| https://charts.christianhuth.de | base (row 3, gateway-api-crds 1.2.5, condition) | NO | **VICTIM — owner's error** |
| https://traefik.github.io/charts | traefik, traefik-zerotrust (row 1) | YES | ok |
| https://crowdsecurity.github.io/helm-charts | traefik (row 2) | NO | **VICTIM next** |
| https://grafana.github.io/helm-charts | loki + k8s-monitoring (row 1) | YES | ok |
| https://prometheus-community.github.io/helm-charts | k8s-monitoring (row 2) | NO | **VICTIM next** |
| https://go.temporal.io/helm-charts | postiz (row 2) | NO | **VICTIM next** |
| https://helm.coder.com/v2 | coder (row 1) | YES | ok |
| https://helm.erpnext.com | erp-next (row 1) | YES | ok |
| https://lumepart.github.io/Explo | explo (row 1) | YES | ok |
| https://charts.external-secrets.io | external-secrets-bitwarden (row 1) | YES | ok |
| https://immich-app.github.io/immich-charts | immich (row 1) | YES | ok |
| https://codecentric.github.io/helm-charts | keycloakx (row 1) | YES | ok |
| https://privatebin.github.io/helm-chart/ | privatebin (row 1) | YES | ok |
| https://seaweedfs.github.io/seaweedfs/helm | seaweedfs (row 1) | YES | ok |
| https://seaweedfs.github.io/seaweedfs-csi-driver/helm | seaweedfs-csi-driver (row 1) | YES | ok |
| https://bokysan.github.io/docker-postfix/ | smtp-relay (row 1, name `mail`) | YES | ok |
| https://NeptuneHub.github.io/AudioMuse-AI-helm | audiomuse-ai (row 1) | YES | ok |
| oci://code.forgejo.org/forgejo-helm | forgejo | skipped by design | ok (registry path) |
| oci://ghcr.io/mariadb-operator/charts | mariadb-operator | skipped by design | ok |
| oci://ghcr.io/stacklok/toolhive ×2 | hivetools (rows 1–2) | row 1 emitted+skipped; row 2 never even emitted (exit) | ok today — BOTH rows oci |

Victim set under the shipped loop = {base, k8s-monitoring, postiz, traefik} —
the four charts with ≥1 URL at row ≥2 (harness: full simulation over all 74
charts, `helm dependency list` buggy-vs-fixed pipelines diffed against each
lock's URL set). Alphabetically after `base`: betanin…ok, …, k8s-monitoring
✝, …, postiz ✝, …, traefik ✝. Shape hazard the fix must not re-acquire: a
future chart with an OCI row FIRST and an http row SECOND is a silent victim
under any "first emitted row" scheme even if that scheme exits cleanly —
per-ROW field scan + `next` per row is the correct semantics (TEST B').

### A3. Historical parity — the GitHub twin (deleted at rebuild; read via `git show`)

- `git show a6e493b78:.github/workflows/release.yaml`: BOTH test-build and the
  release job ran an in-job `Add repositories` step followed by
  `helm/chart-releaser-action` (release job: `@v1.7.0`, `skip_existing: true`;
  test-build: SHA `3e001cb8…`, `skip_existing + skip_upload: true`). No
  `--check-dependencies`, no `--dependency-update`, no skip-package anywhere —
  the twin relied entirely on the loop + cr's internal Build.
- The twin-era loop (parent of the hardening, `git show c4d74dfc4^:...`) was
  `awk '{ print $1, $3 }'` — it printed EVERY dependency row ⇒ all repos were
  registered ⇒ cr's Manager.Build resolved all lock URLs ⇒ green fires. The
  twin-era cr (action v1.7.0 default line) ALREADY called Build():
  `pkg/packager/packager.go` at tag v1.6.0 is the same CreatePackages with the
  explicit `downloadManager.Build()` — so parity was on the LOOP side, not the
  cr side.
- `c4d74dfc4` (2026-10-28 23:02Z, "fix(ci): repo-add step takes only
  URL-shaped dependency fields" — cf-77 r2) replaced the all-rows print with
  the field-scan + `exit`, fixing cf-77's empty-REPOSITORY-column breakage
  while introducing the completeness regression. It IS an ancestor of
  `a6e493b78` (`git merge-base --is-ancestor` verified) — the twin was ALREADY
  broken at twin deletion. Corroborating freshness: the published index at the
  2026-11-10 first scout still topped out at actualbudget 1.0.4 dated
  2026-10-25 (§5, lines 207-213 above) ⇒ no green twin fire between the
  hardening and the move — the bug was born unfired, ported verbatim into all
  three Forgejo jobs (rebuild commits 0dfefeb33/1ada03a50), and this owner
  fire was the first-ever cr-package to feel it. The gateway-api-crds row
  itself predates everything (e3ca402ca, 2026-10-24, "swap vendored tcproutes
  CRD template for pinned gateway-api-crds 1.2.5 dependency") — base has been
  a 3-row chart since then; row 3 came last (its comment :13-19 explains the
  traefik-3.7 tcproutes rationale).
- $HOME law: the twin's loop sat IN the same job as cr (fresh job = fresh
  repositories file — same caveat this scout was asked about) — the rebuild
  kept that topology correctly (:117/:300/:360 all precede their consumers).

### A4. cr package semantics (authoritative sources for this round)

RESEARCH.md's cr sections (:178-200 identity/env + wrapper pitfalls,
:810-820 post-plan cr→direct replacement + shallow-tag law, sources :555-560)
ground the API/identity side but do NOT cover dependency resolution — this
round's authority is the upstream source + the reproduction:

- `cr package` v1.10.1 `cr/cmd/package.go`: "If you wish to use advanced
  packaging options such as … updating chart dependencies please use helm
  package instead" — while `pkg/packager/packager.go` CreatePackages does the
  OPPOSITE internally: per chart it calls `downloader.Manager.Build()`
  UNCONDITIONALLY before `helmClient.Run` (with `DependencyUpdate = true` set
  on the action). Build with a Chart.lock present resolves EVERY lock
  `repository:` URL against the repositories file; any URL not defined there
  is collected and the call fails as `no repository definition for <joined
  URLs>. Please add the missing repos via 'helm repo add'` BEFORE any network
  use for that chart — exactly TESTS C/D. (cr 1.10.1 go.mod pins helm library
  v3.22.1; local 3.16.4 CLI and downloaded 3.22.1 CLI both emit "missing
  repos"; the owner's log wording is the same error class from the instance's
  binary.)
- Consequence: repo definitions must be COMPLETE over every chart's lock before
  `cr package charts/*/` runs — a per-URL, per-lock-entry contract. The
  shipped dynamic loop is the right shape (mirrors bump-free test-build's
  `helm dependency build` at :139, which needs the same completeness for
  changed multi-row charts); it just emits one row per chart.
- Does per-chart `helm dep build` between repo-add and cr package fix it? The
  build itself needs the SAME repo completeness (TEST C), so an added dep-build
  leg alone changes nothing; with the loop fixed, cr's own Build does the work
  (TEST F) — an explicit pre-build would only be belt-and-suspenders. Vendored
  tgz + matching lock is what would make Build repo-free (loader satisfies by
  name-version), but vendoring is gitignored out of existence (:3 .gitignore).

### A5. Test surfaces (`tests/services/forgejo-release.sh`, 20 legs, header :39-45)

- **t6 (:227-251) is THE repo-add leg.** Pins per job (`test-build`, `release`,
  `forgejo-publish`) that the run-blob contains the three tokens `'helm
  dependency list'`, `'^(https?|oci|file)'`, `'^oci://'` (:240-242). It does
  NOT pin `exit` vs `next`, the `tail +2 | head -n -1` arithmetic, step names,
  or any URL list ⇒ an exit→next fix keeps t6 GREEN as-is. BUT t6's comment
  (:233-236) narrates the contract as the "first URL-shaped field" scan —
  prose that must be re-truthed with the fix (it currently blesses the bug),
  and t6 has no completeness TEETH: nothing reddened if the loop under-adds —
  the class of leg the plan will want extended (a fixture-driven awk replay
  demanding all 3 base pairs, like t15's carrier-replay pattern).
- **t19 (:992-1055)** pins the baked-toolchain law: per-job command presence —
  test-build must run `helm dependency list`/`helm repo add`/`helm dependency
  build`/`helm lint`/`helm package` (:1043-1046), release must run
  `helm dependency list`/`helm repo add`/`cr package`/`cr upload`/`cr index`
  (:1047-1048), forgejo-publish `helm dependency list`/`cr package`
  (:1049-1050). Any fix option that REPLACES the dynamic loop with a static
  list deletes `helm dependency list` from those blobs and reddens BOTH legs.
- t12 (:510-556): tag-fetch-before-cr ordering (V-6-2) — unaffected.
- No leg anywhere pins the URL list statically. Static URL literals in tests
  exist only as (a) t15's dep-block FIXTURE (:718 crowdsecurity — fixture
  data, not a contract) and (b) `tests/services/forgejo-ssh-gateway.sh` t2
  (:431, :501-503) — another ticket's suite pinning base's
  gateway-api-crds 1.2.5 Chart.yaml + Chart.lock ENTRY shape (breaks only if
  the dep itself changes shape, not under a loop fix).
- The loop text lives ONLY in release.yaml (repo-wide grep for the hardened
  `for (i = 2` form returns the workflow alone) — no skill/reference prose to
  re-truth beyond t6's comment and the three identical step comments
  (:121-124, :304-307, :364-367) which cite "cf-77 r2 finding" and describe
  the per-ROW field-scan rationale (still true); none claims one-row-per-
  chart.

### A6. Fix-shape options (evidence, no decision)

- **(a) exit→next in the three loop copies (:125, :308, :368)** + t6 comment
  re-truth (+ optional t6 completeness teeth). Why "the release job lacks it"
  is the wrong frame: it HAS the hardened loop in all three jobs already —
  cf-77 r2 broke its completeness at :125's lineage. Minimal correct form
  keeps the cf-77 URL-shaped guard (per-row first URL field — a row with an
  empty REPOSITORY column still yields no pair) while restoring all-rows
  iteration — exactly TEST B'/F. Blast radius: 3 one-word edits in release.yaml
  (+ test comment/chunk prose); the bump job has NO helm at all, so the
  FF-only/single-writer laws and the curl-index retry (t20) are untouched;
  t5/t6/t12/t19 stay green byte-unchanged. Resilience: automatic — any future
  chart/dependency row is registered by derivation. New runner-side egress
  surface: the loop will now `helm repo add` (index-fetch at add time) five
  hosts never added before (jetstack, christianhuth, prometheus-community,
  go.temporal, crowdsecurity) — reachable from this seat (TEST F), NOT proven
  from the instance runners (owner-log watch, D37-class like the bump index
  fetch). Note the same 3 copies must ALL change or the unchanged-set paths
  stay a time bomb: a future renovate PR touching base/traefik/k8s-monitoring/
  postiz reddens `test-build` (:139 dep build) through the same missing repo.
- **(b) static complete URL list in the release/forgejo-publish/test-build
  steps.** Kills `helm dependency list` from those blobs ⇒ REDDENS t6 (:240)
  and t19 (:1043-1050) — both legs must be re-pinned, and the cf-77 empty-
  column guard narrative dies with the scan. Zero resilience: the next chart
  adding a NEW repo reproduces this exact class silently (add-loop passes,
  cr dies mid-glob) — the same staleness that made this bug survive 4 weeks
  unfired. Blast radius larger (2 legs rewritten + 3 step blocks), benefit
  none over (a).
- **(c) vendoring / committed Chart.lock+charts/*.tgz for the four victims.**
  Blocked by repo law first: `.gitignore:3 charts/**/charts` (and :4 for
  services) — committed tgz would need a gitignore inversion, breaking the
  "lockfiles committed, vendor files not" convention main's f418cc01c
  ("regenerate drifted Chart.locks via helm dependency update", 2026-11-21)
  just re-established. Even vendored, the discipline rots: renovate bumps
  Chart.yaml dep versions + regenerates locks (helm-values managers), and a
  stale tgz against a fresh lock sends cr's Build back through repo resolution
  (the TEST-C path) — so vendoring only moves the failure to the next renovate
  bump unless repo-add ALSO stays complete ⇒ (a) is still required underneath.
  t6/t19 would still demand the loop's tokens (`helm dependency list`/`helm
  repo add` presence), and ssh-gateway's t2 shape-pins keep base's entry
  honest regardless.

### A7. Not verifiable from this seat

- Instance-runner egress to the five newly-registered hosts (TEST F proves
  workspace-side only) — owner-side first-fire observation.
- The full owner run log (which changed set fed test-build; assumed not to
  contain base/traefik/k8s-monitoring/postiz since test-build passed).
- Whether any GitHub-side twin fire actually FAILED red between 2026-10-28 and
  the move (GH logs unreachable here — the index-staleness corroboration is
  repo-side only).

## Fire-3 discrimination (2026-11-24)

C08 (exit→next, D45) shipped to main as `f5c48dfbc` (committer 2026-11-23
22:00:26Z) and the owner's re-run then failed BYTE-IDENTICAL (same six packaged
charts, same `no repository definition for https://charts.jetstack.io,
https://charts.christianhuth.de`, exitcode 1). This section discriminates
H-A (stale re-run executing the ORIGINAL commit's workflow definition) against
H-B (C08 code ran; `helm repo add` failed for the two hosts and was swallowed).

**VERDICT: H-A with high confidence (three independent grounds below); H-B is
REFUTED as shipped.** C08's code has NEVER executed on any runner.

### F1. Graph elimination — no fresh fire of C08's code was possible

- Trigger law (`origin/main .forgejo/workflows/release.yaml:29-33`):
  `on: push branches:[main] paths:[charts/**]` ONLY — no workflow_dispatch
  (the shipped file has zero dispatch surfaces). A run of C08's awk requires a
  push to main whose diff touches charts/** AFTER f5c48dfbc.
- Walked `b89acb5df..f5c48dfbc` (parents single-chain: 217c49ad7→…→b89acb5df→
  9d12d4be0→d5099d36d→7549343d6→f5c48dfbc→87d3da0c3): the four post-fire-2
  commits (plans ×2, test t21, C08 dev) touch NO charts/** file (per-commit
  name-only sweep empty; f5c48dfbc = STATE.json + chunks/C08.md + release.yaml
  only). After C08: the only push is `87d3da0c3` — the pipeline's OWN bump,
  and workflow-token pushes NEVER re-trigger (`:174-177` "its push re-triggers
  no workflow — that non-re-trigger is the loop guard (R3/D5)"). origin/main
  tip IS 87d3da0c3 (22:02:12) with nothing after. ⇒ NO event that could run
  the new definition has ever fired, anywhere.
- Run-identity law (Forgejo Actions reference, v17.0 docs, fetched 2026-11-24):
  `FORGEJO_SHA`/`github.sha` = "the commit SHA that triggered the workflow",
  stable across re-runs; `FORGEJO_RUN_ATTEMPT` = "incrementing when the job is
  re-run". A re-run therefore executes the trigger commit's workflow YAML —
  for the fire-2 lineage that is `3303b711d` (18:00:15, the ONLY charts/**
  push in the 16:00-21:00 window; touched charts/forgejo-runner/values.yaml)
  or a pre-C08 SHA alike — all pre-C08 definitions.

### F2. The re-run fingerprint at 87d3da0c3 (H-A's positive evidence)

- Parent = exactly `f5c48dfbc` (created 76s after the C08 merge) — a run
  executing at 22:02 whose bump reset to the NEW main tip (`:180-181`
  fetch+reset --hard refs/remotes/origin/main) then pushed FF on top of it.
  That is bump-loop behavior under a RE-RUN, not a new event.
- Content identity: `87d3da0c3` = `chore(release): bump forgejo-runner`,
  Chart.yaml `1.0.3 → 1.0.4`; fire-2's own bump `b89acb5df` (20:46:23) =
  same message, `1.0.2 → 1.0.3`. Same single-chart CHARTS set re-derived from
  the same old event (detect diffs the OLD payload range :60-63), version
  recomputed strictly above tree per `:233-239` — the idempotent re-bump a
  re-run always produces. Author/committer identity `AN=tms` identical on
  both bumps (the triggering push's actor), the pipeline's own signature.
- The byte-identical log then follows automatically: re-run's release job =
  pre-C08 `exit` loop (its 16-name add set provably contains neither jetstack
  nor christianhuth — computed from the shipped buggy pipeline over the tree)
  running cr package against the NEW tree (base unchanged multi-row shape,
  still lock-with-unvendored) ⇒ fire-2 scout TEST-D state reproduced.
  STATE.json `fr2_close` already handed off "owner = micro-merge + RE-FIRE
  under UA-11" — a RE-FIRE (new push) was asked for; a RE-RUN happened.

### F3. Code-semantics elimination — the shipped C08 loop cannot produce this

- Quoted failure branch: there is NONE. All three copies are bare adds under
  `set -euo pipefail` — release step at `:300-313` (`set -euo pipefail` :302,
  carrier awk :308 with `next`, `helm repo add "$name" "$url"` :310 with no
  `|| warn`, no `|| true`, no continue); identically test-build `:117-130`
  (`:125` awk `next`, add at `:127`) and forgejo-publish `:360-373` (add
  `:370`). The step's own cf-77 comment (`:304-307`) NARRATES the law: "breaks
  this step under bash -e". So under the C08 definition a failing add reddens
  the STEP with helm's add error ("could not get …/index.yaml…" class), never
  reaching cr package; a succeeding add makes the named error IMPOSSIBLE
  (Build resolves lock URLs against the repositories file — all would match).
- E2E proof of the shipped loop from main's own text (f5c48dfbc file, fresh
  HOME, this workspace): 20 http(s) name+URL pairs added in 8.8s,
  `jetstack|christianhuth` count in `helm repo list` = 2, and ALL FOUR victim
  charts (base, traefik, k8s-monitoring, postiz) `helm dependency build` OK.
  ⇒ the owner's signature cannot come from the new definition under any
  add-outcome — only the old definition can produce it.

### F4. Host forensics (workspace-side, for the future fresh fire — UA-11)

| host | role | bytes (index.yaml) | cdn/ip | redirects | TTFB | add |
|---|---|---|---|---|---|---|
| charts.jetstack.io | base row2 (the named missing) | 467,336 | Cloudflare 104.18.31.120 | none, 200 direct | 0.036s | OK |
| charts.christianhuth.de | base row3 (the named missing) | 5,582,033 | Fastly/GHP 185.199.110.153 | none, 200 direct | 0.030s | OK |
| argoproj.github.io/argo-helm | base row1 (added even under the bug) | 1,713,552 | Fastly/GHP | none, 200 | 0.024s | OK |
| bjw-s-labs.github.io/helm-charts | 55 charts row1 (added, succeeded-era) | 201,811 | Fastly/GHP | none, 200 | 0.025s | OK |
| grafana.github.io/helm-charts | loki+k8s-monitoring row1 | 4,117,843 | Fastly/GHP | 200 | — | OK |
| prometheus-community.github.io/helm-charts | k8s-monitoring row2 (never attempted) | 6,832,371 | GitHub Pages | 200 | — | OK |
| go.temporal.io/helm-charts | postiz row2 (never attempted) | 84,295 | — | 200 | — | OK |
| crowdsecurity.github.io/helm-charts | traefik row2 (never attempted) | 69,765 | — | 200 | — | OK |

The owner's "christianhuth difference" intuition is NOT supported: both named
hosts serve 200 at `<url>/index.yaml` directly (no 301/path quirk: christianhuth
is at the ROOT path like every succeeding GitHub-Pages-class host — same Fastly
anycast family 185.199.x as argo/bjw-s/grafana, and AAAA records exist for all
three measured; jetstack is Cloudflare-fronted but small and fast). The REAL
difference between the two named URLs and the succeeding ones is purely
HISTORICAL: they are exactly the rows the old loop never attempted (fire-2 §A2).
Sizes say the slowest add is prometheus-community 6.8MB — also never-attempted;
if the instance runners' egress MTU flake (cf-6 8ef4545fe fought it with dind
--mtu=1450; EXPLORE §9-9 k3s MTU law) bites any big-index add on the first real
fire, it will bite LOUDLY at the Add-repositories step, with the retry-vs-not
tradeoff in F5/O1.

### F5. Spelling/collision audit (the "add succeeded under a different name,
Build still errors" class — O3 input)

- base Chart.yaml rows vs Chart.lock rows: byte-identical strings AND order
  (`['https://argoproj.github.io/argo-helm','https://charts.jetstack.io',
  'https://charts.christianhuth.de']` == lock) — no trailing-slash/oci-vs-https
  drift; cr Build names lock URLs verbatim, the same strings the add registers.
- Repo-wide: NO Chart.lock carries a URL absent from its Chart.yaml rows
  (sweep empty) — the lock-union == dependency-list-derived set EXACTLY
  (20 http(s) URLs, live diff `diff lockunion dlunion` empty) ⇒ O2's union
  offers zero coverage today, only parse-format robustness.
- 21 unique name+URL pairs, 21 names, 20 URLs: NO name maps to >1 URL (a
  `helm repo add` name-collision RED is impossible today); the one URL with 2
  names (grafana ← {loki, k8s-monitoring}) is harmless (entries coexist, URL
  match). NO chart has an oci-row-1-over-http-row-2 shape today (hazard sweep
  from §A2 stays clean).
- Lock freshness note: victim locks' `generated:` stamps (base 2026-11-21,
  traefik 11-17, k8s-monitoring 10-25, postiz 10-24) all match current rows
  (strings verified above); a digest-mismatch re-resolution, if any, uses the
  same URLs — not this failure's class.

### F6. Fix-shape options (fire-design, no decision)

- **O4 fresh-fire protocol (PRIMARY under H-A — the fix is already shipped;
  no code change is mandatory).** Owner validation = a NEW run on post-C08
  main: push ANY commit touching charts/** (the next renovate chart PR does
  it naturally; a 1-line charts/README edit is the token trigger). NEVER
  validate a workflow-code fix by re-running an old run — re-runs are forever
  pinned to the trigger commit's definition (F1). Blast: zero files.
  Optional O4b belt (recommended, tiny): an identity echo step opening the
  changes job — `echo "fire at sha=$GITHUB_SHA attempt=$GITHUB_RUN_ATTEMPT"`
  (both vars doc-proven, F1) so any stale re-run is self-identifying in logs.
  Blast: one added run-step in `changes`; t5/t12/t13/t19/t21 unaffected (t19
  pins commands in the OTHER three jobs; no `uses:`; no id needed — t13 only
  requires every referenced steps.<id> to exist); the D43 "vacated slots"
  ban is about installer/presence NAMES — 'Show run identity' matches none.
- **O1 loud + bounded retry (hardening for the first REAL fire).** Premise
  correction: the shipped loop is ALREADY loud — there is no warn-swallow to
  replace (F3; `:127/:310/:370` bare adds under `set -euo pipefail`). O1
  therefore means ONLY adding a bounded retry around `helm repo add` (e.g.
  3 attempts, short sleep, final loud failure), motivated by F4 sizes + the
  MTU/ECONNRESET egress class that spawned D33/D37. Blast: 3 byte-identical
  sites in one commit (all-three law, C08 Tasks); the awk carrier text stays
  byte-identical so t6/t21 keep green; t19's 'helm repo add' token still
  present; cost: a persistently-dead host takes 3× to redden (designed-loud
  tradeoff preserved — the step still dies, just later).
- **O2 lock-union pre-add.** Evidence: sets already IDENTICAL to the
  dependency-list derivation (F5) — no coverage gain; the gain is immunity to
  helm `dependency list` table-format drift (the `tail +2 | head -n -1`
  trailing-blank arithmetic was verified correct at BOTH 3.16.4 and 3.22.1 —
  fire-2 §A0/B'). Cost is real: dropping `helm dependency list` from the
  three jobs REDDENS t6 (:240 token) AND t19 (:1043-1050 presence law) and
  rewrites t21's carrier replay (it extracts and replays THE dependency-list
  carriers) — three legs re-pinned to defend a class with no live instance.
  Reject on evidence unless helm's table format actually breaks.
- **O3 normalization.** Nothing to normalize — the F5 audit is clean (no
  spellings drift, no collisions, no oci/http ordering hazard). Zero files.
- Non-option: the fire-2 §A6 (c) vendoring remains gitignore-blocked
  (.gitignore:3) and unchanged in verdict.

### F7. The discriminating ONE-LINEs for the owner (read off the run page NOW)

1. Run header: the SHA it is bound to + attempt. A re-run shows the OLD
   trigger commit (fire-2 lineage = `3303b711d` "fix(containers): forgejo-runner
   bake takes tools from digest-pinned OCI stages", pre-C08) with attempt 2+
   under the SAME run number. SHA ≠ post-C08 ⇒ H-A confirmed outright.
2. Release job → `Add repositories` step log: search for `cert-manager` or
   `gateway-api-crds`. The old loop's set (16 pairs, computed) contains
   NEITHER; the C08 loop adds both names before cr ever runs. Absent ⇒ old
   definition executed ⇒ H-A. Present + failed ⇒ H-B (would additionally have
   reddened the STEP, not cr).
3. Corroboration already visible: the `87d3da0c3` bump on main 76s after the
   C08 merge, bumping the same single chart one patch above the old run's bump
   — the re-run's own footstep (F2).

### F8. Not verifiable from this seat

- What the owner actually clicked (re-run vs fresh UI run) — F7/1 answers it
  instance-side; repo-side, no fresh-fire trigger event exists to run the new
  code, which is what the verdict rests on.
- Runner-side egress to the four never-attempted hosts (jetstack+christianhuth
  measured workspace-side in F4; prometheus-community/go.temporal/crowdsec
  likewise) — the UA-11 first-real-fire watch (STATE ua11_watch) stays open.
- Forgejo UI exactness of "re-run reuses the trigger SHA's workflow" — the
  docs quote the sha/run_attempt semantics; the repo-side elimination in F3
  makes the verdict independent of this residual.

## Rename surface (2026-11-25): release.yaml -> build-charts.yaml

Rename-scout round (fresh launch, cwd `cf-55-feat-helm-builds-to-forgejo-rebuilt` at main `3f21e85e8`). Method: repo-wide greps of `release.yaml` and `Release Charts` (57 live-surface hits with `.agents/` excluded), per-surface reads of every hitting suite/file, Forgejo Actions reference docs webfetch for name semantics. Classes: **HARD** = code/tests that go RED if missed; **SOFT** = prose that lies if stale (no red leg unless a pin reads the token); **FROZEN** = ticket records — never rewrite.

### A. Hard pins (break if missed)

| Surface (file:line) | What it pins | Change type | Red leg if missed |
|---|---|---|---|
| `.forgejo/workflows/release.yaml` (429 lines; header token :1; `name: Release Charts` :28; push-only trigger :29-33) | the workflow itself | `git mv` -> `.forgejo/workflows/build-charts.yaml`; keep content byte-stable (D3/E anchor note); `name:` field is display-only (F) — change to match is the owner's style call, nothing reads it | — (the subject) |
| `tests/services/forgejo-release.sh:63` | `WF=".forgejo/workflows/release.yaml"` — t1 `[ -f "$WF" ]`, every leg reads $WF | rewrite string | whole suite hard-exits at t1 (all 21 legs) |
| `tests/services/forgejo-release.sh:88` | composed twin-absence check on `.github/workflows/release.yaml` | LEAVE — the deleted GitHub twin keeps its historical name forever | none (correct as-is) |
| `tests/services/forgejo-ci-surface.sh:67` | `FJ_SET` = exact SET of file NAMES in `.forgejo/workflows/` (os.listdir, not paths) — enumerates `'release.yaml'` | rewrite member to `build-charts.yaml` (FAIL msg L86 prose too) | ci-surface t1 red (set equality); t3–t7 never run (hard-exit) |
| `tests/services/forgejo-ci-surface.sh:94` | `.github` inventory must NOT hold `release.yaml` | LEAVE (twin name unchanged, still deleted) | none |
| `tests/services/forgejo-ci-surface.sh:247` (t7) | `need('release.yaml' in ref and 'Forgejo' in ref)` over `skills/helm-chart-creation/references/chart-templates.md` | rewrite t7 token AND chart-templates.md:30,154 in ONE change | ci-surface t7 red |
| `charts/llama-swap/tests/strata_testlib.py:51` | `RELEASE_WORKFLOW` path constant, read by `test_strata_untouched.py::test_c01_release_workflow_carries_no_strata_reference` (S.read raises on absent) | re-pin path | strata pytest leg errors (the Q-C pristine guard) |
| `tests/pipeline-push-pr/surface.sh:215` | `contract ci-on-push … 'release.yaml'` — needle must appear in SRC `.rulesync/skills/pipeline-push-pr/SKILL.md` and GEN `.opencode/skills/pipeline-push-pr/SKILL.md` (:51-52; needle-substring semantics verified :80-110) | rewrite needle + skill source together (`build-charts.yaml` does not contain `release.yaml`) | pipeline-push-pr P3[AC3] ci-on-push red on both carriers |
| `.rulesync/skills/pipeline-push-pr/SKILL.md:24` + `.opencode/skills/pipeline-push-pr/SKILL.md:27` | the push-effects law ("the forge `release.yaml` fires on push to prod main (paths `charts/**`)") every -pr session loads | rewrite string in source; `rulesync generate`; commit source+mirror in one commit | the row above; `rulesync generate --check` drift |
| `tests/agent-board-coord/agents-md.sh:467`, `gate.sh:1027`, `rulesync-surface.sh:691` (+ their truth-comments :378/:401, :931/:948, :608) | the cf-55 arm's per-file allow-set names `.forgejo/workflows/release.yaml` + composed `".github/"workflows/release.yaml` | CONDITIONAL HARD: if the rename runs as a board-coord ticket, its own arm must admit the NEW workflow path, the rename ticket's plan folder, and `charts/prowlarr/Chart.yaml` (NOT under any wildcard); git-mv'd suites ride `tests/*`; new workflow file rides nothing — join it explicitly ("A replan-added file joins THIS line" convention) | c7 / t14 / c* fail "path outside C04's in-scope set" on the unadmitted new path |
| `AGENTS.md:459` + `:497` and twin source `.rulesync/rules/overview.md:457` + `:495` | the bump law ("`release.yaml` runs on the prod Forgejo Actions") and the ROLE law's narrow five-workflow enumeration | rewrite string in overview.md, regenerate AGENTS.md, commit the pair; KEEP sentence shapes for the substring-pins (H) | no name-token pin found; sloppy prose rewrites trip ci-surface t5/t7 token lists and builder-bootstrap b9 (five/.forgejo/builder-bootstrap/narrow block; four-workflow ban regex) — and the stale name misinforms every session that loads AGENTS.md |

### B. Soft prose (lies if stale; no red leg)

| Surface (file:line) | Mention | Change type |
|---|---|---|
| `.forgejo/workflows/main-sync.yaml:121` | "(release.yaml:54 precedent)" | rewrite name -> `build-charts.yaml:54`; the :54 anchor (`EVENT_SHA: ${{ github.sha }}`) stays TRUE only if the file keeps 429 lines (pure mv or same-line-count edits) |
| `tests/services/forgejo-main-sync.sh:438`, `:458` | same `release.yaml:54` cites in a FAIL message + comment | rewrite prose (legs parse main-sync.yaml only) |
| `tests/services/forgejo-containers-build.sh:2086-2088` | x4 header: "release.yaml left this fence … moved to .forgejo/workflows/release.yaml" | dated reword or leave-as-history; x4's legs check the five `.github` siblings — unaffected |
| `tests/services/forgejo-ci-surface.sh:7,8,12,86,88,92,97,114,172,197`; `forgejo-release.sh:2,167,282`; `forgejo-packages.sh:5` | comments + ok/FAIL message prose naming the workflow/suite | rewrite prose in the same pass |
| `.rulesync/skills/role-planner/SKILL.md:60` + `.opencode/skills/role-planner/SKILL.md:61`; `role-code/SKILL.md:60` + `:61` | "the forge `release.yaml` bumps Chart.yaml" | rewrite source + regenerate mirrors (no token pin found over these) |
| `skills/helm-chart-creation/references/chart-templates.md:30,154` | name prose AND the template line copied into every future Chart.yaml comment | rewrite (paired with hard t7 — see A) |
| `charts/prowlarr/Chart.yaml:3` | "initial only — release.yaml auto-bumps patch on merge to main" — ships inside the packaged tgz; only chart with the line (verified) | rewrite string = touches `charts/**` -> first-fire coupling (E) |
| `containers/forgejo-runner/Dockerfile:61` | "cr at the version+digest pair release.yaml pinned" | rewrite comment |
| `containers/forgejo-runner/README.md:68` | names the suite path `tests/services/forgejo-release.sh` | true iff the suite keeps its name; re-pin if the suite is git-mv'd (C) |
| `custom-values/infra/prod-values.yaml:87` | "(release.yaml's forgejo-publish leg)" | rewrite comment |
| `tests/cf96-deploy/readback-runbook.md:88` | "release.yaml owns chart versions" | leave-as-record (dated historical runbook) or bracketed correction — plan's call |
| `charts/amd-gpu/tests/test_provenance.py:42`; `charts/radiance/tests/test_contract.py:3,46`; `tests/multi-repo/ha-chart.sh:385`; `tests/multi-repo/mosquitto-chart.sh:175` | FAIL-message prose ("release.yaml owns bumps") | rewrite optional; message strings, no file reads |
| `charts/llama-swap/tests/test_strata_untouched.py:1,4,10,35,64` | docstrings/messages; L10 "its name survives the cutover" becomes FALSE on rename | rewrite docstrings with the testlib re-pin |

### C. Suite naming (the launch's question)

`tests/services/` pairs `forgejo-<workflow>.sh` for every Forgejo workflow: `forgejo-main-sync.sh`, `forgejo-renovate.sh`, `forgejo-containers-build.sh`, `forgejo-builder-bootstrap.sh`, `forgejo-release.sh`. Precedent-consistent move: git mv the suite to `forgejo-build-charts.sh` alongside A1. Re-pin surface is small — ci-surface comments (L4,172,197), `containers/forgejo-runner/README.md:68` — and NO CI workflow or other suite executes or reads the path (grep-verified: only the README + ci-surface prose). Keeping the old suite name has zero red legs but breaks the pairing precedent. Decision for the plan; both costs enumerated.

### D. Does anything KEY on the workflow NAME or FILE? No.

- `Release Charts` appears only in the workflow itself (L1 comment, L28 `name:`). Docs: the `name:` is display-only in the Actions tab, falling back to the file name — safe to change or keep; nothing machine-reads it.
- File name keys: trigger is push-only + `paths: charts/**` (release.sh t2 pins `set(trig)=={'push'}` — do NOT add workflow_dispatch while editing, it reddens t2); no badge URLs anywhere; cr writes use `--owner/--git-repo/--package-path .cr-release-packages` (cr's own default staging dir — the `.gitignore:2` entry is NOT workflow-derived); gh-pages/`:yy.mm.N` artifact paths independent; ArgoCD never sees workflow files; `renovate.yaml`, `containers-build.yaml`, `builder-bootstrap.yaml` contain zero release.yaml mentions (verified); `main-sync.yaml:121` comment is the only in-`.forgejo` cross-cite.
- Instance side: workflows are discovered from the repo tree at the pushed SHA — no Forgejo config/registration change for a rename.

### E. Runtime / first-fire effects

- The merge landing the rename fires `build-charts.yaml` only if that merge touches `charts/**` (paths filter). If the prose pass edits `charts/prowlarr/Chart.yaml:3`, the SAME merge is the first fire and mints one benign prowlarr patch-bump commit (precedent: STATE `post_merge_adaptation` — "expect green + one benign forgejo-runner bump commit").
- ROLE guards read `vars.ROLE`, not the file name; bump loop / DUAL publish / credential topology unchanged by a byte-stable mv.
- Anchor discipline: three live cites of `:54` — keep 429 lines (mv + same-line-count header/name edits only) so reworded cites stay true.

### F. Run history across a rename (partially grounded; OQ)

- Grounded (Forgejo Actions reference docs, webfetched 2026-11-25): each run carries `workflow_ref` = `owner/repo/.forgejo/workflows/<file>@refs/heads/<ref>` — the PATH recorded at trigger time; the per-workflow dispatch API keys on workflow name (irrelevant here — no dispatch trigger); `name:` is display.
- NOT verifiable from the repo seat: whether the Actions UI's per-workflow history view groups by that recorded path (old runs then vanish from the new file's view but remain in All-workflows and per-commit links, run IDs intact — the cf-55/cf-6 records cite runs 94/97/101/106 by number) or re-resolves to the current tree. Inference says the former; confirm via research or accept history-per-run-id.

### G. Frozen history (never rewrite — list what carries mentions)

- 105 record files under `.agents/plans/` cite `release.yaml` (count verified; the enumeration is representative): all of this ticket (plan file, DECISIONS, RESEARCH, FRICTION, STATE, EXPLORE incl. its own §1a/§8/A1 sections, chunks C01–C08); cf-6 `debug-forge-runner-docker` (+-1), `feat-builder-bootstrap` (+-2/-3/-4), `feat-forgejo-container-builds-1`; cf-135, cf-139, cf-143, cf-144, cf-145, cf-119, cf-104, cf-105, cf-93, cf-95, cf-97, cf-77 (both folders), cf-58; `2026-10-refactor-forgejo-runner-per-instance`, `2026-10-feat-forgejo-ssh`, `2026-10-feat-forgejo-infra-and-runner`, `2026-10-feat-llama-swap-config-generation`, `2026-10-feat-coder-workspace-rebuild`, `2026-10-bug-llama-swap-echo-proxy-port`, `2026-10-bug-kubernetes-mcp-toml`, `2026-10-dep-wekan-v12-upgrade`, `2026-10-debug-flash-next-vulkan-oom`, `2026-11-feat-radiance-multi-instance`, `2026-11-feat-seaweedfs-debug-skill`, plus the bare plans-root files (`2026-09-*`, `2026-10-12-feat-add-dev-service`, `2026-10-20-debug-gpu-*`, `2026-10-28-chore-friction-followups-cf-77-r2`, `2026-11-02-debug-proxy-remote-*`). They cite the pre-rename path honestly — append-only law; the plan must exempt them explicitly.
- `.agents/skills/` vendored third-party: `gitops-workflows/references/repo_patterns.md:140` (generic tree diagram), `ha-integration-dev/references/publishing.md:386` (generic GitHub example) — SHA-pinned vendors, never hand-edit (skills-lock.json law).
- `.agents/notes/`: zero mentions (grep-verified). `charts/llama-swap/tests/evidence/c05_expected_evidence.yaml:11`: a historical evidence artifact — leave as record.

### H. Rewrite-law traps for the test wave

1. ci-surface t3 (`STALE_PAT` L109, composed so the suite never self-matches) hard-exits if a PLAIN `.github/workflows/release.yaml` literal lands in any tracked file under `skills tests containers .rulesync .opencode charts services custom-values`. Every rewritten reference to the deleted GitHub twin must keep the sanctioned forms: prose "the GitHub release twin", `os.path.join(...)` in python, the composed `".github/"workflows/release.yaml` alternation in the coord allow-cases. Writing the plain literal = t3 red and t4–t7 masked.
2. ci-surface t4: every `docker-build` mention on the carrier routes must keep its workflow_dispatch/manual/fallback co-word — the pipeline-push-pr SKILL and AGENTS lines pass today; preserve while rewriting the same sentences.
3. builder-bootstrap b9 item 5: never introduce "four … .forgejo"-shaped phrasing into overview/AGENTS/README/skill docs (the four-workflow ban regex); the family stays five, only a member changes its name.
4. NO global `s/forgejo-release/.../`: the token `forgejo-releases` is a Renovate DATASOURCE name (`renovate.json:136,141`, `containers/coder-workspace/Dockerfile:66`, `tests/renovate/dockerfile-pins.sh:81,91`, `tests/renovate/chart-yaml-legs.sh:254`, `tests/coder-workspace/image-structure.sh:48`) — a sed would break live pin contracts. All edits surgical per the tables above.
5. Collision: `build-charts` is unused in the tree (the only grep hits are "helm dependency build charts/…" verb-phrase false positives); no existing file to collide; ci-surface t1's exact-set accepts the renamed member once L67 changes.

## Round-5 scout (2026-11-26)

Fresh Exploration relaunch on the owner's round-5 directive (STATE `directive` :87). cwd `cf-55-feat-helm-builds-to-forgejo-rebuilt`, HEAD `2b6ad58cc` (plans commit riding origin/main `52d3b5c45`, which contains the owner's `aeda85f86` — `git merge-base --is-ancestor` verified). Classes reused from the Rename-surface round: HARD (red if missed) / SOFT (prose lies) / FROZEN (records, never rewrite).

### A. containers-build.yaml AS SHIPPED (aeda85f86 "last-built marker and coder-workspace node fix")

**The marker is a branch ref of this repository, Forgejo-local, not a tag**: `refs/heads/ci/containers-built` — header law `:20-23` ("belongs to no registry… advanced by the workflow itself after a fully-green push build, and it gates nothing — it only says where the already-published history ends") and `:44-48` (the advance wears no PAT — the checkout's own same-repo credential, "the release.yaml idiom"; GitHub never receives it because main-sync mirrors `refs/heads/main` alone).

- **Read**: `resolve last-built marker` step (`:133-165`) — `git ls-remote origin refs/heads/ci/containers-built` at `:147`. Non-push events emit an empty `sha=` output (`:143-146`); missing marker → empty output = the bootstrap state (`:148-153`); non-sha answer → fatal (`:154-157`); present-but-unreachable (history rewrite) → fatal with owner verbs, explicitly NOT silently downgraded (`:158-164`).
- **Who advances / when**: the `advance-marker` job (`:464-483`), `if: forgejo.event_name == 'push' && needs.build-release.result == 'success'` (`:465`) + `needs: [detect-changes, build-release]` (`:466`). The condition is the matrix-green law: a skipped build-release (empty set) yields `skipped`, not `success`, so a nothing-built push does not move the marker. The step pushes plain `git push origin HEAD:refs/heads/ci/containers-built` (`:483`) with no force form — git's non-FF refusal IS the monotonicity contract (`:477-482`); its checkout pins `fetch-depth: 0` (`:469-473`). HEAD here = the event sha commit — the marker lands at the trigger commit, not past it.
- **The marker..sha walk**: detect step `:166-205` feeds `MARKER_SHA` (`:175`, the resolver's output) into `bash scripts/forgejo-container-detect.sh detect` (`:182`); the verdict echo names all endpoints incl. `marker=` (`:186`). Script push-arm base chain (`forgejo-container-detect.sh:60-80`): **marker** (`:63-66`, `a=MARKER_SHA b=SHA`) → **tip-only** first-push (`:67-75`, all-zero before → `HEAD^..HEAD` + `::warning::` announce) → **before** fallback (`:76-79`); empty `EVENT_BEFORE` dies first (`:52-58`, "no push payload sends one"). `marker==sha` diffs empty and reads as the verified-empty INFO line, never an anomaly annotation (workflow `:199-204`, suite header `:77-79`) — that is the designed idempotence for a re-invocation at the same sha. The PR arm (`:38-49`) anchors on `git merge-base` of payload base/head and carries no base token (byte-frozen PR posture); dispatch names its list outright (`:32-35`).
- **fetch-depth: 0** on detect (`:117-127`): range endpoints must resolve locally (marker..sha or before..sha); measured 21.23 MiB / 1,849 ms full fetch; the build jobs stay shallow because they never diff. The `before..sha` fallback is the marker-MISSING state only (`:53-54`, `:148-153`).
- **The coder-workspace node fix (the other half of aeda85f86)**: `containers/coder-workspace/Dockerfile` — what broke: the `datasource=node-version` renovate contract emits BARE versions (`renovate.json:136,141` capture; `ARG NODE_VERSION=26.12.1` at `:41`), but nodejs.org hosts only `v`-prefixed dist paths — the old layer interpolated `${NODE_VERSION}` bare, 404ing every fetch, AND its `grep … | sha256sum -c` fed empty input on an unmatched grep, which exits 0 silently: "kept this layer 0-green/15-red in CI from 3713c83d1 (2026-10-20) with every shape-level check green" (comment `:128-137`). The fix: `v` at the USE sites (`:138-143`), ARG stays bare, capture the grep and `[ -n "$node_shasums" ]` refuse emptiness before `sha256sum -c` (`:140-141`), assertion `test "$(node --version)" = "v${NODE_VERSION}"` (`:143`). Fenced by `tests/coder-workspace/image-structure.sh` c7a/c7b counting legs (`:352-368`: 2 `dist/v${NODE_VERSION}` sites + 0 bare; 5 `node-v${NODE_VERSION}-linux-x64.tar.xz` + 0 bare) — 219 lines added there in the same commit.
- **What a shared-marker-branch RENAME touches** (directive 2): the ref string lives in exactly TWO files (`grep -rl 'ci/containers-built'` → the workflow + its suite). Workflow: `:147` (ls-remote), `:483` (push), header prose `:20-23,:50-52`. Detect script: ref-AGNOSTIC (consumes `MARKER_SHA` env, `:10-16`) — no change for a rename. Suite `tests/services/forgejo-containers-build.sh`: `REF = 'refs/heads/ci/containers-built'` `:1252`; t16 (advance-job shape, byte-pin of the push stmt incl. the ref, no-force scan `:1295-1317`); t17 (executes the body against a scratch remote — creates/verifies `refs/heads/ci/containers-built` at `:1402-1429`, plus the ls-remote stub `:1453`); resolver legs (t13 env map `:947-963`, d16-d19 chain per header `:51-57`). The gated docs carry only the `marker..sha` VOCABULARY (x5 tuples, suite `:17-22` DOCS body) — no ref-name pins there.
- **THE KEY INTERACTION for a SHARED branch**: t16's exclusivity walk (`:1306-1312`) fails if ANY OTHER `.forgejo/workflows/*.yaml` names the ref ("the marker ref lives in containers-build.yaml only"). A shared marker branch used by build-charts + a future coder-templates builder violates this pin BY DESIGN — that leg must be re-scoped (allow-set over the named builder files) as part of the adaptation, else every later builder that names the ref reddens t16.

### B. build-charts.yaml — current detection, the version-regex fire, and the chart states

- **Current detection has NO marker**: `changes` job `:39-83` diffs the PUSH PAYLOAD `before..sha` (`env EVENT_BEFORE/EVENT_SHA :56-57`; `git diff --name-only "${EVENT_BEFORE}" "${EVENT_SHA}" -- charts/` `:66`), first-push/all-zero-before → `HEAD^ HEAD` (`:63-64`); CHARTS = `cut -d/ -f2` filtered to DNS-safe names (`:70-71`) admitted by `[ -f "charts/$c/Chart.yaml" ]` (`:73-77`). Trigger is `push branches:[main] paths:[charts/**]` ONLY (`:32-36`). Suite pins: `forgejo-build-charts.sh:92` WF literal; t2 `:144-157` `set(trig)=={'push'}`, `branches==['main']`, `paths` covering `charts/**` — "no dispatch, no PR"; the empty-`event.before` guard legs `:1017-:1039` ("Forgejo payloads can OMIT event.before" — A3; "the same guard containers-build.yaml ships").
- **The fire's exact regex** — `test-build` job, step "Patch-bump Chart.yaml (local, never pushed)" `:103-119`:
  `:111` `m = re.search(r"(?m)^version: (\d+)\.(\d+)\.(\d+)$", text)` — the terminal `$` admits nothing after the third number group: **any trailing comment kills the match**, and `:113` raises the observed message verbatim: `raise SystemExit(f"{path}: top-level version: is not MAJOR.MINOR.PATCH")`. The owner's "at the bump step" = this test-build matrix leg (the bump JOB never ran — see outcome below).
  The bump-leg parse has the SAME class of vulnerability: `:258` `re.search(r"(?m)^version: (\S+)$", text)` — a comment makes the whole line non-matching → `:260` `"{path}: no top-level version: line"` (different message, same `$`-anchor cause); `ver()` `:217-221`/`:267-269` then guards non-semver VALUES ("version X is not MAJOR.MINOR.PATCH"). `(?m)^version:` anchors column 0, so indented dependency pins never match — a comment-tolerant fix at BOTH sites must keep the column-0 anchor (traefik-style wrapper collision law, comment `:223-230`).
- **charts/prowlarr/Chart.yaml:3 CONFIRMED ON THE VERSION LINE**: `version: 1.0.1  # initial only — build-charts.yaml auto-bumps the calendar version on merge to main` — the comment predates C11 (`git show 0404a906f:charts/prowlarr/Chart.yaml` shows it with the old `release.yaml` wording on the same line); C11 rewrote the token in place ("prowlarr clause verbatim", STATE r4 dev record `:351`); the seed-law origin is C10/`1b2a4ba28` (r4f1). So prowlarr's line has ALWAYS been unparseable by `:111` — it simply never entered the detected set until C11's own merge touched `charts/prowlarr/Chart.yaml`.
- **charts/llama-swap/Chart.yaml:3 clean**: `version: 1.0.40` (no comment) — its test-build leg passes. `git log --oneline -5 -- charts/llama-swap/Chart.yaml`: all five are "Commit from GitHub Actions (Release Charts)" (tip `8840634f1`) — **llama-swap has NEVER been calendar-bumped on Forgejo**. prowlarr's log: `3e0d4c324` (C11) → `0404a906f` → `e6117f54b`. **Outcome of the Nov-25/26 fires**: prowlarr test-build leg red → `bump` `needs: [test-build, changes]` (`:152`) skipped → `release`/`forgejo-publish` `needs: [bump, changes]` (`:332`, `:409`) skipped → ZERO bumps: `git log --grep='chore(release)' --since=2026-11-24` names no new bump commit (last are `a28e53189` radiance and the Nov-23/24 `87d3da0c3`/`b89acb5df` forgejo-runner fires, all pre-C11). Neither {llama-swap, prowlarr} — the AC5 RE-TRUTH expected set (STATE r2 review `:353`) — reached its first calendar release.
- **Where a marker..sha adaptation lands (mirroring A)**: (i) a marker-resolver step in `changes` before `Detect changed charts`, emitting `MARKER_SHA`; (ii) the push-arm base chain becomes marker→(payload fallback / none) — note directive 4 removes the push trigger entirely, so under a `workflow_call` there IS no `event.before`: the marker becomes the ONLY push-side base (the containers-build bootstrap fallback `:148-153` analogue must decide what "no marker yet" means for a called run — the caller's sha vs marker); (iii) an `advance-marker`-twin job keyed on `release` + `forgejo-publish` success (containers-build's t16 laws — no ROLE vocabulary, no `secrets.`, plain push, `fetch-depth: 0` — are the shape precedent). Loop-guard law change to record: today the bump's own push-to-main "re-triggers no workflow — that non-re-trigger is the loop guard (R3/D5)" (`:174-177,184-185`); once main-sync calls the builders, the marker's `marker==sha ⇒ verified-empty set` property (A) must become the loop guard in practice — a called run at an sha at-or-behind the marker builds nothing.
- Related pre-existing coupling for E: `charts/coder/coder-templates/**` sits UNDER `charts/**`, and `:70-77` `cut -d/ -f2` collapses it to `coder` — `[ -f charts/coder/Chart.yaml ]` passes, so a pure Terraform-template push today enters the CHARTS set and bumps/publishes charts/coder (1.0.9). Any three-builder split must decide this filter.

### C. main-sync.yaml + what "calling the builders" can mean on THIS Forgejo

- **Current shape** (`.forgejo/workflows/main-sync.yaml`, 124 lines): triggers `push: branches: [main]` + `workflow_dispatch: {}` (`:42-45`); jobs `push-gh` (`:48-67`, ROLE `contains(vars.ROLE,'prod')` `:49`, plain `git push … HEAD:refs/heads/main` through `vars.PUSH_URL_GH`/`secrets.PUSH_TOKEN_GH` `:60-67`), `push-dev` (`:69-88`, twin to `PUSH_URL_DEV`/`PUSH_TOKEN_DEV`), `sync-fanout` (`:90-124`) — **needs-graph today: `sync-fanout.needs == ['push-gh']`** (`:101`, "the race resolution, cf-139 R1 option (c)"); the org-secret vault `secrets.ARGOCD_SYNC_TOKENS` (`:112`) with designed skip-green on unset (`:117-119`) and the UN-guarded `python3 scripts/argocd-fanout.py` call (`:124`). Header law `:28-40`: the fan-out IS the webhook (no external webhook).
- **Instance Forgejo version — LIVE-probed** (readonly k8s MCP): both deployments run image `code.forgejo.org/forgejo/forgejo:15.0.10-rootless` (infra `infra-forgejo`, dev `dev-forgejo`). So the Actions semantics to trust are the **v15.0 docs line** (`forgejo.org` labels v15.0 "LTS (v15.0.12)"); code.forgejo.org itself (a different instance) answers `/api/v1/version` = 17.0.2~gitea-1.22.0 — irrelevant to our runners. The repo-side pin pair: wrapper chart `charts/forgejo/Chart.yaml` appVersion 15.0.9, dependency chart 17.3.1 (chart ≠ app version; the deployed image is what Actions honors).
- **`on: workflow_call` EXISTS on v15.0 — the orchestration answer.** Docs: https://forgejo.org/docs/v15.0/user/actions/reference/ sections `on.workflow_call`, `on.workflow_call.inputs`, `on.workflow_call.outputs`, `jobs.<job_id>.uses`, `.with`, `.secrets`: same-repo form `uses: ./.forgejo/workflows/x.yml`; **workflow expansion** when the caller omits `runs-on` ("the target workflow's jobs appearing in the UI as separate jobs… permit[t]ing the jobs to run on separate runners with their own runs-on fields") — exactly the "call both builders, each with its own matrix/jobs" shape; inputs typed boolean/number/string; outputs declared in `on.workflow_call.outputs` mapping job outputs; `secrets: inherit` or per-key maps; cross-instance URL form is the documented expansion DISABLE. Known limit (docs footnote 1): `on.workflow_call.inputs.*.default` cannot reference `inputs` (codeberg.org/forgejo/forgejo/issues/9768). The `on:` mapping is a set of event subkeys — containers-build already co-lists push+PR+dispatch (`:87-103`), so co-listing `workflow_call` beside kept `pull_request`/`workflow_dispatch` is the documented shape.
- **`workflow_run` DOES NOT EXIST on v15.0**: the reference's `on` enumeration covers push, issues, issue_comment, pull_request, pull_request_target, release, schedule, workflow_call, workflow_dispatch — no workflow_run section (same for `repository_dispatch`/`check_run` classes — absent). Cross-workflow "fire after another workflow completes" is not available; needs-graph (workflow_call) or API polling are the only two shapes.
- **API alternative — primitives probed LIVE against git.spencerslab.com (this repo, unauthenticated GET/HEAD existence probes)**: `GET /api/v1/repos/CuratedForest/SpencersLab/actions/runs` → **200** (`workflow_runs[]`, e.g. id 324 = round-4 plans run); `…/actions/runs/1` → **200** (per-run object reachable, public repo ⇒ polling needs no auth for a public repo; write-side scopes below); `…/actions/workflows` → 404 and `…/actions/jobs/1` → 404 (**these routes do not exist in 15.0.10**); `…/actions/workflows/build-charts.yaml/dispatches` → **405 Method Not Allowed** (route EXISTS, POST-gated) — matching the docs' dispatch endpoint for `workflow_dispatch`: `POST /repos/{owner}/{repo}/actions/workflows/{workflowname}/dispatches` (v15.0 reference, `on.workflow_dispatch` section). Auth pieces documented: `FORGEJO_TOKEN`/`secrets.GITHUB_TOKEN` ("the unique authentication token automatically created for duration of the workflow") and `FORGEJO_API_URL`/`forgejo.api_url` (v15.0 reference env table); token-granularity for API WRITES is NOT documented on v15.0 — the `pull_request_target` section proves the auto token has repo write "permission" broadly, but a dispatch-write probe (in a throwaway workflow or the UI test repo) is the implement-time check. **Lab precedent: none for the Actions API** — repo-wide grep finds only `scripts/argocd-fanout.py:255,270` calling ArgoCD `/api/v1` with bearer tokens, and package-API curls (build-charts `:469-496`, containers-build registry reads); a dispatch+poll job would be the first Actions-API consumer here.
- **Read of the design hinge**: workflow_call is real on 15.0.10 and keeps the wait inside the needs graph (`sync-fanout.needs: ['push-gh', <caller jobs of both builders>]`), preserves UI expansion per builder, and needs no token probes; the dispatch+poll fallback buys nothing except decoupling file identity and would re-invent sequencing in shell with an unproven write scope. main-sync suite HARD re-pins either way: `forgejo-main-sync.sh:116-117` (job SET exactly `{push-gh,push-dev,sync-fanout}` — a `uses:` job is a fourth/fifth file key), `:341-342` (`needs == ['push-gh']` EXACTLY), `:131` per-job byte-guard over the enumerated names, `:351` (fanout checkout has NO `with:`) — and the `release.yaml:54`→`build-charts.yaml:57` cite precedent (`main-sync.yaml:121`, suite `:438/:458`) shows line-anchors in comments go stale silently.

### D. Runner scale (directive 5: "runners scale to 10")

- **One release = one registration = one 1-replica STS, by written law**: `charts/forgejo-runner/Chart.yaml:3` ("one 1-replica StatefulSet per release"), header `values.yaml:1-9` ("Each release runs exactly one pod, one headless Service and one ExternalSecret — every resource is named after the release"). The replicas key: `values.yaml:157-162` under `app-template.controllers.runner`: `type: statefulset`, `replicas: 1` with the decision-B1 comment `:158-160`: "Single replica on purpose: one (uuid, token) pair must map to exactly one pod. **Scaling means more runner records, never more replicas of one identity** (decision B1)".
- **The suites pin it**: `tests/services/dev-forgejo-runner.sh:303-304` (t2: per release `spec.replicas != 1` → bad, message recites B1; `:319` ok: "replicas 1, VCTs exactly data (2Gi) + docker-data (10Gi), both RWO local-path"); `tests/services/gpu-forgejo-runner.sh:257-258` (g2: same, "one uuid/token pair maps to one pod"), ok `:272`. A `replicas: 10` render reddens BOTH legs unless they are re-ruled and re-pinned.
- **`capacity` is hard-coded, not values-driven**: `charts/forgejo-runner/templates/secret-runner.yaml:88` — rendered `config.yaml` carries `runner: {capacity: 1}` (with `timeout: 30m`, `shutdown_timeout: 5m` `:91-93`). This is the "lab runner has capacity 1, so matrix cells serialize through one pod" fact quoted in the containers-build header `:75-77`. Neither runner suite greps `capacity` today (verified) — scaling parallelism per pod would be a NEW values key + config change, un-pinned.
- **Per-release slices carry NO replicas override today**: `services/dev/prod/values.yaml:116-119` + slice `:178` (labels-only override `:194-195`), `services/gpu/prod/values.yaml:119-122,271-273` — replicas lives solely at the chart default, so `10` lands on the chart and both t2/g2 legs. Resource envelope per pod (`values.yaml:246-252` dind: requests 100m/256Mi, limits 2cpu/4Gi; `:281-287` runner: 250m/512Mi, limits 2cpu/4Gi) and the VCT shapes (data 2Gi + docker-data 10Gi, RWO `local-path`, `:165-188`) multiply per pod under a 10-replica STS: 10×(12Gi) local-path PVCs per release, each pinned to whichever node the local-path provisioner picks; all 10 pods mount the SAME ExternalSecret identity (one uuid/token) — the B1 violation is not cosmetic, it is the registration model. The three design shapes the plan can price: (a) `capacity: N` on one record (in-pod parallel jobs; needs a values key; dind carries it — limits are per pod), (b) MORE RUNNER RECORDS = more releases/registrations (the B1-sanctioned scaling; each a 1-replica STS + registration ceremony on the instance), (c) job-count autoscaling — the owner already minted the follow-up card (STATE `directive` :87 item 6), so a plain replicas=10 contradicts a documented decision and two test legs; call it out as a ruling-in-transit, not a silent edit.

### E. Coder templates — location, deploy, and the shared-marker implication

- **Where**: `charts/coder/coder-templates/kubernetes/{main.tf,terraform.tfvars}` and `charts/coder/coder-templates/kubernetes-hardened/{main.tf,terraform.tfvars}` (find; the kubernetes→kubernetes-hardened pair is a documented move, fenced by `tests/templates/coder-move.sh:3-4`). They sit INSIDE `charts/**` — see B's last bullet for the set-collapse coupling already live today.
- **Deploy = CLI (card #56 law, repo-grounded)**: `charts/coder/coder-templates/kubernetes-hardened/main.tf:35` comment — `coder templates edit kubernetes-hardened --default-ttl 168h`; `tests/templates/coder-hardened.sh` (C04 acceptance, header `:1-17`) validates template content offline (scratch-copy `terraform init` recipe `:14-16`, packaging guard c4 `:398-402`: the `.helmignore` line `coder-templates/` keeps the dir OUT of the published chart tgz — `charts/coder/.helmignore:6`). NO CI step today publishes/applies the templates; nothing keys a workflow trigger on them except the accidental charts/** bump coupling (B).
- **"Incoming support" in the marker story means**: a third builder workflow (call it build-coder-templates) keyed on `charts/coder/coder-templates/**` (or on a moved `templates/**` — a path move would touch `tests/cf96-tz/surface.sh:46-47` TF_A/TF_B literals, `tests/services/dev-git-auth.sh:37`, and the trio allow lines `tests/agent-board-coord/agents-md.sh:488`/`gate.sh:1036`/`rulesync-surface.sh:709`, which already name BOTH current .tf paths), carrying the same resolver+advance pair against the SHARED marker ref, and invoked by main-sync with the same `uses:` pattern as the other two. Consequences grounded: (i) the marker ref's exclusivity leg (A) must invert to a named-set of builder files; (ii) all three builders diff the SAME marker..sha range filtered to their own path — so either the marker advances once after ALL called builders are green (a fourth, aggregating `advance` job under the caller), or each advances the shared branch itself and the later builders see a range the earlier one already consumed (per-builder path filters make that benign ONLY because each filters its own subtree — charts/** vs containers/** — and the bump-commit hazard of B's loop guard applies to helm alone); (iii) build-charts must stop claiming coder-templates paths (B), else helm and templates double-act on one diff.

### F. Rename blast: containers-build.yaml -> build-containers.yaml (C11 method, priced)

`build-containers` is UNUSED today (grep: hits only STATE.json prose — FROZEN records). Families:

**HARD (red if missed):**
1. `git mv .forgejo/workflows/containers-build.yaml -> build-containers.yaml` — the subject; keep line shape (several cites below name line anchors: `main-sync.yaml:9` "Unlike containers-build.yaml, whose guards widen" prose; `ci-surface t6` mechanics, #3).
2. `tests/services/forgejo-containers-build.sh:218` `WF=".forgejo/workflows/containers-build.yaml"` — t1 hard-exits all ~47 legs if missed. Suite pairing law (Rename-surface §C precedent): `git mv` to `forgejo-build-containers.sh` — machine consumers: NONE (grep: only the suite's own path strings `:208-213,226,2774-2776`; the mktemp prefix and PASS banner are cosmetic). Prose readers: none for the suite path itself (`forgejo-runner/README.md:73` names the RUN, not the suite).
3. `tests/services/forgejo-ci-surface.sh:80` FJ_SET member `'containers-build.yaml'` (t1 set-equality; a miss hard-exits t3-t7) + FAIL prose `:98-99`; `:216` `WIDEN_OK = {'containers-build.yaml'}` — t6 keys the widen-on-unset EXCLUSIVITY by FILE NAME (`:218-240`): renamed file keeps its `vars.ROLE == null` clause, the set member must move; t6 messages `:234,242` name containers-build prose; `:202` t5 token tuple `('containers-build.yaml', 'yy.mm.N', 'FORGE_PUSH_TOKEN', 'PUSH_TOKEN_GH')` requires the literal PATH token inside AGENTS.md + skills/container-creation/SKILL.md — docs rewrite and suite re-pin SAME commit.
4. `tests/services/forgejo-containers-build.sh` x3 `:2554-2564`: SKILL.md, overview.md and regenerated AGENTS.md each must still carry a line containing `containers-build` — after a rename that token only survives as `build-containers` ⇒ x3 FAILS unless its needle becomes the new name (same-commit docs parity, x5 `:2589-2658` parity law applies to whatever token x5 keys — x5's own tuples are vocabulary, not filename).
5. `tests/pipeline-push-pr/surface.sh:313-318` P7: `grep -qiE 'containers-build'` over `.rulesync/skills/pipeline-push-pr/SKILL.md` + the `.opencode` mirror — re-needle + rewrite `SKILL.md:24,41` + `role-code/SKILL.md:64` + `role-planner/SKILL.md:64` (+ regenerate mirrors, rulesync-pair law — exactly C11's needle flow).
6. `tests/services/forgejo-packages.sh:306` t7: token `'containers-build.yaml'` must live in the comment block above `packages:` in `custom-values/infra/prod-values.yaml` (`:89` carries it) — comment rewrite + tuple re-pin together (file NOT under charts/** → no fire coupling).
7. `tests/renovate/services-values-pins.sh:166` pins the renovate.json `:308` description string literally (`.forgejo/workflows/containers-build.yaml `) — renovate.json:308 + that suite line in one change. (Renovate trap from C11 §H-4 still stands: never blanket-sed the token `forgejo-releases` etc. — edits surgical.)
8. Guard-trio CONDITIONAL (board-run): `tests/agent-board-coord/agents-md.sh:422-425`, `gate.sh:978`, `rulesync-surface.sh:662` record "containers-build … stays outside" the cf-55 arm allow-set — the rename run's arm must explicitly admit `.forgejo/workflows/build-containers.yaml` (new path rides nothing by default; the "A replan-added file joins THIS line" convention from C11 §A).
9. Law pair `:500`: `.rulesync/rules/overview.md:228,:500` + `AGENTS.md:230,:502` — the five-workflow ROLE sentence enumerates members by name; rewrite source + `rulesync generate`, keep the 'five'/'.forgejo'/'builder-bootstrap'/'narrow' block shape or builder-bootstrap **b9** (:900-907, token-set scan, survives a member rename ONLY if the block keeps those four tokens) and C11 §H-3's four-workflow ban stay satisfied.
10. First-fire coupling INVERTED by directive 4: today renaming touches only `.forgejo/**` (no charts/**) ⇒ zero bump fire; but if the same pass rewrites prose under charts/** (e.g. `charts/forgejo-runner/values.yaml:133,135` "not minted by the containers-build pipeline"), note that once build-charts loses its push trigger, a charts/** prose merge bumps NOTHING until main-sync next calls it — the C11 §E "merge itself is the first fire" assumption changes semantics.
**SOFT (prose lies):** cross-cites in `.forgejo/workflows/renovate.yaml:11`, `main-sync.yaml:9`, `build-charts.yaml:14,186,289,453`, `.github/workflows/docker-build.yaml:5` (dated history, x4 class), the containers-build suite's own header history lines (`:3-7,41-47`), `forgejo-build-charts.sh:10,19,193,925,958,1019,1039,1488` (lesson-cites; no file reads), builder-bootstrap workflow `:23-34,52` and suite message-prose `:213,423,500,749,763,855` (leg LOGIC keys on builder-bootstrap's own bytes + b9 shape, not the filename), container-docs prose (`containers/renovate-mcp/Dockerfile:18`, `strata/README.md:163`, `vllm-radiance-mxfp4/Dockerfile:11`+`README.md:13`, `wekan-mcp/pyproject.toml:3`+`README.md:60`, `forgejo-runner/Dockerfile:5`+`README.md:15,73,83`, `custom-values/infra/prod-values.yaml:89` HARD-via-#6, `skills/container-creation/SKILL.md:3,44,351` HARD-via-#4/#5 for the token-bearing lines only, `tests/argocd-fanout/disposal.sh:8,212-227` d6 reads the DETECT SCRIPT not the yaml — safe), `tests/wekan-mcp/tools.sh:351,362` (message prose).
**FROZEN**: everything under `.agents/` (all prior rounds incl. this file, STATE `directive`, the cf-6 marker plan `2026-11-25-feat-containers-built-marker.md`), plus dated reword-or-leave classes per C11 §G.
**Marker-rename interaction** (do directives 2+3 in one fence): the suite REF literal `:1252` + t16/t17 bodies (byte-pin `git push origin HEAD:refs/heads/<ref>` `:1317` + scratch-remote asserts `:1402-1429`) move with the shared branch name; t16's exclusivity walk (`:1306-1312`) must become the builders allow-set (A). Detect script needs no change for either rename.

### Digest for the plan (10 lines)

1. Fire cause grounded: `build-charts.yaml:111` regex `^version: (\d+)\.(\d+)\.(\d+)$` rejects trailing comments; `prowlarr/Chart.yaml:3` carries the seed-law comment ON the version line (since before C11 — C11 only renamed the token in it); fix shape must cover both parse sites (`:111` + `:258`) and keep the column-0 anchor.
2. Consequence of the fire: zero bumps since C11 — test-build red → bump/release/forgejo-publish all skipped; {llama-swap 1.0.40, prowlarr 1.0.1} still pre-calendar; the fix merge is itself the first real calendar fire (expect TWO first releases, per STATE AC5).
3. Marker shipped-shape: branch `refs/heads/ci/containers-built`, read `:147`, advanced `:483` by `advance-marker` ONLY on push×build-release-matrix-success; chain marker→tip-only→before; `marker==sha` ⇒ verified-empty info line = the idempotence property the new orchestration needs as its loop guard (the old non-re-trigger guard at `:184-185` dies with directive 4).
4. Shared-marker renames touch: workflow 2 lines + suite REF/t16/t17/t13/d-legs; script is ref-agnostic; docs carry vocabulary only. t16's "ref in no other .forgejo yaml" walk must invert to a builder allow-set.
5. Forgejo 15.0.10 (live-probed both clusters) SUPPORTS `on.workflow_call` + same-repo `uses:` + expansion + inputs/outputs/`secrets: inherit` (docs: forgejo.org/docs/v15.0/user/actions/reference/). workflow_run does NOT exist. Dispatch API route exists on our instance (405 probe; GET runs/runs{id} answer 200 anonymously; /actions/workflows and /actions/jobs are 404 in 15.0.10) — but workflow_call is the expressive answer; dispatch+poll would be the lab's first Actions-API consumer with an unproven token write-scope.
6. main-sync wiring = 2 `uses:` jobs beside push-gh/push-dev; sync-fanout `needs: [push-gh, <helm-job>, <docker-job>]`; HARD suite re-pins: main-sync.sh:116-117 job-set, :341-342 needs-exact, per-job byte guard loop :131; build-charts.sh t2 trigger set (:144-157) and containers-build t2 (:289-295) both re-pin when push arms drop.
7. Runner replicas=10 breaks written decision B1 (values.yaml:158-162) + t2/g2 legs (dev-forgejo-runner.sh:303, gpu-forgejo-runner.sh:257) and multiplies 12Gi RWO local-path VCTs/pod; capacity (config, secret-runner.yaml:88) is per-record, hard-coded, un-pinned; the sanctioned scalings are more runner records or a capacity ruling — autoscaling already has the owner's follow-up card.
8. Coder templates live at `charts/coder/coder-templates/**` (CLI-deployed, helmignored out of chart packaging) — today a template push collapses into charts/coder's bump set via `cut -d/ -f2`; the third builder needs that filter resolved and (for any path move) the trio + cf96/dev-git-auth literals re-admitted.
9. Rename blast F mirrors C11's method; 10 hard surfaces enumerated (WF literal, FJ_SET, WIDEN_OK, t5 tuple, x3, P7 needle, packages t7 tuple, renovate-pin services-values-pins:166, trio admits, overview/AGENTS law pair + b9 shape); suite pairing law suggests `forgejo-build-containers.sh` (zero machine consumers); no collision; first-fire semantics INVERT under directive 4 (charts/** prose merges stop auto-bumping).
10. Verdict on the hinge: **workflow_call exists on this Forgejo** — design the orchestration on `uses:` + needs-graph, keep dispatch+poll only as documented fallback.

## Round-6 diagnosis (2026-11-26)

Fresh Exploration relaunch on owner ruling D60(1): the owner observes REAL job serialization despite C16's replicas-10, contradicting `RESEARCH.md §Round-6 research`'s throughput claim ("10 pods × capacity 1 really is up to 10 concurrent jobs"). This section grounds both fronts — live cluster (A) and v15.0.10 source re-verification (B) — and renders the verdict. Read-only throughout; probes via `readonly-gpu/dev/infra-kubernetes`, anonymous instance API, codeberg raw at commit `17e1001d5e00e8ee3cbc1b6dd31be94ac38185f9` (= v15.0.10, [S1] unchanged), forgejo-runner v13.2.0 via `proxy.golang.org` zip. Measured 2026-11-26 ~17:50–18:10 UTC.

### A — LIVE CLUSTER TABLES

**A1 StatefulSets (ns `default`):**

| STS | spec.replicas | status | pods actual |
|---|---|---|---|
| `gpu-forgejo-runner-gpu` | **10** | `replicas:4, currentReplicas:4, readyReplicas:3, availableReplicas:3, updatedReplicas:4` (observedGeneration 5, current==update rev `cffbdc496` — no template churn) | `-0` Running (node gpu, created 2d23h, runner container restarted 16:23:23Z, restarts=1), `-1` Running (created 16:42:15Z), `-2` Running (16:42:31Z), **`-3` Pending 69+ min, node `<none>`**, `-4`…`-9` **do not exist at all** |
| `dev-forgejo-runner-dev` | **1** (!) | `1/1 ready`, observedGeneration 6, current==update rev `794ff5f585` | `-0` Running 17d (node dev), runner container restartCount=14, last daemon line 2026-11-23T14:38:45Z; zero task fetches since |

- Pod-3 scheduler condition VERBATIM (`pods_get`, type `PodScheduled=False`, reason `Unschedulable`, since 16:43:47Z): **"0/1 nodes are available: 1 Insufficient cpu. no new claims to deallocate, preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod."** — the GPU cluster is a SINGLE node (`gpu`, control-plane/master/etcd, v1.36.5+k3s1, capacity cpu=6, allocatable cpu=6, Ready, **no DiskPressure condition**) carrying 78 Running pods; sampled requests include the `coder` deployment 2000m, workspaces 250m, most stacks 15m–250m — the pool is simply spent before a 4th runner pod (each = 250m runner + 100m dind = 350m).
- **Why ordinals 4-9 are absent, not just Pending:** StatefulSet management creates ordinals SEQUENTIALLY — pod N+1 is only created once pod N is Ready. Pod-3's CPU wall therefore FREEZES the whole scale-out at 3 ready; the remaining 7 pods never reach the scheduler. The C16 shape cannot express "10" on this node — it degrades to 3.

**A2 PVCs:** `data-gpu-forgejo-runner-gpu-{0,1,2}` + `docker-data-gpu-forgejo-runner-gpu-{0,1,2}` all **Bound** (dynamic `pvc-…`, SC `local-path`); the ordinal-3 pair (`data-…-3`, `docker-data-…-3`) **Pending with empty volumeName** — the consequence, not the cause: local-path is WaitForFirstConsumer, so provisioning waits for the pod that the scheduler cannot place. No bind errors. Dev: `data-`/`docker-data-dev-forgejo-runner-dev-0` exist for the single ordinal. Nodes: gpu no DiskPressure (see A1); dev single node `dev`, capacity cpu=8.

**A3 Runner daemons (pods_log, container `runner`, image `data.forgejo.org/forgejo/runner:13.2.0`):** ALL THREE gpu daemons healthy and polling: each log shows `Starting runner daemon` → `runner: gpu-runner, with version: v13.2.0, with labels: [ubuntu-latest ubuntu-24.04 ubuntu-22.04 docker node22], ephemeral: false, declared successfully` → `[poller] launched`. dind is a **native sidecar** (initContainer `dind`, `restartPolicy: Always`, image `docker:29.9.2-dind`, `args: ["--mtu=1450"]`, `privileged: true`; runner env `DOCKER_HOST=unix:///var/run/docker.sock` on the shared `socket` emptyDir) — running+ready on every gpu pod (0 restarts), ready on dev-0 (5 restarts). No registration/token/config-parse errors anywhere; only benign `ReportState error: not all logs are submitted 1 remain` ×2 and one `RESULT_CANCELLED` self-terminate (task 677, a `push-dev` job cancelled via concurrency-group at 17:08:25). So the research's Q1 discriminator ("check whether 10 sets of logs each show declared successfully + [poller] launched") **fails on pod COUNT (3+1 exist, not 10+10), not pod health**.

**A4 Job concurrency, measured from log timestamps** (the anonymous API cannot answer this — see A5): fetched-task windows across the three gpu daemons show genuine cross-pod concurrency AND a hard cap at the ready-pod count:

| instant | gpu-0 | gpu-1 | gpu-2 |
|---|---|---|---|
| 16:28:13–16:42:30 | tasks 650,651,652 then release-job chain 10–15 s apart, SERIAL (only pod alive pre-sync) | — (created 16:42:15) | — (created 16:42:31) |
| **16:51:15** | (holding task 654, a ~25-min `release` build 16:49→17:14) | **655** → done 16:51:22 | **656** → done ~16:52:07 — ≥2 tasks simultaneously on ONE uuid |
| 16:51:15–16:51:22 | still holding 654 (25-min build) | 655 (7 s job) | 656 (52 s job) — **3 tasks concurrently RUNNING on one uuid** |
| 17:07:31–17:07:37 | idle | 673 (cleanup 17:07:37) | 674@17:07:37 (handoff, at best 2-way) |
| **17:17:21** | **697** (`sync-fanout`, cleanup 17:17:26) | **696** (cleanup 17:17:27) — same-second cross-pod pair #2 | — |

Effective concurrency observed: up to **3** (the 654+655+656 triple), exactly = ready-pod count; never >3 (impossible: capacity 1 per daemon, 3 daemons). The owner's serialization is fully accounted for by (a) pre-16:42 reality — literally ONE pod per instance while C16 hadn't synced, and (b) post-sync reality — 3 on prod + 1 on dev, not 10 + 10.

**A5 Actions API (anonymous, prod instance `git.spencerslab.com`):** `GET /api/v1/repos/CuratedForest/SpencersLab/actions/runs` → 200 but the public-repo anonymous view strips `name/created_at/updated_at/run_started_at` (all null; only id+status), and `…/actions/runs/346/jobs` → **404** in 15.0.10 (consistent with Round-5 §C's route probes). Run 346 sits in `waiting` RIGHT NOW (pull_request event) while all three daemons polled it away instantly → the queue drains at the 3-slot service rate, no dispatch stall. Job-overlap measurement therefore rides A4's logs.

**A6 ArgoCD (the dev-side root cause):** BOTH runner Applications are sourced from `https://github.com/OwnYourIO/SpencersLab.git`@main (values leg + `path: charts/forgejo-runner` chart leg), resolved revision `7b8d831b…` — **and NEITHER has `syncPolicy.automated`** (syncOptions only; plain manual-sync apps):

| Application | sync | last operation | consequence |
|---|---|---|---|
| `gpu-forgejo-runner-gpu` | **Synced** | Succeeded **2026-11-26T16:40:51Z** | STS hit spec.replicas=10 at 16:40 — the 16:42 pod creations in A1 match to the second |
| `dev-forgejo-runner-dev` | **OutOfSync** | Succeeded **2026-11-09T15:13:41Z** | replicas:10 has been in the rendered git revision for weeks-worth of commits but was NEVER applied here — dev STS still spec **1**, pod 17 days old |

So the "scale applied" story is half-true: gpu landed via a sync this afternoon, dev never did. The git side is confirmed landed (`226aecb86` is an ancestor of `main` — `git merge-base --is-ancestor` verified; `services/dev/prod/values.yaml:178-185` and `services/gpu/prod/values.yaml:271-279` both carry `replicas: 10` with the D57 ruling comment — disk reads this run).

### B — SOURCE RE-VERIFICATION (Forgejo v15.0.10 = `17e1001d`, forgejo-runner v13.2.0)

**File reality first: `models/actions/task_find.go` does NOT exist at this commit** (raw fetch 404; the dir listing via `codeberg.org/api/v1/repos/forgejo/forgejo/contents/models/actions?ref=17e1001d…` shows `task.go`, `task_list.go`, `tasks_version.go`, `run_job.go`, `runner.go`, … — no `task_find.go`; that file is a different-revision artifact). The FIND path is `CreateTaskForRunner` in `models/actions/task.go`. Quote-by-quote answers to the five questions:

- **(a) server-side count of the runner's RUNNING tasks vs task_capacity (per-uuid gate)? NO.** `services/actions/task.go:23 PickTask` — the ONLY per-row busy check is behind the ephemeral flag, `:29-40`:
  ```go
  if runner.Ephemeral {
      hasRunnerAssignedTask, err := actions_model.HasTaskForRunner(ctx, runner.ID)
      …
      if hasRunnerAssignedTask { return nil, false, nil }   // don't assign new task
  }
  ```
  with `models/actions/task.go:180 HasTaskForRunner = WHERE runner_id = ?` over `action_task`. The live rows read `ephemeral: false` (A3 declare lines), so this gate is inert for the C16 fleet. Non-ephemeral: no count, no cap, anywhere in the pick path.
- **(b) one-task-per-fetch or in-progress refusal? NO refusal; capacity-shaped multi-task.** `routers/api/actions/runner/runner.go FetchTask`: `:194 taskCapacity := req.Msg.GetTaskCapacity()` then the loop keeps calling `PickTask` while `taskCapacity > 0`, appending to `additionalTasks` — the server hands back up to the CLIENT-claimed number, and never inspects whether that runner row already runs tasks. The job-eligibility query is `models/actions/task.go:300 GetAvailableJobsForRunner`: `:336 Where("task_id=? AND action_run_job.status=? AND \`repo_unit\`.type=?", 0, StatusWaiting, unit.TypeActions)` + concurrency-group EXISTS — **runner-id appears nowhere in it**. Binding: `CreateTaskForRunner` `:345` → `:363 if j.IsRequestedByRunner(handle) && j.ItRunsOn(runner.AgentLabels)` → insert task → CAS `:433 UpdateRunJobWithoutNotification(ctx, job, builder.Eq{"task_id": 0})`, `n != 1 → return nil,false,nil` (rollback) — the race-safe claim the research described, unchanged.
- **(c) heartbeat/last_online effect on dispatch? NONE.** `interceptor.go:48-53` stamps `last_online` on every authenticated call and `last_active` on `UpdateTask`/`UpdateLog` only; no dispatch query reads either column (`GetAvailableJobsForRunner` never joins `action_runner`). Offline-ness matters only for the UI status (`RunnerOfflineTime=1m`) and the disabled-by-default cleanup cron.
- **(d) forgejo-runner v13.2.0 client budget? YES, per daemon.** `internal/app/poll/poller.go`: `:128 availableCapacity := capacity - inProgressTasks.Load()`, `:129 if availableCapacity > 0 { fetch }` (and `:180` early-return at 0), fetchMutex held across each fetch (`capacity - inProgress` "can't perform multiple fetches simultaneously or else we could be overprovisioned", `:82-85`); default `fetch_interval 2s` (`internal/pkg/config/config.go:562-563`). So a daemon with capacity 1 asks for nothing while its job runs — the ONLY real concurrency cap in the system, and it is per-process, so N daemons = N slots.
- **(e) server using the runner row's stored last_task/uuid to serialize? NO.** `grep LastTask models/actions/runner.go models/actions/task.go services/actions/task.go` → **zero hits — the column itself is gone in 15.0.10** (it is a Gitea-era field; research's "no session/multiplexing concept" holds). `uuid` appears only in `GetRunnerByUUID` (`models/actions/runner.go:260`, the auth lookup) and `DeleteRunner`'s sentinel rename — never in any task-finding condition.
- One FIND-path nuance the research didn't detail, checked and BENIGN: `FetchTask` only attempts a pick when the request's version differs from the DB (`runner.go:184 if req.Msg.TasksVersion != latestVersion`) — change detection, not a cap: version bumps on run/job queueing (`models/actions/run.go:470`), jobs returning to waiting (`run_job.go:232`), and finalizing a task when `CONCURRENCY_GROUP_QUEUE_ENABLED` (`runner.go:326-327`, default true), plus the client CASes its local version to 0 after ANY successful task fetch (`poller.go:231`) forcing requery next poll. No starvation loop; the idle-but-waiting run 346 drained instantly (A5).
- Cross-pod `requestKey` collision (would serialize fetches through the server's request-key MutexMap): ruled out — the key is a per-poller-loop RANDOM uuid (`gouuid.New()`, `poller.go:119/137`), never derived from the runner uuid.

**Empirical corroboration:** A4's same-second cross-pod task pairs (655/656 at 16:51:15; 696/697 at 17:17:21) are exactly the behavior source predicts — two daemons on ONE uuid held TWO running jobs at once. A per-uuid serial gate would make those interleavings impossible.

### VERDICT

**`lab-side infra cause (pending pods/pvc/dind/argo drift — specifics), research claim holds`** — with BOTH legs named:
1. **Dev fleet: the scale never landed.** `dev-forgejo-runner-dev` Application is manual-sync and last synced 2026-11-09; it sits OutOfSync with STS `spec.replicas: 1` while git says 10. One daemon = one concurrent job, 17 days of that.
2. **GPU fleet: the scale landed but only 3 pods fit.** Single 6-cpu node; pod-3 unschedulable (`Insufficient cpu`, no preemption victims) since 16:43:47Z; StatefulSet ordinal sequencing freezes ordinals 4–9 out of existence; effective fleet = 3.
3. Timing compounds it: until the 16:40:51Z sync BOTH fleets were literally 1 pod each — the owner's serialization observation is TRUE and was total; the protocol was never the limiter. The research predicted precisely this discriminator ("If the owner observed serialization in practice, the cause is deployment, not protocol") and its Q3 §5 pod-health check is what fails. **No CORRECTION subsection is appended to RESEARCH.md** — the source reading CONFIRMS §Round-6 Q1/TL;DR item 2 verbatim (ephemeral-only gate, CAS claims, client-side capacity), so nothing there is refuted; the two refinements recorded above (no `task_find.go` at this commit; the TasksVersion change-detection gate) do not change the throughput conclusion.

**Consequence for C17 (N releases):** releases fix VISIBILITY (N rows) unconditionally, and THROUGHPUT only up to the schedulable-pod ceiling — which today is **3 on the gpu cluster and (once synced) 10 affordable on the dev cluster**:
- Semantics verified: 1 release = 1 registration = 1 STS = 1 pod at capacity 1 = **exactly 1 concurrent job slot**; requests 350m/pod (250 runner + 100 dind).
- **GPU cluster: 10 releases do NOT give 10 slots.** Unlike C16's frozen STS, ten separate 1-replica STSes would each schedule independently, but the node still fits only ~3 at 350m against the current request pool — expect ~7 of them Pending forever. Owner options inside C17's frame: (a) size the gpu fleet at what fits (≈3–4 releases) and raise the count only with a node/requests change (cutting per-pod requests to ~150m could double the count but throttles real 2-cpu-limited builds); (b) capacity>1 per release as a multiplier once slot math is settled (the research's option C caveat — shared dind envelope — still applies).
- **DEV cluster: 10 releases IS affordable request-wise** (10×350m = 3.5 of 8 cpus; verify the current sum like A1 did for gpu before pinning). C17 MUST also wire the landing leg: the N dev releases are manual-sync — without an explicit `argocd app sync` (or cf-139's fan-out reaching the dev cluster's ArgoCD) each new release repeats today's silent never-applied failure. Per instance: N UI/offline registrations + N Bitwarden items (the B1 owner legs the research priced).
- Suite note for C17: D57's per-slice `replicas: 10` becomes dead config once scaling means releases — the t2/g2 re-pins plus a render-count leg, and the rendered proof should assert `readyReplicas == replicas` per STS (this whole fire was invisible in `replicas:` alone — gpu's STS would have "proven" 10 while running 3).
