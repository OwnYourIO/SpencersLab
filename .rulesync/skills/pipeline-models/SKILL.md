---
name: pipeline-models
description: Model routing for the agent-* coordinator — which model each subagent role runs on, the kickoff picker's size order and local mapping, and this lab's favorited models map. MUST-loaded by agent-coord; never auto-selected.
targets: ["*"]
disable-model-invocation: true
metadata:
  opencode/autoinvoke: "false"
---

# Models for subagents

Set the model explicitly on every subagent launch (pass `model` as `providerID/modelID`), unless the user asks for something different:

| Roles | Tier | Default model |
|---|---|---|
| `agent-plan`, `agent-research` | planning (architecture, judgment, research) | `gpu-ai/qwen3.8-flash-next-radiance` |
| `agent-test`, `agent-dev-local`/`agent-dev-pr`, `agent-review` (per-chunk reviews) | code (test-writing, implementation, verification) | `gpu-ai/qwen3.8-flash-next-radiance` |
| `agent-review` — FINAL whole-plan review only | planning | the run's planning-tier model |

Provider posture: `gpu-ai` is the **default** provider — the table above is the blank-Model(s) answer, the Radiance fleet serving both tiers. `openrouter` is the explicit-choice provider (a model checked without `Local`) and the fallback when the local route is unavailable or the user asks for a hosted model; a run that falls back says so in RESULT instead of silently switching.

The final whole-plan review runs on the planning tier, not the code tier — it is the last judgment call of the run. Kickoff choices (the `pipeline-kickoff` skill) override the defaults for the run.

## Kickoff picker mapping

The kickoff's model question is one multi-select over `Qwen Large` / `Qwen Dense` / `Qwen Flash` / `Local (gpu-ai)`. `Qwen Dense` is this lab's label for the 27B dense family — a vocabulary change, never a model id: no served catalog carries a "Dense" id, so every route below keeps its id. Size order for routing (largest → smallest):

1. `qwen/qwen3.8-2.4t-a95b` (Qwen Large)
2. `qwen/qwen3.8-27b` (Qwen Dense)
3. `qwen/qwen3.8-flash` (Qwen Flash)

- One model checked → both tiers. Several checked → largest checked = planning tier, smallest checked = code tier, anything between is unused.
- `Qwen Dense` checked without `Local` → `openrouter/qwen/qwen3.8-27b` (the hosted dense route).
- Combination rule (`Qwen Flash` alone stays `openrouter/qwen/qwen3.8-flash`): `Qwen Flash` + `Local` checked together → assume Qwen Flash Next: `gpu-ai/qwen3.8-flash-next-radiance` — the served quality lane, the default since the owner ruling 2026-11-22 (chain: cf-106 OQ-14 2026-11-03 → Strata-q4 ruling 2026-11-09 → radiance, D4/D16). There is no plain-flash local route. Documented alternates, explicit request only: `gpu-ai/qwen3.8-flash-next-strata-q4` (the Strata lane) and `qwen3.8-flash-next-q3`; other flash-next quants only on explicit request.
- `Local (gpu-ai)` checked → provider `gpu-ai`: Dense → `gpu-ai/qwen3.8-27b-radiance` unless another quant is explicitly requested — the lane serves `qwen3.8-27b-mxfp4` from the dedicated q27 pod, which git renders parked at `replicas 0`, so until a manual scale-up this route answers a loud 502 (an accepted consequence of the owner ruling 2026-11-22 D20, recorded beside the route, never refiled as a bug); Large → `gpu-ai/qwen3.8-2.4t-a95b-q6` (q6 assumed, not catalog-verified — pre-existing); Flash → the combination rule above.
- Only `Local` checked, no model → `gpu-ai/qwen3.8-flash-next-radiance` for every role (the Local-only answer takes the Flash Next default; an explicit `Qwen Dense` check is what selects the dense lane).
- NO item checked at all (a blank Model(s) answer) → `gpu-ai/qwen3.8-flash-next-radiance` for both tiers — planning and code alike, the owner's "for everything" ruling 2026-11-22 (D4/D16); a card whose `Priority` lands on the class table's 10+/background row is still served by that row. openrouter stays the explicit-choice provider and the fallback when the local route is unavailable.

## Priority class table (board runs)

