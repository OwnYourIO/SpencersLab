# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions

- Contract suites for this ticket follow the established
  `tests/services/forgejo-*.sh` shape: bash + embedded python3 (pyyaml), purely
  offline, one leg per invariant with mutation teeth, `set -euo pipefail`, YAML
  1.1 note (`on:` parses as boolean True — read `doc.get(True) or doc.get('on')`).
  A suite leg that a chunk's legitimate change reddens routes to the test
  session (validation-at-fault channel, cf-55 D50/D51 precedent) — never fixed
  by dev or review.
- `forgejo.*` event-context fields are adoptable only with live fleet precedent
  on the same Forgejo 15.0.10 instance (build-containers.yaml is the precedent
  carrier); top-level fields without a proven `forgejo.*` sibling (the `ref`
  family) keep the `github.*` compat name as a documented fallback.
- The `DEBUG` variable is an instance-side repo-scoped Actions variable (owner
  runbook item, the ROLE / RENOVATE_GIT_AUTHOR placement class); workflows read
  it via inline var reference (`vars.DEBUG` renders empty when unset — unset →
  false, per the card).
- Standing laws every chunk must keep green (cf-55 D52-D59 / cf-6 / D45):
  `fetch-depth: 0` on every diffing job, the marker-orphan red-with-owner-verbs
  shape, the `${GITHUB_OUTPUT:-$FORGEJO_OUTPUT}` output idiom, the per-file
  ROLE guard polarity (narrow on unset, the build-containers widen the
  documented exception), the build-charts `on:` exactly `{workflow_call}` pin,
  versions CI-only (no hand-bumps), ArgoCD-applies-only (never `kubectl apply`).
- Run posture: see D5 below — the ORIGINAL in-place posture was superseded by
  the owner's worktree override 2026-11-27T14:45Z. Landing (merge/PR + the
  cf-55 D66(6) runner unstick sequence) stays an owner leg. Baseline suite
  state 2026-11-27: dev-forgejo-runner 67 ok, gpu-forgejo-runner 24 ok,
  forgejo-build-charts 34 ok, forgejo-main-sync 18 ok, forgejo-build-containers
  50 ok, forgejo-builder-bootstrap 20 ok, forgejo-renovate 10 ok,
  forgejo-ci-surface RED t4 (admitted pre-existing, `skills/seaweedfs-debug`
  prose — cf-55 D44 class, excluded from chunk gates).

## Decisions

- 2026-11-27 plan D1 (C18 relationship): CARRY the C18 chart + test delta into
  this ticket's working tree (chunk C01), not reference-only. Rationale: the
  C18 delta is the designed, reviewed-APPROVED fix (cf-55 D66; branch
  commits 3d2159dca / 67569ebfe, review r1 APPROVED); reference-only would
  leave the runners broken until a separate merge of the rebuilt branch.
  Rejected: reference-only (the fix's landing is not guaranteed by this
  ticket's landing); re-deriving the fix from the decision prose (the branch
  file is the source of truth; re-derivation is the drift class). OQ6 (landing
  vehicle) since RULED — this ticket's tree lands, the branch's C18 content is
  the duplicate to drop.
- 2026-11-27 plan D2 (the DEBUG reading): KEEP `set -euo pipefail` always (43
  run blocks + 3 scripts untouched) and gate the VERBOSE OUTPUT on `DEBUG`
  (unset → false): the `docker info` / `env | grep ACTIONS_` / `docker buildx
  version` diag dumps and the renovate `LOG_LEVEL` (chunk C02). Rationale:
  errexit emits nothing — the card's "set -e makes logs chatty" hypothesis does
  not hold on the evidence (EXPLORE §1.4), and gating errexit weakens the
  failure gate in load-bearing bump/push/publish steps (the 5-attempt bump loop
  and the staged-content guard assume `set -euo pipefail`). SUPERSEDED target
  set by the batched-round OQ1 answer (below): the gate list is evidence-driven
  (LOGSPAM.md), errexit stays untouched.
