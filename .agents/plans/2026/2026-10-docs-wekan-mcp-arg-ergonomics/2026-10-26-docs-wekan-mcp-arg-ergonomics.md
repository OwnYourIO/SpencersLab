# PLAN: wekan-api skill — document wekan-mcp argument ergonomics (verified signatures)

feature: 2026/2026-10-docs-wekan-mcp-arg-ergonomics
origin: card #70 run FRICTION item 3 — "wekan-mcp argument ergonomics cost
round-trips: `board_id` required on nearly every call, checked-state field is
`finished` (not `checked`), `move_card` needs `from_list_id`/`to_list_id` and
REJECTS `swimlane_id`, comment body arg is `comment` · open (fix: document in
the wekan-api skill's MCP section)"
(2026/2026-10-cf-70-debug-wekan-enter-submit/FRICTION.md — read-only source,
never touched by this ticket; re-stating it as `fixed` is that folder's coord's job.)

## Goal
Make the wekan-mcp call surface discoverable without trial-and-error: encode the
argument signatures live-verified 2026-10-26 against wekan-mcp 4.1.3 (dev-cluster
`boards` endpoint at `mcp.dev.scifi.farm/boards/mcp`) into the wekan-api skill —
a short "call shape" rules block in `SKILL.md` (loaded with the skill, where the
friction bites) and a full tool→args→gotcha table in
`references/wekan-mcp-ops.md` — plus pin the docs against silent drift from the
server source with a repo-validation suite. Second concern (C02, independent):
add `wekan-api` to AGENTS.md's self-written-skills list so agents stop having to
re-derive where this skill lives.

## Diagnosis (verified 2026-10-26 by agent-plan — this is why edits are sanctioned here)
- **Sanctioned edit surface = `skills/wekan-api/` directly.** The skill loads from
  `skills/wekan-api/SKILL.md` (self-written area per AGENTS.md "Where things live").
  Not in `.rulesync/skills/` → rulesync generates nothing for it, no regenerate step.
  Not in `.agents/skills/` and absent from `skills-lock.json` → not vendored /
  registry-managed, so the SHA-pinned re-fetch path does NOT apply. Loaded directly
  via `.opencode/opencode.jsonc` `"skills": [ …, "./.agents/skills", "skills/" ]`.
- **Ground-truth authority = `containers/wekan-mcp/wekan_mcp/server.py`** (in-repo,
  `@mcp.tool` function signatures). It independently confirms every launch-brief
  fact: `list_checklists(board_id, card_id)`; `get_checklist` item field is
  `finished` (mapped from REST `isFinished`); `toggle_checklist_item(..., done)`
  input/response field is `done`; `add_comment(board_id, card_id, comment)`;
  `move_card(board_id, from_list_id, card_id, to_list_id, to_swimlane_id=None)` —
  bare `swimlane_id` is not a parameter (hence rejected), cross-swimlane moves use
  `to_swimlane_id`; `set_card_custom_field(board_id, card_id, custom_field_id, value)`.
- **Overlap owner checked:** sibling ticket `2026/2026-10-bug-board-coord-dev-boards-allow`
  owns the `dev-boards` MCP-permission literals (`.rulesync/subagents/`,
  `.rulesync/skills/boards/`, agents-sync permissions.md). Zero file overlap here;
  cross-reference only. The MCP-over-HTTP fallback recipe is ALREADY documented
  ("Verifying a server directly" in wekan-mcp-ops.md) — not re-planned.

## Out of scope
- Any change to `containers/wekan-mcp/` server code, its README, or the deployed image.
- Anything in `.agents/plans/2026/2026-10-cf-70-debug-wekan-enter-submit/` or
  `2026-10-bug-board-coord-dev-boards-allow/` (read-only), incl. re-status of their
  friction items.
- Agent permission literals / rulesync subagent surfaces (sibling ticket's scope).
- `.rulesync/skills/boards/SKILL.md` call-shape pointer (deferred — see Open questions).
- Machine-local config (`~/.config/opencode/`); merge/push/PR of any kind.

## Commands
- test: `bash tests/wekan-mcp/arg-surface.sh` (new suite, agent-test writes before dev)
- skill-load: `bash tests/wekan-mcp/arg-surface.sh t1` — frontmatter intact +
  reference files present + pointers resolve (structural load-readiness; live
  `/wekan-api` load by review as smoke)
- regen (C02 only): `rulesync generate && rulesync generate` — second run must be
  a no-op (idempotence), then `rulesync generate --check` passes
- surface: `git diff --name-only $(git merge-base main HEAD)..HEAD` ⊆ the chunk's
  declared file list (C01 never lists a `.opencode/` or `.rulesync/` path;
  C02's only generated output is `AGENTS.md`)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | wekan-api MCP call-shape docs + pinning suite | S | 1 | [] | — |
| C02 | AGENTS.md self-written-skills list current (rulesync) | S | 1 | [] | independent of C01 — different files, different machinery (direct skill edit vs rulesync regen); no data/interface dependency |

## Wave order
1. C01, C02 (independent; run in id order)

## Risks / assumptions
- Line numbers in `server.py` drift → docs cite **function names** as source
  anchors, never line numbers.
- The 2026-10-26 evidence is live-probe + source cross-check on the dev `boards`
  endpoint; gpu tiers run the same image family but are not re-probed. Docs stamp
  `verified 2026-10-26 · wekan-mcp 4.1.3 · dev boards endpoint` and mark the two
  source-only claims (`to_swimlane_id` acceptance, tool count) distinctly.
- `rulesync generate` in C02 regenerates all outputs; the surface check catches any
  unexpected rewrite (agents-sync lesson "verify syncs landed").
