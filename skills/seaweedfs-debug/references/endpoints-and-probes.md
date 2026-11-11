# HTTP endpoints & probes — the operator debug surface

What to GET during an incident, what the answer means, and what it costs. Every size and
timing is a live measurement (2026-11-11, zero credentials, GET only) of the deployed weed
**4.50** (`ec8f97935`) lab — `RESEARCH.md` §R2.4 of
`.agents/plans/2026/2026-11-feat-seaweedfs-debug-skill/` carries the [T#]-anchored detail.
Route names exist at 4.50 and churn between versions — re-verify after any bump (renovate
carries 4.53.0 pending) before trusting a row.

Sibling split: `mcp-server-spec.md` §3 is the BUILD view (endpoint → MCP tool mapping);
this file is the OPERATOR view (probing and interpreting during an incident). Route
existence and the auth model are stated in both on purpose — each is load-bearing for its
audience; what lives only here is the interpretation and curl shapes.

## Base URLs

Lab public ingress (all three tiers reachable anonymously as configured — see *Auth posture*):

| Component | URL |
|---|---|
| master | `https://seaweedfs-master.infra.spencerslab.com` |
| admin | `https://seaweedfs-admin.infra.spencerslab.com` |
| filer | `https://seaweedfs-filer.infra.spencerslab.com` |
| volume | `https://seaweedfs-volume.infra.spencerslab.com` (public subdomain → ONE pod; which pod answers is not controllable — per-pod access is in-cluster only) |

In-cluster dial strings (what the workloads actually use — paste-block context, not agent
reach; pod exec is human-tier):

- master: `seaweedfs-master.default:9333`
- filer client: `seaweedfs-filer-client.default:8888`
- s3 gateway: `seaweedfs-s3.default.svc.cluster.local:8333`

## Master routes (ns `default`, port 9333)

| Route | Answers | Measured size / time | Debug use |
|---|---|---|---|
| `/` | HTML volume table + Up Time | 9.3 KB / 16 ms | quickest "is the leader up, since when" glance |
| `/dir/status` | JSON `{Version,TopologyId,Topology}`: DC→rack→node with `Volumes`, `EcShards`, `Max`, range-compressed `VolumeIds`; proxies to the leader | 8.8 KB / 24 ms | cluster shape + per-node EC shard counts WITHOUT the 1 MB payload; the `Version` field is the cheap version check |
| `/vol/status` | JSON `{Version,Volumes}` = `Topo.ToVolumeMap()`: per-node arrays of the SAME VolumeInfo rows as shell `volume.list` (Id, Collection, Size, DeletedByteCount, FileCount, DeleteCount, CompactRevision, ReadOnly, ReadOnlyCanDelete, ReplicaPlacement, Ttl, ModifiedAtSecond, DiskId) | **1.0 MB / 57 ms** | the full detail union of all 8 volume pods in ONE call — replaces the 8-pod `/status` fan-out; the HTTP face of the read-only sweep (`ReadOnly` filter) and of the `CompactRevision` rev-0 gate (collections-and-ec.md) |
| `/dir/lookup?volumeId=<vid>` | JSON replica locations: `url` (in-cluster), `publicUrl`, `grpcPort` | 370 B | where does the master think the copies of this volume live |
| `/collection/info?collection=<name>` | JSON `{Collection,FileCount,TotalSize,UsedSize,Version,VolumeCount}` | 137 B | **named collections only** (`logs` measured 528,569 files / 675 GB). `default` → `collection default does not exist`; empty → `collection is required` — the display-alias trap has an HTTP face too: the lab's unnamed pool is NOT queryable here (collections-and-ec.md) |
| `/healthz`, `/readyz` | empty, 200 | ~0 B / 13 ms | cheap liveness |

**Do-not-use rows (the two missing-endpoint negatives, measured):**

- master `/status` → **404** `volume id status not found: unknown volume id status` — the
  route does not exist in 4.50; the `{fileId}` redirect-handler catch-all swallows the path.
  Use `/dir/status` + `/vol/status` instead.
- volume `/dir/config` → **400** (body empty) — does not exist; volume routes are only
  `/status`, `/healthz`, `/readyz`, `/ui/index.html`, `/stats/*` (flag-gated), `/` —
  `/dir/*` is master namespace.

## Admin routes (the dashboard server)

| Route | Answers | Measured size / time | Debug use |
|---|---|---|---|
| `/api/admin` | JSON cluster summary: total_volumes (3,089 measured), total_chunks (49.3 M), total_size (53.7 TB), master/volume/filer/s3 node lists, datacenters, `total_ec_volumes`/`total_ec_shards`, trends, tier_stats | 16 KB / 24 ms | cluster totals + EC health in one cheap call — the first probe of any sweep |
| `/api/cluster/topology` | JSON nodes with volumes/max_volumes/disk_usage | 7.7 KB / 14 ms | siblings: `/api/cluster/volumes` 3.6 KB, `/api/cluster/masters` 209 B, `/api/config` 372 B |
| `/api/files/properties?path=<url-encoded>` | JSON file/dir metadata incl. the chunk list with fids | ~350 B | the fid→carrier probe — worked below. Gotchas: URL-encode the path (`%2F` for each `/`), pass NO trailing slash, and see the 500 caveat below |
| `/api/files/view?path=…`, `/api/files/list-folders?path=/buckets` | JSON metadata / folder list | ≤300 B | same path rules as properties; list-folders answers `{"folders":[…]}` (12 buckets measured) |
| `/health` | JSON | 16 B / 19 ms | liveness |
| `/metrics` | Prometheus text | 19 KB | route registered BEFORE the auth gate — unauthenticated even if auth is later configured |
| `/storage/ec-shards` | HTML EC group table | 18 KB | human eyes only: templ-rendered, NO embedded JSON (rows carry `data-volume-id`; measured live: vol 1 at 13/14 "Minor Issues", vol 4 at 7/14 "Degraded"). Scrape is version-brittle — totals come from `/api/admin`, per-node counts from `/dir/status` |
| `/storage/ec-volumes/<id>`, `/storage/volumes`, `/cluster/volume-servers` | HTML detail pages | 171 KB default (pageSize honored on `/storage/volumes`), 32.8 KB | human eyes; `/vol/status` beats all of them for machine parsing |

## Volume-server routes (per pod, port 8080)

| Route | Answers | Measured size / time | Debug use |
|---|---|---|---|
| `/status` | JSON `{DiskStatuses,Version,Volumes[]}` for THIS node | 98–156 KB / 20–50 ms (5 samples) | single-node detail on demand (e.g. DiskStatuses free space); for anything multi-node use master `/vol/status` instead — one call, same union |
| `/healthz`, `/readyz` | liveness | unmeasured | cheap |

The `/status` churn, so it is never mistaken for a signal:
`error writing JSON status /status 200: … connection reset by peer` at ~1.5–1.7k lines/h
cluster-wide is BENIGN kubelet-probe RST noise (readiness 15 s + liveness 90 s poll
`/status`; the probe client closes with the body unread and the server-side final write
fails). Never alert on it. Two client rules follow: read response bodies to completion —
an early disconnect ADDS a line — and never fan out to 8 volume `/status` calls when one
master `/vol/status` answers the same union (8× payload + 8× log-line risk for nothing).

## The properties chunk-list trick (worked)

Mapping a lost fid back to the live object that carries it — the decisive probe of the
2026-11 incident:

```bash
curl -sS "https://seaweedfs-admin.infra.spencerslab.com/api/files/properties?path=%2Fbuckets%2Flogs%2Findex%2Floki_index_20765%2Ffake%2F1794147797505872010-compactor-1794085698030-1794147325922-a373bee8.tsdb.gz"
```

- URL-encode the path (every `/` becomes `%2F`) and pass **no trailing slash**: `/buckets/logs/`
  answers **500** `filer: no entry is found in filer store` — byte-identical text to the
  genuine missing-entry answer (error-signatures.md, two-face row). A missing `path` param → 400.
- The response lists the object's chunks with their fids, so: fid
  `1982649,ffcb4cee151f1745a60afc08` → this `.tsdb.gz` object → the s3 retry loop's carrier.
  A single-chunk object is proven here before any `fs.rm` decision (nothing else shares it).
- The reverse map (fid → path) has NO HTTP endpoint: candidate object paths come from the
  log side (`failed to stream logs/index` / s3 retry lines — loki-recipes.md), then this
  probe confirms presence and chunk count.

## Auth posture — agent-safe, and a standing caveat

Every route above answered anonymously (measured 2026-11-11): the admin server has no
user/password configured ("all routes are public" branch), and master `/dir/*`,`/vol/*`
sit behind `guard.WhiteList` — empty allowlist = open. **Read-only probing of these
endpoints is therefore agent-safe** and is what agents contribute while repairs stay
human-run. The same fact is the security caveat for anything built in front of these
routes: exposure is inherited verbatim — see `mcp-server-spec.md` §9 (gate mutating tiers
before exposing them). If `enableSecurity` ever lands, this section's "anonymous" reading
goes stale with it.

## Curl shapes (GET only)

```bash
M=https://seaweedfs-master.infra.spencerslab.com;  A=https://seaweedfs-admin.infra.spencerslab.com
curl -sS "$M/dir/status"                          # version + per-node EC shard counts
curl -sS "$M/vol/status" > /tmp/vol_status.json   # 1 MB detail union; parse ReadOnly / CompactRevision
curl -sS "$M/dir/lookup?volumeId=1982649"         # replica locations of one vid
curl -sS "$M/collection/info?collection=logs"     # named-pool totals
curl -sS "$A/api/admin"                           # cluster totals incl. EC counts — first call of a sweep
curl -sS -o /dev/null -w '%{http_code}\n' "$M/healthz"
```

Prefer the cheap trio (`/api/admin` + `/dir/status` + targeted `/dir/lookup`) for routine
state; pull the 1 MB `/vol/status` only when per-volume fields (read-only marks,
compaction revisions, delete backlog) are actually the question.
`scripts/health-probe.sh` runs exactly this sweep and prints PASS/WARN.

## What is shell-only (no HTTP equivalent at 4.50)

`volume.fsck`, `volume.check.disk` (simulate and `-apply`), EC **per-shard** role detail
(`volume.list` prints the shard lines), `cluster.ps`, `volumeServer.state` queries. All of
it runs inside `weed shell` from the master pod — human-paste blocks under the
`weed-shell.md` discipline (lock-first law, heredoc binding, `-collection` matcher);
repair sequences have one normative home:
`.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md`.
