# PLAN: cf-123 Tweak init
feature: 2026/2026-11-cf-123-bug-tweak-init
card: AD-123 (`xdrvXPW3LeF2TGpGD`) · type bug · Services `agent context` · Pipeline: Context
tiers: plan `openrouter/qwen/qwen3.8-2.4t-a95b` · code `openrouter/qwen/qwen3.8-27b` (STATE.json kickoff)
round: FINALIZATION 2026-11-07 — the five batched-round questions are owner-ruled (Open questions below, all RESOLVED); the deploy surface was re-probed in-session after the host restart (39-tool build live)

## Goal
Tweak the board-run init per the card's four asks: (A) trim the scheduled
loop file's comment-header junk that rides every hourly tick prompt, (B)
expand the board-context block to STRICT YAML with each list's cards
(`card_number` derived as `<boardKey>-<n>` / `card_id` / `labels`) —
including the wekan-mcp server change the owner ruled for (`key` added to
the `get_board` projection) and the requested "new MCP tool?" evaluation —
(C) land the owner runbook for `permissionAutoAccept` on the scheduled
task, and (D) inject the block on the FIRST prompt only with a
`/reload-board-context` manual refresh.

## Out of scope
- A new composite wekan-mcp tool (`get_board_context`): ruling #2 answers
  the card's evaluation — server-side projection YES (C04), composite tool
  NO (stays the standing follow-up, W1 Option A / DECISIONS Deferred).
- The claim-time card-details leg: `get_card_details` is now DEPLOYED (the
  39-tool build, in-session probe), ending its "surface absent" degrade —
  but that leg is not this ticket's ask; nothing here changes it.
- Writing host state: the permissionAutoAccept toggle and the loop
  re-approval are USER-owned steps (runbook below); agents never operate
  OpenChamber.
- L1's endgame (removing the NEED for the Always-Allow toggle — cf-90 plan
  appendix :143-149); this run lands the interim only.
