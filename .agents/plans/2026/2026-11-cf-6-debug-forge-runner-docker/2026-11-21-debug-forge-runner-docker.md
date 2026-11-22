# PLAN: forge runner docker socket — complete the chart socket contract
feature: 2026/2026-11-cf-6-debug-forge-runner-docker
status: draft — scope USER-PRE-APPROVED 2026-11-21 ("Ok, looks like a good plan, but you
need to implement it. Please use the openrouter flash model for all going forward.");
no question round — the four planned OQs land as USER-RULED decisions below.

## Goal
Complete the runner chart's socket contract so forge container-build jobs can `docker
build`: add `container.docker_host: unix:///var/run/docker.sock` to the docker-backend
branch of `charts/forgejo-runner/templates/secret-runner.yaml` (runner v13.2.0 default
`-` = never share the in-pod dind socket with job containers — EXPLORE §2/§4/§6). Land
the four pre-existing main-red legs + the blast-radius fence into the same landing so
the tree's runner/build suites go fully green.

## Out of scope
- The cf-55 `release.yaml` push-run failures on infra (runs **94/97/101/106**, non-docker)
  — Deferred below; the fix round (C05-C07) has since merged on main, retest before filing.
- `tests/services/forgejo-ci-surface.sh` t4 (red on current main — seaweedfs-spec
  docker-build mentions lack the manual-fallback co-naming; a cf-55/D29 close-out-sweep
  survivor, zero overlap with this landing's files) — recorded + deferred, OQ-B.
  [2026-11-22, as-applied correction: the "zero overlap" claim held for t4 but NOT for
  t3 — the C02 x4-note's literal `.github/workflows/release.yaml` (suite L2082)
  overlapped t3's hard-exit live-surface grep sweep and turned it green→red; caught by
  the FINAL whole-plan review round 1 (the suite was outside the Commands bar —
  FRICTION lesson booked). The note is being reworded via test-r4 to the sanctioned
  "GitHub release twin" phrasing, and the final bar gains a ci-surface re-run leg
  (expect t3 green, red ONLY at t4).]
- AGENTS.md / `.rulesync` edits; rewriting the 2026-10 research docs (historical record).
- The host-backend branch of the template (card #88 territory) — untouched by design.
- All owner legs (merge, sync, restart, re-run, tag checks) — user-owned, listed below.

## USER-RULED decisions (folded in from the 2026-11-21 directive — not open items)
1. **OQ-1 ABSORB** the pre-existing main-red legs into this landing:
   `forgejo-containers-build.sh` t6+t12 (re-pin `actions/checkout@v6`→`@v7` — the
   `b80fae102` Renovate bump moved the pin: the uses-set pin, the t12 checkout-step
   counter, plus the t6 comment + ok message), x4 (drop the deleted
   `.github/workflows/release.yaml` from the six-file scope fence — grounded DROP:
   the fence's intent is the `.github` sibling fleet; the cf-55 side of the move is
   already pinned by `forgejo-ci-surface.sh` t1/t2 and `tests/agent-board-coord/*`
   twin-path bans, so re-pointing at the `.forgejo` file would fork a different
   concern), and `dev-forgejo-runner.sh` t5 (dated correction of the stale
   "relocation is pending" dev-values comment, falsified by cf-104 `e824542f8`
   2026-11-05 — see Verified facts for the two-part mechanism). Rationale: landing
   tree fully green; teeth-move-with-docs (cf-6 C01 precedent).
2. **OQ-2 MINIMAL doc scope**: a dated why-comment on the new template line (job→dind
   socket share; runner v13.2.0 default `-`; cf-97 covered the runner→dind leg only)
   + the chart's `container:`-block description lines in `values.yaml` (grounded: the
   dind-sidecar comment "jobs stay sandboxed (`container.privileged: false` …)" and the
   header's docker-backend summary both exist and must stay truthful). NO AGENTS.md
   edit. The workflow's "in-pod dind daemon (chart socket contract)" diag comment
   (.forgejo/workflows/containers-build.yaml L172-174) **stays** — the fix makes it
   fully true. 2026-10 research docs are historical record — do not rewrite.
3. **OQ-3 cf-55 release.yaml red set OUT** — run ids 94/97/101/106 recorded as the
   follow-up card's seed in Deferred.
4. **OQ-4 owner-leg order a→e** after merge (see "Post-merge owner legs").

Rejected alternatives (ruled end state, recorded — EXPLORE §7): `automount` (works
identically here but less precise, discovery-order coupling); TCP 2375/2376 (cf-97
rejected plaintext b1 / TLS-unverified b2); `runner.envs.DOCKER_HOST` alone (the MOUNT
is missing, not the env). No workflow/guard/detection change — the 41-leg contract
teeth stay put except the absorbed drift re-pins.

## Verified facts (plan session 2026-11-21, read-only; EXPLORE.md is the scout base —
these are the deltas my grounding runs added)
- **Baseline moved**: `origin/main` = `6c16aad4a` (20 commits since `b80fae102` — the
  cf-55 fix round C05-C07 + cf-135/cf-55 records landed). The branch must be rebased
  onto the current tip before dev (it has no commits — trivial fast-forward).
- **The cf-55 baked-label swap does not change the defect or the fix**: template diff
  touches only the labels comment block; the rendered docker config still carries
  `container: {privileged: false}` with NO `docker_host` (rendered on the tip, verified).
  The four act-24.04-family labels now resolve to `ghcr.io/ownyourio/forgejo-runner:26.11.1`
  — `containers/forgejo-runner/Dockerfile` states its inventory inherits the act base's
  "docker CLI + buildx + compose" (D36 no-regression law), so jobs still have the CLI;
  the missing MOUNT is still the whole bug.
- **Red set on the tip (ran every relevant suite in a temp worktree of `6c16aad4a`,
  removed after)**: `dev-forgejo-runner.sh` 33 ok/1 red (**t5** — "both runners dial
  out" message); `forgejo-containers-build.sh` 38 ok/3 red (**t6, t12, x4**);
  `forgejo-ci-surface.sh` **t4 red** (out-of-blast-radius, see Out of scope);
  `gpu-forgejo-runner.sh` 18/18, `forgejo-release.sh` 20/20, `infra-forgejo.sh` 33/33,
  `forgejo-lfs.sh` 40/40, `forgejo-packages.sh` 8/8, `forgejo-main-sync.sh` 8/8,
  `forgejo-renovate.sh` 8/8 (+t9 default-off skip), `forgejo-move-config.sh` **8/8**
  (was 6/6 at `b80fae102` — cf-55 grew two legs).
- **t5 is two-layered** (my run + read): the trigger is the `\bboth\b` region check
  catching the *cf-93 pair comment* ("appName == chart name for both", services/dev
  values L118) — the trio-exemption forward region scan swallows the next entry's
  leading comment. Independently, the comment it pins (L111-113 "relocation is
  pending") is itself false since cf-104. Fixing either one alone leaves t5 red:
  DEV lands the dated comment correction (target wording below contains `infra`,
  `relocat*`, names `forgejo-runner-dev`, and no "both"); TEST moves the teeth —
  re-word the L866-867 pins to the corrected text AND narrow the region capture so a
  following entry's leading comment is not read as this entry's. The suite's own
  header note (L18-21 "relocation pending") is stale too — TEST corrects it.
- **Deployment chain grounded (readonly MCP only, no admin, no exec, no secret reads)**:
  both releases are **StatefulSets** — `gpu-forgejo-runner-gpu` (gpu cluster, ns
  `default`) and `dev-forgejo-runner-dev` (dev cluster, ns `default`) — live-verified:
  `reloader.stakater.com/auto: "true"` on both STS metadata; each mounts Secret
  `<release-name>` (the ExternalSecret target, `mergePolicy: Merge`) via the
  `runner-creds` volume (config.yaml subPath — no hot update, restart is mandatory).
  Reloader runs on both clusters (`default/gpu-reloader-reloader-*`,
  `default/dev-reloader-reloader-*`). The dev STS pod template carries a live reload
  stamp for exactly that Secret (`last-reloaded-from` type SECRET, hash, observedAt
  2026-11-06T21:07:36Z) — the chain is proven in production. The gpu STS has no stamp
  yet (created 2026-11-05, its Secret never changed since) — the post-sync restart is
  reloader's first observed reload there; fallback owner commands in owner-leg (a).
- `npx aislop scan --changes` runs in this workspace (cliVersion 0.22.2): score 100,
  0 findings; format/lint engines skip ("no formatter/linter for the detected
  languages" — YAML/bash have no analyzers) — FRICTION expectation confirmed as fact.
- The ticket folder is not gitignored (`git check-ignore` rc=1) — the record can ride
  the landing commit.
- Local `main` ref now equals `origin/main` (6c16aad4a) — g7's DIFF_BASE resolves to
  the tip, so g7 sees exactly this landing's diff.

## Commands (the validation bar — every form verified working this session)
```bash
export PATH=$HOME/.local/bin:$PATH          # helm lives there (AGENTS.md; without it
                                            # the suites mass-skip helm-guarded legs)
# In-blast-radius suites (final bar = ALL green on the landing tree):
bash tests/services/dev-forgejo-runner.sh        # green incl. the new docker_host pin;
                                                 # t5 green after the absorbed fix
bash tests/services/forgejo-containers-build.sh  # 41/41 after the t6/t12/x4 re-pins
bash tests/services/gpu-forgejo-runner.sh        # green incl. the re-armed g7 (OQ-C)
# Adjacent forgejo families (green pre-landing; must stay green):
bash tests/services/forgejo-main-sync.sh         # 8/8
bash tests/services/forgejo-renovate.sh          # 8/8 (+t9 default-off skip)
bash tests/renovate/forgejo-move-config.sh       # 8/8 at the current tip
bash tests/services/forgejo-ci-surface.sh        # t3 green; red ONLY at t4 (the
                                                 # deferred seaweedfs-spec leg) —
                                                 # added post-final-review-r1 so the
                                                 # deferral claim is re-verified at
                                                 # every gate
# Direct render bar (mirrors the new teeth; the repo path has no built deps —
# dependency-build a COPY, the t1/g1 shape):
W=/tmp/opencode/cf6-verify; rm -rf $W; mkdir -p $W
cp -R charts/forgejo-runner $W/chart && (cd $W/chart && helm dependency update .)
helm lint $W/chart
U=d3dafd1a-3d88-454e-88d4-b4ec010ae2c2   # any non-sentinel uuid works; this is the
                                         # committed dev custom-values id
# docker backend (chart default — the shape of BOTH live releases; per-release url
# is slice-driven, irrelevant to the container block):
helm template gpu-forgejo-runner-gpu $W/chart --set "bitwardenIds.runner-token=$U" \
  | # ExternalSecret → spec.target.template.data["config.yaml"] → container: must be
    # {privileged: false, docker_host: unix:///var/run/docker.sock} — exact key set
# host backend (the C03 gate demands the three null-outs alongside backend=host):
helm template host-probe $W/chart --set "bitwardenIds.runner-token=$U" \
  --set runner.backend=host \
  --set 'app-template.controllers.runner.initContainers.dind=null' \
  --set 'app-template.controllers.runner.containers.runner.env.DOCKER_HOST=null' \
  --set 'app-template.persistence.socket=null'
  # → config keys stay [cache, host, runner, server]; NO container key — the fix
    touches the else branch only, the host rendering must be unchanged
# rulesync generate --check: N/A — no .rulesync source is in scope (verified: none of
#   the five changed files is under .rulesync/).
# aislop: npx aislop scan --changes --json on the staged landing — expect score 100
#   with format/lint engine-skips on YAML/bash (fact recorded; review re-runs it).
```
**Red-first doctrine**: the new docker_host pin leg is **RED on the pre-fix tree**
(rendered container block lacks the key — verified today) and green after DEV's line.
t5/t6/t12/x4 are **RED right now** (re-verified on `6c16aad4a`) and green after the
absorbed moves. g7 must stay green on the landing only via its re-arm (OQ-C) — without
the re-arm the fix line and the dev-comment hunk redden it. Every other leg: green
before, green after, unchanged.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Socket contract completed — template fix + chart/dev doc lines + render pins + t5 + g7 | M | 1 | [] | — |
| C02 | Absorbed containers-build drift — t6/t12/x4 teeth re-pins | S | 1 | [] | independent: disjoint files from C01 (the two suites share no file); run in id order |

No C-final chunk is minted: the whole-tree bar is the final whole-plan review re-running
Commands (coord gate), per the role's "prefer fewer cohesive chunks". C01 groups the fix
with t5/g7 because their teeth move **with** the fix lines — splitting would ship a
chunk that a single S task could have joined (and g7 cannot be green before the fix
hunks exist).

## Wave order
1. C01, C02 (independent; run in id order; test phase writes both suites' files before
   either dev — repo pipeline convention).

## Landing mechanics
- Rebase `cf-6-debug-forge-runner-docker` onto current `origin/main` (`6c16aad4a`+)
  **before dev** — the plan is grounded on the tip; nothing else on the branch.
- **ONE new commit** on the branch = fix + absorbed drift + this ticket folder's record
  (`git check-ignore` says the folder is trackable). Coord stages the files; **OWNER
  commits** (coord floor denies `git commit`; cf-6 -3 bot precedent). Push/PR/merge stay
  user-owned; `main` is never advanced by any agent.
- **EXCLUSION RULE**: the 3 locally-modified cf-6 run -3 record files
  (`2026-11-cf-6-feat-forgejo-container-builds-3/{STATE,DECISIONS,FRICTION}.md`) are -3
  record tail — OUT of this landing (one branch, one concern); do not stage them.
- Routing (hard): DEV floor allows `charts/**`/`services/**` and **hard-denies
  `edit tests/**`** (cf-6 -3 C01 precedent) — TEST owns ALL `tests/**` writes: the new
  pin leg, t5 teeth, g7 re-arm, t6/t12/x4. Recorded in every chunk file header.

## Post-merge owner legs (ruled order a→e — user-owned)
a. Merge → ArgoCD syncs both Applications → reloader restarts each runner pod
   (`gpu-forgejo-runner-gpu` on gpu, `dev-forgejo-runner-dev` on dev — grounded chain
   above). **Fallback** if a pod has not rolled within ~10 min of sync:
   `kubectl -n default rollout restart statefulset/gpu-forgejo-runner-gpu` (gpu
   kubeconfig) and `kubectl -n default rollout restart statefulset/dev-forgejo-runner-dev`
   (dev kubeconfig) — kind/name live-verified (StatefulSet, not Deployment).
b. Rendered-config byte check (EXPLORE §6.1, owner-only — readonly MCP cannot read
   Secrets): both Secrets' `config.yaml` must show the `docker_host` line under
   `container:`.
c. Re-run one failed PR run from the Actions UI (e.g. run 110 / the latest batch) or a
   scratch PR touching `containers/**` — "build and push the pr tag" must get past
   docker build + push.
d. `FORGE_PUSH_TOKEN` tags/list on the instance registry (EXPLORE §6.3): a
   `pr-<branch>-<sha>` tag lands under `curatedforest/<container>`.
e. First calendar `yy.mm.N` mints on the next main build touching `containers/**`
   (prod role: ghcr + instance registry, `:latest`/`:main` too).

## Risks / merge caveats (for the PR)
- **Security posture**: jobs gain control of the in-pod dind daemon — the designed
  capability, within the cf-97 trust boundary (pod-local daemon, no host mounts beyond
  its own PVCs, capacity 1 = one job's dind world at a time; the docs' automount
  caveats — cross-job visibility, `docker run -v` escape — bound to the same pod-local
  daemon). The runner container already holds gid 2375 over that daemon.
- Both runner pods restart once post-sync: capacity-1 downtime blip; in-flight jobs get
  the 30m/5m timeouts + 300s grace (values ruling 4) — a running job is cut and its run
  fails/requeues. Schedule owner-leg (a) in a quiet window.
- The dev runner carries the identical latent defect and is fixed by the same commit —
  dev PR builds touching `containers/**` would have hit it (EXPLORE §5).
- The absorbed drift (checkout v7 pin, release.yaml fence entry, relocation comment)
  is **main's pre-existing red set, not caused by this change** — recorded per leg.
- The cf-55 `release.yaml` red set is OUT (Deferred) — this landing does not make
  release push runs green.
- Post-cf-55, job containers are the baked `ghcr.io/ownyourio/forgejo-runner:26.11.1`
  image — verified it inherits the docker CLI/buildx (D36), so the fix lands on the
  new job-image shape; if the owner has not yet synced cf-55's runner config, both
  changes ride the same sync (byte check in leg b shows both).

## Deferred (follow-up card seeds)
- cf-55 `release.yaml` push-run failures on infra — runs **94/97/101/106** (non-docker;
  cf-55 territory). Note: the cf-55 fix round (C05-C07, merged by `6c16aad4a`) targets
  exactly these — retest the next main push touching `charts/**` before filing; if
  still failing, seed the card with these run ids.
- `forgejo-ci-surface.sh` t4: `skills/seaweedfs-debug/references/mcp-server-spec.md`
  L281+L287 cite `docker-build.yaml` without the workflow_dispatch manual-fallback
  co-naming — a D29 close-out-sweep survivor (out of blast radius; OQ-B best-guess:
  defer with the sweep card, not absorb). 2026-11-22: the t9-exemption retirement —
  due when the owner pastes the real HA UUIDs — rides this same close-out-sweep card.

## Open questions (best-guess resolved — owner-vetoable at PR; no live round)
- **OQ-A** t5 teeth design: TEST narrows the trio-exemption region capture (the cf-93
  comment above the NEXT charts entry must not be read as this entry's trailing block)
  and re-words the L861-867 pins to the corrected comment. Best-guess: exclude the
  contiguous comment run immediately preceding the next sibling key.
- **OQ-B** `forgejo-ci-surface.sh` t4 NOT absorbed (zero blast-radius overlap; same
  deferral family the suite header itself carves out). Best-guess: record + seed the
  close-out sweep card. Owner veto alternative: fold the 2-line spec reword into C02.
- **OQ-C** g7 blast-radius fence re-arm: g7 as written reddens on ANY non-comment,
  non-label chart line and on any services/dev `forgejo-runner` line. Best-guess:
  re-arm in the same landing — the chart leg gains a sanctioned edit class (exactly one
  added `docker_host: unix:///var/run/docker.sock` line in the template's else branch),
  the dev leg tolerates the dated relocation hunk while still rejecting new gpu-attrib
  content in dev files, keeping the leg's original hazard-detection intent.
- **OQ-D** New pin leg placement: TEST's choice — extend the t2/t3 config-parse block
  per release or add a standalone numbered leg (precedent: t14/g-legs are standalone
  red-first insertions). Optional symmetry: assert the same container key set in
  `gpu-forgejo-runner.sh` g2 (same rendered config, per-release view).
