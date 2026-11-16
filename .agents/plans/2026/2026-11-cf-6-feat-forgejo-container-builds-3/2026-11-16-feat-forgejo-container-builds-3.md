# PLAN: cf-6 follow-up (-3): land the forgejo container-build convention (yy.mm.N + contains() guards)
feature: 2026/2026-11-cf-6-feat-forgejo-container-builds-3

## Goal
Land the user-ruled forgejo container-build contract — `yy.mm.N` calendar +
`:latest`/`:main` rolling tags to BOTH `ghcr.io/ownyourio/<name>` and
`<instance-host>/curatedforest/<name>`, `contains()` ROLE membership guards in
all three `.forgejo/workflows/` (the `vars.ROLE == null ||` widening clause in
`containers-build.yaml`, narrow fail-safe in the other two), and the GitHub
`docker-build.yaml` narrowed to a `workflow_dispatch`-only manual fallback — by
amending `cf-6-feat-forgejo-container-builds-rebuilt` (`bc38a759f` = `main`
`69ccbe0bb` + one squash commit; 40-file diff 9916+/91-), which already carries
the end state on every ruled surface (EXPLORE.md, scout-verified same-session;
plan spot-checks confirmed). The batched-round rulings add the landing's scope:
the parity sweep moving the surviving `v<run>` prose and its test teeth — P7,
t5, and the `dev-mcp-fleet` t7 image-regex extension (post-approval ruling 5) —
in one change (ruling 1) and the card-134 pre-merge leg — the
`managerFilePatterns` extension that turns the one-time v84/v162 bump into a
post-merge Renovate PR (ruling 3) — with the validation bar run against the
final amended tree and the whole landing committed as ONE follow-up commit on
`bc38a759f` (ruling 2).

## Rulings applied (batched round, 2026-11-16 — visible at the approval gate)
1. **OQ-1 ABSORB** — the parity sweep is IN this landing: the 11-file spec moved
   from "Deferred work" into chunk C01 (one change: docs + P7/t5 teeth +
   regenerated mirrors), and its legs are added to the validation bar (C03).
2. **OQ-2 FOLLOW-UP COMMIT** — sweep + C02 extension + the -3 ticket record land
   as ONE follow-up commit on `bc38a759f`; the rebuild squash commit stays
   untouched; the branch ends at 2 commits; the user's single-commit preference
   is honored at the user-owned PR-merge. The coordinator defers the landing
   commit until C03 passes.
3. **OQ-3 INCLUDE** — the card-134 pre-merge leg (C02) is in scope: the
   `managerFilePatterns` extension in `renovate.json` exposes the top-level
   `services/**/values.yaml` pin lines to the plain-image manager. The pin
   VALUES stay (`v84` ×4, `v162` ×3) until the first post-merge forge build
   mints `26.11.1`; after that, the existing 10th packageRule + the extension
   make the one-time bump a Renovate PR the owner merges instead of a manual
   bump. The post-merge sequence is stated explicitly below.
4. **Chart-values comment parity** (the `:main` rolling chart values with
   old-convention comments — the EXPLORE.md §2 list): **DEFERRED to a
   follow-up card** (my ruling; either was acceptable). Reasoning: (a) the
   branch deliberately touches NO chart/service file — a core property of this
   40-file contract landing, and the user-ruled end state names no chart file;
   (b) the comments are stale but INERT — they sit on `:main` rolling pins that
   remain correct under the new convention, and no test teeth pin them, so
   deferral reds nothing; (c) comment-only churn across 7 chart files in a
   contract PR muddies the "does this PR touch chart behavior?" review, and the
   repo hard rule requires `helm lint`/`helm template` on chart-file edits even
   for comment-only changes. Rejected: absorb into C01 (would add 7 chart files
   + a helm validation surface to the one-change sweep commit). Residual: the
   stale `:v<run>`-era comments stay until the follow-up card (spec in
   "Deferred work").
5. **Post-approval ruling (the rework-surfaced t7 open question — the user's
   ruling SUPERSEDES the recorded best guess): EXTEND NOW in C01** — the
   `tests/services/dev-mcp-fleet.sh` t7 image-regex extension lands in this
   landing as part of C01 (the regex widens to also accept the calendar form
   `yy.mm.N` while still accepting `main` and `v<digits>`; the plan's best
   guess "extend in the owner's bump PR" and its rejected alternative stand
   recorded in Open questions). The t7 edit joins C01's one-change commit:
   docs + the P7/t5/t7 teeth changes + the regenerated mirrors land in ONE
   change.

## Out of scope
- The card-134 bump PR itself + the first post-merge forge build (owner legs —
  the pre-merge leg, C02, is IN scope; sequence below).
