> Mirror of `.agents/plans/2026/2026-10-feat-llama-swap-config-generation/RESEARCH.md` (the pipeline deliverable); citations [n] key to ./sources.md.
# RESEARCH — llama-swap config autogen adoption (2026-10-feat-llama-swap-config-generation)

Written by `agent-research` 2026-10-22 (STORM run: `storm-runs/adopt-shirayullama-swap-config-autogen-to-generate-llama/`, sources [n] keyed to its `sources.md`; interview trail in `raw/`). Tool facts read from the pinned source checkout at commit `c7357e68` [37].

## TL;DR
1. `shirayu/llama_swap_config_autogen` is a disk-scan-only Python generator: it discovers `*.gguf` in directories and emits `cmd: … -m <path> …`; declaring models that are not on disk is **impossible in its input format**, and its generated commands can **never carry `-hf`** (the template is fixed) [1][3][37].
2. Download-on-demand was always llama.cpp's job (`-hf repo:quant` in `cmd`, `LLAMA_CACHE`, `HF_TOKEN`), not llama-swap's — v262 says so verbatim [6][49][50][51]. The lab's current roster is 100 % `-hf`-based, so the autogen's native pattern fits ~0 of the lab's models.
3. Inversion is achievable **without touching the tool**: llama-swap v262 natively merges `-config` + `-config-dir` with strict identity-map semantics — put autogen output and a declared `-hf` roster as two files, no merge script [5][15][46]. One true DSL needs a **small fork** adding an `hf_models:` section.
4. All three requested model families exist on HF with q3–q6 (official Ornith-122B repo lacks Q3; unsloth/bartowski cover it). **The 180B-class flash-next at q5/q6 (147–157 GiB) and 122B at q8 exceed the gpu-ai node's ~125 GiB RAM budget outright** — the requested quant ladders are only partly deployable [29–33][21][24][25].
5. Integration supply-chain: no PyPI, no releases/tags, no OCI image, 1 star, single active author → pin a commit SHA, self-build a tiny `containers/` image or vendor 12 .py files; the unified-vulkan image already ships python3+pip (no git) if an entrypoint wrapper is chosen [8][9][12][16][7][11].

## Reliability notes (peer review)
- **8/10 — tool has no native declared-model support.** Read every extension point in source (spec §9 + `generate_full_config` + sidecars + `model_labels`); zero issues in the tracker requesting it. Verification path: one `pip install git+… && generate` run against an empty dir fails ("No models found") — the plan can prove it in minutes.
- **9/10 — llama-swap v262 `-config-dir` merge semantics** (identity maps hard-error on duplicates, macros union, sequences concat, scalar conflicts error): read `merge.go` directly [5]. One UNVERIFIED edge: whether `matrix.vars` referencing a model ID absent from `models` is a load error — repo comments imply yes; test in cluster.
- **7/10 — flash-next/122B fit verdicts.** Sizes are hard facts from the HF API; the fit reasoning uses the repo's own 125 GiB budget comment + kubelet RAM snapshot. gpu-ai VRAM (the binding constraint for dense non-expert weights at -ngl 999) is NOT independently verified. Plan must treat q3/q4-tier residency as measure-on-cluster, not pre-guaranteed.
- **6/10 — ggml-org flash-next Q8_0 = 151.5 GiB vs 175 GiB elsewhere.** Unreconciled provider discrepancy (suspected module omission). Do not size anything off ggml-org flash-next files until checked; prefer unsloth/bartowski.
- Perspective weighting: tool-internals + upstream-release got the most source time (correctly — the plan hinges on them). The HF curator table is fresh data (all fetched today, 2026-10-22) but quants/filenames churn on these very new repos (122B GGUF updated 2026-10-21!). Re-verify the exact filenames of chosen quants at implementation time.

---

## 1. How `llama_swap_config_autogen` actually works (Q1)

