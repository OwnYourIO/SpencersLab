# Plan: Standardize agent context files across 7 repos (kilo + opencode) — rev 2

Rev 2 changes vs rev 1 (user feedback 2026-09-26):
1. **`.claude` and `CLAUDE.md` are dropped entirely** — never created; removed
   (with `git rm`) wherever they exist. `AGENTS.md` is the only instruction
   file (both kilo and opencode read it natively).
2. **Verbatim-reuse policy**: every standard block below is copied word-for-word
   from the strongest existing source (fabric `rules/git-workflow.md` for
   branch rules, SpencersLab/HALbF for skill + plan rules, kilo's built-in
   ask/debug/review prompts for the new agents). Repo-specific content is
   preserved verbatim. Merge only where sources differ.
3. **`skills/helm-chart-creation` documents the expected context locations** —
   new Phase 1 step adds a "Repo context locations" section to the skill so
   chart work knows the standard layout (user request 2026-09-26).

## Goal

Every target repo gets one standard agent-context layout that works in **both**
kilo 7.7.7 and opencode v2.0.16: a tracked `.agents/` directory (agents,
plans, gitignored third-party skills, worktrees), a single root `AGENTS.md`,
tracked `skills-lock.json`, standard `.gitignore` entries, and five
single-file agents (plan, code, ask, debug, review) that fold kilo's layered
built-ins into repo files. SpencersLab keeps its numbered pipeline agents and
is the single tracked home of the global MCP/permission config
(`agent-config.jsonc`), symlinked into `~/.config/kilo/kilo.jsonc` and
`~/.config/opencode/opencode.json`.

Target repos: SpencersLab, HomeAssistant, brother-ptouch-automation,
CuratedForest.com, Home-Assistant-Label-based-Features, ha-mcp,
pictaria-server. Reference-only (no changes): fabric, k8s.

## Skills

Code agent: load `kilo-config` (kilo/opencode config paths, agent-manager
behavior) and `using-git-worktrees` (worktree move/prune mechanics). No Helm,
container, or cluster skills are needed — this is filesystem + git work.

## MCP Servers

None. This plan is pure filesystem and git; no cluster or service access.

## Verified context

Verified against installed binaries and the repos themselves (2026-09-26):

- **kilo 7.7.7** loads config/agents from `.kilo`/`.kilocode` dirs (walk-up),
  agent files via glob `{agent,agents}/**/*.md` (both names work), skills from
  `.claude`/`.agents`/`.kilocode`/`.kilo`, instructions `AGENTS.md`,
  `CLAUDE.md`, `CONTEXT.md`. Plan mode writes to `.kilo/plans`.
  `kilo agent list` / `kilo debug config` work non-interactively.
- **opencode v2.0.16** natively scans `.claude`, `.agents`, `.opencode` as
  config dirs, same `{agent,agents}/**/*.md` glob, reads `AGENTS.md`.
  `opencode debug agents` / `opencode debug config` work non-interactively.
- **Compatibility test performed**: an `opencode.json` containing JSONC
  comments + kilo-style `permission` map + kilo-style `mcp` entries parses
  cleanly in opencode v2 (it translates permission→permissions, bash→shell,
  mcp→mcp.servers). One shared config file works for both CLIs.
- **SpencersLab Phase 0/1 is already staged** in this worktree (branch
  `refactor-agents-to-support-opencode`): `agent-config.jsonc` created,
  ask/debug/review agents added, `.opencode` + `.claude` symlinks + `CLAUDE.md`
  staged, `skillfish.json` deleted, `.skillfish.json` untracked, AGENTS.md
  updated. The global symlinks already exist but point at the **worktree**
  path. Rev-2 corrections are in Phase 1 below.

Audit vs the expected standard (state at recon time):

| Repo | State found |
|---|---|
| SpencersLab | agents plural (11 files incl. pipeline) ✅; `.agents/worktrees/` was not gitignored (fixed in staged work); `.agents/skills/…/.skillfish.json` was tracked (fixed); skillfish.json's `ha-integration-dev` was missing from the lock (fixed); inner `.agents/.gitignore` now tracked; extra `.agents/notes/` (keep) |
| HomeAssistant | `.kilo` symlink tracked, `.opencode` symlink untracked; agents **singular** `agent/` (plan+code reference `.kilo/plans`); skills-lock.json present, no skillfish.json; inner `.agents/.gitignore` untracked; `.agents/package.json` (@kilocode/plugin runtime — covered by inner gitignore) |
| brother-ptouch | `.kilo` REAL dir: 2 registered worktrees + 1 **epoch-named** plan (`1786213324692-…`); `.opencode -> .agents` symlink untracked; `.claude` real dir (empty skills/); `CLAUDE.md`→AGENTS.md symlink tracked (to remove); no agents; non-standard `skill/SKILL.md` (skill name `label-printer`); AGENTS.md references "root CLAUDE.md" twice; skills-lock.json (7 skills) |
| CuratedForest.com | `.kilo` REAL dir: 9 registered worktrees + 1 **epoch-named** plan (`1790181728684-…`); `.opencode` **broken** symlink; no agents, no skills-lock; AGENTS.md line 24 mentions a `CLAUDE.md` symlink (stale — remove); rich domain content to keep |
| HA-Label-based-Features | `.kilo` REAL dir: **23 registered worktrees** + 1 plan + byte-identical duplicate agent files; `.claude` symlink + `CLAUDE.md` symlink tracked (to remove), `.opencode` symlink untracked; agents singular; skills-lock.json (9 skills) **gitignored**, `.kilo/` gitignored |
| ha-mcp | `.opencode` **broken** symlink; no `.agents`/`.kilo`; CLAUDE.md only (466 lines, real file — becomes AGENTS.md); tracked skill bundle `.claude/skills/ha-mcp/` (5 skills) + doc references to it; gitnexus doc reference points at non-existent `.claude/skills/gitnexus/`; no skills-lock |
| pictaria-server | Nothing: no `.agents`, no symlinks; AGENTS.md (37 lines Linear↔GitHub PR rules); CLAUDE.md = 11-byte `@AGENTS.md` import (to remove); `prompts/` is app-level (keep) |

