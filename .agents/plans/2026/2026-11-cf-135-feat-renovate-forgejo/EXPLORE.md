# EXPLORE — cf-135 Move Renovate to git.spencerslab.com (card AD-135)

Written by `agent-explore` 2026-11-10 (workspace clock, all probes UTC). Read-only
grounding for the planner + research: where Renovate runs today, where the PR-count
limits live, the Forgejo/Actions/runner topology that would host it, the `ROLE`
gating precedent, the credentials surface, and the validation inventory.

Card ask (verbatim, from the launch brief): convert the Renovate runner from GitHub
to Forgejo, gate it for `ROLE=dev` because "I'll primarily test in dev", remove the
open-PR limits, and the user disables the GitHub side by hand.

**Two findings dominate everything below.**

1. There is **no Renovate workflow file in this repo, never was** — the GitHub side is
   an out-of-repo Renovate installation reading root `renovate.json` (§1). "Convert the
   action" is therefore *author* `.forgejo/workflows/<renovate>.yaml` from scratch, not
   port one.
2. The limits are **`renovate.json:9-10` only**, and deleting those two lines does NOT
   remove the limits: Renovate's built-in defaults are `prHourlyLimit 2` /
   `prConcurrentLimit 10`. "0 means no limit" — the removal must set zeros (§2).

---

## §1 Current GitHub Renovate surface (paths + lines)

**No workflow.** `.github/workflows/` holds exactly 7 files, none Renovate-related
(`aislop.yaml`, `docker-build.yaml`, `gpt-researcher-render-tests.yaml`,
`llama-swap-tools-tests.yaml`, `release.yaml`, `rulesync.yaml`, `vllm-render-tests.yaml`),
and `git log --all --diff-filter=A --name-only -- .github/workflows` lists the same set
plus the retired `build-image.yaml` — **no `renovate*` file was ever added** in any ref.
`grep -ri renovate .github/` → 0 hits (so no `# renovate:` annotations there either).

The GitHub side is an **out-of-repo Renovate installation** (app/org-config) pointed at
`github.com/OwnYourIO/SpencersLab` (remote `upstream`) with this repo's root
`renovate.json` as its config. Evidence, all read 2026-11-10:

| Fact | Evidence |
|---|---|
| 40 `renovate/*` head branches live on GitHub | `git ls-remote --heads upstream \| grep -c refs/heads/renovate/` → `40` |
| They are fresh, not leftovers | `upstream/renovate/alpine-3.x` → commit date `2026-11-09 15:53:31 +0000`; `…/docker.io-getmeili-meilisearch-1.x` → `2026-11-09 13:56:36` |
| Renovate PRs are still being merged on GitHub | `upstream/main` = `d55f597ce` "Update ghcr.io/home-operations/prowlarr Docker tag to v2.7.0.5723 (#842)", 2026-11-10 11:33:14 +0000 |
| Config is app-style (no platform/endpoint/hostRules/token keys at all) | `renovate.json:3-5` `extends: ["config:recommended"]`; no `platform`/`endpoint`/`hostRules` keys anywhere in the 301-line file |
| The live installation carries a GitHub token this repo cannot see | cf-95 `FRICTION.md:6`: "no `GITHUB_COM_TOKEN` in agent env … **ignored (accepted — live runner has a token)**" |
| The GitHub-only `release.yaml` publishes the Helm repo Renovate reads | `.github/workflows/release.yaml:3-8` (`push` main, `paths: charts/**`) → the registry `https://ownyourio.github.io/SpencersLab/` pinned as `# renovate: datasource=helm registryUrl=…` in `services/*/prod/templates/appset.yaml` (e.g. `services/infra/prod/templates/appset.yaml:21`) |
| Renovate is *also* design-time tooling in the lab (unrelated to the bot) | `services/dev/prod/values.yaml:294-312` + `services/gpu/prod/values.yaml:891-909`: ToolHive MCPServer `renovate`, image `ghcr.io/ownyourio/renovate-mcp:v84`; `containers/renovate-mcp/Dockerfile:32-34` pins `renovate-mcp@1.4.11` — the `global-renovate`/`dev-renovate` MCP servers of the AGENTS.md table |

Consequence for the plan: nothing to delete in-repo on the GitHub side; the *in-repo*
diff is a new `.forgejo/workflows/` file + `renovate.json` edits, and the GitHub
installation teardown is a user action ("I'll disable github's action by hand").

## §2 Limits to remove (exact locations)

