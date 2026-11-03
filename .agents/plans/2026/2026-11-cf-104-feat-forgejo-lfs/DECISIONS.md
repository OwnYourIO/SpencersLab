# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions
- The plan of record is `2026-11-03-feat-forgejo-lfs.md`; RESEARCH.md is the
  technical authority over the card body's Oct-2026 briefing.
- Card #104 carries the legacy **Research** checklist (no Lifecycle checklist),
  so the stage list is the standard default loop and the checked
  `Before Planning` item is consumed as timing only.
- Repo validation = renders/sweeps/greps (`AGENTS.md`), never a unit suite; the
  LFS contract is `tests/services/forgejo-lfs.sh`.
- Everything needing a pod shell, the vault, the gateway IAM store, ArgoCD sync
  or git landing is a labelled **User action** in the plan — never a chunk.

## Decisions
- 2026-11-03 plan: follow RESEARCH §Q1/§What-this-changes 2 — **every** LFS key
  inside `[lfs]`, no `[storage]` section anywhere. Rejected: the pinned chart's
  `docs/ha-setup.md` split shape (`lfs.STORAGE_TYPE` + credentials under
  `[storage]`), which Forgejo 15.0.10's `getStorage` precedence does not
  support (C1) and which would also move attachments/avatars/packages/actions to
  S3.
- 2026-11-03 plan: purpose-built bucket **`git-lfs`**, not the idle
  `/buckets/git` collection. Rejected reuse because bucket-scoped IAM could only
  be as narrow as `git` and the 1 TiB RWX PV would then be able to read and
  overwrite every LFS object (RESEARCH §Q3).
- 2026-11-03 plan: the **activation switch stays per-instance**
  (`[lfs] STORAGE_TYPE=minio` + `server.LFS_START_SERVER=true` in
  `custom-values/<c>`), while the chart ships only the inert shape keys
  (`MINIO_BUCKET`, `MINIO_BUCKET_LOOKUP`, `MINIO_CHECKSUM_ALGORITHM`,
  `SERVE_DIRECT`). Rejected: chart-level activation, which would turn LFS on for
  every cluster deploying the chart at once with no safe default for a cluster
  that has no bucket.
- 2026-11-03 plan: endpoints split per instance — dev
  `s3.spencerslab.com` + `MINIO_USE_SSL=true`, infra
  `seaweedfs-s3.default.svc.cluster.local:8333` + `MINIO_USE_SSL=false`.
  Rejected: one shared endpoint (infra would hairpin through its own Traefik;
  dev has no local gateway). Bare host is safe for 443 — verified in minio-go
  v7.0.99 (`utils.go:109-128`, `api.go:1048-1052`), closing RESEARCH OQ4.
- 2026-11-03 plan: `MINIO_BUCKET` always set explicitly (code default is
  `gitea`, C2); `MINIO_BUCKET_LOOKUP=path` explicit even though `auto` already
  resolves path-style for a non-AWS endpoint (removes the heuristic);
  `MINIO_CHECKSUM_ALGORITHM=md5` for per-request `Content-MD5`, explicitly not
  as a #12177 mitigation.
- 2026-11-03 plan: **no `LFS_JWT_SECRET` work** — the subchart generated it at
  first boot and `config_environment.sh` drops those four secret envs once
  `app.ini` exists, so an override would be silently ignored.
- 2026-11-03 plan: no SeaweedFS version change (stay 4.50.0/4.50); #12177 is
  unreachable from Forgejo's minio-go client (no `TrailingHeaders`) and the
  server gate never runs. Rejected: the downgrade-to-4.46 idea (a shared storage
  system Loki writes to is a bigger risk than the bug it avoids).
- 2026-11-03 plan: do not touch `s3.enableAuth`/`-s3.config` in
  `charts/seaweedfs`. Auth is already enforced by the filer-backed store; the
  chart flag would auto-generate a fresh credential set and break Loki first
  (C4). A blast-radius test leg (t11) pins the file untouched.
- 2026-11-03 plan: credentials ride a **real UUID from the first commit** —
  `OVERRIDE_NEEDED` is forbidden for `bitwardenIds.forgejo-s3` (plan D11),
  a deliberate exception to the repo's interim-placeholder precedent, because
  the credential `secretKeyRef` sits on the init container: an unresolved
  ExternalSecret means the forgejo pods cannot start at all.
