# STORM report — kubernetes-mcp-server flag removal / TOML config migration

**Reliability notes**
- Confidence: 9/10 on root cause (multi-source: repo git history, upstream releases/PRs/source, ghcr digests, verbatim usage-text match). 10/10 on the TOML key mapping for the four keys the fix needs (tag-pinned upstream migration doc).
- Weakest claim: "no behavioral regressions in v0.0.69" — based on an issue search window (created >2026-10-01), which cannot catch unreported problems; verify post-deploy via tools/list + a read call.
- Over-weight check: P4 forensics dominates because the incident's central mystery was attribution; P2/P5 findings are independently corroborated by tag-pinned upstream docs.
- One declared drift risk: the full configuration.md reference was read from `main`, not the v0.0.69 tag (all fix-relevant keys cross-checked against v0.0.69-tagged docs/source).
- Missing 6th angle: live-cluster verification (the MCP path into the clusters is the thing that's down) — the plan must include direct kubectl verification steps run by the user.

## 1. Root cause

The crash is **not** caused by the ToolHive operator upgrade. It is caused by Renovate's image bump `ghcr.io/containers/kubernetes-mcp-server:v0.0.65 → v0.0.69`, merged to main 2026-10-25T15:14 UTC (PR #704, commit 4922af75d) ~40 minutes after the toolhive-operator 0.50.0→0.56.0 merges (PRs #787/#788) in the same operator session [local git; 1].

Upstream **v0.0.68** (2026-10-22) shipped "Config rework" (PR #1423, merged 2026-09-18), which removed every runtime CLI flag; the CLI collapsed to `--config` / `--config-dir` / `--version` and HTTP mode now requires `port` set in TOML [1][2][5]. v0.0.69 (2026-10-23) is v0.0.68 + CI/build fixes only [1]. The incident's usage output matches v0.0.69's root.go help strings verbatim [4]. v0.0.65 is provably flag-based (--port/--stateless/--read-only defined at the tag) [3], and its ghcr digest is intact (no re-tag) [17][18][19].

Renovate jumped v0.0.65→v0.0.69 (skipping v0.0.66–v0.0.68) because the v0.0.68 multi-arch container release failed — no `v0.0.68` index tag exists on ghcr (issue #1560) [17][20].

## 2. TOML schema (fix-relevant subset, exact)

Precedence per load: defaults < `--config` file (or `$MCP_CONFIG_PATH` env if flag unset) < `--config-dir` drop-ins (lexical order) < env vars (where declared) [5][6].

| Key | Type | Default | Meaning |
|---|---|---|---|
| `port` | **string** | `""` | set → HTTP mode, Streamable HTTP at `/mcp`; empty → stdio [5][6] |
| `bind_address` | string | `"0.0.0.0"` | listen address [6] |
| `stateless` | bool | `false` | disables tool/prompt change notifications; restart-only [5][6] |
| `read_only` | bool | `false` | expose only `readOnlyHint=true` tools [5][6] |
| `disable_destructive` | bool | `false` | no effect when `read_only=true` [6] |
| `kubeconfig` | string | `""` | empty → in-cluster config / client-go fallback [5][6] |
| `cluster_provider_strategy` | string | auto | `kubeconfig`\|`in-cluster`\|`kcp`\|`disabled` [5] |
| `toolsets` | string[] | `["core","config"]` | same default as before [5][6] |
| `enabled_tools` / `disabled_tools` | string[] | `[]` | allowlist then denylist; `configuration_view` hidden in HTTP mode since v0.0.68 [1][6] |
| `denied_resources` | GVK table array | `[]` | block resource kinds [6] |

Drop-ins: `--config-dir` alone is sufficient; `.toml` files load in lexical order; later files override earlier per-key; unknown keys in any file fail startup; numeric prefixes recommended [5][6]. Bootstrap env: `MCP_CONFIG_PATH` (renamed from `K8S_MCP_CONFIG_PATH`, no shim); **no env vars exist for the dropped runtime flags** [5]. The v0.0.69 image bakes `/etc/kubernetes-mcp-server/config.toml` containing `port = "8080"` and sets `ENV MCP_CONFIG_PATH` to it — zero-arg start serves HTTP :8080 *stateful with write tools visible* (never acceptable for the lab's readonly tier) [22][23].

Upstream verbatim migration example [5]:

```
# before
kubernetes-mcp-server --port 8080 --log-level 2 --kubeconfig ~/.kube/config --toolsets core,config,helm
# after: config.toml
port = "8080"
log_level = 2
kubeconfig = "/home/user/.kube/config"
toolsets = ["core", "config", "helm"]
# run
kubernetes-mcp-server --config config.toml
```

## 3. Migration mapping for the lab

readonly (`--port 8080 --stateless --read-only`):

```toml
port = "8080"
stateless = true
read_only = true
```

admin (`--port 8080 --stateless`):

```toml
port = "8080"
stateless = true
```

Gone with no equivalent: `--sse-base-url` (SSE-era, unused by lab); `K8S_MCP_CONFIG_PATH` (renamed). `--disable-list-namespace-resources` never existed in this project [3]. Read-only enforcement: `read_only` keeps its tool-hiding role; RBAC stays the real boundary (unchanged) [5][6]. No `allowed-hosts` concept exists; the only Host check is the go-sdk loopback DNS-rebinding guard, which doesn't fire when ToolHive's proxy reaches the pod by IP — `disable_localhost_protection` is NOT needed [6][24].

## 4. Delivering the file on ToolHive

MCPServer `spec.volumes` is **hostPath-only** ({name, hostPath, mountPath, readOnly}) — ConfigMap delivery must go through `spec.podTemplateSpec` (volumes + volumeMount on the container named `mcp`), which the lab's `generic-mcpserver.yaml` already passes through verbatim [9]. Reference pattern: the upstream Helm chart — ConfigMap key `config.toml`, mounted at `/etc/kubernetes-mcp-server`, args `["--config", "/etc/kubernetes-mcp-server/config.toml"]` [14][15][16]. Explicit `--config` beats relying on the baked-in `MCP_CONFIG_PATH`.

## 5. ToolHive catalog & regressions

No ToolHive catalog entry for kubernetes-mcp-server exists — not in toolhive-catalog main (193 servers), not in the last embedded registry.json before the 2026-02 catalog split [11][12][13]. The operator passes spec.image/args verbatim; nothing in toolhive 0.51.0–0.56.0 changed that [9][10]. No open functional regressions against v0.0.68/v0.0.69 in the upstream issue tracker (search window >2026-10-01); v0.0.69 is the newest release [1][20].

## 6. Unchanged contracts

Streamable HTTP still at `/mcp` (v0.0.69 source: `mcpEndpoint = "/mcp"`), `/healthz` available; listen stays 0.0.0.0:8080; ingress/proxy/normalize-middleware unaffected [7].

Full citations in `sources.md`; per-perspective evidence in `raw/`; conflicts mapped in `contradictions.md`.