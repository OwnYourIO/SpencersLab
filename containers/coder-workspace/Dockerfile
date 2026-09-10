# Coder workspace base image for SpencersLab — pinned Ubuntu 26.04 base with
# the whole toolchain baked in, so the workspace cannot drift under us.
#
# Designed for Kubernetes "restricted" Pod Security Standards:
#   - runs as uid/gid 1000 (runAsNonRoot); no sudo / setuid escalation baked in
#   - everything needed at runtime is installed at BUILD time; the pod is
#     expected to set readOnlyRootFilesystem: true, allowPrivilegeEscalation:
#     false, capabilities.drop: [ALL], seccompProfile: RuntimeDefault, plus a
#     writable /tmp emptyDir and the home PVC
#   - runtime writes must land in $HOME (PVC) or /tmp (emptyDir); the XDG_* and
#     TMPDIR env vars below steer well-behaved tools there
#
# Node policy: the baked-in Node.js is THE node for all workspaces. No nvm is
# installed or expected; templates/startup scripts must not install other node
# versions.
#
# Python policy: Ubuntu 26.04 (resolute) ships python3 3.14.3 as the distro
# default (verified via packages.ubuntu.com), so no deadsnakes PPA and no
# update-alternatives switch are needed; pipx is installed for that distro
# python via pip below.
#
# Built and pushed by .github/workflows/docker-build.yaml as
# ghcr.io/ownyourio/coder-workspace. No ENTRYPOINT: the Coder workspace
# template supplies the agent bootstrap script.
#
# Layout constraint: on existing workspaces /home/coder is a PVC mount that
# shadows anything baked into the image at that path. All tooling therefore
# lives in system paths (/usr/local, /etc); /home/coder is only created and
# chowned for fresh workspaces.

# ubuntu:26.04 pinned by digest (multi-arch index, resolved 2026-09-06)
FROM ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b

ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# --- Base apt layer -----------------------------------------------------------
# iputils-ping / netcat-openbsd: network troubleshooting under restricted PSS.
# ping needs no CAP_NET_RAW (unprivileged ICMP datagram sockets) provided the
# nodes keep net.ipv4.ping_group_range covering gid 1000; if a node ever
# resets that sysctl to a range excluding gid 1000, ping stops working.
# sudo is deliberately NOT installed: restricted PSS forbids privilege
# escalation, and with a read-only rootfs runtime apt is impossible anyway —
# anything ever needed must be baked in here.
# python3-pip / python3-venv: distro python 3.14 tooling; pipx is installed
# from pip below (the apt pipx package is avoided so it runs on the same
# interpreter the workspace uses).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release software-properties-common \
        locales openssh-client jq unzip zip xz-utils rsync \
        vim htop less man-db iproute2 procps build-essential tzdata \
        iputils-ping netcat-openbsd \
        python3-pip python3-venv \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

