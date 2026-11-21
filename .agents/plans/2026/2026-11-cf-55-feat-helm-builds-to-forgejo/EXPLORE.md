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
