# Interview — Helm chart ecosystem

Interviewed 2026-10-21 (inline, single session).

## Q1: Is there an official Forgejo runner chart?

No. The official `forgejo-helm` repo (the OCI chart this repo already wraps
for the server at `charts/forgejo`) is server-only — no runner chart is
published from it, and ArtifactHub shows no `forgejo` org runner chart.
What exists is community material:

- **wrenix/forgejo-runner** — listed on ArtifactHub at v0.7.6 [17], but the
  `runner` chart directory is **absent from the current WrenIX/helm-charts
  main branch** — the listing appears stale or the chart was removed.
  (ArtifactHub API returns HTML to fetches; state assessed via search
  snippets + repo browsing.)
- **dtechvision/forgejo-runner-helm-chart** — v0.0.1, self-described
  untested: Deployment replicas 2, DinD sidecar default
  `docker:28.3.0-dind`, rootless option, **persistence off by default**
  [12]. Its README marketing of a "kubernetes backend" corresponds to the
  **experimental** gRPC plugin (see k8s-homelab-practitioner notes), not a
  shipping feature.
- **gitea.com/gitea/helm-actions** — the Gitea fork's runner chart; not
  Forgejo-compatible (env-var registration model, Gitea image).
- **forgejo-hetzner-runner**, TrueNAS "Forgejo Runner" — VM/bare-metal
  playbooks, not Helm.

## Q2: What is the non-Helm prior art worth stealing from?

- **mother-of-all-self-hosting/ansible-role-forgejo-runner**
  (defaults/main.yml + templates/config.yaml.j2) [22]: the canonical
  declarative `config.yaml` shape — `runner.file`, `server.connections.<name>
  .{url, uuid, token, labels}`, `container.docker_host`, `cache.*` —
  matches the v13 `config.example.yaml` exactly; good cross-check that the
  config surface is stable.
- **gitea/runner examples/kubernetes** [10][11] (see k8s-homelab-practitioner
  notes): the PVC + DinD-initContainer + probes + `terminationGracePeriodSeconds`
  pattern is the strongest prior art for this chart.
- **net-pilgrim k3s gist** [13]: confirms the single-node-k3s shape
  (StatefulSet r=1 + dind) but is stale (runner 4.0.1, dead
  `actions generate-runner-token` command).

## Q3: What does this repo's convention say?

Repo standard (AGENTS.md + helm-chart-creation skill + existing charts):
every chart is hand-rolled on the bjw-s **app-template** library
(currently 5.0.1 in this repo); official charts are only used when
maintained, and even then usually wrapped (`charts/forgejo` wraps
forgejo-helm; `charts/coder` wraps coder). No official runner chart exists
→ a **hand-rolled custom app-template chart** in `charts/forgejo-runner/`
is the convention-conforming path. Extract patterns from the community
charts/examples; do not adopt any of them (all untested/stale, and the
dtechvision chart's persistence-off default is exactly the footshot this
chart must avoid).

Repo conventions the chart must honor (from the skill, verified against
`charts/forgejo` + `services/dev/prod/`):
- `bitwardenIds:` map with `OVERRIDE_VIA_CUSTOM_VALUES` sentinels (the
  runner token is a secret → chart gets a `templates/secret-*.yaml`
  ExternalSecret following `services/dev/prod/templates/secret-forgejo-token.yaml`
  and the `<service>` Bitwarden item naming pattern → item
  `forgejo-runner`, token in PASSWORD field).
- The **trio**: `charts:` entry in `services/dev/prod/values.yaml` +
  `ingress.subdomains` entry + `custom-values/dev/prod-values.yaml` entry
  (only when there are secrets — there are, so all three). Note the runner
  is a *client* (no inbound HTTP) — the ingress entry may be
  placeholder/disabled; the planner should confirm how a non-routable
  service is expressed.
- Pinned image tags with renovate docker-datasource annotations; standard
  security context (drop ALL); resource tiers per the skill; `local-path`
  storage class for PVCs (matches `charts/forgejo`).
