# PLAN: Git LFS for Forgejo (SeaweedFS S3) + runner LFS-readiness + gpu runner instance — round 3 (APPROVED)

feature: 2026/2026-11-cf-104-feat-forgejo-lfs
card: #104 `uDTEEpnqEahASJjJN` (AI-Dev) — "Add LFS support to forgejo"
round: 3 (plan APPROVED at the batched pause; two scope deltas folded in — Q10 new gpu runner instance, Q12 node22 job-image swap; Q11: no research round)

## Goal

Turn Git LFS on for both Forgejo instances (dev, infra) and put the LFS object
store on the infra SeaweedFS S3 gateway, through the repo's existing config path
(`gitea.config.*` → `<release>-inline-config`, credentials →
`additionalConfigFromEnvs` fed by a Bitwarden ExternalSecret). Per the answered
Q1/Q10, the card's `gpu` check means the **Forgejo runner** and the user
explicitly chose **a new runner instance on the gpu cluster** (C05), while the
existing runner stays on dev: the LFS-capability record and the now-approved
`node22` job-image swap (Q12: an LFS-capable image) land on the runner chart
(C04). No research round for in-job Actions checkout behavior (Q11 answer).
The repo work is values + one secret template + the runner chart's labels block
+ the gpu trio; the object store, its bucket, its IAM identity and the
server-side runner records are provisioned out-of-band, so the rollout
ordering is where the risk lives.

## Out of scope

- **SeaweedFS version change.** Stay on chart `4.50.0` / image `4.50`. RESEARCH
  §Q2 proves Forgejo never reaches the #12177 multipart path (no
  `TrailingHeaders` in minio-go v7.0.99 as Forgejo builds it; the server block is
  gated on the recorded algorithm). A 4.52 bump is its own `dep` ticket. The
  user's Q6 answer (`MINIO_CHECKSUM_ALGORITHM=default`) rests on the same
  finding — no mitigation is needed from either side.
- **A gpu Forgejo instance.** Q10 answer: `gpu` = a new runner INSTANCE on the
  gpu cluster (C05), not a Forgejo install there and not merely the
  dev-resident runner chart. The gpu cluster still gets **no** Forgejo and no
  SeaweedFS (live fleet + R1): the gpu runner dials out over HTTPS to a Forgejo
  on another cluster.
- **Runner daemon-image work.** The `act-*` swap (Q12) is a job-image/label
  change in `secret-runner.yaml`; the runner **daemon** image needs no git-lfs
  (its git use is action clones from `data.forgejo.org`, EXPLORE §R2a/§R5), and
  no `containers/forgejo-runner/` image exists or is created.
- **In-job Actions LFS checkout proof.** Q11 answer: **no research round** —
  the unobservable in-job items (checkout token scope, `actions/checkout`
  `lfs:` input default, §R6) stay unproven; the runner chunks stay
  record/labels/instance-level, and V5/V6 are the only live probes.
- **Enabling S3 auth through GitOps** (`s3.enableAuth` / `-s3.config` in
  `charts/seaweedfs/values.yaml:419-420`). Auth is already enforced by the
  filer-backed identity store (RESEARCH §Q3, live probe), and flipping the chart
  flag auto-generates a *new* credential set that would break Loki first
  (contradiction C4). Not touched; a blast-radius test leg guards it.
- **Anything beyond LFS**: no `[storage] STORAGE_TYPE`, no attachments/avatars/
  packages/actions/archives to S3, no `SERVE_DIRECT` (uploads always route
  through Forgejo; only downloads could be presigned).
- **New ingress/proxy legs.** The `s3.spencerslab.com` route already exists
  (infra umbrella `ingress.subdomains.s3`), and with `SERVE_DIRECT=false` only
  the Forgejo pods talk to the gateway — no client-facing storage host.
- Bucket creation, gateway IAM provisioning, `migrate-storage` pre-flight,
  ArgoCD sync, PR/merge — all labelled **User actions** below (no agent shell
  into pods, no vault writes, no `kubectl apply`).
- Reusing the idle infra `git` RWX PV/PVC as a filesystem LFS store (RESEARCH
  §Q3 argues against it; Q2 answer: dedicated bucket).

## Authority

`RESEARCH.md` (this folder) is the technical authority over the card body's
Oct-2026 briefing; it corrects four briefing claims, all of which this plan
honours:

1. The pinned chart's `docs/ha-setup.md` split shape (`lfs.STORAGE_TYPE` +
   credentials under `[storage]`) is **not** what Forgejo 15.0.10 does — the
   section that declares `STORAGE_TYPE` is the credential target (C1). This plan
   puts every LFS key inside `[lfs]`.
2. The code default bucket is `gitea`, not the documented `forgejo` (C2) →
   `MINIO_BUCKET` is always set explicitly.
3. #12177 does not bite this stack (§Q2) → no version churn here.
4. The gateway's auth is already ON with identities in the filer-backed store
   (§Q3) → credentials are mandatory; a credential-less design is not available.

`EXPLORE.md` grounds the repo/cluster shapes; its round-2 section
"Runner surface (gpu) — round 2" (§R0–§R7) grounds everything runner-side —
R0–R7 facts are used as-is, not re-derived. Facts the plan sessions added
themselves (all re-verified 2026-11-03 in this worktree):

