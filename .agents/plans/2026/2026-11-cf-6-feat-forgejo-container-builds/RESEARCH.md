# RESEARCH — cf-6 Forgejo container builds

Written by `agent-research` 2026-11-09 (Pre-Research round, upstream of the plan;
companion to `EXPLORE.md`, which it updates where flagged). STORM method; five
perspectives; full trail (perspectives, interview notes, 30 numbered sources,
contradiction map, report) in
`/tmp/opencode/storm-work/storm-runs/porting-the-github-actions-container-buildpublish-pipeline/`
(ephemeral — the citations below are self-contained). **EMPIRICAL** = executed here
against the shipped Renovate 44.181.5 library (npx cache), not from memory.

## TL;DR

1. The Renovate hazard EXPLORE §6 flagged is REAL and scheme-fundamental: the docker
   datasource sorts `v162` above any `26.x` calendar tag (EMPIRICAL) — a packageRule
   with `versioning: regex:` scoped to ownyourio images must land **before or with**
   the one-time pin-bump PR, or the pin loop stalls / offers downgrades.
2. Forgejo's default concurrency silently cancels in-flight runs of the same workflow
   on every new push/PR-sync (v15.0 docs, verbatim) — `concurrency:
   cancel-in-progress: false` on the build workflow is mandatory, not polish.
3. EXPLORE's buildx flag resolves YES: the lab's act runner images ship docker CLI +
   buildx (image build-script source). But `type=gha` cache has driver/env/scope traps
   the lab's dockerd-dind shape doesn't meet today; the chart's persistent dind
   docker-data VCT already IS a cache — design cache, don't port it.
4. GHCR has **no tag immutability and no retention policy** — re-pushing a tag silently
   overwrites; collision semantics (re-runs) and PR-tag cleanup are pipeline-owned.
5. The GitHub/Forgejo coexistence window is a *correctness* issue: while GitHub's
   docker-build.yaml keeps minting `v<run>` tags into the same namespace, Renovate (tag
   union + ordering) keeps choosing the GitHub line — the cutover must be atomic
   (workflow off + rule in + pins bumped together).

## Key findings

### A. Renovate cutover mechanics (the load-bearing part)

