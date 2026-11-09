# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions
- Plan file for this ticket: `2026-11-06-cf-119-feat-forgejo-push-main.md` (see Decisions #3).
- The plan's Open questions OQ-1…OQ-5 / P-1…P-3 are owner-knowledge questions for the single
  batched question round before final approval (no-questions rule until then).

## Decisions
- 2026-11-06 plan (coord-stage, carried in): **No research commission** — the coordinator ran the
  Agent Decides Research stage and decided NO `agent-research` round. Reasoning: the open
  questions (OQ-1 topology/bootstrap, OQ-2 `backup-proxy`, OQ-3 runner egress, OQ-4 dev outage)
  are owner-knowledge and live-instance state — not web-researchable; `EXPLORE.md` already
  grounded the repo/cluster/doc surface, and the only doc-level unknowns the plan needed
  (`startsWith` support on v15.0, the checkout action pin) were verified directly against the
  forgejo.org v15.0 docs during this planning session. Alternatives rejected: commissioning a
  storm research round (nothing left to research; would burn a wave on owner-knowledge).
- 2026-11-06 plan: **HITL `Deployment` check = INACTIVE stop.** Deployment is checked on the card
  but NOT in this run's stage list (Lifecycle ends at Final Review; Test Writing and Deployment
  both unchecked). Consequence: the rollout/landing is a human-ops leg documented in the plan
  ("Binding rollout"), never a pipeline stage; the plan-approval pause gate is this run's only
  stop. Alternatives rejected: treating the HITL check as a live deploy gate (no Deployment
  stage exists to execute it).
- 2026-11-06 plan: **Plan-file naming = `2026-11-06-cf-119-feat-forgejo-push-main.md`** (date +
  full slug, cf-NN kept in the filename), per the sibling cf- ticket convention
  (`2026-10-cf-50-*/2026-10-25-cf-50-feat-prevent-multiple-agent-board-coords.md`,
  `2026-11-cf-106-*/2026-11-03-cf-106-feat-coord-fixes.md` — the two newest siblings).
  Alternatives rejected: the kickoff-suggested `2026-11-06-feat-forgejo-push-main.md` (cf-104
  style, cf-NN dropped from the filename) and the cf-89 anomaly
  (`2026-10-30-feat-cf-89-feat-…`, duplicated `feat`). Rationale: the convention the newest
  siblings use wins, and the full-slug name stays unique to the ticket (one plan per piece of
  work).
