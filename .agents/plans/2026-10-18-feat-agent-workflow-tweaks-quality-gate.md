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
  All PLAN.md references updated across cord/plan/dev/validate/review,
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
  swept the orphan, generated surface verified at 19 agents; cord's
  subagent permission roster now exactly plan/dev/validate/review).
- New **final review**: after all chunks are done cord launches
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

- New `## Kickoff (new ticket)` section in agent-cord: for a NEW ticket, ask
  (question tool) — project slug (2-3 suggested, type-prefixed), planning
  model (default openrouter/qwen/qwen3.8-2.4t-a95b), model for the rest
  (default openrouter/qwen/qwen3.8-27b), run tag (bare model tag / +run
  number / +variant / user-provided). Kickoff model choices override the
  defaults table for the run.
- Cord then names the run surfaces via the `opencode` tool: `worktree_create`
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
