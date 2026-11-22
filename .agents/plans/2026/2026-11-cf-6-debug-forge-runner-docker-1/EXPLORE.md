# EXPLORE — cf-6-debug-forge-runner-docker-1: the runner cannot pull its own baked job image

Scouted 2026-11-22 (runs ~01:00–01:30Z) from the worktree `cf-6-feat-forgejo-container-builds`
on branch `cf-6-debug-forge-runner-docker` (its `b8d7b1d27` is run 0's branch commit; the
landing merged separately). Read-only: git reads + `git fetch`, file reads, read-only k8s MCP
probes (gpu/dev/infra clusters; no `admin-*`, no pod exec, no secret reads), anonymous HTTP
probes (ghcr token flow, both instance registries' bearer-token flow, Forgejo Actions API +
anonymous Actions HTML, api.github.com), upstream reads (forgejo/runner v13.2.0 source via
`git clone --depth 1 --branch v13.2.0` to `/tmp/opencode/fr-src` — kept, outside the repo;
GitHub docs pages; forgejo.org package docs). One temp worktree of `origin/main` at
`/tmp/opencode/main-tip` (suite runs) — removed, `git worktree prune` clean. Nothing
committed, nothing edited outside this file.

**Bottom line.** Run 0's socket fix landed and deployed (`8dc73a71a`, 2026-11-22 00:57Z,
gpu runner restarted with it at 00:59:39Z). The new failure is not a socket problem and not
an auth-configuration problem: **the job image the four act-24.04-family labels now name —
`ghcr.io/ownyourio/forgejo-runner:26.11.1` — does not exist anywhere.** It was a
*walk-predicted* pin: cf-55's D42 ruled that the C05/C06 merge itself would mint it (the
`containers-build` release arm "merge fire" publishing `26.11.1` = `yy.mm.1`). That fire
(run #186, push `6c16aad4a2`, landed on Forgejo main ~22:13Z the 21st) executed only at
01:00:09Z — 30 seconds after the runner pod restarted **with the new labels** (the plan's
bootstrap assumption "the job schedules within seconds, almost certainly still on the OLD act
image" was falsified by queue + ArgoCD timing). Its `detect-changes` job — `runs-on:
ubuntu-24.04`, which the C06 map routes to the not-yet-existing image — died at container
creation with exactly the reported `denied\ndenied`: ghcr answers 403 `DENIED` to the
anonymous pull-token exchange for a repo it has never seen (verified verbatim this session;
the workflow's own comment documents that shape). The same denial has been killing **every
job of every one of the four `.forgejo` workflows** since 00:59:39Z (all use the act labels):
containers-build, main-sync (so the GitHub/dev fan-out is frozen), release, renovate — and
because ArgoCD syncs the runner from **GitHub** (`repoURL: https://github.com/OwnYourIO/SpencersLab.git`,
verified on the live Application), a repo-side label fix cannot deploy itself either: it
would reach GitHub only through the dead main-sync. Two circularities, not one. The user's
hypothesis (labels → instance registry) is *not* the fix by itself: both instance registries
are **provably empty** of the package (404 `NAME_UNKNOWN` under an anonymous bearer token —
a strictly stronger probe than run 0's 401), so B needs the same owner-side bootstrap of A,
plus a chart re-point, plus a full test-teeth re-arm. No repo change can unstick this without
an owner leg; the decision space and the owner commands are in §5–§7.

## 1. Current main state (task 1)

- `git fetch origin` clean (twice — main moved during the scout). **`origin/main` tip =
  `a4900315290efe9174720ddc46ec816cb03699b1`** ("Update markbeep/audiobookrequest Docker tag
  to v2 (#88)", 2026-11-22 01:09:56Z).
- **Run 0's landing is merged: `8dc73a71a71e3d5840ed3fe5b6733e40ea525320`** — "feat(cf-6):
  complete forge runner docker socket contract — enable job containers to docker build"
  (committer 2026-11-22 00:57:01Z, pushed to Forgejo main by `tms`). 16 files = the six
  landing files (`charts/forgejo-runner/templates/secret-runner.yaml` +6 — the
  `docker_host: unix:///var/run/docker.sock` line + its why-comment; `charts/forgejo-runner/values.yaml`
  +7/-2 — comment-only, labels untouched; `services/dev/prod/values.yaml` — the dated
  cf-104 relocation-truth comment; `tests/services/dev-forgejo-runner.sh` +243; `tests/services/
  forgejo-containers-build.sh` ±20; `tests/services/gpu-forgejo-runner.sh` +70) plus the
  run-0 ticket folder and cf-55 ledger riders.
- **The labels were set by the cf-55 fix round, and nothing post-merge touched them again**:
  `b150b4f60` (C05 — `containers/forgejo-runner/Dockerfile` + README, first creation) and
  `1a99f7629` (C06 — the four act-24.04-family labels → the baked pin) both at 2026-11-21
  22:00:34Z (batch tip `6c16aad4a2`, pushed ~22:13Z). On the tip the `runner.labels` block is
  exactly:

  ```yaml
  labels:
    - ubuntu-latest:docker://ghcr.io/ownyourio/forgejo-runner:26.11.1
    - ubuntu-24.04:docker://ghcr.io/ownyourio/forgejo-runner:26.11.1
    - ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04
    - docker:docker://ghcr.io/ownyourio/forgejo-runner:26.11.1
    - node22:docker://ghcr.io/ownyourio/forgejo-runner:26.11.1
  ```

  with the values.yaml law comments: "The pins are immutable calendar tags and **no renovate
  manager reads these lines**, so a bump is manual: one values line plus the ArgoCD sync.
  Rolling refs are forbidden here (`:main`/`:latest` included) — these runners never re-pull
  a tag they have cached … a wrong calendar pin fails loudly as a pull error."
  Renovate non-read **verified this session**: `renovate.json`'s only `values.yaml`-matching
  image extractor (customManager 0) requires the literal `image:` prefix — the
  `- <label>:docker://…` list entries match nothing (mgrs 3/4/5/9 are chart-version/Go-module
  shapes). AGENTS.md's paragraph (`:457-460`) repeats the hand-bump law.
- `containers/forgejo-runner/` on the tip: Dockerfile `FROM
  ghcr.io/catthehacker/ubuntu:act-24.04@sha256:7bf3a8af…` + `ARG HELM_VERSION=v3.22.1`,
  `ARG CR_VERSION=1.10.1`, `ARG CR_SHA256=ce46baf9…`; README carries the **bump law** and the
  D42 first-merge note: "a brand-new image's first calendar tag is deterministic — both
  registry walks see no tags, so it publishes `<yy.mm>.1` of the merge month (**26.11.1** for
  the November landing); the C06 label pins predict exactly that literal. If the merge crosses
  into the next month, the owner amends the one label-pin line (UA-8)." The chart renders
  `.Values.runner.labels` verbatim into the ExternalSecret `config.yaml`
  (`secret-runner.yaml` :150-154), beside the D39/D40 record comment (t14 pins that the
  record names `ownyourio/forgejo-runner`).

## 2. Provenance of `26.11.1` (task 2)

**It was never minted by anyone.** Candidates, tested:

- **(a) forge `containers-build` release arm (the D42 merge fire)** — the intended publisher.
  The run exists: anonymous Actions HTML shows **run #186, `containers-build.yaml`, push
  event, commit `6c16aad4a2` (the C05+C06 batch tip), status Failure, duration 17s**. The gpu
  runner log ties it to the restart: daemon start 00:59:39Z → `task 386` at 01:00:09Z →
  `Cleaning up network for job detect-changes` — i.e. the fire's **first job died at container
  creation pulling its own job image** (17s is impossible for a multi-GB act-derivative build
  + two-registry publish). **No forge build has ever published**: ghcr shows zero calendar
  tags fleet-wide (wekan-mcp list byte-identical to run 0), and §3 proves both instance
  registries `NAME_UNKNOWN` for the package. The cf-55 plan's bootstrap premise — "its job
  schedules within seconds, almost certainly still on the OLD act image" (plan :615-618) —
  was defeated by timing: capacity-1 backlog (Renovate batch #137–183 filled the queue
  22:06–22:12Z) + the ArgoCD flip arriving with the *next* re-render (the 00:59:39Z
  socket-fix restart carried the C06 labels live for the first time, 2.5 h after the batch
  landed on Forgejo main — proven by main-sync #189/#191 **succeeding** at 23:08/00:57, i.e.
  still on cached act-24.04 before that restart).
- **(b) GitHub fallback `workflow_dispatch`** — REFUTED: the `.github/workflows/docker-build.yaml`
  runs API (anonymous, repo public) shows the newest runs are 2026-11-19 (all `pull_request`/`push`,
  zero `workflow_dispatch` recent); and the Dockerfile it would build only reached GitHub main
  with the 00:57Z fan-out. Even a dispatch **cannot mint `26.11.1`**: it computes tags
  `v<run_number>` + `<branch>` (never a calendar tag).
- **(c) built before the law by another route** — REFUTED: `containers/forgejo-runner` first
  exists at `b150b4f60` (2026-11-21 22:00:34Z); nothing earlier could have built it.

cf-55's own records confirm the pin was always a prediction, not an observation: chunk C06's
probe table — "ghcr probe … ownyourio/forgejo-runner token exchange DENIED (repo absent —
image never built; control forgejo-host-runner serves anonymously) ⇒ walk-predicted branch:
26.11.1 = `date +%y.%m`.1 correct today" — and STATE.json `ghcr_fact`: "tags/list => 403
resource-denied (repo absent = registry provably empty)".

## 3. Registry probes, tag-precise, both registries (task 3)

All statuses VERBATIM, 2026-11-22 ~01:07–01:24Z, anonymous only.

**ghcr (`ghcr.io/ownyourio/forgejo-runner`)**

| probe | result |
|---|---|
| `GET https://ghcr.io/token?scope=repository:ownyourio/forgejo-runner:pull` | **HTTP 403** `{"errors":[{"code":"DENIED","message":"requested access to the resource is denied"}]}` |
| `GET /v2/ownyourio/forgejo-runner/tags/list` (no bearer — none issuable) | **HTTP 403** `{"errors":[{"code":"DENIED","message":"invalid token"}]}` |
| `HEAD /v2/ownyourio/forgejo-runner/manifests/26.11.1` (Accept oci-index + manifest-list) | **HTTP 401** + `www-authenticate: Bearer realm="https://ghcr.io/token",service="ghcr.io",scope="repository:ownyourio/forgejo-runner:pull"` |
| control `ownyourio/wekan-mcp` token | **HTTP 200** → tags/list **HTTP 200**, 20 tags, still zero calendar tags (same list as run 0) |
| `api.github.com/orgs/ownyourio/packages/container/forgejo-runner` (anon) | **HTTP 401** `Requires authentication` (the REST API gates on auth even for public packages — cannot consult it anonymously) |

The daemon's reported `error from registry: denied\ndenied` is this 403-DENIED body as docker
renders it; the workflow text itself documents the shape ("GHCR answers DENIED (403), not
404, on the token endpoint for a repository nobody has pushed", containers-build.yaml
:264-267). **Existence verdict:** on ghcr the anonymous probes alone cannot distinguish
*absent* from *present-but-private* (both DENY token issuance) — but combined with §2 (no
publisher ever ran: zero successful runs on every path, no GitHub dispatch, package creation
requires a push) **absent is the evidence-backed state**; the launch's error text is NOT the
`manifest unknown` shape because the pull never got to the manifest step. Owner settle (any
PAT): `gh api /orgs/ownyourio/packages/container/forgejo-runner` — 404 = absent, 200 =
exists (then check `visibility`).

**Instance registries — both hosts, same shape (NEW probe recipe, supersedes run 0's)**

`GET /v2/` → **401** but with `www-authenticate: Bearer realm="https://<host>/v2/token",
service="container_registry",scope="*"` — a **token realm**. Redeeming it:

| probe (both `git.spencerslab.com` and `git.scifi.farm`) | result |
|---|---|
| `GET /v2/token?scope=repository:curatedforest/forgejo-runner:pull` | **HTTP 200** (JWT issued anonymously) |
| `GET /v2/curatedforest/forgejo-runner/tags/list` (Bearer that token) | **HTTP 404** `{"errors":[{"code":"NAME_UNKNOWN","message":""}]}` |
| `GET /v2/curatedforest/forgejo-runner/manifests/26.11.1` (Bearer) | **HTTP 404** |
| `GET /api/v1/packages/curatedforest?type=container` (plain anon) | **HTTP 200 `[]`** — the org's whole container namespace is empty |

So the registries do **not** blanket-gate anonymous reads (run 0's "401 UNAUTHORIZED for
everything" was the un-negotiated challenge, and `HEAD /v2/` answers **405 allow: GET** — a
probe-method trap, record it); with an anonymous token the answer is `NAME_UNKNOWN`: the
package is **provably absent from both instance registries**. Forgejo's access model (docs
user/packages "Access Restrictions"): read = "public, if org is public, otherwise org
members only" — the `CuratedForest` org answers 200 anonymously, so per the model, a package
that exists there will be anonymously *readable*; whether 15.0.10's `/v2/` middleware fully
honours that has never been observable (no package ever existed) — **UA-10 stays open** until
a real push. Contrast live: `data.forgejo.org` (Forgejo **17.0.2**) serves
`/v2/forgejo/runner/tags/list` → **200 anonymously** — anonymous public container reads work
in current Forgejo generally (it's how the runner image itself reaches the pods); our
instances are **15.0.10** (`GET /api/v1/version`).

## 4. The pull path, grounded (task 4)

- The rendered config's labels map `ubuntu-24.04` (etc.) →
  `docker://ghcr.io/ownyourio/forgejo-runner:26.11.1`; the PULL is performed by the
  **runner daemon** against the **in-pod dind daemon** at job-container creation (v13.2.0
  source: `act/runner/run_context.go` `prepareJobContainer` →
  `act/container/docker/run.go:166` `Pull` → `pull.go` `NewDockerPullExecutor`). It is **not**
  a kubelet pull — `imagePullSecrets` on the pod are irrelevant to job images (only the two
  *pod* images, `data.forgejo.org/forgejo/runner:13.2.0` and `docker:29.9.2-dind`, go through
  kubelet; both pull anonymously today).
- Auth order in `pull.go`/`auth.go`: (1) `NewContainerInput.Username/Password` — populated
  **only** from the workflow job's `container: credentials: {username,password}` (`run_context.go:1776`
  `handleCredentials`); **none of the four `.forgejo` workflows declares `container:`** (run 0
  §2; verified against the tip file), so empty — that is the `username=` in the failure log.
  (2) fallback `LoadDockerAuthConfig`: `docker/cli config.Dir()` = `$DOCKER_CONFIG` (unset in
  the chart) else `$HOME/.docker/config.json`; the runner image sets **`ENV HOME=/data`**
  (`Dockerfile:39`, upstream source) → the lookup is `/data/.docker/config.json` inside the
  runner container — a file the chart never mounts (persistence: `/var/run` emptyDir,
  `/data` PVC, `/run/secrets/forgejo-runner` + config.yaml subPath — run 0 §4 live spec; no
  `.docker` entry in the chart). ⇒ the daemon pull is strictly anonymous. (3) `forcePull` is
  false (config default; chart sets none) — but `pull.go:44` skips the pull only when
  `ImageExistsLocally`; a never-pulled tag always attempts the pull. (Bonus fact for a future
  digest pin: `isPinnedImage` (`@sha256:` refs) skips re-pull even with forcePull.)
- **Pre-cf-55 the same anonymous path worked** because `ghcr.io/catthehacker/ubuntu:act-24.04`
  is public (upstream catthehacker) and, once pulled, cached in the 10 Gi `docker-data` PVC.
- **Missing ingredient:** the image's *existence* on the named registry (ghcr: absent; the
  visibility question is moot for an absent package — if later pushed by `GHCR_PUSH_PAT` the
  new org package's visibility defaults to the org's "Package creation visibility" setting,
  and GitHub's docs state a linked repo inherits *permissions* "but not the visibility" — a
  PAT-created package must be made public once, owner UI. The 13 legacy images are
  anonymously public today — created by the GitHub fallback's `GITHUB_TOKEN` on a public
  repo, precedent 13/13). If the labels named the instance registry instead (§5 B), the
  same anonymous path would work per the token-flow probes once the package exists, with the
  15.0.10 behaviour unproven (UA-10). A repo-side third path exists in principle — mount
  `/data/.docker/config.json` (or set `DOCKER_CONFIG`) with a pull PAT via the chart, making
  *any* private package pullable — grounded in `auth.go` above; it does not fix existence.

## 5. Fix space, ranked by the grounded facts (decision stays with plan/owner)

**Framing fact — two circularities, so no repo-only fix self-heals:** (i) the *publisher* of
the missing image (containers-build release arm) itself runs on the missing image — any
re-run, dispatch, or next containers/** merge dies at `detect-changes` before building
anything; (ii) the *deployer* of any repo-side label fix is ArgoCD reading **GitHub** main
(`gpu-forgejo-runner-gpu` Application sourceRepo verified live:
`https://github.com/OwnYourIO/SpencersLab.git`, targetRevision main), which only advances via
the dead main-sync. **Every family below needs at least one owner-side command**; only family
A needs zero repo commits.

1. **A — owner bootstraps the image onto ghcr and (if needed) sets it public. Zero repo
   change, breaks both circularities at once.** Facts supporting it: the package is absent
   (§2/§3), the pin is a valid future-tense prediction (D42: first calendar tag of a brand-new
   image is `26.11.1` iff published in November), the anonymous ghcr public pull is the
   proven lane (13/13 legacy images), and no test or chart surface moves. Exact owner steps:
   on any machine with docker, `docker build` `containers/forgejo-runner` at the tip tree;
   tag + push `ghcr.io/ownyourio/forgejo-runner:26.11.1` (plus `:latest`/`:main` for
   convention) with a `write:packages` PAT (`docker login ghcr.io -u OwnYourIO`); then
   ghcr.io → org `ownyourio` → package `forgejo-runner` → Package settings → **Make public**
   (set once; visibility is not push-settable). Afterwards the dead runs can be re-run from
   the Actions UI (re-run of #186 will then genuinely build and publish, taking `26.11.2` via
   the walk since `26.11.1` is taken — the label stays honestly on `26.11.1` until the manual
   bump law moves it). Caveat to rule: content built outside the forge pipeline is a
   provenance deviation — pin the exact commit (`b150b4f60`+labels-consistent tree = today's
   tip Dockerfile is unchanged since C05).
2. **B — labels → `git.spencerslab.com/curatedforest/forgejo-runner:26.11.1` (the user's
   hypothesis).** The facts say B is *not* a substitute for A's bootstrap: the instance
   registry is provably **empty** (§3), so the owner must push the image *there* first (e.g.
   the same manual build + `docker login $registry -u forge-push -p $FORGE_PUSH_TOKEN &&
   docker push`); the user's instinct "look at the forgejo repo for the ownyourio stuff"
   conflates registries — the `ownyourio/forgejo-runner` package name is the ghcr half of the
   dual-publish. B *after* a forge-registry push then hinges on **15.0.10 anonymous pulls of
   public-org packages being unproven** (UA-10 was deliberately routed to the owner by cf-55:
   "instance-registry `/v2/` anonymous pull is NOT proven runner-side … never assumed",
   D39) — the anonymous token flow + Forgejo's org-public read model say it *should* work
   (and 17.0.2 upstream proves the capability exists), and if it doesn't, B additionally needs
   the §4 docker-config mount (a chart change). Repo cost: four label lines + comments +
   secret-runner record rewrite + AGENTS/README law flips + the full g7/t2/t14/g2 re-arm (§6).
   Rank below A on facts (same owner leg, more repo churn, one unproven dependency).
3. **A′/B′ — mount `/data/.docker/config.json` (pull creds) on the runner via the chart.**
   Grounded in `auth.go` (§4): makes whatever registry the labels name auth-pullable,
   private-visible or not — a good *belt-and-braces* for B (kills the UA-10 risk) or for
   keeping a PAT-pushed ghcr package private. Still requires the image to be bootstrapped
   (§4). Repo cost: persistence/env additions under charts/forgejo-runner — **g7's non-comment
   clause reds it as-is** (only comments/labels/the one socket line are sanctioned); it is a
   new sanctioned class needing a g7 re-arm + secret-render test updates. Rank as an
   amendment, not a primary.
4. **D — revert the four labels to `ghcr.io/catthehacker/ubuntu:act-24.04`** (public +
   already cached in dind → Actions revive the moment ArgoCD can sync). Honest but heavy:
   needs an owner fan-out for deploy (ii), re-arms the same test surfaces (the g7 out-shape
   only accepts *removing* act-24.04 lines, §6), re-introduces the D33 installer-instability
   the baked set exists to kill, and the next containers/** merge then mints `26.11.1` via the
   release arm — with the visibility footgun: a PAT-created ghcr package may land private, so
   the *second* flip to baked labels would die exactly here unless the owner flips visibility
   (org "Package creation visibility" default is owner-configurable). D is A's work done the
   slow way; list it for completeness.
5. **C (launch's hybrid: "release arm re-push after ensuring visibility on first push")** —
   FACT-CHECKED FALSE as an entry point: you cannot pre-set visibility for a package that does
   not exist (ghcr creates it on first push with a default), and the release arm cannot run
   before the image exists (circularity i). Visibility-setting is one-time owner UI, never a
   push property.

**Ranking by facts: A > B (with a forge-registry bootstrap; add A′ if UA-10 fails) > A′ as
amendment > D.** What only the owner can confirm/run: ghcr package absent-vs-private settle;
org package-creation visibility; the manual build+push+public leg; the GitHub fan-out for any
repo-side fix (or admin-tier live Secret patch outside GitOps — explicitly the owner's call);
secret presence (`GHCR_PUSH_PAT`, `FORGE_PUSH_TOKEN` in the repo's Actions settings — not
anonymously readable).

## 6. Blast radius + test teeth (task 6)

**Live blast (grounded, infra instance, since 00:59:39Z):** every job of every `.forgejo`
workflow `runs-on` an act-family label (containers-build :95/:153/:360, main-sync :30/:51,
release :38/:85/:146/:265/:342, renovate :63), so all four are down. Evidence: runner log
tasks 386–401 each followed immediately by network cleanup; UI table — containers-build #184
(PR #90 "Update Node.js", touches `containers/{coder-workspace,gpt-researcher-frontend}` —
**the user's task 389 = `pr coder-workspace` of this PR**), #185 (PR #91, `containers/
forgejo-host-runner`), #186 all **Failure**; main-sync #193 + release #192/#194 **Failure**
(#191/#193 show `push-gh`/`push-dev` tasks received then dropped at 01:06/01:10) ⇒ **GitHub +
dev mirrors frozen at `8dc73a71a`** (cf-145 + #88 merged commits not fanned out) and chart
releases + the Renovate daily pass are not running. The dev cluster's `dev-forgejo-runner-dev-0`
is *not yet affected* (last daemon start 2026-11-19T02:41:02Z — its ArgoCD has not applied
C06/the fix; it will fall into the identical trap the moment it syncs, latent not safe). Also
latent: the first **push** to Forgejo main touching `containers/**` after recovery fires the
release arm and (with a public `26.11.1` already pushed) mints `26.11.2` — the "bumped by hand
to the newest published calendar tag" law then expects the label re-pin; nothing automatic.

**Suite baseline measured this session (temp worktree at tip `a49003152`, helm on PATH):**
`dev-forgejo-runner.sh` exit 0 (57 ok), `gpu-forgejo-runner.sh` exit 0 (18 ok),
`forgejo-containers-build.sh` exit 0 (41 ok) — run 0's three-red-leg drift is gone (cf-6
re-armed it). **Family A ⇒ zero churn** (these suites pin strings, not registry state; the
ghcr probe legs are default-off). Family B/D/A′ ⇒ the legs that go RED and must move in the
same commit: `dev-forgejo-runner.sh` **t2** (L267-271 `ACT_LABELS` hard-codes the four
`ghcr.io/ownyourio/forgejo-runner:26.11.1` strings; L476 message), **t14** (L702-703: the
`secret-runner.yaml` record block must contain `ownyourio/forgejo-runner`), `gpu-forgejo-runner.sh`
**g2** (L227-231/273 — same baked-set equality), and **g7** (L636-750): the just-armed fence
computes the diff vs `GPU_RUNNER_DIFF_BASE` (origin/main) and — grounded in its code — for a
*label* change requires **removed** `docker://` lines to contain
`catthehacker/ubuntu:act-24.04` (a revert or re-point removing the ownyourio:26.11.1 line →
RED, "not the act-24.04 out-shape") and **added** lines to match
`ownyourio/forgejo-runner:[0-9]{2}\.[0-9]{2}\.[0-9]+` (an instance-registry or act-24.04
re-add → RED), caps changed `docker://` lines at 8, keeps `ubuntu-22.04` byte-stable (D40),
and reds **any non-comment, non-label chart line** except the single value-exact
`docker_host:` line already sanctioned **add-side** against the pre-cf-6 base (post-landing,
that exemption can only match a re-addition; the "anything wider stays red" clause is live —
so A′'s env/mount lines need a **new sanctioned class, i.e. a g7 re-arm** exactly like cf-6's
OQ-C did). `tests/containers/forgejo-runner.sh` pins the Dockerfile ARGs (unaffected);
`tests/services/forgejo-release.sh` forbids run-time tool installs in workflows (closes the
"just install helm in the job again" alternative). Chart render pins t15 (container block
equality) stay green under A/B/D; they move only with a config-key change (A′ adds pod env,
not config — t15-safe, g7-unsafe).

## 7. Could-not-verify — owner commands (task 7)

1. **ghcr package absent vs private** (anonymous DENIED both):
   `gh api /orgs/ownyourio/packages/container/forgejo-runner` (or `curl -u "ownyourio:$GHCR_PUSH_PAT"
   https://api.github.com/...`) — 404 = absent; 200 → read `.visibility`.
2. **Secrets presence** (`GHCR_PUSH_PAT`, `FORGE_PUSH_TOKEN`): Actions → Secrets UI on
   `git.spencerslab.com/CuratedForest/SpencersLab` (no anonymous API).
3. **org Package-creation visibility default**: org Settings → Packages.
4. **UA-10 (15.0.10 anonymous container pull of a public-org package)** — settle after any
   test push: `curl -s "https://git.spencerslab.com/v2/token?scope=repository:curatedforest/
   forgejo-runner:pull" | jq -r .token` then `curl -H "Authorization: Bearer <tok>"
   https://git.spencerslab.com/v2/curatedforest/forgejo-runner/tags/list` (200 ⇒ B viable
   anonymously), and/or bare `docker pull git.spencerslab.com/curatedforest/forgejo-runner:latest`
   on an un-logged-in docker.
5. **Instance-registry authenticated tag state** (belt for §5 B / retention rules):
   `curl -u "forge:$FORGE_PUSH_TOKEN" https://git.spencerslab.com/v2/curatedforest/forgejo-runner/tags/list`.
6. **Why the dev release hasn't synced C06** (auto-sync window?): dev-cluster ArgoCD UI/
   `kubectl -n default get application dev-forgejo-runner-dev -o jsonpath='{.spec.syncPolicy} {.status.sync.revision}'`
   — until it syncs it stays on the old cached map (and then breaks identically).
7. **Actions queue semantics** (when #186 was actually scheduled) — job/step logs are not
   anonymously exposed (run 0 §9 still true); timings inferred from the runner-pod log +
   relative-time stamps, labelled as inference in §2.
8. **Live rendered runner config** (the secret bytes): readonly SA is forbidden on Secrets
   (run 0 §4); the daemon's log line `declared successfully … labels: [ubuntu-latest
   ubuntu-24.04 ubuntu-22.04 docker node22]` proves the *names*, and the observed
   `Start image=ghcr.io/ownyourio/forgejo-runner:26.11.1` proves the *map* is live — the
   `docker_host:` key itself stays repo-template-authoritative (owner: `kubectl -n default
   get secret gpu-forgejo-runner-gpu -o jsonpath='{.data.config\.yaml}' | base64 -d | sed
   -n '/^container:/,/^server:/p'`).

## Gotchas for downstream agents

- HEAD vs GET: `HEAD /v2/` on the instance registries answers **405** (allow: GET); run 0's
  "uniform 401" was the un-negotiated challenge — always redeem `/v2/token` before concluding
  a gate. ghcr *lacks* that grace: absent repo = 403 at token issuance, never 404.
- The anonymous API for instance Actions returns only `id/event/status` (sparse) and its id
  space ≠ the UI's run number; the **UI HTML** (`/actions`, anonymous) carries workflow,
  commit, status tooltip and timestamp — parse it for forensics.
- No tier grants pod exec; the multi-GB first pull lands on the 10 Gi `docker-data` PVC —
  prune escape (cf-55 plan point 4) stays owner-run.
- Task-id ↔ run mapping via the runner log timestamps ("Cleaning up network for job X" =
  the job's death line, not success).
