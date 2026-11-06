# No-op audit readback — how to judge C03b with a measurement, not a memory

Test-tree runbook for `scripts/session-noop-audit.sh` (cf-106 C03a). The audit is
the instrument: it regenerates the session-store classification that the planning
pass produced by hand in
`../../../.agents/plans/2026/2026-11-cf-106-feat-coord-fixes/2026-11-03-cf-106-feat-coord-fixes-noop-evidence.md`.
C03b's fix is judged on this output, never on the diff.

## Who runs this, and why not the pipeline

A **human or an interactive session** runs it. An unattended scheduled tick cannot:
its `bash scripts/…` call resolves to the `ask` posture and denies there, and the
owner's answer 11 keeps that toggle posture — **no shell grant is added for this
script anywhere** (`tests/cf106-noop/surface.sh` N3 machine-checks that no agent
definition names it). The script is read-only by construction (`mode=ro` SQLite
URI, no `opencode api` POST/PATCH, no board call, no `.pipeline/` touch; N2
enforces it) — it reads the same host store whichever worktree the reader sits in,
because sessions live per project/directory and `--repo` filters on
`session_v2.directory`.

## Commands

```bash
# the window that contains the ticks under review
bash scripts/session-noop-audit.sh --since 2026-11-04 --until 2026-11-06 --json \
  | tee /tmp/opencode/noop-audit-$(date +%Y%m%dT%H%M%SZ).json

# one repo only, capped, human-readable
bash scripts/session-noop-audit.sh --since 2026-11-04 --limit 40
```

`--db <path>` points the audit at a copied store snapshot (the suite points it at a
fixture it builds itself; the live 500 MB store never enters a gate). Default is the
host store, `~/.local/share/opencode/opencode.db`.

Verdict vocabulary — exactly one class per row, marker classes winning over stop
shapes: `marked-archived`, `marked-unarchived`, `unmarked-archived`, `gate-stop`,
`abnormal-end`, `mcp-surface-absent`, `did-work`.

Two reading rules that keep the table honest. `abnormal-end` means *evidence* of a
death — fewer turns than the floor (3), or a last turn with no text; a transcript the
audit cannot read at all (no `session_message` rows, unparseable `data`, malformed
`metadata`) decides `did-work` instead, so a store-schema change never masquerades as a
wave of runs that died before any exit. And an empty `turns` on a row that has session
data is the tell that the store shape moved: re-check the instrument before believing
any class distribution.

## Baseline parity (C03a AC1)

For the artifact's window (`--since 2026-11-02 --until 2026-11-04`), the audit must
reproduce the artifact **row by row for the session ids it names**: 32
`marked-archived` scheduled rows, 6 unmarked scheduled rows (2 `abnormal-end` on raw
`<tool_call>` XML, 3 mid-turn deaths after the lock check, 1 `mcp-surface-absent`),
and the 1 manual `probeSentinel` control row. Compare **per id**, never by total
count — the store is live, and a newer session must not move an older verdict
(N4's control arm pins exactly that).

## PASS after C03b (chunk AC8)

Read the table for the window that starts at the first scheduled tick *after* the
merge (at least two ticks, so a single lucky run cannot carry the claim):

Two launch flavors, and they do not prove the same thing. Only one of them ever puts
gate text into a transcript:

| flavor | started by | gate verdict in the prompt? | what a stop-path run looks like |
|---|---|---|---|
| scheduled loop | `.agents/loops/pipeline-worker.md` and `pipeline-worker-local.md` — the live hourly population (C10 collapses them to one) | **no**: neither loop prompt carries a gate block (0 `GATE:` lines in either file, read 2026-11-04) | never `gate-stop`; after C03b a stop-path tick reads `marked-archived`, a half-run reads `marked-unarchived`/`unmarked-archived`, a death reads `abnormal-end` |
| `/pipeline-boards-hourly` | the command whose expansion runs the gate (the verdict block enters at `.rulesync/commands/pipeline-boards-hourly.md:11`) | **yes** | `gate-stop` while it stops on a gate verdict without marking |

Measured through the instrument rather than recalled (read-only, `--json`,
2026-11-04): window `--since 2026-11-02 --until 2026-11-05` → 64 rows, **0
`gate-stop`**; store-wide → 93 rows, **0 `gate-stop`**. Review measured the same shape
differently sized (0 of 49 in the window, 0 of 123 store-wide match the gate line). So
the live scheduled population cannot produce a `gate-stop` row at all, and an arm that
waits for one can never fire.

Judge C03b on the **marker columns**, and label the flavor of every row you paste:

1. **No scheduled row that ended on a stop path is missing both a marker and an
   archive.** The failure pairs are `unmarked-archived` (archived without marking) and
   a `marked-unarchived` still unarchived an hour later (marker written, the
   `{"archived": true}` PATCH dropped). Those pairs are observable in **both** flavors,
   which is why they are the judge.
2. **A `gate-stop` row proves the failure outright — for the hourly flavor only.** Zero
   such rows proves nothing about the loop flavor; write which flavor each row came from
   and, when the row cannot tell you (`kind`, `title` and the excerpt are the only
   clues), write `flavor: unknown` rather than guessing.
3. **No new `unmarked-archived` scheduled rows** against the artifact's baseline for the
   same window.
4. **`abnormal-end` and `mcp-surface-absent` rows may remain.** That is the honest
   limit stated once in the boards skill: a run that dies before reaching an exit
   cannot mark itself. Their alert standing is accepted for this ticket; if the
   engine-side close-out was shipped, C03b's RESULT says so and these rows should
   start carrying markers — if it was deferred, a follow-up card exists on the owner's
   board instead.
5. **`marked-archived` stays the dominant class for scheduled no-ops** — 32 of the 38
   scheduled rows in the artifact's read. A regression there means the two legacy exits
   broke, not the new ones.

**Excerpt caution (USER-owned step 5):** `excerpt` is the last assistant text collapsed
and cut at 160 characters, so a pasted row can end mid-token — attribute a row's class
from `verdict`/`turns`, and quote the session id, never the excerpt, when an excerpt
looks truncated.

## The alert-silence claim, checked against a column

The owner's complaint is "the phone rings for ticks that did nothing" plus "idle
sessions sit in the list". Both claims are judged on the `marker` / `archived`
columns, not on recollection:

- Silence needs the reader's conjunction: OpenChamber `kind == "scheduled"` **and** a
  well-formed `metadata.pipelineNoop` (`reason` non-empty; `at` is an audit stamp,
  never a gate). So count rows where both hold and compare with the pushes the phone
  actually received — a scheduled row with no marker is expected to alert.
- A marked **manual** run still alerts by design (OQ4): `kind` is a column in the
  audit output for exactly this check.
- A crash push is **never** suppressed: `question-notify` consults the predicate on
  the FINISHED event only, and the reap alert stays gated only by `haNotify` (the
  owner's answer 13). `abnormal-end` rows therefore still page — by design.

## If the numbers disagree with the contract

Do not re-tune the script to match a memory. Re-read the artifact
(`…-noop-evidence.md`), re-run with an explicit window, and record the divergence in
the ticket's `FRICTION.md` with the session ids: the classification vocabulary is the
readback's authority, and a class that cannot be derived is a defect in the
instrument, not a license to reinterpret the evidence.
