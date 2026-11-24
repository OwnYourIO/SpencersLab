# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions

- Contract suites for `.forgejo/workflows/*.yaml` follow `tests/services/forgejo-main-sync.sh`:
  bash + embedded python3 (pyyaml), purely offline, one leg per invariant with
  mutation teeth, `set -euo pipefail`, YAML 1.1 note (`on:` parses as boolean True —
  read `doc.get(True) or doc.get('on')`).
- Lab runner labels (the only routable set): `ubuntu-latest`, `ubuntu-24.04`,
  `ubuntu-22.04`, `docker`, `node22`. `ubuntu-26.04` routes nowhere on lab runners.
- Forgejo secret/var names in workflows must avoid the reserved `GITHUB_`/`FORGEJO_`
  prefixes (main-sync t5 law) and never reference the automatic token for
  cross-forge writes; same-repo writes MAY use it (and that's the loop guard).
- Every moved workflow keeps its GitHub-era file NAME (`release.yaml`,
  `docker-build.yaml`) under `.forgejo/workflows/` — a dozen bare-name prose and
  test needles cite those names (tests/pipeline-push-pr/surface.sh P3/P7, AGENTS
  hard rules, suite comments); only path-citing references move.

## Decisions

- 2026-11-10 plan D1 scope: move only the two matrix builders (`release.yaml`,
  `docker-build.yaml`); the five single-job gate workflows (aislop, rulesync, three
  render-tests) stay on GitHub. Rejected: full-CI move — the card names "parallel
  builds"; gate moves hinge on the PR-platform question (OQ-6) and would drag
  aislop-pin-parity and pipeline allow-set tests in lockstep for no build-parallelism
  gain. Recorded as OQ-1.
- 2026-11-10 plan D2 publish target = RESEARCH option 1: keep GitHub Releases +
  gh-pages index, publish FROM Forgejo with a dedicated cross-forge PAT
  (`RELEASES_TOKEN_GH`). Rejected: option 2 (Forgejo Helm package registry — sweeps
  7 live + 4 umbrella consumer `repository:` pins + all renovate `datasource=helm`
  annotations + appset template + anonymous-visibility unknown) and option 3 (OCI —
  appset-template rework, breaks the renovate helm managers as the repo's own
  `charts/forgejo/Chart.yaml:8` comment concedes, needs action/cr pin bumps).
  Zero consumer diff wins for this ticket; registry/OCI = follow-up cards. OQ-2.
- 2026-11-10 plan D3 action policy: moved workflows use only mirror-confirmed
  actions (`actions/checkout`, `azure/setup-helm`, `docker/*`); non-mirrored
  (`dorny/paths-filter`, `EMAsphere/bump-helm-chart-action`,
  `EndBug/add-and-commit`, `helm/chart-releaser-action`) replaced by inline
  equivalents (git-diff detect loop, stdlib python patch bump, raw git, `cr` CLI).
  Rejected: absolute `https://github.com/...` `uses:` — unproven runner egress to
  github.com for clones and mirror-scope drift (RESEARCH A2/A4); the `cr`-direct
  route also dodges the wrapper's `GITHUB_REPOSITORY` owner trap and default-`origin`
  pages-remote trap (B1/X5).
- 2026-11-10 plan D4 bump-collision fix: the `bump` leg becomes a single job that
  loops the changed charts (one checkout, one writer), fixing the known-broken
  release.yaml:144-145 TODO ("maybe loop instead of matrix") instead of inheriting
  it; concurrency-group hacks die with it. EXPLORE §9-7 read: the owner expects the
  move to fix this.
- 2026-11-10 plan D5 bump landing: Chart.yaml bumps push to prod-Forgejo `main`
  with the automatic same-repo token — no workflow re-trigger, which is exactly the
  loop guard AND keeps main-sync's next human push fast-forwarding GitHub. Rejected:
  bumping GitHub main directly (PAT pushes re-run GitHub workflows — the dead
  release.yaml twin would have to stay deleted forever, and it re-opens the non-FF
  hazard direction main-sync was designed against). GitHub-side lag accepted
  (RESEARCH B5-ii). OQ-3.
- 2026-11-10 plan D6 container registry stays `ghcr.io/ownyourio/*`, pushed
  cross-forge with a classic PAT (`GHCR_PUSH_TOKEN`, write:packages — GitHub docs:
  fine-grained PATs cannot do Packages, RESEARCH [1]/B3) + `vars.GHCR_PUSH_USER`.
  Rejected: instance OCI registry (every chart pin + renovate docker datasource in
  the repo moves — far beyond this card). OQ-5.
- 2026-11-10 plan D7 tag scheme: `v$((10000 + run_number))` on the Forgejo builder.
  Rejected: raw `v<run_number>` (Forgejo counter restarts at 1 → would re-mint
  existing immutable tags `v1..v~163` and poison the "registry maximum isn't
  automatically yours" rule), date-based `v<yyyymmdd>.<n>` (works but abandons the
  established monotonic-integer shape the pinning recipes and Renovate ordering
  rely on), branch-tag-only (loses the immutable-tag law). Offset 10000 keeps one
  monotonic space per builder, disjoint, semver-orderable. OQ-4.
- 2026-11-10 plan D8 guards: every job in every moved workflow carries
  `if: vars.ROLE == 'prod'` — the dev instance receives the synced repo and PAT-
  authored sync pushes DO re-trigger instance workflows; unguarded twins would
  double-publish from dev. This is main-sync's own precedent (its suite t3).
- 2026-11-10 plan D9 helm toolchain: pinned `azure/setup-helm` per helm-running job
  (mirror-confirmed; get.helm.sh default download, GitHub-API-free). Rejected:
  custom CI image under `containers/` (label→image freeze law, RESEARCH C2-3) and
  per-job curl installs (bigger file diff than one setup step). act-24.04 proven to
  lack helm (RESEARCH C1 — upstream act.sh inventory).
- 2026-11-10 plan D10 cutover shape: per-workflow single commit — add `.forgejo`
  twin + delete `.github` twin + re-point bound tests together. Rejected: dual-run
  transition window (two bump authorities collide on `charts/**` — EXPLORE §9-10's
  central tension; the double-publish window of RESEARCH B5-iii). Green-before-
  delete cannot be pipeline-proven anyway (first fire is user-side, UA-5); the plan
  optimizes for no-coexistence instead.
- 2026-11-10 plan D11 docs lockstep grouped into one chunk (C03): all AGENTS
  (`from .rulesync/rules/`, regenerated), skill (`skills/` + `.rulesync/skills/`,
  regenerated) and container-README prose that describes the post-move world, plus
  one `rulesync generate` pass — instead of each builder chunk editing the generated
  surfaces separately (two regenerations over a half-moved truth invite drift; P6
  gate).

## Deferred

- 2026-11-10 plan: PR-gate workflows (aislop/rulesync/render-tests) move,
  consumer migration to the instance registries (visibility/auth questions bind
  that follow-up card — D20), second-runner repo slice pending UA-3's Bitwarden
  item (D21), `[skip ci]`-style push policies, package pruning automation
  (needs a `delete:packages` decision — deliberately ungranted, D16). The
  batched-round rulings R1–R9 closed the drafting OQs; these deferrals are the
  post-ruling follow-ups.

## Decisions — batched-round owner rulings (2026-11-10, verbatim answers; OVERRIDES marked)

- 2026-11-10 human R1 (OQ-1): "Yes — two builders only." The five gate workflows
  stay on GitHub. (Confirms D1.)
- 2026-11-10 human R2 (OQ-2, OVERRIDES D2 — was single GitHub store): "So for now,
  I'd like both the github releases + gh-pages published from Forgejo, and I'd also
  like a forgejo helm package registry. Figure I'll test and move services over as
  I have time and it's OK to leave this project building and pushing to the forgejo
  repo, but leaving all of my services left pointing to where they currently are."
  ⇒ DUAL chart publish; every consumer stays pointed at GitHub byte-stable; service
  migration = follow-up card at owner's pace.
- 2026-11-10 human R3 (OQ-3): "Forgejo main only." Bump commits push solely to
  prod-Forgejo main with the automatic token; no GitHub-side push from CI.
  (Confirms D5.)
- 2026-11-10 human R4 (OQ-4, OVERRIDES D7 — was `v$((10000+run))` offset):
  "Date-based." Concrete immutable spelling pinned by the plan:
  `v<UTC-YYYYMMDD>.<minute-of-day>.<run_number>` (see D15).
- 2026-11-10 human R5 (OQ-5, OVERRIDES D6 — was ghcr-only): "Both." Containers
  push to ghcr.io/ownyourio AND the prod instance's OCI registry; no chart pin or
  consumer change in this ticket (follow-up card may share R2's migration card).
- 2026-11-10 human R6 (OQ-6): "Accept; triggers wired on twins for later
  re-enable." PR-time validation on Forgejo stays dormant until PRs open there.
  (Confirms the drafted posture.)
- 2026-11-10 human R7 (OQ-7, OVERRIDES the drafted secret names): "Extend existing
  PUSH_TOKEN_GH" — no `RELEASES_TOKEN_GH`/`GHCR_PUSH_TOKEN`; the one secret gains
  what it needs (see D16); owner re-mints scopes; `delete:packages` avoided; ghcr
  username rides a plain non-secret var `GHCR_PUSH_USER`.
- 2026-11-10 human R8 (OQ-8, OVERRIDES "accept serialization" — now): "Provision a
  second runner now" (owner-side registration + Bitwarden item + slice once the
  UUID exists — UA-3). Forces the two-runner bump-safety design (D17).
- 2026-11-10 human R9 (OQ-9, OVERRIDES "keep type=gha, downgrade later"): "Use
  registry cache from the start" (placement D18; the registry-push leg doubles as
  auth proof; hygiene cost accepted).