**Runtime & packaging.** Python ≥3.10; deps `PyYAML`, `gguf`, `pydantic≥2`, `jsonschema` (pyproject [14][37]). Console script `llama-swap-config-autogen` → `cli.py` [14]. Not on PyPI (404 [12]); no GitHub releases or tags ([8][9]) — pip-install from a git URL or an archive-tarball URL only [1][37]. Repo created 2025-09-15, still pushed to on 2026-10-22; 1 star/0 forks/0 human issues; single maintainer (Yuta Hayashibe, 143 public repos since 2011) [7][10][11][2]. CI is uv/mise lint+test only, no publish workflow [13].

**CLI.** Three subcommands (cli.py [37]):
- `init --model <dir> --binary <llama-server path> -o base.yaml` — scaffolds base.yaml from the bundled `template.yaml`; validators print path errors but do not abort.
- `generate --config base.yaml [-o config.yaml] [--llama-bin CMD] [-v]` — full llama-swap config (YAML, literal blocks). `--llama-bin` is only consumed by the optional `vram_estimation` feature (runs `llama.cpp fit-params` via shlex-split command, e.g. `podman exec …`; docs/vram-estimation [41]).
- `validate <config.yaml>` — checks alias uniqueness, groups/preload references, macro resolution. Its models only understand `cmd/cmdStop/proxy/aliases/checkEndpoint/groups/macros/hooks` — it ignores `matrix`/`profiles`/`capabilities` (extra=ignore) [37 validation_models.py].

**What it scans.** Only directories: base.yaml `models:` is a list of paths; discovery = `rglob("*.gguf"/"*.GGUF")` [37 generator.py]. Required layout is strict: `<model>/*.gguf`, `<model>/<variant>/*.gguf`, or optional leading family dir; anything deeper/mixed → hard error; nothing found → generation fails [3 spec §3.1/§9][37]. It does **not** scan any HF index or remote catalog (README never claims that; launch-message premise corrected).

**What it outputs.** A full `config.yaml`: `healthCheckTimeout/logLevel/startPort` (declared) +
**every unknown top-level base.yaml key passed through verbatim** (matrix,
groups, hooks, apiKeys, profiles, captureBuffer, sendLoadingState, performance —
demonstrably used in base.example.yaml [37], per `generate_full_config` merging
`config.model_extra`; also spec-adjacent behavior [3]) + `models:` + `macros:`
restricted to those actually referenced, after full recursive macro expansion. Per model exactly: `ttl`, `cmd`, `name`, optional `metadata`, optional `capabilities`. **No aliases, description, proxy, filters, env, checkEndpoint, cmdStop, unlisted, or per-model macros are emittable.**

**Command template (the crux).** Fixed: `${binary} -m <abs path> --port ${PORT} --host 0.0.0.0 [--mmproj …] [--draft-arg …] ${macro}` [3 §4.3][37]. The `-m` path is hardwired from the scan; a generated profile **cannot** express `-hf`. mmproj/draft attachment is auto-discovery by filename (`mmproj`, `mtp|draft` tokens) with overrides; `draft.arg` is configurable (`-hfd` possible — but still a scanned local path) [3 §3.6–3.7][37].

**Naming/quantization.** Model ID/name = `<dir path lowercased, family stripped>:<QUANT>`; QUANT extracted by filename regex `-(Q\d(_[A-Z0-9]+)+|BF16|F16)(?=\.gguf$)` — no match → ValueError (so `-imatrix.gguf` files in a scanned dir **crash generation**; and `UD-Q4_K_XL` becomes `Q4_K_XL`, colliding with a plain `Q4_K_XL` file → duplicate IDs silently ignored after first) [37][3 §5]. Variants/presets append suffixed IDs (`:Q4_K_M-(with-cpu)`), driven by `model_patterns` (first substring/glob match wins, fallback `default-params`) and `variant_presets` with parameterized macros `${macro:arg}` + rightmost-flag-wins dedupe [37][38].

