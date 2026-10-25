# Perspectives — kubernetes-mcp-server flag removal / TOML config migration

Local pre-survey evidence (repo git forensics):
- `charts/hivetools/values.yaml` pinned `ghcr.io/containers/kubernetes-mcp-server:v0.0.65` since 2026-09-07 with args `--port 8080 --stateless --read-only` (readonly) / `--port 8080 --stateless` (admin). Servers worked until ~2026-10-24/25.
- Renovate commit 4922af75d (2026-10-24 20:53 UTC) bumped the image v0.0.65 → **v0.0.69**, merged to main via PR #704 (98936cebd).
- Renovate PRs #787/#788 (merged 2026-10-25) bumped toolhive-operator(-crds) Helm deps 0.50.0 → 0.56.0.
- Failure mode: binary in container rejects `--port`; usage shows only `--config` / `--config-dir` (TOML).

## P1 — Upstream release historian (containers/kubernetes-mcp-server)
Lens: repo/release archaeology — ahmetb → containers org lineage.
Sees: which exact release replaced CLI flags with TOML config; whether v0.0.65 is the last flag-based build and v0.0.69 config-based; what v0.0.66–v0.0.69 changelogs say. Nobody else can date the breaking change.

## P2 — TOML config schema authority
Lens: upstream source-of-truth for the new config file format.
Sees: exact key names/types/defaults (transport/listen/port, stateless, readOnly, auth/kubeconfig/context, tool enablement, allowed hosts), verbatim example config, --config-dir drop-in merge & precedence rules. The fix is impossible without exact field names.

## P3 — ToolHive platform engineer (operator 0.50 → 0.56)
Lens: how the operator turns an MCPServer CRD into a pod.
Sees: CRD fields for delivering files (volumes/podTemplateSpec/configmap support), what changed 0.50→0.56 that could interact with args/images, whether operator/registry overrides images, the streamable-HTTP `/mcp` path + proxy Service naming that the ingress depends on.

## P4 — Registry & digest forensics
Lens: what actually gets pulled from ghcr.io and what catalogs pin.
Sees: ghcr tags/digests for containers/kubernetes-mcp-server (did v0.0.65 move?), ToolHive registry catalog data for the kubernetes server (stacklok registry) and which version it pins, known regressions/issues in recent releases.

## P5 — Migration & enforcement engineer
Lens: translating the lab's current flags into the new config without losing security posture.
Sees: flag→config mapping for both tiers, flags with no config equivalent (does `--read-only` survive as config?), where read-only enforcement must live if not (RBAC, per lab's mcp-servers.md model), allowed-hosts/DNS-rebinding implications behind the ToolHive proxy.