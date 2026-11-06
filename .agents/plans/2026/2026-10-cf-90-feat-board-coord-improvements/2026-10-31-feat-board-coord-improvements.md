# PLAN: agent-board-coord improvements (card #90)
feature: 2026/2026-10-cf-90-feat-board-coord-improvements

## Goal
Ship the card's in-scope core: an idempotent board-provisioning command
(Backlog→Planning list sync, `Bucket: <list>` labels + per-list rule pairs,
Provider labels), Provider: API/Local task filtering with a duplicated Local
loop task, the no-cards archive-and-never-ask exit, the follow-up-card
protocol (timing + parent labels) with the deferred-cards ledger created
on-board, slug auto-accept, global run-tag retirement, the -pr description
updates, and the -deploy variant DEFINITION. Deep-research grounded in
RESEARCH.md (Before round done; its F1–F10 findings are the design basis).

## Out of scope
- The actual CI workflows, playwright/kopia/test-env mechanics, env-var
  secret plumbing IMPLEMENTATION, and the linting plugin — all deferred to
  the ledger cards (appendix), per the card's own scoping.
- wekan-mcp container code changes (label-on-card tool, pin bump) — ledger
  cards L4/L5; this run consumes the deployed surface as-is with documented
  fallbacks.
- Any OpenChamber UI operation (task approval, Always-Allow toggles) —
  human hand-offs, recorded in DECISIONS.md.
- Any live board mutation except C07's ledger cards; the one live
  provisioning run is a post-merge human-confirmed hand-off.

## Commands
- regenerate: `rulesync generate` (run TWICE; second must be a no-op), then `rulesync generate --check`
- suites (offline bash text-pin suites — this repo has NO pytest for machinery):
  `bash tests/agent-board-coord/rulesync-surface.sh && bash tests/agent-board-coord/agents-md.sh && bash tests/agent-board-coord/gate.sh`
  `bash tests/noop-marker/surface.sh && bash tests/session-origin/surface.sh && bash tests/session-origin/script.sh && bash tests/kickoff-branch/surface.sh && bash tests/kickoff-branch/script.sh`
  `bash tests/wekan-board-provision/surface.sh` (new, C01) · `bash tests/provider-loops/surface.sh` (new, C04) · `bash tests/agent-dev-deploy/surface.sh` (new, C06)
  `bash tests/wekan-mcp/tools.sh && bash tests/wekan-mcp/skill-surface.sh && bash tests/wekan-mcp/create-list.sh && bash tests/wekan-mcp/board-provisioning.sh && bash tests/wekan-mcp/board-context.sh`
  `bash tests/agent-perms/surface.sh && bash tests/standalone-agents/surface.sh && bash tests/coord-inwork/surface.sh && bash tests/pipeline-models/surface.sh && bash tests/pipeline-push-pr/surface.sh && bash tests/board-preload-probe/surface.sh`
- dry-run (C01): `python3 scripts/provision-board.py --fixture tests/wekan-board-provision/fixtures/ai-dev-live-2026-10-31.json --dry-run` → expected action set; `... --fixture .../ai-dev-full-provisioned.json --dry-run` → zero actions
- quality gate: `npx aislop ci --changes` (every touched file; review re-runs)
- frontmatter validity: `python3 -c "import yaml,glob; [yaml.safe_load(open(f).read().split('---')[1]) for f in glob.glob('.opencode/agents/agent-*.md')]"`
- grep invariants (per-chunk pins, run by review): run-tag retirement (no `run tag`/`run_tag` outside retirement wording), slug auto-accept sentence, `{"archived": true}` + never-ask in both no-op exits, provider-filter sentences in both loop files, except-Research parent-label rule
- helm: N/A this ticket (no chart changes) — helm-guarded suites unaffected
- smoke (optional, unchanged surfaces): `pytest charts/gpt-researcher/tests -v` / `pytest charts/llama-swap/tests -v` (CI runs these on the PR anyway)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Board provisioning command (Inbox-aware; script+skill+command, dry-run, REST fallback) | L | 1 | [] | new interface; standalone |
| C02 | Run tag retired everywhere + slug auto-accept + ls/pwd close | M | 1 | [] | naming surfaces; disjoint files from C03 |
| C03 | Boards behavior round: provider filter, archive exit, follow-up protocol, cleanup | M | 1 | [] | coord behavior text; owns boards skill edits |
| C04 | Provider loop tasks: API filter + Local duplicate + Always-Allow hand-off | M | 2 | [C03] | loop bodies cite C03's Provider filtering section (interface) |
| C05 | -pr flow description updates (assumed infra) | M | 2 | [C02] | regens over C02's kickoff/commands text; single-authority push-pr section |
| C07 | Deferred-cards ledger creation on AI-Dev (destination: Inbox, Backlog swimlane) | M | 2 | [C03] | creates cards under C03's parent-label protocol (policy before use); card timing rule schedules it first in the wave |
| C06 | -deploy variant definition + coord hook | L | 3 | [C05, C03] | -deploy-pr cites C05's -pr flow text; coord hook extends the file C03 edited (sequential state) |

