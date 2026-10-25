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
- fixed: OQ2 — 2026-10-24 user ruling + pastes: github-mcp reuses the dev `github-pat` LOGIN item (522b1cc4…, bitwarden-login/password), searxng LOGIN item f90806ff…; contract t9 re-ruled through the test session (6f40db347), template + UUIDs in ddf0167cb; dev-forgejo PLACEHOLDER_ES allowance retired (fail-closed again).
- open: boards precondition remains user-owned — d8e2b2ca item URI field + valid password service account (WITH_API=true) on that instance.
- open: post-sync endpoint verification tools/list mcp.dev.scifi.farm/{playwright,renovate,searxng,boards}/mcp; boards :v<run> pin after first CI build replaces :main if operator prefers pinning.
- open: aislop `scan` is directory-only and its language set excludes YAML/bash, so file-level evidence for values/templates isn't obtainable — workaround: `scan --changes` (repo-wide) + manual comment-slop audit of added lines.
- open: this branch's SHAs diverge from main's cherry-picked copies (branch rebased mid-run); treat `main..HEAD` as provenance only, never merge it into main.

## 2026-10-25 dev-boards post-sync failure (live-cluster diagnosis, C03 reopened)
- ROOT CAUSE (evidence: ArgoCD `dev-hivetools` operationState=Failed "failed to create typed patch object (default/mcp-boards; MCPServer): .spec.secrets: duplicate entries for key [name=wekan-mcp]" + toolhive MCPServer CRD `x-kubernetes-list-type: map` keyed by `name`): C03's boards entry referenced the `wekan-mcp` Secret three times in `spec.secrets[]` — one Secret name may appear only ONCE. MCPServer was never admitted; ingress `/boards` routes to a nonexistent proxy service, so the client catalog shows no dev-boards.
- Rule to remember: a hivetools MCP server needing MULTIPLE keys from one Secret uses `podTemplateSpec` container `envFrom.secretRef` (gpu `homeassistant` precedent), NOT repeated `secrets[]` entries. Repo-wide sweep: dev-boards was the sole offender.
- Ruled out with evidence: image (`:main`==`:v55` carries the C02 login code), Bitwarden item (`wekan-mcp` ES Ready/SecretSynced), ingress route (present), runtime crash (no pod ever created).
- Still unverifiable cluster-side after the fix: the item's URI value (empty vs populated — SecretSynced cannot tell), service-account validity, `WITH_API=true` on the target instance.
