# Debug: home cluster daemon crash during Pictaria enrichment

Type: debug | Date: 2026-09-13 | Status: root cause identified; mitigations proposed

## Symptom

Starting a Pictaria enrich run crashed the home cluster's k3s daemon
(API server refusing connections ~22:09 UTC, kubelet 502). Cluster entered a
probe-failure/restart storm and recovered slowly (kubelet restarted at
22:15:04 per kubelet Summary API startTime).

## Evidence (from monitoring-cluster Prometheus + home API)

- **No OOM kills**: `node_vmstat_oom_kill{instance="home-lab"}` = 0 throughout.
- **Load explosion, not CPU**: `node_load1` baseline 2–6 → 13.1 (21:57) →
  30.5 (21:59) → 48.8 (22:01) → **55.1 (22:03)**, sustained 33–55 for 10+
  min. Container CPU usage during the window was only ~2.0–2.4 cores →
  the load is D-state (uninterruptible I/O wait), not compute.
- **Disk saturation**: `rate(node_disk_io_time_seconds_total{device="sda"})`
  baseline 0.35–0.55 → 0.85–0.94 sustained from ~21:53 through the crash.
- **Memory chronically on the edge**: MemAvailable 1.1–1.5 GB of ~17.5 GB for
  the whole window (dips to 1.06 GB at 21:57 and 22:05), **zero swap**.
- **Read storm across unrelated pods** during the crash window (mongodb,
  seaweedfs-csi controller+mount, pg-immich, pg-paperless, pg-immich-dev,
  argocd, alloy all reading 1–7 MB/s simultaneously) — page-cache thrash:
  with ~1 GB available, cache eviction forces every reader to the saturated disk.
- **Enrichment correlation**: Pictaria's SQLite writes active 21:09–21:51
  (earlier run) with matching load spikes at ~20:51–20:57 (load 10–11) and
  ~21:07 (10.8); the fatal spiral began ~21:53 as the next run ramped.
  Pictaria's own disk I/O is tiny (KB/s) — it triggers via Immich asset
  reads + DB activity on an already-edge node, not by writing.
- **The disk**: `node_disk_info` → sda = `QEMU_HARDDISK`, **rotational=1**.
  home-lab is a QEMU VM on a virtual spinning disk — the worst case for the
  concurrent random-read pattern above.

## Causal chain

1. Node runs chronically at ~90% memory, no swap (pods ≈ 13 GB of 17.5 GB).
2. Enrich run starts → Immich serves originals (disk reads) + pg-immich +
   Pictaria SQLite writes on top of normal background load.
3. sda saturates (~90% io_time); memory pressure evicts page cache, so every
   other workload's reads also hit the saturated disk.
4. Processes pile up in D-state → load1 ≈ 55 on 6 cores.
5. k3s server (etcd fsync) can't make progress through the I/O storm → daemon
   hangs/dies → API down, kubelet down; systemd brings it back ~22:15.
6. Probe failures during the blackout trigger a pod restart storm that keeps
   the disk saturated during recovery (io PSI avg300 ≈ 22 afterwards).

## Secondary finding (fixed)

`home-immich-analyze` in CreateContainerConfigError for 4d: chart sets
`runAsNonRoot: true` but the image declares `USER appuser` (non-numeric),
which kubelet cannot verify. Fixed in charts/immich-analyze/values.yaml with
numeric IDs taken from the image's /etc/passwd (appuser=100, group=101).
Validated with helm lint/template. (Not crash-related; the pod never started.)

Note: immich-analyze has no persistence for /data — its processed-asset state
is ephemeral across restarts. Design question for a follow-up, out of scope.

## Recommended mitigations (user decision)

1. **Add swap on home-lab** (4–8 GB zram or file): converts the hard
   thrash cliff into graceful slowdown; K3s runs fine with swap.
2. **Fix the storage**: if the VM's backing storage is SSD, present it as
   non-rotational (virtio + cache=none, rotational=0); if it's really
   HDD-backed, move the VM to SSD. Random I/O on rotational media is the
   core weakness.
3. **Reduce memory overcommit**: ~13 GB of pods on 17.5 GB leaves no buffer;
   trim idle services or add RAM.
4. **Until then**: run enrich runs when the node is otherwise quiet; expect
   the cluster to degrade during large sweeps.
