# Strata engine + llama-swap supervisor bundle for the gpu-ai strata pod
# (consumer: the in-chart strata controller of charts/llama-swap). PID 1
# is llama-swap and the engine arrives as its child through the documented
# `serve` CLI + run-config JSON; the upstream tini + entrypoint.sh launch
# path is replaced by design. The interface contract C02/C05 build against
# lives in README.md.

# Pin shape = the 2026-10-27 coord ruling (b): literal flavor-complete tags,
# no renovate comment on this depName (no repo manager extracts a
# datasource=docker ARG pin; DECISIONS coordination round). The tag->digest
# ledger and the manual-bump procedure are in README.md — #3421 and the
# unified-vulkan-262 in-place rebuild are the why. Strata releases 0.2.4-0.2.6
# ship NO images: the GHCR tag list, not the release list, is the truth of
# what can be pinned (RESEARCH §1).
FROM ghcr.io/niko1221/strata:0.2.7-rocm-gfx120x AS engine-primary

# gfx1151 sibling bundled for the Strix-alone fallback C05 supervises; its
# existence at the same 0.2.7 tag is what makes the single-image bundle viable
# (RESEARCH §1 measured).
FROM ghcr.io/niko1221/strata:0.2.7-rocm-gfx1151 AS engine-strix

# Supervisor stage: the golden release-versioned family the existing chart
# rides, kept honest by the renovate.json versioning packageRule. Manifest
# digest re-verified 2026-10-28 via GHCR manifest HEAD:
# sha256:0cc42f1024b54be3de100ae7a7a2730047ca5c27cf7a354f8a9f63142f00c045
# (RESEARCH §3). Only the single binary is harvested, see below.
FROM ghcr.io/mostlygeek/llama-swap:unified-vulkan-266 AS supervisor

# Source-checkout stage: headless weight provisioning IS a source-checkout
# operation — upstream's llama-swap integration doc ("needs a source
# checkout, not the desktop installer", docs/LLAMA_SWAP.md) and TERMINAL
# install error ("this folder has no installer (setup.py)") both require
# the repo's setup.sh tree, which the packaged images do not carry. The
# first-quant pin is v0.2.7, matching the engine packages below; bump it
# WITH the flavor tags per the README ledger (manual cadence, ruling (b) —
# no renovate comment: this image carries zero directives by the C01
# contract). No .git: updates land through image rebuilds, not in-place pulls.
FROM alpine:3.22 AS strata-src
RUN apk add --no-cache git ca-certificates \
    && git clone --depth 1 --branch v0.2.7 https://github.com/Niko1221/Strata /opt/strata/src/Strata \
    && rm -rf /opt/strata/src/Strata/.git

# Runtime base = the gfx120x image: engine root
# 0.1.52-linux-x86_64-hip-rx9070, the terminal tree at
# /opt/strata/terminal, and the baked ROCm env/STRATA_COMPONENTS_DIR all
# arrive laid out once instead of being re-copied; the bundle adds only the
# second flavor's engine root and the supervisor binary.
FROM engine-primary AS runtime

# Engine-compile dependencies for the model-fetch init's setup.sh: the
# source-checkout Step 4 compiles the AMD engine once into the checkout on
# the claim (deploy 2026-10-29 "[X] a C++ compiler and git are needed to
# compile the AMD engine"; ccache added per that build's own warning).
# Baked, not installed at boot: runtime apt would
# make every pod start depend on mirror availability and ship a
# non-reproducible image (container-creation: apt in the same RUN,
# --no-install-recommends, lists cleaned).
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential git ccache \
    && rm -rf /var/lib/apt/lists/*

# The two flavors install same-named binaries, so the copy plan must keep the
# label dirs distinct — merging them under one dir would silently shadow the
# R9700 engine with the halo one (or vice versa) at exe-resolution time.
COPY --from=engine-strix /opt/strata/components/engine/0.1.52-linux-x86_64-hip-halo /opt/strata/components/engine/0.1.52-linux-x86_64-hip-halo

# The unified image's Vulkan llama.cpp stack, run.sh launcher and /models
# workingdir stay behind on purpose: ROCm owns this container's GPU path and
# run.sh belongs to the launch shape this image replaced. PATH already
# resolves /usr/local/bin (COPY preserves the executable bit).
COPY --from=supervisor /usr/local/bin/llama-swap /usr/local/bin/llama-swap

# setup.sh tree for the model-fetch init container (chart contract): copied
# to the claim at first boot so setup's outputs (run configs, Strata-data)
# persist on the PVC alongside the weights.
COPY --from=strata-src /opt/strata/src/Strata /opt/strata/src/Strata

# Interface freeze (README.md contract): a broken surface fails this build,
# not the running pod. The `strata` names under both label dirs are measured
# facts, not guesses — and the find re-prints every non-library executable
# there into the build log so the C02/C05 profile `exe` literals can be
# checked against what upstream actually shipped at this pin.
RUN set -eux; \
    test -x /opt/strata/terminal/bin/strata; \
    test -x /opt/strata/components/engine/0.1.52-linux-x86_64-hip-rx9070/strata; \
    test -x /opt/strata/components/engine/0.1.52-linux-x86_64-hip-halo/strata; \
    test -f /opt/strata/src/Strata/setup.sh; \
    command -v git >/dev/null; \
    command -v c++ >/dev/null; \
    find /opt/strata/components/engine -mindepth 2 -maxdepth 2 -type f -perm -u+x ! -name '*.so*' -exec ls -l '{}' +

# The base image's Cmd is an argument to its own entrypoint.sh launch path;
# it must not survive the ENTRYPOINT swap as a llama-swap flag. This default
# is the documented config path — the chart overrides it via container args
# either way.
CMD ["-config", "/app/config/config.yaml"]

ENTRYPOINT ["llama-swap"]

# The inherited upstream healthcheck presumes the entrypoint.sh launch this
# image replaced, and Kubernetes ignores image HEALTHCHECK — kubelet probes
# llama-swap's own /health (chart contract, DECISIONS 2026-10-27 probes).
HEALTHCHECK NONE

# Root posture is deliberate, not oversight: the engine needs /dev/kfd and
# /dev/dri with video+render group membership and DOCKER.md's memlock
# semantics, and no uid-65532 user is created (deviation from the
# container-creation standard approved in the cf-77 plan; device access is
# brokered by the pod, which runs privileged with hostPath devices).

# Escalation if this bundle fails on-target = the guide-2B TheRock source
# build, and two facts make it non-trivial (RESEARCH §6): the
# therock-dist-linux-gfx120X-all-7.14.1.tar.gz is published WITHOUT a sha256
# (2.336 GB — record the digest on download), and the repo carries no gfx1201
# hipBLASLt tuning table for 100401, so a source build runs plain-dense
# prompt matmuls or self-tunes via tools/hip/tune_hipblaslt.cpp (PR #3636
# ran gfx1201 on 7.14.1 without a table fine). The packaged pins above are
# the v1 path precisely because they are self-sufficient.