## Decisions — post-ruling plan implementation (2026-11-10)

- 2026-11-10 plan D13 (implements R2): dual-publish topology — `release` (GitHub)
  and `forgejo-publish` (instance Helm registry) are INDEPENDENT jobs (neither
  needs the other): a registry outage reddens only its own job loudly and can
  never block or wait on the GitHub publish; serializing `forgejo-publish` after
  `release` was rejected because it couples the two failure domains backwards
  (a red GitHub leg would silently skip the registry leg). Rejected: step-level
  `continue-on-error` on a combined leg (hides the outage in a purple step —
  ruling says LOUDLY).
- 2026-11-10 plan D14 (implements R2/R5): same-forge credential law — the
  instance-side legs (helm package push, instance OCI login) authenticate with
  the runner-injected automatic token (`${GITHUB_ACTOR}:${GITHUB_TOKEN}` env /
  `${{ github.actor }}`+`${{ github.token }}` per docker/login-action), the
  documented in-workflow package-upload path (RESEARCH [2]); instance URLs are
  composed at runtime from `GITHUB_SERVER_URL`/`GITHUB_REPOSITORY` — NO
  instance-URL literal enters a workflow file (main-sync portability law).
  Cross-forge legs use `secrets.PUSH_TOKEN_GH` only. Fallback if first-fire shows
  the automatic token cannot write packages (401): owner mints a Forgejo PAT as a
  new named secret — recorded as UA-5, not silently assumed.
- 2026-11-10 plan D15 (implements R4): date-tag spelling
  `v$(date -u +%Y%m%d).$((10#$(date -u +%H%M))).<run_number>` — all-numeric
  semver so Renovate's docker datasource orders bumps with zero versioning
  config; legacy-disjoint by shape (major ≈ 20261110 ≫ 200); run_number patch
  guarantees same-minute uniqueness (immutable tag never overwritten);
  minute-of-day numeric form avoids leading-zero minors (00:45→45, still
  order-correct inside a date). Rejected: the ruling's illustrative
  `v<YYYYMMDD>-<HHMM>-<short-sha>` (hyphen/dash form is not semver-comparable
  by renovate's default docker versioning — would need a per-pin versioning
  regex across every consumer, contradicting the ruling's own
  "renovate must still be able to compare bumps" requirement);
  `v<YYYYMMDD>.<HHMM>` without the tiebreaker (same-minute pushes silently
  re-mint an "immutable" tag). One-time major-jump on the first post-cutover
  bump is documented, expected.
- 2026-11-10 plan D16 (implements R7): `PUSH_TOKEN_GH` becomes ONE classic PAT
  (`repo` + `write:packages`, NO `delete:packages`) serving main-sync's push-gh,
  `cr`'s Releases/gh-pages writes, and the ghcr login (+ buildcache push). Forced
  by RESEARCH [1]: fine-grained PATs cannot touch Packages, so "extend the
  existing fine-grained PAT" (its cf-119 shape, plan:184) means re-mint-as-
  classic; classic `repo` covers everything main-sync used the old PAT for, so
  main-sync.yaml needs NO edit and its suite stays green (its t5 counts occurrences
  per-file; other files may reference the same secret).
