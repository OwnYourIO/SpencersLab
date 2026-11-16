# EXPLORE — cf-6 follow-up run (-3): forgejo container builds reconciliation

Scouted 2026-11-16 from the worktree `cf-6-feat-forgejo-container-builds` on branch
`cf-6-feat-forgejo-container-builds-rebuilt` @ `bc38a759f`. Read-only: git
reads/diffs, file reads, one read-only ghcr registry probe, one read-only k8s MCP
fleet probe, one temp worktree of `main` (created for test-state verification,
removed at end). Nothing committed, nothing edited outside this file.

## 0. State verification (re-verified from live git)

- `HEAD` = `bc38a759fd615700663bd70e9a5dbb82e855eb09`, branch
  `cf-6-feat-forgejo-container-builds-rebuilt`.
- `main` = `origin/main` = `69ccbe0bb5672abc6237ab58f13ea93aff43560c`;
  `git merge-base main HEAD` = `69ccbe0bb` — **the branch is exactly main + one
  commit** (confirmed, as claimed).
- That one commit: `bc38a759f` (2026-11-16 17:00:31 +0000) — *"cf-6: forgejo
  container builds — rebuilt on main, squashed. Squash of cf-6-feat-forgejo-container-builds
  (ab146a7d3, 28 commits over 3 runs: original, -1, -2) onto main (69ccbe0bb)"*.
