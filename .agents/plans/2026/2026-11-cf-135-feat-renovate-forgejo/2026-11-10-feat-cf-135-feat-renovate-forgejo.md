# PLAN: Move Renovate to Forgejo (AD-135, card cf-135)
feature: 2026/2026-11-cf-135-feat-renovate-forgejo

## Goal
Replace the out-of-repo GitHub Renovate installation with a Forgejo Actions workflow
(`.forgejo/workflows/renovate.yaml`, container job on the pinned Renovate image, gated
`vars.ROLE == 'dev'`) and remove the open-PR limits in `renovate.json` by setting
`prHourlyLimit`/`prConcurrentLimit` to `0` (deleting the keys would silently restore the
built-in 2/10). The GitHub app is disabled by the user by hand; nothing in `.github/` is
touched. EXPLORE.md + RESEARCH.md + EXPLORE-renovate-mcp-token.md (round-2, the Q4 donor
chain) are the ground — this plan follows RESEARCH §5's shape as amended by the owner's
batched-round rulings (DECISIONS D12–D14).

## Scope
In scope (all in-repo):
- `renovate.json`: limits → `0`/`0`. Nothing else in the config (Q3 owner ruling, D12–D14:
  no containment packageRule, no self-update regex leg — the built-in `github-actions`
  manager tracks the workflow's image line natively, and PR grouping/automerge posture
  needs no rule: both bump classes stay human-merged per existing automerge name lists).
- `.forgejo/workflows/renovate.yaml` (new) + `tests/services/forgejo-renovate.sh` (new
  static contract suite, house shape per `forgejo-main-sync.sh`) +
  `tests/renovate/forgejo-move-config.sh` (new static config suite pinning the zeros AND
  the no-rules/no-legs override).

Out of scope:
- Any `.github/workflows` change or deletion — the GitHub install is app-side and the
  user disables it by hand; `release.yaml`/`docker-build.yaml`/render-tests/`rulesync.yaml`
  stay on GitHub (EXPLORE §3).
- Repairing the dev runner's `failed to fetch task` state (UA4) or the pre-existing RED
  suites — `chart-yaml-legs.sh` k5/k10 (cf-93 drift) and `kubernetes-mcp-version-floor.sh`
  k2 (stale packageRules count 9≠8) — one branch, one concern; both keep their exact
  baseline failures under our gate.
- Any `renovate.json` packageRule or customManager beyond the two limit values — the
  containment rule and the self-update regex leg were both REJECTED by the owner's Q3
  ruling (D12/D13); the config-side effect of this ticket is two numbers.
- Editing `.forgejo/workflows/main-sync.yaml` (its suite bans a dev guard *in that file*).
- No chart/values/service changes → `helm lint/template` N/A.
- GitHub-side residue: the 40 `renovate/*` branches / open PRs on `upstream` stay
  untouched (cleanup = optional user follow-up, OQ-7 posture Q7).
- A Forgejo-side PR test workflow (`ignoreTests: true` stays, D7).

## Lifecycle / run posture
Checked stages: Exploration ✔, Pre Research ✔, Planning (this), Test Writing, Chunk
Development, Chunk Review, Final Review. Deployment NOT checked → `-local` commit-only
shape; Single Session NOT checked → ordinary chunk loop. Coordinator commits every chunk;
this plan commits nothing.

## Commands
Agent-session-runnable (deterministic); baseline states verified 2026-11-10 at branch base
`931df5eec`:

