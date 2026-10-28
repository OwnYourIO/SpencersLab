# RESEARCH — cf-77-feat-strata-llama-swap (post-plan, 2026-10-27)

Status labels: **measured** = verified against a live registry/API/source this run; **documented** = stated by upstream docs I read; **reported** = stated by a community/PR author; **unconfirmed** = could not verify.

## TL;DR
Upstream is real and fresher than the plan assumed: `ghcr.io/niko1221/strata` carries `0.2.7-rocm-gfx120x` AND `0.2.7-rocm-gfx1151` (released today; 0.2.4–0.2.6 have releases but no container images) → C05 one-image bundling holds. The plan's `strata serve` flag hypothesis is wrong in shape — tuning lives in a **run-config JSON** (`args` + `user_args` + `env`), `serve` itself takes only `--profile/--host/--port/--plan/--output`; but the DECISIONS "one values-driven profile" design maps onto that file directly. llama-swap v266 (deployed, digest re-verified) has everything the peers design needs — peers is a **required `proxy` + `models:` list** route (not a blanket URL proxy), forwards Anthropic `/v1/messages`, rewrites the model name to the inner ID, and streams SSE. The PR #3636 configs are readable: the real R9700-alone recipe uses `--expert-cache auto` with **no `--resident-budget-gib`** and `--conversation-cache-mib 24576` — the plan's "expert-cache 24576" was a misattribution. Net: no architecture change, targeted amendments to C01/C02/C03/C05 (below).

## 1. Upstream image facts (Q1)
- Repo `Niko1221/Strata` exists: 34,505 stars, default branch `main`, pushed 2026-10-27; description "Qwen3.8-Flash-Next on any consumer hardware … OpenAI/Anthropic API on localhost". **measured** [S1]
- Latest release **v0.2.7** (2026-10-27T14:54Z); v0.2.6 (10-25), v0.2.5 (10-25), v0.2.4 (10-24) also exist. **measured** [S1]
- GHCR tag list (28 tags, complete): flavors `cuda13/cuda12/rocm-gfx120x/rocm-gfx110x/rocm-gfx1151/sycl(0.2.3+)/latest-*` exist at **0.2.1, 0.2.2, 0.2.3 and 0.2.7 only — no 0.2.4/0.2.5/0.2.6 images**. `latest-rocm-gfx120x` == `0.2.7-rocm-gfx120x` today. **measured** [S2]
- Digests recorded 2026-10-27 (in-place-rebuild guard, repo law): `0.2.7-rocm-gfx120x` = `sha256:703efd51c040152e9fceb993688b01ca0374535a5bfd86c14a60b5e60c96407a`; `0.2.7-rocm-gfx1151` = `sha256:29ecd5cf8b0e21525dbb5c0191d7743d62fa356da646cb6aaf0546e5a31a8b3f`. **measured** [S2]
- **The `rocm-gfx1151` sibling exists at every release with images, incl. 0.2.7** → C05's two-stage bundle is viable in one image. **measured** [S2]
- What is inside (image config blobs, 9 layers each; gfx120x ≈0.55 GB, gfx1151 ≈0.31 GB compressed):
  - Engine package at `/opt/strata/components/engine/<label>/`; labels today: `0.1.52-linux-x86_64-hip-rx9070` (gfx120x) and `0.1.52-linux-x86_64-hip-halo` (gfx1151) — engine binary version 0.1.52 under Strata 0.2.7. **measured** [S2][S3]
  - Terminal (bundled Python 3.12 + `strata_cli`/`strata_control`/`serve`) at `/opt/strata/terminal/`; `strata` on PATH = wrapper `/usr/local/bin/strata` → `exec /opt/strata/terminal/bin/strata`. **measured** [S3][S4]
  - Entrypoint `tini -- /opt/strata/entrypoint.sh`, `CMD ["run"]`; entrypoint accepts `run` **and `serve`** (same launch path) or any other argv as a command (`docker run IMAGE strata launch --plan …`). **measured** [S3][S5]
  - **ROCm is baked in**: "the engine package carries the ROCm runtime and kernels; the host's amdgpu driver and /dev/kfd are used" — base `ubuntu:24.04`. Env baked: `STRATA_COMPONENTS_DIR`, `STRATA_INSTALL_DIR=/data/install`, `XDG_*` under `/data`, `HOME=/data/home`, `PORT=8080`, `STRATA_IN_DOCKER=1`; (NVIDIA_* vars are leftovers, harmless on hip flavor). `VOLUME /data`, `EXPOSE 8080`, `STOPSIGNAL SIGTERM`, image HEALTHCHECK `/opt/strata/healthcheck.sh` 30s/8s/2h-start. **measured** [S2][S3][S4]
