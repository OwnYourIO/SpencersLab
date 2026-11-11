# seaweedfs-mcp — build spec (verified against weed 4.50)

Build spec for WeKan card `HhiinjT5hdi8D6fCY`: a FastMCP server exposing SeaweedFS
operations at three privilege tiers from one image. `skills/seaweedfs-debug/references/mcp-server-spec.md`
is the pointer target named in that card's description — keep the path byte-exact if this
file ever moves.

Provenance: distilled from `RESEARCH.md` §R2 of
`.agents/plans/2026/2026-11-feat-seaweedfs-debug-skill/`. Source labels used below resolve
there: `[T#]` in §R2.12, `[S#]` in §R1.11. Anchors written `R2.x` point at the §R2
subsections — read the anchor before contradicting a claim. This is a reference for the
build, not a research log: every claim states the verified fact at the deployed build.

**Verified pins (all measurements 2026-11-11):**

- SeaweedFS server: weed **4.50**, build `ec8f97935` — tag `4.50` resolves to
  `ec8f9793502c59ce3381cc4151bfc0806afd92e8` and equals the deployed
  `chrislusf/seaweedfs:4.50` image (digest `c2658820…`; `/status` Version
  `"30GB 4.50 ec8f97935"`) [T20][T9].
- FastMCP: **4.1.x**, verified at **4.1.8** (PyPI, 2026-11-10) [T33]; pin
  `fastmcp>=4.1,<5`, exactly as `containers/wekan-mcp/pyproject.toml` does [T25].
- ToolHive: CRD API **v1beta1** (storage version on the live cluster), operator
  **v0.56.0** [T30][T41].
- Framework floors: Python ≥3.10, pydantic ≥2.12, `mcp>=2.3,<3`, `httpx2>=2.5.0` [T33][T34].

**Standing rule — re-verify on bump.** Every command shape, route, and payload size here
was verified at 4.50. Renovate already carries a `seaweedfs-4.x` bump to 4.53.0: on every
chart or image bump, re-run the §11 probes and update §3–§5 before trusting them again.

---

## 1. Goal & scope

Build `containers/seaweedfs-mcp` (FastMCP `>=4.1,<5`, Python ≥3.10) serving SeaweedFS
4.50 ops over MCP. Three modes — `readonly` / `admin` / `onprem` — from ONE image, mode
selected by env, the wekan-mcp precedent [T25][T28]. Mode gating is conditional tool
registration, not runtime hiding (§6). Out of scope: filer write APIs, the S3 data plane,
operating the Rust volume server (§5, informational).

**Read §9 before exposing `admin` or `onprem`: the ToolHive proxy authenticates nobody by
default and every weed endpoint behind it is anonymous.**

## 2. Verified-facts baseline

- Live surface probes (GET, zero credentials, ~01:35 UTC 2026-11-11) ran through the
  public ingress against `seaweedfs-{master,admin,volume}.infra.spencerslab.com`; shell
  laws read from weed source at tag 4.50 [T1]–[T8]; FastMCP facts from gofastmcp.com docs
  + PyPI [T33]–[T40]; ToolHive facts from docs.stacklok.com + live CRD/operator reads
  [T30][T41]–[T44].
- The lab's cluster state that pins these facts (8 volume pods, collection `logs` EC
  groups, ToolHive operator v0.56.0 on infra) is described in §R2 of the provenance file.

## 3. Readonly tier — pure-HTTP surface

No shell, no subprocess, no writes: the whole readonly tier is anonymous GETs measured at
4.50. Sizes are `size_download` bytes, times curl totals [T14]–[T16][T23].

