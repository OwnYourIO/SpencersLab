---
name: boards
description: WeKan AI-Dev board flow for the agent-board-coord pipeline variant — card pickup (a given card id, else the top card walking Rework → Not Started → Low Priority), card-driven kickoff where the five standard checklists (Services/Type/Model(s)/Research/Human in the Loop) and the slug + session custom fields supply the answers pipeline-kickoff would ask live, run-tag-free cf-<cardNumber>- slugs naming every surface, the iterative research-only loop for Research-labelled cards (ending at Review), the card lifecycle with post-plan write-back (Finished stays human-owned), and the batched question protocol. MUST-loaded by agent-board-coord at run start; load it anywhere else when working the WeKan AI-Dev board card flow.
targets: ["*"]
---

# Boards

Board-driven intake and exit for `agent-board-coord`. The pipeline machinery (plan folders, chunks, gates, RESULT handoffs) is unchanged from `pipeline-conventions` and `pipeline-role-coord`; this skill defines only the board surface — where work comes from, what the card already answers, how a card moves, and how questions reach the user.

## Board facts

- Instance: `https://wekan.spencerslab.com`; board **AI-Dev**; swimlane **In Process**.
- Lists (six): **Not Started**, **Executing**, **Review**, **Rework**, **Finished**, **Low Priority** (deprioritised work — picked up last).
- Board label **Research** marks a research-only card; matched case-insensitively by name. The agent never creates or mutates labels (human-owned).
- Custom fields: exactly TWO board-level text fields, `slug` and `session`, resolved by name with `list_custom_fields`. There is no `models` custom field (D12) — model routing rides the Model(s) checklist, never a field.
- The five standard checklists on every card (future cards via the multi-action createCard rule — imported per the upgrade-ticket runbook — existing cards via backfill; the runbook owns their maintenance):
  - **Services** — the 13 `services/` folders: `backups` `dev` `gpu` `gpu-ai` `grow` `home` `infra` `media` `monitoring` `personal` `proxy-backup` `proxy-local` `proxy-remote`, plus the two non-folder work targets `home-assistant` (the HA instance itself) and `agent context` (the agent/pipeline machinery). Re-derive the folder set live from `ls services/`; the surface test regenerates it from the repo, so drift here fails loudly (D9).
  - **Type** — `feat` | `bug` | `debug` | `dep` | `refactor` | `chore` | `docs`.
  - **Model(s)** — `Qwen Large` | `Qwen 27b` | `Qwen Flash` | `Local` (gpu-ai). Default selection: `Qwen Flash`. How the check lands: agents creating cards pass `default_checked` to `create_card` (race-free by construction); the board's multi-action createCard rule carries the checkItem extras, but they are DORMANT until WeKan fixes the broken checkItem rule action upstream (`checkListId` field typo, present v12.64→main — details in the wekan-v12-upgrade ticket). A card that arrives with the default unchecked routes from the default selection WITHOUT mutating the card (see kickoff).
  - **Research** — `None` | `Before Planning` | `After Planning` | `Agent Decides`: WHEN this card's research belongs relative to the plan (checked items are the answer; several may be checked; `Agent Decides` delegates the call to the pipeline, `None` = no pre-planning research). Default: `Agent Decides` — the same check situation as Model(s): the agent path checks it now, the rule path is dormant until the upstream fix, and an unchecked card routes from the default.
  - **Human in the Loop** — `Research` | `Plan` | `PR` | `Deployment`: the stages AFTER which the agent must STOP and wait for human input on that card; the checked items are the active stop points. Default: `Plan` — every run pauses for human approval after planning regardless of the checked state (that pause is a pipeline gate, not a card bit); the visible check follows the same situation as Model(s).
