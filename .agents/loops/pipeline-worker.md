---
name: pipeline-worker
schedule: 0 * * * *
enabled: true
model: gpu-ai/qwen3.8-flash-next-strata-q4
agent: agent-board-coord
---

<!--
Single scheduled runner (cf-106 C10). The model is the owner-ruled runner
literal gpu-ai/qwen3.8-flash-next-strata-q4 (owner ruling 2026-11-09,
confirmed in-session; supersedes cf-106 OQ-14 2026-11-03); the catalog
churns, so it moves only by a fresh owner ruling.

Live state, verified 2026-10-29 against OpenChamber scheduledTasks: this
file syncs as the "pipeline-worker" task — enabled, cron 0 * * * * UTC,
agent agent-board-coord. The frontmatter enabled: true is the owner's own
toggle (080c9878a); scheduler decisions stay human-owned. The legacy
"Hourly Pipeline call" daily task (enabled:false per the 2026-11-07 live
probe) is human-owned scheduler hygiene.

Body edits rotate the task's approved loopApprovals fingerprint; a
fingerprint-mismatched task sits loopApproval:"outdated" with enabled
forced false until the owner re-approves it. permissionAutoAccept ("Always
Allow") is a UI-only toggle the file format cannot express; it survives
loop re-sync, and ledger card L1 tracks removing the need.

Swap target: if a live smoke ever proves slash dispatch from loop text,
replace the body with the bare command /pipeline-tick and nothing else.
-->

Load the boards skill and run exactly one Parallel pipeline loops iteration. First call pipeline_status, then follow the skill. This one scheduled task serves both Provider flavors — the card's `Provider: API` or `Provider: Local` label routes the model inside the run, per the boards skill's Provider filtering section, and a run that takes an unlabeled card asks the user which provider applies before any routing. The run starts with the structural board-context block and receives the claimed card's details on the claim answer, so the first turn does not spend round-trips; a no-work tick takes the marked, archived exit the boards skill's No-op marker section defines.