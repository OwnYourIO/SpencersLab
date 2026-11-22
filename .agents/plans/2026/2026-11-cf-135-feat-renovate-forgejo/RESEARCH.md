# RESEARCH — cf-135 Move Renovate to Forgejo (pre-research stage)

Written by `agent-research` 2026-11-10 (STORM discipline: every external claim carries a
numbered source from §8, read/accessed 2026-11-10; claims from the vendored offline
Renovate 44.181.5 dist and the repo itself carry exact `path:line` refs in §0). Scope:
the four asks flagged by EXPLORE §7 (OQ-4, OQ-5, OQ-6, OQ-8) for the card ask
(convert the Renovate runner to Forgejo, gated `ROLE=dev`, open-PR limits removed,
GitHub side disabled by hand). Forgejo = 15.0.10 on both lab instances; Renovate pin of
record = 44.181.5.

**Bottom line:** every one of the four asks is solvable with a single
`.forgejo/workflows/renovate.yaml`: `on: schedule` is supported on v15.0.x (POSIX cron,
default-branch semantics); the job must carry its own token because Renovate's `forgejo`
platform hard-requires one (the automatic `FORGEJO_TOKEN` is repo-scoped and *can* write
on public repos like ours, with documented caveats); every github-facing datasource leg
needs `RENOVATE_GITHUB_COM_TOKEN` or the run rate-limits into noise; and the clean
runtime shape is a `container:` job on `ghcr.io/renovatebot/renovate:<semver-tag>` —
the act image's Node is too old for 44.x's engines, so the `npx` alternative is
second-class. The limits removal stays a `renovate.json` edit (`prHourlyLimit: 0` /
`prConcurrentLimit: 0` — EXPLORE §2 holds; the card's "remove the limits" means set
zeros, and 44.181.5's own option defaults (2/10) make that the only non-silent shape).

## §0 Fact base (offline dist + repo evidence used below)

All dist paths are under
`/home/coder/.npm/_npx/c1fd9d04902091d3/node_modules/renovate` (44.181.5, verified via
its `package.json`), read offline 2026-11-10:

| # | Fact | Where |
|---|---|---|
| F1 | `forgejo` platform is a thin `createPlatform` wrapper over the shared gitea impl; `id: "forgejo"`, `defaultEndpoint: "https://code.forgejo.org/"` → **`RENOVATE_ENDPOINT` must be set** to the lab instance | `dist/modules/platform/forgejo/index.js:38,50-55` |
| F2 | Platform init **throws without a token**: `if (!token) throw new Error("Init: You must configure a forgejo personal access token")` | `dist/modules/platform/gitea/index.js:122-123` (shared by forgejo via F1) |
| F3 | Endpoint normalization: `trimTrailingApiPath(endpoint)` tolerates a trailing `/api/v1`; `API_PATH = "/api/v1"` is appended internally; `RENOVATE_CONFIG_FILE`, `RENOVATE_CONFIG` (inline JSON) supported | `dist/modules/platform/gitea/utils.js:13,56`; `dist/modules/platform/gitea/index.js:124-128`; `dist/workers/global/config/parse/file.js:7-14`, `env.js:106-118` |
| F4 | Clone/push git auth: `getRepoUrl` builds `https://<token>:x-oauth-basic@<host>/<repo>.git` from the API `clone_url` (default) or from the configured `endpoint` when `gitUrl: endpoint`; **the platform token is used for git too** — `gitBaseURL` does not exist in this code path | `dist/modules/platform/gitea/utils.js:16-42`; `dist/config/options/index.js:3597-3615` (`gitUrl` allowedValues `default`/`ssh`/`endpoint`, `supportedPlatforms` includes `forgejo`) |
| F5 | `RENOVATE_*` env → options via `RENOVATE_${CAMEL→SNAKE_UPPER}` (`getEnvName`), so `RENOVATE_PLATFORM`, `RENOVATE_ENDPOINT`, `RENOVATE_TOKEN`, `RENOVATE_REPOSITORIES`, `RENOVATE_CONFIG_FILE` are the canonical names; `LOG_LEVEL` is a logger env, not an option | `dist/config/options/env.js:4-9`; `dist/workers/global/config/parse/env.js:106-160` |
| F6 | **`GITHUB_COM_TOKEN` (or `RENOVATE_GITHUB_COM_TOKEN`) becomes a global hostRule `hostType=github matchHost=github.com token=…`** — special-cased in env parsing, no `detectHostRulesFromEnv` needed; the generic env→hostRule parser is gated on `detectHostRulesFromEnv` (default false) | `dist/workers/global/config/parse/env.js:164-171`; `dist/workers/global/config/parse/host-rules-from-env.js:28-39`; `dist/config/options/index.js:120-127` |
| F7 | `github.com` rate-limit failure shape: `Rate limit exceeded for api.github.com … Please set a GITHUB_COM_TOKEN` (once-warn pointing at docs anchor `getting-started/running/#githubcom-token-for-changelogs-and-tools`) | `dist/util/http/github.js:79` |
| F8 | **`REQUIRE_TOKEN` does not exist anywhere in 44.181.5** (case-insensitive grep over `dist/` = 0 hits; the docs' admin knobs for this are `requireConfig` and the platform's own throw, F2) | grep of `dist/` 2026-11-10; `dist/config/options/index.js` (`requireConfig` at [10]) |
| F9 | Node engine: `engines.node = "^24.11.0"` (all three cached 44.x installs: 44.65.5, 44.115.13, 44.181.5); mismatch logs a **non-fatal ERROR** `"Unsupported node environment detected."` at startup — cf-95 observed node 26 producing exactly this plus a red exit signal in its harness | `package.json` of each cache; `dist/workers/global/index.js:67-77`; cf-95 `FRICTION.md:8` |
| F10 | The `github-actions` manager's default patterns **match `.forgejo/workflows/*.ya?ml`**, and it extracts `runs-on:` labels as `github-runner` deps; bare `uses:` pins resolve against **github.com** tag lists regardless of platform (endpoint rewrite only applies when `platform: github` + GHES endpoint) | `dist/modules/manager/github-actions/index.js:22`; `extract.js:128-147` (`runnerVersionRegex`, `depType: "github-runner"`); `extract.js:22-38` (`detectCustomGitHubRegistryUrlsForActions`) |
| F11 | The pinned datasource's own runner release table ships `ubuntu-26.04` (released 2026-09-17) as "newer than" `ubuntu-24.04` — i.e. **Renovate will PR-bump `runs-on: ubuntu-24.04` → `ubuntu-26.04`**, a label the lab runners do not advertise | `dist/modules/datasource/github-runners/index.js:18-30`; labels per EXPLORE §3 / `charts/forgejo-runner/values.yaml:107-112` |
| F12 | Repo side: limits live only at `renovate.json:9-10`; built-in defaults `prHourlyLimit 2` / `prConcurrentLimit 10` / `branchConcurrentLimit null`→inherits; `0` = no limit | EXPLORE §2 + `dist/config/options/index.js:2431-2450` |
| F13 | Live runners are **docker-backend + DinD sidecar** (both), `capacity: 1`, `timeout: 30m`, `shutdown_timeout: 5m`; host backend is a chart capability (`backend: host`, labels `cf-host`, image `ghcr.io/ownyourio/forgejo-host-runner`) with **no deployed release** — `values.yaml:107` defaults `backend: docker`, no slice overrides it (`services/gpu/prod/values.yaml:271-273`, `services/dev/prod/values.yaml:176-178` carry only `runner.url`) | EXPLORE §3 (live pods 2/2); `charts/forgejo-runner/values.yaml:15-52,107-112`; `charts/forgejo-runner/templates/secret-runner.yaml:88-93,18-50,96-119` |

**Correction to the launch brief:** it parenthesized "the gpu/infra runner runs in host
mode per EXPLORE/STATE history". That is superseded — EXPLORE §3 verified live pods
(docker+dind), F13 confirms no `backend` override ships, and cf-11's
`FRICTION.md:21` (2026-11-06) records the dev host-mode release being *reverted* to
main's docker defaults. Everything in §4 assumes docker/DinD runners, where container
jobs are native.

## §1 OQ-4 — Scheduled workflows on Forgejo 15.0.10 + sizing

**Verdict: `on: schedule:` is supported and documented on v15.0.x, with GitHub-familiar
semantics; a daily schedule is the right frequency; one Renovate pass fits the 30-minute
runner ceiling with margin, on the order of a lookup-run (~2 min) plus per-branch git
work — the honest caveat is that nothing on dev has executed yet.**

Version-specific answers, all from the **v15.0-tagged** docs (not `latest`, which is now
v17):

- **Existence + semantics** [1]: "When a workflow with a `schedule` event is present in
  the **default branch**, Forgejo will add a task to run it at the designated time. The
  scheduled workflows on other branches or pull requests are ignored." → the workflow
  file must be merged to `main` to schedule; branch testing needs `workflow_dispatch`
  (also documented [1]).
- **Syntax**: POSIX cron 5 fields (crontab(5)) — minute granularity is the floor; no
  GitHub-only extras documented. Quote the string in YAML (practitioner gist notes `*`
  is YAML-special [15]).
- **Timezone**: **UTC by default**; a per-entry `timezone:` key takes an IANA zone id
  (e.g. `America/Denver`, matching `renovate.json:6`); DST caveat documented: runs
  scheduled into the spring-forward hour are **skipped**, fall-back hour **runs twice**
  [1]. Recommendation: schedule in UTC at an off-hours minute with non-round offset.
- **Activation caveat**: changing the default branch unregisters schedules until a new
  commit lands (known bug, fixed upstream [16]; whether 15.0.10 carries the fix is
  unverified — irrelevant operationally since `main` is stable, but note for the planner).
- **Timeouts** (three layers, lowest wins):
  1. job-level `timeout-minutes` — optional [1];
  2. **runner config `timeout` — the lab pins 30m** (F13); the runner default is 3h and
     the docs comment notes "the Forgejo instance also has a timeout (3h by default) for
     the job" [6][7];
  3. instance-side defaults — nothing configured repo-side (EXPLORE §3), so 3h class
     defaults stand.
  → effective ceiling on the lab runners = **30 minutes** without any workflow change.
- **Sizing**: no published per-run timing exists for self-hosted Renovate of this repo's
  shape, so this is a reasoned estimate, flagged as such. Inputs: cf-95 measured the
  full-config `dry-run=lookup` over this repo (all 13 custom managers, network live) at
  **~2 minutes** [repo: cf-95 plan `:33`]; a real run adds the branch layer (one commit
  + one push per updated dep into the same forge, LAN-fast, token-auth HTTPS per F4) on
  ~40 trackable deps — and the first post-move run is the worst case (fresh platform,
  `prHourlyLimit: 0` → potentially dozens of branches in one pass). Lookup dominates;
  pushes are seconds-scale. **Estimated first pass ~10–20 min, steady-state passes well
  under 5 min — fits 30m** *provided* the GitHub token of §3 is set (anonymous
  rate-limit stalls, §3, are the realistic path to a bloated run). Serialization risk:
  `capacity: 1` [F13] means a 20-minute Renovate job delays a queued `main-sync` job by
  the same order — acceptable (main-sync runs 15-21 s jobs; a delayed sync is
  non-destructive) but name it (risk R4).
- **Dev-runner prerequisite (unchanged from OQ-2)**: the dev instance has started zero
  jobs and its runner log ends on `failed to fetch task: deadline exceeded` [repo:
  EXPLORE §3]. A schedule gated `vars.ROLE == 'dev'` will **fire on the server but queue
  forever** until that runner takes tasks; live validation of this ticket can only run on
  infra (gate flip) or after a dev-runner repair (separate work). The plan must split
  static validation (now) from first-fire evidence (post prerequisite).

## §2 OQ-5 — Which token can open PRs on Forgejo, and how Renovate uses it

**Verdict: Renovate hard-requires a token (F2). Two viable identities: (b) a dedicated
bot-user PAT — the documented, stable path; (a) the built-in `secrets.FORGEJO_TOKEN` —
repo-scoped and write-capable, and PR-creating on *public* repos like ours, but with
open upstream fragility and a stated future switch to read-only. Recommend (b), test (a)
at first fire if the user wants zero extra secrets.**

- **(a) Built-in `FORGEJO_TOKEN` / `GITHUB_TOKEN` alias** [2][3][4]:
  - v15.0 docs: auto-created per run, destroyed at completion; usable as
    `env.FORGEJO_TOKEN`, `secrets.FORGEJO_TOKEN`, `forgejo.token` (GitHub aliases
    included); "**write permission to the repository** and can be used to push commits
    or use API endpoints such as creating a label or merge a pull request"; only works
    on the run's own repo; **changes authored with it never trigger workflows** (built-in
    ping-pong breaker — exactly the property cf-119 wanted) [2].
  - **PR-creating caveat**: upstream issue #13739 (open 2026-08-02, "problem" report
    retested on latest dev): creating a PR with the automatic token **works on public
    repositories but fails on internal/private ones** (`Can't read pulls or can't read
    UnitTypeCode`). Both lab repos are public (`private:false`, anonymous API, EXPLORE
    §3), so today this token class **can** satisfy Renovate — flagged as unverified
    end-to-end here [3].
  - #14026 (open, enhancement) says the automatic token "has a weak internal
    implementation with hacks" (citing #13739 among others) and that the project wants
    the Actions user **defaulted to read-only** eventually [4] → the auto-token path is
    explicitly on a change path. Repo posture: `main-sync`'s contract suite bans
    referencing `FORGEJO_TOKEN` **in that file only** [repo:
    `tests/services/forgejo-main-sync.sh:152-156` via EXPLORE §5]; a *new* Renovate
    workflow is not bound by that suite.
  - Note `usableRepo()` refusal conditions mirror the docs: no pull **or** push
    permission, `mirror:true`, PRs disabled → the token must satisfy all three (EXPLORE
    §3; autodiscover ignore list [8]).