- 2026-11-10 plan D17 (implements R8 consequence): two-runner bump safety =
  Forgejo documents `concurrency:` but only best-effort group semantics
  (RESEARCH A3/[2]) — so the bump job is an IDEMPOTENT single-writer loop: pull
  main → recompute each chart's next patch against tree + published index →
  FF-only push → bounded retry on rejection (re-pull/re-check; refused push never
  overwrites). A `concurrency` group may stay as opportunistic belt-and-braces
  with a comment saying it is not the safety property. Rejected: relying on
  concurrency alone (documented best-effort; two runners break the old
  serialization assumption); registry-write lock files (reinvents what git
  fast-forward semantics already guarantee).
- 2026-11-10 plan D18 (implements R9): buildcache placement
  `ghcr.io/ownyourio/<container>-buildcache:<branch-tag>`, `mode=max`, default
  ignore set, `cache-from` always / `cache-to` non-PR only (a PR must not write
  the cache a publish rides); ghcr-only (one cache store, credential already
  proven by the push leg). Rejected: instance-registry cache (couples cache auth
  to the unproven instance-OCI first fire); `type=local` (PVC-backed dind survives
  daemon recreation but not runner pod recreation — cache hit rate unpredictable).
- 2026-11-10 plan D19 (implements R2-b enablement question): instance registry
  enablement IS repo-side — `custom-values/infra/prod-values.yaml` already drives
  per-instance `gitea.config` maps (APP_NAME/server/lfs/mailer), and the chart's
  own comment establishes the declaration-is-the-gate pattern (:92-100) with the
  inline-config Secret render path (:70-76). So it becomes chunk C04 with
  `tests/services/forgejo-packages.sh`, NOT a UA-only admin task. Rejected:
  adding `FORGEJO__PACKAGES__*` legs to the chart's static
  `additionalConfigFromEnvs` (chart law :145-151 forbids slices overriding that
  list; and the gate belongs per-instance, not chart-wide). `[storage]` S3 stays
  deliberately untouched (would drag attachments/avatars/packages — chart
  comment).
- 2026-11-10 plan D20 (implements R2/R5 migration posture): dev instance gets no
  `packages` block; consumers keep GitHub pointers byte-stable; the owner's
  migration to instance registries is a follow-up card (visibility/auth questions
  — RESEARCH OQ-2 — bind THAT card, not this one, since nothing reads the new
  registries yet).
- 2026-11-10 plan D21 (implements R8 boundary): the second runner's repo-side
  slice is NOT pipeline-preparable today — one release = one registration with
  `uuid`+`token` from a Bitwarden item (charts/forgejo-runner/values.yaml:77-89)
  and the trio contract needs the real UUID in custom-values, so the slice lands
  only after UA-3 mints registration+item (late chunk this run if supplied mid-
  run — coord's call — else follow-up). Chunking it now would ship a sentinel
  that 1:1-gate tests can never pass.

## Rework history

- 2026-11-10 plan rework (this entry set): batched-round rulings R1–R9 applied;
  D2/D6/D7/D8-era single-target designs superseded where marked OVERRIDE; chunks
  C01/C02/C03 reworked, C04 added; STATE gains C04, C03 depends_on grows.

## Decisions — post-approval delta (RESEARCH "Post-plan round" V-1..V-6, 2026-11-10)

Grounded by the card's checked `Post Research` stage; owner ruled on the single
plan-changing finding (F-1). `plan_status` stays approved — this is delta work.

- 2026-11-10 human+plan D22 (F-1; OWNER RULING "Add a Forgejo-PAT secret";
  SUPERSEDES D14's credential limb, marks R7's "no new secret names" void for
  same-forge legs): the automatic workflow token provably CANNOT push packages on
  Forgejo 15.0 — basic.go maps the task token to a synthetic Actions user with
  `Scope() → None`, `reqPackageAccess` falls through to the package-permission
  check, and `services/packages/perm.go` carries the unimplemented
  `// TODO: ActionUser permission check` (V-2 chain [38]–[46]; the docs'
  "uploading to a package registry" line [2] never documents the workflow token
  as a package credential — D14 read it too generously; community corroboration
  [44]; not a Gitea-fork artifact [45][46]). New law: C01 `forgejo-publish`
  (helm `curl --user` upload) and C02's instance OCI login authenticate with
  Actions secret `secrets.PUSH_TOKEN_FJ` — a CLASSIC Forgejo user-PAT with
  packages write minted from the account owning the `CuratedForest` package
  namespace — plus Actions var `vars.FJ_PACKAGE_USER`. The refuted auto-token
  fact becomes a why-comment in the workflows; the suites' credential-topology
  legs (C01 t8/AC7, C02 t6/AC5) now PIN THE WORKING SHAPE and explicitly ban
  `github.actor`/`github.token` on package/OCI legs — the previously drafted
  "zero secrets in the instance legs" assertions enforced a provably-401 design
  and are replaced, not kept. Unaffected by V-2: the bump push's same-repo
  automatic git credential and its non-re-trigger loop guard are documented-true
  [43]; UA-5's "401 fallback" framing is retired (the PAT is the primary shape,
  registration = UA-1b).
- 2026-11-10 plan D23 (F-1 username carrier): the instance-leg username rides
  plain Actions var `FJ_PACKAGE_USER`, NOT a baked login literal — same
  repo-agnostic reason as `GHCR_PUSH_USER` (the synced file lands on both
  instances; a baked personal login would leak an admin identity into every
  copy and break the dev-instance portability posture; the var name also joins
  the `PUSH_TOKEN_*`/`*_USER` family and passes the reserved-prefix law).
  Pairs `FJ_PACKAGE_USER`+`PUSH_TOKEN_FJ` are pinned as the canonical names for
  BOTH instance legs (C01 helm push, C02 OCI login) — one credential, one shape.
