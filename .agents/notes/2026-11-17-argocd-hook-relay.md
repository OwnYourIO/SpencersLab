# argocd-hook relay — operator runbook (cf-139)

Makes "push to `main` lands on every cluster" real without touching the kill-switch.
Every command in this file is **human-executed**: this repo never applies to a cluster
(AGENTS.md law), and the four setup legs (Bitwarden items, per-cluster token mints,
custom-values UUID fill, Actions vault key placement) are owner-owned by ruling (plan
"Human-owned list"). Background lives in the ticket folder
`.agents/plans/2026/2026-11-cf-139-feat-argocd-webhook-sync/` (plan of record,
`RESEARCH.md`, `DECISIONS.md` incl. the R1–R4 reopen rulings); this file is the procedure.

## 1. What this is / what it is not

- **Is**: a small HMAC-verified relay (`containers/argocd-hook`, chart
  `charts/argocd-hook`, deployed only on the proxy-local hub) that receives a signed
  push payload and drives **actual API syncs**
  (`POST /api/v1/applications/<app>/sync`, non-force, `prune=false`) on each cluster's
  root app and its still-OutOfSync repo-sourced children, over mesh DNS.
- **Origin of the trigger** (R1 ruling, option (c)): the canonical caller is the
  `hook-relay` job of the Forgejo `.forgejo/workflows/main-sync.yaml` mirror workflow —
  **no webhook is created anywhere; the job IS the webhook**. It fires
  `needs: [push-gh]`, i.e. only after the mirror push advanced GitHub: all nine
  reachable clusters' apps still source `https://github.com/OwnYourIO/SpencersLab.git`
  (EXPLORE [P §1]), so a fan-out fired earlier would resolve the PREVIOUS revision —
  the ordering is race-freedom, not a nicety. A public POST endpoint remains as a
  documented door (§4), not the shipped trigger.
- **Signature dialects** (R3): the relay accepts `X-Hub-Signature-256` carrying
  `sha256=<hex>` (GitHub/door shape) and `X-Forgejo-Signature` carrying PLAIN
  lowercase hex (the job's shape). The first-present header decides the dialect and
  only that header is verified — no cross-dialect fallback (a malformed or forged
  first header is a 401 even beside a valid second one). The job sends the
  GitHub-compatible header family (`X-GitHub-Event: push` included), so the relay's
  event gate is unchanged.
- **Secret file** (R4 rename): the shared HMAC key lands in the relay's mounted
  secrets dir as `hook-secret` (`/secrets/hook-secret`) — semantics are no longer
  GitHub-specific; the caller is the Actions job.
- **Is not**: a change to any automated sync policy. The
  `services.<cat>.selfHeal="false"` cluster-secret annotations — the kill-switch — stay
  untouched, on roots and children alike (OQ1 ruling "kill-switch KEPT"). Nothing here
  edits them, no appset template, or `charts/base`; every command below mutates nothing
  annotation-related. The cf-11 precedent (human out-of-band cluster-annotation edits)
  is the pattern this runbook deliberately does NOT need — no annotation is touched.
- **Ref model** (OQ7 ruling): the relay fires only for refs present in its
  `allowed_refs` CONFIG LIST (chart values key `allowedRefs`, shipped default
  `["refs/heads/main"]` — the only branch revision the fleet's appsets resolve to
  today). Second, per-target layer with zero config: for a fired ref it syncs only
  apps whose live `spec.targetRevision` matches it, so a widened `stage` push can
  never sync-fire a prod-tracking cluster. `refs/tags/*` never fire.
- **Widening procedure** (e.g. a future per-cluster `stage` branch): edit `allowedRefs`
  in `charts/argocd-hook/values.yaml` (add the full ref), open a PR, let the owner merge,
  sync root `proxy-local` once — the ConfigMap re-renders, the reloader restarts the pod.
  One values edit + PR + sync; no code change.
- **Why non-force always**: the 2026-10-20 k3s incident — automated selfHeal re-applying
  system-upgrade-controller Plans on `/status` drift SIGTERM'd k3s (comment in
  `charts/base/values.yaml`, ignoreDifferences fix). Force could clobber live-owned
  fields the same way; non-force + the shipped ignoreDifferences cannot.

## 2. Step 0 — secrets (human, POST-merge: "merge first, fill later", OQ5)

The OQ5 ruling is **merge first, fill later**: the branch merges with the
`OVERRIDE_NEEDED` sentinels intact and the real UUIDs arrive in a post-merge commit.
Do this BEFORE Step 1 so bootstrap starts clean in one pass.

