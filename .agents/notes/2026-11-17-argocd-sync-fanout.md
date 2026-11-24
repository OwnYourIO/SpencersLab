# ArgoCD sync fan-out — operator runbook (cf-139)

Makes "push to `main` lands on every cluster" real without touching the kill-switch.
Every command in this file is **human-executed**: this repo never applies to a cluster
(AGENTS.md law), and the operator legs are the 11 per-cluster `mcp-bot` token mints,
ONE org-level Actions secret paste, the moot-keys check, and the dispatch smoke (plan
"Human-owned list"). Background lives in the ticket folder
`.agents/plans/2026/2026-11-cf-139-feat-argocd-webhook-sync/` (plan of record,
`RESEARCH.md`, `DECISIONS.md` incl. the reopen2 rulings R5/R6 and the 2026-11-23
batched round). The reopen1 in-cluster layer (chart + container) was never deployed
and was disposed branch-local — nothing on any cluster needs teardown ([P2],
DECISIONS 2026-11-23).

## 1. What this is / what it is not

- **Is**: the Forgejo `sync-fanout` job of `.forgejo/workflows/main-sync.yaml` driving
  **actual ArgoCD API syncs** (`POST /api/v1/applications/<app>/sync`, non-force,
  `prune=false`) on each cluster directly from the runner's network vantage — root app
  first, settle, then a sweep of every still-OutOfSync app whose source repo and live
  `targetRevision` match the push. The logic is `scripts/argocd-fanout.py` (stdlib
  python3, from the checkout) with the roster `scripts/argocd-fanout.json`; auth is one
  per-cluster `mcp-bot` bearer token (RBAC `applications get,sync */*`) held in one
  org-level Actions secret.
- **The job IS the trigger** (R1 option (c), unchanged by reopen2): no webhook exists
  or is created anywhere, there is no receiver endpoint, and no in-cluster component.
  The race resolution is `needs: [push-gh]` — the fleet's apps still source
  `https://github.com/OwnYourIO/SpencersLab.git` (EXPLORE [P §1]), so the fan-out fires
  only after the mirror push advanced GitHub; an earlier fan-out would land the
  PREVIOUS revision.
- **Is not**: a change to any automated sync policy. The
  `services.<cat>.selfHeal="false"` cluster-secret annotations — the kill-switch — stay
  untouched, on roots and children alike (OQ1 ruling "kill-switch KEPT"). No appset
  template, no `charts/base`, and no cluster-secret is edited by anything in this
  file; the cf-11 annotation-edit precedent is the pattern this runbook does not need.
- **Ref model** (OQ7 ruling): the fan-out fires only for refs in the `allowed_refs`
  LIST in `scripts/argocd-fanout.json` (shipped `["refs/heads/main"]` — the only branch
  revision the fleet's appsets resolve to today; `refs/tags/*` entries are rejected at
  parse). Second, per-target layer with zero config: for a fired ref it syncs only apps
  whose live `spec.targetRevision` matches it, so a widened `stage` push can never
  sync-fire a prod-tracking cluster.
- **Widening procedure** (e.g. a future per-cluster `stage` branch): add the full ref
  to `allowed_refs` in `scripts/argocd-fanout.json`, open a PR, merge — the job runs
  from the checkout, so the next push already carries the widened list. One JSON edit +
  PR; no vault change, no code change.
- **Why non-force always**: the 2026-10-20 k3s incident — automated selfHeal re-applying
  system-upgrade-controller Plans on `/status` drift SIGTERM'd k3s (comment in
  `charts/base/values.yaml`, ignoreDifferences fix). Force could clobber live-owned
  fields the same way; non-force + the shipped ignoreDifferences cannot.

## 2. Step 0 — the vault (human, post-merge)

Zero Bitwarden: no items to create, no ExternalSecrets, no UUID fill — the Forgejo
Actions vault is the entire secret story (reopen2 R5). Sequence:

