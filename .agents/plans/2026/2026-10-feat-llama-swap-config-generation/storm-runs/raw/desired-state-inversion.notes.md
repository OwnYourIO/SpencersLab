# Perspective: Desired-state inversion strategist

## Question asked: does the tool natively support declaring models that are NOT on disk?

**No — exhaustively verified, five ways:**
1. `README.md` "Get Started": models come from `init --model <dir>` + directory
   scan; "Re-run step 3 whenever you add or remove .gguf files."
2. `docs/spec.md` §3.1: `models:` = "Directories to scan for .gguf files";
   §9 Compatibility Notes: "If no models are discovered, generation fails."
3. `generator.py`: discovery is `rglob('*.gguf')` only; every emitted entry's
   cmd embeds the scanned absolute path as `-m <path>` (format_command_with_macro);
   no code path constructs a remote/hub reference. grep of the whole tree for
   `hf|huggingface|download|remote` finds nothing except a doc-example
   `repo_url` metadata string and the `<model>.json` sidecar.
4. GitHub issue tracker (`/issues?state=all`): 11 closed items, all dependabot
   PRs; no one has even requested HF/declarative support.
5. `base.example.yaml`/`template.yaml`: every example references local files.

## The inversion surface that DOES exist (and its limits)
- **Passthrough top-level keys** (generator.py generate_full_config merges every
  unknown base.yaml key into config.yaml; base.example.yaml demonstrates with
  `captureBuffer`, `sendLoadingState`, commented `groups`/`hooks`): lets the
  lab keep `matrix`, `hooks.on_startup.preload`, `apiKeys`, `globalTTL`,
  `profiles`, `performance`, etc. declaratively in base.yaml. This is per-FILE
  pass-through, not per-model.
- **No per-model passthrough**: generated model entries can carry only
  ttl/cmd/name/capabilities/metadata. `aliases`, `filters`, `description`,
  `proxy`, `env`, `checkEndpoint`, `cmdStop`, `unlisted`, per-model `macros`
  are not emittable. (Confirmed in generate_full_config: the per-model dict is
  built with exactly those five keys.)
- **Sidecar `<model>.json`** merges only into `metadata`, requires the GGUF to
  exist (path_model.with_suffix('.json')). Not a declaration mechanism.
- **`path_prefix_map`** rewrites `-m` host→runtime paths only; doesn't create
  entries for absent files.
- **`model_labels`** is a retired key (only in the exclusion set + a
  negative test). No hidden feature there.

## Concrete low-effort paths (for the plan)
A. **Two-source config (zero tool changes) — RECOMMENDED shape.**
   llama-swap v262 natively merges `-config` + `-config-dir` (internal/config/merge.go):
   identity maps (`models`, `matrix`, `groups`, `profiles`...) union by key,
   duplicate keys across sources are hard errors. So:
   - initContainer runs autogen against on-disk GGUFs → `10-generated.yaml`
     into an emptyDir;
   - Helm renders the declared `-hf` roster + matrix + aliases/filters as
     `20-declared.yaml` (ConfigMap key); initContainer copies it next to the
     generated file (or mount the ConfigMap key as a second directory and pass
     -config + -config-dir; run.sh already maps LLAMA_SWAP_CONFIG_DIR).
   - llama-swap merges both at startup; declared models appear before their
     GGUFs exist because their cmd uses `-hf repo:quant` (llama.cpp downloads
     on first request; healthCheckTimeout already sized for it).
   Cost: a 2-line wrapper script (generate + copy) — no YAML-merge logic needed.
   Caveat: autogen's DRY engine then covers ONLY disk models; the declared half
   stays hand-written (the thing the user wanted to reduce).
B. **Small fork/patch adding `hf_models:` (native inversion).**
   New base.yaml section: list of {name, repo: 'org/repo', quant(s) or
   quant_list, macro/pattern fields, explicit capabilities, optional draft
   `-hfd` repo refs}. Emitter reuses the existing pattern/variant machinery but
   builds `${binary} --port ${PORT} --host 0.0.0.0 -hf repo:QUANT ${macro}`
   (no -m, no GGUF reads — capabilities must be declared, not derived). ~
   a day of work + tests; upstreamable as a feature PR (maintainer ships
   features like "decision models" within weeks; but 0 prior issue demand →
   merge is a coin-flip; fork is Apache-2.0 so vendoring is trivial).
   This is the only shape where ALL models flow through one DSL.
C. **Rejected — placeholder scan-tree**: pre-create empty `x-Q4_K_M.gguf`
   files so the scanner emits entries. Fails because the entry cmd is
   `-m /models/.../x-Q4_K_M.gguf` — llama-server never downloads via -m;
   it would load the 0-byte file and die. (Also `-hf` smuggled via macro
   conflicts with the hardwired `-m`; llama.cpp errors or ignores.)
D. **Rejected — `${binary}` shim**: macro `binary: /app/shim` where a
   ConfigMap script maps `-m <placeholder>` to `-hf`. Works in theory, adds an
   untracked indirection layer between llama-swap and llama.cpp, breaks
   checkEndpoint timing intuition, and is worse than B for clarity.

## Decision-relevant nuance for the planner
- llama-swap's strict merge rules make A SAFE against drift (a model ID
  accidentally defined on both halves fails config load loudly, and
  -watch-config reload failures keep the old config? UNVERIFIED — check reload
  failure behavior before relying on it).
- If the plan wants ONE DSL over everything (user's literal ask: "the desired
  models must be declared so their entries appear in the generated config"),
  that is B; A satisfies the operational outcome (declared entries exist before
  files land) with less cleverness.
