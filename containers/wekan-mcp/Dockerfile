# WeKan MCP server image for ToolHive on Kubernetes.
#
# Build:
#   docker build -t registry.example.com/wekan-mcp:0.1.0 .
# Push:
#   docker push registry.example.com/wekan-mcp:0.1.0
#
# The image runs as a non-root user, exposes 8080, and starts the
# streamable-http server. WEKAN_BASE_URL and WEKAN_TOKEN come from
# the environment at runtime (injected by ToolHive's MCPServer resource).

FROM python:3.12-slim

# Don't buffer logs; write .pyc off; keep the image small
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Install package sources first (leverage layer cache).
# VERSION is required by setuptools' dynamic version in pyproject.toml.
COPY pyproject.toml README.md VERSION ./
COPY wekan_mcp ./wekan_mcp

RUN pip install . && \
    # non-root user for the server process (uid 65532 per repo convention)
    groupadd --system --gid 65532 mcp && \
    useradd --system --uid 65532 --gid 65532 --shell /bin/false \
        --home /home/mcp --create-home mcp && \
    chown -R mcp:mcp /app

USER 65532

EXPOSE 8080

# The console entry point registered by pyproject.toml.
ENTRYPOINT ["wekan-mcp"]
