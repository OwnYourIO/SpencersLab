# EXPLORE — cf-6-feat-builder-bootstrap-3 (builder lane dispatched post-merge: the BUILD failed)

Scout: `agent-explore`, 2026-11-22T23:23Z. Read-only grounding for the owner report
"I deployed the builder and ran it, but it failed on the build: [error text truncated]".
Probes used: git reads + `git fetch origin`; anonymous Forgejo Actions API + Actions UI HTML;
anonymous registry/token probes; `readonly-gpu-kubernetes` / `readonly-infra-kubernetes`
(pods_log, resources_get/list, events_list); repo file reads. No admin tier, no pod exec,
no secret reads (all Secrets/vars API routes answer 401 — see §6.6).

## 0. Verdict up front

1. **World = "run -2 is MERGED".** `origin/main` tip is `dcc54c091` (22:43:17 +0000) — the
   landed run-2 trio. The **B-era forge-only lane is live on main** (blob `06dd168f7`), the
   A-era file (`42f9cadd7`, ghcr login + `GHCR_PUSH_PAT`) is gone from main.
2. **The lane WAS dispatched after the merge and the BUILD step is what failed.** Actions run
   api-id **231 / UI #215**, `workflow_dispatch` on `refs/heads/main` @ `dcc54c091`,
   22:52:05Z → 22:54:44Z (159 s), `status: failure`. Step table (§2.1): diag ✓, forge login +
   calendar walk ✓ (0 s), **`build and push` ✗ at 2 m 32 s**.
3. **Proven root cause (verbatim from the live dind daemon log):** the image build died in the
   **helm-bake `RUN` step** of `containers/forgejo-runner/Dockerfile` with **curl exit 35
   (SSL connect error)** fetching `https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz`.
   It is **not** the PVC, **not** the 30 m ceiling, **not** a login/credential failure, **not**
   the old-lane phantom-secret class, and **not** a base-image availability problem (§4).
