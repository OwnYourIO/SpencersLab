# Perspectives — Forgejo act_runner on Kubernetes

Derived from the coordinator's 7 questions; each lens has a stake in the chart
design and sees what the others miss.

1. **Forgejo upstream documentation** (forgejo.org/docs, code.forgejo.org)
   - Lens: the official contract for the runner (registration, env vars,
     `.runner` semantics, server-side `[actions]` config, admin UI).
   - Sees: the exact registration flow and what the SERVER must enable —
     the ground truth the chart must match.

2. **act_runner project** (codeberg/github forgejo/act_runner releases + source)
   - Lens: the software itself — images, registries, tag scheme, release
     cadence, `config.yaml` surface, version compatibility with server 15.x.
   - Sees: what to pin for renovate and what flags/env map to config keys.

3. **Kubernetes operator / homelab practitioner**
   - Lens: running a DinD-style workload on a single-node k3s with local-path
     storage — Deployment vs StatefulSet, privileged requirements,
     overlay-on-overlay pitfalls, volume needs.
   - Sees: the failure modes a homelab-scale runner hits at runtime.

4. **Helm chart ecosystem** (forgejo-helm repo, ArtifactHub community charts)
   - Lens: does an official runner chart exist? What shape do community charts
     have (registration secret handling, DinD, persistence)?
   - Sees: extractable design decisions — and whether wrapping beats
     hand-rolling (repo convention is hand-rolled app-template).

5. **Ops/security reviewer**
   - Lens: runner lifecycle — heartbeats, restarts, lost identity, token
     rotation, stale-runner cleanup, replicas>1 implications, privileged-pod
     blast radius.
   - Sees: the day-2 questions the planner must encode as values/docs.