- `renovate.json:9` → `"prHourlyLimit": 2,`
- `renovate.json:10` → `"prConcurrentLimit": 5,`

Those two lines are the **only** limit configuration in the repo:
`grep -i "limit" renovate.json` → lines 9, 10 (+ four `automergeSchedule` entries at
188/207/217/238, which are schedules, not PR counts);
`grep -rn "prHourlyLimit\|prConcurrentLimit"` over `*.sh *.ts *.yaml *.json` outside
`.agents/plans/` → only `renovate.json:9-10`. No workflow, test, chart, or script sets a
PR count. **No test asserts these keys**, so removing them reddens nothing.

Grounded semantics, from the vendored Renovate 44.181.5 options table
(`~/.npm/_npx/c1fd9d04902091d3/node_modules/renovate/dist/config/options/index.js`):

| Line | Key | Default | Description (verbatim) |
|---|---|---|---|
| 2431-2436 | `prHourlyLimit` | `2` | "Rate limit PRs to maximum x created per hour. **0 means no limit**." |
| 2438-2443 | `prConcurrentLimit` | `10` | "Limit to a maximum of x concurrent branches/PRs. **0 means no limit**." |
| 2445-2450 | `branchConcurrentLimit` | `null` | "…0 means no limit, `null` (default) **inherits value from `prConcurrentLimit`**." |

So the removal shape is `prHourlyLimit: 0` + `prConcurrentLimit: 0` (deleting the keys
re-introduces 2/10 silently). Related knob the planner may want to name explicitly:
`renovate.json:7` `"ignoreTests": true` — with no CI on Forgejo PRs (§6) this stays
load-bearing; and `semanticCommits: "disabled"` (line 11) plus `labels: ["dependencies"]`
(line 8) are platform-neutral and carry over.

## §3 Forgejo topology + runner reachability

### Instances and repos (both live, probed 2026-11-10)

| | dev instance | infra instance (canonical) |
|---|---|---|
| Host | `git.scifi.farm` | `git.spencerslab.com` (`forgejo.spencerslab.com` is an alias, banned for runner/LFS — cf-119 EXPLORE §2) |
| Version | `15.0.10+gitea-1.22.0` (`GET /api/v1/version` → 200) | same (→ 200) |
| Repo | `CuratedForest/SpencersLab`, API id **1**, created 2026-10-23 | same path, API id **3**, created 2026-11-07 |
| Repo flags (anonymous API) | `private:false`, `mirror:false`, `has_pull_requests:true`, `default_branch:main`, anonymous `permissions:{pull:true}` | identical |
| `main` HEAD (ls-remote) | `8885c173d` (remote `dev`, SSH :22222 — reachable) | `8885c173d` (remote `origin`, HTTPS — reachable) |
| GitHub for reference | — | `upstream/main` = `d55f597ce`; merge-base of the two mains = `e76c36e83` (2026-11-10 00:31) → **the two forges have diverged** |
| Worktree remotes | `git remote -v`: `origin`→`https://git.spencerslab.com/CuratedForest/SpencersLab.git`, `dev`→`ssh://git@git.scifi.farm:22222/…`, `upstream`→`git@github.com:OwnYourIO/SpencersLab.git`, `spencerslab-dev`→`https://git.scifi.farm/CuratedForest/SpencersLab-Dev.git` (a *different* repo, `ls-remote` returns empty) | |

`.forgejo/workflows/` **already exists**, with one file: `.forgejo/workflows/main-sync.yaml`
(cf-119, landed on main). So the "no `.forgejo/` ⇒ Forgejo falls back to `.github/workflows/`"
behavior noted in cf-119 EXPLORE §2 is already retired — GitHub's 7 files are invisible to
Forgejo and vice versa.

Second Forgejo workflow exists but **is not merged**: `.forgejo/workflows/containers-build.yaml`
lives only on branch `cf-6-feat-forgejo-container-builds` (`git merge-base --is-ancestor`
fails; `scripts/forgejo-container-detect.sh` is likewise absent from `scripts/` on main —
main has only board/pipeline machinery there). Its header is the best in-repo prose on
Forgejo Actions constraints (single-runner capacity, 30-min job ceiling, mirror inventory)
and its guard style (`startsWith(forgejo.server_url, …)`) is the *older* pattern cf-119
replaced with `ROLE`.

### Runners (live pods + logs, readonly MCP, 2026-11-10 ~15:5x UTC)

