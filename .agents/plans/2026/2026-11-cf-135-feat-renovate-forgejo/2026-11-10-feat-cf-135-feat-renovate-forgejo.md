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


---

## Rework round 2 (2026-11-21) — live-outcome delta on the landed feature

Owner reviewed the RUNNING feature on canonical (`git.spencerslab.com`) and raised three
asks: (1) "PRs with merge conflicts… most of them are doing it. Can you configure it to
address these when it runs?"; (2) "checking the boxes in issues & prs doesn't seem to do
anything… enable that in forgejo?"; (3) "on github it'd update the Chart.lock files? Can
you see if Forgejo will do that too?". RESEARCH.md §R2/§R3 are the authority for this
section; DECISIONS Round-3 (D17–D20) records the rulings. Round-1 sections above are the
completed record and are not rewritten.

**Ground truth at this pass (verified 2026-11-21 against `origin/main` = `b80fae102` after
`git fetch`; our worktree head `215ce4c03` is NOT an ancestor — cf-135 landed REBASED and
main has moved: a REBASE-ONTO-MAIN is a precondition for the test/dev waves, and baseline
fingerprints re-measure post-rebase):**
- `renovate.json@main`: round-1 zeros in place; 10 packageRules (cf-6 added the
  calendar-ownership rule), 13 customManagers, 11 top-level keys;
  `gitIgnoredAuthors`/`constraints`/`gitAuthor`/`rebaseWhen`/`ignorePrAuthor` ABSENT.
- `.forgejo/workflows/renovate.yaml@main`: owner/cf-6 re-land rewrote it to the
  `contains(vars.ROLE, 'dev')` guard variant + expanded header (documents the D12/D13
  rulings itself); structure (cron, env keys, 2 steps, image pin 44.181.5, digest comment)
  otherwise ours. main-sync/release migrated to `contains(vars.ROLE, 'prod')` likewise.
  Canonical ROLE provably contains `dev` (the job RAN: ~96 PRs 11-19, Edited/Blocked batch
  11-20 06:20Z) — canonical is today's Renovate home (U8; Q-R2-4).
- The three contract suites were ALREADY re-pinned on the main side by cf-6 run −2
  (GUARD strings → `contains(...)`, counts → 10/13) — the delta test wave does NOT
  re-do that; its only obligations are below.
- R2 fleet state: 97 open renovate PRs, 85 `mergeable:false`, ONE checkbox ticked (#90,
  2026-11-21 15:02:25Z). Root cause: the 2026-11-19 15:41–15:51Z main REBUILD orphaned
  foreign-author commits onto every branch; `isBranchModified` scans ALL commits in
  `base..branch` (author ∪ committer emails — live census on `node-26.x`: 12× tms +
  4× `bot-and-reviewed@spencerslab.com` + 1 mixed) and the edited-guard locks each out of
  auto-rebase. The PRs' heads ARE Renovate-authored-as-`tms@spencerslab.com` (RENOVATE_TOKEN
  = owner-account PAT; discovery makes gitAuthor = that email → self-consistent).
- R3 lock state: built-in `helmv3` PM owns Chart.lock regeneration; the default image ships
  NO helm (binarySource=install resolves the tool via github-releases helm/helm →
  anonymous api.github.com → "No tool releases found." on ALL 22 helm PRs); three merged
  yaml-only during the rebuild batch ⇒ drifted on main exactly at `charts/base`
  (argo-cd yaml 10.18.2 vs lock 10.11.6) and `services/home/prod` (wekan yaml 12.99.0 ×2
  vs lock 12.77.0 ×2); 77/80 pairs otherwise consistent. Daily passes do NOT re-run
  artifacts on untouched branches — the drift never self-heals.

