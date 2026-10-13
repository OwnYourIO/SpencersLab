# Plan: Incorporate the staged agent-* pipeline + fix context generally

## Goal
Turn the staged `agent-*` chunk-pipeline set into a first-class, repo-grounded
part of SpencersLab: fix its broken wiring (nonexistent `agent-cord-and-plan`
reference, commands invisible to OpenCode, `question`/`skill` permission gaps,
single-level plan globs), enforce skill loading via `/skill-name` (mandatory
BMAD role skills in the `-bmad` variants), organize pipeline artifacts into
`.agents/plans/yyyy-mm/<feature-slug>/` folders, strip every `steps:` cap
everywhere, grant `question` to every agent/subagent, migrate the five
standalone agents to V2 frontmatter, and document the whole system in
`AGENTS.md`.

## Skills
executing-plans, opencode

## MCP Servers
None — local file edits only.

## Verified context
- Staged set (git): 10 agent files (`agent-{cord,plan,dev,test,review}{,-bmad}.md`),
  4 commands (`pipeline{,-bmad}`, `pipeline-resume{,-bmad}`), and root-level
  scaffolding `.agents/plans/{PLAN.md,DECISIONS.md,STATE.json,chunks/C01.md}`.
- Staged files already use OpenCode **V2** `permissions:` list syntax
  (verified against https://opencode.ai/v2/docs/agents: ordered list,
  last-match-wins, broad rules first). Older agents use legacy V1
  `permission:` maps; repo went "Native V2" 2026-10-12 per `.opencode/opencode.json`.
- V2 docs confirm: `steps` caps model steps; legacy fields (`permission`,
  `tools`, `temperature`, …) should not be used in new V2 configs; commands
  are discovered only from `.opencode/commands/` (project) or global config.
- `.opencode/` has tracked symlinks `agents` and `skills` (git mode 120000)
  but **no `commands` link** — the four staged commands are invisible to OpenCode.
- `commands/pipeline*.md` reference `agent: agent-cord-and-plan` — **no such
  agent exists**; `agent-cord` already holds permission to launch `agent-plan`.
- `agent-dev*`/`agent-test*` set `question: deny`; the 9 SDLC stage agents
  never grant `question` (only covered today by the global `question: allow`
  rule in `agent-config.jsonc`); `agent-plan/dev/test/review` never grant the
  `skill` action.
- `steps:` caps live in 3 places: 10 staged files, 14 older agent `.md`
  files, and the 18 agent entries in `agent-config.jsonc` (global config,
  symlinked into HomeAssistant + CuratedForest too).
- `_bmad/` is installed in this repo only (not in the sibling repos).
  BMAD skills installed: `bmad-agent-pm` (the PM skill — no literal
  `bmad-pm` exists), `bmad-spec`, `bmad-ticket`, `bmad-build`,
  `bmad-qa-generate-e2e-tests`, `bmad-code-review`, `bmad`.
- Sibling repos (HomeAssistant, CuratedForest.com) have the same
  plan/code/ask/debug/review agents minus repo specifics and no agent-* set.

## Design decisions
1. **V2 `permissions:` lists everywhere** (staged files are already V2; V2
   docs forbid legacy maps in new configs).
2. **Commands wired via a new tracked symlink** `.opencode/commands ->
   ../.agents/commands` (mode 120000, same pattern as `agents`/`skills`).
3. **No `agent-cord-and-plan`**: `agent-cord` gains Phase 1 — it launches
   `agent-plan` when no approved plan exists; commands point at
   `agent-cord`/`agent-cord-bmad`.
4. **Feature folders** `.agents/plans/yyyy-mm/<feature-slug>/` (user's
   choice: month bucket + slug); staged root scaffolding becomes
   `.agents/plans/templates/`, copied per feature by `agent-plan`;
   `STATE.json` gains a `feature` field.
5. **Repo grounding lives in AGENTS.md, not in the agent files.** AGENTS.md
   is auto-loaded into every session including subagents (the pattern every
   existing agent in this repo already uses). The agent-* bodies stay fully
   repo-agnostic and portable to HomeAssistant/CuratedForest; the new
   "Feature pipeline" section in AGENTS.md carries the repo specifics
   (validation-as-tests, hard rules apply). No `## This repo (SpencersLab)`
   blocks in any agent file.
6. **Skills as step 5** of the shared "Read first, then act" list, forceful
   wording, `/skill-name` slash invocation. The old line "Never start a
   message with `/skill-name`" is deleted from all 10 files. BMAD variants
   get per-role MUST-load blocks instead of the duplicated generic paragraph.
