# EXPLORE.md — cf-124 Board Checklist, locks, and dependency improvements

Scouted 2026-11-10 by `agent-explore` at worktree branch `cf-124-feat-checklist-locks-dependency`, main HEAD `a6e493b78`.
Repo citations are `path:line` at that HEAD. Live-board facts cite `live read 2026-11-10 (dev-boards <tool>)`; the board is AI-Dev, id `TNQJ2BrXenZovngTS`.
Nothing here was mutated: board reads only (`list_boards`, `preload_board`, `list_board_dependencies`, `list_rules`, `get_rule`, `get_card`), no `create_card`, no moves, no comments.

The card's asks, as anchors used throughout: (A) expand the Lifecycle checklist vocabulary everywhere — **starting with `Session Rename` and `Worktree Creation`** — across default lists, board skills, agent steps, and existing cards NOT on the In Process swimlane; (B) rule defaults → Models `Qwen Dense`, Lifecycle `Exploration, Agent Decides Research, Planning, Test Writting, Chunk Development, chunk Review, Final Review, Deployment`, HITL `Final Review`; (C) default `Priority` = 5 + backfill cards not on In Process; (D) new Services: `CuratedForest.Com`, `HomeAssistant`, `Home-Assistant-Label-Based-Features`, `brother-ptouch-automation`; (E) lock assumptions — user continuation prompt ⇒ lock extendable, card in Executing ⇒ assumed locked; (F) dependency gating on `related-to` instead of `blocks`/`is-blocked-by` ("the dependent card does not move until the related card moves out of Review") + new-card-with-parent ⇒ `fixes` edge.

Vocabulary notes: the card writes `Test Writting` / `chunk Review` — the repo spelling is `Test Writing` / `Chunk Review` (`boards` SKILL.md:21). `Session Rename` and `Worktree Creation` do **not exist anywhere in the repo** as checklist vocabulary (grep over `.rulesync/`, `.agents/loops/`, `scripts/` returns zero hits) — they are brand-new stage names.

---

## 1. Where the Lifecycle checklist vocabulary / stage list is defined and consumed

### 1.1 The single authority — the boards skill (SOURCE + generated mirror)

`.rulesync/skills/boards/SKILL.md` (464 lines; generated mirror `.opencode/skills/boards/SKILL.md` — verified 2026-11-10: bodies from `## Board facts` to EOF are byte-identical, the diff is frontmatter re-wrapping of `description` plus the dropped `targets:` key):

| Surface | Lines | What it pins |
|---|---|---|
| frontmatter description | 3 | "checked-stages-only Lifecycle stage gate with its single-authority Stage map", five checklists named |
| five-checklist roster — **Lifecycle** item | 21 | current 11-name vocabulary, current wording below |
| five-checklist roster — **Human in the Loop** item | 22 | "the SAME eleven names as Lifecycle — the checklists mirror each other" + HITL default `Final Review` |
| **Stage map** section | 28–44 | table rows L34–44: `Exploration`, `Agent Decides Research`, `Pre Research`, `Planning`, `Post Research`, `Test Writing`, `Chunk Development`, `Chunk Review`, `Final Review`, `Deployment`, `Single Session` — one row per stage, each naming the pipeline agent/shape |
| **Blank defaults** | 46–50 | L48 the seven-stage standard default loop; L50 `Deployment` + `Single Session` "never enter the default stage list: … OPT-IN, only what an explicitly checked box runs" |
| **Transition (legacy Research)** | 52–54 | old `Research` checklist timing-only consumption; legacy HITL map `Plan→Planning, PR→Deployment, Research→Pre Research` |
| **Board-side cutover** | 56–58 | human-owned 5-step runbook (rename Research→Lifecycle, replace HITL items, rename Model(s) items, re-import the rules artifact, ensure `Research: Parallel`); "no agent may rename anything on the board" |
| Card-driven kickoff **lifecycle** bullet | 281–284 | checked Lifecycle items ARE the run's stage list; Stage map cited, blank = default loop, legacy = transition rule |
| Card-driven kickoff **human-in-the-loop** bullet | 272–279 | HITL stop-point consumption |
| Post-plan card write-back, step 3 | 411–417 | `delete_checklist_item` for EVERY unchecked item of the five checklists; "the surviving Lifecycle items the stage record this run executes" |
| Follow-up cards — Mechanics | 426 | `default_checked` on `create_card`, `NEVER add_checklist` |
| Friction follow-up (board override) | 430–440 | rule adds the five checklists; check via `toggle_checklist_item` (typically Services `agent context`, Type `chore`, Model(s) `Qwen Dense`) |
| Launch prompt to agent-plan | 462 | "for each of Services / Type / Model(s) / Lifecycle / Human in the Loop the CHECKED items…" |

Current wording the change touches (verbatim, SKILL.md:21):

> **Lifecycle** — `Exploration` | `Agent Decides Research` | `Pre Research` | `Planning` | `Post Research` | `Test Writing` | `Chunk Development` | `Chunk Review` | `Final Review` | `Deployment` | `Single Session`: the stages THIS card runs, in card order (`Single Session` last, kept by the OQ6 ruling)

Blank defaults (SKILL.md:48, verbatim):

> Default when nothing is checked: the Lifecycle stage list is the standard default loop — `Exploration`, `Agent Decides Research`, `Planning`, `Test Writing`, `Chunk Development`, `Chunk Review`, `Final Review` — so every default run starts with the read-only scout (the OQ14 ruling) and closes with the whole-plan review.

