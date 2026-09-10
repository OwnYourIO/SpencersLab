# 2026-09-07 — immich image serving outage: empty SeaweedFS CSI CoreDNS rewrites (home)

## Status

Fix applied and validated in worktree `seaweed-troubleshooting`; **not committed** (user
opted to handle it). Merge to main + ArgoCD sync is the remaining recovery step.

## Symptom

`pictures.spencerslab.com` (immich, home cluster) failed to serve pictures starting
~20:26 UTC. immich-server log: `Unable to send file: Error: EIO: i/o error, read`.

## Root cause chain

1. immich's `UPLOAD_LOCATION` is the `pictures-shared` PVC → SeaweedFS CSI FUSE mount
   (daemon pod `home-seaweedfs-csi-driver-mount`).
2. SeaweedFS servers run only on the **infra** cluster (8 volume pods, 5 filers,
   master — all healthy). The home-cluster mount reads chunks via
   `http://seaweedfs-volume-{0..7}.seaweedfs-volume.default:8080/...`.
3. Those names don't exist in-cluster; `charts/seaweedfs-csi-driver` renders a
   `coredns-custom` ConfigMap (kube-system) with CoreDNS `rewrite name` rules mapping
   them to `seaweedfs-volume-{i}.infra.spencerslab.com`.
4. The live ConfigMap's `log.override` was **empty**: the template iterates
   `until (.Values.seaweedfs-csi-driver.volume-count | int)`; `volume-count` was absent
   at that nesting level, so the chart placeholder string coerced to 0 → empty block.
5. Regression commit: `19ab00d5` "Try moving volume-count: 8 up an indentation level"
   un-nested `volume-count: 8` in `custom-values/home/prod-values.yaml`. gpu, media and
   proxy-local keep the nested copy — only home broke. ArgoCD sync history: #23
   (2026-04-14) last good values, #24 (2026-09-06 17:22) first render without them.
6. Trigger for tonight: cluster-wide reboot ~18:45 restarted CoreDNS, which loaded the
   emptied override → NXDOMAIN for all volume servers → EIO on every read.

## Change

`custom-values/home/prod-values.yaml` (+6 lines): restored `volume-count: 8` nested
under `seaweedfs-csi-driver.seaweedfs-csi-driver` (parity with gpu/media/proxy-local),
plus an explanatory comment.

## Validation

- `helm lint charts/seaweedfs-csi-driver` — pass.
- `helm template charts/seaweedfs-csi-driver` with the post-fix merged values — renders
  all 8 rewrite lines in `coredns-custom`.
- Infra backend confirmed healthy via `infra-readonly-kubernetes` (volume/filer/master
  pods Running). Infra's own empty `coredns-custom` is harmless (native pod DNS).

## Remaining recovery steps

1. Commit + merge to `main` (user's action).
2. ArgoCD syncs `home-seaweedfs-csi-driver` → ConfigMap refilled.
3. CoreDNS picks up the override via `reload`; if it does not hot-reload imported
   `.override` files, restart the `coredns` pod (needs `home-admin-kubernetes`
   confirmation).
4. FUSE mount self-heals (weed mount retries with backoff); no immich restart needed.

## Follow-ups (not blocking)

- Infra filer pods restarted several times recently (filer-2/3/4 within ~90 min of the
  incident) — watch separately.
- Consider a CI/render guard: fail chart rendering when any `OVERRIDE_VIA_CUSTOM_VALUES`
  placeholder survives into a template output (the empty-rewrite failure mode was silent).
