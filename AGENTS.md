# AGENTS.md — SpencersLab

GitOps repo for the homelab: Helm charts (`charts/`), ArgoCD ApplicationSets
(`services/`), per-environment value overrides (`custom-values/`), custom
container images (`containers/`). **ArgoCD applies everything — never
`kubectl apply` from this repo.**

## Where things live

- `charts/<name>/` — Helm charts, all built on the bjw-s app-template library.
- `services/<category>/<env>/` — ApplicationSets + values per category
  (gpu, home, infra, media, monitoring, proxy-local, proxy-remote, …).
- `custom-values/<category>/` — private overrides (Bitwarden UUIDs) via `bitwardenIds`.
- `containers/<name>/` — custom images (Dockerfile + CI in `.github/workflows/`).
- `.agents/agents/` — agent definitions. `.agents/plans/` — plan documents named
  `yyyy-mm-dd-short-description.md` (date prefix, **never** a unix epoch).
- `skills/` — self-written skills (`helm-chart-creation`, `container-creation`,
  `llama-swap`). `.agents/skills/` — third-party skills managed by skillfish
  (`skillfish.json`, `skills-lock.json`); don't hand-edit those.

## Agents

- `plan` — writes implementation-ready plans to `.agents/plans/`. Use before any
  non-trivial change.
- `code` — executes plans. Runs in fresh sessions: the plan file tells it which
  skills and MCP servers to load.
- `0-pipeline` + stages `1-`…`7b-` — gated 7-stage SDLC pipeline for large
  features. Start at `0-pipeline`.

## Skills registry

Load with the `skill` tool. Everything here is task-triggered. Skills an agent
loads unconditionally live in that agent's file (`.agents/agents/`), not here.

| Skill | Load when | Notes |
|---|---|---|
| `helm-chart-creation` | Creating/modifying charts or service wiring | self-managed (`skills/`); pairs with `helm-bjw-s-chart` |
| `helm-bjw-s-chart` | Chart work — the bjw-s app-template values/schema API | upstream reference |
| `container-creation` | Adding/editing images in `containers/` | self-managed (`skills/`) |
| `kubernetes-skill` | Authoring/reviewing manifests or charts | complements k8s-troubleshooter |
| `gitops-workflows` | ArgoCD/ApplicationSet/sync/secrets-in-git work | **primary GitOps skill** |
| `argocd-advanced` | ApplicationSet generators, Image Updater, cluster onboarding/bootstrapping | |
| `k8s-troubleshooter` | Live cluster incidents (CrashLoopBackOff, Pending, OOM, PVC, networking) | live debugging; distinct from kubernetes-skill |
| `systematic-debugging` | Any non-obvious bug, before proposing fixes | generic discipline |
| `test-driven-development` | Writing/changing real code (`containers/`, `src/`) | not for YAML-only changes |
| `using-git-worktrees` | Starting isolated feature work | |
| `prometheus` | PromQL, Prometheus HTTP API | API reference |
| `grafana` | Grafana HTTP API (dashboards, datasources, alerting) | API reference |
| `loki` | Loki deployment, LogQL, retention | |
| `traefik` | Traefik ingress/middleware/TLS (`charts/traefik*`, proxy services) | |
| `container-security` | Image scanning (Trivy), Dockerfile hardening (`containers/`) | some ACR-specific content |
| `llama-swap` | llama-swap / llama.cpp work only (`charts/llama-swap`) | self-managed in `./skills/` |
| `wekan-api` | WeKan REST API or `wekan-mcp` server work (`containers/wekan-mcp`, `mcp.wekan` in hivetools, WeKan instances in `services/home/prod`) | self-managed in `./skills/` |

## MCP servers

| Server | Use when |
|---|---|
| `kubernetes` | Nearly always — inspect cluster state, ApplicationSets, pod logs, events |
| `searxng` | Web search: docs, chart research, image versions |
| `playwright` | JS-heavy doc sites, UI verification |
| `homeassistant` | Only for Home Assistant work (`charts/home-assistant`, zigbee2mqtt, music-assistant, or the live HA instance) |

**Keep these lists current:** when a task uses a skill or MCP server not listed
above, add a line to this file (or the relevant agent file) as part of your
change.

## References (read on demand, not upfront)

- `renovate.json` — dependency update rules; keep renovate annotations in
  values files and Dockerfiles intact.
- `skills/helm-chart-creation/references/` — chart templates, ApplicationSet
  patterns, storage/secrets deep-dives.

## Hard rules

- **Never push to `main` — only the user does that.** Agents work on their own
  branch/worktree and commit there. To pick up changes, merge `main` *into*
  your worktree (`git merge main`); never merge your branch into `main` and
  never run `git push origin main`. Landing work on `main` is the user's
  decision alone.
- **Never bump versions or image tags by hand.** `release.yaml` bumps
  `Chart.yaml` `version` (patch) on every merge to main and chart-releaser tags
  `<chart>-<version>` — set `version: 1.0.0` only on a brand-new chart.
  Containers are tag-based: `docker-build.yaml` pushes `:v<run_number>`
  (immutable) + `:<branch>` (`:main`/`:dev`, rolling) on every merge; reference
  `:main` (+ `pullPolicy: Always`) or a `:v<run>` pin.
- Validate chart changes: `helm lint charts/<name>` and
  `helm template charts/<name>` must pass before finishing.
- Secrets: ExternalSecret + Bitwarden only. Placeholder
  `OVERRIDE_VIA_CUSTOM_VALUES` in `services/**/values.yaml`, real UUID in
  `custom-values/<category>/prod-values.yaml`. Never commit real secrets.
- Adding a service = chart entry + ApplicationSet values entry + proxy values
  entry. All three — plus a `custom-values/` entry only when the service has
  secrets needing per-cluster overrides.
- Plans are `yyyy-mm-dd-short-description.md` in `.agents/plans/`.
