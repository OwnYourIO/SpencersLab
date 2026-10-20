# Permission model

Generated agents carry `permissions:` blocks in their frontmatter (authored in `.rulesync/subagents/`, emitted by `rulesync generate`). Rules are evaluated **in order, last match wins**, so broad rules come early and specific overrides after them. Rule shape: `{ action: "<tool>", resource: "<glob>", effect: allow|deny|ask }`.

- Actions are tool names. MCP tools are permissioned as `"<server>_<tool>"` with unsupported characters (like `-`) becoming `_` — so the pattern `readonly*` matches server `readonly-gpu-kubernetes`'s tools, and `admin*` matches both `admin-*` and `admin_*` spellings.
- Resources are path globs for file tools (`edit`, `read`) and command globs for `shell` (e.g. `git status *`). `**` crosses directory boundaries.
- `subagent` resources are target agent ids, matched **whole-value** — a rule without `*` matches exactly one id. Verified live on OpenCode v2.0.24 (2026-10-14) back when this repo still shipped `-bmad` overlay variants: a coordinator was denied the other variant's agents and allowed only its own four, and the `subagent` tool's "Available subagents" list shown to each coord contained exactly its 4 permitted same-variant agents. The naming scheme stays relevant for any overlay added later: variant names are prefix-free (overlays lead), so `agent-dev` is not a prefix of `agent-dev-bmad` — safe even if a build, saved approval, or hand-added wildcard rule ever behaves prefix-like.
- `ask` pauses for the user; unattended subagents treat it as effectively blocked, so allow-lists decide what runs hands-free.

## Role matrix (who may write what)

| role | edit | subagent | shell | MCP |
|---|---|---|---|---|
| coord | ONLY `.agents/plans/**/STATE.json`, `…/DECISIONS.md`, `…/friction.md` (starts from `* * deny`) | plan/dev/validate/review of same variant | none | none |
| plan | ONLY `.agents/plans/**` | none | read-only git | `admin*` deny; `readonly*`/`global*` allow |
| dev | everything EXCEPT chart/container `tests/` folders (`charts/**/tests/**`, `containers/**/tests/**`) and `.agents/plans/**`, plus the context-file rules below | none | git reads + `helm lint/template` | as plan |
| validate | ONLY chart/container `tests/` folders | none | git reads + `helm lint/template` | as plan |
| review | ONLY `.agents/plans/**` | none | read-only git | as plan |

All roles allow `question` and `skill` everywhere; MCP servers named `readonly*`/`global*` are allowed and `admin*` denied for plan/dev/validate/review (mutations need a user step), while cord denies everything (it orchestrates, never touches the cluster).

### Context-file rules (dev)

Repo/agent context files get a per-file policy for the dev role — the other roles start from `edit * deny`, so this concerns dev only (its single `edit * allow` makes the trailing overrides matter):

| effect | resources | why |
|---|---|---|
| **allow** | `skills/**`, `.rulesync/rules/**`, `.rulesync/skills/**` | a chunk may legitimately update self-written skills or the repo-context rules (which generate `AGENTS.md`) — dev edits and reports it under `deviations` so the coordinator sees it |
| **ask** | `.rulesync/**`, `.opencode/opencode.jsonc`, `skills-lock.json`, `rulesync.jsonc` | agent machinery (subagent/command sources, MCP fleet config, registry lock, generator config): explicit user approval per edit (unattended subagents treat `ask` as blocked). Order matters: the broad `.rulesync/**` ask comes BEFORE the two `.rulesync/{rules,skills}/**` allows, so those allows win for context sources while everything else under `.rulesync/` still asks |
| **deny** | `AGENTS.md`, `.opencode/agents/**`, `.opencode/commands/**`, `.opencode/skills/**` | generated surfaces — `rulesync generate` owns them; a hand-edit is silently overwritten on the next generate, so the change belongs in the `.rulesync/` source instead |
| **deny** | `.agents/**` (and `.kilo/**`, its symlink) | plans are cord/plan-owned; third-party skills in `.agents/skills/` are registry-managed — never hand-edited (self-written, in-repo skills live in top-level `skills/`) |

(`.kilo` is a symlink to `.agents`; both spellings are listed because matchers differ on symlink resolution. Order matters: these denies come last, after `edit * allow`, because last match wins.)

### MCP allow-lists

This repo's servers follow the `<priv>-<cluster>-<service>` naming (`readonly-*` / `admin-*` / `global-*`), so the agents use the prefix rules `admin* deny, readonly* allow, global* allow` — subagents never mutate cluster state; mutations are a user step. A repo whose servers lack that naming needs explicit per-server allow-lists instead, with anything that can mutate systems the repo shouldn't touch denied, and unlisted servers falling through to `ask` (conservative for unattended runs).

## Audit checklist (run after files move or servers are renamed)

1. Extract every resource: `grep -hE 'resource: "?[^ "]' .rulesync/subagents/agent-*.md | sort | uniq -c`.
2. For each path-shaped resource, confirm the target exists in the current layout (`ls`/`git ls-files` globs). Plans live per-ticket now: cord needs `.agents/plans/**/STATE.json` style, NOT root `.agents/plans/STATE.json` — with cord's leading `* * deny`, a stale root path silently locks cord out of its own state files.
3. For each MCP prefix rule, list live servers (`.opencode/opencode.jsonc` `mcp` keys) and confirm the intended servers match a rule; anything unintended should hit deny or `ask`.
4. Confirm the dev context-file denies are present and ordered AFTER `edit * allow` (last match wins), and the `.rulesync/**` ask precedes the two `.rulesync/{rules,skills}/**` allows.
5. Confirm kick-off commands' state lookup matches the layout: `find .agents/plans -mindepth 2 -maxdepth 3 -name STATE.json` (month/ticket levels).

## Drift incidents (history — keep as regression tests for audits)

- **2026-10-13 — coord root-pinned paths.** After plans moved to per-ticket folders, coord still had `edit .agents/plans/STATE.json` / `DECISIONS.md` (root). Under its leading deny-all, coord would have been unable to write any tracking file. Fixed with `.agents/plans/**/<file>` (+ `friction.md`).
- **2026-10-14 — dev over-broad edit.** dev was `edit * allow` with only `tests/` + plans denied, so dev subagents could edit `AGENTS.md`, agent definitions, skills, and the generator — observed as subagents updating context files. Fixed with the per-file allow/ask/deny table above (dev may update repo-context sources when a chunk needs it; agent machinery needs explicit approval; plans, generated surfaces, and registry-managed skills stay closed). The same incident family applies whenever a surface BECOMES generated (as `AGENTS.md`/agents did under rulesync): move it from allow to deny and point editors at the source.
