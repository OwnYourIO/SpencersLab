---
name: pipeline-kickoff
description: New-ticket kickoff for the agent-* coordinator — the questions to ask the user (slug, models, run tag) and how to name the worktree/branch/session from the answers. MUST-loaded by agent-coord; never auto-selected.
targets: ["*"]
disable-model-invocation: true
metadata:
  opencode/autoinvoke: "false"
---

# Pipeline kickoff (new ticket)

Run this before resolving or creating a feature folder for a NEW ticket; skip all of it when resuming an existing folder.

## Questions (ask with the `question` tool)

1. **Project slug** — suggest 2–3 short kebab-case slugs derived from the request, each carrying your inferred `<type>` (`feat|bug|debug|dep|refactor|chore|docs`, e.g. `feat-llama-cache-ttl`); the user picks one or types their own.
2. **Model for planning** — default `openrouter/qwen/qwen3.8-2.4t-a95b`; offer alternates from the `pipeline-models` favorites map.
3. **Model for the rest** (test/dev/review) — default `openrouter/qwen/qwen3.8-27b`; offer alternates.
4. **Run tag** — compose `<provider>-<model>` with the model sanitized (`.` and `/` → `-`), then offer: the bare tag, tag + run number (count of existing runs with the same prefix, +1), tag + variant (if the chosen model uses one), or a user-provided string.

## Name the run's surfaces from the answers

- **Worktree + branch**: `opencode` tool `worktree_create` with name `<slug>-<run tag>` (flat, no slashes).
- **Session**: `session_rename` to the slug.
- **Move in**: `session_move` the session to the worktree directory so every subagent of this run works there.

## Hand off to planning

Pass slug, type, and both chosen models to `agent-plan` (feature folder becomes `.agents/plans/<yyyy>/<yyyy-mm>-<type>-<slug>/`); record the answers in `STATE.json` under `kickoff` (slug, run tag, worktree, models). The kickoff model choices override the `pipeline-models` defaults for this run.
