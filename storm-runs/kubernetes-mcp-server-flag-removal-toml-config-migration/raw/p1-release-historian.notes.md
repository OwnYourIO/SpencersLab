# P1 — Upstream release historian

## Lineage
- Project started as manusa/kubernetes-mcp-server (Marc Nuri), renamed/rebranded to containers/kubernetes-mcp-server at v0.0.47 (2025-07-31, PR #202). NOT the ahmetb project (ahmetb/kubernetes-mcp-server is a different, older Go implementation; the lab image `ghcr.io/containers/kubernetes-mcp-server` is the containers-org one). Red Hat-sponsored maintainers (matzew, Cali0707, 2uasimojo, nader-ziada).
- Sources: GitHub releases list; v0.0.47 release notes.

## The breaking change: v0.0.68 "Config rework"
- PR #1423 "Config rework" (by @2uasimojo, "See the design at docs/specs/config.md", closes #1374) merged 2026-09-18T19:02:12Z.
- v0.0.67 published 2026-09-18T13:46Z — BEFORE the merge, so v0.0.67 is still flag-based.
- v0.0.68 published 2026-10-22T21:03Z — first release with the rework. Release notes include "Config rework" (#1423), "fix: restore Streamable HTTP behind kube-rbac-proxy" (#1455, origin of disable_localhost_protection), and "feat!: do not enable configuration_view tool if in http mode".
- v0.0.69 published 2026-10-23T17:51Z — only CI/build chores on top (playwright, s390x container build fix #1566).
- Sources: releases API; PR #1423 API.

## What the rework did
- Runtime CLI flags REMOVED; CLI collapsed to `--config`, `--config-dir`, `--version` (bootstrap only). Runtime settings moved to TOML (docs/configuration-changes.md at v0.0.69 has the full dropped-flag table).
- TOML config support already EXISTED in v0.0.65 (flags and config coexisted; loadFlags overrode config). The rework removed the flag layer and made config mandatory for HTTP mode.
- Unknown TOML keys now fail startup. Env rename K8S_MCP_CONFIG_PATH → MCP_CONFIG_PATH, no shim.
- Container image now bakes /etc/kubernetes-mcp-server/config.toml (content: `port = "8080"`) and sets ENV MCP_CONFIG_PATH.
- Sources: v0.0.69 docs/configuration-changes.md; v0.0.65 root.go; v0.0.69 Dockerfile + mcp-config-container-defaults.toml.

## v0.0.65 is flag-based (proven at the tag)
- pkg/kubernetes-mcp-server/cmd/root.go at tag v0.0.65 defines: --version, --log-level, --log-file, --config, --config-dir, --port, --bind-address, --sse-base-url, --kubeconfig, --toolsets, --list-output, --read-only, --disable-destructive, --stateless, hidden OAuth flags, --disable-multi-cluster, --cluster-provider, --tls-cert/--tls-key/--require-tls.
- NO --disable-list-namespace-resources flag ever existed in this project's v0.0.65 CLI (asked about by coordinator; likely confused with another server).
- --port help at v0.0.65: "Start a streamable HTTP and SSE HTTP server on the specified port (e.g. 8080)".
- Earlier flag trims: v0.0.55 (2025-12-03) "feat(cmd)!: remove deprecated http/sse port from cli" removed the deprecated SSE-era port flags, NOT --port (v0.0.65 still had --port; lab ran it successfully for ~10 weeks).
- Sources: root.go at v0.0.65; v0.0.55 release notes.

## The incident binary is v0.0.69 (verbatim match)
- Incident usage output ("# start STDIO server", "# start a Streamable HTTP server using a TOML config file", "--config /path/to/config.toml", "# start using only a drop-in directory", "--config-dir /path/to/conf.d", flag help strings "Path of a config file." / "Directory of lexical .toml files. Usable alone or with --config...", "Print version information and quit") matches pkg/kubernetes-mcp-server/cmd/root.go at tag v0.0.69 EXACTLY.
- Sources: root.go at v0.0.69.

## Lab timeline (git forensics, SpencersLab repo)
- v0.0.65 pinned 2026-09-07 (commit 28a6b4a28 "Split kubernetes MCP into readonly/admin tiers"); servers healthy until 2026-10-25.
- Renovate commit 4922af75d 2026-10-24T20:53Z bumps image v0.0.65 → v0.0.69; merged to main as PR #704 (98936cebd) 2026-10-25T15:14Z.
- Same session, toolhive-operator(-crds) 0.50.0 → 0.56.0 merged (PRs #788 14:37Z, #787 ~14:46Z). Operator session = what the user remembers as "updated toolhive"; the image bump rode along in the same merge batch.
