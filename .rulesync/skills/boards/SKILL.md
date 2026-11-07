---
name: boards
description: "WeKan AI-Dev board flow for the agent-board-coord pipeline variant — card pickup (a given card id, else the top card walking Rework → Not Started → Low Priority, the one scheduled walk serving both Provider flavors with the card's Provider: label routing models inside the run; candidates additionally skipped by the dependency gate over blocking Red Strings edges), the claim-time `preload_board` consumer with its degrade law, the grouped-sibling flow running a card's blocking-edge companions under one claim, card-driven kickoff where the five standard checklists (Services/Type/Model(s)/Lifecycle/Human in the Loop) and the two custom fields — `slug` (combined `[<slug>](<session link>)` value) and `Priority` (NUMBER, the serving-class kickoff input; model choice still rides the Model(s) checklist) — supply the answers pipeline-kickoff would ask live, the checked-stages-only Lifecycle stage gate with its single-authority Stage map, run-tag-free cf-<cardNumber>- slugs naming every surface, the iterative research-only loop for Research-labelled cards (ending at Review), the card lifecycle with post-plan write-back (Finished stays human-owned), the follow-up-card protocol landing Inbox (Backlog swimlane), the archive-and-never-ask no-cards exit, and the batched question protocol. MUST-loaded by agent-board-coord at run start; load it anywhere else when working the WeKan AI-Dev board card flow."
targets: ["*"]
---

# Boards

Board-driven intake and exit for `agent-board-coord`. The pipeline machinery (plan folders, chunks, gates, RESULT handoffs) is unchanged from `pipeline-conventions` and `pipeline-role-coord`; this skill defines only the board surface — where work comes from, what the card already answers, how a card moves, and how questions reach the user.

## Board facts

- Instance: `https://wekan.spencerslab.com`; board **AI-Dev**; swimlane **In Process**.
- Lists — the board structure is human-owned and DRIFTS; this enumeration is context, never a freeze — resolve list ids live (the board-context block's `lists:` section, else `list_lists`). Captured 2026-11-01, the **In Process** swimlane holds: **Not Started**, **Executing**, **Review**, **Rework**, **Finished** (human acceptance — the agent never moves there, and the dependency gate counts a blocker here as satisfied), **Low Priority** (deprioritised work — picked up last), plus two human-owned non-intake lists the flow READS: **Test** (acceptance-holding — a blocker sitting here also satisfies the dependency gate; never a pickup or grouping source) and **Cancelled** (human shelving — never picked). Pickup walks only **Rework → Not Started → Low Priority**. **Timeout** (reaper destination, still landing via the D22 follow-up card — never a pickup source; its triage is human-owned like **Review**'s; until it exists the reaper degrades per Parallel pipeline loops).
- Board label **Research** marks a research-only card; matched case-insensitively by name. The agent never creates or mutates labels (human-owned). Labels whose name starts with `Pipeline:` mark the pipelines a card blocks on the lease-lock surface (Parallel pipeline loops): the TRIMMED remainder of the label name is one pipeline/lock name, ONE card may carry several, and a card with no such label runs on the single `default` pipeline. `Pipeline:` labels are human-created in the WeKan UI and never agent-created or agent-mutated — the same posture as **Research** (D17/D19). Labels whose name starts with `Repo:` name the owning repo of a card for PICKUP filtering (Card pickup): the TRIMMED remainder of the label name is the owning repo's name, matched case-sensitively on the exact `Repo:` prefix, and a card may carry AT MOST ONE `Repo:` label — one carrying more is claimed by none of its conflicting repos, so the walk skips it and the run records the conflict in its RESULT. A card with NO `Repo:` label at all belongs to the DEFAULT PICKER repo (Repo identity below). `Repo:` labels are human-created in the WeKan UI and never agent-created or agent-mutated — the same posture as `Pipeline:` and **Research** (OQ-A1 COEXIST). `Repo:` is a pickup filter, not a lock: it NEVER contributes to the claim set (Parallel pipeline loops, derivation bullet), while `Pipeline:` keeps its lock meaning unchanged — the two prefixes coexist on one card.
- Custom fields: exactly TWO board-level fields — `slug` (text, carrying the combined `[<slug>](<session link>)` link value) and `Priority` (NUMBER), both resolved by name with `list_custom_fields`. `get_card` is the only value source for `Priority` (`[{id, value}]`); the claim-time `preload_board` per-card dict does NOT carry it, so the value is read from the single `get_card` confirm at kickoff. `Priority` is a serving-class field consumed at kickoff — the D12 carve-out: model choice still rides the Model(s) checklist, so `Priority` modifies how the resolved model is served (the background leg moves engine, never model family) and never picks models otherwise. The legacy `session` field may linger on the live board but is retired: never read, never written (its board-level removal is human-owned). There is no `models` custom field (D12) — model routing rides the Model(s) checklist, never a field. Nor a `pipeline` field — that route was retired with D19: pipeline identity is LABELS, never a field.
- The five standard checklists on every card (future cards via the multi-action createCard rule — imported per the upgrade-ticket runbook — existing cards via backfill; the runbook owns their maintenance):
  - **Services** — the 13 `services/` folders: `backups` `dev` `gpu` `gpu-ai` `grow` `home` `infra` `media` `monitoring` `personal` `proxy-backup` `proxy-local` `proxy-remote`, plus the two non-folder work targets `home-assistant` (the HA instance itself) and `agent context` (the agent/pipeline machinery). Re-derive the folder set live from `ls services/`; the surface test regenerates it from the repo, so drift here fails loudly (D9).
  - **Type** — `feat` | `bug` | `debug` | `dep` | `refactor` | `chore` | `docs`.
  - **Model(s)** — `Qwen Large` | `Qwen Dense` | `Qwen Flash` | `Local` (gpu-ai). Default selection: `Qwen Dense`. How the check lands: agents creating cards pass `default_checked` to `create_card` (race-free by construction); the board's multi-action createCard rule carries the checkItem extras, but they are DORMANT until WeKan fixes the broken checkItem rule action upstream (`checkListId` field typo, present v12.64→main — details in the wekan-v12-upgrade ticket). A card that arrives with the default unchecked routes from the default selection WITHOUT mutating the card (see kickoff).
  - **Lifecycle** — `Exploration` | `Agent Decides Research` | `Pre Research` | `Planning` | `Post Research` | `Test Writing` | `Chunk Development` | `Chunk Review` | `Final Review` | `Deployment` | `Single Session`: the stages THIS card runs, in card order (`Single Session` last, kept by the OQ6 ruling) — only the checked items execute, and the Stage map section below is the single stage→pipeline mapping (coords cite it, never restate it). Nothing checked runs the standard default loop — the Stage map's Blank defaults section names its seven stages; a card picked up for work cannot mean "run no stages". An unchecked Lifecycle checklist is a valid answer, not a gap: it runs that default WITHOUT mutating the card (the createCard rule's checklist extras stay DORMANT until the upstream WeKan fix — see the Model(s) note).
  - **Human in the Loop** — `Exploration` | `Agent Decides Research` | `Pre Research` | `Planning` | `Post Research` | `Test Writing` | `Chunk Development` | `Chunk Review` | `Final Review` | `Deployment` | `Single Session`: the SAME eleven names as Lifecycle — the checklists mirror each other, so a stop point can only name a stage the run's own vocabulary has. The checked items are the active stop points: each one stops the run AFTER that step completes (even if a later stage is skipped). Default: `Final Review` — the run pauses at the whole-plan review hand-off before continuing. The plan-approval pause is separate doctrine and always applies regardless of the checked state (that pause is a pipeline gate, not a card bit — see the Stage map's `Planning` row); the visible check follows the same situation as Model(s).
- Access: the `dev-boards` MCP server — the wekan-mcp tool set (`get_card`, `list_cards_in_list`, `move_card`, `add_comment`, `list_comments`, `list_checklists`, `get_checklist`, `list_custom_fields`, `set_card_custom_field`, `delete_checklist_item`, …), write-capable; it is the agent's single MCP permission (narrow `dev-boards*`, D21 — server-name spelling: MCP tool ids keep the hyphen).
- `dev-boards` authenticates SERVER-SIDE via login-mint: `WEKAN_USERNAME` + `WEKAN_PASSWORD` arrive from the `wekan-mcp` Bitwarden LOGIN item and the instance URL rides that item's URI field (data, not values-config). The agent never handles credentials.
- Tool behavior unclear → load the `wekan-api` skill for WeKan API semantics (on demand, never at run start).
- The board structure (board, swimlane, lists, label, custom fields, checklist rules, bot membership) is a user-owned prerequisite; if it is missing the flow sees an empty board and stops cleanly per Card pickup.

