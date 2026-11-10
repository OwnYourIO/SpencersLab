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
# lost Loki object: entry presence check (no shell needed):
curl -sk "https://seaweedfs-admin.infra.spencerslab.com/api/files/properties?path=%2Fbuckets%2Flogs%2Ffake%2F681e07742c8440a8%2F1a1bb915381%3A1a1bb93f591%3A358a4ee9"
#   {"error":"...filer: no entry is found in filer store"} → entry gone (11-10 verified)
# admin: EC proposals suppressed (exact lines from config_toml.go / master source):
kubectl -n default logs sts/seaweedfs-admin | grep -E "Applied \[maintenance.erasure_coding\] settings from admin.toml"
kubectl -n default logs sts/seaweedfs-master-0 | grep "Skipping master maintenance scripts because admin server is connected"
# repo render for the ingress typo fix (already on fix branch):
helm template infra services/infra/prod --set domain=spencerslab.com --set clusterName=infra \
  -s templates/generic-ingress.yaml | grep -A3 "name: \"seaweedfs-filer\""
```

## Phase 0 — stop the EC churn (owner directive 11-10: global maintenance stays ON)

The EC proposal loop runs in the **admin server** (`worker.enabled=false`, but the admin process
detects/schedules itself). Its `ec_balance` proposals can never be persisted: task IDs embed
`host:8080` and the ID sanitizer (`^[A-Za-z0-9_.-]+$`) rejects colons →
`Failed to save/delete task state ... invalid task ID` × ~8k/day.

1. **Merged on branch `dep/seaweedfs-disable-ec-maintenance`** — `charts/seaweedfs/values.yaml`
   `admin.extraEnvironmentVars`:
   ```yaml
   WEED_MAINTENANCE_ERASURE_CODING_ENABLED: "false"   # [maintenance.erasure_coding] enabled
   ```
   Verified against `weed/admin/dash/config_toml.go` + `weed/command/scaffold/admin.toml`.
   `WEED_MAINTENANCE_ENABLED` is deliberately **not set** — the maintenance system stays on, so
   auto-vacuum keeps draining the delete backlog.
2. Residual `ec_balance` log noise: `ec_balance` has **no** admin.toml/env key of its own (the
   overlay covers only `vacuum` / `balance` / `erasure_coding`), so it keeps re-proposing the
   existing EC groups. Nothing executes (no worker; the proposals can't even persist) — it is
   log-only churn that **dies out automatically once Phases 1–2 remove every EC group**. If you
   want it silent in the meantime, the toggle exists only in the admin UI (persisted to the
   `/data` PVC): `/plugin` → EC Shard Balance → Enabled off (one-time action, survives restarts).
3. Verify after ArgoCD sync: admin-0 restarts and logs
   `Applied [maintenance.erasure_coding] settings from admin.toml`; no new *encode* proposals.
   The master's built-in 17-min maintenance script (which contains `ec.encode` — what EC'd these
   volumes originally) stays suppressed while admin is connected — check the master log once for
   `Skipping master maintenance scripts because admin server is connected`.

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
Expected: the five groups above decode OK; groups 4, 5, 446, 447, 449 fail — with fewer than
the 10 data shards that 10+4 needs to reconstruct, decode is mathematically impossible, and
that failure is the confirm-unrecoverable answer; leave them for Phase 2.

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

Re-verified 11-10 14:25 UTC after the node reboot: only **1982649 is still read-only** (the
other flags cleared with the volume-server restarts; filer delete retries are back to zero),
and the holder map below is the current one. The `volume.mark` lines are all idempotent, so
the full list is safe to paste even if most flags already cleared.

Order matters: mark writable **before** `check.disk` (it skips read-only replicas unless you
pass the experimental `-fixReadOnly`) and before `deleteEmpty` (source: it silently skips
read-only candidates). Paste as one block; run in a tmux/screen — the check.disk pass takes
hours on 13–24k-entry indexes:

```bash
kubectl -n default exec -i seaweedfs-master-0 -c seaweedfs -- \
  weed shell -master=localhost:9333 -filer=seaweedfs-filer-client.default:8888 \
  2>&1 | tee /tmp/sw_heal_$(date +%Y%m%d_%H%M).log <<'EOF'
