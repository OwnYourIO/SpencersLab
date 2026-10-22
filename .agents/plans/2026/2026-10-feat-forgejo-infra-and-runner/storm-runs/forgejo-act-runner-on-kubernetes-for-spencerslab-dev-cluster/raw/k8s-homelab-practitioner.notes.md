# Interview — Kubernetes operator / homelab practitioner

Interviewed 2026-10-21 (inline, single session); cluster state re-verified
via MCP on 2026-10-21; gitea/runner example re-fetched 2026-10-21.

## Q1: What are we scheduling onto?

Live dev cluster (MCP, 2026-10-21) [19]: k3s **v1.36.5+k3s1**, single node
`dev` (openSUSE Tumbleweed, containerd 2.3.4), node capacity **8 CPU /
~13.3 GiB / ~99 GiB**, default StorageClass **local-path**. Already running:
`dev-forgejo` (Forgejo 15.0.9, chart `forgejo-17.2.0`) and `pg-forgejo-1`
(Postgres 18), plus Coder, ArgoCD, monitoring. No node-local Docker — jobs
must run via the runner's own DinD sidecar.

## Q2: What is the canonical runner+DinD pod shape?

Two reference patterns, both read:

**gitea/runner `examples/kubernetes/dind-docker.yaml`** (main, re-fetched
2026-10-21) [10]:
- 2 PVCs: `runner-vol` 1Gi (RWO) → `/data` (holds `.runner` + config),
  `docker-vol` 20Gi (RWO) → `/var/lib/docker` (image cache — comment:
  "Without it … every job re-pulls its images").
- Deployment, `replicas: 1`,
  `terminationGracePeriodSeconds: 10800` — "keep above
  runner.shutdown_timeout" (3h).
- DinD as **initContainer with `restartPolicy: Always`** (legal since K8s
  1.29; dev's k3s 1.36.5 qualifies) [19], image `docker:29.9.1-dind`,
  `securityContext.privileged: true`, mounts the docker-socket emptyDir at
  `/var/run` and the docker PVC at `/var/lib/docker`.
- startup **and** liveness probe: `test -S /var/run/docker.sock`.
- runner container mounts `runner-data` → `/data` and the socket emptyDir →
  `/var/run`; talks to DinD via `DOCKER_HOST`.
- Same repo: a **StatefulSet variant** (per-replica PVC for `.runner` →
  stable identity per ordinal) and `kubernetes-pods.yaml` (experimental
  k8s backend: Role with pods/pods-exec/pods-log/secrets, label
  `ubuntu-latest:kubernetes://…`) [11].

**Official forgejo/runner example** (v13.2.0 source) [4]: Deployment
`replicas: 2`, per-pod initContainer runs the deprecated `register` CLI in a
retry loop (`RUNNER_NAME` from `metadata.name`), privileged
`docker.io/docker:28.3.0-dind` with TLS (`DOCKER_TLS_CERTDIR=/certs`),
hardened non-privileged runner container — but **all emptyDir**, so every
pod recreation registers a *new* runner (stale-runner accumulation), and it
pins the stale runner tag `6.4.0`. Mechanism is instructive, persistence
model is not.

## Q3: What breaks on a single-node k3s with local-path?

- **Overlay-on-overlay is not supported by the kernel** (Stack Overflow
  70631927; Docker docs concur) [14]: a DinD daemon whose storage driver
  needs overlay cannot run on a containerized/overlay rootfs. On this node,
  local-path PVs are backed by the **host root filesystem**, so overlay2
  inside DinD works *if* the node root is a normal fs. openSUSE Tumbleweed
  defaults to **btrfs**, on which overlay2 is fine — but the node's actual
  root fs type was not verifiable via the MCP k8s surface (no fs-type
  exposure) → open question, one-liner `df -T /` / `stat -f /` on the node.
- `/var/lib/docker` must **always** be a volume mount (never the pod's
  writable layer) — both reference examples agree [10][4].
- Sizing guidance (inference from [19] capacity + workload profile — not a
  sourced fact): runner container req 100m–500m / 256–512Mi, lim 1–2 CPU /
  2–4Gi; DinD req 100m / 256Mi, lim 2 CPU / 4Gi; PVCs runner-data 1–2Gi,
  docker-data 10–20Gi. The node already hosts Forgejo + Coder + PG +
  ArgoCD + monitoring, so limits stay conservative.

## Q4: Is there a Kubernetes-native (no-DinD) backend?

Experimental only. Runner 13.1.0 added an experimental gRPC
`plugin.v1alpha.BackendPlugin` [2]; upstream PR #1472 (K8s backend) is
**not merged**; feedback tracked at forgejo/runner issue #1773; discussion
codeberg forgejo/discussions#66 [20][16]. Third-party implementations
(eleboucher/runner-k8s-plugin, sjones512/forgejo-runner-kubernetes,
blurrycat.dev/kuranto, marinatedconcrete/forgejo-runner-operator) are not
production-ready [21]. A k3s community gist (net-pilgrim) does
StatefulSet r=1 + `docker:27-dind` but pins runner `4.0.1` and registers
with the long-gone `actions generate-runner-token` command — stale [13].
**Verdict: DinD sidecar on a PVC is the only proven path.**