- Old branch `cf-6-feat-forgejo-container-builds` = `ab146a7d3`; its tree hash
  `113c8eb8…` is **byte-identical to HEAD's tree** (`git diff HEAD
  cf-6-feat-forgejo-container-builds` = empty; both trees `113c8eb8c1608dcc612d30c00f9afe33a05b7f0d`,
  main's tree `4adadb75…`).
- Net diff `main..HEAD`: **40 files, 9916 insertions(+), 91 deletions(-)** (matches the claim).
- The 40 files = 13 non-plan files + 27 ticket-record files (the `-1`/`-2`/base cf-6
  ticket folders are ALL branch-side additions; on `main` the cf-6 ticket folder
  holds **only `DECISIONS.md`** — verified `git ls-tree main` on the folder).
- Run history (from the three ticket folders on the branch): **run 0** (2026-11-09/10,
  plan `2026-11-09-feat-forgejo-container-builds.md`): forge builder + detector +
  23-leg suite + renovate calendar rule + doc re-pin; **run -1** (2026-11-10/11,
  plan `2026-11-10-…-1.md`): ROLE list-membership split, dual registry, unset-ROLE
  widens, GitHub fallback triggers kept commented; **run -2** (2026-11-13,
  plan `2026-11-13-…-2.md`): detection contract pinned (fetch-depth 0, hand-rolled
  merge-base PR arm), empty outcome loud, guards migrated repo-wide (C04).
- This run's folder `2026-11-cf-6-feat-forgejo-container-builds-3/` exists with
  `STATE.json` (`plan_status: draft`) + `DECISIONS.md` carrying the user's batched
  end-state rulings (quote: *"the forgejo `containers-build.yaml` is the ACTIVE
  container builder … the GitHub `docker-build.yaml` is the `workflow_dispatch`-only
  manual fallback, and the ROLE membership guards in the forgejo workflows are
  `contains()` (not `==`). Landing = amend `cf-6-feat-forgejo-container-builds-rebuilt`;
  follow-up commit vs re-squash is a plan decision with a recommendation."*).

## 1. Main's newer container-builds work — origin and stated intent

The `:v<run_number>` (immutable) + `:<branch>` (rolling) convention on main was
introduced by exactly three commits, none of them pipeline-ticket work (author
"Spencer's Bot (Claud)" — standalone agent runs; **no plan folder on main
references the ADO switch** — `git grep 'ADO containers' main -- .agents/plans/`
is empty, and there is no legacy-layout plan at `.agents/plans/` root on main):

1. **`90e5b035a`** (2026-09-06) — *"Switch container builds to tag-based GH Actions
   workflow (from ADO)"*. THE origin: `:v<run_number>` + `:<branch>` in
   `AGENTS.md`, `skills/container-creation/SKILL.md`, and
   `.github/workflows/docker-build.yaml` (138-line rewrite); dropped the
   `containers/*/VERSION` files; repointed the traefik-allowlist pin to `:main`.
   **Stated intent (commit message, verbatim):** *"Replace the VERSION-file
   auto-bump flow with the ADO containers.yml model: CI on main/dev pushes
   :v<run_number> (immutable) + :<branch> (rolling); PR builds validate only and
   never push. Drop VERSION files, repoint the traefik allowlist image to :main,
   and update agents/skills to match."* The in-file rationale: `v<run_number>` is
   *"the monotonic immutable tag (ADO v$(Build.BuildId))"* — **immutability of the
   release tag** is the design point; the PR-never-push rule exists because *"a PR
   branch named e.g. 'dev' would otherwise overwrite the mutable ':dev' tag"* —
   **rolling-tag safety** is the second design point. Same-day companion
   `67a34a9d4` *"Never bump versions by hand — CI owns versioning."* pins the
   no-hand-bump half of the hard rule.
2. **`6c688f980`** (2026-09-06) — *"Pin image tags; adopt tag-based versioning in
   skills"*: the consumption convention — pin `:v<run_number>` **by default**;
   `:main` rolling only as a documented exception (snapcast "no pinned `:v<run>`
   tag exists yet", hivetools "new container, no pinned tag yet",
   brother-ptouch-automation "documented EXCEPTION … active development, tracks
   :latest with pullPolicy Always"); added the `helm-chart-creation` skill's
   "Image tag pinning" rule.
3. **`ea2a7e3c1`** (2026-10-18) — *"feat(rulesync): add agent workflow quality
   gates"*: the rulesync reorg that replaced the generic `overview.md` stub with
   the full AGENTS.md content — this is the commit that put the `run_number` text
   into `.rulesync/rules/overview.md` (the source of the generated `AGENTS.md`).

**Timeline note for the collision framing:** the convention predates the cf-6
ticket (first cf-6 work 2026-11-09) by two months, and the rebuilt branch's base
`69ccbe0bb` **contains all three commits**. The branch's overwrite of main's
`v<run>` docs is therefore a deliberate replacement of deliberate main work (the
user's "may be deliberate work" — it is; its intent is the immutability +
rolling-tag-safety + CI-owns-versioning rationale above), not a rebase accident.
Nothing in `90e5b035a`/`6c688f980` is a mechanism the branch needs to preserve:
its live machinery is the GitHub builder itself, which the branch **narrows, not
deletes** (owner ruling OQ-1, supersedes D1 — `cf-6` DECISIONS 2026-11-09
owner round: *"narrow, do not delete … kept but reduced to workflow_dispatch-only
… the GitHub-side manual rebuild escape hatch"*).

## 2. Full inventory — every place on `main` carrying the `:v<run_number>` convention

**Workflow (the builder):** `.github/workflows/docker-build.yaml`
- L4: `CI on main/dev → push v<run_number> (monotonic immutable tag) + <branch>
  (mutable rolling tag the cluster pulls)`; L120 `RUN_NUMBER: ${{
  github.run_number }}`; L124 comment `v<run_number> is the monotonic immutable
  tag (ADO v$(Build.BuildId))`. Tag computation: `run_tag=v${RUN_NUMBER}` +
  sanitized `branch_tag` (`'/'`→`-`); pushed on non-PR events, PRs validate
  only (`push: ${{ github.event_name != 'pull_request' }}`).

**Docs (all present on main):**
- `AGENTS.md` L425-429: *"Containers are tag-based: `docker-build.yaml` pushes
  `:v<run_number>` (immutable) + `:<branch>` (`:main`/`:dev`, rolling) on every
  merge; reference `:main` (+ `pullPolicy: Always`) or a `:v<run>` pin."*
- `.rulesync/rules/overview.md` L425-427 — the rulesync source mirror of the same.
- `.rulesync/skills/role-code/SKILL.md` L61 and generated `.opencode/skills/role-code/SKILL.md` L62;
  `.rulesync/skills/role-planner/SKILL.md` L62 and generated `.opencode/skills/role-planner/SKILL.md` L63
  — the "never hand-bump" bullets quote `pushes :v<run_number> + :<branch>`.
- `skills/container-creation/SKILL.md`: description L3, L42, L54
  (`:v<run_number> — monotonic, immutable (the GitHub run_number…)`), L200-202,
  L212, L235-236, L254.
- `skills/helm-chart-creation/SKILL.md` L291 (`:v<run_number>` pin rule).
- `skills/helm-chart-creation/references/mcp-servers.md` L401-410 (in-repo image
  section: `docker-build` tag-based, pin newest `:v<run_number>`).

**Renovate (main):** `renovate.json` carries **no** run-number rule and **no**
`ownyourio` calendar rule — only the `kubernetes-mcp-server` `allowedVersions`
floor and the `llama-swap` regex-versioning rule. (Verified by JSON parse +
`-S run_number` — zero hits on `renovate.json`.)

**Actual `:v<run>` image pins — 6 lines, 2 images (the legacy pins the end state
must eventually bump):**
- `services/dev/prod/values.yaml` L298, L332 — `ghcr.io/ownyourio/renovate-mcp:v84`;
  L454 — `ghcr.io/ownyourio/wekan-mcp:v162` (comment: *":v60 = the 25-tool
  custom-field build …"* on the line above).
- `services/gpu/prod/values.yaml` L732, L769 — `wekan-mcp:v162`; L912, L946 —
  `renovate-mcp:v84`.
- **Extraction caveat (verified):** the plain-image `customManager` in
  `renovate.json` has `managerFilePatterns` =
  `/(^|/)charts/[^/]+/templates/…/` and `/(^|/)services/[^/]+/[^/]+/templates/…/`
  **only** — the top-level `services/**/values.yaml` files are NOT extracted by
  any manager, so `v84`/`v162` are invisible to Renovate. The one-time bump needs
  a `managerFilePatterns` extension or a manual bump (branch final-review note,
  `cf-6` STATE.json `deferred_by_final_review`).

**`:main` rolling pins with old-convention comments (charts, identical on both
sides — the branch touches NO chart/service file):**
- `charts/coder/coder-templates/kubernetes-hardened/main.tf` L429 —
  `coder-workspace:main` (comment: pin the first `:v<run>` tag when it lands).
- `charts/gpt-researcher/values.yaml` L35/L114 — backend + frontend
  `:main`, "no immutable `:v<run>` tag exists yet … pin a `:v<run>` once one is
  published"; `charts/gpt-researcher/Chart.yaml` L9 same.
- `charts/llama-swap/values.yaml` L1172/L1224 — `strata:main` init + main
  ("No `:v<run>` exists yet" / "`:v<run>` builds exist for this image; adopting…").
- `charts/okd/values.yaml` L143 — `okd-enketo:main`; `charts/snapcast/values.yaml`
  L16-19 — `snapcast:main` ("No pinned `:v<run>` tag exists yet…");
  `charts/vllm/values.yaml` L283-287 — `vllm-radiance-mxfp4:main` ("first
  `:v<run>` once docker-build.yaml has run on main"); `charts/traefik/values.yaml`
  L80 — `traefik-mqtt-allowlist:0.0.12` (pinned semver, not a v-pin).

**Container READMEs / Dockerfile (main):** `containers/strata/README.md`
L165-170 (`:v<run_number>` (immutable, monotonic) + `:main` (rolling));
`containers/wekan-mcp/README.md` L62 (merge publishes
`ghcr.io/ownyourio/wekan-mcp:v<run_number>`); `containers/vllm-radiance-mxfp4/README.md`
L13 + `Dockerfile` L11 (first-build `:v<run>` law).

**Notes / runbooks / tests (main):** `.agents/notes/vllm-on-target-acceptance.md`
L62, L1118-1132 (PIN-ME → first `:v<run>`); `tests/cf96-deploy/readback-runbook.md`
+ `tests/cf96-deploy/surface.sh` L101-118 (pins the `v<run>` PLACEHOLDER verbatim
in the runbook — a historical cf-96 artifact); `tests/services/dev-mcp-fleet.sh`;
`tests/wekan-mcp/tools.sh` (t5 literal); `tests/pipeline-push-pr/surface.sh` (P7
docker-build routing section).

**Live ghcr registry (read-only probe, 2026-11-16, pull-scoped token +
`/v2/<img>/tags/list`):**
- `ownyourio/wekan-mcp`: `0.0.1 0.0.2 latest main v24 v25 v26 v27 v28 v29 v55 v60
  v68 v81 v87 v90 v101 v102 v148 v162 v177` — **all v\<run\>-style; no
  `yy.mm.N` calendar tag exists yet**. `v162` (the pin) is live; `v177` is a
  newer UNPINNED live tag (first forge build after merge will mint `26.11.1`,
  not `…178`, per the calendar rule's registry-max walk).
- `ownyourio/renovate-mcp`: `v24 main v31 v84` — `v84` (the pin) is the max; no
  calendar tag.
- Live k8s check **inconclusive**: `readonly-dev-kubernetes` (56 pods) and
  `readonly-gpu-kubernetes` (93 pods) — swept all namespaces in both — contain
  **no** `ownyourio/*` pods (no wekan-mcp/renovate-mcp workloads visible from
  this read-only fleet; the dev-mcp-fleet deployment lives outside it). The repo
  pin lines above are the authoritative "which charts pin them" evidence.

## 3. Guard-shape inventory on `main`

Workflows on main (verified `git ls-tree`): `.forgejo/workflows/` =
`main-sync.yaml`, `renovate.yaml` **only — `containers-build.yaml` is ABSENT on
main** (confirmed, as believed); `.github/workflows/` = `aislop`,
`amd-gpu-render-tests`, `docker-build`, `gpt-researcher-render-tests`,
`llama-swap-tools-tests`, `radiance-render-tests`, `release`, `rulesync`,
`vllm-render-tests`.

| file (main) | guard(s) | shape | unset-ROLE default |
|---|---|---|---|
| `.forgejo/workflows/main-sync.yaml` | L25 `if: vars.ROLE == 'prod'` (push-gh), L46 `if: vars.ROLE == 'prod'` (push-dev) | `==` | narrow — "An unset ROLE renders empty and fires [nothing]" (header) |
| `.forgejo/workflows/renovate.yaml` | L43 `if: vars.ROLE == 'dev'` | `==` | narrow — "an unset ROLE renders empty and fires nothing" (header) |
| `.github/workflows/docker-build.yaml` | L89 `needs.detect-changes.outputs.changed-containers != '[]'`, L109 `github.event_name != 'pull_request'` | no ROLE guard at all | n/a |

**Branch (end-state) guard shapes (verified on HEAD):** `main-sync.yaml`
L29/L50 `if: contains(vars.ROLE, 'prod')`; `renovate.yaml` L46 `if:
contains(vars.ROLE, 'dev')`; `containers-build.yaml` L94 detect `vars.ROLE == null
|| contains(vars.ROLE, 'dev') || contains(vars.ROLE, 'prod')`, L151 build/push
`… && (vars.ROLE == null || contains(vars.ROLE, 'prod')) …`, L358 PR arm `… &&
(vars.ROLE == null || contains(vars.ROLE, 'dev')) …` — the `null ||` clause is the
deliberate **widening** polarity (unset = both roles); the other two files stay
narrow fail-safe. `docker-build.yaml` on HEAD: `on:` = `workflow_dispatch` only
(push/`pull_request` blocks kept **commented** in the file as the re-enable
affordance) and **zero ROLE references** — it retains no ROLE guard in the end
state, so no `contains()` is due there.

## 4. Divergence set — `main` vs rebuilt branch (`bc38a759f`), per file

13 non-plan files (27 ticket-record files excluded — see below):

| file | M/A | what main's newer work does | what the branch does | same lines? | what the branch DISCARDS from main's newer work |
|---|---|---|---|---|---|
| `.forgejo/workflows/containers-build.yaml` | A | absent on main | the ACTIVE builder: push/PR/dispatch triggers, ROLE membership guards (incl. null-widening), whole-range detection (`fetch-depth: 0`, hand-rolled merge-base), `yy.mm.N` calendar + `:latest` + `:main` to **both** registries, `pr-<branch>-<sha>` forge-only on PRs | no (new) | nothing |
| `.forgejo/workflows/main-sync.yaml` | M | 2 jobs guarded `vars.ROLE == 'prod'` | same 2 jobs, `contains(vars.ROLE, 'prod')` + convention header (L8-10) | **yes** (the two `if:` lines + header comment) | only the `==` guard shape (strictly superseded: `contains()` accepts `dev,prod` list values and stays fail-safe on unset) — no job/trigger/mechanism lost |
| `.forgejo/workflows/renovate.yaml` | M | 1 job guarded `vars.ROLE == 'dev'` | same job, `contains(vars.ROLE, 'dev')` + header | **yes** (guard + header) | only the `==` guard shape |
| `.github/workflows/docker-build.yaml` | M | **automatic** push(main,dev) + PR triggers minting `v<run_number>` + `:<branch>` "on every merge" | surgical diff: ONLY the `on:` block (triggers commented out, kept as re-enable affordance) + header re-pinned to manual-only; detect/build/push jobs byte-identical | yes (the `on:` block region only) | **the automatic triggers and the automatic v\<run\>-minting cadence** — the one mechanism of main's newer work the end state replaces; the manual dispatch path and the whole job body are preserved |
| `.rulesync/rules/overview.md` | M | the `v<run>` container prose (L425-427) | forge-contract prose + the new **Forge Actions ROLE-membership hard rule** (incl. the sequencing bullet: infra `ROLE` stays `prod` until merged; flip to `dev,prod` is a post-merge owner leg) | **yes** (the container section of the hard rules + the "Where things live" line) | the `v<run>` prose (replaced by the `yy.mm.N` contract) |
| `AGENTS.md` | M | (generated mirror of the above) | (generated mirror of the above) | **yes** (L20, L222-238, L425-451 regions) | the `v<run>` prose |
| `renovate.json` | M | 9 packageRules (no ownyourio rule) | **additive**: 10th packageRule — `matchPackageNames: ghcr.io/ownyourio/*`, `matchDatasources: [docker]`, `versioning: regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$` with the description spelling the v-pin silent-skip rationale (v162 > 26.11.1 under default docker versioning; legacy v-pin fails the regex → clean invalid-version skip, never a downgrade PR) | no (insertion after the llama-swap rule) | nothing — pure addition |
| `scripts/forgejo-container-detect.sh` | A | absent | detector: `detect` (whole `before..sha` / merge-base range), `next-n` (per-registry `max(yy.mm.*)+1`), `sanitize` (branch-name sanitizer) | no (new) | nothing |
| `skills/container-creation/SKILL.md` | M | `v<run>` build-pipeline section (Buildx + GHA cache, PR-never-push, `:v<run_number>` pin-default) | 103+/35- rewrite: Forgejo builder, ROLE selection, range-pinned detection detail, dual registry, `yy.mm.N` + `:latest` + `:main` push contract, `pr-` tags, `:yy.mm.N` pin-default with the **legacy-pin note** ("Charts still on a legacy `:v<run_number>` pin stay there until the one-time bump PR moves them onto `:yy.mm.N`; meanwhile the calendar versioning rule in `renovate.json` makes Renovate skip those deps silently") | **yes** (the Build pipeline section, description, directory layout, pin section) | main's `v<run>` pipeline prose + Buildx/GHA-cache mechanics (superseded by plain `docker build` + dind VCT cache) — everything else in the file carried over |
| `tests/renovate/forgejo-move-config.sh` | M | m5 pins `len(rules) == 9` | re-pins m5 to `10` (with the cf-135 D14 "no rule lands at 9" comment kept true) | **yes** (m5 assertion + ok line) | the 9-count pin (superseded by the calendar rule's landing) |
| `tests/services/forgejo-main-sync.sh` | M | t3 pins `GUARD = "vars.ROLE == 'prod'"` | t3 pins `GUARD = "contains(vars.ROLE, 'prod')"` + migration comment; also rewrites the `vars.ROLE == 'dev'` negative check's context | **yes** (t3 block) | the `==` pin |
| `tests/services/forgejo-renovate.sh` | M | t3 pins `GUARD="vars.ROLE == 'dev'"`; packageRules 9 | t3 pins `contains(vars.ROLE, 'dev')` + polarity comment; packageRules 10 | **yes** (t3 block + rule count) | the `==` pin |
| `tests/services/forgejo-containers-build.sh` | A | absent | the 41-leg contract suite (see §7) | no (new) | nothing |

**The 27 ticket-record files** (`…/2026-11-cf-6-feat-forgejo-container-builds{,-1,-2}/`
plan/DECISIONS/EXPLORE/RESEARCH/STATE/chunks) are append-only records of the three
completed runs — **not** semantic-collision candidates; on main only the base
folder's `DECISIONS.md` exists, the branch adds the rest.

**Net collision picture:** the only same-line semantic collision set is
`{AGENTS.md, overview.md, container-creation SKILL.md, main-sync.yaml,
renovate.yaml, docker-build.yaml}` — and in every one of them the branch's text
is the user-ruled end state (forge contract + `contains()`), so the landing is a
**clean one-sided overwrite**: main's newer work is fully contained in the branch's
base, and nothing of it survives on main that the branch fails to address (its
machinery — the GitHub builder — is deliberately narrowed, its docs are
deliberately replaced). `renovate.json` and the two new test/script files are pure
additions. **Nothing on main is silently lost by the branch; the only main
behavior that stops after the merge is the automatic GitHub push/PR tag minting,
which the end state rules out by design.**

**Parity gaps that SURVIVE in the branch tree** (the branch's own final review
deferred them — `STATE.json deferred_by_final_review` + `cf-6` DECISIONS 2026-11-10
"Deferred (out-of-scope findings)"): `.rulesync/skills/role-code/SKILL.md:61` +
`.opencode/skills/role-code/SKILL.md:62`, `.rulesync/skills/role-planner/SKILL.md:62` +
`.opencode/skills/role-planner/SKILL.md:63`, `skills/helm-chart-creation/SKILL.md:291`,
`skills/helm-chart-creation/references/mcp-servers.md:401-410`,
`.agents/notes/vllm-on-target-acceptance.md` (L62, L1118-1132), the three
container READMEs + the vllm-radiance-mxfp4 Dockerfile comment,
`tests/pipeline-push-pr/surface.sh` P7 + `tests/wekan-mcp/tools.sh` t5 (test teeth
pinning the old GitHub-builder/`v<run>` prose — **green on both sides today**,
must be moved **with** the docs in one change), `tests/cf96-deploy/surface.sh`
(historical runbook `v<run>` placeholder — intentionally untouched), and the
`:main` rolling chart values with their old-convention comments (§2).

## 5. End-state grounding (the fixed target, per the 2026-11-16 user rulings)

**`yy.mm.N` (+ `:latest` + `:main` rolling, dual registry) must appear — all
present in the branch tree, verified:**
1. `.forgejo/workflows/containers-build.yaml` push block — prod arm publishes
   `yy.mm.N` + `:latest` + `:main` to **both** `ghcr.io/ownyourio/<name>` and
   `<instance-host>/curatedforest/<name>` (L184 "log in to the forge registry
   and derive its calendar N"; L241-257 calendar derivation; month fixed once per
   job); N = per-registry `max(yy.mm.*)+1` + existence-advance (GHCR has no tag
   immutability — re-runs must not clobber a published release); PR arm pushes
   `pr-<branch>-<sha>` to the instance registry only.
2. `AGENTS.md` hard rules (L439-451) + `.rulesync/rules/overview.md` mirror — the
   tag-contract prose incl. the sequencing bullet (infra `ROLE` stays `prod`
   until merged; flip to `dev,prod` is a post-merge owner leg — before the
   merge, `main`'s `main-sync.yaml` still guards by equality, so an early flip
   would silently stop the main fan-out).
3. `renovate.json` calendar packageRule (§4 row 7) — rule-before-bump posture;
   while pins sit on `v84`/`v162` it is a clean silent skip (never a downgrade PR).
4. `skills/container-creation/SKILL.md` — `:yy.mm.N` pin-default convention + the
   legacy-pin note.
5. **The legacy pins to bump (the one-time bump PR, owner-owned follow-up —
   Inbox card 134 / "AD-134"):** `services/{dev,gpu}/prod/values.yaml`
   `renovate-mcp:v84` + `wekan-mcp:v162` (6 lines). The branch does **not** touch
   them; the bump needs the first post-merge forge build to mint `26.11.1` and,
   because no current manager extracts top-level `services/**/values.yaml` (§2
   extraction caveat), a `managerFilePatterns` extension **or** a manual bump.
6. Dual registry: `curatedforest/<image>` mirror + the forge push identity
   (per-instance human-minted **non-admin `write:package`** PAT, Actions secret
   `FORGE_PUSH_TOKEN`) are documented in the workflow + AGENTS.md + skill.

**`contains()` must appear — all present in the branch tree, verified:**
- `if:` guards of **all three** `.forgejo/workflows/*.yaml`: `main-sync.yaml`
  (2× `contains(vars.ROLE, 'prod')`), `renovate.yaml`
  (`contains(vars.ROLE, 'dev')`), `containers-build.yaml` (3× `contains(vars.ROLE, …)`
  with the `vars.ROLE == null ||` widening clause — the one equality form g1
  explicitly blesses: "the null-comparison `vars.ROLE == null` stays allowed
  (byte-boundary: quote after `==`)").
- The GitHub `docker-build.yaml` **does not retain** ROLE guards in the end state
  (workflow_dispatch-only, zero ROLE references — verified), so no `contains()`
  is due there; the repo-wide teeth are the g1 sweep (§7).

## 6. Read-only live checks (performed; inconclusive parts noted)

- ghcr tag lists: see §2 — **no `yy.mm.N` calendar tag exists on ghcr yet**; the
  live `v<run>` families match the repo pins exactly (v84 max on renovate-mcp;
  v162 pinned on wekan-mcp with a newer unpinned v177).
- k8s pods: **inconclusive** — neither `readonly-dev-kubernetes` nor
  `readonly-gpu-kubernetes` (all namespaces swept; 56 + 93 pods) runs any
  `ownyourio/*` workload, so the actually-deployed tag state of the
  dev-mcp-fleet images could not be confirmed from this session; the repo pin
  lines are the grounding. No `admin*` server was used; no pod exec was needed.

## 7. Test-surface state (verified by running)

**The branch's 41-leg suite — `tests/services/forgejo-containers-build.sh`
(41/41 PASS on the branch tree, run this session):** 15 `t`-legs (workflow
contract: t5 PR-arm unpin, t8 per-side push-chain reaching image prefix + all
three tags, t11 registry naming, t14 empty-outcome warning shapes under five env
shapes), 5 `r`-legs (push mechanics: r1 fromJSON-ban in guards, r2
both-registries-before-push, r3 per-push registry attribution, r5 scheme-strip
law), 15 `d`-legs (detector units: d7 `next-n = max(yy.mm.*)+1` with numeric
compare, v/rolling/foreign-months ignored, 1 when none; d14/d15 the
owner-ruled merge-base shape), 5 `x`-legs (inertness/scope: **x1 the
`on:`-scoped trigger proof** — parsed `on:` key-set is authoritative, raw grep
scoped because the `docker/build-push-action` `push:` INPUT key is a blessed
false positive), **1 `g`-leg: the repo-wide guard-shape sweep — every
`.forgejo/workflows/*.yaml` must be URL-literal-free, URL-guard-free, ROLE-only-via-
`vars.ROLE` membership, and the regex `vars.ROLE == '<literal>'` equality form
must NOT occur (only the `vars.ROLE == null` comparison allowed)**.

**Guard-shape teeth across the three suites:** g1 (containers suite, repo-wide) +
the main-sync t3 and renovate t3 **exact-string pins** (`contains(vars.ROLE,
'prod')` / `contains(vars.ROLE, 'dev')`). **Tag-scheme teeth:** d7 (calendar N
derivation), t5/t8 (arms + full tag sets), r2/r3 (dual-registry push order and
attribution), x1 (GitHub fallback inertness), plus the move-config m5 rule-count
pin (10).

**State matrix (all runs performed this session; temp worktree of `main`
`69ccbe0bb` used for the middle column, removed afterwards):**

| suite (version) | vs main tree | vs branch tree |
|---|---|---|
| `forgejo-main-sync.sh` (main's own) | **PASS** 8/8 | n/a |
| `forgejo-renovate.sh` (main's own) | **PASS** 8/8 (t9 live probe default-OFF skipped) | n/a |
| `forgejo-move-config.sh` (main's own) | **PASS** 6/6 | n/a |
| `forgejo-main-sync.sh` (branch's) | **RED** — t3: `push-gh.if is "vars.ROLE == 'prod'", expected "contains(vars.ROLE, 'prod')"` | **PASS** 8/8 |
| `forgejo-renovate.sh` (branch's) | **RED** — t3: `jobs.renovate.if is "vars.ROLE == 'dev'", expected exactly "contains(vars.ROLE, 'dev')"` | **PASS** 8/8 |
| `forgejo-move-config.sh` (branch's) | **RED** — m5: `packageRules has 9 entries, expected 10` | **PASS** 6/6 |
| `forgejo-containers-build.sh` (branch's, new) | n/a (file absent on main) | **PASS** 41/41 |

**Recording the red state as fact (per instructions):** the three pre-existing
forgejo test families are red **on main's state under the branch's red-first
versions** — exactly the legs the landing changes (t3/t3/m5). Main's own versions
of the same files are green on main (nothing is red on main under main's own
suite). The "four foreign red families" of the previous session's report = these
three red-on-main families + the new 41-leg suite (which was red-first at
authoring: its header records "t d hands off 25 ok / 5 red, the full suite 34 ok
/ 7 red", now 41/41 green after the last chunk). The c05 pipeline-models hygiene
tests named in the base `cf-6` DECISIONS do **not** exist in `main`'s
`tests/` (grep: referenced only in the DECISIONS file itself) — they were
renamed/removed by later main work (cf-143 territory) and could not be
re-identified; not in scope for this landing's validation bar.

**Post-merge drift hazard (both sides green today):** `tests/pipeline-push-pr/surface.sh`
P7 and `tests/wekan-mcp/tools.sh` t5 pin the old GitHub-builder/`v<run>` prose —
after the landing they will red until the deferred docs-parity sweep moves docs
**and** these test teeth in one change. The validation bar the plan should name:
the four forgejo suites green on the amended branch tree (8/8, 8/8, 6/6, 41/41),
`rulesync generate --check` after the `.rulesync/rules/` edits, `bash -n` on the
detector + embedded run blocks, and the two `python3 yaml.safe_load` parses — the
exact bar the cf-6 final review used.

## 8. Could-not-verify notes

- Actually-deployed image tags of the dev-mcp-fleet workloads (§6 — outside the
  read-only MCP fleet's visible namespaces).
- The first real Forgejo `containers-build.yaml` run — by design never executed
  pre-merge ("no run of this workflow has executed yet, so every number here is
  offline" — branch SKILL.md; the owner's pre-merge `workflow_dispatch` smoke is
  a human leg that repoints live `:latest`/`:main` and mints a real `26.11.1`
  calendar tag, per the base `cf-6` final-review handoff).
- The c05 hygiene test identities (§7 — gone from `main`'s test tree).

## 9. Open questions for the plan

1. **Parity-sweep scope:** the user-ruled end state names `AGENTS.md`/`overview.md`,
   `renovate.json`, the chart-pin convention, and the three forgejo workflows — it
   does not name the surviving `v<run>` prose in `role-code`/`role-planner` skill
   sources, `helm-chart-creation` SKILL + `mcp-servers.md` reference, the three
   container READMEs, the vllm runbook note, and the P7/t5 test teeth (all
   deferred by the cf-6 final review as "its own card"). Does the landing change
   absorb that sweep, or does it stay a follow-up card? (The branch's own
   recommendation: follow-up card.)
2. **Follow-up commit vs re-squash** on the amended branch — a plan decision per
   the recorded ruling.
3. **The one-time v84/v162 bump (card 134)** stays owner-owned post-merge (needs
   the first post-merge forge build + a managerFilePatterns extension or manual
   bump) — confirm it is out of the landing's scope.