**Delta answers to the three asks:**
1. #1 → `gitIgnoredAuthors: ["bot-and-reviewed@spencerslab.com"]` (the documented guard
   escape; repo-scoped) PLUS the owner's Q1 OVERRIDE "Also pin a git author": a
   `RENOVATE_GIT_AUTHOR: "Renovate <tms@spencerslab.com>"` job-env line on the canonical
   workflow. Value ground-ruled at D21: the email MUST be the running PAT account's
   commit email — the stuck ranges' PR-HEAD commits are tms-authored, so stamping
   bot-and-reviewed (the launch-recommended convergence shape) would DEMOTE tms from the
   guard's accepted set and leave all 85 locked (verified arithmetically against the live
   census 2026-11-21); the name "Renovate" is guard-cosmetic and provenance-legible.
   Accepted set after the delta = {tms (stamped), bot-and-reviewed (ignored)} = exactly
   the two live email classes. Next pass after it lands: all 85 rebase automatically
   (`rebaseWhen auto→conflicted` already resolves to the wanted policy — do NOT set it;
   `ignorePrAuthor` — wrong lever, global discovery filter [R2 §B] — NOT added).
2. #2 → NOTHING to enable: the checkbox machinery is intact on Forgejo 15.0.10 (raw
   ` - [x] <!-- rebase-check -->` byte-exact in #90's stored body; the list API carries
   bodies; the pinned dist has the #46200 onboarding fix). Once-daily CLI runs consume the
   tick on the NEXT pass — by construction no immediacy, no webhook needed for correctness.
   Verifiable prediction U7: at/after ~06:2xZ 2026-11-22 #90 rebases from fresh main, its
   Edited/Blocked comment disappears, the box resets — independently of this delta.
3. #3 → `"constraints": {"helm": "3.22.1"}` in `renovate.json` (exact single version
   SHORT-CIRCUITS the api.github.com tool-resolution hop [R3 §C/§D; containerbase.js:303];
   honors the repo helm-v3 law; matches the coder-workspace Dockerfile ARG — a new suite
   leg pins the pair) + ONE manual repair: `helm dependency update charts/base
   services/home/prod` (workspace helm v3.16.4 verified in-session; argo-helm 10.18.2 and
   wekan 12.99.0 present in their indexes — verified by probe 2026-11-21). The repair
   should NOT be expected to be small on home/prod: helm rewrites the non-canonical
   duplicate-heavy lock into tool-canonical shape (R3 §R3.0/3).
   Sequencing law (R3 §D.4): config delta AND repair land before the gitIgnoredAuthors
   recovery pass — otherwise every recreated helm branch re-lands yaml-only; with
   constraints in, recovery-pass re-cuts carry yaml+lock pairs.

**Delta chunks:**

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C03 | renovate.json two keys + workflow `RENOVATE_GIT_AUTHOR` stamp (+ suites learn, value pins) | S | 1 | [] | |
| C04 | Chart.lock repair: `charts/base` + `services/home/prod` | S | 1 | [] | none — disjoint files from C03; id order keeps the shared config suite red-first gate simple |

Test-Writing stage for the round (agent-test, BEFORE C03 dev, red-first): extend
`tests/renovate/forgejo-move-config.sh` — m5's exact top-level KEYSET learns
`constraints` + `gitIgnoredAuthors` (red before C03 lands, green after); new m7 pins both
values byte-exact; new m8 pins the `constraints.helm` ↔ `containers/coder-workspace/
Dockerfile` `HELM_VERSION` ARG pair (strips `v`) — the drift-knob R3 §D.1 warns about
(k09 PRs bump the ARG; m8 reddens that review so the pair moves together). PLUS one
re-pin in `tests/services/forgejo-renovate.sh`: t5's exact env-KEYSET map grows SIX
keys → SEVEN — add `'RENOVATE_GIT_AUTHOR': 'Renovate <tms@spencerslab.com>'` (red-first,
same posture as m5/m7/m8; the secret once-count semantics are UNAFFECTED — the stamp is
a literal value, not a `secrets.` ref; reserved-prefix regex still clean — it scans
`secrets.`/`vars.` refs only). t3/t8 already canonical-accurate via cf-6 run −2 — no
further work there; t8 absence-pins stay TRUE after C03 (keys and env are not rules).

