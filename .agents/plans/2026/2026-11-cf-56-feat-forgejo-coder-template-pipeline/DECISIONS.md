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
