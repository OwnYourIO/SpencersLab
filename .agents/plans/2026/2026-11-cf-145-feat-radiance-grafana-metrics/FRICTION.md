# Friction

Append-only. What blocked or slowed runs, each with the resolution used. Status: open -> fixed/ignored (never deleted).

## Open
- 2026-11-21 coord: kickoff permission-policy friction — the mint/warm scripts are denied `external_directory` when `workdir` is outside the session's own location (October precedent ran them from the main checkout; from the cf-11 worktree it was denied). Resolution used this run: ran both scripts from the session's current location where the tracked `scripts/` copy exists — worked (`MINTED` + `WARMED` + move). Needs a human ruling on the sanctioned invocation path. [open]
- 2026-11-21 coord: mid-run the `AI` claim was reaped by an engine restart while the session stayed alive; the sanctioned card-id takeover claim first answered `already_held` because the session's root record still pinned the reaped setId. Resolution used (owner-authorized takeover): released the phantom root (`ok:true, released:[AI]`), then re-claimed under the card-id key immediately — clean lock restored (`80402038`). The reaper should probably clear per-root claim records with the lock file, else the takeover needs this two-step. [open]
- 2026-11-21 coord: post-takeover, `pipeline_status` enumerated zero groups while the held card-id claim was provably alive (`pipeline_heartbeat` ok:true + beaten, re-claim answered already_held naming this session) — the status groups view is blind to the takeover entry (projection quirk or reap-lineage move). Resolution used: treated the claim/heartbeat answers (identity channel D28) as authoritative over the enumeration; continued under the owner-authorized lock. [open]
- 2026-11-21 explore: k8s MCP answers `null` (not an empty list) for absent CR kinds — a bare read looks like an error. Resolution used: validate absence against a positive control resource before concluding. [open]
- 2026-11-21 explore: `readonly-global-grafana` dashboard search caps at 50 rows. Resolution used: full enumeration via `grafana_api_request` against `/api/search`. [open]
- 2026-11-21 coord: C01 dev round-1 session died mid-turn on a harness transport error ("OpenAI Chat tool call delta is missing id or name") with no RESULT. Resolution used: fresh relaunch of the same dev variant with explicit ground-truth-check instructions for possible partial edits (crash detection delegated to the dev's validation run because the coord's `git status` is outside its shell grants — firewall-correct, not a defect). If the class recurs on flash launches, it belongs upstream, not in the pipeline. [open]

## Fixed
- ...