**Rebase note:** the coord rebases this branch onto current main before launching the test
wave (house rule); post-rebase the suites run green-on-main-shape except the deliberately
red-first m5/m7/m8 + t5(7) until C03 lands. Re-fingerprint the Commands §4 baselines
after the rebase (k2 grows to 10≠8, same single failure; k5/k10 same class; the three
contract suites arrive ALREADY GUARD-migrated + count-re-pinned by cf-6 run −2 — read
their main blobs before specifying anything as "stale").

## Commands — rework round 2 additions (post-rebase, agent-session-runnable)

```bash
# R2a. Both touched suites + the re-pin battery (agent-test red-first, C03 dev+review green):
bash tests/renovate/forgejo-move-config.sh     # m5 keyset learns the 2 keys; m7/m8 new pins
bash tests/services/forgejo-renovate.sh        # t5 seven-key env pin (6→7, red-first); other legs unmoved; t9 designed skip
# R2a'. Workflow shape after the stamp line (probe-proven 2026-11-21 on a scratch copy of
#       the canonical main blob: YAML-valid, seven env keys, value round-trips):
python3 -c 'import yaml; e=yaml.safe_load(open(".forgejo/workflows/renovate.yaml"))["jobs"]["renovate"]["env"]; assert len(e)==7 and e["RENOVATE_GIT_AUTHOR"]=="Renovate <tms@spencerslab.com>"; print("env7 ok")'

# R2b. Config gate over the delta (schema-validity of both keys PROVEN 2026-11-21 by a
#      probe copy carrying exactly {"constraints":{"helm":"3.22.1"},"gitIgnoredAuthors":
#      ["bot-and-reviewed@spencerslab.com"]} -> validator exit 0):
npx -y -p renovate@44.181.5 renovate-config-validator renovate.json

# R2c. Resolved-config + helmv3 presence check (offline dry-run, cf-95 shape): the log's
#      resolved dumps must show both new keys and a helmv3 section in packageFiles:
LOG_LEVEL=debug npx -y renovate@44.181.5 --platform=local --dry-run=lookup > /tmp/opencode/renovate-dry-rr2.log 2>&1
grep -c '"gitIgnoredAuthors": \["bot-and-reviewed@spencerslab.com"\]' /tmp/opencode/renovate-dry-rr2.log
grep -c '"constraints": {"helm": "3.22.1"}' /tmp/opencode/renovate-dry-rr2.log
grep -c '"helmv3"' /tmp/opencode/renovate-dry-rr2.log            # >0 = PM active (it always was; locks failed BELOW extraction, at tool install)
grep -E "ERROR|failed to look up" /tmp/opencode/renovate-dry-rr2.log | grep -v 'github-token-required\|no-result' # ERROR fingerprint unchanged

# R2d. Repair verification (C04): R3 §R3.0/3 consistency scan over the whole tree — every
#      Chart.yaml dependencies[] (name OR alias) version must equal its Chart.lock entry:
python3 <inline scan per chunks/C04.md — expect 0 mismatches; was 3 rows/2 charts at main>
helm lint charts/base && helm lint services/home/prod
git diff --name-only -- '*/Chart.lock' '*/Chart.yaml'            # exactly the TWO lock files; Chart.yaml untouched (version-ownership law)
```

## User actions — rework round 2 additions (instance-side, owner-owned)
- UA7 · verify `RENOVATE_GITHUB_COM_TOKEN` is provisioned on CANONICAL (U13: #90's 11-19
  "no github.com credentials" banner proved it empty then; today's PRs are banner-free —
  suggestive, not proof). The constraints pin makes helm TOOL-RESOLUTION token-independent,
  but changelogs and the tool ASSET download (U14) still ride it.
- UA8 · create the `dependencies` label on the canonical repo (#90 `labels: []` despite
  the config — the gitea createPr path silently drops unknown labels).
