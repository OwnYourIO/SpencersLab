# 2026-10-18 feat: agent workflow tweaks + comment-slop/aislop quality gate

Status: **implemented** (branch worktree, pending user commit/merge). Builds on
2026-10-17-feat-rulesync-building-agents-conversion.md.

## Goal

Six changes to how the agents work, all through the rulesync sources:
plan-folder reorg, coordinator read lockdown, workflow-only coordinator
skills, subagent model routing, `opencode.jsonc` rename, and the full
comment-slop + aislop quality-gate stack (user chose: implement here now,
stay opencode-only — no claudecode target).

## What changed

### 1. Plan folders → `.agents/plans/<yyyy>/<yyyy-mm>-<type>-<slug>/`
- Types: `feat|bug|debug|dep|refactor|chore|docs`; folder keeps its earliest
  month forever; legacy `yyyy-mm/<feature-slug>/` folders stay until migrated
  per-ticket (documented in AGENTS.md + building-agents references).
- Updated: templates/PLAN.md (`feature:` field), all 10 `agent-*` sources
  (shared conventions + coord resolve step + plan create step), rules source,
  building-agents SKILL.md + plan-and-result.md + pipeline-overview.md,
  STATE.json `feature` schema.
- `/pipeline*` commands unchanged: their `find -mindepth 2 -maxdepth 3`
  already matches the new depth.

### 2. Coordinator read lockdown (`agent-coord{,-bmad}`)
- Permissions: removed `read * allow` / `glob *` / `grep *`; added
  `read .agents/plans/** allow` (last-match-wins: default-deny at top).
- Prompts: intro now says exploration/verification belong to subagents;
  new hard rule "your read access ends at `.agents/plans/`".

### 3. Coordinator skills = workflow-only
- coord MUST-loads `/building-agents` + `/executing-plans`; coord-bmad
  `/bmad` + `/building-agents`. Dropped "load top 5 relevant skills"
  dynamic task-skill loading; subagents carry task skills.

### 4. Subagent model routing (verified against live session DB, 85 sessions)
- New "Models for subagents" section in both cords: `agent-plan` →
  `openrouter/qwen/qwen3.8-2.4t-a95b` (large), `agent-dev/test/review` →
  `openrouter/qwen/qwen3.8-27b` (code), unless the user says otherwise.
- Favorited-models map in both cords: openrouter rows (the two defaults +
  gpt-6-astra, qwen3.8-max-0902, qwen3.6-35b-a3b, qwen3.8-flash,
  deepseek-v4.1-flash-1017 — all confirmed in the models.dev catalog), plus
  the self-hosted fallback rows — the only local models marked tool-capable:
  gpu-ai qwen3.8-27b-q8 (+ -1m), gpu-ai qwen3.6-35b-a3b-q8, gpu-moe
  qwen3.6-35b-a3b-q8 (usage-backed: 3+1 sessions on the two gpu-ai ones).

### 5. `.opencode/opencode.json` → `.opencode/opencode.jsonc`
- Renamed via `git mv`. Verified supported: OpenCode V2 discovery searches
  `["opencode.json","opencode.jsonc"]` in every config dir (grep of the
  installed binary), and `opencode debug config` picked the renamed file up
  live with the full 41-server MCP fleet intact.
- All references updated (rules source ×5, agent-dev{,-bmad} permission
  resource, building-agents references ×2, rulesync.jsonc comment).
- `skills/` was already in the `skills` paths array — no addition needed.

### 6. Quality gate: comment-slop + aislop (opencode-only)
- Vendored + SHA-pinned in `.rulesync/skills/` (with `VENDORED.md` records):
  - `comment-slop` ← dashed/claude-marketplace@baedf610
    (auto-invocable, frontmatter verified: name/description non-empty).
  - `aislop` ← scanaislop/skills@e9017219 with the frontmatter patch:
    `disable-model-invocation: true` + `metadata.opencode/autoinvoke: "false"`
    (manual-only via `$aislop`). skill.json/evals/examples/references kept.
    Verified the patch survives `rulesync generate`.
