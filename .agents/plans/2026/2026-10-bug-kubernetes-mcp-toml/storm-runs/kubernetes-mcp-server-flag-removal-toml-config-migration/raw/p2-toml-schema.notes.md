# P2 — TOML config schema authority

Primary reference: docs/configuration.md (fetched from main 2026-10-25; drift risk vs v0.0.69 is small — all keys below are corroborated by v0.0.69-tagged docs/source). Migration doc: docs/configuration-changes.md (v0.0.69 tag).

## Precedence (each option resolved once per load, later overrides earlier)
1. Defaults → 2. main config file (--config, or $MCP_CONFIG_PATH if flag unset) → 3. --config-dir drop-ins (lexical order) → 4. env vars (only where declared; empty = no override) → 5. CLI (only selects files).

## Drop-in merge semantics
- --config-dir loads every .toml in the dir in LEXICAL order; usable ALONE or layered on --config. Numeric prefixes control order (00-base.toml … 99-override.toml). Dotfiles ignored. Partial files allowed.
- Merge: values present in a later file override earlier; missing values preserved. Last file setting a key is its recorded source.
- Unknown key in ANY file fails the whole load (startup and SIGHUP exit non-zero).
- GOTCHA: a sibling conf.d/ next to --config is NOT auto-loaded anymore (v0.0.65 did implicit lookup); if such a dir exists with .toml files and --config-dir is not passed, startup fails with instructions.
- Recommend numeric-prefixed file names.

## Keys the lab needs (verbatim semantics from docs)
- `port` (string, default "") — "When set, starts the MCP server in HTTP mode (Streamable HTTP at /mcp) on the specified port." STRING, e.g. port = "8080". Empty port = stdio mode.
- `bind_address` (string, default "0.0.0.0").
- `stateless` (bool, default false) — "disables tool and prompt change notifications. Useful for container deployments, load balancing, and serverless environments." Non-reloadable (restart required).
- `read_only` (bool, default false) — "only exposes tools annotated with readOnlyHint=true. Prevents any write operations on the cluster." Reloadable.
- `disable_destructive` (bool, default false) — no effect when read_only=true.
- `kubeconfig` (string, default "") — empty → in-cluster config or $KUBECONFIG/~/.kube/config (client-go fallback). Pod auto-detects in-cluster; explicit path overrides detection.
- `cluster_provider_strategy` — kubeconfig|in-cluster|kcp|disabled (auto-detect default).
- `toolsets` (string[], default ["core","config"]).
- `enabled_tools` / `disabled_tools` (string[]) — allowlist then denylist. `configuration_view` disabled by default in HTTP mode since v0.0.68.
- `denied_resources` (array of {group,version,kind} tables).
- `log_level` (int 0-9, default 0), `log_file` (string; required for stdio logging; "stderr" special value), `list_output` ("table"|"yaml", default "table").
- `metrics_port` (string) — separate metrics/stats/healthz server.
- `trust_proxy_headers` (bool, default false), `server_url`, OAuth block (require_oauth, oauth_audience, authorization_url, skip_jwt_verification, token_exchange.*).
- `disable_localhost_protection` (bool, default false) — disables the go-sdk DNS-rebinding/loopback Host check; ONLY for trusted-proxy-to-loopback sidecar pattern (kube-rbac-proxy), combined with bind_address="127.0.0.1". Not needed when the proxy reaches the server via pod IP (traffic to podIP:port never hits the Host check).
- `[http]` table: read_header_timeout (default "10s"), max_body_bytes (16MB), rate_limit_rps/burst.
- Memory bounds: max_backend_response_bytes (4MB), max_result_bytes (16MB), max_in_flight (64).
- SIGHUP reload supported with --config/--config-dir; port/stateless/kubeconfig etc. require restart.

## Env-var config
- MCP_CONFIG_PATH points at the main config file (renamed from K8S_MCP_CONFIG_PATH, NO shim, v0.0.68+). --config flag wins over env.
- No env vars for port/stateless/read_only ("No new K8S_MCP_* names were added for dropped flags"). Env-var config of runtime settings is NOT an alternative to the file for these keys — the file (or drop-ins) is required.
- Image bakes /etc/kubernetes-mcp-server/config.toml (`port = "8080"`) + ENV MCP_CONFIG_PATH → zero-arg start serves HTTP :8080 stateful with write tools visible (do not rely on this for lab tiers).

## Upstream verbatim example (configuration-changes.md migration example)
before: kubernetes-mcp-server --port 8080 --log-level 2 --kubeconfig ~/.kube/config --toolsets core,config,helm
after (config.toml):
  port = "8080"
  log_level = 2
  kubeconfig = "/home/user/.kube/config"
  toolsets = ["core", "config", "helm"]
run: kubernetes-mcp-server --config config.toml

## Drop-in example (docs)
10-toolsets.toml: toolsets = ["core", "config", "helm", "kubevirt"]
99-local.toml: log_level = 9 / read_only = true
