# C10 read-back runbook — deploy chain, pin bump (all three tiers), probes, cutover apply (cf-96)

Executor: the OWNER for every repo/board-affecting step (merge, build watch,
pin bump, board backup, rules import); `agent-board-coord` for the two board
comments (it owns card writes, not values files); the guided live probes are
USER-owned per the plan's Commands (a pipeline session may repeat the pure
reads — `tools/list`, `pods_get`, `--dry-run` — those are inspections, not
executions). Nothing in this runbook is agent-executed before merge — the
`v<run>` tag literally does not exist until CI builds it, which is why the
bump instructions stay PREPARED here (planner's call on OQ8, recorded in
DECISIONS). This is a review contract + owner checklist, the cf-90 C07
read-back posture: the offline pin suite (`tests/cf96-deploy/surface.sh`) is
green NOW over this file; the post-deploy legs below are production
read-backs, not suite tests.

Actors below are load-bearing: a step labelled **Owner** must never be
executed by a pipeline agent, and a **coord** step touches only board
comments. Governing law for the whole probe round — the wekan-mcp skill's:
the deployed build can lag the repo source, so **docs are claims, the live
`tools/list` is fact**.

## Steps (in order)

1. **Owner — merge.** Merge the ticket branch `cf-96-feat-dep-tracking-card-
   pickup` to `main` (the user's decision alone; agents never merge or push
   `main`). The branch touches `containers/wekan-mcp/`, so the merge itself
   is what arms the build. No step below may be marked done before this
   lands.

2. **CI — image build; record the run number.** `docker-build.yaml` on
   `main` detects the changed `containers/wekan-mcp/` dir, builds its
   Dockerfile, and pushes two tags —
   - `ghcr.io/ownyourio/wekan-mcp:v<run>` (immutable): `v` + the GitHub
     Actions **run number** of the workflow run (monotonic, not the run-id
     in the URL), and
   - `ghcr.io/ownyourio/wekan-mcp:main` (rolling).

   **Owner records the run number** — every later step substitutes that
   number for `<run>`. Read it from the docker-build run on `main` (the
   `#NNN` label on the workflow-runs page) or registry-side per the
   container-creation skill: `docker buildx imagetools inspect
   ghcr.io/ownyourio/wekan-mcp` and its tag list. Do NOT invent one here —
   until the run answers, the tag does not exist anywhere.