The single authority for the board `Priority` → serving-class mapping; `boards` and `pipeline-kickoff` cite this table, never duplicate it (the same cite-don't-restate pattern as the size order above).

| Card `Priority` | Class | Model row (this lab) | Radiance `body.priority` |
|---|---|---|---|
| `1`–`3` | urgent | `gpu-ai/qwen3.8-flash-next-radiance-urgent` | 9 |
| unset / `null`, `4`–`7` | default | `gpu-ai/qwen3.8-flash-next-radiance` | 5 |
| `8`–`9` | low | `gpu-ai/qwen3.8-flash-next-radiance-low` | 1 |
| `10`+ | background | `gpu-ai/qwen3.8-27b-q4` (llama.cpp — off vLLM, keeps KV headroom) | n/a |

Polarity is per-engine, and the value column belongs to the engine it names: radiance is higher-wins since cf-143, so the resolved row's `body.priority` rides 9/5/1 for urgent/default/low, 1:1. The 1/5/9 numbers are the polarity of the RETIRED vLLM lane (lower-wins) — never port those numbers to radiance: urgent would sit near-idle and low would take the preemption-proof top lane. The board field is a free NUMBER, so intermediate values snap to the class interval (midpoint boundaries: 1–3→9, 4–7→5, 8–9→1, 10+→10). The peer filter floor (`peers.radiance.filters.setParams "priority?" = 5`) is set-if-undefined: non-priority clients land in the default class, never outrank it, and a client-sent `priority` still wins.

The field is agent-WRITABLE within the boundary the `boards` priority bullet carries (D20): an agent may set `Priority` on the card its run claims and on cards its run creates, never as a bulk sweep — bulk values come from the owner-run `--apply` backfill (D19). Provenance never moves the mapping: this table decides the CLASS whatever wrote the value, and a stamp of the default `5` on an unset card selects the row unset already selected — a no-op for routing.

## Favorited models in this lab

Local first: the self-hosted `gpu-ai`/`gpu-moe` rows are the default provider's serving inventory; the `openrouter` rows are the explicit-choice models and the fallback when the local route is unavailable:

| Provider | Model | Usual role |
|---|---|---|
| `gpu-ai` | `qwen3.8-2.4t-a95b-q6` | local planning (kickoff `Local` option; q6 assumed, not catalog-verified — pre-existing) |
| `gpu-ai` | `qwen3.8-flash-next-strata-q4` | local fast — the documented alternate lane (explicit request only, per the combination bullet above) — 180B-class MoE served by the dedicated Strata pod through the outer llama-swap `peers` seam (UD-Q4_K_XL arena on the R9700; the first request pays a minutes-long arena pin, so cold start is expected; the `-strix` sibling is a manual/secondary fallback only, never an agent route) |
| `gpu-ai` | `qwen3.8-flash-next-radiance` | local fast-adjacent quality lane — 180B-class MoE served by the dedicated radiance pod through the outer llama-swap `peers.radiance` seam (a dedicated pod, booted once — NOT swap-on-first-request like the llama.cpp children, so no request ever pays a lazy load: per D57 an engine that isn't Ready yields the 502 peer-proxy error rather than blocking the request. The load is boot-time and minutes-class: ~66 GiB working set (113.60 pack − 47.7 GiB streamed n-gram tier); the printed figure the budget prices is 71.04 (D30(2)). 200K ctx / 8 sessions on the named R9700 pool) — the Flash+Local default route and the runner's lane since the owner ruling 2026-11-22 (D16); its `-urgent`/`-low` catalog siblings are the same served model at another priority class, not further models |
| `gpu-ai` | `qwen3.8-27b-radiance` | measured opt-in candidate — the 27B dense lane (`qwen3.8-27b-mxfp4`) served by the pod-swap release `gpu-ai-radiance-q27` through the `peers.radiance-q27` seam: git renders that pod idle at `replicas 0` (one card, one engine at a time — scale fn down FIRST, then q27 up; routing there while it rests fails with a 502 peer proxy error — the Service has no endpoints and llama-swap neither health-checks nor hides peers — loud, never silent; the code is sourced at D57). NEVER a default route and no runner tier points here: q27 joins the runner pool only after measurement ON THIS BOX (D54(4)) — the table above and the runner-model literal ride `gpu-ai/qwen3.8-flash-next-radiance` (owner ruling 2026-11-22, D16); its trio rides 8/4/0 urgent/default/low (`-urgent` 8, base 4, `-low` 0; the set-if-undefined `peers.radiance-q27` floor 4 lands non-priority clients on the base slot) under the same higher-wins polarity, strictly below fn's 9/5/1 (D56(5)) |
| `gpu-ai` | `qwen3.8-flash-next-radiance-tp1` | resting opt-in lane, never a default route — the flash pack as a second single-card release `gpu-ai-radiance-flash-tp1` (the cf-143 TP1-era recipe) through the `peers.radiance-flash-tp1` seam: git renders it at `replicas 0` (owner scale act to boot; routing there while it rests answers the same loud 502 as its siblings — no endpoints, no health-check, no hiding). No runner tier points here: the trio rides 7/3/2 urgent/default/low (`-urgent` 7, base 3, `-low` 2; `peers.radiance-flash-tp1` floor 3 = its OWN default slot, never fn's 5) under the same higher-wins polarity, strictly below the live lanes (D19 ladder, TEST_SPEC §3); coexistence with any TP2 lane is claim math, not policy — see the lane subtree |
| `gpu-ai` | `qwen3.8-27b-radiance-tp2` | resting opt-in lane, never a default route — the q27 pack as a TWO-card TP2 engine `gpu-ai-radiance-q27-tp2` (`--tp 2 --tp-wire wht6`) through the `peers.radiance-q27-tp2` seam: git renders it at `replicas 0` because its 2-card claim parks the whole pool while up (it can never co-boot with flash-TP1: 2+1 > 2 cards); routing there while it rests fails with a 502 peer proxy error (no endpoints; llama-swap neither health-checks nor hides peers — loud, never silent). Its trio rides 6/2/1 urgent/default/low (`peers.radiance-q27-tp2` floor 2 = its OWN default slot) under the same higher-wins polarity; the low rung 1 ties fn's low 1 by accepted ruling — separate peers, separate queues (D19) |
| `gpu-ai` | `qwen3.8-27b-q4` | the llama.cpp dense rung (UD-Q4_K_XL + MTP; verified served in the chart catalog and the provider catalog) — the Priority class table's 10+/background leg |
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

Retired lanes stay named, never re-listed: the three `qwen3.8-27b-vllm` rows left both tables above with the cf-143 C01 disable of that lane (`charts/vllm` — the magiccodingman vllm-radiance FORK, a different engine from cf-143's radiance). The lane is dormant by the owner's Q3 ruling and its provider rows are commented, one edit from a re-enable, so they return to the tables only when the owner re-enables it.
