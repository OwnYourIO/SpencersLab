# wekan-mcp: expose swimlane_id in list_lists

Date: 2026-09-07
Status: stage 1 merged to main (5237671c); stage 2 implemented here, pending merge

## Context

While querying the Projects board for WeKan rule authoring, `list_lists`
returned only `{id, title}` per list. List titles repeat across swimlanes,
so rules and card creation need the (list, swimlane) pair.

## Stage 1 (merged: 5237671c)

`_slim_list` in `containers/wekan-mcp/wekan_mcp/server.py` now returns
`swimlane_id` alongside `id`/`title`; docstring + README updated.

Post-deploy verification showed `swimlane_id: null` on every list: the
field never reaches the MCP server.

## Stage 2 (this change): hydrate swimlaneId per list

Root cause, verified against WeKan v9.99 source (deployed image
`ghcr.io/wekan/wekan:v9.99`):

- `GET /api/boards/:boardId/lists` hard-projects each list to
  `{_id, title}` (wekan `server/models/lists.js`, route handler). The
  collection endpoint structurally cannot return `swimlaneId`.
- `GET /api/boards/:boardId/lists/:listId` returns the full list document
  (schema includes `swimlaneId`; e2e spec `23-rest-api-more.e2e.js`
  exercises the route).

Fix: `list_lists` hydrates each list via the single-list endpoint when
`swimlane_id` is absent (N+1 GETs — acceptable at homelab board sizes).
A failed hydration logs a warning and degrades to `null` instead of
failing the whole listing. If a future WeKan adds `swimlaneId` to the
collection endpoint, the hydration is skipped automatically.

## Validation

- `ast.parse` syntax check passes on `server.py` and `wekan.py`
  (bytecode-free; `.gitignore` now covers `__pycache__/` regardless).
- No unit-test harness exists in this container (module import
  instantiates `WekanClient` against live env vars); full verification is
  post-deploy: `list_lists` on board `TrfngHQf8PWj9mnqC` (Projects) must
  return non-null `swimlane_id` per entry.

## Deploy path (post admin/readonly split)

- Both wekan tiers reference the rolling tag
  `ghcr.io/ownyourio/wekan-mcp:main` with `imagePullPolicy: Always` in
  `services/gpu/prod/values.yaml` — merge to `main` + CI build, then delete
  the wekan MCP pods to force a re-pull (done for stage 1 on 2026-09-07;
  digest c4a6de0b -> 82a9ed3e confirmed the rollout mechanism works).