4. **Bigger collateral, proven independently of the owner's report:** the **entire Forgejo fleet on
   the infra instance has been unable to START any job since 22:43-ish back to 01:06Z** — because
   the **live runner label map points the baked labels at `ghcr.io/ownyourio/forgejo-runner:26.11.1`,
   which is not anonymously pullable** (ghcr token endpoint → **403 DENIED**, proven by the dind
   log's own failed pulls at 21:42 / 22:18 / 22:43). Only `renovate` still *completes*, because it is
   the one job with a public `container.image` override; `builder-bootstrap` also gets its job
   container started (its `ubuntu-22.04` label maps to a public act image, by paradox-guard
   design) — every other workflow dies at pull. Consequence: **the run-2 credential fix
   (`PUSH_TOKEN_GH` in containers-build) has never executed** — its "first real test" is still
   pending, blocked by the label/registry outage, not by the fix. (§2.3, §2.4)
5. Nothing was minted anywhere: no calendar tag exists on either instance registry as far as
   anonymous reads can see, and ghcr `ownyourio/forgejo-runner` is private-or-absent (§3).

## 1. Deploy-state verification (which world are we in)

| Question | Answer | Evidence (read) |
|---|---|---|
| `git fetch origin` | ok; origin/main moved | tip `dcc54c091` 2026-11-22 22:43:17 +0000 |
| main since base `2b11120a8` | `b63b85798` (cf-145 ledger), `e15ce378d`, `54cc84188` (radiance merge) … then **`45578a578` + `3a9f760fe` + `dcc54c091`** | `git log --oneline --graph origin/main ^2b11120a8` |
| Is run -2 merged? | **YES — as a REBASE (new SHAs, identical content)** | branch SHAs `e8c31644d` / `44086389a` / `0c18e21c8` are **not** ancestors of main (`git merge-base --is-ancestor` → NO for all three); the landed trio `45578a578` / `3a9f760fe` / `dcc54c091` carry the same messages, same author dates (20:50:36 / 21:19:44 / 21:37:13) and a shared committer date 22:43:17 = one rebase operation |
| Lane-file blob identity | main = `06dd168f758a8db3bc91a5262745229162d6afd8` **==** the blob at `e8c31644d` **==** the blob on the local branch; base `2b11120a8` had `42f9cadd760ead8170015e8bfcab2fc89765e959` | `git rev-parse <ref>:.forgejo/workflows/builder-bootstrap.yaml` |
| Live lane shape | **B-era forge-only**: guard `contains(vars.ROLE,'prod')`, `runs-on: ubuntu-22.04`, 3 run-steps (diag / forge login + walk / build and push), single credential `secrets.FORGE_PUSH_TOKEN` (only secret in the file), **no `timeout-minutes`** (the ceiling is the runner's), no `ghcr.io` literal | `git show origin/main:.forgejo/workflows/builder-bootstrap.yaml` (186 lines, quoted at §2.1) |
| Did the local branch get pushed instead? | No branch ref for it on origin: remote-tracking refs are only `origin/main` + `origin/fix-strata-q4-oom-envelope` + renovate branches. Local `cf-6-feat-builder-bootstrap-1` = `e48281dc8` (a merge of `dcc54c091` into the branch at 22:55:56), and **`git diff origin/main HEAD` is EMPTY** — the worktree already carries the full landed state | `git for-each-ref refs/remotes/origin`, `git diff --stat origin/main HEAD` |
| GitHub side | `upstream/main` == `dcc54c091` locally; **anonymous GitHub API confirms `repos/OwnYourIO/SpencersLab` `branches/main` = `dcc54c091d6c…`** (repo public, commit readable). Mechanism undetermined: main-sync has not run since 01:06Z, and the local reflog says `update by push` | `curl https://api.github.com/repos/OwnYourIO/SpencersLab/branches/main` |

**Consequence for planning:** there is nothing to "merge" and the highest-value possibility the
brief asked to rule in/out first — *old-lane-still-live ⇒ owner must merge* — is **RULED OUT**.
Any repo-side change for run -3 branches from current `origin/main` (`dcc54c091`), per the STATE
kickoff note.

## 2. The run itself (Actions forensics, anonymous)

### 2.1 builder-bootstrap: three dispatches exist

| api id | UI run | started → stopped (UTC) | dur | commit_sha | status | what it ran |
|---|---|---|---|---|---|---|
| 222 | #206 | 17:10:13 → 17:10:38 | 25 s | `1d6d56dc01` (run-1 record) | success | **general-lane era**: job `detect`, step `resolve the dispatch list` — the silent-empty no-op "success" (the A-era trap the scope ruling killed) |
| 224 | #208 | 18:51:43 → 18:51:50 | 7 s | `2b11120a8f` (pre-run-2 base) | failure | **A-era lane**: job `publish`, steps `Set up job`✓ `checkout`✓ `diag`✓ **`log in to ghcr` ✗ (0 s)**, everything after **skipped** — `docker login ghcr.io -u OwnYourIO --password-stdin` against the phantom `secrets.GHCR_PUSH_PAT`. **No build ever ran in that world.** |
| 231 | **#215** | **22:52:05 → 22:54:44** | **159 s** | **`dcc54c091d` (landed run-2 tip)** | **failure** | **B-era lane — the reported failure.** Step table below. |

Run #215 / job id 713 `publish` steps (from `data-initial-post-response` in the anonymous job
HTML, verbatim statuses):

| step | duration | status |
|---|---|---|
| Set up job | 2 s | success |
| actions/checkout@v7 | 4 s | success |
| diag | 0 s | success |
| log in to the forge registry and derive its calendar N | 0 s | success |
| **build and push** | **2 m 32 s** | **failure** |
| Complete job | 1 s | failure |

Runner-log correlation (`readonly-gpu-kubernetes`, pod `gpu-forgejo-runner-gpu-0`, container
`runner`, family idiom "the death line"):

```
22:52:05Z task 435 repo is CuratedForest/SpencersLab …
22:54:44Z Cleaning up network for job publish, network name WORKFLOW-95291153322c629a8a99fb25799a6922
```

(same pattern: `task 418 / 18:51:43 → 18:51:50 publish` for run 208; `task 415 / 17:10:13 →
17:10:37 detect` for run 206.)

Readings that the step table settles:

* The **job container started** (Set up job ✓ + diag ✓ ⇒ the public `ubuntu-22.04` →
  `ghcr.io/catthehacker/ubuntu:act-22.04` label mapping works and the in-pod dind socket was
  reachable — `docker info` in `diag` did not fail the job, and `set -euo pipefail` would have).
  Candidate **"job container failed to start" is REFUTED**.
* The **forge login + calendar walk succeeded**, so `FORGE_PUSH_TOKEN` authenticated and
  `docker login "$forge_registry" -u forge-push` worked (0 s — a live HTTPS round-trip pair).
  **Secret-scope is REFUTED** for this run. The derived `n_forge=` / `list=` codes are **log-only**
  and unreadable anonymously (§4.3).
* The failure is inside `docker build` (or, strictly, inside the `build and push` step; §4 proves
  the build, not the push, died).

### 2.2 Duration vs the 30-minute ceiling — REFUTED

159 s total, build step 2 m 32 s. The ceiling is the runner's own
(`charts/forgejo-runner/templates/secret-runner.yaml:92-93`: `timeout: 30m`,
`shutdown_timeout: 5m`; the lane file carries no `timeout-minutes`). A timeout red would look
like ~30 m, not 2½ m.

### 2.3 Fleet collateral (the surprise)

All runs since 14:47Z, infra instance, `CuratedForest/SpencersLab` (anonymous detail API +
job-level UI):

| api id | wf | event | started | status | job-level detail |
|---|---|---|---|---|---|
| 206 | main-sync | push | 2026-11-22 **00:57:25Z** | **success** | `push-gh` 10 s ✓, `push-dev` 8 s ✓ — **last job that started anywhere** |
| 208 / 210 | main-sync | push | 01:06:21 / 01:09:59 | failure | both jobs **0 s**, no steps (never started) |
| 213 | renovate | schedule | 06:17:27 | **success** | `renovate` **15 m 7 s** ✓ — the ONLY survivor (§2.4) |
| 214/215/216 | containers-build | pull_request | 06:32 | failure / waiting | 0 s |
| 217–230 | containers-build, main-sync, release | push | 14:47 → **22:43:39** | failure | 0 s, jobs `push-gh`/`push-dev`/`changes`/`detect-changes` all 0 s and **no steps** |
| 231 | builder-bootstrap | dispatch | 22:52:05 | failure | real steps (§2.1) |

Job-start failure signature (e.g. UI #214, api 230 = main-sync on the merge commit): jobs listed
`{'push-gh','failure','0s'}, {'push-dev','failure','0s'}` with `steps: []` — the pod-side proof is
in the dind log at exactly those seconds:

```
22:43:39.704Z level=info msg="fetch failed" error="failed to authorize: failed to fetch anonymous
  token: unexpected status from GET request to https://ghcr.io/token?scope=repository%3Aownyourio%2Fforgejo-runner%3Apull&service=ghcr.io: 403 Forbidden" host=ghcr.io method=HEAD url="https://ghcr.io/v2/ownyourio/forgejo-runner/manifests/26.11.1"
22:43:39.724Z level=error msg="Handler for POST /images/create returned error" error-response="error from registry: denied\ndenied" request-url="/v1.56/images/create?fromImage=ghcr.io%2Fownyourio%2Fforgejo-runner&platform=linux%2Famd64&tag=26.11.1" status=500
```

…same pair at 21:42:43/45/47 and 22:18:21/23/25 (the earlier main-sync/release runs).

**Why:** the live runner label map (baked labels `ubuntu-latest` / `ubuntu-24.04` / `docker` /
`node22`) points at `ghcr.io/ownyourio/forgejo-runner:26.11.1`, and a job-container pull is done
**anonymously by the in-pod daemon** — there is no login at job-start (logins happen *inside*
jobs). Grounding of that map:

* `charts/forgejo-runner/values.yaml` at `1a99f7629` (cf-55 C06, 2026-11-21 22:00) introduced
  `ghcr.io/ownyourio/forgejo-runner` refs; `f236be07f` (cf-6 run-1, 2026-11-22 17:07:30) replaced
  them with per-instance refs. `git log -S` names exactly those two commits for the string.
* **What main says TODAY** (post-run-1 + post-run-2): chart `values.yaml:141-145` →
  `git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` ×4 +
  `ubuntu-22.04 → ghcr.io/catthehacker/ubuntu:act-22.04`;
  `services/dev/prod/values.yaml:194-198` → the dev slice's `git.scifi.farm/...` twin set.
* **What is RUNNING**: the pod was created/reloaded at **2026-11-22 00:59:19Z**
  (`metadata.creationTimestamp`, `status.startTime`, and the reloader annotation
  `reloader.stakater.com/last-reloaded-from … "observedAt":1795309158` = 00:59:18Z) — i.e. the
  ghcr-era chart — and has **not reloaded since** (restartCount 0, age 22 h at probe time).
* **ArgoCD saw the drift and did not apply it**: event
  `Application/gpu-forgejo-runner-gpu — "Updated sync status: Synced -> OutOfSync"` at
  **22:22:34Z** (gpu cluster, ns default). No later sync event for that app. The runner app is
  **path-based** (`services/gpu/prod/values.yaml:119-122` → `chart: forgejo-runner`, no
  `version:`/`repository:`, `ServerSideApply: "false"`, `namespace: default`; top-level slice
  L271-273 only pins `runner.url: https://git.spencerslab.com`) — so **no chart release is needed
  to heal it: an ArgoCD sync + pod reload is.** The `Chart.yaml` version is still `1.0.2` (last
  touched 2026-10-25) and `release.yaml` has been red since 22:13Z Nov 21 — the version-bumper is
  itself part of the outage, but for this chart it is not on the critical path.

### 2.4 The credential fix's first real test — STILL PENDING

`3a9f760fe` changed `containers-build.yaml:183` to
`printf '%s' '${{ secrets.PUSH_TOKEN_GH }}' | docker login ghcr.io -u OwnYourIO --password-stdin`
(was `GHCR_PUSH_PAT`). It has **never executed**: no containers-build job has started since
01:06Z. `main-sync` already used `PUSH_TOKEN_GH` (`main-sync.yaml:43`; `release.yaml:272` too),
and its last **successful** run was **00:57:25Z (id 206)** — pre-merge, pre-outage. So the secret
itself is proven-good history, but nothing post-merge has been exercised. Full secret inventory
now on main: `PUSH_TOKEN_GH` (main-sync, release, containers-build), `FORGE_PUSH_TOKEN`
(containers-build ×2, release, builder-bootstrap), `PUSH_TOKEN_DEV` (main-sync),
`RENOVATE_TOKEN`/`RENOVATE_GITHUB_COM_TOKEN` (renovate).

### 2.5 ROLE — inference, not proof (owner settle)

Both role-guarded classes executed on the infra instance: `contains(vars.ROLE,'prod')` jobs were
**scheduled** (builder-bootstrap ran; main-sync/release/containers-build jobs started execution
attempts, which requires the `if:` to have been TRUE — a false guard means `skipped`, and skipped
is exactly what the A-era run 208 showed for later steps), and `renovate`'s
`if: contains(vars.ROLE,'dev')` job **ran 15 m 7 s**. ⇒ **infra `vars.ROLE` contains both `dev`
and `prod`** (the AGENTS sequencing flip has happened). Proof-grade reading is the lane's own
`diag` line `ROLE=[…]` in the job log — auth-gated (§4.3). The vars API is 401 anonymously.

## 3. Registry state — decisive, verbatim

Anonymous probes at 23:16–23:23Z (families: `GET /v2/` challenge → redeem `/v2/token` →
`tags/list` + `manifests/<t>`; never `HEAD /v2/` = 405 trap).

### 3.1 Infra (`git.spencerslab.com`, namespace `curatedforest`, image `forgejo-runner`)

| probe | result |
|---|---|
| `GET https://git.spencerslab.com/v2/` (anon) | **401**, `WWW-Authenticate: Bearer realm="…/v2/token",service="container_registry",scope="*"` |
| `GET /v2/token?scope=repository:curatedforest/forgejo-runner:pull` | **200**, token issued (159 chars) |
| `GET /v2/curatedforest/forgejo-runner/tags/list` (Bearer) | **404 `{"errors":[{"code":"NAME_UNKNOWN","message":""}]}`** |
| `…/manifests/26.11.1` · `26.11.2` · `26.11.3` · `latest` · `main` (Bearer) | **404** each (54-byte NAME_UNKNOWN body) |
| `GET /api/v1/packages/curatedforest?type=container` (anon) | **200 `[]`** (also 200 `[]` with `CuratedForest`) |

**Verdict:** as far as anonymous can see, **the infra instance registry holds NO `curatedforest/
forgejo-runner` package — no calendar tag, no `latest`, no `main`** (the `[]` + NAME_UNKNOWN pair
is exactly the "empty" fingerprint this family used in run 0/-1). Run -2's `OQ-1=B` publish target
therefore has **still never produced a byte**. Caveat that stays honest: a *private* Forgejo
package is invisible to anonymous reads, so "absent" and "private" are not separable without the
PAT — but either answer means the labels pointing there cannot pull anonymously today (see §5).

### 3.2 Dev (`git.scifi.farm`, the OL3 leg)

Identical shape: `/v2/token` 200; `tags/list` **404 NAME_UNKNOWN**; `/api/v1/packages/
curatedforest?type=container` **200 `[]`**. ⇒ **dev side empty** as predicted; the dev slice's
pinned `git.scifi.farm/curatedforest/forgejo-runner:26.11.1` does not exist anonymously-visible —
the dev runner would fail job-start identically if it were reloaded onto that map.

### 3.3 ghcr `ownyourio/forgejo-runner` (must stay ABSENT/unused under B)

| probe | result |
|---|---|
| `GET https://ghcr.io/token?scope=repository:ownyourio/forgejo-runner:pull` | **403 `{"errors":[{"code":"DENIED","message":"requested access to the resource is denied"}]}`** — no token |
| `HEAD …/v2/ownyourio/forgejo-runner/manifests/26.11.1` (no auth) | **401** + bearer realm (the documented challenge, not an answer) |
| `https://github.com/orgs/OwnYourIO/packages/container/package/forgejo-runner` (anon HTML) | **404 Not Found** (9-byte body) |
| **Runtime proof** | the runner's own anonymous pull of `…:26.11.1` → 403-at-token / `denied` (§2.3) |

**Verdict:** **not anonymously consumable** — private-or-absent (anonymous ghcr cannot separate
the two; the family gotcha stands). No new ghcr content was minted by run 215. The chart comment
claiming "26.11.1 … pushed to BOTH registries by hand 2026-11-22" is **not confirmable
anonymously**, and operationally the ghcr copy is a dead end for job scheduling.

### 3.4 The base image the build consumes (candidate root (e) — REFUTED)

`FROM ghcr.io/catthehacker/ubuntu:act-24.04@sha256:7bf3a8afc2bbfe7fdaf4b9d2716cb2f3634fd21e4f38e26aa17a12cfda80d721`
(`containers/forgejo-runner/Dockerfile:25`):

* anonymous token for `catthehacker/ubuntu:pull` → **200**; manifest **by that exact digest** →
  **HTTP 200**, `Docker-Content-Digest: sha256:7bf3a8af…d721` (index, 528 bytes);
  `manifests/act-22.04` (the job label) → **200**.
* (`tags/list` returns a 100-tag first page without the rolling `act-*` names — a pagination
  quirk; the manifest probes above are the authority.)

**Verdict:** base image present and public; digest pin resolves. The build demonstrably got PAST
`FROM` (a `RUN` step executed), so the pull worked or was cache-warm.

## 4. Pinpoint the build failure

### 4.1 What is PROVEN (daemon-side, not inferred)

From `readonly-gpu-kubernetes` `pods_log gpu-forgejo-runner-gpu-0 -c dind` (157 lines available in
the tail; the window covers 21:42 → 22:54):

```
2026-11-22T22:52:05.976Z level=info msg="connecting to shim 1a26504c6d4b…" namespace=moby   ← job container
2026-11-22T22:54:43.238Z level=error msg=/moby.buildkit.v1.Control/Solve error="rpc error: code =
  Unknown desc = process \"/bin/bash --login -e -o pipefail -c curl -fsSL -o
  \"/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz\"
  \"https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz\" && curl -fsSL -o …sha256sum\" …
  && (cd /tmp && sha256sum -c …) && tar -xzf … linux-amd64/helm && install -m 0755 …/helm
  /usr/local/bin/helm && rm -rf … && helm version --short | grep -q \"^${HELM_VERSION}\"\"
  did not complete successfully: exit code: 35"
2026-11-22T22:54:43.824Z … "received task-delete event from containerd" (shim disconnected)
2026-11-22T22:54:44Z  (runner) Cleaning up network for job publish   ← the run's end line
```

*(Abridged: every `…` inside the quote is my elision within the daemon's single log line — the
status, the `Solve` handler name and the `exit code: 35` tail are verbatim; the full line is
reproducible with the §4.3 probes.)*

That quoted command **is** `containers/forgejo-runner/Dockerfile:48-54` (the helm bake, the
coder-workspace D38 recipe shape, `${HELM_VERSION}` expanding to `v3.22.1`). So:

* **Failing step:** `build and push`, specifically the **first `RUN` of the Dockerfile** —
  the helm download from `get.helm.sh`. The `cr` download (`:60-65`, github.com) never got a turn;
  **no `docker push` was reached** (all three target tags would have been pushed only after the
  build, and §3 shows none appeared).
* **Error class:** **curl exit 35 = `CURLE_SSL_CONNECT_ERROR`** — the TLS connection to
  `get.helm.sh` failed to establish. `curl -fsSL` makes a 4xx/5xx exit **22** and a transport
  failure 6/7/28/35, so the code itself discriminates: this is **not** a missing asset. (An
  anonymous range probe from this sandbox returns **HTTP 206** for
  `helm-v3.22.1-linux-amd64.tar.gz` and **200** for the sidecar
  `896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea` — the asset exists; the
  cluster's own path to it is what fails. Sandbox ≠ cluster network: inference, flagged.)
* **History match, verbatim from the repo:** the Dockerfile header records that this bake exists
  because "*the release pipeline's first fire died on a read ECONNRESET downloading helm from
  get.helm.sh inside a job's 'Set up helm' step*" (D33). The same host failed the same way at run
  time before the bake; moving it into the build moved the failure, not the network. `charts/
  forgejo-runner/values.yaml:74-81` documents the known k3s egress class (forgejo/runner#1779,
  "suspected overlay/MTU interaction") with named mitigations **`dind --mtu 1450`** or **per-job
  host networking**, full research in
  `.agents/plans/2026/2026-10-feat-forgejo-infra-and-runner/RESEARCH-dind-supplement.md`.

### 4.2 Candidate roots from run -2's `post_close`, scored

| # | Candidate | Verdict | Evidence |
|---|---|---|---|
| a | **dind PVC space** (`docker-data` 10 Gi, first multi-GB `FROM` pull) | **NOT today's cause.** Zero `no space left` / ENOSPC / disk lines in the daemon log window; the build got past `FROM` into a `RUN`, which is only reachable after the base layers are materialised. **LIVE RISK stays**: PVC is `Bound 10Gi local-path` (age 17 d), node `gpu` `Ready`, no DiskPressure events; usage is invisible to the API (owner-only measure, §4.3) | dind log grep (`no space|ENOSPC|disk` → 0 hits); `resources_list` PVCs; `events_list` |
| b | 30 m timeout mid-build | **REFUTED** (159 s; ceiling is the runner's `timeout: 30m`, `secret-runner.yaml:92`) | §2.1-2.2 |
| c | job container failed to START (login/pull class) | **REFUTED** for run 231 (`Set up job` ✓ 2 s, `diag` ✓ with `docker info`); **TRUE for every baked-label job** since 01:06Z (§2.3) — a different failure, different fix | §2.1, §2.3 |
| d | old-lane ghcr-login death | **TRUE ONLY for run 224** (A-era, `log in to ghcr` ✗ 0 s, build skipped). Main is B-era now, so it cannot recur unless someone reverts the lane file | §2.1, §1 |
| e | base-image pull failure (act-24.04 availability) | **REFUTED** (digest manifest 200 + the build reached `RUN`) | §3.4 |
| f | anything the log actually shows | **PROVEN: helm-bake `RUN`, curl 35 (TLS to `get.helm.sh`)** | §4.1 |
| — | secret scope (`FORGE_PUSH_TOKEN`) | **REFUTED** for this run (login+walk step ✓) | §2.1 |

### 4.3 What the anonymous surface CANNOT show → owner's exact next commands

1. **The job's own step log** (the `curl: (35) …` stderr line names which of the two curls and the
   reason; `diag` also prints `ROLE=[…]`; the login step prints `n_forge=<N> list=<code>`):
   `curl -u "<user>:<token>" "https://git.spencerslab.com/CuratedForest/SpencersLab/actions/runs/215/jobs/0/attempt/1"`
   with a session, or open the UI:
   `https://git.spencerslab.com/CuratedForest/SpencersLab/actions/runs/215` → step
   **"build and push"**. (Anonymous: step *statuses* readable, `logs.stepsLog: []`; every log
   route I tried returns 404/401 — tried
   `/api/v1/…/actions/jobs/713/logs`, `/actions/runs/231/jobs`, `…/attempt/1/log`, `…/run-215/logs`,
   `/actions/summary?run=215`.)
2. **dind disk usage** (no pod exec for agents; owner-run):
   `kubectl -n default exec gpu-forgejo-runner-gpu-0 -c dind -- df -h /var/lib/docker`
   `kubectl -n default exec gpu-forgejo-runner-gpu-0 -c dind -- docker system df -v | head -40`
   The cf-55 prune leg (the "owner-side prune" caveat carried since run-1) — whether it ever ran is
   unknown from here; these two commands settle it.
3. **The real egress test from inside the job network** (proves/refutes the MTU/NAT class without
   touching the lane file):
   `kubectl -n default exec gpu-forgejo-runner-gpu-0 -c dind -- curl -fsSv -o /dev/null https://get.helm.sh/helm-v3.22.1-linux-amd64.tar.gz`
   (dind container has curl; if the *daemon's* namespace path is the problem this succeeds where
   the job's NAT path failed — compare the two.)
4. **ghcr package visibility/ownership** (`gh api /orgs/ownyourio/packages/container/forgejo-runner`
   → 404 absent vs 200 + `.visibility`), and the **instance-registry package state with the PAT**:
   `curl -u "forge:$FORGE_PUSH_TOKEN" https://git.spencerslab.com/v2/curatedforest/forgejo-runner/tags/list`
5. **Actions vars/secrets** (all 401 anonymously — the forbidden-fact stands):
   `GET /api/v1/repos/CuratedForest/SpencersLab/actions/variables` (repo scope; org scope too) and
   `…/actions/secrets` with a token; settles the ROLE inference of §2.5.
6. **Why the runner app sat OutOfSync**: `kubectl -n default get application
   gpu-forgejo-runner-gpu -o jsonpath='{.spec.syncPolicy} {.status.sync.status} {.status.sync.revision}'`
   (the readonly MCP cannot resolve `argoproj.io/v1 Application` — "no matches for kind",
   §6.5 — so this is owner-only from here).

## 5. Fix-space, grounded on the pinned root

The owner's "ran it, failed on the build" is fully explained by **§4.1: the helm bake's TLS
download to `get.helm.sh` fails inside the job's build network (curl 35)**. Fix space, cheapest
first, with what each touches:

**A. Owner-side, no repo change (the retry path).** Re-dispatching the same lane is *retry-safe by
the lane's own law* (`gaps, never clobbers`, OQ-1=B). The base layers are now (probably) in the
`docker-data` store, so a retry starts the build warm and only the download is retried — if the TLS
failure is intermittent (which the D33 precedent suggests: an earlier fire got an ECONNRESET, later
fires downloaded helm fine at job runtime), a plain re-dispatch may just work. Zero code, zero
suites. This is the cheapest experiment and should be ruled first.

**B. Repo-side, same recipe, hardened egress.** Options, in the order least likely to fight the
fences:
1. Add curl resilience in `containers/forgejo-runner/Dockerfile` (`--retry 5 --retry-all-errors
   --retry-delay 2`, optionally `-4`/`-6` to pin family). `tests/containers/forgejo-runner.sh t3`
   pins the *flat* recipe shape — it greps for the `get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz`
   URL, the `.sha256sum` sidecar, `sha256sum -c`, `install -m 0755 … /usr/local/bin/helm` and the
   `helm version … HELM_VERSION` assert. Flags do not break any of those greps; **swapping the host
   (a mirror) reddens t3 by design.**
2. Host networking for the build: `docker build --network=host …` in the lane. `tests/services/
   forgejo-builder-bootstrap.sh b8` matches `^docker build ` and requires the **last token** to be
   `containers/forgejo-runner` and exactly one such line, so a flag between is structurally
   allowed — but it must be *proven* by running the suite (bt-legs probe mutations). Two
   host-literal bans fence this file: **b3** zeroes `git.spencerslab.com`, `git.scifi.farm`,
   `github.com/` and `@github.com` in raw text **including comments**; **b8** zeroes `ghcr.io`
   (plus `ghcr_image`/`ghcr_tags`). A lane-side fix must name no host — hosts belong in the chart.
3. Chart-side, the documented mitigation for this exact class: dind `--mtu 1450` dockerd flag (or
   per-job host net) — `charts/forgejo-runner/values.yaml:74-81` names both; a chart change touches
   `tests/services/gpu-forgejo-runner.sh` (g2/g3 label-map + "no gpu labels override" laws) and the
   dind container spec; **and it does not take effect until the OutOfSync app is synced and the pod
   reloads**, which is the same owner leg as C.

**C. Owner-side leg the pipeline cannot skip (fleet heal, independent of the build fix).** Nothing
the lane mints matters while job-starts are broken:
1. Flip the infra instance's **package visibility** for `curatedforest/forgejo-runner` to public
   (or accept that labels must point at a truly public image), then
2. **Sync `Application/gpu-forgejo-runner-gpu`** (OutOfSync since 22:22:34Z) so the live runner
   config adopts the per-instance-registry label map of main (`values.yaml:141-145`), pod reloads,
   and job pulls target `git.spencerslab.com/curatedforest/forgejo-runner:26.11.N`; and
3. mirror the dev leg (`git.scifi.farm` empty; the dev slice exists at
   `services/dev/prod/values.yaml:194-198`).
   Ordering trap to put in front of the owner: **the instance-registry tag must exist AND be
   anonymously pullable before the sync helps** — today the infra registry reads as empty (§3.1)
   and an anonymous pull of a *private* Forgejo package is exactly the failure that killed the
   fleet on ghcr. That makes **UA-10 (anonymous container pull on 15.0.10) the live blocker** for
   the whole OQ-1=B design, no longer a deferred probe card: the deferred item "did main-sync's
   ghcr leg survive since the merge" is subsumed — nothing survives while job-start is dead.

**D. Ruled out as fix targets:** merging run -2 (already merged, §1), PVC growth/prune as today's
cause (§4.2 a — measure first, don't grow blind), timeout raise (§2.2), credential/secret scope
(§2.1), reverting to a ghcr arm (`gpu-forgejo-runner.sh` has a "law gate" leg that reddens "a
return to `ghcr.io/ownyourio`", and builder-bootstrap b8 bans `ghcr.io` outright — so an
old-lane-style fix is fenced red by design).

## 6. Probe-shape gotchas for downstream agents (new or re-confirmed)

1. **The "anonymous Actions API is sparse" belief is only half true and it misled this probe once
   already.** `/actions/runs` (list) returns `id/title/status` only — and its `title` is the
   **workflow path for dispatch runs** but the **commit message for push runs**, which makes
   workflow attribution from the list alone unreliable. **`/actions/runs/{api-id}` (detail) is
   rich**: `workflow_id`, `trigger_event`, `trigger_user`, `prettyref`, `commit_sha`, `created`,
   `started`, `stopped`, `duration` (ns), `index_in_repo`, `html_url`, `event_payload`, and it
   correctly reports `failure` where the list-family gotcha remembered `success`. Use detail-per-id.
2. **`index_in_repo` (UI run number) ≠ api id**, and the offset is not constant across history
   (observed: api 231 ↔ UI 215, but api 213 ↔ UI 197). Take it from the detail payload.
3. **The job page is anonymous-JSON-bearing**: `…/actions/runs/<ui>/jobs/0/attempt/1` (follow the
   307 from `/actions/runs/<ui>`) embeds `data-initial-post-response` with per-**step**
   `summary/duration/status` and job-level durations — that is what located this failure without
   auth. Step *logs* stay auth-gated (5 candidate log routes probed, all 404/401).
4. **A 0 s job with `steps: []` = the job never started (image-pull class)**; a 0-7 s failure with
   steps present = a real step died. This distinguishes the fleet outage from the build failure.
5. **`readonly-*-kubernetes` cannot resolve `argoproj.io/v1 Application`** ("no matches for kind")
   even though ArgoCD runs there — the CRD is missing from the MCP discovery. Use
   `events_list`/`pods_log` for ArgoCD facts (the `Synced -> OutOfSync` event came from there).
   `resources_list` returns **PascalCase columns** (Name/Status/Capacity/Age, `"Access Modes"`) —
   `pods_list`/`pods_log` need `name` (+ `container`, `tail`); `resources_get` needs
   `apiVersion`+`kind`+`name`.
6. **Secrets and Actions vars are 401 anonymously** (`token is required`) at both repo and org
   scope — the forbidden-fact stands; role/credential state must be read from *behaviour*
   (scheduled vs skipped) or by owner command.
7. Registry reading order matters on this fleet: `HEAD /v2/` → **405**; `GET /v2/` → 401 +
   realm; redeem `/v2/token` first, then `tags/list` + `manifests/*`. ghcr has no grace: absent and
   private both answer **403 at token issuance**. `catthehacker/ubuntu` `tags/list` is
   first-page-truncated (100 tags, no rolling `act-*`) — probe the **digest**, not the tag list.
8. The suite idiom `cd "$(git rev-parse --show-toplevel)"` makes any `/tmp` throwaway tree
   **vacuously green**; if run -3 tests anything, `git init` the scratch trees or work in the real
   worktree (bootstrap-2 FRICTION, re-confirmed here by reading the suites' own headers).
9. Transient provider aborts on the flash route: none hit this session; retry-single remains the
   posture (bootstrap-2 FRICTION).

## 7. Open questions for the owner (things no read-only probe can settle)

1. Re-dispatch first (warm-cache retry) or fix-then-dispatch? (§5 A vs B) — the lane is
   retry-safe, so this is a cost/urgency call, not a correctness call.
2. Is `get.helm.sh` reachable from the **job network** at all right now, i.e. TLS-intermittent or
   systematically blocked (MTU/proxy)? Only an in-pod/in-job probe settles it (§4.3.3).
3. Package visibility of the instance-registry `curatedforest/forgejo-runner` **before** the ArgoCD
   sync, and whether the ghcr `ownyourio/forgejo-runner` copy is private or missing (§4.3.4).
   Answering "public on the instance registry: yes/no" decides whether OQ-1=B can ever heal the
   fleet without runner-side registry credentials.
4. `docker-data` actual usage + whether the cf-55 prune leg ever ran (§4.3.2).
5. infra `vars.ROLE` verbatim (expected `dev,prod` per §2.5) and whether `FORGE_PUSH_TOKEN`
   exists as a repo secret (the lane's 0 s success implies yes).
6. Was the GitHub main update (`upstream/main` == `dcc54c091`) done by a direct push rather than
   main-sync? (main-sync has not run since 01:06Z, so it must have been — confirm, because it means
   the fan-out job is currently being done by hand.)
7. Ownership of the ArgoCD sync leg (`gpu-forgejo-runner-gpu` OutOfSync at 22:22:34Z): owner
   applies, or a plan change turns on automated sync? Nothing in this ticket may `kubectl apply`.
