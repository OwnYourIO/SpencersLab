# Perspectives

Topic: adopt shirayu/llama_swap_config_autogen to generate the lab's llama-swap
config, inverting scan-disk → declare-desired, with HF download-on-demand and
three new model families. Audience: the planner agent (infra/GitOps engineer).

1. **Tool-internals archaeologist** (interviewed by the coordinator session, on
   the actual checked-out source) — reads `spec.md`, `cli.py`, `config.py`,
   `generator.py`, `template.yaml` to establish exactly what the tool scans,
   emits, and what extension points exist (patterns, variants, presets,
   overrides). Everyone else will claim features from the README; this lens only
   trusts code. Sees: whether "declared models" is possible without a fork.

2. **Desired-state inversion strategist** (coordinator session) — has a stake in
   NOT forking: evaluates the cheapest concrete path to declare-a-model-before-
   the-GGUF-exists (manifest mode, post-gen merge, template injection, wrapper
   script), each weighed against the GitOps contract (ArgoCD renders the
   ConfigMap; nothing runs at repo time).

3. **llama-swap upstream release lawyer** (subagent) — only the v262-era docs,
   schema, and config.example.yaml count; knows which download-on-demand fields
   (`-hf`, `-hfd`, quant aliases, LLAMA_CACHE, mmproj) are llama.cpp's vs
   llama-swap's, and what "snippets"/`profiles`/`capabilities` mean upstream —
   so conversion targets are grounded in the actual runtime, not memory.

4. **HuggingFace GGUF curator** (subagent) — verifies repos/filenames/quant
   naming/sizes on live HF; the user's model names ("qwen3.8 flash-next",
   "Ornith 1.5") are informal and may not exist verbatim; this lens reports
   best-match candidates with confidence instead of assuming.

5. **Container/GitOps integration engineer** (subagent) — stakes: supply-chain
   hygiene (is the tool on PyPI? an OCI image? pip-from-git in an initContainer?
   self-built container per repo convention?), maintenance risk (1-star project,
   single author), and the k8s mechanics of initContainer-vs-entrypoint against
   the app-template chart shape (ConfigMap-mounted config dir, watch-config).
