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