- 2026-11-27 plan D3 (the touched-charts scope): NARROW the `cr package
  charts/*/` publish legs (release + forgejo-publish) to the changed set (chunk
  C03); the full-tree `helm dependency update` lock self-heal STAYS (D47.1 —
  deliberate ruling: one drifted lock outside the changed set would poison the
  publish legs; byte-no-op on a fresh lock, cheap on churn); the detection and
  the per-chart test-build matrix are already touched-scoped and stay; renovate
  chart-dep churn stays untouched (cf-55 round-4 rulings' domain). Rejected:
  scoping the self-heal too (breaks D47.1's named rationale). RULED in the
  batched round exactly as drafted.
- 2026-11-27 plan D4 (the unification split): UNIFY in scope (chunk C04) —
  (a) the marker-gate shape (build-charts' `push` legacy belt retired; the
  three builders read one `workflow_call` skip shape), (b) the event-context
  family (fleet-proven fields only, per the conventions), (c) the triple-
  duplicated helm repo-add loop (extracted to `scripts/forgejo-helm-repo-add.sh`
  — the D45 fix had to be applied at three sites; the extraction kills the
  drift class). DOCUMENT-AND-KEEP (comments + this record, no behavior change):
  the guard polarity (build-containers widen on unset — the deliberate
  builder-class ruling), the registry walk shapes (two-registry union vs the
  single-registry bootstrap walk — OQ-1=B), the exit postures (warn-and-skip
  green vs red-on-setup-error — two halves of one doctrine), the concurrency
  postures, the inline-vs-script detection split, the `github.ref` fallback and
  the renovate `github.server_url` / `github.repository` compat reads (no
  proven `forgejo.*` siblings — betting the fleet's sync on an unproven context
  field is the class this plan refuses).
- 2026-11-27 human D5 (posture override, in-session): the card left
  `Worktree Creation` unchecked (D28 in-place, zero-commit posture) — the
  owner directed "you missed the worktree and branch step. Please do so".
  Human instruction supersedes the card default: kickoff mint ran complete —
  worktree `.local/share/opencode/worktree/e32e19/cf-159-refactor-build-process`,
  branch `cf-159-refactor-build-process` (MINTED a91627e06 off local main, then
  `git rebase origin/main` → branch == origin/main tip 1d46d1c84, honouring the
  OQ5 ff ruling after the `git merge --ff-only` forms denied on the coord shell
  floor), warm + session_move ran. Posture reverts to the STANDARD pipeline
  shape: coordinator commits each approved chunk on the ticket branch; the
  never-advance-main law is honoured by the branch itself. Consequences: the
  ticket folder was rebuilt in the worktree (main-checkout reads deny
  `external_directory` post-move, cp/mv deny — dump-leg carry for EXPLORE.md +
  chunks via the still-located scout session); the stray duplicate worktree
  `cf-159-refactor-build-process-2` (created by a replayed mint before the
  state was re-checked; `worktree_remove` denied out of step-10 scope) is
  removed at run cleanup; `coord_session` is captured
  (ses_de48b8d53ffeX58xO2I6x47B2k, via the session_move return + lock holder —
  the Session Rename leg itself stays unchecked, the id is recorded because it
  is legitimately known), so the `slug`-stack line lands as the combined
  `[<slug>](<session link>)` form at write-back.

## Batched question round — human rulings (2026-11-27, coord session)

- 2026-11-27 human OQ1 (the DEBUG reading): RE-DIRECTED both readings — the owner
  ruled "look at the logs and identify what makes them spammy". Neither the
  planned best guess nor the literal errexit gate stands as drafted: C02's target
  set must come from EVIDENCE in live Forgejo workflow-run logs (scout pass ->
  LOGSPAM.md in this folder), then gate those actual spam sources under DEBUG.
  The errexit-untouched posture itself is untouched by the redirect (nothing in
  the answer endorses gating `set -e`). DECISIONS D2 re-aims to the findings.
- 2026-11-27 human OQ2: RULED — narrow packaging only (D3 stands as drafted:
  `cr package` publish legs scoped to the changed set; D47.1 full-tree lock
  self-heal stays; renovate churn untouched).
- 2026-11-27 human OQ3: RULED — the C18 chart IS already applied out-of-band to
  dev and gpu. Consequences: the C01 chart hunk duplicates live state (harmless,
  keeps the tree self-contained); the D66(6) unstick sequence's chart-merge
  premise is satisfied already — what remains is landing + the owner-side STS
  recreate/verify legs. Recorded tension: EXPLORE §3.2 observed 0/10 ready on
  both clusters ~05:30Z, consistent with C17 live — C01's dev pass must
  re-observe the clusters read-only and reconcile (pods may predate the apply or
  the recreate may still be pending) rather than assume.
- 2026-11-27 human OQ4: RULED — dev node capacity OUT of scope; separate
  capacity ticket (Deferred stands).
- 2026-11-27 human OQ5: RULED — base the work on the true tip before chunks.
  Executed per D5: ticket branch rebased to origin/main (1d46d1c84); local
  `main` ref untouched (its ff denied on the coord shell floor — moot now).
- 2026-11-27 human OQ6: RULED — the owner lands THIS ticket's tree; the rebuilt
  branch's C18 content becomes the duplicate to drop. D66(6) unstick runs once,
  after that landing.
- 2026-11-27 human OQ7: RULED — renovate `LOG_LEVEL` default stays `info`
  (status quo); `DEBUG=true` raises it to `debug` only.
- 2026-11-27 human OQ8: RULED — the cheap single-line diag echoes stay ungated;
  DEBUG gates only the heavy dumps (as C02's evidence-driven scope decides).

## Deferred

- The dev node capacity issue (5/10 runner pods unschedulable, EXPLORE §3.2) —
  OQ4 ruled out of scope, a separate capacity ticket.
- The renovate chart-dep churn reduction (OQ2 second rejected arm) — separate.
- The runner image pin / `appVersion` (cf-97 deferred class) — untouched.
- `skills/seaweedfs-debug` stale `docker-build.yaml` prose (the base ci-surface
  t4 red) — the admitted-red class, another ticket's sweep card.
- Stale duplicate ticket folder left in the MAIN CHECKOUT
  (`/home/coder/SpencersLab/.agents/plans/2026/2026-11-cf-159-refactor-build-process/`,
  frozen at ~14:45Z, unreachable from this session post-move) — owner-side
  cleanup or a future run there; the worktree copy is authoritative.
- Duplicate worktree `cf-159-refactor-build-process-2` — removed at step-10
  cleanup (D5).
