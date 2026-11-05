# vllm-rocm — vLLM + GGUF plugin overlay for the R9700 (cf-105 C01)

A thin overlay over the upstream `vllm/vllm-openai-rocm:v0.33.0-rocm100`
image: it adds the OOT `vllm-gguf-plugin` (GGUF weight loading — the only
32 GiB weight path that fits the D4 envelope) and the R1 recipe env pins,
and nothing else. The base's `ENTRYPOINT ["vllm", "serve"]`, `WORKDIR /app`
and all other runtime behavior are inherited unchanged; C02 (`charts/vllm`)
appends the serve args.

The build is CI-primary: `docker-build.yaml` triggers on `containers/**`
and pushes `:v<run>` (immutable) + `:main` (rolling) on merge. There is no
docker daemon in agent sessions, so the build-critical base facts below
were captured from the Docker Hub registry API (tags endpoint + manifest +
image config) and the upstream `docker/Dockerfile.rocm` at the pinned tag
— not by pulling the image.

## Tag -> digest ledger (manual)

| What | Pin | Digest / SHA | Verified (probed 2026-11-05) |
|---|---|---|---|
| Base image | `vllm/vllm-openai-rocm:v0.33.0-rocm100` | `sha256:4fcd39b758b660c4e9c345c021e2ea8f0ccdb31e3c32507d676cc3005ae83fba` | Docker Hub tags API: `full_size` 18,038,402,058 B, `tag_last_pushed` 2026-11-02T02:45:27Z, amd64/linux |
| Plugin | git ref `e454affe0ca23c9dc8754ec3033270cb30622ed5` (main, 2026-10-24, "[BugFix] Flatten batched inputs in the GGUF linear method (#149)") | git commit SHA, not a registry digest | GitHub commits API: exists, committed 2026-10-24T03:46:01Z; `weights_adapter/qwen3_5.py` (PR #98's adapter) fetched at the ref |
| Import-compat patch | `carry/qwen35-import-compat.patch` | file in this dir | generated as a real diff against the ref; `git apply` + `git apply --check --reverse` clean locally |

### Why the plugin is a git ref, not a PyPI release

No release carries the Qwen3.5 GGUF adapter: the newest release is v0.0.5
(2026-08-10), which predates PR #98 ("[Models] support Qwen3.5/3.6
multimodal GGUF and MTP", merged to main 2026-08-18) — so the plugin is
pinned to a full commit SHA on main (the ARG in the Dockerfile) and no
release pin of it exists in this dir. Plugin main at that SHA is also
import-broken against the pinned base as-is (the patch below is why).
Watch for a release containing PR #98 + the import fix (v0.0.6?); when one
ships, point the ARG at it, drop the carry, and re-record this ledger.

### The import-compat patch (drop condition)

`carry/qwen35-import-compat.patch` (2 lines): the plugin's main-only
`weights_adapter/qwen3_5.py` imports the Qwen3.5 configs from
`vllm.transformers_utils.configs.{qwen3_5,qwen3_5_moe}` — vendored modules
vLLM removed in #60623 (2026-10-09, "Remove vendored code made redundant
by Transformers 5.16.1"), absent from v0.33.0 (raw-404 verified at the
tag). The patch redirects those two imports to `transformers`, where vLLM
v0.33.0's own `models/qwen3_5.py` imports the same configs. A tree-wide
grep of the ref confirmed no other plugin file touches the removed module,
so the carry is exactly these two lines.

**Drop condition:** a plugin release (v0.0.6?) or a main ref carrying the
upstream import fix — point the ARG at it, delete the carry file, and
re-record this ledger in the same bump (RESEARCH Post Research open
question 2). Until then the C06 step-3 import probe
(`python -c "import vllm_gguf_plugin"` + GGUF serve + first token) is the
functional acceptance.

## Manual-bump procedure (no auto-update for the image pins)

By contract this dir carries **zero auto-update directives for the image
pins** — the ledger above is manual and the CI build is the authority. The
ONE sanctioned machine-readable directive in this dir is the plugin ARG's
`git-refs` comment (repo convention, `containers/gpt-researcher`
precedent); it proposes the SHA bump as a PR, which a human merges.

Bumping either pin is a three-step procedure:

