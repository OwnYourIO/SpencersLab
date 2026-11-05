# ghcr.io/ownyourio/forgejo-host-runner — the one image the host-backend
# Forgejo runner pod runs as (charts/forgejo-runner, runner.backend: host).
# Runner daemon plus the whole job surface for the Immich -> CuratedForest
# Hugo pipeline: git/git-lfs (LFS derivatives), curl/jq (API work), zstd
# (actions cache), python3 (sync tooling), hugo extended (site build),
# go (hugo module download), node + netlify-cli (deploys).
#
# amd64 only (lab nodes); arm64 is a follow-up if nodes ever go arm.

# Binary donor only: the upstream image is busybox/alpine-based and ships
# the daemon as a static ELF at /bin/forgejo-runner. It runs as uid 1000
# with HOME=/data, the identity this image adopts as the node user so /data
# ownership matches between the docker and host backends.
# renovate: datasource=docker depName=forgejo/runner registryUrl=https://data.forgejo.org
FROM data.forgejo.org/forgejo/runner:13.2.1 AS runner-src

FROM docker.io/library/node:22-bookworm-slim

# hugo EXTENDED at the site's exact netlify.toml pin: the runner build must
# reproduce Netlify's output, and SCSS/.Resize only exist in the extended
# binary.
# renovate: datasource=github-releases depName=gohugoio/hugo
ARG HUGO_VERSION=0.151.0
# manual-pin: sha256 of the tarball from the same release's
# hugo_${HUGO_VERSION}_checksums.txt; bump with HUGO_VERSION — a stale
# digest must fail the build, not get auto-trusted.
ARG HUGO_SHA256=f2fe3b4ef90bf053d93c713eca1d4d5a467d8d2d5da858a448d55eb71ad44ddf
# hugo downloads the site's modules with a `go` binary on PATH, so the
# toolchain ships pinned from the official tarball; the URL expands from
# this ARG, so a version-only bump fails the digest check below loudly.
# renovate: datasource=golang-version depName=golang
ARG GO_VERSION=1.27.3
# manual-pin: sha256 of go${GO_VERSION}.linux-amd64.tar.gz (official
# dl.google.com .sha256); bump with GO_VERSION — a stale digest must fail
# the build, not get auto-trusted.
ARG GO_SHA256=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
# Deploy CLI. Requires Node >=22.13.0; the pinned base resolves to 22.23.4,
# so the engine floor holds while the 22.x line stays at/above 22.13.
# renovate: datasource=npm depName=netlify-cli
ARG NETLIFY_CLI_VERSION=27.16.2

# Job-surface toolchain. dumb-init reaps zombies the same way the donor
# image's entrypoint does; git and git-lfs land in one layer so the
# package's system-wide LFS hook install (postinst) finds git.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dumb-init \
        git \
        git-lfs \
        jq \
        python3 \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# The tarball also carries README.md and LICENSE — extract only the binary.
RUN set -eux; \
    curl -fsSL -o /tmp/hugo.tar.gz \
        "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz"; \
    printf '%s  %s\n' "${HUGO_SHA256}" "/tmp/hugo.tar.gz" > /tmp/hugo.expected; \
    sha256sum -c /tmp/hugo.expected; \
    tar -xzf /tmp/hugo.tar.gz -C /usr/local/bin hugo; \
    rm -f /tmp/hugo.tar.gz /tmp/hugo.expected; \
    /usr/local/bin/hugo version

RUN set -eux; \
    curl -fsSL -o /tmp/go.tar.gz \
        "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"; \
    printf '%s  %s\n' "${GO_SHA256}" "/tmp/go.tar.gz" > /tmp/go.expected; \
    sha256sum -c /tmp/go.expected; \
    tar -xzf /tmp/go.tar.gz -C /usr/local; \
    rm -f /tmp/go.tar.gz /tmp/go.expected; \
    /usr/local/go/bin/go version

# Build-time root install, runtime read: uid 1000 needs go on PATH for hugo
# module download.
ENV PATH=/usr/local/go/bin:$PATH

RUN npm install -g netlify-cli@${NETLIFY_CLI_VERSION} && npm cache clean --force

# The daemon at the exact path the chart's command names for both backends.
COPY --from=runner-src /bin/forgejo-runner /bin/forgejo-runner

# The sync tooling as one package (relative imports, so the wrappers run
# python3 -m sync.<module>); the /usr/local/bin names are what the site's
# workflows call. node owns /opt/immich-hugo-sync so runtime bytecode
# caches can land there.
COPY sync/ /opt/immich-hugo-sync/sync/
COPY bin/immich-hugo-sync /usr/local/bin/immich-hugo-sync
COPY bin/immich-hugo-publish /usr/local/bin/immich-hugo-publish
RUN chown -R node:node /opt/immich-hugo-sync

# /data is the runner's home on the release PVC: workdir, actions cache,
# sync state and dotfiles all land there (the donor image declares it too).
RUN mkdir -p /data && chown node:node /data
ENV HOME=/data
USER node

# The chart replaces this with its own command; kept for parity with the
# donor image's entrypoint when the image is run bare.
ENTRYPOINT ["/usr/bin/dumb-init", "/bin/forgejo-runner", "daemon"]
