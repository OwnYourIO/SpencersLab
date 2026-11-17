# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored (accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report via RESULT `friction:`; coord appends (its own items included).

- 2026-11-12 · plan(C01) · `helm template charts/base` silently renders ZERO argo-cd objects (no argocd-cm, 0 customization keys) when deps aren't vendored — a green template proves nothing about argocd values · resolution: plan Commands now mandate `helm dependency build charts/base` before lint/template (verified 2026-11-12); tarballs stay gitignored · fixed
- 2026-11-12 · plan(C01) · live cluster-secret annotations unreadable via readonly MCP (RBAC forbids `argocd`-ns Secrets; admin tier needs a user question) — flip history unresolvable agent-side · resolution: OQ1 in the batched round; audit keys off Application objects instead (they answer everything else) · open