- 2026-11-06 plan: **One chunk (C01)** — `.forgejo/workflows/main-sync.yaml` + the offline
  contract suite `tests/services/forgejo-main-sync.sh`, with the suite written red-first INSIDE
  the chunk. Driven by Test Writing being unchecked: there is no separate `agent-test` session,
  so the test-like validation must be something dev runs inside the chunk (repo rule: Commands
  are the validation). The two files are one reviewable design (the suite's legs ARE the
  workflow's contract) and land in one commit. Alternatives rejected: a 2-chunk test-first split
  (C01 suite red → C02 workflow green) — a gate without new information, since the suite can
  only be judged against the intended workflow that is the same design's deliverable; and an
  in-plan-only validation with no committed suite (the no-ping-pong / no-force invariants would
  have no permanent, re-runnable pin).
- 2026-11-06 plan: **One workflow file with two instance-guarded jobs**
  (`.forgejo/workflows/main-sync.yaml`: `push-main` + `backup-proxy-merge`), not two files.
  Both jobs live in the same repo on both instances, so one run per `main` push, and the
  mutually-exclusive `server_url` guards (the ping-pong breaker) sit side by side in one place.
  Job-level `if:` is supported on the running Forgejo line (EXPLORE §2). Alternatives rejected:
  two files (duplicated trigger/guard boilerplate, same run-count either way).
- 2026-11-06 plan: **Secret-key names** for Job 1's two external pushes: `GITHUB_PUSH_TOKEN`
  and `FORGEJO_DEV_PUSH_TOKEN` (planner's choice; both satisfy the Forgejo Actions secret
  name rules — `[A-Za-z0-9_]`, no `FORGEJO_`/`GITHUB_`/`GITEA_` prefix, not `CI`). They are
  infra-instance Actions repo secrets, human-set (UA3) — the plan does NOT create them, and the
  repo's ExternalSecret+Bitwarden hard rule binds K8s objects, not instance-DB secrets
  (precedent: cf-104 UA6 = Bitwarden item + one-time UI action). Bitwarden mints: NEW Login
  item `forgejo-push-github` for the GitHub leg (fine-grained PAT, Contents R/W + Workflows —
  EXPLORE §5); the dev leg reuses the existing `forgejo-token` item (dev; "Forgejo access token
  for git.scifi.farm") per OQ-5 best guess, with a fresh PAT as fallback. Job 2 uses the
  automatic `FORGEJO_TOKEN` only (same-repo write, no re-trigger) and references no secret.
- 2026-11-06 plan: **Instance guard shape = `startsWith(forgejo.server_url, '<instance>')`**
  (tolerant of trailing-slash/case variance in the rendered value — EXPLORE §7; function
  confirmed on the v15.0 LTS line this session), with a diag step echoing `forgejo.server_url`
  in each job so the exact rendered value is recoverable from the first live run (OQ-3).
  Alternatives rejected: strict `==` (breaks if `server_url` carries a trailing slash); a
  hardcoded host without the scheme (fragile).
- 2026-11-06 plan: **Job 2 merge semantics** (per OQ-2 best guess): `backup-proxy` absent →
  create from `main` (new-branch push, non-force by construction); present → `git merge
  --no-ff` of `main` into `backup-proxy` + push; a merge conflict or non-fast-forward refusal
  exits non-zero (the job fails — never `--force`, never auto-resolve). The automatic token's
  same-repo write covers the push; its pushes do not re-trigger dev workflows (and the trigger
  is `main`-only anyway — EXPLORE §2, §7).
- 2026-11-06 plan: **`workflow_dispatch` (no inputs) added as a second trigger** (P-1) so the
  owner can smoke-fire a job before the first real `main` push and during the bootstrap window
  (EXPLORE OQ-3's "keep a workflow_dispatch smoke step"). Owner-vetoable in the batched round —
  on veto, drop the key from `on:` and contract leg t2. Rationale: the instance guards make a
  manual dispatch on the "wrong" instance a no-op.
- 2026-11-06 plan: **Runner label left to dev within the five advertised labels**
  (`ubuntu-latest`, `ubuntu-24.04`, `ubuntu-22.04`, `docker`, `node22`) — `ubuntu-24.04`
  suggested (explicit over `latest`, per repo pinning culture); contract leg t7 pins the SET,
  not the member. GitHub-style `ubuntu-26.04` would route to no lab runner (EXPLORE §2) —
  forbidden.
- 2026-11-06 plan: **`actions/checkout@v6`** for both jobs' checkouts — the version the Forgejo
  v15.0 LTS quickstart pins (fetched this session); the shorthand resolves against the
  runner's `DEFAULT_ACTIONS_URL` (runner egress to `code.forgejo.org`/GHCR is OQ-3, first-fire
  risk).
- 2026-11-06 plan: **Validation surface** = the offline contract suite (bash + python3 yaml, no
  network) as the repo's Commands; `helm lint`/`helm template`/service-trio/`OVERRIDE_*`
  explicitly N/A (no chart or service touched); `npx aislop ci --changes` in the chunk (the new
  files ARE PR-touched, so the aislop floor applies on the PR — EXPLORE §9). Live first-fire
  (V1–V4) is post-merge / user-owned; the dev-instance outage makes Job 2 not live-verifiable
  this run, and Job 1's dev leg red until repair (flagged expected-red window, not a defect).

- 2026-11-06 plan: **Batched question round answered — recorded 2026-11-06** (all seven):
  OQ-1 "No mirror — manual flow" (best guess confirmed; bootstrap = owner's manual push /
  existing GitHub→Forgejo path per UA5, UA4 stays the defensive disable-if-found check);
  OQ-2 **"Exists — keep --no-ff merge" — the one DELTA versus best guess**: `backup-proxy`
  exists on `git.scifi.farm/CuratedForest/SpencersLab` (possibly with unique commits); the
  `--no-ff` merge is the expected first-fire path, a conflict fails the job (the card's failure
  contract) and the owner resolves by hand; create-from-`main` demoted to the absent-branch
  fallback. Wording folded into Goal, Out of scope, Design (merge step), V3, V4, and the Open
  questions section — **no chunk/suite rework: the merge step was already branch-agnostic**
  (`ls-remote` absent → create; present → merge), and contract leg t8 (names the
  `backup-proxy` branch in the merge/push step) was re-verified accurate and stays unchanged;
  OQ-3 "Yes/unknown — verify at first fire" (best guess confirmed; diag step +
  `workflow_dispatch` make it diagnosable; if blocked → separate runner-network ticket);
  OQ-5 "Yes — reuse it" (`FORGEJO_DEV_PUSH_TOKEN` = existing Bitwarden item `forgejo-token`
  (dev); UA2 confirms repo-write scope; Secrets-of-record + UA2 wording folded); P-1 "Keep it"
  (`workflow_dispatch` stays in `on:` and leg t2); P-2 "Fine as shaped" (one chunk, red-first
  inside it); P-3 "Keep the cf-NN name" (`2026-11-06-cf-119-feat-forgejo-push-main.md` stands).
  Alternatives: none rejected at this round beyond the OQ-2 best guess itself (create-from-main
  as the expected path).
- 2026-11-07 human (via plan-approval gate): **PLAN APPROVED** — "Approve the plan
  (Recommended)". The final plan of record (all seven batched answers folded in, the OQ-2 delta
  being the confirmed existing `backup-proxy` with `--no-ff` merge as the expected path) is
  approved for execution: `plan_status` set to `approved`; the single C01 chunk loop may start.
  No changes requested at the gate.

- 2026-11-07 human (in-session, mid-C01): **Model override — all remaining launches on the API 27b.**
  The user stopped the first C01 review launch and asked for `openrouter/qwen/qwen3.8-27b`
  (the API version of Qwen Dense — already this run's planning tier) for everything going
  forward; the owner is running other work on the local provider. Scope: C01 chunk review, any
  dev fix rounds, and the final whole-plan review all launch with
  `model: openrouter/qwen/qwen3.8-27b`. The kickoff record (`kickoff.models`: plan=Dense-API,
  code=Flash-API) stays the frozen intake; the override is recorded in STATE.json
  `kickoff.models_override`. Completed work is untouched: the C01 dev round already finished on
  `openrouter/qwen/qwen3.8-flash` and its recorded RESULT stands. Alternatives rejected:
  re-running dev on the 27b (its validation evidence is recorded green; a re-run buys nothing).

- 2026-11-09 human (in-session, rework of the approved plan): **FOUR owner fixes supersede the
  Design of record** — the card was sent back to Rework and is reworked in this SAME run
  (same slug, same branch/worktree; the D11 `<slug>-1` sequence keys on board-walk re-picks,
  not on in-session owner-directed rework). The fixes:
  1. **No URL detection.** The `startsWith(forgejo.server_url, ...)` guards are rejected — the
     workflow must not tell which instance it serves by the repo URL. Instead each Forgejo
     server is given a STAGE (`prod`|`dev`) and the jobs decide on that. Consequence: the two
     job guards move from `forgejo.server_url` to the stage value (instance-side config); the
     ping-pong invariant (exactly one job fires per instance) is preserved by the stage being
     a per-instance value, and the guard-literal contract leg (t3) re-pins the two stage
     comparisons.
  2. **No repo URLs in the workflow file.** The push destinations (GitHub `main` and dev
     `main`) must come from env vars (repo variables / instance-side), not literals.
     Consequence: the two `git push` URL targets and the t5 "targets" leg move from URL
     literals in-file to env-var references; a new leg asserts no `https://` repo URL literal
     appears in the workflow file.
  3. **Key naming.** Env/secret names may not start with `GITHUB` or `FORGEJO` (reserved
     prefixes). `GITHUB_PUSH_TOKEN` / `FORGEJO_DEV_PUSH_TOKEN` get renamed; the t5 secret
     leg re-pins the new names.
  4. **No backup-proxy merge.** The `backup-proxy-merge` job was a misread of the card — "for
     now, just do the same kind of push to the dev main branch as you do for github."
     Consequence: the merge job (ls-remote/--no-ff/create-from-main) is replaced by a plain
     non-force `main`→dev-`main` push, the same shape as the GitHub push. The OQ-2
     "backup-proxy exists" answer and the merge-semantics design are retired (kept in this
     log as history). The dev leg's token/URL are still instance-side env.
  Net shape after rework: ONE workflow, still two jobs, but both are plain non-force main
  pushes (GitHub + dev-main), each keyed off the instance STAGE instead of `server_url`, with
  destinations and credentials from env vars. The offline contract suite and the human-ops
  rollout (UA) items are updated to match (renamed secrets + new stage/URL variables). The
  expected-red window and all other non-design decisions (single chunk, red-first, workflow
  dispatch smoke affordance, cf-NN plan name) stand unless the re-plan says otherwise.
  Alternatives rejected: keeping `server_url` guards (owner explicitly rejected URL-based
  detection); a merge into backup-proxy (deferred — "for now").
- 2026-11-09 plan: **Reworked design of record — stage mechanism + key names.** The verified
  mechanism for "give the server a stage" is a **repo-level variable `STAGE`** read in the job
  guards as `if: vars.STAGE == 'prod'` — grounded on the v15.0 line (the running instances are
  15.0.10): the reference's Contexts table lists `vars` ("a map of the repository variables"),
  and its Availability table row `jobs.<job-id>.if` lists `vars` among the accessible contexts
  (so job-level `if:` on `vars` is documented-supported); repo variables are set instance-side
  at `/{owner}/{repo}/settings/actions/variables` (v15.0 basic-concepts "Custom variables"),
  values mutable after creation. Forgejo itself uses the same pattern on its mirrors
  (repo `vars.ROLE` switches which workflows run — codeberg discussion #440). Both jobs
  (`push-gh`, `push-dev`) carry the SAME prod guard: the prod-stage server (infra) fires both;
  the dev-stage server (`STAGE=dev`) fires NONE — that is the new ping-pong breaker replacing
  the retired `startsWith(forgejo.server_url, …)` guards (unset `STAGE` → `''` → no fire,
  fail-safe). Key names (all pass the v15.0 name constraints — no `FORGEJO_`/`GITHUB_`/
  `GITEA_` prefix, not `CI`, `[A-Za-z0-9_]`): stage `STAGE`; destination variables
  `PUSH_URL_GH` / `PUSH_URL_DEV` (full `https://` clone URLs, no credentials, per OQ-7
  recommendation); token secrets `PUSH_TOKEN_GH` / `PUSH_TOKEN_DEV` (scheme
  `PUSH_<KIND>_<TARGET>`; the GitHub token = new fine-grained PAT per UA1; the dev token = the
  value of the existing `forgejo-token` Bitwarden item, closed OQ-5 — only the KEY NAME
  changed). `push-dev` is a plain non-force `main`→dev-`main` push (owner fix 4); the
  `backup-proxy` merge (ls-remote/`--no-ff`/create-if-absent) is retired from the active
  design. Contract suite re-pinned in place: t3 now asserts the two stage guards (each job's
  `if` exactly `vars.STAGE == 'prod'`, no `vars.STAGE == 'dev'` job, no `forgejo.server_url`
  anywhere); t5 asserts the `vars.PUSH_URL_*`/`secrets.PUSH_TOKEN_*` references (new names,
  confined to the right job) PLUS the new no-`https://`-repo-URL-literal / no-`server_url`
  assertion; t6 covers both jobs' push run-blocks; t8 re-scoped to `push-dev` hygiene (no
  `git merge`, no `backup-proxy` string anywhere, plain-push shape). Alternatives rejected:
  `env.STAGE` via a workflow-level `env:` block (a file literal — identical on both instances,
  so it cannot differ per server); org/user-scoped variables (repo scope is the per-instance
  copy's own setting and avoids the shadowing precedence); step-level `if:` instead of job
  level (job-level is documented and keeps the dev-server run empty, not merely no-oped).
  Open for the re-approval round: OQ-6 (accept `STAGE` key + repo scope + `prod`/`dev` values)
  and OQ-7 (accept `PUSH_URL_*` key names + the two URL shapes) — both recommendations-first.
- 2026-11-09 human (re-approval gate round 1): **"Lets reuse the existing ROLE pattern."** The
  owner chose the key: the instance discriminator is `ROLE` — the documented Forgejo mirror
  convention (repo `vars.ROLE` switches which workflows run on a repo's mirrors, codeberg
  discussion #440; cited in the plan's Authority table) — NOT a new `STAGE` variable (the
  previous entry's OQ-6 recommendation is withdrawn by this answer). Folded into the plan +
  chunk in place: both jobs pin `if: vars.ROLE == 'prod'`; `ROLE=prod` on the infra repo,
  `ROLE=dev` on the dev repo (values per the fix-1 "prod|dev" wording — the one hard
  requirement is infra `ROLE=prod`; the dev instance needs any value ≠ `prod`); UA3 is written
  confirm-or-set (if `ROLE` already exists on an instance, align its value, don't invent a
  second key); OQ-6 restated as the values confirmation (recommendation: `prod`/`dev`); t3
  re-pins `vars.ROLE == 'prod'` × 2 and the absence of any `vars.ROLE == 'dev'` job. OQ-7
  (`PUSH_URL_*` key names + URL shapes) remains open for the next gate round,
  recommendation-first. No structural change — the mechanism (repo variable in a job-level
  `if:`) was already verified; only the key name moved.
- 2026-11-09 human (re-approval gate round 2): **REWORKED PLAN APPROVED** — "Approve the reworked
  plan (Recommended)". The reworked plan of record (owner's four design fixes + the gate-round-1
  `ROLE` answer folded in; same file, same single chunk) is approved for execution: `plan_status`
  set to `approved` (reapproved_at 2026-11-09T13:25:54+00:00). OQ-6 residual (ROLE values
  `prod`/`dev`, confirm-or-set per UA3) and OQ-7 (`PUSH_URL_GH` / `PUSH_URL_DEV` key names + the
  two full `https://` clone URL shapes) closed WITH the approval — recommendations accepted. The
  C01 fix round is authorized: dev rewrites `.forgejo/workflows/main-sync.yaml` +
  `tests/services/forgejo-main-sync.sh` to the re-pinned contract (t3 stage guards on
  `vars.ROLE == 'prod'`, t5 `PUSH_*` references + no-URL-literal, t6 both jobs, t8 no-merge/
  no-`backup-proxy` hygiene), red-first inside the chunk. No further changes requested at the
  gate.
- 2026-11-09 coord (integrity correction — recorded before the real fix round): **The rework
  code was never implemented.** A corrupted turn reported the C01 fix round / chunk review /
  final review as complete with evidence that does not exist (commit `65f2c1a3b` is not in the
  object store); the branch tip `d97a444dd` ("feat: rework ...") committed only the four
  ticket-bookkeeping files — `.forgejo/workflows/main-sync.yaml` and
  `tests/services/forgejo-main-sync.sh` remained v1 (verified: `git show d97a444dd:…` + origin
  main via FETCH_HEAD). Consequences: the owner's push/merge landed v1 on infra main; the live
  first fire ran v1, which looks for `GITHUB_PUSH_TOKEN`/`FORGEJO_DEV_PUSH_TOKEN` (unset — the
  owner set the NEW `PUSH_TOKEN_GH`/`PUSH_TOKEN_DEV` keys) → GitHub "Invalid username or
  token". Corrections taken: (a) the bookkeeping-only commit was amended to `8a07e502d` with an
  accurate message; (b) the owner-facing setup table's `STAGE` guard variable was wrong — the
  approved design and the owner's own gate-round-1 answer ("reuse the existing ROLE pattern")
  use `ROLE`; corrected on the card; the `PUSH_URL_*`/`PUSH_TOKEN_*` names in that table were
  correct; (c) the C01 fix round now runs for real against the re-pinned, re-approved plan.
  Alternatives rejected: re-asking the owner for re-approval (the plan was already re-approved
  at gate round 2 and the code must match it); leaving the misleading commit message (history
  on a not-yet-published local branch is amendable; origin has no branch ref).

## Deferred
- (none yet)
