# Perspective: Container/GitOps integration engineer (packaging + runtime mechanics)

## Packaging facts (all retrieved 2026-10-22)
- GitHub repo `shirayu/llama_swap_config_autogen`: created 2025-09-15, pushed
  2026-10-22T01:31Z (same day as this research) — actively developed.
  1 star, 0 forks, 0 open issues. Language Python, Apache-2.0.
  (https://api.github.com/repos/shirayu/llama_swap_config_autogen)
- **No GitHub releases and no tags** (both API endpoints return `[]`).
  Pinning must use commit SHAs.
- **Not on PyPI**: https://pypi.org/pypi/llama-swap-config-autogen/json 404.
  README install is `pip install 'git+https://github.com/shirayu/llama_swap_config_autogen'`
  or `uv tool install` of the same. A tarball URL (`.../archive/<sha>.tar.gz`)
  is pip-installable without git (verified: the archive tarball fetch worked).
- **No container image** for the tool: `.github/workflows/` contains only
  `ci.yml` (uv/mise lint+test; no publish job). No `homepage`/packages.
- Issue tracker: the 11 items in `/issues?state=all` are ALL dependabot PRs,
  every one closed — zero human issues ever filed. No feature request exists
  for HF/remote/declarative models; nothing to upstream-piggyback on.
  (https://api.github.com/repos/shirayu/llama_swap_config_autogen/issues?state=all)
- Maintainer: `shirayu` = Yuta Hayashibe (https://hayashibe.jp), GitHub account
  since 2011, 143 public repos, 114 followers. pyproject author email
  yuta@hayashibe.jp. Single author on every recent commit sampled
  ("Fix", "Updated mise.toml", "add saihai", "Support llama.cpp decision models
  in capabilities" ...). Bus-factor = 1, but velocity is real and the repo is
  dependency-hygenic (SHA-pinned actions, mise.lock, uv.lock).

## Runtime requirements for integration
- Python >=3.10; deps PyYAML, gguf, pydantic v2, jsonschema. No compiled
  deps beyond what `gguf` pulls (gguf is pure python; fine on vulkan image).
  Generation is offline/local-only (dir scan + GGUF header reads); VRAM
  estimation optionally shells out to a `fit-params`-capable binary (any
  shlex-able command, docs/vram-estimation.md).
- fit-params/GGUF caches are written under `~/.cache/llama_swap_config_autogen/`
  — an initContainer needs a writable HOME (or emptyDir) or caching is just lost
  every run (acceptable; estimation off by default).

## Where the generator can physically run vs the lab's current image
- The lab's main container is `ghcr.io/mostlygeek/llama-swap:unified-vulkan-262`.
  Its runtime stage installs `python3`, `python3-pip`, `python3-numpy`,
  `python3-sentencepiece`, `curl`, `ca-certificates`
  (docker/unified/runtime.Dockerfile at v262) — but NOT `git`, and Ubuntu 24.04
  python3 is PEP-668 externally-managed (pip needs --break-system-packages or a
  venv). So an entrypoint-wrapper inside the stock image is possible
  (pip install from a tarball URL at pod start, or vendor the ~12 small .py
  files into a ConfigMap and run `python3 -m ...` with PYTHONPATH) — but it
  mutates the stock image's startup (custom command overriding run.sh, or a
  derived container per repo convention in containers/).
- An initContainer on the bjw-s app-template shape is natively supported:
  `app-template.controllers.llama-swap.initContainers.<name>` is the chart's
  own vocabulary; the generator image would be python:3.12-slim (already used
  by the repo for the `tools` sidecar, charts/llama-swap/values.yaml) + pip
  install from a pinned tarball at image build (a `containers/llama-swap-autogen`
  built by docker-build.yaml → `:v<run>` + `:main` tags fits the repo's
  container-creation convention; or pip-installed at initContainer startup from
  the tarball URL).
- Volume math for initContainer shape: the config dir is currently a readOnly
  ConfigMap mount at /app/config (charts/llama-swap/values.yaml persistence
  note). Generated config must land in a WRITABLE emptyDir (e.g. /app/config)
  mounted into both init and main containers; the chart's existing
  `reloader.stakater.com/auto: "true"` ConfigMap-reload trick becomes moot for
  the generated half — the pod restarts on base.yaml ConfigMap change (reloader
  still works: base.yaml is the ConfigMap; emptyDir regenerates on every start).
  llama-swap -watch-config on an emptyDir file only reacts to writes inside the
  pod, not to upstream ConfigMap edits — hot-reload semantics CHANGE: base.yaml
  edits require pod restart (reloader provides that).

## initContainer vs entrypoint wrapper — what the tool favors
- The tool is designed as a batch CLI (generate → file), no watch mode, and its
  own docs (docs/containerized-setup.md) assume "run generator wherever, mount
  the OUTPUT into the container" — i.e. generation happens BEFORE llama-swap
  starts, from outside. initContainer matches the tool's design intent exactly;
  entrypoint-wrapping only buys "regenerate without pod restart", which
  llama-swap can't hot-reload into anyway for the scanned half (new files
  appear via -hf downloads, but the whole point is declared models don't need
  scanning).
- Counter-consideration: an entrypoint wrapper inside the llama-swap pod means
  one less container image and same-PATH `llama-server` for `--llama-bin`
  VRAM estimation (run.sh maps LLAMA_SWAP_* only; overriding command on the
  app-template container is normal). But it breaks "never hand-edit
  ghcr images" cleanliness and adds startup latency to every restart; and
  ArgoCD's config-reload path (directory-mounted ConfigMap with subPath caveat)
  is already tuned in this chart — a wrapper keeps that mount model intact
  only if it writes OUTSIDE the ConfigMap mount and points LLAMA_SWAP_CONFIG
  at the generated file.

## Risk register (for the plan)
- 1-star/0-fork/0-issue single-author tool, no releases: pin a commit SHA in
  the container build (repo hard rule: immutable `:v<run_number>` tags from
  docker-build.yaml anyway), add renovate handling per containers/ convention.
- API drift: the tool hardcodes llama-swap's cmd composition; llama-swap is
  moving fast (v259 stdout split, v262 current, v265 days later). Upstream has
  no `matrix` awareness in the generator — matrix IDs must be maintained in
  base.yaml manually (passthrough), which is exactly the kind of drift the lab
  already hand-manages today.
- Silent-failure modes found in source review: duplicate model IDs skipped
  after first (UD-Q4_K_XL vs Q4_K_XL collision), quant regex requires the
  `-Q...`/`-BF16`/`-F16` token immediately before `.gguf`.
