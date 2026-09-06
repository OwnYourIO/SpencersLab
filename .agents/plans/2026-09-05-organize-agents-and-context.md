# Plan: Organize agents, skills, plans, and context for SpencersLab

## Goal

Reorganize this repo's agent context: date-based plan filenames, a minimal root
`AGENTS.md` that registers skills/MCP servers with load-triggers, two new
HA-style agents (`plan`, `code`) tailored to this GitOps/Helm repo alongside
the existing 7-stage pipeline, removal of three redundant skills, and
conversion of the two root how-to guides into self-managed skills.

## Decisions (confirmed with user)

- Keep pipeline agents `0-pipeline` … `7b-docs-dev`; refresh their outdated
  skills/MCP sections only.
- New agents named `plan` and `code`, placed in the existing plural dir
  `.agents/agents/`.
- Add `helm-bjw-s-chart` to the suggested skills list (all charts use bjw-s
  app-template).
- Remove `gitops-principles` and `monitoring-observability` entirely (delete
  `.agents/skills/<name>/` + `skills-lock.json` entries).
  `ArgocdClusterBootstrapping` is nested inside `argocd-advanced/References/`
  — leave files, drop from registry with a note (its parent routes to it).
- Split `HELM_CHART_CREATION_PRP.md` → `skills/helm-chart-creation/` (SKILL.md
  + `references/`) and `CONTAINER_CREATION_GUIDE.md` →
  `skills/container-creation/SKILL.md`, then delete both root files.
- Self-written skills live in `./skills/` (llama-swap already does; no
  kilo.json change needed — that dir is already discovered).
- Code agent runs in fresh sessions: each plan file must list the skills/MCP
  servers to load.

## Models to copy

- `/home/coder/HomeAssistant/.agents/agent/plan.md` and `.../code.md` —
  structure, permissions pattern, Inputs/Method/Pre-completion-checklist shape.
- `/home/coder/HomeAssistant/AGENTS.md` — tone; ours is shorter and
  registry-focused.

---

## Task 1 — Rename plans to `yyyy-mm-dd-short-description.md`

Epoch → date (UTC): 1785084829358→2026-07-26, 1785468616851→2026-07-31,
1786126572422→2026-08-07, 1786549388220→2026-08-12.

```
git mv .agents/plans/1785084829358-actualbudget-sso-secret-plan.md      .agents/plans/2026-07-26-actualbudget-sso-secret-plan.md
git mv .agents/plans/1785468616851-add-hivetools-mcp-servers.md         .agents/plans/2026-07-31-add-hivetools-mcp-servers.md
git mv .agents/plans/1786126572422-llama-swap-more-models.md            .agents/plans/2026-08-07-llama-swap-more-models.md
git mv .agents/plans/1786549388220-restrict-kubernetes-mcp-secrets.md   .agents/plans/2026-08-12-restrict-kubernetes-mcp-secrets.md
git mv ACTUALBUDGET_SSO_IMPLEMENTATION.md                               .agents/plans/2026-07-26-actualbudget-sso-implementation.md
```

The implementation summary shares the sso-secret plan's date (2026-07-26) per
user instruction. No content edits to these files.

## Task 2 — Uninstall two skillfish skills

- `rm -rf .agents/skills/gitops-principles .agents/skills/monitoring-observability`
- Edit `skills-lock.json`: delete the `gitops-principles` and
  `monitoring-observability` entries. Keep JSON valid.
- Do NOT touch `.agents/skills/argocd-advanced/` (its
  `References/ArgocdClusterBootstrapping/` stays; the registry note below
  tells agents not to load it as a separate skill).
- `skillfish.json` needs no change (it only lists `ha-integration-dev` and
  `home-assistant-best-practices`).

## Task 3 — Split guides into skills, delete root files

### 3a. `skills/helm-chart-creation/` (from HELM_CHART_CREATION_PRP.md)

Frontmatter `description` must trigger on: creating a new Helm chart in
`charts/`, adding a service to the ApplicationSets, wiring Bitwarden
ExternalSecrets for a service, or deciding custom vs external chart. Mention
SpencersLab explicitly.

**`SKILL.md`** (distilled workflow, target ≤300 lines — push bulk to
references/):

