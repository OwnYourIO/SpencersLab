# RESEARCH — cf-139 feat: Sync ArgoCD with Webhooks

Pre-Research stage, run 2026-11-12 (storm method; live searches + upstream source reads).
Read with EXPLORE.md (repo grounding) — findings below assume its facts. Citations `[n]`
resolve in the Sources section at the bottom. Claims from EXPLORE.md are marked **[E]**.

## TL;DR

1. Webhooks never sync — they only refresh; **automated syncPolicy is what makes pushes land** [4][5][10]. The ticket's root cause is the `services.<cat>.selfHeal:"false"` annotations gating automated OFF on every root app **[E]**.
2. GitHub cannot reach any cluster today: `cluster.<name>.spencerslab.com` is NXDOMAIN on public DNS (measured) and mesh-only by design — "N webhooks → N clusters" and "GitHub Actions syncs each cluster" are both dead without new public exposure (§2).
3. Minimal fix, zero new network surface: flip the annotation gate → roots auto-sync like children already do, worst-case ~3 min detection (120s+60s jitter) [5][11].
4. For seconds-level sync later: ONE public relay webhook (`argocd-hook.<domain>`, crowdsec-only chain) → in-mesh fan-out to each cluster's existing argocd-server `/api/webhook` (§3 shape C).
5. The flip was likely deliberate (bootstrap out-of-band; root app contains ArgoCD itself; prior selfHeal incident) — the plan MUST confirm history with the user before reversing it (§Contradictions, §Open questions).

## Key findings

### Agenda 1 — webhook semantics at chart 10.11.6 / ArgoCD v3.5.6

- **Chart→app version:** argo-cd Helm chart **10.11.6 = ArgoCD appVersion v3.5.6** [16] (answers EXPLORE open q6).
- **Who serves webhooks in 3.x:** the **API server** (`argocd-server`), not the repo-server: `server/server.go` wires the webhook handler [9]; tuning keys are `server.webhook.parallelism.limit` / `server.webhook.refresh.workers` in argocd-cmd-params-cm [19]; 3.5's argocd-cm has **no `repo.webhook.serve` key** [20]. Correspondingly the chart has **no `configs.repoWebhook` values section** — 0 hits in argo-helm commit history [17][18] (a key my working memory invented; re-grounded). The webhook lands on `/api/webhook` of the normal argocd-server route [4] — which already exists per cluster as `cluster.<name>.…:80` **[E]**.
- **REFRESH, never SYNC:** the handler sets `argocd.argoproj.io/refresh` on matching Applications [4][8]; source-level proof: `util/webhook/webhook.go` → `processAppRefresh` → `argo.RefreshApp(..., RefreshTypeNormal, ...)` — no sync call exists in the webhook path [10]. The docs' own framing: webhooks exist "to eliminate this delay from polling" — polling performs the same refresh [4][8].
- **⇒ A refresh webhook alone does NOT sync apps without `syncPolicy.automated`.** It only flips them to OutOfSync (better status visibility; still manual sync).
- **Documented minimum for push→lands:** `spec.syncPolicy.automated` (enabled/prune/selfHeal) on the app [5][12]. Semantics that matter for planning: automated syncs only when OutOfSync; **one sync per commit SHA** (no loops; failed syncs on the same SHA are not re-attempted automatically; selfHeal required to re-sync on live-only drift); rollback unavailable while automated [5]. Detection without webhook: default poll `timeout.reconciliation: 120s` + jitter `60s` ⇒ worst ~3 min [5][11]. Upstream/community consistently frames **automated as the mechanism + webhook as the accelerator** [4][5][1].
- **ApplicationSet has a separate webhook** (its own controller service, ClusterIP, own Ingress needed) that refreshes ApplicationSet resources for *Git generators* [6]. Our appsets use matrix(clusters × list) generators **[E]** → pushes never change the generated set → **not needed here**; the appset template itself is updated by the root app syncing.

### Agenda 2 — fan-out for ONE repo → N independent ArgoCD API servers

