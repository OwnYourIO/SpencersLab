# RESEARCH — cf-55 Move GitHub parallel helm builds to Forgejo

Research round by `agent-research`, 2026-11-10 (STORM method; 5 perspectives,
37 sources — numbered `[n]` below, full URL list at the end; 1–33 merged by
the storm run, 34–37 added in the peer-review round). Lab version pins
this document reasons against: **Forgejo 15.0.10+gitea-1.22.0** (docs branch
`v15.0` = LTS v15.0.11 used for every Forgejo citation) and the
catthehacker `ubuntu:act-*` job images advertised by the five act labels of
`charts/forgejo-runner`. Repo grounding is taken from `EXPLORE.md` (§ refs)
and is not re-verified here except where a probe is named.

## TL;DR

1. The moved actions mostly survive, but not all by name: the default Forgejo
   action mirror (`data.forgejo.org`) verifiably carries `actions/*`,
   `docker/*` and `azure/setup-helm` — **not** `dorny/paths-filter`,
   `EndBug/add-and-commit`, `helm/chart-releaser-action` or the bump action —
   so those need absolute `https://github.com/...` `uses:` URLs (runner egress
   to github.com, unproven in-lab) or a deliberate mirror/pinning move.
2. `act-24.04` has no `helm` (upstream installer proof) but does ship
   jq/python3/git-lfs/yq/node20+24/docker-CLI+buildx; the smallest remedy is
   `azure/setup-helm` (mirrored, defaults to get.helm.sh, no GitHub API).
3. All three chart-publishing options are technically live; option 2
   (Forgejo Helm **package registry**) is the only one that keeps the
   https-index consumption shape (ArgoCD + renovate `datasource=helm`
   annotations) while becoming forge-native; option 1 (keep GitHub Releases
   + gh-pages from Forgejo) works but needs owner/repo override surgery in
   `chart-releaser-action`; option 3 (OCI) requires action v1.8.0+/cr v1.9.0+,
   appset-template changes and breaks the renovate helm managers (in-repo
   comment already concedes OCI is untracked).
4. The bump-back → sync interaction flips into a NEW failure mode on Forgejo:
   pushes made with the automatic token do not re-trigger the repo's own
   workflows, so a Forgejo-side version bump would silently NOT fan out to
   GitHub until some later human push moves main.

---

## Q-A — action availability and mirrors

### A1. How Forgejo resolves `uses:` (the model; version-pinned to v15.0)

- Relative `uses: owner/repo@ref` is prefixed with the instance setting
  `[actions] DEFAULT_ACTIONS_URL`, **default `https://data.forgejo.org`**
  [2, 3, 16] — NOT `github.com` (that is the *Gitea* default — its cheat sheet
  documents the keyword values `github`/`self` [34]; the launch brief's
  "typically github.com" is that Gitea-era framing; contradiction X1). The
  docs "strongly recommend fully qualified URLs" because an admin can change
  the default and break resolution [2, 5].
- Resolution order: absolute URL in `uses:` > local `./` action >
  DEFAULT_ACTIONS_URL prefix [2]; a community write-up confirms the same three
  admin modes, including `DEFAULT_ACTIONS_URL = self` (mirror repos into the
  instance under the identical org/repo path — the air-gapped recipe)
  [8, 9]. **No ENV "fetch-through proxy" is required to reach GitHub actions:
  the act_runner performs the git clone itself, from the runner network, at
  job start.** So "fetch-through-proxying" reduces to (a) the URL you write in
  `uses:` and (b) the runner's egress.
- Ref forms all documented: commit SHA, tag, partial major tag, branch — and
  the docs recommend **commit SHAs** because floating tags are compromiseable
  (CVE-2025-30066 cited there) [2]. The repo's existing SHA-pin style is
  portable; a SHA `uses:` on a `github.com` absolute URL still needs egress.
- Node actions need Node in the image (not auto-installed) [5] — satisfied by
  the act images (node 20+24, Q-C). Docker-type actions need a container
  engine in the job — irrelevant to this workflow set (none uses a docker
  action). Composite actions are plain steps [5] — relevant, two of the used
  actions are composite (A2).

### A2. Per-action verdict (mirror scope MEASURED live, 2026-11-10)

Probes: HTTP `GET https://data.forgejo.org/<org>/<repo>/info/refs` smart-git
check; 200 = present, 302→`code.forgejo.org`→404 = not present. Recorded here
as own measurements (trail: shell session of this run) — treat as
"currently mirrored" state, subject to the mirror's sync policy.

| Action (usage today) | data.forgejo.org | Verdict for the move |
|---|---|---|
| `actions/checkout@v7` (×11) | **200** | Keep. Shorthand already proven in-lab via main-sync's `actions/checkout@v6` (EXPLORE §2/§4). |
| `actions/setup-node@v7` (aislop, rulesync) | **200** | Keep (npx/node already in the act image anyway — could also drop). |
| `actions/setup-python@v7` (3× render-tests, pins python **3.15**) | **200** | Resolvable; RUNNER_TOOL_CACHE exists in act images [26] — but the action first checks the tool cache, then downloads CPython builds from `actions/python-versions` GitHub Releases [36], i.e. still github egress; the act image's own python3 is 3.12 (Ubuntu 24.04). Behavior on first fire UNVERIFIED (open question). |
| `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/metadata-action@v6`, `docker/build-push-action@v7` | **200** | Keep (docker CLI+buildx already in the image, Q-C). Caveat: these act on a daemon the job must have (Q-C DinD) and `login` today uses `github.actor` + `GITHUB_TOKEN` — cross-forge that identity changes (A4). |
| `helm/chart-releaser-action@v1.7.0` + SHA-pin | **404** | Must be fetched as `https://github.com/helm/chart-releaser-action@v1.7.0` (egress), mirrored instance-side (`self` recipe [8]), or replaced by the `cr` CLI directly (it is a thin composite wrapper [19]). |
| `dorny/paths-filter@v4` | **302→404** | Same trio of remedies. On a `push`-triggered workflow paths-filter is pure-git anyway [23] — or drop it for the `git diff --name-only` loop the repo's own `docker-build.yaml` already uses (EXPLORE §1b). |
| `EndBug/add-and-commit@v11.1.1` | **302→404** | Same remedies; note it is pure git via simple-git, no GitHub API in its inputs [24] — a `run: git commit && git push` step is a faithful substitute on any forge. |
| `EMAsphere/bump-helm-chart-action@main` | **302→404** | Composite that `apt-get`s python3-dev/pip and runs `pybump` [25]; its own README now points at a DIFFERENT org (`explorium-ai/...`) while the API still reports `EMAsphere/...` [25 probe] — floating `@main` + org churn = replace with a direct `pybump` run step (2 lines) or pin by SHA. |
| `azure/setup-helm` (NOT used today — remedy candidate) | **200** | Ideal helm installer: `downloadBaseURL` defaults to `https://get.helm.sh` (GitHub-API-free; the `token` input is deprecated) and it runs node24 [30]. |

There is no "firstparty/checkouts"-style Forgejo-native rewrite needed for any
of this: the first-party set is `code.forgejo.org/actions/*` (docs link
checkout/upload-artifact/setup-node/setup-go/cache there) mirrored for cloning
at `data.forgejo.org` [2, 5]. On the Gitea side the equivalent org is
`gitea.com/actions` (probe 200) — irrelevant to this lab unless dev-instance
workflows are ever shared with Gitea users. Gitea's own "checkout replacement"
myth-check: Forgejo keeps using the (mirrored) `actions/checkout`, there is no
separate native checkout action to adopt.

### A3. Runner selection and context parity (moved-workflow surface)

