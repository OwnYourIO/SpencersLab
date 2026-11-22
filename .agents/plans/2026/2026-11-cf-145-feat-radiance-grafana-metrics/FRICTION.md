# Friction

Append-only. What blocked or slowed runs, each with the resolution used. Status: open -> fixed/ignored (never deleted).

## Open
- 2026-11-22 test: tests/renovate legs have NO discovery mechanism anywhere (no CI/Makefile/scripts wiring) — landing a leg is drop-file+chmod+x, running is the manual `bash tests/renovate/<leg>.sh` convention; a coordinator expecting a glob to pick new legs up would be wrong. [open]
- 2026-11-22 review: `npx rulesync@latest generate --check` false-flags stale generated files (version drift); the canonical check is the CI-pinned `npx --yes rulesync@37.0.0 generate --check`. [open]
- 2026-11-21 coord: kickoff permission-policy friction — the mint/warm scripts are denied `external_directory` when `workdir` is outside the session's own location (October precedent ran them from the main checkout; from the cf-11 worktree it was denied). Resolution used this run: ran both scripts from the session's current location where the tracked `scripts/` copy exists — worked (`MINTED` + `WARMED` + move). Needs a human ruling on the sanctioned invocation path. [open]
- 2026-11-21 coord: mid-run the `AI` claim was reaped by an engine restart while the session stayed alive; the sanctioned card-id takeover claim first answered `already_held` because the session's root record still pinned the reaped setId. Resolution used (owner-authorized takeover): released the phantom root (`ok:true, released:[AI]`), then re-claimed under the card-id key immediately — clean lock restored (`80402038`). The reaper should probably clear per-root claim records with the lock file, else the takeover needs this two-step. [open]
- 2026-11-21 coord: post-takeover, `pipeline_status` enumerated zero groups while the held card-id claim was provably alive (`pipeline_heartbeat` ok:true + beaten, re-claim answered already_held naming this session) — the status groups view is blind to the takeover entry (projection quirk or reap-lineage move). Resolution used: treated the claim/heartbeat answers (identity channel D28) as authoritative over the enumeration; continued under the owner-authorized lock. [open]
- 2026-11-21 explore: k8s MCP answers `null` (not an empty list) for absent CR kinds — a bare read looks like an error. Resolution used: validate absence against a positive control resource before concluding. [open]
- 2026-11-21 explore: `readonly-global-grafana` dashboard search caps at 50 rows. Resolution used: full enumeration via `grafana_api_request` against `/api/search`. [open]
- 2026-11-21 dev/C02: inline `python -c "…"` string escaping false-failed a manual datasource-sed assert (shell `\"` artifact, not a chart fact). Resolution used: heredoc python or the shell-immune T4 test for rendered-byte assertions; future render-leg checks use heredoc. Recurred in C02 review (same class — chart emits `| sed ...` continuation; block-dump verification is the proven path). [open]
- 2026-11-21 coord: C01 dev round-1 session died mid-turn on a harness transport error ("OpenAI Chat tool call delta is missing id or name") with no RESULT. Resolution used: fresh relaunch of the same dev variant with explicit ground-truth-check instructions for possible partial edits (crash detection delegated to the dev's validation run because the coord's `git status` is outside its shell grants — firewall-correct, not a defect). If the class recurs on flash launches, it belongs upstream, not in the pipeline. [open]

- 2026-11-21 dev/C03: execute-tool JS template literals break on markdown backticks embedded in heredoc payloads (syntax-error artifact). Resolution used: write the checker to /tmp/opencode and run it via shell — the proven heredoc path from the C02 note. [open]

## Fixed
- ...
