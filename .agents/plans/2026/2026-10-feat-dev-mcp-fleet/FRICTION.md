# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; cord appends (its own items included).

- 2026-10-24 · plan · `readonly-dev-kubernetes.resources_list` requires `apiVersion`+`kind` scalars (a `resource:` object guess fails with "missing argument apiVersion"), and its items use CAPITALIZED keys (`Name`/`Namespace`), not k8s object paths · resolution: read the tool signature via Code Mode `search`, filter on the capitalized fields.
- 2026-10-24 · plan · `helm` is NOT on PATH in this environment (only at `~/.local/bin/helm`) · resolution: contract scripts must use the existing helm-discovery recipe (`tests/services/dev-forgejo-runner.sh` header) instead of bare `helm`.
- 2026-10-24 · plan · cannot read ArgoCD cluster secrets from any readonly MCP, so `services.dev.customValuesUrls` is inference-verified (dev's synced UUID-backed resources prove the load) · resolution: recorded in plan Risks; user can confirm in the ArgoCD UI.

## 2026-10-24 agent-test handoff (test suite, commit 7ef80d65f)
- readonly-dev-kubernetes resources_list arg shape + capitalized item keys — discovery via signature search, filter Name/Namespace (carried from plan).
- helm absent from PATH (only ~/.local/bin) — test scripts use the dev-forgejo-runner.sh discovery recipe.
- services.dev.customValuesUrls unverifiable via readonly MCP — inference-verified, recorded in plan Risks.
- Legacy cross-ticket contract conflicts A (dev-forgejo-runner.sh t9) and B (forgejo-ssh-gateway.sh t8) vs approved plan — escalated to user (pipeline-gates validation_at_fault-equivalent); resolution pending user ruling.
