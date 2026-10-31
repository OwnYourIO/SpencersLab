# PLAN: Immich → Hugo photo pipeline (CuratedForest.com via Forgejo runner)

feature: 2026/2026-10-cf-11-feat-immich-hugo-pipeline

## Goal

Build the owner-locked phase-1 pipeline: an in-cluster Forgejo **host-backend
runner on a PVC** that syncs Immich preview derivatives into CuratedForest.com
page bundles (one PR, update-in-place, `draft: true` + `author_reviewed: false`
machine pages), and deploys the Hugo site to Netlify via CLI (merge→main =
curatedforest.com; PR→main = curatedforest.farm, last PR wins). Triggers are
`schedule` + `workflow_dispatch` (sync) and `push`/`pull_request` (deploy) —
the socket.io album-event shim and old-LFS removal are explicitly later.

Direction is locked (DECISIONS.md 2026-10-31 "DIRECTION LOCKED BY OWNER"); the
three RESEARCH docs are the evidence base. This plan implements the lock.

## Two-repo map

| Surface | Repo | Status |
|---|---|---|
| Toolchain image + sync/publish tooling, runner chart host mode, secret seeder, watchdog | SpencersLab (this repo, branch worktree) | fully buildable/validatable now |
| Workflows (deploy/sync), album archetype, `content/photos/` section, `hugo.yaml` docSections edit | CuratedForest.com | staged in this ticket folder (`site-staging/`); local checkout is dirty (2 ahead of origin + WIP) and stays UNTOUCHED; applied to the Forgejo clone in C07 once the owner migrates the repo |

Blocked-on-owner preconditions (gate C07 and live verification only; all
SpencersLab chunks are independently validatable): Forgejo instance chosen +
repo migrated **including LFS objects** (471 MB aeroponics originals), runner
registration + Bitwarden items, Netlify token/site ids, Immich API key, PAT.

## Out of scope

- Standing up Forgejo itself (owner: "I'll get the repo into Forgejo"); the
  existing dev/infra instances and the DinD dev runner are untouched.
- Album-change EVENT triggers (socket.io `on_album_update` shim) — phase 2.
- Old-LFS-image removal (`content/plants/aeroponics/**`, ~407 MB) — card #87.
- IPP/folio B′ companion — separate.
- Any auto-merge anywhere; single-PR invariant; zero template changes to
  `layouts/_shortcodes/gallery.html`; the two existing manual derivatives in
  `current-grows` are never touched (hard guard extends to all of `content/plants/**`).
- Touching `/home/coder/CuratedForest.com` working tree (read-only survey; C07
  works against a Forgejo clone).

## Commands

