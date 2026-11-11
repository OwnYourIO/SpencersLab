# Plan — get off SeaweedFS EC + heal read-only/vacuum deadlock

Date: 2026-11-10 · Type: dep (decommission) · Evidence: `.agents/notes/2026-11-10-seaweedfs-incident-findings.md`

> **Corrections 2026-11-11 — weed 4.50 source-verified.** A research round against the exact
> deployed build (`ec8f97935`) corrected four things in this runbook; superseded lines are
> marked inline and cited §R1.x — evidence:
> `.agents/plans/2026/2026-11-feat-seaweedfs-debug-skill/RESEARCH.md` §R1, deploy state also
> that folder's `EXPLORE.md` §1.2.
> - Phase 1 decode: the pool is the UNNAMED one — `-collection=default` is a silent no-op
>   here — and a batch decode aborts on its first failing group, so decode per `-volumeId`
>   (§R1.4).
> - Phase 3 healing: `volume.check.disk` copies absent needles only with
>   `-resurrectMissingNeedles`, gated on each receiving replica's compaction revision —
>   simulate first, then branch on the printed verdict (§R1.1).
> - Phase 3 paste blocks: a heredoc feeds the command it is attached to — `| tee` comes last,
>   or `weed shell` receives no stdin (verified by experiment 2026-11-11).
> - Phase 0 deploy: no sync runs automatically — the Application has no `automated:` block —
>   a human `argocd app sync infra-seaweedfs` is the deployment step (§R1.6).

Operator: user (every step needs pod access; agents have no exec). Run shell commands from an
infra pod with the weed binary (e.g. `seaweedfs-master-0`) :
`weed shell -master seaweedfs-master-0.seaweedfs-master.default:9333 -filer seaweedfs-filer.default:8888`
(scriptable: `echo 'lock; …; unlock' | weed shell`).

Goal: EC is not wanted ("I don't use it"). Today: 10 EC groups in the UNNAMED collection
(`""` — the admin UI renders it as "default"; §R1.4),
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
# Phase 0 deploy state — the app has NO automated sync block, so this pair brackets the
# HUMAN `argocd app sync infra-seaweedfs` (no agent tier holds ArgoCD writes; §R1.6):
argocd app get infra-seaweedfs   # before: OutOfSync at main tip · after: Synced + Healthy
kubectl -n default get pod seaweedfs-admin-0 -o jsonpath='{.spec.containers[0].env}' \
  | grep -o WEED_MAINTENANCE_ERASURE_CODING_ENABLED   # empty pre-sync (pod from 10-25); present after
# repo render for the ingress typo fix (content is on main; re-render after the Phase-0 sync):
helm template infra services/infra/prod --set domain=spencerslab.com --set clusterName=infra \
  -s templates/generic-ingress.yaml | grep -A3 "name: \"seaweedfs-filer\""
