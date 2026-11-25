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
# inherited untouched — the no-regression law (D36). helm and cr are the
# only additions, landed at the default-PATH names plain workflow
# invocations resolve.
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
# Bump recipe (2026-11-23): move a version ARG and its stage tag together,
# refresh that stage's digest, then re-anchor both BIN_SHA256 from the
# OFFICIAL release checksums by hashing the EXTRACTED binary of the
# checksum-verified tarball — an archive hash and its own binary's hash are
# never equal, so hashing the archive would fail every build — and re-pin
# the literals tests/containers/forgejo-runner.sh checks, in the same
# commit. A stale anchor dies this build; that death is the anchor working.

# The tool stages come first so the job image below stays the last stage
# (cf-6-feat-builder-bootstrap-4, 2026-11-23). Each pin is the digest that
# tag serves: 3.22.1 is a multi-arch INDEX, so its anchor is the index
# digest; v1.10.1-amd64 is a single-manifest per-arch tag, so its anchor is
# that manifest digest. Substituting the other class for either moves the
# pin off what a pull of the tag gets.
FROM docker.io/alpine/helm:3.22.1@sha256:8191701ad1f82ee3695c87211fcbfe6d7b1bb7df92ac1c8de9ccdb0995a6a2c1 AS helmtool
FROM ghcr.io/helm/chart-releaser:v1.10.1-amd64@sha256:f04f886affa5ba55b004788591b56f35bfd79abca9f85f0cb2f61c2f90bbe84c AS crtool

FROM ghcr.io/catthehacker/ubuntu:act-24.04@sha256:7bf3a8afc2bbfe7fdaf4b9d2716cb2f3634fd21e4f38e26aa17a12cfda80d721

# helm stays on the v3 line: ArgoCD renders this repo's charts with v3, so
# the client must validate against the same engine that deploys (the
# coder-workspace bake-pin and the GitHub-hosted preinstall equivalent,
# D38).
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v3.22.1

# cr at the version+digest pair build-charts.yaml pinned and the C01 review
# verified against upstream checksums.txt (D37 migrates the pair from
# workflow env into this build's ARGs).
# renovate: datasource=github-releases depName=helm/chart-releaser
ARG CR_VERSION=1.10.1

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

# Provenance of the two anchors (measured 2026-11-23 against the official
# release metadata): the helm-v3.22.1-linux-amd64 tarball is
# 896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea and the
# chart-releaser_1.10.1_linux_amd64 tarball is
# ce46baf9975d10193b7070b2b7406750c3f664181e36df3f3bbb4a00be40dc1b — the
# value the retired CR_SHA256 ARG carried. The binaries those archives hold
# are the binaries the stages above carry, which is what the BINARY anchors
# assert; the community alpine/helm image is a rehost of the official
# tarball, not a rebuild of it.

COPY --from=helmtool /usr/bin/helm /usr/local/bin/helm
COPY --from=crtool /usr/local/bin/cr /usr/local/bin/cr

# One RUN covers both tools (cf-6-feat-builder-bootstrap-4, 2026-11-23): the
# copied bytes must match the anchors, and each binary must report its own
# pinned version, so a wrong tool dies here instead of at the next release
# fire. cr answers with the `version` SUBCOMMAND — chart-releaser 1.10.1
# rejects `--version` outright (measured here: unknown flag, non-zero exit),
# so the flag form would have died on the first build whose transport worked.
RUN printf '%s  %s\n' "${HELM_BIN_SHA256}" /usr/local/bin/helm \
        "${CR_BIN_SHA256}" /usr/local/bin/cr | sha256sum -c - \
 && helm version --short | grep -q "^${HELM_VERSION}" \
 && cr version | grep -q "v${CR_VERSION}"
