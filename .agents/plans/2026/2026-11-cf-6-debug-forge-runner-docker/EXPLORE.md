# EXPLORE — cf-6-debug-forge-runner-docker: the forge builder's missing docker socket

Scouted 2026-11-21 from the worktree `cf-6-feat-forgejo-container-builds` on branch
`cf-6-feat-forgejo-container-builds-rebuilt` @ `9ff565b60`. Read-only: `git fetch` +
git reads, file reads, read-only k8s MCP probes (dev, infra, gpu, ai-gpu, grow, home,
media, monitoring, proxy-local clusters; no `admin-*`, no pod exec, no secret reads —
one secret read was attempted and is `forbidden` for the readonly SA, recorded as fact),
read-only registry/instance HTTP probes (ghcr, git.scifi.farm, git.spencerslab.com
anonymous APIs), upstream source fetches (forgejo/runner v13.2.0 + main, docker/cli,
docker/buildx, forgejo.org docs). One temp worktree of `origin/main` at
`/tmp/opencode/main-tree` (suite runs) — **removed at the end** (verified in
`git worktree list`). Nothing committed, nothing edited outside this file.

**Bottom line (one paragraph).** The failing step is not a missing docker daemon and
not a runner-host problem. The infra instance's runner is a pod
(`gpu-forgejo-runner-gpu-0`, gpu cluster) that runs a healthy in-pod DinD sidecar; the
runner uses that socket to *spawn* each job container (which is why checkout runs), but
the runner's rendered `config.yaml` sets no `container.docker_host`, so the runner
default (`-`, "do not share the socket with job containers" — Forgejo's documented
v4+/v5+ security default, verified in the v13.2.0 source) applies, and the ephemeral
job container is created **without** `/var/run/docker.sock`. Inside the job, `docker
login` survives (the docker CLI falls back to a client-side registry auth when the
daemon dial fails — verified in the CLI source, which is why that step is green), then
`docker build` (buildx → moby client) dies with exactly the reported error:
`ERROR: failed to connect to the docker API at unix:///var/run/docker.sock; check if
the path is correct and if the daemon is running: dial unix /var/run/docker.sock:
connect: no such file or directory`. The one-line repo fix is `docker_host:
unix:///var/run/docker.sock` in the chart's rendered config (`charts/forgejo-runner/templates/secret-runner.yaml`,
docker-backend branch); it covers both runner releases (dev + gpu). The "in-pod dind
daemon (chart socket contract)" the workflow comment assumes exists only on the
runner→dind leg — the job→dind leg was never wired (cf-97 scoped the runner→dind
socket fix; the 2026-10 dind research knew about the gap and its rejected alternatives;
the cf-6 workflow assumed it across).

## 1. Post-merge main state (task 1)

- `git fetch origin` clean. **`origin/main` tip = `b80fae102343402f71e6d73afc9572bd0908057d`**
  ("Update actions/checkout action to v7 (#104)", 2026-11-21 14:48:03 +0000 — a
  Renovate PR, the newest run on main).
- The cf-6 work landed on `origin/main` as **two commits with amended SHAs** (the
  task-named `9ff565b60`/`bc38a759f` are the *branch* commits, both present locally):
  - `3b13f5c62` — "cf-6: forgejo container builds — rebuilt on main, squashed"
    (author 2026-11-16; the re-squash of the branch tip `bc38a759f`)
  - `6230e1297` — "feat(cf-6): forgejo container builds — calendar tags, contains()
    guards, and renovate rule" (author 2026-11-16 20:24:36; **committer 2026-11-19
    15:47:06 +0000** — the landing the owner shipped; it adds the run -3 ticket record
    folder + the surviving parity-sweep files).
  - `git merge-base HEAD origin/main` = `69ccbe0bb` — the branch is exactly the landing
    content; `git diff 9ff565b60 6230e1297` is only other post-landing main work
    (boards/cf-55/seaweedfs/etc.).
- **Landing choreography (archaeology, matters for the run timeline):** on the night
  of **2026-11-16 23:17** the owner first pushed the whole cf-6 work to main as a
  *different* commit chain (tip `1fc86d598b`, a 105-file diff over `69ccbe0bb`
  including `.forgejo/workflows/containers-build.yaml` + 6 `containers/**` files); that
  push is containers-build run 59 (§5). On **2026-11-19 15:47** main was rewritten to
  the current history (re-squash + cf-55 `1ada03a50` + pipeline commits). `1fc86d598b`
  is **not** an ancestor of current main; its file content is (all 6 containers files
  byte-identical on both).