```
export PATH="$HOME/.local/bin:$PATH"   # helm + hugo 0.151.0+extended live here

# C01 tooling tests (pytest per-directory convention)
python3 -m pytest containers/forgejo-host-runner/tests/ -v

# C02 image — agent sessions have no docker daemon:
docker build containers/forgejo-host-runner => no-daemon, CI-deferred   # designed passing shape
bash tests/containers/forgejo-host-runner.sh && hadolint containers/forgejo-host-runner/Dockerfile

# C03 chart + home wiring (deps are gitignored; Chart.lock committed)
helm dependency build charts/forgejo-runner
helm lint charts/forgejo-runner
helm template charts/forgejo-runner --set bitwardenIds.runner-token=00000000-0000-0000-0000-000000000000 --debug
bash tests/services/dev-forgejo-runner.sh        # regression — must stay green UNCHANGED
bash tests/services/home-forgejo-runner-cf.sh    # new contract (agent-test)

# C04/C05 charts
helm dependency build charts/forgejo-secret-seed && helm lint charts/forgejo-secret-seed \
  && helm template charts/forgejo-secret-seed --set bitwardenIds.immich-api-key=u --set bitwardenIds.netlify=u --set bitwardenIds.forgejo-pat=u
bash tests/services/home-forgejo-secret-seed.sh
# (C05 same shape; bash tests/services/home-forgejo-run-watchdog.sh)

# Home umbrella render (mirror the dev-umbrella pattern; the full sentinel
# --set list is pinned by the new test scripts, dev-forgejo-runner.sh-style)
helm dependency build services/home/prod
helm template home services/home/prod -f custom-values/home/prod-values.yaml \
  --set domain=spencerslab.com --set clusterName=home <sentinel --set list> --debug

# Sentinel sweep (every OVERRIDE_VIA_CUSTOM_VALUES matched 1:1 in custom-values/home;
# only documented OVERRIDE_NEEDED user-fill placeholders allowed in custom-values)
grep -rn 'OVERRIDE_' charts/forgejo-runner charts/forgejo-secret-seed services/home/prod/values.yaml custom-values/home/prod-values.yaml

# C06 staged site artifacts (hugo render gate runs on a SCRATCH COPY in /tmp/opencode —
# the real repo is never written; module cache already holds compose@pinned)
python3 -m pytest .agents/plans/2026/2026-10-cf-11-feat-immich-hugo-pipeline/site-staging/tests/ -v

# Quality gates
npx aislop ci --changes
```

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Sync + publish tooling (Python stdlib) in `containers/forgejo-host-runner/` | M | 1 | [] | core logic; defines the tool contract C06 calls |
| C02 | `forgejo-host-runner` toolchain image (runner+hugo+netlify-cli+git-lfs) | M | 2 | [C01] | Dockerfile COPYs C01's modules |
| C03 | `charts/forgejo-runner` host-backend mode + home release wiring (`forgejo-runner-cf`) | L | 1 | [] | chart-internal; image NAME is plan-locked (tag `:main`, no pinned tag yet) |
| C04 | `charts/forgejo-secret-seed` — Bitwarden→Forgejo repo-secret seeder + home wiring | M | 1 | [] | independent chart; satisfies "ExternalSecret+Bitwarden for every secret" |
| C05 | `charts/forgejo-run-watchdog` — schedule-failure watchdog (DEFERRABLE) | M | 3 | [C04] | reuses C04's PAT/URL values pattern |
| C06 | Site-repo artifacts staged: deploy+sync workflows, album archetype, photos section, hugo.yaml edit spec | M | 2 | [C01] | workflows call C01's tool contract |
| C07 | Apply staged artifacts to CuratedForest.com on Forgejo (branch+PR) | S | 3 | [C06] | blocked on owner precondition (repo migrated to Forgejo) |

## Wave order

