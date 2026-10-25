# Sources

[1] containers/kubernetes-mcp-server releases (v0.0.1–v0.0.69, dates+changelogs) — https://github.com/containers/kubernetes-mcp-server/releases
[2] PR #1423 "Config rework" (merged 2026-09-18) — https://github.com/containers/kubernetes-mcp-server/pull/1423
[3] root.go at v0.0.65 (flag definitions) — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.65/pkg/kubernetes-mcp-server/cmd/root.go
[4] root.go at v0.0.69 (collapsed CLI + help text matching incident) — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/pkg/kubernetes-mcp-server/cmd/root.go
[5] Configuration Changes doc at v0.0.69 (dropped flag table, migration) — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/docs/configuration-changes.md
[6] Configuration Reference (main branch, fetched 2026-10-25) — https://github.com/containers/kubernetes-mcp-server/blob/main/docs/configuration.md
[7] pkg/http/http.go at v0.0.69 (/mcp, /healthz endpoints) — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/pkg/http/http.go
[8] npm wrapper docs confirming --config/--config-dir CLI (secondary) — https://www.npmjs.com/package/kubernetes-mcp-server
[9] MCPServer CRD types at toolhive v0.56.0 — https://raw.githubusercontent.com/stacklok/toolhive/v0.56.0/cmd/thv-operator/api/v1beta1/mcpserver_types.go
[10] ToolHive releases v0.50.0–v0.56.0 (changelogs) — https://github.com/stacklok/toolhive/releases
[11] Remove embedded registry.json in favour of toolhive-catalog (2026-02-21) — https://github.com/stacklok/toolhive/commit/8abdc0438
[12] stacklok/toolhive-catalog (193 servers, no kubernetes-mcp-server entry) — https://github.com/stacklok/toolhive-catalog
[13] Last embedded registry.json (no kubernetes-mcp-server entry) — https://raw.githubusercontent.com/stacklok/toolhive/80c3133f1/pkg/registry/data/registry.json
[14] Upstream chart values (configFilePath, config, extraArgs note) — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/charts/kubernetes-mcp-server/values.yaml
[15] Upstream chart deployment (--config args + ConfigMap mount) — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/charts/kubernetes-mcp-server/templates/deployment.yaml
[16] Upstream chart configmap (toToml) — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/charts/kubernetes-mcp-server/templates/configmap.yaml
[17] ghcr tags list (fetched 2026-10-25 with anonymous pull token) — https://ghcr.io/v2/containers/kubernetes-mcp-server/tags/list
[18] v0.0.65 manifest digest sha256:5df586e2… — https://ghcr.io/v2/containers/kubernetes-mcp-server/manifests/v0.0.65
[19] v0.0.69 manifest digest sha256:1da9d62a… — https://ghcr.io/v2/containers/kubernetes-mcp-server/manifests/v0.0.69
[20] Issue #1560: v0.0.68 container release failed; multi-platform image tag missing — https://github.com/containers/kubernetes-mcp-server/issues/1560
[21] release-image.yml: GHCR image built from root Dockerfile — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/.github/workflows/release-image.yml
[22] Dockerfile at v0.0.69 (baked config + ENV MCP_CONFIG_PATH + USER 65532) — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/Dockerfile
[23] Image default config: port = "8080" — https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/mcp-config-container-defaults.toml
[24] PR #1455 restore Streamable HTTP behind kube-rbac-proxy (disable_localhost_protection origin) — https://github.com/containers/kubernetes-mcp-server/pull/1455