| Release | Cluster/pod | Dials | Live state | Job evidence |
|---|---|---|---|---|
| `gpu-forgejo-runner-gpu` | gpu, `default/gpu-forgejo-runner-gpu-0` | `https://git.spencerslab.com` (`services/gpu/prod/values.yaml:271-273`; `charts:` alias 119-122) | Running 2/2, age 4d18h, 8 restarts | **Executing**: log lines `task 59…64 repo is CuratedForest/SpencersLab https://data.forgejo.org https://git.spencerslab.com` + `Cleaning up network for job push-gh` / `job push-dev`, 15:28:10–15:38:17Z |
| `dev-forgejo-runner-dev` | dev, `default/dev-forgejo-runner-dev-0` | `http://dev-forgejo-http:3000` in-cluster (`services/dev/prod/values.yaml:176-178`; alias 114-117) | Running 2/2, age 24h, 0 restarts | **Takes no tasks**: whole log since the 2026-11-09 15:16Z start is 4 lines — `runner: Dev Runner, with version: v13.2.0, with labels: [ubuntu-latest ubuntu-24.04 ubuntu-22.04 docker node22], declared successfully`, `[poller] launched`, then `failed to fetch task: deadline exceeded; increase fetch_timeout if this error is persistent` (15:44:16Z). No `task` line ever. |

Servers: `charts/forgejo-runner/values.yaml` (both releases are docker-backend, hence
2/2 pods = runner + privileged dind sidecar); labels at `:107-112`
(`ubuntu-latest`/`ubuntu-24.04`/`ubuntu-22.04`/`docker`/`node22`, all →
`ghcr.io/catthehacker/ubuntu:act-24.04`, `node22` is a slot name, not a Node guarantee);
`capacity: 1`, `timeout: 30m`, `shutdown_timeout: 5m` at
`charts/forgejo-runner/templates/secret-runner.yaml:88-93`; registration is scope-agnostic
(repo/org/instance) and label-based per `values.yaml:45-51`. The act-image tags are
**rolling and no Renovate manager reads them** — manual bumps
(`secret-runner.yaml:121-136`, note at `:128`).

Forgejo-side run history (public `GET …/actions/runs`, 2026-11-10):

- infra: 31 runs, all `main-sync.yaml` — `success` on ids 25,27,28,29,30,31 (Nov 9 16:39 →
  Nov 10 00:32); `failure` on the three newest: 33 (15:28:17), 34 (15:37:12), 35 (15:38:10).
  Successful runs took 15-21 s; the failures ~7-8 s.
- dev: 14 runs, all `main-sync.yaml` — 13 `cancelled` (each killed by the next push) and
  id 16 `waiting` (`created 2026-11-10T15:38:18Z`, `started 1970-01-01T00:00:00Z`,
  `need_approval:false`) — i.e. **no dev run has ever started or completed**.
  The `jobs` subresource is not public (`GET …/actions/runs/35/jobs` → 404), so per-job
  reasons are not readable anonymously.

Reachability conclusions (grounded vs unproven):

- Infra runner egress to `github.com` and `git.scifi.farm` over HTTPS: **proven** — those
  are `main-sync.yaml:37-43` / `:58-64` pushes executed by real tasks (and infra `main`
  equals dev `main` sha, so `push-dev` lands).
- Job-container egress to what Renovate actually needs — `ghcr.io`, `docker.io`, Helm
  indexes (`ownyourio.github.io`, `*.github.io` chart repos, `code.forgejo.org` OCI),
  `github.com` API for the `github-releases`/`github-tags` legs, `grafana.com/api`,
  `npm`/`node-version` registries, plus `git ls-remote` for the `git-refs` legs — is
  **unproven**. The manager block is `renovate.json:12-167` — 13 regex customManagers
  (object ranges: image-lines 13-24, k3s `github-releases` 25-38,
  system-upgrade-controller `git-tags` 39-51, chart-field helm 52-62, key-as-chart helm
  63-73, Traefik plugins `github-releases` 74-85, grafana.com dashboards 86-97,
  baseChartVersion helm 98-108, Dockerfile git pins `github-tags|github-releases` 109-118,
  chart changelog/sourceUrl 119-130, containers ARGs
  `node-version|golang-version|forgejo-releases|npm` 131-140, git-refs (branch-aware)
  141-153, git-refs (default-`main`) 154-166) + 1 custom datasource (168-176).