- 2026-11-10 plan D24 (F-2; SUPERSEDES D19's key literals — declaration path
  itself CONFIRMED by V-3 [47]): v15.0 `[packages]` has NO generic `LIMIT_SIZE`
  (declaring it renders into app.ini and is silently ignored — C04's drafted key
  set `{ENABLED, LIMIT_SIZE}` enshrined the wrong literal) and size caps are
  per-type: `LIMIT_SIZE_HELM`/`LIMIT_SIZE_CONTAINER`, default `-1` unlimited
  [16]; `ENABLED` already defaults TRUE, and the upstream chart ships
  `gitea.config.packages: {}` rendering generically into the inline-config
  Secret [47]. Decisions: C04's declared map is EXACTLY `{ENABLED: "true"}` —
  explicit-on pin retained as a deliberate declaration (C04's anticipated-
  default note now resolved); size caps ABSENT (default unlimited — declaring
  caps is scope creep; owner adds per-type keys later at leisure via UA-4's
  noted path). `[quota]` stays default-disabled, untouched.
- 2026-11-10 plan D25 (F-3 nits + test-writer guards, no topology change):
  (a) V-1a wording — the date-tag minor is `HHMM` (base-10 coerced),
  "time-of-day (HHMM, base-10)", NOT "minute-of-day"; arithmetic unchanged and
  V-1 confirmed the `10#` coercion is load-bearing (leading-zero minors are
  invalid semver); C03 prose tasks + plan spelling updated; V-1b note added
  (non-semver rolling tags never compete under docker versioning).
  (b) V-5 — buildx setup step is LOAD-BEARING for `type=registry` (the default
  docker driver needs the containerd image store, lab dind is plain
  moby/overlay2, so the `docker-container` driver from setup-buildx is required
  [51]): new C02 suite leg t11 pins existence + ordering before build-push.
  (c) V-4 — confirms D17 unchanged; documents that concurrency gates RUNS not
  jobs and FF-refusal is git-native (test-writer note recorded in C01 t7).
  (d) V-6 — the inline replacements' shallow-clone failure modes become explicit
  suite legs: fetch-depth 0 on every diffing/cr job (C01 t12, C02 t11),
  tag fetch before `cr` (C01 t12), detached-HEAD-correct remote-tip re-read
  INSIDE the retry loop + refspec push shape (C01 t7 tightened).
- 2026-11-11 coord D26 (test-wave adjudication accepted): C03's stale-path sweep
  reddens a fifth file its task list omits — `containers/renovate-mcp/Dockerfile`
  (comment cites the deleted `.github/workflows/docker-build.yaml` path); evidence
  `git grep -lE '\.github/workflows/(release|docker-build)\.yaml'` returns exactly
  the five paths. The one-line comment fix FOLDS INTO C03's scope (its
  Files-in-scope grows by that file; prose-only, no build behavior). Also recorded
  as law from the test wave: job-level `if: vars.ROLE == 'prod'` EXACT equality
  (gating goes step-level), and C01 t8 pins the `--user` curl credential reading
  `FJ_PACKAGE_USER`/`FJ_PKG_TOKEN` step envs (step-env name variants are a review
  judgment on topology preservation, not a weakening).
