# P3 — ToolHive platform engineer (operator 0.50 → 0.56)

## MCPServer CRD at v0.56.0 (cmd/thv-operator/api/v1beta1/mcpserver_types.go)
- spec.image (required), spec.transport (stdio|streamable-http|sse), spec.proxyPort (default 8080), spec.mcpPort.
- spec.args []string (listType atomic) — passed to the MCP server container as-is. Incident proves pass-through (our --port reached the binary).
- spec.env []EnvVar (name/value only — no valueFrom).
- spec.volumes []Volume — HOSTPATH ONLY: {name, hostPath, mountPath, readOnly}. NOT usable for ConfigMap delivery.
- spec.podTemplateSpec — RawExtension, full pod-spec customization; the MCP container must be named "mcp". THIS is the ConfigMap-volume path (volumes + volumeMounts on container mcp).
- spec.secrets []SecretRef (name+key → env var). spec.serviceAccount (existing SA). oidcConfigRef, authzConfig(Ref), toolConfigRef, audit, trustProxyHeaders, endpointPrefix, sessionAffinity (ClientIP default | None), replicas/backendReplicas, sessionStorage (redis), rateLimiting.
- permissionProfile deprecated & ignored by operator since v0.53.0 (lab never sets it).

## What changed 0.50.0 → 0.56.0 (release notes)
- v0.51.x: SPIFFE JWT auth, SSE session fixes, catalog bumps; v0.52.0: Redis TLS, llm teardown change (CLI), DCR store method; v0.53.0: permissionProfile ignored (security fix), vMCP group filter; v0.54.0: catalog bump v0.20261013.0, Pi client; v0.55.x: Podman egress proxy security advisory (GHSA-2x65-h9w3-h7hc, rootless Podman only), homebrew cask; v0.56.0: OSS scanner audit, DCR client caps, Claude Code gateway discovery, 401 on missing upstream token.
- NOTHING in 0.51–0.56 changes how spec.image/spec.args reach the server container. The --port failure cannot be caused by the operator bump.

## Registry/catalog
- Catalog split out of the toolhive repo 2026-02-21 (PR #3926 "Remove embedded registry.json in favour of toolhive-catalog Go package"); now github.com/stacklok/toolhive-catalog (module bumped by renovate inside toolhive releases) and mirrored at stacklok/toolhive-registry.
- Current catalog (main, 193 servers) has NO entry for containers/kubernetes-mcp-server (searched kube/k8s). Last embedded registry.json (toolhive@80c3133f1, 2026-02-20, 79 servers) also had NO kubernetes-mcp-server entry — closest is "k8s" = ghcr.io/stackloklabs/mkp/server:0.2.4 (different Stacklok project).
- Conclusion: no catalog pin exists for this server; the operator does not override spec.image from any catalog; the lab's explicit image pin is the only source of truth.

## Config delivery options in the lab's hivetools chart
- generic-mcpserver.yaml renders: image, transport, proxyPort/mcpPort, serviceAccount, oidcConfigRef, args, env, resources, secrets, podTemplateSpec, spec.volumes (hostPath-type!), audit, authzConfig, toolConfigRef.
- Chart already deep-merges arbitrary podTemplateSpec (values → CRD verbatim), so a ConfigMap volume + mount on container `mcp` needs no chart template change beyond (a) a ConfigMap template and (b) values wiring.
- Upstream's own Helm chart (charts/kubernetes-mcp-server in the server repo, v0.0.69) is the reference pattern: ConfigMap with config.toml (toToml of values.config), mounted at configFilePath|dir, args ["--config", configFilePath], configFilePath default /etc/kubernetes-mcp-server/config.toml; probes on /healthz; extraArgs docs say only bootstrap flags exist.