1. C01, C03, C04 — independent (different file sets).
2. C02 (needs C01), C06 (needs C01's contract).
3. C05 (deferrable by owner), C07 (blocked until the repo lives in Forgejo).

## Verified facts (this planning session)

- `charts/forgejo` + `charts/forgejo-runner` EXIST (v1.0.2, appVersion 13.2.0,
  DinD shape; release `forgejo-runner-dev` on dev; `forgejo-runner-infra`
  un-wired 2026-10-25, relocation pending). Forgejo instances: dev
  (`git.scifi.farm`/`git.dev.scifi.farm`) and infra (`git.spencerslab.com`
  canonical + `forgejo.spencerslab.com` alias; local-path PVC 10Gi).
- Immich hub route (`services/proxy-local`) is SSO-gated with
  `ssoAllowedPaths: [/.well-known/immich, /api/server/ping]` only → API-key
  clients CANNOT reach Immich cross-cluster through the hub → the runner must
  sit on the **home** cluster for `http://home-immich-server:2283` (precedent:
  `charts/immich-analyze` uses exactly that URL from home's `default` ns).
- CuratedForest.com: `.gitattributes` LFS-tracks jpg/jpeg/png/gif/webp/svg
  (derivatives land as LFS automatically; post-migration LFS lives in Forgejo
  storage); `netlify.toml` pins HUGO_VERSION 0.151.0; `docSections` lacks
  `photos`; front-matter convention incl. `author_reviewed`/`editor_reviewed`;
  gallery contract = page resources sorted by Name; repo dirty (2 ahead + WIP).
- Agent env has `hugo v0.151.0+extended` at `~/.local/bin` (exact site pin —
  corrects the launch assumption "no local hugo") → C06 gets a real render gate.
- Precedents: cronjob controllers (`charts/spotdl`), per-source ExternalSecret
  stores incl. `bitwarden-fields` (`charts/immich-analyze`, `charts/archon`),
  `OVERRIDE_NEEDED` user-fill placeholders in custom-values, client-only
  runner releases with no proxy leg, contract test scripts under
  `tests/services/` rendering from /tmp copies.

## Risks / assumptions

- **Schedule fragility** (research §1.1): mitigated by C05 watchdog + manual dispatch.
- **k3s MTU / forgejo-runner#1779** hit the dev DinD runner during action
  clones; host mode clones actions in the pod itself. If checkouts die:
  hostNetwork or node MTU tuning — owner/dev response, not planned work.
- Runner registration + LFS-bearing migration + tokens are owner preconditions;
  C07 and live verification cannot pass without them.
- Best guesses marked `(BG)` in Open questions carry impact if flipped.
- Forgejo infra data PVC is 10Gi; +407 MB LFS fits, long-term sizing = owner note.
- Sync PRs grow LFS history monotonically (accepted; DECISIONS).

## Open questions (batched to owner — best guess + impact recorded)

1. **Which Forgejo instance hosts CuratedForest.com?** (BG: infra,
   `git.spencerslab.com` — canonical lab git.) Impact: `runner.url` value,
   seed/watchdog URL, registration target, C07 clone URL.
2. **Card Services = gpu+home — what was gpu for?** All SpencersLab workloads
   land on home (Immich reachability finding above; exposing Immich API
   cross-cluster would need new hub `ssoAllowedPaths` = security-posture
   change). (BG: gpu untouched in phase 1.) Impact: re-plan runner placement.
3. **Album selection model**: v3 `AlbumResponseDto` has NO album-level tags, so
   BG = allowlist file in the site repo (`sync-albums.yaml`) + dispatch-input
   override; asset-tag opt-in later. Impact: C01 selection module, owner UX.
4. **Runner registration scope**: BG = repo-scoped (least privilege) vs
   instance-admin. Impact: Bitwarden item contents, Forgejo admin steps.
5. **Relation to the pending `forgejo-runner-infra` relocation**: BG = coexist
   (ours is a new purpose-named host runner). Impact: naming/item reuse.
6. **Watchdog in phase 1 (C05) or deferred?** BG = include. Also notification
   channel: HA is deployed from `services/grow` → cross-cluster from home; BG =
   generic notify URL value the owner points anywhere (HA/n8n). Impact: 1 chunk.
7. **Sync cadence**: BG = hourly `17 * * * *` UTC (cheap probe-then-exit) —
   locked window was "hourly/daily". Impact: cron line, watchdog threshold.
8. **`content/photos/_index.md` ships `draft: true`** (BG) — section hidden on
   prod until owner flips. Impact: first-publish UX only.
9. **Force-push of the machine branch `immich-sync`** (BG = yes — ephemeral
   single-commit batch branch; documented exception; owner review comments
   may go stale between runs). Impact: PR hygiene.
10. **Netlify cutover**: owner disconnects git builds on BOTH sites after first
    CLI deploy (else two deploy writers), and migration includes `git lfs
    fetch --all` + LFS push to Forgejo (else aeroponics builds break). Confirm.

## User actions (preconditions — consolidated)

1. Choose Forgejo instance; migrate CuratedForest.com **with LFS objects**
   (`git lfs fetch --all` first; push refs + `git lfs push --all`).
2. Create runner registration (BG: repo-scoped) → Bitwarden item
   `home-forgejo-cf-runner` (LOGIN: username=uuid, password=token) → UUID into
   `custom-values/home/prod-values.yaml` (replaces `OVERRIDE_NEEDED`).
3. Immich (owner account that owns the albums): API key with EXACTLY
   `asset.read, asset.view, album.read, tag.read` → Bitwarden `cf-sync-immich`.
4. Netlify: auth token + site ids for curatedforest.com and .farm → Bitwarden
   `cf-sync-netlify`; create Forgejo PAT (`write:repository`, BG repo-scoped)
   → Bitwarden `cf-sync-forgejo`.
5. (If C05 approved) notify endpoint/token → Bitwarden per C05 notes.
6. After SpencersLab PR merges + ArgoCD syncs: runner pod Running; runner
   online in Forgejo UI; trivial workflow completes on the host label; then
   `workflow_dispatch` a sync → PR opens → farm deploy observed → owner flips
   flags and merges the sync PR → prod deploy observed.
7. Disconnect Netlify git builds on both sites once CLI deploys are proven.

## Follow-ups (not this ticket)

- Watchdog phase-2 upgrade to Immich native album trigger when it ships (research §8.2).
- actions/cache for hugo/LFS warm builds (optimization; PVC already persists).
- Pin `forgejo-host-runner:main` → `:v<run>` once CI publishes; renovate then tracks it.
- Card #87: old-LFS removal from aeroponics.
