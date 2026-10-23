# Outline

1. TL;DR
2. What llama_swap_config_autogen actually is (runtime, CLI, scan→output
   pipeline, naming/quant rules, extension points, container story)
3. The inversion verdict: native support = none; the four concrete paths with
   the two viable ones (config-dir overlay vs forked `hf_models`) — and which
   one matches "generate right before llama-swap starts"
4. Download-on-demand mechanics at v262 (llama-swap vs llama.cpp ownership,
   tag resolution, shards/mmproj/MTP, cache layout, HF auth)
5. New-model HF inventory (flash-next, Ornith 122B, Ornith 35B-A3B: repos,
   exact quant filenames, sizes, gating, box-fit assessment)
6. Conversion blockers for the current lab config (inventory → mapping table)
7. Packaging / integration / maintenance risk
8. Contradictions & reliability notes
9. Implications for the plan
10. Open questions
