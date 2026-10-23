> Provenance: byte-identical copy of run 1's RESEARCH.md (ticket 2026/2026-10-feat-forgejo-infra-and-dev-runner, branch feat-forgejo-infra-and-dev-runner-3), ported by the 2026-10-23 fusion (port 4).
> Path references inside are historical run-1-folder paths; this folder's RESEARCH.md remains the ticket's primary research.

# RESEARCH — Forgejo Actions runner chart (C03) — dev cluster, dev instance

Written by `agent-research` 2026-10-21 for `.agents/plans/2026/2026-10-feat-forgejo-infra-and-dev-runner/` (STORM method; every claim cites a source actually retrieved and read; live probes marked). Scope = the nine questions in `chunks/C03.md`. Target decision (D8: dev-only) treated as fixed.

## TL;DR

1. Image: `code.forgejo.org/forgejo/runner:13.2.0` (no `v` prefix on tags, amd64+arm64, non-root uid 1000, ships git+bash); latest release v13.2.0 (2026-09-18) [3][4][6].
2. The official runner Helm chart exists but is effectively unmaintained (0.7.3-era, appVersion 12.7.3, never tagged/released/OCI-published, hook-Job registration, whole-pod privileged, emptyDir cache) → **build the custom app-template chart**; the "only viable model" exception in C03 does not apply [15][16].
3. There is **no `kubernetes://` execution runtime**. Label types are `docker`/`lxc`/`host` only; the v13.1+ plugin engine (gRPC, alpha) is what community "k8s backend" charts ride on — not production-grade [2][9][17][18][21].
4. On k3s (containerd-only, confirmed live on dev [13]) the only execution model that actually works per upstream's own k8s example is a **privileged dind sidecar** with a hardened runner container; rootless dind is kernel-distro fragile [17][20].
5. Registration: use Forgejo 15's **uuid+token pair** (admin UI or `POST /api/v1/admin/actions/runners`, both on the live dev instance [14]) directly in declarative `server.connections` config — no register step, no hook job, no SA/RBAC; token lives in one Bitwarden LOGIN item (`bitwarden-login`: password=token, username=uuid) [1][7].

## Key findings

### Q1 — Official runner image, version, pinning, arch

