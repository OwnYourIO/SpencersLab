# PLAN: Add Dependency tracking to agent-board-coord card picking (cf-96)
feature: 2026/2026-10-cf-96-feat-dep-tracking-card-pickup

## Goal
Give the AI-Dev pipeline machine-readable card relationships — WeKan Red Strings
dependency edges exposed through five new wekan-mcp tools plus a one-call
`preload_board` — and make card pickup dependency-aware (a card whose depended-on
card is not in Test or Finished is skipped), with the sibling-card asks shipped
under this card. Ride the same ticket: the Lifecycle checklist redesign — 11
items (the ten stages + Single Session kept last) — with its (modify-only,
human-executed) board cutover process, the read-only
`agent-explore` scouting stage, per-ask research sessions, grouped-sibling flow,
and coder-workspace timezone handling for human-facing timestamps. Post-research
delta (C11, human ruling 2026-11-02): the `get_rule`/`_slim_rule` extras +
`enabled` passthrough that makes the schema-2 snapshot capture the provision
skill and C10 runbook advertise actually executable, its docs parity re-stamp,
and three text-only folds (present-but-failed call degrade, dependency-gate
edge cases, runbook registry recipe) and — per the second batched round — a
registry-recipe widening re-stamping the two adjacent surfaces (`wekan-mcp-ops`
Deploy/verify loop, `container-creation` pin-by-default recipe) that still
teach the misleading untagged-`imagetools` tag-list flow.

## Out of scope
- Running ANY provisioning/cutover step against the live board (owner executes
  post-backup after merge; C08/C10 gate this explicitly). My Dependencies (the
  private per-user layer — docs mention only, OQ9). Linked cards / mirror cards
  (no role in the three relation kinds, RESEARCH 1.1).
- Touching cards #77a/#70a/#78b (wrong-number candidates, RESEARCH Q5) or
  re-opening anything in Finished.
- The board-context prompt HOOK growing card data (preload stays
  coord-at-claim; the 8 s hook budget is untouched, OQ3 decided).
- Wave-parallel dev sessions (AD-71 half 2 — revisit-text only, Deferred).
- OQ-P5 credential hygiene (v12.75+: a service-user password change invalidates
  its static bearer → the gpu tiers need a re-mint plan) — OUT by coord ruling
  2026-11-02, Inbox follow-up card at close-out.
- The upstream `checkItem` rule-action typo (RESEARCH F5, [P8]): v2 createCard
  extras stay DORMANT until WeKan fixes it — external, nothing in-ticket acts.
