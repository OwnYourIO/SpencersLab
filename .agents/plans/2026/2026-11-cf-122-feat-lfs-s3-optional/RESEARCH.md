# RESEARCH — cf-122: make the S3 component of forgejo LFS optional

Research log for the ticket. Append-only; each section is dated and self-contained.

## Incident research (2026-11-09): how app.ini gets rebuilt on every boot

Scope launched by coord: the user live-edited the PVC's `app.ini` and `[lfs]` "came back".
User's assertion: "it's in the god damn secret, so whatever I do to the ini file will get
blown away on the next boot." Determine the exact mechanism, who is right, and the durable
fix. All evidence below is cited to file:line (repo chart at `origin/main` ad3e9ce4b ≡
synced revision 1865031af for everything this incident touches), to the pulled subchart
(forgejo-helm 17.3.1, OCI, fetched 2026-11-09 into `/tmp/opencode/cf122-incident/`), to the
running Forgejo app source (codeberg tag v15.0.10), and to the LIVE dev cluster read on
2026-11-09 via `readonly-dev-kubernetes` (no cluster mutation; no MCP tier grants pod exec,
so node/kubelet logs were not readable — flagged where it matters).

### TL;DR

- **Who re-writes `[lfs]` on each boot:** the pod's `init-app-ini` container, via the
  subchart's `config_environment.sh` → `environment-to-ini`, from exactly two sources:
  (a) fragment files mounted from **`Secret/dev-forgejo-inline-config`**
  (`/env-to-ini-mounts/inlines/`), (b) six optional env legs
  (`FORGEJO__LFS__*`) from **`Secret/forgejo-lfs-shape`** and **`Secret/forgejo-s3-secret`**
  (the ESO target). `environment-to-ini` only adds/updates keys — it **never deletes**.
- **The user is right, and the object is `dev-forgejo-inline-config`:** its `lfs` fragment
  (`STORAGE_TYPE=minio`, `MINIO_ENDPOINT`, `MINIO_USE_SSL`) was in the API Secret from
  **2026-11-07 14:22 (first post-merge sync with the still-stale valuesObject) until
  2026-11-09 13:23:19**, so every pod recreation in that window (crash-looping rev9 pods
  `5zn9w`, `qwnnc` @13:20:18, …) re-wrote `[lfs]` over the user's edits — observed directly
  in the 13:20/13:29 init-container logs.
- **Why it stayed stale for two days:** the child app's `valuesObject` is fed by a
  **frozen etcd annotation** (`services.dev.*.customValues` on the cluster entry), not by
  the git merge; dev's child apps also have **no `automated` sync** (lab-wide on dev —
  verified on `dev-coder`). The cf-122 plan's D9 rollout assumption ("merge → apps
  re-render, ESO pruned on sync") did not hold for this lab's wiring.
- **Current state:** the chain is now fully fresh at the API level (valuesObject flipped
  11-09 13:22:00; manual syncs 13:23:18/13:23:46 applied the fragment-free Secret and
  pruned `forgejo-lfs-shape` + the s3 ESO; app `Synced`, `argocd-cm` has no Secret
  ignoreDifferences). The crash loop is now caused solely by the **residual `[lfs]`
  section still inside `app.ini`** (written 13:29:33 from a node-stale secret volume;
  nothing ever deletes it): minio init fatals with `Bucket name cannot be empty`.
- **Durable fix (user-executed):** strip `[lfs]` from `app.ini` once, recreate the pod,
  verify the new init log shows no `lfs` section and the main log shows
  `Initialising LFS storage with type: local` / `Creating new Local Storage at /data/lfs`.
  The one-time strip **is** required — `environment-to-ini` will not delete `[lfs]` for
  you, and the residual section keeps the pod fatal-looping today.

### 1. The boot pipeline (wrapper `charts/forgejo` + forgejo-helm 17.3.1 subchart)

Release name is `dev-forgejo` (appset naming `<serviceName>-<appName>`,
`charts/base/templates/appset-charts.yaml:42`), so subchart `gitea.fullname` =
`dev-forgejo` and every subchart object is named `dev-forgejo*`.

**Secrets the pod mounts, and where** (live pod spec, `dev-forgejo-c4ccf6fcb-mwklh`,
read 2026-11-09; template source subchart `templates/gitea/deployment.yaml`):

| Volume → mountPath | Secret | Used by |
|---|---|---|
| `init` → `/usr/sbin` (init-directories, configure-gitea) | `dev-forgejo-init` (`deployment.yaml:398-401`) | scripts only: `init_directory_structure.sh`, `configure_gitea.sh`, gpg/ssh signing (`templates/gitea/init.yaml:4,10-17` — the secret carries exactly these 4 script keys, nothing else) |
| `config` → `/usr/sbin` (**init-app-ini only**) | `dev-forgejo` main Secret (`deployment.yaml:402-405,117-118`) | `config_environment.sh` runs from here (`command: ["/usr/sbin/config_environment.sh"]`, `deployment.yaml:100`). The main Secret is rendered by subchart `templates/gitea/config.yaml:11-21,52-53` and carries **exactly two keys: `assertions` (empty, multi-replica checks) and `config_environment.sh`**. **There is no `app.ini` key in any Secret in this chain** — no full app.ini is ever copied over the PVC one; the classic gitea-chart `init-app-ini`-copies-app.ini behavior does not exist in forgejo-helm 17.3.1 |
| `inline-config-sources` → `/env-to-ini-mounts/inlines/` | `dev-forgejo-inline-config` (`deployment.yaml:409-411`) | the fragment files; one file per config section, filename = section name |
| `data` → `/data` | PVC `forgejo` (10Gi, local-path, RWO; `deployment.yaml:436-441`, wrapper `values.yaml:52-59` era) | `GITEA_APP_INI=/data/gitea/conf/app.ini` (`deployment.yaml:102-103,304-305`) |

**`dev-forgejo-inline-config` content builder:** subchart `templates/gitea/config.yaml:1-10`
renders the Secret's `stringData` from the `gitea.inline_configuration` helper
(`templates/_helpers.tpl:187-216`): for each map-valued section of the **merged**
`gitea.config`, it emits `KEY=VALUE` lines (`printf "%s=%v"`, no `tpl`); **empty maps are
skipped** (`if kindIs "map" $value` + `gt (len $value) 0`). The subchart's own default is
`gitea.config.lfs: {}` (pulled tgz `values.yaml:665-666`), so a `lfs` fragment appears in
the Secret **iff the merged values carry a non-empty `forgejo.gitea.config.lfs` map** —
i.e. iff the instance's values declare `lfs.STORAGE_TYPE`/`MINIO_ENDPOINT`/… The wrapper
gate (`charts/forgejo/templates/_helpers.tpl:8-9`, `forgejo.lfs.s3.enabled`) is
`eq (toString (get … "lfs" … "STORAGE_TYPE" | default "")) "minio"` and controls only the
two **additional** objects (`secret-forgejo-lfs-shape.yaml:1`, `secret-forgejo-s3.yaml:1`)
— it does not control the fragment; the fragment follows the values directly.

**Init order and exact semantics.** Three init containers run in pod-spec order
(`deployment.yaml:61-288`): `init-directories` (`init_directory_structure.sh` —
`mkdir -p /data/gitea/conf` etc., never touches app.ini), then **`init-app-ini`**
(`config_environment.sh`), then `configure-gitea` (`configure_gitea.sh` — DB migrate +
admin user + OAuth; never touches app.ini). `config_environment.sh` (subchart
`scripts/config_environment.sh`, byte-identical across both tgz generations observed):

```bash
# line 142: snapshot the pod's own FORGEJO__* envs (the env legs) before anything else
env | (grep -e '^FORGEJO__' || [[ $? == 1 ]]) > /tmp/existing-envs
# line 145: generate 4 secrets as envs (INTERNAL_TOKEN, SECURITY__SECRET_KEY,
#           OAUTH2__JWT_SECRET, SERVER__LFS_JWT_SECRET)
env2ini::generate_initial_secrets
# lines 147-148: THE "Processing inlines…" STEP — reads every symlink in the mounted
#                fragment dir; section = basename of the file; each line
#                KEY=VALUE -> export FORGEJO__<SECTION>__<KEY>=VALUE (lines 4-49, 87-102)
env2ini::load_config_sources '/env-to-ini-mounts/inlines/'
env2ini::load_config_sources '/env-to-ini-mounts/additionals/'   # empty for dev (no additionalConfigSources)
# line 151: re-export the pod's OWN envs AFTER the files -> env legs win over fragments
env2ini::reload_preset_envs
# lines 156-167: if app.ini exists, DROP the 4 auto-generated secret envs only
#                (so they never overwrite vault-persisted keys)
if [ -f "${GITEA_APP_INI}" ]; then unset FORGEJO__SECURITY__INTERNAL_TOKEN … fi
# line 169: merge everything into the ini
environment-to-ini -o "${GITEA_APP_INI}"
```