- Latest release **v13.2.0** (published 2026-09-18; majors v10 2025-09, v11 2025-11, v12 ~2026, v13 2026-08-03) — verified via the code.forgejo.org releases API [3]. ⚠️ The C03 question's premise "runner 1.x→2.x→3.x majors" is stale; current major is 13.
- Canonical image: **`code.forgejo.org/forgejo/runner`** — registry tags confirmed live: exact `13.2.0` + minor `13.2` + major `13`; **no `latest` and no `main`/rolling tags at all** (188 tags, probe [4]). Manifest for `13.2.0` is an OCI index with `linux/amd64` + `linux/arm64` → dev (amd64 k3s) fine [4]. Anonymous pull works via the token realm `https://code.forgejo.org/v2/token?service=container_registry` (the bare `/v2/` ping returns 401 — normal challenge flow, ArgoCD/containerd pull this correctly) [4].
- Mirror path used in the official install docs: `data.forgejo.org/forgejo/runner:13` [5]; the official + community charts all use `code.forgejo.org` as registry [15][17][18]. Prefer `code.forgejo.org` (primary, what the wrapper chart's OCI dep already trusts; digest/renovate story below).
- Image internals (Dockerfile @ v13.2.0): alpine 3.24 base, **`git`, `bash`, `dumb-init` present**; `USER 1000:1000`, `WORKDIR /data`, `ENV HOME=/data`, `VOLUME /data`, entrypoint dumb-init + `/bin/forgejo-runner` [6]. Binary releases are GPG-signed (key `EB114F5E…`, docs show verification) [docs binary install].
- **Pin `:13.2.0`** (immutable exact tag; major tags like `:13` roll). Digest-pin is optional: tags are mutable in principle but the project treats per-release tags as immutable; renovate can also supply digests. Repo convention: `# renovate: datasource=docker depName=forgejo/runner registryUrl=https://code.forgejo.org` above the image line — the repo already runs a `image:<name>:<ver>` regex custom manager and per-line `# renovate:` annotations (`charts/immich`, `charts/ilias`) [25]; custom registries are exactly what `registryUrl=` is for. (agent-test/dev may confirm with the `global-renovate` MCP `preview_custom_manager`/`explain_config`.)

### Q2 — Official/community Helm chart → wrapper-vs-custom

- Official chart repo: `code.forgejo.org/forgejo-helm/forgejo-runner`. Hard facts from live API probes [15][16]:
  - `Chart.yaml` v0.7.5, **appVersion 12.7.3** (three minors behind v13.2.0, missing all v13 breaking changes + plugin work).
  - **Zero git tags, zero releases, NOT published as OCI** (`helm show chart oci://…` → 404 "name unknown"), so ArgoCD couldn't consume it the way `charts/forgejo` consumes the forgejo chart.
  - Last commits 2026-05-25 = renovate dependency bumps only.
  - Implementation: runner + dind sidecar over TLS tcp://127.0.0.1:2376; **top-level `securityContext: {privileged: true}` applied to BOTH containers** (runner container privileged too); registration via a **pre-install hook Job** that runs `forgejo-runner register --no-interactive` and patches the `.runner` file into a Secret using **kubectl + SA/Role/RoleBinding** (extra RBAC surface); `runner-data` is an **emptyDir**; config.yaml rendered from **plaintext values** (token/instance inline).
- Community charts (search survey [18][19][20]): `dtechvision/forgejo-runner-helm-chart` — self-declared "v0.0.1… not widely tested", adds a "Kubernetes backend" (job-per-Pod) via the alpha plugin protocol + PVC option (default off, 1Gi); `ultimaterex/forgejo-runner-k8s` — KEDA scale-to-zero ephemeral runners + privileged dind sidecar; "wrenix" chart referenced by the rootless-dind blog [20]. None is upstream-maintained.
- **Decision input (C03 task 1):** the wrapper-the-official-chart escape hatch was conditioned on "the official chart's k8s runtime is the only viable model" — there is no k8s runtime (Q5), and the chart fails this repo's standards (hook Job + kubectl RBAC + inline token in values + whole-pod privileged + emptyDir). → **Custom app-template 5.0.1 chart** (`charts/forgejo-runner`), which is also what the user explicitly asked for (D8 note "user asked for a separate chart").

### Q3 — Registration / authentication on Forgejo 15.0.9

Verified against the **live dev instance** (`git.scifi.farm` → `/api/v1/version` = `15.0.9+gitea-1.22.0`; `/swagger.v1.json` spec pulled) [14] + v15.0 docs [1]:

- Four scopes (identical in UI and API): instance `/admin/actions/runners`, org `/orgs/{org}/actions/runners`, user `/user/actions/runners`, repo `/repos/{owner}/{repo}/actions/runners` [1][14].
- **The current model is "authentication token", not "one-time registration token"**: creating a runner (UI "Create new runner", or `POST …/runners` with `{name, description?, ephemeral?}`) returns **`{id, token, uuid}`** and that token is the runner's long-lived credential — you paste `url`+`uuid`+`token` straight into the runner config (`server.connections.<name>`). No exchange step [1][14].
- Legacy endpoints still exist (`GET …/runners/registration-token`) for the old two-step `forgejo-runner register` flow used by the official chart / old examples [14][15][17]. We don't need them.
- **Offline registration** (built for IaC): `forgejo forgejo-cli actions register --name X --scope Y --secret <40-hex>` — you *generate the secret yourself*; first 16 hex chars become the uuid identifier, last 24 are the secret; re-running with the same name and changed trailing 24 chars rotates in place. Requires shell on the Forgejo server (kubectl exec into the forgejo pod — a **user action** under this repo's no-pod-exec rule) [1].
- Lifetime/rotation: persistent-runner token does not expire; rotation = delete + recreate via UI/API (no PUT endpoint in 15.0.9 [14]) or offline-CLI secret update [1]. Re-label/re-name is not API-editable in 15.0.9.
- **GitOps + Bitwarden shape** (finalizes the "exact env/key name" question in C03):
  - One item, LOGIN type, e.g. `dev-forgejo-runner`: **password = runner token, username = runner uuid** (both generated by Forgejo's create action).
  - ExternalSecret (`bitwarden-login` store) → Secret `forgejo-runner-secret` with keys `RUNNER_TOKEN` (password) and `RUNNER_UUID` (username).
  - Runner consumes the token **from a mounted file** (`token_url: file:/secrets/runner/RUNNER_TOKEN`, supported since v13 config: `token` and `token_url` are mutually exclusive [7]) → the token never appears in the rendered ConfigMap. The uuid is an identifier, not a secret — inline it in `config.yaml` or the custom-values slice.
  - `reloader.stakater.com/auto: "true"` (already planned) restarts the pod on token rotation.
  - One-time user action (before first boot): create the runner in the dev Forgejo UI (`/admin/actions/runners` for instance scope) or `curl -X POST` the API with an admin token, paste token+uuid into the Bitwarden item, put the UUID into `custom-values/dev/prod-values.yaml`.
  - Ephemeral mode: exists (`--ephemeral`, API property) but the daemon **refuses ephemeral** (`forgejo-runner daemon` exits when told to switch; `one-job` only) [1][11] → persistent runner is the correct choice for a long-lived deployment.

### Q4 — Config schema + breaking changes across majors

Current schema (authoritative: `config.example.yaml` @ v13.2.0, retrieved [7]):

```
log:      level, job_level                    (trace/debug/info/warn/error/fatal)
runner:   file (.runner), capacity (1), envs, env_file, timeout (3h),
          shutdown_timeout (3h), insecure, fetch_timeout (30s),
          fetch_interval (2s), report_interval (1s), labels []
cache:    enabled (true), dir ("" → $HOME/.cache/actcache = /data/.cache/actcache [6]),
          port/proxy_port (0=random), host, external_server, secret/secret_url,
          actions_cache_url_override
container: network ("" = create isolated per-job), enable_ipv6, privileged (false),
          options, workdir_parent, valid_volumes [], docker_host ("-"),
          force_pull, force_rebuild
host:     workdir_parent
server:   connections.<name>: {url, uuid, token | token_url, labels?, fetch_interval?}
plugins:  <name>: {address (host:port | unix socket), options map}   (v13.1+, alpha [9])
```

- **Env-var configuration: none in v13.** The old `GITEA_DEBUG/GITEA_TRACE/GITEA_RUNNER_CAPACITY/GITEA_RUNNER_FILE/GITEA_RUNNER_ENVIRON/GITEA_RUNNER_ENV_FILE` are *ignored* since v13 (no `FORGEJO_*` equivalent for the daemon) [8]. The official chart's `CONFIG_NAME/CONFIG_INSTANCE/CONFIG_TOKEN` envs are read only by its own registration Job script, not by the runner [15]. → **config.yaml is the only supported contract**; the chart should render it (ConfigMap for config.yaml, Secret for the token file).
- Labels grammar: `<name>:<backend>://<default-image>`; per-connection `labels:` limit a label set to one instance [2][7]. Backend options via query string (`?platform=linux/amd64`) or mapping form [7].
- Major-history that matters (RELEASE-NOTES.md ≤v8 [10] + per-release notes [3][8][9]):
  - v3.1: label scheme rework (`docker://`, `lxc://`, `host`); v4.0/v5.0: **`docker_host` default changed to NOT mount the socket** (security);
  - v7.0: `FORGEJO_*` contexts; v8.0: workflow schema validation, default image `docker://node:22-bookworm`, bash fallback changes;
  - v12.5: action cloning switched go-git → **git binary** (⇒ k3s MTU issue, Q5-ops/1779);
  - **v13.0 breaking** [8]: `add-path`/`set-output`/`set-env` workflow commands removed (use `$FORGEJO_PATH/$FORGEJO_OUTPUT/$FORGEJO_ENV`); `DOCKER_USERNAME/DOCKER_PASSWORD` secrets registry-auth removed (use `jobs.<job_id>.container.credentials`); invalid expressions/matrix now hard errors; **Docker minimum 25.0** (28.0.1 if job IPv6); `container.network_mode` removed → `container.network`; GITEA_* envs ignored.
  - v13.1: plugin engine (alpha) [9].
- Config file **format** has been stable across v9→v13 (same sections; additive keys); the v13 majors break *workflow semantics*, not config parsing. Renovate/coder discipline: bump runner with the docs' release blog in hand.

### Q5 — Execution model on single-node k3s (the posture question)

Facts, ranked by evidence strength:

1. **Host docker socket: unavailable — confirmed.** Dev cluster node `dev` runs `containerd://2.3.4-k3s1.36` (live probe [13]); k3s ships **containerd** as its CRI, docker is not present ("Packages…: containerd / cri-dockerd container runtime (CRI)" [24]). The runner speaks the **Docker or Podman HTTP API** (docs list `docker_host: unix://… | tcp://… | automount`, "Docker or Podman containerization" [2][7]) — a containerd CRI socket is not a Docker-API endpoint, so there is no socket-mount shortcut; `automount` would find nothing.
2. **`kubernetes://` runtime: does not exist.** Docs (v15 and latest) enumerate exactly three label types: `docker`, `lxc`, `host` [2]. The runner's own tracker: feature request "Dynamic OS Workloads … in Kubernetes" (#1355) closed in favor of an upstream design discussion (forgejo/discussions#66) [21]. The **only** way jobs-as-Pods works today is the **v13.1 alpha plugin protocol** (external gRPC engine, `plugins:` config + `<label>:<plugin>://<image>`), which the community dtechvision chart uses; the team explicitly documents alpha status, no stability guarantees, and is still collecting feedback on whether to commit to it [9][18][21]. → The plan's SA/RBAC/PodTemplateSecurity option is **off the table** for C03.
3. **Docker sidecar (dind) — the upstream-sanctioned k8s model.** Three converging sources:
   - **Official runner repo k8s example** `examples/kubernetes/dind-docker.yaml` [17]: Deployment with initContainer (register) + `runner` container + `daemon` container = `docker:28.3.0-dind` with `securityContext.privileged: true` **only on the dind container**; runner container hardened (drop ALL caps, `runAsNonRoot`, `readOnlyRootFilesystem`, `automountServiceAccountToken: false`, seccomp RuntimeDefault); DOCKER_HOST `tcp://localhost:2376` with TLS certs via emptyDir; job `network: host` in that example; all-emptyDir storage; it even carries an `argocd.argoproj.io/sync-wave` annotation (GitOps-aware).
   - **Official chart**: same two-container shape (runner + dind TLS 2376), weaker security defaults (whole-pod privileged) [15].
   - **Docs install-docker compose**: same pattern (`docker:dind` privileged + runner non-root 1001) [5]; docker-access doc gives the dind recipe incl. passing certs into job containers via `container.options` + `valid_volumes` [12].
   - Security posture (docs `docker-access` + `security` pages [12][11]): dind isolates jobs from *any host Docker system* (the alternative `automount` exposes the whole host to jobs — moot on k3s, but the docs' warning frames the threat model). Privileged dind ⇒ a malicious workflow can root the **dind container**, and privileged mode weakens the container/node boundary — the accepted mitigation set: private instance + trusted users only, tightest scope (Q3), `container.privileged: false` for *job* containers, no `valid_volumes`, per-job isolated networks (`network: ""`), resource caps via `container.options`, `runner.capacity` = concurrency, and ephemeral runners are *not* the pod-deletion pattern here [11][12].
4. **Rootless dind: fragile.** Community write-up documents rootless-dind-in-k8s failing outright on Ubuntu 24.04 (`kernel.apparmor_restrict_unprivileged_userns=1` breaks rootlesskit) requiring node-level sysctl changes; author concludes rootless runners on k8s are "not well-suited out of the box" [20]. The official docs' dind example runs `docker:dind` privileged [5][17]. Dev's node is openSUSE Tumbleweed (kernel 7.2) [13] — behavior unverified; do not stake the chunk on it.
5. **`host` labels** (steps run directly in the runner container): no isolation, workflow can read the runner's credentials file, docs explicitly warn "a single job can permanently destroy the host" [2][11]. Not proposed.
6. **Homelab precedents** (Q5 evidence): official example (above); ultimaterex KEDA chart runs privileged dind sidecars + scale-to-zero on k3s-class clusters [19]; k3s runner user filed issue #1779 (open): runner **≥12.5.0 intermittently fails action clones on k3s** — maintainer confirmed v12.5 moved cloning to the `git` binary; suspected overlay/MTU interaction; multi-node reporter cluster [21]. Single-node dev (CNI traffic mostly local via flannel's direct bridge) is a lower-risk exposure, but keep this as the first thing to check if clones fail — mitigation candidates: dind `--mtu 1450/1400` dockerd flag or job `network: host` (official example already uses host-network for jobs) [17][21].

**Recommendation for the user-sign-off gate:** *privileged dind sidecar + hardened runner container + no ServiceAccount (automountServiceAccountToken: false) + no RBAC at all* (declarative config, Q3 — we drop even the official example's init-registration SA). This is upstream's documented k8s pattern, not a repo-invention [5][12][17].

### Q6 — Connectivity

- The runner **polls** the instance over HTTPS/HTTP REST — "fetches workflows to run from a Forgejo instance" [docs], `runner.fetch_interval: 2s` + per-connection override in v13 config [7], and the security doc calls it "this runner's **polling** routine" [11]. No inbound connections needed → a headless Deployment is fine; no proxy/ingress entry required (consistent with the planned trio-deviation D9). The historic 30s default for codeberg.org is enforced client-side per instance [10]; nothing similar applies to our own instance.
- **In-cluster Service URL is viable**: `server.connections.<name>.url` is just how the runner reaches the instance — every deployment method (UI/API-issued uuid+token) is instance-agnostic; there is no requirement that the runner's URL equal the instance ROOT_URL, no Host-based auth in the runner protocol, and no redirect/TLS pinning on the API path. Both the official k8s example and the official chart take the URL as a plain value ("Do not forget to update `FORGEJO_INSTANCE_URL`" [17]) [15][17][18]. Keep the planned default `http://dev-forgejo-http:3000`.
  - **Caveat 1 (DNS scope):** a bare `dev-forgejo-http` resolves **only within the forgejo Service's namespace**. The runner lands in whatever namespace the dev umbrella gives it; C04 must either co-locate or make the URL a namespace-qualified FQDN (`dev-forgejo-http.<forgejo-ns>.svc.cluster.local`) — decide explicitly. ⚠️ Also: **today's dev cluster has NO forgejo workload at all** (namespaces list = base only, service not found — live probe [13]); see Contradictions.
  - Caveat 2 (plain http): token travels unencrypted inside the cluster network only; acceptable for a LAN-only dev cluster (the instance's own traffic is LAN/mesh; secrets elsewhere in this repo ride the same assumption). Public https (`https://git.scifi.farm`) works too and survives cross-cluster moves, but adds mesh/DNS + cert-chain dependencies to a CI control-plane — plan's in-cluster default stands.
  - The C02 hub-crowdsec routing is **irrelevant** — the runner never traverses the hub.
- Egress needed from the runner+dind pod: `data.forgejo.org` (DEFAULT_ACTIONS_URL = `https://data.forgejo.org` in Forgejo 15 [22] — actions like `actions/checkout` are cloned from there by the runner container, needs git+CA in image [6]) + image registries for job/label images (docker.io/ghcr.io) — dev cluster internet egress assumed (same as today's workloads).

### Q7 — Persistence / cache / volumes

- Two distinct caches:
  1. **Runner-side ACTIONS_CACHE** (`actions/cache`-style tarballs) — "The cache is stored by the runner itself and never sent to Forgejo" [docs admin]; dir default `"" → $HOME/.cache/actcache`, and `$HOME=/data` in the image [6][7]. Without persistence, caches vanish on every pod restart but correctness is unaffected (cache miss).
  2. **dind image store** `/var/lib/docker` inside the dind container — docs: "images … are **never updated** once downloaded" (pinning implication, Q9) and dind's `/var/lib/docker` "is **wiped if the container is recreated** unless volume-mapped; a mapped dir **needs periodic `docker system prune`**" [2][12]. This is the expensive one: pulling `act-24.04` ≈ 0.6 GB compressed / ~2 GB extracted per cold start (ghcr manifest probe [23]); every workflow also pulls service/step images.
- Official chart + upstream k8s example ship **everything as emptyDir** (no persistence story at all) [15][17]; the dtechvision chart adds an *optional* PVC (default off, 1Gi) for the runner's `/data` [18]. Upstream's own guidance says the dind data dir should be volume-mapped if you care about performance [12].
- **k3s/local-path specifics** (live [13]): the dev SC `local-path` is the **default**, provisioner `rancher.io/local-path`, `ReclaimPolicy: Delete`, `WaitForFirstConsumer`. Data lives on the node at `/var/lib/rancher/k3s/storage/…` [24]. single-node ⇒ RWO "host-ish" performance; PVC vs hostPath is then purely a management question — **prefer PVC** (declarative via app-template `persistence:`, reclaim semantics owned by the release; deleting the PVC deletes the cache, which is fine). emptyDir ⇒ cold cache on every redeploy/restart (and counts against pod `ephemeral-storage`).
- **Recommendation:**
  - dind `/var/lib/docker` → PVC (`local-path`, 10–20 Gi; act-24.04 ~2 GB extracted + base images + build layers; leave headroom, `docker system prune` note in values comment). Mount must be **only** on the dind container.
  - runner `/data` → either small PVC (3–5 Gi, keeps ACTIONS_CACHE across restarts) or emptyDir for v1; the token/config don't need `/data` in the declarative model (no `.runner` file). Pick: **PVC**, since the same local-path volume is trivial and restart-fast CI matters more than volume minimalism.
  - `docker-certs` shared volume: **emptyDir** (regenerated each start — the official example's comment "credentials re-generated each time the pod connects and does not need to be persisted" [17]).
  - Cache reachability: with dind sharing the pod netns, the runner's internal cache-proxy on a pod-IP port is reachable from job containers; if `ACTIONS_CACHE_URL` auto-detect ever picks the wrong interface, `cache.host` pins it [7]. Leave defaults.

### Q8 — Sizing + observability

- **The runner has NO metrics endpoint.** v13 config reference [7] has no metrics/listen option; official chart renders no ServiceMonitor/Service/port for metrics [15]; no community or upstream artifact provides Prometheus metrics (search surfaced only KEDA's queue-length scaler hitting Forgejo's *instance* API, not the runner [19][21-adjacent]). → **Do not add a ServiceMonitor/PodMonitor** in C03 (the repo `serviceMonitor:`/`podMonitor:` app-template pattern exists — `charts/exporter-mikrotik`, `charts/keycloakx` [25] — and both CRDs are installed on dev [13], so wiring later is cheap if metrics ever land upstream).
- Observability that *does* exist: stdout logs of both containers (job logs go to the instance UI via report_interval, not to stdout verbosity — `log.level`/`log.job_level` [7]); Forgejo admin API `GET /admin/actions/runners` (+ `/jobs`) to see registered runners/queue [14]; node/pod metrics via existing kube monitoring (restarts, cpu/mem, PVC usage).
- Sizing evidence: official example limits `runner 1 CPU/4Gi`, `dind 1 CPU/4Gi`, requests `100m/64Mi` [17]. Single-node dev cluster runs the whole dev stack; keep footprint modest and bound job waste:
  - runner container: requests `100m/256Mi` (repo tier floor), limit `500m/512Mi` (daemon itself is idle-poll + git clones).
  - dind container: requests `250m/512Mi`, limit `2 CPU/3Gi` (job workloads run *here*); plus `ephemeral-storage` request/limit if jobs use emptyDir space heavily (the official example caps 3Gi).
  - `runner.capacity: 1` (single node, plan default) ⇒ one concurrent job; also set `container.options` (e.g. `--memory=2g --cpus=2`) as the docs' resource-constraint mechanism for job containers [11].
- Probes: nothing to TCP-probe (no listener; cache ports are random [7]) — omit liveness/readiness (or exec `forgejo-runner --help`-style liveness is cargo-cult; skip is cleaner and matches upstream). Set `terminationGracePeriodSeconds ≥ runner.shutdown_timeout`… in practice: shutdown_timeout default 3h is the *doc* default — for a dev runner prefer an explicit shorter `timeout`/`shutdown_timeout` (e.g. 30m/5m) so ArgoCD syncs don't hang the pod [7][11].

### Q9 — Default labels + image resolution

- Grammar: `ubuntu-latest:docker://<image>` makes the runner answer `runs-on: ubuntu-latest` and run steps as root in `<image>` [2]. Actions that `uses:` node actions (e.g. `actions/checkout`) require **Node.js inside the job image** unless steps override `container.image` [2]; the runner's built-in fallback when nothing matches is `docker://node:22-bookworm` (v8+ default) [10].
- **The GitHub-parity image is `ghcr.io/catthehacker/ubuntu:act-24.04`** (also on docker.io as `catthehacker/ubuntu`): live registry probes → `act-24.04`, `act-22.04`, `act-latest` exist (200), `act-25.04` does **not** (404) — only LTS-based `act-*` tags [23]. Docs' own example uses `ghcr.io/catthehacker/ubuntu:act-22.04` [2]. These images ship node/tool-cache like GitHub runners (~0.6 GB compressed, ~2 GB extracted [23]).
- Known gotcha: non-LTS Ubuntu 25.x+ images broke step startup for runner ≤12.x due to rust-coreutils vs the runner's hard-coded `tail -f /dev/null` keepalive (issues #1565 → #1300, still open) [21]. Sticking to `act-22.04/act-24.04` avoids it; if jobs ever override `container.image` with rolling `ubuntu:latest`-style images, that's the failure mode to recognize.
- **Recommended starter set** (docker://amd64, covers the common `runs-on` vocabulary):

```yaml
labels:
  - ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-24.04
  - ubuntu-24.04:docker://ghcr.io/catthehacker/ubuntu:act-24.04
  - ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04
  - docker:docker://ghcr.io/catthehacker/ubuntu:act-24.04   # generic `runs-on: docker`
  - node22:docker://docker.io/library/node:22-bookworm       # light/no-toolcache runs
```
  - Docs advise pinning label images **by digest** for reproducibility (`node@sha256:…` example) [2] — homelab trade-off: tag-pin + renovate now, optional digest later.
  - No `arm64`, no `gpu`, no `host`/`lxc` labels (dev is amd64 k3s; lxc/host unsupported/unsafe in-pod [2][11]).
  - Per-connection labels exist [7] — moot for a single-connection dev runner.

## Contradictions (and how to weigh them)

1. **Kickoff note "Service `dev-forgejo-http:3000` verified live on dev 2026-10-21" vs today's later live probe:** dev cluster (readonly-dev-kubernetes, in-cluster k3s v1.36.5, node `dev`) shows **only base namespaces** — no `dev`/forgejo namespace, no `dev-forgejo-http` Service; the cluster looks freshly (re)built (8 days old) and not yet synced [13]. Meanwhile `git.scifi.farm` **is** live on 15.0.9 [14]. ⇒ The chart design is unaffected (URL is values-driven), but **C04's wiring premise needs re-verification**: which namespace hosts the dev forgejo when it re-syncs, and whether the "verified live" claim pre-dated a cluster rebuild. Escalated to coord; nothing in RESEARCH.md depends on resolving it.
2. **Official chart vs official docs/examples:** chart lags (12.7.3, privileged-everywhere, emptyDir, hook-Job+kubectl+RBAC, inline token values) while the docs+repo-example define the current sane pattern [15] vs [2][5][12][17]. Weight: **docs/example** — the chart is a community-maintenance artifact of the forgejo-helm org, not a support statement.
3. **`forgejo-runner register` (chart + k8s example flow) vs declarative `server.connections` (v15 docs, v13 config)** [15][17] vs [1][7]. Both work; the register path writes `.runner` (which also re-adds a writable state file + hook logic). For GitOps: **declarative config wins** — idempotent, secret-clean, no hook. (The compose install doc's flow is exactly this: edit config, run daemon, no register [5].)
4. **"dind requires privileged" (official README) vs rootless-dind charts/blogs** [17] vs [18][20]. Rootless works only after node-level sysctl/userns surgery and is known-fragile on current distros [20]; upstream never endorses it. Weight: privileged sidecar.
5. **Plan question wording "runner 1.x→2.x→3.x" and "kubernetes:// labels, SA/RBAC, PodTemplateSecurity"** vs reality (v13; no k8s runtime) [3][2][9]. The questions were written from a Gitea-runner/older-era mental model; answers above supersede. The only future-proof mention: watch forgejo/discussions#66 + the alpha plugin protocol [9][21].

## Implications for the plan — decision-ready for C03/C04

**Execution model (the user sign-off gate):** single Deployment, two containers, mirroring upstream's k8s example shape [17]:

| container | image (pin) | privileged | notes |
|---|---|---|---|
| `runner` | `code.forgejo.org/forgejo/runner:13.2.0` | **no** — drop ALL, runAsNonRoot 1000, RO rootfs, seccomp RuntimeDefault, automountServiceAccountToken: **false** | reads `/etc/runner/config.yaml` + token file |
| `dind` | `docker.io/library/docker:29.5.2-dind` (official chart's current pin; satisfies v13 Docker≥25 [8]) | **yes (the one and only)** | TLS on 2376 via shared emptyDir certs; `/var/lib/docker` on PVC |

**Volumes:** dind `/var/lib/docker` → PVC 15Gi `local-path` (image cache; `docker system prune` maintenance note in values comment [12]); runner `/data` → PVC 5Gi `local-path` (ACTIONS_CACHE + workdir, `$HOME=/data` [6][7]); `docker-certs` emptyDir [17]. No hostPath (PVC on the single default local-path SC is equivalent-with-better-lifecycle).

**Secret/token flow (fixes C03's open key-name item):** Bitwarden `dev-forgejo-runner` LOGIN item (password=token, username=uuid) → ExternalSecret → Secret `forgejo-runner-secret` keys `RUNNER_TOKEN`,`RUNNER_UUID` → mounted as files; config uses `server.connections.dev.{url, uuid, token_url: file:/secrets/forgejo-runner/RUNNER_TOKEN}`. Token never lands in a ConfigMap or values [1][7][14]. Re-create (delete+POST or UI) is the rotation story [14]. One-time user action: create runner (instance scope recommended — private dev instance, keeps org/user/repo scoping unnecessary; state this in values comment) + fill Bitwarden + `OVERRIDE_NEEDED` in custom-values/dev [1][14].

**Config rendered by chart** (values-driven skeleton; every key cited in comments): `log.level: info`; `runner: {capacity: 1, timeout: 30m, shutdown_timeout: 5m, fetch_interval: 2s, insecure: false, labels: <values>}`; `cache: {enabled: true, dir: /data/.cache/actcache}`; `container: {privileged: false, network: "", docker_host: "tcp://127.0.0.1:2376", options: " -v /certs/client:/certs/client", valid_volumes: ["/certs/client"]}`; `runner.envs: {DOCKER_HOST: tcp://127.0.0.1:2376, DOCKER_TLS_VERIFY: "1", DOCKER_CERT_PATH: /certs/client}` so `docker build` inside jobs reaches dind (the docs' three-step dind recipe [12]); `instanceUrl` default `http://dev-forgejo-http:3000` — **C04 decides namespace (FQDN if cross-ns)**. No Service, no Ingress, no probes, no SA/RBAC [17] (deviation from official chart's hook-RBAC is intentional).

**Resources:** runner `100m/256Mi` req (repo floor) — `500m/512Mi` limit; dind `250m/512Mi` req — `2 CPU/3Gi` limit; `container.options` job caps `--memory=2g --cpus=2`; ephemeral-storage limits on dind if jobs are storage-hungry [8-official example numbers 17].

**No metrics/ServiceMonitor** — none exists to scrape [7][15]; CRDs + repo pattern ready if upstream ever adds it [13][25].

**Renovate:** image lines annotated `# renovate: datasource=docker depName=forgejo/runner registryUrl=https://code.forgejo.org` (+ dind `depName=library/docker registryUrl=https://index.docker.io`), per the repo's existing annotation style [25]; validate via `global-renovate` MCP in C03 dev if in doubt.

**Known-risk callouts to put in values comments:** open upstream issue #1779 (k3s + runner ≥12.5 intermittent git-clone failures — first-suspect if workflows die at "checking out actions" [21]); docker never updates pulled images once downloaded ⇒ label images are effectively frozen until pruned [2]; privileged dind = documented security posture of the whole model [11][12].

### Would this CHANGE the approved plan?

Nothing structural — the chunk boundaries, dev-only target (D8), trio deviation (D9), ExternalSecret shape, and "custom chart unless official-chart-only-model" condition all survive contact with the evidence. **Updates C03/C04 must fold in** (not replan-worthy, but plan-text-stale): (a) runner is v13.x, not "1.x→3.x"; (b) the `kubernetes://`/SA/RBAC branch of the execution-model question is off the table → the user sign-off (gate item 2) can be a *one-line posture confirmation*: "privileged dind sidecar only in the pod, declarative token, no RBAC"; (c) token item carries **uuid + token** (two fields), not just "the token"; (d) no metrics wiring; (e) C04 namespace check against contradiction #1 before hardcoding the short service name.

## Open questions

1. **Where will the dev-forgejo Service live when dev re-syncs** (namespace name + whether the dev umbrella deploys it there at all) — needed for the exact default `instanceUrl` in C04; contradiction #1 [13][14].
2. Runner pod **fsGroup**: image runs as uid 1000 and mounts PVCs; local-path default perms may need `podSecurityContext.fsGroup: 1000` for /data writability — verify during first deploy (emptyDir path is fine today). Not researchable ahead of a working cluster.
3. Whether to mount the dind `/var/lib/docker` PVC **rw** while a `docker system prune` cron (possible later Forgejo-side workflow on this very runner — nice dogfood) — defer; manual prune fine.
4. Instance-scope vs dev-org-scope registration token: recommend **instance** for the private dev box, but it's a posture taste the user may fold into the same sign-off.
5. Confirm `forgejo-runner daemon` is fully happy with **connections-only config and no `.runner` file** (docs imply yes — compose flow edits config and starts daemon [5]); C03's smoke test should cover this. (This is the one implementation-time verification the research could not close from docs alone; risk low, fallback = `forgejo-runner register` once at first boot.)

## Adjacent (not core, but coord/dev should know)

- KEDA ships a `forgejo-jobs` scaler; the ultimaterex chart demonstrates scale-to-zero ephemeral runner pods for the dev box later if dind-idle RAM becomes a problem [19].
- `forgejo-runner exec` lets any agent smoke-test a workflow inside the runner pod without registering (used in docs to demo dind/ipv6 flags) [2][5].
- The dev instance's own admin token is NOT needed by the runner (uuid+token is the auth) — no extra Keycloak/Bitwarden item beyond the runner item [1][14].
- v17.0 is the current Forgejo *latest*; dev pins 15.0.9 = **LTS** — runner v13's workflow-semantics tightening (v13 blog) matches what newer-instance users already experience; fine [3][8].

## Reliability notes (self-review per STORM step 6)

- High (9/10): Q1 image/version/tags (registry+API direct probes); Q3 API endpoints + schemas (pulled from the live 15.0.9 instance swagger); Q2 official-chart status (repo API + helm OCI probe); Q5 no-kubernetes-runtime (docs v15 AND latest + release blog + issue trail).
- Medium (7/10): Q7 volume recommendation (upstream evidence is thin — official chart/example all-emptyDir; sizing is reasoned, not cited from a benchmark); Q8 sizing numbers (extrapolated from the official example's caps + repo tiers, not measured on *this* node).
- Weakest claim: "in-cluster plain-http Service URL works" — strong inference (URL is a config value everywhere, docs never mandate HTTPS, community charts take arbitrary URLs) but no source *explicitly* states "http in-cluster is fine"; first C03 smoke test verifies empirically. A fix/verify path exists: flip `insecure`-free https via ingress if ever proven wrong — the chart stays values-driven either way.
- Potential over-weight: privileged-dind recommendation leans on upstream examples; if the user rejects privileged entirely, the only viable fallback with today's stable runner is `runs-on` restricted to images that never need `docker build` (plain test jobs still work — runner *containers* don't require privileged, only dind does) — worth stating at the sign-off gate.
- Blind spot covered late: the plugin protocol (found mid-run via issue 1773) — captured as alpha-only [9]; nothing else in the question list was missed.

## Sources

1. https://forgejo.org/docs/v15.0/admin/actions/registration/ (LTS v15.0.10) — fetched full text.
2. https://forgejo.org/docs/v15.0/admin/actions/configuration/ — fetched full text.
3. https://code.forgejo.org/api/v1/repos/forgejo/runner/releases (live API probe, 2026-10-21: latest v13.2.0 2026-09-18).
4. code.forgejo.org container registry v2 API — live probes: `…/v2/token?service=container_registry…`, `…/v2/forgejo/runner/tags/list` (188 tags, no latest/main), `…/manifests/13.2.0` (OCI index amd64+arm64).
5. https://forgejo.org/docs/v15.0/admin/actions/installation/docker/ — fetched (uid 1000, compose dind, `data.forgejo.org/forgejo/runner:13`).
6. https://code.forgejo.org/forgejo/runner file `Dockerfile` @ref=v13.2.0 — fetched (alpine, git/bash/dumb-init, USER 1000, HOME=/data, VOLUME /data).
7. https://code.forgejo.org/forgejo/runner file `internal/pkg/config/config.example.yaml` @ref=v13.2.0 — fetched full 270-line reference.
8. https://forgejo.org/2026-08-runner-release-v13/ (blog) — fetched full text (v13 breaking changes).
9. https://forgejo.org/2026-09-runner-release-v131/ (blog) — fetched (v13.1 plugin capability, alpha gRPC, plugins config + label grammar).
10. https://code.forgejo.org/forgejo/runner file `RELEASE-NOTES.md` (main) — fetched (≤v8 history: v5/v4 docker_host default, v8 defaults+breaking, polling frequencies).
11. https://forgejo.org/docs/v15.0/admin/actions/security/ — fetched full text ("polling routine", ephemeral, scope, resource constraints, valid_volumes).
12. https://forgejo.org/docs/v15.0/admin/actions/docker-access/ — fetched full text (dind recipe, automount risks, LXC, emptyDir/prune warnings).
13. Live dev-cluster probe via `readonly-dev-kubernetes` MCP 2026-10-21: Node `dev` containerd 2.3.4-k3s1.36 / k3s v1.36.5 / openSUSE Tumbleweed / amd64 / single node; StorageClass `local-path (default)` ReclaimPolicy Delete WaitForFirstConsumer; ServiceMonitor+PodMonitor CRDs present; namespaces = base-only (no forgejo workload — contradiction #1).
14. Live instance probes 2026-10-21: `https://git.scifi.farm/api/v1/version` = `15.0.9+gitea-1.22.0`; `https://git.scifi.farm/swagger.v1.json` — runner endpoints + `RegisterRunnerOptions`/`RegisterRunnerResponse{id,token,uuid}` schemas.
15. https://code.forgejo.org/forgejo-helm/forgejo-runner — live probes: Chart.yaml (0.7.5 / appVersion 12.7.3), values.yaml, templates/deployment.yaml, templates/jobs.yaml, templates/secrets.yaml, values-dind-bypass.yaml, commits list (last 2026-05-25), tags=[], releases=[].
16. `helm show chart oci://code.forgejo.org/forgejo-helm/forgejo-runner` → 404 "name unknown" (chart not OCI-published), run 2026-10-21.
17. https://code.forgejo.org/forgejo/runner `examples/kubernetes/README.md` + `examples/kubernetes/dind-docker.yaml` @main — fetched full (official k8s dind pattern, per-container securityContext, argocd sync-wave).
18. https://github.com/dtechvision/forgejo-runner-helm-chart — README (v0.0.1 warning), values.yaml (kubernetesBackend, dind.rootless, persistence default off), deployment template grep.
19. https://github.com/ultimaterex/forgejo-runner-k8s — README (KEDA ephemeral + privileged dind sidecar, amd64+arm64).
20. https://sbulav.github.io/kubernetes/running-rootless-forgejo-runners-kubernetes-ubuntu/ — fetched (rootless dind breakage on Ubuntu 24.04 apparmor; TLS-dind config shape; wrenix chart).
21. code.forgejo.org issue tracker probes: forgejo/runner #1779 (open, k3s MTU ≥12.5, maintainer confirms git-binary cloning), #1355 (closed → discussions#66, "no native k8s engine"), #1773 (open, plugin-protocol alpha feedback thread), #1565 (closed — ubuntu≥25 rust-coreutils) → #1300 (open, hard-coded entrypoint).
22. https://forgejo.org/docs/v15.0/admin/config-cheat-sheet/ — fetched Actions section (DEFAULT_ACTIONS_URL = https://data.forgejo.org; retention defaults).
23. Live registry probes: `ghcr.io/v2/catthehacker/ubuntu/manifests/{act-22.04,act-24.04,act-latest}` → 200; `act-25.04` → 404; act-24.04 amd64 layers sum 0.58 GB compressed; docker hub API confirms docker.io mirror (`catthehacker/ubuntu:act-22.04`).
24. https://docs.k3s.io/ — fetched ("Packages… containerd / cri-dockerd CRI, Flannel CNI, local-path provisioner").
25. Repo files read today: `charts/forgejo/Chart.yaml` (appVersion 15.0.9, oci dep forgejo-helm 17.2.0), `charts/qdrant/Chart.yaml` (app-template 5.0.1), `renovate.json` (regex managers incl. `image:` + `# renovate: datasource=…` annotations), `charts/exporter-mikrotik/values.yaml` + `charts/keycloakx/values.yaml` (serviceMonitor precedent), `charts/forgejo/values.yaml` (no [actions] override).