Adding `Session Rename` + `Worktree Creation` FIRST renumbers this list, the HITL mirror (L22), the Stage map (add two rows), the Blank defaults (are the two new stages in the default loop? — the card's default list under (B) does NOT include them, yet "It should start with Session Rename and Worktree Creation" describes the checklist, not the default), and the OQ6 "eleven names" phrasing everywhere.

### 1.2 Consumers (cite-the-map; each needs a wording re-pin if the map grows)

- `.rulesync/skills/pipeline-role-coord/SKILL.md` — step 5b **L23** (skip review launch when `Chunk Review` unchecked), step 7 **L27** (evidence-shape done-gate), step 8b **L29** (Deployment-stage hook), step 11 **L35–44** (friction modes; boards:430–440 overrides it), **Stage gate paragraph L46** ("the card's checked `Lifecycle` items ARE this run's stage list… the `boards` Stage map is the single authority"), hard-rules **L67** (`agent-explore` launch = Stage map's `Exploration` row). These steps cite, never restate — but two NEW first stages mean the stage gate now gates kickoff mechanics: Session Rename / Worktree Creation currently happen in step 0 (L16, per `pipeline-kickoff`) BEFORE any stage gate runs. Design question: an unchecked `Session Rename` cannot "skip" the rename that every surface name depends on (D10) — the planner must decide whether these stages are always-run (and then what does the checkbox mean?).
- `.rulesync/skills/pipeline-role-deploy/SKILL.md` **L12** (`Deployment` row = launch condition); `.rulesync/skills/pipeline-push-pr/SKILL.md` **L53** (Lifecycle `Deployment` check drives the push).
- Subagent bodies (generated mirrors in `.opencode/agents/`): `.rulesync/subagents/agent-board-coord.md` — Skills MUST-load list **L424–436** (`/agents-sync /executing-plans /opencode /pipeline-conventions /pipeline-kickoff /pipeline-models /pipeline-gates /pipeline-role-coord /boards`), permissions comment **L362** ("the boards Stage map's Deployment row is the gate"), `## Boards` section **L442–455** (kickoff bullet L448; the write-back paragraph L452 repeats "`delete_checklist_item` for every unchecked item of the five checklists"); twins `agent-board-coord-local.md` **L362/L448** and `agent-board-coord-pr.md` **L380/L469** (alias-twin equality is pinned — `pipeline-role-coord` L62: "Any change to a variant's permissions or roster must land on its alias twin in the same commit"). `.rulesync/subagents/agent-explore.md` **L92** ("The lifecycle `Exploration` stage launches you"); `.rulesync/subagents/agent-dev-deploy{,-pr}.md` **L5** descriptions ("a run whose card checked the Lifecycle Deployment stage").
- Commands: `.rulesync/commands/pipeline-boards.md` **L16** and `pipeline-boards-pr.md` **L16** (both enumerate "Services / Type / Model(s) / Lifecycle / Human in the Loop"); `.rulesync/commands/pipeline-boards-hourly.md` — body L24–32 (gate verdicts + BOARD CHECK; L32 bans `set_card_custom_field`, `delete_checklist_item`, `toggle_checklist_item`, card creation until the Executing-empty verdict), no checklist-vocabulary enumeration.
- Rules source → generated AGENTS.md: `.rulesync/rules/overview.md` L142, L165, L251–259 → `AGENTS.md` L144, L167, L253–260 ("checked Lifecycle items are the stages the run executes (checked-stages-only; the 11-item checklist ends with the kept `Single Session` opt-in… the `boards` Stage map's Blank defaults section names its seven stages)"). The literal "11-item" and "seven stages" phrasing needs re-deriving.
- Stage-mechanics homes the two new stage names map to: `.rulesync/skills/pipeline-kickoff/SKILL.md` **L33** (worktree `worktree_create` + `kickoff-mint-branch.sh`) and **L34** (`session_rename`), `pipeline-role-coord` step 0 **L16**, boards **L295–298** (D10 surfaces-named-from-slug + mint citation).
- Not to be confused with: the `0-pipeline` 7-stage SDLC vocabulary (`.rulesync/subagents/0-pipeline.md`, `1-feature-generation`…`7b-docs-dev`) — separate system, untouched by Lifecycle changes.

### 1.3 Provision-side + artifact copies of the vocabulary (also "everywhere")

- `scripts/provision-board.py` `LIFECYCLE_ITEMS` **L76–88**, comment **L65–75** ("that text is the authority, copied not retyped (the cf96 cutover suite pins the equality and fails loudly on drift)"); `CHECKLIST_SPEC` **L89–120** (Lifecycle L118, HITL L119 both `{"items": LIFECYCLE_ITEMS, "checked": []}`).
- `.agents/plans/2026/2026-11-cf-106-feat-coord-fixes/board-rules-v12.65-dense.json` — the current-generation createCard rule, `checklistItems` strings carry the 11 Lifecycle + 11 HITL names (top-level action + extraActions).
- `skills/wekan-board-provision/SKILL.md` **L3** ("11-item Lifecycle + Human in the Loop mirror, Model(s) → Qwen Dense default-checked"), **L39–45** (five extras, schema-2 diff), **L119–130**, **L148–150** — all re-pin the generation name count.

---

## 2. The card-checklist PRODUCERS and how a rule-extras artifact is applied

### 2.1 `scripts/provision-board.py` (355 lines; the offline engine, never applies)

- `CHECKLIST_SPEC` L89–120 — five checklists; **default_checked today: ONLY `Model(s): ["Qwen Dense"]` (L116)**; Services (15 items, L90–109), Type (L110–113), Lifecycle (L118) and HITL (L119) arrive `checked: []` per the OQ13 single-check posture (comment L69–72).
- `RULES_ARTIFACT` L126–128 → `.agents/plans/2026/2026-11-cf-106-feat-coord-fixes/board-rules-v12.65-dense.json`.
- Schema-2 snapshot gate L146–158 (`wekan-board-snapshot/2` must carry `checklist_extras`); drift → action `{"action": "update_createcard_checklists", "artifact": RULES_ARTIFACT, "drift": [...]}` L298–305; rendered as L315–318: `HUMAN-EXECUTED: WeKan UI → Rules → Import JSON … (backup first)`.
- `--dry-run` is an accepted no-op: "the engine never applies, so every run is the dry run" (L332–337).

### 2.2 Rule artifacts under `.agents/plans/` (all three exist at HEAD)

- `.agents/plans/2026/2026-10-dep-wekan-v12-upgrade/board-rules-v12.64.json` — v1 (Research checklist era, `Qwen 27b`).
- `.agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/board-rules-v12.65.json` — cf-96 applied generation (the 11-item cutover).
- `.agents/plans/2026/2026-11-cf-106-feat-coord-fixes/board-rules-v12.65-dense.json` — CURRENT: title `Std checklists + defaults (Model(s): Qwen Dense, 11-item Lifecycle + HITL mirror)`; action `addChecklistWithItems Model(s) = Qwen Large,Qwen Dense,Qwen Flash,Local (gpu-ai)`; extraActions = `checkItem Model(s)/Qwen Dense` + `addChecklistWithItems` for Services(15)/Type(7)/Lifecycle(11)/HITL(11). A new vocabulary generation means a NEW artifact (cf-106 re-issued cf-96's; the naming precedent is `board-rules-v<version>-<vocab>.json`).

### 2.3 How an extras artifact gets applied — human-only, quoted

- boards SKILL.md **L58** (verbatim, the operative rule): "Agents never mutate board checklists or rule extras — the existing labels-are-human-owned posture extends to checklists; the owner applies the artifact and the renames POST-BACKUP, backup first, read back after." Plus "C02 produces it modify-only (never run against the live board by an agent)".
- `skills/wekan-board-provision/SKILL.md` **L119–124** (verbatim): "An `update_createcard_checklists` action in the plan is **HUMAN-EXECUTED, never applied here**: checklist extras on a rule are creatable only through the WeKan UI wizard or Rules → Import JSON, never through any REST or MCP call — that is why this leg exists as a runbook action." And invariant **L148–150**: "no agent path writes checklist extras, and the engine only prints the import runbook." (dev-boards does carry `update_rule`/`create_rule` tools — the ban is doctrine, not tool absence.)
- The one sanctioned agent-executed board-write leg: the `/wekan-board-provision` additive apply the owner directs (lists, `Bucket:` labels, rule pairs, label ensures) after a confirmed dry-run (boards L58; skill step-3 contract L85–102).

### 2.4 Live rule state (live read 2026-11-10, `list_rules` + `get_rule`) — DRIFTS from repo history

- 19 rules total. TWO `Std checklists + defaults` createCard rules coexist: `iacQY5QxQbPfzjgjR` (legacy Flash/Research/Plan vocabulary, `Model(s): "Qwen Large,Qwen 27b,Qwen Flash,Local (gpu-ai)"`) — **enabled: false** — and `Wt2CRjuikgde6eFb7` (the Dense 11-item generation) — **enabled: true**, its stored `extraActions` match `board-rules-v12.65-dense.json` byte-for-item (checkItem Qwen Dense + the four `addChecklistWithItems`). So cf-106 C02's artifact WAS imported by the owner; the disable of the legacy rule is not recorded in the repo docs (skill only documents it as "the applied history"). A plan that ships a new artifact should also state the pause/keep-posture for the old disabled rule.
- `checkItem` extras being DORMANT upstream (the `checkListId` typo, "present v12.64→main", boards L20) is why new cards' Model(s) default lands unchecked via the rule; agent-created cards bypass it with `default_checked` (§4/§7).
- Rule-vocabulary facts for any rule work: `skills/wekan-api/references/wekan-mcp-ops.md` L50–80 — no action whitelist ("the vocabulary is what `rulesHelper.js` implements. Confirmed entries include `addChecklistWithItems` and `addLabel`/`removeLabel`"), execution order unspecified, rules async 1–2 s, "never retroactive — existing cards need a per-card backfill".

---

## 3. Services checklist vocabulary

- Authority: boards SKILL.md **L18** (verbatim): "**Services** — the 13 `services/` folders: `backups` `dev` `gpu` `gpu-ai` `grow` `home` `infra` `media` `monitoring` `personal` `proxy-backup` `proxy-local` `proxy-remote`, plus the two non-folder work targets `home-assistant` (the HA instance itself) and `agent context` (the agent/pipeline machinery). Re-derive the folder set live from `ls services/`; the surface test regenerates it from the repo, so drift here fails loudly (D9)."
- "Re-derived live": `tests/agent-board-coord/rulesync-surface.sh` **L666–674** — `for d in $(ls services/); do grep -qF "\`$d\`" "$SKILL_GEN"` for every folder, plus the two extra targets hard-listed (L672–674). So a new `services/` folder only needs the prose updated; a new NON-folder target needs spec+prose+test changes.
- Repo check 2026-11-10: `ls services/` = exactly the 13 folders (no drift today). Copies of the 15-item list: `scripts/provision-board.py` L90–109; `board-rules-v12.65-dense.json` Services string; live rule `Wt2CRjuikgde6eFb7` extras (identical string, live read).
- **The four names the card wants added are repositories, not `services/` folders.** They belong to the multi-repo worker posture (cf-93), whose home is the boards `Repo:` label table, SKILL.md **L81–95**:

  | `Repo:` label spelling (exact dir name) | Default picker |
  |---|---|
  | `SpencersLab` | yes — it claims the no-`Repo:`-label cards |
  | `HomeAssistant` | no |
  | `Home-Assistant-Label-based-Features` | no |
  | `brother-ptouch-automation` | no |

  With the spelling-history sentence L95 (verbatim): "card #93's text writes `Home-Assistant-Label-Based-Features` — that capital-B is a mis-cased historical spelling of the LBF directory; the label spelling is the exact lowercase-b dir name in the table above." The worker-repo sentence L85: "The four worker repos" — adding `CuratedForest.com` as a fifth worker repo touches this sentence, the table (every ported copy of the body carries all repos, L83–84), `tests/multi-repo/` (existing ports: `port-homeassistant.sh`, `port-lbf.sh`, `port-brother-ptouch.sh`, plus `repo-label-filter.sh`, `hourly-board-check.sh`, `dev-wiring.sh`; no CuratedForest port exists), and each sibling repo's own boards-skill copy.
- Live facts (live read 2026-11-10, `preload_board` `label_names`): the board carries **no `Repo:` labels at all** (19 labels: `Research`, `Ready for Work`, `Bucket Color`, 5 `Pipeline:*` = Local/CICD/Context/Home Assistant/AI, `Provider: Local/API`, 8 `Bucket:*`, `Research: Parallel`). A Planning list **`CurateForest.com`** (note spelling "Curate" — card writes "CuratedForest.Com") exists with one card #87, so the owner already segregates that work by LIST, not label.
- Decision the planner must make per name: Services item (only defensible as a non-folder target like `home-assistant`, since D9 regenerates the folder set from this repo's `services/`), and/or `Repo:` table entry (defensible for the three existing worker repos; they are ALREADY covered), and/or provision-script addition. The card's framing ("add some more services") most plausibly means: make `Repo:` coverage explicit + add CuratedForest.com as the fifth worker repo — but the evidence that three of four are already the cf-93 table is what the plan must not miss.

---

## 4. Priority (`Priority` NUMBER custom field) — whole surface

- Roster: boards SKILL.md **L16** — "exactly TWO board-level fields — `slug` … and `Priority` (NUMBER) … `get_card` is the only value source for `Priority` (`[{id, value}]`); the claim-time `preload_board` per-card dict does NOT carry it" (verified live: preload card dict keys are exactly `[id, card_number, label_ids, slug, archived, sort, parent_id, checklists]`).
- Consumption: boards **L264–271** (verbatim, the bullet the change rides):

  > **priority** — the `Priority` custom field's value (string→int coercion; `null`/absent = the default class) joins the card-provided answers; … The board field itself is NEVER written back by agents: it is input-only, and the post-plan write-back stays slug-only.

  STATE.json record shape: `kickoff.priority {raw, class}` (L266–267, L308). `pipeline-kickoff/SKILL.md` **L44** — the `priority` slot exists only for board runs.
- Class table authority: `.rulesync/skills/pipeline-models/SKILL.md` **L39–51**. L45 (verbatim row): "`| unset / `null`, `4`–`7` | default | `gpu-ai/qwen3.8-27b-vllm` | 5 |`"; L50 snaps intervals "1–3→1, 4–7→5, 8–9→9, 10+→10". **Reading of the card's ask vs the table: a card that reads unset/null ALREADY resolves to the default class = vLLM `body.priority` 5.** Backfilling `Priority = 5` changes the raw value (visible on the card, no longer null) but is a class no-op. The plan should say so explicitly — "default priority to 5" is a display/defaults change, not a behavior change. (The "5" the card means is the WeKan-side NUMBER, not "urgent".)
- **Does `default_checked` reach custom fields? No.** `create_card` (`containers/wekan-mcp/wekan_mcp/server.py` L578–656) accepts `default_checked` (dict of checklist-title → item titles, validated L550–577, applied with a bounded poll L459–548) and `parent_id` (PUT `parentId`, outcome `parent_id_set`/`parent_id_error` L638–654) — nothing custom-field. Custom fields attach per card via `set_card_custom_field` (server.py L963+, upsert attach-if-missing; semantics in `skills/wekan-api/references/wekan-mcp-ops.md` L114–125 — "attaches-if-missing by PUTting the whole `customFields` array (documented read-modify-write race…)", "Values are written as given — number… coercion is not implemented"). `create_custom_field` has `automatically_on_card` (field ATTACHES to future cards, **no default-value concept** — ops doc L116–119: v9.99 create ignores `alwaysOnCard`, so existing cards are NOT attached).
- createCard rule extras cannot set a custom field through any confirmed action: the confirmed rules vocabulary is `addChecklistWithItems` + `addLabel`/`removeLabel` (ops L54–58); a `checkItem` action exists (used by the live rules) but no custom-field action is documented anywhere in this repo. → **Open question for research/plan**: whether WeKan v12.65 rules can set custom-field values on create (would need upstream check), else the "default priority 5" has exactly two landing shapes: (a) human/agent per-card `set_card_custom_field` backfill for existing cards + agents passing nothing at create (field stays null → default class anyway), or (b) a doctrine amendment where the boards skill's "NEVER written back by agents" ban (L269–271) is precisely what the card's backfill ask runs into for agent execution.
- Live state (live read): `list_custom_fields`/preload `field_names` → `slug` `RaNeqvh9YoT4bnkZ8`, `session` `zZw4PwMoLeodJy3eT` (retired, still on the board — its removal is human-owned, itself a follow-up card #73), `Priority` `fp5vnD5YrA7oAxPiK`. Sampled `get_card` on #124: `custom_fields: [{Priority: null}, {session: null}, {slug: null}]` — Priority is null on a current card.

---

## 5. Lock doctrine — engine + skill text, and where the two new assumptions land

### 5.1 Engine — `.opencode/plugin/pipeline-locks/index.ts` (2534 lines, hand-managed)

- Lock set claim: O_EXCL sorted creation (L4–8); one file holds N holders, record v2 (L12–16); `reason:"occupied"` names live foreign holders (L14–16); sharing only via per-claim `shared: true` "the human supplies…, never a deployment setting" (L16–19); every downstream action "acts on the CALLER's holder row and never on, or against, a co-tenant's" (L19–20).
- Lost-set door (L22–27, verbatim): "the plugin signals only. `handleLockLost` arms a per-root stop marker that keeps guarded tools blocked until the session makes its OWN new claim — **no self-reclaim, ever** — and a claim whose whole set is exactly the card's id, made with a `.reaped/` record naming that card, is tagged `after_reap` in the record and the claim audit as **evidence, not as a new permission**."
- `LOCK_LOST_STOP` (L178, verbatim — the text every tool answer emits): "PIPELINE LOCK LOST — do not commit or move the card; stop the step, ask the user once whether to continue anyway, and on yes re-claim with pipelines:[<cardId>] instead of the reaped pipeline label — on no or silence, take the blocked/abandoned exit".
- Stale window: `DEFAULT_STALE_MS = 7200000` (L113–115, "D21 ruled the stale window at 2 h"); reaper moves whole files to `.reaped/` (`REAPED_SUBDIR` L127), cross-process guard `reaper.lock` (L117–122), card comment "Timed out: no heartbeat for 2h" (`TIMEOUT_COMMENT` L144), HA alert title L150; tool names L72; takeover tag constant `TAKEOVER_AFTER_REAP = "after_reap"` (L180–183). There is **no extend/renew call** in the engine: liveness is heartbeat-only (automatic on activity; `pipeline_heartbeat` force-beats, boards L159).

### 5.2 Skill text (`.rulesync/skills/boards/SKILL.md`) — the sentences the card's assumptions touch

- **(a) "if the user prompts continuation, it should be assumed the lock can be extended."** Current governing sentences:
  - **L160 (Human stops D20/D21)**: "**PIPELINE LOCK LOST** from any tool answer or hook: stop the step, then exactly ONE sanctioned question in this run — \"may I continue anyway?\"; the answer gates the resume. On yes: re-claim with `pipeline_claim(cardId, pipelines:[<cardId>])` (the card-id lock — a key no other run contends) … record the takeover in STATE.json `kickoff.claim` … On no or silence: the blocked/abandoned exit — never a silent resume, never a second question."
  - L161 (Exit): "continue anyway only after the one sanctioned question — the resume runs under the card-id lock, not the reaped pipeline label."
  - The plugin side keeps working regardless: a continuation prompt answered by the run is still "its OWN new claim" (engine L24–25), the resume stays a **re-claim under `pipelines:[<cardId>]`**, never a re-claim of the reaped pipeline label; the `after_reap` tag stays "evidence, not … permission" (L26–27). What the card changes is the WORDING, not the engine: "ask the user once" becomes "a user continuation prompt counts as the yes" — the sanctioned question is answered-by-context instead of demanded-in-session. Sentences that must change: boards L160 ("then exactly ONE sanctioned question in this run… the answer gates the resume"), L161 ("only after the one sanctioned question"), and the `LOCK_LOST_STOP` comment guidance in `pipeline-locks/index.ts:174–178` (L178 itself is a runtime string — changing it is a plugin change with the suites that pin the phrase; gate/audit tests cite the "one sanctioned question" posture). The plan must decide: does the assumption also revive a REAPED set (extend the original pipeline label)? Engine says no (`.reaped/` + card-id key); if the card wants true extension of the original lock, that is an ENGINE change, flag it.
  - Also adjacent: L160 first half (the 2 h clock ticking through stop points, the Timeout degrade) is unchanged by (a) — continuation prompts don't stop the stale clock until a re-claim exists.
- **(b) "if a card is already in executing, it's assumed to have a lock."** Current sentences:
  - L125: "The walk never visits **Executing** — a card there is owned by the run holding its pipeline lock set" — the CURRENT doctrine makes the LOCK the evidence of ownership; the card inverts it to make **list membership itself the evidence** (a card in Executing is assumed locked even if no live lock record exists — e.g. the D22 degrade where the reaper could not move it to a Timeout list, or a crash before release).
  - L155: "**Never pick or restart a card in Executing**; never pick from **Timeout**." — unchanged in effect (the walk already never visits Executing); the assumption strengthens WHY.
  - `AGENTS.md` L314 / `.rulesync/rules/overview.md` L312: "One card per session; never pick or restart a card already in **Executing**" — wording can stay, but the rationale sentence (L125) must be rewritten to the assumption form.
  - Grouped-siblings **L380**: "cards **Executing** under another run's lock are never grouped or moved" — under the assumption the qualifier "under another run's lock" becomes redundant/removable (membership alone suffices).
  - Gate script: `scripts/agent-board-coord-gate.sh` L6–9 + L60 — "The WeKan Executing operand is deliberately NOT evaluated here: a bash script cannot hold an MCP session, so the board check is the agent's own read-only turn" (verdicts L65–67: `GATE: RUN|LIVE|SKIP`). `.rulesync/commands/pipeline-boards-hourly.md` L26–32 (BOARD CHECK: any Executing card passing the `Repo:` filter stops the tick). The assumption is compatible: the hourly Executing operand ALREADY treats Executing membership as occupancy (it never checks locks there); the plan can cite that as the precedent this assumption generalizes.

### 5.3 Supporting doctrine (for context, likely untouched)

"Claim before anything else" L156; "Co-tenancy is the human's call, never the run's" L157 (`shared: true` per claim); "Exit" L161 (Review→`pipeline_release(outcome:"done")` is the release point); "Board-side prerequisites" L162; `pipeline_*` tools are Code-Mode-only L151–152; AGENTS.md worker-rules section L300–330.

---

## 6. Dependency semantics — current wording, stored shape, live edges

### 6.1 The gate text that flips (boards SKILL.md L127, inside `## Card pickup` L96–139)

> **Dependency gate — a blocked candidate is skipped.** … the candidate is SKIPPED when a blocking edge points at it from a card that is neither archived nor sitting in a list titled **Test** or **Finished**. The blocking edge set is EXACTLY the two Red Strings types `blocks` and `is-blocked-by` — `related-to`, `fixes`/`is-fixed-by` and `duplicates`/`is-duplicated-by` never gate pickup. Both spellings mean one thing here, but the board stores only one entry per drawn edge: v12.65 keeps the edge on the card it was drawn FROM and neither the board-wide edge list nor the preload synthesizes an inverse twin — so the gate honors BOTH spellings consumer-side via WeKan's type-inverse map …

Also keyed here: satisfaction = "neither archived nor sitting in Test or Finished" (a blocker in **Review** blocks today; the card's "until the related card moves out of Review" matches that direction); "Every reference keys on the card `_id`; `card_number` is display-only"; unresolvable far end = NON-GATING + REPORT; skips reported in RESULT + claim comment. Related sentences: L14 (Test/Finished satisfaction in Board facts), description L3 ("the dependency gate over blocking Red Strings edges"), grouped-sibling trigger **L375**: "The flow triggers ONLY on blocking Red Strings edges: the claimed card's `blocks`/`is-blocked-by` edges … Kind-1 follow-up lineage is `parent_id` alone — it is NEVER a grouping trigger, no follow-up edge is drawn and none is expected back (the batched-round ruling)." If `related-to` becomes the blocking set, L375, the gate, the Board-facts sentence, and the tests all re-pin; `fixes` becoming the parent-edge also collides head-on with L426 (Follow-up cards):

> **Mechanics** — `create_card` with … `parent_id` set to the parent card's `_id`: parentId is the ONLY follow-up lineage representation (the batched-round ruling — no dependency edge is drawn for a follow-up and none is expected back).

### 6.2 Tool surface (repo + deployed) — `containers/wekan-mcp/wekan_mcp/server.py`

- Seven types, pinned tuple L1272–1275: `related-to, blocks, is-blocked-by, fixes, is-fixed-by, duplicates, is-duplicated-by` — note there is **no inverse for `related-to`** (unlike the other three pairs): a `related-to` edge is single-spelled, which removes the "both-spellings" inverse-map machinery for the new gate but raises the "which end is the dependent?" question (stored edges are one-sided, §6.3).
- `list_board_dependencies` L1353–1373: passthrough of `GET /api/boards/:id/dependencies`, shape `{from, fromTitle, fromCardNumber, to, toTitle, toCardNumber, type, color, icon}`; "the board view carries NO synthesized inverse" (L1360–1362); archived cards excluded server-side.
- `list_card_dependencies` L1376–1387 (one card's stored `cardDependencies`, `{cardId, type, color, icon}` — target ids only).
- `add_card_dependency` L1390–1441: UPSERT on the (source→target) pair — "a repeat add with a new type/color/icon rewrites that edge"; client-side type gate naming the seven; **"Omitted type … ride the upstream defaults (related-to, #eb144c, link)"** (L1412–1413); "the house rule is is-blocked-by stored on the DEPENDENT card toward its blocker" (L1405–1406) — that house-rule sentence changes under the new doctrine.
- `edit_card_dependency` L1444–1484 (re-type existing edge), `remove_card_dependency` L1487+ (DELETE, no undo).
- `create_card(..., default_checked, parent_id)` L578–656: `parent_id` sets `parentId` via PUT after create, non-fatal failure shape L638–654. **There is no dependency parameter on `create_card`** — a "new card with a parent ⇒ fixes edge" flow means `create_card(parent_id=…)` + `add_card_dependency(type:"fixes")` after, or extending the tool.
- `preload_board` L1507+ shape (verified live): `{board_id, swimlanes:[{id,title,lists:[{id,title,cards:[{id,card_number,label_ids,slug,archived,sort,parent_id,checklists:[{id,title,items:[{title,finished}]}]}]}]}], dependencies:[…board-wide edge list…], label_names, field_names}`; kickoff-vocabulary checklist filter `_PRELOAD_CHECKLIST_TITLES` L1286–1288 + legacy 8-item heuristic L1295. Boards L320 makes this the single claim-time read ("the dependency-gate evaluations" ride it); degrade law L320 (absent/present-but-failed both degrade, one retry, gate skipped, RESULT note).

### 6.3 Live stored edges (live read 2026-11-10, `list_board_dependencies` + preload `dependencies`) — the whole truth: 4 edges, ALL `related-to`

| from | to | type |
|---|---|---|
| #56 Forgejo pipeline for Coder templates (`BdMdZ5ia7kemwTB5x`) | #135 Move Renovate to git.spencerslab.com (`grj3HFxsi3WzM5y96`) | `related-to` |
| #73 Delete legacy session custom field (`qMMB5XRQpX9JXdbxZ`) | #140 Improve coord card picking (`zKf2GkiwPgeDmfpu2`) | `related-to` |
| #126 Compaction and Pipeline Sessions (`PpN4g7xQDD4LXEuPW`) | #124 THIS card (`QZPzjuGT4u6aQvq6C`) | `related-to` |
| #140 Improve coord card picking | #126 Compaction and Pipeline Sessions | `related-to` |

Constraining facts for the design:
- **No `blocks`/`is-blocked-by` edge exists anywhere** — the current gate never fires on this board. Under the card's rule every one of these four edges starts gating.
- One-sided storage is real here: #73→#140 has no twin, while #126↔#140 and (through #124) a chain exist — #140 and #126 are BOTH in Not Started and mutually related: gating on `related-to` would deadlock the pair (each waits on the other "moving out of Review"). #126→#124 means #126 is tied to this ticket's own card (#124 sits in Executing, not in Review/Finished/Test — #126 gates either way). The plan needs a direction/tie-break rule (which endpoint "has the dependency"?) because `related-to` carries no direction.
- v12.65 keeps an edge only on the drawing card; no inverse synthesis anywhere (server docstrings + boards L127) — any consumer reading `related-to` must enumerate BOTH the card's own `dependencies` and the board list to know its full related-set (the preload already returns the board-wide list — fine).

---

## 7. The live board as it stands — backfill targets + deployed tool surface

### 7.1 Structure (live read 2026-11-10, `preload_board` unfiltered) — DRIFTS past the skill's 2026-11-01 capture (skill L14 admits "DRIFTS; context, never a freeze")

- **In Process**: `Not Started` (16 cards, 10 archived), `Low Priority` (2, both archived), `Executing` (4: **#124 itself**, #6, #141, #55), `Review` (9, 7 archived), `Test` (3: #93, #96, #81), `Finished` (36, 1 archived), `Cancelled` (7), **`Resume Later` (2: #105, #131 — a list the skill never names)**.
- **Planning**: `Context` (15), `CICD` (8), `CurateForest.com` (1), `Dev Env` (4), `Home Assistant` (5).
- **Backlog**: `Inbox` (10), `AI` (5), `Context` (11), `CICD` (8), `Dev Env` (2), `Home Assistant` (5), `Outside Process` (4 — the provision skill's "Farm's `Outside Proccess` typo survives" invariant, `skills/wekan-board-provision/SKILL.md` L142–145, is stale two ways: live spelling is `Outside Process` and the list now sits in Backlog), `Research` (11), `Features` (6).
- **Farm**: `Home Assistant` (8), `Dev Env` (1), `Features` (2).
- 19 labels / 3 custom fields as listed in §3/§4. `Timeout` list still absent (the D22 degrade stands).

### 7.2 Backfill targets — "all existing cards not on the In Process swimlane"

**90 non-archived cards** outside In Process (106 including 16 archived): Planning 28, Backlog 52, Farm 10. Checklist generations (from `checklists` in the preload):

- ~76 (the bulk): legacy shape — `Services(15) + Type(7) + Model(s)(5 options: `Qwen 27b` generation) + Research(4: None/Before Planning/After Planning/Agent Decides) + Human in the Loop(14 legacy items) + Lifecycle(11, mostly unchecked)`. They carry BOTH the legacy Research checklist and an 11-item Lifecycle, but a **14-item legacy HITL** — the cf-96 cutover step 2 ("replace the HITL items with the same 11 names") never landed on existing cards.
- 10 new-gen (Lifecycle 11 + HITL 11, no Research): #125, #128 (Planning/Context), #127, #129, #130, #134, #136, #137, #138 (Inbox), #132 (Backlog/Features).
- 2 duplicated-set oddities: #66 (Planning/Context) and #65 (Backlog/Context) — double Services/Type/Research/HITL sets (12-item HITL = two partial sets), consistent with the documented add_checklist duplication (boards L426 "duplicates proven on cards #64–67, 2026-10-28"; also #64/#67/#120/#57 show duplicates inside In Process/Finished).
- 2 oldest: #57, #71 (Planning/Context) — Research checklist only, 4-item HITL, **no Lifecycle at all**.

In Process (NOT backfill targets per the card): Executing #6 carries an 8/8-item legacy Lifecycle (the L1295 heuristic's 8-item spelling); #135 (Review) `Lifecycle(7/7)` 7-item; #122 (Finished) `Lifecycle(0/0)` empty; the In-Process new cards (#124, #141, #133, #139…) carry 11-item Lifecycle with 6–8 checked — #124 itself has Lifecycle(6/11) + HITL(1/11) checked (the run's card).

Backfill mechanics available and blocked-posture: per-card checklist mutation tools exist deployed (§7.3) and per-card mutation is already normal doctrine (post-plan `delete_checklist_item`, L411–417; friction `toggle_checklist_item`, L440). The board-LEVEL ban (L58) covers "board checklists or rule extras", while existing-CARD maintenance is assigned to the runbook: L17 (verbatim) — "future cards via the multi-action createCard rule — imported per the upgrade-ticket runbook — **existing cards via backfill; the runbook owns their maintenance**". The plan must choose: agent-executed backfill (needs a human-directed sanction analogous to the `/wekan-board-provision` step-3 contract — the only sanctioned agent board-write precedent, L58) vs a human runbook. Same question for the Priority=5 backfill (§4).

### 7.3 Deployed dev-boards surface (live probe 2026-11-10 via the Code Mode catalog)

- **39 tools deployed** (matches `containers/wekan-mcp/README.md` L9 "39 typed tools"; registry grew 38→39 at cf-106 C07): the 5 checklist-mutation tools are ALL present — `list_checklists`, `get_checklist`, `add_checklist_item`, `delete_checklist_item`, `toggle_checklist_item` — plus `preload_board`, `get_card_details`, `set_card_labels`, `set_card_custom_field`, `list_card_dependencies`, `list_board_dependencies`, `add_card_dependency`, `edit_card_dependency`, `remove_card_dependency`, `create_list`, `create_label`, rule tools, `update_board/board members/swimlane`.
- **`default_checked` IS accepted by the deployed build**: the deployed `create_card` schema exposes `default_checked?: {} | null` AND `parent_id?: string | null` (catalog signature). History: cf-49 FRICTION (`…2026-10-cf-49-bug-friction-followup-cards/FRICTION.md` L18) recorded the DEPLOYED v4.1.3 build rejecting `default_checked` on 2026-10-26 ("deploy lag") — that was the old build; the cf-106 C10 deploy chain shipped the current one. Boards L426's "when the deployed build accepts it (probe once)" is satisfied by the signature probe; the createCard rule's `checkItem` extras stay DORMANT independently (§2.4).
- `get_rule` projects `extra_actions`/`extra_triggers`/`enabled` (server.py L144–163) — schema-2 snapshot capture reads through this projection (cf-96 F5 note L148–151).

---

## 8. Test suites that pin this wording (files, run shape, what each pins)

All are standalone bash (`cd $(git rev-parse --show-toplevel)`); run the file, or a subset by id where noted. (Repo note: `helm` lives at `~/.local/bin` — irrelevant to these grep-contract suites.)

| Suite | Run / subset | Windows pinning THIS ticket's wording |
|---|---|---|
| `tests/agent-board-coord/rulesync-surface.sh` | `bash …rulesync-surface.sh` (c1..c22); subset: `bash … c11 c18`; `CHUNK_BASE=` env for base guards | **c11** L665–711: five-checklist window; Services regenerated from `ls services/` (L667–670) + `home-assistant`/`agent context` (L672–674); eleven-item Lifecycle window L689–690; seven-stage nothing-checked default L692; HITL mirror regex L693–694; Model(s) four-option + `Qwen 27b` single-mention cap. **c18** L821–901: Stage-map completeness regex + `stage_tokens` dict (one entry per stage — L847–858, a new stage needs a token entry), transition rule, "never fires" sentence, six board-coord bodies + both boards commands enumerate the five checklists. **c19**: custom-field roster count (currently RED, §9). c10/c16: pickup order / commands |
| `tests/agent-board-coord/agents-md.sh` | `bash …agents-md.sh` (c1..c11) | **c9** L463–485: Lifecycle wording + checked-stages-only in AGENTS.md+rules, Research-checklist-enumeration negative. **c3** L231–245: pickup order + Model(s)-alone. **c11** runner-model paragraph pair (currently RED, §9) |
| `tests/agent-board-coord/gate.sh` | `bash …gate.sh` (t1..t21); subset `bash …gate.sh t17`; header usage L~30 | t11 L712–718: board-facts passage (`AI-Dev`/`In Process`/`Executing`) + the write-tool window `move_card/add_comment/set_card_custom_field/delete_checklist_item/toggle_checklist_item`; L996 area: boards commands checklist enumeration; t17 coord-shell contract (pre-existing red, §9) |
| `tests/cf96-lifecycle/surface.sh` | `bash …surface.sh` (t1..t7) | The whole 11-item design: card-order literal list, Stage map, blank defaults, HITL alignment, transition, cutover, source↔mirror equality (whitespace-normalized). Header L12–27 carries the C07 cross-tree audit of every other pin — the planner's map of re-pin targets |
| `tests/boards-deps/surface.sh` | `bash …surface.sh` (t1..t9) | The dependency-gate wording (blocking types, both-spelling inverse, Test/Finished by TITLE, `_id` keying, archived exemption), preload consumer (claim-time, not the hook; lean stamp; degrade + one retry), grouped siblings (blocking-edges-only trigger, no parentId), follow-up (`set_card_labels` degrade, `parent_id` only lineage) |
| `tests/cf90-ledger/surface.sh` + `readback-runbook.md` | `bash …surface.sh` | Follow-up-card ledger/runbook posture (8 ok today) |
| `tests/coord-inwork/surface.sh` | i-arm suite | i3: boards in-work citation; i4 frontmatter contract (pre-existing red) |
| `tests/kickoff-branch/{script.sh,surface.sh}` | `bash …` | m2/m3: mint strings across six skill files + four coord files (the Session Rename/Worktree stages re-map onto the same text); script.sh is behavior tests for `kickoff-mint-branch.sh` |
| `tests/session-origin/{script.sh,surface.sh}` | `bash …` | s2/s3: claim-once record + boards carry inventory (byte-window over boards text — grows if kickoff bullets grow) |
| `tests/provider-loops/surface.sh` | `bash …surface.sh` | t1: `.agents/loops/pipeline-worker.md` frontmatter shape (currently RED on the model literal, §9) |
| `tests/wekan-mcp/` | each file standalone | `tools.sh` registry arithmetic + `default_checked`/`parent_id` shape (10 ok); `dependencies.sh` the 7-type gate/upsert/preload (11 ok); `slug-stack.sh` the custom-field roster contract (S5 red); `card-details.sh` `get_card_details`; `board-context.sh` hook legs (t6 red via agent-perms A15 roster); `board-provisioning.sh` + `create-list.sh` the four provisioning tools; `rest-overview-v102.sh`/`skill-surface.sh` docs parity; `registry-parity.py` is a **helper with subcommands `counts|claims|rows`** (`tests/wekan-mcp/registry-parity.py:1-16`) — invoked BY the suites; running it bare is a harness misuse, not a red |
| `tests/wekan-board-provision/{surface.sh,checklist-cutover.sh}` | `bash …` | Engine `CHECKLIST_SPEC` vocabulary + artifact + skill citations (both green) — first reds when the vocabulary generation moves |
| Adjacent, also wording-pinned | `tests/cf96-siblings`, `tests/board-preload-probe`, `tests/agent-explore`, `tests/noop-marker`, `tests/cf106-noop`, `tests/multi-repo/repo-label-filter.sh` + `hourly-board-check.sh` + `port-*.sh`, `tests/services/dev-mcp-fleet.sh` | siblings grouping wording; probe script; explore contract; no-op marker; runner loop; Repo-label filter / hourly board-check / sibling-repo ports; dev MCP fleet registration |

## 9. Pre-existing reds at main HEAD `a6e493b78` (ran 2026-11-10; NOT attributable to cf-124)

Failing (7 of the launch-named suites + 2 wekan-mcp):

| Suite | Failing check | Message gist |
|---|---|---|
| `tests/agent-board-coord/gate.sh` | **t17** | `agent-coord.md` shell row `bash scripts/kickoff-warm-location.sh *` not in the pinned coord contract (the documented "warm-location family") |
| `tests/coord-inwork/surface.sh` | **i4** | same frontmatter contract (warm-location family) |
| `tests/kickoff-branch/surface.sh` | **m4** | CONTROL FAILED — splice3 rejects the canonical three-allow form (warm-location family) |
| `tests/session-origin/surface.sh` | **s4** | CONTROL FAILED — splice4 rejects the canonical four-allow form (warm-location family) |
| `tests/agent-board-coord/agents-md.sh` | **c11** | rules/AGENTS pair must name runner model `gpu-ai/qwen3.8-27b-q4` — superseded by the owner ruling 2026-11-09 (`…/cf-106` OQ-14); the loop file now ships `gpu-ai/qwen3.8-flash-next-strata-q4` (`AGENTS.md` L304–308 records the ruling) |
| `tests/provider-loops/surface.sh` | **t1** | same: loop frontmatter model `strata-q4` != pinned `27b-q4` (runner-model family) |
| `tests/agent-board-coord/rulesync-surface.sh` | **c19** | boards skill "still counts exactly two custom fields — the roster is the single slug field" (roster-contract family, pre-dates the Priority flip) |
| `tests/wekan-mcp/slug-stack.sh` | **S5** | same roster family: "bullet counts fields into the agent roster; bullet declares the live Priority field (undeclared by ruling OQ-15)" |
| `tests/wekan-mcp/board-context.sh` | **t6** | fails via embedded agent-perms A15: "the roster counts the retired session field into the agent's roster" (roster family) |

The warm-location family (gate t17 / coord-inwork i4 / session-origin s4 / kickoff-branch m4) is **documented as pre-existing** in `tests/cf96-lifecycle/surface.sh:22–25`. Passing green at HEAD: cf90-ledger (8), cf96-lifecycle (7), boards-deps (9), kickoff-branch/script (8), session-origin/script (7), wekan-board-provision surface (11) + checklist-cutover (11), cf96-siblings (4), board-preload-probe (6), wekan-mcp tools (10) / dependencies (11) / card-details (5) / board-provisioning (9) / create-list (6) / rest-overview (7) / skill-surface (8). (Per-directory runs: AGENTS.md L325 — test basenames duplicate across suites.)

---

## Constraints and gotchas (plan-bound)

- **Generated-surface law**: `.opencode/skills|agents|commands/` + `AGENTS.md` are `rulesync generate` output — edit `.rulesync/` sources only, regenerate, commit sources+generated together; `rulesync generate --check` verifies; a second generate must be a no-op (agents-sync skill). The boards mirror equality is pinned by cf96-lifecycle t7 / rulesync-surface c11.
- **Human-owned board posture**: board-level checklists/rule extras are human-only (boards L58; provision skill L119–130 "never through any REST or MCP call"); labels are human-created; `Finished` never agent-touched; existing-card maintenance is runbook-owned (boards L17) — every card-mutation ask in this ticket lands against this wall; the only sanctioned agent board-write precedent is the owner-directed `/wekan-board-provision` additive apply.
- **Alias-twin equality**: agent-board-coord `-`/`-local`/`-pr` (and coord pairs) must be edited in the same commit; suites parse-equality-check pairs (role-coord L62).
- **Pin-copy, never retype**: the provision engine copies the boards stage names (script L65–68 "the cf96 cutover suite pins the equality and fails loudly on drift"); artifacts/suites follow the cf-96 C07 audit note ("never retype from memory").
- **Permission floors**: no pipeline agent advances/pushes `main`; implementers don't commit (coord commits per chunk); chunk validations sit behind `ask` rows — unattended runs report not-run instead of faking green (role-coord L60). The pipeline-locks plugin owns `.pipeline/` files.
- **Quality gates**: `aislop` via `npx` (vendored skill), `aislop-gate` plugin on edits, CI `aislop ci --changes`; comment hygiene per `comment-slop`. There is no unit-test suite: validation = the bash suites above + grep checks (AGENTS.md L318–325).
- **One plan per piece of work**: the dated plan file is the ticket folder's plan of record (`yyyy-mm-dd-feat-<slug>.md` from `templates/PLAN.md`); `RESEARCH.md`/`EXPLORE.md` ride beside it; fusion is the only second plan file.
- **WeKan rule quirks that bite a defaults redesign**: rule execution order is unspecified (ops L61–70) and `checkItem` is DORMANT upstream (`checkListId` typo, boards L20) — the card's (B) ask (checked Lifecycle/HITL defaults **via the rule**) may be UNIMPLEMENTABLE upstream even with the right artifact; the agent-side `default_checked` on `create_card` is the currently-working check path (deployed build accepts it, §7.3) but only covers agent-created cards. The plan must split "rule declares the items" (works) from "rule pre-ticks them" (dormant).
- **Rule import replaces the rule**: the dense rule replaced the flash one; a new artifact should state whether it re-uses rule id/trigger and that the legacy disabled rule (`iacQY5QxQbPfzjgjR`) stays as history or is removed (human action).
- **Two rules named `Std checklists + defaults` exist live** (one disabled) — the provision engine matches rule titles case-insensitively; a title change in the new artifact changes what the next dry-run calls "drift".

## Questions for planning (none asked to the user, per launch)

1. **Session Rename / Worktree Creation semantics**: these mechanics run in every kickoff before the stage gate today (role-coord step 0). What does an UNchecked box mean — stage genuinely skippable (impossible for the surfaces D10 naming), or "already-done bookkeeping stages" that always run? Do they enter the Blank-defaults seven-stage loop, and where in the Stage map do their rows point (kickoff citation)?
2. **(B) rule defaults vs the two bans**: the card wants checked defaults (incl. `Deployment` — currently OPT-IN-only per L50) on the createCard RULE, but rule `checkItem` is DORMANT upstream and agents can't import rules. Confirm the deliverable is: item vocabulary via rule extras (works), checks via `default_checked` for agent-created cards + a human runbook for the rule (or verify upstream custom/checkItem fix — needs research), and whether the Blank-defaults section must now equal the card's 8-stage list (with Deployment inside? That reverses the L50 ruling — needs a DECISIONS entry) — plus the "Agent Decides vs Pre/Post Research" default wording conflict (card defaults say Agent Decides; fine) and the `Test Writting`/`chunk Review` spelling normalization.
3. **Priority**: with unset already resolving to vLLM priority 5, is the ask (i) cosmetic raw=5, (ii) backfill via `set_card_custom_field` (agent-executed? human runbook? the input-only ban at L269–271), and (iii) a *default* at creation — is there ANY custom-field-capable rule action in v12.65 (needs upstream research; none confirmed in-repo), else default=5 is documentation-only ("null behaves as 5"). Backfill scope: non-archived only (90) vs incl. archived (106), and In-Process-excluded per the card.
4. **Services vs Repo labels**: are the four names `Repo:` coverage (three already exist; is CuratedForest.com a fifth WORKER repo — needs port tests + its own boards copy) or Services non-folder targets (breaks the D9 folder-regeneration story) or both? Live board has zero `Repo:` labels and a `CurateForest.com` list already — is the list the answer? Also fix the two stale docs facts in passing: `Outside Proccess` invariant, and the boards L14 capture missing `Resume Later`/`Farm` lists.
5. **Lock assumption (a)**: continuation-prompt-as-yes — is the resume still the card-id re-claim under `after_reap` (engine unchanged), or does the card want true extension of the ORIGINAL pipeline lock (engine change, currently forbidden: `.reaped/` + "no self-reclaim, ever")? Which prompt counts (any "continue" in a session holding/losing a claim)?
6. **Dependency redesign**: with no inverse for `related-to`, which endpoint is "the card with the dependency"? The #126↔#140 mutual pair deadlocks a naive gate — tie-break rule needed. Satisfaction set: does "moves out of Review" replace the Test/Finished/archived set exactly, and does gating apply only at pickup or to every `move_card` (the sentence "should not move" reads broader than today's pickup-skip)? `fixes` edges from new cards to parents reverse L375/L426 ("parent_id only") — is `parent_id` kept alongside the edge (recommended, it's what the preload carries)? Do the four existing `related-to` edges (incl. this card's own #126→#124) get grandfathered or re-typed?
7. **Backfill execution**: agent-executed per-card checklist rewrite (add 2 items to Lifecycle+HITL on 90 cards, or full re-shape incl. dropping legacy Research/14-item HITL, or leaving legacy per the transition rule) vs a runbook artifact like the rules-import — and does the transition rule (L52–54) need a "cards still carrying 14-item HITL" clause?

RESULT
status: DONE
chunk: exploration
files_changed: [.agents/plans/2026/2026-11-cf-124-feat-checklist-locks-dependency/EXPLORE.md]
commands_run: [git log/branch => pass; grep/read over .rulesync+.opencode+scripts+skills+tests => pass; diff source↔generated boards skill => pass (bodies identical); 25 bash suites at HEAD a6e493b78 => 16 green / 7 red pre-existing + registry-parity bare-call misuse; live dev-boards reads: list_boards, preload_board ×2, list_board_dependencies, list_rules, get_rule ×2, get_card #124, dev-boards tools/catalog probe (39 tools) => pass; zero board writes]
deviations: none
friction: shell background flag needs literal `true` (three rejected calls before shape fixed); preload per-card dict carries no `title` — backfill enumeration must join titles via list-by-list reads or get_card; get_rule projects `extra_actions` (snake_case) — first read mis-parsed the live rule extras as empty.
open_questions: see "Questions for planning" 1–7; needs research: yes — (a) upstream v12.65 rules: any custom-field or working checkItem action (dormant `checkListId` fix status); (b) the four stored `related-to` edges' intended dependency direction and the #126↔#140 mutual-gate hazard; (c) whether the reaped-lock engine may ever extend the original pipeline label vs the card-id takeover.
next_suggested: plan (with the agent-research round for the upstream rule-action question gated on the card's Lifecycle research checks) after the coordinator resolves Questions 1, 2 and 6 in the batched round.
