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
a **daily** schedule + workflow_dispatch. Card #11 builds and validates the
host-backend runner mode **on DEV**; the prod runner on gpu is delegated to
card #88 (external precondition), which also owns the gpu→Immich network path —
so card #11's sync E2E is **fixture-based** (fake Immich server in tests).

Direction is locked (DECISIONS.md "DIRECTION LOCKED BY OWNER") and amended by
the owner answer round (DECISIONS.md "OWNER ANSWER ROUND"); the three RESEARCH
docs remain the evidence base.

## Two-repo map

| Surface | Repo | Status |
|---|---|---|
| Sync/publish tooling, toolchain image, runner chart host mode (**dev validation release**), secret seeder + watchdog (**gpu wiring**) | SpencersLab (this repo, branch worktree) | fully buildable/validatable now |
| Workflows (deploy/sync) + the `sync-albums.yaml` page-mapping allowlist | CuratedForest.com | staged in this ticket folder (`site-staging/`); local checkout dirty + pre-Forgejo, stays UNTOUCHED; applied to the Forgejo clone in C07 once the owner migrates the repo |

Cluster map (owner answer round): **dev** = this ticket's runner-mode
validation; **gpu** = seeder/watchdog wiring + future prod runner (card #88);
**infra** = target Forgejo (`git.spencerslab.com`, prod); **home** = Immich
(data source only — no card-#11 landing; gpu→home API path is card #88's open
item). Blocked-on-owner preconditions gate C07 + live verification only; all
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

# C03 chart + DEV wiring (deps are gitignored; Chart.lock committed)
helm dependency build charts/forgejo-runner
helm lint charts/forgejo-runner
helm template charts/forgejo-runner --set bitwardenIds.runner-token=00000000-0000-0000-0000-000000000000 --debug
bash tests/services/dev-forgejo-runner.sh        # EXTENDED red-first to the two-release dev contract (C03)
helm dependency build services/dev/prod
helm template dev services/dev/prod <sentinel --set list pinned by the test scripts> --debug

# C04/C05 charts (gpu wiring — chart-level sentinel strings shadowed by the
# custom-values/gpu app blocks; C04 shipped, r2 APPROVED)
helm dependency build charts/forgejo-secret-seed && helm lint charts/forgejo-secret-seed \
  && helm template charts/forgejo-secret-seed --set bitwardenIds.immich-api-key=u --set bitwardenIds.netlify=u --set bitwardenIds.forgejo-pat=u
helm dependency build services/gpu/prod
helm template gpu services/gpu/prod <sentinel --set list pinned by the test scripts> --debug
bash tests/services/gpu-forgejo-secret-seed.sh && bash tests/services/gpu-forgejo-run-watchdog.sh

# Sentinel sweep — two flavors, both matched 1:1:
grep -rn 'OVERRIDE_' charts/forgejo-runner charts/forgejo-secret-seed charts/forgejo-run-watchdog \
  services/dev/prod/values.yaml services/gpu/prod/values.yaml \
  custom-values/dev/prod-values.yaml custom-values/gpu/prod-values.yaml
# OVERRIDE_VIA_CUSTOM_VALUES <-> custom-values/dev keys; OVERRIDE_NEEDED app-block slots in
# custom-values/gpu <-> each gpu chart's bitwardenIds keys (USER ACTION per slot — fill with
# the Bitwarden item UUID; the OVERRIDE_VIA_CLUSTER_ANNOTATION strings in chart/service values
# are inert shadowed defaults, fleet practice, NOT delivery instructions)

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
| C03 | `charts/forgejo-runner` host-backend MODE + DEV validation release `forgejo-runner-dev-host` (gpu prod = card #88) | L | 1 | [] | chart-internal; image NAME plan-locked; dev instance in-cluster URL |
| C04 | `charts/forgejo-secret-seed` — Bitwarden→Forgejo repo-secret seeder, **gpu wiring** | M | 1 | [] | independent chart; secrets rule compliance |
| C05 | `charts/forgejo-run-watchdog` — schedule-failure watchdog (INCLUDED phase 1, answer 3), **gpu wiring** | M | 3 | [C04] | reuses C04's PAT/URL values pattern |
| C06 | Site-repo artifacts staged: deploy+sync workflows (daily cron), sync-albums.yaml page-mapping schema (no archetype/section — N3) | M | 2 | [C01] | workflows call C01's tool contract |
| C07 | Apply staged artifacts to CuratedForest.com on Forgejo (branch+PR) | S | 3 | [C06] | blocked on owner precondition (repo migrated to Forgejo) |

## Wave order

1. C01, C03, C04 — independent (different file sets).
2. C02 (needs C01), C06 (needs C01's contract).
3. C05 (included, owner-locked), C07 (blocked until the repo lives in Forgejo).

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

- **Schedule fragility** is weightier at daily cadence (one shot/day): C05
  watchdog (hourly check, 48h threshold) + manual dispatch are the mitigation
  (answer 7 note, research §1.1).
- **k3s MTU / forgejo-runner#1779** may bite action clones in host mode —
  runtime mitigation (hostNetwork/MTU), not chart work.
- Runner registration + migration (with LFS objects) + tokens + gpu
  custom-values/gpu OVERRIDE_NEEDED slot fills are owner preconditions; C07
  and live verification depend on them.
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
3. PROD (card #88 scope, listed for completeness): ORG-scoped runner on gpu
   for git.spencerslab.com + gpu→Immich network path resolution.
4. Immich API key (owner account; EXACTLY asset.read/asset.view/album.read/
   tag.read) → Bitwarden `cf-sync-immich`; Netlify token + both site ids →
   `cf-sync-netlify`; Forgejo PAT (write:repository) → `cf-sync-forgejo`.
5. GPU uuid fills — **NOT annotation edits** (the cluster-annotation mechanism
   is dead since `aa817da6b`; see Verified facts + DECISIONS COORD FACT-RULE):
   replace each `OVERRIDE_NEEDED` slot in the `forgejo-secret-seed:` app block
   of `custom-values/gpu/prod-values.yaml` with its Bitwarden item UUID
   (immich-api-key / netlify / forgejo-pat — C04 shipped this block), and the
   same for C05's `forgejo-run-watchdog:` app block when it lands (reuses the
   same items; no new mandatory items).
6. After SpencersLab PR merges + ArgoCD syncs: dev runner pod Running + online
   in git.scifi.farm admin UI; trivial host-label workflow completes on a
   scratch dev repo (owner/coord creates e.g. `runner-host-validation`);
   seeder CronJob green against the prod repo once it exists; then dispatch a
   sync → PR → farm deploy observed → owner reviews/merges.
7. Disconnect Netlify git builds on both sites once CLI deploys are proven.

## Follow-ups (not this ticket)

- Card #88: gpu prod runner + gpu→Immich path (owns live E2E against real Immich).
- Watchdog upgrade to Immich native album trigger when it ships (phase 2 shim).
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
