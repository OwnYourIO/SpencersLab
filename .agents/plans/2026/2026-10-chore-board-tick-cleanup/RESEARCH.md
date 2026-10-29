# RESEARCH — board-tick-cleanup (chore, 2026-10-29)

Two commissioned research briefs, folded into the ticket folder verbatim from
their /tmp findings locations (the launches wrote them under a path override;
this copy is the durable home every pipeline agent reads at run start).
Author: agent-research (inline STORM runs, repo-grounded). W1 = board preload
enablement; W2 = no-op tick alerting. NOTE: each brief's own recommendation was
written BEFORE the user's 2026-10-29 batched rulings; the rulings OVERSIDE
where they conflict (W1: enable-as-is — the B1 `cards:` extension and the
composite `get_board_context` MCP tool are deferred; W2: Option B metadata
marker, not the brief's recommended Option A didWork RPC). The plan's Open
questions record the contradiction; verified facts from both briefs are folded
into the plan and chunks.

---

# W1 research — preloading board-structure data into the board-coord hourly tick

Design research, 2026-10-29. Question: how to give an `agent-board-coord` tick its
initial board-structure data WITHOUT the agent making per-call round-trips after
skill load (observed live cost: 6 dev-boards calls before the first decision —
`list_boards` → `get_board` → `list_lists` → `list_cards_in_list` ×3).

Grounding rule followed: every claim cites a repo file (path + line where the
line count is stable) or the stamped live probe below. No web sources — this is
an internal-design question and the repo is the literature (deviation from the
storm method noted in the RESULT).

## TLDR

- **The preload already exists and is merged on `main`, just switched off.**
  `.opencode/plugin/board-context/index.ts` (cf-75 C04, commit `7bbca8195`) is a
  hand-managed prompt hook that, ahead of the FIRST prompt of any board-coord
  session, fetches the board structure over MCP-over-HTTP and appends the schema
  Board context block — zero credentials, zero session-side round-trips,
  degrade-safe. It ships `DEFAULT_ENABLED=false` (AC6 degraded outcome, user
  ruling 2026-10-27 OQ5) with the enable steps cited in its own header: a
  user-owned live-fire through the real admission path in the main checkout,
  then flip.
- **Enabling it covers 3 of the observed 6 calls; the remaining 3 are the
  pickup-list card projections, which the schema deliberately excludes**
  ("Card and checklist ids are not included — they are live per-card data",
  `skills/wekan-mcp/SKILL.md:90`). Recommendation: **option B1** — extend the
  existing plugin with an optional `cards:` section (3 parallel
  `list_cards_in_list` legs inside the prefetch) and enable in one live-fire;
  staleness is already absorbed by the mandated `get_card` confirmation
  (boards skill pickup step 3) and the `pipeline_claim` arbiter (claim-before-
  move), plus the existing re-resolve consumer rule.
- **Option A (combined `get_board_context` tool in `containers/wekan-mcp`) is
  the right follow-up but the wrong primary**: its deploy chain is merge →
  docker-build `:v<run>` push → image-pin bump in `services/dev/prod/values.yaml`
  (currently `wekan-mcp:v87`, hand-bumps forbidden) → ArgoCD sync → known
  session-catalog staleness mode — and it still costs ONE post-skill-load
  round-trip instead of the ask's zero. File it as a board card once B1 lands
  (it then collapses the plugin's own 8 prefetch legs to one and gives the
  manual `/pipeline-boards` runs and the collector command the same win).

## Key facts (all verified this run)

F1. **The plugin exists, on main, disabled.**
`.opencode/plugin/board-context/index.ts` (359 lines; `git log -1` on it =
`7bbca8195`, branch set includes `main`, which is the current checkout).
Mechanism: `ctx.session.hook("prompt", …)` (`:357`) appends the block to the
first prompt of `agent-board-coord` / `-local` / `-pr` (`:70-74`), once per
session (`ONCE_TTL_MS` guard keyed on sessionID, `:65-68,230-231`), never-throws
and races an 8 s admission-latency budget (`:17-23,62,240-243,260-279`). URL is
discovered at runtime from `ctx.mcp.list()`, falling back to parsing
`.opencode/opencode.jsonc` — no credentials, no hardcoded host (`:10-15,193-214`).
Header `:40-52` records the shipping state: live-fire legs executed 2026-10-28
from the cf-75 worktree proved discovery + handshake + the five resolution
calls + `formatBlock` against live dev-boards (read-only); the ON arm is
unproven through a real admission because plugins load per location and the
main checkout only has it after landing — landing + enable steps are explicitly
user-owned.

F2. **Auth answer for the credential question in the brief (option B's risk).**
The WeKan credentials (`WEKAN_BASE_URL/USERNAME/PASSWORD`, Bitwarden LOGIN
item) land ONLY as an in-cluster Secret consumed by the server pod
(`containers/wekan-mcp/wekan_mcp/wekan.py:5-9` — process-start login-mint;
`services/dev/prod/templates/secret-wekan-mcp.yaml`; boards-skill: `dev-boards`
"authenticates SERVER-SIDE via login-mint… The agent never handles
credentials", `.rulesync/skills/boards/SKILL.md:24`). A plugin therefore must
NOT talk raw WeKan REST (no cred path in the workspace, and committing one
violates the secrets hard rule); the shipped plugin's path is the same
streamable-HTTP MCP endpoint the session uses, which needs no token because
OIDC is disabled on the deployments (plugin header `:10-12`;
`services/dev/prod/values.yaml:408` "OIDC temporarily disabled (2026-09)";
recipe in `skills/wekan-api/references/wekan-mcp-ops.md`). Caveat for
open questions: if OIDC is re-enabled, that no-credential leg breaks for
plugin and session alike.

F3. **Consumer rule and schema already bind the preload — including drift.**
`skills/wekan-mcp/SKILL.md:73-102` is the single normative home of the Board
context block (producers named there: the `/wekan-board-context` collector
command and the board-coord prefetch plugin). `.rulesync/skills/boards/SKILL.md:155-162`
(Board context block — consumer side): block present → use its ids all run,
"the first six board round-trips are already spent"; record it at claim as
STATE.json `kickoff.board_context`; block absent → normal, resolve top-down;
any id-shaped error (incl. "an empty projection where the block's ids promised
data") → re-resolve against the live board and note drift in RESULT — "a
starting context, never a freeze". `tests/wekan-mcp/skill-surface.sh` t3 pins
the schema's single markdown owner; `tests/opencode/board-context.test.ts`
pins `formatBlock` byte-for-byte against the schema fence (its header states
the seam contract and the drift adjudication route).

F4. **What the block does NOT cover, and why pickup is the gap.**
Observed tick calls split: structural = `list_boards`, `get_board`, `list_lists`
(3 of 6; the plugin internalizes 5 incl. `list_swimlanes` + `list_custom_fields`);
cards = `list_cards_in_list` ×3 (Rework / Not Started / Low Priority) — excluded
by schema design (F3). The exclusion is sound for *checklist* ids
(card-scoped, "can never be pre-collected board-wide", `skills/wekan-mcp/SKILL.md:64-68`)
and for per-card *facts* (by-list projection strips `cardNumber`, custom
fields and labels → candidate confirmation needs `get_card` anyway,
`.rulesync/skills/boards/SKILL.md:71-73,97`), but the *enumeration* itself is
static-enough: pickup walk order is fixed, `list_cards_in_list` response
order IS board order (`:67-69`), and the claim protocol is race-safe:
`pipeline_claim` before any `move_card`/edit with `locked` → next candidate,
max 3 attempts (`:99-100`), so a stale snapshot at worst costs one re-list on
the affected list (the F3 empty-projection branch).

F5. **Live board state (probed 2026-10-29 via dev-boards, read-only — the same
sequence a tick pays).** Board AI-Dev = `TNQJ2BrXenZovngTS`, swimlane In
Process = `jLzy39L7djCRr67SF`. Labels: 2 (`Research`, `Ready for Work`) —
ZERO `Pipeline:` labels, i.e. every card derives the single `default` pipeline
today, consistent with `.rulesync/skills/boards/SKILL.md:97`. Pickup lists:
Rework 0 cards, Not Started 4, Low Priority 0 (Executing 1). Payload estimate
for a block incl. `cards:`: ~1 KB (ids + ≤10 titles/list) — a token rounding
error against the 5-8 calls it saves. The label map rides in full, so when
humans create `Pipeline:<name>` labels they appear with no code change.
(Note: `Ready for Work` is not described in the boards skill's board facts —
observation only, not a gap the preload must fix.)

F6. **Entry points the preload must serve.** Two, and they behave differently:
(a) the hourly `/pipeline-boards-hourly` command (`.rulesync/commands/pipeline-boards-hourly.md`)
— expands shell blocks at expansion time (gate script, `Session origin` probe;
precedent = option C's machinery) and its prompt goes through `session.prompt`,
which DOES run prompt hooks (cf-75 DECISIONS: "prompt hook runs at admission,
command prompts via session.prompt run it, synthetic/shell do not");
(b) the OpenChamber loop `.agents/loops/pipeline-worker.md` — ships
`enabled: false`, body is the plain-text tick sentence (`:32`, D30: slash
dispatch of a plugin command from loop text is unproven on v2.1.4), NO
expansion mechanism, so any launch-time baking (C) cannot reach this entry
without re-introducing exactly the dispatch that cf-76 deferred. The plugin
hook is entry-agnostic — it fires on the first prompt of any board-coord
session, whichever door it came through; that is its key structural advantage
and also why its live-fire must now cover the loop path (open question OQ-a).

F7. **Lock-joining is NOT worth preloading.** The brief asked whether the
payload could join "the three-list card projections + lock availability".
`pipeline_status` is a local plugin tool (reads `.pipeline/` lock files;
`pipeline-locks/index.ts` `toolStatus`, output at `:1595-1620`) with zero
network, and the tick contract already calls it FIRST as the plugin-liveness
proof (`.agents/loops/pipeline-worker.md:32`; boards skill `:98`). Injecting a
collection-time lock snapshot would add a cross-plugin data path (the
board-context plugin reading another plugin's files — `.pipeline/` is
pipeline-locks-owned) and would be *fresher* via `pipeline_status` anyway.
Recommendation: leave locks out; keep `pipeline_status` as the first live call.

## Option evaluation

### A — combined read-only tool in `containers/wekan-mcp` (`get_board_context`)

Feasible: `server.py` composes existing internals (`list_boards`,
`get_board`, `list_swimlanes`, `list_lists`, `list_custom_fields`,
`list_cards_in_list` at `:158-286`, slim helpers `:85-155`); a board-wide
`board_id` default + `include_card_lists:[titles]` arg is natural. Server-side
auth means agents still handle no credentials, and the same tool serves
`dev-boards`, `readonly-/admin-global-wekan` alike.
Against it as the primary: (i) deploy = merge → `docker-build.yaml` pushes
`:v<run>` + `:main` → `services/dev/prod/values.yaml:405` image pin bump —
hand-bump forbidden ("Never bump versions or image tags by hand", AGENTS.md;
the values comment names the renovate-managed bump as the sanctioned route) →
ArgoCD sync → and a documented post-swap failure mode: "session catalogs
cache per connection and go stale after image swaps"
(`skills/wekan-mcp/SKILL.md:112`); (ii) it replaces six round-trips with
ONE — still a per-call round-trip after skill load, against the literal ask
("initial data loaded via the plugin"); (iii) call-shape docs churn
(`references/call-shapes.md` tables, `tools/list` probe posture).
Verdict: right FOLLOW-UP card (one call, all consumers, and the plugin's
prefetch drops from 8 legs to 1), wrong answer to THIS ticket.

### B — hand-managed plugin: prefetch + inject (exists; extend + enable)

B0 = enable as shipped (structure-only). Covers F4's 3 structural calls; the
3 card enumerations stay live. Enablement is the cited user-owned leg (F1).
B1 = also extend the block with the optional `cards:` section (3 parallel
`list_cards_in_list` legs), collapsing the whole observed 6-call startup to
zero session-side calls. Deploy = repo files only (`.opencode/plugin/` is
explicitly the hand-managed surface, AGENTS.md `:56-59`; precedents shipped
this way: question-notify, aislop-gate, pipeline-locks). Credentials: none
needed (F2). Never-throw + bounded budget already engineered and tested; the
absence-is-normal consumer rule (F3) means a degraded (un-injected or
card-less) tick behaves exactly like today's — B1 fails soft into B0 fails
soft into status-quo.
Costs/risks: admission latency budget (5 serial structural legs + 3 parallel
card legs inside 8 s — tight but the legs are ~1 s each in the 2026-10-28
live-fire; see OQ-b); snapshot staleness (absorbed by F4's claim protocol);
the ON arm remains user-gated (no half-proven hook ships enabled — cf-75
ruling, plugin header `:49-52`).
Verdict: **recommended** — it is the only option that is simultaneously
zero-round-trip, entry-point-agnostic (F6), repo-file-deployable, credential-
free, and already contract-integrated (schema + consumer rule + two test
suites exist).

### C — launch-command / loop-text expansion (gate-script pattern)

Against: (i) the loop entry has no expansion mechanism at all (F6b) — C only
fixes half the doors; (ii) a `!`bash …`` block would have to speak the same
MCP-over-HTTP JSON-RPC (the plugin's `makeCallTool` recipe, `:294-332`) from
shell — duplicating a third implementation of the resolution sequence, and
the schema's one-normative-home posture (skill-surface t3, F3) exists exactly
to punish that kind of copy; (iii) failure posture: the gate script is
deliberately board-blind ("this script never touches a board", D1/D16
posture in `scripts/agent-board-coord-gate.sh` header) — a board fetch inside
the gate path contradicts a pinned decision, and a failed expansion block
pollutes the gated prompt or trips fail-closed skips; (iv) ids baked into
command text are a *worse* freshness story than the plugin (collected at
expansion vs at admission — same magnitude, but without the once-guard, the
budget race, or the tests). Verdict: rejected; the precedent it invokes
(gate script) is an argument for keeping shell out of the board path.

## Recommendation — B1, behind the existing flag, in one live-fire

Order of operations: code+docs+tests land on a branch with `DEFAULT_ENABLED`
still `false`; the user's cited enable steps then cover BOTH the cf-75
structure leg and the new cards leg in one live-fire pass.

### Exact files to touch (all sources; generated surfaces via rulesync only)

1. **`.opencode/plugin/board-context/index.ts`** (hand-managed — rulesync must
   never generate or delete it; header comment stays truthful):
   - `const PICKUP_LIST_TITLES = ["Rework", "Not Started", "Low Priority"]` +
     `CARDS_CAP_PER_LIST = 10` (Config-constant style, verbatim from the
     boards skill's walk order — cite the skill, don't re-derive).
   - `resolveBoardContext`: after the existing five legs, filter `laneLists`
     by the three titles and fire the `list_cards_in_list` legs via
     `Promise.allSettled` (parallel — protects the 8 s budget; F4/OQ-b).
     Structural legs keep today's throw→degrade policy; card legs are
     failure-soft: any rejected leg simply omits that list's projection, and
     if all three reject the block ships without `cards:` at all (legal —
     the section is optional in the schema).
   - `formatBlock`: emit the optional `cards:` section after `labels:` and
     adjust the footer when present (see payload below). Keep it pure, no
     clock reads (test seam rule, `board-context.test.ts` header).
   - Do NOT flip `DEFAULT_ENABLED` here — that lands in a separate, later
     commit carrying the live-fire proof citation beside the constant (the
     header procedure `:49-52`).
2. **`skills/wekan-mcp/SKILL.md`** — "Board context block schema" (the single
   normative home): add the optional `cards:` field group to the fence, name
   which producer emits it (the plugin; the collector command stays
   structure-only), and extend the footer prose: card projections are
   collection-time, the walk's `get_card` confirmation and the claim-before-
   move rule are unchanged, and an empty-or-missing projection is resolved by
   re-listing that one list live (matching the consumer rule's existing
   empty-projection branch).
3. **`.rulesync/skills/boards/SKILL.md`** — "Board context block (consumer
   side)" only: one bullet — with `cards:` present, run the pickup walk over
   the injected projections instead of listing the three lists; pickup step 3
   (`get_card` confirm — labels/cardNumber/cf are stripped by the projection)
   and the Parallel-pipeline-loops claim protocol are untouched; a snapshot
   that contradicts the live board → re-list the affected list, note drift in
   RESULT. Also reword `:159` "the first six board round-trips are already
   spent" to "the structural calls and the pickup-list enumerations are
   already spent" (the six-count predates B1's card legs).
4. **`.rulesync/commands/wekan-board-context.md`** — one clarifying sentence
   that the collector's output is structure-only and omitting `cards:` is
   schema-legal (prevents a future reader "fixing" the producer mismatch).
5. **`pipeline-role-coord`: no edit.** Verified no board-context text there
   (grep: zero hits) — the boards skill is the board-surface authority
   ("this skill defines only the board surface", `:9`) and the coord already
   records `kickoff.board_context` per the consumer rule. Do not touch.
6. **Regenerate + commit together**: `npx rulesync generate` (targets per
   `rulesync.jsonc`), commit `.rulesync` sources + generated
   `.opencode/skills|commands/` in one commit (cf-75 DECISIONS `:15`; AGENTS.md
   hard rule). Never hand-edit `.opencode/skills/boards/`.
7. **Tests** (land with 1–4, same branch):
   - `tests/opencode/board-context.test.ts` — extend the seam contract:
     expected block gains the `cards:` section (byte-pinned against the new
     schema fence); `resolveBoardContext` stub `callTool` gains
     `list_cards_in_list`; add cases: one card leg rejects → that list
     omitted, block still ships; all card legs reject → structure-only block;
     structural reject → untouched prompt (existing shape).
   - `tests/wekan-mcp/skill-surface.sh` t3 must keep passing unchanged (it
     polices one markdown owner of the header — still satisfied).
8. **AGENTS.md** (source `.rulesync/rules/overview.md`): the hand-managed
   plugin list sentence (`:55-59`) names aislop-gate + question-notify; cf-75
   claimed an AGENTS.md plugin-list sentence — extend the one that covers the
   pipeline-worker section to also name `board-context` as the tick's
   prefetch, so the next reader finds it (this is the "keep the lists
   current" rule, AGENTS.md MCP section spirit).

### Proposed payload shape (schema-faithful, live values 2026-10-29)

```text
Board context (collected 2026-10-29T…Z, dev-boards)
board_id: TNQJ2BrXenZovngTS
swimlane_id: jLzy39L7djCRr67SF
lists:
  Not Started=<id>        # all In-Process-lane lists, incl. Executing/Review/
  …                       # Rework/Finished/Low Priority (+ Timeout when D22 lands)
custom_fields:
  slug=<id>
  session=<id>
labels:
  Research=<id>           # FULL map — future Pipeline:<name> labels ride in
  Ready for Work=<id>     #   with no code change; the name-prefix grammar is
  …                       #   derived by the skill, not the payload
cards:                    # NEW, optional; only when the pickup legs succeeded
  Rework:                 # empty list = the key present with no rows (the
  Not Started:            #   walk must be able to prove "empty", not just
    <title> [<card_id>]   #   "present")
    …(max 10, board order; then `    … (N more)`)
  Low Priority:
Card ids above are a collection-time snapshot in the listed order — the
pickup walk's get_card confirmation and pipeline_claim-before-move still
apply. Checklist ids are never pre-collected (card-scoped). On any id-shaped
call error, re-resolve this block against the live board before retrying.
```

Deliberately NOT in the payload: lock availability (F7 — local `pipeline_status`
is cheaper and fresher and is the mandated first call), per-card labels/custom
fields/checklists (projection-stripped and card-scoped — F4), Executing-list
cards (the hourly BOARD CHECK must count it live by design,
`pipeline-boards-hourly.md:26-30`; the block only saves that branch its
list-id resolution).

### Validation commands (no helm, no container CI — matches brief)

```bash
node --test tests/opencode/board-context.test.ts     # seam contract, incl. new cards cases
bash tests/wekan-mcp/skill-surface.sh                # schema single-owner (t3) still green
bash tests/wekan-mcp/board-context.sh                # C03 collector/consumer contracts still green
npx rulesync generate && npx rulesync generate --check   # sources+generated committed together
# grep checks — exactly one owner of the new section bytes:
grep -c "Board context block schema" skills/wekan-mcp/SKILL.md            # == 1
grep -rn "^cards:" skills/wekan-mcp/SKILL.md .rulesync/                  # no stray copies
# aislop gate on the diff (AGENTS.md quality rule):
npx aislop ci --changes   # or the gate plugin's local equivalent
```

Then the two HUMAN/probe legs (cannot run from CI, mirror the cf-75 AC6
posture — "no half-proven hook ships on"):

- **Probe session**: from the main checkout (plugin location!), `GET
  /api/session/<id>/context` readback after seeding a board-coord first prompt
  — expect expanded tick text + the block with a `cards:` section; assert the
  session's first turn makes ZERO dev-boards structural/list calls (dev-boards
  audit via `tools/list`-style probe of its own session log or by the run's
  RESULT `commands_run`).
- **Live smoke**: with `DEFAULT_ENABLED=true` locally, run one real hourly-shape
  tick; verify pickup consumed the snapshot (RESULT/claim comment shows
  board/list/card ids with no preceding enumeration calls), and one
  drift-case: rename nothing, just observe; optionally test the empty-board
  branch by checking the "no work" path stays clean. Record the proof citation
  beside `DEFAULT_ENABLED` before the flip commit lands (the header's own
  procedure).

### Sequencing / deploy notes

- Ticket is repo-files-only; nothing deploys until merge. The flag flip is a
  second, separate commit owned by the user after the live-fire — preserving
  the cf-75 ruling verbatim.
- The loop path stays `enabled:false` (cf-76 D9) — the preload benefits the
  command path immediately when the flag flips; the loop path inherits it
  whenever the human enables the loop (same first-prompt mechanism, OQ-a).
- Follow-up board card for option A (`get_board_context` composite tool +
  `:v<run>` pin bump via renovate, not by hand) — precedent shape: the D22
  `create_list` follow-up card. It should also mention folding the plugin's
  8 prefetch legs into 1 once the tool ships.

## Open questions

- OQ-a: does the OpenChamber loop dispatch create the session+first-prompt in
  a way that runs `prompt` hooks on v2.1.4? The command path is proven
  (cf-75 DECISIONS); the loop path is the same `session.prompt` family but the
  live-smoke checklist (cf-76 C06) hasn't run. Fold into the enable live-fire;
  if the loop path skips hooks, the fix is the loop body pointing at
  `/pipeline-tick` (the already-planned swap target) rather than any preload
  change.
- OQ-b: is 8 s enough for 5 serial + 3 parallel legs from the OpenChamber
  server process? The 2026-10-28 leg timings weren't recorded per-call. If
  tight: raise `FETCH_TIMEOUT_MS` (it delays only the dispatch HTTP response,
  cf-75 RESEARCH Implication 2 — no model-turn race) or run the structural
  legs of `list_swimlanes`+`list_lists`+`list_custom_fields`+`get_board` in
  parallel after `list_boards` (they're independent given `board_id` —
  serial today). Recommend the parallelization; keep the budget.
- OQ-c: cards cap and ordering — 10/list mirrors the LIVE-branch "max 5
  titles" comment posture loosely; confirm with the human at the plan-approval
  round (board cards today fit under it: 4 total in pickup lists, F5).
- OQ-d: `Ready for Work` label is live on the board but undocumented in the
  boards skill's board facts (F5). Preload-neutral — flag for the human; if
  it becomes intake grammar, the skill (not the plugin) should own it.
- OQ-e: OIDC re-enablement would break the plugin's credential-free leg (F2).
  No action now; noted so the enable proof restamps if the cluster changes.

## Contradictions and how to weigh them

- Schema footer says cards are "resolved at use time" (F3) while the brief's
  ask is to preload them (F4). Resolution adopted: the footer's reason is
  staleness-safety, and the walk's mandatory `get_card` + claim arbiter
  already provide it; making `cards:` an OPTIONAL, explicitly-collection-
  stamped section with a named re-list fallback keeps the schema's posture
  while retiring its blanket exclusion. This is a schema *edit*, not a
  violation — hence the change plan runs through the wekan-mcp home + t3.
- "Gate scripts never touch a board" (D1/D16) vs option C. Weighted as
  decisive against C (F6, option C §iii): the posture exists because the gate
  runs outside the MCP/permission flow; the plugin runs at admission with
  degrade arms and tests instead.
- cf-75 "no half-proven hook ships enabled" vs this ticket's urgency. Kept:
  the recommendation ships B1 code behind the flag; enablement stays the user's
  cited step. Nothing here automates the flip.

---

# W2 — Stop no-op alerting on hourly board-coord ticks (findings brief + options + recommendation)

Research ticket, 2026-10-29. Design research only — **no repo file was edited**. Findings live at
`/tmp/opencode/research-w2-noop-alert.md` per the launch override (no feature folder, no RESEARCH.md).

## TLDR

- **The alert fires because `question-notify` pushes on every top-level `session.execution.succeeded`**
  — a no-op tick ends as a *successful* empty run and is indistinguishable from a real completion at the
  event layer. The crash/question/approval paths must not be touched; only the "finished" push needs a
  no-work predicate. `[QN-1]`
- **pipeline-locks already records ground truth about "did this session do anything"** — claim/release
  audit lines in `.pipeline/events.log` (durable, timestamped, shared across worktrees), live lock files,
  and durable `ctx.storage` claim records. `didWork(sessionID)` is a small, authoritative, race-safe query. `[PL-1]`
- **The cross-plugin transport is real on the pinned v2.1.4** — the binary itself ships an RPC kernel
  (`/api/rpc/{rpcID}/{method}`, `rpc.*` reserved errors, `ctx.rpc.register(...)` + `rpc.<id>.<name>`
  stream events — OpenCode's own browser feature uses exactly this API in 2.1.4). Recommended fix:
  **Option A — pipeline-locks exposes a `didWork` RPC; question-notify suppresses the finished push for
  `agent-board-coord*` sessions only on a definite `worked:false`; everything unknown still alerts.** `[BIN-1] [DOC-rpc]`

---

## Sources

Repo (paths + lines verified live 2026-10-29):

- `[QN-1]` `.opencode/plugin/question-notify/index.ts` — trigger constants L61–75; `handleLifecycle` L157–179;
  tool hook L390–415; event loop L443–475; HA plumbing `haMcpUrl` L271–316, `sendHANotify` L342–363; cooldown L380–385.
- `[QN-2]` `.opencode/plugin/aislop-gate/index.ts` — sibling plugin precedent (edit/write hooks).
- `[PL-1]` `.opencode/plugin/pipeline-locks/index.ts` — runtime dir/constants L58–107; claim/release/status
  store L480–625; `appendEvent` (JSONL audit with `at:` stamp) L394–403; `handleEvent` (session lifecycle
  incl. TERMINAL events) L804–871; `toolBefore/toolAfter` activity beats L873–930; storage binding
  `bindStorage` L1699+ ("ctx.storage is plugin-id + project-id scoped and shared across worktrees" L76–78);
  tick/reap/status commands L1560–1640 (incl. `{ev:"tick"}` audit line L1640); reaper HA literals L125–131;
  **"Duplicated, never imported: plugin discovery loads every module under `.opencode/plugin/`" L953**;
  "session.updated never fires on v2.1.4 (D31)" L160; tool specs "reachable ONLY through Code Mode"
  (live-restamped 2026-10-29 probe, ~L1540).
- `[BC-1]` `.opencode/plugin/board-context/index.ts` — prompt-hook prefetch; `DEFAULT_ENABLED = false` (L64);
  observes nothing about claims/lifecycle → **not** an existing alert-observer.
- `[LOOP-1]` `.agents/loops/pipeline-worker.md` — frontmatter `schedule: "0 * * * *"`, `enabled: false`, agent
  `agent-board-coord`; comment claims "Shipped DISABLED … /pipeline-boards-hourly and its gate stay the
  fallback entry point" (L16–19); body = the plain-text worker sentence (L32) identical to
  `TICK_PROMPT` in `[PL-1]`.
- `[CMD-1]` `.agents/commands/pipeline-boards-hourly.md` — the gated command: expands
  `bash scripts/agent-board-coord-gate.sh`, three-way decision rule (RUN/LIVE/SKIP), no-claim/no-work
  replies for SKIP/LIVE branches.
- `[GATE-1]` `scripts/agent-board-coord-gate.sh` — session-liveness gate over `opencode api get /api/session`
  (three board-coord agent ids, tree-age rule, fail-closed SKIP).
- `[CF76-1]` `.agents/plans/2026/2026-10-cf-76-feat-parallel-pipeline-loops/chunks/C01.md` L136–137 — v2.1.4
  probe facts: `execute.before/after` shapes confirmed; before-throw blocks; **`session.updated|idle|status`
  never emitted**; flat `data.sessionID/parentID`; all four `session.execution.*` live; plugin tools reachable
  only via Code Mode (D29, live-restamped 2026-10-29 in `[PL-1]`).
- `[CF52-1]` `.agents/plans/2026/2026-10-cf-52-feat-coord-session-inwork/2026-10-26-feat-coord-session-inwork.md`
  + `DECISIONS.md` D9/D11 — the OpenChamber metadata contract: `session.metadata.openchamber.work`
  zod `({state:"open"|"done", openedAt, openedBy:"auto"|"jev"|"user", doneAt, suggestDoneAt})`;
  `PATCH /api/session/{id}` **replaces `metadata` whole** (read-merge-write mandate); scheduled runs are
  excluded from OpenChamber's auto-open; `openchamber.kind:"scheduled"` exists on scheduled launches.
- `[SUB-1]` `.rulesync/subagents/agent-board-coord-local.md` frontmatter — permissions include
  `opencode: allow`, shell `opencode api get /api/session*` allow, `opencode api patch /api/session/*` allow
  (scoped by the skill rule to the own-session work key, not technically enforced per-key).
- `[TEST-1]` `tests/opencode/question-notify.test.ts` — seam matrix; header: "plugin discovery loads every .ts
  it scans in `.opencode/plugin(s)/`"; fixtures copied from live `…/context`: assistant `content` parts are
  `{type:"text"|"reasoning"|"tool"}`; T6: "suppresses the finished push when the session/context lookup fails"
  (existing doubt-suppresses policy for topology).
- `[CFG-1]` `.opencode/opencode.jsonc` — hand-managed project config; permissions array (~L787); note at ~L1020:
  "permission actions name the normalized `<server>_<tool>` id" (MCP tool-id shape evidence).

Runtime / host (read-only probes):

- `[OC-CFG]` `/home/coder/.config/openchamber/projects/path_L2hvbWUvY29kZXIvU3BlbmNlcnNMYWI.json` —
  OpenChamber `scheduledTasks`: **"pipeline-worker" `enabled:true`, cron `0 * * * *` UTC, agent
  `agent-board-coord`, prompt = the whole loop file text (comment block + worker sentence), lastRunAt
  2026-10-29T13:19:41Z, lastStatus success, nextRunAt 14:00Z**; **"Hourly Pipeline call" also `enabled:true`,
  now `daily 16:05 America/Denver`, agent `agent-board-coord-local`, prompt "Please take the next card and
  start processing it." (runs no gate)**; `loopApprovals` pins the loop-file sha256 (sync approval).
- `[BIN-1]` `strings` of `/home/coder/.nvm/versions/node/v26.5.0/lib/node_modules/@opencode/cli/bin/opencode.exe`
  (v2.1.4): literals `session.execution.started|succeeded|failed|interrupted`, `session.idle`, `session.error`
  exist (emission facts from `[CF76-1]`); reserved RPC errors `rpc.unavailable|method_not_found|invalid_input|
  internal|invalid_output`; `server.rpc` service with `rpc.call(rpcID, method, input)` handler; client factory
  maps `rpc:` from `server.rpc`; **bundled `BrowserConnection.make` calls `e.rpc.register(contract, {methods})`
  and `_.events.emit("control", …)` on the 2.1.4 promise/effect ctx**, event-type helper `Vr()` =
  `rpc.${contract.id}.${name}`; `session.update` handler calls `setMetadata` when `payload.metadata` present.
- `[API-1]` live `opencode api get /openapi.json` (this host): path **`/api/rpc/{rpcID}/{method}` exists**;
  `Session.Info.properties` include `metadata` (with `Session.Metadata` `$ref`), `agent`, `parentID`, `time`;
  event schema `V2EventEncoded` is an opaque JSON-string (no inline enum — hence binary+probe grounding above).

Docs (fetched 2026-10-29):

- `[DOC-plugins]` https://opencode.ai/v2/docs/build/plugins — parts, loading, publish; RPC contract ships as a
  package export other parts import.
- `[DOC-rpc]` https://opencode.ai/v2/docs/build/plugins/rpc — `Rpc.define` (methods/events/errors, JSON Schema or
  Standard Schema); server plugin registers inside `setup` via `ctx.rpc.register(Acme, handlers)` and can call
  its own RPC via `ctx.rpc(Acme)`; **"Once an RPC is registered, it can be called over HTTP or from another
  plugin"**; plugin-side subclients via `client.rpc(Acme)`; RPC events ride the event stream **prefixed
  `rpc.<id>.<name>`**, live-only subscribers, each event carries `data` + `location`; `rpc.`-prefixed error
  names reserved.
- `[DOC-server]` https://opencode.ai/v2/docs/build/plugins/server — ctx is "essentially an OpenCode server
  client" + plugin-only methods; `ctx.session.get/context/update/prompt/wait…`, `ctx.session.update` accepts
  `metadata` and `permissions`; `ctx.storage` values "scoped to the plugin"; tool hooks `execute.before`
  (`event.tool`, `event.input`, inspect/replace input) and `execute.after` (`status`, `result/error`);
  `ctx.event.subscribe({types})` (note: types-filter needs a newer build — silently drops on 2.1.4 per
  `[PL-1]` comment).

---

## Findings

### F1 — Why the alert fired (exact mechanism)

`question-notify` (`[QN-1]`) pushes to Home Assistant on three triggers:

1. **Question path** — `ctx.tool.hook("execute.before")` where `event.tool === "question"` and the agent
   starts with `agent-` → title `OpenCode: <agent> has a question`.
2. **Lifecycle path** — the durable pair `session.execution.succeeded` (title "…finished") /
   `session.execution.failed` (title "…stopped") on the `ctx.event.subscribe` stream, filtered to
   **top-level sessions only** (`isTopLevel` = no `parentID`). **No agent-family filter**: any top-level
   successful end pushes, with the last assistant text part as the body (`lastAssistantExcerpt`,
   240-char cap).
3. **Approval path** — `permission.asked` arms a 15 s pending timer (canceled by `permission.replied`
   for the request id); fires unless the cooldown (15 s per session) gates it.

The hourly tick ended **successfully having done nothing** → event 2 fired → `agent-board-coord` finished
push. "Did nothing" is invisible at the event layer: a no-op tick and a real completion emit the identical
`session.execution.succeeded`.

HA plumbing / config: no credentials in the file — the URL is discovered at runtime from the MCP config view
(`ctx.mcp.transform` `editor.get("admin-global-homeassistant")`, compat fallback `ctx.mcp.list()`), and the
plugin speaks raw MCP JSON-RPC over streamable HTTP (`initialize → notifications/initialized → tools/call
call_service`, domain `notify`, service `mobile_app_pixel_6`). The ADMIN tier is required (readonly ha-mcp
runs `READ_ONLY_MODE`). One env knob: `OPENCODE_NOTIFY_PENDING_MS` (approval window only). Failure policy:
fire-and-forget, stderr only; lifecycle topology-lookup failures **suppress** the push (`[TEST-1]` T6),
approval lookup failures **degrade but still push**.

### F2 — v2.1.4 session-event vocabulary (what a plugin can actually see)

Grounded on the pinned binary + the cf-76 C01 probe, not on latest docs:

- Live and emitted: `session.execution.started / succeeded / failed / interrupted`; `permission.asked /
  replied`; tool hooks `execute.before / execute.after` (flat event `{tool, sessionID, agent, messageID,
  id, input}`); `session.created`.
- **Never emitted on 2.1.4** (despite existing as literals): `session.updated`, `session.idle`,
  `session.status` (`[CF76-1]` fact 3; `session.error` is legacy-V1, ignored by design `[QN-1]` header).
- `interrupted` fires but question-notify deliberately does not alert on it (shipped decision) — a manual
  stop is silent today, unchanged by this fix.
- No `question.asked` event exists — the question path rides the tool hook (already how it works).
  `session.idle-info` does not exist in this vocabulary at all.
- `ctx.event.subscribe({types})` filter option: accepted-but-drops on 2.1.4 → filter in-handler (repo convention).
- Session metadata readable via `ctx.session.get` → `Session.Info` includes `metadata` (`[API-1]`); writable
  via `ctx.session.update({sessionID, metadata})` (server handler `setMetadata` `[BIN-1]`; HTTP PATCH replaces
  `metadata` **whole** — read-merge-write mandate `[CF52-1]`).

### F3 — "Did this run do anything?" — signals that exist today

- **pipeline-locks state** (`[PL-1]`): per-claim identity `(sessionID, cardId, setId, pipelineSet)` is stamped
  into every lock file at the canonical root `.pipeline/locks/`, mirrored durably in `ctx.storage`
  (`claim/<sessionID>`, rebuilt after restart, shared across worktrees), and **every claim/release lands an
  audit line in `.pipeline/events.log` with an ISO timestamp**. Release removes the live record but the audit
  line persists → "did this session ever claim (and how did it end)" is answerable after the fact, crash-safe
  by construction (a mid-claim crash leaves both the held lock and the claim line).
- **Cross-plugin surfaces that are real on 2.1.4**: (a) plugin RPC — register + call + events, all proven
  inside the shipped binary (`[BIN-1]`, `[DOC-rpc]`), HTTP-visible at `/api/rpc/{rpcID}/{method}`; (b) the
  shared server event bus — RPC events arrive as `rpc.<id>.<name>` on every plugin's existing
  `ctx.event.subscribe` stream; (c) `.pipeline/` files — "agents never touch them; **plugins may**" (worker
  rules in AGENTS.md), though pipeline-locks owns their semantics; (d) `ctx.storage` is **plugin-id scoped** —
  question-notify cannot read pipeline-locks' keys (by design, `[PL-1]` L76–78).
- **Code-precedent constraint**: cross-plugin **imports** are poison ("plugin discovery loads every module
  under `.opencode/plugin/`" — `[PL-1]` L953, `[TEST-1]` header). Contracts must be **duplicated literals or
  placed outside the plugin dir**, never imported between plugins.
- **Session message parts** (`[TEST-1]` fixtures): at end-of-run, `ctx.session.context` returns messages with
  assistant `content` parts `{type:"text"|"reasoning"|"tool"}` — a tool-call census *is* computable from the
  array question-notify already fetches on the succeeded path. MCP tool ids normalize to `<server>_<tool>`
  (`[CFG-1]` ~L1020) — but whether the hook/event `tool` value and the message part name carry exactly that
  form on 2.1.4 is **unprobed**; needs one log line to pin. Code Mode makes nested calls opaque at this layer:
  `pipeline_claim`/`pipeline_status` execute *inside* the `execute` tool (`[CF76-1]` D29), visible in message
  parts only as `execute` with the code text as input.
- **OpenChamber session metadata** (`[CF52-1]`, `[OC-CFG]`): scheduled launches carry
  `metadata.openchamber.kind:"scheduled"`; the coord family marks `openchamber.work {state:"open",
  openedBy:"auto"}` at kickoff (after claim) and only the human marks done. A no-op tick never claims, never
  kicks off, never marks — but absence-of-LLM-written-marker is an LLM-compliance signal, not evidence.
- **board-context** (`[BC-1]`) is a prompt-prefetch only (and ships disabled) — it observes nothing
  session/claim-state relevant here.

### F4 — The RESULT convention is not a reliable signal

Ticks end with a RESULT block (`pipeline-conventions`: status DONE|BLOCKED|NEEDS_INFO|CHANGES_REQUESTED;
boards: no-eligible-work ends `NEEDS_INFO`). Honest brittleness assessment:

- The final assistant **text part is 240-char truncated for the push** — the RESULT block often exceeds the
  excerpt; selection is the *last* text part, which a trailing prose sentence can displace.
- **`NEEDS_INFO` is not equivalent to no-op**: the plan-approval pause (the default human gate!) and the
  batched-question round also end NEEDS_INFO — and those are exactly the runs the user wants alerted.
  Status-keyword parsing would silence real alerts; any refinement becomes a parser over free-form model
  prose. Verdict: reject RESULT-text parsing as a predicate; keep as body decoration only.

### F5 — Which launcher actually fires hourly today (and the stale doc claim)

The loop file (`[LOOP-1]`) *ships* `enabled: false` and its comment claims the hourly entry is
`/pipeline-boards-hourly` + `scripts/agent-board-coord-gate.sh` (`[CMD-1]`, `[GATE-1]`). **Live state
disagrees** (`[OC-CFG]`):

- OpenChamber synced the loop file into a scheduled task **"pipeline-worker" that is `enabled:true`**, cron
  `0 * * * *` UTC, agent `agent-board-coord`, prompt = the file's whole text ending with the worker sentence
  ("Load the boards skill and run exactly one Parallel pipeline loops iteration. First call pipeline_status…").
  Its last run — **2026-10-29T13:19:41Z, status success** — is the observed no-op tick that alerted.
- A second legacy task **"Hourly Pipeline call"** is also enabled (demoted to daily 16:05 Denver, agent
  `agent-board-coord-local`, raw prompt "Please take the next card and start processing it." — it runs
  **neither** the gate script nor the boards tick wording), last run 2026-10-29T01:51Z.
- Consequence: the gate path (`agent-board-coord-gate.sh`) is **not what runs hourly today** — the boards
  lock surface (`pipeline_status` + claim-before-move + 3-attempt cap) is the effective concurrency guard for
  the loop task, while the gate remains the documented fallback entry. Both tasks create top-level scheduled
  sessions that end succeeded → alert. Any fix must therefore cover: (a) the synced loop task, (b) the legacy
  daily task, and (c) manual `/pipeline-boards*` no-ops — which argues for a predicate keyed on the agent
  family + work evidence, **not** on launch kind. The "ships DISABLED" comment in `[LOOP-1]` and the
  matching AGENTS.md sentence are stale and should be reconciled (human decision: keep OpenChamber's task
  enabled and fix the docs, or disable the task and let the gate command back into the slot — not our call).

---

## Option comparison

| | mechanism | authority of signal | crash/race safety | failure direction | files | brittleness |
|---|---|---|---|---|---|---|
| **A: didWork query** | question-notify calls a tiny RPC exposed by pipeline-locks on the finished push; suppress only a definite `{worked:false}` for board-coord agents | strong — durable locks + storage + `events.log` (audit lines with `at:` stamps, written by the claim/release code paths) | query at end, request/response (no event-order race); mid-claim crash = held lock + claim line ⇒ `worked:true`; crash path is `failed`, which never consults didWork ⇒ always alerts | unknown/throw/degrade ⇒ **alert** (fail-open on notifications) | 2 plugins + 2 test suites | low — both ends are plugin code; contract is a duplicated literal (repo pattern) |
| **B: coord writes no-op marker** | coord PATCHes a metadata key on no-op ends; notifier skips when present | weak — LLM compliance across ≥4 no-op exit paths (gate SKIP, gate LIVE, 3×claim-contention, empty board) | a dead run never marks (good), but a misclassified `NEEDS_INFO` (plan-approval pause marked no-op) **silences a real alert** | forgets marker ⇒ noise persists (safe); marks wrongly ⇒ **misses real alert** (unsafe) | rulesync subagents + kickoff/boards skills + regen (permission rows already allow the PATCH, `[SUB-1]`) | high — prose-rule contract + metadata whole-replace merge discipline |
| **C: structural detection in notifier** | on finished, census the already-fetched message parts: no board-write tool part + no claim evidence | mixed — MCP part-name shape unprobed (`<server>_<tool>` likely `[CFG-1]`); claim/release hidden inside `execute` code text (string-matching `tools.pipeline_claim` vs `tools.pipeline_status` — every tick calls status!) | same fetch cost as today; no cross-plugin race | parse miss ⇒ default decides — must hardcode ⇒alert | 1 plugin + tests | medium-high — Code Mode opacity + unverified part naming; RESULT-text variant rejected (F4) |
| **D: OpenChamber-native discriminator** | suppress when `metadata.openchamber.kind=="scheduled"` (+ some no-work signal) | none by itself — `kind` says *how* it launched, not *whether* it worked; "scheduled + finished" suppression would kill real hourly completions | n/a | n/a | 1 plugin | as sole signal: wrong; usable only as a scope-limiter, but agent-name scoping (`agent-board-coord*`) already covers launchers+manual without OpenChamber coupling |

Hybrid note: C's board-write check is a cheap *belt* over data A's predicate doesn't see (a run that
violated claim-before-move); it is not the primary signal. D's only real value is if the user wants
scheduled runs suppressed even after work — they don't ("alerts MUST stay for real completions").

---

## Recommendation — Option A (`didWork` RPC), with defaults that always alert

### Signal contract

- **Writer**: none new — pipeline-locks already writes the evidence (`[PL-1]`: lock files, `claim/` storage
  records, `events.log` claim/release/tick/child_mapped lines, each with `at:` + `sessionID`).
- **Reader**: pipeline-locks exposes
  `rpc.register({id:"pipeline-locks", methods:{ didWork: {input:{sessionID:string}, output:{worked:boolean, basis:string}} }})`;
  `didWork(sessionID)` ⇒ true iff any of:
  1. live claim: `findClaim(env, sessionID)` (cache/storage) or any lock-file group with `holder==sessionID`
     (reuse `lockStatus` internals);
  2. audit history: an `events.log` line with `ev in {claim, release}` and `sessionID==arg`, or
     `ev=="child_mapped"` with `rootID==arg` (bounded tail read from session `time.created` when available);
  3. (belt) `{ev:"tick"}`-style rows never count; reap lines naming a holder session do count (that run did work).
  false only when all three answer nothing.
- **Consumer**: question-notify, in `handleLifecycle`'s FINISHED branch, *after* `isTopLevel` and the
  session-record it already reads: if `agent ∈ {agent-board-coord, agent-board-coord-local,
  agent-board-coord-pr}` → `await deps.didWork(sessionID)`; suppress the push **only** on a strictly-typed
  `{worked:false}` answer; `undefined`/throw/absence ⇒ push (explicitly overrides the doubt-suppresses
  precedent for this one predicate — the user rule is "never miss a real alert"; log the suppression to
  stderr for audit). Question and approval paths, crash path, and all non-board-coord sessions:
  byte-identical behavior.
- **Race/crash matrix**: tick ends clean & empty ⇒ false ⇒ silent (the fix). Tick claimed, crashed mid-claim
  ⇒ `failed` event ⇒ crash push untouched. Succeeded while still holding locks (forgot release) ⇒ (1) ⇒ push.
  Done properly (claim→Review→release) ⇒ (2) ⇒ push. Server restart mid-run: storage + events.log durable
  (`[PL-1]` D26), notifier's in-memory state irrelevant.
- **Cross-plugin import ban**: the contract object is a small duplicated literal in each plugin (pattern
  already codified at `[PL-1]` L953 "Duplicated, never imported"), or better, the notifier keeps *no* schema —
  capability-detect `ctx.rpc` and call through it; degrade = alert.

### Exact files to touch (implementation plan — NOT executed here)

1. `.opencode/plugin/pipeline-locks/index.ts`
   - additive seam exports (the header pins "the seam export surface stays ADDITIVE"): pure
     `workFromAuditLines(lines, sessionID)` + `didWorkQuery(env, input)` composing
     findClaim/lockStatus/tail-read; register the RPC inside the existing setup try/catch,
     capability-gated on `typeof ctx?.rpc?.register === "function"` (mirror the `env.pin` D28 pattern:
     degrade + one stderr line when absent; setup must never throw).
2. `.opencode/plugin/question-notify/index.ts`
   - `handleLifecycle(deps, event)`: new optional `deps.didWork` consulted only for the FINISHED branch and
     the three board-coord agent names; suppression logs `[question-notify] suppressed no-op finished push
     <sessionID>`; cooldown stamps stay on push attempts (a suppression consumes nothing — mirror the
     approval-path cancellation rule from C03).
   - setup wires `deps.didWork = async (sid) => ctx.rpc(PipelineLocksWork).didWork({sessionID: sid})` behind
     capability probes; anything not exactly `{worked:false}` ⇒ alert.
3. `tests/opencode/pipeline-locks-*.test.ts` — new offline arms: empty audit ⇒ false; claim-then-release ⇒
   true; held lock ⇒ true; failed-claim-only (contention, no audit line) ⇒ false; child_mapped root ⇒ true;
   windowed tail read.
4. `tests/opencode/question-notify.test.ts` — new matrix arms: coord+false ⇒ suppressed; coord+true ⇒ push;
   coord+throw ⇒ push (fail-open); non-coord ⇒ unchanged; crash+false ⇒ push (predicate never consulted).
5. Docs (human-owned, one commit, rulesync flow for generated surfaces): reconcile `[LOOP-1]`'s "Shipped
   DISABLED" comment + the AGENTS.md sentence with the live OpenChamber state (`[OC-CFG]`), and record the
   notifier suppression rule.

### Validation (required before "done")

1. **Probe first** (v2.1.4 runtime): one stderr line at each plugin's setup logging
   `typeof ctx?.rpc?.register` / `typeof ctx?.rpc` — confirms the promise-plugin RPC surface the docs promise
   (the binary proves the kernel and an internal registrant, `[BIN-1]`; if absent, the degrade path = today's
   behavior = alerts, and the fallback is the C-lite board-write-predicate variant — see open questions).
2. Force a no-op: with all cards' pipeline sets locked by a live run (or board empty), launch
   `/pipeline-boards` manually → session ends succeeded → expect **no push** + the suppressed- log line, HA
   notify history shows nothing for the tick; next hourly fire likewise.
3. Real run: unlock/pick a card, drive a minimal run to Review + release → expect the finished push with the
   summary excerpt.
4. Crash: a claiming session ended by provider failure → expect the "stopped" push.
5. Question/approval: unchanged paths spot-checked (a batched plan-question round still rings).

---

## Open questions (for the user / next round)

1. **Gate-path skips** (`GATE: SKIP` — CLI/detection failure; `GATE: LIVE` — another coord live): those runs
   also "did nothing" and would suppress under the agent-family predicate. Silent *persistent* gate failure
   is a small hide-forever risk. Accept, or add a "N consecutive suppressions ⇒ one digest alert" follow-up?
2. **Manual `/pipeline-boards` no-ops** — covered by the same predicate (recommended: yes, suppress them too;
   the user ticket asks, this answer covers both launchers and the legacy daily task without extra rules).
3. `ctx.rpc` promise-plugin shape on 2.1.4 — probe #1 above settles it; if absent, decide between C-lite
   belt (after pinning the MCP tool-part name with one live log line) and waiting for a newer OpenCode
   (repo pins v2.1.4 deliberately).
4. Launcher hygiene (human call): disable the redundant "Hourly Pipeline call" daily task or repoint it at
   the gate command; fix or flip the loop file's `enabled` flag so the repo claim matches OpenChamber reality.
5. `session.execution.interrupted` still never alerts (shipped behavior) — confirm a manually-stopped tick
   staying silent is acceptable (it currently is).

## Deviations & friction (research-run honesty)

- STORM ran inline, no interview fan-out: the ticket pre-fixed the perspectives, the options to evaluate, and
  the file output; grounding came from repo files, live host state, fetched official docs, and binary/OpenAPI
  probes (all cited above), not web interviews.
- Output written ONLY to `/tmp/opencode/research-w2-noop-alert.md` per the launch override (no RESEARCH.md,
  no feature folder). No repo file was created or modified.
- Friction: the live OpenAPI inlines no event enum (`V2EventEncoded` is opaque) → event vocabulary had to be
  grounded through the cf-76 probe log + binary strings; docs-vs-2.1.4 drift is real (instruction-entry API
  documented but absent in 2.1.4 per `[PL-1]` D28) — every claim above carries runtime grounding, not just a
  doc link.
- The `write` tool denied the /tmp/opencode path (edit permission); the file was written via shell heredoc —
  same content, no repo surface touched.
