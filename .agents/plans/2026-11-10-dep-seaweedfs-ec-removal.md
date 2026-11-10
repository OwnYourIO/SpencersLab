# Plan — get off SeaweedFS EC + heal read-only/vacuum deadlock

Date: 2026-11-10 · Type: dep (decommission) · Evidence: `.agents/notes/2026-11-10-seaweedfs-incident-findings.md`
Operator: user (every step needs pod access; agents have no exec). Run shell commands from an
infra pod with the weed binary (e.g. `seaweedfs-master-0`) :
`weed shell -master seaweedfs-master-0.seaweedfs-master.default:9333 -filer seaweedfs-filer.default:8888`
(scriptable: `echo 'lock; …; unlock' | weed shell`).

Goal: EC is not wanted ("I don't use it"). Today: 10 EC groups in the (default) collection,
8 degraded, 5 unrecoverable, admin maintenance loop thrashing on impossible placement,
and a vacuum deadlock on read-only logs volumes blocking the filer delete queue.

## Commands (verification suite for this plan)

```bash
# cluster state before/after (all should be empty/absent at the end):
curl -sk https://seaweedfs-admin.infra.spencerslab.com/storage/ec-shards   # EC groups table → "No EC volumes"
curl -sk https://seaweedfs-master.infra.spencerslab.com/ | grep -A2 "Up Time"
echo "lock; volume.list; unlock" | weed shell … | grep -iE "read.?only|not found"   # no read-only flags left
# Loki: no new NoSuchKey:
#   {cluster="monitoring", app_kubernetes_io_name="loki"} |~ "NoSuchKey" |~ "load chunk"
# s3 pod: retry loop gone:
kubectl -n default logs deploy/seaweedfs-s3 | grep -c "retry reading"   # → 0 after pod restart
# repo render for the ingress typo fix (already on fix branch):
helm template infra services/infra/prod --set domain=spencerslab.com --set clusterName=infra \
  -s templates/generic-ingress.yaml | grep -A3 "name: \"seaweedfs-filer\""
```

## Phase 0 — stop the churn (do this first, before touching data)

The EC maintenance loop runs in the **admin server** (no `weed worker` exists; the chart's
`worker.enabled=false`, which is why tasks are detected, queued, never executed, and never
persisted — `admin.dataDir` is empty → in-memory state → `invalid task ID` × ~8k/day).

1. In the admin UI → **Workers / plugin lanes pages** (`/plugin/lanes/default`, `/plugin/lanes/heavy`):
   set **Enabled = false** for `erasure_coding` and `ec_balance` (leave `vacuum` ON — you need it
   in Phase 3).
2. Make it survive restarts — in the seaweedfs subchart values for infra:
   ```yaml
   admin:
     extraEnvironmentVars:
       WEED_MAINTENANCE_ERASURE_CODING_ENABLED: "false"
       WEED_MAINTENANCE_EC_BALANCE_ENABLED: "false"
   ```
   (env names follow admin.toml's `[maintenance.*]` sections uppercased with dots→underscores;
   confirm exact keys with `weed scaffold -config=admin` inside any weed container before
   merging. Optionally also set `admin.dataDir`/persistence so task state stops re-proposing.)
3. Verify: admin-0 restarts (ArgoCD sync) → `W… detection.go` / `E… maintenance_queue.go` lines
   stop; master log should show `Skipping master maintenance scripts because admin server is
   connected` (the master's built-in 17-min `ec.encode` script — the thing that EC'd these
   volumes in the first place — stays suppressed while admin is connected).

## Phase 1 — decode the recoverable EC volumes

Recoverable = ≥10 of 14 shards present: **1 (13), 440 (13), 441 (14), 448 (11), 461 (14)**.
`ec.decode` rebuilds a normal replicated volume from the shards, then deletes them
(≈29GB logical each; servers have 3–7TB free each).

```
lock
ec.decode -collection=default     # if "no matches", retry with -collection="" (unnamed collection is literally "default" here)
volume.list
unlock
```
Expected: the five groups above decode OK; groups 4, 5, 446, 447, 449 fail with
"not enough shards" — that is the confirm-unrecoverable answer; leave them for Phase 2.

## Phase 2 — purge the unrecoverable remnants (groups 4, 5, 446, 447, 449)

1. Find live files that still reference them (probably few — most of this data looks like
   deleted-but-unvacuumed CSI PVC leftovers):
   ```
   lock
   volume.fsck -findMissingChunksInFiler -verifyNeedles -volumeId 4
   … repeat for 5, 446, 447, 449
   unlock
   ```
   It prints filer paths (e.g. `/buckets/…`) whose chunks can't be assembled. For each path,
   confirm with `fs.meta.cat <path>` (shows the missing fids) and `fs.rm <path>` — apps backed
   by those PVCs should be restored from the `backups`/`backup-gpu` collections, not expected
   to self-heal.