- 2026-11-11 coord D28 (C02/C04 closure): C02 APPROVED r1 (five deviations
  adjudicated, incl. the single-clock date-tag computation as a STRICT
  improvement over D15's two-call literal — midnight-straddle inversion
  removed; D15's pinned tokens survive per test-wave ruling (e)). Coord
  call on C02's MINOR-1 (uppercase CuratedForest owner saved only by
  metadata-action v6 toLowerCase + Forgejo v15 lowercase-only
  imageNamePattern — both independently source-verified by review):
  ACCEPTED as documented-and-implicit (behavior proven at the pinned
  versions; an explicit-lowercase edit inside C02's shipped file
  post-approval is not worth a reopen; re-verify when metadata-action is
  next bumped — rides the existing renovate lane). C04 APPROVED r1
  (exactly {ENABLED: "true"}, real-render t6 proof; string-vs-bare-bool is
  the PLAN-PINNED shape — do not "normalize" it).
 - 2026-11-11 coord D29 (C03 closure + extension record): C03 APPROVED r1.
 - 2026-11-11 coord D30 (final closure): whole-plan review APPROVED (seams 1-8
  verified incl. the end-to-end bump/skip-existing/OverwriteExisting race
  re-derivation — no double-publish, no silent skip, red index pushes
  self-heal). Zero blocking findings; repo-side pre-existing reds stand at
  exactly three (c11/c19/t17, message-identical at the base). M-1 (three
  prose surfaces narrating the dormant PR-build lane) routed onto the
  D29(2) follow-up sweep card — same class, one coherent owner action, no
  reopen of an approved chunk. Landing order owner-critical (N-1): the
  cf-55 merge IS the builders' first fire — register UA-1 (PUSH_TOKEN_GH
  classic re-mint) + UA-1b (PUSH_TOKEN_FJ + vars) BEFORE merging; expect
  one benign llama-swap chart bump from the first fire; C04 rides the same
  PR. plan_status complete.
   Extension accepted: six files beyond the chunk's Files-in-scope
   (skills/helm-chart-creation/SKILL.md + references/mcp-servers.md,
   skills/wekan-api/references/wekan-mcp-ops.md, containers/vllm-radiance-mxfp4/
   Dockerfile comment + README) were prose-forced by AC5's
   banned-scheme-clause + the "any other first-build :v<run> law phrasing"
   instruction (D26 fold precedent, D11 single-generate law) — review
   adjudicated APPROVE, comment/prose-only, posture-identical. Both
   NOT-touched exemptions verified legitimate (cf-96 readback-runbook is
   grep-pinned by its own suite; dev-mcp-fleet.sh is bare-name-only and
   read-only to chunks). Review Deferred routings: (1)
   tests/services/dev-mcp-fleet.sh t7's (main|v[0-9]+) regex cannot match a
   dotted date tag — cf-96's own M2 pin self-reddens post-cutover; routed to
   THIS ticket's test session as a cross-suite mechanical generalize
   (cf-104 ebcdbf421 precedent — our shipped change breaks another suite's
   stale pin); (2) :v<run>-era comments surviving inside other tickets'
   charts/services files — path-based sweep exclusion, follow-up sweep card
   at run end (owner's Inbox); (3) the scope-tripwire false-red on
   uncommitted ticket folders — known cf-96 friction class, no action.
- 2026-11-11 coord D27 (C01 closure bookkeeping; re-appended with its header
  after an earlier coord edit clobbered it — append-only content preserved):
  C01 APPROVED round 3 after two
  real runtime defects were caught and closed in-loop — missing `id: detect`
  (outputs silently empty) and missing `-X POST` (charts route POST-only), then
  BLOCKER 3 (published-index parser pairing an inline `dependencies:` version as
  the entry version — 9/97 live keys wrong, 8 live charts would have minted jump
  releases on first fire; closed by same-indent name/version pairing on BOTH
  carriers, independently re-derived against the live index; t15 value-semantics
  legs pin it). Human-owned Deferred follow-ups: (1) charts/traefik-zerotrust
  declares `name: traefik` (dir≠name class — rename candidate; the fixed parser
  handles it meanwhile); (2) NIT 5 — the parser admits 5 phantom non-entry keys
  from the live index shape, zero collisions with the 72 repo chart names today;
  watch if cr changes entry-key ordering.
  [Placement note (coord): during final bookkeeping a whitespace-matching
  limitation of the edit tool left D27 ordered after D29/D30 and D30 between
  D29's header and body. Content is complete and append-only; ordering is
  cosmetic — read D26→D30 by their labels. No history was rewritten.]

## Decisions — rebuild onto main (2026-11-16)

- 2026-11-16 human+coord D31 (owner rebase directive, verbatim intent: "rebase this
  work onto main in this branch or another, but move this session too"; then the scope
  question answered "New branch, keep old"): cf-6 (commits 2d213bb10 + 043be6645)
  LANDED the container-build move on main (containers-build.yaml: calendar tags
  yy.mm.N, ROLE contains() membership guards, FORGE_PUSH_TOKEN + GHCR_PUSH_PAT, dual
  registries incl. instance OCI, manual-fallback .github twin) — cf-55's C02 is
  SUPERSEDED, not ported; its forgejo-docker-build.sh suite and the
  .forgejo/workflows/docker-build.yaml are gone; 572a20308 (dev-mcp-fleet t7
  generalization for the v-date scheme) is moot (main's t7 already accepts the
  calendar form for the OTHER reason). The rebuilt branch carries the chart half
  (C01) + C04 + a re-derived C03 + the plan folder. Old branch
  cf-55-feat-helm-builds-to-forgejo stays untouched as history.
- 2026-11-16 coord D32 (reconciled contract the port implements, grounded on cf-6's
  landed conventions): release.yaml job guards become NARROW membership
  contains(vars.ROLE, 'prod') (equality retired as live-guard law; unset ROLE fires
  nothing — release joins main-sync/renovate polarity per the bump-is-state-change
  reading; AGENTS.md ROLE-law enumeration extended to four workflows); instance Helm
  publish reuses the SHIPPED secret FORGE_PUSH_TOKEN with cosmetic username forge:
  and the literal lowercase curatedforest namespace (D22/D23's PUSH_TOKEN_FJ +
  FJ_PACKAGE_USER pair RETIRED before ever being provisioned — cf-6's secret already
  exists, so UA-1b shrinks to a scoping confirmation; GITHUB_REPOSITORY
  owner-derivation replaced by the literal cf-6 uses for imageNamePattern's
  lowercase-only law); output writes carry the ${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}
  compat idiom; .github/workflows/docker-build.yaml STAYS (cf-6 manual fallback) so
  only release.yaml's GitHub twin is deleted; the bump-loop/cr/published-index/
  date-pairing-free laws from D13-D17/D22's surviving half carry unchanged.
- 2026-11-21 human+coord D33 (owner continuation directive — the rebuild PR merged
  to main and the FIRST FIRE failed): the rebuilt branch landed via PR (release.yaml
  on origin/main is blob 12160c7fe = the post-fix-restore hash; per-path diffs of all
  32 shipped files against origin/main show our content fully merged, main having
  evolved only via later tickets). Owner ruling verbatim: "this is still cf-55 work.
  You'll need to pull in main, but keep the same naming, we're just testing and
  fixing what you've done previously." Evidence of failure: runner "Set up helm"
  step, read ECONNRESET downloading helm-v3.16.4-linux-amd64.tar.gz from
  get.helm.sh, all three retries, exitcode 1 — the exact egress unknown cf-55
  RESEARCH flagged for UA-5 first-fire observation, now live-proven flaky/blocked.
  FIX APPROACH (owner-confirmed from three options): a CUSTOM act-runner image with
  helm BAKED IN — built by our own containers-build.yaml pipeline, published to the
  instance registry — with the setup-helm steps retired from the workflows. Branch
  handling: git reset --hard origin/main (the redundant squash-merged replay dropped;
  36f6f542d stays reachable as merged history; the remote feature branch, if it still
  exists at 36f6f542d, diverges — its forced update is owner-gated per the
  explicit-request law, never performed by this run unasked). The run now lands under
  main's newer conventions (13-item Lifecycle; Session Rename + Worktree Creation are
  no-ops here — folder, worktree, branch and session all exist from the original run).
- 2026-11-21 human D34 (lease posture): the CICD pipeline key is held live by card
  #135's run (Renovate move, ses_e39eb7bc4ffectkAy9nSpDDzuF); the owner answered the
  batched claim question "Share CICD with #135" — pipeline_claim(cardId #55,
  ["CICD"], shared:true) lands set 627dcc2c as co-tenant; release removes only this
  card's holder (holders-not-files law, cf-106 C08).
- 2026-11-21 human D35 (models, superseding chain): "use openrouter flash going
  forward" — every tier of this run's remaining rounds routes
  openrouter/qwen/qwen3.8-flash, supersedes both the card's Model(s) checklist
  (Qwen Flash, API provider) and the 2026-11-16 local-model ruling for all future
  launches in this ticket; the original card checklist stays untouched on the board
  as the frozen kickoff record.

## Decisions — fix round: baked runner toolchain (2026-11-21)

- 2026-11-21 plan D36 (fix-round image design, per D33's owner-confirmed
  approach and RESEARCH C2 remedy-3): `containers/forgejo-runner/` builds the
  job image behind the runner's act labels as a DERIVATIVE of the current
  production base — `FROM ghcr.io/catthehacker/ubuntu:act-24.04@sha256:<head
  digest>` (digest verified live 2026-11-21, dev re-verifies) — plus helm and
  cr baked to `/usr/local/bin`. The no-regression law (the image serves all
  four .forgejo workflows' jobs: containers-build needs the docker CLI +
  buildx, every job needs the node action runtime + git/git-lfs/jq/python3)
  is satisfied BY CONSTRUCTION: the derivative is the RESEARCH C1 inventory
  plus two static binaries — rebuilding that inventory on a slim base was
  rejected (a too-thin image silently breaks the OTHER pipelines sharing the
  runner; the multi-GB re-assembly buys nothing). Documented deviation from
  the container-creation non-root law: no USER/ENTRYPOINT/CMD/COPY lines — a
  job shell keeps the act base's root user because today's jobs apt-get and
  write system paths (the law serves service containers, not job images).
  Suite placement (D41) keeps the Dockerfile contract in tests/containers/.
