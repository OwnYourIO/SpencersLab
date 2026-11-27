# PLAN: Improve build process (AD-159)
feature: 2026/2026-11-cf-159-refactor-build-process

## Goal
Bring the broken dev+gpu Forgejo runner story to a close by carrying the reviewed
C18 chart+test delta (commits 3d2159dca / 67569ebfe — the rebuilt branch was
re-anchored by the cf-55 r8 revert, D67; the commit objects are the port source)
into this ticket's tree, reconciling the live cluster state read-only (OQ3), then
bring the six-workflow build/sync threads to matching approaches: evidence-driven
quiet-by-default / DEBUG-gated output (errexit untouched), changed-set-scoped chart
packaging, and unification of the marker-gate / event-context / repo-add
divergences — all validated by the `tests/services/` contract suites.

Run posture: STANDARD pipeline shape (owner override D5) — work in the worktree
`/home/coder/.local/share/opencode/worktree/e32e19/cf-159-refactor-build-process`,
branch `cf-159-refactor-build-process` at base 1d46d1c84 (the origin/main tip at
mint; the OQ5 ff ruling executed as a rebase of the empty ticket branch after both
`git merge --ff-only` forms denied on the coord shell floor). The coordinator
commits each approved chunk on the branch; the never-advance-main law is honoured
by the branch itself. Landing (merge/PR + the D66(6) runner unstick sequence) stays
an owner leg. Recorded at rework time: origin/main has moved past the branch base
by `6ffeeb87e` (cf-55 r8: the D67 REVERT of the merged C17 refactor — C18 never
landed main, the re-anchor dropped the C18 commits from the rebuilt branch ref,
which now points at main's tip `5bea6160b`) + `5bea6160b` (plans record); see open
question 9 and DECISIONS D8.

## Out of scope
- Merging, pushing, or touching `main` in any form (repo hard rule; owner leg).
- The dev node capacity issue (5/10 runner pods unschedulable, EXPLORE §3.2) —
  OQ4 ruled out of scope; a separate capacity ticket (Deferred).
- Runner image pin / `appVersion` bump (cf-97 deferred class).
- The shared `ci/last-built` marker mechanism itself: sole-writer advance
  topology (D54), `fetch-depth: 0` law, marker-orphan red-with-owner-verbs law,
  the `${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}` idiom — all preserved, not re-ruled.
- Renovate chart-dep churn reduction, `lockFileMaintenance`, new-chart seed law
  (cf-55 round-4 owner rulings — untouched).
- No brand-new charts, so no `Y.M.1` seeding; no version hand-bumps (CI-only).
- The inline-vs-script detection split (build-charts inline vs two detect
  scripts) — documented-and-kept, not merged into a third shared detector.
- The act-runner platform noise (~21% of the biggest job: `##[]` / `[command]` /
  `##[endgroup]` markers, the Complete-job cleanup blocks, the checkout-action
  internals beyond the progress lines, registry-login warnings) — not gateable
  from workflow YAML (LOGSPAM verdict); recorded, not fixed.
- Re-basing the ticket branch onto the moved main tip (open question 9 — the
  approval round's call, not a chunk task).

## Commands
- path: `export PATH=$HOME/.local/bin:$PATH` (helm at `~/.local/bin`; required
  before any helm run)
- lint: `helm lint charts/forgejo-runner`
- template (hermetic — the chart's `charts/` dir is empty by repo convention, so a
  bare `helm template` needs a copy-side dependency update):
  `rm -rf /tmp/opencode/forgejo-runner-tpl && cp -r charts/forgejo-runner /tmp/opencode/forgejo-runner-tpl && (cd /tmp/opencode/forgejo-runner-tpl && helm dependency update . && helm template forgejo-runner .)`
- test (contract suites, run per-directory — no unit-test suite in this repo;
  baseline RE-MEASURED at rework time 2026-11-27 on the branch tip 1d7979c1e —
  base 1d46d1c84 = a91627e06 + 2 CI-bump commits (file-disjoint: the two
  Chart.yaml versions) + 2 docs commits (file-disjoint with the suites); all
  offline, all green except the one admitted red):
  `bash tests/services/dev-forgejo-runner.sh` (67 ok)
  `bash tests/services/gpu-forgejo-runner.sh` (25 ok — corrects the 24 recorded at
  planning: the a91627e06 tree also reports 25, the earlier handoff number was
  stale)
  `bash tests/services/forgejo-build-charts.sh` (34 ok)
  `bash tests/services/forgejo-main-sync.sh` (18 ok)
  `bash tests/services/forgejo-build-containers.sh` (50 ok)
  `bash tests/services/forgejo-builder-bootstrap.sh` (20 ok)
  `bash tests/services/forgejo-renovate.sh` (10 ok)
  `bash tests/services/forgejo-ci-surface.sh` — **admitted pre-existing red t4**
  at base (stale `docker-build.yaml` prose in `skills/seaweedfs-debug/` —
  cf-55 D44 admitted-reds class, unrelated to this thread; t1–t3 green); review
  gates a chunk on the legs that chunk's change owns, not on this base red.
- quality gate: `npx aislop` (CI: `aislop ci --changes` — every touched file must
  clear the score floor with no error-severity findings)
- docker build: `docker build => no-daemon, CI-deferred` (no container changes in
  this ticket; the line is the designed passing shape, cf-77)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Carry the C18 runner fix into the working tree (+ cluster-reconcile observation leg) | M | 1 | [] | the urgent breakage; file-disjoint from the workflow chunks; the card's priority orders it first |
| C03 | Scope chart packaging to the changed set | M | 2 | [] | independent of C01 (chart+tests vs build-charts.yaml); first owner of build-charts.yaml in the re-ordered sequence |
| C04 | Unify the builder family (gate shape, context, repo-add) | L | 3 | [C03] | same file (build-charts.yaml) + the package-leg comment re-truth; sequential review gates keep the suite green between chunks |
| C02 | Quiet-by-default / DEBUG-gated output (evidence-driven; errexit untouched) | M | 4 | [C03, C04] | its build-charts.yaml legs (fetch-quiet, output capture) must wrap the settled package-step shape (C03) and the extracted repo-add script (C04) so the suite re-aims once against the final shape (DECISIONS D6) |

Ids keep the draft names; the table is listed in wave order.

## Wave order
1. C01
2. C03
3. C04
4. C02

## Open questions
All eight draft questions were ANSWERED in the 2026-11-27 batched round
(DECISIONS.md "Batched question round" section — the authoritative record):
(1) the `set -e`/DEBUG reading → OQ1: re-directed to an EVIDENCE-driven gate set
(LOGSPAM.md); D2's errexit-untouched law stands (nothing in the ruling endorses
gating `set -e`). (2) packaging scope → OQ2: ruled as drafted (D3: narrow the
`cr package` publish legs; D47.1 full-tree lock self-heal stays; renovate churn
untouched). (3) C18 chart applied out-of-band → OQ3: RULED yes (dev+gpu) — C01's
chart hunk duplicates the live state (harmless, keeps the tree self-contained);
the D66(6) unstick chart-merge premise is satisfied; C01's observation leg
re-observes the clusters read-only and reconciles. (4) dev node capacity → OQ4:
out of scope, separate capacity ticket. (5) base on the true tip → OQ5: RULED;
executed via rebase (the ff forms denied on the coord shell floor). (6) landing
vehicle → OQ6: the owner lands THIS ticket's tree; D66(6) unstick runs once,
after that landing. (7) renovate `LOG_LEVEL` default → OQ7: STAYS `info`
(status quo — the scout's `warn` recommendation is overruled); `DEBUG=true`
raises it to `debug`. (8) cheap single-line diag echoes → OQ8: stay ungated.

NEW (surfaced by rework-time fact-check; for the approval round):
(9) The ticket branch is 2 commits behind the moved main tip: `6ffeeb87e` (the
D67 C17 revert — touches the same chart/test files C01 ports) + `5bea6160b`
(plans record). OQ5's "base on the true tip" principle collides with D1's
no-re-derivation law: re-basing onto `5bea6160b` would move the C18 port onto
the reverted registration shape (a re-derivation class). **Recommendation:** hold
the base at 1d46d1c84 (the C18 delta applies cleanly to the C17-state base as
authored); the chart-hunk fate at landing (D67's repo revert vs OQ3's live
out-of-band C18 parity) is the owner's landing-leg call (OQ6 mechanism is
owner-chosen). Confirm at approval.

## Risks / assumptions
- The C18 port source is the commit objects 3d2159dca / 67569ebfe, now only
  loosely reachable (the rebuilt branch re-anchor dropped them from the ref; the
  objects existed at rework time — C01's dev pass re-verifies resolvability at
  run start and stops with NEEDS_INFO if GC'd, never re-deriving, D1).
- The branch base (1d46d1c84) is 2 commits behind the current main tip (the D67
  revert + the plans record — open question 9); the 2 commits that moved the
  base past the a91627e06 measurement point are file-disjoint (the two Chart.yaml
  versions), so the re-measured suite baseline holds (Commands).
- `forgejo.*` context fields used by C04 (`event_name`, `event.before`, `sha`,
  `event.ref`) all have live fleet precedent in the same Forgejo 15.0.10
  instance (build-containers.yaml); the top-level `ref` has no proven `forgejo.*`
  sibling, so `github.ref` stays the documented fallback.
- C03 assumes `cr index --push` regenerates the gh-pages index from the
  repository's release assets (unchanged charts' tgz assets persist), so scoping
  the packaging leg drops nothing from the published index.
- The checkout-step quieting is mechanism-limited (DECISIONS D7): `show-progress:
  false` removes the `remote:` progress block only; the per-ref summary lines of
  the five full-depth checkouts are a documented residual (the action has no
  `--quiet`/refspec surface — v7 source-verified), while the two explicit
  `git fetch --tags` calls gate fully (`-q` empirically silent).
- Suite re-aims forced by a chunk's legitimate change route to the test session
  (validation-at-fault channel, cf-55 D50/D51 precedent) — never fixed by dev or
  review.
