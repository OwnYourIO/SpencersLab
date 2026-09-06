# Add Hivetools MCP Servers to Kilo & Cline Config

## Goal
Add all enabled MCP servers from `charts/hivetools/values.yaml` to the Kilo CLI MCP config (`~/.config/kilo/kilo.jsonc`) and the Cline VS Code MCP config (`cline_mcp_settings.json`). Playwright is already present in both.

## MCP Servers to Add

From `charts/hivetools/values.yaml`, these servers are enabled and not yet in Kilo config:

| Server | Transport | mcpPort | URL |
|--------|-----------|---------|-----|
| git | stdio | 8080 | `http://mcp-git-proxy.default:8080/mcp` |
| github | stdio | 8080 | `http://mcp-github-proxy.default:8080/mcp` |
| homeassistant | streamable-http | 8080 | `http://mcp-homeassistant-proxy.default:8080/mcp` |
| kubernetes | streamable-http | 8080 | `http://mcp-kubernetes-proxy.default:8080/mcp` |
| fetch | stdio | 8080 | `http://mcp-fetch-proxy.default:8080/mcp` |
| filesystem | stdio | 8080 | `http://mcp-filesystem-proxy.default:8080/mcp` |
| onemcp | streamable-http | 3050 | `http://mcp-onemcp-proxy.default:3050/mcp` |
| sequential-thinking | stdio | 8080 | `http://mcp-sequential-thinking-proxy.default:8080/mcp` |
| firecrawl | streamable-http | 8080 | `http://mcp-firecrawl-proxy.default:8080/mcp` |
| searxng | stdio | 8080 | `http://mcp-searxng-proxy.default:8080/mcp` |

**Already configured (skip):** playwright

## Files to Modify

### 1. `/home/coder/.config/kilo/kilo.jsonc`

Add entries under the existing `"mcp"` block (playwright is already there). Use `"type": "remote"` for all servers. Each entry:

```jsonc
"<name>": {
  "type": "remote",
  "url": "http://mcp-<name>-proxy.default:<mcpPort>/mcp",
  "enabled": true,
  "timeout": 60000
}
```

### 2. `/home/coder/.vscode-server/data/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json`

Add entries under the existing `"mcpServers"` block (playwright is already there). Use `"type": "streamableHttp"` for all servers (ToolHive proxy exposes HTTP for both stdio and streamable-http backends). Each entry:

```json
"<name>": {
  "autoApprove": [],
  "disabled": false,
  "timeout": 60,
  "type": "streamableHttp",
  "url": "http://mcp-<name>-proxy.default:<mcpPort>/mcp"
}
```

## Notes
- All URLs use the `-proxy` service pattern per user preference
- The `kilo.jsonc` file uses JSONC format (comments allowed) — preserve existing formatting
- The Cline config uses strict JSON — preserve existing formatting
- Port values come from each server's `mcpPort` in `values.yaml`

## Validation
- Verify `kilo.jsonc` is valid JSONC after editing
- Verify `cline_mcp_settings.json` is valid JSON after editing
- Optionally test connectivity: `curl -s http://mcp-<name>-proxy.default:<mcpPort>/mcp` from within the cluster
