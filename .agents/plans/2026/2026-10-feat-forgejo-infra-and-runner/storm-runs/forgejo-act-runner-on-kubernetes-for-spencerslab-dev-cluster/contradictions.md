# Contradictions — Forgejo act_runner on Kubernetes

Mapped 2026-10-21 from the five perspective notes. Each entry: the clashing
claims (with sources), then how to weigh them.

## C1. Server version: "Forgejo 7.x" vs actual 15.0.9

- Coordinator context said "Forgejo server 7.x / chart 17.x".
- Repo + live cluster say **Forgejo 15.0.9**: `charts/forgejo` appVersion
  15.0.9, live `dev-forgejo` pod runs 15.0.9 [18][19]; the "17.x" is the
  upstream *chart* version (`forgejo-helm` 17.2.0), not the server version.

**Weigh:** repo + live pod win; they are direct evidence. Impact is small
for the plan (registration/config docs are identical between the 15.0 and
latest doc trees), but it matters for: ephemeral runners (require 15+ [4]),
and for not chasing a nonexistent "7.x" doc tree.

## C2. Image registry: `data.forgejo.org` vs `code.forgejo.org`

- Official docs use `data.forgejo.org/forgejo/runner` [5][7].
- The official k8s example and most community examples use
  `code.forgejo.org/forgejo/runner` [4][12][13].

**Weigh:** both hosts serve the same image (tag lists verified on
data.forgejo.org [1]; the runner's own Dockerfile build context and
renovate pins in community charts confirm the code.forgejo.org variant).
Prefer the docs host (`data.forgejo.org`) — it's the canonical CDN and is
what the official docs tell users to pull; the renovate annotation
`depName=` must match the referenced image string exactly.

## C3. Env-var auto-registration: gitea examples vs forgejo source

- gitea/runner's k8s example registers purely via
  `GITEA_INSTANCE_URL` + `GITEA_RUNNER_REGISTRATION_TOKEN` env vars [10],
  and some community pages show `FORGEJO_INSTANCE_URL` /
  `FORGEJO_RUNNER_REGISTRATION_TOKEN` for Forgejo [13].
- Forgejo runner v13 source + docs: the image has a **bare binary CMD** with
  no env-driven registration [4]; the v13.0.0 release explicitly removed
  support for the deprecated `GITEA_*` env vars [3]; the community wiki
  warns those `FORGEJO_*` env vars belong to Gitea's act_runner [15];
  `register` itself is deprecated in favor of declarative
  `server.connections` [4].

**Weigh:** source + release notes win over examples. The env-var pattern
does not work for the Forgejo runner. The chart must use declarative
registration (config `server.connections` with `token_url: file:…`, or
`--url/--uuid/--token-url/--label` flags).

## C4. Persistence model: emptyDir+self-register vs PVC

- Official forgejo/runner k8s example: **all emptyDir**, per-pod
  initContainer self-registration → new runner per pod recreation, stale
  runners accumulate; pins stale tag 6.4.0 [4].
- gitea/runner examples: **PVCs** for `/data` (identity) and
  `/var/lib/docker` (image cache), stable identity across recreations [10][11].
- dtechvision helm chart: persistence **off by default** [12].

**Weigh:** the PVC model wins for a production-ish dev cluster — a lost
`.runner` means a new runner record + secret update + stale cleanup. The
official forgejo example's persistence choice is not a design statement;
its 6.4.0 pin shows the example is simply not maintained. Default the chart
to PVCs (both of them).

## C5. `docker_host`: "-" default vs socket-mounting examples

- Config default is `docker_host: "-"` = **no docker socket into job
  containers** [4][23].
- Community examples mount the socket and/or set `DOCKER_HOST` so jobs can
  reach it [13], and the DinD socket *is* mounted into the runner
  container in every example [4][10].

**Weigh:** these are two different sockets' worth of access. The runner
**daemon** must see the socket (that is how it creates job containers) —
every reference example does that. The **jobs** should not, by default.
Keep the config default; expose a values switch for opt-in job access.

## C6. "Kubernetes backend" claims

- dtechvision chart markets a "kubernetes backend" [12]; the gitea example
  ships `kubernetes-pods.yaml` [11].
- Upstream state: the k8s backend is an **experimental** gRPC plugin
  (runner 13.1.0+), PR #1472 not merged, issue #1773 tracks feedback;
  third-party implementations are not production-ready [16][20][21].

**Weigh:** treat as future work, not a dependency. The DinD sidecar pattern
is the only proven path for this chart.

## C7. DinD image version

- Official forgejo example: `docker:28.3.0-dind` [4].
- gitea example: `docker:29.9.1-dind` [10].
- v13 runner requirement: Docker ≥ 25.0, 28.0.1+ recommended (IPv6 bug) [3].

**Weigh:** both satisfy the requirements; the delta is irrelevant to
correctness. Pick one (suggest the newer 29.x per the more recently updated
gitea example) and let renovate track it.

## C8. wrenix/forgejo-runner chart state

- ArtifactHub lists wrenix/forgejo-runner at v0.7.6 [17].
- The `runner` chart directory is absent from the current WrenIX/helm-charts
  main branch (repo browsing 2026-10-21).

**Weigh:** the listing is likely stale (or the chart was removed). Either
way it cannot be adopted without re-validation; no impact on the plan since
the repo convention is hand-rolled charts.

## Uncontested (all perspectives agree)

- Runner identity = (uuid, token) pair; `.runner` file persists it; restart
  = re-attach [4][8].
- Actions is enabled by default on the server; no server-side config needed
  for dev [6][18].
- DinD must be privileged and its data root must be a volume mount [3][10][14].
- No official runner Helm chart exists; repo convention is hand-rolled
  app-template [12][17][18].

## Blind spot (no perspective fully addressed)

- **Node root filesystem type** on the dev k3s node. overlay-on-overlay is
  impossible [14], and local-path PVs back onto the node root fs [19];
  Tumbleweed defaults to btrfs (overlay2-friendly), but the MCP k8s surface
  exposes no fs type. Needs a one-liner on the node (`df -T /` or
  `stat -f /`) before the DinD pattern can be called safe.