**Templates/overrides/presets.** Yes: hierarchical `macros` (normalized `.`→`-`), `model_patterns` (macro/emit_base/variants/capabilities/mmproj/draft), `variant_presets` (with pattern-local macro slots like `fast-params`), legacy `variants` [3][38]. `capabilities` (context/in/out/tools/reranker) and rich `metadata` (estimated_vram_bytes, file_size_bytes, content_fingerprint, expert counts, repo_url, license, mmproj projector type) are auto-derived from GGUF headers when `read_gguf_metadata`/`vram_estimation` enabled, overridable per pattern and via per-file `<model>.json` sidecars (metadata only) [39][41][37]. There is **no "snippets" feature** — llama-swap has no `snippets` key at all at v262 (grep of schema [42] + config.example [44]: the word appears only as a comment); the lab's "snippets" are `macros` + YAML anchors, which map cleanly onto the tool's macros.

**Container story per the tool's own docs.** Host-side generation, paths rewritten into the runtime via `path_prefix_map`, binary path per container, `--llama-bin` via `podman/docker exec` [40]. Nothing k8s-specific exists — k8s shapes are extrapolated (see §7, flag in blind spots).

## 2. Declared/desired-state support (Q2)

**Native support: none** — proven five ways (README flow [1]; spec §3.1/§9 [3]; source: scan-only discovery + fixed `-m` cmd + no remote strings anywhere [37]; issue tracker with zero human issues [2]; examples all local [37]).

Viable inversion paths (full analysis + rejected options in `raw/desired-state-inversion.notes.md`):

