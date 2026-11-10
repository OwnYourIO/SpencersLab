# SeaweedFS incident findings — 2026-11-10

Evidence gathered from Loki (`readonly-global-grafana`), Prometheus
(`prometheus.spencerslab.com`), pod logs/APIs (`readonly-{infra,media,gpu,home}-kubernetes`),
and the SeaweedFS master/admin HTTP surfaces (`seaweedfs-{master,admin}.infra.spencerslab.com`).
All times UTC. Cluster: infra (weed v4.50 `ec8f97935`, 8 volume servers, 5 filers, 1 master, 1 s3, 1 admin).

## Trigger event

- `pve-infra` (Proxmox host of the infra k3s VM) rebooted **2026-11-08 14:34**, taking down
  master/volumes/filers/s3/admin all at once. Master uptime at investigation time was 46h
  (started 14:33). A **second reboot happened during this investigation** (11-10 12:58).
- 17 minutes later (**11-08 14:53:17**) the S3 gateway began an eternal retry loop on one lost
  chunk — still running at 36,000 error lines/day.
- The same window corrupted the media FUSE staging mounts on the media cluster (first
  `corrupted mount` at 11-08 14:35:28) → the jellyfin error burst (11-08, peak ~1,330 err/day).
  `proxy-local` VM rebooted at the same 14:36 timestamp.

## ALL bad files (confirmed unrecoverable / permanently failing)

Only **one real lost data file** exists in 7 days of logs (≈8M lines swept):