1. **Base image** — re-verify the digest, then edit the FROM tag, the
   Dockerfile ledger comment, and the table row above:

   ```sh
   curl -s https://hub.docker.com/v2/repositories/vllm/vllm-openai-rocm/tags/v0.33.0-rocm100
   ```

   The `digest` field is the ledger value (`sha256:4fcd39b7…83fba` as
   probed 2026-11-05); note `full_size` and `tag_last_pushed` alongside it.
2. **Plugin ref** — re-resolve the ref (a release containing PR #98 + the
   import fix, else a newer main SHA): fetch
   `https://api.github.com/repos/vllm-project/vllm-gguf-plugin/commits/<sha>`
   (exists + date + message) and
   `https://raw.githubusercontent.com/vllm-project/vllm-gguf-plugin/<sha>/vllm_gguf_plugin/weights_adapter/qwen3_5.py`
   (adapter present, import lines located). If the carry patch's context
   moved, regenerate it against the new ref — a context mismatch fails the
   build, by design.
3. **Re-bench on target** — the C06 runbook acceptance (patched-plugin
   import probe + GGUF serve + first token, then the D4 benchmark) before
   the bump is considered done.

## Base-image facts (pinned image registry data, probed 2026-11-05)

- manifest (the ledger digest): 41 layers, ~16.8 GiB uncompressed,
  amd64/linux, Ubuntu 22.04
- image config: `User: null` (the base runs as root — the overlay creates
  the uid-65532 user), `Entrypoint: ["vllm", "serve"]`, `Cmd: null`,
  `WorkingDir: /app`, no `ExposedPorts` (this overlay adds `EXPOSE 8000`),
  no healthcheck (kubelet probes are the chart's job)
- python 3.12 at `/usr/local/lib/python3.12/dist-packages` (the image's own
  `SITE_PACKAGES` env var — the Dockerfile applies the carry patch there),
  `pip` and `git` present in the image (git is a base-image fact: every
  stage of the upstream `docker/Dockerfile.rocm` clones from it without
  installing it)
- `PYTORCH_ROCM_ARCH` includes gfx1201+gfx1151 (the R1-verified chip
  class); `AITER_ROCM_ARCH=gfx942;gfx950` — the AITER prebuilds are
  CDNA-only, hence the baked `VLLM_ROCM_USE_AITER=0`
- the base's own `docker/Dockerfile.rocm` (fetched at tag v0.33.0) ends in
  `ENTRYPOINT ["vllm", "serve"]` over the `rocm/vllm-dev:base` (TheRock)
  stage; its plugin-wheel build path uses the system python env, which is
  why the overlay's `--no-build-isolation` install reuses the image's ROCm
  torch + hipcc instead of letting pip fetch a CUDA torch

## Interface contract (what C02 builds against)

- **Port 8000** — serve = metrics = health on one port (R5 Q1); the chart
  probes `/health` on it and scrapes `/metrics` from it
- **`ROCR_VISIBLE_DEVICES`** — chip targeting (device index or UUID under
  ROCm 10, RESEARCH V2); the chart supplies the value (default `"0"` =
  R9700), never this image
- **`/data`** — cache mount point (the C02 cache PVC): `TRITON_CACHE_DIR`
  and `HUGGINGFACE_HUB_CACHE` are baked under it by this image
- **Non-root** — uid 65532 (`USER 65532` in the Dockerfile; the base had
  no user). GPU access is group-mediated: the chart adds `runAsGroup: 44`
  (video) + `SYS_PTRACE` + `seccomp Unconfined`, the upstream
  k8s-device-plugin vllm-serve pod shape (RESEARCH V2 [153])
- **Entrypoint** — inherited `["vllm", "serve"]`; the chart appends the
  serve args (the D4 recipe)
- The GGUF weights are NOT in this image — they come from the chart's
  read-only `/models` mount (the existing 500 GiB PVC, RESEARCH V3)

## Provenance

- cf-105 C01 — plan `2026-11-04-feat-cf-105-feat-implement-vllm.md`
- RESEARCH Post Research V1 (plugin pin + patch mechanics), V2 (chip
  env), V3 (weights on the PVC), R1 §3 (the GGUF envelope), R5 Q1
  (the single port)
