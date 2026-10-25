# P4 — Registry & digest forensics

## ghcr.io/containers/kubernetes-mcp-server (anonymous pull token, v2 API, 2026-10-25)
- 53 tags present: latest(+per-arch), v0.0.59…v0.0.67 (+per-arch each), v0.0.68-linux-amd64, v0.0.68-linux-arm64 (NO multi-arch v0.0.68 tag), v0.0.69 (+amd64/arm64/ppc64le/s390x).
- Digests (OCI image index):
  - v0.0.65 = sha256:5df586e2c7ced2a3125f6e78923388d80b69de0a2ad1470325b05318f12725bd
  - v0.0.69 = sha256:1da9d62ad0c008a6cadcf2718c86c2e2d18753ca1d9f1f3313068980794b24f2
  - latest = sha256:8ca95ced1719380bceed7a4384b23ee65a3c958633b82cdd565a8c3f7027cfbf (≠ v0.0.69 — latest tracks a separate build)
- v0.0.65 tag INTACT and distinct → the "re-tagged v0.0.65" hypothesis is RULED OUT.
- Missing multi-arch v0.0.68 tag explained by upstream issue #1560 "v0.0.68 container release failed; multi-platform image tag is missing" (closed; fixed by #1566 in v0.0.69 — "s390x container should work again"). This is why Renovate's datasource skipped v0.0.68 and bumped v0.0.65 → v0.0.69 directly.
- GHCR image built from the root Dockerfile by .github/workflows/release-image.yml (GHCR_IMAGE_NAME=ghcr.io/containers/kubernetes-mcp-server, podman build -f Dockerfile) → the ENV MCP_CONFIG_PATH + baked config.toml apply to the exact image the lab pulls. (quay.io/containers/kubernetes_mcp_server is the parallel konflux build used by the upstream chart defaults.)

## What could produce the "unknown flag: --port" symptom — verdicts
1. Running a config-based build (v0.0.68+) with legacy args → THIS IS THE INCIDENT. v0.0.69 landed in the lab repo's main via Renovate PR #704 merged 2026-10-25T15:14Z; ArgoCD sync rolled the StatefulSets; new image rejected --port. Usage text matches v0.0.69 root.go verbatim.
2. Re-tagged v0.0.65 → ruled out (digest intact, published 2026-07-14, distinct from v0.0.69).
3. Floating :latest/:main → not used (values pin v0.0.65 pre-incident / v0.0.69 post).
4. ToolHive catalog/operator overriding image → no catalog entry exists; operator passes spec.image/args verbatim.
5. toolhive-operator 0.56 changing arg handling → no such change in 0.51–0.56 notes; args provably reach the binary unchanged.

## Known regressions since the config rework
- Issue search (created >2026-10-01, repo containers/kubernetes-mcp-server): no open functional regressions against v0.0.68/v0.0.69 config surface. #1560 (v0.0.68 container release failure — build/infra only) closed via v0.0.69. #1568 flaky test (CI-only, closed). Rest are dependency bumps/chores.
- v0.0.69 is the latest release (2026-10-23); no v0.0.70 yet.
