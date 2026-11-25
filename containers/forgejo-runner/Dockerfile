# ghcr.io/ownyourio/forgejo-runner — the act job image behind the runner's
# four act-24.04-family labels (charts/forgejo-runner). D33 bake: the
# release pipeline's first fire died on a read ECONNRESET downloading helm
# from get.helm.sh inside a job's "Set up helm" step, so the toolchain
# bakes at image build time, on the containers-build egress lane that
# production already proves, and workflow jobs install nothing at run time.
#
# This is a DERIVATIVE of the production act base, not a rebuild: the
# inventory every workflow step assumes today (git/git-lfs, jq, python3,
# node 20+24 with tool caches, yq, docker CLI + buildx + compose, apt) is
# inherited untouched — the no-regression law (D36). helm, cr and the coder
# CLI are the only additions, landed at the default-PATH names plain
# workflow invocations resolve.
#
# The base tag is rolling upstream and runners never re-pull a cached tag,
# so the digest below is the authority and the tag is the human label;
# refreshing the digest is a deliberate, upstream-verified edit.
#
# Deviation from the container-creation non-root law, on purpose (D36): no
# USER line — a job image keeps the base's root job shell because today's
# jobs write system paths and install packages through the package
# manager, and a non-root job shell would regress them. That law serves
# service containers; this image never serves traffic.
#
# Run -4 (2026-11-23, cf-6-feat-builder-bootstrap-4) changed the acquisition
# SOURCE, not the network path. Three lane dispatches died identically on
# curl TLS exit 35 fetching helm from get.helm.sh while ghcr pulls, the
# Forgejo API and the GitHub API answered from the same daemon — a targeted
# upstream filter of that one host against this egress, not a fault this
# side of the NAT. So both fetch RUNs are gone, and with them the run -3
# retry budget that hardened them; helm and cr now arrive by COPY --from of
# two digest-pinned tool images. A comment may name get.helm.sh as history;
# no RUN line may reference it.
#
# Bump recipe (2026-11-23, extended cf-56 2026-11-25): move a version ARG
# and its stage tag together, refresh that stage's digest, then re-anchor
# the three BIN_SHA256 anchors from the OFFICIAL release checksums by
# hashing the EXTRACTED binary of the checksum-verified tarball (for the
# coder stage: the official image's layer binary, provenance below) — an
# archive hash and its own binary's hash are never equal, so hashing the
# archive would fail every build — and re-pin the literals
# tests/containers/forgejo-runner.sh checks, in the same commit. A stale
# anchor dies this build; that death is the anchor working.

# cf-56 (OQ3 owner ruling, 2026-11-25): the Coder CLI bakes into THIS image
# — a digest-pinned stage over the official coder/coder image (the ghcr
# pull lane the helm and cr stages ride) — replacing the prior separate-
# coder-cli-image plan and any run-time fetch (the D33 egress class).
# Accepted consequences: the runner's chart label pin (charts/forgejo-
# runner, four act-label lines) is hand-bumped to the new calendar tag —
# no Renovate lane reads it (AGENTS.md law) — and the image rebuild must
# land before the first coder-template push fires, or the first fire runs
# the pre-bake image and dies at the plain `coder version` diag.
#
# The tool stages come first so the job image below stays the last stage
# (cf-6-feat-builder-bootstrap-4, 2026-11-23). Each pin is the digest that
# tag serves: 3.22.1 is a multi-arch INDEX, so its anchor is the index
# digest; v1.10.1-amd64 is a single-manifest per-arch tag, so its anchor is
# that manifest digest; v2.39.5 is a multi-arch index too (three platforms,
# measured 2026-11-25), so its anchor is that index digest. Substituting
# the other class for any of the three moves the pin off what a pull of
# the tag gets.
FROM docker.io/alpine/helm:3.22.1@sha256:8191701ad1f82ee3695c87211fcbfe6d7b1bb7df92ac1c8de9ccdb0995a6a2c1 AS helmtool
FROM ghcr.io/helm/chart-releaser:v1.10.1-amd64@sha256:f04f886affa5ba55b004788591b56f35bfd79abca9f85f0cb2f61c2f90bbe84c AS crtool
FROM ghcr.io/coder/coder:v2.39.5@sha256:40fade40473a8a143d762f8ba0be07c0239be9932651f22046c0c0b21800552d AS codertool

FROM ghcr.io/catthehacker/ubuntu:act-24.04@sha256:7bf3a8afc2bbfe7fdaf4b9d2716cb2f3634fd21e4f38e26aa17a12cfda80d721

# helm stays on the v3 line: ArgoCD renders this repo's charts with v3, so
# the client must validate against the same engine that deploys (the
# coder-workspace bake-pin and the GitHub-hosted preinstall equivalent,
# D38).
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v3.22.1

