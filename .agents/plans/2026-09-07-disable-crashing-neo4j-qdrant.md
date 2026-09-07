# Plan: Disable crashing workloads on the gpu and home-lab clusters

## Goal
Stop crash-looping workloads on two clusters by removing them from ArgoCD
management through GitOps config, using **reversible disables** that preserve
data (PVCs) and shared secret wiring. Also remove the dangling Hugo ingress
routes.

- **gpu cluster:** neo4j (CrashLoopBackOff) and qdrant (CreateContainerConfigError).
- **home-lab cluster:** hugo-help (CrashLoopBackOff), scifi-farm (crash-looping),
  zigbee2mqtt-remote (CrashLoopBackOff / Degraded).
- **home-lab hygiene:** remove the dangling `help:`/`love:`/`grow:` Hugo ingress
  entries (their backend Services do not / will not exist).

**Out of scope (explicitly):** wekan-mcp (gpu, per user); mongodb drift (home —
config drift, not a crash; it is wekan's DB, do NOT disable); the hugo-grow /
hugo-love Chart.yaml dependencies themselves (left as no-op deps — only their
dangling ingress routes are removed); the gpu llama-swap `Unknown` orphan pod.

## Skills
Code agent runs in a fresh session — load:
- `helm-chart-creation` — primary: services/<category>/<env>/values.yaml wiring
  (`charts:` / `ingress.subdomains` / umbrella-chart subcharts) and the helm
  lint/template validation convention.
- `gitops-workflows` — context for why removing a `charts:` entry / subchart
  values makes the ApplicationSet prune the ArgoCD Application.

## MCP Servers
- `kubernetes` (readonly tier) for BOTH clusters — the gpu cluster and the
  home-lab cluster (`kubernetes-home-readonly`). Use to confirm current crash
  state if needed and, post-sync, that the workloads and ingress routes are gone.

## Verified context
Recon 2026-09-07 via kubernetes-readonly (gpu + home-lab) + repo reads
(worktree `clean-up-failing-pods`).

**gpu crashers:**
- `gpu-neo4j-…` CrashLoopBackOff, exit 1: `Failed to read config: Unrecognized
  setting … name: PASSWORD` (secret-sourced `NEO4J_PASSWORD` env misread by
  Neo4j's env→config mapping). Wired in `services/gpu/prod/values.yaml`:
  `charts.neo4j` (60–62), `ingress.subdomains.neo4j` (183–186),
  `bitwardenIds.neo4j` sentinel (19). Uses `existingClaim` → PVC `neo4j` (20Gi)
  not chart-owned.
- `gpu-qdrant-…` CreateContainerConfigError: `secret "qdrant" not found` (no
  `bitwardenIds.qdrant` exists anywhere). Wired: `charts.qdrant` (63–65),
  `ingress.subdomains.qdrant` (178–181). Uses `existingClaim` → PVC `qdrant`
  (10Gi) not chart-owned.

**home-lab crashers:**
- `home-hugo-help-…` CrashLoopBackOff 42d (~11.9k restarts). Hugo can't load
  module `github.com/OwnYourIO/SpencersLab/sites/help` — repo has no `sites/`
  dir and `git log -- sites` is empty (never existed). **Deployed as an
  `app-template` subchart dependency** (alias `hugo-help`) of the home umbrella
  chart (`services/home/prod/Chart.yaml` 54–57), values in the top-level
  `hugo-help:` block (`values.yaml` 1066–1225), ingress `help:` (183–185). No
  PVC/secret. The Chart.yaml also has `hugo-grow`/`hugo-love` app-template deps
  with NO values blocks that render nothing — proof an empty-values app-template
  dep is safe.
- `home-scifi-farm-…` crash-looping (140 restarts since reboot). Same class:
  Hugo can't load `…/sites/grow` (its imports come from
  `custom-values/home/prod-values.yaml` `scifi-farm:` block). Wired:
  `charts.scifi-farm` (`chart: hugo`, 23–28), `ingress.subdomains.scifi-farm`
  (99–102). No PVC/secret.
- `home-zigbee2mqtt-remote-…` CrashLoopBackOff, ArgoCD app Degraded. Can't reach
  remote adapter `home-zigbee2mqtt-remote.spencerslab.com:6638` →
  `EHOSTUNREACH 10.0.3.195`. Wired: `charts.zigbee2mqtt-remote` (`chart:
  zigbee2mqtt`, 75–80), `ingress.subdomains.zigbee-remote` (125–128). Uses
  `existingClaim: {{ .Release.Name }}` → PVC `home-zigbee2mqtt-remote` (1Gi)
  survives. Its `zigbee2mqtt` Bitwarden id is **shared with zigbee2mqtt-coord**
  (`custom-values/home/prod-values.yaml` 83–88) — must NOT be removed.

**Dangling Hugo ingresses (home-lab):** `ingress.subdomains.help`/`love`/`grow`
(`values.yaml` 183–191) render Ingress resources `help-ingress`/`love-ingress`/
`grow-ingress`. Verified against the live Service list: `home-hugo-help` exists
(removed when hugo-help is disabled), but **`home-hugo-love` and
`home-hugo-grow` do not exist** (hugo-love/hugo-grow are no-op deps). So
`love:`/`grow:` are pure dangling routes; after this change `help:` is too.

**ArgoCD state (home-lab):** apps `home-scifi-farm` (Progressing),
`home-zigbee2mqtt-remote` (Degraded); hugo-help lives inside the main `home`
app, which is **OutOfSync due to separate mongodb drift** (StatefulSet/home-mongodb
+ 2 Services + 1 ConfigMap) — disabling these clears the hugo/zigbee
Progressing/Degraded but will NOT make `home` fully Synced (mongodb drift remains).

**Render checks performed:** `helm template services/gpu/prod` → exit 0.
`helm template services/home/prod` → fails without `helm dependency build`
(umbrella chart deps not vendored); `services/home/prod/values.yaml` confirmed
valid YAML via python yaml parse.

## Design decisions
- **Disable = remove from GitOps config, not delete pods.** All these apps have
  `automated.prune/selfHeal`; deleting pods/Deployments would be reverted by
  ArgoCD. Removing the config removes the generated ArgoCD Application (or the
  subchart's rendered resources), which then prunes the workload.
- **Repo convention = comment out** (matches the commented `langfuse`/`langgraph`
  chart entries). Commenting keeps changes trivially reversible and self-documenting.
- **Ingress entries are disabled alongside** each workload so no route points at a
  removed Service. The pre-existing dangling `love:`/`grow:` Hugo routes (no
  backend Service ever existed) are removed at the same time.
- **PVCs + shared secrets are intentionally left** (reversible, no data loss).
  neo4j/qdrant/zigbee2mqtt-remote all use `existingClaim` (not chart-owned), so
  removal never deletes the PVC.
- **hugo-help disable mechanism = remove its values block, keep the Chart.yaml
  dependency.** An app-template dependency with no values renders nothing
  (hugo-grow/hugo-love already do this), so no Chart.lock regeneration / network
  `helm dependency update` is needed. Re-enable = restore the block. (Optional
  deeper cleanup — removing the Chart.yaml dependency — requires regenerating
  Chart.lock; not done here.)
- **wekan-mcp (gpu) and mongodb drift (home) left untouched** per scope.

## Changes

### gpu cluster — `services/gpu/prod/values.yaml`
1. [MODIFY] comment out `charts.neo4j` (lines 60–62) + a why/re-enable note.
2. [MODIFY] comment out `charts.qdrant` (lines 63–65) + note.
3. [MODIFY] comment out `ingress.subdomains.qdrant` (lines 178–181).
4. [MODIFY] comment out `ingress.subdomains.neo4j` (lines 183–186).
   Leave `bitwardenIds.neo4j` (19) and `custom-values/gpu/prod-values.yaml` as-is.

Example for step 1:
```yaml
  # Disabled 2026-09-07: CrashLoopBackOff (neo4j env/config bug). Re-enable by
  # uncommenting; PVC `neo4j` and bitwardenIds.neo4j left in place.
  #neo4j:
  #  namespace: default
  #  ServerSideApply: "false"
```

### home-lab cluster — `services/home/prod/values.yaml`
5. [MODIFY] comment out `charts.scifi-farm` (lines 23–28) + note.
6. [MODIFY] comment out `ingress.subdomains.scifi-farm` (lines 99–102) + note.
7. [MODIFY] comment out `charts.zigbee2mqtt-remote` (lines 75–80) + note.
8. [MODIFY] comment out `ingress.subdomains.zigbee-remote` (lines 125–128) + note.
9. [MODIFY] remove the top-level `hugo-help:` values block (lines ~1066–1225),
   leaving a short disable comment in its place. Do NOT touch `Chart.yaml` or
   `Chart.lock` (the `alias: hugo-help` dependency stays and renders nothing).
10. [MODIFY] comment out the Hugo ingress block `help:` (183–185), `love:`
    (186–188) and `grow:` (189–191). `help:` goes with the hugo-help disable;
    `love:`/`grow:` are dangling (backend Services `home-hugo-love`/
    `home-hugo-grow` never existed). Leave `custom-values/home/prod-values.yaml`
    (scifi-farm + zigbee2mqtt-remote blocks and the shared `zigbee2mqtt`
    bitwardenId) untouched. Do NOT remove the hugo-grow/hugo-love Chart.yaml deps.

Example for step 9 (replacement for the removed block):
```yaml
# hugo-help disabled 2026-09-07: CrashLoopBackOff — Hugo module
# github.com/OwnYourIO/SpencersLab/sites/help does not exist in this repo, so the
# site can never build. The `alias: hugo-help` app-template dependency stays in
# Chart.yaml and renders nothing (like hugo-grow/hugo-love). Re-enable by restoring
# the previous `hugo-help:` values block (see git history) and the `help:` ingress.
```

Example for step 10:
```yaml
    # Hugo site ingress routes disabled 2026-09-07. `help:` backed home-hugo-help
    # (disabled above); `love:`/`grow:` were dangling — home-hugo-love /
    # home-hugo-grow Services never existed (no-op Chart.yaml deps).
    #help:
    #  service: home-hugo-help
    #  port: 1313
    #love:
    #  service: home-hugo-love
    #  port: 1313
    #grow:
    #  service: home-hugo-grow
    #  port: 1313
```

Do NOT change: any chart under `charts/`, wekan-mcp/hivetools (gpu), mongodb or
wekan (home), `custom-values/**`, `services/home/prod/Chart.yaml`/`Chart.lock`,
or any version/image tag. No version bumps.

## Verification
Config-level (Code agent, pre-commit):
1. `helm lint services/gpu/prod` and `helm template services/gpu/prod` → pass.
2. `python3 -c "import yaml; yaml.safe_load(open('services/home/prod/values.yaml'))"`
   → valid YAML. (Full `helm template services/home/prod` needs
   `helm dependency build services/home/prod` first — run only if network is
   available, as the thorough check.)
3. Grep proof:
   - gpu values: no active `neo4j:`/`qdrant:` under `charts:` or
     `ingress.subdomains`; `bitwardenIds.neo4j` sentinel still present.
   - home values: no active `scifi-farm:`/`zigbee2mqtt-remote:` under `charts:`;
     no top-level `hugo-help:` block; `scifi-farm:`/`zigbee-remote:`/`help:`/
     `love:`/`grow:` ingress entries all commented; `zigbee2mqtt-coord:` still active.
   - `custom-values/gpu/prod-values.yaml` and `custom-values/home/prod-values.yaml`
     unchanged; `services/home/prod/Chart.yaml` + `Chart.lock` unchanged.
4. `git diff` shows only the intended commented/removed blocks in the two values files.

Live (post-merge — Code agent commits to its branch/worktree only; NEVER pushes to
main; ArgoCD syncs from main after the user merges):
5. gpu: `gpu-charts-appset` drops `gpu-neo4j`/`gpu-qdrant`; apps + Deployments/
   Services/ExternalSecrets pruned; no `gpu-neo4j-*`/`gpu-qdrant-*` pods. PVCs
   `neo4j`/`qdrant` remain.
6. home-lab: `home-charts-appset` drops `home-scifi-farm`/`home-zigbee2mqtt-remote`;
   the `home` app no longer renders `home-hugo-help`; no `home-hugo-help-*`,
   `home-scifi-farm-*`, `home-zigbee2mqtt-remote-*` pods. PVC
   `home-zigbee2mqtt-remote` remains; `home-zigbee2mqtt-coord` still runs.
7. home-lab ingress: `help-ingress`/`love-ingress`/`grow-ingress` are gone
   (no dangling Hugo routes).
   NOTE: the `home` app may still report OutOfSync due to the separate mongodb
   drift — expected, not caused by this change.

## Risks & open questions
- **ApplicationSet orphan handling:** removing generator entries should delete the
  owned ArgoCD Applications and cascade-prune their resources. If an Application or
  its resources linger post-sync, delete the stale ArgoCD Application once
  (GitOps-managed; never `kubectl apply`).
- **Data retained, not destroyed:** neo4j (20Gi), qdrant (10Gi),
  zigbee2mqtt-remote (1Gi) PVCs are kept. Reclaiming space is a separate, explicit step.
- **hugo-help leaves a no-op Chart.yaml dependency** (renders nothing). Optional
  later cleanup: remove the `alias: hugo-help` dependency AND regenerate Chart.lock
  (`helm dependency update`, network) — not part of this change.
- **Root causes (if re-enabling later instead of staying disabled):**
  - neo4j — fix the env/config collision (secret-sourced `NEO4J_PASSWORD` parsed as
    a Neo4j setting); inject the password without a `NEO4J_*`-named env.
  - qdrant — add a `bitwardenIds.qdrant` entry (values + custom-values UUID) so its
    ExternalSecret renders the `qdrant` secret.
  - hugo-help / scifi-farm — add the missing Hugo content (`sites/help`, `sites/grow`)
    to the repo or point the module imports at a real content source.
  - zigbee2mqtt-remote — restore/reach the remote Zigbee adapter (10.0.3.195:6638),
    or confirm it is decommissioned.
- **mongodb drift (home)** is a separate OutOfSync issue on wekan's DB; investigate
  separately — do not disable.
