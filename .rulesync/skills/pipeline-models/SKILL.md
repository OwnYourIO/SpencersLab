---
name: pipeline-models
description: Model routing for the agent-* coordinator — which model each subagent role runs on, and this lab's favorited models map. MUST-loaded by agent-coord; never auto-selected.
targets: ["*"]
disable-model-invocation: true
metadata:
  opencode/autoinvoke: "false"
---

# Models for subagents

Set the model explicitly on every subagent launch (pass `model` as `providerID/modelID`), unless the user asks for something different:

| Roles | Tier | Model |
|---|---|---|
| `agent-plan`, `agent-research` | large (planning, architecture, judgment, research) | `openrouter/qwen/qwen3.8-2.4t-a95b` |
| `agent-test`, `agent-dev`, `agent-review` | code (test-writing, implementation, verification) | `openrouter/qwen/qwen3.8-27b` |

Kickoff choices (the `pipeline-kickoff` skill) override these defaults for the run.

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
| `gpu-ai` | `qwen3.8-27b-q8` | local code fallback (self-hosted, 262k ctx) |
| `gpu-ai` | `qwen3.8-27b-q8-1m` | local code fallback, long context (1M ctx) |
| `gpu-ai` | `qwen3.6-35b-a3b-q8` | local MoE fallback (262k ctx) |
| `gpu-ai` | `kat-coder-q8` | local code fallback (KAT Coder V2.5 Dev, Q8_0, 262k ctx) |
| `gpu-moe` | `kat-coder-q6` | local code fallback (KAT Coder V2.5 Dev, Q6_K, gpu-moe cluster) |
| `gpu-moe` | `qwen3.6-35b-a3b-q8` | local MoE fallback (gpu-moe cluster) |
