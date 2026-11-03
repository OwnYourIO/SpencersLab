# RESEARCH.md — cf-104 Add LFS support to Forgejo

Written by `agent-research` 2026-11-02→03 (research round requested by card #104's
`Research: Before Planning` answer; scope = the four decision-changing unknowns the coord
named, not a re-litigation of the card body's Oct-2026 briefing).

Method: STORM (`.agents/skills/storm`) run with 5 perspectives (Forgejo internals, SeaweedFS
gateway operator, Git-LFS protocol path, GitOps/secrets, hardening). Because every question
is version-exact against this fleet's pins (Forgejo image `15.0.10-rootless`, wrapper chart →
`forgejo-helm` **17.3.1**, SeaweedFS upstream chart **4.50.0** / image `4.50`), the decisive
evidence is **source code read at the pinned tags** plus **two live fleet probes**, with docs
and wikis used as corroboration. Code at a pinned tag outranks prose; every disagreement is
listed in §Contradictions. Audit trail (`perspectives.md`, `sources.tsv`, `contradictions.md`,
`outline.md`) is at `/tmp/opencode/storm-trail/forgejo-15-lts-lfs-object-storage-on-seaweedfs-s3-gateway-cf/`
(worktree-local `storm-runs/` was moved out of the repo so the only repo artifact is this file).

Evidence shorthand: `FJ v15.0.10 <path>:<line>` = file read from tag `v15.0.10`;
`SW 4.50 <path>:<line>` = file read from tag `4.50`; `LIVE` = read-only probe 2026-11-02/03;
`RENDER` = `helm template` of `charts/forgejo` with the pinned OCI dep (17.3.1) in `/tmp/opencode/fjrender`.

---

## TL;DR (5 lines)

1. **Every `[lfs]`/`[storage]` key in the launch question exists in Forgejo 15.0.10** — both
   `MINIO_BUCKET_LOOKUP` and `MINIO_CHECKSUM_ALGORITHM` are in the struct with ini tags; no
   version caveat applies to this pin. `[server] LFS_START_SERVER` defaults **false**; the
   chart already auto-generates `server.LFS_JWT_SECRET`, so no secret work is needed there.