Reference takeaways used: fabric (`rules/git-workflow.md` — the forceful
branch rules copied verbatim below; plan-agent skill preamble), k8s (minimal
`.agents/` + AGENTS.md registry tables), kilo source prompts (`ask.txt`,
`debug.txt`, `soul.txt`, `/review` command prompt in `kilocode/review`).

## Design decisions

1. **Canonical dir `.agents/`; tracked symlinks `.kilo -> .agents` and
   `.opencode -> .agents` only.** kilo needs `.kilo`; opencode reads
   `.agents` natively but the `.opencode` symlink keeps legacy paths working.
   **No `.claude` symlink and no `CLAUDE.md`** — dropped entirely (user
   decision, rev 2); existing ones are `git rm`'d.
2. **Agent dir is plural `.agents/agents/`** (user decision). HA and HALbF
   rename `agent/` → `agents/` via `git mv`. Both CLIs accept either.
3. **Five standard agents per repo: plan, code, ask, debug, review**, all
   `mode: all`, single-file with kilo-style frontmatter (verified compatible).
   ask/debug/review bodies are **verbatim copies** of kilo's built-in prompts
   (templates below). SpencersLab additionally keeps `0-pipeline`…`7b-docs-dev`
   unchanged.
4. **Global tool config lives in SpencersLab as `agent-config.jsonc`** (repo
   root), content = the full former `~/.config/kilo/kilo.jsonc`.
   `~/.config/kilo/kilo.jsonc` and `~/.config/opencode/opencode.json` are
   symlinks to it (done; currently point at the worktree path — re-point to
   `/home/coder/SpencersLab/agent-config.jsonc` when the branch lands on main).
5. **skills-lock.json in every repo, tracked, never ignored.** Empty where no
   third-party skills: `{"version": 1, "skills": {}}`. **skillfish.json is
   removed everywhere**; SpencersLab's `ha-integration-dev` entry was migrated
   into its lock first (done, staged).
6. **Skill-loading rule** — exact user wording, goes verbatim into every
   AGENTS.md Skills section and every agent's Skills section:
   "Evaluate your skills and load the top 5 relevant to the task, and any
   included in the plan."
7. **Verbatim-merge policy** (rev 2): the standard blocks below are copied
   word-for-word into every repo's AGENTS.md; repo-specific rules stay
   verbatim in their own bullets/sections; where sources differed (branch
   rules), the merged text below is the single standard. Do not paraphrase.
8. **`.agents/skills/` stays gitignored** (synced third-party content);
   self-managed skills live in tracked `skills/`. ha-mcp's bundle moves
   `.claude/skills/ha-mcp/*` → `skills/ha-mcp-*`. brother-ptouch's
   `skill/SKILL.md` → `skills/label-printer/SKILL.md`.
9. **Worktrees move, never delete**: `git worktree move .kilo/worktrees/<n>
   .agents/worktrees/<n>`, then remove the emptied real `.kilo` and symlink
   it. Epoch-named plans are renamed to `yyyy-mm-dd-<type>-<desc>.md` using
   their first-commit date (`git log --diff-filter=A --format=%cs -- <file>`).
10. **Plans**: `.agents/plans/`, naming `yyyy-mm-dd-<type>-<short-desc>.md`,
    never epoch. Empty dirs get `.gitkeep`.
11. **Inner `.agents/.gitignore` is tracked** (no self-ignore line) — shields
    Agent-Manager runtime files in every repo.
12. **AGENTS.md standard sections**: Purpose · Repository layout · Agents ·
    Skills (rule + registry) · MCP servers · Plans · Hard rules · Verification
    commands · References. Existing repo content is preserved verbatim and
    reorganized under these headings; the standard blocks below are inserted
    verbatim.

## The standard layout (target for all 7 repos)

```
<repo>/
├── AGENTS.md                  # only instruction file; standard sections
├── skills-lock.json           # tracked; {"version":1,"skills":{}} if empty
├── skills/                    # tracked self-managed skills (where present)
├── .gitignore                 # includes: .agents/skills/  .agents/worktrees/
├── .agents/
│   ├── .gitignore             # tracked (template below)
│   ├── agents/                # plan.md code.md ask.md debug.md review.md
│   ├── plans/                 # .gitkeep when empty
│   ├── skills/                # gitignored (third-party)
│   └── worktrees/             # gitignored
├── .kilo -> .agents           # tracked symlink
└── .opencode -> .agents       # tracked symlink
```

