# RESEARCH — cf-96: dependency tracking + card-pickup context changes (AI-Dev board)

Pre-planning research round, commissioned by the board-coord run of card #96
(`iD4WjWQZrCykSe6Aj`), executed 2026-11-01. Method: the STORM interview stage is
realized as evidence-gathering against primary sources (same shape as the
sibling `2026-10-dep-wekan-v12-upgrade/RESEARCH.md`): GitHub `wekan/wekan` main
read first-hand (ground-truth order per the wekan-api skill: api.py >
models/*.js > docs), in-repo source reads, and live read-only probes of the
AI-Dev board via `dev-boards`. Every finding cites a source from the numbered
list at the bottom; nothing is cited from memory. Live board reads were done
~02:25Z; the instance was briefly unreachable (server-side ConnectError)
~02:12–02:20Z and recovered on its own — no data was written at any point.

## TL;DR

1. WeKan's dependency feature exists and is live in the lab's version: "Red
   Strings" card dependencies (#3392) — typed, colored, icon'd card→card edges
   stored on the source card (`cardDependencies`), with full REST CRUD since
   2026-06-15 and a per-user visibility toggle since 2026-10-01 [S1][S3][S4][S6].
   The lab runs WeKan **v12.65** (chart pin [S8]), which is newer than both
   dates, so nothing needs enabling server-side — the owner couldn't find it
   because the old board-header "Show dependencies" button was **removed** in
   the #6732 change; the switch now lives in **Member Settings (own avatar) →
   "Show Board Dependencies"**, off by default, per-user [S5][S6].
2. The MCP server (`containers/wekan-mcp`, 31 tools today [S13]) has no
   dependency tools and no board-wide preload. Both are straightforward adds:
   the five dependency REST routes are stable and documented [S4], and a
   preload can ride ONE call to `GET /api/boards/:boardId/export?attachments=false`
   (full board JSON incl. lists/cards/swimlanes/customFields/`cardDependencies`,
   with `?fields=` section trimming) instead of N per-card reads [S11].
3. Three distinct WeKan relation mechanisms exist and map onto the owner's
   three kinds: Red Strings edges (kinds 2+3), `parentId`/`parentIds` subtask
   links (#3626, multi-parent since 2026-09-29) and `linkedId` mirror cards
   (#5897) — the plan should pick Red Strings as the machine-readable edge
   store (same-board constraint is fine: everything is on AI-Dev) [S2][S4][S9].
4. Deploy chain matters: the **deployed dev-boards image is `:v87`** [S14] —
   it lacks even the v102 provisioning tools (cf-89), so every new tool this
   ticket adds needs: merge → `docker-build.yaml` pushes `v<run_number>` [S31]
   → pin bump in `services/dev/prod/values.yaml` (ledger card L4 tracks the
   v102+ bump [S27][L4]) → pod restart before any pipeline code may call it.
5. Sibling cards resolve: AD-74 = the label-tool card (`MS8e8uoF27R2dk73e`,
   alive in Not Started — the kickoff scan missed it because the by-list
   projection strips `card_number`); AD-66/71/77/70/81/78 disambiguated by
   content below, with two asks already shipped (cf-75, cf-90), one partially,
   and four open. Card numbers on this board are NOT a stable identity —
   numbers 70/77/78 each have two live docs, and one card renumbered 74→78.

---

## Q1 — WeKan dependency/linked-card feature: what it is, data model, REST, UI

### 1.1 Three distinct relation mechanisms on current wekan main

| Mechanism | Storage | Direction/scope | REST surface | Fit |
|---|---|---|---|---|
| **Card dependencies ("Red Strings")** #3392 | `card.cardDependencies: [{cardId, type, color, icon}]` on the SOURCE card | Same-board only for drawing AND for REST writes ("Target card is not on this board" → 400) [S4] | Full CRUD, 5 routes [S4][S1] | **Primary candidate** for dependency kinds 2+3 |
| **Subtask / parent links** #3626 | `card.parentId` (primary) + `card.parentIds[]` (multi-parent, maintainer decision 2026-09-29) | Parent may be another board if visible; REST sets parentId on create-bulk and PUT | `POST .../cards/bulk` body `cards[].parentId`; `PUT .../cards/:cardId` body `parentId`; single-card POST reads only a (currently always-undefined) route param [S9] | Candidate for kind-1 "follow-up created from" lineage |
| **Linked cards** #5897 | `card.linkedId` + `type: cardType-linkedCard` — the card IS a reference/mirror of another card (content lives on the target; cross-board allowed) | Reference, not an edge | `POST /api/boards/:boardId/lists/:listId/cards` with body `linkedId` (+`swimlaneId`) [S1][S9] | NOT a dependency — a second view of the same card; no role in the three kinds |

### 1.2 Red Strings data model (the one that matters)

From `models/metadata/dependencies.js` [S3] and `models/cards.js` [S2]:

- A dependency entry: `{ cardId, type, color, icon }`.
  - `type` ∈ `related-to | blocks | is-blocked-by | fixes | is-fixed-by | duplicates | is-duplicated-by` (7 types; `directed`/`forward` flags decide arrow drawing — `is-blocked-by`/`is-fixed-by`/`is-duplicated-by` draw the arrow backwards).
  - `color`: any CSS color, default `#eb144c`; `icon`: FontAwesome 4.7 name without `fa-`, default `link`; default type `related-to`.
  - `DEPENDENCY_TYPE_INVERSE` maps each type to its reverse (blocks ↔ is-blocked-by, etc.).
  - `normalizeDependency` accepts a legacy bare-string card id or partial object — external/old data stays valid.
- Storage is denormalized on the source card; the board-wide view is computed by walking cards. Cross-board targets are rejected by the write routes [S4].
- Linked cards are transparent for dependencies: a linked card's dependencies live on the card it points at (`realCard()` in [S4]).
- Archiving/moving a card cross-board pulls stale dependency entries targeting it ([S9] lines ~1070-1098) — edges self-clean on card moves.

### 1.3 REST routes (wekan main == v12.65 for these files, see 1.5)

From `server/models/dependencies.js` [S4] and `api.py` CLI commands `listdependencies` / `listcarddependencies` / `adddependency` / `editdependency` / `removedependency` [S1]:

| Route | Shape |
|---|---|
| `GET /api/boards/:boardId/dependencies` | ALL board lines: `[{from, fromTitle, fromCardNumber, to, toTitle, toCardNumber, type, color, icon}]` (archived cards excluded) |
| `GET /api/boards/:boardId/cards/:cardId/dependencies` | One card's deps: `[{cardId, type, color, icon}]` |
| `POST /api/boards/:boardId/cards/:cardId/dependencies` | Body `{"cardId": <target> (or "dependsOn"), "type"?, "color"?, "icon"?}` — **UPSERT**: existing edge updates its props, missing edge is added. Answer `{_id, cardId, type, color, icon}` |
| `PUT /api/boards/:boardId/cards/:cardId/dependencies/:targetId` | Body: at least one of `type/color/icon` |
| `DELETE /api/boards/:boardId/cards/:cardId/dependencies/:targetId` | `$pull` the edge |

Non-obvious facts for the plan:

- **Permission rule** (`models/lib/dependencyAccess.js` [S12]): a member may write Board Dependencies iff their role `write`s OR `moveCard`s (board admin, Normal, Worker; assigned-only members only on their assigned cards); site admin always. REST enforces the same rule board-level first, then per-card. **The pipeline service user qualifies** — it already moves cards on AI-Dev daily.
- POST validates `type` against the 7 ids and answers a clean 400 naming the allowed list on a bad type [S4].
- Since 2026-10-02 (commit `215293868b` [S6]) refused REST requests answer their REAL status (403/404), not 200+error — the wekan-mcp client's embedded-error guard still covers the documented v9.88 low bound.
- `GET /api/cards/:cardId` returns the FULL card document (`cardWithChecklists` spreads `...card` — `cardNumber`, `labelIds`, `customFields`, `cardDependencies`, `parentId` all present) [S9][S10]. The **by-list** projection strips everything but `{_id, title, description, swimlaneId, receivedAt, startAt, dueAt, endAt, assignees, sort}` [S9] — the same strip the wekan-mcp skill documents, and the reason the kickoff scan couldn't see card numbers (finding 5.1).
- There are two **separate** layers since #6732: Board Dependencies (on cards, everyone sees whose toggle is on, solid lines) and **My Dependencies** (private per-user profile lines, dashed, max 5000) [S5][S4]. The agent only needs Board Dependencies.
- Import/export of dependency lines exists (JSON or SVG-with-data-attributes; matches cards by id → cardNumber → exact title; import only ADDS) [S5][S4] — a useful human recovery path, not needed for v1.

### 1.4 How to enable it in the newest UI (the owner's actual question)

From the design doc [S5] and commit `cff80a9d7b` (2026-10-01) [S6]:

- **The board-header "Show dependencies" button is gone.** Issue #6732: one user toggling it wrote one shared board field, and only board admins could write it.
- Now: click **your own avatar → Member Settings** — at the top are **Show My Dependencies**, **Show Board Dependencies**, **Import**, **Export**. Both switches are **off by default** and saved per-user in the profile (`profile.showBoardDependencies`), following the user across boards/devices. Anyone who can view the board may show its dependencies — no board permission needed.
- With the layer shown, each minicard has a **connect handle**: drag onto another card to draw a line; click a line for its popup (change type/color/icon, remove). The card-details view also has a Dependencies section.
- The old board field `showDependencies` is no longer read (kept in schema for old boards/imports) [S5].
- The bot/service user's own toggle is irrelevant to the agent (REST reads never consult visibility), but the OWNER should flip "Show Board Dependencies" on for their account to see what the agent writes.

### 1.5 Version grounding — the lab instance has all of it

- Red Strings shipped 2026-06-15 (commit `2a0d9cbf09`: "typed relations, color/icon, badge, filter, REST API, import/export, docs" [S6]); directed duplicates 2026-09-28; per-user visibility + My Dependencies 2026-10-01; ErrorBleed status fix 2026-10-02.
- The lab pins WeKan **chart 12.65.0** (both the `wekan` and `boards`-alias entries in `services/home/prod/Chart.yaml` [S8]); v12.65 released 2026-10-25, v12.64 2026-10-24 [S7] — both NEWER than every dependency commit above. So v12.64 and v12.65 both carry the feature, the REST API, and the Member-Settings toggle. (The sibling upgrade ticket researched the v9.99→12.64 jump: 117 v9.99 routes all survive into v12.x, env stable [S26].)
- The files read from GitHub main (`server/models/dependencies.js`, `models/lib/dependencyAccess.js`) last changed 2026-10-16 or earlier [S6] — i.e. the main-branch code IS the v12.65 code for the dependency surface. One caveat: a live REST probe of the deployed instance wasn't possible this round (no bearer in agent context; the instance also had its transient outage) — the plan's first dev step should probe `GET /api/boards/TNQJ2BrXenZovngTS/dependencies` through a new/existing tool to confirm live, exactly as the wekan-mcp skill's deploy-verify loop prescribes.

---

## Q2 — containers/wekan-mcp: what adding support takes

Current state: `server.py` is 1115 lines, 31 tools (14 read, 17 write), one
`WekanClient` wrapper, `_slim_card` response shaping [S13]. Relevant gaps:

### 2.1 (a) Dependency read/write support — 5 thin tools

Each maps 1:1 to a route in 1.3; the precedent style is the cf-89 v102 block
(one additive, reviewable section at the file's end — that block's own header
pins the value of keeping new surface as ONE additive hunk [S13]):

- `list_board_dependencies(board_id)` → GET board deps (board-wide edge list with titles+cardNumbers — ideal for the pickup gate).
- `list_card_dependencies(board_id, card_id)` → GET one card's deps.
- `add_card_dependency(board_id, card_id, target_card_id, type=None, color=None, icon=None)` → POST (upsert semantics — document it; a repeated add UPDATES, never duplicates).
- `edit_card_dependency(board_id, card_id, target_card_id, type/color/icon)` → PUT.
- `remove_card_dependency(board_id, card_id, target_card_id)` → DELETE (the third destructive op — docstring-marked like `remove_rule`/`delete_checklist_item`).
- `_slim_card` should additionally pass through `card_dependencies` (and `parent_id`) from the full single-card document — `GET /api/cards/:cardId` already returns them; today `_slim_card` silently drops them [S13][S9]. One-line additions to `get_card`.
- Type validation client-side (mirror the 7-id list; reject unknowns before the request, same posture as `create_label`'s color gate [S13]).
- Write tools register through `_write_tool`, so `WEKAN_MCP_READ_ONLY` hides them automatically on the readonly tier [S13].
- Permission: no new grants needed — the service user's move/write role suffices (1.3 [S12]).

**Kind-1 follow-up support:** `create_card` gains an optional `parent_id` param (REST sets it via the bulk-create body `cards[].parentId` — the single POST create does NOT honor a body `parentId`; options: (i) two-step create→PUT `parentId`, or (ii) ride the bulk endpoint with one entry [S9]). Whether kind 1 also draws a Red Strings edge is a plan decision (Open question OQ1). Note the upstream bulk-label route `POST /api/boards/:boardId/cards/labels` (`{cardIds, addLabelIds, removeLabelIds}`, ≤500, write-access-gated, validates label ids against the board [S9]) — this is the missing piece behind AD-74 and behind follow-up-card label inheritance (the boards skill today degrades to a "labels to apply" comment line [S20][S24→C07]); adding a `set_card_labels` tool folds into this ticket naturally (OQ11).

### 2.2 (b) Board preload tool

- **Piggyback endpoint confirmed**: `GET /api/boards/:boardId/export` streams the full board JSON (format `wekan-board-1.0.0`): board header, `lists`, `cards` (full card docs — incl. `cardNumber`, `labelIds`, `customFields`, `cardDependencies`; linked cards excluded from the card array), `swimlanes`, `customFields`, `checklists`, `rules`, `activities` [S11]. It supports:
  - `?attachments=false` — skips base64 attachment payloads (a MUST for preload) [S11];
  - `?fields=a,b,c` — section trim: unselected sections come back as EMPTY ARRAYS; vocabulary includes `labels, people, dates, description, custom-fields, checklists, subtasks, comments, attachments, dependencies, sort, activities, board-header, scrum` [S11-exportFields];
  - auth via the normal Bearer header (the `authToken` query param is an extra path, not required) [S11].
- Proposed tool: `preload_board(board_id)` → one export call (`attachments=false`, `fields=` trimmed to what pickup needs), reshaped into the grouped map the card asked for: **by swimlane → list → cards**, each card carrying `{id, card_number, label_ids, slug (from the slug custom field), archived, sort}` + the board's **dependency lines** + label/field name maps. The owner said titles/descriptions are NOT needed — dropping them keeps the payload lean; keep `card_number` (slug derivation + human reference), `label_ids` (Pipeline:/Provider:/Research derivation), the slug field (resume-vs-new-run detection), `archived`/`sort` (walk order), and dependencies (the new gate).
- **Decision-relevant fields to raise with the owner** (the card explicitly invited this): `due_at`/`end_at` (stale-work triage?), `assignee_ids` (assigned-only visibility rules?), `parent_id` (follow-up grouping), `modified_at` (card staleness). Best guess: include `parent_id`, skip the rest until asked (OQ3).
- **Where it gets called — budget warning**: the board-context plugin races an 8 000 ms admission-latency budget and today spends it on 5 structural calls [S15]. A whole-board export of ~100 cards + checklists may exceed that even with attachments off. Recommendation: the preload is called by the **pipeline at claim time** (after `pipeline_claim`, alongside the existing pickup reads), NOT folded into the prompt-hook prefetch; the structural block stays as-is. If the owner wants it in the hook anyway, the budget and the schema footer ("Card and checklist ids are not included — they are live per-card data" [S15][S22]) both change (OQ3).
- Payload reality check: the export includes checklists/rules/activities unless trimmed — with `?fields=board-header,labels,custom-fields,dependencies,dates,sort` the sections not named arrive as empty arrays, keeping it small [S11-exportFields].

### 2.3 Deployment bump each new tool needs (the v87 reality)

- `services/dev/prod/values.yaml` pins the dev-boards image at `ghcr.io/ownyourio/wekan-mcp:v87` [S14] (comment still narrates ":v60 = the 25-tool build"). The repo source has 31 tools (cf-89's v102 block included); the deployed build has NEITHER — live-probed absent 2026-10-31 per the cf-90 ledger [S27].
- Shipping chain (all from repo fact): merge to `main` touching `containers/**` → `docker-build.yaml` pushes `ghcr.io/ownyourio/wekan-mcp:v<run_number>` (immutable, monotonic) + `:main` rolling tag [S31] → bump the pin in `services/dev/prod/values.yaml` (the L4 ledger card "Bump dev-boards wekan-mcp pin to a v102+ build" exists for exactly this [S27][L4]) → ArgoCD syncs the hivetools MCPServer → pod restart re-mints the login. The gpu tiers (`wekan-admin`/`wekan-readonly` in `services/gpu/prod/values.yaml`) share the image and want the same bump decision (OQ8).
- The wekan-mcp skill's failure-mode law applies: probe `tools/list` on the deployed server before any pipeline code trusts a new tool [S-wekan-mcp-skill]; the plan must sequence "pipeline calls preload/dependency tools" strictly AFTER the bump lands. The gpu+dev skill table + `references/call-shapes.md` evidence stamps need re-stamping in the same ticket (AGENTS.md "keep these lists current").

---

## Q3 — Pipeline surfaces the card touches

### 3.1 Prefetch today

- `.opencode/plugin/board-context/index.ts` [S15]: prompt hook for the 3 board-coord agents; discovers the dev-boards URL from the live MCP catalog or `.opencode/opencode.jsonc`, runs initialize → 5 resolution calls (`list_boards, get_board, list_swimlanes, list_lists, list_custom_fields`), appends the Board context block to the first prompt. `DEFAULT_ENABLED = true` since the 2026-10-29 live-fire proofs (LF1-LF7 citation in-file) [S15][S16]. Never-throw posture; 8 s budget; once-per-session TTL 6 h; canonical-header dedup.
- The block's single normative home is the wekan-mcp skill's schema section [S-wekan-mcp-skill]; the `/wekan-board-context` collector command emits the same block for manual pasting [S22]. Both say cards are NOT pre-collected. The card's new preload tool is the sanctioned place to change that (2.2).
- `scripts/board-preload-probe.sh` [S16] is the probe harness for the hook's enablement legs — NOT the preload itself; it needs no change unless the hook block grows.

### 3.2 Pickup + lifecycle + kickoff (boards skill, .rulesync/skills/boards/SKILL.md [S20])

The dependency gate ("a card whose depended-upon card is not in Test or Finished must not be picked for Execution") lands in the **Card pickup** section: candidate cards already get `get_card`'d at pickup (step 3); with the preload (2.2) the gate needs ZERO extra round-trips — edge list + card→list map are in hand. Design notes for the plan:
- "Test or Finished" = the two In-Process lists (`Test=jNYNdCPPkX8Bs95s4`, `Finished=DHw56fMKy3qyfudz4` — live ids [S25]). A dependency of type `blocks`/`is-blocked-by` pointing AT the candidate from an unfinished card is the blocking shape; decide the exact edge-direction convention (OQ2).
- The pickup walk itself (Rework → Not Started → Low Priority, skipping locked sets on scheduled runs, Provider filtering) is otherwise untouched [S20].
- The **grouped-sibling flow** ("I'll use it to group multiple small related tasks in the future") is a NEW boards-skill section: when a card's relationships (the new dependency edges) name companion cards, the run pulls their asks into its own plan/execution, moves them to Executing at start and to Review at the end — the exact flow this card's owner used with card numbers here. This ticket executes the first instance of it (Q5 below).
- **Lifecycle cutover**: today's Lifecycle = `Pre Research | Plan | Post Research | Test | Code | Review | Deploy | Single Session` [S20]; the card replaces it with a 10-item list: Exploration, Agent Decides Research, Pre Research, Planning, Post Research, Test Writing, Chunk Development, Chunk Review, Final Review, Deployment. Consequences the plan must carry: the Stage map table rewritten (new names, new `Exploration` row running the new agent-explore, `Agent Decides Research` = today's coord-judged research [S19]); blank-Lifecycle default becomes "all steps, Agent Decides Research instead of Pre/Post, Deployment skipped" (today's default is Plan+Test+Code+Review [S20]); blank-HITL default becomes **Final Review** (today: Plan [S20]); HITL items match the Lifecycle list with "human engaged AFTER that step (even if skipped)"; `Single Session` disappears from the checklist (transition rule for existing checked cards needed — OQ6). The legacy-Research-checklist transition section [S20] rewrites accordingly (this card itself still carries the legacy Research checklist — kickoff consumed it under today's transition rule [STATE.json]).
- **Research split**: the card wants coord to run one `agent-research` session PER research ask, **serial unless the card carries a `Research: Parallel` label**. That touches the pipeline-role-coord Research section [S19] (currently "launch agent-research with the scope" — singular) and the boards research-only loop [S20]. The `Research: Parallel` label is a NEW human-created board label (labels stay human-owned per D17/D19 [S20]); matched case-insensitively like the existing `Research` label. It exists nowhere in the repo yet (grep-verified).

### 3.3 agent-explore (new agent)

- Pattern: `agent-research`'s source [S24] is the closest template (read/glob/grep/skill/question/webfetch allowed, edit denied except `.agents/plans/**`, no subagents, shell ask-default with read-only git allows). agent-explore is stricter: fully read-only (NO edit grant anywhere — it hands back via RESULT), plus the `readonly*`/`dev*` MCP grants it needs to ground "MCP ids and such" (the research row's MCP posture [S23]).
- Adding an agent is the agents-sync checklist [S23][agents-sync]: new `.rulesync/subagents/agent-explore.md` → `rulesync generate` → roster rows on ALL SIX coord twins (agent-coord{,-local,-pr} + agent-board-coord{,-local,-pr} — the same-commit parity law; parsed-equality suites pin the pairs [S19]) → permissions.md matrix row → agents-sync references pipeline-overview mention → AGENTS.md roster paragraph ("Keep these lists current"). The stage gate adds an `Exploration` Lifecycle row that launches it "before Research > Before Planning" (the card's words).
- Output artifact: RESULT only vs an `EXPLORE.md` next to the plan file (OQ10). Everyone-reads-at-run-start precedent exists only for RESEARCH.md [pipeline-conventions]; a new file type means touching the conventions skill's read order.

### 3.4 Board-side cutover / initialization-and-update process (modify, DO NOT run)

- Today's provisioning engine `scripts/provision-board.py` (207 lines, offline, additive-only) covers ONLY: Backlog→Planning list mirror, `Bucket:` label + createCard/moveCard rule pair per Planning list, Provider labels, Inbox ensure [S21]. It has NO checklist section — the five standard checklists are the board's multi-action createCard rule's doing (extras creatable ONLY via UI wizard or Rules→Import JSON, never REST — v12-upgrade research [S26]).
- The card's "modify the initialization and update process to include the changes" therefore means: extend the provision spec + skill + engine with (a) the renamed **Lifecycle** checklist and its 10 items, (b) the **Human in the Loop** checklist item-set match, (c) the createCard rule's checklist-extras update (runbook/UI-import-JSON work, human-executed), and (d) the new `Research: Parallel` label ensure. Runbook precedent: the boards skill's "Board-side cutover — human-owned, documented, never agent-executed" section [S20] is exactly where this lives; the wekan-v12-upgrade folder keeps `board-rules-v12.64.json` (the rules-import artifact) which needs a v2 [S26-folder].
- The card's explicit order: change the process artifacts in this ticket, but DO NOT run the provisioning against the live board — the owner takes a backup and runs it themselves after the work lands. The plan must gate every apply step behind that human action (same posture as the v12 upgrade runbook [S26]).
- Note the wekan-board-provision skill already documents the deployed-surface degrade: `create_list`/`create_label` absent on :v87, raw-REST fallback recipes for the human shell [S21] — the pin bump (2.3) retires that degrade.

### 3.5 Loop/worker files

`.agents/loops/pipeline-worker.md` (Provider: API, hourly :00) and `pipeline-worker-local.md` (Provider: Local + unlabeled, hourly :30) [S17][loop-local] carry only the one-sentence tick body; pickup semantics live in the boards skill, so the loops need NO change for dependency gating. One loop-adjacent fact for Q4: the cron runs UTC (comment: "timezone is omitted so the server default applies" [S17]), and OpenChamber stamps `kind:"scheduled"` itself — loop timestamps are not workspace-local either.

---

## Q4 — Coder workspace timezone

Facts gathered live (read-only):

- This workspace (`SpencersLab-Claud`, owner `thehackmeister`, `CODER_AGENT_URL=https://coder.spencerslab.com/`) has **`$TZ` UNSET**; `/etc/localtime -> Etc/UTC`; `date` prints UTC [S36].
- Timestamp emitters today are UTC-by-construction: `board-context` plugin `collectedAt: new Date().toISOString()` [S15]; `pipeline-locks` plugin ISO-UTC stamps + epoch-ms in lock files and `timeouts.jsonl` [S-plugin-locks]; `board-preload-probe.sh` `date -u` [S16]; the gate script epoch-ms [S-gate]; STATE.json `updated_at` Z-suffixed; the boards no-op session title `no-op <yyyy-mm-ddThh:mm>` (bare `date` — would follow `$TZ` if set) [S20].
- Coder's own docs treat the `TZ` env var as the timezone mechanism ("falls back to either the TZ environment variable or /etc/localtime" [S29]). There is no per-workspace timezone setting in the Coder dashboard for the environment itself (the `schedule start … [location]` IANA zone is only for start/stop scheduling [S29]).
- **The workspace template lives in THIS repo**: `charts/coder/coder-templates/kubernetes/main.tf` (538 lines) + `kubernetes-hardened/main.tf` (543 lines). The `coder_agent.main` resource has an `env = { … }` block (L161-165: OPENCODE_BINARY/SERVER_USERNAME/SERVER_PASSWORD) [S37]. Adding `TZ = "<IANA zone>"` there propagates to every process the agent launches — startup script, terminals, code-server, and the OpenCode server (the plugin host). That is the correct layer: dotfiles (`~/.bashrc`) reach only interactive shells, not the agent-spawned OpenCode server.
- What "timestamps used should be in the coder workspace timezone" touches once TZ is set: nothing automatic — every emitter above hardcodes UTC (`toISOString`, `date -u`). The change is per-emitter formatting for HUMAN-facing timestamps (board-context block stamp, no-op marker session title, claim/summary comment stamps, STATE.json if wanted); machine fields (lock files, epoch-ms, WeKan's own stored dates) should stay UTC/epoch. WeKan stores dates UTC; card-date DISPLAY is browser-local (no timezone field in WeKan's user model — grep of models/users.js found none [S30]), so card due/start dates shown in the UI already follow the owner's browser.
- Research-grade only, per the launch constraint: nothing was changed. The owner's IANA zone is unknown to the agent (OQ5); the plan should carry the one-line template env add plus the emitter formatting pass, gated on the zone answer.

---

## Q5 — Sibling-card asks digest (all candidates pulled live 2026-11-01 [S25])

Board context: the board has 4 swimlanes — In Process (pipeline lists), Backlog (Bucket lists + Inbox), Farm, Planning (Bucket mirrors) — full list map in [S25]. **card_number repeats across swimlanes** (two live docs each for 70, 77, 78), so "AD-<n>" disambiguation below is by content; the picks favor the agent-context/wekan family the card is about, with reasons recorded.

| AD-# | Chosen card (id, live list) | Ask | Lands on / status |
|---|---|---|---|
| **AD-74** | `MS8e8uoF27R2dk73e` "wekan-mcp: add a label tool to drop the rules-engine round-trip" — **Not Started**, In Process | Add label read/apply tools to wekan-mcp (list board labels — already via get_board; card label_ids — already via get_card; **set/remove labels — missing**) | Q2.1: upstream's bulk route `POST /api/boards/:boardId/cards/labels` [S9] is the backend; a `set_card_labels` tool + retiring the boards-skill "labels to apply" comment degrade [S20]. Identity pinned by cf-90 C07 live get_card 2026-10-31 [S27]. OPEN |
| **AD-66** | `t4N5D4eZ9Nc2MoAZd` "System-upgrade-controller on renovate" — Backlog/CICD | Get the k3s system-upgrade-controller (charts/base/templates/k3s-system-upgrade-controller.yaml [S38]) managed by renovate | Separate small chunk (renovate.json package rule); not agent-context but explicitly grouped by the owner. OPEN |
| **AD-71** | `v8priYKMuuWLCoFDq` "Reduce the number of chunks the planner creates for small tasks / Have dev work all chunks in a wave?" — Backlog/Context | Smaller plans for small tasks; wave-parallel dev | PARTIAL: pipeline-role-plan already groups "up to 5 S tasks into one chunk" [S35]; the wave-parallel half is unbuilt (coord runs one chunk at a time [S19]). The Lifecycle `Chunk Development` redesign is the moment to revisit |
| **AD-77** | `Ru3CzNiyaEQH7YFcr` "Fix rest-api-overview.md POST /api/boards board-colors list (v12.65 BOARD_COLORS)" — Planning/Context (NOT #77a "Strata in llama-swap", Test list — active human testing, unrelated gpu infra) | Stamp the v12.65 BOARD_COLORS list into skills/wekan-api/references/rest-api-overview.md | One-doc chunk; the doc currently has NO BOARD_COLORS entry (grep-verified [S33]). Fits this ticket — the same doc surface the dependency tools update. OPEN |
| **AD-70** | `SouMZ2fbd8vDbz2m3` "templates/FRICTION.md: fix 'cord' typo in the append rule" — Planning/Context (NOT #70a "Wekan 9.99→12.64 input fields need click-add", **Finished** + Research label — research-only card already run; re-opening a Finished card is human-owned territory) | Fix `cord` → `coord` in `.agents/plans/templates/FRICTION.md` | Still present — line 5 verified live [S32]. One-word fix; the typo seeds every new ticket folder. OPEN |
| **AD-81** | `Q7Sg7H4dicTALAp8q` "Update -pr agents to understand a PR in draft covers 'unit' tests…" — Backlog/Context | -pr agents understand: draft PR = unit tier (chart starts, user can login); ready-for-review = integration tier (deploy services, restore backup, confirm data) | MOSTLY SHIPPED: cf-90 C05/C06 wrote exactly this two-tier contract into pipeline-push-pr (draft/unit fires during draft via plain `on: pull_request`; ready/integration keyed `ready_for_review` + draft guard) [S34][git-log]. Remainder: verify every -pr agent surface carries it + the backup-restore detail; owner note "(will need to go beyond v102)" = its execution needs the NEW wekan-mcp build deployed (2.3 chain), matching ledger L4 |
| **AD-78** | `jaEe2jfobfboyaM92` "coord route test fixes automatically" — **Test** list (NOT #78b "[cf-90 ledger L1] Always-Allow…" Planning/Context — a big OpenChamber-permission ledger scope, queued for the owner) | Coord should route test fixes to the test-writing agent silently instead of asking the user, unless functionality changes | ALREADY SHIPPED: cf-75 C02 implemented and documented exactly this (silent route to `test_session`; functionality carve-out = the test session's NEEDS_INFO escalation; user-confirmed OQ6/DECISIONS) [S28]. The card sits in Test = human acceptance phase. Integration here = confirm coverage + move to Review at run end per the owner's instruction |

The card's move protocol for the group: coordinator moves the chosen siblings to **Executing** at start and to **Review** when their asks land — the coordinator owns these moves (this research session touched nothing).

---

## Contradictions and how they were weighed

- **C1 — "AD-74 cannot be found" vs it being alive.** The kickoff's full-swimlane scan reported no card_number 74; a direct `get_card` on the cf-90-pinned id found it live in Not Started, card_number 74 [S25]. Root cause: `list_cards_in_list` strips `card_number` (returns null) [S9][S-wekan-mcp-skill rule 6] — a scan that doesn't `get_card` each candidate is blind to numbers. Weigh: the live single-card read wins; the kickoff note is a known-projection artifact, not a board truth. (This is itself an argument for the preload tool, which returns card_numbers in bulk.)
- **C2 — Two cards claimed the number 74 historically.** cf-75's 2026-10-27 records call `jaEe2jfobfboyaM92` ("coord route test fixes automatically") card #74 [S28]; that same id reads card_number **78** today, while `MS8e8uoF27R2dk73e` holds 74 [S25]. Weigh: card numbers on this board are COUNTER ASSIGNMENTS that can change on cross-board moves (WeKan re-numbers from the destination board's counter) — number ≠ identity. The cf-90 C07 identity pin (get_card-verified 2026-10-31 [S27]) is the newest evidence and wins. Consequence for the plan: dependency edges and all cross-card references must key on card `_id` (Red Strings does exactly this [S3]), NEVER on card numbers; `card_number` rides along only as a human-facing label.
- **C3 — Duplicate live numbers 70/77/78.** Two live docs per number (kickoff candidates, confirmed live [S25]). Resolved per-row in Q5 by content fit + list posture (a card in Test is in human testing — don't steal it; a card in Finished is human-accepted — don't reopen it; ledger cards in Planning/Inbox queue for the owner). Residual risk: the owner meant the other candidate — that's OQ12.
- **C4 — "Enable" the feature: board header vs member settings.** Older WeKan had a board-header "Show dependencies" button (board field, admin-only write); #6732 removed it in favor of per-user Member-Settings switches [S5][S6]. The owner's memory of the button explains the "can't figure out how to turn it on" — both claims are true at different dates. Weigh: v12.65 UI = Member Settings only.
- **C5 — Export payload shape: cards include or exclude archived?** The dependency-list route filters `archived: false` explicitly [S4]; the exporter's card selector shows `boardId + linkedId` filters with no visible archived filter in the read section [S11] — archived cards likely ride the export (import needs them). Weigh: the preload tool must filter or flag `archived` client-side; the reshaped map drops archived cards from pickup-relevant lists (verify live in the first dev probe).

## Implications for the plan

1. **Dependency mechanism**: Red Strings for kinds 2+3; kind 1 = follow-up lineage (parentId at create AND/OR a typed edge — OQ1). Enforce NOTHING in WeKan rules/automation: the pickup gate is coordinator logic over preloaded state (Q3.2). Edge direction convention = OQ2.
2. **MCP server chunk set**: 5 dependency tools + `preload_board` + `set_card_labels` (AD-74) + `get_card`/`_slim_card` passthrough of `card_dependencies`/`parent_id` + optional `create_card(parent_id=)` — one additive block per the v102 precedent [S13]. README + wekan-mcp skill table + call-shapes.md re-stamp in the same ticket.
3. **Deploy sequencing is a hard gate**: new tools unusable until merge → v<run> → pin bump (values.yaml; fold the L4 ledger ask) → pod restart; every pipeline-side consumer chunk depends_on the bump chunk. AD-81's "beyond v102" note is exactly this (2.3).
4. **Preload consumer**: coordinator at claim time, not the prompt hook (8 s budget) — unless the owner says otherwise (OQ3). The board-context block schema footer + the /wekan-board-context command text change only if the hook grows.
5. **Lifecycle cutover is the biggest text delta**: boards Stage map rewrite (10 stages, new defaults: blank = all steps minus Deployment with Agent-Chooses-Research; blank HITL = Final Review), HITL alignment, transition rules for legacy Research-checklist AND Single-Session-checked cards, pipeline-role-coord stage-gate citation updates, provision spec/skill/engine extension with checklist sections + `Research: Parallel` label ensure — all modify-only, runbook execution stays human-owned and POST-backup per the card's explicit order (3.4).
6. **agent-explore**: new read-only subagent + six-twin roster widening + permissions row + `Exploration` stage row; output artifact OQ10.
7. **Research split**: pipeline-role-coord Research section + boards loop: one session per ask, serial unless `Research: Parallel` labeled (new label, human-created; match case-insensitively).
8. **Timezone**: one-line `TZ` env in `charts/coder/coder-templates/kubernetes*/main.tf` coder_agent env (owner's zone = OQ5) + human-facing emitter formatting pass; machine stamps stay UTC. Template change = workspace reprovision, owner-gated.
9. **Sibling group execution**: first run of the new grouped-flow section — AD-74/66/71/77b/70b/81/78a pulled into this ticket's plan per Q5; AD-78a ships as "verify cf-75 coverage + card to Review"; the two wrong-number candidates (Strata #77a, input-fields #70a) stay untouched with reasons recorded.
10. **Identity rule**: all new cross-card references by `_id`; card_number displayed-only (C2).

## Open questions (ride into the plan's batched round)

- **OQ1** Kind-1 follow-up representation: Red Strings edge only (convention type/color/icon — e.g. `related-to` + icon `code-fork`), `parentId` subtask link only, or both? Best guess: BOTH — parentId records creation lineage (UI shows the parent path), a typed edge makes the relation visible on the board and queryable like the others. Impact: create_card signature + follow-up-card protocol text.
- **OQ2** Kind-2 edge direction: store on the DEPENDENT card as `is-blocked-by → dependency`, or on the dependency as `blocks → dependent`? Best guess: store `is-blocked-by` on the dependent card (reads naturally per-card; the board-wide list shows both directions via the inverse map). Impact: gate logic + convention docs.
- **OQ3** Preload call site: coordinator-at-claim (best guess) vs board-context hook extension (budget risk, schema-footer change). Extra fields to include beyond id/card_number/label_ids/slug/list/dependencies — `parent_id` (best guess: yes), dates/assignees (best guess: no until asked)?
- **OQ4** Which timestamps convert to workspace-local: human-facing only (best guess: block stamp, no-op title, comment stamps) vs also STATE.json? Machine fields (locks, epochs, WeKan card dates) stay UTC.
- **OQ5** The owner's IANA timezone for the template `TZ` env (best guess: ask — do not ship a guessed zone).
- **OQ6** `Single Session` fate in the new Lifecycle: retired (the card's 10 items omit it) — what about cards that still carry it checked? Best guess: transition rule maps checked Single Session to the new "Chunk Development" run shape (one dev session, no chunk loop).
- **OQ7** AD-66 scope: implement renovate management of system-upgrade-controller IN this ticket (best guess: yes, small chunk — the owner grouped it deliberately) or track-only?
- **OQ8** Pin bump scope: bump dev-boards only (L4's letter) or gpu wekan-admin/wekan-readonly too (same image; best guess: bump all three, they share the tier surface)?
- **OQ9** My Dependencies (private user layer): expose anything for it? Best guess: NO — Board Dependencies only; mention it exists in the skill docs.
- **OQ10** agent-explore output: RESULT-only vs `EXPLORE.md` next to the plan file (best guess: EXPLORE.md, added to the conventions read order) — the card's "ground the task" implies a durable artifact research/planning read.
- **OQ11** `set_card_labels` tool in this ticket (best guess: yes — AD-74 asks it, follow-up label inheritance needs it, upstream route ready [S9]) or keep AD-74 a separate follow-up?
- **OQ12** Sibling-pick confirmation: the content-based AD-77/70/78 picks (77b/70b/78a) — best guesses recorded in Q5; wrong picks cost one re-point each, the board moves are coordinator-owned anyway.

## Adjacent

- The board carries a `Cancelled` list (In Process, `52dS3k7Kdk9EB5cJj` [S25]) no skill text mentions — pickup never visits it; nothing to do, noted for drift awareness.
- `Provider: Local (dup)` label (`PnhFKk`) exists alongside `Provider: Local` (board_context in STATE.json) — human-owned label hygiene, out of scope.
- The dev cluster `mcp.dev.scifi.farm/boards` ingress + OIDC-disabled posture [S15-OQ-e] means the preload tool's hook path (if chosen, OQ3) keeps working credential-free; OIDC re-enablement would need the plugin re-stamp.
- The 02:12–02:20Z WeKan outage (server-side ConnectError on every route, self-recovered) matches the wekan-mcp skill's "cold Mongo/lock" failure mode family [S-wekan-mcp-skill] — worth a FRICTION line if it recurs during implementation.

## Sources

- [S1] `wekan/wekan` GitHub main `api.py` (read 2026-11-01): dependency CLI block L1812-1879 (routes + types + examples), `linkcard` L1581-1598, `exportboard`/import L1971-2007.
- [S2] `wekan/wekan` main `models/cards.js`: card schema field enumeration (title…cardDependencies, parentId/parentIds L152-171, linkedId L825, cardDependencies L833-867 with #3392 comment).
- [S3] `wekan/wekan` main `models/metadata/dependencies.js` (full read): storage shape, 7 types, defaults, inverse map, normalization.
- [S4] `wekan/wekan` main `server/models/dependencies.js` (full read): 5 REST routes + bodies, upsert POST, same-board constraint, `dependsOn` alias, permission gate `checkRestDependencyAccess`, Meteor methods (`setDependencyVisibility`, `setBoardDependency`, My Dependencies set), linked-card transparency, import/export merge semantics.
- [S5] `wekan/wekan` main `docs/Features/General/Editor/RedStrings/Board-And-My-Dependencies.md` (full read): two layers, Member Settings switches off-by-default, role table (edit-or-move), import/export formats, implementation map, `showDependencies` board field retired.
- [S6] GitHub commit history for `server/models/dependencies.js`: `2a0d9cbf09` 2026-06-15 (Red Strings incl. REST), `eb527dd13f` 2026-09-28, `cff80a9d7b` 2026-10-01 (per-user visibility + My Dependencies; file list incl. boardHeader.jade removal), `215293868b` 2026-10-02, `b7589737f5` 2026-10-16.
- [S7] `wekan/wekan` main `CHANGELOG-big.md`: v12.64 2026-10-24, v12.65 2026-10-25, v12.77 2026-10-31 release dates.
- [S8] repo `services/home/prod/Chart.yaml` L39-48: wekan chart `12.65.0` ×2 (wekan + boards alias).
- [S9] `wekan/wekan` main `server/models/cards.js`: by-list projection L1357-1384; single-card GET L1389-1401; bulk create with `parentId` L1577-1678; `req.body.parentId` PUT L1762-1777; bulk labels route L2280+; route inventory; cross-board move dependency cleanup L1070-1098.
- [S10] `wekan/wekan` main `server/lib/checklistDeadlines.js`: `cardWithChecklists` = `{...card, checklists}`.
- [S11] `wekan/wekan` main `models/export.js` + `models/exporter.js` + `models/lib/exportFields.js`: export route auth/`?attachments=false`/`scope`/`fields`, `wekan-board-1.0.0` payload sections, empty-array-not-missing rule, linked-card exclusion, `BOARD_EXPORT_FIELD_KEYS` vocabulary incl. `dependencies`.
- [S12] `wekan/wekan` main `models/lib/dependencyAccess.js` (full read): `canEditBoardDependencies` = write OR moveCard, card-visibility rules, My-Deps max 5000.
- [S13] repo `containers/wekan-mcp/wekan_mcp/server.py` (full read) + `wekan.py` + `Dockerfile`: 31 tools, `_slim_card` shape, `_write_tool` read-only gating, v102 additive-block precedent, embedded-error guard, label-color client gate.
- [S14] repo `services/dev/prod/values.yaml` L403-409: `boards` image `ghcr.io/ownyourio/wekan-mcp:v87`.
- [S15] repo `.opencode/plugin/board-context/index.ts` (full read): hook design, 8 s budget, block schema mirror, DEFAULT_ENABLED + LF proofs, URL discovery.
- [S16] repo `scripts/board-preload-probe.sh` (full read): probe-leg harness, `date -u` stamps, structural-tool list.
- [S17] repo `.agents/loops/pipeline-worker.md` (full read): hourly :00 UTC cron, Provider: API walk, plain-text tick body.
- [S18] repo `.rulesync/subagents/agent-board-coord-local.md` (full read): permission block, subagent roster rows (plan/test/dev-local/review/research/dev-deploy), dev-boards-only MCP grant.
- [S19] repo `.rulesync/skills/pipeline-role-coord/SKILL.md` (full read): loop steps 0-11, Research section (singular launch today), stage gate, step 8b, one-chunk-at-a-time.
- [S20] `.rulesync/skills/boards/SKILL.md` (loaded content, 329 lines): pickup walk, Lifecycle/HITL checklists + defaults, Stage map, transition rule, board-side cutover runbook section, research-only loop, write-back, follow-up-card protocol + label degrade, batched questions.
- [S21] repo `skills/wekan-board-provision/SKILL.md` (full read) + [S21b] `scripts/provision-board.py` (full read): engine spec (lists/labels/rules/inbox only, no checklist sections), apply procedure, `:v87` tool-probe note + raw-REST fallback.
- [S22] repo `.rulesync/commands/wekan-board-context.md` (full read): 5-call collector, schema citation.
- [S23] `.rulesync/skills/agents-sync/references/permissions.md` (relevant rows): coord roster law, research row, same-commit parity, no-git-write roster, MCP tier posture.
- [S24] repo `.rulesync/subagents/agent-research.md` (full read): permission template for a read-mostly subagent.
- [S25] Live `dev-boards` reads 2026-11-01 ~02:25Z (read-only): card #96 + claim comment; #66 `t4N5D4eZ9Nc2MoAZd`, #70a `fWAw8RKWjcDpmrQf5`, #70b `SouMZ2fbd8vDbz2m3`, #71 `v8priYKMuuWLCoFDq`, #74 `MS8e8uoF27R2dk73e`, #77a `gCcXSu3DZd6NEp97v`, #77b `Ru3CzNiyaEQH7YFcr`, #78a `jaEe2jfobfboyaM92`, #78b `ttv3k8b45fXXRynM8`, #81 `Q7Sg7H4dicTALAp8q`, #87 `ZE6K3iQBn8kBnSCdZ`, ledger L4 `r3ghE7qGj75HTnghH`; full `list_lists`+`list_swimlanes` map (4 swimlanes, 29 lists).
- [S26] `.agents/plans/2026/2026-10-dep-wekan-v12-upgrade/RESEARCH.md` (read): chart-pin mechanics, route survival v9.99→v12.64, rules-extras UI/import-JSON-only creation, board-rules-v12.64.json artifact.
- [S27] `.agents/plans/2026/2026-10-cf-90-feat-board-coord-improvements/` DECISIONS + C07 (read): ledger L1-L12 ids, #74/#87 identity pins (get_card-verified 2026-10-31), create_card default_checked degrade on :v87.
- [S28] `.agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/` plan + DECISIONS + C02 (grep-read): card #74 (`jaEe2jfobfboyaM92`) ask covered by C02 silent test-fix routing; OQ6 adjudication.
- [S29] Coder docs (websearch, read 2026-11-01): `schedule start` — "falls back to either the TZ environment variable or /etc/localtime"; templates tour — `coder_agent` `env` block semantics.
- [S30] `wekan/wekan` main `models/users.js` (grep): no timezone/tz field — card dates are browser-local display over UTC storage.
- [S31] repo `.github/workflows/docker-build.yaml` header: `v<run_number>` + branch tag on main/dev push, PR builds never push.
- [S32] repo `.agents/plans/templates/FRICTION.md` L5: "cord appends" typo still present.
- [S33] repo `skills/wekan-api/references/rest-api-overview.md`: grep — no BOARD_COLORS entry.
- [S34] `.rulesync/skills/pipeline-push-pr/SKILL.md` L34-35: draft=unit tier, ready=integration tier contract (cf-90 C05/C06).
- [S35] `.rulesync/skills/pipeline-role-plan/SKILL.md` L22: "group up to 5 S tasks into one chunk".
- [S36] Live env probe 2026-11-01: `$TZ` unset, `/etc/localtime -> Etc/UTC`, `date` UTC, `CODER_WORKSPACE_*` env present.
- [S37] repo `charts/coder/coder-templates/kubernetes/main.tf` L158-165 (coder_agent env block), L471-477 (pod env); hardened twin exists (543 lines).
- [S38] repo grep: system-upgrade-controller manifests in `charts/base/templates/`.
- [S-wekan-mcp-skill] `skills/wekan-mcp/SKILL.md` (loaded content): call-shape rules (by-list projection strip = rule 6), failure-mode playbook (deployed-build-lag law, stale-catalog probe), board-context schema section.
- [S-plugin-locks] repo `.opencode/plugin/pipeline-locks/index.ts` (grep): ISO-UTC + epoch-ms stamp sites.
- [S-gate] repo `scripts/agent-board-coord-gate.sh` L205: epoch-ms fallback.
- [L4] Live card `r3ghE7qGj75HTnghH` "[cf-90 ledger L4] Bump dev-boards wekan-mcp pin to a v102+ build": v102 tools live-probed absent 2026-10-31 on :v87.