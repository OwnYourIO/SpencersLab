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

## Red posture in this tree (2026-11-05, after C01-C08)

Every wekan-mcp suite in this folder is green; the designed reds the table
used to carry have landed. When a suite reddens again, attribute it before
reading it as a defect here (FRICTION 2026-11-04: these bash batteries abort
at the first red, so run id-subsets).

| Leg | Status | Why |
|---|---|---|
| `card-details.sh` t5 | green — C07's dev round landed the fail-the-call | a shipped-behaviour pin now: the executed half distinguishes a failed items read from a genuinely empty checklist offline; the mechanism half bans the swallow shapes, with a swallow-free /tmp copy as the green-side control, five fabricated degradations as red controls, and the typed `isinstance`-guard + raise spelling accepted at synthetic and file level (round-3 R3-M1) |
| `agent-perms/surface.sh` A15 | green — C08 landed | `board-context.sh` t6 still runs A15 as its own arm and prints a fold-back note when it is green |
| `agent-board-coord/gate.sh` t17 | red — tracked outside cf-106 | pre-existing warm-location permissions drift; every t6-style id-subset already excludes it |
