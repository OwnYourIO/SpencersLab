# Permission model

Generated agents carry `permissions:` blocks in their frontmatter (authored in `.rulesync/subagents/`, emitted by `rulesync generate`). Rules are evaluated **in order, last match wins**, so broad rules come early and specific overrides after them. Rule shape: `{ action: "<tool>", resource: "<glob>", effect: allow|deny|ask }`.

- Actions are tool names. MCP tools are permissioned as `"<server>_<tool>"` with unsupported characters (like `-`) becoming `_` — so the pattern `readonly*` matches server `readonly-gpu-kubernetes`'s tools, and `admin*` matches both `admin-*` and `admin_*` spellings.
- Resources are path globs for file tools (`edit`, `read`) and command globs for `shell` (e.g. `git status *`). `**` crosses directory boundaries.
- `subagent` resources are target agent ids, matched **whole-value** — a rule without `*` matches exactly one id. Verified live on OpenCode v2.0.24 (2026-10-14) back when this repo still shipped `-bmad` overlay variants: a coordinator was denied the other variant's agents and allowed only its own four, and the `subagent` tool's "Available subagents" list shown to each coord contained exactly its 4 permitted same-variant agents. The naming scheme stays relevant for any overlay added later: variant names are prefix-free (overlays lead), so `agent-dev` is not a prefix of `agent-dev-bmad` — safe even if a build, saved approval, or hand-added wildcard rule ever behaves prefix-like.
- `ask` pauses for the user; unattended subagents treat it as effectively blocked, so allow-lists decide what runs hands-free.

## Role matrix (who may write what)

| role | edit | subagent | shell | MCP |
|---|---|---|---|---|
| coord | ONLY `.agents/plans/**/STATE.json`, `…/DECISIONS.md`, `…/FRICTION.md` (starts from `* * deny`) | plan/research/test/dev/review of same variant | none | none |
| plan | ONLY `.agents/plans/**` | none | read-only git | `admin*` deny; `readonly*`/`global*`/`dev*` allow |
| research | ONLY `.agents/plans/**` (its `RESEARCH.md`, at the exact feature-folder path from its launch message) | none | read-only git | as plan; plus `webfetch`/`websearch` allowed |
| test | ONLY chart/container `tests/` folders + the context allows below (starts from `edit * deny`) | none | git reads + `helm lint/template/unittest` | as plan |
| dev | everything EXCEPT chart/container `tests/` folders (`charts/**/tests/**`, `containers/**/tests/**`) and `.agents/plans/**`, plus the context-file rules below | none | git reads + `helm lint/template` | as plan |
| review | ONLY `.agents/plans/**` (never edits code or tests — a faulty test escalates to coord, who asks the user and routes the fix to the test session) | none | git reads + `helm lint/template` | as plan |
| fuser | ONLY `.agents/plans/**` — the ticket folder of the CONFIRMED base worktree, which it enters via `session_move` before writing (`FUSION-REPORT.md` + `<plan-file>-fusion.md`) | none | read-only git (`status/log/diff/show/branch/merge-base/worktree list`) + `helm lint/template` + `opencode api get /api/session*` and `opencode api post /api/session/*` (session lookup + the one hand-back prompt); else ask | as plan |

All roles allow `question` everywhere. `skill` is allowed everywhere EXCEPT for coord, which denies the other roles' contract skills (`pipeline-role-{plan,research,test,dev,review}`, after its broad `skill * allow` — it coordinates and must not absorb their contracts); coord still loads its own workflow skills and the intake's 3 request-relevant task skills. MCP servers named `readonly*`/`global*`/`dev*` are allowed and `admin*` denied for plan/research/test/dev/review/fuser (mutations need a user step), while coord denies everything (it orchestrates, never touches the cluster).

### Context-file rules (dev)

Repo/agent context files get a per-file policy for the roles that edit the repo — dev (broad `edit * allow` with the trailing overrides below) and test (starts from `edit * deny`, so it gets only the two context **allow** rows plus the machinery asks):

| effect | resources | why |
|---|---|---|
| **allow** | `skills/**`, `.rulesync/rules/**`, `.rulesync/skills/**` | a chunk may legitimately update self-written skills or the repo-context rules (which generate `AGENTS.md`) — dev edits and reports it under `deviations` so the coordinator sees it |
| **ask** | `.rulesync/**`, `.opencode/opencode.jsonc`, `skills-lock.json`, `rulesync.jsonc` | agent machinery (subagent/command sources, MCP fleet config, registry lock, generator config): explicit user approval per edit (unattended subagents treat `ask` as blocked). Order matters: the broad `.rulesync/**` ask comes BEFORE the two `.rulesync/{rules,skills}/**` allows, so those allows win for context sources while everything else under `.rulesync/` still asks |
| **deny** | `AGENTS.md`, `.opencode/agents/**`, `.opencode/commands/**`, `.opencode/skills/**` | generated surfaces — `rulesync generate` owns them; a hand-edit is silently overwritten on the next generate, so the change belongs in the `.rulesync/` source instead |
| **deny** | `.agents/**` (and `.kilo/**`, its symlink) | plans are coord/plan-owned; third-party skills in `.agents/skills/` are registry-managed — never hand-edited (self-written, in-repo skills live in top-level `skills/`) |