- The chart-values comment parity (deferred — ruling 4 above; spec in
  "Deferred work").
- The `tests/containers/{forgejo-host-runner,vllm-radiance-mxfp4}.sh` CI-deferred
  comment drift (inert comment-only; the deferred card, same scope).
- Any chart/service file change (the branch touches none; C01/C02 touch none
  either).
- "Fixing" the red-on-main forgejo test families (red-first doctrine — the plan
  never fixes main).
- `tests/cf96-deploy/*` (the historical runbook `v<run>` placeholder — a cf-96
  artifact, intentionally untouched).
- The c05 pipeline-models hygiene tests (gone from main's test tree; not in the
  bar — EXPLORE.md §7).
- Push, PR creation, merge to `main` (user-owned).

## Card-134 post-merge sequence (explicit — what lands NOW vs the owner legs)
- **Lands NOW (C02):** a 3rd `managerFilePatterns` entry —
  `/(^|/)services/[^/]+/[^/]+/values\.ya?ml$/` — on the plain-image
  `customManager` (the existing two patterns keep their `templates/` scope; no
  overlap — plan-verified this session: it matches all 13
  `services/<category>/<env>/values.yaml` files and none of the templates
  paths). It exposes 16 `image:` lines (verified via the manager's own
  `matchStrings`): exactly the 7 ownyourio pin lines (`v84` ×4, `v162` ×3) + 9
  other-org image lines.
- **Verified behavior (plan note, this session):** the 10th rule's calendar
  versioning `regex:^\d+\.\d+\.\d+$` (named-group form in the file) behaves as
  intended: `v84`/`v162`/`v177` and `:main`/`:latest` rolling refs fail the
  regex → clean silent skip (invalid-version — no downgrade PR, per the rule's
  description); `26.11.1`/`26.11.2` match → comparable → the bump PR. (The
  `0.0.12`-shaped semver pins — e.g. `traefik-mqtt-allowlist` in `charts/` —
  also match and ride the same calendar-line behavior; that is a pre-existing
  10th-rule consequence, not a C02 one.)
- **Owner leg A (post-merge):** the first post-merge forge build (or the
  pre-merge `workflow_dispatch` smoke, per the base cf-6 handoff) mints the
  first calendar tag `26.11.1` — the calendar rule's registry-max walk: no
  `yy.mm.*` tag exists on ghcr yet and the v-pins don't count.
- **Owner leg B (post leg A):** with C02 + the 10th rule in place, Renovate
  proposes the one-time bump PR (`v84` → the renovate-mcp calendar tag, `v162`
  → the wekan-mcp calendar tag); the owner merges it instead of a manual bump.
  No test edit is owed in leg B: the `dev-mcp-fleet.sh` t7 image regex already
  accepts the calendar form (extended in C01 per post-approval ruling 5), so
  the first calendar pin does not red t7.

## Commands (the validation bar — C03, run on the FINAL amended tree)
- test: `bash tests/services/forgejo-main-sync.sh` → expect 8/8
- test: `bash tests/services/forgejo-renovate.sh` → expect 8/8 (t9 live probe default-OFF/skipped is the expected shape)
- test: `bash tests/renovate/forgejo-move-config.sh` → expect 6/6 (m5 still pins 10 packageRules — C02 touches a `customManager`, not `packageRules`)
- test: `bash tests/services/forgejo-containers-build.sh` → expect 41/41 (the 41-leg contract suite incl. the g1 repo-wide guard sweep — C01/C02 touch no `.forgejo/workflows/`, so g1 stays intact)
- test: `bash tests/pipeline-push-pr/surface.sh` → green (P7 re-pinned by C01)
- test: `bash tests/wekan-mcp/tools.sh` → green (t5 re-pinned by C01)
- test: `tests/services/dev-mcp-fleet.sh` t7 leg — **shape leg (authoritative,
  offline):** extract t7's image regex from the file (the `re.fullmatch`
  pattern) and verify with python `re` that it matches
  `ghcr.io/ownyourio/wekan-mcp:v162`, `ghcr.io/ownyourio/wekan-mcp:main`, and
  `ghcr.io/ownyourio/wekan-mcp:26.11.1` (the calendar form), still accepts
  `main`/`v<digits>`, and does NOT match `1.2.3` (one-digit components) or
  `v1.2.3`. **Reasoning (the chosen shape, stated per the post-approval ruling):**
  `dev-mcp-fleet.sh` supports single-leg invocation (documented: `bash tests/
  services/dev-mcp-fleet.sh t7`), but the t7 leg renders the hivetools chart via
  `helm dependency update` against the OCI registry — the suite's own rule is
  "registry-unreachable is skip-with-warning only … (t6-t8/t11 OCI toolhive
  deps)" — so a live t7 leg is non-deterministic in agent sessions and a
  skipped leg is not a bar pass; the shape leg verifies the same extension
  contract deterministically offline. The targeted `bash tests/services/
  dev-mcp-fleet.sh t7` run is OPTIONAL corroboration: run it if helm + the OCI
  registry are reachable in the session; a skip-with-warning is the expected
  shape and never overrides the shape leg.