```

## Phase 0 — stop the EC churn (owner directive 11-10: global maintenance stays ON)

The EC proposal loop runs in the **admin server** (`worker.enabled=false`, but the admin process
detects/schedules itself). Its `ec_balance` proposals can never be persisted: task IDs embed
`host:8080` and the ID sanitizer (`^[A-Za-z0-9_.-]+$`) rejects colons →
`Failed to save/delete task state ... invalid task ID` × ~8k/day.

1. **Merged to main as `4b832237c`** (the branch `dep/seaweedfs-disable-ec-maintenance` is a
   stale duplicate — its content is on main; EXPLORE §1.1) — `charts/seaweedfs/values.yaml`
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
3. Verify after the human sync (see *Deploy reality* below): admin-0 restarts and logs
   `Applied [maintenance.erasure_coding] settings from admin.toml`; no new *encode* proposals.
   The master's built-in 17-min maintenance script (which contains `ec.encode` — what EC'd these
   volumes originally) stays suppressed while admin is connected — check the master log once for
   `Skipping master maintenance scripts because admin server is connected`.

#### Deploy reality (2026-11-11): merged, NOT deployed — and nothing auto-syncs

The env-var change is **merged to main** (`4b832237c`) but **UNDEPLOYED**: `seaweedfs-admin-0`
has run since 2026-10-25 without it, and `infra-seaweedfs` sits OutOfSync at main tip. The
cause is operational, not technical (§R1.6, EXPLORE §1.2): the live Application has **no
`automated:` block at all** — automated sync is gated off for this cluster's charts-appset
apps by the `services.infra.selfHeal` cluster-annotation gate (which exact annotation key is
U1 — agents cannot read the cluster secret). No sync is failing; none is attempted.

**Phase 0 deploys when a human runs `argocd app sync infra-seaweedfs`** (UI or CLI — no agent
tier holds ArgoCD writes). No chart release bump is involved: the app sources the git path
(`charts/seaweedfs`) directly, so that sync renders the merged values.

The four `RepeatedResourceWarning`s (duplicate Services `seaweedfs-{filer,master,s3,volume}`)
do **not** block that sync: ArgoCD v3.5.6 dedupes same-name manifests LAST WINS, render order
makes the four wrapper templates
(`charts/seaweedfs/templates/seaweedfs-{master,s3,filer-http,volume-http}-service.yaml`) the
winners, and the 11-09 sync succeeded with the warnings present (§R1.6). The warning recurs on
every refresh until the duplicate-Service debt is fixed; the owner ruled that debt cosmetic at
approval (declined C06; follow-up only), so expect `RepeatedResourceWarning` in the conditions.

#### Post-sync verification checklist (Phase 0/5 acceptance — §R1.5/§R1.6)

1. `argocd app get infra-seaweedfs` (or an API read): Synced + Healthy, and
   `status.operationState.operation.sync.revisions` == the synced main tip with phase Succeeded
   — proves the manual sync actually ran.
2. `seaweedfs-admin-0` env contains `WEED_MAINTENANCE_ERASURE_CODING_ENABLED=false` (agents:
   read-only `pods_get` suffices) and the admin log shows
   `Applied [maintenance.erasure_coding] settings from admin.toml`.
3. EC churn stops (admin log via `kubectl -n default logs sts/seaweedfs-admin`, or Loki):
   NO new `placed with relaxed placement constraints`, `EC Detection: stopping early after
   10 consecutive placement failures`, or `Failed to save/delete task state for ec_balance_*:
   invalid task ID` lines after the restart. Loki caveat: a verification query THROUGH Loki
   reads index objects stored on SeaweedFS and can regenerate the very lines it measures
   (self-query noise) — rate fresh windows, never historical totals.
4. Loki: the s3 `retry reading` rate → 0 after Phase 4;
   `{cluster="monitoring", app_kubernetes_io_name="loki"} |~ "NoSuchKey"` steady, not growing.
5. Conditions: `RepeatedResourceWarning` may persist while the duplicate-Service debt stands —
   warning-only, never fails the sync; zero-conditions is acceptance only after a
   duplicate-Service fix (follow-up) lands.

## Phase 1 — decode the recoverable EC volumes

Recoverable = all 10 **data** shards present (parity optional): **1 (13/14), 440 (13/14),
441 (14/14), 448 (11/14), 461 (14/14)** decode directly **iff** their missing shards are
parity-only; a lost DATA shard needs the `ec.rebuild` pre-step below (per-group verdict,
§R1.4). `ec.decode` rebuilds a normal replicated volume from the shards, then deletes them
(≈29GB logical each; servers have 3–7TB free each).

**Target the UNNAMED pool, decode per volume (§R1.4):**

- `-collection=default` is a **silent no-op** on this cluster (prints `ec decode volumes: []`,
  exits 0): the shell matcher treats `default` as a *literal* collection name and this
  cluster's EC pool has **no name** — the admin UI merely RENDERS `""` as "default". Correct
  target: `-collection=""` ≡ sentinel `-collection=_default` ≡ omitting the flag.
- A batched decode **aborts on the first failing group** (ascending volume id: a bulk decode
  of all ten groups runs group 1, aborts at 4, and never reaches 440+). Decode per
  `-volumeId`.
- Group 448 shard-role pre-check — decode needs all 10 DATA shards (ids 0–9; parity optional).
  Read the missing shard ids from the admin EC page (`/storage/ec-shards`,
  `/storage/ec-volumes/448`) or the `volume.list` EC lines (probe U5 — instructed, never
  assumed). If a missing shard is a DATA shard, run `ec.rebuild -collection=_default -apply`
  first: the rebuild floor is any ≥10 of 14 (RS reconstruction) and 448's 11/14 clears it.

```
lock
ec.decode -collection="" -volumeId 1
ec.decode -collection="" -volumeId 440
ec.decode -collection="" -volumeId 441
ec.decode -collection="" -volumeId 448
ec.decode -collection="" -volumeId 461
volume.list
unlock
```
Expected: 441 and 461 decode cleanly (complete groups). 1 and 440 fail with
`data shards are missing and no decoded volume exists to finish` only when a DATA shard is
lost → `ec.rebuild` first, then decode. Groups 4, 5, 446, 447, 449 sit at ≤9/14 shards —
below the RS reconstruction floor, so unrecoverable (source-confirmed, not a heuristic); that
failure is the confirm-unrecoverable answer; leave them for Phase 2. Decoded groups' shards
are unmounted and deleted; a group with no live entries purges without creating a volume
(§R1.4).

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

   Collection discipline (§R1.4): `-volumeId` alone is collection-free; if you scope
   `-collection`, these five groups live in the UNNAMED pool — `-collection=_default` (or
   `""`). A literal name matches only itself. Cautionary note from 11-10: `volume.fsck` was
   run with `-collection media` instead of the right pool — `1982886` sits in `logs` — so it
   scanned nothing and reported nothing.
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
the full list is safe to paste even if most flags already cleared; `volume.list -readonly`
runs first in the block to confirm the live truth at paste time (§R1.5).

Probe U4 before trusting any mark you re-apply — grep the volume-server logs since the 11-10
restarts: `kubectl -n default logs seaweedfs-volume-2 | grep -F "idx references end="` (same
on seaweedfs-volume-3). An `.idx`-past-`.dat` mismatch re-marks read-only on EVERY restart —
`volume.mark -writable` does not survive the next one until the pair is consistent; 1982649's
surviving mark is either this re-detection or a persisted `.vif` flag (§R1.2).

Order matters: mark writable **before** `check.disk` (it answers `skipping readonly volume %d
on %s` for read-only replicas and touches none of them) and before `deleteEmpty` (source: it
silently skips read-only candidates). Keep the vacuum lane disabled around the whole window
(`volume.vacuum.disable` in the block below; `volume.vacuum.enable` in the cleanup pass):
vacuuming a diverged pair drops tombstones per-replica, bumps the compacted replica's
compaction revision — closing the resurrection gate forever — and lets reads return deleted
data on the replica that missed the delete; heal or canonicalize BEFORE vacuum (§R1.1).

Run in a tmux/screen — the simulate pass over 13–24k-entry indexes takes hours.

### Step 1 — mark + simulate (pasteable; changes nothing)

A heredoc body feeds the command it is attached to — `| tee` must come LAST in the pipeline,
or the body feeds `tee`'s stdin and `weed shell` executes nothing (verified by experiment
2026-11-11).

```bash
kubectl -n default exec -i seaweedfs-master-0 -c seaweedfs -- \
  weed shell -master=localhost:9333 -filer=seaweedfs-filer-client.default:8888 \
  2>&1 <<'EOF' | tee /tmp/sw_heal_$(date +%Y%m%d_%H%M).log
