# EXPLORE — cf-106 "Coord fixes" (WeKan card #106)

Scout pass by `agent-explore`, 2026-11-03, worktree `cf-106-feat-coord-fixes` (branch `cf-106-feat-coord-fixes`, HEAD `ceb9a86`-line: `ceb9a8ed6`). Every claim below is a path read in this tree or a live read-only probe, stamped. No file outside this folder was touched.

Ask families are numbered as the ticket lists them; each section says what already exists, the exact file, and the gotcha a plan must respect.

---

## 0. Live facts (probed this run; supersedes re-derivation)

`dev-boards` = WeKan MCP `boards` deployment on the dev cluster; image pin `ghcr.io/ownyourio/wekan-mcp:v87` (`services/dev/prod/values.yaml:442`; the two gpu tiers share the same pin at `services/gpu/prod/values.yaml:697,734`). Repo source (`containers/wekan-mcp/wekan_mcp/server.py`) is ahead of that pin — `skills/wekan-mcp/SKILL.md:131` names this failure family ("deployed build lags the repo source"); ledger card L4 / board card #81 (`r3ghE7qGj75HTnghH`, Not Started) tracks the bump.

Confirmed by live `tools/list` earlier in this run (coordinator-reported): 26 tools; `preload_board`, `list_board_dependencies`, `list_card_dependencies`, `set_card_labels`, `create_list`, `create_label` ABSENT. `skills/wekan-mcp/SKILL.md:38-58` documents the 38-tool target surface; `tests/wekan-mcp/tools.sh` pins counts.

Live board reads (my probes, 2026-11-03, `dev-boards`, all read-only):

