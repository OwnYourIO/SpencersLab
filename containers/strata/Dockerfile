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
#
# 0.2.9 -> 0.2.13 (cf-141 C04, gated by the tuning runbook §4 — owner Q8
# un-defer, Q13(a) pin-first order): engine packages 0.1.59 bring the K-quant
# MMQ prompt defaults and the matrix-core QSA scorer on gfx12 Linux, the 8-slot
# KV-window walkdown grace, and unconditional drafting.apply() shaping (RESEARCH
# round 2 [60][62][79]); v0.2.13 is the tag the vendored carry below re-cut
# applies against (RESEARCH round 3, verdict (a)). Both flavor tags exist at
# 0.2.13 and their digests are the README ledger pair (live re-read 2026-11-11).
# The 0.2.8 -> 0.2.9 step (cf-86 C09, U10.2) brought the chunked DeltaNet
# prompt kernels and #4708 — era history, recorded because the carry's own
# hunks were cut against that line.
FROM ghcr.io/niko1221/strata:0.2.13-rocm-gfx120x AS engine-primary

# gfx1151 sibling bundled for the Strix-alone fallback C05 supervises; its
# existence at the same flavor tag is what makes the single-image bundle viable
# (RESEARCH §1 measured, re-measured at 0.2.13 by this bump's tag reads).
FROM ghcr.io/niko1221/strata:0.2.13-rocm-gfx1151 AS engine-strix

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
# checkout tag tracks the flavor tags (v0.2.13 here), so setup.py's catalog
# and the bundled engine packages stay one release line; bump it WITH them
# per the README ledger (manual cadence, ruling (b) — no renovate comment:
# this image carries zero directives by the C01 contract). No .git: updates
# land through image rebuilds, not in-place pulls.
#
# The checkout also carries the vendored cf-86 C09 constants patch
# (carry/ornith-q36.patch, upstream issue #3574) — without it the claim-compiled
# engine refuses Ornith-1.5-122B at load. It patches SOURCE, so it applies here;
# the packaged engine roots below are upstream binaries and stay UNPATCHED,
# which is why the ornith profile must name the claim-compiled engine and never
# a packaged root (charts/llama-swap engineProfileStrataOrnith).
FROM alpine:3.24 AS strata-src
COPY carry/ornith-q36.patch /opt/strata/carry/ornith-q36.patch
RUN apk add --no-cache git ca-certificates \
    && git clone --depth 1 --branch v0.2.13 https://github.com/Niko1221/Strata /opt/strata/src/Strata \
    && cd /opt/strata/src/Strata && git apply /opt/strata/carry/ornith-q36.patch \
    && rm -rf /opt/strata/src/Strata/.git

# Runtime base = the gfx120x image: engine root
# 0.1.59-linux-x86_64-hip-rx9070, the terminal tree at
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
# Official-first with a fallback guard: the plain update runs against
# whatever sources the base image ships (Canonical's deb822
# ubuntu.sources). Only a non-zero exit re-points BOTH stanza hosts at
# the kernel.org mirror and retries; the fallback is never the primary
# path, self-retires when the official endpoints answer again, and
# targets exactly the deb822 file the noble base layer carries
# (cf-141 C05 probe). This layer is a throwaway toolchain bake, not the
# serving image's trust path.
RUN apt-get update \
    || { sed -i 's|http://archive.ubuntu.com|http://mirrors.edge.kernel.org|; s|http://security.ubuntu.com|http://mirrors.edge.kernel.org|' \
           /etc/apt/sources.list.d/ubuntu.sources \
           && apt-get update; } \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential git ccache \
    && rm -rf /var/lib/apt/lists/*

# The two flavors install same-named binaries, so the copy plan must keep the
# label dirs distinct — merging them under one dir would silently shadow the
# R9700 engine with the halo one (or vice versa) at exe-resolution time.
COPY --from=engine-strix /opt/strata/components/engine/0.1.59-linux-x86_64-hip-halo /opt/strata/components/engine/0.1.59-linux-x86_64-hip-halo

# The unified image's Vulkan llama.cpp stack, run.sh launcher and /models
# workingdir stay behind on purpose: ROCm owns this container's GPU path and
# run.sh belongs to the launch shape this image replaced. PATH already
# resolves /usr/local/bin (COPY preserves the executable bit).
COPY --from=supervisor /usr/local/bin/llama-swap /usr/local/bin/llama-swap

# setup.sh tree for the model-fetch init container (chart contract): copied
# to the claim at first boot so setup's outputs (run configs, Strata-data)
# persist on the PVC alongside the weights. The carry patch rides along as the
# build's own evidence: the verify layer below re-applies it in reverse over
# the tree that actually ships (CI never compiles HIP, so that re-apply plus
# the ternary-floor and X(12) greps are the only pre-merge proof of the
# patched tree).
COPY --from=strata-src /opt/strata/src/Strata /opt/strata/src/Strata
COPY --from=strata-src /opt/strata/carry/ornith-q36.patch /opt/strata/carry/ornith-q36.patch

# Weight staging lives in the image, not in the chart (cf-86 C07 lift):
# files/fetch_models.sh is the driver the strata pod's model-fetch init execs,
# files/hf_fetch.py its downloader (anon + gated modes) and files/byte_pins.env
# the shard byte literals it sources. Baking them is what lets the verify step
# below check them — a 330-line chart heredoc is logic no build ever parses.
# The driver must end up executable: exec-form command + mode 644 is an
# "exec format error" at container start, which keeps the chart's boot guard
# loud but makes it useless.
COPY files/ /opt/strata/bin/
RUN chmod 0755 /opt/strata/bin/fetch_models.sh

# Interface freeze (README.md contract): a broken surface fails this build,
# not the running pod. The `strata` names under both label dirs are measured
# facts, not guesses — and the find re-prints every non-library executable
# there into the build log so the C02/C05 profile `exe` literals can be
# checked against what upstream actually shipped at this pin.
# The fetch trio is verified by syntax + interface only: RUNNING the driver
# here would stage ~183 GB of weights inside CI, with no claim and no token.
RUN set -eux; \
    test -x /opt/strata/terminal/bin/strata; \
    test -x /opt/strata/components/engine/0.1.59-linux-x86_64-hip-rx9070/strata; \
    test -x /opt/strata/components/engine/0.1.59-linux-x86_64-hip-halo/strata; \
    test -f /opt/strata/src/Strata/setup.sh; \
    test -x /opt/strata/bin/fetch_models.sh; \
    test -f /opt/strata/bin/hf_fetch.py; \
    test -f /opt/strata/bin/byte_pins.env; \
    sh -n /opt/strata/bin/fetch_models.sh; \
    /opt/strata/terminal/python/bin/python3 -m py_compile /opt/strata/bin/hf_fetch.py; \
    rm -rf /opt/strata/bin/__pycache__; \
    cd /opt/strata/src/Strata \
      && git apply --check --reverse /opt/strata/carry/ornith-q36.patch \
      && grep -q -F '> 2048 ?' include/strata/kernels/cpu/native_expert.hpp \
      && grep -q -F ': 2048;' include/strata/kernels/cpu/native_expert.hpp \
      && grep -q 'X(12)' src/kernels/cuda/iq_kernels.cu; \
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
