---
name: pipeline-worker
schedule: 0 * * * *
enabled: true
model: gpu-ai/qwen3.8-flash-next-strata
agent: agent-board-coord
---

<!--
cf-76 pipeline worker loop. OpenChamber syncs loop files from the project
tree; schedule is a cron — hourly spans the 2 h stale window twice (D21);
timezone is omitted so the server default applies; the model is the code
tier by the Q2 ruling and the agent is the board-coord ALIAS (D15 — the
command/gate/saved-approval continuity name).

Live state, verified 2026-10-29 against OpenChamber scheduledTasks (RESEARCH
W2 F5 in .agents/plans/2026/2026-10-chore-board-tick-cleanup/): this file
syncs as the "pipeline-worker" task — enabled, cron 0 * * * * UTC, agent
agent-board-coord, lastRun 2026-10-29T13:19:41Z success. The frontmatter
enabled: true is the owner's own toggle as landed on main (080c9878a,
2026-10-30): scheduler decisions stay human-owned (OQ10 ruling), and
/pipeline-boards-hourly with its gate stays the documented fallback entry.
The legacy "Hourly Pipeline call" daily task (also enabled, runs no gate) is
human-owned scheduler hygiene — retiring or repointing it is the owner's call.

cf-90 Provider round: this scheduled task serves `Provider: API` — its walk
takes only cards explicitly labeled `Provider: API`, never unlabeled cards;
the Local sibling pipeline-worker-local.md (hourly :30) is the planned taker
of cards without a Provider label. The pickup-filter semantics live in the
boards skill's Provider filtering section — this file names the provider,
never restating the walk. A run pointed at an unlabeled card arrives only
through a manual launch the user initiates, and it asks which provider
applies before any Model(s)/provider routing, then requests the human apply
the matching `Provider:` label (labels stay human-owned). OpenChamber
hand-offs stay human-owned (DECISIONS post-research correction, 2026-10-31):
post-merge BOTH tasks need loopApprovals before either runs. This task's
provider-round body edits rotated its approved fingerprint (live-approved
8137741841… vs 9ae4146e… recomputed over the landed body; every later body
edit — this paragraph included — rotates it again, so approve whatever value
the task UI shows at merge time), and reconcileLoopTasks pins a
fingerprint-mismatched task as "outdated" with its enabled flag forced false
until re-approved: merge day silently stops this hourly walk otherwise. The
Local sibling needs its first approval likewise. Then permissionAutoAccept
("Always Allow") is toggled on both — the file format cannot express it, the
toggle survives loop re-sync, and ledger card L1 tracks removing the need.
Run tags are retired for every
flavor (cf-90): each run's surfaces are named by the card's final slug
alone.

Swap target (checklist item 3): slash dispatch of a plugin command from loop
text is unproven on the pinned OpenCode v2.1.4 (D30 — opencode run sent a
"/cmd" line as literal text), so the body below is the plain-text worker
sentence and /pipeline-tick stays out of it. If the live smoke proves
dispatch, replace the body with the bare command /pipeline-tick and nothing
else on the line (no arguments — multi-line command arguments are broken on
that build). With the plain-text body the tick executor never runs from
here, and determinism still holds: the same guarded reap passes at every
claim and on the reap timer.
-->

Load the boards skill and run exactly one Parallel pipeline loops iteration. First call pipeline_status, then follow the skill.