## Stage map — what each checked Lifecycle item runs

The single authority for the Lifecycle consumption; `pipeline-role-coord` and the board-coord bodies cite this table, never restate it. Checked-stages-only: unchecked stages are skipped end to end; nothing checked runs the standard default loop (the Blank defaults subsection below) — never zero stages.

| Stage | What runs |
|---|---|
| `Exploration` | ONE `agent-explore` session — the read-only scout runs BEFORE research and planning; its summary lands in `EXPLORE.md` next to the plan file (the `pipeline-conventions` read order) |
| `Agent Decides Research` | the coord's own research loop per `pipeline-role-coord`'s Research section (cited, never restated here): one `agent-research` session per distinct research ask, serial unless the card carries the human-created `Research: Parallel` label; findings into the shared `RESEARCH.md` |
| `Pre Research` | `agent-research` round BEFORE planning — findings land in `RESEARCH.md` next to the plan file |
| `Planning` | `agent-plan` + the plan-approval gate (the plan-approval pause is a pipeline gate, not a card bit — it always applies regardless of checks) |
| `Post Research` | `agent-research` AFTER planning — findings that change the plan go back for a replan |
| `Test Writing` | the ONE `agent-test` session writing every chunk's tests before implementation |
| `Chunk Development` | the chunk loop's implementation: the coord's `agent-dev-local`/`agent-dev-pr` variant implements, one chunk at a time. With `Chunk Review` also checked the loop alternates dev→review per chunk; with `Chunk Review` unchecked the loop runs DEV-ONLY — a chunk completes on the dev's DONE plus validations-green `commands_run` evidence, judged by the coord from the command list itself (never on the dev's word); the dev still runs every command, determinism mandatory |
| `Chunk Review` | the per-chunk fresh-session `agent-review` step — validations first, then review. Checked-stages-only: unchecked it is SKIPPED end to end (the OQ15 ruling), never silently absorbed into `Chunk Development`'s gate |
| `Final Review` | the whole-plan review — one fresh `agent-review` session over all chunks, on the planning-tier model |
| `Deployment` | the `-pr` variants: push the ticket branch + open the PR per `pipeline-push-pr` (the explicit-user-request rule still governs); the `-local` variants incl. the alias: report "ready — commits local" and stop; merge and ArgoCD sync stay human-owned either way; a checked `Deployment` additionally launches the coord's deploy fixer per `pipeline-role-coord` step 8b — definition-only until first fire |
| `Single Session` | OPT-IN run-shape (never in the blank default; OQ6 keeps it in the checklist): replaces the Test Writing/Chunk Development/Chunk Review run-shape — ONE session of the coord's `agent-dev-local`/`agent-dev-pr` variant implements the whole approved plan (running the plan's Commands itself — no chunk loop, no separate test session, no per-chunk reviews), then ONE final `agent-review`; the other checked stages still run, in card order |

### Blank defaults

A blank checklist is an answer, not a gap, consumed WITHOUT mutating the card. Default when nothing is checked: the Lifecycle stage list is the standard default loop — `Exploration`, `Agent Decides Research`, `Planning`, `Test Writing`, `Chunk Development`, `Chunk Review`, `Final Review` — so every default run starts with the read-only scout (the OQ14 ruling) and closes with the whole-plan review. The blank Human in the Loop default is `Final Review`: the run pauses for the human at that hand-off.

Two members never enter the default stage list: `Deployment` and `Single Session` are OPT-IN, only what an explicitly checked box runs. And the default's `Agent Decides Research` replaces the two named rounds — a blank run leaves research timing to the coord's loop above rather than fixing a round before or after planning; `Pre Research` and `Post Research` appear only when the card checks them.

### Transition — cards still carrying the legacy Research checklist