lock
volume.mark -node seaweedfs-volume-2.seaweedfs-volume.default:8080 -volumeId 1982649 -writable
volume.mark -node seaweedfs-volume-3.seaweedfs-volume.default:8080 -volumeId 1982649 -writable
volume.mark -node seaweedfs-volume-1.seaweedfs-volume.default:8080 -volumeId 1982750 -writable
volume.mark -node seaweedfs-volume-4.seaweedfs-volume.default:8080 -volumeId 1982750 -writable
volume.mark -node seaweedfs-volume-1.seaweedfs-volume.default:8080 -volumeId 1982751 -writable
volume.mark -node seaweedfs-volume-4.seaweedfs-volume.default:8080 -volumeId 1982751 -writable
volume.mark -node seaweedfs-volume-1.seaweedfs-volume.default:8080 -volumeId 1982752 -writable
volume.mark -node seaweedfs-volume-4.seaweedfs-volume.default:8080 -volumeId 1982752 -writable
volume.mark -node seaweedfs-volume-1.seaweedfs-volume.default:8080 -volumeId 1982753 -writable
volume.mark -node seaweedfs-volume-4.seaweedfs-volume.default:8080 -volumeId 1982753 -writable
volume.mark -node seaweedfs-volume-1.seaweedfs-volume.default:8080 -volumeId 1982754 -writable
volume.mark -node seaweedfs-volume-4.seaweedfs-volume.default:8080 -volumeId 1982754 -writable
volume.mark -node seaweedfs-volume-2.seaweedfs-volume.default:8080 -volumeId 1982885 -writable
volume.mark -node seaweedfs-volume-3.seaweedfs-volume.default:8080 -volumeId 1982885 -writable
volume.mark -node seaweedfs-volume-2.seaweedfs-volume.default:8080 -volumeId 1982886 -writable
volume.mark -node seaweedfs-volume-3.seaweedfs-volume.default:8080 -volumeId 1982886 -writable
volume.mark -node seaweedfs-volume-3.seaweedfs-volume.default:8080 -volumeId 10 -writable
volume.mark -node seaweedfs-volume-6.seaweedfs-volume.default:8080 -volumeId 10 -writable
volume.check.disk -v -apply -slow -volumeId 1982649 -nonRepairThreshold 1 -syncDeleted
volume.check.disk -v -apply -slow -volumeId 1982750 -nonRepairThreshold 1 -syncDeleted
volume.check.disk -v -apply -slow -volumeId 1982751 -nonRepairThreshold 1 -syncDeleted
volume.check.disk -v -apply -slow -volumeId 1982752 -nonRepairThreshold 1 -syncDeleted
volume.check.disk -v -apply -slow -volumeId 1982753 -nonRepairThreshold 1 -syncDeleted
volume.check.disk -v -apply -slow -volumeId 1982754 -nonRepairThreshold 1 -syncDeleted
volume.check.disk -v -apply -slow -volumeId 1982885 -nonRepairThreshold 1 -syncDeleted
volume.check.disk -v -apply -slow -volumeId 1982886 -nonRepairThreshold 1 -syncDeleted
volume.fix.replication -n
volume.fix.replication -apply
volume.deleteEmpty -quietFor=24h -apply
volume.vacuum -garbageThreshold=0.1
s3.clean.uploads -timeAgo=24h
unlock
EOF
```

Notes on the flag choices (all source-verified against weed 4.50/master):
- `-nonRepairThreshold 1`: default is **0.3**, and these pairs diverge up to 46%
  (1982751: 13,385 vs 24,685) — repair would be *refused* at the default. `1` = no cap.
- `volume.check.disk` only reconciles **replicated** volumes; logs pair count = 2 locations
  with rep `001` → treated as replicated ✓. It appends entries present in one replica and
  missing in the other (mutual heal), and `-syncDeleted` also syncs delete marks.
- `volume.deleteEmpty -quietFor=24h -apply` (`-force` is a deprecated alias): skips
  read-only + remote-backed volumes by design — which is why the marks above must succeed
  first. The 8 B/0-file husks on 1982360–1982382 etc. qualify (untouched > 24 h).
- If the pipe breaks mid-run, the cluster stays locked: re-run with `lock` replaced by
  nothing, or `echo "unlock" | weed shell …` first.
- `volume.fix.replication -n` output goes into the tee'd log — skim it before the `-apply`
  line runs; drop the `-n` pair if you want full dry-run first passes.

## Phase 4 — the ONE bad file: a live Loki TSDB index object (located definitively)

**Updated 11-10 ~15:30 UTC — the retry loop's carrier is now named, with the old "entry is
gone" understanding corrected.** Two distinct casualties of the 11-08 crash window:

1. **Gone (already cleaned):** chunk group `logs/fake/681e07742c8440a8/1a1bb915381:…:358a4ee9`
   — its filer entry no longer exists (`no entry is found in filer store`); it returns
   `NoSuchKey` fast. Nothing to delete; ~5 min of Nov 6 07:21–07:27 logs lost.
2. **LIVE bad file (delete this):**
   ```
   /buckets/logs/index/loki_index_20765/fake/1794147797505872010-compactor-1794085698030-1794147325922-a373bee8.tsdb.gz
   ```
   Evidence: the s3 gateway's stuck retry targets `1982649,ffcb4cee151f1745a60afc08`
   (ModifiedTsNs 2026-11-08 14:23:17); this object's filer entry **exists**, is exactly one
   64,836-byte chunk, and that chunk's file_id **is the lost fid** (via
   `/api/files/properties`). 7-day sweep of `failed to stream logs/index`: this key 251×, the
   only persistent offender (one `loki_index_20749` hit = transient). This is why the loop
   "respawned" after the s3 restart at ~13:00: every Loki query touching table
   `loki_index_20765` (Nov 8) GETs this index file, the gateway blocks retrying the dead
   chunk, the querier times out and re-issues. It is also why `fs.ls` in `fake/<streamhash>/`
   never showed anything: the carrier is under `index/`, not `fake/`.

**Delete it (pasteable):**

```bash
kubectl -n default exec -i seaweedfs-master-0 -c seaweedfs -- \
  weed shell -master=localhost:9333 -filer=seaweedfs-filer-client.default:8888 <<'EOF'