Inner `.agents/.gitignore` template (tracked):

```
node_modules
package.json
package-lock.json
pnpm-lock.yaml
bun.lock
yarn.lock
agent-manager.json
```

Root `.gitignore` standard additions:

```
.agents/skills/
.agents/worktrees/
```

## Standard blocks (copy VERBATIM)

### Block A — Hard rules (git/branch/skills/plans)

Merged verbatim from SpencersLab `AGENTS.md` (skill rule, plan rule) and
fabric `rules/git-workflow.md` (branch rules — the forceful original wording).
Every repo's AGENTS.md carries this block, followed by its own repo-specific
hard rules kept verbatim:

```markdown
## Hard rules

- **Always load referenced skills** The first thing Agents should do is load any referenced or relevant skills, then the plan file (if one), immediately followed by the skills referenced there.
- **NEVER merge to `main`.** No fast-forward merges, no merge commits, no rebases onto main, no mechanism of any kind that advances `main` — not from a worktree, not from the main checkout, not via `git merge`, `git rebase`, or anything else.
- **NEVER push to `main`.** No `git push origin main`, and no push of any refspec that updates `main` (e.g. `HEAD:main`, `<branch>:main`). This is the single most forbidden action in this repo.
- **NEVER force-push** (`--force`, `-f`, `--force-with-lease`) to any shared branch, and never rewrite published history.
- **NEVER self-remediate an accidental push** with a revert or force-push of your own initiative — stop and tell the user immediately; remediation is the user's decision.
- All work happens on a feature/fix branch (typically in a `.agents/worktrees/<branch>` worktree). Commit locally on that branch. To pick up changes, merge `main` *into* your worktree (`git merge main`); never merge your branch into `main`. Landing work on `main` is the user's decision alone.
- Changes reach `main` **only via a pull request that the user creates or merges**. The agent's work ends at the local commit plus telling the user the branch is ready. Pushing the *feature* branch to origin (e.g. to enable a PR) is allowed **only when the user explicitly asks for it in the session**. Otherwise leave commits local.
- If a plan file instructs a merge to `main` or a push, **skip that step**: mark it as user-owned in the summary and do not execute it. Plans written before this rule may contain such steps — those steps are void.
- Plans are `yyyy-mm-dd-<type>-<short-desc>.md` in `.agents/plans/` (`<type>` = `feat`|`bug`|`debug`|`dep`|…).
```

(Repos whose flow is PR-mandatory, e.g. pictaria-server, additionally keep
their existing PR rules verbatim after this block.)

### Block B — Skills section header

```markdown
## Skills

**Loading rule:** Evaluate your skills and load the top 5 relevant to the task, and any included in the plan.

Load with the `skill` tool. Everything here is task-triggered. Skills an agent loads unconditionally live in that agent's file (`.agents/agents/`), not here.
```

