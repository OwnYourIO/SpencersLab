# DECISIONS — AD-56 Forgejo pipeline for Coder templates

## 2026-11-25

- **Model route override (owner, in-session)**: card Model(s) = `Qwen Dense` + `Local`
  resolves per pipeline-models to `gpu-ai/qwen3.8-27b-radiance`. The first
  `agent-explore` launch on that route died with `peer proxy error: dial tcp
  10.43.162.16:8000: connect: connection refused` — the documented parked-q27-pod
  502 shape (replicas 0 in git). Owner then ruled: "Use radiance tp2 27b" →
  every tier of this run (plan/research/explore/test/dev/chunk-review/final-review)
  runs on `gpu-ai/qwen3.8-27b-radiance-tp2` — the resting opt-in 2-card lane,
  routed here on explicit request per the lane's rule. If this lane answers
  the same 502, the owner must scale the `gpu-ai-radiance-q27-tp2` release up;
  no further silent lane-hopping by the coordinator.
- **Dependency-gate override (owner, in-session)**: AD-56 carries an outbound
  `related-to` edge to AD-135 (grj3HFxsi3WzM5y96, live in **Review**), which
  would normally block pickup. Owner ruled "Override — process AD-56 now anyway".
- **Shared claim (owner, in-session)**: the `CICD` pipeline lock was live-held by
  AD-139's run (ses_e322c32b0ffe5HJ6VipD19SFKD). Owner authorized co-tenancy;
  claimed with `shared: true` (setId 4b1f093c-f27d-44c8-b36e-c964c6c7f9a2).
- **Gated kickoff legs**: card Lifecycle checklist lacks a `Session Rename` item →
  rename leg skipped, `kickoff.coord_session: null` (reason session-rename-skipped),
  claim comment carries the `unnamed` token, slug-stack line will be the bare slug.
  `Worktree & Branch creation` checked → worktree + branch minted
  (`cf-56-feat-forgejo-coder-template-pipeline` @ bfe424a4), warmed, session moved in.

## 2026-11-25 (plan)

Plan authored 2026-11-25 (plan tier on the tp2-27b lane per the model-route ruling);
three chunks (C01 image, C02 scripts, C03 workflow+runbook; waves 1/1/2). Best-guess
decisions carried into the plan's Open questions (OQ1–OQ9) for the batched round:

- **D1 — one endpoint per executing instance (OQ1)**: the card's "the coder endpoint
  should come from a variable" reads singular → instance-side repo var `CODER_URL` +
  repo secret `CODER_SESSION_TOKEN` (the `main-sync.yaml` instance-side doctrine: no
  URL/token literal in the file, identical-safe to host on both Forgejo instances).
  Each instance pushes the changed templates to its OWN Coder with its own per-cluster
  var values. Rejected: the `argocd-fanout.json` cross-instance roster shape (a single
  file driving both endpoints with a token list) — it contradicts the card's singular
  var, and per-instance placement is one var set per instance.
- **D2 — CLI in its own image, not baked (OQ3)**: new `containers/coder-cli` (the
  `renovate.yaml` job-level `container:` precedent — the house answer for "the tool
  needs its own image"), built by the EXISTING `containers-build.yaml` lane (no new
  workflow, no appset — the name is DNS-safe + `Dockerfile`-gated). Rejected: run-time
  `curl coder.com/install.sh` (the D33 flaky-egress class, documented risk not a
  default) and baking into `forgejo-runner` (the hand-bumped calendar-tag law — no
  Renovate lane reads that pin — plus an owner chain before the first fire).
- **D3 — narrow-on-unset, both role members; main-push-only + dispatch (OQ2)**: the
  publish-to-external-service class is fail-safe (the `release.yaml` posture), and
  both members fire because each instance serves its own Coder. No PR leg: fork heads
  carry empty secrets and a PR would mint an active version.
- **D4 — `CODER_SESSION_TOKEN` env name (OQ4)**: the docs' CI shape for the pinned
  CLI; the script reads exactly `CODER_URL` + `CODER_SESSION_TOKEN`; the runbook's UA
  leg verifies auth with `coder whoami` before first use (a legacy-name fix would be
  one env line).