- **(b) Bot-user PAT (recommended)** [8][5][14]:
  - Renovate's own Forgejo platform page: create a PAT **for the Renovate account**, the
    account "should have full name and email address configured" (git-commit authorship
    — practitioner blog confirms "without that, it won't be able to commit to Git"
    [14]); set via `RENOVATE_TOKEN` env (or `--token=` / config file) [8].
  - Scope table [8] (Gitea-era names) vs the v15.0 scope model [5]: scopes are
    read/write per route family; **`write:repository`** covers "`/repos/*` … Repository
    file, **pull-request**, and release operations" → in Forgejo 15 UI terms the token
    needs **Repository: Write** (plus whatever the account needs to be visible/committable
    — full name/email are profile fields, not scopes). Renovate's table additionally
    lists legacy `repo: Read and Write`/`user: Read` ("valid for all" Forgejo versions);
    map to: Repository read+write. Issue scope (`write:issue`) is needed only if labels
    are managed via API — `renovate.json:8` sets `labels: ["dependencies"]`, so include
    Issue read+write for the label path (table: `>= 1.20.0` [8]).
  - Minting + storing is instance-UI/user work (OQ-5 stays partly user-owned; EXPLORE
    §5: no Forgejo token with PR-writing scope exists in the lab inventory today —
    `forgejo-token` (Bitwarden) is an MCP credential, explicitly not runner-scoped, and
    its API scopes are undocumented).
