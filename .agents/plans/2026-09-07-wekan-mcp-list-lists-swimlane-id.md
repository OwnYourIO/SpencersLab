# wekan-mcp: expose swimlane_id in list_lists

Date: 2026-09-07
Status: implemented, pending merge + CI rebuild

## Context

While querying the Projects board for WeKan rule authoring, `list_lists`
returned only `{id, title}` per list. The swimlane-to-list mapping was
unavailable because `_slim_list` in `containers/wekan-mcp/wekan_mcp/server.py`
stripped the `swimlaneId` field that the WeKan `/api/boards/:id/lists`
endpoint returns. List titles repeat across swimlanes, so rules and card
creation need the (list, swimlane) pair.

## Changes

1. `containers/wekan-mcp/wekan_mcp/server.py`
   - `_slim_list` now returns `swimlane_id` alongside `id` and `title`
     (snake_case, consistent with `_slim_card`).
   - `list_lists` docstring updated so models know entries carry swimlane_id
     and can be grouped by swimlane.
2. `containers/wekan-mcp/README.md`
   - Tools table row for `list_lists` updated to mention `swimlane_id`.

## Validation

- `python3 -m py_compile` passes on `server.py` and `wekan.py`.
- No unit-test harness exists in this container (module import instantiates
  `WekanClient` against live env vars); full verification is post-deploy:
  `list_lists` on board `TrfngHQf8PWj9mnqC` (Projects) should return
  `swimlane_id` per entry.

## Deploy path (no manual version bumps)

- Merge to `main` -> `docker-build.yaml` pushes `:v<run_number>` + `:main`.
- Image is pinned at `ghcr.io/ownyourio/wekan-mcp:v25` in
  `services/gpu/prod/values.yaml` (hivetools `mcp.wekan`); Renovate opens the
  tag-bump PR once the new tag is published. ArgoCD syncs after that.
