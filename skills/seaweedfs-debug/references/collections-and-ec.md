# Collections & EC — mechanism facts

How collections, erasure coding, read-only marks and vacuum work at weed **4.50**
(`ec8f97935`, the deployed build) — the facts repair decisions branch on. Evidence depth:
`RESEARCH.md` §R1 of `.agents/plans/2026/2026-11-feat-seaweedfs-debug-skill/`; every procedure
sequence lives in one normative home: `.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md`
("runbook Phase N" below). Re-verify after any chart/image bump (renovate carries 4.53.0
pending).

## Collections on this cluster

- The big pool is UNNAMED (`Collection=""`). Cause: the four dynamic-CSI StorageClasses —
  `seaweedfs-extra`, `seaweedfs-important`, `seaweedfs-backups`,
  `seaweedfs-backup-important` (`services/infra/prod/templates/pvc-storage-classes.yaml`) —
  carry no `collection` parameter, so everything they provision lands nameless. Named pools
  (`logs`, `media`, `documents`, `backups` buckets, …) exist only where a bucket or
  collection is configured explicitly.
- 4.50 has NO defaultCollection concept anywhere in filer/command source: the pool is the
  empty name itself, not a collection that happens to be called "default" (§R1.4).

## The display-alias trap

The admin UI RENDERS the empty name as "default": the dashboard stats and the
collection/volume pages substitute `collection = "default"` (in-source comment: "Default
collection for volumes without explicit collection"), the EC page's HTTP filter
special-cases `filterCollection == "default"` against `volumeCollection == ""`, and shell
`volume.list` prints `"" (default)`. None of that is a matchable name: every shell
`-collection` flag is a LITERAL matcher (`weed-shell.md` law; §R1.4). So an admin-UI warning
reading "in collection \"default\"" means the unnamed pool, and typing `default` into a
shell flag matches nothing — silently. Empirical backing: master
`/collection/info?collection=default` answers `collection default does not exist`, while an
empty param answers `collection is required` — the unnamed pool is only reachable via the
shell `""`/`_default` semantics or the UI alias (§R2.11).

## EC arithmetic — RS(10,4)

- 10 data + 4 parity = 14 shards per group; a shard is one volume server's slice.
- `ec.decode` is NOT recovery: it interleaves the 10 DATA shards back into a regular volume
  — ALL 10 must be present somewhere; parity shards are optional and never used to
  reconstruct on the decode path. One data shard missing →
  `volume <id> cannot be decoded: data shards are missing and no decoded volume exists to
  finish` (§R1.4).
- `ec.rebuild` IS the recovery step: RS reconstruction from ANY ≥10 of 14 shards, then
  decode. It is the mandatory pre-step for a group whose missing shards include a data
  shard. At ≤9 of 14 shards a group is mathematically unrecoverable — no tool changes that
  arithmetic; purging the remnants is the only end state (runbook Phase 2).
- Batch decode aborts on the first failing group (ascending volume id; the loop returns the
  error, later groups never run) — always decode per `-volumeId`:
  `ec.decode -collection="" -volumeId <vid>`. Exit 0 alone does not prove every group was
  decoded.
- A group whose index holds no live entries decodes to NOTHING: its shards are purged and no
  volume is created — husk groups vanish cleanly and quietly (§R1.4).
- Placement math makes EC impossible here by construction: 14 shards must land on distinct
  servers, but the cluster has 8 volume servers, one rack, one node — the admin loop thrashes
  on `placed with relaxed placement constraints` forever (see error-signatures.md; runbook
  Phase 0). With fault tolerance the floor is ≥15 distinct-fault-domain servers for 10+4 —
  single-node infra never qualifies (runbook Phase 5).

## EC shard inventory surfaces

| Surface | What it gives | Notes |
|---|---|---|
| admin `/storage/ec-shards` | every group with per-shard placement | HTML (templ): rows carry `data-volume-id`, health labels like "Minor Issues" / "Degraded"; no embedded JSON — scrape is version-brittle |
| admin `/storage/ec-volumes/{id}` | one group's shard detail | HTML |
| admin `/api/admin` | `total_ec_volumes` / `total_ec_shards` totals | JSON, cheap (mcp-server-spec.md §3) |
| shell `volume.list` | EC shard lines per server, per-volume stats | the shard-role answer for the decode-vs-rebuild branch (probe U5) |
| master `/dir/status` | `EcShards` count per node | JSON topology view |

## Replication codes

The placement field is a tiered "extra copies" count, datacenter / rack / node: each digit
requests additional copies at that tier, and total copies = 1 original + sum of digits.
Replication `001` therefore means EXACTLY 2 copies on distinct nodes — a two-location `001`
volume counts as replicated to `volume.check.disk` (both its repair classes apply). The
durability caveat is fault domains, not digits: with every "server" a pod on one host, `001`
copies share a fate — one reboot is one correlated failure for the whole pool.

## Read-only mechanics (§R1.2 condensed)

The verdict is `noWriteOrDelete` ∥ `noWriteCanDelete` ∥ `diskSpaceLow`. Five trigger sites:

1. **Load-time structural check**: `.idx` references past the `.dat` end (crashed batched
   write) → runtime flag, re-detected on EVERY load while the pair is inconsistent.
2. **Disk-space-low**: free space under the configured floor (chart sets
   `minFreeSpacePercent: 2`) → runtime-only, self-clears on the next disk probe once space
   recovers; the auto-vacuum sweep still compacts this kind of read-only replica.
3. **IO-error quarantine**: sustained EIO past tolerance → runtime flag, sticky, the replica
   stops announcing to the master; recovery only via writable-mark.
4. **Failed recovery / unavailable**: persists `ReadOnly=true` to `.vif` AND writes a
   `.unavailable` marker; `volume.mark -writable` refuses until the marker is verified and
   removed by hand.
5. **Operator mark** (`volume.mark`): always persists to `.vif`.

- Persistence split: the `.vif` (volume-info file) is the crash-durable artifact — sites 4
  and 5 survive restarts; sites 1 and 2 are re-evaluated at load/probe (site 3 is sticky at
  runtime). "A restart cleared the mark" means it was a runtime kind.
- `volume.mark -writable` does four things: reopens the `.idx` for write, clears the runtime
  flags, rewrites the `.vif` (`ReadOnly=false`), and notifies the master so writes route
  there again. It cannot fix WHY site 1 re-marks — the idx/dat pair must actually be
  consistent or the next restart re-marks it.
- `-readonlyCanDelete` is the drain mark: writes refused, deletes still accepted, so expiring
  data compacts the volume away over time.
- NO self-heal exists: the master simply stops routing writes to a read-only replica;
  `volume.fix.replication` only ADDS missing replicas (never merges diverged content, never
  picks a read-only replica for deletion); `volume.check.disk` skips read-only replicas.
  Persisted marks need explicit `volume.mark -writable`.
- `check.disk -fixReadOnly` is EXPERIMENTAL and uni-directional — source is a random
  writable replica and the read-only side's unique needles are never propagated back: never
  on diverged pairs (§R1.2, runbook Phase 3).

## Vacuum mechanics (§R1.3 condensed)

- Master auto-sweep: every `vacuumIntervalSeconds` = **840 s (14 min)** + 0–120 s jitter,
  leader-master only, default `garbageThreshold` 0.3; skips read-only replicas except
  disk-space-low ones. It runs independent of the admin connection, gated only by
  `volume.vacuum.disable`.
- Explicit `volume.vacuum` without `-volumeId` is the same sweep (also skips read-only);
  name a read-only volume with `-volumeId <vid>` to vacuum it anyway; `_default` selects the
  unnamed pool. `volume.vacuum.disable` / `volume.vacuum.enable` wrap long repair windows —
  the runbook's Phase 3 block does exactly that.
- `volume.deleteEmpty -quietFor=24h -apply` husk rules: candidate is non-remote, writable or
  can-delete-marked, and (size ≤ superblock OR `0 < FileCount ≤ DeleteCount`), quiet for the
  whole period. Read-only, not-canDelete husks are SKIPPED — mark first. The automatic sweep
  deletes empties only when `vacuumDeleteEmptyAfterSeconds > 0` (default 0 = never).
- **Heal BEFORE vacuum.** Vacuuming a diverged replica pair hardens the divergence: it drops
  tombstones per-replica (delete marks that never reached the other side become
  unsyncable forever), bumps the compacted replica's compaction revision — closing the rev-0
  resurrection gate permanently — and lets reads routed to the replica that missed a delete
  return already-deleted files (§R1.1).
- Phantom verbs: `vacuum.submit.all` and `delete.emptyVault` DO NOT EXIST in 4.50 — no shell
  verb, no master route (master HTTP exposes only `/vol/vacuum`, which runs a full sweep and
  returns immediately). Guide-era names; check `help` on the running build before pasting
  anything learned from a guide.

## The "never EC again" posture

- Current state: `WEED_MAINTENANCE_ERASURE_CODING_ENABLED=false` on the admin server
  (runbook Phase 0; deploys with the HUMAN `argocd app sync infra-seaweedfs`).
- `WEED_MAINTENANCE_ENABLED` is deliberately UNSET: the maintenance system also hosts the
  auto-vacuum sweep — switching maintenance off freezes the delete-backlog drain.
- `ec_balance` has no admin.toml/env key of its own; its residual proposals die only when the
  EC groups themselves are gone (runbook Phases 1–2), so log-noise expectations during the
  repair window are in the runbook, not here.
- Prevention (never accidentally EC again): give the four dynamic-CSI StorageClasses explicit
  `collection` parameters and/or pin per-path options with `fs.configure`, so the idle
  scans have nothing nameless to encode — plan in runbook Phase 5.
