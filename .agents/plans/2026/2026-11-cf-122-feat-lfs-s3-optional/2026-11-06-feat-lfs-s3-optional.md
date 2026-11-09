# PLAN: Make the forgejo LFS S3 object store optional (default OFF); dev flips to local LFS

feature: 2026/2026-11-cf-122-feat-lfs-s3-optional
card: #122 `prBBEA8JnJDx7cHfy` (AI-Dev)
round: 1 (user-directed in-session run — the user's instruction IS the approval; `plan_status` stays `draft` until the coord flips it, gate-honest)
round: 2 (2026-11-09 delta planning pass — C01 merged to main as 483bf1607, ticket reopened `approved` for the user-directed follow-up chunk C02: flip the forgejo elements to `ServerSideApply: "true"`. See the "Delta round 2" section below; C01's record is untouched.)

## Goal

The forgejo wrapper chart's S3 (SeaweedFS-gateway) LFS object store becomes
optional and **default OFF**: an instance's LFS server stays on, but objects
store LOCALLY on the instance's data volume unless the instance opts into S3
by declaring `gitea.config.lfs.STORAGE_TYPE: minio` (+ endpoint + TLS flag +
the `forgejo-s3` vault UUID) in its own custom-values slice. The **dev**
instance (git.scifi.farm) takes the not-enabled stance; **infra** keeps S3
exactly as cf-104 shipped it — zero infra regression is an acceptance
criterion; the runner charts/apps and `custom-values/{infra,gpu}` are
untouched.

## Out of scope

- **No new boolean flag.** `STORAGE_TYPE` in the merged `[lfs]` values IS the
  switch (coord ruling 1); absent or anything-but-`minio` = local.
- **Infra config changes.** `custom-values/infra/prod-values.yaml` is
  byte-untouched (blast-radius AC); infra's effective S3 config is unchanged
  (AC3).
- **Runner charts/apps, seaweedfs chart, services/, gpu custom-values** —
  untouched (blast-radius AC).
- **Fixing the live dev ESO-provider failure** (Authority A11: dev's
  `bitwarden-login` store cannot fetch item `forgejo-s3` right now;
  git.scifi.farm is down for it). That is a separate user/admin incident (store
  access to the item). This ticket's dev flip makes dev's availability
  independent of it — but does not repair the store.
- **Migrating or deleting dev's orphan LFS objects** (the `git-lfs` bucket
  contents written while dev's LFS was S3-backed — see Rollout §orphan note;
  the user called this "junk"). No data action; recovery recipe recorded.
- **The `forgejo-s3` Bitwarden item** stays (infra consumes it); its UUID
  stays in `custom-values/infra` and is dropped from `custom-values/dev`.
- SeaweedFS version churn, `[storage]` (attachments/avatars/packages) S3,
  `SERVE_DIRECT=true` — all cf-104 out-of-scope items remain out of scope.
- **Bumping chart versions by hand** — `release.yaml` bumps the wrapper
  `version` on merge (CI); `Chart.lock` / the OCI `forgejo-helm 17.3.1` dep
  stay byte-untouched (no dep change).

## Authority

The cf-104 record (`.agents/plans/2026/2026-11-cf-104-feat-forgejo-lfs/`) is
the grounding record for the LFS×SeaweedFS facts (auth on, bucket `git-lfs`,
`[lfs]` carries all keys, gateway `seaweedfs-s3` on infra 8333 plain /
`s3.spencerslab.com` public TLS, the minio-go handshake, the
`config_environment.sh` env-survives-app.ini lesson) — cited, not
re-researched. This round's own verified facts (all verified 2026-11-07 in
this worktree unless marked LIVE):

