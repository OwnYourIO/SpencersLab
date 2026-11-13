# Checklist backfill runbook — owner-executed

`scripts/board-checklist-backfill.py` expands existing cards' Lifecycle,
Human in the Loop and Services checklists onto the generation
`scripts/provision-board.py` defines. The engine plans offline by default —
a dry run performs zero network calls — and its apply leg belongs to the
owner alone, after a board backup. No pipeline run executes the apply, and
the engine never re-implements the rules import: that stays a human
UI → Rules → Import JSON leg.

## Preflight

1. The server runs with `WITH_API=true` — every REST call answers an auth
   error otherwise, even with a valid token.
2. Take a board backup first (WeKan board menu → export board data). The
   apply leg asserts the backup through `--backup-confirmed <ref>` — name
   the backup there.
3. The apply leg's credentials come from the environment only: `WEKAN_URL`
   (site root, no trailing `/api`) and `WEKAN_TOKEN` (the long-lived
   bearer). Never put a value into a command line, plan, log or commit —
   names only.
4. Export the board to a `wekan-board-export/1` JSON: cards carry inline
   `checklists` (items as `{title, isFinished, sort}`) and
   `custom_fields` (`{name, value}`); the file carries `swimlanes`,
   `lists`, a `board` object with its `_id`, and board-level
   `custom_fields` with ids when the Priority leg runs.
   `tests/wekan-board-provision/fixtures/board-backfill-sample.json`
   shows the shape.

## Plan (the default dry run)

```
python3 scripts/board-checklist-backfill.py --board <export.json> \
  [--out plan.json] [--report report.txt] [--dry-run]
```

The plan prints on stdout; the report prints on stderr and lands in
`--report` when the file is named.

Reading the plan:

- One entry per missing item — every insert carries its card and checklist
  ids, the item title and an explicit negative `sort`; existing items keep
  their stored sorts. Negative sorts render the inserts ahead of the
  stored set, so the read-back pass below includes the human order
  correction for trailing names.
- A name the card already carries (whitespace/case-insensitively) yields
  no entry. Tick state never appears in a planned write: existing ticks
  survive because the backfill cannot re-tick, and re-ticking would
  silently re-approve decisions.
- Anomaly cards — a missing Lifecycle, a duplicated checklist set — appear
  in the report with their ids and in no plan. `--create-missing-lifecycle`
  opts the Lifecycle create leg in; `--card <id>`, `--include-list` and
  `--exclude-list` adjust scope; archived cards, the In Process swimlane
  and `Cancelled` stay out of the scope by default.
- Rule drift is expected pre-import: the provision dry-run keeps reporting
  createCard rule drift until the owner imports the current-generation
  rules artifact, and that report is the provision engine working, not a
  backfill defect.
- The plan is deterministic — run it twice and diff: one export yields
  byte-identical plans.

## Apply (owner-executed, never a run's work)

```
python3 scripts/board-checklist-backfill.py --board <export.json> \
  --apply --yes --backup-confirmed <backup-ref>
```

All three flags are required; missing any one, the engine exits non-zero
and writes nothing. The apply leg posts the plan per card in plan order —
WeKan has no cross-card or bulk checklist endpoint, so the loop is the
designed path. A failed call or an embedded error in an otherwise-successful
response aborts the run after flushing the completed-action log to stderr;
re-run the dry plan to see the remainder, because landed inserts dedupe to
no-ops — the plan is resumable by construction. A Priority write onto a card
that does not yet carry the field rewrites the card's whole `customFields`
array (the dedicated value route silently no-ops on unattached fields), so
do not run an armed apply while the same cards' fields are open in the UI.

## Read-back spot checks

Check three cards after applying:

1. One legacy 14-item Human in the Loop card: the new names are present and
   every earlier tick is intact.
2. One current-generation card: unchanged — its plan was empty.
3. One of #65/#66: still carrying its duplicated checklist sets — the
   backfill reported them and never touched them.

Drag trailing item names into card order in the UI where that matters to
you: the inserts lead the stored set by design, and renumbering stored
items is exactly the delete-and-rebuild path this engine exists to avoid.

## Anomaly triage (human-owned)

- **#57, #71** — cards with no Lifecycle checklist at all. Creating one is
  the `--create-missing-lifecycle` leg; until it is decided for them they
  stay a report.
- **#65, #66** — cards carrying duplicated checklist sets (one title twice
  over). Deduping is a human merge: removing a checklist cascades its
  items and their ticks, which is why the engine offers no removal.
- Anomaly cards receive no writes in any mode beyond the named opt-ins;
  repairing them stays with the board-data owner.

## Priority

The `--priority-default <N>` leg is off by default. Armed, it plans numeric
writes — the board's NUMBER field takes the int form — only for in-scope
cards where the field is unset or null, and it never overwrites an
explicit value. Two permissions sit here and must never be read as one:
this bulk leg is the owner-run path — a permission lift is not a mandate
and not a sweep authorization, every other card and all bulk board-data
mutation still need explicit owner direction, and bulk values come from
the owner, this being that leg. The agent's own per-card stamp — its
claimed or created cards only, conditional, idempotent, never a loop over
a board or a list — is a separate permission and never runs through this
engine. An unset field already resolves to the default serving class, so
a stamped `5` is visibility, not an urgency change.

## No upstream action

The rule-driven checklist-default dormancy (`checkListId` lookups) is a
documented fact at the pinned version, re-checked at the next version
bump. Nothing in this runbook owes an upstream action, and no filing ask
stands here.