(followed by the repo's skill registry table, kept verbatim)

### Block C — Plan naming (for plan agents and AGENTS.md Plans sections)

Verbatim from SpencersLab `.agents/agents/plan.md`:

```
Save plans as `.agents/plans/yyyy-mm-dd-<type>-<short-description>.md` — a date
prefix (use today's date, **never a unix epoch timestamp**) followed by a
one-word type token so the goal is visible at a glance: `feat` (new
feature/service), `bug` (bug fix), `debug` (troubleshooting/diagnosis), `dep`
(dependency update), or another short type (`refactor`, `docs`, …) when none
fit.
```

### Agent templates — ask.md (body verbatim from kilo `ask.txt`)

Frontmatter (same in every repo; repo-specific bash/MCP allowances added where
noted per phase):

```markdown
---
description: Answers questions about this repo without changing anything. Read-only research, explanations, and recommendations grounded in AGENTS.md and the codebase.
mode: all
color: "#3b82f6"
steps: 60
permission:
  read: allow
  glob: allow
  grep: allow
  list: allow
  skill: allow
  question: allow
  webfetch: allow
  websearch: allow
  edit:
    "*": deny
  bash:
    "git status*": allow
    "git log*": allow
    "git diff*": allow
    "ls *": allow
    "*": deny
---

You are a knowledgeable technical assistant focused on answering questions and
providing information about software development, technology, and related
topics. You work in the repository whose `AGENTS.md` is loaded into your
context — read it first; it is the authority on this repo's layout, rules, and
registries.

Guidelines:
- Answer questions thoroughly with clear explanations and relevant examples
- Analyze code, explain concepts, and provide recommendations without making changes
- Use Mermaid diagrams when they help clarify your response
- Do not edit files or execute commands; this agent is read-only
- If a question requires implementation, suggest switching to a different agent

## Skills

Evaluate your skills and load the top 5 relevant to the task, and any included
in the plan.
```

### Agent templates — debug.md (body verbatim from kilo `debug.txt`)

```markdown
---
description: Diagnoses and fixes issues in this repo with systematic debugging — hypothesize, validate with evidence, then apply minimal targeted fixes.
mode: all
color: "#ef4444"
steps: 150
permission:
  read: allow
  glob: allow
  grep: allow
  list: allow
  skill: allow
  question: allow
  todowrite: allow
  todoread: allow
  edit:
    "*": allow
  bash:
    "git status*": allow
    "git log*": allow
    "git diff*": allow
    "ls *": allow
    "*": ask
---

You are an expert software debugger specializing in systematic problem
diagnosis and resolution. You work in the repository whose `AGENTS.md` is
loaded into your context — read it first and follow its hard rules and
verification commands.

Guidelines:
- Reflect on 5-7 different possible sources of the problem
- Distill those down to 1-2 most likely sources
- Add logging or diagnostic output to validate your assumptions before making fixes
- Explicitly ask the user to confirm the diagnosis before applying a fix
- Prefer minimal, targeted fixes over broad refactors

## Skills

Evaluate your skills and load the top 5 relevant to the task, and any included
in the plan. `systematic-debugging` is a strong default here.
```

### Agent templates — review.md (faithful copy of kilo's `/review` prompt)

```markdown
---
description: Advisory code reviewer. Reviews changes (uncommitted by default, or a branch/commit when asked) for security, performance, business logic, deploy safety, duplication, and dead code. Never edits during review.
mode: all
color: "#10b981"
steps: 100
permission:
  read: allow
  glob: allow
  grep: allow
  list: allow
  skill: allow
  question: allow
  edit:
    "*": deny
  bash:
    "git status*": allow
    "git log*": allow
    "git diff*": allow
    "git show*": allow
    "git merge-base*": allow
    "git rev-parse*": allow
    "git ls-files*": allow
    "ls *": allow
    "*": ask
---

You are an expert code reviewer with deep expertise in software engineering
best practices, security vulnerabilities, performance optimization, and code
quality. Your role is advisory — provide clear, actionable feedback but DO NOT
modify any files. Do not use any file editing tools.

You work in the repository whose `AGENTS.md` is loaded into your context —
read it first; review against this repo's hard rules and conventions.

## Determining the Diff Scope

If the request names a scope, use it; otherwise default to uncommitted:

- **Uncommitted** (default): staged + unstaged + untracked. Gather with
  `git diff HEAD` (tracked changes; exclude lockfiles), `git diff --cached`
  (staged-only), and `git ls-files --others --exclude-standard` (untracked —
  read each file in full).
- **Unpushed**: commits ahead of upstream — `git log @{u}..HEAD --oneline`,
  then `git diff @{u}..HEAD`.
- **Branch**: diff against the base branch — `git merge-base HEAD <base>`,
  then `git diff <merge-base>..HEAD`.
- **Commit**: `git show <commit>`.

ONLY review changes in the selected scope. Never flag pre-existing code
outside it.

## Review Focus

Permitted tracks: security, performance, business logic, deploy safety,
duplication, dead code.

Always out of scope: style, naming, formatting, lint-only issues, and generic
refactors with no bug or product risk.

Deploy safety: flag missing migration/rollback plans, unsafe rollout ordering,
feature-flag gaps, and breaking schema/config changes only when the reviewed
change introduces them.

Duplication: flag only when it creates bug or drift risk (two copies that must
stay in sync); do not flag incidental similarity.

Dead code: flag only when the reviewed change itself orphans the code.

## How to Review

1. **Start from the diff**: read full file context when needed; diffs alone
   can be misleading, as code that looks wrong in isolation may be correct
   given surrounding logic.

2. **Tools usage**: use read-only git commands and file reads to gather
   context. Do not use any file editing tools.

3. **Be confident**: only flag issues where you have high confidence. Use
   these thresholds:
   - **CRITICAL (95%+)**: Security vulnerabilities, data loss risks, crashes, authentication bypasses
   - **WARNING (85%+)**: Bugs, logic errors, performance issues, unhandled errors
   - **SUGGESTION (75%+)**: Code quality improvements, best practices, maintainability
   - **Below 75%**: Don't report — gather more context first or omit the finding

4. **Assign severity by impact**: CRITICAL — security, data loss, crashes,
   auth bypass, unsafe rollout. WARNING — bugs, logic errors, performance,
   unhandled errors. SUGGESTION — non-blocking, tied to a permitted track and
   a concrete risk.

5. **Finding quality**: one finding = one issue, with the exact changed line.
   No praise, no style notes. Prefer no findings over weak findings.

## Output Format

Your review MUST follow this exact format:

## Review for **<scope>**

### Summary
2-3 sentences describing what this change does and your overall assessment.

### Issues Found
| Severity | File:Line | Issue |
|----------|-----------|-------|
| CRITICAL | path/file.ts:42 | Brief description |
| WARNING | path/file.ts:78 | Brief description |
| SUGGESTION | path/file.ts:15 | Brief description |

If no issues found: "No issues found."

### Detailed Findings
For each issue listed in the table above:
- **File:** `path/to/file.ts:line`
- **Confidence:** X%
- **Problem:** What's wrong and why it matters
- **Suggestion:** Recommended fix with code snippet if applicable

If no issues found: "No detailed findings."

### Recommendation
One of:
- **APPROVE** — Code is ready to merge/commit
- **APPROVE WITH SUGGESTIONS** — Minor improvements suggested but not blocking
- **NEEDS CHANGES** — Issues must be addressed before merging

## Post-Review Workflow

You MUST first write the COMPLETE review above (Summary, Issues Found,
Detailed Findings, Recommendation) as regular text output. Do NOT use the
question tool until the entire review text has been written.

ONLY AFTER the full review is written:

- If your recommendation is **APPROVE** with no issues found, you are done. Do
  NOT call the question tool.
- If your recommendation is **APPROVE WITH SUGGESTIONS** or **NEEDS CHANGES**,
  THEN call the question tool to offer next steps (e.g. fix via the code
  agent, investigate via the debug agent).

Only an explicit user request to fix switches you into implementation
behavior, and only for reviewed findings.

## Skills

Evaluate your skills and load the top 5 relevant to the task, and any included
in the plan.
```

(SpencersLab's review.md additionally allows `"helm lint*"` / `"helm template*"`
in bash; HA/HALbF add the read-only `homeassistant_*` subset — see phases.)

### plan.md / code.md base

Where a repo has existing plan/code agents (SpencersLab, HomeAssistant,
HALbF): keep them **verbatim**; only fix `.kilo/plans` → `.agents/plans` path
references and align the Skills section with the standard rule. Where a repo
has none (brother-ptouch, CuratedForest, ha-mcp, pictaria): copy SpencersLab's
`.agents/agents/plan.md` and `code.md` verbatim as the base, then change only:
the role/identity line, the Iron Law's artifact list, the permission block
(bash allowlist for the repo's toolchain; MCP tool allowlists where the repo
uses live-instance MCP servers), and the pre-completion checklist items. All
other wording stays verbatim.

## Changes

Work per repo on a feature branch (never push/merge to main — Block A).

### Phase 0 — global config (DONE, verify only)

`agent-config.jsonc` exists in SpencersLab; `~/.config/kilo/kilo.jsonc` and
`~/.config/opencode/opencode.json` are symlinks to it (currently the worktree
path). Verify: `kilo debug config` + `opencode debug config` show the MCP
servers. **Follow-up when this branch lands on main (user merges):** re-point
both symlinks to `/home/coder/SpencersLab/agent-config.jsonc`, then the
worktree may be removed.

### Phase 1 — SpencersLab: correct the staged rev-1 work

1. `.claude` — [REMOVE] `git rm -f .claude` (staged symlink; delete from disk).
2. `CLAUDE.md` — [REMOVE] `git rm -f CLAUDE.md` (staged symlink; delete).
3. `AGENTS.md` — [MODIFY] (a) layout bullet: change "`.kilo`, `.opencode`,
   `.claude` — tracked symlinks to `.agents/`, so kilo, opencode, and Claude
   Code all load the same agents…" → "`.kilo`, `.opencode` — tracked symlinks
   to `.agents/`, so kilo and opencode load the same agents, plans, and
   skills."; (b) replace the Hard rules section's first two bullets with
   **Block A verbatim** (keep the SpencersLab-specific bullets that follow:
   never bump versions, validate chart changes, secrets, adding-a-service
   trio).
4. `.agents/agents/ask.md` — [REWRITE] with the ask template above (body is
   the verbatim kilo `ask.txt` text + AGENTS.md anchor; the staged version was
   paraphrased).
5. `.agents/agents/debug.md` — [REWRITE] with the debug template above
   (verbatim kilo `debug.txt` text).
6. `.agents/agents/review.md` — [REWRITE] with the review template above
   (faithful `/review` prompt copy; keep the `helm lint`/`helm template` bash
   allowances in the frontmatter).
7. `.agents/agents/plan.md`, `code.md`, pipeline agents — untouched (already
   original wording; staged skill-rule tweak stays).
8. Everything else staged in rev 1 stays: `agent-config.jsonc`,
   `.opencode` symlink, `.gitignore` addition, inner `.agents/.gitignore`,
   skills-lock.json `ha-integration-dev` entry, skillfish.json deletion.
9. `skills/helm-chart-creation/SKILL.md` — [MODIFY] insert a new
   `## Repo context locations` section between the "Deep-dives in
   `references/`" block and `## When to use / when not`, with exactly this
   content (wording matches the root AGENTS.md layout bullets):

   ```markdown
   ## Repo context locations

   Standard agent-context layout for this repo (mirrors root `AGENTS.md`):

   - `.agents/agents/` — agent definitions (`plan`, `code`, `ask`, `debug`,
     `review`, plus the numbered pipeline agents `0-pipeline`…`7b-docs-dev`).
   - `.agents/plans/` — plan documents, named `yyyy-mm-dd-<type>-<short-desc>.md`
     (date prefix, **never** a unix epoch; `<type>` = `feat`|`bug`|`debug`|`dep`|…).
   - `.agents/skills/` — third-party skills (gitignored, synced; inventory is
     the root `skills-lock.json`); don't hand-edit those.
   - `skills/` — self-written skills (`helm-chart-creation` — this one,
     `container-creation`, `llama-swap`).
   - `.kilo`, `.opencode` — tracked symlinks to `.agents/`, so kilo and
     opencode load the same agents, plans, and skills.
   - `agent-config.jsonc` — global agent tool config (permissions, MCP
     servers, UI prefs), symlinked into `~/.config/kilo/kilo.jsonc` and
     `~/.config/opencode/opencode.json`.
   ```

### Phase 2 — HomeAssistant

1. `.agents/agent` → `.agents/agents` — [RENAME] `git mv`.
2. `.agents/agents/plan.md`, `code.md` — [MODIFY] `.kilo/plans` →
   `.agents/plans` (all references incl. plan-naming section, which switches
   to Block C verbatim); Skills section → standard rule; keep the
   `homeassistant_*` permission allowlists verbatim.
3. `.agents/agents/ask.md`, `debug.md`, `review.md` — [CREATE] from templates;
   ask/debug additionally allow the read-only `homeassistant_*` inspection
   tools (copy the read-only subset verbatim from plan.md's permission block);
   debug also gets `homeassistant_validate_config`,
   `homeassistant_render_template`.
4. `.opencode` — [TRACK] (`git add`; symlink already correct). `.kilo` already
   tracked. No `.claude`, no CLAUDE.md (and none created).
5. `AGENTS.md` — [MODIFY] (a) `.kilo/plans/` → `.agents/plans/` (hard-rules +
   layout entries); (b) drop the "(`.kilo/skills/` is the same directory as
   `.agents/skills/`.)" note, add the standard layout note (`.kilo`,
   `.opencode` symlinks); (c) replace Hard rules' first bullet cluster with
   **Block A verbatim** keeping the HA-specific rules that follow; (d) Skills
   section header → **Block B**; (e) Agents section: list all five agents with
   file paths; (f) MCP section: prepend "Servers are defined in
   `agent-config.jsonc` in the SpencersLab repo, symlinked into
   `~/.config/kilo/kilo.jsonc` and `~/.config/opencode/opencode.json`."