```bash
export PATH=/home/coder/.nvm/versions/node/v24.22.0/bin:$HOME/.local/bin:$PATH  # node 24.22 satisfies 44.x engines; helm lives in ~/.local/bin (AGENTS.md recipe)

# 1. Renovate config schema gate — GREEN at baseline (ignore the re2
#    NODE_MODULE_VERSION WARN, it falls back to RegExp; see FRICTION).
npx -y -p renovate@44.181.5 renovate-config-validator renovate.json

# 2. Workflow YAML parse (runnable once C02 lands the file — the suite's t1 is the
#    existence gate before that; YAML-1.1 `on:` → True gotcha: suites read it as
#    doc.get(True) or doc.get('on'); a plain parse is enough for syntax).
python3 -c 'import yaml; yaml.safe_load(open(".forgejo/workflows/renovate.yaml"))'

# 3. New suites (agent-test writes; dev runs; review re-runs):
bash tests/renovate/forgejo-move-config.sh
bash tests/services/forgejo-renovate.sh          # static by default; FORGEJO_RENOVATE_PROBE=1 opts into the network leg

# 4. Existing suites — gate = no NEW failures vs baseline:
bash tests/services/forgejo-main-sync.sh          # GREEN baseline (8 ok)
bash tests/renovate/dockerfile-pins.sh            # GREEN baseline (36/0)
bash tests/renovate/system-upgrade-controller.sh  # GREEN baseline (3 ok)
bash tests/renovate/kubernetes-mcp-version-floor.sh   # RED baseline: k2 count 9≠8 (pre-existing cf-93-family drift).
                                                     # No rule lands in this ticket (Q3 ruling): count stays 9, the
                                                     # suite keeps exactly this failure — gate = no NEW one.
bash tests/renovate/chart-yaml-legs.sh            # RED baseline: k5 (wekan tuple drift) + k10
                                                    # (forgejo-host-runner dead annotation) — cf-93
                                                    # pre-existing; this ticket leaves the SAME two failures.

# 5. Offline dry-run gate (cf-95 shape; network-dependent, exercised at C01 dev+review):
LOG_LEVEL=debug npx -y renovate@44.181.5 --platform=local --dry-run=lookup > /tmp/opencode/renovate-dry.log 2>&1
grep -c '❌' /tmp/opencode/renovate-dry.log        # and: grep -E "ERROR|failed to look up" (exit 1 == a logged ERROR)
# grep gotcha: extraction evidence is the DEBUG "packageFiles with updates" payload + the
# "Found N package file(s)" stats — there is NO "Extracted" INFO line to grep for.
# After C02 lands the workflow the full-repo run doubles as native self-update proof:
# expect manager github-actions on packageFile .forgejo/workflows/renovate.yaml with deps
# ghcr.io/renovatebot/renovate (depType container, datasource docker) + ubuntu
# (depType github-runner) — probe of record 2026-11-10 (D13 evidence).

# 6. helm lint/template — N/A (no chart touched).

# 7. Live workflow execution — CI-primary/USER-gated: cannot run in an agent session and
#    cannot run on the dev instance today (runner takes no tasks, EXPLORE §3/OQ-2).
#    First-fire is UA5 after merge. `docker build`/daemon: N/A (no container image authored).
```

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | renovate.json: limit zeros (+ suite pinning the no-rules override) | S | 1 | [] | |
| C02 | `.forgejo/workflows/renovate.yaml` + contract suite `forgejo-renovate.sh` | M | 1 | [] | |