- Labels: `runs-on` matches runner-advertised labels; jobs on a label with no
  online runner **halt until one appears** [2]. Lab: the five act labels
  (`ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`, `docker`, `node22`) are the
  only game in town (EXPLORE §4); `ubuntu-26.04` (today's every-job label)
  routes nowhere — re-label is mandatory (EXPLORE §9-1, agreed).
- Contexts: `forgejo.*` with `github.*`/`forge.*` aliases; fields include
  `run_number`, `server_url`, `api_url`, `repository`, `actor`, `ref`, `sha`
  [2] — so `${{ github.run_number }}`-style tag math (`:v<run>`) still
  EXPANDS, but see B5/OQ-5 for the counter-space change. "Some keys in the
  `github` context are missing" is the documented caveat [4, 6] — anything
  depending on an event-payload key (paths-filter PR mode [23],
  docker-build's `github.event.before` [EXPLORE §1b]) needs first-fire check.
- Divergences that bite these workflows: job-level `permissions:` and
  job-level `continue-on-error` are IGNORED [4, 6] (EXPLORE §9-3, agreed;
  step-level continue-on-error IS documented [2]); OIDC requires the
  `enable-openid-connect` key, not `id-token: write` [4] — unused today.
- Concurrency is documented with "best-effort" group semantics and an
  automatic cancel model when unset [2] — relevant to release.yaml's
  bump-serialization design (EXPLORE §1a's known-colliding matrix): on ONE
  runner with capacity 1 (chart `runner.capacity: 1`, repo evidence) matrix
  jobs queue anyway, which incidentally removes the collision class
  (EXPLORE §9-8's fact, sharpened: serialization is then structural, not by
  concurrency group).
- `workflow_dispatch` inputs are capped by `LIMIT_DISPATCH_INPUTS` (default
  10) [3, 16] — docker-build's single free-text `containers` input is fine.

### A4. Known pitfalls for the fetch-through case specifically

1. **Egress**: every job clone hits the actions host at run time (mirror or
   github.com); EXPLORE §9-9's k3s MTU action-clone flakiness and cf-119 OQ-3
   apply and are lab-verified risks; github.com from the gpu runner is
   PROVEN-NEEDED but UNPROVEN-WORKING (main-sync only exercised the default
   mirror path).
2. **No server-side action cache documented** — re-clone per job; rate-limit
   and MTU exposure per job start [2, 8] (devroom troubleshooting: restart
   after config, runner cache of definitions).
3. **Mirror scope drift**: `data.forgejo.org` availability is the Forgejo
   project's policy, not a contract [2] — measured absent for our four
   third-party actions today (A2). Anything "unusual" in a moved workflow
   should therefore be written as an absolute URL or replaced by inline `run`
   steps, and a moved workflow that must be air-gap-tolerant follows the
   `self`-mirror recipe [8, 9] (admin-owned).
4. **Tag-vs-SHA supply chain**: docs recommend SHA pinning [2]; the lab
   already SHA-pins one usage — make it consistent.
5. **Automatic token identity**: `${{ secrets.FORGEJO_TOKEN }}` == the
   `github.token` alias, same-repo only, and **pushes made with it do not
   re-trigger that repo's workflows** [2 semantics + cf-119 EXPLORE §2 docs
   quote]. Every cross-repo/cross-forge write (GitHub Releases, ghcr, the
   gh-pages branch on GitHub) needs an explicit PAT-shaped secret instead
   (Q-B/Q-C below); `docker/login-action` with `github.actor` breaks because
   the forge actor is not a ghcr identity with `write:packages`.

---

## Q-B — chart publishing target ergonomics

### B0. What consumers pin TODAY (repo evidence, EXPLORE §5/§6 + fresh grep)

- Live versioned-chart installs resolve `repository:` →
  `https://ownyourio.github.io/SpencersLab/` in seven `charts:` entries
  (`services/{gpu,grow,home,infra,media,monitoring×2}/prod/values.yaml`,
  verified by grep this run) + four umbrella service `Chart.yaml` dependency
  blocks (`services/{backups,home,infra,personal}/prod/Chart.yaml`) + the
  `datasource=helm registryUrl=https://ownyourio.github.io/SpencersLab/`
  renovate annotations (managers #7/#8, `baseChartVersion`, changelog
  override — EXPLORE §6-2) incl. `services/*/prod/templates/appset.yaml`
  template annotations. The shared ApplicationSet source shape is
  `repoURL: {{ .repository | default services.repo }}` + `chart:` +
  `targetRevision: {{ .version | main }}`
  (`charts/base/templates/appset-charts.yaml:54-70`, read this run).
- The live index's `urls:` all point at GitHub Releases assets (EXPLORE §5,
  webfetch-proven): the **index (gh-pages) and the artifacts (Releases) are
  two different GitHub surfaces a replacement must serve both of.**
- Internal charts (`forgejo`, `llama-swap`, `vllm`, …) deploy by git path, not
  from the index (EXPLORE §5) — a publishing move does not touch them.

### B1. Option 1 — keep GitHub Releases + gh-pages, publish FROM Forgejo

Mechanics (all upstream-documented): `cr upload`/`cr index` speak **GitHub
REST** (`api.github.com`, `uploads.github.com`, both overridable via
`--git-base-url`/`--git-upload-url` or `CR_GIT_*` — designed for GHES but any
HTTPS client location works) with `-t/--token`, so running them from a
non-GitHub runner is just cross-network API traffic [17]. This is the
"how does chart-releaser behave against api.github.com from a non-GitHub
runner" answer: **nothing about it is location-aware; only identity matters.**

- Secret shape: NOT the forge `GITHUB_TOKEN`/`FORGEJO_TOKEN` alias (same-repo
  scoped; api.github.com would 401) — a **GitHub fine-grained PAT bound to
  `OwnYourIO/SpencersLab` with Contents: Read/Write (gh-pages push) +
  Releases: Read/Write**, passed as `CR_TOKEN`, plus the same-or-a-second
  credential wired into the git push path (`x-access-token:$PAT@…` URL form,
  the pattern main-sync already uses for the GitHub fan-out — repo evidence).
  Classic PAT with `repo` scope is the fatter equivalent. (GitHub's PAT doc
  [1] enumerates the permission model; chart-releaser README itself only says
  "a Github token with the right permissions" [17].)
- **Wrapper pitfall #1**: `chart-releaser-action` computes owner/repo ONLY
  from `$GITHUB_REPOSITORY` [19]; on the prod instance that expands to
  `CuratedForest/SpencersLab` → releases would be sought at the (nonexistent)
  GitHub `CuratedForest/SpencersLab`. Fixes: step-level
  `env: GITHUB_REPOSITORY: OwnYourIO/SpencersLab` override (env wins over the
  composite's inherited context? — the composite reads the step env, so
  yes; verify on first fire), OR a `cr.yaml` config with `owner:`/`git-repo:`
  (config is overridden by the wrapper's CLI args [17 precedence], so the
  config path only works with direct `cr` invocation), OR drop the wrapper
  and run `cr` directly (a single binary download + checksum, trivially
  inlined).
- **Wrapper pitfall #2**: `cr index --push` pushes the Pages branch to the
  git **remote named by config `remote:` (default `origin`)** [17, 19] — the
  Forgejo checkout's origin is `git.spencerslab.com`, so without setting
  `remote:` in `cr.yaml` to a manually-added GitHub remote the index commit
  lands on the FORGEJO repo's `gh-pages` branch. The wrapper's
  `ensure_pages_branch` also bootstraps a missing publishing branch on that
  same remote [19]. Both fixable with config; both silent-wrong if missed.
- ArgoCD impact: **zero** (GitHub Pages index + Releases assets unchanged);
  renovate annotations unchanged; main-sync unchanged. The desync hazard the
  plan fights is the bump-back loop (B5/OQ-2), not this.
- Residual risk: this option keeps GitHub as the chart source of truth —
  it does not advance the card's "move to Forgejo" goal beyond the CI
  execution itself. Not a blocker, a scoping note.

### B2. Option 2 — Forgejo Releases + a Pages-equivalent index

- **Forgejo 15.0 has NO built-in Pages**: v15.0's release notes contain no
  Pages feature (Actions items were reusable-workflows, OIDC, ephemeral
  runners, simplified registration) [7], and the v15.0 config cheat sheet has
  no `[pages]` section [3, 16]. Third-party page servers exist (Codeberg-
  Pages-style, e.g. the `git-pages` tool that serves forgejo.org itself) but
  are extra services — out of the in-repo move surface.
- **`actions/upload-artifact` is not a publish substrate**: artifacts are
  run-scoped, default 90-day retention, admin-changeable, and currently
  NOT accessible from other workflow runs at all (documented limitation,
  forgejo#8004) — plus Forgejo requires v3 or a patched v4 of the artifact
  actions [2 and adv-features doc quoted there]. Good for passing a built
  `.tgz` between jobs of ONE run; useless as the durable store.
- **The real same-forge store is the Helm package registry**: chartmuseum-
  compatible HTTP index. Push = `curl --user u:t -X POST --upload-file
  chart.tgz https://<forgejo>/api/packages/{owner}/helm/api/charts` or
  `helm cm-push`; consume = `helm repo add …
  https://<forgejo>/api/packages/{owner}/helm` — i.e. **the registry SERVES
  the index.yaml** that today's gh-pages branch hand-hosts [13]. Forgejo
  Actions officially documents "uploading to a package registry" from
  workflows [2]. This preserves the consumption contract that B0 says
  consumers use today: ArgoCD ApplicationSet `repository:` values change from
  `https://ownyourio.github.io/SpencersLab/` to the instance URL (7 live +
  4 umbrella deps + commented templates + appset annotations), renovate
  `datasource=helm` [15]. Auth/visibility: the docs describe token/PAT auth
  for push and pull [13]; whether the served index is anonymously readable
  for this repo depends on package visibility settings on the instance
  (instance state — open question OQ below), and if creds are needed ArgoCD
  (helm repo secret) and Renovate (hostRules) both have standard paths.
- A **Forgejo Releases**-flavoured variant (upload the `.tgz` as a release
  asset via `/api/v1/repos/{owner}/{repo}/releases` + assets endpoint, index
  built and hosted elsewhere) reproduces the GitHub Releases mechanics —
  `cr` cannot do it (GitHub-API only [17]); it would be hand-rolled curl
  steps. The helm-registry option is the supported, less-invented path.

### B3. Option 3 — OCI chart registry

- Builder side: **chart-releaser grew native OCI publishing**: `cr push`
  "publish chart packages and sibling provenance files to OCI registries" —
  added in **cr v1.9.0** [22, 17]; the wrapper gained `oci_registry_url` +
  `skip_release` (package-and-push-only, no GitHub releases/index, CR_TOKEN
  not required) in **action v1.8.0** [21, 18]. The repo's pins (action
  v1.7.0, cr ≤v1.6-era default) predate both — a move to OCI MUST bump the
  pins; the README's `@v1.7.0` + OCI example is stale (contradiction X4).
  Auth is either `docker/login-action` into `~/.docker/config.json` or
  `CR_USERNAME/CR_PASSWORD` [17, 18].
- Targets: `ghcr.io/ownyourio/charts…` — same store the containers already
  live in, **but** pushing needs the classic-PAT `write:packages` route,
  because GitHub's own docs state fine-grained PATs do NOT support Packages
  [1] (EXPLORE §6-3 guessed "write:packages" — confirmed, and the
  fine-grained variant it resembles is ruled out by doc). A Forgejo-native
  alternative is the instance's OCI distribution registry, documented to
  carry Helm charts alongside images [14] (`helm push oci://…/<registry>…`).
- Helm semantics: charts at `oci://<registry>/<repo>/<chart>:<version>` via
  `helm push`/`helm pull` — the OCI reference must NOT include the chart
  basename or tag when pushing [12].
- ArgoCD consumption: documented today — Application `source.repoURL:
  oci://…`, `targetRevision: <chart version>`, `path: "."` for the
  helm-chart mediaType; private registries via repo secret `type: oci`
  (or `type helm --enable-oci`) [10]. OCI appears nowhere in Argo CD's
  unstable-features table [11] (treat as stable in the v3.x generation; the
  lab pins argo-cd chart 10.11.6 in `charts/base/Chart.yaml`, repo evidence).
  In-cluster proof that OCI chart resolution already works under this lab's
  ArgoCD: three in-repo charts declare `oci://` dependencies (hivetools,
  mariadb-operator, forgejo — grep this run) and deploy (EXPLORE §4/§5 live
  Apps). NOTE that's dependency-build-time OCI, not source OCI; the
  Application-source path is what option 3 adds.
- What changes: `charts/base/templates/appset-charts.yaml:64-70` must grow
  an OCI-shaped branch (repoURL gets the chart name, `path: "."`,
  `chart:` key retired) + every consumer `repository:` annotation + the
  Renovate side: the helm datasource reads an **index URL** [15] — OCI-only
  charts need a different datasource (docker-style registry listing) and the
  repo's own comment states renovate's helm managers cannot track OCI deps
  (`charts/forgejo/Chart.yaml:8`, repo evidence). This is the option with the
  biggest consumer-side diff and a renovate re-engineering leg.

### B4. Cross-cutting publishing facts

- Helm/OCI, ghcr pull-side anonymous for public artifacts — the cluster
  already renders oci:// deps without extra creds (B3 in-repo proof).
- `skip_existing` semantics differ across backends: Releases 409/422-guarded
  [17], OCI push `--skip-existing` supported in cr ≥1.9 [17], registry
  re-push of an existing chart version is a normal overwrite in chartmuseum
  registries (Gitea/Forgejo behavior not doc-tested here — flag).

### B5. (Adjacent) bump-back commit mechanics on the new forge

The `bump` job today commits Chart.yaml bumps to GitHub main via
add-and-commit (pure git; on Forgejo the equivalent push goes to
FORGEJO main and — via the automatic token — **does not re-trigger
main-sync**, because token-authored pushes don't re-run the repo's workflows
[2] + cf-119 EXPLORE §2). Consequences the plan must weigh (OQ-2):
(i) today's latent desync direction (GitHub-main ahead of Forgejo-main via
GitHub bump commits → main-sync non-FF failures) STOPS once GitHub's
release.yaml goes inert — nothing on GitHub advances main anymore;
(ii) the new lag is Forgejo-main ahead of GitHub: ArgoCD (which reads GitHub
main, EXPLORE §5) sees version bumps only after the next human push that
does trigger main-sync;
(iii) pushing bumps to GitHub with the cross-forge PAT instead DOES re-run
GitHub workflows — GitHub's docs contrast the two credential shapes exactly
here: events created with `GITHUB_TOKEN` do not trigger workflows, the same
event via a PAT stored as a secret does [35]; a PAT is not the workflow token.
So a hybrid "bump on Forgejo, also push to GitHub" needs the GitHub-side
release.yaml removed FIRST, else double-publish. `[skip ci]` cannot
selectively tame main-sync alone (skip strings apply to every workflow
matching the push event) [3, 16].

---

## Q-C — runner image toolchain

### C1. What `catthehacker/ubuntu:act-24.04` actually carries (upstream proof)

Build inputs: `Dockerfile` parameterized by `FROM_IMAGE/FROM_TAG`,
`TYPE=act`, `NODE_VERSION="20 24"` [27]; the `act-24.04` tag comes from
`build-ubuntu.yml`'s TYPE=act matrix leg (act-<ver> + act-latest aliases)
[28]; installer = `act.sh` [26]. Inventory relevant to these workflows
(all from [26]):