1. Bitwarden — create login item **`argocd-hook`**: password = a fresh random
   high-entropy **shared relay↔main-sync HMAC** secret — one value, both callers
   (the job signs with it, the relay verifies with it; human-executed):

   ```bash
   # human-executed
   openssl rand -hex 32
   ```

   The chart's ExternalSecret mounts that password into the relay pod as the flat
   file `hook-secret` under `/secrets`.

2. Bitwarden — create item **`argocd-hook-tokens`** with one custom field per fleet
   category, field name = category (11 fields): `dev`, `gpu`, `gpu-ai`, `grow`, `home`,
   `infra`, `media`, `monitoring`, `proxy-local`, `proxy-backup`, `proxy-remote`.

3. On EACH cluster mint a NEW token for the existing `mcp-bot` local account (its RBAC is
   `applications get,sync */*` — exactly what the relay needs; fresh tokens rather than
   the argocd-mcp servers' tokens for rotation isolation, DECISIONS 2026-11-17). From an
   admin session against that cluster's ArgoCD (UI alternative: mcp-bot account →
   API KEYS → ADD KEY), human-executed:

   ```bash
   # human-executed — run against each cluster's live ArgoCD route host: the derived
   # cluster.<cat>.spencerslab.com for nine categories, dev on cluster.dev.scifi.farm
   # and home on cluster.home-lab.spencerslab.com (fixed hosts — appendix)
   argocd account generate-token --account mcp-bot
   ```

   Paste each token into the matching `argocd-hook-tokens` field.

4. On the PROD forge instance (the infra-role one whose `ROLE` makes main-sync fire),
   place the Actions vault pair for the `hook-relay` job — repo Settings → Actions →
   Secrets and variables:

   - secret `ARGOCD_HOOK_SECRET` = the `argocd-hook` Bitwarden item's password (the
     same value, not a new one);
   - variable `ARGOCD_HOOK_URL` = the relay URL the runner reaches — the mesh form
     `https://argocd-hook.cluster.proxy-local.<domain>/` or the public entry
     `https://argocd-hook.spencerslab.com/`; which one resolves from the runner is
     the owner's instance-side call and Step 3(a)'s dispatch smoke proves it.

   The HMAC value now lives twice — the Bitwarden item password (what the relay reads
   as `hook-secret`) and this Actions secret (what the job signs with) — and both
   vaults MUST AGREE. The symptom is diagnosable: a 401 in the job log means they
   disagree (the job says so in its own warning line).

5. Once the branch has merged, replace BOTH sentinel lines in
   `custom-values/proxy-local/prod-values.yaml` with the real item UUIDs, as a follow-up
   commit at your convenience. The shipped block reads (quoted verbatim):

   ```yaml
   argocd-hook:
     bitwardenIds:
       argocd-hook-secret: OVERRIDE_NEEDED
       argocd-hook-tokens: OVERRIDE_NEEDED
   ```

   `argocd-hook-secret` takes the `argocd-hook` item UUID, `argocd-hook-tokens` the
   `argocd-hook-tokens` item UUID.

Until that UUID commit exists AND root `proxy-local` has synced after it, the relay
cannot come up: `proxy-local-argocd-hook` crash-loops visibly (ExternalSecret cannot
resolve the sentinels). That is ruled-in designed behavior (OQ5) — visible and harmless
to everything else, not an incident.

## 3. Step 1 — bootstrap (after Step 0 ideally)

1. Land the PR — the owner opens/merges it; the repo never advances `main` by an agent.
   The trigger lands with this merge: the `hook-relay` job ships inside the already
   deployed `main-sync.yaml`, so beyond Step 0's vault pair there is nothing to
   install, enable or click for the fan-out to exist.
2. Sync root app `proxy-local` once, manually — the last manual act this workflow will
   need. UI: `https://cluster.proxy-local.spencerslab.com` → app `proxy-local` →
   SYNC (human-executed; `argocd app sync proxy-local` is the CLI equivalent).
3. The `charts:` entry ships `argocd-hook` in the base charts appset, which generates the
   child Application `proxy-local-argocd-hook`; sync it once too, as the appset appears
   it. The rendered Service is named `proxy-local-argocd-hook` (port 8080) — the same
   name the hub subdomain entry `proxy.subdomains.argocd-hook.service` points at in
   `services/proxy-local/prod/values.yaml`.
4. Verify (human-executed):

   ```bash
   # human-executed — pod Ready: UI app tree, or
   kubectl --context proxy-local get pods -n default -l app.kubernetes.io/name=proxy-local-argocd-hook
   # relay health through the hub route:
   curl -fsS https://argocd-hook.spencerslab.com/health   # expect: ok (HTTP 200)
   ```

