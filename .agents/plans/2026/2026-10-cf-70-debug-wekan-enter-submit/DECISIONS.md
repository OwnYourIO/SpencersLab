# Decisions

Append-only. Newest at the bottom.

## Conventions
- Research-only card (board label `Research`): iterative loop per the `boards` skill — round 1 → ONE batched question round → further research in the same session → result comment + write-back → Review. Never reaches agent-plan/test/dev/review.

## Decisions
- 2026-10-26 coord: Card #70 arrived with ALL five checklists unchecked (dormant createCard rule). Routed from standard defaults WITHOUT mutating the card: Model(s) → Qwen Flash (openrouter/qwen/qwen3.8-flash, every tier); Research → Agent Decides; Human in the Loop → Plan. Type unset → best guess `debug` (regression investigation), joins the batched round.
- 2026-10-26 coord: Slug minted as best guess `cf-70-debug-wekan-enter-submit` (cardNumber 70 from get_card; empty description → title is the request). Names folder/branch/session alike (D10); batched round confirms or replaces.
- 2026-10-26 coord: This launch carried no `Session origin:` line → SESSION_URL_BASE UNRESOLVED → every link slot (claim comment, `session` custom field, result comment) gets the RAW session id ses_e85bfecb1ffejpDAfp91lHp8b1, per the D23-r2 fallback. No host re-guessing.
- 2026-10-26 coord: Surface naming executed through the local OpenChamber API (read-merge-write patch on own session) because the harness catalog exposes neither `session_rename` nor `worktree_create` — see FRICTION.md. No worktree created: research-only run writes only the plan folder.

## Deferred
- Live-browser verification of the setting toggle rides on the human's Review decision (residual unknowns carried in the result comment). If a field still ignores Enter with the pref ON → card back to Rework as a real upstream bug.

