# Debug: SeaweedFS CSI driver can't connect after upgrades — 2026-10-25

## Symptom

After renovate bumped the seaweedfs chart (4.35.0 → 4.50.0, server image
4.34 → 4.50) and the seaweedfs-csi-driver chart (0.2.27 → 0.2.42, driver
image v1.4.20 → v1.4.35), every SeaweedFS volume mount failed on all
consumer clusters (gpu, infra, media, home, proxy-local observed):

```
MountVolume.MountDevice failed for volume "media" : rpc error: code = Internal
desc = reading persisted volume attributes for media: filer
seaweedfs-filer-4.infra.spencerslab.com:8884: Get
"http://seaweedfs-filer-4.infra.spencerslab.com:8884/.csi/vac/bWVkaWE":
dial tcp 10.0.77.59:8884: connect: connection refused
```

All pods were Running; all PVCs stayed Bound. ArgoCD showed
`proxy-local-seaweedfs-csi-driver` Degraded (stuck rollout, see below).

## Root cause

Driver v1.4.32+ added a VAC store (commit `7fbdd5c` in
seaweedfs/seaweedfs-csi-driver, `pkg/driver/vacstore.go`): the driver
persists VolumeAttributesClass parameters on the filer under `/.csi/vac/`
**via the filer's plain-HTTP API**, and `NodeStageVolume` reads them back on
**every mount** (`stageNewVolume` → `loadPersistedVolumeAttributes`, hard
failure if unreachable). `ControllerModifyVolume` writes them (hard
failure). The HTTP calls dial `filer.ToHttpAddress()` — the **base** port of
each configured `seaweedfsFiler` entry (here `8880-8884`), while gRPC uses
`ToGrpcAddress()` (base+10000 → `18880-18884`).

The lab's exposure of the infra filers is the five per-filer LoadBalancers
(`services/infra/prod/templates/seaweedfs-filer-{0..4}-grpc-service.yaml`,
k3s ServiceLB, shared IP 10.0.77.59 = the wildcard target of
`*.infra.spencerslab.com`). They exposed only the gRPC ports
`1888N → targetPort 18888`. The old driver v1.4.20 was gRPC-only, so the
`seaweedfsFiler: ...:8880-8884` config worked (clients silently dialed gRPC
at 18880-18884). Nothing ever listened on 8880-8884 (verified with a port
probe of 10.0.77.59: 18880-18884/8080/80/443 open, 8880-8884 refused).

So the new driver's VAC HTTP reads had no listener → every mount failed.
The seaweedfs server chart bump itself was not implicated (its filer
service template is effectively unchanged between 4.35.0 and 4.50.0).

## Fix (this branch)

Added the filer HTTP port to each per-filer LoadBalancer:
`port: 888N, targetPort: 8888` alongside the existing gRPC
`port: 1888N, targetPort: 18888`. After ArgoCD syncs the infra
`seaweedfs` app, ServiceLB binds 8880-8884 on 10.0.77.59 and the VAC HTTP
path resolves on every cluster. Exposure posture is unchanged from the
already-exposed gRPC ports (LAN/mesh only, no public proxy route).

Validation: YAML parse + port/selector assertions for all five service
files (`python3 -c yaml` script, all OK). No chart touched, so no
helm lint/template run. Runtime verification (mount recovery, see below)
happens after merge + ArgoCD sync.

## Post-merge recovery steps (user-owned)

1. **proxy-local controller rollout is deadlocked.** The CSI chart
   hardcodes a *required* podAntiAffinity on the controller deployment; on
   the single-node cluster the surging new pod
   (`proxy-local-seaweedfs-csi-driver-controller-59f8477ccc-2brsm`, Pending
   since the upgrade) can't schedule next to the old one, and the
   deployment hit `ProgressDeadlineExceeded`. Unblock by deleting the old
   pod so the new one schedules:
   `kubectl --context proxy-local -n default delete pod proxy-local-seaweedfs-csi-driver-controller-5bb79bdc65-pqvtl`
2. Verify recovery: FailedMount warnings stop; restart a pod that mounts a
   SeaweedFS volume and watch it come up; check each cluster's
   `seaweedfs-csi-driver` ArgoCD app returns Healthy.
3. **proxy-backup cluster** has no MCP access from this repo's tooling —
   check its CSI rollout and mounts by hand the same way.

## Follow-ups (not done here)

- Consider relaxing the controller podAntiAffinity to *preferred* for the
  single-node clusters (set `controller.affinity.podAntiAffinity` through
  the wrapper chart) so future CSI-driver bumps don't deadlock the rollout
  the same way.
- Unrelated pre-existing bug noticed during investigation:
  `services/infra/prod/values.yaml` maps the `seaweedfs-filer` generic
  ingress to service `seadweedfs-filer` (typo) — the filer's HTTPS ingress
  backend does not exist.