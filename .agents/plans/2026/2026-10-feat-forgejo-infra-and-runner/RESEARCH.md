# RESEARCH — Forgejo Actions runner on the dev k3s cluster
> DinD supplement (run 1, ported 2026-10-23): RESEARCH-dind-supplement.md — k3s MTU clone-failure warning (forgejo/runner#1779), ArgoCD-timeout rationale, reliability self-rating.

Deep research for ticket `feat-forgejo-infra-and-runner`, commissioned by the
coordinator on 2026-10-21. All web sources fetched 2026-10-21 unless noted;
full audit trail (perspectives, per-perspective notes + source lists,
contradiction map) in
`storm-runs/forgejo-act-runner-on-kubernetes-for-spencerslab-dev-cluster/` (this folder).
Citation keys `[n]` resolve in the Sources section below.

## TL;DR

1. Pin `data.forgejo.org/forgejo/runner:13.2.0` (latest, 2026-09-18). Runner
   v13 is a breaking major: **no env-var auto-registration, no `GITEA_*` env
   vars, `register` CLI deprecated** — register declaratively via
   `server.connections` + `token_url: file:…` in a mounted config/secret.
2. The dev server is **Forgejo 15.0.9** (chart wrapper 1.0.4 wrapping
   forgejo-helm 17.2.0), not "7.x"; Actions is on by default → **no
   server-side changes needed**.
3. Chart shape: 1-replica workload + **privileged DinD initContainer
   (`restartPolicy: Always`, fine on k3s 1.36)** + 2 PVCs (`/data` for the
   `.runner` identity, `/var/lib/docker` for the image cache). Never share
   one uuid+token across pods.
4. **No official runner Helm chart exists**; community charts are stale or
   untested → hand-rolled bjw-s app-template chart (repo convention), with a
   new Bitwarden item for the registration token (ExternalSecret).
5. Open items: dev node root-fs type (assumed btrfs → DinD overlay2 OK),
   runner registration scope (admin vs repo), Bitwarden item naming.

## Key findings

### Q1 — Runner images & versions

- Project is now `forgejo/runner` (renamed from `act_runner`; binary
  `forgejo-runner`); no GitHub mirror — code.forgejo.org only [2][4]. Image
  published as `data.forgejo.org/forgejo/runner` in official docs; community
  examples use `code.forgejo.org/forgejo/runner` — same image, two hosts
  (see Contradictions C2) [1][4][5].
- Tags verified via registry API: full semver + short aliases. Latest =
  **13.2.0** [1]. Releases: v13.0.0 2026-08-03, v13.1.0 2026-08-31,
  v13.2.0 2026-09-18 [2] — ~2–4 week cadence; runner majors are **not**
  aligned to server majors (server 15.x ↔ runner 13.x).
- **v13.0.0 is a breaking major** (official blog post) [3]: `GITEA_DEBUG`/
  `GITEA_TRACE`/`GITEA_RUNNER_CAPACITY`/`GITEA_RUNNER_FILE`/
  `GITEA_RUNNER_ENVIRON`/`GITEA_RUNNER_ENV_FILE` env vars ignored;
  `container.network_mode` removed (→ `container.network`); workflow
  commands `add-path`/`set-output`/`set-env` removed (write
  `$FORGEJO_PATH`/`$FORGEJO_OUTPUT`/`$FORGEJO_ENV`); `DOCKER_USERNAME`/
  `DOCKER_PASSWORD` secrets no longer used for registry auth (→
  `jobs.<id>.container.credentials`); **Docker minimum raised to 25.0**
  (28.0.1+ recommended for an IPv6 bug).
- v13.2.0 Dockerfile (read from source): alpine 3.24, `USER 1000:1000`,
  `HOME=/data`, `WORKDIR /data`, `VOLUME ["/data"]`, dumb-init entrypoint,
  **bare binary CMD — no auto-registration logic in the image** [4].
- Renovate: pin full semver with
  `# renovate: datasource=docker depName=data.forgejo.org/forgejo/runner versioning=semver`
  (repo already renovates runner references elsewhere) [1][18].
- Server: dev runs **15.0.9** (2026-09-17); latest 15.x patch is
  **15.0.10** (2026-10-12); v16.0.6 and v17.0.0 (2026-10-15) also out
  [9][18][19].

### Q2 — Registration flow

- Runner identity = **(uuid, token) pair**. Create via admin UI
  (Admin → Actions → Runners; v15 form is name+description only; the setup
  screen shows UUID+token one last time with a config snippet) or via
  `POST /api/v1/admin/actions/runners` `{Name, Description, Ephemeral}` →
  201 `{ID, UUID, Token}` [5][8].
- Admin API: `GET`/`DELETE /admin/actions/runners/{id}`,
  `GET /admin(/actions)/runners/jobs?labels=`; the global
  `registration-token` endpoint is **deprecated in Forgejo 15** (scoped
  variants exist); the server keeps serving the latest token for a runner
  [8]. UI offers per-runner `reset_registration_token` + delete [8].
- v13 registers over **gRPC actions-proto** (`runnerv1.Register`), not the
  old HTTP exchange; `forgejo-runner register` / `create-runner-file` are
  **deprecated** ("declare connections in the runner configuration instead",
  register.go:40) [4]. The v15.0 server branch has the gRPC actions API
  (added 2026-01-15) → 15.0.9 compatible [4][8].
- **`.runner` file** (default path; `runner.file: .runner`) is JSON
  `{WARNING, id, uuid, name, token, address, labels}` [4]. Persisting it on
  a PVC is what makes a restart a **re-attach**, not a re-registration.
  Conflict rules (source): `.runner` file + `server.connections` = error;
  flags + `server.connections` = error [4].
- **Declarative registration (use this)**: config
  `server.connections.dev: {url, uuid, token | token_url: file:$CREDENTIALS_DIRECTORY/token, labels}`
  (`$CREDENTIALS_DIRECTORY` is substituted by the runner) **or** flags
  `--url --uuid --token-url --label` (config file optional; `daemon`
  requires ≥1 connection) [4].
- **The Forgejo image does NOT auto-register from
  `FORGEJO_INSTANCE_URL` / `FORGEJO_RUNNER_REGISTRATION_TOKEN`** — those
  are Gitea `act_runner` env vars; gitea/runner examples still use them,
  which is what misleads community write-ups (see C3) [4][10][15].
- Ephemeral runners require **Forgejo 15+** (register.go:357 error string)
  and are **refused in daemon mode** (daemon.go:84) — a one-shot concept,
  not relevant to a persistent daemon [4].
- Default register label: `docker:docker://data.forgejo.org/oci/node:lts`
  [4][5].

### Q3 — Kubernetes patterns

- **Official forgejo/runner example** (v13.2.0 source): Deployment
  `replicas: 2`; per-pod initContainer runs the deprecated `register` CLI in
  a retry loop (`RUNNER_NAME` from `metadata.name`); privileged
  `docker:28.3.0-dind` with TLS (`DOCKER_TLS_CERTDIR=/certs`); hardened
  non-privileged runner container; **all emptyDir** → every pod recreation
  registers a *new* runner (stale-runner accumulation) and it pins the stale
  tag 6.4.0 [4]. Good mechanism reference, bad persistence model.
- **gitea/runner examples** (main, re-fetched 2026-10-21) [10][11]:
  Deployment + 2 PVCs — `runner-vol` 1Gi → `/data` (holds `.runner` +
  config), `docker-vol` 20Gi → `/var/lib/docker` (comment: without it "every
  job re-pulls its images"); **DinD as initContainer with
  `restartPolicy: Always`** (legal since K8s 1.29; dev's k3s 1.36.5
  qualifies [19]); DinD image `docker:29.9.1-dind`, `privileged: true`,
  socket emptyDir at `/var/run` + docker PVC at `/var/lib/docker`; startup
  **and** liveness probe `test -S /var/run/docker.sock`;
  `terminationGracePeriodSeconds: 10800` ("keep above
  runner.shutdown_timeout" = 3h). A StatefulSet variant gives per-ordinal
  PVCs (stable identity per replica); `kubernetes-pods.yaml` shows the
  experimental k8s backend (Role: pods/pods-exec/pods-log/secrets).
- **No DinD alternative in production shape**: the K8s-native backend is an
  experimental gRPC plugin (runner 13.1.0+); upstream PR #1472 not merged;
  issue #1773 tracks feedback; third-party impls (eleboucher/
  runner-k8s-plugin, sjones512/forgejo-runner-kubernetes, blurrycat.dev/
  kuranto, marinatedconcrete/forgejo-runner-operator) not production-ready
  [16][20][21].
- **Storage gotcha**: overlay-on-overlay is unsupported by the kernel [14] —
  DinD's data root must be a **volume mount** (never the pod layer).
  local-path PVs back onto the node root fs [19]; openSUSE Tumbleweed
  defaults to btrfs (overlay2-friendly) but the dev node's root fs type was
  not verifiable via the MCP k8s surface → open question.
- **Dev cluster facts** (MCP, 2026-10-21) [19]: k3s v1.36.5+k3s1, single
  node `dev` (openSUSE Tumbleweed, containerd 2.3.4), 8 CPU / ~13.3 GiB /
  ~99 GiB, default StorageClass local-path; already runs `dev-forgejo`
  (15.0.9) + `pg-forgejo-1` (Postgres 18) + Coder/ArgoCD/monitoring.
- **Sizing guidance** (inference from [19] + workload profile — not a
  sourced fact): runner req 100m–500m / 256–512Mi, lim 1–2 CPU / 2–4Gi;
  DinD req 100m / 256Mi, lim 2 CPU / 4Gi; PVCs runner-data 1–2Gi,
  docker-data 10–20Gi. Keep limits conservative — the node is shared.

### Q4 — Runner config surface (v13.2.0 `config.example.yaml`, read in full) [4]

- `runner`: `file: .runner`, `capacity: 1`, `envs`, `env_file`,
  `timeout: 3h` (server also caps jobs at 3h), `shutdown_timeout: 3h`,
  `insecure`, `fetch_timeout: 30s`, `fetch_interval: 2s`,
  `report_interval: 1s`, `report_retry`, `labels` (supports `?platform=`
  suffix + `label: image` mapping form).
- `cache`: `enabled: true`, `port: 0` (auto), `dir: $HOME/.cache/actcache`
  (= `/data/.cache/actcache` in the image → lands on the runner-data PVC),
  `external_server`, `secret`/`secret_url` (`file:` +
  `$CREDENTIALS_DIRECTORY`), `host`, `proxy_port`,
  `actions_cache_url_override`.
- `container`: `network: ""` (auto), `enable_ipv6`, `privileged: false`
  (comment: "required for Docker-in-Docker" — that's for *job* containers),
  `options`, `workdir_parent: /workspace`, `valid_volumes` (glob),
  **`docker_host: "-"` (default = no docker socket into job containers**;
  `automount` or `unix://…`/`ssh://` to opt in) [4][23], `force_pull`,
  `force_rebuild`.
- `host`: `workdir_parent: $HOME/.cache/act/`.
- `server.connections`: per-connection `url`, `uuid`, `token`/`token_url`,
  `labels`, `fetch_interval`.
- Relevant env vars: `DOCKER_HOST` (point the daemon at the in-pod socket),
  `CREDENTIALS_DIRECTORY`, `FORGEJO_CLIENT_TIMEOUT` [4].

### Q5 — Server-side Actions configuration

- **Actions is enabled by default** (since v1.21). `[actions]` defaults:
  ENABLED=true, DEFAULT_ACTIONS_URL=https://data.forgejo.org,
  ARTIFACT_RETENTION_DAYS=90, LOG_RETENTION_DAYS=365,
  ZOMBIE_TASK_TIMEOUT=10m, ENDLESS_TASK_TIMEOUT=3h, ABANDONED_JOB_TIMEOUT=24h
  [6].
- Dev's forgejo values set **no `[actions]` keys** [18] → the dev instance
  works out of the box for a runner; **no server-side changes required**
  (an optional 15.0.9 → 15.0.10 patch bump is a separate concern).

### Q6 — Operations

- Admin UI `/admin/actions/runners`: Name / Labels / Owner / online-offline
  status, Edit / Delete, per-runner `reset_registration_token` [5][8].
- **Restart = re-attach** (identity in `.runner`); in-flight jobs are lost
  on restart; the server reclaims them after ZOMBIE_TASK_TIMEOUT (10m)
  [4][6].
- **Lost identity** = orphaned server-side runner: create a fresh runner,
  update the uuid/token the chart consumes (new Bitwarden value →
  ExternalSecret refresh), delete the stale record (UI or DELETE API) [8].
  **Rotation**: UI reset (new token, same uuid) or full re-register (new
  uuid+token → secret + `.runner` update).
- **replicas>1 requires per-replica identity** (per-pod initContainer
  self-registration, or StatefulSet per-ordinal PVCs); **never share one
  uuid+token across pods** (double job pickup) [4][10][11]. At dev scale:
  default replicas=1; scaling means more runner *records*, not more
  replicas of one identity.
- **Blast radius**: DinD must be privileged (root-equivalent on node);
  runner container stays non-privileged (repo standard: drop ALL caps,
  allowPrivilegeEscalation false); `container.privileged: false` and
  `docker_host: "-"` keep *jobs* sandboxed by default [3][4][10].
- **Upgrade path**: image-tag bump only; `.runner` stays valid → re-attach
  across versions [2][4].

### Q7 — Prior art

- **No official Forgejo runner Helm chart** (official forgejo-helm is
  server-only; nothing from the forgejo org on ArtifactHub) [17][18].
- Community: **wrenix/forgejo-runner** — ArtifactHub v0.7.6 but the runner
  dir is absent from current WrenIX/helm-charts main (stale/removed) [17];
  **dtechvision/forgejo-runner-helm-chart** — v0.0.1, untested, Deployment
  r=2, DinD default `docker:28.3.0-dind`, **persistence off by default**
  [12]; **gitea.com/gitea/helm-actions** — Gitea fork, not Forgejo-
  compatible; forgejo-hetzner-runner / TrueNAS "Forgejo Runner" — VM
  playbooks, not Helm [12][17].
- Non-Helm prior art worth stealing: mother-of-all-self-hosting
  ansible-role-forgejo-runner (canonical declarative `config.yaml` shape,
  cross-checks the v13 config surface) [22]; gitea/runner k8s examples
  (the PVC + DinD-initContainer pattern) [10][11]; net-pilgrim k3s gist
  (shape only — stale: runner 4.0.1, dead `actions generate-runner-token`)
  [13].
- **Repo convention**: hand-rolled bjw-s app-template charts; official
  charts only wrapped when maintained (`charts/forgejo`, `charts/coder`)
  [18]. No official runner chart → hand-rolled `charts/forgejo-runner/`;
  extract patterns, adopt none.

## Contradictions and how to weigh them

1. **"Forgejo 7.x" vs 15.0.9** — coordinator context said 7.x; repo + live
   pod say 15.0.9, and "17.x" is the upstream chart version, not the server
   [18][19]. Weigh: direct evidence wins. Plan impact: ephemeral runners
   (15+) are available; don't chase a 7.x doc tree.
2. **Registry host** — docs say `data.forgejo.org/…`, examples say
   `code.forgejo.org/…` — same image. Weigh: use the docs host; the
   renovate `depName=` must match the referenced string exactly [1][4][5].
3. **Env-var auto-registration** — gitea examples + some community pages
   imply it; Forgejo v13 source + release notes say it doesn't exist
   (GITEA_* removed, bare binary CMD, `register` deprecated). Weigh: source
   wins. Use declarative `server.connections` [3][4][10][15].
4. **emptyDir+self-register vs PVCs** — official forgejo example vs gitea
   examples vs dtechvision (persistence off). Weigh: PVCs win (identity
   survival); the forgejo example is stale (6.4.0 pin) — its persistence
   choice is not a design statement [4][10][12].
5. **`docker_host`** — default `"-"` (jobs get no socket) vs examples that
   expose it. Weigh: two different audiences — the *daemon* needs the
   socket (all examples mount it), *jobs* should not by default. Keep the
   default; opt-in via values [4][13][23].
6. **"Kubernetes backend"** — dtechvision marketing / gitea example vs
   upstream reality (experimental gRPC plugin, PR #1472 unmerged). Weigh:
   future work only; DinD is the only proven path [11][12][16][20][21].
7. **DinD image** — 28.3.0-dind (forgejo example) vs 29.9.1-dind (gitea
   example). Both satisfy Docker ≥25.0 / 28.0.1+ guidance. Weigh: pick the
   newer and let renovate track [3][4][10].
8. **wrenix chart** — ArtifactHub listing vs absent repo dir. Weigh: stale
   either way; no impact (we hand-roll) [17].

## Implications for the plan

1. **Chart**: `charts/forgejo-runner/` — hand-rolled bjw-s app-template
   (repo standard 5.0.1), modeled on `charts/forgejo` (wrapper conventions:
   `bitwardenIds:` sentinels, local-path PVCs, one-file-per-secret
   ExternalSecret).
2. **Workload**: single-replica (Deployment or StatefulSet — planner's
   choice; app-template defaults to Deployment). Containers:
   - primary: `data.forgejo.org/forgejo/runner:13.2.0` (renovate-pinned),
     `forgejo-runner daemon` with declarative config (or flags);
   - initContainer `restartPolicy: Always` (K8s 1.29+; k3s 1.36.5 OK):
     `docker:29.x-dind` (or 28.3.0) **privileged**, socket emptyDir at
     `/var/run`, docker-data PVC at `/var/lib/docker`, startup+liveness
     probe `test -S /var/run/docker.sock`; runner container gets
     `DOCKER_HOST=unix:///var/run/docker.sock` (in-pod socket).
   - `terminationGracePeriodSeconds` ≥ 10800 (≥ `shutdown_timeout` 3h).
3. **Volumes**: 2 PVCs on `local-path` — runner-data 1–2Gi → `/data`
   (`.runner` + config + cache), docker-data 10–20Gi → `/var/lib/docker`.
   Resource tiers per the sizing guidance above (conservative; shared
   node).
4. **Registration**: one-time admin step (UI or API on
   `https://git.scifi.farm/`) to create the runner record → capture
   uuid + token. **New Bitwarden item** (suggested name `forgejo-runner`,
   token in PASSWORD field) → ExternalSecret in the chart (pattern:
   `services/dev/prod/templates/secret-forgejo-token.yaml`) → config
   `server.connections.dev.token_url: file:$CREDENTIALS_DIRECTORY/token`
   with `CREDENTIALS_DIRECTORY` pointing at the mounted secret; uuid/name
   are non-secret values. `url:` = in-cluster `http://dev-forgejo-http.default.svc:3000`
   (runner is a client; no public ingress).
5. **Labels**: at minimum the default
   `docker:docker://data.forgejo.org/oci/node:lts` plus a dev-specific
   label for `runs-on:` targeting.
6. **Secrets/trio**: `bitwardenIds` sentinel in chart values, UUID in
   `custom-values/dev/prod-values.yaml`, chart entry in
   `services/dev/prod/values.yaml`; the ingress/proxy entry is N/A for a
   client-only service — planner to confirm how to express that (the
   convention assumes web services).
7. **Do not** use: `register` CLI, env-var registration, emptyDir identity,
   shared identity across replicas, job-container docker socket by default,
   community charts, the k8s-native backend.
8. **Server side**: nothing to change (Actions on by default); note the
   optional 15.0.10 patch as adjacent, not in-scope.

## Open questions

1. **Dev node root filesystem type** — assumed btrfs (Tumbleweed default)
   → overlay2 OK for DinD on local-path PVs; needs one line on the node
   (`df -T /` / `stat -f /`; no MCP exposure). If the root were itself an
   overlay, DinD would need `vfs` or a different node.
2. **Registration scope** — instance-admin runner (all dev repos, simplest)
   vs repo-scoped runner? And: manual UI creation vs scripted via API using
   the existing `forgejo-token` item?
3. **Bitwarden item naming** for the runner registration token —
   `forgejo-runner`? (Repo pattern is one item per concern; must NOT reuse
   the existing `forgejo-token` item, which is the Coder workspace access
   token.)
4. **Workload kind** — Deployment vs StatefulSet for replicas=1 (both work;
   StatefulSet scales identity per ordinal later).
5. **DinD image pin** — `docker:29.9.1-dind` (gitea example, more recently
   updated) vs `28.3.0-dind` (forgejo example); both compliant.
6. **wrenix/forgejo-runner chart state** — stale listing vs removed dir;
   irrelevant to the plan (hand-rolled), noted for completeness.

## Adjacent

- **Forgejo 15.0.9 → 15.0.10** patch is available (2026-10-12); the chart
  dependency is manually bumped (OCI dep, renovate can't track it) — a
  separate `dep` ticket.
- The existing `forgejo-token` Bitwarden item + ExternalSecret (Coder
  workspace access token) is the template to copy for the runner token
  secret [18].
- **Experimental k8s backend** (runner 13.1.0+ gRPC plugin; PR #1472,
  issue #1773) is the long-term replacement for the DinD pattern — watch,
  don't depend [16][20][21].
- **Ephemeral runners** (Forgejo 15+) are available if one-shot job
  runners are ever wanted; they are explicitly not daemon-mode [4].
- A commented-out second Forgejo instance section exists in
  `services/infra/prod/values.yaml` — out of scope for this ticket [18].

## Sources

- [1] https://data.forgejo.org/v2/forgejo/runner/tags/list — runner image tag list — fetched 2026-10-21
- [2] https://data.forgejo.org/api/v1/repos/forgejo/runner/releases?limit=3 — runner releases v13.0.0/v13.1.0/v13.2.0 — fetched 2026-10-21
- [3] https://forgejo.org/2026-08-runner-release-v13/ — runner v13.0.0 breaking-changes post (2026-08-03) — fetched 2026-10-21
- [4] https://code.forgejo.org/forgejo/runner — forgejo/runner v13.2.0 source (Go module proxy zip): Dockerfile, config.example.yaml, config.go, registration.go, register.go, daemon.go, args.go, examples/kubernetes/dind-docker.yaml — fetched 2026-10-21
- [5] https://forgejo.org/docs/latest/admin/actions/ — admin docs: Actions runners, default label — fetched 2026-10-21
- [6] https://forgejo.org/docs/latest/admin/config-cheat-sheet/ — server `[actions]` defaults — fetched 2026-10-21
- [7] https://forgejo.org/docs/latest/admin/installation/ — runner installation docs — fetched 2026-10-21
- [8] https://codeberg.org/forgejo/forgejo — server source, branch `v15.0/forgejo`: routers/api/v1/api.go, templates/shared/actions/runner_{create,setup,list}.tmpl — fetched 2026-10-21
- [9] https://data.forgejo.org/api/v1/repos/forgejo/forgejo/releases?limit=8 — server releases v15.0.9/v15.0.10/v17.0.0 — fetched 2026-10-21
- [10] https://gitea.com/gitea/runner/raw/branch/main/examples/kubernetes/dind-docker.yaml — gitea/runner K8s DinD example — fetched 2026-10-21
- [11] https://gitea.com/gitea/runner — examples/kubernetes/: StatefulSet variant, kubernetes-pods.yaml — fetched 2026-10-21
- [12] https://github.com/dtechvision/forgejo-runner-helm-chart — v0.0.1 README + templates — fetched 2026-10-21
- [13] https://gist.github.com/net-pilgrim/5e10f4e54e7a996d7ca54f9aac2a8724 — k3s runner gist (stale) — fetched 2026-10-21
- [14] https://stackoverflow.com/questions/70631927 — overlay-on-overlay unsupported — fetched 2026-10-21
- [15] https://wiki.serversatho.me/forgejo — FORGEJO_* registration env vars are Gitea's — fetched 2026-10-21
- [16] https://codeberg.org/forgejo/discussions/issues/66 — native K8s runners discussion — fetched 2026-10-21
- [17] https://artifacthub.io/packages/helm/wrenix/forgejo-runner — wrenix listing (v0.7.6; dir absent from repo main) — fetched 2026-10-21
- [18] Local repo (verified 2026-10-21): charts/forgejo/{Chart.yaml,values.yaml}, services/dev/prod/values.yaml, custom-values/dev/prod-values.yaml, services/dev/prod/templates/secret-forgejo-token.yaml
- [19] Live dev cluster via readonly-dev-kubernetes MCP (2026-10-21): k3s v1.36.5+k3s1, node dev (openSUSE TW, containerd 2.3.4), 8 CPU/~13.3GiB/~99GiB, local-path default, dev-forgejo Running 15.0.9, pg-forgejo-1
- [20] https://code.forgejo.org/forgejo/runner — PR #1472 (K8s backend, unmerged), issue #1773 — fetched 2026-10-21
- [21] https://github.com/eleboucher/runner-k8s-plugin · https://github.com/sjones512/forgejo-runner-kubernetes · https://blurrycat.dev/kuranto · https://github.com/marinatedconcrete/forgejo-runner-operator — third-party k8s backends (not prod-ready) — fetched 2026-10-21
- [22] https://github.com/mother-of-all-self-hosting/ansible-role-forgejo-runner — config.yaml.j2 shape — fetched 2026-10-21
- [23] https://forgejo.org/docs/latest/admin/actions/docker-access/ — docker_host docs — fetched 2026-10-21
