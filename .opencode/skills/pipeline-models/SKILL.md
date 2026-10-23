---
name: pipeline-models
description: >-
  Model routing for the agent-* coordinator — which model each subagent role
  runs on, the kickoff picker's size order and local mapping, and this lab's
  favorited models map. MUST-loaded by agent-coord; never auto-selected.
metadata:
  opencode/autoinvoke: 'false'
disable-model-invocation: true
---
# Models for subagents

Set the model explicitly on every subagent launch (pass `model` as `providerID/modelID`), unless the user asks for something different:

| Roles | Tier | Default model |
|---|---|---|
| `agent-plan`, `agent-research` | planning (architecture, judgment, research) | `openrouter/qwen/qwen3.8-2.4t-a95b` |
| `agent-test`, `agent-dev`, `agent-review` (per-chunk reviews) | code (test-writing, implementation, verification) | `openrouter/qwen/qwen3.8-27b` |
| `agent-review` — FINAL whole-plan review only | planning | the run's planning-tier model |

The final whole-plan review runs on the planning tier, not the code tier — it is the last judgment call of the run. Kickoff choices (the `pipeline-kickoff` skill) override the defaults for the run.

## Kickoff picker mapping

The kickoff's model question is one multi-select over `Qwen Large` / `Qwen 27b` / `Qwen Flash` / `Local (gpu-ai)`. Size order for routing (largest → smallest):

1. `qwen/qwen3.8-2.4t-a95b` (Qwen Large)
2. `qwen/qwen3.8-27b` (Qwen 27b)
3. `qwen/qwen3.8-flash` (Qwen Flash)

- One model checked → both tiers. Several checked → largest checked = planning tier, smallest checked = code tier, anything between is unused.
- `Local (gpu-ai)` checked → provider `gpu-ai`, model id = the checked model's basename + `-q6` (assume q6 quantizations are served): Large → `gpu-ai/qwen3.8-2.4t-a95b-q6`, 27b → `gpu-ai/qwen3.8-27b-q6` (verified serving), Flash → `gpu-ai/qwen3.8-flash-q6`.
- Only `Local` checked, no model → `gpu-ai/qwen3.8-27b-q6` for every role.

## Favorited models in this lab

`openrouter` first; the self-hosted `gpu-ai`/`gpu-moe` rows are tool-capable local fallbacks for when openrouter is unavailable:

| Provider | Model | Usual role |
|---|---|---|
| `openrouter` | `qwen/qwen3.8-2.4t-a95b` | large/reasoning default (variant `xhigh`) |
| `openrouter` | `qwen/qwen3.8-27b` | code/fast default (variant `xhigh`) |
| `openrouter` | `openai/gpt-6-astra` | alternate large |
| `openrouter` | `qwen/qwen3.8-max-0902` | alternate large |
| `openrouter` | `qwen/qwen3.6-35b-a3b` | general MoE |
| `openrouter` | `qwen/qwen3.8-flash` | cheap/fast triage |
| `openrouter` | `deepseek/deepseek-v4.1-flash-1017` | cheap/fast triage |
| `gpu-ai` | `qwen3.8-2.4t-a95b-q6` | local planning (kickoff `Local` option; assumed q6 serving) |
| `gpu-ai` | `qwen3.8-27b-q6` | local code default (UD-Q6_K_XL, verified serving) |
| `gpu-ai` | `qwen3.8-flash-q6` | local fast (kickoff `Local` option; assumed q6 serving) |
| `gpu-ai` | `qwen3.8-27b-q8` | local code fallback (self-hosted, 262k ctx) |
| `gpu-ai` | `qwen3.8-27b-q8-1m` | local code fallback, long context (1M ctx) |
| `gpu-ai` | `qwen3.6-35b-a3b-q8` | local MoE fallback (262k ctx) |
| `gpu-ai` | `kat-coder-q8` | local code fallback (KAT Coder V2.5 Dev, Q8_0, 262k ctx) |
| `gpu-moe` | `kat-coder-q6` | local code fallback (KAT Coder V2.5 Dev, Q6_K, gpu-moe cluster) |
| `gpu-moe` | `qwen3.6-35b-a3b-q8` | local MoE fallback (gpu-moe cluster) |
