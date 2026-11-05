# PLAN: Coord fixes — slug linking, preload, locks, model defaults, permissions, scheduled-runner hygiene
feature: 2026/2026-11-cf-106-feat-coord-fixes
revised: 2026-11-03 (post-batched-question-round — all 15 open questions RESOLVED by the owner; C03 split into C03a evidence + C03b contract)
revised: 2026-11-05 (scoped amendment, **C03b only**: its done-claim is judged on the audit's **marker columns**, never a `gate-stop` row count — that class is structurally unobservable for loop-launched runs (DECISIONS 2026-11-04), so a zero count is a coverage limit, not a finding. Chunk ids, sizes, waves and the eleven-chunk map unchanged)

## Goal
Fix the fourteen coordination-machinery defects the owner listed on WeKan card #106: make the `slug` custom field an append-only `[slug](session-link)` stack, give the board-coord flow a real card-level preload (whole-board by swimlane/list, and one automatic single-card read), make the lease-lock engine support co-tenant cards and a user-ruled takeover after a reap, land the `Qwen Dense` vocabulary + local-first default, keep git writes with the coordinator while letting it reach the `code` agent (with push on the `-pr` family), make no-work scheduled ticks mark-and-archive instead of alerting-and-idling, offer five friction follow-up modes in both coordinator families, and collapse the scheduled worker to one runner that sets agent + provider/model and starts with card info in hand.

Everything is agent-machinery: `.rulesync/**` sources (+ their generated mirrors), the hand-managed `.opencode/plugin/*`, `containers/wekan-mcp`, `scripts/`, `.agents/loops/*` and the `tests/**` batteries that pin them. **Out of scope:** any live-board mutation (checklist renames, rule-extra apply, label creation), any OpenChamber scheduler operation (task create/retire, `loopApprovals` fingerprints, `permissionAutoAccept`), the `wekan-mcp` image pin bump (`:v87` → newer; card #81 / ledger L4 owns it), the `Priority` custom field (another ticket — owner ruling OQ-15), chart/service/helm work, any permission widening of the validation shell (owner ruling OQ-11), and backfilling the legacy split-value `slug`/`session` fields on already-landed cards (frozen history — the parse rule only has to tolerate them).

## Grounding (verified at plan time, worktree HEAD `ceb9a8ed6`; revised 2026-11-03 with the no-op audit and the permission-shape reads)

- **Suites green at plan time** (run here, this tree): `node --test 'tests/opencode/*.test.ts'` → 243 pass / 0 fail; `tests/{agent-perms,pipeline-models,noop-marker,boards-deps}/surface.sh` → exit 0. **`tests/provider-loops/surface.sh` is RED at HEAD** on its `t6` leg, which runs `tests/agent-board-coord/gate.sh` as an id subset — the nested suite's `t14` scope guard rejects `.agents/plans/2026/2026-11-cf-106-feat-coord-fixes/EXPLORE.md` ("path outside the ticket's Files in scope"). The admits live in three suites (`agents-md.sh` c7, `rulesync-surface.sh` c8, `gate.sh` t14 `FEATURE*`), and `provider-loops` t6 reddens as that subset's consumer. **C01 owns those admits for this ticket's whole declared file set.**
- **Ask 6/7 arm is now measured, not guessed** (full table in `2026-11-03-cf-106-feat-coord-fixes-noop-evidence.md`, read 2026-11-03T21:58Z from `~/.local/share/opencode/opencode.db`, table `session_v2`, read-only via python3 stdlib `sqlite3` — no `sqlite3` binary exists here): every scheduled run that wrote `metadata.pipelineNoop` also carries `time_archived` — **55 of 55 across the store's whole board-coord population, 32 of 32 in the 11-02→11-04 window** — so "the PATCH is ineffective" and "the app ignores the archive" are refuted; the broken runs are scheduled runs that **never reached a marked exit** (6 in that window: two died emitting raw `<tool_call>` XML as text, three died mid-turn after the lock-state check, one reported its own session missing the `dev-boards` MCP tools), and the pattern **reproduced during planning** — the 22:00Z and 22:30Z ticks landed unmarked and unarchived while the evidence was being written. Coverage, not mechanism, and it is still happening.
- **Two side findings from the same read**, neither an archive bug: a scheduled board-coord session ran without the `dev-boards` MCP tools while the prefetch hook reached the same server (feeds C10), and the marked-but-unarchived 20:06 row carries `openchamber.kind: none` + a `probeSentinel` — a probe/manual session that alerts **by design** (the OQ4 conjunction), kept as the manual-side control.
- **Deployed board surface lags the repo** (EXPLORE §0, live `tools/list` = 26 tools): `preload_board`, `list_board_dependencies`, `set_card_labels`, `create_list`, `create_label` ABSENT on `wekan-mcp:v87`. Every wekan-mcp change here is repo-only until the pin moves (USER-owned) and is consumed through the `tools/list` probe + degrade law — no chunk may depend on the deployed build.
- **`get_checklist` does return item titles** on the deployed build (EXPLORE §0 correction, probed on card #106); `list_checklists` (`{id,title}` only) and the by-list projection do not.
- **A card id is already a legal lock name**: `sanitizePipelineKey` folds `[A-Za-z0-9._-]`, so `pipelines:[cardId]` writes `.pipeline/locks/<cardId>.json` with no new machinery (EXPLORE §3). Live lock state: `Context` (this run), `CICD`, `Local`/`default` in `state:"failed"`, `lastReap 2026-11-03T15:33:09Z trigger:"timer"`.
- **The `code`-push ruling has an existing mechanical template**: `agent-dev-pr.md` carries `git push*` **allow** closed by the deny floor `git push*main*`, `git push --force*`, `git push -f*`, `git push * --force*`, `git push * -f*` — the same matrix a `code-pr` twin must reproduce — and `pipeline-push-pr`'s "Applies to" list (`agent-coord-pr`, `agent-board-coord-pr`, `agent-dev-pr`, `dev-pr`) is the single authority a new variant must join. Subagent grants are whole-value/exact-match per agent (cf-90 verification), so family-differentiated access needs two sources, not one conditional.
- **The approval posture is a constraint, not an option** (owner ruling OQ-11): role shell baselines are `shell '*' → ask`, and in an unattended scheduled session `ask` resolves to deny (this run's scheduled predecessor shows it). So validation commands (`node --test`, `bash tests/…`, `rulesync generate`, `npx aislop`) are not runnable by an unattended subagent — they run in an interactive session, in a role that already carries the row (helm on the dev family), or the owner runs them. `permissionAutoAccept` stays the interim; ledger L1 stays open.
- **Model vocabulary is pinned in four suites**: `tests/pipeline-models/surface.sh:151-153,219-223,313-316`, `tests/agent-board-coord/rulesync-surface.sh:647-668`, `tests/wekan-board-provision/{checklist-cutover.sh,surface.sh,fixtures/*.json}`, plus runbook prose in `tests/cf90-ledger/readback-runbook.md:47,72` and `tests/cf96-deploy/readback-runbook.md:188`. Current-state wording lives in exactly five sources: `.rulesync/skills/{boards,pipeline-kickoff,pipeline-models}/SKILL.md`, `scripts/provision-board.py:70,113,114`, `skills/wekan-board-provision/SKILL.md` (hand-managed). No `*Dense*` model id exists in the gpu-ai catalog — the rename is vocabulary, not a new route.
- **Loop frontmatter recognizes `name|schedule|enabled|model|agent|timezone`** — provider rides the `model:` string; there is no `provider:` key (cf-90 RESEARCH W2). Editing any loop body rotates the OpenChamber `loopApprovals` fingerprint and `reconcileLoopTasks` force-disables a mismatched task (cf-90 DECISIONS:127) → all loop edits are batched into C10 with a USER-owned re-approval.

### Executability by role (permission verdicts, read from the sources at plan time)

Last-match-wins over each role's ordered rows; "ask" means **blocked in an unattended run** (the shipped `agent-dev-local.md` comment states it: "unattended runs treat ask as blocked"). This is the practical shape of the OQ-11 ruling — it decides *who performs which edit*, and it is not a reason to widen a grant.

| file class (chunks that touch it) | dev | test | review | code | coord |
|---|---|---|---|---|---|
| `.rulesync/skills/**` (C01, C02, C03b, C05, C06, C09, C10) | allow | **ask** ⚠ | deny | ask | deny |
| `.rulesync/rules/**` (C03b, C10) | allow | **ask** ⚠ | deny | ask | deny |
| `.rulesync/subagents/**` (C04) | **ask** | **ask** | deny | **ask** | **deny** |
| `.rulesync/commands/**` (C03b) | **ask** | **ask** | deny | ask | deny |
| `.opencode/plugin/**` (C03b comments, C08, C09) | allow | deny | deny | ask | deny |
| `containers/wekan-mcp/**` (C06, C07) | allow | tests only | deny | allow | deny |
| `scripts/**` (C03a) | allow | deny | deny | ask | deny |
| `.agents/loops/**` (C10) | allow | deny | deny | ask | deny |
| `skills/**` hand-managed (C01, C06, C07) | allow | allow | deny | allow | deny |
| `tests/**` (every chunk's pins) | **deny** | allow | deny | ask | deny |

Two consequences the coordinator must plan around, not discover mid-chunk:

1. **C04 cannot run unattended at all.** `.rulesync/subagents/**` is `ask` for dev, test, code and `deny` for coord, so its source edits need an interactive session where the owner answers the ask (or the owner makes the edits). Same for C03b's `.rulesync/commands/**` leg. This is the owner's OQ-11 posture working as designed — the fix is scheduling, never a new grant row.
2. **⚠ row-order drift found at plan time:** `agent-test.md` puts `.rulesync/** → ask` **after** its `.rulesync/rules/**` and `.rulesync/skills/**` allows (lines 55-63), so those two allows are dead for `agent-test`, while `agent-dev-local.md` orders them the other way and they are live. Not this ticket's ask (test owns `tests/**` only), so it is recorded in `FRICTION.md` and routed as a candidate follow-up card rather than silently fixed here.


## Ask → chunk map (card #106, in the card's own order)

| # | Card ask | Chunk | Round ruling |
|---|---|---|---|
| 1 | `[slug](link)`, append `\n` + new slug when a different slug exists | C01 | as designed |
| 2 | Single task/pipeline runner: card info preloaded, sets provider/model + agent | C10 | runner `model:` switches to `gpu-ai/qwen3.8-27b-q4` (OQ-14) |
| 3 | Better preload board (hook + filter; all cards by swimlane/list; both card ids, checklists, labels) | C06 | coord-side enrichment; hook stays structural (OQ-4) |
| 4 | Better preload cards — automatic single-card details | C07 | claim-time tool-hook leg (OQ-4) |
| 5 | `Qwen 27b` → `Qwen Dense`, default over Flash | C02 | label rename, **both** defaults flip (OQ-6) |
| 6 | Not archiving scheduled tasks that run nothing | **C03a → C03b** | "worth investigating" → measured: coverage gap, not mechanism |
| 7 | Don't alert on scheduled tasks that run nothing | **C03a → C03b** | same |
| 8 | Alerting | C03b | same family; reap alert unchanged (OQ-13) |
| 9 | Coord owns commits; `code` gets git privs; coord may use `code` | C04 | commits + **push on `-pr`** via a `code-pr` twin (OQ-10) |
| 10 | Better default to local provider | C02 | routing default flips to `gpu-ai` (OQ-7) |
| 11 | Fix "always allow" privs | — (ruling) | **no grant change**: the UI toggle stays, ledger L1 open (OQ-11) |
| 12 | Friction follow-up modes | C05 | **five** modes, both families, Inbox preferred on board runs (OQ-12) |
| 13 | Reap → ask "continue anyway"; take the card ID as the lock | C09 | as designed (OQ-9) |
| 14 | More than one card per pipeline lock; empty-pipeline start rule with override | C08 | as designed (OQ-8) |

## Chunks

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C01 | Slug stack: append `[slug](link)`, newest-last parse; roster wording (ask 1) + this ticket's scope admits | M | 1 | [] | — |
| C02 | Model vocabulary: `Qwen Dense` replaces `Qwen 27b`, Dense default in both places, local-first routing (asks 5, 10) | M | 1 | [] | — |
| C03a | No-op audit instrument: classify every scheduled run's marker/archive/alert state (ask 6 evidence) | S | 1 | [] | — |
| C04 | Permission model: `code` / `code-pr` in the coord roster; `code-pr` pushes under `pipeline-push-pr`; **no** shell-allow widening (ask 9, ask 11 ruling) | M | 1 | [] | — |
| C05 | Friction follow-up: five modes in both families, Inbox preferred on board runs (ask 12) | S | 1 | [] | — |
| C03b | Close the no-work coverage gap: the tick-stop exits mark + archive (asks 6, 7, 8) | M | 2 | [C03a] | The arm must be measured before any wording moves — C03a's instrument (and its evidence artifact) is what makes C03b's chosen exit set provable and its fix readable as a readback |
| C06 | `preload_board` payload: cards by swimlane+list with checklist state, labels, both card ids (ask 3) | L | 2 | [C01] | Same function (`_slug_from_combined_value`) and the same doc rows; C06 restates the `slug` field shape C01 defines — one authority, one doc edit |
| C08 | Locks: co-tenant cards on one pipeline + "don't start unless empty, user can override" (ask 14) | L | 2 | [] | Independent of wave 1: pipeline-locks plugin + the boards `Parallel pipeline loops` section; the boards overlap with C03b sits in a different subsection, and the coord runs chunks one at a time |
| C07 | Automatic single-card preload: one server read + claim-time plugin leg (ask 4) | M | 3 | [C06] | Same file pair (`server.py`, `skills/wekan-mcp/SKILL.md`) and the `tools.sh` tool-count/field-set pins; reuses C06's checklist-state projection |
| C09 | Locks: reap → one sanctioned "continue anyway" question → takeover claim under a card-id lock (ask 13) | M | 3 | [C08] | The takeover re-claim rides C08's rewritten `claimLockSet`/holder-record shape; both re-pin the same `pipeline-locks-*` + A15 arms |
| C10 | Single scheduled runner: one loop task, agent + `gpu-ai/qwen3.8-27b-q4` model, card info preloaded (ask 2) | M | 4 | [C03b, C06, C07] | The runner's no-work exit sentence needs C03b's contract; its preload sentence needs C06/C07's shapes to exist |

## Wave order

1. **C01, C02, C03a, C04, C05** — mutually independent; run in id order. (C01/C02/C05 share `.rulesync/skills/boards/SKILL.md`, in different subsections; one chunk at a time keeps mirrors consistent.) C03a's script is repo machinery a dev can write (`scripts/` is not in dev's deny set) while its pins are `agent-test`'s.
2. **C03b, C06, C08** — mutually independent; C03b may wait for the owner's post-merge audit readback, which does not block C06/C08.
3. **C07, C09** — C07 follows C06, C09 follows C08; independent of each other.
4. **C10** — last: consumes C03b's exit contract and C06/C07's preload shapes, and it is the only chunk that edits the loop files, so the OpenChamber fingerprint rotates once and the owner re-approves once.

## Test ownership (hard rule, cf-96 friction ×5)

Dev has `tests/**` denied. **Every `tests/**` creation or re-pin listed in a chunk's `## Tests` is `agent-test`'s write, authored in the single Test Writing session before that chunk's dev runs** (or routed back to `test_session` mid-chunk when review proves a pin wrong). Dev implements to the pinned shape; review re-runs. A mid-flight pin fix never happens in a dev session.

## Commands

Run from the worktree root; `export PATH=$HOME/.local/bin:$PATH` first (helm). Node v26 type-strips `tests/opencode/*.test.ts` — no npm deps.

- **Validation execution posture (owner ruling OQ-11):** in an unattended session `ask` behaves as deny, so the batteries below are run by an interactive session, by a role that already carries the row, or by the owner. Never by widening a permission block. A chunk that cannot run a command records it as `not-run (ask-denied, owner/interactive owed)` rather than claiming a pass.
- **regen (after any `.rulesync/**` edit): `npx --yes rulesync@37.0.0 generate` twice — the second run must be a no-op — then `npx --yes rulesync@37.0.0 generate --check`.** Sources + generated mirrors (`.opencode/{agents,commands,skills}/**`, `AGENTS.md`) commit together; hand-managed files (`.opencode/plugin/**`, `skills/**`, `.opencode/opencode.jsonc`, `.agents/loops/**`, `scripts/**`) never regenerate.
- **node suites, per directory** (basenames duplicate): `node --test 'tests/opencode/*.test.ts'` (baseline 243/0 at plan time) and `node --test tests/opencode/<name>.test.ts` for the touched file.
- **python / scripts**: `python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py scripts/provision-board.py`, and `bash -n scripts/session-noop-audit.sh` (or `python3 -m py_compile` on its embedded python — whichever shape C03a ships, pinned by its suite).
- **bash batteries, by blast radius** (zero `FAIL:` lines, exit 0):
  - C01: `bash tests/wekan-mcp/tools.sh && bash tests/wekan-mcp/skill-surface.sh && bash tests/session-origin/surface.sh && bash tests/session-origin/script.sh && bash tests/agent-perms/surface.sh`
  - C02: `bash tests/pipeline-models/surface.sh && bash tests/agent-board-coord/rulesync-surface.sh && bash tests/wekan-board-provision/surface.sh && bash tests/wekan-board-provision/checklist-cutover.sh && python3 scripts/provision-board.py --fixture tests/wekan-board-provision/fixtures/ai-dev-schema2-matching.json --dry-run && python3 scripts/provision-board.py --fixture tests/wekan-board-provision/fixtures/ai-dev-schema2-drift.json --dry-run`
  - C03a: `bash tests/cf106-noop/surface.sh && bash scripts/session-noop-audit.sh --since 2026-11-02 --until 2026-11-04 && bash tests/noop-marker/surface.sh && bash tests/agent-perms/surface.sh && bash tests/agent-board-coord/gate.sh`
  - C03b: `bash tests/noop-marker/surface.sh && node --test tests/opencode/question-notify.test.ts && node --test tests/opencode/permission-ask-notify.test.ts && bash tests/agent-board-coord/gate.sh && bash tests/agent-board-coord/agents-md.sh`
  - C04: `bash tests/agent-perms/surface.sh && bash tests/standalone-agents/surface.sh && bash tests/pipeline-push-pr/surface.sh && bash tests/agent-board-coord/rulesync-surface.sh`
  - C05: `bash tests/cf90-ledger/surface.sh && bash tests/pipeline-gates/validation-fix.sh && bash tests/agent-perms/surface.sh`
  - C06/C07: `bash tests/wekan-mcp/tools.sh && bash tests/wekan-mcp/skill-surface.sh && bash tests/wekan-mcp/board-context.sh && bash tests/wekan-mcp/dependencies.sh && bash tests/boards-deps/surface.sh && bash tests/board-preload-probe/surface.sh && node --test tests/opencode/board-context.test.ts` — `board-context.sh` nests `gate.sh` and exceeds the default shell timeout (cf-96 FRICTION): run its legs individually before the whole-suite claim.
  - C08/C09: `node --test tests/opencode/pipeline-locks-core.test.ts && node --test tests/opencode/pipeline-locks-engine.test.ts && node --test tests/opencode/pipeline-locks-reap.test.ts && node --test tests/opencode/pipeline-locks-tick.test.ts && bash tests/agent-perms/surface.sh && bash tests/agent-board-coord/rulesync-surface.sh`
  - C10: `bash tests/provider-loops/surface.sh && bash tests/agent-board-coord/gate.sh && bash tests/multi-repo/hourly-board-check.sh && node --test tests/opencode/pipeline-locks-tick.test.ts` — `provider-loops` `t6` (via the nested `gate.sh` `t14`) is RED at plan time for the missing C01 admits; green before C10's claim.
- **regression sweep before the final review**: the C01–C10 batteries above (C03a's and C03b's included) plus `bash tests/coord-inwork/surface.sh && bash tests/boards-deps/surface.sh && bash tests/cf90-ledger/surface.sh && bash tests/wekan-mcp/{create-list,board-provisioning,rest-overview-v102}.sh && bash tests/cf96-coord/surface.sh && bash tests/cf96-lifecycle/surface.sh && bash tests/cf96-siblings/surface.sh && bash tests/cf96-tz/surface.sh && bash tests/cf96-deploy/surface.sh && bash tests/session-origin/{surface,script}.sh && bash tests/standalone-agents/surface.sh && bash tests/agent-explore/surface.sh && bash tests/multi-repo/hourly-board-check.sh && python3 -m py_compile containers/wekan-mcp/wekan_mcp/server.py scripts/provision-board.py && node --test 'tests/opencode/*.test.ts'`.
- **quality**: `npx --yes aislop@0.20.0 ci --changes` (version equals the `aislop-gate` pin and `.github/workflows/aislop.yaml`; `tests/opencode/aislop-pin-parity.test.ts` guards it) + the `comment-slop` pass over every edited comment/docstring.
- **helm**: `helm lint` / `helm template` are **N/A — no chart file in this ticket's blast radius** (explicit N/A line in every chunk's `commands_run`). The `dev` service selection marks `services/dev/prod/values.yaml` (the wekan-mcp pin at line 442) as the ticket's visible deploy seam; touching it is out of scope (card #81 / ledger L4).
- **container**: `docker build => no-daemon, CI-deferred` — the designed passing shape (AGENTS.md; `containers/wekan-mcp` builds in `docker-build.yaml`). No Dockerfile/base change; the image pin bump is USER-owned.
- **surface**: `git diff --name-only $(git merge-base main HEAD)..HEAD` ⊆ the union of the chunks' declared file lists (this ticket's own folder and `scripts/session-noop-audit.sh` ride the admits C01 adds).
- **live legs (USER-owned, never agent-executed)**: `bash scripts/session-noop-audit.sh` readbacks after each scheduled-tick generation post-merge; live `dev-boards tools/list` readback after the pin bump; live AI-Dev `get_checklist` readback after the owner's Model(s) rename; the first tick on the new runner model.

## Risks / assumptions

- **C03's fix covers less than the complaint.** Proven: runs that die mid-turn (malformed `<tool_call>` turns) or without the MCP surface cannot mark themselves, so they will still alert and idle after C03b. The candidate close-out (engine-side marker by `pipeline-locks`, which knows exactly which roots never claimed) is gated on an unproven mechanism — whether a plugin may write session metadata. C03b states the limit instead of shipping a guess; the follow-up card is the honest fallback (owner's board).
- **Ask-as-deny is now a documented pipeline constraint** (OQ-11): unattended subagents cannot run the validation batteries. Mitigation is procedural (interactive runs, owner-run batteries, honest `not-run` lines in `commands_run`), not a grant change — and it is exactly the debt ledger L1 tracks. A chunk that pretends otherwise is not done.
- **C04 is now a doctrine change, not a grant sweep.** The `code`/`code-pr` split must land on all six coord twins + two standalone sources + `pipeline-role-coord` + `pipeline-push-pr` + the `permissions.md` matrix **in one commit** (alias-twin law, A12 parsed equality). The mechanical risk is a `-pr` push row without the `dev-pr` deny floor — hence AC3 reproduces that whole matrix, and `tests/pipeline-push-pr/surface.sh` gains the `code-pr` arm.
- **C02's re-pin cost is confirmed in scope**: four suites, two runbooks, the provision fixtures and the refreshed rule artifact all carry `Qwen 27b` / `Default selection: Qwen Flash` (≈30 `Qwen Flash` hits under `tests/`). A partial sweep leaves parity batteries red; the live checklist keeps the old item name until the owner renames it, so the alias rule is load-bearing.
- **C08 inverts two shipped invariants** (`fsx.open("wx")` exclusivity, one `sessionID` per lock file) that `releaseLockSet`, `checkMember` and `handleLockLost` assume. The owner's "they'll overwrite each other's timestamps, that's fine" authorizes stamp races, **not** cross-holder release or cross-holder reap — C08's ACs pin that boundary.
- **C09 puts a user question on the reap path, and plugins have no question channel.** Until the **Timeout** list exists live, the reaper still degrades to `.pipeline/timeouts.jsonl` + a card comment, so the affordance must work off the reaped-set record.
- **C10 deletes a live-scheduled loop file and changes the model literal.** The repo-side delete does not retire the OpenChamber task; any body edit rotates the fingerprint and force-disables the task until the owner re-approves (cf-90 DECISIONS:127). The new model must actually be served by the arena when the tick fires — a serving change needs a fresh owner ruling, never a silent literal swap.
- **Deploy lag swallows C06/C07 at runtime**: until `wekan-mcp:v87` moves, neither the enriched preload nor the new card read exists in `dev-boards tools/list`; the degrade law keeps runs honest, but the owner must not expect live behavior change from this ticket alone.
- **Services = `agent context` + `dev`**: the second selection is recorded because the ticket's runtime seam is the dev-cluster `wekan-mcp` deployment, but no `services/` or `charts/` file changes here (the pin bump is another card).
- **Type/slug confirmed** (`feat` / `cf-106-feat-coord-fixes`), so the folder/worktree/branch/session names stand as minted.

## USER-owned steps (never agent-executed)

1. **Live board Model(s) rename**: rename the live `Qwen 27b` item to `Qwen Dense` and re-check the createCard rule's default-check, post-backup, read back after. The sanctioned write leg is the owner-confirmed `/wekan-board-provision` apply of the refreshed artifact C02 produces. Agents never rename checklists.
2. **wekan-mcp image pin bump** (`:v87` → a build carrying C01/C06/C07; card #81 / ledger L4, the `services/dev/prod/values.yaml` seam) and the live `tools/list` readback that proves the new tool surface.
3. **Timeout list creation** (the reaper's owed list) — until it lands, C09's affordance rides the reaped-set degrade path.
4. **OpenChamber scheduler hygiene for C10**: re-approve the surviving task's fingerprint after the loop commit, retire/disable the `pipeline-worker-local` task, and **keep `permissionAutoAccept` ("Always Allow") on** — the owner's ruling keeps the toggle as the interim, so ledger L1 stays open and unattended runs depend on it.
5. **Audit-script readbacks** (C03a/C03b): run `bash scripts/session-noop-audit.sh --since … --until …` on the host after each scheduled-tick generation post-merge and paste the table into the ticket folder; the before/after tables are C03a/C03b's proof, and an unattended run cannot do this itself (ask-denied).
6. **Follow-up cards the owner may want to land** (the run proposes, the owner creates): the scheduled-session `dev-boards` MCP-surface-absent defect (found in the evidence table), and, if C03b rejects the engine-side marker on mechanism grounds, the marker-on-abnormal-end gap itself.
7. **Interactive execution for the grant-gated chunks** (OQ-11 consequence, from the Executability-by-role table): **C04** (`.rulesync/subagents/**` = `ask` for dev/test/code, `deny` for coord) and **C03b**'s `.rulesync/commands/**` leg have no unattended path — either the run is interactive so the owner answers the ask, or the owner lands those source edits. Likewise every chunk's validation batteries (`node --test`, `bash tests/…`, `rulesync generate`, `npx aislop`) are owner/interactive-run while the toggle posture stands.
8. Landing the branch: PR creation/merge is the owner's alone; this run ends at local commits on `cf-106-feat-coord-fixes`.

## Open questions — ALL RESOLVED 2026-11-03 by the owner's batched round (kept as the decision record; no re-ask)

1. **Which arm of "not archiving / still alerting" is broken?** RESOLVED: *"I don't know. It's worth investigating."* → the plan stopped guessing and measured it (`…-noop-evidence.md`): marked scheduled runs archive 13/13 (mechanism fine); the failures are runs that never reach a marked exit (three malformed-turn deaths, one MCP-surface-absent run), plus the contract gap on the gate-stop exits. Shape change: **C03 split into C03a (instrument + classification) and C03b (the contract change)**, with C03b's exit set provable and its fix read back through C03a's script.
2. **Type + slug** RESOLVED: keep `feat` / `cf-106-feat-coord-fixes`.
3. **Services** RESOLVED: `agent context` **+ `dev`**, both stay checked on the card at write-back (the `dev` selection names the dev-cluster deploy seam without authorizing a `services/` edit).
4. **Preload scope vs cf-96 OQ3** RESOLVED: coord-side `preload_board` enrichment; the prompt hook stays structural (OQ3 stands) and gains only the claim-time single-card leg → C06/C07 as designed.
5. **Preload checklist shape** RESOLVED: export `fields=` trim, filtered to the standard + legacy checklists → C06 as designed.
6. **`Qwen Dense` scope** RESOLVED: rename the vocabulary label **and** flip both defaults (checklist default and blank-checklist fallback); ids untouched; a live `Qwen 27b` item is consumed as an alias → C02 as designed, fixtures + rule artifact re-pins in scope.
7. **Local provider** RESOLVED: the routing default itself flips to `gpu-ai` (blank Model(s) ⇒ `gpu-ai/qwen3.8-27b-q4` both tiers), openrouter stays the documented fallback, the kickoff provider question recommends `Local` first → C02 as designed.
8. **Multi-card lock semantics** RESOLVED: one lock file per pipeline holding N holders; stamps last-writer-wins; release/lock-lost act only on the caller's holder; still no start on a non-empty pipeline without the human override → C08 as designed.
9. **Reap continue-anyway** RESOLVED: plugin signals only; the coordinator asks exactly once; a "continue" answer re-claims with `pipelines:[<cardId>]` → C09 as designed.
10. **`code` git rights** RESOLVED: *"Commits + push on -pr runs."* → C04 reshaped: `code` gains `git add`/`git commit` (+ non-main branch verbs, main/force floored, `git push` left at `ask`); a new **`code-pr`** twin carries the `agent-dev-pr` push-allow + deny-floor matrix and joins `pipeline-push-pr`'s Applies-to list; the `-pr` coord twins roster `code-pr`, the plain/-local twins roster `code`; coord stays the sole chunk committer.
11. **"Always allow" privs** RESOLVED: *"Keep the UI toggle."* → the validation-battery shell allows are **dropped** from C04; the `ask` baselines stay; ledger L1 stays open; consequence documented (unattended `ask` = deny → validation commands run interactively, by a role that carries the row, or by the owner).
12. **Friction follow-up** RESOLVED: *"That should apply to both coord and board-coord. There should be another option for Inbox that the board-coord prefers."* → C05 reshaped to **five** modes (`new session` / `current session` / `plan only` / `Inbox card` / `none` = skip) in both families, Inbox card recommended on `agent-board-coord` runs, `new session` recommended on plain `agent-coord` runs.
13. **Standalone "Alerting." bullet** RESOLVED: same no-work family; the reap alert stays as-is; no new channel → C03b (pin the reap alert unchanged).
14. **Runner model** RESOLVED: *"Switch to gpu-ai/qwen3.8-27b-q4."* → C10 edits the loop `model:` literal and re-pins `tests/opencode/pipeline-locks-tick.test.ts` T2 + `tests/provider-loops` t1/t3; the fingerprint re-approval rides the same commit (USER-owned step 4).
15. **Custom-field roster** RESOLVED: *"Right now, just slug is active, priority will land with another ticket."* → C01 keeps `slug` as the only active agent-facing field, does **not** declare `Priority`, and reword so other live fields are explicitly outside the agent's read/write surface without falsifying the claim.
