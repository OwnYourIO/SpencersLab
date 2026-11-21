# EXPLORE — cf-139 feat: Sync ArgoCD with Webhooks

Card AD-139 (Y3vPeX4nhtDbsdwCg): "After pushing to main, I have to manually go into each cluster and run argocd sync. This should happen automatically when pushed to main."

Scouted 2026-11-12 on branch `cf-139-feat-argocd-webhook-sync` (branched from main @ 0d9b41785). Read-only repo probes + live read-only MCP probes of the clusters. No fixes proposed here.

## 1. Where ArgoCD is deployed / values'd

- **ArgoCD ships inside the `base` chart as a Helm subchart dependency**: `charts/base/Chart.yaml:5-8` — `argo-cd` chart **10.11.6** from `https://argoproj.github.io/argo-helm` (pinned in `charts/base/Chart.lock`; renovate classifies `argo-cd` as "Non-critical services" in `renovate.json:242`).
- The base chart is deployed **on every cluster**: each category's ApplicationSet renders a second source `chart: base` (see §2), so **every cluster runs its own ArgoCD** — matching "go into each cluster".
- Central ArgoCD values: `charts/base/values.yaml:79-173` (`argo-cd:` block):
  - `server`: `authMode: sso` (Keycloak OIDC via `$argocd-sso:*` secret refs, lines 101-113), `extraArgs: --insecure, --application-namespaces="*"` (88-90).
  - `configs.cm`: ignoreDifferences customizations, and **local account `accounts.mcp-bot: apiKey`** (line 147) with `configs.rbac.policy.csv` granting `mcp-bot` `applications get+sync` only (149-161).
  - **`notifications: enabled: false`** (lines 166-167) — argocd-notifications is OFF everywhere.
  - `applicationSet.enabled: true` (168-169).
- **No webhook config anywhere in the repo**: zero hits for `serverWebhookPath`, `configs.params`, repo-creds, or any incoming-webhook wiring in `charts/`, `services/`, `custom-values/`, `.github/workflows/` (grep run 2026-11-12). CI workflows (`release.yaml`, `docker-build.yaml`, `aislop.yaml`, `rulesync.yaml`, render-tests) never notify ArgoCD.
- The ArgoCD UI URL is injected per cluster as helm param `argo-cd.configs.cm.url=https://cluster.<clusterName>.<domain>` in every `services/<cat>/prod/templates/appset.yaml` (~line 113; live-verified on infra, see §3).
- Per-service values (`services/<cat>/prod/values.yaml`) contain **no `argo-cd:` override** (grep `^argo-cd` → no hits); ArgoCD config is repo-centrally in the base chart.

## 2. ApplicationSets / Applications under services/

- Two ApplicationSet kinds, both using a `matrix: clusters: {} × list` generator (goTemplate):
  1. **Service appset** `services/<cat>/prod/templates/appset.yaml` (11 categories have one: dev, gpu, gpu-ai, grow, home, infra, media, monitoring, proxy-backup, proxy-local, proxy-remote; `services/backups` and `services/personal` are values-only, no templates) → generates the **root Application named `<cat>`** which renders `services/<cat>/prod` (templates incl. the appset itself) + the `base` chart. Sources: repo `services.repo` twice + `values.repo` + `chart.repo` chart `base`, `targetRevision: main` (or stage); custom values ride URL valueFiles from `https://raw.githubusercontent.com/OwnYourIO/SpencersLab/refs/heads/main/custom-values/<cat>/prod-values.yaml` (example annotation at `services/infra/prod/templates/appset.yaml:61`).
  2. **Charts appset** `charts/base/templates/appset-charts.yaml` (rendered by the base chart itself) → one Application per entry of `.Values.charts` named `<cat>-<app>` (e.g. `infra-389ds`).
- **syncPolicy is annotation-gated, default ON** in both appsets:
  - service appset: `services/infra/prod/templates/appset.yaml:125-134` — `automated: {prune: true, selfHeal: true}` only when cluster annotation `services.<cat>.selfHeal` != `"false"`.
  - charts appset: `charts/base/templates/appset-charts.yaml:124-143` — same gate, service-wide `services.<svc>.selfHeal` plus per-app `services.<svc>.<app>.selfHeal` override; syncOptions `CreateNamespace=true, ServerSideApply=…, RespectIgnoreDifferences=true`.