- Overview + when-to-use / when-not (official chart exists → don't build).
- Workflow: (1) Research — check artifacthub.io/kubesearch for official
  charts; identify app type (db-backed, auth, web, file-storage) and expected
  env vars; pick a reference chart by complexity tier: `qdrant`=simple
  self-contained, `n8n`=database-backed, `langfuse`=multi-container+Redis,
  `archon`=complex 4-container. (2) Decide custom vs external chart
  (`charts/` vs values-only ApplicationSet entry — see references). (3)
  Scaffold: dir structure, Chart.yaml with app-template dependency. (4)
  values.yaml — point to `references/chart-templates.md`. (5) Secrets —
  Bitwarden stores + sentinel pattern, point to
  `references/storage-and-secrets.md`. (6) Integrate — the trio:
  ApplicationSet entry in `services/<category>/prod/`, proxy values entry,
  `custom-values/<chart>/prod-values.yaml`; point to
  `references/values-and-appset.md`. (7) Validate — the 4 levels: `helm lint`,
  `helm template`, grep services for appset+proxy wiring, file presence check.
- Known gotchas (the CRITICAL list: app-template dependency, CloudNativePG,
  external-secrets+Bitwarden only, domains only in secret templates,
  OVERRIDE_VIA_CUSTOM_VALUES, service name == chart name, localhost only for
  intra-pod, `pg-<svc>-rw` for db access, drop ALL capabilities, every chart
  needs a custom-values file, valueFiles must include service values.yaml).
- Anti-patterns list; override sentinel table (`OVERRIDE_VIA_APPSET` /
  `OVERRIDE_VIA_CUSTOM_VALUES` / `OVERRIDE_NEEDED`); standard security
  context; resource allocation tiers; service category matrix (gpu/home/
  infra/media with appset file paths).
- Pointers: `references/` files, reference charts, `container-creation`
  skill (pair), `helm-bjw-s-chart` skill (upstream app-template API).

**`references/chart-templates.md`**: full YAML bodies from PRP lines ~445-910 —
Chart.yaml pattern, full single-container values.yaml template, pg-*.yaml
CloudNativePG cluster, secret-*.yaml ExternalSecret bodies, pvc-*.yaml,
multi-container notes, external-chart real-world examples
(services/home/prod/Chart.yaml + values.yaml, pg-postiz service-level cluster).

**`references/values-and-appset.md`**: three-tier value loading, service
values.yaml structure, ApplicationSet valueFiles config, custom-values
annotation control (cluster-secret annotations, includeCustomValues), Go
template safety for ApplicationSets (`hasKey`, `dig`, `index`, `default`),
the advanced `chart:` field multi-deployment section, integration points.

**`references/storage-and-secrets.md`**: Bitwarden store structure
(`bitwarden-login` username/password vs `bitwarden-fields` custom fields,
`bitwardenIds` map semantics), common env vars by application type, shared
storage pattern (SeaweedFS PV/PVC, conditional chart PVC via
`index .Values "shared-storage"`, hivetools knowledge worked example).

**`skills/container-creation/SKILL.md`**: near-verbatim conversion of
CONTAINER_CREATION_GUIDE.md (238 lines, already skill-shaped) — add
frontmatter (`description` triggers on: adding a custom image under
`containers/`, Dockerfile conventions, ghcr.io/ownyourio publishing,
docker-build workflow, VERSION auto-bump, renovate ARG pins); fix the stale
"Pair it with HELM_CHART_CREATION_GUIDE.md" line to reference the
`helm-chart-creation` skill.

### 3b. Delete root files

- `git rm HELM_CHART_CREATION_PRP.md CONTAINER_CREATION_GUIDE.md`
- Grep repo for references to both filenames; update any hits (AGENTS.md is
  handled in Task 4; check `charts/*/README.md`, code-workspace files,
  `.agents/agents/*`).

## Task 4 — Create root `AGENTS.md` (new, minimal)

````markdown
# AGENTS.md — SpencersLab

GitOps repo for the homelab: Helm charts (`charts/`), ArgoCD ApplicationSets
(`services/`), per-environment value overrides (`custom-values/`), custom
container images (`containers/`). **ArgoCD applies everything — never
`kubectl apply` from this repo.**

## Where things live

- `charts/<name>/` — Helm charts, all built on the bjw-s app-template library.
- `services/<category>/<env>/` — ApplicationSets + values per category
  (gpu, home, infra, media, monitoring, proxy-local, proxy-remote, …).
- `custom-values/<name>/` — private overrides (Bitwarden UUIDs) via `bitwardenIds`.
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

Load with the `skill` tool. "Always" is per-agent as noted; everything else is
task-triggered.

| Skill | Load when | Notes |
|---|---|---|
| `writing-plans` | Always — plan agent | |
| `executing-plans` | Always — code agent | |
| `helm-chart-creation` | Creating/modifying charts or service wiring | self-managed (`skills/`); pairs with `helm-bjw-s-chart` |
| `helm-bjw-s-chart` | Always for chart work — code agent | upstream bjw-s app-template API reference |
| `container-creation` | Adding/editing images in `containers/` | self-managed (`skills/`) |
| `kubernetes-skill` | Authoring/reviewing manifests or charts (near-always — code agent) | complements k8s-troubleshooter |
| `gitops-workflows` | ArgoCD/ApplicationSet/sync/secrets-in-git work | **primary GitOps skill** |
| `argocd-advanced` | ApplicationSet generators, Image Updater, cluster onboarding/bootstrapping | covers what ArgocdClusterBootstrapping had (its `References/`) — never load nested reference skills separately |
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

Removed 2026-09-05: `gitops-principles` (redundant with `gitops-workflows`),
`monitoring-observability` (use the dedicated prometheus/grafana/loki skills),
`ArgocdClusterBootstrapping` (subset of `argocd-advanced`).

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

- Validate chart changes: `helm lint charts/<name>` and
  `helm template charts/<name>` must pass before finishing.
- Secrets: ExternalSecret + Bitwarden only. Placeholder
  `OVERRIDE_VIA_CUSTOM_VALUES` in `services/**/values.yaml`, real UUID in
  `custom-values/<name>/prod-values.yaml`. Never commit real secrets.
- Adding a service = chart entry + ApplicationSet values entry + proxy values
  entry. All three.
- Plans are `yyyy-mm-dd-short-description.md` in `.agents/plans/`.
````

## Task 5 — Create `.agents/agents/plan.md` (new)

Model on `/home/coder/HomeAssistant/.agents/agent/plan.md`. Frontmatter:

```yaml
---
description: Planning agent for this GitOps/Helm repo. Turns infrastructure requests (new chart, service change, ApplicationSet, secrets, monitoring, debugging) into verified, implementation-ready plans grounded in this repo and the cluster. Use before any non-trivial change.
mode: all
color: "#8b5cf6"
steps: 30
permission:
  read: allow
  glob: allow
  grep: allow
  list: allow
  skill: allow
  question: allow
  todowrite: allow
  todoread: allow
  edit:
    ".agents/plans/**": allow
    "*": deny
  bash:
    "git status*": allow
    "git log*": allow
    "git diff*": allow
    "ls *": allow
    "helm lint*": allow
    "helm template*": allow
    "*": ask
---
```

Body sections (adapted from HA plan agent):

1. **Role** — turns infra requests into verified, implementation-ready plans;
   only writable output is `.agents/plans/`; the code agent implements them.
   Point at AGENTS.md for layout/rules/registries.
2. **The Iron Law** — "VERIFY EVERY FILE, CHART, VALUES KEY, AND APPLICATIONSET
   AGAINST THE REPO — NEVER GUESS." Before planning resolve: artifact type
   (new chart / values change / ApplicationSet / ExternalSecret / container /
   CI), exact files touched, behavior + edge cases. Ask with `question` when
   ambiguous.
3. **Workflow** — clarify → recon (`charts/`, `services/<cat>/<env>/`,
   `custom-values/`, existing similar services; for new charts load the
   `helm-chart-creation` skill, for new containers `container-creation`) →
   optionally inspect cluster via `kubernetes` MCP → render-check with
   `helm template` where useful → write plan.
4. **Plan file naming** — `.agents/plans/yyyy-mm-dd-short-description.md`,
   date prefix, never epoch.
5. **Plan output format** — same skeleton as HA's, with `## Skills` and
   `## MCP Servers` sections mandatory (the code agent starts in a fresh
   session and loads exactly what the plan lists), plus Verified context
   (files/charts found in recon), Design decisions, Changes (ordered,
   one file per step), Verification (`helm lint`, `helm template`, ArgoCD
   sync outcome), Risks & open questions.
6. **Skills** — always: `writing-plans`. Task-triggered: copy the registry
   table from AGENTS.md.
7. **MCP servers** — copy the registry table from AGENTS.md.

## Task 6 — Create `.agents/agents/code.md` (new)

Model on `/home/coder/HomeAssistant/.agents/agent/code.md`. Frontmatter:

```yaml
---
description: Implementation agent for this GitOps/Helm repo. Edits charts, services, custom-values, and containers following repo patterns, validates with helm lint/template, and lets ArgoCD sync. Use after a plan exists or for small, well-scoped changes.
mode: all
color: "#f59e0b"
steps: 60
permission:
  read: allow
  glob: allow
  grep: allow
  list: allow
  skill: allow
  question: allow
  todowrite: allow
  todoread: allow
  edit:
    "charts/**": allow
    "services/**": allow
    "custom-values/**": allow
    "containers/**": allow
    "skills/**": allow
    ".agents/plans/**": allow
    ".github/**": ask
    "*": ask
  bash:
    "git status*": allow
    "git log*": allow
    "git diff*": allow
    "ls *": allow
    "helm lint*": allow
    "helm template*": allow
    "*": ask
---
```

Body sections (adapted from HA code agent):

1. **Role** — implements approved plans from `.agents/plans/yyyy-mm-dd-*.md`;
   edits in place; the edit is the deliverable. Point at AGENTS.md.
2. **Inputs** — plan file given: load the skills + MCP servers it lists first
   (fresh session — nothing carries over), then implement its Changes section
   in order; plan vs reality mismatch → stop and surface, don't redesign.
   No plan: request must be small and unambiguous; ask first otherwise; create
   a plan file after the work is confirmed. Read every file before editing;
   match surrounding style.
3. **Method** — verify each file/values key exists → edit one plan step at a
   time (new charts: `helm-chart-creation` skill governs; new containers:
   `container-creation`) → `helm lint charts/<name>` +
   `helm template charts/<name>` after chart changes, fix and re-validate →
   for new services confirm the trio (chart, ApplicationSet values, proxy
   values) → report; never `kubectl apply` — ArgoCD syncs.
4. **Pre-completion checklist** — helm lint/template pass (or explicitly
   noted as skipped); secrets via ExternalSecret + `bitwardenIds` placeholder +
   custom-values entry; bjw-s app-template conventions followed; ApplicationSet
   + proxy values updated for new services; renovate annotations preserved;
   plan file exists and is named `yyyy-mm-dd-*`.
5. **Skills** — always: `executing-plans`; near-always: `helm-bjw-s-chart`,
   `kubernetes-skill`; task-triggered: copy registry table from AGENTS.md.
6. **MCP servers** — copy registry table from AGENTS.md.

## Task 7 — Refresh pipeline agents' skills/MCP sections

- `0-pipeline.md`: replace the hardcoded skills bullet list and the MCP line
  (`git`, `github`, … `filesystem`) with a pointer to the AGENTS.md registries,
  keeping its stage-routing text intact.
- Stage agents `1-feature-generation` … `7b-docs-dev.md`: in each "Skills and
  MCP servers" section, replace stale lists with a one-line pointer to the
  AGENTS.md registries plus any accurate stage-specific note (e.g.
  `2-dependency-map`: searxng for package info — and drop its incorrect
  classification of `k8s-troubleshooter` as an MCP server).
- Do not change pipeline logic, gates, permissions, or stage outputs.

## Task 8 — Validation

1. `ls .agents/plans/` — six date-prefixed files, zero epoch names;
   `ACTUALBUDGET_SSO_IMPLEMENTATION.md` gone from root.
2. `AGENTS.md` exists at root and every path it references exists (`charts/`,
   `services/`, `custom-values/`, `containers/`, `.agents/agents/`,
   `.agents/plans/`, `skills/helm-chart-creation/`, `skills/container-creation/`,
   `skills/llama-swap/`, `renovate.json`).
3. `.agents/agents/plan.md` and `code.md` have valid YAML frontmatter and
   appear alongside pipeline agents.
4. `skills/helm-chart-creation/SKILL.md` + 3 reference files and
   `skills/container-creation/SKILL.md` exist; root
   `HELM_CHART_CREATION_PRP.md` and `CONTAINER_CREATION_GUIDE.md` deleted;
   `rg -l "HELM_CHART_CREATION_PRP|CONTAINER_CREATION_GUIDE"` returns nothing
   outside `skills-lock.json`-free docs (fix any hits).
5. `.agents/skills/gitops-principles/` and `monitoring-observability/` gone;
   `skills-lock.json` parses (`jq . skills-lock.json`) and lacks both entries.
6. Grep pipeline agents: no remaining references to MCP servers `git`,
   `github`, `fetch`, `filesystem` as available servers.
7. No changes under `charts/`, `services/`, `custom-values/` in this work.

## Risks / notes

- `.kilo` is a symlink to `.agents`; use `.agents/` paths in docs for
  consistency.
- Removing the two skillfish skills only touches `skills-lock.json` + dirs;
  if a future skillfish sync restores them, remove them from whatever
  skillfish source list re-adds them.
- The PRP contains session-specific "Known Good Examples" — distill to file
  pointers (reference charts) rather than copying stale session output.
- New skill names sit next to third-party `helm-bjw-s-chart`; the registry
  notes disambiguate (upstream API reference vs this repo's end-to-end
  workflow).
