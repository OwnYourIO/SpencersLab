---
name: pipeline-kickoff
description: >-
  New-ticket kickoff for the agent-* coordinator — the questions to ask the user
  (slug, models, run tag) and how to name the worktree/branch/session from the
  answers. MUST-loaded by agent-coord; never auto-selected.
metadata:
  opencode/autoinvoke: 'false'
disable-model-invocation: true
---
# Pipeline kickoff (new ticket)

Run this before resolving or creating a feature folder for a NEW ticket; skip all of it when resuming an existing folder.

## Questions (ask with the `question` tool)

1. **Project slug** — suggest 2–3 short kebab-case slugs derived from the request, each carrying your inferred `<type>` (`feat|bug|debug|dep|refactor|chore|docs`, e.g. `feat-llama-cache-ttl`); the user picks one or types their own.
2. **Models for this run** — ONE multi-select question (`multiple: true`) with exactly these four options:
   - `Qwen Large` — `openrouter/qwen/qwen3.8-2.4t-a95b`
   - `Qwen 27b` — `openrouter/qwen/qwen3.8-27b`
   - `Qwen Flash` — `openrouter/qwen/qwen3.8-flash`
   - `Local (gpu-ai)` — run the checked models on the self-hosted `gpu-ai` provider, assume q6 quantizations

   Derive the routing with the size order and local mapping defined in the `pipeline-models` skill:
   - Exactly one model option checked → that model for BOTH tiers (planning and the other agents).
   - Several model options checked → the LARGEST checked model is the planning tier (`agent-plan`, `agent-research`, and the final whole-plan review); the SMALLEST checked model is the code tier (`agent-test`, `agent-dev`, chunk `agent-review`). Options in between are unused.
   - Only `Local (gpu-ai)` checked, no model → default `gpu-ai/qwen3.8-27b-q6` for every role.
   - `Local` unchecked → provider `openrouter` for all chosen models; `Local` checked → provider `gpu-ai` with the `-q6` model ids from `pipeline-models`.
3. **Run tag** — compose `<provider>-<model>` from the planning-tier model with the model sanitized (`.` and `/` → `-`), then offer: the bare tag, tag + run number (count of existing runs with the same prefix, +1), tag + variant (if the chosen model uses one), or a user-provided string.

## Name the run's surfaces from the answers

- **Worktree + branch**: `opencode` tool `worktree_create` with name `<slug>-<run tag>` (flat, no slashes).
- **Session**: `session_rename` to the slug. The call returns YOUR OWN sessionID — keep it: the planner records it under `coord_session` in `STATE.json`, and `agent-fuser` uses it to hand fusion plans back to this session.
- **Move in**: `session_move` the session to the worktree directory so every subagent of this run works there.

## Hand off to planning

Pass slug, type, both tier models (+ `local` flag), run tag, worktree name, and your own sessionID to `agent-plan` (feature folder becomes `.agents/plans/<yyyy>/<yyyy-mm>-<type>-<slug>/`); the planner records them in `STATE.json` under `kickoff` (slug, run tag, worktree, `models: {plan, code}`, `local`) and `coord_session` when it creates the folder. The kickoff model choices override the `pipeline-models` defaults for this run.
