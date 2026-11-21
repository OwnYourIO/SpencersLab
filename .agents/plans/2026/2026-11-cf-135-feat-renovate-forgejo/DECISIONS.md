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

## Round 3 — rework round 2 (owner live-review 2026-11-21; folded by plan from RESEARCH §R2/§R3)
- 2026-11-21 plan: D17 R2 fold — conflict resolution = ONE config key,
  `gitIgnoredAuthors: ["bot-and-reviewed@spencerslab.com"]`. Grounded live: origin/main..
  renovate-branch email census (12× tms + 4× bot-and-reviewed + 1 mixed, 2026-11-21
  `git log` on `node-26.x`); guard = `isBranchModified` scanning ALL commits' author ∪
  committer emails against the DISCOVERED gitAuthor (tms-as-bot PAT — self-consistent for
  its own commits) ∪ gitIgnoredAuthors. Rejected, each with R2 citations: `ignorePrAuthor`
  (global-only PR-DISCOVERY filter — the brief's hypothesis, corrected §R2.B),
  setting `rebaseWhen` (auto→conflicted IS the wanted policy — documentation-only),
  `gitAuthor`/`RENOVATE_GIT_AUTHOR` (discovery is documented-best §R2.A), any
  instance/webhook work for the checkbox (§R2.C proved the machinery intact end-to-end;
  ticks are one-shot requests consumed by the NEXT daily pass — latency by construction,
  #90's 15:02Z tick predicts its own heal at ~06:2xZ 11-22, U7 check recipe).
  THE MAIN-REBUILD LAW (recorded for the merge flow, UA11): rebuilding `main` history
  while `renovate/*` branches are open is what poisoned the fleet (11-19 15:41–15:51Z
  event, forensics §R2.0/7); avoid it, or pair every such rebuild with the automatic
  recovery this delta enables (and add any new orphaned-author email here). Supersedes
  nothing from Round 1 — the shipped runner works as designed.
- 2026-11-21 plan: D18 R3 fold — Chart.lock ownership = the built-in `helmv3` PM
  (platform-independent, enabled by `config:recommended`, runs real `helm dependency
  update` — §R3.A); the default Renovate image ships NO helm, and `binarySource=install`
  tool resolution rides github-releases→api.github.com — anonymous = the proven failure
  (`No tool releases found.` on all 22 helm PRs, community-corroborated #39399). Delta =
  `"constraints": {"helm": "3.22.1"}`: the exact single version short-circuits before any
  GitHub lookup (dist containerbase.js:303), is deterministic token-independent, and
  matches the repo's helm-v3 law + the coder-workspace Dockerfile ARG (live-verified
  v3.22.1; m8 pins the pair so k09 ARG bumps can't silently stale it — the §R3.D.1
  drift knob). Rejected: token-provisioning as the SOLE fix (restores the anonymous
  resolution dependency on every pass + picks helm v4-latest, violating the v3 law —
  §R3.C honest-consequence paragraph); postUpdateOptions/enabledManagers (R3 ruled both
  irrelevant). Drift repair = one manual generator commit (C04); daily passes never
  re-run artifacts on completed branches, so no automatic path exists.
- 2026-11-21 plan: D19 delta shape — two S chunks, both wave 1, independent: C03 (the
  two keys + suite learn/extend: m5 keyset red-first, m7 value pins, m8 ARG-pair pin) and
  C04 (lock regeneration + NEW permanent suite `tests/renovate/chart-lock-consistency.sh`
  as the U16-class yaml-only-merge regression net). The contains()-guard variant on
  canonical is LEFT ALONE (owner/cf-6 live edit; its header even documents D12/D13 itself;
  cf-6 run −2 already re-pinned the three suites' GUARD/count strings — verified by diff
  against main 2026-11-21 — so the test wave touches only forgejo-move-config.sh).
  Workflow file: zero changes this round (R2 recommended delta confirmed: keys-only).
  Repair as its own commit, not folded with config (different evidence classes: generator
  output vs hand-edited JSON; cleaner revert). Rebase-onto-main before any wave;
  re-fingerprint Commands §4 post-rebase (k2 red grows to count 10≠8 — same single
  failure class; suite pins at main's re-pinned values).
- 2026-11-21 plan: D20 deferrals ruled for the batched round (best guesses): bot-account
  migration of RENOVATE_TOKEN (R2 structural follow-up — revives R1 §2b with the
  human-edit-blindness evidence; needs user+PAT+one-time ignorePrAuthor-env handover —
  new card if the owner says go); U15 dead `lockFileMaintenance` blocks in rules 3/4
  (separate cleanup decision); F1 ignoreTests-vs-red-CI posture note and F2 the 6-s
  `pr …` build failures (cf-6 surface) as follow-up cards; U16 (who merged #19/#53/#63)
  recorded as owner-side history, no chunk; U8/canonical-Renovate-home acceptance
  pending the owner's word (behaviourally canonical IS the home today).

- 2026-11-21 plan: D21 Q1 OWNER OVERRIDE — "Also pin a git author": the delta adds
  `RENOVATE_GIT_AUTHOR: "Renovate <tms@spencerslab.com>"` as a job-env line on the
  canonical workflow (contains-guard file stays per D22/Q3). CHOSEN VALUE ground-ruled
  against R2, rejecting the launch-recommended `Renovate <bot-and-reviewed@spencerslab.com>`:
  the guard accepts {effective gitAuthorEmail} ∪ gitIgnoredAuthors (all author AND
  committer emails in base..head, isBranchModified — R2 §A), and the live stuck-range
  census carries TWO email classes — tms@ (12 PR-HEAD commits per sampled range: the
  running bot IS the tms PAT account; discovery today stamps exactly that) and
  bot-and-reviewed@ (orphaned rebuild commits). Stamping bot-and-reviewed would DEMOTE
  tms@ from the accepted set while the existing 85 branches' head commits stay tms —
  recovery fails (arithmetically verified 2026-11-21: accepted={bot-and-reviewed} →
  uncovered {tms} → guard still fires). Stamping tms@ + ignoring bot-and-reviewed keeps
  the accepted set exactly the census: recovery holds and the stamp adds determinism.
  The brief's own verify-clause ("whether the platform bot user's email should be the
  address instead") is thus answered YES — the platform bot user (PAT account) email.
  DOUBLE-SAFETY recorded: (1) the stamp pins the authorized author against `/user`
  metadata drift (account rename/email change no longer moves the guard floor; new
  commits also carry the stamp via writeGitAuthor — self-consistent); (2)
  gitIgnoredAuthors covers the foreign orphan class; (3) residual docs-danger (identity
  non-unique/personal → human tms edits invisible to the guard) is UNCHANGED from the
  discovery regime and is honestly closed only by F3 (dedicated bot account, deferred).
  PAIRING LAW: the stamp email and gitIgnoredAuthors are one arithmetic — any change of
  either moves the other in the same edit (C03 AC8 re-checks the live census at dev
  time; a third email appearing = new ignored entry, stamp unchanged — owner's running
  identity is not re-decidable by a worker). Name kept "Renovate" (cosmetic to the
  guard, legible in blame, aligned with F3's future direction).
- 2026-11-21 plan: D22 ROUND-3 FOLD RULINGS (batched answers verbatim-folded) —
  Q1: OVERRIDE accepted, D21 (config side unchanged: two keys; +1 env line +1 header
  why-line; t5 six→seven red-first). Q2: deferral stands, F3 named as a card. Q3:
  contains()-guard variant LEFT — acceptance of the owner/cf-6 live edit recorded (suites
  already migrated; equality-flip would be a separate ticket). Q4: CANONICAL ACCEPTED as
  the Renovate home — round-1 UA4 (dev-runner repair) and UA5 (dev first-fire) marked
  SUPERSEDED-AS-GATE (repair stays valid infra housekeeping, decoupled from cf-135;
  first-fire happened in production 11-19→11-21 on canonical), round-1 R1/R6/R7 likewise
  superseded; instance gaps re-expressed canonically (UA7 token-verify, UA8 label, UA10
  observation chain). Q5: separate chunks stand (C03 = keys+stamp; C04 = lock repair).
  Q6: constraints.helm "3.22.1" confirmed + m8 parity leg. Q7: next-pass timing accepted
  (manual workflow_dispatch recorded as a UA OPTION, no obligation). Q8: coordinator
  mints THREE follow-up cards at run end: F1 (ignoreTests-vs-CI-parity posture note),
  F2 (6-s `pr …` containers-build PR-arm failures on canonical), F3 (dedicated renovate
  bot account + PAT migration handover incl. one-time
  `RENOVATE_IGNORE_PR_AUTHOR=true` pass — global-only env option, R2 §B). Approval: owner
  "Approve — run the delta" — plan_status flip + STATE C03/C04 stubs are coordinator-
  owned; nothing re-opened from round-1 rulings.

## Round 3 — owner line-note fold (2026-11-21, branch HEAD d21c2c1ea)
- 2026-11-21 plan: D23 C05 stamp-to-variable — owner line-noted `.forgejo/workflows/renovate.yaml:67`
  ("should be a variable/secret set in Forgejo") on the landed C03 literal. CHOSEN SHAPE:
  repo-scoped Actions VARIABLE `RENOVATE_GIT_AUTHOR: ${{ vars.RENOVATE_GIT_AUTHOR }}`
  (NOT a secret: the identity is public in every commit header — the census that proved
  it was an anonymous API read; secrets are for credentials and mask values; the repo
  convention for non-secret instance-side config is Actions variables per the cf-119
  ROLE/PUSH_URL_* lineage, now law in AGENTS.md's Forgejo conventions — ROLE-membership,
  repo-scoped not instance-global, no instance values in workflow files). D21's VALUE
  arithmetic is unchanged; only its LOCATION moves: m7/gitIgnoredAuthors stay
  repo-pinned (they read renovate.json); the stamp value becomes instance config the
  suites can only pin as a REFERENCE (t5 exact-value flips to exact-shape — a literal
  re-introduction or vars-name typo both redden via the same string equality; once-count
  extended to the new `vars.` ref). UNSET VERDICT dist-verified (decisive for ordering):
  empty-string env values are SKIPPED at `env.js:114` (`if (!envVal) continue;`),
  `gitAuthor` has no static default, so `modules/platform/index.js:36–43` falls through
  to gitea/forgejo `/user` DISCOVERY = `Spencer H <tms@spencerslab.com>` — exactly the
  email the stuck heads carry, so unset does NOT re-lock the 85 (not the D21-rejected
  value failure — that needed a FOREIGN accepted email) and does NOT crash; it silently
  degrades to the pre-stamp regime, voiding only the determinism guarantee. Therefore
  UA12-before-merge is ORDERING-MANDATORY for the law, not incident-avoidance, and the
  header paragraph must state the fallback (comment-accuracy law: the shipped "pinned
  literal, identical on every instance" prose is false post-edit — it also breaks the
  round-1 instance-neutrality convention the literal itself had silently violated).
  Rejected: `secrets.RENOVATE_GIT_AUTHOR` (masks a public value; wrong tool class);
  config-side `gitAuthor` key (would duplicate authority across repo and instance — the
  stamp deliberately lives in env per D21); dropping the stamp entirely (owner line-note
  asked to KEEP the pin, just instance-side). F3 consequence: bot-account migration now
  flips one instance variable + PAT rotation + adds old tms@ to gitIgnoredAuthors; the
  minted F3 card is NOT rewritten — coordinator may post the location note; D21 pairing
  law body-text now names the variable location (recorded here + plan Round-3 section).
## Deferred
- UA6 infra flip (Q1 ruling), GitHub-side `renovate/*` branch cleanup (Q7), Forgejo PR-CI
  gate-parity workflow (Q8), ArgoCD-source/merge→deploy path verification (Q6/OQ-3) —
  all follow-up-owner decisions, not chunks here.
- Repairing pre-existing reds `chart-yaml-legs.sh` k5/k10 (cf-93 drift) — separate concern,
  untouched by this branch.
- Repairing pre-existing red `kubernetes-mcp-version-floor.sh` k2 (stale packageRules count
  9≠8, cf-93-family drift) — same treatment since the Q3 override removed our rule-add
  (D14); a future rule-touching ticket flips it as its own test-session edit.
- FOLLOW-UP CARDS TO MINT AT RUN END (owner ruling Q8, D22 — coordinator leg, three):
  F1 ignoreTests-vs-red-CI posture note; F2 the 6-s `pr …` containers-build PR-arm
  failures on canonical; F3 dedicated renovate bot account + PAT migration (one-time
  `RENOVATE_IGNORE_PR_AUTHOR=true` handover pass; closes the docs non-unique-identity
  danger D21 carries forward). D23 LOCATION UPDATE (card NOT rewritten; coord may post
  it): with the stamp instance-side, F3 flips the one instance variable
  `RENOVATE_GIT_AUTHOR` + rotates the PAT + adds old tms@ to gitIgnoredAuthors. The
  former U8 canonical-vs-dev home question RESOLVED by the Q4 acceptance (D22) — off
  the deferred list. U15 dead lockFileMaintenance blocks
  stay deferred (own decision if the owner asks).
