# Contradictions map

## Where perspectives clash
1. **"Unknown top-level keys are ignored" (spec.md §9 [3]) vs passthrough in code
   ([37] generator.py generate_full_config) and base.example.yaml using active
   passthrough keys (`captureBuffer`, `sendLoadingState`) [37].** Weigh: code +
   examples win; the spec sentence describes generation logic, not output merge.
   This is load-bearing for the whole conversion design, so the plan should
   re-verify with one `generate` run.
2. **README's "no per-model YAML entries to write or maintain" [1] vs the
   inversion strategist's finding that aliases/filters/description are NOT
   emittable and matrix IDs must still be hand-maintained.** The pitch is true
   only for the disk-scanned `-m` subset.
3. **Launch premise "llama-swap snippets" vs reality: no `snippets` key exists
   at llama-swap v262 at all** (schema [42], config.example [44], grep). The
   concept maps to `macros` — which autogen models natively. No blocker once
   renamed mentally.
4. **User model naming vs HF naming**: "qwen3.8 flash-next" = exact hit
   `Qwen/Qwen3.8-Flash-Next` [29][30]; "Ornith 1.5 35B" = `Ornith-1.5-35B-A3B`
   (MoE; filenames in the official repo say "35B" without A3B) [22][23].
   "Ornith 1.5 122B" = `ornith-ai/Ornith-1.5-122B` [19].
5. **Provider size discrepancy for flash-next Q8_0**: unsloth 175.3 GiB [32]
   vs ggml-org 151.5 GiB [34]; bartowski Q8_0 175.3 [33] sides with unsloth.
   Unreconciled — likely ggml-org omits a module (vision tower?) — planner
   should prefer unsloth/bartowski and not quote ggml-org sizes as the model
   footprint.
6. **VRAM-fit guidance vs measured reality**: repo comments call gpu-ai the
   "125 GiB node budget"; kubelet stats show ~128 GiB physical RAM with ~94 GiB
   free under current load [readonly-ai-gpu-kubernetes nodes_stats_summary,
   session-internal]. Minor conflict; use the repo's 125 GiB budget number for
   admission decisions since that's the operator-measured ceiling with the trio
   resident.

## What every perspective agrees on (likely true)
- The tool is disk-scan-only; declared/download-on-demand entries are impossible
  without extending it or bypassing it (README [1], spec [3], code [37], zero
  demand issues [2]).
- llama-swap v262 does not download models itself — llama.cpp's `-hf` does,
  inside `cmd` [6][50]; multi-file merging via `-config-dir` is native and
  strict [5][15][46].
- All three requested model families and their q3–q6 quants exist publicly
  (except the official 122B repo has no Q3 — unsloth/bartowski supply it)
  [21][24][25][27][29–33].

## Blind spots (nobody addressed — surfaced by the coordinator)
- No source anywhere describes running THIS generator inside Kubernetes (docs
  cover host+podman only [40]); every k8s shape here is extrapolated —
  validation runs on the cluster are essential.
- Nobody verified the lab's actual gpu-ai VRAM (kubelet stats don't expose it);
  the ≥32GB remark in repo comments [17] means the trio's dense-Q8 residency
  regime is itself operator-measured, so new-model fit must be measured, not
  computed.
- Nobody checked whether the autogen maintainer would accept an upstream PR —
  no CONTRIBUTING file in the tree [36]; assume fork-first.
- Interaction of `-watch-config` with a config-dir where one file lives in an
  emptyDir rewritten only at init: hot-reload semantics of the generated half
  need a plan-level decision (reloader-on-ConfigMap restarts the pod anyway).
