---
name: wekan-board-provision
description: "Provision or update the AI-Dev WeKan board structure idempotently — mirror Planning's lists from Backlog, ensure one Bucket: <list> label plus a createCard/moveCard rule pair per Planning list, ensure the Provider: API / Provider: Local labels, and ensure Inbox exists in Backlog. Use when asked to (re-)provision the board, when /wekan-board-provision runs, or when the action plan of scripts/provision-board.py must be applied through dev-boards or raw REST."
---

# WeKan board provisioning

`scripts/provision-board.py` is the offline engine: a board snapshot goes in
(`--fixture <snapshot.json>`, schema `wekan-board-snapshot/1`), one ordered,
idempotent action list comes out. It never touches the network and never
reads credentials — every board mutation happens in the apply steps below,
gated by a human-confirmed plan.

## The spec the engine diffs against

- **Lists**: every Backlog list title is mirrored into the Planning
  swimlane. Lists that exist only in Planning (or Farm) are left alone —
  the sync never deletes a list absent from Backlog.
- **Bucket labels**: one `Bucket: <list>` label per mirrored Planning
  list, colored `darkgreen` — the board's "Bucket Color" swatch.
- **Rules**: per Planning list, two single-action rules —
  `createCard` and `moveCard` (creating a card fires `createCard`, not
  `moveCard`, so one rule is never enough). Every trigger carries the
  `swimlaneName: Planning` matcher: identical list titles exist in
  Backlog and Farm as separate list documents, and an unscoped rule
  cross-fires into them. WeKan rule actions take a fixed labelId with no
  substitution, which is why the design is one label and two rules per
  list, not one generic rule.
- **Provider labels**: `Provider: API` and `Provider: Local` exist.
- **Inbox**: `Inbox` is a Backlog-swimlane list the engine ensures
  exists. It is NEVER mirrored into Planning and NEVER receives a
  `Bucket:` label or a rule pair — cards parked in Inbox stay
  unbucketed by design.

## Procedure

### 1. Collect the snapshot

Read-only through the `dev-boards` MCP server, in this order:
`list_boards` (match the title **AI-Dev**) → `get_board` (carries the
board labels) → `list_swimlanes` → `list_lists` (each item carries its
`swimlane_id`; group titles by it) → `list_rules`. Normalize into
`wekan-board-snapshot/1` JSON: `swimlanes` as name→id, `lists` as
swimlane-id→titles, `labels` as name→color, and rules as
`{title, trigger, action}` records — omit `"*"` matchers and resolve an
`addLabel` id to its label name. The engine keys on titles, not ids.

### 2. Dry run — the engine emits the action plan

```
python3 scripts/provision-board.py --fixture <snapshot.json> --dry-run [--format json|text]
```

The printed output IS the action plan and the dry run: deterministic,
offline, zero board effect. Show it to the human and get confirmation
before any apply step. An empty plan means the board already matches the
spec — report that and stop, there is nothing to apply.

### 3. Apply, tool-probe first

Probe the live tool catalog (`tools/list`) before applying anything: the
deployed build can lag the repo. `create_rule` is present in the deployed
dev-boards surface; `create_list` and `create_label` are NOT (the `:v87`
pin — ledger card L4 tracks the bump that makes the MCP path whole).
Apply through dev-boards when the tool is present, otherwise emit the
raw-REST fallback recipes below for the human shell (`WEKAN_BASE_URL` +
`WEKAN_TOKEN`, the wekan-api skill convention) or route them through the
admin-global-wekan surface, and stop cleanly for human confirmation.

Apply the plan in its emitted order — list creations first, then each
`Bucket:` label immediately followed by that list's rule pair, provider
labels last — and resolve every title to its live id at apply time
(re-read structure after creating lists/labels; never trust snapshot
ids). That order already keeps every label ahead of the rules referencing
it; do not regroup the plan by action type. Rule titles follow the
convention `Bucket: <list> — <activityType>` exactly as the engine prints
them, so the next dry run matches them case-insensitively and reports
them as done.

- create a list: `POST /api/boards/:id/lists` with
  `{"title": "<list>", "swimlaneId": "<target-swimlane-id>"}`
- create a label: `POST /api/boards/:id/labels` with
  `{"name": "<label>", "color": "<color>"}`

### 4. Verify with a zero-action re-run

Re-collect the snapshot (step 1), then re-run the engine on it (step 2):
expect ZERO actions. A non-empty second plan means an apply step failed
or the board drifted mid-run — fix the apply, never the diff.

## Invariants

- Additive-only: the flow never deletes, archives, or empties anything.
  A Planning list absent from Backlog stays exactly where it is.
- Case-insensitive title matching with never-rename behavior: the engine
  compares lower-cased, and a near-miss list keeps its human spelling —
  Farm's `Outside Proccess` typo survives untouched. Fixing spellings is
  a human edit, never a provisioning side effect.
- Inbox contract: ensured in Backlog, never mirrored into Planning, never
  given a `Bucket:` label or a rule pair.
