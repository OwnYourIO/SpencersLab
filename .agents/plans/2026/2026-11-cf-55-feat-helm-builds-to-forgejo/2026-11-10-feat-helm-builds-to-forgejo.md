# PLAN: Move GitHub parallel helm builds to Forgejo

feature: 2026/2026-11-cf-55-feat-helm-builds-to-forgejo
card: 4NyPcY7WTHaG7TsT8 (#55) · type: feat · slug: cf-55-feat-helm-builds-to-forgejo
revised: 2026-11-10 post-batched-round (all nine plan questions ANSWERED — see
Open questions; three design areas OVERRIDDEN by owner rulings, recorded in
DECISIONS.md R1–R9) · v2 post-approval delta (D22–D25, RESEARCH "Post-plan round"
V-1..V-6): same-forge publish legs re-credentialed to a dedicated Forgejo-PAT
secret `PUSH_TOKEN_FJ` (V-2 REFUTED the auto-token design — owner ruling "Add a
Forgejo-PAT secret"), `[packages]` key literals fixed (V-3), test-writer guards
and prose nits folded (V-1/V-4/V-5/V-6).

## Goal

Move the two matrix ("parallel") build pipelines — `.github/workflows/release.yaml`
(helm chart bump + publish) and `.github/workflows/docker-build.yaml` (container
matrix) — to Forgejo Actions on the prod instance (`git.spencerslab.com/CuratedForest/
SpencersLab`). Both builders go DUAL-target per the owner rulings: charts publish to
GitHub Releases + gh-pages AND to the prod instance's Helm package registry;
containers push to `ghcr.io/ownyourio/*` AND to the instance's OCI registry — while
every consumer (ArgoCD, Renovate, appsets, chart pins) stays pointed at GitHub
today, byte-stable; the owner migrates services to the instance registries at
leisure (follow-up card, not this ticket's surface).

Out of scope is below; every former open question now carries an owner ruling —
the residual unknowns are first-fire observations (UA-5), not plan questions.

## Out of scope

- The five single-job gate workflows (`aislop.yaml`, `rulesync.yaml`,
  `vllm-render-tests.yaml`, `gpt-researcher-render-tests.yaml`,
  `llama-swap-tools-tests.yaml`) stay on GitHub (ruling R1: two builders only).
- Consumer migration: no `repository:`/`registryUrl`/image-pin rewrites toward the
  new instance registries — follow-up card (ruling R2/R5). No chart values pin edits.
- Dev-instance `[packages]` enablement (prod/infra only — decisions D19/D20).
- No signing/provenance; no GitHub-side push from the bump leg (ruling: Forgejo
  main only).
- First real fire of the moved workflows, PR creation and merge — user-owned
  (Lifecycle `Deployment` unchecked; commit-only local landing per AGENTS law).

## Commands

Agent-shell law: `export PATH=$HOME/.local/bin:$PATH` first (helm lives there —
without it pytest mass-skips its helm legs); pytest runs per-directory (basenames
duplicate across chart suites). No docker daemon: `docker build => no-daemon,
CI-deferred` is the designed passing shape (cf-77 ruling) — this ticket edits no
Dockerfile.

- contract (template, regression): `bash tests/services/forgejo-main-sync.sh`
- contract (new, C01): `bash tests/services/forgejo-release.sh`
- contract (new, C02): `bash tests/services/forgejo-docker-build.sh`
- contract (new, C03): `bash tests/services/forgejo-ci-surface.sh`
- contract (new, C04): `bash tests/services/forgejo-packages.sh`
- guard re-point (C01; baseline 7/7 green measured 2026-11-10):
  `python3 -m pytest charts/llama-swap/tests/test_strata_untouched.py -v`
- regression (workflow-existence leg; green at baseline 1/1):
  `python3 -m pytest charts/vllm/tests/test_contract.py -k workflow -v`
- docs-parity (C03): `bash tests/pipeline-push-pr/surface.sh` and `bash tests/wekan-mcp/tools.sh`
- generated-surface drift (C03): `npx --yes rulesync@37.0.0 generate --check`
- quality gate (every chunk): `npx --yes aislop@0.20.0 ci --changes --base origin/main --human`
- smoke: first-fire observation is a User action (UA-5) — the pipeline cannot fire
  `.forgejo` workflows from the workspace; static contract suites are the test surface.
- BASELINE RED, not cf-55's: `charts/llama-swap/tests` full dir = 111 failed /
  165 passed / 150 skipped and `charts/vllm/tests` full dir = 17 failed / 19 passed
  at `a6e493b78` (other tickets' red-first suites); validation is scoped to the
  named files/legs above, and no chunk may "fix" another ticket's red.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Move the helm release pipeline to Forgejo Actions (dual publish) | L | 1 | [] | — |
| C02 | Move the container build pipeline to Forgejo Actions (dual push, date tags, registry cache) | L | 1 | [] | independent of C01: disjoint files; shared conventions (guard/label/credential law) copied from `main-sync.yaml`, not from each other |
| C03 | Surface parity: AGENTS/skills/docs lockstep + whole-state guard | M | 2 | [C01, C02, C04] | sweeps prose that describes the post-move state (all producers/enablement must exist first) and runs the single `rulesync generate` over one tree; pins the whole `.forgejo`/`.github` inventory |
| C04 | Enable the instance package registries (helm + OCI) repo-side in infra custom-values | S | 1 | [] | no static dependency (C01/C02 suites never read it); gates their FIRST FIRE only — landing order to the human: merge C04 no later than the builders' first charts/containers push |

## Wave order

1. C01, C02, C04 (independent; run in id order)
2. C03

## Central design (all chunks; per EXPLORE/RESEARCH + owner rulings)

- **Same-forge law**: every job in every moved workflow guards `if: vars.ROLE == 'prod'`
  (the dev instance receives the synced copy — a PAT-driven sync push re-triggers its
  workflows; main-sync's precedent + suite t3 is the model). `runs-on` only from the
  advertised act set `{ubuntu-latest, ubuntu-24.04, ubuntu-22.04, docker, node22}` —
  `ubuntu-26.04` routes nowhere. Labels stay shared; a second prod runner is being
  provisioned by the owner (ruling R8) ⇒ cross-job interleaving is possible ⇒ see
  bump-safety law.
- **Action policy**: moved workflows use ONLY mirror-confirmed actions
  (`actions/checkout`, `azure/setup-helm`, `docker/*`) — no absolute `github.com`
  `uses:`. Non-mirrored actions replaced inline: paths-filter → the repo's own
  `git diff --name-only` detect loop; EMAsphere bump → python3-stdlib patch bump;
  EndBug add-and-commit → raw git; chart-releaser-action → `cr` CLI directly
  (pinned + checksummed; dodges the wrapper's `GITHUB_REPOSITORY` owner trap and
  default-`origin` pages-remote trap, RESEARCH B1/X5).
- **Helm toolchain**: act image has NO helm (RESEARCH C1) — pinned `azure/setup-helm`
  per helm-running job.
- **Bump authority + two-runner safety**: bumps commit to prod-Forgejo `main` via the
  checkout's automatic same-repo token (token-push non-re-trigger = loop guard;
  ruling R3: Forgejo main only — GitHub learns via the next human push through
  main-sync). The `bump` leg is a SINGLE job looping changed charts (fixes
  release.yaml:144's known-broken TODO). Because Forgejo's `concurrency:` is
  documented BEST-EFFORT (RESEARCH A3/[2]) and two runners may interleave, real
  safety is the **idempotent bump loop**: re-pull main, recompute each chart's next
  patch from BOTH the tree and the published index (`skip_existing` semantics),
  fast-forward-only push with bounded retry; a refused non-FF re-loops, never
  overwrites. A `concurrency:` group is kept as opportunistic belt-and-braces with
  a comment saying it is not the safety property.
- **Dual chart publish (R2)**: two independent jobs after the bump —
  `release` (GitHub Releases + gh-pages index via `cr`, primary, unchanged consumer
  contract) and `forgejo-publish` (package each chart with `cr package`, push each
  `.tgz` to `${GITHUB_SERVER_URL}/api/packages/<owner>/helm/api/charts` — owner
  segment derived from `GITHUB_REPOSITORY` env at runtime, NO instance-URL literal
  in the file). `forgejo-publish` does NOT depend on `release` and vice versa: a
  registry outage reddens only its own job, loudly and separately (ruling Q2
  error-posture); GitHub publish never waits on or blocked by the instance leg.
  Auth (D22 — supersedes the auto-token design): a dedicated Actions secret
  `secrets.PUSH_TOKEN_FJ` — a CLASSIC Forgejo user-PAT with packages write,
  minted from the account owning the `CuratedForest` package namespace — plus
  Actions var `vars.FJ_PACKAGE_USER` (the PAT owner's login), used as curl
  `--user` basic auth. The automatic workflow token provably CANNOT push packages
  on Forgejo 15.0: it authenticates as a synthetic Actions user with no token
  scope, and `services/packages/perm.go` carries the unimplemented
  `// TODO: ActionUser permission check` → guaranteed 401 (RESEARCH V-2
  [38]–[46]) — this fact rides the workflow as a why-comment, not a fallback
  path (D14's read of [2] corrected). URL derivation from
  `GITHUB_SERVER_URL`/`GITHUB_REPOSITORY` env stays (location ≠ credential).
- **Cross-forge credential (R7, amended by D22)**: the extended classic PAT
  `secrets.PUSH_TOKEN_GH` stays the ONLY GitHub-side credential:
  it is re-minted by the owner as a CLASSIC PAT with
  `repo` + `write:packages` (fine-grained cannot touch Packages — RESEARCH [1];
  the current fine-grained shape is cf-119 plan:184). It serves: main-sync push-gh
  (unchanged usage), the `release` leg (`cr upload`/`cr index` + the gh-pages
  remote via `vars.PUSH_URL_GH` credential-slot pattern, main-sync's proven shape),
  and the ghcr login (`username: vars.GHCR_PUSH_USER` — a plain non-secret Actions
  var holding the PAT owner's GitHub login — `password: secrets.PUSH_TOKEN_GH`).
  `delete:packages` is NOT granted (no prune logic — ruling Q7). The bump and instance legs reference `PUSH_TOKEN_GH`
  nowhere; the instance legs ride their own same-forge credential —
  `secrets.PUSH_TOKEN_FJ` + `vars.FJ_PACKAGE_USER` (D22).
- **Dual image push + date tags (R4/R5)**: `docker-build` twin builds each changed
  container once and tags it in BOTH `ghcr.io/ownyourio/<name>` (cross-forge,
  `PUSH_TOKEN_GH` + `vars.GHCR_PUSH_USER`) and `${GITHUB_SERVER_URL host}/<owner-
  derived>/<name>` (same-forge, `docker/login-action` with `username: vars.FJ_PACKAGE_USER`
  + `password: secrets.PUSH_TOKEN_FJ` — D22: the automatic token is a provable 401
  on the packages/OCI auth stack, V-2 [38]–[44]). Immutable tag scheme
  (R4 ruling "Date-based", pinned spelling):
  **`v<UTC-YYYYMMDD>.<HHMM-base10>.<run_number>`** (e.g. `v20261110.1315.164`;
  "time-of-day (HHMM, base-10)" per V-1a — prose says that, the arithmetic is
  `$((10#…))` of `%H%M`) —
  all-numeric semver, so Renovate's docker datasource compares/orders bumps with
  zero versioning config; disjoint from the legacy `v<N>` space by shape (no
  offset arithmetic); run-number tiebreaker makes same-minute pushes unique; the
  base-10 coercion avoids leading-zero minors (00:45 → `45`, still
  order-correct inside a date — the `10#` is load-bearing, V-1). Rolling
  `:<branch>` + `pullPolicy: Always` behavior unchanged (non-semver rolling tags
  never compete under docker versioning, V-1b). Versioning implication: the FIRST
  bump after cutover looks like a giant major jump (`v162 → v20261110.*`) —
  expected, one-time (precedent: the landed v148→v162 bump was itself a major
  jump Renovate filed, V-1).
- **Registry cache (R9)**: `type=registry` from the start, no `type=gha` gamble:
  cache image per container at `ghcr.io/ownyourio/<container>-buildcache:<branch>`,
  `mode=max`, default ignore set, on the ghcr side (auth already proven there by
  the push leg — the login doubles as cache-push credential; instance registry
  NOT used for cache: one cache store). `cache-from` always; `cache-to` only on
  non-PR events (a PR build must not write cache that gates a publish). The
  hygiene cost (one cache repo per container, UI-side manual prune) is
  owner-accepted per the ruling.
- **Instance registry enablement is repo-side (R2-b, decision D19, literals
  fixed by D24)**:
  `charts/forgejo` already merges per-instance `gitea.config` maps from
  `custom-values/infra/prod-values.yaml` (`forgejo.forgejo.gitea.config.*`) — the
  LFS opt-in is this exact pattern ("that declaration is the gate", chart values
  comment :92-100) — so C04 adds a `packages: {ENABLED: "true"}` block to the
  INFRA slice only. No chart-template edit (the static `additionalConfigFromEnvs`
  list is never overridden — chart law :145-151). V-3 verified the full render
  path (upstream forgejo chart 17.3.1 renders `gitea.config` generically into the
  inline-config Secret [47]); v15.0 keys are per-type (`LIMIT_SIZE_HELM` /
  `LIMIT_SIZE_CONTAINER`, default `-1` unlimited; NO generic `LIMIT_SIZE` key
  exists — declaring one would be silently ignored [16]) and `ENABLED` already
  defaults true, so the declaration is the explicit-on posture and caps stay
  deliberately ABSENT (D24: declaring caps is scope creep). Blob storage stays on the
  data PVC (the `[storage]` S3 section is deliberately not touched — chart comment
  warns it would drag attachments/avatars/packages to S3).
- **Cutover single-commit per workflow** (unchanged): add `.forgejo` twin + delete
  `.github` twin + re-point bound tests in the same chunk; file NAMES kept
  (`release.yaml`, `docker-build.yaml`) so bare-name needles across tests/skills/
  AGENTS stay honest; full-path prose moves in C03.

## Open questions — ANSWERED (batched round 2026-11-10, owner rulings verbatim in DECISIONS.md R1–R9)

1. Scope → R1: two builders only; gates stay on GitHub.
2. Chart artifact store → R2 OVERRIDE: DUAL publish — GitHub Releases + gh-pages
   (consumer surfaces byte-stable) AND the prod instance's Helm package registry;
   consumers migrate on a follow-up card at the owner's pace; instance leg fails
   loudly-but-separately (parallel independent job, GitHub primary never blocked).
3. Bump push → R3: Forgejo main only.
4. Container tag scheme → R4 OVERRIDE: date-based; pinned spelling
   `v<UTC-YYYYMMDD>.<HHMM-base10>.<run_number>` UTC (semver-comparable, legacy-
   disjoint, minute-collision-safe); `:<branch>` rolling + pullPolicy unchanged.
   Spelling refined post-approval per V-1a: time-of-day (HHMM, base-10 coerced).
5. Image registry → R5 OVERRIDE: BOTH — ghcr.io/ownyourio unchanged AND the
   instance OCI registry; no pin changes in this ticket (shared follow-up card).
6. PR legs → R6: accept; triggers wired on the twins for later re-enable.
7. Secrets → R7 OVERRIDE: extend the existing `PUSH_TOKEN_GH` (re-mint as CLASSIC
   `repo` + `write:packages`; fine-grained excluded for Packages); ghcr username
   as plain var `GHCR_PUSH_USER`; no new secret names; no `delete:packages`.
   **Amended post-approval (D22, owner ruling "Add a Forgejo-PAT secret")**: the
   "no new secret names" limb is superseded for the SAME-FORGE legs only — V-2's
   code proof (perm.go `// TODO: ActionUser permission check`, synthetic Actions
   user with no token scope [38]–[46]) shows the automatic workflow token 401s
   on package push, and no GitHub PAT can credential the Forgejo packages API:
   instance legs get their own Actions secret `PUSH_TOKEN_FJ` (classic Forgejo
   user-PAT, packages write, minted by the CuratedForest-namespace owner
   account) + Actions var `FJ_PACKAGE_USER`. GitHub-side stays
   single-`PUSH_TOKEN_GH` as ruled.
8. Runner capacity → R8 OVERRIDE: provision a second runner now (owner-side:
   registration + Bitwarden item + repo slice once the UUID exists — UA-3 with
   evidence; slice can join this run as a late chunk if the owner supplies the
   item mid-run, else follow-up). Consequence handled: best-effort `concurrency:`
   + idempotent FF-only bump loop (central design).
9. buildx cache → R9 OVERRIDE: `type=registry` from the start at
   `ghcr.io/ownyourio/<container>-buildcache:<branch>` mode=max, cache-to non-PR;
   hygiene accepted.

## User actions (not chunks)

- **UA-1** GitHub-side credentials (as approved): re-mint/replace the prod-instance
  repo secret `PUSH_TOKEN_GH` as a CLASSIC GitHub PAT on the
  `OwnYourIO/SpencersLab`-reachable identity: scopes `repo` (contents write for
  main-sync + gh-pages push, releases RW for `cr`) + `write:packages` (ghcr push;
  implies pull). NOT: `delete:packages` (no prune logic), admin/org scopes. The
  bump leg needs no GitHub-side push (R3). Also set repo var `GHCR_PUSH_USER` =
  the PAT owner's GitHub login.
- **UA-1b** SAME-FORGE credentials (D22, new): mint a **classic Forgejo user
  PAT** from the account that owns the `CuratedForest` package namespace with
  packages write (org membership supplies `unit.TypePackages` — perm.go
  DeterminePackageAccessMode honors user tokens [V-2 41]); register it on the
  **prod Forgejo instance** as repo Actions secret `PUSH_TOKEN_FJ`, plus repo
  Actions var `FJ_PACKAGE_USER` = that account's login. Instance-side, NOT a
  GitHub credential; required before C01/C02 first fire or their instance legs
  go red (loudly, by design — GitHub legs unaffected, D13).
- **UA-2** — (folded: the pre-ruling dedicated `RELEASES_TOKEN_GH`/`GHCR_PUSH_TOKEN`
  secrets are R7-void; `PUSH_TOKEN_FJ` (UA-1b) is the only new secret, forced by
  V-2, not by draft preference.)
- **UA-3** second runner: register a new runner on the prod instance (owner-side
  UI, same pattern as `forgejo-runner-gpu`: registration token → Bitwarden item →
  repo slice). Evidence the slice CANNOT be pipeline-prepared now: the chart is
  one-release-one-registration with `uuid`+`token` from a Bitwarden item
  (charts/forgejo-runner/values.yaml:77-89) and the trio's `custom-values` 1:1
  sentinel contract needs the real UUID. Owner mints registration + item; the
  repo slice (services/gpu/prod/values.yaml + custom-values/gpu pattern of the
  existing `forgejo-runner-gpu` entry :119-122,271-273 / :109-118) then lands as
  a late chunk this run or a small follow-up.
- **UA-4** first-fire checks on `[packages]`: after merging C04, confirm the
  infra-forgejo pod rolled and the registry endpoints answer
  (`/api/packages/CuratedForest/helm/api/charts` listing / OCI v2 endpoint).
  Per D24 no size caps are declared (v15.0 per-type `LIMIT_SIZE_HELM` /
  `LIMIT_SIZE_CONTAINER` default `-1` unlimited [16]) — if the owner later wants
  hygiene bounds, they add those per-type keys to the same block (no generic
  `LIMIT_SIZE` key exists — it would render and be silently ignored).
- **UA-5** first-fire observation after merge: instance-leg auth (`PUSH_TOKEN_FJ`
  + `FJ_PACKAGE_USER` registered per UA-1b — the automatic token is provably
  rejected (V-2), so a missing secret reds the instance legs at parse/run start;
  GitHub legs stay unaffected by design, D13);
  job egress to `api.github.com`/`uploads.github.com`/`get.helm.sh`/`ghcr.io`;
  `azure/setup-helm` fetch; a chart appearing in BOTH the GitHub index and the
  instance helm registry; a date-tag image landing in BOTH ghcr and the instance
  registry; the buildcache repo created on ghcr; main-sync still green (non-FF)
  through the first bump-bearing GitHub sync; the idempotent bump loop under the
  (best-effort) two-runner interleaving.
- **UA-6** PR + merge ordering: merging C04 (packages enablement) before or with
  the builders avoids a red `forgejo-publish` first fire (with UA-1b's
  `PUSH_TOKEN_FJ`/`FJ_PACKAGE_USER` registered on the instance — missing there,
  the instance legs are the red ones, GitHub legs unaffected); the infra-forgejo pod
  restarts once when C04 lands (brief git/runner blip — runners reconnect).

## Risks / assumptions

- **First-fire ≠ pipeline-testable**: static contract suites prove shape, not
  execution; RESEARCH's unanimous rule is "every moved workflow needs a smoke run".
  UA-5 owns it; a red first fire reopens the ticket.
- **Same-forge package auth has NO zero-config shape on Forgejo 15.0** — the
  automatic workflow token maps to a synthetic Actions user whose packages
  permission is an unimplemented TODO (`perm.go`, V-2 [38]–[46]): `PUSH_TOKEN_FJ`
  (UA-1b) is load-bearing; the instance legs red-out without it (loudly, and by
  the D13 topology they cannot take the GitHub publish down with them).
- **Two-runner interleavings beyond the bump loop**: concurrent `release` jobs of
  two different runs could race the gh-pages index push (non-FF → job red, next
  charts push re-publishes; `skip_existing` makes retries cheap). Accepted as rare;
  the bump/critical write path is guarded (central design).
- **Date-tag transition**: Renovate opens one-time large-looking major bumps
  (v≤200 → v2026…); pins in charts continue to resolve old tags unchanged.
- **Package blobs on the data PVC**: growth is unbounded by default (v15.0
  per-type size keys default unlimited and are deliberately not declared — D24);
  prune is owner-side UI; `[storage]` S3 remains deliberately unconfigured (chart-law warning
  about dragging attachments/avatars along).
- **Event-payload keys** (`github.event.before`, PR shas) — "some keys missing"
  caveat (RESEARCH A3); detect legs keep the all-zero→`HEAD^` fallback; first-fire
  checks.
- **Red-first baselines in chart test dirs** (measured at a6e493b78): the full
  `charts/llama-swap/tests` and `charts/vllm/tests` dirs carry other tickets'
  red-first legs; all cf-55 validation is scoped to the named files/legs in
  Commands (each individually green at baseline) — a dev or review agent must not
  chase or "fix" that unrelated red.
- `rulesync generate` regenerates AGENTS.md + skill mirrors in C03 — commit sources
  and generated files together; P6 of `tests/pipeline-push-pr/surface.sh` gates it.
- aislop scans 7 languages — `.sh`/`.yaml` legs pass vacuously (cf-119 precedent);
  the real teeth are the contract suites themselves.

## Review

### Final whole-plan review — 2026-11-11 (agent-review, fresh session, launch-scoped to `a6e493b78...HEAD`)

**VERDICT: APPROVED.** All validations fresh-green on the committed tip; the eight
named cross-chunk seams verified coherent; the findings below are minors/nits that
do not gate the plan's completion.

#### Validation posture (all run fresh in this session, worktree tip 572a20308, clean tree)

| surface | result |
|---|---|
| `forgejo-release.sh` / `forgejo-docker-build.sh` / `forgejo-packages.sh` (t6 rendered for real) / `forgejo-ci-surface.sh` / `forgejo-main-sync.sh` | 15/15 · 11/11 · 7/7 · 6/6 · 8/8 |
| `tests/containers/forgejo-host-runner.sh` (launch's `tests/services/` path typo stands) | 11/11 |
| guard trio `CHUNK_BASE=a6e493b78` — agents-md / gate / rulesync-surface | admitted arms green per-id (agents-md c7+c8, gate t14, rulesync-surface c8); the three recorded pre-existing reds (c11 cf-106 runner-model needle, t17 agent-coord contract, c19 boards custom-field count) message-identical — c11 needle absent at base too (0 hits in `a6e493b78:.rulesync/rules/overview.md`), t17/c19 inputs (.rulesync/subagents, boards skill) untouched by this ticket; NEW coverage this run: the tail legs the first-red exits hide — gate t18–t21 and rulesync-surface c20–c24 all PASS |
| `tests/pipeline-push-pr/surface.sh` / `tests/wekan-mcp/tools.sh` | 10/10 · 10/10 |
| strata guard `test_strata_untouched.py` / `test_contract.py -k workflow` | 7/7 · 1/1 |
| full-dir posture-compares | llama-swap 111F/165P/150S and vllm 17F/19P — equal to the plan-recorded baselines, zero new reds |
| `PATH=$HOME/.local/bin:$PATH helm lint` — `charts/forgejo`, `charts/llama-swap`, `services/infra/prod` | 0 failures each |
| `rulesync@37.0.0 generate --check` + two plain `generate` runs | clean; both no-ops (md5-pinned AGENTS.md + generated set, `git status` clean afterwards) |
| `aislop@0.20.0 ci --changes` | 91 files, 0 errors / 0 warnings, exit 0 (plus the plan line with `--base origin/main --human`: 100/100, exit 0; yaml/shell vacuous-class caveat restated honestly) |
| `dev-mcp-fleet.sh` posture | 18 ok + 1 FAIL: t7 mcp-playwright v0.0.78-pin vs live v0.0.83. Honest shape: the t7 python exits on the first bad(), so the THREE stale verbatim pins (playwright v0.0.78→live v0.0.83, renovate-mcp v31→live v84, mcp-searxng 1.13.0→live 2.8.1) collapse to one visible red; all belong to the pin's owner ticket (cf-55 changed only the boards digits arm, `services/dev` untouched — the same red stands at base). The cf-55-generalized boards tag arm (572a20308): CORRECT and matching the live `:v162` today, and a dotted date tag post-cutover (`v20261110.1315.164` verified against the landed regex; junk shapes rejected) — but UNREACHABLE in a suite run until those three owner pins are re-pinned (its teeth were proven 7-way out-of-band at the test wave). |
| stale-path sweep `git grep -E '\.github/workflows/(release|docker-build)\.yaml'` | zero live-surface hits; every survivor is `.agents/` history or the vendored `ha-integration-dev` HACS example (both legitimate exclusions) |

#### Cross-chunk seams (launch-named, adjudicated)

1. **Credential law coherent everywhere.** No live surface claims the automatic token
   can push packages — every auto-token mention is a prohibition (AGENTS.md:451,
   overview.md:449, container-creation:83, the two workflow why-comments) or the
   carved bump exception (same-repo automatic *git* credential, D22/[43]). The pair
   `PUSH_TOKEN_FJ`+`FJ_PACKAGE_USER` matches between release.yaml (curl `--user`,
   exactly-once step env), docker-build.yaml (login step, exactly-once), the AGENTS
   law, DECISIONS D22/D23 and the container-creation skill; `PUSH_TOKEN_GH`+
   `GHCR_PUSH_USER` likewise GitHub-side. No `RELEASES_TOKEN_GH`/`GHCR_PUSH_TOKEN`
   survives anywhere outside `.agents/` history. `github.actor/github.token` and
   reserved-prefix secret names: zero occurrences in either builder (the two
   `$GITHUB_ACTOR` reads are commit-author identity strings in bump/release, not
   credentials; none in forgejo-publish).
2. **Date-tag spelling identical across surfaces.** `v<UTC-YYYYMMDD>.<HHMM-base10>.
   <run_number>` ("time-of-day (HHMM, base-10)") in AGENTS, overview.md,
   container-creation, wekan-mcp/strata READMEs and the workflow comment; the shipped
   computation is the D28-blessed single-clock variant (`STAMP=$(date -u +%Y%m%d.%H%M)`
   + `${STAMP%%.*}.$((10#${STAMP#*.})).${RUN_NUMBER}`) and t8 accepts it per test-wave
   ruling (e); the `10#` is present and its why-comment truthful. Zero `minute-of-day`
   residue; no live surface cites D15's two-call literal as law.
3. **ROLE guard story coherent.** Both twins guard every job with the exact
   `vars.ROLE == 'prod'` equality (D26 law; suites t3); the dev-never-publishes claim
   (D8) rests on the guard, and C04's prod-only `[packages]` declaration (D20) is the
   complementary posture, not a contradiction — the dev slice's absence is machine-
   pinned (packages t4/t5), and main-sync's ROLE precedent is cited unchanged (its
   file byte-stable).
4. **End-to-end race re-derived clean.** The bump chain is strict-above-max over
   (Forgejo tree, GitHub Pages index) and FF-only with bounded re-check, so
   interleaved fires chain versions instead of colliding; gaps are benign per V-4.
   Double-publish: GitHub-side the release name/tag is unique and `cr upload
   --skip-existing` skips (loser no-ops or reddens on the gh-pages non-FF —
   documented risk, self-healing because `cr index` regenerates cumulatively from the
   release list); instance-side `OverwriteExisting:true` makes a concurrent same-version
   push last-write-wins with identical bytes (churn, never corruption). Silent skip of a
   fresh chart: both skip decisions key on the EXACT (name, version) pair being present
   in the respective index — a version that has never published cannot match; a false
   HIT needs a same-indent dependency pair equal to a fresh repo-chart (name,version)
   (none exists; NIT-5 watch recorded). GitHub-lag (R3) is race-safe: cr uses an empty
   `target_commitish` (default-head, the one shape that cannot reference a commit
   GitHub has not seen — why-comment :341-344), and main-sync fans the bumps out on the
   next human push with FF-only semantics.
5. **Consumers byte-stable.** `git diff --name-only` blast radius: workflow adds ×2 +
   GitHub twin deletes ×2, `custom-values/infra/prod-values.yaml` ×1, the five
   contract suites + guard trio admits + dev-mcp-fleet t7 generalization, plan folder,
   AGENTS/rules/skills/.opencode prose+mirrors, containers README/Dockerfile comments.
   Under `charts/`: ONLY the two strata-guard test files (the plan-mandated re-point,
   assertions unchanged) — zero `Chart.yaml`/`values.yaml`/template touches; `services/`
   zero; `custom-values/dev` zero; ApplicationSet/ArgoCD surfaces zero.
6. **Gates and main-sync untouched.** `.github/workflows/` holds exactly the five gate
   twins (only the two builder files were deleted); `.forgejo/workflows/main-sync.yaml`
   has no delta; inventory machine-pinned by ci-surface t1/t2.
7. **Rulesync/AGENTS mirror consistency proven byte-level** (`generate --check` clean,
   two no-op generate runs, md5-pinned AGENTS.md + all mirrors, `git status` clean).
8. **User actions recorded accurately** — UA-1, UA-1b, UA-2(folded), UA-3, UA-4, UA-5,
   UA-6 all present with the right facts (classic-PAT scopes, var carriers, runner
   slice evidence, `{ENABLED}`-only posture, per-direction credentials, ordering).
   Two gaps, closed by this section as the owner-facing addendum (M-2 below): the
   PR-`cache-from` re-enable decision and the dispatch-inputs key-spottiness check —
   both routed to UA-5 by the C02 review but never folded into the (frozen) plan text.

#### Findings (minors/nits — none blocking)

- **minor M-1 — the dormant PR-validation lane is not surfaced in prose.** The R6
  ruling wires the `pull_request` triggers on the twins but PRs live on GitHub until
  re-enable — so no PR-time container build fires anywhere today (GitHub twin deleted,
  Forgejo twin sees no PRs and its push trigger matches only main/dev). Three surfaces
  still narrate PR validation as if it served: `pipeline-push-pr/SKILL.md:41` ("builds
  ride the existing `docker-build.yaml` PR validation"), `containers/strata/README.md`
  / `containers/wekan-mcp/README.md` ("detects this changed directory on PRs"), and the
  container-creation Triggers paragraph. The sentences are literally true of the shipped
  trigger set (which the workflows do carry), but an agent in a future `-pr` container
  chunk can read them as "my pushed branch gets a build check" and wait for a run that
  never starts. Fix: one R6-dormancy sentence at container-creation's Triggers block +
  pipeline-push-pr:41 (re-pin the P3/P7 needles' tokens while at it), or fold into the
  D29(2) follow-up sweep card. Not caught by ci-surface t3 (full-path sweep; these are
  bare-name/descriptive cites) and truth-checked out of C03's review scope, which
  compared prose against the shipped WORKFLOW files, not against instance-side PR
  reality (the FRICTION on-record "instance state unverifiable" class).
- **minor M-2 — UA-5 list (plan file) lacks two owner-routed items** (resolved above
  in seam-8 and recorded in the addendum below; plan text frozen pre-C02, coordination
  bookkeeping only).
- **minor M-3 — STATE.json `updated_at` is stale** (2026-11-10T22:35:00Z) against the
  newest recorded handoffs (C03 review 2026-11-11T05:50:00Z, test_wave_2 06:10:00Z) —
  display stamp per the conventions; coord re-stamps at next write.
- **nit N-1 — the cf-55 merge itself is the builders' first fire, by the filter's own
  semantics.** This branch edits `charts/llama-swap/tests/*` and `containers/*` comment
  files — both match the twins' `charts/**`/`containers/**` path triggers, so the first
  post-merge fan-out will bump+publish llama-swap (a benign patch bump — inherited twin
  behavior, identical before the move) and run one container detect pass. Landing order
  judgment, plain for the owner: land UA-1 (classic PAT re-mint + `GHCR_PUSH_USER`) and
  UA-1b (`PUSH_TOKEN_FJ` secret + `FJ_PACKAGE_USER` var) BEFORE merging this branch;
  C04 rides the same merge (single PR = enablement lands with the builders, the UA-6
  preferred ordering satisfied). If the credentials lag, the instance legs red loudly
  and self-heal on the next charts/containers fire (GitHub legs unaffected, D13).
- **nit N-2 — the lowercase-owner invariant (C02 MINOR-1, D28 "documented-and-implicit")
  lives only in this ticket's DECISIONS record**, not in a workflow comment — a metadata-
  action version bump is the re-verify trigger (rides the renovate lane per D28).

#### Owner addendum to UA-5 (first-fire/re-enable checklist, completes the plan's list)

- PR-`cache-from` on private `-buildcache` repos: decide at Forgejo-PR re-enable time —
  gate `cache-from` to non-PR, publish the buildcache repos, or add a PR-safe ghcr read
  login (buildkit import failure is non-fatal; zero impact while PRs stay dormant).
- `workflow_dispatch` inputs: `github.event.inputs.containers` key-spottiness on Forgejo
  payloads (RESEARCH A3) — a named dispatch silently degrading to auto-detect is the
  failure shape to watch in the run log.
- Plus the pre-existing N-1 merge-is-first-fire note (bump of llama-swap expected on the
  landing fan-out).

#### Handback to coord

Plan complete: goal met as a whole, every acceptance criterion machine-pinned and
fresh-green, all nine rulings and D22–D29 landed in code and prose, the three chunk-
round residual classes verified closed at whole-plan scope. Remaining actions are the
owner's (UA-1/UA-1b before merge, UA-5 + addendum observations) and two non-blocking
prose/bookkeeping folds (M-1 wording fix — may ride the D29(2) sweep card or a
coord-approved micro-fold; M-3 STATE stamp). Per the card's Lifecycle the run stops at
this Final Review; merge/PR stays human-owned (AGENTS law).

## Rebuild onto main (2026-11-16)

Record-transport pass: this work rebases onto main (base 043be6645) on the rebuilt
branch cf-55-feat-helm-builds-to-forgejo-rebuilt. Authority: DECISIONS.md D31 (owner
rebase directive + supersession of C02 by cf-6's landed container-build move) and D32
(the reconciled contract the port implements — contains() guards, FORGE_PUSH_TOKEN,
lowercase curatedforest literal, output-compat idiom).

Shipped scope now: the chart move (C01, re-anchored) + enablement (C04, content
unchanged) + parity (C03, re-derived chart-half prose and ci-surface). The container
half landed with cf-6 (containers-build.yaml + its suite + the kept .github manual
fallback); C02 is superseded, not ported.

User actions changed:
- UA-1b is now: confirm FORGE_PUSH_TOKEN scopes the Helm package namespace (the
  PUSH_TOKEN_FJ/FJ_PACKAGE_USER mint retired under D32 before ever being provisioned).
- UA-3 second-runner provisioning now lands with cf-6's world — the container builders
  already run on the fleet cf-6 stood up.
- UA-6 merge ordering is now: this branch merges alone — the container builders already
  live; only the release builder's first fire rides this merge (UA-1's classic-PAT
  re-mint still precedes it).

---

## Fix round (2026-11-21) — bake the toolchain into a custom runner job image

Authority: D33 (owner continuation directive after the release pipeline's FIRST
FIRE failed at the runner's "Set up helm" step — read ECONNRESET downloading
`helm-v3.16.4-linux-amd64.tar.gz` from get.helm.sh, 3 retries, exitcode 1;
owner-confirmed fix: a custom act-runner image with helm BAKED IN, built by our
own containers-build pipeline, setup-helm steps retired) + D34 (shared CICD
lease) + D35 (openrouter flash, no plan surface). Ground truth: EXPLORE.md
§F0–§F6. This section and chunks C05–C07 supersede nothing already merged;
they fix what the first fire revealed. D33's "still cf-55 work" ruling keeps
there is no second plan file. REWORK 2026-11-21 (post-batched-round,
D42/D43): all seven fix-round questions ANSWERED — D37 cr-bake, D38 helm
v3.22.1, D39 ghcr pull, D40 22.04-unmoved CONFIRMED as adopted; landing =
SINGLE PR (D42: the recommended UA-7 split is RETIRED, UA-7's slot restated
as the single-merge observation leg; UA-8 month-crossing amend stands); the
three `Verify toolchain` steps are RETIRED (D43 — t19 loses its step-presence
limbs, t5 flip unchanged, t20's `--retry` STANDS). Plan APPROVED to run
C05 → C06 → C07.

### First-fire truth (§F1)

The fragility surface is **release.yaml ONLY** among the four `.forgejo`
workflows: three `azure/setup-helm@v4` steps (jobs `test-build` :101, `release`
:289, `forgejo-publish` :377) and two cr tarball installs (:294, :382) — the cr
downloads share the exact same egress-fragility class and land in the two
never-reached jobs. The bump leg's published-index fetch (:188,
`ownyourio.github.io`) is a same-class egress but is DATA, not a tool install —
it cannot be baked; it gets `--retry` hardening instead. The other three
workflows install nothing at run time (`main-sync` git-only, `renovate` runs
inside its job-level container image, `containers-build`'s curls are registry
API reads). The agent-side get.helm.sh fallbacks in many `tests/services/*.sh`
(§F1 last bullet) are a different class (Coder-workspace egress, skip-on-failure)
— a de-helm sweep must NOT touch them.

### Fix-round chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C05 | `containers/forgejo-runner` — the baked act job image + its contract suite | M | 1 | [] | — (new files only; detection is path-based, NO registration list — verified: `scripts/forgejo-container-detect.sh` gates on `containers/**` diff + DNS-safe name + Dockerfile existence, §F3) |
| C06 | Re-point the runner label map to the baked image (chart + dev/gpu suites + g7/t14 amendments) | M | 2 | [C05] | the label lines name C05's image ref and its first calendar tag; the template record comments assert facts C05's Dockerfile creates; the suites pin the merged posture |
| C07 | Retire setup-helm + cr downloads in `release.yaml`; flip `forgejo-release.sh` t5/t19 to the baked posture; prose bullet | M | 3 | [C06] | the workflow may not drop its runtime installs until every `ubuntu-24.04`-family label provably names a helm+cr-bearing image (merge-order law, D40); C07 alone is not mergeable against today's live runners |

### Central design (D36–D41 as APPROVED — landing amended by D42, presence steps retired by D43; full text in DECISIONS.md)

- **Image**: `containers/forgejo-runner/` → publishes
  `ghcr.io/ownyourio/forgejo-runner` (+ instance-registry twin, automatic).
  `FROM ghcr.io/catthehacker/ubuntu:act-24.04@sha256:7bf3a8afc2bbfe7fdaf4b9d2716cb2f3634fd21e4f38e26aa17a12cfda80d721`
  (digest verified live 2026-11-21 via the anonymous ghcr pull-token recipe) —
  the digest-pin satisfies the no-regression law by construction: the RESEARCH
  C1 inventory (git/git-lfs/jq/python3.12/node 20+24 tool-cache/yq/docker CLI
  +buildx+compose/sudo-apt) is what all four workflows' steps assume TODAY, and
  the derivative is that exact set plus two static binaries.
- **Baked tools**: helm `v3.22.1` (D38 — coder-workspace precedent :49-50,
  :142-149 and the GitHub-hosted preinstall equivalent; supersedes the
  first-fire v3.16.4 by adoption, one ARG revert if the owner rules otherwise)
  via the get.helm.sh tarball + fetched `.sha256sum` + version assert; cr
  `1.10.1` (D37 — the workflow-verified version + sha256 pair migrates to a
  Dockerfile ARG, manual-pin sha precedent HUGO/GO/FJ) + binary-only extract +
  assert. Both ARGs carry `# renovate: datasource=github-releases` pins
  (helm/helm, helm/chart-releaser) claimed by the existing Dockerfile ARG
  manager (renovate.json :112-121). No `COPY`/`USER`/`ENTRYPOINT` in the
  Dockerfile — a job shell keeps the base's root user (documented deviation
  from the service-container law, D36).
- **Pull source + tag law (D39)**: labels name
  `docker://ghcr.io/ownyourio/forgejo-runner:26.11.1` — the runner-side
  anonymous **ghcr** pull is the proven path (every lab job pulls ghcr today;
  ownyourio ghcr repos serve anonymous manifest/tags, verified live 2026-11-21);
  the instance-registry `/v2/` anonymous pull is NOT proven runner-side (§F4/F0)
  → routed as owner UA-10, never assumed. `:main`/`:latest` are banned here by
  the measured "runners never re-pull a cached tag" law (RESEARCH C2 remedy-3,
  renovate.yaml header :21-23) — an immutable calendar pin makes staleness loud
  (pull fail / pod restart) instead of silent. The first calendar tag of a
  brand-new image is DETERMINISTIC: both registry walks see no tags → N=1 →
  `yy.mm.1` of the MERGE month (walk code, `next_n` + the 404-tolerance
  posture). Under D42's single merge the registry list is provably EMPTY at
  C06 dev time, so the walk prediction IS the shipped literal and this merge's
  own containers-build fire makes it true (a non-empty probe — C05 pre-built
  out-of-band despite the retired split — would pin the highest observed
  calendar tag instead); a merge crossing the month boundary is owner UA-8
  (one-line amend).
- **Label scope (D40)**: the four act-24.04-family entries (`ubuntu-latest`,
  `ubuntu-24.04`, `docker`, `node22`) move to the baked image — uniform
  toolchain behind every label jobs actually request. `ubuntu-22.04` stays
  `docker://ghcr.io/catthehacker/ubuntu:act-22.04` (no job uses it; a
  24.04-content image behind a 22.04 label would lie; helm-bearing jobs must
  request the 24.04 family — the law t4's whitelist already permits).
- **Test-contract deltas (scheduled here, per explore_handoff)**:
  `forgejo-release.sh` t5 (allow-list shrinks to `actions/checkout@`;
  `azure/setup-helm` joins the file-wide banned list) and t19 (flips from the
  runtime cr-download contract to the BAKED posture: no `get.helm.sh` /
  cr-tarball string / `CR_VERSION`/`CR_SHA256`/`RELEASES_HOST` env anywhere,
  no installer-shaped or presence-check step in the vacated slots (D43 — the
  real invocations ARE the check), while the actual
  `cr package/upload/index` and `helm dependency/lint/package` call sites stay
  pinned positively; t20 new pins the bump-leg index curl's `--retry`).
  `dev-forgejo-runner.sh` ACT_LABELS constant + t14 record
  (rewritten truth: baked derivative, calendar-pin manual bumps, no digest in
  the record). `gpu-forgejo-runner.sh` ACT_LABELS + g2 equality; **g7 must be
  amended** — its current legs forbid ANY `charts/forgejo-runner/values.yaml`
  change and cap the chart diff at 2 `docker://` lines, so the re-point reddens
  it by design (§F6); the replacement pins semantics (only label lines move,
  every `+` docker:// line names the baked image), dev-surface invariance kept.
  `forgejo-ci-surface.sh` needs NO edit (four-file inventory and ROLE-guard
  legs are untouched; the prose bullet must dodge its banned-token list —
  stated in C07). New suite `tests/containers/forgejo-runner.sh` (D41 — the
  `tests/containers/forgejo-host-runner.sh` pattern: static Dockerfile
  contract + hadolint-with-skip + `docker build => no-daemon, CI-deferred`
  designed shape; `containers/<img>/tests/` python dirs are for shipped
  tooling only, and none ships here).

### Commands (fix-round additions; agent-shell law `export PATH=$HOME/.local/bin:$PATH` first)

- `bash tests/containers/forgejo-runner.sh` (new, C05)
- `bash tests/services/dev-forgejo-runner.sh` · `GPU_RUNNER_DIFF_BASE=origin/main bash tests/services/gpu-forgejo-runner.sh` (C06)
- `bash tests/services/forgejo-release.sh` (C07, 20 legs)
- `bash tests/services/forgejo-ci-surface.sh` · `bash tests/services/forgejo-main-sync.sh` · `bash tests/services/forgejo-packages.sh` (regression)
- `helm lint charts/forgejo-runner` + `helm template charts/forgejo-runner` (C06)
- pin truth: `TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:ownyourio/forgejo-runner:pull" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'); curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/ownyourio/forgejo-runner/tags/list`
- base digest truth: `curl -sI -H "Authorization: Bearer <catthehacker/ubuntu pull token>" https://ghcr.io/v2/catthehacker/ubuntu/manifests/act-24.04 -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' | grep -i docker-content-digest`
- prose drift (C07): `npx --yes rulesync@37.0.0 generate --check`
- `npx --yes aislop@0.20.0 ci --changes --base origin/main --human` (every chunk)
- `docker build => no-daemon, CI-deferred` is the designed passing shape for the
  image legs (cf-77 ruling) — the containers-build fire on the merged branch is
  the authoritative build test.

### Landing order / owner first-fire observation (UA-7..UA-10)

D42 ruling: **SINGLE PR**. C05+C06+C07 merge together and the bootstrap red is
DESIGNED, not an accident. The runner flip does NOT wait on the release
pipeline (no circular dependency): `forgejo-runner` deploys straight from the
git path of GitHub main (EXPLORE §5 — internal charts with no `version:` pin
need no chart publish to roll their config; the label map rides the rendered
Secret + reloader), so main-sync + ArgoCD + the pod restart carry the flip on
the merge itself. Order of operations, all effects riding the ONE push to
Forgejo main:

1. `containers-build` fires (paths `containers/**`) and builds
   `forgejo-runner` — its job schedules within seconds, almost certainly still
   on the OLD act image (the pods flip only at step 3) — and publishes
   `26.11.1` + `:main` + `:latest` to ghcr and the instance registry. The
   published tag is readable in that run log (or the tags/list recipe).
2. `main-sync` fans Forgejo main to GitHub main, and `release` fires (paths
   `charts/**`). The first release run reddens early in one of the DESIGNED
   shapes: `helm: command not found` in `test-build`'s first helm-invoking
   step (old image, pre-restart), or a container-creation pull error on a
   not-yet-published pin (restarted, pre-build). The bump never ran — no
   chart-bump commit, no publishes. This is the expected bootstrap cost of
   the single merge, not a regression; the owner does NOT retry-fix anything.
3. ArgoCD syncs both runner releases from GitHub main, the ExternalSecret-
   rendered `config.yaml` re-renders with the new label map, and the reloader
   restarts `gpu-forgejo-runner-gpu-0` + `dev-forgejo-runner-dev-0`. The next
   job scheduled on a 24.04-family label pulls the baked image.
4. **UA-7 — the single-merge observation leg** (this slot formerly carried
   the recommended split-merge option; retired by D42, the observation duty
   takes its name). Once step 1 published the tag and step 3 restarted the
   runners, the owner RE-RUNS the failed release run — the re-run reads the
   same post-C07 workflow SHA against the flipped runner config. That re-run
   is the clean first fire.

How to read the re-run's log — what proves the bake now that D43 retired the
presence steps:

1. `test-build`'s plain-helm steps simply SUCCEED: "Add repositories" runs
   `helm dependency list` and "Lint and package smoke" runs `helm lint` /
   `helm package` — the binary they invoke IS the baked one, and the job list
   shows NO "Set up helm" and NO "Install cr" step (the D32-twin shape is
   gone; t5/t19 pin exactly that). `release` / `forgejo-publish` reaching
   `cr package` / `cr upload` / `cr index` success is the baked-cr proof. A
   mis-baked image fails LOUDLY at the first plain `helm`/`cr` call with
   `command not found` — the designed absence-of-installer check.
2. The fire's chart list will include `forgejo-runner` itself (C06 edits
   charts/) — expect ONE benign patch bump commit on main + its dual publish
   (same class as the original run's predicted llama-swap bump, N-1).
3. If a job dies at container creation with a pull error on
   `ownyourio/forgejo-runner:26.11.1`, the pin predates the merge month (the
   real first tag is e.g. `26.12.1`) or the build lagged — verify with the
   tags/list recipe, amend the one label-pin line in
   `charts/forgejo-runner/values.yaml` (UA-8), let ArgoCD re-sync, re-run.
4. Watch the first pull against the 10Gi `docker-data` PVC (the act base is
   multi-GB and the new digest may not share layers with the cached copy): if
   the pull fails on no-space, prune inside the runner pod
   (`kubectl exec -n default <runner-pod> -c dind -- docker image prune -a -f`
   — owner-run command, agents have no pod exec per AGENTS MCP law). Owner
   confirmation that both runners (gpu `gpu-forgejo-runner-gpu-0`, dev
   `dev-forgejo-runner-dev-0`) restarted and re-registered is the rollout
   gate (UA-9).
5. Follow-up, optional (UA-10): prove the instance-registry anonymous `/v2/`
   pull runner-side (cf-6 proved org visibility only, §F4); if proven, a future
   LAN-pull ruling may move the label refs to
   `git.spencerslab.com/curatedforest/forgejo-runner:<pin>`. Nothing in this
   fix round assumes it.

### Open questions — fix round — ANSWERED (batched round 2026-11-21; rulings
D42/D43 + confirmations, verbatim in DECISIONS.md. Original best-guess
answers were: 1 bake, 2 adopt-3.22.1, 3 ghcr, 4 unmoved, 5 split-merge,
6 keep-verify, 7 predict+UA-8 — items 1–4 CONFIRMED, items 5–6 OVERRIDDEN,
item 7 settled by the override's shape.)

1. cr: baked vs vendored vs download-with-retry → **CONFIRMED (D37 stands)**:
   baked, 1.10.1 + verified sha migrated to the Dockerfile ARG; vendoring and
   retry-only stay rejected.
2. helm v3.22.1 vs v3.16.4 → **CONFIRMED (D38 stands)**: v3.22.1 adopted
   (coder-workspace pin + GitHub-hosted preinstall equivalence,
   renovate-tracked); no 3.16.4 revert.
3. Pull registry: ghcr vs instance → **CONFIRMED (D39 stands)**: ghcr, the
   proven anonymous runner-side path; the LAN-pull upgrade stays the
   owner-verified UA-10.
4. `ubuntu-22.04` label stays plain act-22.04 → **CONFIRMED (D40 stands)**:
   unmoved.
5. Landing: split merges vs single PR → **D42 OVERRIDE**: owner chose the
   SINGLE PR — C05+C06+C07 merge together, the bootstrap red is designed, the
   owner's re-run after publish + sync + restart is the clean first fire;
   UA-8 carries the month-crossing one-line amend. The landing section above
   is the written order of operations.
6. `Verify toolchain` steps → **D43 OVERRIDE (against the planner's keep)**:
   the three steps are RETIRED. t19 pins absence-of-installs +
   presence-of-WORK with no step-presence limbs; the t5 flip is unchanged;
   t20's index-curl `--retry` (resilience, not a presence assertion) STANDS.
7. Pin prediction vs blocking on a live tag → **settled by D42's shape**: the
   single merge makes the dev-time registry provably empty, so the walk-rule
   `<yy.mm>.1` prediction is the shipped literal; the merge's own
   containers-build fire verifies it and UA-8 is the one-line contingency.

### Out of scope (fix round)

The five `.github` gate workflows (GitHub-hosted runners preinstall helm,
RESEARCH C1); consumer migration to instance registries (pre-existing
follow-up card); the agent-side get.helm.sh fallbacks in tests (different
class, §F1); `charts/forgejo-runner` daemon/dind pins (untouched, renovate-
tracked); host-backend `forgejo-host-runner` toolset (its jobs need no helm);
`[packages]`/registry enablement (already merged, C04).

## Fix round 2 (2026-11-23) — repo-add loop completeness: `exit` → `next`

**Goal:** make the "Add repositories" loop complete — every URL-shaped
dependency row of every chart is `helm repo add`-ed on every fire in all three
jobs — so `cr package`'s lock-driven dependency Build resolves every chart's
Chart.lock and the release leg goes green through the four victim charts.

Authority: owner re-run evidence (the merged fix-round-1 release re-run packed
389ds/actualbudget/amd-gpu/archon/audiobookrequest/audiomuse-ai — the bake
worked, the 127/ECONNRESET classes are closed — then died at `Publish GitHub
Releases and the Pages index`: `cr package` → `Error: no repository definition
for https://charts.jetstack.io, https://charts.christianhuth.de`, exitcode 1)
+ EXPLORE.md "Fix-round-2 scout (2026-11-23)" §A0–§A7 (THE ground truth:
root cause reproduced end-to-end, TEST D = the owner's error verbatim, TEST F =
the fix shape proven green) + D45 (this round's ruling). Lease: shared CICD set
8ebe5219 with #139 on the owner's explicit word.

### Root cause (one paragraph, scout §A0/§A1/§A4)

The release pipeline is not missing the hardened repo-add loop — it carries it
three times (`release.yaml` :117-130/:300-313/:360-373) and the step RAN GREEN.
The loop itself is the defect: cf-77 r2's awk ends `{ print $1, $i; exit }` at
:125/:308/:368. Program-`exit` TERMINATES the awk after the first emitted row;
`next` would skip to the next record. So each chart registers only its FIRST
URL-shaped dependency row. `cr package` v1.10.1 `Build()`s unconditionally per
chart before packaging (source-verified: packager.go CreatePackages, explicit
downloadManager.Build + DependencyUpdate=true) and Build resolves EVERY lock
URL against the repositories file — undefined ones surface exactly the owner's
error. Victims = the four multi-URL charts {base, k8s-monitoring, postiz,
traefik} (scout §A2 full-74-chart simulation; the six that packaged are
single-row charts). Lineage (scout §A3): the twin-era loop printed EVERY row and
was green; `c4d74dfc4` (cf-77 r2) fixed the empty-REPOSITORY-column break while
introducing this completeness regression, was an ancestor of the twin deletion,
and was ported VERBATIM into all three Forgejo jobs at rebuild — the bug was
born unfired and this owner fire was its first-ever victim. **The defect lives
in cf-55's shipped surface; no other ticket owns it** (D45 supersession fact).

### Fix-round-2 chunk

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C08 | `exit`→`next` at the three awk sites + t6 comment re-truth + new t21 completeness leg | S | 1 | [] | — standalone bug fix on the shipped file: wave 1 is the test→dev→review round on release.yaml's three byte-identical carriers; all three must flip in one commit (an unchanged copy stays a time bomb — scout §A6); no interface from any prior chunk is in flight (C05–C07 are merged and untouched) |

### Central design (D45)

- **(a) minimal-mechanical ACCEPTED**: one-word swap `exit` → `next` at
  :125/:308/:368 only. Keeps cf-77's per-row URL-shaped field guard (empty
  REPOSITORY column still yields no pair) while restoring all-rows iteration —
  exactly TEST B'/F. Blast radius: 3 words + test prose.
- **(b) static complete URL list REJECTED with evidence**: deletes
  `helm dependency list` from the blobs → reddens t6 (:240) and t19
  (:1043-1050) re-pinning both, kills the cf-77 empty-column narrative, and
  zero resilience — the next chart with a NEW repo reproduces this class
  silently (the same staleness that let this bug survive 4 weeks unfired).
- **(c) vendoring committed tgz REJECTED with evidence**: blocked by
  `.gitignore:3` law first; rots at the next renovate bump (stale tgz vs fresh
  lock sends Build back through repo resolution — the TEST-C path), and only
  moves the failure unless repo-add ALSO stays complete ⇒ (a) required
  underneath anyway.
- **Test-wave delta — RULING: include the completeness leg.** t6 has zero
  completeness teeth (nothing reddened while the loop under-added); the new
  t21 leg replays each of the three landed awk carriers against a base-shaped
  3-row fixture demanding ALL THREE pairs emit (TEST-D-shaped teeth), plus
  single-row / oci-only / empty-REPOSITORY / zero-dep fixtures (AC3 class) —
  the t15 carrier-replay pattern, offline, no network.
- **Comment truth**: the t6 suite comment (:233-236, "first URL-shaped field"
  scan copied VERBATIM from the proven loop) currently blesses the bug and is
  re-truthed with the fix; the three cf-77 workflow step comments narrate
  per-ROW rationale, stay TRUE, and do NOT move (AC5).

### Out of scope (fix round 2)

- **The URL list is dynamically derived — there is no static list to extend**
  (the derivation stays: `helm dependency list` per chart + per-row field
  scan); option (b) rejected, see D45.
- The two-registry walk, the bump loop, the FF-only/single-writer laws, the
  index-curl `--retry`, the oci:// skip, the five-workflow posture, D42's
  landing shape — all UNCHANGED (scout §A1: the bump job runs NO helm; the
  launch-brief premise that it did is false by evidence).
- **UA-11 — runner egress to the five newly-registered hosts** (jetstack,
  christianhuth, prometheus-community, go.temporal, crowdsecurity): the fixed
  loop will `helm repo add` (index fetch at add time) hosts the runners never
  fetched. Workspace-proven only (TEST F); NOT proven from the instance
  runners. Recorded as the OWNER first-fire watch item (D37-class like the
  bump index fetch) — a landing contingency, NOT code.
- docker/CI-deferred posture unchanged; no container or chart surface moves.

### Landing (fix round 2)

C08 is one micro-commit on the ticket branch (test wave first: t21 red-for-
right-reason naming all three jobs; dev greens it; review re-runs). Owner
path: merge → the NEXT release fire (or a re-run) walks repo-add completely —
expect `cr package` to green through base/k8s-monitoring/postiz/traefik; if a
victim chart dies at the add step on a fetch error to one of the five new
hosts, that is UA-11 materializing (owner-side egress observation, benign
re-run posture as D42 established).

### Commands (fix-round-2 additions; agent-shell law `export PATH=$HOME/.local/bin:$PATH` first)

- `bash tests/services/forgejo-release.sh` (21 legs after the t21 delta)
- regression, byte-unchanged baselines: `bash tests/services/forgejo-ci-surface.sh` ·
  `bash tests/services/forgejo-packages.sh` · `bash tests/services/forgejo-main-sync.sh`
- scratch replay harness allowed (`/tmp` only — carrier extraction + mutation
  teeth; live paths never targeted by comparison writes)
- `npx --yes aislop@0.20.0 ci --changes --base origin/main --human` (vacuous
  for yaml/shell — record honestly, standing FRICTION posture)
- `docker build => no-daemon, CI-deferred` unchanged (nothing built this round)
