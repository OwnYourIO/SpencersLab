# Perspective: Tool-internals archaeologist

Interviewed against the actual checked-out source at commit
`c7357e68c755b54557f5b0f88b0507bf1c981500` (main, 255 commits, retrieved
2026-10-22 as tarball from
https://github.com/shirayu/llama_swap_config_autogen/archive/c7357e68c755b54557f5b0f88b0507bf1c981500.tar.gz).
All claims below cite files in that tree.

## Runtime & dependencies
- Python >=3.10, deps: PyYAML>=6.0, gguf>=0.18.0, pydantic>=2.0, jsonschema>=4.0.0
  (pyproject.toml). Console script: `llama-swap-config-autogen` ->
  `llama_swap_config_autogen.cli:main` (pyproject.toml [project.scripts]).
- No network access needed for generation itself (pure-local: directory scan +
  optional GGUF header reads). `--llama-bin` (fit-params) is only for the
  optional VRAM estimation and is shlex-split, so it can be any command that
  execs llama.cpp's `llama fit-params` (docs/vram-estimation.md) — including a
  `podman/docker exec` into a running container.
- Caches under `~/.cache/llama_swap_config_autogen/{fit_params_vram,gguf_metadata}.json`
  (docs/vram-estimation.md §Caching; FitParamsCache.load/GGUFMetadataCache.load
  called in generator.py).

## CLI surface (cli.py)
- `init --model <dir> (repeatable, required) --binary <llama-server path> (required) [--output]`
  — writes a starter base.yaml (template.yaml + your dirs). Path validators print
  errors to stderr but do NOT abort (validate_model_dir/validate_binary_file
  just sys.stderr.write).
- `generate --config base.yaml [--output config.yaml] [--verbose] [--llama-bin CMD]`
  — emits full config.yaml to stdout or file (yaml.dump, sort_keys=False,
  literal blocks preserved).
- `validate <llama-swap config.yaml> [--quiet]` — business-logic validation of a
  final llama-swap config: checks alias uniqueness, group members exist,
  hooks.preload targets exist, undefined macros (skips PORT/MODEL_ID/PID).
  Validation models (validation_models.py) only understand models/cmd/cmdStop/
  proxy/aliases/checkEndpoint, `groups` (legacy), macros, hooks — it does NOT
  know `matrix`, `profiles`, `capabilities` (extra="ignore", so unknown keys
  pass, but nothing is cross-checked for them).

## What it scans — and ONLY what it scans
- base.yaml `models:` is a list of DIRECTORIES; discovery is
  `models_dir.rglob("*.gguf") | rglob("*.GGUF")` (generator.py
  generate_model_configs). There is NO HF index scan, no remote model support,
  no file-exempt entries: if no .gguf is found anywhere, generation FAILS
  ("No models found. Searched directories: ..." generator.py; docs/spec.md §9
  "If no models are discovered, generation fails").
- Directory layout is strictly enforced: `<model>/*.gguf`, `<model>/<variant>/*.gguf`,
  or an optional leading family dir that's dropped from naming; deeper/mixed
  layouts raise (generator.py should_ignore_first_segment, format_model_layout_details;
  spec.md §3.1). mmproj files (name contains "mmproj") and draft files (name
  matches /\bmtp\b|draft/i) are excluded from standalone models and instead
  attached (-- docs/spec.md §3.6/§3.7).

## Quantization / naming rules
- Quant suffix is extracted from the FILENAME by regex
  `-(Q\d(?:_[A-Z0-9]+)+|BF16|F16)(?=\.gguf$)`; no match -> ValueError
  ("Could not determine quantization suffix") (generator.py QUANTIZATION_PATTERN,
  extract_quantization_suffix). Consequences:
  - `unsloth_..._UD-Q4_K_XL.gguf` yields quant token `Q4_K_XL` — the UD- prefix
    is LOST from the ID. A UD-Q4_K_XL file and a plain Q4_K_XL file in the same
    directory would collide on ID; duplicate model IDs are silently ignored
    after first occurrence (spec.md §5). UNVERIFIED risk: the lab uses UD- quants.
  - Q10+ or Q0 quants, or names like `Q4_K_M-isl` would fail/mismap.
- Model ID = `<relative dir path, lowercased, family stripped>:<QUANT>`
  (build_model_id). Name defaults to the same string. Variants append a
  suffix-derived ID (`:Q4_K_M-(with-cpu)` via format_suffix_for_id).

## Generated cmd — FIXED template (the crux for this ticket)
- spec.md §4.3 / generator.py format_command_with_macro:
  `${binary} -m <abs model path> --port ${PORT} --host 0.0.0.0 [<mmproj_arg> <path>] [<draft_arg> <path>] <macro-or-${macro}>`
  - The `-m <path>` is hardwired. You CANNOT get `-hf repo:quant` into a
    generated cmd via any documented field — `binary` macro text could in
    principle smuggle a shim script, but `-m` would still be in argv.
  - mmproj/draft args are configurable (`mmproj.arg`, `draft.arg`), so `draft.arg: -hfd`
    would emit `-hfd <local path>` — still a scanned path, not a hub ref.
- Per-model emitted keys (generator.py generate_full_config): ONLY
  `ttl, cmd, name`, plus `metadata` and `capabilities` when present. NO
  `description`, NO `aliases`, NO `proxy`, NO `filters`, NO `checkEndpoint`,
  NO `env`, NO `cmdStop`, NO `unlisted`, NO per-model `macros` on output models.
- Top-level output = healthCheckTimeout/logLevel/startPort (from base.yaml
  declared keys) + EVERY unknown top-level base.yaml key PASSED THROUGH
  (generator.py merges `config.model_extra` minus
  {vram_estimation, read_gguf_metadata, model_labels, path_prefix_map}) —
  base.example.yaml shows `groups` and `hooks` passthrough examples, and
  captureBuffer/sendLoadingState as active passthrough keys. So `matrix`,
  `profiles`, `apiKeys`, `globalTTL`, `unloadTimeout`, `logToStdout`,
  `includeAliasesInList`, `performance` will pass through untouched (Config is
  extra="allow", models.py).
- `macros:` in the OUTPUT are re-emitted but ONLY those referenced by generated
  commands, after full recursive expansion of nested macros
  (extract_used_macros_from_commands; spec.md §2 flow step 7). Macros support
  positional args `${macro:arg1,arg2}` with `${1}`/`${2}` placeholders and
  rightmost-wins duplicate-flag dedupe (expand_macro + deduplicate_parameters;
  tutorial.md §2). Macro names are normalized: `.` -> `-` (config.py
  normalize_macro_name) — `${env.HF_TOKEN}`-style refs keep their `.` only
  because they're not in all_macros (left as `${...}` literal by expand_macro;
  but note normalize only applies to macro KEYS, a `${env.X}` ref inside a
  macro value stays as-is).