1. **Loki chunk object in bucket `logs`**
   - Object key: `fake/681e07742c8440a8/1a1bb915381:1a1bb93f591:358a4ee9`
     (full S3 path `/buckets/logs/fake/681e07742c8440a8/1a1bb915381:1a1bb93f591:358a4ee9`)
   - Contains stream-hash `681e07742c8440a8`, log window **2026-11-06 07:21:46 → 07:26:57** (a ~5 min slice of one stream's logs).
   - Evidence: `NoSuchKey … The specified key does not exist` (Loki `parallel_chunk_fetch.go:74`, 12 hits)
     and the s3 gateway retry loop on chunk `fid 1982649,ffcb4cee151f1745a60afc08` —
     404 from BOTH replicas (volume-2 and volume-3) of volume `1982649` (logs collection),
     even with `readDeleted=true`.
   - **Action to take:** delete the filer entry (admin UI → File Browser → bucket `logs` → `fake/681e07742c8440a8/…`),
     then restart `seaweedfs-s3` deployment — the in-process reader retries forever until the pod restarts.

2. **Stuck pending-deletion (garbage, not a live file): `fid 10,ffcb4cee151762199b65ca24`**
   - media-collection volume `10` (28.5GB, live) is flagged **read only** → filer can never write
     the delete mark; retried forever. Fix by clearing volume 10's read-only flag (below), not by deleting a file.

3. **Potentially bad (no reads failed yet — but unreadable if touched): EC groups with >4/14 shards lost**
   in collection `default` (dynamic-CSI PVCs: `seaweedfs-extra/-important/-backups/-backup-important`
   storage classes — none set `collection`, so their data lands here):

   | EC volume | shards present | verdict |
   |---|---|---|
   | 1   | 13/14 | recoverable |
   | 4   | 7/14  | **data lost** |
   | 5   | 4/14  | **data lost** |
   | 440 | 13/14 | recoverable |
   | 441 | 14/14 | complete |
   | 446 | 6/14  | **data lost** |
   | 447 | 9/14  | **data lost** |
   | 448 | 11/14 | recoverable |
   | 449 | 7/14  | **data lost** |
   | 461 | 14/14 | complete (but delete_count 29010 > file_count 24649 anomaly) |

   Any file whose fid starts `4,`, `5,`, `446,`, `447,` or `449,` in collection `default` is unreadable.
   Enumerate from inside the cluster (no pod-exec for agents):
   ```
   weed shell -master seaweedfs-master.default:9333
     fsck -collection=default          # lists every fid whose chunks can't be assembled
     volume.list -collection=default   # file counts per EC shard location
   ```
   Nothing in the media/logs/backups reads failed for these groups in 7 days, so they may be
   stale/already-deleted data — fsck is the authoritative sweep.

## Volume-server problems inventory

1. **Diverged replica pairs in the `logs` collection** (each pair listed twice, rep `001` = wrong):
   | volume | replica A | replica B | file-count delta |
   |---|---|---|---|
   | 1982649 | volume-2: 80,872 | volume-3: 81,019 | 147 (both missing the lost chunk) |
   | 1982750 | volume-1: 37,334 | volume-4: 27,465 | ~10k |
   | 1982751 | volume-1: 13,385 | volume-4: 24,685 | ~11k |
   | 1982752 | volume-1: 12,963 | volume-4: 23,697 | ~11k |
   | 1982753 | volume-1: 13,564 | volume-4: 24,822 | ~11k |
   | 1982754 | volume-1: 13,502 | volume-4: 24,616 | ~11k |
   | 1982885 | volume-2: 25,174 | volume-3: 25,197 | 23 |
   | 1982886 | volume-2: 24,918 | volume-3: 24,929 | 11 |
   Documents/media volumes also drift by a few files (e.g. 1981163: 445 vs 450; 1981164: 476 vs 479).
   Reads land on whichever replica answers → intermittent NoSuchKey/500 for Loki even where data survives.
2. **Read-only volumes**: 1982649, 1982750–1982754, 1982885, 1982886 (logs) and **10 (media)**.
   These block the filer deletion queue at every vacuum cycle (daily ~03:29, 1,300–2,050 W-lines
   per filer/24h: `max retry attempts (10) reached … volume is read only`).
3. **Vacuum deadlock**: master repeatedly logs `skip vacuuming: not enough copies for volume` for
   1982360–1982362, 1982375, 1982376, 1982379, 1982381, 1982382, 1982656–1982660, 1982663
   (all **8-byte, 0-file husk volumes** in media/player/documents/backups/proxy-allowlist/backup-gpu).
   Delete marks on read-only volumes can never be compacted → garbage accumulates.
4. **EC misconfiguration (structural)**: EC is 10+4 = 14 shards, placement needs distinct servers,
   but there are **8 volume servers on ONE rack** (`infra.spencerslab.com`, single k3s node).
   Admin loops forever: `placed with relaxed placement constraints [anti-affinity caps replica-placement]`,
   `EC Detection: stopping early after 10 consecutive placement failures`, and
   `Failed to save/delete task state for ec_balance_*: invalid task ID` (~7.9k E/W lines/24h on admin-0).
   EC shard distribution: v0 17, v1 21, v2 22, v3 6, v4 14, v5 9, v6 6, v7 3 shards — the imbalance is
   the rebalancer thrashing against the impossible placement.
5. **Media PVs are replication `001` = two copies** (1 original + 1 extra; the master volume
   table shows every media volume on exactly 2 locations, so the "single copy" framing in the
   first pass was wrong). The real durability caveats: both copies live on **one physical host**
   (all 8 volume "servers" are pods on the single infra node, backed by the same 5 HDDs), and
   replica pairs drift after interrupted compaction (1981163: 445 vs 450; 1981164: 476 vs 479;
   the logs-collection deltas below are the extreme case).

## Filer / master / s3 / admin status

- Filers: no data-integrity errors other than the deletion-queue retries above; filer-4's 38k/h of
  `maybeReadHardLink` lines is INFO noise from library scans (hardlink resolution on /buckets/media).
- Master: healthy apart from the vacuum warnings; 46h uptime = crash/restart, not a redeploy
  (no chart change in git in that window — nearest commit c8d5effb2 11-09 is forgejo SSA).
- S3 gateway: 32.4k–36k E/24h, ~99% is the single-fid retry loop plus `failed to stream
  logs/fake/... GetObjectHandler: … connection reset by peer / broken pipe` (Loki cancels/traefik aborts).
- **Volume `/status` endpoint churn: ~1,709 `error writing JSON status /status 200: connection reset`
  lines/hour, still ongoing** — probes/scrapes timing out on the huge status JSON (matches the
  chart comment "volumes are actually broken… need a more permissive health check").
- Filer UI ingress is dead: `services/infra/prod/values.yaml` routes `seaweedfs-filer` to
  service **`seadweedfs-filer.infra`** (typo, line 70) → https://seaweedfs-filer.infra.spencerslab.com 404s.

## CSI / mount clients / app logs

- CSI controllers (external sidecars) crash-loop counts: **gpu attacher 420 / provisioner 412 / resizer 473**,
  home 60/63/63, infra 65/59/67, media 48/46/48 — all currently running; counts track seaweedfs downtime.
- Mount pods (FUSE): media 41, home 35, proxy-local 26, gpu 15, infra 6 restarts.
  `corrupted mount`/`not a live mount` warnings cluster around every pve-infra reboot.
- Leader-election `context deadline exceeded` (infra/media, 11-09 & 11-10 11:00 UTC): transient k8s API blips.
- **Jellyfin**: 1,480 err/warn 7d — all from the 11-08/09 mount crash (ENOTCONN on thumbnails;
  library recovered), plus standing non-storage noise (TVHeadEnd username unset, plugin-manifest
  deserialize failures, MusicBrainz). No file-level corruption observed.
- **Sonarr / Radarr**: zero storage errors in 7 days. Clean.

## Recommended remediation (order matters)

1. **Stop the retry storm**: delete `/buckets/logs/fake/681e07742c8440a8/1a1bb915381:1a1bb93f591:358a4ee9`
   (admin File Browser or `weed filer.delete`), restart the `seaweedfs-s3` pod.
2. **Decide on EC**: 10+4 on 8 servers/1 rack can never satisfy placement, and it already cost data.
   Either disable EC for `default` (admin UI → EC config / `file.configure.save`), or re-provision
   EC to 6+2 with the reality that a host reboot degrades every group. Then `ec.rebuild.*` for the
   recoverable groups 1, 440, 448.
3. **Repair diverged logs replicas**: keep the *larger* copy per pair (1982649: keep v3 81019;
   1982750-754: keep volume-4 copy; 1982885/886: either), delete the other replica via
   `volume.delete -force` on the losing server, let replication recopy. Then clear read-only flags
   (`weed volume.markReadonly` on each affected server) so the deletion queue + vacuum can drain.
4. **Clean husk volumes** (8 B/0 file, "not enough copies"): `volume.delete.empty` or
   `vacuum -force` per volume, which also unblocks the 461 delete_count anomaly.
5. **Fix repo hygiene**: `seadweedfs-filer` typo in `services/infra/prod/values.yaml:70`
   (fixed on branch `fix/seaweedfs-filer-ingress-typo`); add `collection` parameters to the
   dynamic StorageClasses so new CSI data never lands in the EC-eligible unnamed/default pool.
   (Media `001` is already two copies — no bump needed; see the replication note above.)
6. **Harden the reboot path**: a pve-infra reboot currently takes master+volumes+filers+s3 down
   simultaneously mid-vacuum/mid-EC-move — that is what broke the shards and diverged the replicas.
   Ordered shutdown on the VM (stop master first), plus podDisruptionBudgets on the weed
   StatefulSets, would prevent the next occurrence.
