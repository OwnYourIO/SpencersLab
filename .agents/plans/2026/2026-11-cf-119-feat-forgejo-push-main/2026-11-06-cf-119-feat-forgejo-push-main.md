# PLAN: Forgejo main-sync jobs — infra `main` → GitHub + dev (non-force), dev `main` → `backup-proxy`

feature: 2026/2026-11-cf-119-feat-forgejo-push-main
card: #119 `H9RyH3jp5W6uSMfoK` (AI-Dev) — "Forgejo job to push main"
status: APPROVED 2026-11-07 (plan-approval gate) — single C01 chunk loop may start

## Goal

One Forgejo Actions workflow in this repo — `.forgejo/workflows/main-sync.yaml` — with two
instance-guarded jobs: **`push-main`** on the infra instance (`git.spencerslab.com`), which on
every push to `main` non-force pushes `main` to GitHub `OwnYourIO/SpencersLab` and to the dev
instance `git.scifi.farm` and fails the run if either push fails; and **`backup-proxy-merge`** on
the dev instance (`git.scifi.farm`), which on the same `main` sync merges `main` into the
`backup-proxy` branch — owner-confirmed **existing** on the dev instance (OQ-2 answer, 2026-11-06):
the `--no-ff` merge is the expected path, a conflict fails the job for the owner to resolve by
hand, and create-from-`main` remains only as the absent-branch fallback — using the instance's
automatic `FORGEJO_TOKEN` and no secrets. The entire in-repo surface is that one workflow file plus one
offline contract suite (`tests/services/forgejo-main-sync.sh`); credentials, the instance-side
Actions secrets, and live first-fire are human-ops legs recorded below (Deployment unchecked —
no pipeline stage executes the rollout).

## Out of scope

- **Minting credentials or instance secrets.** The GitHub PAT and the dev-Forgejo push token are
  human-minted (UA1/UA2); the two infra-instance Actions secrets are human-set (UA3). The
  repo's ExternalSecret+Bitwarden rule binds K8s objects, not Forgejo instance-DB secrets; the
  repo precedent (cf-104 UA6) is Bitwarden item + one-time action in the Forgejo UI.
- **Live first-fire on either forge, and the dev-instance repair** (cf-104 LFS leg,
  `forgejo-s3-secret` ESO not ready). Job 2 is written but not live-verifiable this run.
- **The GitHub→infra bootstrap flow itself** (OQ-1): the plan names the one owner action (UA5);
  it does not build the flow.
- **Any `charts/`, `services/`, `custom-values/`, `containers/` change.** Both instances, both
  runners (where live), ingress and the SSH gateway already exist (EXPLORE §2). The standard repo
  validation trio (`helm lint`/`helm template` + service-trio greps + `OVERRIDE_*` 1:1 sweep) is
  therefore **N/A — no chart or service is touched**; stated, not run.
- **The seven `.github/workflows/` files** — untouched. Note the intended behavior flip: once
  `.forgejo/workflows/` exists, Forgejo stops falling back to it on both instances (EXPLORE §2) —
  desired isolation, the GitHub files would fail there anyway (`ubuntu-26.04`, `GITHUB_TOKEN`).