## Wave order
1. C01, C02, C03 — independent file sets; run in id order.
2. C07 (first — the card's timing rule: ledger cards after post-research,
   before the test session), then C04, C05.
3. C06.

## Risks / assumptions
- Deployed dev-boards LAGS the repo: live-probed 2026-10-31, no
  create_label/create_list/create_swimlane/update_board/list_board_members,
  so OQ1's board-admin probe was impossible and C01 ships the raw-REST
  fallback; `create_card` `default_checked` may also be rejected — C07
  probes once and degrades to toggle_checklist_item. L4 tracks the pin bump.
- Two concurrent loop tasks: the lease-lock surface serializes claims.
  Unlabeled cards have a PLANNED taker (final-approval ruling): the Local
  task's scheduled walk takes them WITH the ask-at-claim; the API task's
  scheduled walk takes only `Provider: API`-labeled cards — an unlabeled
  card reaches the API flavor only through a MANUAL run the user initiates,
  and that run asks too (both flavors carry the ask instruction, C03/C04).
  A Local scheduled run that claims an unlabeled card blocks on that
  question until the human answers (question-notify pushes the ask) — the
  accepted steady-state trade-off; DECISIONS.md.
- Session archive during the run's final turn is a metadata flag — safe per
  RESEARCH F4 (OpenChamber archives the same way).
- Test-suite flips (C02) change pinned POSTURE text; agent-test owns the
  rewording, review checks intent, not just string matches.
- Local model catalog churns: the pinned `gpu-ai/qwen3.8-flash-next-strata`
  was CONFIRMED in the batched round (2026-10-31) — C04 lands it as-is.
- RESEARCH contradictions: per-swimlane lists (live data beats the
  wekan.fi sentence) → provisioning always passes swimlane ids and Bucket
  rules always match swimlaneName; the draft-PR CI premise RESEARCH F8
  carried ("draft PRs run no pull_request workflows — unit must ride
  on: push") was proven FALSE in post-research round 2 — the corrected
  tier-trigger contract is the DECISIONS post-research entry's (GitHub
  thread #25722), and the C05 surfaces read it (no mechanics restated
  here).
- The card description's truncated AD-88 tail carries NO hidden scope —
  resolved in the batched round (2026-10-31); the bullet list is the
  complete request.
- Board drift mid-planning: the user created the **Inbox** list in the
  Backlog swimlane after the prefetch board-context block was collected —
  every Inbox consumer re-resolves its id via `list_lists` at use time
  (board-context block is a snapshot, never a freeze).

## Open questions — RESOLVED in the batched round (2026-10-31), #4 refined at final approval
All seven questions answered; answers 4, 5 and 6 CORRECTED the planner's
best guesses, and answer 4 was ruled again at final approval (see its entry).
The decisions live in DECISIONS.md; this section is the audit record.

1. **Slug** — CONFIRMED: `cf-90-feat-board-coord-improvements`. (One-time
   confirmation — card-derived slugs auto-accept after C02 lands.)
2. **Provider: Local loop initial model** — CONFIRMED:
   `gpu-ai/qwen3.8-flash-next-strata`.
3. **Parent-label inheritance** — CONFIRMED: every parent label EXCEPT
   `Research`.
4. **Cards with NO Provider label** — CORRECTED twice (RESEARCH OQ7 guess
   VOID; the batched round's "either may take" fold superseded by the
   FINAL-APPROVAL ruling, verbatim): *"Unlabeled should be ran by the Local
   provider, but sometime I'll get the API version to run an unlabeled card,
   so both versions need the ask instruction, but only Local should plan on
   picking up cards without a Provider label."* Design: scheduled API task
   = explicit `Provider: API` cards only; scheduled Local task =
   `Provider: Local` + unlabeled (planned steady-state taker); BOTH flavors
   carry the ask instruction — the run that takes an unlabeled card asks
   the user which provider applies before consuming Model(s)/provider
   routing and requests the user apply a Provider: label (labels stay
   human-owned per D17/D19 — the ask ends with the human labeling; agents
   never mutate labels); the API flavor only ever sees unlabeled cards via
   a MANUAL run the user initiates.
5. **Follow-up/ledger destination** — CORRECTED: the new **Inbox** list in
   the **Backlog** swimlane (user-created on the live board; id re-resolved
   at use time). All follow-up/ledger cards land in Inbox — replacing both
   the old friction-Review posture and the Low-Priority guess. C01's engine
   ensures Inbox exists and NEVER mirrors it into Planning.
