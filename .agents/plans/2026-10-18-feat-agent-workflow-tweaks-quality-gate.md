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
  (shared conventions + cord resolve step + plan create step), rules source,
  building-agents SKILL.md + plan-and-result.md + pipeline-overview.md,
  STATE.json `feature` schema.
- `/pipeline*` commands unchanged: their `find -mindepth 2 -maxdepth 3`
  already matches the new depth.

### 2. Coordinator read lockdown (`agent-cord{,-bmad}`)
- Permissions: removed `read * allow` / `glob *` / `grep *`; added
  `read .agents/plans/** allow` (last-match-wins: default-deny at top).
- Prompts: intro now says exploration/verification belong to subagents;
  new hard rule "your read access ends at `.agents/plans/`".

### 3. Coordinator skills = workflow-only
- cord MUST-loads `/building-agents` + `/executing-plans`; cord-bmad
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
  dir, SKILL.md name/title, sync-reference examples, cord MUST-load lines,
  registry row). `delete: true` swept the orphaned generated dir; the new
  skill registered live and the old id was retired.
- `.agents/skills/` bullet corrected to reality: third-party skills are
  **tracked in git**, synced from GitHub sources with provenance/integrity
  in `skills-lock.json` (previously claimed "gitignored").
- Dropped the dead `./skill/` entry from the `skills` paths in
  `.opencode/opencode.jsonc` (parses clean after).

## `-bmad` variants removed (user: "just remove the bmad variants")

- Deleted sources: 5 agents (`agent-{cord,plan,dev,test,review}-bmad.md`) +
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

## Validation

- `rulesync generate` idempotent; `rulesync generate --check` ✓.
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