- **Force-push of any kind.** The card explicitly rejects the built-in force-push mechanism
  (Forgejo's native push mirror — docs: "This will force push… overwrite any changes").
- **`backup-proxy` branch policy beyond** "merge `main` into the existing branch with `--no-ff`"
  (OQ-2 answered 2026-11-06: the branch **exists** on the dev instance, possibly with unique
  commits; a merge conflict fails the job and the owner resolves it by hand). Create-from-`main`
  survives only as the fallback for the absent-branch case (not the expected state).

## Authority

`EXPLORE.md` (this folder) is the grounding — its facts are used as-is, not re-derived:

- No `.forgejo/` (or `.gitea/`) directory exists; the forge surface is
  `.forgejo/workflows/*.yaml` (EXPLORE §2).
- Both instances host the **same repo path** `CuratedForest/SpencersLab` → repo-level guards are
  impossible; the `forgejo.server_url` guard is mandatory on both jobs or the instances
  ping-pong (EXPLORE §2, §7).
- The automatic `FORGEJO_TOKEN` is same-repo-only, has write permission, and its pushes do not
  re-trigger the repo's workflows → Job 2 uses it; Job 1's two external pushes cannot (EXPLORE §2).
- Runner labels: `ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`, `docker`, `node22`;
  GitHub-style `ubuntu-26.04` routes to no lab runner (EXPLORE §2).
- Job 1 (infra) has a live runner (`gpu-forgejo-runner-gpu` 1/1); Job 2 (dev) does not — the dev
  instance is down (cf-104 LFS leg) (EXPLORE §2, OQ-4).
- Forgejo's native repository mirror force-pushes — the "built in mechanism" the card rejects; any
  existing mirror is instance-DB state the owner must check/disable (EXPLORE §4).
- From this worktree only GitHub `origin` is reachable; both forge remotes are unreachable → live
  validation is post-merge / user-owned (EXPLORE §3, §9).

Facts the plan session verified itself (2026-11-06):

| Fact | Evidence |
|---|---|
| `startsWith(searchString, searchValue)` is a supported expression function in job/step `if:` on the running Forgejo line (both instances 15.0.10 = v15.0 LTS family); it is case-insensitive | forgejo.org/docs/v15.0/user/actions/basic-concepts/ (Functions), fetched this session; v17.0 page identical |
| `forgejo.server_url` is a workflow context field on v15.0 | forgejo.org docs v15.0 reference (EXPLORE §2 also confirmed the raw v15.0 doc) |
| The Forgejo v15.0 quickstart pins `actions/checkout@v6` | forgejo.org/docs/v15.0/user/actions/quick-start/ ("Using an action to check out your code"), fetched this session |
| Sibling cf- plan-file convention: `<date>-<full-slug>.md` | `2026-10-cf-50-*/2026-10-25-cf-50-feat-prevent-multiple-agent-board-coords.md`, `2026-11-cf-106-*/2026-11-03-cf-106-feat-coord-fixes.md` |
| Suite-shape convention: bash, `set -euo pipefail`, `cd "$(git rev-parse --show-toplevel)"`, ok/fail counters, run-from-anywhere, no network | `tests/services/infra-forgejo.sh` (read this session) |

## Design (config of record)

**One file, two jobs.** Both jobs live in one repo, so one workflow run per `main` push; the two
instance guards sit side by side in one place. A single file keeps the no-ping-pong invariant
co-located (DECISIONS 2026-11-06, #5).

```yaml
# .forgejo/workflows/main-sync.yaml
on:
  push:
    branches: [main]
  workflow_dispatch: {}            # P-1 smoke affordance (owner-confirmed: keep)

jobs:
  push-main:                       # fires ONLY on the infra instance
    if: startsWith(forgejo.server_url, 'https://git.spencerslab.com')
    runs-on: <one of the five runner labels; ubuntu-24.04 suggested>
    steps:
      - uses: actions/checkout@v6  # automatic token, same-repo clone only
      - diag: echo forgejo.server_url + forgejo.repository   # first-fire evidence
      - push GitHub: non-force `git push` of main → https://github.com/OwnYourIO/SpencersLab
                     (credential = secrets.GITHUB_PUSH_TOKEN)
      - push dev:    non-force `git push` of main → https://git.scifi.farm/CuratedForest/SpencersLab
                     (credential = secrets.FORGEJO_DEV_PUSH_TOKEN)
                     # each run block: set -euo pipefail; plain `git push` — no --force,
                     # no +refspec; a non-fast-forward refusal exits non-zero
  backup-proxy-merge:              # fires ONLY on the dev instance
    if: startsWith(forgejo.server_url, 'https://git.scifi.farm')
    runs-on: <one of the five runner labels>
    steps:
      - uses: actions/checkout@v6  # automatic FORGEJO_TOKEN (same-repo write)
      - diag: echo forgejo.server_url
      - merge main → backup-proxy, no secrets referenced
        (OQ-2 answered: the branch EXISTS — the merge is the expected path):
          branch present → `git merge --no-ff` main into backup-proxy, push
          branch absent  → create from main (new-branch push, non-force by construction) —
                           fallback only (the confirmed state is "present")
          conflict / non-ff refusal → non-zero exit (never --force, never auto-resolve —
                           the owner resolves conflicts by hand)
```

- **Guard semantics.** `startsWith(forgejo.server_url, '<instance>')` — tolerant of the
  trailing-slash/case variance in the rendered value (docs show `https://code.forgejo.org` bare;
  infra `ROOT_URL` is `https://git.spencerslab.com/` — EXPLORE §7). The two guard literals are
  unrelated strings, so exactly one job fires per push per instance: the ping-pong breaker
  (EXPLORE §7). The diag step makes the exact rendered `server_url` recoverable from the first
  live run if a guard ever misbehaves (OQ-3).
- **Failure contract (the card's core ask).** Each external push is its own step under
  `set -euo pipefail` with a plain (non-force) `git push`: a refused non-fast-forward or a
  network/credential error exits the step non-zero → the job fails. No `continue-on-error`,
  no swallowing. (Forgejo ignores job-level `continue-on-error` anyway — EXPLORE §2.)
- **Secrets of record** (infra instance, repo `CuratedForest/SpencersLab`, instance-side — never
  committed; the repo's secret rules do not cover instance-DB secrets):

  | Actions secret key | Purpose | Bitwarden mint |
  |---|---|---|
  | `GITHUB_PUSH_TOKEN` | push `main` → `github.com/OwnYourIO/SpencersLab` | NEW Login item `forgejo-push-github` (UA1) |
  | `FORGEJO_DEV_PUSH_TOKEN` | push `main` → `git.scifi.farm/CuratedForest/SpencersLab` | existing item `forgejo-token` (dev; "Forgejo access token for git.scifi.farm") — **reused per the OQ-5 answer**; UA2 confirms its repo-write scope |

  Job 2 references **no** secret (automatic token). GitHub PAT shape: fine-grained,
  **Contents R/W + Workflows** (the pushed tree contains `.github/workflows/` — EXPLORE §5).
  Name-rule check: both keys match `[A-Za-z0-9_]`, no `FORGEJO_`/`GITHUB_`/`GITEA_` prefix,
  not `CI` (EXPLORE §2).

## Chunks

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | `main-sync.yaml` workflow + offline contract suite | M | 1 | [] | — |

One chunk (DECISIONS #4): the workflow and the suite that proves its contract are one design and
land in one commit. No separate test session (Test Writing unchecked) — the suite is written
red-first *inside* the chunk, then the workflow is written to make it green.

## Wave order

1. C01 (only chunk)

## Commands

The repo has no unit-test suite — the Commands ARE the validation (AGENTS.md "Pipeline specifics
in this repo"). `agent-dev-local` runs them in the chunk; `agent-review` re-runs them first.

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
anywhere, **no network**, per-leg `ok:` / `fail:` + non-zero exit. Legs:

1. **t1 shape** — `.forgejo/workflows/main-sync.yaml` exists and YAML-parses
   (`python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))'`).
2. **t2 trigger** — top-level `on` has `push.branches == [main]` exactly (no other branches, no
   `pull_request`/`schedule`), and `workflow_dispatch` present (P-1 answered: keep). Suite
   gotcha: pyyaml (YAML 1.1) parses the bare `on` key as boolean `True`, so the
   trigger block is read as `doc.get(True) or doc.get('on')`.
3. **t3 jobs + guards** — `jobs` has exactly two keys, `push-main` and `backup-proxy-merge`;
   `push-main.if` is the guard `startsWith(forgejo.server_url, 'https://git.spencerslab.com')`;
   `backup-proxy-merge.if` is the guard `startsWith(forgejo.server_url, 'https://git.scifi.farm')`;
   each guard literal occurs exactly once in the file, in its own job; the two literals differ.
4. **t4 no force** — zero occurrences of `--force`, zero of `+refs`, zero of `git push -f` in the
   workflow file.
5. **t5 targets + secrets** — `github.com/OwnYourIO/SpencersLab` and
   `git.scifi.farm/CuratedForest/SpencersLab` both appear as push destinations under `push-main`;
   `secrets.GITHUB_PUSH_TOKEN` and `secrets.FORGEJO_DEV_PUSH_TOKEN` each occur exactly once, only
   in `push-main`; the automatic `FORGEJO_TOKEN`/`GITHUB_TOKEN` is never the credential of an
   external push.
6. **t6 failure semantics** — every `run:` block in `push-main` begins with `set -euo pipefail`.
7. **t7 runner labels** — every job's `runs-on` ∈ {`ubuntu-latest`, `ubuntu-24.04`,
   `ubuntu-22.04`, `docker`, `node22`}.
8. **t8 job-2 hygiene** — `backup-proxy-merge` references no `secrets.*` key, contains no
   `github.com/` URL, and names the `backup-proxy` branch in its merge/push step.

## Binding rollout (human-ops — never chunks)

No pipeline stage executes this leg: Deployment is unchecked on the card, the stage list ends at
Final Review, and the plan-approval pause is this run's only stop (HITL `Deployment` check is an
**inactive** stop — DECISIONS #2).

### User actions (UA) — before/at merge

- **UA1** — Mint a fine-grained GitHub PAT for `OwnYourIO/SpencersLab`: **Contents R/W +
  Workflows R/W** → Bitwarden Login item `forgejo-push-github` (password = the PAT).
- **UA2** — Dev-Forgejo push credential: the OQ-5 answer is **reuse the existing item**
  `forgejo-token` (dev; "Forgejo access token for git.scifi.farm") — confirm it has repo-write
  scope on `CuratedForest/SpencersLab` (mint a new dev-instance PAT + new item only if scope is
  found insufficient).
- **UA3** — On the **infra** instance, set two Actions repo secrets for
  `CuratedForest/SpencersLab` (Settings → Actions → Secrets): `GITHUB_PUSH_TOKEN` = UA1,
  `FORGEJO_DEV_PUSH_TOKEN` = UA2.
- **UA4** — On **both** instances, check and **disable any existing push/pull mirrors** on
  `CuratedForest/SpencersLab` (the native mirror force-pushes — the built-in mechanism the card
  rejects; EXPLORE §4).
- **UA5** — Bootstrap: land the merged PR (carrying `.forgejo/`) on **infra `main`** via the
  owner's manual push / existing GitHub→Forgejo path (OQ-1 answered 2026-11-06: **no mirror
  exists — manual flow**). Until then the workflow is not live on infra.

### Live verification (V) — after merge

- **V1** — First `push-main` fire on infra (next real `main` push, or a manual
  `workflow_dispatch`): run green; GitHub `main` advanced to the same SHA; dev push succeeded.
- **V2** — If the first fire fails at the runner/egress level (action clone from
  `code.forgejo.org`, act image from GHCR, egress to `github.com` / `git.scifi.farm`) — OQ-3:
  diagnose on `gpu-forgejo-runner-gpu`; a runner-network fix is a separate workstream (the card
  demands failure on *push* failure, not on runner-network failure).
- **V3** — After the dev instance is repaired (cf-104 LFS leg): `push-main` fully green; first dev
  `main` push fires `backup-proxy-merge` → `--no-ff` merge into the existing `backup-proxy`
  (OQ-2 answered: the branch exists). If that first merge conflicts, the job fails — the owner
  resolves the conflict by hand and the next fire retries.
- **V4** — After the first successful merge, the owner confirms the merged `backup-proxy` state
  matches the branch's intended purpose (existence itself was confirmed by the OQ-2 answer).

### Expected-red window (flagged at approval)

While the dev instance is down, **every** `push-main` run fails at the dev-push step. That is the
job behaving exactly as the card specifies ("if it does [fail] I do expect the job to fail"), not
a defect. The GitHub leg lands first (step order). Expect red infra runs until V3.

## Open questions

**Batched round — CLOSED 2026-11-06** (owner answers received and folded into this plan). These
were owner-knowledge questions — the coordinator ruled **no research commission**: board/instance
state and owner intent, not web-researchable. None blocked C01. The one delta versus best guess
(OQ-2) required wording changes only, because the merge step was already branch-agnostic
(`ls-remote` absent → create; present → merge); DECISIONS 2026-11-06 records the round.

- **OQ-1 (topology / bootstrap) — ANSWERED: "No mirror — manual flow."** No native Forgejo
  push/pull mirror exists; GitHub `main` reaches the infra instance by the owner's manual push /
  existing GitHub→Forgejo path, which is UA5's bootstrap action (best guess confirmed as the
  answer). UA4 stays as the defensive check: if a push mirror is ever found, disable it. No design
  change — wording folded into Out of scope (bootstrap), UA5.
- **OQ-2 (`backup-proxy`) — ANSWERED: "Exists — keep --no-ff merge." DELTA versus best guess:**
  the branch **exists** on `git.scifi.farm/CuratedForest/SpencersLab`, possibly with unique
  commits. The expected first fire is the `--no-ff` merge into it; a merge conflict fails the job
  (the card's failure contract) and the owner resolves it by hand. Create-from-`main` is retained
  only as the absent-branch fallback. Wording changes caused: Goal, Out of scope, Design merge
  step (present = expected path, absent = fallback), V3, V4. No logic change — the merge step and
  contract leg t8 (which names the `backup-proxy` branch in the merge/push step) already hold for
  the confirmed state; t8 re-verified accurate, unchanged.
- **OQ-3 (runner egress) — ANSWERED: "Yes/unknown — verify at first fire."** Best guess
  confirmed: assume egress works (the runner already pulls GHCR images and dials out HTTPS);
  verify at V1/V2 — the diag step + `workflow_dispatch` make any failure diagnosable in one look.
  If egress is blocked, the fix is a separate runner-network ticket (Follow-ups), not a change to
  this plan's files.
- **OQ-4 (dev instance down) — CONFIRMED FACT** (carried from the coordinator, not re-asked): the
  dev Forgejo is down today (cf-104 LFS S3-secret leg). The plan treats it as the
  expected-red window — Job 1's dev-push step red until repair, by design, not a defect.
- **OQ-5 (dev push credential) — ANSWERED: "Yes — reuse it."** `FORGEJO_DEV_PUSH_TOKEN` = the
  existing Bitwarden item `forgejo-token` (dev; "Forgejo access token for git.scifi.farm");
  UA2 confirms its repo-write scope on `CuratedForest/SpencersLab` (mint a fresh PAT only if
  scope is found insufficient). Wording folded into the Secrets of record table and UA2. The
  workflow file and the secret-key name are unchanged.
- **P-1 (`workflow_dispatch`) — ANSWERED: "Keep it."** `workflow_dispatch` (no inputs) stays in
  `on:` as the smoke affordance, and contract leg t2 keeps asserting it.
- **P-2 (single chunk) — ANSWERED: "Fine as shaped."** One chunk (C01): workflow + contract
  suite, the suite written red-first inside the chunk; no separate test session.
- **P-3 (plan-file name) — ANSWERED: "Keep the cf-NN name."**
  `2026-11-06-cf-119-feat-forgejo-push-main.md` stands as the plan of record.

## Risks / assumptions

- **Ping-pong** is structurally prevented by the two mutually-exclusive `server_url` guards
  (EXPLORE §7); contract leg t3 pins both.
- **GitHub re-trigger:** Job 1's GitHub `main` push re-fires GitHub's path-filtered push
  workflows (`release.yaml` on `charts/**`, `docker-build.yaml` on `containers/**`, the render
  suites) — behavior that already exists for any GitHub `main` push (EXPLORE §1);
  chart-releaser is idempotent via `skip_existing`.
- **First-fire egress (OQ-3)** unverified — the diag step + `workflow_dispatch` (P-1) make a
  failure diagnosable in one look.
- **Dev outage (OQ-4):** Job 2 not live-verifiable this run; Job 1's dev leg red until repair
  (expected-red window).
- **`server_url` exact format** only knowable live — `startsWith` is tolerant; the diag step
  records the value.
- **Bootstrap ordering (OQ-1):** until UA5 the workflow is not live on infra and nothing fans
  out; the current GitHub→forge flow continues unchanged in the meantime.

## Follow-ups (not this ticket)

- Runner-network egress fix, if V2 shows egress blocked (separate ticket; OQ-3).
- Dev-instance repair is the cf-104 LFS leg (separate workstream; OQ-4).
- Any `backup-proxy` retention/pruning policy (after V4 confirms the first merged state).