- **Live state contradicts the repo default at the root-app level** (readonly MCP `resources_get` on Application, 2026-11-12):

  | cluster (server) | root app | spec.syncPolicy | sync status |
  |---|---|---|---|
  | infra | `infra` | syncOptions only (`CreateNamespace=true`,`ServerSideApply=true`) — **no automated** | **OutOfSync** |
  | dev | `dev` | same | **OutOfSync** |
  | gpu | `gpu` | same | **OutOfSync** |
  | home | `home` (dest name `home-lab`) | same | **OutOfSync** |
  | grow | `grow` | same | Synced |
  | monitoring | `monitoring` | same | Synced |
  | proxy-local | `proxy-local` (dest name `cloud-proxy`) | same | Synced |

  The live `infra-appset` **does** carry the selfHeal gate in its `templatePatch` (verified), so the rendered "no automated" ⇒ **each cluster's own cluster-secret is annotated `services.<cat>.selfHeal: "false"`** (couldn't read the secrets themselves — readonly SA RBAC forbids `argocd` ns Secrets). That is the grounded root cause: root apps never auto-sync → after a push to main the user syncs them by hand; child `<cat>-<app>` apps (from the charts appset) DO have automated (all `infra-*` apps Synced except `infra-seaweedfs` OutOfSync).
- Cluster-annotation flips are an established **human action** pattern in this fleet — precedent: cf-11 plan/chunks describing user edits to the ArgoCD cluster secret annotations (`.agents/plans/2026/2026-10-cf-11-feat-immich-hugo-pipeline/chunks/C04.md:185`).
- Appset variant drift (context, not a problem): dev/gpu/gpu-ai appsets are a newer copy with extra bump-comment blocks and older pinned `baseChartVersion` (gpu 1.0.198, `services/gpu/prod/templates/appset.yaml:35`) vs infra 1.0.202 (`services/infra/prod/templates/appset.yaml:22`).

## 3. Repo → cluster topology

- Git origin consumed by ArgoCD: `https://github.com/OwnYourIO/SpencersLab.git`, `targetRevision: main` — read live from the `infra` Application's sources; cluster annotation values (`services.repo`/`values.repo`/`chart.repo`/`domain=spencerslab.com`/`clusterName`) live **only on the ArgoCD cluster secrets**, never in this repo.
- **Every cluster manages only itself**: root app destination `name` = its own registered cluster (`infra→infra`, `home→home-lab`, `proxy-local→cloud-proxy` — display names differ from service names!). There is no hub app-of-apps in the repo; `kind: Application` exists only in `charts/base/templates/k3s-system-upgrade-controller.yaml`.
- **Bootstrap is out-of-band**: nothing in the repo applies the service appsets themselves (chicken-and-egg: the appset ships inside the root app it bootstraps); first apply is manual, per-cluster — no docs found (README is chart-releaser boilerplate; `.agents/notes/` has no sync-automation note).
- Cluster set in play: dev, gpu, gpu-ai, grow, home, infra, media, monitoring, proxy-local, proxy-remote, proxy-backup (`services/*` + `custom-values/*`; extra custom-values dirs `base`, `cherry`). MCP catalog exposes readonly kubernetes for gpu, ai-gpu, dev, grow, home, infra, media, monitoring, proxy-local — **no proxy-remote/proxy-backup server** in the session catalog.
- ArgoCD SSO secret per cluster: ExternalSecret template `charts/base/templates/secret-argocd-sso.yaml` (Keycloak client-id/secret/issuer from Bitwarden item `bitwardenIds.argocd-sso-secret`, UUID `6bc8ead2-…` in every `custom-values/<cat>/prod-values.yaml`; dev cluster uses its own item `d07b1bec-…`, `custom-values/dev/prod-values.yaml:21`).

## 4. Webhook-relevant surface that already exists

