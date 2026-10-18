# 2026-10-17 feat: rulesync setup — convert building-agents + .opencode/agents

Status: **implemented** (branch `can-you-load-the-rulesync-skill-as-well-as-buildin/openrouter-qwen-qwen3-8-2-4t-a95b`, pending user commit/merge)

## Goal

Make `.rulesync/` the single source of truth for this repo's AI-tool config:
convert the existing `.opencode/agents/` agents and `/pipeline*` commands into
rulesync sources, and convert the Aerofarms `building-agents` skill (its
generic, non-BMAD, non-MES/Fabric/K8s core) into a portable rulesync skill.
Sync to repos outside this one comes later (via `rulesync fetch` /
declarative `sources:`); this repo goes first, OpenCode as the only target.

## What changed

### rulesync.jsonc (rewritten)
- `targets: ["opencode"]` (was codexcli+claudecode+opencode — those would
  create `.codex/`, `.claude/`, `CLAUDE.md`, `.mcp.json`, root `opencode.jsonc`,
  none of which this repo uses).
- `features: ["rules","subagents","commands","skills"]` — MCP, permissions,
  hooks stay OFF: the MCP fleet and repo permissions remain hand-managed in
  `.opencode/opencode.json` (revisitable later).
- `delete: true` kept, safe after the symlink fix below; `rulesync gitignore`
  is documented as never-run (it would gitignore AGENTS.md).

### Boilerplate removed
The `rulesync init` scaffold (sample TS rules, sample `planner` subagent,
deepwiki/playwright MCP sample, sample permissions/hooks, `project-context`
skill) was deleted. A dry-run had proven it destructive for this repo:
`delete: true` + skills feature would have swept all of `.agents/skills/`
(every third-party skill, via the `.opencode/skills` symlink) and all 24 real
agents, and overwritten AGENTS.md with TypeScript boilerplate.

### Import (rulesync import --targets opencode --features rules,subagents,commands)
- `AGENTS.md` → `.rulesync/rules/overview.md` (root rule).
- 24 agents `.opencode/agents/*.md` → `.rulesync/subagents/` (ordered v2
  `permissions:` lists preserved under `opencode:` blocks).
- 4 commands `.opencode/commands/*.md` → `.rulesync/commands/`.
- Skills deliberately NOT imported (would have pulled every third-party skill
  via the `skills` paths in opencode.json).

### Symlink hazard fixed
`.opencode/skills` was a symlink → `../.agents/skills`; replaced with a real
directory so the skills feature can own it without sweeping third-party
skills. Those stay discoverable via the existing `skills` paths entry
(`./.agents/skills`) in `.opencode/opencode.json`.

### building-agents conversion → `.rulesync/skills/building-agents/`
Generalized from the Aerofarms skill (untracked copy in the main checkout):
- `SKILL.md` — architecture with `.rulesync/` + `rulesync generate` replacing
  the Python generators; roles; prefix-free variant naming; per-ticket plan
  layout; files-are-the-bus; editing workflow; hard-won lessons
  (permission drift, verify syncs landed, one branch one concern).
  Fabric/MES/K8s domain packs, BMAD overlays, engine-probe T-SQL specifics
  and both Python scripts dropped.
- `references/pipeline-overview.md` — how the pipeline runs in this repo,
  permissions summary, known OpenCode v2 issues (incl. the v2.0.24
  enforcement verification recipe).
- `references/plan-and-result.md` — plan folders, STATE.json schema,
  RESULT block (now with `friction:`), chunk + friction lifecycles.
- `references/permissions.md` — rule grammar (ordered, last match wins),
  role matrix incl. the new dev context-file table, audit checklist,
  drift-incident history.
- `references/syncing-to-other-repos.md` — the future cross-repo story:
  declarative `sources:`/`rulesync install` (rules+skills), `rulesync fetch`
  (any feature incl. subagents/commands), or copy+re-target; per-repo
  adaptation table + skills-symlink hazard warning + post-install checklist.

### Friction log (building-agents' core generic mechanism, new to this repo)
- `.agents/plans/templates/friction.md` — blank template (agent-plan copies
  the whole templates dir, so it flows automatically).
- All 10 `agent-*` sources (5 roles × plain/bmad): RESULT block gains a
  `friction:` line; shared conventions gain the `friction.md` bullet and
  read-at-start step.
