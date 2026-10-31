---
name: pipeline-worker-local
schedule: 30 * * * *
enabled: true
model: gpu-ai/qwen3.8-flash-next-strata
agent: agent-board-coord
---

<!--
cf-90 Local sibling of pipeline-worker.md — the Provider: Local half of the
card's Provider-label task pattern. Schedule is staggered to :30 off the API
task's :00 so one tick never stacks two claims; the lease-lock surface already
serializes card claims across the two tasks, and labeled cards split cleanly
by provider. The model is the local tier confirmed in the cf-90 batched round
(2026-10-31); pipeline-models maps every tier onto it for Provider: Local
runs — its table is that authority, cited not copied. The shipped posture is
enabled: true with scheduler hygiene human-owned (main 080c9878a precedent,
same as the API file).

OpenChamber hand-offs, human-owned and one-time (DECISIONS): this task's
FIRST sync needs the loopApprovals approval (the task fingerprint), and
permissionAutoAccept ("Always Allow") must be toggled once in the task UI —
the file format cannot express it, the toggle survives loop re-sync, and
ledger card L1 tracks removing the need later.

Swap target (D30): slash dispatch of a plugin command from loop text is
unproven on the pinned OpenCode v2.1.4, so the body below is the plain-text
worker sentence, as on the API file.
-->

Load the boards skill and run exactly one Parallel pipeline loops iteration serving `Provider: Local`: the scheduled walk takes cards explicitly labeled `Provider: Local` plus unlabeled cards — this task is the planned steady-state taker of the unlabeled pool (the boards skill's Provider filtering section is the authority for the walk). A claimed unlabeled card triggers the ask before routing: ask which provider applies, then request the human apply the matching `Provider:` label. Route every tier through the `pipeline-models` local mapping. First call pipeline_status, then follow the skill.