6. `.agents/.gitignore` — [MODIFY] drop self-ignore line, `git add`.
7. `skills-lock.json` — keep as-is (9 skills, tracked).

### Phase 3 — brother-ptouch-automation

1. Worktrees — [MOVE] `git worktree move .kilo/worktrees/implement-ha-icons
   .agents/worktrees/implement-ha-icons` (create `.agents/worktrees/` first);
   same for `mulberry-ferry`.
2. `.kilo/plans/1786213324692-ha-mdi-icons-and-service-image.md` —
   [MOVE+RENAME] → `.agents/plans/<first-commit-date>-feat-ha-mdi-icons-and-service-image.md`.
3. `.kilo` — [REPLACE] delete the emptied real dir (runtime files only);
   `ln -s .agents .kilo`; track. `.opencode` — [TRACK].
4. `CLAUDE.md` — [REMOVE] `git rm CLAUDE.md` (tracked symlink). `.claude` —
   [REMOVE] real dir (untracked, empty `skills/`) — delete from disk.
5. `.agents/agents/{plan,code,ask,debug,review}.md` — [CREATE] all five per
   the base rule (SpencersLab verbatim base + Python/uv substitutions: bash
   allowlist `uv *`, `pytest*`, `ruff *`, `lp *` render-only; no MCP tool
   permissions; code-agent edit scope `src/**`, `tests/**`, `templates/**`,
   `containers/**`, `docs/**`, `skills/**`, `.agents/plans/**`, `AGENTS.md`,
   else ask).
