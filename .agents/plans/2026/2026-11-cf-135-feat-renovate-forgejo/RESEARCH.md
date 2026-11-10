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
