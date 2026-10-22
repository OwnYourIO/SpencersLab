# Packs shirayu/llama_swap_config_autogen as a dependency-baked image so
# llama-swap's config-generation initContainer needs no PyPI egress at boot.
# Upstream ships no PyPI package and no release tags, so the only immutable
# pin is the commit SHA below; the CI-pushed :v<run> tag anchors the build
# afterwards.

FROM python:3.12.15-slim-bookworm

# renovate: datasource=git-refs depName=shirayu/llama_swap_config_autogen
ARG AUTOGEN_COMMIT=c7357e68c755b54557f5b0f88b0507bf1c981500

# Archive-tarball URL instead of git+https: the image needs no `git` binary.
RUN pip install --no-cache-dir "llama-swap-config-autogen @ https://github.com/shirayu/llama_swap_config_autogen/archive/${AUTOGEN_COMMIT}.tar.gz"

RUN groupadd --system --gid 65532 autogen \
    && useradd --system --uid 65532 --gid 65532 --shell /bin/false \
        --home /home/autogen --create-home autogen

USER 65532:65532

ENTRYPOINT ["llama-swap-config-autogen"]