- Runtime requirements (DOCKER.md): `--ulimit memlock=-1:-1`, `--shm-size 2g`, `--stop-timeout 120`, **no container memory limit**, devices `/dev/kfd`+`/dev/dri`, groups video+render; image sizes on disk: gfx120x 2.8 GB, gfx1151 1.5 GB. Do NOT use `strata update` inside the container (engine lives in the image). **documented** [S3]
- Tag semantics: `latest-rocm-gfx120x` is maintained per flavor; DOCKER.md says pin version tags. Renovate note for C01: use `datasource=docker depName=ghcr.io/niko1221/strata` (container tags), not `github-releases` — releases (0.2.4–6) and images (none) are **not** in lockstep. **measured** [S1][S2][S3]

## 2. `strata serve` CLI + profile JSON (Q2)
- `strata serve` exists ("start the existing Strata inference server in the foreground") with **only**: `--profile/--config CONFIG.json` (**required**), `--engine strata|mock`, `--host`, `--port`, `--parallel`, `--batch-groups`, `--max-queue`, `--queue-timeout`, `--batch-telemetry`, `--offline`, `--ready-file`, `--shutdown-timeout` (default **30 s** drain, 0..300), `--plan`, `--output human|json|jsonl`, `--json` (= `--plan --output json`), `--quiet`. **measured (cli.py@main)** [S6]
  - **No engine-tuning flags on `serve`** and **no `--api-key` flag**: the API key comes from the run-config `"api_key"` or env `STRATA_API_KEY`; host gate is `"allowed_hosts"`/`STRATA_ALLOWED_HOSTS`, and any `api_key` disables the Host check. **measured** [S6][S7]
  - `strata serve --plan --output json` exists → the plan's on-target `--plan` gate is valid. [S6]
- **Run config** `strata-<model>.json` (written by setup/launch, read by serve): keys `exe`, `args[]`, `cwd`, `tokenizer`, `model_name`, `log`, `lib_dirs[]`, `port`, `backend`, `env{}`, `parallel`, `gpu[]`, `vision{}`, `host`, `aliases[]`, `fit_max_tokens`; hand-set engine options go in `user_args` (persist across rewrites, person wins per-flag; `args_written` tracks generated). Operator "profiles" (`strata profile`, XDG/`STRATA_PROFILE_DIR`) are a thin layer `{schema_version,id,source_config,overrides}` overriding only host/port/parallel/batch_groups/max_queue/queue_timeout/offline/batch_telemetry. **measured (profiles.py, user_args.py)** [S8][S9]
- Engine flag validity (DETAILS.md "Strata engine and server reference" @main + setup.py@main [S10][S11]):

| flag in plan hypothesis | status |
|---|---|
| `--prefill N` (32768) | valid — used in PR #3636 arena recipe [S12][S10] |
| `--kv-grow` | valid on main; env alias `STRATA_KV_GROW=1`, `--no-kv-grow`; "On HIP it uses virtual memory management (`STRATA_HIP_VMM=0` off-switch)"; needs one GPU + expert profile + whole KV in VRAM + every expert in RAM; pays ≤24 GB cards at ≥128K |
| `--kv int8` | valid, **is the default** (`q4_0`, `k8v4`, `fp16` alternatives) [S10] |
| `--max-context 262144` | valid [S11][S12] |
| `--expert-cache N` / `auto` | valid; **N is slot count ("N times the largest expert blob"), not MiB** — re-read the plan's "#1715 numeric" framing [S10] |
| `--vram-reserve-mib N` | valid; default 700; PR #3636 recommends **2048 only for `--batch 4`** (stall log) [S10][S12] |
| `--resident-budget-gib N` | flag exists ("copies N GiB hottest non-VRAM experts into RAM; **implies `--mmap-experts`**, leaves 4 GiB headroom") — the R9700-alone recipe **omits it** (page-locked arena ≠ mmap mode); it belongs to the Strix fix-class of #1715 [S10][S12][S13] |
| `--spec 4` `--spec-min-p 0.5` `--mtp <dir>` `--mtp-window 8192` | all valid, all in the recipe; `--lookup-chain`/`--lookup-chain-min`/`--mtp-q4` documented (lookup-chain 3 + mtp-q4 all in STRIX_HALO history) [S10][S12] |
| `--prompt-cache-every N` | exists, but only together with `--prompt-cache N` (count); recipe omits both; open issue #4206: *no-op when N ≤ prefill chunk size* — the plan's `--prompt-cache-every 32768` with `--prefill 32768` rides that edge. Drop from v1 [S10][S14] |
| `--conversation-cache-mib/-slots/-min-free-mib` | all valid; mib 24576 + slots 16 are the PR's values; default budget 40% of RAM above `min-free-mib` (2560), cap 8192 MiB, off <1024 [S10] |
| `--host/--port` | on `serve` ✓ (config `"host"`/`"port"` ✓) |
| `--api-key` | ✗ on serve (config `api_key` / env `STRATA_API_KEY`) — also `"api_key": "none"` / `--no-api-key` [S7][S10] |
| `--memory-limit-mib` | documented on main (container-invisible-limit case) — nuance: PR #1601 itself closed unmerged [S10] |