- New root rule `.rulesync/rules/00-comments-and-slop.md` → lands at the top
  of AGENTS.md (00- prefix; user's paste named it the coordinating rule).
- `.opencode/plugin/aislop-gate/index.ts` — hand-written V2 plugin (NOT
  rulesync-generated): after edit/write, runs `npx --yes aislop@0.18.1 scan
  --changes`, debounced + deduped, appends findings to the tool result.
  Pinned CLI version; silent if aislop fails. **Verified live in-session**:
  the plugin hot-loaded and appended a clean 100/100 scan to a write result.
- `.aislop/config.yml` — engines format/lint/code-quality/ai-slop/security
  on, architecture off, `ci.failBelow: 80`, plus `exclude:` for vendored
  upstream trees (`_bmad/**`, `charts/llama-swap/scripts/gguf-py/**`;
  defaults re-listed because an explicit exclude replaces them).
- CI `.github/workflows/aislop.yaml` — PR gate:
  `npx aislop@0.18.1 ci --changes --base origin/main` (the composite
  Action can't pass `--changes`, so direct npx with the same version pin).
  Bootstrap model: changed files must pass; legacy debt tracked locally.
- CI `.github/workflows/rulesync.yaml` — PR drift check:
  `npx rulesync@37.0.0 generate --check`.
- `code` agent and both `agent-dev` variants: new quality-gate paragraph
  (comment-slop on every comment; `$aislop` before handing back; fix
  aislop-gate findings same-turn). In agent-dev{,-bmad} it sits as its own
  `## Quality gate` section after Skills.
- AGENTS.md skills registry: `comment-slop` + `aislop` rows; `.aislop/`
  layout bullet; `.rulesync/` bullet names the vendored skills.
- `.gitignore`: `.rulesync/skills/.curated/` (fetch cache stays out of git).
- Fixed one real gate finding in our own code:
  `skills/wekan-api/scripts/webhook_receiver.py` swallowed-exception error →
  backpressure drops now counted (lock-guarded) and exposed via `/health`
  (`dropped_events`), keeping the intentional 200-fast contract.

## Skill rename + skills-management doc fixes

- Renamed the pipeline skill `building-agents` → `agents-sync` (sources
  dir, SKILL.md name/title, sync-reference examples, coord MUST-load lines,
  registry row). `delete: true` swept the orphaned generated dir; the new
  skill registered live and the old id was retired.
- `.agents/skills/` bullet corrected to reality: third-party skills are
  **tracked in git**, synced from GitHub sources with provenance/integrity
  in `skills-lock.json` (previously claimed "gitignored").
- Dropped the dead `./skill/` entry from the `skills` paths in
  `.opencode/opencode.jsonc` (parses clean after).

## Agents → rule/call skeletons (2026-10-20, round 2)

- Remaining agent body text moved into five role skills (hidden, same
  pattern): `pipeline-role-coord` (identity + loop + hard rules),
  `pipeline-role-plan` (process + chunk template + planning rules),
  `pipeline-role-dev` (quality gate + process + hard rules),
  `pipeline-role-validate` (validate procedure + hard rules),
  `pipeline-role-review` (chunk + final review process + hard rules).
- The `## Hand-off contract` pointer paragraphs dropped — the agents see
  their loaded skills; no restatement needed.
- Agent files are now frontmatter (rules) + one paragraph + the MUST-load
  `/skill` calls: 244–382 words each (was ~550–1,400); all five
  permission blocks verified byte-identical to the pre-split commit.
- Skill count in `.opencode/skills/`: 12 (agents-sync, aislop,
  comment-slop, 4 pipeline contract skills, 5 pipeline role skills).
- Docs: overview.md contract pointer + registry row and the agents-sync
  diagram/domain-context paragraph updated for the role skills.

## Agent text blocks → hidden `pipeline-*` contract skills (2026-10-20)

- The blocks duplicated/inline across the pipeline agents are now four
  rulesync-managed skills, all hidden from auto-selection
  (`disable-model-invocation` + `metadata.opencode/autoinvoke: "false"`,
  same pattern as `aislop`), composed into the agents via MUST-load
  `/skill` calls:
  - `pipeline-conventions` — plan-folder layout, file semantics,
    files-are-the-bus read order, RESULT block (loaded by all 5 pipeline
    agents).
  - `pipeline-kickoff` — new-ticket questions + worktree/branch/session
    naming (coord).
  - `pipeline-models` — role→model routing table + lab favorites map (coord).
  - `pipeline-gates` — deterministic-first, stuck detection, retry caps,
    BLOCKED/NEEDS_INFO handling, deviation logging (coord).
- Agent files slimmed accordingly (coord 1,391→887 words; the four
  subagents lost the ~280-word shared-conventions+RESULT block each,
  replaced by a one-line hand-off pointer). Total pipeline-agent text
  ~3,800 words, contract now single-sourced.
- Docs updated: AGENTS.md `.rulesync/` bullet + contract pointer +
  `pipeline-*` registry row; agents-sync pipeline-overview "Domain
  context" paragraph.

## Tests placement + plan-file naming (2026-10-20, follow-up)

- **No global `tests/`**: tests/validation live in the chart's or
  container's own `tests/` folder. Permission globs changed accordingly —
  agent-validate may edit only `charts/**/tests/**` +
  `containers/**/tests/**`; agent-dev is denied exactly those (was
  root `tests/**` + one-level `*/tests/**`, which wouldn't even have
  matched `charts/<name>/tests/`). Matrices in agents-sync
  permissions.md/pipeline-overview.md updated; validate/dev prompts and
  AGENTS.md mirror wording now say chart/container tests folders.
- **Plans moved off `PLAN.md` onto the dated convention**: the ticket's
  plan of record is now `<yyyy-mm-dd>-<type>-<slug>.md` (same naming as
  standalone plans — one convention everywhere). `templates/PLAN.md` stays
  as boilerplate; agent-plan renames it to the dated name when creating the
  ticket (and still adopts a pre-existing root-level dated plan via git mv).
  All PLAN.md references updated across coord/plan/dev/validate/review,
  overview.md, code.md, plan.md, and the agents-sync skill (SKILL.md diagram,
  plan-and-result layout + new-ticket bullet). The old docs listed BOTH a
  dated file and PLAN.md inside tickets — that contradiction was the
  two-plan-files bug; resolved in favor of the dated file (user decision).
- Validated: frontmatter YAML parses (dev 32 perms, validate 19), new globs
  asserted, regenerate idempotent, --check ✓, no stray PLAN.md references.

## Pipeline phase consolidation + one-plan rule (2026-10-20)

- Duplicate test/validate/review phases collapsed: the chunk loop is now
  `agent-dev` (implement) → `agent-validate` (run validation + full suite) →
  `agent-review` (chunk review), max 3 fix rounds — the separate
  "write failing tests first" phase is gone (this repo's validations are
  helm lint/template + grep checks, not unit tests).
- `agent-test` renamed to `agent-validate` (source rename; `delete: true`
  swept the orphan, generated surface verified at 19 agents; coord's
  subagent permission roster now exactly plan/dev/validate/review).
- New **final review**: after all chunks are done coord launches
  `agent-review` over the whole plan (full diff vs every acceptance
  criterion + DECISIONS.md + friction.md); only its APPROVED sets
  `plan_status: complete`. agent-review's prompt now covers both scopes.
- aislop is enforced via the `.opencode/plugin/aislop-gate/` OpenCode
  plugin (auto-scan on edit/write); the dev/code agent quality gates no
  longer instruct a manual `$aislop` run — the plugin findings are the
  in-loop mechanism, the root AGENTS.md rule stays as the hand-back policy.
- **One plan per piece of work**: dated `yyyy-mm-dd-*` plan files are
  standalone-work only; pipeline tickets keep their single plan of record
  as the ticket's `PLAN.md` (not renamed — the duplicate came from two
  conventions, so `agent-plan` now `git mv`s a pre-existing dated plan
  into the ticket as PLAN.md, and `code`/`plan` agents never write a
  dated plan when a ticket exists). Rule documented in AGENTS.md plans
  bullet, agent-plan step 2, plan.md naming section, code.md fallback.
- Coord favorites map: confirmed `openrouter/qwen/qwen3.8-flash` already
  present (added with the original map).
- Updated: agents-sync SKILL.md + all 4 references (roles, flow, chunk
  lifecycle incl. final review, permission matrix), chunk template
  ("Validation to add"), overview.md (agents bullet, pipeline paragraph,
  specifics bullet reworded off the TDD-era phrasing).

## Coordinator kickoff flow (new-ticket naming)

- New `## Kickoff (new ticket)` section in agent-coord: for a NEW ticket, ask
  (question tool) — project slug (2-3 suggested, type-prefixed), planning
  model (default openrouter/qwen/qwen3.8-2.4t-a95b), model for the rest
  (default openrouter/qwen/qwen3.8-27b), run tag (bare model tag / +run
  number / +variant / user-provided). Kickoff model choices override the
  defaults table for the run.
- Coord then names the run surfaces via the `opencode` tool: `worktree_create`
  `<slug>-<run tag>`, `session_rename` to the slug, `session_move` into the
  worktree (so all subagents of the run work there); answers recorded in
  STATE.json under `kickoff` (schema documented in agents-sync
  plan-and-result.md).
- Permission grant: `action: opencode, resource: '*', effect: allow` —
  constrained by a hard rule to worktree_create/worktree_list/session_rename/
  session_move only; worktree_remove explicitly forbidden.
- `/pipeline` command and agents-sync pipeline-overview updated to lead with
  the kickoff (resume skips it).
- Branch maintenance: merged main into this branch; resolved one conflict in
  services/gpu-ai/prod/values.yaml (kept main's f4c888f67 cache-slot rebalance
  comment + our expanded MoE/solo sets); re-validated merged file (helm render
  clean, 0 OVERRIDE, config assertions pass, merge committed d2f364e9c).

## Coord favorites: kat-coder + global config sync (2026-10-18, follow-up)

- kat-coder tool use CONFIRMED from the Kwaipilot model card: `agent`/
  `agentic-coding` tags, Qwen3.6-35B-A3B base, RL-trained tool labels
  (9.34% → 0.28% anomalies), SWE-bench Verified 69.40 via claude_code
  harness. The global OpenCode config was just missing the
  `capabilities.tools` flags.
- Coord map: added `gpu-ai/kat-coder-q8` + `gpu-moe/kat-coder-q6`; intro
  line now reads "tool-capable local fallbacks" (the earlier caveat about
  kat-coder being non-tool models was wrong and is removed).
- Global configs (machine-local, hand-managed, both backed up as
  `*.bak-20261018`): `~/.config/opencode/opencode.json` and
  `~/.config/kilo/kilo.jsonc` — all 9 kat-coder entries per file gained
  `capabilities: {tools: true, input: [text], output: [text]}`; gpu-ai
  provider gained `qwen36-heretic`, `qwen36-huihui` (tools + vision, 262k)
  and `coder-next-ablit` (tools, text-only, 262k) matching the llama-swap
  roster entries committed in d070a3371.
- Verified live after the config-triggered server restart: `opencode debug
  config` shows all 3 new gpu-ai models and kat tools:true.
- Note: coder-next-ablit tool-calling is upstream-validated (rafw007
  agent-loop deployment) but the plan's Task 5 tool-call smoke test is still
  pending first load post-merge.

## AGENTS.md overlap slimming (user-approved)

- Removed the last bmad mention: the `bmad-*` skills-registry row (BMAD
  skills remain installed third-party; just no longer documented as
  pipeline-wired).
- `## Feature pipeline` section deduplicated against the agents' own
  self-contained shared block: the file-semantics paragraph (STATE/
  DECISIONS/friction writers + lifecycle) and the skills meta-paragraph are
  gone; replaced by a pointer to `.rulesync/subagents/agent-*.md` (the
  operational contract) and the `agents-sync` references. 382 → 250 words;
  AGENTS.md total 2,499 → 2,367 words. Canonical homes for pipeline
  mechanics: agent prompts (runtime contract) + agents-sync references
  (methodology). Verified nothing lost: dev/test tests-only rules live in
  both prompts; file semantics in `plan-and-result.md`.

## `-bmad` variants removed (user: "just remove the bmad variants")

- Deleted sources: 5 agents (`agent-{coord,plan,dev,test,review}-bmad.md`) +
  2 commands (`pipeline-bmad.md`, `pipeline-resume-bmad.md`); `delete: true`
  swept the 5 generated agents, and the 2 generated commands went with their
  sources. Generated surfaces: 19 agents, 2 commands.
- overview.md: all `-bmad` text removed (commands bullet, agents bullet,
  pipeline section, Skills paragraph); the `bmad-*` registry row now says
  the BMAD skills stay installed for direct use but are not pipeline-wired.
- agents-sync skill: repo-specific statements updated (plain set only,
  2 commands, one file per role); the overlay/variant mechanism stays
  documented as portable methodology for other repos.
- The third-party `bmad-*` skills in `.agents/skills/` and the `_bmad/`
  setup are untouched.

## Claude sweep (user: "drop all the claude junk — I don't use claude")

- SDLC stage agents pinned `model: anthropic/claude-{sonnet,opus}-*` — a
  provider with no credentials in this lab (pre-existing on main, imported
  verbatim). Re-mapped to the fleet: `3-plan` + `6-review` (judgment stages,
  were opus) → `openrouter/qwen/qwen3.8-2.4t-a95b`; the other seven stages
  (were sonnet) → `openrouter/qwen/qwen3.8-27b`.
- CLAUDE.md/.cursorrules convention-file fallbacks in the five SDLC bodies →
  plain `AGENTS.md`.
- Vendored `aislop` skill de-Claude'd (deviations recorded in its
  VENDORED.md): skill.json loses claude-code/anthropic keywords +
  compatibility + the "fix with claude" trigger; examples/05-agent-handoff.md
  deleted (Claude Code hand-off demo); SKILL.md fix/hook docs rewritten to
  the in-session flow (`aislop fix -p`, aislop-gate plugin).