- **(c) How Renovate authenticates to `forgejo`** [F1-F4]:
  - `RENOVATE_PLATFORM=forgejo` + `RENOVATE_ENDPOINT=https://<instance>/` (default is
    `https://code.forgejo.org/`, F1 — must be overridden; trailing `/api/v1` tolerated,
    F3). `github.api_url`-style context values (`…/api/v1`) work per F3 — the
    practitioner gist uses `${{ github.api_url }}` [15].
  - API auth: token via the Forgejo API (`/api/v1`) [8][F3].
  - **Git clone/push also uses the same token**: default `gitUrl` builds the clone URL
    from the API's `clone_url` and injects `username=<token> password=x-oauth-basic`
    (F4). `gitUrl: endpoint` forces the configured endpoint (useful only if
    `clone_url` advertises an unreachable host, cf-119's `forgejo.`-alias lesson);
    `gitUrl: ssh` needs a deploy key — not recommended here. **No `gitBaseURL`
    involvement on this platform** (F4). Consequence: the token identity is also the git
    author/transport identity; for (a) that means the Actions-token-as-git-basic shape
    has to be proven at first fire (residual unknown U2).
  - `REQUIRE_TOKEN`: **not a thing in 44.181.5** (F8) — the effective gate is F2's
    throw. The similarly-named admin knob in current docs is `requireConfig`
    (`required|optional|ignored`, default `required`) [10]; ours is satisfied because
    `renovate.json` exists in the repo → **no onboarding PR round-trip** on first run
    (the "Configure Renovate" PR the blog describes appears only without a config [14]).

## §3 OQ-6 — github-facing datasources from a Forgejo job: the `GITHUB_COM_TOKEN` leg

**Verdict: mandatory-in-practice. Set `RENOVATE_GITHUB_COM_TOKEN` (secret) — 44.181.5
also accepts plain `GITHUB_COM_TOKEN` (F6). It needs only read-only GitHub access;
nothing about *this* repo's visibility matters on this leg, and the repo is confirmed
public on GitHub anyway [13].**

- Which legs hit GitHub: `github-releases` (k3s, Traefik plugins, Dockerfile pins),
  `github-tags`, `git-refs` on github.com, release-notes/changelog lookups, plus
  `docker/metadata`-style source-URL resolution — i.e. most of `renovate.json`'s 13
  custom managers (EXPLORE §1 manager block). Renovate's own warning text names
  `api.github.com` (F7).
- Official guidance is blunt: "GitHub greatly rate limits unauthenticated API requests,
  so **you need to configure credentials for `github.com` or your deployment will get
  rate limited quickly**" [11]; and the running page: any account on GitHub, **read-only
  scope is enough**, env `RENOVATE_GITHUB_COM_TOKEN` *or* a hostRule; without it,
  "you will exceed the rate limit… which will lead Renovate to close and reopen PRs
  because it could not get reliable info on updated dependencies" [9].
- Anonymous baseline: **60 REST requests/hour per IP** [12] — this repo's pass needs
  hundreds of calls (40+ deps × multiple lookups + changelog source resolution), and
  the lab egress IP is shared with every other GitHub-hitting job on that runner.
  Expect silent degradation, not clean errors: cf-95 reproduced the symptom class
  locally (`skipReason github-token-required`, `no-result` digest lookups, WARN
  rate-limit lines) and its gate had to allowlist it [repo: cf-95 `FRICTION.md:9`].
- Mechanism from the pinned dist (F6): `GITHUB_COM_TOKEN ?? RENOVATE_GITHUB_COM_TOKEN`
  → global hostRule `{hostType: github, matchHost: github.com, token}`; the generic
  `detectHostRulesFromEnv` parser (default `false`, F6) is *not* needed if the env var
  is set; a `hostRules` entry in the admin config file works too [9]. **Recommended**:
  workflow-level `env: RENOVATE_GITHUB_COM_TOKEN: ${{ secrets.RENOVATE_GITHUB_COM_TOKEN }}`
  (the blog's day-2 story is exactly this omission [14]).
- **Does the GitHub repo's privacy matter?** No: the token is used for *dependency
  lookups and changelogs* on github.com, not to read/write `OwnYourIO/SpencersLab`
  (that write path retires with the GitHub install). And the live probe (2026-11-10)
  confirms `api.github.com/repos/OwnYourIO/SpencersLab` → `"private": false` [13], so
  even a repo-read angle is unnecessary; any read-only PAT works. Reusable lab value
  source: the Bitwarden `github-mcp` item already holds a GitHub PAT that backs the
  renovate-mcp container's clone init — plausible donor for this secret's value
  [repo: EXPLORE §5]; minting/attaching stays user-owned.
- Also unauthenticated-but-fine: ghcr.io anonymous manifest reads for the Renovate
  image itself (EXPLORE §3 probed 200), Docker Hub metadata lookups (today's GitHub app
  run does them anonymously too — no regression).

## §4 OQ-8 — Runtime shape on the lab's act_runner

**Verdict: run Renovate as a `container:` job pinned to
`ghcr.io/renovatebot/renovate:<semver tag>`; the `npx`-on-act-image alternative is
second-class (Node engines wall); self-update is achievable and repo-idiomatic (add the
image-line leg, or consciously accept manual bumps like the act images).**

- **(a) Container job — supported and the fit here.** v15.0 docs describe
  `jobs.<job_id>.container.image` for Docker/Podman runners (runner switches are how act
  labels map to job images) [1]; the live runners are docker+dind (F13/§0-correction),
  so container jobs execute natively. Two doc-flagged properties to respect:
  - "container images, once downloaded, are **never updated**" — a reused floating tag
    (e.g. `:latest`) would stick at first-pull forever on a `capacity:1` runner with a
    docker-cache volume [repo: EXPLORE §3]. → **pin an immutable SemVer tag** (Renovate
    publishes "all SemVer tags" — `44.181.5`, plus `44`, `44.181` which are mutable
    rollups; use the full patch form [11]); the docs also recommend digest pinning for
    reproducibility [1] — tag+digest-comment is the pragmatic middle.
  - "Many Actions require node… a custom container without node may break these" [1] —
    our container job needs **no `uses:` steps at all** (Renovate clones the repo itself,
    F4), so this caution does not bind.
  - Entrypoint/args: the image is the official Renovate distribution whose documented
    usage is `docker run --rm renovate/renovate:44` (entrypoint runs the CLI [11]); in a
    `container:` job the steps are `run:` and execute *inside* the image via its shell,
    so the step body is simply `renovate` (CLI on PATH — containerbase convention). This
    PATH/exec detail is **medium-confidence, first-fire verifiable** (U4); the GitHub
    Action-based practitioner variant avoids it but drags in mirror/egress questions
    (below).
  - Which image: `ghcr.io/renovatebot/renovate` is the repo's registry of record
    (ghcr pull proven anonymous here — EXPLORE §3) and hosts identical tags to
    Docker Hub (Docker Hub probe for `44.181.5` returned active `amd64`
    `sha256:9210782e…d1930` + `arm64` images, ~440 MB [13-registry]). Default image =
    Node-only, tools installed at runtime [9]; this repo's managers are regex/custom
    managers + HTTP datasources (EXPLORE §1) → nothing needs extra binaries, so the
    default (not `-full`, several GB [9]) is right.
- **(b) `run:`-steps + `npx renovate@pin`** — the fallback, downgraded by evidence:
  Renovate 44.x requires `engines.node ^24.11.0` (F9); the act job image is
  `ghcr.io/catthehacker/ubuntu:act-24.04` [repo: `charts/forgejo-runner/values.yaml:107-112`],
  whose shipped Node is undocumented here and likely <24.11; a mismatch logs the
  non-fatal-but-ERROR startup line (F9), and cf-95's own harness treats an ERROR log as
  a red run [repo: cf-95 `FRICTION.md:8`]. There is no proven `setup-node` on the
  actions mirror (mirror inventory beyond `actions/checkout` unproven — EXPLORE §3), so
  the npx shape cannot *guarantee* Node 24 inside the job. Also: no daemon constraint
  does not apply to workflow execution (that rule is about agent sessions, not act).
  A third practitioner shape — `uses: https://github.com/renovatebot/github-action@v41`
  (full-URL action resolution bypasses the mirror; the blog gist's approach [15]) — adds
  DOCKER_HOST/socket gymnastics and a mirror-independent github.com action pull; not
  recommended. **Verdict: (a), with (b) only as a local validation convenience** —
  the repo's existing local dry-run gates already run `npx renovate@44.181.5` under the
  workspace's nvm Node 24.22.0, which *does* satisfy the engines [repo: EXPLORE §6 /
  cf-95 `FRICTION.md:7`].
- **(c) Version-pin posture — who bumps Renovate:**
  - Upstream expectation: the self-hosting checklist explicitly includes "make sure
    Renovate itself is updated" [9]; the GitHub app was self-updating out-of-band
    (EXPLORE §7 OQ-8), so a replacement must name the bump path.
  - **Self-update is mechanically available** with this repo's habits: (i) the
    `github-actions` manager already reads `.forgejo/workflows` files (F10) — if the
    pin were `uses:`-shaped it would be tracked automatically; for the `container:`
    shape (ii) add one `customManagers` regex leg annotated on the image line
    (`# renovate: datasource=docker depName=ghcr.io/renovatebot/renovate` — the house
    annotation convention, cf. `renovate.json` image-lines leg) → the next run PRs its
    own bump, merges, and the *following* run uses the new image (deterministic
    because the pin is an immutable full-patch tag; §4a's "never updated" only bites
    floating tags). Digest-pinning instead is also supported (`currentDigest` updates)
    but heavier for the house regex style. Recommend (ii) as a named chunk task, or the
    deliberate alternative: **manual bump posture like the act images** (documented
    "no manager reads them" — EXPLORE §3). Do not leave the image line *un-annotated
    and unmentioned*: silent staleness is the worst outcome (a pinned old renovate is
    fine; a forgotten floating tag is the bug §4a warns of).
  - **Watch-out the planner must decide on:** the same manager that can self-update the
    image will also see `runs-on: ubuntu-24.04` and bare `uses:` pins. F11 shows 44.181.5
    considers `ubuntu-26.04` a valid update for the label (`depType: github-runner`)
    — a merged bump would strand the workflow on a label no runner advertises; and F10
    shows bare `uses:` bumps are validated against **github.com tags**, not against what
    `data.forgejo.org` actually mirrors. Both classes need a `packageRules` block
    (e.g. `matchManagers: ["github-actions"]` with `matchFileNames` under `.forgejo/**`
    → `enabled: false`, or `matchDepTypes: ["github-runner"]` ignore) — or the plan
    consciously opts into tracking with mirror-freshness risk. (Note this affects
    `main-sync.yaml` too, but the GitHub install owns that consequence until disabled.)
- **Forgejo-platform config keys — confirmed against the 44.181.5 dist (F1/F2/F5/F8):**
  `platform` (global, enum incl. `forgejo`, default `github`), `endpoint` (global,
  default null → platform default `https://code.forgejo.org/`), `token` (global; the
  platform **throws without one**, no REQUIRE_TOKEN override); env names exactly
  `RENOVATE_PLATFORM`, `RENOVATE_ENDPOINT`, `RENOVATE_TOKEN`, `RENOVATE_REPOSITORIES`
  (+ `LOG_LEVEL`, `RENOVATE_CONFIG_FILE` / inline `RENOVATE_CONFIG` JSON).

## §5 RECOMMENDED shape (workflow skeleton for the planner)

Static sketch — planner/dev own final keys and the contract-test leg names
(`tests/services/forgejo-renovate.sh`, house shape per EXPLORE §6):

```yaml
# .forgejo/workflows/renovate.yaml  (new; the file itself never carries tokens/hosts)
name: Renovate

on:
  schedule:
    - cron: '17 6 * * *'        # 06:17 UTC daily = well before the America/Denver day;
  workflow_dispatch: {}         # POSIX-5-field, minute granularity; default branch only

jobs:
  renovate:
    if: vars.ROLE == 'dev'      # card gate; same vars.ROLE precedent as main-sync:25
    runs-on: ubuntu-24.04       # label of record on both runners (values.yaml:107-112)
    # no timeout-minutes: the runner's 30m ceiling already bounds it (secret-runner.yaml:91)
    container:
      image: ghcr.io/renovatebot/renovate:44.181.5  # immutable full-patch tag;
      # digest sha256:9210782ef24244d4c986327f598b832d8c977dba632b6f81c6cedfc28c6d1930 (amd64, DHub-probe [13r])
    env:
      LOG_LEVEL: info
      RENOVATE_PLATFORM: forgejo
      RENOVATE_ENDPOINT: ${{ github.server_url }}   # per-instance public ROOT_URL —
      # proven context (cf-6's startsWith(forgejo.server_url,...) guard pattern);
      # identical to `github.api_url` modulo /api/v1, which the platform strips anyway.
      RENOVATE_REPOSITORIES: ${{ github.repository }}  # this repo only; no autodiscover
      RENOVATE_TOKEN: ${{ secrets.RENOVATE_TOKEN }}    # bot-user PAT (Repositories R/W,
      # Issues R/W for labels, full name+email on the account) — or test
      # `secrets.FORGEJO_TOKEN` (auto-token) first if zero-new-secrets is wanted (§2a).
      RENOVATE_GITHUB_COM_TOKEN: ${{ secrets.RENOVATE_GITHUB_COM_TOKEN }}  # read-only
      # GitHub PAT (§3); donor candidate: existing Bitwarden `github-mcp` item.
    steps:
      - name: renovate
        run: renovate            # clones/pushes via clone_url + token (gitUrl default)
      # no uses: steps — the container job needs no checkout and no node actions
```

`renovate.json` delta (the "remove the limits" ask, EXPLORE §2 semantics preserved):
`prHourlyLimit: 0`, `prConcurrentLimit: 0` (lines 9-10 → zeros, `branchConcurrentLimit`
stays unset → inherits the 0 [F12]); plus the `github-actions`-manager containment rule
of §4c and — if self-update is chosen — one regex-manager leg for the image line.

User/instance-side (not agent-executable, per repo rules): create the bot user + PAT on
**dev** instance; add `RENOVATE_TOKEN` + `RENOVATE_GITHUB_COM_TOKEN` Actions secrets on
the dev repo (`ROLE=dev` already set); keep the GitHub install disabled by hand
(card-stated); mirror the same two secrets onto infra later when the gate flips (OQ-1).

Validation split the plan can actually gate on now: `renovate-config-validator` over the
edited `renovate.json`, the offline `--platform=local --dry-run=lookup` gate (cf-95
Commands shape — unchanged by the platform move since it exercises *config*, not the
platform), the new static contract suite (`on:` shape, `vars.ROLE == 'dev'` guard,
secret-name uniqueness, no `uses:`), and the existing `tests/renovate/*` suites
unchanged. Live first-fire validation is **blocked behind the dev-runner repair
(OQ-2)** — record, don't fake it.

## §6 Risks

- **R1 — dev execution is a prerequisite, not a detail.** Gated `ROLE=dev` + zero dev
  jobs ever started ⇒ schedule fires into an unclaimed queue (EXPLORE OQ-2). The ticket
  must scope to "authored + statically validated + first-fire evidence plan", or the
  runner repair lands first.
- **R2 — `runs-on`/`uses:` auto-bumps can strand the workflow** (F10/F11): without the
  containment packageRule, Renovate will PR `ubuntu-24.04 → ubuntu-26.04` and checkout
  tags the `data.forgejo.org` mirror may not carry.
- **R3 — auto-token fragility (only if option (a) chosen):** PR creation works on public
  repos today but is documented as a hack under reimplementation, with a stated
  read-only-default intent [3][4]; a silent server-side tightening breaks Renovate.
- **R4 — capacity:1 serialization:** a long Renovate pass delays `main-sync` jobs on the
  same runner (≤30m worst case) [F13]; pick a quiet UTC minute (skeleton does).
- **R5 — rate-limit stall without §3's token:** anonymous 60/h [12] against a shared
  egress IP → noisy degraded runs (cf-95 reproduced the failure class locally); with
  the limits at 0, a *partially* failed run is worse than a skipped one (half-tracked
  deps open/close churn).
- **R6 — merge→deploy path unproven (OQ-3 unchanged):** Renovate PRs merged on dev never
  reach GitHub/deploy (main-sync divergence; ArgoCD's forge unknown) — the card's "test
  in dev" posture tolerates it, but say it out loud in the plan.
- **R7 — endpoint reachability from job containers:** `github.server_url` (public
  ingress) must resolve/route from inside the DinD job network on each cluster; infra's
  egress is proven only for *push* steps (EXPLORE §3) — dev-instance egress entirely
  unproven. First-fire item.
- **R8 — docs-version drift:** `forgejo.org/docs/latest` is now v17; every syntax claim
  here was read from the v15.0-tagged pages, but Renovate's *docs* track their latest
  release — where docs and the pinned dist differed, this file follows the dist
  (F1-F12).

## §7 Residual unknowns for the planner

- **U1 — exact bot-PAT scope set on Forgejo 15 UI:** legacy names (repo/user/issue) vs
  the new `write:repository`/`write:issue` model [5][8]; needs first-fire or instance-UI
  confirmation (user mints it).
- **U2 — auto-token as git transport:** `FORGEJO_TOKEN` push via the F4
  `token:x-oauth-basic` URL is inferred from "can be used to push commits" [2], never
  shown in Forgejo docs in basic-auth form. If option (a) is pursued, prove before
  depending on it.
- **U3 — Renovate exit-code semantics vs ERROR logs** (cf-95 asserted "ERROR ⇒ exit 1";
  the dist's own startup `checkEnv` ERROR [F9] vs repository-error exit codes may
  differ). Decide the workflow's failure posture (`set -e` step vs `continue-on-error`)
  after one controlled live run, not from docs.
- **U4 — `renovate` on PATH in the container job** (§4a, medium confidence — official
  `docker run renovate/renovate` usage [11] implies it, the blob fetch failed 404/429).
  First `run: renovate --help` step proves it in one line.
- **U5 — whether 15.0.10 carries the schedule-re-registration fix** [#12680/#13029,
  16]; moot unless default branches churn.
- **U6 — dev-instance GitHub/API hairpin egress** (R7) — live-probe or first-fire.

## §8 Sources (all accessed 2026-11-10; local reads listed separately)

External web sources:

1. Forgejo v15.0 docs — *Forgejo Actions | Reference* — https://forgejo.org/docs/v15.0/user/actions/reference/ (sections read: `on.schedule`, `jobs.<job_id>.container.image`, `jobs.<job_id>.timeout-minutes`, `concurrency`, contexts `github`/`vars`/`secrets`).
2. Forgejo v15.0 docs — *Forgejo Actions | Basic concepts → Automatic token* — https://forgejo.org/docs/v15.0/user/actions/basic-concepts/
3. forgejo/forgejo issue #13739 (open, 2026-08-02) — *Automatic token gets wrong permissions unless the repo is fully public* — https://codeberg.org/forgejo/forgejo/issues/13739
4. forgejo/forgejo issue #14026 (open, 2026-08-22) — *org & repo-level service accounts; reimplement `${{ forgejo.token }}`* — https://codeberg.org/forgejo/forgejo/issues/14026
5. Forgejo v15.0 docs — *Access Token Scope* — https://forgejo.org/docs/v15.0/user/authentication/token-scope/
6. forgejo/runner — `internal/pkg/config/config.example.yaml` (branch main; runner `timeout: 3h` default + instance-timeout comment) — https://code.forgejo.org/forgejo/runner/raw/branch/main/internal/pkg/config/config.example.yaml
7. Forgejo v15.0 docs — *Forgejo Runner Configuration → Configuration file reference* — https://forgejo.org/docs/v15.0/admin/actions/configuration/
8. Renovate docs — *Forgejo platform* (Authentication PAT table, autodiscover, merge-style notes; docs track latest — cross-checked against the 44.181.5 dist) — https://docs.renovatebot.com/modules/platform/forgejo/
9. Renovate docs — *Running Renovate* (distributions incl. npm/Docker images default-vs-full, GitHub.com-token section, self-hosting checklist "Renovate itself is updated") — https://docs.renovatebot.com/getting-started/running/
10. Renovate docs — *Self-Hosted configuration* (`requireConfig`, `detectHostRulesFromEnv`, `autodiscover*`; no `REQUIRE_TOKEN`) — https://docs.renovatebot.com/self-hosted-configuration/
11. Renovate repo @44.181.5 — *Self-Hosting Examples* (`docs/usage/examples/self-hosting.md`: "you need to configure credentials for github.com"; "all SemVer tags are published"; tag examples) — https://raw.githubusercontent.com/renovatebot/renovate/44.181.5/docs/usage/examples/self-hosting.md
12. GitHub docs — *Rate limits for the REST API → Primary rate limit for unauthenticated users* (60 req/h, IP-associated) — https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
13. Live probe — `https://api.github.com/repos/OwnYourIO/SpencersLab` → `private:false` (public on GitHub).
13r. Live probe — `https://hub.docker.com/v2/repositories/renovate/renovate/tags/44.181.5` → active `linux/amd64` digest `sha256:9210782e…d1930`, `linux/arm64`, ~440 MB.
14. Practitioner — M. Teixeira, *Running Renovate on self-hosted Forgejo* (2025-02-16, updates to 2025-03-05; bot-user PAT flow, full-name/email, `RENOVATE_REPOSITORIES`, `RENOVATE_GITHUB_COM_TOKEN` day-2 fix, onboarding-PR observation) — https://mteixeira.wordpress.com/2025-02-16/running-renovate-on-self-hosted-forgejo/
15. Practitioner gist — `forgejo-runner-workflow-renovate.yaml` (last active 2026-05-06; cron schedule on Forgejo, `${{ github.api_url }}`, action-from-github.com shape) — https://gist.github.com/badnetmask/0f866e3213590a820916239c7aed1cab
16. forgejo/forgejo issue #12680 + PR #13029 (search-surfaced titles/snippets; schedules re-registration after default-branch change, fix "implements schedule detection and registration") — https://codeberg.org/forgejo/forgejo/issues/12680 · https://codeberg.org/forgejo/forgejo/pulls/13029

Local/offline evidence (read 2026-11-10, cited inline as §0 F-rows and `[repo: …]`):
`EXPLORE.md` (this folder); cf-95 `2026-11-01-bug-fix-renovate.md:33`,
`FRICTION.md:7-9`; `renovate.json`; `.forgejo/workflows/main-sync.yaml`;
`charts/forgejo-runner/values.yaml` + `templates/secret-runner.yaml`;
`services/{dev,gpu}/prod/values.yaml` runner slices; cf-104 plan `:148` (runner→infra
dial), cf-11 `FRICTION.md:21` + `DECISIONS.md:54` (host-mode history, FORGEJO_TOKEN
suppression note); Renovate 44.181.5 dist files per §0.

Contradictions map (STORM step kept honest): the launch brief's host-mode parenthetical
vs EXPLORE's live-pod docker verdict (resolved: EXPLORE+chart+cf-11, §0 correction);
docs' auto-token-write claims vs #13739's visibility-conditioned failure (resolved:
public-repo-conditional, R3); Renovate-docs legacy scope names vs Forgejo v15 scope
model (resolved to v15 names, U1). No source addressed the exit-code-vs-ERROR nuance
blind spot (U3) — nobody's docs tie them together; flagged rather than guessed.

RESULT
status: DONE
chunk: pre-research
files_changed: [.agents/plans/2026/2026-11-cf-135-feat-renovate-forgejo/RESEARCH.md]
deviations: none (STORM run organized per the four-ask brief rather than five-perspective fan-out; every claim source-grounded either via live docs/registry/API reads or the pinned offline dist)
friction: raw.githubusercontent 429/404 blocked the Renovate Dockerfile ENTRYPOINT source-check (worked around via docs' `docker run renovate/renovate` evidence, flagged as U4); docs.github.com "Unauthenticated requests" heading name differed (refetched via heading list); codeberg issue pages render with ToS-banner + nav noise (content still extractable).
open_questions: U1-U6 (§7) — chiefly the bot-PAT scope set to mint (user), whether the plan takes the FORGEJO_TOKEN zero-secret route (§2a vs §2b), the github-actions-manager containment decision (§4c), and confirmation that first-fire validation waits on the dev-runner repair (R1/OQ-2).
next_suggested: agent-plan: build the ticket from §5 — chunks = (1) renovate.json zeros + containment packageRule (+ optional self-update leg), (2) new `.forgejo/workflows/renovate.yaml` + contract suite, (3) user-side secret-minting runbook + first-fire evidence plan; carry OQ-1/OQ-2 rulings (dev-gate vs dev-runner-broken) as explicit plan decisions.

---

# R2 — rework round 2026-11-21: Renovate rebase & checkbox behaviour on Forgejo

Written by `agent-research` 2026-11-21 (rework-round-2 append; nothing above this
section was rewritten). Scope: the owner's three live observations on the CANONICAL
forge `git.spencerslab.com/CuratedForest/SpencersLab` — (1) many Renovate PRs sit
"dirty" (merge conflicts) and no later run fixes them, with PR #90 carrying the
"does not recognize the last commit author" comment; (2) the rebase/retry checkbox
"doesn't seem to do anything"; (3) Renovate PRs' CI shows `pr coder-workspace` /
`pr gpt-researcher-frontend` failing after ~6 s. Method: the pinned 44.181.5 dist
read offline with `path:line` refs, the Renovate docs fetched AT tag 44.181.5, live
anonymous Forgejo API reads (2026-11-21), and git forensics against a fresh fetch
of `origin`. All [S-r#] sources accessed 2026-11-21; dist paths are under
`/home/coder/.npm/_npx/c1fd9d04902091d3/node_modules/renovate/dist`.

**Bottom line.** The shipped runner works as designed; every observed symptom traces
to ONE event: canonical `main`'s history was REBUILT at 15:41–15:51Z on 2026-11-19,
minutes after a 15:25–15:28Z run (not the 06:17 cron — a manual dispatch) opened
~96 PRs. That rebuild orphaned every Renovate branch onto a discarded base, so each
`origin/main..origin/renovate/<x>` range now contains 17 base commits, four of them
authored by `bot-and-reviewed@spencerslab.com`. Renovate's edited-PR guard
(`isBranchModified`) scans ALL commits in that range (not just the last, despite the
comment text) and flags the branch as human-edited on ANY author email it doesn't
recognise — so all 85 dirty PRs are locked out of automatic rebasing: with
`rebaseWhen` resolving `auto → conflicted` here, a conflicted branch is rebased only
when NOT modified, and the daily runs (proven firing at 06:20:2xZ on 11-20) can only
re-ensure the "Edited/Blocked" comment. The checkbox machinery is INTACT on Forgejo
15.0.10 (the list API carries raw bodies; #90's stored body shows a byte-exact
` - [x] <!-- rebase-check -->`); it "did nothing" because the box was ticked at
15:02:25Z on 11-21 — AFTER the last run — and a once-daily CLI run processes it only
on the NEXT pass. The documented escape for the author guard is `gitIgnoredAuthors`
(repo-scoped, renovate.json) — **not** `ignorePrAuthor`, which in this line is a
global-only PR-DISCOVERY filter for bot-account migrations (the launch brief's
hypothesis corrected in §R2.B). The 6-s-failing jobs belong to cf-6's
`containers-build.yaml` PR arm on canonical main and have zero bearing on rebase
decisions, which never consult status checks; `ignoreTests: true` additionally
short-circuits every status read to green (§R2.D).

## §R2.0 Live facts — what canonical actually carries (brief question E)

1. **cf-135 landed on canonical `main`, rebased.** `origin/main` = `b80fae102`
   (fetched 2026-11-21; EXPLORE §8's `8885c173d` is stale). The C02 commit exists as
   `93e37f9d2` "feat(ci): .forgejo/workflows/renovate.yaml — Forgejo-side Renovate
   (C02, review APPROVED r1)" (author date 2026-11-10 18:10:24Z) and IS an ancestor
   of origin/main; our worktree head `215ce4c03`/`893ab9a44` are not (rebuilt copies
   landed instead). The branch `cf-135-feat-renovate-forgejo` itself is not on
   origin. C01's limits zeros are in `origin/main:renovate.json`
   (`prHourlyLimit: 0`, `prConcurrentLimit: 0`, `ignoreTests: true`,
   `timezone: America/Denver`; `gitAuthor`/`rebaseWhen`/`ignorePrAuthor` all ABSENT)
   [S-r16, S-r17].
2. **Canonical `.forgejo/workflows/` now holds FOUR files**: `main-sync.yaml`,
   `containers-build.yaml` (cf-6), `release.yaml` (cf-55, NEW since EXPLORE), and
   `renovate.yaml` [S-r17].
3. **The `renovate.yaml` on canonical is NOT verbatim ours.** Blob `a40fdd75` vs our
   `b122ac9f`: the job guard was changed `vars.ROLE == 'dev'` →
   `contains(vars.ROLE, 'dev')`, and the header rewritten to say a list value like
   `dev,prod` fires the job on that instance too. The change arrived with cf-6's
   squash `3b13f5c62` (author date 11-16 17:00, RE-LANDED onto current main with
   committer date 11-19 15:47) as part of a repo-wide "contains() guards" shape
   (main-sync/release guards are all `contains(...)` now too) [S-r16, S-r17].
4. **ROLE on canonical is therefore a substring match** — the job RAN (96 PRs opened
   11-19 15:25–15:28Z, author `tms`, later Edited/Blocked comments 11-20 06:20Z),
   which proves canonical's instance-side `ROLE` value contains `dev` (e.g.
   `dev,prod`). The variable value itself is instance-side and not anonymously
   readable — recorded as unknown (U8), but the *distinguish-two-hypotheses* ask
   resolves cleanly: BOTH hypotheses are true — the file differs (contains-guard)
   AND the value must contain `dev` [S-r14, S-r16].
5. **PR fleet**: 98 `renovate/*` heads on origin; **97 open renovate PRs, of which
   85 report `mergeable: false`**, and exactly ONE has its rebase checkbox ticked
   (#90). 12 open ones are clean (created or rebased after the rebuild, e.g.
   #102/#103/#105 carry `mergeable: true` and full bodies; #104
   "actions/checkout v7" branch commit 11-21 14:46Z, merged 14:48Z — another manual
   dispatch+merge happened TODAY) [S-r14, S-r16].
6. **PR #90 evidence** (brief asked for the commits' author identity via public
   API): `GET /api/v1/repos/CuratedForest/SpencersLab/pulls/90/commits` IS public
   (the jobs subresource 404 from EXPLORE §3 did not extend here). Head commit
   `3bf424e82` — author AND committer `Spencer H <tms@spencerslab.com>`, 2026-11-19
   15:28:00Z, subject "Update Node.js". PR author user: `tms` (full_name "Spencer
   H", the public API masks the account email as
   `tms@noreply.git.spencerslab.com` — the authenticated `/user` view evidently
   returns the real one, which is what the commits carry, see §R2.A) [S-r15, S-r12].
   Body details: `createdInVer 44.181.5` confirmed via the base64
   `renovate-debug` payload decode (also `updatedInVer 44.181.5`,
   `targetBranch main`, `labels ["dependencies"]`); the body carries the
   "Release Notes retrieval … skipped because **no github.com credentials were
   available**" banner → `RENOVATE_GITHUB_COM_TOKEN` was EMPTY/missing in the 11-19
   run on canonical; PR `labels: []` → the `dependencies` label apparently does not
   exist on the canonical repo (gitea createPr resolves labels by name and dropped
   it); Rebasing line "Whenever PR becomes conflicted, or you tick the rebase/retry
   checkbox" = the live fingerprint of `rebaseWhen: auto → conflicted` (§R2.B);
   `created 2026-11-19T15:28:01Z`, `updated 2026-11-21T15:02:25Z` (the tick),
   `mergeable: false`, 136 changed files, +23239/−890 [S-r12].
7. **Timeline of the poisoning event** (git forensics + API timestamps) [S-r16]:

   | When (UTC) | What |
   |---|---|
   | 11-10 18:10 | cf-135 C02 lands on main (`93e37f9d2`) |
   | 11-16 15:15 | `69ccbe0bb` — the merge-base of every stuck renovate branch |
   | 11-16 17:00–22:32 | OLD main chain grows: `2d213bb10` cf-6 squash (contains-guards copy), `043be6645`, `794dfa355` cf-55 |
   | 11-17 00:06 | OLD main tip ≈ `b7fc1f92e` ("Merge branch 'main' into cf-124…" — cf-124 landed with its merge commit AS the tip) |
   | 11-19 15:25:30–15:28:02 | **Renovate dispatch run** (not 06:17 cron): ~96 PRs cut from the OLD main (PRs #1…#96) |
   | 11-19 15:41–15:51 | **main rebuilt** onto the current chain: `e6f708a9d`… cf-124 re-lands, `3b13f5c62`/`6230e1297`/`1ada03a50` cf-6+cf-55 re-land, then the 15:51 seaweedfs batch — every old-chain commit replaced by a new object (same subjects, new committer dates) |
   | 11-20 06:17→06:20:2x–45Z | scheduled run FIRES (schedule registered on default branch works): all 85 still-dirty PRs get "Edited/Blocked Notification" comments; `updated_at` batch proof on #1/#2/#3 (06:20:23Z) … #89/#90/#91 (06:20:45Z) [S-r13, S-r14] |
   | 11-21 06:17 (inferred) | pass fires again — idempotent (comments already exist, bodies hash-equal, branches locked) so no timestamp changes; **not directly observable** — see U9 |
   | 11-21 14:46/14:48 | another manual dispatch updates `actions-checkout-7.x` from healthy main; #104 merged |
   | 11-21 15:02:25 | owner ticks #90's rebase checkbox |

8. **Other workflows ARE running on canonical** (observation 3 grounded): the
   6-s-failing `pr coder-workspace` / `pr gpt-researcher-frontend` jobs match
   `origin/main:.forgejo/workflows/containers-build.yaml` — job template
   `name: pr ${{ matrix.container }}` (line 361), PR arm guarded
   `forgejo.event_name == 'pull_request' && (vars.ROLE == null ||
   contains(vars.ROLE, 'dev'))` (line 358), which also confirms the ROLE-contains-dev
   finding. So Forgejo Actions execute on canonical for Renovate PRs (the dev-runner
   defect does not apply there, as the owner said). The 6-s failure itself is cf-6
   surface, out of cf-135's fix scope — noted as follow-up F2 (§R2.D) [S-r17, S-r16].

## §R2.A Question A — why "does not recognize the last commit author"

**How the decision is computed (pinned dist, authoritative over docs where they
differ):**

- The guard is `scm.isBranchModified(branchName, baseBranch)`
  (`util/git/index.js:705-755`). It is NOT last-commit-scoped despite the comment
  text (the comment template is stale): it enumerates **every commit** in
  `git log origin/<baseBranch>..origin/<branchName>` and collects BOTH
  `author_email` (`%ae`) and `committer_email` (`%ce`). A branch is "modified" iff
  any collected email ∉ {effective `gitAuthorEmail`} ∪ `gitIgnoredAuthors`
  (config option, glob/regex supported — `util/git/index.js:261-263`) ∪
  `platformIgnoredAuthors` (module-global set, **only the GitHub platform ever
  populates it**, `modules/platform/github/index.js:178`; gitea/forgejo never
  call `setPlatformIgnoredAuthors`). The branch worker calls it at
  `workers/repository/update/branch/index.js:205` and on true →
  `handleModifiedPr` (`branch/handle-existing.js:30-52`, the exact owner-quoted
  sentence + the `Edited/Blocked Notification` topic) → early-return
  `result:"pr-edited"` unless a manual rebase request exists.
- **The identity a bare container run commits with when `RENOVATE_GIT_AUTHOR` is
  unset** (our shape — verified `renovate.yaml` env carries no such key):
  the platform supplies it. `modules/platform/gitea/index.js:129-147` —
  `initPlatform` calls `/user` with the token and returns
  `gitAuthor = "${user.full_name || user.login} <${user.email}>"`;
  `modules/platform/index.js:36-43` prefers an explicitly configured `gitAuthor`
  and otherwise adopts the platform-discovered one; `setGitAuthor`
  (`util/git/index.js:225-233`) parses it (fallback string
  `Renovate <renovate@whitesourcesoftware.com>` exists only when NO discovery
  supplied anything — greps show no `bot@renovateapp.com` default anywhere in this
  line); `writeGitAuthor` (`:234-260`) stamps `git config user.name/user.email`,
  which is what simple-git commits with — so author AND committer both equal the
  PAT account's `/user` email. The docs at our exact tag state it plainly: "When
  this field is unset (default), Renovate will use its platform credentials (e.g.
  token) to learn/discover its account's git author automatically" [S-r1], and the
  Forgejo platform page requires the account to "have full name and email address
  configured" [S-r8] (consistent with mteixeira R1 [14]).
- **Is a mismatch guaranteed in our shape?** NO — in a CLEAN shape it is
  self-consistent: commits stamped `tms@spencerslab.com`, guard compares against
  that same discovered email → Renovate's own commits always pass. (Live proof:
  every sampled renovate tip commit is `Spencer H <tms@spencerslab.com>` while
  #90's PR-author user is likewise `tms` — §R2.0/6.) What makes our fleet fire is
  **any foreign email inside the base..branch range**, and our repo has two systemic
  sources: (1) the 11-19 main rebuild orphaned base commits including four by
  `bot-and-reviewed@spencerslab.com` (the lab's pipeline-bot email) onto ~85
  branches — measured, not hypothesized: `git log origin/main..origin/renovate/node-26.x`
  → 13 tms + 4 bot-and-reviewed emails, none ignorable [S-r16]; (2) going forward,
  ANY commit by another account (e.g. a human "update branch" click by a different
  user, or another bot) locks a branch. The flipside is the docs' `gitAuthor` danger
  note — with a NON-unique (personal) identity, human edits BY tms on a Renovate
  branch are invisible to the guard ("Renovate will mistake the branch as unmodified
  and potentially force push over the changes" [S-r1]) — which is exactly what the
  checkbox's "custom changes will be lost" warning then silently permits. Maintainer
  guidance for the same message class: leave `gitAuthor` blank and let discovery do
  it; `gitIgnoredAuthors` entries must be EMAILS (a login name was a user's mistake
  in #32157) [S-r9]; #42165 documents the same false-"Edited/Blocked" class from an
  identity mismatch on GitHub [S-r10].

## §R2.B Question B — making conflicted PRs auto-resolve every run

**Semantics (docs at 44.181.5 [S-r3] + dist `reuse.js`):**

- `rebaseWhen` default `auto` resolves per repo/PR: `behind-base-branch` when the
  update automerges (or platform requires up-to-date), else `conflicted`
  (`reuse.js:75-94`). Ours has no merge queue (`getBranchForceRebase` is not defined
  on the gitea platform) and these PRs are human-merge (`automerge` false for most)
  → effective `conflicted` — matching #90's rendered "♻ **Rebasing**: Whenever PR
  becomes conflicted, or you tick the rebase/retry checkbox" [S-r12].
- `conflicted`: rebase only when `isBranchConflicted(base, branch)` AND
  `isBranchModified() === false` (`reuse.js:38-51`: "Branch is not mergeable but
  can't be rebased" is the modified case). `behind-base-branch` is gated identically
  (`reuse.js:24-32`). **So no `rebaseWhen` value unblocks our 85** — the edited
  guard is the lock, not the policy. Setting `rebaseWhen: "conflicted"` explicitly
  would be documentation-only (it's the resolved value). `behind-base-branch` is
  counter-indicated: with a near-daily-moving main it would force-push-rebase most
  of ~100 PRs every run — runner churn and CI-storm on a capacity:1 box.
- **The documented escape for the guard is `gitIgnoredAuthors`** [S-r2]: "Renovate
  will treat any PR as modified if another Git author has added to the branch… If
  you have other bots which commit on top of Renovate PRs, and don't want Renovate
  to treat these PRs as modified, then add the other Git author(s)". Repo-scoped →
  lives in `renovate.json`. It matches `author_email`/`committer_email`
  exact/glob/regex strings (`options/index.js:1376-1382`).
- **Correction to the launch brief: `ignorePrAuthor` is NOT the escape.** At this
  line it is `globalOnly` (cannot even be set in renovate.json) and documented as
  "fetch the entire list of repository PRs instead of… only those PRs which it
  created itself" — its use case is migrating the account Renovate runs as
  [S-r6]; dist confirms pure PR-DISCOVERY scope (`gitea/pr-cache.js:80-84` —
  without it the list query adds `poster=<botUserName>`, and
  `gitea/utils.js:69-71 toRenovatePR` drops PRs whose creator ≠ bot user, with a
  `reconfigure` branch-name exception). It touches neither `isBranchModified` nor
  `handleModifiedPr`. Setting it true here would change nothing about rebase
  behaviour — do not add it. (The "force-push over custom changes" cost the brief
  associates with it is real, but it attaches to the guard-bypass paths — the
  checkbox etc. — not to this option.)
- The manual bypass trio, all read fresh from the platform every run and all
  accepted at `branch/index.js:41-57, 214-216, 347-356`: (1) tick the PR-body
  **checkbox**, (2) prefix the PR title with `rebase!`, (3) add the `rebase` label
  (`rebaseLabel`, auto-removed on use); plus the Dependency-Dashboard equivalents,
  and for headless one-shot recovery the **global-only `checkedBranches`** option —
  "as if you selected their checkboxes in the Dependency Dashboard issue"
  [S-r7] — settable as `RENOVATE_CHECKED_BRANCHES='["renovate/x", …]'` env for a
  single `workflow_dispatch` run (documented to also bypass commit limits —
  configuration-options.md, commitHourlyLimit note: "Manual rebases (requested via
  checkbox, Dependency Dashboard, or rebase label) always bypass this limit").

**Minimal config delta for OUR posture** (scheduled CLI once daily, human merges,
lab bots coexist):

1. `renovate.json` top-level:
   `"gitIgnoredAuthors": ["bot-and-reviewed@spencerslab.com"]` — declares the lab
   pipeline-bot identity as non-editing, unblocking the edited guard on the current
   orphan stack AND on any future rebuild wave that orphans its commits.
2. `rebaseWhen`: leave unset (`auto` → `conflicted` is exactly the intended daily
   policy: dirty branches self-heal, healthy-but-behind branches are NOT churned).
3. No workflow change needed for the daily loop; `RENOVATE_GIT_AUTHOR` stays unset
   (discovery is the documented recommendation [S-r1, S-r9]).

**Expected behaviour on the next 06:17 pass after that lands on canonical main**:
each of the 85 conflicted branches evaluates `isConflicted && !isBranchModified` →
true → `forceCommit` path (`branch/index.js:446-448`) → branch is re-cut from
CURRENT main, the dependency update re-applied, and the branch force-pushed
(`--force-with-lease` falling back to `--force`, `util/git/index.js:1103-1127`) →
Forgejo recomputes mergeability → PRs go clean, orphan commits vanish from the
ranges. #90 additionally self-heals even WITHOUT the delta tonight (its ticked box
bypasses the guard). Two costs to state: the stale "Edited/Blocked Notification"
comments are NOT auto-removed on the recovery pass (removal only happens on the
manual-request branch of `handleModifiedPr` — cosmetic residue); and one run
force-pushing ~85 branches fires ~85 PR synchronize events → ~85
`containers-build` PR-arm runs queued serially behind whatever else (capacity:1,
and currently failing at ~6 s each — F2), while the Renovate job itself must fit its
own 30-min ceiling (likely: local checkouts + 85 push round-trips ≈ minutes, not
hours — unmeasured, U9).

**The operational law this finding really implies**: rebuilding `main`'s history
(force-reset) while Renovate branches are open is what poisons the fleet; either
avoid it on the canonical forge, or pair every such rebuild with a recovery pass
(the delta above makes recovery automatic).

## §R2.C Question C — the rebase/retry checkbox path

- **How it works** (dist): the checkbox is part of every PR body template —
  `" - [ ] <!-- rebase-check -->If you want to rebase/retry this PR, check this
  box"` (`pr/body/controls.js:3`). Each run, `getBranchPr` → gitea PR-cache
  (`/repos/<repo>/pulls` LIST with `poster=` and `state=all`) →
  `toRenovatePR` → `bodyStruct: getPrBodyStruct(data.body)`
  (`gitea/utils.js:83`); `pr-body.js:8,23-27` matches
  `/- (?<checkbox>\[[\sx]]) <!-- rebase-check -->/` and sets
  `rebaseRequested = (checkbox === "[x]")`. `rebaseCheck`
  (`branch/index.js:40-58`) re-reads it fresh every run — **no event or webhook is
  part of the mechanism**; the webhook on hosted Renovate only makes it react
  FAST. On true: bypasses the edited guard (`:214-216`), forces
  `reuseExistingBranch=false` + `forceCommit` (`:347-356`, `:446-448`), removes the
  pending/edited comment (`handle-existing.js:34-44`), and the regenerated body
  resets the box to `[ ]` — a ONE-SHOT request, consumed by the next run (docs
  generalise the same per-run semantics: "[Renovate acts] on a subsequent run"
  [S-r5]).
- **Is body-reading broken on Forgejo?** NO, verified live end-to-end at the data
  layer: (a) the list endpoint returns `body` (probed: 10 KB–199 KB bodies present
  in `GET /pulls?state=open`; the dist zod PR schema requires `body:
  z.string()` and `mergeable: z.boolean()` and parses, `gitea/schema.js:84-107`)
  [S-r14]; (b) Forgejo stores raw markdown task-list syntax and HTML comments
  byte-exact through UI edits — #90's CURRENT raw body contains
  `" - [x] <!-- rebase-check -->If you want to rebase/retry this PR, check this box"`
  [S-r12]; (c) Renovate's own createPr `sanitize()` preserved the comment when the
  PR was created. The only known Forgejo checkbox defect upstream was
  ONBOARDING-scoped (#46200: forgejo missing from the onboarding rebase/config-hash
  allowlists, "forcing prUpdateRequested instead of honoring the rebase checkbox" —
  merged 2026-09-16 and verifiably PRESENT in our pinned dist:
  `onboarding/branch/rebase.js:17`, `…/index.js:108,135`) [S-r11]; the
  Forgejo platform docs list no checkbox caveat [S-r8].
- **Why the owner saw "doesn't seem to do anything"** — the tick is the
  most-recent event on #90 (15:02:25Z Nov 21, AFTER the 06:17 pass; and the tick
  itself is what bumped `updated_at`) — with a once-daily CLI there is NO immediacy,
  by construction: the requirement the brief asks about ("any webhook needed for
  immediacy that a CLI cron doesn't have") resolves to **no webhook is needed for
  correctness, only for latency**, and latency on this deployment is up to ~24 h
  (a tick at 06:18 waits 23 h 59 m). Verifiable prediction for the planner: by
  ~06:2xZ on 11-22 #90's head should be replaced by a fresh commit cut from
  `b80fae102`-era main, its Edited/Blocked comment removed, and the box reset —
  independent of the §R2.B delta (U7).
- **With the §R2.B config, is the checkbox still needed?** Not as the daily path:
  conflicted → auto-rebase. It stays the per-PR manual override (also the recovery
  lever if a future orphaning event introduces an author not yet in
  `gitIgnoredAuthors`), alongside `rebase!` title prefix, the `rebase` label, and
  the dashboard/`checkedBranches` headless routes.

## §R2.D Question D — CI failures vs rebase (and the 6-s red jobs)

- `ignoreTests: true` means "ignore _all_ status checks" — the code proves it is a
  hard short-circuit, not a preference: `resolveBranchStatus` returns `"green"`
  immediately when `ignoreTests` (`branch/status-checks.js:7-14`), consumed by
  automerge gates (`pr/automerge.js:34-41`, `branch/automerge.js:13`) and PR-state
  logic (`branch/index.js:505, 725`) [S-r4]. Platform caveat checked: the gitea
  `cannotMergeReason` from `mergeable` only gates automerge when `ignoreTests` is
  false (`pr/automerge.js:34` consults it only under `!ignoreTests`) — with true,
  even a `mergeable:false` PR reads as merge-ready to Renovate; the server still
  refuses the actual merge until it's clean.
- The REBASE decision chain (`reuse.js` conflicted/behind checks +
  `branch/index.js` guard) never calls `getBranchStatus`/`resolveBranchStatus` —
  it is pure git-range arithmetic plus the author guard. So the failing checks on
  Renovate PRs are **confirmed independent of rebase/update**: they neither block
  rebasing nor (with ignoreTests) automerge. The 6-s failures are NOT why the 85
  are dirty.
- **Provenance of the red jobs**: `pr ${{ matrix.container }}` is the PR arm of
  `.forgejo/workflows/containers-build.yaml` on canonical main (cf-6; job name
  template at :361; PR guard `contains(vars.ROLE,'dev')` at :358; the
  `detect-changes` success + `release …` skip pattern in the owner's screenshot
  matches that file's job set exactly). They run on PR synchronize events — which
  the recovery pass will generate ~85 of. Their 6-s failure mode is a cf-6/runner
  matter (likely registry login or DinD startup — unproven here), **out of cf-135's
  fix scope** — carry as follow-ups:
  **F1**: plan a status note that rebase/automerge deliberately ignore CI today
  (`ignoreTests: true`) so red `pr …` jobs do NOT protect merges — if the owner
  wants the PR builds to gate anything, that is an `ignoreTests`/branch-protection
  conversation (cf. R1 OQ-9).
  **F2**: separate ticket for the 6-s `pr …` build failures on canonical.

## RECOMMENDED config delta (exact, for the plan)

`renovate.json` (C01's file — one added key; validator must stay green):

```json
"gitIgnoredAuthors": ["bot-and-reviewed@spencerslab.com"]
```

`.forgejo/workflows/renovate.yaml`: **no key changes.** (Optional: extend the
header comment with the edited-guard/`gitIgnoredAuthors` coupling and the
"main-rebuild poisons Renovate branches" law — planner's call.)

NOT recommended: `ignorePrAuthor` (wrong lever, §R2.B), `rebaseWhen` change
(already resolves to the wanted `conflicted`), `RENOVATE_GIT_AUTHOR` (discovery is
documented-best [S-r1, S-r9]).

Cost/risk of `gitIgnoredAuthors:["bot-and-reviewed@spencerslab.com"]` for a repo
where humans DO occasionally edit Renovate PRs: it only whitelists the PIPELINE-BOT
identity — human edits by tms are today already invisible to the guard (same email
as the discovered gitAuthor [S-r1 danger]), and human edits under any third identity
still lock branches (desired). The delta therefore does NOT weaken human-edit
protection for the tms identity (that protection was already structurally absent —
the honest fix is a dedicated bot account, below); its only new exposure is that if
`bot-and-reviewed` ever commits meaningful work ONTOP of a `renovate/*` branch, the
next rebase force-pushes it away. Observed pipeline law is one-branch-one-owner
(workers never push to `renovate/*`), so the exposure is near-zero — but say it in
the plan.

Structural follow-up (planner decision, mirrors R1 §2b): migrate `RENOVATE_TOKEN`
to a **dedicated bot account** (full name + unique email, e.g.
`renovate@…`), which (a) restores the guard's discrimination against HUMAN edits
(the docs' danger note, [S-r1]), (b) makes commit provenance legible, (c) then
requires a one-time `ignorePrAuthor: true` pass via env
(`RENOVATE_IGNORE_PR_AUTHOR=true`, global-only [S-r6]) for the old→new PR handover
— that IS its documented migration use.

Instance-side items the owner must fix (surfaced by §R2.0, not config-delta): set
`RENOVATE_GITHUB_COM_TOKEN` secret on canonical (present evidence: #90's
release-notes-skipped banner), create the `dependencies` label on the canonical
repo (#90 `labels: []` despite the config), and confirm whether the dev instance is
meant to run Renovate at all now that canonical demonstrably does (guard value
`ROLE` containing `dev` on canonical — the card asked for dev-stage testing;
U8/decision for the planner).

## §R2.Residual unknowns (for the planner)

- **U7** — verify at/after ~06:2xZ 2026-11-22: #90 rebased from fresh base on the
  tick alone (proves checkbox end-to-end live); if it instead keeps the comment and
  stays dirty, the next hypothesis to test with `LOG_LEVEL=debug` is the
  `poster=` cache filter vs list paging (`prCacheSyncMaxPages`), not the body read.
- **U8** — canonical's literal `ROLE` value (instance-side; behaviour-proven to
  contain `dev`, exact string unknown — and whether that was intentional or a
  side-effect of cf-6's contains() sweep).
- **U9** — duration and completeness of the ~85-branch recovery pass inside the
  30-min job ceiling + the capacity:1 CI queue it triggers (unmeasured; the Nov 19
  creation burst handled ~96 branches in ~2.5 min, a useful but imperfect proxy).
  Also unobserved whether today's 06:17 pass fired (idempotent ⇒ invisible).
- **U10** — the 6-s `pr …` build failures' cause (cf-6 surface, F2).
- **U11** — stale `Edited/Blocked Notification` comments remain after recovery
  (cosmetic; removal path exists only for manual-request runs).
- **U12** — whether Forgejo's async `mergeable` recomputation lags enough that a
  just-rebased branch can still read `mergeable:false` into the NEXT run (would
  self-correct; no source found either way).

## §R2.Sources (accessed 2026-11-21)

External docs/repos (all at the pinned tag where "44.181.5" is stated):

1. [S-r1] Renovate docs @44.181.5 — *Configuration options* — `gitAuthor` (discovery default + unique-email danger) — https://raw.githubusercontent.com/renovatebot/renovate/44.181.5/docs/usage/configuration-options.md (section `## gitAuthor`)
2. [S-r2] same file — `gitIgnoredAuthors` (modified-PR default + bots escape) — section `## gitIgnoredAuthors`
3. [S-r3] same file — `rebaseWhen` (auto/never/conflicted/behind-base-branch/automerging semantics) — section `## rebaseWhen`
4. [S-r4] same file — `ignoreTests` ("ignore _all_ status checks") — section `## ignoreTests`
5. [S-r5] same file — `automergeType` (subsequent-run semantics; "automerges branches which are up-to-date and green") — section `## automergeType`
6. [S-r6] Renovate docs @44.181.5 — *Self-Hosted configuration* — `ignorePrAuthor` (entire-PR-list fetch; account-migration use case) — https://raw.githubusercontent.com/renovatebot/renovate/44.181.5/docs/usage/self-hosted-configuration.md
7. [S-r7] same file — `checkedBranches` (dashboard-equivalent headless rebase/create + consent warning)
8. [S-r8] Renovate docs (live, 44.257.9 — version caveat per R1 §R8) — *Forgejo platform* (full-name+email requirement, PAT scopes, merge style, no checkbox caveats) — https://docs.renovatebot.com/modules/platform/forgejo/
9. [S-r9] renovatebot/renovate discussion #32157 (closed, answered by rarkins 2024-10-27) — "Renovate does not recognize the last commit author": leave `gitAuthor` blank for discovery; `gitIgnoredAuthors` entries must be emails — https://github.com/renovatebot/renovate/discussions/32157
10. [S-r10] renovatebot/renovate PR #42165 (closed UNMERGED) — "pass gitAuthor to platform commit API to prevent false 'Edited/Blocked'" — symptom-class evidence — https://github.com/renovatebot/renovate/pull/42165
11. [S-r11] renovatebot/renovate PR #46200 (MERGED 2026-09-16, present in pinned dist) — forgejo onboarding-checkbox/config-hash allowlist fix (scope: onboarding only) — https://github.com/renovatebot/renovate/pull/46200
12. [S-r12] Live probe — `GET https://git.spencerslab.com/api/v1/repos/CuratedForest/SpencersLab/pulls/90` → body with ticked ` - [x] <!-- rebase-check -->`, createdInVer-44.181.5 debug payload, github-credentials-skipped banner, `mergeable:false`, `updated_at 2026-11-21T15:02:25Z`, `labels:[]`, head `3bf424e82`
13. [S-r13] Live probe — `GET …/issues/90/comments` → "Edited/Blocked Notification" comment created `2026-11-20T06:20:45Z` by tms
14. [S-r14] Live probe — `GET …/pulls?state=open` (all pages) → 97 open `renovate/*` PRs, 85 `mergeable:false`, exactly 1 ticked box (#90); LIST response carries full `body` (+ `mergeable`) for every PR; all 85 dirty PRs `updated_at` batched at 2026-11-20 06:20:2x–45Z; sampled comments on #1/#2/#3 created 06:20:23Z
15. [S-r15] Live probe — `GET …/pulls/90/commits` → PUBLIC (unlike the runs/jobs subresource): head commit author=committer=`Spencer H <tms@spencerslab.com>` @2026-11-19T15:28:00Z
16. [S-r16] Git forensics (this worktree, `git fetch origin` 2026-11-21) — origin/main `b80fae102`; 98 `renovate/*` heads; `merge-base origin/main origin/renovate/node-26.x` = `69ccbe0bb`; `origin/main..branch` email census (13 tms + 4 bot-and-reviewed on #90's range); `93e37f9d2` (C02 landed, ancestor) vs local `893ab9a44` (not ancestor); `3b13f5c62` contains-guard (committer 11-19 15:47); old-chain twins `2d213bb10`/`043be6645`/`794dfa355`/`b7fc1f92e`; branch-tip timestamp cluster 15:25:30–15:28:02Z; `renovate/actions-checkout-7.x` 11-21 14:46:34Z; GitHub-authored main commits `73da0c56b`/`c8a27b8fd`/`74f404ae1` (old GitHub-install PRs merged) inside current main's chain
17. [S-r17] Repo reads — `origin/main:.forgejo/workflows/{renovate,main-sync,containers-build,release}.yaml` (guards incl. `name: pr ${{ matrix.container }}` :361, PR guard :358), `origin/main:renovate.json`, our branch's `.forgejo/workflows/renovate.yaml` + `renovate.json` (launch-brief quoted shape re-verified)

Pinned-dist evidence (44.181.5, offline): `util/git/index.js` `isBranchModified`
(:705-755 author/committer census + guard), `setGitAuthor`/`writeGitAuthor`
(:225-260), `setUserRepoConfig`/`setPlatformIgnoredAuthors` (:261-267),
`prepareCommit` force paths (:1103, :1127); `modules/platform/index.js:36-43`
(gitAuthor preference); `modules/platform/gitea/index.js:122-149` (token throw +
`/user` discovery), `:166/:223` (`ignorePrAuthor` → cache poster filter),
`:304-331/:587` (getPrList/getPr/findPr/getBranchPr); `gitea/pr-cache.js:79-90`;
`gitea/schema.js:84-107` (PR `body`/`mergeable` required); `gitea/utils.js:64-95`
(`toRenovatePR`, creator filter, `bodyStruct`); `modules/platform/pr-body.js:8,
23-27` (checkbox regex); `workers/repository/update/branch/index.js:40-58`
(rebaseCheck incl. `rebase!` title + label), `:102-103`, `:205-221` (guard +
`pr-edited` early return + manual bypass), `:347-356` (userRebaseRequested →
reuse=false), `:446-448` (forceCommit), `:505/:725` (ignoreTests consumers);
`branch/handle-existing.js:30-52` (the exact comment + removal paths);
`branch/reuse.js:24-51, 75-94` (rebaseWhen resolution + guard gating);
`branch/status-checks.js:7-14` (ignoreTests → green);
`update/pr/body/controls.js:3` (checkbox template); `update/pr/index.js:83`
(rebase-requested skips body-cache short-circuit); `modules/platform/github/index.js:178`
(only-GitHub `setPlatformIgnoredAuthors`); `config/options/index.js:1353-1359`
(`gitAuthor` no static default), `:1376-1382` (`gitIgnoredAuthors`), `:3554-3560`
(`ignorePrAuthor` globalOnly), `:3674-3682` (`checkedBranches` globalOnly/
experimental), `:4675+` (`rebaseWhen`);
`global-config-option-defaults.generated.js` (`ignorePrAuthor:false`).

Contradictions map (STORM, round-2 slice): the launch brief's "ignorePrAuthor is
the documented escape" vs docs+dist (it is a discovery filter; `gitIgnoredAuthors`
is the escape) — resolved to dist+docs [S-r6, S-r2]. The comment's "last commit
author" wording vs dist scanning ALL commits — resolved to dist (forensics show the
tip author IS recognized while mid-range authors fire it) [S-r15, S-r16]. Docs'
"gitAuthor unset → discover account identity" vs the old `bot@renovateapp.com`
default (absent from this line) — resolved to dist+docs at tag [S-r1]. No source
addressed whether Forgejo's `mergeable` recompute lags a just-rebased head —
flagged as U12 rather than guessed.

RESULT
status: DONE
chunk: rework-round-2-research
files_changed: [.agents/plans/2026/2026-11-cf-135-feat-renovate-forgejo/RESEARCH.md]
commands_run: [git ls-remote origin => pass, git fetch origin main + renovate/* refs => pass, origin/main tree/log/blob forensics (ls-tree, log -L, merge-base, range author census) => pass, dist greps + reads (isBranchModified/rebaseCheck/rebaseWhen/checkbox/ignoreTests paths) => pass, curl raw docs @44.181.5 configuration-options.md + self-hosted-configuration.md => pass, live Forgejo API probes /pulls/90 + /issues/90/comments + /pulls list (body+mergeable census: 97 open, 85 dirty, 1 ticked) + /pulls/90/commits => pass, GitHub issue/PR lookups (#32157, #42165, #46200) => pass]
deviations: none material (organized per the launch brief's A–E rather than a five-perspective STORM fan-out, mirroring round 1; the brief's ignorePrAuthor hypothesis was corrected against docs+dist rather than adopted; the canonical /actions/runs list page renders JS-only (11-byte response) so schedule-firing evidence rests on the 06:20Z comment/updated_at batch — noted inline)
friction: canonical /actions/runs HTML unreadable anonymously (JS shell) — worked around with comment/commit timestamp forensics; the anonymous API masks the tms account email as tms@noreply.git.spencerslab.com while commits carry the real one — resolved via the discovery-precedence code read (guard is self-consistent either way); one searxng multi-query call timed out (retried single-shot); GitHub search API's low anonymous budget rationed to three calls; /tmp/opencode writes denied to this session (research role — RESEARCH.md only), so the R2 text was appended in place.
open_questions: U7–U12 (§R2.Residual) — chiefly the verifiable 11-22 06:17Z #90 prediction, canonical's literal ROLE value, whether the owner wants canonical to stay the Renovate home (it contradicts the card's dev-gate posture while cf-6's contains() rewrite made it true), plus the owner-side secrets/labels gaps; config-delta recommendation = one key: renovate.json `gitIgnoredAuthors:["bot-and-reviewed@spencerslab.com"]`, with rebaseWhen/RENOVATE_GIT_AUTHOR/ignorePrAuthor all deliberately untouched.
next_suggested: agent-plan: fold §R2.B's delta + the recovery-pass expectations into the rework chunk (C03-style), record the main-rebuild law in DECISIONS, and queue F1 (ignoreTests-vs-red-CI posture note) + F2 (6-s pr-build repair) as follow-up cards; UA-list additions: canonical RENOVATE_GITHUB_COM_TOKEN secret, `dependencies` label, bot-account decision (R1 §2b revived with fresh evidence).

# R3 — rework round 2026-11-21: Chart.lock updates under the Forgejo-side Renovate

Written by the SECOND `agent-research` session of the rework round 2026-11-21 (pure-append;
R2 and everything above untouched). Scope: the owner's verbatim question — *"I think on
github it'd update the Chart.lock files? Can you see if Forgejo will do that too? Or if I
was actually going about it a different way?"* Method: pinned 44.181.5 dist read offline
(`path:line` refs under `/home/coder/.npm/_npx/c1fd9d04902091d3/node_modules/renovate/dist`),
Renovate docs fetched AT tag 44.181.5 [S-r3-1..4], git forensics against a fresh `origin`
fetch (origin/main `b80fae102`, unchanged from R2), repo-wide Chart.yaml↔Chart.lock parse
over the canonical tree, and anonymous Forgejo API probes of the helm-PR fleet (bodies,
file lists, comments) [S-r3-10..14]. All [S-r3-#] accessed 2026-11-21.

**Bottom line.** Your memory of GitHub is correct AND you were not going about it a
different way: in both worlds the lock files are updated by the SAME component — the
built-in `helmv3` package manager, whose artifact step runs real `helm repo add … && helm
dependency update` in the Renovate container and commits the regenerated `Chart.lock`
next to the `Chart.yaml` dep bump. It is platform-independent code (no platform module is
even consulted) and `helmv3` is enabled in our config by default (no `enabledManagers`,
no Chart.lock-targeting custom manager exists). **But the Forgejo-side run has NEVER
successfully updated a lock file.** Every `Update Helm release …` PR on canonical — all
22 (3 merged 11-19, 19 open) — carries an auto-posted `⚠️ Artifact update problem`
comment naming every touched `Chart.lock` with the identical failure
`No tool releases found.`: Renovate's dynamic tool-installer (binarySource=install —
the default, and the pinned default image ships **only Node**, helm is fetched at
runtime) resolves the helm tool via the **`github-releases` datasource on
`helm/helm`**, which needs api.github.com — and api.github.com without credentials is
exactly the missing `RENOVATE_GITHUB_COM_TOKEN` R2 proved on the 11-19 run. Upstream
corroborates this failure class on Forgejo hosting verbatim (discussion #39399: same
WARN, maintainer root-caused to api.github.com 403 rate-limiting). The artifact error
does not stop the PR — Renovate commits the yaml-only change and annotates the PR —
and the 11-19 rebuild batch merged three of those warning-bearing PRs anyway, so main
today carries the drift you feared, in exactly **two charts**: `charts/base` (argo-cd
yaml 10.18.2 vs lock 10.11.6) and `services/home/prod` (wekan yaml 12.99.0 ×2 blocks vs
lock 12.77.0 ×2). The other 77 dependency pairs across all 81 lock files are consistent;
Forgejo-era git has **zero** Chart.lock commits since 11-19, while the GitHub era since
2026-09 produced 33 renovate[bot]-authored lock-touching commits (pairs, e.g. #826, #921).
Fix is small and already half-wired (the workflow references the secret): provision
`RENOVATE_GITHUB_COM_TOKEN` on canonical and — recommended as the durable, v3-law-honoring
delta — pin the tool: `"constraints": {"helm": "3.22.1"}` in renovate.json (an exact
version skips the GitHub API lookup entirely). Existing drift needs one manual
`helm dependency update` repair commit; daily passes will NOT self-heal completed bumps.

## §R3.0 Live facts (canonical, 2026-11-21)

1. **Config** (`origin/main:renovate.json` [S-r3-8]): `extends: ["config:recommended"]`
   — which contains NO manager restriction (dist `config/presets/internal/config.preset.js:24-44`
   enumerates dashboard/grouping/changelog presets only) → every default-enabled manager,
   **`helmv3` included**, runs. There is no `enabledManagers`, no `constraints`, no
   `postUpdateOptions`, no `bumpVersion`, no top-level `lockFileMaintenance`, and
   `gitIgnoredAuthors` is STILL absent (R2's delta has not landed). The file mentions
   `Chart.lock` **zero times**; the 13 customManagers legs target values.yaml /
   appset.yaml / Dockerfile / (k10: annotated Chart.yaml name+version+repository blocks
   only, as a changelog/sourceUrl override leg — the cf-95 suite tests it as "manager #9")
   — none of them has lock-file capability (regex managers have no `updateArtifacts` at
   all; dist grep: capability exists for 50 named managers, none is `regex`).
2. **The lock surface census**: 74 `charts/*/Chart.yaml` + 13 `services/*/prod/Chart.yaml`
   tracked; 74 + 7 = **81 Chart.lock files**; every Chart.yaml that declares `dependencies`
   has a lock sibling (the 6 service umbrellas without a lock — dev, gpu, gpu-ai, grow,
   monitoring, proxy-backup — declare NO dependencies block, so there is nothing to lock).
   `helmv3`'s fileMatch `/(^|/)Chart\.ya?ml$/` (dist `helmv3/index.js:28`) therefore
   covers all 74 charts AND the 7 services umbrella charts; `lockFileNames:
   ["Chart.lock"]` (`:21`).
3. **Consistency scan over `origin/main`** [S-r3-9] (parse both files per chart, compare
   each yaml `dependencies[].version` against the lock entry): **80 dependency pairs →
   77 OK, 3 problem rows in exactly 2 charts**:
   - `charts/base`: `argo-cd` yaml **10.18.2** vs lock **10.11.6** (lock otherwise fine:
     cert-manager v1.21.3, gateway-api-crds 1.2.5; lock `generated: 2026-11-03`).
   - `services/home/prod`: `wekan` **two yaml blocks at 12.99.0** (plain +
     `alias: boards`) vs lock **two 12.77.0 entries**. (This lock also carries 7
     app-template 5.0.1 entries mirroring 7 yaml blocks — a non-canonical duplicate-
     heavy shape that a real `helm dependency update` would rewrite; expect one larger
     diff on this chart when locks first flow.)
   Everything else is consistent today — including `charts/traefik`/`charts/traefik-zerotrust`
   (42.4.1 pair — see §R3.B for why that one escaped) and all 55 bjw-s app-template pairs.
4. **The helm-PR fleet on the Forgejo side** [S-r3-10,11,12]: 22 PRs titled
   `Update Helm release …` (datasource-level title — `modules/datasource/helm/index.js:24`
   sets `commitMessageTopic: "Helm release {{depName}}"` for EVERY helm-datasource dep,
   which is why both the built-in PM's PRs and the regex legs' PRs share the wording;
   titles alone do NOT identify the manager). Merged: **#19** traefik 42.4.1 (2 files —
   both Chart.yaml), **#53** argo-cd 10.18.2 (1 file — Chart.yaml), **#63** wekan 12.99.0
   (1 file — Chart.yaml); `merged_at` 15:29:11–15:29:19Z on 11-19. **None contains a
   Chart.lock file** (`/pulls/{n}/files`). Every sampled PR — merged #19/#53/#63 AND open
   #52 (app-template v5.3.0, the 55-chart surface), #56 (gateway-api-crds), #58 (loki) —
   carries the `### ⚠️ Artifact update problem` comment listing one failure per touched
   lock file, error body **`No tool releases found.`** (#19 names both traefik locks;
   #52 names charts/389ds … — one entry per chart).
5. **Git census** [S-r3-9]: `git log origin/main --since=2026-11-19 -- '*Chart.lock'` →
   **empty** — no Forgejo-era commit has ever touched a lock file. GitHub era since
   2026-09: 83 lock-touching commits total, **33 authored by `renovate[bot]`**, all in
   yaml+lock pair shape, e.g. `73da0c56b` (11-18, "Update Helm release traefik to
   v42.4.1 (#921)", 4 files: 2 yaml + 2 lock), `bcf254c3b` (11-03, "#826" argo-cd 10.11.6
   pair — this is the commit that produced the lock half of today's base drift),
   `d8b12fd0f` (11-01, wekan 12.77.0 pair on services/home/prod), `ed1b1f1b1` (11-14).
6. **Today's runs**: the scheduled 06:17Z pass FIRED (PRs #97/#98 created 06:20Z —
   answers R2 U9's "not directly observable" with new data), plus a 14:45–14:48Z manual
   batch (#99–#105, incl. merged #104 actions/checkout). **No PR created today carries
   the "no github.com credentials were available" banner** that #90 from 11-19 showed —
   first evidence that `RENOVATE_GITHUB_COM_TOKEN` may NOW be provisioned on canonical
   (unconfirmed; U13). None of today's PRs is a helm one, so **the lock mechanism has
   not actually been re-exercised under a token yet** — artifact steps only re-run when
   a branch is retried (see §R3.D).

## §R3.A Mechanism — who updates Chart.lock, and what it needs

1. **The component is the built-in `helmv3` manager** — nothing else in Renovate or in
   this repo's config can write a Chart.lock. Docs at our tag
   (`lib/modules/manager/helmv3/readme.md`): it "supports updating Helm Chart references
   in … Chart.yaml files, for Helm v3" [S-r3-1].
   - Extraction (`helmv3/extract.js:12-69`): requires apiVersion v2, reads
     `dependencies[].name/version/repository`; `repository:` https URLs → `registryUrls`
     + helm datasource; **`oci://` repos → `getOciChartDep`** (`utils.js:16`, docker
     datasource — covers our 4 OCI deps: toolhive ×2, mariadb-operator, forgejo-helm);
     `git+` repos skipped (`extract.js:44`). `lockFiles: [Chart.lock]` is advertised when
     the sibling exists (`extract.js:69`).
   - **The lock refresh RUNS real helm — it is not a synthesized lock**
     (`helmv3/artifacts.js:17-33`): per chart dir it issues `helm registry login` for
     OCI repos (hostRules of hostType docker — `common.js`), `helm repo add <name>
     <url> --force-update` (+ `--username/--password` from helm-type hostRules) and then
     **`helm dependency update <dir>`**, then commits whatever lock the tool rewrote
     (`:72`, with `isHelmLockChanged` `:91-95` treating any diff beyond the `generated:`
     timestamp line as a change). No lock sibling → silent `return null` ("No Chart.lock
     found", `:46`) — not our case (all dep-bearing charts have locks).
   - **Requirements**: (a) a `helm` binary — see §R3.C, NOT present in our image and
     fetched at runtime; (b) outbound network from the container to EVERY dependency
     repository URL (repo indexes + OCI pulls); (c) writable cache (`HELM_REGISTRY_CONFIG`/
     `HELM_REPOSITORY_CONFIG`/`HELM_REPOSITORY_CACHE` are pointed at `privateCacheDir()`
     by `generateHelmEnvs`, `common.js`); (d) hostRules only for private repos — none
     needed for ours (all public).
2. **Platform=forgejo changes nothing here.** `grep updateArtifacts dist/modules/platform/
   → 0 hits`; the artifact step lives in `workers/repository/update/branch/index.js`
   (shared by all platforms, uses the git storage layer, not the platform API). Proven
   empirically anyway: the Forgejo-side run DID enter the helmv3 artifact path on all
   22 branches — it is precisely what posted the artifact-problem comments. The failure
   was below the platform layer, in tool installation.
3. **Which of the repo's two helm surfaces this touches**:
   - **(i) Chart.yaml dependency blocks** — the 81-lock surface (charts + 7 service
     umbrella charts): the helmv3 PM's domain; PRs bump `dependencies[].version` AND
     (once fixed) regenerate the lock pairs. 80 tracked pairs today.
   - **(ii) chart-version annotations in services values / ApplicationSets** — legs
     k04/k05 (values.yaml `chart:`/`<name>:` + `version:` + `repository:` triples),
     k08 (appset `baseChartVersion` with `# renovate: datasource=helm`), k10 (the
     changelog/sourceUrl override leg over annotated Chart.yaml/values.yaml blocks).
     These are regex managers: **no artifact capability → they never touch Chart.lock**
     (structurally, not by config). And on the values/appset surface there is no lock at
     all — those entries are chart releases ArgoCD pulls directly from the repositories,
     not local subcharts. k10 does double-extract the two annotated `wekan` blocks
     alongside helmv3 (the cf-95 suite's k5 leg pins exactly that "2 split wekan legs"),
     which is why both managers' updates can share one branch; #63's artifact comment
     names `services/home/prod/Chart.lock` → the helmv3 copy was present in the branch
     and its artifact step failed like everywhere else.
4. **The `version:`-ownership law holds**: `helmv3` exports `bumpPackageVersion`
   (own-Chart-version bump) but it is wired only via `bumpVersions(config)`
   (`update/branch/bump-versions.js:12-24`), which no-ops unless a `bumpVersion`
   (option or packageRule) is configured — renovate.json sets none and has no
   `postUpdateOptions` → Renovate never touches the chart's own `version:` (release.yaml's
   exclusive job per AGENTS.md law) and never commits vendored `charts/*.tgz` archives
   (helmUpdateSubChartArchives off).
5. **Digest/lock churn**: top-level `lockFileMaintenance` is unset → the feature is
   DISABLED by default (docs `configuration-options.md:2744-2767` ["By default, …
   disabled"; weekly `before 4am on monday` when on]) [S-r3-2]. No lockfile-only digest
   refresh PRs have ever existed on either side (git-log census). The per-package
   `lockFileMaintenance: {enabled: true}` blocks inside packageRules 3/4 ("Internet
   facing services", "Non-critical services") can conjure nothing while the feature is
   off globally — an LFM update is evaluated only when the maintenance branch exists —
   they are dead weight today (U15). When a branch IS retried, note that helm rewrites
   `digest:` + `generated:` for all deps of that chart, so a fix pass can legitimately
   include small digest-only hunks in the same PR.

## §R3.B History — GitHub-side (owner-memory check) and Forgejo-side

**GitHub side: YES, it really updated the locks.** 33 merged renovate[bot] commits since
2026-09 touched `charts/*/Chart.lock`/`services/*/Chart.lock`, always as yaml+lock pairs
inside one commit (= one PR): argo-cd #826 (`bcf254c3b`, 11-03, pair to 10.11.6), traefik
#921 (`73da0c56b`, 11-18, 4-file pair), wekan (`d8b12fd0f`, 11-01, home/prod pair to
12.77.0), crowdsec #876 (`ed1b1f1b1`) etc. That is the hosted Renovate GitHub App (author
`renovate[bot]`) running the same helmv3 PM on Mend's infrastructure, where helm
resolves/downloads without our token problem. The last such merge was 11-18; the
GitHub install was then disabled by hand (card premise, R1 header).

**Forgejo side: never once.** Chronology of the drift, fully evidenced:

| When (UTC) | Event |
|---|---|
| 11-19 15:25–15:28 | first canonical run (manual dispatch, R2) cuts ~96 PRs; every helm branch's artifact step fails `No tool releases found.` → **yaml-only** branches + warning comments (GITHUB_COM_TOKEN empty — proven by #90's banner from the same run) |
| 11-19 15:29:11–19 | **#19/#53/#63 merged** (traefik-pair, argo-cd, wekan) — batch merges during the rebuild window, not Renovate automerge (their automerge rules' schedules are the 1–6h Denver window; 15:29Z = 08:29 MST; U16). The warning comments said "You probably do not want to merge this PR as-is"; `ignoreTests: true` also blinds Renovate itself (R2 §R2.D) |
| 11-19 15:41–15:51 | **main rebuilt** (R2 §R2.0/7). traefik's yaml-only merge got superseded by GitHub-side twin `73da0c56b` (pair) → traefik consistent. argo-cd 10.18.2 / wekan 12.99.0 had NO GitHub-side twin (newer than the 11-18 cutoff) → re-landed as yaml-only commits `80c503f72`/`dfd95e3e2` → **the two drifts baked into current main** |
| 11-20…11-21 06:17 | daily passes fire (R2 evidence + today's #97/#98 at 06:20Z) — **no helm branch retries its artifacts** on unchanged branches (the warning comment itself spells the retry triggers; `branch/index.js:420-446` only re-runs work when files/conflicts/checkbox change) → zero lock commits since 11-19 (census §R3.0/5) |
| 11-21 14:45–48 | manual batch — non-helm PRs only; no banner → token likely present NOW (U13) but UNTESTED against a helm artifact step |

**Consistency-per-chart report**: per §R3.0/3 — mismatches only `charts/base` (argo-cd)
and `services/home/prod` (wekan ×2); all other 71 charts and 6 other service umbrella
charts are yaml↔lock-consistent, including the 55-app-template pairs.

## §R3.C Why "YES-but-not-happening" — the exact failing layer

The chain that produces a lock file, with the break point marked (all dist, 44.181.5):

1. helmv3 update committed to branch (works — that's what landed).
2. Artifact step → `resolveToolConstraint(config,'helm')` (`manager/util.js`) →
   `config.constraints?.helm` — **unset in our config** → constraint `undefined`.
3. `exec(...)` with `{toolName:'helm', constraint: undefined}`; `binarySource` default is
   **`install`** (`config/options/index.js:672-684`; globalOnly — env-settable);
   `isDynamicInstall` (`util/exec/containerbase.js:281-288`) returns true inside a
   containerbase image; the official default image is exactly that — and per the docs it
   ships **Node only: "The default image only comes with the Node.js environment. Renovate
   will then install any needed tools when it runs"** [S-r3-3]. **`helm` is NOT in
   `ghcr.io/renovatebot/renovate:44.181.5`** (the `-full` flavour is the one with tools
   pre-installed — docs `running.md` "Docker images" section).
4. `resolveConstraint` (`containerbase.js:294-330`): no constraint → **must look up the
   tool's release list**: the helm entry of `allToolConfig` is
   `{datasource: "github-releases", packageName: "helm/helm", versioning: "semver"}`
   (`:118-122`) → api.github.com. Releases empty →
   `logger.warn(...); throw new Error("No tool releases found.")` (`:316-317`).
5. That error → caught in `artifacts.js:87-88` → `artifactErrorResult(lockFileName, err)`
   → PR gets the ⚠️ comment (default `suppressNotifications: []`,
   `options/index.js:3341-3346`, so it is visible; branch still raises the PR —
   `branch/index.js:420-436` throws-away-the-PR only under a `releaseTimestamp` we
   never have → "PR has no releaseTimestamp" → proceeds).

**Root cause = anonymous api.github.com.** The github-releases lookup inside the tool
installer rides the same host-rule pipeline as changelogs: `GITHUB_COM_TOKEN` /
`RENOVATE_GITHUB_COM_TOKEN` becomes a global github.com hostRule at env-parse
(`workers/global/config/parse/env.js:164-171`, R1 F6) and the tag docs are explicit:
*"GitHub.com token for changelogs **(and tools)** … It's used when fetching changelogs
for repositories, **as well as some Renovate-specific tools at runtime**, in order to
increase the hourly API limit"* [S-r3-4]. R2 proved the 11-19 canonical run had the
secret EMPTY (no-credentials banner; `renovate.yaml` only references
`secrets.RENOVATE_GITHUB_COM_TOKEN`, whose provisioning is instance-side UA2). Anonymous
api.github.com = 60 req/h/IP — in a 96-branch burst with dozens of github-releases/
git-tags lookups, the helm/helm call lands empty → 403-swallowed → "No tool releases
found". Community corroboration of the exact class, on Forgejo hosting: discussion
**#39399** ("WARN: No tool releases found", maintainer jamietanna root-caused to
`POST https://api.github.com/graphql … 403 … GitHub failure: rate limit`, dup of #37685
= provision the token), and **#34665** (same throw, lockfile-maintenance context)
[S-r3-5]. Also NOT the cause, each ruled out with evidence: repo config disabling the
PM (preset read, §R3.0/1); platform=forgejo quirks (§R3.0/2, §R3.A.2); a different
update source than the dependency version (titles/comments identify helmv3 branches);
the custom-manager legs (they cannot write locks, §R3.A.3-ii); chart-own `version:`
confusion (never touched, §R3.A.4). The old GitHub-side updates came from the SAME
helmv3 PM — nothing in renovate.json ever targeted Chart.lock (0 mentions).

One honest consequence to state: with the token merely fixed, the resolver picks the
**latest stable helm release** (v4.x in Nov 2026) — the tool that then writes our locks
would be helm 4, while the repo law ("Hold the helm v3 line" packageRule, whose real
target is the `helm/helm` ARG pin in `containers/coder-workspace/Dockerfile` extracted
by leg k09 — v3.22.1 today, cf. open PR #103) exists precisely because ArgoCD renders
with helm v3. v4-generated Chart.lock is same-schema in principle, but that is U17 —
unverified.

## §R3.D Verdict + config delta + what the owner should observe

**Verdict**: Forgejo-side Renovate is DESIGNED to update Chart.lock (same helmv3 PM as
the GitHub side, platform-independent, enabled by default, no config-side machinery
needed or present) — and has failed at it on every single branch so far because the
runtime tool install has no GitHub credentials. The owner's fear is real and already
materialized in exactly two charts.

**Recommended delta** (keys, where):
1. `renovate.json` top-level (repo-owned, C01's file): **`"constraints": {"helm": "3.22.1"}`**
   — the options schema exposes one property per containerbase tool (`toolConstraintProperties`,
   `options/index.js:3027-3053`, freeChoice) and `resolveConstraint` with a SINGLE exact
   version **short-circuits before any GitHub lookup** (`containerbase.js:303`), so the
   artifact path becomes deterministic, token-independent, and honors the v3 law (matches
   the coder-workspace ARG; note it must be re-pinned when that ARG bumps — k09's PRs do
   NOT auto-sync it). Validator-safe; suite-neutral (touches no leg/rule counts that
   m3/m4/m5/t8 pin — it is a new top-level key; C01's m5 keyset equality WILL redden on
   it — the suite update belongs to the same rework chunk).
2. Owner/instance side: **verify `RENOVATE_GITHUB_COM_TOKEN` on canonical** (today's
   banner-free PRs suggest it landed — U13); still the right thing beyond this question
   (changelogs, R1 §3, and possibly the asset download itself, U14).
3. **Repair the drift with one manual commit**: `helm dependency update charts/base
   services/home/prod` (expect the home/prod lock to rewrite into canonical shape —
   the duplicate app-template ×7/wekan ×2 entries collapse per what helm emits; the
   base bump lands 10.18.2 + new digests). Renovate will NOT re-do completed version
   bumps, so no automatic path exists for these two.
4. Sequencing with the R2 delta: land 1–2 **before** the `gitIgnoredAuthors` recovery
   pass rebases the 85 branches — otherwise every recreated helm branch force-pushes a
   yaml-only diff AGAIN; with the constraint in, the recovery pass re-cuts branches and
   re-runs artifacts under working helm, producing paired yaml+lock diffs.

**What to observe on the next pass (concrete expected PR shape)**: after the constraint
lands on canonical main (or the secret is confirmed), tick the rebase/retry checkbox on
**#52 ("Update Helm release app-template to v5.3.0")** — the biggest clean test: at the
next 06:17Z pass its branch must be re-cut from current main and the PR's Files tab must
show paired hunks — one `Chart.yaml` version line **+ one `Chart.lock`** per affected
chart (~55 charts), lock hunks changing `version:` 5.0.1→5.3.0, `digest:`, and
`generated:` — and the `⚠️ Artifact update problem` comment must be **auto-removed**
(the removal path `branch/index.js:437-446` fires exactly when a retry pass has
`updatedArtifacts` and no errors). New helm PRs from later daily passes should open
WITHOUT any artifact comment at all. If #52 instead re-lands yaml-only + a fresh
comment: the remaining suspect is the containerbase **asset download** (resolution was
skipped by the exact pin, but `install-tool helm 3.22.1` still downloads from
GitHub/get.helm.sh) — rerun once with `LOG_LEVEL=debug` and grep
`"Failed to update Helm lock file"` + `helmv3.updateArtifacts` (U14).

**Residual unknowns for the planner**:
- **U13** — canonical's current `RENOVATE_GITHUB_COM_TOKEN` state (banner absence today
  is suggestive, not proof; ask owner or read run logs).
- **U14** — whether `install-tool helm <exact>` succeeds anonymously at the DOWNLOAD
  step even when resolution is skipped (containerbase download internals not read here).
- **U15** — semantics of the per-package `lockFileMaintenance:{enabled:true}` blocks in
  packageRules 3/4 (inert while global LFM off, per §R3.A.5 reasoning — one doc-line
  check or dry-run confirmation would close it; also decide whether they should be
  deleted or made real).
- **U16** — who/what executed the 15:29Z merges of #19/#53/#63 (rebuild batch, presumably
  bot-and-reviewed; not Renovate automerge per schedules) — relevant only if the owner
  wants merge-policy changes; and the odd `#103 "Update dependency helm to v3.22.1"`
  title against an already-v3.22.1 Dockerfile (possibly stale-cache lookup; harmless).
- **U17** — helm-4-generated Chart.lock compatibility with the ArgoCD helm-3 renderer
  (moot if the v3 constraint pin lands).

## §R3.Sources (accessed 2026-11-21)

External docs/repos (tag-pinned where stated):
1. [S-r3-1] Renovate @44.181.5 — `lib/modules/manager/helmv3/readme.md` (Chart.yaml v3
   support, registryAliases, private-repo hostRules incl. OCI docker-hostType logins,
   `helmUpdateSubChartArchives`, OCI via docker datasource) —
   https://raw.githubusercontent.com/renovatebot/renovate/44.181.5/lib/modules/manager/helmv3/readme.md
2. [S-r3-2] same tag — `docs/usage/configuration-options.md:2744-2767` — lockFileMaintenance
   ("disabled by default"; delete-lock-then-run-the-tool semantics; weekly schedule).
3. [S-r3-3] same tag — `docs/usage/self-hosted-configuration.md` `binarySource` ("install
   (default): Downloads and installs tools at runtime if running in a Containerbase
   environment") + `docs/usage/getting-started/running.md` "Docker images" (default image
   ships Node only and installs tools at runtime; `-full` ships the tools; containerbase
   cache dir note).
4. [S-r3-4] same tag — `docs/usage/getting-started/running.md` — "GitHub.com token for
   changelogs (and tools)": token used for "some Renovate-specific tools at runtime … to
   increase the hourly API limit".
5. [S-r3-5] renovatebot/renovate discussion #39399 (closed-answered 2025-11-19; Forgejo-
   hosted self-host Renovate; "WARN: No tool releases found"; maintainer answer: api.github.com
   403 rate limit; dup of #37685) and discussion #34665 (same throw in lockfile-maintenance) —
   https://github.com/renovatebot/renovate/discussions/39399 / …/34665
6. Pinned-dist evidence (44.181.5, offline): `modules/manager/helmv3/index.js:21,27-28`
   (lockFileNames, fileMatch, commitMessageTopic), `extract.js:12-69` (v2/api checks,
   git+ skip, oci → getOciChartDep, lockFiles), `utils.js:7-16`, `artifacts.js:17-33,44-46,
   66-75,85-95` (helm repo add/login + helm dependency update; null paths; error→
   artifactErrorResult; generated-line-stripped change test), `common.js` (HELM_* envs →
   privateCacheDir; credential args), `modules/manager/util.js` (resolveToolConstraint),
   `util/exec/containerbase.js:118-122,281-288,294-330,352-370` (helm tool =
   github-releases helm/helm; isDynamicInstall; single-version short-circuit :303; throw
   :316-317; `install-tool` command generation), `modules/datasource/helm/index.js:24`
   (title topic "Helm release {{depName}}"), `workers/repository/update/branch/index.js:107,
   420-446,682-706` (artifact-error gate, removal path, warning-comment gate),
   `update/branch/bump-versions.js:12-24`, `config/options/index.js:672-684,2793+,
   3027-3053,3341-3346` (binarySource default, lockFileMaintenance, constraints
   tool-properties, suppressNotifications default []), `config/presets/internal/
   config.preset.js:24-44` (recommended preset has no enabledManagers),
   `workers/global/config/parse/env.js:164-171` (token→hostRule).
7. Live Forgejo API probes (anonymous): `GET …/pulls?state=all` (104 PRs; 22 helm-titled;
   merged #19/#53/#63 at 11-19 15:29:11–19Z) [S-r3-10]; `GET …/pulls/{53,63,19}/files`
   (yaml-only; open PR file lists dominated by orphan-base noise — comments used instead)
   [S-r3-11]; `GET …/issues/{53,63,19,52,56,58}/comments` (⚠️ Artifact update problem,
   per-lock-file `No tool releases found.`) [S-r3-12]; `GET …/pulls/{97..105}` bodies
   (no credentials-banner today) [S-r3-13].
8. Repo/git evidence: `git fetch origin` (main `b80fae102`); `origin/main:renovate.json`
   full parse (13 legs/10 rules/absent-keys census) [S-r3-8]; repo-wide Chart.yaml↔
   Chart.lock parse over `git show origin/main:` blobs (80-pair scan, drift list)
   [S-r3-9]; `git log` lock-censuses (83/33 GitHub-era; 0 since 11-19); commit stats
   `80c503f72`/`dfd95e3e2`/`73da0c56b`/`d8b12fd0f`/`ed1b1f1b1`/`bcf254c3b`;
   `charts/base/Chart.{yaml,lock}`, `services/home/prod/Chart.{yaml,lock}`
   (wekan ×2 blocks incl. alias boards, app-template ×7), `containers/coder-workspace/
   Dockerfile` (helm/helm ARG v3.22.1 pin = the real target of the hold-rule),
   `tests/renovate/chart-yaml-legs.sh` (k1–k10 legs: manager #9 contract, wekan
   double-leg pin at k5, Dockerfile annotation enumeration gate at k10).

RESULT
status: DONE
chunk: rework-round-2-research-chartlock
files_changed: [.agents/plans/2026/2026-11-cf-135-feat-renovate-forgejo/RESEARCH.md]
commands_run: [git fetch origin + origin/main forensics => pass, repo-wide Chart.yaml<->Chart.lock consistency parse (80 pairs) => pass, renovate.json@main full parse (legs/rules/absent-keys) => pass, dist reads+greps (helmv3 artifacts/extract/common/utils, containerbase, branch/index bump-versions, options, datasource/helm, platform coupling grep) => pass, curl raw docs @44.181.5 (helmv3 readme, configuration-options lockFileMaintenance, self-hosted binarySource, running.md images+github-token) => pass, Forgejo API: pulls census + /pulls/{53,63,19,52}/files + /issues/{19,52,53,56,58,63}/comments + bodies of #97-#105 => pass, searxng search "No tool releases found" => pass (39399/34665), webfetch discussion 39399 => pass, GitHub-era lock-commit log --since=2026-09 census (83/33) => pass]
deviations: none material (organized per the launch brief's A-D slice as in R1/R2 rather than a five-perspective fan-out; the brief's "helm binary in the image" requirement turned out to be inverted — the default image ships NO helm, tools install at runtime, which is exactly where it breaks; the brief's `postUpdateOptions`-vs-customManager hypothesis resolved to "neither — built-in helmv3 with a failing containerbase tool lookup", the customManagers grep for Chart.lock returned zero; two GitHub-API fetch 404s on Dockerfile/manager-doc paths fixed by tree-lookup (manager docs live in lib/*/readme.md since the image is containerbase-built))
friction: webfetch on the full 44.181.5 git tree dumped a 1-line-truncated blob (recovered by grepping the saved tool-output file); one heredoc python scan initially globbed charts/charts due to ls-tree full paths (fixed); sed -n range expressions with command-substituted addresses failed twice (worked around with awk/grep); anonymous /pulls/{n}/files for orphan-based PRs returns base-drift noise capped at 50 entries (the artifact comments gave the decisive signal instead); #103 title vs main's v3.22.1 pin inconsistent and unchased (U16)
open_questions: U13 (canonical token state today), U14 (anonymous install-tool download step), U15 (per-package lockFileMaintenance blocks inertness), U16 (merger of the 15:29Z batch + #103 oddity), U17 (helm4 lock compat — moot with the pin). Recommended delta: renovate.json `"constraints":{"helm":"3.22.1"}` (suite note: m5/t8 keyset counts need the same chunk), owner-side token verification, one manual `helm dependency update charts/base services/home/prod` repair commit, sequence before the R2 gitIgnoredAuthors recovery pass; verification recipe = tick #52's checkbox and expect ~55 yaml+lock pairs + comment auto-removal next 06:17Z pass.
next_suggested: agent-plan: fold the constraints pin + drift-repair + sequencing-against-gitIgnoredAuthors into the rework chunk (C03-style), record "helmv3 owns Chart.lock; custom legs never can; the default image has no tools — tool availability == RENOVATE_GITHUB_COM_TOKEN or a constraints pin" in DECISIONS, and carry U13/U14 as the plan's live-verification ACs (tick #52 post-merge observation).