Answer to the launch's question "does the inlines step sed/awk-strip existing sections
first?": **no.** `load_config_sources`/`process_config_file`/`read_config_to_env`
(lines 87-116) only *export environment variables* — they never read or write
`app.ini`. The only writer is the final `environment-to-ini` call, whose semantics are
**create-section-if-absent, create-key-if-absent, overwrite-value** — and iterate only
over env vars that exist (Forgejo v15.0.10 `modules/setting/config_env.go`,
`EnvironmentToConfig`: `cfg.GetSection` → `cfg.NewSection` on error, `ConfigSectionKey`
→ `section.NewKey` on nil, `key.SetValue(keyValue)`; the function loops over
`os.Environ`/the passed env list — there is no delete path). **Nothing in the boot
pipeline ever deletes a section or key from `app.ini`** (known, now source-verified):
a `[lfs]` absent from all boot sources stays absent; a `[lfs]` present in `app.ini`
stays present, and any source that still carries `[lfs]` keys overwrites exactly those
keys on every boot.

### 2. The two write-back modes, precisely

**(a) per-fragment inline writing (from `dev-forgejo-inline-config`).** Each Secret key
becomes a fragment file; `KEY=VALUE` lines export `FORGEJO__<key-as-section>__<KEY>`.
For dev in the stale era the `lfs` fragment was exactly:

```
lfs: |-
  MINIO_ENDPOINT=s3.spencerslab.com
  MINIO_USE_SSL=true
  STORAGE_TYPE=minio
```

(re-rendered this round from the live app's historical valuesObject — see §4 evidence;
pre-cf-122 it was 7 lines with the 4 shape constants still in the fragment, the
cf-122 design moved them to the shape Secret: plan D2).

