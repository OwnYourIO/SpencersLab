# Perspective: llama-swap upstream release lawyer (v262)

All claims verified against tag `v262` (published 2026-10-03) of
mostlygeek/llama-swap, or llama.cpp commit `889edf43` (the revision the lab's
`unified-vulkan-262` image audit note names). URLs in sources.tsv.

## v262 ↔ image tag mapping
- llama-swap ships plain sequential tags: `v262` exists, released 2026-10-03,
  latest at research time is v265 (2026-10-14).
  https://api.github.com/repos/mostlygeek/llama-swap/releases
- The lab's chart comment says unified-vulkan-262 == "the v262-release image of
  the per-project (unified) pipeline" — consistent with tags above and the
  `docker/unified/*` build files present at tag v262
  (https://github.com/mostlygeek/llama-swap/tree/v262/docker/unified:
  base-vulkan.Dockerfile, runtime.Dockerfile, run.sh, build-image.sh, unified-docker*.yml workflows).

## The config-surface that matters here (v262 schema, 49KB)
- Top-level keys (complete list from config-schema.json properties):
  apiKeys, captureBuffer, globalConcurrencyLimit, globalTTL, groups,
  healthCheckTimeout, hooks, includeAliasesInList, logLevel, logTimeFormat,
  logToStdout, macros, matrix, metricsMaxInMemory, models, peers, performance,
  profiles, routing, security, selectors, sendLoadingState, startPort, store,
  tailcat, ui, unloadTimeout, upstream.
  → **There is NO `snippets` key in llama-swap at all.** The word appears only
  once in v262's own config.example.yaml ("macros are reusable snippets") and
  once in the autogen tool's test fixture — it is a mental synonym for `macros`,
  not a feature. The launch message's "llama-swap snippets" therefore maps to
  `macros:` (+ per-model `macros:` overrides) and YAML anchors, nothing else.
- Per-model keys (schema): cmd, cmdStop, name, description, env, proxy,
  checkEndpoint, ttl, unloadTimeout, useModelName, aliases, unlisted, metadata,
  concurrencyLimit, sendLoadingState, timeouts, filters, macros, capabilities,
  compat. The lab uses a wide subset (all present) — including `capabilities`
  (in/out/tools/...) and per-model `filters.setParamsByID`.
- `profiles` (schema, v262): "Runtime-selectable model ID rewrites. One profile
  or none may be active at runtime." pins map model IDs → target (""/`~` disables).
  Not used by the lab today; the autogen tool doesn't generate it (passthrough only).

## Download-on-demand: llama-swap explicitly does NOT own it
- v262 KB `docs/kb/guides/model-runtime/writing-cmd.md`, section "Model files",
  verbatim: "llama-swap has no setting that downloads a missing GGUF from
  Hugging Face or another model registry. The file must already exist, or the
  configured `cmd` must fetch it before starting the inference server."
- Which is exactly the lab's shape: `cmd` contains llama.cpp's `-hf repo:quant`;
  llama-server does the fetch at startup into `LLAMA_CACHE=/models`; that is
  why healthCheckTimeout=3600 exists in the chart (comment in
  charts/llama-swap/values.yaml).

## llama.cpp (889edf43) `-hf` mechanics — the real "fields"
- Syntax: `-hf <user>/<model>[:quant]` — split on ':' (download.cpp
  common_download_split_repo_tag; invalid without exactly one '/').
- Tag resolution (find_best_model): regex `TAG[.-]` case-insensitive against
  file paths; picks the FIRST non-shard-tail `.gguf` that is a model file
  (filename excludes mmproj/imatrix/mtp-/eagle3-/dflash-/dspark-); empty tag
  tries `Q4_K_M` then `Q8_0` then first available. `:F16`/`:BF16` match any
  filename containing `-F16.` / `-F16-` (e.g. `-F16-00001-of-00002.gguf` heads)
  and get_split_files pulls ALL shards sharing prefix+count — this is how the
  lab's two-shard orcarouter `:F16` works.
- mmproj auto-download when `-hf` repo has one and `--mmproj` path unset
  (opts.download_mmproj; `--no-mmproj` disables; find_best_mmproj picks best
  "mmproj" sibling preferring exact tag match then closest quant bits).
- Sidecars: `--spec-type draft-mtp` (+`-hfd repo[:tag]` for external MTP drafts
  — the lab's ggml-org `mtp-Qwen3.8-27B-Q8_0.gguf` pattern; find_best_mtp matches
  `mtp-` siblings, tag-aware).
- Cache layout: **HF-hub cache format** — `$LLAMA_CACHE` (env precedence:
  LLAMA_CACHE > HF_HUB_CACHE > HUGGINGFACE_HUB_CACHE > HF_HOME/hub > ...),
  `models--<org>--<repo>/refs/<branch>` + `snapshots/<commit>/<paths>` symlinks
  into `blobs/<oid>`; symlinks fall back to copies ("degraded mode").
  Offline mode reads the snapshot dir directly (get_cached_files).
- Auth: `-hft/--hf-token`, default from env `HF_TOKEN` (arg.cpp line 3082,
  set_env("HF_TOKEN")) — matches the lab's gpu-ai note.

## Multi-file config: `-config-dir` IS the merge mechanism
- llama-swap.go (v262): `-config-dir` = "directory of *.yml/*.yaml config files
  (additive to -config)"; run.sh maps LLAMA_SWAP_CONFIG_DIR and explicitly
  notes "-config-dir is additive" and guards the default `-config` to avoid
  merging the image's example config.
- Merge engine internal/config/merge.go:
  * `-config` file first, then dir files in SORTED FILENAME order.
  * `models`, `groups`, `profiles`, `selectors`, `peers`, `matrix` are
    "identity maps": children append; a key defined in TWO sources is a HARD
    ERROR ("duplicate models \"x\" found in ...") → safe two-file overlay as
    long as generated IDs and declared IDs never collide.
  * other mappings (e.g. `macros`, `hooks`) merge recursively; sequences
    concatenate; two DIFFERENT scalar values for the same path = conflict error.
  * `${env.VAR}` substitution happens per-file before parse.
  * watch-config re-loads on dir/file change (main.go watch wiring ~line 429).
- Implication for the ticket: a generated file (disk-scan `-m` entries) and a
  declared file (roster of `-hf` entries + aliases/filters/matrix) can be
  loaded together natively — no in-cluster YAML-merge script required, IF
  model-ID namespaces are kept disjoint. (UNVERIFIED: whether matrix `vars`
  referencing a model missing from `models` is tolerated — the repo's gpu-ai
  comment "vars must not reference undefined models" implies it is a load error;
  not confirmed from source in this pass.)