## Wave order
1. C01, C02 (independent — the owner's Q3 ruling deleted the only cross-file contract:
   there is no config leg paired to the workflow anymore, and neither chunk edits the
   other's files; run in id order). STATE.json's C02 stub (wave 2/depends_on C01) predates
   the fold — this table wins; coord syncs the stub at approval.

## Key design decisions (grounded in EXPLORE/RESEARCH; full log in DECISIONS.md)
- Gate `if: vars.ROLE == 'dev'` (job-level guard, `main-sync.yaml:25` precedent; unset
  ROLE fails safe). Card-title tension ruled as Q1 with the dev-instance best guess.
- Trigger `on: {schedule: [{cron: '17 6 * * *'}], workflow_dispatch: {}}` — schedules only
  run from the default branch (RESEARCH [1]); POSIX 5-field quoted string.
- `container: ghcr.io/renovatebot/renovate:44.181.5` full-patch immutable tag (floating
  tags stick forever on the act runner, RESEARCH §4a) + digest comment; `runs-on:
  ubuntu-24.04`; NO `uses:` steps (mirror inventory beyond actions/checkout unproven;
  Renovate self-clones via token-auth HTTPS clone_url, F4).
- Env: `RENOVATE_PLATFORM=forgejo`, `RENOVATE_ENDPOINT=${{ github.server_url }}`,
  `RENOVATE_REPOSITORIES=${{ github.repository }}`, `RENOVATE_TOKEN=${{ secrets.RENOVATE_TOKEN }}`,
  `RENOVATE_GITHUB_COM_TOKEN=${{ secrets.RENOVATE_GITHUB_COM_TOKEN }}`, `LOG_LEVEL=info`.
  Bot-PAT identity (RESEARCH §2b), not the auto FORGEJO_TOKEN (R3 fragility; Q2).
- Limits: set `0`s at `renovate.json:9-10` (F12: delete ⇒ silent 2/10 defaults).
- No containment (owner Q3 ruling, D12): the `github-actions` manager reading `.forgejo/**`
  is ACCEPTED — it will PR `runs-on` label bumps (`ubuntu-24.04 → ubuntu-26.04` offered by
  the pinned dist, probe-verified) and bare `uses:` pins (main-sync's `actions/checkout@v6`,
  tags resolved against github.com, mirror carry unproven). Tripwires instead of the ban:
  suite label whitelists (`forgejo-renovate.sh` t7, `forgejo-main-sync.sh` t7) red on a
  stranded-label merge, and human-merge posture (neither dep class appears in any automerge
  name list — config-verified 2026-11-10). `.github/**` stays tracked as before.
- Self-update = the native manager (D13): github-actions extracts `jobs.<id>.container.image`
  as a docker dep (dist `extract.js:153` → dockerfile `getDep`; scratch probe 2026-11-10:
  `ghcr.io/renovatebot/renovate 44.181.5 → 44.226.3` found, branch
  `renovate/ghcr.io-renovatebot-renovate-44.x`). NO dedicated regex leg — two managers
  claiming one line is the duplicate-dependency warning class this repo's own containers/
  ARG description explicitly engineers around. No grouping/automerge rule needed: default
  human-merged bump PRs are exactly the posture D4 wanted; the immutable full-patch tag
  makes every proposed newValue itself immutable. Net: C01 lands ZERO config rules.

## User actions (out of repo — never executed by an agent)
- UA1 · mint a Renovate bot user + PAT on the **dev instance** (`git.scifi.farm`): profile
  full name + email set (else git commits fail, RESEARCH [14]); token scope Repository
  R/W + Issue W (labels path; exact 15.x UI scope names = U1, confirm at mint). Do NOT
  reuse the Bitwarden `forgejo-token` item (MCP credential; runner-scope-banned, EXPLORE §5).
- UA2 · add Actions secrets to the **dev** repo `CuratedForest/SpencersLab`:
  `RENOVATE_TOKEN` (UA1 bot PAT) and `RENOVATE_GITHUB_COM_TOKEN` — **donor ruled (Q4/
  EXPLORE-renovate-mcp-token.md): the owner copies the password value of Bitwarden item
  `dev-github` (UUID `522b1cc4-2c74-4399-887d-b4e20014b2d2`, `custom-values/dev/
  prod-values.yaml:30` — the github-mcp/github-pat chain PAT, live Synced on dev) into the
  Forgejo repo's Actions secret** (cf-119 mint pattern; instance-DB secret, no k8s wiring,
  no new repo-side credential plumbing; the workflow references
  `secrets.RENOVATE_GITHUB_COM_TOKEN` only). Read-only need ⊂ this item's documented
  capability (RESEARCH §3). Owner-check at mint: classic-vs-fine-grained, owning account,
  expiry — nothing in-repo claims them (§3). Blast-radius note (§2/§5): one identity already
  serves the coder `kubernetes-hardened` workspace `GITHUB_TOKEN` + the renovate-MCP clone
  init — revocation/expiry now also degrades the bot's github lookups; if a separate
  datasource identity is wanted, gpu item `f4938da9-3260-42c7-9787-b38100023fc3`
  (bitwarden-fields `token`) is the donor alternative. `ROLE=dev` is already set on the
  repo (cf-119). Forgejo Actions secrets are instance-side and human-minted — the repo's
  ExternalSecret+Bitwarden law governs in-cluster secrets; this is the same class as
  cf-119's `PUSH_TOKEN_*` and never enters git.