- Access: the `dev-boards` MCP server — the wekan-mcp tool set (`get_card`, `list_cards_in_list`, `move_card`, `add_comment`, `list_comments`, `list_checklists`, `get_checklist`, `list_custom_fields`, `set_card_custom_field`, `delete_checklist_item`, …), write-capable; it is the agent's single MCP permission (narrow `dev_boards*`, D21).
- `dev-boards` authenticates SERVER-SIDE via login-mint: `WEKAN_USERNAME` + `WEKAN_PASSWORD` arrive from the `wekan-mcp` Bitwarden LOGIN item and the instance URL rides that item's URI field (data, not values-config). The agent never handles credentials.
- Tool behavior unclear → load the `wekan-api` skill for WeKan API semantics (on demand, never at run start).
- The board structure (board, swimlane, lists, label, custom fields, checklist rules, bot membership) is a user-owned prerequisite; if it is missing the flow sees an empty board and stops cleanly per Card pickup.

## Config constants

The values the flow writes onto the board. They are a written-onto-the-board contract: copy verbatim, never re-derive or "correct" them — with one exception. `SESSION_URL_BASE` is the single RUNTIME value: D18/D22 (cf-50 round 2) supersede intake-D20's copy-verbatim rule for that constant alone, and the literal intake-D20 shipped has since been proven a dead host (coderd answers it `400` — malformed app-host grammar), so no reader may treat it as valid. Every other constant below — `RESEARCH_LABEL` in particular — keeps the copy-verbatim/never-re-derive posture byte-exact.

- `SESSION_URL_BASE` — THIS run's OpenChamber origin, defined as the launch command's `Session origin:` line value, copied verbatim. That line was produced at command expansion from the running workspace's Coder app-origin env `$VSCODE_PROXY_URI` (`{{port}}` → the `openchamber` app-slug label; host labels lowercased; the agent label KEPT — coderd parses it away for app slugs). coderd renders the env per deployment, so no label-order assumption survives and nothing is re-derived agent-side. Never a remembered, guessed or historically-observed host.
- The block self-probes its derived host before emitting — one `curl -m 5` at expansion; recognized answers `200`/`30x`/`401`/`403`. `Session origin: UNRESOLVED` is defined precisely, three branches: the app-origin env absent (the launch is not Coder-hosted), the template shape unexpected (`{{port}}` missing), or the derived host answered a code outside the recognition set (`400` malformed, `000` = DNS/connect/timeout — e.g. a brand-new gpu workspace whose exact split-horizon DNS record has not landed; the probe degrades that to the fallback below instead of shipping a broken link). Honest limit: the probe proves coderd recognizes the host from the workspace's own DNS view — not the human LAN view, not the authenticated leg (landing observations cover those).
- On `UNRESOLVED` the run PROCEEDS (user ruling 2026-10-25, D23 r2): every would-be link slot gets the RAW session id — claim-comment session line, `session` custom-field value, research-only result comment — and the RESULT records the fallback (open_questions/friction). Never silently re-guess a host, and never write a raw id when an origin DOES resolve.
- Session links are exactly `$(SESSION_URL_BASE)/?session=<sessionID>` whenever this run's origin resolves — the `/?session=` form is OpenChamber's own router format (its integrations build the identical URL). Never a raw session id (D13) — that rule governs the resolved branch; the UNRESOLVED branch writes the raw id BY RULE, not by drift.
- Consistency check (the drift check reworded, D23 r2): every link this run writes must equal this run's `Session origin:` value (or the raw-id fallback when it says UNRESOLVED); a mismatch → RESULT flag, never silently re-guess. Historical links are frozen history — card #50's old comments carry the retired literal and its `session` custom field was re-pointed 2026-10-25 — compare only THIS run's writes.
- `RESEARCH_LABEL = Research` — matched case-insensitively.

## Card pickup

1. Card id given in the launch → `get_card` it; that card is the request.
2. Otherwise walk the lists in order **Rework → Not Started → Low Priority**,
   each list top-to-bottom (`list_cards_in_list` response order IS board
   order) and take the first card found — the highest-sorted card of the
   first non-empty list.
3. Confirm the candidate with `get_card` — the by-list projection omits
   `cardNumber`, custom fields and labels, so pickup facts always come from
   the single-card read.
4. Nothing anywhere → report no work and stop cleanly: RESULT
   `status: NEEDS_INFO`, `open_questions: no cards on the AI-Dev board`.
   Never fabricate a request.

The card description is the request. Claim the card per the Card lifecycle before kickoff.