7. **agent-test is the mirror of agent-dev** (user revision): same worker
   framing and skeleton, inverted test permissions (`tests/**` allow,
   everything else deny — where dev has `*` allow, `tests/**` deny). Jobs A/B
   stay (cord's loop dispatches both); `bmad-agent-pm` added to plan-bmad's
   required skills (user revision).
8. **Sources kept intact**: nothing removed from plan.md/code.md/README.md —
   the standalone agents keep working unchanged (user's choice); README is
   user-facing chart docs, untouched.

## Changes

### 1. `.opencode/commands` — [CREATE symlink]
Tracked symlink `.opencode/commands -> ../.agents/commands` (git mode 120000,
same as the existing `.opencode/agents` / `.opencode/skills` links).

### 2. `.agents/plans/templates/` — [CREATE from staged root files]
`PLAN.md`, `DECISIONS.md`, `STATE.json`, `chunks/C01.md` move to
`.agents/plans/templates/…`; the four root copies are deleted. Edits:
- `STATE.json`: add `"feature": ""` as the first field.
- `PLAN.md`: add second line `feature: <yyyy-mm>/<feature-slug>` under title.
- `DECISIONS.md`, `chunks/C01.md`: unchanged.

### 3. All 10 `agent-*` files — [MODIFY] shared transform
- Delete the `steps:` frontmatter line.
- Add colors: cord `#06b6d4`, plan `#8b5cf6`, dev `#f59e0b`, test `#22c55e`,
  review `#ef4444` (same for `-bmad` twins).
- Ensure permission entries exist: `{ action: "read"|"glob"|"grep"|"skill"|"question",
  resource: "*", effect: allow }`; `agent-dev*`/`agent-test*` flip explicit
  `question: deny` → allow.
- Edit resources `.agents/plans/*` → `.agents/plans/**`, `tests/*` → `tests/**`.
- Delete the paragraph "Never start a message with `/skill-name`…".
- After the opening paragraph add the standard pointer line: *"All repo
  layout, conventions, and hard rules live in `AGENTS.md` — it is loaded into
  your context automatically; follow it."*
- Replace the shared conventions block with the feature-folder version whose
  "Read first, then act" list ends with step 5 (mandatory skill loading via
  `/skill-name` or the `skill` tool). RESULT block kept verbatim.

### 4. `agent-plan.md` — [MODIFY]
V2 frontmatter: edit deny-all + `.agents/plans/**` allow; read/glob/grep/
skill/question allow; subagent deny; shell ask + git read-only/ls/helm
lint/template allows; `admin*` deny, `readonly*`/`global*` allow.
Body: Process gains the feature-folder step (create
`.agents/plans/yyyy-mm/<feature-slug>/`, copy templates, record folder in
`STATE.json` `feature`); all path references become feature-folder relative.

### 5. `agent-cord.md` — [MODIFY]
Frontmatter: staged deny-first block kept; edit allows become
`.agents/plans/**/STATE.json` and `.agents/plans/**/DECISIONS.md`.
Body: loop step 1 rewritten — resolve the feature folder (ask the user if
several exist), and if none exists or `plan_status != "approved"`, run
Phase 1 by launching `agent-plan` with the user's request; continue only once
`STATE.json` shows approved (never approve on the user's behalf). Gates
wording generalizes to "the commands in PLAN.md 'Commands' passing". Paths
become feature-folder relative.

### 6. `agent-dev.md` — [MODIFY]
Permissions: edit `*` allow, `tests/**` + `*/tests/**` deny,
`.agents/plans/**` deny; read/glob/grep/skill/question allow; shell ask +
git read-only/helm allows; MCP rules kept. Body: hard rule "you have no
user" replaced with "escalate via NEEDS_INFO/open_questions; use the
question tool only when blocked on a decision only the user can make";
Process step 4 says "the commands in PLAN.md 'Commands'" instead of
"lint/typecheck".

### 7. `agent-test.md` — [MODIFY] (mirror of dev)
Permissions: the exact mirror — edit `*` deny, `tests/**` + `*/tests/**`
allow, `.agents/plans/**` deny; everything else identical to dev. Body:
dev-shaped opening ("You write that chunk's failing tests without touching
the implementation"), Job A as the main Process (read chunk → survey test
conventions → one+ test per criterion → fail for the right reason → run
existing suite → RESULT), Job B kept as the second mode (cord's step c),
hard rules mirror dev's.

### 8. `agent-review.md` — [MODIFY]
Permissions: staged set + read/glob/grep/skill allow, `.agents/plans/**`
edit allow, helm lint/template shell allows. Body: lens (f) extended to
"conventions in `DECISIONS.md` and the repo rules in `AGENTS.md`".

### 9. The five `-bmad` variants — [MODIFY]
Same transforms as their base twins (cord-bmad launches the `-bmad`
subagents), plus description suffix `" (BMAD: enforces BMAD role skills)"`
and a per-role mandatory block replacing the duplicated generic paragraph:

| File | MUST-load skills |
|---|---|
| agent-plan-bmad | `/bmad-agent-pm`, `/bmad-spec`, `/bmad-ticket` |
| agent-dev-bmad | `/bmad-build` |
| agent-test-bmad | `/bmad-qa-generate-e2e-tests` |
| agent-review-bmad | `/bmad-code-review` |
| agent-cord-bmad | `/bmad` |

Each ends: use the `/skill-name` slash command (or the `skill` tool); follow
the BMAD workflow inside the pipeline; chunk file and RESULT block still
govern hand-offs — plus the kept `<!-- add further skill instructions here -->`.

### 10. `.agents/commands/*` — [MODIFY] all 4
- `pipeline.md`/`pipeline-bmad.md`: `agent: agent-cord` / `agent-cord-bmad`
  (fixes nonexistent `agent-cord-and-plan`); state block becomes a find-based
  dump of every feature folder's STATE.json.
- `pipeline-resume.md`/`pipeline-resume-bmad.md`: feature folder from
  `$ARGUMENTS`; if empty, list STATE.json-bearing folders and ask which.

### 11. Standalone agents V2 migration — [MODIFY]
`plan.md`, `code.md`, `ask.md`, `debug.md`, `review.md`: delete `steps:`,
rewrite each `permission:` map into an equivalent V2 `permissions:` list
(broad rule first, exceptions after; `bash` → `action: shell`; keep
`todowrite`/`todoread`, `list`, `webfetch`/`websearch`, helm patterns; keep
description/mode/color; bodies untouched).

### 12. SDLC stage agents — [MODIFY] `0-pipeline.md` … `7b-docs-dev.md` (9 files)
Two mechanical edits each: delete the `steps:` line; add `question: allow`
under `skill: allow` in the permission map (their bodies already call
`question` at every stage gate).

### 13. `agent-config.jsonc` — [MODIFY]
Delete the `"steps": N,` line from all 18 agent entries. (Global config,
symlinked into all three repos — intended per user choice.)

### 14. `AGENTS.md` — [MODIFY]
- **Where things live**: add bullets for `.agents/commands/` and
  `.agents/plans/templates/`; extend the `.agents/plans/` bullet with the
  `yyyy-mm/<feature-slug>/` pipeline folders.
- **Agents**: add bullet for the `agent-*` set + `/pipeline` commands.
- **New section `## Feature pipeline (agent-*)`** after Agents: roles,
  commands, feature-folder layout, files-are-the-bus + RESULT summary, BMAD
  notes (`_bmad/` installed here; `-bmad` variants halt elsewhere), and a
  "### Pipeline specifics in this repo" subsection (validation-as-tests:
  helm lint/template + service-trio greps + secret-placeholder matching;
  all Hard rules apply to pipeline agents; agent files stay repo-agnostic).
- **Skills registry**: add `bmad-*` row (forced skills of the `-bmad`
  pipeline variants).
- **Hard rules**: add bullet — every agent/subagent must keep `question`
  allowed explicitly, or questions are denied by default.

## Verification
1. `grep -rn "^steps:" .agents/agents/` → zero; `grep -c '"steps"'
   agent-config.jsonc` → 0.
2. Every agent grants question: `grep -L question .agents/agents/*.md` → no
   matches among frontmatters; `grep -rn "question.*deny" .agents/agents/` →
   zero.
3. YAML-parse every agent frontmatter (python yaml) — catches list/map slips;
   confirm no `permission:` (singular) key remains in any frontmatter.
4. `grep -c "/skill" .agents/agents/agent-*.md` ≥ 1 each; `grep -rn "Never
   start a message with" .agents/` → zero.
5. `ls -L .opencode/commands/pipeline.md` resolves; templates exist;
   `.agents/plans/PLAN.md|DECISIONS.md|STATE.json|chunks/` gone from root.
6. Path consistency re-read: `yyyy-mm/<feature-slug>/` everywhere, `**`
   globs in every permission touching plans.
7. JSON-parse agent-config.jsonc (comments stripped) to confirm still valid.

## Risks & open questions
- `admin*`/`readonly*`/`global*` MCP permission actions kept exactly as
  staged; V2 docs don't enumerate MCP action naming — rests on staged design.
- Kilo shares these files; it tolerated V1 maps, V2-list parsing unverified.
  OpenCode is the primary client.
- agent-config.jsonc edits affect HomeAssistant/CuratedForest sessions
  immediately (step caps gone there too) — intended.
- Adjacent, out of scope: `0-pipeline.md` launches stages via V1 `task:`
  permissions (V2 name: `subagent`). If stage launches misbehave, migrate
  that block next.
- BMAD variants require `_bmad/` (SpencersLab only); elsewhere they HALT by
  design of the bmad skills.

## Outcome (filled during implementation)
All 14 changes applied and verified 2026-10-13:
- `steps:` removed everywhere: 0 in `.agents/agents/*.md`, 0 in
  `agent-config.jsonc` (all 18 entries; file re-parsed as valid JSON/JSONC).
- `question: allow` explicit in all 24 agent files; `question: deny` appears
  nowhere (agent-dev/agent-test flipped; 9 SDLC stage agents granted it).
- All 24 frontmatters YAML-parse; no legacy `permission:` key remains in the
  15 migrated files (the 9 SDLC stage agents keep their V1 maps by plan
  step 12 — steps+question only).
- `/skill` invocation present in all 10 agent-* files; the old "Never start
  a message with /skill-name" line is gone; 5 bmad variants carry per-role
  `## Domain: BMAD (required)` blocks.
- Templates live at `.agents/plans/templates/` (PLAN/DECISIONS/STATE/chunks);
  plan root is clean; `STATE.json` template carries `"feature"`.
- `.opencode/commands` symlink resolves; commands reference `agent-cord` /
  `agent-cord-bmad` (the nonexistent `agent-cord-and-plan` is gone); state
  blocks are feature-folder aware.
- All 10 agent files use `yyyy-mm/<feature-slug>/` and `**` plans globs.
- AGENTS.md: Where-things-live, Agents, new "Feature pipeline (agent-*)"
  section (+ repo-specifics subsection), bmad-* skills row, and the
  question-allowed hard rule added.
- Not committed — awaiting user go-ahead for branch + commit.

### Follow-up round (same session)
User revision: the skill `/call`s live in the agent files themselves.
- Every pipeline agent gained a `## Skills` section restoring the standard
  loading rule ("The first thing you MUST always do is load the skills
  listed in the plan… top 5 relevant skills") plus a MUST-load `/skill-name`
  call list:
  - plan: `/helm-bjw-s-chart`, `/gitops-workflows`, `/writing-plans`,
    `/helm-chart-creation`, `/kubernetes-skill`, `/argocd-advanced`,
    `/using-git-worktrees` (7)
  - dev & test: `/helm-bjw-s-chart`, `/gitops-workflows`,
    `/helm-chart-creation`, `/executing-plans`, `/kubernetes-skill`,
    `/test-driven-development`, `/argocd-advanced` (7)
  - review: `/helm-bjw-s-chart`, `/gitops-workflows`, `/helm-chart-creation`,
    `/kubernetes-skill`, `/argocd-advanced`, `/container-security` (6)
  - cord: loading rule only (orchestrates; loads per feature need)
- `-bmad` variants prepend their BMAD role skills to the same list
  (plan +3: `bmad-agent-pm`/`bmad-spec`/`bmad-ticket`; dev `bmad-build`;
  test `bmad-qa-generate-e2e-tests`; review `bmad-code-review`;
  cord `/bmad`) — the former trailing "Domain: BMAD" section was merged
  into `## Skills`, keeping the `<!-- add further skill instructions here -->`
  marker in all 5 variants.
- Re-verified: 10/10 frontmatters parse, exactly one `## Skills` section
  each, RESULT block intact, 5/5 extension markers present.

### Revision round 3 (same session, from user line comments)
- Removed the 3 hardcoded extra `/call`s from all 8 role files; replaced
  with: "Then evaluate the task against the `AGENTS.md` skills registry and
  load 3 more relevant skills dynamically at runtime, the same way
  (`/skill-name`)." Final hard lists: plan 4 (+3 bmad), dev/test 4 (+1 bmad),
  review 3 (+1 bmad), cord none, cord-bmad `/bmad`.
- Dropped the step-5 "Load your skills NOW" line from the shared read-first
  list in all 10 files — the top-of-file `## Skills` section owns skill
  loading ("in favor of the first section").
- cord/cord-bmad step 3c: added the note to reference each needed skill with
  a `/skill-name` slash command in the launch message.
- AGENTS.md pipeline paragraph updated to match (Skills section + 3 dynamic
  skills + slash-reference-on-dispatch).
- Cleanup pass: fixed missing blank line before the runtime note (all 8 role
  files); full re-verification green (frontmatter, Skills sections, RESULT
  blocks, question allows, no steps, no stale lines).