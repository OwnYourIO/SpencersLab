# ArgoCD sync fan-out — operator runbook (cf-139)

Makes "push to `main` lands on every cluster" real without touching the kill-switch.
Every command in this file is **human-executed**: this repo never applies to a cluster
(AGENTS.md law), and the operator legs are the 11 `mcp-bot` token mints, the 22-key org
pair table (11 vars + 11 secrets), the sourced-env pre-verify, the moot-trio key check,
and the dispatch smoke (plan "Human-owned list"). Background lives in the ticket folder
`.agents/plans/2026/2026-11-cf-139-feat-argocd-webhook-sync/` (plan of record,
`EXPLORE.md`, `RESEARCH.md`, `DECISIONS.md` incl. the reopen3 ruling R7, the reopen4
ruling R8 fleet-blind delivery, and the 2026-11-25/26 input-mechanism blocks);
this file is the procedure.

## 1. What this is / what it is not

- **Is**: the Forgejo `sync-fanout` job of `.forgejo/workflows/main-sync.yaml` calling
  `scripts/argocd-fanout.py` (stdlib python3, from the checkout) after the `push-gh`
  job has advanced GitHub. The script POSTs **actual ArgoCD API syncs**
  (`POST /api/v1/applications/<app>/sync`, non-force, `prune=false`) to each cluster's
  own ArgoCD over the lab network: root app first, settle, then a sweep of every
  still-OutOfSync app whose source repo and live `targetRevision` match the push.
- **Input mechanism (R7 keys, R8 delivery)**: one key PAIR per cluster — org-level
  Actions **var** `ARGOCD_SYNC_<CAT>_URL` (the route host) plus org-level Actions
  **secret** `ARGOCD_SYNC_<CAT>_TOKEN` (that cluster's `mcp-bot` JWT) — and the fleet
  is **discovered from the delivered key map**: in CI the job's filter step selects the
  pair-named keys into `$RUNNER_TEMP/pairs.json` and the script reads that file (the
  `ARGOCD_PAIRS_FILE` channel); locally the script scans its own environment. Same
  names, same validator, zero divergence — no fleet list in code or JSON, no
  composition step, nothing to paste or format.
  `scripts/argocd-fanout.json` is five globals only (`allowed_refs`, `tracked_repo`,
  `settle_seconds`, `target_timeout_seconds`, `parallel_workers`).
- **The job IS the trigger** (R1 option (c), grown by the D59 owner ruling): no
  webhook exists or is created anywhere, there is no receiver endpoint, and no
  in-cluster component. The race resolution is
  `needs: [push-gh, build-containers, build-charts]` — the fleet's apps still source
  `https://github.com/OwnYourIO/SpencersLab.git` (EXPLORE [P §1]), so the fan-out
  fires only after the mirror push advanced GitHub, and the builder wait holds it
  until the fan BUILDS green: a red builder leaves the fleet at the previous
  revision until the next green fan (the unmoved `ci/last-built` marker re-covers
  the range by construction). An earlier fan-out would land the PREVIOUS revision.
- **Is not**: a change to any automated sync policy. The
  `services.<cat>.selfHeal="false"` cluster-secret annotations — the kill-switch —
  stay untouched, on roots and children alike (OQ1 ruling "kill-switch KEPT"). No
  appset template, no `charts/base`, no cluster secret, no Bitwarden record, and no
  annotation is edited by anything in this file.
- **Ref model** (OQ7 ruling): the fan-out fires only for refs in the `allowed_refs`
  list (shipped `["refs/heads/main"]`; `refs/tags/*` entries are rejected at parse).
  Second, per-target layer with zero config: for a fired ref it syncs only apps whose
  live `spec.targetRevision` matches it, so a widened `stage` push can never
  sync-fire a prod-tracking cluster.
- **Fleet changes**: widening a ref = one `allowed_refs` PR against
  `scripts/argocd-fanout.json`; fleet membership itself is VAULT-ONLY — the job is
  FLEET-BLIND and the vault IS the fleet: membership lives in which org key pairs
  exist (pure discovery, RULED 2026-11-26), so neither the job nor any repo file
  lists the fleet. Creating a complete pair enables a cluster; deleting BOTH keys
  retires one (§7/§8) — a fleet change is never a repo change.
- **Why non-force always**: the 2026-10-20 k3s incident — automated selfHeal re-applying
  system-upgrade-controller Plans on `/status` drift SIGTERM'd k3s (comment in
  `charts/base/values.yaml`, ignoreDifferences fix). Force could clobber live-owned
  fields the same way; non-force + the shipped ignoreDifferences cannot.

