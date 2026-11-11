# RESEARCH — feat-seaweedfs-debug-skill

Deep-research summary for ticket `2026-11-feat-seaweedfs-debug-skill`. One section per
research round (R1, R2, …); sections are append-only, never rewrite earlier ones.

---

## R1 — repair procedures + ArgoCD sync block

By `agent-research`, 2026-11-11. Method: the deployed weed build is the authority — cloned
`github.com/seaweedfs/seaweedfs` at tag `4.50` (commit `ec8f9793502c59ce3381cc4151bfc0806afd92e8`,
byte-identical to the deployed `weed v4.50 ec8f97935`, verified against
raw.githubusercontent.com), plus ArgoCD source at `v3.5.6` (the live cluster's version, read
from the `argocd-application-controller-0` pod label `app.kubernetes.io/version=v3.5.6`), the
SeaweedFS wiki, repo files in this worktree, and read-only live probes
(`readonly-infra-kubernetes`). Live evidence wins over docs where they conflict; conflicts are
flagged inline and in §R1.8.

### R1.0 TL;DR

1. The runbook's Phase 3 `volume.check.disk` line is missing `-resurrectMissingNeedles`; without it,
   needles that are live on one replica and **absent** on the other are never copied — the split-brain
   pairs get re-diagnosed, not healed. With the flag, healing is additionally gated on each receiving
   replica's **compaction revision == 0** (never vacuumed); otherwise 4.50 refuses and prescribes
   fsck orphan-verification before any re-copy.
2. Read-only marks come from five distinct sites; only some persist (`.vif`). `volume.mark -writable`
   clears both runtime flags and the `.vif` flag, but a load-time `.idx`-past-`.dat` mismatch will
   re-mark the volume read-only on every restart until the index/dat pair is actually fixed.
3. `ec.decode -collection=default` is a **silent no-op** here: shell commands match a collection
   literally named `default`, while this cluster's pool is the **unnamed** one (the admin UI renders
   `""` as "default"). The exact incantation is `ec.decode -collection=""` (or `-collection=_default`),
   and a batch decode **aborts on the first failing group** — decode per `-volumeId`. Decode requires
   all 10 *data* shards present (parity optional); a missing data shard needs `ec.rebuild` first
   (needs ≥10 of 14 shards — so 448 may be saveable, 4/5/446/447/449 are not).
4. The ArgoCD sync that should deploy Phase 0 is **not** blocked by the duplicate Services: ArgoCD
   v3.5.6 dedupes same-name manifests (last wins) and syncs anyway. It isn't running because the
   live `infra-seaweedfs` Application has **no `automated:` block at all** — automated sync is
   disabled for this cluster's charts-appset apps (the `services.infra.selfHeal` cluster-annotation
   gate). Phase 0 needs a manual `argocd app sync` (human/admin).
5. Fixing the duplicate-Service debt: the subchart offers no service-disable toggles, and
   resource-exclusions/ignoreDifferences cannot remove the warning; the clean fix is deleting the four
   wrapper templates (the subchart services are name-compatible) — but the live filer/s3 Services have
   allocated ClusterIPs, so switching them to the subchart's headless spec requires deleting those two
   Services first (clusterIP is immutable), or renaming the local ones instead.

### R1.1 Q1 — split-brain repair (diverged 2-replica pairs, both sides hold unique live needles)

**What check.disk does with the runbook's flags.** `checkWritableVolumes` sorts writable replicas by
file count and syncs pairs bidirectionally; read-only replicas are skipped with
`skipping readonly volume %d on %s` [S1:172-179] — so marking writable first is mandatory (runbook
order is correct). Inside `doVolumeCheckDisk` there are exactly two repair classes [S1:673-777]:

- **partiallyDeletedNeedles** — key deleted on source, still live on target → re-deleted on target,
  only with `-syncDeleted`.
- **missingNeedles** — key live on source, *entirely absent* on target → copied over **only when the
  resurrection gate passes**; otherwise counted into `skippedAbsentNeedles` and reported as
  `not resurrecting %d needle(s) absent on %s (cannot prove they are missing writes vs vacuumed deletes)`.

The split-brain pairs (1982649, 1982750-54, 1982885, 1982886) diverge exactly by live-needle
absence, so **without `-resurrectMissingNeedles` the runbook's
`volume.check.disk -apply -slow -volumeId <vid> -nonRepairThreshold 1 -syncDeleted` changes nothing
on them** — it re-runs the diagnosis and prints the verdict again. [CORRECTION to runbook Phase 3,
see §R1.8.]

**The resurrection gate.** `-resurrectMissingNeedles` copies absent needles back, but per-direction
only into a replica whose compaction revision is 0 [S1:46-53, 519-533]: `checkBoth` calls
`compactionRevision()`, which reads the live replica's `CompactionRevision` via the volume-server
`ReadVolumeFileStatus` gRPC [S1:350-362]. Rationale in-source: a never-vacuumed index still holds a
tombstone for every delete it processed, so a needle absent there is *provably* a missing write;
after any vacuum the tombstones of deleted entries are gone and absence is ambiguous.
`-nonRepairThreshold` bounds `len(missingNeedles)/sourceEntryCount` (default 0.3, refuses with
`failed to start repair ... percentage of missing keys is greater than the threshold` [S1:744-749]) —
the runbook's `-nonRepairThreshold 1` is right (1982751 diverges ~45%).

**Verdicts printed when nothing could be repaired** (`reportDivergenceVerdict` [S1:601-667]) — this
is the source of the messages observed live:

- ONE-SIDED (lagging side holds no unique live needles): recommends whole-volume re-copy
  `volume.copy -source <complete> -target <lagging> -volumeId <vid>` **only** when the lagging side
  is proven never-vacuumed under the flag; otherwise `Do NOT re-copy the whole volume: the absent
  needles may be valid deletions already vacuumed away on the lagging side, which a re-copy would
  resurrect. Restore only the confirmed-missing needles (volume.fsck ... -findMissingChunksInFiler,
  then needle-level repair)`.
- TWO-SIDED, both replicas proven never-vacuumed (rev 0 on both, flag set, bidi):
  `These are mutually missed writes, not split-brain: re-run this command with -apply to resurrect
  them in place (both directions).` — i.e. the documented automatic recovery for exactly this shape:
  simulate first (read the verdict), then re-run with `-apply`.
- TWO-SIDED otherwise: the observed `TWO-SIDED (split-brain) divergence — %s has %d unique live
  needle(s) AND %s has %d. Do NOT auto-repair: each side may hold data the other lacks. Confirm
  orphans with volume.fsck -collection <c> -volumeId %d -findMissingChunksInFiler before re-copying
  the complete replica, or restore the missing needles manually.` [S1:657-658]