If a root sync happened before the Step 0 UUID fill: the expected CrashLoopBackOff
resolves itself after the UUID commit lands and you sync root `proxy-local` once more
(the appset re-renders the child with real UUIDs). No other remediation.

## 4. Step 2 — the trigger: the main-sync hook job (nothing to create)

R1 option (c): **nothing to create** in this step — no webhook exists on any
platform; the mirror workflow's final `hook-relay` job (`needs: [push-gh]`) IS the
fan-out trigger. A merge that
reaches `main` on the prod forge instance runs main-sync automatically: `push-gh`
advances GitHub, then the job signs the push payload and POSTs it to
`vars.ARGOCD_HOOK_URL`. On the dev instance or with `ROLE` unset nothing fires at all
(the job's `if: contains(vars.ROLE, 'prod')` guard stays fail-safe-narrow, and
`needs: push-gh` chains its skip).

- **Kill switch (instant, no git)**: unset `ARGOCD_HOOK_URL` / `ARGOCD_HOOK_SECRET`
  in the prod instance's repo Actions settings. The job then warns and exits green —
  its log line is exactly `hook-relay not configured` (full warning: it names the two
  instance keys and notes the next push covers) — and manual sync keeps the fleet.
  The hook can never break the mirror: unset keys skip, failures warn, the job ends
  0. This is also the rollback lever (§7 leg 1).
- **Never create a raw Forgejo push webhook on this repo.** It would fire BEFORE
  `push-gh` advances GitHub, so every fan-out would sync the PREVIOUS revision
  (EXPLORE [P §3] — the race is structural, not tunable). Forgejo-shaped webhook
  headers and signatures are already supported by the relay, so the door does not
  need code — but the delivery itself must not be created while the fleet tracks
  GitHub.
- **Future door (R2)**: the public `https://argocd-hook.spencerslab.com/` entry stays
  shipped as a documented option. If the owner ever wants a real webhook, the
  race-free choice is a GitHub repo webhook — the apps track GitHub anyway, and its
  `X-Hub-Signature-256` prefixed dialect is the one the relay verifies unchanged
  (a non-`push` test delivery such as GitHub's ping verifies HMAC then no-ops 200,
  starting nothing).

## 5. Step 3 — smoke before trusting

Run these in order; relay logs:
`kubectl --context proxy-local logs deploy/proxy-local-argocd-hook` (human-executed).

- **(a) Dispatch smoke** — on the prod instance run main-sync via
  `workflow_dispatch` (Actions UI → main-sync → Run workflow; human-executed):
  `push-gh` runs first (its push no-ops when GitHub is already up to date), then the
  `hook-relay` job must log `ok: relay accepted code=202 delivery=<run-id>-<attempt>`.
  Call-out: a dispatch carries no push event, so the payload comes from the job's
  fallback defaults (`ref` → `refs/heads/main`, `after` → the run SHA, repo full name
  → the job's own repo) — same fan-out, honest payload shape. The relay audit log
  then shows `push accepted ref=refs/heads/main delivery=<run-id>-<attempt> targets=11`
  plus one `target=<name> result=ok|failed|skipped …` line per target.
  Eyeball the delivery tag: it is `run_id`-`run_attempt`, so a re-run of the same
  workflow reads as a distinct delivery.
- **(b) Signed synthetic `refs/heads/main` pushes in BOTH dialects** (from any mesh
  host; you will be prompted for the shared HMAC value), human-executed:

  ```bash
  # human-executed — read -rs keeps the HMAC out of the command line you copy around;
  # note openssl still sees it briefly in argv, so run this on a trusted host
  IFS= read -rs SECRET
  BODY='{"ref":"refs/heads/main"}'

  # door dialect (prefixed form, as a future GitHub webhook would sign):
  SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
  curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://argocd-hook.spencerslab.com/ \
    -H 'Content-Type: application/json' -H 'X-GitHub-Event: push' \
    -H "X-Hub-Signature-256: $SIG" -d "$BODY"

  # job dialect (plain hex) — the exact signing line main-sync's hook-relay uses:
  SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')
  curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://argocd-hook.spencerslab.com/ \
    -H 'Content-Type: application/json' -H 'X-GitHub-Event: push' \
    -H "X-Forgejo-Signature: $SIG" -d "$BODY"
  ```

  Each expect **202** + the per-target audit lines. The relay only reads `ref` from
  the payload. A WRONG secret value must yield **401** on either dialect — that is
  also what the job's `relay answered 401` warning means (§2 item 4's must-agree
  pair). First-present rule in action: sending `X-Hub-Signature-256` with a bad
  prefix form 401s even if a perfectly valid `X-Forgejo-Signature` rides along —
  no cross-dialect fallback.