## 2. Step 0 — the org key pairs (human, instance-side)

Zero Bitwarden: no items, no ExternalSecrets, no UUID fill — the Forgejo Actions
vault (org-level) is the entire secret story (reopen2 R5, reshaped by R7).

**2.1 Mint 11 tokens** — one per fleet category, each against that cluster's OWN
ArgoCD route host (the `dev`/`home` rows are the two sanctioned exception domains —
the derived form does not resolve there). Fresh `mcp-bot` tokens (rotation isolation —
not the argocd-mcp servers' tokens), minted WITHOUT `--expires-in` per the ruled TTL
posture (§8); admin session per server or the UI key form, human-executed:

```bash
# human-executed — one indefinite mcp-bot JWT per cluster route host
argocd account generate-token --account mcp-bot --server https://cluster.dev.scifi.farm
argocd account generate-token --account mcp-bot --server https://cluster.gpu.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.gpu-ai.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.grow.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.home-lab.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.infra.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.media.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.monitoring.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.proxy-local.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.proxy-backup.spencerslab.com
argocd account generate-token --account mcp-bot --server https://cluster.proxy-remote.spencerslab.com
```

**2.2 Create the 22 keys in the PROD instance's ORG Settings → Actions**
(CuratedForest org at git.spencerslab.com — NOT repo settings): per category, the
var URL-side and the secret TOKEN-side, keys EXACTLY as below (the Actions UI shows
these names; category upper-snake, gpu-ai→`GPU_AI`). **Never create any of them
repo-side**: scope resolution puts repo above org for BOTH kinds, and a repo twin of
either kind WINS silently over the org row you think you set — the org placement
stays the single instance for both kinds. Fleet names are hyphen-only DNS labels:
underscores or dots inside a real cluster name cannot survive the delivered-key
mapping (§8).

| category | org var (URL side, value = the §6 route host) | org secret (TOKEN side, value = that JWT) |
|---|---|---|
| dev | `ARGOCD_SYNC_DEV_URL` = `https://cluster.dev.scifi.farm` | `ARGOCD_SYNC_DEV_TOKEN` |
| gpu | `ARGOCD_SYNC_GPU_URL` = `https://cluster.gpu.spencerslab.com` | `ARGOCD_SYNC_GPU_TOKEN` |
| gpu-ai | `ARGOCD_SYNC_GPU_AI_URL` = `https://cluster.gpu-ai.spencerslab.com` | `ARGOCD_SYNC_GPU_AI_TOKEN` |
| grow | `ARGOCD_SYNC_GROW_URL` = `https://cluster.grow.spencerslab.com` | `ARGOCD_SYNC_GROW_TOKEN` |
| home | `ARGOCD_SYNC_HOME_URL` = `https://cluster.home-lab.spencerslab.com` | `ARGOCD_SYNC_HOME_TOKEN` |
| infra | `ARGOCD_SYNC_INFRA_URL` = `https://cluster.infra.spencerslab.com` | `ARGOCD_SYNC_INFRA_TOKEN` |
| media | `ARGOCD_SYNC_MEDIA_URL` = `https://cluster.media.spencerslab.com` | `ARGOCD_SYNC_MEDIA_TOKEN` |
| monitoring | `ARGOCD_SYNC_MONITORING_URL` = `https://cluster.monitoring.spencerslab.com` | `ARGOCD_SYNC_MONITORING_TOKEN` |
| proxy-backup | `ARGOCD_SYNC_PROXY_BACKUP_URL` = `https://cluster.proxy-backup.spencerslab.com` | `ARGOCD_SYNC_PROXY_BACKUP_TOKEN` |
| proxy-local | `ARGOCD_SYNC_PROXY_LOCAL_URL` = `https://cluster.proxy-local.spencerslab.com` | `ARGOCD_SYNC_PROXY_LOCAL_TOKEN` |
| proxy-remote | `ARGOCD_SYNC_PROXY_REMOTE_URL` = `https://cluster.proxy-remote.spencerslab.com` | `ARGOCD_SYNC_PROXY_REMOTE_TOKEN` |

These names ARE the selection law, not a transcription of the workflow: the filter
step `resolve fan-out pairs` selects every delivered key matching
`^ARGOCD_SYNC_(.+)_(URL|TOKEN)$` into the pairs file, the script enforces the same
pair law on whatever arrives, and the workflow file itself names no pair keys at all
(fleet-blind, cf-139 R8) — a name that fits this table but not that regex (or vice
versa) is a bug the runbook suite fails on. Because the vault IS the fleet: creating
a complete valid pair IS enabling the cluster — the next run joins it, no PR;
deleting BOTH keys retires one — the pair leaves discovery silently and the §5
summary count is the audit, by design; deleting ONE side leaves a half-pair that
goes config RED naming the category until the twin follows; blanking a token
(present-but-empty) stays the ruling-(j) RED while the fleet is configured (§7/§8).
The same-release pairing of vault and repo changes died with R8 — fleet operations
never touch git.

**2.3 Pre-verify from a checkout (human)** — the pinned recipe is a SOURCED env file;
values never ride a command line (a `VAR=value cmd` shape puts the pair values in a
ps-visible argv). Write `pairs.env` with one `export` line per key (all 22, real
values), source and run the two read-mostly modes, then delete the file — it holds the
live bearer JWTs, the checkout does not gitignore it, and it must never end up in a
commit:

```bash
# human-executed — write pairs.env (one export line per org key, all 22, real
# values), source it, run the two read-mostly modes; values never on a command line
cat > pairs.env <<'EOF'
export ARGOCD_SYNC_DEV_URL=https://cluster.dev.scifi.farm
export ARGOCD_SYNC_DEV_TOKEN=<paste-dev-jwt>
# ... the remaining 20 keys in the same export form
EOF
set -a
source pairs.env
python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --check
python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --dry-run
rm -f pairs.env
```

`--check` opens zero sockets and must print `argocd-fanout --check: OK`, the
NAME/URL table from the discovered pairs, and the one line
`pairs: 11 targets discovered (values never printed)`. `--dry-run` dials every route with GETs only — the live reachability
read (expect the §5 ruled rows: `applications list HTTP 307` for proxy-local,
`applications list failed` for proxy-backup). Clear any
`argocd-fanout config:` complaint BEFORE the first push: it names clusters and keys,
never values, and lists ALL pair-integrity violations in one aggregated line.

**2.3b File-channel variant (human-executed)** — what CI actually runs: with the
exported pairs above still sourced, dump the `ARGOCD_SYNC_*` names to a temp JSON
and point the script at the file. The PATH is the only thing on the command line —
values never are — and the file channel wins ENTIRELY over the env scan when set,
so this pre-checks exactly what a CI run will see:

```bash
# human-executed — pairs.env sourced above; dump NAME->value pairs to a temp
# file, then --check through the CI channel (ARGOCD_PAIRS_FILE names a PATH only)
python3 -c 'import json, os; json.dump({k: v for k, v in os.environ.items()
    if k.startswith("ARGOCD_SYNC_")}, open(os.path.expanduser("~/pairs-check.json"),
    "w"), sort_keys=True)'
ARGOCD_PAIRS_FILE=~/pairs-check.json python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --check
rm -f ~/pairs-check.json
```

**2.4 Delete-check the moot TRIO** (owner hygiene — keys the superseded designs would
have created; the reopen1 pair's creation leg was post-merge and never ran, and the
reopen2 paste leg may or may not have run in the 11-23→11-25 window, so confirm
ABSENCE or DELETE each): `vars.ARGOCD_HOOK_URL`, `secrets.ARGOCD_HOOK_SECRET`, and
`secrets.ARGOCD_SYNC_TOKENS` — repo Settings → Actions for the first two, ORG
Settings → Actions for the blob. Nothing reads any of them: the pair shapes match no
discovery key and the blob name matches nothing by construction.

## 3. Step 1 — the merge IS the install

Nothing to pre-apply and no vault write makes the mechanism exist: the fleet lives
in the org key pairs, the blob-and-filter delivery channel rides the workflow file,
and the script + globals ride every checkout. The §2 keys live instance-side, so
their order against the merge is inert-safe; what fans out is the conjunction — merge
the PR (the owner opens/merges; this repo never advances `main` by an agent), keep
§2 complete, and the next push to `main` fans out. While no org TOKEN carries a value
(and nothing malformed carries one either — §8's RED-first lane), runs skip green with
the §4 warning — designed, not an incident.
The sweep is SHA-agnostic (it syncs current git state), so any pre-existing OutOfSync
drift lands with that first fan-out — the §6 accept-before-first-push note applies
once.

## 4. Step 2 — the trigger's anatomy (nothing to create)

No webhook to add on any platform and nothing to enable in ArgoCD — the job IS the
mechanism: `sync-fanout`, `needs: [push-gh, build-containers, build-charts]` (the
D59 wait — the fan-out fires only once the mirror push landed AND both called
builders came back green), guarded `if: contains(vars.ROLE, 'prod')`
(unset `ROLE` or a dev-role instance fire nothing — fail-safe-narrow, the file-wide
convention). Its four steps: `diag`, a bare `actions/checkout@v7`, the filter step
`resolve fan-out pairs`, and the fan-out step `fan out ArgoCD syncs`. Only the
filter step's OWN env receives the delivered merged maps as blobs — `VARS_JSON:
${{ toJSON(vars) }}` and `SECRETS_JSON: ${{ toJSON(secrets) }}` — while the fan-out
step's env carries the pairs file PATH plus the refs: the checkout-running step's
process never sees the maps (RESEARCH Agenda 4). The filter is a dumb serializer:
it selects every delivered key matching `^ARGOCD_SYNC_(.+)_(URL|TOKEN)$` from both
maps (union; the secrets side wins a same-name collision), writes the flat
`{NAME: value}` JSON to `$RUNNER_TEMP/pairs.json` (mode 0600 — the filter's duty;
`RUNNER_TEMP` is per-job ephemeral [40][51]), and prints only
`filter: <N> keys selected` — nothing else. The fan-out step hands the script that
path via `ARGOCD_PAIRS_FILE`, and the script validates the delivered map with the
SAME pair law it applies to the environment locally (§2) — one validator, two
channels, zero divergence; an empty `{}` file is the all-absent result, not an
error, and the file channel wins over the env scan entirely when set. The values
never reach the run body (an interpolation would land in the step script file the
runner writes) and never reach argv. There is no shell `-z` guard: **the script owns
both lanes** (single source of truth, DECISIONS micro-call e).

Unconfigured lane — while no `*_TOKEN` carries a value and no malformed key name
carries one (the §8 RED-first corner takes precedence), every run prints
this line at column 0 (human-executed observation, the job's own stdout):

```text
::warning::sync-fanout not configured (no ARGOCD_SYNC_*_TOKEN keys with values) — fan-out skipped, manual sync or the next push covers it
```

and exits green: zero sockets opened, no table, no summary. The ref comes from the
fallback chain `EVT_REF → GH_REF → refs/heads/main` (dispatch/first-push), and the
call `python3 scripts/argocd-fanout.py --config scripts/argocd-fanout.json --ref "$REF"`
is deliberately UN-guarded under `set -euo pipefail` — a RED `sync-fanout` job means a
pair-integrity or globals problem (§8) naming the category or raw key: fix the org
pair or the five-globals file. Two honest lanes, per ruling: **config/setup errors go
RED** (a typo'd org key name must not silently lose a cluster every push forever),
**per-target runtime failures stay soft** inside the audit contract (job green, §5).
The mirror itself is unaffected either way: the push jobs complete before the
fan-out runs.

## 5. Step 3 — smoke (human)

- **(a) Dispatch smoke = the live validation** (owner-ruled no-probe adoption,
  STATE `reopen4`, 2026-11-26): on the prod instance run main-sync via
  `workflow_dispatch` (Actions UI → main-sync → Run workflow). The run's shape is
  the whole fan — `push-gh` executes (its push no-ops when GitHub is current), the
  called builders run for the range, and `sync-fanout` starts only once BOTH came
  back green (the D59 ordering — the first dispatch observes it too, so builders
  green are part of the acceptance); the `sync-fanout` log then
  validates, leg by leg, what the skipped engine probes would have: the
  `resolve fan-out pairs` step running green ⇒ `toJSON` of the secrets/vars contexts
  is supported on this fork build ([49][50][53]); its `filter: 22 keys selected`
  line ⇒ the org+repo merge delivered the pair keys complete ([43][44][45][46] —
  22 is the CURRENT vault key count, 11 pairs; re-derive it from the vault, never
  from this doc); the fan-out step finding the file ⇒ `RUNNER_TEMP` persistence
  across run steps ([40][51]); the audit table's names matching the vault rows ⇒
  parse-and-discovery parity end to end; a log value-search finding no raw token
  ⇒ per-value masking survives blob serialization ([40], with §8's escape-free
  charset edge). The log carries one audit line per discovered cluster —
  `target=<name> result=<ok|skipped|failed> root=<root-app> ref=<full-ref> elapsed=<N.N>s detail=<...>` —
  and the roll-up `fan-out summary: targets=11 ok=<n> skipped=<n> failed=<n>`,
  where `targets=11` is the DISCOVERED pair count — the vault's reality, not a repo
  list: if the count disagrees with your mental roster, the vault drifted (§8), and
  the run log IS the fleet inventory. Zero filled TOKEN keys gives the §4 warning
  and no roll-up at all; a pair present-but-blanked while others carry values is an
  aggregated config RED naming it (ruling (j), §8) — but clean vault changes move
  the count WITHOUT any alert: a deleted pair drops silently, a complete stray pair
  joins silently (§8). Loudness is reserved for half-states and malformed key
  names, by ruling. If an ENGINE leg reddens (expression failure, blob short, file
  not found), RESEARCH round 3's source conclusions were wrong for this build — revert the
  branch to `3f330df1a` (the pre-R8 delivery shape: one commit, zero cluster
  impact); the owner accepted that risk with the no-probe ruling, and the runner
  v13 fail-loud doctrine [53] makes such a failure visible, not silent. Two rows are
  EXPECTED FAILED by ruling, not regressions:
  `target=proxy-local result=failed` — structural: the hub route 307s to the SSO
  login even WITH a valid bearer (Keycloak middleware reads cookies, not
  Authorization, `UseAuthHeader: "false"`), and the script's no-follow opener turns
  that into an honest `applications list HTTP 307` — the remedy, if the hub should
  automate too, is the crowdsec-only `git`/`forms` route-exception precedent: a
  separate owner decision outside this ticket (§6 row);
  `target=proxy-backup result=failed` — the OQ9 posture: silent from the runner
  vantage ([P2] TCP timeout), an honest failed audit line every run, the other
  clusters proceed, the job stays green, until the owner's reachability check lands
  its own conclusion.
- **(b) Pre-check legs**: the §2.3 sourced-env recipe, `--check` then `--dry-run`,
  plus the `ARGOCD_PAIRS_FILE` file-channel variant (§2.3b) to exercise the CI
  channel itself — `--dry-run` is the live confirmation (or retirement) of both
  ruled rows above before any real push; all legs must name the same clusters as
  the org pairs.
- **(c) Masking spot-check (hygiene)**: every TOKEN is a native single-line Actions
  secret — the runner masks each secret's value wherever it appears in the log,
  including inside the serialized `toJSON` blobs of the filter step (§4).
  One-time sanity leg: search the rendered run log for the first ~12 characters of
  any one pasted token — expect zero hits. Plain hygiene; the JSON-escape edge and
  the escape-free charset rule live in §8.
- **(d) Real end-to-end**: push a no-op-ish PR to `main` on the prod forge and watch
  the run — `sync-fanout` starts only after `push-gh` finishes AND both builders come
  back green (D59); latency = mirror + builders + fan-out, seconds-to-a-minute for
  the fan-out itself (the old hand-path was ≤3 min per cluster). Watch APP
  status, not just the audit: ArgoCD answers a sync POST before manifest-generation
  failures land asynchronously, so the `home` root logs `ok` while its pre-existing
  drift (§6) keeps the app Unknown — manual sync fails identically there; it is not
  fan-out damage.

## 6. Preflight table (live reads 2026-11-21 + runner-vantage reads 2026-11-23, RESEARCH round 2 [P2])

The route hosts below ARE the values of the §2.2 org vars (`ARGOCD_SYNC_<CAT>_URL`) —
with the endpoint list gone from the repo, this table plus the `--check` output and
the smoke are the route-truth surface ("live-verified, never guessed" doctrine lives
here). One row per fan-out category; targets `backups` and `personal` are
absent (no root Application — values-only dirs, EXPLORE §2). SyncPolicy + OutOfSync
columns are the 2026-11-21 readonly MCP probes: every root gated-off — the kill-switch
documented, not moved.

| cluster | fan-out URL (the org var's value) | root syncPolicy (probe 2026-11-21) | OutOfSync at probe | expected fan-out reading |
|---|---|---|---|---|
| dev | `https://cluster.dev.scifi.farm` | syncOptions only — gated-off | `dev` (root); children Synced | ok — exception host, TLS-verified 401-unauth baseline |
| gpu | `https://cluster.gpu.spencerslab.com` | syncOptions only — gated-off | `gpu-llama-swap` | ok — the runner's OWN cluster: self-restart window, §8 |
| gpu-ai | `https://cluster.gpu-ai.spencerslab.com` | syncOptions only — gated-off | `gpu-ai-llama-swap`, `gpu-ai-radiance`, `gpu-ai-radiance-q27` | ok |
| grow | `https://cluster.grow.spencerslab.com` | syncOptions only — gated-off | `grow-assistant`, `grow-okd` | ok |
| home | `https://cluster.home-lab.spencerslab.com` | syncOptions only — gated-off | `home` (Unknown — pre-existing manifest-generation drift), `home-immich-analyze`, `home-pictaria`, `home-postiz` | ok line, app may stay Unknown (§5d); the other exception host |
| infra | `https://cluster.infra.spencerslab.com` | syncOptions only — gated-off | `infra` (root), `infra-forgejo` | ok |
| media | `https://cluster.media.spencerslab.com` | syncOptions only — gated-off | `media` (root), `media-minuspod`, `media-prowlarr` | ok — probe retry answered 2026-11-21 after scout-time ECONNREFUSED |
| monitoring | `https://cluster.monitoring.spencerslab.com` | syncOptions only — gated-off | `monitoring-grafana` | ok |
| proxy-local | `https://cluster.proxy-local.spencerslab.com` | syncOptions only — gated-off | none (`proxy-local-traefik` compares Unknown — transient) | **expected failed (ruled): the route 307s to the SSO login regardless of bearer** — structural, no-follow opener audits `applications list HTTP 307` (§5a); remedy if wanted = the crowdsec-only `git`/`forms` route exception, a separate owner decision |
| proxy-backup | `https://cluster.proxy-backup.spencerslab.com` | not probed (no readonly MCP) | unknown | **expected failed (OQ9)**: TCP timeout from the runner vantage; honest `failed` audit line every push, never a silent drop, until the owner's vantage check concludes; if truly dead, deleting its org pair IS the whole removal (§7/§8), no PR owed |
| proxy-remote | `https://cluster.proxy-remote.spencerslab.com` | not probed (no readonly MCP) | unknown | ok expected — [P2] TLS-verified through the public edge; the `mcp-bot` mint there is a by-hand leg (UI on that cluster — no MCP to read its syncPolicy from here) |

`infra-seaweedfs` — the known 2026-11-10 drift app
(`.agents/notes/2026-11-10-seaweedfs-incident-findings.md`) — probed **Synced/Healthy**
on 2026-11-21; the incident remediation stuck. The accept-before-first-push habit
applies to every app the OutOfSync column names: the first fan-out sync applies that
accumulated drift exactly like your manual Sync button does today — glance at the
column once, then trust it.

## 7. Rollback

1. **The kill lever is TOKEN-side**: delete (or blank) the eleven org TOKEN secrets in
   the prod instance's ORG Settings → Actions — the lever binds to the TOKEN keys, not
   the vars, because the script's configured predicate is token presence: zero
   non-empty tokens ⇒ every subsequent run prints the §4 warning line and skips green —
   that warning IS the proof-of-off. URL vars may stay populated; no git churn, the
   mirror keeps running, the fleet reverts to manual sync. Do NOT blank a single
   cluster's token and expect a quiet drop: while any other token still carries a
   value the fleet is CONFIGURED, and that category's now-broken pair goes RED naming
   it — partial kills are config errors by ruling (§8), so the lever is
   all-or-nothing.
2. **Decommissioning one cluster (pure discovery, RULED 2026-11-26)**: delete BOTH
   org keys of the cluster — the var and the secret, ORG Settings → Actions — that
   IS the decommission: no JSON line, no PR, no repo edit of any kind; there were
   never key rows to leave behind. The category leaves discovery at the next run —
   silently, the §5 summary count being the only signal (quiet BY DESIGN). The
   interim half-state is loud on purpose: deleting one key leaves a half-pair that
   goes config RED naming the category until the twin follows. Blanking instead of
   deleting keeps the ruling-(j) RED while the fleet is configured; the all-blank
   kill above is the quiet lever, by design.
3. **Git leg (full removal)**: revert the PR — the `sync-fanout` job hunk in
   `.forgejo/workflows/main-sync.yaml` and the two `scripts/argocd-fanout.*` files go
   with it; the pre-ticket main-sync (push jobs only) returns. The org keys become
   inert once the job stops reading them; remove them whenever convenient under §2's
   org hygiene. If an ENGINE claim fails in the field (§5a's validation legs), the
   reopen4 fallback is this same revert — back to `3f330df1a` — one commit, zero
   cluster impact, owner's standing call.

State plainly: nothing else changes anywhere — no residual impact. No cluster-side
cleanup leg exists or ever existed: the reopen1 in-cluster layer was never deployed
(DECISIONS 2026-11-23 R6, never-deployed proof), so there is no
in-cluster component, secret, or route to remove. The syncPolicy posture never moved
(§6 proves it), no prune was ever run (`prune=false` pinned in both query and body of
every sync), and no cluster-secret annotation was ever touched. The fleet is exactly
back at today's manual workflow.

## 8. Limitations

- **Trigger failure lands the push as a no-op at the old revision**: job skipped,
  runner dead, or a target failing mid-sweep — that push simply does not land there.
  No Actions redeliveries exist and the fan-out is stateless (no queue, no replay);
  the next push to main self-heals it (the sweep syncs current git state, whatever
  SHA that is); fallback otherwise = manual sync, as today.
- **Green job ≠ green fleet, by design**: per-target runtime failures audit honestly
  and keep the job green (the mirror must never break over the fan-out); an
  all-failed run (e.g. 11 revoked tokens) still exits 0 — read the `fan-out summary`
  line, not the job chip. The all-SKIPPED shape additionally prints a
  `::warning::` naming the `tracked_repo`-mismatch trap: `tracked_repo` is the one
  global GitHub URL in the five-globals file, and flipping it is only ever valid in
  lockstep with the clusters' app sources ([P §3]) — never drift it alone.
- **Pair-integrity RED is aggregated BY DESIGN**: every violation (missing side,
  non-JWT token, bad URL scheme, `@`/query in a URL — and, per DECISIONS 2026-11-25
  ruling (j) re-read 2026-11-26, a delivered pair whose values BOTH arrive blanked in
  an otherwise configured fleet) names every affected cluster in ONE
  value-free `argocd-fanout config:` line, and the job goes red — partial fleets are
  config errors, never silent drops. The TRUE catch envelope (DECISIONS 2026-11-25,
  i-adj-1, live-probed, re-read for the blob world): a key in pair shape with a
  malformed CATEGORY — double underscore (`ARGOCD_SYNC_GPU__URL`), dots, or a
  lowercase segment (`ARGOCD_SYNC_gpu_URL`) — carrying a value is RED naming the raw
  key; DEGENERATE shapes that never match the pair regex — `ARGOCD_SYNC__TOKEN`, a
  lowercase SIDE-suffix (`ARGOCD_SYNC_GPU_url`) — are ignored by design, value or
  not. The script's scan is defense in depth for both channels; in CI the delivered
  vault map IS the name surface — key NAMES are runtime-meaningful code (an org
  Actions write is fleet config, §8 name discipline), guarded by the
  branch-protection follow-up card `abkP2XsbuuPuuvri6` on `.forgejo/workflows/**`
  (RESEARCH [55]) — the named substitute for the membership check the owner declined
  in code 2026-11-26 — and by the runbook suite, which fails any drift between this
  table's names, the filter's selection regex, and the script's pair law. Do not read
  the scan as catching all typos: it catches the ones that carry values in pair
  shape.
- **Rotation is PER KEY**: re-mint on the cluster → `argocd account delete-token` the
  old JWT → overwrite that ONE org secret row → the next run picks it up (no refresh
  window, nothing restarts). The delete-then-overwrite window can redden exactly one
  push (the pair is momentarily broken) — by design, fix forward.
- **Decommissioning is a vault action**: delete BOTH org keys of the cluster (§7) —
  that IS the decommission, no repo edit ever. A complete pair simply leaves discovery
  — silently, by ruling 2026-11-26: an alarm on clean removals would demand a repo
  edit per retirement, and the owner declined that friction; the §5 summary count is
  the audit. A STRAY complete pair joins the same way, silently — the mirror image —
  which is why an org Actions write is fleet config (name discipline below). The
  half-states stay loud by design: ONE key deleted (either side) is a half-pair —
  aggregated pair-integrity RED naming the category, and pushes stay red until the
  twin follows; a blanked-but-present pair is the ruling-(j) RED (DECISIONS
  2026-11-25, re-read 2026-11-26). Reverse-direction residue cannot exist: nothing
  in the repo lists the fleet.
- **Name discipline**: fleet names are hyphen-only DNS labels — a real cluster name
  with underscores is unrepresentable (it collides with its hyphen twin on one
  delivered key), and dots do not survive the name mapping, so no future cluster may
  be named that way. Names are runtime-meaningful CODE: an org Actions write changes
  which clusters the fan-out drives — org Actions write IS fleet config, guarded by
  this discipline plus the branch-protection follow-up card `abkP2XsbuuPuuvri6`
  (`.forgejo/workflows/**`, RESEARCH [55]) and the org key-name governance it stands
  for; that is the named backstop for the membership check declined in code.
- **Masking edge — keep key values escape-free**: the runner masks each delivered
  value inside the serialized blobs too, but a value containing a JSON-escaped
  character (quote, backslash, control byte) would not match the masker after
  serialization. Fleet values today — JWTs and route hosts — are escape-free
  (`[A-Za-z0-9._~+/-]` shape, RESEARCH [30][31]); any future key value must stay
  that way, and §5's log leg spot-checks the shape live.
- **Blob retired, no back-compat**: the reopen2 single-blob input died with R7 — no
  compatibility shim exists, and its name is ignored by construction (its delete-check
  lives in §2.4).
- **Token TTL is indefinite by ruling (OQ10)** — `argocd account generate-token`
  defaults to no expiry, and that is the answer, not a gap: mcp-bot is apiKey-only and
  cannot self-mint, so an expiry mandate would build an outage treadmill (silent 401s
  in the warn-and-green lane) where a rotation robot does not exist. Revocation:
  `argocd account delete-token --account mcp-bot` identifying the mint kills the JWT
  server-side immediately.
- **Org-wide vault visibility (ruled trade-off)**: an org Actions secret surfaces into
  every repo job in the org (fork-PR jobs excluded, RESEARCH [21][22]); accepted under
  the owner's org key hygiene with this repo the sole consumer — the vault already
  holds the main-push token, so the crown-jewel argument is unchanged. The R8 blobs
  deliver the same merged maps the engine already hands every job regardless of any
  reference ([43][46], RESEARCH Agenda 4: the widening delta of the blob shape is
  ≈0); the real boundary stays PR review, hardened by the carded branch-protection
  lever above.
- **Runner vantage**: the job runs on the gpu cluster's runner (dind containers inherit
  the pod's LAN split-horizon resolver — inferred, not measured: §5's dispatch smoke IS
  the acceptance leg). The fan-out also syncs that hosting cluster, and nothing in the
  design places that target last (targets are discovered alphabetically and run in
  parallel): a gpu root sync touching the runner's own pod manifests can truncate the
  running job — rare, bounded ≈1–3 min at 4 workers, next push self-heals. Accepted
  risk per DECISIONS 2026-11-23 (reopen2 known-risks item 1); the discovered order is
  alphabetical because the pairs file is written sorted, not because anything lists
  it.
- **No prune** (OQ6 ruling): git-removed resources linger until you prune manually;
  every sync is non-force, `prune=false` — a mirror of the conservative manual button,
  not a replacement for the flip that was declined (OQ1).
- **Only allowed refs fire** (OQ7 ruling): refs outside `allowed_refs` print one
  skipped line and open no sockets; per fired ref only apps whose live
  `spec.targetRevision` equals it are synced. **Route URLs stay `https`**: discovery
  accepts `http://` (test-lane shape), but the values are bearer tokens — the org vars
  must carry the scheme-included hosts of §6, never a cleartext URL.
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
  (the network main-sync jobs execute in) — RESEARCH [P2 §1], measurement cells
  unchanged; 10 of 11 targets TLS-verify with no `-k`; proxy-backup is the one silent
  host:

  | target host (org var value) | DNS | TLS (verified, no -k) | API answer | note |
  |---|---|---|---|---|
  | cluster.dev.scifi.farm | 10.0.77.12 | ok | 401 | the §6 exception host, unchanged |
  | cluster.home-lab.spencerslab.com | 10.0.3.78 | ok | 401 | the other exception, unchanged |
  | cluster.gpu.spencerslab.com | 10.0.22.205 | ok | 401 | |
  | cluster.gpu-ai.spencerslab.com | 10.0.99.151 | ok | 401 | |
  | cluster.grow.spencerslab.com | 10.0.3.5 | ok | 401 | |
  | cluster.infra.spencerslab.com | 10.0.77.59 | ok | 401 | |
  | cluster.media.spencerslab.com | 10.0.77.9 | ok | 401 | |
  | cluster.monitoring.spencerslab.com | 10.0.99.129 | ok | 401 | |
  | cluster.proxy-local.spencerslab.com | 10.0.77.54 | ok | 307→200 | redirect lands on the login UI page (unauth); API needs the bearer either way — and the hub's `UseAuthHeader: "false"` middleware makes the 307 structural (§5a/§6) |
  | cluster.proxy-backup.spencerslab.com | 10.0.77.5 | — | **timeout** | TCP 443+80 filtered, ping dead |
  | cluster.proxy-remote.spencerslab.com | 5.78.101.168 | ok | 401 | the public edge serves its argocd route |