- 2026-11-03 plan: chunk shape = C01 (chart plumbing, inert) → C02 (dev) →
  C03 (infra), three waves, so the rollout order RESEARCH requires (bucket →
  identity → pre-flight → config, dev first) is expressible in commits and C03
  is independently revertable.
- 2026-11-03 plan: test suite name `tests/services/forgejo-lfs.sh`, one script,
  11 numbered legs, sentinel baselines pinned from measurement (dev umbrella
  render = 1 pre-existing home-assistant hit, infra = 0) rather than assumed 0.

## Deferred
- The nine plan questions (plan file "Open questions", Q1–Q9) — one batched
  round, answers return to a re-launched plan session before approval.
  · status 2026-11-03: answered; folded into the round-2 plan (see below).
- If Q5 wants the `git` PV's `002` placement: 4.50 has no per-bucket replication
  command, so that becomes a shared-infra placement change outside this ticket.
  · status 2026-11-03: Q5 accepted the `001` default — stays out of this ticket.
- Post-merge live verification (V1–V4) sits with the user/deploy surface, not
  these chunks — the pipeline stops at local commits.

## Round-2 rework decisions (2026-11-03 plan, after the batched answer round)
- 2026-11-03 plan: **Q6 override adopted — `MINIO_CHECKSUM_ALGORITHM: default`**
  (user overrode the plan's md5 recommendation). User's rationale, recorded
  verbatim in intent: no #12177 mitigation is needed because Forgejo's minio-go
  code path never sets `TrailingHeaders` (RESEARCH §Q2), so per-object
  `Content-MD5` buys nothing against that bug. Verified the literal: at
  v15.0.10 (`modules/storage/minio.go:87-88`) only `""`/`default`/`md5` pass
  validation and `SendContentMd5` is set only for `md5` (`:218-219`) — `default`
  equals the unset behaviour, made explicit. Pre-flight flags omit
  `--minio-checksum-algorithm` entirely (D16).
- 2026-11-03 plan: **Q9 override adopted — owner grant with self-healing
  MakeBucket** (replaces round-1 D7 least-privilege `Read,Write(,List)`).
  Sequence per 4.50 grammar: `s3.user.create -name forgejo-lfs` →
  `s3.bucket.create -name git-lfs -owner forgejo-lfs` → `s3.bucket.access
  -name git-lfs -user forgejo-lfs -access Read,Write,List,Admin`.
  Reconciliation with RESEARCH's boot-fatal analysis: MakeBucket is the
  PutBucket route, 4.50 gates that route on `Admin` (`s3api_server.go:1204`),
  and `CanDo` matches a stored bucket-scoped `Admin:git-lfs` for **any** action
  on that bucket (`auth_credentials.go:2099-2165`) — so the self-heal works
  without gateway-wide Admin. This **removes the "missing bucket ⇒
  `log.Fatal`, whole instance down" failure mode** (Forgejo recreates the
  bucket at boot); the `Read`-at-boot and unreachable-endpoint fatal modes
  stay. Costs: on `git-lfs` the identity is effectively full-control (incl.
  DeleteBucket and bucket subresources), and a deleted bucket returns **empty**
  — silent object loss instead of a loud boot failure (risk recorded in the
  plan).
- 2026-11-03 plan: **`s3.user.provision -role readwrite` stays the rejected
  alternative** — its attached-policy shape routes via
  `authorizeViaAttachedPolicies` and its coverage of the PutBucket route is
  unverified; the explicit `s3.bucket.access` grants deterministically use the
  legacy-actions route (Authority table, verified at tag 4.50 this round).
- 2026-11-03 plan: **Q1 answer consumed as runner scope, with the live-fleet
  conflict recorded, not papered over**: the runner exists exactly once, on dev
  (EXPLORE §R1), the gpu cluster has no Forgejo and no runner; the plan adds
  the record-only runner chunk C04 (dev surface) and raises "new gpu runner
  instance vs runner-chart surface" as Q10 at the approval pause —
  recommendation: no new instance this ticket (it costs a full trio + vault
  item + suite and adds no LFS work, since LFS-capable jobs need only the
  server-side activation + the git-lfs-bearing act job images).
