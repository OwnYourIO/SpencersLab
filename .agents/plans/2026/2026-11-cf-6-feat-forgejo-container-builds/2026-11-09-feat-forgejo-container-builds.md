# PLAN: Forgejo container builds (card 6)
feature: 2026/2026-11-cf-6-feat-forgejo-container-builds
plan: 2026-11-09-feat-forgejo-container-builds.md

**Goal:** Port the container build/publish pipeline from `.github/workflows/docker-build.yaml` to a Forgejo Actions workflow (`.forgejo/workflows/containers-build.yaml`, infra instance) that keeps the changed-folder detection + per-container matrix and switches tags to CalVer: main builds push `yy.mm.N` + `:latest` (+ keep `:main`), PR builds push `pr-<branch>-<sha>` tags. The GitHub builder's narrowing to a `workflow_dispatch`-only manual fallback, the Renovate calendar-versioning packageRule, and the doc re-pin land as one atomic cutover on this branch.

**Architecture:** Two offline-testable pieces — a pure-shell detector/tag helper (`scripts/forgejo-container-detect.sh`) and a thin workflow that calls it — pinned by a contract suite (`tests/services/forgejo-containers-build.sh`, the `forgejo-main-sync.sh` template). "Deploy" stays the existing consume loop (publish → Renovate pin-bump PR → ArgoCD sync); the pipeline itself only publishes (OQ-6 ruling).

**Spec:** card request verbatim + `EXPLORE.md` §1–§11 + `RESEARCH.md` (TL;DR + A–D govern); rulings recorded in `DECISIONS.md` 2026-11-09 planning entry.

## Request (verbatim)

> Need to set up a forgejo pipeline that will build and deploy containers. It should work like the existing .github action in that it detects which folders were updated and only builds the updated ones. It should build main -> latest AND a tag. I prefer yy.mm.1++. It should also build any PRed branches. For those, should tag with the branch name, and additionally have a build hash.

## Out of scope