- `STRATA_PREFILL_CPU_SHARE`: **exists, still current**: default off on HIP ("Layer split, batch slots and HIP keep it off unless you set it"); CUDA-only auto scope (one GPU, no `--batch`, chunks <1,024 tokens); changes last bits; PR uses `=auto` env in the one-at-a-time arm. Plan's posture (`auto`, no `--batch`) matches the PR's fastest short-prompt column. **measured (docs + PR envs)** [S10][S12]
- `STRATA_KV_GROW_HOLD`: **not found** — 0 hits in DETAILS.md, AMD_HIP.md, BATCHING.md, serve/server.py, and the PR configs. The documented kv-grow env is `STRATA_KV_GROW=1`. Treat the plan's `KV_GROW_HOLD` as void. **measured (absence)** [S10][S11][S15]
- **nofile self-raise: NOT in any release.** PR #2398 (HIP virtual memory for `--kv-grow`/`--vram-elastic`) closed *unmerged* in the 0.2.0-beta tracker reset; PR #2399 (open, measured today) carries "the raise" as its first commit. PR #3636: at default soft limit 1024 `hipMemCreate` fails at chunk #1,017 (2.0 GiB) with 31.8 GiB free → **`ulimit -n` (the plan's 524288 wrapper = exactly the PR's hard-limit value) remains mandatory for `--kv-grow` on HIP**; release notes 0.2.4–0.2.7 mention no such change. **measured + documented** [S12][S16][S1]
- `strata bench run`: `--suite standard-v1|serving-smoke|parallel-mixed-v1|parallel-overload-v1|parallel-cancel-v1|parallel-prefill-cancel-v1`, source `--profile <config>` or `--url` (remote requires HTTPS), `--load-timeout` default 1800, `--credential-env` default `STRATA_API_KEY`; PR #3636's protocol = "draft protocol `strata-qwen38-thinking-v1-draft.1`" run via `--url http://127.0.0.1:8080 --suite standard-v1 --optional-concurrency --track custom`. **measured (cli.py) + documented (README)** [S17][S12]

## 3. llama-swap / peers facts (Q3)
- Deployed image: `ghcr.io/mostlygeek/llama-swap:unified-vulkan-266` exists; **its digest matches the chart's recorded pin** (`sha256:0cc42f10…00c045`) on 2026-10-27 — no tag drift since 2026-10-25. (Registry `tags/list` enumeration did *not* surface `unified-*`; manifest HEAD is authoritative.) **measured** [S18][S19]
- **`peers:` is in the v266 schema, identical to main except `tailcatKey` (unneeded)**; also present in v240 — i.e. the peers feature the plan rides predates the pin by ≥26 releases. **measured (config-schema.json @v240/v262/v266/main)** [S20][S21]
- Peer entry schema (required: `proxy`, `models`):
  - `proxy`: base URL; **request path is appended verbatim** (`…:8080` + `/v1/chat/completions`). A `/v1` suffix in `proxy` would double-prefix → C03's `http://<svc>…:8080/v1` shape is **wrong**; use `http://gpu-ai-strata.default.svc.cluster.local:8080`. [S21][S22]
  - `models`: **explicit list of the inner's model IDs** — peers is not a blanket proxy. [S21][S22]
  - `apiKey` optional (injected as both `Authorization: Bearer` and `x-api-key`); macro substitution works inside peers values (`apiKey: ${env.X}` in the official example); omitted + inner `apiKeys: []` = exactly the plan's quarantine posture. [S21][S22]
  - `timeouts`: `connect`/`keepalive`/`responseHeader`/`tlsHandshake`/`idleConn` seconds (defaults 30/30/60/10/90). "`responseHeader` is the one to raise for a peer that has to cold-start a model before it responds" → the O2 answer: set outer `timeouts.responseHeader: 1800` (≈ inner `healthCheckTimeout`). [S21][S23]
  - `filters`: `stripParams`/`setParams` per peer (same as models). [S21]
