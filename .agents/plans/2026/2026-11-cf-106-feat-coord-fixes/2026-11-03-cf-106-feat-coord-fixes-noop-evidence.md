# No-op / archive / alert evidence — scheduled board-coord sessions (read 2026-11-03T21:58Z)

**Baseline read 2026-11-03T21:58Z; superseded counts in the addendum at the bottom (re-read 22:45Z).** OQ-1 was "which arm of the archive/alert ask is actually broken — the coord never runs the recipe, the archive PATCH is ineffective, or the app ignores the archive?" The owner answered "I don't know. It's worth investigating," so the investigation ran read-only against the OpenCode session store, the only surface that records marker + archive state per session: `~/.local/share/opencode/opencode.db`, table `session_v2` (`metadata`, `time_archived`, `agent`, `directory`, `title`), opened read-only through `python3 -c "sqlite3.connect('file:…?mode=ro')"`. No `sqlite3` binary exists in the workspace; `python3`'s stdlib `sqlite3` does (verified). No write, no board call, no session PATCH.

## The table (SpencersLab sessions, newest 25 matching, 2026-11-02 → 2026-11-03)

| created (UTC) | session | title | `openchamber.kind` | `metadata.pipelineNoop` | `time_archived` |
|---|---|---|---|---|---|
| 11-03 21:30 | `ses_e5cae562ff…` | `no-op 2026-11-03T21:39` | scheduled | `{reason:"no-claimable-cards"}` | **11-03 21:39:50Z** |
| 11-03 21:00 | `ses_e5cc9c99af…` | `pipeline-worker 2026-11-03 21:00` | scheduled | **absent** | **none** |
| 11-03 20:35 | `ses_e5ce065e2f…` | `pipeline-worker 2026-11-03 20:35` | scheduled | **absent** | **none** |
| 11-03 20:30 | `ses_e5ce54255f…` | `pipeline-worker-local 2026-11-03 20:30` | scheduled | **absent** | **none** |
| 11-03 20:06 | `ses_e5cfa57d6f…` | `no-op 2026-11-03T20:07` | **none** | `{reason:"no-cards"}` (+ `openchamber.probeSentinel:"keepme"`) | none |
| 11-03 20:00 | `ses_e5d00b9b2f…` | `no-op 2026-11-03T20:15` | scheduled | `{reason:"no-claimable-cards"}` | 11-03 20:17:13Z |
| 11-03 19:30 | `ses_e5d1c2cabf…` | `pipeline-worker-local 2026-11-03 19:30` | scheduled | **absent** | **none** |
| 11-03 19:00 | `ses_e5d37a4caf…` | `no-op 2026-11-03T19:18+00:00` | scheduled | `{reason:"no-claimable-cards"}` | 11-03 19:19:24Z |
| 11-03 16:30 / 16:00 | `ses_e5dc0fbf8f…`, `ses_e5ddc7612f…` | `no-op …` | scheduled | `no-claimable-cards` | archived |
| 11-03 06:00 → 11-02 22:00 | 11 more `no-op …` sessions | | scheduled | `no-claimable-cards` / `no-cards` | **archived in every case** |

Message-tail read of the four unmarked scheduled runs (`session_message`, newest rows, last assistant text):

- `…21:00` (10 msgs): ends mid-turn on raw `<tool_call>…<function=list_cards_in_list>` XML emitted as text — the turn died in the pickup walk.
- `…20:35` (14 msgs): ends on raw `<tool_call><function=dev-boards_list_boards>` XML.
- `…20:30` (5 msgs): ends after "I'll load the pipeline skills and check lock state first." — died at the first step.
- `…19:30` (21 msgs): ran a real walk and ended reporting **"The board MCP surface is confirmed absent from this session — probed three ways … the dev-boards server itself is alive: the launch's board-context block was collected from it at 19:30Z by the prefetch hook."**
- All four: `children: 0` (no subagent was launched), so no work happened and no exit recipe ran.

