# Sources

[1] README (scan-disk workflow; re-run on gguf add/remove) — https://github.com/shirayu/llama_swap_config_autogen/blob/main/README.md
[2] Issue tracker: 11 items, all dependabot PRs, zero human issues — https://api.github.com/repos/shirayu/llama_swap_config_autogen/issues?state=all&per_page=100
[3] spec.md §3.1/§9: models: = dirs to scan; generation fails with no GGUFs — https://github.com/shirayu/llama_swap_config_autogen/blob/main/docs/spec.md
[4] llama-swap v262 file tree (merge.go location) — https://api.github.com/repos/mostlygeek/llama-swap/git/trees/v262?recursive=1
[5] multi-file merge: -config + -config-dir, identity maps, conflict rules — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/internal/config/merge.go
[6] "llama-swap has no setting that downloads a missing GGUF" — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/docs/kb/guides/model-runtime/writing-cmd.md
[7] Repo metadata: created 2025-09-15, pushed 2026-10-22, 1 star, 0 forks, Apache-2.0, Python — https://api.github.com/repos/shirayu/llama_swap_config_autogen
[8] GitHub releases: empty — https://api.github.com/repos/shirayu/llama_swap_config_autogen/releases
[9] GitHub tags: empty — https://api.github.com/repos/shirayu/llama_swap_config_autogen/tags
[10] Commit cadence: 2026-10-22 active, single author — https://api.github.com/repos/shirayu/llama_swap_config_autogen/commits?per_page=15
[11] Maintainer identity: Yuta Hayashibe, 143 public repos since 2011 — https://api.github.com/users/shirayu
[12] PyPI 404: not published — https://pypi.org/pypi/llama-swap-config-autogen/json
[13] CI: uv+task lint/test only, no publish job (via tarball) — https://github.com/shirayu/llama_swap_config_autogen/blob/main/.github/workflows/ci.yml
[14] pyproject: deps PyYAML/gguf/pydantic/jsonschema, requires-python >=3.10 (via tarball) — https://github.com/shirayu/llama_swap_config_autogen/blob/main/pyproject.toml
[15] run.sh: LLAMA_SWAP_CONFIG/CONFIG_DIR/WATCH_CONFIG mapping — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/docker/unified/run.sh
[16] unified runtime: python3+pip+numpy+sentencepiece installed, no git — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/docker/unified/runtime.Dockerfile
[17] Repo chart: unified-vulkan-262 pin, run.sh env usage, persistence layout (local worktree) — https://github.com/SpencersLab/SpencersLab/blob/main/charts/llama-swap/values.yaml
[18] HF search: Ornith family repos — https://huggingface.co/api/models?search=ornith&limit=50
[19] Ornith-1.5-122B base: Qwen3_5Moe, 125.09B BF16 params — https://huggingface.co/api/models/ornith-ai/Ornith-1.5-122B
[20] 122B config: 256 experts, top-8, 48L, hidden 3072 — https://huggingface.co/ornith-ai/Ornith-1.5-122B/raw/main/config.json
[21] official 122B GGUF: Q4_K_M/Q5_K_M/Q6_K/Q8_0/BF16 + mmproj, sizes — https://huggingface.co/api/models/ornith-ai/Ornith-1.5-122B-GGUF/tree/main
[22] official 35B-A3B GGUF: 5 quants + mmproj, sizes — https://huggingface.co/api/models/ornith-ai/Ornith-1.5-35B-A3B-GGUF/tree/main
[23] base 35B-A3B: Qwen3_5MoeForConditionalGeneration — https://huggingface.co/api/models/ornith-ai/Ornith-1.5-35B-A3B
[24] unsloth 122B: UD ladder incl. Q3-Q6_K_XL shards, mmproj — https://huggingface.co/api/models/unsloth/Ornith-1.5-122B-GGUF/tree/main?recursive=true
[25] bartowski 122B: full K/IQ ladder, imatrix, mmproj — https://huggingface.co/api/models/bartowski/Ornith-1.5-122B-GGUF/tree/main?recursive=true
[26] 35B GGUF providers: official, bartowski, mudler APEX-MTP, derivatives — https://huggingface.co/api/models?search=Ornith-1.5-35B&filter=gguf&limit=30
[27] bartowski 35B-A3B: all 28 quants enumerated with sizes — https://huggingface.co/api/models/bartowski/Ornith-1.5-35B-A3B-GGUF/tree/main?recursive=true
[28] 122B MTP derivative quants/sizes — https://huggingface.co/api/models/prithivMLmods/Ornith-1.5-122B-MTP-GGUF/tree/main?recursive=true
[29] Qwen3.8-Flash-Next ecosystem: Qwen org + unsloth/bartowski/ggml-org/orcarouter GGUFs — https://huggingface.co/api/models?search=qwen3.8%20flash&limit=50
[30] base: Qwen4Exp MoE, 180B BF16 params — https://huggingface.co/api/models/Qwen/Qwen3.8-Flash-Next
[31] flash-next config: 512 experts top-10, moe_intermediate 640, 48L — https://huggingface.co/Qwen/Qwen3.8-Flash-Next/raw/main/config.json
[32] unsloth flash-next: UD Q2-Q6 + Q8/BF16 shards, MTP/, mmproj — https://huggingface.co/api/models/unsloth/Qwen3.8-Flash-Next-GGUF/tree/main?recursive=true
[33] bartowski flash-next: full ladder incl. Q3_K_M 85.6, Q4_K_M 111.4, Q5_K_M 125.4, Q6_K 156.6 — https://huggingface.co/api/models/bartowski/Qwen3.8-Flash-Next-GGUF/tree/main?recursive=true
[34] ggml-org flash-next reference: Q2_K/IQ4_NL/Q8_0 + mtp/dflash — https://huggingface.co/api/models/ggml-org/Qwen3.8-Flash-Next-GGUF/tree/main
[35] orcarouter gated="auto" flag (HF auth required) — https://huggingface.co/api/models/orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF
[36] Full file tree at main (commit c7357e68) — https://api.github.com/repos/shirayu/llama_swap_config_autogen/git/trees/HEAD?recursive=1
[37] Source tarball pinned to c7357e68 (read locally: pyproject.toml, cli.py, models.py, config.py, generator.py, validation_models.py, template.yaml, base.example.yaml, docs/*) — https://github.com/shirayu/llama_swap_config_autogen/archive/c7357e68c755b54557f5b0f88b0507bf1c981500.tar.gz
[38] tutorial.md: parameterized macros, variant presets, mmproj/draft binding (via tarball) — https://github.com/shirayu/llama_swap_config_autogen/blob/main/docs/tutorial.md
[39] capabilities.md: auto-derived capabilities (via tarball) — https://github.com/shirayu/llama_swap_config_autogen/blob/main/docs/capabilities.md
[40] containerized-setup.md (via tarball) — https://github.com/shirayu/llama_swap_config_autogen/blob/main/docs/containerized-setup.md
[41] vram-estimation.md: fit-params, caching, sidecar JSON (via tarball) — https://github.com/shirayu/llama_swap_config_autogen/blob/main/docs/vram-estimation.md
[42] llama-swap v262 config-schema.json — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/config-schema.json
[43] llama-swap v262 KB: Configuration overview — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/docs/kb/guides/configuration/configuration-overview.md
[44] llama-swap v262 docs/config.example.yaml — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/docs/config.example.yaml
[45] llama-swap v262 unified Vulkan builder base — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/docker/unified/base-vulkan.Dockerfile
[46] llama-swap v262 main flags (-config-dir additive) — https://raw.githubusercontent.com/mostlygeek/llama-swap/v262/llama-swap.go
[47] mostlygeek/llama-swap releases (v262 published 2026-10-03) — https://api.github.com/repos/mostlygeek/llama-swap/releases
[48] config.example.yaml moved to docs/ (root file = pointer) — https://github.com/mostlygeek/llama-swap/blob/v262/config.example.yaml
[49] llama.cpp 889edf43 HF cache (LLAMA_CACHE, hub layout) — https://raw.githubusercontent.com/ggml-org/llama.cpp/889edf43/common/hf-cache.cpp
[50] llama.cpp 889edf43 download plan (repo:tag resolution, shards, mmproj/MTP siblings) — https://raw.githubusercontent.com/ggml-org/llama.cpp/889edf43/common/download.cpp
[51] llama.cpp 889edf43 args (--hf-token default $HF_TOKEN, --no-mmproj) — https://raw.githubusercontent.com/ggml-org/llama.cpp/889edf43/common/arg.cpp
[52] unified image build directory at v262 — https://github.com/mostlygeek/llama-swap/tree/v262/docker/unified