**1. Mint 11 tokens** — one per fleet category, each against that cluster's OWN ArgoCD
route host (the full table in §6; dev answers on `cluster.dev.scifi.farm`, home on
`cluster.home-lab.spencerslab.com`). Fresh `mcp-bot` tokens (rotation isolation — not
the argocd-mcp servers' tokens); admin session or the UI key form, minted WITHOUT
`--expires-in` per the ruled TTL posture (§8):

```bash
# human-executed — one mint per cluster route host
argocd account generate-token --account mcp-bot
```

**2. Compose the paste** — newline-delimited `cat:token` records, one per line, 11
lines (OQ8 ruling — per-line masking granularity, RESEARCH [26]):

```text
dev:<dev-mcp-bot-jwt>
gpu:<gpu-mcp-bot-jwt>
gpu-ai:<gpu-ai-mcp-bot-jwt>
grow:<grow-mcp-bot-jwt>
home:<home-mcp-bot-jwt>
infra:<infra-mcp-bot-jwt>
media:<media-mcp-bot-jwt>
monitoring:<monitoring-mcp-bot-jwt>
proxy-local:<proxy-local-mcp-bot-jwt>
proxy-backup:<proxy-backup-mcp-bot-jwt>
proxy-remote:<proxy-remote-mcp-bot-jwt>
```

Category left of the `:`, token right of it, one line per cluster. Run
`python3 scripts/argocd-fanout.py --check` locally with the same value mapped into
the `ARGOCD_SYNC_TOKENS` env (§5b) before pasting: it parses fully and answers
`vault: 11 records matched to the roster (values never printed)` — a mangled
composition fails there, not in a live run.

**3. Create the ONE org-level Actions secret** — on the PROD forge instance, in the
**ORG** Settings → Actions → Secrets (CuratedForest org at git.spencerslab.com — NOT
repo settings): name `ARGOCD_SYNC_TOKENS`, value = the 11 lines above. The repo
INHERITS it: the job's `${{ secrets.ARGOCD_SYNC_TOKENS }}` reference resolves through
scope resolution repo→org→user, so keep this the single instance — a repo-level key
of that name would silently WIN, so never create one repo-side. Confirm at creation
that the UI stored all 11 lines (multi-line paste is an instance-UI behavior the
owner checks once, at creation).

**4. Delete-check the moot pair** — delete `vars.ARGOCD_HOOK_URL` and
`secrets.ARGOCD_HOOK_SECRET` from this repo's Settings → Actions if they exist;
EXPLORE [P2] confirmed they were never created, so this is a no-op: confirm their
ABSENCE and move on. The fan-out reads neither.

## 3. Step 1 — the merge IS the install

Nothing to pre-apply. Merge the PR (the owner opens/merges; this repo never advances
`main` by an agent) and the `sync-fanout` job exists inside the already-deployed
`main-sync.yaml`, with `scripts/argocd-fanout.py` + `scripts/argocd-fanout.json`
riding every checkout the runner makes. Then paste the §2 secret. Until the paste,
every run skips green with the §4 warning — designed, not an incident. The first push
after the paste fans out; the sweep is SHA-agnostic (it syncs current git state), so
any pre-existing OutOfSync drift lands with it — the same real-drift note as §6's
accept-before-first-push row applies once.

## 4. Step 2 — the trigger's anatomy (nothing to create)

No webhook to add on any platform and nothing to enable in ArgoCD — the job IS the
mechanism, and the ordering (`needs: [push-gh]`) is why no webhook is needed at all:
a raw Forgejo push webhook must never be created (it fires BEFORE `push-gh` advances
GitHub, so every fan-out would land the PREVIOUS revision — [P §3]). Live bytes of the
job's shape:

- Triggers: `push` on `main` and `workflow_dispatch`.
- Guard: `if: contains(vars.ROLE, 'prod')` — unset `ROLE` or a dev-role instance fire
  nothing (fail-safe-narrow, the file-wide convention).
- The vault value is mapped into the step `env` ONLY (never interpolated into the run
  body, never argv).
- Unset-skip (exact warning the job prints when the secret is absent):
  `::warning::sync-fanout not configured (org-level Actions secret ARGOCD_SYNC_TOKENS absent) — fan-out skipped, manual sync or the next push covers it`
  followed by exit 0. This line is also the §7 kill switch's proof-of-removal.
- Ref resolution for dispatch/first-push: `EVT_REF → GH_REF → refs/heads/main`.
- The call `python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref "$REF"`
  is deliberately UN-guarded under `set -euo pipefail` — two honest lanes:
  **config/setup errors go RED** (a typo'd record, unknown or missing category,
  non-JWT token — even a reversed `token:cat` paste, reported value-free as
  `vault record looks reversed (token before category)` — must not silently lose a
  cluster every push forever), while **per-target runtime failures stay soft** inside
  the script's own contract (§5 audit lines, job green).

## 5. Step 3 — smoke (human)

Run (a) after the paste; (b) is the optional offline/live pre-check from any checkout;
(c) is the log-cleanliness leg; (d) is the real-merge acceptance.

- **(a) Dispatch smoke**: on the prod instance run main-sync via `workflow_dispatch`
  (Actions UI → main-sync → Run workflow). `push-gh` executes first (its push no-ops
  when GitHub is current); `sync-fanout` then prints, per target, one audit line of the
  form `target=<name> result=<ok|skipped|failed> root=<root-app> ref=<full-ref> elapsed=<N.N>s detail=<...>`,
  then the roll-up `fan-out summary: targets=11 ok=<n> skipped=<n> failed=<n>`. A
  dispatch carries no push event, so the ref comes from the §4 fallback chain
  (`refs/heads/main`) — same fan-out, honestly labeled. Expect: `ok` lines for the
  reachable clusters, plus the two RULED honest `failed` rows — `proxy-local` (its
  route 307s to the hub login before the API sees the bearer — §6 note) and
  `proxy-backup` (unreachable from the runner vantage, OQ9 — other targets proceed
  regardless).
- **(b) Manual pre-check legs** (owner runs from a checkout; the token paste goes in
  via the environment — never argv):

  ```bash
  # human-executed — offline parse (zero network): roster + vault + table
  ARGOCD_SYNC_TOKENS="$(cat ./tokens-paste.txt)" python3 scripts/argocd-fanout.py --check
  # live GETs only, zero POSTs — the per-target reachability + would-sync report
  ARGOCD_SYNC_TOKENS="$(cat ./tokens-paste.txt)" python3 scripts/argocd-fanout.py --dry-run
  ```

  `--dry-run` is the pre-live reachability read (it is how the proxy-backup row's
  `applications list failed` expectation gets confirmed or retired).
- **(c) Masking spot-check** (verifies the [26] per-line masking claim live): in the
  rendered run log, search the first ~12 characters of any ONE minted token — expect
  ZERO hits: the runner registers every secret LINE independently, so any accidental
  echo prints as `***`. A hit means per-line masking does not hold at this runner:
  treat the pasted values as exposed, revoke (§8 `delete-token`), re-mint, re-paste —
  and re-weigh the record-shape ruling against that evidence.
- **(d) Real end-to-end**: push a no-op-ish PR to `main` on the prod forge. Watch the
  run: `sync-fanout` starts only after `push-gh` finishes; latency = mirror + fan-out,
  seconds-to-a-minute end to end (old poll path was ≤3 min per cluster by hand). Then
  watch APP status, not just the audit: ArgoCD answers a sync POST before
  manifest-generation failures land asynchronously, so the `home` root logs `ok` while
  its pre-existing drift (§6) keeps the app Unknown — manual sync fails identically
  there; it is not fan-out damage.

## 6. Preflight table (live reads 2026-11-21 + runner-vantage reads 2026-11-23 [P2])

One row per the 11 roster categories; the `backups` and `personal` categories are absent (they have no root Application — values-only dirs with no appset templates, EXPLORE §2). Root `spec.syncPolicy` and OutOfSync columns are the 2026-11-21 readonly MCP probes (all roots gated-off — the kill-switch, documented not moved); URL + expected columns are the shipped roster (`scripts/argocd-fanout.json`) and the [P2 §1] runner-vantage matrix (reproduced in the appendix).

| cluster | fan-out URL (roster) | root syncPolicy (probe 2026-11-21) | OutOfSync at probe | expected fan-out reading |
|---|---|---|---|---|
| dev | `https://cluster.dev.scifi.farm` | syncOptions only — gated-off | `dev` (root); children Synced | ok — exception host, TLS-verified 401-unauth baseline |
| gpu | `https://cluster.gpu.spencerslab.com` | syncOptions only — gated-off | `gpu-llama-swap` | ok — the runner's OWN cluster: self-restart window, §8 |
| gpu-ai | `https://cluster.gpu-ai.spencerslab.com` | syncOptions only — gated-off | `gpu-ai-llama-swap`, `gpu-ai-radiance`, `gpu-ai-radiance-q27` | ok |
| grow | `https://cluster.grow.spencerslab.com` | syncOptions only — gated-off | `grow-assistant`, `grow-okd` | ok |
| home | `https://cluster.home-lab.spencerslab.com` | syncOptions only — gated-off | `home` (Unknown — pre-existing manifest-generation drift), `home-immich-analyze`, `home-pictaria`, `home-postiz` | ok line, app may stay Unknown (§5d); exception host |
| infra | `https://cluster.infra.spencerslab.com` | syncOptions only — gated-off | `infra` (root), `infra-forgejo` | ok |
| media | `https://cluster.media.spencerslab.com` | syncOptions only — gated-off | `media` (root), `media-minuspod`, `media-prowlarr` | ok — probe retry answered 2026-11-21 after scout-time ECONNREFUSED |
| monitoring | `https://cluster.monitoring.spencerslab.com` | syncOptions only — gated-off | `monitoring-grafana` | ok |
| proxy-local | `https://cluster.proxy-local.spencerslab.com` | syncOptions only — gated-off | none (`proxy-local-traefik` compares Unknown — transient) | **failed while the route answers 307→login**: the hub's SSO forward-auth ignores the bearer, so this target can structurally refuse it regardless of mint (C05-review owner leg). Honest `applications list HTTP 307` line meanwhile; remedy, if the hub should automate too, is the crowdsec-only `git`/`forms` route-exception precedent — a separate owner call outside this ticket |
| proxy-backup | `https://cluster.proxy-backup.spencerslab.com` | not probed (no readonly MCP) | unknown | **failed — ruled posture (OQ9)**: silent from the runner vantage ([P2] TCP timeout); an honest `failed` audit line, every other target proceeds, never a silent drop. Owner leg: check the box from a vantage that can (its old subnet made it reachable to the hub); if truly dead, the roster edit is a follow-up PR, out of this ticket |
| proxy-remote | `https://cluster.proxy-remote.spencerslab.com` | not probed (no readonly MCP) | unknown | ok expected — [P2] TLS-verified through the public edge; the `mcp-bot` mint there is a by-hand leg (UI on that cluster, no MCP to check its syncPolicy from here) |

`infra-seaweedfs` — the known 2026-11-10 drift app
(`.agents/notes/2026-11-10-seaweedfs-incident-findings.md`) — probed **Synced/Healthy**
on 2026-11-21; the incident remediation stuck. The accept-before-first-push habit
applies to every app the OutOfSync column names: the first fan-out sync applies that
accumulated drift exactly like your manual Sync button does today — glance at the
column once, then trust it.

## 7. Rollback

1. **Instant kill switch (no git)**: delete — or overwrite with empty — the ORG-level
   Actions secret `ARGOCD_SYNC_TOKENS` in the prod instance's ORG Settings → Actions.
   Presence is the whole switch: the repo carries no key of that name (org placement is
   the single instance, §2), so the removal takes effect for the inheriting repo's next
   run immediately. The job then logs the §4 line `sync-fanout not configured …` and
   skips green, every run — that warning IS the proof-of-unset. The fleet reverts to
   manual sync; the mirror (push jobs) keeps working untouched.
2. **Git leg (full removal)**: revert the PR — the `sync-fanout` job hunk in
   `.forgejo/workflows/main-sync.yaml` and the two `scripts/argocd-fanout.*` files go
   with it; the pre-ticket main-sync (push jobs only) returns.

State plainly: nothing else changes anywhere — no residual impact. No cluster-side
cleanup leg exists or ever existed: the reopen1 layer was never deployed (§1
disposition note), so there is no in-cluster component, secret, route, or Bitwarden
record to remove. The syncPolicy posture never moved (§6 proves it), no prune was ever
run (`prune=false` pinned in both query and body of every sync), and no cluster-secret
annotation was ever touched. The fleet is exactly back at today's manual workflow.

## 8. Limitations

- **Trigger failure lands the push as a no-op at the old revision**: if the job skips
  (unset vault), the runner dies, or a target fails mid-sweep, that push simply does
  not land there. No Actions redeliveries exist — a finished job cannot be
  re-delivered — and the fan-out is stateless: no queue, no replay. The next push to
  main self-heals it (the sweep syncs current git state, whatever SHA that is);
  fallback otherwise = manual sync, as today.
- **Green job ≠ green fleet, by design** (DECISIONS 2026-11-23 exit posture): per-target
  runtime failures audit honestly but keep the job green (the mirror must never break
  over the hook); an all-failed run (e.g. 11 revoked tokens) still exits 0 — read the
  `fan-out summary` line, not just the job chip. Config errors are the RED lane (§4).
  An all-SKIPPED run additionally prints a `::warning::` naming the
  `tracked_repo`-mismatch trap: the flip of `tracked_repo` is only ever valid in
  lockstep with the cluster annotations ([P §3]) — never drift it alone.
- **No prune** (OQ6 ruling): git-removed resources linger until you prune manually;
  every sync is non-force, `prune=false` — a mirror of the conservative manual button,
  not a replacement for the flip that was declined (OQ1).
- **Only allowed refs fire** (OQ7 ruling): refs outside `allowed_refs` print one
  skipped line and open no sockets; per fired ref only apps whose live
  `spec.targetRevision` equals it are synced. Shipped set covers every revision in
  use; widening is §1's roster-JSON PR.
- **Token TTL is indefinite by ruling (OQ10)** — `argocd account generate-token`
  defaults to no expiry, and that is the answer, not a gap: mcp-bot is apiKey-only and
  cannot self-mint, so an expiry mandate would build an outage treadmill (silent 401s
  in the warn-and-green lane) where a rotation robot does not exist. Revocation:
  `argocd account delete-token --account mcp-bot` identifying the mint kills the JWT
  server-side immediately. Rotation = re-mint on the cluster, then overwrite the vault
  secret — the next run uses the new record immediately (no refresh window, no pod
  restart).
- **One store, org-wide visibility (ruled trade-off)**: an org Actions secret surfaces
  into every repo job in the org (fork-PR jobs excluded, RESEARCH [21][22]); accepted
  under the owner's org key hygiene with this repo the sole consumer — the vault
  already holds the main-push token, so the crown-jewel argument is unchanged.
- **Runner vantage**: the job runs on the gpu cluster's runner (dind containers inherit
  the pod's LAN split-horizon resolver — inferred, not measured: §5's dispatch smoke IS
  the acceptance leg). The fan-out also syncs the gpu cluster that hosts the runner,
  and nothing in the design places that target last (workers are parallel, roster order
  is cosmetic): a gpu root sync that changes runner-pod manifests can truncate the
  running job — rare (only when the push touched those manifests), bounded ≈1–3 min by
  the 4-worker parallelism, next push self-heals. Accepted risk, ruled in the plan's
  Risks block and DECISIONS 2026-11-23.