- **(b′) Signed synthetic push of a NON-`allowed_refs` ref** — same recipes with
  `"ref":"refs/heads/smoke-x"` in the BODY: expect **200 no-op** and NO `target=` /
  sync log lines. This proves the config-list filter live; a dispatch cannot fake a
  foreign ref (the fallback pins `refs/heads/main`), so this leg stays curl-only.
  Repeat for a `refs/tags/…` ref if you like (also never fires).
- **(c) Real end-to-end**: merge a no-op-ish PR (docs bump). In the run view eyeball
  the ordering — `hook-relay` starts only after `push-gh` finishes — then watch every
  reachable root app reach Synced. Observed latency is now mirror (`push-gh`) + relay
  fan-out: seconds-to-a-minute end to end, well under the old ≤3-min poll path;
  record it. The `home` root's sync will not complete until its pre-existing
  manifest-generation drift clears: ArgoCD answers the relay's sync POST before the
  failure lands asynchronously, so the relay logs `target=home result=ok` while the
  app stays Unknown/OutOfSync — watch the app status, not the relay log (section 6
  note; manual sync fails identically).

## 6. Preflight table (live readonly MCP probes, 2026-11-21)

One row per the 11 fan-out categories; the `backups` and `personal` categories are absent (they have no root Application — values-only dirs with no appset templates, EXPLORE §2). Columns: root `spec.syncPolicy` as observed | one sampled child app state as
observed | apps not Synced at probe time | probe status. Expectation confirmed: every
root is gated-off (no `automated` block) — the table documents the kill-switch, it gates
nothing. Sampled children came back gated-off too (syncOptions only), confirming the
plan's working hypothesis that the service-wide annotation gates children as well; the
relay stays correct either way because its list-and-sync fan-out is policy-agnostic.

| cluster | root syncPolicy (observed) | child sample (observed) | OutOfSync set at probe | probe status |
|---|---|---|---|---|
| dev | syncOptions only — gated-off | `dev-cloudnative-pg` Synced/Healthy, no automated | `dev` (the root itself) | gated-off — probe ok (readonly MCP) |
| gpu | syncOptions only — gated-off | `gpu-amd-gpu` Synced/Healthy, no automated | `gpu-llama-swap` | gated-off — probe ok |
| gpu-ai | syncOptions only — gated-off | `gpu-ai-amd-gpu` Synced/Healthy, no automated | `gpu-ai-llama-swap`, `gpu-ai-radiance`, `gpu-ai-radiance-q27` | gated-off — probe ok |
| grow | syncOptions only — gated-off | `grow-assistant` OutOfSync/Healthy, no automated | `grow-assistant`, `grow-okd` | gated-off — probe ok |
| home | syncOptions only — gated-off | `home-bri-budget` Synced/Healthy, no automated | `home` (status Unknown), `home-immich-analyze`, `home-pictaria`, `home-postiz` | gated-off — probe ok; anomaly: root manifest generation fails on a pre-existing base-chart helm-dependency drift (fails under manual sync too, not relay-caused) |
| infra | syncOptions only — gated-off | `infra-389ds` Synced/Healthy, no automated | `infra` (the root itself), `infra-forgejo` | gated-off — probe ok |
| media | syncOptions only — gated-off | `media-audiobookrequest` Synced/Healthy, no automated | `media` (the root itself), `media-minuspod`, `media-prowlarr` | gated-off — probe ok (ECONNREFUSED at scout time 2026-11-12; retry 2026-11-21 answered) |
| monitoring | syncOptions only — gated-off | `monitoring-exporter-mikrotik` Synced/Healthy, no automated | `monitoring-grafana` | gated-off — probe ok |
| proxy-local | syncOptions only — gated-off | `proxy-local-external-secrets-bitwarden` Synced/Healthy, no automated | none (`proxy-local-traefik` compares Unknown — transient) | gated-off — probe ok |
| proxy-backup | not probed | not probed | unknown | not-reachable — manual row: no readonly MCP (EXPLORE §5); verify the root app's syncPolicy and mint its token by hand in the UI |
| proxy-remote | not probed | not probed | unknown | not-reachable — manual row: no readonly MCP (EXPLORE §5); same by-hand verification |