2. **SeaweedFS #12177 does not bite this stack.** Forgejo's minio-go v7.0.99 client is built
   **without `TrailingHeaders`**, so it never sends `x-amz-checksum-*`; SeaweedFS 4.50's
   faulty comparison sits behind a gate keyed on the algorithm recorded at
   CreateMultipartUpload, so it is never reached. The fix (PR #12194) shipped in **4.52**
   (released 2026-11-02, chart `4.52.0` same day) if belt-and-braces is wanted. Do **not**
   downgrade to 4.46.
3. **The gateway already enforces S3 auth** — live probe: unauthenticated → `403 AccessDenied`,
   SigV4 with a bogus key → `403 InvalidAccessKeyId`, despite no `-s3.config` in the pod args.
   Credentials are **mandatory**, and the identity store is the out-of-band filer-backed
   credential store (`identity.json`), not GitOps. This resolves card OQ3 and reverses
   EXPLORE §3.2's assumption.
4. **Section-placement trap that would silently break the rollout:** a section that declares
   `STORAGE_TYPE = minio` *is* the target section — `[lfs]` never inherits `[storage]`
   credentials (only `SERVE_DIRECT`/`MINIO_BASE_PATH`/`MINIO_BUCKET` override). The chart's
   own doc example (`lfs.STORAGE_TYPE` + creds under `storage:`) contradicts the code. Also
   the code default `MINIO_BUCKET` is **`gitea`**, not the documented `forgejo`.
5. **Rollout is not zero-risk:** `routers/init.go:117 mustInit(storage.Init)` → `log.Fatal`, so
   a bad/unreachable S3 config takes down the whole Forgejo web process, not just LFS.
   Ordering rule: create the bucket **and** the SeaweedFS identity with bucket-scoped actions
   (`Read` is needed for the HeadBucket Forgejo does at startup) **before** the Forgejo config
   lands — Forgejo's own `MakeBucket` fallback needs `Admin`, so it cannot self-heal a missing
   bucket.

---

## Q1 — Forgejo 15.0.10 `[lfs]` / `[storage]` key set and semantics

**The complete, version-exact key set.** `MinioStorageConfig` at FJ v15.0.10
`modules/setting/storage.go:34-47` declares exactly eleven keys with ini tags:
`MINIO_ENDPOINT`, `MINIO_ACCESS_KEY_ID`, `MINIO_SECRET_ACCESS_KEY`, `MINIO_BUCKET`,
`MINIO_BUCKET_LOOKUP`, `MINIO_LOCATION`, `MINIO_BASE_PATH`, `MINIO_USE_SSL`,
`MINIO_INSECURE_SKIP_VERIFY`, `MINIO_CHECKSUM_ALGORITHM`, `SERVE_DIRECT`. **Both keys the
coord asked about exist in 15.0.10** — `MINIO_BUCKET_LOOKUP` (added upstream Mar 2024, PR
#2482 / docs PR #465) and `MINIO_CHECKSUM_ALGORITHM` (older; docs backport label `v7.0`) both
predate 15.x and both appear in the v15.0 docs table with defaults. [S1][S4]

Defaults as the code sets them (`getDefaultStorageSection`, storage.go:70-85):
`STORAGE_TYPE=local`, `MINIO_ENDPOINT=localhost:9000`, `MINIO_BUCKET=`**`gitea`**,
`MINIO_BUCKET_LOOKUP=auto`, `MINIO_LOCATION=us-east-1`, `MINIO_USE_SSL=false`,
`MINIO_INSECURE_SKIP_VERIFY=false`, `MINIO_CHECKSUM_ALGORITHM=default`. `SERVE_DIRECT` is a
Go bool → default `false`. The v15.0 docs page agrees on all of these **except** the bucket
default, which it prints as `forgejo` (contradiction C2). [S1][S4]

Validation is strict and fails the storage init, not the render: an unknown
`MINIO_CHECKSUM_ALGORITHM` (anything but `""`/`default`/`md5`) or an unknown
`MINIO_BUCKET_LOOKUP` (anything but `auto`/`dns`/`path`) returns an error from
`NewMinioStorage` (minio.go:88-99). [S5]

**The S3 handshake at storage init decides the rollout order.** `NewMinioStorage` runs under a
hard 30 s ceiling (`initializationTimeout`, minio.go:79/:83) and does three calls before the
process is usable: `GetBucketVersioning` (minio.go:120) — only an HTTP 400 aborts init, 403/404
are explicitly tolerated (the code comment notes it needs bucket "owner" to really succeed);
then `BucketExists` (HeadBucket, minio.go:133) where **any error is returned as fatal**; then
`MakeBucket` if the bucket is missing (minio.go:139). Two consequences the plan must respect:
the identity needs read permission on the bucket *just to boot* (SeaweedFS gates HeadBucket on
the `Read` action — §Q3 action matrix), and the auto-`MakeBucket` leg cannot work with a
least-privilege identity (SeaweedFS gates PutBucket on `Admin`), so a missing bucket turns into
a `log.Fatal`, not a self-healing create. [S5][S27]

**Object key layout.** LFS is subsystem `lfs`; the default base path is `lfs/`
(storage.go `getStorageForMinio`: `defaultPath = name + "/"`), so objects land at
`<bucket>/lfs/<oid-sharded path>`, matching the docs table (`LFS | lfs/ | [lfs]`).
`MINIO_BASE_PATH` is honoured in a subsystem section to relocate that prefix; the docs forbid
setting it in `[storage]` (the code in fact prefixes it, C7). [S1][S4]

**The precedence rule that the chart's example violates.** `getStorage(rootCfg, "lfs", "",
[lfs])` (FJ v15.0.10 `modules/setting/lfs.go:55`). Resolution in storage.go:145-205:

* If `[lfs]` declares `STORAGE_TYPE=minio` **and no `[storage.minio]` section exists** →
  `[lfs]` itself is the target section (`targetSecIsSec`) and *every* MINIO key is read from
  `[lfs]`; `[storage]` credentials are then irrelevant to LFS.
* If `[lfs]` declares no `STORAGE_TYPE` and `[storage]` does → `[storage]` is the target and
  `[lfs]` acts as the override section, which per `getStorageOverrideSection` **only** pulls
  `SERVE_DIRECT`, `MINIO_BASE_PATH`, `MINIO_BUCKET` (and `PATH` for local). Endpoint and
  credentials in `[lfs]` would be ignored in that shape.

So there are two coherent shapes and one broken mix (contradiction C1): (a) all keys inside
`[lfs]` (what the v15.0 docs' "single subsystem" example does), (b) all keys inside
`[storage]` with no `[lfs]` section at all — but (b) also switches attachments, avatars,
repo-avatars, repo-archives, packages, actions logs and artifacts to S3, i.e. far beyond this
ticket's scope. (c) the forgejo-helm `docs/ha-setup.md` shape (`lfs.STORAGE_TYPE: minio` +
credentials only under `storage:`) is the one the pinned chart documents and the one the code
does not support.

**Chart 17.3.1 surface, verified by render.** `gitea.config.lfs` and `gitea.config.storage`
exist as `additionalProperties: true` objects (values.yaml:665-675, values.schema.json), and
dotted section names (`'storage.packages'`) are legal. RENDER proof with
`--set forgejo.gitea.config.lfs.STORAGE_TYPE=minio --set forgejo.gitea.config.lfs.MINIO_BUCKET=git-lfs …`:
the `dev-forgejo-inline-config` Secret gains an `lfs` stringData key whose value is the
alphabetically-sorted `KEY=value` list (`MINIO_BUCKET=git-lfs`, `MINIO_BUCKET_LOOKUP=path`,
`MINIO_CHECKSUM_ALGORITHM=md5`, `MINIO_ENDPOINT=s3.spencerslab.com`, `MINIO_USE_SSL=true`,
`SERVE_DIRECT=false`, `STORAGE_TYPE=minio`), and `gitea.config.server.LFS_START_SERVER=true`
renders inside the existing `server` key. Booleans render via `printf "%v"` → literal
`true`/`false`, which Forgejo's ini parser accepts. This matches EXPLORE §2's call shape. [S36]

**The chart's "`MINIO_BUCKET` is not a bucket" note is a wording trap, not a semantic one.**
`docs/ha-setup.md` says: *"`MINIO_BUCKET` here is just a name and does not refer to a S3
bucket. It's the root access point for all objects belonging to the respective application."*
The code says `MINIO_BUCKET` **is** the S3 bucket name (minio-go `BucketExists`/`MakeBucket`/
`PutObject` all take it as the bucket), and `MINIO_BASE_PATH` (default `lfs/`) is the prefix
inside it. Read the note as "one bucket is shared by all Forgejo subsystems, with per-subsystem
prefixes", not as "this field is decorative". [S1][S5][S34]

**`LFS_START_SERVER` / `LFS_JWT_SECRET` on the rootless image.** Cheat sheet v15.0:
`[server] LFS_START_SERVER: **false**` → must be set `true`; `LFS_JWT_SECRET: <empty>` default,
"change this to a unique base64-encoded 32-byte value", generatable with
`forgejo generate secret LFS_JWT_SECRET`; v15 also has `LFS_JWT_SECRET_URI` (file-sourced
secret) plus `LFS_HTTP_AUTH_EXPIRY` (24h), `LFS_MAX_FILE_SIZE` (0 = unlimited) and
`LFS_MAX_BATCH_SIZE`. No rootless-specific handling exists: forgejo-helm
`scripts/config_environment.sh:134-136` unconditionally runs
`FORGEJO__SERVER__LFS_JWT_SECRET=$(gitea generate secret LFS_JWT_SECRET)` at init, and
`config_environment.sh:155-166` **drops those four secret envs whenever app.ini already
exists** ("safety to prevent rewrite of secret keys"). Both live instances therefore already
carry a generated `LFS_JWT_SECRET` in app.ini on the PVC, and a plan **cannot** override it
through `additionalConfigFromEnvs` on an existing instance (the env is unset before
`environment-to-ini` runs). Nothing to do; do not add an LFS JWT secret. [S3][S35]

**Env-var path for the credentials works as EXPLORE assumed.** `decodeEnvSectionKey` ends with
`section = strings.ToLower(section)` (FJ v15.0.10 `modules/setting/config_env.go:89`), so
`FORGEJO__LFS__MINIO_ACCESS_KEY_ID` lands in section `[lfs]` (not `[LFS]`) — ini sections are
otherwise case-sensitive (`configProviderLoadOptions()` sets no `Insensitive`). A
`…__FILE` suffix variant also exists (value read from a file path) if a mounted-file shape is
ever preferred. [S42]

**`migrate-storage` (user-run) shape for 15.0.10** (`cmd/migrate_storage.go:31-98`):
`migrate-storage --type lfs --storage minio --minio-endpoint … --minio-access-key-id …
--minio-secret-access-key … --minio-bucket … --minio-location … --minio-base-path …
--minio-use-ssl --minio-insecure-skip-verify --minio-checksum-algorithm default|md5`.
There is **no `--minio-bucket-lookup` flag** and no dry-run flag. Since it calls
`storage.Init()` itself (migrate_storage.go:209), it doubles as a **pre-flight check of the
target storage config** before any pod is touched. [S41]

---

## Q2 — SeaweedFS 4.50 exposure to the multipart `BadDigest` regression (#12177)

**Current status of the issue: fixed, closed, released.** #12177 opened 2026-10-28, closed as
completed 2026-10-29 by chrislusf, who opened PR #12194; the 4.52 release notes list it: *"s3:
accept bare composite checksum on CompleteMultipartUpload"*. Verified in code: tag `4.50`
`weed/s3api/filer_multipart.go:628` still has the unfixed comparison
`objectChecksum != checksumValue`; tag `4.52` line 628 calls
`!matchesObjectChecksum(objectChecksum, checksumValue)` with the helper defined at :1878.
Release ladder (GitHub releases API, read 2026-11-02): **4.52 published 2026-11-02T11:24Z**,
4.51 2026-10-25, 4.50 2026-10-25, 4.49 2026-10-23, 4.48 2026-09-28. Helm chart index:
`4.52.0` published 2026-11-02T16:43Z, then 4.51.0, 4.50.0, 4.49.0, 4.48.0, 4.47.0, 4.46.0
(2026-09-08). Image tags `4.52`, `4.52_full`, `4.52_large_disk` exist on Docker Hub. [S16][S17][S18][S19][S20][S21][S22]

**Does Forgejo's LFS save path reach the buggy code? No — three independent gates.**

1. *Client never sends object checksums.* `NewMinioStorage` builds the client with only
   `Creds`, `Secure`, `Transport`, `Region`, `BucketLookup` (minio.go:104-112) — **no
   `TrailingHeaders`**. minio-go v7.0.99 `api.go:310`:
   `clnt.trailingHeaderSupport = opts.TrailingHeaders && clnt.overrideSignerType.IsV4()`; and
   `api-put-object.go` (PutObject) only then does
   `opts.AutoChecksum.SetDefault(ChecksumCRC32C); addAutoChecksumHeaders(&opts)`. With
   `AutoChecksum` unset, `checksum.go:applyAutoChecksum` returns immediately and the per-part
   checksum block is skipped (`if opts.AutoChecksum.IsSet()`). So no
   `x-amz-checksum-algorithm` at CreateMultipartUpload and no composite checksum at Complete. [S5][S10][S11][S12][S14]
2. *Server gate is keyed on the recorded algorithm.* SW 4.50 `filer_multipart.go:129` stores
   `ExtChecksumAlgorithm` **only** when the CreateMultipartUpload request carried one;
   the whole validation region (lines 566-629, including the faulty line 628 and the
   `AmzChecksumType` check at :588) executes only `if checksumHeaderName != ""`. No header ⇒
   block never runs. [S19]
3. *Even the reporter's repro client differs.* #12177 reproduced with `mc` / minio-go
   v7.0.90 on **4.51**, and the reporter scopes it to uploads where minio-go auto-adds CRC32C
   ("`mc pipe`, or any unknown-size upload"). Forgejo always knows the LFS size:
   `ContentStore.Put` passes `pointer.Size` to `Save` (content_store.go:48-56), so the
   known-size `putObjectMultipartStream` path is used, not `putObjectMultipartStreamNoLength`. [S8][S16]

**Multipart boundary and what `md5` does / does not do.** minio-go constants:
`minPartSize = 16 MiB` (the single-PUT ↔ multipart switch), `absMinPartSize = 5 MiB`,
`maxPartsCount = 10000`; `PutObject` does a single PUT when `size <= partSize` and
`putObjectMultipartStream` above it, so LFS objects **>16 MiB do go multipart with 16 MiB
parts** — the briefing's threshold is right. `MINIO_CHECKSUM_ALGORITHM = md5` sets
`SendContentMd5: true` (minio.go:219), which adds a **`Content-MD5` per PUT/part** — it is
not an object-checksum header and does not change the single-PUT/multipart decision, so `md5`
is *not* a #12177 mitigation in either direction. Its real value is end-to-end corruption
detection: with `default`, minio-go over TLS sends no per-object digest at all. [S5][S12][S13]

**Which version to pin / fallback order.** No pin change is needed for LFS to work on 4.50.
Options in ascending preference: (a) **stay on 4.50.0** (this ticket) — the regression is
unreachable from Forgejo; (b) **bump the wrapper dep 4.50.0 → 4.52.0** as its own chore/dep
ticket (image `4.52` exists, chart published yesterday, and 4.52 also carries 216 other PRs —
treat as a separate change with its own validation, per "one branch one concern"); (c)
**do not roll back to 4.46** — the reporter's "worked on 4.46" is about a client behaviour
this stack does not exhibit, and downgrading a shared storage system that Loki writes to is a
larger risk than the bug it avoids. Chart `4.46.0` does exist in the repo index, so the
downgrade is technically available — it is simply the wrong trade.

---

## Q3 — Bucket vs filer-collection semantics, bucket creation, auth blast radius

**Bucket ≡ directory under the buckets folder.** Upstream flag/behaviour: `weed/command/s3.go:298`
defaults `filerBucketsPath = "/buckets"`, then asks the filer for `resp.DirBuckets` (:317) and
passes `BucketsPath` to the server (:383). `s3api_bucket_handlers.go` scans `/buckets` for
ListBuckets (`scanVisibleBuckets`, `bucketScanPageSize = 1000`). The repo's own chart comment
says it plainly: *"directories under this folder will be automatically creating a separate
bucket"* next to `WEED_FILER_BUCKETS_FOLDER: "/buckets"` (charts/seaweedfs/values.yaml:404).
So the CSI collections (`/buckets/git`, `/buckets/logs`, …) and S3 buckets are the **same
namespace** — a CSI-created collection is addressable as an S3 bucket. [S23][S24][S31]

**How a bucket comes into existence.**
* Forgejo *tries* to create it: `NewMinioStorage` calls `BucketExists` → if absent `MakeBucket`
  with `Region: MINIO_LOCATION` (minio.go:133-142), after a `GetBucketVersioning` probe that
  only aborts on HTTP 400. SeaweedFS 4.50 implements both routes
  (`s3api_server.go:1134` `?versioning`, `:1112` `?location`), so the probe will not misfire.
  But `MakeBucket` is the PutBucket route, which SeaweedFS gates on the `Admin` action
  (`s3api_server.go:1204`), and its own auto-create path carries the same rule
  (`ErrAutoCreatePermissionDenied … requires Admin permission`, `s3api_bucket_handlers.go:639-643`).
  So with a least-privilege identity **the bucket must exist before the config does** — otherwise
  Forgejo does not create it, it fails to boot. [S5][S24][S27]
* SeaweedFS auto-creates on upload: `-autoCreateBucket` **defaults true**, "create the bucket
  on upload if it does not exist, **for admin identities only**" (`weed/command/s3.go:128`;
  `autoCreateBucket` + `ErrAutoCreateDisabled` / `ErrAutoCreatePermissionDenied` in
  `s3api_bucket_handlers.go:639-830`). The wiki adds that `Admin:<bucket>` authorizes
  CreateBucket **and** implicit auto-creation, while a plain `Read/Write:bucket` identity
  cannot create it. [S23][S24][S28]

**Auth is already on — this is the biggest change to the plan's assumptions.** Live probes
(2026-11-02, from the Coder workspace, read-only):

| probe | result |
|---|---|
| `GET https://s3.spencerslab.com/` unauthenticated | `403 AccessDenied` (SeaweedFS XML, RequestId present) |
| same with SigV4, fabricated access key | `403 InvalidAccessKeyId` — signature machinery is running |
| `HEAD /git/`, `/logs/`, `/forgejo/` | `403` for all three (auth checked before existence) |
| live `Deployment/seaweedfs-s3` args + env | **no `-config`/`-s3.config`, no config volume, no `AWS_*` env** |
| live `StatefulSet/seaweedfs-filer` args | no `-s3.config` either |

Code explains it: `weed/s3api/auth_credentials.go:381-437` (assignment at :427) — the `-config` file is optional;
the gateway **always** merges identities from the credential manager ("Always try to
load/merge config from credential manager (filer/db)"), then sets
`iam.isAuthEnabled = identityCount > 0 || startConfigFile != ""`, with log lines
`"S3 authentication enabled (%d identities configured)"` / `"S3 authentication disabled - no
credentials configured (allowing all access)"`. The `Auth` middleware short-circuits only when
`isEnabled()` is false (`auth_credentials.go:1678-1697`). So at least one identity exists in
the filer-backed store — the wiki names its location and reload path (`… updated
/etc/seaweedfs/iam/identity.json`; `weed/credential/filer_etc/filer_etc_identity.go:19`
`IamLegacyIdentityFile = "identity.json"`), created out-of-band via `weed shell` or the admin
UI, and it is **not modelled anywhere in this repo**. [S26][S28][S29][S32]

Consequences: card **OQ3 is resolved — credentials are mandatory**, a credential-less Forgejo
would get `403` on every LFS read/write (and would fail storage init, see Q4). Also note the
one-way rule: once enabled, enforcement stays on for the process lifetime even if identities
are later removed. [S26][S28]

**Blast radius of touching auth at all.** Chart 4.50.0's `s3.enableAuth: true` path (repo has it
commented out at charts/seaweedfs/values.yaml:419-420) renders `-config=/etc/sw/seaweedfs_s3_config`
on the s3 Deployment, **also** flips `-s3.config` onto the **filer** StatefulSet via
`filer.s3.enableAuth` (chart comment: "need to inject to all services"), adds
`checksum/s3config` pod annotations (automatic rollout of s3 + filer), and — the sharp edge —
`s3-secret.yaml` **auto-generates random credentials** unless `s3.existingConfigSecret` or
`s3.credentials` is set. Flipping that flag without carrying the *existing* Loki key would
break Loki immediately. The wiki claims priority overrides with "no merging"; the 4.50 code
says file + dynamic store are merged (contradiction C4) — either way, the safe move is **not to
introduce a static config at all** and instead add a new identity to the store the gateway
already uses. CSI is unaffected: the driver talks to the filer, not the S3 gateway. [S30][S28]

**Least-privilege identity shape that the plan can ask for.** The action set is not guesswork:
SeaweedFS 4.50's route table gates each operation on a named action
(`s3api_server.go:1060-1076`, `:1112-1168`, `:1198-1204`; action constants in
`s3_constants/s3_actions.go:4-11`), which maps 1:1 onto the calls Forgejo's minio storage makes.

| Forgejo call (`modules/storage/minio.go`) | S3 operation | SeaweedFS action needed |
|---|---|---|
| `GetBucketVersioning` probe (:120) | GET `?versioning` | `Read` (:1134) |
| `BucketExists` (:133) — **fatal if it errors** | HeadBucket | `Read` (:1199) |
| `MakeBucket` (:139) | PutBucket | `Admin` (:1204) |
| `Open`/`Stat` (GetObject/HeadObject) | GET/HEAD object | `Read` (:1060-1067) |
| `Save` (PutObject) | PUT object | `Write` (:1074) |
| `Delete` | DELETE object | `Write` (:1076) |
| (list, e.g. cleanup/migration tooling) | ListObjectsV2 | `List` (:1168) |

Scoping grammar comes from `Identity.CanDo` (`auth_credentials.go:2098-2154`): a bare action
(`"Write"`) matches anywhere, `"Write:git-lfs"` matches that bucket at any key (exact
`action + ":" + bucket` comparison), `"Read:git-lfs/<prefix>*"`-style wildcards narrow to a
prefix, and `"Admin:git-lfs"` grants everything on that bucket — including CreateBucket. A
least-privilege Forgejo grant is therefore `["Read:git-lfs", "Write:git-lfs"]` — `Read` for boot
+ downloads, `Write` for uploads + deletes; add `List:git-lfs` only for operator tooling
(`mc ls`, cleanup sweeps), since Forgejo itself never lists.
That covers the multipart flow too: for LFS objects above minio-go's 16 MiB part size Forgejo's
`PutObject` becomes NewMultipartUpload/UploadPart/CompleteMultipartUpload, and 4.50 gates all
three on `Write` (`s3api_server.go:1019-1023`) — the separate
`ListBucketMultipartUploads`/`ListMultipartUploadParts` actions (`s3_actions.go:26-27`) are only
needed by tooling that lists in-flight uploads, not by Forgejo.

Wiki-documented provisioning commands: create dynamically with `weed shell` →
`s3.user.provision -name forgejo -bucket git-lfs -role readwrite` (or `s3.user.create` +
`s3.policy -put` + `s3.policy.attach`), or via the admin UI (Object Store → Users, which writes
to the same filer store and live-reloads with **no restart**). Inventory/debug: `s3.user.list`,
`s3.config.show`, `s3.iam.export`. [S26][S27][S28]

**Reuse `/buckets/git`, or a purpose-built bucket?** Both are the same filer directory
namespace, and the idle `git` collection is a legitimate physical home. The argument against
reusing it is isolation, not layout: a bucket-scoped identity can only be as narrow as the
bucket name, and that same collection is already mounted as a 1 TiB RWX PV/PVC
(`services/infra/prod/templates/pvc-git-seaweedfs.yaml`, collection `git`, path `/buckets/git`,
replication `002`) — so any pod that ever mounts that PVC can read and overwrite every LFS
object, and conversely an LFS-writing identity with `Write:git` can write anywhere in that
collection. A dedicated bucket (`git-lfs`) keeps IAM narrow, keeps `migrate-storage`
rollback/cleanup surgical, and leaves the `git` collection for its original filesystem
purpose. `replication: "002"` is a property of how the CSI PV was declared, not of the bucket;
a new bucket inherits the filer/master default placement (`-defaultReplicaPlacement=001` is on
the filer args) — worth a deliberate decision if LFS durability should match the `002` PV.
(EXPLORE §3.4, §6 of the `git` PVC; placement default is LIVE filer args.)

---

## Q4 — Serving LFS through the ingress path (dev → `https://s3.spencerslab.com`)

**Endpoint shape is confirmed, and `MINIO_BUCKET_LOOKUP = path` is safe but not strictly
required.** minio-go's `auto` lookup falls back to
`s3utils.IsVirtualHostSupported(url, bucket)`, which returns true **only** for Amazon, Google
and Aliyun-OSS endpoints (pkg/s3utils/utils.go:71-83). A SeaweedFS endpoint therefore gets
**path-style under `auto`** already. Setting `MINIO_BUCKET_LOOKUP = path` explicitly is still
the right call: it makes the intent visible, and it removes any dependence on that
endpoint-classification heuristic (which is exactly what would silently turn into
`https://git-lfs.s3.spencerslab.com/…` and fail TLS if the client or the value ever changed).
Docs shape for TLS: `MINIO_ENDPOINT = minio.example.com` (host, no scheme) with
`MINIO_USE_SSL = true`; the docs also warn `MINIO_USE_SSL` defaults to false and "if an
external S3 provider is intended… should be set to true". Loki's working config is the same
shape (`endpoint: https://s3.spencerslab.com`, `s3forcepathstyle: true`,
`region: us-co-1`). Whether minio-go implies 443 from a bare host was not verified in source —
low stakes, but a plan may write `s3.spencerslab.com:443` to remove the doubt. [S1][S15][S31]

**Signature / Host header.** SigV4 signs the `Host` header; Traefik preserves the client Host
unless a `SetHost`/rewrite middleware is applied. Repo greps for
`maxRequestBodyBytes|buffering|client_max_body_size|proxy-body-size|whiteList` across
`services/` and `charts/base/` returned **nothing**, and no middleware attaches to the s3
ingress (`services/infra/prod/values.yaml:78-82` gives host+service+port only). The live probe
signed for `Host: s3.spencerslab.com` end-to-end (the gateway evaluated the signature and
answered `InvalidAccessKeyId`), which proves the ingress does not rewrite the Host or the path
on that route. [S31][S32]

**Body-size limits: none in this fleet.** Traefik's only request-size mechanism is the opt-in
`buffering` middleware, whose `maxRequestBodyBytes` defaults to **0 = no maximum** (413 only
appears when you configure it). Nothing in this repo configures it. [S38][S31]

**The real ingress constraint is a timeout, and it lands on the client side, not the gateway
side.** This fleet's Traefik static config sets, on the `websecure` entrypoint,
`transport.respondingTimeouts: readTimeout: 600s, writeTimeout: 0, idleTimeout: 600s`
(charts/base/templates/traefik-config.yaml:54-59). `readTimeout` bounds the read of a request
body, so: (a) **client → Forgejo** LFS uploads are one single PUT per object bounded by 600 s
of transfer (git-lfs does not client-side multipart), i.e. roughly 3 GB at 5 MB/s upstream;
(b) **Forgejo → gateway** requests are 16 MiB parts (or one ≤16 MiB PUT), three orders of
magnitude inside 600 s — the multipart behaviour that #12177 was about is precisely what keeps
each request short. `LFS_MAX_FILE_SIZE` (default 0 = unlimited) is the guard rail if huge
single objects are a concern. [S3][S31]

**Where the bytes actually go — `SERVE_DIRECT` matters only for downloads.**
`services/lfs/server.go:475-505`: the **upload action always points at Forgejo**
(`rc.UploadLink`); only `download` consults `setting.LFS.Storage.MinioConfig.ServeDirect` to
substitute a 5-minute presigned S3 URL (`storage.URL` → `PresignedGetObject(…, 5*time.Minute, …)`
in minio.go:291-302) and drop the Authorization header. So with `SERVE_DIRECT = false` (the
briefing's choice, not re-litigated here), **only the Forgejo pod needs to reach the gateway** —
git clients never do, and no wildcard DNS/TLS for `*.s3.spencerslab.com` is needed. Choosing
`true` later would move that requirement to every git client. [S5][S9]

**Reachability and latency (indirect → now partly direct).** DNS from this workspace resolves
`s3.spencerslab.com` → `10.0.77.59` (same address as `git.spencerslab.com`), and the TLS +
ingress + gateway round trip completed in **0.02 s** from the Coder workspace (gpu cluster) —
so the path works fast from inside the lab, from a cluster with no SeaweedFS of its own, which
is exactly dev's situation. Whether the name is reachable **from the internet** was not
established (only in-lab resolution was observed; no external probe was run). NetworkPolicy
inventory taken for both clusters: dev and infra `default` namespace policies select only
ArgoCD components and `bitwarden-cli` — **nothing selects forgejo pods**, so no egress policy
blocks a dev forgejo pod from reaching the public ingress. No NetworkPolicy exists that would
help if you wanted to *restrict* it. [S31][S32]

**Boot-time dependency is the sharpest edge, not latency.** `routers/init.go:117` runs
`mustInit(storage.Init)` and `mustInit` does `log.Fatal` on error (init.go:58-64);
`storage.Init` → `initLFS` → `NewMinioStorage`, which **hard-fails** if `BucketExists` errors
(only `GetBucketVersioning` errors are tolerated unless HTTP 400) — with auth enforced, a
missing/under-privileged identity gives `AccessDenied` → error → the Forgejo web process dies
(→ pod not ready, whole forgejo instance down, not just LFS). Ordering rule for the plan: identity
+ bucket-scoped grants + (if the identity lacks `Admin:<bucket>`) the bucket itself must exist
**before** the Forgejo config change is applied; `forgejo migrate-storage --type lfs --storage
minio …` run as a one-off is the cheapest pre-flight of exactly that init path. [S5][S26][S39][S41][S32]

**Single point of failure note (repo/LIVE-grounded, low surprise):** `seaweedfs-s3` is a
1/1 Deployment on infra; dev's LFS availability therefore inherits both that replica and the
infra Traefik route. Worth a line in the plan's risk section, and a reason to prefer the
in-cluster endpoint for the **infra** instance and keep the public one only for dev.

---

## Contradictions (and how to weigh them)

| # | Clash | Weigh |
|---|---|---|
| C1 | forgejo-helm 17.3.1 `docs/ha-setup.md`: `lfs.STORAGE_TYPE: minio` with credentials under `storage:` — vs FJ 15.0.10 code: the section declaring `STORAGE_TYPE` is the target; `[lfs]` override covers only `SERVE_DIRECT`/`MINIO_BASE_PATH`/`MINIO_BUCKET`; vs FJ v15 docs single-subsystem example which puts credentials **inside `[lfs]`** | **Code at the pinned tag.** Copy the docs' `[lfs]`-carries-everything shape, not the chart's split shape |
| C2 | Docs v15.0: default `MINIO_BUCKET: forgejo` — code: `MustString("gitea")` | **Code.** Always set `MINIO_BUCKET` explicitly |
| C3 | Forgejo docs test-compatibility list = MinIO + garage only (no SeaweedFS) — card briefing recommends SeaweedFS | Briefing stands as the decision, but the combo is **not upstream-tested** → dev-first rollout with explicit byte-level verification (push → clone in a fresh clone → compare OID) |
| C4 | SeaweedFS wiki (2026-10-31): auth methods "completely override … no merging" — SW 4.50 code: "always try to load/merge config from credential manager" | **Code**, but the disagreement sits exactly on the path that would break Loki → do not introduce `-s3.config` in this ticket |
| C5 | EXPLORE §3.2: gateway "unauthenticated … credentials accepted-but-not-validated" — LIVE: `InvalidAccessKeyId` on an unknown key | **Live probe + code rule.** Auth is enforced; identities live in the filer store, out-of-band |
| C6 | Briefing's implied #12177 urgency for 4.50 — code: Forgejo never sends object checksums, and the server block is gated on the recorded algorithm | **Both sides' code.** Not reachable from Forgejo; keep 4.50, optionally bump to 4.52 separately |
| C7 | Docs: "`MINIO_BASE_PATH` must not be set in `[storage]`" — code honours it there and prefixes the subsystem name | Follow the docs (don't set it in `[storage]`); note the code differs if someone tries |

**Blind spot no prose source covered:** that the gateway had already transitioned to enforced
auth through the dynamic store. Only the live probe plus `auth_credentials.go` revealed it —
and it is the finding that most changes the plan (a credential-less design, which EXPLORE left
open as technically possible, is not possible).

---

## What this changes for the plan

1. **Credentials are in scope and must exist before the config does.** Add a chunk: create the
   `git-lfs` bucket with an admin identity, then create a SeaweedFS identity for Forgejo in the
   existing dynamic store with the verified minimum grant `["Read:git-lfs", "Write:git-lfs"]`
   (`Read` is needed just for the HeadBucket at boot, `List` is optional operator tooling;
   `Admin` is not needed once the bucket exists — §Q1 handshake, §Q3 action matrix) — user-run
   (admin UI or `weed shell
   s3.user.provision …`), then a Bitwarden Login item (Loki precedent: `loki-s3`) + an
   ExternalSecret in the forgejo chart mirroring `charts/loki/templates/secret-s3.yaml`, and
   `additionalConfigFromEnvs` entries `FORGEJO__LFS__MINIO_ACCESS_KEY_ID` /
   `FORGEJO__LFS__MINIO_SECRET_ACCESS_KEY`. Card OQ3 closes: the question is not *whether* to
   authenticate. [S26][S27][S28][S5][S31]
2. **Use the single-subsystem shape: everything in `[lfs]`.** Do not set `[storage]
   STORAGE_TYPE=minio` — it would move attachments/avatars/packages/actions to S3 as a
   side effect. Do not copy the chart's split shape (C1). Put `STORAGE_TYPE`, endpoint, bucket,
   lookup, ssl, checksum in `[lfs]`; per-instance differences (endpoint, and bucket if it
   differs) go in `custom-values/<cluster>/prod-values.yaml` under the top-level `forgejo:` key
   (the appset value law, EXPLORE §1/§8-1). [S4][S7][S31]
3. **Purpose-built bucket** (e.g. `git-lfs`) instead of `/buckets/git`, so bucket-scoped IAM
   stays narrow and the RWX `git` PV cannot read/overwrite LFS objects; set `MINIO_BUCKET`
   explicitly (C2); decide bucket placement (filer default `001` vs the `002` the `git` PV
   used) deliberately. [S24][S28][S31]
4. **No SeaweedFS version change in this ticket.** Drop any "pin to 4.46" or "must upgrade for
   LFS" step; if the team wants 4.52.0 (fix for #12177 published 2026-11-02), make it its own
   dep ticket with its own validation. `MINIO_CHECKSUM_ALGORITHM = md5` may still be chosen —
   for corruption detection, not as a #12177 workaround. [S16][S17][S19][S20][S21]
5. **Endpoint per instance:** infra → `seaweedfs-s3.default.svc.cluster.local:8333` +
   `MINIO_USE_SSL=false`; dev → `s3.spencerslab.com` + `MINIO_USE_SSL=true` +
   `MINIO_BUCKET_LOOKUP=path` (explicit; `auto` would also resolve to path-style). Keep the
   public endpoint off the infra instance to avoid a needless hairpin through Traefik. [S15][S1][S31]
6. **Rollout risk must be planned, not discovered.** Bad S3 config ⇒ `log.Fatal` at boot ⇒ the
   whole Forgejo instance is down (missing bucket, unreadable bucket and unreachable endpoint
   all land inside a 30 s storage-init ceiling, then kill the process). Sequence: bucket (as
   admin) → identity (`Read/Write:<bucket>`) → pre-flight via
   `forgejo migrate-storage --type lfs …` (also migrates any existing objects) → apply config →
   dev first, infra second. Rollback = revert the values change (ArgoCD), no data action. [S39][S5][S41][S27]
7. **Validation oracles that do not need Secret reads or pod exec** (fills the gap EXPLORE §9
   flagged): the boot log lines `Initialising LFS storage with type: minio` and
   `Creating Minio storage at <endpoint>:<bucket> with base path lfs/`
   (storage.go:167 `initLFS`, minio.go:102); `LFS_START_SERVER=true` + the `lfs` key asserted in
   the rendered `<release>-inline-config` Secret (RENDER shape above); a real push/clone with an
   object >16 MiB to exercise the multipart path; and `helm template` grep legs for the trio. [S4][S5][S33]
8. **Nothing to do about `LFS_JWT_SECRET`** — the chart generated it at first boot and refuses
   to rewrite it once app.ini exists. Remove it from any plan checklist. Optional guard rail to
   consider deliberately: `LFS_MAX_FILE_SIZE` against Traefik's 600 s read timeout. [S35][S3][S31]
9. **Card label error to raise with the human, not fix in code:** `Services: dev + gpu` is
   inconsistent with the fleet (Forgejo is dev+infra; no Forgejo on gpu; gateway on infra only)
   — EXPLORE OQ1 stands.

---

## Adjacent (not core)

* Forgejo's **quota** feature has a `size:git:lfs` subject (`[quota] ENABLED=false` by default)
  — a knob if LFS growth ever needs bounding. [S3]
* Forgejo docs nav shows the 15 LTS line at **v15.0.11** while this fleet runs `15.0.10`; the
  wrapper chart's `appVersion: 15.0.9` is cosmetic (EXPLORE §1). Not this ticket. [S1]
* `SERVE_DIRECT=true` would move gateway reachability to every git client and needs 5-minute
  presigned URLs; out of scope per the briefing, recorded only because it changes §Q4's
  reachability conclusions. [S5][S9]
* SeaweedFS 4.52 carries 217 merged PRs beyond the checksum fix — bumping is a real change, not
  a patch. [S18]

---

## Open questions (flagged, could not confirm)

1. **Who created the existing SeaweedFS identities, and what is in that store?** Proven that
   identities exist and enforcement is on; the *contents* are unobservable to agents (no exec,
   no Secret reads). Needs user-run `weed shell` → `s3.user.list`, `s3.config.show`,
   `s3.iam.export`, or the admin UI (Object Store → Users). The plan needs to know whether
   Forgejo joins Loki's identity or gets its own (recommend its own).
2. **Which buckets exist today?** All three HEAD probes returned `403` because auth precedes
   existence. Needs user-run `s3 ls` / `s3.mb` check — including whether `/buckets/git`
   (CSI-created) actually surfaces as an S3 bucket, and whether Loki's `logs` bucket is an
   S3 `MakeBucket` or just a filer directory.
3. **Is `s3.spencerslab.com` reachable from the internet, or lab-only?** Only in-lab
   resolution (`10.0.77.59`) and a 22 ms in-lab round trip were observed; no external probe was
   run. This decides how urgent bucket-scoped IAM is for LFS bytes of private repos.
4. **`MINIO_ENDPOINT` port defaulting in minio-go v7.0.99** (bare host + `MINIO_USE_SSL=true`
   ⇒ 443?) — not verified in source; write `s3.spencerslab.com:443` to sidestep it.
5. **Exact `weed shell` provisioning commands for this store** — the wiki documents
   `s3.user.provision -name X -bucket Y -role readwrite`, but this fleet's store variant
   (legacy single `identity.json` vs the newer distributed credential manager with policy
   engine) was not identified; the operator should confirm which subcommands exist on 4.50.
6. **Carried over from EXPLORE and unresolved by research:** OQ1 (`Services: gpu` mislabel),
   OQ2 (accept dev↔public / infra↔in-cluster asymmetry — §Q4 supports it), OQ4 (bucket creation
   and `migrate-storage` are user-run), OQ6 (bucket choice — §Q3 now argues for dedicated).
7. **dev pod DNS for `*.spencerslab.com`** — proven from a gpu-cluster workspace and from
   Loki on monitoring, not from a dev-cluster pod. Cheap to close at dev rollout time.

---

## Sources (all read 2026-11-02/03 unless noted)

| # | Source | Used for |
|---|---|---|
| S1 | https://forgejo.org/docs/v15.0/admin/setup/storage/ (LTS v15.0, fetched 2026-11-02) | key set + defaults, `[storage]` vs subsystem sections, base-path rule, S3-compat list (MinIO/garage), `MINIO_USE_SSL` guidance |
| S2 | https://forgejo.org/docs/latest/admin/storage/ and /docs/v16.0/admin/setup/storage/ (search snippets only) | wording persistence across versions — snippet-level, not read in full |
| S3 | https://codeberg.org/forgejo/docs/raw/branch/v15.0/docs/admin/config-cheat-sheet.md (LFS at :370-377, quota at :1366-1392, `[lfs]` at :1331) | `LFS_START_SERVER=false`, `LFS_JWT_SECRET(_URI)`, `LFS_HTTP_AUTH_EXPIRY`, `LFS_MAX_FILE_SIZE`, `LFS_MAX_BATCH_SIZE`, quota subject |
| S4 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/modules/setting/storage.go | ini tags (:34-47), defaults (:70-85), section precedence (:145-205), `getStorageForMinio` base-path (:244-270) |
| S5 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/modules/storage/minio.go | client options (no `TrailingHeaders`), versioning probe + `BucketExists`/`MakeBucket`, `SendContentMd5`, `PartSize` for size<0, `URL` presign 5 min |
| S6 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/modules/setting/lfs.go:55 | `getStorage(rootCfg, "lfs", "", lfsSec)` |
| S8 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/modules/lfs/content_store.go | LFS `Put` passes `pointer.Size` (known size) |
| S9 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/services/lfs/server.go:475-510 | `SERVE_DIRECT` download-only; upload action always Forgejo |
| S10 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/go.mod | `minio-go/v7 v7.0.99` |
| S11 | https://raw.githubusercontent.com/minio/minio-go/v7.0.99/api.go (:310 trailingHeaderSupport; :1088-1115 lookup) | checksum gating; `auto` ⇒ path-style for non-AWS/Google/Aliyun |
| S12 | https://raw.githubusercontent.com/minio/minio-go/v7.0.99/api-put-object.go | PutObject docstring (>16 MiB multipart), `AutoChecksum` only with trailing headers, single-PUT decision |
| S13 | https://raw.githubusercontent.com/minio/minio-go/v7.0.99/constants.go | `minPartSize 16MiB`, `absMinPartSize 5MiB`, `maxPartsCount 10000` |
| S14 | https://raw.githubusercontent.com/minio/minio-go/v7.0.99/checksum.go | `addAutoChecksumHeaders` / `applyAutoChecksum` gating |
| S15 | https://raw.githubusercontent.com/minio/minio-go/v7.0.99/pkg/s3utils/utils.go:71-83 | `IsVirtualHostSupported` = Amazon/Google/Aliyun only |
| S16 | https://github.com/seaweedfs/seaweedfs/issues/12177 (opened 2026-10-28, closed 2026-10-29) | bug shape, 4.48+ affected / 4.46 OK, repro on 4.51 with minio-go v7.0.90 |
| S17 | https://github.com/seaweedfs/seaweedfs/releases/tag/4.52 | "s3: accept bare composite checksum on CompleteMultipartUpload" (PR #12194) |
| S18 | GitHub releases/tags API for seaweedfs | 4.52 2026-11-02T11:24Z … 4.48 2026-09-28 |
| S19 | https://raw.githubusercontent.com/seaweedfs/seaweedfs/4.50/weed/s3api/filer_multipart.go | unfixed :628; gate on `ExtChecksumAlgorithm` set at :129 |
| S20 | https://raw.githubusercontent.com/seaweedfs/seaweedfs/4.52/weed/s3api/filer_multipart.go | `matchesObjectChecksum` present at :628/:1878 |
| S21 | https://seaweedfs.github.io/seaweedfs/helm/index.yaml | chart 4.52.0 (2026-11-02T16:43Z) … 4.46.0 (2026-09-08) |
| S22 | Docker Hub tag list `chrislusf/seaweedfs` | `4.52`, `4.52_full`, `4.51`, `4.50`, `4.49` tags exist |
| S23 | https://raw.githubusercontent.com/seaweedfs/seaweedfs/4.50/weed/command/s3.go | `-autoCreateBucket` default true (:128), buckets folder default `/buckets` (:298/:317/:383), `-domainName` (:114) |
| S24 | https://raw.githubusercontent.com/seaweedfs/seaweedfs/4.50/weed/s3api/s3api_bucket_handlers.go | ListBuckets empty for unauthenticated; `checkBucket`/`hasAccess`; auto-create errors (:639-830); `/buckets` scan |
| S27 | https://raw.githubusercontent.com/seaweedfs/seaweedfs/4.50/weed/s3api/s3api_server.go | routes implement `?versioning` (:1134) and `?location` (:1112); `iam.Auth` wrapping; action gating per route — HeadObject/GetObject/HeadBucket `Read` (:1060-1067, :1199), PutObject/DeleteObject `Write` (:1074-1076), ListObjectsV2 `List` (:1168), PutBucket `Admin` (:1204) |
| S26 | https://raw.githubusercontent.com/seaweedfs/seaweedfs/4.50/weed/s3api/auth_credentials.go | `isAuthEnabled = identityCount > 0 \|\| startConfigFile != ""` (:427); merge of file + credential manager (:393); empty-file deny-all; env-var identities; `Auth` short-circuit (:1678) |
| S28 | https://github-wiki-see.page/m/seaweedfs/seaweedfs/wiki/S3-Credentials (mirror, last modified 2026-10-31) | identity JSON, actions incl. `Read/Write/List/Admin:bucket`, `s3.user.provision`, admin UI path, live reload of filer store, one-way auth transition, "no merging" claim (contradicted by code) |
| S29 | https://github.com/seaweedfs/seaweedfs/blob/4.50/weed/credential/filer_etc/filer_etc_identity.go:19 | `identity.json` in the filer-backed store |
| S30 | upstream `seaweedfs` helm chart 4.50.0 (helm pull, `values.yaml` + `templates/s3/*`, `templates/filer/*`) | `s3.enableAuth`, `existingConfigSecret` key `seaweedfs_s3_config`, auto-generated secret, `filer.s3.enableAuth`, `checksum/s3config` rollout |
| S31 | Repo reads: `charts/seaweedfs/values.yaml:400-429`, `charts/base/templates/traefik-config.yaml:54-59`, `charts/loki/values.yaml:1-34`, `services/infra/prod/values.yaml:70-95`, `services/infra/prod/templates/pvc-git-seaweedfs.yaml` + EXPLORE.md | fleet config truth, Traefik 600 s timeouts, Loki S3 shape, no size middlewares |
| S32 | LIVE read-only probes 2026-11-02/03: `https://s3.spencerslab.com/` unauth → 403 AccessDenied; SigV4 bogus key → 403 InvalidAccessKeyId; HEAD `/git/`,`/logs/`,`/forgejo/` → 403; DNS → 10.0.77.59; 22 ms round trip; `Deployment/seaweedfs-s3` + `StatefulSet/seaweedfs-filer` args/env; NetworkPolicy inventory dev+infra | auth state, reachability/latency, no `-s3.config`, no forgejo egress policy |
| S33 | RENDER: `helm template dev charts/forgejo` (dep 17.3.1) with `forgejo.gitea.config.lfs.*` + `server.LFS_START_SERVER=true` | inline-config `lfs` key + `server` key shapes |
| S34 | forgejo-helm 17.3.1 `docs/ha-setup.md:80-110` (helm pull) | the `MINIO_BUCKET` note and the split shape (C1) |
| S35 | forgejo-helm 17.3.1 `scripts/config_environment.sh:119-167` | `LFS_JWT_SECRET` auto-generation; drop-when-app.ini-exists |
| S36 | forgejo-helm 17.3.1 `values.yaml:665-675` + `values.schema.json` | `gitea.config.lfs`/`storage` `additionalProperties: true` |
| S39 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/routers/init.go:58-64,117 | `mustInit(storage.Init)` → `log.Fatal` |
| S40 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/modules/setting/config_provider.go:180-185 | no `Insensitive` → ini section names case-sensitive |
| S41 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/cmd/migrate_storage.go:31-98,209 | flag set incl. `--minio-checksum-algorithm`; no `--minio-bucket-lookup`; calls `storage.Init()` |
| S42 | https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/modules/setting/config_env.go:60-112 and `contrib/environment-to-ini/` | `FORGEJO__LFS__*` → section lowercased to `[lfs]`; `__FILE` suffix |
| S37 | https://codeberg.org/forgejo/forgejo/issues/2482 · https://codeberg.org/forgejo/docs/issues/701 (search snippets only, not read in full) | arrival versions of `MINIO_BUCKET_LOOKUP` (Mar 2024) and `MINIO_CHECKSUM_ALGORITHM` (≤7.0 docs backport) — existence in 15.0.10 is proven by S4, not by these |
| S38 | https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/buffering/ | `maxRequestBodyBytes` default 0 (no limit) → no 413 unless configured |

```
RESULT
status: DONE
chunk: plan
files_changed: [/home/coder/.local/share/opencode/worktree/5e680f/cf-104-feat-forgejo-lfs/.agents/plans/2026/2026-11-cf-104-feat-forgejo-lfs/RESEARCH.md]
commands_run: [helm pull oci://code.forgejo.org/forgejo-helm/forgejo --version 17.3.1 => pass | helm pull seaweedfs/seaweedfs --version 4.50.0 => pass | helm dependency update + helm template dev /tmp/opencode/fjrender (lfs keys render proof) => pass | git clone --depth1 --branch 4.50 --sparse seaweedfs => pass | git clone --depth1 --branch v15.0.10 --sparse forgejo => pass | source reads at pinned tags (forgejo: modules/storage/{storage,minio}.go, modules/setting/{storage,lfs,config_env}.go, modules/lfs/{content_store,pointer}.go, routers/init.go, cmd/migrate_storage.go; seaweedfs 4.50: weed/command/s3.go, weed/s3api/{s3api_server,s3api_bucket_handlers,auth_credentials,filer_multipart,s3_constants/s3_actions}.go) => pass | curl unauth S3 probe => pass(403 AccessDenied) | python SigV4 bogus-key probe => pass(403 InvalidAccessKeyId) | curl HEAD /git /logs /forgejo => pass(403) | NetworkPolicy inventory dev+infra (MCP readonly) => pass | searxng_web_search x11 + webfetch of v15 docs/#12177/wiki => pass]
deviations: The launch scope was kept exactly (4 questions), but the evidence base is code-at-pinned-tag + live probes rather than prose, because every question is version-exact; the STORM fan-out ran in-session (no nested Task tool). One live probe (read-only signed GET against our own S3 endpoint) went beyond EXPLORE's read-only-k8s set — it is what corrected the auth assumption; no writes, no admin-* grants used. storm-runs/ was created inside the worktree by the skill's init script and moved to /tmp/opencode/storm-trail/ so this RESEARCH.md is the only artifact in the repo.
friction: STORM init script wrote storm-runs/ into the worktree (unexpected for a repo-scoped session) — moved out; `codeberg.org/<repo>/raw/tag/<tag>/<path>` works for Forgejo source but GitHub raw needs tag names without `v` for SeaweedFS (404 on first guess); `raw.githubusercontent.com/.../api-object.go` 404'd — minio-go split PutObject into api-put-object.go (listed the dir via the contents API); `helm template` silently produced nothing when PATH=$HOME/.local/bin was not exported in the second shell (same trap EXPLORE §8-5 records, still bites per-shell); write tool is denied for /tmp paths so the STORM trail had to be written via shell heredocs; the searxng engines duckduckgo/wikipedia/wolframalpha were repeatedly unavailable — worked around by going straight to primary sources (codeberg/github raw + APIs).
open_questions: (1) Who owns the existing SeaweedFS identity store and what is in it — needs user-run `weed shell` (`s3.user.list`, `s3.config.show`, `s3.iam.export`); Forgejo should get its own identity, confirm the role/provisioning subcommands that exist on 4.50. (2) Which buckets exist today (all HEAD probes 403 before existence) — does CSI's /buckets/git surface as an S3 bucket? (3) Is s3.spencerslab.com internet-reachable or lab-only (only in-lab resolution/22ms proven) — sets the urgency of bucket-scoped IAM for private-repo LFS bytes. (4) Card Services label `gpu` is wrong for this fleet (no Forgejo on gpu; gateway on infra) — human question, not a code fix. (5) Accept the dev=public-endpoint / infra=in-cluster-endpoint asymmetry (research supports it). (6) minio-go bare-host→443 default unverified in source — plan may write `:443`.
next_suggested: Planner: build the plan around (a) create the `git-lfs` bucket with an admin identity and a bucket-scoped Forgejo identity (`Read:git-lfs` + `Write:git-lfs`; `Read` is what makes the startup HeadBucket succeed) + Bitwarden item + ExternalSecret BEFORE any Forgejo config change, (b) `[lfs]`-carries-the-full-key-set shape with that dedicated bucket, per-instance endpoint in custom-values, (c) `migrate-storage` as pre-flight, dev-first rollout with the boot-log + push/clone-verify oracles, and no SeaweedFS version change; carry C1/C2 and the boot-time `log.Fatal` risk (30 s storage-init ceiling, fatal HeadBucket error) into the chunk acceptance criteria, and put OQ1-OQ3 into the single batched plan-question round for the human.
```
