# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Edit `.rulesync/` sources, `rulesync generate` (twice; second run no-op),
  commit sources + generated mirrors together. Never hand-edit AGENTS.md /
  `.opencode/{agents,commands,skills}`.
- Loop files (.agents/loops/*.md) are FILE EDITS ONLY in this pipeline — no
  OpenChamber operations; scheduler hygiene stays human-owned (main
  080c9878a precedent).
- This repo's machinery tests are offline bash text-pin suites; pytest
  exists only for chart suites (untouched this ticket).

## Decisions
- 2026-10-31 plan: RESEARCH.md F9/F10 ordering adopted — split the card into
  an in-scope core (provisioning command, Provider tasks, archive exit,
  follow-up protocol + ledger, slug auto-accept, run-tag retirement, -pr
  descriptions, -deploy definition) and a deferred backlog (the ledger
  cards); every CI/playwright/kopia/env-var MECHANIC is a ledger card, per
  the card's own scoping. Rejected: implementing the mechanics inline —
  the card explicitly defers each to follow-up cards.
- 2026-10-31 plan: ledger reconciled to 12 entries (8 CREATE, 4 CITE) after
  a live-board scan found five already-carded items (label tool ×2,
  create_list, kopia ×2, playwright). The coord's sizing counted 9; the
  delta is the env-var research folded into L10 and the live-board duplicate
  scan the sizing predates. Rejected: recreating existing cards — cite-only
  posture; existing cards are never mutated.
- 2026-10-31 plan: provisioning engine is OFFLINE and credential-free
  (snapshot in → action list out); applying is the skill's job via dev-boards
  tools where present, raw-REST recipes (human WEKAN_TOKEN) where the
  deployed surface lacks the tool. Rejected: a script that calls the API
  directly — agents hold no board credentials, and dry-run-first validation
  requires the split. Live-probed 2026-10-31: deployed dev-boards has NO
  create_label/create_list/create_swimlane/update_board (the :v87 pin lags
  cf-89's v102 build) — the fallback is load-bearing; ledger L4 tracks the
  pin bump. The OQ1 board-admin probe was impossible for the same reason and
  is recorded resolved-by-evidence, not pending.
- 2026-10-31 plan: OpenChamber hand-offs (human-owned, one-time): (1)
  approve the new pipeline-worker-local task at first sync (loopApprovals
  fingerprint), (2) toggle permissionAutoAccept ("Always Allow") on BOTH
  pipeline tasks — it survives loop re-sync, the agent cannot set it
  (RESEARCH F3/F8), and ledger L1 tracks removing the NEED later.
- 2026-10-31 plan: the Local loop task ships `enabled: true`, schedule
  `30 * * * *` (staggered off the API task's :00), model
  `gpu-ai/qwen3.8-flash-next-strata` (OQ3 best guess — batched round
  confirms). The gate script stays UNCHANGED: it counts the three
  board-coord agent names regardless of provider, and both tasks run
  agent-board-coord. The "label map" is the board-context block's labels:
  section — new labels ride it with no code change (RESEARCH F3).
- 2026-10-31 plan: ls/pwd bullet closed verify-and-close — all six coord
  variants carry the ls/pwd allows (cf-88 ruling; sources verified at
  planning). No permission change; C02 confirms the generated copies.
- 2026-10-31 plan: C07 executes as a COORD board action (boards-skill
  friction-follow-up precedent — board writes are the coord's surface),
  scheduled after post-research and before the test session per the card's
  own timing rule; its "tests" are a review-run board read-back, not code.
- 2026-10-31 plan: run-tag retirement is GLOBAL (both families) per the
  card — superseding the "agent-coord keeps run tags" posture the suites
  currently pin; C02 flips those pins. The `-2` suffix of this run's
  surfaces is the D11 sequential-run suffix, not a run tag.
- 2026-10-31 plan: OQ best guesses adopted pending the batched round —
  parent labels: all except Research; unlabeled cards → the API task;
  ledger destination Low Priority; cleanup: worktree removed at run end,
  branch deleted only once merged (else explicit skip), -deploy closes its
  own worktree at hand-back.
- 2026-10-31 plan (batched round 1 — resolutions): slug CONFIRMED
  `cf-90-feat-board-coord-improvements`; Local loop model CONFIRMED
  `gpu-ai/qwen3.8-flash-next-strata`; parent-label inheritance CONFIRMED
  (all except Research); AD-88 tail resolved — no hidden scope, the bullet
  list is the complete request.
- 2026-10-31 plan (batched round 2 — CORRECTIONS superseding the guesses
  above): (a) UNLABELED cards — the "API task takes them" default is VOID.
  Ruling: unlabeled cards stay claimable by BOTH tasks (Local favored in
  guidance since the API flow already runs today, but either run may take
  one); the claiming run MUST ask the user which provider applies before
  consuming Model(s)/provider routing, and requests the user apply the
  Provider: label. TENSION noted and accepted: labels stay human-owned
  (D17/D19 — agents never create/mutate labels), so the ask ends with the
  human labeling; the user also runs cards manually sometimes, so a label
  applied mid-run is fine — the run re-reads labels rather than caching
  them. A SCHEDULED run holding an unlabeled claim blocks on the question
  until answered (question-notify pushes it) — accepted over guessing.
  (b) DESTINATION — all follow-up/ledger cards land in the new **Inbox**
  list (Backlog swimlane, user-created live 2026-10-31; id re-resolved at
  use time — it postdates the prefetch block). This replaces BOTH the old
  friction-Review posture (boards skill Friction follow-up section repointed
  in C03; the Backlog-swimlane location keeps those cards out of the pickup
  walk exactly as Review did) and the Low-Priority guess. C01's engine
  ensures Inbox exists and NEVER mirrors it into Planning. (c) CLEANUP —
  landing is CONTENT-based ("is the code in main?"): diff the branch's
  changed paths (vs its merge base) against main; empty ⇒ landed —
  squash/merge-PR landings count even when the branch history is "awful";
  ancestry checks (`git branch --merged`) are explicitly NOT the gate.
  Landed → remove worktree, delete branch, session home. Not landed → ask
  the user once (default keep — branch may be wanted for a PR push), obey,
  never force; session still moves home.
- 2026-10-31 human (final approval — SUPERSEDES batched-round item (a)
  above): unlabeled-card pickup RULED, verbatim: "Unlabeled should be ran by
  the Local provider, but sometime I'll get the API version to run an
  unlabeled card, so both versions need the ask instruction, but only Local
  should plan on picking up cards without a Provider label." Design: the
  scheduled API task takes ONLY explicit `Provider: API` cards; the
  scheduled Local task takes `Provider: Local` cards AND unlabeled cards
  (its planned steady-state pool); the ask-before-routing +
  human-apply-label instruction lives on EVERY flavor — an unlabeled card
  reaches the API flavor only via a MANUAL run the user initiates, and that
  run asks too. Rejected: batched-round "claimable by BOTH, whichever
  claims first" (arbitration left the unlabeled pool's owner to the lock
  race, not to intent) and the earlier "API takes unlabeled" default
  (void). Manual-runs habit stays compatible: a human pointing an API run
  at an unlabeled card triggers the ask, it never needs a pre-labeling
  step. Folded into plan risks + C03 (skill text, AC1, test pins for
  "API-scheduled-never-takes-unlabeled" / "Local-scheduled-takes-unlabeled-
  with-ask") + C04 (loop bodies, AC1/AC2, tests t2/t7).

- 2026-10-31 · **Coord rulings during wave-1 (agent-test escalation + C01 deviation).** (a) C07 ledger cards' Services checklist: the chunk Tasks line and the plan appendix disagreed for L4/L7 — RULING: follow the plan appendix (the declared card-content authority): L4 (deployed dev-boards pin bump) and L7 (kopia deploy location) are Services=`dev`; L1–L3/L5/L6 remain `agent context`. (b) C01's staged re-probed fixture (/tmp/opencode/cf-90-c01/) vs the committed fixture: engine plans byte-identical and the committed fixture already carries Inbox — RULING: keep the committed fixture; the staged file stays as probe evidence, not a repo file. The underlying chunk-note/tests-deny drift is logged in FRICTION as fixed.

- 2026-10-31 C02 dev (appended by coord per the sanctioned hand-off route): ls/pwd bullet CLOSED verify-and-close, zero code. Grep evidence (AC5): all six generated .opencode/agents/agent-{coord,coord-local,coord-pr,board-coord,board-coord-local,board-coord-pr}.md carry exactly one each of the rows `resource: ls`, `resource: ls \*`, `resource: pwd`, `resource: pwd \*` (24/24 counts = 1), and the six .rulesync/subagents/ sources match — the cf-88 grants are mirror-synced, no drift, no permission edit needed. The check is pinned as an ongoing arm by rulesync-surface c20(h). Cross-checked at append time by review r1 (independent grep) and green c20(h).

- 2026-10-31 C07 (coord-executed board action) · ledger ids: L1→ttv3k8b45fXXRynM8, L2→ZkduYpGkJPxci9gZe, L3→CqufKTJ9x98kP4Xue, L4→r3ghE7qGj75HTnghH, L7→NHgP5NscGsboaNk8u, L10→oBB5KtteQodi7FYtT, L11→MogiWe94eKC3Ht7ny, L12→XLfuqsHPnnppFAj2T (all created in Inbox PjEZ39rXBdpNcpncs, Backlog swimlane MoZHQz3C4dSW4Atya — re-resolved live per the NOTE, not the prefetch block); cited untouched: L5=#74 MS8e8uoF27R2dk73e + #87 ZE6K3iQBn8kBnSCdZ, L6=#68 Wg93SkHZ7bMLWJYBA, L8=#62 PLtfM4C9MvcP684PZ, L9=#60 HPh2fE8Xv9suJr7GN + #61 HBtAhaa2xdbfneqcS. Checklist answers per the plan appendix under ruling (a) (L1-L3 agent context+chore; L4 dev+dep; L7/L10/L11/L12 dev+feat; all Qwen Flash) — correction to ruling (a)'s parenthetical: L7 is TEST-ENV CHART LOADING (the appendix's entry; the earlier note mis-described it as kopia, which is L9-cite — the dev ruling itself unchanged). create_card accepted no default_checked on the deployed surface — toggle fallback used per C07; board createCard rule auto-added the five checklists (no add_checklist). Forward-reference deviation (runbook MINOR-1): the L7/L10-L12 bodies' '-pr flow contract' pointers cite the pipeline-push-pr assumed-flow section landing in C05 — self-marked "(C05)" in the bodies; verified present at C05's review.

- 2026-10-31 C04 · **Coord acceptance: API provider sentences live in the loop file's COMMENT block, not the prose sentence.** tests/opencode/pipeline-locks-tick.test.ts (a HOLD) pins the non-comment prose of pipeline-worker.md byte-identically to the plugin TICK_PROMPT — extending the prose sentence would break it, and editing the plugin is out of scope. The provider contract therefore rides the comment paragraph (lines 26–41), which is still the OpenChamber task prompt: the whole loop-file body, comments included, becomes the scheduled task prompt (RESEARCH F3; pipeline-worker.md is the API twin of the new pipeline-worker-local.md), so the scheduled run carries the ask instruction. C04's own suite greps the whole file (t2/t5/t7 strip only YAML frontmatter) — placement satisfies it as designed, nothing relaxed; review r1 verified mechanically (TICK HOLD 12/12, provider-loops 7/7, negatives zero-hit). No chunk depends on C04; no replan needed. C07 NIT-1 (stale run-tag line in pipeline-worker.md) DISPROVEN by dev + reviewer (git -S empty, zero hits pre-edit on main); the retirement-factually line was folded into the comment block anyway per the launch direction.

- 2026-10-31 C05 · Forward-reference VERIFIED at review r1 (live-board read-back): the assumed-flow section heading `## -pr testing flow (assumed)` is findable from L7's pointer sentence; L10 restates the contract inline; L11/L12 cite L10. Findability from C05's side complete — board-side pointer symmetry deliberately NOT forced (editing created-card bodies for cosmetics is out of posture). L3 linting pointer accepted as card-frame-faithful condense (reviewer live-read L3).

- 2026-10-31 post-research (round 2) · DRIFT FIXES FOLDED, no replan needed: (1) OPENCHAMBER APPROVAL COUNT CORRECTED — post-merge BOTH loop tasks need human approval, not just the new Local: the C04 body edit rotates pipeline-worker.md's loopApprovals fingerprint (8137741841… live-approved → 9ae4146e…; reconcileLoopTasks forces a fingerprint-mismatched task enabled:false as "outdated" until re-approved). Post-merge runbook: approve BOTH tasks (API re-approval + Local first approval), then toggle Always-Allow (permissionAutoAccept) on both, then run the one live provisioning. (2) F8 PREMISE FALSE, CONTRACT CORRECTED — GitHub DOES run pull_request-triggered workflows on draft PRs (thread #25722, 2025 confirmations; the if: draft==false idiom exists because they run). Unit tier therefore rides plain on: pull_request default types (fire during draft); integration tier keeps types: [ready_for_review, synchronize] + !draft guard; the "draft PRs run nothing on pull_request — unit must ride on: push" claim is void (loop bodies, pipeline-push-pr source+mirror, ledger-card consumers L10-L12 read the corrected contract).

- 2026-10-31 final-review r1 folds (coord actions): L10 ledger-card BODY corrected in place via update_card (void F8 clause → corrected tier contract + the pipeline-push-pr assumed-flow pointer; L11/L12 self-heal transitively via their "same shape as L10" wording) — the post-research DECISIONS claim "L10–L12 read the corrected contract" is now TRUE at the bodies. C07 timing substance-over-literal: the ledger landed after the agent-test session and wave-1 code though chunk/plan text said "before the test session" — the one-shot Test stage precedes every chunk by repo law and the plan structure was human-approved as such; substance held (Inbox never auto-picked-up, parent completed same day). Pipeline-worker.md "(also enabled, runs no gate)" nit RULED ignored per final review (stale prose about the legacy daily task, human-owned hygiene; rewording rotates the API approval fingerprint for zero gain).

## Deferred
- The one live provisioning run (lists+labels+rules on AI-Dev) — post-merge,
  human-confirmed, per the card's Deploy-ish hand-off posture.
- wekan-mcp container changes (L4 pin bump, L5 label tool) — ledger cards.
- Every -pr mechanic (L7–L12) — ledger cards; this ticket ships the
  descriptions assuming them (C05).