- UA3 · disable the GitHub Renovate installation by hand (card: user does this). Leave the
  40 `renovate/*` branches + open PRs on `upstream` for optional later cleanup (Q7).
- UA4 · dev-runner execution prerequisite: the `dev-forgejo-runner-dev` release takes no
  tasks (`failed to fetch task: deadline exceeded`, EXPLORE §3). Repair = user/ops or a
  separate ticket; gated on it, the schedule fires into an unclaimed queue (R1). This
  ticket ships authored + statically validated.
- UA5 · first-fire evidence (after merge to main + UA1/UA2/UA4): `workflow_dispatch` the
  workflow on dev; verify run is claimed → diag line shows `ROLE=dev` → `renovate
  --version` line proves PATH (U4) → platform init authenticates (F2 throw absent) → PRs
  open if updates pending → runtime inside the 30m runner ceiling (RESEARCH §1: first pass
  est. 10–20 min). Decide exit-code/ERROR posture (U3) from that one controlled run.
- UA6 · follow-up ruling only (Q1): to move firing to infra, flip the guard to `'prod'` +
  mirror UA1/UA2 on `git.spencerslab.com` (a one-line edit + suite GUARD constant flip).

## Risks / assumptions
- R1 dev execution is a prerequisite, not a detail (UA4; static validation only for now).
- R2 auto-bump stranding — containment ruled out by the owner (D12); churn is accepted and
  the guard is procedural: bump PRs arrive human-merged, and both contract suites' label
  whitelists (t7) go red on any agent session touching the workflows after a bad merge.
- R3 auto-token fragility — avoided by bot-PAT choice (Q2 re-opens it only on owner word).
- R4 capacity:1 serialization vs main-sync jobs — quiet UTC minute chosen; acceptable.
- R5 GitHub rate-limit stall without `RENOVATE_GITHUB_COM_TOKEN` — secret is mandatory in
  practice (§3/UA2); with limits at 0 a degraded run churns PRs, so UA5 watches the first pass.
- R6 merge→deploy path unproven: ArgoCD's forge = instance-side `services.repo` annotation
  (OQ-3); Renovate PRs merged on dev do not reach GitHub (push-gh currently failing on
  divergence). "Test in dev" posture tolerates it; recorded, Q6 asks for the stance confirm.
- R7 job-container egress on dev entirely unproven (first-fire item, UA5).
- R8 docs-vs-dist drift — plan follows the pinned 44.181.5 dist where they differ (RESEARCH §7).
- Assumption: `renovate --version`/`renovate` on PATH in the official image (U4, medium
  confidence, proved or fixed at first fire — diag step makes the failure cheap).

## Open questions (batched round held 2026-11-10 — outcomes annotated; fold is final)
1. **Target instance reading (OQ-1/Q1).** Best guess: the gate follows the card's explicit
   `ROLE=dev` → Renovate executes on the **dev instance** `git.scifi.farm` ("test in dev");
   the title's `git.spencerslab.com` names the canonical forge the repo moved to, not the
   execution stage. Impact if ruled otherwise: `if:` flips to `'prod'` (+ suite GUARD),
   UA1/UA2 happen on infra instead — no shape change.
   → RULING: **stands** — fire on dev, `if: vars.ROLE == 'dev'`. Infra flip stays UA6.