- Vendored `comment-slop`: one prose example renamed (VENDORED.md records it).
- The `disable-model-invocation` frontmatter flag stays (harmless outside
  Claude tools; the OpenCode behavior comes from the metadata key).
- Nothing else referenced claudecode targets/hooks — those were never
  implemented (opencode-only decision held).

## Standalone skeletonizing, planner rename, validate→review merge, research agent (2026-10-21)

- **Standalone agents → rule/call skeletons** (same treatment as the pipeline
  agents): `planner`/`code`/`ask`/`debug`/`review` bodies moved into five new
  hidden skills `role-{planner,code,ask,debug,review}` (all
  `disable-model-invocation: true` + `metadata.opencode/autoinvoke: "false"`);
  agent files are now frontmatter + `/skill` MUST-load calls.
- **`plan` → `planner`** (standalone agent only; avoids the built-in plan
  mode). `agent-plan` keeps its name. Source renamed via `git mv`; generated
  `plan.md` swept.
- **`agent-*` user-selectable**: agent-plan/dev/review/research are
  `mode: all` (coord stays `primary`) — every pipeline agent is drivable from
  the agent picker, not just via coord.
- **Chunk grouping**: S tasks up to 5 per chunk (was 3), M tasks up to 2
  related per chunk (was 1), L always alone (`pipeline-role-plan` +
  pipeline-overview doc).