Resume vs new run (D11) — before minting anything, read the card's `slug` custom field:

- It names an existing feature folder whose `STATE.json` `plan_status` is not
  `complete` → RESUME that run: no kickoff minting, no new slug — continue
  the chunk loop where it stopped.
- The run it names is `complete` (card re-picked, e.g. sent back to Rework)
  → start a new sequential run `<slug>-1`; each further completed re-pick
  continues the sequence `<slug>-2`, ….
- Unset, or no matching folder → fresh kickoff.

## Card-driven kickoff — replaces pipeline-kickoff Q1–Q3 for board runs

For card-driven runs this section REPLACES the live `pipeline-kickoff` questions (type, models, slug + run tag) and feeds `pipeline-models` routing from the card instead of a live question. `pipeline-kickoff` and `pipeline-models` stay byte-identical and authoritative for `agent-coord`; the override lives here, not in their files (D1).

Checked checklist items and set custom fields ARE the user's answers: consume them, do not re-ask what the card answers; only genuine gaps join the batched round.

- **type** — the checked Type item; none checked → the question joins the
  batched round.
- **models** — the sole routing input is the checked Model(s) items (D12).
  Default first: if NO item is checked (a card created outside the
  multi-action rule's reach), route from the standard default selection —
  `Qwen Flash` — WITHOUT mutating the card. Then: exactly one checked →
  that model for every tier; several checked →
  the largest drives planning (plan / research / final review), the smallest
  drives code (test / dev / chunk review); only **Local** checked →
  `gpu-ai/qwen3.8-27b-q6` for every role. The size order and the local
  mapping authority stay in `pipeline-models` — reference it, never
  duplicate its table. Record the resolved tiers in STATE.json
  `kickoff.models` and in the claim comment — never as a custom field.
- **human-in-the-loop** — the checked Human in the Loop items are THIS
  run's stop stages: after each checked stage the agent pauses and waits
  for human input before continuing. `Plan` (the default) = pause for plan
  approval; `Research` = pause with the research findings before planning;
  `PR` / `Deployment` = pause before those actions. Nothing checked =
  route from the default (`Plan`) WITHOUT mutating the card — the
  plan-approval pause still happens.
- **slug** — the `slug` custom field if already set; otherwise mint 2–3
  suggestions and put them in the batched round. The final slug is
  `cf-<cardNumber>-<type>-<desc>` (`cardNumber` comes from `get_card`).
  EVERY surface is named from the full slug (D10): feature folder
  `2026-10-<cf-slug>`, worktree `<cf-slug>`, branch `<cf-slug>`, and
  `session_rename` to `<cf-slug>`.
- **In-work mark** — after the `session_rename` returns the sessionID, mark
  the session in-work per `pipeline-kickoff` (citation only — the contract,
  its values and its commands live there, never here).
- **No run tag** — card-driven runs retire the run tag entirely: STATE.json
  `kickoff` carries `card` (the id) + `slug` and omits/nulls `run_tag`.

## Research-only cards — iterative loop

Trigger: the card's labels include the **Research** board label — read board labels via `get_board` and the card's label ids via `get_card`, matched case-insensitively. The label is the ONLY trigger (D14); the Research checklist never fires this flow — on normal cards its checked items only time the research (`Before Planning` / `After Planning` / `Agent Decides`) or cancel it (`None`).

Research-only cards never go to `agent-plan`/`agent-test`/`agent-dev`/`agent-review`. The run:

1. Claim per the Card lifecycle (`move_card` to **Executing** + claim
   comment), then resolve the feature folder exactly as in Card-driven
   kickoff: `cf-<cardNumber>-<type>-<desc>`. No `feat` default for an unset
   Type — it joins the round-2 questions.
2. `agent-research` ROUND 1 — launch with the card request, the checked
   Research-checklist items, and the absolute feature-folder path; the
   summary lands in `RESEARCH.md` there.
3. ONE batched `question` round for the user: refine/direct further
   research — carry every open question from RESEARCH.md plus the slug
   suggestion when the `slug` custom field is unset.
4. Further research on the answers — continue the SAME `agent-research`
   session via its sessionID so the round-1 context carries.
5. Terminate: the default is at most one follow-up round, then wrap.
   Residual unknowns ride along in the final comment for the human's
   Finished-vs-Rework call — do not spin a second round.
6. Write-back exactly as in Post-plan card write-back (D19):
   `set_card_custom_field` for `slug` + `session`, then
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
- **Plan approved** (after the question round) → `add_comment` that the plan is approved (plan path, worktree/branch), then the Post-plan card write-back below.
- **Each chunk done** → `add_comment` with the chunk status (chunk id, dev/review verdict, commit).
- **All chunks done + final whole-plan review passed** → `move_card` to **Review** + summary comment: branch, commit range, validation results, plan path.
- **Never** `move_card` to **Finished** — a human moves Review → **Finished** (accept) or → **Rework** (send back).
- Card picked from **Rework**: read its full comment history (`list_comments`) first; the comments are the rework context.
- **Resume vs new run**: apply the D11 rule from Card pickup; a resumed run re-claims without re-minting the slug or re-running kickoff.

## Post-plan card write-back

Right after plan approval (research-only cards do the same immediately before their Ready-for-Review move, D19):

1. `list_custom_fields` on the AI-Dev board → the ids of the `slug` and
   `session` fields.
2. `set_card_custom_field` (upsert): `slug` = the final
   `cf-<cardNumber>-<type>-<desc>`; `session` =
   `$(SESSION_URL_BASE)/?session=<sessionID>` when this run's
   `Session origin:` resolved, or the RAW session id when it said UNRESOLVED
   (fallback recorded in RESULT) — never a raw id when an origin resolves,
   never a remembered host. This first write-back performs the Config
   constants consistency check.
3. `delete_checklist_item` for EVERY unchecked item of the Services / Type /
   Model(s) / Research / Human in the Loop checklists (checklist ids from
   `list_checklists`, item ids from `get_checklist`). The surviving checked
   items are the on-card decision record — the checked Model(s) options ARE
   the routing record (D12), the surviving Human in the Loop items the
   stop-point record.

## Batched question protocol

Until the plan is finalized, no one in this flow calls the `question` tool on the user:

- `agent-board-coord` AND every agent it launches for research/planning work MUST NOT ask the user questions.
- Every question is recorded in the plan file's **Open questions** section — the question, the best-guess answer taken, and its impact — and work continues on the best guess.
- When the plan is about to be written/finalized, `agent-plan` returns the accumulated questions: RESULT `open_questions` plus the plan's Open questions section.
- `agent-board-coord` then asks the user the ENTIRE built-up list in ONE `question` call — multiple questions, each with the recommended (best-guess) answer first — and re-launches the plan session with the answers to rework the plan before final approval.

This REPLACES per-question escalation during the planning phase: questions accumulate, they do not block. (`question` stays allowed in every agent's permissions — the protocol decides when the one batched round happens, it does not revoke the tool.)

The card answers in advance: the planner MUST NOT record a question whose answer the five checklists or the `slug`/`session` custom fields already give. The batched round carries only genuine gaps (an unchecked Type item, an unset `slug`), each with its best-guess recommendation first. Research-only cards run the same accumulation rule inside their own single follow-up round (Research-only cards, step 3).

## Launch prompt to agent-plan

When launching `agent-plan`, agent-board-coord MUST include this extra prompt text (in addition to the standard launch prompt):

> Card context: <card title, card description, and card comments> — the card description is the request; the feature folder is <path>.
> Checklist answers — already provided by the user, do not re-ask: for each of Services / Type / Model(s) / Research / Human in the Loop the CHECKED items, plus the card's `slug` and `session` custom-field values and its `cardNumber`.
> No-questions rule: until this plan is finalized you must NOT call the `question` tool. Record every question you would ask — question, the best-guess answer you take, and its impact — in the plan's Open questions section, and continue the work on the best guess.
> Question return: when the plan is about to be written/finalized, return ALL accumulated questions — in RESULT `open_questions` and in the plan's Open questions section. They go to the user in one batched question round, and the plan session is re-launched with the answers before final approval.