**Copy-side procedure.** `volume.copy` exists in 4.50 [S3a]: it freezes the source read-only
(non-persistent), streams the whole volume to the target via the `VolumeCopy` gRPC, and the target
mounts the received copy [S3b:265-288, 353-365] — the target's previous content is replaced.
`volume.delete` removes a replica from one server; afterwards `volume.fix.replication -apply`
rebuilds the missing replica by copying from the survivors — source choice is
`PickOneReplicaToCopyFrom` = **most recently modified** replica [S17a:517-545, S17b:44-54]; with one
survivor it copies that one. fix.replication never merges diverged content; the wiki describes it as
fixing *missing* replicas ("If a volume is replicated and one replica is missing, the volume will be
marked as readonly ... volume.fix.replication will do exactly that") [S22].

**Risk for a pair like 1982885 (23-vs-20 unique live needles):** the smaller copy's 20 unique
needles may be the only copy of live filer-referenced files (replication `001` = exactly 2 copies;
both on one host). Re-copying the larger side over it destroys them → those files become unreadable.
The 4.50-prescribed procedure is: (1) run
`volume.fsck -collection logs -volumeId <vid> -findMissingChunksInFiler` and classify each side's
unique needles as filer-referenced (live data) vs orphans (unreferenced garbage); (2) if one side's
unique needles are all orphans, re-copy from the other side (accepting the orphan loss); (3) if both
sides hold referenced unique needles, the only union-preserving automated path is the rev-0
resurrection — if either side was ever vacuumed, 4.50 has no automated union and the choice is
manual needle-level restore vs accepting partial loss.

**Vacuum/compaction on a still-diverged pair (long term):** the automatic sweep skips read-only
replicas (`skipReadOnly` branch in `batchVacuumVolumeCheck`, exempting only disk-space-low ones
[S13a:60-72]); explicit `volume.vacuum -volumeId <vid>` compacts read-only volumes too [S15].
Compaction is per-replica: it physically drops tombstones on the compacted replica only, so
(a) delete marks that never reached the other replica become unsyncable forever (`-syncDeleted` only
propagates *partially-deleted* keys), (b) `CompactionRevision` increments and the resurrection gate
closes — the divergence hardens from "ambiguous" to "permanently unprovable", (c) reads routed to the
replica that missed a delete mark return the deleted file ("resurrection of deleted data"), and
(d) any further failed write propagation (e.g. the replica goes read-only again) grows the divergence.
Conclusion: diverged pairs should be healed (or deliberately reduced to one canonical copy) **before**
vacuum runs on them; the runbook's "keep vacuum lane disabled until check.disk finishes" note is
exactly this [runbook rollback notes].

### R1.2 Q2 — read-only semantics in 4.50

`Volume.ReadOnlyReasons()` is the single verdict: `noWriteOrDelete || noWriteCanDelete ||
diskSpaceLow` (with `ioUnavailable` folded into `noWriteOrDelete`) [S10a:581-595]. The five trigger
sites:

1. **Load-time structural check** (`LoadVolume`): if `.idx` references bytes past the end of `.dat`
   (a crashed batched write — this cluster's 11-08 failure mode), `v.noWriteOrDelete = true` with
   glog `volume %d: idx references end=%d but .dat is %d bytes; marking readonly` [S9:394-409].
   Runtime-only, but **re-detected on every load while the mismatch exists** — `volume.mark -writable`
   does not survive the next restart unless the index/dat pair is actually consistent.
2. **Disk space low**: `DiskLocation.CheckDiskSpace` periodically probes and stores `isDiskSpaceLow`
   when free space is below the configured minimum (chart sets `minFreeSpacePercent: 2`
   [charts/seaweedfs/values.yaml:149]) [S21:724-750]. Runtime-only; self-clears on the next probe
   once space recovers. The automatic vacuum sweep *does* compact disk-space-low read-only replicas
   ("the copy compaction exists for" [S13a:64-71]).
3. **IO-error quarantine**: sustained EIO (≥ `IoErrorTolerance`) quarantines the replica —
   `noWriteOrDelete = true`, stop announcing to master, sticky ("recovery is via MarkVolumeWritable")
   [S11c:535-565].
4. **Failed recovery / unavailable**: `markIoUnavailable` persists `ReadOnly=true` to `.vif` **and**
   writes a `.unavailable` marker file; `MarkVolumeWritable` refuses until the volume is verified and
   the marker removed manually [S10b:613-666, S11b:970-978].
5. **Operator mark**: `VolumeMarkReadonly` gRPC → `Store.MarkVolumeReadonly(i, canDelete, persist)`
   [S11a:924-968, S12].

**`readonlyCanDelete` semantics**: `-readonlyCanDelete` (or `CanDelete=true`) sets
`noWriteCanDelete` — new writes rejected, deletes still accepted ("so a volume holding expiring data
drains over time until it can be vacuumed away or merged ... with fs.mergeVolumes" [S2a:33-37]); the
idx is reopened for write so tombstones can append [S11a:936-941].

**Persistence**: `.vif` (volume info file). `PersistReadOnly(readOnly, canDelete)` updates
`volumeInfo.ReadOnly`/`ReadOnlyCanDelete` and calls `SaveVolumeInfo()` (crash-durable rename)
[S10c:668-698]. `volume.mark` always passes `persist=true` [S2b:117-133]; the transient freeze used by
`volume.copy` passes `Persist:false` [S3b:298-305]. So an operator mark **survives restarts**;
runtime causes (1, 2) do not persist as `.vif` writes (except the unavailable path).

**What `volume.mark -writable` / `VolumeMarkWritable` changes on disk** [S11b:970-1000, S12:403-421]:
refuses unavailable volumes; `reopenIdxForWrite()` (a volume booted read-only from `.vif` opened its
`.idx` O_RDONLY with a needle map that rejects Put — swapped to the writable form before flipping the
flag); clears `noWriteOrDelete`, sets `noWriteCanDelete=false`; `PersistReadOnly(false,false)` →
`.vif` rewritten with `ReadOnly=false`; then `notifyMasterVolumeReadonly(false)` so the master routes
writes there again. On-disk artifact = the `.vif` file.

**Self-heal?** No mechanism re-copies into an existing read-only replica: master stops assigning
writes to it, `volume.fix.replication` only adds replicas on servers that lack the volume entirely
(and never picks a read-only replica for deletion [S17b:84-95]), check.disk skips it without
`-fixReadOnly`. The disk-space-low form "self-clears" only because the probe re-evaluates. Everything
persisted needs explicit `volume.mark -writable` (the wiki's note that a missing-replica volume "will
be marked as readonly" and fix.replication marks the *id* writable applies to re-replication, not to
repairing an existing diverged replica [S22]). `-fixReadOnly` on check.disk is EXPERIMENTAL and
uni-directional (source = a random writable replica; the read-only side's unique needles are never
propagated back) [S1:258-329] — do **not** use it on the split-brain pairs.

The incident's "restart cleared most flags" is consistent with runtime-only causes (disk-space-low
and/or load-time checks whose mismatch the load path itself repaired via the leveldb index update);
1982649's surviving mark is either a persisted `.vif` flag or a still-present idx/dat mismatch
re-detected at load — distinguish by grepping the volume-server log for the
`idx references end=` line [S9:405-407] (see U4).

### R1.3 Q3 — vacuum / delete backlog

**Drain path after read-only marks are cleared:**

- Master **automatic sweep**: `StartRefreshWritableVolumes` runs `Vacuum(..., automatic=true)` every
  `vacuumIntervalSeconds` (default **840s = 14 min**, +0-120s jitter) on the leader master
  [S14:16-52], independent of the admin server connection (gated only by `volume.vacuum.disable` /
  plugin-disable, with a safety-net re-enable if admin disconnects [S14:35-41]). Default
  `garbageThreshold` 0.3; automatic mode skips read-only replicas except disk-space-low ones.
- **Explicit**: `volume.vacuum [-garbageThreshold=0.3] [-collection=...] [-volumeId=...]` — without
  `-volumeId` it is the same sweep (skips read-only); "Name a read-only volume with -volumeId to
  vacuum it anyway" [S15:25-41]. `_default` selects the unnamed collection here too.
- `volume.vacuum.disable` / `volume.vacuum.enable` exist [S15a] — use them around the hours-long
  check.disk window (runbook already does).
- **`vacuum.submit.all` / `delete.emptyVault` do not exist in 4.50** (no shell verbs, no master
  routes; master HTTP exposes only `/vol/vacuum`, which immediately runs a full sweep and returns dir
  status [S15b]). The empty-husk cleanup is `volume.deleteEmpty -quietFor=24h -apply`: candidate =
  non-remote, `(!ReadOnly || ReadOnlyCanDelete)`, size ≤ superblock **or** `FileCount>0 &&
  FileCount<=DeleteCount`, quiet for the period [S13b:475-545]. The automatic sweep deletes empties
  only when `vacuumDeleteEmptyAfterSeconds > 0` (default 0 = disabled) [S14a:99, weed/command/master.go:99].
- The incident's `skip vacuuming: not enough copies for volume:%d` is `enoughCopies(vid)` failing
  [S13c:444-456] — the husk volumes have fewer replicas than placement expects; cleared by
  `volume.fix.replication -apply` (re-adds replicas) or `volume.deleteEmpty` (deletes the husks).
  Note deleteEmpty skips read-only husks that are not `canDelete` [S13b:532-540] — marks first.

**`delete_count > file_count` on EC 461:** admin-dashboard aggregation warning, display-only:
for EC volumes the dashboard sums `delete_count` across shard holders but dedupes `file_count` via
max; when the summed tombstones exceed the deduped live count it logs
`ec volume %d in collection %q: summed delete_count=%d exceeds file_count=%d; skipping object count`
and excludes that volume from the collection's object total [S8c:2255-2293]. It is not fixed by
vacuuming regular volumes (EC shards are not vacuumed); it **resolves after `ec.decode`** — the group
becomes a regular volume whose tombstones then follow normal accounting and are reclaimable by
`volume.vacuum`. No other EC-side action needed for the anomaly itself.

### R1.4 Q4 — ec.decode on this cluster: unnamed vs "default", degraded groups

**The pool is the unnamed one (`Collection=""`).** Evidence chain: (1) the four dynamic-CSI
StorageClasses carry no `collection` parameter [services/infra/prod/templates/pvc-storage-classes.yaml,
per incident note lines 49-52]; (2) 4.50 has no defaultCollection concept at all (no
`DefaultCollection` identifier anywhere in filer/command source); (3) the admin UI **renders the
empty name as "default"** — `collection = "default"` substitutions in the dashboard stats,
collection management and volume pages, explicitly commented "Default collection for volumes without
explicit collection" [S8a:2215,2244; S8b:38,92; S8d:146], and `volume.list` prints `"" (default)`
[S19a:214-219]; (4) the admin EC page's own HTTP filter special-cases `filterCollection == "default"
&& volumeCollection == ""` [S8e:15-21] — i.e. when the EC page said `in collection "default"` it was
showing the unnamed pool.

**Shell commands do not share that alias.** All shell `-collection` flags go through
`wildcard.CompileCollectionMatcher`: `""`/`*` = every collection, `_default` sentinel = the
empty-named collection only, and a literal `default` matches **only a collection literally named
"default"** — the sentinel's comment says it exists precisely because `"_default" avoids colliding
with a collection literally named "default"` [S7:20-26, 55-90]. `volume.mark` help states
`Use -collection _default to target volumes that belong to no named collection` [S2a:30-37].

**ec.decode specifics:** its `-collection` help says "empty matches the collection with no name"
because `compileCollectionPattern("")` maps to the `_default` sentinel [S4a:66-79, S4b:146-156]. So:

- `ec.decode -collection=""` (flag omitted works too) → unnamed pool ✓ — **the exact incantation**.
- `ec.decode -collection=_default` → same ✓.
- `ec.decode -collection=default` → matches nothing here; it is a **silent no-op** (prints
  `ec decode volumes: []` and exits 0) [S4a:96-104]. [CORRECTION to the runbook's first guess; its
  `-collection=""` fallback is the right one.]
- Same discipline for `volume.fsck -collection _default`, `volume.vacuum -collection _default`,
  `volume.mark -collection _default` (fsck/vacuum additionally accept `""`/`*` = all [S16a:122]).

**Degraded groups:** `ec.decode` loops batches and **returns on the first error**
(`if err = ec.DoEcDecode(...); err != nil { return err }`) [S4a:105-122]. `DoEcDecode` fails a group
when a **data** shard is missing everywhere and no already-decoded volume exists:
`volume %d cannot be decoded: data shards are missing and no decoded volume exists to finish`
[S5a:46-59]. So a bulk decode over {1,4,5,440,441,446,447,448,449,461} decodes volume 1 and then
aborts at 4 (ascending id order). **Decode per group: `ec.decode -collection="" -volumeId <vid>`.**

**Shard requirements:** decode gates on `missingDataShard` — all 10 *data* shards (ids 0-9) present
somewhere; parity shards are optional ("Parity shards are not enough to answer this: the decode
rebuilds the volume from the data shards" [S5b:183-197]) and the reconstruction interleaves the data
shards only (`WriteDatFile`, `dataShards := len(shardFileNames)`, no RS recovery from parity on the
decode path [S5c:238-320]). A group missing a data shard must first run `ec.rebuild`, which uses RS
`Reconstruct` from any ≥10 of 14 shards (error: `not enough shards to rebuild ... need at least %d
(data shards)` [S6:355, 660-720]). Consequences for this cluster's groups: 441/461 complete, 1/440
(13/14) and 448 (11/14) decode directly **iff** their missing shards are parity-only — otherwise
`ec.rebuild -collection=_default -apply` first (448 has ≥10 shards, so rebuild is possible); groups
4/5/446/447/449 have ≤9/14 shards → below the RS floor → unrecoverable, confirmed by source (not
just by the "≥10/14" heuristic). Bonus: if an EC index has no live entries, decode purges the shards
without creating a volume (`EcNoLiveEntriesSubstring` path [S5a:96-106]) — husk groups vanish cleanly.

### R1.5 Q5 — verdicts + verification probes per step

| Step | Cheap read-only verification | "Clean" looks like |
|---|---|---|
| Split-brain healed (per pair) | `volume.check.disk -slow -volumeId <vid>` (no `-apply`) | both directions print `volume <vid> <server> has N entries, <other> missed 0 and partially deleted 0 entries` [S1:723-724] and **no** verdict/`not resurrecting` lines; `volume.list` file counts of the pair equal |
| Read-only cleared | `volume.list -readonly` [S19b:58,319-322] | no volume lines at all; no new `volume %d is read only` in filer/s3 logs [S11d:871,888; volume_write.go:185] |
| Delete backlog drained | `volume.list` per-volume stats line `total size:%d file_count:%d deleted_file:%d deleted_bytes:%d` [S19c:454-457]; filer logs | `deleted_file:0` on the healed volumes; zero new `max retry attempts (10) reached` lines (`MaxRetryAttempts = 10`, after which entries are dropped from the retry queue and the durable deletion ledger [S18:25,229-262]) |
| Husks gone | `volume.list`; master log | no 8-byte/0-file volumes; no `skip vacuuming: not enough copies` [S13c:454] |
| EC group decoded | `ec.decode` output; `volume.list`; admin EC page | `ec volume <vid> shard locations` + unmount/delete lines, no error; a normal volume with the same vid present; admin `/storage/ec-shards` → "No EC volumes" when all done (runbook's own check) |
| 461 anomaly gone | admin log | no new `summed delete_count=... exceeds file_count=...` [S8c:2288] |
| Phase 0 live | `pods_get(seaweedfs-admin-0)` env; admin log | env contains `WEED_MAINTENANCE_ERASURE_CODING_ENABLED=false`; log line `Applied [maintenance.erasure_coding] settings from admin.toml`; no new EC-churn lines (`placed with relaxed placement`, `EC Detection: stopping early`, `Failed to save/delete task state`) |
| ArgoCD unblocked | Application status | `Synced`+`Healthy`, zero conditions, `operationState` revision == main tip (§R1.6 acceptance) |

There is no Prometheus metric for the filer deletion retry queue (source check: none in
`weed/filer/filer_deletion.go`) — the log-based probes above are the designed surfaces.

### R1.6 Q6 — ArgoCD sync block (repo + live + source verified)

**Live state (probed 2026-11-11, ArgoCD v3.5.6 in ns `default`):**
`infra-seaweedfs`: Sync=OutOfSync, Health=Healthy; `status.sync.comparedTo` = main tip
`a6e493b78`; last `operationState` = Succeeded at **2026-11-09T15:35:16Z on `c8d5effb2`** — i.e. no
sync operation has even been attempted since the 11-10 change landed. Conditions: the four recurring
`RepeatedResourceWarning`s (`Resource /Service/default/seaweedfs-{filer,master,s3,volume} appeared 2
times among application resources`). `spec.syncPolicy` = **syncOptions only**
(`CreateNamespace=true`, `ServerSideApply=false`, `RespectIgnoreDifferences=true`) — **no `automated`
block**. [S30]

**Root cause of the stuck sync — not the duplicates.** In v3.5.6 `autoSync` returns at its first
gate when `!app.Spec.SyncPolicy.IsAutomatedSyncEnabled()` [S25:2424-2426]. Spot-checked
`infra-forgejo`: same shape (no `automated`). The appset template renders `automated: {prune,
selfHeal}` only when the cluster annotation resolves "true":
`charts/base/templates/appset-charts.yaml:124-138` reads `services.<svc>.selfHeal` /
`services.<svc>.<app>.selfHeal` from the cluster metadata annotations (clusters generator), default
"true" — the live apps lacking the block means the infra cluster's annotation resolves non-"true"
(most likely `services.infra.selfHeal="false"`; the cluster secret itself is unreadable by agents —
the readonly MCP SA cannot list secrets). The live ApplicationSet `infra-charts-appset` does carry
the current gate text, so this is annotation state, not a stale appset. Consequence: **every
infra charts-appset app syncs manually only**; the umbrella `infra` app's OutOfSync is the same
condition, not seaweedfs collateral. [CORRECTION/refinement of EXPLORE Q1's "failing automated sync"
hypothesis and the runbook's "Verify after ArgoCD sync" assumption — the sync must be human-triggered.]

**What the duplicate Services actually do.** `CompareAppState` dedupes: `// Only keep the last target
object to avoid duplicate resources.` + the warning condition [S24:560-574]; the docs state the same
for multi-source duplicates: "the last source to produce the resource will take precedence. Argo CD
will produce a RepeatedResourceWarning in this case, but it will sync the resources" [S26]. The
11-09 sync succeeded with the duplicates present — live proof they don't block.

**Which duplicate wins, and the CSA residue.** Local render (`helm template` of `charts/seaweedfs`
with dependency `seaweedfs-4.50.0.tgz` from the official repo): subchart services render first, the
four wrapper templates render **after** → the wrapper manifests are the dedup winners [S31]. That
matches live: `seaweedfs-filer` and `seaweedfs-s3` are pure wrapper spec (ClusterIP with allocated
IPs, wrapper ports/selector, `kubectl.kubernetes.io/last-applied-configuration` = wrapper manifest).
But `seaweedfs-master` and `seaweedfs-volume` are **hybrids**: wrapper ports/selector plus subchart
residue — `clusterIP: None`, `publishNotReadyAddresses: true`, and stale `helm.sh/chart:
seaweedfs-4.0.393` labels. That residue is CSA 3-way-merge mechanics: fields a past sync applied
(from the then-winning subchart manifest) that neither the current last-applied nor desired manifest
mentions are never deleted. Two field-by-field differences matter: all four subchart services are
**headless** (`clusterIP: None`) with grpc ports (filer 18888, master 19333, volume 18080; s3 has no
18333), while the wrapper's are ClusterIP; and the subchart selectors add
`app.kubernetes.io/instance: infra-seaweedfs` (the pods carry it [S31]). The subchart StatefulSets
set `serviceName: seaweedfs-{filer,master,volume,admin}` — StatefulSet pod DNS needs those names to
stay headless (the master/volume residue currently provides that; filer pod DNS is not used by
anything in this repo). The subchart's separate `seaweedfs-filer-client` headless service (the
CSI/mount target, `WEED_CLUSTER_SW_FILER=seaweedfs-filer-client.default:8888`) is **not** part of
the collision — only the wrapper renders no service by that name.

**SSA vs CSA semantics (docs + source):** `ServerSideApply=false` → "By default, Argo CD executes
the kubectl apply operation" (CSA, 3-way merge via last-applied annotation) [S27a]; with
`ServerSideApply=true` ArgoCD uses `kubectl apply --server-side --force-conflicts` [S27b]. For **two
Applications** managing one resource the documented behavior is `SharedResourceWarning` plus silent
mutual overwrite (CSA); tracking-annotation takeover quirks are tracked upstream (issue #24150)
[S28]; `FailOnSharedResource=true` is the opt-in hard failure. The launch's hypothesized SSA error
`Validation error: ... already exists` is **not** a v3.5.6 behavior for this scenario (the string
appears nowhere in the argo-cd v3.5.6 or its gitops-engine sources); SSA's real failure modes are
immutable-field errors (e.g. `spec.clusterIP is immutable`) and admission validation. None of this
is live anyway: ServerSideApply=false, and the collision is **within one Application** (dedup path),
not between two. Also checked: `helm.sh/resource-policy: keep` is **not** set anywhere — not on the
live Application annotations, not in `charts/seaweedfs/templates/*`, not in the appset templates
[CORRECTION to the launch brief].

**Options, ranked:**

- **(a) Delete the four wrapper service templates — recommended for end-state cleanliness, with a
  surgery caveat.** The subchart services are name-compatible with every consumer: proxy subdomain
  entries (`seaweedfs-filer/-volume/-master`, `s3` → `seaweedfs-s3`) resolve to the same names;
  `seaweedfs-filer-client` and the headless governing services already come from the subchart; s3's
  lost 18333 grpc port is unused in this repo (grep: only the local template mentions it). Blockers:
  (1) `spec.clusterIP` is immutable — the live filer/s3 Services have allocated IPs and the subchart
  wants `None`, so the sync would fail on those two until the live Services are deleted first
  (`kubectl delete svc seaweedfs-filer seaweedfs-s3`, brief VIP gap, recreated headless on sync);
  master/volume are already headless-live and transition cleanly. (2) Verify proxy/traefik routing to
  headless backends for the filer UI and s3 subdomains after the switch (traefik routes via
  endpoints; expected fine, but it is a behavior change). (3) The hybrid residue (old chart labels,
  publishNotReadyAddresses) disappears only via delete-and-recreate for those objects too, or stays
  as harmless drift — under CSA it will not be cleaned otherwise.
- **(b) Rename the local services** (e.g. `seaweedfs-filer-http`) and point the proxy `service:`
  entries at the new names; subchart keeps the canonical names. No immutable-field surgery (new
  objects create cleanly), but two Service objects per component forever and four proxy-entry edits;
  public names that must survive either way: `seaweedfs-filer-client` (CSI/mount), the StatefulSet
  governing names (`seaweedfs-{master,volume,filer}` — keep headless), `seaweedfs-s3` (Loki/clients
  FQDN `seaweedfs-s3.default.svc.cluster.local:8333`), `seaweedfs-master` (WEED_CLUSTER_SW_MASTER).
- **(c) Exclude the subchart services via values — unavailable.** The official 4.50 chart has no
  per-service enable toggles; the service templates are gated only by component `.enabled`
  (filer/master/volume/s3 templates inspected in the 4.50.0 tarball) [S32].
- **(d) resource-exclusions / ignoreDifferences — does not fix it.** Exclusions apply **after**
  dedup in `CompareAppState` (NormalizeTargetObjects → dedup conditions appended → then
  `resFilter.IsExcludedResource` drops the deduped target [S24:744-771]), so the
  RepeatedResourceWarning persists and the exclusion merely removes the Services from ArgoCD
  management entirely (and `resource.exclusions` is global via argocd-cm, not per-app).
  ignoreDifferences only suppresses field-level diffs against live; it never touches in-manifest
  duplicates. Under CSA + keep-style thinking there is additionally nothing to "keep": no
  resource-policy annotation exists (§above).

**Acceptance test for the sync block (all must hold):**
1. `argocd app get infra-seaweedfs` (or API read): `Synced` + `Healthy`, zero conditions —
   specifically no `RepeatedResourceWarning` after a refresh cycle;
2. `status.operationState.operation.sync.revisions` == main tip (and phase Succeeded) — proving the
   manual sync ran;
3. `seaweedfs-admin-0` env contains `WEED_MAINTENANCE_ERASURE_CODING_ENABLED=false`
   (`pods_get`, read-only) and admin log shows `Applied [maintenance.erasure_coding] settings from
   admin.toml`;
4. EC churn stops: no new `placed with relaxed placement constraints`, `EC Detection: stopping early
   after 10 consecutive placement failures`, or `Failed to save/delete task state for ec_balance_*`
   lines on admin after its restart;
5. (if option a/b applied) all five consumer surfaces still resolve: filer UI subdomain, s3 endpoint
   (Loki query), master UI, CSI mounts (`/.csi/vac`), volume PUBLICURL ingress.

### R1.7 Verdict table (per question)

| # | Question | Verdict |
|---|---|---|
| Q1a | Documented recovery for two-sided divergence | `-resurrectMissingNeedles` + both replicas rev 0 → re-run with `-apply` (mutual in-place resurrection). Rev > 0 on either side → refused by design; fsck-verify orphans, then re-copy or manual restore |
| Q1b | Runbook Phase 3 as written | **Insufficient** — missing `-resurrectMissingNeedles`; repairs only delete-mark drift, re-diagnoses the split-brain |
| Q1c | `volume.copy` route for 1982885 | Only after fsck proves the smaller side's 20 unique needles are orphans; otherwise destroys live data (fix.replication rebuild copies the survivor, never merges) |
| Q1d | Vacuum on diverged pair | Hardens divergence (drops tombstones per-replica, bumps revision, resurrects deleted reads on the wrong replica) — heal or canonicalize before vacuuming |
| Q2 | Read-only set/persist/clear | 5 trigger sites; `.vif` persistence for operator/unavailable marks; `volume.mark -writable` = runtime flags + `.vif` + master notify; no self-heal (disk-space-low form self-clears on probe); load-time idx>dat re-marks on every restart |
| Q3 | Backlog drain | Marks → `volume.vacuum -garbageThreshold=0.1` (or wait for 14-min master sweep); `volume.deleteEmpty -quietFor=24h -apply` for husks; `vacuum.submit.all`/`delete.emptyVault` **do not exist** in 4.50; 461 anomaly is admin display-only, resolves via ec.decode |
| Q4 | Collection identity + decode | Pool is unnamed; exact form `ec.decode -collection=""` (or `_default`); `-collection=default` is a silent no-op; batch decode aborts on first failing group → use `-volumeId`; decode needs all 10 data shards (parity optional), else `ec.rebuild` first (needs ≥10/14 — 448 maybe, 4/5/446/447/449 no) |
| Q5 | Probes | Table in §R1.5; log-based (no deletion-queue metric exists) |
| Q6 | Sync block | Automated sync is disabled cluster-wide for charts-appset apps (no `automated` block; selfHeal annotation gate) → manual sync required; duplicates are warning-only, wrapper templates win dedup; fix = (a) delete local templates + pre-delete filer/s3 Services (immutable clusterIP) or (b) rename local; (c) unavailable, (d) ineffective; no resource-policy:keep anywhere |

### R1.8 Contradictions and how they were weighed

1. **Runbook Phase 3 vs weed 4.50 source** — runbook assumes mutual append from `-apply
   -syncDeleted`; source shows absent-needle repair requires `-resurrectMissingNeedles` (and the
   rev-0 gate). Source wins (same build as deployed). The runbook's `-nonRepairThreshold 1` and
   mark-writable-first ordering remain correct.
2. **Runbook Phase 1 `-collection=default` first guess vs source** — `default` is a literal name in
   the shell matcher; the pool is unnamed. Source wins; the runbook's own fallback (`-collection=""`)
   is the correct form.
3. **EXPLORE Q1 "automated sync failing on repeated-resource warnings" vs live Application spec** —
   live spec has no `automated` block at all, and v3.5.6 source proves duplicates don't block sync
   (dedup + warning + the 11-09 sync succeeded). Live spec wins; the block is operational (manual
   sync), not technical.
4. **Launch brief "helm.sh/resource-policy: keep on infra-seaweedfs" vs repo + live** — the
   annotation exists nowhere (Application CR, chart templates, appset templates all checked).
   Dropped from the model.
5. **Launch brief selector claim ("instance=infra-seaweedfs + name/seaweedfs") vs repo templates** —
   the local selectors are `app.kubernetes.io/component + name` (no instance); the **subchart**
   selectors add `instance`. Minor, but matters for option (a)'s equivalence check.
6. **Note's "1982885 delta 23" vs launch's "23-vs-20 unique needles"** — different metrics (total
   file-count delta vs per-side unique live needles in the split-brain message). Both kept; the
   unique-needle counts are the repair-relevant ones.
7. **"Recoverable ≥10/14 shards" heuristic vs decode internals** — decode needs the 10 *data* shards
   specifically; parity-only losses decode fine, data-shard losses need `ec.rebuild` first. The note's
   verdicts still hold (unrecoverable groups max out at 9/14 < RS floor).

### R1.9 Implications for the plan

- Phase 0 deploy is a **human-triggered `argocd app sync infra-seaweedfs`** — plan it as an explicit
  operator step with the §R1.6 acceptance test; optionally raise re-enabling
  `services.infra.selfHeal` with the owner (separate decision, affects all infra apps).
- The new skill/runbook chunk must fix the Phase 3 check.disk line: add
  `-resurrectMissingNeedles`, run simulate-first per pair, and branch on the printed verdict
  (rev-0 both sides → `-apply`; split-brain message → fsck orphan-classification step before any
  re-copy). Include the `-fixReadOnly` warning (never on split-brain pairs).
- Phase 1 becomes **per-volume** `ec.decode -collection="" -volumeId <vid>` with an explicit
  "aborts on first failure" note; add an `ec.rebuild -collection=_default` pre-step for any group
  whose missing shards include data shards (verify shard ids from the admin EC page first).
- The ArgoCD duplicate-Service cleanup is a **separate chunk** from the ops runbook (repo-only:
  charts/seaweedfs/templates + possibly services/infra/prod/values.yaml), with option (a)'s
  delete-live-Services caveat or option (b) named explicitly; it is pre-existing debt (filer warning
  since 11-03), not a regression of this ticket.
- Skill prose should standardize on `_default` (with the `""` equivalence for ec.decode) and warn
  that the admin UI's "default" label is a display alias for the unnamed collection.

### R1.10 Unresolved (open questions)

- **U1** — which exact annotation disables automated sync (`services.infra.selfHeal` vs per-app):
  needs the ArgoCD cluster secret or the owner's word (agents cannot read secrets).
- **U2** — compaction revisions of the eight diverged logs volumes (decides resurrection path vs
  manual path): run simulate `volume.check.disk -slow -volumeId <vid> -resurrectMissingNeedles`
  per pair — the skip/verdict lines print each side's revision (human-run).
- **U3** — orphan vs filer-referenced classification of each pair's unique needles
  (`volume.fsck -collection logs -volumeId <vid> -findMissingChunksInFiler`, human-run, hours each).
- **U4** — is 1982649's surviving read-only a persisted `.vif` flag or a load-time idx>dat
  re-detection: grep seaweedfs-volume-{2,3} logs for `idx references end=` since the 11-10 restart.
- **U5** — group 448's missing shard ids (data vs parity) from the admin EC page — decides
  decode-direct vs rebuild-first.
- **U6** — live confirmation that the master/admin collection listing is the unnamed pool (the
  source chain is conclusive, but one curl of `https://seaweedfs-master.infra.spencerslab.com/` by
  the user closes it empirically; not reachable from this session).
- **U7** — umbrella `infra` app OutOfSync diff not inspected (presumed same manual-sync condition;
  confirm at the Phase 0 sync time).
- **U8** — `/status` churn and MCP endpoint surface belong to R2.

### R1.11 Sources

Weed 4.50 source (all at `raw.githubusercontent.com/seaweedfs/seaweedfs/4.50/<path>`, verified
byte-identical to the deployed build `ec8f97935`):

- [S1] `weed/shell/command_volume_check_disk.go` (flags 100-117; readonly skip 172-179; fixReadOnly
  pass 258-329; compactionRevision 350-362; checkBoth + resurrection gate 493-578; liveDivergence
  580-600; reportDivergenceVerdict 601-667; doVolumeCheckDisk 673-777)
- [S2] `weed/shell/command_volume_mark.go` ([S2a] help/readonlyCanDelete 25-37, -node/-volumeId
  requirement 81-93, persist=true 117-133), [S2b] same file collection mode
- [S3] `weed/shell/command_volume_copy.go` ([S3a]) and `weed/operation/volume_move/volume_move.go`
  ([S3b] CopyVolume 265-288, ensureVolumeReadonly 293-317, copyVolumeData 353-365)
- [S4] `weed/shell/command_ec_decode.go` ([S4a] flags 63-79, batch abort loop 105-122) and
  `weed/shell/command_ec_common.go` ([S4b] compileCollectionPattern/resolveEcCollections 146-175)
- [S5] `weed/ec/ec_decode.go` ([S5a] DoEcDecode 23-135, missingDataShard 183-197,
  regularVolumeHolder 200+), [S5b] same, [S5c] `weed/storage/erasure_coding/ec_decoder.go`
  (WriteDatFile/writeDatFile 238-320)
- [S6] `weed/storage/erasure_coding/ec_encoder.go` (rebuild floor error 355, Reconstruct loop 660-720)
- [S7] `weed/util/wildcard/collection_filter.go` (CollectionDefault sentinel 20-26, matcher 48-90,
  ExpandCollectionFilter 190-225)
- [S8] admin "default" alias: [S8a] `weed/admin/dash/admin_server.go:2215,2244`;
  [S8b] `weed/admin/dash/collection_management.go:38,92`; [S8c] aggregation warning
  `admin_server.go:2255-2293`; [S8d] `weed/admin/dash/volume_management.go:146`;
  [S8e] `weed/admin/dash/ec_shard_management.go:15-21`
- [S9] `weed/storage/volume_loading.go` (idx>dat read-only check 394-409)
- [S10] `weed/storage/volume.go` ([S10a] ReadOnlyReasons 581-595, [S10b] markIoUnavailable +
  persistUnavailable + restoreUnavailable 613-666, [S10c] PersistReadOnly 668-698)
- [S11] `weed/storage/store.go` ([S11a] MarkVolumeReadonly 924-968, [S11b] MarkVolumeWritable
  970-1000, [S11c] IO quarantine 535-565, [S11d] "volume %d is read only" 871,888)
- [S12] `weed/server/volume_grpc_admin.go` (VolumeMarkReadonly/Writable handlers 384-421,
  makeVolumeReadonly/Writable 281-340)
- [S13] `weed/topology/topology_vacuum.go` ([S13a] batchVacuumVolumeCheck skipReadOnly 34-100,
  [S13b] deleteEmptyVolumes + isEmptyVolumeDeleteCandidate 475-545, [S13c] vacuumOneVolumeId +
  "not enough copies" 444-456, Vacuum 256-302)
- [S14] `weed/topology/topology_event_handling.go` (auto sweep 16-52, [S14a] same);
  `weed/command/master.go` (vacuumIntervalSeconds=840, garbageThreshold=0.3,
  vacuumDeleteEmptyAfterSeconds=0 defaults, 97-102)
- [S15] `weed/shell/command_volume_vacuum.go` (help 25-41, flags), [S15a]
  `command_volume_vacuum_{disable,enable}.go`, [S15b] `weed/server/master_server.go:225` +
  `master_server_handlers_admin.go:51-67` (/vol/vacuum only)
- [S16] `weed/shell/command_volume_fsck.go` ([S16a] flags 119-135, filtered-volume exclusion note
  186-190)
- [S17] `weed/shell/command_volume_fix_replication.go` ([S17a] help 39-53,
  fixOneUnderReplicatedVolume 517-545), `weed/topology/balancer/replica_selection.go`
  ([S17b] PickOneReplicaToCopyFrom 44-54, PickOneReplicaToDelete 84-95)
- [S18] `weed/filer/filer_deletion.go` (MaxRetryAttempts=10 25, GetReadyItems expiry 229-262)
- [S19] `weed/shell/command_volume_list.go` ([S19a] `"" (default)` print 214-219, [S19b] -readonly
  flag 58 + isNotMatchDiskInfo 319-322, [S19c] statistics line 428-457)
- [S20] `weed/shell/command_volume_delete_empty.go`, `command_volume_delete.go` (existence verified
  in shell command listing)
- [S21] `weed/storage/disk_location.go` (CheckDiskSpace/isDiskSpaceLow 724-750)

Wiki: [S22] Volume Management — `github.com/seaweedfs/seaweedfs/wiki/Volume-Management` (admin
script defaults incl. `volume.deleteEmpty -quietFor=24h -apply` + `volume.fix.replication -apply` at
17 min; fix.replication semantics; 2026-10-19); [S23] Erasure Coding for warm storage —
`.../wiki/Erasure-Coding-for-warm-storage` (RS(10,4) tolerates any 4 missing shards; repair/decode
notes; 2026-10-24).

ArgoCD (source at tag `v3.5.6`, `raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/<path>`):
[S24] `controller/state.go` (dedupAppResources 540-577; exclusions after dedup 735-771; condition
re-stamp 1108-1114); [S25] `controller/appcontroller.go` (autoSync gates 2414-2562,
alreadyAttemptedSync 2568+); [S26] `docs/user-guide/multiple_sources.md:43-46`; [S27]
`docs/user-guide/sync-options.md` ([S27a] CSA default ~284, [S27b] SSA `--force-conflicts` ~296,
immutable-field troubleshooting); [S28] argo-cd issue #24150 (tracking annotation not overwritten
with multiple managing apps).

Repo + live: [S29] `charts/seaweedfs/{Chart.yaml,values.yaml,templates/*}`,
`charts/base/templates/appset-charts.yaml:124-143`, `services/infra/prod/values.yaml:35-91`,
`services/infra/prod/templates/{appset.yaml,seaweedfs-filer-*-grpc-service.yaml,pvc-storage-classes.yaml}`;
[S30] live probes via `readonly-infra-kubernetes` 2026-11-11 (Application infra-seaweedfs +
infra-forgejo syncPolicy/conditions/operationState; Services seaweedfs-{filer,master,s3,volume}
spec/labels/last-applied; ApplicationSet infra-charts-appset templatePatch; pod
argocd-application-controller-0 version label v3.5.6); [S31] local `helm template` render of
`charts/seaweedfs` + official `seaweedfs-4.50.0.tgz` (document order: subchart services doc#5-10,
wrapper services doc#11-14; StatefulSet serviceName fields; pod instance labels) — render artifacts
under `/tmp/opencode/research/`; [S32] official chart templates inspected from the 4.50.0 tarball +
`k8s/charts/seaweedfs/templates/` in the weed repo at tag 4.50 (no per-service enable toggles).
Incident evidence: `.agents/notes/2026-11-10-seaweedfs-incident-findings.md`,
`.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md` (both in `/home/coder/SpencersLab`), and this
ticket's `EXPLORE.md`.

---

## R2 — seaweedfs-mcp spec verification

By `agent-research`, 2026-11-11. Scope: verify the load-bearing UNVERIFIED items of the prior
seaweedfs-mcp implementation guide (FastMCP 4.1.1 / SeaweedFS 4.48 / ToolHive v1beta1; three
instances readonly/admin/onprem; plan→confirm_token→apply mutations; conditional tool registration;
per-volume unmount→`weed fix`→mount for onprem) against authoritative sources. Method: weed source
at tag `4.50` via raw.githubusercontent.com (tag ref == `ec8f9793502c59ce3381cc4151bfc0806afd92e8`,
commit "4.50" 2026-10-25T03:09:42Z — identical to the deployed build, re-verified via the GitHub
API [T20]); GitHub issues/PRs via the GitHub API; the SeaweedFS wiki; gofastmcp.com docs + PyPI;
docs.stacklok.com ToolHive docs; this repo's `containers/wekan-mcp`, `docker-build.yaml`,
`charts/hivetools`, `services/{dev,gpu,infra}/prod/values.yaml`; read-only live HTTP GET probes of
the infra cluster's master/admin/volume endpoints (~01:35 UTC); Loki metric queries via
`readonly-global-grafana`; CRD/pod reads via `readonly-infra-kubernetes`. No writes anywhere; the
only side-effecting risk (a client-disconnect log line from one truncated `head -c` read of
volume `/status`) is the benign RST mechanism documented in §R2.4. Source labels continue as
`[T#]` (R1 owns `[S#]`).

### R2.0 TL;DR

1. The guide's shell exit-code law, `weed fix` shape, `volume.unmount`, FastMCP visibility/era/
   stateless/custom_route/lifespan claims, and all four ToolHive v1beta1 CRDs **verify** against
   4.50 source, official docs, and the live cluster — with three corrections: master `/status`
   does not exist in 4.50 (use `/dir/status` + `/vol/status`), volume `/dir/config` does not
   exist, and FastMCP is at 4.1.8 (guide says 4.1.1; repo precedent pin is `>=4.1,<5`).
2. The TLS silent-fallback of issue #10502 is **still in the 4.50 binary** (five
   insecure-credentials fallback branches in `LoadClientTLS`); the issue was fixed chart-side
   (PR #11589). Since PR #11117 (merged 2026-09-03, in 4.50) the failure is loud at exit-code
   level: the reliable self-test is any piped shell command (`printf 'cluster.ps\n' | weed shell
   -master=… -debug` → exit 1 + `cannot connect to master … within 30s` when certs are missing
   and the endpoint enforces mTLS).
3. The ~1,709 `error writing JSON status /status` lines/hour are **benign kubelet-probe RST
   noise**, measured live right now at 1,569/h across the 8 volume pods (readiness probe polls
   `/status` every 15 s; the probe client closes with an unread body → server-side write fails →
   one glog line). `/status` itself answers in 20–50 ms — cheap to poll; the MCP just must read
   full bodies to avoid adding lines.
4. The best readonly-MCP surface is the admin server's **unauthenticated JSON API** (`/api/admin`
   16 KB cluster summary incl. EC totals, `/api/cluster/{topology,volumes,masters}`, `/api/config`,
   `/api/files/{properties,view,list-folders}`, `/health`, `/metrics`) plus master
   `/dir/status` (8.8 KB), `/vol/status` (1 MB, == `volume.list` detail fields),
   `/dir/lookup?volumeId=` (370 B) and `/collection/info` (137 B). Only `fsck`, `check.disk` and
   EC per-shard detail need a shell subprocess; EC shard detail has **no JSON HTTP endpoint** in
   4.50 (HTML scrape or shell only).
5. Repo precedent for the follow-up card is unambiguous: build in `containers/seaweedfs-mcp`
   (wekan-mcp Dockerfile/pyproject shape, CI tag law `:v<run>`+`:main`), deploy as
   `hivetools.mcp.<name>` ToolHive MCPServer entries in `services/infra/prod/values.yaml` (the
   wekan readonly/admin two-tier precedent; infra already runs ToolHive operator v0.56.0), and
   register in the machine-global `~/.config/opencode/opencode.json` (NOT this repo) + AGENTS.md
   table row. ToolHive's proxy is **unauthenticated by default** (docs, verbatim) and the lab's
   OIDC blocks are commented out — an exposed `seaweedfs-admin` tier would be world-drivable;
   the card must gate it.

### R2.1 Q1 — shell exit-code law in 4.50: VERIFIED

PR #11117 "shell: exit non-zero when a piped command fails" exists, merged **2026-09-03T05:12:52Z**
[GitHub API [T17]] — before tag 4.50 (2026-10-25), and the code is present at the tag [T1][T2][T3]:

- `weed/command/shell.go:75-79`: `if err := shell.RunShell(shellOptions); err != nil { …
  SetCommandExitStatus(1) }` with the in-source comment *"The command already printed the error; a
  piped run has to fail the script wrapping it too."* [T1]
- `weed/command/command.go:102-115`: `SetCommandExitStatus` records (highest wins), never calls
  `os.Exit` — *"Recorded, not os.Exit'ed, so the failure still travels through main's shutdown
  path"*; `weed/weed.go:106,205-207` applies it after deferred flushes [T2].
- `weed/shell/shell_liner.go:24-113`: doc comment *"Piped stdin returns the last command failure;
  an interactive session shows the error to the operator and keeps going."* The non-interactive
  branch tracks `lastErr` across all piped lines and returns it; **`lastErr` is sticky** — it is
  never cleared by a later success, so ANY failed command in a piped run exits 1. Unknown
  commands error too. Master-connect failure within `-connectTimeout` (default 30 s) returns
  `cannot connect to master %s within %s` → exit 1 [T3].
- Exit status is **1** (2 is reserved for usage/syntax errors); interactive sessions still exit 0
  after errors — the law is piped-mode-only [T1 PR body].
- PR provenance: split out of #11110 to land the two halves of issue #11106; motivation was a
  CronJob-piped `s3.lifecycle.run-shard` run that "reported green while the run aborted
  partway" [T17 body].

MCP consequence: admin/onprem shell verbs can be driven as `printf '<cmd>\n' | weed shell
-master=…` and trust the exit code; stderr carries `error: <detail>` per failed command
(`processEachCmd` prints it [T3]). Test method per the brief: cited from source + PR, no live
write-test performed.

**Extra gate the guide missed — the cluster shell lock.** Mutation verbs (`volume.unmount`
verified; the family that calls `confirmIsLocked`) fail with `need to run "lock" first to
continue` unless the session holds the cluster-wide exclusive admin-shell lock
(`weed/shell/commands.go:80-92`, `command_lock_unlock.go`: `lock` "in order to exclusively manage
the cluster … blocking operation if there is already another lock", holder queryable via master
`GetAdminLockStatus`) [T4][T5]. So a piped admin flow must be `lock\n<mutation>\nunlock` in ONE
session, must handle a blocking wait when another holder exists (e.g. the admin server's
maintenance worker or a human shell), and `shell_liner.go:134-139` resets `noLock` per command
(the dry-run `noLock` never leaks into the next command) [T3]. Read-only verbs do not lock.

### R2.2 Q2 — TLS silent fallback (#10502) at 4.50: STILL PRESENT (verified); self-test identified

- Mechanism unchanged at 4.50: `weed/security/tls.go` `LoadClientTLS` returns
  `grpc.WithTransportCredentials(insecure.NewCredentials())` on FIVE branches — nil config,
  missing cert/key/`grpc.ca`, cert `pemfile.NewProvider` failure, CA provider failure,
  `advancedtls.NewClientCreds` failure — each with only a `glog.Warningf` [T6]. Exactly the
  `weed/security/tls.go:176-190` path issue #10502 described.
- Issue #10502 ("helm: bucket-creation hook cannot reach an mTLS filer under enableSecurity",
  opened 2026-07-31) was closed 2026-10-04 by **PR #11589 "helm: mount TLS certificates in bucket
  hook"** (merged 2026-10-04T12:35:08Z) [T18] — a CHART fix (mount the cert Secrets into the hook
  pod). The binary-side silent fallback was NOT changed; at 4.50 a shell whose security.toml
  points at unmounted cert paths still dials plaintext.
- What the operator sees when the endpoint enforces mTLS (`RequireClientCert`, tls.go server
  side): the plaintext handshake fails → shell never reaches master → piped run exits 1 with
  `cannot connect to master …` (post-#11117). The CAUSE (missing certs) is only in the glog
  warning, which is hidden from stderr unless `-debug` is passed — `RunShell` sets
  `alsologtostderr=false`, `logtostderr=false` when not debug [T3].
- **Reliable startup self-test** (no writes, bounded): `printf 'cluster.ps\n' | weed shell
  -master=<master:9333> -debug -connectTimeout=10s`. The master connect happens BEFORE any
  command dispatch [T3], so even `help` exercises it; `cluster.ps` is a cheap read. Verdicts:
  exit 0 = shell↔master gRPC works (plaintext both ends, or certs valid); exit 1 + stderr
  `pemfile.NewProvider(...) failed` + `cannot connect to master` = certs missing/unmounted while
  mTLS is enforced. Add a filer leg (`fs.ls /`) for the case where master is plaintext but the
  filer requires mTLS (the #10502 hook hit exactly that split). An MCP server (admin/onprem tiers)
  should run this probe in its FastMCP `lifespan` startup and fail readiness loudly.
- Lab today: no security.toml, plaintext gRPC — the fallback path is inert until
  `enableSecurity`; when enabled, the MCP pod must mount the cert Secrets alongside security.toml
  (the #10502 lesson) — see the card's credential story (§R2.5).

### R2.3 Q3 — onprem volume-file reality: VERIFIED, with a lab-layout correction

**`weed fix` at 4.50** [T7]:
- `UsageLine: "fix [-remoteFile=false] [-volumeId=234] [-collection=bigData] /tmp"` — the target
  is POSITIONAL (dir or single `.dat`); there is **no `-dir` flag** (flags are only: collection,
  volumeId, includeDeleted, ignoreError, remoteFile, ecx, ecDataShards, ecParityShards,
  ecUnsafeIgnoreSidecar).
- Long help verbatim: *"Fix runs the SeaweedFS fix command on local dat files ( or remote files)
  or whole folders to re-create the index .idx file. … **You Need to stop the volume server when
  running this command.**"*
- `doFixOneVolume` → `SaveToIdx` opens `<basepath>/<baseFileName>.idx` with
  `O_WRONLY|O_CREATE|O_TRUNC` — rewrites the `.idx` in place. 4.50's `SaveToIdx` deliberately
  emits entries in **.dat append order** (every tombstone included) because a key-sorted `.idx`
  "used to flip volumes read-only on load" — directly relevant to this lab's idx>dat read-only
  failure mode (R1 §R1.2 site 1). Scan/save failure → `glog.Fatal` unless `-ignoreError`.
- Bonus in 4.50: `-ecx` regenerates lost `.ecx` (+ `.vif`) from local shards with RS
  reconstruction — same "stop the volume server" rule.

**`volume.unmount` / `volume.mount`** [T8][T19][T21]:
- `weed/shell/command_volume_unmount.go` @4.50: exact shape `volume.unmount -node <volume server
  host:port> -volumeId <volume id>`, help "unmount a volume from one volume server"; both flags
  required; goes through `confirmIsLocked` (see §R2.1 lock note) then the `VolumeUnmount` gRPC.
- Issue #6139 (2024-10-17, "[volume] avoid reset volume metrics after one volume
  unmount/mount") exists and demonstrates exactly this unmount→mount pair [T19]; it was closed
  2024-10-22 by commit `d38456dc0` — the metrics-reset side effect is fixed long before 4.50
  [T19 timeline]. Note: #6139 is evidence of the command's use, not itself a doc; the wiki
  "Add volumes" section documents `volume.mount -node <host>:<port> -volumeId <id>` (and SIGHUP
  reload for all new files), while the wiki's documented tool for "Servicing live volumes"
  without stopping is `volumeServer.state --nodes <n> --maintenanceOn` — a sticky, whole-server
  read-only maintenance mode [T21]. The admin tier should expose both granularities.

**Lab layout correction for the onprem flow** (live pod spec `seaweedfs-volume-0` [T9]):
- The volume server runs `exec /usr/bin/weed -logdir=/logs -v=1 volume -port=8080 -dir /drive
  **-dir.idx=/idx** -max 0 -index=leveldb …` — `.dat` files live on **hostPath `/var/mnt/$(POD_NAME)`**
  (mounted at `/drive`), while `.idx` files live on a **separate PVC** `idx-seaweedfs-volume-N`
  (10 Gi, charts/seaweedfs/values.yaml `volume.idx.type: persistentVolumeClaim`) whose PV is a
  k3s local-path hostPath: `/var/lib/rancher/k3s/storage/pvc-<uid>_default_idx-seaweedfs-volume-N`
  (live-verified for volume-0) [T10]. Infra is a single node (`nodeName: infra`, hostPath-able).
- `weed fix <datDir>` writes the fresh `.idx` NEXT TO the `.dat` — i.e. into the dat dir, NOT
  where the server reads indexes from (`/idx`). The chart already knows this: the pod's
  initContainer `seaweedfs-vol-move-idx` runs `weed fix "$dir"` for a `.dat` whose `.idx` is
  missing from both dirs, then `mv /drive/*.idx /idx/` — at every pod start [T9].
- Therefore the onprem per-volume procedure is: `volume.unmount` (shell, needs `lock`) → run
  `weed fix` with BOTH the dat dir (`/var/mnt/<pod>`) and the idx dir
  (`/var/lib/rancher/k3s/storage/pvc-<uid>_default_idx-seaweedfs-volume-N`) visible, placing the
  regenerated `.idx` into the idx dir → `volume.mount`. A pod-restart shortcut exists (the
  initContainer does fix+mv) but remounts everything and is not per-volume. The onprem MCP pod
  needs hostPath mounts of `/var/mnt` and `/var/lib/rancher/k3s/storage` plus the `weed` binary
  in its image.

**Rust volume server at 4.50** [T11][T12][T13][T22]:
- Real and shipped: `seaweed-volume/` Cargo crate in-tree, `VOLUME_SERVER_RUST_PLAN.md` at repo
  root, `rust_binaries_release.yml` builds versioned binaries on every tag, wiki page "Rust
  Volume Server" (Chris Lu, 2026-08-22). The binary is `weed-volume`; the standard
  `chrislusf/seaweedfs` image **carries both servers** — run `weed volume` for Go, `weed
  volume-rust` for Rust (amd64/arm64 only) [T22].
- **How to tell which binary a pod runs**: the pod's container command (`weed … volume …` = Go).
  This lab is Go — live-verified: `chrislusf/seaweedfs:4.50` (digest `sha256:c2658820…`), command
  `exec /usr/bin/weed … volume …`, `/status` Version `"30GB 4.50 ec8f97935"` [T9][live probe].
  Runtime alternative: the `Server` response header / `/status` version string.
- **Does unmount/fix work identically?** Per the wiki parity tables: all 48 gRPC RPCs implemented
  including `VolumeUnmount` (explicitly "Identical" for the missing-volume nil return), storage
  formats byte-identical (`.dat`/`.idx`/`.vif`/EC), passes all 109 Go integration tests → shell
  `volume.unmount`/`volume.mount` and file-level `weed fix` behave the same against either server
  [T22]. Contradiction on record: `seaweed-volume/MISSING_FEATURES.md` (audit dated 2026-03-07)
  lists TLS, streaming reads, master-notification of readonly marks etc. as missing/partial
  [T12], while the wiki (2026-08-22) and README claim mTLS + full parity [T11][T22] — the audit
  predates; Sprint 1 in it is already marked ✅ DONE (incl. the VolumeMarkReadonly notification).
  Immaterial for this lab (Go), but the card should note the Rust path is where future drift risk
  lives.

### R2.4 Q4 — read-only HTTP endpoints: live measurements + recommended surface

All probes 2026-11-11 ~01:35 UTC from the Coder workspace through the public ingress, zero
credentials sent, GET only. Sizes are `size_download` bytes; times are curl totals.

| Endpoint | Auth | Code | Size | Time | Format / content |
|---|---|---|---|---|---|
| master `/` | none | 200 | 9.3 KB | 16 ms | HTML volume table + Up Time |
| master `/status` | — | **404** | 64 B | 26 ms | JSON error `volume id status not found: unknown volume id status` — **route does not exist in 4.50**; the `{fileId}` redirect handler swallows the path [T14] |
| master `/dir/status` | none | 200 | 8.8 KB | 24 ms | JSON `{Version,TopologyId,Topology}`: DC→rack→node with `Volumes`,`EcShards`,`Max`,range-compressed `VolumeIds`; proxies to leader; `guard.WhiteList` (open unless configured) [T14][T15] |
| master `/vol/status` | none | 200 | **1.0 MB** | 57 ms | JSON `{Version,Volumes}` = `Topo.ToVolumeMap()`: per-node arrays of the SAME VolumeInfo structs as volume `/status` (Id, Collection, Size, DeletedByteCount, FileCount, DeleteCount, CompactRevision, ReadOnly, ReadOnlyCanDelete, ReplicaPlacement, Ttl, ModifiedAtSecond, DiskId) — i.e. `volume.list` detail lines over pure HTTP [T14][T15] |
| master `/dir/lookup?volumeId=2` | none | 200 | 370 B | ~20 ms | JSON replica locations: `url` (in-cluster), `publicUrl`, `grpcPort` |
| master `/collection/info?collection=logs` | none | 200 | 137 B | ~20 ms | JSON `{Collection,FileCount,TotalSize,UsedSize,Version,VolumeCount}` (logs: 528,569 files / 675 GB total / 210 GB used / 1 volume). `collection=default` → `collection default does not exist`; empty param → `collection is required` (the unnamed pool is not queryable here) |
| master `/healthz`,`/readyz` | none | 200 | 0 B | 13 ms | empty; cheap liveness |
| master `/stats/health`,`/stats/counter` | — | 404 | — | — | flag-gated (metrics build), not enabled here [T14] |
| volume `/status` (public subdomain → one pod) | none | 200 | 98–156 KB (5 samples) | 20–50 ms | JSON `{DiskStatuses,Version,Volumes[]}` per node [T16] |
| volume `/dir/config` | — | **400** | 0 B | 17 ms | **does not exist in 4.50** — volume routes are `/status`,`/healthz`,`/readyz`,`/ui/index.html`,`/stats/*`(gated),`/` [T16]; `/dir/*` is master namespace |
| admin `/api/admin` | none | 200 | 16 KB | 24 ms | JSON cluster summary: total_volumes 3,089, total_chunks 49.3 M, total_size 53.7 TB, volume_size_limit_mb, master/volume/filer/s3 node lists, datacenters, **total_ec_volumes/total_ec_shards**, trends, tier_stats |
| admin `/api/cluster/topology` | none | 200 | 7.7 KB | 14 ms | JSON nodes with volumes/max_volumes/disk_usage |
| admin `/api/cluster/volumes` | none | 200 | 3.6 KB | 14 ms | JSON volume-server rows |
| admin `/api/cluster/masters` | none | 200 | 209 B | 14 ms | JSON |
| admin `/api/config` | none | 200 | 372 B | 14 ms | JSON |
| admin `/api/files/list-folders?path=/buckets` | none | 200 | ~150 B | ~20 ms | JSON `{"folders":[…]}` (12 buckets incl. logs) |
| admin `/api/files/properties?path=/buckets/logs` | none | 200 | ~350 B | ~20 ms | JSON file/dir metadata (mode, size, timestamps, ttl). **Gotcha: no trailing slash** — `/buckets/logs/` → 500 `filer: no entry is found in filer store`; missing `path` → 400 |
| admin `/api/files/view?path=…` | none | 200/500 | ~300 B | ~20 ms | JSON metadata; same path rules (file download/view sibling of properties) |
| admin `/cluster/volume-servers` | none | 200 | 32.8 KB | 23 ms | HTML page |
| admin `/storage/ec-shards` | none | 200 | 18 KB | 21 ms | HTML (templ/Bootstrap). **No embedded JSON** — scrape-only (rows carry `data-volume-id`; live shows vol 1 at 13/14 "Minor Issues", vol 4 at 7/14 "Degraded", matching R1). Per-volume detail is another HTML route `/storage/ec-volumes/{id}` |
| admin `/storage/volumes` | none | 200 | 171 KB default / 50 KB `?pageSize=20` / 778 KB `?pageSize=500` | 22–28 ms | HTML; `pageSize` honored, unbounded above |
| admin `/health` | none | 200 | 16 B | 19 ms | JSON |
| admin `/metrics` | none | 200 | 19 KB | 24 ms | Prometheus text, no auth (route registered before the auth gate) [T23] |

**Auth model (source-verified):** admin `SetupRoutes(r, authRequired, …)` — when an admin
user/password is configured, UI routes get `RequireAuth` and `/api` gets `RequireAuthAPI`;
otherwise *"No authentication required - all routes are public"* [T23]. The lab runs unconfigured
→ every endpoint above is anonymous. Master `/dir`,`/vol` routes sit behind `guard.WhiteList`
(IP allowlist, empty = open) [T14]. The MCP inherits this exposure — the card's credential story
must say so.

**The `/status` churn, resolved.** Loki live measurement 2026-11-11 01:48 UTC: `sum(count_over_time(
{app_kubernetes_io_name="seaweedfs"} |= "error writing JSON status" [1h])) by (pod)` = **1,569
lines/h** total (184–213 per volume pod ≈ one per 18 s/pod) — same order as the incident note's
~1,709/h, i.e. STEADY STATE, not incident load. Sample lines:
`common.go:136 error writing JSON status /status 200: write tcp 10.42.0.35:8080->10.42.0.1:48756:
write: connection reset by peer`. The peer `10.42.0.1` is the node/CNI gateway = **kubelet
probes**: the pod spec polls `/status` as both readiness (period 15 s, timeout 30 s,
failureThreshold 100) and liveness (90 s) [T9] — ≈2,240 probe GETs/h over 8 pods, ~70 % logging an
RST line because the probe client closes with the response body unread after the 200 header; the
server-side `writeJson` marshals the full payload then fails the final `w.Write` →
`writeJsonQuiet` logs it (`weed/server/common.go:134-139`) [T24]. Verdict: **/status is cheap to
poll** (full JSON in 20–50 ms; the error lines are log noise, not failed probes — pods stay
Ready). MCP rules: read bodies to completion (never abort early, or you add lines); prefer one
master `/vol/status` (1 MB) or admin `/api/*` (KB-scale) over fanning out to 8 volume `/status`
(~1 MB total + 8× log-line risk).

**Recommended readonly-tier surface (pure HTTP, no shell):**

| MCP tool (suggested) | Backend | Cost |
|---|---|---|
| `cluster_summary` | admin `/api/admin` | 16 KB |
| `cluster_topology` | admin `/api/cluster/topology` (+`/volumes`,`/masters`,`/config`) | ≤8 KB |
| `volume_list_detail` (== shell `volume.list` fields; filter ReadOnly for `-readonly`) | master `/vol/status` | 1 MB |
| `topology_overview` (per-node counts + VolumeIds ranges + EcShards counts) | master `/dir/status` | 8.8 KB |
| `volume_lookup` (replica locations of one vid) | master `/dir/lookup?volumeId=` | 370 B |
| `collection_info` | master `/collection/info?collection=` | 137 B |
| `node_status` (one volume server, on demand) | volume `/status` | ~150 KB |
| `file_properties` / `file_view` / `list_folders` | admin `/api/files/*` | ≤1 KB |
| `health` / `metrics` | admin `/health`,`/metrics`; master+volume `/healthz` | ≤19 KB |

**Shell-subprocess-only (no HTTP equivalent at 4.50):** `volume.fsck`, `volume.check.disk`
(simulate), `ec.status`-style per-shard maps (`volume.list` prints EC shard lines), `cluster.ps`,
`volumeServer.state` query. EC shard DETAIL over HTTP exists only as templ-rendered HTML
(`/storage/ec-shards`, `/storage/ec-volumes/{id}`) — scrape is brittle across versions; the
readonly tier should expose EC totals from `/api/admin` + per-node counts from `/dir/status`, and
route shard-level detail through the shell tier (admin instance) or omit it.

### R2.5 Q5 — repo precedent for build + deploy + registration

**Build (containers/wekan-mcp is the template)** [T25][T26][T27]:
- `containers/wekan-mcp/` = `Dockerfile` + `pyproject.toml` + `wekan_mcp/` package + README.
  Dockerfile: `python:3.15-slim`, pip-install the package, non-root uid/gid 65532, `EXPOSE 8080`,
  `ENTRYPOINT ["wekan-mcp"]` (console script from `[project.scripts]`). Deps pinned
  **`fastmcp>=4.1,<5`** + `httpx>=0.27,<1` (plain httpx for its own REST calls — coexists with
  FastMCP 4's httpx2; see §R2.6). The seaweedfs-mcp container mirrors this layout
  (`containers/seaweedfs-mcp/`, console entry `seaweedfs-mcp`), plus for the onprem tier a
  multi-stage `COPY --from=chrislusf/seaweedfs:<pinned>` of `/usr/bin/weed` (renovate-pinnable via
  the ARG+datasource pattern of the container-creation skill).
- CI: `.github/workflows/docker-build.yaml` — triggers on push to `main`/`dev` touching
  `containers/**`, PRs (build-only, never push), plus `workflow_dispatch` with an explicit
  container list. Publishes `ghcr.io/ownyourio/seaweedfs-mcp:v<run_number>` (immutable) +
  `:<branch>` (rolling) [T26]. Chart/values pin the `:v<run>` tag; renovate's docker manager
  tracks bumps (wekan precedent comments in both values files).
- No docker daemon in agent sessions: the container chunk's build gate is CI-primary per AGENTS.md
  (cf-77 shape: `docker build => no-daemon, CI-deferred`).

**Deploy (ToolHive MCPServer entries — NOT a plain Deployment, NOT a standalone chart)** [T27][T28][T29][T30]:
- wekan-mcp ships as `hivetools.mcp.<name>` values entries rendered by `charts/hivetools`
  (cluster-wide via base): dev `boards` (services/dev/prod/values.yaml:451-487, image
  `wekan-mcp:v162`, `transport: streamable-http`, `mcpPort: 8080`, multi-env secret via
  `podTemplateSpec` `envFrom.secretRef` because CRD `secrets[]` is a list-map keyed by Secret
  name); gpu `wekan-readonly` (env `WEKAN_MCP_READ_ONLY=true`) + `wekan-admin` — **the exact
  two-tier precedent** for seaweedfs readonly/admin, tier enforced server-side by the image, not
  by the proxy [T27][T28].
- `charts/hivetools/templates/generic-mcpserver.yaml` renders `toolhive.stacklok.dev/v1beta1
  MCPServer` named `mcp-<name>` in ns `default`, supporting `env`, `secrets`, `serviceAccount`,
  `resources`, `podTemplateSpec`, `volumes`, `oidc→oidcConfigRef`, `authz→authzConfig`,
  `toolsFilter→toolConfigRef`; `generic-mcptoolconfig.yaml` renders a matching **MCPToolConfig**
  `mcp-<name>-tools`; ingress path `/<name>` on `mcp.<cluster>.<domain>` comes free
  (`generic-mcp-ingress.yaml`) — no ApplicationSet entry, no proxy subdomain entry [T29].
- For seaweedfs: entries under `hivetools.mcp` in `services/infra/prod/values.yaml` (infra already
  runs the platform: postgres-keycloak entry there; live operator `ghcr.io/stacklok/toolhive/
  operator:v0.56.0`, helm release `infra-hivetools`, ns default [T30]). Client URLs land at
  `https://mcp.infra.spencerslab.com/<name>/mcp` (pattern proven live by
  `readonly-infra-postgres-keycloak`).
- onprem tier specifics: `podTemplateSpec.spec.volumes` + `volumeMounts` for hostPath `/var/mnt`
  (dat) and `/var/lib/rancher/k3s/storage` (idx PV dirs) — ToolHive docs show arbitrary volumes
  (incl. PVCs) via `podTemplateSpec`; the top-level `spec.volumes` is hostPath-only per the repo's
  mcp-servers reference [T30][T31]. Node targeting: single-node infra cluster, but a nodeSelector
  keeps it honest. Security contexts drop-ALL per repo standard; note hostPath mounts of the
  storage dirs are a deliberate privilege escalation — gate the onprem tier behind the mutation
  confirm flow AND keep it unregistered/disabled by default.

**Registration (machine-global, NOT this repo)** [T32]: the MCP fleet lives in
`~/.config/opencode/opencode.json` (39 servers; unversioned). Pattern: `<priv>-<cluster>-<service>`
remote entries; infra-cluster servers use the public ingress URL form
(`https://mcp.infra.spencerslab.com/<name>/mcp`), gpu/global ones use in-cluster headless-service
URLs (`http://mcp-mcp-<name>-headless.default:8080/mcp`). Follow-up card: register e.g.
`readonly-infra-seaweedfs` (and `admin-…` only if/when OIDC gating exists), AND add the AGENTS.md
MCP-table row in the same change (AGENTS.md hard rule: machine-global fleet changes are recorded
in the repo's table).

**Credential story**: today — none needed; every seaweedfs HTTP endpoint probed is auth-free and
the ToolHive proxy default is unauthenticated (§R2.7). Later, if `enableSecurity` lands: the MCP
pods need security.toml AND the cert Secrets mounted (issue #10502/#11589 lesson, §R2.2), the
startup self-test guards misconfiguration, and s3/admin basic-auth (if enabled) must come from
Bitwarden via ExternalSecret per repo law. If the lab re-enables ToolHive OIDC (currently
commented out chart-wide since 2026-09), uncomment the per-server `oidc:` blocks for the new
entries too.

### R2.6 Q6 — FastMCP 4.1.x: all guide claims verified (one version bump, one direction-of-gate nuance)

- **Release line**: PyPI latest stable **4.1.8** (uploaded 2026-11-10; 4.1.7 same day; 4.1.1 is
  eight patches back); 4.2.0a1–a4 alphas in flight [T33]. `fastmcp` is a thin meta-package over
  `fastmcp-slim[client,server]`; Python ≥3.10; floors: pydantic ≥2.12, starlette ≥1.0.1 (server
  extra), `mcp>=2.3,<3`, **`httpx2>=2.5.0`** [T33][T34]. Guide delta: say "4.1.x (verified
  4.1.8)" and pin `fastmcp>=4.1,<5` exactly like `containers/wekan-mcp/pyproject.toml` [T25].
- **Visibility API**: `enable()/disable(names=…, tags=…, keys=…, version=…, components=…)` is the
  sanctioned runtime API ("Component Visibility", New in 3.0.0); disabled tools vanish from
  `list_tools` AND cannot be called; allowlist mode `enable(tags={…}, only=True)` flips the
  default to disabled and is recommended "for restrictive environments"; provider-level rules run
  first, server-level override later [T35]. The **"default not guarantee" caveat, verbatim
  sources**: (a) "If no visibility state is set, the component is enabled by default"; (b) WARNING:
  filters in one call INTERSECT and "a rule that matches nothing fails silently … the components
  you meant to hide stay exposed"; (c) component keys need the trailing `@`
  (`tool:name@`) [T35]. Consequence: the readonly tier must use CONDITIONAL REGISTRATION
  (never register mutation tools — the wekan `WEKAN_MCP_READ_ONLY` precedent) with
  `enable(only=True)` allowlisting as defense-in-depth, not `disable(tags=…)` alone.
- **ctx.elicit era gate**: VERIFIED and sharper than the guide states. Elicitation is era-gated in
  4.0: `ctx.elicit()` works ONLY on handshake-era connections (≤ 2025-11-25) and RAISES on the
  modern **2026-07-28** protocol (SEP-2322 removed server-initiated back-channel requests;
  SEP-2575 statelessness) — `ToolError: elicitation via server-initiated requests is unavailable
  on 2026-07-28 connections.` Because `fastmcp.Client` defaults to `mode="auto"` (negotiates the
  modern era), the upgrade guide calls this "the single most likely runtime failure" [T36][T37].
  The modern replacement is the **guard pattern**: return `InputRequiredResult` (New in 4.0.0),
  client answers, tool re-runs statelessly; multi-replica deployments need a shared sealing key
  (`request_state_security=RequestStateSecurity(keys=[…])`; default is per-process ephemeral)
  [T36]. Guide delta: the plan→confirm_token→apply design is the RIGHT choice — it is era-proof
  (the token rides tool arguments, no back-channel, no session state); do not implement
  confirmation via `ctx.elicit`.
- **stateless_http**: verified in all three spellings — `mcp.http_app(stateless_http=True)`,
  `mcp.run(transport="http", stateless_http=True)`, env `FASTMCP_STATELESS_HTTP=true`; required
  for horizontal scaling because sticky sessions don't work (MCP clients don't forward Set-Cookie)
  and on the modern era session state doesn't persist anyway [T38].
- **custom_route**: verified — `@mcp.custom_route("/health", methods=["GET"])`; documented NOTE:
  "Custom routes are never protected by the server's authentication middleware … by design" —
  perfect for k8s/ToolHive probes [T38]. (Guide's `/healthz` path is arbitrary; any path works.)
- **lifespan=**: verified — `FastMCP("…", lifespan=app_lifespan)` with `@lifespan` from
  `fastmcp.server.lifespan` (New in 3.0.0); the yielded dict is reachable as
  `ctx.lifespan_context`; composable via `|`; plain `@asynccontextmanager` still accepted. Use it
  for the §R2.2 shell self-test and shared httpx client setup [T39].
- **httpx2/except guidance**: verified from the official 3→4 upgrade guide: "FastMCP now uses
  httpx2 exclusively" (a fork; httpx is no longer a FastMCP dependency); the subtle break —
  `except httpx.…` handlers around FastMCP calls "still import and still type-check — [they] just
  never match, because FastMCP now raises httpx2 exceptions … Grep your codebase for `except
  httpx.`"; custom `httpx_client_factory`/`httpx.Auth` objects must be httpx2; **"HTTP made
  inside your own tools is entirely yours and is unaffected"** — so calling weed endpoints with
  the pinned plain `httpx` (wekan-mcp precedent) is fine; exceptions raised inside tools are
  mapped to `ToolError` by FastMCP's error boundary, which recognizes both libraries during the
  transition. Also: httpx2 uses the OS trust store (honors `SSL_CERT_FILE`/`SSL_CERT_DIR`)
  instead of certifi, and HTTP loggers rename to `httpx2`/`httpcore2.*` [T37].
- Other 4.x facts worth carrying into the card: per-tool `timeout=` (New in 3.0); sync tools run
  in a threadpool by default (`run_in_thread=True`) so a blocking `weed shell` subprocess is
  concurrency-safe; `mask_error_details=True` option; middleware now sees every message incl.
  unroutable ones; resource-not-found wire code changed -32002→-32602; `ctx.set_state` does NOT
  persist on modern-era connections (another reason the confirm_token must ride arguments)
  [T36][T37][T40].
- UNVERIFIED-from-docs: none of the guide's FastMCP claims remains unverified. Standing
  verification command for drift at build time: `pip index versions fastmcp` /
  `curl -s https://pypi.org/pypi/fastmcp/json | jq -r .info.version`, and read
  `https://gofastmcp.com/docs/llms.txt` for the page index.

### R2.7 Q7 — ToolHive v1beta1 CRDs: VERIFIED (docs + live cluster)

- All four CRDs exist as the guide claims: the CRD reference index lists **MCPServer** (core
  workload) and, under shared configuration, **MCPOIDCConfig**, **MCPAuthzConfig**,
  **MCPToolConfig** — with per-resource pages documenting fields/defaults/validation [T41]:
  `docs.stacklok.com/toolhive/reference/crds/` + `/mcpserver`, `/mcpoidcconfig`, `/mcpauthzconfig`,
  `/mcptoolconfig`. v1beta1 is current (migration guide: inline `spec.tools` was REMOVED in
  v0.15.0 in favor of `spec.toolConfigRef` → MCPToolConfig; `spec.port`→`proxyPort`,
  `targetPort`→`mcpPort`) [T42]. `kubectl explain` equivalents at deploy time:
  `kubectl explain mcpserver --recursive` etc. against `toolhive.stacklok.dev/v1beta1`.
- Live infra cluster (where seaweedfs runs): all **14** `toolhive.stacklok.dev` CRDs installed;
  `mcpservers.toolhive.stacklok.dev` serves `v1alpha1` + **`v1beta1` (storage)**; operator
  `ghcr.io/stacklok/toolhive/operator:v0.56.0` (helm release `infra-hivetools`, ns default,
  Ready 1/1) [T30]. The repo's chart already renders v1beta1 MCPServer + MCPToolConfig and
  supports `authz`/`oidc` refs (§R2.5) [T29].
- **Unauthenticated-proxy default: CONFIRMED verbatim** (run-mcp-k8s guide, updated 2026-11-04):
  *"Authentication is not enabled by default … If you configure no authentication source, the
  proxy accepts every request that can reach it and forwards it to the MCP server under a
  synthetic local-user identity, with no token or credential check. This is intended for local
  development or deployments already isolated behind a trusted network boundary (such as a
  NetworkPolicy or service mesh)."* To enforce: `oidcConfigRef` → MCPOIDCConfig, or
  `authServerRef` (embedded auth server); Cedar authorization via `authzConfig`/MCPAuthzConfig
  [T43][T44]. Lab posture matches: every `oidc:` block commented out since 2026-09 [T27][T28].
  Consequence for the card: an exposed `seaweedfs-admin`/`onprem` MCPServer at
  `mcp.infra.spencerslab.com/…` is world-drivable for anyone who can reach that ingress — gate
  via re-enabled OIDC, MCPToolConfig allowlists, NetworkPolicy, or keep the mutating tiers
  unregistered until OIDC returns.

### R2.8 Verdict table (per question)

| # | Question | Verdict | Key source |
|---|---|---|---|
| Q1 | Piped `weed shell` exits non-zero on command failure in 4.50 | **VERIFIED** (PR #11117 merged 2026-09-03; code at tag 4.50; sticky-lastErr nuance; interactive still exits 0; exit code 1 not 2) + **ADDITION**: mutation verbs need in-session `lock` first | [T1][T2][T3][T17][T4][T5] |
| Q2 | #10502 TLS silent fallback still present at 4.50 | **VERIFIED present** (5 insecure-fallback branches in `LoadClientTLS`); issue closed chart-side by PR #11589, binary unchanged. Self-test: piped `cluster.ps` (+`fs.ls /` for the filer leg) with `-debug -connectTimeout=10s` → exit 1 + `cannot connect to master` + pemfile warning | [T6][T18][T3] |
| Q3a | `weed fix` positional dir, no -dir, rewrites .idx in place, help says stop the server | **VERIFIED** (verbatim help; O_TRUNC rewrite; append-order .idx nuance; `-ecx` bonus) | [T7] |
| Q3b | `volume.unmount -node -volumeId` exists; #6139 claim | **VERIFIED with refinement**: exact flag shape in 4.50 source; #6139 is real usage evidence (its metrics-reset bug fixed 2024-10-22, commit d38456dc0); wiki documents `volume.mount` and `volumeServer.state --maintenanceOn` (server-wide) as the live-service tools | [T8][T19][T21] |
| Q3c | Lab volume-file reality | **CORRECTED for the lab**: `.dat` on hostPath `/var/mnt/<pod>`, `.idx` on local-path PVC dirs under `/var/lib/rancher/k3s/storage/`; fix must place the .idx where `-dir.idx=/idx` reads it; chart initContainer already does fix+mv at pod start | [T9][T10] |
| Q3d | Rust volume server | **VERIFIED real at 4.50** (`weed-volume` in the standard image; `volume` vs `volume-rust` verb); lab runs Go (pod command + image + Version string); unmount/mount/fix behave identically per wiki parity (all 48 RPCs, byte-identical files); README-vs-MISSING_FEATURES contradiction noted (audit 2026-03 predates wiki 2026-08) | [T11][T12][T22][T9] |
| Q4 | Read-only endpoint set | **CORRECTED**: master `/status` and volume `/dir/config` do NOT exist in 4.50; the guide's endpoint list is replaced by the measured table (§R2.4); all endpoints auth-free; `/status` churn = benign kubelet-probe RST noise (1,569/h live), polling is cheap (20–50 ms); recommended surface = admin `/api/*` JSON + master `/dir/status`,`/vol/status`,`/dir/lookup`,`/collection/info`; shell-only = fsck, check.disk, EC per-shard detail (no JSON HTTP; HTML scrape brittle) | [T14][T15][T16][T23][T24][T9][live probes] |
| Q5 | Repo precedent shape | **VERIFIED**: containers/wekan-mcp build shape + CI tag law; ToolHive `hivetools.mcp.*` deploy (wekan readonly/admin two-tier precedent; infra runs operator v0.56.0); fleet registration is machine-global (not repo); credentials: none today, #10502 mount story if enableSecurity | [T25][T26][T27][T28][T29][T30][T32] |
| Q6 | FastMCP 4.1.x claims | **VERIFIED with version bump + one direction nuance**: line is 4.1.8 (guide: 4.1.1); enable/disable(tags) sanctioned with the silent-no-match/default-enabled caveats; ctx.elicit era gate real — elicit FAILS on 2026-07-28 (modern) and works on ≤2025-11-25; stateless_http/custom_route(never authed)/lifespan= all confirmed; httpx2-exclusive with the dead-`except httpx.` trap; tool-internal plain-httpx unaffected | [T33][T34][T35][T36][T37][T38][T39][T40] |
| Q7 | ToolHive v1beta1 CRDs | **VERIFIED**: MCPServer + MCPOIDCConfig + MCPAuthzConfig + MCPToolConfig documented (URLs cited) and all 14 CRDs live on infra with v1beta1 as storage version; unauthenticated-proxy default confirmed verbatim | [T41][T42][T43][T30] |

### R2.9 Guide deltas (what the follow-up ticket must change vs the pasted guide)

1. **Version pins**: SeaweedFS 4.48 → **4.50** (deployed `ec8f97935`; renovate has a 4.53.0 chart
   bump pending — re-verify command shapes at bump time); FastMCP 4.1.1 → **`>=4.1,<5`** (verified
   4.1.8); ToolHive v1beta1 confirmed (operator **v0.56.0** live).
2. **Drop master `/status` and volume `/dir/config`** from any tool design — neither route exists
   in 4.50. Replace with master `/dir/status` (8.8 KB summary) + `/vol/status` (1 MB full detail)
   + `/dir/lookup?volumeId=` + `/collection/info`; volume `/status` per-node only on demand.
3. **Reframe the `/status` churn**: benign kubelet-probe RST noise (readiness 15 s + liveness 90 s
   per pod), steady ~1.5–1.7 k lines/h, responses complete in 20–50 ms. Not a health signal; do
   not alert on it; MCP clients must read full bodies (early disconnects add lines).
4. **Shell lock requirement**: every mutation verb needs `lock` acquired in the same piped session
   (`lock\n<cmd>\nunlock`), blocks while another holder has it, and `noLock` never leaks between
   commands. The admin tier's plan→confirm_token→apply scripts must embed this and surface
   "waiting for lock held by …".
5. **Exit-code law confirmed** — build the shell-runner on piped mode + exit status (sticky: one
   failure poisons the run's exit code; parse stderr `error:` lines for detail).
6. **TLS story**: fallback still silent at 4.50; add the lifespan startup self-test (§R2.2) to
   admin/onprem tiers; when enableSecurity lands, mount cert Secrets WITH security.toml (#10502/
   #11589 lesson).
7. **onprem file topology**: split `.dat` (hostPath `/var/mnt/<pod>`) vs `.idx` (local-path PVC
   dir); the per-volume flow must land the regenerated `.idx` in the idx location the server
   reads (`-dir.idx=/idx`); cite the chart's initContainer fix+mv as prior art; hostPath-mount
   `/var/mnt` + `/var/lib/rancher/k3s/storage` in the onprem pod; ship the `weed` binary in the
   image (multi-stage from `chrislusf/seaweedfs:<pin>`).
8. **Rust server**: informational section only — detection via pod command (`weed volume` vs
   `weed volume-rust`), lab is Go, procedures identical; note the README-vs-audit contradiction.
9. **Confirmation UX**: keep plan→confirm_token→apply; do NOT use `ctx.elicit` (raises on the
   default modern-era connection); guard pattern (`InputRequiredResult`) is the sanctioned
   alternative if interactive confirmation is ever wanted; tokens must ride arguments (no session
   state on the modern era; `request_state` sealing is per-process unless a shared key is set).
10. **Visibility hardening**: conditional registration per mode (wekan `WEKAN_MCP_READ_ONLY`
    precedent) as the primary gate + `enable(only=True)` allowlist as second layer; never rely on
    `disable(tags=…)` alone (default-enabled; silently-failing filters).
11. **FastMCP 4 API hygiene**: `stateless_http=True`; `@mcp.custom_route("/healthz", …)` for
    probes (never auth-protected — by design); `lifespan=` for startup probes/clients; `except
    httpx2.*` (never `except httpx.*`) around FastMCP calls; plain `httpx` inside tools is fine;
    pydantic ≥2.12 floor.
12. **Deployment wiring**: `hivetools.mcp.{seaweedfs-readonly,seaweedfs-admin,seaweedfs-onprem}`
    under `services/infra/prod/values.yaml` (image `ghcr.io/ownyourio/seaweedfs-mcp:v<run>`,
    streamable-http, mcpPort 8080, securityContext uid 65532); NO new chart/appset/proxy entries;
    register in machine-global opencode.json + AGENTS.md table row.
13. **Security gate before exposing mutating tiers**: ToolHive proxy default is unauthenticated
    AND weed endpoints are auth-free — either re-enable the `oidc:` blocks, add an MCPToolConfig
    allowlist, or ship admin/onprem `enabled: false` until the owner rules.

### R2.10 Card skeleton (description-body outline for the follow-up WeKan card)

The coordinator authors the card; this is the section list its description should carry:

1. **Goal & scope** — build `containers/seaweedfs-mcp` (FastMCP `>=4.1,<5`, Python ≥3.10) exposing
   SeaweedFS 4.50 ops over MCP; three modes (readonly / admin / onprem) from ONE image, mode by
   env (wekan-mcp precedent); out of scope: filer write APIs, s3 data plane, Rust volume server.
2. **Verified-facts baseline** — pointer to this RESEARCH.md §R2 (pin: weed 4.50 `ec8f97935`,
   FastMCP 4.1.8-verified, ToolHive operator v0.56.0); "re-verify on version bumps" note
   (renovate 4.53.0 pending).
3. **Readonly tier tool list** — the §R2.4 HTTP table (cluster_summary, topology,
   volume_list_detail via /vol/status, volume_lookup, collection_info, node_status,
   file_properties/view/list_folders, health/metrics) + explicit NON-goals (no EC per-shard JSON
   — shell-tier only; no master /status — doesn't exist).
4. **Admin tier tool list + mutation protocol** — plan→confirm_token→apply; shell-runner design
   (piped mode, exit-code law §R2.1, in-session `lock`/`unlock`, stderr parsing, sticky-lastErr
   note); verbs: volume.mark, volume.unmount/mount, volume.vacuum, volume.deleteEmpty, ec.decode
   (per-volumeId), check.disk/fsck (simulate vs -apply), volumeServer.state maintenance mode;
   every mutation annotated destructiveHint + confirm token TTL.
5. **Onprem tier procedure** — per-volume unmount→fix→mount with the lab's .dat/.idx split
   (§R2.3/R2.9-7): hostPath mounts, weed binary in image, idx placement rule, initContainer prior
   art, node targeting.
6. **Server framework conventions** — conditional registration + allowlist visibility (§R2.9-10);
   stateless_http; /healthz custom_route; lifespan startup self-test (§R2.2); httpx2 except-rule;
   error masking decision.
7. **Container + CI** — Dockerfile shape (wekan-mcp template, uid 65532, EXPOSE 8080, console
   entrypoint), `docker-build.yaml` tag law (`:v<run>` + `:main`), CI-primary build gate
   (no-daemon rule), renovate pin.
8. **Deployment wiring** — `hivetools.mcp.*` entries in `services/infra/prod/values.yaml`
   (per-tier env/secrets/podTemplateSpec; onprem volumes), no appset/proxy/chart entries,
   validation commands (`helm lint/template charts/hivetools`, sentinel grep), MCPToolConfig
   option.
9. **Security & credentials** — today auth-free end-to-end (proxy default unauthenticated —
   quote §R2.7); gating decision needed BEFORE enabling admin/onprem routes (OIDC re-enable vs
   enabled:false vs NetworkPolicy); future enableSecurity: cert Secret + security.toml mounts,
   self-test guards.
10. **Fleet registration** — machine-global opencode.json entries
    (`readonly-infra-seaweedfs` → `https://mcp.infra.spencerslab.com/seaweedfs-readonly/mcp`),
    AGENTS.md MCP-table row, wekan-mcp skill-style usage doc follow-up.
11. **Acceptance / Commands** — helm lint+template renders; registry-parity-style tool-count test
    (tests/wekan-mcp precedent); live `tools/list` probe per tier; readonly tier answers match
    the §R2.4 measurements; admin dry-run plan/apply against a canary volume; onprem flow
    rehearsed on a scratch volume.
12. **Open decisions for the owner** — (a) which tiers to register at all pre-OIDC; (b) confirm
    token TTL/shape; (c) EC-shard detail via shell tier vs HTML scrape vs omit; (d) whether
    onprem gets its own card (privilege review) or ships disabled.

### R2.11 Adjacent

- **R1 U6 closed empirically**: master `/collection/info?collection=default` → `{"error":
  "collection default does not exist"}` (live, 2026-11-11) — confirms at the master API level
  that no collection literally named "default" exists; the pool is the unnamed one (empty
  `collection=` is rejected as "collection is required", so the unnamed pool is only queryable
  via shell `_default`/`""` semantics or the admin UI's display alias). R1's source-chain
  conclusion now has live backing.
- Admin `/storage/ec-shards` live content cross-checks R1: volume 1 at 13/14 shards ("Minor
  Issues, 1 missing"), volume 4 at 7/14 ("Degraded") — consistent with R1 §R1.4's
  recoverable/unrecoverable split.
- Master `/vol/status` response (1 MB) is the single richest JSON surface: it equals the union of
  all 8 volume pods' `/status` payloads — one call replaces an 8-pod fan-out.
- Loki label for seaweedfs logs is `app_kubernetes_io_name="seaweedfs"` (no `app` label) — useful
  for the debug skill's log-query recipes; `pod` rides structured metadata, not a stream label.

### R2.12 Sources

Weed 4.50 source (`raw.githubusercontent.com/seaweedfs/seaweedfs/4.50/<path>`, tag ==
deployed `ec8f97935` [T20]):
- [T1] `weed/command/shell.go` (runShell 43-83; SetCommandExitStatus(1) 75-79)
- [T2] `weed/command/command.go` (SetCommandExitStatus/CommandExitStatus 96-115); `weed/weed.go`
  (setExitStatus(CommandExitStatus()) 106; os.Exit path 205-207)
- [T3] `weed/shell/shell_liner.go` (RunShell 24-113: interactive vs piped, sticky lastErr,
  master-connect gate 61-71; processEachCmd 116-155: `error:` stderr print, SetNoLock(false)
  per-command 134-139; log-flag suppression when !Debug 31-34)
- [T4] `weed/shell/commands.go` (CommandEnv 41-61; confirmIsLocked 80-92 `need to run "lock"
  first`; shellLockHolder 118-134)
- [T5] `weed/shell/command_lock_unlock.go` (lock/unlock semantics, blocking, holder message)
- [T6] `weed/security/tls.go` (LoadClientTLS 167-220: five insecure-fallback branches with
  glog.Warningf only; LoadClientTLSFromFile 150-165)
- [T7] `weed/command/fix.go` (UsageLine/Long 30-37 incl. "You Need to stop the volume server";
  flags 39-49; runFix positional args 86-151; SaveToIdx O_TRUNC + append-order comment 186-223;
  doFixOneVolume 225-273; doFixEcxFromShards 275+)
- [T8] `weed/shell/command_volume_unmount.go` (help + required flags + confirmIsLocked +
  VolumeUnmount gRPC); `weed/shell/command_volume_mount.go` (existence in tag tree)
- [T14] `weed/server/master_server.go` (route table 214-233: NO /status; /dir/*, /vol/*,
  /stats/* gated, `{fileId}` catch-all 233)
- [T15] `weed/server/master_server_handlers_admin.go` (dirStatusHandler 43-49; volumeVacuumHandler
  → dirStatus 51-66; volumeStatusHandler 102-107 ToVolumeMap)
- [T16] `weed/server/volume_server.go` (routes 157-173: /status,/healthz,/readyz,/ui,/stats/*,
  NO /dir/config); `weed/server/volume_server_handlers_admin.go` (statusHandler →
  writeJsonQuiet); [T24] `weed/server/common.go` (writeJson marshal-then-write 93-120;
  writeJsonQuiet `error writing JSON status %s %d` 134-139)
- [T23] `weed/admin/handlers/admin_handlers.go` (SetupRoutes auth gate 61-101: authRequired →
  RequireAuth/RequireAuthAPI else "all routes are public"; UI routes 103-159; /api routes
  162-263 incl. /api/files/{view,properties,metadata,list-folders,download} GETs + wrapWrite
  mutations; /health,/metrics unauthenticated 64-67)
- [T11] `seaweed-volume/README.md` (drop-in claim, flags, features incl. TLS, parity testing)
- [T12] `seaweed-volume/MISSING_FEATURES.md` (audit 2026-03-07: P1.3 "No TLS at all", P1.4 fixed
  Sprint 1 ✅, coverage tables); `seaweed-volume/PARITY_PLAN.md` (mount/unmount "needs
  verification" rows)
- [T13] `VOLUME_SERVER_RUST_PLAN.md` (12-phase port plan, critical invariants); repo tree at 4.50
  (`seaweed-volume/`, `rust_binaries_release.yml` building `weed-volume` per tag)

GitHub API (fetched 2026-11-11):
- [T17] PR #11117 (title, merged_at 2026-09-03T05:12:52Z, body: piped-failure motivation, exit-1-
  not-2 rationale, sentry flush, interactive unchanged, test table)
- [T18] Issue #10502 (body: security.toml-without-certs → LoadClientTLS insecure fallback →
  handshake fail → shell exited 0 pre-#11117; timeline: closed by PR #11589 "helm: mount TLS
  certificates in bucket hook" merged 2026-10-04T12:35:08Z)
- [T19] Issue #6139 (body: `volume.unmount`/`volume.mount` usage + metrics-reset symptom;
  timeline: closed 2024-10-22 by commit d38456dc06d354d5c395519fb2f8185b2456a82e)
- [T20] tag ref `refs/tags/4.50` → `ec8f9793502c59ce3381cc4151bfc0806afd92e8`; commit date
  2026-10-25T03:09:42Z, message "4.50"

Wiki: [T21] Volume Management (ed. 2026-10-19: `volume.mount -node -volumeId`, SIGHUP reload,
`volumeServer.state --maintenanceOn` maintenance mode, fix.replication/admin-script context);
[T22] Rust Volume Server (ed. 2026-08-22: `weed-volume` binary, `volume` vs `volume-rust` in the
standard image, amd64/arm64 only, 48/48 RPCs, 109 Go integration tests pass, byte-identical
storage, mTLS "Supported", subtle-difference tables).

FastMCP: [T33] PyPI `fastmcp` JSON (latest 4.1.8 2026-11-10; 4.2.0a1-a4; requires_dist →
fastmcp-slim); [T34] PyPI `fastmcp-slim` 4.1.8 (deps: httpx2>=2.5, mcp>=2.3<3, starlette>=1.0.1,
pydantic>=2.12, uvicorn); [T35] `gofastmcp.com/docs/servers/tools.md` + `/docs/servers/
visibility.md` (Component Visibility New-in-3.0.0; disable/enable names/tags/keys; allowlist
`only=True`; default-enabled; silent-no-match WARNING; key `@` rule; per-session visibility +
2026-07-28 session-less scoping); [T36] `/docs/servers/elicitation.md` (era gate ≤2025-11-25 vs
2026-07-28; SEP-2322/SEP-2575; guard pattern InputRequiredResult New-in-4.0.0; request_state
sealing + RequestStateSecurity multi-replica); [T37] `/docs/getting-started/upgrading/
from-fastmcp-3.md` ("single most likely runtime failure" = ctx.elicit; "FastMCP now uses httpx2
exclusively"; dead `except httpx.` trap; tool-internal HTTP unaffected; truststore/OS-CA change;
logger renames; ctx.set_state non-persistence; -32002→-32602; environment floors); [T38]
`/docs/deployment/http.md` (stateless_http three spellings New-in-2.10.2; sticky-session
warning; custom_route + never-authed NOTE); [T39] `/docs/servers/lifespan.md` (lifespan=
constructor, @lifespan New-in-3.0.0, ctx.lifespan_context, `|` composition); [T40]
`/docs/servers/tools.md` (timeout= New-in-3.0; run_in_thread; mask_error_details; annotations).

ToolHive: [T41] `docs.stacklok.com/toolhive/reference/crds/` index (MCPServer, MCPOIDCConfig,
MCPAuthzConfig, MCPToolConfig + per-resource pages); [T42] `/toolhive/guides-k8s/
migrate-to-v1beta1` (v0.15.0 removals: inline tools → MCPToolConfig toolConfigRef; port renames);
[T43] `/toolhive/guides-k8s/run-mcp-k8s` (updated 2026-11-04: "Authentication is not enabled by
default" verbatim; synthetic local-user identity; podTemplateSpec container `name: mcp`; PVC
mount example; automatic RBAC; restart annotation); [T44] `/toolhive/guides-k8s/auth-k8s`
(oidcConfigRef/authzConfig optional; Cedar via MCPAuthzConfig).

Repo: [T25] `containers/wekan-mcp/{Dockerfile,pyproject.toml}` (python:3.15-slim, uid 65532,
EXPOSE 8080, console ENTRYPOINT, `fastmcp>=4.1,<5` + `httpx>=0.27,<1`); [T26]
`.github/workflows/docker-build.yaml` (triggers, `:v<run_number>` + `:<branch>` tag law, PR
build-only, workflow_dispatch); [T27] `services/dev/prod/values.yaml:228-487` (hivetools.mcp
shape, boards entry, envFrom secret pattern, OIDC-commented posture); [T28]
`services/gpu/prod/values.yaml:672-780` (wekan-readonly WEKAN_MCP_READ_ONLY=true + wekan-admin
two-tier precedent, :v162 pins); [T29] `charts/hivetools/templates/generic-mcpserver.yaml`
(v1beta1 MCPServer, ns default, env/secrets/serviceAccount/podTemplateSpec/volumes/oidc/authz/
toolsFilter fields) + `generic-mcptoolconfig.yaml` (MCPToolConfig) + `services/infra/prod/
values.yaml:323-336` (infra hivetools already live); [T31]
`skills/helm-chart-creation/references/mcp-servers.md` (platform architecture, in-repo image
pinning, spec.volumes hostPath-only note, wekan worked example); [T32] machine-global
`~/.config/opencode/opencode.json` (39-server fleet, `<priv>-<cluster>-<service>` naming,
infra public-ingress vs gpu headless-service URL forms — NOT version-controlled).

Live probes (2026-11-11, read-only): [T9] `readonly-infra-kubernetes` `pods_get
seaweedfs-volume-0` (Go binary command line, `-dir.idx=/idx` split, initContainer fix+mv,
readiness/liveness on /status 15s/90s timeout 30s, image chrislusf/seaweedfs:4.50 digest
c2658820…, restartCount 7, node `infra`); [T10] PVC/PV read for `idx-seaweedfs-volume-0`
(hostPath `/var/lib/rancher/k3s/storage/pvc-0ccb84d1-…_default_idx-seaweedfs-volume-0`); [T30]
Deployment `toolhive-operator` on infra (v0.56.0) + CRD list (14 toolhive CRDs; mcpservers serves
v1alpha1+v1beta1 storage); HTTP GET battery over `seaweedfs-{master,admin,volume}.infra.
spencerslab.com` (§R2.4 table, zero credentials); Loki via `readonly-global-grafana`
(datasource P8E80F9AEF21F6940): churn metric 1,569 lines/h + sample lines with `10.42.0.1`
kubelet peer and `common.go:136` origin.