(`.kilo` is a symlink to `.agents`; both spellings are listed because matchers differ on symlink resolution. Order matters: these denies come last, after `edit * allow`, because last match wins.)

### MCP allow-lists

This repo's servers follow the `<priv>-<cluster>-<service>` naming (`readonly-*` / `admin-*` / `global-*`), so the agents use the prefix rules `admin* deny, readonly* allow, global* allow` — subagents never mutate cluster state; mutations are a user step. Tier-less servers match none of those prefixes, and unlisted servers fall through to `ask` (= blocked in unattended runs), so the dev-cluster utility fleet (`dev-playwright`, `dev-renovate`, `dev-searxng`, `dev-boards`) is granted by a `dev*` allow added AFTER the `admin*` deny (2026-10-24, ticket 2026-10-feat-dev-mcp-fleet): under last-match-wins the deny stays the effective last match for `admin_*` tool names — `dev*` matches only `dev_*` names — and no tier-less `dev-*` name may shadow an `admin`-capable server; if the fleet ever gains one, put a specific deny after the `dev*` allow. A repo whose servers lack that naming needs explicit per-server allow-lists instead, with anything that can mutate systems the repo shouldn't touch denied.

## Audit checklist (run after files move or servers are renamed)

1. Extract every resource: `grep -hE 'resource: "?[^ "]' .rulesync/subagents/agent-*.md | sort | uniq -c`.
2. For each path-shaped resource, confirm the target exists in the current layout (`ls`/`git ls-files` globs). Plans live per-ticket now: coord needs `.agents/plans/**/STATE.json` style, NOT root `.agents/plans/STATE.json` — with coord's leading `* * deny`, a stale root path silently locks coord out of its own state files.
3. For each MCP prefix rule, list live servers (`.opencode/opencode.jsonc` `mcp` keys) and confirm the intended servers match a rule; anything unintended should hit deny or `ask`.
4. Confirm the dev context-file denies are present and ordered AFTER `edit * allow` (last match wins), and the `.rulesync/**` ask precedes the two `.rulesync/{rules,skills}/**` allows.
5. Confirm kick-off commands' state lookup matches the layout: `find .agents/plans -mindepth 2 -maxdepth 3 -name STATE.json` (month/ticket levels).

## Drift incidents (history — keep as regression tests for audits)

- **2026-10-13 — coord root-pinned paths.** After plans moved to per-ticket folders, coord still had `edit .agents/plans/STATE.json` / `DECISIONS.md` (root). Under its leading deny-all, coord would have been unable to write any tracking file. Fixed with `.agents/plans/**/<file>` (+ the friction file).
- **2026-10-21 — validate merged into review; friction file uppercased.** The standalone validate stage was removed (it rarely caught anything dev's own run hadn't); review now runs the validations first, then reviews. Same day `friction.md` became `FRICTION.md` and `agent-research` joined coord's launch roster — audit any saved permission snippet against the matrix above, and remember path globs are case-sensitive.
- **2026-10-21 (same day, user corrections) — review never edits tests; dedicated test writer.** Two brief states lived only in staging and are reverted here: review holding validate's `tests/` grants (vetoed — a faulty test escalates, coord asks the user, the fix routes to the authoring session), and dev authoring validations (replaced by a dedicated writer). Final state: `agent-test` writes every chunk's tests in ONE session after planning and before dev (its sessionID is `STATE.json` `test_session`); dev is tests-denied again; review is plans-only. If you find review or dev with `tests/` grants anywhere, that is a reverted state — remove them.
- **2026-10-14 — dev over-broad edit.** dev was `edit * allow` with only `tests/` + plans denied, so dev subagents could edit `AGENTS.md`, agent definitions, skills, and the generator — observed as subagents updating context files. Fixed with the per-file allow/ask/deny table above (dev may update repo-context sources when a chunk needs it; agent machinery needs explicit approval; plans, generated surfaces, and registry-managed skills stay closed). The same incident family applies whenever a surface BECOMES generated (as `AGENTS.md`/agents did under rulesync): move it from allow to deny and point editors at the source.
- **2026-10-23 — coord skill firewall; kickoff picker collapsed; agent-fuser added.** Coord was observed drifting toward planning/investigating itself — it now gets explicit `skill` denies on the five other roles' `pipeline-role-*` contract skills (after the broad `skill * allow`; last match wins), a 3-skill intake for judging the request, and end-of-session friction follow-up as one multi-select question. The kickoff's two model questions collapsed into ONE multi-select (Qwen Large / Qwen 27b / Qwen Flash / Local-gpu-ai; size order Large > 27b > Flash; largest checked = planning tier incl. the final review, smallest = code tier; Local maps to `gpu-ai/<model>-q6`, assume q6; Local alone = `gpu-ai/qwen3.8-27b-q6` everywhere). `agent-research` must write `RESEARCH.md` only at the feature-folder path in its launch message (else `NEEDS_INFO`). New `agent-fuser`: planner-tier permissions + git branch reads + `opencode` (worktree_list/session_move) + `opencode api` session lookup/prompt; it compares parallel runs of a ticket and writes `FUSION-REPORT.md` + `<plan-file>-fusion.md` into the confirmed base worktree's ticket folder (fusion plans are the sanctioned second plan file), then hands back via a prompt to the base session (`coord_session` in `STATE.json`, recorded by coord from its `session_rename` return).