lock
volume.vacuum.disable
volume.list -readonly
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
volume.check.disk -v -slow -volumeId 1982649 -nonRepairThreshold 1 -resurrectMissingNeedles
volume.check.disk -v -slow -volumeId 1982750 -nonRepairThreshold 1 -resurrectMissingNeedles
volume.check.disk -v -slow -volumeId 1982751 -nonRepairThreshold 1 -resurrectMissingNeedles
volume.check.disk -v -slow -volumeId 1982752 -nonRepairThreshold 1 -resurrectMissingNeedles
volume.check.disk -v -slow -volumeId 1982753 -nonRepairThreshold 1 -resurrectMissingNeedles
volume.check.disk -v -slow -volumeId 1982754 -nonRepairThreshold 1 -resurrectMissingNeedles
volume.check.disk -v -slow -volumeId 1982885 -nonRepairThreshold 1 -resurrectMissingNeedles
volume.check.disk -v -slow -volumeId 1982886 -nonRepairThreshold 1 -resurrectMissingNeedles
unlock
EOF
```

The simulate pass (no `-apply`) rewrites nothing but prints each pair's divergence verdict
and both replicas' compaction revision — that is probe U2's answer. Read the tee'd log per
volume before any repair runs.

### Step 2 — per pair, branch on its verdict (§R1.1, §R1.7 Q1a)

- **TWO-SIDED, both replicas at revision 0 (rev-0, never vacuumed):** the verdict prints a
  mutual-missed-writes diagnosis — re-run the pair's line with `-apply`:

  ```
  volume.check.disk -v -apply -slow -volumeId <vid> -nonRepairThreshold 1 -resurrectMissingNeedles -syncDeleted
  ```

  Mutual in-place resurrection in both directions — the documented recovery for exactly this
  shape. Without `-resurrectMissingNeedles`, an apply pass cannot copy absent needles: it
  re-diagnoses and changes nothing (§R1.1).
- **TWO-SIDED otherwise:** the auto-refusal ("Do NOT auto-repair: each side may hold data the
  other lacks") is **correct behavior**, not a failure to force past. Classify each side's
  unique live needles first:

  ```
  volume.fsck -collection logs -volumeId <vid> -findMissingChunksInFiler -v
  ```

  (hours per volume; `-v` for progress; `-collection logs` because these volumes sit in the
  `logs` pool — the name must match literally, see Phase 2's discipline). Then:
  - one side's uniques are all orphans (no filer reference) → whole-volume re-copy from the
    complete side: `volume.copy -source <complete server> -target <lagging server> -volumeId
    <vid>` — replaces the target's content and freezes the source read-only (non-persistent).
  - both sides hold filer-referenced uniques → **no automated union exists in 4.50** —
    manual needle-level restore, or an accepted partial loss.
  - NEVER blind-copy the larger side over the smaller: 1982885's minority side holds ~20
    unique live needles that may be the only copy (replication `001` = exactly 2 copies, one
    host).
- **ONE-SIDED** (lagging side holds no unique live needles): whole-volume `volume.copy` ONLY
  when the lagging side is proven never-vacuumed (rev-0 under the flag); otherwise restore
  the confirmed-missing needles per the verdict text — a re-copy would resurrect deletions
  already vacuumed away on that side.

### Step 3 — cleanup pass (after every pair is healed or canonicalized)

```bash
kubectl -n default exec -i seaweedfs-master-0 -c seaweedfs -- \
  weed shell -master=localhost:9333 -filer=seaweedfs-filer-client.default:8888 \
  2>&1 <<'EOF' | tee /tmp/sw_clean_$(date +%Y%m%d_%H%M).log
