---
description: >-
  Collect the AI-Dev board's structural ids plus its per-list card snapshot into
  a Board context block for pasting into an OpenChamber scheduled-job prompt
agent: agent-board
---
Board title (optional, default **AI-Dev**; a swimlane override may ride along): $ARGUMENTS

Resolve the board structure through the `dev-boards` MCP server, read-only, in exactly this order:

1. `list_boards` — the only board call that takes no `board_id`; match the board title (default **AI-Dev**) to get it.
2. `get_board` — with that id; it carries the board `labels` and the board `key` — the `card_number` prefix source below.
3. `list_swimlanes` — match the pipeline swimlane (default **In Process**; an override named in $ARGUMENTS wins) to get the `swimlane_id`.
4. `list_lists` — keep only the items whose `swimlane_id` equals that swimlane: titles repeat across swimlanes, the items carry the field to filter on.
5. `list_custom_fields` — items carry `{id, name, type}`; the block keys on `name`, not `title`.
6. `preload_board` — with the `board_id` ONLY, never a swimlane filter: the whole-board export the per-list `cards:` join reads — its swimlane grouping is scoped to the named lane client-side, and its board-wide `label_names` map resolves each card's `label_ids` to names (an id the map lacks emits raw).

Derive each card's `card_number` as `<boardKey>-<card_number>` — the board key the `get_board` answer carries, e.g. AI-Dev's key `AD` → `AD-123` — never a hardcoded literal. Cards render sort-ascending with archived skipped, and a list the export drops renders empty cards. When the deployed projection carries no key (pre-rollout build), degrade to the bare `card_number` and carry the schema section's pinned note line — the degrade shape is documented there, never silent.

Emit the Board context block EXACTLY per the `wekan-mcp` skill's "Board context block schema" section — that section is the format's single normative home (field list, collection stamp, the cards group, the re-resolve footer all come from it; this command carries no copy of the schema). Produce the collection stamp in the workspace-local ISO-8601 offset form — the same rule the board-context plugin's `collectedAt` follows through its single formatter (cf-96 OQ4), UTC `Z` when `$TZ` names no usable zone. Wrap the emitted block in a fenced code block so it pastes cleanly. Then print the two usage notes:

- Paste the block into the OpenChamber scheduled-task prompt, above or below the `/pipeline-boards-hourly` invocation — a launched board-coord run consumes it instead of re-running the resolution calls (boards skill, Board context block consumer rule).
- The ids and the per-list cards are a collection-time snapshot, not a freeze: re-collect after any board-structure change, and consumers re-resolve on any id-shaped call error. Checklist ids stay live per-card data — they are never pre-collected.