# cr at the version+digest pair release.yaml pinned and the C01 review
# verified against upstream checksums.txt (D37 migrates the pair from
# workflow env into this build's ARGs).
# renovate: datasource=github-releases depName=helm/chart-releaser
ARG CR_VERSION=1.10.1

# coder at the newest stable release at or above the deployed coderd floor
# (charts/coder appVersion 2.35.2; v2.39.5 measured newest stable
# 2026-11-25) — the CI CLI must not predate the server it pushes to, and a
# stable release keeps the pin auditable as a concrete version.
# renovate: datasource=github-releases depName=coder/coder
ARG CODER_VERSION=2.39.5

# manual-pin: sha256 of the EXTRACTED linux-amd64 helm binary, measured
# 2026-11-23 (cf-6-feat-builder-bootstrap-4) byte-identical to the helm
# stage's /usr/bin/helm and to the official v3.22.1 release's. Bump with
# HELM_VERSION and the stage digest; unannotated so no bump sails past it.
ARG HELM_BIN_SHA256=46aeab5e043f62d01f7c168823b392cabc1cea3807b67906296290483791be43

# manual-pin: sha256 of the EXTRACTED linux_amd64 cr binary, measured
# 2026-11-23 (cf-6-feat-builder-bootstrap-4) byte-identical to the cr stage's
# /usr/local/bin/cr and to the official v1.10.1 release's. Bump with
# CR_VERSION and the stage digest; unannotated for the helm anchor's reason.
ARG CR_BIN_SHA256=ca45e76c0aa7a159425cd5b4b63269b8cb5ee481a2667c9f8ffcf092a33402fc

# manual-pin: sha256 of the EXTRACTED coder binary (opt/coder) of the
# pinned codertool stage, measured 2026-11-25 (cf-56 OQ3) from the pinned
# image's GHCR layer tar-listing (no docker daemon); its layer is the
# single-entry opt/coder of the stage's amd64 manifest. Bump with CODER_VERSION and the stage digest.
ARG CODER_BIN_SHA256=834311719b2daca0c6baf7338c3029212143a7d4753385e3fe00f389bdd7afe4

# Provenance of the three anchors: the helm-v3.22.1-linux-amd64 and
# chart-releaser_1.10.1_linux_amd64 tarballs (measured 2026-11-23 against
# the official release metadata) are
# 896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea and
# ce46baf9975d10193b7070b2b7406750c3f664181e36df3f3bbb4a00be40dc1b — the
# value the retired CR_SHA256 ARG carried. The coder anchor was measured
# 2026-11-25 (cf-56) from the pinned image's GHCR layer tar-listing (the
# container-creation skill's sanctioned offline check, no docker daemon):
# the v2.39.5 tag serves index
# sha256:40fade40473a8a143d762f8ba0be07c0239be9932651f22046c0c0b21800552d,
# whose amd64 manifest
# sha256:878a8e0aa3374ea033ab4a5918cbe6b105278b1dde73f30c801a9da42228a4d4
# carries the coder binary in layer
# sha256:cd812300e60e57e49bb7e6506ffb3df5e60c04daf7429a6111e530d3714676c5
# (content-sha256 verified on download) as its single entry, opt/coder. The
# binaries those archives and the layer hold are the binaries the stages
# carry — what the BINARY anchors assert; the community alpine/helm image is
# a rehost of the official tarball, not a rebuild of it, and the official
# coder/coder image is the Coder build itself (coderd and CLI are one
# binary), so its layer is the source of truth.

COPY --from=helmtool /usr/bin/helm /usr/local/bin/helm
COPY --from=crtool /usr/local/bin/cr /usr/local/bin/cr
COPY --from=codertool /opt/coder /usr/local/bin/coder

# One RUN covers the three tools (cf-6-feat-builder-bootstrap-4, 2026-11-23,
# extended cf-56 2026-11-25): the copied bytes must match the anchors, and
# each binary must report its own pinned version, so a wrong tool dies here
# instead of at the next release fire. cr answers with the `version`
# SUBCOMMAND — chart-releaser 1.10.1 rejects `--version` outright (measured
# here: unknown flag, non-zero exit), so the flag form would have died on
# the first build whose transport worked. coder answers the same subcommand
# shape: `coder version` prints `Coder v2.39.5+<build-id> ...` (measured
# 2026-11-25 on the extracted binary, rc 0), so the assert greps the
# v-prefixed version token, exactly like the cr arm.
RUN printf '%s  %s\n' "${HELM_BIN_SHA256}" /usr/local/bin/helm \
        "${CR_BIN_SHA256}" /usr/local/bin/cr \
        "${CODER_BIN_SHA256}" /usr/local/bin/coder | sha256sum -c - \
 && helm version --short | grep -q "^${HELM_VERSION}" \
 && cr version | grep -q "v${CR_VERSION}" \
 && coder version | grep -q "v${CODER_VERSION}"
