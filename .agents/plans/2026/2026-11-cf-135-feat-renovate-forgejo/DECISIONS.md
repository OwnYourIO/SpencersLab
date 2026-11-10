# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions
- EXPLORE.md + RESEARCH.md are the ground for this ticket; where docs and the pinned
  Renovate 44.181.5 dist differ, the dist wins (RESEARCH §8 R8).
- Contract suites follow the house shape of `tests/services/forgejo-main-sync.sh`:
  static-only, `ok:`-per-check + one `PASS:` line, python3 heredocs, YAML-1.1 `on:` read
  as `doc.get(True) or doc.get('on')`.
- Instance identity and credentials never enter the workflow file — contexts
  (`github.server_url`/`github.repository`) + secret refs only, per the cf-119 main-sync
  convention; the file stays safe to host on both instances.
- Gate semantics for validation: "existing suites pass" = no NEW failure vs the recorded
  baseline reds (Commands §4 in the plan file).

## Decisions
- 2026-11-10 plan: D1 instance/gate — job guard `if: vars.ROLE == 'dev'` (dev instance
  `git.scifi.farm` executes; card's explicit "gated for ROLE=dev" + "test in dev" beats
  the title's `git.spencerslab.com`, which names the canonical forge, not the stage).
  Rejected: `vars.ROLE != 'prod'` (fires on ANY unset-ROLE host — breaks the fail-safe
  that unset fires nothing, main-sync header precedent); two-job prod/dev matrix (extra
  surface for a move the card stages in dev). Infra flip = UA6 one-line follow-up. Open
  as Q1 for the batched round.
- 2026-11-10 plan: D2 token identity — dedicated bot-user PAT via
  `secrets.RENOVATE_TOKEN` (RESEARCH §2b). Rejected: automatic `FORGEJO_TOKEN` (§2a) —
  PR-creation on public repos works today but is documented hack-on-a-change-path (#13739
  open, #14026 read-only-default intent = R3) and its git-transport form is unproven (U2).
  Renovate hard-requires a token (F2), so "none" is not an option. Open as Q2.
- 2026-11-10 plan: D3 containment — disable the `github-actions` manager for
  `.forgejo/**` via one packageRule appended at the array end (RESEARCH §4c, R2: 44.181.5
  ships `ubuntu-26.04` as a valid `runs-on` bump — a label no lab runner advertises, F11 —
  and validates bare `uses:` tags against github.com, not the `data.forgejo.org` mirror
  whose inventory is unproven, F10). Accepted consequence: `main-sync.yaml`'s
  `actions/checkout@v6` pin also stops being PR'd (mirror freshness unknown — containment
  is the safe side). `.github/**` stays tracked (GitHub-native there). Rejected: ignore
  only depType `github-runner` (leaves the mirror-tag class live); consciously opting into
  tracking (adds a mirror-freshness dependency the ticket can't verify). Open as Q3.
- 2026-11-10 plan: D4 self-update — track the workflow image pin with a dedicated
  `customManagers` regex leg scoped to `.forgejo/workflows/renovate.yaml` (RESEARCH
  §4c(ii)); immutable full-patch tag `44.181.5` + digest comment (floating tags stick at
  first-pull forever on the act runner, §4a). No automerge on the self-bump — human-merged
  (a broken new image would fail the next run silently on a schedule). Rejected: manual
  bump posture like the act images (acceptable but RESEARCH rules silent staleness the
  worst outcome — an un-annotated, unmentioned image line is out); digest-only pin
  (heavier regex style). Open as Q3.
- 2026-11-10 plan: D5 limits shape — set `prHourlyLimit: 0` / `prConcurrentLimit: 0` at
  `renovate.json:9-10`; deleting keeps limits (defaults 2/10, F12; EXPLORE §2 headline).
  `branchConcurrentLimit` stays unset → inherits the 0. Card's "remove the limits" = zeros.
- 2026-11-10 plan: D6 trigger shape — `on: {schedule: [{cron: '17 6 * * *'}],
  workflow_dispatch: {}}`; schedules fire only from the default branch (RESEARCH [1]) so
  branch testing rides workflow_dispatch; POSIX 5-field, quoted (bare `*` is YAML-special
  [15]); UTC 06:17 ≈ late-evening America/Denver, quiet minute (R4: capacity:1 runner is
  shared with main-sync jobs). Rejected: push trigger (Renovate on every push = churn),
  round-hour cron (collision-prone).
- 2026-11-10 plan: D7 `ignoreTests: true` stays (EXPLORE §2: with no Forgejo PR CI it is
  load-bearing for the four existing automerge schedules). Adding a Forgejo-side render-test
  workflow for gate parity is out of scope (own follow-up ticket if the owner wants it).
  Open as Q8.
- 2026-11-10 plan: D8 no `uses:` steps in the Renovate job — container job + Renovate's own
  token-auth clone/push (F4); act images' Node is too old for 44.x engines anyway (F9),
  and mirror inventory beyond actions/checkout is unproven. Rejected:
  `uses: renovatebot/github-action` (404 on the mirror, EXPLORE §3), full-URL action from
  github.com [15] (extra egress + socket gymnastics), `npx renovate` on the act image
  (second-class per RESEARCH §4b).
- 2026-11-10 plan: D9 step failure posture — plain `set -euo pipefail` steps, step failure
  = red run; `renovate --version` diag step proves the PATH assumption (U4) cheaply before
  the run step. Exit-code-vs-ERROR semantics (U3) decided after one controlled first fire
  (UA5), not from docs.
- 2026-11-10 plan: D10 chunking — two chunks (config subsystem; workflow + its suite),
  not RESEARCH's suggested three: the "user runbook + first-fire plan" has no in-repo
  artifact of its own — dev writing into `.agents/plans/` collides with plan-folder write
  rules — so it lives in the plan file's User actions section instead. Suite-owned edits
  to existing test files (kubernetes-mcp-version-floor k2 8→10) are test-session work, not
  dev work (tests are read-only to dev).
- 2026-11-10 plan: D11 endpoint/env names — `RENOVATE_ENDPOINT: ${{ github.server_url }}`
  (per-instance public root; the gitea/forgejo platform appends `/api/v1` itself and
  tolerates trailing forms, F3; keeps the file instance-neutral). `RENOVATE_*` env mapping
  per F5; `RENOVATE_GITHUB_COM_TOKEN` special-cases into the github.com hostRule with no
  `detectHostRulesFromEnv` needed (F6).

## Round 2 — batched question round (owner rulings 2026-11-10, folded by plan)
- 2026-11-10 plan: D12 Q3 CONTAINMENT OVERRIDE — owner ruled "no containment": no
  `github-actions` packageRule lands. The manager reading `.forgejo/**` is accepted churn:
  `runs-on` label bumps (dist probe: 44.181.5 offers `ubuntu-24.04 → ubuntu-26.04`,
  major/breaking) and bare `uses:` bumps (main-sync's `actions/checkout@v6`, tags resolved
  against github.com, `data.forgejo.org` mirror carry unproven). Rejected: the round-1
  plan's `.forgejo/**` disable rule (owner call), depType-`github-runner`-only ignore
  (partial containment, contradicts the ruling). Safety nets instead of a ban: both
  classes human-merged (verified absent from every automerge `matchPackageNames` list in
  the config), and the two contract suites' t7 label whitelists act as the merge-review
  tripwire. Supersedes D3.
- 2026-11-10 plan: D13 Q3 reconciliation, ground-ruled at the dist — the self-update regex
  leg is DROPPED. Grounding: 44.181.5 `github-actions/index.js` default `managerFilePatterns`
  includes `\.(?:github|gitea|forgejo)/(?:workflows|actions)` paths (`.forgejo/workflows/`
  ✓); `extract.js:153` extracts `jobs.<id>.container` via the dockerfile manager's `getDep`
  → depType `container`, datasource `docker`; scratch-repo probe 2026-11-10
  (`/tmp/opencode/cf135-q3-probe`, pinned CLI, network lookup): 2 deps extracted from the
  planned workflow shape — `ghcr.io/renovatebot/renovate 44.181.5→44.226.3` (minor) and
  `ubuntu 24.04→26.04` (major) — with the broad Grafana `/\.ya?ml$/` customManager scoring
  the file as "No dependencies found" (annotation-scoped, no claim). Conclusion: the native
  manager ALREADY renovates the image line; a dedicated leg would double-match (the
  duplicate-dependency warning class this repo's own containers/ ARG description
  documents avoiding). Alternative rejected: keep-regex-plus-narrow-suppression (a
  github-actions suppression packageRule is exactly what the owner banned). No
  grouping/automerge rule needed — default human-merged bump PRs match the wanted posture.
  Supersedes D4's leg; the immutable full-patch tag (D4) stays and every native bump value
  is itself full-patch (probe: newValue `44.226.3`).
- 2026-11-10 plan: D14 Q3 consequences — `renovate.json` net delta = the two limit values
  ONLY (9 rules / 13 legs unchanged; suites m3/m4/t8 pin the absence). The round-1 k2
  count flip (8→10) loses its trigger: k2's stale count joins `chart-yaml-legs` k5/k10 as
  an untouched pre-existing red with the no-NEW-failures fingerprint. C01 shrinks M→S; the
  config↔workflow cross-file dependency dissolves → both chunks wave 1, independent
  (STATE.json's round-1 stub is superseded; coord syncs at approval).
- 2026-11-10 plan: D15 Q4 DONOR DIRECTION — `RENOVATE_GITHUB_COM_TOKEN` value = the
  password field of live Bitwarden item `dev-github` (UUID `522b1cc4-2c74-4399-887d-
  b4e20014b2d2`, `custom-values/dev/prod-values.yaml:30`; the github-mcp/github-pat chain
  PAT per EXPLORE-renovate-mcp-token.md §1–2), owner-copied into the dev Forgejo repo's
  Actions secret (cf-119 mint pattern; instance-DB, no k8s wiring, no new repo-side
  credential code; the workflow references only the secret name). Read-only need ⊂
  documented capability (RESEARCH §3). Kept as owner-check notes at UA2: token
  type/account/expiry unclaimed in-repo (§3); shared-identity blast radius — coder
  workspace `GITHUB_TOKEN` + renovate-MCP clone + the bot's github leg all ride this one
  PAT (revocation/expiry breaks three consumers, §2/§5); separate-donor alternative if the
  owner wants a distinct datasource identity: gpu item `f4938da9-3260-42c7-9787-
  b38100023fc3` (bitwarden-fields `token`, §4). Supersedes Q4's "donor candidate" phrasing.
- 2026-11-10 plan: D16 RULINGS STAND — Q1 dev-instance gate (`vars.ROLE == 'dev'`; D1
  stands, title-vs-gate tension closed), Q2 bot-PAT identity (D2 stands; scope names
  `write:repository`+`write:issue` per owner wording, U1 confirm-at-mint), Q5 dev-runner
  repair = out-of-repo prerequisite (UA4/UA5 split stands), Q6 merge→deploy tolerance,
  Q7 GitHub residue untouched, Q8 `ignoreTests` kept. No artifact change from these six;
  the fold touched only the Q3/Q4 sections. `plan_status` stays `draft` — approval is
  coordinator-owned (owner already conditionally approved on this fold: "Approve — run
  all waves").

## Deferred
- UA6 infra flip (Q1 ruling), GitHub-side `renovate/*` branch cleanup (Q7), Forgejo PR-CI
  gate-parity workflow (Q8), ArgoCD-source/merge→deploy path verification (Q6/OQ-3) —
  all follow-up-owner decisions, not chunks here.
- Repairing pre-existing reds `chart-yaml-legs.sh` k5/k10 (cf-93 drift) — separate concern,
  untouched by this branch.
- Repairing pre-existing red `kubernetes-mcp-version-floor.sh` k2 (stale packageRules count
  9≠8, cf-93-family drift) — same treatment since the Q3 override removed our rule-add
  (D14); a future rule-touching ticket flips it as its own test-session edit.
