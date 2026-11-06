# PLAN: Immich → Hugo photo pipeline (CuratedForest.com via Forgejo runner)

feature: 2026/2026-10-cf-11-feat-immich-hugo-pipeline
rework: 2026-10-31 (owner answer round — DECISIONS.md "OWNER ANSWER ROUND"; deltas 6–9)
final: 2026-10-31 (owner N1–N3 answers folded — DECISIONS R11–R14; last planning pass)

## Goal

Build the owner-locked phase-1 pipeline: a **host-backend Forgejo runner on a
PVC** that syncs Immich preview derivatives **into the site's EXISTING page
bundles** — every allowlist entry names its target page (`page:` REQUIRED, no
fallback), writes are additive-only, and where a page's gallery call would not
include the synced files, sync extends the page with its own machine-marked
gallery call (idempotent, owner N2); one PR, update-in-place, farm-gated
review. Deploys CuratedForest.com to Netlify via CLI (merge→main =
curatedforest.com; PR→main = curatedforest.farm, last PR wins). Sync fires on
a **daily** schedule + workflow_dispatch. Card #11 builds the host-backend runner **mode** in the shared chart; the
runner **instances** are separate asks (the dev validation release left this
branch in the 2026-11-06 owner review — its instance is a different ticket;
the gpu prod runner is card #88), which also owns the gpu→Immich network path —
so card #11's sync E2E is **fixture-based** (fake Immich server in tests).

Direction is locked (DECISIONS.md "DIRECTION LOCKED BY OWNER") and amended by
the owner answer round (DECISIONS.md "OWNER ANSWER ROUND"); the three RESEARCH
docs remain the evidence base.

## Two-repo map

| Surface | Repo | Status |
|---|---|---|
| Sync/publish tooling, toolchain image, runner chart host mode (dev validation release removed 2026-11-06 owner review; seeder + watchdog charts dropped same review) | SpencersLab (this repo, branch worktree) | fully buildable/validatable now |
| Workflows (deploy/sync) + the `sync-albums.yaml` page-mapping allowlist | CuratedForest.com | staged in this ticket folder (`site-staging/`); local checkout dirty + pre-Forgejo, stays UNTOUCHED; applied to the Forgejo clone in C07 once the owner migrates the repo |

Cluster map (owner answer round, 2026-11-06 review-amended): **dev** = no
card-#11 landing (the dev validation release was removed — the dev runner
instance is a separate ask); **gpu** = no card-#11 landing (seeder/watchdog
charts dropped in the 2026-11-06 review; the prod runner is card #88);
**infra** = target Forgejo (`git.spencerslab.com` — the site repo + its
secrets live there, in no chart values); **home** = Immich (data source only
— no card-#11 landing; gpu→home API path is card #88's open item).
Blocked-on-owner preconditions gate C07 + live verification only; all
SpencersLab chunks are independently validatable.

## Out of scope

- Standing up Forgejo itself; the existing dev/infra instances and the DinD
  dev runner are untouched. **gpu productionization of the host runner = card
  #88** ("Deploy the host-backend Forgejo runner to gpu as the ONLY
  git.spencerslab.com (prod) runner"; created → Low Priority — board scan at
  rework found the list empty; reference stands per the owner answer round).
- The **gpu→Immich network path** (hub SSO gate; candidates LAN allowlist /
  NodePort / proxy-local exception) = explicit card-#88 open item. Card #11
  E2E is fixture-based accordingly.
- Album-change EVENT triggers (socket.io shim) — phase 2. Old-LFS removal —
  separate card. IPP/folio B′ companion — separate.
- Any auto-merge; zero template changes to `layouts/_shortcodes/gallery.html`;
  no destructive edits to ANY existing repo file — the ONLY permitted machine
  edits of existing files are the append-only front-matter marker (N1) and
  sync's own machine-marked gallery blocks (N2); the two manual derivatives in
  `current-grows` stay untouched.
- Netlify cutover (disconnect git builds on both sites) + LFS-object
  carry-over during migration — owner jobs, not chunks (answer 5).
