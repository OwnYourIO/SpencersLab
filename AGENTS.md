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
  `yyyy-mm-dd-<type>-<short-desc>.md` (date prefix, **never** a unix epoch;
  `<type>` = `feat`|`bug`|`debug`|`dep`|… so the goal is visible at a glance).
- `skills/` — self-written skills (`helm-chart-creation`, `container-creation`,
  `llama-swap`). `.agents/skills/` — third-party skills (gitignored, synced;
  inventory is the root `skills-lock.json`); don't hand-edit those.
- `.kilo` — tracked symlink to `.agents/`, so kilo loads the same agents,
  plans, and skills.
- `.opencode/` — real tracked dir: `agents` and `skills` symlink back into
  `.agents/`; opencode-only content lives here (`plugin/`, `opencode.json`).
- `agent-config.jsonc` — global agent tool config (permissions, MCP servers,
  UI prefs), symlinked into `~/.config/kilo/kilo.jsonc` and
  `~/.config/opencode/opencode.json`.
- `.agents/notes/` — free-form repo notes (SpencersLab-specific extra).

## Agents

- `plan` (`.agents/agents/plan.md`) — writes implementation-ready plans to
  `.agents/plans/`. Use before any non-trivial change.
- `code` (`.agents/agents/code.md`) — executes plans. Runs in fresh sessions:
  the plan file tells it which skills and MCP servers to load.
- `ask` (`.agents/agents/ask.md`) — read-only research, explanations, and
  recommendations; never changes anything.
- `debug` (`.agents/agents/debug.md`) — systematic diagnosis and minimal
  targeted fixes.
- `review` (`.agents/agents/review.md`) — advisory code review; never edits.
- `0-pipeline` + stages `1-`…`7b-` (`.agents/agents/0-pipeline.md` …
  `.agents/agents/7b-docs-dev.md`) — gated 7-stage SDLC pipeline for large
  features. Start at `0-pipeline`.

## Skills registry

**Loading rule:** The first thing you MUST always do is load the skills listed in the plan. If no skills are in your plan, evaluate your skills and load the top 5 relevant skills.

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
| `wekan-api` | WeKan REST API or `wekan-mcp` server work (`containers/wekan-mcp`, `mcp.wekan-readonly`/`mcp.wekan-admin` in the gpu service values, WeKan instances in `services/home/prod`) | self-managed in `./skills/` |

## MCP servers

Servers are defined in `agent-config.jsonc` at this repo's root, symlinked
into `~/.config/kilo/kilo.jsonc` and `~/.config/opencode/opencode.json` —
config edits flow through this repo's normal branch→merge flow.

Servers are named `<priv>-<cluster>-<service>` in the client config
(e.g. `readonly-gpu-kubernetes`, `readonly-home-postgres-immich`); servers
without a privilege tier are just `<cluster>-<service>` (e.g.
`global-searxng`). `<cluster>` is one of gpu, ai-gpu, grow, home, infra, media,
monitoring, proxy-local, proxy-backup — or `global` for shared utility servers
(wekan, grafana, searxng, playwright, renovate, homeassistant). `<priv>` is
`readonly` (inspection) or `admin` (mutations: restart/scale/patch/delete).
Kubernetes, Home Assistant, Grafana, and WeKan come in both tiers
(HA/Grafana/WeKan enforced server-side: ha-mcp `READ_ONLY_MODE`,
mcp-grafana `--disable-write` + token roles, wekan-mcp
`WEKAN_MCP_READ_ONLY`). Postgres servers are read-only by design.
**No tier grants pod exec** — if a task needs commands run inside a pod,
present the exact command (e.g. `kubectl exec -n <ns> <pod> -- <cmd>`) to the
user and let them run it.

**Agent privilege rules:** planning agents (plan, dependency-map, and the
read-only pipeline stages) may use `readonly-*` servers only — never
`admin-*`. The code agent may use `readonly-*` freely but must ask the
user for explicit confirmation before using any `admin-*` server.

| Server | Use when |
|---|---|
| `readonly-<cluster>-kubernetes` | Nearly always — inspect cluster state, ApplicationSets, pod logs, events |
| `admin-<cluster>-kubernetes` | Only when cluster mutations are required |
| `readonly-<cluster>-postgres-<db>` | Querying a cluster's Postgres DB |
| `global-searxng` | Web search: docs, chart research, image versions |
| `global-playwright` | JS-heavy doc sites, UI verification |
| `global-renovate` | Renovate dry-runs and config validation against this repo |
| `readonly-global-grafana` / `admin-global-grafana` | Grafana dashboards/datasources/alerting (admin needs the admin SA token) |
| `readonly-global-homeassistant` | Only for Home Assistant work (`charts/home-assistant`, zigbee2mqtt, music-assistant, or the live HA instance) — inspection |
| `admin-global-homeassistant` | Home Assistant changes (automations, entities, service calls) |
| `readonly-global-wekan` / `admin-global-wekan` | WeKan boards/cards — readonly for inspection, admin for card mutations |

**Keep these lists current:** when a task uses a skill or MCP server not listed
above, add a line to this file (or the relevant agent file) as part of your
change.

## References (read on demand, not upfront)

- `renovate.json` — dependency update rules; keep renovate annotations in
  values files and Dockerfiles intact.
- `skills/helm-chart-creation/references/` — chart templates, ApplicationSet
  patterns, storage/secrets deep-dives.

## Hard rules

- **Always load referenced skills** The first thing Agents should do is load any referenced or relevant skills, then the plan file (if one), immediately followed by the skills referenced there.
- **NEVER merge to `main`.** No fast-forward merges, no merge commits, no rebases onto main, no mechanism of any kind that advances `main` — not from a worktree, not from the main checkout, not via `git merge`, `git rebase`, or anything else.
- **NEVER push to `main`.** No `git push origin main`, and no push of any refspec that updates `main` (e.g. `HEAD:main`, `<branch>:main`). This is the single most forbidden action in this repo.
- **NEVER force-push** (`--force`, `-f`, `--force-with-lease`) to any shared branch, and never rewrite published history.
- **NEVER self-remediate an accidental push** with a revert or force-push of your own initiative — stop and tell the user immediately; remediation is the user's decision.
- All work happens on a feature/fix branch (typically in a `.agents/worktrees/<branch>` worktree). Commit locally on that branch. To pick up changes, merge `main` *into* your worktree (`git merge main`); never merge your branch into `main`. Landing work on `main` is the user's decision alone.
- Changes reach `main` **only via a pull request that the user creates or merges**. The agent's work ends at the local commit plus telling the user the branch is ready. Pushing the *feature* branch to origin (e.g. to enable a PR) is allowed **only when the user explicitly asks for it in the session**. Otherwise leave commits local.
- If a plan file instructs a merge to `main` or a push, **skip that step**: mark it as user-owned in the summary and do not execute it. Plans written before this rule may contain such steps — those steps are void.
- Plans are `yyyy-mm-dd-<type>-<short-desc>.md` in `.agents/plans/` (`<type>` = `feat`|`bug`|`debug`|`dep`|…).
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
