# C10 read-back runbook — deploy chain, pin bump (all three tiers), probes, cutover apply (cf-96)

Executor: the OWNER for every repo/board-affecting step (merge, build, pin
bump, backup, rules import); `agent-board-coord` for the two board comments
(it owns card writes, not values files); the guided live probes are
USER-owned per the plan's Commands. Nothing in this runbook is agent-
executed before merge — the `v<run>` tag literally does not exist until CI
builds it, which is why the bump instructions stay PREPARED here (planner's
call on OQ8, recorded in DECISIONS). This is a review contract + owner
checklist, the cf-90 C07 read-back posture: the offline pin suite
(`tests/cf96-deploy/surface.sh`) is green NOW over this file; the post-
deploy legs below are production read-backs, not suite tests.

Actors below are load-bearing: a step labelled **Owner** must never be
executed by a pipeline agent, and a **coord** step touches only board
comments.

## Steps (in order)

1. **Owner — merge.** Merge the ticket branch `cf-96-feat-dep-tracking-card-
   pickup` to `main` (the user's decision alone; agents never merge or push
   `main`). No agent step may be marked done before this lands.

2. **CI — image build.** `docker-build.yaml` on `main` (a `containers/**`
   change) pushes `ghcr.io/ownyourio/wekan-mcp:v<run>` (immutable, run
   number) + `:main` rolling. **Owner records the run number** — every later
   step substitutes that number for `<run>`. Do NOT invent one here.

3. **Owner — the pin bump, ALL THREE tiers in ONE commit (OQ8 ruling).**
   Same image, same surface lag, three entries:

   - `services/dev/prod/values.yaml` — the `boards:` MCPServer entry. Today:
     ```
     # :v60 = the 25-tool custom-field build (ticket 2026-10-feat-board-coord-intake, D17/M2).
     image: ghcr.io/ownyourio/wekan-mcp:v87
     ```
     Bump the `image:` line to `image: ghcr.io/ownyourio/wekan-mcp:v<run>`
     AND rewrite that stale comment line to the new build's surface, e.g.
     `# :v<run> = the cf-96 38-tool build (dependency/preload/label tools).`
   - `services/gpu/prod/values.yaml` — the `wekan-admin:` entry and the
     `wekan-readonly:` entry, each bumped with the identical line shape
     `image: ghcr.io/ownyourio/wekan-mcp:v<run>`.

   This same bump ABSORBS ledger card L4 `r3ghE7qGj75HTnghH` ("Bump
   dev-boards wekan-mcp pin to a v102+ build"): **coord** comments the
   absorption (this runbook's path + commit) on L4 — and on card #96 per
   the plan's Run protocol. The Inbox move-out of L4 stays **owner-owned**.

4. **ArgoCD — sync.** GitOps applies: the hivetools MCPServer (`dev`
   cluster) + the gpu entries reconcile, pods restart, the login-mint
   re-mints the bearer. Verify the items you shipped actually applied
   (the AGENTS.md GitOps law: a sync can reject individual items silently):
   `readonly-dev-kubernetes` + `readonly-gpu-kubernetes` pods_get on the
   three wekan-mcp pods, image tags = `:v<run>`, restart age fresh.

5. **User-owned live probes** (recipe:
   `skills/wekan-api/references/wekan-mcp-ops.md`):
   - `tools/list` on `dev-boards` = **38 tools** (17 reads + 21 writes)
     including the seven new signatures: `list_board_dependencies`,
     `list_card_dependencies`, `add_card_dependency`,
     `edit_card_dependency`, `remove_card_dependency`, `preload_board`,
     `set_card_labels`. (The plan's Commands says "8 new signatures" while
     its own arithmetic lands +7 tools = 17+21 = 38 — probe the seven names
     above; if a surface the plan counts as a signature is missing, stop
     the chain and report rather than squaring the number.)
   - `tools/list` on `readonly-global-wekan` = 17 reads, NO new writes
     (the four new write tools must be absent — `_write_tool` gating by
     construction).
   - First-ever live round-trip `GET /api/boards/TNQJ2BrXenZovngTS/
     dependencies` via `list_board_dependencies` — this confirms the v12.65
     routes RESEARCH §1.5 could not agent-probe (no bearer in agent
     context).
   - One `preload_board` payload sanity check: cards carry card_numbers,
     `archived` FLAGGED not dropped (RESEARCH C5), dependency lines +
     label/field name maps present.

6. **Owner-approved follow-up commit — stamp the evidence.** Once step 5 is
   green: `skills/wekan-mcp/references/call-shapes.md` rows C01 stamped
   `source-only 2026-11` upgrade to `live-probed <date>`; the wekan-mcp
   skill's evidence-posture line re-stamps to match. This is a repo change
   like any other: own branch → PR → owner merges (agents prepare, never
   land).

7. **Owner — cutover apply (board backup FIRST, non-negotiable).** Take a
   full board backup/export of AI-Dev, then WeKan UI → Rules → Import JSON
   with `.agents/plans/2026/2026-10-cf-96-feat-dep-tracking-card-pickup/
   board-rules-v12.65.json` (the C08 artifact — checklist extras are
   UI/Import-JSON-creatable only, never REST, which is exactly why this
   step is human-executed). Then run the boards skill's Board-side cutover
   checklist steps (the 11-item Lifecycle + matching HITL checklists on the
   live board). Agents never mutate board checklists or rules.

8. **Verify with a zero-action re-run.** Re-collect a schema-2 board
   snapshot (`/wekan-board-context` collector or the owner's REST shell),
   then `python3 scripts/provision-board.py --fixture <snapshot> --dry-run`
   must print **ZERO actions** (the wekan-board-provision skill's step-4
   verify loop). Any action = the apply drifted; fix by re-running the
   import, never by editing the spec.

9. **Flip the degrade + record.** Once steps 4–5 are green the boards
   skill's degrade posture is live-eligible automatically — the probe gate
   flips behavior, so NO text change is needed. **Coord** records the flip
   date in card #96's summary comment (and the L4 comment from step 3).
   From here on, pickup runs use the dependency gate + preload + grouped-
   sibling flow for real.

## Reporting (what review verifies at the ticket's end)

RESULT `commands_run` for the post-merge legs lists each probe with its
verdict (step 5 reads, step 4 pod tags, step 8 engine output). The coord
writes the recorded `v<run>` + probe verdicts into the chunk's Review
notes; the flip date rides the card comment (step 9). A found-red probe
stops the chain: re-check the sync BEFORE assuming the build (GitOps
verify-landed law), then report — never re-apply blindly.
