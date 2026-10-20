# Plan folders, STATE.json, RESULT, friction

The pipeline's living state. Everything here is per-ticket; there is no global state, so tickets never overwrite each other.

## Ticket folder layout

```
.agents/plans/
  templates/                         blank versions of every plan/tracking file
  <yyyy>/
    <yyyy-mm>-<type>-<slug>/         ONE folder per ticket, everything together;
                                     <type> = feat|bug|debug|dep|refactor|chore|docs
      <yyyy-mm-dd>-<type>-<slug>.md  plan of record: goal, scope, chunk table, waves.
                                     Only plan/coord write it. Renamed from
                                     templates/PLAN.md when the ticket is created.
      <companions>                   runbooks/scripts share the plan file's prefix
      STATE.json                     machine state: status, waves, per-chunk handoffs. Only cord writes it.
      DECISIONS.md                   append-only decision log. Read before acting; only plan/coord add to it.
      friction.md                    append-only friction log. Agents report via RESULT; cord appends; everyone reads at run start.
      chunks/C01.md ...              one per chunk: goal, tasks, files in scope, acceptance criteria, verification, review notes.
```

- Keep a ticket in its **earliest** folder — the one created in the year/month the ticket started; follow-up plans join the existing folder even in later months or years.
- Folders created before 2026-10-17 use the legacy `yyyy-mm/<feature-slug>/` layout and are migrated per-ticket; plans created before the per-ticket convention live flat at the `.agents/plans/` root — historical and immutable.
- New ticket: copy the blanks from `templates/` into `<ticket>/`, renaming `PLAN.md` to the dated plan file `<yyyy-mm-dd>-<type>-<slug>.md` (`agent-plan` does this). One plan file per ticket — never a second one.

## STATE.json schema

```json
{
  "feature": "<yyyy>/<yyyy-mm>-<type>-<slug>",
  "kickoff": { "slug": "<slug>", "run_tag": "<tag>", "worktree": "<slug>-<tag>",
               "plan_model": "<provider/model>", "code_model": "<provider/model>" },
  "plan_status": "draft | approved | needs-replan | complete",
  "current_wave": 1,
  "updated_at": "YYYY-MM-DDTHH:MM:SSZ",
  "chunks": {
    "C01": { "status": "pending | in-progress | done | blocked",
             "wave": 1, "depends_on": [], "dev_rounds": 0, "review_rounds": 0,
             "last_verdict": null,
             "handoffs": [ { "round": "dev-1", "result": { /* RESULT block, verbatim */ } } ] }
  },
  "blocked": [], "deferred": []
}
```

## RESULT block (every subagent hand-back ends with exactly this)

```
RESULT
status: DONE | BLOCKED | NEEDS_INFO | CHANGES_REQUESTED
chunk: <chunk-id or "plan">
files_changed: [<paths>]
commands_run: [<cmd> => pass|fail]
deviations: <anything done differently from the chunk/plan, or "none">
friction: <one line per item: what blocked/slowed the run + resolution used, or "none">
open_questions: <questions for cord/human, or "none">
next_suggested: <one line>
```

Cord copies it verbatim into `STATE.json` under `chunks.<id>.handoffs[]` **before anything else** — context may be compacted at any moment; the file is the only memory.

## Chunk lifecycle (per wave, one chunk at a time)

`agent-dev` implements → `agent-validate` runs the validation commands/full suite → `agent-review` reviews. On `CHANGES_REQUESTED`, dev fixes and validate→review repeat (max 3 rounds each; then chunk `blocked`, ask the user: more rounds / accept / re-plan / drop). A chunk is `done` only with dev DONE + verification shown passing in `commands_run` + review APPROVED. Two consecutive dev rounds failing the same verification on the same files → stop and escalate. When all chunks are `done`, cord launches a final `agent-review` over the whole plan (full diff against every acceptance criterion, plus DECISIONS.md and friction.md); only its APPROVED marks `plan_status: "complete"`.

## Friction lifecycle

Friction = anything an agent could not find or had no access to, crashes/tool-MCP failures, stale docs/plans, forced repeats or workarounds — **each with the resolution actually used**.

1. Every agent reads `friction.md` at run start (known workarounds are not rediscovered) and reports new items in RESULT `friction:`.
2. Cord appends reported + own items after every hand-back. Primary agents without a coord append their own.
3. User triages: entries are never deleted, only re-statused `open` → `fixed` (cause repaired) or `ignored` (accepted). Agents treat `fixed` as history and `ignored` as known-OK.

Entry format:

```
- YYYY-MM-DD · <role>(<chunk>) · <what happened + impact> · resolution: <what the agent did> · <open|fixed|ignored>
```