- 2026-11-03 plan: **C04 is comment+test only** — no job-image/label/pin
  change (`ACT_LABELS` untouched), the `node22` git-lfs gap is documented not
  fixed (Q12), the runner daemon image needs no git-lfs (§R2a), and the
  in-job checkout-auth questions (R6) are gated behind a research round (Q11)
  before any behavioural runner work. Runner-suite leg t14 is placed **before
  the pinned-red t5** because the suite stops at its first failing leg — an
  appended leg would never execute.
- 2026-11-03 plan: test strategy per the user's answer — **extend
  `tests/services/dev-forgejo-runner.sh`** (one leg) rather than invent a new
  runner suite, and carry all pinned pre-existing red baselines (runner exit
  1 / 27 ok; ssh-gateway exit 1 / 63 ok; audit-trail exit 1 / 0 ok) into the
  Commands so no dev/review session chases them; the `forgejo-ssh-gateway.sh:
  1601` runner-rerun coupling and the `dev-wiring.sh:252-253` comment-citation
  leg are named landmines — neither file is touched by this ticket.

## Approval-round scope deltas (2026-11-03 coord-relay, user answers — the human chose these, not the planner)
- 2026-11-03 coord-relay (user answer): **plan Q10 → a NEW runner INSTANCE on
  the gpu cluster**, explicitly not "the dev-resident runner chart only".
  Rejected at the pause: the plan's round-2 recommendation (surface-only, no
  new instance). Consequence: new chunk **C05** — `charts:` alias + top-level
  `forgejo-runner-gpu:` HTTPS URL slice in `services/gpu/prod/values.yaml`,
  UUID in `custom-values/gpu/prod-values.yaml`, new `tests/services/gpu-forgejo-
  runner.sh`; the trio's proxy leg is N/A (dial-out-only service, exemption
  comment mirrors the dev precedent `services/dev/prod/values.yaml:96-101`);
  the server-side runner record + vault pair stay **User actions** (UA5/UA6).
  The target instance has no live ground (no gpu Forgejo) → Q13, best guess
  dev (`https://git.scifi.farm`, D17) because Q8 activates dev first.
- 2026-11-03 coord-relay (user answer): **plan Q12 → swap the `node22` job
  image now** (the only label whose image lacks git-lfs). Rejected at the
  pause: the plan's round-2 recommendation (document, don't change).
  Consequence: C04 became a **functional** change —
  `node22:docker://ghcr.io/catthehacker/ubuntu:act-24.04` (plan D18: tag +
  digests re-verified at the registry this round; act-24.04 = index
  `sha256:62d572b9…`, same amd64 manifest `sha256:dff4ec57…` §R2 probed, tag
  unmoved). Couplings honoured: agent-test edits `ACT_LABELS` red-first (the
  runner suite's stop moves t5→t2 until C04 lands — a designed transitional
  state, baselines recorded), t14 stays before t5, the ssh-gateway t11 rerun
  and the dev-wiring comment citation stay pinned. Honest caveat carried to
  Q14: `act-24.04` ships Node **20/24** (`docker_images` `Dockerfile:14`
  `ARG NODE_VERSION="20 24"`, source-verified), so the label name outlives
  its Node-22 promise; job images remain renovate-untracked (manual bumps).
- 2026-11-03 coord-relay (user answer): **plan Q11 → no research round** —
  in-job Actions checkout/LFS behaviour stays unproven by decision; runner
  chunks stay record/labels/instance-level; V5/V6/V7 are the only live probes.
- 2026-11-03 plan (r3, grounded this round): gpu sentinel baseline pinned at
  **1** (measured umbrella render: legacy `OVERRIDE_VIA_CLUSTER_ANNOTATION`
  trio on one values-JSON line) and `tests/multi-repo/dev-wiring.sh` baseline
  pinned at **exit 0 / 9 ok** — both measured, not assumed.