2. **PR-opening identity (OQ-5).** Best guess: dedicated bot-user PAT in `secrets.RENOVATE_TOKEN`
   (RESEARCH §2b). Alternative: zero-new-secret `secrets.FORGEJO_TOKEN` auto-token route
   (works on public repos today per #13739, but documented as hack-on-a-change-path, R3/U2).
   Impact: one env line + UA1 scope-mint step; auto-token must prove PR-creation +
   git-transport at first fire if chosen.
   → RULING: **stands** — bot-user PAT (`write:repository` + `write:issue`), UA1.
3. **github-actions containment + self-update (OQ-8/§4c).** Best guess: disable the
   `github-actions` manager across `.forgejo/**` AND add the self-update regex leg on the
   image line.
   → RULING: **OWNER OVERRODE — "no containment"**. The manager reading `.forgejo/**`
   (runs-on label churn incl. main-sync.yaml, bare `uses:` bumps) is accepted (D12).
   Consequence re-adjudicated at the same time (D13): the 44.181.5 dist's github-actions
   manager natively extracts the workflow `container.image` (dist extract.js:153; probe
   found 44.181.5→44.226.3 live), so the dedicated regex leg would DOUBLE-MATCH and is
   dropped too; no grouping/automerge rule is required (both classes stay human-merged).
   Net: `renovate.json` gains zero rules/legs — the k2 count flip falls out of scope and
   the stale count joins the pre-existing-red fingerprints.
4. **GITHUB_COM_TOKEN secret shape (OQ-6).** Best guess: secret name
   `RENOVATE_GITHUB_COM_TOKEN` at workflow `env:`, value user-minted (read-only GitHub
   PAT). Instance-side secret per cf-119 `PUSH_TOKEN_*` precedent — NOT an ExternalSecret
   (repo secret law covers in-cluster only); nothing to commit.
   → RULING: **OWNER DIRECTION** — donor is the live Bitwarden item `dev-github`
   (`522b1cc4-…`, the github-mcp/github-pat chain): the owner copies its password value
   into the dev repo's Actions secret (UA2, per EXPLORE-renovate-mcp-token.md);
   type/scope/expiry stay an owner-check with the shared-identity revocation blast-radius
   noted; gpu `f4938da9-…` is the separate-donor alternative. Secret NAME unchanged.
5. **Dev-runner brokenness: user action vs blocker (OQ-2/Q5).** Best guess: prerequisite
   OUT of this ticket (UA4) — this ticket lands authored + statically validated; first-fire
   (UA5) waits on the runner repair, possibly a separate bug card. Impact if ruled blocker:
   chunk work is unchanged, but the ticket cannot hand to Review until dev executes — the
   whole acceptance flips to live-validated.
   → RULING: **stands** — out-of-repo prerequisite; statics gate the chunks; first-fire is
   owner-gated observation.
6. **Merge→deploy stance (OQ-3).** Best guess: "test in dev" tolerates dev-merged Renovate
   PRs not deploying until the infra flip (R6); ArgoCD's actual forge is an
   instance-side-annotation check the user can answer. Impact: none on artifacts; decides
   whether UA6 should also cover ArgoCD source rewiring as a follow-up ticket.
   → RULING: **stands** — tolerated; ArgoCD-forge verification stays a follow-up concern.
7. **GitHub-side residue after disabling (OQ-7).** Best guess: leave the 40 `renovate/*`
   branches/open PRs on `upstream` alone; no in-repo GitHub files deleted (none exist for
   Renovate anyway). Impact: cosmetic housekeeping ticket later.
   → RULING: **stands** — left for the owner; no cleanup card.
8. **ignoreTests posture with no Forgejo PR CI (OQ-9).** Best guess: keep
   `ignoreTests: true` (it makes the existing automerge schedules functional without CI)
   and do not add a Forgejo render-test workflow in this ticket. Impact: if the owner wants
   gate-equivalent CI on Forgejo PRs first, automerge timing changes — a follow-up ticket,
   not a chunk here.
   → RULING: **stands** (no answer needed beyond the best guess) — kept; CI parity is a
   later ticket if ever.