- **Public route to each ArgoCD API server exists**: `cluster` subdomain per cluster (`services/<cat>/prod/values.yaml` `ingress.subdomains.cluster: {clusterBase: true, service: argocd-server, port: 80}` — verified in all of dev:167, gpu-ai:75, gpu:255, grow:85, home:257, infra:102, media:186, monitoring:60, proxy-backup:71, proxy-local:321, proxy-remote:100) rendered by `services/<cat>/prod/templates/generic-ingress.yaml` → host `cluster.<clusterName>.spencerslab.com`, TLS secret `cluster-wildcard-cert` = `*.<clusterName>.spencerslab.com` Let's Encrypt cert (`charts/base/templates/cert-manager-wildcard-cert.yaml`, DNS-08 via Cloudflare solver token). No middlewares by default on workload clusters (`proxy.middlewares.entrypoint: ""`, `charts/base/values.yaml:28-30`); proxy-remote's own edge adds geoblock + https-redirect (`services/proxy-remote/prod/values.yaml:22-23`). Whether `cluster.*` DNS is published publicly (vs reachable only via the proxy-remote SSH tunnel, `services/proxy-remote/prod/values.yaml` `sshd` :2222) is **not resolvable from the repo** — open question.
- **API-token + sync-RBAC precedent exists**: `mcp-bot` local account (`charts/base/values.yaml:144-161`, apiKey-only, `applications sync` allowed, tokens minted per-cluster out-of-band into Bitwarden) and the media cluster's token plumbing — ExternalSecret `services/media/prod/templates/secret-argocd-mcp.yaml` (Bitwarden LOGIN `argocd-mcp-media`, key `token`) + `bitwardenIds.argocd-mcp: 5783b79e-…` in `custom-values/media/prod-values.yaml` (+ `sa-argocd-mcp-client.yaml` OIDC-SA variant). A GitHub secret token would follow the same ExternalSecret+Bitwarden trio.
- **GitHub PAT-for-repo-access precedent**: `github-mcp` secret consumed with `x-access-token:…@github.com/OwnYourIO/SpencersLab.git` clone (`services/dev/prod/values.yaml:330-350`, `services/gpu/prod/values.yaml:946` area; secret templates `services/{dev,gpu}/prod/templates/secret-github*.yaml`).
- `ARGOCD_EXEC_TIMEOUT=5m` env on repoServer only (`charts/base/values.yaml:91-95`); no repo polling-interval override anywhere → ArgoCD defaults apply (live config is research/planner territory).
- `services/personal`, `services/backups`: values-only, no ingress/appset — not webhook targets as far as the repo shows.

## 5. Live inspection surface for the planner

