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
| `agent-plan`, `agent-research` | planning (architecture, judgment, research) | `gpu-ai/qwen3.8-27b-q4` |
| `agent-test`, `agent-dev-local`/`agent-dev-pr`, `agent-review` (per-chunk reviews) | code (test-writing, implementation, verification) | `gpu-ai/qwen3.8-27b-q4` |
| `agent-review` — FINAL whole-plan review only | planning | the run's planning-tier model |

Provider posture: `gpu-ai` is the **default** provider — the table above is the blank-Model(s) answer and it is the local dense route for both tiers. `openrouter` is the explicit-choice provider (a model checked without `Local`) and the fallback when the local route is unavailable or the user asks for a hosted model; a run that falls back says so in RESULT instead of silently switching.

The final whole-plan review runs on the planning tier, not the code tier — it is the last judgment call of the run. Kickoff choices (the `pipeline-kickoff` skill) override the defaults for the run.

## Kickoff picker mapping

The kickoff's model question is one multi-select over `Qwen Large` / `Qwen Dense` / `Qwen Flash` / `Local (gpu-ai)`. `Qwen Dense` is this lab's label for the 27B dense family — a vocabulary change, never a model id: no served catalog carries a "Dense" id, so every route below keeps its id. Size order for routing (largest → smallest):

1. `qwen/qwen3.8-2.4t-a95b` (Qwen Large)
2. `qwen/qwen3.8-27b` (Qwen Dense)
3. `qwen/qwen3.8-flash` (Qwen Flash)

- One model checked → both tiers. Several checked → largest checked = planning tier, smallest checked = code tier, anything between is unused.
- `Qwen Dense` checked without `Local` → `openrouter/qwen/qwen3.8-27b` (the hosted dense route).
- Combination rule (`Qwen Flash` alone stays `openrouter/qwen/qwen3.8-flash`): `Qwen Flash` + `Local` checked together → assume Qwen Flash Next: `gpu-ai/qwen3.8-flash-next-strata-q4` (Strata default, q4 quant per the owner ruling 2026-11-09; `qwen3.8-flash-next-q3` remains a documented alternate — other flash-next quants only on explicit request). There is no plain-flash local route.
- `Local (gpu-ai)` checked → provider `gpu-ai`: Dense → `gpu-ai/qwen3.8-27b-q4` unless another quant is explicitly requested (q4 verified served in both the llama-swap chart catalog and the provider catalog); Large → `gpu-ai/qwen3.8-2.4t-a95b-q6` (q6 assumed, not catalog-verified — pre-existing); Flash → the combination rule above.
- Only `Local` checked, no model → `gpu-ai/qwen3.8-27b-q4` for every role (the Local-only default follows the Dense local default).
- NO item checked at all (a blank Model(s) answer) → `gpu-ai/qwen3.8-27b-q4` for both tiers — planning and code alike. The local dense route is the standard default; openrouter is what an explicit check selects, or the fallback when the local route is unavailable.

## Priority class table (board runs)

The single authority for the board `Priority` → serving-class mapping; `boards` and `pipeline-kickoff` cite this table, never duplicate it (the same cite-don't-restate pattern as the size order above).

| Card `Priority` | Class | Model row (this lab) | vLLM `body.priority` |
|---|---|---|---|
| `1`–`3` | urgent | `gpu-ai/qwen3.8-27b-vllm-urgent` | 1 |
| unset / `null`, `4`–`7` | default | `gpu-ai/qwen3.8-27b-vllm` | 5 |
| `8`–`9` | low | `gpu-ai/qwen3.8-27b-vllm-low` | 9 |
| `10`+ | background | `gpu-ai/qwen3.8-27b-q4` (llama.cpp — off vLLM, keeps KV headroom) | n/a |

Polarity is lower = more urgent (vLLM's own convention); the discrete values 1/5/9 ride the resolved row's `body.priority` 1:1. The board field is a free NUMBER, so intermediate values snap to the class interval (midpoint boundaries: 1–3→1, 4–7→5, 8–9→9, 10+→10). The peer filter floor (`peers.vllm.filters.setParams "priority?" = 5`) is set-if-undefined: non-priority clients land in the default class, never outrank it, and a client-sent `priority` still wins.

## Favorited models in this lab

Local first: the self-hosted `gpu-ai`/`gpu-moe` rows are the default provider's serving inventory; the `openrouter` rows are the explicit-choice models and the fallback when the local route is unavailable:

| Provider | Model | Usual role |
|---|---|---|
| `gpu-ai` | `qwen3.8-2.4t-a95b-q6` | local planning (kickoff `Local` option; q6 assumed, not catalog-verified — pre-existing) |
| `gpu-ai` | `qwen3.8-flash-next-strata-q4` | local fast for the Flash+Local combo — 180B-class MoE served by the dedicated Strata pod through the outer llama-swap `peers` seam (UD-Q4_K_XL arena on the R9700; the first request pays a minutes-long arena pin, so cold start is expected; the `-strix` sibling is a manual/secondary fallback only, never an agent route) |
| `gpu-ai` | `qwen3.8-27b-q4` | local code default (UD-Q4_K_XL + MTP; verified served in the chart catalog and the provider catalog) — also the Priority class table's background leg |
| `gpu-ai` | `qwen3.8-27b-vllm` | local vLLM 27B default class (board `Priority` unset/`null`/`4`–`7`; `body.priority` 5, served through the llama-swap `peers.vllm` hop) |
| `gpu-ai` | `qwen3.8-27b-vllm-urgent` | local vLLM 27B urgent class (board `Priority` 1–3; `body.priority` 1) |
| `gpu-ai` | `qwen3.8-27b-vllm-low` | local vLLM 27B low class (board `Priority` 8–9; `body.priority` 9) |
| `gpu-ai` | `qwen3.8-27b-q6` | local verified alternate quant (UD-Q6_K_XL + MTP — only on explicit request) |
| `gpu-ai` | `qwen3.8-27b-q8` | local code fallback (self-hosted, 262k ctx) |
| `gpu-ai` | `qwen3.8-27b-q8-1m` | local code fallback, long context (1M ctx) |
| `gpu-ai` | `qwen3.6-35b-a3b-q8` | local MoE fallback (262k ctx) |
| `gpu-moe` | `qwen3.6-35b-a3b-q8` | local MoE fallback (gpu-moe cluster) |
| `openrouter` | `qwen/qwen3.8-2.4t-a95b` | large/reasoning default (variant `xhigh`) |
| `openrouter` | `qwen/qwen3.8-27b` | code/fast default (variant `xhigh`) |
| `openrouter` | `openai/gpt-6-astra` | alternate large |
| `openrouter` | `qwen/qwen3.8-max-0902` | alternate large |
| `openrouter` | `qwen/qwen3.6-35b-a3b` | general MoE |
| `openrouter` | `qwen/qwen3.8-flash` | cheap/fast triage |
| `openrouter` | `deepseek/deepseek-v4.1-flash-1017` | cheap/fast triage |
