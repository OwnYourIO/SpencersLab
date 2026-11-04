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

1. **Zero `gate-stop` rows without a marker and an archive.** Every run that ended
   on `GATE: SKIP`, `GATE: LIVE` with filtered-in Executing cards, or a failed board
   check must read `marked-archived` — that is the coverage C03b adds. A row showing
   `gate-stop` means the run stopped without marking: the contract leg failed.
2. **No new `unmarked-archived` scheduled rows.** A marker without an archive (or the
   reverse) means the exit recipe ran half — the read-merge-write mandate or the
   `{"archived": true}` PATCH was dropped.
3. **`abnormal-end` and `mcp-surface-absent` rows may remain.** That is the honest
   limit stated once in the boards skill: a run that dies before reaching an exit
   cannot mark itself. Their alert standing is accepted for this ticket; if the
   engine-side close-out was shipped, C03b's RESULT says so and these rows should
   start carrying markers — if it was deferred, a follow-up card exists on the owner's
   board instead.
4. **`marked-archived` stays the dominant class for scheduled no-ops** — 13/13 in the
   baseline read. A regression there means the two legacy exits broke, not the new ones.

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