**Decisive measurement (live, 2026-11-12, via dns.google/resolve DoH + workspace resolver):**
`cluster.{infra,dev,gpu,home,grow,monitoring,media,gpu-ai}.spencerslab.com` → **NXDOMAIN publicly**; workspace-internal split-horizon → 10.x. `cluster.proxy-local` → public **A 10.0.77.54** (private-IP leak; a rule violation, see Adjacent). `cluster.proxy-remote` → 5.78.101.168 (the zero-trust edge). `skills/helm-chart-creation/references/proxying.md`: cluster-scoped (`clusterBase`) hosts carry no external-dns label, are mesh-only, and "**Don't expose cluster-scoped hosts publicly** (ArgoCD, MCP, traefik dashboards)… OIDC/geoblock assumptions depend on it."
**⇒ Answers EXPLORE open q1: GitHub webhooks cannot reach any cluster's argocd-server today.**

| Shape | Verdict | Why |
|---|---|---|
| **A. N GitHub hooks → N cluster ingresses** | REJECTED | Physically impossible without publishing 7–11 SSO-fronted admin APIs that are mesh-only by design; the documented exemption pattern (crowdsec-only proxy-subdomain, `forms`/`git` precedents **[E]**) would be per-cluster, multiplying edge exceptions; GitHub tolerates N hooks fine (json + HMAC + push per hook, 10s response budget, 422 "spammed" auto-disable on persistent failure) [2][3] — the problem is ours, not GitHub's. |
| **B. GitHub Actions → `argocd app sync` per cluster** | REJECTED as primary | Canonical pattern exists: CLI/API + apiKey local account + `applications sync` RBAC — exactly this repo's existing `mcp-bot` shape **[E]**, mirrored by community practice [1]. BUT all repo CI runs on GitHub-hosted runners (no self-hosted runner in `.github/workflows/`) **[E]** → public-internet → **same reachability wall as A**, plus N long-lived *write-capable* tokens in GitHub secrets (worse blast radius than a refresh-only HMAC, §Agenda 5). Upstream explicitly frames automated sync as removing CI's need for API access [5]. Partial-failure handling (continue-on-error + summary + re-run escape hatch) all addable, but nothing justifies it over A/C once exposure cost is equal. |
| **C. One public relay → in-mesh fan-out** | BEST inbound shape | One GitHub hook → `argocd-hook.<domain>` proxy-subdomain (crowdsec-only chain, forms/git precedent **[E]**; edge geoblock passes GitHub's US deliverers **[E]**) → verify GitHub HMAC once, then POST the payload to each `https://cluster.<name>.spencerslab.com/api/webhook` over mesh DNS (existing ingress, **zero new cluster-side exposure**). Must absorb GitHub's 10s deadline (queue + async forward) [3]; adding a cluster = one relay config line + one secret; per-cluster distinct HMAC secrets are possible via relay re-sign, but one shared webhook secret is the simpler default. |
| D. Centralize (one ArgoCD for all clusters) | REJECTED | Classic hub pattern [7] but contradicts the fleet's every-cluster-runs-its-own topology **[E]**; migration risk unrelated to the ask. |
| E. argocd-notifications | REJECTED | Its webhook service is **outbound** ("trigger a Jenkins job, update GitHub commit status") [15]; notifications are disabled fleet-wide anyway **[E]**. Not a fan-out mechanism. |

**Secrets axis:** webhook HMAC = per-hook, no login, payload trusted-low (§Agenda 5); CI shape = per-cluster PAT/apiKey with sync rights. Reachability identical (both need public ingress except C). Maintainability per new cluster: A +1 hook +1 public exception +1 secret; B +1 secret +1 matrix entry + still blocked; C +1 relay target (+optional re-sign secret).

### Agenda 3 — the annotation-gate axis (flip `services.<cat>.selfHeal`)

- Enabling automated on roots = exactly what children already run fleet-wide (automated+prune+selfHeal) **[E]**; the gate is annotation-driven in both appsets **[E]**; appset-managed apps **cannot** be toggled per-app — only via the ApplicationSet/[annotation] path [5].
- **selfHeal=true in a homelab:** manual kubectl/helm/UI edits get reverted — the canonical homelab pain is documented verbatim ("changes appear to work briefly, then get reverted… root cause selfHeal: true") [13]; HPA-reverted-replicas is the classic sub-issue, solved by ignoreDifferences [14]; note disabling selfHeal doesn't freeze drift in multi-source apps anyway (autosync on any source change) [5].
- **Fleet-specific hazard (strongest argument the flip was deliberate):** the root app's tree **contains ArgoCD itself** (base chart renders argocd **[E]**) — a selfHealing root applies changes to its own controlling server/controller mid-sync. Scar tissue already in-repo: ignoreDifferences entries for `argocd-(server|repo-server|applicationset-controller)` selectors, and a **fired incident** where automated selfHeal re-applied system-upgrade-controller Plans on `/status` drift and SIGTERM'd k3s (comment in `charts/base/values.yaml`) **[E]**. Uniform human flip to "false" across all clusters smells intentional **[E q2]** — user confirmation required.
- **Does automated still need a webhook?** No, only for speed: default poll is 120s+60s jitter (~3 min) [5][11]. Upstream recommended combo for immediacy IS webhook+automated [4][5][1]. For a homelab, poll-only is a legitimate final state; webhook optional.
- Prune risk at root: prune=false by default; enabled here via the existing gate **[E]**; allow-empty protection exists [5]. A push to main normally cannot prune the appset; the realistic prune scenario is a bad git removal — same risk children already carry, but consequences at a root are cluster-wide.

### Agenda 4 — exact landing points in argo-cd chart 10.11.6 values schema

All under the `argo-cd:` subchart key (centralized in `charts/base/values.yaml`) **[E]**:

| Need | Key (verified in chart pkg [17]) | Note |
|---|---|---|
| GitHub webhook secret → argocd-secret | `configs.secret.githubSecret: "<literal>"` | renders `data."webhook.github.secret"` — **literal in git = violates repo rules**, see next row |
| Secret via ExternalSecret | `configs.secret.extra: {"webhook.github.secret": "$<k8s-secret-name>:<key>"}` | `$…` indirection is officially supported; referenced Secret needs label `app.kubernetes.io/part-of: argocd` [8]. New `charts/base/templates/secret-argocd-webhook.yaml` ExternalSecret (mirror `secret-argocd-sso.yaml` **[E]**) + `bitwardenIds.argocd-webhook-secret` in `custom-values/<cat>/prod-values.yaml`. Caveat: argocd-server hot-reloads webhook secrets [9], but re-resolution timing of `$ref` when only the referenced secret rotates is unverified → plan a rollout after rotation. |
| Webhook tuning (optional) | `configs.params."server.webhook.parallelism.limit"` / `.refresh.workers` [19]; `configs.cm."webhook.maxPayloadSizeMB"` / `"webhook.refresh.jitter"` [20] | defaults fine at homelab scale |
| appset webhook ingress (NOT needed) | `applicationSet.webhook.ingress.enabled` / `httproute` | only for Git-generator appsets [6]; ours are matrix(clusters×list) **[E]** |
| repo-server webhook key | **does not exist** | no `configs.repoWebhook` / `repoServer.webhook` in 10.11.6 [17][18] |
| Per-cluster syncPolicy gate | not a Helm value — annotations on the ArgoCD **cluster secret** (`services.<cat>.selfHeal`, plus per-app `services.<svc>.<app>.selfHeal`), read by both appsets' templatePatch **[E]**; flip = per-cluster out-of-band edit (cf-11 human precedent **[E]**) or a templatePatch-default change in git (`services/<cat>/prod/templates/appset.yaml`, `charts/base/templates/appset-charts.yaml` — mind the dev/gpu/gpu-ai template variant drift **[E]**) |

### Agenda 5 — GitHub side + secret storage per repo rules

- Create at **repo** Settings → Webhooks (org-level hook possible but this is one repo; keep repo): Payload URL = the endpoint (C: `https://argocd-hook.spencerslab.com/...`); **Content type must be `application/json`** (form-encoded unsupported by ArgoCD) [4][8]; Secret = random high-entropy string used as HMAC hex-digest key (`X-Hub-Signature-256`) [2][3]; events: push [2] (default for new hooks; GitHub push hooks fire for **all branches** — ArgoCD ref-matching is only documented via the branch/tag-collision caveat [4], so don't *rely* on branch filtering server-side). Ops knobs: 10s respond budget, redeliver API + deliveries list, `X-GitHub-Delivery` replay id, `GET /meta` IP allowlist option, 422 auto-disable on spam/failing endpoints [2][3].
- ArgoCD-side storage per repo rules: ExternalSecret + Bitwarden only → the `configs.secret.extra` + `$name:key` indirection (Agenda 4) is the one shape that keeps the literal out of git AND out of the chart-managed argocd-secret (which Helm re-renders; template warns blank-data wipes keys [17]). Bitwarden: one LOGIN/LOGIN-fields item per concern named `argocd-webhook` (repo item-naming convention **[E]** per helm-chart-creation skill); same item shape feeds the relay's verify secret. Relay-hosting cluster additionally needs each cluster's webhook secret if per-cluster secrets are chosen (shared secret ⇒ relay just forwards).

## Contradictions and how to weigh them

- **Ticket says "webhook"; mechanics say "automated syncPolicy".** Every primary source: webhook = refresh only [4][8][9][10]. Weigh: mechanics — deliver automated-sync-first; webhook as optional stage 2.
- **Immediacy purism vs homelab tolerance.** Upstream sells webhooks to eliminate poll delay [4]; at homelab scale a ≤3-min settle needs no new edge. Weigh: staged plan — poll first, relay later, decide after user input.
- **Blog/CI-tutorial shape (Actions syncs clusters [1]) vs upstream GitOps posture [5] vs this fleet's mesh-only rule.** Weigh: repo architecture + upstream posture over tutorials.
- **Unanimous:** webhook never syncs; public-exposing SSO admin APIs is the wrong tool; notifications can't fan out.
- **Blind spot I had to surface from repo evidence:** root app = ArgoCD's own control plane; flipping its selfHeal makes ArgoCD mutate itself mid-sync (see Agenda 3). No external source covers this — it's this fleet's special case and the single best reason to ask the user before flipping.

## Implications for the plan

1. **Stage 0 (user):** ask the EXPLORE q2 history question with the k3s-incident + self-controller context; get the live cluster-secret annotations read (admin tier or user) **[E]**.
2. **Stage 1 (minimal fix, repo-clean):** enable automated on roots — flip `services.<cat>.selfHeal` annotations per cluster (human, out-of-band, cf-11 precedent) or change the appset gate default in git (needs one manual root sync to propagate; covers future clusters). Add/extend ignoreDifferences for known live-drift writers (HPA replicas etc.) before flipping [14]. Accept ≤~3-min sync latency [5][11].
3. **Stage 2 (optional, only if user wants seconds-level):** relay chart + one proxy-subdomain crowdsec-only entry + GitHub hook + ExternalSecret trio per Agenda 4/5. NO changes to the 7–11 workload clusters' ingress posture; optional per-cluster webhook secret via `$ref` indirection.
4. Do NOT plan: `configs.repoWebhook` (doesn't exist), argocd-notifications fan-out, per-cluster public exposure, GitHub Actions direct sync.
5. Validation shape (repo standard): `helm lint`/`helm template charts/base`, grep trio, sentinel check **[E]**; plus for stage 2 a relay e2e: `gh api`-created test hook / `ping`, deliveries list green, apps flip Synced within seconds of a push.

## Open questions (would-ask; no questions asked per instruction)

1. **Why was `services.<cat>.selfHeal="false"` set on every cluster (EXPLORE q2)?** Proceeding on best guess: deliberate safety around manual bootstrap + self-managing root; plan must confirm.
2. Is the real end-state "webhook-triggered instant sync" or "any push lands automatically" (EXPLORE q3)? Best guess: the latter — poll-fix satisfies the pain; webhook optional.
3. Accept 7–11 long-lived sync tokens in GitHub if Actions-fanout were ever wanted? Best guess: no (blast radius), another reason C > B.
4. One shared GitHub↔fleet webhook secret, or per-cluster with relay re-sign? Best guess: shared initially; per-cluster only if the relay chart already re-signs cleanly.
5. Does the user want the `cluster.proxy-local` public-record leak fixed in this ticket or a separate bug? (Adjacent.)
6. Where to host the relay (proxy-local hub is the natural seat: owns the public-edge hop **[E]**) — user's call on hosting policy.

## Adjacent

- **Public DNS leak:** `cluster.proxy-local.spencerslab.com` publishes a public A record to 10.0.77.54, contradicting the "cluster-scoped hosts must not be publicly published" rule (likely a stray external-dns label or manual record) — worth its own bug card.
- `infra-seaweedfs` OutOfSync + `ServerSideApply:"false"` **[E]** — first sync after a root-gate flip may cascade a real sync; glance before stage 1.
- Renovate manages the argo-cd chart (Non-critical class **[E]**); stage-2 values keys above are verified against 10.11.6 only — re-verify the `configs.secret.*`/`configs.params` shapes on chart bumps.

## TLDR (merged recommendation — planner + claim comment)

> **cf-139 research:** ArgoCD webhooks only *refresh* apps (chart 10.11.6 = ArgoCD v3.5.6); the reason pushes don't land is the `services.<cat>.selfHeal="false"` cluster-secret annotations gating `syncPolicy.automated` OFF on every root app. Direct "GitHub → each cluster" webhooks are impossible as designed: `cluster.*` hosts are mesh-only (NXDOMAIN publicly, by design) — so not N public exposures, and not Actions-token fan-out (same wall + write-token sprawl). **Recommended:** stage 1 = enable automated on roots (annotation flip, human, cf-11 precedent) → pushes auto-land in ≤~3 min via polling, zero new network surface; stage 2 optional for seconds-level = ONE crowdsec-only `argocd-hook.<domain>` relay verifying the GitHub push-hook HMAC once, fanning out in-mesh to each cluster's existing `argocd-server /api/webhook` (secret via ExternalSecret+Bitwarden through `configs.secret.extra: {webhook.github.secret: "$ref:key"}`). Gating risk for the plan: the flip looks deliberate (manual bootstrap; root app contains ArgoCD itself; prior selfHeal k3s-upgrade incident) — confirm history with the user before reversing. Full findings + 20 sources in RESEARCH.md.

## Sources

1. https://oneuptime.com/blog/post/2026-02-26-argocd-github-actions-integration/view — ArgoCD + GitHub Actions integration patterns (token CI sync, apiKey account + sync RBAC; poll+webhook framing). Read 2026-11-12.
2. https://docs.github.com/en/rest/repos/webhooks?apiVersion=2022-11-28 — GitHub REST repository webhooks (content_type json, HMAC-secret config, events=push default, deliveries/redeliver/tests, 422 "endpoint has been spammed"). Read 2026-11-12.
3. https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks — webhook secret guidance, HTTPS, `GET /meta` IP allowlist, 10s response, redelivery, X-GitHub-Delivery replay. Read 2026-11-12.
4. https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/ — ArgoCD Webhook Configuration (stable): poll-every-3-min framing, `/api/webhook`, `webhook.github.secret`, unauthenticated-refresh safety, refresh-annotation mechanics, maxPayloadSizeMB. Read 2026-11-12.
5. https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/ — Automated Sync Policy (read via release-3.5 `docs/user-guide/auto_sync.md`): automated semantics, per-SHA dedup, selfHeal, prune/allow-empty, appset toggle note, 120s+60s jitter. Read 2026-11-12.
6. https://raw.githubusercontent.com/argoproj/argo-cd/release-3.5/docs/operator-manual/applicationset/Generators-Git.md — ApplicationSet webhook is separate from the API-server webhook (ClusterIP service, own ingress required). Read 2026-11-12.
7. https://www.digitalocean.com/community/tutorials/application-deployments-multi-cluster-kubernetes — centralized multi-cluster ArgoCD pattern (snippet-read via search, 2026-11-12).
8. https://argo-cd.readthedocs.io/en/release-3.5/operator-manual/webhook/ — release-3.5 webhook docs incl. `$<k8s_secret_name>:<key>` alternative-secret indirection + `app.kubernetes.io/part-of: argocd` label requirement. Read 2026-11-12.
9. https://raw.githubusercontent.com/argoproj/argo-cd/release-3.5/server/server.go — API-server webhook handler wiring + webhook-secret hot-reload watch. Read 2026-11-12.
10. https://raw.githubusercontent.com/argoproj/argo-cd/release-3.5/util/webhook/webhook.go — webhook handler = `RefreshApp(RefreshTypeNormal)`; no sync path. Read 2026-11-12.
11. https://raw.githubusercontent.com/argoproj/argo-cd/release-3.5/docs/faq.md — "polls Git every 3 minutes… 120 seconds + up to 60 seconds of jitter; `timeout.reconciliation`". Read 2026-11-12.
12. https://raw.githubusercontent.com/argoproj/argo-cd/release-3.5/docs/operator-manual/application.yaml — syncPolicy reference (automated/prune/selfHeal defaults and meaning). Read 2026-11-12.
13. https://pando85.github.io/homelab/troubleshooting/argocd-gitops-workflow/ — homelab: manual kubectl changes reverted; root cause selfHeal (snippet-read, 2026-11-12).
14. https://notes.kodekloud.com/docs/Prep-Course-Certified-Argo-Project-Associate-CAPA/ArgoCD/Demo-ignoreDifferences/page — ignoreDifferences vs autosync/selfHeal/HPA replica reverts (snippet-read, 2026-11-12).
15. https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/services/webhook/ — notifications webhook service is outbound. Read via search snippet, 2026-11-12.
16. https://raw.githubusercontent.com/argoproj/argo-helm/argo-cd-10.11.6/charts/argo-cd/Chart.yaml — chart 10.11.6 `appVersion: v3.5.6`. Read 2026-11-12.
17. https://github.com/argoproj/argo-helm/releases/download/argo-cd-10.11.6/argo-cd-10.11.6.tgz — chart package (values.yaml, README, `templates/argocd-configs/argocd-secret.yaml`, `templates/argocd-applicationset/*`): `configs.secret.githubSecret`/`extra`, `configs.params`, `applicationSet.webhook.ingress`; no repoWebhook. Downloaded + read 2026-11-12.
18. https://github.com/search?q=repo%3Aargoproj%2Fargo-helm+repoWebhook&type=commits — 0 results (no `repoWebhook` ever existed in argo-helm). Run 2026-11-12.
19. https://raw.githubusercontent.com/argoproj/argo-cd/release-3.5/docs/operator-manual/argocd-cmd-params-cm.yaml — `server.webhook.parallelism.limit`, `server.webhook.refresh.workers`. Read 2026-11-12.
20. https://raw.githubusercontent.com/argoproj/argo-cd/release-3.5/docs/operator-manual/argocd-cm.yaml — `webhook.refresh.jitter(.threshold)`, `webhook.maxPayloadSizeMB`; no repo-webhook key. Read 2026-11-12.

Plus repo/live evidence **[E]**: EXPLORE.md; live DoH DNS probes + workspace resolver output (2026-11-12); `skills/helm-chart-creation/references/proxying.md`; `charts/base/values.yaml` (ignoreDifferences incident comment, mcp-bot); `.github/workflows/*` runner labels.

Storm audit trail: /tmp/opencode/storm-cf-139/storm-runs/argocd-webhook-auto-sync-on-push-to-main-for-a-multi-cluster/ (perspectives.md, raw/*.notes.md, contradictions.md, outline.md, report.md incl. reliability notes, sources.md).
