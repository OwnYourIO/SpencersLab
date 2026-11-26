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

---

# RESEARCH round 2 — vault-direct fan-out (remove the relay hop)

Appended 2026-11-23 (reopen2, STATE `reopen2.reason`: "secrets belong in the Forgejo
Actions vault (delimited input), fan-out direct to clusters, not via proxy-local relay
hop"). Citations `[n]` ≥ 21 resolve in the new Sources block at the bottom; `[P2]` =
live read-only probes run this round; `[R]` = repo reads this round. Prior-round claims
relied on are marked [E]/[P] per the sections above. Nothing implemented; the shipped
branch code is the comparison baseline throughout.

## TLDR (recommended shape + owner calls)

1. **Endpoint: direct `https://cluster.<cat>.<domain>/api/v1/...` from the runner job.**
   Measured [P2] from the gpu cluster's own pod network — which IS the runner's network
   (main-sync jobs execute in the dind of the `gpu-forgejo-runner-gpu` pod, live-verified
   1/1 Ready): **10 of 11 targets answer TLS-verified (LE chain OK, no `-k` needed) and
   API-shaped (401 unauth / redirect-then-UI); proxy-backup (10.0.77.5) is SILENT from
   this vantage** (TCP 443/80 timeout, no ping — dead host or filtered, unknown, no
   readonly MCP). Mesh DNS reaches pods transparently (k3s CoreDNS `forward . /etc/resolv.conf`
   → LAN split-horizon resolver) [P2].
2. **Vault shape: ONE secret `ARGOCD_SYNC_TOKENS`, NEWLINE-delimited `cat:token` lines** —
   not the owner's floated comma/space. Evidence: forgejo-runner's masker splits
   multi-line secret values on newline boundaries and registers EVERY LINE as an
   independently masked string [26]; a comma/space single-line blob masks only as a whole
   string, so an accidental single-token echo (traceback, debug line) leaks unmasked —
   the exact "structured data as a secret" hazard GitHub's docs name [28]. JWT tokens
   contain no commas/spaces/newlines, so any delimiter parses safely [30][31]; the
   per-record newline form keeps per-record masking granularity. Roster (cat → URL) is
   NOT secret: repo-side config file riding the checkout (or a `vars.ARGOCD_ROSTER`
   var), so fleet additions stay PR-reviewable.
3. **Logic home: option (b) — `scripts/argocd-fanout.py` (stdlib-only python3) + a
   checkout step in the hook job.** Precedent: `scripts/forgejo-container-detect.sh` run
   by containers-build from its checkout [R]; the act image has python3/curl/openssl
   proven by five shipped workflows using them on this exact runner family [R][35].
   150 lines inline (a) is ugly and bash `-n` can't lint it; the image-as-job-container
   shape (c) IS supported by Forgejo (`jobs.<id>.container.image` [23]) but pins a
   never-re-pulled image + manual bump law [23][24] to keep an image lane that only a
   future relay would need; argocd-CLI+kubeconfigs (d) breaks the repo's
   "workflows install no tools at run time" law and adds 11 kubeconfig blobs (worse
   masking shape).
4. **Disposition: the relay layer disappears branch-local — it was NEVER DEPLOYED**
   ([P2]: no `proxy-local-argocd-hook` Deployment/Ingress on proxy-local; custom-values
   still `OVERRIDE_NEEDED`). Clean delete: `charts/argocd-hook/`,
   `containers/argocd-hook/`, both proxy-local trio entries (charts + `argocd-hook`
   subdomain = the R2 public door — with no relay to serve it, the door is moot), the
   custom-values block, the HMAC vault pair (`vars.ARGOCD_HOOK_URL`/
   `secrets.ARGOCD_HOOK_SECRET`), the relay + wiring test suites, and the runbook's
   Step-0 Bitwarden legs (items: none; token mints: 11, now pasted into the forge vault).
   No cluster-side teardown, no revert choreography: rollback = revert the PR.
5. **Needs owner input (3):** (A) delimiter ruling — newline vs the floated comma/space
   (best guess: newline, per §2 evidence); (B) proxy-backup — skip-and-warn today + a
   human reachability check, or fix its route first (best guess: warn-and-skip posture,
   the fan-out already isolates per-target); (C) token lifetime — keep indefinite
   mints (revocable via `argocd account delete-token` [33]) + rotation-by-vault-edit, or
   mandate `--expires-in` + a rotation treadmill that NEEDS a human admin leg (mcp-bot is
   apiKey-only and cannot self-mint [R]) (best guess: keep indefinite, document revoke).

## 1. Runner reachability & identity [P2]

**Where jobs run.** The prod forge instance (git.spencerslab.com, infra) hands main-sync
jobs to the **gpu cluster's** runner: registration relocated there 2026-11-05 per the
chart's own history [R `charts/forgejo-runner/values.yaml:1-14`], wired by
`services/gpu/prod/values.yaml` top-level slice (`runner.url: https://git.spencerslab.com`,
no labels override ⇒ the chart's five act labels) [R]. Live pod state: StatefulSet
`gpu-forgejo-runner-gpu` 1/1 Ready, containers `runner` (data.forgejo.org/forgejo/runner:13.2.0)
+ restartable initContainer `dind` (docker:29.9.2-dind, `--mtu=1450`) [P2] — the docker
backend, jobs = containers spawned by that in-pod daemon, i.e. **inside the gpu cluster's
network namespace chain** (pod net → dind bridge NAT → node SNAT → LAN). The dev
instance's jobs (git.scifi.farm) run on the dev cluster's own runner — irrelevant here
(main-sync guards `contains(vars.ROLE,'prod')`).

**DNS.** gpu's k3s CoreDNS is stock: `hosts` file carries only the node itself;
`forward . /etc/resolv.conf` sends everything else to the node's upstream = the LAN
split-horizon resolver [P2 configmap read]. That resolver answers all 11 `cluster.*`
forms from the lab vantage (this session runs in a gpu-cluster Coder workspace —
gpu in-cluster names resolve here, dev/infra's do not [P2], so the workspace vantage =
the runner vantage). A dind job container inherits the pod's resolv.conf by docker's
standard behaviour (inference, not measured — the dispatch smoke is the proof leg).

**Per-target matrix (measured 2026-11-23 from a gpu pod):**

| target host (roster form) | DNS | TLS (verified, no -k) | API answer | note |
|---|---|---|---|---|
| cluster.dev.scifi.farm | 10.0.77.12 | ok | 401 | the chart `clusterHosts` exception, unchanged |
| cluster.home-lab.spencerslab.com | 10.0.3.78 | ok | 401 | the other exception, unchanged |
| cluster.gpu.spencerslab.com | 10.0.22.205 | ok | 401 | |
| cluster.gpu-ai.spencerslab.com | 10.0.99.151 | ok | 401 | |
| cluster.grow.spencerslab.com | 10.0.3.5 | ok | 401 | |
| cluster.infra.spencerslab.com | 10.0.77.59 | ok | 401 | |
| cluster.media.spencerslab.com | 10.0.77.9 | ok | 401 | |
| cluster.monitoring.spencerslab.com | 10.0.99.129 | ok | 401 | |
| cluster.proxy-local.spencerslab.com | 10.0.77.54 | ok | 307→200 | redirect lands on the login UI page (unauth); API needs the bearer either way |
| cluster.proxy-backup.spencerslab.com | 10.0.77.5 | — | **timeout** | TCP 443+80 filtered, ping dead — NEW finding, see below |
| cluster.proxy-remote.spencerslab.com | 5.78.101.168 | ok | 401 | the public edge serves its argocd route |

Consequences: (a) **TLS trust is a non-issue** — per-cluster LE wildcard certs validate
against a normal ca-certificates store (curl verified without `-k` on every live host)
and the act-24.04-family image is full Ubuntu [35]; (b) the "mesh-only DNS" prior-round
claim survives and *helps*: no public exposure is needed by anyone — the relay hop
existed to fan out from proxy-local, but the runner sits on the same LAN-reachable
vantage; (c) **proxy-backup is the one reachability risk of dropping the hop**: the
relay's own vantage (proxy-local hub, same 10.0.77.x subnet) could reach it, the gpu
runner cannot (today, reason unknown — no readonly MCP for that cluster; EXPLORE §5
manual row). Design must keep per-target isolation (already shipped behaviour: one dead
target ⇒ `failed` audit line, others proceed [R main.py `drive_target`/`fan_out`]) and
the runbook needs an owner leg to check the box or its route. (d) The prior round's
rejected "shape B" (GitHub-hosted Actions → clusters) died on PUBLIC reachability
[NXDOMAIN, §Agenda-2 above]; that objection does NOT apply to self-hosted Forgejo
runners inside the lab network — this round's measurements are the answer.

**Runner tool inventory** (fan-out script shape): the act image family carries
git/git-lfs, jq, **python3**, node, yq, docker CLI, apt [R `containers/forgejo-runner/README.md`, 35]
(that upstream tag set is now declared unmaintained by Gitea, which moved its own runner
images to buildpack-deps bases — irrelevant to this ticket's digest-pinned fork, but the
successor fact belongs on the fleet's renovate-class radar [36]);
curl is proven across `release.yaml` (5 sites) and `containers-build` (7) on this runner
family; **openssl** by the shipped `hook-relay` signing line [R main-sync:128 — note
that job's own live proof is the still-owner-owned dispatch smoke, C03-fix §5(a)]. The fan-out therefore
needs NOTHING baked beyond what the runner already has IF written stdlib-only (the
current `main.py` is: json/urllib/hashlib/threading only [R]) — no pyyaml, no pip,
honouring the "install nothing at run time" law [R AGENTS.md + forgejo-runner README].

## 2. Delimited vault-input patterns

**Forgejo mechanics.** Secrets: repo/org/user key-value stores, encrypted in the DB,
surfaced as `${{ secrets.KEY }}`; once added, the value can't be viewed and is replaced
by overwriting [21]. Secrets are omitted for fork-PR jobs; the instance auto-provides a
same-repo-only token [21][22]. Injection shape: `${{ secrets.X }}` in a `run:` body is
interpolated into the step script the runner writes — safe-ish (masked in logs) but the
literal lands in the job container's script file; the universally recommended shape is
an `env:` mapping consumed as `$X` [27][29][38]. `jobs.<id>.container.env` also
exists if the job container shape were chosen [23].

**Masking (the decisive difference vs GitHub)**: forgejo-runner's reporter masks every
log row through `mask.go` — single-line secrets via a cached `strings.Replacer`; a
multi-line secret value is **split on newlines and each line registered as its own
masked string, plus the whole-blob matched across log rows** (buffered lookahead);
candidates are sorted longest-first so a line never partially redacts ahead of the
blob [26 file:line detail]. Practical read: **newline-delimited = 11 independently
masked `cat:token` strings** — an accidental echo of one token is `***`. Comma/space-
delimited single-line = ONE masked string; echoing a split-off token is a leak. The
shared caveats still apply and are shape-independent: only exact matches are masked
(base64/upper-cased/derived copies leak [28][29]), `set -x` prints expansions before
masking sees them in some lanes [29] — but the runner masks every row it forwards [26],
and the repo's `set -euo pipefail` head (no `-x`) is suite-pinned [R t6]. `::add-mask::`
is supported across the runner family for run-time-derived values [39] — not needed
here (nothing derives), noted for completeness. GitHub's own guidance generalises:
"Never use structured data as a secret … create individual secrets for each sensitive
value" [28] — a newline-lines form is the middle road the owner asked for that keeps
per-record masking.

**Charset safety**: ArgoCD local-account tokens are JWTs — base64url + dots, no
whitespace/comma/[=] in practice [30][31 pattern]; category names are `[a-z0-9-]`; URLs
carry `:`/`/` but no comma/space. Any of `,` / ` ` / `\n` / `;` parses cleanly; pick on
MASKING grounds (→ newline), not on charset. Parsing recipe robust to both ruling
shapes: read the env var in python and `re.split(r'[,\s]+', ...)` if the owner insists
on comma/space, but **recommend** newline records with an explicit
`cat=token` (or `cat:token`) pair form; reject any line whose token doesn't look like a
JWT (loud config error, the relay's `ConfigError` doctrine ported [R]).

**Alternative shapes judged**: 11 separate secrets (`ARGOCD_TOKEN_DEV`, …) = per-value
masking (strongest), GitHub-best-practice [28], but 11 vault rows to hand-edit per
fleet change and an expression-context wall: `${{ secrets[matrix] }}`-style selection is
NOT supported [21][25] — a single script reading a map is fine (env each), a per-matrix-
job lookup is not. JSON/YAML blob secret = explicitly warned against by [28]; forgejo's
line masker saves the per-line pieces (JSON lines would even mask), but a pretty-printed
blob masks worse and adds a parser failure class. **Verdict: one secret, newline records.**

## 3. Security trade-off vs shipped shape

| axis | shipped (relay + Bitwarden ES) | vault-direct |
|---|---|---|
| token resting place | k8s Secret on proxy-local (projected mount) + Bitwarden item, static until rotation [R] | encrypted at rest in the forge DB, materialised only in the running job container (minutes) [21] |
| token in-flight | relay pod env-less file read at startup | server→runner task payload (FetchTask delivers secrets to the runner process; legacy shape held ALL repo secrets in runner memory, the expansion shape trims [23-discussion]) |
| exposure classes | anyone/anything with proxy-local Secret-read or pod-exec; the mounted file lives for the pod's life | job-container env/`/proc`, the step script if interpolated instead of env-mapped, run logs (masked [26]); forge vault read access |
| HMAC layer | needed: an internet-reachable POST endpoint (R2 door) must authenticate callers | **dead weight**: no inbound surface exists; auth = per-cluster bearer tokens, which are STRONGER identity (per-target, individually revocable) |
| blast radius if forge repo/Actions compromised | relay trigger keys only (sync still needs the cluster-side tokens — NOT in the vault) | 11 sync tokens + `PUSH_TOKEN_GH` + `PUSH_TOKEN_DEV` land in one crown-jewel store — BUT: that store already grants main-push, and with children/roots tracking GitHub-manifests a main-write is already near-sync-equivalent power in this design; the marginal gain (skipping the human sync step) is small. The Bitwarden vault (the alternative "safe place") itself holds every cluster's secrets, so total lab blast radius is unchanged; only WHICH store breaks changes [R AGENTS.md + EXPLORE] |
| token TTL | same tokens under both: `argocd account generate-token` default `--expires-in 0s` = **never expires**; JWT carries iat/no exp [30][33] | same; vault posture adds the OPTION of short-lived mints, but rotation needs an admin leg (mcp-bot is apiKey-only, cannot self-mint; admin session JWTs die in 24h [31]) — automation would need admin creds in the vault too, a strictly worse store |
| revocation | re-mint on cluster → Bitwarden field → ES 1h refresh → reloader restart | re-mint on cluster → `argocd account delete-token` (or update the account's token list) kills the old JWT server-side [31][33] → overwrite the vault row → **next run uses the new one immediately** (no 1h refresh window, no pod restart) |
| rotation story | two vaults must agree for the HMAC (the runbook's must-agree pair + 401 diagnosability [R runbook §2]) | one store; nothing to keep in sync |

Net: vault-direct is *equal or better* on every axis except "which store is the crown
jewel" (already true today: the vault holds the GitHub main-push token — the design's
weakest accepted link [R]). The relay's `local:`-last ordering loses its rationale (the
relay process no longer lives on proxy-local and cannot restart itself mid-fan-out) [R];
ordering becomes cosmetic. The R2 public door and the dual-dialect HMAC verifier exist
only to serve an external caller — with the caller IS the workflow, both go (unless the
owner separately wants to keep the relay alive purely as the door's backend — then this
whole ticket stays as shipped; flagged as call C-adjacent, best guess: the owner's
direction kills it).

## 4. Where the fan-out logic lands (this repo's conventions)

(a) **Inline `python3 - <<'PY'` heredoc, no checkout.** Precedent: the shipped payload
builder is a 1-line `python3 -c` [R main-sync:123]. Cost: ~120–150 lines of relay logic
(list→match→sync→settle→sweep, 409-tolerance, timeouts, audit lines — port from
`main.py` minus HTTP/HMAC/event-gate) wedged into a YAML run block; t13's `bash -n`
syntax-checks the block but nothing lints the python; roster has to come from
vars/secret anyway. Verdict: workable, degrades maintainability badly at this length.

(b) **`scripts/argocd-fanout.py` + `actions/checkout@v7` in the job** (RECOMMENDED).
Precedent: containers-build runs `scripts/forgejo-container-detect.sh` from its checkout
[24-rules R: `.forgejo/workflows/containers-build.yaml`, `scripts/forgejo-container-detect.sh`];
main-sync's own push jobs already prove checkout works on this runner (t8 pins a checkout
step on push-dev [R]). Cost: one added step (default shallow clone — push jobs need
`fetch-depth: 0` for push negotiation, the fan-out job does NOT need history at all)
[re-read]; suite amendment: t9's "no uses: steps" leg flips to "exactly the pinned
checkout"; python-compile leg (`python3 -m py_compile scripts/argocd-fanout.py`) joins
the static suite naturally [R plan Commands style]. Roster: `scripts/argocd-fanout.json`
(or `.yaml` — but runner pyyaml is NOT guaranteed; JSON, stdlib-parsed, wins) — the
chart `clusterHosts` + `targetCategories` + `trackedRepo` + `allowedRefs` values fold
into this one repo-side file; fleet additions = one PR (same review surface as today's
chart values, minus Bitwarden).

(c) **Image-as-job-container (`container: image: …argocd-hook:<calendar-tag>`).**
VERIFIED supported in Forgejo — `jobs.<id>.container.{image,entrypoint,env,credentials,
volumes,options}`, with sharp edges: the daemon never re-pulls a tag it has cached
(manual bump law again, like the runner labels [23][24][R forgejo-runner bump law]);
`volumes` restricted to an operator allow-list, `options` restricted to a small set;
custom images without node break `uses:` steps — fine if the job skips checkout and
carries the roster in-image or via env. Keeps `containers/argocd-hook` as the logic
home (add a `--fanout` mode: read roster+tokens from env, sync, exit) and keeps its CI
build lane alive for a door the owner is dropping. Verdict: viable, but it buys nothing
over (b) at the cost of the image lifecycle — only choose it if the owner wants the
relay IMAGE kept warm for the R2 door's possible future.

(d) **argocd CLI + kubeconfig-per-cluster.** Rejected on repo law: workflows install no
tools at run time [R AGENTS.md, containers README — the very reason the forgejo-runner
image exists]; CLI download-at-run breaks the digest-pinned supply posture; and 11
kubeconfigs are opaque multi-line YAML blobs (worse masking shape than `cat:token`) plus
a secret axis (cluster-admin-ish creds) strictly stronger than the get+sync tokens the
design has deliberately kept narrow.

**Suite contract deltas** (all shapes share these, (b) adds the checkout legs):
`tests/services/forgejo-main-sync.sh` t3 job set keeps 3 jobs (the hook job may rename);
t5's key matrix swaps `vars.ARGOCD_HOOK_URL`+`secrets.ARGOCD_HOOK_SECRET` for the token
secret (+optional roster var) exactly-once pair; t9's no-`uses:` leg flips under (b);
t10's `sha256=`/`X-Hub-Signature-256` ban stays trivially satisfiable (no HMAC at all —
consider extending the ban to `X-Forgejo-Signature`); t11 contract tokens fully re-pinned
(heredoc/env shape, timeouts, per-target audit line form); t12 warn-and-exit-0 posture
carries over verbatim (unset ⇒ skip; per-target failures logged, job green — the R1
"never break the mirror" doctrine [R]); t13 keeps `bash -n`, adds `python3 -m
py_compile` of the fanout script (b) or the heredoc extract (a).
`tests/containers/argocd-hook-relay.sh` (1173 L) and `tests/services/argocd-hook-wiring.sh`
retire under (a)/(b)/(d); (b)'s new offline suite `tests/services/forgejo-argocd-fanout.sh`
inherits the relay suite's behaviour tests minus the HTTP handler (app_matches byte-compare,
targetRevision sweep, 409-as-success, settle semantics all port as pure-function tests —
the harness already binds a fake server, the same trick ports to a fake transport).

## 5. Dispositions if the relay dies (clean-removal checklist)

Branch-local only — **[P2] confirmed nothing from C01–C04 was ever deployed** (no
`proxy-local-argocd-hook` Deployment, no `argocd-hook` Ingress on proxy-local, sentinels
unfilled). Rollback for a future release = revert the PR; there is no cluster-side
cleanup leg, ever.

1. `git rm -r charts/argocd-hook containers/argocd-hook`.
2. `services/proxy-local/prod/values.yaml`: delete the `argocd-hook:` charts: entry
   (lines ~60–64) AND the `proxy.subdomains.argocd-hook:` crowdsec-only entry
   (~144–151) — the R2 door dies with its backend (owner call).
3. `custom-values/proxy-local/prod-values.yaml`: delete the `argocd-hook:` bitwardenIds
   block (~46–55).
4. Tests: delete `tests/containers/argocd-hook-relay.sh`,
   `tests/services/argocd-hook-wiring.sh`; add the fanout suite (§4); re-pin
   `tests/services/forgejo-main-sync.sh` (§4); re-pin `tests/notes/argocd-hook-runbook.sh`.
5. `.forgejo/workflows/main-sync.yaml`: rewrite the `hook-relay` job body to the
   vault-direct fan-out (header comment block reworded: origin unchanged, transport now
   per-cluster API, instance key names).
6. Logic port from `containers/argocd-hook/main.py`: KEEP root-first-then-children,
   settle-delay (10s default), `app_matches` byte-compare vs `trackedRepo`, per-app live
   `targetRevision` match (OQ7 layer 2), 409/"already in progress" as success, per-target
   timeout + isolation, prune=false in query AND body, audit-line format. DROP: HTTP
   server, HMAC verify, event/ref-header gates (the job knows its own ref), `local:`
   self-last ordering, `--check` mode (replace with a `--dry-run`/`--list` that the smoke
   step can run), `targets.json` ConfigMap.
7. CI lane: deletion is self-safe — containers-build detection filters changed names by
   `[ -f containers/$n/Dockerfile ]` at HEAD, a deleted dir never enters the build list
   [R forgejo-container-detect.sh]. Any `pr-*` tags already minted on the dev instance
   registry for argocd-host dies with normal registry hygiene (owner, note in runbook).
8. Instance-side vault keys (owner legs, shrinking): DELETE `ARGOCD_HOOK_URL` var +
   `ARGOCD_HOOK_SECRET` secret (or rename both — kill-switch semantics move to the
   tokens secret's presence); ADD the tokens secret; Bitwarden: NEVER-created items
   `argocd-hook` + `argocd-hook-tokens` stay uncreated — the runbook's Step-0 collapses
   from "2 Bitwarden items + 11 fields + HMAC + 2 vault keys + UUID fill + crash-loop
   explanation" to "1 vault secret + 11 token pastes". Token mints (human, unchanged
   shape): `argocd account generate-token --account mcp-bot` per cluster, now against
   the cluster's OWN route host (the same hosts the job will call, §1 — the appendix
   table moves verbatim).
9. **Roster fate (the "still 11 URLs somewhere" answer)**: `targetCategories`,
   `clusterHosts` (dev/home exceptions), `trackedRepo`, `allowedRefs` move from chart
   values to the repo-side fanout config (§4b) — where they keep PR reviewability and
   test pinning; the final-review live-verification ruling ("route truth — correct them
   against live Ingresses, never guess" [R values comment]) transfers with them.

## 6. Community precedent

No published "Forgejo Actions job fans out to N ArgoCD API servers" precedent found
(searched this round). The nearest published shapes, all corroborating the direct-API
leg: (i) ArgoCD's own CI-automation docs: loop `argocd app sync` / REST `POST
/api/v1/applications/<app>/sync` with a local-account apiKey or project-role token, CLI
downloadable from the API server itself [32][33]; (ii) GHA marketplace actions of exactly
the shape "address + token + app → sync" (omegion/argocd-application-sync-action,
cheelim1/argocd-sync-actions, iamops-team/argocd-api — comma-separated app lists) [37] — all
SINGLE-server per invocation; multi-server at fleet scale is normally solved by ONE
central ArgoCD (rejected here, prior Agenda-2 shape D — the fleet's every-cluster-runs-its-
own-ArgoCD topology stands [E]) or a CI matrix over servers; (iii) blogs (oneuptime CI
sync guide, devopscube) use a bash loop over a per-cluster server/token list — the vault
`cat:token` shape is the same idea with stronger masking. The plan can cite these as
"CI-side sync fan-out is mainstream; our in-mesh endpoint choice is what the prior round
proved possible; the runner-vantage measurement (§1) is the new proof this round."

## Contradictions (this round) & how to weigh

- **Owner's floated comma/space vs per-record masking evidence [26]**: newline wins on
  security grounds; comma/space still work functionally. Weigh: recommend newline,
  present comma as the fallback if the vault UI workflow hates multi-line pasting (not
  verified against the live instance UI — owner leg).
- **Prior round rejected "CI syncs clusters" (shape B)** — this round's design IS that,
  minus the fatal premise: shape B died because GitHub-hosted runners can't reach
  mesh-only hosts (§Agenda-2 [E] measurement). Self-hosted lab runners can (§1 [P2]).
  Not a reversal, a premise change — the plan should say so explicitly.
- **"Best practice: always expire tokens" [34] vs this fleet's rotation mechanics**
  (§3 TTL row): expiry without an automated rotator converts a leak-posture into an
  outage-posture (the fan-out silently 401s after expiry, warn-and-green hides it until
  noticed). Weigh: indefinite + vault-overwrite rotation + revoke command documented.
- **Single-secret (owner) vs one-secret-per-value ([28] GitHub doctrine)**: forgejo's
  line-splitting masker [26] neutralises most of the structured-blob hazard — the
  contradiction is platform-specific, resolve in favour of owner's single delimited
  secret.
- **Blind spot this round**: dind container DNS inheritance is inferred (standard docker
  behaviour), not measured; the dispatch smoke must be the acceptance leg for §1
  reachability, same role it played for the relay URL hop.

## Implications for the plan (what the re-cut should look like)

1. R1's race resolution SURVIVES untouched: still the main-sync job after `needs:
   push-gh` [P §3]; only the transport changes (no POST-to-relay — direct per-cluster
   API). trackedRepo stays the GitHub URL; the skipped×11 trap note [P §3] stands.
2. Wave re-cut: the four fix-round chunks (C01-fix/C02-fix/C03-fix/C04) become
   SUPERSEDED — the shipped relay contract they pin dies. New chunks ≈ one (container
   deletion + fanout script + config), one (workflow job rewrite + suite re-pin), one
   (runbook rewrite); chart/service/custom-values deletions ride the first. C01–C03
   commits stay DONE-at-review history (same as the 2026-11-21 reopen treated them).
3. Human-owned list shrinks (per §5.8) and the must-agree-two-vaults problem vanishes.
4. The plan must pin the token-line grammar and an explicit
   `cat not in roster ⇒ loud line-level error` posture (a typo'd category silently losing
   a cluster is the fan-out's only new silent-failure class vs today).
5. Keep the OQ7 ref model: the script only runs for refs in its config list; with
   `on: push.branches:[main]` + dispatch that already holds [R t2], but the per-app
   `targetRevision` match is what protects a future widened roster — port unchanged.
6. Add per-target parallelism or tightened timeouts: worst-case serial today ≈ 11 ×
   (list 60s + settle 10s + list 60s + children) against the runner's 30m ceiling [R
   renovate.yaml comment, 25]; 4-thread fan-out (stdlib) or 20s timeouts keep it minutes.

## Open questions (this round — accumulated, no questions asked)

1. **Delimiter ruling**: newline records (evidence-preferred, §2) vs the floated comma/
   space (single masked blob, split-token echoes leak unmasked). Best guess: newline.
2. **proxy-backup**: dead box, or route/filtered — owner to verify from a vantage that
   can; meanwhile ship it in the roster with warn-and-skip (per-target isolation already
   logs it). Best guess: keep listed, add a runbook preflight row (the §6 table moves).
3. **R2 door**: confirmed-dead with the relay, or does the owner want a relay-less
   public hook path (which would need SOME in-cluster inbound component → contradicts
   the reopen's premise)? Best guess: door goes.
4. **Token expiry posture** (§3, call C): indefinite + revoke (best guess) vs
   `--expires-in` with a scheduled human/CI rotation leg (would need admin creds in the
   vault — worse).
5. Does the tokens secret stay repo-scoped or org-scoped on the prod instance [21]?
   Best guess: repo-scoped (single consumer repo; org scope widens read surface).
6. Instance-side key hygiene leg: owner deletes the now-moot `ARGOCD_HOOK_URL`/
   `ARGOCD_HOOK_SECRET` pair (or the plan keeps the URL var name for something else).
7. The chart's `clusterHosts` doctrine ("correct against live Ingresses, never guess")
   — does the fanout config file inherit the final-review's harness leg that greps the
   host set against a live-verified list? (readonly MCP, smoke-time, best guess: yes.)

## Sources (round 2, numbered continuing from round 1)

21. https://forgejo.org/docs/latest/user/actions/basic-concepts — secrets: repo/user/org scopes, `${{ secrets.KEY }}`, encrypted in DB, value immutable-in-place after add; automatic token aliases. Read 2026-11-23.
22. https://forgejo.org/docs/latest/user/actions/security — runner redacts secrets from logs; do-not-print caveat; fork-PR secret omission; container vs host runner trust. Read 2026-11-23.
23. https://forgejo.org/docs/latest/user/actions/reference — jobs.<job_id>.container.image/entrypoint/env/credentials/volumes/options (+services); "once downloaded never updated" caution; volumes allow-list; entrypoint override mechanics; node requirement for `uses:` steps. Read 2026-11-23.
24. https://forgejo.org/docs/latest/admin/actions/configuration — label syntax `<name>:docker://image`, multi-label runs-on, label image overridable by jobs.<id>.container. Read 2026-11-23.
25. https://forgejo.org/docs/latest/user/actions/github-actions — familiarity-not-compatibility; known differences (default env, missing github-context keys, some job subkeys ignored — `permissions`, `continue-on-error`). Read 2026-11-23.
26. https://deepwiki.com/project-mirrors/forgejo-runner/2.3-task-reporting-logs-and-secret-masking — mask.go architecture: newline-split registration of multi-line secrets, longest-first ordering, whole-blob cross-row matching, cached single-line replacer (file:line cites internal/pkg/report/mask.go 14–149). Read via search-index body 2026-11-23 (direct fetch rate-limited; source tree itself Anubis-gated — flag for smoke-time if the claim is load-bearing).
27. https://docs.gitea.com/usage/actions/secrets + https://hoop.dev/blog/gitea-actions-secrets — sibling platform: exact-match masking confirmed; transformed/encoded copies leak; repo>org precedence. Read 2026-11-23.
28. https://docs.github.com/en/actions/reference/security/secure-use — "Never use structured data as a secret"; register derived values; masking is a log filter, not a boundary; short values poorly protected. Read 2026-11-23.
29. https://builder.aws.com/content/3M3cZHtghA7BymHTyfBJ7s5yaO8/secrets-in-git-hub-actions-logs-find-and-prevent-leaks — set -x leak class, ACTIONS_STEP_DEBUG, retention. Read 2026-11-23.
30. https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_account_generate-token — `--expires-in` default "0s" = no expiration; `--id` token labeling. Read 2026-11-23.
31. https://argo-cd.readthedocs.io/en/stable/operator-manual/security — JWT-only auth; admin session tokens 24h; project-token revocation by jti; password update revokes session tokens. Read 2026-11-23.
32. https://argo-cd.readthedocs.io/en/latest/user-guide/ci_automation — CI authentication menu (project role token / local apiKey account / Dex exchange / --core); CLI served from the API server. Read 2026-11-23.
33. https://argo-cd.readthedocs.io/en/stable/user-guide/user-management + https://oneuptime.com/blog/post/2026-02-26-argocd-account-commands — generate-token/delete-token lifecycle; non-expiring-token warning ("without --expires-in the token never expires"). Read 2026-11-23.
34. https://oneuptime.com/blog/post/2026-02-26-argocd-api-tokens-service-accounts — rotation-schedule table, least-privilege account posture. Read 2026-11-23.
35. https://github.com/catthehacker/docker_images — act-* image description (the base of the repo's job image); tool-completeness vs full image. Read 2026-11-23.
36. https://blog.gitea.com/runner-images-ubuntu-26.04 — catthehacker/ubuntu declared unmaintained upstream; successor images buildpack-deps-derived (context for the job image's future, not its present inventory). Read 2026-11-23.
37. https://github.com/marketplace/actions/argocd-application-sync-action · https://github.com/marketplace/actions/argocd-sync-actions · https://github.com/iamops-team/argocd-api — single-server address+token sync actions, comma-separated app-list precedent. Read 2026-11-23.
38. https://oneuptime.com/blog/post/2026-02-26-argocd-trigger-sync-ci-pipeline — CLI vs REST vs webhook trade-off table for CI sync; curl sync-body shape. Read 2026-11-23.
39. https://gitea.com/gitea/runner (secret-masking section) + job-hooks docs — family behaviour: `::add-mask::`, masking on every log path (local job.log, summaries, container names). Read 2026-11-23.

Plus repo/live evidence **[P2]**: per-target DNS/TLS/HTTP matrix + gpu-pod vantage
confirmation + coredns Corefile + `gpu-forgejo-runner-gpu` pod spec (all 2026-11-23,
readonly MCP + workspace shell, no admin used); **[R]**: `.forgejo/workflows/main-sync.yaml`,
`charts/forgejo-runner/values.yaml`, `services/{dev,gpu}/prod/values.yaml`,
`containers/forgejo-runner/README.md`, `containers/argocd-hook/{Dockerfile,main.py}`,
`charts/argocd-hook/{values.yaml,templates/*}`, `services/proxy-local/prod/values.yaml`,
`custom-values/proxy-local/prod-values.yaml`, `scripts/forgejo-container-detect.sh`,
`tests/services/forgejo-main-sync.sh` (t1–t13), `tests/services/argocd-hook-wiring.sh`
(header), runbook + ticket-folder docs, STATE.json reopen2.

---

# RESEARCH round 3 — dynamic discovery research (reopen4, 2026-11-26)

Appended 2026-11-26 per STATE `reopen4` (owner direction: "the 11 shouldn't be
hardcoded into the job. Instead, they should be detected dynamically and passed
in"). Question under test: is reopen3's premise — DECISIONS 2026-11-25 R7 /
micro-call (d), citing [21][25]: "`${{ secrets[matrix] }}` unsupported, Forgejo
cannot index secrets dynamically" — an ENGINE limitation, or only a limitation of
the `${{ secrets.NAME }}` reference syntax? Citations `[n]` ≥ 40 resolve in the
Sources block at the bottom; `[R3]` = repo reads this round. Every finding is
tagged **[docs]**, **[source]**, **[community]**, or **[unverified→probe]**.

## TLDR (verdicts)

1. **PREMISE REFUTED at the engine level [source].** The Forgejo server builds
   EVERY task with the COMPLETE merged secrets map — `getSecretsOfJob` →
   `FetchActionSecrets(ownerID, repoID)` fetches ALL owner(org) + repo secrets
   (no reference scan), decrypts, adds the three token aliases, and ships the
   whole map in `runnerv1.Task{Secrets: …}` alongside `Vars` [43][44][46]. The
   act-derived evaluator keeps `secrets` as a first-class context object and
   `toJSON` is an unconditional function [40][41][49][50].
2. **toJSON(secrets): supported** — docs list `toJSON(value)` with no key
   restriction and the reference page's own debug recipe serializes a whole
   context in a `run:` body showing `"token": "***"` — a masked value INSIDE a
   serialized blob [40][41]; the live Forgejo-platform docs at frem.sh state
   `toJSON(secrets)` and computed names `secrets[format('{0}_KEY', 'DEPLOY')]`
   work and reference EVERY secret [54]; the open-platform/mitosis issue #2
   record shows a shipped+validated production Forgejo workflow doing exactly
   the dynamic-name-discovery pattern via `${{ toJSON(secrets) }}` [55].
   Prod-instance behavior = probe leg A (17.3.x + runner 13.2.0 [R3][53]).
3. **Org merge: supported [source].** `secrets` = owner(org)+repo merged, repo
   inserted last ⇒ repo wins; `vars` = global+owner+repo merged with the same
   repo-wins order per the code comment — the v17.0 basic-concepts precedence
   sentence (owner-over-repo) is WRONG vs current source [41][45]; either way
   the 22 org keys appear in the job's contexts. No user-tier third lookup for
   org-owned repos — "repo→org→user" in the workflow header is loose; the
   second tier IS the repo owner (org or user) [43][44].
4. **Mask-survives serialization: yes [docs+source lineage].** The masker
   registers each delivered secret VALUE as its own masked string (multi-line
   values split per-line, longest-first, whole-blob matching) [26][39][56] —
   registration is global to the task's secret map, NOT per-env-key, so 22
   values inside one JSON env var each print as `***`; the docs' own
   `toJSON(forgejo)` sample output proves the shape [40]. Edge to probe (leg B):
   JSON-escaped values — a secret containing `"`/`\` serializes altered and
   would NOT exact-match; none of our JWT/URL/alnum values contain such chars
   [30][31][R3], and a masked echo of the BLOB NAME KEYS is inventory-visible
   (names are not masked) — acceptable, never echo the raw blob by design.
5. **Security widening delta ≈ 0 [source].** Forgejo IGNORES `permissions:`
   and has no environments [42][57]; EVERY job of EVERY workflow in the repo
   already receives ALL repo+owner secrets ([source] — no reference filtering,
   unlike GitHub which lazily unseals only referenced ones and counts
   `toJSON(secrets)` as a whole-context reference [52]). A merged malicious
   `.forgejo/workflows/` change can exfiltrate everything today; the static
   22-row map protects nothing against that attacker. The inline-filter
   mitigation keeps the CHECKOUT-RUN process's env identical in CONTENT to
   today (11 URLs + 11 tokens, via `$RUNNER_TEMP/pairs.json` instead of env)
   while the blob itself lives only in step-1's env — an honest restatement:
   both files are merged-and-reviewed bytes, so the real boundary is PR review;
   the production-validated hardening lever is branch-protecting
   `.forgejo/workflows/**` (mitosis #16 did exactly this after red-teaming a
   `toJSON(secrets)`-exfil workflow) [55].
6. **Recommended shape (pending live probes A–E):** option (1) — job-level
   `toJSON(vars)` + `toJSON(secrets)` into ONE hidden filter step that emits
   the ARGOCD_SYNC_* pairs to `$RUNNER_TEMP/pairs.json`; the fan-out script
   learns a file path (its env then carries FEWER names than today), the 22
   env rows collapse to 2 blob refs + 1 file arg, org keys stay per-key vault
   entries, micro-call (d) lockstep dies (cluster add/remove = org keys only).
   Stay-static remains the zero-risk fallback if any probe fails.

## Agenda 1 — expression engine: toJSON support, runner/act lineage

- **Versions in play [R3][source]:** infra prod runs Forgejo 17.3.x
  (EXPLORE.md:172, `charts/forgejo/Chart.yaml` dep 17.3.1). The server imports
  `code.forgejo.org/forgejo/runner/v13/act/jobparser` — the ACT FORK LIVES
  INSIDE the runner repo (`act/` subtree of forgejo/runner v13) [43][46].
  Deployed runner: `tag: 13.2.0` (`charts/forgejo-runner/values.yaml:255-260`);
  job labels 149-153 map `ubuntu-24.04` →
  `git.spencerslab.com/curatedforest/forgejo-runner:26.11.1`, itself a
  digest-pinned derivative of `ghcr.io/catthehacker/ubuntu:act-24.04` with
  node + python3 + helm/cr baked (`containers/forgejo-runner/Dockerfile:49-52`,
  README 1-26). So: expression engine = forgejo/runner v13's bundled act fork
  (nektos/act lineage), evaluating step-level `${{ }}` RUNNER-side [41].
- **toJSON [docs+source]:** the v17 docs list `toJSON(value)` and
  `fromJSON(value)` among the general expression functions (plus a Forgejo-only
  `case()`), with the `[ ]` INDEX operator and `.` deref both first-class [41].
  Lineage source: `evaluateFuncCall` dispatches `tojson` unconditionally to
  `json.MarshalIndent` over the evaluated argument — no secret filtering, no
  per-key gating (only `success()/failure()/cancelled()` are context-gated)
  [49][50]. `secrets` is an explicit top-level context variable returning
  `env.Secrets` (the whole map) [49]. The docs' availability table lists
  `secrets` accessible in `jobs.<id>.env` AND `steps[*].env`/`run` [40]; the
  table's "Accessible functions: hashFiles" column is underinclusive (the same
  page uses `toJSON(forgejo)` inside a run body) — read it as "extra gated
  functions", not "ONLY these" [40] — **[docs, ambiguity noted → probe A]**.
- **GitHub precedent & divergence [community]:** GitHub's own docs pattern is
  `env: GITHUB_CONTEXT: ${{ toJSON(github) }}` [via 134460 community];
  actions/runner discussion #2445 settled (2023) that GitHub unseals only
  REFERENCED secrets — and that referencing `${{ toJSON(secrets) }}` counts as
  referencing ALL: "then all available secrets are sent to the runner", with
  the published leak step `env: ALL_MY_SECRETS: ${{ toJSON(secrets) }}` +
  `echo "$ALL_MY_SECRETS"`, masked but readable structure [52]. **Divergence:
  Forgejo has NO lazy path — the server ships the full map at task-pick time
  regardless of any reference** [43][46]. Consequences: (a) `toJSON(secrets)`
  on Forgejo cannot "accidentally" return `{}` the way a mis-scoped GitHub
  reference might; (b) dynamic `secrets[computed]` is purely an evaluator
  question, and `evaluateIndexAccess` handles string-indexed map lookups
  (case-insensitive) — lineage-verified [49]; frem.sh documents it working on
  their Forgejo platform [54].
- **v13 runner breaking changes that matter [docs]:** expression evaluation
  FAILURES now fail jobs ("fail jobs, steps if expression interpolation fails"
  [#1646]) — a typo'd function or bad `format()` arg is RED, not a warning
  [53]; `::set-output::`/`::set-env::`/`::add-path::` commands REMOVED →
  `$FORGEJO_OUTPUT`/`$FORGEJO_ENV`/`$FORGEJO_PATH` files [53] (the C10 run
  bodies already use none of the removed commands [R3]); the implicit
  DOCKER_USERNAME/DOCKER_PASSWORD registry-auth was removed — its existence
  until v13 is ANOTHER proof the runner process always held the full secret
  map [53]. `::add-mask::` survives across the family [39].

## Agenda 2 — context completeness: org + repo merge into BOTH contexts

- **secrets [source]:** `FetchActionSecrets(ctx, ownerID, repoID)` finds
  owner-scoped rows (OwnerID set, RepoID 0 — org OR user), then repo-scoped
  rows, and inserts them into one map with `append(ownerSecrets, repoSecrets…)`
  ⇒ repo entries OVERWRITE same-name owner entries [44]. `getSecretsOfJob`
  calls it unconditionally for non-fork, non-workflow-call jobs, then
  `getSecretsOfTask` adds `GITHUB_TOKEN`/`GITEA_TOKEN`/`FORGEJO_TOKEN` =
  task token [43]; `PickTask` puts the map into `runnerv1.Task{Secrets:…}` +
  the `Context` JSON + raw `WorkflowPayload` + `Vars` — everything a job needs
  delivered in one fetch [46]. So the org-level placement ruled in reopen3 IS
  visible in the context (verified: `TestGetSecretsOfJob` fixtures mix a
  owner-scope and a repo-scope secret into one expected map [43]).
- **vars [source]:** `GetVariablesOfRun` merges GLOBAL (OwnerID=0,RepoID=0) +
  owner + repo variables — "Level precedence: Repo > Org / User > Global" per
  the code comment, insertion order matches [45]. **Docs contradiction [41]:**
  v17.0 basic-concepts says owner-precedence-over-repo — stale/wrong vs the
  current source; weigh source. Immaterial to the design either way (runbook
  §2 forbids repo twins), but the workflow header sentence "resolution is
  repo→org→user and a repo key WINS" deserves a wording fix for vars, and
  note: vars additionally merge INSTANCE-GLOBAL rows (secrets cannot exist
  globally — `InsertEncryptedSecret` rejects ownerID=repoID=0) [44][45].
- **The 11+11 keys' visibility is therefore guaranteed by delivery, not by
  reference [source].** No `getSecretsOfJob` reference scan exists in the
  17-line; the only gates are: fork-PR runs (empty map except aliases),
  inner workflow-calls (`secrets: inherit` / evaluated selection map)
  [43][46].

## Agenda 3 — masking of the serialized blob

- Registration model [26] (round-2 deepwiki read of forgejo-runner
  `internal/pkg/report/mask.go` 14–149): EVERY secret VALUE the task carries
  becomes a masking string; multi-line values are newline-split and each line
  registered independently; candidates sorted longest-first; whole-blob
  cross-row lookahead. Seeding is from the TASK's secret set — job-global, NOT
  per-env-key — so the reopen2 [26] per-line finding generalizes: 22 delivered
  values serialize into one env string and still mask individually.
  Corroboration: docs security page ("the runner redacts secrets from the
  logs") [22][40-debug-example]; the reference page's own `toJSON(forgejo)`
  sample prints `"token": "***"` — a masked value inside a serialized JSON
  blob, doc-verified [40]; Gitea-lineage README states masking covers job
  logs, local job logs, summaries and container names [56]; frem.sh: "any log
  output that exactly matches a secret value is replaced" [54].
- **Edges (honest):** (a) exact-match only — transformed copies leak
  [27][28]; in the JSON shape, values containing characters that JSON escapes
  (`"`,`\`, control chars incl. raw newline handling nuances) appear ALTERED
  and would not match ⇒ an unmasked leak channel for future weird secrets;
  our current fleet (JWT tokens [30][31], https URLs, hex-ish tokens) is
  escape-free — probe leg B asserts it on prod. (b) Short/empty values:
  [28] warns short secrets are poorly protected; blanked org secrets deliver
  `""` (no-op candidate, and the empty-detection lanes already treat "" ==
  absent [R3 script]). (c) Masking guards LOGS, not the runner disk:
  `$RUNNER_TEMP/pairs.json` is plaintext inside the job container (and its
  docker volume) until job cleanup — same trust zone as today's step env,
  no new resting place class; chmod 0600 as belt. (d) KEYS inside the blob
  are NOT masked — echoing it reveals the org/repo secret INVENTORY to anyone
  who can read the job log (names like PUSH_TOKEN_GH, FORGE_PUSH_TOKEN,
  FORGEJO_TOKEN…). The design never echoes the blob; the filter step must
  print names only if at all.

## Agenda 4 — security widening analysis (the crux)

- **What IS accessible at job scope TODAY [source+R3]:** every repo-scoped
  secret + every OWNER(org)-scoped secret, merged, into every job, delivered
  by PickTask [43][46]; `permissions:` blocks ignored [42]; no environments
  feature (upstream discussion #440 open; fremforge built its own scoping
  layer precisely because native Forgejo secrets "reach every job of the
  repository") [54][57]. The repo's vault inventory (scope per main-sync
  header + greps [R3]): `PUSH_TOKEN_GH`, `PUSH_TOKEN_DEV`, `FORGE_PUSH_TOKEN`
  (repo-side per the header wording and AGENTS.md; owner/API verify leg),
  org-side: the 11 `ARGOCD_SYNC_*_TOKEN` (+ `ROLE`/`PUSH_URL_*`/
  `ARGOCD_SYNC_*_URL` as vars); `RENOVATE_*` keys are DEV-instance repo
  secrets (renovate.yaml guards `contains(vars.ROLE,'dev')`) — different
  forge, not delivered here [R3].
- **Attack-surface delta of `X: ${{ toJSON(secrets) }}`:**
  (a) *Merged-workflow-attacker* class (PR edits `.forgejo/**`): **unchanged —
  already total.** Today a malicious merged workflow change could add
  `env: T: ${{ secrets.PUSH_TOKEN_GH }}` + exfil; every secret in the repo's
  resolution set is referenceable from any workflow in the repo, and
  `on: push: branches:[main]` fires the attacker's file on the very merge
  push. (b) *Merged-scripts-only attacker* class (PR edits
  `scripts/argocd-fanout.py`): today gains step-env = the 11+11 enumerated
  values; with the recommended shape gains the SAME 11+11 via pairs.json and
  NOTHING more (step-2's env declares only `ARGOCD_PAIRS_FILE` + refs;
  step-1's blob env is a different process). With the naive shape (blob
  straight into the script's env) it would gain all secrets incl.
  PUSH_TOKEN_GH/DEV + the run-scoped write token aliases — which is exactly
  why the filter step exists. The mitigation therefore has a real, if narrow,
  invariant: **the checked-out code's runtime env stays at the 22-value floor
  while enumeration dies.**
  (c) *Honesty caveat the brief asked for:* both `main-sync.yaml` and
  `scripts/argocd-fanout.py` are merged-and-reviewed repo files — same review
  gate, so the filter is NOT a privilege boundary against repo write-access;
  the actual lever is making the workflow gate stricter than the script gate:
  branch protection / CODEOWNERS on `.forgejo/workflows/**` — the mitosis #16
  red-team-validated pattern [55]. Optional owner decision leg (no gate on
  this ticket).
- **Inline-filter feasibility in the act lineage [source+docs]:** step-level
  `env:` interpolation is runner-side over the delivered map [41][49]; the
  env VALUE (not the run body) carries the blob, so the token values never
  land in the step script file the runner writes (the C10 job-comment doctrine
  holds: values in env, `$VAR` refs in body [27][29][38]); `RUNNER_TEMP` is a
  documented runner context var with `runner.temp` ↔ `RUNNER_TEMP` [40] and
  `/tmp` in the lineage `startJobContainer` envList [51]; steps run as
  `docker exec` in ONE persistent job container per job (reference page: the
  job container lives for the whole job; "files written outside the workspace
  …" caveat applies to ACTION steps' own containers, not to run steps)
  [40][51] ⇒ a file written by step 1 in `$RUNNER_TEMP` is readable by step 2
  — probe legs C+D confirm both (index op + temp-file persistence) on prod.
- **Token-in-payload note (unchanged from round 2 §3):** FetchTask delivering
  all secrets to the runner process is the same legacy shape the [23-discussion]
  note described; reopen4 CONFIRMS it as current and org-merged [43][46].

## Agenda 5 — mechanisms if toJSON(secrets) disappoints (and full scoring)

| # | Mechanism | Dynamic? | Per-key vault? | Error-proneness | Verdict |
|---|---|---|---|---|---|
| 1 | **toJSON blobs + inline filter step → pairs.json** | YES (both kinds) | YES | LOW: 2 env lines replace 22; fleet ops never touch the YAML again | **RECOMMENDED** (probe-gated) [40][41][43][44][46][49][52][54][55] |
| 2 | toJSON(vars)+API → detect job → `$FORGEJO_OUTPUT` name list → `strategy.matrix` from `fromJSON(needs…)` → per-cell `env: TOKEN: ${{ secrets[format('ARGOCD_SYNC_{0}_TOKEN', matrix.CAT)] }}` | YES | YES | MED-HIGH: two-step chain, matrix job-name uniqueness note, outputs-carrying-secrets hazard [56], restructures the fan-out (one process per cluster — loses the single settle/summary/parallel contract [R3]) | ENGINE-feasible (matrix-from-outputs doc-verified [40]; index-op lineage+frem.sh [49][54]), but redesign-tax with zero gain over (1) |
| 3 | REST API discovery: `GET /orgs/{org}/actions/secrets` (names) + `/actions/variables` (names+VALUES) | vars: yes; secrets: **names only** | YES | LOW ops-wise, but runtime-impossible for TOKENS (values never leave the vault — swagger handler source) [43][44][47][48] and the AUTO token can only touch its own repo (org endpoints 404) [41] ⇒ needs an owner/org PAT in the vault = a new crown-jewel key | RUNBOOK/audit helper only, not the fan-out channel |
| 4 | One JSON-blob secret (reopen2) | N/A (paste-time static) | NO (single key) | HIGH — owner ruled it out 2026-11-25 ("too error-prone"); mechanics were never the blocker [26] | DEAD by ruling, not by engine |
| 5 | Stay static (22 rows) | NO | YES | LOW runtime, MED ops (lockstep edits per fleet change — the exact cost the owner rejects) | FALLBACK if any probe fails; costs unchanged from R7 |

Scoring against the owner's ask (dynamic + per-key vault entries +
error-proneness minimized): (1) satisfies all three with the smallest diff;
(2) satisfies all three but re-pays the fan-out topology; (3) can only be
half-dynamic; (5) fails the ask.

## Agenda 6 — live verification (dispatch/smoke legs — become the runbook §5.5)

The suite cannot reach git.spencerslab.com; these legs prove the design BEFORE
any re-cut commit lands. Run as `.forgejo/workflows/cf139-probe.yaml`,
`on: workflow_dispatch`, `if: contains(vars.ROLE,'prod')`, `runs-on:
ubuntu-24.04`, dispatched on a NON-main branch (a probe must never merge to
main; `workflow_dispatch` selects the branch [40][41]). Delete the file after.
- **A — toJSON support + completeness + masking:** step `env: S: ${{
  toJSON(secrets) }}` / `V: ${{ toJSON(vars) }}`; run: python3 one-liner that
  prints `sorted(json.loads(os.environ["S"]))` KEYS only + count; asserts the
  22 ARGOCD_SYNC_* names + `FORGEJO_TOKEN` present in S, the 11 URL names +
  ROLE in V; then `printf '%s' "$S" | grep -c '\*\*\*'` (>0 ⇒ blob-internal
  masking live) and a single `echo "$EXPECTED_ONE_TOKEN_VAR"` round-trip
  showing `***` in the fetched log. Failure modes are distinct: function
  absent ⇒ job RED (v13 doctrine [53]); key missing ⇒ delivery/merge gap;
  unmasked echo ⇒ masker-seeding surprise — all abort option (1).
- **B — escape-hazard spot-check:** `python3 -c` over the parsed blob asserting
  every ARGOCD_SYNC_* value matches `^[A-Za-z0-9._~+/-:=]+$` (no JSON-escape or
  whitespace chars) — keeps agenda-3(a) edge closed on real values.
- **C — index-operator probe (only needed if option 2 were ever wanted):**
  job-level `strategy.matrix: cat: [dev]` + step `env: X: ${{
  secrets[format('ARGOCD_SYNC_{0}_TOKEN', matrix.cat_upper)] }}` (name
  construction per R7 upper-snake) + length-only assert. Green would also
  RETIRE the reopen3 [21][25] wording at its root; red confines it to docs.
- **D — RUNNER_TEMP persistence:** step1 `echo test > "$RUNNER_TEMP/x"`;
  step2 `test -f "$RUNNER_TEMP/x" && rm -f "$RUNNER_TEMP/x"` — pre-validates
  the pairs.json channel [40][51].
- **E — log-fetch assertion:** after the dispatch, `curl` (or UI) the job log
  and grep for `BEGIN/END` markers around each step to confirm no secret value
  appears raw anywhere (the masking spot-check §5 already does this shape
  natively [R3 plan]).
- **Owner API shells (not dispatch):** `curl -H "Authorization: token $PAT"
  https://git.spencerslab.com/api/v1/orgs/CuratedForest/actions/secrets` ⇒
  names of ALL org keys (complete the agenda-4 inventory — verifies no
  unexpected crown jewels ride every job); `.../repos/OwnYourIO/SpencersLab/
  actions/secrets` ⇒ the repo-side set incl. PUSH_TOKEN_* scope confirmation
  [47][48]; `.../actions/variables` ⇒ VALUES readable (URL roster audit) [47].
- **Rollback posture:** probes are additive and dispatch-only; any red ⇒ the
  ticket stays on the static enumeration exactly as shipped at d81831446 —
  nothing already merged changes.

## Contradictions (this round) & how to weigh

- **reopen3 [21][25] "cannot index secrets dynamically" vs [43][44][46] source
  + [54][55] live community usage.** The docs pages the earlier round leaned on
  never state a dynamic-index prohibition — the claim was a best-guess
  generalization from GitHub's reference-scanning behavior. Weigh: SOURCE WINS —
  delivery is unconditional and the evaluator is generic; the residual unknown
  is only the exact fork build on prod (probe A/C).
- **basic-concepts vars-precedence sentence vs `GetVariablesOfRun` source**
  (owner-wins vs repo-wins): weigh code; both are moot under the no-repo-twin
  rule; record for the runbook wording pass.
- **reference availability-table "Accessible functions" vs the same page's
  `toJSON(forgejo)` example**: the table is underinclusive prose, the engine
  source has no such gate [49]; weigh example+source; probe A still asserts it
  on the exact prod build.
- **GitHub ≠ Forgejo on the WHY of "all secrets visible":** GitHub's
  toJSON(secrets) WORKS by escalating what's fetched (lazy unseal triggered by
  the whole-context reference [52]); Forgejo always has the full map anyway —
  same visible outcome, different delivery models. Matters for any future
  "port to GitHub CI" thought experiment (would silently NOT work for
  dynamically-indexed names).

## Implications for the plan (if probes green — re-cut shape, NOT executed here)

- C-new (workflow): sync-fanout becomes 3 steps — checkout; **filter step**
  (`name: resolve fan-out pairs`; `env: ARGOCD_SECRETS: ${{ toJSON(secrets) }}`
  + `ARGOCD_VARS: ${{ toJSON(vars) }}` + the same EVT_REF/GH_REF pair; inline
  `python3 -c` or short heredoc FILTER: keep `^ARGOCD_SYNC_(.+)_URL$` from V +
  `^ARGOCD_SYNC_(.+)_TOKEN$` from S, write name-keyed JSON `{cat: {url,token}}`
  to `$RUNNER_TEMP/argocd-pairs.json`, chmod 600; prints only `pairs: N`);
  **fan-out step** (`env: ARGOCD_PAIRS_FILE: $RUNNER_TEMP/argocd-pairs.json` +
  refs; unguarded python3 call unchanged). 22 static rows DELETE; the header's
  "static enumeration IS the discovery surface" + "Forgejo cannot index
  secrets dynamically" sentences RETIRE with them.
- C-new (script input): `discover_targets` gains ONE channel — read
  `ARGOCD_PAIRS_FILE` (absent ⇒ env scan exactly as today, preserving local
  `--check` + the behavior suite's env shape); the pair-shape/malformed/(j)
  logic ports to JSON values verbatim (empty-string semantics identical: the
  blob carries "" for blanked keys). Fan-out core stays byte-locked (t13
  doctrine). The "enumerated" vocabulary in micro-calls (c)/(d) re-reads as
  "discovered" — typo'd ORG keys now surface WITHOUT any workflow row
  (broad-catch already handles it: a value-carrying malformed key ⇒ RED naming
  the raw key [R3 script] — and with dynamic discovery an EXTRA org key pair
  auto-joins the fleet, which is the whole point; the runbook must say
  "creating the org pair IS the enablement; the workflow is fleet-blind").
- Suite re-pin: forgejo-main-sync t5/t11/t12 shift from 22-name pins to the
  2-blob-name + filter-contract pins (the filter IS the enumeration — its
  regexes deserve their own static legs); behavior t4/t5 arms (j)-family
  mostly port through the file channel; runbook suite re-pins §2/§5/§7/§8 +
  §5 probe legs A–E.
- Ops consequences (all IMPROVEMENTS the owner asked for): add cluster =
  1 var + 1 secret, zero PR; decommission = delete pair, zero PR — micro-call
  (d) lockstep and the "both drift directions visible" wording DIE; §7 kill
  lever unchanged (token-side predicate survives); rotation §8 unchanged.
  New doc duties: (i) org-key NAMES become runtime-meaningful code (a stray
  `ARGOCD_SYNC_FOO_TOKEN=x` with no URL now surfaces — the malformed/pair-RED
  lanes catch it; a complete stray pair would JOIN the fleet — the org write
  surface is now the fleet config surface; org Actions write perms =
  fleet-deploy perms, worth a runbook sentence); (ii) the mask edge list
  (agenda-3) lands in §5.

## Open questions (this round — accumulated, no questions asked)

1. **Probe outcomes A–D** (the only real gate on adopting option 1): best
   guess all green given [43][44][46][49][54][55]; the fork-build caveat is
   why they exist.
2. Does the owner want `.forgejo/workflows/**` branch-protected (mitosis #16
   lever) as part of this ticket or its own card? Best guess: separate card —
   it is an org-settings leg, out of the ticket's blast radius.
3. What ELSE lives at org scope on CuratedForest (agenda-4 inventory leg) —
   affects only documentation honesty about "the blob carries everything",
   never the design. Best guess: PUSH/ROLE-family keys are repo-side (header
   says so), org holds the ARGOCD_SYNC_* pair set alone.
4. Filter step wording/language: `python3 -c` one-liner vs the already-shipped
   `scripts/` — it must be INLINE (not checkout-runnable) to keep the
   "runtime env floor" invariant; a 10-liner is acceptable; `bash -n` leg
   extends to it [R3 t13]. Best guess: inline python3 (json module stdlib ✓).
5. Keep the malformed-name RED lane identical when the name source shifts
   from "22 known rows" to "whatever the org has" (a typo in an ORG KEY name
   now matters more — the lane covers it; plan round to confirm the (i-adj-1)
   envelope wording rather than the envelope itself).

## Sources (round 3, numbered continuing)

40. https://forgejo.org/docs/latest/user/actions/reference/ — v17.0.2: contexts table (`secrets`/`vars` at steps env/run), availability matrix, `toJSON(forgejo)` debug example with masked `"token": "***"`, runner context `RUNNER_TEMP`, `jobs.<id>.outputs` + `$FORGEJO_OUTPUT`, matrix-from-`fromJSON(needs…)`-outputs generator example, `jobs.<id>.secrets`/workflow_call, dispatch inputs, `permissions` absent. Read 2026-11-26.
41. https://forgejo.org/docs/latest/user/actions/basic-concepts/ — v17.0.2: Functions list incl. toJSON/fromJSON/case; operators incl. `[ ]` Index; secrets org/user/repo scopes + write-only-after-add; variables name constraints (`FORGEJO_`/`GITHUB_` prefix bans) + the (stale) owner-precedence sentence; automatic token scope ("only its repository, other repos 404"). Read 2026-11-26.
42. https://forgejo.org/docs/latest/user/actions/github-actions/ — differences: job subkeys like `permissions` IGNORED; familiarity-not-compatibility. Read 2026-11-26.
43. https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/services/actions/secret.go — getSecretsOfTask/getSecretsOfJob: token aliases added; CanAccessSecrets gate; `FetchActionSecrets(OwnerID, RepoID)` NO reference filtering; workflow-call `inherit`/`EvaluateWorkflowCallSecrets` paths; imports `runner/v13/act/jobparser`. Read 2026-11-26.
44. https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/models/secret/secret.go — Secret model (owner XOR repo scope, global secrets rejected), FetchActionSecrets merge order (owner first, repo overwrites), ToUpper names, encrypted-at-rest decryption at fetch. Read 2026-11-26.
45. https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/models/actions/variable.go — ActionVariable incl. instance-global tier; GetVariablesOfRun "Repo > Org / User > Global". Read 2026-11-26.
46. https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/services/actions/task.go — PickTask/RecoverTasks: `runnerv1.Task{WorkflowPayload, Context, Secrets, Vars, Needs}` — full maps per task. Read 2026-11-26.
47. https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/routers/api/v1/org/action.go — swagger handlers: GET /orgs/{org}/actions/secrets ⇒ Name+Created ONLY; GET /orgs/{org}/actions/variables ⇒ Name+Data (values); full var CRUD via API. Read 2026-11-26.
48. https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/modules/structs/secret.go + .../variable.go — `Secret{ Name, Created }` / `ActionVariable{ OwnerID, RepoID, Name, Data }`. Read 2026-11-26.
49. https://gitea.com/gitea/act/raw/branch/main/pkg/exprparser/interpreter.go — lineage fork: evaluateVariable "secrets"→env.Secrets (whole map), "vars"→env.Vars; evaluateIndexAccess string-index ⇒ `secrets[name]` works; evaluateFuncCall `tojson` ungated; coerceToString(map)="Object". Read 2026-11-26.
50. https://raw.githubusercontent.com/nektos/act/main/pkg/exprparser/functions.go — toJSON = json.MarshalIndent(value) unconditionally. Read 2026-11-26.
51. https://gitea.com/gitea/act/raw/branch/main/pkg/runner/run_context.go — lineage fork: RUNNER_TEMP=/tmp in job-container envList; one persistent container per job (steps = docker exec); rc.Config.Secrets drives credential lookups (full-map visibility). Read 2026-11-26.
52. https://github.com/actions/runner/discussions/2445 — GitHub option-1 lazy unsealing proven by diagnostic logs; `${{ toJSON(secrets) }}` counts as referencing ALL secrets ("then all available secrets are sent to the runner"; "The actions/runner will mask the json encoded secrets just fine"); published leak step shape. Read 2026-11-26.
53. https://forgejo.org/2026-08-runner-release-v13/ — Runner v13.0.0 breaking changes: expression failures fail jobs; set-output/set-env/add-path removed (→ $FORGEJO_* files); DOCKER_USERNAME/PASSWORD implicit-auth removed; gitea context removed. Read 2026-11-26.
54. https://docs.frem.sh/build/secrets/ — fremforge (Forgejo-based platform) docs: `${{ toJSON(secrets) }}` and computed names `${{ secrets[format('{0}_KEY', 'DEPLOY')] }}` reference EVERY secret; native Forgejo repo/org secrets "reach every job of the repository" (their scoped-secrets layer exists precisely because of it); masking = exact-value replacement. Read 2026-11-26.
55. https://git.open-platform.sh/open-platform/mitosis/issues/2 — shipped, end-to-end-validated production design: natural-named Forgejo Actions secrets read via `${{ toJSON(secrets) }}` by a sync-env workflow; #16 credential boundary: `.forgejo/workflows/**` branch-protected to stop `toJSON(secrets)`-exfil workflows, red-team validated. Read 2026-11-26.
56. https://gitea.com/gitea/runner (README @ main, v6 line) — lineage sibling: "Secrets and ::add-mask:: values are hidden in job logs, local job logs, job summaries and container names. As on GitHub, a job output containing one is dropped with a warning." Read 2026-11-26.
57. https://codeberg.org/forgejo/discussions/issues/440 — no GitHub-style environments in Forgejo (feature ask open); org secrets injection into every repo job confirmed in discussion. Read via search body 2026-11-26.

Plus repo/live evidence **[R3]**: `charts/forgejo-runner/values.yaml:148-153,255-266`
(runner tag 13.2.0; act-24.04-family labels → curatedforest/forgejo-runner:26.11.1),
`containers/forgejo-runner/{Dockerfile:49-52,README.md}` (digest-pinned
catthehacker act-24.04 base; node/python3 inventory; manual-bump law),
`.forgejo/workflows/*.yaml` secrets/vars grep (PUSH_TOKEN_GH/DEV +
FORGE_PUSH_TOKEN repo-side; RENOVATE_* dev-instance-side),
EXPLORE.md:172 (infra = Forgejo 17.3.x, charts/forgejo dep 17.3.1),
`scripts/argocd-fanout.py` (discover_targets/kill-lane/JWT_RE),
`tests/services/forgejo-main-sync.sh` t5/t11/t12/t13 pins, STATE/DECISIONS/plan
INPUT contract reads.

Method note: single-session targeted research (coordinator-pinned 6-agenda
brief; no persona fan-out — the questions, not perspectives, were fixed
upstream). code.forgejo.org is Anubis-gated and deepwiki 429-limited — the
forgejo/runner fork internals rest on the act-lineage sources [49][50][51],
round-2 [26], and the community usage [54][55]; probe legs A–D close exactly
that gap. Prior-round citations [21]-[39] unchanged.
