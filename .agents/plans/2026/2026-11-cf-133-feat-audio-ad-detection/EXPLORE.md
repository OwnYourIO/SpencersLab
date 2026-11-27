# EXPLORE — cf-133 Audio Ad Detection

Grounded 2026-11-23 (Exploration stage, read-only). Method: repo reads +
read-only MCP probes (`readonly-home-kubernetes`, `readonly-grow-kubernetes`,
`readonly-dev-kubernetes`, `readonly-global-homeassistant`). No cluster
mutations, no admin-* servers. Card-embedded research dump NOT re-validated
here (that is Pre Research's job); this file grounds repo/cluster facts only.

## 1. containers/ conventions (for the new worker container)

- Layout: `containers/<name>/` with a required `Dockerfile` (dir name = image
  name); build context is the container dir. Precedents:
  `containers/brother-ptouch-automation/Dockerfile` (ARG pin + git source),
  `containers/traefik-mqtt-allowlist/` (single `main.py` + `requirements.txt`),
  `containers/snapcast/Dockerfile` (multi-stage rust builder + debian runtime).
- Build is **CI-primary**: `.forgejo/workflows/containers-build.yaml`
  (detection in `scripts/forgejo-container-detect.sh`). Triggers: push to
  `main` touching `containers/**`, PRs targeting `main`, `workflow_dispatch`.
  Detection gate: dir name must match `^[a-z0-9]+(-[a-z0-9]+)*$` AND contain a
  `Dockerfile` (`scripts/forgejo-container-detect.sh:83-89`).
- Dual publish: main/dispatch on `prod`-role instance pushes
  `:yy.mm.N` + `:latest` + `:main` to **both** `ghcr.io/ownyourio/<name>` and
  `<instance-host>/curatedforest/<name>` (workflow lines 337-356); PR on
  `dev`-role pushes `pr-<branch>-<sha>` to the instance registry only
  (lines 399-405). Calendar N = union max of both registries' month tags,
  walked per side (`scripts/forgejo-container-detect.sh:92-115`).
- **Single-arch reality**: the build is plain `docker build` on an
  `ubuntu-24.04` runner — no buildx/`--platform` anywhere in the workflow
  (only `docker buildx version || true` diagnostics, line 172).
  `containers/snapcast/Dockerfile:11-17` hardcodes `amd64` artifacts. The
  home cluster node `home-lab` is `kubernetes.io/arch=amd64`, k3s v1.37.1
  (live probe). **No arm64 builds exist in this repo**; a .NET image from
  `mcr.microsoft.com/dotnet` will be amd64 here.
- **No .NET precedent**: repo-wide grep for `dotnet`/`mcr.microsoft.com` finds
  only the Playwright MCP image pins (`services/dev/prod/values.yaml:256`,
  `services/gpu/prod/values.yaml:573`) and one commented `DOTNET_` env in
  `services/media/prod/values.yaml:228`. The .NET 10 worker is the repo's
  first .NET container; `mcr.microsoft.com/dotnet/sdk` base image choice has
  no in-repo precedent to copy.
- Dockerfile conventions (skills/container-creation): layer ordering
  (ARG pins → apt → lang deps → app code → non-root user → ENTRYPOINT),
  non-root **uid 65532** with explicit groupadd/useradd (username-collision
  warning), apt cleanup in the same RUN, `ENTRYPOINT` not `CMD`, no
  `:latest` bases, no secrets in layers.
- Renovate ARG-pin pattern (`renovate.json:112-169`): a
  `# renovate: datasource=github-tags|github-releases|git-refs depName=X`
  comment line **directly above** an `ARG W=...` line (value = 7-40 hex digest
  or version). Live example:
  `containers/brother-ptouch-automation/Dockerfile:3-4`. For a .NET base, the
  `FROM mcr.microsoft.com/dotnet/sdk:10.x` line is tracked by Renovate's
  built-in dockerfile manager (docker datasource); use the ARG-pin comment for
  any git/commit-pinned source (SoundFingerprinting checkout).
- Calendar-tag rule for own images (`renovate.json:308-316`):
  `ghcr.io/ownyourio/*` uses regex versioning `^\d+\.\d+\.\d+$`; chart pins
  must be `:yy.mm.N`. Brand-new image (no calendar tag yet) may use
  `:main` + `pullPolicy: Always` with a pin-me comment — the documented
  exception shape is `charts/snapcast/values.yaml:17-22` (stale wording
  `:v<run>`; the current standard is `:yy.mm.N`).
- A test pins the workflow's behavior: `tests/services/forgejo-containers-build.sh`
  (do not change the workflow without updating it). Per-container validation
  scripts live in `tests/containers/*.sh` (e.g. `forgejo-runner.sh`,
  `vllm-radiance-mxfp4.sh`).
- Name check: no existing `fingerprint`/`ad-detection`/`audio` container or
  chart name (repo-wide grep) — a new `containers/audio-ad-detection/`
  (or similar, must match `^[a-z0-9]+(-[a-z0-9]+)*$`) is collision-free.

## 2. Chart pattern (where the new chart registers)

Two live integration mechanisms in `services/home/prod/` — both in use today:

- **(a) `charts:` key (the skill-standard "add a service")**: entries under
  `charts:` in `services/<category>/prod/values.yaml` (e.g.
  `services/home/prod/values.yaml:17-110` — `postiz`, `playsms`,
  `smtp-relay`, …). `charts/base/templates/appset-charts.yaml:16-39` renders
  one ArgoCD Application per entry; per-app config comes from the **top-level
  `<appName>:` block** in the same service values.yaml (the generator merges
  only that key — `appset-charts.yaml:36`, dev comment
  `services/dev/prod/values.yaml:174-177`). Charts come from the published
  `https://ownyourio.github.io/SpencersLab/` registry via the commented
  `#version: … # renovate: datasource=helm registryUrl=…` + `#repository:`
  pair (key-as-chart-name manager, `renovate.json:66-75`).
- **(b) Chart.yaml dependency of the service chart**: `services/home/prod/Chart.yaml`
  depends on `snapcast` (1.0.14), `hyperion`, `ledfx`, `logitech-media-server`,
  `mosquitto` (lmatfy 0.1.1), … (lines 5-73); config rides in top-level
  `<name>:` value blocks (e.g. `services/home/prod/values.yaml:407-443`
  `snapcast:`, `445-517` `music-assistant:`) and service-level templates in
  `services/home/prod/templates/` (e.g. `pvc-snapcast-tmp-default.yaml`, a bare
  1Gi RWO PVC for the subchart's `existingClaim`). This is how the home audio
  stack (snapcast, music-assistant, ledfx, lms) ships.

Trio rule (skills/helm-chart-creation): chart entry + proxy values entry +
custom-values entry **only when the service has Bitwarden secrets**. For a
headless worker (no UI) the proxy leg is N/A by design — the documented
posture is the dev-cluster `mosquitto`/`forgejo-runner-dev` comments
(`services/dev/prod/values.yaml:108-133`: "the service trio's proxy leg is N/A
by design, not an oversight").

Reference charts: simple single-container `charts/qdrant/` (app-template 5.0.1,
security context, probes); in-repo-image consumer `charts/snapcast/`
(`global.nameOverride`, rolling-tag exception comment); the repo's own
`charts/mosquitto/` (ClusterIP, no ingress, no secrets — the cleanest
headless-worker shape; its `createDefaultServiceAccount: false` trick and
subPath-mounted ConfigMap-with-reloader pattern are worth copying for the
fingerprinter's config).

app-template 5.0.1 is the repo standard for all charts
(`charts/snapcast/Chart.yaml:6-7`, `charts/mosquitto/Chart.yaml:6-7`,
`services/home/prod/Chart.yaml:32-34`).

## 3. Category: home

- `services/home/prod/` = `Chart.yaml` + `Chart.lock` + `values.yaml`
  (1149 lines) + `templates/` (`appset.yaml` = the `home-appset`
  ApplicationSet, `pvc-snapcast-tmp-default.yaml`).
- `subDomain: home-lab` (`services/home/prod/values.yaml:16`); release naming
  `<serviceName>-<appName>` (e.g. `home-snapcast`, `home-mosquitto`).
- `custom-values/home/prod-values.yaml` (138 lines): per-service
  `<service>: { bitwardenIds: { <key>: <uuid> } }` blocks (e.g. `postiz:`
  lines 65-75, `zigbee2mqtt:` lines 90-98). **No MQTT credential item exists
  for the home broker** — see §5: the in-cluster broker is anonymous, so no
  Bitwarden item is needed *for that broker*. A custom-values entry for the
  new service is only required if its chart carries
  `OVERRIDE_VIA_CUSTOM_VALUES` sentinels.

## 4. Snapcast presence

- Chart: `charts/snapcast/` (app-template 5.0.1, `global.nameOverride: snapcast`);
  container: `containers/snapcast/` (rust builder → debian:bookworm-slim,
  **installs only the snapserver deb — no snapclient binary in the image**,
  `containers/snapcast/Dockerfile:13`). Gotcha for the file-path variant: the
  `snapclient --player file:filename=stdout` pipe must come from a different
  image/layer (upstream `badaix/snapcast` snapclient or a second stage) —
  the current in-repo image cannot run the card's snapclient side.
- Deployed on home as Chart.yaml dependency (v1.0.14, live release
  `home-snapcast`); live-verified services (readonly-home-kubernetes probe):
  - `home-snapcast` — LoadBalancer, **1704** (stream), 1705 (control), 4953
    (tcp), external IP 10.0.3.78;
  - `home-snapcast-snapcast-http` — 1780 (web);
  - `home-snapcast-roc-streaming` — UDP 10001/10002 + 10003 (Roc sources).
  So the in-cluster connection for the fingerprinter is
  `home-snapcast:1704` (DNS name `home-snapcast`, not
  `home-snapcast-snapcast` — nameOverride collapses it).
- Live `snapserver.conf` (home values override,
  `services/home/prod/values.yaml:418-434`): streams = LMS
  (`home-logitech-media-server.default`), Roc `SpencersStream`, TCP
  `MusicAssistant` on 4953, fifo `default`; combined stream `Spencer`
  (`meta:///SpencersStream/LMS/MusicAssistant/default?mode=recent`),
  **buffer 700ms** (BT-speaker headroom, line 430). The fingerprinter's
  snapclient will consume one of these via 1704.
- `snapcast-tmp` PVC (1Gi, `services/home/prod/templates/pvc-snapcast-tmp-default.yaml`).
- `snapclient` usage precedent: `services/home/prod/values.yaml:490`
  (ledfx custom entrypoint runs `snapclient --host … --daemon 1`).

## 5. MQTT + HA wiring

Brokers that exist (repo + live-verified):
- **home cluster**: `home-mosquitto` (ClusterIP, 1883, pod Running). Live
  config `home-mosquitto-config`: `per_listener_settings false / listener 1883 /
  allow_anonymous true` (helm chart `mosquitto-0.1.1` = lmatfy, per
  `services/home/prod/Chart.yaml:6-8`). **Anonymous, in-cluster only** — no
  ingress, no LB. No Bitwarden item needed to talk to it.
- **dev cluster**: `dev-mosquitto` (ClusterIP 1883) + `dev-home-assistant`
  (8123) — the cf-93 dev sandbox pair
  (`services/dev/prod/values.yaml:120-133`), in-repo `charts/mosquitto`
  (anonymous configmap, `persistence false`, emptyDir data/log).
- **grow cluster**: **no mosquitto, no HA container** (live probe: only
  `pg-grow-assistant-*` CNPG services + MCP servers). The prod HA is EXTERNAL
  (owner-side), per `charts/home-assistant/values.yaml:9-15` ("grow's live HA
  is EXTERNAL — an always-on container would deploy a second Home Assistant
  into grow"); its DB is the in-cluster CNPG via
  `pg-grow-assistant-external:5432` (LoadBalancer, live probe).
- **`mqtt.<domain>:1883`** — the documented external broker host:
  `charts/traefik/templates/secret-traefik-mqtt.yaml:20`
  (`MQTT_URI: "mqtt.{{ .Values.domain }}:1883"`, creds from
  `bitwardenIds.traefik-mqtt` → `custom-values/proxy-local/prod-values.yaml:27`)
  and `charts/keycloakx/values.yaml:27` ("Broker: mqtt.spencerslab.com:1883").
  Served through proxy-local traefik with the
  `ghcr.io/ownyourio/traefik-mqtt-allowlist:0.0.12` sidecar
  (`charts/traefik/values.yaml:76-91`, `containers/traefik-mqtt-allowlist/main.py`
  — subscribes `keycloak/events/LOGIN`, maintains an IP allowlist file). Which
  physical broker `mqtt.<domain>` forwards to is not pinned in the repo
  (mesh ExternalName fan-out; `references/proxying.md` pattern).
- Precedents for a container that talks MQTT with creds:
  `charts/zigbee2mqtt/templates/secret-zigbee2mqtt.yaml` (ExternalSecret →
  `bitwarden-login` store, username/password properties from one Bitwarden
  item; the canonical ExternalSecret shape: `external-secrets.io/v1`,
  `target.name: "<release>-secret"`, `template.engineVersion: v2`).

**HA-side finding (live probe, readonly-global-homeassistant)**: the lab HA
(2026.10.4, `home.spencerslab.com` — matches the chart's pinned tag
`charts/home-assistant/values.yaml:36`) has exactly one MQTT config entry:
`core-mosquitto`, **source `hassio`** (HAOS add-on broker), state `loaded`.
Broker host/port/credentials are NOT exposed by the read-only MCP — they live
in the owner-side HA config. Consequence: **the prod HA is currently NOT
subscribed to any in-repo cluster broker** (home-mosquitto, dev-mosquitto, or
`mqtt.<domain>`). An ad-detection worker publishing to `home-mosquitto` will
not reach HA unless (a) the worker targets the HAOS add-on broker instead
(needs that broker's endpoint + credentials — owner-side fact), (b) HA's mqtt
integration is re-pointed at a cluster broker (HA-side config change), or
(c) the worker runs where the add-on broker lives. The repo ships **no
HA-MQTT-discovery publisher precedent** (only MQTT *consumers*: zigbee2mqtt,
keycloakx, traefik-mqtt-allowlist), so the discovery-topic payload shape and
the topic-naming convention must come from the HA docs (Pre Research R4) +
an owner-side confirmation of the target broker.

## 6. Validation facts for this repo (for the plan's Commands)

- No unit-test suite; "tests" = validation commands
  (AGENTS.md "Pipeline specifics in this repo").
- `helm` lives at `~/.local/bin` — `export
  PATH=$HOME/.local/bin:$PATH` before any suite run (without it,
  pytest silently mass-skips helm-guarded tests).
- Chart validation: `helm lint charts/<name>` + `helm template charts/<name>`;
  render check must show **no `OVERRIDE_*` sentinels**; integration grep
  `grep -r "<name>" services/*/prod/values.yaml`; file-presence check
  (Chart.yaml, Chart.lock, values.yaml, templates/ + custom-values entry when
  secrets exist) — the four-level checklist in skills/helm-chart-creation §7.
- **No docker daemon in agent sessions**: a container chunk's build AC is
  CI-primary — the forge `.forgejo/workflows/containers-build.yaml` run on the
  pushed branch is authoritative; locally, build-critical facts come from the
  pinned base images' GHCR layer tar-listings / manifest digests. A
  `docker build => no-daemon, CI-deferred` line is the designed passing gate
  shape (ruled 2026-10-28, cf-77).
- Repo test layout: `tests/containers/<name>.sh` per container,
  `tests/services/<name>.sh` per service (pytest per-directory note applies to
  chart suites — basenames duplicate across directories, so run per-dir).
- `aislop` runs via `npx`; CI runs `aislop ci --changes` on PRs.
- Sentinel resolution: `OVERRIDE_VIA_APPSET` (appset params),
  `OVERRIDE_VIA_CUSTOM_VALUES` (`custom-values/<category>/prod-values.yaml`),
  `OVERRIDE_NEEDED` (fill before merge); a fourth,
  `OVERRIDE_VIA_CLUSTER_ANNOTATION`, exists (e.g.
  `services/grow/prod/values.yaml:2`, `services/gpu/prod/values.yaml:12-20`).

## 7. Gotchas / risks for research + planning

1. **Broker mismatch is the top risk** (§5): prod HA (external, HAOS) points at
   its own add-on mosquitto; no in-repo broker is confirmed to be HA's broker.
   Plan must pick the target broker + who owns the HA-side config change.
2. **New-image pinning posture**: first build has no calendar tag → chart must
   start at `tag: main` + `pullPolicy: Always` with a pin-me comment
   (snapcast shape); bump to `:yy.mm.N` after the first prod build
   (Renovate then manages it via the calendar-line rule).
3. **Never hand-bump Chart versions** (release.yaml bumps on main merge); a
   brand-new chart starts `version: 1.0.0` only.
4. **Secrets**: ExternalSecret + Bitwarden only; `bitwardenIds` map with
   `OVERRIDE_VIA_CUSTOM_VALUES` sentinels in the chart, real UUIDs only in
   `custom-values/home/prod-values.yaml`; skip both when the service has no
   secrets (mosquitto shape). If MQTT creds ARE needed (authed broker), the
   zigbee2mqtt ExternalSecret shape is the precedent.
5. **app-template subcharts cannot see top-level values** (domain/clusterName
   are injected top-level by the appset): domain-dependent env must live in
   parent-context templates (ExternalSecret/ConfigMap), not in the
   `app-template:` subtree (searxng `SEARXNG_BASE_URL: https://` live bug is
   the cited example).
6. **Standard security context on every container**
   (`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`);
   `createDefaultServiceAccount: false` when the app never calls the K8s API
   (mosquitto comment, `charts/mosquitto/values.yaml:8-11`).
7. **Single-arch amd64** (build pipeline + home node) — no multi-arch build
   machinery exists; don't design arm64 into the Dockerfile.
8. **The in-repo snapcast image has no snapclient** (§4) — the card's
   `snapclient --player file:filename=stdout` leg needs its own source (new
   layer/stage, or a second container/sidecar in the chart).
9. **Renovate managers**: ARG pins need the comment-line-above-ARG shape
   (`renovate.json:112-169`); `FROM` images are covered by the built-in
   dockerfile manager; the `.NET 10` base + `SoundFingerprinting` git pin
   (NuGet package vs git — if NuGet, the `dotnet restore` version pin is
   Renovate-traceable only via the dockerfile/custom manager; if git, use the
   git-refs ARG-pin shape).
10. **The home service chart carries its own Chart.lock** — adding a
    Chart.yaml-dependency variant (b) requires `helm dependency update
    services/home/prod` (lock regen); the `charts:`-key variant (a) needs
    nothing there.
11. **Workflow change ⇒ test update**: `tests/services/forgejo-containers-build.sh`
    pins the container-build workflow; the new container itself needs no
    workflow change (detection is dir-name-based).
12. **Release naming law**: `service name == chart name` for proper routing;
    releases are `<serviceName>-<appName>` (e.g. `home-audio-ad-detection`).
13. **PVC for the SoundFingerprinting DB**: the fingerprint DB is a growing
    file DB — a persistent volume (shared-storage/existingClaim pattern, cf.
    `snapcast-tmp` or `lms-playlists`) is likely needed; emptyDir would reset
    the ad DB on every pod restart. Sizing per repo tiers (app data 5-10Gi).
14. **CPU budget**: resample 48k stereo → 5512 Hz mono + realtime fingerprint
    queries is CPU-bound; home is a single node (`home-lab`, 1 node live
    probe) — the worker's CPU request/limit must be sized against the node,
    not a fleet.

## Open questions (for research/planning, not user-asking)

1. **Which broker does the prod HA's `core-mosquitto` (hassio) integration
   actually reach**, and does it take username/password? (Owner-side HAOS
   config; not in repo, not in read-only MCP.) Decides the worker's
   publish target and whether a Bitwarden item is needed.
2. Which snapcast stream should the fingerprinter tap (the combined `Spencer`
   meta-stream via 1704, or a single source)? Affects false-positive surface
   (Roc/LMS vs music-only).
3. Where does the SoundFingerprinting ad DB live (PVC size, init/seed
   workflow — is the DB pre-seeded with known ads, or does it learn)?
4. Container name + chart name (collision check passed for
   `audio-ad-detection`; confirm preferred name).
5. .NET SDK major (10 per card) — confirm the base image
   (`mcr.microsoft.com/dotnet/sdk:10.x` vs `aspnet` runtime split) and the
   resampling library (NAudio? ffmpeg-in-pipe? the 48k s16le → 5512 float
   step) — R3 territory.
6. Integration variant (a `charts:` key vs (b) Chart.yaml dependency of the
   home service chart) — precedent split in §2; both are live patterns.

## Chart idiom re-exploration (2026-11-26, owner review finding)

Grounded 2026-11-26 (read-only round, owner-flagged defect on the C04
hybrid chart). Method: repo reads + scratch renders in /tmp (helm
v3.16.4; scratch copies of `charts/audio-ad-detection` mutated OUTSIDE the
repo — the repo tree is untouched; every scratch used release name
`home-audio-ad-detection`, the ArgoCD release name).

### 1. Taxonomy sweep (75 charts, `charts/*/`)

**(a) templates/ contents**

- **1/75 charts has a `templates/common.yaml` — `charts/audio-ad-detection`
  (ours, the one-line `{{- include "bjw-s.common.loader.all" . }}`).**
  Repo-wide grep for `common.loader` finds only our chart
  (`templates/common.yaml:1` + the `values.yaml:9` comment). No sibling has
  any parent-side loader; the owner's "no other chart does this" is
  confirmed 74/74.
- 13 charts have an EMPTY `templates/` (pure-subchart, values-only):
  amd-gpu, docling, generic-device-plugin, jellyfin, k8s-monitoring,
  logitech-media-server, mariadb-operator, metube, music-assistant,
  privatebin, prowlar, qbittorrent, samba (10 app-template + 3 upstream
  consumers).
- The other 61 charts carry ONLY auxiliary parent-side manifests:
  `pvc-*` (39 files, e.g. `charts/qdrant/templates/pvc-qdrant-default.yaml`),
  `secret-*`, `cm-*`, `pg-*`, `mariadb-*`, ingress/service extras, and
  `NOTES.txt` (4 siblings: forgejo-runner, llama-swap, radiance, vllm —
  ours is the fifth). No `common.yaml`, no loader, no parent-side workload
  rendering.

**(b) values.yaml ROOT keys** (sweep = YAML parse of all 75)

- 56/75 charts carry the `app-template:` root key: **55 pure-nested
  siblings** (all workload config inside `app-template:`) and **1 hybrid
  (ours)** — top-level library keys `controllers/defaultPodOptions/monitoring/
  persistence/rbac/service` + non-empty `common: {defaultPodOptionsStrategy:
  overwrite}` stub + top-level `global:` + the `app-template:` stub
  (`values.yaml:220-222`). **No other chart has a top-level app-template
  library key.**
- The other 19 are upstream-chart consumers with config nested under the
  upstream chart-name key (or a named block): audiomuse-ai (`audiomuse-ai:`),
  coder (`coder:`), erp-next (`erpnext:`), explo, forgejo, hivetools
  (multi-block), immich, k8s-monitoring, keycloakx, loki, mariadb-operator,
  privatebin, smtp-relay (`mail:`), traefik, traefik-zerotrust, base,
  external-secrets-bitwarden, seaweedfs, seaweedfs-csi-driver.
- Within app-template charts, extra top-level keys are consumed by PARENT-side
  auxiliary templates (parent context), never by app-template: e.g.
  `charts/vllm/values.yaml:8` `cachePvcSize` (read by
  `templates/pvc-vllm-cache.yaml`; the comment states "the claim template is
  a parent-context manifest, so it reads this key at the chart top level
  rather than from the app-template subtree") and
  `charts/llama-swap/values.yaml:10` `modelsPvcSize` (rendered in
  `templates/pvc-llama-swap-default.yaml:10` as
  `storage: {{ .Values.modelsPvcSize | default "300Gi" }}`). That is the
  sanctioned home for parent-context values.

**(c) Chart.yaml dependency stanzas**

- All 56 app-template charts (including ours) pin **`app-template` 5.0.1**
  from `https://bjw-s-labs.github.io/helm-charts/` (sweep of every
  `Chart.yaml`). **Zero 4.x pins; no `catalogVersion` anywhere in the repo.**
  Sibling answer to "4.x vs 5.0.1": uniformly 5.0.1
  (`charts/mosquitto/Chart.yaml:6-9`, `charts/vllm/Chart.yaml:11-14`,
  `charts/radiance/Chart.yaml` same shape). Our stanza is byte-identical to
  the siblings' (`charts/audio-ad-detection/Chart.yaml:9-12`).
- 75/75 charts commit `Chart.lock`; ours is digest `sha256:0ea7893a5c4e…` —
  byte-identical to `charts/mosquitto/Chart.lock` (same dep spec; the
  digest is a spec-derived MAC). The only vendored `charts/*.tgz` in the
  tree is ours (`charts/audio-ad-detection/charts/app-template-5.0.1.tgz`,
  gitignored via `.gitignore:3 charts/**/charts` — must not enter a commit;
  C04 NIT-1 stands).

**(d) The MAJORITY idiom (55/55 app-template siblings) + outliers**

The idiom, precisely:

```
charts/<name>/
├── Chart.yaml      # apiVersion v2, app-template 5.0.1 dep, committed lock
├── Chart.lock
├── values.yaml     # domain: OVERRIDE_VIA_APPSET (+ bitwardenIds: when secrets)
│                   #   + ALL workload config nested under `app-template:`
└── templates/      # auxiliary parent-side manifests ONLY (pvc-*/secret-*/
                    # cm-*/pg-*/NOTES.txt) — NO common.yaml, NO loader
```

The workload is rendered by the `app-template` subchart itself (the single
dep bundles the common chart internally); there is no parent-side loader and
no second dep. The documented form — `charts/vllm/Chart.yaml:5-8` comment:
*"The repo app-template idiom: the single dep bundles the common chart
internally (which generates no k8s objects of its own), so the workload
renders from this chart's app-template: values with no parent-side loader
and no second dep."*

Outliers: the 19 upstream-chart consumers (each wraps its own upstream
chart as the workload renderer — wrapper pattern, `skills/helm-chart-creation`
§2) and the 1 hybrid (ours, C04 "test-forced").

**PVC idiom within app-template charts:** 44 charts use
`persistence.<name>.existingClaim` + a hand-written
`templates/pvc-*-default.yaml` (static name, `namespace: default`, RWO,
`resources.requests.storage: <size>Gi` — `charts/qdrant/templates/
pvc-qdrant-default.yaml:1-11`, `charts/llama-swap/templates/
pvc-llama-swap-default.yaml:1-11`, `services/home/prod/templates/
pvc-snapcast-tmp-default.yaml:1-11`). **Zero siblings use the library
PVC render (`type: persistentVolumeClaim` + `size:` in values) — ours is
the only chart in the repo with that shape** (grep: `type:
persistentVolumeClaim` in `charts/*/values.yaml` matches only
`charts/audio-ad-detection/values.yaml:197`). (forgejo-runner's `size:`
entries are statefulset `volumeClaimTemplates`, a different mechanism.)

### 2. The D-8 monitoring/scrape annotations — every chart that sets them

Repo-wide grep for `k8s.grafana.com`: exactly **3 charts** set the pair.

| Chart | values path (values key) | block | gate | port |
|---|---|---|---|---|
| `charts/vllm` | `app-template.defaultPodOptions.annotations` (`values.yaml:262-264`) | pod annotations (defaultPodOptions) | `app-template.monitoring.annotations` (`values.yaml:106-107`, nested) | 8000 |
| `charts/radiance` | `app-template.defaultPodOptions.annotations` (`values.yaml:273-275`) | pod annotations (defaultPodOptions) | `app-template.monitoring.annotations` (`values.yaml:251-252`, nested) | 8000 |
| `charts/audio-ad-detection` (ours) | top-level `defaultPodOptions.annotations` (`values.yaml:39-41`) **plus mirrored** top-level `controllers.main.annotations` (`values.yaml:51-53`) | pod + controller metadata | top-level `monitoring.annotations` (`values.yaml:13-14`) | 8080 |

The gate must live in the same values context as the map it gates (the map
is tpl'd as a whole in that context). `charts/radiance/values.yaml:243-250`
comment states it outright: *"The gate lives INSIDE this app-template
subtree because the map is tpl'd against the subchart values: at chart top
level the subchart cannot read it (vllm's working layout)."* vllm's
comment (`values.yaml:103-107`): 60 s scrape interval is the k8s-monitoring
v4 annotationAutodiscovery feature default — NO `metrics.scrapeInterval`
annotation (Q5 ruling; exactly two keys). Gate-OFF keeps the keys with inert
empty values (an empty value is what disables the scrape). Radiance's
comment additionally records the autodiscovery job-name source
(`values.yaml:266-272`): *"job = the app.kubernetes.io/name label fallback
… path /metrics"*.

**Canonical example 1 — `charts/mosquitto/values.yaml` in full** (the
cleanest headless-worker shape: ClusterIP, no ingress, no secrets,
`createDefaultServiceAccount: false`, parent template = one ConfigMap):

```yaml
# Passed to the ApplicationSet at deploy time (repo shape). No template in
# this chart consumes it, so it never reaches rendered output: this chart has
# no ingress and no secrets to build hostnames or credentials from.
domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: mosquitto
    # The broker never calls the K8s API; 5.0.1 would otherwise add an
    # unprivileged default ServiceAccount object to every render.
    createDefaultServiceAccount: false

  defaultPodOptions:
    # The image runs `User: None` and its entrypoint chowns /mosquitto only
    # under uid 0, so runAsNonRoot alone admits a treated-as-root pod.
    # 1883 is the image's own mosquitto uid/gid; fsGroup makes the data and
    # log emptyDirs group-writable by it.
    securityContext:
      runAsUser: 1883
      runAsGroup: 1883
      fsGroup: 1883
      runAsNonRoot: true

  controllers:
    mosquitto:
      annotations:
        # The conf rides a subPath mount, which kubelet never refreshes in
        # place: restart the pod when the ConfigMap changes.
        reloader.stakater.com/auto: "true"
      containers:
        main:
          image:
            repository: docker.io/library/eclipse-mosquitto
            # Newest tag of the bare release stream: 2.1.x ships only with
            # the -alpine suffix (latest = 2.1.2-alpine), so the bare pin
            # stays renovate-annotatable like this repo's other charts.
            tag: 2.0.22
          ports:
            - containerPort: &port 1883
              name: mqtt
            # websockets 9001: add a containerPort + service port here when
            # a real consumer needs it. Unused in dev.
          probes:
            # enabled defaults to false on this app-template build; type
            # must be the uppercase enum value (lowercase tcp fails
            # values.schema).
            liveness:
              enabled: true
              type: TCP
              port: *port
            readiness:
              enabled: true
              type: TCP
              port: *port
          resources:
            requests:
              cpu: 10m
              memory: 64Mi
            limits:
              memory: 256Mi
          # The broker writes into /mosquitto beyond its mounted volumes, so
          # the root filesystem stays writable here.
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL

  service:
    mosquitto:
      controller: mosquitto
      type: ClusterIP
      ports:
        mqtt:
          port: *port

  persistence:
    # mosquitto 2.x binds no remote listener without an explicit config: the
    # ConfigMap below is load-bearing, not decoration.
    config:
      type: configMap
      name: "{{ .Release.Name }}-config"
      globalMounts:
        - path: /mosquitto/config/mosquitto.conf
          subPath: mosquitto.conf
    # Dev-only broker with persistence off: data and log live and die with
    # the pod. Revisit with a PVC once a real consumer lands.
    data:
      type: emptyDir
      globalMounts:
        - path: /mosquitto/data
    log:
      type: emptyDir
      globalMounts:
        - path: /mosquitto/log
```

**Canonical example 2 — `charts/qdrant/values.yaml` in full** (custom HTTP
probes + PVC + `existingClaim` + hand-written PVC template + secret):

```yaml
bitwardenIds:
  qdrant: OVERRIDE_VIA_CUSTOM_VALUES

domain: OVERRIDE_VIA_APPSET

app-template:
  global:
    nameOverride: &chartName qdrant

  controllers:
    qdrant:
      annotations:
        reloader.stakater.com/auto: "true"
      containers:
        main:
          image:
            repository: qdrant/qdrant
            tag: v1.20.0
          env:
            QDRANT__SERVICE__HTTP_PORT: "6333"
            QDRANT__SERVICE__GRPC_PORT: "6334"
            QDRANT__LOG_LEVEL: "INFO"
            TZ: Etc/UTC
          envFrom:
            - secretRef:
                name: *chartName
          probes:
            liveness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /
                  port: 6333
            readiness:
              enabled: true
              custom: true
              spec:
                httpGet:
                  path: /readyz
                  port: 6333
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              memory: 2Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
  service:
    qdrant:
      controller: *chartName
      ports:
        http:
          port: 6333
        grpc:
          port: 6334
  persistence:
    storage:
      existingClaim: *chartName
      globalMounts:
        - path: /qdrant/storage
```

plus `charts/qdrant/templates/pvc-qdrant-default.yaml` (the hand-written
PVC idiom, in full):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: qdrant
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

**D-8 pair verbatim — `charts/vllm/values.yaml:257-264`** (the D-8 source
idiom):

```yaml
    # D8: exactly two k8s.grafana.com/* annotations (scrape + port). Values
    # are ternary-templated on the monitoring.annotations gate; the map is
    # tpl'd as a whole by app-template 5.0.1, so gate-OFF keeps the keys
    # with inert (empty) values instead of dropping them — an empty value
    # is what disables the scrape.
    annotations:
      k8s.grafana.com/scrape: '{{ .Values.monitoring.annotations | ternary "true" "" }}'
      k8s.grafana.com/metrics.portNumber: '{{ .Values.monitoring.annotations | ternary "8000" "" }}'
```

(`charts/radiance/values.yaml:273-275` is the same pair, port 8000, with
the gate at `values.yaml:251-252` inside the `app-template:` block. Note
vllm/radiance both carry the pair **pod-copy only** — no controller-
metadata mirror.)

### 3. `--set` reachability reality

The ternary resolves against the values context where the containing map
lives. Empirically verified in scratch (helm v3.16.4, release
`home-audio-ad-detection`):

- **Current hybrid:** `helm template --set monitoring.annotations=false`
  flips BOTH copies (controller → `""`, pod → `''`; the diff between the
  arms is exactly those four D-8 value lines, re-confirmed today).
  `--set app-template.monitoring.annotations=false` does NOT flip the gate
  (the render still carries 2 `k8s.grafana.com/scrape.*true` lines). The
  two shapes' `--set` paths are not interchangeable.
- **Idiom scratch** (config nested under `app-template:`,
  `templates/common.yaml` deleted): `--set
  app-template.monitoring.annotations=false` flips the pair to `""`/`''`
  (pod copy) — the qualified path is the correct `--set` under the majority
  idiom. `helm lint` = 1 chart linted, 0 failed (one INFO: icon — the
  sibling norm). 3 objects render.
- Removing the top-level `rbac: {}` while the parent loader is still
  present crashes the render (`nil pointer evaluating interface {}.roles`
  in the common chart's rbac renderer) — `rbac: {}` is load-bearing ONLY
  for the parent loader; it disappears with it. (Same class as the
  `common:` stub requirement, per the C04 round-1 review.)
- Repo tests that `--set` into app-template charts use the QUALIFIED
  prefix: `tests/services/dev-forgejo-runner.sh:828-830` —
  `--set 'app-template.controllers.runner.initContainers.dind=null'`,
  `--set 'app-template.controllers.runner.containers.runner.env.DOCKER_HOST=null'`,
  `--set 'app-template.persistence.socket=null'`. Top-level `--set` is used
  only for top-level keys (`--set domain=…`, `--set clusterName=…`,
  `--set bitwardenIds.…=…`; `--set runner.url=…` targets
  `charts/forgejo-runner`'s TOP-LEVEL `runner:` block — a parent-template
  key, not an app-template key). `tests/multi-repo/mosquitto-chart.sh:15`
  pins the no-OVERRIDE_ rule for `--set` renders. So the repo's own test
  convention is `app-template.<path>` for app-template config — t27's
  top-level `--set` is the outlier.

**ApplicationSet consumption (does the restructure receive values?):**
`charts/base/templates/appset-charts.yaml` — an entry with no active
`version:` (ours: commented `#version` + `# renovate: datasource=helm …` +
`#repository:` pair, `services/home/prod/values.yaml:111-118`) takes the
git-source branch: `path: <chart.repo.path>/<appName>` (=
`charts/audio-ad-detection` on `main`), `valueFiles: [values.yaml]` (the
chart's OWN values.yaml), helm `parameters` `domain`/`clusterName`/
`serviceName`/`appName`/`namespace` (top-level `--set`s — all legitimate
top-level keys; `domain` resolves the chart's `OVERRIDE_VIA_APPSET` in both
shapes), and `valuesObject` = shallow merge of cluster customValues + the
service's top-level `<appName>:` block. The mechanism is
**chart-shape-agnostic**: the nested idiom receives values identically to
the hybrid (the chart's own values.yaml carries the `app-template:` block;
the appset merges the service block on top). A per-app owner override would
be written `audio-ad-detection: { app-template: { … } }` in
`services/home/prod/values.yaml` — the shallow merge replaces the whole
`app-template` key (the same caveat as a top-level `controllers:` override
in the hybrid; nothing shape-specific is lost or gained). The extra keys
(the service block's `namespace`/`ServerSideApply` leak into `valuesObject`
in both shapes — the same leak exists on every sibling) are harmless.
Verdict: the restructure receives values correctly through the same
pipeline; no appset change is needed.

### 4. Ours vs idiom — the exact target-shape mapping

Current structures (`charts/audio-ad-detection/`): values.yaml root keys
`{domain, monitoring, common, global, defaultPodOptions, controllers,
service, persistence, rbac, app-template}`; `templates/common.yaml`
(one-line loader); `templates/NOTES.txt`; `Chart.yaml` (v2, 1.0.0,
app-template 5.0.1 dep — already sibling shape); `Chart.lock` (digest
0ea7893a…, already sibling shape); the `app-template:` stub
(`values.yaml:220-222`, inert per C04 MINOR-2); the `common:` stub
(`values.yaml:24-25`); the `rbac: {}` (`values.yaml:215`); the D-8 pair
duplicated (pod `values.yaml:39-41` + controller `values.yaml:51-53`);
`persistence.models` = library-rendered PVC with the self-describing
`aad.io/size: 10Gi` label (`values.yaml:196-203`).

Target shape (majority idiom), piece by piece:

| current piece | destination under the idiom |
|---|---|
| `templates/common.yaml` (loader) | **deleted** (file removed) |
| top-level `monitoring: {annotations: true}` | `app-template.monitoring: {annotations: true}` |
| top-level `defaultPodOptions.annotations` (D-8 pod copy) | `app-template.defaultPodOptions.annotations` (kept — the functional copy) |
| top-level `controllers.main` | `app-template.controllers.main` (strategy/replicas/pod/containers verbatim) |
| `controllers.main.annotations` (D-8 controller mirror) | **recommended: dropped** (vllm/radiance idiom is pod-only; the mirror is scraping-inert per the C04 round-1 finding — k8s-monitoring v4 annotationAutodiscovery is pod+service roles only) — or moved to `app-template.controllers.main.annotations` if render-parity with today is preferred |
| top-level `service:` | `app-template.service:` |
| `persistence.models` (`type: persistentVolumeClaim`, `size: 10Gi`, `labels: aad.io/size: 10Gi`) | `app-template.persistence.models: {existingClaim: audio-ad-detection, globalMounts: [{path: /models}]}` + NEW `templates/pvc-audio-ad-detection-default.yaml` (hand-written, the qdrant shape: static `name: audio-ad-detection`, `namespace: default`, RWO, `storage: 10Gi`); the `aad.io/size` label **disappears** |
| `persistence.tmp` / `persistence.home` (emptyDir) | `app-template.persistence.tmp` / `app-template.persistence.home` (unchanged content) |
| top-level `global.createDefaultServiceAccount: false` | `app-template.global.createDefaultServiceAccount: false` |
| — (absent) | **add `app-template.global.nameOverride: audio-ad-detection`** (the sibling norm — mosquitto/qdrant/vllm/radiance all set `nameOverride` to the chart name; it keeps `app.kubernetes.io/name: audio-ad-detection` and the autodiscovery job name identical to today's hybrid render) |
| `common: {defaultPodOptionsStrategy: overwrite}` | **deleted** (only load-bearing for the parent loader's values.init merge) |
| `rbac: {}` | **deleted** (only load-bearing for the parent loader's rbac renderer nil guard) |
| `app-template:` stub (`values.yaml:220-222`) | becomes the real config block (the stub is subsumed) |
| `domain: OVERRIDE_VIA_APPSET` (`values.yaml:4`) | stays top-level (sibling norm) |
| `Chart.yaml` / `Chart.lock` | **unchanged** (already sibling shape; dep stanza byte-identical to siblings) |
| `templates/NOTES.txt` | kept (5 charts carry NOTES.txt incl. ours); one reword: the "PVC: home-audio-ad-detection" line (NOTES.txt:9-10) → the PVC is now named `audio-ad-detection` (static hand-written-template name, the sibling norm — cf. `snapcast-tmp`, `llama-swap`, `qdrant`) |
| `charts/app-template-5.0.1.tgz` | stays gitignored, never committed (C04 NIT-1) |

**What disappears:** `templates/common.yaml`, the `common:` stub, the
`rbac: {}` stub, the `app-template:` stub-as-stub, the D-8 controller
mirror (recommended), the `aad.io/size` PVC label, the library PVC render
(`type`/`size`/`labels` block), the top-level `global:`.

**Render-equivalence checklist** (scratch-verified, release
`home-audio-ad-detection`, idiom shape WITH `nameOverride`):

| item | hybrid render | idiom render | verdict |
|---|---|---|---|
| object count/kinds | 3 (Deployment/PVC/Service) | 3 (same) | equal |
| object names | `home-audio-ad-detection` ×3 | `home-audio-ad-detection` ×3 | equal (PVC: `audio-ad-detection` in the idiom — see NOTES reword) |
| D-8 pod copy | `k8s.grafana.com/scrape: 'true'` + port `'8080'` | identical | equal |
| D-8 controller copy | `"true"`/`"8080"` double-quoted | absent (pod-only) or present (nested, same quotes) | diverges iff dropped (recommended) |
| gate-off diff | exactly 4 D-8 value lines | same 4 (or 2 if pod-only) | equal shape |
| `SNAP_STREAM_ID: "TBD-owner"` env | present | present (verbatim line) | equal |
| pod security | `runAsUser/runAsGroup/fsGroup: 65532`, `runAsNonRoot: true` | identical | equal |
| container security | `allowPrivilegeEscalation: false`, `drop: [ALL]`, `readOnlyRootFilesystem: true` | identical | equal |
| `strategy: Recreate`, `replicas: 1` | present | identical | equal |
| PVC | 10Gi RWO, mounted `/models` | 10Gi RWO, mounted `/models` (hand-written template) | equal (name differs: static `audio-ad-detection` — sibling norm) |
| emptyDir mounts | `/tmp` + `/home/aadworker` | identical | equal |
| Service | ClusterIP, `health` port 8080 | identical | equal |
| probes | startup 30×10 s /readyz, liveness 12×10 s /healthz, readiness 3×10 s /readyz | identical | equal |
| ServiceAccount | 0 (suppressed) | 0 (suppressed via `app-template.global`) | equal |
| `app.kubernetes.io/name` label | `audio-ad-detection` | `audio-ad-detection` **with** `nameOverride`; `home-audio-ad-detection` without | equal iff `nameOverride` added |
| `helm.sh/chart` label | `audio-ad-detection-1.0.0` | `app-template-5.0.1` | diverges — but `app-template-5.0.1` is the SIBLING shape (mosquitto render-verified) |
| `app.kubernetes.io/version` label | `0.1.0` present | absent | diverges — absent is the SIBLING shape (mosquitto render-verified) |
| boolean fields (`enableServiceLinks`, `hostIPC`, …) | render empty | render `false` | semantically equal; `false` is the SIBLING shape (mosquitto render-verified) |

So: same workload, sibling-shape metadata; the only functionally meaningful
delta is the PVC object name (`audio-ad-detection` vs
`home-audio-ad-detection`) and the optional D-8 controller copy.

### 5. Test-arm impact (`tests/containers/audio-ad-detection.sh`, t25–t31)

- **t25** (render grep: no `OVERRIDE_*` / no ExternalSecret / no credential
  material, lines 862-884): render-only, shape-agnostic → **unchanged**.
- **t26** (render grep: Recreate, `replicas: 1`, three probe kinds,
  `httpGet`, `/healthz`, `/readyz`, RMS-free probe blocks, lines 886-916):
  render-only, shape-agnostic → **unchanged** (all verified present in the
  idiom scratch render).
- **t27** (D-8 gate, lines 918-942) — encodes the hybrid in TWO places:
  1. line 928: `--set monitoring.annotations=false` → becomes
     `--set app-template.monitoring.annotations=false` (required in both
     variants of the rework).
  2. the value regexes (raw bytes verified): default-arm
     `grep -qE 'k8s\.grafana\.com/scrape[[:space:]]*:[[:space:]]*"?true"?'`
     / `…"?8080"?` (lines 932/934) — the ERE tail is `"?true"?`
     (optional DOUBLE quotes only): matches `true` or `"true"`, does NOT
     match the single-quoted `'true'`; gate-off arms
     `…""` (lines 936/938) match only the double-quoted empty `""`, not
     `''`. If the D-8 controller copy is dropped (recommended, pod-only),
     the default render carries only `'true'`/`'8080'` and the off render
     `''` → all four greps go red. Widened regexes verified to match both
     arms of the pod-only render: `['\"]?true['\"]?`,
     `['\"]?8080['\"]?`, and `['\"]{2}` (twice). If the controller copy is
     KEPT (nested), the greps still pass (the double-quoted copy satisfies
     them) and only the `--set` path changes.
- **t28** (no Ingress; ClusterIP; pod security; PVC, lines 944-991) — the
  `size: 10Gi` story: line 983 `grep -q 'size: 10Gi'` matches ONLY the
  `aad.io/size` label line in the current render (the PVC spec line is
  `storage: "10Gi"`, which does not contain the literal — C04 round-1
  finding). Under the idiom the hand-written PVC template renders
  `storage: 10Gi` (scratch-verified) → the grep becomes
  `grep -q 'storage: 10Gi'` (or the quote-tolerant
  `grep -qE 'storage:[[:space:]]*"?10Gi"?'`). The `aad.io/size` carrier
  **does not survive** (it is the test-driven label; the k8s spec field is
  the idiomatic carrier). Every other t28 grep verified to pass against the
  idiom PVC scratch render: `ReadWriteOnce`, `mountPath: /models`,
  `emptyDir`, `mountPath: /tmp`, `runAsUser: 65532`, `runAsNonRoot: true`,
  `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `ALL`,
  `Recreate` (t26), `kind: Service`, `ClusterIP`, `port: 8080`,
  `name: health`.
- **t29** (services wiring + Chart.yaml pins + placeholder, lines 993-1051):
  the `SNAP_STREAM_ID: "TBD-owner"` grep (line 1041, fixed-string,
  indentation-agnostic) survives the restructure — the env line is
  verbatim, only its indentation moves; the "required" comment must stay
  within 3 lines above it (lines 1043-1047). The Chart.yaml pins
  (`v2`/name/`1.0.0`/`app-template`/`5.0.1`/repo URL, lines 1026-1037) and
  the `charts:`-entry shape pins (lines 998-1011) are untouched by the
  rework → **t29 unchanged** (contingent on the rework preserving the
  literal + comment proximity).
- **t30** (whole-plan re-entry, lines 1053-1080): harness, shape-agnostic →
  **unchanged**. **t31** (ruled-defaults pins vs C05.md, lines 1082-1125):
  shape-agnostic → **unchanged**.

Summary: **t27 and t28 are the two arms that encode the hybrid shape**
(t27: the top-level `--set` path + the double-quote-only regexes; t28: the
`size: 10Gi` label carrier). t25/t26/t29/t30/t31 need no change. The
`aad.io/size` carrier and the D-8 double-copy (recommended drop) both go
away under the corrected idiom.

### 6. Skill state

**`skills/helm-chart-creation/` (repo, self-written) — ALIGNED with the repo
idiom; does NOT mislead toward common/loader.**
- `SKILL.md:133-145` (Scaffold): `templates/` = `secret-*/pg-*/secret-db-*/
  pvc-<service>-default.yaml` — no `common.yaml` anywhere in the scaffold.
- `SKILL.md:232-234` (Known gotchas): "All charts use the bjw-s
  **app-template** dependency (repo standard is currently `5.0.1` — check an
  existing chart …)".
- `references/chart-templates.md:156-162`: the Chart.yaml template is the
  `app-template 5.0.1` dep; `:164-219`: the full single-container
  values.yaml template is fully NESTED under `app-template:` (with
  `persistence.config.existingClaim: *chartName` at `:216-218`);
  `:265-279`: the PVC template body is the hand-written
  `templates/pvc-<service>-default.yaml` with
  `storage: <size>Gi` — exactly the idiom this rework targets.
- `SKILL.md:15-17` cross-references `helm-bjw-s-chart` as the "upstream
  app-template API reference … the values schema" — the load-together
  pairing is where the two shapes collide (below).
- Gap worth a skill-update leg: neither `SKILL.md` nor the references
  document the **D-8 scrape-annotation gate** (the `monitoring.annotations`
  ternary pair in `defaultPodOptions.annotations`, gate nested in the same
  subtree — vllm/radiance idiom) at all; the only reachability rule they
  carry is the subchart-can't-see-top-level-values gotcha
  (`SKILL.md:252-258`), which is exactly the rule the rework relies on.
  A short D-8 section (values path + gate placement + the qualified
  `--set app-template.monitoring.annotations` test shape) would close the
  gap that let the C04 hybrid get test-forced.

**`.agents/skills/helm-bjw-s-chart/` (third-party, `obeone/claude-skills`,
hash-pinned in `skills-lock.json` — do NOT hand-edit; a repo-side note in
`skills/helm-chart-creation` is the sanctioned override surface) — the
mislead source.** It documents the standalone-`common`-dependency +
parent-loader shape as THE canonical shape, with no mention of the
app-template-bundle shape anywhere (references grep: a single "app-template"
hit, `references/best-practices.md:532`, about resource identifiers):
- `SKILL.md:78-79` (Quick Start): "Generate the base from
  `assets/templates/`: `Chart.yaml`, `values.yaml`, `templates/common.yaml`,
  `templates/NOTES.txt`."
- `SKILL.md:85-99` (Core Structure): "templates/common.yaml / common.yaml —
  Includes the bjw-s library … `templates/common.yaml` is always exactly
  one line: `{{- include "bjw-s.common.loader.all" . }}`."
- `SKILL.md:101-114` (Chart.yaml): the dependency is `name: common`,
  `version: 5.1.0` — NOT the repo's `app-template` 5.0.1 bundle.
- `SKILL.md:116-158` (values.yaml Structure): top-level `defaultPodOptions:`,
  `controllers:`, `service:`, `ingress:`, `persistence:`, `configMaps:`,
  `secrets:` — the top-level shape our hybrid uses.
- `assets/templates/Chart.yaml`: `name: common`, `version: 5.1.0` dep;
  `assets/templates/templates/common.yaml`: the one-line loader;
  `assets/templates/values.yaml`: top-level keys incl.
  `persistence.config.type: persistentVolumeClaim` + `size: 1Gi` (the
  library-PVC shape no repo sibling uses).
- `SKILL.md:286-293` (Publishing): "Either commit `charts/` to git, or
  gitignore it and run `helm dependency build` in the pipeline" — the repo
  norm is the opposite (commit `Chart.lock` only, 75/75; gitignore
  `charts/`, `.gitignore:3`).

Correct read for the skill-update leg: both shapes are legitimate upstream
consumption of the same library (standalone `common` dep + parent-side
loader vs `app-template` bundle dep + subchart render); SpencersLab chose
the bundle shape for all 55 app-template charts, and
`skills/helm-chart-creation` already encodes it — the fix is an explicit
disambiguation note in the repo skill ("for charts under `charts/`, use the
app-template-bundle shape: nested `app-template:` values, NO
`templates/common.yaml`; `helm-bjw-s-chart` documents the standalone
common-dep shape — do not copy its Core Structure/asset templates into
`charts/`") plus the D-8 section. The C04 round-1 review's wording ("the
shape is the upstream bjw-s skill's documented canonical generated shape")
is what pulled the C04 dev toward the hybrid before the test-forcing
constraint landed.
