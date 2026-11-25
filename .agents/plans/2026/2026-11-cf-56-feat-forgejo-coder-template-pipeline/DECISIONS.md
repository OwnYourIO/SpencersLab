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