- The **dev** runner (the one `ROLE=dev` would use) has run **zero** jobs, so *everything*
  about dev-instance execution and egress is unproven, and today it does not even pick
  tasks up.
- Actions server config: **nothing in this repo configures Actions** — `grep -ri actions
  charts/forgejo/ custom-values/infra/prod-values.yaml custom-values/dev/prod-values.yaml`
  → 0 hits, so both instances run on server defaults (cf-97 RESEARCH: "Actions enabled by
  default" on 15.0.10, and both instances demonstrably create runs, §3 history) with no
  in-repo mirror/`DEFAULT_ACTIONS_URL` override to point somewhere friendlier.
- Actions resolution path: the runner's task line names `https://data.forgejo.org` (Forgejo's
  official actions mirror) as the actions source. Probes 2026-11-10:
  `data.forgejo.org/renovatebot/github-action` → redirects to `code.forgejo.org/…` →
  **HTTP 404** (the Renovate GitHub Action is *not* on the mirror);
  `data.forgejo.org/actions/checkout/` → HTTP 403 (rate/auth-shaped, but `actions/checkout@v6`
  demonstrably works — main-sync's successful runs use it, `main-sync.yaml:28`).
  cf-6's workflow header states the same: "Actions resolve through the instance's mirror,
  whose inventory beyond actions/checkout … is unproven."
  ⇒ a Renovate job must not rely on `uses: renovatebot/github-action`; run it as a plain
  `run:` step (`npx renovate@<pin>`, act images ship Node) or a job `container:` from
  `ghcr.io/renovatebot/renovate` (anonymous `GET /v2/renovatebot/renovate/tags/list` → 200).
- Renovate's Forgejo platform exists in the pinned line: the npx-cached installs ship
  `dist/modules/platform/forgejo/` at **44.181.5, 44.115.13, 44.65.5 and 41.173.1** (absent
  at 37.440.7). `forgejo/index.js:49-55` → `id: "forgejo"`,
  `defaultEndpoint: "https://code.forgejo.org/"` (so `--endpoint` must be set to the
  instance), shares the gitea utils (`gitea/utils.js:56` `API_PATH = "/api/v1"`;
  `trimTrailingApiPath`), `checkNativeAutomerge` needs server ≥ 10.0.0 (15.0.10 fine), and
  `usableRepo()` refuses `mirror:true`, missing pull **or** push permission, or
  `has_pull_requests:false`. `constants/platforms.js:53-64` gives the forgejo datasource
  family (`forgejo`, `forgejo-releases`, `forgejo-tags`, `forgejo-changelog`,
  `knownHosts: codeberg.org, codefloe.com`) — the repo already uses `forgejo-releases`
  in `renovate.json:131-140` (the containers/ ARG-pin leg's datasource alternation); the
   family's `apiBaseUrl` appends `api/v1/` to the configured endpoint, so keep its
   trailing slash.

Flow gotchas the plan must not trip on:

- GitHub↔infra `main` divergence (§3 table) means `main-sync`'s `push-gh` currently fails
  by design (plain non-force push, `main-sync.yaml:41-43`; the failure runs 33-35 line up
  with it). Renovate PRs merged on a Forgejo instance therefore do **not** reach GitHub
  until that heals.
- ArgoCD's git source is **instance-side**: every appset reads
  `{{ index .metadata.annotations "services.repo" }}` (e.g.
  `services/infra/prod/templates/appset.yaml:78-85`, `charts/base/templates/appset-charts.yaml:54`)
  and those cluster-annotation secrets are not in this repo — so *which forge ArgoCD pulls*
  is unverifiable from the worktree (§7 OQ-3). It decides where a Renovate PR must merge to
  actually deploy.
- `release.yaml` (chart publishing → the Helm registry Renovate consumes) and
  `docker-build.yaml` must stay on GitHub until cf-6 ships the Forgejo build path; the
  three render-test workflows and `rulesync.yaml` are GitHub `pull_request` gates that a
  Forgejo-side Renovate PR will **not** run.

## §4 ROLE=dev gating precedent

The repo convention is a job-level guard on the instance-side repo variable `ROLE`:

- `.forgejo/workflows/main-sync.yaml:25` and `:46` → `if: vars.ROLE == 'prod'`, with the
  header comment `:1-6` explaining the ping-pong breaker and the fail-safe ("An unset ROLE
  renders empty and fires nothing too"), plus a `diag` step echoing the value
  (`:35`, `:56`) as first-fire evidence.
- Values of record (owner-set, never committed) — cf-119 plan
  `.agents/plans/2026/2026-11-cf-119-feat-forgejo-push-main/2026-11-06-cf-119-feat-forgejo-push-main.md:178-186`:
  `ROLE=prod` on **infra** repo `CuratedForest/SpencersLab`; `ROLE=dev` on **dev** repo;
  "Only the infra repo needs the `PUSH_*` keys … the dev repo needs only `ROLE=dev`."
  Platform provenance for the pattern is cited there at `:93` (Forgejo uses `vars.ROLE` on
  mirrors to select workflows) and the `vars` context legality on job-level `if:` at `:90`.
- Contract teeth: `tests/services/forgejo-main-sync.sh:74` (`GUARD = "vars.ROLE == 'prod'"`),
  `:92` forbids the literal `vars.ROLE == 'dev'` **in that file** ("the dev stage must fire
  nothing"), `:94` forbids `forgejo.server_url` there. A new Renovate workflow file guarding
  on `dev` is therefore consistent; editing `main-sync.yaml` to add a dev guard is not.
- Alternative guard precedent (retired for main-sync, still live on the cf-6 branch):
  `if: startsWith(forgejo.server_url, 'https://git.spencerslab.com')`
  (`cf-6-feat-forgejo-container-builds:.forgejo/workflows/containers-build.yaml`, jobs
  `detect-changes` / `build-and-push`).

**Semantic conflict to rule on before planning:** the card title names
`git.spencerslab.com` (= infra, `ROLE=prod`) while the gate asks for `ROLE=dev` (=
`git.scifi.farm`). Under the grounded convention, `vars.ROLE == 'dev'` pins the run to the
**dev instance**, whose runner currently starts no jobs at all (§3). Recorded as OQ-1/OQ-2.

## §5 Secrets / variables surface (Forgejo)

Existing Actions-side config of record (all instance-side, human-minted — cf-119 plan
`:178-186`, "never committed to this repo"):

| Kind | Key | Value | Where |
|---|---|---|---|
| variable | `ROLE` | `prod` / `dev` | infra / dev repo |
| variable | `PUSH_URL_GH`, `PUSH_URL_DEV` | destination URLs | infra repo |
| secret | `PUSH_TOKEN_GH` (fine-grained PAT, Contents R/W + Workflows), `PUSH_TOKEN_DEV` | push creds | infra repo |

Dev repo today needs only `ROLE=dev` — **no Renovate-capable token exists there yet.**

What a Forgejo-run Renovate needs, grounded:

- Platform/token: `--platform=forgejo --endpoint=https://<instance>/` (`/api/v1` appended
  internally, §3) and a token whose repo permissions satisfy `usableRepo()` (`pull` AND
  `push` true, PRs enabled). Anonymous API reads show `permissions:{pull:true}` only — so
  a dedicated bot/PAT (Forgejo token with `Repositories: Write`, or the run's own token if
  its scope suffices) is required; token *creation* is instance-UI work → user-owned leg.
- The automatic per-run token (`secrets.FORGEJO_TOKEN` / `GITHUB_TOKEN` alias) is
  same-repo-scoped, has write to that repo, and pushes made with it do not re-trigger
  workflows (cf-119 EXPLORE §2, docs-grounded) — attractive for Renovate, but its ability
  to open PRs on 15.0.10 is **unverified**, and `main-sync.yaml`'s suite deliberately bans
  referencing it (`tests/services/forgejo-main-sync.sh:152-156`).
- Registry credentials Renovate currently consumes invisibly from the GitHub install: a
  `github.com` token (cf-95 FRICTION: "live runner has a token" for `GITHUB_COM_TOKEN` —
  the repo's `github-releases`/`github-tags`/`github`-URL legs at `renovate.json:26-49`,
  `96-116`, `153-176` will rate-limit without one); GHCR anonymous pull is fine (probed
  200). Env-side hooks: `detectHostRulesFromEnv` exists as a global option
  (`options/index.js:127`), and `renovate.json` carries no `hostRules` at all, so the
  workflow's `env:` (`RENOVATE_*` / `GITHUB_COM_TOKEN`) is the injection point.
- Lab credential inventory that *looks* reusable but is not documented for this:
  Bitwarden item `forgejo-token` — "Forgejo access token for git.scifi.farm", consumed by
  dev MCP ExternalSecrets (`services/dev/prod/values.yaml:64-65`, UUID noted in cf-119
  EXPLORE §5:187); `charts/forgejo-runner/values.yaml:84-89` warns it must never back a
  runner registration and never says it has PR-writing scope. `github-mcp`
  (`services/dev/prod/values.yaml:69`, `services/gpu/prod/values.yaml:39`) is the GitHub PAT
  that backs the *renovate MCP server's* clone initContainer — a plausible source of a
  `GITHUB_COM_TOKEN` value, not a Forgejo token. The runner identities themselves are
  Bitwarden login items per release (`charts/forgejo-runner/values.yaml:77-90`,
  `templates/secret-runner.yaml:144-172`) and stay untouched by this ticket.

- The only *other* Forgejo credential wired in this repo is coderd's OAuth app against
  each forge (`services/gpu/prod/templates/secrets-coder.yaml:31-40` + `:108-112` for the
  canonical `git.spencerslab.com`, `charts/coder/templates/secret-coder.yaml:44-53` +
  `:124` for the dev twin, item `coder-external-auth` = username client-id / password
  client-secret). It is a device-flow git-auth credential for Coder workspaces, not an
  API token: nothing in the repo today holds a Forgejo token with PR-writing scope
  (OQ-5).

## §6 Validation command inventory

Nothing here needs a chart change, so `helm lint/template` are only for the "did I touch a
chart?" check; the real gates are static workflow contracts and a local Renovate dry-run.

Tooling present in this workspace (verified 2026-11-10): `helm v3.16.4+g7877b45` at
`~/.local/bin/helm` (**export `PATH=$HOME/.local/bin:$PATH` first** — AGENTS.md agent-shell
recipe), `python3` with `pyyaml 6.0.3`, `node v26.5.0` default + nvm `v24.22.0`
(the Renovate CLI logs an `Unsupported node environment` ERROR on node 26 — cf-95 D9),
`curl`, and Renovate in the npx cache (44.181.5 / 44.115.13 / 44.65.5 / 41.173.1 / 37.440.7).

Commands, with their source of record:

```bash
# Renovate config schema gate (cf-95 plan Commands §1)
export PATH=/home/coder/.nvm/versions/node/v24.22.0/bin:$HOME/.local/bin:$PATH
npx -y -p renovate@44.181.5 renovate-config-validator renovate.json

# Offline dry-run gate (cf-95 plan Commands §3 + FRICTION): no positional repo arg,
# exit 1 == a logged ERROR; grep the log, not level codes
LOG_LEVEL=debug npx -y renovate@44.181.5 --platform=local --dry-run=lookup > /tmp/opencode/renovate-dry.log 2>&1
grep -c '❌' /tmp/opencode/renovate-dry.log
grep -E "ERROR|failed to look up" /tmp/opencode/renovate-dry.log

# Existing suites touching this surface
bash tests/renovate/dockerfile-pins.sh            # 461 L, RENOVATE_CONFIG override convention
bash tests/renovate/chart-yaml-legs.sh            # 274 L, datasource enumeration gate at :249
bash tests/renovate/kubernetes-mcp-version-floor.sh
bash tests/renovate/system-upgrade-controller.sh
bash tests/services/forgejo-main-sync.sh          # 236 L — THE model for a workflow contract suite

# Chart/render sanity only if the plan touches charts/
helm lint charts/<name> && helm template charts/<name>
```

House shape of a static contract suite (`tests/services/forgejo-main-sync.sh`): bash
`set -euo pipefail`, `cd "$(git rev-parse --show-toplevel)"`, `fail()`/`ok()` helpers with
an `ok:`-per-check and one `PASS: <name> checks (%d ok)` line, inline `python3` heredocs
parsing the YAML, and — the non-obvious part — `doc.get(True) or doc.get('on')` because
YAML 1.1 resolves bare `on:` to boolean `True` (`:13-15`, `:48`). Legs worth cloning for a
Renovate workflow: t1 parse, t2 trigger shape, t3 job set + `ROLE` guard, t5
vars/secrets referenced exactly once and only under their own job (+ reserved-prefix ban),
t6 every `run:` starts `set -euo pipefail`, t7 `runs-on` ∈ the five advertised labels
(`:189`). Precedent for a *network-dependent* leg that must skip rather than fail:
`tests/services/dev-forgejo-runner.sh:592-605` runs `npx --yes renovate@44.115.13
--platform=local --dry-run=true` with `timeout 300` and `skip`s on timeout/absence.

Also relevant: `tests/renovate/chart-yaml-legs.sh:249` hardcodes the supported Dockerfile
datasource tokens `['github-tags','github-releases','git-refs','node-version',
'golang-version','forgejo-releases','npm']` — if the plan adds a `forgejo`-family or new
datasource annotation anywhere in `containers/`, that enumeration gate needs the same
commit. No test currently reads `.github/workflows/*` for Renovate purposes;
`tests/opencode/aislop-pin-parity.test.ts` binds the `aislop` pin, so don't drift
`aislop.yaml:29` (the pin; its `:9` names that parity test) while editing workflow surfaces.

## §7 Open questions worth asking the planner (recorded, not asked)

- **OQ-1 — Which instance actually gets Renovate?** `ROLE=dev` (per the card) means the
  dev instance `git.scifi.farm`; the card title says `git.spencerslab.com` (= `ROLE=prod`).
  Under §4's grounded convention the two are mutually exclusive for one job. Needs a user
  ruling (e.g. gate `!= 'prod'`, or ship gated `dev` with the prod flip as a named
  follow-up). *Needs research: no — user decision.*
- **OQ-2 — dev-instance Actions do not execute today** (§3): zero started runs in 14, newest
  `waiting` since 15:38Z, runner log ends at a `failed to fetch task: deadline exceeded`
  warning. If the ticket's whole premise is "test in dev", dev execution is a prerequisite
  (repair = a separate bug ticket?), and any dev-side validation in this run can only be
  static. *Needs research: no — operational/user + first-fire evidence.*
- **OQ-3 — Where must a Renovate PR merge for the change to deploy?** ArgoCD's git endpoint
  is the instance-side `services.repo` cluster annotation (§3), and `main` is today
  published infra→GitHub by a workflow whose `push-gh` leg is currently failing. The
  deploy path for Forgejo-origin Renovate PRs is unproven. *Needs research: no — user/
  instance check.*
- **OQ-4 — Trigger + runtime shape**: is a scheduled run (`on: schedule:`) available and
  cron-configurable on Forgejo 15.0.10, what timezone semantics apply, and does one Renovate
  pass over this repo fit the runner's `timeout: 30m` at `capacity: 1` (cf-95 measured ~2
  min for a `dry-run=lookup` with network; a full PR-creating run is heavier, and it
  serializes against main-sync jobs on the same pod)? *Needs research: yes (Forgejo docs +
  renovate runtime expectation).*
- **OQ-5 — Token identity and scopes**: dedicated bot user + `Repositories: Write` PAT, or
  the automatic Actions token (§5)? Can an Actions token open PRs on 15.0.10? *Needs
  research: yes (Forgejo 15 Actions-token scopes) + user for the minting.*
- **OQ-6 — Non-GitHub credentials in the job env**: without a `github.com` token, most of
  this repo's 10 custom managers (`github-releases`/`github-tags`/`git-refs` legs) degrade
  to rate-limit noise — cf-95's allowlist documents the symptom but the GitHub install
  hides the cure (§1). Which secret name/shape does the plan standardize on?
  *Needs research: partially (renovate hostRules-from-env specifics).*
- **OQ-7 — GitHub leftovers after the move**: 40 `renovate/*` branches and any open PRs on
  `upstream`; disabling the app does not clean them, and the merged-PR flow (user merges on
  GitHub today, cf-119 OQ-1 territory) is what the move implicitly re-parents. Also confirm
  the GitHub files that must stay: `release.yaml` (publishes the Helm repo Renovate reads),
  `docker-build.yaml` (until cf-6 lands the Forgejo equivalent), `aislop.yaml`,
  `rulesync.yaml`, three render-test suites. *Needs research: no.*
- **OQ-8 — Version pin and self-update posture for the new runner**: which Renovate to run
  (`ghcr.io/renovatebot/renovate:<pin>` vs `npx renovate@<pin>`), and who bumps it — the
  GitHub app self-updates out-of-band today, and the repo's harness pins (44.181.5 in
  cf-95, 44.115.13 in `dev-forgejo-runner.sh:596`) show a hand-pinned habit with no
  self-update config anywhere in `renovate.json`. Note the runner's own act images are
  documented as *not* Renovate-trackable (§3). *Needs research: yes (image/entrypoint
  recommendation for Forgejo-hosted Renovate).*
- **OQ-9 — `ignoreTests: true` (`renovate.json:7`) with no Forgejo CI**: once Renovate opens
  PRs on an instance whose PRs run no gates (§6), does the user want merge-blocking handled
  by automerge schedules (four `automergeSchedule` rules already) or by a Forgejo-side test
  workflow? *Needs research: no — product decision, planner's call.*

## §8 id / source map (what I actually used)

Board: card **AD-135** (cf-135) — consumed from the launch brief; I did **not** touch the
board (no claim, no `dev-boards` call) — that is the coordinator's surface.

Git (read-only, worktree `…/cf-135-feat-renovate-forgejo`, branch `cf-135-feat-renovate-forgejo`):
HEAD `931df5eec`; `origin/main` = `8885c173d` (= dev `main`); `upstream/main` = `d55f597ce`;
merge-base `e76c36e83`.

Kubernetes (readonly MCP, namespace `default`, 2026-11-10):
- `readonly-infra-kubernetes` → `infra-forgejo-6b95547f88-psps8` Running 1/1 (24h),
  `pg-forgejo-1` Running 1/1.
- `readonly-gpu-kubernetes` → `gpu-forgejo-runner-gpu-0` Running 2/2 (4d18h, 8 restarts).
- `readonly-dev-kubernetes` → `dev-forgejo-c4ccf6fcb-2dbbk` Running 1/1 (23h),
  `dev-forgejo-runner-dev-0` Running 2/2 (24h, 0 restarts), `pg-forgejo-1` Running 1/1.
  `pods_log` read for both runner pods (tails 40/200; dev output identical at both bounds).

HTTP GETs (read-only, no auth, 2026-11-10): `https://git.spencerslab.com/api/v1/version`
(200, `15.0.10+gitea-1.22.0`), `https://git.scifi.farm/api/v1/version` (200, same),
`…/api/v1/repos/CuratedForest/SpencersLab` (200 both; infra id=3, dev id=1),
`…/actions/runs` (200 both; 31 infra / 14 dev runs),
`…/actions/runs/{31,35}/jobs` (404, not public),
`https://data.forgejo.org/renovatebot/github-action` (404 via code.forgejo.org),
`https://data.forgejo.org/actions/checkout/` (403),
`https://ghcr.io/v2/renovatebot/renovate/tags/list` (200 with anonymous pull token).

Vendored Renovate read offline (no network, no install):
`/home/coder/.npm/_npx/c1fd9d04902091d3/node_modules/renovate` (44.181.5) —
`dist/config/options/index.js:1176-1196` (`platform`/`endpoint`/`token` globals),
`:2431-2450` (the three limit keys), `:127` (`detectHostRulesFromEnv`);
`dist/modules/platform/forgejo/index.js:39-55` (`id`, `defaultEndpoint`,
`checkNativeAutomerge` ≥10.0.0); `dist/modules/platform/gitea/utils.js:56`
(`API_PATH="/api/v1"`), `usableRepo()` in the same file's map;
`dist/constants/platforms.js:2-14` (`PLATFORM_HOST_TYPES` incl. `forgejo`), `:53-64`
(forgejo datasource family + `apiBaseUrl`). Older caches inspected for the version boundary:
`59c0475bfd22776c` (44.65.5), `c2637f3b1963bb95` (44.115.13), `3e96708c037817f7`
(41.173.1, has forgejo), `05eeecd92f4e18e0` (37.440.7, does not).

Repo docs used as evidence: `renovate.json`, `.forgejo/workflows/main-sync.yaml`,
`charts/forgejo-runner/{values.yaml,templates/secret-runner.yaml}`,
`charts/forgejo/{values.yaml,Chart.yaml}`, `services/{dev,gpu,infra}/prod/values.yaml`,
`services/*/prod/templates/appset.yaml`, `tests/renovate/*`,
`tests/services/{forgejo-main-sync,dev-forgejo-runner,gpu-forgejo-runner,infra-forgejo}.sh`,
`.agents/plans/2026/2026-11-cf-95-bug-fix-renovate/{plan,DECISIONS,FRICTION}.md`,
`.agents/plans/2026/2026-11-cf-119-feat-forgejo-push-main/{EXPLORE.md,plan,DECISIONS}.md`,
`.agents/plans/2026/2026-11-cf-97-bug-forgejo-runner/*`,
`.agents/plans/2026/2026-11-cf-6-feat-forgejo-container-builds/DECISIONS.md`,
branch `cf-6-feat-forgejo-container-builds:.forgejo/workflows/containers-build.yaml`.
