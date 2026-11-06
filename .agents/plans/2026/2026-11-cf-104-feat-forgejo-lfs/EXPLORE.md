# EXPLORE.md — cf-104 feat-forgejo-lfs

Written by `agent-explore` 2026-11-02 (Exploration stage, before research + planning).
Scope: repo + live-cluster grounding only. The card body's Oct-2026 research briefing
(SeaweedFS S3 recommendation, `migrate-storage`, issue #12177) is NOT re-verified here —
it is the input the research/plan stages own.

Evidence convention: `path:line` = read in this worktree; `LIVE <cluster>` = read-only MCP
probe (readonly-* only, 2026-11-02). Claims I could not ground are in §9, not scattered here.

---

## 0. Card intake (board-grounded, `dev-boards` MCP)

Card "Add LFS support to forgejo", id `uDTEEpnqEahASJjJN`, board `AI-Dev`
(`TNQJ2BrXenZovngTS`), list **Executing** (`qZ9CLZqCRbv7NQQ6R`), swimlane
`jLzy39L7djCRr67SF`. `label_ids` empty → no `Pipeline:` label → the single `default`
pipeline lock; no `Repo:` label → this repo; no `Research: Parallel` label.
`custom_fields: []` — the `slug` CF has not been written back for this card yet.
Description length 22,885 chars (the briefing).

Checklist state (read via `get_checklist`, checked flag is **`finished`** — see §8 gotcha):

- Services: **`dev` ✔, `gpu` ✔** (everything else, incl. **`infra`, unchecked**)
- Type: **`feat` ✔** · Model(s): **`Qwen Flash` ✔** · Human in the Loop: **`PR` ✔**
- Research: **`Before Planning` ✔** → coord WILL launch `agent-research` after this file
- **This card has no `Lifecycle` checklist.** Its five checklists are
  Model(s) / Services / Type / **Research** / Human in the Loop — not the
  Services/Type/Model(s)/**Lifecycle**/Human-in-the-Loop set in `AGENTS.md` and the
  `boards` skill. Consequence: the checked-stages-only stage gate has nothing to read,
  so the run defaults to the standard loop; do not spend a chunk reconciling the card.

**The Services label is the ticket's biggest open fact.** Ground truth from §1/§3: Forgejo
runs on **dev + infra**; the SeaweedFS S3 gateway runs **only on infra**; **gpu has no
Forgejo at all**. `gpu` on this card is either a mislabel for `infra` or an intent to
touch a gpu-side consumer (gpu's Coder authenticates against the infra Forgejo —
`services/gpu/prod/templates/secrets-coder.yaml:38` `CODER_EXTERNAL_AUTH_0_ID: "forgejo"`).
Handed to coord as OQ1.

---

## 1. Where Forgejo lives today

### Chart — one wrapper chart, two instances

`charts/forgejo/` is a **wrapper chart around the official Forgejo OCI chart**
(not app-template, not custom):

- `charts/forgejo/Chart.yaml:12-14` — dependency `forgejo` `version: 17.3.1`,
  `repository: oci://code.forgejo.org/forgejo-helm`. **OCI dep ⇒ renovate cannot bump it;
  bumps are manual** (Chart.yaml comment) and ArgoCD 3.1 resolves it natively.
- `charts/forgejo/Chart.lock` — dep 17.3.1, generated 2026-10-25.
- `charts/forgejo/Chart.yaml:6` wrapper `version: 1.0.7` (CI `release.yaml` bumps — never
  hand-bump), `appVersion: 15.0.9` — **stale/cosmetic**: the pulled subchart 17.3.1 declares
  `appVersion: 15.0.10` and both live pods run `forgejo:15.0.10-rootless`. Don't let a plan
  "fix" the appVersion as if it drove the image.
- Files: `Chart.yaml`, `Chart.lock`, `values.yaml`, `templates/{pg-forgejo.yaml,
  secret-forgejo.yaml, secret-forgejo-db.yaml, secret-forgejo-admin.yaml}`.
  No `tests/` dir in this chart (only `charts/gpt-researcher/tests` and
  `charts/llama-swap/tests` exist repo-wide).

### ApplicationSet entries (the trio)

| leg | file:line | shape |
|---|---|---|
| dev appset | `services/dev/prod/values.yaml:76-78` | `charts.forgejo: {namespace: default, ServerSideApply: "false"}` |
| infra appset | `services/infra/prod/values.yaml:18-20` | identical |
| dev proxy leg | `services/dev/prod/values.yaml:136-138` | `ingress.subdomains.git → service: dev-forgejo-http, port 3000` |
| infra proxy leg | `services/infra/prod/values.yaml:86-91` | `git` + `forgejo` → `infra-forgejo-http:3000` |
| hub routing | `services/proxy-local/prod/values.yaml:115-130` | `forgejo` alias entry (crowdsec-only chain) |
| custom-values (secrets leg) | `custom-values/dev/prod-values.yaml:62-80`, `custom-values/infra/prod-values.yaml:44-63` | both filled with real UUIDs |
| ssh | `services/{dev,infra}/prod/values.yaml` `gitSshPort: 22222` ↔ chart `gitea.config.server.SSH_PORT: 22222` (`charts/forgejo/values.yaml:82-83`) | must stay equal |

`gpu` appears nowhere under `charts:` in `services/gpu/prod/values.yaml` (gpu chart keys:
langflow, docling, drawio, searxng, flowise, n8n, llama-swap, seaweedfs-csi-driver,
cloudnative-pg, open-webui, amd-gpu, coder, external-secrets-bitwarden, k8s-monitoring,
smtp-relay). **No gpu Forgejo.**

### Per-instance identity plumbing — where per-cluster differences go

`custom-values/<cluster>/prod-values.yaml` under the top-level `forgejo:` app key:
`bitwardenIds` + `forgejo.gitea.config.*` overrides deep-merge over the chart's neutral
defaults. dev sets `APP_NAME`, `server.DOMAIN: git.scifi.farm`, `ROOT_URL`, `admin.email`
(`custom-values/dev/prod-values.yaml:72-80`); infra sets the same plus a mailer block
(`custom-values/infra/prod-values.yaml:50-63`). This is the **designed place for any
per-instance LFS/S3 difference** (e.g. endpoint differs per cluster).

Hard law for that mechanism — `charts/base/templates/appset-charts.yaml:32-36`:
`values: merge $extraValues (index $.Values $appName)` — only the **top-level `<appName>:`**
key reaches the release (plus injected `shared-storage` and `subDomain`). Anything under
`charts.<appName>` beyond `namespace/ServerSideApply/version/repository/chart` **never
reaches the chart**. (Same lesson recorded in the runner refactor's FRICTION.)
Custom-values loading itself is cluster-annotation driven:
`services/<c>/prod/templates/appset.yaml:64-66` (`services.<serviceName>.customValuesUrls`).

### How app config reaches `app.ini` today (the shape an LFS change rides)

Two mechanisms, both already in use:

1. **Inline config** — `gitea.config.<section>.<KEY>` in values renders into the Secret
   `<release>-inline-config`, one data key per section. Rendered sections for dev today:
   `_generals_, cache, database, metrics, oauth2_client, queue, repository, security,
   server, service, session`. **A `[lfs]` section would appear as a new `lfs` key there.**
   Current chart config sites: `charts/forgejo/values.yaml:59-102`
   (`database` 73-77, `server.SSH_PORT` 82-83, `service` 86-88, `oauth2_client` 96-102).
2. **`gitea.additionalConfigFromEnvs`** — `charts/forgejo/values.yaml:104-119`: two entries
   today, `FORGEJO__DATABASE__PASSWD ← secretKeyRef pg-forgejo-secret/password` and
   `FORGEJO__SECURITY__SECRET_KEY ← forgejo-secret/SECRET_KEY`. **This is the only path for
   anything secret** (the pattern a `FORGEJO__LFS__MINIO_ACCESS_KEY_ID` /
   `..._SECRET_ACCESS_KEY` would use).

Live proof of the mechanism (LIVE dev): pod `dev-forgejo-54ccc57f98-xzmpn` has 3 init
containers; **`init-app-ini`** runs `/usr/sbin/config_environment.sh` with
`FORGEJO__DATABASE__PASSWD` + `FORGEJO__SECURITY__SECRET_KEY` and mounts
`/env-to-ini-mounts/inlines/`. The **main container carries no `FORGEJO__*` env at all**
(only `SSH_LISTEN_PORT/SSH_PORT`, `GITEA_*`, `HOME`) — a reviewer grepping the main
container for LFS envs will find nothing; look at the init container.
Volumes: Secrets `dev-forgejo-init`, `dev-forgejo`, `dev-forgejo-inline-config`;
PVC **`forgejo`** → `/data`. Persistence: `charts/forgejo/values.yaml:41-48`
(`create: true`, `claimName: forgejo`, 10Gi, RWO, **`local-path`**, resource-policy keep).
DB: CNPG `Cluster pg-forgejo` (`templates/pg-forgejo.yaml`), host `pg-forgejo-rw:5432`.
OAuth: single Keycloak source `login.spencerslab.com/realms/SpencersLab`
(`charts/forgejo/values.yaml:130-139`).

### Live instance state

| instance | cluster | workload | image / chart | PVC | notes |
|---|---|---|---|---|---|
| `dev-forgejo` | dev | **Deployment** (not STS), 1/1 | `code.forgejo.org/forgejo/forgejo:15.0.10-rootless` / `forgejo-17.3.1` | `forgejo` | Services `dev-forgejo-http:3000`, `dev-forgejo-ssh` |
| `infra-forgejo` | infra | **Deployment**, ready 1 | same | `forgejo` | Services `infra-forgejo-http`, `infra-forgejo-ssh`; CNPG `pg-forgejo` + `pg-keycloak` present |

Both in namespace **`default`** (chart entries pin `namespace: default`).

---

## 2. Is Git LFS enabled today? No — and where it would go

- Repo-wide grep for `lfs` in `charts/`, `services/`, `custom-values/` → **zero hits**
  (only unrelated hits in plans and model-pull notes). No `LFS_START_SERVER`, no `[lfs]`.
- Render proof: `helm template dev charts/forgejo` (neutral chart values) produces **no `lfs`
  section** in `dev-forgejo-inline-config`; the only LFS strings are the chart's own secret
  bootstrap: `FORGEJO__SERVER__LFS_JWT_SECRET=$(gitea generate secret LFS_JWT_SECRET)`
  (lines 209-210, 236, 241 of the render). So `[server] LFS_JWT_SECRET` is auto-generated,
  `[lfs]` is absent, and `LFS_START_SERVER` is unset → app default applies (upstream default
  is `false`; that default is a briefing/research claim, not repo-grounded).
- Upstream chart surface (verified by pulling the exact pinned dep — §6 recipe):
  `gitea.config.lfs: {}` at `values.yaml:665-666` of forgejo-helm 17.3.1, and
  `values.schema.json` declares `gitea.config.lfs` and `gitea.config.storage` as
  `additionalProperties: true` objects → **arbitrary `[lfs]`/`[storage]` keys pass schema
  validation**. `gitea.config['storage.packages']`-style dotted section names are legal.
- Upstream doc shape (`docs/ha-setup.md:85-110` of the pulled chart) is the S3 example:

  ```yaml
  gitea:
    config:
      attachment: {STORAGE_TYPE: minio}
      lfs:        {STORAGE_TYPE: minio}
      picture:    {AVATAR_STORAGE_TYPE: minio}
      'storage.packages': {STORAGE_TYPE: minio}
      storage:
        MINIO_ENDPOINT: <svc.ns.svc.cluster.local:9000>
        MINIO_LOCATION: <location>
        MINIO_ACCESS_KEY_ID: <ak>
        MINIO_SECRET_ACCESS_KEY: <sk>
        MINIO_BUCKET: <bucket>
        MINIO_USE_SSL: false
  ```

  Its own warning: **"`MINIO_BUCKET` here is just a name and does not refer to a S3
  bucket. It's the root access point for all objects belonging to the respective
  application"** — plan/research must settle what that means against SeaweedFS's
  bucket=filer-dir model (§3.4). The briefing's extras (`MINIO_BUCKET_LOOKUP`,
  `SERVE_DIRECT`) do **not** appear in the chart docs — key names unverified here.

Call shape for the implementer (both legs ride existing patterns, nothing new needed):

```yaml
# charts/forgejo/values.yaml (neutral) or custom-values/<c>/prod-values.yaml (per-instance)
forgejo:
  gitea:
    config:
      server: {LFS_START_SERVER: true}          # [server] section — already rendered
      lfs:    {STORAGE_TYPE: minio, MINIO_ENDPOINT: ..., MINIO_BUCKET: ...}
    additionalConfigFromEnvs:                    # secret half only
      - name: FORGEJO__LFS__MINIO_ACCESS_KEY_ID
        valueFrom: {secretKeyRef: {name: forgejo-s3-secret, key: access_key_id}}
```

---

## 3. SeaweedFS in this fleet

### 3.1 Chart + which cluster

- `charts/seaweedfs/` = **wrapper around upstream `seaweedfs` helm chart `4.50.0`**
  (`charts/seaweedfs/Chart.yaml:9`), wrapper version 1.0.37. Templates in-repo are only
  extra Services/Ingress (`seaweedfs-{filer,master,s3,volume}-*-service.yaml`,
  `seaweedfs-volumes-ingress.yaml`).
- **Deployed on `infra` only**: `services/infra/prod/values.yaml:26-30`
  (`charts.seaweedfs`, `ServerSideApply: "false"`).
- `seaweedfs-csi-driver` (client side) is deployed on **infra, gpu, home, media,
  proxy-local, proxy-backup** (`services/*/prod/values.yaml`: infra :31, gpu :103,
  home :71, media :15, proxy-backup :31, proxy-local :44). **`dev` has NEITHER** —
  no `seaweedfs`, no `seaweedfs-csi-driver` entry in `services/dev/prod/values.yaml`.

### 3.2 S3 gateway — live args (this is the load-bearing read)

LIVE infra: `Deployment/seaweedfs-s3` (not a StatefulSet), 1/1 ready, image
`chrislusf/seaweedfs:4.50`, container command:

```
exec /usr/bin/weed -logtostderr=true -v=1 s3 \
  -ip.bind=0.0.0.0 -port=8333 -metricsPort 9327 \
  -domainName=s3.spencerslab.com \
  -filer=seaweedfs-filer-client.default:8888 \
  -port.lance=9101
```

- **No `-s3.config`, and `s3.enableAuth` is commented out in the chart
  (`charts/seaweedfs/values.yaml:419-420`)** → the gateway is running **unauthenticated**.
  Any credentials Forgejo sends are accepted-but-not-validated today. Enabling auth is a
  shared-infra change touching every consumer (Loki first) — flag for the plan.
- `s3.enabled: true`, `allowEmptyFolder: true`, `s3.domainName: "s3.spencerslab.com"`
  (`charts/seaweedfs/values.yaml:416-429`), upstream `s3.ingress.enabled: false` (:423-424)
  — the public route comes from the umbrella instead (below).
- Other components live: `seaweedfs-master` 1/1, `seaweedfs-filer` **5/5**,
  `seaweedfs-volume` **8/8** (chart says `replicas: 5` at `values.yaml:133` — live is 8,
  a repo-vs-live drift to note but not this ticket's), `seaweedfs-admin` 1/1
  (`allowInsecureBind: true`, `values.yaml:25-32`).
- Filer bucket root: `WEED_FILER_BUCKETS_FOLDER: "/buckets"` (`values.yaml:404`) —
  i.e. **S3 bucket ≡ directory under `/buckets` ≡ collection**.

### 3.3 The addresses a consumer uses

| path | address | evidence |
|---|---|---|
| in-cluster, **infra only** | `seaweedfs-s3.default.svc.cluster.local:8333` (ClusterIP; ports 8333, 18333 grpc, 9327 metrics) | `charts/seaweedfs/templates/seaweedfs-s3-service.yaml`; LIVE: Service exists since 2024-07-27, Endpoints populated (`10.42.0.94:8333`, pod `seaweedfs-s3-d564967dd-cgrcq`) |
| cross-cluster / public | **`https://s3.spencerslab.com`** (TLS) | LIVE infra Ingress `s3-ingress`: host `s3.spencerslab.com` → `seaweedfs-s3:8333`, `ingressClassName: traefik`, TLS secret **`wildcard-cert`**; rendered from `services/infra/prod/values.yaml:79-82` (`ingress.subdomains.s3`) via the umbrella `generic-ingress` |
| filer (file API, for context) | `seaweedfs-filer:8888`, `seaweedfs-filer-client:8888` | templates + live Service list |

Cross-cluster HTTPS to the gateway **works today**: LIVE monitoring cluster's
`loki-backend-0` (chart `loki-7.5.0`, v3.6.11, 2/2 Running) is configured with
`storage.type: s3`, `endpoint: https://s3.spencerslab.com`, `region: us-co-1`,
`s3forcepathstyle: true` (`charts/loki/values.yaml:9-34`) and its log tail shows healthy
S3 reads/compactions (`downloaded file`, `mark file created …/s3_2026-01-02/markers/...`)
with **no digest/signature/403/500 errors**. Cross-cluster CSI mounts to the same SeaweedFS
cluster also work from gpu/home/media/proxy-* (static PVs below).

### 3.4 Existing consumers of the shared SeaweedFS storage pattern

Two distinct patterns exist — do not conflate:

1. **S3 API (HTTP)** — the *only* consumer in-repo is **Loki**
   (`charts/loki/values.yaml` + `charts/loki/templates/secret-s3.yaml`). Buckets:
   `logs` for chunks/ruler/admin (`bucketNames`, `charts/loki/values.yaml:11-14`).
2. **CSI static PVs (`seaweedfs-csi-driver`) pointing at `/buckets/<collection>`** — 12+
   such PV/PVC pairs in `services/infra/prod/templates/` (`pvc-{git,dev,media,documents,
   pictures,backups,backup-gpu,backups-business,monitoring-logs,monitoring-metrics,
   artifacts}-seaweedfs.yaml`) plus gpu's `pvc-{dev,media,knowledge}-seaweedfs.yaml`, and
   the documented `shared-storage` override pattern in
   `skills/helm-chart-creation/references/storage-and-secrets.md` (§"Shared storage
   pattern (SeaweedFS)", worked example `services/gpu/prod/templates/pvc-knowledge-*` +
   `services/gpu/prod/values.yaml:519-522`). StorageClasses: `seaweedfs-extra`,
   `seaweedfs-important`, `seaweedfs-backups`, `seaweedfs-backup-important`
   (`services/infra/prod/templates/pvc-storage-classes.yaml`).

**Directly relevant leftover:** there is an **idle SeaweedFS-backed RWX PV/PVC pair named
`git` on infra** — `services/infra/prod/templates/pvc-git-seaweedfs.yaml`
(`collection: git`, `path: /buckets/git`, `replication: "002"`, `diskType: hdd`,
1Ti capacity, 30Gi claim, `Retain`) — LIVE **Bound**, unused by Forgejo (infra took
local-path by user decision A2, `2026-10-feat-forgejo-infra-and-runner/DECISIONS.md`).
Its own follow-up line calls it the candidate for a future LFS/attachment store
(`2026-10-21-feat-forgejo-infra-and-runner.md:366`). A plan that wants a *filesystem*
LFS store instead of S3 has that claim already provisioned; a plan that wants an S3 bucket
should note it is the same filer directory (`/buckets/git`).

**No bucket-creation mechanism exists in the repo** — grep for `weed shell`/`s3 mb`/bucket
jobs: nothing. Bucket creation is a **user-run** step (weed shell or an S3 client).

---

## 4. Secrets recipe for S3 credentials

- Stores: `bitwarden-login` (Login item: `username`/`password`) and `bitwarden-fields`
  (custom fields: `api_key`, `secret_key`, …) —
  `skills/helm-chart-creation/references/storage-and-secrets.md:11-24`.
- Item naming: one item per concern named after the service — `<service>`, `<service>-db`,
  `<service>-sso`; **never point a chart at a shared multi-consumer item** (same
  reference, §"Bitwarden item naming pattern"). Existing forgejo items: dev reuses a
  shared dev item for `-admin`/`-pg` (commented exception,
  `charts/forgejo/values.yaml:22-26`; UUIDs at `custom-values/dev/prod-values.yaml:63-67`),
  infra uses dedicated `infra-forgejo{,-admin,-pg,-sso}`
  (`custom-values/infra/prod-values.yaml:45-49`).
- **The exact S3-credential precedent to copy is Loki's**:
  `charts/loki/templates/secret-s3.yaml` — one ExternalSecret, target Secret
  `loki-s3-secret`, `data: access_key_id ← bitwarden-login property username`,
  `secret_access_key ← bitwarden-login property password`, both from
  `{{ index .Values "bitwardenIds" "loki-s3" }}`, with the mandatory
  `conversionStrategy: Default / decodingStrategy: None / metadataPolicy: None` boilerplate,
  whole template gated by `{{ if (index .Values "bitwardenIds") }}`. Note loki's chart
  ships **no `bitwardenIds:` default** — the map comes only from custom-values
  (`custom-values/monitoring/prod-values.yaml:13-15`, `loki-s3: 06a65037-…`).
  The forgejo chart's own style differs: it *does* ship the sentinel map
  (`charts/forgejo/values.yaml:17-30`) and reads by item id.
- Sentinel placement: `OVERRIDE_VIA_CUSTOM_VALUES` in the **chart** values
  (`charts/forgejo/values.yaml:17-30`) — the `services/**/values.yaml` sentinel
  convention applies to service-level `bitwardenIds` (e.g.
  `services/dev/prod/values.yaml:60-70`). Real UUIDs only in `custom-values/<category>/prod-values.yaml`.
  Precedent when the vault item doesn't exist yet: ship `OVERRIDE_NEEDED` in custom-values
  as the documented unfilled interim (`2026-10-feat-forgejo-auth-support` DECISIONS,
  infra-forgejo t6 precedent).
- **Category files for this ticket's Services labels:**
  `custom-values/dev/prod-values.yaml` (dev) and `custom-values/gpu/prod-values.yaml` (gpu).
  There is **no `custom-values/infra` entry needed for the S3 gateway itself** — the gateway
  has no credentials — but the infra Forgejo instance's own slice lives in
  `custom-values/infra/prod-values.yaml:44-63`. If a plan adds a `-s3` `bitwardenIds` key to
  `charts/forgejo/values.yaml`, **every category that deploys forgejo (dev, infra) needs the
  real UUID**, or the chart's ExternalSecret renders a sentinel → the sentinel sweep fails
  and the ESO fails to resolve. gpu only needs it if gpu actually gets a consumer (OQ1).

---

## 5. Validation this pipeline actually runs (feed the plan's `Commands`)

There is **no unit-test suite**; "tests" = shell suites under `tests/<group>/`, helm
lint/template renders, sentinel sweeps, trio greps
(`2026-10-feat-forgejo-infra-and-runner/DECISIONS.md` "Conventions"). Exact shapes used by
recent tickets:

```bash
export PATH=$HOME/.local/bin:$PATH            # MANDATORY: helm is ~/.local/bin/helm (v3.16.4)
cd "$(git rev-parse --show-toplevel)"

# forgejo chart renders (OCI dep must be vendored first; charts/**/charts is gitignored)
helm dependency update charts/forgejo
helm lint charts/forgejo
helm template dev charts/forgejo --set domain=scifi.farm --set clusterName=dev \
  --set bitwardenIds.forgejo=u1 --set bitwardenIds.forgejo-admin=u2 \
  --set bitwardenIds.forgejo-pg=u3 --set bitwardenIds.forgejo-sso=u4

# umbrella render + sentinel sweep (cf-97's exact shape)
helm template dev services/dev/prod -f custom-values/dev/prod-values.yaml \
  --set domain=scifi.farm --set clusterName=dev | grep -c OVERRIDE_ || true   # want count 0
helm template infra services/infra/prod -f custom-values/infra/prod-values.yaml \
  --set domain=spencerslab.com --set clusterName=infra | grep -c OVERRIDE_ || true

# existing regression suites this ticket touches
bash tests/services/infra-forgejo.sh          # 33-leg forgejo/infra contract
bash tests/services/dev-forgejo-runner.sh     # runner contract (48 ok after cf-97 C02)

# quality gate (CI-pinned version; aislop is not preinstalled)
npx --yes aislop@0.18.1 ci --changes --base main
```

- My run today: `helm dependency update` + `helm lint charts/forgejo` = **pass** ("0 chart(s)
  failed", only an icon INFO), render of 13 docs = **pass**. Rendered kinds (useful for test
  authoring): `Secret dev-forgejo-inline-config`, `Secret dev-forgejo`, `Secret
  dev-forgejo-init`, `PVC forgejo`, `Service dev-forgejo-http`, `Service dev-forgejo-ssh`,
  `Deployment dev-forgejo`, `Cluster pg-forgejo`, `ExternalSecret forgejo-admin-secret`,
  `ExternalSecret pg-forgejo-secret`, `ExternalSecret forgejo-secret`,
  `TCPRoute dev-forgejo-ssh`, `Pod dev-forgejo-test-connection`.
- New-suite convention: `tests/services/<area>-<topic>.sh`, fail-fast, numbered legs (`t1…`),
  auto-discovers the helm binary (`HELM_BIN`, PATH, `~/.local/bin`, `/tmp/opencode`, else
  downloads v3.21.4), **skips (not fails) helm legs when the OCI registry is unreachable**,
  and copies the chart to `/tmp/opencode/…` so the worktree is never written
  (`tests/services/infra-forgejo.sh:1-30`).
- pytest exists only for `charts/gpt-researcher/tests` and `charts/llama-swap/tests`
  (render-contract tests that shell out to `helm template`; they self-skip when `helm` or the
  vendored dep tgz is missing — `charts/gpt-researcher/tests/test_render.py:26-40`). CI runs
  them per-directory: `helm dependency update charts/<c>` then `pytest charts/<c>/tests -v`
  (`.github/workflows/gpt-researcher-render-tests.yaml:47-57`,
  `llama-swap-tools-tests.yaml`). **AGENTS.md: pytest must be run per-directory** — test
  basenames duplicate across suites. A new pytest suite for this ticket would need its own
  workflow (none exists for forgejo).
- CI does **not** run `tests/services/*.sh`. CI legs that will fire for this diff:
  `aislop.yaml` (`npx aislop ci --changes`, gate `failBelow: 80`, `.aislop/config.yml`) and
  `release.yaml` (bumps `charts/forgejo` `version` patch on merge to main — do not hand-bump).
  Known no-op: **aislop doesn't score YAML/MD**, and in this repo it silently skips its
  format/lint engines (`missing tools: ruff`) — see cf-97 FRICTION; comment quality rides
  `comment-slop` + review.

---

## 6. How I pinned the upstream chart surface (repeatable)

The wrapper vendors nothing, so the subchart's values schema had to be read from the pinned
version. Recipe (read-only, no worktree writes):

```bash
export PATH=$HOME/.local/bin:$PATH
helm pull oci://code.forgejo.org/forgejo-helm/forgejo --version 17.3.1 \
  --untar --untardir /tmp/opencode/forgejo-helm
# → gitea.config.lfs / gitea.config.storage: values.yaml:665-675, schema additionalProperties: true
# → S3/minio example: docs/ha-setup.md:85-110
```

Same trick as the tests' "copy to /tmp + `helm dependency update`" convention
(`tests/services/infra-forgejo.sh:10-13`). FRICTION port: `code.forgejo.org` is Anubis
bot-gated for plain fetches; the OCI registry pull works fine.

---

## 7. MCP / cluster handles for live confirmation

Namespaces: **`default` on every cluster** in scope (forgejo, seaweedfs, loki, CNPG).

| purpose | server | exact call shapes that worked |
|---|---|---|
| infra SeaweedFS args/state | `readonly-infra-kubernetes` | `resources_get({apiVersion:"apps/v1",kind:"Deployment",name:"seaweedfs-s3",namespace:"default"})` (args live in `spec.template.spec.containers[0].command`); `resources_get` Service/Endpoints/Ingress `s3-ingress`; `pods_get` for env |
| dev forgejo state | `readonly-dev-kubernetes` | `pods_list_in_namespace({namespace:"default",labelSelector:"app.kubernetes.io/name=forgejo"})` then `pods_get` (init-container env = the app.ini inputs) |
| infra forgejo state | `readonly-infra-kubernetes` | `resources_get` `Deployment/infra-forgejo`; `resources_list({apiVersion:"postgresql.cnpg.io/v1",kind:"Cluster"})` → `pg-forgejo` |
| S3-consumer health precedent | `readonly-monitoring-kubernetes` | `pods_list_in_namespace` labelSelector `app.kubernetes.io/name=loki`, `pods_log({name:"loki-backend-0",namespace:"default",tail:120})` |
| gpu side (if OQ1 says gpu matters) | `readonly-gpu-kubernetes` | same shapes |
| board reads | `dev-boards` (args are snake_case: `board_id`, `card_id`, `checklist_id`) | `list_checklists` then `get_checklist` per checklist |

Also available and read-only in this session: `readonly-gpu-ai`… — **note the naming
quirk**: the `gpu-ai` cluster's server is `readonly-ai-gpu-kubernetes` (cluster token
reversed). `admin-*` tiers are denied to this role; **no tier grants pod exec** — anything
needing `weed shell`, `s3 ls`, `forgejo migrate-storage`, or an app.ini dump is a
**user-run** step (present the exact command).

Live-state shortcuts already paid for: SeaweedFS S3 = Deployment (not STS); buckets are
**not** enumerable via k8s (see §9); Secret reads are RBAC-denied.

---

## 8. Gotchas to carry (repo-confirmed, most already in a FRICTION file)

1. **appset value law**: only the top-level `<appName>:` slice reaches a release
   (`charts/base/templates/appset-charts.yaml:32-36`); `shared-storage` and `subDomain` are
   injected separately. Per-instance LFS endpoint/bucket ⇒ `custom-values/<c>`, not
   `charts.<appName>`.
2. **Secrets are invisible to agents**: `resources_get` on a Secret →
   `…cannot get resource "secrets"` (LIVE, dev). No pod exec. Live app.ini content is
   therefore **not** directly observable; use the render + init-container env + reloader-stamp
   oracles documented in cf-97's Commands.
3. **wekan-mcp checklist flag is `finished`**, not `isDone`/`done`; and
   `list_checklists` returns items as an empty array — you must `get_checklist` per
   checklist id. (I initially mis-read every checklist as unchecked; corrected.)
4. `resources_list` returns **summary rows** (`Name`, `Labels`, `Age`, `Images`, `Ready`),
   not full objects — `items[i].metadata` is undefined; spec inspection needs `resources_get`
   by exact name. Earlier tickets also recorded `resources_list` name redaction and empty
   `pods_list`/`events_list` on dev; today both worked.
5. `helm` is not on PATH (`~/.local/bin/helm`, v3.16.4); `charts/**/charts` is gitignored →
   `helm dependency update` before lint/template of `charts/forgejo` (OCI dep, needs network;
   if the registry is unreachable, tests skip those legs by design).
6. `helm template --show-only templates/<f>.yaml` erroring "could not find template" is a
   valid closed-gate proof; a `# comment` outside a `{{- if }}` leaks a comment-only manifest.
7. ESO `template.data` placeholders must be valid YAML *before* substitution (quote `{{ }}`);
   CRD-defaulted fields (e.g. `mergePolicy`) don't show in renders — read the live CR.
8. CNPG/ESO pair: the forgejo app Application runs `ServerSideApply: "false"`; the CNPG
   Cluster carries its own SSA sync option. Preserve both.
9. `services/proxy-local/prod/values.yaml` **cannot be `yaml.safe_load`'d** naively
   (redefined `&port` anchor — PyYAML ComposerError); tests use a lenient loader.
10. Don't touch `Chart.yaml version` (CI bumps) and don't hand-bump the OCI dep version
    unless the plan explicitly says so.

---

## 9. What I could NOT establish (say it plainly)

- **Live `app.ini`** on either instance (Secrets RBAC + no exec). "No `[lfs]` today" is
  proven from the *render* and the repo, plus the init-container env list; the on-disk file
  could in principle carry manual edits — unobservable to agents.
- **Which S3 buckets exist on the gateway today** (e.g. whether Loki's `logs` bucket, or
  `/buckets/git`, is visible as an S3 bucket). No S3 API surface and no pod exec. The filer
  *paths* are known from the CSI PVs; the S3 bucket list is a user-run `weed shell`/`s3 ls`.
- **SeaweedFS S3 auth feasibility/impact**: enabling `-s3.config` + identity would change a
  shared gateway used by Loki (and CSI is unaffected); nothing in the repo models it, and I
  can't observe Loki's credential behavior beyond "creds are supplied and ignored/accepted".
- **dev→`s3.spencerslab.com` reachability** is only *indirect* evidence (Loki on monitoring
  uses it healthily; dev workloads reach the lab Keycloak over `login.spencerslab.com`).
  No NetworkPolicy inventory was taken; nothing in this repo's dev manifests defines
  NetworkPolicies, and I did not enumerate live ones.
- **Forgejo key names/semantics** beyond what the pinned chart documents
  (`MINIO_BUCKET_LOOKUP`, `SERVE_DIRECT`, `[lfs]`-vs-`[storage]` key placement,
  `migrate-storage` CLI shape) — **needs research**, per the card's own
  `Research: Before Planning` answer.
- **SeaweedFS ≥4.48 multipart `BadDigest` (#12177)**: repo pins chart 4.50.0 / image
  `chrislusf/seaweedfs:4.50`. Whether that regression applies to this build is not
  repo-verifiable; Loki's healthy tail is weak counter-evidence only (different client,
  different part sizes).
- **The intended meaning of `Services: gpu`** on card #104 (see §0/OQ1).
- Whether the user wants a **new Bitwarden item** (name/id) at all, given the gateway is
  currently unauthenticated (a credential-less design is technically possible today).

---

## 10. Open questions handed to coord

1. **OQ1 (user)** — Card says Services `dev` + `gpu`; Forgejo is on `dev` + `infra` and the
   SeaweedFS S3 gateway is `infra`-only. Is `gpu` a mislabel for `infra`, or is a gpu-side
   consumer (Coder external-auth against the infra forgejo, or a gpu workload needing LFS)
   actually in scope?
2. **OQ2 (user)** — Endpoint choice per instance: infra forgejo → in-cluster
   `seaweedfs-s3.default.svc.cluster.local:8333`; dev forgejo → must use
   `https://s3.spencerslab.com` (no local gateway). Confirm that asymmetry is acceptable
   (it changes `MINIO_USE_SSL`/port per instance, so it belongs in custom-values, not the chart).
3. **OQ3 (user)** — Do we enable SeaweedFS S3 auth (shared change, Loki is the incumbent
   consumer) or keep the gateway unauthenticated and skip credentials? This decides whether
   a Bitwarden item + ExternalSecret is even needed.
4. **OQ4 (user-owned step)** — Bucket creation + `forgejo migrate-storage --type lfs` are
   not agent-executable (no exec/vault surfaces); plan them as labelled User actions with
   exact commands, like cf-97 does.
5. **OQ5 (research)** — Forgejo 15 `[lfs]`/`[storage]` key set and semantics (incl. the
   chart's "`MINIO_BUCKET` is not a bucket" note vs SeaweedFS's bucket=collection model),
   `SERVE_DIRECT`/`MINIO_BUCKET_LOOKUP` validity, and the #12177 exposure against 4.50.
6. **OQ6 (plan)** — Scope: reuse the idle infra SeaweedFS `git` collection/PVC
   (`/buckets/git`) as the LFS home, or a purpose-built bucket? And dev-vs-infra rollout
   order (dev first is the repo's usual proving ground).

---

## Runner surface (gpu) — round 2

Appended 2026-11-03 by the second `agent-explore` round, after the batched question round
resolved OQ1: card #104's `gpu` Services check means the **Forgejo runner**, not a Forgejo
instance. Only runner facts are here; §1–§10 stand and are not repeated. Same evidence
convention (`path:line` read in this worktree, `LIVE <cluster>` = readonly MCP probe,
`LIVE probe` = read-only network GET/POST/registry probe from this session).

### R0. The one-sentence answer

The runner exists **only on `dev`** (one release, talking to the dev instance), its *daemon*
image has git but **no git-lfs**, and its **job** images (`ghcr.io/catthehacker/ubuntu:act-*`)
**do** ship git-lfs — so "make the runner LFS-capable" is not an image-side change for the
four `ubuntu-*`/`docker` labels; it is a server-side (`[lfs]`) change plus, if `gpu` means a
gpu-hosted runner, a new ApplicationSet/custom-values trio.

### R1. Where the runner lives (repo + live)

| fact | evidence |
|---|---|
| Chart | `charts/forgejo-runner/` — **app-template wrapper** (`Chart.yaml:9-12`: dep `app-template` 5.0.1, `https://bjw-s-labs.github.io/helm-charts/`), wrapper `version: 1.0.2`, `appVersion: 13.2.0`. Files: `Chart.yaml`, `Chart.lock`, `values.yaml` (247 lines), `templates/NOTES.txt`, `templates/secret-runner.yaml` (the ExternalSecret **and** the whole runner `config.yaml`), no `tests/` dir |
| Deployed today | ONE release: `services/dev/prod/values.yaml:102-105` (`charts.forgejo-runner-dev` + `ServerSideApply: "false"` + `chart: forgejo-runner` alias) + TOP-LEVEL slice `:164-166` (`runner.url: http://dev-forgejo-http:3000`) + `custom-values/dev/prod-values.yaml:82-88` (`bitwardenIds.runner-token: d3dafd1a-…`, item `dev-forgejo-dev-runner`) |
| Instance served | the **dev** Forgejo, in-cluster (`dev-forgejo-http:3000`). `runner.url` chart default `http://dev-forgejo-http.default.svc:3000` (`values.yaml:49-50`) is a render stand-in |
| Infra runner | un-wired by user decision 2026-10-25 (commit `32b445cd6` "un-wire forgejo-runner-infra"; `2026-10-feat-forgejo-auth-support/DECISIONS.md:236,242`). Vault item `dev-forgejo-prod-runner` + the server-side runner record on `git.spencerslab.com` stay "for the future relocation"; its UUID is recorded in `2026-10-refactor-forgejo-runner-per-instance/DECISIONS.md:20` (not reprinted here) |
| LIVE dev | Applications (apiVersion `argoproj.io/v1alpha1`, ns `default`): `dev-forgejo`, `dev-forgejo-runner-dev` (12 apps total, 9d old). STS `dev-forgejo-runner-dev` **1/1**, container `runner`, image `data.forgejo.org/forgejo/runner:13.2.0`. Pod `dev-forgejo-runner-dev-0` `pods_log`: `runner: Dev Runner, with version: v13.2.0, with labels: [ubuntu-latest ubuntu-24.04 ubuntu-22.04 docker node22], declared successfully` (2026-11-02T19:23:40Z) → **online against dev** |
| LIVE gpu | **No forgejo and no runner anywhere on gpu**: zero `forgejo`/`runner` name hits across `resources_list` of StatefulSet, Deployment, Service (ns `default`) and Application (19 apps). gpu *can* host one: k3s (rancher-mirrored images), StorageClasses `local-path` (default) + `seaweedfs-storage` → the chart's `local-path` VCTs (`values.yaml:68-85`) need no change; gpu already pulls ghcr.io + docker.io images today |

Gotchas: app-template names every resource by the **release**, so the pod's
`app.kubernetes.io/name` label is `dev-forgejo-runner-dev` — a `labelSelector
app.kubernetes.io/name=forgejo-runner` returns `null` (my probe did). Argo Applications are
`argoproj.io/v1alpha1`; `v1alpha2` errors "no matches for kind".

### R2. Does the runner's git have LFS? Three git environments — answer differs per one

**(a) The runner daemon image — git yes, git-lfs NO.** Live image
`data.forgejo.org/forgejo/runner:13.2.0` (amd64 manifest `sha256:874c731a…`, config
`sha256:9f1e98df…`, LIVE probe of `https://data.forgejo.org/v2/…`, no auth needed). History:
`ADD alpine-minirootfs-3.24.2-x86_64` → `apk add --no-cache git bash dumb-init` → `COPY
/srv/forgejo-runner /bin/forgejo-runner`; `User 1000:1000`, `HOME=/data`, `WORKDIR /data`,
`VOLUME [/data]`, ENTRYPOINT `/usr/bin/dumb-init`, CMD `/bin/forgejo-runner`. No `lfs` string
anywhere → the daemon has no `git-lfs` binary.

**(b) The job images — where the repo checkout actually happens — the act images DO have
git-lfs.** The label map is in `templates/secret-runner.yaml:72-77` (config.yaml
`server.connections.default.labels`), also asserted verbatim by the contract test:

```
ubuntu-latest|ubuntu-24.04|docker → ghcr.io/catthehacker/ubuntu:act-24.04
ubuntu-22.04                      → ghcr.io/catthehacker/ubuntu:act-22.04
node22                            → docker.io/library/node:22-bookworm
```

- `act-24.04` (LIVE GHCR probe, amd64 manifest `sha256:dff4ec57…`, config `sha256:cb041d0d…`,
  6 layers / 577.6 MB): base `ubuntu:24.04` + `buildpack-deps` layers (install `git`,
  mercurial, … — **no** git-lfs) then the layer `bash /imagegeneration/installers/act.sh`
  with `TYPE=act FROM_IMAGE=buildpack-deps FROM_TAG=24.04`. That installer
  (`catthehacker/docker_images`, `linux/ubuntu/scripts/act.sh` @master, LIVE fetch) does
  `add-apt-repository ppa:git-core/ppa`, `apt-get install -y git`,
  **`wget https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash` +
  `apt-get install -y git-lfs`**, and `git config --system --add safe.directory '*'`.
  → LFS filters are available in jobs on the four act labels.
- `node:22-bookworm` (LIVE Docker Hub probe, amd64 config): 12 history entries, `git` yes
  (base layer), **git-lfs: 0 hits** → the `node22` label has no LFS.
- Caveat on (b): the act images' `org.opencontainers.image.revision` label is a literal
  unsubstituted `${BUILD_REF}`, so I could **not** pin the installer commit that built the
  pinned tag. Verify in-job (`git lfs version`) rather than trusting this.

**(c) The gpu-side git client that already works: the Coder workspace image.**
`containers/coder-workspace/Dockerfile:112` installs `git git-lfs …` and `:115` runs
**`git lfs install --system`**; the Coder Terraform startup script repeats the install
(`charts/coder/coder-templates/kubernetes/main.tf:188`). LIVE from this session's own
workspace (a gpu-cluster pod): `git-lfs/3.7.1`, `git 2.56.0`, `/etc/gitconfig` carries the
four `filter.lfs.*` keys. So the human/agent git path on gpu is LFS-ready today; only the
Actions path is in question.

**Config surface today (what is NOT set).** LIVE pod spec of `dev-forgejo-runner-dev-0`:
volumes are only `data` + `docker-data` (VCT PVCs), `runner-creds` (Secret
`dev-forgejo-runner-dev`) and the `socket` emptyDir; mounts are `/data`,
`/run/secrets/forgejo-runner`, `/data/config/config.yaml` (subPath), `/var/run`. The runner
container env is exactly `CREDENTIALS_DIRECTORY` + `DOCKER_HOST`. **No `.gitconfig` mount, no
`~/.lfs`, no `GIT_LFS_*`/`LFS_*` env, no hostPath.** Repo grep
`gitconfig|GIT_LFS|LFS_|git-lfs` over `charts services custom-values tests` → only the
coder-workspace hits above; `LFS_START_SERVER` → **zero hits repo-wide** (confirms §2).
Injection points if a plan ever needs them: `containers.runner.env`
(`charts/forgejo-runner/values.yaml:157-161`) and the config.yaml `runner:`/`cache:`/
`container:` blocks (`templates/secret-runner.yaml:52-63`; the `runner.envs` shape is
documented in `2026-10-feat-forgejo-infra-and-runner/RESEARCH-dind-supplement.md:172`).

**SSH or HTTPS → HTTPS.** No SSH key material exists anywhere in the release (the
ExternalSecret reads only the login `username`/`password` = uuid/token pair; NOTES.txt
documents that shape). The clone and LFS URLs are ROOT_URL-derived:
`custom-values/dev/prod-values.yaml:72-80` (`ROOT_URL: https://git.scifi.farm/`) and
`custom-values/infra/prod-values.yaml:50-56` (`ROOT_URL: https://git.spencerslab.com/`), and
the instances hand out ROOT_URL-based `html_url`s (LIVE API probe). LIVE `git lfs env` in this
worktree shows the exact endpoint shapes:
`https://git.scifi.farm/CuratedForest/SpencersLab.git/info/lfs` and
`https://git.spencerslab.com/CuratedForest/SpencersLab.git/info/lfs` (remotes `dev` /
`prod`; SSH remotes exist for humans only — the §1 git-over-SSH gateway, never used by the
runner). What authenticates a checkout inside a job (the task token, and whether it may read
LFS objects) is **not observable repo-side** — see R6.

### R3. Reachability from gpu, and the LFS batch endpoint

Exact objects (LIVE):

| leg | object | host → backend | address |
|---|---|---|---|
| dev instance | Ingress `git-ingress` (ns `default`, class traefik, TLS secret `wildcard-cert`) | `git.scifi.farm` `/` Prefix → Service `dev-forgejo-http:3000` (ClusterIP 10.43.249.131) | LB **10.0.77.12** |
| infra instance | Ingress `git-ingress` + alias `forgejo-ingress` (TLS `wildcard-cert`) | `git.spencerslab.com` / `forgejo.spencerslab.com` `/` → `infra-forgejo-http:3000` | LB **10.0.77.59** |
| hub (public path only) | proxy-local ns `default`: Services `git-service`, `forgejo-service` = **ExternalName → `infra.spencerslab.com:443`**; IngressRoutes `git-local-ingress`, `forgejo-local-ingress` (crowdsec-only middleware, `services/proxy-local/prod/values.yaml:113-131`) | — | node `cloud-proxy` |

**LAN path = direct to the owning cluster's Traefik — no proxy-local hop.** This session's
sandbox is itself a gpu-cluster pod (`coder-9539094a-…`, resolv `10.43.0.10`, search
`spencerslab.com`), which makes it a free gpu-side probe oracle:

- `git.spencerslab.com` → **10.0.77.59**, `GET /api/v1/version` → 200
  `{"version":"15.0.10+gitea-1.22.0"}`
- `git.scifi.farm` → **10.0.77.12**, 200, same version → gpu reaches the **dev** instance too
- `forgejo.spencerslab.com` → **5.78.101.168** (public, hairpins) and the TLS handshake fails
  (`SSL: no alternative certificate subject name matches`) → LAN split DNS only carries
  `git.spencerslab.com`; **never use the `forgejo.` alias as a runner URL or LFS host**
- LFS batch today, both hosts: `POST /<owner>/<repo>.git/info/lfs`
  (`Accept: application/vnd.git-lfs+json`, body `{"operation":"upload",…}`) → **404 with the
  plain `Not found.` HTML/text body** on dev AND infra (probed on
  `CuratedForest/SpencersLab` and `…/SpencersLab-Dev`) → read as "the LFS route is not
  mounted", i.e. live confirmation of §2's render-level finding. (Expected contrast — an
  *enabled* endpoint should answer 401 in LFS JSON for an unauthenticated batch — is upstream
  behaviour I did not verify here; treat as a hypothesis the plan can test after C02 lands.)
- git route is reachable and not crowdsec-blocked from gpu: `GET /<repo>.git/info/refs?service=git-upload-pack`
  → **200** for dev `CuratedForest/SpencersLab`; **401** for the same path on infra (auth
  demanded for that repo) — the transport works either way, no hub/middleware rejection
- gpu→infra-Forgejo precedent already in production: gpu's coderd authenticates against
  `https://git.spencerslab.com/login/oauth/authorize`
  (`services/gpu/prod/templates/secrets-coder.yaml:31-42`)

SeaweedFS is not on the client path: with `[lfs] STORAGE_TYPE=minio` and `SERVE_DIRECT` off
(`DECISIONS.md` — SERVE_DIRECT explicitly deferred), the batch response URLs are Forgejo's own
`…/media/<uuid>` on the same host, so nothing in the ingress inventory above points at
`s3.spencerslab.com` for git clients.

### R4. Validation that exists for the runner (extend, do not invent)

`tests/services/dev-forgejo-runner.sh` — 1508 lines, **the one runner contract** (predecessor
ruling), legs: t1 dep-update+lint · t2 single-instance render per release · t3 URL-override
probe · t4 renovate built-in helm-values extraction · t5 chart sentinel + aliased `charts:`
entries + top-level slices · t6 doc ports · t7 custom-values UUID slots · t8 sentinel parity
1↔1 (deployed slice) · t9 dev-umbrella render · t10 base-chart ground-truth render · t11
cf-97 C02 wording · t12 mergePolicy pin · t13 dind socket group + identity pin.

Load-bearing literals a plan must plan around:
- `ACT_LABELS` is a **hard-coded 5-element set** (`:250-258`) — any job-image/label change is
  a red-first test edit by `agent-test` before dev.
- `CHART_DEFAULT_URL = 'http://dev-forgejo-http.default.svc:3000'` (`:260`).
- t5 pins `APP_KEYS = ('forgejo-runner-dev',)` and requires `forgejo-runner-infra` **absent**,
  scoped to `services/dev/prod/values.yaml` only — a gpu app would not trip it.
- Header lines 29-36: cluster acceptance is **not testable** by any leg — the evidence shape
  is exact-name `resources_get` StatefulSet + ExternalSecret, `pods_get`, `pods_log` gated on
  the pod-startTime/refreshInterval oracle.
- Baseline this ticket already pinned: **exit 1 / 27 ok** (t5 false positive, `STATE.json`
  `deferred`, plan Commands line 350).
- Cross-suite coupling: `tests/services/forgejo-ssh-gateway.sh:1601` re-runs
  `dev-forgejo-runner.sh` in t11 and requires **exit 0** → that suite stays red for the same
  reason.
- `tests/multi-repo/dev-wiring.sh:252-253` asserts the mosquitto trio-exemption comment in
  `services/dev/prod/values.yaml` **still cites the `forgejo-runner-dev` precedent** — do not
  delete that citation while editing the adjacent runner block.
- gpu-suite naming precedent: `tests/services/gpu-coder-sso.sh` → a gpu runner contract would
  be a new `tests/services/gpu-forgejo-runner.sh`.
- Client-only trio exemption to copy for any new runner app:
  `services/dev/prod/values.yaml:96-101` (no `ingress.subdomains` entry "by design, not an
  oversight").

### R5. Repo-side or image-side?

- **Job images (the LFS-relevant ones): no image work needed** for `ubuntu-latest`,
  `ubuntu-22.04`, `ubuntu-24.04`, `docker` — the pinned `act-*` images already ship git-lfs
  (R2b). The only job-image gap is `node22` → `node:22-bookworm` (no git-lfs). Repo-side fix,
  if wanted: change that one label's image in `charts/forgejo-runner/templates/secret-runner.yaml`
  (or drop the label) — and note that **no workflow in this repo's dev mirror uses Actions at
  all**: LIVE contents probe returned 404 for `.forgejo/workflows`, `.gitea/workflows` **and**
  `.gitattributes` on `CuratedForest/SpencersLab` @ git.scifi.farm (control probe:
  `.github/workflows` → 200, 6 files) → the repo has no LFS-tracked paths today either.
- **No in-repo runner image exists** (`ls containers/` → brother-ptouch-automation,
  coder-workspace, gpt-researcher{,-frontend}, music-assistant, okd-enketo, renovate-mcp,
  snapcast, strata, traefik-mqtt-allowlist, wekan-mcp). Putting git-lfs into the *daemon*
  image would mean a new `containers/forgejo-runner/` image (container-creation skill:
  Dockerfile + `docker-build.yaml` + `:main`/`:v<run>` reference) or a different upstream
  image — and nothing here shows the daemon needs it (its git use is action clones from
  `data.forgejo.org`, per the dind supplement §Q7/egress note).
- **If `gpu` means a gpu-hosted runner instance**, the repo-side file set is exactly:
  `services/gpu/prod/values.yaml` (a `charts:` entry `forgejo-runner-gpu:` with
  `namespace: default`, `ServerSideApply: "false"`, `chart: forgejo-runner` + a **TOP-LEVEL**
  `forgejo-runner-gpu:` slice carrying an HTTPS `runner.url` — no in-cluster forgejo exists on
  gpu, so `http://dev-forgejo-http:3000` would be dead) ;
  `custom-values/gpu/prod-values.yaml` (`forgejo-runner-gpu.bitwardenIds.runner-token` = a
  real UUID — the §4/OQ-`OVERRIDE_NEEDED` ban applies here too, the pod crash-loops without
  it); `charts/forgejo-runner/**` untouched unless the label set/config changes; plus the test
  edits in R4. The runner record + Bitwarden pair for the second instance are a **User action**
  (NOTES.txt documents: create the record persistent, uuid→username / token→password, and the
  reserved `dev-forgejo-prod-runner` item already exists for the relocation).
- **Renovate reality (matters if the plan wants the job images kept fresh):** the runner and
  dind pins in `charts/forgejo-runner/values.yaml:96-102,136-141` are tracked by renovate's
  built-in helm-values manager (the values comments claim dry-run verification 2026-10-23 and
  leg t4 asserts it — I did not re-run it). The **job images in `templates/secret-runner.yaml`
  are NOT tracked**: the repo's only template-file manager (`renovate.json` customManagers[0],
  `managerFilePatterns` covering `charts/*/templates/*.yaml`) matches
  `^[ \t]*image: <name>:<tag>`; applying that regex to the file yields **0 hits** (the labels
  are `- <label>:docker://…` lines). A job-image bump is therefore manual + a test edit.

### R6. What I could NOT establish (runner surface)

- **In-job networking/DNS**: whether a DinD job container resolves and routes
  `git.scifi.farm`/`git.spencerslab.com` (dockerd's embedded DNS forwards to the pod
  resolv.conf, plausible but unobservable without exec). Also unmanaged: the k3s MTU /
  forgejo-runner#1779 clone-failure risk the chart itself flags (`values.yaml:27-31`), which
  a cold `act-24.04` pull on a new cluster makes more relevant.
- **Checkout auth**: which token the runner gives `actions/checkout`, and whether that token
  may read LFS objects. Also the checkout version/pin a workflow would use and its `lfs:`
  input default — upstream behavior, **needs research** (not repo-groundable).
- **Whether the pinned `act-24.04` really contains git-lfs at build time**: history has no
  `lfs` string and the tag's `BUILD_REF` label is unsubstituted; my proof is the upstream
  installer at `master`. Needs an in-job `git lfs version` (User/plan action).
- **Who uses the runner**: the Actions runners API needs a token (`GET
  /api/v1/repos/<o>/<r>/actions/runners` → 401 `token is required`), private repos aren't
  listable anonymously, and only public repos surfaced in the search API were inspected (dev:
  `CuratedForest/SpencersLab`, `CuratedForest/SpencersLab-Dev`, `tms/SpencersLab-Dev`; infra:
  both listed as empty repos).
- **LFS over the SSH gateway path** (`git-lfs-authenticate`): not exercised — the runner is
  HTTPS-only (R2), so the SSH leg stays untested.
- **Which gpu reading the coordinator meant**: (i) a new runner *instance* on the gpu cluster,
  or (ii) the runner *chart* as the LFS-relevant surface (job images/labels/config) while it
  keeps running on dev. Both are fully grounded above; picking is a plan/user call — I did not
  re-ask, the round already answered "runner".

### R7. Probe shapes this round used (reuse, don't re-derive)

- `resources_list({apiVersion:"argoproj.io/v1alpha1",kind:"Application",limit:100})` — app
  inventory per cluster (v1alpha2 fails). Returns **strings** containing JSON
  (`{"items":[…]}`) — parse before filtering; summary rows only (spec needs `resources_get`).
- `pods_log({name:"dev-forgejo-runner-dev-0",namespace:"default",tail:60})` — the runner's
  declaration line is the cheapest "is it registered + which labels" oracle.
- `resources_get({apiVersion:"v1",kind:"ConfigMap",name:"coredns"|…-custom",namespace:"kube-system"})`
  — readable (unlike Secrets); gpu's `coredns-custom` rewrites
  `seaweedfs-volume-N.seaweedfs-volume.default → .infra.spencerslab.com` (evidence the
  `*.<cluster>.spencerslab.com` scheme resolves from inside gpu pods); dev has **no**
  `coredns-custom` (its pods resolve lab names via the node resolver).
- Registry probes, all anonymous-capable: `data.forgejo.org/v2/forgejo/runner/…` (no token);
  `ghcr.io/token?scope=repository:catthehacker/ubuntu:pull` then `/v2/…/blobs/<cfg>` with
  `-L` (307 to a CDN); `auth.docker.io/token?service=registry.docker.io&scope=repository:library/node:pull`.
  Config-blob `history` is the tool-presence oracle (the runner image's `apk add git bash
  dumb-init` line, the act image's `installers/act.sh` layer).
- LFS route probe: `curl -X POST -H 'Accept: application/vnd.git-lfs+json' -H
  'Content-Type: application/vnd.git-lfs+json' -d '{"operation":"upload","transfers":["basic"],"objects":[]}'
  https://<host>/<owner>/<repo>.git/info/lfs` → 404 today, 401 when enabled.
- The gpu-side oracle itself: this agent's sandbox is a gpu-cluster pod, so `getent hosts` +
  `curl` from the worktree give gpu-cluster answers with no MCP call at all.
