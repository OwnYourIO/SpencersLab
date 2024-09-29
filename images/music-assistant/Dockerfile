ARG REPO=ghcr.io/music-assistant/server
ARG TAG=2.2.6
FROM ${REPO}:${TAG}
RUN  apt-get update \
    # install roc-toolkit from 
    && wget https://github.com/roc-streaming/roc-toolkit/releases/download/v0.4.0/roc_0.4.0_amd64.deb \
    && wget https://github.com/roc-streaming/roc-toolkit/releases/download/v0.4.0/libroc_0.4.0_amd64.deb \
    && wget https://github.com/roc-streaming/roc-toolkit/releases/download/v0.4.0/libroc-dev_0.4.0_amd64.deb \
    && apt-get install -y vim ./*.deb \
    && rm ./*deb \
    # cleanup
    && rm -rf /tmp/* \
    && rm -rf /var/lib/apt/lists/*