- **Model naming (O1 resolved, no deviation):** peer models are *always* addressable as `<peerID>/<modelID>`; the **unqualified inner ID also routes when exactly one peer serves it and no outer local model/alias shadows it** (local wins). `/v1/models` on the outer lists the **qualified** names. On forward, the outer **rewrites the request-body `model` from the FQ name to the inner's bare ID** (`ReplaceRequestModel`), so the inner instance resolves it as its own model. Clients may therefore ask the outer surface for `qwen3.8-flash-next-strata` *or* `strata/qwen3.8-flash-next-strata`. **measured (internal/router/peer.go) + documented** [S24][S22]
- Anthropic surface: `/v1/messages` and `/v1/messages/count_tokens` are in the shared `modelPostJSONRoutes` dispatch list; peers route "any server providing the `/v1/` endpoints llama-swap supports"; peer hop strips browser `Origin` (Anthropic compat, issue #1214 comment) and rewrites `Host` to the peer URL host. **measured (server.go, peer.go)** [S24][S25]
- SSE: peer proxy sets `X-Accel-Buffering: no` on `text/event-stream` responses; streaming is native ReverseProxy pass-through. Client disconnect cancels the proxy request. **measured** [S24]
- `checkEndpoint`: default `/health`, must return 200; `"none"` skips; non-200 JSON `{"progress":…}` feeds readiness progress and **restarts the healthCheckTimeout countdown** on change. Strata's `/health` "answers only once the model is loaded" (upstream integration doc) and answers without a key (DOCKER.md) → inner `checkEndpoint: /health` **valid** (C02's VERIFY resolves YES); `healthCheckTimeout: 1800` fits (upstream example uses 300; PR's arena read is 46.84 GiB @17.3 GiB/s). [S25][S26][S3][S10]
- `unloadTimeout`: global default **10 s**; per-model `0` = use global; it is the window llama-swap waits for the process to exit **before force-kill** on *any* unload (TTL, manual, swap). For a page-locked ~47 GiB arena (docker guidance: 120 s stop) set a generous per-model `unloadTimeout` (≥180, runbook-verified), keeping `terminationGracePeriodSeconds: 420 > unloadTimeout`. Peer side is irrelevant (llama-swap never manages a peer's lifecycle). [S27][S23][S3][S22]
- `hooks.on_startup.preload` exists in v266 schema (`preload: [model IDs]` + `profile`); ttl-tristate confirmed (`-1` inherit / `0` never / `>0` idle-secs; timer resets on every request); manual escape `POST /api/models/unload/:id` (also `/unload` all) documented. `globalTTL: 0` + `ttl: 0` posture = fine; doc warning: preloading several models needs a matrix/group that admits them — our C05 `(p|s)` alternatives would swap if both were preloaded, so keep preload empty (plan's lazy posture confirmed). Caveat found: peers models are **not** reachable via `/upstream/<model>` passthrough (probes must stay on llama-swap's own `/health` — the plan already decided this). [S27][S28][S22][S23]

## 4. IQ3_S quant facts (Q4)
- HF: `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` (1,066 likes, 7.3 M downloads; last touch 2026-09-29). `IQ3_S/` = **two shards: 54,817,524,224 B + 28,800,138,432 B = 83.62 GB on disk** (sha256 + revision `ed59f920…` recorded in the repo's own `model-manifest.json`, matching PR #3636's pinned commit). Shard 00002 is the PLE file (`--ple-gguf`). [S29][S30][S12]
- MODELS.md: IQ3_S "RAM + VRAM for the model" = **54.8 GB** (working set, not disk), "best; matches the full model on the published tests". Ordering Q2_0 37.6 < IQ2_XS 39.2 < IQ3_XXS 47.0 < IQ3_S 54.8. [S14]
- Prepared **pack** (`/data/Strata-data/packs/iq3_s`) + MTP draft layer (`mtp/rt`, ~6 GB) + optional vision `mmproj-Qwen3.8-Flash-Next-BF16.gguf` (~0.9 GB) sit on top of the 83.6 GB GGUFs. Pack size for IQ3_S is **unconfirmed** (DOCKER.md names ~40 GB for IQ3_XXS); budget the `/models/strata/` area ≈ 135–160 GB — the shared 500 Gi claim has room. [S3][S12][S14]
- Alternate: `unsloth/Qwen3.8-Flash-Next-GGUF` `UD-IQ4_XS` = 3 shards, **93.68 GB on disk**; MODELS.md: Unsloth 4–8 bit need **72–136 GB** for all experts in RAM. [S29][S14]

## 5. PR #3636 fork configs (Q5)
Readable at `jiayeZhu/Strata@bench-strix-halo-r9700-022` (PR open, base main, 84 files, `bench/results/2026-10-21-community-strix-halo-r9700-oculink-0.2.2/`). Exact R9700-alone arena config (`r9700-arena-pf32k.json`): **measured** [S12]
```
--pack packs/iq3_s --native …IQ3_S-00001-of-00002.gguf --ple-gguf …00002…
--expert-profile data/expert-profile.bin
--expert-cache auto          ← NOT 24576
--spec 4 --spec-min-p 0.5 --mtp mtp/rt
--max-context 262144 --kv int8 --kv-resident 32768 --mtp-window 8192 --prefill 32768
--conversation-cache-mib 24576 --conversation-cache-slots 16   ← "24576" lives HERE
--batch-mtp --vision
env: STRATA_PF_FUSED=1 STRATA_PF_GEMM=1 STRATA_PA_FAST=1 STRATA_HIP_WMMA=1 STRATA_SELECT_WMMA=1 ROCR_VISIBLE_DEVICES=0
parallel: 4  gpu: [0]  host: 0.0.0.0  aliases: ["qwen3.8-flash-next"]  backend: hip  lib_dirs: <TheRock multiarch>/…
(no --resident-budget-gib anywhere; no --prompt-cache*)
```
- "one at a time" arm (the plan's chosen posture): same minus `--batch`/`--kv-resident`, plus `STRATA_PREFILL_CPU_SHARE=auto`, optional `--kv-grow` (needs raised ulimit; +13% experts in VRAM, +2–3% @64K).
- Measured headline (README summary tables): 64K/128K/200K prompt 2,519 tok/s-ish, decode 80 (one-at-a-time, 64K); short 570-tok prompts 429–443 tok/s with the CPU share vs 224 control; `--batch 4` stall incident at default reserve after 85 min (basis for the plan rejecting batch v1). All **reported** (single machine) [S12].
- Split mode (deferred) config exists (`split-0.2.2.json`, `--mmap-experts --prefill 4096 --no-prefill-borrow --trim-stage-weights --batch 4 --batch-groups 1`, gfx1151 table, `STRATA_HC_UPMIX` off per #2706). [S12]

## 6. TheRock 7.14.1 / hipBLASLt (Q6, escalation-path only)
- `https://repo.amd.com/rocm/tarball-multi-arch/` serves: **`therock-dist-linux-gfx120X-all-7.14.1.tar.gz` — exists, HTTP 200, Content-Length 2.336 GB** (`-tests-` variant too); `therock-dist-linux-gfx1151-7.14.1.tar.gz` 1.713 GB (docs say "1.7 GB, sha256 `c40e8f2bd6630a7d…4afb00`" [S31]). **No sha256 sidecars in the listing; no published sha for the gfx120X file** — an operator download must record it. **measured** [S32][S18b]
- Repo ships `tools/hip/gfx1201-hipblaslt-100202.txt` and `gfx1201-hipblaslt-100500.txt`, and `gfx1151-…-100401.txt` etc. The engine accepts a table only for the arch+hipBLASLt version on its second line (`STRATA_HIPBLASLT_TUNING_V1 gfx1151 100401` = ROCm 7.14.1). → **No gfx1201 tuning table for 7.14.1/100401** in-tree: a 2B source build against 7.14.1 would run plain-hipBLAS dense prompt matmuls (or must generate its own with `tools/hip/tune_hipblaslt.cpp`). The packaged 0.2.7 image is self-sufficient ("a packaged engine finds its table itself"). PR #3636 ran gfx1201 on TheRock 7.14.1 + hipBLASLt 1.4.1 fine without a 1201 table. **measured (file lists) + reported** [S33][S31][S12]

## 7. gfx1151 §5 fast-config for C05 (Q7)
Current `docs/STRIX_HALO.md` §5 "What is not on by default (it changes bits)" — maintainers' fast config sets all eight: **measured (verbatim)** [S31]
```
STRATA_PF_FUSED=1  STRATA_PF_GEMM=1  STRATA_HC_UPMIX=1  STRATA_PA_FAST=1
STRATA_HIP_WMMA=1  STRATA_SELECT_WMMA=1
STRATA_PF_SWITCH_MIN_T=4096  STRATA_PREFILL_STREAM_MIN=128
```
(+`STRATA_PF_FUSED_KQ=1` only for K-quant packs; `STRATA_PF_F16` gfx11-only; `--mtp-window 8192`, `--spec/--lookup-chain/--mtp-q4` cross-refs. §4 lists what gfx1151 auto-enables — incl. `STRATA_SH_STREAM=1` on Linux; `STRATA_GFX1151_DEFAULTS=0` disables. §5: KL-gated, rounds differently — matches the plan's caveat. HC_UPMIX was a hazard on 0.2.2 split (#2706) — §5 still lists it; on-target log check.)
- The plan's strix numbers "1,265/59.1 @8K, 1,310/42.1 @128K" = the STRIX_HALO **History** "merged 0.1.40, no env switches" IQ3_S row — exact match, but it is **engine-0.1.40-era** (current 0.1.52; §6 0.2.3 Windows row: 685/783/749 prompt @4K/8K/64K). [S31]
- "expert-cache 24576 / resident-budget 55 (guide §7)": **unconfirmed upstream** — no source carries this pair. Context: #1715 (closed) is `[Strix Halo, 128 GB] setup's --expert-cache auto (no --resident-budget-gib) causes a global OOM` — the fix-class (explicit expert-cache and/or resident-budget) is right; the values read as card-guide-derived (24576 also equals the model's **total expert count** per PR #3636, which may be where the "expert-cache 24576" story came from). Keep them in `strixProfile` as VERIFY-marked hypotheses; on-target gate = `strata serve --plan --output json` + startup log lines (arena sizing, table load). [S13][S12][S31]
- Second-engine-beside-first visibility: PR hides the 8060S with `ROCR_VISIBLE_DEVICES=0` when the R9700-alone engine runs (chip becomes index-invalid); §5b: on a Halo+discrete pair the discrete card is the recommended Main, chip stays Off in roles; `setup --gpus all` excludes the chip when two own cards exist; "name it by number" (`--gpus`, config `"gpu": [0]`, `STRATA_ROCM_INDEX` env exists in setup.py). With both engine builds bundled in one image, ROCR indices come from the host at runtime → the chart's values-configurable `rocrVisibleDevices` + on-target `rocminfo` gate stays exactly right. [S31][S12][S11]

## Contradictions and how to weigh them
1. **Plan "line 0.2.5/0.2.6" vs measured 0.2.7** — registry/GitHub API win; the plan was right that releases 0.2.4–6 exist, wrong that images track them. Pin `0.2.7-*` (releases fast: v0.2.6 was 2 days ago; expect 0.2.8 — the renovate docker datasource handles drift).
2. **O1 "peers = blanket URL proxy, inner owns IDs" vs schema `required: [proxy, models]`** — the schema/source win, but the *outcome* the plan wanted survives: the outer forwards the bare inner ID, unqualified names route with a single provider, so the inner still owns resolution. Config shape must change.
3. **Guide "expert-cache 24576" vs PR `--expert-cache auto` + `--conversation-cache-mib 24576`** — the fork's own configs are the primary source: the plan's C02 numeric-expert-cache framing and C05's "guide §7 measured" pair are misattributions. The `--resident-budget-gib` in C02's primary profile would switch the engine to `--mmap-experts` mode — the opposite of the page-locked arena the architecture is built on. Remove it from the primary; keep (VERIFY-marked) for strix.
4. **DOCKER.md 120 s stop vs plan 420 s grace vs llama-swap 10 s default unloadTimeout** — all coexist, but the *binding* constraint nobody had yet: llama-swap force-kills at `unloadTimeout` (10 s default) long before kubelet's 420 s matters. The per-model `unloadTimeout` is load-bearing; set it explicitly (C02 currently only implies it via grace sizing).
5. **#2398/#2399 = the "nofile" pair the plan guessed** — actually correct attribution (PR #3636 says it in terms: #2398 found the fd ceiling, died in the tracker reset; its raise is the first commit of open #2399). Conclusion: no engine self-raise in 0.2.7; wrapper `ulimit -n 524288` stays.
6. **#3421** (run engine without the wrapper) was closed-then-discussed today: maintainer fixed only the silent re-download ("fails loudly in 0.2.7"); wrapperless engine-as-child "is a larger design, we keep this issue open". Upstream's own `docs/LLAMA_SWAP.md` documents the direct-`serve` integration anyway; our cmd uses the documented `serve` CLI, not the container entrypoint — but cite #3421 in the Dockerfile README as the reason we pin exact digests and re-verify on upgrades.
7. **`strata serve` exists as a CLI but DOCKER.md's documented container path is the `run` entrypoint** — for supervised-in-llama-swap use, the CLI `serve` + run-config is the documented integration surface (`docs/LLAMA_SWAP.md`); the docker docs assume single-model one-click use. Registry inspection confirms the terminal is inside the image, so `/opt/strata/terminal/bin/strata serve --profile …` is available in the container. [S6][S3][S15]

## Implications for the plan (concrete amendments; architecture unchanged)
- **C01**: pin `0.2.7-rocm-gfx120x` + `0.2.7-rocm-gfx1151` (record both digests above; `# VERIFY(research)` markers retire). Renovate comment: `datasource=docker depName=ghcr.io/niko1221/strata` (container tags lag releases — a `github-releases` depName would propose pins with no image). Bundle plan valid: each image = 9 layers; copy `/opt/strata/components` (two distinct engine roots) + `/opt/strata/terminal` once; root-user base posture unchanged. Interface contract update: the engine binary lives under `…/components/engine/<label>/` (exact filename to be read from the stage at C01 build time — the image's own verify step checks `strata*` files there; source-build configs name it `strata`), referenced **from the profile `exe`**, not cmd; the serve entry is `/opt/strata/terminal/bin/strata`.
- **C02**: cmd becomes `bash -c 'ulimit -n 524288; exec /opt/strata/terminal/bin/strata serve --profile /profile/<x>.json --host 127.0.0.1 --port ${PORT}'` (SanitizeCommand-safe). `config.engineProfile` renders the **run-config JSON** (`exe`, `args[]`, `env{}`, `tokenizer`, `model_name`, `lib_dirs`, `port`-less (llama-swap owns it via `${PORT}`→`--port`), `backend: hip`), modeled 1:1 on the PR's `r9700-arena-pf32k.json` minus `--resident-budget-gib`, minus `--prompt-cache-every`; add per-model `unloadTimeout` (≥180, VERIFY); `checkEndpoint: /health` marker resolves valid; keep `healthCheckTimeout: 1800`, `globalTTL: 0`, `ttl: 0`, `apiKeys: []`; drop `STRATA_KV_GROW_HOLD` from the env list; keep `STRATA_PREFILL_CPU_SHARE=auto`; `--api-key` is not a serve flag — key via env `STRATA_API_KEY` (config `"api_key"` alternative also disables Strata's Host check, which is moot behind llama-swap since the peer hop rewrites Host and inner→strata is 127.0.0.1); vision default off (recipe ran it on; mmproj adds ~0.9 GB).
- **C03**: peers entry shape finalizes:
  ```yaml
  peers:
    strata:
      proxy: http://<rendered-svc>:8080      # NO /v1 suffix
      models: [qwen3.8-flash-next-strata]    # C05 adds …-strix to this list
      timeouts: {responseHeader: 1800, connect: 30}
  ```
  O1 closes with no deviation (unqualified IDs reach the peer; FQ listed by `/v1/models`). C03's "matrix ignores peers" note stays true (peers are not outer `models:` entries; selectors/spillover optional later).
- **C05**: strix profile = PR's five env vars **plus** `STRATA_HC_UPMIX=1` + `STRATA_PF_SWITCH_MIN_T=4096` + `STRATA_PREFILL_STREAM_MIN=128` (the §5 eight-set) with log-gate for #2706; keep `--expert-cache` explicit-numeric + `--resident-budget-gib` per the #1715 fix-class (values VERIFY: 24576/55 unconfirmed upstream); `--mtp-window 8192 --spec 4 --spec-min-p 0.5 --prefill 16384` class per the STRIX_HALO history recipe; expected-perf text should cite History (engine-0.1.40-era) vs current 0.1.52; `rocrVisibleDevices` values-key stays (unset on strix-alone).
- **Runbook (C04)**: on-target gates now name exact commands — `strata serve --profile X.json --plan --output json`; startup lines to look for (`hipBLASLt tuning enabled (…gfx1151…100401)`, nice +5, expert-cache sizing, memory-guard source); `unloadTimeout` verification (timed manual unload via `POST /api/models/unload/:id` against the inner instance); the PR's `--kv-grow` fd experiment; `strata bench run --url … --suite standard-v1` for the acceptance protocol; k3s `LimitNOFILE` justification cites #2399-open.
- **Validation (plan "Commands")**: config-schema validation target is now `https://raw.githubusercontent.com/mostlygeek/llama-swap/v266/config-schema.json` (match the deployed pin, not main — `helpagent` exists only on main and could false-fail/flag a v266-invalid key).

## Reliability notes
High confidence (8–9/10) on Q1/Q3/Q5/Q6/Q7 — direct registry/source/API measurements. Q2 medium-high (8): docs+source are current-main, but the engine binary itself is closed-component here (a packaged-engine `--help` on-target closes the residual). Q4 (8): sizes measured; IQ3_S pack size unconfirmed. The perf numbers are single-machine reported data from 2026-10-21 — the plan already gates reproduction on-target. Weakest claim: "0.2.7 has no nofile self-raise" — inferred from open #2399 + release-note silence, not from a 0.2.7 binary inspection; the wrapper makes it harmless either way.

## Open questions (for coord / one batched human round)
1. Do the card-guide's strix values `expert-cache 24576 / resident-budget 55` have a source the operator holds (guide §7 itself)? Upstream carries no such pair — otherwise they ship as VERIFY-marked hypotheses.
2. Vision on or off in v1? The PR recipe ran `--vision` (CPU encoder, mmproj ~0.9 GB on disk); the plan never ruled. Cheap decision: off for v1.
3. Confirm the gpu-ai node's RAM figure for the arena math (PR machine: 124 GiB; plan request `memory: 96Gi` assumes ~125 — if the node is 128, conv-cache 24 GiB + arena 47 GiB + KV/pack page-cache headroom needs the pre-sync check the runbook already lists).
4. `--kv-grow` in v1 or defer? Documented benefit is +2–3% at 64K only, at the price of the fd-raise dependency; the plan lists it unconditionally — acceptable, but worth an explicit operator nod.

## Sources
- [S1] api.github.com `repos/Niko1221/Strata` + `/releases` — measured 2026-10-27.
- [S2] ghcr.io registry API `token` + `tags/list` + manifest/config blobs for `0.2.7-rocm-gfx120x`/`0.2.7-rocm-gfx1151` — measured 2026-10-27 (digests above).
- [S3] Niko1221/Strata `docs/DOCKER.md` @main — fetched full.
- [S4] `docker/Dockerfile` @main — fetched.
- [S5] `docker/entrypoint.sh` + `docker/strata-wrapper.sh` @main — fetched full.
- [S6] `strata_cli/cli.py` @main — `serve`/`bench` parser blocks — measured.
- [S7] DETAILS.md "Network access" section — fetched.
- [S8] `strata_control/profiles.py` @main — measured.
- [S9] `strata_control/user_args.py` @main — fetched full.
- [S10] `docs/DETAILS.md` @main (153 KB; sections: KV cache, Conversation cache, Memory modes, Config keys, Network access) — fetched.
- [S11] `setup.py` @main — flag/env name extraction (`--resident-budget-gib`, `STRATA_ROCM_INDEX`, …) — measured.
- [S12] `jiayeZhu/Strata@bench-strix-halo-r9700-022` `bench/results/2026-10-21-community-strix-halo-r9700-oculink-0.2.2/` README.md + `configs/r9700-arena-pf32k.json`, `r9700-one-kvgrow*.json`, `r9700-one-pf32k-cpushare.json`, `r9700-arena-pfauto.json` + PR meta (`/pulls/3636`, `/files`) — fetched.
- [S13] Strata issue #1715 (title/state via issues API).
- [S14] `docs/MODELS.md` @main — fetched (quant tables + HF links).
- [S15] `serve/server.py` @main — token counts (api_key/allowed_hosts; KV_GROW_HOLD/PREFILL_CPU_SHARE absent) — measured absence.
- [S16] Strata PRs #2398 (closed unmerged) / #2399 (open) / #3421 (comments, maintainer close note 2026-10-27) — issues API.
- [S17] `strata_cli/cli.py` bench block (suites list) — measured.
- [S18] `ghcr.io/mostlygeek/llama-swap` manifests (unified-vulkan-266 digest; v266/latest 404 vs v-tag absence note; `cpu` present) — measured.
- [S18b] HEAD `repo.amd.com/rocm/tarball-multi-arch/therock-dist-linux-gfx120X-all-7.14.1.tar.gz` + gfx1151 — measured 2026-10-27.
- [S19] repo: `charts/llama-swap/values.yaml` L895-954 (pin + recorded digest comment), `renovate.json` L246-253, `charts/llama-swap/Chart.yaml`.
- [S20] `config-schema.json` @tags v240/v250/v260/v262/v266 + main — peers sections — measured.
- [S21] `config-schema.json` @v266 — peers required fields + timeouts defaults — measured.
- [S22] llama-swap `docs/kb/examples/peers-and-multi-host.md` @main — fetched.
- [S23] llama-swap `docs/kb/guides/connectivity/remote-peers.md` + `proxy-timeouts` config_keys (via remote-peers) — fetched.
- [S24] llama-swap `internal/router/peer.go` @main — fetched (ReplaceRequestModel, X-Accel-Buffering, Host rewrite, Origin strip).
- [S25] llama-swap `internal/server/server.go` @main — `modelPostJSONRoutes` incl. `/v1/messages` — measured.
- [S26] Strata `docs/LLAMA_SWAP.md` @main — fetched full (healthCheckTimeout 300 example, checkEndpoint /health, exec, allowed-hosts, /upstream, load-time history).
- [S27] llama-swap `docs/kb/guides/model-runtime/ttl-and-unloading.md` @main — fetched.
- [S28] llama-swap `docs/kb/guides/operations/startup-preloading-and-hooks.md` @main — fetched.
- [S29] `huggingface.co/api/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF(/tree/main/IQ3_S)` + `unsloth/Qwen3.8-Flash-Next-GGUF` — measured.
- [S30] Strata `bench/results/2026-10-08-community-r9700-linux/model-manifest.json` @main (sizes+sha256+revision).
- [S31] Strata `docs/STRIX_HALO.md` @main — §§1–6 + History — fetched.
- [S32] repo.amd.com tarball directory (embedded JSON manifest) + HEAD sizes.
- [S33] Strata git tree `tools/hip/*` listing (per-arch hipBLASLt tables) + STRIX_HALO §3 table format.
