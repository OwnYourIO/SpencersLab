# PLAN: Forgejo main-sync jobs — infra `main` → GitHub + dev `main` (non-force, stage-keyed)

feature: 2026/2026-11-cf-119-feat-forgejo-push-main
card: #119 `H9RyH3jp5W6uSMfoK` (AI-Dev) — "Forgejo job to push main"
status: APPROVED 2026-11-09 (re-approval gate, round 2) — single C01 fix round may start
rework: owner pulled the card Review → Rework with four explicit design fixes (DECISIONS 2026-11-09):
(1) no URL detection — jobs key off an instance-side ROLE (the existing Forgejo mirror pattern,
per the owner's gate-round-1 answer), not `forgejo.server_url`;
(2) no repo URL literals — push destinations come from instance-side env (repo) variables;
(3) key renames — no `GITHUB_`/`FORGEJO_` prefixes;
(4) no `backup-proxy` merge — the second job is a plain non-force `main`→dev-`main` push, same
shape as the GitHub one. The 2026-11-07 approval is superseded; re-approval required.

## Goal

One Forgejo Actions workflow in this repo — `.forgejo/workflows/main-sync.yaml` — with two
instance-stage-guarded jobs, each a plain non-force push of `main`: **`push-gh`** pushes `main` to
GitHub `OwnYourIO/SpencersLab`; **`push-dev`** pushes `main` to the dev instance's `main` branch
(`git.scifi.farm/CuratedForest/SpencersLab`). Each job's guard keys on the instance-side repo
variable `ROLE` (`if: vars.ROLE == 'prod'`) — not on the server URL (owner fix 1): on the
prod-stage server (infra, `git.spencerslab.com`) both jobs fire; on the dev-stage server
(`git.scifi.farm`, `ROLE=dev`) **neither fires — that asymmetry is the ping-pong breaker**.
Destinations come from instance-side repo variables (`PUSH_URL_GH`/`PUSH_URL_DEV`), tokens from
repo secrets (`PUSH_TOKEN_GH`/`PUSH_TOKEN_DEV`) — no URL literals, no reserved-prefix key names
(owner fixes 2, 3). Any push failure fails its job (the card's failure contract). The entire
in-repo surface is that one workflow file plus one offline contract suite
(`tests/services/forgejo-main-sync.sh`); the instance-side variables/secrets and the live
first-fire are human-ops legs recorded below (Deployment unchecked — no pipeline stage executes
the rollout).

(`backup-proxy`: retired by owner fix 4 — at most the history note in Out of scope and the
DECISIONS log; it does not appear anywhere in the active design.)

## Out of scope

- **Minting credentials or instance variables/secrets.** The GitHub PAT (UA1) and the dev-Forgejo
  token (UA2 — reuse of the existing `forgejo-token` Bitwarden item, closed OQ-5) are
  human-minted/confirmed; the `ROLE`/`PUSH_URL_*`/`PUSH_TOKEN_*` variables + secrets are
  human-set on the instances (UA3). The repo's ExternalSecret+Bitwarden rule binds K8s objects,
  not Forgejo instance-DB variables/secrets; the precedent (cf-104 UA6) is Bitwarden item +
  one-time UI action.
- **Live first-fire on either forge, and the dev-instance repair** (cf-104 LFS leg,
  `forgejo-s3-secret` ESO not ready). `push-dev` is not live-verifiable this run (OQ-4).
- **The GitHub→infra bootstrap flow itself** (OQ-1, answered: no mirror — manual flow): the plan
  names the one owner action (UA5); it does not build the flow.
- **Any `charts/`, `services/`, `custom-values/`, `containers/` change.** Both instances, both
  runners (where live), ingress and the SSH gateway already exist (EXPLORE §2). The standard repo
  validation trio (`helm lint`/`helm template` + service-trio greps + `OVERRIDE_*` 1:1 sweep) is
  therefore **N/A — no chart or service is touched**; stated, not run.
- **The seven `.github/workflows/` files** — untouched. Note the intended behavior flip: once
  `.forgejo/workflows/` exists, Forgejo stops falling back to it on both instances (EXPLORE §2) —
  desired isolation, the GitHub files would fail there anyway (`ubuntu-26.04`, `GITHUB_TOKEN`).
- **Force-push of any kind.** The card explicitly rejects the built-in force-push mechanism
  (Forgejo's native push mirror — docs: "This will force push… overwrite any changes").
- **URL-based instance detection** — the `startsWith(forgejo.server_url, …)` job guards are
  RETIRED by owner fix 1 ("you're detecting if the repo serves a specific URL. This is
  incorrect."). Replaced by the instance-side `ROLE` variable mechanism (Design below).
- **The `backup-proxy` branch and any merge into it** — RETIRED by owner fix 4 ("for now, just do
  the same kind of push to the dev main branch as you do for github"). The OQ-2 "backup-proxy
  exists" answer and the `--no-ff`-merge design survive in the DECISIONS log as history only.

## Authority

The owner's four design fixes (DECISIONS 2026-11-09) supersede the `server_url`-guard +
`backup-proxy`-merge design this plan carried in its approved 2026-11-07 round. The still-valid
`EXPLORE.md` facts this plan uses as-is:

- Both instances host the **same repo path** `CuratedForest/SpencersLab` (EXPLORE §2, §7) — the
  reason a per-instance discriminator is needed at all; the owner's `ROLE` variable is that
  discriminator (fix 1), and "no job fires on the dev stage" is what keeps the loop from
  forming.
- The automatic `FORGEJO_TOKEN` is same-repo-only (EXPLORE §2) → BOTH `push-gh` and `push-dev`
  are external pushes; each carries its own external credential (`PUSH_TOKEN_*`).
- Runner labels: `ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`, `docker`, `node22`;
  GitHub-style `ubuntu-26.04` routes to no lab runner (EXPLORE §2).
- `push-gh`/`push-dev` run on the infra server, whose only runner is live
  (`gpu-forgejo-runner-gpu` 1/1); `push-dev`'s DESTINATION (the dev instance) is down
  (cf-104 LFS leg) → `push-dev` red at first fire until repair (EXPLORE §2, OQ-4).
- Forgejo's native repository mirror force-pushes — the "built in mechanism" the card rejects;
  any existing mirror is instance-DB state the owner checks/disables (EXPLORE §4; UA4).
- From this worktree only GitHub `origin` is reachable; both forge remotes are unreachable →
  live validation is post-merge / user-owned (EXPLORE §3, §9).

Facts the rework plan session verified (2026-11-09, against the v15.0 LTS line — the running
instances are 15.0.10):

| Fact | Evidence |
|---|---|
| `vars` is a top-level context on the v15.0 line: "A map of the repository variables", e.g. `${{ vars.MYVARIABLE }}` | forgejo.org/docs/v15.0/user/actions/reference/ → Contexts + `vars`, fetched this session |
| `vars` is an accessible context in a **job-level** `if:` — Availability table row `jobs.<job-id>.if` → contexts `env, forgejo, inputs, needs, secrets, vars` (functions `always/cancelled/failure/success`) → `if: vars.ROLE == 'prod'` is supported on the running line | same reference → Availability table, fetched this session |
| Repository variables are set instance-side at `/{owner}/{repo}/settings/actions/variables` ("to be available to the workflows of a single repository"); values are mutable after creation | forgejo.org/docs/v15.0/user/actions/basic-concepts/ → Custom variables, fetched this session |
| Variable name constraints: `[a-zA-Z0-9_]` only, must NOT start with the `FORGEJO_`/`GITHUB_`/`GITEA_` prefix, must not start with a number, case-insensitive, must not be `CI`; precedence: org/user-level variables shadow same-named repo variables | same basic-concepts page → Name constraints + Precedence |
| The same per-instance-variable pattern is platform-blessed: "Repository variables can be used to change the Actions workflows that run. For example, Forgejo uses `vars.ROLE` set on the repo to change which workflows run on different mirrors" | codeberg.org/forgejo/discussions/issues/440 (websearch this session) |
| `actions/checkout@v6` is the version the Forgejo v15.0 quickstart pins | forgejo.org/docs/v15.0/user/actions/quick-start/ (verified in the earlier planning pass) |
| Suite-shape convention: bash, `set -euo pipefail`, `cd "$(git rev-parse --show-toplevel)"`, ok/fail counters, run-from-anywhere, no network | `tests/services/infra-forgejo.sh` (read in the earlier planning pass) |

## Design (config of record)

**One file, two jobs — both plain non-force `main` pushes, both prod-stage-keyed.** The jobs are
separate (they run in parallel on the prod server); each is a checkout + one external push.
**Both share the guard `vars.ROLE == 'prod'`** — on the dev-stage server that guard is false for
both, so the dev server fires NO job: the new ping-pong breaker, replacing the retired URL
guards.

```yaml
# .forgejo/workflows/main-sync.yaml
on:
  push:
    branches: [main]
  workflow_dispatch: {}            # P-1 smoke affordance (owner-confirmed: keep)

jobs:
  push-gh:                         # external push: main -> GitHub
    if: vars.ROLE == 'prod'       # fires ONLY on the prod-stage server (infra)
    runs-on: <one of the five runner labels; ubuntu-24.04 suggested>
    steps:
      - uses: actions/checkout@v6  # automatic token, same-repo clone only
      - name: diag
        run: echo "ROLE=${{ vars.ROLE }}"   # first-fire evidence of the instance-side config
      - name: push main (non-force) to GitHub
        env:
          PUSH_URL: ${{ vars.PUSH_URL_GH }}
          PUSH_TOKEN: ${{ secrets.PUSH_TOKEN_GH }}
        run: |
          set -euo pipefail
          git push "<PUSH_URL with PUSH_TOKEN in the credential slot>" HEAD:refs/heads/main
  push-dev:                        # external push: main -> dev instance main (owner fix 4: plain push, no merge)
    if: vars.ROLE == 'prod'       # fires ONLY on the prod-stage server (infra)
    runs-on: <one of the five runner labels>
    steps:
      - uses: actions/checkout@v6  # automatic token, same-repo clone only
      - name: diag
        run: echo "ROLE=${{ vars.ROLE }}"
      - name: push main (non-force) to dev
        env:
          PUSH_URL: ${{ vars.PUSH_URL_DEV }}
          PUSH_TOKEN: ${{ secrets.PUSH_TOKEN_DEV }}
        run: |
          set -euo pipefail
          git push "<PUSH_URL with PUSH_TOKEN in the credential slot>" HEAD:refs/heads/main
```

- **Instance-discriminator mechanism (fix 1, verified; gate round 1: "reuse the existing ROLE
  pattern").** Each instance's copy of the repo carries the repo variable `ROLE` — `prod` on
  infra (`git.spencerslab.com`), `dev` on the dev instance (`git.scifi.farm`) — set
  instance-side at Settings → Actions → Variables (`ROLE` is the documented Forgejo convention
  for exactly this use: Forgejo switches which workflows run on its mirrors via repo
  `vars.ROLE`). Each job guards on
  `if: vars.ROLE == 'prod'` (the v15.0 reference Availability table lists `vars` among the
  contexts accessible in a job-level `if:` — Authority table). On prod: both jobs fire. On dev:
  neither fires → **the dev-stage server fires no job — the ping-pong breaker**. Fail-safe: an
  unset `ROLE` renders `''`, the guard is false, nothing fires there (no accidental pushing).
- **Destinations + credentials from the instance, not the file (fixes 2, 3).** Push URLs come
  from repo variables `PUSH_URL_GH` / `PUSH_URL_DEV` (full `https://` clone URLs, no
  credentials), tokens from repo secrets `PUSH_TOKEN_GH` / `PUSH_TOKEN_DEV` — both set
  instance-side (UA3). The workflow file contains no repo destination URL literal (no
  `github.com/…` or `git.scifi.farm/…` repo path — the bare `https://` scheme prefix in the
  credential-injection shape is allowed) and no `forgejo.server_url` at all. All five key names
  pass the v15.0 name constraints (no
  `FORGEJO_`/`GITHUB_`/`GITEA_` prefix, not `CI`). Naming scheme: `PUSH_<KIND>_<TARGET>` with
  KIND ∈ {`URL` (variable), `TOKEN` (secret)} and TARGET ∈ {`GH`, `DEV`} — short, consistent,
  the suffix never collides with a reserved prefix.
- **Push shape (recommended; dev picks the exact credential form).** Each push step
  materializes `PUSH_URL`/`PUSH_TOKEN` as step `env` (the "env-injected destination URL" the
  owner asked for), then:
  `rest="${PUSH_URL#https://}"; git push "https://x-access-token:${PUSH_TOKEN}@${rest}" HEAD:refs/heads/main`
  — plain non-force push of the checked-out `main` tip; `x-access-token` is the GitHub
  credential form; the dev Forgejo leg's exact credential slot is dev's choice (first-fire
  evidence at V1/V3 settles any 401). A non-fast-forward refusal or any error exits the step
  non-zero → the job fails.
- **Failure contract (the card's core ask).** Each external push is its own step under `set -euo
  pipefail` with a plain (non-force) `git push` (no `--force`, no `+refspec`): a refused
  non-fast-forward or a network/credential error exits the step non-zero → the job fails. No
  `continue-on-error`, no swallowing. (Forgejo ignores job-level `continue-on-error` anyway —
  EXPLORE §2.)
- **Instance-side config of record** (all owner-set, UA3 — never committed to this repo):

  | Kind | Key | Value | Where |
  |---|---|---|---|
  | variable | `ROLE` | `prod` | infra instance, repo `CuratedForest/SpencersLab` |
  | variable | `ROLE` | `dev` | dev instance, repo `CuratedForest/SpencersLab` |
  | variable | `PUSH_URL_GH` | `https://github.com/OwnYourIO/SpencersLab.git` | infra repo |
  | variable | `PUSH_URL_DEV` | `https://git.scifi.farm/CuratedForest/SpencersLab.git` | infra repo |
  | secret | `PUSH_TOKEN_GH` | fine-grained GitHub PAT (Contents R/W + Workflows) | infra repo (UA1) |
  | secret | `PUSH_TOKEN_DEV` | dev-Forgejo token — value = the existing Bitwarden item `forgejo-token` (dev; closed OQ-5) | infra repo (UA2) |

  Only the infra repo needs the `PUSH_*` keys (only the prod stage fires jobs); the dev repo
  needs only `ROLE=dev`. The GitHub PAT shape is unchanged from the earlier round:
  fine-grained, **Contents R/W + Workflows** (the pushed tree contains `.github/workflows/` —
  EXPLORE §5).

## Chunks

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | `main-sync.yaml` (two stage-keyed push jobs) + offline contract suite | M | 1 | [] | — |

One chunk (DECISIONS #4, owner-confirmed P-2 "fine as shaped"): the workflow and the suite that
proves its contract are one design and land in one commit. No separate test session (Test
Writing unchecked) — the suite is written red-first *inside* the chunk, then the workflow is
written to make it green.

## Wave order

1. C01 (only chunk)

## Commands

Unchanged in shape (the repo has no unit-test suite — the Commands ARE the validation, AGENTS.md
"Pipeline specifics in this repo"). `agent-dev-local` runs them in the chunk; `agent-review`
re-runs them first.

```bash
export PATH=$HOME/.local/bin:$PATH
cd "$(git rev-parse --show-toplevel)"

# C01 — the contract suite (the ticket's test surface):
bash tests/services/forgejo-main-sync.sh        # exit 0, legs t1-t8 all ok

# YAML parse (also covered by the suite's t1):
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .forgejo/workflows/main-sync.yaml

# Quality gate — aislop scans touched files on the PR; run it in the chunk:
npx aislop ci --changes                          # expect: exit 0, ≥80 floor, 0 errors

# Blast radius:
git diff main --name-only
# expect exactly: .forgejo/workflows/main-sync.yaml, tests/services/forgejo-main-sync.sh
```

`helm lint` / `helm template` / the service-trio greps / the `OVERRIDE_*` 1:1 sweep: **N/A** —
no chart, service, or custom-values file is touched (stated per plan guidance).

### Contract suite spec (dev writes it in C01 — there is no test session)

`tests/services/forgejo-main-sync.sh`: bash, `set -euo pipefail`, `cd "$(git rev-parse
--show-toplevel)"`, ok/fail counter convention of `tests/services/infra-forgejo.sh`, run from
anywhere, **no network**, per-leg `ok:` / `fail:` + non-zero exit. Legs (re-pinned for the
reworked design):

1. **t1 shape** — `.forgejo/workflows/main-sync.yaml` exists and YAML-parses
   (`python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))'`). Suite gotcha (kept):
   pyyaml (YAML 1.1) parses the bare `on` key as boolean `True`, so the trigger block is read
   as `doc.get(True) or doc.get('on')`.
2. **t2 trigger** — top-level `on` has `push.branches == [main]` exactly (no other branches, no
   `pull_request`/`schedule`), and `workflow_dispatch` present (P-1 answered: keep).
3. **t3 jobs + stage guards** — `jobs` has exactly two keys, `push-gh` and `push-dev`; each
   job's `if` is exactly the stage guard `vars.ROLE == 'prod'` (one per job, in its own job —
   both jobs fire only on the prod-stage server); NO job's `if` contains `vars.ROLE == 'dev'`
   (the dev-stage server fires no job — the ping-pong breaker); no reference to
   `forgejo.server_url` anywhere in the file (URL detection retired by owner fix 1).
4. **t4 no force** — zero occurrences of `--force`, zero of `+refs`, zero of `git push -f` in
   the workflow file.
5. **t5 destinations + credentials** — `vars.PUSH_URL_GH` and `secrets.PUSH_TOKEN_GH` each
   referenced exactly once, only under `push-gh`; `vars.PUSH_URL_DEV` and
   `secrets.PUSH_TOKEN_DEV` each exactly once, only under `push-dev`; and (new) NO repo
   destination URL literal appears anywhere in the file (no `github.com/…` repo path, no
   `git.scifi.farm/…` repo path — the bare `https://` scheme prefix of the credential-injection
   shape is allowed), and NO `forgejo.server_url` anywhere; the automatic
   `FORGEJO_TOKEN`/`GITHUB_TOKEN` is never the credential of an external push.
6. **t6 failure semantics** — every push `run:` block in BOTH jobs begins with `set -euo
   pipefail`.
7. **t7 runner labels** — every job's `runs-on` ∈ {`ubuntu-latest`, `ubuntu-24.04`,
   `ubuntu-22.04`, `docker`, `node22`}.
8. **t8 push-dev hygiene (re-scoped)** — `push-dev` contains no merge command (`git merge`);
   the string `backup-proxy` appears NOWHERE in the workflow file (owner fix 4 — the branch is
   retired from the active design); `push-dev` is a plain `main` push shaped like `push-gh`
   (checkout + one external push, no branch-creation or merge logic, no secrets beyond
   `PUSH_TOKEN_DEV`).

## Binding rollout (human-ops — never chunks)

No pipeline stage executes this leg: Deployment is unchecked on the card, the stage list ends at
Final Review, and the plan-approval pause is this run's only stop (HITL `Deployment` check is an
**inactive** stop — DECISIONS #2).

### User actions (UA) — before/at merge

- **UA1** — Mint a fine-grained GitHub PAT for `OwnYourIO/SpencersLab`: **Contents R/W +
  Workflows R/W** → Bitwarden Login item `forgejo-push-github` (password = the PAT).
- **UA2** — Dev-Forgejo push credential: **reuse the existing item `forgejo-token`** (dev;
  "Forgejo access token for git.scifi.farm") — confirm repo-write scope on
  `CuratedForest/SpencersLab` (closed OQ-5 answer); mint a fresh dev PAT only if scope is found
  insufficient.
- **UA3** — Set the instance-side config (repo Settings → Actions → Variables / Secrets);
  **confirm-or-set** (gate round 1: "reuse the existing ROLE pattern" — if `ROLE` already
  exists on an instance, align its value rather than invent a second key):
  - **infra** instance, repo `CuratedForest/SpencersLab`:
    - variables: `ROLE=prod`, `PUSH_URL_GH=https://github.com/OwnYourIO/SpencersLab.git`,
      `PUSH_URL_DEV=https://git.scifi.farm/CuratedForest/SpencersLab.git`
    - secrets: `PUSH_TOKEN_GH` = the UA1 token; `PUSH_TOKEN_DEV` = the UA2 token
  - **dev** instance, repo `CuratedForest/SpencersLab`: variable `ROLE=dev` — nothing else
    (any value ≠ `prod` is correct there: no job fires on the dev stage, so the dev repo
    needs no `PUSH_*` keys).
- **UA4** — On **both** instances, check and **disable any existing push/pull mirrors** on
  `CuratedForest/SpencersLab` (the native mirror force-pushes — the built-in mechanism the card
  rejects; OQ-1 answered: no mirror exists, so this is the defensive check; EXPLORE §4).
- **UA5** — Bootstrap: land the merged PR (carrying `.forgejo/`) on **infra `main`** via the
  owner's manual push / existing GitHub→Forgejo path (OQ-1 answered: no mirror — manual flow).
  Until then the workflow is not live on infra.

### Live verification (V) — after merge

- **V1** — First fire on infra (next real `main` push, or a manual `workflow_dispatch`):
  `push-gh` green (GitHub `main` advanced to the same SHA); the diag step's `ROLE=prod` echo
  confirms the instance-side variable is read; `push-dev` red if the dev instance is still down
  (expected — the window below).
- **V2** — If a fire fails at the runner/egress level (action clone from `data.forgejo.org` /
  `code.forgejo.org`, act image from GHCR, egress to `github.com` / `git.scifi.farm`) — the
  closed OQ-3 stance (verify at first fire): diagnose on `gpu-forgejo-runner-gpu`; a
  runner-network fix is a separate workstream (the card demands failure on *push* failure, not
  on runner-network failure).
- **V3** — After the dev instance is repaired (cf-104 LFS leg): `push-dev` green — the dev
  `main` branch advanced to the pushed SHA (a plain push; no merge, no `backup-proxy`).
- **V4** — Owner confirms the instance-side config from the first-fire evidence: `ROLE`
  resolves to `prod` on infra and `dev` on the dev instance (dev: no jobs fire at all — check
  the Actions tab shows zero triggered jobs after a dev `main` push), and the `PUSH_URL_*`
  values read the intended destinations. A mis-set `ROLE` surfaces as "no jobs fire" on the
  prod server; correcting the variable (UA3) is the fix.

### Expected-red window (flagged at approval)

While the dev instance is down (cf-104 LFS leg), the **`push-dev`** job fails at its dev-push
step on every infra `main` push (the parallel `push-gh` / GitHub job still lands green). That is
the job behaving exactly as the card specifies ("if it does [fail] I do expect the job to
fail"), not a defect. Expect a red `push-dev` (and thus a red workflow run) until V3.

## Open questions

**Rework round — pending re-approval (2026-11-09).** The owner's four design fixes retired the
earlier round's design questions: OQ-1 (no mirror — manual flow), OQ-2 (backup-proxy — retired
by fix 4, history only), OQ-3 (egress — verify at first fire), OQ-5 (reuse the `forgejo-token`
item — only the secret KEY renamed), P-1 (`workflow_dispatch` kept) all stand as answered and
are folded in above. The genuine remaining gaps are the two instance-side choices the rework
surfaces; each lists the plan's recommendation first.

- **OQ-4 (dev instance down) — confirmed fact, not a gate question:** the dev Forgejo is down
  (cf-104 LFS S3-secret leg). The plan treats it as the expected-red window above — `push-dev`
  red until repair; not a defect, not a chunk failure.
- **OQ-6 (instance-discriminator key + values) — ANSWERED at gate round 1 (2026-11-09): "Lets
  reuse the existing ROLE pattern."** → the key is `ROLE` (the documented Forgejo mirror
  convention — Forgejo switches which workflows run on its mirrors via repo `vars.ROLE`;
  Authority table), repo-level scope on each instance's `CuratedForest/SpencersLab`, not a new
  `STAGE` variable. Both jobs pin `if: vars.ROLE == 'prod'`. Residual to confirm (recommendation
  first): **values `prod` (infra) / `dev` (dev), per the fix-1 wording** — if `ROLE` already
  exists on your instances with other values, the one hard requirement is that the INFRA repo's
  `ROLE` read `prod` (the guard pins it); the dev instance needs any value ≠ `prod` (UA3 is
  written confirm-or-set, so either way it is one UI step). Impact: instance-side config only —
  the workflow file and the suite are unaffected by the exact dev-side value.
- **OQ-7 (destination URL variable key names + values) — NEW, owner to confirm.** The plan
  proposes repo variables `PUSH_URL_GH = https://github.com/OwnYourIO/SpencersLab.git` and
  `PUSH_URL_DEV = https://git.scifi.farm/CuratedForest/SpencersLab.git` — full `https://` clone
  URLs, no credentials embedded (the token is injected from `PUSH_TOKEN_*` at push time; the
  scheme stays `https://` for that shape). **Recommendation: accept the key names and URL
  shapes** (naming follows the same `PUSH_<KIND>_<TARGET>` scheme as the secrets; none hits a
  reserved prefix). Best guess: these are the owner's intended destinations. Impact:
  instance-side config (UA3) — if the actual clone URLs differ (host/path/scheme), only the
  variable values change; the workflow file and the suite are unaffected.

## Risks / assumptions

- **Ping-pong** is structurally prevented by the prod-only stage guard: on the dev-stage server
  (`ROLE=dev`) no job's `if` is true, so dev never pushes back (EXPLORE §7, reworked). Contract
  leg t3 pins both guards + the absence of any `vars.ROLE == 'dev'` job.
- **GitHub re-trigger:** `push-gh`'s GitHub `main` push re-fires GitHub's path-filtered push
  workflows (`release.yaml` on `charts/**`, `docker-build.yaml` on `containers/**`, the render
  suites) — behavior that already exists for any GitHub `main` push (EXPLORE §1);
  chart-releaser is idempotent via `skip_existing`.
- **First-fire egress (OQ-3, closed as verify-at-first-fire):** unverified — the gpu runner's
  egress to `data.forgejo.org`/`code.forgejo.org` (action clones), GHCR (act images),
  `github.com`, and `git.scifi.farm`. The diag step + `workflow_dispatch` (P-1) make a failure
  diagnosable in one look.
- **Dev outage (OQ-4):** `push-dev` not live-verifiable this run; `push-dev` red until repair
  (expected-red window).
- **ROLE unset / mis-set:** if `ROLE` is unset or misspelled on the prod server, no job fires
  there — fail-safe (no accidental pushing) but also no fan-out until corrected (V4). An
  org/user-level `ROLE` would shadow the repo-level one (v15.0 precedence) — keep it at repo
  scope.
- **URL variable shape:** the token-injection shape assumes `PUSH_URL_*` values are full
  `https://` clone URLs; a non-`https` or credentials-embedded value would break the push
  (OQ-7, checked at V4).
- **Bootstrap ordering (OQ-1, answered: manual flow):** until UA5 the workflow is not live on
  infra and nothing fans out; the current GitHub→forge flow continues unchanged in the meantime.

## Follow-ups (not this ticket)

- Runner-network egress fix, if V2 shows egress blocked (separate ticket; OQ-3).
- Dev-instance repair is the cf-104 LFS leg (separate workstream; OQ-4).
- Any `backup-proxy`-branch policy: deferred by the owner ("for now") — if wanted later, it is a
  new design on top of the now-plain `push-dev` (retired by owner fix 4; see the DECISIONS log
  history).