- 2026-11-03 coord (measured during C01): **the plan's Commands carry three
  numeric defects**, corrected in STATE.json `measured_baselines` rather than by
  editing an approved plan: infra's sentinel baseline is **1** not 0 (the plan
  measured an in-place `services/infra/prod` render where helm aborts on
  unvendored deps and the grep saw an empty stream), C04's runner-suite target
  is exit 1 / **34** ok not 28, and C01 AC7's "t7 green" is unreachable in a
  C01-only run (the suite exits at t5). Rejected: leaving the numbers only in a
  card comment — every later session reads STATE.json first. Fix the plan file
  at the next plan pass.
- 2026-11-03 coord: **chart-sentinel changes must update the suites that
  enumerate ids** — C01's fifth `bitwardenIds` key silently broke
  `forgejo-ssh-gateway.sh` t6 (hard-coded four-id `--set` render) and
  `infra-forgejo.sh:587` (exact four-key set). Both repaired by the test author
  (mechanical, routed back per the gates, no functionality change). Rejected:
  letting dev touch test files. Accepted as a follow-up card for a repo-wide
  guard.

## Coord decisions (2026-11-03, board run — run ended at the approval pause)
- 2026-11-03 coord: **model routing for a `Provider: Local` card** — the Model(s)
  checklist is read as `Local`-checked on top of its own checks, so `Qwen Flash`
  plus the implied `Local` resolves through the `pipeline-models` combination
  rule to `gpu-ai/qwen3.8-flash-next-strata` for planning AND code. Rejected:
  routing from the checklist alone (openrouter tiers) — the Provider rule overrides it.
- 2026-11-03 coord: legacy checklists consumed per the boards transition rule —
  **Research** `Before Planning` is timing only, so the stage list stays the
  standard default loop; **Human in the Loop** `PR` maps to the `Deployment` stop
  point, and since `Deployment` is opt-in and absent from this run's stage list
  that stop collapses onto the commit-only hand-off (ready — commits local). The
  plan-approval pause applies whatever the checks say.
- 2026-11-03 coord: **one** research round, scoped to the fleet's pinned versions
  and the briefing's open unknowns. Rejected: skipping research (runtime
  `forgejo:15.0.10-rootless`, chart 17.3.1, SeaweedFS 4.50 differ from the
  briefing's assumptions) and re-researching what the card already answered.
- 2026-11-03 coord: two follow-up cards the run would normally mint (SeaweedFS
  chart 4.50.0 to 4.52.0 carrying the #12177 fix; the three pre-existing red
  suites) were NOT created — `dev-boards` is absent from the tool catalog after
  the restart, so no Inbox write is possible. They stay in `STATE.json.deferred`
  for the resuming run or the human.
- 2026-11-03 coord: **slug `cf-104-feat-forgejo-lfs` minted from card content**
  (cardNumber 104 + checked Type `feat` + title), auto-accepted, and it names
  folder, worktree, branch and session alike. Rejected: putting the slug in the
  batched round — a content-derived slug is never a question.
- 2026-11-03 coord: **`Exploration` ran twice.** Round 1 scoped Forgejo +
  SeaweedFS; after the batched round answered the card's `gpu` check as "the
  runner", the scope genuinely widened, so a second scout round (EXPLORE §R0–R7)
  ran before the plan rework rather than letting the planner guess the runner
  surface. Rejected: folding the runner question into the plan without grounding.
- 2026-11-03 coord: **the user's `gpu` answer and the live fleet facts are kept
  as a recorded conflict**, not resolved by fiat: the runner is deployed only on
  dev and gpu has neither Forgejo nor a runner, so the plan carries the
  record-only C04 on the dev surface and the "new gpu runner instance?" choice
  is Q10 for the human. Rejected: silently adding a gpu ApplicationSet entry +
  vault item on a terse answer.
- 2026-11-03 coord: **corrected STATE.json `kickoff.board_context.labels`** — it
  claimed "no Pipeline: label → single default lock", but card #104 carries
  `Provider: Local` + `Pipeline: Local`, and this run's claim set was
  `["Local"]`. A resuming run trusting the old note would claim the wrong lock
  and collide with a `default` run.
- 2026-11-03 coord: **lock-loss posture — stop, do not re-claim.** The reaper
  took the `Local` set during the workspace outage (see FRICTION), so this run
  made no commit and no card move; the resume protocol lives in STATE.json
  `run_state` instead. Rejected: re-claiming inside the lock-lost session, and
  committing the untracked plan folder to "save" it — both are exactly what the
  rule forbids; the commit is the human's call.