- **Default versioning** of the docker datasource is `"docker"` — set in the datasource
  source (`defaultVersioning = docker.id`; [datasource docs](https://docs.renovatebot.com/modules/datasource/docker/),
  code EMPIRICAL). Docker versioning sorts SemVer-like tags, strips `v`, treats
  post-hyphen text as a compatibility suffix, and marks `latest`/`main` non-versions —
  rolling tags never compete for pins
  ([docker versioning docs](https://docs.renovatebot.com/modules/versioning/docker/),
  EMPIRICAL `isValid("latest")=false`).
- **Ordering hazard, measured** (EMPIRICAL, renovate 44.181.5):
  `isGreaterThan("26.11.1","v162") = false`; reverse = `true`. From a `v162` pin no
  calendar tag ever looks newer; from a `26.11.1` pin `v162` looks like an UPGRADE
  (downgrade-PR direction). A v-tolerant regex versioning still compares major
  numerically — the crossing cannot be regexed away; only the pin moves.
- **Regex versioning over a legacy pin is a silent no-op, not an error** (EMPIRICAL
  worker code, `workers/repository/process/lookup/index.js`):
  `if (!versioningApi.isVersion(currentVersion)) { skipReason: "invalid-version"; return; }`.
  So `versioning: "regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$"` on a `v162` pin
  skips the dep cleanly — intra-line ordering is correct (`26.11.10 > 26.11.9`,
  EMPIRICAL). Capture groups must be purely numeric
  ([regex versioning docs](https://docs.renovatebot.com/modules/versioning/regex/)).
- **allowedVersions cannot cross the boundary** — it filters candidate releases but the
  current-vs-new comparison still ranks `v162` above the calendar line (EMPIRICAL,
  `process/lookup/filter.js` resolution order: slash-regex predicate → versioning
  `matches` → npm-semver fallback → config error). In-repo precedents of all three
  shapes: llama-swap regex versioning, kubernetes-mcp-server semver floor, kubectl
  slash-regex `allowedVersions` (`renovate.json` L268–293).
- Maintainer guidance for date-shaped docker tags: loose/regex versioning +
  allowedVersions-style constraint; regex is the workable one for non-semver-ish shapes;
  `extractVersion` is disallowed inside regexManagers but fine as a packageRule (ours is
  the built-in helm-values manager, so a packageRule is the natural hook)
  ([discussion #13020](https://github.com/renovatebot/renovate/discussions/13020),
  [#24201](https://github.com/renovatebot/renovate/discussions/24201)).
- ⇒ **Migration ordering is a named plan decision with testable teeth**:
  (1) forge pipeline live pushing calendar tags → (2) packageRule landed (scoped
  `matchPackageNames` for `ghcr.io/ownyourio/*` or per-image, `matchDatasources:
  ["docker"]`) → (3) ONE dev PR bumping every chart pin `v<run>` → `26.mm.N`.
  Rule-late window = downgrade-PR risk; bump-late = stall; both are silent.

### B. The coexistence arithmetic (OQ-1, derived from A — high confidence)

Both forges build the same `CuratedForest/SpencersLab`; GitHub's workflow keeps pushing
`v<ghRun>` + `:main` to the same ghcr namespace on synced pushes. Renovate sees the tag
**union**, and the ordering above keeps every consumer pin on the GitHub line no matter
how healthy the forge pipeline is. "Deploy via Renovate pin bumps" therefore silently
deploys GitHub builds until the GitHub docker-build workflow is disabled **in the same
wave** as the pin migration. Coexistence is not inert; replace-in-one-atomic-change is
the only shape that converges (card intent "like the existing action" supports it).

### C. Forgejo runner semantics the workflow must encode

- **Concurrency default is cancel-everything** (docs, verbatim, v15.0 LTS = the 15.0.10
  instances): no `concurrency` key + `on.push`/`pull_request(synchronize)` ⇒ "any other
  invocations of the same workflow will be canceled automatically"; the docs' own
  release-pipeline remedy is `cancel-in-progress: false` with group omitted
  ([v15.0 reference](https://forgejo.org/docs/v15.0/user/actions/reference/),
  [latest reference](https://forgejo.org/docs/latest/user/actions/reference/),
  [codeberg #9434](https://codeberg.org/forgejo/forgejo/issues/9434),
  [#5914](https://codeberg.org/forgejo/forgejo/issues/5914)). This confirms EXPLORE §4 —
  with matrix + capacity-1 serialization, a second containers/** push during a build
  kills the first matrix.
- **Actions resolution**: relative `uses:` prepend `DEFAULT_ACTIONS_URL`
  (`https://data.forgejo.org` default); docs "strongly recommended to choose fully
  qualified URLs", SHA pinning advised (CVE-2025-30066 named in the docs);
  `docker://` container actions; local `./` actions
  ([v15.0 reference](https://forgejo.org/docs/v15.0/user/actions/reference/)).
  No published inventory of the mirror exists
  ([codeberg docs #1287](https://codeberg.org/forgejo/docs/issues/1287)); practitioner:
  mirror "covers the common ones… the long tail is not there" yet lists
  `docker/build-push-action` under works
  ([sumguy, Sep 2026](https://sumguy.com/forgejo-actions-runners-self-hosted/));
  app.ini can repoint the default to github.com or self-mirrors
  ([devroom.io, Mar 2026](https://www.devroom.io/2026-03-15/using-github-actions-in-self-hosted-forgejo/)).
  ⇒ **Plan policy: no dependency on the mirror** — either fully-qualified
  `uses: https://github.com/docker/...@<sha>` (needs runner egress to github.com,
  smoke-checked) or plain shell steps; the Fjord house shape is
  `checkout → docker build -t ... → docker login --password-stdin → docker push`
  ([fjord docker guide](https://fjord.sh/guides/docker-builds-forgejo-actions)).
  Forgejo's own doc examples use fully-qualified URLs (`code.forgejo.org/actions/...`).
- **Token/registry auth**: every job gets `FORGEJO_TOKEN` ≡ `GITHUB_TOKEN`
  (forge-scoped, per-task, `permissions:` ignored —
  [security docs](https://forgejo.org/docs/latest/admin/actions/),
  [codeberg #3571](https://codeberg.org/forgejo/forgejo/issues/3571),
  [sumguy](https://sumguy.com/forgejo-actions-runners-self-hosted/)). It cannot write
  ghcr ⇒ a GitHub PAT (`write:packages`, `ownyourio`) as a human-entered Actions secret
  on the infra instance stands (EXPLORE §5 confirmed; cf-119 UA-pattern human leg).
- **Cache**: buildx `type=gha` targets "other cache services supporting the GitHub
  Actions cache protocol" in principle, but: env fallback requires
  `ACTIONS_CACHE_URL`/`ACTIONS_RUNTIME_TOKEN` exposed to inline `docker buildx` steps;
  it "works with the default docker driver only when the containerd image store is
  enabled" (lab dind = classic store); default `scope: buildkit` makes each image in a
  matrix **overwrite the previous one's cache** unless scoped per image; v1/v2 endpoint
  selection keyed on the same env
  ([Docker gha-backend doc](https://docs.docker.com/build/cache/backends/gha/)).
  The Gitea-lineage runner ships its own cache server (cache service v2) and
  `actions/cache` works without setup
  ([Gitea runner cache docs](https://docs.gitea.com/runner/cache/)); whether forgejo-runner
  13.2 injects the env vars in a buildx-usable form is **unverified from the workspace**
  (no source either way — the first-fire smoke decides). Meanwhile the lab's dind
  docker-data VCT (10 Gi, chart) persists the dockerd layer store across jobs and pod
  restarts — plain `docker build` is already warm without any buildx cache backend
  (derived from EXPLORE §3 chart facts). Practitioner principle: "Caching is a
  performance feature, not a correctness feature — workflows should pass cold"
  ([fjord cache guide](https://fjord.sh/guides/cache-dependencies-forgejo-actions));
  watch runner disk pressure
  ([fjord docker guide](https://fjord.sh/guides/docker-builds-forgejo-actions)).
- **Runner images ship the tools** — EXPLORE §7 UNVERIFIED → resolved: the act image
  build script installs `moby-engine moby-cli moby-buildx moby-compose` and asserts
  `docker buildx version` at build time
  ([act.sh source](https://raw.githubusercontent.com/catthehacker/docker_images/master/linux/ubuntu/scripts/act.sh),
  [README](https://github.com/catthehacker/docker_images)). Gotcha: job images "once
  downloaded are never updated" on the runner
  ([Forgejo runner config docs](https://forgejo.org/docs/latest/admin/actions/configuration/)).
- **Workflow-shape parity confirmed** in v15.0 docs: `on.push.paths` (+branches
  AND-semantics), matrix `fromJSON(needs…outputs…)` with `$GITHUB_OUTPUT` generator
  (the exact detect-job pattern; per-cell unique `jobs.<id>.name` caveat),
  `workflow_dispatch` typed inputs (`choice|boolean|number|string`) + API dispatch
  endpoint ⇒ OQ-7 escape hatch ports fully
  ([v15.0 reference](https://forgejo.org/docs/v15.0/user/actions/reference/)).
  Broken-elsewhere surfaces (artifacts v4, job-level `permissions:`/`continue-on-error:`,
  GitHub-API actions) are unused by this port
  ([sumguy](https://sumguy.com/forgejo-actions-runners-self-hosted/)).

### D. Registry + tag-scheme semantics

- **GHCR tags are fully mutable — no immutability feature exists** (Dec 2025 community
  request still uncommitted to roadmap; May 2026 investigation: "the toggle doesn't exist
  anywhere in GHCR's UI or API")
  ([issue write-up](https://github.com/glitchwerks/github-actions/issues/173));
  GitHub's "immutable releases" is git-level, not GHCR
  ([GHCR docs](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)).
  No native GHCR retention policy; third-party pruning via the packages API is the
  de-facto ([snok/container-retention-policy](https://github.com/snok/container-retention-policy));
  GHCR storage currently free
  ([billing docs](https://docs.github.com/en/billing/concepts/product-billing/github-packages)).
  ⇒ re-pushing an existing tag SILENTLY OVERWRITES: registry-derived-N must carry a
  skip-if-exists gate (the anonymous token + `tags/list` recipe already in
  `skills/container-creation`), or explicitly document overwrite-as-rebuild; PR-tag
  retention = naming discipline now, API-prune later (OQ-5).
- **The card's shape is canonical CalVer**: `YY.MM.MICRO` (release-counter micro;
  1-based date segments; short year relative to 2000; four-segment versions discouraged
  — the timestamp fallback is off-spec; padding is a style choice, invisible to
  Renovate's numeric capture groups) ([calver.org](https://calver.org/)). So
  `26.11.1` = first Nov-2026 release — option 2's reading is the on-spec one;
  option 1 (`yy.mm.<repoRunNumber>`) is legal but not "N of the month".
- Increment-source decision table (constraints now settled: mutability D-above +
  ordering A + capacity-1 serialization):
  - `forgejo.run_number` third component: never collides; sparse; diverges from the
    card's `1++` intent; re-runs mint fresh tags (orphan manifests).
  - registry-derived max(`yy.mm.*`)+1: literal card intent; re-run collides →
    skip-if-exists gate + `cancel-in-progress:false` required; same-image concurrency
    only theoretical at capacity 1.
  - `git rev-list --count --since=<YYYY-MM-01>`: deterministic per commit; re-run of a
    commit = same N = rebuild-overwrite of that release (coherent semantics, no API
    work, no state); monthly reset natural. (EXPLORE's cross-image tie is harmless —
    tags are per-image.)
  ⇒ research leans registry-derived-with-gate (card-literal) or git-count (simplest
  correct); run_number only if the plan prefers zero-compute uniqueness over intent.

## Contradictions and how to weigh them

1. **"docker/build-push-action works" (field report) vs the gha-backend contract**
   (driver/env/scope gates). Both stand: the action *runs*; the cache may silently not
   attach. Weigh: plan plain-shell or fully-qualified actions, cache gated by the smoke,
   `ignore-error: true` on any cache export if used.
2. **"mirror covers common actions" vs "no inventory exists"** — unverifiable from the
   workspace; weigh via the docs' own fully-qualified recommendation; plan assumes the
   mirror may NOT have what it needs.
3. **`:latest` (card) vs `:main` (repo contract)** — owner ruling, not a research clash;
   tooling-safe to run both (rolling tags never compete as pins, EMPIRICAL). Suggested:
   keep pushing `:main`, add `:latest` as the card asks, decide `:main` retirement
   later as a docs/consumer change (OQ-4).
4. **"immutable tag" language inherited from GitHub habit vs GHCR's total mutability** —
   the registry enforces nothing; whichever N scheme is chosen must state its re-run
   semantics in the plan text (silent overwrite is the failure mode to design against).

## Implications for the plan

- **Chunk-worthy named decisions**: (1) increment scheme + re-run gate; (2) packageRule
  + pin-migration PR with ordering teeth (and the GitHub-workflow disablement in the
  same wave — B); (3) `concurrency: {cancel-in-progress: false}` on the workflow;
  (4) action-sourcing policy (no-mirror-dependency); (5) cache posture (VCT-first vs
  smoke-gated gha); (6) `:latest` alongside `:main`; (7) PR tag name `pr-<branch>-<sha>`
  (+ explicit "PR tags are disposable; no TTL exists" stance) and PR-push decision
  (OQ-5 — card says push; the naming makes it safe, retention is manual).
- **Workflow body first-fire smoke step** (house diag style, per main-sync precedent):
  `env | grep -E 'ACTIONS_(CACHE|RUNTIME|RESULTS)'`, `docker buildx version`,
  `echo ${{ forgejo.server_url }}`, `docker info` (dind reachability), cold build of
  ONE cheap container (`traefik-mqtt-allowlist`), then — second fire — one cache-hit
  assertion. Matrix trusted only after.
- **Validation shape unchanged from EXPLORE §9**: offline contract suite (red-first,
  mutation teeth — the changed-dirs/tag computation helpers are unit-testable in a
  scratch git repo), `python3 -c yaml.safe_load` parse, `bash -n`; live-fire infra-only;
  the Renovate packageRule itself is checkable offline with
  `dev-renovate validate_config`/`test_package_rules` (and the ordering facts above are
  reproducible with the npx-cache library test used here).
- **Human legs (enumerate, don't implement)**: mint ghcr PAT (`write:packages`) into
  Bitwarden; Actions secret on the infra instance repo; merge the pin-migration PR;
  (later) optional PR-tag prune action. Dev-instance repair stays out of scope.
- **EXPLORE deltas**: §7 "buildx available in act image" → RESOLVED YES (source);
  §4 concurrency trap → CONFIRMED verbatim with docs' prescribed remedy; §7 gha-cache →
  REFINED (three concrete gates: env, driver, scope); §6 hazard → CONFIRMED empirically
  with library-level proof + exact Renovate skip semantics; §6/§7 "images never update
  on the runner" gotcha added.

## Open questions

- (research-limits) Does forgejo-runner 13.2 inject `ACTIONS_*` env in a buildx-usable
  form, and does data.forgejo.org carry docker/*? — both are first-fire smoke
  observations, not book knowledge; the plan should branch on them, not assume.
- OQ-1..OQ-7 from EXPLORE §10 stand as owner questions; research narrows them: OQ-1
  now has a correctness argument for "replace atomically"; OQ-3's Renovate half is
  fully answered (regex versioning + rule-before-bump), its scheme half reduced to a
  one-line ruling between registry-derived+gate and git-count; OQ-4 can be "both tags"
  at zero tooling cost.
- `strategy.fail-fast: false` — documented GitHub behavior; not explicitly listed in
  the v15.0 reference; low-risk smoke item alongside the rest.
