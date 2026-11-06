---
name: pipeline-worker
schedule: 0 * * * *
enabled: true
model: gpu-ai/qwen3.8-27b-q4
agent: agent-board-coord
---

<!--
Single scheduled runner (cf-106 C10). OpenChamber syncs loop files from the
project tree; schedule is a cron — hourly spans the 2 h stale window twice
(D21); timezone is omitted so the server default applies; the agent is the
board-coord ALIAS (D15 — the command/gate/saved-approval continuity name).
The model is the owner-ruled runner literal `gpu-ai/qwen3.8-27b-q4` (cf-106
OQ-14, 2026-11-03): the runner rides the Dense/local default C02 landed
instead of the old flash literal. The catalog churns, so the pin moves only
by a fresh user ruling — if a later tick finds the arena not serving it, the
fix is a fresh owner ruling plus a re-pin, never a silent literal change.
The recognized frontmatter set is name/schedule/enabled/model/agent/
timezone — there is no `provider:` key: the provider rides the model:
string (provider/model), while per-card provider choice stays coord-side
(the card's `Provider:` label routes models, not pickups).

Live state, verified 2026-10-29 against OpenChamber scheduledTasks (RESEARCH
W2 F5 in .agents/plans/2026/2026-10-chore-board-tick-cleanup/): this file
syncs as the "pipeline-worker" task — enabled, cron 0 * * * * UTC, agent
agent-board-coord, lastRun 2026-10-29T13:19:41Z success. The frontmatter
enabled: true is the owner's own toggle as landed on main (080c9878a,
2026-10-30): scheduler decisions stay human-owned (OQ10 ruling), and
/pipeline-boards-hourly with its gate stays the documented fallback entry.
The legacy "Hourly Pipeline call" daily task (also enabled, runs no gate) is
human-owned scheduler hygiene — retiring or repointing it is the owner's call.

Single-runner hand-off (cf-106 C10, OQ-14): this ONE task serves both
Provider flavors; the run routes from the card's `Provider:` label per the
boards skill's Provider filtering section, which owns the routing and the
unlabeled-card ask. The :30 staggered twin is retired — its live task's
removal is the owner's step (USER-owned step 4). OpenChamber hand-offs stay
human-owned (DECISIONS post-research correction, 2026-10-31): this body
edit rotated the task's approved loopApprovals fingerprint, and every later
body edit — this paragraph included — rotates it again, so approve whatever
value the task UI shows at merge time; reconcileLoopTasks pins a
fingerprint-mismatched task as "outdated" with its enabled flag forced
false until re-approved, which silently stops the hourly walk on merge day
otherwise. Then permissionAutoAccept ("Always Allow") is toggled on — the
file format cannot express it, the toggle survives loop re-sync, and ledger
card L1 tracks removing the need. Run tags are retired for every flavor
(cf-90): each run's surfaces are named by the card's final slug alone.

Known failure the preload legs degrade around (cf-106 C10): the 2026-11-03
19:30Z scheduled run reported the `dev-boards` MCP tools missing from its
own session while the board-context prefetch hook reached the same server
(evidence artifact 2026-11-03-cf-106-feat-coord-fixes-noop-evidence.md,
class `mcp-surface-absent`). A run must probe `tools/list` and, when the
surface is absent, degrade per the boards law instead of stalling; the
defect itself is out of this ticket's file set and rides the owner's
follow-up card.

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

Load the boards skill and run exactly one Parallel pipeline loops iteration. First call pipeline_status, then follow the skill. This one scheduled task serves both Provider flavors — the card's `Provider: API` or `Provider: Local` label routes the model inside the run, per the boards skill's Provider filtering section, and a run that takes an unlabeled card asks the user which provider applies before any routing. The run starts with the structural board-context block and receives the claimed card's details on the claim answer, so the first turn does not spend round-trips; a no-work tick takes the marked, archived exit the boards skill's No-op marker section defines.