6. `skill/SKILL.md` → `skills/label-printer/SKILL.md` — [MOVE] `git mv`
   (frontmatter name is `label-printer`); remove empty `skill/`.
7. `skills-lock.json` — keep (7 skills, tracked).
8. `.agents/.gitignore`, `.agents/plans/.gitkeep` — [CREATE] per templates.
9. `.gitignore` — [MODIFY] add `.agents/worktrees/` (`.agents/skills/` exists).
10. `AGENTS.md` — [MODIFY] keep all domain content verbatim; (a) "Snake_case
    for Python (per root CLAUDE.md)" → "(per root AGENTS.md)"; project-structure
    tree line `├── CLAUDE.md` → `├── AGENTS.md`; (b) insert standard sections:
    Agents (five), Skills (**Block B** + registry row for `label-printer` in
    `skills/`), MCP servers (global set via SpencersLab `agent-config.jsonc`),
    Plans (**Block C** naming), Hard rules (**Block A**), Verification
    (`uv sync`, `pytest`, `ruff check`).

### Phase 4 — CuratedForest.com

1. Worktrees — [MOVE] all 9 via `git worktree move`: add-de-google-page,
   fix-bad-links, more-pages, reorg-documentation, reorg-documentation-v2,
   reorganize-designs, reorganize-files-2,
   rework-dispatch-loop-documentation, support-dev-instance →
   `.agents/worktrees/<name>`.
2. `.kilo/plans/1790181728684-label-based-features-page-split.md` —
   [MOVE+RENAME] → `.agents/plans/<first-commit-date>-docs-label-based-features-page-split.md`.
3. `.kilo` — [REPLACE] remove emptied real dir, symlink → `.agents`, track.
   `.opencode` — [FIX] broken symlink becomes valid once `.agents` exists;
   track. No `.claude`, no CLAUDE.md created.
4. `.agents/agents/{plan,code,ask,debug,review}.md` — [CREATE] per base rule;
   Hugo flavor: verification notes "This env has no `hugo` binary. Assume you
   cannot preview locally. Rely on careful reading, Netlify's build for
   verification" (verbatim from AGENTS.md golden rules); bash allowlist
   `python scripts/split_icons.py` + git read-only; code-agent edit scope
   `content/**`, `layouts/**`, `assets/**`, `static/**`, `hugo.yaml`,
   `netlify.toml`, `.agents/plans/**`, else ask.