- UA9 · confirm canonical-vs-dev posture (U8): canonical's ROLE contains `dev` and the bot
  demonstrably runs there with the tms PAT — accept as the live home (Q-R2-4), or flip
  the guard/value back per UA6. Also: keep `ROLE` values exact — under contains(),
  a literal like `dev,prod` on one instance fires BOTH the sync and renovate jobs there.
- UA10 · observation recipe (post-merge): tick #52's checkbox ("Update Helm release
  app-template to v5.3.0") — at the next 06:17Z pass its branch must re-cut from current
  main with PAIRED hunks (Chart.yaml + Chart.lock per ~55 charts) and the ⚠️ Artifact
  update problem comment AUTO-REMOVED [R3 §D verification]. If it re-lands yaml-only +
  fresh comment: rerun once `LOG_LEVEL=debug` and grep `Failed to update Helm lock file`
  — the asset download (U14) is the suspect, not the pin. Separately verify U7 on #90 at
  ~06:2xZ 2026-11-22 (head replaced, comment gone, box reset) regardless of this delta.
- UA11 · the main-rebuild law (human-owned merge flow): rebuilding/force-resetting `main`
  while `renovate/*` branches are open re-poisons the fleet (every rebuild wave needs its
  orphaned commits' emails added to `gitIgnoredAuthors` or reopens this ticket). Recorded
  in DECISIONS Round-3; pair such events with the recovery pass.

**Superseded by the Q4 canonical-home ruling (marked honestly, not deleted):** round-1
**UA4** (dev-runner repair) and **UA5** (dev-instance first-fire) LOSE THEIR FIRST-FIRE
RELEVANCE — the first fire happened, on canonical, repeatedly (11-19 → 11-21). Runner
repair stays valid infra housekeeping, decoupled from cf-135. Round-1 **R1/R6/R7**
(dev-execution prerequisite, dev merge→deploy path, dev job-container egress) are
likewise superseded-by-reality: canonical executes with proven egress (96-PR fleet;
11-21 passes banner-free). Round-1 UA1/UA2 keep historical accuracy (they were minted
against tms's own account on canonical, not a fresh bot user — the F3 card migrates
that). The dev mirror (round-1 UA6) survives only as the flipped OPTION it always was.
Rework UA7–UA11 above are the live instance-side list, in canonical words.

## Risks / assumptions — rework round 2
- R9 recovery pass = ~85 force-pushes in ONE run inside the 30-min ceiling (creation burst
  did ~96 in ~2.5 min — R2 U9 proxy; unmeasured for rebases) AND fires ~85 synchronize
  events → `pr …` build storm behind a capacity:1 runner whose PR jobs currently fail at
  ~6 s each (cf-6 surface, F2 follow-up — does NOT block rebase/automerge: `ignoreTests`
  blinds status entirely, R2 §D).
- R10 the ⚠️ Edited/Blocked comments already posted are NOT auto-removed on recovery
  (U11 cosmetic residue).
- R11 #19/#53/#63 were merged during the rebuild batch by an unknown actor (U16 —
  owner-side history, no in-repo action; their yaml-only merges are what C04 repairs).
- R12 the per-package `lockFileMaintenance:{enabled:true}` blocks (packageRules 3/4) are
  inert while global LFM is off (U15) — left as-is this round; separate cleanup decision.
- R13 with the exact-version constraints pin, helm-4 lock-shape drift (U17) is moot;
  re-establishing token-free determinism depends on containerbase's asset download
  succeeding anonymously (U14, UA10 recipe catches it).
- R14 Forgejo's async `mergeable` recompute may lag a just-rebased head enough that the
  NEXT pass still sees `mergeable:false` (U12) — self-correcting at daily cadence; watch
  the recovery pass count, don't chase a one-day ghost.
- Assumption: canonical keeps running the tms-account PAT until the bot-account migration
  follow-up (R2 structural note; revival of R1 §2b — deferred, Q-R2-2).

## Open questions — batched round 2: ALL RESOLVED (owner rulings 2026-11-21)
Approval: owner answered "Approve — run the delta" — the answers below ARE the fold;
plan_status flip + C03/C04 STATE stubs are coordinator-owned (DECISIONS D22 records the
verbatim rulings; nothing re-opened from round-1 decisions).

