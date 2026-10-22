# Sources — Forgejo act_runner on Kubernetes (SpencersLab dev)

Merged 2026-10-21 from the per-perspective `raw/*.sources.tsv` files.
Citation keys `[n]` are used in the raw notes and in
`.agents/plans/2026/2026-10-feat-forgejo-infra-and-runner/RESEARCH.md`.

## Web

- [1] https://data.forgejo.org/v2/forgejo/runner/tags/list — Forgejo runner
  image tag list (data.forgejo.org registry) — fetched 2026-10-21
- [2] https://data.forgejo.org/api/v1/repos/forgejo/runner/releases?limit=3 —
  forgejo/runner releases: v13.0.0 (2026-08-03), v13.1.0 (2026-08-31),
  v13.2.0 (2026-09-18) — fetched 2026-10-21
- [3] https://forgejo.org/2026-08-runner-release-v13/ — "Forgejo Runner
  v13.0.0 is available" blog post (2026-08-03): breaking changes — fetched
  2026-10-21
- [4] https://code.forgejo.org/forgejo/runner — forgejo/runner **v13.2.0
  source** (fetched via Go module proxy zip,
  `proxy.golang.org/code.forgejo.org/forgejo/runner/v13/@v/v13.2.0.zip`):
  `Dockerfile`, `internal/pkg/config/config.example.yaml`,
  `internal/pkg/config/config.go`, `internal/pkg/config/registration.go`,
  `internal/app/cmd/register.go`, `internal/app/cmd/daemon.go`,
  `internal/app/cmd/args.go`, `examples/kubernetes/dind-docker.yaml` —
  fetched 2026-10-21
- [5] https://forgejo.org/docs/latest/admin/actions/ — Forgejo admin docs:
  Actions runners (registration, labels, default label
  `docker:docker://data.forgejo.org/oci/node:lts`) — fetched 2026-10-21
- [6] https://forgejo.org/docs/latest/admin/config-cheat-sheet/ — Forgejo
  server config cheat sheet: `[actions]` section defaults — fetched
  2026-10-21
- [7] https://forgejo.org/docs/latest/admin/installation/ — Forgejo runner
  installation docs (binary/docker) — fetched 2026-10-21
- [8] https://codeberg.org/forgejo/forgejo — Forgejo **server source, branch
  `v15.0/forgejo`** (the 15.x line our dev server runs):
  `routers/api/v1/api.go` (admin actions runner endpoints, deprecated
  `registration-token` route), `templates/shared/actions/runner_create.tmpl`,
  `runner_setup.tmpl`, `runner_list.tmpl` — fetched 2026-10-21
- [9] https://data.forgejo.org/api/v1/repos/forgejo/forgejo/releases?limit=8 —
  Forgejo server releases: v15.0.9 (2026-09-17), v15.0.10 (2026-10-12),
  v16.0.6 (2026-10-12), v17.0.0 (2026-10-15) — fetched 2026-10-21
- [10] https://gitea.com/gitea/runner/raw/branch/main/examples/kubernetes/dind-docker.yaml —
  gitea/runner K8s DinD example (2 PVCs; DinD initContainer
  `restartPolicy: Always`; socket probes; `terminationGracePeriodSeconds: 10800`)
  — fetched 2026-10-21
- [11] https://gitea.com/gitea/runner — gitea/runner repo,
  `examples/kubernetes/`: StatefulSet variant (per-ordinal PVC),
  `kubernetes-pods.yaml` (experimental k8s backend: Role
  pods/pods-exec/pods-log/secrets, label `ubuntu-latest:kubernetes://…`) —
  fetched 2026-10-21
- [12] https://github.com/dtechvision/forgejo-runner-helm-chart — dtechvision
  forgejo-runner-helm-chart v0.0.1 README + templates — fetched 2026-10-21
- [13] https://gist.github.com/net-pilgrim/5e10f4e54e7a996d7ca54f9aac2a8724 —
  k3s Forgejo runner gist (stale) — fetched 2026-10-21
- [14] https://stackoverflow.com/questions/70631927 — overlay-on-overlay
  (overlayfs on overlayfs) is not supported — fetched 2026-10-21
- [15] https://wiki.serversatho.me/forgejo — community wiki warning:
  `FORGEJO_INSTANCE_URL` / `FORGEJO_RUNNER_REGISTRATION_TOKEN` are Gitea
  `act_runner` env vars, not honored by the Forgejo runner — fetched
  2026-10-21
- [16] https://codeberg.org/forgejo/discussions/issues/66 — Forgejo
  discussion: native Kubernetes runners — fetched 2026-10-21
- [17] https://artifacthub.io/packages/helm/wrenix/forgejo-runner — wrenix
  forgejo-runner ArtifactHub listing (v0.7.6) — fetched 2026-10-21 (API
  returned HTML; state assessed from listing + WrenIX/helm-charts repo)
- [20] https://code.forgejo.org/forgejo/runner — upstream PR #1472
  (Kubernetes backend — not merged) + issue #1773 (feedback) — fetched
  2026-10-21
- [21] https://github.com/eleboucher/runner-k8s-plugin ·
  https://github.com/sjones512/forgejo-runner-kubernetes ·
  https://blurrycat.dev/kuranto ·
  https://github.com/marinatedconcrete/forgejo-runner-operator — third-party
  k8s-backend implementations (not production-ready) — fetched 2026-10-21
- [22] https://github.com/mother-of-all-self-hosting/ansible-role-forgejo-runner —
  `defaults/main.yml` + `templates/config.yaml.j2` — fetched 2026-10-21
- [23] https://forgejo.org/docs/latest/admin/actions/docker-access/ — Docker
  access / `docker_host` docs — fetched 2026-10-21

## Local / live (verified 2026-10-21)

- [18] Local repo: `charts/forgejo/Chart.yaml` + `values.yaml` (wrapper v1.0.4
  around `oci://code.forgejo.org/forgejo-helm` 17.2.0, appVersion 15.0.9),
  `services/dev/prod/values.yaml` (chart entry namespace `default`, ingress
  `git` → `dev-forgejo-http:3000`, `forgejo-token` bitwardenIds entry),
  `custom-values/dev/prod-values.yaml` (Bitwarden UUIDs,
  `ROOT_URL: https://git.scifi.farm/`),
  `services/dev/prod/templates/secret-forgejo-token.yaml` (existing
  ExternalSecret pattern)
- [19] Live dev cluster via `readonly-dev-kubernetes` MCP — k3s
  v1.36.5+k3s1; single node `dev` (openSUSE Tumbleweed, containerd 2.3.4);
  node capacity 8 CPU / ~13.3 GiB / ~99 GiB; default StorageClass
  `local-path`; `dev-forgejo` pod Running (Forgejo 15.0.9, chart
  `forgejo-17.2.0`); `pg-forgejo-1` (Postgres 18)