5. `skills-lock.json` — [CREATE] `{"version": 1, "skills": {}}`.
6. `.agents/.gitignore`, `.agents/plans/.gitkeep` — [CREATE].
7. `.gitignore` — [MODIFY] add `.agents/skills/` + `.agents/worktrees/`.
8. `AGENTS.md` — [MODIFY] keep ALL domain content verbatim (golden rules,
   decision table, nav/TOC/sidebar sections, theme updates, deployment,
   diagnostics cheat sheet); remove the stale line 24 "`CLAUDE.md` — tracked
   symlink to `AGENTS.md`." if present; wrap in standard sections: Purpose,
   Repository layout (+ `.agents/` lines), Agents (five), Skills (**Block B**,
   registry empty), MCP servers (global note), Plans (**Block C**), Hard rules
   (**Block A**), Verification, References.

### Phase 5 — Home-Assistant-Label-based-Features

1. Worktrees — [MOVE] all 23 from `.kilo/worktrees/<name>` to
   `.agents/worktrees/<name>` via `git worktree move`. If any refuse
   (dirty/locked), stop and report which — no `--force` without user
   confirmation.
2. `.kilo/plans/2026-07-26-branch-comparison.md` — [MOVE] → `.agents/plans/`
   (name already conformant).
3. `.kilo` — [REPLACE] delete emptied real dir (its `agent/` copies are
   byte-identical to `.agents/agent/` — verified); `ln -s .agents .kilo`;
   track the symlink.
4. `.claude`, `CLAUDE.md` — [REMOVE] `git rm .claude CLAUDE.md` (tracked
   symlinks).
5. `.agents/agent` → `.agents/agents` — [RENAME] `git mv`; plan.md/code.md
   path fixes + Skills rule as in Phase 2.
6. `.agents/agents/{ask,debug,review}.md` — [CREATE] from templates with the
   same `homeassistant_*` read-only subset as Phase 2.
7. `.opencode` — [TRACK] (`git add`).
8. `.gitignore` — [MODIFY] remove lines `skills-lock.json`, `.kilo/`,
   `.claude/skills/`; keep `.agents/skills/`; add `.agents/worktrees/`.
9. `skills-lock.json` — now tracked (was ignored); keep its 9 entries.
10. `AGENTS.md` — [MODIFY] File Map: `.agents/agent/` → `.agents/agents/`;
    Agents section: add ask/debug/review; Skills header → **Block B**; Hard
    rules: insert **Block A** before the existing Always/Ask/Never boundaries
    (kept verbatim); MCP section: global note; Plans section: **Block C**.

### Phase 6 — ha-mcp

1. `CLAUDE.md` → `AGENTS.md` — [RENAME] `git mv CLAUDE.md AGENTS.md`. No
   CLAUDE.md left behind.
2. Skill bundle — [MOVE] `git mv .claude/skills/ha-mcp/ha-mcp-tools
   skills/ha-mcp-tools` (and gotchas, guide, patching, efficiency); remove the
   emptied real `.claude` dir. No `.claude` symlink created.
3. `.opencode` — [FIX] broken symlink becomes valid once `.agents` exists;
   track. `.kilo` — [CREATE] symlink → `.agents`; track.
4. `.agents/agents/{plan,code,ask,debug,review}.md` — [CREATE] per base rule;
   Go flavor: bash allowlist `task *`, `go *`, `golangci-lint *`, git
   read-only; code-agent edit scope `cmd/**`, `internal/**`, `configs/**`,
   `docs/**`, `skills/**`, `scripts/**`, `.agents/plans/**`, `AGENTS.md`,
   else ask; code agent must respect the repo's linter rules + test coverage
   rules (kept verbatim in AGENTS.md).
5. `.agents/.gitignore`, `.agents/plans/.gitkeep` — [CREATE].
6. `skills-lock.json` — [CREATE] `{"version": 1, "skills": {}}` (bundle is
   self-managed, not lock inventory).
7. `.gitignore` — [MODIFY] add `.agents/skills/` + `.agents/worktrees/`.
8. `AGENTS.md` — [MODIFY] restructure the 466-line content into standard
   sections keeping ALL wording verbatim (architecture, coding rules, testing
   rules, workflow preferences, Always/Never lists); `# CLAUDE.md` heading →
   `# AGENTS.md — ha-mcp`; internal self-references "CLAUDE.md" → "AGENTS.md"
   (incl. the Documentation Update Checklist item); skill table paths
   `.claude/skills/ha-mcp/<skill>/SKILL.md` → `skills/<skill>/SKILL.md` and
   "this project ships a skill bundle at `.claude/skills/ha-mcp/`" → "at
   `skills/`"; remove or mark external the gitnexus line referencing
   non-existent `.claude/skills/gitnexus/`; add Agents (five), Skills
   (**Block B**), MCP (global note), Plans (**Block C**), Hard rules
   (**Block A** + existing Always/Never kept verbatim).

### Phase 7 — pictaria-server

1. `.agents/` — [CREATE] full tree: `agents/{plan,code,ask,debug,review}.md`
   (base rule; Node flavor: bash allowlist from `package.json` scripts, git
   read-only), `plans/.gitkeep`, inner `.gitignore`.
2. `.kilo`, `.opencode` — [CREATE] symlinks → `.agents`; track both. No
   `.claude`.
3. `CLAUDE.md` — [REMOVE] `git rm CLAUDE.md` (the 11-byte `@AGENTS.md`
   import).