- Verified on `origin/main` (not the stale local `main` ref, which sits at `7886e20b4`):
  - `.forgejo/workflows/containers-build.yaml` — **present** (blob `9eee60f5`). Diff
    vs worktree HEAD (`5956d77b`): **only** the three `actions/checkout@v6` → `@v7`
    lines from `b80fae102`. Logic identical.
  - `scripts/forgejo-container-detect.sh` — **present**, blob-identical to HEAD.
  - `renovate.json` — **present**, blob-identical to HEAD; the plain-image
    `customManager`'s `managerFilePatterns` carries the **3rd entry**
    `/(^|/)services/[^/]+/[^/]+/values\.ya?ml$/` (L19). `tests/renovate/forgejo-move-config.sh`
    m5 pins 10 packageRules — **PASS on main** (run this session, §8).
  - `.forgejo/workflows/` on main = `containers-build.yaml`, `main-sync.yaml`,
    `release.yaml` (cf-55 chart release, merged 2026-11-18 as `1ada03a50`),
    `renovate.yaml`.

## 2. The failing step, precisely (task 2)

Workflow on `origin/main` (`.forgejo/workflows/containers-build.yaml`, 405 lines).
PR arm = job `build-pr` (`name: pr ${{ matrix.container }}`), guard
`forgejo.event_name == 'pull_request' && (vars.ROLE == null || contains(vars.ROLE,
'dev')) && needs.detect-changes.outputs.changed-containers != '[]'`,
`runs-on: ubuntu-24.04`, **no job-level `container:` and no `services:`** — plain
shell steps in the runner's job container. Matrix = the detector's JSON list.

The failing step, verbatim from `origin/main`:

```yaml
- name: build and push the pr tag          # (the report quotes it as "…pr tags")
  env:
    FORGE_SERVER_URL: ${{ forgejo.server_url }}
  run: |
    set -euo pipefail
    forge_registry=${FORGE_SERVER_URL#https://}
    forge_registry=${forge_registry%/}
    branch=$(bash scripts/forgejo-container-detect.sh sanitize '${{ forgejo.head_ref }}')
    branch=${branch:0:96}
    sha=$(git rev-parse --short HEAD)
    pr_tag="pr-$branch-$sha"
    if [ "${#pr_tag}" -gt 128 ]; then echo "pr tag exceeds the registry tag grammar" >&2; exit 1; fi
    tag="$forge_registry/curatedforest/${{ matrix.container }}:$pr_tag"
    docker build -t "$tag" "containers/${{ matrix.container }}"
    docker push "$tag"
```

- **Tooling:** the plain **docker CLI** inside the job container (the act image
  `ghcr.io/catthehacker/ubuntu:act-24.04`, label-mapped in the runner config), which
  delegates `docker build` to the **buildx** plugin (default since docker 23). The
  repo script contributes only `sanitize` (pure shell, no docker). No
  `docker/setup-buildx-action`, no `DOCKER_HOST` anywhere in the workflow, no
  `container:`/`services:` on any job.