- Board **AI-Dev** = `TNQJ2BrXenZovngTS`. Swimlanes: `In Process` `jLzy39L7djCRr67SF`, `Backlog` `MoZHQz3C4dSW4Atya`, `Farm` `BkNBQgMLJBvmCgMAQ`, `Planning` `hFgncuRJ8Pkvpt8ki`.
- **In Process** lists: Not Started `XhDyShvuwhGWzWH2z`, Executing `qZ9CLZqCRbv7NQQ6R`, Review `2B6wWGJ8Tetp5QWDJ`, Rework `y9tsvb3AguKWhzCoF` (empty), Finished `DHw56fMKy3qyfudz4`, Test `jNYNdCPPkX8Bs95s4`, Cancelled `52dS3k7Kdk9EB5cJj`. **Backlog**: Inbox `PjEZ39rXBdpNcpncs` (empty). No **Timeout** list exists live (reaper degrade path, see §3).
- **This ticket's card**: #106 "Coord fixes" → `_id` `ZPP55zX4GEfesPbnL`, in **Executing**, all three custom fields null (no slug written for this run yet).
- Custom fields live on the board are **three**, not one: `slug` `RaNeqvh9YoT4bnkZ8` (text), `session` `zZw4PwMoLeodJy3eT` (text, retired in contract, still on the board), `Priority` `fp5vnD5YrA7oAxPiK` (number). The boards skill claims "exactly ONE board-level text field — `slug`" (`.rulesync/skills/boards/SKILL.md:16`); `Priority` is human-owned and outside that claim.
- Slug value shapes on live cards are **mixed**: post-cf-85 combined `[slug](url)` in `slug` only (#96 `iD4WjWQZrCykSe6Aj`, #97 `xJSxCDv3sqqgyHwDq`, #89 `phrhiExtY4B9TAZmg`, #95 `eA8hd82XxaxCcdwye`, #22); pre-flip split (bare slug in `slug`, session URL in `session`) on #77 `gCcXSu3DZd6NEp97v`, #75 `BhukC6WP3t5MfX2Gr`, #85 `DNoEkqdDJ3YJjuwbg`, #66 `Ch2tMQQTbNawW8jjP`, #58 `En98XdBL255NgRpAx` (raw session id, no URL); #69 `y6PxArduWZhjF2Gaq` carries the combined form in **both** fields. So "Fix slug and session linking" is partly a live-data reality, not only a contract bug.
- Lock state live (`tools.pipeline_status`, Code Mode): claims held on pipeline names **`Context`** (card #106, this session's root), **`CICD`** (card #95), **`Local`** (state `failed`, card `rQCRHsLB86Ci6oJki` #89) and **`default`** (state `failed`, card `BywTteyyeSjwqLHFG`); `lastReap: {at:"2026-11-03T15:33:09.192Z", trigger:"timer", reaped:["Local"]}`. `Pipeline:` labels in real use are therefore `Context`, `CICD`, `Local` (+ `default` fallback).

**Correction to a fact handed to this scout.** The launch states `get_checklist` returns items as `{id, finished}` with no item text. Proven false on the deployed build: `dev-boards.get_checklist` on AI-Dev card #106 (`ZPP55zX4GEfesPbnL`, checklist `nSsnX9mXw9gzem4Zs`, 2026-11-03) returned items **with titles** — `Qwen Large` / `Qwen 27b` / `Qwen Flash` / `Local (gpu-ai)`, each `{id, title, finished}`, all `finished:false`. Same shape re-proven on the read tier (`readonly-global-wekan`, board Projects, checklist `kMWb37EoPYCjAdF2p`). The repo projection already carries the title: `containers/wekan-mcp/wekan_mcp/server.py:257-270` (`get_checklist` → `{id,title,items:[{id,title,finished}]}`), documented at `skills/wekan-mcp/references/call-shapes.md:38` and `skills/wekan-api/references/wekan-mcp-ops.md:39-40`. What genuinely carries no item text is `list_checklists` (`{id,title}` only, `server.py:250-253`) and the by-list card projection. Plan/research should treat "checklist item titles unreadable" as **not** a constraint; if a run hit it, the cause is a different call (`list_checklists`, or the cards' `checklistIds` summary) and worth re-probing before designing around it.

Also relevant to §1/§4: `readonly-global-wekan` (gpu `wekan-readonly` tier) is **not** a substitute surface for AI-Dev work — its service user is a member of only the `Projects` board (`TrfngHQf8PWj9mnqC`); it cannot read AI-Dev at all (probed).

---

## 1. Slug + session-link write path (ask: `[slug](link)`, append `\n` + new slug when a different slug exists)

Format spec / writers (all `.rulesync/` sources; `.opencode/skills/…` and `AGENTS.md` are rulesync mirrors — never hand-edit):

- `.rulesync/skills/boards/SKILL.md:16` — one-field roster; legacy `session` retired, never read/written.
- `:129-137` — **Resume vs new run (D11)** parse rule: combined value yields the bracketed text; a legacy bare value yields the slug whole; unset → fresh kickoff.
- `:330-349` — **Post-plan card write-back**: `list_custom_fields` → `set_card_custom_field` (upsert) with `[<slug>](<session link>)`; link half = `$(SESSION_URL_BASE)/?session=<sessionID>`, or the raw session id on `UNRESOLVED`; then `delete_checklist_item` for every unchecked item of the five checklists.
- `:296-298` — research-only cards do the same write-back.
- `:60-75` — Config constants + `SESSION_URL_BASE` runtime resolution (the `Session origin:` line, `scripts/session-origin.sh`); `:68` UNRESOLVED fallback rule.
- Commands carry the origin block: `.rulesync/commands/pipeline-boards.md:13-14`, `pipeline-boards-hourly.md:34-35`, `pipeline-boards-pr.md`.
- Prior ticket: `.agents/plans/2026/2026-10-cf-85-refactor-wekan-slug-session-link/` (plan of record `2026-10-29-cf-85-refactor-wekan-slug-session-link.md`; D11/D12/D13 in `DECISIONS.md`; risks at plan lines 42-47 — the `agent-perms` A15 custom-field roster guard and the `session-origin` s2 byte-pins are the two suites that fence this wording).

Server-side parse (single authority for the combined value):

- `containers/wekan-mcp/wekan_mcp/server.py:1184-1195` `_slug_from_combined_value` — added in cf-96 C01 (`395c89028`), used only by `preload_board`; **it parses the first `[…](…)` only**. A multi-line value (`[old](u1)\n[new](u2)`) parses to `old`, i.e. the newest slug would be lost.
- `set_card_custom_field` (`server.py:849-874`) replaces the field value verbatim (upsert; attach-if-missing whole-array write; archived cards excluded). No append semantics exist server-side — appending is consumer-side read-modify-write.
- Doc row: `skills/wekan-mcp/references/call-shapes.md:65`.
- `preload_board`'s per-card `slug` field is the parsed value (`server.py:1420-1424`).

Gotchas for planning: (a) the append rule touches the boards parse rule (`:129`), the write-back step (`:334-342`), `_slug_from_combined_value`, the `preload_board` docstring/`slug` shape (`server.py:1353-1377`), and `skills/wekan-mcp/references/call-shapes.md`; (b) which line is "the" slug must be decided (last line = newest run fits the D11 `<slug>-1` sequence rule); (c) live cards (§0) already hold split/duplicated values, so resume logic must tolerate them; (d) deploy lag means any wekan-mcp change is repo-only until the `:v87` pin moves (card #81 / L4).

---

## 2. Board-context prefetch — "better preload board" + "better preload cards"

Plugin: `.opencode/plugin/board-context/index.ts` (hand-written, NOT rulesync-generated; AGENTS.md §Agents).

- Fires on `ctx.session.hook("prompt", …)` for `agent-board-coord|-local|-pr` only (`BOARD_COORD_AGENTS`, line 105-113), once per session (`ONCE_TTL_MS` 6 h, line 103), append-only, never throws (header lines 17-23: a throwing prompt hook blocks prompt admission).
- Budget: `FETCH_TIMEOUT_MS = 8_000` (line 71) across the whole board fetch and every MCP call; `DEFAULT_ENABLED = true` (line 99) with the live-fire evidence block (lines 73-98).
- What it fetches (structural only): `list_boards` → `get_board` (labels) → `list_swimlanes` → `list_lists` filtered to **one swimlane** (`SWIMLANE_TITLE = "In Process"`, line 65) → `list_custom_fields` (lines 154-180). **No cards, no checklists, no card ids.**
- Block format: `formatBlock` (lines 119-135) mirrors the schema whose single normative home is `skills/wekan-mcp/SKILL.md:94-124` (`tests/wekan-mcp/skill-surface.sh` t3 keeps code and doc from drifting). The footer explicitly says card and checklist ids are not included.
- MCP transport for plugins: raw JSON-RPC over streamable HTTP (`makeCallTool`, lines 329-367); URL discovered from `ctx.mcp.list()` else parsed from `.opencode/opencode.jsonc` (lines 228-249); credential-free (OIDC disabled on these deployments, `skills/wekan-api/references/wekan-mcp-ops.md`).
- Collector command (the manual twin): `.rulesync/commands/wekan-board-context.md`, run as `agent-board` (`.rulesync/subagents/agent-board.md`).

The preload law the ask runs against: `.rulesync/skills/boards/SKILL.md:274` — "Preload consumer at claim": the **coordinator** calls `preload_board` once at claim; "It is never the hook: the 8 s board-context prompt-hook budget stays structural-only and prefetches no card data (the plan's OQ3 ruling — the hook would race a whole-board export past its admission budget)." Degrade law: probe `tools/list` first; absent **or** failed → per-list `list_cards_in_list` reads, skip the dependency gate, note in RESULT, at most one retry. `tools/list` presence ≠ call success. The same probe law is reused for `set_card_labels`/`default_checked` (`:358`) and the grouped-sibling degrade (`:328`).

What the target preload already gives (repo source, not deployed): `preload_board(board_id)` (`server.py:1353-1466`) returns swimlane→list→cards, dependency lines, `label_names`, `field_names`; each card is exactly `{id, card_number, label_ids, slug, archived, sort, parent_id}` — titles/descriptions deliberately dropped, and **checklists come back empty** because the export `fields=` trim omits them (`?attachments=false&fields=board-header,labels,custom-fields,dependencies,sort`, line 1379-1382; unselected sections return empty arrays, docstring lines 1358-1363). So the ask's "checklists + both card ids in the preload" is a real delta on an already-designed lean shape: `card_number` + `id` are already there; checklists are not, and the export trim is the mechanism to change or supplement.

Other preload-adjacent surfaces: live-fire runbook `scripts/board-preload-probe.sh` (legs LF1-LF7; the only sanctioned session-minting shell grant, §7); unit suites `tests/opencode/board-context.test.ts`, `tests/wekan-mcp/board-context.sh` (note: it nests `tests/agent-board-coord/gate.sh` and exceeds default shell timeouts — cf-96 FRICTION), `tests/board-preload-probe/surface.sh` (B1-B5), `tests/boards-deps/surface.sh`.

---

## 3. Locks — reap → "continue anyway", and several cards on one lock

Single implementation: `.opencode/plugin/pipeline-locks/index.ts` (hand-managed, ~92 KB; the plugin owns `.pipeline/` — agents never read/write it, `boards:152`).

Shape (line numbers from the current file):

- Constants: `LABEL_PREFIX="Pipeline:"`, `DEFAULT_PIPELINE="default"`, `TOOL_NAMES` (53-55); `TICK_PROMPT` (63); runtime dir `.pipeline`, `locks/`, `events.log`, `config.json` (70-73); `CLAIM_KEY_PREFIX`, `CHILD_KEY_PREFIX` (77,147); defaults `timerMs 300000`, `reapEveryMs 600000`, `hookThrottleMs 30000`, `staleMs 7200000` (2 h D21) (90-98); reaper guard `reaper.lock` + `GUARD_STALE_MS 300000` (104-105); reaped files → `locks/.reaped/<name>.<pass-ts>.json` (107-110); board defaults `AI-Dev` / `In Process` / `Timeout` (123); `TIMEOUT_COMMENT`, `REAP_ALERT_TITLE` (127-128); HA notify `admin-global-homeassistant` + `notify.mobile_app_pixel_6` (118,129-130); `MCP_CALL_TIMEOUT_MS 8000` (138); `LOCK_LOST_STOP` text (153); guarded tools `edit`,`write`,`bash` (158).
- Label → lock set: `derivePipelineSet` (231-241), `sanitizePipelineKey` (221-229) — a lock file name is the trimmed `Pipeline:` remainder, filesystem-folded to `[A-Za-z0-9._-]`, 100 chars. **A card id is a legal pipeline key** — `pipelines:[cardId]` already lands `.pipeline/locks/<cardId>.json` (relevant to the "use the card ID as the lock" override; no new file-naming machinery is needed).
- Lock record: `newLockRecord` (355-376) → `{version:1, pipeline, cardId, sessionID, setId, pipelineSet[], state:"live", claimedAt, heartbeatAt, cardTitle?}`; offset-ISO stamps via `localIso` (186). Path `lockPathOf` (384). Atomic tmp+rename + `utimes` (402-428); staleness = `max(heartbeatAt, mtime)` (421-423).
- Claim: `claimLockSet` (509-560) — reap-before-claim (517), **one claim per session** (`already_held`, 525-526), then `acquireSetWithRollback` (474-507) walks the sorted set with `fsx.open(path,"wx")` → **exclusive per pipeline key**; first `EEXIST` rolls back and answers `{ok:false, reason:"locked", pipeline, holder}`. So today: one card per pipeline, and multi-tenant claims are structurally impossible. `releaseLockSet` (575-614) owner-checks the whole set before deleting. `lockStatus` (624-671) groups by `setId` and returns `groups`, `session`, `lastReap`.
- Lock-lost: `checkMember` (673-685) + `handleLockLost` (687-755) — any stolen/missing member kills the whole set, deletes only our files, drops caches; `PIPELINE LOCK LOST` is the stop signal (153). `markSetFailed` (826) writes `state:"failed"` on a failed root (config `releaseOnFailure:false`, D12) — the live `failed` groups in §0 are this path.
- Reaper: `reapStale` (1349-1389) guarded pass → `reapOneLock` (1212), `clearDeadHolders` (1269), `writeReapMeta` (1294), `runReapCardLegs` (1303-1347) which per card runs `moveCardToTimeout` then the HA alert (unless `haNotify:false`). Board leg `moveCardToTimeout` (1426-1470): `get_card` → `list_lists` → `move_card` into the `Timeout` list **in the card's own swimlane** → `add_comment`; with no `Timeout` list live (§0), it skips the move and appends `{at, cardId, setId, pipelines, sessionID, reason}` to `.pipeline/timeouts.jsonl` (`queueTimeoutRow`, 1399-1414) plus the comment (`reapCommentBody`, 1421). Reap triggers: `claim`, `timer` (978-980), `command`, `tick`.
- Tool specs (1541-1602): `pipeline_claim{cardId,pipelines?,cardTitle?}`, `pipeline_release{outcome:done|abandoned}`, `pipeline_heartbeat{}`, `pipeline_status{}`; registered flat, reachable **only** via Code Mode (`tools.pipeline_*`) on v2.1.4 (D29). Command specs (1608-1693): `/pipeline-reap`, `/pipeline-status`, `/pipeline-tick` (reap-then-prompt with `TICK_PROMPT`).
- Config seam: `.pipeline/config.json` only (`loadConfig`, 246-329): `staleMs`, `timerMs`, `reapEveryMs`, `hookThrottleMs`, `releaseOnFailure`, `strictLockLoss`, `haNotify`, `maxWorkers` (reserved/unwired), `board.{boardTitle,swimlaneTitle,timeoutListTitle}`.
- **Nothing implements "continue anyway" after a reap**: no user-facing prompt, no takeover/force argument, no re-claim affordance on the reaped set — the shipped contract is stop-on-`PIPELINE LOCK LOST` and "only a fresh run re-claims" (`boards:157-158`). The whole ask is new surface: plugin signal + skill contract + likely a claim override.
- Multi-card-per-lock likewise inverts two invariants: the `wx` exclusivity (474-507) and the per-session `already_held` guard (525). "Must not start unless the pipeline is empty, user can override" is close to today's `pipeline_status`-then-skip rule (`boards:154`), but the shared-tenancy + timestamp-overwrite expectation is unimplemented and the release/status owner-checks (588, 681) assume a single `sessionID` per file.

Suites: `tests/opencode/pipeline-locks-core.test.ts`, `-engine`, `-reap`, `-tick`, `aislop-pin-parity.test.ts`; `tests/agent-perms/surface.sh` A15 pins the `pipeline_*` tool rows + label constants across plugin ↔ permission rows ↔ boards skill.

---

## 4. No-op marker, archive exit, alerting

Alerts (`.opencode/plugin/question-notify/index.ts`, hand-managed):

- Push channels: question (`PERMISSION_ASK_EVENT`-adjacent question path), finished (`session.execution.succeeded`, line 79), crash (`session.execution.failed`, 80), pending approval after 15 s (`PENDING_NOTIFY_MS`, 77 + `permission.replied` cancel, 82). Titles 97-111. Target `notify.mobile_app_pixel_6` via `admin-global-homeassistant` (68-70). Top-level only (`isTopLevel`, 116-119).
- The one suppression: `noWorkSuppressed` (128-135) — requires `metadata.openchamber.kind === "scheduled"` **and** `metadata.pipelineNoop` with a non-empty string `reason`. Marker shape/authority is the boards skill; the plugin is the reader only (header 40-46). Any malformed shape alerts (fail-loud).

Writer side (`.rulesync/skills/boards/SKILL.md:161-204`):

- Marker contract (161-190): `metadata.pipelineNoop = {at:<epoch-ms>, reason:"no-cards"|"no-claimable-cards"}`, never nested under `openchamber.*`; writer predicate = zero successful `pipeline_claim` AND zero board writes; "Mark ONLY at the two exits citing this subsection — the gate's SKIP/LIVE replies stay unmarked (OQ5)". Recipe: `session_rename` → `opencode api get /api/session/<id>` → merge into the FULL current metadata → `opencode api patch … -d '{"metadata": <merged>}'` with `$(date +%s%3N)`.
- **Archive exit** (192-204): after the marker write, `opencode api patch /api/session/<id> -d '{"archived": true}'`; never asks "should I close out?"; failure still ends cleanly; RESULT stays `NEEDS_INFO`.
- The two marked exits: Card pickup step 5 (`:116-121`, `no-cards`) and the claim-cap stop in Parallel pipeline loops (`:155`, `no-claimable-cards`).

Why a scheduled tick can still alert and still idle in the session list (the ticket's two asks): the hourly command's own stop paths — `GATE: SKIP`, `GATE: LIVE` with filtered-in Executing cards, and the fail-closed board-check stop (`.rulesync/commands/pipeline-boards-hourly.md:20-30`) — are explicitly **unmarked** (OQ5) and never archive; a `GATE: RUN` walk that finds nothing does mark+archive. The gate script `scripts/agent-board-coord-gate.sh` is marker-blind by design (its verdict contract, lines 60-70).

Suites/pins: `tests/noop-marker/surface.sh` (N1 reader conjunction, N2 writer authority + both exits, N3 single-home grep counts + "gate stays marker-blind", N4 scheduler docs truth, N5 RESULT stays NEEDS_INFO, N6 `{"archived": true}` in both no-op ends + never-ask; header lines 1-33), behavior matrix `tests/opencode/question-notify.test.ts` T9/T10 and `permission-ask-notify.test.ts`, live legs `scripts/board-preload-probe.sh` LF4/LF5/LF6.

Reaper alerting is separate (`sendHaReapAlert`, pipeline-locks 1472-1494) and is gated only by `haNotify`.

---

## 5. Scheduled runs — the "single runner that starts a new session with card info preloaded, sets provider/model and agent" ask

Today there is no runner; there are two near-duplicate OpenChamber loop files plus gated commands:

- `.agents/loops/pipeline-worker.md` — frontmatter `name`, `schedule: 0 * * * *`, `enabled: true`, `model: gpu-ai/qwen3.8-flash-next-strata`, `agent: agent-board-coord`; body = the plain-text worker sentence (line 61) identical to `TICK_PROMPT`. Comment block (9-58) records the live OpenChamber state, the fingerprint/approval law, and that slash dispatch from loop text is unproven on v2.1.4 (D30) so `/pipeline-tick` is NOT the body.
- `.agents/loops/pipeline-worker-local.md` — `schedule: 30 * * * *`, same agent, same model, body names the `Provider: Local` filter (line 38).
- Recognized loop frontmatter (cf-90 RESEARCH, `.agents/plans/2026/2026-10-cf-90-feat-board-coord-improvements/RESEARCH.md:77-81`): `name`, `schedule`, `enabled`, `model` (`provider/model` → providerID+modelID), `agent`, `timezone`; the whole file body becomes the prompt; any other key is ignored. **There is no separate `provider:` key** — provider rides the model string. So "set the provider/model as well as agent" is expressible today only as `model: <provider>/<model>` + `agent:`; per-card dynamic provider choice lives coord-side (`boards:139-146` Provider filtering + `pipeline-models`), and the duplication itself is deferred card **L2** ("Dynamic provider/model routing or pipelines", cf-90 plan §Appendix).
- Gated entry: `.rulesync/commands/pipeline-boards-hourly.md` (gate + BOARD CHECK + Session origin block) with the ungated manual twins `pipeline-boards.md`, `pipeline-boards-pr.md`; the plain-family twins `pipeline.md`, `pipeline-pr.md`, `pipeline-resume.md`, `pipeline-resume-pr.md`.
- Gate script: `scripts/agent-board-coord-gate.sh` — verdicts `GATE: RUN|LIVE|SKIP` (60-70), liveness = the three exact board-coord agent names (line 227 jq filter), 15-min freshness / 5-min self-grace defaults (36,42), `opencode api` only, cross-project unscoped on purpose (OQ-A3).
- Card data at launch: only the structural board-context block (§2). Card details come from the coord's own `get_card` at claim; `/wekan-board-context` is the manual collector.
- Existing session-minting precedent (the closest thing to a runner): `scripts/board-preload-probe.sh:294-307` creates a session with `opencode api post /api/session -d '{"title":…,"location":{"directory":…}}'` and prompts it via `opencode run --session … --agent agent-board-coord` (124-141). Grant-wise this exists only as the scoped `bash scripts/board-preload-probe.sh *` row; widening coord to raw `opencode api post` was **explicitly rejected** (A12 api containment, `.rulesync/skills/agents-sync/references/permissions.md:102`, DECISIONS 2026-10-29). Any "runner" plan must pick between a script-wrapped launch and a new grant, and knows the warm-before-move law: `scripts/kickoff-warm-location.sh` + `session_move` (`.rulesync/skills/pipeline-kickoff/SKILL.md:40`) — an unwarmed destination bricks the run.

---

## 6. Model routing — "27b should be Qwen Dense, default over Flash" and "better default to local provider"

Current vocabulary and defaults (sources; mirrors generated):

- `.rulesync/skills/boards/SKILL.md:20` — Model(s) checklist items `Qwen Large | Qwen 27b | Qwen Flash | Local` (gpu-ai), **"Default selection: `Qwen Flash`"**; `default_checked` on `create_card` is the race-free path; the board's createCard rule extras are DORMANT (upstream `checkListId` typo, v12.64→main).
- `:74` — human-owned cutover runbook: the rules-import artifact `.agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/board-rules-v12.65.json` checks ONLY `Model(s)` → `Qwen Flash` (OQ13).
- `:233-241` — consumption rules for a card's Model(s) checks (one checked → both tiers; largest=planning, smallest=code; `Qwen 27b`+`Local` → `gpu-ai/qwen3.8-27b-q4`; Local-only → 27b-q4 everywhere).
- `:380` — friction/ledger cards check `Model(s)` `Qwen Flash`.
- `.rulesync/skills/pipeline-models/SKILL.md` — default tiers table (planning `openrouter/qwen/qwen3.8-2.4t-a95b`, code `openrouter/qwen/qwen3.8-27b`), size order Large > 27b > Flash, local mapping (`gpu-ai/qwen3.8-27b-q4`, `gpu-ai/qwen3.8-flash-next-strata` for Flash+Local), and the favorited-models table. The provider default is **openrouter-first**; the "local provider" default today only arrives via the `Local` checkbox or a `Provider: Local` card label (`boards:146`).
- `.rulesync/skills/pipeline-kickoff/SKILL.md:17-27` — the live picker: the same four options with model ids, and the same size/local derivation.
- Provision engine + skill: `scripts/provision-board.py:70-114` (`"Model(s": {"items": ["Qwen Large","Qwen 27b","Qwen Flash","Local (gpu-ai)"], "checked": ["Qwen Flash"]}`) and `skills/wekan-board-provision/SKILL.md:3,41,122`. Note the boards skill's item list says `Local` while the engine and live board say **`Local (gpu-ai)`** — live `get_checklist` on card #106 confirms `Local (gpu-ai)`.
- Provider catalog: `.opencode/opencode.jsonc` → `providers.gpu-ai.models` (83 entries) has `qwen3.8-27b-q4|-q6|-q8|-q8-1m|-bf16|-q8-visual`, `qwen3.8-flash-next-strata` (+ `-q3/-q4/-orca/-strata-orca`), `local/qwen3.8-27b`, `qwen3.8`; the 27B family is the lab's **dense** family (cf. `charts/llama-swap/tests/TEST_SPEC.md` "dense regime"/"never-two-dense" language and `charts/gpt-researcher/values.yaml:58`). No "Dense" model id exists — the rename is a label/vocabulary change, not a new model.

Suites that will fight the rename (re-pin them deliberately, in the same commit as the wording):

- `tests/pipeline-models/surface.sh:151-153` (four-option picker line must stay), `:219-223` (negative: no `Qwen Flash Next` option), `:313-316` (Model(s) option list + `Default selection: \`Qwen Flash\`` must stay).
- `tests/agent-board-coord/rulesync-surface.sh:647-668` (c11 pins the four options **and** the Qwen Flash default in the generated mirror).
- `tests/wekan-board-provision/*` (`checklist-cutover.sh`, `surface.sh`, fixtures `tests/wekan-board-provision/fixtures/*.json`) pin the `Qwen Flash` default-check in the rule extras.
- `tests/cf90-ledger/readback-runbook.md:47,72` and `tests/cf96-deploy/readback-runbook.md:188` cite the default in runbook text.

Human-owned half: the live board's Model(s) items (§0 shows them still named `Qwen 27b`/`Qwen Flash`) and the createCard rule extras — agents never rename checklists (`boards:56-58`); the sanctioned write leg is the owner-confirmed `/wekan-board-provision` apply. Card #106's Model(s) checklist is entirely unchecked, so this run itself runs the blank default.

---

## 7. Git privileges, coord-as-committer, and "always allow"

Already true (ask 9's first half): the coordinator is the pipeline's sole committer — `.rulesync/skills/pipeline-role-coord/SKILL.md:47-49`; `agent-dev-local`/`agent-dev-pr` carry `git add *`/`git commit *`/`git push*` **deny** rows (`.rulesync/subagents/agent-dev-local.md:128-136`, same for the standalone `dev*.md` trio). Coords carry one broad `git *` allow closed by a pinned deny floor (see `agent-coord-local.md:122-162` and the matrix cell in `.rulesync/skills/agents-sync/references/permissions.md:25`).

The new part: the coord roster does **not** include the standalone `code` agent.

- Roster rows are `action: subagent` whole-value allows in each coord twin: `agent-coord-local.md:331-356` (`*` deny, then `agent-plan`, `agent-test`, `agent-dev-local`, `agent-review`, `agent-research`, `agent-explore`, `agent-dev-deploy`; `-pr` twins swap the dev slot and add `agent-dev-deploy-pr`). Same block in all six coord sources; prose roster in `pipeline-role-coord/SKILL.md:56`.
- `code` (`.rulesync/subagents/code.md`) is `mode: all` with git at **`ask`**: `git checkout*/switch*/commit*/push*` are ask, `git status/log/diff` allow, `shell *` ask (lines 62-95). So "agent-code should have git privs" = a real grant change, and `code` is currently invisible to coords.
- Naming caveat: the ids are `code`, `dev`, `dev-local`, `dev-pr` (standalone) vs `agent-dev-local`/`agent-dev-pr` (pipeline). A bare `agent-dev` names a retired id (`permissions.md:95`).
- Alias law: `agent-coord`/`agent-board-coord` are commit-only twins of the `-local` files; any permission/roster edit must land on the twin in the same commit (`pipeline-role-coord/SKILL.md:51`), and `tests/agent-perms/surface.sh` A12 pins parsed equality across the six sources + mirrors.

"Fix always allow privs" — what it most likely means, grounded:

- The interim posture is OpenChamber's task-level `permissionAutoAccept` ("Always Allow"), a UI-only toggle the loop file cannot express; it enrolls the session before the first prompt and subagents inherit the ancestor's mode (cf-90 RESEARCH:84-90); ledger card **L1** exists to remove the need (cf-90 plan §Appendix). Both loop files document the toggle + fingerprint re-approval law (`.agents/loops/pipeline-worker.md:43-45`, `-local.md:29-31`).
- The reason unconditional approval is currently needed: every pipeline role's shell baseline is `* ask` with a tiny allow list — dev (`agent-dev-local.md:113-145`: git status/diff/log, `ls *`, `helm lint *`, `helm template *`; git writes denied), review (`:47-69`), test (`:77-99`), explore (`:55-68`). So `node --test …`, `bash tests/…`, `rulesync generate`, `npx aislop …` all resolve to **ask**, and "unattended subagents treat ask as effectively blocked" (`permissions.md:8`). Explicit rows for the validation commands (and for `rulesync generate`, which dev is expected to run per cf-85/cf-90/cf-96 chunk files) are the shape an "always allow" fix would take.
- Edit-row facts this ticket will hit: dev allows `edit *` and `.rulesync/rules/**` + `.rulesync/skills/**` + `skills/**`; **ask** on `.rulesync/**` (i.e. `subagents/`, `commands/`), `.opencode/opencode.jsonc`, `skills-lock.json`, `rulesync.jsonc`; **deny** on `AGENTS.md`, `.opencode/agents|commands|skills/**`, `.agents/skills/**`, `.kilo/**`, `tests/**`, `.agents/plans/**` (`agent-dev-local.md:10-81`). `.opencode/plugin/**` has no row → falls under `edit * allow`. Consequence (cf-96 FRICTION, twice-recorded): chunks must name the OWNER of each `tests/**` flip — dev can't write tests; the loop is spec-handup → test session → commit → coord fold.
- Recurring gotcha worth pre-empting: the coord's `git *push*` deny matches the substring `push` inside **path names and commit messages** (cf-96 FRICTION 2026-11-01) — never put `push`/`pipeline-push-pr` in a git command string.
- Hand-managed global array: `.opencode/opencode.jsonc:798-…` (50 rows, universal default `* * ask` leading, `shell * allow` at index 38, `*>*` ask at 39, `skill * allow` last). Agent blocks append after it (last match wins) — see the "global arrays must lead with the default" lesson in the `agents-sync` skill.

---

## 8. Friction follow-up (ask 12's four modes)

- `.rulesync/skills/pipeline-role-coord/SKILL.md:35` — step 11 today: ONE multi-select "Should any of this friction be addressed?", one option per open `FRICTION.md` item; **for every checked item launch a fresh `agent-plan` session** as a new ticket; no items / none checked → stop. There is no "current session", "plan only", or per-mode branch today.
- Board override: `.rulesync/skills/boards/SKILL.md:362-364` — on `agent-board-coord` family runs step 11 is overridden: each checked item becomes a `create_card` in **Inbox** (Backlog swimlane), never an in-session `agent-plan`; checklists come from the createCard rule (never `add_checklist`); check the known answers via `toggle_checklist_item` (currently "typically … Model(s) `Qwen Flash`" — the §6 rename lands here too).
- History: `.agents/plans/2026/2026-10-cf-49-bug-friction-followup-cards/` (the friction-card ticket, its FRICTION line is the origin of the deployed `default_checked` deploy-lag fact); Inbox destination ruling in cf-90 plan §"Deferred-cards ledger"; `tests/cf90-ledger/surface.sh` + `readback-runbook.md` pin the ledger/cards surface.

---

## 9. How machinery tickets write their "Commands" (validation shapes)

No unit-test suite for charts-of-machinery; the repo's shape is offline shell/Node suites + regeneration + greps. Closest models:

- `.agents/plans/2026/2026-11-bug-pipeline-locks-tick-pin/2026-11-02-bug-pipeline-locks-tick-pin.md` (newest, plugin-scope): `node --test 'tests/opencode/*.test.ts'` (quoted glob; gate now exit-0 with zero failures), targeted single-file `node --test tests/opencode/<x>.test.ts`, `bash tests/provider-loops/surface.sh`, scope-guard `bash tests/agent-perms/surface.sh`, pin-parity test, manual grep parity, `npx --yes aislop@0.20.0 scan --changes` one-off, explicit "helm N/A — no chart in blast radius".
- `.agents/plans/2026/2026-10-cf-90-feat-board-coord-improvements/…md` (broadest skill/permission/loop scope): `rulesync generate` twice (second no-op) + `generate --check`; the full battery list (`tests/agent-board-coord/{rulesync-surface,agents-md,gate}.sh`, `tests/noop-marker/`, `tests/session-origin/`, `tests/kickoff-branch/`, `tests/wekan-board-provision/`, `tests/provider-loops/`, `tests/agent-dev-deploy/`, `tests/wekan-mcp/{tools,skill-surface,create-list,board-provisioning,board-context}.sh`, `tests/agent-perms/`, `tests/standalone-agents/`, `tests/coord-inwork/`, `tests/pipeline-models/`, `tests/pipeline-push-pr/`, `tests/board-preload-probe/`); `python3 scripts/provision-board.py --fixture … --dry-run` (both fixtures); `npx aislop ci --changes`; frontmatter YAML validity one-liner; explicit grep-invariant list (run-tag retirement, `{"archived": true}` + never-ask in both no-op exits, provider-filter sentences in both loop files).
- `.agents/plans/2026/2026-10-cf-76-feat-parallel-pipeline-loops/…md`: per-file `node --test` (basenames duplicate — run per directory), surface suites after any `.rulesync/` edit, `npx --yes rulesync@37.0.0 generate --check`, live-fire legs deferred to a chunk checklist.
- `.agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/…md`: one suite per chunk (statics-only, section-windowed greps), delta battery with HOLD/GREEN arms, `python3 -m py_compile`, rulesync ×2 + `--check`, `node --test 'tests/opencode/*.test.ts'`, `npx aislop ci --changes`, surface ⊆ declared file lists, `docker build => no-daemon, CI-deferred` as the designed passing line, live probes marked USER-owned.
- Tooling facts: `helm` at `~/.local/bin` (export PATH first, AGENTS.md); `rulesync` via `npx --yes rulesync@37.0.0` (CI pin `.github/workflows/rulesync.yaml:24`); `aislop` pin parity `.opencode/plugin/aislop-gate/index.ts:32` (`0.20.0`) ↔ `.github/workflows/aislop.yaml`; Node v26 type-stripping runs `tests/opencode/*.test.ts` with no npm deps.

Suite inventory this ticket will most likely touch: `tests/{agent-perms,agent-board-coord,pipeline-models,provider-loops,noop-marker,coord-inwork,boards-deps,cf90-ledger,cf96-coord,cf96-lifecycle,cf96-siblings,cf96-deploy,cf96-tz,wekan-mcp,wekan-board-provision,board-preload-probe,session-origin,kickoff-branch,standalone-agents,agent-explore,agent-dev-deploy,pipeline-gates,pipeline-push-pr,multi-repo,templates}` + `tests/opencode/*.test.ts`.

---

## 10. Known friction not to rediscover (read `FRICTION.md` of these folders)

- `.agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/FRICTION.md`: dev-can't-write-`tests/**` collision (×5, loop = spec → test session → commit → coord fold); `tests/wekan-mcp/board-context.sh` nests `gate.sh` and blows the 300 s shell timeout; the `git *push*` substring trap; per-ticket scope-admits now cost a line in FOUR arms (`agents-md` c7, `rulesync-surface` c8, `gate` t14, `provider-loops`) — the "one admits file" idea is a standing Inbox card; run each HOLD/GREEN arm individually before handoff.
- `.agents/plans/2026/2026-10-cf-90-feat-board-coord-improvements/` (`DECISIONS.md:127`): loop-body edits rotate the OpenChamber `loopApprovals` fingerprint and `reconcileLoopTasks` force-disables a mismatched task — any change to `.agents/loops/*.md` needs a human re-approval note in the plan's runbook.
- `.agents/plans/2026/2026-10-cf-75-bug-wekan-mcp-skill/` and `skills/wekan-mcp/SKILL.md:131`: probe `tools/list`, never trust docs — the deploy lag is the failure family.
- `agents-sync` references (`.rulesync/skills/agents-sync/references/permissions.md` §drift history): permission drift is silent; dead-literal rows (`dev_boards*`, bare `playwright_browser_*`); the `$(date +%s%3N)` subcommand grant; matrix rows move with every block change; run the audit checklist (`permissions.md:78` onward) after any roster/permission edit.

---

## 11. Open questions this scout could not answer repo-side (route to research/plan)

1. Which live behavior failed for "Not archiving scheduled tasks that don't run anything" — the marker+archive recipe never executed by the coord (skill-text compliance), the `opencode api patch … {"archived": true}` call refused or ineffective, or OpenChamber's task UI ignoring the native archive? Repo-side evidence shows the contract exists (`boards:192-204`) and is pinned offline (`tests/noop-marker` N6), and the two `state:"failed"` live claims plus the 15:33Z reap show real reap/stop paths that are *not* marker exits (§4). Deciding which arm is broken needs live session records, not repo reads.
2. Intended semantics of "more than 1 card operating on a single lock": shared co-tenant lock file (one file, N holders, last-writer timestamps) vs a lock keyed by card id under a shared pipeline label group? The plugin today assumes one `sessionID` per file in claim (`wx`), release (588) and lock-lost (`checkMember`, 681) — the choice determines how much of §3 moves.
3. Expected reap "continue anyway" actor: plugin-side question (plugins have no question channel — `question` is an agent tool), or the coord asking after `PIPELINE LOCK LOST` / a Timeout-list comment and then claiming with `pipelines:[cardId]` (mechanically legal today, §3)?
4. Scope of the preload ask vs the standing OQ3 ruling (hook stays structural, 8 s budget, `boards:274`): does the user want the hook to start carrying cards (budget/payload risk, already argued against in cf-96's plan) or the coordinator-side `preload_board` shape extended with checklist state (the export `fields=` trim, §2)? Also whether checklist state per card should ride `preload_board` (currently returns empty checklists by design) or a per-card fan-out.
5. "Qwen Dense": rename the Model(s) item only, or also re-label the picker options and the local/dense mapping strings (`Qwen 27b` → `Qwen Dense` in boards/pipeline-models/pipeline-kickoff/provision engine + live board items via the owner-applied rules artifact)? And does "default over flash" mean the checklist default, the kickoff fallback when nothing is checked, or both (§6 pins both)?
6. Whether the live `Priority` (number) custom field and the legacy `session` field should be declared in the boards skill's "exactly ONE text field" roster (§0 shows three fields live; A15 pins the roster wording).