- lint: `rulesync generate` (after C01's `.rulesync/skills/` source edits) then `rulesync generate --check` (rulesync 37.0.0) → clean
- lint: `bash -n scripts/forgejo-container-detect.sh`
- lint: `bash -n` on every embedded `run:` block of `.forgejo/workflows/containers-build.yaml` (extract each step body; record the count)
- lint: `npx aislop` per the repo quality-gate convention — every file the landing touches clears the score floor with no error-severity findings (CI form: `aislop ci --changes` on the PR)
- typecheck: `python3` `yaml.safe_load` parse of each `.forgejo/workflows/{containers-build,main-sync,renovate}.yaml` AND of `.github/workflows/docker-build.yaml` — YAML 1.1 gotcha: `on:` parses as boolean key `True`; the parsed `on` key-set of `docker-build.yaml` must be exactly `['workflow_dispatch']`; `renovate.json` still JSON-parses with 10 packageRules
- smoke: n/a — no docker daemon in agent sessions; no new container code in this landing (C02's renovate config is consumed by no container build)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Parity sweep: the surviving `v<run>` prose + P7/t5/t7 teeth, one change | M | 1 | [] | — |
| C02 | Card-134 pre-merge leg: the `renovate.json` `managerFilePatterns` extension | S | 1 | [] | — |
| C03 | Validation bar on the final amended tree | S | 2 | [C01, C02] | the bar runs against the FINAL tree: `rulesync generate --check` is meaningful only after C01's source edits + `rulesync generate`, the surface/tools suites only after C01's teeth re-pin, and the move-config suite must re-read 10 rules after C02's extension |

## Wave order
1. C01, C02 (independent — different subsystems: C01 touches the skill/doc/teeth
   surface, C02 touches `renovate.json` only; C01 does not touch
   `renovate.json`, C02 touches no C01 file; run in id order)
2. C03

**Landing shape (ruling 2):** the coordinator defers the landing commit until
C03 passes, then commits C01 + C02 + the final -3 ticket record as ONE
follow-up commit on `bc38a759f`. The rebuild squash commit stays untouched.
The branch ends at 2 commits; the user's single-commit preference is honored at
the user-owned PR-merge.

## Open questions (the batched round is resolved; the rework-surfaced gap is resolved by post-approval ruling)
1. **`dev-mcp-fleet.sh` t7's image regex** (rework-surfaced) — **RESOLVED:
   EXTEND NOW in C01** (post-approval user ruling, 2026-11-16 — supersedes the
   recorded best guess; the entry stands unedited below). t7 pins
   `ghcr.io/ownyourio/wekan-mcp:(main|v[0-9]+)` — green today and green after
   the landing (the pin stays `v162`), but it would RED on the first calendar
   pin (the card-134 bump, owner leg B) if not extended. — **Recorded best
   guess (superseded): extend the regex in the owner's bump PR** (a one-liner
   that belongs in the PR that moves the pin; the suite's own comment — "the
   pin-bump commit must not need a test edit" — held for the M2 v-pin window
   but not for the calendar form). **Rejected alternative (superseded in the
   other direction): extend it now in C01** — the user's ruling chose exactly
   this alternative, so the t7 extension (regex widens to also accept the
   calendar form `yy.mm.N` while still accepting `main` and `v<digits>`) lands
   in C01's one-change commit. Impact: leg B no longer carries a test edit
   (card-134 sequence updated); the C03 bar carries the t7 shape leg.

## Risks / assumptions
- **Sweep-execution risk (replaces the resolved P7/t5 post-merge drift
  hazard):** the one-change invariant — `tests/pipeline-push-pr/surface.sh` P7
  and `tests/wekan-mcp/tools.sh` t5 sit RED between the doc edit and the teeth
  edit, so the docs, the THREE teeth changes (P7, t5, and the
  `dev-mcp-fleet` t7 regex extension — all in the one commit), and the
  regenerated mirrors land in ONE change (C01); no intermediate state is
  committed (the coordinator defers the landing commit until C03 passes). The
  t7 extension is a green-on-both-sides superset widening (`main`/`v<digits>`
  still match, the calendar form is added), so the red-window concern applies
  to P7/t5; the t7 edit joins the one-change commit per post-approval ruling 5.
- **Red-family doctrine (recorded as fact, EXPLORE.md §7):** the three
  pre-existing forgejo families are RED on main's state under the branch's
  red-first versions (t3/t3/m5 — exactly the legs the landing changes); main's
  own versions of the same files are green on main; all four suites are green
  on the branch tree (scout-verified this session: 8/8, 8/8, 6/6, 41/41).
  After the merge main's tree is the branch's tree, so all four are green on
  main. This plan never "fixes" main.
- **ghcr live state (scout probe, read-only):** no `yy.mm.N` calendar tag
  exists yet; `wekan-mcp` live max `v177` unpinned, `v162` pinned;
  `renovate-mcp` max `v84` (the pin). The first post-merge forge build mints
  `26.11.1` per the calendar rule's registry-max walk.
- **C02 churn expectation:** all 16 `image:` lines in the 13 top-level values
  files become visible to Renovate; the 9 non-ownyourio ones ride default
  docker rules (possible update PRs on those — the designed trade of exposing
  the files); the 7 ownyourio ones ride the 10th rule (silent skip until leg
  A).
- **Merge-time caveats for the user-owned PR discussion:** (a) the merge reverts
  main's newer AGENTS.md container section to the forgejo contract — deliberate
  per the ruling, not an accident: main's newer `v<run>` work (`90e5b035a` +
  `6c688f980` 2026-09-06, `ea2a7e3c1` 2026-10-18; stated intent: immutability
  of the release tag, rolling-tag safety, CI owns versioning) is deliberate
  work, and its machinery (the GitHub builder) is deliberately narrowed to a
  dispatch-only fallback, not deleted — the only main behavior that stops after
  the merge is the automatic GitHub `v<run>` minting; (b) the OQ-p flip
  sequencing (an early flip would silently stop the main fan-out while `main`'s
  `main-sync.yaml` still guards by equality); (c) the red-family doctrine;
  (d) the card-134 post-merge sequence — the extension lands NOW, the pin
  VALUES stay, leg A mints `26.11.1`, leg B is the Renovate bump PR (which
  carries NO test edit: the `dev-mcp-fleet.sh` t7 regex extension already
  landed in C01 per post-approval ruling 5, so the first calendar pin does not
  red t7).
