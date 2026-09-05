# Connecting Claude Desktop to the in-cluster WeKan MCP server

Once the `MCPServer` resource is `Ready`, the ToolHive operator has created:

- a Deployment `wekan` (the MCP server pod)
- a proxy Deployment `mcp-wekan-proxy` (or similar) and a Service exposing streamable-http

Confirm:

```
kubectl get mcpserver -n toolhive-system wekan
kubectl get svc      -n toolhive-system | grep wekan
kubectl logs         -n toolhive-system deploy/wekan
```

The proxy Service DNS is roughly:

```
mcp-wekan-proxy.toolhive-system.svc.cluster.local:8080
```

with an MCP endpoint at `/mcp`.

## Option A — port-forward (fastest for solo use)

Forward the proxy Service to your workstation:

```
kubectl port-forward -n toolhive-system svc/mcp-wekan-proxy 8080:8080
```

Then register it in Claude Desktop as a remote connector. In Claude Desktop:

**Settings → Connectors → Add custom connector**

- Name: `wekan`
- URL: `http://localhost:8080/mcp`
- Authentication: none (or bearer, if you added auth in front)

Claude Desktop's `claude_desktop_config.json` `mcpServers.command`/`args` form
is stdio-only. Remote HTTP/SSE MCP servers belong under the custom-connector UI.

## Option B — expose via ingress / gateway (small team)

For a few teammates to share the server, expose the proxy Service through
your ingress controller with TLS. Put an auth layer in front — options:

1. **Bearer/JWT gate at the ingress.** Add a middleware (e.g. Traefik
   `ForwardAuth`, NGINX `auth_request`) that validates a shared or per-user
   token before proxying to the ToolHive Service.
2. **ToolHive's embedded OIDC/OAuth.** Configure an `MCPExternalAuthConfig`
   and reference it from `MCPServer.spec.authServerRef` to require OIDC
   at the proxy layer (see docs.stacklok.com/toolhive/guides-k8s for details).

Then in each user's Claude Desktop, add the ingress URL as a custom connector
with the appropriate bearer token.

**Caveat**: the same WeKan token backs every session unless you set up a
per-user WeKan token → per-user MCP identity mapping. Every WeKan action
will appear in WeKan's own audit log as coming from that one service user.
Mitigations: (a) provision a dedicated, least-privilege WeKan user for the
token; (b) have tools prefix comments/descriptions with `[via AI]`; (c) log
tool calls with the requesting identity server-side.

## Verifying the server responds

Once port-forwarded, a raw JSON-RPC request should list the tools:

```
curl -sS -X POST http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

You should get back the 13 tools (`list_boards`, `get_board`, ..., `toggle_checklist_item`).
