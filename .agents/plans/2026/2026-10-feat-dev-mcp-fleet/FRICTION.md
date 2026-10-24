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
## 2026-10-24 agent-test conflict-fix follow-up (commit 94e193af6)
- Concurrent-edit hazard: a suite that execs another script from disk picks up mid-edit bytes (phantom syntax error). Never edit a test script while an in-flight suite chains it; run sequentially.
## Resolution ledger (plan complete)
- open: readonly-dev-kubernetes resources_list arg shape / capitalized item keys — workaround documented; could become a fixed helper in shared skill.
- fixed: helm + aislop absent from PATH (only ~/.local/bin / npx pinned aislop@0.18.1) — all contract scripts use the discovery recipe; FRICTION lines above carry the workaround.
- fixed: concurrent-edit hazard (suite execs another script from disk) — run sequentially; line above.
- fixed: legacy contract conflicts A/B — re-ruled by user at 94e193af6, fail-closed, regression green.
- ignored(superseded): skills-permission-block drop on v2.0.32 — fixed by OpenCode v2.1.4 runtime upgrade at ticket start; saved skill/subagent rules purged; verified end-to-end this run (zero approval prompts across plan/test/dev/review sessions).
- open: machine-global client configs (~/.config/opencode, ~/.config/kilo) still lack the four dev-* mirrors — user action.
- open: OQ2 — dev github-token FIELDS item UUID pasted over OVERRIDE_NEEDED; d8e2b2ca URI field populated (+ WITH_API=true account).
- open: post-sync endpoint verification tools/list mcp.dev.scifi.farm/{playwright,renovate,searxng,boards}/mcp; boards :v<run> pin after first CI build replaces :main if operator prefers pinning.
