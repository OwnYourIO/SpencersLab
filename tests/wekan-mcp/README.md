# tests/wekan-mcp — the wekan-mcp contract batteries

Static + offline-exec checks over `containers/wekan-mcp/wekan_mcp/server.py`
(the tool registry and payload shapes), the MCP catalog docs
(`skills/wekan-mcp/SKILL.md`, `references/call-shapes.md`), and the
board-context plugin/collector surfaces that consume them. No suite here starts
a server or touches the network: the live `tools/list` readbacks stay
USER-owned (the deployed image lags the repo source).

Each suite takes check ids (`bash tests/wekan-mcp/card-details.sh t2 t3`); run
one whole only when none of its legs is a designed red for another chunk.

## Count literals: derived from the registry, never re-typed

Every tool-count claim in this tree is checked against the `@mcp.tool` /
`_write_tool` decorators in `server.py` by `tests/wekan-mcp/registry-parity.py`
(the single reader — modes `counts`, `claims`, `rows`). It answers
`18 21 39` today: C07's `get_card_details` grew the read side, so 18 reads +
21 writes = 39 is the current fact, and a future +1 moves the number without a
suite edit. **Do not chase the number when a count arm reddens** — the registry
is the source, so the doc or runbook that drifted is what gets fixed
(cf-68 FRICTION: hard-coded parity literals; DECISIONS 2026-11-04 C07 routing,
OQ-13: re-pinning counts in the pre-ticket `cf96-deploy` suite is allowed and
expected).

Five suites read it (`tools.sh`, `dependencies.sh`, `create-list.sh`,
`board-provisioning.sh`, `skill-surface.sh`) plus `tests/cf96-deploy/surface.sh`
t3 — the counts are read into `REG_READS/REG_WRITES/REG_TOTAL`, and doc claims
and table rows are compared against the registry rather than against prose.

Two consequences worth knowing before editing a suite:

- A claim is checked on the **line that makes it** where the suite scopes it
  (`tests/cf96-deploy/surface.sh` t3 over the deploy runbook): a stale
  `38 tools` / `17 reads` may not pass because a correct `39-tool` line sits
  elsewhere on the page (cf-106 C07 round 2, N5).
- `claims` deliberately skips a bare "the 5 dependency tools" — that names a
  subset, not the surface. The count-presence arms require one house-spelling
  claim per doc, so a doc cannot dodge the scan by rewording.

## Designed reds currently expected in this tree

Red for a chunk that has not landed yet is a passing state for the *other*
chunks — attribute it before reading it as this chunk's defect (FRICTION
2026-11-04: these bash batteries abort at the first red, so run id-subsets).

| Leg | Red until | Why |
|---|---|---|
| `card-details.sh` t5 | cf-106 C07 dev round | `get_card_details` still swallows a failed checklist-items route into `items: []`; the C06 fail-the-call ruling (DECISIONS 2026-11-04) makes it fail the call |
| `agent-perms/surface.sh` A15 (run via `board-context.sh` t6) | cf-106 C08 | the pipeline_claim `shared` override input (AC6) and the boards skill's co-tenancy posture (AC7) |
| `agent-board-coord/gate.sh` t17 | tracked outside cf-106 | pre-existing warm-location permissions drift; every t6-style id-subset already excludes it |