lock
volume.vacuum.enable
volume.fix.replication -n
volume.fix.replication -apply
volume.deleteEmpty -quietFor=24h -apply
volume.vacuum -garbageThreshold=0.1
s3.clean.uploads -timeAgo=24h
unlock
EOF
```

Notes on the flag choices (all source-verified against weed 4.50; §R1.11):
- `-nonRepairThreshold 1`: default is **0.3**, and these pairs diverge up to 46%
  (1982751: 13,385 vs 24,685) — repair would be *refused* at the default. `1` = no cap. Keep.
- `volume.check.disk` reconciles **replicated** volumes only — logs pair count = 2 locations
  with rep `001` → treated as replicated ✓. Its two repair classes (§R1.1): needles live on
  one replica but absent on the other are copied only with `-resurrectMissingNeedles`, and
  only into a receiving replica at compaction revision 0 — a never-vacuumed index still holds
  the tombstone that proves "missing write" instead of "deleted"; delete marks propagate only
  with `-syncDeleted`.
- **Never use `-fixReadOnly` on these pairs:** EXPERIMENTAL and uni-directional — the source
  is a random writable replica and the read-only side's unique needles are never propagated
  back; on a split-brain pair it destroys data (§R1.2).
- `volume.deleteEmpty -quietFor=24h -apply` (`-force` is a deprecated alias): skips
  read-only + remote-backed volumes by design — which is why the marks above must succeed
  first. The 8 B/0-file husks on 1982360–1982382 etc. qualify (untouched > 24 h).
- `volume.fix.replication -n` output goes into the tee'd log — skim it before the `-apply`
  line runs; drop the `-n` pair if you want full dry-run first passes. It re-adds MISSING
  replicas by copying the most-recently-modified survivor — it never merges diverged content
  (§R1.1).
- If the pipe breaks mid-run, the cluster stays locked: re-run with `lock` replaced by
  nothing, or `echo "unlock" | weed shell …` first.

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

The `-collection logs` above follows the corrected Phase 3 discipline: fsck's `-collection`
must name the volume's pool literally (this example already did).

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
- The per-pair `volume.check.disk` repair runs are the longest op (hours). Keep the vacuum
  lane disabled until every pair is healed or canonicalized: compaction bumps the revision
  and closes the rev-0 resurrection gate forever (§R1.1).
- If a step behaves unexpectedly, `unlock` before exiting the shell to release the cluster lock.