- The loop file's body paragraph (byte-exact), the gate script, the
  `Repo:`/`Pipeline:` lock surface, and the lock-lost root cause (kickoff
  friction — owner's follow-up card candidate).

## The "add support to the MCP server?" evaluation (card ask B — settled by owner ruling #2)
- **Ruling**: the card-number prefix is the WeKan BOARD KEY — owner
  verbatim: "In wekan it's called the board key. You may have have to
  research it and add support to the MCP server." The prefix is DERIVED
  from the board document as `<boardKey>-<cardNumber>` (AI-Dev's key is
  `AD`, hence `AD-123`), never hardcoded, and this ticket gains the
  server-side projection change: **C04** adds `key` to `get_board`.
- **Key semantics, verified from repo sources (finalization round)**: the
  board document carries `key` — `update_board`'s echo projects it and its
  v12.65-source-checked docstring grounds the semantics (2-10 capitals,
  auto-assigned on insert, REST-immutable);
  `skills/wekan-api/references/rest-api-overview.md:130` agrees. The
  DEPLOYED `get_board` lacks `key` (re-proven live in-session; projection =
  id/title/permission/color/archived/labels) → the plugin carries the
  degrade (bare `card_number` + one pinned `#` note line) until C04's
  merge-day rollout lands — the probe/degrade law binds.
- **Block assembly stays Option 1 — consumer-side in the plugin** from ONE
  extra `preload_board` leg (deployed surface proven live: per-card
  `card_number`/`label_ids` + board-wide `label_names`; the pod now runs
  the 8-field shape with titles + checklists, 173 cards). **Option 2**
  (composite tool) rejected for now — the deploy chain means days of
  unreachability (W1 Option A: "right follow-up card, wrong primary"); it
  remains the standing follow-up. **Option 3** (extend
  `list_cards_in_list`) impossible — WeKan's by-list endpoint strips
  cardNumber/labelIds server-side.
- C04 is a PROJECTION change, not a new tool: the 39-tool registry pins
  (tools.sh t2, READS 18 / WRITES 21) are untouched — verified.
- Consequence kept from round 1: the S10 scope guards in
  tests/opencode/board-context.test.ts pin the OPPOSITE of ask B — the
  test session deliberately re-pins them (cards presence, six legs; the
  `list_cards_in_list` ban STAYS because Option 1 never uses that
  projection). Dev cannot write tests/**; the inversion is test-session
  authorship.

## Ask → decision map (grounded in EXPLORE.md + the finalization re-verification)
- **A — loop header trim (C02)**: keep every pinned byte (t3 `OQ-14|cf-106`
  citation; T2 raw `/pipeline-tick` + byte-exact body; N4 windows
  `openchamber+enabled+2026-10-29` ≤900ch and `hourly pipeline
  call+human-owned` ≤500ch; the single `enabled: true` row), drop the
  unpinned dead weight (P4 known-failure paragraph — the degrade law lives
  in the boards skill; D-numbered audit refs; run-tag sentence; retired-twin
  removal step), correct P2's stale "also enabled" legacy-task phrasing to
  the live `enabled:false` (2026-11-07 probe), keep ONE fingerprint-law +
  permissionAutoAccept clause (the owner's merge-day duty doc; L1 cited).
- **B — strict YAML + per-list cards (C01 + C04)**: fence contract per
  rulings #1/#2/#3 — the `CANONICAL_HEADER` line stays VERBATIM
  (five-artifact idempotence anchor; no `#`-comment header, no move); the
  body under it is strict parseable YAML: list mappings with `cards:`
  sequences of `{card_number: "<boardKey>-<n>", card_id, labels}`, mapping
  keys / list titles / label names / `card_number` double-quoted via
  JSON.stringify (ids bare), and the trailing footer prose becomes `#`
  comment lines (strict parseability; DECISIONS finalization). Prefix
  DERIVED from the existing get_board leg's `key` (no extra leg —
  source-verified; C04 adds the field server-side); degrade = bare number +
  the one pinned note line. Cards scope: ALL In Process lists, no cap
  (≈5 KB), archived skipped, `sort` ascending, unknown label ids emitted
  raw (live drift: `jXX4GM`), empty lists render `cards: []` from the
  plugin's own list_lists leg (verified: the preload still drops cardless
  lists under the NEW deployed shape). The preload leg passes `{board_id}`
  only, In Process scoping client-side (build-tolerant + drift-safe —
  DECISIONS finalization). Five artifacts move in ONE commit: plugin
  formatBlock, skill schema fence, EXPECTED_BLOCK, the CANONICAL_HEADER
  string (unchanged bytes), the collector emit instruction.
- **C — permissionAutoAccept (USER-owned)**: runbook below; mechanics
  grounded (PUT upsert preserving execution keys; toggle survives re-sync;
  runtime enrollment). Merge-day ordering carried explicitly: A's edit
  rotates the loopFingerprint (body is in the sha256), so the owner must
  BOTH set the toggle AND re-approve after merge, else the task sits
  loopApproval:"outdated" + forced-disabled and the hourly walk silently
  stops.
- **D — first-prompt-only + refresh (C03)**: durable once-mark in
  `ctx.storage` (key `once/<sessionID>`, epoch-ms; plugin-id+project-id
  scoped, shared by the two live opencode servers — pipeline-locks D26
  precedent; tolerant adapter, per-process in-memory fallback). Candidates
  rejected: session metadata (PATCH-replaces-whole hazard), message-history
  scan (per-prompt cost). Ruling #4: scheduled ticks UNCHANGED — each tick
  is a fresh session and keeps its first-prompt block; the once rule is
  session-scoped, durable across both server processes. Ruling #5: failed
  fetch KEEPS consume-once-whether-successful (today's S6 semantics; block
  absence is designed-normal). Refresh = plugin command
  `/reload-board-context` (ctx.command.transform precedent), human-typed
  only (D30: never a loop-body surface).

## Verified facts
Round 1 (branch == main f5ee40c64; suites re-run then, no repo edits since):
node suites green (board-context, pipeline-locks-tick); noop-marker N4,
wekan-mcp/skill-surface (8 ok), cf90-ledger, multi-repo/hourly-board-check
green; **provider-loops t7 RED pre-existing on main** (boards-skill
frontmatter teaches the retired two-task posture — C01 rider fixes);
wekan-mcp/board-context t1-t5 green, t6 + gate t14 + rulesync-surface c8 red
on this ticket's own untracked plan folder until the test session's
self-admit rows (cf-106 precedent row gate.sh:952); gate t17 known
exclusion; board-context.sh needs ≥900 s (cf-96 friction).

Finalization round (this session, 2026-11-07 ~15:20Z):
- server.py source: `_slim_board` = {id, title, permission, color,
  archived, labels} with `get_board` its only consumer; `update_board`'s
  echo already carries `board.get("key")` and its docstring grounds the key
  semantics; repo `preload_board(board_id, swimlane_titles=None)` DROPS
  cardless lists (`if not cards_in_list: continue`), emits swimlane/list
  titles, 8-field cards with checklists.
- plugin source: `resolveBoardContext` already calls `get_board` (consumes
  `labels` only) — the board key rides the EXISTING leg, no extra call.
- tests: NO suite pins the get_board field set; tools.sh pins registry
  names/counts via AST (a projection change does not move them);
  skill-surface t4 accepts either stamp spelling ("source-only" or
  "live probe"+"2026-10-27") — a mixed stamp row stays green.
- docs: skills/wekan-api lists tool names only (no get_board field shape →
  no C04 edit); skills/wekan-mcp/SKILL.md documents no get_board field set
  (no C04 edit); containers/wekan-mcp/README.md:113 and call-shapes.md:32
  carry the rows C04 updates.
- live (dev-boards, in-session): 39 tools; `get_board` answered top-level
  keys [id, title, permission, color, archived, labels] — NO `key`
  (re-proven; 19 labels); `preload_board`'s advertised signature DOES carry
  `swimlane_titles?` (correcting the relaunch brief's premise — the design
  stays build-tolerant regardless, DECISIONS).

## Commands
- test (node, from repo root): `node --test tests/opencode/board-context.test.ts`
- test: `node --test tests/opencode/pipeline-locks-tick.test.ts`
- test (shell suites): `bash tests/provider-loops/surface.sh` (t1-t8; t6
  nests the gate subset — slow) · `bash tests/noop-marker/surface.sh n4` ·
  `bash tests/wekan-mcp/skill-surface.sh` · `bash tests/wekan-mcp/board-context.sh`
  (nests gate.sh subset — cf-96 FRICTION: exceeds default shell timeouts,
  use ≥10 min) · `bash tests/agent-board-coord/rulesync-surface.sh` ·
  `bash tests/multi-repo/hourly-board-check.sh` · `bash tests/cf90-ledger/surface.sh`
- test (C04): `bash tests/wekan-mcp/tools.sh` (registry arms + the new
  offline `_slim_board` projection arm) ·
  `python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py`
- regen (any .rulesync edit): `npx --yes rulesync@37.0.0 generate` twice —
  second run must be a no-op — then `npx --yes rulesync@37.0.0 generate --check`
- quality: `npx aislop ci --changes`
- docker (C04, containers/ change): no daemon in agent sessions —
  `docker build => no-daemon, CI-deferred` is the designed passing gate
  shape (AGENTS.md / cf-77); docker-build.yaml on the merge is
  authoritative. helm lint/template: N/A (no chart in any chunk's blast
  radius; C04's image-pin bump is a merge-day renovate/USER step).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C02 | Loop header trim + stale-phrase correction (ask A; C's header clause) | M | 1 | [] | independent (disjoint files) |
| C04 | wekan-mcp `get_board` projects the board `key` (server + doc parity) | S | 1 | [] | independent (file-disjoint from every other chunk) |
| C01 | Board context block — strict YAML + per-list cards (ask B; t7-rider fix) | L | 2 | [C04] | interface-first: C01's prefix derivation + fence note consume the `key` projection C04 adds; the degrade keeps C01 shippable ahead of the server ROLLOUT regardless |
| C03 | First-prompt-only durable mark + /reload-board-context (ask D) | L | 3 | [C01] | same plugin file as C01 — serial, never parallel writes; the command answers C01's fence and rides its re-pinned seam/fixture |

Ids stay as round 1 minted them (C01–C03 are anchored in the STATE /
DECISIONS / FRICTION records); C04 appends — no renumbering.

## Wave order
1. Wave 1: C02 and C04 (independent, file-disjoint; either order)
2. Wave 2: C01
3. Wave 3: C03

Chunks run one at a time; the coordinator commits each approved chunk.
Test Writing happens BEFORE any dev: one agent-test session writes every
chunk's tests (the deliberate S10 inversion, C04's projection arm, and the
gate self-admit rows), per the checked Lifecycle stages. C02 review-time
note: provider-loops t7 is still red when C02 runs (pre-existing on main;
the rider fix lands with C01 in wave 2) — documented in C02's AC, not a
C02 defect.

## USER-owned runbook (merge-day — agents never execute these)
1. **Set permissionAutoAccept on `loop:project:pipeline-worker`** — any
   time; it survives loop re-sync (reconcileLoopTasks merges execution;
   UI-only fields the file format cannot express are preserved; runtime
   enrolls the session at runtime.js:844). UI: OpenChamber → SpencersLab →
   Scheduled tasks → pipeline-worker → the "Always Allow" toggle. Or
   owner-executed from the workspace host (server 127.0.0.1:3000,
   projectId `path_L2hvbWUvY29kZXIvU3BlbmNlcnNMYWI`): GET
   `/api/projects/<projectId>/scheduled-tasks`, set
   `task.execution.permissionAutoAccept = true` PRESERVING every other
   execution key (agent, modelID, prompt, providerID), PUT the whole task
   back to the same route (upsert).
2. **After this branch merges: re-approve the loop.** Ask A's header trim
   changes `execution.prompt` → `loopFingerprint = sha256({name, schedule,
   execution})` rotates → reconcileLoopTasks holds the task back as
   loopApproval:"outdated" with enabled forced false until re-approved —
   the hourly walk silently stops otherwise. Re-approve in the OpenChamber
   UI (the enable/approve action = setLoopApproval recording the new
   fingerprint). Order matters: the toggle (step 1) may be set before or
   after merge; the re-approval MUST come after merge.
3. **After this branch merges: the wekan-mcp deploy chain for C04's
   board-key projection.** Merge triggers `docker-build.yaml` → note the
   fresh `ghcr.io/ownyourio/wekan-mcp:v<run>` tag and check the newest tag
   is THIS merge's build (container-creation: the registry maximum is not
   automatically yours) → renovate opens the pin-bump PR
   (`services/dev/prod/values.yaml` boards + `services/gpu/prod/values.yaml`
   wekan-admin/wekan-readonly; currently `:v162`) → owner merges it →
   ArgoCD rolls the pods → verify with a `get_board` probe that the
   projection now carries `key` (and optionally promote the call-shapes
   stamp). Until this completes, the plugin emits bare `card_number` + the
   degrade note — designed behavior, no action needed.
4. L1 (cf-90 appendix :143-149) tracks removing the need for steps 1-2 —
   cite, do not re-scope.
5. Optional post-rollout hygiene (NOT this ticket): promote the cf-96/cf-106
   `source-only 2026-11` stamps in skills/wekan-mcp — the deployed shape is
   now live-proven (cord 15:02Z + this session's in-session probe);
   recorded as a follow-up candidate (DECISIONS finalization).

## Risks / assumptions
- 8 s admission budget with a sixth serial leg: the whole-board preload now
  carries checklists for ~173 cards (heavier than the old lean shape; the
  post-roll probes answered promptly). A breach degrades silently
  (untouched prompt, one stderr line — S6 shape). Leg parallelization is
  the recorded follow-up if live breaches appear (DECISIONS).
- Deploy state at finalization: the pod runs the 39-tool build (preload
  titles + checklists, `get_card_details` present); `get_board` carries NO
  `key` until runbook step 3 completes — C01's degrade is live from day one
  BY DESIGN, and the deployed surface stays the authority (never an
  assumption) for every consumer.
- Preload leg passes `{board_id}` only and scopes client-side —
  build-tolerant and drift-safe (a server-side `swimlane_titles` filter
  would render every list `cards: []` on a renamed swimlane; client-side
  scoping throws instead → the safe no-block degrade).
- Cards are a collection-time snapshot on every first prompt: walk drift is
  absorbed by the get_card confirmation + claim-before-move (the footer
  says so).
- Offline suites pin the D seam only; the cross-process behavior proves on
  the first post-merge scheduled tick + follow-up (live-smoke leg rides the
  Review comment, cf-75 LF precedent).
- The merge-day fingerprint rotation is a feature of OpenChamber approvals;
  the runbook above is the mitigation (card ask C's point).

## Open questions — ALL RESOLVED (owner, the one batched round 2026-11-07; never re-ask)
1. **YAML strictness — RESOLVED**: STRICT YAML under the UNCHANGED
   canonical header line; the header stays verbatim (five-artifact
   idempotence anchor); no CANONICAL_HEADER move, no `#`-comment header.
   (Plan consequence: the footer prose becomes `#` comment lines so the
   body parses strictly — DECISIONS finalization.)
2. **Card-number prefix — RESOLVED**: the WeKan BOARD KEY. Owner verbatim:
   "In wekan it's called the board key. You may have have to research it
   and add support to the MCP server." Derived from the board document as
   `<boardKey>-<cardNumber>`, never hardcoded; C04 adds `key` to the
   get_board projection; the plugin degrades to the bare `card_number`
   (+ pinned note line) until the rollout is proven in-session.
3. **Cards scope — RESOLVED**: ALL In Process lists, no cap (≈5 KB),
   archived skipped, empty lists render `cards: []`.
4. **Scheduled ticks — RESOLVED**: UNCHANGED — each tick is a fresh session
   and keeps its first-prompt block; the once rule is session-scoped,
   durable across the two live opencode server processes (the ctx.storage
   mark keying stands).
5. **Failed fetch — RESOLVED**: KEEP consume-once-whether-successful
   (today's S6 semantics — a failed first fetch is not retried on later
   prompts).

## Plan-approval gate
plan_status stays `draft`. This finalization round presents the plan to the
user with the one sanctioned approval question; only the user's word sets
`plan_status: "approved"` (recorded in STATE.json kickoff.approval, cf-106
shape). The plan-approval pause applies regardless of the card's
Human-in-the-Loop checks — it is a pipeline gate, not a card bit.
