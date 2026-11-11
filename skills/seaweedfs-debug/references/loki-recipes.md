# Loki recipes — debugging SeaweedFS from its own log store

LogQL for the lab's weed logs, distilled from the 2026-11 incident week. The store is
self-referential on purpose: this Loki keeps its chunks AND index on SeaweedFS (bucket
`logs`) — every query here can touch the very objects it is diagnosing, which is Rule 1
below. Log lines are weed strings at **4.50** (`ec8f97935`): wording churns between
versions, re-verify literals after any bump (renovate carries 4.53.0 pending).

What each signature MEANS (and the one next action) lives in `error-signatures.md`; this
file only teaches how to measure them over Loki.

## Label reality (measured 2026-11)

- SeaweedFS pods carry the stream label `app_kubernetes_io_name="seaweedfs"` — there is
  **no `app` label**; a selector like `{app="seaweedfs"}` silently returns nothing.
- `pod` rides **structured metadata**, not a stream label. Match it AFTER a pipeline
  stage (`| pod=~"seaweedfs-volume-.*"`), never inside the `{…}` selector. Aggregating
  `by (pod)` after such a pipe is the live-proven shape (measured per-pod split below).
- Loki's own logs (the consumer side of this loop) sit on the monitoring cluster:
  `{cluster="monitoring", app_kubernetes_io_name="loki"}`. Label sets differ per
  deployment — verify a stream's labels first, never assume this one.
- Datasource access: agents run these through `readonly-global-grafana` (read-only,
  agent-safe). The Loki datasource UID is environment-specific fleet config — resolve it
  at runtime via the datasource listing rather than hardcoding a uid anywhere.

## Self-query noise — the rule that shapes every window

A verification query served by this Loki GETs the index objects stored ON SeaweedFS.
Querying a corrupt window REGENERATES the error lines it is measuring — and while the bad
object lives, each covering query re-triggers the s3 gateway's retry loop (that feedback
loop is why the 2026-11 loop looked like it "respawned" after a restart). Therefore:

1. Measure RATES over fresh windows (`count_over_time(… [10m])`, `[1h]`), never historical
   totals spanning a known-bad window.
2. Post-repair verification: a window that STARTS after the fix time — a seven-day "since"
   re-enters the bad range and shows phantom failures.
3. Prefer weed-side counters where reachable: the s3 pod's `retry reading` grep
   (`kubectl … logs deploy/seaweedfs-s3 | grep -c "retry reading"` → 0 after the fix) is
   the human-tier equivalent in runbook Phase 4.

## Paste-ready queries

Each block: query → what it proves.

**Churn baseline — per-pod kubelet-probe noise rate:**

```logql
sum(count_over_time({app_kubernetes_io_name="seaweedfs"} |= "error writing JSON status" [1h])) by (pod)
```

Proves: benign RST noise, NOT a health signal — measured steady state 1,569 lines/h
cluster-wide, 184–213 per volume pod (≈ one per 18 s/pod; incident-era ~1,709/h was the
same baseline). A lopsided or exploding per-pod split is what actually deserves a look.

**Retry-loop presence (s3 side) — fresh window:**

```logql
sum(count_over_time({app_kubernetes_io_name="seaweedfs"} | pod=~"seaweedfs-s3-.*" |= "retry reading" [15m]))
```

Proves: the gateway is actively re-fetching a lost fid right now. A nonzero fresh-window
count means a live filer entry still references the dead chunk — find the carrier, not
the fid's volume. Zero after a repair (evaluated in a window starting after it) = loop
gone.

**Churning-fid counter — which fid the loop is stuck on:**

```logql
topk(10, sum by (fid) (count_over_time({app_kubernetes_io_name="seaweedfs"} |= "retry reading" | regexp "(?P<fid>[0-9]+,[0-9a-f]+)" [24h])))
```

Proves: the per-signature distinct-fid pattern. One fid with hundreds of hits = the live
carrier (2026-11: the loop was pinned to `1982649,ffcb4cee151f1745a60afc08`); a long tail
of one-hit fids = transient/cancelled reads or already-gone casualties. Map the fid →
object path with the admin `/api/files/properties` trick (endpoints-and-probes.md).