- dev-instance repair and dev-side build inclusion (CrashLoopBackOff, EXPLORE §3; separate workstream).
- The one-time pin-bump PR (`v84`/`v162` → first calendar tag) — needs a real tag that only exists post-merge; the coordinator's Inbox card (owner round).
- PR-tag GC / retention automation (GHCR has no retention policy, RESEARCH D; naming discipline only).
- Runner chart changes: extra runner records, job-timeout raises, dockerd `--mtu` (EXPLORE §3/§7 "do not touch").
- `:main` retirement (kept by ruling D4; retire-later is a docs/consumer change).
- Registry migration off `ghcr.io/ownyourio` (EXPLORE §5: record, don't pick).
- Any ArgoCD-side deploy step (publish = deploy, D6).
- Minting the GHCR PAT / entering the Actions secret / merging (human legs, below).

## Key decisions (full text + evidence in DECISIONS.md)

- **D1 → superseded by the owner round (2026-11-09): narrow, not delete.** `.github/workflows/docker-build.yaml` is kept but stripped to `workflow_dispatch`-only in C02 (push + PR triggers gone) — the GitHub-side manual rebuild escape hatch. The Renovate hazard resolves the same way: with no automatic GitHub builds, the calendar line is authoritative from activation (DECISIONS owner-round entry). Docs re-pin must state the fallback's manual-only status.
- **D2 infra-only guard:** every job `if: startsWith(forgejo.server_url, 'https://git.spencerslab.com')` (main-sync house pattern); dev excluded until recovered + secreted.
- **D3 CalVer `yy.mm.N`, registry-derived:** `N = max(yy.mm.* in ghcr tags/list) + 1`, then existence-advance until the manifest is free; GHCR tags are fully mutable (RESEARCH D), re-run semantics documented in-file. Renovate packageRule `versioning: regex:^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$` scoped to `ghcr.io/ownyourio/*` (docker datasource), lands **before or with** any pin bump — v-pins skip cleanly meanwhile (RESEARCH A, EMPIRICAL).
- **D4 rolling tags:** main builds push `:main` AND `:latest` (`:main` is a live consumer contract; rolling tags never compete as pins, RESEARCH contradiction 3).
- **D5 PR builds push** `pr-<sanitized-head_ref>-<short-sha>` only (card-literal; `pr-` prefix can never shadow rolling/calendar lines; sanitizer lowercases, `/`→`-`, strips to `[a-z0-9._-]`, ≤128). Owner gloss: PR builds run on the FORGE — PRs live there, so the GitHub PR trigger's departure in C02 is by design.
- **D7 `workflow_dispatch` kept** (free-text `containers` input, rebuild escape hatch); **`dev` leg dropped** (no dev branch exists on any remote, EXPLORE §1).
- **D8 build mechanics:** plain `docker build` + `docker push`; cache = the persistent 10 Gi dind docker-data VCT (no buildx cache backend, no `type=gha`); no `docker/*` actions (mirror-independence, RESEARCH C); only `actions/checkout@v6` from the proven mirror; auth `docker login ghcr.io -u OwnYourIO --password-stdin` with Actions secret `GHCR_PUSH_PAT`; top-level `concurrency: {cancel-in-progress: false}`; matrix `fromJSON` + `fail-fast: false` + per-cell unique job `name:`.

## Commands

```bash
export PATH=$HOME/.local/bin:$PATH   # house recipe; helm unused here (no chart changes)
bash tests/services/forgejo-containers-build.sh            # C01+C02 offline contract suite (red-first, no network)
bash -n scripts/forgejo-container-detect.sh                # detector syntax
python3 -c 'import yaml,sys; yaml.safe_load(open(".forgejo/workflows/containers-build.yaml"))'
rulesync generate && rulesync generate --check             # after .rulesync/rules/ edits (precedent 2faf55b8d; never `rulesync gitignore`)
bash tests/services/forgejo-containers-build.sh x1   # C02 trigger proof (authoritative): scoped to the on: block — a raw ^push: grep false-hits the docker/build-push-action `push:` INPUT key (~L150) that stays (coord-fixed per test-session OQ-2)
grep -n "containers-build" .rulesync/rules/overview.md skills/container-creation/SKILL.md   # docs re-pinned
# Renovate rule check (MCP, not shell — dev/test/review sessions): dev-renovate validate_config + test_package_rules
#   on renovate.json: rule matches ghcr.io/ownyourio/wekan-mcp (docker), NOT ghcr.io/mostlygeek/llama-swap
# docker build AC: `docker build => no-daemon, CI-deferred` is the passing shape (cf-77);
#   authoritative build test = the live Forgejo run on infra post-merge (user-owned leg).
```

No pytest here (no chart-test changes). `aislop ci --changes` does not scan `.sh`/`.yaml` (cf-119) — comment discipline is manual per repo rule; run `$aislop` on the touched `.md`/`.json` files.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Forgejo build workflow + detector + contract suite | M | 1 | [] | — |
| C02 | Atomic cutover: narrow GitHub builder to manual-only, Renovate calendar rule, docs parity | S | 2 | [C01] | correctness (RESEARCH B, owner round): the GitHub builder's automatic triggers must stop in the same change that ships the forge builder; docs parity re-pins rules to C01's workflow |

## Wave order

1. C01
2. C02 (after C01 review passes)

## Risks / assumptions

- First-fire unknowns (data.forgejo.org's action set beyond checkout, `ACTIONS_*` env for a future gha cache, `fail-fast` support on Forgejo): the design needs nothing unproven except `actions/checkout@v6` (live-proven, EXPLORE §3); diag step records the rest for the record.
- Runner job timeout is 30 m (chart) — a cold large build (vllm-rocm, coder-workspace) can exceed it; capacity-1 serializes the matrix. Follow-up card candidate if first real fires prove it.
- Atomic merge means the forge workflow is the only AUTOMATIC builder from merge onward (C02's narrowed `docker-build.yaml` stays as manual-dispatch fallback); mitigation: contract suite + the owner's pre-merge smoke (`workflow_dispatch` one cheap container on the pushed branch).
- Registry-derived N under >999-tag pagination would undercount the max; the existence-advance loop bounds the blast radius to overwrite-rebuild of the same content (documented, D3).
- While pins sit on `v84`/`v162` with the rule live, Renovate silently skips those deps (invalid-version, RESEARCH A) — intended stall until the bump PR, no downgrade PRs.
- PR legs run where PRs live — the forge (owner ruling 2026-11-09); C02 removing the GitHub PR trigger is by design, and the leg is exercised by real forge PRs, not ceremonial.
- Fork-PR rule (secrets empty for forked heads, EXPLORE §4): same-repo PRs only, noted in the workflow comment.

## Open questions — all ANSWERED by the owner batched round (2026-11-09)

1. **OQ-1 RESOLVED — narrow, do not delete.** `.github/workflows/docker-build.yaml` is kept, stripped to `workflow_dispatch`-only (push + PR triggers gone) as the GitHub-side manual rebuild fallback; the docs re-pin states its manual-only status. Supersedes D1 (DECISIONS owner-round entry).
2. **OQ-3 RESOLVED — confirmed** registry-derived `max(yy.mm.*)+1` + existence-advance. D3 stands.
3. **OQ-4 RESOLVED — confirmed** both `:main` and `:latest` on main builds. D4 stands.
4. **OQ-5 RESOLVED — confirmed with owner gloss:** PR builds run on the FORGE (PRs live there — the GitHub PR trigger's departure is by design); `pr-<branch>-<sha>` tags push to ghcr as D5 spells. D5 stands.
5. **Landing cadence RESOLVED — confirmed:** atomic single change on this branch + owner pre-merge `workflow_dispatch` smoke on the pushed branch.
6. **Follow-ups RESOLVED:** ONLY (a) the one-time pin-bump PR (v84/v162 → first calendar tag after the first forge build) becomes a coordinator-created Inbox card. (b) PR-tag GC, (c) runner records/timeout raise, (d) dev-instance inclusion + dev secret, (e) `:main` retirement — stay deferred, NOT cards.
7. **OQ-7 RESOLVED — confirmed:** the forge is the PR venue; the `pull_request` leg ships and is real, not ceremonial.

## Human legs (enumerate, don't implement)

1. Mint GitHub PAT (`write:packages`, OwnYourIO) → Bitwarden item (cf-119 UA pattern).
2. Enter Actions secret `GHCR_PUSH_PAT` on the infra instance, repo `CuratedForest/SpencersLab` — BEFORE the merge (PR and push legs both need it).
3. Owner pre-merge smoke (confirmed cadence): push the ticket branch to the infra forge, `workflow_dispatch` with `containers=traefik-mqtt-allowlist`, then merge (OQ-8 posture).
4. Merge the PR (user-owned; landing on main is never the agent's).
5. Post-merge first fire: next `containers/**` push (or a dispatch) mints the first calendar tags → the pin-bump then runs as the coordinator's Inbox card (follow-up (a) — the only card the owner round sanctioned).
