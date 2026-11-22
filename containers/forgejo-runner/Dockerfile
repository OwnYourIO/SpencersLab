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
# manual-pin: archive digest from the release's checksums.txt. CR_VERSION
# above carries the renovate annotation; this line deliberately has none —
# bump the digest with every CR_VERSION/HELM_VERSION bump, and re-pin the
# literals tests/containers/forgejo-runner.sh checks in the same commit.
ARG CR_SHA256=ce46baf9975d10193b7070b2b7406750c3f664181e36df3f3bbb4a00be40dc1b

# The coder-workspace bake recipe (containers/coder-workspace/Dockerfile
# :142-148) verbatim in shape, so the version assert catches a mis-baked
# helm at THIS build instead of at the next release fire.
RUN curl -fsSL -o "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz" "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
 && curl -fsSL -o "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" \
 && (cd /tmp && sha256sum -c "helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum") \
 && tar -xzf "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz" -C /tmp linux-amd64/helm \
 && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
 && rm -rf "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz" "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" /tmp/linux-amd64 \
 && helm version --short | grep -q "^${HELM_VERSION}"

# cr: the same github.com-egress installer class that killed the first
# fire, promoted from run time to build time (D37). The digest check is
# mandatory — a bare fetch reopens the supply-chain question the sha pin
# closed. Binary-only extract; the tarball also ships README and LICENSE.
RUN curl -fSL -o /tmp/cr.tar.gz "https://github.com/helm/chart-releaser/releases/download/v${CR_VERSION}/chart-releaser_${CR_VERSION}_linux_amd64.tar.gz" \
 && printf '%s  %s\n' "${CR_SHA256}" /tmp/cr.tar.gz | sha256sum -c - \
 && tar -xzf /tmp/cr.tar.gz -C /usr/local/bin cr \
 && chmod 0755 /usr/local/bin/cr \
 && rm -f /tmp/cr.tar.gz \
 && cr --version
