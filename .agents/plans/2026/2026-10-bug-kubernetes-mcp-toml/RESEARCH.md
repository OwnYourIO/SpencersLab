# RESEARCH — kubernetes-mcp-server `--port` startup failure (TOML config migration)

**Date**: 2026-10-25 · **Agent**: agent-research (STORM method, 5 perspectives; audit trail in `storm-runs/kubernetes-mcp-server-flag-removal-toml-config-migration/` — perspectives, raw notes, numbered sources, contradictions, report)

## TL;DR

1. Root cause is **NOT the ToolHive upgrade**: Renovate's image bump `ghcr.io/containers/kubernetes-mcp-server:v0.0.65 → v0.0.69` (commit 4922af75d, merged via PR #704 at 2026-10-25 15:14 UTC — ~40 min after the toolhive 0.50→0.56 merges in the same session) landed the breaking build.
2. Upstream **v0.0.68** (2026-10-22) shipped "Config rework" (PR #1423): all runtime CLI flags removed; CLI is now only `--config` / `--config-dir` / `--version`; HTTP mode requires `port` in TOML. v0.0.69 is the first release with a working multi-arch container for that change. The crashing pod runs v0.0.69 (its usage text matches v0.0.69 source verbatim).
3. Migration: `--port 8080 --stateless --read-only` → TOML `port = "8080"` (a **string**), `stateless = true`, `read_only = true`; admin tier without `read_only`. RBAC remains the enforcement boundary; `read_only` only hides write tools, as before.
4. Delivery on ToolHive: `spec.volumes` is hostPath-only → mount a **ConfigMap via `podTemplateSpec`** (volume + volumeMount on container `mcp`), args become `["--config", "/etc/kubernetes-mcp-server/config.toml"]` (the upstream chart's exact pattern). Env-var config is NOT an alternative (no env names for the dropped flags).
5. No ToolHive catalog entry pins this server (operator passes spec.image verbatim); no open upstream regressions in v0.0.69; `/mcp` path and the whole ingress/proxy contract are unchanged.

## Incident timeline (lab git forensics)

| When (UTC) | Event | Evidence |
|---|---|---|
| 2026-09-07 | v0.0.65 pinned in `charts/hivetools/values.yaml` (readonly/admin split, commit 28a6b4a28); servers healthy ~10 weeks | repo git |
| 2026-10-22 21:03 | upstream **v0.0.68** released (Config rework + others) | [releases](https://github.com/containers/kubernetes-mcp-server/releases) |
| 2026-10-23 17:51 | upstream **v0.0.69** released (build fixes only) | [releases](https://github.com/containers/kubernetes-mcp-server/releases) |
| 2026-10-24 20:53 | Renovate commit 4922af75d: image v0.0.65 → v0.0.69 | repo git |
| 2026-10-25 14:37–14:46 | toolhive-operator(-crds) 0.50.0 → 0.56.0 merged (PRs #788, #787) | repo git |
| 2026-10-25 15:14 | **PR #704 merged** → v0.0.69 on main → ArgoCD sync → pods roll → `unknown flag: --port` | repo git (98936cebd) |

The operator's "updated toolhive" session merged a Renovate backlog; the image bump rode along. Both memories are real events; only the image bump is causal (the error is cobra usage from the server binary itself — the operator cannot change that).

## Key findings

### F1 — Which release broke what (Q1)
- Project is **containers/kubernetes-mcp-server** (Red Hat-sponsored; rebranded from manusa/kubernetes-mcp-server at v0.0.47). It is *not* ahmetb/kubernetes-mcp-server (a different, older project). Source: release history, v0.0.47 notes.
- **PR #1423 "Config rework"** (merged 2026-09-18T19:02Z) removed the runtime flags; first released in **v0.0.68** (v0.0.67, published hours *before* the merge, is still flag-based). v0.0.68 also: `fix: restore Streamable HTTP behind kube-rbac-proxy` (#1455) and `feat!: configuration_view tool disabled by default in HTTP mode`. https://github.com/containers/kubernetes-mcp-server/pull/1423
- **v0.0.65 is flag-based, proven at the tag**: `pkg/kubernetes-mcp-server/cmd/root.go` defines `--port` ("Start a streamable HTTP and SSE HTTP server on the specified port"), `--read-only`, `--stateless`, `--bind-address`, `--kubeconfig`, `--toolsets`, `--list-output`, `--disable-destructive`, `--disable-multi-cluster`, `--cluster-provider`, TLS + hidden OAuth flags (and `--config`/`--config-dir` already coexisted). https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.65/pkg/kubernetes-mcp-server/cmd/root.go
- **The failing binary is v0.0.69**: the incident's usage output (example block + flag help strings "Path of a config file." / "Directory of lexical .toml files. Usable alone or with --config..." / "Print version information and quit") matches `root.go` at tag v0.0.69 **verbatim**. https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/pkg/kubernetes-mcp-server/cmd/root.go
- **What would produce this symptom — verdicts:** (a) config-based build run with legacy args → **this incident**; (b) re-tagged v0.0.65 → **ruled out**: ghcr digest of v0.0.65 is intact and distinct (sha256:5df586e2… vs v0.0.69 sha256:1da9d62a…, fetched live via ghcr v2 API with anonymous pull token); (c) floating `:latest` → not used (and ghcr `latest` = sha256:8ca95ced…, ≠ v0.0.69 anyway); (d) ToolHive catalog/operator image override → no catalog entry exists (F5); (e) operator 0.56 arg handling → no such change in 0.51–0.56 release notes, and our args provably reach the binary.
- Note: v0.0.55's "remove deprecated http/sse port from cli" removed SSE-era flags, NOT `--port` (v0.0.65 still had it). `--disable-list-namespace-resources` never existed in this project.
- Renovate skipped v0.0.66–v0.0.68: **no multi-arch `v0.0.68` tag exists on ghcr** (only per-arch tags) — upstream issue #1560 "v0.0.68 container release failed; multi-platform image tag is missing" (closed; fixed in v0.0.69 via #1566). https://github.com/containers/kubernetes-mcp-server/issues/1560

### F2 — Exact TOML schema (Q2)
Primary sources: [docs/configuration-changes.md at v0.0.69](https://raw.githubusercontent.com/containers/kubernetes-mcp-server/v0.0.69/docs/configuration-changes.md) (tag-pinned migration doc) and [docs/configuration.md](https://github.com/containers/kubernetes-mcp-server/blob/main/docs/configuration.md) (main branch; all fix-relevant keys cross-checked against the tag-pinned doc/source).

**Dropped-flag → TOML table (verbatim from configuration-changes.md):**

| Dropped flag | Replacement |
|---|---|
| `--port` | `port` in TOML |
| `--bind-address` | `bind_address` |
| `--metrics-port` | `metrics_port` |
| `--log-level` / `--log-file` | `log_level` / `log_file` |
| `--kubeconfig` | `kubeconfig` (`$KUBECONFIG` remains client-go fallback when empty) |
| `--list-output` | `list_output` |
| `--read-only` | `read_only` |
| `--disable-destructive` | `disable_destructive` |
| `--stateless` | `stateless` |
| `--toolsets` | `toolsets` |
| `--cluster-provider` | `cluster_provider_strategy` |
| `--disable-multi-cluster` | `cluster_provider_strategy = "disabled"` |
| `--tls-cert`/`--tls-key`/`--require-tls` | `tls_cert`/`tls_key`/`require_tls` |
| hidden OAuth flags | matching TOML keys (`require_oauth`, `oauth_audience`, `authorization_url`, …) |

Remaining CLI: `--version`; `--config` (env fallback `MCP_CONFIG_PATH`, flag wins); `--config-dir` (no default, usable alone).

**Fix-relevant keys:** `port` (**string**, default `""` — set ⇒ HTTP mode, Streamable HTTP at `/mcp`; empty ⇒ stdio), `bind_address` (string, default `"0.0.0.0"`), `stateless` (bool, default false — disables tool/prompt change notifications; **restart-only**, not SIGHUP-reloadable), `read_only` (bool, default false — exposes only `readOnlyHint=true` tools; reloadable), `disable_destructive` (bool; no effect when `read_only=true`), `kubeconfig` (string; empty ⇒ in-cluster config in a pod), `cluster_provider_strategy` (`kubeconfig`|`in-cluster`|`kcp`|`disabled`, auto-detect default), `toolsets` (string[], default `["core","config"]` — unchanged from v0.0.65 defaults), `enabled_tools`/`disabled_tools` (allowlist then denylist), `denied_resources` (GVK tables), `trust_proxy_headers`, `disable_localhost_protection`, `[http]` table, `max_*` memory bounds, `[telemetry]`.

**Drop-in merge & precedence (verbatim semantics):** resolution order per load: defaults → main config (`--config` or `$MCP_CONFIG_PATH`) → `--config-dir` files in **lexical order** → env vars (only declared names; empty = no override) → CLI (bootstrap only). `--config-dir` alone is sufficient; only `.toml` files, dotfiles ignored; partial files allowed; **values in a later file override earlier per-key, missing values preserved**; numeric prefixes recommended (`00-base.toml` … `99-override.toml`). **Unknown keys in any file fail the whole load** (startup and SIGHUP exit non-zero). Gotcha: a sibling `conf.d/` next to `--config` is no longer auto-loaded (v0.0.65 did implicit lookup); if such a dir exists with `.toml` files and `--config-dir` isn't passed, startup fails.

**Upstream verbatim migration example (configuration-changes.md):**
```bash
# before
kubernetes-mcp-server --port 8080 --log-level 2 --kubeconfig ~/.kube/config --toolsets core,config,helm
```
```toml
# after: config.toml
port = "8080"
log_level = 2
kubeconfig = "/home/user/.kube/config"
toolsets = ["core", "config", "helm"]
```
```bash
kubernetes-mcp-server --config config.toml
```

**Env-var config:** `MCP_CONFIG_PATH` points at the main config file (renamed from `K8S_MCP_CONFIG_PATH`, **no shim**). "No new `K8S_MCP_*` names were added for dropped flags" — there is **no env alternative** for port/stateless/read_only. The file is mandatory.

**Image-baked default (important):** the v0.0.69 Dockerfile does `COPY mcp-config-container-defaults.toml /etc/kubernetes-mcp-server/config.toml` and `ENV MCP_CONFIG_PATH=/etc/kubernetes-mcp-server/config.toml`; the defaults file is literally `port = "8080"`. So a **zero-arg** v0.0.69 container boots HTTP on :8080 *stateful, with write tools visible* — never acceptable for the readonly tier; always mount explicit config. (Dockerfile also: `USER 65532:65532`, `EXPOSE 8080`; GHCR image built from this exact Dockerfile by `release-image.yml`.)

### F3 — Migration mapping for the lab's exact args (Q3)
readonly tier (`--port 8080 --stateless --read-only`):
```toml
port = "8080"
stateless = true
read_only = true
```
admin tier (`--port 8080 --stateless`):
```toml
port = "8080"
stateless = true
```
- No `kubeconfig`/`toolsets` keys needed: empty kubeconfig ⇒ in-cluster config via the pod's ServiceAccount (same behavior as before); toolsets default `["core","config"]` is unchanged. Optionally pin `cluster_provider_strategy = "in-cluster"` for explicitness.
- Semantics carry over 1:1; `read_only` still only hides write tools from `tools/list` — **RBAC remains the enforcement boundary** (per `skills/helm-chart-creation/references/mcp-servers.md`; no secrets/exec verbs either way). The admin tier keeps write tools visible (unchanged).
- No-longer-exists: `--sse-base-url` (SSE-era, lab never used it); `K8S_MCP_CONFIG_PATH` (renamed). Behavior delta to expect: `configuration_view` tool disappears from HTTP-mode `tools/list` (disabled by default since v0.0.68; it exposed kubeconfig contents — acceptable/desirable).

### F4 — Getting the file into the container on ToolHive (Q4)
- MCPServer CRD at toolhive v0.56.0 ([mcpserver_types.go](https://raw.githubusercontent.com/stacklok/toolhive/v0.56.0/cmd/thv-operator/api/v1beta1/mcpserver_types.go)): `spec.args` ([]string, atomic, passed to the server container verbatim), `spec.env` (plain name/value), **`spec.volumes` is HostPath-only** (`{name, hostPath, mountPath, readOnly}`) — NOT usable for a ConfigMap. `spec.podTemplateSpec` is a RawExtension escape hatch (container must be named `mcp`).
- Therefore: **ConfigMap volume + volumeMount via `podTemplateSpec`**. The lab's `generic-mcpserver.yaml` already passes `podTemplateSpec` through verbatim and both kubernetes servers already use it (securityContext + /tmp emptyDir) — no template change needed beyond a new ConfigMap template in `charts/hivetools/templates/`.
- **Reference pattern — the upstream project's own Helm chart** (`charts/kubernetes-mcp-server` in the server repo at v0.0.69): ConfigMap key `config.toml` (rendered from values via `toToml`), volume mounted at `configFilePath | dir`, container args `["--config", "{{ .Values.configFilePath }}"]`, `configFilePath` default `/etc/kubernetes-mcp-server/config.toml`, probes on `/healthz`, and an explicit note: "Only bootstrap flags exist (`--config`, `--config-dir`, `--version`). Runtime settings go in `config`."
- Recommended shape: one ConfigMap per tier (or one CM with two keys + subPath mounts); mount over `/etc/kubernetes-mcp-server/config.toml` (shadows the image-baked default; fine under `readOnlyRootFilesystem: true`); args `["--config", "/etc/kubernetes-mcp-server/config.toml"]`. Alternative that also works: mount the file there and pass NO args (image `ENV MCP_CONFIG_PATH` finds it) — explicit `--config` is clearer and survives image-default changes. `--config-dir` drop-ins work too but add no value here.
- Env-var-only config is impossible for these settings (F2).

### F5 — ToolHive catalog status + regressions (Q5)
- **No catalog pin exists.** The ToolHive registry was split out of the toolhive repo 2026-02-21 (PR #3926) into [stacklok/toolhive-catalog](https://github.com/stacklok/toolhive-catalog) (mirrored at stacklok/toolhive-registry). Current catalog (193 servers) has **no kubernetes-mcp-server entry** (searched kube/k8s; closest is "k8s" = `ghcr.io/stackloklabs/mkp/server:0.2.4`, a different Stacklok project). Even the last embedded registry.json (toolhive@80c3133f1, 2026-02-20, 79 servers) had none. So the operator has never overridden this server's image; the lab's explicit pin is the only source of truth, and "move to what the catalog pins" is moot. **Recommended version: stay on v0.0.69** (newest release, first release with the fix for the v0.0.68 container-publish failure).
- **Regressions check:** upstream issue search (created >2026-10-01) shows no open functional regressions against the v0.0.68/v0.0.69 config surface — #1560 (container release failure, build-only) closed via v0.0.69; #1568 flaky CI test closed; the rest are dependency bumps/chores. ToolHive 0.51.0→0.56.0 notes (auth-server/vMCP/CLI-focused; v0.53.0 deprecates+ignores `permissionProfile`, which the lab never sets; v0.55.2 is a rootless-Podman advisory) contain nothing that affects this workload. Caveat: an issue-search window can't catch unreported problems — verify functionally post-deploy.

### F6 — Anything else that changes the fix (Q6)
- **`/mcp` path unchanged**: v0.0.69 `pkg/http/http.go` has `mcpEndpoint = "/mcp"`, plus `/healthz` (200 OK — usable for future probes), `/stats`, `/metrics`. Listen = `bind_address:port` = `0.0.0.0:8080` with defaults, same wire contract as v0.0.65. Ingress (`mcp-mcp-<name>-proxy:8080`), the `normalize-mcp-path` middleware, and client URL `https://mcp.<cluster>/<name>/mcp` are all unaffected.
- **No `allowed-hosts` config exists** in this server (unlike mcp-grafana). The only Host-based rejection is the MCP go-sdk loopback DNS-rebinding guard, which fires only when a request is accepted on a loopback address; ToolHive's proxy Deployment reaches the backend by pod IP, so the guard never fires and `disable_localhost_protection` must stay false (it's for kube-rbac-proxy-style sidecars forwarding to 127.0.0.1, introduced by PR #1455).
- **Statelessness/affinity**: with `stateless = true`, MCPServer `sessionAffinity: None` is supported (CRD default is ClientIP). Optional hardening; the previous stateful-affinity setup worked, so not required.
- **Keep toolhive 0.56.0**: nothing in the operator bump needs reverting.
- **Renovate note**: v0.0.65 is now 3+ months behind; after migrating, no pin-downgrade is needed. If instant restore beats migration, rolling values back to v0.0.65 restores service with zero other changes (its tag is intact) — but Renovate will re-propose the bump; migration is the durable fix.

## Contradictions and how to weigh them

1. **"Updated toolhive broke it" vs evidence** — both merges happened in the same session; only the image bump is causal (the error is the server binary's own cobra usage; no operator change touches server args). Weigh: git timestamps + binary usage match settle it.
2. **"We pin v0.0.65" vs the running image** — the worktree/incident text predates PR #704's merge; main pins v0.0.69 and the usage text proves the pod ran v0.0.69. The re-tag hypothesis is refuted by live ghcr digests.
3. **"TOML is new" nuance** — `--config`/`--config-dir` already existed in v0.0.65 (flags overrode files). v0.0.68 removed the flags and made config mandatory for HTTP mode. Don't misdate the change.
4. **Source-freshness drift** — full configuration.md read from `main`, not the v0.0.69 tag; every fix-relevant key is corroborated by the tag-pinned migration doc and source files, so risk is low but declared.
5. **v0.0.55 "remove deprecated http/sse port"** looks like an earlier `--port` removal; it was the SSE-era flags. v0.0.65 root.go settles it.

## Implications for the plan

1. **Fix forward on v0.0.69** (recommended) rather than pinning back to v0.0.65: add one/two ConfigMap(s) to `charts/hivetools/templates/`, rewrite both `mcp.kubernetes-*` entries: `args: ["--config", "/etc/kubernetes-mcp-server/config.toml"]`, add the ConfigMap volume + `volumeMount` (mountPath `/etc/kubernetes-mcp-server/config.toml`, subPath or directory mount) to each server's existing `podTemplateSpec`. Keep `mcpPort: 8080`, `transport: streamable-http`, ServiceAccounts and RBAC untouched.
2. ConfigMap content is 3 keys readonly / 2 keys admin — TOML must be exact: `port` is a **quoted string**; unknown keys crash startup. No kubeconfig/toolsets keys.
3. The chart already renders `spec.volumes` from `$config.volumes` but that CRD field is hostPath-only — do NOT use it for this; use podTemplateSpec volumes.
4. Validation plan: `helm lint`/`helm template charts/hivetools`; then per cluster after sync — pod Running, `tools/list` via `https://mcp.<cluster>/kubernetes-readonly/mcp` shows read tools only (no write tools, no `configuration_view`), admin tier shows write tools, one read call succeeds. Because the MCP fleet is down, kubectl verification commands must be presented to the user to run (no pod exec via MCP in any tier).
5. Expect a second ArgoCD-driven rolling update if the operator previously patched pod-template annotations (per the repo's known GitOps restart mechanic) — harmless.
6. Update `skills/helm-chart-creation/references/mcp-servers.md` in the same change: the kubernetes server section still documents the flag form.
7. Optional (separate decision): `sessionAffinity: None` on both stateless servers.

## Open questions

- Verify the live failing pods' image + last good state with `kubectl get sts mcp-kubernetes-readonly -o jsonpath='{.spec.template.spec.containers[?(@.name=="mcp")].image}'` and pod logs (user-run; confirms v0.0.69 beyond the usage-text match).
- One ConfigMap with two keys (readonly.toml/admin.toml, subPath mounts) vs two ConfigMaps — planner's choice; two CMs is simpler against list-replace merge semantics.
- Whether to also add `/healthz` liveness/readiness probes via podTemplateSpec while touching these entries (upstream chart does; ToolHive operator manages its own proxy probes — backend probes are additive).

## Adjacent

- Upstream publishes its own Helm chart for this server (charts/kubernetes-mcp-server) and publishes chart releases per image release (PR #1569 in flight) — a future option if the lab ever wants to de-ToolHive this one server, but out of scope.
- The ghcr `latest` tag ≠ v0.0.69 (tracks a separate build); nobody in the lab uses it — no action.
- `docs/specs/config.md` in the server repo holds the full design rationale behind PR #1423 (not needed for the fix).