- **D5 — value-var naming (OQ5)**: `CODER_NS_<TEMPLATE>` per template,
  `CODER_USE_KUBECONFIG`, `CODER_SHARED_PVC_NAME`; the three version pins stay in
  `terraform.tfvars` (auto-loaded, the repo's GitOS single source of truth). Unset
  value var = `--var` omitted (server-side resolved values are preserved, logged
  loud); a SET var is passed.
- **D6 — token lifetime (OQ6)**: mint at the server's max allowed lifetime; the
  30-day default is a monthly-401 trap (EXPLORE Q5); rotation by vault overwrite
  (the cf-139 OQ10 posture).
- **D7 — the user-owned `--default-ttl 168h` is NOT re-asserted (OQ7)**: the
  2026-10-19 fusion plan records it user-owned; a push does not reset template-level
  settings; the runbook states it as an answer.
- **D8 — detection job limits the push to changed templates**: every push mints a
  version (EXPLORE gotcha 7) — pushing unchanged siblings would churn versions on
  every template edit; the `containers-build.yaml` detect+matrix+dispatch shape is the
  house pattern and powers the dispatch escape hatch.
- **D9 — runbook + parity suite (cf-139 shape)**: `.agents/notes/
  2026-11-25-coder-template-push.md` with UA1–UA5 owner legs, the postures stated as
  answers, and `tests/notes/coder-template-push-runbook.sh` pinning them.

## 2026-11-26 (coord decision — C04 review nit)

- Review C04 minor finding: main-sync.yaml sync-fanout header reword is a 4th change site
  beyond the sanctioned 3. COORD ACCEPTS: post-C03 there are three called builders, the
  old 'both called builders (C15)' would misinform; the new text carries the ruled
  coupling (coder-red skips advance-marker, deliberately NOT sync-fanout) and no suite
  pins the old wording. Recorded so the cross-ticket edit's full diff is legible.

## 2026-11-26 (coord ruling — ci-surface t4 pre-existing red)

- tests/services/forgejo-ci-surface.sh t4 is RED since the r5 merge itself (seaweedfs spec
  leg, byte-identical between branch and main @ 5f5762a19; confirmed by agent-test's heal
  wave). Suite fail-fasts, so full-suite runs die at t4 before t8.
- RULING: DEFER — fixing t4 would violate the OQ14 ruling (t2–t7 byte-identical) and pull
  an unrelated upstream leg into C04. C04 gates use per-leg probe runs (t1 + t8 + the six
  touched legs); the t8 expectation after dev's 20-line re-fence stands as the gate.
  A follow-up card is proposed to the owner at the friction round (step 11).
- Technique noted from test wave: per-leg state read via &-free sed no-op probe variants;
  an &-bearing replacement corrupts fail calls (produced one false-green in the wave —
  caught, re-run clean).

## 2026-11-26 (batched round 2 — owner rulings, r5 shapes)

- **OQ10 RULED FAN MEMBER — overrides the plan's standalone best-guess**: the coder-template
  workflow joins main-sync's prod-main fan as a `workflow_call` run (build-containers r5
  contract: own push arm retired, marker-first + call-bootstrap arms, advance job retired —
  main-sync's aggregate is the single marker writer). Accepted consequence, spelled in the
  question and ruled anyway: the fan runs on the PROD-STAGE instance, so automated coverage
  is the gpu Coder; DEV-SIDE pushes ride the `workflow_dispatch` escape hatch on the dev
  instance (manual leg — the runbook must state it). Supersedes OQ1's automation reach,
  not its per-instance endpoint story.
- **OQ11 RULED SHARE ci/last-built**: consistent with fan membership — one shared
  per-repo-per-instance marker ref, read marker..sha on called runs, no own ref, no own
  advance. Coupling accepted: a red coder leg blocks the aggregate's advance (needs-gate),
  and a red sibling holds the marker (re-covered next fan — the law's designed behavior).
  Remote pre-state noted by scout: ci/last-built not yet live (first green fan creates it);
  only ci/containers-built exists.
- **OQ12 confirmed step-owned** warning law (retire the C03 inversion).
- **OQ13 confirmed short runbook note** + asymmetries reworded to D57 topology + UA3
  re-verified (four :26.11.1 pins intact; C01 suite 9 ok green post-merge).
- **OQ14 confirmed FULL HEAL in C04** of upstream tests/services/forgejo-ci-surface.sh
  (FJ_SET six-workflow re-aim + t1 prose; t8 green via the same-commit stale-ref re-fence;
  D50.3 pairing; suite bytes test-session-owned).
- **Cross-ticket surface accepted with the ruling**: C04 edits main-sync.yaml (fan entry +
  needs wiring) and the ci-surface suite — cf-55/cf-139 territory by ownership, sanctioned
  here by explicit owner choice.

## 2026-11-26 (round 2 — main r5 merged; C04 re-ground required)

- **Owner instruction**: "pull in main as the shape has changed some and you'll need to
  adapt." Replan commit 16df8a38d banked first; then `git merge main` @ 5f5762a19
  (cf-55 round 5) — clean auto-merge, no conflicts.
- **Lock status**: lastReap 2026-11-26T08:10 reaped the CICD key's AD-139 holder group
  (silent); THIS run's claim (setId 4b1f093c) survived fresh and is now the key's only
  holder (`shared:false`). Card stays Executing, owned.
- **The r5 law supersedes the r4 grounding C04 was written against** (AGENTS.md diff):
  containers-build.yaml RENAMED build-containers.yaml; it is now a workflow_call CALLED
  run from main-sync's prod-main fan (C15); the marker is the SHARED `ci/last-built`
  (C14) and main-sync's AGGREGATE job advances it once the whole fan's builders publish
  green — the builder workflow no longer advances its own marker; a called run with no
  marker narrows tip-only and announces; build-charts rides the same shared marker on the
  prod-main fan. `scripts/forgejo-container-detect.sh` changed again (73 lines).
- **Merge touched C01's surface**: containers/forgejo-runner/Dockerfile (2 lines),
  tests/containers/forgejo-runner.sh (4 lines), charts/forgejo-runner/values.yaml
  (9 lines) — post-merge regression re-run required; the runbook UA3 `:26.11.1` pin facts
  need re-verification.
- **Consequence**: C04's design re-ground needed against r5 — own-workflow marker vs
  sharing `ci/last-built` (a path-filtered consumer sharing a fan-advanced marker is the
  dead-run-loss class again — must be reasoned, not guessed), advance-job shape under the
  workflow_call idiom, stale `containers-build.yaml` refs across my four artifacts +
  EXPLORE r2/C04 text. The interrupted OQ10–OQ13 round will be RE-ISSUED in the r5 shapes
  after the delta scout + plan re-ground.

## 2026-11-26 (main moved — marker-scheme adaptation round)

- **Catch-up merge (owner-side)**: `00cedcd1e` merged main tip `52d3b5c45` (cf-55 round 4)
  INTO this ticket branch (author: Spencer's Bot (Claud), 02:57 UTC). AD-56's work is NOT
  on main (`git branch --contains 63351b411` = ticket branch only); the owner's "I merged
  in main" means the branch adopted main, not that the branch landed. Working tree clean,
  my C01–C03 artifacts intact post-merge.
- **Upstream law change requiring adaptation** (AGENTS.md diff): containers-build detection
  is now `marker..sha` — from the last-built marker ref, advanced only on a push run whose
  whole build matrix published green; whole `before..sha` is the marker-missing fallback;
  empty range from a PRESENT marker is informational (proves nothing missed), no-op push and
  empty dispatch stay silent, empty `before` fatal, unresolvable range fails loud. Also
  `release.yaml` -> `build-charts.yaml` with calendar Y.M.N chart bumps.
- **Owner instruction**: "Checkout containers-build.yaml for how it works there and adapt
  for coder templates if not already done." The C02 detector models the OLD shape, so
  adaptation is needed; same dead-run loss class applies (a push that died mid-matrix leaves
  templates unre-covered by the next before..sha range). Round opens: fresh agent-explore on
  the delta -> agent-plan replan (C04) -> agent-test extension -> dev C04 -> review ->
  final-review delta round. `plan_status` -> needs-replan until the reworked plan lands.
- **Precedent pointer**: main carries `.agents/plans/2026/2026-11-cf-6-debug-detect-rerun/`
  — the detect-rerun ticket whose ruling produced the marker law; read it for intent.

## 2026-11-25 (batched plan-question round — owner rulings)

- **OQ1 confirmed**: per-instance, both Coders; each executing Forgejo pushes every
  changed template to its own instance.
- **OQ2 confirmed**: main-push + paths filter + workflow_dispatch escape hatch;
  narrow-on-unset `contains(vars.ROLE,'dev') || contains(vars.ROLE,'prod')`; no PR leg.
- **OQ3 RULED DIFFERENT — owner override**: bake the coder CLI into
  `containers/forgejo-runner` (plan's best guess D2 was a new `containers/coder-cli`
  image). Accepted consequences: the runner image's chart label pin is bumped by hand
  to the newest published calendar tag (AGENTS.md law), no Renovate lane reads it, and
  the image's rebuild must land before the first template push fires. C01 re-scoped;
  D2 superseded; OQ8 retags onto the forgejo-runner line.
- **OQ4 confirmed**: `CODER_SESSION_TOKEN` (+ `CODER_URL`), runbook verifies with
  `coder whoami`.
- **OQ5 RULED MINIMAL — owner** ("that seems like too many … Just need to login and
  push the template"): exactly one var (`CODER_URL`) + one secret
  (`CODER_SESSION_TOKEN`). All template input values come from in-repo
  `terraform.tfvars`/template files; per-instance value differences must be expressible
  there, or the planner documents the single residual mechanism it needs. D5 superseded.
- **OQ6 confirmed**: tokens minted at server max lifetime; rotate by vault overwrite.
- **OQ7 confirmed**: `--default-ttl 168h` stays user-owned, not re-asserted.
- **OQ8**: moot as posed (no coder-cli image) — folded into OQ3's forgejo-runner
  calendar-tag story; a verify-the-published-tag leg stays in the runbook.
- **OQ9 confirmed**: rename/delete not mirrored.
- **Overall**: owner pre-approved conditional on the rework — once the plan session
  folds these rulings, coord flips `plan_status: approved` and proceeds to Test
  Writing + the chunk loop without a second approval round.

## 2026-11-25 (plan re-work, rulings folded)

Plan re-worked in-session to fold the rulings above; no second approval round per the
overall ruling. C01 re-scoped to the `forgejo-runner` bake (the `containers/coder-cli`
image idea is retired — no new image, no new pin; the workflow's push job runs on the
job image as today, `runs-on: ubuntu-24.04`, no `container:` field). OQ8 retired
into the runbook's UA3 verify-the-published-tag + hand label-pin bump leg.

- **D10 — `namespace = "default"` from the repo (OQ5 ruling, verified 2026-11-25
  against the actual files)**: the only required variable without a repo-side value in
  either template is `namespace` (required, no default; absent from the kubernetes
  tfvars, no tfvars at all in kubernetes-hardened); every other variable has a
  `main.tf` default (the three version pins already in the kubernetes tfvars).
  `default` is valid for BOTH instances: both coderd releases in `default`
  (`services/dev/prod/values.yaml:101`, `services/gpu/prod/values.yaml:143`), the gpu
  `dev-shared` PVC manifest carries no namespace key → `default`
  (`services/gpu/prod/templates/pvc-dev-seaweedfs.yaml`), the dev git-auth secrets
  `github-pat`/`forgejo-token` in `default` (`services/dev/prod/templates/
  secret-*.yaml:11` — the hardened template's own header requirement). No per-instance
  value differs → no Forgejo value var needed; the script passes NO `--var`. The
  single residual mechanism (a divergent workspace namespace later) is documented as a
  runbook answer: one `--var namespace=...` from one instance-side var. C02 lands the
  tfvals edit + the new hardened tfvars.
- **D11 — the runner-bake sequencing is a runbook owner leg (OQ3 ruling
  consequence)**: merge → `containers-build.yaml` publishes the new `forgejo-runner`
  calendar tag → the owner hand-bumps the four act-label lines in
  `charts/forgejo-runner/values.yaml` (currently `:26.11.1`; the AGENTS.md law — no
  Renovate lane reads that pin) → ArgoCD syncs the runner releases → only then may a
  template push fire. A first-fire `command not found: coder` is the sequencing state
  (loud via the diag's plain `coder version` call, the D43 class), not a pipeline bug.
  The chart label pin is deliberately NOT a chunk task.

## 2026-11-26 (C04 replan — marker-scheme adaptation)

Replan round (`plan_status` `needs-replan` → `awaiting-approval`; coord flips to
`approved` after the batched round): the `00cedcd1e` catch-up merge carried main's
marker law (cf-55/cf-6) + the `release.yaml` → `build-charts.yaml` rename; the owner
instructed the coder-templates adaptation "if not already done" — the landed C02
detector models the OLD shape, so the adaptation is the directive. C04 added (wave 3,
`depends_on` C02+C03 — both done); C01 unaffected (no image/chart surface); C02/C03
touched only with supersession notes (R2-Q4: no in-place fix), never re-opened;
`scripts/coder-template-push.sh` out of scope (R2-Q4: no stale references). Best-guess
pins carried into the batched round (the plan's OQ10–OQ13 table):

- **D12 — C04 scope (OQ10, best guess: full upstream mirror)**: the `marker..sha` arm
  + the `advance-marker` job + the warning-law alignment + the re-run-law shift (cf-6
  design 7) — not a minimal marker-only backport: the dead-run loss class (a push that
  died mid-matrix leaves the templates unre-covered by the next `before..sha` range)
  is exactly why the owner asked the adaptation; the minimal backport would heal
  nothing. Consequential: under the step-owned warning mirror, the C02 dispatch
  divergence (the all-ungated-list warning) retires — dispatch exempt wholesale, the
  upstream law; the run-log echo still names the resolved set.
- **D13 — marker ref name (OQ11, best guess): `refs/heads/ci/coder-templates-pushed`**
  — scheme-consistent (`ci/` prefix, domain + past-tense verb mirroring
  `ci/containers-built` with this pipeline's own verb), a distinct ref, named in no
  other `.forgejo` workflow (grep-measured); owner-vetoable per the cf-6 OQ-1 pattern:
  one string + one pin.
- **D14 — warning-law location (OQ12, best guess: step-owned mirror)**: retire the C03
  documented inversion (the `exempt` flag) so one law governs both workflows — the
  empty-set decision lives marker-aware in the detect step (present marker + empty
  set → one plain info line; no-op `before == sha` + empty dispatch silent; bootstrap
  empty → `::warning::`), enabling the t14-analog behavioral test shape. Alternative
  (ruled, not default): script-owned, extend the `exempt` flag with marker-verified-
  empty → info, keep the documented deviation.
- **D15 — runbook note scope (OQ13, best guess: short note, yes)**: the per-instance
  marker self-initialization note (first green push run auto-creates the marker at its
  sha; pre-init fallback = today's semantics; NO full-fleet legs — the templates are
  already live on both Coders; NO new secret — the advance rides the checkout's
  automatic same-repo credential, no `FORGE_PUSH_TOKEN`; the first live advance run
  is the proof leg for the job credential's non-main `refs/heads` push — near-
  proven, cf-6 OQ-2; fallback = a repo-write-scoped minted PAT, one-line change +
  suite re-pin) + the R2-Q5 named asymmetries (stale-queued over-push; the re-run
  re-mint law shift — user-visible on the Coder servers, the cf-6 accepted law). Not
  cf-6-style B1/B2 owner legs: those initialized containers-build history, a
  precondition we do not inherit.
- **D16 — per-instance marker state by construction**: the marker is read
  `git ls-remote origin` / written `git push origin` against the executing instance's
  own repo; `main-sync` mirrors `refs/heads/main` alone, so the marker is never
  mirrored to the other forge or to GitHub; both forges execute the push leg (the
  guard matches `dev` and `prod` alike, OQ1), each advancing its own repo's marker —
  per-instance "last pushed" state is the correct semantics, no cross-instance mirror
  needed or wanted. The dev instance receives main via the main-sync fan-out push (a
  normal push event with its own `before` payload), so `marker..sha` works identically
  there.
- **D17 — merge-order-independent-safe both ways**: the pre-marker fallback is byte-
  exact to the C02 shipped behavior on every channel (the d18 pin), so the code can
  land before any live bootstrap; each instance's first green push run
  self-initializes its marker (cf-6 design 5, "EITHER ORDER IS SAFE — proved").
- **D18 — re-run-law shift (plan Risk, stated honestly)**: a re-run of a fully
  succeeded push run answers `marker..sha` with the marker advanced ⇒ empty info-exit
  — a VERIFY, not a re-mint (user-visible on the Coder servers); failure-class re-
  runs keep the old behavior exactly (marker put ⇒ same range ⇒ same full set re-
  pushed, succeeded legs included). The cf-6 owner accepted it knowing; the OQ10
  scope question confirms it as the acceptable price for the coder-templates port.

## 2026-11-26 (r5 re-ground — C04 rework, OQ10–OQ14 re-issued)

Re-grounding round after the `01d2e3f45` merge (main r5, cf-55 C14/C15)
into this ticket branch — the r4 replan's pins (D12–D18, grounded
against `containers-build.yaml`'s r4 shape) are superseded where r5
moved the law: the push arm DIED upstream (the builder is now a
`workflow_call` called run from `main-sync`'s prod-main fan), the
advance moved to `main-sync`'s aggregate job on the SHARED
`ci/last-built` (single writer; the advance CLASSIFIES non-FF
refusals — already-advanced = skip-green, diverged = red), the detect
script re-ordered marker-first + gained the call bootstrap arm, the
empty-set warning is step-owned in the workflow (`build-containers.
yaml:210-216`, marker-aware), and the `containers-build.yaml` →
`build-containers.yaml` rename staled our artifacts' citations (the
`release.yaml` → `build-charts.yaml` rename staled the w3 suite prose
too). The 2026-11-25 OQ1–OQ9 rulings stand unchanged; the interrupted
OQ10–OQ13 round RE-ISSUES in the r5 shapes + OQ14 (the ci-surface
heal). Best-guess pins carried into the batched round (the plan's
OQ10–OQ14 table; full re-ground in the plan's C04 section +
`chunks/C04.md`, grounded on EXPLORE Round 3 L801–1386):

- **D19 — C04 shape (OQ10, best guess: STANDALONE)**: own push trigger
  + own marker ref + own plain non-FF `advance-marker` job — the
  r4/cf-6 shape, NOT a fan member. Rationale: (1) the fan runs on the
  PROD-STAGE instance only (`main-sync`'s `contains(vars.ROLE,'prod')`
  guard; the dev instance carries no marker) — fan membership would
  strand the dev Coder, a direct conflict with the OQ1 ruling
  (per-instance, both Coders); (2) the D54 poison ruling does not
  reach a single-writer per-repo ref (the poison is per-builder
  advance on a SHARED multi-owner ref); (3) the r4 plain non-FF shape
  (a queued/rewound run fails loudly) is the defensible contract for
  an own ref (no second owner to get ahead of — the r5 classify shape
  is what the shared-ref aggregate adopted); (4) the dispatch escape
  hatch stays on the push-triggered workflow. The fan-member
  alternative is honestly pinned as the isolated delta (one-leg re-pin,
  not a re-plan): the join is mechanically cheap (the D55 pre-built
  room: one `uses:` + one `needs` entry + one t16 allow-set member;
  the aggregate's target rule handles an output-less builder via the
  event-sha fallback), the dispatch hatch survives the call, and we
  mint no commits (the D53 bump-tail does not apply) — but it strands
  the dev Coder, makes the marker state single-repo (the prod repo's
  `ci/last-built`), lands into the pre-migration shared-ref state
  (`ci/last-built` NOT yet live — the first called fires would be
  bootstrap tip-only until the owner's UA-R5-1/UA-R5-2 pre-steps + the
  first aggregate green), and is a cross-ticket surface edit in our
  commit (the "one branch one concern" tension D55 names). Under the
  fan shape the script re-orders marker-first + gains the call
  bootstrap tip-only arm and the die scopes to real pushes, and the
  `advance-marker` task retires (main-sync's aggregate advances the
  shared ref).
- **D20 — marker ref name (OQ11, best guess re-pinned): `refs/heads/
  ci/coder-templates-pushed`** — free on the remote (R3-Q5b, read
  2026-11-26: exactly one `ci/` ref — `ci/containers-built` @
  `52d3b5c45` (the r4-era ref; its deletion = UA-R5-3); `ci/last-
  built` is NOT yet live — the C14 migration pre-steps are owner-
  side). Naming mirrors `ci/containers-built` (domain + past-tense
  verb) with this pipeline's own verb. Sharing `ci/last-built` (the
  fan-join room) is rejected on the R3-Q4 collision analysis: its
  single writer is main-sync's aggregate (advanced only when BOTH
  builders publish green) — a red sibling builder would hold OUR
  range, coupling our push timing to an unrelated domain's build
  health; our consumer is path-filtered (`charts/coder/coder-templates/`)
  and instance-paired (per-instance ref state), not the shared-base
  model. The upstream t16 fence cannot catch our ref either way
  (token-scoped to the `ci/last-built` literal) — the decoupling, not
  the fence, is the point. Owner-vetoable per the cf-6 OQ-1 pattern:
  one string + one pin.
- **D21 — warning-law location (OQ12, best guess re-pinned: step-
  owned)**: the r5 upstream empty-set warning lives in the workflow
  step (`build-containers.yaml:210-216`, marker-aware) — the C03
  documented inversion (the script's `exempt` flag + stderr warning)
  retires; the script keeps only its two tip-only announces; the all-
  ungated-dispatch-list warning retires with it (dispatch exempt
  wholesale, the upstream law — the OQ10 scope consequence). Enables
  the t14-analog behavioral test shape (six shapes — the upstream nine
  minus the PR and workflow_call shapes by the OQ2 ruling + our
  standalone shape). Alternative (ruled, not default): script-owned —
  extend the `exempt` flag with the marker-verified-empty → info case,
  keep the documented deviation.
- **D22 — runbook note scope (OQ13, best guess: short note, yes, + the
  UA3 re-verification)**: the per-instance marker self-initialization
  note (short, NON-leg — no full-fleet legs, the templates are already
  live; no new secret — the advance rides the checkout's same-repo
  credential; the first live advance run is the proof leg for the job
  credential's non-main `refs/heads` push) + the NAMED ASYMMETRIES
  reworded to the r5 runner topology (10 poller pods × capacity-1 +
  FIFO + `cancel-in-progress: false`, D57 — the race remains vanishing
  by per-pod serialization; the plan/chunk "capacity-1 runner"
  phrasing rewords with it) + the UA3 pin facts RE-VERIFIED post-
  merge (R3-Q5c: the four act-24.04-family label lines in
  `charts/forgejo-runner/values.yaml:149-153` still pin `:26.11.1`;
  the act-22.04 ghcr line unchanged; the dev slice's five-entry label
  list `services/dev/prod/values.yaml:201-205` incl. its bootstrap
  `:26.11.1` copy intact; the B1 comment exists AMENDED, not deleted
  — the runbook's "the chart's own comment" pointer still resolves;
  the C01 post-merge regression 9 ok GREEN, the bake byte-intact).
- **D23 — the ci-surface suite heal (OQ14, best guess: FJ_SET re-aim
  + the t8 expect-list, upstream-suite legs byte-identical otherwise)**:
  `tests/services/forgejo-ci-surface.sh` is RED on this branch for two
  reasons (t1: FJ_SET is the five-workflow family — our workflow is a
  sixth member; t8: the containers-era bare-token sweep catches the 6
  bare lines (workflow L9/L25, suite L113/L115/L121/L187) + the 4
  release-era lines (workflow L11/L188, suite L158/L165)). The heal =
  FJ_SET re-aimed to the six-workflow family (naming
  `coder-template-push.yaml`) + the t1 comment/FAIL-message/ok-line
  reword (five → six); t8 stays BYTE-IDENTICAL — its teeth are a
  token sweep over every tracked live surface (no per-file expect-
  list), so its red state resolves from our side's 20-line re-fence in
  the SAME commit set (the D50.3 pairing law: "docs + suite move in
  ONE commit set"); no other leg (t2–t7, WIDEN_OK) touched (our
  workflow's guard is narrow-on-unset — WIDEN_OK stays
  `build-containers.yaml` alone; our file is outside the t3/t4 routes).
  Suite bytes owned by the test session; dev never edits tests.
- **D24 — the full stale-ref sweep folds into C04 (20 lines, one
  change set)**: the `containers-build.yaml` mentions in our artifacts
  now name a file that no longer exists (the r5 rename) and the
  release-era `release.yaml` mentions predate the `build-charts.yaml`
  rename: the workflow 7 lines (L9, L11, L25, L102, L119, L180, L188),
  the w-suite 7 lines (L113, L115, L121, L158, L165, L187, L337), the
  runbook 6 lines (L47, L50, L67, L81, L166, L276) — re-fenced to
  `build-containers.yaml`/`build-charts.yaml` in the same commit set as
  the suite heal (D23) so the cross-ticket suite goes green on this
  branch; the prose-form lines (no bare `.yaml` token — workflow L102/
  L119/L180, suite L337) pass the t8 sweep but are still stale and
  move with the x5-parity reword. The plan/chunk/STATE/DECISIONS/
  EXPLORE-r1-r2 mentions are historical record — no in-place fix (the
  plan's live blocks re-fence with this re-grounding; EXPLORE round 3
  corrects the round-2 pins).