- Both cord variants: loop step 4 appends reported + own friction after the
  STATE.json write; hard rule + description updated; permission
  `edit .agents/plans/**/friction.md allow` added.

### Dev context-file lockdown (building-agents' drift-incident fix, adapted)
`agent-dev{,-bmad}` had `edit * allow` with only tests/plans denied — the
exact "dev over-broad edit" incident building-agents hit on 2026-10-14, now
more dangerous since AGENTS.md/agents are generated (a dev hand-edit is
silently overwritten on the next generate). Added, ordered last-match-wins:
- allow: `skills/**`, `.rulesync/rules/**`, `.rulesync/skills/**`
  (repo-context sources — edit + report under deviations)
- ask: `.rulesync/**`, `.opencode/opencode.json`, `skills-lock.json`,
  `rulesync.jsonc` (agent machinery — explicit approval; the broad ask
  precedes the two context-source allows so those win)
- deny: `AGENTS.md`, `.opencode/{agents,commands,skills}/**` (generated
  surfaces), `.kilo/**` + `.agents/**` (plans cord/plan-owned, third-party
  skills registry-managed)
Plus a hard-rule line in the dev prompts explaining generated surfaces.

### AGENTS.md (now generated)
Root rule source updated to document: `.rulesync/` as source of truth, the
generated surfaces under `.opencode/`, friction.md in templates and in the
per-ticket layout, cord's friction.md ownership, the building-agents
registry row, and a hard rule against hand-editing generated surfaces.
`rulesync generate` reproduces AGENTS.md from it.

## Validation

- `rulesync generate` — 25 files written (24 subagents + 1 skill); second run
  "All files are up to date" (idempotent); `rulesync generate --check` passes.
- Round-trip fidelity: AGENTS.md initially byte-identical after import+generate;
  semantic YAML comparison of all 24 agents old-vs-new — only intended diffs
  (cord friction perms/description, dev lockdown); bodies differ only by a
  cosmetic blank line after frontmatter.
- Live enforcement probe against the running OpenCode server (v2.0.32,
  `opencode api get /api/agent` with `x-opencode-directory`): all 24 agents
  loaded; `agent-dev` has all 32 rules incl. the lockdown; `agent-cord`
  allowed exactly its 4 plain subagents + exactly STATE.json/DECISIONS.md/
  friction.md edits; `agent-cord-bmad` allowed exactly its 4 `-bmad`
  subagents (cross-variant isolation intact).
- Untouched (verified via git status): `.opencode/opencode.json`,
  `skills-lock.json`, `.agents/skills/` (all third-party skills intact).
- The generated `building-agents` skill was auto-discovered by OpenCode the
  moment it was written; the regenerated AGENTS.md reloaded live.

## Fusion note (same-day parallel runs merged)

Two refinements ported from parallel attempts at the same task:
- `rulesync.jsonc` comment now carries the evidence-backed reason mcp/
  permissions/hooks stay OFF (rulesync's OpenCode adapter rewrites a root
  `opencode.jsonc` `mcp` key in flat V1 shape, which would fight the
  41-server V2 `mcp.servers` fleet in `.opencode/opencode.json`; hooks would
  emit `.opencode/plugins/rulesync-hooks.js` from nothing).
- The `.rulesync/` bullet in the rules source (→ AGENTS.md) now documents
  `rulesync generate --check` as the freshness verifier and why generated
  files stay tracked (fresh clone/worktree works without running rulesync).
The other attempts' deltas were not ported: one migrated only 10 of 24
agents (`delete: false`, building-agents deferred — superseded here), the
other additionally fanned out to `claudecode`/`codexcli` targets
(CLAUDE.md/.claude/.codex — no such tools in use here; widening `targets`
later remains a one-line change).

## Follow-ups (not done, user-owned)

- Commit + PR (agent work ends at local changes; landing is the user's call).
- The original `skills/building-agents/` copy in the main checkout stays
  untracked there — it belongs to the Aerofarms repos; delete or keep as
  reference at the user's discretion.
- Later: sync to external repos per `.rulesync/skills/building-agents/references/syncing-to-other-repos.md`;
  optionally migrate MCP/permissions/hooks into rulesync features.