- **Live k8s tag-state check inconclusive** (no `ownyourio/*` pods in the
  read-only dev/gpu fleets) — the repo pin lines are the grounding.
- **Model note:** every tier of this run runs on
  `gpu-ai/qwen3.8-27b-radiance-urgent`; a 502 peer-proxy error from an
  unscaled pod is a routing fallback, not a verdict.
- **Pin-count correction (plan-verified this session):** the legacy pins are 7
  lines (`v84` ×4, `v162` ×3), not the "6" in the scout's summary — the line
  inventory in EXPLORE.md §2 itself lists 7; verified by both grep and the
  manager's own `matchStrings` extraction.

## Deferred work: the stale-convention-comment residual card (complete spec for the follow-up ticket)
**Scope (comment-only, inert — no test teeth pin any of it):**
1. The `:main` rolling chart values with old-convention comments (the
   EXPLORE.md §2 list): `charts/coder/coder-templates/kubernetes-hardened/main.tf`
   L429; `charts/gpt-researcher/values.yaml` L35/L114 + `Chart.yaml` L9;
   `charts/llama-swap/values.yaml` L1172/L1224; `charts/okd/values.yaml` L143;
   `charts/snapcast/values.yaml` L16-19; `charts/vllm/values.yaml` L283-287
   (the `charts/traefik/values.yaml` `0.0.12` line is a pinned semver, not a
   v-pin — include only if its comment is stale-convention).
2. The CI-deferred comments in `tests/containers/forgejo-host-runner.sh`
   L335-337 and `tests/containers/vllm-radiance-mxfp4.sh` L361-365 that cite
   the old GitHub builder as the build authority (the forge
   `containers-build.yaml` is now the authority; the `no-daemon, CI-deferred`
   passing shape is unchanged).
**Excluded (grep false positive):** `tests/containers/wekan-mcp-login.sh`'s
`docker-build.log` is a local `docker build` log filename, not a builder
reference.
**Deliberately untouched:** `tests/cf96-deploy/*` (the historical runbook
`v<run>` placeholder — a cf-96 artifact).
**Validation bar for the card:** `helm lint` + `helm template` on every touched
chart (the repo hard rule — chart-file edits, even comment-only);
`tests/containers/forgejo-host-runner.sh` + `tests/containers/vllm-radiance-
mxfp4.sh` stay green (comment-only — no functional change); the four forgejo
suites stay green; aislop on every touched file.