- Touching `/home/coder/CuratedForest.com` working tree.

## Commands

```
export PATH="$HOME/.local/bin:$PATH"   # helm + hugo 0.151.0+extended live here

# C01 tooling tests — includes the fixture-based E2E (fake Immich server + scratch site)
python3 -m pytest containers/forgejo-host-runner/tests/ -v

# C02 image — no docker daemon in agent sessions:
docker build containers/forgejo-host-runner => no-daemon, CI-deferred   # designed passing shape
bash tests/containers/forgejo-host-runner.sh && hadolint containers/forgejo-host-runner/Dockerfile

# C03 chart host mode (deps are gitignored; Chart.lock committed; the dev
# validation release left this branch in the 2026-11-06 review — services/dev
# + custom-values/dev are main-state)
helm dependency build charts/forgejo-runner
helm lint charts/forgejo-runner
helm template charts/forgejo-runner --set bitwardenIds.runner-token=00000000-0000-0000-0000-000000000000 --debug
bash tests/services/dev-forgejo-runner.sh        # main-state suite (byte-identical to main; the C03 two-release extension reverted per the 2026-11-06 review)
helm dependency build services/dev/prod
helm template dev services/dev/prod <sentinel --set list pinned by the test scripts> --debug

# C04/C05 — DROPPED 2026-11-06 owner review (seeder + watchdog charts deleted;
# the five repo secrets get a one-shot manual seed — user action 8). No
# C04/C05 command legs survive; the gpu umbrella render is covered by the
# sentinel sweep below.

# Sentinel sweep (post-2026-11-06 review: the two forgejo app-block charts are
# dropped, so the sweep is chart + service + custom-values only):
grep -rn 'OVERRIDE_' charts/forgejo-runner \
  services/dev/prod/values.yaml services/gpu/prod/values.yaml \
  custom-values/dev/prod-values.yaml custom-values/gpu/prod-values.yaml
# OVERRIDE_VIA_CUSTOM_VALUES <-> custom-values/dev keys; the
# OVERRIDE_VIA_CLUSTER_ANNOTATION strings in chart/service values are inert
# shadowed defaults (fleet practice, NOT delivery instructions). No
# OVERRIDE_NEEDED app-block slots remain on this branch.

# C06 staged site artifacts (hugo render gate on a SCRATCH COPY in /tmp/opencode —
# never the real repo; module cache warm; hugo = site's exact pin)
python3 -m pytest .agents/plans/2026/2026-10-cf-11-feat-immich-hugo-pipeline/site-staging/tests/ -v

# Quality gates
npx aislop ci --changes
```

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Sync + publish tooling: album→existing-bundle mapping (page: required), additive-only writer + machine-marked gallery-call extension, fixture-based E2E | M | 1 | [] | core logic; defines the tool contract C06 calls |
| C02 | `forgejo-host-runner` toolchain image (runner+hugo+netlify-cli+git-lfs) | M | 2 | [C01] | Dockerfile COPYs C01's modules |
| C03 | `charts/forgejo-runner` host-backend MODE (DEV validation release removed 2026-11-06 owner review — runner instances are separate asks; gpu prod = card #88) | L | 1 | [] | chart-internal; image NAME plan-locked; re-landed onto main's current chart 2026-11-06 (cf-97/cf-104 drift) |
| C04 | ~~`charts/forgejo-secret-seed`~~ — **DROPPED 2026-11-06 owner review** (no standing seeder; one-shot manual seed = user action 8) | M | 1 | [] | (was: independent chart; secrets rule compliance) |
| C05 | ~~`charts/forgejo-run-watchdog`~~ — **DROPPED 2026-11-06 owner review** (commits + immich webhooks are the coverage) | M | 3 | [C04] | (was: reuses C04's PAT/URL values pattern) |
| C06 | Site-repo artifacts staged: deploy+sync workflows (daily cron), sync-albums.yaml page-mapping schema (no archetype/section — N3) | M | 2 | [C01] | workflows call C01's tool contract; workflows combined into one pipeline.yml + IMMICH_URL moved to a repo variable per owner site-review round 3 (2026-11-06) |
| C07 | Apply staged artifacts to CuratedForest.com on Forgejo (branch+PR) | S | 3 | [C06] | blocked on owner precondition (repo migrated to Forgejo — RESOLVED 2026-11-05, live-verified incl. LFS) |
| C08 | `forgejo-host-runner` image: pinned Go toolchain (hugo module download on the runner) | S | 4 | [C02] | C07 dev r1 live finding: site imports hugo modules, image has no go → first runner build red (added 2026-11-05) |

## Wave order

1. C01, C03 (chart host mode only — the dev release left in the 2026-11-06 review), C04 (DROPPED in that review) — independent (different file sets).
2. C02 (needs C01), C06 (needs C01's contract).
3. C05 (DROPPED 2026-11-06 owner review), C07 (repo now lives in Forgejo — RESOLVED 2026-11-05; remote legs await the site PR).
4. C08 (needs C02; added 2026-11-05 per C07 dev r1 live finding — must land before the first live runner build and before the C07 PR opens).
5. (2026-11-06 owner-review rework) C04 + C05 dropped; C03 dev release removed + host mode re-landed onto main's current chart; C02 bin/ → build-time-generated wrappers. See the amendment log 2026-11-06 bullet.

## Verified facts (planning + rework sessions)

- `charts/forgejo` + `charts/forgejo-runner` EXIST (v1.0.2, DinD shape;
  `forgejo-runner-dev` live on dev via `services/dev/prod` with in-cluster
  `runner.url: http://dev-forgejo-http:3000`; `forgejo-runner-infra` un-wired
  2026-10-25, relocation pending — this plan COEXISTS with it, answer-round
  note). Forgejo instances: dev (`git.scifi.farm`) and infra
  (`git.spencerslab.com` canonical — answer 1: CuratedForest.com lives there).
- Immich hub route is SSO-gated (`ssoAllowedPaths` = `/.well-known/immich`,
  `/api/server/ping` only) → API-key clients CANNOT reach Immich cross-cluster
  through the hub → with the prod runner on gpu (answer 8) and validation on
  dev, card #11's E2E is fixture-based; the network path is card #88's item.
- gpu bitwardenIds CLUSTER-ANNOTATION mechanism is DEAD since `aa817da6b`
  (2025-09-28) — DECISIONS "COORD FACT-RULE 2026-11-01" (reviewer live-proof:
  the deployed gpu Applications resolve uuids from per-app `bitwardenIds:`
  blocks in `custom-values/gpu/prod-values.yaml`, projected into each
  Application's valuesObject by base's charts appset; that file is fetched
  via the `services.gpu.customValuesUrls` cluster annotation — the gpu
  annotation that actually feeds uuids). C04 shipped exactly this shape
  (APPROVED r2). The `OVERRIDE_VIA_CLUSTER_ANNOTATION` sentinel STRING stays
  as the inert chart-level default the app block shadows (live fleet
  practice, searxng/neo4j) → C04/C05 owner fills are OVERRIDE_NEEDED slot
  replacements in custom-values/gpu, NOT annotation edits.
- CuratedForest.com gallery contract: page resources sorted by `Name`; calls
  vary — no-glob `.ByType "image"` (current-grows, `sort="desc"`),
  case-insensitive jpg glob (past-designs), semantic-prefix globs
  (grow-environments `v6-*`…`2017-pfc-*`). Owner N2 settled the fit problem:
  sync AUTO-EXTENDS pages with a machine-marked gallery call when no existing
  call includes the synced files (idempotent, additive-only otherwise —
  DECISIONS R12; C01 pins the exact edit shape).
- `.gitattributes` LFS-tracks jpg/jpeg/png/gif/webp/svg (derivatives land as
  LFS automatically; post-migration LFS lives in Forgejo storage);
  `netlify.toml` pins HUGO_VERSION 0.151.0; repo dirty (2 ahead + WIP).
- Agent env: `hugo v0.151.0+extended` at `~/.local/bin` (exact site pin) →
  C06 render gate; pytest 9.1.1; hadolint; helm.
- Board scan at rework (dev-boards MCP): card #88 NOT yet visible (Low
  Priority list empty) — RESOLVED per owner: #87/#88 were auto-routed by the
  board classifier into its new Context swimlane lists (board drift, human
  triage); the delegation reference stands, no action needed (DECISIONS R14).

## Risks / assumptions

- **Schedule fragility** at daily cadence (one shot/day): per the 2026-11-06
  owner review there is NO standing compensating job — coverage is the sync's
  commit/PR history + Immich webhook triggers + manual `workflow_dispatch`
  (a catch-up, if ever wanted, lands as a site-repo `.forgejo/workflow`,
  never a k8s CronJob — answer 7 note + review ruling 6).
- **k3s MTU / forgejo-runner#1779** may bite action clones in host mode —
  runtime mitigation (hostNetwork/MTU), not chart work.
- Runner registration (separate ask / card #88) + migration (with LFS
  objects — DONE 2026-11-05, proven 74/74) + the one-shot repo seed (user
  action 8) are the owner preconditions; C07's remote legs and live
  verification depend on them.
- Gallery-call parsing is best-effort regex (C01 notes); the safe failure for
  unparseable calls is the machine-marked block, never an authored rewrite.

## Open questions

None — N1–N3 settled by the owner (final answer round below). New genuine
gaps surfaced during build enter the pipeline's normal RESULT/coord path.

### Resolved (owner answer round 2026-10-31 — recorded in DECISIONS.md)

Q1 instance = infra git.spencerslab.com · Q2 selection = allowlist file +
dispatch override · Q3 watchdog included phase 1 · Q4 force-push exempt on
bot-owned immich-sync · Q5 Netlify cutover + LFS carry-over = owner jobs ·
Q6 registration = ORG-scoped · Q7 cadence = DAILY · Q8 topology = dev-first
validation + gpu prod via card #88 (fixture E2E) · Q9 seam = albums INTO
existing pages, additive-only · Q10 (old open-q list) subsumed by the above.

### Resolved (final N-round 2026-10-31 — DECISIONS R11–R13)

N1 front matter on existing pages = append-only machine-marker keys, never
touch existing keys/flags; gate = PR + farm preview (as recommended) ·
N2 gallery fit = AUTO-EXTEND: sync manages machine-marked gallery calls
(idempotent, minimal, same PR; overrides the refuse-on-mismatch BG) ·
N3 `page:` REQUIRED on every allowlist entry — NO content/photos/ fallback
posture anywhere (overrides the BG; schema-invalid entries fail loud).

## User actions (preconditions — consolidated)

1. Choose/confirm Forgejo = infra; migrate CuratedForest.com WITH LFS objects
   (`git lfs fetch --all` first; push refs + `git lfs push --all`). (answer 5)
2. DEV validation runner registration (instance/org per dev-forgejo shape) →
   Bitwarden `dev-forgejo-host-runner` (uuid/token) → UUID into
   `custom-values/dev/prod-values.yaml` (replaces OVERRIDE_NEEDED).
   — REMOVED 2026-11-06 owner review: the dev runner instance is managed in a different ask; the chart's host-backend mode stays in this branch for it.
3. PROD (card #88 scope, listed for completeness): ORG-scoped runner on gpu
   for git.spencerslab.com + gpu→Immich network path resolution.
4. Bitwarden items (owner naming rule 2026-11-02 — `hugo-build-*`; closed
   records name the same items under the pre-rename label): Immich API key
   (owner account; EXACTLY asset.read/asset.view/album.read/tag.read) →
   `hugo-build-immich` (created); Netlify token +
   both site ids → `hugo-build-netlify` (created); Forgejo PAT →
   `hugo-build-forgejo` (MINTED+STORED 2026-11-05, owner confirmed): write:repository + Actions-write if
   offered, on a CuratedForest.com-writer, minted at git.spencerslab.com
   Settings→Applications — needed for BOTH seeder API-auth and workflow
   PR/push (automatic FORGEJO_TOKEN suppresses workflow triggers).
   — 2026-11-06: no longer consumed by a CronJob (seeder dropped); the items are the source for the one-shot manual repo-seed (action 8).
5. ~~GPU uuid fills~~ — **SUPERSEDED 2026-11-06 owner review**: the
   `forgejo-secret-seed:` / `forgejo-run-watchdog:` app blocks no longer
   exist (both charts dropped — user actions 2/4 context). The filled uuids
   remain in the closed records for provenance; the live surface is the
   one-shot manual repo-seed (action 8), which reads the hugo-build-* items
   directly.
6. After SpencersLab PR merges + ArgoCD syncs: dev runner pod Running + online
   in git.scifi.farm admin UI; trivial host-label workflow completes on a
   scratch dev repo (owner/coord creates e.g. `runner-host-validation`);
   seeder CronJob green against the prod repo once it exists; then dispatch a
   sync → PR → farm deploy observed → owner reviews/merges.
   — 2026-11-06: the dev-runner validation half is removed with action 2; the post-merge observation stands, gated on the (separate-ask) runner being online + the action-8 one-shot seed in place of "seeder CronJob green".
7. Disconnect Netlify git builds on both sites once CLI deploys are proven.
8. One-shot manual seed of the five repo secrets (IMMICH_API_KEY, NETLIFY_AUTH_TOKEN, NETLIFY_SITE_ID, NETLIFY_SITE_ID_FARM, FORGEJO_SYNC_PAT) and one repo variable (IMMICH_URL — the runner's view of Immich; gpu value settled by the cf-88 probe: https://immich.spencerslab.com) into the CuratedForest.com repo on Forgejo — the secrets from the hugo-build-* Bitwarden items, the variable as a plain Settings -> Actions entry (owner or coord-assisted; ~5 fields + 1 variable in repo settings). Until it runs, the first workflow run fails loud at first secret use — the designed shape.

## Follow-ups (not this ticket)

- Card #88: gpu prod runner + gpu→Immich path (owns live E2E against real Immich).
- Immich album-event trigger (phase 2) — now the schedule-coverage follow-up
  by default since the k8s watchdog was dropped 2026-11-06; the fallback if
  run-history coverage ever proves insufficient is a site-repo
  `.forgejo/workflow` catch-up cron, not a k8s CronJob.
- actions/cache for hugo/LFS warm builds; pin forgejo-host-runner `:main` →
  `:v<run>` once CI publishes; old-LFS removal card.

## Amendment log

- 2026-11-01 · sentinel-delivery premise corrected per DECISIONS "COORD
  FACT-RULE 2026-11-01": gpu bitwardenIds do NOT resolve from the ArgoCD
  cluster annotation (mechanism dead since `aa817da6b`, 2025-09-28; reviewer
  live-proof in chunks/C04.md review r1 MAJOR-1) — real delivery =
  custom-values/gpu app blocks projected via valuesObject, C04 shipped +
  APPROVED r2. Amended surfaces: Verified-facts bullet, Commands sweep
  comment + grep paths, risk-bullet precondition, User action 5, and
  chunks/C05.md (r1 D-2 propagation, before its dev round). The GPU
  placement decision (DECISIONS R9) is UNCHANGED — only its mechanism
  sentence is superseded (DECISIONS PLAN-AMEND line).
- 2026-11-05 · C07 dev r1 live finding: the forgejo-host-runner image (C02) carries no go binary, but the live site's hugo.yaml imports two hugo modules (lkhrs/hugo-dark-visitors, onweru/compose) → the first runner build of deploy.yml (both legs) fails at module download ("binary with name go not found in PATH" — reproduced clone-side at a hugo -D --gc stop). Added chunk C08 (S, wave 4, depends C02): pinned sha256-verified Go toolchain in the image; sequenced before the first live run and before the C07 PR opens. Also noted: the C05 watchdog app-block uuid fills (user action 5) ride the C08 dev session with suite re-validation (values = the two hugo-build-* item uuids already in the adjacent seeder block). Amended surfaces: Chunks table (C08 row + C07 precondition cell), Wave order (4), chunks/C08.md (new), STATE.json (C07 handoff + C08 entry).
- 2026-11-06 · OWNER BRANCH-REVIEW RUlINGS (cf-11-feat-immich-to-hugo vs main, line review): (1) `forgejo-runner-dev-host` dev-validation release OUT of this branch — the dev runner is managed in a different ask; the chart's host-backend MODE stays (inert without a release slice) for that ask to consume. (2) charts/forgejo-secret-seed DROPPED (C04) — no standing seeder; five repo secrets get a one-shot manual seed (plan user action 8). (3) charts/forgejo-run-watchdog DROPPED (C05) — commits + immich webhooks are the coverage. (4) runner image: no repo-carried bin/ wrappers — generated by a Dockerfile RUN step (C02 rework). (5) standing rule: no spencerslab/curatedforest/git.spencerslab.com literals in chart values.yaml — such values come from an ExternalSecret field where needed. (6) confirmed: the import+deploy pipeline job IS a forgejo job — C06's site-repo workflows, unchanged. Amended surfaces (plan-file coherence pass complete): Goal, Two-repo map, Cluster map, Commands (C03 block, C04/C05 block removed, sentinel sweep), Chunks table (C03 dev-release out, C04/C05 dropped), Wave order (5), Risks (schedule-fragility + preconditions bullets), User actions (2/4/6 notes + new 8, item 5 superseded), Follow-ups (watchdog item reworded), chunks/C02.md (REWORK + rework review notes), C04/C05 (DISPOSITION), STATE.json (rework_2026_11_06), board comment.
- 2026-11-06 · OWNER PR-REVIEW AMENDMENT (round 2, post-merge follow-up card #100): the live site imports hugo modules, so the runner image needs a Go toolchain for `hugo`'s module download — C08 (S, wave 4, depends C02) added: pinned sha256-verified Go in the forgejo-host-runner image, static-gate leg t11 red-first by agent-test. Amended surfaces: Chunks table (C08 row), Wave order (5), User actions (item 5 reworded), this bullet.
- 2026-11-06 · OWNER SITE-REVIEW ROUND 3 (the CuratedForest.com workflows in the owner's checkout): (1) IMMICH_URL leaves the workflow content — now a Forgejo repo VARIABLE referenced as ${{ vars.IMMICH_URL }} (the runner-specific value lives in repo settings: gpu = https://immich.spencerslab.com per the cf-88 probe; rotation = one settings edit, no repo commit). (2) deploy.yml + sync.yml COMBINED into a single .forgejo/workflows/pipeline.yml — two event-gated jobs: sync (schedule/dispatch only) imports + publishes the immich-sync PR; deploy (push/PR only) builds + delivers prod/farm. Behavior preserved 1:1 (mapping proof in the dev round's handback). Amended surfaces: user action 8 (5 secrets + 1 variable), C06 row, this bullet, chunks/C06.md. The site files are the owner's (their checkout, uncommitted); this branch carries the record only.
- 2026-11-06 · OWNER SITE-REVIEW ROUND 4 (pipeline.yml, owner's checkout): the album import is KEPT as its own job with its "create a PR if there are changes" behavior (owner: "I see the value in the album import"); its schedule moves 05:17 UTC → 06:00 UTC = the owner's local Denver midnight (confirmed zone when asked; Forgejo cron is UTC, no DST — exact midnight Nov–Mar/MST, 11 PM Apr–Oct/MDT). Deploy job, event gating, the IMMICH_URL repo variable, and sync-albums.yaml unchanged. Amended surfaces: this bullet, chunks/C06.md, STATE.json (owner_review_round4).
