# renovate-mcp — design-time Renovate config tooling (stdio MCP server).
# Served by ToolHive MCPServer "renovate" in namespace default.
#
# Transport (2026-09-27): the MCPServer uses streamable-http; this image
# bridges stdio → Streamable HTTP with supergateway (the MCPServer
# podTemplateSpec overrides the entrypoint to run `supergateway --stdio
# renovate-mcp --outputTransport streamableHttp --port 8080`). The stdio
# proxyrunner attach is avoided because it dies permanently after transient
# apiserver outages (see
# .agents/plans/2026-09-27-debug-mcp-servers-longterm-fix.md). The ENTRYPOINT
# below is kept as-is: reverting the MCPServer to `transport: stdio` still
# works with this image (supergateway is additive).
#
# node:26-bookworm-slim pinned by digest (multi-arch index). Debian, NOT
# Alpine: Renovate's native deps (re2, better-sqlite3) need glibc. git is
# required because dry-run/local-platform operate on a git working tree.
#
# Built and pushed by .github/workflows/docker-build.yaml as
# ghcr.io/ownyourio/renovate-mcp. No ENTRYPOINT args: the MCPServer supplies
# runtime configuration via env (RENOVATE_BASE_DIR, RENOVATE_MCP_REQUIRE_CLI).
FROM node:26-bookworm-slim@sha256:367679cf9792759492a486e4aa4b421764d71a9546a6dae8aab81a99eb797b3e

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pinned; renovate ships bundled as a runtime dependency of the package.
# npm 12 blocks package install scripts by default, so re2's native binary is
# NOT built here — Renovate detects the missing module at runtime and falls
# back to native RegExp (warning only). Acceptable for design-time use; if
# re2 ever becomes required, rebuild with --allow-scripts plus build tooling.
# renovate: datasource=npm depName=renovate-mcp
# renovate: datasource=npm depName=supergateway
RUN npm install -g renovate-mcp@1.4.11 supergateway@4.0.0

# The official node image already ships a "node" user at uid/gid 1000 —
# exactly the runAsUser the MCPServer podTemplateSpec securityContext sets.
# Do NOT groupadd/useradd 1000 here: the GID/UID are taken (exit code 4).
USER 1000:1000

ENV NODE_ENV=production
# stdio server by default (ToolHive stdio fallback); the streamable-http
# deployment overrides this with `supergateway` (see header + values.yaml).
ENTRYPOINT ["renovate-mcp"]