3. **Owner — the pin bump, ALL THREE tiers in ONE commit (OQ8 ruling).**
   Same image, same surface lag, three entries — the bump reaches `main`
   through the owner's own PR (main moves only via owner-created/merged
   PRs), exactly one commit touching both values files:

   - `services/dev/prod/values.yaml` — the `boards:` MCPServer entry under
     the hivetools section (line 406 at authoring). Today, verbatim:
     ```
     # :v60 = the 25-tool custom-field build (ticket 2026-10-feat-board-coord-intake, D17/M2).
     image: ghcr.io/ownyourio/wekan-mcp:v87
     ```
     Bump the `image:` line to the exact shape
     `image: ghcr.io/ownyourio/wekan-mcp:v<run>`
     AND rewrite the stale comment to the new build's surface, e.g.
     `# :v<run> = the cf-96 38-tool build (dependency/preload/label tools).`
     — the values comment must keep telling the truth about what is
     deployed. It currently narrates the 25-tool build while pinning
     `:v87`, whose real surface only the step-5 probe settles (the cf-90
     ledger live-probed :v87 WITHOUT the v102-era additions — docs are
     claims, `tools/list` is fact; after the bump, `:v<run>` = 38 is the
     claim step 5 verifies).
   - `services/gpu/prod/values.yaml` — the `wekan-admin:` entry (line 734
     at authoring) and the `wekan-readonly:` entry (line 697), each bumped
     with the identical line shape `image: ghcr.io/ownyourio/wekan-mcp:v<run>`.
     `wekan-readonly` carries the same stale narration ("Pinned to :v60 —
     the first build carrying the 25-tool custom-field surface…", lines
     692–694): rewrite it to match the new build too. Renovate's docker
     manager will open its own per-tier bump PRs once the tag publishes —
     the ONE-commit ruling wins over three split bumps: close the bot PRs
     unmerged after this commit lands.

   Scope guard: the commit touches ONLY those three `image:` lines and
   their comments. Never hand-bump `Chart.yaml` versions anywhere in the
   same change — `release.yaml` owns chart versions (the hard rule); and
   no entry switches to `:main` — the immutable-pin manifest edit IS the
   recreation trigger (step 4).

   This same bump ABSORBS ledger card L4 `r3ghE7qGj75HTnghH` ("Bump
   dev-boards wekan-mcp pin to a v102+ build"): **coord** comments the
   absorption (this runbook's path + the bump commit) on L4 — and on card
   #96 per the plan's Run protocol. The Inbox move-out of L4 stays
   **owner-owned**; coord writes comments and nothing else here.

4. **ArgoCD — sync; verify what is actually running.** The bump commit on
   `main` is a manifest diff, and that is the whole mechanism: pods do NOT
   restart because a new image was pushed — ArgoCD recreates only on a
   manifest change (deploy/verify loop, `skills/wekan-api/references/wekan-mcp-ops.md`).
   The hivetools MCPServer (`dev` cluster: `boards`) + the gpu entries
   (`wekan-admin`, `wekan-readonly`) reconcile, pods recreate, and the
   login-mint re-mints the bearer in-pod. Verify the items you shipped
   actually applied (the GitOps verify-landed law — a sync can reject
   individual items silently): `readonly-dev-kubernetes` +
   `readonly-gpu-kubernetes` `pods_get` on the three servers — each shows
   the ToolHive two-pod shape (`mcp-<name>-0` StatefulSet server pod + an
   `mcp-<name>-<hash>` proxyrunner pod; two pods per server is normal).
   `spec` image = `:v<run>` and `status.containerStatuses[].imageID`
   carries the manifest DIGEST — the tag in a manifest is a claim, the
   imageID digest is what runs; compare it against the ghcr manifest for
   `:v<run>` (the anonymous-token tag-digest flow in the ops reference, no
   pull needed). Old digest ⇒ re-check the sync before assuming anything
   about the build.

5. **User-owned live probes — READ-ONLY first** (recipe:
   `skills/wekan-api/references/wekan-mcp-ops.md`; the ordering below is
   the law: catalog before call, catalog over docs):
   - `tools/list` on `dev-boards` = **38 tools** (17 reads + 21 writes)
     including the seven new names: `list_board_dependencies`,
     `list_card_dependencies`, `add_card_dependency`,
     `edit_card_dependency`, `remove_card_dependency`, `preload_board`,
     `set_card_labels`. The plan's "8 new signatures" is ruled (DECISIONS
     coord-rulings): seven new tool NAMES plus the new `parent_id` argument
     on the existing `create_card` — additionally spot-check
     `create_card.inputSchema` in the same catalog for `parent_id`. A
     documented surface missing from the live catalog = stop the chain and
     report; never square a number.
   - `tools/list` on `readonly-global-wekan` = 17 reads, NO new writes —
     the four new WRITE tools must be absent (`_write_tool` gating by
     construction) and the three new READS (`list_board_dependencies`,
     `list_card_dependencies`, `preload_board`) must be present.
   - `tools/list` on `admin-global-wekan` = the full 38-tool surface, same
     as dev-boards (same image, same build).
   - One `preload_board` call-shape check on AI-Dev `TNQJ2BrXenZovngTS`
     (this also closes RESEARCH §1.5's agent-probe gap): ONE call returns
     `{swimlanes, lists→cards, dependencies, label_names, field_names}`
     with per-card dicts EXACTLY `{id, card_number, label_ids, slug,
     archived, sort, parent_id}` — `card_number`s present (the projection
     the by-list read strips), `archived` cards FLAGGED not dropped
     (RESEARCH C5), dependency lines present.
   - `get_card` passthrough spot-check: take one card from that payload
     and `get_card` it — its `card_number`, label ids, combined `slug`
     value and parent link must equal the preload's entry for the same
     card (the first live confirmation of the `_slim_card` passthroughs).
   - First-ever live round-trip `GET /api/boards/TNQJ2BrXenZovngTS/
     dependencies` via `list_board_dependencies` — confirms the v12.65
     routes RESEARCH §1.5 could not agent-probe (no bearer in agent
     context). The pass condition is a clean answer carrying the board's
     stored edges — likely none yet (nothing agent-side has drawn edges
     before this deploy); a non-empty list only means UI-drawn edges
     exist, which is fine.
   - `set_card_labels` dry-check: verify presence and argument shape in
     the catalog (`board_id`, `card_ids`, `add_label_ids`,
     `remove_label_ids`, ≤500 gate) — do NOT invoke any write tool on a
     live production card in the probe round; if the owner wants one
     round-trip, a scratch card with the same label added then removed is
     the only sanctioned shape.

6. **Owner-approved follow-up commit — stamp the evidence.** Once step 5 is
   green: `skills/wekan-mcp/references/call-shapes.md` rows stamped
   `source-only 2026-11` (the seven cf-96 rows) upgrade to `live-probed
   <date>`; the wekan-mcp skill's evidence-posture line and the
   `dev-boards` table note ("NOT deployed until the C10 bump") re-stamp to
   match. This is a repo change like any other: own branch → PR → owner
   merges (agents prepare, never land).

7. **Owner — cutover apply (board backup FIRST, non-negotiable), AFTER
   steps 4–5 are green.** In order:
   - Take a full board backup/export of AI-Dev. No apply step runs before
     this exists.
   - Run `/wekan-board-provision` at the owner's direction (the landed
     provision path: snapshot collect + dry-run are read-only, and the
     skill's own step 3 applies ADDITIVE actions through `dev-boards`
     only after the human confirms the plan): collect a schema-2 snapshot
     (step 1 — `get_rule` the createCard rule's checklist extras), render
     the plan dry-run (step 2, offline, zero board effect), then the
     additive actions apply — now possible because the bump makes
     `create_list`/`create_label` live, retiring the skill's
     raw-REST-fallback degrade (ledger L4's ask, absorbed at step 3,
     completes here).
   - The checklist-extras leg is **HUMAN-EXECUTED only**: WeKan UI → Rules
     → Import JSON with
     `.agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/board-rules-v12.65.json`
     (the C08 artifact — checklist extras are UI/Import-JSON-creatable,
     never REST, which is exactly why this step is human-executed). It
     replaces the createCard rule's five-checklist shape (`Model(s)` →
     Qwen Flash the only default check, per OQ13).
   - Then the boards skill section "Board-side cutover — human-owned, documented, never agent-executed" steps: rename the `Research`
     checklist to `Lifecycle` with the 11 items (`Single Session` last),
     replace `Human in the Loop` items with the same 11, ensure the
     `Research: Parallel` label (the provision apply usually covers this;
     the human step is its read-back). Agents never mutate board checklists
     or rules.

8. **Verify with the zero-action re-run** (the read-back contract of
   `tests/wekan-board-provision/checklist-cutover.sh` and
   `tests/wekan-board-provision/surface.sh`). Re-collect the schema-2
   snapshot — the `checklist_extras` capture (get_rule or the Rules UI
   export) is what makes the drift legs decidable; a schema-1 snapshot
   only earns the engine's UNVERIFIABLE stderr note and zero checklist
   actions. A pipeline session may run the engine read-back at any time
   (offline, deterministic):
   `python3 scripts/provision-board.py --fixture <snapshot.json> --dry-run`
   must print **ZERO actions** — specifically ZERO
   `update_createcard_checklists` (drift here = re-run the import, never
   edit the spec), plus zero list/label/rule actions, and the
   `Research: Parallel` label present in the snapshot's labels (the wekan-
   board-provision skill's step-4 verify loop). Any action = the apply
   drifted. And if the artifact itself is ever found wrong: regenerate it
   programmatically from the engine's `CHECKLIST_SPEC` — never hand-edit
   `board-rules-v12.65.json` (the C08 rule: artifact bytes are derived,
   the suite compares them byte-wise against the engine).

9. **Flip the degrade + record.** Once steps 4–5 are green the boards
   skill's degrade posture is live-eligible automatically — the probe gate
   flips behavior, so NO text change is needed (the one exception is the
   step-6 evidence stamps). **Coord** records the flip date in card #96's
   summary comment (and the L4 comment from step 3). From here on, pickup
   runs use the dependency gate + preload + grouped-sibling flow for real.
   Which clause retires at which step is the next section.

## Which degrade clauses retire, at which step

Every consumer already probes `tools/list` and degrades with a RESULT note
(the family degrade law, DECISIONS). The flip is behavior-side; this table
is the reading map:

| Degrade clause (landed text) | Retires at |
|---|---|
| boards `Preload consumer at claim` — "while the deployed build predates the C10 pin bump, `preload_board` is ABSENT… keeps per-list reads, SKIPS the dependency gate" | step 5 (dev-boards `tools/list` shows `preload_board`) atop step 4's green digest read-back |
| boards `Card pickup` dependency-gate skip — same clause, gate half | step 5, and it starts gating FOR REAL at the next run: edges absent ⇒ gate vacuously passes; the moment an edge exists it blocks |
| boards follow-up `Mechanics` — the "labels to apply" comment-line degrade → the one `set_card_labels(board_id, [new card id], add_label_ids=…)` call retiring AD-74's ledger round-trip | step 5's `set_card_labels` catalog probe (dry-check, not invocation — the first REAL call happens in the next follow-up run) |
| wekan-board-provision step 3 — `create_list`/`create_label` ABSENT on the `:v87` pin, raw-REST fallback recipes for the human shell | step 3's bump deploying at step 4; the MCP path is whole at step 7's apply |
| wekan-mcp skill + `call-shapes.md` `source-only 2026-11` stamps; the server-table "NOT deployed until the C10 bump" note | step 6 (the only clause with a text change of its own) |

## What stays human-owned after this runbook lands

- The merge (step 1) and every merge after it, including the step-6 stamp
  commit — `main` moves only via owner-created/merged PRs.
- The values bump itself (step 3) and the ArgoCD apply watch (step 4):
  GitOps reconciles automatically; the owner confirms the read-backs.
- The board backup + the cutover-specific mutations (step 7): the rules
  import, checklist renames, and HITL replacements stay owner-side — no
  agent path writes board checklists or rule extras. The single
  agent-executed board-write leg is the `/wekan-board-provision` additive
  apply the owner directs inside step 7: `dev-boards` creates the lists,
  `Bucket:` labels, rule pairs and the Provider/`Research: Parallel`
  label ensures after the human confirms the dry-run plan (the skill's
  own step-3 contract). Everywhere else in this runbook, agents write
  card comments only.
- Board bookkeeping: L4's Inbox move-out, card #96's move to **Finished**
  (Finished is human acceptance — no agent moves there), and any **Review**
  / **Timeout** triage.
- The C09 workspace reprovision (the coder template's `TZ` reaching live
  workspaces): owner-gated like everything terraform; until it fires, the
  `UTC Z` stamp fallback is the designed behavior, not a failure.

## Reporting (what review verifies at the ticket's end)

RESULT `commands_run` for the post-merge legs lists each probe with its
verdict (step 5 reads, step 4 pod tags + digests, step 8 engine output).
The coord writes the recorded `v<run>` + probe verdicts into the chunk's
Review notes; the flip date rides the card comment (step 9). A found-red
probe stops the chain: re-check the sync BEFORE assuming the build (GitOps
verify-landed law), then report — never re-apply blindly.
