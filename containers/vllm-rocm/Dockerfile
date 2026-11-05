# vLLM GGUF overlay for the gpu-ai R9700 (cf-105 C01): the upstream
# vllm/vllm-openai-rocm:v0.33.0-rocm100 base (R1-verified image class —
# ROCm 10.0, PyTorch 2.13.0, py3.12, PYTORCH_ROCM_ARCH incl. gfx1201+gfx1151)
# plus the OOT vllm-gguf-plugin (GGUF weight loading — the only 32 GiB weight
# path that fits the D4 envelope, RESEARCH R1 §3) and the R1 recipe env
# pins. The base's ENTRYPOINT ["vllm", "serve"], WORKDIR /app and all other
# runtime behavior are inherited unchanged — this overlay adds the plugin +
# env, nothing else (C01 AC4). Interface contract C02 builds against:
# README.md.
#
# Base pin = tag in the FROM + full manifest digest in the ledger comment
# below. The image pins carry NO auto-update directives by contract — the
# ledger is manual and the CI build (docker-build.yaml, triggered on
# containers/**) is authoritative; re-verify command + procedure in
# README.md "Tag -> digest ledger".
# ledger: vllm/vllm-openai-rocm v0.33.0-rocm100 @
#         sha256:4fcd39b758b660c4e9c345c021e2ea8f0ccdb31e3c32507d676cc3005ae83fba
#         (Docker Hub tags API, probed 2026-11-05)
FROM vllm/vllm-openai-rocm:v0.33.0-rocm100

# Plugin pin = a GIT REF, not a PyPI release: the newest release (v0.0.5,
# 2026-08-10) predates PR #98 (merged to main 2026-08-18) and has no
# Qwen3.5 GGUF adapter, and no release since exists (RESEARCH Post Research
# V1 [147][149]). The ref is main HEAD (2026-10-24) — verified to exist and
# to carry the #98 adapter (its weights_adapter/qwen3_5.py, fetched at the
# ref); the git-refs comment below is the ONE sanctioned machine-readable
# directive in this container dir (the gpt-researcher git-pin shape).
# renovate: datasource=git-refs depName=vllm-project/vllm-gguf-plugin
ARG VLLM_GGUF_PLUGIN_REF=e454affe0ca23c9dc8754ec3033270cb30622ed5

# Vendored import-compat carry (the strata carry/ precedent) — what it fixes
# and its drop condition are documented in the file header.
COPY carry/qwen35-import-compat.patch /opt/vllm-rocm/carry/qwen35-import-compat.patch

# Plugin install + patch, one stage:
#  - the precheck asserts the build-critical base facts up front (ROCm torch
#    + setuptools for the non-isolated wheel build) so a base that loses
#    them fails with a clear message, not a cryptic wheel-build error
#  - --no-build-isolation is REQUIRED, not an optimization: the plugin's
#    setup.py compiles vllm_gguf_plugin._C_gguf with torch cpp_extension,
#    and a default-isolated build would fetch a CUDA torch from PyPI (no
#    nvcc in this image) instead of building against the ROCm torch whose
#    hipcc is the only valid toolchain — the plugin README's own install
#    instruction
#  - the carry patch then redirects the plugin's top-level
#    `from vllm.transformers_utils.configs.qwen3_5 import Qwen3_5Config`
#    (+ the qwen3_5_moe line) to `transformers` — the layout vLLM #60623
#    introduced: the vendored configs module was removed from vLLM and is
#    absent from v0.33.0, while vLLM's own models/qwen3_5.py imports the
#    same configs from transformers (RESEARCH Post Research V1)
#  - the tail is the build's own proof the shipped tree is the patched one:
#    reverse --check + the import greps (CI never runs the engine; the C06
#    on-target import probe is the functional acceptance)
RUN python3 -c "import setuptools, torch; assert torch.version.hip, 'non-ROCm torch'" \
    && pip install --no-cache-dir --no-build-isolation \
        "git+https://github.com/vllm-project/vllm-gguf-plugin@${VLLM_GGUF_PLUGIN_REF}" \
    && cd "$SITE_PACKAGES" \
    && git apply /opt/vllm-rocm/carry/qwen35-import-compat.patch \
    && git apply --check --reverse /opt/vllm-rocm/carry/qwen35-import-compat.patch \
    && grep -q '^from transformers import Qwen3_5Config$' vllm_gguf_plugin/weights_adapter/qwen3_5.py \
    && grep -q '^from transformers import Qwen3_5MoeConfig$' vllm_gguf_plugin/weights_adapter/qwen3_5.py \
    && ! grep -q 'vllm.transformers_utils.configs.qwen3_5' vllm_gguf_plugin/weights_adapter/qwen3_5.py

# Non-root posture: the pinned base has no USER (image config User: null —
# it runs as root), so the overlay creates the repo-standard uid 65532 user
# (container-creation standard). The getent guards keep the build correct if
# a future base ships its own uid-65532 user; USER is numeric for the same
# reason. GPU access is group-mediated at runtime — the C02 chart adds
# runAsGroup 44 (video) + SYS_PTRACE + seccomp Unconfined, the upstream
# k8s-device-plugin vllm-serve pod shape (RESEARCH V2 [153]).
RUN (getent group 65532 >/dev/null || groupadd --system --gid 65532 vllm) \
    && (getent passwd 65532 >/dev/null || useradd --system --uid 65532 --gid 65532 \
         --shell /bin/false --home-dir /home/vllm --create-home vllm) \
    && mkdir -p /data/triton /data/hf \
    && chown -R 65532:65532 /data
USER 65532

# R1 recipe env pins (baked here, not per-pod: the overlay is the recipe's
# home).
#  - PYTORCH_ALLOC_CONF: expandable segments against ROCm allocator
#    fragmentation (R1 Q5.5)
#  - TRITON_CACHE_DIR / HUGGINGFACE_HUB_CACHE: under /data, the C02 cache
#    PVC mount — Triton JIT + HF model cache persist across pods
#  - VLLM_ROCM_USE_AITER=0 explicit: the image's AITER prebuilds are
#    CDNA-only (AITER_ROCM_ARCH=gfx942;gfx950); gfx11x/gfx12x must not pick
#    them up (R1 §Q1)
ENV PYTORCH_ALLOC_CONF=expandable_segments:True \
    TRITON_CACHE_DIR=/data/triton \
    HUGGINGFACE_HUB_CACHE=/data/hf \
    VLLM_ROCM_USE_AITER=0

# The base declares no ExposedPorts; the serve = metrics = health surface is
# one port (R5 Q1) — the C02 chart probes /health on it and scrapes
# /metrics from it.
EXPOSE 8000

# ENTRYPOINT ["vllm", "serve"] is inherited from the base (verified in the
# pinned image's config); the C02 chart appends the serve args.
