---
name: pipeline-dispatch
schedule: 0 * * * *
enabled: true
model: gpu-ai/qwen3.8-flash-next-strata-q4
agent: agent-board-dispatch
---

<!--
The shared-session dispatcher (cf-126). This file is the SECOND dispatcher
loop file the Ruling OQ1 chose (owner ruling 2026-11-17): the walk moves to
this task's dispatcher session while .agents/loops/pipeline-worker.md stays
BYTE-UNTOUCHED beside it — no fingerprint rotation, no re-approval of the old
loop. The old OpenChamber task's deletion is the owner's scheduler-hygiene
step; until it runs, the window dedupes on the lock surface and the card's
Executing membership, so no card is double-run or lost. The owner creates this
task from this frontmatter as the cutover's first step (agent
agent-board-dispatch, the runner literal as written here, hourly, enabled).

The model row is the owner-ruled runner literal
gpu-ai/qwen3.8-flash-next-strata-q4 (owner ruling 2026-11-09, confirmed
in-session; supersedes cf-106 OQ-14 2026-11-03 — the catalog churns, so it
moves only by a fresh owner ruling; cf-126 C04 is the wave that may flip it,
gated on that chunk's owner ruling + merge + pod-scale + receipt facts).

Body edits rotate this task's approved loopApprovals fingerprint; a
fingerprint-mismatched task sits loopApproval:"outdated" with enabled forced
false until the owner re-approves it. Scheduler decisions stay human-owned.
-->

Check whether a live pipeline-dispatcher session exists (`opencode api get /api/session` — filter records with `agent == "agent-board-dispatch"` AND `metadata.pipelineDispatcher` true, excluding your own id). If one exists: POST this same tick text to it (`opencode api post /api/session/<id>/prompt`) and end with the no-op `delegated` marker plus the archived exit, per the boards skill's No-op marker subsection — you are your own session record and you did no board work. If none exists: you ARE the dispatcher — first mark your own session record (`opencode api patch /api/session/<id>` with `metadata.pipelineDispatcher = true`, the sibling marker in the same metadata namespace the no-op marker uses), then load the boards skill and run exactly one Parallel pipeline loops iteration: first call `pipeline_status`, then follow the skill's Dispatcher section.