## Round-3 answer deltas (2026-11-03 coord-relay, user answers — the human chose these, not the planner)

Supersedes the "best guess dev (`https://git.scifi.farm`, D17)" line in the
Q10 delta entry above; that was the planner's guess and the human overrode it.

- 2026-11-03 coord-relay (user answer): **plan Q13 → the gpu runner serves the
  INFRA instance**, not dev. `forgejo-runner-gpu.runner.url:
  https://git.spencerslab.com`; **UA5 registers the runner record on infra**.
  Rejected: the plan's round-3 best guess (dev / `git.scifi.farm`).
  Grounding verified in-repo this pass: `services/infra/prod/values.yaml:84-91`
  routes `git` (canonical — DOMAIN/ROOT_URL) and `forgejo` (alias) both to
  `infra-forgejo-http:3000`; `custom-values/infra/prod-values.yaml:55-56` sets
  `DOMAIN: git.spencerslab.com` / `ROOT_URL: https://git.spencerslab.com/`;
  the proxy-local hub (`services/proxy-local/prod/values.yaml:114-131`) mirrors
  both hostnames with `target: infra`, crowdsec-only (no hub forward-auth —
  it breaks git-over-HTTPS); gpu's coderd already authenticates against this
  exact host in production (`services/gpu/prod/templates/secrets-coder.yaml:
  31-42`). **No contradiction** with EXPLORE §R3 beyond one nuance worth
  keeping: the `forgejo.spencerslab.com` ban is about **live behaviour, not
  route absence** — the alias route exists repo-side and targets infra, but
  from gpu its name resolves to the public edge (5.78.101.168) where the TLS
  handshake fails a cert name-mismatch, while split DNS carries
  `git.spencerslab.com` → 10.0.77.59 (200, `15.0.10`). So the runner URL is
  the canonical host, never the alias.
- 2026-11-03 coord-relay (user answer): **the Q13 ordering consequence is a
  gate, not a caveat.** Serving infra means the gpu runner's LFS clones depend
  on infra's LFS, which only activates in **C03** (wave 3, gated on the user's
  dev verification). Chosen posture: **C05's live step (the gpu Application's
  ArgoCD sync) rides after C03 + V1/V5-on-infra** (plan rollout step 7, C05
  acceptance 8, C03 acceptance 9). Rejected: "register early and keep
  LFS-bearing repos away from the gpu runner" — a runner that registers,
  clones plain repos fine and fails every LFS fetch (batch endpoint 404, §R3
  before-state) is a half-capable runner nobody can reason about. UA5's record
  may exist early regardless: a registered runner with no pod takes no jobs.
- 2026-11-03 coord-relay (user answer): **plan Q15 → a NEW Bitwarden item
  `gpu-forgejo-runner`** for the gpu runner's uuid/token pair (UA6), per the
  repo's one-item-per-concern naming. Rejected: reusing the reserved
  `dev-forgejo-prod-runner` — that item stays free for the pending infra-runner
  relocation (DECISIONS 2026-10-25). Consequence: `custom-values/gpu/
  prod-values.yaml` carries the new item's UUID against the chart's
  `runner-token: OVERRIDE_VIA_CUSTOM_VALUES` sentinel; the reserved UUID is
  never pasted on gpu.
- 2026-11-03 coord-relay (user answer): **plan Q14 → the Node-22 guarantee is
  accepted as dropped** — `node22` keeps its label name while
  `act-24.04` ships Node 20/24 (zero Actions consumers today). The user's bare
  follow-up **"26?"** is recorded as **Q14b**, open, blocking nothing: facts
  verified at the registry this pass are that `act-26.04` is **not published**
  (manifest 404; the upstream build matrix already lists `26.04`, so the tag
  may appear later) and that in the act family a "26" tag means **Ubuntu
  26.04, not Node 26** (`Dockerfile:14` still `ARG NODE_VERSION="20 24"`) —
  i.e. not available in the incumbent family; a Node-26+git-lfs image needs
  vetting outside it, in a follow-up. **C04's image is unchanged by this pass.**
