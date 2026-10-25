# Contradictions & consensus map

## C1 — Incident attribution: "updated toolhive" vs the image bump
- Operator narrative: failure began after "updated toolhive".
- Evidence: TWO merges landed in the same ~40-minute window on 2026-10-25: toolhive-operator(-crds) 0.50.0→0.56.0 (PRs #788 14:37 UTC, #787 ~14:46 UTC) and the kubernetes-mcp-server image v0.0.65→v0.0.69 Renovate bump (PR #704, 15:14 UTC). The operator session merged a Renovate backlog; the image bump rode along.
- The `--port` failure can ONLY come from the server image (cobra usage of the binary itself). ToolHive 0.51–0.56 release notes contain no change to how spec.image/spec.args reach the container [9][10]. Verdict: the image bump is the cause; "updated toolhive" is a misattribution (both memories are true events, only one is causal).

## C2 — "We run v0.0.65" vs what actually runs
- The feature-branch worktree (and the incident report) says the pin is v0.0.65; main has carried v0.0.69 since 2026-10-25T15:14Z. The crashing pod runs v0.0.69 (usage text matches v0.0.69 root.go verbatim [4]).
- The "re-tagged v0.0.65" alternative is REFUTED: v0.0.65's ghcr digest is intact and distinct (sha256:5df586e2… vs v0.0.69 sha256:1da9d62a…) [17][18][19].

## C3 — "TOML config is new in v0.0.68" (nuance)
- TOML config support already existed in v0.0.65 (--config/--config-dir flags coexisted with runtime flags; CLI flags overrode file values [3]). v0.0.68's "Config rework" [2] REMOVED the runtime flags and made config mandatory for HTTP mode — it did not introduce TOML. Sources agreeing: v0.0.65 root.go [3], configuration-changes.md [5].

## C4 — Source freshness drift (main vs v0.0.69)
- docs/configuration.md was fetched from `main` (post-v0.0.69) [6]; exact schema at the pinned tag is only fully guaranteed by the v0.0.69-tagged configuration-changes.md [5] and source files [4][7]. Every key the fix needs (port/bind_address/stateless/read_only/toolsets/MCP_CONFIG_PATH) is corroborated by the tag-pinned docs, so drift risk is low but declared.

## C5 — Apparent early `--port` removal (v0.0.55)
- v0.0.55 changelog says "feat(cmd)!: remove deprecated http/sse port from cli" [1], which could read as --port removal. v0.0.65's root.go proves --port was alive three releases later [3]; v0.0.55 removed the deprecated SSE-era port flags. Not a real contradiction once source is checked — flagged so the planner doesn't misdate the breaking change.

## Consensus (all perspectives agree)
- Breaking change = v0.0.68 "Config rework"; lab's failing build = v0.0.69; fix = TOML config delivered via mounted file + bootstrap args.
- RBAC remains the read-only enforcement boundary; read_only is cosmetic tool-hiding in both old and new worlds.
- /mcp path, 0.0.0.0:8080 listen, and ToolHive proxy/ingress contract are unchanged.

## Blind spots (none of the perspectives could verify)
- Live cluster state: the crashing pod's actual image digest / full logs — the very MCP path into the clusters is down; verification must use kubectl directly (present exact commands to the user; no pod exec via MCP).
- Whether the ToolHive operator tolerates EMPTY args on a streamable-http MCPServer (it should — args is optional — but the fix passes explicit --config anyway, making this moot).
- Any post-v0.0.69 unreleased drift on upstream main beyond docs wording.