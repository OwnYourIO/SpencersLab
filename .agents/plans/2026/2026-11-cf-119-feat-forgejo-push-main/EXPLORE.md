# EXPLORE — cf-119 Forgejo main-sync jobs (card #119)

Written by `agent-explore` 2026-11-06 (workspace clock; UTC+0 probes). Read-only
grounding for the planner: CI layout, Forgejo surface, remotes, "the built in
mechanism", credentials, and the `backup-proxy` question.

## Card recap (topology)

- **Job 1** — a Forgejo Actions workflow on the **infra** instance
  (`git.spencerslab.com`, repo `CuratedForest/SpencersLab`), triggered on every
  push to `main`, that **non-force** pushes `main` to
  `github.com/OwnYourIO/SpencersLab` **and**
  `git.scifi.farm/CuratedForest/SpencersLab` (the **dev** instance's copy of
  the same repo). Must fail the run if either push fails.
- **Job 2** — a Forgejo Actions workflow on the **dev** instance
  (`git.scifi.farm`, same repo path), triggered when `main` syncs (i.e. by
  Job 1's push), that merges `main` into the `backup-proxy` branch.

Instance identity is grounded in
`.agents/notes/2026-10-23-forgejo-git-ssh.md` (dev = `git.scifi.farm`,
infra = `git.spencerslab.com`, git-over-SSH on **:22222** via traefik Gateway;
`:22` is the node sshd — the Coder workspaces' remotes all use the `ssh://…:22222`
shape). Both instances run **Forgejo 15.0.10** (dev pod label
`app.kubernetes.io/version=15.0.10`, MCP probe 2026-11-06; infra probed
`15.0.10` in cf-104 DECISIONS:284).

## 1. CI layout (`.github/workflows/` — GitHub Actions only, 7 files)

All seven workflows are GitHub-only; **none pushes to any remote besides
GitHub's own registry/chart-repo plumbing**. Auth is exclusively
`secrets.GITHUB_TOKEN` — no OIDC, no PATs, no deploy keys anywhere in the repo
(verified by reading every file; secret references found:
`aislop.yaml:24` `GITHUB_TOKEN`… actually only these):

| File | Trigger | What it does |
|---|---|---|
| `aislop.yaml` | `pull_request` | `aislop ci --changes` quality gate on touched files (pinned `npx aislop@0.20.0`, Node 24, `ubuntu-26.04`) |
| `docker-build.yaml` | `push` main/dev on `containers/**`; `pull_request`; `workflow_dispatch` | Detects changed containers, matrix build+push to `ghcr.io` (`v<run>` + branch tag); PR builds never push; `permissions: contents:read, packages:write` + `GITHUB_TOKEN` login |
| `gpt-researcher-render-tests.yaml` | `push` main on chart/container/service/custom-values paths; `pull_request` (same paths) | pytest `charts/gpt-researcher/tests` + `helm lint`/`helm template` (chart + dev umbrella) |
| `llama-swap-tools-tests.yaml` | same shape, paths `charts/llama-swap/**` + gpu/gpu-ai/proxy-local values | pytest + helm lint/template of chart, gpu-ai, gpu, proxy-local umbrellas |
| `vllm-render-tests.yaml` | same shape, paths `charts/vllm/**`, `containers/vllm-rocm/**`, gpu-ai values | pytest + helm lint/template |
| `release.yaml` | `push` main on `charts/**` | chart-releaser: detect changed charts, bump `Chart.yaml` version (patch), commit back to the repo (`contents:write` + `GITHUB_TOKEN`), upload to the Helm chart repo |
| `rulesync.yaml` | `pull_request` | `npx rulesync@37.0.0 generate --check` drift gate |

Recurring shapes to imitate or avoid: path-filtered `push: branches: [main]`
triggers; `permissions: contents: read` job defaults; `ubuntu-26.04` runners
(GitHub-hosted — NOT available on the lab Forgejo runners, see §2). A mirror
push to GitHub `main` will re-trigger GitHub's path-filtered push workflows
(`release.yaml` on `charts/**`, `docker-build.yaml` on `containers/**`, the
three render-test suites) — that behavior already exists for any GitHub main
push and is not new, but the plan should note it (a charts/** commit synced
from infra fires `release.yaml` on GitHub; chart-releaser re-running is
idempotent via `skip_existing`).

## 2. Forgejo surface in this repo

**No `.forgejo/` (or `.gitea/`) directory exists.** Root listing 2026-11-06:
`.agents .aislop .github .gitignore .kilo .opencode .rulesync …` — no
workflow dir for Forgejo. Everything Forgejo is deployed *by* this repo, but
no workflow file lives in it yet.

### Instances (deployed from `charts/forgejo`, the upstream wrapper)

| | dev instance | infra instance |
|---|---|---|
| Host (canonical) | `git.scifi.farm` | `git.spencerslab.com` (`forgejo.spencerslab.com` is an alias; **banned for runner/LFS use** — public-edge TLS cert name-mismatch, cf-104 §R3 / DECISIONS:148) |
| Cluster / release | dev cluster, `default/dev-forgejo` | infra cluster, `default/infra-forgejo` |
| Wiring | `services/dev/prod/values.yaml:76` (+`ingress.subdomains.git:137`), `custom-values/dev` | `services/infra/prod/values.yaml:18-20,85-91,106-111` (`gitSshPort: 22222`), `custom-values/infra/prod-values.yaml:44-87` |
| Version | 15.0.10 | 15.0.10 |
| Live 2026-11-06 ~23:08 UTC | **DOWN**: pod `Init:CreateContainerConfigError` — `secret "forgejo-s3-secret" not found`; ESO `forgejo-s3-secret` `ready=False` on dev (`True` on infra; MCP `resources_list` ExternalSecret) | **UP**: `default/infra-forgejo` ready 1/1 (14d) |

The dev outage (down ~21:05 UTC today, 123-min-old pod) is the LFS SeaweedFS
S3 secret leg from the cf-104 (forgejo-lfs) work — **a separate workstream's
problem, but it blocks Job 2's live validation today and also makes
`https://git.scifi.farm` answer 503 "no available server"** (verified via the
`spencerslab-dev` remote `git ls-remote`).

### Runners (deployed from `charts/forgejo-runner`, docker backend + DinD)

| Release | Cluster | Dials | Live |
|---|---|---|---|
| `dev-forgejo-runner-dev` | dev, `default`, STS | `http://dev-forgejo-http:3000` in-cluster (`services/dev/prod/values.yaml:96-105,164-167`) | **CrashLoopBackOff**, 28 restarts; log tail: `fail to invoke Declare … dial tcp 10.43.249.131:3000: connection refused` (downstream of the dev server outage) |
| `gpu-forgejo-runner-gpu` | gpu, `default`, STS | `https://git.spencerslab.com` — **serves the INFRA instance** (`services/gpu/prod/values.yaml:115-122,271-273`; user ruling cf-104 Q13) | **ready 1/1** (26h) — infra's only runner |

So: **Job 1 (infra) has a live runner; Job 2 (dev) does not, today.**

Advertised labels (chart default `labels:` block, `charts/forgejo-runner/values.yaml:101-107`; no slice overrides on dev or gpu):
`ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`, `docker`, `node22` — each
mapped to `ghcr.io/catthehacker/ubuntu:act-24.04`/`act-22.04`. A workflow must
use `runs-on: ubuntu-latest` (or one of the others); GitHub-style
`ubuntu-26.04` will not route to any lab runner.

Actions-enabled evidence: cf-97 RESEARCH:23 ("server 15.0.10 up with Actions
enabled by default" — dev); cf-104 C05 ("runner record … exists on the INFRA
instance, Settings → Actions") + live `gpu-forgejo-runner-gpu` 1/1.

### Forgejo Actions syntax essentials (docs; verified v17.0 AND v15.0 LTS)

Sources: `forgejo.org/docs/latest/user/actions/overview/`,
`…/basic-concepts/`, `…/reference/` (context tables also present in the v15.0
raw: `codeberg.org/forgejo/docs/raw/branch/v15.0/docs/user/actions/reference.md`,
`server_url` field confirmed), `forgejo.org/docs/latest/user/repo-mirror/`.

- Workflow files: `.yaml` in **`.forgejo/workflows/`**.
  **Fallback gotcha:** "In the absence of a `.forgejo/workflows` directory,
  workflows will be looked up in the `.github/workflows` directory" — once we
  add even one `.forgejo/workflows/` file, the seven GitHub files stop being
  candidates on both Forgejo instances (they'd fail anyway: `ubuntu-26.04`,
  `GITHUB_TOKEN`). This is the desired isolation, but it is a behavior flip
  worth one plan note.
- Trigger: `on: push: branches: [main]` (also `paths:` filters, `workflow_dispatch`,
  `schedule`).
- Context: `forgejo.*` with `github.*` and `forge.*` aliases (compat). Fields
  include `server_url` (instance URL — **the guard key**, e.g.
  `https://git.spencerslab.com`), `repository` (`CuratedForest/SpencersLab` —
  **identical on both instances, cannot guard on it**), `repository_owner`,
  `ref_name`, `sha`, `actor`, `token`, `api_url`, `event_name`.
- Secrets: repo/org/user Actions secrets (UI: `/{owner}/{repo}/settings/actions/secrets`),
  referenced `${{ secrets.KEY }}`; name rules: `[A-Za-z0-9_]`, no `FORGEJO_`/`GITHUB_`/`GITEA_`
  prefix, not `CI`.
- Automatic token `FORGEJO_TOKEN` (alias `GITHUB_TOKEN` / `secrets.FORGEJO_TOKEN` /
  `forgejo.token`): created per run, **scoped to its own repository only**
  ("any attempt to use it on other repositories … will return 404"), **has
  write permission to that repo** (can push branches), and **pushes authored
  with it do NOT re-trigger that repo's workflows** (infinite-recursion guard).
  Consequences: Job 1 **cannot** use the automatic token for its two external
  pushes (different instance / different forge); Job 2 **can** use the dev
  instance's automatic token for `main`→`backup-proxy` (same repo) — and that
  push then does not re-trigger dev workflows (the trigger is `main` anyway,
  so no loop regardless).
- Divergences from GitHub Actions (docs "Known list of differences"): job-level
  `permissions:` and `continue-on-error` are **ignored**; OIDC via
  `enable-openid-connect` key; default env is Debian bookworm + node.js;
  `actions/checkout@v7` shorthand resolves against `DEFAULT_ACTIONS_URL`
  (runner egress to codeberg.org + ghcr.io for act images is required — not
  yet live-verified from the gpu runner; a first-fire risk, see §9).

## 3. Remotes and reachability (this worktree)

`git remote -v` (worktree root, 2026-11-06):

| Remote | URL | `git ls-remote` from this workspace |
|---|---|---|
| `origin` | `git@github.com:OwnYourIO/SpencersLab.git` | **OK** — main @ `0b1e2e2b1f9c…`; full branch listing readable. No `backup-proxy` branch on origin (only `feat/gpu-ai-proxy-backup-services` + `backups-*`/`appset-backups-*` tags) |
| `dev` | `ssh://git@git.scifi.farm:22222/CuratedForest/SpencersLab.git` | **UNREACHABLE** — `coder gitssh` fails, `Connection reset by 10.0.77.12 port 22222` |
| `prod` | `ssh://git@git.spencerslab.com:22222/CuratedForest/SpencersLab.git` | **UNREACHABLE** — `Connection closed by 10.0.77.59 port 22222` |
| `spencerslab-dev` | `https://git.scifi.farm/CuratedForest/SpencersLab-Dev.git` | **503** `remote: no available server` (dev Forgejo pod down — consistent with §2) |

So from this Coder workspace only GitHub is visible; the branch topology of
both Forgejo copies of `CuratedForest/SpencersLab` is **unverifiable here**.
The `prod` remote name implies the lab's mental model: infra = "prod" of the
repo. `CuratedForest/SpencersLab-Dev` is a *different* repo (dev workspaces) —
not a target of the card.

Local branch list: no `backup-proxy` anywhere (`git branch -a` full output
checked); current ticket branch `cf-119-feat-forgejo-push-main` off
`main` (worktree at main state `0b1e2e2b…`, clean apart from the feature folder).

## 4. "The built in mechanism"

Grounded = **Forgejo's native repository mirroring**
(`forgejo.org/docs/latest/user/repo-mirror/`):

- Push mirror: repo Settings → Repository → Mirror Settings → **Add Push
  Mirror**; periodic sync + "Synchronize Now". Docs verbatim: **"This will
  force push to the remote repository. This will overwrite any changes in the
  remote repository!"** No branch filter ⇒ `git push --mirror`; a branch
  filter pushes only matched branches. Supports HTTPS (user+token/password)
  or SSH (instance-generated Ed25519 deploy key).
- Pull mirror: only for repos that don't exist yet; cannot be converted after
  creation.

No mirror configuration lives in this repo (it's instance-DB state), and no
repo script/workflow performs cross-forge pushes (`scripts/` = board/pipeline
machinery only; `git config --list` shows only the four remotes' url/fetch).
**Open:** whether either Forgejo repo currently has push/pull mirrors
configured (e.g. infra pulling from GitHub, which would be today's
GitHub→infra main path) — unverifiable without instance API access; see §8.

## 5. Credentials surface

- **GitHub workflows:** `secrets.GITHUB_TOKEN` only (7/7 files); no OIDC, no
  PAT, no deploy key.
- **Lab pattern for cross-forge git creds** (dev cluster,
  `custom-values/dev/prod-values.yaml:20-29`, live ESOs):
  - `github-pat` — item **dev-github** (password = PAT), UUID `522b1cc4-…`
  - `forgejo-token` — "Forgejo access token for **git.scifi.farm**", UUID `5488c4ba-…`
  - Infra equivalents for the runner: `custom-values/infra` carries the
    `forgejo:` app block (`infra-forgejo`, `infra-forgejo-admin`, `infra-forgejo-pg`,
    `forgejo-s3`, `infra-forgejo-sso`, `custom-values/infra/prod-values.yaml:44-57`).
- **Forgejo Actions secrets are NOT k8s/Bitwarden objects** — they live in the
  instance DB, set per org/user/repo in the UI; the repo's precedent for
  runner tokens is Bitwarden item + **one-time user action in the Forgejo UI**
  (`charts/forgejo-runner/templates/NOTES.txt:20-26` "one-time-user-action
  block"; cf-97 C02). cf-119's new secrets will need the same: mint
  Bitwarden items, then human-enter the values as Actions secrets on the
  infra instance (Job 1's GitHub PAT + dev-Forgejo push token) and, if a
  separate identity is chosen for Job 2, on the dev instance.
- Design note for the plan: **Job 2 needs no external secret** — the dev
  repo's automatic token has same-repo write and its pushes don't re-trigger.
  **Job 1 needs two external credentials** (GitHub PAT — fine-grained needs
  *Contents R/W* plus *Workflows* since the pushed tree includes
  `.github/workflows/`; dev-Forgejo PAT or SSH deploy key for
  `CuratedForest/SpencersLab`). A GitHub *deploy key* (repo write) is the
  alternative for the GitHub leg; the docs' mirror recipe shows the
  fine-grained-PAT shape.

## 6. `backup-proxy`

- String `backup-proxy`: **zero occurrences in the repo** (grep, all files).
- No local branch, no `origin` branch, unverifiable on `dev`/`prod`
  (remotes unreachable from this workspace — §3).
- Nothing in this repo consumes a `backup-proxy` branch: every cluster's
  ApplicationSet tracks `main` for stage `prod`
  (`services/proxy-backup/prod/templates/appset.yaml:~line 40`:
  `$targetRevision := (eq $stage "prod") | ternary "main" $stage`), so the
  proxy-backup cluster (a real cluster category, `services/proxy-backup/`)
  is not reading it either.
- Best reading: a user-maintained branch **on the dev instance's
  `CuratedForest/SpencersLab`** (the repo Job 2 lives in) whose purpose is
  not documented in this repo. If it doesn't exist yet, "merge main into
  backup-proxy" degenerates to *create it from main* — a plain
  `git push origin HEAD:refs/heads/backup-proxy` (new-branch push,
  inherently non-force, succeeds either way). **Open question for the user**
  (§8, OQ-2).

## 7. Loop / ping-pong analysis (planning input)

Once committed, the `.forgejo/workflows/` files exist in the repo content, so
**both instances' copies of the repo carry both jobs**:

1. infra main push (human/CI on the infra instance) → Job 1 fires (infra
   runner, live). It pushes main → GitHub + main → dev.
2. That push lands on **dev main** → dev's copy of Job 1 also matches
   `on: push: branches: [main]` → **must be skipped by an instance guard**
   (`if: forgejo.server_url == …git.scifi.farm…`-style negation, i.e. Job 1
   guards `== 'https://git.spencerslab.com'`, Job 2 guards
   `== 'https://git.scifi.farm'`). Without guards: infinite ping-pong
   (each side re-pushes to the other; non-force pushes fail fast once history
   diverges, but the runs would flap every sync).
3. Job 2 fires on dev main → merges main→backup-proxy (auto-token, same repo,
   no re-trigger; trigger is `main`-only anyway).
4. GitHub main push → GitHub's path-filtered workflows may fire (§1 note);
   GitHub never pushes back to either Forgejo (no such job on GitHub), so no
   GitHub-originated loop.
5. The automatic token's recursion guard covers same-repo pushes only — it
   does **not** protect Job 1's cross-instance pushes; the guards in (2) are
   the actual loop breakers.

`server_url` format risk: docs show `https://code.forgejo.org` (no trailing
slash); infra's `ROOT_URL` is `https://git.spencerslab.com/`. The plan should
use a tolerant comparison (`startsWith`/`endsWith` or trim) or echo the value
in a first-fire smoke step — the exact rendered value is only knowable
live.

## 8. Open questions (needs-research: none required; needs-user: yes)

- **OQ-1 (topology/bootstrap — user-owned):** today, how does GitHub main
  reach the infra instance's `main` (the card treats infra as the source of
  truth, but this pipeline lands PRs on GitHub)? Is there already an
  infra-side **pull mirror from GitHub** or a manual habit? The new
  `.forgejo/workflows/` files only become live on infra once they are on
  infra's `main` — a one-time bootstrap step (merge on GitHub → sync to infra
  by whatever mechanism OQ-1 names) must be part of the rollout. Also: check
   and disable any existing **push mirrors** on both Forgejo repos so the
  built-in force-push path doesn't run alongside the new jobs (mirror
  settings live in instance DB — user-side check).
- **OQ-2 (`backup-proxy`):** confirm the branch exists on
  `git.scifi.farm/CuratedForest/SpencersLab` (and its purpose/drift) — or
  rule that Job 2 may create it from main if absent. Unverifiable from this
  workspace (dev unreachable, §3).
- **OQ-3 (runner egress):** unverified whether the gpu docker runner can pull
  `actions/checkout`-class actions (codeberg/DEFAULT_ACTIONS_URL) and
  `ghcr.io` act images, and can egress to `github.com` + `git.scifi.farm`
  (SSH :22222 or HTTPS) — first-fire will reveal; plan should keep a
  `workflow_dispatch` smoke step or accept a first-run failure as expected
  (the card wants job-failure on push failure, not runner-network failure).
- **OQ-4 (dev instance outage):** `dev-forgejo` is down today
  (`forgejo-s3-secret` ESO not ready — cf-104 LFS leg). Job 2 can be written
  but not live-validated until that's repaired; and Job 1's dev-remote push
  will **fail until then** (card: "if it does I do expect the job to fail"
  — so expect red Job 1 runs until dev recovers). Flag to the user at plan
  approval.

## 9. Implications for the plan (files, chunks, validation)

- **Repo files to create (the entire in-repo surface):**
  `.forgejo/workflows/<name>.yaml` — one or two workflow files (Job 1 + Job 2,
  each instance-guarded; a single file with two jobs is viable since
  job-level `if:` guards work). No chart/service/custom-values changes needed:
  both instances, both runners (where live), SSH gateway, ingress all already
  exist. `Services=dev,gpu` on the card matches the two runner hosts (dev
  cluster hosts dev-forgejo+runner; gpu cluster hosts infra's runner).
- **Out-of-repo (human) legs the plan must enumerate, not implement:**
  (a) mint the GitHub push PAT (fine-grained: Contents R/W + Workflows) and
  dev-Forgejo push token as Bitwarden items; (b) set them as **infra-instance
  Actions repo secrets** for `CuratedForest/SpencersLab` (Job 1); Job 2 uses
  the automatic token (no secret); (c) bootstrap the merged workflow files
  onto infra's `main` per OQ-1; (d) check/disable pre-existing mirrors (OQ-1);
  (e) verify `backup-proxy` state on dev (OQ-2).
- **Validation feasible in THIS workspace** (no docker daemon, forges
  unreachable — §3):
  - `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .forgejo/workflows/<f>.yaml`
    (pyyaml 6.0.3 present; python 3.14.4)
  - structural asserts (trigger `push`/`branches: [main]`, both `if:`
    instance guards, `runs-on:` ∈ the five runner labels, `secrets.*` names
    match the planned secret names, no `--force` anywhere, `set -euo pipefail`
    in run steps) — a small `tests/services/` script in the repo's
    existing suite shape (`infra-forgejo.sh` / `gpu-forgejo-runner.sh`
    conventions: `bash` + ok/skip/fail counters, run-from-anywhere, no
    network dependence) is the natural home; plan decides naming.
  - `git ls-remote origin` (GitHub reachable) to re-confirm branch state pre/post;
    forge remotes honestly report as unreachable.
  - `helm` v3.16.4 at `~/.local/bin` (export `PATH=$HOME/.local/bin:$PATH`)
    — only if the plan adds chart-side changes (it shouldn't need to).
  - **Live-fire validation is post-merge / user-owned** (this ticket's stage
    list ends at Final Review — no Deployment stage): Job 1 smoke on infra
    can run as soon as the files land on infra `main` (runner live); Job 2
    is gated on the dev instance repair (OQ-4).
- **Repo conventions the chunks must respect:** no hand-bumped versions
  (N/A — no chart change); the aislop gate will scan any changed
  `.github/workflows` file only on PR (`.forgejo/` files are not in its
  scope paths — `aislop ci --changes` operates on whatever the PR touches,
  so the new files WILL be scanned on the PR: keep comments terse /
  why-only, aislop floor applies); rulesync drift check (PR trigger) is
  unaffected (no generated surface touched); comment style per AGENTS.md
  ("why, not what").
- **Do not touch:** the seven `.github/workflows` files, `charts/forgejo*`,
  `services/*/prod/values.yaml` — all already in place and live-verified.
