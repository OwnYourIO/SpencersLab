# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives rejected, why.

## Conventions
- All new cross-card references key on card `_id`; `card_number` is display-only
  (RESEARCH C2: the 74→78 renumber proves numbers are counters, not identity).
- Edge storage convention: `is-blocked-by` on the DEPENDENT card; consumers
  honor the inverse (`blocks` on the dependency side) via WeKan's inverse map.
- Degrade law: until the C10 deploy chain lands, every consumer of the new
  wekan-mcp tools probes `tools/list` and degrades to today's behavior with a
  RESULT note — never a hard failure.
- Doc/parity pins are never red between commits: code + its re-stamped docs +
  suite re-pins land in the SAME chunk commit.
- Statics-only test posture (cf-intake D8): no pytest harness in
  containers/wekan-mcp; validation = windowed-grep suites + py_compile.

## Decisions
- 2026-11-01 plan: Red Strings (card dependencies) is the machine-readable edge
  store. Rejected: parentId-only (not typed/queryable board-wide), linkedId
  (a reference/mirror, not an edge). RESEARCH implication 1.
- 2026-11-01 plan: OQ2 closed per launch ruling — is-blocked-by on the
  dependent; gate treats both directions as equivalent; only
  blocks/is-blocked-by edges gate pickup.
- 2026-11-01 plan: OQ3 closed per launch ruling — preload called by the coord
  at claim time; the 8 s prompt hook stays structural-only. Rejected: hook
  extension (budget risk + schema-footer churn). preload cards carry
  id/card_number/label_ids/slug/archived/sort/parent_id (parent_id folded per
  RESEARCH best guess; dates/assignees rejected until asked).
- 2026-11-01 plan: OQ7 closed per launch ruling — AD-66 ships in-ticket (C04).
- 2026-11-01 plan: OQ9 closed — My Dependencies (private user layer) not
  exposed; one docs line records its existence.
- 2026-11-01 plan: OQ10 closed per launch ruling — agent-explore writes
  EXPLORE.md next to the plan file; pipeline-conventions read order updated
  (C02). Rejected RESULT-only (the card's "ground the task" wants a durable
  artifact research/planning read).
- 2026-11-01 plan: OQ11 closed per launch ruling — set_card_labels ships in
  this ticket (C01 T3), retiring the boards-skill "labels to apply" comment
  degrade (with a tools/list-gated degrade until the bump).
- 2026-11-01 plan: OQ12 closed per launch ruling — sibling ids pinned
  (74=MS8e8uoF27R2dk73e, 66=t4N5D4eZ9Nc2MoAZd, 71=v8priYKMuuWLCoFDq,
  77b=Ru3CzNiyaEQH7YFcr, 70b=SouMZ2fbd8vDbz2m3, 81=Q7Sg7H4dicTALAp8q,
  78a=jaEe2jfobfboyaM92); #77a/#70a/#78b explicitly untouched.
- 2026-11-01 plan: create_card parent_id = two-step create→PUT parentId.
  Rejected: single bulk-endpoint POST (extra route surface for one optional
  param). RESEARCH 2.1.
- 2026-11-01 plan: registry lands at 38 tools = 17 reads + 21 writes; the new
  surface is ONE additive block (cf-89 precedent).
- 2026-11-01 plan: agent-explore ships with an inline role contract — NO new
  pipeline-role-explore skill yet. Rejected: full contract skill (smallest
  sensible delta; revisit if the role grows). Permission block mirrors
  agent-research minus websearch (scouting, not research).
- 2026-11-01 plan: chunking = 10 chunks; C01 fuses code+docs because parity
  pins forbid a red gap; boards-skill chunks (C05→C07) serialize on the shared
  file; C08 sits after C07 so the engine/artifact never pin pre-answer item
  lists. AD-71's spirit applied (4 S asks share C03; verifies folded into
  their sibling chunk).
- 2026-11-01 plan: v2 board-rules artifact lives in THIS ticket folder
  (plan-adjacent), the v12-upgrade folder's v1 artifact stays historical; the
  boards cutover section points at the new path.
