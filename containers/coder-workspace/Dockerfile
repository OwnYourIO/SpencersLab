# Coder workspace base image: Debian 13 (trixie) slim with the full toolchain
# baked in.
#
# Baked, not installed at boot: workspaces run under the "restricted" Pod
# Security Standard with a read-only root filesystem, so nothing can be
# installed at runtime. What is not in this image does not exist for the
# workspace.
#
# Runtime shape follows from that policy:
#   - uid/gid 1000 and no sudo: allowPrivilegeEscalation: false makes setuid
#     escalation impossible anyway, so a sudo package would only advertise a
#     capability the pod does not have.
#   - writes are confined to $HOME (the workspace PVC) and /tmp (emptyDir); the
#     XDG_*/TMPDIR/GOPATH vars below steer tools there.
#
# Layout constraint: on existing workspaces /home/coder is a PVC mount that
# shadows anything baked at that path, so baked tools live in system paths
# (/usr/local, /usr/bin, /etc). code-server is the deliberate exception: the
# startup script installs it into $HOME on first boot, because a 240 MB
# download kept on the PVC beats 240 MB added to every image rebuild.
#
# Pinning: the base is pinned by digest, every tool by ARG + renovate
# annotation. The digest makes a rebuild reproducible; the annotations are how
# renovate keeps both current.
#
# No ENTRYPOINT: the Coder template supplies the agent bootstrap and calls
# /usr/local/bin/workspace-startup.sh itself.

# renovate: datasource=docker depName=debian
FROM debian:13-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# pipefail matters here: the build-time version asserts pipe each CLI into
# grep, and /bin/sh alone would only honor grep's exit status — a crashing
# tool could slip past it.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

# One pinned Node for every workspace: a node version manager would let a
# workspace drift off the pin.
# renovate: datasource=node-version depName=node
ARG NODE_VERSION=v26.12.0

# Go from go.dev: the Debian-packaged Go lags what the repo's own tooling is
# built against.
# renovate: datasource=golang-version depName=golang
ARG GO_VERSION=1.27.2

# Helm stays on the v3 line: ArgoCD renders this repo's charts with v3, so a v4
# client would validate against a different engine than the one that deploys.
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v3.22.1

# kubectl tracks the cluster minor. kubernetes/kubernetes tags carry the same
# numbers as kubectl releases, so one datasource feeds both.
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.36.5

# uv runs the BMad skill tooling, whose setup only works under `uv run`.
# renovate: datasource=github-releases depName=astral-sh/uv
ARG UV_VERSION=0.13.1

# forgejo-cli is the Forgejo-native client. Its release publishes binaries and
# no checksum file, so this is the one hardcoded hash in the image and a
# version bump fails the build until it is recomputed — deliberate: a silently
# wrong binary is worse than a red build.
# renovate: datasource=forgejo-releases registryUrl=https://codeberg.org depName=forgejo-contrib/forgejo-cli
ARG FJ_VERSION=v0.7.0
ARG FJ_SHA256=6803c12eed17bfadb40ba95da2a6ab58f9b4a7dc10eabfe3512fce7e2fe6216f

# OpenCode (the agent) and OpenChamber (its web UI) are the workspace's IDE
# pair, which the baked startup contract runs.
# renovate: datasource=npm depName=@opencode/cli
ARG OPENCODE_VERSION=2.1.4
# renovate: datasource=npm depName=@openchamber/web
ARG OPENCHAMBER_VERSION=2.5.1