| Tool the workflows assume | In act-24.04? | Evidence detail |
|---|---|---|
| git | **YES** | git-core PPA, `safe.directory '*'` set system-wide |
| git-lfs | **YES** | installed via packagecloud script (matches the chart's own comment that act images carry git-lfs) |
| jq | **YES** | apt package AND pinned jq-1.6 binary on x86_64 |
| python3 | **YES** (3.12, Ubuntu 24.04 system python) | `python3-pip`, `python3-venv`, `pipx`, `python` symlink |
| node 20 + 24 | **YES** | `/opt/acttoolcache/node/...`, 24 prepended to PATH; `RUNNER_TOOL_CACHE`/`AGENT_TOOLSDIRECTORY` dirs exist 0777 (satisfies `cr.sh`'s tool-cache requirement [19]) |
| yq | **YES** | dedicated installer script |
| docker CLI + **buildx + compose** | **YES (client-side)** | moby-buildx plugin installed — `docker buildx build` works wherever a daemon answers (C2) |
| **helm** | **NO** | absent from `act.sh`; the ONLY extra script is `yq.sh`. GitHub-hosted ubuntu images DO preinstall Helm 3.22.1 [29] — the workflows' no-setup `helm` calls assume that (EXPLORE §4's caveat, now confirmed) |
| gh CLI | **NO** (act variant) | `gh.sh` only runs in the `-full` variant's `custom.sh` [26] |
| go | **NO** (act variant) | same |
| cosign/sigstore | **NO** anywhere | not in act.sh/custom.sh; release.yaml never uses it |
| sudo/apt | **YES** | `sudo` package; apt with retry-friendly defaults |

So the EXPLORE §9-5 "toolchain gap" is **exactly one tool** for the helm
pipeline — `helm` — plus one deliberate choice for python-version parity.

### C2. Remedies (ranked, with the repo's conventions)

1. **`azure/setup-helm`** per Q-A (mirrored, node24, get.helm.sh default,
   token deprecated, checksums auto [30]) — smallest diff: one setup step
   added to each helm-running job. `version:` pinned (e.g. the workspace's
   3.16-equivalent) keeps renders stable.
2. **Explicit install step** — `curl -fsSL https://get.helm.sh/helm-v…tar.gz`
   (or the repo's existing belt-and-braces `apt-get install -y jq` pattern
   in release.yaml:29 extended to helm). No action supply-chain surface at
   all; a few lines of pinned download+verify per job.
3. **Purpose-built image under `containers/`** per the container-creation
   skill (Dockerfile conventions, `:v<run>` + rolling tags, renovate ARG
   pins) — a `helm+node+git` CI image published to ghcr. Two structural
   cautions from the Forgejo docs: a runner label binds to an image **tag**,
   and "container images, once downloaded, are never updated" [32] — a
   rolling `:main` in a label therefore freezes until the daemon's local
   copy is pruned; digest-pinned labels (docs-recommended [32]) mean a
   manual runner-config change per bump, which collides with EXPLORE §4's
   "one release = one registration" law. Custom image = the heavy option;
   justified only if many more tools (cosign, gh…) arrive later.

### C3. Docker daemon inside jobs (the `docker/build-push-action` legs)

- Official state of the problem: job containers get **no** docker socket by
  default (`Cannot connect to the Docker daemon at unix:///var/run/docker.sock`
  is the documented symptom) [31].
- Supported solutions per [31]: **DinD sidecar** (isolated daemon; admin
  notes: capacity>1 shares one dind ⇒ jobs see each other; `/var/lib/docker`
  lives inside the dind container and is wiped on its recreation unless
  volume-mapped; build artifacts persist in the dind store) — or
  `container.docker_host: automount/unix://` (host socket exposed into jobs,
  explicitly "no security isolation", instance-trust required) — or LXC
  (services unsupported) — or VM isolation. A runner label with `:host` type
  runs steps directly on the runner machine (no job container; the
  docker-access doc treats host-mode as out of scope — no isolation at all,
  docs [32]).
- **Lab state (repo evidence, EXPLORE §4 + chart read this run)**: the live
  act-label runners use the docker backend with a **privileged DinD
  sidecar** exactly per the docs pattern: in-pod `DOCKER_HOST:
  unix:///var/run/docker.sock` (values.yaml:219-223 per EXPLORE), a PVC-
  backed `/var/lib/docker` ("Docker image cache — without it every job
  re-pulls" comment), `cache.enabled: true` in the runner config
  (`secret-runner.yaml`, read this run), `capacity: 1`. ⇒ **Yes: jobs on the
  lab's act runners have a usable docker daemon (in-DinD), and
  `docker/build-push-action` (CLI + buildx present in the image, C1) has a
  working target.** The host-socket (`automount`) case is chart-supported
  (`backend: host`) but has no live runner (cf-11 ruling, EXPLORE §4).
- Build-cache follow-on: `type=gha` cache uses the GitHub-Actions cache
  **protocol**, which "other cache services" may serve [37]; Forgejo's runner has its own cache service (`cache.enabled`,
  ACTIONS_CACHE_URL injected into jobs — docs confirm actions/cache works
  when the runner is configured, and errors when not [2]) ⇒ buildx `type=gha`
  is plausible on the lab runners, unproven — a first-fire item. The
  alternative that definitely works: registry cache (`type=registry`) or
  plain dind-local layer reuse (PVC-backed `/var/lib/docker`, above).
- k3s MTU note: EXPLORE §9-9's dockerd `--mtu 1450` mitigation applies to the
  dind daemon too (large image push fragility), not only action clones.

---

## Contradictions and how they were weighed

- **X1** `DEFAULT_ACTIONS_URL`: launch brief (github.com) vs v15.0 official
  docs (data.forgejo.org) [2, 3, 16]. Both are real defaults of different
  forges — the Gitea cheat sheet documents `github`/`self` keywords with
  default `github` [34], Forgejo ships `data.forgejo.org` [3, 16]. For the
  lab's Forgejo the docs win; the lab's admin setting remains unverifiable
  from the workspace (main-sync works under either).
- **X2** EXPLORE's feared "helm/python/jq" gap vs measured reality [26, 29]:
  only helm (plus optional gh/go) is missing; python3+pip, jq, git-lfs, yq,
  node 20/24, docker-CLI+buildx are present. The plan's toolchain work is one
  setup step, not an image rebuild.
- **X3** Launch-brief naming ("firstparty/checkouts", "gitea/actions") vs the
  actual first-party org `code.forgejo.org/actions` + clone host
  `data.forgejo.org` [2, 5]; `gitea.com/actions` exists on the Gitea side only.
- **X4** chart-releaser-action README example `@v1.7.0` with OCI input [18]
  vs releases API placing OCI in v1.8.0 [21]: trust the release history;
  require ≥v1.8.0 (and cr ≥v1.9.0 [22]) for any OCI path.
- **X5** "cr can target GitHub from anywhere" [17] vs "the wrapper's
  GITHUB_REPOSITORY-derived owner/repo + default `origin` remote break on a
  Forgejo checkout" [19] — both true; option 1 needs the override trio (step
  env / added remote / direct CLI).
- **X6** Launch brief's hint "act-runner 'upload-artifact' as a
  Pages-equivalent" vs the docs' run-scoped/90-day/no-cross-run artifacts
  [2] — artifacts are a within-run transport only; the helm package registry
  [13] is the same-forge durable store.
- **Unanimous across perspectives**: Forgejo Actions is "familiarity, not
  compatibility" [4, 6] — every moved workflow needs a smoke run; nothing in
  this research substitutes for first-fire evidence.

**Blind spot no perspective covered**: chart signing/provenance (cosign
bundles, attestations) — today's pipeline doesn't sign anything, so the move
neither requires nor (by these findings) enables signing; if the owner wants
provenance, that is new scope (cr supports `.tgz.prov` siblings in upload and
OCI push [17] — the hook exists).

---

## Implications for the plan (mapped to the OQ-1..OQ-6 the launch brief cites)

**Numbering caveat (honesty note)**: `EXPLORE.md` carries no explicit
`OQ-1..OQ-6` list — it references `OQ-n` inherited from **cf-119**'s
EXPLORE (§OQ-2 line 228 = bump/main-sync desync; §OQ-3 line 182 = runner
action egress) plus an unnumbered §11 unknowns list. The mapping below keys
the six unknowns the launch brief's questions target; if the planner meant a
different enumeration, the finding text still disambiguates.

- **OQ-1 — action availability/egress** (cf-119 OQ-3; EXPLORE §2, §9-4):
  ANSWERED structurally: checkout-class actions resolve today through the
  default mirror; the four third-party actions are NOT on the default mirror
  (measured) → moved workflows should write **absolute
  `https://github.com/...` URLs** (no instance-config dependency, admin-free)
  or replace them outright (paths-filter→git-diff loop; add-and-commit→raw
  git; bump-action→pybump step; chart-releaser-action→`cr` CLI or bumped
  action). github.com egress FROM the gpu runner remains unproven — keep it
  an explicit first-fire smoke step, and per-plan a `self`-mirror fallback
  [8] if egress fails.
- **OQ-2 — bump-back vs main-sync desync** (EXPLORE §6-1, §11): ANSWERED
  B5: three distinct push-semantics outcomes (auto-token ⇒ no re-trigger ⇒
  GitHub lag; PAT-to-GitHub ⇒ GitHub workflows re-run ⇒ double-publish
  unless GitHub release.yaml is inert first; `[skip ci]` ⇒ skips main-sync
  too). The plan must choose the bump target + trigger model per these
  mechanics; the old "GitHub ahead → non-FF" hazard disappears only when the
  GitHub twins go dead.
- **OQ-3 — act-image toolchain (helm?)** (EXPLORE §4 caveat, §9-5, §11 last
  bullet): ANSWERED: no helm; everything else needed is present (C1);
  remedy ranked: setup-helm > inline install > custom image (C2). The
  python-3.15 pins in the render-tests are a version-policy choice (system
  3.12 vs keep setup-python vs relax the pin) — plan decision.
- **OQ-4 — docker daemon for container builds** (EXPLORE §4/§9-3): ANSWERED:
  yes on the live docker-backend runners via privileged DinD + in-pod
  DOCKER_HOST (docs pattern [31] == chart shape); host-mode exists but has
  no runner. Plan constraints: dind image cache persists on PVC; capacity 1
  serializes the "parallel" matrix (EXPLORE §9-8); `type=gha` buildx cache is
  plausible-not-proven (C3) — treat a cache-mode downgrade as the fallback.
- **OQ-5 — `:v<run_number>` counter spaces** (EXPLORE §6-3, §9-6):
  INFORMED: `run_number`/`FORGEJO_RUN_NUMBER` exists but is per-repo on each
  forge [2]; no documented mechanism to carry GitHub's counter across — the
  plan must pick a scheme (seed via one-time ghcr tag scan, a monotonic
  replacement like `v<yyyymmdd.nn>`, or tolerate two numbering spaces with
  the container-creation rule "check the newest is YOURS" tightened to
  builder-aware). Research provides the facts; scheme choice is design.
- **OQ-6 — publish surfaces & consumer pins** (EXPLORE §5/§6-2): ANSWERED
  per option: (1) GitHub Releases+gh-pages FROM Forgejo — zero consumer
  diff, two wrapper pitfalls, keeps GitHub authoritative (B1); (2) Forgejo
  helm **package registry** — index+artifacts served by the forge itself,
  keeps the https-index contract, one URL sweep (7 live + 4 umbrella +
  annotations) + visibility/auth open question (B2); NO built-in Pages in
  15.0, artifacts unfit (X6); (3) OCI — supported by ArgoCD today [10, 11],
  needs pin bumps (action≥1.8/cr≥1.9 [21, 22]) or `helm push`, appset-
  template rework, renovate re-engineering (in-repo comment concedes the
  gap), ghcr-push ⇒ classic PAT `write:packages` (fine-grained cannot
  [1]) (B3).

---

## Open questions (for the batched plan round; research can't close them)

1. Which `DEFAULT_ACTIONS_URL` do the lab instances actually run (admin
   setting), and does the gpu runner have working egress to `github.com` for
   action clones AND for `api.github.com`/`uploads.github.com` + ghcr token
   auth (EXPLORE §9-11 path-3)? First-fire items.
2. Package/repo visibility on the prod instance: would the helm registry's
   `/api/packages/{owner}/helm/index.yaml` be anonymously readable by ArgoCD
   and Renovate, or does the plan provision read credentials (repo secret /
   hostRules) against git.spencerslab.com?
3. Does `actions/setup-python@v7` deliver python 3.15 on the act image in
   this lab (egress to python-versions manifests), or do the render-tests
   move to system python 3.12 / a different pin?
4. Is buildx `type=gha` cache functional against the lab runner's cache
   service (protocol-compatible per docs; untested combination) — or does
   the moved builder switch to `type=registry`/dind-local caching?
5. Bump-commit push target: Forgejo main with auto-token (accepting the
   GitHub-lag semantics of B5) vs also pushing GitHub with the PAT — and is
   the owner willing to sequence GitHub-workflow removal so the
   double-publish window never opens?
6. Tag-scheme decision for container images across the two run-number
   spaces (OQ-5 fact set) — pure design call for the human.

## Sources

(merged, deduped, numbered by `storm_run.py merge`; full audit trail —
perspectives, per-interview notes, raw sources — in
`/tmp/opencode/storm-runs/storm-runs/move-spencerslab-helmcontainer-builds-from-github-actions-to/`)

1. https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens — GitHub PAT model; fine-grained cannot access Packages
2. https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/user/actions/reference.md — Forgejo v15.0 Actions reference (uses resolution, SHA recommendation/CVE-2025-30066, runs-on/labels, strategy.matrix, concurrency, contexts, artifacts, cache)
3. https://forgejo.org/docs/v15.0/admin/config-cheat-sheet/ — v15.0 `[actions]` keys (DEFAULT_ACTIONS_URL default, retention, skip strings, dispatch limit)
4. https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/user/actions/github-actions.md — v15.0 known-differences list
5. https://forgejo.org/docs/v15.0/user/actions/actions/ — Using Actions v15.0 (mirror default, fully-qualified advice, node/docker/composite rules)
6. https://forgejo.org/docs/latest/user/actions/github-actions/ — "familiarity instead of compatibility" framing
7. https://forgejo.org/2026-04-release-v15-0/ — v15.0 release announcement (feature list; no Pages)
8. https://www.devroom.io/2026-03-15/using-github-actions-in-self-hosted-forgejo/ — DEFAULT_ACTIONS_URL modes incl. `self` mirroring recipe (community, secondary)
9. https://github.com/renovatebot/renovate/discussions/31666 — FORGEJO__actions__DEFAULT_ACTIONS_URL=self worked example (community, secondary)
10. https://argo-cd.readthedocs.io/en/stable/user-guide/oci/ — Argo CD OCI application sources, repo credentials, media types
11. https://argo-cd.readthedocs.io/en/stable/operator-manual/feature-maturity/ — unstable-feature list (OCI absent)
12. https://helm.sh/docs/topics/registries/ — Helm OCI push/install semantics
13. https://forgejo.org/docs/v15.0/user/packages/helm/ — Forgejo Helm package registry (push/install endpoints)
14. https://forgejo.org/docs/v15.0/user/packages/container/ — Forgejo OCI container registry ("supports … Helm Charts")
15. https://docs.renovatebot.com/modules/datasource/helm/ — Renovate helm datasource (index-based); Forgejo datasources exist in the module index
16. https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/admin/config-cheat-sheet.md — raw v15.0 cheat sheet (no `[pages]`)
17. https://github.com/helm/chart-releaser — `cr` CLI README (upload/index/push; git-base-url/git-upload-url; remote/pages flags; env precedence; GHE notes)
18. https://github.com/helm/chart-releaser-action — wrapper README (inputs, OCI examples, checkout-credential notes)
19. https://raw.githubusercontent.com/helm/chart-releaser-action/main/cr.sh — wrapper source (GITHUB_REPOSITORY owner/repo; tool-cache install; ensure_pages_branch; remote config; jq requirement)
20. https://raw.githubusercontent.com/helm/chart-releaser-action/main/action.yml — wrapper inputs (oci_*, skip_release)
21. https://api.github.com/repos/helm/chart-releaser-action/releases — action release history (v1.8.0 OCI push)
22. https://api.github.com/repos/helm/chart-releaser/releases — cr release history (v1.9.0 `cr push`)
23. https://raw.githubusercontent.com/dorny/paths-filter/master/README.md — push-mode git vs PR-mode GitHub API
24. https://raw.githubusercontent.com/EndBug/add-and-commit/main/README.md — pure-git action surface
25. https://raw.githubusercontent.com/EMAsphere/bump-helm-chart-action/main/action.yml (+ repo API probe) — composite pybump internals; org-name churn
26. https://raw.githubusercontent.com/catthehacker/docker_images/master/linux/ubuntu/scripts/act.sh — act-image installer inventory
27. https://raw.githubusercontent.com/catthehacker/docker_images/master/linux/ubuntu/Dockerfile — image build args (TYPE, NODE_VERSION)
28. https://raw.githubusercontent.com/catthehacker/docker_images/master/.github/workflows/build-ubuntu.yml — act-/runner-/full- tag matrix
29. https://raw.githubusercontent.com/actions/runner-images/main/images/ubuntu/Ubuntu2404-Readme.md — GitHub-hosted preinstalls (Helm 3.22.1)
30. https://raw.githubusercontent.com/Azure/setup-helm/main/action.yml — get.helm.sh default, node24, deprecated token
31. https://forgejo.org/docs/v15.0/admin/actions/docker-access/ — DinD / automount / LXC / VM answers + admin caveats
32. https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/admin/actions/configuration.md — label→image semantics, "images never auto-update", host label type
33. https://hub.docker.com/r/catthehacker/ubuntu — image variants overview (act subset vs full)
34. https://docs.gitea.com/administration/config-cheat-sheet/ — Gitea `[actions] DEFAULT_ACTIONS_URL` default `github`, values `github`/`self` (the contrast behind C1)
35. https://docs.github.com/en/actions/using-workflows/triggering-a-workflow — `GITHUB_TOKEN`-created events do not trigger workflows; PAT-created ones do (B5)
36. https://raw.githubusercontent.com/actions/setup-python/main/README.md — tool-cache-first, then `actions/python-versions` GitHub Releases downloads (A2 line)
37. https://docs.docker.com/build/cache/backends/gha/ — buildx `gha` cache backend: GitHub-provided cache **or other services supporting the GitHub Actions cache protocol**