- 2026-11-01 plan: TZ best guess America/Denver grounded from renovate.json's
  "timezone" field — C09 ships the value or an explicit HOLD marker, never a
  silent different guess.
- 2026-11-01 human (batched round): ALL EIGHT rulings landed, folding as
  follows —
  1. OQ1: **parentId only**. Kind-1 follow-up lineage = `create_card(parent_id)`
     (two-step create→PUT); NO Red Strings edge is drawn for follow-ups, and no
     consumer (grouped-sibling flow, pickup logic) may expect kind-1 edges.
     Dependency kinds 2+3 remain Red Strings. Rejected: the plan's both-edge
     best guess.
  2. OQ4: **everything incl. machine fields**. Every DISPLAYED ISO stamp the
     pipeline machinery writes becomes workspace-local ISO-8601 WITH offset —
     including the previously-UTC-only plugin fields: pipeline-locks
     `claimedAt`/`heartbeatAt` (lock records), the audit-JSONL `at`,
     `timeouts.jsonl` row `at`, and the board-context `collectedAt` — plus the
     human-facing set (no-op title, comment stamps, STATE.json `updated_at`).
     VALUES THAT ARE INSTANTS stay as they are by definition: epoch-ms fields
     (`metadata.pipelineNoop.at`, gate.sh `date +%s%3N` + jq `.time.updated`
     arithmetic, file mtimes, `Date.now()` pass-throughs) CANNOT "become
     local" — only their display could, and no such display surface exists in
     the gate/boards text. Reaper-comparison consequence (checked against the
     implementation): the staleness consumers parse the stamps —
     `pipeline_status` age via `Date.parse(heartbeatAt ?? claimedAt)` and the
     reaper's `max(parsed heartbeatAt, file mtimeMs)` against
     `DEFAULT_STALE_MS = 7200000` (the 2 h window) — and ECMAScript
     `Date.parse`/`new Date(iso)` honor an explicit offset, so an
     offset-bearing stamp parses to the SAME instant as its UTC `Z` twin: the
     change is writer-side only, the 2 h window and the max() formula stay
     exactly correct with NO comparison-side code change, and mixed-era lock
     files (old `Z` + new offset) coexist safely. `$TZ` unresolvable ⇒ UTC `Z`
     fallback (today's behavior, fail-safe). `scripts/agent-board-coord-gate.sh`
     therefore needs ZERO change (epoch-only by construction).
  3. OQ5: **America/Denver** — C09 ships the coder_agent `TZ` env for real in
     both templates; no HOLD marker. Template apply = workspace reprovision,
     owner-side, stays human-gated.
  4. OQ6 — USER VERBATIM: "Oh, At the end of Lifecycle leave the Single
     Session option". The new Lifecycle checklist is ELEVEN items: the ten
     named stages PLUS `Single Session` as the final item. Semantics preserved
     (replaces the Test Writing/Chunk Development/Chunk Review run-shape: ONE
     dev session implements the whole approved plan running the Commands
     itself — no chunk loop, no separate test session — then ONE final
     review; other checked stages still run). The Stage map keeps a Single
     Session row. Blank-Lifecycle default does NOT include it (opt-in).
     Consequence: NO Single-Session transition rule is needed (the v1 8-item
     cutover never landed on the live board — cards carry the legacy Research
     checklist — so nothing migrates away from it). Derived consequence
     (recorded, unobjected): the HITL checklist mirrors Lifecycle exactly, so
     it is the same 11 items. The legacy-HITL mapping best guess
     (Plan→Planning, PR→Deployment, Research→Pre Research) stands — the round
     did not touch it.
  5. OQ8: **all three tiers** — C10 runbook bumps dev-boards
     (`services/dev/prod/values.yaml`) + gpu wekan-admin AND wekan-readonly
     (`services/gpu/prod/values.yaml`) in ONE owner commit; ledger L4 folded.
     Planner's call on prep location: the values bumps stay in the C10 runbook
     (the `v<run>` tag exists only post-merge/CI — nothing committable exists
     earlier); the runbook carries exact file paths + line shapes.
  6. OQ13: **only Model(s)→Qwen Flash checked** — Lifecycle (11 items) and
     HITL (11 items) arrive unchecked so the blank defaults govern;
     Type/Services unchecked. C08 spec + board-rules artifact reflect exactly
     this.
  7. OQ14: **Exploration IS in the blank-Lifecycle default** — every default
     run starts agent-explore before research; written into the Stage map +
     defaults text (C07).
  8. OQ15: **Chunk Review unchecked = skipped** — a card checking Chunk
     Development without Chunk Review runs the dev-only chunk loop: coord
     commits chunks approved-by-validations-only (dev's RESULT `commands_run`
     shows the plan's Commands + chunk tests all passing; the coord judges
     from that evidence per its step-7 posture — never on the dev's word).
     Validation-green determinism stays mandatory (dev still runs every
     command). Checked-stages-only doctrine governs: pipeline-role-coord
     step 7 + step 5b gain the carve-out (C06), the boards Stage map rows
     carry the semantics (C07). The AGENTS.md/rules text stays untouched —
     its "validations gate chunk done" statement remains true under both
     shapes. Rejected: the plan's still-runs best guess.

## Coord rulings (post-research round)
- 2026-11-02 human (via coord question round): **OQ-P1 = FOLD THE CODE** — add the
  `get_rule`/`_slim_rule` passthrough (rule extras: `extraActions` + the rule's
  `enabled` field) to the UNDEPLOYED C01 surface in `containers/wekan-mcp`,
  re-stamp its docs/call-shapes row, and let the zero-action schema-2 read-back
  work as written. Rejected: re-pointing to UI-export-only capture (leaves the
  agent path broken), and deferring to a follow-up card (the defect makes
  C10's step 8 silently degrade — worse than the fix). Consequence: the plan
  gains a delta chunk (C11) and C10's runbook/provision-skill capture
  instructions become true without text change.
- 2026-11-02 coord: OQ-P2/P3/P4/P5 dispositions — P2 (a present-but-failed
  `tools/list` answer degrades like absence, one retry) and P3 (title-map
  fallback + unresolvable-edge-end wording) and P4 (runbook step-2 ghcr recipe:
  anonymous `tags/list` is the truth, `imagetools inspect` resolves the legacy
  `:latest` and would mislead; note the v90–v102 distractor tags) fold as
  TEXT-ONLY into the C11 delta round. P5 (changing the WeKan service user's
  password invalidates the minted bearer → the deploy needs a re-mint plan) is
  out of this ticket's scope → Inbox follow-up card at close-out.
- 2026-11-02 human (second batched round, two answers): (a) the C11 delta is
  APPROVED as planned; (b) the verified anonymous-token + `tags/list` registry
  recipe is NOT deferred — C11 WIDENS to re-stamp the two adjacent surfaces
  that still carry the misleading `imagetools inspect` tag hint:
  `skills/wekan-api/references/wekan-mcp-ops.md` (Deploy/verify loop) and the
  `container-creation` skill's tag-inspection recipe. Rejected: the coord-
  recommended close-out follow-up card (the same false-recipe class as OQ-P1:
  fixing it once, here, is cheaper than a card + a later run). Consequence:
  C11 gains a docs-surface task and the suites those two files' pins bind may
  need leg updates — the planner enumerates them in the chunk file.
- 2026-11-02 coord: post-research verification of record — the seven
  dependency-surface files are byte-identical v12.65↔main and the lab actually
  runs v12.77 (renovate d8b12fd0f), so no assumption in C01/C05/C08 moved;
  the upstream `checkItem` rule-action typo is NOT fixed on main, so the v2
  createCard extras stay DORMANT (the landed "dormant until upstream fix"
  wording is honest as written); rule extras remain import-only (no REST path).

## Close-out (coord, 2026-11-02)
- Final review r2 APPROVED → `plan_status: complete`; card #96 moved to Review
  with the full summary comment; the grouped siblings (AD-74/66/71/77b/70b/81/78a)
  each got a per-card outcome comment and moved to Review; `pipeline_release
  (outcome:"done")` released the `Context` lock set.
- Surfaces: branch + worktree KEPT per the owner's answer (35 local commits,
  never pushed — landing on main is theirs alone; the HITL `PR` stop held all
  run). Work did NOT land in main, so nothing was deleted.
- Inbox cards minted at close-out (Backlog/Inbox, five standard checklists
  auto-added by the board rule — never `add_checklist`; Services `agent
  context` + Type `chore` + Model(s) `Qwen Flash` checked, Lifecycle-side left
  to the defaults; parent labels listed in each body because the deployed
  surface has no label tool until cf-96 C01's `set_card_labels` deploys):
  1. `T2AXwrGLRb5yowQM9` — WeKan service-user password rotation signs out the
     static gpu-tier bearers → re-mint/rotation runbook (OQ-P5, mandated).
  2. `XRG8uTY2JkD8xEMkn` — one scope-admits file the four arms read (the
     per-ticket admit ritual, recorded 6× this run; mandated by RESEARCH F6).
  3. `S78iY2FCGzeuogHM9` — wave-parallel dev / commit-ownership redesign
     (AD-71 half 2) — the only one of the 11 offered items the owner selected.
- Not minted (owner declined for now, ledger stands): Provider-label naming
  drift (`Provider: API` in text vs `Provider: OpenRouter` on the board — the
  most operationally significant of the remainder; raise it again if a
  scheduled walk ever comes up empty), the five-vs-six roster-drift re-pin
  family, shared registry-count source, pipeline-overview roster drift,
  Cancelled-blocker semantics + stale step pointer, gate-skip-all vs the no-op
  marker, offset-INPUT reap leg, test-hygiene bundle, dev-mcp-fleet pin drift.

## Deferred
- Wave-parallel dev sessions (AD-71 half 2): coord is the sole committer — one
  chunk = one commit it makes; concurrent devs collide at commit time. C06
  lands the revisit text + the explicit one-at-a-time line; true parallelism
  needs a commit-ownership redesign → follow-up card material (owner's call).
- Hook-based preload (OQ3 rejected alternative): revisit only if claim-time
  preload proves too late for a consumer.
- Kind-1 Red Strings edges (OQ1 rejected alternatives): the 2026-11-01
  batched round ruled parentId-only — revisit only if follow-up lineage proves
  it needs board-visible edges.
- Shared registry-count source for the three suites carrying the 17+21/38
  arithmetic (test session tempting-refactor, 2026-11-01): would end the
  same-commit count chases on every wekan-mcp tool addition; follow-up card
  material (owner's call).
- C06 review ledger notes (2026-11-01, non-blocking, follow-up candidates):
  (1) pipeline-role-research parity line for shared-RESEARCH.md append/merge
  when multiple research sessions write one file; (2) the `Research: Parallel`
  label's same-file write pressure stays dormant until parallel fires — if
  enabled, needs append discipline; (3) cf96-coord t5 negative-check (2) is
  loose — coverage actually held by t4's affirmative pins; a future harness
  touch may tighten.

## Coord rulings (test session's open questions)
- 2026-11-01 coord: test-Q1 CLOSED — "8 new signatures" counts the seven new
  tool NAMES (5 dependency + preload_board + set_card_labels) PLUS the new
  `parent_id` signature on the existing create_card = 8 signature changes over
  +7 registered tools (31→38). The test session's arithmetic is correct; no
  eighth tool name exists or is expected; runbook step 5 keeps its
  stop-and-report guard. The suites' 7-names/38-total pin stands.
- 2026-11-01 coord: test-Q2 RULED — the gate t17 / coord-inwork i4 five-vs-six
  drift arms are PRE-EXISTING reds binding files C02 does not touch
  (gate script, inwork plugin text) — they stay OUT of every cf-96 chunk's
  per-chunk gate under the cf-90/cf-75 baseline-identity rule (a baseline red
  may only stay message-identical, never grow into a chunk's own suite). C02's
  own in-commit re-pin duty is limited to what C02 verily changes:
  agent-perms/surface.sh roster-enumeration arms (six→seven coords' rosters)
  per the chunk file. Their re-pin belongs to their own drift ticket, not here.