**(b) environment-to-ini env legs (from the pod spec's static list).** The wrapper pins
eight legs in `charts/forgejo/values.yaml:123-187`: two core hard refs
(`FORGEJO__DATABASE__PASSWD` ← `pg-forgejo-secret/password`,
`FORGEJO__SECURITY__SECRET_KEY` ← `forgejo-secret/SECRET_KEY`) and six LFS legs,
**all six `optional: true`** (`:152-187`): 2 cred legs ← `forgejo-s3-secret`
(`access_key_id`/`secret_access_key`), 4 shape legs ← `forgejo-lfs-shape`
(`MINIO_BUCKET`/`_MINIO_BUCKET_LOOKUP`/`_MINIO_CHECKSUM_ALGORITHM`/`SERVE_DIRECT`).
Lower-cased section resolution puts them in `[lfs]` (comment at `values.yaml:140-141`).
`optional: true` = when the referenced Secret is absent, the env var is simply missing
and `environment-to-ini` has nothing to write for that key.

**Fresh chain (current desired): can `[lfs]` STORAGE_TYPE=minio reappear on a fresh
boot? No — proof by source enumeration.** A boot writes `[lfs]` keys only if a source
supplies them:
- Fragment source: the desired `dev-forgejo-inline-config` rendered from today's
  `origin/main` chart + the live valuesObject (which carries **no** `forgejo.gitea.config.lfs`
  block — verified in the app spec and in `status.history` #67/#68) contains **no `lfs`
  key** (render: `/tmp/opencode/cf122-incident/renders/gateclosed-argocd.yaml`, Secret
  stringData keys = `_generals_ cache database metrics queue repository security server
  service session`; independent re-render at the correct release name by a parallel
  forensics session, `/tmp/opencode/cf122-forensics/render-fresh.yaml`, keys identical,
  and its `checksum/config` `3b77bfac…` equals the live Deployment's — i.e. ArgoCD's
  actual render is fragment-free).
- Env-leg source: all six LFS legs resolve to *absent* — `forgejo-lfs-shape` and
  `forgejo-s3-secret` were pruned by the 13:23:46 sync (app-controller log:
  `Adding resource result … 'Pruned' … kind=Secret name=forgejo-lfs-shape` and
  `kind=ExternalSecret name=forgejo-s3-secret`, syncId 00334-Pvqix) and are absent from
  the live ESO list (read 2026-11-09); the 13:29:33 init log confirms it: "Reloading
  preset envs…" lists only `FORGEJO__SECURITY__SECRET_KEY` and
  `FORGEJO__DATABASE__PASSWD` — none of the six LFS legs.
- Auto-generated envs: the four generated secrets are unset when `app.ini` exists
  (`config_environment.sh:156-167`) and none of them is an `[lfs]` key anyway
  (`LFS_JWT_SECRET` lands in `[server]`).
∴ **no source supplies any `[lfs]` key; `environment-to-ini` creates nothing; a fresh
boot leaves `[lfs]` untouched — and, since nothing deletes, a pre-existing `[lfs]`
persists (it does not come back, it never went away).**

**The exact stale condition that makes it (re)appear:** any of, still live at pod
creation time:
1. `dev-forgejo-inline-config` carrying the `lfs` fragment shown above (re-writes the
   3 activation keys — this is "the god damn secret" the user meant), and/or
2. `forgejo-lfs-shape` existing (re-writes the 4 shape keys via optional legs), and/or
3. `forgejo-s3-secret` existing (re-writes the 2 credential keys).
With only (1) live — the current 13:29 state — the boot re-writes exactly
`STORAGE_TYPE`/`MINIO_ENDPOINT`/`MINIO_USE_SSL` into `[lfs]` and nothing else: which is
precisely what the 13:29:33 init log shows, and why the subsequent main-container fatal
is `Bucket name cannot be empty` (no shape keys, no bucket in `[lfs]`).

### 3. The ArgoCD apply-vs-rollout race anatomy for this chart

**No sync waves.** Neither the wrapper nor the subchart templates carry
`argocd.argoproj.io/sync-wave` annotations (grepped the full render and
`charts/{forgejo,base}` on main; only `charts/okd` and `charts/hivetools` use waves in
this repo). All forgejo objects sit in wave 0, so ArgoCD orders them by its default
precedence — phase → wave → **kind** → name (ArgoCD docs, *Sync Phases and Waves*,
stable: "Order all resources according to their wave … By kind … By name"; the kind
table is gitops-engine `pkg/sync/sync_tasks.go` at the commit the docs pin,
`bc9ce57…`: `Secret` is index 7, `Service` 22, `Deployment` 27 —
`sortTasks.Less` compares phase, then wave, then kind, then name). **Within any single
sync, `dev-forgejo-inline-config` (and all Secrets) are therefore always applied before
the `dev-forgejo` Deployment** — confirmed empirically in today's op 00310:
`Applying resource Secret/dev-forgejo-inline-config` @13:23:19 precedes
`Applying resource Deployment/dev-forgejo` @13:23:19 (results: `secret/… configured`
then `deployment.apps/dev-forgejo configured`, syncId 00310-pSgvP).

**Coupling that makes this safe by design:** the pod template carries
`checksum/config: sha256(rendered gitea/config.yaml)` (subchart
`deployment.yaml:33`), and `config.yaml` is the template of *both* the
`dev-forgejo-inline-config` Secret and the main Secret. So whenever the fragment Secret
content changes, the Deployment's desired pod template changes in the **same** render
and the same sync applies Secret-then-Deployment; the rolled pod mounts the new
Secret. A pod "created mid-sequence" inside one sync cannot run inits against the
previous Secret revision — the Secret lands first.

**The races that actually fired here are between syncs / actors, not within one sync:**

1. **Stale-spec syncs (the big one).** The child app's `valuesObject` is not git-driven:
   it is assembled by the appset from the **cluster-annotation** layers
   (`charts/base/templates/appset-charts.yaml:114-123`:
   `merge(appCustomValues, serviceCustomValues, baseValues)` where the `*CustomValues`
   come from annotations `services.dev.forgejo.customValues` /
   `services.dev.customValues` on the in-cluster ArgoCD entry, while the umbrella `dev`
   app *does* pull `custom-values/dev/prod-values.yaml` live from
   `raw.githubusercontent.com/…/refs/heads/main` via `customValuesUrls` — its spec
   shows the URL in `valueFiles`). The merge of cf-122 into `main` changed the git file
   but not the frozen annotation; the appset regenerated the child spec only when the
   annotation flipped, at **2026-11-09 13:22:00** (appset-controller log:
   "updated Application dev-forgejo"; `status.sync` then went `Synced → OutOfSync` at
   13:22:03). Until then, every sync re-applied the **stale** (lfs-bearing) desired
   state: ops 00257/00281 at 13:21:29/13:21:45 (both with the old
   `ValuesObject` — the op dumps in the controller log show
   `lfs: {MINIO_ENDPOINT, MINIO_USE_SSL: true, STORAGE_TYPE: minio}` and
   `bitwardenIds.forgejo-s3: 06a65037-…`) kept the fragment in the API Secret. And the
   whole 11-07 14:22 → 11-09 13:21 window ran on the stale desired state
   (`status.history` #59–#66: five deploys, all `lfs=YES s3uuid=YES`), so the rev9 pod
   that crash-looped all that time was re-writing `[lfs]` on **every pod recreation**.
2. **Manual-sync-only apps.** `dev-forgejo`'s live `spec.syncPolicy` has **no
   `automated` block** (only `syncOptions: [CreateNamespace=true,
   ServerSideApply=false, RespectIgnoreDifferences=true]`); `dev-coder` is the same.
   The appset template renders `automated {prune, selfHeal}` only unless the
   selfHeal annotation says otherwise (`appset-charts.yaml:132-138`) — on dev it is off,
   so nothing in the chain ever synced by itself; the plan's D9 expectation
   ("merge bumps the wrapper version → both forgejo apps re-render; the dev ESO is
   pruned on sync") assumed automated sync that does not exist here.
3. **Node-local secret-volume eventual consistency (the 13:29 anomaly).** After the
   fragment-free applies (13:23:19/47) the API Secret was clean and stayed clean
   (ArgoCD `Synced` at 13:23:47; level-2 comparison 13:30:19: "No status changes";
   no dev-forgejo controller activity at all in 13:24:00–13:31:00; no Secret
   ignoreDifferences anywhere — live `argocd-cm` has
   `resource.customizations.ignoreDifferences` only for `apps_Deployment/
   apps_StatefulSet/apps_DaemonSet` (reloader `last-reloaded-from` annotations) and
   `upgrade.cattle.io_Plan /status`). Yet the pod `dev-forgejo-c4ccf6fcb-mwklh`,
   created 13:29:31, ran `init-app-ini` at 13:29:33 against a volume that still held
   the 3-line `lfs` fragment. Kubernetes documents secret volumes as
   **eventually-consistent**: "the kubelet keeps a cache of the current keys and values
   for the Secrets that are used in volumes for pods on that node … total delay … can
   be as long as the kubelet sync period + cache propagation delay"
   (kubernetes.io, *Secrets*); the kubelet's watch-based object cache
   (`pkg/kubelet/util/manager/watch_based_manager.go`, master) tears down an entry when
   the last referencing pod disappears and re-LISTs on a new reference, with a ≤1 s
   sync wait in `Get` — the exact k3s v1.36.5 path that served the stale file could not
   be confirmed from here (no pod-exec tier; `nodes_log` for kubelet is not
   accessible to the MCP service account). It is the only remaining explanation
   consistent with all API-side evidence, and it is flagged as open question OQ-1
   with a distinguishing command.

**Reliable fix sequence (from this anatomy):** get the *values* right first
(annotation/valuesObject), then one **sync with prune** (the prune is what deletes the
gate-open-only objects `forgejo-lfs-shape` + `forgejo-s3-secret`), confirm
`Synced`, then let the rollout run — and **verify the boot that follows**: the new
pod's `init-app-ini` log must show no `lfs` section under "Processing inlines…" and the
main log must show the local-storage oracles. If a boot shows the fragment while the
API Secret is clean, re-create the pod (and if that recurs, treat it as the node
secret-cache anomaly, OQ-1). Sync waves are unnecessary for this chart — the kind
ordering already puts the fragment Secret ahead of the Deployment in every sync.

### 4. Verdict table — current live chain (fresh git values → fresh render)

| Question | Verdict | Evidence |
|---|---|---|
| Is the desired `dev-forgejo-inline-config` lfs-free now? | **Yes** | valuesObject (app spec + `status.history` #67/#68, 13:23:20/13:23:47): no `forgejo.gitea.config.lfs`, no `bitwardenIds.forgejo-s3`; re-render with the live valuesObject: fragment keys absent; live Deployment `checksum/config` `3b77bfac…` equals that render's checksum byte-for-byte (parallel-session `render-fresh.yaml`) → ArgoCD's render == my render |
| Fragment file list the desired Secret would carry | `_generals_, cache, database, metrics, queue, repository, security, server, service, session` (10 files, **no `lfs`**) | `render-fresh.yaml` stringData key list |
| Shape/S3 Secrets in the live API? | **Absent** | 13:23:47 op 00334 `Pruned` results (Secret/forgejo-lfs-shape, ExternalSecret/forgejo-s3-secret); live ESO list has no `forgejo-s3-secret`; 13:29:33 init log "Reloading preset envs" shows no `FORGEJO__LFS__*` |
| `ignoreDifferences` masking drift on the Secret? | **No** | app spec: no `spec.ignoreDifferences`; live `argocd-cm`: no `v1_Secret` customization (only workload reloader annotations + Plan `/status`); `RespectIgnoreDifferences=true` therefore changes nothing for Secrets |
| `argocd.argoproj.io/hydrate: hard` on the app? | **Inert** | docs: the annotation acts only when `spec.sourceHydrator` is set; live spec has no `sourceHydrator` (spec keys: `destination, project, sources, syncPolicy`) |
| Stale repo-server render? | **No** | checksum equality above (a stale render would change `checksum/config`); revisions pinned `1865031af` in `status.sync` and every op dump |
| If a live pod still processes an `lfs` fragment — ranked explanations + one distinguishing command each | 1. **API Secret still fragment-bearing (chain not yet re-applied)** — all era-2 boots incl. `qwnnc` @13:20:18; `kubectl -n default get secret dev-forgejo-inline-config -o jsonpath='{.data.lfs}'` (non-empty = this; today: empty)  2. **Pod booted from a node-stale secret volume while the API is clean** — `mwklh` @13:29:31; same kubectl read = empty while the pod's `kubectl logs … -c init-app-ini` shows `lfs` → node-side; re-create the pod and re-read the new init log  3. **Child valuesObject stale (annotation not flipped)** — the 11-07→11-09 cause; `kubectl get application dev-forgejo -o jsonpath='{.spec.sources[?(@.helm)]}' \| grep -c STORAGE_TYPE` (1 = stale, 0 = fresh; today: 0)  4. **ignoreDifferences masking the Secret** — ruled out; `kubectl get application dev-forgejo -o jsonpath='{.spec.ignoreDifferences}'` + `kubectl -n default get cm argocd-cm -o jsonpath='{.data}' \| grep -c 'ignoreDifferences\.v1_Secret'` (both empty)  5. **Within-sync apply/rollout race** — cannot happen for this chart (kind order Secret<Deployment, no waves; op 00310 log order); verify any suspected case with `kubectl -n default logs argocd-application-controller-0 \| grep 'syncId\|Applying resource'` for that sync  6. **Second writer of the Secret** — ruled out: no ESO targets it (ESO list), reloader does not write Secrets (its only dev reaction this month was the runner StatefulSet @11-06), no other app owns it (app list + tracking-id on the RS: `argocd.argoproj.io/tracking-id: dev-forgejo:apps/Deployment:default/dev-forgejo`) |

### 5. Fix design (NOT applied — no cluster mutations from pipeline agents)

**What must be true for a fresh boot to leave `app.ini`'s `[lfs]` untouched-and-absent:**
1. The child app's `valuesObject` carries no `forgejo.gitea.config.lfs` map (annotation
   layer — already true since 13:22:00) **and** the chart gate stays closed (follows
   from 1: `forgejo.lfs.s3.enabled` reads the merged values, `_helpers.tpl:8-9`), so the
   desired `dev-forgejo-inline-config` has no `lfs` key, and no
   `forgejo-lfs-shape`/`forgejo-s3-secret` objects render.
2. The live API Secret equals the desired (i.e. a sync happened *after* the values flip,
   with the fragment-free content applied — done 13:23:18/13:23:46; app `Synced`).
3. The `lfs` fragment, the shape Secret, and the s3 ESO are all absent from the cluster
   (prune done 13:23:47 — the prune is load-bearing: without it the optional legs keep
   re-writing the 4 shape keys even with a fragment-free inline Secret).
4. **`app.ini` itself has no residual `[lfs]` section** — the one item that no chart
   state can fix, because `environment-to-ini` only adds/updates
   (`modules/setting/config_env.go` `EnvironmentToConfig`): the fragment-vs-env
   interaction is purely additive, so with all sources gone a pre-existing `[lfs]`
   (today: `STORAGE_TYPE=minio, MINIO_ENDPOINT=s3.spencerslab.com,
   MINIO_USE_SSL=true`) persists boot over boot and keeps the main container fatal in
   minio storage init (`routers/init.go:63 mustInit` → `minio.go:102 NewMinioStorage` →
   `Bucket name cannot be empty`, observed 13:35:16/13:45:29, 8 restarts at time of
   writing). **Yes, the one-time strip is still needed** — confirmed by source and by
   the live pod's continued crash loop with a fragment-free API chain in place.

**Exact command sequence (user-owned; agents may not run these):**

```bash
# 0) pre-check: the API chain must already be fresh (all of these must hold NOW,
#    and they do per §4 — re-run after any change):
kubectl -n default get application dev-forgejo -o jsonpath='{.status.sync.status}'            # Synced
kubectl -n default get application dev-forgejo -o jsonpath='{.spec.sources[?(@.helm)]}' | grep -c STORAGE_TYPE   # 0
kubectl -n default get secret dev-forgejo-inline-config -o jsonpath='{.data.lfs}'            # (empty)
kubectl -n default get secret forgejo-lfs-shape; kubectl -n default get externalsecret forgejo-s3-secret  # both NotFound
kubectl -n default get deployment dev-forgejo -o jsonpath='{.spec.template.metadata.annotations.checksum/config}'  # 3b77bfac…

# 1) one-time [lfs] strip from the PVC (RWO local-path = hostPath: a scratch pod on the
#    same node can mount it even while the crash-looping pod holds it):
kubectl -n default run lfs-strip -it --image=alpine --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"lfs-strip","image":"alpine","command":["sh","-c","sleep 600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"forgejo"}}]}}'
kubectl -n default exec lfs-strip -- sh -c "awk '/^\[lfs\]/{f=1;next} /^\[/{f=0} !f' /data/gitea/conf/app.ini > /tmp/app.ini.new && cat /tmp/app.ini.new > /data/gitea/conf/app.ini && chown 1000:1000 /data/gitea/conf/app.ini"
kubectl -n default exec lfs-strip -- grep -c '^\[lfs\]' /data/gitea/conf/app.ini            # 0
kubectl -n default delete pod lfs-strip                                              # remove the scratch pod

# 2) recreate the pod so a fresh boot happens against the fresh chain:
kubectl -n default delete pod -l app.kubernetes.io/instance=dev-forgejo

# 3) verify the boot (the two oracles — cf-122 plan A7):
kubectl -n default logs -l app.kubernetes.io/instance=dev-forgejo -c init-app-ini --tail=200 \
  | grep -A3 'Processing inlines'    # NO 'lfs' section anywhere in the fragment list
kubectl -n default logs -l app.kubernetes.io/instance=dev-forgejo -c forgejo \
  | grep 'LFS storage'               # "Initialising LFS storage with type: local" + "Creating new Local Storage at /data/lfs"
kubectl -n default get application dev-forgejo   # Synced / Healthy
```

If step 3's init log shows the `lfs` fragment again **while step 0's kubectl read of the
Secret is empty**, that is the node-stale-volume anomaly (OQ-1): re-run step 2 once
more; if it persists, restart the node's kubelet (`sudo systemctl restart k3s-agent`)
and/or file it against k3s v1.36.5.

**Recurrence prevention (decisions, not this ticket):**
- The child apps' values are annotation-frozen while the umbrella tracks
  `refs/heads/main` by URL — move dev-forgejo's values to the same git-following
  mechanism (per-app `customValuesUrl` annotation pointing at
  `raw.githubusercontent.com/…/main/custom-values/dev/prod-values.yaml`, with the
  inline `customValues` annotation removed so it can't shadow the URL layer — merge
  order in `appset-charts.yaml:114-120` is app > service > base, and `valueFiles`
  rank below `valuesObject`).
- Decide whether dev's child apps should carry `automated {prune, selfHeal}` (the
  appset renders it when `services.dev[.forgejo].selfHeal != "false"` — currently off
  lab-wide; D9 assumed it on).
- Add a post-sync boot-log check (step 3) to any runbook that flips LFS storage mode.

### 6. Contradictions and how they were weighed

- **`Synced` at 13:30:19 vs the 13:29:33 init log showing the fragment.** Weighed by
  separating the API object from the node volume: ArgoCD compares API objects (its
  informer reads the API), the kubelet populates volumes (its own cache). All API-side
  facts (op results, prunes, comparison outcomes, absence of any logged write in
  13:24–13:31) put the Secret at fragment-free from 13:23:47; the only fact that can't
  be reconciled is the volume content at 13:29:31 → attributed to node-local
  eventual consistency (documented behavior; exact k3s code path unverified, OQ-1).
- **Two consecutive "configured" results for the same Secret (op 00310 @13:23:19 and
  op 00334 @13:23:47)** despite identical desired content: treated as client-side-apply
  re-write churn between the two manual syncs (no semantic contradiction: the content
  is pinned by the checksum-equal render in both cases); not load-bearing for any
  conclusion.
- **Chart.lock digest drift** (`digest: sha256:08c947b4…` generated 2026-10-25 vs the
  registry tgz fetched today `sha256:5816ead4…`): the `forgejo-helm:17.3.1` OCI tag
  was re-published at some point; the cf-122 planning round (2026-11-07) already read
  the current generation (its cited line numbers match today's tgz exactly) and
  ArgoCD's live render matches today's tgz (checksum equality), so the re-publication
  predates this incident and has no operational effect here. Recorded as adjacent
  finding: `helm dependency build` on a fresh clone does not hard-verify the lock
  digest — re-pinning `Chart.lock` is a hygiene follow-up, not an incident cause.

### 7. Open questions

1. **OQ-1 (node-side):** the precise k3s v1.36.5 kubelet secret-cache path that served
   `dev-forgejo-c4ccf6fcb-mwklh` the pre-13:23 fragment at 13:29:31 while the API
   object was clean — verify with §5 step 0+3; if reproducible, escalate to k3s.
2. **OQ-2 (lab wiring):** who sets/owns the `services.dev.*.customValues` cluster
   annotations, and should dev-forgejo's values move to the URL/git-following layer
   (§5 prevention, item 1)?
3. **OQ-3 (lab wiring):** should dev's child apps enable `automated {prune, selfHeal}`
   (item 2)? The incident's two-day stale window was a direct consequence of it being
   off.
4. **OQ-4 (hygiene):** re-pin `charts/forgejo/Chart.lock` to the current
   `forgejo-helm:17.3.1` tgz digest (item in §6) — owner: renovate follow-up already
   recorded in the cf-122 plan.
5. **OQ-5 (adjacent):** `dev-forgejo-runner-dev` StatefulSet has been
   CrashLoopBackOff since ~11-07 16:30 (46 h at time of writing); the runner dials
   `dev-forgejo-http:3000` (`services/dev/prod/values.yaml:164-166`), so it is likely
   collateral of this incident — confirm after forgejo is up; separate ticket if not.

### 8. Adjacent (out of scope, noted)

- The dev `bitwarden-login` store still cannot fetch item `forgejo-s3` (A11, plan
  Q1) — now irrelevant to dev's availability (the ESO + legs are gone from dev's
  render), but matters if dev ever re-opts into S3.
- Orphan LFS objects: none expected (plan D10) — dev never completed a healthy
  SFS-backed push window; the `git-lfs` bucket is untouched by this incident.

### Evidence index (where each artifact lives)

- Repo sources: `charts/forgejo/templates/{_helpers.tpl,secret-forgejo-s3.yaml,
  secret-forgejo-lfs-shape.yaml}`, `charts/forgejo/values.yaml:123-187`,
  `charts/base/templates/appset-charts.yaml:36-44,89-143`,
  `services/dev/prod/templates/appset.yaml` (umbrella), `custom-values/dev/
  prod-values.yaml` (main: lfs-free; `483bf1607^`: the stale slice with
  `forgejo-s3: 06a65037-…` + `lfs:` block), `charts/base/values.yaml:116-145`
  (argocd-cm ignoreDifferences template).
- Subchart (pulled 2026-11-09, `/tmp/opencode/cf122-incident/subchart/charts/forgejo/`):
  `templates/gitea/deployment.yaml`, `templates/gitea/config.yaml`,
  `templates/gitea/init.yaml`, `templates/_helpers.tpl`, `scripts/
  config_environment.sh`, `values.yaml:665-666`.
- Forgejo app source: `codeberg.org/forgejo/forgejo` tag v15.0.10 —
  `modules/setting/config_env.go` (`EnvironmentToConfig`), `contrib/
  environment-to-ini/environment-to-ini.go` (`runEnvironmentToIni`); minio/local
  storage oracles per cf-122 plan Authority A6/A7.
- Renders (this round, `/tmp/opencode/cf122-incident/renders/` + the parallel
  session's `/tmp/opencode/cf122-forensics/render-{fresh,stale,mixed}.yaml` —
  provenance: unknown peer session, created 13:27–13:42; its outputs were
  independently re-derived and checksum-matched before use): gateclosed (release
  `dev`), gateopen (release `dev`, old valuesObject), and the release-correct
  `render-fresh` (== live Deployment checksum `3b77bfac…`).
- Live cluster reads (2026-11-09, `readonly-dev-kubernetes`): Application
  `dev-forgejo` (spec, syncPolicy, status, `status.history` #59–#68), ApplicationSet
  controller log (13:22:00 spec update), application-controller log (ops
  00257/00281/00310/00334, 13:21:29–13:23:47; zero dev-forgejo lines
  13:24:00–13:31:00), ExternalSecret list, Deployment + ReplicaSets (rev 7–10,
  checksums `3a00bb0a/0fcbd17e/e22fbd96/3b77bfac`), pod
  `dev-forgejo-c4ccf6fcb-mwklh` (spec volumes/env, init-app-ini log, main log),
  namespace events 12:47–13:40, node `dev` (k3s v1.36.5+k3s1), `argocd-cm`,
  reloader pod log, sibling app `dev-coder` (syncPolicy), umbrella app `dev`
  (sources/valueFiles incl. the raw-main custom-values URL).

RESULT
status: DONE
chunk: incident-mechanism
files_changed: [.agents/plans/2026/2026-11-cf-122-feat-lfs-s3-optional/RESEARCH.md]
commands_run: [git archive origin/main → /tmp render tree => pass, helm dependency build (subchart pull, /tmp copy) => pass, helm template dev-forgejo (live valuesObject + 5 ArgoCD params, /tmp copies) => pass, checksum comparison live-Deployment 3b77bfac… == gate-closed render 3b77bfac… => pass (release-name-corrected; first attempt with release `dev` produced the non-matching fca739f9… — artifact, documented), readonly-dev-kubernetes: Application spec/status/history + ApplicationSet & application-controller logs + ESO list + Deployment/RS/pod objects + events + argocd-cm + node + reloader log => pass, webfetch: forgejo v15.0.10 config_env.go + environment-to-ini, kubernetes kubelet secret_manager/watch_based_manager sources, ArgoCD sync-waves docs + gitops-engine sync_tasks.go + source-hydrator docs => pass, kubelet node logs => fail (MCP forbidden — flagged, OQ-1)]
deviations: none — no cluster mutation, no repo writes beyond the deliverable; /tmp renders on COPIES only (worktree untouched; charts/forgejo/charts/ never written in place); a parallel session's /tmp/opencode/cf122-forensics renders were used only after independently re-deriving them (checksum equality)
friction: (1) MCP service account cannot read Secrets in `default` — live `dev-forgejo-inline-config` content established indirectly via init-container logs + ArgoCD Synced state + op logs; (2) MCP nodes_log returned an HTML error page (no kubelet log access) — the 13:29 node-stale-volume path is therefore inferred, not code-traced (OQ-1); (3) first local render used release name `dev` instead of `dev-forgejo`, which shifted checksum/config (the subchart fullname is release-derived) — corrected before any conclusion was drawn; (4) forgejo-helm:17.3.1 OCI tag was re-published since Chart.lock was generated (tgz sha256 5816ead4… vs locked 08c947b4…) — verified the cf-122 planning round and ArgoCD both render with the current generation, so it is not an incident cause (OQ-4 hygiene)
open_questions: OQ-1 k3s kubelet secret-cache path for the 13:29:31 stale volume (verify per §5 step 0+3); OQ-2 ownership of the services.dev.*.customValues cluster annotations + move dev-forgejo values to the git-following URL layer; OQ-3 enable automated {prune, selfHeal} on dev child apps (D9 assumed it); OQ-4 re-pin Chart.lock to the current forgejo-helm 17.3.1 digest; OQ-5 dev-forgejo-runner-dev CrashLoopBackOff (46 h) — likely collateral, confirm after forgejo is up
next_suggested: hand §5 to the user as the one-time fix sequence (API chain is already fresh; only the residual [lfs] in app.ini + one clean pod boot remain), and fold OQ-2/OQ-3 into a follow-up ticket so the annotation-vs-git values path can't silently lag a merge again

## Incident research (2026-11-09): does ServerSideApply fix the stringData→data orphan class?

Scope launched by coord: verify/refute five claims about flipping the dev-forgejo app from
`ServerSideApply=false` to `true` as the durable fix for the orphaned `data.lfs` key in
`Secret/dev-forgejo-inline-config` (a key the subchart rendered via `stringData:` that
survived every client-side apply after it left the manifest, while the app kept reporting
`Synced`). All k8s claims are verified against the cluster's own API-server generation
(k3s v1.36.5 ⇒ kubernetes v1.36.5 source, sparse-cloned this round) and against the lab's
ArgoCD v3.5.6 (live controller pod label; go.mod pins k8s.io/kubectl v0.36.1,
k8s.io/cli-runtime v0.36.1, k8s.io/client-go v0.36.1) and its gitops-engine.

### TL;DR

- **Claim 1 (pure SSA): CONFIRMED — managedFields are computed BEFORE the stringData→data
  merge.** The merge lives in the v1→internal conversion (`conversion.go`, "StringData
  overwrites Data"), which runs in `structuredMergeManager.Apply` *after*
  `updater.Apply` computed the applier's managed fields on the **v1-scoped** tree, where
  `stringData` is a first-class field and `data.lfs` does not exist. The materialized
  `data.lfs` is owned by **no manager**, and SSA prunes only fields the applier's entry
  previously owned ⇒ a stringData-born key removed under pure SSA is **never pruned**
  (upstream: k8s#99003, still open; k8s Secrets docs: "stringData … does not work well with
  server-side apply").
- **But the flip DOES fix THIS orphan** — not by pure-SSA semantics, by ArgoCD's inherited
  kubectl **CSA→SSA managedFields migration**: ArgoCD v3.5.6 runs the kubectl apply library
  with `fieldManager = "argocd-controller"` in *both* apply modes; on the first SSA sync the
  kubectl-lib `migrateToSSAIfNecessary` step unions the CSA manager's fields (incl. `data.lfs`)
  into the `argocd-controller/Apply` entry, deletes the `argocd-controller/Update` entry, then
  **re-sends the SSA patch**, which now prunes `data.lfs` (sole owner is the re-applying
  manager; no other owner). Verdict for the launch question: **the orphan is pruned on the
  first post-flip sync** — pending the live `--show-managed-fields` check in OQ-1.
- **Claim 2 refinement**: the app reported `Synced` not because the stringData→data
  normalizer hides the key (it exists, `NormalizeSecret`, and runs on both sides), but because
  the CSA-era diff engine is **ThreeWayDiff on the last-applied annotation**: after the
  key-removal sync the annotation no longer carries `data.lfs`, so three-way merge treats
  `data.lfs` as a *current-only* field (someone else's change) → predicted-live == live →
  no diff, forever. Upstream: argo-cd#29109 (Aug 2026, closed WITHOUT a fix, `workaround`
  label) and argo-cd#9368 (open since 2021).
- **The flip is NOT a durable fix for the class**: every future stringData key removal under
  SSA re-creates an unowned `data` key that no diff mode will ever surface (SSA dry-run
  diff predicts keep ⇒ Synced). Durable fix = render `data:` (base64) in the chart
  (upstream forgejo-helm; the wrapper cannot patch the subchart — cf-122 plan A1).
- **Risks of the flip (mixed app)**: `--force-conflicts` overwrites third-party-owned fields
  on value clash (documented trade-off; CNPG precedent on this cluster is healthy for 21 d);
  no-op SSA bumps resourceVersion/managedFields timestamps (k8s#131175, open); the
  last-applied annotation is frozen post-flip (downgrade trap, k8s docs + proposal R-2);
  key-level `ignoreDifferences` on this Secret is actively dangerous with the app's
  `RespectIgnoreDifferences=true` (argo-cd#29644, open regression, wiped prod MinIO keys).

### 1. Pipeline order — verified in kubernetes v1.36.5 source

- The stringData→data merge is in the **external(v1)→internal conversion**, not in the
  registry strategy:
  `Convert_v1_Secret_To_core_Secret` — "StringData overwrites Data"
  (https://github.com/kubernetes/kubernetes/blob/v1.36.5/pkg/apis/core/v1/conversion.go,
  lines ~408–423: `for k, v := range in.StringData { out.Data[k] = []byte(v) }`).
  The internal type has **no** `StringData` field at all
  (https://github.com/kubernetes/kubernetes/blob/v1.36.5/pkg/apis/core/types.go#L6602 —
  `Secret` = Immutable/Data/Type only), so the merged `data` is the only persisted form.
- The old strategy-side merge is gone: `dropDisabledFields` in
  https://github.com/kubernetes/kubernetes/blob/v1.36.5/pkg/registry/core/secret/strategy.go
  is an **empty function** (line ~97); the secret REST wiring now lives in
  `pkg/registry/core/secret/storage/storage.go` (plain generic store).
- SSA merge order (the load-bearing fact): in
  `structuredMergeManager.Apply`
  (https://github.com/kubernetes/kubernetes/blob/v1.36.5/staging/src/k8s.io/apimachinery/pkg/util/managedfields/internal/structuredmerge.go#L121):
  1. live object (internal) → `toVersioned` (internal→v1; `stringData` empty, `data.*` as stored),
  2. patch object = the apply-patch body **as submitted** (v1, unstructured, `stringData.lfs` present),
  3. `f.updater.Apply(live, patch, apiVersion="v1", managed, manager, force)` — **managedFields computed here, v1-scoped** (the applier's new field set = `patch.ToFieldSet()` = `stringData.lfs`, NOT `data.lfs`; pruning runs against the applier's *previous* v1-scoped set — smd v6.3.3 `merge/update.go`: "prune will remove a field … iff: applyingManager applied it last time; applyingManager didn't apply it this time; no other applier claims to manage it", https://github.com/kubernetes-sigs/structured-merge-diff/blob/v6.3.3/merge/update.go#L209 + `addBackOwnedItems`),
  4. only then `toUnversioned` = v1→internal conversion = **the stringData→data merge** (line ~170–183 of the same file, after `updater.Apply`).
  ⇒ The applier's managedFields entry claims `stringData.lfs` (a field that exists in no
  persisted object); the persisted `data.lfs` has **no field owner**. Next SSA apply without
  the key: pruning `stringData.lfs` is a no-op against the live tree; `data.lfs` is
  unclaimed by anyone ⇒ survives. This is exactly kubernetes/kubernetes#99003 ("Server-side
  apply: migration from client-side apply leaves stuck fields in the object", OPEN,
  sig/api-machinery; maintainers confirmed "we don't entirely convert
  kubectl-client-side-apply into the kubectl server-side applier, which means that these
  fields don't get removed when server-side removed"; community explicitly kept it open on
  2026-10-27: https://github.com/kubernetes/kubernetes/issues/99003).
- Pruning scope per the API docs: "If you remove a field from a manifest and apply that
  manifest, Server-Side Apply checks if there are any other field managers that also own the
  field. If the field is not owned by any other field managers, it is either deleted … or
  reset to its default" (https://kubernetes.io/docs/reference/using-api/server-side-apply/#field-management).
- Official upstream note on the Secret flavor of this: k8s Secrets docs, twice
  (basic-auth & bootstrap-token sections): "**The `stringData` field for a Secret does not
  work well with server-side apply.**" (https://kubernetes.io/docs/concepts/configuration/secret/).
- Non-apply (PUT/PATCH) ownership: `managerOrUserAgent` — explicit `fieldManager` param
  wins, else the User-Agent prefix before the first `/`
  (https://github.com/kubernetes/kubernetes/blob/v1.36.5/staging/src/k8s.io/apiserver/pkg/endpoints/handlers/create.go#L259);
  empty manager for apply is recorded as `"unknown"`
  (https://github.com/kubernetes/kubernetes/blob/v1.36.5/staging/src/k8s.io/apimachinery/pkg/util/managedfields/internal/buildmanagerinfo.go).
  (Moot for ArgoCD v3.5.6 — see below, which always passes an explicit manager.)
- smd `Set.Difference` semantics (why the `metadata` strip in managedFields does NOT strip
  annotations/labels — needed for the migration to work at all): "parent - child = parent;
  child - parent = {empty set}" — stripping the parent path `metadata` removes the parent
  node and children listed in the strip set, but `metadata.annotations`/`metadata.labels`
  survive (the strip set lists only `metadata.name/.namespace/.managedFields/…`), consistent
  with the docs' apply example owning `f:metadata: f:labels` (https://github.com/kubernetes-sigs/structured-merge-diff/blob/v6.3.3/fieldpath/set.go#L96).

**Verdict claim 1: the user's mechanistic claim is CORRECT (order confirmed with source);
its conclusion ("SSA won't prune the orphan") is CORRECT for orphans born under pure SSA —
and it is the reason the flip is not a durable class-fix. It is INCORRECT as the outcome for
THIS incident, because the orphan is owned by a CSA-era manager entry, and ArgoCD v3.5.6's
first SSA sync runs a managedFields migration that transfers that ownership and then prunes
the key (next section).**

### 2. Why the app reported `Synced` (refined from the launch's parenthetical)

- The stringData→data diff normalizer exists and runs on config, live and orig:
  `NormalizeSecret` ("move stringData to data section … base64 encode") in gitops-engine
  `pkg/diff/diff.go` (v3.5.6: lines ~933–990; introduced long ago per
  https://github.com/argoproj/argo-cd/pull/814, closed "Add special case for secrets to
  base64 encode stringData before performing diff").
- But for a `ServerSideApply=false` app the diff engine is **ThreeWayDiff**
  (`diff.go`: `Diff()` → `GetLastAppliedConfigAnnotation(live)` → `ThreeWayDiff(orig,
  config, live)` → `strategicpatch.CreateThreeWayMergePatch(orig, config, live)`).
  After the key-removal sync, the last-applied annotation carries **no** `data.lfs` (it
  mirrors the lfs-free manifest), `config` has none, only `live` has it ⇒ three-way merge
  classifies `data.lfs` as *present only in current* ⇒ NOT in the predicted patch ⇒
  predicted-live == live ⇒ **in-sync, forever** — the diff prediction models the (broken)
  apply behavior exactly, so the orphan is stable and invisible. `selfHeal` never fires
  because there is nothing to heal. (Upstream confirmation with the same symptom and the
  same root-cause analysis: https://github.com/argoproj/argo-cd/issues/29109 — "Removing a
  key from a Secret using stringData never removes it from the live Secret, and the app
  still reports [Synced]", filed 2026-08, labels `bug, bug/severity:major, component:sync,
  workaround`; **closed 2026-08-09 with NO fixing PR referenced — no fix landed**; and the
  2021 predecessor https://github.com/argoproj/argo-cd/issues/9368, still open — "the only
  method I've found to be successful is to delete the secret entirely … and then syncing it
  back in".)
- Post-flip the diff engine switches to the SSA dry-run path (`Diff()` →
  `structuredMergeDiff`/`ServerSideDiff`, kubectl-apply dry-run under the same manager);
  it predicts the server's actual apply, so it is *equally* blind to unowned `data` keys —
  the flip does not retroactively make hidden orphans visible; it only fixes ownership of
  the existing one via the migration below.

### 3. What the first post-flip sync actually does (verified in ArgoCD v3.5.6 source)

Facts from the tree (all read this round; v3.6.1 spot-checked, identical wiring):

- The controller builds sync options with an explicit SSA manager — NOT kubectl's default:
  `controller/sync.go:326-331`:
  `sync.WithServerSideApply(HasOption(ServerSideApply=true))`,
  `sync.WithServerSideApplyManager(cdcommon.ArgoCDSSAManager)` (constant
  `ArgoCDSSAManager = "argocd-controller"`, `common/common.go:128`),
  `sync.WithClientSideApplyMigration(enabled=true, default "kubectl-client-side-apply" or
  app-annotation override)`.
- gitops-engine `sync_context.go:1439` passes `sc.serverSideApplyManager` to
  `ApplyResource` in **both** modes; `resource_ops.go` builds kubectl's `ApplyOptions`
  with `o.FieldManager = manager` (= "argocd-controller") and
  `o.ForceConflicts = serverSideApply` (⇒ `--server-side --force-conflicts` — matches the
  ArgoCD docs: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#server-side-apply).
- Consequence for the CSA era (what created this incident): every ArgoCD client-side apply
  recorded managedFields under **`argocd-controller` / operation `Update`** (explicit
  fieldManager beats the User-Agent fallback — the kubectl-lib helper only omits the
  param when it's empty, https://github.com/kubernetes/cli-runtime/blob/v0.36.1/pkg/resource/helper.go
  `if m.FieldManager != "" { options.FieldManager = m.FieldManager }`; here it is never
  empty). That entry owns the whole post-apply object, **including `data.lfs`** (the
  three-way merge body keeps it) and the last-applied annotation itself (metadata.annotations
  survives the smd strip — §1).
- First SSA sync of `dev-forgejo-inline-config` (kubectl v0.36.1 `applyOneObject` SSA
  branch, https://github.com/kubernetes/kubectl/blob/v0.36.1/pkg/cmd/apply/apply.go):
  1. **SSA apply #1** under `fieldManager=argocd-controller`: the `argocd-controller/Apply`
     entry is created with the v1-scoped manifest fields (`stringData.*` fragments — no
     `data.lfs`; `data.lfs` not prunable: not in this manager's previous set).
  2. `saveLastApplyAnnotationIfNecessary`: skipped (runs only when the manager is the
     literal `kubectl` — line ~823 `if o.FieldManager != fieldManagerServerSideApply { return nil }`);
     the last-applied annotation is frozen from now on (see §5 downgrade risk).
  3. **`migrateToSSAIfNecessary`** (line ~905): `csaupgrade.FindFieldsOwners(managedFields,
     Update, <last-applied-annotation path>)` → finds `argocd-controller/Update`;
     `csaupgrade.UpgradeManagedFieldsPatch(obj, {"argocd-controller"}, "argocd-controller")`
     (https://github.com/kubernetes/client-go/blob/v0.36.1/util/csaupgrade/upgrade.go) →
     JSON patch that **unions the CSA entry's fieldsV1 (incl. `data.lfs`) into the
     `argocd-controller/Apply` entry and deletes the `argocd-controller/Update` entry**;
     sent as a JSON patch carrying `fieldManager=argocd-controller`, so the server
     recomputes `argocd-controller/Update` from the *request's* (post-migration)
     managedFields → the Update entry is **not** re-asserted (smd `Update`:
     `set = old − removed ∪ modified ∪ added`, old set absent ⇒ empty ⇒ entry dropped;
     `decodeLiveOrNew` prefers the request object's managedFields —
     https://github.com/kubernetes/kubernetes/blob/v1.36.5/staging/src/k8s.io/apimachinery/pkg/util/managedfields/internal/fieldmanager.go#L77).
  4. **Re-apply of the original SSA patch** (the kubectl "migrated → re-send" step,
     comment: "Re-send original SSA patch (this will allow dropped fields to finally be
     removed)"): now `argocd-controller/Apply`'s previous set includes `data.lfs`, the new
     patch omits it, no other manager owns it ⇒ **`data.lfs` is pruned from the live
     Secret.**
  5. gitops-engine's *own* pre-apply migration (`sync_context.go`
  `performCSAUpgradeMigration`, default manager `kubectl-client-side-apply`) additionally
  covers legacy entries from the very old kubectl-exec era, if any survive.
- Live-cluster grounding (readonly-dev-kubernetes, 2026-11-09): apps live in namespace
  `default` on the dev cluster; `dev-forgejo` currently has `syncOptions:
  [CreateNamespace=true, ServerSideApply=false, RespectIgnoreDifferences=true]` and no
  `automated` block; `dev-cloudnative-pg` already runs `ServerSideApply=true` (its CNPG
  Cluster `pg-forgejo`, 21 d, healthy — the "per-resource SSA" precedent is a sibling app;
  both paths share the same `argocd-controller` manager + force-conflicts).
  **MCP limitation**: the service account cannot read Secrets and the MCP projection strips
  `metadata.managedFields` from all GETs — so the live manager names above are source-derived
  predictions; OQ-1 gives the one-command check.

**Conclusion (Q1, final): flipping to `ServerSideApply=true` DOES prune the existing
`data.lfs` orphan on the first post-flip sync (migration + re-apply, ArgoCD v3.5.6
behavior), and the app's orphan-class vulnerability is NOT durably fixed — a future
stringData key removal under SSA recreates an unowned, unprunable, diff-invisible `data`
key (k8s#99003; k8s docs note).**

### 4. Mitigations in the wild, ranked

1. **(a) One-off out-of-band key removal** — the documented workaround for exactly this:
   argo-cd#29109 ("Workaround that resolved it: `kubectl patch secret … --type=json
   -p '[{"op":"remove","path":"/data/<stale-key>"}]'`"; "Replace=true … would presumably
   also work") and argo-cd#9368 ("delete the secret entirely … and sync it back"). The JSON
   remove works today under CSA (the patch deletes the key; `argocd-controller/Update`
   loses it via smd `removed` computation; no other owner) and is harmless post-flip. It is
   also the fallback if the OQ-1 check shows the live CSA entry under an unexpected manager
   name. Heavier documented escape hatch: "Clearing managedFields" — overwrite
   `metadata.managedFields` with `[{}]` via patch/PUT when state is inconsistent
   (https://kubernetes.io/docs/reference/using-api/server-side-apply/#clearing-managedfields).
2. **(b) Chart renders `data:` (base64) instead of `stringData:`** — the durable class-fix,
   and the only option that gives BOTH apply modes correct ownership: under CSA the
   last-applied annotation then carries `data.lfs`, so key removal produces
   `data.lfs: null` in the three-way patch (the #89938-era inversion disappears — k8s#89938
   documents the stringData-flavored variant, closed, "Do not use kubectl apply to edit
   secrets"); under SSA the applier's Apply entry owns `data.lfs` directly (first-class v1
   field; no transient-field gap), so removal is pruned and — bonus — the SSA dry-run diff
   then *detects* any stray live-only `data` key (predicted-live ≠ live ⇒ OutOfSync ⇒
   selfHeal acts). Cost: base64 in git for the fragment values; upstream change needed
   (forgejo-helm `gitea.inline_configuration` helper; the SpencersLab wrapper cannot
   override the subchart's `stringData` rendering — cf-122 plan A1). **Upstream status: no
   issue found for this class** — `code.forgejo.org/forgejo-helm/forgejo-helm` (the OCI
   source, https://code.forgejo.org/forgejo-helm/forgejo-helm) has only 9 non-PR issues,
   none about stringData/stale keys; dev mirror `johanneskastl/forgejo-helm` (codeberg.org)
   has none. A fresh upstream issue/PR is the move; k8s's own docs note ("stringData does
   not work well with server-side apply") is the supporting citation.
3. **(c) `ignoreDifferences` on the Secret's `data`** — hides, doesn't prune, and is
   actively risky here: the app already sets `RespectIgnoreDifferences=true`, and
   argo-cd#29644 (OPEN, labels `bug, regression, component:sync, component:gitops-engine,
   component:ignore-differences`) shows that a **key-level** ignore on a stringData Secret
   makes the RespectIgnoreDifferences sync target **drop the whole `data` map** — reported
   to have wiped every MinIO access/secret key in a production cluster on the first post-upgrade
   sync (regression since v3.5.2, passes on v3.4.4; fix PRs #29646/#30675 still open).
   Whole-map ignores (`.data, .stringData`) are "unaffected" per that issue but then merely
   mask any future key-level drift. Verdict: do not add; if anything, file a guard against
   key-level ignores on this Secret.
4. **(d) Anything else** — nothing upstream for the chart (see 2b); the *app.ini* staleness
   layer is separate and already settled in the 2026-11-09 first section (add-only
   `environment-to-ini`; one-time PVC strip, user-executed). For completeness: the
   `argocd.argoproj.io/client-side-apply-migration-manager` app annotation exists to point
   the pre-apply migration at a non-default CSA manager (ArgoCD docs,
   https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#client-side-apply-migration)
   — only needed if OQ-1 finds a legacy/renamed CSA entry.

### 5. Q4 — risks of flipping the mixed app (Deployment, PVC, Gateway-API TCPRoute,
ExternalSecret CRDs, CNPG Cluster, plain Secrets)

- **Precedent on this cluster**: `dev-cloudnative-pg` already runs `ServerSideApply=true`
  against the CNPG operator (Cluster `pg-forgejo` healthy 21 d; operator co-owns `status`) —
  the `argocd-controller` + `--force-conflicts` combination demonstrably coexists with an
  active controller here. The flip extends that same mechanism to the app's other kinds.
- **force-conflicts semantics**: ArgoCD's SSA syncs set `Force=true`
  (`o.ForceConflicts = serverSideApply`, gitops-engine resource_ops.go) — on value-level
  conflict ArgoCD overwrites and steals ownership from the other manager (k8s docs
  "Conflicts": force "removes the field from all other managers' entries"). This is the
  proposal's chosen behavior (Q-1: "The first version should use the force flag and
  override even if there are conflicts",
  https://argo-cd.readthedocs.io/en/stable/proposals/server-side-apply/). Watch-out: any
  manual `kubectl edit`/third-party write on dev-forgejo objects (e.g. someone scaling the
  Deployment) gets force-overwritten on the next sync instead of surfacing a conflict.
- **Churn**: no-op SSA calls bump `resourceVersion` and `managedFields[].time`
  (kubernetes/kubernetes#131175, open, sig/api-machinery) — expect "configured" sync
  results and RV increments on every reconcile even with zero semantic change (the prior
  round already saw CSA double-"configured" churn; SSA adds this class too).
- **Downgrade trap**: post-flip the `last-applied-configuration` annotation is NOT kept
  current (kubectl only rewrites it for the `kubectl` field manager —
  `saveLastApplyAnnotationIfNecessary`; ArgoCD proposal risk R-2 "Alternating
  Server-Side/Client-Side syncs"; k8s docs "Downgrading from server-side apply to
  client-side apply": the annotation must be kept up to date, and any field not managed by
  CSA "raise[s] conflicts"). Reverting to `ServerSideApply=false` later would three-way-merge
  against the frozen pre-flip annotation — plan to stay SSA.
- **CRDs / static-schema edge**: ArgoCD's SSA diff + `ignoreDifferences.managedFieldsManagers`
  + SSA-without-server-side-diff rely on a hard-coded built-in schema; "field not declared
  in schema" is the documented failure (ArgoCD FAQ,
  https://argo-cd.readthedocs.io/en/latest/faq/ — "How do I fix `field not declared in
  schema`?"). v3.5.6 pins k8s v0.36.1 libs against a k3s v1.36.5 server — same generation,
  so built-in types are fine; CRDs use the live schema. Gateway API had SSA-merge-correctness
  fixes for list typing (kubernetes-sigs/gateway-api#3972 "Correct wrong list type on set
  fields", closed/merged) and the tracker shows **no open SSA blocker** for TCPRoute-class
  resources; SSA treats CRD lists atomic unless `x-kubernetes-list-type` is declared
  (k8s docs "Custom resources and Server-Side Apply" — gateway-api declares them).
  ExternalSecret CRDs: same shape (spec ArgoCD-owned, status ESO-owned) — low risk; the one
  Secret-specific SSA wart is the *typed* `kubernetes.io/dockerconfigjson` dry-run diff
  failure (argo-cd#29740, fix PR #29784 open) — dev-forgejo's Secrets are plain Opaque, so
  not hit.
- **"fieldsV1 cannot be managed"**: no such error string exists upstream (GitHub global
  issue search: 0 hits; k8s v1.36.5 tree: 0). The launch's recollection likely conflates:
  (i) SSA conflict errors ("conflicting server-side apply field … managed by …"), (ii) the
  stuck-fields behavior of k8s#99003, (iii) `fieldsV1`/`fieldsType` schema-validation
  chatter (e.g. RedHat bug 1842660 on old OCP). Nothing in the modern stack (k8s ≥1.25
  managed-fields-for-CRDs, k3s v1.36.5 here) reproduces a `fieldsV1 cannot be managed`
  failure for this object set.
- **#29644 landmine** (see 4c) applies the moment anyone adds a key-level
  `ignoreDifferences` to this app's Secrets while `RespectIgnoreDifferences=true` — v3.5.6
  is inside the regression window.

### 6. Q5 — verdict and minimal remaining actions

**If the user flips dev-forgejo to `ServerSideApply=true`:**

- Genuinely improves: (i) the 262144-byte last-applied-annotation limit goes away for this
  app (ArgoCD docs cite it as the primary motivation — the inline-config Secret's
  annotation is already large); (ii) field-ownership visibility
  (`argocd-controller/Apply` entries replace the opaque annotation bookkeeping); (iii)
  admission webhooks run on every sync even without a diff (proposal G-3); (iv) the existing
  `data.lfs` orphan is pruned on the first sync (§3 migration + re-apply); (v) partial-manifest
  / co-owned resource patching becomes available (`ServerSideApply` + partial yaml, docs).
- Orphan `data.lfs` on the next sync: **pruned** (first post-flip sync, via
  `migrateToSSAIfNecessary` union + SSA re-apply) — *assuming* the live CSA entry is
  `argocd-controller/Update` (predicted from source; verify, OQ-1). If the live entry turns
  out to be under some other name that neither the kubectl migration (any Update owner of
  the last-applied annotation — covered) nor gitops-engine's default pre-apply migration
  (`kubectl-client-side-apply`) matches, fall back to action 3 below.
- Does NOT fix: the class. Future `stringData` key removals under SSA recreate unowned
  `data` keys that survive every apply and every diff (pure-SSA gap, §1; k8s#99003; k8s
  docs note). The flip is a one-time cleanup, not a durable remedy.

**Minimal remaining action list (all user-owned; agents make no cluster writes):**

1. Verify the predicted ownership first (read-only):
   `kubectl -n default get secret dev-forgejo-inline-config --show-managed-fields`
   — expect `argocd-controller / Update` owning `f:data.f:lfs` (and the Deployment/PVC/
   TCPRoute/ESO objects to show the same manager for the CSA era).
2. Flip the app: `ServerSideApply=false` → `true` in dev-forgejo's syncOptions (the appset
   values layer that renders `dev-forgejo`'s `spec.syncPolicy.syncOptions`), then one manual
   sync (the app has no `automated` block — prior round).
3. Verify the prune: `kubectl -n default get secret dev-forgejo-inline-config -o
   jsonpath='{.data.lfs}'` ⇒ empty, and `--show-managed-fields` ⇒ `argocd-controller/Apply`
   entry with no `f:data.f:lfs`, no `argocd-controller/Update` entry. If `data.lfs`
   survived: one-off `kubectl -n default patch secret dev-forgejo-inline-config --type=json
   -p '[{"op":"remove","path":"/data/lfs"}]'` (the #29109/#9368 documented workaround) and
   re-sync.
4. Do NOT add key-level `ignoreDifferences` on this app's Secrets (app has
   `RespectIgnoreDifferences=true`; argo-cd#29644 is open in the v3.5.x window).
5. Durable class-fix: open an upstream issue/PR against forgejo-helm (OCI source
   `code.forgejo.org/forgejo-helm/forgejo-helm`, dev mirror `codeberg.org/johanneskastl/
   forgejo-helm`) to render the inline-config fragments as `data:` (per-key `b64enc`)
   instead of `stringData:`; cite k8s#99003 + the k8s Secrets docs note + argo-cd#29109.
   Track here as a follow-up (cf-122 plan "Follow-ups").

### Contradictions and how they were weighed

- **Launch claim "managedFields computed before the merge ⇒ SSA can't prune ⇒ the flip
  won't help" vs "ArgoCD flips are safe"**: both true in different domains. The pre-merge
  ordering is source-confirmed and makes *pure-SSA* stringData orphans unprunable
  (k8s#99003). The *incident's* orphan, however, sits in a CSA `Update` entry, and ArgoCD's
  first SSA sync runs kubectl's CSA→SSA managedFields migration (explicit
  `argocd-controller` manager in v3.5.6, verified in `controller/sync.go`) which transfers
  ownership before the re-apply — so the flip *does* clean this specific orphan. Weighed by
  tracing the exact code paths (not by picking a side): the launch's mechanism is right, its
  predicted outcome is wrong for this lab's ArgoCD version.
- **`Synced` attributed to "stringData→data diff normalization" vs ThreeWayDiff**: the
  normalizer exists (and matters for `argocd app diff` readability), but the stable-Synced
  state is produced by the three-way *prediction* matching the three-way *apply* — the
  annotation round-trip. argo-cd#29109's own root-cause writeup says the same thing.
- **Docs say the SSA manager is `argocd-controller`** (sync-options "Client-Side Apply
  Migration" + the proposal G-5) **while the proposal also notes G-5 as a goal, not a fact**
  — verified as implemented in v3.5.6 *and* v3.6.1 `controller/sync.go`
  (`WithServerSideApplyManager(cdcommon.ArgoCDSSAManager)`); an earlier grep that missed it
  was an artifact of an incomplete sparse checkout (controller/ not materialized), corrected
  before any conclusion was drawn.

### Open questions

1. **OQ-1 (live verification, user-owned)**: exact live `managedFields` entries on
   `dev-forgejo-inline-config` and the app's other CSA-era objects — predicted
   `argocd-controller/Update`; confirm via action 1. If entries are `kubectl-client-side-apply`
   (legacy kubectl-exec era) the gitops-engine pre-apply migration covers them by default;
   if any other name, set the
   `argocd.argoproj.io/client-side-apply-migration-manager` annotation or use action 3's
   one-off patch.
2. **OQ-2 (upstream)**: argo-cd#29109 closed without a fix (Aug 2026) — the diff-masking
   half (CSA ThreeWayDiff blind spot) remains open in effect (cf. still-open #9368); if the
   user wants ArgoCD-side durability, comment/keep #29109 + k8s#99003 referenced in a fresh
   report, since chart-level `data:` rendering (4b) is the only full fix found.
3. **OQ-3 (follow-up ticket)**: upstream forgejo-helm `data:`-rendering change (4b/5) —
   owner: cf-122 follow-ups list; until it lands, every future config-key removal from
   `gitea.config` needs the one-off `/data/<key>` patch (action 3) to stay clean.