- **Which cluster hosts ArgoCD: all of them** — probe any affected cluster with its `readonly-<cluster>-kubernetes` server (infra/media/monitoring are NOT "the" ArgoCD host; there is no central instance).
- Probes verified today (Code Mode): `tools["readonly-<cluster>-kubernetes"].resources_list/resources_get` with `apiVersion: argoproj.io/v1alpha1, kind: Application|ApplicationSet, namespace: default` → full spec JSON (syncPolicy, sources, annotations). `resources_list` returns condensed table rows (Name/Namespace/Sync Status), `resources_get` returns full object.
- **Gotchas found**:
  - `readonly-*` SA (`kubernetes-mcp-readonly`, hivetools-managed) is **forbidden from listing Secrets in the `argocd` namespace** → cluster-secret annotations (`services.<cat>.selfHeal`) can't be read with readonly MCP; need `admin-*` (planner must ask the user per AGENTS.md) or ask the user.
  - `readonly-media-kubernetes` was **ECONNREFUSED** during this scout (media cluster's MCP endpoint down/unreachable) — retry later or route around.
  - ArgoCD resources live in namespaces `default` (apps/appsets) and `argocd` (workloads); `--application-namespaces="*"` is set.
  - `scripts/` contains only board/pipeline machinery (`agent-board-coord-gate.sh`, `provision-board.py`, kickoff scripts) — nothing sync-related. No `.agents/notes/` doc about sync automation.
- No unit-test suite; validation = `helm lint`/`helm template charts/base` + the grep trio per AGENTS.md (chart entry + ApplicationSet entry + proxy values entry). `helm` needs `export PATH=$HOME/.local/bin:$PATH`.

## Open questions (for research/plan; scout does not answer)

1. **Is `cluster.<name>.spencerslab.com` publicly resolvable/reachable** (GitHub webhooks originate on the internet), or does traffic only arrive via the proxy-remote zero-trust edge/tunnel? Needs live DNS/route check or the user.
2. **Who/what set `services.<cat>.selfHeal="false"` on each cluster secret, and why** — flipping it back on is the minimal fix, but the deliberate-looking flip (all clusters, roots only) suggests history the user should confirm (readonly RBAC can't read the annotations; needs admin-tier or user).
3. Does the user's ask mean "webhook-triggered sync" specifically, or "any push to main lands automatically" — webhooks refresh, they don't sync by themselves; automated syncPolicy (or a sync-job/CI step, or argocd-image-updater-style CI hook) is needed on top. Design decision → research/plan.
4. Where should the GitHub webhook(s) be created (per-repo settings → one hook per cluster URL, or one edge → fan-out), and with what secret storage (Bitwarden + ExternalSecret pattern per §4)? Repo-side half only; the GitHub side is a user action.
5. `infra-seaweedfs` is OutOfSync while `ServerSideApply: "false"` — unrelated drift, but worth a glance during planning so a fleet-wide sync doesn't surprise.
6. ArgoCD *application* version behind helm chart 10.11.6 (affects webhook API details, e.g. `serverWebhookPath` defaults) — planner should read live (`argocd-cm` or server image tag) rather than assume.

---

# Forgejo rework probe (2026-11-21)

Trigger: owner ruling at Final Review (STATE.json `reopen.reason`): "webhook source must be
Forgejo (forge migrated to git.spencerslab.com), not GitHub". Read-only probes: live
`resources_get`/`resources_list` on `argoproj.io/v1alpha1 Application` via the nine
`readonly-<cluster>-kubernetes` MCP servers (all apps live in ns `default` — re-verified
2026-11-21 on all nine clusters; the launch hint "ns argocd" is wrong for Applications),
repo greps, git log/remote reads, and the Forgejo v17.0 webhooks docs (forgejo.org, fetched
2026-11-21).

## 1. Ground truth: repoURL per cluster TODAY — the fleet STILL tracks GitHub, 9/9

| cluster (MCP server) | root app | git source repoURLs (`services`/`values`/service-path) | targetRevision | chart source (base) | one child app corroborated | root sync (this probe) |
|---|---|---|---|---|---|---|
| dev (`readonly-dev-kubernetes`) | `dev` | `https://github.com/OwnYourIO/SpencersLab.git` ×3 | `main` ×3 | `https://ownyourio.github.io/SpencersLab/` @1.0.201 | `dev-cloudnative-pg`: github `main` + chart `cloudnative-pg.github.io` | OutOfSync |
| gpu (`readonly-gpu-kubernetes`) | `gpu` | github ×3 | `main` | gh-pages index @1.0.198 | `gpu-amd-gpu`: github `main` + chart `rocm.github.io` | Synced |
| gpu-ai (`readonly-ai-gpu-kubernetes`) | `gpu-ai` | github ×3 | `main` | gh-pages index @1.0.198 | `gpu-ai-amd-gpu`: github `main`, path `charts/amd-gpu` | Synced |
| grow (`readonly-grow-kubernetes`) | `grow` | github ×3 | `main` | gh-pages index @1.0.202 | `grow-assistant`: github `main`, path `charts/home-assistant` | Synced |
| home (`readonly-home-kubernetes`) | `home` | github ×3 | `main` | gh-pages index @1.0.202 | `home-bri-budget`: github `main`, path `charts/actualbudget` | **Unknown** |
| infra (`readonly-infra-kubernetes`) | `infra` | github ×3 | `main` | gh-pages index @1.0.202 | **`infra-forgejo`: github `main`, path `charts/forgejo`** (the app that *deploys the Forgejo instance itself* sources from GitHub) | OutOfSync |
| media (`readonly-media-kubernetes`) | `media` | github ×3 | `main` | gh-pages index @1.0.202 | `media-audiobookrequest`: github `main`, path `charts/audiobookrequest` | OutOfSync |
| monitoring (`readonly-monitoring-kubernetes`) | `monitoring` | github ×3 | `main` | gh-pages index @1.0.202 | `monitoring-exporter-mikrotik`: github `main` + chart gh-pages index | Synced |
| proxy-local (`readonly-proxy-local-kubernetes`) | `proxy-local` | github ×3 | `main` | gh-pages index @1.0.202 | `proxy-local-external-secrets-bitwarden`: github `main`, path `charts/external-secrets-bitwarden` | Synced |
| proxy-remote | — | **MANUAL ROW** — no readonly MCP server in the catalog (unchanged from §5) | — | — | — | — |
| proxy-backup | — | **MANUAL ROW** — no readonly MCP server | — | — | — | — |

**Answer 1: no cluster has moved to the Forgejo origin.** Every reachable root app AND every
sampled child carries the byte-exact string `https://github.com/OwnYourIO/SpencersLab.git`
(incl. `.git`) at `main`. The two manual rows are structurally identical templates (§2) and
presumed GitHub too — unverified. Side observations: `home` root now reports sync `Unknown`
(was Synced 2026-11-12); `media` MCP answered this probe (the 2026-11-12 ECONNREFUSED is
gone — FRICTION note closed in practice).

## 2. Where repoURL comes from in the repo — it never appears as a literal

- Both appsets render every git `repoURL` from the ArgoCD **cluster-secret annotations**:
  `services.repo` / `values.repo` / `chart.repo` (service appsets, e.g.
  `services/infra/prod/templates/appset.yaml:78,81,84,102`; `charts/base/templates/appset-charts.yaml:54,64`).
  Same for the custom-values URL valueFiles — `services.gpu.customValuesUrls` annotation,
  the template only carries it as a COMMENT example (appset.yaml:61).
- Live confirmation (infra root spec, read 2026-11-21): the rendered `valueFiles` still
  contain `https://raw.githubusercontent.com/OwnYourIO/SpencersLab/refs/heads/main/custom-values/infra/prod-values.yaml`
  — i.e. **a third GitHub-bound URL surface lives in the cluster secrets, not in git**.
- Repo-side evidence of the forge migration: it exists for **developers and CI, not for
  ArgoCD**. `git remote -v` here: `origin` = `https://git.spencerslab.com/CuratedForest/SpencersLab.git`
  (GitHub is only an `upstream` remote). `.forgejo/workflows/` (containers-build, main-sync,
  renovate, release) is build/release-authoritative. `grep github.com/OwnYourIO services/`
  → only clone-URL comments/secrets (`services/{dev,gpu}/prod/values.yaml` coder github-auth,
  a stale comment in home) — **zero appset/source templates carry it**. So flipping the
  fleet's git world = editing the 11 cluster-secret annotations (out-of-band, human, cf-11
  precedent), not a git change.

## 3. The two answers + implications for the fix rounds

**Answer: roots track GitHub ⇒ the fan-out race EXISTS and is structural.** Mechanism, all
read today: `.forgejo/workflows/main-sync.yaml` (on the prod instance, `push.branches:[main]`,
ROLE-guarded `contains(vars.ROLE,'prod')`) asynchronously clones (checkout `fetch-depth: 0`)
and non-force-pushes main to GitHub (`push-gh` job, lines 28-47) and the dev instance
(`push-dev`, 49-68). A Forgejo-fired webhook therefore hits the relay **before** GitHub —
which the fleet still reads — has advanced; the sync resolves whatever revision
`github.com/OwnYourIO/SpencersLab`'s `main` had when ArgoCD last polled it (default 120s+60s
jitter, no override **[E §4]**). Result: sync-lands-old-revision, every push, deterministically
(mirror lag = Actions queue + clone + push; add the repo-server cache staleness on top).
The C03 runbook already reasoned around this: `.agents/notes/2026-11-17-argocd-hook-relay.md:123-124`
fires the hook on GitHub *precisely because* "main-sync copies main from the Forgejo canonical
repo" — the owner ruling re-opens that choice. The fix round must pick the resolution (NOT
this scout's call): **(a)** move the fleet to Forgejo sources (all git repoURL annotations +
the customValuesUrls raw URLs → forge raw path; GitHub Pages chart index `ownyourio.github.io`
is semver-not-ref and can stay), then flip `trackedRepo` atomically; **(b)** keep GitHub
sources and fire the Forgejo hook with a settle/re-verify leg (new code + a GitHub read
credential — argues against); **(c)** fire from the Forgejo repo but from the main-sync
workflow AFTER `push-gh` lands (timing-correct, zero annotation churn — needs an HMAC'd POST
step; arguably still "webhook source = FORGEJO" in the owner's sense). **Decision needed →
escalate.**

**If the fleet moves to Forgejo (option a), the roster facts change as follows**:
`trackedRepo` (`charts/argocd-hook/values.yaml:23`, github URL) is consumed byte-literally —
`app_matches` is exact `s.get("repoURL") == repo` (`containers/argocd-hook/main.py:213-214`),
no normalization. It is correct-world for all 11 targets TODAY (live string is byte-identical
incl. `.git`); flipping it while sources stay on GitHub would make every target's root app
non-eligible → fan-out logs `result=skipped` ×11 — a silent no-op (202 still returned!).
The flip must therefore be: cluster secrets first, `trackedRepo` in the same release, chosen
string = exactly what the annotations will be set to (the fork's canonical clone form is
`https://git.spencerslab.com/CuratedForest/SpencersLab.git` per `git remote -v` origin — with
or without `.git` is the fix round's contract to pin). Also: the hub itself (proxy-local →
its root app) is on GitHub too, so option (a) changes the relay's own app's source repo
mid-flight — bootstrap-ordering note for the runbook.

## 4. Forgejo webhook surface — verified vs assumed (fix rounds + runbook)

VERIFIED (forgejo.org docs v17.0, fetched 2026-11-21 — infra runs Forgejo 17.3.x:
`charts/forgejo/Chart.yaml:13` dep 17.3.1, renovate tag bump commit 3027dec66 → v17.0 docs
apply with minor-drift caveat; plus local files):
- UI path: repo `Settings → Webhooks` at `/:user/:repo/settings/hooks`; type **Forgejo** or
  **Gitea** (both POST, `application/json` selectable); secret configurable ("Secret" field);
  Test Delivery button + Recent Deliveries list exist. Org- and instance-level hooks also exist.
- Headers on an event: Forgejo sends ALL of `X-Forgejo-Event`/`X-Gitea-Event`/
  **`X-GitHub-Event`** + matching `*-Delivery` UUID headers (docs example block) ⇒ the relay's
  `X-GitHub-Event` check and `X-GitHub-Delivery` logging (main.py:369,388) **work unchanged**
  against a Forgejo webhook of type Forgejo. Type→header-family mapping for the *Gitea*
  webhook type alone is ASSUMED (docs list the union; verify live).
- Signature: `X-Forgejo-Signature` = **plain hex HMAC-SHA256 of the raw body — no `sha256=`
  prefix** (docs' PHP reference implementation). The relay reads only `X-Hub-Signature-256`
  and `verify_signature` REQUIRES the `sha256=` prefix (main.py:179-183,365) ⇒ **every Forgejo
  delivery 401s today**. This is a code change (accept the bare-hex header in parallel or
  instead), not a values change — the DECISIONS "fix with values, not code" ruling covered
  roster hosts only and does not exempt this.
- Push payload fields: `ref` (full `refs/heads/<branch>`), `before`, `after`,
  `repository.full_name`, `repository.ssh_url` (`ssh://git@host:PORT/owner/repo.git` form on
  this fleet, `.agents/notes/2026-10-23-forgejo-git-ssh.md`), `compare_url`, `commits[]` —
  docs example verified. Local corroboration: `.forgejo/workflows/release.yaml:54` reads
  `${{ github.event.before }}` (Actions context mirrors the payload; its comment warns
  "Forgejo event payloads can carry missing keys" — handle absent `before`/first-push).
  Relay consumes `ref` only (main.py:379) — `refs/heads/main` in, `["refs/heads/main"]`
  filter matches unchanged. Gitea-type signature header name (`X-Gitea-Signature`) = ASSUMED
  from the launch brief, unverified by my fetch.
- Ping/test event: GitHub sends `ping`; Forgejo's Test Delivery semantics (event name +
  payload shape) NOT verified → fix round must test against the live instance before
  rewriting the runbook's smoke steps.

GitHub-coupled surfaces the fix round must sweep (all read 2026-11-21): relay code
(main.py:25-30 `GITHUB_SECRET_FILE`/`github-webhook` filename, 179-183, 365-388; README.md:3,16);
chart (`values.yaml:20-23` comment+default; `templates/secret-argocd-hook.yaml:18`
`secretKey: github-webhook` — flat filename is the relay's file contract, renaming touches
chart+relay+harness+Bitwarden item field together); harness
(`tests/containers/argocd-hook-relay.sh:391-395` signs `X-Hub-Signature-256` +
`X-GitHub-Event` — add/switch to Forgejo-shaped deliveries, keep both if dual-format);
runbook (`.agents/notes/2026-11-17-argocd-hook-relay.md:114-146,199` — webhook creation
steps, curl smoke headers, kill switch all point at GitHub repo settings).

## Open questions (fix rounds / owner — scout does not decide)

1. Which race resolution (option a/b/c above) does the owner rule? Whole roster + runbook +
   human-action list shape depends on it.
2. Is `CuratedForest/SpencersLab` on the prod forge PUBLIC? The fleet's ArgoCD repo-server
   has zero repo-creds wiring ([E §1]); private sources would add per-cluster credential work
   to option (a).
3. Exact strings the 11 cluster-secret annotations will take (`…/SpencersLab` vs `…/SpencersLab.git`,
   raw-values URL form `/raw/branch/main/…` — form assumed from Gitea convention, verify live).
4. Forgejo Test Delivery event name/payload (ping-equivalent) and Gitea-type signature header
   — verify against the live instance, not docs.
5. Whether the `ownyourio.github.io` chart index and `upstream` GitHub remote stay (they can —
   not ref-tracked surfaces), or the owner expects a fuller GitHub retirement than this ticket
   must implement.
