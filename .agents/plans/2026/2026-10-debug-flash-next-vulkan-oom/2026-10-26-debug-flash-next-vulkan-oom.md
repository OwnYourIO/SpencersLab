# PLAN: gpu-ai llama-server crashes at load of Qwen3.8-Flash-Next GGUF (Vulkan device-lost)
feature: 2026/2026-10-debug-flash-next-vulkan-oom
run-tag: openrouter-qwen3-8-flash

## Goal
Make `qwen3.8-flash-next-q3` (`unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q3_K_XL`, 83.8 GiB) load and serve on gpu-ai (Framework Desktop A6, Ryzen AI MAX+ 395 / gfx1151, 128 GiB unified memory), or land an evidenced "cannot run today" decision with a clean fail-fast. llama-server aborts ~21 s into load with `radv/amdgpu: Not enough memory for command submission` → `ggml_vulkan: device lost on Vulkan0` → `vk::DeviceLostError`.

## Out of scope
- The 8 GiB dGPU `gpu` box (its carve-out capacity math is solved in the 2026-10-11 debug plan; flash-next rungs echo there).
- Host/kernel changes themselves (openSUSE node cmdline/params are user-owned; the plan may record them as a precondition).
- General MoE throughput tuning, unrelated roster changes, the llama-swap v265-detector oddity (noted in C01; separate chore if real).

## User-directed flow (binding)
Initial plan (this file) → **agent-research** (open_questions below) → follow-up planning pass folds `RESEARCH.md` into this plan of record and rewrites research-gated C03 before any dev starts. Chunks C01/C02 are plan-independent; C03/C04 are NOT approved for execution until research lands.

## Grounded facts (verified 2026-10-26)
- Crash is the repo's **known signature**: same kernel lines preceded the 2026-10-18/19 gpu-ai node freezes (`.agents/plans/2026-10-20-debug-gpu-gpuai-dev-offline-investigation.md`) and the 2026-10-11 capacity OOM on the gpu box (`2026-10-11-debug-gpu-moe-qwen36-35b-q8-vram-oom.md`, which also shows the qwen36-35b Q8 loading *fine* on gpu-ai with experts on CPU).
- flash-next-q3 live cmd (chart catalog family `qwen3.8-flash-next` + gpu-ai macros): `-t 10` `${moe}` = `-ngl 99 -ot "\.ffn_.*_exps\.=CPU" --load-mode none`, `--ctx-size 262144 -b 2048 -ub 2048`, `--flash-attn on --cache-type-k q8_0 --cache-type-v q8_0`, q38-sampling/think, MTP draft `-hfd ...:mtp-Qwen3.8-Flash-Next-Q8_0` (3.9 GiB) + `--spec-type draft-mtp`. Solo matrix set, not preloaded, q5/q6 in no set (DECISIONS 2026-10-22).
- Node `ai-gpu`: 32 CPU, ~125 GiB allocatable (136.7 GB physical), **~2 GiB swap**, kernel `7.3.0-1-default`, openSUSE Tumbleweed, k3s v1.36.5; `amd.com/gpu: 1` via amd-gpu device plugin 0.22.0; pod on `ghcr.io/mostlygeek/llama-swap:unified-vulkan-266` (llama.cpp b11810, flags audited 2026-10-25).
- Live `GET llama.gpu-ai.spencerslab.com/api/hardware` (2026-10-26T03:29:38Z): gfx1151 accelerator reported `memory.kind=dedicated, capacity_bytes=536870912` (**512 MiB**) — plausible root of a GTT/BAR aperture limit under RADV. Unverified interpretation; C01 pins the real heap facts.
- On unified memory, `--load-mode none` host weights + `-ngl 99` device buffers draw from the **same** 127 GiB — device "VRAM" and host RAM are not independent budgets (double-count hypothesis, research Q1/Q4).
- `resolve_fused_ops: fused top-k mask not supported, set to disabled` (arch `qwen4exp`, 512 experts/top-10) is a warning 2 s *before* the crash — suspected red herring for the abort, but its support status is research Q2.

## Commands (validation — this repo has no unit suite except the chart's pytest contract)
- test: `pytest charts/llama-swap/tests -v` (chart config contract; goldens/disabled-stubs are agent-test-owned — see TEST_SPEC.md)
- lint: `helm dependency update charts/llama-swap && helm lint charts/llama-swap`
- render: `helm template llama-swap charts/llama-swap --set domain=spencerslab.com --set clusterName=gpu-ai`
- umbrellas: `helm lint services/gpu-ai/prod && helm template gpu-ai services/gpu-ai/prod --set domain=spencerslab.com --set clusterName=gpu-ai >/dev/null` (same for `services/gpu/prod`)
- config parity (extract-and-render per TEST_SPEC §1): python3 yaml extract of `services/gpu-ai/prod/values.yaml` `llama-swap:` subtree → `helm template ... -s templates/configmap-llama-swap.yaml` → inspect `models.qwen3.8-flash-next-*`
- trio grep (only if a new container is added): chart entry + ApplicationSet values entry + proxy values entry
- cluster verify (readonly MCP only): `readonly-ai-gpu-kubernetes` pods/events/node; `readonly-global-grafana` Loki for node journal + upstream streams; `GET /api/hardware`, `GET /running`, `GET /logs/stream/{model_id}`; pod-exec commands are **presented to the user**, never run via MCP.
- NOTE: `helm` is not installed in the agent worktree env (CI has it) — surfaces needing it must install helm or run the checks in a helm-equipped checkout.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Evidence: crash mechanics on gfx1151 (kernel + Vulkan + unified-RAM accounting) | S | 1 | [] | — |
| C02 | Containment: fail-fast the flash-next ladder on gpu-ai (repo-side) | S | 1 | [] | independent of C01; operator-approved at plan approval |
| C03 | Root-cause fix (RESEARCH-GATED — rewritten by the post-research planning pass) | M | 2 | [C01] | needs C01's measured heap/GTT facts + RESEARCH.md to pick a branch; size firm-ens then |
| C04 | Cluster verification: controlled load attempt + no-freeze proof + record | S | 3 | [C02, C03] | validates the landed change after user merge; containment must be consistent with the fix outcome |

## Wave order
1. C01, C02 (independent; run in id order)
2. C03 — **blocked until agent-research completes and the reintegration planning pass rewrites it**
3. C04

## Open questions → deep research (coordinator: launch agent-research with these)
See RESULT open_questions; they are written there in full and mirrored in `chunks/C03.md` candidate branches.

## Risks / assumptions
- The 512 MiB "dedicated" figure from `/api/hardware` may be llama-swap's parse of one heap, not the whole device-local budget — assumption explicitly not load-bearing (C01 verifies).
- Any fix path that grows GTT/device allocations risks repeating the 2026-10-18/19 **whole-node freeze** (single-node k3s). Mitigation bias: smaller GPU-resident footprint and/or engine-level fixes over larger apertures; C04 requires journal-silent proof.
- The immutable chart pytest contract (golden configs) predates the flash-next catalog in places; a chunk touching config must route golden re-capture through the agent-test session per pipeline rules.
- Landing (merge/PR) is user-owned; cluster checks after merge are part of C04.