Own measurements (this run): data.forgejo.org / code.forgejo.org / gitea.com
smart-git availability probes (A2 table), chart-releaser/EMAsphere API reads —
timestamps 2026-11-10, commands in the session trail.


---

## Post-plan round (2026-11-10, verification of approved-plan assumptions V-1..V-6)

Round type: post-planning verification after owner-approval (R1–R9 folded,
D1–D21). Verified against the APPROVED plan + DECISIONS + chunks C01–C04
(read this round). Sources 38–52 continue the numbered list below; prior
round's [1]–[37] unchanged. Lab version pins: Forgejo 15.0.10 (+gitea-1.22.0)
— code reads done against the **`v15.0/forgejo` release branch on
codeberg.org/forgejo/forgejo** (the lab's exact lineage), not main.

### Verdict table

| # | Assumption under test | Verdict |
|---|---|---|
| V-1 (D15) | date-tag `v<YYYYMMDD>.<10#HHMM>.<run>` orders under Renovate defaults; no regex rule breaks on it | **SUPPORTED** (2 wording notes, no plan change) |
| V-2 (D13/D14) | automatic workflow token can push packages (helm + OCI) to the same Forgejo instance | **REFUTED — WOULD CHANGE THE PLAN** (code-level proof; see V-2) |
| V-3 (D19/D20) | `[packages]` enablement declarable repo-side via `gitea.config.packages`; keys ENABLED + LIMIT_SIZE | **PARTIALLY REFUTED — plan-literal fix needed** (`LIMIT_SIZE` is not a v15.0 key; per-type keys; ENABLED already defaults true) |
| V-4 (D17) | workflow-level `concurrency:` honored (best-effort) on Forgejo 15; FF-only idempotent loop is the right fallback | **SUPPORTED** |
| V-5 (D18) | buildx `type=registry` mode=max against ghcr with the classic PAT; inputs unchanged except cache-from/to | **SUPPORTED** (one builder-driver guard) |
| V-6 | inline replacements' shallow-clone/fetch-depth failure modes | **MAPPED** (one top failure each, guards named) |

### V-1 — date tags under Renovate (D15): SUPPORTED

- Default versioning of the docker datasource is **`docker`** itself [48], whose
  documented semantics: "Renovate tries to accept and sort SemVer-like versions";
  **the text after the first hyphen is treated as a platform/compatibility
  suffix**; ranges unsupported; commit-hash-like tags ignored [49]. The
  `v<YYYYMMDD>.<10#HHMM>.<run>` shape has **no hyphen**, so no suffix logic
  interferes; all three components are numerics → numeric semver compare.
- Order checks: across months (`20261130 < 20261201` major ✓), across midnight
  (major dominates minor ✓), within a day with leading zeros stripped
  (`$((10#0905))=905 < 1005` ✓). **The `10#` arithmetic is load-bearing**: an
  uncoerced `0705` minor is not valid semver (leading zeros) — C02 t8 already
  asserts the coercion exists ✓. Same-minute duplicates resolved by the
  run_number patch ✓ (two distinct runs can never share a run_number; a
  re-fired dispatch is a new run_number).
- Legacy space: `v84` coerces to `84.0.0`; `v20261110.x` is one enormous major —
  `config:recommended` (the repo's only extends) creates separate major PRs,
  nothing suppresses majors for ownyourio images: grepping all 13 customManagers
  + 10 packageRules of `renovate.json` (this round) found **no rule that
  regex-parses `v<digits>`-style tags for ghcr.io/ownyourio** (the only
  versioning-regexes are k3s `+k3s\d+`, traefik-plugins `v\d+\.\d+\.\d+`,
  grafana revision, llama-swap UPSTREAM `unified-vulkan-(\d+)`, Dockerfile ARG
  git-pins — none touches ownyourio tags). `allowedVersions: /^v3\./` binds
  only `helm/helm`.
- Extraction path confirmed live: `renovate[bot]` commits `14e63aa77`
  ("Update ghcr.io/ownyourio/wekan-mcp Docker tag to v162") and `2ecaf66c2`
  (renovate-mcp v84) touch the `services/*/prod/values.yaml` pins — the
  **helm-values manager** fileMatches `/(^|/)values\.ya?ml$/` and supports the
  conventional `image:`/`repository:`/`tag:` formats + the docker datasource
  natively [50]; the tag-shape it extracts is order-agnostic. The pin-bump flow
  survives a date tag unchanged.
- Order-of-magnitude precedent (empirical): the landed `v148→v162` bump is
  itself a MAJOR jump under docker versioning — Renovate filed it, so majors
  are demonstrably unsuppressed for these packages; the date-jump behaves the
  same, one time.
- Wording notes (no plan change): (a) D15 calls the minor "minute-of-day" but
  the pinned arithmetic yields `HHMM` — also monotonic within a day; keep the
  arithmetic, fix the prose in C03 when the AGENTS/skills sentence is written
  (or call it "time-of-day (HHMM, base-10)"). (b) `:main`/`:dev` rolling tags
  coexist in the same repos; non-semver-like tags simply don't compete [49] —
  unchanged behavior.

### V-2 — same-forge package push with the AUTOMATIC token (D13/D14): REFUTED

Chain of primary evidence, all on `v15.0/forgejo`:

1. What the automatic token IS: the v15.0 user docs define it as
   repository-scoped — "write permission to **the repository** … push commits,
   create a label, merge a pull request"; "any attempt to use it on other
   repositories … 404"; pushes made with it never trigger workflows [43].
   The advanced-features "Uploading to a package registry" section [2-round
   ref] only POINTS to the registry docs — it does not document the
   workflow token as a package credential. (RESEARCH round's [2] citation was
   read too generously by D14; correction below.)
2. The package-registry docs show only username+password / user-PAT auth
   (`curl --user {username}:{password}`, `helm repo add --username/--password`
   with "personal access token instead" for 2FA) [13].
3. Code proof — the credential plumbing: docker/login-action + curl basic auth
   land in the **Basic auth method**, which DOES recognize the actions task
   token — but maps it to a **synthetic user**: `&actionsTaskTokenAuthenticationResult{user: user_model.NewActionsUser(), taskID: …}`
   [38, 39]. That result reports **no token scope** (`Scope() →
   optional.None`) [39].
4. The packages router for `/api/packages/{owner}/helm/…` is mounted with
   `verifyAuth(r, []auth.Method{OAuth2, Basic, nuget.Auth, conan.Auth, chef.Auth})`
   [40]; `reqPackageAccess(Write)` [40] first checks the token-scope branch —
   skipped for the task token (None scope) — then falls to
   `ctx.Package.AccessMode < write && !IsUserSiteAdmin` → 401 with
   `"user should have specific permission or be a site admin"`.
5. `ctx.Package.AccessMode` comes from `DeterminePackageAccessMode(owner, doer)`
   [41, 42] — which for an **organization owner** (CuratedForest) resolves the
   doer's org-membership/team `unit.TypePackages` permissions; the synthetic
   Actions user holds none — and the function carries the literal upstream
   comment **`// TODO: ActionUser permission check`** [41]. There is no
   special-casing of task tokens in the packages router files inspected
   (api.go, helm/, container/: zero ActionsTask/synthetic hits this round).
6. Community corroboration: a Forgejo self-host write-up states plainly:
   "Forgejo create a Automatic token with each workflow run. **But you can't
   use it to push images to a registry**" — recipe = mint a user token [44].
7. Not inherited from Gitea, not later: Gitea's job-token scopes feature
   (Permissive/Restricted incl. packages) is a post-1.22 addition documented
   only in current Gitea docs [45]; the v1.22.0 release notes — the lab's
   fork base — contain no actions-token-packages feature [46]; Forgejo's own
   TODO comment confirms it never landed in 15.0 [41].

**Consequences (plan-changing):**
- `forgejo-publish` (C01) with `${GITHUB_ACTOR}:${GITHUB_TOKEN}` → **401 on
  every run, first fire included** — the UA-5 "fallback: owner mints a Forgejo
  PAT" is the *only working shape*, not a fallback. Same for the C02
  instance-OCI login/push (`github.actor`/`github.token`): container uploads
  go through the same packages auth stack (`verifyContainerAuth` with the same
  Basic method + package context; the OCI docs page [14] shows user-token
  auth).
- UA-1's extended `PUSH_TOKEN_GH` CANNOT cover the instance legs (a GitHub PAT
  is not a credential the Forgejo packages API accepts) — the answer to the
  launch question is: **neither the auto-token nor PUSH_TOKEN_GH; a THIRD
  credential is required** — a Forgejo user PAT (the org-owner identity with
  packages write via membership; the token-scope check at [40] honors the
  classic unrestricted/user-scoped tokens) stored as an Actions secret on the
  prod instance.
- This collides with ruling R7 "no new secret names". The plan must either
  (a) add one same-forge secret (e.g. `PUBLISH_TOKEN_FORGEJO`) and amend
  R7/D14 + C01 AC7/t7/t8, C02 AC5/t6 (their "zero secrets in the instance
  legs" assertions currently enforce the broken design!), or (b) ship the
  auto-token shape knowingly-red-first and flip on UA-5 evidence. Research
  recommends (a) — the suites would otherwise pin a provably failing
  credential topology.
- The non-re-trigger property D14 also leaned on for the bump loop guard is
  REAL and unaffected [43] (that's about workflow triggers, not packages).

### V-3 — repo-side `[packages]` enablement (D19/C04): PARTIALLY SUPPORTED

- Declaration path: **confirmed end-to-end**. Upstream chart
  `forgejo 17.3.1` (the pinned dep of `charts/forgejo`) keeps
  `gitea.config.packages: {}` by default [47]; templates render
  `.Values.gitea.config` generically into the `<fullname>-inline-config`
  **Secret** whose keys become app.ini sections [47] — the exact mechanism the
  lab's LFS precedent uses (chart values comment :92-100 cited in C04). A
  `packages:` map added to the infra custom-values slice therefore lands in
  app.ini; helm map-merge semantics hold (deep merge, siblings preserved).
  C04 t6's render-proof shape (assert `[packages]` lines the way `[lfs]`/
  `[server]` render) is the right test.
- **Keys (the refutation):** v15.0 `[packages]` has `ENABLED` **default true**
  and **no generic `LIMIT_SIZE`** — sizes are per-type:
  `LIMIT_SIZE_HELM`, `LIMIT_SIZE_CONTAINER`, … (defaults **-1 = unlimited**,
  format accepts `1000` / `1 MB` / `1 GiB`) [16]. A `LIMIT_SIZE:` key would
  render into app.ini and be **silently ignored by the binary** — C04 t3's
  pinned key set {ENABLED, LIMIT_SIZE} enshrines the wrong literal. Fix (C04
  dev-notes already pre-authorize exactly this "distinct flag → update t3 in
  lockstep" move): key set → `{ENABLED, LIMIT_SIZE_HELM, LIMIT_SIZE_CONTAINER}`
  (GENERIC optional only if the plan ever pushes generic packages; it doesn't).
  Also UA-4's "the 50-era default does not [fit]" is stale — current default
  is unlimited; the caps become OPTIONAL hygiene bounds, not a blocker.
  (`enforcePackagesQuota` in the push middleware [40] consults the separate
  quota subsystem, `[quota]` **default disabled** [16] — no action needed.)
- OCI needs no extra section: same `[packages]` subsystem, docs state the
  container registry "follows the OCI specs and supports … Docker and Helm
  Charts" [14].
- ENABLED already-true ⇒ the instance's registries may already answer on
  git.spencerslab.com today (the upstream chart doesn't disable them either —
  no packages block rendered = binary default). The C04 declaration stays
  correct as an explicit pin (C04's note anticipated this branch verbatim).
  **Anonymous pull**: `DeterminePackageAccessMode` grants READ only for a
  publicly-visible owner/org (ghost/nil doer path) [41]; private org ⇒
  consumers (ArgoCD/Renovate) will later need credentials — consistent with
  the round-1 OQ-2 and D20's deferral to the migration card. No change for
  cf-55 (nothing reads them yet).

### V-4 — concurrency + two-runner bump safety (D17): SUPPORTED

- `concurrency` IS implemented in Forgejo 15 Actions — workflow-level
  `concurrency.group` + `cancel-in-progress`, with the docs' own words:
  "Forgejo makes a **best-effort** … in exceptional circumstances this cannot
  be guaranteed" [2]; "Multiple jobs within a workflow are NOT affected by the
  concurrency setting" [2] (it gates RUNS, not jobs — exactly how D17 uses it).
  Queued-but-never-dispatched runs are killed after `ABANDONED_JOB_TIMEOUT`
  (default 24h) [3] — so a queued duplicate bump cannot linger forever.
- Double-bump race analysis (two capacity-1 runners, near-simultaneous
  triggers): each workflow run's `bump` is a SINGLE job (D4) so no same-job
  parallelism inside one run. Across runs, B's FF-only push onto a main
  advanced by A is **rejected by git itself** (non-force push of stale head =
  the transport refuses, no state change — git-native semantics, the same
  property main-sync's suite t4 relies on [main-sync.yaml header + repo]);
  B's bounded retry re-pulls and re-derives from the NEW tree+index — since B
  only bumps charts in ITS OWN diff, and A's bump is now B's base, no
  same-change double-bump is produced. Residual benign skew: if A's `release`
  leg died before upload, B may publish 1.0.7 leaving an unpublished 1.0.6
  gap — harmless under `skip_existing` [17]. Verdict: the plan's
  belt(best-effort concurrency)+braces(FF-only idempotent loop) is
  exactly the right pairing; no change. (Test-writer note: t7's static shape
  asserts — pull-before-push, numeric retry cap, no-force — are the
  provable surface; interleaving itself is UA-5's first-fire observation.)

### V-5 — buildx registry cache vs ghcr (D18): SUPPORTED, one guard

- Backend semantics [51]: `registry` cache = OCI-external cache image,
  `mode=min|max` supported (max caches all stages ✓ multi-stage), `ref` is any
  pullable/pushable name (branch-scoped `<container>-buildcache:<branch>`
  fine ✓), `image-manifest`/`oci-mediatypes` default true (plain OCI manifests
  — ghcr serves them), `ignore-error:false` default → **a cache-push failure
  reddens the build** (consistent with the plan's "loud failure" posture; if
  the owner later prefers cache best-effort, `ignore-error=true` is the
  documented knob — no plan change needed now).
- **The one real pitfall** (GHA-specific? no — a DRIVER-specific one):
  "This cache storage backend works with the default `docker` driver only when
  the containerd image store is enabled" [51]. Lab dind = plain moby,
  overlay2 store — so the plan's preserved `docker/setup-buildx-action` step
  (→ `docker-container` driver, where registry-cache is fully supported) is
  load-bearing for the cache leg, not just hygiene. Guard for the test writer:
  the docker-build suite must assert the buildx setup step EXISTS and precedes
  build-push (C02's t5 allow-list already includes it; t9 should also pin the
  ordering or the dev silently dropping setup-buildx turns every cache-to red).
- Action inputs unchanged except `cache-from`/`cache-to` (build-push-action's
  documented input pair; login/metadata untouched ✓ C02 shape). No Forgejo-
  side cache dependency introduced (the earlier `type=gha` unprovenness is
  moot under R9).

### V-6 — inline replacements: the ONE top failure mode each (shallow-clone lens)

checkout's documented default: "Only a single commit is fetched by default,
for the ref/SHA that triggered the workflow … Set `fetch-depth: 0` to fetch
all history for all branches and tags"; the token is persisted into local git
config (push auth works in-job) [52]. The four replacements, one pinned
failure each:

1. **paths-filter → `git diff --name-only` detect loop**: with the default
   depth-1 checkout, `HEAD^` / the event `before..sha` range DO NOT EXIST →
   the diff errors under `set -e` (job red) or, worse, yields an empty change
   set ⇒ **silently green "no charts/containers changed" no-op**. Guard (C01/
   C02 already mandate): `fetch-depth: 0`; suite leg asserts the checkout
   `with: fetch-depth: 0` in BOTH jobs that diff (main-sync.yaml:30-31 comment
   is the same lesson already paid [repo]).
2. **chart-releaser-action → direct `cr` upload/index**: `cr`'s own change
   detection (`lookup_latest_tag` = `git fetch --tags` + `git describe --tags
   HEAD~`) **collapses to the root commit under shallow history** — the
   documented fallback path is `git rev-list --max-parents-0` [19] ⇒ every
   chart repackages on every run (versions churn, uploads rely on
   skip_existing). Second-order: `cr index --push` needs the Pages branch
   fetched from the remote named by config `remote:` (default origin = the
   FORGEJO checkout [17, 19]) — the plan's AC9 GitHub-remote requirement is
   this same trap; keep it. Guard: fetch-depth 0 + `git fetch --tags` (or
   `fetch-tags: true`) + explicit `remote:` config.
3. **bump action → stdlib regex version loop**: checkout leaves the workspace
   at a **detached HEAD** at `$GITHUB_SHA` — the local branch ref `main` may
   not exist, so a loop that "pulls main" via bare `git pull` (no upstream)
   errors or no-ops ⇒ **bumps computed against a stale tree** and two runners
  mint the same next version. Guard (t7 shape): explicit
  `git fetch origin refs/heads/main:refs/remotes/origin/main` + rebase/merge
  onto the fetched remote tip (or reset the worktree to it — local-side only,
  never force the remote) before computing the next version; assert the
  remote-tip re-read happens INSIDE the retry loop, not once outside it.
4. **add-and-commit → raw `git commit && git push`**: same detached-HEAD +
   single-commit world ⇒ `git push origin main` pushes a nonexistent/stale
   local branch — the only correct spelling is the explicit refspec
   `git push <remote> HEAD:refs/heads/main` (main-sync's own line-43 form),
   and it MUST expect non-FF refusal when main advanced mid-job. Guard: t7's
   refspec-shaped push + bounded retry already pin this [C01].

### Plan-impact summary (explicit, per the launch contract)

- **WOULD CHANGE THE PLAN — V-2** (automatic-token package push). Affected:
  **D14** (premise wrong), **C01** (`forgejo-publish` auth step + AC7/AC8 +
  t7/t8/t10 credential-topology legs currently pin the broken shape),
  **C02** (instance login step + AC5/t6 likewise), **UA-1** (extended
  PUSH_TOKEN_GH does NOT cover instance legs — answer is "a third credential:
  a Forgejo user-PAT secret"), **UA-5** (401-fallback becomes the primary
  design), and collides with **R7** ("no new secret names") — owner ruling
  needed.
- **WOULD CHANGE THE PLAN-LITERALS — V-3** (`LIMIT_SIZE` key does not exist
  in 15.0): affected **C04** (Tasks wording, AC1, t3 key-set — dev-notes'
  escape hatch applies), **UA-4** (unit check → per-type keys; default
  unlimited not "50"), **D19** wording. No topology change.
- **NO CHANGE** — V-1 (two prose nits for C03 wording), V-4 (confirms D17 as
  designed), V-5 (confirms D18 + one suite-ordering guard for the test
  writer), V-6 (guards already present in C01/C02 ACs; handed to agent-test
  as pinning targets).

### New sources (post-plan round; [1]–[37] from the pre-plan round unchanged)

38. https://codeberg.org/forgejo/forgejo/raw/branch/v15.0/forgejo/services/auth/method/basic.go — task-token branch → synthetic Actions user [V-2]
39. https://codeberg.org/forgejo/forgejo/raw/branch/v15.0/forgejo/services/auth/method/auth_result_actionstask.go — `Scope() → None`, ActionsTaskID [V-2]
40. https://codeberg.org/forgejo/forgejo/raw/branch/v15.0/forgejo/routers/api/packages/api.go — `verifyAuth(OAuth2, Basic, …)`, `reqPackageAccess` scope→401 flow [V-2, V-3]
41. https://codeberg.org/forgejo/forgejo/raw/branch/v15.0/forgejo/services/packages/perm.go — `DeterminePackageAccessMode` + `// TODO: ActionUser permission check`; anonymous-read = public-owner only [V-2, V-3]
42. https://codeberg.org/forgejo/forgejo/raw/branch/v15.0/forgejo/services/context/package.go — `PackageAssignment` computes `ctx.Package.AccessMode` [V-2]
43. https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/user/actions/basic-concepts.md — Automatic token: repository-write scope, 404 cross-repo, no re-trigger [V-2]
44. https://nexveridian.com/blog/forgejo-pushing-container-images/ — community: auto token cannot push images; user PAT recipe (corroboration) [V-2]
45. https://docs.gitea.com/usage/actions/token-permissions/ — Gitea job-token scopes (Permissive/Restricted incl. packages) — a post-1.22 Gitea feature, absent in Forgejo 15 [V-2 context]
46. https://api.github.com/repos/go-gitea/gitea/releases/tags/v1.22.0 — fork-base release notes: no actions-token-package feature [V-2 negative]
47. oci://code.forgejo.org/forgejo-helm/forgejo@17.3.1 (helm pull this round; digest sha256:38d6d9ea57512808754d310bd6c0fe717d697b5f67ea4e34bdb8500ab49b0343) — `gitea.config.packages: {}` default; `templates/gitea/config.yaml` renders the `<fullname>-inline-config` Secret [V-3]
48. https://docs.renovatebot.com/modules/datasource/docker/ — Table of values: default versioning `docker` [V-1]
49. https://docs.renovatebot.com/modules/versioning/docker/ — accepts/sorts SemVer-like; post-hyphen = platform suffix; no ranges [V-1]
50. https://docs.renovatebot.com/modules/manager/helm-values/ — fileMatch `/(^|/)values\.ya?ml$/`, conventional image-repository-tag formats, docker datasource [V-1]
51. https://docs.docker.com/build/cache/backends/registry/ — registry cache params (mode min|max, ignore-error default false, any ref) + the default-docker-driver/containerd restriction [V-5]
52. https://raw.githubusercontent.com/actions/checkout/main/README.md — single-commit default fetch, `fetch-depth: 0` requirement, token persistence [V-6]

Own measurements (this round): codeberg code fetches on `v15.0/forgejo`
(HTTP 200 bodies quoted above), `helm pull` of the upstream chart, grep of
`renovate.json` managers/rules + `git log -S` of the two renovate[bot] pin
bumps (`14e63aa77`, `2ecaf66c2`).

## Round-4 research (2026-11-25): Chart.lock ownership + calendar chart versions

Round type: decision-grade research for the owner's two asks on the live
fire class ("the lock file (Chart.lock) is out of sync with the dependencies
file (Chart.yaml)") and the calendar-versions wish. STORM method, 5 lenses
(Renovate internals, Helm core, release-pipeline/cr, versioning schema,
GitOps-consumer); new numbered items run 53–88 (1–52 unchanged, none re-used).
Tool pins this round reasons against: Renovate 44 docs pages state
"correspond to Mend Renovate 44.261.2" (lab image is 44.181.5 — same v44
architecture [53][58]); Helm docs current at v4.3.1 with the v3 line at
3.22.1 (the lab's baked runner helm is exactly v3.22.1, so every Helm claim
below is read against the `dev-v3` branch, cross-checked against `main`=v4
where it matters); chart-releaser read at tag v1.10.1 (the version the
forgejo-runner bakes).
Repo grounding read this round: release.yaml @3f21e85e8,
containers-build.yaml, renovate.json, renovate.yaml workflow, .gitignore,
live Chart.yaml/Chart.lock drift table over all 74 charts.

### TL;DR

1. The drift is NOT a Renovate design gap — the instance's Renovate TRIED to
   update every Chart.lock and FAILED in-sandbox (smoking-gun PR comments:
   `EACCES /opt/containerbase/data` → `Install tool helm failed`, and
   `spawn helm ENOENT`); it then opens the yaml-only PR after 2 h with a red
   `renovate/artifacts` check, which the human-merge posture walks straight
   over. GitHub-era Renovate (pre-11-19) updated the locks in the same PRs
   because the hosted environment has helm.
2. Renovate's helmv3 lockfile update is DEFAULT behavior (no
   postUpdateOptions opt-in exists any more); a `helm-locks` manager has
   never existed upstream. The fix is an environment fix: give the Renovate
   container a runnable helm (self-baked image with helm v3 +
   `binarySource=global`, or the official `-full` image — which ships helm
   **v4** and needs a cross-version lock check first).
3. The pipeline can own the heal unconditionally: `helm dependency update`
   regenerates a stale lock and is a byte-no-op when the lock is already
   fresh; there is no `--force-update` on dep build (that flag belongs to
   `helm repo add`). Because `cr package` Build()s EVERY chart every fire,
   one drifted chart poisons the whole release leg — the heal must cover the
   tree cr touches, not just the changed matrix. RECOMMENDED: BOTH — fix
   Renovate's image (root cause at the PR) AND self-heal in the pipeline
   (deterministic green guarantee); details and the exact knob settings below.
4. Calendar chart versions (`2026.11.1++`) are legal semver end-to-end: helm
   package validates with Masterminds `NewVersion` (rejects LEADING ZEROS —
   so the month must be unpadded, `date +%Y.%-m`, the D15 lesson reborn);
   the bump loop's own `ver()` already parses 4-digit majors; ArgoCD and
   Renovate consume exact pins, so the 1.0.x → 2026.y jump is one benign
   major PR per pin (all 61 own-chart pins verified exact — zero ranges).
5. A deterministic walk rule for the bump loop (single month clock stamp,
   N = same-month max(tree, gh-pages index).patch+1 else N=1) preserves the
   D17 FF-only loop unchanged; live precedents exist (NVIDIA GPU Operator
   22.9.0 style CalVer, current Helm charts shipping YY.MM.N — sbomify
   26.11.1, ethora-core).

---

### Q1-A — Renovate side: what the helmv3 manager does TODAY

**A(a) Lock-in-same-PR is the default, not an option.** The current `helmv3`
manager's artifact updater [54] runs, for every dependency change in
Chart.yaml when a `Chart.lock` exists in the repo, a three-part command
sequence in the Renovate sandbox: `helm registry login` per OCI repo that has
hostRules credentials [55], `helm repo add <name> <url> --force-update
[--username/--password]` for every non-OCI repository found in the NEW
Chart.yaml *and* the existing lock (plus `registryAliases`) [54], then
`helm dependency update <chart-dir>` — and commits the regenerated
`Chart.lock` into the same PR/branch. The old `postUpdateOptions` opt-ins
for this are RETIRED: the current allowedValues list contains exactly one
helm entry, `helmUpdateSubChartArchives` (vendored-`charts/` archives
support); there is no `helm3` and no `helmLockFileUpdate` [58]. The helmv3
manager docs now describe the lock only via `lockFileMaintenance` support
("delegated to the underlying package manager") [53]. `helm-locks` as a
separate manager DOES NOT EXIST upstream: zero matches in the entire
renovatebot/renovate GitHub issue+PR index [59], and it is absent from the
docs manager list [53]. What upstream *does* offer for lock-only refreshes
is `lockFileMaintenance` (off by default, `before 4am on monday` schedule) —
for helmv3 it deletes Chart.lock and runs `helm dependency update` [58].

**A(b) What fails / does not update** (source-level [54]):
- No committed `Chart.lock` → Renovate returns without touching anything
  (it never CREATES a lock). Our locks are committed (only `charts/**/charts`
  tgz caches are gitignored) ✓.
- The helm exec itself fails → `artifactErrorResult` [54]; the branch worker
  then STILL raises/updates the PR with the Chart.yaml-only change once the
  PR is older than 2 hours ("raise PR with lock file errors"), after adding
  the `:warning: Artifact update problem` PR comment and a failing
  `renovate/artifacts` status check (default `statusCheckWhen.artifactError
  = "failed"`) [57][58]. This is the exact observed shape — see A(d).
- OCI deps need `hostRules` (hostType docker, matchHost per-repo or global)
  for login; classic http(s) repos need hostRules hostType `helm` creds for
  private ones [53][55]. All our dep repos are public https — no
  credentials needed.
- Repository *aliases* (`@repo` / registryAliases) resolve only if
  `registryAliases` config maps them [53]; our Chart.yaml files use full
  URLs ✓. Transitive and alias deps are handled by delegating to helm
  itself (`helm dep update` rewrites the lock including aliases) — Renovate
  does not parse the graph itself [54].

**A(c) `helm-locks`: not upstream** — see A(a); anyone citing it is
describing either a config pattern of `lockFileMaintenance` on helmv3 or an
unmerged proposal.

**A(d) The REAL root cause of our drift — measured, with smoking guns.**
Own-forensics at 3f21e85e8:
- GitHub-era Renovate commits updated locks: `73da0c56b` (traefik 42.4.1,
  11-18, author `renovate[bot]@users.noreply.github.com`, Chart.lock +
  Chart.yaml in one PR) and `bcf254c3b` (argo-cd 10.11.6, 11-03) ✓.
- Instance-era Renovate commits skip the lock: `80c503f72` (argo-cd 10.18.2,
  11-19), `95533725d` (argo-cd 10.18.3, 11-24), `a619fe6ad` (traefik 42.4.2,
  11-24) — all author `tms@spencerslab.com` (the RENOVATE_GIT_AUTHOR stamp),
  Chart.yaml-only.
- Live instance PRs carry the proof: PR #112 (argo-cd 10.18.3) status check
  `renovate/artifacts => failure | Artifact file update failure`, combined
  state `failure`, and the artifact-problem comment quoting, for
  charts/base/Chart.lock: `[06:21:18] ERROR: EACCES: can't write to
  /opt/containerbase/data, the current user has no write permission …
  FATAL: Install tool helm failed in 3ms` [61]; PR #113 (traefik 42.4.2)
  quotes `spawn helm ENOENT` for BOTH traefik Chart.locks [62].
- Mechanism: the workflow runs the **slim** image `ghcr.io/renovatebot/renovate:44.181.5`
  (renovate.yaml:67), whose default `binarySource` is **`install`** — tools
  are fetched at runtime via containerbase `install-tool` [56][60]; our repo
  even pins `constraints.helm: 3.22.1`, which `install` mode feeds to that
  installer [54][60]. On the act runner the containerbase data dir is not
  writable by the job user (EACCES), and helm is not otherwise on PATH
  (ENOENT). On the old GitHub platform the same default worked because the
  hosted runners have a writable/executable toolchain. The red
  `renovate/artifacts` check lands on the PR but nothing blocks the merge —
  AGENTS.md's "human-merge posture" walks over it — so yaml-only drift
  accumulates on main, then dies at the next release fire (and today, at
  this HEAD, drift is LIVE again in exactly base + both traefik charts).
- Config knobs that actually change behavior, ranked:
  1. **Self-baked renovate image with helm v3 inside + `binarySource=global`**
     (env `RENOVATE_BINARY_SOURCE=global`) — the C05/C06 forgejo-runner
     precedent applied to renovate: `FROM ghcr.io/renovatebot/renovate@<digest>`
     + COPY helm (digest-pinned OCI stage, same shape as
     containers/forgejo-runner's helm sidecar), pinned immutable tag law
     applies (runners never re-pull cached tags). Under `global`,
     `constraints.helm` is IGNORED [58] — so the image IS the version pin,
     and it must be a **v3** to keep lock digests byte-compatible with the
     v3.22.1 the release pipeline runs (see B matrix).
  2. **Official `-full` image** (`:44.x-full`, tag suffix per the build docs):
     binarySource=global + most tools pre-installed, "no outbound access at
     runtime" [60] — but the base-image Dockerfile installs `helm v4.3.2`
     into full [60], while our pipeline builds locks/consumes with helm v3;
     the digest function itself is byte-identical v3 vs v4 (`json.Marshal`
     of `[2][]*chart.Dependency`, unchanged on `main`) [66][73], so
     compatibility is *probably* fine — one live cross-check (helm4 `dep
     update` → helm3 `dep build`) must gate this choice.
  3. Keep slim + `install` but fix the sandbox (writable
     `/opt/containerbase/data` via container options/volume): reintroduces
     the get.helm.sh egress fragility class D33 retired; rejected for
     the same reason release.yaml left setup-helm behind.
  4. Optional belt: `lockFileMaintenance {enabled:true}` on the helmv3
     manager (weekly Chart.lock refresh PRs even without dep bumps) —
     cheap, matches A(a) semantics [53][58].

---

### Q1-B — Pipeline side: exact helm dependency semantics

Verified against the `helm/helm` **dev-v3** source (the lab's v3.22.1 line)
and the versioned docs [69][70][71][72][76][77]:

**B(a) `helm dependency build` vs `update` — the abort condition.**
`Build()` reads Chart.yaml + Chart.lock and computes
`resolver.HashReq(req, lock.Dependencies)` = `sha256:` over the **JSON
marshal of BOTH dependency lists** (Chart.yaml deps and lock deps) [73]; if
that sum ≠ the lock's `digest:` field, build aborts with exactly our error
"the lock file (Chart.lock) is out of sync with the dependencies file
(Chart.yaml). Please update the dependencies" [72]. Which fields count:
every field that serializes on `chart.Dependency` — name, alias, version,
repository, tags, condition, enabled, import-values — on BOTH sides;
the top-level chart `version:` is NOT hashed (a plain Chart.yaml version
bump never invalidates the lock ✓ — load-bearing for the bump-commit-
with-lock idea). The `generated:` timestamp is not part of the digest.
Other build aborts: repo not added → `ErrRepoNotFound` "…Please add the
missing repos via 'helm repo add'" [69] (the C08 "Add repositories" step is
what serves this); **no Chart.lock at all → build silently mirrors
`update`** (documented behavior, `lock == nil → m.Update()`) [69][72][78].
`Update()` never aborts on staleness by definition — it re-negotiates from
Chart.yaml, downloads, and REWRITES the lock; and when the recomputed digest
equals the existing one it skips the write entirely — so update on a fresh
lock is a **byte-no-op** (idempotency for the bump job ✓) [72]. It also
auto-adds unknown repos to its own repo file (`ensureMissingRepos`; the
source comment flags this for removal in Helm v4) [72] — so
`helm dep update` works even where `build` would demand repo add first.

**B(b) `--force-update` does NOT exist on `helm dependency build/update`.**
The dependency subcommand flags are exactly: --verify, --keyring,
--skip-refresh, --username/--password/--cert-file/--key-file/
--insecure-skip-tls-verify/--plain-http/--ca-file [70][71]; the docs page
(4.3.1, identical flag set for build) confirms [71]. `--force-update` belongs
to `helm repo add` — which is precisely how Renovate drives it [54]. The
regeneration verb IS `helm dependency update` [78].

**B(c) The failure matrix (lock stale/fresh × deps cached/not):**

| command | lock stale, any cache state | lock fresh, deps NOT in charts/ | lock fresh, deps cached |
|---|---|---|---|
| `helm dep build` | **ABORTS** — digest check runs BEFORE any download [72] | fetches repos+tgz (always downloads; no cache-skip — `downloadAll` copies via tmpPath every run) [72] | re-downloads anyway, succeeds |
| `helm dep build` (no lock at all) | n/a — behaves as `update` [69][78] | n/a | n/a |
| `helm dep update` | succeeds, rewrites lock | succeeds, downloads | success, lock NOT rewritten (digest-equal skip) [72] |
| `helm lint` | passes (lint never reads the lock) | **WARNING only** "found in Chart.yaml, but missing in charts/ directory" → exit 0 unless --strict [74] | passes |
| `helm package` (no -u) | passes if charts/ populated (package ignores the lock); fails if not, on `CheckDependencies` ("missing in charts/"), not on staleness [75][76][77] | **ERROR** [76][77] | success; tgz embeds what's in charts/ |
| `helm package -u/--dependency-update` | runs `manager.Update()` first → self-heals, packages fresh [77] | same | same |
| `cr package` (v1.10.1, what release + forgejo-publish run) | **ABORTS** — runs `downloadManager.Build()` per chart before packaging [79] | needs the added repos + network (same as build) | Build() still re-downloads (no offline shortcut), then packages |

Two corrections to the brief's framing: (i) the fire died at the EXPLICIT
`helm dependency build` step of test-build (release.yaml:139) — a stale lock
aborts regardless of caching, and the tgz caches are gitignored so charts/
is always empty at checkout anyway [72]; (ii) `cr package charts/*/` runs on
EVERY chart every fire, so a drifted chart OUTSIDE the changed set kills the
release + forgejo-publish legs too — blast radius is the whole published
tree, not the matrix slice [79]. The current test-build failure simply
precedes that.

**B(d) If the bump job ran `helm dependency update` per chart and committed
Chart.lock alongside the version bump:**
- vs cr packaging: compatible — the release/forgejo-publish jobs re-checkout
  main TIP (they already do, V-6-3), so they Build() against the healed
  lock; the top-level version bump never invalidates the digest [73].
- vs ArgoCD: compatible — consumers pull the packaged tgz from the index;
  the tgz embeds the subchart archives Build() fetched; ArgoCD's helm
  `template` never sees Chart.lock or charts/** [81].
- vs FF-only single-writer law (D17): compatible — the heal runs INSIDE the
  existing loop iteration (after `git reset --hard origin/main`, before the
  version rewrite): two files in one commit is still one FF push; a rejected
  push re-derives everything including a fresh heal pass [72].
- Idempotency: fresh lock → helm skips the write → `git add Chart.lock`
  stages nothing → commit carries only Chart.yaml (no churn, no empty
  commits under `set -euo pipefail` if the loop guards the commit on staged
  content). `helm dep update` needs no repo-add step (auto-adds) but DOES
  need upstream egress — a class the release leg already depends on via cr
  Build(), so the bump job gains no NEW dependency, only earlier exposure
  (a transient upstream outage now reddens bump instead of release —
  availability trade-off, loudly either way).
- One design trap to respect: healing only the CHANGED charts leaves the
  cr-wide blast radius exposed — either heal the full tree (cost ≈ what cr
  package already pays on every fire) or heal-on-test-build-failure per
  chart. The plan must pick; the safe shape is full-tree heal in bump.

---

### Q1-C — Verdict: who owns Chart.lock?

| option | latency-to-heal | failure modes it leaves | blast radius on the four workflows |
|---|---|---|---|
| **Renovate-owns only** (fix the image; today's default behavior finally runs) | 0 (lock lands in the bump PR itself, reviewable) | human edits of Chart.yaml deps never get a lock (but those are still charts/** pushes → the fire's test-build would die); a future sandbox regression silently re-opens yaml-only PRs — only the red `renovate/artifacts` check is the signal, and nothing today blocks on it | release.yaml untouched; renovate.yaml image line + env; main-sync/containers-build/builder-bootstrap untouched |
| **Pipeline-owns only** (bump-job `helm dep update` + commit; test-build switches to update or heals first) | ≤ next fire — and every drift source is itself a charts/** push, which IS a fire trigger, so effectively at-the-push | locks on main stay stale between the renovate merge and the fire (cosmetic; PRs show it); bump job reddens on upstream-egress blips (same class release already has); doesn't heal *unpushed* local state | release.yaml (test-build, bump); suites forgejo-release re-pin; strata lock-guard flips from enforcer to witness; other three workflows untouched |
| **BOTH** | Renovate: 0 for bot bumps; pipeline: 0 guarantee at publish | Renovate-internal failures degrade to "pipeline heals" (silent, benign); pipeline never sees drift from renovate when renovate works | union of the two |

2025-era practice elsewhere: chart-releaser-action ships **no** lockfile
automation — its README never mentions Chart.lock at all [80]; helm's own
best-practices page for dependency versions recommends *ranges* (`~1.2.3`)
over pins and carries no lock guidance [82]; the tools that keep locks
fresh are the dependency updaters themselves: Renovate does it by default
[54], Dependabot regenerates the lock natively in its own implementation —
"generated, not authored" is the maintainers' framing for why
lockfile-only config does not apply [67][68][63]. The norm that holds:
whoever changes Chart.yaml regenerates the lock in the same transaction;
nobody in the known-good setups lets a stale lock reach the release
branch.

**RECOMMENDATION: BOTH, pipeline as the guarantee.**
1. Pipeline (load-bearing, kills this fire class deterministically):
   test-build's smoke swaps `helm dependency build` → `helm dependency
   update`; the bump loop, after its main-tip reset and before the version
   rewrite, runs `helm dependency update` over every chart carrying a
   Chart.lock (full-tree, cheapest correct shape per B(d)), stages
   `charts/*/Chart.lock` next to `charts/*/Chart.yaml` (with a
   staged-content guard before `git commit`), FF-pushes as today.
2. Renovate (root cause at the PR): give the instance Renovate a runnable
   helm v3 — a lab-baked image
   (`FROM ghcr.io/renovatebot/renovate:44.x@digest` + helm 3.22.1 sidecar
   copy, exactly the containers/forgejo-runner pattern) with
   `RENOVATE_BINARY_SOURCE=global`; keep the immutable pin + digest law.
   Accepting the official `-full` image instead is only lawful after the
   one-time helm4-update → helm3-build digest cross-check passes.
3. Optional: enable helmv3 `lockFileMaintenance` weekly (cheap drift sweep
   while renovate itself is being fixed).

---

### Q2 — calendar chart versions

Owner framing: "I'd like version to work like containers-build.yaml —
2026.11.1++ … expectation is they'll get there as I naturally update &
rebuild".

**(a) Semver legality + tool acceptance.** SemVer 2 clause 1: X.Y.Z are
"non-negative integers, MUST NOT contain leading zeroes … Each element MUST
increase numerically (1.9.0 -> 1.10.0 -> 1.11.0)" — no width cap, so
`2026.11.1` is a normal legal version [84]. Helm's chart-version law
(topics/charts): "should follow the
SemVer 2 standard but it is not strictly enforced", non-semver explicitly
disallowed, `x`/`x.y` coerced [75]; `helm package` validates with
Masterminds `semver.NewVersion` [76], whose regex is
`v?(0|[1-9]\d*)...` per component — **rejects leading zeros** [88].
Therefore the D15 lesson returns exactly: the month MUST be unpadded —
`date +%Y.%-m` (or `10#` coercion) — `2026.07.1` is invalid semver and dies
at `helm package`; `2026.7.1` orders correctly. Unquoted YAML is safe for
the 3-dot form (it never parses as a float; that trap is the 2-segment
`1.0`/`2026.11` case the docs' appVersion warning describes [75]).
cr: treats version as a string (tgz name `<name>-<version>.tgz` ↔
release tag `<name>-<version>`, index key) [79]; ArgoCD pulls by exact pin
[81]; Renovate's helm datasource default versioning is the `helm`
module = semver/Masterminds semantics, ranges supported [64][65]; the OCI/
Helm-registry path only ever puts version in tag/reference strings, same
grammar as image tags (our containers already ship 26.11.N there). No
4-digit-major gotcha found in any of the four surfaces. apiVersion v2 is
orthogonal; Helm 4 keeps the same validation. Our own bump loop's `ver()`
helper already parses 2026.11.1 (3 numeric parts) and tuple-compares
correctly against 1.0.x [repo release.yaml:186-190].

**(b) Ordering + upgrade safety.** 2026.11.1 ≫ 1.0.203 numerically: `helm
upgrade`/`helm template` place no guard on chart-version majors (version is
a release marker only; only `kubeVersion` and `appVersion` semantics are
checked — appVersion is "informational, no impact on chart version
calculations") [75]. ArgoCD: chart+exact targetRevision pin → repo resolves
that literal; no downgrade or major guard; and Argo CD re-renders with the
helm binary per release — the docs page states modern Argo CD renders with
**helm v4** ("The only Helm binary used to render charts in Argo CD
(starting with version 3.5) is v4") [81] (see Contradictions — the repo's
"renders with helm v3" law is going stale, but that is ArgoCD's bundled
binary, not a constraint on our version FORMAT). Renovate consumption of
the published index: all 61 own-chart pins are EXACT (audited: `#version:
1.0.x # renovate: datasource=helm registryUrl=…` + appset `appName/
baseChartVersion` pairs; zero `^ ~ *` ranges anywhere in services/,
charts Chart.yaml dep pins, or custom-values — grep clean [repo]); under
`config:recommended` a 1.x → 2026.y pin update is a normal **major** update
PR (majors are not suppressed for these packages — no packageRule touches
them; the only helm-related holds are `helm/helm` + `alpine/helm` tool
holds [repo renovate.json rules 4/5], and rule 9's regex versioning covers
the *docker* calendar tags only — chart pins keep default `helm` versioning
and need no regex, unlike the containers precedent). First-fire churn: one
major-bump PR per pin per chart that converts (16+17+12+5+… pins across the
61-line set), human-merged like every other renovate PR; prConcurrentLimit
0 already accepts the volume.

**(c) The N-walk design (parity with containers-build, adapted).** The
containers pipeline derives N by walking PUBLISHED tags (union max of two
registry tag lists + bounded existence walk) because its two registries are
async truth sources with no shared transaction [containers-build
:185-330]. For charts the situation is kinder: the **tree is a
synchronous, FF-ordered shared ledger** — every minted version is committed
before it is published — so the bump loop's existing idempotency pair
(max(tree, gh-pages index) + 1) already IS the two-runner-safety mechanism
(D17 law; the FF push is the lock). Deterministic calendar rule proposed
for the bump leg (single-writer loop, re-derived every attempt, one clock
stamp per job like the containers `month=` law):

```
Y.M = date -u +%Y.%-m            # fixed once per run (containers law)
base = max(ver(tree), ver(published gh-pages index))   # tuple compare, today's ver() parses it
if base.major == Y and base.minor == M:  new = (Y, M, base.patch + 1)   # same-month walk
elif base < (Y, M, 0):                   new = (Y, M, 1)  # month-change reset, legacy 1.x first jump, first-ever chart
else:                                    FAIL LOUD      # base ahead of clock = clock skew; never walk backwards
```
Edge cases resolved: charts whose published max predates the calendar
(1.0.202) take the strict-jump to 2026.11.1 under the `base < (Y,M,0)` arm
— no `max(index)+1` is needed because `(1,0,202) < (2026,11,0)` by
definition; the instance Helm registry stays handled by its existing
skip-if-present guard (reading it in bump would drag FORGE_PUSH_TOKEN into
the bump job's credential surface for a truth the tree already carries —
recommend tree+gh-pair, instance as skip-only); re-run of an old pipeline
after a new fire re-derives from the advanced tree tip and pushes one
benign extra N (today's D17 shape, unchanged); midnight-straddle is moot
within one run because month is stamped once; two runners both derive N,
first FF wins, second re-derives N+1 — monotone (the D17 loop law itself;
the write-skip freshness check is what makes the heal no-op repeat-safe
[72]). The test-build smoke regex (`^version: (\d+)\.(\d+)\.(\d+)$`,
patch+1) needs no change: on a converted chart it walks N locally.

**(d) Migration shape.** Convert-at-next-change works cleanly: index lists
are mixed-version-tolerant (every published version is a separate entry;
"latest" = highest semver = the calendar one, which is desired); consumers
pin exact versions and get bumped by renovate per chart (b), so one chart
jumping while neighbors stay 1.x breaks nothing; the C01 same-indent
index-pairing guard and value-semantics legs (t15) are name/version-string
blind — 4-digit majors parse under the same `ver()` (they are the exact
shape the guard was written for). No global cutover commit is needed; the
owner's "as I naturally update & rebuild" path is the mechanism.

**(e) Precedents + anti-patterns.** CalVer-in-semver is a documented
pattern (calver.org's own scheme table: YYYY/M/MM; case studies NVIDIA GPU
Operator `22.9.0` — "new major every six months", RAPIDS `21.06.00`) [85];
live Helm-chart examples today: sbomify's chart ships `26.11.1 (YY.MM.MICRO
CalVer)` and ethora-core states "The chart version is CalVer, YY.M.patch
for the month it ships" [86][87]; the lab itself already publishes
`26.11.N` calendar container tags and a `pipenv 2026.11.0` install-tool pin
appears in Renovate's own base image — the 4-digit-major form is
business-as-usual across the ecosystem. Anti-pattern to respect: any
consumer range like `^1.0.0` or `~1.0` would silently STOP updating at the
jump (caret excludes 2026.x) — **audited this repo: zero chart-version
ranges; all pins exact** ✓. The only ranges in the chart world here are
upstream `dependencies[].version` pins, which our renovate helmv3 manager
rewrites as exact values. Second watch-point: `version: 1.0.0` for
brand-new charts (AGENTS law) — decide whether new charts start at the
current `Y.M.1` or at 1.0.0-and-convert; either is consistent with the walk
rule (c).

---

### Contradictions and how they were weighed

- **"Renovate doesn't update Chart.lock" vs "it does"** — both are true
  depending on environment. The docs [53][58] and source [54] show the
  behavior is default; our instance's PR evidence [61][62] shows the
  EXECUTION fails (EACCES/ENOENT), and the 2-hour rule [57] then ships the
  half-PR. Weighted toward the live PR artifacts + source code over prose.
- **Old RESEARCH/plan prose ("GitHub Renovate opened lock-keeping PRs")** —
  the pre-migration commits (42.4.0/42.4.1, #899/#921) prove hosted Renovate
  succeeded where the slim-in-act-container fails; consistent, not
  contradictory — the migration (card #139) moved the failing environment.
- **Repo law "ArgoCD renders this repo's charts with helm v3" (renovate.json
  rules 4/5, D38) vs ArgoCD docs "starting with version 3.5 the only Helm
  binary used to render is v4"** [81]. Not load-bearing for either ask
  today (both lock-format and version-format claims hold on v3 and v4 —
  HashReq identical, semver validation identical), but it means the
  helm-v4 hold's stated REASON is stale: ArgoCD itself will move under us;
  the v3 alignment that still binds is OUR baked runner + cr's bundled helm
  v3 libs. Flag for a future owner ruling; do not change the holds here.
- **D15's rejected date-tag spelling** (hyphen form broke renovate sorting)
  vs today's calendar wish — the same law applies in the semver world:
  zero-padding and hyphens are the killers; unpadded numeric YYYY.M.N
  sorts everywhere by construction.
- **containers `yy.mm` vs charts `2026.mm`**: owner asked 4-digit for
  charts; 2-digit year sorts fine too, but 4-digit avoids any future
  collision with genuine 26.x majors and makes the ledger self-describing;
  adopting owner's literal.

### Implications for the plan (what the planner must decide differently)

- Q1 is NOT solved by a renovate.json knob — no knob enables what is already
  on; the plan decides the IMAGE route (baked-with-helm recommended; full
  image gated by the v4→v3 digest cross-check) and the pipeline heal shape
  (full-tree dep update inside the bump loop + staged-content guard;
  test-build smoke choice: `update` vs heal-then-`build`).
- Committing Chart.lock beside Chart.yaml in the bump commit requires no
  new laws: FF loop, credential topology (auto token, no re-trigger), cr
  and ArgoCD consumption all verified compatible above.
- The bump version-derivation block becomes the calendar walk of (c);
  suites re-pin: the t-suite's `ver()`-pair legs, the smoke regex leg, and
  (if Q1 pipeline lands) a new leg per healed file pair. AGENTS.md's
  "bumps Chart.yaml version (patch)" sentence and the
  helm-chart-creation skill versioning law change with it (rulesync twin).
- Calendar adoption is per-chart-on-next-change; the plan must add the
  `date +%Y.%-m` non-padding law (D15 twin) and the FAIL-LOUD clock-skew
  arm, and decide the new-chart seed version rule.

### Open questions (for the batched plan round; research can't close them)

1. Renovate image route: custom `containers/renovate` bake with helm v3
   (+`RENOVATE_BINARY_SOURCE=global`) vs official `-full` image (needs the
   one-time helm4-writes / helm3-builds digest cross-check gate) vs
   leaving the red-check-merge hole to process (owner's own review posture)?
2. Pipeline heal placement: heal in bump only (release legs then never see
   drift, but test-build must stop `build`-ing or run after a heal) vs heal
   in test-build too; and full-tree vs changed-set — full-tree is the only
   shape that also protects `cr package charts/*/'s whole-tree Build().
3. Should `lockFileMaintenance` (weekly lock refresh) be enabled as a third
   belt, with its PR volume accepted?
4. New-chart seed: `1.0.0` (convert at first change) or straight to
   `Y.M.1`?
5. Does the owner want the instance-index consulted in the N derivation
   (extra credential in bump job) or stay tree+gh-pages pair + skip guard?
6. Year 2027+ rollover is safe by arithmetic; but confirm the owner wants
   MONTH granularity (not the containers' `yy.mm` 2-digit) — adopted above
   pending explicit word.

### Reliability notes (round-4 peer review, per the storm method)

- **Confidence by finding** (1–10): Renovate-default lock flow [54 source
  read] 9 — code is unambiguous, but read at `main` (44.261.2-era) while
  the lab runs 44.181.5; the two artifacts.ts commits straddling are
  behavior-stable, not re-diffed per release. Instance root-cause
  (EACCES/ENOENT) 10 — live PR comments + status checks quoted verbatim.
  Helm build/update/package/lint matrix 9 — all primary claims read from
  dev-v3 source, cross-checked with v4 text; the one soft spot is mapping
  dev-v3-tip semantics onto the shipped 3.22.1 binary (same line, tagged
  v3.22.1 source not re-fetched per file). cr packager 10 — tag-pinned
  source read. Calendar semver legality 9 — parser-level evidence across
  every consuming surface; the ArgoCD/OCI legs rest on docs, not a lab
  instance probe. Walk rule 8 — design derived from the repo's own proven
  D17 loop, not yet executed.
- **Weakest claim**: the full-image route's v4↔v3 lock-digest
  compatibility — textual identity of HashReq [66][73] strongly implies
  it, but no live `helm4 dep update → helm3 dep build` run was performed
  here; it is gated as a plan-side verification, do not ship on this
  sentence alone.
- **Not verified, flagged as-is**: the dependabot "regenerates Chart.lock
  natively" specifics come from ecosystem threads [67][68][63] — direction
  certain, mechanism (pure-Ruby vs helm invocation) not source-read.
- **Perspective weighting**: the Renovate lens dominated (appropriate —
  it owns the drift's first cause); the GitOps-consumer lens was thin
  because pin-shape facts were all repo-side greps; a fleet-operator lens
  (per-cluster baseChartVersion override annotations, appset.yaml:44-49)
  was noted but not exercised — calendar jumps interacting with frozen
  per-cluster overrides is a plan-round question, not a research gap.
- **Blind spot none of the interviews probed**: chart-releaser's own
  provenance/signing path with a rebuilt lock (checksums under `cr
  package --sign`) — irrelevant while signing is off, listed for
  completeness.

### Sources (round 4; 53–88; 1–52 from earlier rounds unchanged)

53. https://docs.renovatebot.com/modules/manager/helmv3/ — lockFileMaintenance support for Chart.lock; helmUpdateSubChartArchives; hostRules for private repos/OCI; registryAliases [A]
54. https://raw.githubusercontent.com/renovatebot/renovate/main/lib/modules/manager/helmv3/artifacts.ts — DEFAULT lock flow: `helm repo add --force-update` + `helm dependency update`; no lock → null; failure → artifactErrorResult; generated-line-blind diff [A(a),A(b),A(d),C]
55. https://raw.githubusercontent.com/renovatebot/renovate/main/lib/modules/manager/helmv3/common.ts — OCI registry-login from hostRules [A(b)]
56. https://raw.githubusercontent.com/renovatebot/renovate/main/lib/config/options/index.ts — binarySource default `install`, allowedValues [global,docker,install,hermit]; docker mode deprecated [A(d)]
57. https://raw.githubusercontent.com/renovatebot/renovate/main/lib/workers/repository/update/branch/index.ts — artifactErrors: PR raised anyway >2 h ("raise PR with lock file errors"), error-topic comment + removal logic [A(d)]
58. https://docs.renovatebot.com/configuration-options/ — postUpdateOptions allowedValues (no helmLockFileUpdate/helm3), lockFileMaintenance default {enabled:false,"before 4am on monday"}, statusCheckWhen.artifactError default "failed", notes that constraints/installTools do NOT take effect under binarySource=global [A(a),A(d)]
59. https://api.github.com/search/issues?q=repo:renovatebot/renovate+%22helm-locks%22 — total_count 0: no upstream helm-locks manager/issue/PR [A(a)]
60. https://docs.renovatebot.com/docker-build-process/ + https://raw.githubusercontent.com/renovatebot/base-image/main/Dockerfile — slim=install (runtime egress), full=global (pre-installed tools; full stage `RUN install-tool helm v4.3.2`; `install-tool pipenv 2026.11.0`); default-tools policy "generally only the full image" [A(d), Q2(e)]
61. https://git.spencerslab.com/api/v1/repos/CuratedForest/SpencersLab/issues/112/comments + …/commits/95533725d/status — LIVE: renovate/artifacts=failure; EACCES /opt/containerbase/data, "Install tool helm failed in 3ms" [A(d)]
62. https://git.spencerslab.com/api/v1/repos/CuratedForest/SpencersLab/issues/113/comments — LIVE: "spawn helm ENOENT" for both traefik locks [A(d)]
63. https://stackradar.io/blog/open-source-kubernetes-dependency-management — corroboration: "Dependabot has supported Helm since 9 April 2025" [C]
64. https://docs.renovatebot.com/modules/datasource/helm/ — reads index.yaml; DEFAULT versioning `helm`; release timestamps from `created` [Q2(a),Q2(b)]
65. https://docs.renovatebot.com/modules/versioning/helm/ — semver + Masterminds semantics, ranges supported [Q2(a),Q2(b)]
66. https://raw.githubusercontent.com/helm/helm/main/internal/resolver/resolver.go + main pkg/chart layout (dependency.go compat accessors + v2/) — v4 HashReq textually identical to v3's; v2/v3 metadata compatibility kept [A(d)-full-image cross-check]
67. https://github.blog/changelog/2025-04-09-dependabot-version-updates-now-support-helm/ — Dependabot Helm version-updates GA [C]
68. https://github.com/dependabot/dependabot-core/issues/2237 (+ ecosystem note in #15216: "Chart.lock is generated, not authored") — Dependabot Helm implementation thread [C]
69. https://raw.githubusercontent.com/helm/helm/dev-v3/cmd/helm/dependency_build.go — build desc ("will not re-negotiate…"; "If no lock file is found… mirror… update"); ErrRepoNotFound → "Please add the missing repos via 'helm repo add'" [B(a),B(c)]
70. https://raw.githubusercontent.com/helm/helm/dev-v3/cmd/helm/dependency.go — full dependency-subcommand flag set; NO --force-update [B(b)]
71. https://helm.sh/docs/helm/helm_dependency_build/ (4.3.1; 3.22.1 twin at /docs/v3/) — user-facing synopsis + identical flag list [B(b)]
72. https://raw.githubusercontent.com/helm/helm/dev-v3/pkg/downloader/manager.go — Build(): digest-check abort, hasAllRepos, UpdateRepositories unless --skip-refresh, downloadAll (always fetches via tmpPath — no charts/ cache-skip); Update(): ensureMissingRepos (v4-removal TODO), digest-equal ⇒ lock NOT rewritten [B(a),B(c),B(d),Q2(c)]
73. https://raw.githubusercontent.com/helm/helm/dev-v3/internal/resolver/resolver.go — HashReq = sha256 over json.Marshal([Chart.yaml deps, lock deps]); top-level chart version outside the hashed inputs [B(a),B(d),A(d)]
74. https://raw.githubusercontent.com/helm/helm/dev-v3/pkg/lint/rules/dependencies.go — dep missing from charts/ = WARNING severity (exit 0 sans --strict); lock never consulted [B(c)]
75. https://helm.sh/docs/topics/charts/ — "version should follow SemVer 2 … not strictly enforced"; non-semver disallowed, x/y coerced; package name = version token; appVersion informational; dependencies repo + repo-add note [B(c),Q2(a),Q2(b)]
76. https://raw.githubusercontent.com/helm/helm/dev-v3/pkg/action/package.go — validateVersion = Masterminds semver.NewVersion; CheckDependencies error "missing in charts/" [B(c),Q2(a)]
77. https://raw.githubusercontent.com/helm/helm/dev-v3/cmd/helm/package.go — -u/--dependency-update runs downloader Manager.Update() before packaging [B(c)]
78. https://helm.sh/docs/helm/helm_dependency_update/ — the regeneration verb; synopsis of deps-in-Chart.yaml flow [B(a),B(b),B(c)]
79. https://raw.githubusercontent.com/helm/chart-releaser/v1.10.1/pkg/packager/packager.go — cr package: downloadManager.Build() per chart, error ABORTS the run; then helm action.Package; version handled as the Chart.yaml string [B(c),B(d),Q2(a)]
80. https://github.com/helm/chart-releaser-action — README (v1.7–v1.9): zero Chart.lock/dependency automation; skip_packaging escape hatch [C]
81. https://argo-cd.readthedocs.io/en/stable/user-guide/helm/ — helm used only to `helm template`; chart+targetRevision exact pins; "starting with [Argo CD] version 3.5 [the] only Helm binary used to render charts is v4" [B(d),Q2(a),Q2(b),Contradictions]
82. https://helm.sh/docs/chart_best_practices/dependencies/ — recommends RANGE dep versions (`~1.2.3`), no lockfile guidance (measured 2026-11-25) [C,Q2(e)]
83. Own measurements (round 4): full-tree Chart.yaml↔Chart.lock drift scan at 3f21e85e8 (DRIFT live: charts/base argo-cd 10.18.3↔10.18.2; charts/traefik + charts/traefik-zerotrust traefik 42.4.2↔42.4.1; all other dep-carrying charts in sync); git-log provenance split GitHub-era (locks present: bcf254c3b, 73da0c56b) / instance-era (locks absent: 80c503f72, 95533725d, a619fe6ad) with author/committer emails; Forgejo API PR/commit status reads; renovate.json audit (13 customManagers, 11 packageRules, no enabledManagers ⇒ built-in helmv3+helm-values live; constraints.helm 3.22.1 present); services/ pin-shape audit (61 datasource=helm pins, all exact 1.0.x; zero ^/~/* chart-version ranges repo-wide); release.yaml/containers-build.yaml line-level reads (@3f21e85e8).
