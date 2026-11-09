# vLLM Radiance 0.30 re-export for the gpu-ai R9700 (cf-131 C01): the repo's
# first-build-law artifact for the magiccodingman/vllm-radiance 0.30 stack.
# The upstream image is a SELF-CONTAINED terminal build (RESEARCH R3 L1.2):
# vLLM 0.30.0 @ ced6857afa0ea7b2e3f0846a62e1394e90f15607 (the v0.30.0 tag
# commit) + libr4d 0.5.0 + the 35 release overlays + the R4D/MXFP4 kernels +
# 16 RDNA4-tuned block-FP8 GEMM configs (device_name=AMD_Radeon_R9700), all
# baked. There is no build story left to transcribe: apart from the one
# sanctioned flash-attn layer below (D34), the overlay adds NOTHING — we
# re-export it under the repo's ghcr namespace because the cluster's pull
# target must be an in-repo-ledgered artifact and docker-build.yaml's
# first-build `:v<run>` law needs its target (D23). The chart-direct
# upstream pin stays rejected: it would orphan that artifact and move the
# ledger home out of README.md.
#
# Pin law: the DIGEST is the pin, written tag+digest (the maintainers' own
# sha-pinned tag convention, guide Part 2.3 / R2 L1.3). Tag<->commit law
# (R3 L1.1): publishes are release-branch-only -- each build pairs a
# `1.0.<pipeline>` tag with a `sha-<commit>` tag at one digest, and the
# config blob's org.opencontainers.image.revision label records the source
# commit. WATCH: the bump trigger is the next release-branch 1.0.<n>/sha
# pair, NOT GitHub main movement -- test-only main merges never reach an
# image (R3 conflict #4). The pin bumps manually; the release-branch sha
# pairs have no auto-update datasource (D12-amended). Bump procedure and
# interface contract: README.md.
# ledger: magiccodingman/vllm-radiance 1.0.397 (= latest = 1.0 =
#         sha-5b99d66c844f) @
#         sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0
#         (Docker Hub tags API + registry manifest probe, re-verified
#         2026-11-08: 4,079,863,554 B compressed, pushed 2026-10-18T06:35Z,
#         amd64/linux single-arch, tag_status active; source commit
#         5b99d66c844fd0a54e4a7eb93b40a1ece009a53d read from the OCI revision
#         label; engine vLLM 0.30.0 @ ced6857afa0ea7b2e3f0846a62e1394e90f15607
#         = the v0.30.0 tag commit; stack record torch 2.12.0 / triton 3.7.1 /
#         AITER 0.1.20 / libr4d 0.5.0 @ e8de4bc1 / ROCm 7.14)
FROM docker.io/magiccodingman/vllm-radiance:1.0.397@sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0

# flash-attn for the ViT FLASH_ATTN path (owner ruling 2026-11-09, D33
# overturned — RESEARCH R5): the pure-Triton AMD port, the SAME source the
# official vLLM ROCm gfx1250 base image builds
# (docker/Dockerfile.rocm_base_gfx1250 @ v0.30.0: jpvillam-amd/
# flash-attention, branch jpvillam/gfx1250_wip) — chosen over the PyPI
# wheel because the PyPI 2.8.3 arch list omits gfx1250 (the R9700's
# enumeration per the commission; the gfx1201 probe result would equally
# license `flash-attn==2.8.3.post2`). With FLASH_ATTENTION_TRITON_AMD_
# ENABLE=TRUE at build time the package compiles NO extension (setup.py
# SKIP_CK_BUILD default) — kernels JIT via Triton at runtime; the flag is
# deliberately inline-only, the runtime var stays chart-owned (20-var law).
# --no-deps --no-build-isolation protect the stack-pinned torch/triton
# (stack.yaml atomicity law); setup.py imports torch+packaging+setuptools
# +wheel, hence the prep. No tag exists upstream → no auto datasource;
# manual bump with the base-pin law (D12-amended shape).
ARG FLASH_ATTN_REPO=https://github.com/jpvillam-amd/flash-attention.git
ARG FLASH_ATTN_REF=aa743c5933560d097d8aa5e833ca10153ed7f6bb
RUN python3 -m pip install --no-cache-dir setuptools wheel packaging \
 && FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE python3 -m pip install \
      --no-cache-dir --no-deps --no-build-isolation \
      "flash-attn @ git+${FLASH_ATTN_REPO}@${FLASH_ATTN_REF}"

# serve = health = metrics on one port: the chart probes /health here and
# scrapes /metrics from it. The upstream image config declares no
# ExposedPorts, so the port record lives here (as on the retired GGUF
# overlay this re-export replaces).
EXPOSE 8000