- **Roster hosts stay `https`**: the parser accepts `http://` (test-lane shape), but the
  vault tokens are bearers — never add a cleartext roster URL.
- Dead `argocd-hook` `pr-*` container tags from reopen1's CI runs expire with normal
  registry hygiene — no action owed.

## Appendix — known anomalies + the [P2] runner-vantage matrix (note-only)

- `cluster.proxy-local.spencerslab.com` publishes a public A record `10.0.77.54` — a
  mesh-only-rule violation, owner ruled NOTE-ONLY (DECISIONS 2026-11-17, OQ4); do not
  fix here. The fan-out dials the same route hosts every cluster's apps already use;
  from the lab the split-horizon answer is that LAN address — the leak note is about
  the public record, not this ticket's traffic.
- The `home` root's pre-existing helm-dependency manifest-generation error (§6 row)
  also fails manual syncs; the fleet repair belongs to a renovate-class change outside
  this ticket (FRICTION 2026-11-21, review C02).
- Runner-vantage reachability, measured 2026-11-23 from the gpu cluster's pod network
  (the network main-sync jobs execute in) — the RESEARCH [P2 §1] matrix, measurement
  cells unchanged;
  10 of 11 targets TLS-verify with no `-k`; proxy-backup is the one silent host:

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
  | cluster.proxy-backup.spencerslab.com | 10.0.77.5 | — | **timeout** | TCP 443+80 filtered, ping dead |
  | cluster.proxy-remote.spencerslab.com | 5.78.101.168 | ok | 401 | the public edge serves its argocd route |