- **Validate stage removed** (user: "validation isn't catching much, so is a
  waste"): `agent-validate` + `pipeline-role-validate` deleted; its verbiage
  merged into `pipeline-role-review` — review now runs the validation
  commands + full suite as step 1, then reviews; coord's loop is dev → review
  (fix rounds: dev → review). ~~Review inherits validate's edit grants so it
  can fix a broken validation~~ — superseded by the correction section below:
  review edits nothing, the fix routes to the authoring session via coord +
  user confirmation. Coord's chunk-done gate now reads
  the validation proof from review's RESULT `commands_run`.
- **`friction.md` → `FRICTION.md`** everywhere (conventions layout + read
  order, coord loop/permissions — globs are case-sensitive, coord permission
  resource updated, templates renamed via `git mv`, docs).
- **`agent-research`** added: deep, citation-grounded research via the `storm`
  skill + `global-searxng` MCP; summary lands in the ticket folder as
  `RESEARCH.md` next to the plan file. `mode: all`; webfetch/websearch
  allowed; write access only `.agents/plans/**`. Research is commissioned,
  never ad hoc: any agent reports a need via RESULT/open_questions, it
  bubbles up through coord (new "Research" section in `pipeline-role-coord`,
  coord's launch roster now plan/research/dev/review), coord launches research;
  `pipeline-role-plan` reads `RESEARCH.md` first and returns `NEEDS_INFO` +
  `Needs research: yes` instead of planning on guesses; conventions read
  order includes `RESEARCH.md`; `pipeline-models` routes research on the
  large tier.
- **aislop plugin audit** (user request, checked against the live session
  store): the aislop-gate plugin fired in **51 sessions / 331 edit/write
  results**, including this fusion session (19 hits) and the pipeline
  dev/test/plan/review subagent sessions from the coder-workspace run —
  confirming it runs automatically after the dev/code agents edit.
- Docs kept current: AGENTS.md/overview (Agents bullets, pipeline specifics,
  research bullet), agents-sync SKILL + references (roles, flow, permission
  matrix incl. research row, chunk lifecycle, drift-incident entry for the
  validate merge + FRICTION rename), plan-and-result layout/lifecycle,
  syncing-to-other-repos smoke test, kickoff Q3 (dev/review), chunk template
  section ("Validation (review agent runs)").

## Correction: reviewer never edits tests + dedicated test writer (2026-10-21, user fixes)

- The previous section gave review validate's `tests/` edit grants so it could
  fix a broken validation itself — **vetoed by the user**. Correct flow: if a
  validation/test fails and review judges the test (not the code) at fault,
  review returns `BLOCKED` with `validation_at_fault:` details and touches
  nothing; the coordinator **always asks the user** to confirm sending the fix
  back to the session that wrote the test, or a fresh session if the original
  is gone.
- A brief intermediate state (dev as validation author, its `tests/` denies
  flipped to allows) was also staged-only and is **reverted**: the user wants
  dev to never write tests.
- **New agent `agent-test`** (test writer): writes the tests for **every chunk
  of the plan in one session**, after the plan is approved and before any dev
  starts. `mode: all` (user-selectable), code-tier model. Writes ONLY test
  files (chart/container `tests/` folders) + context (self-written `skills/`,
  `.rulesync/rules/**`, `.rulesync/skills/**` allowed; other `.rulesync/**` +
  generator configs ask; starts from `edit * deny`) — never implementation
  code, never plans. Role skill: `pipeline-role-test`.
- Coord: new loop step 2 "Tests" (one launch for the whole plan); the session
  ID is recorded as top-level `test_session` in STATE.json (the
  per-chunk `dev_session` field is dropped — the test session is the single
  author); the `validation_at_fault` branch routes to `test_session`. Roster:
  plan/research/test/dev/review.
- Dev: `tests/` denies restored; hard rule back to "tests are read-only
  (agent-test wrote them); escalate a wrong test via BLOCKED".
- Planner: each chunk file's "## Tests" list must be concrete enough to write
  tests from before implementation exists (chunk template section renamed
  "## Tests (agent-test writes, review runs)").
- Docs synced: pipeline-models (test on the code tier), kickoff Q3
  (test/dev/review), gates (test-session routing), plan-and-result (lifecycle
  + `test_session` schema), permissions.md (+test row, drift entry rewritten
  to the final state), pipeline-overview (roles, tests phase, matrix),
  agents-sync SKILL, AGENTS.md overview.
- Note: this revives a test-writing phase (dropped in the 2026-10-20 phase
  consolidation) in a different shape — one session for the whole plan,
  positioned after planning rather than per-chunk.

## Post-generation review tweaks (2026-10-21)

- **`agent-cord` → `agent-coord`** everywhere: source + role skill renamed
  (`pipeline-role-cord` → `pipeline-role-coord`), prose "cord" → "coord"
  across skills/docs/changelog, both `/pipeline*` commands route to
  `agent-coord`, generated `agent-cord.md`/`pipeline-role-cord/` swept.
- **Skills registry removed from AGENTS.md** — agents already see the skill
  list in-session. All 10 skeleton agents' dynamic-pick line now reads
  "evaluate the task against the skills available to you"; the `0-pipeline`
  dispatcher and agents-sync loading guidance reworded to match.
- **agent-plan loads 5** dynamic skills (was 3).
- **S-chunk grouping**: mixing unrelated S tasks is now explicitly fine
  ("they're small"); M stays "up to 2 related".
- **coord hard rules**: dropped the redundant read-access rule (already in
  the role intro and enforced by permissions); the opencode-tool rule is now
  just "exists only to name the run. Never call any other opencode tool."
- **pipeline-conventions**: removed the "You were told to load this skill in
  your prompt" line.
- **role-code Git safety**: added "You may leave changes uncommitted for
  review on the main branch if asked."; the `git checkout/switch/commit/push`
  prose enumeration replaced with a pointer to the permission rules — the
  `ask` rules for those four commands already exist in `code.md`.

## Skill-read grants, friction follow-ups, question-notify plugin (2026-10-21)

- **Skill reads pre-granted for all agent-\***: every agent-\* source now
  carries explicit `read` allows for `.opencode/skills/**`, `.agents/skills/**`
  and `skills/**` — for coord (deny-all baseline) this is the actual grant;
  for the others it makes the implicit `read *` explicit so skill loading
  never prompts regardless of how the glob matcher treats dot-directories.
- **Friction follow-up at plan completion**: coord step 9 — after the final
  report, coord asks the user (question tool) whether to spin up a new
  `agent-plan` session per open `FRICTION.md` item; each confirmed item gets
  its own planning session (friction line + ticket/chunk context as the
  request) and becomes a new ticket. Mirrored in plan-and-result lifecycle +
  AGENTS.md pipeline bullet.
- **`question-notify` plugin** (`.opencode/plugin/question-notify/index.ts`,
  hand-written like aislop-gate): when any `agent-*` session invokes the
  `question` tool, pushes a Home Assistant notification to the user's phone
  (`notify/mobile_app_pixel_6`). Determinism: plugins run in the server
  process where MCP tools don't exist for models — so it speaks MCP JSON-RPC
  (streamable HTTP: initialize → initialized → `tools/call call_service`)
  directly to the `admin-global-homeassistant` endpoint (readonly ha-mcp
  rejects service calls), URL discovered at runtime from `ctx.mcp.list()`
  with a `.opencode/opencode.jsonc` parse fallback. Agent filter via
  `event.sessionID`/`event.agent` → `ctx.session.get` (prefix `agent-`),
  15s per-session cooldown, fire-and-forget — a notification can never block
  a question. Unverified paths (event field names, handshake tolerance) log
  one-time debug keys to opencode.log. AGENTS.md `.opencode/` bullet now
  lists both plugins.
- **Dev fixes return to the implementing session** (user directive): on
  `CHANGES_REQUESTED`, coord directs the fix to the session that originally
  implemented the chunk — continuing that dev session via its sessionID
  (`chunks.<id>.dev_session` is back in the STATE.json schema, recorded on
  every dev hand-back); a fresh session is acceptable only when the
  continuation fails/is gone. Reviews are ALWAYS fresh sessions, never
  continued. Mirrored in plan-and-result (schema + lifecycle) and
  pipeline-overview flow. Contrast with test fixes: those require explicit
  user confirmation; dev fix rounds are the normal loop and don't.
- aislop-gate live-check while writing the plugin: fired on the write,
  100/100 clean run.
- Event shape verified afterwards against `@opencode/plugin@2.1.2` types
  (`dist/promise/tool.d.ts` via unpkg): `execute.before` carries
  `{ tool, sessionID, agent, messageID, id, input }` — `event.agent` is read
  directly, with a `ctx.session.get` fallback kept only because the installed
  CLI (v2.0.32) predates the checked types. (Lesson logged: the plugins guide
  names the hook event types without defining them; the definitions live in
  the npm package's .d.ts, pullable from the CDN even when the package isn't
  installed.)

## Validation

- `rulesync generate` idempotent; `rulesync generate --check` ✓.
- Generated surfaces swept + created: `.opencode/agents/{plan,agent-validate}.md`
  gone; `planner.md` + `agent-research.md` present; `.opencode/skills/`
  gains `role-*` ×5 + `pipeline-role-research`, loses `pipeline-role-validate`;
  all six new skills keep the hidden flags after generation; agent-plan/dev/
  review/research generate `mode: all`, coord `mode: primary`; coord permission
  resources show `FRICTION.md` and the research/test subagent grants;
  agent-test has tests+context allows only; dev and review have zero
  `tests/**` allows.
- Semantic permission diff vs main: cords +read plans/−glob/grep/broad-read;
  nothing else changed unexpectedly (python tuple-compare of all 24 agents).
- `opencode debug config`: renamed jsonc loaded, 41-server fleet parsed.
- `aislop ci --changes --human` on this changeset: **91/100, 0 errors, exit 0**
  (4 warnings = intentional elif dispatch ladder in the wekan starter script).
- Full-repo `aislop ci` baseline (for awareness, not gated in CI yet):
  score 43 with vendored trees excluded — legacy debt concentrated in
  charts/llama-swap scripts (138 repetitive-dispatch warnings),
  skills/wekan-api, containers/{traefik-mqtt-allowlist,wekan-mcp}, src/java.
- Generated aislop skill frontmatter keeps `metadata.opencode/autoinvoke`
  after generation; comment-slop auto-discovered live, aislop stays hidden.
- helm lint/template: N/A (no charts touched).

## Follow-ups (user-owned)

- Commit + PR on the current branch.
- The 4 dispatch-ladder warnings in webhook_receiver.py are deliberate
  starter-script style; convert to a handler map if the skill graduates.
- Pay down legacy aislop debt incrementally (each PR gates its own files).
- Watch rulesync #2592 (V2 hooks for OpenCode) — if it ships, the
  hand-written aislop-gate plugin logic could move to `.rulesync/hooks.json`.
