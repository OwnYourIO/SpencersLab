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