- 2026-11-21 plan D37 (cr is BAKED too; the first-fire's whole fragility
  class retires): the two `Install cr` steps (release.yaml :294, :382) are
  the same github.com-egress class that killed the first fire, land in the
  two jobs it never reached, and cr is a static binary — same bake recipe,
  pin pair (1.10.1 + the review-verified sha256) migrates from workflow env
  to Dockerfile ARG with a renovate github-releases annotation. REJECTED:
  vendoring the tarball into git (~15 MB binary, re-opens the supply-chain
  review the sha pin closed); leaving it as download-with-retry (keeps the
  exact failure mode that motivated the fix round waiting in the untested
  legs). The remaining runtime egress in release.yaml is the bump leg's
  published-index fetch — DATA, not a tool install, un-bakeable by nature —
  hardened instead with `curl --retry 3` (new leg t20 pins the hardening).
- 2026-11-21 plan D38 (helm version ADOPTS v3.22.1, not the first-fire's
  v3.16.4): the failed fire pinned v3.16.4 for twin-parity; v3.22.1 is both
  the repo's existing baked-pin (containers/coder-workspace
  Dockerfile:49-50, already on an active renovate lane) and the
  GitHub-hosted-runner preinstall the pre-move workflows implicitly used
  (RESEARCH C1 helm row), so it is the closer parity — same v3 major,
  ArgoCD renders with v3. One-ARG revert to v3.16.4 if the owner rules
  literal-parity instead (Open question 2; impact nil-to-minor on chart
  rendering).
- 2026-11-21 plan D39 (pull side + tag law): the labels name
  `docker://ghcr.io/ownyourio/forgejo-runner:<calendar tag>` — anonymous
  ghcr pull is the runner's PROVEN path (every lab job already pulls ghcr;
  ownyourio repos answer anonymous manifest/tags probes, verified live
  2026-11-21), while the instance-registry anonymous /v2/ pull has never
  been exercised runner-side (EXPLORE §F4/F0 — cf-6 proved org visibility
  only) and the dev runner would additionally need WAN reach to
  git.spencerslab.com; the upgrade to LAN pulls is a separate
  owner-verified move (UA-10), so the fix round avoids BOTH unproven paths
  rather than routing one as a bet. Tag form: the AGENTS containers law
  offers `:main + pullPolicy: Always` or a `:yy.mm.N` pin; the runner has
  no pullPolicy knob on labels and the measured law "runners never re-pull
  a tag they already cached" (RESEARCH C2 remedy-3, renovate.yaml header
  :21-23) makes any rolling ref silently freeze — so an IMMUTABLE calendar
  pin is the only safe shape; a wrong/stale pin fails LOUD (pull error),
  never stale. First tag determinism: a brand-new image's first build
  publishes `<yy.mm>.1` (both registry walks see no tags → `next_n`
  max+1=1 — code-verified 2026-11-21). Since the branch is commit-only (no
  pushable build lane pre-merge), C06 pins dev-time `date +%y.%m`.1 after
  a live tags/list probe, and a merge crossing the month boundary is the
  owner's one-line amend (UA-8). Bumps thereafter are manual + red-first
  (no renovate manager reads the label lines — the values.yaml law comment
  survives the re-point, re-worded).
- 2026-11-21 plan D40 (re-point scope + merge-order safety): exactly the
  four act-24.04-family labels (`ubuntu-latest`, `ubuntu-24.04`, `docker`,
  `node22`) move to the baked image; `ubuntu-22.04` stays plain act-22.04
  (no workflow requests it; a 24.04-content image behind a 22.04 label
  would lie about its OS; helm/cr jobs request the 24.04 family — t4's
  whitelist already bounds what jobs may ask). Intermediate states: the
  ONLY unsafe overlap is a retired workflow ahead of a flipped label
  (helm-less image + no installer), so chunk order C06→C07 is the
  merge-order law too — flipped label + old workflow is safe (setup-helm
  is idempotent over a present binary), old label + new workflow must
  never ship. Bootstrap race: the same merge flips the labels AND first
  builds the image, so a job scheduled after the ArgoCD sync but before
  the build would need image X to build image X — the recommended landing
  is split merges (UA-7: C05 alone first, the build publishes the pin's
  literal on the still-old-image runner; C06+C07 follow); a single PR is
  survivable with the DESIGNED loud shapes (release fire reds at `helm:
  command not found` or a pull error, both self-heal on re-run after
  tag+sync+restart; that re-run is the clean first fire). Rollout risk is
  real — a wrong image ref idles ALL Forgejo CI on both runners — so the
  plan carries the owner first-fire observation (UA-7..UA-9) incl. the
  10Gi docker-data cold-pull watch with the owner-run prune command (no
  agent pod-exec per AGENTS MCP law).