lock
fs.meta.cat /buckets/logs/index/loki_index_20765/fake/1794147797505872010-compactor-1794085698030-1794147325922-a373bee8.tsdb.gz
fs.rm /buckets/logs/index/loki_index_20765/fake/1794147797505872010-compactor-1794085698030-1794147325922-a373bee8.tsdb.gz
unlock
EOF
kubectl -n default rollout restart deploy seaweedfs-s3
sleep 120 && kubectl -n default logs deploy/seaweedfs-s3 | grep -c "retry reading"
```

`fs.meta.cat` first prints the chunk list so you confirm the fid before deleting (it also
proves the object is one chunk = nothing else shares it). Impact: the index slice it carries
(window ≈ 11-07 21:08 → 11-08 14:15) is already unreadable-by-hang, so queryability of that
window does not decrease — after deletion, queries covering Nov 8 return results minus that
window instead of stalling on it; the underlying chunk data stays on disk (index entry lost,
data orphaned — reclaimable only by full chunk-scan tooling, not worth it).

**Why the earlier `volume.fsck` attempt "didn't do anything" (for the record):** source shows
the reverse mode's progress lines (`checking directory …`, `find missing file chunks in …`)
are `-v`-gated and the **first finding can only print after it has collected set A from the
volumes AND walked the entire filer** (`collectFilerFileIdAndPaths` traverses from `/` — every
bucket, 43M+ media chunk references). Without `-v` it is a silent, hours-long job; it would
*have* eventually reported this index object. Skipped here because targeted proof was already
in hand; run an overnight `-v` pass if you want the belt-and-braces sweep:

```bash
echo 'lock
volume.fsck -findMissingChunksInFiler -verifyNeedles -collection logs -volumeId 1982649 -v
unlock' | kubectl -n default exec -i seaweedfs-master-0 -c seaweedfs -- \
  weed shell -master=localhost:9333 -filer=seaweedfs-filer-client.default:8888 2>&1 | tee /tmp/fsck_1982649.log
```

Also cleared from the to-do list: no stale multipart uploads exist (`/buckets/logs/.uploads`
and `/.uploads` return "no entry is found"), so `s3.clean.uploads` is optional hygiene only.
The read-only flags are mostly self-cleared by the 11-10 restarts too — only `1982649` still
logs `is read only` (2× since reboot), so trim the Phase 3 mark list to that volume unless
`volume.list` shows otherwise.

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
