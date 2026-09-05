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

# Install package sources first (leverage layer cache)
COPY pyproject.toml README.md ./
COPY wekan_mcp ./wekan_mcp

RUN pip install . && \
    # non-root user for the server process
    useradd --create-home --uid 10001 mcp && \
    chown -R mcp:mcp /app

USER 10001

EXPOSE 8080

# The console entry point registered by pyproject.toml.
CMD ["wekan-mcp"]