6. **Work-complete cleanup** — REFINED: landing is CONTENT-based ("is the
   code in main?"), not ancestor-clean — squash/merge-PR landings count as
   landed (the branch history may stay "awful"). Landed → remove worktree,
   delete branch, move session to the main tree. NOT landed → ask the user
   once whether to delete branch+worktree (default keep — the branch may be
   wanted for a PR push); obey, never force.
7. **AD-88 tail** — no hidden scope; the bullet list is the complete
   request.

## Appendix — deferred-cards ledger (C07; content authority)
Reconciled to 12 entries: every follow-up the card requests, with the five
already-carded items CITED instead of recreated (the coord's "9" count
folded env-var research into L10 and predates the live-board duplicate scan).
Titles/bodies are created verbatim-ish; `Parent card: #90` + parent-labels
line (minus Research) on each. Destination for every CREATE: the **Inbox**
list in the Backlog swimlane (batched-round ruling — id re-resolved via
`list_lists` at use time; never the prefetched block).

- **L1 (CREATE) — Always-Allow: remove the need for the interim posture.**
  "Permissions: Always Allow" is enabled on the pipeline tasks via the
  OpenChamber UI toggle (`permissionAutoAccept`, survives loop re-sync) as an
  INTERIM. Goal: get the pipeline to a point where unconditional approval is
  not needed, then remove the posture. Context: pipeline-worker +
  pipeline-worker-local tasks; RESEARCH F3/F8. Services: agent context ·
  Type: chore.
- **L2 (CREATE) — Dynamic provider/model routing or pipelines.** Today the
  Provider: API / Provider: Local split is two near-duplicate loop files —
  "not really scalable, good enough for today's need". Research + implement
  either dynamically setting provider/model per card or dedicated pipeline
  definitions; retire the duplication. Services: agent context · Type: chore.
- **L3 (CREATE) — Linting plugin for the relevant agents.** Linting should
  be handled automatically by a plugin that runs the linter for the relevant
  agents (initially the -pr family). Research & implement. Services: agent
  context · Type: chore.
- **L4 (CREATE) — Bump dev-boards wekan-mcp pin to a v102+ build.** The
  deployed dev-boards surface lacks cf-89's v102 tools (create_list,
  create_label, create_swimlane, update_board, list_board_members —
  live-probed absent 2026-10-31; pin `:v87` in services/dev values). Bump
  the pin deliberately, verify the tools land, then the board-provisioning
  command runs full-MCP and the reaper Timeout list can be created.
  Services: dev · Type: dep.
- **L5 (CITE) — wekan-mcp label-on-card capability.** Existing cards:
  "wekan-mcp: add a label tool to drop the rules-engine round-trip"
  (Not Started) + "Wekan Labels on cards" (Review). Needed for parent-label
  inheritance to become a set-labels call instead of a body note; bulk route
  `POST /api/boards/:boardId/cards/labels` verified present v9.88+v12.65
  (RESEARCH F5).
- **L6 (CITE) — create_list tool / Timeout list.** Existing card: "wekan-mcp:
  add create_list tool (Timeout list for pipeline-locks reaper)" (Test). The
  tool shipped in cf-89; availability rides L4's pin bump.
- **L7 (CREATE) — Test-environment loading mechanics for k8s charts (unit
  tier).** Work out + document how the impacted chart(s) get loaded into the
  test environment for the draft-PR "unit" tier; define the skip-testing
  annotation/label + its Chart.yaml setting (precedent shapes in RESEARCH
  F7). References L8. Services: dev · Type: feat.
- **L8 (CITE) — Playwright mechanics.** Existing card: "Playwright Unit
  tests for charts" (Backlog/CICD): the login/verify/logout walker over all
  accessible ingress/gateway objects without skip-testing, run mechanics,
  the `--isolated` fresh-login consequence (RESEARCH F7).
- **L9 (CITE) — Kopia mechanics.** Existing cards: "Kopia backups" + "Kopia
  restore as a part of testing services" (Backlog/CICD): locate the kopia
  deployment (absent from this repo — RESEARCH F9), restore the most recent
  production backup into the test namespace, credentials story.
- **L10 (CREATE) — PR testing flow: k8s charts.** Draft PR = unit tier
  (plain `on: pull_request` default types — they FIRE during draft; GitHub
  thread #25722 per the DECISIONS post-research entry), ready PR =
  integration tier (ready_for_review+synchronize, !draft); unit = chart
  loaded in test env + playwright login/logout walk; integration = + kopia
  restore + data-presence check after login; prefer live playwright-MCP
  actions when tests are absent and the app reachable, else write tests from
  research and update once running; single shared dev/test account consumed
  from env vars — INCLUDES the research: how env vars reach OpenCode agents
  in Coder workspaces (coder_env/k8s-Secret option per RESEARCH F6) and how
  the agent uses them. Consumes L7/L8/L9; flow contract: pipeline-push-pr's
  assumed-flow section (C05). Services: dev · Type: feat.
- **L11 (CREATE) — PR testing flow: services.** Same shape as L10, performed
  in the services location. Consumes L8/L9. Services: dev · Type: feat.
- **L12 (CREATE) — PR testing flow: containers.** Same shape for docker
  containers: each container's `testing/` folder carries a values.yaml with
  an app-template defining how to run the container; tests execute against
  it. Consumes L8. Services: dev · Type: feat.