| Suggested tool | Backend | Size / time (2026-11-11) | Payload |
|---|---|---|---|
| `cluster_summary` | admin `/api/admin` | 16 KB / 24 ms | total_volumes, total_chunks, total_size, node lists, datacenters, `total_ec_volumes`/`total_ec_shards`, trends, tier_stats |
| `cluster_topology` | admin `/api/cluster/topology` | 7.7 KB / 14 ms | nodes with volumes, max_volumes, disk_usage; siblings `/api/cluster/volumes` 3.6 KB, `/api/cluster/masters` 209 B, `/api/config` 372 B |
| `volume_list_detail` | master `/vol/status` | **1.0 MB / 57 ms** | `{Version,Volumes}` = `Topo.ToVolumeMap()` — the SAME VolumeInfo fields as shell `volume.list` per node (Id, Collection, Size, DeletedByteCount, FileCount, DeleteCount, CompactRevision, ReadOnly, ReadOnlyCanDelete, ReplicaPlacement, Ttl, ModifiedAtSecond, DiskId). One call is the union of all 8 pods' `/status` — it replaces the fan-out (R2.11). Filter `ReadOnly` in-tool for the read-only-mark listing |
| `topology_overview` | master `/dir/status` | 8.8 KB / 24 ms | `{Version,TopologyId,Topology}` DC→rack→node with `Volumes`, `EcShards`, `Max`, range-compressed `VolumeIds`; proxies to leader |
| `volume_lookup` | master `/dir/lookup?volumeId=` | 370 B | replica `url`, `publicUrl`, `grpcPort` |
| `collection_info` | master `/collection/info?collection=` | 137 B | `{Collection,FileCount,TotalSize,UsedSize,Version,VolumeCount}` — NAMED collections only. `default` → `collection default does not exist`; empty → `collection is required`. The lab's main pool is the UNNAMED one and is NOT queryable here — shell `_default`/`""` semantics or the admin UI alias are the only views (R2.11) |
| `node_status` | volume `/status` | 98–156 KB / 20–50 ms | `{DiskStatuses,Version,Volumes[]}` — per-node, on demand only; prefer `volume_list_detail` |
| `file_properties` / `file_view` / `list_folders` | admin `/api/files/properties?path=` (siblings `/api/files/view`, `/api/files/list-folders`) | ≤1 KB | file/dir metadata. Gotcha: pass NO trailing slash — `/buckets/logs/` → 500 `filer: no entry is found in filer store`; missing `path` → 400 |
| `health` | admin `/health` 16 B; master `/healthz` `/readyz` ~0 B (volume also serves `/healthz` `/readyz`, unmeasured) | ≤20 ms | cheap liveness reads |
| `metrics` | admin `/metrics` | 19 KB | Prometheus text — registered before the auth gate, so unauthenticated even if auth is later configured [T23] |

**Do-not-use routes (the two missing-endpoint negatives).** Neither exists in 4.50; drop
them from any tool design [T14][T16]:

- master `/status` → **404** `volume id status not found: unknown volume id status` — the
  `{fileId}` redirect-handler catch-all swallows the path.
- volume `/dir/config` → 400 — volume routes are only `/status`, `/healthz`, `/readyz`,
  `/ui/index.html`, `/stats/*` (flag-gated, 404 here), `/`; `/dir/*` is master namespace.

**`/status` churn is not a health signal.** `error writing JSON status /status 200: …
connection reset by peer` runs ≈1,569–1,700 lines/h cluster-wide (live count 2026-11-11;
incident-era ~1,709/h was the same steady state). Cause: kubelet polls volume `/status` as
readiness (15 s) and liveness (90 s); the probe client closes with the body unread, the
server-side `writeJson` fails its final write, glog logs one line [T9][T24]. Responses
complete in 20–50 ms — `/status` is CHEAP. Rules: never alert on these lines; read
response bodies to completion (an early disconnect adds a line); one master `/vol/status`
or admin `/api/*` beats fanning out to 8 volume `/status` (1 MB total + 8× log-line risk).

**Auth posture.** Everything above is anonymous as configured: admin with no
user/password set logs *"No authentication required - all routes are public"* [T23], and
master `/dir/*`,`/vol/*` sit behind `guard.WhiteList` — empty allowlist = open [T14]. An
MCP server in front of these endpoints inherits this exposure verbatim (§9).

**Shell-tier-only surfaces (no JSON HTTP equivalent at 4.50).** `volume.fsck`,
`volume.check.disk` (simulate), EC per-shard detail (`volume.list` prints the shard lines),
`cluster.ps`, `volumeServer.state` queries. EC shard detail over HTTP exists ONLY as
templ-rendered HTML (`/storage/ec-shards`, `/storage/ec-volumes/{id}` — rows carry
`data-volume-id`, no embedded JSON); scrape is brittle across versions. Expose EC totals
(`/api/admin`) + per-node counts (`/dir/status`) in the readonly tier; route shard-level
detail through the admin tier's shell or omit it (open decision, §12c).

## 4. Admin tier — shell verbs + plan→confirm_token→apply

Drive `weed shell` as a subprocess: `printf '<cmds>\n' | weed shell -master=<m:9333>`.
Sync Python tools run in a threadpool by default (`run_in_thread=True`), so a blocking
subprocess is concurrency-safe; set per-tool `timeout=` [T40].