1. **gitIgnoredAuthors value vs RENOVATE_GIT_AUTHOR (Q-R2-1).** (Round-2 best guess was
   the single key with no stamp.) → RULING: **OWNER OVERRIDE — "Also pin a git author."**
   Folded as D21: stamp `RENOVATE_GIT_AUTHOR: "Renovate <tms@spencerslab.com>"` on the
   canonical workflow + one header why-line; the launch-recommended
   `Renovate <bot-and-reviewed@…>` convergence was ground-tested and REJECTED — it
   demotes the tms PR-head author from the guard's accepted set and leaves all 85 stuck
   branches locked (verified arithmetic on the live census); if the owner later insists
   on the bot-and-reviewed address, the PAIRING LAW applies — tms@spencerslab.com must
   join `gitIgnoredAuthors` in the same edit or recovery stalls (C03 AC8 re-checks).
2. **Bot-account migration now or deferred (Q-R2-2).** Best guess DEFER.
   → RULING: **deferral stands** — minted as follow-up **F3** (dedicated renovate bot
   account + PAT handover incl. one-time `RENOVATE_IGNORE_PR_AUTHOR=true` env pass);
   after F3 lands, D21's stamp must be re-ruled to the new unique identity (closing the
   docs' non-unique-identity danger noted at R13).
3. **contains()-guard variant (Q-R2-3).** Best guess LEAVE. → RULING: **LEAVE** — owner
   live edit accepted; guard line byte-untouched by C03 (AC2); suites already migrated
   (cf-6 run −2). An equality-flip would be its own ticket.
4. **Renovate home: canonical vs dev (Q-R2-4/U8/UA9).** Best guess ACCEPT canonical.
   → RULING: **ACCEPTED** — canonical is the Renovate home; UA4/UA5/R1/R6/R7
   supersession block recorded; U8's literal ROLE string stays an instance-side
   curiosity only (behaviour-proven, guard value `contains(...,'dev')` accepted).
5. **Repair commit shape (Q-R2-5).** Best guess separate chunk C04. → RULING: **stands**.
6. **constraints.helm = 3.22.1 exactly (Q-R2-6).** Best guess exact pin + m8 parity.
   → RULING: **confirmed** (v3 law + deterministic + ARG-paired).
7. **Pass-timing consequence (Q-R2-7).** Best guess accept the cron cadence. → RULING:
   **accepted** — no manual-dispatch obligation; the option stays recorded at UA10
   (owner may dispatch after merge for immediate recovery; #90's existing tick heals it
   at the 11-22 pass regardless — U7 check).
8. **F1/F2 follow-up cards (Q-R2-8).** → RULING: **mint all THREE at run end**
   (F1 ignoreTests-vs-CI-parity posture note, F2 the 6-s `pr …` build failures, F3 per
   Q-R2-2) — coordinator leg.

## Rework round 2 — execution notes for the wave (folded rulings baked)
- Wave: agent-test (red-first m5-keyset/m7/m8 + t5-seven-key) → C03 dev+review → C04
  dev+review (id order; both wave 1, independent files) → final whole-delta review.
  Coordinator: rebase onto origin/main first; flip plan_status; add STATE stubs; mint
  F1/F2/F3 at run end; owner merges C03+C04 together before the next 06:17Z pass so the
  recovery re-cuts carry paired yaml+lock (R3 §D.4).
- Post-merge observation chain (owner, UA10): [tonight] U7 — #90 rebases from fresh main,
  Edited/Blocked comment gone, box reset (tick-only proof); [first pass after C03+C04]
  85-branch recovery pass fires; [then] tick #52 → paired Chart.yaml+Chart.lock hunks
  across ~55 charts and the ⚠️ artifact comment AUTO-REMOVED — the combined proof that
  D21 restored rebase and D18 restored locks. Stale Edited/Blocked comments on recovered
  PRs are EXPECTED cosmetic residue (U11/R10) — not a bug.