## What this proves

1. **The marker + archive contract works when a run reaches a marked exit.** Every scheduled run that wrote `pipelineNoop` also carries `time_archived` (13 of 13 with a marker and `kind: scheduled`). So the archive PATCH is neither refused nor ignored by the app — **the "PATCH ineffective" arm and the "OpenChamber ignores the native archive" arm are refuted for the scheduled population.**
2. **The broken arm is coverage, not mechanism.** The four unmarked, unarchived sessions are all runs that **never reached a marked exit**: three died abnormally mid-turn (malformed `<tool_call>` emitted as text), one ended after discovering the `dev-boards` MCP surface was missing from its own session. None of them is a `no-cards` / `no-claimable-cards` exit, so none wrote a marker — and with no marker, `question-notify`'s reader conjunction pushes (the alert the owner is complaining about), and the session stays in the list (the idle row the owner is complaining about).
3. **The gate-stop exits (OQ5's unmarked set) are the *contract* half of the same gap** — no session in today's sample can be positively identified as a `GATE: SKIP`/`GATE: LIVE` stop (those runs are indistinguishable from the abnormal ends without their prompt text), so C03a keeps a leg to classify future runs by their first-line verdict. The two gaps are the same shape: **a scheduled run that does no work but does not land on one of the two marked exits is neither marked nor archived.**
4. **Two side findings, outside the archive question:** (a) a scheduled board-coord session ran **without the `dev-boards` MCP tools** while the prefetch hook reached the same server (19:30 run) — a live availability defect in scheduled sessions, feeding the ask-2 runner work (C10); (b) the marked-but-unarchived row at 20:06 carries `openchamber.kind: none` and a `probeSentinel` — it is a probe/manual session, not a scheduled one, so the reader conjunction would alert it **by design** (OQ4); it is not evidence of an archive failure, and C03a keeps it as the manual-side control.

## What remains open (C03a's job)

- Reproduce the classification **on demand** instead of by hand: the audit script (C03a) regenerates this table for any window, so "did C03b fix it?" is a readback, not a memory.
- Attribute each future unmarked scheduled session to a verdict class (`gate-skip`, `gate-live`, `board-check-unavailable`, `abnormal-end`, `mcp-surface-absent`) from the launch text + message tail, which the script can read but not the plugin.
- Decide (with the owner's alert preference) whether a run that dies before any exit may be **engine-marked** — the `pipeline-locks` plugin knows exactly which roots never claimed, and `question-notify` already reads the session record; whether either may *write* session metadata is a mechanism fact C03b's dev must prove, not assume.

Read-only commands used (reproducible): `python3` stdlib `sqlite3` against `file:$HOME/.local/share/opencode/opencode.db?mode=ro`, queries over `session_v2` (`id,title,slug,agent,model,directory,metadata,time_created,time_archived`) and `session_message` (`session_id,type,seq,data`).

## Addendum — re-read 2026-11-03T22:45Z (the pattern reproduced while this ticket was being planned)

Same read-only method, whole `agent-board-coord*` population for `directory=/home/coder/SpencersLab`:

| population | count |
|---|---|
| scheduled runs with a `pipelineNoop` marker **and** `time_archived` | **55** |
| scheduled runs with a marker and **no** archive stamp | **0** |
| → archive-rate for marked scheduled runs, whole store | **55 / 55** |

Window `2026-11-02T00:00Z → 2026-11-04T00:00Z`, classified per the C03a vocabulary:

| class | scheduled | manual/none |
|---|---|---|
| `marked-archived` | **32** | 0 |
| `marked-unarchived` | 0 | **1** (the `probeSentinel` control — alerts by design) |
| unmarked + abnormal-end (raw `<tool_call>` / `<function=` tail) | **2** | 0 |
| unmarked + mid-turn death after the lock-state check | **3** | 0 |
| unmarked + `mcp-surface-absent` | **1** | 0 |
| probe/manual runs (no marker expected) | 0 | 3 |

Two new unmarked, unarchived scheduled rows appeared **after** the first read — `ses_e5c92db19f…` (22:00Z, tail is raw `<tool_call> <function=dev-boards_list_cards_in_list> …`) and `ses_e5c776275f…` (22:30Z, dies right after "Plugin is alive. Two other runs hold CICD and Context sets live") — so the coverage gap is not a historical artifact: roughly every other tick of the current pair of scheduled runners ends unmarked and keeps its alert + its idle row.

Consequences carried into the plan (no re-ask, no interpretation change):
1. **The mechanism claim is stronger, not weaker** — 55/55 marked scheduled runs are archived, so the archive call is definitively fine and C03b must not touch it.
2. **The coverage claim is live** — the failing population is runs that die before any exit; C03b fixes the stop-path half and states the mid-turn limit instead of guessing at a plugin-side marker writer.
3. **The baseline must not be a count** — the store is live, so C03a's parity acceptance is per session id against a fixture seeded from this table (plus a later-row control), never a total that any new tick can move.

---

## C03a script readback — the instrument reproduces this table (run 2026-11-04T06:05Z)

`bash scripts/session-noop-audit.sh --since 2026-11-02 --until 2026-11-04` (default `--repo` = the canonical root
`/home/coder/SpencersLab`, default `--db` = the host store, read through `file:…?mode=ro`): 41 board-coord rows —
`marked-archived` 33, `abnormal-end` 3, `mcp-surface-absent` 1, `did-work` 3, `marked-unarchived` 1; scheduled rows 37,
of which 4 carry no marker. The 33 is the artifact's 32 **plus** `ses_e5c776275f…`, which had not yet run its exit recipe
at the 22:45Z read and completed it afterwards — the count moved because the population moved, which is why the check below
is per id.

Per the AC1 rule the check is **per named id**, and the artifact's rows are the target:

| session (artifact's abbreviation) | created | artifact class | script verdict | marker | archived | reads |
|---|---|---|---|---|---|---|
| `ses_e5cae562ff…` | 11-03 21:30 | `marked-archived` | `marked-archived` | `no-claimable-cards` | yes | match |
| `ses_e5d00b9b2f…` | 11-03 20:00 | `marked-archived` | `marked-archived` | `no-claimable-cards` | yes | match |
| `ses_e5d37a4caf…` | 11-03 19:00 | `marked-archived` | `marked-archived` | `no-claimable-cards` | yes | match |
| `ses_e5dc0fbf8f…` | 11-03 16:30 | `marked-archived` | `marked-archived` | `no-claimable-cards` | yes | match |
| `ses_e5ddc7612f…` | 11-03 16:00 | `marked-archived` | `marked-archived` | `no-claimable-cards` | yes | match |
| `ses_e5d1c2cabf…` | 11-03 19:30 | `mcp-surface-absent` | `mcp-surface-absent` | none | no | match — the live defect keeps its own class |
| `ses_e5c92db19f…` | 11-03 22:00 | unmarked + raw `<tool_call>` tail | `abnormal-end` | none | no | match |
| `ses_e5ce54255f…` | 11-03 20:30 | unmarked + mid-turn death | `abnormal-end` | none | no | match (tail is empty: the turn was cut off) |
| `ses_e5cc9c99af…` | 11-03 21:00 | unmarked + raw `<tool_call>` tail | **no row** | — | — | the session is gone from the store (id-prefix and title reads both empty) |
| `ses_e5ce065e2f…` | 11-03 20:35 | unmarked + raw `<tool_call>` tail | **no row** | — | — | same — pruned since the 22:45Z read |
| `ses_e5c776275f…` | 11-03 22:30 | unmarked + mid-turn death | `marked-archived` | `no-claimable-cards` | yes | the 22:45Z read caught it mid-turn; it then ran the exit recipe (title is now `no-op 2026-11-03T22:42`, marker + archive present) |
| `ses_e5cfa57d6f…` | 11-03 20:06 | marked, unarchived, manual control | `marked-unarchived` | `no-cards` | no | match; its `openchamber.kind` is **absent** in the record, so the row reads `kind: null` — which is exactly why the reader's conjunction alerts it |

What the readback settles, with no re-interpretation:

- **The instrument's classification matches the hand table** for every artifact-named session still in the store:
  **9 verdicts match** (the five `marked-archived` rows, the `mcp-surface-absent` run, the two `abnormal-end` rows and the
  manual control), **2 ids are store-side losses** (pruned between the 22:45Z read and this run — no row either way), and
  **1 verdict legitimately changed** (`ses_e5c776275f…`: mid-turn at the earlier read, `marked-archived` now). Nothing in
  the table contradicts the instrument.
- **The store prunes.** Two of the six unmarked rows this artifact named no longer exist, so "6 unmarked" was a count
  of a live population, not a durable record. Any later readback must compare per id — AC1's rule, now demonstrated
  on the real store rather than only on the fixture (`tests/cf106-noop/surface.sh` N4's control arm pins the other
  half: a newer session moves no existing verdict).
- **One recorded death was not a death.** `ses_e5c776275f…` continued after the read and marked + archived, so the
  addendum's "roughly every other tick of the current pair ends unmarked" overstates the rate: in this window **4 of 37**
  scheduled rows carry no marker — 19:30 `mcp-surface-absent`, 20:30 and 22:00 `abnormal-end`, and 23:30 `did-work`.
- **The absent `gate-stop` row is an instrument coverage limit, not a clean sample** (review C03a, blocker 1 — this
  corrects the earlier "no sample in this window" wording, which read a blind spot as a finding). The class is
  **structurally unobservable** for the loop-launched population: review measured **0 of 49** board-coord sessions in the
  11-02…11-04 window and **0 of 123** store-wide with any user-message line matching the gate-line pattern, because the
  gate verdict reaches a transcript **only** through the `/pipeline-boards-hourly` command expansion
  (`.rulesync/commands/pipeline-boards-hourly.md:11`), while the live scheduled runs are launched by
  `.agents/loops/pipeline-worker.md` / `pipeline-worker-local.md`, whose prompt carries no gate block — **101 of 123**
  first prompts start with the loop body's `<!--`. `test_session`'s own readback measures the same thing on the script's
  row shape: window 11-02…11-05 → 64 rows, 0 `gate-stop`; store-wide → 93 rows, 0 `gate-stop`. (Row counts differ across
  the two reads by window and store filter, not by disagreement.)
  Therefore the post-merge readback does **not** judge a `gate-stop` row count: it judges the **marker columns** — a
  scheduled row that ended on a stop path with neither marker nor archive — per the flavor-labelled judgement in
  `tests/cf106-noop/readback.md`. C03b's target population stays unmeasured by this baseline either way.
- **Vocabulary mapping, stated once:** the artifact's "mid-turn death after the lock-state check" is not a class of the
  fixed vocabulary. The instrument reports it as `abnormal-end` when the tail is empty or carries raw call XML, and it
  falls through to `did-work` when a cut-off turn left a normal-looking last text — the 23:30 row (8 turns, last text
  reports it is still probing the MCP surface) is that case, and the artifact counts it among the broken runs. That
  resolution limit is the instrument's, not the evidence's; C03b's done-claim is judged on the marker columns, not on
  this class.
- **The two transcript heuristics over-match on quotes** (same limit, stated once so a future read is not over-trusted):
  `GATE_LINE` scans **any** user line, so a later message that merely *quotes* `GATE: LIVE` classifies a session that never
  stopped at the gate; `RAW_CALL` likewise over-matches an unmarked run that quotes `<tool_call>` while *explaining* the
  defect (exactly what this ticket's own evidence reads do). Both classes are therefore evidence-grade hints, never
  verdicts — which is another reason the marker columns carry the done-claim.
