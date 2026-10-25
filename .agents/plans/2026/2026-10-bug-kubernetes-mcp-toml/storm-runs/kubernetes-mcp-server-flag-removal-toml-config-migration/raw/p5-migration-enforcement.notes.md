# P5 — Migration & enforcement engineer

## Exact mapping for the lab's two tiers (v0.0.65 flags → v0.0.69 TOML)
readonly tier args: --port 8080 --stateless --read-only  →
  port = "8080"
  stateless = true
  read_only = true
admin tier args: --port 8080 --stateless  →
  port = "8080"
  stateless = true

- port is a STRING in TOML. stateless/read_only are bools. Semantics carry over 1:1 (read_only = expose only readOnlyHint=true tools; stateless = disable tool/prompt change notifications).
- No kubeconfig key needed: empty kubeconfig → in-cluster config (the pod's ServiceAccount), same as before. Optionally pin cluster_provider_strategy = "in-cluster".
- toolsets default ["core","config"] — same default as v0.0.65 (lab never set --toolsets), no key needed.

## Flags with no 1:1 future-proof equivalent / behavior deltas
- --sse-base-url: gone (SSE-era; lab never used it).
- configuration_view tool now DISABLED by default in HTTP mode since v0.0.68 (exposes kubeconfig contents) — the tool disappears from tools/list after migration; acceptable/desirable for the lab.
- K8S_MCP_CONFIG_PATH env renamed to MCP_CONFIG_PATH with no shim (irrelevant to lab; we pass --config).
- Unknown TOML keys fail startup — keep ConfigMap TOML minimal and exact.

## Read-only enforcement after migration
- read_only = true survives as a config boolean (same server-side tool hiding as --read-only). Defense in depth unchanged: RBAC is still the real boundary per lab model (skills/helm-chart-creation/references/mcp-servers.md) — readonly SA has read tier only, no secrets/exec; --read-only/read_only only hides write tools from tools/list.
- Admin tier: write tools remain visible; RBAC restart-tier scoping unchanged.

## Allowed-hosts / DNS-rebinding
- kubernetes-mcp-server has NO allowed-hosts config (unlike mcp-grafana's --allowed-hosts). The only Host-based check is the go-sdk loopback DNS-rebinding protection, which only fires when the request was accepted on a loopback address. ToolHive's proxy Deployment reaches the backend via pod IP → the check never fires → disable_localhost_protection NOT needed. (It exists for kube-rbac-proxy-style sidecars forwarding to 127.0.0.1; PR #1455.)

## /mcp path + ingress
- HTTP mode serves Streamable HTTP at /mcp (unchanged from v0.0.65; confirmed in v0.0.69 pkg/http/http.go: mcpEndpoint = "/mcp", plus /healthz, /stats, /metrics). Lab ingress (mcp-mcp-<name>-proxy:8080, path /<name> stripped to /mcp by normalize-mcp-path middleware) is unaffected.
- bind_address default 0.0.0.0 → pod listens on all interfaces inside the pod netns, same as --port before. No change needed.
- Optional: since servers run stateless, MCPServer sessionAffinity: None is supportable (CRD default ClientIP) — not required; previous setup ran stateful-affinity fine.

## Delivery mechanism verdict (ToolHive)
- MCPServer spec.volumes is hostPath-only → ConfigMap must come via podTemplateSpec (volumes + volumeMounts on container named "mcp"). The hivetools chart passes podTemplateSpec through verbatim; the lab already uses it for securityContext + /tmp emptyDir on these exact servers.
- Recommended shape (mirrors upstream chart): args ["--config","/etc/kubernetes-mcp-server/config.toml"]; ConfigMap key config.toml mounted at /etc/kubernetes-mcp-server/config.toml (subPath) or the directory. Mount shadows the image-baked default file; fine under readOnlyRootFilesystem.
- Alternative (works but implicit): mount the ConfigMap over /etc/kubernetes-mcp-server/config.toml and pass NO args (image ENV MCP_CONFIG_PATH finds it). Explicit --config is clearer and survives image default changes.
- Env-var-only config is NOT an option for port/stateless/read_only (no env names for dropped flags).