- Tagged digest reads via `imagetools inspect` (e.g.
  `containers/strata/README.md`'s bump procedure) — the CORRECT class of
  use; the second-round widening re-stamps only the UNTAGGED tag-list claim
  in `wekan-mcp-ops.md` + `container-creation` (both now IN C11's scope via
  T5), nothing else.
- Unit tests for the Python server: repo posture is statics-only suites
  (cf-intake D8) — no pytest harness is introduced.

## Verified facts (evidence in RESEARCH.md)
- WeKan v12.65 (lab pin, S8) carries Red Strings CRUD (5 routes, 7 types,
  stored on the source card, same-board only) + export endpoint
  `?attachments=false&fields=` trim (S4/S11). Service user qualifies for
  dependency writes (moveCard role, S12).
- Deployed dev-boards image is `:v87` (S14) — lacks even the v102 tools; every
  new tool needs merge → `docker-build.yaml` `v<run>` → pin bump → restart.
- Registry today: 14 reads + 17 writes = 31 tools (tests/wekan-mcp/tools.sh).
  This plan lands +3 reads (list_board_dependencies, list_card_dependencies,
  preload_board) +4 writes (add/edit/remove_card_dependency, set_card_labels)
  = 38 tools (17+21).
- card_number is a counter, NOT identity (74→78 renumber proven, C2): every new
  cross-card reference keys on `_id`; card_number is display-only.
- Baseline suites green at plan time (tools.sh, skill-surface.sh,
  wekan-board-provision/surface.sh; 2026-11-01 ≈02:52Z).
- `renovate.json` carries `"timezone": "America/Denver"` — the grounding for the
  OQ5 best guess.
- C11 delta-round verification (re-read of the LANDED code at this branch HEAD,
  2026-11-02, agreeing with RESEARCH post-planning F1–F5): `_slim_rule` returns
  exactly `{id, title, trigger, action}` — `extraActions`/`extraTriggers`/
  `enabled` are structurally dropped; `get_rule` + `list_rules` are plain
  `@mcp.tool` (READ-ONLY tier exposes both; a `_slim_rule` change serves both);
  the provision engine's schema-2 contract is a collector-built
  `checklist_extras` map (name → `{items, checked}`) and its skill step 1 +
  runbook steps 7–8 name `get_rule` as the capture route — the defect (and the
  fix's target) confirmed in-tree; every suite C11 moves or must survive
  (dependencies, tools, skill-surface, boards-deps, checklist-cutover,
  cf96-deploy) is green at HEAD as the delta baseline; boards-deps needle
  windows re-simulated with draft fold text — all survivors hold
  (/tmp/opencode/cf96-c11, 2026-11-02).
- Second-round audit (2026-11-02, for the T5 widening): a full `tests/` grep
  shows NO suite content-grips `skills/wekan-api/references/wekan-mcp-ops.md`
  or `skills/container-creation/SKILL.md` — the only bindings are name
  pointers on files C11 already keeps pointing at (skill-surface t7 greps
  `skills/wekan-mcp/SKILL.md` for the ops pointer and bans rules-engine
  camelCase inside `skills/wekan-mcp/` only; cf96-deploy t3 greps the
  RUNBOOK for the ops path; board-context.test.ts greps plugin SOURCES).
  The ops Deploy/verify loop carries the digest-compare half only (untagged
  enumeration absent — that is what T5 adds, keeping the digest bullet
  byte-intact); the container-creation false hint is the one sentence
  "Grab the run number … or `docker buildx imagetools inspect
  ghcr.io/ownyourio/<name>`" in "Two ways to reference the image — pin by
  default"; `containers/strata/README.md`'s imagetools use is a TAGGED
  digest read — correct class, stays.

## Design decisions taken (full log in DECISIONS.md)
Pre-round (launch rulings + best guesses):
- OQ2 (launch-ruled): `is-blocked-by` stored on the DEPENDENT card; the pickup
  gate also honors the inverse shape (`blocks` stored on the dependency) via
  WeKan's inverse map. Only blocks/is-blocked-by edges gate pickup.
- OQ3 (launch-ruled): preload is called by the COORD at claim; the prompt hook
  stays structural-only. preload cards carry `{id, card_number, label_ids, slug,
  archived, sort, parent_id}` (parent_id folded per RESEARCH OQ3 best guess;
  dates/assignees excluded).
- OQ7/OQ11/OQ12 (launch-ruled): AD-66 ships in-ticket; `set_card_labels` ships
  in-ticket (AD-74); sibling ids pinned as listed below, #77a/#70a/#78b untouched.
- OQ9: My Dependencies not exposed — one docs line saying it exists.
- OQ10 (launch-ruled): agent-explore writes `EXPLORE.md` next to the plan file;
  added to the pipeline-conventions read order.
- Degrade law until the pin bump lands: consumers probe `tools/list`; new tools
  absent ⇒ pickup gate skipped with a RESULT note, grouped flow runs from the
  plan-enumerated ids, follow-up labels keep the comment-line degrade. No
  pipeline run hard-fails on the missing build.
- create_card `parent_id` = two-step create→PUT (RESEARCH 2.1 option i).

Batched-round rulings (2026-11-01, user — all 8 questions resolved):
- OQ1: kind-1 follow-ups = **parentId only** — no Red Strings edge drawn for
  follow-ups; grouped-sibling/pickup logic must NOT expect kind-1 edges; kinds
  2+3 remain Red Strings.
- OQ4: timestamp conversion extends to **everything incl. machine fields** —
  encoded as: every displayed ISO stamp the machinery writes becomes
  workspace-local with offset (incl. lock-file `claimedAt`/`heartbeatAt`,
  audit-JSONL/timeouts.jsonl `at`, board-context stamp); instant values stay
  epoch-ms by definition (no-op marker `at`, gate.sh epochs, mtimes). The
  reaper/pipeline_status staleness consumers parse offset-aware
  (`Date.parse`), so the 2 h window stays correct with writer-side-only
  changes — see C09 AC2.
- OQ5: TZ = **America/Denver**, shipped for real (no HOLD marker); workspace
  reprovision stays owner-gated.
- OQ6: Lifecycle is **11 items** — the ten stages PLUS `Single Session` kept as
  the final item (user verbatim: "Oh, At the end of Lifecycle leave the Single
  Session option"); semantics preserved (replaces Test Writing/Chunk
  Development/Chunk Review run-shape); opt-in — NOT in the blank default; no
  Single-Session transition rule needed; HITL mirrors the same 11 items.
- OQ8: pin bump = **all three tiers** (dev-boards + gpu wekan-admin +
  wekan-readonly), one owner commit; the values bumps stay prepared in the C10
  runbook (the `v<run>` tag exists only post-merge/CI).
- OQ13: v2 createCard rule checks **only Model(s)→Qwen Flash**; Lifecycle/HITL
  arrive unchecked (blank defaults govern); Type/Services unchecked.
- OQ14: **Exploration IS in the blank-Lifecycle default** — every default run
  starts with agent-explore.
- OQ15: **Chunk Review unchecked = skipped** — dev-only chunk loop; coord
  commits validations-green chunks on the dev's RESULT command evidence
  (determinism mandatory); checked-stages-only carve-out lands in
  pipeline-role-coord (C06) + boards Stage map (C07).

Post-research round (2026-11-02, human ruling + coord dispositions — full log in
DECISIONS "Coord rulings (post-research round)"; all land as chunk C11):
- OQ-P1 (the sole REPLAN-CANDIDATE, F5): **FOLD THE CODE** — C11 T1 extends
  `_slim_rule` with the `extra_actions`/`extra_triggers`/`enabled` passthrough on
  C01's UNDEPLOYED surface, so the schema-2 capture the provision skill + C10
  runbook already describe becomes executable WITHOUT touching either capture
  text. Rejected: UI-export-only re-point (leaves the advertised agent path
  broken) and deferral (C10 step 8 silently degrades). Consequence: the fix
  lands pre-merge so the deploy chain's single `v<run>` build carries it.
- OQ-P2 (fold-1) + OQ-P3 (folds-2/3): TEXT-ONLY folds into the boards skill —
  a PRESENT-but-FAILED call degrades exactly like absence (one retry, never a
  stall) + a never-retires row in the runbook retire table; title-map fallback
  and unresolvable-edge-end wording (skip-safe: non-gating + REPORT, never
  assume).
- OQ-P4: runbook step-2 registry recipe corrected to the verified anonymous
  ghcr `tags/list` flow (`imagetools inspect` resolves the legacy `:latest` and
  cannot enumerate; v90–v102-era builds named as distractors), digest-verify leg
  kept — phrased so every `tests/cf96-deploy/surface.sh` pin survives UNMODIFIED.
- OQ-P5: out of the ticket → Inbox follow-up card at close-out (coord).
- Ordering ruling: C11's test duties land GREEN-ON-ARRIVAL after dev's
  code+docs+boards-text commit (no designed-red ceremony — the change is purely
  additive, so no existing pin is forced to move).

Second batched round (2026-11-02, human, two answers — DECISIONS):
- (a) **C11 APPROVED as planned** (T1–T4 stand verbatim).
- (b) **OQ-C11-1 REJECTED the deferral recommendation — C11 WIDENS**: the two
  adjacent registry-recipe surfaces — `skills/wekan-api/references/
  wekan-mcp-ops.md` (Deploy/verify loop) and the `container-creation` skill's
  tag-inspection recipe — are re-stamped NOW with the verified anonymous-token
  + `tags/list` flow (untagged `imagetools inspect` resolves the legacy
  `:latest` and cannot enumerate; the v90–v102 distractor caution goes where a
  reader would count tags). The digest-compare leg of the deploy/verify loop
  STAYS (correct + live-proven). Rationale: same false-recipe class as OQ-P1 —
  one fix here beats a card + a later run. Lands as C11 T5.

## Commands
Run from the worktree root; `export PATH=$HOME/.local/bin:$PATH` first (helm).
- new suites (agent-test writes before dev; names are agent-test's, per-chunk
  files list them): one suite per chunk C01–C10 under `tests/` (statics-only,
  section-windowed greps — the cf-89/cf-90 posture).
- C11 (post-research delta) adds NO new suite file — its legs join the existing
  cf96 family, authored green-on-arrival AFTER dev's commit (test-route,
  tests/** dev-denied). Delta battery:
  `python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py && bash tests/wekan-mcp/dependencies.sh && bash tests/boards-deps/surface.sh && bash tests/wekan-board-provision/checklist-cutover.sh && bash tests/cf96-deploy/surface.sh` (new legs green; HOLD arms — cf96-deploy t1–t7 UNMODIFIED with the new t8 dead-sentence guard green-on-arrival, tools.sh 17+21/38, skill-surface t4/t7 rows/stamps/pointer, boards-deps t1–t5, rest-overview-v102, cf90-ledger — all green unchanged), plus `rulesync generate` ×2 (2nd no-op) + `rulesync generate --check` (boards-skill text fold only — the two T5 recipe docs under `skills/` are hand-managed, no regeneration), `node --test 'tests/opencode/*.test.ts'`, `npx aislop ci --changes`. `docker build => no-daemon, CI-deferred` stays the designed passing shape — the passthrough lands pre-merge so the deploy chain's `v<run>` image carries it in the same build.
- regression: `bash tests/wekan-mcp/tools.sh && bash tests/wekan-mcp/skill-surface.sh && bash tests/wekan-mcp/rest-overview-v102.sh && bash tests/wekan-mcp/board-provisioning.sh && bash tests/wekan-mcp/create-list.sh && bash tests/wekan-mcp/board-context.sh && bash tests/agent-perms/surface.sh && bash tests/wekan-board-provision/surface.sh && bash tests/cf90-ledger/surface.sh && bash tests/containers/wekan-mcp-login.sh && node --test 'tests/opencode/*.test.ts'` (re-pins land in the same commits as the changes that move them — doc/parity pins must never be red between commits; the node suite is Node v26 type-stripped, no npm deps — baseline green at plan time).
- lint: `python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py scripts/provision-board.py`
- rulesync: `rulesync generate` twice (2nd run a no-op) then `rulesync generate --check` (after any `.rulesync/**` change; sources + generated mirrors commit together).
- helm (C09): `helm lint charts/coder && helm template charts/coder --debug`
- renovate (C04): offline via `global-renovate` MCP — `validate_config`, `lint_config`, `preview_custom_manager` (a `renovate.json` dry-run is NOT runnable in-session; the MCP offline tools + the new `tests/renovate/` suite are the gate).
- quality: `npx aislop ci --changes` (every touched file clears the floor) + the `comment-slop` pass on every comment/docstring edited.
- surface: `git diff --name-only $(git merge-base main HEAD)..HEAD` ⊆ the chunks' declared file lists (plan-folder artifacts exempt).
- docker build: `docker build => no-daemon, CI-deferred` — `docker-build.yaml` on the pushed branch is authoritative (AGENTS.md rule; the line itself is the designed passing shape). No new pip deps; Dockerfile/base untouched.
- live probes (USER-owned, post-merge + post-bump, C10 runbook): `tools/list` on `dev-boards` shows 38 tools incl. the 8 new signatures; `GET /api/boards/TNQJ2BrXenZovngTS/dependencies` live round-trip; readonly tier lists the 3 new reads, no new writes (recipe: `skills/wekan-api/references/wekan-mcp-ops.md`).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | wekan-mcp: 5 dependency tools + preload_board + set_card_labels + `_slim_card`/create_card passthroughs + README/skill/call-shapes re-stamp | L | 1 | [] | — |
| C02 | agent-explore subagent: source + 6 coord-twin roster rows (same commit) + permissions matrix row + AGENTS roster + EXPLORE.md read order | L | 1 | [] | independent of C01–C04 |
| C03 | sibling asks I: AD-77b BOARD_COLORS stamp, AD-70b `cord→coord`, AD-81 -pr two-tier verify, AD-78a silent-route verify | S×4 | 1 | [] | independent |
| C04 | sibling asks II (AD-66): renovate manages system-upgrade-controller | S | 1 | [] | independent |
| C05 | boards skill: pickup dependency gate + preload consumer at claim + grouped-sibling flow + follow-up label-inheritance retire | M | 2 | [C01] | interface: gate/consumer text names the exact new tool signatures + degrade contract C01 pins |
| C06 | coord+plan skills: per-ask research split (`Research: Parallel` label), agent-explore joinable roster text, AD-71 chunk-count guidance, Chunk Review done-gate carve-out (OQ15) | M | 2 | [C02] | interface: coord contract names agent-explore; its roster rows land in C02's commit |
| C07 | boards skill: Lifecycle redesign — 11 items (10 stages + Single Session kept) — Stage map, blank defaults, HITL alignment, transitions, cutover section update | M | 3 | [C05] | same file — serial; the gate/sibling text must be stable first |
| C08 | cutover process artifacts: provision-board.py spec extension + wekan-board-provision skill + board-rules v2 import artifact (MODIFY ONLY — never run live) | M | 4 | [C07] | data: engine constants + rule artifact carry C07's FINAL item list (batch-round answers may move it) |
| C09 | coder workspace TZ env (both templates) + human-facing stamp pass (plugin, boards prose, conventions) — OQ5-gated | M | 4 | [C07] | same-file prose (boards skill); independent of C08 |
| C10 | HOLD: deploy chain runbook — merge→v\<run\>→pin bump (dev + gpu per OQ8)→restart→probes→L4 absorb; cutover apply readback (human-executed, post-backup) | S | 5 | [C01, C08] | runbook pins the merged surface + the final artifacts; execution is post-merge, human-owned |
| C11 | post-research delta (OQ-P1 FOLD ruling, approved + widened 2nd round): `_slim_rule` extras+enabled passthrough (schema-2 capture executable) + docs-parity re-stamp + OQ-P2/P3/P4 text folds + T5 registry-recipe fold of the two adjacent surfaces (`wekan-mcp-ops` Deploy/verify loop, `container-creation` pin recipe) + green-on-arrival suite legs incl. cf96-deploy t8 guard | S | 6 | [C01, C05, C08, C10] | delta round over landed surfaces: extends C01's undeployed `_slim_rule` (rides the same `v<run>` build), edits C05's gate/degrade-law sections (same-file serial — C07's untouched), corrects C10's runbook step 2 (tests/**, test-route commit), and repairs the capture contract C08 advertises — capture texts themselves stay byte-untouched |

## Wave order
1. C01, C02, C03, C04 — all independent; run in id order.
2. C05, C06 — independent of each other; id order.
3. C07.
4. C08, C09 — independent of each other; id order.
5. C10 — HOLD: agent deliverable is the runbook + its pin suite; every execution step is human-owned (owner merge → CI → bump → backup → apply).
6. C11 — post-research delta (planned 2026-11-02 after all ten chunks closed; approved + widened the same day — T5 registry-recipe fold): dev lands code+docs+boards-text+both recipe docs in one commit (doc-parity law), the test route lands the runbook fold + new pins + cf96-deploy t8 green-on-arrival immediately after; lands PRE-MERGE so the C10 chain's `v<run>` build carries the passthrough. Nothing deploys; C10's human gate is unchanged.

## Run protocol — coord-owned board actions (this ticket's grouped flow, first instance)
- At start (after claim of #96): move siblings to **Executing**: 74=`MS8e8uoF27R2dk73e`, 66=`t4N5D4eZ9Nc2MoAZd`, 71=`v8priYKMuuWLCoFDq`, 77b=`Ru3CzNiyaEQH7YFcr`, 70b=`SouMZ2fbd8vDbz2m3`, 81=`Q7Sg7H4dicTALAp8q`, 78a=`jaEe2jfobfboyaM92`. They ride #96's claim (never claimed separately); the pickup walk skips Executing, so no double-pick.
- At end (their asks landed + final review APPROVED): move the same ids to **Review** with one summary comment each (chunk(s) that shipped the ask, commit range).
- L4 ledger card `r3ghE7qGj75HTnghH`: comment that this ticket absorbs its bump ask (the C10 runbook executes it); Inbox move-out stays owner-owned.
- This first instance runs from these plan-enumerated ids (dependency tools undeployed); later runs drive it from Red Strings edges per C05's section.

## Risks / assumptions
- HARD deploy gate: every consumer of the new tools degrades until the C10 chain
  lands (degrade law above); no answer in the batched round removes this gate.
- C11 rides the same undeployed build: the passthrough must land BEFORE the
  owner's pin bump, or the deployed `v<run>` ships the broken capture path and
  step-8 read-back degrades to schema-1 (RESEARCH F5) — order: C11 → merge → CI
  → bump. The C10 chain stays the only human gate; C11 adds no new one.
- OQ5 resolved: C09 ships `TZ = "America/Denver"`; the residual risk is the
  owner-gated workspace reprovision (template change ⇒ rebuild) — until then
  the emitters keep the UTC fallback (`$TZ` unset).
- OQ15's dev-only loop leans on the dev's RESULT command evidence for the
  done-gate — the coord's existing "never on the subagent's word" posture
  applies unchanged (evidence = the Commands in `commands_run`, all passing).
- No agent-side live REST probe of the dependency routes exists pre-deploy (no
  bearer in agent context); C01 carries the embedded-error guard posture and the
  first live confirmation is the C10 user probe.
- Export payload likely includes archived cards (C5): preload flags `archived`
  and pickup-relevant reshaping drops them; verify at first live probe.
- Moving 78a out of **Test** (human acceptance phase) is per the owner's grouped
  instruction; flagged here for visibility.
- Checklist extras on rules are UI/Import-JSON-only (never REST) — the cutover's
  rule update is human-executed by construction.

## Open questions — ALL RESOLVED (batched round, user answers 2026-11-01)
Pre-round closures: OQ2/OQ3/OQ7/OQ9/OQ10/OQ11/OQ12 landed as design decisions
(launch rulings / RESEARCH best guesses — see Design decisions + DECISIONS.md).
The eight batched-round questions returned these rulings, now folded into every
affected chunk:

1. **OQ1 — kind-1 follow-up representation.** RESOLVED: **parentId only** (deviated from the both-edge best guess). `create_card(parent_id)` records lineage; NO Red Strings edge for follow-ups; consumers must not expect kind-1 edges. → C01 T5, C05 T3/T4.
2. **OQ4 — timestamp conversion scope.** RESOLVED: **everything incl. machine fields** (deviated from human-facing-only). Encoded as displayed-stamps-local + instants-preserved: lock-file ISO fields (`claimedAt`/`heartbeatAt`), audit/timeouts.jsonl `at` and the board-context stamp convert to workspace-local with offset; epoch-ms instants (no-op marker `at`, gate epochs, mtimes) stay as-is — they are instants, not stamps. Reaper consequence verified + pinned in C09 AC2: the staleness consumers parse offset-aware (`Date.parse`), the 2 h window and `max(heartbeatAt, mtime)` formula stay correct writer-side-only, gate.sh needs zero change. → C09.
3. **OQ5 — IANA timezone.** RESOLVED: **America/Denver**, shipped for real in both coder templates; reprovision owner-gated. → C09 T1.
4. **OQ6 — Single Session.** RESOLVED (user verbatim: "Oh, At the end of Lifecycle leave the Single Session option"): Lifecycle = **11 items** — the ten stages plus Single Session LAST; semantics preserved (replaces the Test Writing/Chunk Development/Chunk Review run-shape); opt-in, not in the blank default; Stage map keeps its row; no transition rule needed; HITL mirrors the 11 items. → C07, C08.
5. **OQ8 — pin bump scope.** RESOLVED: **all three tiers** (dev-boards + gpu wekan-admin + wekan-readonly), one owner commit; values bumps prepared in the C10 runbook (planner's call: the `v<run>` tag exists only post-merge/CI, so nothing committable lands earlier); L4 absorbed. → C10.
6. **OQ13 — v2 createCard rule defaults.** RESOLVED: **only Model(s)→Qwen Flash checked**; Lifecycle/HITL unchecked (blank defaults govern); Type/Services unchecked. → C08.
7. **OQ14 — Exploration in the blank default.** RESOLVED: **yes** — every default run starts agent-explore. → C07 T3.
8. **OQ15 — Chunk Review unchecked.** RESOLVED: **skipped when unchecked** (deviated from the still-runs best guess) — dev-only chunk loop; done-gate = dev DONE + validations-green RESULT evidence; determinism mandatory; checked-stages-only carve-out in coord contract + Stage map. → C06 T5, C07 T2.

### Post-research round (2026-11-02) — RESOLVED (human ruling + coord dispositions, DECISIONS)
1. **OQ-P1 (F5 defect — schema-2 capture impossible through `get_rule`).** RESOLVED by the human: **FOLD THE CODE** — `_slim_rule` passthrough on the undeployed C01 surface, docs re-stamp, capture texts untouched (they become true by construction); the ruling's refinement per RESEARCH fix-shape (i): `extra_actions` + `extra_triggers` + `enabled`. → C11 T1/T2.
2. **OQ-P2 (fold-1).** RESOLVED by coord: TEXT fold — present-but-failed call degrades exactly like absence, one retry, never a stall; + the never-retires retire-table row. → C11 T3.
3. **OQ-P3 (folds-2/3).** RESOLVED by coord: TEXT fold — title-map fallback wording + unresolvable-edge-end = non-gating and REPORTED (skip-safe, never assume). → C11 T3.
4. **OQ-P4 (F4).** RESOLVED by coord: TEXT fold — runbook step 2 to the verified anonymous `tags/list` recipe, legacy-`:latest` hazard + v90–v102 distractors named, digest-verify leg kept; phrasing keeps all cf96-deploy pins green UNMODIFIED. → C11 T3.
5. **OQ-P5 (F6a — password change kills the static bearer).** RESOLVED by coord: OUT of ticket — Inbox follow-up card at close-out.

Second round, 2026-11-02 (human, two answers — DECISIONS):
6. **OQ-C11-1 — adjacent registry-recipe surfaces.** RESOLVED: deferral
   REJECTED by the user — **C11 WIDENS** and re-stamps both now: the
   `wekan-mcp-ops.md` Deploy/verify loop gains the anonymous-token `tags/list`
   enumeration half (the digest-compare bullet stays byte-intact — correct and
   live-proven) and the `container-creation` skill's `imagetools inspect`
   run-number hint is replaced with the verified tags/list flow, the legacy
   `:latest` hazard and the newest-tag-is-not-the-target caution where readers
   count tags (v90–v102 class). The plan-time audit (Verified facts) shows no
   suite content-grips either file ⇒ zero re-pins beyond cf96-deploy's new t8
   dead-sentence guard. → C11 T5.
   Also ruled: **(a) C11 APPROVED as planned** — T1–T4 stand verbatim.
   Nothing in the ticket remains open.
