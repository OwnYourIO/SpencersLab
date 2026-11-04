---
name: wekan-board-provision
description: "Provision or update the AI-Dev WeKan board structure idempotently — mirror Planning's lists from Backlog, ensure one Bucket: <list> label plus a createCard/moveCard rule pair per Planning list, ensure the Provider: API / Provider: Local and Research: Parallel labels, ensure Inbox exists in Backlog, and diff the createCard rule's checklist extras (11-item Lifecycle + Human in the Loop mirror, Model(s) → Qwen Dense default-checked) against the spec via a schema-2 snapshot. Use when asked to (re-)provision the board, when /wekan-board-provision runs, or when the action plan of scripts/provision-board.py must be applied through dev-boards or raw REST."
---

# WeKan board provisioning

`scripts/provision-board.py` is the offline engine: a board snapshot goes in
(`--fixture <snapshot.json>`, schema `wekan-board-snapshot/1`, or schema
`wekan-board-snapshot/2` when the createCard rule's checklist extras were
captured), one ordered, idempotent action list comes out. It never touches
the network and never reads credentials — every board mutation happens in
the apply steps below, gated by a human-confirmed plan.

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
- **Research: Parallel label**: the board label the coord's per-ask
  research split keys on exists, presence judged by name only like the
  Provider labels; `orange` is the palette default, an owner recolor
  survives — an ensure never recolors.
- **Inbox**: `Inbox` is a Backlog-swimlane list the engine ensures
  exists. It is NEVER mirrored into Planning and NEVER receives a
  `Bucket:` label or a rule pair — cards parked in Inbox stay
  unbucketed by design.
- **createCard checklist extras** (schema `wekan-board-snapshot/2` only):
  the multi-action createCard rule carries five extras — Services (15
  items), Type (7), Model(s) (4, arriving with `Qwen Dense` checked),
  Lifecycle (the 11 stage names in card order, `Single Session` last,
  unchecked so the blank Lifecycle default governs), and Human in the
  Loop (the same 11 names, unchecked; the OQ6/OQ13 rulings). Against a
  schema-2 snapshot the engine diffs the captured extras against this
  spec and, on drift, emits ONE `update_createcard_checklists` action
  naming the current-generation rules-import artifact
  `.agents/plans/2026/2026-11-cf-106-feat-coord-fixes/board-rules-v12.65-dense.json`
  (the artifact is re-issued by whichever ticket moved the Model(s)
  vocabulary; the cf-96 `board-rules-v12.65.json` it re-issues is the
  applied history). A board still carrying a retired Model(s) item name IS
  drift against this spec — the boards skill's transition alias governs how
  a card is *consumed*, never what the spec accepts.
  Against a schema-1 snapshot the spec is UNVERIFIABLE and the engine
  prints only a runbook note on stderr — a note is not an action.

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

To capture schema `wekan-board-snapshot/2`, read the createCard rule's
checklist extras with `get_rule` (or the Rules UI export — rule checklists
are write-restricted to the UI/import path, never REST) and add a
top-level `checklist_extras` map: checklist name → `{items: [...names in
order], checked: [...names]}`. If the rule read fails or the extras cannot
be captured, fall back to schema 1 — the engine then treats the checklist
spec as unverifiable instead of guessing.

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
The repo source now carries `create_list`, `create_label`, and
`set_card_labels` (cf-89/cf-90 tooling plus the cf-96 C01 block); the
degrade below retires when the C10 pin-bump deploys — until then treat
the deployed catalog, not the source, as the truth. Apply through
dev-boards when the tool is present, otherwise emit the raw-REST fallback
recipes below for the human shell (`WEKAN_BASE_URL` + `WEKAN_TOKEN`, the
wekan-api skill convention) or route them through the admin-global-wekan
surface, and stop cleanly for human confirmation.

Apply the plan in its emitted order — list creations first, then each
`Bucket:` label immediately followed by that list's rule pair, the
Provider and Research: Parallel label ensures last — and resolve every
title to its live id at apply time (re-read structure after creating
lists/labels; never trust snapshot ids). That order already keeps every
label ahead of the rules referencing it; do not regroup the plan by
action type. Rule titles follow the convention
`Bucket: <list> — <activityType>` exactly as the engine prints them, so
the next dry run matches them case-insensitively and reports them as done.

- create a list: `POST /api/boards/:id/lists` with
  `{"title": "<list>", "swimlaneId": "<target-swimlane-id>"}`
- create a label: `POST /api/boards/:id/labels` with
  `{"name": "<label>", "color": "<color>"}`

An `update_createcard_checklists` action in the plan is **HUMAN-EXECUTED,
never applied here**: checklist extras on a rule are creatable only
through the WeKan UI wizard or Rules → Import JSON, never through any REST
or MCP call — that is why this leg exists as a runbook action. The agent
emits the recipe and stops: the owner takes a board backup FIRST, then
WeKan UI → Rules → Import JSON of the artifact the plan names
(`.agents/plans/2026/2026-11-cf-106-feat-coord-fixes/board-rules-v12.65-dense.json`,
the Dense vocabulary generation), which replaces the createCard rule's
extras with the five-checklist v2 shape (`Model(s)` → `Qwen Dense` the only
default check). This mirrors the boards skill's "Board-side cutover" steps:
checklist renames and the label ensures stay human-owned too — an agent
never mutates board checklists or rules.

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
- The checklist-extras apply is human-executed and backup-gated: no
  agent path writes checklist extras, and the engine only prints the
  import runbook.