- **Env/vars:** `FORGE_SERVER_URL: ${{ forgejo.server_url }}` — the instance's
  ROOT_URL, scheme-stripped + trailing-slash-trimmed to the registry host (the
  workflow's "derive, never literal" law). Credentials: `secrets.FORGE_PUSH_TOKEN`
  (per-instance human-minted non-admin `write:package` PAT; the PR arm uses it only in
  the preceding "log in to the forge registry" step — `docker login "$forge_registry"
  -u forge-push --password-stdin`). GHCR credential `secrets.GHCR_PUSH_PAT` is
  release-arm only; the PR arm works with zero ghcr credentials.
- **Runner-side job configuration:** capacity 1, `timeout: 30m`,
  `shutdown_timeout: 5m` (rendered config, §4); the runner image
  `data.forgejo.org/forgejo/runner:13.2.0`; labels
  `ubuntu-latest/ubuntu-24.04/ubuntu-22.04/docker/node22` → all map to
  `docker://ghcr.io/catthehacker/ubuntu:act-24.04` (the act image set, ruling 3).

**Error attribution (the producer, grounded in source):**

1. The error text is **not** in the repo (grep: zero hits) and **not** from the plain
   docker CLI (that says "Cannot connect to the Docker daemon at …"). It is the **moby
   Go client's** `errConnectionFailed`, `client/request.go:177`:
   `failed to connect to the docker API at %v; check if the path is correct and if the
   daemon is running: %w` — reached via **`docker buildx`** (buildx vendors the moby
   client; the `ERROR: ` prefix is the docker CLI's `Cli.Fatal` print, exit 1 — the
   exact match for the report incl. `exitcode '1'`).
2. `⚙️ [runner]: exitcode '1': failure` is the **runner daemon's** log
   (`act/container/docker/run.go:782`, verified present in the v13.2.0 source): the
   runner's container-exec layer reporting the step's non-zero exit. It comes from the
   runner pod's log, not the job log.
3. Why the **preceding** "log in to the forge registry" step succeeded without a
   socket: docker CLI's `loginWithRegistry` (verified in `v27.5.1` — the noble
   docker.io line — and on master) does `apiClient.RegistryLogin` (daemon) and on
   `client.IsErrConnectionFailed` **falls back to `loginClientSide`** ("daemon isn't
   responding; attempt to login client side") — a direct registry auth handshake, no
   daemon needed. The observed green login step is the live proof the image's CLI
   carries this fallback.
4. The runner does **not** emit this error for a down dind: its startup check says
   `cannot ping the docker daemon. is it running?` (`internal/pkg/envcheck/docker.go`)
   and would crash-loop the pod, and the job containers demonstrably start (checkout
   runs) — so runner→dind is healthy; the dial that fails is inside the job container.

**Conclusion:** the error is produced by `docker build` (buildx → moby client) inside
the job container, which has no `/var/run/docker.sock` at all (`no such file or
directory` — the file is absent, not refused). The workflow's release-arm diag comment
("the plain docker build below talks to the in-pod dind daemon (chart socket
contract)") states the intended contract; the contract is only half-wired — see §4/§6.

## 3. The old builder contrast (task 3)

`.github/workflows/docker-build.yaml` on `origin/main` (the
`workflow_dispatch`-only fallback, `on:` block with push/PR triggers kept commented):
`runs-on: ubuntu-latest` — **GitHub-hosted** runners — with `docker/setup-buildx-action@v4`
+ `docker/build-push-action@v7` + `docker/login-action@v4` (credential
`secrets.GITHUB_TOKEN`, job `permissions: packages: write`) and GHA layer cache. It
worked there because a GitHub-hosted `ubuntu-latest` VM ships a full docker daemon
with `/var/run/docker.sock` always present, and the workflow steps execute **on the
runner host itself** — no job container, no socket-sharing question; `docker build`
talked to the host daemon directly. The forge runner inverts that: it is a self-hosted
act-based daemon that executes every job **inside an ephemeral container** (spawned via
the in-pod DinD daemon), and a job gets docker access only if the runner's config
opts into socket sharing (`container.docker_host` ≠ `-`). The chart never opted in, so
the same `docker build` that worked on a hosted VM has no socket in the forge job
container. The host has a working docker daemon (the dind sidecar — both containers
Ready, jobs spawn fine); the missing piece is the *share* of that socket into the job
container, not the daemon itself.

## 4. The runner environment, grounded (task 4)

**Two Forgejo instances, two runner pods — all in-cluster, none host-process:**

| surface | cluster / ns | public URL | runner release (pod) | dials |
|---|---|---|---|---|
| `infra-forgejo` pod | infra / `default` | `git.spencerslab.com` (UI alias `forgejo.spencerslab.com`, `.agents/notes/2026-10-23-forgejo-git-ssh.md`) | **`gpu-forgejo-runner-gpu-0`** (gpu cluster / `default`) | `https://git.spencerslab.com` |
| `dev-forgejo` pod | dev / `default` | `git.scifi.farm` | `dev-forgejo-runner-dev-0` (dev cluster / `default`) | `http://dev-forgejo-http:3000` (in-cluster) |

- The repo's `origin` remote = `https://git.spencerslab.com/CuratedForest/SpencersLab.git`
  (infra instance); `dev` remote = `ssh://git@git.scifi.farm:22222/CuratedForest/SpencersLab.git`.
- The infra runner lives on the **gpu** cluster (not infra): `services/gpu/prod/values.yaml`
  — `forgejo-runner-gpu` app entry, comment "dials out over HTTPS to the infra instance's
  public route (gpu has no in-cluster Forgejo)", top-level slice
  `runner.url: https://git.spencerslab.com`. Added 2026-11-05 by `e824542f8`
  ("feat(services): C05 add the gpu Forgejo runner instance, dialing out to infra
  (cf-104, review APPROVED)"). The dev-values comment "the infra-instance runner was
  un-wired … relocation is pending" (2026-10-25) is **stale** — cf-104 did the
  relocation as a gpu release; the chart suite's t5 leg pins that staleness red (§8).
- Fleet sweep (10 clusters): **no other runner pods** (ai-gpu, grow, home, media,
  monitoring, proxy-local clean; the `home-actualbudget` hit is a false positive;
  `readonly-proxy-backup-kubernetes` has no `pods_list` tool — recorded, the proxy-backup
  cluster is not a runner host candidate per any repo record).

**Live pod spec — both releases render the same docker-backend shape** (probed via
`readonly-*` MCP `resources_get`; the gpu one is the failing runner's):

`gpu-forgejo-runner-gpu-0` (node `gpu`, created 2026-11-05, **Running 2/2**, runner
container restarts 9 / dind restarts 10 — reloader-driven, healthy now):
- initContainer (sidecar, `restartPolicy: Always`): **dind** `docker:29.9.2-dind`,
  `privileged: true`, mounts `/var/lib/docker` ← PVC `docker-data-gpu-forgejo-runner-gpu-0`,
  `/var/run` ← emptyDir `socket`; startup+liveness probes `test -S /var/run/docker.sock`.
- container: **runner** `data.forgejo.org/forgejo/runner:13.2.0`, env
  `DOCKER_HOST=unix:///var/run/docker.sock`, `CREDENTIALS_DIRECTORY=/run/secrets/forgejo-runner`;
  mounts `/var/run` ← **the same emptyDir `socket`**, `/data/config/config.yaml` ←
  Secret `gpu-forgejo-runner-gpu` (subPath), `/data` PVC.
- pod securityContext: `fsGroup: 1000`, `supplementalGroups: [2375]` (the cf-97
  socket-group fix), runner container `runAsUser/runAsGroup 1000`, `capabilities.drop: [ALL]`.

`dev-forgejo-runner-dev-0` (node `dev`, created 2026-11-09, Running 2/2): byte-identical
shape (same images, env, volumes, securityContext) — probed the same way.

**Live log — the gpu runner is processing the failing PR runs** (pods_log tail,
2026-11-21): `runner: gpu-runner, with version: v13.2.0, with labels: [ubuntu-latest
ubuntu-24.04 ubuntu-22.04 docker node22], ephemeral: false, declared successfully`,
then task lines for `job detect-changes` ×6 and **`job pr coder-workspace
(coder-workspace)` / `job pr forgejo-host-runner (forgejo-host-runner)`** at 14:48–14:49
(today's Renovate batch) — the exact job names of the failing PR arm
(`name: pr ${{ matrix.container }}`).

**The rendered runner config (the defective artifact):** generated by
`charts/forgejo-runner/templates/secret-runner.yaml` (ExternalSecret, v2 template,
`mergePolicy: Merge`). Docker-backend branch renders:

```yaml
runner: {capacity: 1, timeout: 30m, shutdown_timeout: 5m}
cache: {enabled: true}
container:
  privileged: false          # ← the WHOLE container: block. NO docker_host key.
server:
  connections:
    default:
      url: <per-release slice>   # https://git.spencerslab.com (gpu) / http://dev-forgejo-http:3000 (dev)
      uuid: "{{ .uuid }}"
      token_url: file:$CREDENTIALS_DIRECTORY/token
      labels: [the 5-label act set]
```

**There is no `docker_host` anywhere in the chart or the rendered config** (repo grep:
zero hits outside plan/research docs). The runner v13.2.0 default for a missing key is
`Container{DockerHost: "-", ...}` (`internal/pkg/config/config.go:533` at tag v13.2.0),
and the job-container bind is added **only** `if containerDaemonSocket != "-"`
(`act/runner/run_context.go:164-166` at v13.2.0, and `1844-1846` for the twin path).
Forgejo's own docs (forgejo.org `admin/actions/docker-access`, fetched today) state the
default `-` = "Forgejo Runner will **not** share the socket with the containers. This
prevents access to docker … the default so that no unexpected security risks are
present"; `docker_host: "unix://…"` (or `automount`) = the runner **mounts the socket
into job containers at `/var/run/docker.sock`**. The repo's own 2026-10 research
documented this exact default and the rejected alternatives (`2026-10-feat-forgejo-infra-and-runner/RESEARCH.md`
L155/195/238 — "`docker_host: "-"` (default = no docker socket into job containers)";
`RESEARCH-dind-supplement.md` L76 — "v4.0/v5.0: `docker_host` default changed to NOT
mount the socket (security)", and L172 the TLS-TCP-into-jobs design cf-97 later
rejected: b1 plaintext `tcp://0.0.0.0:2375` is cluster-reachable, b2 TLS needs
unverified v13 env support).

**Boundary facts (recorded, not fixable from here):**
- The live Secret bytes (`gpu-forgejo-runner-gpu` / `dev-forgejo-runner-dev`) are
  **unreadable** through the readonly MCP SA (`secrets … is forbidden`); the repo
  template is the authority for the rendered bytes (static except uuid/token/url).
  Owner command to see the live artifact: §6.
- The **job containers are ephemeral dind containers, not k8s pods** — they are gone
  after each job; no MCP surface can inspect their mounts. The evidence for the
  missing mount is the config default + the error's `no such file or directory`
  (the file is absent inside the job, while the runner-side socket probe passes).
- `forgejo.server_url` for the infra runs = `https://git.spencerslab.com/` → the PR
  push target was `git.spencerslab.com/curatedforest/<container>:pr-<branch>-<sha>`
  (the instance registry; PR tags never reach ghcr by design).

## 5. Live build history (task 5)

**ghcr (read-only probe 2026-11-21, anonymous pull token + `/v2/<img>/tags/list`, all
13 `containers/` image names):**

| image | `pr-*` tags | `yy.mm.N` calendar tags | tags (live) |
|---|---|---|---|
| wekan-mcp | 0 | 0 | `0.0.1 0.0.2 latest main v24 v25 v26 v27 v28 v29 v55 v60 v68 v81 v87 v90 v101 v102 v148 v162 v177` |
| renovate-mcp | 0 | 0 | `v24 main v31 v84` |
| strata | 0 | 0 | `v93 main v95 v96 v97 v98 v99 v100 v103 v104 v111 v126 v196 v202` |
| coder-workspace | 0 | 0 | `v37 main v38 v39 v40 v41 v42 v68` |
| gpt-researcher | 0 | 0 | `v32 main v33` |
| gpt-researcher-frontend | 0 | 0 | `v34 main v35 v74` |
| music-assistant | 0 | 0 | `v80 main v154 v239` |
| okd-enketo | 0 | 0 | `v30 main` |
| snapcast | 0 | 0 | `latest` |
| traefik-mqtt-allowlist | 0 | 0 | `0.0.1 … 0.0.12 v87 latest main` |
| vllm-radiance-mxfp4 | 0 | 0 | `v181 main v188` |
| brother-ptouch-automation | 0 | 0 | `0.0.2 0.0.4 latest v87 main` |
| forgejo-host-runner | 0 | 0 | `v166 main` |

**Diff vs the run -3 probe (2026-11-16):** wekan-mcp and renovate-mcp tag lists are
**byte-identical** (max `v177` / `v84`); **no image gained any tag of any kind since
2026-11-16**. All live tags are the legacy GitHub-builder `v<run>`/`:main`/`:latest`
lineage. **Fact: no forge build has ever published — not one calendar tag exists on
ghcr** (the release arm pushes ghcr first, so even a half-failed release would leave
one). (`pr-*` tags would never appear on ghcr — the PR arm is forge-registry-only —
so their ghcr absence is expected, not evidence; the PR arm's evidence is the run list
below.)

**Instance registries (read-only probes 2026-11-21):** both hosts answer:
`https://git.scifi.farm/v2/` → **401**, `https://git.scifi.farm/v2/curatedforest/wekan-mcp/tags/list`
→ **401 UNAUTHORIZED**; `https://git.spencerslab.com/v2/` → **401**, and
`/v2/curatedforest/{forgejo-host-runner,wekan-mcp}/tags/list` → **401**. Both registries
are **live but auth-gated for anonymous reads** — the `pr-*`/calendar state of
`curatedforest/*` is **unreadable from here** (needs `FORGE_PUSH_TOKEN`; owner command
in §6). Not hung on.

**Git/instance run evidence — every containers-build run on the infra instance failed**
(anonymous Actions API, `git.spencerslab.com`; the API exposes runs but no job/step logs
without auth):

- 22 total `containers-build.yaml` runs, **0 successes**:
  - **20 `pull_request` runs — all `failure`** (Renovate PRs that touch `containers/**`,
    e.g. run 110 = PR #102 "Update dependency gohugoio/hugo to v0.170.1", whose only
    file is `containers/forgejo-host-runner/Dockerfile`; the PRs also update
    `data.forgejo.org/forgejo/runner`, `debian:13-slim`, `golang`, node, strata,
    music-assistant, enketo, vllm-radiance, llama-swap pins).
  - **2 `push` runs — all `failure`**: run 59 (the 2026-11-16 23:17 pre-rewrite landing
    push, before=`69ccbe0bb` after=`1fc86d598b`, a 105-file range including 6
    `containers/**` files — the release arm ran on the prod role and died in the
    `docker info` diag step, which has no `|| true`) and run 95 (post-rewrite push of
    `6b7506dd6`, same shape).
- **Timeline:** first containers-build run = 59 (night of 2026-11-16/17, pre-rewrite
  main). Renovate's first infra PR batch opened **2026-11-19 15:25:30Z** (PR #1, run 70
  — ~22 min before the rewrite landing's 15:47 committer stamp, i.e. against the
  pre-rewrite main, which already carried the workflow), failing the PR arm; later
  batches on 2026-11-20/21 (PR #98 → run 104, PR #102 → run 110, and the 14:48–14:49
  batch of today visible live in the gpu runner pod log).
- **Dev instance: zero `containers-build` PR runs** in any of its 3 public repos
  (SpencersLab, SpencersLab-Dev, Proxy-Backup — 49+0+17 runs, all `push` events; the
  dev containers-build push runs are `cancelled`/skipped-role states). The dev runner
  carries the identical latent defect (same chart, same rendered config) — it would
  bite the first PR touching `containers/**` opened on `git.scifi.farm`.
- **`release.yaml` (cf-55) push runs on infra are also failing** (runs 59-adjacent,
  94/97/101/106) — **not** docker-related: that workflow uses `cr` (chart-releaser) +
  git push, no docker at all. Separate failure, out of this ticket's scope (cf-55
  territory); recorded so the plan doesn't conflate the red sets.
- The infra instance's `ROLE` variable is **not anonymously readable**, but the PR arm
  (dev-membership guard) and the main-sync `push-gh`/`push-dev` jobs (prod-membership
  guards) **both ran** today per the gpu runner log ⇒ the live ROLE contains both
  `dev` and `prod` — i.e. the documented post-merge owner flip to `dev,prod` has landed
  (AGENTS.md sequencing bullet). Inference from live logs, not from the variable.

## 6. Diagnosis + owner confirmation commands (task 6)

**Ranked hypotheses (a–d from the launch), grounded:**

- **(b) — CONFIRMED (re-phrased): the runner runs in a pod; the *job* container is
  created without the socket.** The runner pod itself has the socket (emptyDir
  `socket` shared with the dind sidecar; `DOCKER_HOST` set; cf-97's gid-2375 fix
  landed and the daemon pings dind at startup — it is declared and dispatching jobs).
  The defect is one step downstream: with no `container.docker_host` in the rendered
  config, the runner default `-` applies and `GetBindsAndMounts` skips the
  `/var/run/docker.sock` bind for the job container (v13.2.0 source, §4). Every
  docker-needing command in the job then sees `no such file or directory`. This
  explains **all** observations: green checkout, green login (CLI client-side
  fallback), the exact buildx/moby error, exit 1, the runner's `exitcode '1':
  failure` line, zero published tags, both arms failing (release arm dies one step
  earlier at `docker info`).
- **(a) "runner host has no docker / daemon down" — REFUTED** as framed: the only
  docker daemon in this setup is the in-pod dind sidecar, and it is up (both pod
  containers Ready, `test -S` probes passing, job containers spawning, runner log
  healthy). The k3s nodes (gpu, dev) run containerd, not docker — irrelevant; the
  workflow never needed a node daemon by design. The task's host commands
  (`systemctl status docker`, `docker version`, `ls -la /var/run/docker.sock` **on the
  runner host**) are **N/A** — there is no host daemon to check; the equivalent
  checks are the pod-scoped ones below.
- **(c) "socket at a different path / DOCKER_HOST" — REFUTED:** the error names the
  default path `unix:///var/run/docker.sock`, i.e. the job container has **no**
  `DOCKER_HOST` at all (the runner's env does not propagate into job containers; the
  chart sets no `runner.envs`). The dind socket lives at exactly the default path in
  the shared emptyDir — it just is not mounted into the job.
- **(d) "socket permissions for the runner user" — REFUTED at the job level** (no file
  ⇒ no permission question) and already fixed at the runner level by cf-97
  (`supplementalGroups: [2375]` — the dind image's fixed docker gid, upstream
  `addgroup -g 2375 -S docker`; the runner↔dind EACCES was that ticket's root cause).

**Owner confirmation commands** (read-only; the runner is a pod — run on a cluster
kubeconfig, not on any "runner host"; nothing needs pod exec):

```bash
# 1. The live rendered config — expect: container: block with ONLY privileged: false,
#    NO docker_host line (confirms the rendered artifact matches the repo template):
kubectl -n default get secret gpu-forgejo-runner-gpu -o jsonpath='{.data.config\.yaml}' | base64 -d | sed -n '/^container:/,/^server:/p'
kubectl -n default get secret dev-forgejo-runner-dev -o jsonpath='{.data.config\.yaml}' | base64 -d | sed -n '/^container:/,/^server:/p'

# 2. Runner pod state (scout already did this via MCP; re-verify pre-fix baseline):
kubectl -n default get pod gpu-forgejo-runner-gpu-0 -o yaml | sed -n '/containers:/,$p'
kubectl -n default logs gpu-forgejo-runner-gpu-0 -c runner --tail=100        # "declared successfully" + task lines
kubectl -n default logs gpu-forgejo-runner-gpu-0 -c dind --tail=20          # "API listen on /var/run/docker.sock"

# 3. Post-fix verification — re-run one failed PR run from the Actions UI (or open a
#    scratch PR touching containers/**): the "build and push the pr tag" step must get
#    past docker build (dind pulls/builds), and the tag must land on the instance
#    registry (needs the PAT — the only secret-side read):
curl -u "forge:$FORGE_PUSH_TOKEN" "https://git.spencerslab.com/v2/curatedforest/forgejo-host-runner/tags/list"
```

## 7. Fix space, sketched (task 7 — grounded, not decided)

**Family (ii) REPO-SIDE is the fix; family (i) OWNER-SIDE is N/A for this defect.**
The infrastructure the workflow needs (a build-capable daemon the job can reach)
already exists in-pod; no host install, no socket mount on a node, no runner
re-provisioning is required. The "host with NO runtime at all" tooling analysis from
the launch does not apply here: kaniko's executor still needs a container runtime to
start (the pod has one — dind — but kaniko would add an image+step for what a
one-line config gives), skopeo/oras can copy but not build, buildx remote drivers
need an external buildkit, and a host docker install would fight the deliberately
pod-local dind design (cf-97 ruled the pod-local daemon is the trust boundary).

**The one-line fix (docker-backend branch of `charts/forgejo-runner/templates/secret-runner.yaml`):**

```yaml
container:
  privileged: false
  docker_host: unix:///var/run/docker.sock
```

Mechanism, verified against the v13.2.0 source + official docs: the daemon's
`configCheck` accepts an explicit `unix://` value (ping OK — dind is up; the scheme
check keeps unix, only non-unix schemes are forced to `-`), and
`GetBindsAndMounts` then mounts `<in-pod socket>:/var/run/docker.sock` into every job
container (the unix scheme resolves to the path after `unix://` = the shared emptyDir
socket). The job's docker CLI (no `DOCKER_HOST` in the job) uses its default
`unix:///var/run/docker.sock` → reaches dind → `docker build`/`push` work, exactly the
workflow's stated "in-pod dind daemon (chart socket contract)". The host-backend
branch of the template renders a `host:` block with no `container:` key — **the line
goes in the `{{- else }}` (docker) branch only**; host releases (card #88 territory,
external to this repo's releases) are untouched. Deployment path: ArgoCD sync →
ExternalSecret re-renders the config → the stakater reloader annotation restarts each
runner pod (one restart per release; both releases share the template, so one commit
fixes both). Security posture: jobs gain the in-pod dind daemon's control — the
designed capability (the runner already holds gid 2375 over the same daemon; capacity
1 means at most one job's dind world at a time; the docs' automount caveats —
cross-job visibility, host-volume escape via `docker run -v` — are bounded to the
pod-local daemon, which has no host mount beyond its own PVCs).

**Alternatives considered (for the plan's rejected column):** `docker_host: automount`
(worked identically here — discovery would land on the same `DOCKER_HOST` socket — but
less precise than the explicit path and couples to the discovery-order list);
TCP dind 2375/2376 (cf-97 rejected b1 plaintext — `0.0.0.0` cluster-routable
unauthenticated port — and b2 TLS — v13 TLS-env support unverified); adding
`runner.envs.DOCKER_HOST` alone (only sets the *client* env in the job; the **mount**
is what's missing — the runner would still not share the socket under default `-`).

**Test teeth (the cf-6 C01 "teeth move with the docs in one change" rule):**
- `tests/services/dev-forgejo-runner.sh` (the chart suite, 1640 lines): the fix must
  add a leg pinning `container.docker_host: unix:///var/run/docker.sock` in the
  rendered config (red-first). Existing legs parse the rendered config for specific
  keys (uuid/url/token_url/labels/timeouts/DOCKER_HOST env/mounts) and do **not** pin
  the `container:` block's key set — the one-line addition breaks nothing today, but
  without a new leg a future revert would stay green.
- `tests/services/forgejo-containers-build.sh` (the 41-leg workflow suite): a
  chart-only fix touches **no** workflow text → the suite is unaffected by the fix
  itself. But it is **already red on origin/main** with 3 legs (§8: t6/t12 checkout
  pin vs the `b80fae102` v7 bump; x4 scope fence vs cf-55's `.github/workflows/release.yaml`
  deletion) — the plan should move those teeth (re-pin `actions/checkout@v7`, drop
  `release.yaml` from the fence or re-point it at the forge-side `release.yaml`) in
  the same change, or record them as main's pre-existing red set.
- Contract invariants that must survive any fix: calendar `yy.mm.N` + `:latest` +
  `:main` to **both** registries on main/dispatch (prod role); `pr-<branch>-<sha>`
  forge-only on PRs (dev role); the `contains()` ROLE guards with the `vars.ROLE ==
  null ||` widening clause; whole-range detection (`fetch-depth: 0`, hand-rolled
  merge-base PR arm); the dual-registry union-max N walk with both walks before the
  first push; ghcr-first push order. None of these are touched by the chart fix.

## 8. Test-suite state on `origin/main` (verified by running, temp worktree, removed after)

| suite | result on `origin/main` (b80fae102) | red legs / cause |
|---|---|---|
| `tests/services/forgejo-containers-build.sh` (41 legs) | **RED — 38 ok / 3 failed** | t6: `uses set is ['actions/checkout@v7'], expected exactly actions/checkout@v6` (the `b80fae102` Renovate bump moved the pin); t12: `0 checkout steps in detect-changes, expected exactly one` (same v6 pin, step counter); x4: `.github/workflows/release.yaml is gone` (the six-file cutover scope fence names `release.yaml`, which cf-55 deleted when chart releases moved to `.forgejo/workflows/release.yaml`) |
| `tests/services/forgejo-main-sync.sh` | PASS 8/8 | — |
| `tests/services/forgejo-renovate.sh` | PASS 8/8 (t9 live probe default-off skipped) | — |
| `tests/renovate/forgejo-move-config.sh` | PASS 6/6 (m5 pins the 10 packageRules incl. the 3rd `managerFilePatterns` entry) | — |
| `tests/services/dev-forgejo-runner.sh` (chart suite) | **RED — 34 ok / 1 failed** | t5: "the trio-exemption comment still claims BOTH runners dial out — dev deploys forgejo-runner-dev only since 2026-10-25" (the dev-values relocation comment is stale after cf-104's 2026-11-05 gpu relocation) |

All reds are **pre-existing main drift** (teeth vs later landed changes), none caused
by the docker failure. They matter to this ticket only in that the fix change lands on
a main that already carries them, and in that the t5 stale comment is in the same
file family (the runner wiring docs) the fix's doc updates will touch.

## 9. Could-not-verify / open notes

- **Live Secret bytes** (`gpu-forgejo-runner-gpu`/`dev-forgejo-runner-dev`): readonly
  MCP SA is `forbidden` on secrets; the repo template is treated as the rendered
  authority. §6 command 1 is the owner-side byte check.
- **Job-container mounts**: ephemeral dind containers, not inspectable via any MCP
  surface; the missing-mount conclusion rests on the config default + the
  `no such file or directory` dial + the healthy runner-side socket (probe + spawn
  evidence).
- **Instance registry tag state** (`curatedforest/*` on both hosts): 401 anonymous;
  needs `FORGE_PUSH_TOKEN` (§6 command 3).
- **Job/step logs** of the failed runs: the instance's v1 API (Forgejo
  15.0.10+gitea-1.22.0) exposes runs but no anonymous job/log endpoints (no
  `/actions/runs/{id}/jobs` in the v1 swagger); the user's step/error quotes + the
  runner pod log + the source-level error attribution cover the same ground.
- **`readonly-proxy-backup-kubernetes`** has no `pods_list` tool in this session's
  catalog; that cluster was not swept (no repo record puts a runner there).
- **The infra `ROLE` variable** itself: not anonymously readable; the `dev,prod`
  content is inferred from live guard outcomes (§5).
- **The user-quoted step name** "build and push the pr tags" vs the file's singular
  "build and push the pr tag" — cosmetic; the step is unambiguous.
- The `release.yaml` (cf-55) push-run failures on infra are a separate, non-docker
  red set — cf-55's follow-up territory, not this ticket's.