Until the cutover below lands, the live board still ships the old **Research** checklist (`None` | `Before Planning` | `After Planning` | `Agent Decides`) — this ticket's own card #96 rode this rule at kickoff. A card carrying BOTH the legacy checklist and Lifecycle: Lifecycle wins — the stage list comes from the Lifecycle checks alone. A card carrying only that legacy checklist is consumed with timing-only semantics: its checked items TIME the research around planning and never gate the other stages — Before Planning runs a `Pre Research` round, After Planning runs a `Post Research` round, Agent Decides runs the `Agent Decides Research` stage, None runs no research round. Such a card's stage list is the standard default loop in the new names (the Blank defaults section above) — the legacy checklist carries no stage vocabulary of its own. The same rule maps legacy Human in the Loop checks: Plan → Planning, PR → Deployment, Research → Pre Research (the best-guess mapping stands per this ticket's DECISIONS). The Research board LABEL is untouched by all of this — it stays the only research-only trigger. No Single-Session transition rule is needed: `Single Session` stays in the checklist (the OQ6 ruling kept it) and the v1 8-item cutover never landed on the live board, so no card carries a retired vocabulary to migrate away from.

### Board-side cutover — human-owned, documented, never agent-executed

Aligning the live AI-Dev board with the 11-item design is runbook work, in this order: (1) rename the **Research** checklist to **Lifecycle** and replace its items with the 11 names above, in card order, `Single Session` last; (2) replace the **Human in the Loop** items with the same 11 names; (3) rename the **Model(s)** items to the current four-label vocabulary above and re-check the rule's default-check — until that rename lands, the transition alias in the Card-driven kickoff section is what consumes a live card still carrying the retired dense item name; (4) update the multi-action createCard rule's checklist extras via the current-generation rules-import artifact `.agents/plans/2026/2026-11-cf-106-feat-coord-fixes/board-rules-v12.65-dense.json` — C02 produces it modify-only (never run against the live board by an agent); per the OQ13 ruling it checks ONLY `Model(s)` → `Qwen Dense`, Lifecycle and Human in the Loop arriving unchecked so the blank defaults govern (the cf-96 `board-rules-v12.65.json` it re-issues stays as the applied history); (5) ensure the human-created `Research: Parallel` board label exists (the C08 provision-engine label ensure). Agents never mutate board checklists or rule extras — the existing labels-are-human-owned posture extends to checklists; the owner applies the artifact and the renames POST-BACKUP, backup first, read back after. The one sanctioned agent-executed board-write leg is the `/wekan-board-provision` additive apply the owner directs: `dev-boards` creates the lists, `Bucket:` labels, rule pairs and the Provider/`Research: Parallel` label ensures after the human confirms the dry-run plan (the wekan-board-provision skill's step-3 contract governs; step (5)'s ensure rides it). Until a human lands steps 1–5, the transition rule above keeps old-shaped cards consumable, and no agent may rename anything on the board.

## Config constants

The values the flow writes onto the board. They are a written-onto-the-board contract: copy verbatim, never re-derive or "correct" them — with one exception. `SESSION_URL_BASE` is the single RUNTIME value: D18/D22 (cf-50 round 2) supersede intake-D20's copy-verbatim rule for that constant alone, and the literal intake-D20 shipped has since been proven a dead host (coderd answers it `400` — malformed app-host grammar), so no reader may treat it as valid. Every other constant below — `RESEARCH_LABEL` in particular — keeps the copy-verbatim/never-re-derive posture byte-exact.

- `SESSION_URL_BASE` — THIS run's OpenChamber origin, defined as the launch command's `Session origin:` line value, copied verbatim. That line was produced at command expansion from the running workspace's Coder app-origin env `$VSCODE_PROXY_URI` (`{{port}}` → the `openchamber` app-slug label; host labels lowercased; the agent label KEPT — coderd parses it away for app slugs). coderd renders the env per deployment, so no label-order assumption survives and nothing is re-derived agent-side. Never a remembered, guessed or historically-observed host.
- Two-leg resolution of this run's `Session origin:` slot (D10/D13, ticket 2026-10-bug-session-origin-no-line): **leg 1** — a launch whose board command expanded takes that command's `Session origin:` line, copy-verbatim, canonical. **leg 2** — a launch with no board command expansion (a raw-chat kickoff, or a restart-reinjected leg that carried no line) runs `bash scripts/session-origin.sh` ONCE at claim and treats its emitted line exactly like the command's line: same vocabulary, same recognition set, same lowercased canonical host; the script executes the block's own derivation and probe fragments byte-equivalently (D12). The free-hand ban holds for both legs — block-or-script are the only sanctioned channels, never an ad-hoc env read or hand-run probe. If the script itself cannot run (grant absent or denied, file missing): the slot takes `Session origin: UNRESOLVED (session resolver unavailable)` — a terminal reason. Leg 2's line carries the block's three reason branches plus that token, and every UNRESOLVED — block-emitted, script-emitted, or resolver-unavailable — routes to the raw-id fallback below unchanged (D23 r2).
- Claim-once record (OQ2/D14): at claim the run writes the slot's line value verbatim — resolved base or the UNRESOLVED line — to STATE.json `kickoff.session_origin`; every later leg of the run RE-USES the recorded value instead of re-resolving, including a post-restart re-supplied launch, and only a run that has established none resolves. A no-line launch is never a stall: the sanctioned manual entry is `/pipeline-boards` (its expansion emits the line, leg 1) and a command-less launch runs the identical flow through the script leg (leg 2).
- The block self-probes its derived host before emitting — one `curl -m 5` at expansion; recognized answers `200`/`30x`/`401`/`403`. `Session origin: UNRESOLVED` is defined precisely, three branches: the app-origin env absent (the launch is not Coder-hosted), the template shape unexpected (`{{port}}` missing), or the derived host answered a code outside the recognition set (`400` malformed, `000` = DNS/connect/timeout — e.g. a brand-new gpu workspace whose exact split-horizon DNS record has not landed; the probe degrades that to the fallback below instead of shipping a broken link). Honest limit: the probe proves coderd recognizes the host from the workspace's own DNS view — not the human LAN view, not the authenticated leg (landing observations cover those).
- On `UNRESOLVED` the run PROCEEDS (user ruling 2026-10-25, D23 r2): every would-be link slot gets the RAW session id — claim-comment session line, the `slug` field's link half (`[<slug>](<raw session id>)`), research-only result comment — and the RESULT records the fallback (open_questions/friction). Never silently re-guess a host, and never write a raw id when an origin DOES resolve.
- Session links are exactly `$(SESSION_URL_BASE)/?session=<sessionID>` whenever this run's origin resolves — the `/?session=` form is OpenChamber's own router format (its integrations build the identical URL). Never a raw session id (D13) — that rule governs the resolved branch; the UNRESOLVED branch writes the raw id BY RULE, not by drift.
- Consistency check (the drift check reworded, D23 r2): every link this run writes must equal this run's `Session origin:` value (or the raw-id fallback when it says UNRESOLVED); a mismatch → RESULT flag, never silently re-guess. Historical links are frozen history — card #50's old comments carry the retired literal and its `session` field was re-pointed 2026-10-25 — compare only THIS run's writes. Whichever leg supplied the slot, the comparison baseline is the recorded `kickoff.session_origin` — a later leg re-uses it rather than re-resolving, so cross-leg drift is impossible by construction.
- `RESEARCH_LABEL = Research` — matched case-insensitively.

## Stamps and instants

Displayed stamps follow the workspace `$TZ` with its explicit UTC offset — the no-op session title `no-op <yyyy-mm-ddThh:mm>`, the claim and summary comment stamps, the board-context collection stamp, and STATE.json `updated_at` all render under that one rule (cf-96 OQ4).

- **Instant values are never reformatted**: epoch-ms fields (the no-op marker's `at`, `scripts/agent-board-coord-gate.sh`'s `date +%s%3N` arithmetic), file mtimes, and WeKan's stored card dates are values, not stamps — only a stamp has a zone to render in.
- **A fallback is the same instant, not a different clock**: `$TZ` unresolvable — absent, blank, or a zone the runtime cannot name — writes the UTC `Z` spelling instead of an offset. A workspace nobody has reprovisioned since the coder template gained `TZ` therefore stamps byte-identically to before, and mixed-era records coexist because `Date.parse` resolves either spelling to one instant.
- **Machine-side stamps have one writer**: the plugins format through the single `localIso` helper in `.opencode/plugin/pipeline-locks/index.ts` — lock `claimedAt`/`heartbeatAt`, the audit-JSONL and `timeouts.jsonl` `at`, the reap meta, and board-context's `collectedAt`. A run never rewrites a stamp it only reads, which is why the 2 h staleness window and its `max(heartbeatAt, mtime)` formula carry no comparison-side change (C09 AC2).

## Repo identity

The run's repo name decides which `Repo:` labels this worker picks up. It is the BASENAME of the session's canonical project root — resolved through the sanctioned channel, the PARENT of `git rev-parse --path-format=absolute --git-common-dir` (a main checkout's common dir is its own `<root>/.git`, so the same derivation holds there), never the worktree's own basename — the same `project.canonical` the lock engine anchors on, so every worktree of one repo resolves to the root's name — cross-checked against the repo's own generated `AGENTS.md`, which carries a `Repo identity:` line supplied by that repo's rules source (`.rulesync/rules/overview.md`). Both must agree: no `Repo identity:` line, or a line that does not match the basename → STOP the board-read side and return RESULT `status: NEEDS_INFO` naming the mismatch — never guess a repo name or host (OQ-A2, DECISIONS 2026-10-31). The table keeps all four worker repos in every copy; the default picker is named exactly once, in its row — a ported worker repo copies this body verbatim and flips only the `Repo identity:` line in its own rules source.

`Repo:` label spellings are exact, case-sensitive project directory names (OQ-B2). The owner creates the labels in the WeKan UI — human-owned like `Pipeline:`. The four worker repos:

| `Repo:` label spelling (exact dir name) | Default picker |
|---|---|
| `SpencersLab` | yes — it claims the no-`Repo:`-label cards |
| `HomeAssistant` | no |
| `Home-Assistant-Label-based-Features` | no |
| `brother-ptouch-automation` | no |

Spelling history: card #93's text writes `Home-Assistant-Label-Based-Features` — that capital-B is a mis-cased historical spelling of the LBF directory; the label spelling is the exact lowercase-b dir name in the table above.

## Card pickup

1. Card id given in the launch → `get_card` it; that card is the request.
2. Otherwise walk the lists in order **Rework → Not Started → Low Priority**,
   each list top-to-bottom (`list_cards_in_list` response order IS board
   order) and take the first card found — the highest-sorted card of the
   first non-empty list.
3. Confirm the candidate with `get_card` — the by-list projection omits
   `cardNumber`, custom fields and labels, so pickup facts always come from
   the single-card read.
4. Repo filter (cf-93, OQ-A1 COEXIST) — the candidate is ELIGIBLE for this
   run only when its labels include `Repo:<this run's repo>` (the run's
   repo resolves per Repo identity above), or it carries NO `Repo:` label
   at all AND this repo is the default picker. An ineligible candidate is
   SKIPPED like a contended lock — the walk continues to the next card —
   and repo-mismatch skips consume the same at-most-3 attempts and count
   toward the `no-claimable-cards` no-op reason (no third reason token —
   DECISIONS 2026-10-31). A card carrying more than one `Repo:` label is
   claimed by none of its conflicting repos: skip it the same way and
   record the conflict in the run's RESULT.
5. Nothing anywhere → write the no-op marker with reason `no-cards` (the
   No-op marker subsection; a failed write never delays the end), then
   archive the session per that subsection's Archive exit step — never a
   "should I close out?" question — and report no work, stopping cleanly:
   RESULT `status: NEEDS_INFO`, `open_questions: no cards on the AI-Dev
   board`. Never fabricate a request.

The card description is the request. Claim the card per the Card lifecycle before kickoff.

The walk never visits **Executing** — a card there is owned by the run holding its pipeline lock set, and one session runs one card — nor **Timeout** (reaper destination; its triage is human-owned). On parallel-pipeline runs the candidate is additionally filtered by lock-set availability per Parallel pipeline loops below. A candidate's `Provider:` label routes models inside the run per Provider filtering below — the walk itself applies no provider filter. The step-4 `Repo:` eligibility test is part of the walk itself: it runs after the `get_card` confirm and BEFORE the lock-availability check and any claim.

**Dependency gate — a blocked candidate is skipped.** With the claim-time preload's dependency lines in hand (Board context block section — the consumer rule there), evaluate every walk candidate against them BEFORE its `move_card` to **Executing**: the candidate is SKIPPED when a blocking edge points at it from a card that is neither archived nor sitting in a list titled **Test** or **Finished**. The blocking edge set is EXACTLY the two Red Strings types `blocks` and `is-blocked-by` — `related-to`, `fixes`/`is-fixed-by` and `duplicates`/`is-duplicated-by` never gate pickup. Both spellings mean one thing here, but the board stores only one entry per drawn edge: v12.65 keeps the edge on the card it was drawn FROM and neither the board-wide edge list nor the preload synthesizes an inverse twin — so the gate honors BOTH spellings consumer-side via WeKan's type-inverse map: the house convention's `is-blocked-by` carried by the DEPENDENT toward its blocker, and a `blocks` line pointing at the candidate from a blocker that drew it, are the same relation spelled from either end; a manually drawn edge may arrive as either spelling, and reading only one is the miss the OQ2 both-directions ruling exists to prevent. Test/Finished membership resolves by list TITLE against the runtime id map — the board-context block's `lists:` section, or `list_lists` when no block rode the launch or the blocker's list id is not in the block's map (the block carries only the named swimlane's lists and titles repeat across swimlanes; the preload grouping is id-keyed; its list entries carry no titles) — the plan-time live ids ride the STATE.json claim record for traceability, never this skill. Every reference keys on the card `_id`; `card_number` is display-only identity, never a join key (it re-counters on cross-board moves). A blocker that reads `archived: true` never blocks. On a skip the run releases the held claim with `pipeline_release(outcome:"abandoned")` and walks on — the 3-attempt claim cap still governs; a launch-given card that fails the gate is reported and left, never forced. Every skipped candidate is REPORTED — candidate `_id`, the blocking card's `_id`, and that blocker's list — in the RESULT and in the claim comment of the card the run finally takes, so the walk is auditable. An edge whose far end resolves to no card in the payload (deleted/moved away) is NON-GATING: it never gates, and the relation is never assumed either way — skip it safely and REPORT the edge's endpoint ids like a skipped candidate (claim comment and RESULT).

Resume vs new run (D11) — before minting anything, read the card's `slug` custom field. The field is an append-only STACK of combined `[<slug>](<session link>)` lines, newest LAST (Post-plan card write-back): this run's slug is the bracketed link text of the **last non-empty line**; a legacy bare value yields the slug whole. Mixed live shapes are TOLERATED on read, never rewritten — pre-flip cards hold a split value (bare slug in `slug`, the session link in the retired `session` field) and some carry duplicated combined lines; those stored values are frozen history — the parse rule tolerates them on read and never rewrites them.

- It names an existing feature folder whose `STATE.json` `plan_status` is not
  `complete` → RESUME that run: no kickoff minting, no new slug — continue
  the chunk loop where it stopped.
- The run it names is `complete` (card re-picked, e.g. sent back to Rework)
  → start a new sequential run `<slug>-1`; each further completed re-pick
  continues the sequence `<slug>-2`, …. The sequence keys on the stack's
  NEWEST (last) line: a card whose newest line names a `complete` run
  follows this rule even when older lines name earlier runs.
- Unset, or no matching folder → fresh kickoff.

### Provider filtering — one scheduled walk, per-card routing by Provider label

OpenChamber's scheduled tasks have no label filter — and there is one scheduled walk, not two: the single loop task serves both Provider flavors, and the card's `Provider: API` / `Provider: Local` label routes models inside the run rather than filtering pickups. A `Provider: Local` card and an unlabeled card are both eligible to the one walk; the label sets the provider, it never gates eligibility. The label is resolved exactly like the `Pipeline:` derivation — `get_card`'s `label_ids` against `get_board`'s labels, the single-card read being the source (the by-list projection strips labels; the board-context block's `labels:` section carries these labels automatically — new labels ride it with no code change). The Provider label never locks: the lock identity stays the `Pipeline:` derivation alone.

- **One task, both flavors** — the single scheduled walk takes `Provider: API` cards, `Provider: Local` cards and unlabeled cards alike: it is the steady-state taker of the unlabeled pool, the pickup intent the final-approval round planned (not a lock race).
- **Ask on the unlabeled card** — a run that takes an unlabeled card MUST ask the user which provider applies — ONE question in the kickoff round, before consuming the Model(s) checklist or any provider routing — and request the user apply the matching `Provider:` label. The question's option list leads with `Local` as the RECOMMENDED first answer (the self-hosted provider is the routing default in `pipeline-models`), with `API` as the explicit hosted choice. That ask is the only place a human learns a card needs a `Provider:` label — it is never weakened. Labels stay human-owned (D17/D19): the agent never creates or mutates them, so the ask ends with the human labeling. A scheduled run holding the claim waits on the answer (question-notify pushes the ask) — the accepted steady-state trade-off. A manual run — a launch naming a card id — takes its card even unlabeled, and it asks under this rule too.
- **Routing, once the provider is set** — a run with `Provider: Local` (or an unlabeled card answered `Local`) routes EVERY tier through the `pipeline-models` local mapping (treat the Model(s) checklist as `Local`-checked); a run with `Provider: API` routes from the checklist as today — and "as today" covers a blank checklist too, so a `Provider:` label never rewrites the standard default selection (`Qwen Dense`, resolved by `pipeline-models`): the labels add the `Local` treatment or withhold it, they never pick the model. `pipeline-models` stays the size-and-mapping authority — cite it, never restate its table.

## Parallel pipeline loops

The worker iteration one hourly tick drives — C06's tick prompt names exactly this section: run exactly one Parallel pipeline loops iteration, first `pipeline_status`, then follow the skill. One session, one card, one iteration; the card-driven kickoff, Stage map and RESULT machinery all run unchanged underneath it.

- **Transport (D29/D34).** The four lock tools — `pipeline_claim`, `pipeline_release`, `pipeline_heartbeat`, `pipeline_status` — are plugin tools. On v2.1.4 they are reachable ONLY through Code Mode: call `tools.pipeline_claim` etc. from inside `execute` (flat registry ids). They never appear in the native provider tool snapshot, so nothing here relies on the family's per-tool permission rows — those rows are inert future-proofing and the operative grant is the `execute` allow. The `.pipeline/` runtime dir is plugin-owned: agents never read, write, or delete its files — the four tools are the only surface.
- **Derive the pipeline set from the card's labels (D17).** `get_card` the candidate → its `label_ids`; resolve names through `get_board`'s labels (the by-list projection strips labels — the single-card read is the source). Every label whose name starts with `Pipeline:` contributes its TRIMMED remainder as one lock name (matching is case-sensitive on the exact `Pipeline:` prefix; an empty remainder is ignored; duplicates dedupe). NO matching label ⇒ the single `default` pipeline. The claim input is (cardId + derived set) — never a typed pipeline id, never a hand-typed set. Cards carrying `Pipeline:<track>` labels derive that track; unlabelled cards derive `default`. A `Repo:` label NEVER contributes to this set: the claim input derives from `Pipeline:` labels only — `Repo:` is a pickup filter, not a lock (OQ-A1 COEXIST; DECISIONS 2026-10-31 — the locks are already per-repo by each canonical root's `.pipeline/locks/`, so no cross-repo lock name is needed).
- **Pick per lock availability.** Call `pipeline_status` first — cheap, and it proves the plugin is alive in this session. Then run the existing pickup walk (Rework → Not Started → Low Priority, top first; the step-4 `Repo:` eligibility is already applied in the walk) but SKIP a candidate whose ENTIRE derived set is not free: a pipeline key with live foreign holders is busy, and the claim answers `ok:false reason:"occupied"` naming them. Never pick or restart a card in **Executing**; never pick from **Timeout**.
- **Claim before anything else.** `pipeline_claim(cardId, pipelines, cardTitle)` is all-or-nothing over the derived set and MUST precede the `move_card` to **Executing** and the claim comment — no board move and no code edit happens on an unclaimed card. An `ok:false reason:"occupied"` answer names the live holders (card, session, idle age): move to the next candidate, at most 3 claim attempts per session, then write the no-op marker with reason `no-claimable-cards` (No-op marker — a failed write never delays the end), archive the session per its Archive exit step, report "no eligible work" and end the session cleanly. The claim comment records the DERIVED PIPELINE SET alongside the session line — a typo'd label silently falls back to `default`, so the set rides on the card to keep label drift visible (plan Risks). The comment names this run's repo the same way, and every repo-mismatch skip is recorded in the run's RESULT — a card parked by a typo'd or missing `Repo:` label stays as visible as a drifted lock set (cf-93).
- **Co-tenancy is the human's call, never the run's (cf-106 C08).** The emptiness rule is the engine's answer, not a guess this walk makes: free means no live holders, and `pipeline_status` plus the `reason:"occupied"` holder list are the only authorities on it. When — and only when — the human tells this run to share a named pipeline with a named run, pass `shared: true` on THAT one `pipeline_claim`: it appends this claim's holder to a key that already has live foreign holders instead of refusing the claim. The override is per claim: never a config knob, never inherited by the next card, and it widens only WHO may hold a pipeline — never one session's claim count, so one session still holds one card and the one-claim-per-root guard still refuses a second claim by this run. A shared claim is all-or-nothing and owner-checked exactly like an exclusive one, and when sharing lands the claim comment names the co-tenants this run agreed to run beside.
- **Holders, not files (cf-106 C08).** On a shared key each run holds its own entry: its own beats keep its own holder fresh, and a beat never rewrites a co-tenant's stamps. The reaper prunes only the silent holder — a file moves to **Timeout**-handling only when its LAST holder goes stale, and a pruned holder's card legs and alert never name the co-tenant that kept holding. A release removes only THIS card's holder and leaves the file (and the co-tenant's hold) in place — never release a co-tenant's hold. Sharing means both runs write the same lock file, so a co-tenant's beat overwrites the file-level timestamp (last-writer-wins): accepted, because every holder carries its own claimedAt/heartbeatAt and staleness reads those.
- **Heartbeats are automatic.** The engine beats the claimed set on root and subagent activity; `pipeline_heartbeat` only force-beats every lock file of the calling session's root claim — not a routine duty.
- **Human stops (D20/D21).** The stale clock (2 h) keeps ticking through every stop point — the plan-approval pause is no exception. An answer inside the window resumes ordinary heartbeats and the lock is fine; past it the reaper reaps the set — the card moves to **Timeout** with a Home Assistant alert, or, until the D22 follow-up card lands a deterministic list-creation tool, queues `.pipeline/timeouts.jsonl` plus a card comment: that degrade is the shipped interim, never a failure. **PIPELINE LOCK LOST** from any tool answer or hook: stop the step, then exactly ONE sanctioned question in this run — "may I continue anyway?"; the answer gates the resume. On yes: re-claim with `pipeline_claim(cardId, pipelines:[<cardId>])` (the card-id lock — a key no other run contends), keep the card where it is (**Executing**, or **Timeout** — the run asks before any move out of **Timeout**; that move is the owner's call), append a comment naming the takeover and the lock key, and record the takeover in STATE.json `kickoff.claim` (the lock set it now runs under). On no or silence: the blocked/abandoned exit — never a silent resume, never a second question. No release-at-stop; a re-picked card stays a fresh claim under the normal Resume-vs-new-run rule.
- **Exit.** Card to **Review** + summary comment → `pipeline_release(outcome:"done")` — the Review hand-off IS the release point (D6); **Finished** is human-owned and never touches the lock. Takeover (the human-gated branch, after a reap's **PIPELINE LOCK LOST**): continue anyway only after the one sanctioned question — the resume runs under the card-id lock, not the reaped pipeline label. A blocked card: `add_comment` with the reason, then `pipeline_release(outcome:"abandoned")` — or keep the lock and let it go stale (prefer abandon-release when the card should stay re-pickable for another run, keep-and-stale when THIS run may resume). **PIPELINE LOCK LOST** from any tool answer or hook: stop immediately — no commit, no card move; the sanctioned recovery is the one question above, else only a fresh run re-claims.
- **Board-side prerequisites — human-owned, never agent-executed (cf-76).** (1) `Pipeline:<name>` labels are created in the WeKan UI as parallel tracks are wanted; until then every card runs the single `default` pipeline. (2) The **Timeout** list lands via the coordinator-created follow-up card requesting a `create_list` tool for the wekan-mcp surface; until it does, the reaper degrades as above and nothing else is needed. Lists, checklists, labels and rules stay human-owned: this flow only READS labels (`get_card` + `get_board` are the sole board calls the lock surface adds) and mutates nothing — the agent-facing custom-field roster above stays `slug` alone.

### No-op marker (alert suppression)

A run that ends without ever claiming marks its OWN session record so the
finished push can stay quiet on scheduled ticks: top-level `metadata.pipelineNoop =
{ at: <epoch-ms>, reason: "no-cards" | "no-claimable-cards" | "gate-skip" |
"gate-live" | "board-check-unavailable" }` — never nested under `openchamber.*`
(the app owns that namespace; the run only reads `openchamber.kind` there).
Exactly five marked exits cite this subsection and run it: the Card pickup
step-5 empty walk (reason `no-cards`), the Parallel-pipeline-loops claim-cap
stop (reason `no-claimable-cards`), and the three tick stops the hourly gate
reaches — a `GATE: SKIP` verdict (reason `gate-skip`), a `GATE: LIVE` verdict
with a filtered-in card (reason `gate-live`), and a board check that failed
closed (reason `board-check-unavailable`). Writer predicate, conjunctive:
ZERO successful `pipeline_claim` (a `locked`/`ok:false` answer is not a claim;
a held lock means work — never mark, the alert stays) AND zero board writes.
Recipe — the whole-metadata mandate of the `pipeline-kickoff` in-work mark
applies verbatim (citation only: PATCH replaces `metadata` whole, so
read-merge-write or the siblings the reader and OpenChamber depend on die);
self-identify with the sessionID your `session_rename` returns — a no-op exit
renamed nothing yet, so rename to `no-op <yyyy-mm-ddThh:mm>`: the
current-session form answers the id and the title is the human breadcrumb
(OQ3). Then `opencode api get /api/session/<id>` → unwrap the `{"data": …}`
envelope → merge the marker into the CURRENT FULL metadata →
`opencode api patch /api/session/<id> -d '{"metadata": <merged>}'`, epoch
inline via `$(date +%s%3N)`. Any leg failing → end cleanly anyway: no marker
means the alert stands (fail-loud), never a retry loop, never a stall. RESULT
posture is unchanged — no-op ends still report `status: NEEDS_INFO` and stop
cleanly; the marker write or its failure rides in `commands_run`.

The gate SCRIPT stays marker-blind — it prints a verdict and touches no
session; the RUN that reads a SKIP / LIVE-with-filtered-in-cards /
board-check-failed verdict is what marks and archives before ending (OQ5,
reconciled). Suppression is the READER's conjunction (question-notify): the
record's OpenChamber launch kind must be the scheduled one, so a marked manual
run keeps alerting — there the marker is forensic evidence, not a mute button
(OQ4). Well-formedness is a non-empty string `reason`; `at` is the audit
stamp, never a gate (OQ2).

Archive exit — a no-op end does not idle in the session list: once the
marker write is attempted, all five no-op exits above continue with the same
session record — `opencode api patch /api/session/<id> -d '{"archived": true}'`
— OpenCode's native archive, the very route OpenChamber's own archive sends
(live-verified), on the sessionID the no-op rename already returned. The
PATCH is a NEW step AFTER the marker recipe, never a rewrite of it: the
marker write stays first, the archive a single-key PATCH on its own. A no-op
end NEVER asks "should I close out?" or any variant of it — it writes the
marker, archives, and stops. Any PATCH failure → end cleanly anyway and
record the failure in `commands_run` — the marker's own failure posture:
fail-loud, never a retry loop, never a stall. The archive is an exit-side
write, never a RESULT-status change — `status: NEEDS_INFO` stands. Marker
and archive are session-API writes on the run's own record, not board
writes — the tick-stop exits run them under their no-board-writes bans.

Honest limit — a run that dies before reaching an exit (a malformed model
turn, a missing MCP surface, a crash) cannot mark itself: with no turn left
to run the recipe, its alert and its idle row stand, accepted for this
ticket (the audit's `abnormal-end` / `mcp-surface-absent` rows). The mute
stays that narrow: the no-work mute reaches only the finished push of a
scheduled launch — a crash push is never suppressed, and the pipeline-locks
reap alert stays as-is, gated only by `haNotify` (owner's answer 13). The
candidate close-out is engine-side — the `pipeline-locks` plugin knows which
roots never claimed, and `question-notify` already reads the session record
— and the mechanism it needs is proven, not assumed: the v2.1.4 plugin
context carries `ctx.session.update`, a typed session write whose input
accepts `metadata` and `archived` in one call, so a plugin may write and
archive session records from inside the server process; the read it would
pair with is the same `ctx.session.get` `question-notify` already uses live.
The engine-side marker is therefore shippable as a separate, small,
DECISIONS-ruled addition — it is not this wording's file, so until it lands
the limit stands.

## Card-driven kickoff — replaces pipeline-kickoff Q1–Q2 for board runs

For card-driven runs this section REPLACES the live `pipeline-kickoff` questions (type, models, slug) and feeds `pipeline-models` routing from the card instead of a live question. `pipeline-kickoff` and `pipeline-models` stay byte-identical and authoritative for `agent-coord`; the override lives here, not in their files (D1).

Checked checklist items and set custom fields ARE the user's answers: consume them, do not re-ask what the card answers; only genuine gaps join the batched round.

- **type** — the checked Type item; none checked → the question joins the
  batched round.
- **models** — the sole routing input is the checked Model(s) items (D12).
  Default first: if NO item is checked (a card created outside the
  multi-action rule's reach), route from the standard default selection —
  `Qwen Dense` on the local provider — WITHOUT mutating the card. Then: exactly one checked →
  that model for every tier; several checked →
  the largest drives planning (plan / research / final review), the smallest
  drives code (test / dev / chunk review). The combos are routes, not
  options: `Qwen Flash` + `Local` checked together → assume it's Qwen Flash
  Next, `gpu-ai/qwen3.8-flash-next-strata` (Strata default; other flash-next quants
  only on explicit request); `Qwen Dense` + `Local` → `gpu-ai/qwen3.8-27b-q4`
  unless another quant is explicitly requested; only **Local** checked →
  `gpu-ai/qwen3.8-27b-q4` for every role. Transition alias (temporary): a
  live card whose Model(s) checklist still names the dense item `Qwen 27b`
  is consumed as `Qwen Dense`, while a card carrying `Qwen Flash` keeps its
  meaning; the alias exists only until the owner renames the live checklist
  (the Board-side cutover step above — USER-owned), retires with that
  rename, and never touches a provider-catalog model id. The size order and the local
  mapping authority stay in `pipeline-models` — reference it, never
  duplicate its table. Record the resolved tiers in STATE.json
  `kickoff.models` and in the claim comment — never as a custom field.
- **priority** — the `Priority` custom field's value (string→int
   coercion; `null`/absent = the default class) joins the card-provided
   answers; the resolved CLASS is recorded in STATE.json
   `kickoff.priority {raw, class}` and in the claim comment alongside
   `kickoff.models` — the class table's single authority is
   `pipeline-models`, referenced, never duplicated. The board field
   itself is NEVER written back by agents: it is input-only, and the
   post-plan write-back stays slug-only.
- **human-in-the-loop** — the checked Human in the Loop items are THIS
  run's stop stages: each checked item stops the run AFTER that step
  completes (even if a later stage is skipped) and waits for human input
  before continuing. A card still carrying the legacy HITL items follows
  the transition mapping (Plan → Planning, PR → Deployment,
  Research → Pre Research). Nothing checked = route from the default
  (`Final Review`) WITHOUT mutating the card — and the plan-approval
  pause still happens whatever the checks: it is a pipeline gate, not a
  card bit (the Stage map's `Planning` row).
- **lifecycle** — the checked Lifecycle items are THIS run's stage list;
  what each stage runs is the Stage map's table alone (cite it, never
  restate). Nothing checked = the standard default loop (the Stage map's
  Blank defaults section). A card still carrying the legacy Research
  checklist follows the transition rule instead — its items time research
  only, they never gate stages.
- **slug** — the `slug` custom field if already set (parsed per Resume vs
  new run: the bracketed text of the stack's last non-empty line);
  otherwise derive
  `cf-<cardNumber>-<type>-<desc>` from the card's own content (`cardNumber`
  comes from `get_card`, the type from the checked Type item, the desc from
  the card title). A slug derived from card content is auto-accepted — it
  never joins the batched round for confirmation; only a slug that cannot be
  derived from card content (an unchecked Type leaves it incomplete) goes to
  the round. EVERY surface is named from the full slug (D10): feature folder
  `2026-10-<cf-slug>`, worktree `<cf-slug>`, branch `<cf-slug>`, and
  `session_rename` to `<cf-slug>`. The branch named there is minted by
  kickoff's `kickoff-mint-branch.sh` step — citation only; the mechanics
  live in `pipeline-kickoff`, never here.
- **In-work mark** — after the `session_rename` returns the sessionID, mark
  the session in-work per `pipeline-kickoff` (citation only — the contract,
  its values and its commands live there, never here).
- **No run tag** — run tags are retired for every flavor (cf-90): the
  card-driven and the live-kickoff families mint the run's surfaces from the
  bare slug alike, and the mint mechanics live in `pipeline-kickoff` —
  citation only, never restated here. STATE.json `kickoff` carries `card`
  (the id) + `slug` + `session_origin` (the claim-once slot record — Config
  constants) + (board runs) `priority: {raw, class}` (the `Priority` value and its resolved class — the Card-driven kickoff priority bullet) and omits/nulls `run_tag`.

## Board context block (consumer side)

A launch prompt may carry a pre-collected Board context block — the board's structural ids plus a per-list snapshot of its cards, resolved on the live board before the run started. Its producer is the `/wekan-board-context` collector command (the board-coord prompt hook ships the same block on the first prompt of a board-coord session); the format's single normative home is the `wekan-mcp` skill's schema section — cite it, never restate it here. Consumer rule, for the whole run:

- Block present → use its ids for the whole run without re-running the resolution calls, and read the per-list `cards:` group as the pickup walk's starting map: `card_number`/`card_id`/`labels` per card, exactly as the schema fences them.
- The cards are a collection-time snapshot: drift between the stamp and the live board (a card moved, a list renamed) is absorbed by the walk's `get_card` confirmation and the claim-before-move, and a block whose cards contradict the board re-resolves like any id-shaped error below.
- At claim the coordinator records the block as STATE.json `kickoff.board_context` (alongside `card`, `slug`, `session_origin`).
- Block absent → normal, not a gap: resolve ids top-down exactly as before.
- Any id-shaped call error (404, not-found, or an empty projection where the block's ids promised data) → re-resolve the block against the live board before retrying, and note the drift in RESULT. The board structure is human-owned and drifts, so the block is a starting context, never a freeze — the schema's own re-resolve footer binds here too.

**Preload consumer at claim.** The call site is the coordinator at claim — once `pipeline_claim` succeeds for this run's card it calls `preload_board` exactly ONCE and spends nothing else on board reads the payload already answers. It is never the hook's leg: the prompt hook's sixth (preload) leg ships the same whole-board export at launch as the block's per-list `cards:` snapshot, while this claim-time call stays the run's own exactly-once board-wide read — the two are separate surfaces, each spent once, and the claim-time payload is what the rest of the walk keys off. The one map serves the rest of the pickup walk — the dependency-gate evaluations, the Provider/`Pipeline:` label derivations for later candidates (each card's `label_ids` against the payload's `label_names` map, no per-candidate `get_card`+`get_board` pair), and the resume-vs-new-run slug check (the preload carries the parsed `slug`). Every swimlane and list entry carries its `title` beside its `id`, so the Test/Finished/Timeout membership tests read the payload instead of a `list_lists` round-trip, and the optional `swimlane_titles` argument bounds the read to the swimlanes a run names (default: every swimlane; a title matching nothing answers an empty grouping, never an error — and an empty grouping from a FILTERED read is a title miss to re-check against the board, never a read on an empty board, while an empty grouping from the unfiltered read means the board really carries no cards: a broken export RAISES, so an answered payload is never an outage wearing an empty shape). Each card also carries `checklists` — `[{id, title, items: [{title, finished}]}]`, already filtered to the kickoff vocabulary: the five standard checklists plus the legacy `Research` stand-in and a legacy 8-item Lifecycle spelling — so for a CANDIDATE the kickoff checklist consumption and the legacy-vs-Lifecycle checklist detection read off the preload, with no `list_checklists`/`get_checklist` fan-out and no per-card guess about which checklist generation a card carries — the legacy-Lifecycle recognition is a documented item-count heuristic (an 8-item list whose title is not one of the current names), so an off-vocabulary legacy list can still surface through the consumer's own read. The per-card `get_card` confirmation step stays for the CLAIMED card only — its description and custom fields are single-card reads the preload deliberately does not carry; its checklist state is not one of them, it rides `checklists`. From the preload the run records a LEAN stamp — `{preload: {at, tool, cards, degraded}}` — inside that same STATE.json `kickoff` record the block above is written to; the full card map is NOT persisted to STATE.json. Degrade law (the cf-96 family rule): probe `tools/list` first; while the deployed build predates the C10 pin bump, `preload_board` is ABSENT there — the run then keeps today's per-list `list_cards_in_list` reads, SKIPS the dependency gate, and notes the skip in RESULT; never a hard failure, never a stall. A PRESENT-but-failed call degrades exactly like absence: a `preload_board` call that FAILS — export disabled site-wide, an admin-only-custom-fields 403, an outage, a truncated stream — gets the same per-list reads, the same skipped gate, the same RESULT note, and at most ONE retry (the read is idempotent); never a hard failure, never a stall. `tools/list` PRESENCE is not call-successfulness.

**Card details at claim — a TOOL hook, not the prompt hook.** Once `pipeline_claim` succeeds for this run's card, the claim answer can carry a card details block: the board-context plugin watches the claim through a tool hook with its own latency budget and appends the block, which it produces by calling `get_card_details` for the claimed card. This is deliberately not the prompt prefetch — the prompt block is board-scoped (structure plus the per-list cards snapshot) inside its 8 s admission budget, and the card is only known after the claim, so the claim answer is the one place a card-scoped block can land. The format's single normative home is the `wekan-mcp` skill's Card details block section — cite it, never restate it here.

What the block replaces for the CLAIMED card: the `get_card` + `list_checklists`/`get_checklist` fan-out and the separate dependency read. It carries the description, the labels named, the custom-field values raw, EVERY checklist the card carries with its items in stored order and tick state — all of them, not the kickoff vocabulary, which is what makes a follow-up card's inherited Lifecycle answers readable without touching the parent — the card's own dependency lines, and the `slug` field both ways: `slug_stack` (oldest first) and `current_slug` (newest), so the resume-vs-new-run check reads the stack off the block instead of a further round-trip.

Consumer rule and degrade law (the same cf-96 family rule as the preload above): a block on the claim answer is read, never re-derived; NO block is normal — the leg is new, the deployed build may predate `get_card_details`, and the hook may not fire — and the run then calls `get_card_details` itself, once, for the claimed card, after probing `tools/list`. Tool absent or call failed ⇒ degrade to today's reads: `get_card` plus the `list_checklists`/`get_checklist` fan-out and the dependency read, at most ONE retry, the degrade noted in RESULT. Never a hard failure, never a stall, never a card move. The block is working context, not state: nothing of it is persisted to STATE.json beyond the lean `{card_details: {at, tool, degraded}}` stamp in the same `kickoff` record the preload stamp sits in.

## Research-only cards — iterative loop

Trigger: the card's labels include the **Research** board label — read board labels via `get_board` and the card's label ids via `get_card`, matched case-insensitively. The label is the ONLY trigger (D14); the Lifecycle checklist never fires this flow — its Pre/Post Research items are stages of normal cards (a legacy-Research card per the transition rule behaves the same: its checklist only times research, it never marks a card research-only).

Research-only cards never go to `agent-plan`/`agent-test`/`agent-dev-local`/`agent-dev-pr`/`agent-review`. The run:

1. Claim per the Card lifecycle (`move_card` to **Executing** + claim
   comment), then resolve the feature folder exactly as in Card-driven
   kickoff: `cf-<cardNumber>-<type>-<desc>`. No `feat` default for an unset
   Type — it joins the round-2 questions.
2. `agent-research` ROUND 1 — launch with the card request, the checked
   Lifecycle research items (`Pre Research` / `Post Research`), and the
   absolute feature-folder path; the summary lands in `RESEARCH.md` there.
3. ONE batched `question` round for the user: refine/direct further
   research — carry every open question from RESEARCH.md.
4. Further research on the answers — continue the SAME `agent-research`
   session via its sessionID so the round-1 context carries.
5. Terminate: the default is at most one follow-up round, then wrap.
   Residual unknowns ride along in the final comment for the human's
   Finished-vs-Rework call — do not spin a second round.
6. Write-back exactly as in Post-plan card write-back (D19): the `slug`
   stack read-modify-write of its step 2 — this run's combined
   `[<slug>](<session link>)` line appended per that rule, never a blind
   overwrite — then
   `delete_checklist_item` for every unchecked item of the five checklists.
7. `add_comment` on the card: the research session link — this run's
   `Session origin:` URL, or the RAW session id on UNRESOLVED with the
   fallback recorded in RESULT — plus the merged TLDR
   from RESEARCH.md → `move_card` to **Review** — the agent's
   final destination for research-only runs too; **Finished** stays
   human-owned.

## Card lifecycle

**Review** is the agent's final destination; **Finished** is human-owned.

- **Pickup** → `move_card` to **Executing** + `add_comment` claiming the card: the session line — this run's `Session origin:` link, or the RAW session id when it says UNRESOLVED (fallback recorded in RESULT) — the resolved model tiers (from the Model(s) checklist), the consumed checklist answers, the resolved slug, and the plan folder path.
- **Lock set before the move** — every entry path (a tick, a manual `/pipeline-boards` with a card id, or one without) calls `pipeline_claim` for the card's derived pipeline set BEFORE that `move_card` to **Executing** and the claim comment (Parallel pipeline loops). A manually-addressed card whose set is not fully free is reported and left — never forced.
- **Plan approved** (after the question round) → `add_comment` that the plan is approved (plan path, worktree/branch), then the Post-plan card write-back below.
- **Each chunk done** → `add_comment` with the chunk status (chunk id, dev/review verdict, commit).
- **All chunks done + final whole-plan review passed** → `move_card` to **Review** + summary comment: branch, commit range, validation results, plan path; once the comment lands, `pipeline_release(outcome:"done")` hands the lock set back (D6 — **Review** is the release point, **Finished** never touches the lock).
- **Never** `move_card` to **Finished** — a human moves Review → **Finished** (accept) or → **Rework** (send back).
- Card picked from **Rework**: read its full comment history (`list_comments`) first; the comments are the rework context.
- **Resume vs new run**: apply the D11 rule from Card pickup; a resumed run re-claims without re-minting the slug or re-running kickoff.

## Grouped-sibling flow

A card sometimes stands for a group of small companion asks its owner wants run together — cf-96's own card is the pattern's first instance. The flow triggers ONLY on blocking Red Strings edges: the claimed card's `blocks`/`is-blocked-by` edges (from the claim-time preload's `dependencies` list, or `list_board_dependencies` on demand) name the companion cards. Kind-1 follow-up lineage is `parent_id` alone — it is NEVER a grouping trigger, no follow-up edge is drawn and none is expected back (the batched-round ruling). The edges key on card `_id`, never `card_number`.

- **Plan** — the run pulls every sibling's ask into its OWN plan (the plan names each sibling's card `_id` beside the chunk carrying its ask); one plan, one run, one review covers the group.
- **Moves — coord-owned** — at start, right after the run's own claim, the coordinator moves each sibling to **Executing**; at end, once the sibling's ask landed and the final whole-plan review passed, it moves each sibling to **Review** with one summary comment each (which chunk shipped the ask, the commit range). Siblings are moved exactly like the claimed card — by the coord, never by a subagent.
- **Ride the claim** — siblings run under the run's OWN `pipeline_claim`; they are never claimed separately (one session, one card). The pickup walk skips **Executing**, so a grouped sibling can never be double-picked by another run.
- **Never disturb the settled** — grouping only pulls cards the pickup walk could itself have taken: candidates in **Test** or **Finished** (human acceptance phase) and cards **Executing** under another run's lock are never grouped or moved.
- **Degrade** — until edges exist on the deployed board surface, a run may group from a plan-enumerated id list instead (the same card `_id`s enumerated in its plan's run-protocol section); this ticket's own first instance ran exactly that way, and the degrade follows the family `tools/list` probe law.

## Post-plan card write-back

Right after plan approval (research-only cards do the same immediately before their Ready-for-Review move, D19):

1. `list_custom_fields` on the AI-Dev board → the id of the `slug` field.
2. `set_card_custom_field` (upsert): the server stores the value VERBATIM —
   no server-side append exists — so the stack growth is this skill's
   read-modify-write. Read the field's current value (the `get_card` this
   run already did at claim carries it), then write the `slug` field's
   append-only STACK of combined `[<slug>](<session link>)` lines — newest
   LAST, one line per run, the final `cf-<cardNumber>-<type>-<desc>` as the
   link text:
   - current value empty/unset → write this run's line
     `[<slug>](<session link>)`;
   - the last line's bracketed text is the same slug as this run's →
     rewrite that line in place (idempotent refresh of the link half — never
     append a duplicate line);
   - a different slug is present → append: write
     `<existing value>\n[<slug>](<session link>)` — never drop or reorder an
     existing line, the stack only gains a final line.
   The `<session link>` half is exactly as the Config constants define it:
   `$(SESSION_URL_BASE)/?session=<sessionID>` when this run's `Session
   origin:` resolved, or the RAW session id when it said UNRESOLVED
   (fallback recorded in RESULT) — never a raw id when an origin resolves,
   never a remembered host. Existing cards' split or duplicated legacy
   values are frozen history — tolerated on read, never rewritten; the
   retired `session` field stays never read, never written. This first
   write-back performs the Config constants consistency check.
3. `delete_checklist_item` for EVERY unchecked item of the Services / Type /
   Model(s) / Lifecycle / Human in the Loop checklists (checklist ids from
   `list_checklists`, item ids from `get_checklist`). The surviving checked
   items are the on-card decision record — the checked Model(s) options ARE
   the routing record (D12), the surviving Lifecycle items the stage record
   this run executes, the surviving Human in the Loop items the stop-point
   record.

## Follow-up cards

Cards often defer work — "we'll need a follow-up card for the mechanics of X". When the initial ask includes follow-up cards, the coordinator creates them itself, under this protocol:

- **Timing** — after the post-research stage and before the `Test Writing` session (the Stage map's `Post Research` and `Test Writing` rows): every deferred card is on the board before this run's implementation work starts, and whoever picks it up later reads a complete parent record.
- **Destination** — EVERY follow-up/ledger card lands in the **Inbox** list of the **Backlog** swimlane — never Review, never Low Priority. Inbox postdates every prefetched board-context block: re-resolve its id via `list_lists` at use time (the block is a snapshot, never a freeze). The destination keeps the old non-intake guarantee by location: Inbox lives in the Backlog swimlane, which the pickup walk never visits, so follow-up cards queue for the owner instead of entering auto-pickup.
- **Parent-label inheritance** — a follow-up card carries EVERY label of its parent EXCEPT `Research`: the research-only flow shape must not leak onto work cards; every other label (`Pipeline:`, `Provider:`, `Bucket:`) carries over.
- **Mechanics** — `create_card` with the title, a description quoting the parent card and the deferred ask, the parent's swimlane, and `parent_id` set to the parent card's `_id`: parentId is the ONLY follow-up lineage representation (the batched-round ruling — no dependency edge is drawn for a follow-up and none is expected back). Labels: when the deployed build carries `set_card_labels` (probe `tools/list` once, same law as the preload consumer), apply the parent's minus-`Research` label set with one `set_card_labels(board_id, [new card id], add_label_ids=…)` call right after creating the card — this retires AD-74's ledger round-trip. Until that pin bump ships (the C10 deploy chain), keep the pre-deploy degrade: list the same labels as a "labels to apply" line in the card body and cite the existing label-tool ledger card so the owner applies them by hand. Either way, the minus-`Research` rule above IS the label set — what the call applies and what the line asks for are the same list. Checklist answers ride `default_checked` on `create_card` when the deployed build accepts it (probe once); when it rejects the argument, fall back to `toggle_checklist_item` after creation. NEVER `add_checklist` — the board's createCard rule already adds the five standard checklists (duplicates proven on cards #64–67, 2026-10-28).

Creating these cards is not a run: the creating session claims nothing, moves nothing, and sets no fields beyond the cards it creates — every later move out of Inbox is the owner's alone.

## Friction follow-up (board override)

On `agent-board-coord` family runs, `pipeline-role-coord` step 11 keeps its shape — the two questions (the items, then the mode) and the five modes (`Inbox card` / `new session` / `current session` / `plan only` / `none`: check nothing → stop) — but the family's preference flips: an open item normally lands on the board rather than in a new planning session. The two-question budget and the `current session` bound are the role contract's — step 11 is their authority, cited here and never restated — and every mode is asked, never inferred.

- **Inbox card** — the recommended mode on this family. Create one card per checked item with `create_card` into the **Inbox** list of the **Backlog** swimlane — the id re-resolved via `list_lists` exactly as in Follow-up cards above (title stating the fix, description quoting the full `FRICTION.md` line plus its ticket/chunk context). Inbox is the destination by design: these cards are records awaiting the owner's call, NOT auto-pickup intake — the pickup walk never visits the Backlog swimlane where Inbox lives, so a card can only re-enter the pipeline when the owner moves it to Rework (and if the closing session already shipped the fix, the card simply documents it for acceptance).
- **new session** — a fresh `agent-plan` session plans the fix as its own ticket, exactly as on a plain run; on this family it is the owner's explicit answer, never the default.
- **current session** — worked inside this run, and only inside the bound `pipeline-role-coord` step 11 states for that mode (cite; this section does not restate it).
- **plan only** — `agent-plan` writes the item's plan file and no chunk work follows; the actor and the complete-folder shape are `pipeline-role-coord` step 11's (cite; not restated here).
- **none** — check nothing → stop; the item stays `open` in `FRICTION.md` for the owner.

The board's createCard rule adds the five standard checklists automatically — do NOT `add_checklist` (it duplicates them; proven on cards #64–67, 2026-10-28); the rule's checkItem extras stay dormant, so check the answers the friction context already knows via `toggle_checklist_item` (typically Services `agent context`, Type `chore`, Model(s) `Qwen Dense`). This is not a run: the closing session claims nothing, moves nothing off Inbox, and sets no fields beyond the card's own — every subsequent card move is the owner's alone.

## Batched question protocol

Until the plan is finalized, no one in this flow calls the `question` tool on the user:

**One sanctioned exception**: the Provider filtering kickoff-round question — a run that takes an unlabeled card asks which provider applies at claim, before any planning work starts (Provider filtering subsection); the batched round below is unaffected by it.

- `agent-board-coord` AND every agent it launches for research/planning work MUST NOT ask the user questions.
- Every question is recorded in the plan file's **Open questions** section — the question, the best-guess answer taken, and its impact — and work continues on the best guess.
- When the plan is about to be written/finalized, `agent-plan` returns the accumulated questions: RESULT `open_questions` plus the plan's Open questions section.
- `agent-board-coord` then asks the user the ENTIRE built-up list in ONE `question` call — multiple questions, each with the recommended (best-guess) answer first — and re-launches the plan session with the answers to rework the plan before final approval.

This REPLACES per-question escalation during the planning phase: questions accumulate, they do not block. (`question` stays allowed in every agent's permissions — the protocol decides when the one batched round happens, it does not revoke the tool.)

The card answers in advance: the planner MUST NOT record a question whose answer the five checklists or the `slug` custom field already gives. The batched round carries only genuine gaps (an unchecked Type item, a slug that cannot be derived from card content), each with its best-guess recommendation first. Research-only cards run the same accumulation rule inside their own single follow-up round (Research-only cards, step 3).

## Launch prompt to agent-plan

When launching `agent-plan`, agent-board-coord MUST include this extra prompt text (in addition to the standard launch prompt):

> Card context: <card title, card description, and card comments> — the card description is the request; the feature folder is <path>.
> Checklist answers — already provided by the user, do not re-ask: for each of Services / Type / Model(s) / Lifecycle / Human in the Loop the CHECKED items, plus the card's `slug` custom-field value (the combined `[<slug>](<session link>)` link), its `Priority` custom-field value, and its `cardNumber`.
> No-questions rule: until this plan is finalized you must NOT call the `question` tool. Record every question you would ask — question, the best-guess answer you take, and its impact — in the plan's Open questions section, and continue the work on the best guess.
> Question return: when the plan is about to be written/finalized, return ALL accumulated questions — in RESULT `open_questions` and in the plan's Open questions section. They go to the user in one batched question round, and the plan session is re-launched with the answers before final approval.