4. `skills-lock.json` — [CREATE] `{"version": 1, "skills": {}}`.
5. `.gitignore` — [MODIFY] add `.agents/skills/` + `.agents/worktrees/`.
6. `AGENTS.md` — [MODIFY] keep the Linear↔GitHub PR workflow verbatim as part
   of Hard rules (**Block A** first, then the existing workflow bullets:
   one focused branch per issue `pic-XX-…`, PR titles `PIC-XX:`, `Fixes` /
   `Related to` semantics, CHANGELOG duty, no-commit-to-main, validation
   proportionate to risk, naming "Pictaria Frame"); add standard sections
   (Purpose from README, layout, Agents five, Skills **Block B**, MCP global
   note, Plans **Block C**, Verification per package.json scripts).
   `prompts/` is app content — leave.

## Verification

Global (after Phase 0 follow-up at merge time):
- `readlink ~/.config/kilo/kilo.jsonc ~/.config/opencode/opencode.json` → both
  `/home/coder/SpencersLab/agent-config.jsonc`.
- `kilo debug config` lists the MCP servers; `opencode debug config` shows
  translated `mcp.servers` + permissions.

Per repo (after its phase):
- `ls -la .kilo .opencode` → both symlinks to `.agents`; `git ls-files .kilo
  .opencode skills-lock.json` shows all three tracked.
- **Absence checks (rev 2):** `ls .claude CLAUDE.md` → neither exists;
  `git ls-files | grep -E '^\.claude$|^CLAUDE\.md$'` → empty.
- `git check-ignore .agents/skills .agents/worktrees` → both match.
- `git ls-files .agents/skills .agents/worktrees` → empty.
- `kilo agent list` shows plan, code, ask, debug, review (+ 0-pipeline…7b in
  SpencersLab) with no "failed to load agent" errors; `opencode debug agents`
  lists the same five.
- `git worktree list` shows moved worktrees under `.agents/worktrees/`
  (HALbF 23, CuratedForest 9, brother-ptouch 2).
- No `skillfish.json` anywhere; no epoch-named plans (`ls .agents/plans/` →
  only `yyyy-mm-dd-*`).
- `grep -c "## Repo context locations" skills/helm-chart-creation/SKILL.md`
  → 1 (SpencersLab only).
- Spot-check verbatim fidelity: Block A's "NEVER push to `main`" bullet and
  the Skills loading rule match the standard blocks character-for-character
  (`grep -c "single most forbidden action" AGENTS.md` → 1 per repo).

## Risks & open questions

- **`git worktree move` can refuse** for dirty or locked worktrees: report the
  refusing worktree, continue with the rest; `--force` only after explicit
  user confirmation.
- **Config writes through the symlink**: tools that rewrite their global
  config will modify `agent-config.jsonc` inside the SpencersLab checkout —
  intended GitOps behavior; commit the diff like any change. Backups exist at
  `~/.config/kilo/kilo.jsonc.bak*` for rollback.
- **Symlink target during transition**: until the branch lands on main, the
  global symlinks point at the worktree path; re-point them at merge time
  (Phase 0 follow-up) before removing the worktree.
- **opencode permission translation** parses (verified), but kilo-only
  permission keys may be inert in opencode v2. Acceptable: kilo is primary;
  refine later in `agent-config.jsonc`.
- **ha-mcp gitnexus reference** points at a non-existent path; removed/marked
  external. If gitnexus skills belong there, separate follow-up.
- **Claude Code users** (if any) lose `.claude`/CLAUDE.md conveniences; Claude
  Code reads `AGENTS.md` natively, so coverage is retained (user accepted by
  dropping them).
- fabric and k8s are references only — not modified.
- Only `helm-chart-creation` gets the context-locations section in this pass
  (user request). `container-creation` and `llama-swap` could receive the same
  section later if desired — out of scope here.

---

## Addendum rev 3 (2026-09-27, post-execution)

1. **`.opencode/` is a real tracked dir, not a symlink.** Empirically verified:
   opencode does NOT pick up agents from a bare `.agents/` dir — the rev-1/rev-2
   symlink was what fed it. A real `.opencode/` with `agents -> ../.agents/agents`
   and `skills -> ../.agents/skills` symlinks restores agent/skill discovery,
   while opencode-only content (`plugin/`, `opencode.json`) stays out of the
   shared `.agents/` tree (kilo scans `{plugin,plugins}/*.{ts,js}` in its config
   dirs, so plugins in `.agents/` would leak into kilo). All 7 repos converted;
   layout bullets in every AGENTS.md + `skills/helm-chart-creation` updated.
2. **Landing happened outside this session.** A concurrent OpenChamber session
   committed the staged rev-2 work as "Update agent context files to be more
   consistent and support OpenCode/OpenChamber" on `main` in HomeAssistant,
   brother-ptouch-automation, CuratedForest.com, HALbF, ha-mcp, and
   pictaria-server (pushed to origin in HomeAssistant, brother-ptouch, HALbF,
   pictaria; unpushed in CuratedForest and ha-mcp). SpencersLab's copy remains
   uncommitted on branch `refactor-agents-to-support-opencode`. Per repo rules
   no remediation was attempted; the feature branches are now redundant.
3. Rev-3 working-tree changes (real `.opencode/` dirs + doc bullets) are staged
   in the six repos above and uncommitted in HomeAssistant's main checkout
   (owned by the concurrent session).