**Exit-code law (PR #11117, merged 2026-09-03, in 4.50) [T1][T2][T3][T17].**

- A piped run **exits 1** on ANY failed command — trust the exit code. Status is recorded
  (highest wins) and applied after main's deferred flushes, so logging still completes.
- `lastErr` is **sticky**: a later success never clears an earlier failure; one failed
  command poisons the whole run's exit status. Parse stderr for per-command detail — each
  failure prints `error: <detail>`; unknown commands error too.
- The law is piped-mode only: an interactive session shows the error and still exits 0.
  Usage/syntax errors exit **2**, failures **1**.

**Shell lock law (the extra gate) [T3][T4][T5].** Mutation verbs (the family calling
`confirmIsLocked` — `volume.unmount` verified) fail with `need to run "lock" first to
continue` unless the session holds the cluster-wide exclusive admin-shell lock. Therefore:

- Wrap every mutation in ONE piped session: `lock` / `<cmd>` / `unlock` —
  e.g. `printf 'lock\nvolume.unmount -node <host:port> -volumeId <id>\nunlock\n' | weed shell -master=…`.
- `lock` BLOCKS while another holder has it — the admin server's maintenance worker or a
  human shell. The runner must handle the wait and surface `waiting for lock held by …`;
  the holder is queryable via master `GetAdminLockStatus` [T5].
- The dry-run `noLock` stance resets per command and never leaks into the next [T3].
- Read-only verbs never lock.

**Confirmation protocol: plan→confirm_token→apply.** Keep the guide's design — it is
era-proof. Do NOT implement confirmation with `ctx.elicit`: elicitation is era-gated in
FastMCP 4.0 — it works only on handshake-era connections (≤ 2025-11-25) and RAISES on the
modern **2026-07-28** protocol (`ToolError: elicitation via server-initiated requests is
unavailable on 2026-07-28 connections`; SEP-2322 removed server-initiated back-channel
requests, SEP-2575 statelessness) — and `fastmcp.Client` defaults to `mode="auto"`,
which negotiates the modern era; the official upgrade guide calls it "the single most
likely runtime failure" [T36][T37]. The modern sanctioned alternative for interactive
input is the guard pattern (`InputRequiredResult`, New in 4.0.0) — but multi-replica
setups need a shared sealing key because `request_state` sealing is per-process unless
`RequestStateSecurity(keys=[…])` is set [T36]. With the token design, the confirmation
token rides tool ARGUMENTS: no back-channel, no session state — `ctx.set_state` does not
persist on modern-era connections anyway [T37]. Annotate every mutation tool with
`destructiveHint` and carry a confirm-token TTL (shape open, §12b).

**Verb list (admin tier) [R2.10-4].** `volume.mark`, `volume.unmount` / `volume.mount`,
`volume.vacuum`, `volume.deleteEmpty`, `ec.decode` — scope by `-volumeId` on this lab: the
unnamed pool answers to no collection name over HTTP (`collection=default` matches
nothing, §3) — `volume.check.disk` / `volume.fsck` (simulate vs `-apply`; fsck's
`-collection` must name the real owning collection), `volumeServer.state`
(`--nodes <n> --maintenanceOn`, server-wide sticky read-only maintenance — the whole-node
alternative to per-volume unmount, §5) [T8][T21]. Surface the shell-only diagnostics from
§3 (fsck, check.disk, EC shard maps, `cluster.ps`, `volumeServer.state` query) here.

## 5. Onprem tier — per-volume unmount→fix→mount

**Lab file topology (this is the correction the generic flow misses) [T9][T10].** `.dat`
files live on hostPath `/var/mnt/<pod>` (mounted into the volume pod at `/drive`);
`.idx` files live on a SEPARATE per-pod PVC `idx-seaweedfs-volume-N` (10 Gi,
`volume.idx.type: persistentVolumeClaim`), whose k3s local-path PV is
`/var/lib/rancher/k3s/storage/pvc-<uid>_default_idx-seaweedfs-volume-N`. The server
starts `volume -dir /drive -dir.idx=/idx` — it reads indexes from `/idx`. Infra is a
single node (nodeSelector keeps the pod honest).

**`weed fix` shape at 4.50 [T7].**

- Usage `fix [-remoteFile=false] [-volumeId=234] [-collection=bigData] /tmp` — the target
  is a POSITIONAL dir or single `.dat`; there is **no `-dir` flag** (other flags:
  includeDeleted, ignoreError, ecx, ecDataShards, ecParityShards, ecUnsafeIgnoreSidecar).
- Help verbatim: *"You Need to stop the volume server when running this command."*
- `doFixOneVolume`→`SaveToIdx` rewrites `.idx` in place (`O_WRONLY|O_CREATE|O_TRUNC`) and
  writes it NEXT TO the `.dat` — into the dat dir, NOT where the server reads (`/idx`).
  4.50 deliberately emits entries in `.dat` append order, every tombstone included,
  because a key-sorted `.idx` "used to flip volumes read-only on load" — this lab's exact
  idx>dat read-only failure mode. Scan/save failure is `glog.Fatal` unless `-ignoreError`.
- `-ecx` regenerates a lost `.ecx` (+ `.vif`) from local shards with RS reconstruction —
  same stop-the-server rule.

**Per-volume flow.** `volume.unmount -node <host:port> -volumeId <id>` (shell, in-session
`lock`, §4) → run `weed fix` with BOTH the dat dir (`/var/mnt/<pod>`) and the idx dir
(`/var/lib/rancher/k3s/storage/pvc-…_default_idx-seaweedfs-volume-N`) visible, landing the
regenerated `.idx` in the idx location the server reads (`-dir.idx=/idx`) →
`volume.mount -node <host:port> -volumeId <id>`. `volume.unmount`'s 2024-era metrics-reset
side effect (#6139) was fixed long before 4.50 (commit `d38456dc0`, 2024-10-22) — the
unmount→mount pair is clean at the pinned build [T8][T19]. The chart's own initContainer
`seaweedfs-vol-move-idx` (`weed fix "$dir"` + `mv /drive/*.idx /idx/` at every pod start)
is prior art [T9]; a pod restart fixes indexes that way but remounts everything — not
per-volume. Server-wide alternative without unmounting: `volumeServer.state --nodes <n>
--maintenanceOn` (sticky whole-server read-only) then fix, then off [T21].

**Revision-0 caveat for heal planning.** Compaction state matters to repair paths: 4.50's
needle-resurrection repair applies only into a replica whose `CompactRevision` is 0
(never vacuumed); vacuuming bumps the revision and hardens divergence (RESEARCH.md
§R1.1/§R1.7 Q1d). `CompactRevision` rides every `volume_list_detail` row (§3) — expose it
and refuse/escalate on revision > 0 where a procedure presumes rev-0; never assume.

**Pod privileges (deliberate escalation — gate accordingly).** The onprem pod needs
hostPath mounts of `/var/mnt` AND `/var/lib/rancher/k3s/storage` plus the `weed` binary in
its image (§7). Ship it unregistered or `enabled: false` by default and behind the §4
confirm flow [T30][R2.9-7][R2.9-13].

**Rust volume server — informational only [T9][T11][T12][T13][T22].** A Rust rewrite
(`weed-volume`, run as `weed volume-rust`; the standard 4.50 image carries both, Go and
Rust) is real, but this lab runs the Go server — detected from the pod's container command
(`exec /usr/bin/weed … volume …`) and the `/status` Version string. Per the wiki parity
tables (48/48 gRPC RPCs incl. `VolumeUnmount`, byte-identical `.dat`/`.idx`/`.vif`/EC
formats, 109 Go integration tests passing) unmount/mount/fix behave identically against
either. Contradiction on record: `seaweed-volume/MISSING_FEATURES.md` (audit 2026-03-07)
lists TLS/streaming/readonly-notification gaps that the 2026-08 wiki claims closed — the
audit predates. Future drift risk lives with the Rust path; re-check before adopting it.

## 6. Server framework conventions (FastMCP 4.1.x)

- **Tier gate = conditional registration (PRIMARY).** Register mutation tools only when
  the env-selected mode allows — never register what a tier must not offer (the wekan
  `WEKAN_MCP_READ_ONLY` precedent; tier enforced inside the image, not by the proxy)
  [T28]. Then add `enable(only=True)` allowlisting as defense-in-depth [T35]. NEVER rely
  on `disable(tags=…)` alone: components are default-enabled when no visibility state is
  set, a filter that matches nothing FAILS SILENTLY (the components you meant to hide stay
  exposed), and component keys need the trailing `@` (`tool:name@`) [T35]. Disabled tools
  vanish from `tools/list` AND cannot be called — that is why registration-time gating is
  the strong one.
- **`stateless_http=True`** — any of the three spellings
  (`mcp.http_app(stateless_http=True)`, `mcp.run(transport="http", stateless_http=True)`,
  env `FASTMCP_STATELESS_HTTP=true`) [T38]. Required for horizontal scaling: sticky
  sessions don't work (MCP clients don't forward Set-Cookie) and on the modern era session
  state doesn't persist anyway [T36][T38].
- **`@mcp.custom_route("/healthz", methods=["GET"])`** for the probe endpoint — custom
  routes are NEVER auth-protected by design, which is exactly what k8s/ToolHive probes need
  [T38]. (The path is arbitrary.)
- **`lifespan=` runs the startup self-test and builds shared clients** (`@lifespan` from
  `fastmcp.server.lifespan`, yielded dict reachable as `ctx.lifespan_context`) [T39]. The
  self-test asserts BOTH things the spec pins:
  - **certs/connectivity:** `printf 'cluster.ps\n' | weed shell -master=<m:9333> -debug
    -connectTimeout=10s`. Exit 0 = shell↔master gRPC works. Exit 1 + stderr
    `cannot connect to master …` + `pemfile.NewProvider(…) failed` = certs missing while
    mTLS is enforced — fail readiness loudly on that verdict. The master connect happens
    before any command dispatch, so this is write-free and bounded [T3]. Add a filer leg
    (`fs.ls /`) for the split case where master is plaintext but the filer enforces mTLS
    (issue #10502's exact failure) [T18]. Pass `-debug`: `RunShell` suppresses the glog
    warnings otherwise, and the CAUSE (missing certs) lives only in them [T3]. Why the test
    is needed: `LoadClientTLS` still falls back to insecure credentials on FIVE branches
    (nil config; missing cert/key/`grpc.ca`; `pemfile.NewProvider` failure; CA provider
    failure; `advancedtls.NewClientCreds` failure) with only a `glog.Warningf` — the
    silent-fallback issue #10502 described was fixed chart-side (PR #11589, upstream chart
    at `k8s/charts/seaweedfs/` [S31][S32]), NOT in the binary; it is present at 4.50 [T6].
  - **version:** fetch master `/dir/status` or volume `/status` and compare the Version
    field against the pin `4.50 ec8f97935` (volume `/status` reports it prefixed by the
    size token, `"30GB 4.50 ec8f97935"` [T9]); loud-fail (or loud-warn + operator
    note, owner choice) on mismatch so the build cannot silently age past the re-verify
    rule.
  - Lab today: no security.toml, plaintext gRPC — the fallback is inert until
    `enableSecurity`; when it lands, mount the cert Secrets WITH security.toml (§9).
- **httpx2 trap.** FastMCP 4 uses `httpx2` exclusively (a fork; plain `httpx` is no longer
  its dependency): `except httpx.…` around FastMCP calls "still imports and still
  type-checks — [it] just never match[es], because FastMCP now raises httpx2 exceptions".
  Grep the finished codebase for `except httpx.` around framework calls; catch
  `except httpx2.*` there. HTTP made inside your own tools is unaffected — call weed
  endpoints with plain `httpx` pinned as in wekan-mcp (`httpx>=0.27,<1`) [T25][T37]. Note
  httpx2 uses the OS trust store (`SSL_CERT_FILE`/`SSL_CERT_DIR`) instead of certifi —
  relevant once mTLS mounts land; HTTP loggers rename to `httpx2`/`httpcore2.*` [T37].
- Other 4.x facts to carry [T36][T37][T40]: per-tool `timeout=` (New in 3.0); sync tools
  threadpool by default; `mask_error_details` is an option — decide error masking
  explicitly rather than by omission (shell-tier `error: <detail>` lines, §4); middleware
  sees every message including unroutable ones; resource-not-found wire code changed
  -32002→-32602; `ctx.set_state` does not persist on modern-era connections (token rides
  arguments, §4).
- Standing drift check at build time: `pip index versions fastmcp` or
  `curl -s https://pypi.org/pypi/fastmcp/json | jq -r .info.version`, and the docs index
  at `https://gofastmcp.com/docs/llms.txt` [T33].

## 7. Container + CI

Mirror `containers/wekan-mcp` [T25][T26]:

- `containers/seaweedfs-mcp/{Dockerfile,pyproject.toml,seaweedfs_mcp/,README.md}`.
  Dockerfile: `python:3.15-slim`, pip-install the package, non-root uid/gid **65532**,
  `EXPOSE 8080`, `ENTRYPOINT ["seaweedfs-mcp"]` (console script from `[project.scripts]`).
  Deps: `fastmcp>=4.1,<5` + `httpx>=0.27,<1` (§6 rationale).
- onprem tier needs the `weed` binary: multi-stage
  `COPY --from=chrislusf/seaweedfs:<pin> /usr/bin/weed /usr/bin/weed`, pinned via ARG +
  datasource annotation so renovate tracks it (the container-creation skill's pattern).
- CI: `.github/workflows/docker-build.yaml` tag law — push to `main`/`dev` touching
  `containers/**` publishes `ghcr.io/ownyourio/seaweedfs-mcp:v<run_number>` (immutable) +
  `:<branch>` (rolling); PRs build-only, never push; `workflow_dispatch` takes an explicit
  container list [T26]. Deploy pins reference `:v<run>`; renovate's docker manager bumps
  the pin (wekan-mcp's values comments are the annotation precedent).
- No docker daemon in agent sessions (Coder workspace): the container build gate is
  CI-primary — the `docker-build.yaml` run on the pushed branch is authoritative and a
  local `docker build => no-daemon, CI-deferred` line is the designed PASSING shape, not a
  deviation (AGENTS.md, cf-77 precedent).

## 8. Deployment wiring (ToolHive `hivetools.mcp.*`)

NOT a plain Deployment, NOT a new chart, NOT an ApplicationSet or proxy entry: add
`hivetools.mcp.{seaweedfs-readonly,seaweedfs-admin,seaweedfs-onprem}` entries to
`services/infra/prod/values.yaml` — infra already runs the platform (helm release
`infra-hivetools`, operator v0.56.0, ns `default`) [T27][T28][T29][T30].

- `charts/hivetools/templates/generic-mcpserver.yaml` renders each entry as a
  `toolhive.stacklok.dev/v1beta1 MCPServer` named `mcp-<name>` in ns `default`, supporting
  `env`, `secrets`, `serviceAccount`, `resources`, `podTemplateSpec`, `volumes`,
  `oidc→oidcConfigRef`, `authz→authzConfig`, `toolsFilter→toolConfigRef`;
  `generic-mcptoolconfig.yaml` renders a matching **MCPToolConfig** `mcp-<name>-tools`
  (tool allowlist — the §9 gating option) [T29][T41][T42]. v1beta1 notes: inline
  `spec.tools` was removed in v0.15.0 in favor of `toolConfigRef`; `spec.port`→`proxyPort`,
  `targetPort`→`mcpPort` [T42]. At deploy time verify fields against the live CRD
  (`kubectl explain mcpserver --recursive`).
- Per-entry shape: image `ghcr.io/ownyourio/seaweedfs-mcp:v<run>`,
  `transport: streamable-http`, `mcpPort: 8080`, securityContext drop-ALL uid/gid 65532,
  mode env per tier. The two-tier wekan `wekan-readonly`/`wekan-admin` entries are the
  exact precedent [T28].
- Secrets: CRD `secrets[]` is a list-map keyed by Secret name; for multi-env values use
  `podTemplateSpec` `envFrom.secretRef` (the dev `boards` pattern) [T27].
- onprem tier: `podTemplateSpec.spec.volumes` + `volumeMounts` for hostPath `/var/mnt` and
  `/var/lib/rancher/k3s/storage` (arbitrary volumes go through `podTemplateSpec`; the
  top-level `spec.volumes` is hostPath-only per the repo's mcp-servers reference) [T30][T31].
- Client URLs land free on the ingress: `https://mcp.infra.spencerslab.com/<name>/mcp`
  (`generic-mcp-ingress.yaml` renders path `/<name>` on `mcp.<cluster>.<domain>`; the
  pattern is proven live by `readonly-infra-postgres-keycloak`) [T29].
- Validation: `helm lint charts/hivetools` + `helm template charts/hivetools` render the
  three MCPServers, plus the sentinel grep that each `hivetools.mcp` key in
  `services/infra/prod/values.yaml` matches exactly one chart entry.

## 9. Security & credentials — gate mutating tiers BEFORE exposing them

**The proxy is unauthenticated by default — the docs, verbatim [T43]:** *"Authentication is
not enabled by default … the proxy accepts every request that can reach it and forwards it
to the MCP server under a synthetic local-user identity, with no token or credential check.
This is intended for local development or deployments already isolated behind a trusted
network boundary."* The lab matches the unsafe side of that sentence twice over: every
`oidc:` block is commented out chart-wide since 2026-09 [T27][T28], AND every weed endpoint
the MCP proxies is anonymous (§3). **An exposed `seaweedfs-admin`/`onprem` MCPServer at
`mcp.infra.spencerslab.com/<name>/mcp` is world-drivable by anyone who can reach that
ingress** — and the readonly tier's MCP path is also newly reachable on the same ingress
(the exposure itself is inherited, verbatim, not invented).

Options before enabling any mutating tier — the owner rules (§12a) [T43][T44][R2.9-13]:

1. Re-enable per-server `oidc:` blocks (`oidcConfigRef` → MCPOIDCConfig, shared Keycloak).
2. MCPToolConfig allowlists (`toolsFilter`) — narrows the tool surface, not the transport.
3. NetworkPolicy so the ingress cannot reach the proxy pods.
4. Ship `seaweedfs-admin` / `seaweedfs-onprem` `enabled: false` (or simply unregistered)
   until one of 1–3 lands.

**Credential story:** none needed today (auth-free end-to-end, §3). If `enableSecurity`
lands: mount the cert Secrets ALONGSIDE security.toml in the MCP pods — the #10502/#11589
lesson, because a security.toml pointing at unmounted cert paths silently dials plaintext
(§6) — and the lifespan self-test guards the misconfiguration. Any s3/admin basic-auth, if
enabled, comes from Bitwarden via ExternalSecret per repo law — never inline. If ToolHive
OIDC is re-enabled, uncomment the `oidc:` blocks for the new entries in the same change.

## 10. Fleet registration (machine-global, not this repo)

Register the server in `~/.config/opencode/opencode.json` — the machine-global MCP fleet,
NOT version-controlled here [T32]:

- `readonly-infra-seaweedfs` → `https://mcp.infra.spencerslab.com/seaweedfs-readonly/mcp`
  (infra-cluster servers use the public-ingress URL form).
- `admin-infra-seaweedfs` ONLY once §9 gating exists; follow the `<priv>-<cluster>-<service>`
  naming law.
- Record the change in the repo's AGENTS.md MCP-server table in the SAME change (AGENTS.md
  hard rule for machine-global fleet edits; edit `.rulesync/` sources and regenerate, never
  hand-edit AGENTS.md).
- Follow-up: a wekan-mcp-style usage doc for the tool surface once the server ships.

## 11. Acceptance / commands for the build

- `helm lint charts/hivetools` and `helm template charts/hivetools` render the new
  entries (§8).
- Registry-parity-style tool-count test per tier, reading the tool registry out of the
  package (the `tests/wekan-mcp/registry-parity.py` precedent): readonly lists exactly the
  §3 HTTP tools and ZERO shell verbs; admin/onprem add their tier's tools — and on the
  readonly mode the mutation tools are ABSENT from `tools/list`, not merely disabled (§6).
- Live `tools/list` probe per deployed tier through the streamable-HTTP ingress.
- Readonly answers match the §3 table (fields, sizes within drift) at the pinned build;
  the startup self-test (§6) passes exit-0 on today's plaintext config and fails loudly on
  a tampered cert path.
- Admin tier: dry-run plan→apply against one canary volume (lock wait + `waiting for lock
  held by …` path exercised).
- Onprem tier: full unmount→fix→mount rehearsed on a scratch volume with both dirs visible;
  regenerated `.idx` verified in the `-dir.idx=/idx` location before remount.

## 12. Open decisions for the owner

Carry these from §9/§4/§3/§5 (the card description's 12-section skeleton is the same one
this file follows):

- **(a)** Which tiers to register at all pre-OIDC — readonly only, or gate first (§9).
- **(b)** Confirm-token TTL and shape (§4).
- **(c)** EC per-shard detail: shell tier vs brittle HTML scrape vs omit (§3).
- **(d)** Whether onprem gets its own card with a privilege review, or ships disabled (§5).

## Appendix A — known deltas vs the original pasted guide

The card's original guide text is superseded here. Each delta states the corrected fact:

1. **Pins**: SeaweedFS 4.48 → **4.50** (deployed `ec8f97935`; renovate 4.53.0 pending —
   re-verify at bump). FastMCP 4.1.1 → line **4.1.x**, verified **4.1.8**, pin
   `>=4.1,<5`. ToolHive **v1beta1** confirmed (operator **v0.56.0**) [R2.9-1].
2. **Endpoints that do not exist in 4.50**: master `/status` (404 — `{fileId}` catch-all)
   and volume `/dir/config` — drop both; use `/dir/status` + `/vol/status` + `/dir/lookup`
   + `/collection/info`, volume `/status` per-node on demand.
3. **`/status` churn reframe**: the `error writing JSON status` lines are benign
   kubelet-probe RST noise (~1.5–1.7 k/h steady state; responses complete in 20–50 ms) —
   never alert; read bodies to completion.
4. **Shell lock requirement**: every mutation verb needs `lock` in the SAME piped session
   (`lock`/`<cmd>`/`unlock`); the lock blocks while another holder has it; `noLock` never
   leaks between commands. The guide omitted this entirely.
5. **Exit-code law confirmed and sharpened** (PR #11117 in 4.50): piped mode exits 1 on
   any failed command; sticky `lastErr` (one failure poisons the run; successes don't
   clear); interactive exits 0; usage errors exit 2; detail on stderr `error:` lines.
6. **TLS**: the silent insecure fallback is STILL in the 4.50 binary (#10502 closed
   chart-side only, #11589); add the lifespan startup self-test; on `enableSecurity`,
   mount cert Secrets WITH security.toml.
7. **Onprem file topology**: split `.dat` (hostPath `/var/mnt/<pod>`, mounted `/drive`) vs
   `.idx` (local-path PVC, read via `-dir.idx=/idx`); regenerated `.idx` MUST land in the
   idx dir; chart initContainer fix+mv is prior art; hostPath-mount both dirs; ship the
   `weed` binary in the image.
8. **Rust volume server**: informational only — detect via pod command (`weed volume` vs
   `weed volume-rust`); lab runs Go; procedures identical per wiki parity; README-vs-
   MISSING_FEATURES contradiction noted, audit predates.
9. **Confirmation UX**: keep plan→confirm_token→apply; do NOT use `ctx.elicit` (it raises
   on the default modern-era 2026-07-28 connection); tokens ride tool arguments (no
   session state; `request_state` sealing is per-process unless a shared key is set).
10. **Visibility hardening**: conditional registration per mode is the primary gate (never
    register mutation tools) + `enable(only=True)` allowlist as second layer; never rely
    on `disable(tags=…)` alone (default-enabled; silently-failing filters; `@` key rule).
11. **FastMCP 4 API hygiene**: `stateless_http=True`; `@mcp.custom_route` (never
    auth-protected — by design); `lifespan=` for startup probes/clients; `except httpx2.*`
    around FastMCP calls (the dead-`except httpx.` trap); plain `httpx` inside tools fine
    (`httpx>=0.27,<1`); pydantic ≥2.12 floor.
12. **Deployment wiring**: `hivetools.mcp.{seaweedfs-readonly,seaweedfs-admin,seaweedfs-onprem}`
    under `services/infra/prod/values.yaml` (image `:v<run>` pin, streamable-http,
    `mcpPort: 8080`, uid 65532) — MCPServer CRs, NOT plain Deployments, no new
    chart/appset/proxy entries; fleet registration machine-global + AGENTS.md table row.
13. **Security gate before exposing mutating tiers**: ToolHive proxy unauthenticated by
    default AND weed endpoints auth-free — re-enable `oidc:` blocks, or MCPToolConfig
    allowlist, or NetworkPolicy, or ship admin/onprem `enabled: false` until the owner
    rules.
14. **Upstream chart path**: the SeaweedFS Helm chart lives IN the weed repo at
    `k8s/charts/seaweedfs/` (verified at tag 4.50 from the official `seaweedfs-4.50.0.tgz`
    and the repo templates [S31][S32]) — the lab's `charts/seaweedfs` is a wrapper on the
    `seaweedfs 4.50.0` dependency; chart-side fixes (e.g. #11589) land upstream and reach
    the lab only through a dependency bump.
15. **Unnamed-pool law**: no collection literally named `default` exists — HTTP
    `/collection/info` answers `does not exist` for it and rejects an empty value; the
    lab's pool is the UNNAMED one, queryable only via shell `_default`/`""` semantics or
    the admin UI alias [R2.11]. Any tool that "selects the default collection" is a bug.