`infra-seaweedfs` — the known 2026-11-10 drift app (`.agents/notes/2026-11-10-seaweedfs-incident-findings.md`) —
probes **Synced/Healthy** today; the incident remediation stuck. The accept-before-first-push
habit generalizes to every app the OutOfSync column names: the first relay sync applies
that accumulated drift exactly like your manual Sync button does today — glance at the
column once before the first push, then trust it.

## 7. Rollback

1. **Instant source stop (no git)**: unset the prod instance's repo Actions keys —
   delete the `ARGOCD_HOOK_SECRET` secret and the `ARGOCD_HOOK_URL` variable in the
   Actions settings. The `hook-relay` job then warns-and-skips every run (§4's kill
   switch), the fleet reverts to manual sync, and the mirror keeps working untouched.
   If a GitHub webhook was ever created under the R2 door, disable or delete it there
   too — Recent Deliveries stays inspectable afterwards, Redeliver included.
2. **Git leg (optional, full removal)**: revert the wiring via a PR — the two
   proxy-local entries (the `charts.argocd-hook:` block and the
   `proxy.subdomains.argocd-hook:` entry in `services/proxy-local/prod/values.yaml`),
   the `charts/argocd-hook` chart dir, the `argocd-hook:` custom-values block, AND the
   `hook-relay` job hunk in `.forgejo/workflows/main-sync.yaml` (the revert removes the
   hook job the moment it lands). Then sync root `proxy-local` once manually. The
   relay app, route and secrets leave with it (the ExternalSecret targets are
   `creationPolicy: Owner`).

State plainly: nothing else changes anywhere — no residual impact. The syncPolicy
posture never moved (section 6 proves it), no prune was ever run by the relay
(`prune=false` pinned in both query and body of every sync), and no cluster-secret
annotation was ever touched. The fleet is exactly back at today's manual workflow.

## 8. Limitations

- **Trigger failure lands the push as a no-op at the old revision** (R1 documented
  consequence): if the `hook-relay` job skips, the POST dies, or the relay is down
  mid-run, that push simply does not fan out. No redeliveries exist for Actions runs
  — a real webhook can be re-delivered by hand; a finished job cannot — so nothing
  retries it. The next push to main self-heals (the fan-out is SHA-agnostic: it
  syncs current git state, whatever SHA that is); fallback otherwise = manual sync,
  as today. Per-target results are one audit line each in the relay log, so nothing
  fails silently.
- **No replay**: the relay is stateless by design; it never queues what it missed.
  The job POSTs once per run (bounded retries inside the single POST, then warn).
- **No prune** (OQ6 ruling): git-removed resources linger until you prune manually;
  every relay sync is non-force, `prune=false` — a mirror of the conservative manual
  button, not a replacement for the flip that was declined (OQ1).
- **Only allowed refs fire** (OQ7 ruling): refs outside the `allowed_refs` list are
  accepted-and-ignored (200, no syncs), and per fired ref only apps whose live
  `spec.targetRevision` equals it are synced. Shipped set `["refs/heads/main"]` covers
  every revision in use; widening is section 1's one-values-edit procedure.
- **Token rotation** = re-mint the `mcp-bot` token on the cluster, re-store it in the
  matching `argocd-hook-tokens` field; the ExternalSecret refreshes within 1 h and the
  `reloader.stakater.com/auto` pod annotation restarts the relay so it re-reads
  `/secrets` — the relay reads secrets at startup only. Rotating the SHARED HMAC
  means touching BOTH vaults (§2 item 4): new value in the `argocd-hook` item
  password AND in `ARGOCD_HOOK_SECRET`, or the next job run 401s until they agree.

## Appendix — known anomalies (note-only)

- `cluster.proxy-local.spencerslab.com` publishes a public A record `10.0.77.54` — a
  mesh-only-rule violation, owner ruled NOTE-ONLY (DECISIONS 2026-11-17, OQ4); do not
  fix here.
- Relay target hosts are the live-verified mesh route set — the derived
  `cluster.<cat>.<domain>` form for nine categories, and two fixed hosts from the
  chart's `clusterHosts` values map where the derived form does not resolve:
  dev → `cluster.dev.scifi.farm` (its own second apex), home →
  `cluster.home-lab.spencerslab.com` (its cluster name is `home-lab`). None of
  them route through the public record above; the hub resolves every host in-mesh.
  The prod runner → relay hop (`vars.ARGOCD_HOOK_URL`) is the one leg whose form —
  mesh or public entry — is instance-side data; §2 item 4 shows both shapes.
- The `home` root's pre-existing helm-dependency manifest-generation error (section 6
  row) also fails manual syncs; the fleet repair for it belongs to a renovate-class
  change outside this ticket (FRICTION 2026-11-21, review C02).
