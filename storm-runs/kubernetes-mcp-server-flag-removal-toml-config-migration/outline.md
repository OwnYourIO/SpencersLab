# Outline

1. TL;DR — root cause + fix shape.
2. Incident timeline (lab git forensics): what merged when; why "updated toolhive" is a red herring.
3. The upstream breaking change
   - Project lineage (containers org, not ahmetb).
   - v0.0.68 "Config rework" (PR #1423): flags removed, config mandatory for HTTP.
   - v0.0.65 flag-based (proven), v0.0.69 config-based (usage text verbatim match).
   - v0.0.68 container tag missing (issue #1560) → Renovate skipped to v0.0.69.
4. TOML schema for the fix
   - Precedence chain; drop-in merge + lexical order; unknown keys fatal.
   - Key table: port (string!), bind_address, stateless, read_only, disable_destructive, kubeconfig, toolsets, enabled/disabled_tools, denied_resources, MCP_CONFIG_PATH.
   - Image-baked default config (port="8080") — zero-arg boot behavior and why not to rely on it.
5. Migration mapping for the lab's exact args (readonly + admin tiers) + what no longer exists.
6. Getting the file into the container on ToolHive
   - spec.volumes = hostPath-only → podTemplateSpec ConfigMap volume/mount; upstream chart as reference pattern; --config vs env-only trade-off.
7. ToolHive catalog/operator status (no catalog pin; 0.56 safe) + regressions check (none open).
8. Unchanged contracts: /mcp path, /healthz, bind, no allowed-hosts concept, RBAC boundary, sessionAffinity option.
9. Implications for the fix (planner checklist) + open questions.