# Without a locale the agent and terminal sessions mangle non-ASCII output from
# git, jq and the Coder CLI.
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# One apt layer: one cache, one cleanup, and every layer below may assume its
# system dependencies. jq serves the Go checksum, xz the Node tarball,
# build-essential cgo.
#
# iputils-ping works without CAP_NET_RAW only while the nodes keep
# net.ipv4.ping_group_range covering gid 1000; a node that resets that sysctl
# takes ping away, and restricted PSS forbids the raw-socket fallback.
#
# python3-pip/venv/dev plus Debian's own pipx: the distro interpreter is the
# workspace python, and an apt pipx stays in system paths where the PVC cannot
# shadow it. EXTERNALLY-MANAGED is removed so the PEP 668 refusal does not
# block pip install --user, venv and pipx, which land on the PVC. A plain
# pip install into the system site-packages would fail EROFS on the
# read-only root filesystem anyway.
#
# The removal has no -f: trixie's python3.13 always ships the marker, so a
# missing path means the base moved to a new python minor. Failing here is the
# signal; a skipped removal would resurface as a pip error inside a workspace.
#
# localedef writes the locale archive directly. Debian's locale-gen ignores
# its argument form unless the locale is also uncommented in /etc/locale.gen:
# it exits 0 having generated nothing (proven against the published image
# layer — /etc/locale.gen present, no /usr/lib/locale archive), so every
# shell logged "setlocale: LC_ALL: cannot change locale". The locale -a
# assertion makes that silent no-op impossible.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
         ca-certificates curl wget locales openssh-client \
         jq unzip zip xz-utils rsync vim htop less man-db iproute2 procps \
         build-essential tzdata iputils-ping netcat-openbsd \
         git git-lfs python3 python3-pip python3-venv python3-dev pipx \
 && localedef -i en_US -f UTF-8 en_US.UTF-8 \
 && locale -a | grep -qx 'en_US.utf8' \
 && git lfs install --system \
 && rm /usr/lib/python3.13/EXTERNALLY-MANAGED \
 && rm -rf /var/lib/apt/lists/*

# Checksums are fetched from each vendor's own channel instead of being
# hardcoded, so a renovate bump cannot strand the build on a stale hash. The
# version assertion at the end of every layer is the real drift gate: it fails
# the build when the artifact is not the pinned release.
#
# npm has no pin of its own — it ships inside the checksum-verified node
# tarball, so the assertion compares it against the bundled copy: drift here
# means a stray or broken npm on PATH, not a new version.
RUN curl -fsSL -o "/tmp/node-${NODE_VERSION}-linux-x64.tar.xz" "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" \
 && curl -fsSL -o /tmp/SHASUMS256.txt "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" \
 && (cd /tmp && grep " node-${NODE_VERSION}-linux-x64.tar.xz$" SHASUMS256.txt | sha256sum -c -) \
 && tar -xJf "/tmp/node-${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 \
 && rm -f "/tmp/node-${NODE_VERSION}-linux-x64.tar.xz" /tmp/SHASUMS256.txt \
 && test "$(node --version)" = "${NODE_VERSION}" \
 && test "$(npm --version)" = "$(node -p 'require("/usr/local/lib/node_modules/npm/package.json").version')"

RUN curl -fsSL -o /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
 && curl -fsSL -o /tmp/go.json "https://go.dev/dl/?mode=json&include=all" \
 && echo "$(jq -r --arg f "go${GO_VERSION}.linux-amd64.tar.gz" '.[] | .files[] | select(.filename == $f) | .sha256' /tmp/go.json)  /tmp/go.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/go.tar.gz -C /usr/local \
 && rm -f /tmp/go.tar.gz /tmp/go.json \
 && /usr/local/go/bin/go version | grep -q "go${GO_VERSION} "

RUN curl -fsSL -o "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz" "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
 && curl -fsSL -o "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" \
 && (cd /tmp && sha256sum -c "helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum") \
 && tar -xzf "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz" -C /tmp linux-amd64/helm \
 && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
 && rm -rf "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz" "/tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" /tmp/linux-amd64 \
 && helm version --short | grep -q "^${HELM_VERSION}"

RUN curl -fsSL -o /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && curl -fsSL -o /tmp/kubectl.sha256 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
 && echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum -c - \
 && install -m 0755 /tmp/kubectl /usr/local/bin/kubectl \
 && rm -f /tmp/kubectl /tmp/kubectl.sha256 \
 && kubectl version --client | grep -q "${KUBECTL_VERSION}"

RUN curl -fsSL -o /tmp/uv-x86_64-unknown-linux-gnu.tar.gz "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" \
 && curl -fsSL -o /tmp/uv-x86_64-unknown-linux-gnu.tar.gz.sha256 "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz.sha256" \
 && (cd /tmp && sha256sum -c "uv-x86_64-unknown-linux-gnu.tar.gz.sha256") \
 && tar -xzf /tmp/uv-x86_64-unknown-linux-gnu.tar.gz -C /tmp uv-x86_64-unknown-linux-gnu/uv uv-x86_64-unknown-linux-gnu/uvx \
 && install -m 0755 /tmp/uv-x86_64-unknown-linux-gnu/uv /tmp/uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/ \
 && rm -rf /tmp/uv-x86_64-unknown-linux-gnu /tmp/uv-x86_64-unknown-linux-gnu.tar.gz /tmp/uv-x86_64-unknown-linux-gnu.tar.gz.sha256 \
 && uv --version | grep -q "${UV_VERSION}" \
 && uvx --version | grep -q "${UV_VERSION}"

RUN curl -fsSL -o /tmp/fj.tar.gz "https://codeberg.org/forgejo-contrib/forgejo-cli/releases/download/${FJ_VERSION}/forgejo-cli-x86_64-linux.tar.gz" \
 && echo "${FJ_SHA256}  /tmp/fj.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/fj.tar.gz -C /tmp fj \
 && install -m 0755 /tmp/fj /usr/local/bin/fj \
 && rm -f /tmp/fj.tar.gz /tmp/fj \
 && fj version | grep -qx "fj ${FJ_VERSION}"

# --ignore-scripts keeps install-time code from running unreviewed
# (supply-chain stance). @opencode/cli ships a stub that exits 1 until its
# postinstall has copied the platform binary into bin/, so that copy is run
# explicitly; @openchamber/web ships no install scripts. Both version probes
# are hard assertions: a half-installed CLI would only surface inside a user's
# workspace.
RUN npm install -g --ignore-scripts "@opencode/cli@${OPENCODE_VERSION}" "@openchamber/web@${OPENCHAMBER_VERSION}" \
 && (opencode --version || node /usr/local/lib/node_modules/@opencode/cli/postinstall.mjs) \
 && opencode --version | grep -q "${OPENCODE_VERSION}" \
 && openchamber --version | grep -qx "${OPENCHAMBER_VERSION}" \
 && npm cache clean --force

# coder at 1000:1000: the pod's runAsUser and the home PVC ownership both
# assume that id. Debian slim ships no uid-1000 account, so it is created
# outright. -m seeds /home/coder from /etc/skel at build time; the startup
# script re-seeds from /etc/skel on first boot because the PVC shadows that
# copy on existing workspaces.
# Core dumps are off: workspace PVCs otherwise fill up with multi-GB cores.
RUN groupadd --gid 1000 coder \
 && useradd --uid 1000 --gid 1000 --create-home --home-dir /home/coder --shell /bin/bash coder \
 && test "$(id -u coder)" = "1000" \
 && test "$(id -g coder)" = "1000" \
 && install -d -m 0755 /etc/security/limits.d \
 && printf '%s\n' '* hard core 0' '* soft core 0' > /etc/security/limits.d/99-nocore.conf \
 && printf '%s\n' \
         '# pipx-installed tools and ~/bin on PATH. Harmless when the directories do not exist.' \
         'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"' \
         '# Keep core dumps off (see /etc/security/limits.d/99-nocore.conf).' \
         'ulimit -S -c 0 2>/dev/null || true' \
         > /etc/profile.d/dev-tools.sh

COPY --chmod=0755 workspace-startup.sh /usr/local/bin/workspace-startup.sh

# HOME/USER/XDG/TMPDIR/PATH for non-login shells and for the agent, which does
# not start through a login shell. XDG_* + TMPDIR keep runtime writes on the PVC
# and the /tmp emptyDir, which is what makes readOnlyRootFilesystem viable.
# /home/coder is hardcoded because Docker expands $HOME at build time from the
# base image's env, which does not set it.
ENV HOME=/home/coder \
    USER=coder \
    XDG_DATA_HOME=/home/coder/.local/share \
    XDG_CONFIG_HOME=/home/coder/.config \
    XDG_CACHE_HOME=/home/coder/.cache \
    TMPDIR=/tmp \
    GOPATH=/home/coder/go \
    PATH=/home/coder/.local/bin:/home/coder/bin:/usr/local/go/bin:/home/coder/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Numeric user: unambiguous for runAsNonRoot admission.
USER 1000:1000
WORKDIR /home/coder