2. Delete the leftover shard files (shard volume ids are the 1982xxxx entries the admin EC page
   names per server; also visible in `volume.list` EcShard output):
   ```
   lock
   volume.delete -volumeId <shard id> -server <seaweedfs-volume-N.seaweedfs-volume.default:8080>   # each remaining shard of the 5 groups
   unlock
   ```
3. Confirm the admin EC Volumes page is empty.

## Phase 3 — heal the logs/media volume damage (the read-only + husk cleanup)

Order matters: mark writable **before** vacuum/checks, fix divergence **before** deleteEmpty.
Investigate state first, then apply.

```
lock
# 3a. inspect: which locations carry readOnly, current replica counts
volume.list | tee /tmp/vol_before.txt

# 3b. clear read-only flags — targeted (each of the 8 logs volumes, on BOTH replica nodes;
#     the pairs are volume-1/volume-4 for 1982750–754, volume-2/volume-3 for 1982649/1982885/1982886)
volume.mark -node seaweedfs-volume-1.seaweedfs-volume.default:8080 -volumeId 1982750 -writable
… (all 16 node×volume combinations, plus:)
volume.mark -node <holder> -volumeId 1982649 -writable     # v2 and v3
volume.mark -node <holder> -volumeId 1982885 -writable     # v2 and v3
volume.mark -node <holder> -volumeId 1982886 -writable     # v2 and v3
volume.mark -node <holder> -volumeId 10 -writable          # media volume 10 (holders: volume-6/volume-7)
# blunt alternative if the above is tedious: volume.mark -collection logs -writable

# 3c. reconcile each diverged replica pair — diff + heal the smaller copy from the larger:
volume.check.disk -v -apply -slow -volumeId 1982750 -nonRepairThreshold 0 -syncDeleted
… repeat for 1982649, 1982751, 1982752, 1982753, 1982754, 1982885, 1982886
# (per the wiki recipe for exactly this "chunk Not Found" symptom; -nonRepairThreshold 0 =
#  no tolerance for drift on a divergent pair; expect long runtime on 13–24M-entry indexes)

# 3d. replicas that are missing entirely / over-replicated:
volume.fix.replication -n        # dry run — will list the "not enough copies" volumes (1982360–82 etc.)
volume.fix.replication -apply    # adds the missing copy; removes stray misplaced ones

# 3e. husk volumes (8 B / 0 files — the "skip vacuuming" ones):
volume.deleteEmpty -quietFor=1h -apply      # (older docs: -force; current name -apply)

# 3f. drain the stuck delete backlog now instead of waiting for 03:29 vacuum cycles:
volume.vacuum -garbageThreshold=0.1

# 3g. stale S3 multipart cruft from interrupted writes (optional but recommended):
s3.clean.uploads
unlock
```

## Phase 4 — the known-lost Loki object + loop stop

1. Delete the unreadable object entry: admin UI → File Browser →
   `/buckets/logs/fake/681e07742c8440a8/1a1bb915381:1a1bb93f591:358a4ee9` → delete
   (or `fs.rm` in shell). It is already `NoSuchKey` for reads — losing it loses nothing new;
   it's the ~5 min log slice from 11-06 07:21–07:27 UTC.
2. Restart the s3 deployment (clears the in-process eternal retry): ArgoCD → `seaweedfs-s3`
   → hard refresh/restart pods, or `kubectl -n default rollout restart deploy seaweedfs-s3`
   (user-run; not a repo change).
3. Verify: `retry reading` gone from s3 logs; Loki shows no new `NoSuchKey`.

## Phase 5 — never accidentally EC again

- Phase 0 keeps admin detection off.
- `fs.configure` per-path replication/storage options (shell) let you pin the dynamic-CSI SCs to
  named collections (`collection` param on the four `seaweedfs-*` StorageClasses) so future
  volume.idle scans have nothing nameless to encode.
- Optional: since EC needs ≥15 servers for 10+4 with fault tolerance and this is one host,
  document that EC stays off until a multi-node/multi-rack layout exists.

## Rollback / risk notes

- `ec.decode` is non-destructive for recoverable groups (writes replicas, then drops shards).
- Phase 2 step 2 deletes data that is already mathematically unrecoverable; the paths come from
  fsck output — review `fs.meta.cat` before `fs.rm`.
- `volume.check.disk -apply` on 8 diverged pairs is the longest-running op (hours). Keep
  vacuum lane disabled until it finishes so admin doesn't race you.
- If a step behaves unexpectedly, `unlock` before exiting the shell to release the cluster lock.