| # | Fact | Evidence |
|---|---|---|
| A1 | The pinned subchart (forgejo-helm 17.3.1) renders the pod's `env` **only** from the static values lists `deployment.env` + `gitea.additionalConfigFromEnvs` (verbatim `toYaml`, no per-entry conditional) and the `<release>-inline-config` Secret **only** from the merged `gitea.config` map (`_helpers.tpl` `gitea.inline_configuration`, `printf "%s=%v"` per key, no `tpl`). A wrapper chart therefore **cannot** conditionally inject `[lfs]` keys into the inline-config Secret or filter the env list from its own templates — the wrapper's templates can only gate **wrapper-owned objects** | `helm dependency build` copy + read of `charts/forgejo-17.3.1/templates/gitea/deployment.yaml:107-115,403-433` and `_helpers.tpl:187-215`; render experiments below |
| A2 | `secretKeyRef.optional: true` is the one k8s-native soft dependency: the env var is simply absent when the Secret is missing and the pod boots. Secret **volumes** have no `optional` — a dangling Secret-volume reference fails the pod at start (`CreateContainerConfigError`), which kills any `gitea.additionalConfigSources` / file-mount design for the gated artifacts (the subchart ranges that list unconditionally, `deployment.yaml:412-416`; the same wedge is what A11 shows live today) | k8s API semantics + subchart template read this round |
| A3 | The subchart's `values.schema.json` types `gitea.additionalConfigFromEnvs` as an array with **untyped items** (`{}`) — an `optional: true` field on `secretKeyRef` passes schema; `helm lint` of the modified chart: 0 failed | `values.schema.json` properties check + `helm lint` on the experimental chart copy |
| A4 | The subchart pins `[server] APP_DATA_PATH=/data` when unset (`_helpers.tpl:327-328`, the `inline_configuration.defaults` block) and sets `GITEA_WORK_DIR=/data`, `GITEA_APP_INI=/data/gitea/conf/app.ini`, `GITEA_CUSTOM=/data/gitea` on **both** the main `forgejo` container and `init-app-ini` | subchart `deployment.yaml` container env blocks + LIVE dev pod `dev-forgejo-5bb75677cf-g42jb` env (via `readonly-dev-kubernetes`); every render in this round shows `APP_DATA_PATH=/data` in `[server]` |
| A5 | **Dev's data PVC is 10Gi** (the user's "10gb volume" is right): PVC `forgejo`, RWO, `local-path`, Bound, mounted at `/data` in the forgejo pod. Chart wiring: `persistence.{create:true, claimName: forgejo, size: 10Gi, accessModes: [ReadWriteOnce], storageClass: local-path}` — no dev override in the slice | LIVE dev cluster (PVC list) + `charts/forgejo/values.yaml:45-52` + EXPLORE cf-104 §1 |
| A6 | **Local LFS root = `/data/lfs`.** Forgejo v15.0.10: `loadLFSFrom` (`modules/setting/lfs.go`) calls `getStorage(rootCfg, "lfs", "", lfsSec)`; with no `[lfs]` section (or one without a valid `STORAGE_TYPE`) and no `[storage]`/`[storage.lfs]`, `getStorageTargetSection` (`modules/setting/storage.go:145-187`) falls to `getDefaultStorageSection` → `STORAGE_TYPE=local` (:73); `getStorageForLocal` (:206-242): empty `PATH` → `filepath.Join(AppDataPath, "lfs")`; `AppDataPath` = `[server] APP_DATA_PATH` (`modules/setting/server.go:300-302`, default `AppWorkPath/data`) = **`/data`** per A4. Local init = `os.MkdirAll` only (`modules/storage/local.go:30-34`) — **no fatal network handshake** (contrast the minio path: RESEARCH §Q1, `HeadBucket`/`MakeBucket` under the 30 s `log.Fatal` ceiling) | source at tag `v15.0.10` fetched this round (`modules/setting/{lfs,server,path,storage}.go`, `modules/storage/{storage,local}.go`) + A4 |
| A7 | **A bare `[lfs]`-less config with `[server] LFS_START_SERVER: true` is a valid, self-sufficient config** (LFS local storage is the documented code default when `STORAGE_TYPE` is unset — A6). Boot log instead of cf-104's minio oracle: `initLFS` (`modules/storage/storage.go`): `LFS_START_SERVER` false → `DiscardStorage("LFS isn't enabled")`, no init log; true → **`Initialising LFS storage with type: local`** + `NewLocalStorage` → **`Creating new Local Storage at /data/lfs`** (`local.go:33`). `LFS_JWT_SECRET` is load-or-generate-and-save into app.ini on first `LFS_START_SERVER=true` boot (`lfs.go` loadLFSFrom tail) — self-healing, no external dependency | source at tag `v15.0.10` this round; cf-104 RESEARCH §Q1 (minio oracles), D8 (JWT secret history) |
| A8 | `config_environment.sh` (subchart `files/scripts/`, shipped in the `<fullname>` Secret): inlines/`additionals` files export `FORGEJO__<file-base>__<KEY>`; **pod envs (`FORGEJO__*`) are re-exported AFTER files and win**; only the four auto-generated secrets are dropped when app.ini exists — LFS env legs survive an existing app.ini on every start (the cf-104 lesson, unchanged) | read of the script this round (subchart copy); cf-104 plan Authority row 4 |
| A9 | **Zero-infra-regression proof (measured).** Chart copy + `/tmp` + `helm dependency build` (never in place), current infra slice: before/after whole-render diff of the gate design is **exactly**: (i) the 4 shape lines leave the inline-config `[lfs]` string (7→3 lines), (ii) one new object `Secret/forgejo-lfs-shape` (the 4 constants, template-injected), (iii) 4 NEW env entries (the shape legs, all `optional: true`) + 2 added lines (`optional: true`) on the 2 pre-existing cred legs, (iv) the `checksum/config` pod annotation (follows the inline-config change). **`[server]` is byte-identical, the `forgejo-s3-secret` ExternalSecret is byte-identical, the ESO remoteRef UUID is unchanged.** Effective app.ini `[lfs]` = the same 7 non-credential keys + 2 credential keys (3 inline ∪ 4 shape-env ∪ 2 cred-env, disjoint unions) — infra boots into an identical S3 config | before/after renders this round (`/tmp/opencode/cf122/`), diff reproduced in Commands C01-block; renders deterministic (double-render diff clean) |
| A10 | **Dev local stance (measured).** Gate-closed render (post-ticket dev slice: no `lfs` block): **no** `forgejo-s3-secret` ExternalSecret, **no** `forgejo-lfs-shape` Secret, **no** `[lfs]` section, **zero** `STORAGE_TYPE` hits; the only S3 traces are the six env-leg entries in the pod spec (5 `name: FORGEJO__LFS__MINIO_*` lines + 1 `FORGEJO__LFS__SERVE_DIRECT` line, with 8 `MINIO_*` hits total, all on their `name:`/`key:` lines — structurally unavoidable: A1, the env list is the only env surface and it is static; hiding it requires forking the list across values files, the exact cf-104 trap) | same renders this round |
| A11 | **LIVE incident (motivation + D11 proven in the field).** Since 2026-11-06T21:07Z the dev-forgejo pod is stuck: `init-app-ini` `CreateContainerConfigError: secret "forgejo-s3-secret" not found`; dev's ExternalSecret `forgejo-s3-secret` (same item UUID as infra) = `Ready=False, SecretSyncedError, "could not get secret data from provider"` (refreshTime null). Infra's ESO for the SAME item = `Ready=True, SecretSynced` (transition 2026-11-05T21:15Z); `infra-forgejo` Running 1/1, 0 restarts, 29 h. ⇒ the Bitwarden fetch of item `forgejo-s3` fails on the DEV cluster only (dev store access), and dev's git availability is currently hostage to it. Consequence for this ticket: dev's flip removes the ESO + the hard secretKeyRef from dev entirely (A2), so dev boots regardless of that store failure; the store failure itself stays a separate user/admin incident | LIVE via `readonly-{dev,infra}-kubernetes` (pod status, ESO status, events) 2026-11-07 |
| A12 | **Pinned baselines on main a0502f0d (measured this round, solo runs):** `forgejo-lfs.sh` **exit 0 / 34 ok** (CHANGED by this ticket — the master contract rework); `infra-forgejo.sh` exit 0 / 33 ok; `forgejo-ssh-gateway.sh` **exit 1 / 63 ok, red only at t11** (t11 re-runs audit-trail; pinned, pre-dates ticket); `dev-forgejo-runner.sh` **exit 1 / 34 ok, red only at the pinned t5** (cf-93 comment-window false positive); `gpu-forgejo-runner.sh` exit 0 / 18 ok; `dev-git-auth.sh` exit 0 / 36 ok; `gpu-coder-sso.sh` exit 0 / 15 ok; `audit-trail.sh` **exit 1 / 0 ok** (t1: tracked `storm-runs/` at repo root); `tests/multi-repo/dev-wiring.sh` exit 0 / 9 ok. Sentinel umbrella sweeps: **dev 1** (pre-existing `home-assistant.bitwardenIds` wart in the ApplicationSet values JSON), **infra 1** (`charts/samba/values.yaml:5` `samba-users: OVERRIDE_NEEDED` chart default inside the samba app's values JSON), **gpu 1** (legacy `OVERRIDE_VIA_CLUSTER_ANNOTATION` trio on one values-JSON line) | the background solo suite runs + umbrella renders this round (logs `/tmp/opencode/cf122/baseline-*.log`); matches cf-104 STATE `measured_baselines` (which recorded exactly these after the C03 rebase) |
| A13 | Helm gate mechanics gotcha (cost this planning round an hour): a helper used as `{{- if include "x" . }}` **always renders** — `include` returns the STRING `"false"`, which is truthy. The gate must be `{{- if eq (include "forgejo.lfs.s3.enabled" .) "true" }}`. Verified both ways on experimental copies. The `--show-only templates/<file>.yaml` "could not find template" error is the sanctioned way to confirm a gate is closed (helm-chart-creation skill) | experiment + `helm template --show-only` outputs this round |
| A14 | cf-104's four shape constants were verified-legal literals at v15.0.10 (`MINIO_BUCKET_LOOKUP` ∈ auto/dns/**path**; `MINIO_CHECKSUM_ALGORITHM` ∈ ""/ **default** /md5, only `md5` sends Content-MD5) and their values are the Q2/Q6 user answers — they move, unchanged, into the gated template (A9/AC2) | cf-104 plan D5 + RESEARCH §Q1 (S5, minio.go:88-99 validation), cited per the task's grounding rule |

The subchart `docs/ha-setup.md` split shape (`lfs.STORAGE_TYPE` + credentials
under `[storage]`) remains the documented-but-wrong shape (cf-104 C1): every
LFS key still lands in `[lfs]`, and the credential env legs' lower-cased
section still resolves to `[lfs]` (A8; RESEARCH §Q1 S42 `config_env.go:89`).

## Design (coord ruling grounded — the one adjustment is AC3's re-wording, evidenced)

**Gate** (single condition, three artifacts): `forgejo.lfs.s3.enabled` — a
named helper in a NEW wrapper `charts/forgejo/templates/_helpers.tpl`,
`eq (toString (get <merged gitea.config.lfs> "STORAGE_TYPE" | default "")) "minio"`
with `get`/`default` guards at every level (repo missingkey rule), used as
`eq (include …) "true"` (A13). Merged values = chart defaults + the
instance's custom-values slice, exactly as the appset delivers it. No new
boolean flag; dev (and any future instance) opts in by declaration.

**(a) The four shape constants — template-injected, single source.**
REMOVED from `charts/forgejo/values.yaml` (`gitea.config.lfs` goes away from
the chart defaults). NEW wrapper template
`charts/forgejo/templates/secret-forgejo-lfs-shape.yaml`, whole-object
gated, `Secret/forgejo-lfs-shape` (sibling style: fixed name, no namespace
line, `stringData`) carrying exactly `MINIO_BUCKET: git-lfs`,
`MINIO_BUCKET_LOOKUP: path`, `MINIO_CHECKSUM_ALGORITHM: default`,
`SERVE_DIRECT: "false"` (string — env values are strings; A9). They reach
app.ini as four new env legs in the chart's
`gitea.additionalConfigFromEnvs` (see b) — constants live in ONE template,
no values file can fork bucket/lookup/checksum, and a future opted-in
instance copies only the 3 activation keys.

**(b) The env legs.** `gitea.additionalConfigFromEnvs` stays the chart's
single static list — **no slice ever overrides it** (cf-104's lesson,
unchanged). The two pre-existing `FORGEJO__LFS__MINIO_{ACCESS_KEY_ID,
SECRET_ACCESS_KEY}` legs gain `optional: true` on their `secretKeyRef`; four
shape legs (`FORGEJO__LFS__MINIO_BUCKET` / `_MINIO_BUCKET_LOOKUP` /
`_MINIO_CHECKSUM_ALGORITHM` / `_SERVE_DIRECT` → `forgejo-lfs-shape`) are
appended, also `optional: true`. The DB-password + SECRET_KEY legs are
byte-untouched. Effect: gate open (infra) — both Secrets exist, all 6 legs
resolve, effective `[lfs]` identical to today (A9); gate closed (dev/bare) —
neither Secret exists, all 6 legs resolve to *absent*, pod boots, no `[lfs]`
content (A10). The rejected alternatives are in Decisions D3/D4.

**(c) The ExternalSecret.** `templates/secret-forgejo-s3.yaml` — whole-object
gate (`{{- if eq (include "forgejo.lfs.s3.enabled" .) "true" }}…{{- end }}`),
body otherwise byte-untouched (infra render A9). The chart's
`bitwardenIds.forgejo-s3: OVERRIDE_VIA_CUSTOM_VALUES` sentinel **stays**
(consumed only by the gated ESO; rendered only when gate open; dev simply
no longer provides a value — the sentinel can never leak into a gate-closed
render because its only consumer is gated).

**Dev stance** (`custom-values/dev/prod-values.yaml`): DROP the whole
`forgejo.forgejo.gitea.config.lfs` block (STORAGE_TYPE/MINIO_ENDPOINT/
MINIO_USE_SSL), DROP `forgejo.bitwardenIds.forgejo-s3` + its comment block;
KEEP `server.LFS_START_SERVER: true`. The comment block becomes the stance
record: LFS stays on, objects land locally on the data volume — PVC
`forgejo`, **10Gi**, `local-path`, RWO, at `/data`; local LFS root
**`/data/lfs`** (A5/A6; the boot log prints the resolved root — A7). No S3
trace in the dev file (the stance comment avoids the literals `forgejo-s3`,
`MINIO`, `STORAGE_TYPE` — test t8 greps for them).

**Infra stance**: byte-untouched (A9, blast-radius AC5).

## Decisions

| # | Decision | Basis / rejected alternatives |
|---|---|---|
| D1 | Gate = merged `gitea.config.lfs.STORAGE_TYPE == "minio"` via a wrapper `_helpers.tpl` named helper; helper consumed as `eq (include …) "true"` | Coord ruling 1; A13 makes the `eq` form mandatory (a bare `if include` is always-true — measured) |
| D2 | Shape constants: NEW gated wrapper `Secret/forgejo-lfs-shape` + 4 optional env legs; removed from chart `values.yaml` | Coord ruling 2, executed: "template-injected constants, single source". Rejected: (i) keep in chart values = renders on dev (violates the zero-artifacts AC); (ii) carry in infra's slice (D1-alt below) = violates the blast-radius AC + forks for future instances |
| D3 | Credential + shape env legs: `optional: true` on the 6 `secretKeyRef`s, single static list in the chart, no slice override | The only k8s-native soft dependency (A2) that keeps (a) one env list (cf-104 lesson) and (b) dev bootable without the ESO (A11 proves the hard dependency wedges dev's whole git). Rejected: template-side filter of the env list — **infeasible** (A1: the subchart renders the list verbatim from static values; the wrapper cannot touch it); a separate values key the wrapper template "merges when gated" — same wall (values cannot be merged conditionally by a template; helm values are static); `additionalConfigSources` file mount — infeasible (A2: Secret volumes have no `optional`, dangling ref wedges the pod) |
| D4 | AC3 re-wording (the one coord-ruling adjustment, with evidence): infra's **effective** S3 config is byte-identical, and the render delta is exactly the A9 four-item list — not "whole render byte-identical" | "Whole render byte-identical" is unachievable by ANY design that removes the shape keys from dev's render: the inline-config `[lfs]` string is built solely from the merged `gitea.config.lfs` values map (A1), so the 4 shape keys must either stay in chart values (render on dev — ruled out) or leave the inline string (render delta — A9). The blast-radius AC (`custom-values/infra` untouched) rules out the slice-carried alternative. A9 pins the delta exactly, so the zero-regression proof stays mechanical and reviewable |
| D5 | ESO whole-object gate; chart sentinel stays | Coord ruling 2/3(c); A9 (infra ESO byte-identical); A10 (dev: zero ESO) |
| D6 | Dev keeps `LFS_START_SERVER: true` (LFS on, local) | User's verbatim: "It should just write lfs junk to a 10gb volume if s3 is not enabled" — the volume is real (A5: 10Gi), the local root is real (A6: /data/lfs), the config is valid (A7) |
| D7 | `SERVE_DIRECT` value is the **string** `"false"` in the shape Secret (env values are strings; the pre-change inline render also produced the literal `false` via `printf %v`) | A9 keeps the effective value identical; the shape Secret's stringData must hold strings |
| D8 | Test contract: forgejo-lfs.sh legs reworked in place (t2 inverts to the default-off zero-artifacts assertion; t3/t4 gate-aware; t5 dev-local; t7/t8 storage-aware); infra-forgejo.sh t6 + forgejo-ssh-gateway.sh t8c dev-side sweeps become storage-aware (green across the transition — see Test contract) | Coord ruling 5; cf-104's one-line rule (STATE C01 coord_note): any suite sweeping chart-level sentinels or pinning exact key sets updates in the same change that touches the chart |
| D9 | One PR, chart-bump re-renders both forgejo apps; dev pod restarts into local stance, infra pod restarts into identical S3 config (harmless), runner apps do not restart (runner charts untouched) | User's pattern (cf-104 landing); appset `automated {prune, selfHeal}` (cf-104 plan rollout §7) — the dev ESO is PRUNED on sync, which also clears the current dev pod wedge (A11) |
| D10 | Orphan-data note recorded, no data action | Rollout §orphan; user called the objects "junk"; recovery recipe = one-off `git lfs fetch`/re-push from the bucket (or accept loss) |

## Questions (no-questions run — best-guess-first, none blocking)

| # | Question | Best guess taken | Impact if wrong | Who |
|---|---|---|---|---|
| Q1 | Does the dev ESO-provider failure (A11) need a fix **in addition to** this flip? | No — the flip makes dev independent of it; the store-access repair is the user's separate incident (likely: the dev `bitwarden-login` store's Bitwarden user lacks access to item `forgejo-s3`, while infra's has it) | if the item access is broken fleet-wide, infra's next hourly refresh (refreshInterval 1h; next due 2026-11-07T02:15Z) would fail too — but infra already re-synced successfully at the due time (status shows a fresh `SecretSynced`), so the item is fine; dev-store-side is the delta | user |
| Q2 | Is the 10Gi dev data volume acceptable for "lfs junk", or will the user want a larger LFS-specific volume later? | 10Gi is the existing `forgejo` PVC (A5) — LFS objects share it with app data; the user's own words ("a 10gb volume") confirm the target | a quota/size ticket later; nothing in this plan precludes it (persistence is untouched) | user (follow-up, not blocking) |
| Q3 | Should the gated `Secret/forgejo-lfs-shape` carry `reloader.stakater.com/auto`-style churn? | No — it is immutable per-gate (content only changes if the constants change); no annotation needed (sibling `forgejo-secret` ESO uses the reloader via ArgoCD restart-on-secret-change, the shape Secret renders identically across syncs) | cosmetic at worst | plan |

## Chunks

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | Chart gating (helper + gated shape Secret + gated ESO + optional env legs) + dev-slice local stance | M | 1 | [] | One subsystem (the forgejo wrapper + the dev slice edit) that must land atomically: the chart gate and the dev slice edit are one render — splitting them creates a state (gated chart + still-minio dev slice, or ungated chart + dev slice without the shape keys) that neither the ACs nor the live cluster wants |
| C02 | Flip `charts.forgejo.ServerSideApply` to `"true"` on dev + infra (with the comment truth-ups); runner entries untouched | S | 2 | [] | Chart-agnostic values/comment-only flip: it rides on cf-122 already merged to main (483bf1607), so no interface or data dependency on C01 — user directive 2026-11-09 (the 2026-11-09 incident research verdict: the first post-flip sync's CSA→SSA managedFields migration prunes the orphaned `data.lfs`; one-time cleanup, not the durable class fix). Wave 2 = after C01's merge, topologically independent |

(The test deltas are the test-writing stage, not a chunk — coord ruling.)

## Wave order

1. Test-writing session (reworks `forgejo-lfs.sh`, storage-awareness in
   `infra-forgejo.sh` t6 + `forgejo-ssh-gateway.sh` t8c; red-first on the
   forgejo-lfs inverted legs) → C01 dev → C01 review. One wave, one chunk.

## Commands

The pipeline's "tests" in this repo are renders, sweeps and greps
(`AGENTS.md` → "Pipeline specifics"). Helm at `~/.local/bin`:
`export PATH=$HOME/.local/bin:$PATH` in EVERY shell (cf-104 trap: without
it renders silently emit nothing). Renders run on COPIES under
`/tmp/opencode` + `helm dependency build` there — the worktree is never
written (charts/**/charts is gitignored). **Suites run solo** (cf-104
friction: concurrent helm renders degraded counts via registry skips).

```bash
cd "$(git rev-parse --show-toplevel)"
W=/tmp/opencode/cf122; mkdir -p $W
cp -R charts/forgejo/. $W/fj/ && (cd $W/fj && helm dependency build .)   # OCI dep; never in place

# ---- C01: chart ----
helm lint charts/forgejo            # 0 failed (icon INFO pre-existing)
helm template dev $W/fj \
  --set domain=scifi.farm --set clusterName=dev \
  --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
  --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4 \
  --set bitwardenIds.forgejo-s3=u5 > $W/bare.yaml
# ASSERT (the NEW default-off leg — zero S3 artifacts, gate closed):
#   no ExternalSecret named forgejo-s3-secret (show-only => "could not find
#   template" is the sanctioned closed-gate proof, A13); no Secret
#   forgejo-lfs-shape; no [lfs] section in dev-forgejo-inline-config; ZERO
#   STORAGE_TYPE hits; exactly six `name: FORGEJO__LFS__*` env entries with
#   all 8 MINIO_* hits on their name:/key: lines (the pinned A10 residual,
#   no more); those refs point at forgejo-s3-secret/forgejo-lfs-shape, both
#   absent objects;
#   init-app-ini carries exactly 8 FORGEJO__ legs — the 2 core ones
#   (DB password ← pg-forgejo-secret/password, SECRET_KEY ←
#   forgejo-secret/SECRET_KEY) byte-unchanged and WITHOUT `optional`, plus
#   the 6 gated optional ones; the three pre-existing ESOs (forgejo-secret,
#   pg-forgejo-secret, forgejo-admin-secret) unchanged; 0 OVERRIDE_* in
#   output (the --set list resolves them; the forgejo-s3 --set is now
#   unconsumed-but-harmless when the gate is closed)
# Gate-open leg: render with a -f values file (NEVER indexed --set — it
# nulls list entries, cf-104) that adds forgejo.gitea.config.lfs.STORAGE_TYPE
# = minio (plus MINIO_ENDPOINT/MINIO_USE_SSL): ExternalSecret forgejo-s3-secret
# present + byte-identical to pre-change (A9), Secret forgejo-lfs-shape present
# with exactly the 4 constants (A14), [lfs] inline = 3 keys.

# ---- effective per-instance renders (app slice = CONTENTS of the top-level forgejo: key) ----
python3 -c 'import yaml; yaml.safe_dump(yaml.safe_load(open("custom-values/dev/prod-values.yaml"))["forgejo"], open("/tmp/opencode/cf122/dev-slice.yaml","w"))'
python3 -c 'import yaml; yaml.safe_dump(yaml.safe_load(open("custom-values/infra/prod-values.yaml"))["forgejo"], open("/tmp/opencode/cf122/infra-slice.yaml","w"))'
helm template dev   $W/fj -f $W/dev-slice.yaml   --set domain=scifi.farm     --set clusterName=dev   > $W/dev.yaml
helm template infra $W/fj -f $W/infra-slice.yaml --set domain=spencerslab.com --set clusterName=infra > $W/infra.yaml
# ASSERT dev (local stance, A10): no [lfs], no forgejo-s3-secret, no
#   STORAGE_TYPE, [server] gains/keeps LFS_START_SERVER=true beside the
#   byte-unchanged identity keys (DOMAIN git.scifi.farm, ROOT_URL,
#   SSH_PORT 22222, APP_DATA_PATH /data)
# ASSERT infra (zero regression, A9): the [lfs] section resolves to the same
#   7 non-credential keys of record (3 inline ∪ 4 shape-env) + the 2 cred
#   env legs; [server] byte-identical vs pre-change render; the
#   forgejo-s3-secret ESO byte-identical vs pre-change; whole-render diff vs
#   the pre-change capture == exactly the A9 four-item list (dev+infra
#   pre-change captures are made by the TEST session on the pristine tree
#   before C01 lands, and kept in the suite's /tmp workspace)
# ASSERT blast radius: git diff --name-only main | grep -vE '^(charts/forgejo/(values.yaml|templates/(_helpers.tpl|secret-forgejo-s3.yaml|secret-forgejo-lfs-shape.yaml))|custom-values/dev/prod-values.yaml|tests/services/(forgejo-lfs|infra-forgejo|forgejo-ssh-gateway)\.sh|\.agents/plans/2026/2026-11-cf-122-feat-lfs-s3-optional/)' => EMPTY
#   i.e. nothing under services/, charts/forgejo-runner, charts/seaweedfs,
#   custom-values/infra, custom-values/gpu

# ---- sentinel sweeps (baselines pinned, A12 — must be UNCHANGED) ----
for c in dev infra gpu; do
  case $c in
    dev)   U=services/dev/prod   D=scifi.farm ;;
    infra) U=services/infra/prod D=spencerslab.com ;;
    gpu)   U=services/gpu/prod   D=spencerslab.com ;;
  esac
  cp -R $U $W/umb-$c && (cd $W/umb-$c && helm dependency build .) >/dev/null 2>&1 || true
  helm template $c $W/umb-$c -f custom-values/$c/prod-values.yaml \
    --set domain=$D --set clusterName=$c | grep -c OVERRIDE_
done   # want dev=1 (home-assistant wart), infra=1 (samba chart default,
       # charts/samba/values.yaml:5), gpu=1 (legacy annotation trio)
grep -rn 'OVERRIDE_NEEDED' custom-values/dev custom-values/infra | grep -c forgejo   # want 0

# ---- suites (solo; post-chunk targets — re-pin the CHANGED count as measured, cf-104 lesson) ----
bash tests/services/forgejo-lfs.sh          # CHANGED by this ticket: exit 0 / <N> ok, N measured by the test session and pinned here at C01 (all legs green, no skips)
bash tests/services/infra-forgejo.sh        # exit 0 / 33 ok (storage-aware t6 — green across the transition)
bash tests/services/forgejo-ssh-gateway.sh  # exit 1 / 63 ok, red ONLY at the pinned t11 (storage-aware t8c)
bash tests/services/dev-forgejo-runner.sh   # exit 1 / 34 ok, red ONLY at the pinned t5 (cf-93 window) — untouched
bash tests/services/gpu-forgejo-runner.sh   # exit 0 / 18 ok — untouched
bash tests/services/dev-git-auth.sh         # exit 0 / 36 ok — renders the dev umbrella, must stay green
bash tests/multi-repo/dev-wiring.sh         # exit 0 / 9 ok — untouched
bash tests/services/gpu-coder-sso.sh        # exit 0 / 15 ok — untouched
bash tests/services/audit-trail.sh          # exit 1 / 0 ok, pinned t1 (storm-runs/ at root) — NOT this ticket's red
# (all pins above measured on this tree 2026-11-07 — A12)

# ---- quality gate ----
npx --yes aislop@0.18.1 ci --changes --base main   # 0 errors, 0 fixable warnings
```

### Test contract (agent-test writes in one session BEFORE C01 dev; review re-runs)

**A. `tests/services/forgejo-lfs.sh` — the master contract rework (currently 0/34; CHANGED).**
Same harness (copy + dependency-build on /tmp, skip-not-fail on registry
unreachable, red-first stop-at-first-fail convention). The suite re-captures
pre-change infra/dev/bare renders on the pristine tree as the A9 diff
oracle. Leg rework (numbering kept; **red-first** = fails when agent-test
lands it, before C01):

| leg | New assertion | Red until |
|---|---|---|
| t1 | harness (unchanged) | — |
| t2 | **default-off (the new leg, A10)**: bare chart render — no `forgejo-s3-secret` ESO (show-only closed-gate proof), no `forgejo-lfs-shape` Secret, no `[lfs]` section, zero `STORAGE_TYPE` hits, exactly six `name: FORGEJO__LFS__*` env entries with all 8 `MINIO_*` hits on their `name:`/`key:` lines (the pinned residual, no more); the 2 core FORGEJO__ legs (DB password ← pg-forgejo-secret/password, SECRET_KEY ← forgejo-secret/SECRET_KEY) byte-unchanged and WITHOUT `optional`; 0 FORGEJO__ legs on the main container; no `[storage]`/`[attachment]`/`[picture]` | **C01 (red-first)** |
| t3 | **gate-open render** (values file w/ `lfs.STORAGE_TYPE=minio` + endpoint/ssl): ESO present and **byte-identical** to the pristine-tree capture (remoteRef = the `--set`/slice UUID, mapping + boilerplate as cf-104 t3); `forgejo-lfs-shape` Secret present with exactly the 4 constants (A14, `SERVE_DIRECT` string `false` — D7); inline `[lfs]` = the 3 activation keys only | **C01 (red-first)** |
| t4 | **env legs**: chart render (either gate state) — init-app-ini carries exactly 8 FORGEJO__ legs: the 2 core ones (DB password, SECRET_KEY) byte-unchanged and WITHOUT `optional` (still hard), plus the 6 gated ones **with `optional: true`** — the 2 cred legs referencing `forgejo-s3-secret/{access_key_id,secret_access_key}`, the 4 shape legs referencing `forgejo-lfs-shape/{MINIO_BUCKET,MINIO_BUCKET_LOOKUP,MINIO_CHECKSUM_ALGORITHM,SERVE_DIRECT}` | **C01 (red-first)** |
| t5 | **dev effective (local stance, inverted from cf-104's S3 assertion)**: no `[lfs]` section, no `forgejo-s3-secret`, zero `STORAGE_TYPE` hits, all 8 `MINIO_*` hits on the 6 pinned env-leg `name:`/`key:` lines (A10); `[server]` keeps `LFS_START_SERVER=true` + byte-identical identity keys vs the pristine capture; no storage/attachment/picture section | **C01 (red-first — the dev slice edit is in C01)** |
| t6 | infra effective: the 7 non-credential `[lfs]` keys of record resolve (3 inline ∪ 4 shape-env, values pinned to A14), cred legs present, ESO UUID == the infra slice's, `[server]` byte-identical vs pristine capture, no hairpin string (`https://s3.spencerslab.com` 0 hits) — cf-104's t6 assertions kept | **C01 (red-first** — pre-C01 the pristine chart has no shape legs and a 7-key inline, so the reworked leg fails against it) |
| t7 | **parity → single-source**: the 4 shape constants live in values land in EXACTLY one place — the gated template (grep `custom-values/` for `MINIO_BUCKET`, `MINIO_BUCKET_LOOKUP`, `MINIO_CHECKSUM_ALGORITHM`, `SERVE_DIRECT` as values keys == 0 hits repo-wide; the only occurrence is `secret-forgejo-lfs-shape.yaml`); infra's effective 7-key set == the constants of record; dev effective has none | **C01 (red-first)** |
| t8 | **storage-aware UUID leg (inverted dev half)**: infra slice carries UUID-shaped `forgejo.bitwardenIds.forgejo-s3`, no `OVERRIDE_*` in the infra forgejo slice; **dev file: NO `forgejo-s3` key, and zero occurrences of the literals `forgejo-s3`, `MINIO`, `STORAGE_TYPE` anywhere in `custom-values/dev/prod-values.yaml`** (the not-enabled stance has no S3 trace) | **C01 (red-first — dev half)** |
| t9 | sentinel sweeps at the pinned baselines (dev 1, infra 1 — A12; each umbrella's whole-render count unchanged) + the forgejo Application values JSON sentinel-free on both clusters | — (green across the transition; see D8 note) |
| t10 | trio survives (unchanged from cf-104) | — (regression) |
| t11 | blast radius vs the fork base: `charts/seaweedfs` + `services/infra/prod/templates` byte-untouched, `s3.enableAuth` still commented, no `-s3.config`, no Job (unchanged from cf-104) + NEW: `services/`, `charts/forgejo-runner/`, `custom-values/{infra,gpu}/` have zero diff lines vs base | C01 (new clause red-first) |

**B. `tests/services/infra-forgejo.sh` t6 — storage-aware 1:1 sweep.** The
`check_sentinels('charts/forgejo/values.yaml (consumed by dev)', …)` call
(≈:557) must require the `forgejo-s3` key in dev's custom-values **only
when dev's merged slice declares `lfs.STORAGE_TYPE: minio`** (read from
`custom-values/dev/prod-values.yaml` at run time). All other sentinels
unconditional. Green across the transition (pre-C01: dev declares minio
AND has the key; post-C01: dev declares neither) — D8. The infra-side
sweep + the five-key infra `bitwardenIds` exact-set check (:587) unchanged.

**C. `tests/services/forgejo-ssh-gateway.sh`** — the same storage-aware
edit in the t8c static sweep (≈:1426 dev-side `check_sentinels`). t6 (the
chart render with `--set bitwardenIds.forgejo-s3=u`) must stay green
unchanged: post-C01 that `--set` is unconsumed in the gate-closed render,
which only helps its no-OVERRIDE_* assertion. **No other leg may change**;
t11 stays the pinned red (it re-runs audit-trail, A12).

**D. Untouched suites** — `dev-git-auth.sh` (0/36; it renders the dev
umbrella + the coder chart, never the forgejo release), `dev-forgejo-
runner.sh` (1/34 pinned t5), `gpu-forgejo-runner.sh` (0/18), `dev-wiring.sh`
(0/9), `gpu-coder-sso.sh` (0/15), `audit-trail.sh` (1/0 pinned t1):
re-run as regression, zero edits.

## Rollout / landing

One PR (user's pattern). The merge bumps the wrapper `version` (CI
`release.yaml`) → both forgejo Applications re-render: **dev** pod restarts
into the local stance (the prune of the dev ESO + the `optional` refs
clears the current A11 wedge — dev's git availability returns even while
the dev Bitwarden-store incident stays open); **infra** pod restarts into
the identical S3 config (A9 — harmless; the checksum annotation change
restarts the pod once, LFS re-inits against the same bucket); **runner**
apps do NOT restart (runner charts untouched, A12).

**Orphan-data note (no action — user called the objects "junk"):** dev LFS
objects pushed to the shared `git-lfs` bucket while dev was S3-backed are
unreachable after the flip (dev will read from `/data/lfs` onward). Live
evidence (A11) shows dev was DOWN from 2026-11-06T21:07Z (its first and
only post-cf-104 sync attempt) — so dev almost certainly pushed **zero**
objects in that window; infra (served since 2026-11-06T~01:30Z) may hold
real objects and keeps working. Recovery recipe if ever needed: a one-off
`git lfs fetch` + re-push of the affected repos from a client that can
still reach the bucket (the bucket/identity are NOT touched by this
ticket) — or accept loss.

**Post-sync verification (human, no new User actions; agent-readables marked):**

1. **V1 — dev boot log** (agent-readable, `readonly-dev-kubernetes`
   `pods_log`): `Initialising LFS storage with type: local` +
   `Creating new Local Storage at /data/lfs` (A7), pod Ready, no
   `CreateContainerConfigError`, no storage-init fatal. This one also
   closes the A11 incident for dev's availability.
2. **V2 — byte round-trip on a throwaway DEV repo** (human; the local
   write path — cf-104's V2 recipe, >16 MiB file to exercise multipart-
   irrelevant local writes): push, clone elsewhere, `sha256sum` match;
   the object lands under `/data/lfs` (verifiable via the same probe or
   a future quota check).
3. **V3 — infra continuity** (agent-readable): infra pod Ready once
   post-restart; `Initialising LFS storage with type: minio` +
   `Creating Minio storage at seaweedfs-s3…:git-lfs with base path lfs/`
   (cf-104 V1 oracles) in its fresh boot log; the LFS batch endpoint on
   `git.spencerslab.com` still non-404.
4. **V4 — ArgoCD**: both Applications sync (prune on dev removes the ESO +
   no other dev object changes), `forgejo-s3-secret` still `SecretSynced`
   on infra. Merge/sync stay user-owned; the pipeline stops at "branch
   ready — commits local".

## Risks / assumptions

- **The 6 optional env legs are the pinned residual in dev/bare renders**
  (A10, A1). They are inert (referenced Secrets absent by design) but
  *named* in the pod spec; the test contract pins their exact shape so
  they cannot grow. Accepted per D3/D4 — the alternatives are strictly
  worse (list forks / dev wedge).
- **Infra degradation delta** (documented consequence of D3): if infra's
  `forgejo-s3-secret` were ever missing at pod start (ESO provider outage
  spanning a rollout — A11 shows such failures happen), the pod would
  boot WITHOUT the cred envs and the web process would die in storage
  init (cf-104: `mustInit(storage.Init)` → `log.Fatal`), crash-looping
  until the ESO recovers — instead of the pre-change
  `CreateContainerConfigError` wait. Self-healing, loud in ArgoCD, window
  bounded by the ESO's 1h refresh; infra's ESO is currently healthy (A11).
- **Dev disk**: LFS objects now share the 10Gi `forgejo` PVC with app
  data (Q2); local-path has no quota enforcement beyond the 10Gi request.
  The user sized this ("10gb volume").
- **App.ini staleness is a non-issue on dev** (verified, not assumed):
  dev never completed an S3-config boot (A11 — stuck before
  `config_environment.sh` ran), so its app.ini carries no `[lfs]` keys to
  go stale; the flip boot simply adds `LFS_START_SERVER=true` behaviour on
  the pre-existing local default. Infra's app.ini is re-fed with the same
  9 keys (A9).
- **`storm-runs/` at the repo root** keeps `audit-trail.sh` t1 red (and
  ssh-gateway t11 via its re-run) — pinned, pre-existing, NOT this
  ticket's (A12).
- Chart `appVersion: 15.0.9` is cosmetic (cf-104 note) — do not "fix" it;
  the pulled subchart pins 15.0.10 (A4/A6/A7 all verified at that tag).
- No cluster mutation by any pipeline agent: renders on /tmp copies,
  MCP reads only; sync/merge/PR are user-owned.

## Follow-ups (not this ticket)

- **Repair the dev `bitwarden-login` store's access to item `forgejo-s3`**
  (or delete the item's dev-store membership question, Q1) — separate
  incident; only matters if dev ever re-opts into S3.
- If a third instance (or dev again) opts into S3: it copies the 3
  activation keys only (D2) — the first such opt-in is the moment to
  review whether the shape constants deserve promotion to a shared
  service-level surface.
- cf-104's standing follow-ups (renovate coverage for the OCI dep, the
  storm-runs/ red suites, the dev-forgejo-runner t5 false positive) —
  unchanged, not touched here.

## Delta round 2 (2026-11-09): C02 — flip the forgejo apps to `ServerSideApply=true`

**User directive (2026-11-09):** "flip the forgejo elements to
`ServerSideApply: "true"`" — one follow-up change on the completed
ticket, grounded in the 2026-11-09 incident research (RESEARCH, both
sections): the first post-flip sync of each forgejo app runs ArgoCD's
CSA→SSA managedFields migration (kubectl-apply library, explicit
`argocd-controller` manager; `migrateToSSAIfNecessary` unions the
CSA-era `Update` fields — including the orphaned `data.lfs` key of
`dev-forgejo-inline-config` — into the `Apply` entry and the re-sent SSA
patch prunes it; k8s#99003, argo-cd#29109/#9368). The flip is a
**one-time orphan cleanup + future-prune-enablement for SSA-declared
fields, NOT the durable class fix** — the durable fix is upstream
forgejo-helm rendering the inline-config Secret as `data:` instead of
`stringData:` (RESEARCH incident section 2, §4(b)/OQ-3; the wrapper
cannot patch the subchart — A1). The user declined a follow-up card; the
item lives in STATE `deferred`.

**Scope (full detail in `chunks/C02.md`):**
- `services/dev/prod/values.yaml` — `charts.forgejo.ServerSideApply`
  `"false"` → `"true"` + a new why-comment (the entry had none; the
  false choice predates the incident).
- `services/infra/prod/values.yaml` — same flip + the stale
  "the app itself must not SSA (same as dev)" comment rewritten to the
  new stance (infra rides the same mechanism; `infra-forgejo` is
  OutOfSync against main on the C01 A9 four-item delta already, the flip
  adds one more expected diff to that same apply — live-verified
  2026-11-09).
- `charts/forgejo/templates/pg-forgejo.yaml` — header comment truth-up
  only: the per-resource `ServerSideApply=true` annotation on the CNPG
  Cluster STAYS (harmless when the app applies SSA, decisive if the
  app-level flag is ever reverted; it keeps CNPG's webhook-defaulted
  fields out of the annotation-drift class every other CNPG cluster in
  the repo avoids).
- **The runner entries are NOT touched** (`forgejo-runner-dev` on dev,
  `forgejo-runner-gpu` on gpu — user scope is forgejo only; the
  `dev-forgejo-runner.sh` t5 comment-window pin + the gpu exemption
  comment make a runner flip a separate ticket anyway).
- No `custom-values/` edit (no file carries the flag — verified), no
  `charts/forgejo/values.yaml` edit.

**Guardrails (rollout truth, AC7 in the chunk):**
- Never add key-level `ignoreDifferences` to these Secrets —
  argo-cd#29644 (open, v3.5.x window): with the app's
  `RespectIgnoreDifferences=true`, a key-level ignore on a stringData
  Secret drops the whole `data` map on sync (RESEARCH §4 claim 3c).
- Post-merge sync chain (user-owned, in order): sync `dev` umbrella
  (manual; appset regen re-bakes the child spec) → sync `dev-forgejo`
  (first SSA apply = the CSA→SSA migration prunes the orphan) → the
  one-time `[lfs]` strip from `/data/gitea/conf/app.ini` on PVC
  `forgejo` (RESEARCH incident section 1 §5 step 1 — `environment-to-ini`
  never deletes, so the strip is still required even though the init
  overlay stopped re-adding the fragment at the 13:23:47 sync) → pod
  delete → verify the local-LFS oracles (plan A7).

**Test contract (delta):** `infra-forgejo.sh` t3 flips its
`ServerSideApply` expectation `"false"` → `"true"` (the leg already
parses the rendered appset values blob — no count change, stays 0/33);
`forgejo-lfs.sh` gains a static t12 (dev `charts.forgejo` == `"true"`,
dev `charts.forgejo-runner-dev` == `"false"` boundary pin, infra
`charts.forgejo` == `"true"`); `forgejo-ssh-gateway.sh` and
`dev-forgejo-runner.sh` change NOTHING (verified: no leg greps the
rewritten comment text; their pinned reds t11/t5 are pre-existing and
characterized in the chunk's AC2/AC3).

**C02 commands (delta; the C01 Commands block stays the record for C01):**

```bash
export PATH=$HOME/.local/bin:$PATH
W=/tmp/opencode/cf122-c02; rm -rf $W; mkdir -p $W
cp -R services/dev/prod $W/umb-dev   && (cd $W/umb-dev && helm dependency build .)   # no deps — no-op
cp -R services/infra/prod $W/umb-infra && (cd $W/umb-infra && helm dependency build .)
helm template dev   $W/umb-dev   -f custom-values/dev/prod-values.yaml   --set domain=scifi.farm       --set clusterName=dev   > $W/dev-umb.yaml
helm template infra $W/umb-infra -f custom-values/infra/prod-values.yaml --set domain=spencerslab.com  --set clusterName=infra > $W/infra-umb.yaml
# ASSERT (AC1): in each render, the <label>-appset generator element (the
# base element's `values` JSON = the whole service values) carries
#   dev-appset:   charts.forgejo.ServerSideApply == "true",
#                 charts.forgejo-runner-dev.ServerSideApply == "false" (unchanged)
#   infra-appset: charts.forgejo.ServerSideApply == "true"
# sentinel sweeps unchanged at the A12 pins: dev=1, infra=1 OVERRIDE_ lines
helm lint services/dev/prod                                  # 0 failed (in place — no vendored deps)
# (infra umbrella lints on the /tmp copy — AC5; the tracked Chart.lock stays byte-identical)
git diff --name-only 96eeb668d | grep -vE '^(services/(dev|infra)/prod/values\.yaml|charts/forgejo/templates/pg-forgejo\.yaml|tests/services/(infra-forgejo|forgejo-lfs)\.sh|\.agents/plans/2026/2026-11-cf-122-feat-lfs-s3-optional/)'   # => EMPTY (AC5)
# suites (solo; post-C02 targets — N re-pinned as measured by the test session):
bash tests/services/infra-forgejo.sh        # exit 0 / 33 ok (t3 flipped)
bash tests/services/forgejo-lfs.sh         # exit 0 / <37 + t12's measured ok>
bash tests/services/forgejo-ssh-gateway.sh  # exit 1 / 63 ok, red ONLY pinned t11 (untouched)
bash tests/services/dev-forgejo-runner.sh   # exit 1 / 34 ok, red ONLY pinned t5 (untouched)
bash tests/services/gpu-forgejo-runner.sh   # exit 0 / 18 ok (untouched)
# regression per the A12 pins: dev-git-auth 0/36, gpu-coder-sso 0/15, dev-wiring 0/9, audit-trail 1/0 pinned t1
npx --yes aislop@0.18.1 ci --changes --base 96eeb668d   # 0 errors, 0 fixable warnings (AC6)
```

**C02 open threads (best-guess-first, none blocking — no `question` calls
in this run):**
- OQ-1 (RESEARCH incident section 2): the live `managedFields` read on
  `dev-forgejo-inline-config` (predicted `argocd-controller/Update`) is
  user-owned (the MCP tier strips managedFields + cannot read Secrets) —
  the AC7 chain's step-2 verify covers it; if the live entry is under an
  unexpected manager, the RESEARCH §6 action 3 one-off JSON patch is the
  fallback (still user-owned).
- OQ-2 (incident section 2): argo-cd#29109 closed without a fix — the
  diff-masking half stays open; the flip does not retroactively surface
  hidden orphans.
- OQ-3 (incident section 2): the upstream forgejo-helm `data:`-rendering
  PR = the durable class fix — deferred in STATE (user declined a card);
  until it lands, every future `gitea.config` key removal needs the
  one-off `/data/<key>` JSON patch to stay clean.
- The lab-wiring threads (incident section 1 OQ-2/OQ-3: annotation
  ownership of `services.dev.*.customValues` + `automated {prune,
  selfHeal}` on dev child apps) stay open, out of C02 scope — they are
  why the AC7 chain is manual and ordered.
