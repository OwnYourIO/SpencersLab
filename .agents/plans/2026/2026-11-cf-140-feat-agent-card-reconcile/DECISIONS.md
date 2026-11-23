# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions
- Card-driven run (AD-140, board `cf-140`); kickoff answers come from the card's checklists, never re-asked.
- Exploration ran as FOUR parallel `agent-explore` scouts, so the stage writes one file per scout instead of one shared `EXPLORE.md`: `EXPLORE-plugins.md`, `EXPLORE-agents.md`, `EXPLORE-wekan-mcp.md`, `EXPLORE-session-api.md`. Same for research: `RESEARCH-r<N>-<topic>.md` per session, merged into `RESEARCH.md` by a dedicated session once all rounds land.
- Model tiers: coord + chunk review + test + dev = `openrouter/qwen/qwen3.8-flash`; plan + final review = `openrouter/qwen/qwen3.8-2.4t-a95b`; explore + research = `gpu-ai/qwen3.8-flash-next-radiance`.
- `Deployment` is unchecked on the card: commit-only, no push, no deploy-fixer spawn; merge and ArgoCD sync stay human-owned.

## Decisions
- 2026-11-23 human: continue the run under the live claim after a `PIPELINE LOCK LOST` notice; no takeover, no re-claim, no release. Why: `pipeline_status` re-read shows this session still holding `setId=34617c28…` live with no new reap, and the review later confirmed the mechanism — the audit log carries an 8-row spurious `stolen` storm on a live claim, so the firewall false-positives in production. Recorded in `kickoff.claim`.
- 2026-11-23 human: research + exploration run on `gpu-ai/qwen3.8-flash-next-radiance`, superseding the card body's `radiance tp2 27b` ask; API assignments unchanged. Why: the tp2-27b lane is documented parked at `replicas 0` and answers a loud 502; routing a 5-round research wave there would fail the run.
- 2026-11-23 coord: the card's legacy 11-item Lifecycle (no `Session Rename`/`Worktree Creation` rows, `Pre Research`/`Post Research` present) is consumed as Exploration + Pre Research + Planning + Post Research + Test Writing + Chunk Development + Chunk Review + Final Review, with the two leading gates RUN. Alternatives rejected: treating their absence as an opt-out (uncommitted-in-place, zero commits). Why: the blank default checks both, so a card predating the names expresses drift, not the deliberate opt-out D15/D28 require; and a ticket rewriting three hand-written plugins needs commits and a worktree.
- 2026-11-23 coord: AD-73 joins this run as a grouped sibling (inbound `related-to` -> AD-140) and runs under this claim, never separately. Why: the grouped-sibling flow. Its board-field deletion leg stays owner-owned; only the doc/wording sweep is agent work here.
- 2026-11-23 coord (from `REVIEW-existing-plugins.md`): pipeline leases CAN be retired — the owner's "two sessions on one pipeline is a non-event" intuition holds, because **Executing** membership plus `already_held` was always the real card-level guard. What must survive in `card-runner`: a zombie firewall re-keyed on a run registry (a woken dead run would otherwise commit into its successor's worktree), a durable cross-process per-card registry with restart-resume, dead-run alerting, the wake contract, the compaction contract, the no-op marker (predicate redefined), `localIso`, and the never-throw law.
- 2026-11-23 coord (same review): symptom (a) — board block re-injection — is a capability flap, not a tunable bug: the process serving follow-ups had no `ctx.storage` binding, so `writeOnce` never advanced the once-mark. The replacement must move the once-mark off `ctx.storage` onto a provably cross-process surface. Live evidence: 15 of 17 long-lived board-coord sessions re-injected, worst case 12 of 34 prompts.
- 2026-11-23 coord (same review): scope cuts carried into planning — drop webhooks, drop the `format: yaml` MCP tool argument (a card dump needs no new tool), scope "card objective completed" down to explicit signals, and repair the pre-existing `AGENTS.md`/`.rulesync/rules/overview.md` drift (verified red at HEAD) in the first commit.

## Deferred
- OQ-R1 (owner): re-enable `question-notify` or absorb its three detection legs into `card-runner` — the phone channel has been owner-disabled since 2026-11-21 and the Awaiting-Answers alert path assumes it.
- OQ-R2 (owner): provision the `Awaiting Answers` + `Timeout` lists through the provision engine, or accept the `timeouts.jsonl` degrade as permanent design.
- OQ-R3 (plan): keep the `local.pipeline-locks` plugin id inside `card-runner` (zero kv migration) or rename and migrate rows at setup.
- OQ-R4 (research, gates wave-2 dev): pending-question persistence + the answer signal on the running v2.3.2 build, and busy/idle emission — assigned to research round R3.
- Review finding B1 (second-coordinator-on-a-question-paused-card): no question events exist, so tree-age alone reads a paused run as dead. Gating acceptance criterion for the plan.
- Review finding: a compaction handoff-successor reads as "run ended" and would double-spawn; must be discriminated in the run registry.
- YAML-dump file home is undefined for three shapes (Worktree-unchecked run, grouped sibling, Rework re-pick) — plan must name one rule.
- Change-forwarding risks becoming the new context injector — the pivot's own symptom (a) reintroduced; the plan needs a bound.