# --- PPA: git-core (current git) ----------------------------------------------
# git is reinstalled to pick up the PPA version; git-lfs rides along and is
# enabled system-wide.
RUN add-apt-repository -y ppa:git-core/ppa \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        git git-lfs \
 && git lfs install --system \
 && rm -rf /var/lib/apt/lists/*

# --- Node.js 26 (official static tarball; no nvm, by policy) --------------
# sha256 from https://nodejs.org/dist/v26.8.1/SHASUMS256.txt (resolved
# 2026-09-06). v26.8.1 bundles npm 11.19.0; the exact npm check below fails
# the build if that ever drifts.
RUN curl -fsSL -o /tmp/node.tar.xz https://nodejs.org/dist/v26.8.1/node-v26.8.1-linux-x64.tar.xz \
 && echo "3e301118d7df53d563b7e96c1617545f26e2f76f9724be668d6cab65c15dda5d  /tmp/node.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
 && rm -f /tmp/node.tar.xz \
 && node --version \
 && npm --version | grep -qx '11\.19\.0'

# --- Go toolchain -----------------------------------------------------------
# sha256 from https://go.dev/dl/ for go1.27.1.linux-amd64.tar.gz (resolved
# 2026-09-06). Extracted to /usr/local/go; /usr/local/go/bin is added to PATH
# in the ENV block below. GOPATH defaults to $HOME/go, which lands on the
# workspace PVC. build-essential (above) covers cgo.
RUN curl -fsSL -o /tmp/go.tar.gz https://go.dev/dl/go1.27.1.linux-amd64.tar.gz \
 && echo "63d339f0da5ab53635a56f2490a7984dfe12dfcff22ad749f63edaf590168445  /tmp/go.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/go.tar.gz -C /usr/local \
 && rm -f /tmp/go.tar.gz \
 && /usr/local/go/bin/go version

# --- helm ----------------------------------------------------------------------
# Helm v3: the lab's charts are rendered by ArgoCD with helm v3, so local
# validation stays on v3 for fidelity. sha256 verified against the value
# published in helm-v3.21.4-linux-amd64.tar.gz.sha256sum on get.helm.sh,
# hardcoded here so a compromised mirror cannot swap the artifact.
RUN curl -fsSL -o /tmp/helm.tar.gz https://get.helm.sh/helm-v3.21.4-linux-amd64.tar.gz \
 && echo "61f88ab166748cb19604d7884cb100ae9ccb13804ddeb98e08af167eacbb6a14  /tmp/helm.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/helm.tar.gz -C /tmp \
 && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
 && rm -rf /tmp/helm.tar.gz /tmp/linux-amd64 \
 && helm version --short

# --- kubectl --------------------------------------------------------------------
RUN curl -fsSL -o /tmp/kubectl https://dl.k8s.io/release/v1.36.4/bin/linux/amd64/kubectl \
 && echo "8b8f088da2dab964f853b38464033b1be15ede2839eca751482357c45abdd05a  /tmp/kubectl" | sha256sum -c - \
 && install -m 0755 /tmp/kubectl /usr/local/bin/kubectl \
 && rm -f /tmp/kubectl \
 && kubectl version --client

# --- coder user, hygiene ---------------------------------------------------------
# Official ubuntu base images ship a built-in `ubuntu` user/group at UID/GID
# 1000 with home /home/ubuntu (true on 24.04; image builds vary). If present,
# RENAME it rather than creating a second UID-1000 user (which would collide);
# otherwise create the coder user fresh. Either way, assert uid/gid 1000.
# -m carries the skel dotfiles over so the name/home match the workspace PVC
# mountPath and coder_app folder=/home/coder URLs.
# No sudo/sudoers: restricted PSS (allowPrivilegeEscalation: false) blocks
# setuid escalation anyway, and everything is baked in at build time.
# Core dumps are disabled: workspace PVCs otherwise accumulate multi-GB cores.
RUN if id ubuntu >/dev/null 2>&1; then \
        usermod -l coder -d /home/coder -m ubuntu \
     && groupmod -n coder ubuntu; \
    else \
        groupadd --gid 1000 coder \
     && useradd --uid 1000 --gid 1000 --create-home --home-dir /home/coder --shell /bin/bash coder; \
    fi \
 && test "$(id -u coder)" = "1000" \
 && test "$(id -g coder)" = "1000" \
 && printf '%s\n' '* hard core 0' '* soft core 0' > /etc/security/limits.d/99-nocore.conf \
 && printf '%s\n' \
        '# pipx-installed tools and ~/bin on PATH. Harmless when the directories do not exist.' \
        'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"' \
        '# Keep core dumps off (see /etc/security/limits.d/99-nocore.conf).' \
        'ulimit -S -c 0 2>/dev/null || true' \
        > /etc/profile.d/dev-tools.sh

# HOME/USER/XDG/TMPDIR/PATH for non-login shells and the coder agent (not started
# via a login shell, so /etc/profile.d alone is not enough). XDG_* + TMPDIR keep
# runtime tool writes on the PVC / emptyDir, which is what makes
# readOnlyRootFilesystem: true viable. Hardcoded /home/coder: Docker expands
# $HOME at build time from the base image (=/root), which would be wrong.
ENV HOME=/home/coder \
    USER=coder \
    XDG_DATA_HOME=/home/coder/.local/share \
    XDG_CONFIG_HOME=/home/coder/.config \
    XDG_CACHE_HOME=/home/coder/.cache \
    TMPDIR=/tmp \
    GOPATH=/home/coder/go \
    PATH=/home/coder/.local/bin:/home/coder/bin:/usr/local/go/bin:/home/coder/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- pipx ------------------------------------------------------------------------
# Run as the coder user (not root) so the venv and bins land in
# /home/coder/.local instead of root's home. On existing workspaces the PVC
# shadows this copy — those PVCs already carry their own pipx install; this
# baked copy serves fresh workspaces.
# Installed with the distro python 3.14's pip into the user site.
# PIP_BREAK_SYSTEM_PACKAGES covers the EXTERNALLY-MANAGED marker Ubuntu ships;
# it is a no-op otherwise.
USER coder
RUN PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --user pipx \
 && pipx --version

# Numeric user: unambiguous for runAsNonRoot admission. The Coder template
# supplies the agent bootstrap script; no ENTRYPOINT here.
USER 1000:1000
WORKDIR /home/coder