- **Path A — two-source config, zero tool changes (recommended default).** llama-swap v262 merges `-config` + `-config-dir`: dir files merged in sorted order; `models`/`matrix`/`groups`/`profiles`/`peers`/`selectors` are **identity maps** — children union, duplicates across files are hard config errors; `macros` union recursively; sequences concat; differing scalars error [5][46]. Unified `run.sh` exposes `LLAMA_SWAP_CONFIG_DIR` [15]. Shape: Helm renders (1) a `base.yaml` ConfigMap (macros/patterns for whatever runs the lab *does* scan) and (2) a `20-declared.yaml` ConfigMap (the `-hf` roster + aliases/filters/description/matrix/hooks — i.e. today's config, split cleanly); an initContainer runs `generate` into the emptyDir config dir; llama-swap starts against that dir. Declared entries exist **before** GGUFs land because their cmd is `-hf repo:quant` and llama.cpp downloads on first request [6]. Cost: ~one wrapper command + volume wiring; no YAML-merge code.
- **Path B — small fork/patch adding an `hf_models:` section (true single-DSL inversion).** Entries declare `{name, repo, quant(s), pattern fields, capabilities, mtp -hfd ref}`; the emitter bypasses the scan and builds `${binary} --port ${PORT} --host 0.0.0.0 -hf repo:QUANT ${macro}`. Reuses patterns/variants/preset machinery; capabilities can't be auto-derived (no file) — must be declared. Apache-2.0 → trivially vendorable into `containers/`. Upstreaming: no prior demand and no CONTRIBUTING file — assume fork-first, PR opportunistically. This is the only path where *all* models flow through autogen's DRY DSL.
- **Rejected:** placeholder `.gguf` files (cmd would `-m` a 0-byte file; llama.cpp never downloads via `-m`) [50]; a `${binary}` shim rewriting `-m`→`-hf` (fragile indirection; worse than B).

Decision input for the plan: A preserves behavior today with near-zero risk and satisfies the operational goal; B delivers the user's literal "declare-in-the-generator" wish at the cost of owning a fork. A+B hybrid is also coherent (base.yaml drives B-style declared entries once the fork lands).

## 3. Download-on-demand at the pinned v262 (Q3)

- **Ownership**: llama-swap ships nothing for downloads — docs verbatim: "llama-swap has no setting that downloads a missing GGUF from Hugging Face… the configured `cmd` must fetch it" [6]. No download-ish key exists in the v262 config schema (full top-level key list verified) [42].
- **Mechanism** (llama.cpp `889edf43`, the commit the chart's image audit names [17]):
  - `-hf <org>/<repo>[:tag]` (also `-hfr`); `-hfd <repo>[:tag]` for a separate speculative-draft repo. Tag resolution: filename regex `TAG[.-]` case-insensitive; empty tag → `Q4_K_M`→`Q8_0`→first model GGUF; non-head shards skipped as primaries and **all shards pulled together** (`-00001-of-0000N` prefix+count grouping) — this is how the lab's `:F16` two-shard entry works [50 download.cpp].
  - Model-file filter excludes `mmproj|imatrix|mtp-|eagle3-|dflash-|dspark-` names; mmproj auto-attached for `-hf` repos unless `--no-mmproj` (lab chart already relies on this); `mtp-…` siblings resolve as embedded/sidecar drafts with tag-awareness [50].
  - Cache: hub-style layout under `LLAMA_CACHE` (env precedence `LLAMA_CACHE`>`HF_HUB_CACHE`>`HUGGINGFACE_HUB_CACHE`>`HF_HOME/hub`): `models--<org>--<repo>/refs/<branch>` + `snapshots/<commit>/<file>` symlinks → `blobs/<oid>` (degrades to copies). Offline falls back to cached files [49]. **Implication:** scanning `/models` with the autogen tool is effectively impossible — files sit at snapshot depth-4 paths whose dir names (`snapshots/<sha>`) collide across repos and break the strict layout; IDs derived from it would be garbage [37][3][49].
  - Auth: `-hft/--hf-token`, default from env `HF_TOKEN` [51] — matches the chart's gpu-ai secret wiring [17]; the `gpu` box has no HF_TOKEN, so any gated repo (e.g. orcarouter flash-next uncensored [35]) is gpu-ai-only.
- **Can generated profiles carry download fields?** Only if the tool is forked (Path B) or the entry lives in the declared half (Path A) — the stock generator hardwires `-m` [3 §4.3].

## 4. HF availability of the requested models (Q4) — all fetched 2026-10-22

### A) "qwen3.8 flash-next" — exists, exact-name hit
`Qwen/Qwen3.8-Flash-Next` [30]: arch `Qwen4ExpForConditionalGeneration`, **512 experts / top-10**, 48 layers, hidden 2560, **180B BF16 params**; vision (mmproj everywhere); MTP sidecars in-repo [31][32]. Community brands it "125B-A5B" — active-param claim UNVERIFIED.

| quant ask | best-match `-hf` reference (public) | total GGUF size |
|---|---|---|
| q3 | `unsloth/Qwen3.8-Flash-Next-GGUF:UD-Q3_K_XL` (shards) [32]; alt bartowski `:Q3_K_M` 85.6 / `:Q3_K_S` 83.3 [33] | 83.8 GiB |
| q4 | `unsloth/…:UD-Q4_K_XL` 103.7 [32]; bartowski `:Q4_K_M` 111.4 [33] | 104–111 GiB |
| q5 | unsloth UD-Q5_K_XL 147.4 [32]; bartowski Q5_K_M 125.4 [33] | 125–147 GiB |
| q6 | unsloth UD-Q6_K_XL 157.5 [32]; bartowski Q6_K 156.6 [33] | 156–158 GiB |
Also: ggml-org reference (Q2_K 77.4 / IQ4_NL 95.0 / Q8_0 151.5 — Q8 size conflicts with unsloth's 175.3; unreconciled) [34]; orcarouter Uncensored **gated:auto** [35]; huihui/GSQ/abliterated derivatives plentiful [29].
**Fit**: gpu box (8 GiB VRAM / 64 GiB RAM): infeasible at any of these. gpu-ai (~125 GiB budget): q3 (84 GiB weights) is already larger than today's largest solo-set resident (80B-A3B Q4 48.6 GiB) [17] — q3/q4 need a fresh RAM+VRAM regime test as SOLO, and per the repo's own OOM history (node-freeze incidents) this must be gated by `fit-params` before enabling; q5/q6 **exceed node RAM → cannot be offered as the user asked** [32][33]. VRAM binding term (non-expert ~59B params by my estimate from [31]) is unmeasured — flag, don't assume.

### B) "Ornith 1.5 122B" — exists
`ornith-ai/Ornith-1.5-122B` [19]: `Qwen3_5Moe` (qwen3_5_moe), 256 experts/top-8, 125.09B params (⇒ ~92 % of weights are routed experts; expert-on-CPU offload is the serving regime) [20].

| quant ask | options (public) | size |
|---|---|---|
| q3 | **no Q3 in official repo** [21]; unsloth `UD-Q3_K_XL` 55.7 [24]; bartowski Q3_K_M 56.5 (K_S 53.5, K_L 59.8) [25] | 54–60 GiB |
| q4 | official `ornith-ai/Ornith-1.5-122B-GGUF:Q4_K_M` 70.6 (single file) [21]; unsloth UD-Q4_K_XL 74.2 [24]; bartowski Q4_K_M 73.5 [25] | 71–74 GiB |
| q5 | official Q5_K_M 82.6; unsloth UD-Q5_K_XL 88.1; bartowski Q5_K_M 88.4 | 83–88 GiB |
| q6 | official Q6_K 95.4 [21]; unsloth UD-Q6_K_XL 106.4 [24]; bartowski Q6_K 101.8 / Q6_K_S 97.2 [25] | 95–106 GiB |
Q8_0 123.45 / BF16 232.2 official [21]; MTP-head derivative: `prithivMLmods/Ornith-1.5-122B-MTP-GGUF` (Q3_K_L 60.2 etc.) [28]; vision mmproj-BF16 0.85 GiB [21][24][25]. **Fit**: q4–q5 plausible SOLO on gpu-ai (~75–90 GiB RAM w/ experts-on-CPU); q6 marginal (~105+); q8/BF16 impossible; `gpu` box impossible except exotic IQ2 tier (not requested). 122B GGUF repo last modified **2026-10-21** — re-verify filenames at implementation.

### C) "Ornith 1.5 35B" — exists as `Ornith-1.5-35B-A3B` (MoE, ~3B active)
Official `ornith-ai/Ornith-1.5-35B-A3B-GGUF` (ungated, 3.85 M dl): **Q4_K_M 20.22 / Q5_K_M 23.61 / Q6_K 27.20 / Q8_0 35.21 / BF16 66.19** + mmproj-BF16 0.84, all single-file [22]. No unsloth-org GGUF exists (searched) [26].
bartowski full menu [27]: IQ2_XXS 9.55, IQ2_XS 10.50, IQ2_S 10.70, IQ2_M 11.68, Q2_K 12.19, Q2_K_L 12.65, IQ3_XXS 14.29, Q3_K_S 14.89, Q3_K_M 15.55, IQ3_M 16.18, IQ3_XS 15.54, Q3_K_L 16.16, Q3_K_XL 16.58, IQ4_XS 17.95, IQ4_NL 18.94, Q4_0 19.01, Q4_K_S 19.62, Q4_K_M 20.36, Q4_K_L 20.71, Q4_1 20.91, Q5_K_S 22.94, Q5_K_M 23.74, Q5_K_L 24.03, Q6_K 28.43, Q6_K_L 28.66, Q8_0 35.22, bf16 66.18 (2 shards) + imatrix + mmproj f16/bf16 — "all sensible quants" enumerated; a tidy superset = official 5 + bartowski Q3_K_XL/Q4_K_L/Q5_K_L/Q6_K_L (sane "in-between" ladder) (+ IQ2/Q3 tier for the gpu box).
MTP-preserving builds live in `mudler/Ornith-1.5-35B-A3B-APEX-MTP-GGUF` (449k dl) and SC117/EryriLabs/gbuzhf derivatives [26]; abliterations: dealignai/0xKitkat/mradermacher/huihui [26].
**Fit**: same footprint class as the lab's existing qwen3.6-35b-a3b (20–35 GiB weights, experts-on-CPU trio-eligible on gpu-ai; tuned Q8 fits the 8 GiB gpu box) [17] — by analogy (its expert split not measured here; treat as expected-but-verify).

## 5. Conversion blockers & current-snippet inventory (Q5)

**Inventory (read from the worktree 2026-10-22):**
- `charts/llama-swap/values.yaml` — config `macros` (server-cmd, threads, moe, moe-vl-q4, moe-vl-q8, flash-and-q8, ctx-256k, big-ub, ctx-1m) → base.yaml `macros:` 1:1 (note: `${binary}` must become the llama-server path; server-cmd's `--host 0.0.0.0 --jinja` is already partly in the fixed template).
- Chart `models:` 40 entries (qwen3.8-27b ×4, qwen3.6-27b ×2, coder-next ×2, 35b-a3b ×4, 30b-a3b ×2, qwen3-8b ×2, home ×2, kat-coder ×3, qwen3-vl-2b/4b/8b/30b ×17 incl. thinking variants, whisper-large-v3) — **all `-hf`-based → none generatable stock**; they become declared-half entries (Path A) or fork-driven `hf_models` (Path B). YAML anchor `&vlWorkloadFilters` (`filters.setParamsByID` `${MODEL_ID}:tags/:caption` + auto-aliases) + `aliases: [qwen3-vl-4b,…]` + `description:` + `capabilities:` (present in both: lab sets in/out; tool emits capabilities but **not** filters/aliases/description) [37].
- Chart `matrix:` (41 vars + 1 `main` set incl. `homecpu` co-residency) + gpu-ai `matrix` (`main` trio set + `solo`) + `hooks.on_startup.preload` (qwen3.8-27b-q8, qwen3-embedding-0.6b) → base.yaml passthrough keys [37][5].
- `services/gpu-ai/prod/values.yaml` — extra macros (q38-common/-sampling/-think, q36-common/-sampling) → passthrough; 24 models incl. MTP `-hfd ggml-org/…:mtp-…` refs, `--cache-ram/-np/--spec-type` flags (free-form macro text: representable), the `qwen38-rana` `/bin/sh -c` download-bootstrap (multi-curl exec line) → representable only as declared-side raw `cmd` (no macro/scan equivalent; and its inline `#`-comment constraint is llama-swap-side, unchanged).
- `services/gpu/prod/values.yaml` — tuned `qwen3.6-35b-a3b-q8` cmd override + 6 fail-fast `echo>&2; exit 1` DISABLED entries → declared-side per-cluster values; the tool has **no per-variant cmd-override or disabled-entry concept** beyond `emit_base:false`/pattern swaps — per-cluster Helm merge stays as-is or becomes per-cluster base.yaml.
- `whisper-large-v3`: `.bin` weights + `/bin/sh -c` bootstrap + `checkEndpoint` → invisible to a `*.gguf` scanner [37]; declared-side only.
- **Blockers list**: (1) `-m`-only cmd template [3]; (2) no aliases/filters/description/proxy-env emission [37]; (3) strict dir layout makes `LLAMA_CACHE` unscannable + name-derived IDs would change all model IDs → consumer breakage risk (OpenWebUI, Pictaria, Immich, HA, agent routings) [49][3][17]; (4) `imatrix`/UD-vs-plain quant collisions crash/silently-drop [37]; (5) validator doesn't understand `matrix` (won't reject, just can't cross-check) [37]; (6) `-watch-config` semantics change with generated file in emptyDir (restart-to-reload) [15][17].
- **Non-blockers**: `proxy:` omission (default `http://localhost:${PORT}` is correct for `${PORT}` cmds) [6]; capabilities auto-derivation replaces the hand-set in/out (for scanned files only); `healthCheckTimeout/startPort/globalTTL/unloadTimeout/logLevel/logToStdout/sendLoadingState/includeAliasesInList/apiKeys/performance/captureBuffer` all passthrough-able [37][5][42].

## 6. Integration shapes (Q1 second half) — initContainer vs entrypoint
- **Tool's design favors batch-before-start generation** (docs assume host→container paths [40]) → initContainer matches intent + repo GitOps hygiene (app-template supports `initContainers`; python:3.12-slim already used by the `tools` sidecar pattern [17]). Needs: emptyDir `/app/config`, base.yaml ConfigMap, reloader keyed on the ConfigMap; loses hot-reload of generated half (restart-driven) — acceptable since declared half changes via the same restart.
- Entrypoint wrapper **is technically feasible in the stock image** (runtime ships python3+pip+numpy+sentencepiece, no git [16]; run.sh execs llama-swap only when args are absent — a Helm `command:` override wins [15]): pip-install from a pinned tarball URL or vendor the 12 .py files via ConfigMap; PEP-668 needs `--break-system-packages`/venv. Costs: per-restart startup latency + network at boot; deviates from "image = immutable" hygiene.
- **Self-built `containers/llama-swap-autogen`** fits the repo's container-creation convention (Dockerfile + docker-build.yaml + renovate ARG pin), pinning the tool at a commit SHA (no releases to ride) [8][9]; the alternative that avoids an image entirely: vendored source ConfigMap + python:3.12-slim initContainer.
- OCI availability: none for the tool [13]; PyPI: none [12].

## 7. Open questions (for coord / planner)
1. **gpu-moe target box ambiguity** — DECISIONS.md says validation runs against "gpu-moe" but no `services/gpu-moe` exists; the repo shows `gpu` (Radeon 780M 8 GiB/64 GiB) and `gpu-ai` (125 GiB-RAM box, MCP name `ai-gpu`). Need the human to confirm which box is the test target before chunk planning.
2. Path A vs B (or A-then-B): does the user accept a two-file split (declared half stays hand-written YAML — much of today's authoring pain remains) or is a *maintained fork* acceptable to get true single-DSL declaration? This decides chunk shape entirely.
3. Model-ID continuity: any generated/renamed IDs break consumers — does the plan keep today's IDs as declared aliases (Path A makes this trivial) while adopting the tool's IDs only for new scanned models?
4. Should flash-next q5/q6 (infeasible sizes) be dropped from the roster pre-plan, or declared anyway for a future node? (User approval of final quant list is already a DECISIONS item.)
5. Fork maintenance policy if B: vendor at SHA in `containers/` (repo-immutable) vs runtime git-tarball pip install (needs egress at boot).
6. Whether orcarouter-gated flash-next uncensored belongs to the roster at all (gpu box has no HF_TOKEN).
7. Is `-watch-config` reload on config-dir changes actually exercised for the declared half (ConfigMap-sync ~1 min) — plan should verify reload-vs-identity-conflict behavior on cluster (validation is cheap: `llama-swap -validate`).

## Adjacent (out of core scope, noted)
- The autogen's fit-params VRAM estimation (via `--llama-bin` + caching) is a *planning-time* feature that could produce per-cluster fit reports before enabling the 122B/flash-next roster — cheap win, fits the repo's "measure before enabling" incident history [41][17].
- Renovate: a `containers/llama-swap-autogen` Dockerfile `# renovate:` ARG pin on the tool's commit SHA is the established pattern for git-pinned build sources in this repo (repo convention, not externally sourced).