- 2026-11-21 plan D41 (test surfaces, scheduled from explore_handoff): the
  new image's suite is `tests/containers/forgejo-runner.sh` — the
  tests/containers/forgejo-host-runner.sh pattern (static Dockerfile
  contract + hadolint-with-skip + `docker build => no-daemon,
  CI-deferred` designed passing shape, cf-77) — NOT
  `containers/<img>/tests/` (that shape is for python tooling shipped in
  the image; none ships here; CI runs neither kind, the first real build
  is the authoritative test either way). Flips: forgejo-release t5
  (checkout-only allow-list, azure/setup-helm banned file-wide) + t19
  (runtime-cr contract → BAKED-toolchain contract, presence of
  Verify-toolchain legs pinned, cr/helm invocations still pinned) + new
  t20 (index-curl --retry); dev/gpu-forgejo-runner ACT_LABELS constants +
  gpu g2 equality; gpu g7 RE-ARMED not deleted (its values.yaml-untouched
  + 2-docker-line cap exist to fence cf-104's single-line swap and would
  otherwise fence out this very change — replaced by bounded-semantic
  teeth: at most 8 changed docker:// lines, only act-24.04-out /
  forgejo-runner-in shapes, ubuntu-22.04 byte-stable, dev-surface
  invariance kept); dev t14 record re-derived to the rewritten template
  comment (no-digest rule stays, git-lfs-binding stays, helm+cr-baked +
  manual-bump added); forgejo-ci-surface NO edit (inventory/guard legs
  survive; prose must dodge its banned-token list); guard-trio admits
  (agents-md c7, gate t14, rulesync-surface c8) widen for
  charts/forgejo-runner/* and containers/forgejo-runner/* with
  provenance, bound against MAIN's newer trio versions per the STATE
  conventions_shift.
 - 2026-11-21 human D42 (batched plan round — landing shape): the owner chose the
   SINGLE PR over the recommended UA-7 split: C05+C06+C07 land in one merge, riding
   the DESIGNED loud red shapes (helm command not found / pull error) whose re-run
   after the image publishes + sync + restart is the clean first fire; UA-8 (one-line
   pin amend if the merge crosses into December and 26.11.1 predates the real tag)
   stands as the owner contingency. UA-7's split option is retired by this ruling.
   D37/D38/D39/D40 (cr baked, helm v3.22.1, ghcr pull source, 22.04 label unmoved)
   were CONFIRMED unchanged in the same round; the plan was APPROVED to run
   C05 -> C06 -> C07.
 - 2026-11-21 human D43 (batched plan round — scope trim): the three added
   "Verify toolchain" steps in C07 are RETIRED (owner answer over the recommended
   keep): no helm-version/cr-version presence steps enter release.yaml; t5/t19
   flips survive without presence assertions per the planner's own note. The t20
   index-curl --retry hardening (resilience, not a presence assertion) and the
   D41 test-surface schedule otherwise stand as planned.
 - 2026-11-23 coord D44 (post-merge adaptation — owner: "merge in main, it had
   some work done touching on your stuff"): the fix round was already fully
   merged to main; the branch fast-forwarded cleanly to 8227e8f29 (origin/main
   ..HEAD empty, nothing of cf-55 lost or ahead). cf-6's builder-bootstrap wave
   then LEGITIMATELY REWORKED the exact surfaces C05-C07 shipped, and a fresh
   validation session (ses_df5e131d2ffeiSOiOHk72GHC6n) ruled the merged tree
   CONSISTENT: five contract suites green — forgejo-runner 8/8, forgejo-release
   20/20 (de-helm posture survives, release.yaml byte-unchanged from C07),
   gpu-forgejo-runner 19/19, dev-forgejo-runner 58/58, containers-build 41/41
   (the three admitted reds t6/t12/x4 are now FIXED by cf-6, as is dev t9 and
   agents-md c11). SUPERSESSIONS cf-6 landed on cf-55's decisions: 3303b711d
   bakes helm+cr from digest-pinned OCI STAGES not get.helm.sh (my C05 sidecar-
   at-build-time mechanism retired — get.helm.sh survives only as a permitted
   history comment); f236be07f + owner ruling R-B 2026-11-22 re-point the four
   labels to PER-INSTANCE-REGISTRY refs (git.spencerslab.com/curatedforest/
   forgejo-runner:26.11.1 base + git.scifi.farm dev-slice override), which
   SUPERSEDES D39's "ghcr pull source" ruling on the labels surface and LANDS
   UA-10 (instance-registry pull) via a path other than the deferred proof;
   3a9f760fe fixes the containers-build ghcr login (PUSH_TOKEN_GH -u OwnYourIO —
   the publish-failure cause my scout flagged); new .forgejo/workflows/
   builder-bootstrap.yaml is the FIFTH workflow (bare dispatch, prod-role narrow
   guard, mints forgejo-runner to the instance registry ONLY — no ghcr arm,
   rides public act-22.04). UA-8 (calendar-pin amend) stays LIVE but its shape
   WIDENS to TWO pin sites (chart base x4 + services/dev slice x4); today
   26.11.1 is month-correct, 26.12.1 only if a mint crosses into December.
   UA-7's duty stands (framing now names instance-registry pull refs, not ghcr).
   cf-55's own shipped prose tells no lie post-rework (AGENTS.md "no Renovate
   lane reads that image's label pin ... bumped by hand" stays true — renovate's
   only forgejo-runner lane holds the Dockerfile's alpine/helm v3 stage, reads
   no label lines). TWO PROSE FLAGS belong to cf-6 (report-only, not ours to
   edit): README "amends the one label-pin line" now has two pin sites since
   f236be07f; AGENTS.md "the newest published calendar tag" should be
   registry-qualified since the per-registry walks can diverge (OQ-1=B).
   FINDINGS F1/F2 (stale generated AGENTS.md on HEAD; radiance's overview.md
   rewrite dropped the scripts/agent-board-coord-gate.sh line + wake/delegated
   pair, reddening agents-md c13 and gate t16) are RADIENCE-owned, already
   booked as their rulesync-twin follow-up (c56cbd48c D17); cf-55 does NOT land
   that regeneration — the validation session's `rulesync generate --check`
   side-wrote the incomplete AGENTS.md in this worktree and coord discarded it
   (git restore) to keep one-branch-one-concern. Remaining admitted-elsewhere
   reds persist unchanged: ci-surface t4, gate t17, rulesync-surface c19. The
   release re-run is contract-green and can go green subject to the owner-side
   registry truth (image 26.11.1 present in each instance registry, else a
   builder-bootstrap dispatch mints it).

## Decisions — fix round 2: repo-add loop completeness (2026-11-23)

- 2026-11-23 plan D45 (owner re-run evidence + scout root cause + fix-shape
  ruling): the merged fix-round-1 re-run proved the bake (six charts packaged;
  the 127/ECONNRESET classes closed) and died at `cr package` with `Error: no
  repository definition for https://charts.jetstack.io,
  https://charts.christianhuth.de` (exitcode 1). EXPLORE.md Fix-round-2 scout
  §A0–§A7 grounded and reproduced the root cause end-to-end: cf-77 r2's
  hardened repo-add awk uses program-`exit` instead of `next` at
  release.yaml :125/:308/:368, so each per-chart loop TERMINATES after the
  first emitted row and only the FIRST URL-shaped dependency row of each chart
  is repo-added; victims = the four multi-URL charts {base, k8s-monitoring,
  postiz, traefik}; TEST D reproduced the owner's error verbatim from the
  shipped loop's state (only argo added); TEST F proved `exit`→`next`
  registers all rows → `helm dependency build` green → `cr package` exit 0.
  cr v1.10.1 unconditionally calls `downloader.Manager.Build()` per chart
  (source-verified packager.go CreatePackages, DependencyUpdate=true) and
  Build is LOCK-DRIVEN: every Chart.lock `repository:` URL must be defined in
  the repositories file — the per-URL, per-lock-entry completeness contract.
  RULING: option (a) minimal-mechanical ACCEPTED — `exit`→`next` at the three
  sites + t6-comment re-truth, keeping cf-77's per-row URL-shaped field guard
  (empty-REPOSITORY column still yields no pair) while restoring all-rows
  iteration (TEST B'/F shape). REJECTED (b) static URL list — kills
  `helm dependency list` from the blobs (reddens t6+t19, both must re-pin),
  zero resilience, the next new-repo chart reproduces this class silently —
  the same staleness that let the bug live 4 weeks unfired; REJECTED (c)
  vendoring committed tgz — blocked by `.gitignore:3` law first, and rots at
  the next renovate bump (stale tgz vs fresh lock re-enters the TEST-C repo-
  resolution path), so it only moves the failure unless (a) stays underneath.
- 2026-11-23 plan D45 (test-surface delta — RULING: include the completeness
  leg): t6's three token-pins survive the swap byte-unchanged (green as-is),
  but t6 has NO completeness teeth — nothing reddened while the loop
  under-added, which is why the regression shipped. The new t21 leg in
  tests/services/forgejo-release.sh replays EACH of the three landed awk
  carriers (t15 carrier-replay pattern) against a base-shaped 3-URL-row
  fixture demanding ALL THREE pairs emit (TEST-D-shaped teeth), plus
  single-row, oci-only, empty-REPOSITORY and zero-dependency fixtures (no
  regression on the six packaged charts, cf-77 guard survives, oci:// skip
  stays theirs-to-enforce); red-for-right-reason at base naming all three
  jobs, mutation-proven individually per site. t6's comment (:233-236, "first
  URL-shaped field" VERBATIM from the proven loop) currently blesses the bug —
  re-truthed with the fix; the three cf-77 workflow step comments stay TRUE
  untouched (they narrate per-ROW rationale — scout §A5). AC5 keeps the blast
  radius to exactly three one-word hunks in release.yaml.
- 2026-11-23 plan D45 (supersession/ownership fact): this is a defect IN
  cf-55's shipped surface — the hardened loop is C01-era, born unfired in
  cf-77 r2's c4d74dfc4 (an ancestor of the twin deletion a6e493b78 — the
  GitHub twin was already broken when deleted; the published-index staleness
  corroborates no green fire in between), and ported VERBATIM into all three
  Forgejo jobs at the rebuild (0dfefeb33/1ada03a50). NO OTHER TICKET OWNS IT;
  cf-55 fixes it in C08. cf-77's own empty-REPOSITORY fix is PRESERVED, not
  reverted — the field scan and guard stay verbatim.
- 2026-11-23 plan D45 (landing contingency UA-11 — owner first-fire watch):
  the fixed loop will `helm repo add` five hosts the runners have NEVER
  fetched (charts.jetstack.io, charts.christianhuth.de,
  prometheus-community.github.io, go.temporal.io, crowdsecurity.github.io —
  index fetch at add time). Reachability is PROVEN FROM THE WORKSPACE SEAT
  ONLY (TEST F); instance-runner egress is not verifiable from here (scout
  §A7). Recorded as UA-11: if the next fire dies at the Add-repositories step
  on a fetch error to a new host, that is runner egress, not the loop —
  owner-side observation, benign re-run posture as D42 established. Not code,
  not a chunk.
 - 2026-11-24 coord D46 (fire-3 discrimination — VERDICT H-A stale re-run; C08
   stands, never executed): the owner's "again byte-identical" re-fire was
   investigated by the same scout session (+188/0 '## Fire-3 discrimination').
   Three independent grounds: (1) GRAPH ELIMINATION — release.yaml triggers ONLY
   on push·main·charts/** (:29-33, no dispatch); the sole charts/** push in the
   window was 3303b711d (fire-2's own event); workflow-token pushes never
   re-trigger (:174-177 loop guard) — so NO FRESH FIRE of the post-C08
   definition was even possible; (2) RE-RUN FINGERPRINT — 87d3da0c3's parent is
   exactly f5c48dfbc, 76 s post-merge, same author as fire-2's bump, and the
   bump content (forgejo-runner 1.0.3->1.0.4) is the OLD event's idempotent
   re-derivation after the bump leg's fetch+reset onto new main — the stale
   re-run's footstep; Forgejo re-runs pin the trigger commit's YAML
   (FORGEJO_SHA fixed, run_attempt increments); (3) CODE-SEMANTICS ELIMINATION
   of the coord's H-B warn-swallow hypothesis — CORRECTION ON THE RECORD: the
   coord's 2026-11-23 message asserted the repo-add loops were 'warn-only,
   swallowing failures'; that is FALSE — all three loops are bare `helm repo
   add` under `set -euo pipefail` (:127/:310/:370), a failed add REDS the step
   before cr package is ever reached; and the shipped fixed loop run E2E from
   main's own text adds all 20 URLs in 8.8 s with the four victim charts
   dep-building green. The christianhuth/jetstack hosts are 200-direct,
   ordinary CDN (5.6 MB / 467 KB indexes) — the owner's 'difference' intuition
   found no host-side anomaly; the only difference was the OLD loop never
   ATTEMPTED them. LANDS AS PROTOCOL (O4), not code: validate fixes by RE-FIRE
   (push any charts/** commit — e.g. the next renovate chart PR), never by
   re-run of a pre-fix run; the run page's bound SHA + the Add-repositories
   step's cert-manager/gateway-api-crds presence are the one-line discriminants
   (owner confirmation still welcome but non-blocking — grounds 1-3 are
   conclusive). Optional belt considered and left to owner word: O4b identity-
   echo step (print the fire's SHA early so stale re-runs self-identify in any
   log) — NOT applied by default. Retry-hardening (O1) MOOT: adds are already
   loud. O2 lock-union pre-add / O3 name-collision: rejected on evidence (sets
   identical 20==20, zero drift, zero collisions).