## Capabilities & metadata derivation (extra value for conversion)
- capabilities.context from -c/--ctx-size in expanded cmd, fallback GGUF
  header; `in` from attached mmproj clip.has_vision_encoder/has_audio_encoder;
  `tools` from chat_template; `out:[decisions]` for decision GGUFs; explicit
  `model_patterns.<p>.capabilities` override auto-derivation
  (generator.py build_capabilities; docs/capabilities.md). Needs
  `read_gguf_metadata: true` (or vram_estimation) for the GGUF-derived parts.
- metadata: model_family, estimated_vram_bytes (fit-params; adds mmproj/draft
  file sizes), file_size_bytes, content_fingerprint (size + first/last 4MiB
  SHA-256), expert_count/expert_used_count, repo_url, license,
  mmproj_projector_type; merged LAST with user-authored `<model>.json` sidecar
  next to the GGUF whose keys win (generator.py build_model_metadata,
  load_sidecar_metadata; docs/vram-estimation.md §Sidecar).
- `model_labels` appears only in the passthrough EXCLUSION set and a test that
  asserts labels are NOT embedded in names (test/test_mmproj.py
  test_visual_model_labels_are_not_embedded_in_name) — i.e. it's a retired key
  kept out of output; there is no active label feature. (UNVERIFIED: no doc
  mentions it.)

## Snippets / profiles handling
- There is NO llama-swap "snippets" concept in the tool (grep across tree: the
  only hit is a comment "macros are reusable snippets" in
  test/example.llam_swap.original.yaml). `profiles` likewise absent from the
  generator; a `profiles:` block could only ride through as a passthrough
  top-level key. llama-swap's real config surface for reuse IS `macros`, which
  the tool models natively.

## What this perspective concludes for the ticket
- The tool is a *disk-scan-only* config generator with a fixed `-m` command
  template. The inversion the user wants (declare models before GGUFs exist,
  download on demand via `-hf`) is NOT expressible in its input format at all.
  Any path to the user's goal is either (a) a fork/PR adding a declared-models
  section that emits `-hf` cmd entries, or (b) wrapper/merge: generate for
  on-disk models and stitch declarative `-hf` entries + per-model extras
  (aliases/filters/description) around it, or (c) abandon `-m`-style scanning
  for the lab's roster and keep those as declared entries only.
