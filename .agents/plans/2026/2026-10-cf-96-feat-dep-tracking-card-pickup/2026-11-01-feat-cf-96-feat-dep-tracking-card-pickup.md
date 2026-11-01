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
and coder-workspace timezone handling for human-facing timestamps.

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

## Commands
Run from the worktree root; `export PATH=$HOME/.local/bin:$PATH` first (helm).
- new suites (agent-test writes before dev; names are agent-test's, per-chunk
  files list them): one suite per chunk C01–C10 under `tests/` (statics-only,
  section-windowed greps — the cf-89/cf-90 posture).
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

## Wave order
1. C01, C02, C03, C04 — all independent; run in id order.
2. C05, C06 — independent of each other; id order.
3. C07.
4. C08, C09 — independent of each other; id order.
5. C10 — HOLD: agent deliverable is the runbook + its pin suite; every execution step is human-owned (owner merge → CI → bump → backup → apply).

## Run protocol — coord-owned board actions (this ticket's grouped flow, first instance)
- At start (after claim of #96): move siblings to **Executing**: 74=`MS8e8uoF27R2dk73e`, 66=`t4N5D4eZ9Nc2MoAZd`, 71=`v8priYKMuuWLCoFDq`, 77b=`Ru3CzNiyaEQH7YFcr`, 70b=`SouMZ2fbd8vDbz2m3`, 81=`Q7Sg7H4dicTALAp8q`, 78a=`jaEe2jfobfboyaM92`. They ride #96's claim (never claimed separately); the pickup walk skips Executing, so no double-pick.
- At end (their asks landed + final review APPROVED): move the same ids to **Review** with one summary comment each (chunk(s) that shipped the ask, commit range).
- L4 ledger card `r3ghE7qGj75HTnghH`: comment that this ticket absorbs its bump ask (the C10 runbook executes it); Inbox move-out stays owner-owned.
- This first instance runs from these plan-enumerated ids (dependency tools undeployed); later runs drive it from Red Strings edges per C05's section.

## Risks / assumptions
- HARD deploy gate: every consumer of the new tools degrades until the C10 chain
  lands (degrade law above); no answer in the batched round removes this gate.
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