**Hang carrier from the querier's side (weed logs the GET):**

```logql
{app_kubernetes_io_name="seaweedfs"} |= "failed to stream logs/index"
```

Proves: a Loki querier is reading a corrupt/lost TSDB index object stored on SeaweedFS —
the GET hangs, the querier times out and re-issues. The key recurring across successive
sweeps is the live bad file (the one to `fs.rm`, runbook Phase 4); one-off hits are cancel
noise. 2026-11 reference point: the `.tsdb.gz` carrier key dominated the locating sweep
(251 hits, the only persistent offender — that sweep itself was the self-noise pattern,
each covering query re-triggering the loop).

**Read-only marks (volume side, current):**

```logql
{app_kubernetes_io_name="seaweedfs"} |~ "is read only|marking readonly"
```

Proves: which volume ids are refusing writes NOW and since when (`marking readonly` =
load-time re-detection, `is read only` = serving-side refusals). Distinguish a persisted
`.vif` mark from a runtime re-mark via the idx>dat query below.

**idx>dat structural re-detection since the last restart:**

```logql
{app_kubernetes_io_name="seaweedfs"} |= "idx references end="
```

Proves: an `.idx` referencing past the `.dat` end — re-detected on EVERY load while the
pair is inconsistent, so `volume.mark -writable` will not survive the next restart
(collections-and-ec.md, trigger site 1). Window from the pod's restart time.

**Filer deletion-queue drop-outs:**

```logql
{app_kubernetes_io_name="seaweedfs"} | pod=~"seaweedfs-filer-.*" |= "max retry attempts (10) reached"
```

Proves: deletion-queue entries stuck behind read-only volumes gave up after 10 retries
and fell to the durable ledger. There is no Prometheus metric for this queue — the logs
ARE the designed surface (error-signatures.md).

**EC churn trio (admin-side proposals):**

```logql
{app_kubernetes_io_name="seaweedfs"} | pod=~"seaweedfs-admin-.*" |~ "relaxed placement|EC Detection: stopping early|invalid task ID"
```

Proves: the EC proposal loop is thrashing (placement impossible on this topology; task
IDs can never persist). Fresh-window rate is the Phase-0 verification: encode churn
→ ~0 after the admin restart; `ec_balance` lines (`invalid task ID`) keep proposing
until the groups themselves are gone (Phases 1–2) — runbook Phase 0 item 2 is
normative on that split.

**Vacuum skips (husk survivors):**

```logql
{app_kubernetes_io_name="seaweedfs"} |= "skip vacuuming: not enough copies"
```

Proves: the 14-min auto-sweep is refusing under-replicated volumes — the named ids are
husk candidates that no sweep will ever collect (collections-and-ec.md).

**NoSuchKey sweep (Loki's own side — losses vs live loop):**

```logql
{cluster="monitoring", app_kubernetes_io_name="loki"} |~ "NoSuchKey"
```

Proves: measured over FRESH windows only: steady = recorded data loss already taken;
growing = something still references lost objects (go find the driver on the weed side).

**Failed-to-load-chunk grep (the already-gone casualty face):**

```logql
{cluster="monitoring", app_kubernetes_io_name="loki"} |~ "NoSuchKey" |~ "load chunk"
```

Proves: the `parallel_chunk_fetch` casualty — the chunk object's filer entry is gone, so
the read fails fast and stays failed. This face is NOT the retry loop's driver (that is
the live-entry `failed to stream logs/index` face above); the properties probe
confirming `filer: no entry is found in filer store` for the path seals it.

## Post-repair verification window

After the fix (deletes, marks, the human's s3 rollout restart), evaluate the retry and
NoSuchKey queries in windows that begin AFTER the fix timestamp — e.g. presence at 15 m,
30 m, 2 h:

```logql
sum(count_over_time({app_kubernetes_io_name="seaweedfs"} | pod=~"seaweedfs-s3-.*" |= "retry reading" [10m]))
```

All fresh-window rates at zero (churn baseline aside — it never goes to zero and does not
need to) = done. Anything nonzero in a post-fix window is still live; do not conclude
from historical counts spanning the corrupt range.