| Fact | Evidence |
|---|---|
| The `[lfs]` inline-config section and the two credential envs render exactly as planned | `helm template dev charts/forgejo -f /tmp/opencode/forgejo-dev-slice.yaml` → `inline-config` gains `lfs: MINIO_ENDPOINT/MINIO_USE_SSL/STORAGE_TYPE`, `server` gains `LFS_START_SERVER=true`, `init-app-ini` env gains `FORGEJO__LFS__MINIO_ACCESS_KEY_ID`/`…_SECRET_ACCESS_KEY` → `forgejo-s3-secret/{access_key_id,secret_access_key}` |
| Per-instance values reach the chart only as the extracted app slice (the appset passes the *contents* of the top-level `<appName>:` key) | `charts/base/templates/appset-charts.yaml:32-36`; the doubled-key attempt (`{forgejo: <slice>}`) renders **nothing** — proven, and the reason the Commands recipe extracts the slice |
| `helm template --set forgejo.gitea.additionalConfigFromEnvs[2].name=…` **nulls the existing list entries** (render shows `- null` for the DB and SECRET_KEY legs) | render diff, 2026-11-03 → never extend that list with indexed `--set` in tests; use `-f` |
| Credential envs land in `app.ini` on every pod start; only the four auto-generated secrets are dropped when `app.ini` already exists | subchart `config_environment.sh` in the render: `env \| grep ^FORGEJO__ → /tmp/existing-envs`, reload, `unset` only `security.INTERNAL_TOKEN`, `security.SECRET_KEY`, `oauth2.JWT_SECRET`, `server.LFS_JWT_SECRET`, then `environment-to-ini` |
| minio-go resolves a bare host + `MINIO_USE_SSL=true` to 443; an explicit `:443` is also safe (it is stripped from the signed `Host` header) | minio-go v7.0.99 `utils.go:109-128` (`getEndpointURL` builds `<scheme>://<endpoint>`), `api.go:1048-1052` → closes RESEARCH OQ4; the plan writes the bare host |
| Forgejo accepts `MINIO_CHECKSUM_ALGORITHM` literally `default`: only `""`/`default`/`md5` pass validation, and `SendContentMd5` is set **only** for `md5` | Forgejo v15.0.10 `modules/storage/minio.go:87-88,218-219` (fetched this round) → the Q6 answer (`default`) is the same behaviour as leaving the key unset, made explicit |
| SeaweedFS 4.50 shell grammar (verified at tag `4.50` this round): `s3.user.create` takes only `-name/-access_key/-secret_key` — there is **no** `-access` flag; grants go through `s3.bucket.access -name <b> -user <u> -access Read,Write,List,Tagging,Admin` (stored as `Action:bucket`, user auto-created) or attached policies (`s3.policy.*`, `s3.user.provision`) | `weed/shell/command_s3_user_create.go`, `command_s3_bucket_access.go`, `command_s3_bucket_create.go`, `command_s3_bucket_owner.go`, `command_s3_user_provision.go` at tag `4.50` |
| `-owner` semantics: `s3.bucket.create -name <b> -owner <identity>` (and `s3.bucket.owner -owner`) — 4.50 help: "non-admin users can only access buckets they own… without `-owner` the bucket is only accessible by admin users" | `command_s3_bucket_create.go` / `command_s3_bucket_owner.go` Help at tag `4.50` |
| The Q9 self-heal works at the grant level: `CanDo` matches a stored `Admin:<bucket>` action against **every** action evaluated on that bucket (`adminLimitedByBucket := ACTION_ADMIN + ":" + bucket`), and the PutBucket route is gated directly on `ACTION_ADMIN`; the DeleteBucket route passes the same way (that is the cost) | `weed/s3api/auth_credentials.go:2099-2165`, `weed/s3api/s3api_server.go:1204-1208` at tag `4.50` (fetched this round to `/tmp/opencode/`) |
| An identity with legacy Actions and no attached policies authorizes via `authorizeViaLegacyActions` → the explicit `s3.bucket.access` grants are deterministic; `s3.user.provision`'s attached-policy `s3:*` role covering the PutBucket route is **unverified** → not the primary path | `auth_credentials.go:2930-2993` (`authorizationRoute`/`VerifyActionPermission`) at tag `4.50` |
| The `act-*` job images' toolchain, at source (supports the Q12 swap): `act.sh` installs git (git-core PPA) + **git-lfs** (packagecloud) and Node **20 and 24** (`Dockerfile` `ARG NODE_VERSION="20 24"`, act tools dir on PATH) — i.e. `act-24.04` is LFS-capable but is **not** a Node-22 image | `catthehacker/docker_images@master`: `linux/ubuntu/scripts/act.sh:72,80-82,123-144`, `linux/ubuntu/Dockerfile:14`, `.github/workflows/build-ubuntu.yml:122-126` (fetched this round) |
| Replacement-tag existence (Q12): `ghcr.io/catthehacker/ubuntu:act-24.04` and `:act-22.04` exist; act-24.04 index `sha256:62d572b9…` with amd64 manifest `sha256:dff4ec57…` — the same amd64 digest §R2 probed on 2026-11-02 (tag unmoved). GHCR manifest GET returns **404 without an `Accept` header** for multi-arch tags — a false-negative probe trap | registry probe this round (R7 probe shape, corrected with `Accept: …image.index.v1+json…`) |
| gpu cluster repo/cluster ground for C05: `charts:` block at `services/gpu/prod/values.yaml:52`; top-level app slices live beside it; gpu StorageClasses are `local-path` (default) + `seaweedfs-storage`, so the chart's `local-path` VCTs need no override; gpu umbrella sentinel baseline measured at **1** (three legacy `OVERRIDE_VIA_CLUSTER_ANNOTATION` entries on one ApplicationSet values-JSON line) | files read this round + `helm template gpu services/gpu/prod -f custom-values/gpu/prod-values.yaml --set domain=spencerslab.com --set clusterName=gpu \| grep -c OVERRIDE_` → 1 |
| Infra host grounding for the Q13 answer: `services/infra/prod/values.yaml:84-91` routes `git` (**canonical** — DOMAIN/ROOT_URL) and `forgejo` (alias) both to `infra-forgejo-http:3000`; the proxy-local hub (`services/proxy-local/prod/values.yaml:114-131`) mirrors both, crowdsec-only (git clients auth at Forgejo; hub forward-auth would break git-over-HTTPS). The §R3 ban of `forgejo.spencerslab.com` is therefore about **live behaviour, not route absence**: the alias route exists repo-side, but from gpu its name resolves to the public edge (5.78.101.168) where the TLS handshake fails a cert name-mismatch — and LAN split DNS only carries `git.spencerslab.com` → 10.0.77.59 (200, 15.0.10). No contradiction between §R3 and the repo beyond that nuance | files read this pass + §R3 probes |
| Q14b registry facts ("26?" — verified before writing them down): act-family tag `act-26.04` does **not** exist in `ghcr.io/catthehacker/ubuntu` (manifest 404 with the corrected Accept-header probe) although the current build workflow matrix lists `26.04` + `LATEST_TAG: 26.04`; upstream `Dockerfile:14` still has `ARG NODE_VERSION="20 24"` (no Node 26 in any act image); family tag names encode **Ubuntu** releases, not Node versions. Note: the GHCR `tags/list` endpoint is **paginated** (`Link: rel="next"`; the first `n=200` page is all-2021 tags — existence must be proven per-tag via the manifests endpoint) | registry + `catthehacker/docker_images@master` probes this pass |
| Live infra shapes for the user commands | LIVE infra 2026-11-03: `statefulset/seaweedfs-master`, `statefulset/seaweedfs-filer`, `deployment/seaweedfs-s3`, `deployment/infra-forgejo`; services `seaweedfs-master:9333`, `seaweedfs-filer(-client):8888` |
| The forgejo pod's main container is named `forgejo` (exec target for the pre-flight) | render `Deployment/dev-forgejo` containers: `init-app-ini`, `configure-gitea`, `forgejo` |
| The LFS batch route is live-off on both instances today (the before-state oracle) | EXPLORE §R3: `POST /<owner>/<repo>.git/info/lfs` (`Accept: application/vnd.git-lfs+json`) → 404 `Not found.` on dev and infra hosts; an *enabled* endpoint answering 401 for an unauthenticated batch is an upstream **hypothesis**, not yet observed — V5 tests it |
| Regression baselines (measured, not assumed) | `tests/services/infra-forgejo.sh` exit 0 / 33 ok; `dev-git-auth.sh` exit 0 / 36 ok; `dev-forgejo-runner.sh` **exit 1** / 27 ok (t5 false positive: its comment-window scan swallows cf-93's sandbox-pair comment, which contains "both"); `forgejo-ssh-gateway.sh` **exit 1** / 63 ok and `forgejo-ssh-audit-trail.sh` **exit 1** / 0 ok (t1: a tracked `storm-runs/` dir sits at the repo root on main). All four reds pre-date this ticket. The runner suite stops at the first failing leg, so **no leg after t5 executes while t5 stays red** — C04's new leg is deliberately placed before t5 |
| Sentinel baseline | `helm template dev services/dev/prod -f custom-values/dev/prod-values.yaml …` → **1** `OVERRIDE_*` hit (the pre-existing `home-assistant.bitwardenIds` wart inside the ApplicationSet values JSON); infra render → **0** |

## Verified repo context (the shapes the chunks ride)

| Surface | File:line | Note |
|---|---|---|
| Wrapper chart | `charts/forgejo/{Chart.yaml,Chart.lock,values.yaml}` | dep `forgejo` `17.3.1` @ `oci://code.forgejo.org/forgejo-helm` (OCI ⇒ manual bumps, CI bumps wrapper `version` — never hand-bump) |
| Secret templates (the style to copy) | `charts/forgejo/templates/secret-forgejo.yaml` | ungated, fixed names (`forgejo-secret`, `pg-forgejo-secret`, `forgejo-admin-secret`), `bitwarden-login` store, `conversionStrategy: Default` / `decodingStrategy: None` / `metadataPolicy: None` boilerplate |
| S3 credential precedent | `charts/loki/templates/secret-s3.yaml` | `access_key_id ← username`, `secret_access_key ← password`, one item id |
| Sentinel map (chart-owned) | `charts/forgejo/values.yaml:17-30` | four keys today; the new `forgejo-s3` joins it |
| Config path | `charts/forgejo/values.yaml:59-102` (`gitea.config.*`) | renders into `<release>-inline-config`, one key per section |
| Secret env path | `charts/forgejo/values.yaml:104-119` (`additionalConfigFromEnvs`) | the only path for anything secret |
| Per-instance overrides | `custom-values/dev/prod-values.yaml:62-80`, `custom-values/infra/prod-values.yaml:44-63` | top-level `forgejo:` = `bitwardenIds` + `forgejo.gitea.config.*` |
| ApplicationSet legs | `services/dev/prod/values.yaml:76-78`, `services/infra/prod/values.yaml:18-20` | `charts.forgejo` both, `ServerSideApply: "false"` — unchanged by this ticket |
| Proxy legs | `services/dev/prod/values.yaml:136-138`, `services/infra/prod/values.yaml:86-91` | `git`/`forgejo` → `<c>-forgejo-http:3000` — unchanged |
| Gateway route (exists) | `services/infra/prod/values.yaml:79-82` | `ingress.subdomains.s3` → `seaweedfs-s3:8333`, TLS `wildcard-cert` (Let's Encrypt: `charts/base/templates/cert-manager-issuer.yaml`) → no private-CA problem for dev's HTTPS leg |
| Gateway args / buckets folder | `charts/seaweedfs/values.yaml:404`, `:416-429` | `WEED_FILER_BUCKETS_FOLDER=/buckets` (bucket ≡ collection ≡ directory); `s3.enableAuth` stays commented |
| Runner deployment (the ONE release) | `services/dev/prod/values.yaml:102-105` + top-level slice `:164-166`; `custom-values/dev/prod-values.yaml:82-88` | app `forgejo-runner-dev` (chart alias `forgejo-runner`), `runner.url: http://dev-forgejo-http:3000`, `bitwardenIds.runner-token` UUID item `dev-forgejo-dev-runner`. Infra runner un-wired 2026-10-25; gpu has none (LIVE §R1) |
| Runner config surface | `charts/forgejo-runner/templates/secret-runner.yaml` (ExternalSecret + whole `config.yaml`); label→job-image map `:72-77` | the labels block is C04's comment site; pins (`values.yaml:96-102,136-141`) are renovate-tracked, the **job images in the template are NOT** (§R5) |
| Runner contract test | `tests/services/dev-forgejo-runner.sh` (1508 lines, legs t1–t13) | `ACT_LABELS` hard-coded 5-set `:252-258`, asserted `:461`; `CHART_DEFAULT_URL` `:260`; t5 comment-window scan (the pinned false positive) `:725-730` |
| Cross-suite couplings | `tests/services/forgejo-ssh-gateway.sh:1601-1608` re-runs the runner suite requiring exit 0; `tests/multi-repo/dev-wiring.sh:252-253` requires the mosquitto comment in `services/dev/prod/values.yaml` to keep citing `forgejo-runner-dev` | both stay red/hold for pinned reasons; neither may be "fixed" or disturbed by this ticket |

## Decisions

Round-1 question answers (Q1–Q9) are binding; decisions taken this round are
marked *(r2)*.

| # | Decision | Basis |
|---|---|---|
| D1 | Config shape: every LFS key inside `[lfs]`; no `[storage]` section anywhere | C1 + C7 in RESEARCH; the `[storage]` shape would silently move attachments, avatars, packages, actions logs and archives to S3 |
| D2 | Bucket: purpose-built `git-lfs` | **Q2 answer**; bucket-scoped IAM stays narrow, cleanup stays surgical, the 1 TiB RWX `git` PV cannot read/overwrite LFS objects |
| D3 | Chart default stays inert: chart ships only the instance-independent shape (`MINIO_BUCKET`, `MINIO_BUCKET_LOOKUP`, `MINIO_CHECKSUM_ALGORITHM`, `SERVE_DIRECT`); the activation switch (`[lfs] STORAGE_TYPE=minio` + `server.LFS_START_SERVER=true`) and the endpoint live in each cluster's custom-values | per-instance rollout control; a cluster without a bucket keeps local storage |
| D4 | Endpoints: dev → `s3.spencerslab.com` + `MINIO_USE_SSL: true`; infra → `seaweedfs-s3.default.svc.cluster.local:8333` + `MINIO_USE_SSL: false` | **Q4 answer** (asymmetry confirmed); bare host is proven safe for 443 |
| D5 | `MINIO_BUCKET_LOOKUP: path` (explicit); `MINIO_CHECKSUM_ALGORITHM: default` | **Q6 answer — user override of the plan's md5 recommendation**. Rationale as stated by the user: no #12177 mitigation is needed because Forgejo's minio-go code path never sets `TrailingHeaders` (RESEARCH §Q2), so the per-object `Content-MD5` buys nothing against that bug. Verified `default` is a valid literal (v15.0.10 `minio.go:87-88`) and equals the unset behaviour (`SendContentMd5` only for `md5`, `:218`) |
| D6 | Credentials: one Bitwarden Login item `forgejo-s3` (username = access key id, password = secret), one chart key `bitwardenIds.forgejo-s3`, the same UUID in both clusters' custom-values; gateway user `forgejo-lfs` | **Q3 answer** (shared identity + shared item) |
| D7 | Grant *(r2)*: **owner grant with self-healing MakeBucket** — bucket created `-owner forgejo-lfs`, identity carries bucket-scoped `Read,Write,List,Admin` on `git-lfs` only | **Q9 answer**. Reconciliation with RESEARCH's boot-fatal analysis: the chart's `MakeBucket` fallback needs the PutBucket route, which 4.50 gates on `Admin` (srv.go:1204); a **bucket-scoped** `Admin:git-lfs` satisfies that gate for that bucket alone (`CanDo` matches `Admin:<bucket>` for any action on it, ac.go:2099-2165). This **removes the "missing bucket ⇒ `log.Fatal`" failure mode** — Forgejo recreates the bucket at boot instead of taking the instance down. Cost in grant width: on `git-lfs` the identity is effectively full-control (object RW + tagging, DeleteBucket, bucket policy/encryption/public-access-block subresources); it cannot reach `logs`, `git` or any other bucket — grants are per-bucket strings. Also flips the failure signature: a deleted bucket returns **empty** (missing objects read as vanished files, not a boot failure). `List` kept for operator tooling; Tagging deliberately omitted |
| D8 | `LFS_JWT_SECRET`: do nothing | the subchart already generated it at first boot and refuses to rewrite it while `app.ini` exists — an `additionalConfigFromEnvs` override would be silently dropped |
| D9 | Migration: `migrate-storage` is a **pre-flight**, not a data move | LFS was never enabled (`LFS_START_SERVER` unset → false; no `[lfs]` in either render; `/data/lfs` absent per PF0) so nothing exists to migrate; it still calls `storage.Init()` — exactly the boot path |
| D10 | Landing: one branch, all chunks committed; C03 independently revertable; the user may land C01+C02 and hold C03 until dev is verified | **Q8 answer** (all three on the branch; C03 gated on dev-side verification); merge stays user-owned |
| D11 | Placeholder policy: `custom-values/**` must carry a **real UUID** for `forgejo-s3` before any sync — `OVERRIDE_NEEDED` forbidden for this key | the credential `secretKeyRef` is on the **init container**: no `forgejo-s3-secret` → pod cannot start at all (`CreateContainerConfigError`) |
| D12 | `MINIO_LOCATION`: leave the code default (`us-east-1`) | only used by `MakeBucket` — which now *can* run (D7); the `?location` route exists on 4.50 so the region probe will not misfire |
| D13 *(r2, amended r3)* | Scope of `gpu` = the **runner**; the live fleet disagrees with the card's mental model (runner only on dev, gpu has none, §R1), so the instance-vs-surface split was asked rather than assumed — **Q10 answer: a NEW runner INSTANCE on the gpu cluster** | Approved delta → new chunk **C05** (gpu trio + own suite); C04 keeps the record + swap on the shared runner chart. Which instance the gpu runner serves is grounded nowhere → Q13, best guess dev (D17) |
| D14 *(r2, amended r3)* | Runner job images: **Q12 answer — swap the `node22` image now** (the only label whose image lacks git-lfs, §R2b); the swap is a functional C04 change with the `ACT_LABELS` coupling edited **red-first by agent-test**; the daemon image still needs no git-lfs (§R2a) | Rejected at the pause: round-2's leave-documented recommendation. Rejected: renaming the label (same test cost, breaks label compatibility for future workflows) |
| D15 *(r2)* | Runner-side verification is live probes (V5 batch route, V6 in-job `git lfs version`), not suite legs | the runner suite's own header (`tests/services/dev-forgejo-runner.sh:29-36`) rules that cluster acceptance is proven by exact-name readonly reads, not legs; the batch-route probe is a plain `curl` any session can run from this worktree |
| D16 *(r2)* | Pre-flight flags omit `--minio-checksum-algorithm` entirely (flag default == `default`) | keeps PF1/PF2 aligned with D5 without naming a value the code treats as its own special case |
| D17 *(r3, superseded by user Q13 answer)* | The gpu runner serves the **infra** instance: top-level `forgejo-runner-gpu.runner.url: https://git.spencerslab.com` | **Q13 coord-relay user answer — the planner's round-3 best guess (dev / `git.scifi.farm`) is superseded.** Grounding: `git.spencerslab.com` is the infra instance's canonical host (`services/infra/prod/values.yaml:84-91`: `git` = canonical DOMAIN/ROOT_URL, `forgejo` = alias, both → `infra-forgejo-http:3000`), §R3 probed it from a gpu pod at 10.0.77.59 answering 200 `15.0.10`, and gpu's coderd already authenticates against this exact host in production (`services/gpu/prod/templates/secrets-coder.yaml:31-42`). **Never** `forgejo.spencerslab.com`: the alias ingress exists repo-side, but §R3's live probe shows its public-edge path (5.78.101.168) failing TLS with a cert name-mismatch, and LAN split DNS resolves it there — banned on live behaviour, not on route absence. Ordering consequence: infra LFS activates only in C03 → rollout step 7 gates the gpu runner's sync (its first job) behind C03's sync |
| D18 *(r3)* | `node22` replacement image: `ghcr.io/catthehacker/ubuntu:act-24.04` — incumbent LFS-capable family, tag + digests re-verified this round (Authority); the label name stays `node22` | §R2 + source-verified toolchain (Node 20/24, **not** 22 → Q14 caveat recorded, not hidden). Update posture: the tag is **rolling** and **not renovate-tracked** (the repo's template-file custom manager yields 0 hits on `- <label>:docker://…` lines, §R5) → manual bump + red-first `ACT_LABELS` edit + V6 probe; a renovate manager for the label lines is a follow-up chore |

## Questions

### Round-1 batched round — answers received (binding; do not re-ask)

| # | Question | Answer |
|---|---|---|
| Q1 | Card `gpu` label: mislabel or real consumer? | "The runner is on gpu" — `gpu` means the Forgejo **runner**, not a Forgejo instance. Live fleet disagrees (no runner on gpu at all) → the instance-vs-surface split is re-raised as Q10 |
| Q2 | Bucket: dedicated `git-lfs` or reuse `/buckets/git`? | Dedicated `git-lfs` |
| Q3 | One shared gateway identity + Bitwarden item, or per-instance? | ONE identity (`forgejo-lfs`) + ONE item (`forgejo-s3`) for both instances |
| Q4 | Endpoint asymmetry? | Confirmed: dev `s3.spencerslab.com` + SSL; infra in-cluster without |
| Q5 | Bucket replication: accept filer default `001`? | Accept; a `002` requirement would be a separate shared-infra card |
| Q6 | `MINIO_CHECKSUM_ALGORITHM`? | `default` — **override** of the plan's md5 recommendation; rationale in D5 |
| Q7 | `LFS_MAX_FILE_SIZE`? | Unlimited (0) — no key added; the Traefik 600 s read-bound risk stays documented |
| Q8 | Landing shape? | All three activation chunks on the branch; C03 gated on the user's dev-side verification |
| Q9 | Grant width? | Wider **owner grant with self-healing MakeBucket** — `s3.bucket.create -owner forgejo-lfs`; full reconciliation in D7 |

### Round-2 batched round — answers received at the approval pause (binding)

| # | Question | Answer (verbatim intent) |
|---|---|---|
| Q10 | New runner **instance** on the gpu cluster, or the runner-chart surface while the runner stays on dev? | **A NEW runner INSTANCE on the gpu cluster** — explicitly not "the dev-resident runner chart only" → C05 added; its target instance is Q13 |
| Q11 | Prove in-job Actions LFS checkout this ticket (needs a research round)? | **No research round** — C04/C05 stay record/labels/instance-level; V5/V6 stand as the only probes |
| Q12 | `node22` image (no git-lfs): leave documented or swap now? | **Swap now** — C04 becomes a functional change (red-first `ACT_LABELS` edit), replacement pinned per D18 |

### Round-3 batched round — answers received (binding; do not re-ask)

| # | Question | Answer (verbatim intent) |
|---|---|---|
| Q13 | gpu runner target: dev or infra? | **INFRA** — `runner.url: https://git.spencerslab.com`, UA5 registers the record on the infra instance; **supersedes the plan's round-3 dev best guess** (recorded as a coord-relay user answer in DECISIONS.md). Ordering consequence (infra LFS only activates in C03) taken into rollout step 7 + C05 acceptance |
| Q14 | Accept that `node22` no longer guarantees Node 22? | **Accepted** for the current version (act-24.04 = Node 20/24); the user added a fresh **"26?"** → Q14b below |
| Q15 | New vault item vs reusing `dev-forgejo-prod-runner`? | **NEW item `gpu-forgejo-runner`** (one-item-per-concern naming); the reserved `dev-forgejo-prod-runner` stays free for the infra-runner relocation |

### Round-4 open question (answer anytime; blocks nothing)

| # | Question | Best guess taken in this plan | Impact if the answer differs | Who |
|---|---|---|---|---|
| Q14b | The user's **"26?"** — is there an LFS-capable job image on a newer Node? Facts verified at the registry this pass (write down only these): act-family **`act-26.04` does not exist yet** (manifest 404; the upstream build matrix *lists* `26.04`, so the tag may appear later); in that family a "26" tag means **Ubuntu 26.04, not Node 26**; the current `Dockerfile` still builds every act image with `ARG NODE_VERSION="20 24"` — **no act image ships Node 26 today**. Any Node-26-with-git-lfs image would come from elsewhere (`cimg/node` and friends — unvetted) | **No change**: C04 stays on `act-24.04` (the swap was about git-lfs, which it has); Q14b is a registry-vetting follow-up, not a chunk | A vetted newer image = a future labels bump (manual + red-first `ACT_LABELS` edit — job images remain renovate-untracked) | user + follow-up |

Questions the plan **resolves** without asking: RESEARCH OQ4 (bare host → 443,
verified in minio-go), OQ5 (4.50 shell verbs — grammar now verified verb-by-verb
in Authority), `LFS_JWT_SECRET` (nothing to do), the SeaweedFS version question
(stay on 4.50), auth-on (not a choice anymore), the `[lfs]`-vs-`[storage]`
placement (code at the pinned tag decides), and the runner daemon image (no
git-lfs needed, §R2a).

## Config of record

`charts/forgejo/values.yaml` (C01) — additive, inert:

```yaml
bitwardenIds:
  # … existing four …
  # Git LFS object store on the SeaweedFS S3 gateway. LOGIN item:
  # username = access key id, password = secret access key.
  forgejo-s3: OVERRIDE_VIA_CUSTOM_VALUES

forgejo:
  gitea:
    config:
      # Instance-independent LFS shape only. The activation switch
      # ([lfs] STORAGE_TYPE=minio) and MINIO_ENDPOINT are per-instance in
      # custom-values, so a cluster that has not provisioned a bucket keeps
      # LFS on local storage. Every LFS key stays inside [lfs]: Forgejo reads
      # S3 credentials from the section that declares STORAGE_TYPE, and a
      # [storage] section would also move attachments, avatars and packages
      # to S3.
      lfs:
        MINIO_BUCKET: git-lfs
        MINIO_BUCKET_LOOKUP: path
        MINIO_CHECKSUM_ALGORITHM: default
        SERVE_DIRECT: false
    additionalConfigFromEnvs:
      # … existing two …
      # Section name is lower-cased by decodeEnvSectionKey, so FORGEJO__LFS__*
      # lands in [lfs]. Not one of the four auto-generated secrets
      # config_environment.sh drops once app.ini exists, so these do apply on
      # an existing instance's next start.
      - name: FORGEJO__LFS__MINIO_ACCESS_KEY_ID
        valueFrom:
          secretKeyRef:
            name: forgejo-s3-secret
            key: access_key_id
      - name: FORGEJO__LFS__MINIO_SECRET_ACCESS_KEY
        valueFrom:
          secretKeyRef:
            name: forgejo-s3-secret
            key: secret_access_key
```

(`MINIO_CHECKSUM_ALGORITHM: default` is the Q6 answer; valid literal, equals
unset behaviour — `SendContentMd5` only for `md5`.)

`charts/forgejo/templates/secret-forgejo-s3.yaml` (C01) — Loki's mapping, the
forgejo chart's own style (ungated, fixed names, item read by id):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: forgejo-s3-secret
spec:
  refreshInterval: 1h
  target:
    name: forgejo-s3-secret
    creationPolicy: Owner
  data:
    - secretKey: access_key_id
      sourceRef:
        storeRef: {name: bitwarden-login, kind: SecretStore}
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "forgejo-s3" }}'
        property: username
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
    - secretKey: secret_access_key
      sourceRef:
        storeRef: {name: bitwarden-login, kind: SecretStore}
      remoteRef:
        key: '{{ index .Values "bitwardenIds" "forgejo-s3" }}'
        property: password
        conversionStrategy: Default
        decodingStrategy: None
        metadataPolicy: None
```

(`storeRef` shown inline for brevity; write it in the multi-line form
`secret-forgejo.yaml` uses. The `{{ }}` in `key:` stays quoted so the template is
valid YAML before substitution — repo ESO rule.)

`custom-values/dev/prod-values.yaml` (C02) — under the existing `forgejo:` key:

```yaml
    forgejo-s3: <UUID of item forgejo-s3>     # real UUID, never OVERRIDE_NEEDED (D11)
  forgejo:
    gitea:
      config:
        server:
          LFS_START_SERVER: true
        lfs:
          STORAGE_TYPE: minio
          MINIO_ENDPOINT: s3.spencerslab.com
          MINIO_USE_SSL: true
```

`custom-values/infra/prod-values.yaml` (C03) — same shape, in-cluster endpoint:

```yaml
    forgejo-s3: <UUID of item forgejo-s3>
  forgejo:
    gitea:
      config:
        server:
          LFS_START_SERVER: true
        lfs:
          STORAGE_TYPE: minio
          MINIO_ENDPOINT: seaweedfs-s3.default.svc.cluster.local:8333
          MINIO_USE_SSL: false
```

Effective `[lfs]` after the merge (both instances; four keys come from the
chart, three from custom-values):

```ini
[lfs]
MINIO_BUCKET=git-lfs
MINIO_BUCKET_LOOKUP=path
MINIO_CHECKSUM_ALGORITHM=default
MINIO_ENDPOINT=<per instance>
MINIO_USE_SSL=<per instance>
SERVE_DIRECT=false
STORAGE_TYPE=minio
```

`charts/forgejo-runner/templates/secret-runner.yaml` (C04) — one functional
line + a record block at the `server.connections.default.labels` block
(`:72-77`): the swap `- node22:docker://docker.io/library/node:22-bookworm` →
`- node22:docker://ghcr.io/catthehacker/ubuntu:act-24.04` (D18; every label now
maps to a git-lfs-bearing image), beside comments recording the toolchain
facts — act images ship git-lfs (installer-pinned) and Node 20/24 (**not** 22,
Q14), that the daemon image's git needs no LFS, and that the runner clones over
HTTPS (ROOT_URL-derived), so LFS works in jobs iff the instance serves
`[lfs]`. Nothing in `charts/forgejo-runner/values.yaml` changes
(renovate-tracked pins untouched).

`services/gpu/prod/values.yaml` (C05) — inside the existing `charts:` block
(`:52`):

```yaml
  # Client-only service: the gpu runner dials out over the infra instance's
  # public route (gpu has no in-cluster Forgejo), so it deliberately gets NO
  # ingress.subdomains entry — the service trio's proxy leg is N/A by
  # design, not an oversight (same documented posture as forgejo-runner-dev).
  forgejo-runner-gpu:
    namespace: default
    ServerSideApply: "false"
    chart: forgejo-runner
```

and as a **top-level** slice in the same file (the appset merges only the
contents of the top-level `<appName>:`, `appset-charts.yaml:32-36`):

```yaml
forgejo-runner-gpu:
  runner:
    url: https://git.spencerslab.com   # infra instance over HTTPS (Q13 answer) — canonical DOMAIN/ROOT_URL host; never the forgejo. alias (live TLS fails on its public path, §R3), never an in-cluster URL (dead on gpu)
```

`custom-values/gpu/prod-values.yaml` (C05):

```yaml
forgejo-runner-gpu:
  bitwardenIds:
    # Item gpu-forgejo-runner (UA6 — Q15 answer: a NEW item, one item per
    # concern; the reserved dev-forgejo-prod-runner stays free for the infra
    # runner relocation). username = runner uuid, password = runner token,
    # from the INFRA-instance runner record created in UA5
    # (git.spencerslab.com — Q13 answer). Real UUID — an unresolved/placeholder
    # id crashloops the daemon (`'uuid' is empty`).
    runner-token: <UUID from UA6>
```

(`charts/forgejo-runner/values.yaml` already carries the
`runner-token: OVERRIDE_VIA_CUSTOM_VALUES` chart sentinel — C05 replaces it
with the real UUID of the **new `gpu-forgejo-runner` item** (Q15), the standard
sentinel→UUID recipe; reusing the reserved `dev-forgejo-prod-runner` UUID is
forbidden — it is held for the infra relocation. No proxy values entry: the
trio's third leg is N/A for a dial-out-only runner — no ingress, no service
any client contacts; the exemption comment above is what the repo's trio-grep
readers expect, mirroring `services/dev/prod/values.yaml:96-101`.)

## Chunks

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | Chart plumbing: `forgejo-s3` secret path + inert `[lfs]` shape | M | 1 | [] | Owns `charts/forgejo/**`; nothing else can be validated before the chart interface (secret name, env names, `[lfs]` keys) exists |
| C04 | Runner LFS-readiness: `node22`→`act-24.04` swap + record + runner-suite t14 (red-first `ACT_LABELS` edit) | S | 1 | [] | Independent of C01–C03: owns `charts/forgejo-runner/templates/secret-runner.yaml` and the runner suite; its red-first precondition (agent-test editing `ACT_LABELS` at `:252-258`) belongs to the test-writing session, not to a chunk |
| C02 | dev activation (public HTTPS endpoint) | S | 2 | [C01] | Writes the values that merge with C01's chart keys; a dev render is meaningless without C01 |
| C05 | gpu runner instance (trio + own suite), serving **infra** (Q13) | M | 2 | [] | Repo-side depends on no other chunk; its **hard preconditions** are User actions UA5 (runner record on the **infra** instance) + UA6 (new `gpu-forgejo-runner` item, UUID reported) — enforced in C05's acceptance criteria (NEEDS_INFO without a real UUID), deliberately not a fake chunk dependency. Its **sync** additionally rides after C03 in rollout step 7 (infra LFS must be live before the runner takes LFS-bearing jobs) |
| C03 | infra activation (in-cluster endpoint) | S | 3 | [C02] | Deliberate rollout order (RESEARCH §6: dev first); Q8 answer keeps it on the branch, gated on dev verification, independently revertable |

Mergeable grouping: **C01 + C02** is a complete, dev-only change; **C03** is a
separate, independently revertable commit (Q8). **C04** is a separate revert-
able commit (one labels line + comments + test leg; live effect only at the
next runner restart, which the `reloader.stakater.com/auto` annotation triggers
on the config Secret change — worth naming in the RESULT). **C05** is a
separate revertable commit pair (values + suite) with zero effect on dev.

## Wave order

1. **C01 + C04** (independent; one wave). C01 renders inert; C04 is the
   labels swap + record (its t2 leg turns the runner suite red **from the
   test-writing session onward** — see Commands' transitional-baseline note).
2. **C02** — dev. Its *activation* is gated behind UA1–UA4 + PF1 (the
   pre-flight), which must be done before the merge, not before the chunk.
   **C05** — gpu runner instance, in parallel; gated for *completion* on
   UA5/UA6 (runner record on **infra** + the new `gpu-forgejo-runner` item +
   reported UUID), and its live registration is gated on C04
   having landed (the gpu release renders the same labels map — swapping
   first avoids registering a Node-less-LFS runner). Its **sync** rides after
   **C03** (rollout step 7): infra's LFS must be live before this runner can
   take LFS-bearing jobs.
3. **C03** — infra. On the same branch (Q8); its live effect additionally
   gated on V1–V3 + V5 having passed on dev, and PF2 before the sync that
   restarts infra.

## Binding rollout order (RESEARCH TL;DR 5 + §Q1 handshake, Q9 shape)

1. Identity exists: `s3.user.create -name forgejo-lfs` (capture both printed
   keys).
2. Bucket exists **owned by it**: `s3.bucket.create -name git-lfs -owner
   forgejo-lfs`, then the bucket-scoped grant `s3.bucket.access -name git-lfs
   -user forgejo-lfs -access Read,Write,List,Admin` and a re-read to confirm.
   The grant is what makes `Read`-at-boot succeed *and* lets Forgejo's own
   `MakeBucket` self-heal a missing bucket (D7) — the round-1 "missing bucket
   ⇒ whole instance down" leg is gone, replaced by "deleted bucket returns
   empty".
3. `forgejo migrate-storage --type lfs …` with the target config as flags —
   a near-read-only proof of exactly that init path (30 s init ceiling), before
   any pod restarts.
4. Bitwarden item + real UUID in both custom-values files (D11).
5. Only then: merge (C01+C02; C03 may ride the same branch as its own commit)
   → ArgoCD sync → the config lands → the pods restart.
6. dev verified (V1–V3 + V5) before infra's sync is trusted (Q8); PF2 runs
   against infra before its restart.
7. **gpu runner (C05) — commit early, sync last (Q13 answer's ordering
   consequence, made concrete).** UA5 creates the persistent runner record on
   the **infra** instance (`git.spencerslab.com`) → UA6 creates the **new**
   Bitwarden item `gpu-forgejo-runner` + reports the UUID → C05 commits the
   trio on the branch (its wave-2 repo work may land any time after C04).
   **But the gpu Application must not sync before C03 has synced and infra's
   LFS is verified (V1 + V5 on the infra host):** the runner would otherwise
   register and take jobs against an instance whose LFS batch endpoint still
   404s (§R3 before-state), so cloning any LFS-bearing repo fails at the LFS
   fetch while plain repos work — a confusing half-capable runner. The chosen
   ordering is therefore: **C05 live step rides after C03** in this rollout;
   no "register early and keep LFS repos away from the gpu runner" posture.
   V7 after that sync: pod `forgejo-runner-gpu-0` log shows the
   `runner: … declared successfully` line with the labels list (agent-
   readable), and the registration shows online on **infra** (human). Single
   replica only — one record == one pod, chart decision B1.

## Commands

The pipeline's "tests" in this repo are renders, sweeps and greps
(`AGENTS.md` → "Pipeline specifics in this repo"). agent-test writes
`tests/services/forgejo-lfs.sh` (new) and `tests/services/gpu-forgejo-runner.sh`
(new), and extends `tests/services/dev-forgejo-runner.sh` (leg t14 + the
red-first `ACT_LABELS` edit for C04's swap) in one session before any dev;
every dev and review run re-runs them plus the regression set.

```bash
export PATH=$HOME/.local/bin:$PATH          # helm lives at ~/.local/bin (v3.16.4)
cd "$(git rev-parse --show-toplevel)"

# ---- C01: chart ----
helm dependency update charts/forgejo       # OCI dep; charts/**/charts is gitignored
helm lint charts/forgejo                    # INFO: icon is recommended (pre-existing)
helm template dev charts/forgejo \
  --set domain=scifi.farm --set clusterName=dev \
  --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
  --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4 \
  --set bitwardenIds.forgejo-s3=u5
# assert: inline-config `lfs` key == the 4 shape keys (checksum=default) and NO
#         STORAGE_TYPE; no `storage` / `attachment` / `picture` sections;
#         init-app-ini env == 4 legs (2 existing + 2 LFS);
#         ExternalSecret forgejo-s3-secret present.
# NEVER extend additionalConfigFromEnvs with indexed --set — it nulls the
# existing entries (proven). Use -f.

# ---- C02 / C03: effective per-instance render ----
# The Application receives the CONTENTS of the top-level `forgejo:` key, so
# extract the app slice before rendering the chart against real values:
python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); \
  yaml.safe_dump(d["forgejo"], open(sys.argv[2],"w"))' \
  custom-values/dev/prod-values.yaml /tmp/opencode/forgejo-dev-slice.yaml
helm template dev charts/forgejo -f /tmp/opencode/forgejo-dev-slice.yaml \
  --set domain=scifi.farm --set clusterName=dev
# same for infra: extract custom-values/infra/prod-values.yaml["forgejo"], then
#   helm template infra charts/forgejo -f /tmp/opencode/forgejo-infra-slice.yaml \
#     --set domain=spencerslab.com --set clusterName=infra
# assert: [lfs] == the 7 keys of record; [server] LFS_START_SERVER=true;
#         ExternalSecret remoteRef key == the UUID from the slice.

# ---- C04: runner labels swap (node22 → act-24.04) + record + t14 ----
git diff main -- charts/forgejo-runner/values.yaml                       # want EMPTY (renovate pins untouched)
git diff main -- charts/forgejo-runner | grep -cE '^[+-].*docker://'     # want exactly 2: the one removed and one added labels line
bash tests/services/dev-forgejo-runner.sh
# BASELINE TRANSITIONS — pin honestly, do not chase:
#   main today:            exit 1 / 27 ok  (pre-existing t5 false positive, cf-93 comment in the scan window)
#   after agent-test (red-first ACT_LABELS edit, before C04): exit 1 STOPPING AT t2
#     (t2 asserts the labels map against the edited ACT_LABELS at :461 — t2 sits before t5)
#   after C04:             back to exit 1 at t5, ok-count = 27 + t14's ok — report the measured number
# The suite STOPS at the first failing leg, so t14 (placed BEFORE t5) must show
# `ok:` in stdout; legs after t5 never run while t5 stays red — expected, do NOT
# "fix" t5.
grep -c 'forgejo-runner' services/dev/prod/values.yaml   # trio-exemption comment citation must survive (dev-wiring.sh:252-253)

# ---- C05: gpu runner instance ----
# Standalone chart render against the real gpu slice (extract the app key —
# the appset passes the CONTENTS of the top-level `<appName>:`):
python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); \
  yaml.safe_dump(d["forgejo-runner-gpu"], open(sys.argv[2],"w"))' \
  custom-values/gpu/prod-values.yaml /tmp/opencode/runner-gpu-slice.yaml
# The URL lives in the SERVICES file's top-level slice (dev pattern), assert separately:
python3 -c 'import yaml; print(yaml.safe_load(open("services/gpu/prod/values.yaml"))["forgejo-runner-gpu"]["runner"]["url"])'
#   want https://git.spencerslab.com  (Q13 answer: infra instance, canonical DOMAIN/ROOT_URL host;
#   no trailing slash, dev-slice shape; NEVER forgejo.spencerslab.com — §R3 live TLS failure)
helm dependency update charts/forgejo-runner          # app-template dep is an https repo (not OCI)
helm template forgejo-runner-gpu charts/forgejo-runner -f /tmp/opencode/runner-gpu-slice.yaml \
  --set runner.url=https://git.spencerslab.com
# assert: exactly one SA/STS/Service/ExternalSecret named forgejo-runner-gpu,
#         no Deployment; replicas 1; VCTs data 2Gi + docker-data 10Gi RWO
#         local-path (gpu default SC — no override needed, Authority);
#         config.yaml labels map == ACT_LABELS (post-C04 set);
#         ExternalSecret remoteRef key == the UUID from the slice (no OVERRIDE_*);
#         NO `http://dev-forgejo-http` or `http://infra-forgejo-http` anywhere
#         (in-cluster URLs dead on gpu) and NO `forgejo.spencerslab.com` (banned alias).
helm template gpu services/gpu/prod -f custom-values/gpu/prod-values.yaml \
  --set domain=spencerslab.com --set clusterName=gpu | grep -c OVERRIDE_   # BASELINE 1 (measured this round: legacy OVERRIDE_VIA_CLUSTER_ANNOTATION trio on one values-JSON line) — must stay 1
bash tests/services/gpu-forgejo-runner.sh             # NEW suite (agent-test), red until C05
grep -c 'gpu-forgejo-runner' custom-values/gpu/prod-values.yaml        # want >=1 (Q15 answer: the new item is named in the comment)
grep -c 'dev-forgejo-prod-runner' custom-values/gpu/prod-values.yaml   # want 0 (that item stays reserved for the infra relocation)
git diff main -- services/dev custom-values/dev | grep -cE '^[+-].*forgejo-runner'   # want 0 — dev runner trio/comments byte-untouched

# ---- sentinel sweep (baselines are pinned, not 0) ----
helm template dev services/dev/prod -f custom-values/dev/prod-values.yaml \
  --set domain=scifi.farm --set clusterName=dev | grep -c OVERRIDE_          # BASELINE 1
helm template infra services/infra/prod -f custom-values/infra/prod-values.yaml \
  --set domain=spencerslab.com --set clusterName=infra | grep -c OVERRIDE_   # BASELINE 0
# The dev 1 is the pre-existing home-assistant.bitwardenIds wart inside the
# ApplicationSet values JSON. The new legs must keep both counts unchanged AND
# hold the forgejo Application's values JSON free of OVERRIDE_*.
grep -rn 'OVERRIDE_NEEDED' custom-values/dev custom-values/infra   # must be empty for the forgejo slices (D11)

# ---- trio greps (nothing new; assert the existing legs survive) ----
grep -n 'forgejo' services/dev/prod/values.yaml            # charts.forgejo + ingress git
grep -n 'forgejo' services/infra/prod/values.yaml          # charts.forgejo + ingress git/forgejo + pre-existing s3
grep -c 's3' services/dev/prod/values.yaml                 # BASELINE 0 — no new dev storage route
git diff --name-only main -- charts/seaweedfs services/infra/prod/templates   # must be empty

# ---- workload surface (no new image literals, no new security posture) ----
# C04 swaps a job image inside the labels map (a `- <label>:docker://…` line,
# not an `image:`/`tag:` key — C05's runner reuses the chart's renovate-tracked
# pins 13.2.0 / 29.9.2-dind; the privileged dind sidecar is pre-existing chart
# posture, and no new capability/replica/resource literal is added anywhere):
git diff main -- charts/forgejo charts/forgejo-runner | grep -cE '^\+.*(image:|tag:|securityContext|capabilities|privileged|resources:|replicas)'   # want 0

# ---- regression (baselines pinned from measurement — pre-existing reds are NOT this ticket's) ----
bash tests/services/infra-forgejo.sh      # baseline exit 0 / 33 ok
bash tests/services/dev-git-auth.sh       # baseline exit 0 / 36 ok
bash tests/services/dev-forgejo-runner.sh # BASELINE exit 1 / 27 ok (t5 false positive — do not chase; transitions per the C04 block above)
bash tests/services/forgejo-ssh-gateway.sh      # BASELINE exit 1 / 63 ok (t1 tracked storm-runs/; its t11 re-runs the runner suite and stays red for the same reason)
bash tests/services/forgejo-ssh-audit-trail.sh  # BASELINE exit 1 / 0 ok (same cause)
bash tests/multi-repo/dev-wiring.sh       # baseline exit 0 / 9 ok (measured this round — its :252-253 leg is the forgejo-runner-dev comment citation)
bash tests/services/gpu-coder-sso.sh      # gpu-suite regression baseline — record measured exit/ok at test-writing time (untouched by this ticket)

# ---- live LFS route oracle (before-state: 404; after dev sync: non-404 LFS JSON) ----
# Read-only POST from any session (this worktree is itself a gpu-cluster pod, §R7):
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Accept: application/vnd.git-lfs+json' -H 'Content-Type: application/vnd.git-lfs+json' \
  -d '{"operation":"upload","transfers":["basic"],"objects":[]}' \
  https://git.scifi.farm/CuratedForest/SpencersLab.git/info/lfs      # dev host  — 404 until C02 is synced
# infra host (https://git.spencerslab.com/CuratedForest/SpencersLab.git/info/lfs) stays 404 until C03 is synced
# An enabled endpoint answering 401 unauthenticated is an UNVERIFIED upstream
# hypothesis (§R3) — record whatever it actually returns as the new baseline.

# ---- quality gate ----
npx --yes aislop@0.18.1 ci --changes --base main   # YAML/MD are outside its scoring; comment-slop + review carry comments
```

### Test contract (agent-test writes, one session before any dev)

**A. `tests/services/forgejo-lfs.sh`** (new) — numbered legs, the repo's
harness conventions (`tests/services/infra-forgejo.sh:1-30`: helm discovery via
`HELM_BIN`/PATH/`~/.local/bin`/`/tmp/opencode` or a v3.21.4 download; chart
copied to `/tmp/opencode` so the worktree is never written; helm legs **skip**,
not fail, when the OCI registry is unreachable).

| leg | Asserts | Red until |
|---|---|---|
| t1 | harness: `helm dependency update` of a copy succeeded (or the whole leg set skips with a note) | — |
| t2 | chart-level inert guard: `[lfs]` section exists, equals exactly `MINIO_BUCKET=git-lfs`, `MINIO_BUCKET_LOOKUP=path`, `MINIO_CHECKSUM_ALGORITHM=default`, `SERVE_DIRECT=false`, and **no** `STORAGE_TYPE`; no `storage`/`attachment`/`picture` section | C01 |
| t3 | `ExternalSecret/forgejo-s3-secret`: `bitwarden-login` store, `remoteRef.key` = the `forgejo-s3` id, `access_key_id ← username`, `secret_access_key ← password`, the three boilerplate fields, `creationPolicy: Owner` | C01 |
| t4 | `init-app-ini` env carries exactly 4 legs; the two LFS ones name secret `forgejo-s3-secret` keys `access_key_id`/`secret_access_key`; the DB and SECRET_KEY legs still present | C01 |
| t5 | dev effective render: `[lfs]` = the 7 keys with endpoint `s3.spencerslab.com`, `MINIO_USE_SSL=true`; `[server] LFS_START_SERVER=true` | C02 |
| t6 | infra effective render: same with `seaweedfs-s3.default.svc.cluster.local:8333` and `MINIO_USE_SSL=false` | C03 |
| t7 | parity: both instances resolve `MINIO_BUCKET=git-lfs` + `MINIO_BUCKET_LOOKUP=path` (path-style; the virtual-host form would break TLS on `git-lfs.s3.…`) | C01 (partially) |
| t8 | both custom-values carry a UUID-shaped `bitwardenIds.forgejo-s3` — no `OVERRIDE_*`, no `OVERRIDE_NEEDED` (the init-container dependency, D11) | C02, C03 |
| t9 | sentinel sweep at the pinned baselines (dev 1, infra 0) and zero `OVERRIDE_*` inside the forgejo Application's values JSON | C02, C03 |
| t10 | trio: `charts.forgejo` still present in both appsets, `git`/`forgejo` proxy legs still point at `<c>-forgejo-http:3000`, `services/dev/prod/values.yaml` still has zero `s3` mentions (no new storage route) | — (regression) |
| t11 | blast radius: `charts/seaweedfs/values.yaml` untouched (`s3.enableAuth` still commented), no `-s3.config` anywhere, no bucket/`weed` Job introduced in `services/**` | — (regression) |

**B. `tests/services/dev-forgejo-runner.sh`** (extended, not replaced) — two
edits, both by agent-test, both before any dev:

1. **Red-first `ACT_LABELS` edit (C04's swap):** the `node22` entry in the
   hard-coded 5-set (`:252-258`) becomes
   `'node22:docker://ghcr.io/catthehacker/ubuntu:act-24.04'`. From that moment
   t2 (`:461`) is red until C04 lands — that IS the red-first state, the
   suite's stop moves from t5 to t2 meanwhile (see the Commands baseline
   transitions). Only that entry changes; `CHART_DEFAULT_URL` (`:260`) and the
   t5 window (`:725-730`) stay byte-identical.
2. **Leg t14, physically placed after the t4 block and before t5** (the suite
   stops at its first failing leg and t5 stays red — an appended leg would
   never run). t14 asserts the LFS-capability record in
   `charts/forgejo-runner/templates/secret-runner.yaml` beside the labels
   block — wording leg in the established style (t5 comment window, t11 cf-97
   wording): act images ship git-lfs (installer-pin caveat included) and Node
   20/24, `node22` now maps to an LFS-capable image (and no longer guarantees
   Node 22 — Q14), the daemon needs no LFS, and the HTTPS/`[lfs]`-server-side
   coupling. t14 asserts the record only — it must **not** re-assert the labels
   map (t2 owns `ACT_LABELS` at `:461`) and must not widen the t5 window. Red
   until C04.

**C. `tests/services/gpu-forgejo-runner.sh`** (new, C05; named per the
`gpu-coder-sso.sh` precedent, R4) — same harness conventions; legs:

| leg | Asserts | Red until |
|---|---|---|
| g1 | harness: `helm dependency update` of a copy of `charts/forgejo-runner` (app-template 5.0.1 from the https repo) — skip-not-fail when the repo is unreachable | — |
| g2 | standalone render (extracted `forgejo-runner-gpu` slice + `--set runner.url=https://git.spencerslab.com`): exactly one SA/STS/Service/ExternalSecret named `forgejo-runner-gpu`, no Deployment; replicas 1; VCTs data 2Gi + docker-data 10Gi RWO `local-path`; config.yaml labels map == the (post-swap) `ACT_LABELS` set | C05 |
| g3 | the SERVICES file carries the **top-level** `forgejo-runner-gpu:` slice with `runner.url` exactly `https://git.spencerslab.com` (infra instance — Q13 answer), and neither `http://dev-forgejo-http`/`http://infra-forgejo-http` (in-cluster URLs are dead on gpu, §R5) nor `forgejo.spencerslab.com` (banned alias, §R3 live-TLS failure) appears anywhere in the gpu slice or render | C05 |
| g4 | `charts:` entry `forgejo-runner-gpu` with `chart: forgejo-runner`, `namespace: default`, `ServerSideApply: "false"`, **plus a trio-exemption comment** naming the N/A proxy leg "by design, not an oversight" (client-only/dial-out), and gpu `ingress.subdomains` gains NO runner entry | C05 |
| g5 | `custom-values/gpu/prod-values.yaml` `forgejo-runner-gpu.bitwardenIds.runner-token` is UUID-shaped — no `OVERRIDE_NEEDED`/placeholder (an empty or non-UUID id crashloops the daemon: `'uuid' is empty`); its comment names the **`gpu-forgejo-runner`** item (Q15 answer) and the reserved `dev-forgejo-prod-runner` UUID appears nowhere under `custom-values/gpu` | C05 |
| g6 | gpu umbrella sentinel sweep at the **pinned baseline 1** (measured: legacy `OVERRIDE_VIA_CLUSTER_ANNOTATION` trio on one values-JSON line) and zero `OVERRIDE_*` inside the `forgejo-runner-gpu` Application's values JSON | C05 |
| g7 | blast radius: dev runner trio and comments byte-untouched (`git diff` shows no `±.*forgejo-runner` line under `services/dev`/`custom-values/dev`), `services/gpu/prod/values.yaml` `charts.forgejo` still absent (no gpu Forgejo), `charts/forgejo-runner/**` untouched by C05 (C04 owns it) | — (regression) |

## User actions (never chunks)

### Blocking, before the merge

**UA1 — Inventory the gateway's existing IAM + buckets** (tells us which store
Loki's identity lives in and whether `/buckets/git` surfaces as a bucket;
RESEARCH OQ1/OQ2):

```bash
kubectl -n default exec -it statefulset/seaweedfs-master -- weed shell
# if the shell cannot reach the filer from the master pod, use the filer pod and
# point at the master instead:
#   kubectl -n default exec -it statefulset/seaweedfs-filer -- \
#     weed shell -master=seaweedfs-master.default.svc.cluster.local:9333
s3.config.show        # counts + brief listing of users/policies/groups
s3.user.list          # who writes to this gateway today (Loki?)
s3.bucket.list        # does `logs` / `git` appear?
s3.iam.export         # full JSON (do NOT paste values into the ticket)
```

**UA2 — Create the identity** (4.50 grammar verified at tag `4.50`: `-name`
only; there is **no** `-access` flag on `s3.user.create`):

```
s3.user.create -name forgejo-lfs
# access key id prints to stdout, the secret key to stderr only — capture both
```

**UA3 — Create the bucket owned by it, then the bucket-scoped grant** (Q9
answer — owner grant, self-healing `MakeBucket`, D7):

```
s3.bucket.create -name git-lfs -owner forgejo-lfs
s3.bucket.access -name git-lfs -user forgejo-lfs -access Read,Write,List,Admin
s3.bucket.access -name git-lfs -user forgejo-lfs      # re-read to confirm the grant
s3.bucket.list                                        # git-lfs appears, owned by forgejo-lfs
```

`Read` covers the HeadBucket at boot; `Write` covers object PUT/DELETE and the
whole multipart flow; `Admin` (stored as `Admin:git-lfs`, matched per bucket)
is what lets Forgejo's `MakeBucket` recreate a missing bucket instead of
`log.Fatal` — and costs full control of *that one bucket* (delete, policy,
encryption subresources). `List` is operator tooling. `s3.user.provision
-bucket git-lfs -role readwrite` is **not** the primary path: its attached-
policy role map's coverage of the PutBucket route is unverified (Authority
table), whereas the explicit grants above deterministically land the identity
on the legacy-actions route.

**UA4 — Bitwarden item**, then report the UUID to the pipeline (C02/C03 paste
it): item `forgejo-s3` (Login: username = access key id, password = secret
access key), one item for both instances (Q3). Real UUID only —
`OVERRIDE_NEEDED` is forbidden for this key (D11).

**UA5 — Create the gpu runner's server-side record on the INFRA instance**
(`git.spencerslab.com` — Q13 answer). Instance-level Actions runner record
(same shape as `dev-forgejo-dev-runner`, per
`charts/forgejo-runner/templates/NOTES.txt`): create it **persistent**, capture
the uuid + registration token. The single registration maps to exactly one
pod — never scale the gpu STS past 1. Timing: the record may exist early
(harmless — a registered runner takes no jobs until its pod runs), but per
rollout step 7 the **pod sync waits for C03**.

**UA6 — Bitwarden item for the pair**, then report the UUID to the pipeline
(C05 pastes it): **new** Login item `gpu-forgejo-runner` (Q15 answer —
one-item-per-concern naming), username = runner uuid, password = runner token.
The reserved `dev-forgejo-prod-runner` item stays untouched for the infra
runner relocation. Real UUID before any C05 commit — the daemon fail-fasts
(`'uuid' is empty`) and crash-loops without it.

**PF0 — Confirm there is nothing to migrate** (sanity check on the D9
assumption):

```bash
kubectl -n default exec -it deploy/dev-forgejo -c forgejo -- \
  sh -c 'ls -la /data/lfs 2>/dev/null || echo "no LFS dir — nothing to migrate"'
```

**PF1 — Pre-flight of the exact boot path, dev endpoint** (user-run; agents
have no pod exec):

```bash
kubectl -n default exec -it deploy/dev-forgejo -c forgejo -- sh -c \
  'forgejo migrate-storage --type lfs --storage minio \
     --minio-endpoint s3.spencerslab.com --minio-use-ssl \
     --minio-bucket git-lfs --minio-base-path lfs/ \
     --minio-access-key-id "$FJ_LFS_AK" --minio-secret-access-key "$FJ_LFS_SK"'
```

Pass the credentials as already-exported shell variables (argv is readable via
`ps`). No `--minio-checksum-algorithm` flag: the default equals the shipped
`default` (D16). Success means the client reached the gateway, the versioning
probe and HeadBucket passed, and the bucket is writable; it also migrates any
existing objects (expect zero — PF0). With the D7 grant a missing bucket
self-heals here (the tool runs the same `MakeBucket`) — do **not** rely on
that to skip UA3: owner and placement are set at creation. A `403`/
`AccessDenied` here is the same failure that would take the instance down
after the merge, and it is cheap to fix now. There is no
`--minio-bucket-lookup` flag (RESEARCH §Q1) — `auto` resolves path-style for
this endpoint, so the pre-flight matches the shipped config. If the CLI is not
on PATH in that container, use `/usr/bin/forgejo`; the container already
exports `GITEA_APP_INI`/`GITEA_CUSTOM`, so the flags alone define the target.

**PF2 — Same pre-flight for infra** (Q8: C03 rides the branch; run this before
the sync that restarts infra): identical command from `deploy/infra-forgejo -c
forgejo` with `--minio-endpoint
seaweedfs-s3.default.svc.cluster.local:8333` and without `--minio-use-ssl`.

### Post-sync verification (agent-readables marked; the rest are human)

**V1 — Boot-log oracles** (agent-readable via `readonly-{dev,infra}-kubernetes`
`pods_log`): `Initialising LFS storage with type: minio` and
`Creating Minio storage at <endpoint>:git-lfs with base path lfs/`
(RESEARCH §7); no `log.Fatal`, pod Ready, no `CreateContainerConfigError` (the
D11 secret dependency).

**V2 — Byte-level round trip (human)** — the Forgejo×SeaweedFS pair is not in
Forgejo's upstream-tested list (contradiction C3). Run in a throwaway repo on the
forgejo instance under test — **not** in this SpencersLab worktree:

```bash
git init lfs-probe && git -C lfs-probe remote add origin <forgejo-remote-url>
cd lfs-probe && git lfs track "*.bin" && dd if=/dev/urandom of=big.bin bs=1M count=20   # >16 MiB ⇒ the multipart path
git add .gitattributes big.bin && git commit -m lfs && git push -u origin main
git lfs ls-files -s                                                    # OID+size
# fresh clone elsewhere:
git clone <forgejo-remote-url> verify && sha256sum verify/big.bin      # must match
```

**V3 — Object placement (human, read-only)**: `weed shell` →
`fs.ls -l /buckets/git-lfs/lfs` (positional path, not `-dir`) or the filer UI
shows the OID-sharded objects; nothing under `/buckets/git`.

**V4 — ArgoCD**: the two Applications sync (selfHeal on), the `forgejo-s3-secret`
ExternalSecret reports `SecretSynced`, and the pods restarted once. Sync and
merge are user-owned; the pipeline stops at "branch ready — commits local".

**V5 — LFS route flip (agent-readable)** — the batch endpoint probe above:
404 before sync (§R3, both hosts); after dev's sync the dev host must stop
answering 404 (expect 401/400 LFS JSON — record the actual code as the new
baseline; the 401 figure is an unverified upstream hypothesis). This is the
cheap server-side proof the runner's future LFS checkouts would ride on.

**V6 — Job-image LFS proof (human)** — settles the installer-pinned claim
(EXPLORE §R2b caveat: the tags' `BUILD_REF` label is unsubstituted) on any lab
host with a docker daemon, no workflow needed:

```bash
docker run --rm ghcr.io/catthehacker/ubuntu:act-24.04 git lfs version   # expect a version (also the node22 image post-C04)
docker run --rm ghcr.io/catthehacker/ubuntu:act-22.04 git lfs version   # expect a version
docker run --rm docker.io/library/node:22-bookworm git lfs version      # expect "not found" — the pre-swap negative control C04 removes
docker run --rm ghcr.io/catthehacker/ubuntu:act-24.04 node -v           # Q14 caveat check: expect v20/v24, NOT v22
```

**V7 — gpu runner registration (agent-readable + human)** — after the C05
sync (which rollout step 7 gates behind C03): `pods_log({name:"forgejo-runner-gpu-0", namespace:"default"})` on
**gpu** shows the `runner: … declared successfully` line with the labels list
(§R7 oracle); the UA5 registration shows **online** on the **infra**
instance's Actions runners view (human — the API needs a token). A `connection
"default" is invalid` or repeated re-register loop = uuid/token mismatch
(UA5↔UA6 pairing) or the slice URL pointing at the wrong instance — the
record lives on infra (`git.spencerslab.com`), so the slice must too.

## Risks / assumptions

- **Boot-fatal coupling (highest, narrowed by D7).** `routers/init.go:117
  mustInit(storage.Init)` → `log.Fatal`. Still fatal at boot: an identity
  without `Read` on the bucket (HeadBucket gate), an unreachable endpoint, or a
  wrong secret (inside the 30 s storage-init ceiling). **No longer fatal: a
  missing bucket** — the Q9 owner grant (`Admin:git-lfs`) makes Forgejo's
  `MakeBucket` recreate it (D7). UA2–UA3 + PF1 still exist to move the fatal
  modes out of production. dev and infra are separate Applications, so a bad
  infra config costs infra's git, not dev's.
- **Self-heal flip side (new with D7).** A deleted `git-lfs` bucket comes back
  **empty** at the next restart: the instance boots fine, every stored LFS
  object silently 404s. The loud failure mode was traded for a quiet data-
  availability one — V3/V5 catch it; treat bucket deletion as a data incident,
  not a config fix.
- **Grant width cost (D7).** `forgejo-lfs` is effectively owner-full-control on
  `git-lfs`: object RW + delete, `DeleteBucket`, bucket policy / encryption /
  public-access-block subresources (all match `Admin:git-lfs` in `CanDo`). It
  cannot touch `logs`, `git` or any future bucket (grants are per-bucket
  strings). A leaked credential is scoped to the LFS bucket.
- **Init-container secret dependency (new failure mode this ticket
  introduces).** `additionalConfigFromEnvs` puts the credential `secretKeyRef` on
  `init-app-ini` and the Deployment; if `forgejo-s3-secret` does not exist, pods
  cannot start at all. Hence D11 (real UUID before sync) and leg t8.
- **Single point of failure.** `seaweedfs-s3` is a 1/1 Deployment on infra and
  dev reaches it through infra's Traefik route: dev's LFS availability inherits
  both. Accepted at lab scale; the in-cluster endpoint on infra keeps one hop out
  of the picture.
- **Unsupported combination.** Forgejo's docs test MinIO and garage, not
  SeaweedFS (C3). V2 is the real acceptance; renders and ExternalSecrets prove
  the config, not the byte path.
- **dev → public endpoint reachability** is proven for the lab (DNS →
  `10.0.77.59`, 22 ms round trip from a cluster with no gateway, Loki on
  monitoring writes through the same route, no NetworkPolicy selects forgejo pods)
  but is **not** proven from a dev-cluster pod (RESEARCH OQ7). V1 closes it
  cheaply at the first restart.
- **TLS trust** for dev's HTTPS endpoint: `wildcard-cert` is Let's Encrypt
  (`charts/base/templates/cert-manager-issuer.yaml`), so the stock root store in
  the forgejo image is enough; no CA bundle work.
- **Timeout bound, not a body-size limit**: Traefik configures no `buffering`
  middleware, so no 413; the `websecure` `readTimeout: 600s` bounds one
  client→Forgejo LFS PUT per object. Forgejo→gateway requests stay at 16 MiB
  parts. Q7 answer: unlimited, the bound stays documentation.
- **Placement assumption**: the new bucket inherits the filer default replica
  placement (`001`), not the `002` the idle `git` PV declared; 4.50 has no
  per-bucket replication command (verified). Q5 answer accepts this.
- **Rollback after the first write is a data decision, not just a revert**:
  reverting `[lfs]` to local storage leaves objects already in S3 unreadable
  (RESEARCH §6's "no data action" holds only before the first LFS write). Revert
  = `git revert` the custom-values commit → ArgoCD re-renders local storage; any
  objects already written need `migrate-storage` back to local, or they are
  orphaned. Recorded so the user's merge decision is informed.
- **Chart `appVersion: 15.0.9` is cosmetic** (EXPLORE §1) — do not "fix" it; the
  pulled subchart pins `15.0.10`. Wrapper `version: 1.0.7` is CI-bumped.
- **Config precedence subtlety handled by design**: `[lfs]` carries every key, so
  `[storage]` inheritance never comes into play; the env-var credentials land in
  the same section (`decodeEnvSectionKey` lower-cases the section name).
- **C04 has a live effect (changed at r3):** swapping the `node22` label image
  rewrites the runner `config.yaml` Secret, and the pod carries
  `reloader.stakater.com/auto: "true"` — the dev runner pod **restarts** on the
  next sync. Harmless (idle runner; jobs re-queue) but say so in the RESULT.
  In-job dependencies beyond the image (job networking/DNS, checkout-token
  LFS scope, checkout action `lfs:` default, §R6) stay unproven by the Q11
  answer; V5/V6 settle the settleable parts.
- **gpu runner dials out (C05).** Registration and job clones ride the infra
  instance's **public** route (`git.spencerslab.com` → infra Traefik LB
  10.0.77.59, §R3), not an in-cluster service: availability inherits infra's
  ingress and crowdsec posture — and gpu's coderd already authenticates
  against this **exact host** in production (`services/gpu/prod/templates/
  secrets-coder.yaml:31-42`), so the reachability pattern is same-host
  precedent, not hope. A cold `act-24.04` pull on gpu's nodes also re-exposes
  the k3s-MTU / forgejo-runner#1779 clone-failure risk the chart itself flags
  (`charts/forgejo-runner/values.yaml:27-31`) — watch the first job; no config
  re-plan up front.
- **Half-capable gpu runner if sync order slips (C05×C03).** Serving infra
  (Q13) means the runner's LFS clones depend on infra's LFS, which activates
  only in C03; rollout step 7 gates the gpu sync behind C03. A sync that
  jumps the gate yields a runner that registers and clones plain repos fine
  but fails LFS fetches (batch endpoint 404, §R3 before-state) — pin V5-on-
  infra as the precondition, and g-suite/RESULT must say so.
- **One record == one pod.** The gpu STS stays at 1 replica (chart decision
  B1); scaling the gpu runner means a new UA5 record + UA6 item, not replicas.
- **`node22` label semantics shifted (Q14).** The label name promises Node 22;
  `act-24.04` ships Node 20/24 (source-verified). Acceptable while no workflow
  consumes Actions; the honest record lives in the chart comment + Q14.
- **Test-coupling landmines (pinned, do not touch).** The runner suite stops at
  its first failing leg and t5 is red on main (cf-93 comment in the scan
  window) → t14 must be placed before t5; `forgejo-ssh-gateway.sh` t11 re-runs
  the runner suite expecting exit 0 and stays red for the same pinned reason;
  `tests/multi-repo/dev-wiring.sh:252-253` fails if the mosquitto comment in
  `services/dev/prod/values.yaml` loses its `forgejo-runner-dev` citation — this
  ticket does not touch that file, keep it that way.

## Follow-ups (not this ticket)

- Renovate coverage for the runner **job-image** label lines (a custom-manager
  regex for `- <label>:docker://…` in `charts/*/templates/` — today's manager
  yields 0 hits, §R5) so act-image bumps stop being manual.
- **Q14b follow-up (user's "26?")**: registry-vet a newer/Node-26-capable
  LFS-bearing job image. Facts pinned this pass: `act-26.04` is not published
  yet (upstream matrix already lists `26.04` — worth re-checking when it
  lands, but it would still ship Node 20/24 until upstream changes the ARG);
  a true Node-26+git-lfs image needs vetting outside the act family. C04's
  `act-24.04` stands this ticket.
- If Actions gets used for real: an `agent-research` round (checkout token
  scope, `lfs:` input default, §R6) before any behavioural runner work (Q11
  answer deferred this, deliberately).
- Infra runner relocation (`forgejo-runner-infra` re-wire via the reserved
  `dev-forgejo-prod-runner` item) stays deferred from the previous tickets —
  untouched by this ticket: Q15's new-item answer (`gpu-forgejo-runner`)
  keeps that vault item free for the relocation.
- SeaweedFS chart `4.50.0` → `4.52.0` (`dep` ticket; carries the #12177 fix plus
  ~217 other PRs — its own validation).
- Tighten gateway IAM if the `List` grant turns out unnecessary for Forgejo (it
  never lists; `List` is operator tooling only), or if attached-policy shapes
  (provision roles) are proven to cover PutBucket.
- `SERVE_DIRECT=true` evaluation: moves gateway reachability to every git client
  and needs 5-minute presigned URLs — out of scope, deliberately.
- Attachments/avatars/packages to S3 (`[storage]` + `'storage.packages'`) — a
  separate decision with a much bigger blast radius.
- Quota `size:git:lfs` (`[quota] ENABLED=false` today) if LFS growth needs
  bounding.
- Fix the pre-existing red suites (the tracked `storm-runs/` at the repo root
  re-trips `forgejo-ssh-gateway.sh` t1 and `forgejo-ssh-audit-trail.sh` t1) and
  the `dev-forgejo-runner.sh` t5 false positive (cf-93's "both" comment now sits
  inside the scan window) — hygiene ticket; until then the pinned baselines in
  Commands govern.
- Renovate coverage for the OCI `forgejo-helm` dependency (carried from the
  infra/runner ticket's follow-ups).
