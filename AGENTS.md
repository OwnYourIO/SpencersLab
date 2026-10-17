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
- `.agents/agents/` — agent definitions; a symlink to `.opencode/agents/`,
  the real tracked dir. `.agents/plans/` — plan documents named
  `yyyy-mm-dd-<type>-<short-desc>.md` (date prefix, **never** a unix epoch;
  `<type>` = `feat`|`bug`|`debug`|`dep`|… so the goal is visible at a glance),
  plus per-feature pipeline folders `yyyy-mm/<feature-slug>/` used by the
  `agent-*` pipeline (see below).
- `.agents/plans/templates/` — blank boilerplate (`PLAN.md`, `STATE.json`,
  `DECISIONS.md`, `chunks/`) that `agent-plan` copies into each new feature
  folder.
- `.agents/commands/` — slash commands for the pipeline (`/pipeline`,
  `/pipeline-bmad`, `/pipeline-resume`, `/pipeline-resume-bmad`), exposed to
  OpenCode via the tracked `.opencode/commands` symlink.
- `skills/` — self-written skills (`helm-chart-creation`, `container-creation`,
  `llama-swap`). `.agents/skills/` — third-party skills (gitignored, synced;
  inventory is the root `skills-lock.json`); don't hand-edit those.
- `.kilo` — tracked symlink to `.agents/`, so kilo loads the same agents,
  plans, and skills.
- `.opencode/` — real tracked dir: `agents/` is the canonical home of the
  agent definitions (`.agents/agents` symlinks into it), while `skills`
  symlinks back into `.agents/`; opencode-only content lives here
  (`plugin/`, `opencode.json`).
- `.opencode/opencode.json` — version-controlled OpenCode project config:
  the lab MCP servers, permissions, skills paths and the default agent.
  Merged over the machine-global config. LLM providers (`gpu-ai`/`gpu-moe`
  with per-model `limit.context`) live in the machine-local globals —
  `~/.config/opencode/opencode.json` and `~/.config/kilo/kilo.jsonc` are
  real files since 2026-10-13 (`agent-config.jsonc` and its symlinks were
  removed), so global-config edits are no longer version-controlled here.
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
- `agent-*` (`.agents/agents/agent-{cord,plan,dev,test,review}{,-bmad}.md`) —
  chunk-based pipeline: `agent-cord` (primary) runs an approved plan through
  fresh `agent-plan`/`agent-dev`/`agent-test`/`agent-review` subagents, one
  chunk at a time, with files as the only shared memory. `-bmad` variants
  force-load their BMAD role skills. Artifacts live in
  `.agents/plans/yyyy-mm/<feature-slug>/`. Launch with the `/pipeline`
  commands.

## Feature pipeline (agent-*)

A chunk-based pipeline for multi-step work, complementary to the standalone
`plan`/`code` agents (single-shot planning/implementation) and the
`0-pipeline` SDLC stages (large features with docs):

- `agent-cord` — coordinator; writes only `STATE.json`/`DECISIONS.md`; runs
  Phase 1 (launches `agent-plan`) when no approved plan exists yet.
- `agent-plan`, `agent-dev`, `agent-test`, `agent-review` — subagents, fresh
  context per launch. Files are the bus; every hand-back ends in a RESULT
  block that cord parses. `agent-test` is the mirror of `agent-dev`: it may
  edit only `tests/` (dev may edit everything *except* `tests/`).
- `-bmad` variants — same mechanics, but each MUST load its BMAD role skill:
  plan loads `bmad-agent-pm` + `bmad-spec` + `bmad-ticket`, dev `bmad-build`,
  test `bmad-qa-generate-e2e-tests`, review `bmad-code-review`, cord `bmad`.
  They halt in repos without a `_bmad/` setup (this repo has one).

Commands (`.agents/commands/`): `/pipeline`, `/pipeline-bmad` (plan if
needed, then run) and `/pipeline-resume`, `/pipeline-resume-bmad` (resume an
approved plan; feature folder as argument).

Each feature gets `.agents/plans/yyyy-mm/<feature-slug>/` containing
`PLAN.md`, `STATE.json`, `DECISIONS.md` and `chunks/`, copied from
`.agents/plans/templates/`. `STATE.json` carries the machine state (only
cord writes it); `DECISIONS.md` is the append-only decision log (only
plan/cord write it).

Every agent in the set carries a `## Skills` section at the top of its file:
the standard loading rule, its role's MUST-load `/skill-name` calls (the
`-bmad` variants include their BMAD role skills in the same list), and an
instruction to evaluate the task and load 3 more relevant skills dynamically
at runtime. Skill loading is mandatory, not optional. When dispatching a
subagent, reference the skills it needs with `/skill-name` in the launch
message so they load in that fresh session.

### Pipeline specifics in this repo

- There is no unit-test suite. For the pipeline, "Commands" and "tests" mean
  validation: `helm lint charts/<name>` and `helm template charts/<name>`,
  grep checks for the service trio (chart entry + ApplicationSet values entry
  + proxy values entry), and every `OVERRIDE_VIA_CUSTOM_VALUES` placeholder
  matched 1:1 by a `custom-values/` entry. `agent-plan` records these in
  `PLAN.md` "Commands"; `agent-test` writes them as failing checks under
  `tests/` before implementation; `agent-cord` gates a chunk done only when
  they pass.
- All Hard rules below (no hand-bumped versions, ExternalSecret+Bitwarden
  secrets, ArgoCD — never kubectl apply, git safety, MCP privilege tiers)
  apply to every pipeline agent unchanged.

The agent files themselves are repo-agnostic on purpose (they work the same
in HomeAssistant/CuratedForest); repo grounding lives in this file, which is
loaded into every session automatically.

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
| `storm` | Deep research: "research X", "deep dive", briefings, backgrounder reports, "understand all sides of" a topic — sourced multi-perspective output | third-party (`kunjan-p/storm-skill`); citation-grounded STORM pipeline; pairs with `global-searxng` for the web searches |
| `bmad-*` | The `agent-*-bmad` pipeline variants force-load their role skills: plan `bmad-agent-pm` + `bmad-spec` + `bmad-ticket`, dev `bmad-build`, test `bmad-qa-generate-e2e-tests`, review `bmad-code-review`, cord `bmad` | third-party (`bmad-code-org/BMAD-METHOD`); needs the `_bmad/` setup this repo has |

## MCP servers

Servers are defined in `.opencode/opencode.json` (project-level, merged over
the machine-global config) — edits flow through this repo's normal
branch→merge flow. The machine globals
(`~/.config/opencode/opencode.json`, `~/.config/kilo/kilo.jsonc`) carry the
same fleet list for other projects; since 2026-10-13 they are real files, not
symlinks, so keep them in sync by hand when a server is added or changed.

Servers are named `<priv>-<cluster>-<service>` in the client config
(e.g. `readonly-gpu-kubernetes`, `readonly-home-postgres-immich`); servers
without a privilege tier are just `<cluster>-<service>` (e.g.
`global-searxng`). `<cluster>` is one of gpu, ai-gpu, dev, grow, home, infra,
media, monitoring, proxy-local, proxy-backup — or `global` for shared utility
servers (wekan, grafana, searxng, playwright, renovate, homeassistant). `<priv>`
is `readonly` (inspection) or `admin` (mutations: restart/scale/patch/delete).
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
- **Every agent and subagent must keep `question` allowed** — explicitly, in
  its frontmatter permissions. If not granted explicitly, questions are
  denied by default and stage gates / escalations fail silently.
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
