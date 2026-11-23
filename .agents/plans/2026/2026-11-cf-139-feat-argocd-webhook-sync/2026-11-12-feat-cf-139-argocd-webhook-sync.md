# PLAN: cf-139 — Pushes to main auto-sync every cluster (no manual `argocd sync`)
feature: 2026/2026-11-cf-139-feat-argocd-webhook-sync
card: AD-139 "Sync ArgoCD with Webhooks" (Y3vPeX4nhtDbsdwCg)
status: REOPENED² 2026-11-23 (STATE `reopen2`), re-cut in place around the owner's
VAULT-DIRECT rulings R5/R6 + RESEARCH round 2. **APPROVED 2026-11-23 — the batched
round answered OQ8 (newline records: taken), OQ9 (list + warn-and-skip + preflight row:
taken), OQ10 (indefinite + delete-token revoke + vault-overwrite rotation: taken), and
ruled vault scope ORG-LEVEL (the one deviation from the plan's pinned best guess —
`secrets.ARGOCD_SYNC_TOKENS` is an org Actions secret on the prod instance, inherited by
this repo; DECISIONS 2026-11-23).** C01–C04 + the fix rounds stay DONE-at-review
history; their shipped relay form becomes this wave's port source (C05) and disposal
target (C07).
History: APPROVED 2026-11-17 (relay on proxy-local, OQ1–OQ7); re-cut 2026-11-21
reopen1 (rulings R1–R4: trigger = the main-sync job, dual dialect, `hook-secret`).

## Goal

A push to `main` lands on every cluster automatically, driven directly by the canonical
Forgejo repo's own CI: the `.forgejo/workflows/main-sync.yaml` fan-out job (after
`push-gh` has advanced GitHub — R1 option (c) survives untouched) runs
`scripts/argocd-fanout.py`, which POSTs real syncs to **each cluster's own ArgoCD REST
API** over the lab network, authenticating with per-cluster `mcp-bot` tokens held as
**ONE newline-delimited secret in the Forgejo Actions vault**. No relay, no Bitwarden, no
ExternalSecrets, no public door, no HMAC (R5); the shipped-but-never-deployed relay layer
is disposed branch-local (R6). The `services.<cat>.selfHeal="false"` kill-switch
annotations and every appset gate stay untouched (OQ1).

## Scope decisions — R5/R6 + pinned contract

- **Vault-direct (R5):** secrets live in the Forgejo Actions vault, not mounted
  in-cluster; fan-out goes direct from the main-sync job to each cluster's
  `https://cluster.<host>/api/v1/...`. Runner-vantage reachability measured [P2
  RESEARCH §1]: the main-sync jobs execute in the gpu cluster's runner pod (dind → pod
  net → LAN), and **10 of 11 roster hosts answer TLS-verified (LE wildcard chain, no
  `-k`) and API-shaped from exactly there**. `cluster.proxy-backup` (10.0.77.5) is
  SILENT — OQ9 RULED 2026-11-23: it STAYS LISTED with warn-and-skip + a preflight row
  (recommendation taken; the owner reachability check stays a runbook leg). The prior
  round's rejection of "CI syncs clusters"
  (Agenda-2 shape B) died on GitHub-hosted *public* reachability; self-hosted lab
  runners change the premise — this is not a reversal of that finding.
- **Disposal (R6):** relay + chart + container + trio + sentinels + HMAC + public door
  are removed by clean `git rm` — [P2] confirmed NONE of it was ever deployed (no
  `proxy-local-argocd-hook` Deployment/Ingress; custom-values still `OVERRIDE_NEEDED`),
  so there is no cluster-side teardown and rollback = revert the PR, always. The
  R2 "door stays open" ruling is mooted by its premise: with no relay and no external
  caller, the crowdsec-only `argocd-hook` subdomain serves nothing (RESEARCH §3, §5.2).
- **Logic home (R6):** `scripts/argocd-fanout.py`, **stdlib-only** (json/urllib/
  re/threading/concurrent.futures — the `main.py` import set minus http/hmac; pyyaml is
  NOT guaranteed on the job image), invoked from a new `actions/checkout@v7` step in the
  job — precedent: containers-build runs `scripts/forgejo-container-detect.sh` from its
  checkout; python3/curl/openssl are proven on this runner family [P2 RESEARCH §1].
  Rejected: inline 150-line heredoc (a — unlintable), image-as-job-container (c — pins a
  never-re-pulled image to keep a lane only a relay would need), argocd CLI + 11
  kubeconfigs (d — breaks the "workflows install no tools" law + cluster-admin-ish
  blobs).
- **Vault shape (R5, grammar pinned in the fan-out contract below):** ONE secret
  `secrets.ARGOCD_SYNC_TOKENS`, **org-level Actions secret on the prod instance** (OQ-scope
  RULED 2026-11-23 — the owner runs org-scoped key hygiene; inherited by this repo and
  referenced IDENTICALLY as `${{ secrets.ARGOCD_SYNC_TOKENS }}`: scope resolution is
  repo→org→user with repo winning, so nothing in the job changes [21][27]), records
  `cat:token` (ArgoCD tokens are JWTs: base64url+dots, no comma/space/newline
  [30][31]). **OQ8 RULED: newline-delimited records** (per-line masking granularity
  [26: forgejo-runner masks each line of a multi-line secret independently vs one blob
  for a comma/space form]. The **parser stays delimiter-tolerant** (`[,\s]+` split —
  comma and space forms still parse: paste-accident defense, zero cost), so the ruling
  lands on the vault record style + runbook, not the code. The [26] claim was read via a
  search index (direct source unverified) — the smoke's masking spot-check verifies it
  live.
- **Roster (R6 "where do the 11 URLs live" answered):** repo-side
  `scripts/argocd-fanout.json`, riding the checkout — fleet additions stay PR-reviewable,
  Bitwarden leaves the picture. The chart's `clusterHosts`/`targetCategories`/
  `trackedRepo`/`allowedRefs` fold into it as **full literal URLs measured [P2]** (no
  derived-form + exception indirection — that indirection is exactly what produced the
  two wrong hosts reopen1's final review had to fix; the route-truth doctrine —
  "correct against live Ingresses, never guess" — transfers to the file and to a
  suite leg pinning all 11 hosts against the [P2] table).
- **Sync semantics: ported unchanged** from the shipped `main.py`: root-first → settle
  (10 s) → re-list → children sweep; per-app live `spec.targetRevision` match (OQ7
  layer 2) and byte-compare `repoURL == tracked_repo` (a widened stage push can never
  sync-fire prod clusters); `prune=false` in query AND body, never force (OQ6); 409 /
  "already in progress" = success; per-target isolation + 60 s per-request timeout;
  GitHub-shaped payload/event gates and `local:`-self-last ordering DROP (no relay
  process restarts itself any more — ordering is cosmetic). NEW: `ThreadPoolExecutor(4)`
  parallel fan-out (11 serial targets against a 30-min job ceiling; RESEARCH Implications 6).
- **Fail-safe posture (R1 doctrine, refined):** unset/empty secret ⇒ `::warning::` +
  exit 0 (the not-yet-filled vault is a designed state until the owner's paste);
  per-target runtime failure (dead host, timeout, HTTP error) ⇒ audit line + job green —
  next push self-heals, the fan-out is SHA-agnostic; **setup errors** (vault record for a
  category absent from the roster, roster category without a token, non-JWT token,
  malformed roster) ⇒ the script exits non-zero and the job goes RED — the silent-failure
  class RESEARCH Implications 4 names (a typo'd category silently losing a cluster every
  push forever) must NOT ride the warn-and-green lane; the push itself already landed in
  the completed push jobs, so a red fan-out job breaks nothing but hides nothing either.
  A `skipped`×all-targets run additionally emits `::warning::` (trackedRepo-mismatch trap
  [P §3]) and exits 0.

## Context — verified facts (rounds 1–3; [P2] = RESEARCH round-2 probes 2026-11-23)

- [P2 §1] per-target matrix: 10/11 live and TLS-verified from the runner vantage;
  proxy-backup TCP-filtered (reason unknown — no readonly MCP for that cluster);
  proxy-local answers 307→login UI (API needs the bearer either way); dev →
  `cluster.dev.scifi.farm`, home → `cluster.home-lab.spencerslab.com` (the two sanctioned
  exceptions, unchanged). DNS chain: k3s CoreDNS `forward . /etc/resolv.conf` → LAN
  split-horizon answers all 11 forms. **dind container DNS inheritance is inferred, not
  measured — the dispatch smoke is the acceptance leg** (same role it played for the
  relay-URL hop).
- [P §1] all 9 reachable clusters' roots AND sampled children track
  `https://github.com/OwnYourIO/SpencersLab.git` @ `main` byte-exact; repoURLs come from
  cluster-secret annotations; ⇒ `tracked_repo` in the roster JSON stays the GitHub URL.
  [P §3] the raw-push-webhook race is why the job fires `needs: push-gh` — unchanged.
- Shipped code ported as the semantics baseline: `main.py` `ref_tail`, `app_sources`,
  `app_matches` (byte-compare vs the CONFIG repo, never the payload's `repository`),
  `drive_target` (skip-if-root-ineligible, settle, sweep), `sync_application` (query+body
  prune=false, 409-as-success), audit-line format (`target=… result=… root=… ref=…
  elapsed=… detail=…`). The file is deleted by C07 AFTER C05 completes the port — history
  keeps it.
- `main-sync.yaml` conventions the rewritten job keeps verbatim: guard the exact bytes
  `contains(vars.ROLE, 'prod')`; destinations/credentials instance-side — the file
  carries no URL literals and no token values (the roster JSON carries the hosts by
  design: they are non-secret route truth, reviewed in PRs); `set -euo pipefail` run
  heads; lab runner labels; `diag` step echoing ROLE.
- `.forgejo/**` validation = the offline static contract suite
  `tests/services/forgejo-main-sync.sh` (bash + python3/pyyaml; NO actionlint precedent
  in repo — inspected). Its t9–t13 legs pin the shipped hook job and are REPLACED for
  the fan-out shape (t3 job set, t5 key matrix, checkout-flips-"no uses:" leg, HMAC/curl
  bans, invocation tokens, posture, `bash -n` + `py_compile` + roster parse).
- Runner tool inventory [P2 §1][R]: git/jq/python3/yq/docker/node/apt baked in the
  act-based lab image; five shipped workflows prove python3/curl/openssl on this exact
  runner family. The fan-out needs NOTHING beyond stdlib python.
- No unit-test suite; "tests" = the offline `tests/<area>/*.sh` harness convention
  (scripts get their own area: `tests/board-preload-probe/`, `tests/kickoff-branch/`
  precedents) → new area `tests/argocd-fanout/`. `helm` needs
  `export PATH=$HOME/.local/bin:$PATH` (FRICTION).

## Out of scope (ruling-backed)

- ANY in-cluster component of this feature (the reopen2 premise): no chart, no
  container, no Deployment, no Ingress, no ExternalSecret/Bitwarden for the fan-out, no
  targets ConfigMap. Editing `services.<cat>.selfHeal` annotations or ANY appset gate;
  edits to `charts/base` (OQ1 stands).
- Fleet source migration to Forgejo annotations (option (a) — declined; when it happens,
  `tracked_repo` flips in the SAME PR as the annotations [P §3]).
- Re-creating any webhook path: a future real webhook needs SOME in-cluster inbound
  component, i.e. the relay — that is a separate ruling, not this plan (RESEARCH §3
  C-adjacent; R5/R6 read as: owner's direction kills it).
- Token mint mechanics themselves (human, per cluster), the moot vault-key DELETE legs
  (human), `cluster.proxy-local` public-A-record leak (NOTE-ONLY, OQ4), `infra-seaweedfs`
  drift (preflight pointer only).
- Registry hygiene for `pr-*` tags any dev-instance build may have minted for the dead
  `argocd-hook` image (owner-side normal hygiene; runbook note row).

## Commands (validation-first; per-chunk gates close at the chunk, chain-wide first
all-green at C08 review — the reopen1 shape)

- `export PATH=$HOME/.local/bin:$PATH`.
- Fan-out script (C05): `python3 -m py_compile scripts/argocd-fanout.py`;
  `bash tests/argocd-fanout/behavior.sh` (fake localhost ArgoCD transport, offline,
  deterministic); `python3 -c "import json; json.load(open('scripts/argocd-fanout.json'))"`.
- Workflow job (C06): `bash tests/services/forgejo-main-sync.sh` (re-pinned t3/t5/
  t9–t13 incl. `bash -n` of every run block, `py_compile` of the fan-out script and the
  roster-parse leg). THE precedent for forge-workflow checks — no actionlint in repo.
- Disposals (C07): `bash tests/argocd-fanout/disposal.sh` — `[ ! -d charts/argocd-hook ]`
  `[ ! -d containers/argocd-hook ]`; needle sweep over `charts/ containers/ services/
  custom-values/ tests/` ⇒ **0 hits** (fragmented-needle technique so the suite never
  self-matches; ticket tree + `.agents/notes/` out of scope — history and the runbook C08
  renames; `.forgejo/` cleanliness is C06's t10 duty, kept chunk-separated for the
  parallel wave); `helm lint services/proxy-local/prod && helm
  template services/proxy-local/prod` ⇒ renders, no argocd-hook Application; the
  containers-build detect guard line `[ -f containers/$n/Dockerfile ]` present (a deleted
  dir can never re-enter the CI build set — static leg, RESEARCH §5.7).
- **Helm trio checks are N/A for the disposed chart — replaced by the absence asserts
  above** (the chart never published: it is branch-local, so the release.yaml/index
  never saw it; renovate.json has no argocd-hook entry — swept 2026-11-23).
- Runbook (C08): `bash tests/notes/argocd-fanout-runbook.sh` (suite RENAMED from
  `argocd-hook-runbook.sh` together with the runbook `git mv` to
  `.agents/notes/2026-11-17-argocd-sync-fanout.md`; re-pinned: vault legs, 11-paste
  table, dispatch smoke + masking spot-check, unset-secret kill switch, stale-shape bans
  (relay/Bitwarden/webhook-creation), workflow+script+roster parity greps — every token
  the docs quote exists in the landed files).
- Gate-untouched regression (all chunks): `git diff --name-only` shows no
  `services/*/templates/appset.yaml`, no `charts/base/**`, no `renovate.json`.
- `docker build` legs are MOOT (the container is disposed; no container chunk ships).
  `aislop`: `npx aislop ci --changes` clears every touched file at review.

## Chunks (reopen2 table)

| id | title | size | wave | status | depends_on | why the dependency |
|----|-------|------|------|--------|------------|--------------------|
| C01…C04 + fix rounds | relay container / chart+trio / runbook / hook-relay job (reopen1 shipped shape) | — | 1–6 | **done-at-review, superseded-at-reopen2** — artifacts are port source (C05) then disposal target (C07) | — | history, kept untouched |
| C05 | `scripts/argocd-fanout.py` + `scripts/argocd-fanout.json` + `tests/argocd-fanout/behavior.sh` — the fan-out engine, stdlib-only, vault-tokens env contract | M | 7 | pending | [] | interface-first: the job and the docs consume its CLI/exit/audit contract |
| C06 | `main-sync.yaml` job rework (`hook-relay` → `sync-fanout`: checkout + python invocation, one vault secret, HMAC/curl shape dropped) + `forgejo-main-sync.sh` t3/t5/t9–t13 replacement | M | 8 | pending | [C05] | the job calls the script path/flags/env names C05 pins |
| C07 | disposals: `git rm` chart + container, proxy-local trio hunk, custom-values block, relay suites; sweeps + absence verifies | S | 8 | pending | [C05] | only after the port lands is the old logic home safe to delete; file-disjoint with C06 (parallel) |
| C08 | runbook rewrite #3 (vault-direct: 11 token mints + one paste + moot-key deletes + dispatch smoke; zero Bitwarden) + runbook `git mv` to the honest name + suite rename/re-pin | M | 9 | pending | [C06, C07] | docs-parity with the landed job shape, final key names and the final disposal set |

Test session (repo law: agent-test writes every chunk's tests in one session, before any
dev): ADD `tests/argocd-fanout/behavior.sh` + `tests/argocd-fanout/disposal.sh`
(designed-red carriers naming absent artifacts, the kickoff `script.sh` posture);
REPLACE the `hook-relay` legs of `tests/services/forgejo-main-sync.sh` (t3 job set →
`push-gh/push-dev/sync-fanout`; t5 key matrix → `secrets.ARGOCD_SYNC_TOKENS`
exactly-once, `ARGOCD_HOOK_*` rows dropped; t9–t13 → the fan-out contract below); RE-PIN
RENAME+re-pin `tests/notes/argocd-hook-runbook.sh` →
`tests/notes/argocd-fanout-runbook.sh` to the rewrite-#3 contract (designed-red until
C08 lands the renamed runbook); DELETE
`tests/containers/argocd-hook-relay.sh` + `tests/services/argocd-hook-wiring.sh` (the
test-session owns all test-file changes; C07 dev owns the non-test removals and verifies
absence).

## Wave order

7. C05 → 8. C06 ∥ C07 (independent of each other — disjoint file surfaces; both consume
C05: the job its contract, the disposals its completion) → 9. C08. Execution continues
serially per the pipeline (test session first). The batched round is DONE 2026-11-23:
OQ8/OQ9/OQ10 answered exactly as recommended and the vault scope ruled **ORG-level** —
the plan re-cut is APPROVED (DECISIONS 2026-11-23); no open questions remain and none
ever reshaped the chunk table. Only C06 (header sentence + warning wording) and C08
(creation location + rollback leg) carry the org-scope fact; C05 is untouched (the
parser was pinned delimiter-tolerant precisely so the ruling lands on wording, not
code).

## Fan-out contract (pinned; C05 implements, C06 wires, C08 documents)

- CLI: `python3 scripts/argocd-fanout.py [--config PATH] [--ref FULLREF] [--check]
  [--dry-run]`; `--config` default `scripts/argocd-fanout.json`; `--ref` default
  `refs/heads/main` (non-secret, argv-OK). **Tokens come ONLY from the environment
  variable `ARGOCD_SYNC_TOKENS` — never argv, never files.** No positional args.
- Roster JSON schema (all fields required): `allowed_refs` (list of full refs, shipped
  `["refs/heads/main"]`; entries must start `refs/`, `refs/tags/*` rejected — ported
  validation), `tracked_repo` (byte-exact `https://github.com/OwnYourIO/SpencersLab.git`
  — the R1(c) truth, flip only in lockstep with cluster annotations [P §3]),
  `settle_seconds` 10.0, `target_timeout_seconds` 60.0, `parallel_workers` 4,
  `targets`: 11 objects `{name, url, root_app}` with name = category (`dev`, `gpu`,
  `gpu-ai`, `grow`, `home`, `infra`, `media`, `monitoring`, `proxy-local`,
  `proxy-backup`, `proxy-remote`), url = full literal from [P2 §1] (`backups`/`personal`
  have no root app — never in the roster). name charset `[A-Za-z0-9_.-]+` (audit-line
  parser safety, ported).
- Vault parsing: **ruled record style (OQ8): newline-delimited `cat:token` records** —
  the documented, runbook-pasted form; the parser stays tolerant: value stripped, split
  on `[,\s]+` (comma/space inputs still parse — paste-accident defense, not advertised
  style), each record split at the FIRST `:`
  → `cat` + `token`; `cat` must exist in the roster and roster∪tokens must be equal as
  sets (unknown cat ⇒ `argocd-fanout config: record for unknown category "<cat>"`;
  missing token ⇒ `…: roster target "<cat>" has no token`); token must look like a JWT
  (`^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_.-]+$`) else
  `…: token for "<cat>" is not JWT-shaped`. **Messages name categories and fields, never
  values; nothing echoes the token** (suite greps fixture tokens against all output).
- Behavior: `--ref` not in `allowed_refs` ⇒ one log line, no API calls, exit 0.
  Otherwise per target (4 workers): GET `/api/v1/applications` → root-eligibility
  (byte-compare `repoURL == tracked_repo` AND live `targetRevision == ref_tail`, either
  `source` or `sources` shape) → not eligible ⇒ `result=skipped`; else POST
  `/api/v1/applications/<root>/sync?prune=false` body `{"prune":false}` (never force) →
  sleep settle → re-list → sync each non-root app matching repo+revision with live sync
  status ≠ `Synced`. 409 or "already in progress" ⇒ counted as success
  (`root=in-progress`). Any per-target exception ⇒ `result=failed`, other targets
  unaffected.
- Output: per-target audit lines in the shipped grammar
  (`target=<name> result=<ok|skipped|failed> root=<root_app> ref=<full-ref>
  elapsed=<N.N>s detail=<root phase + children count | reason>`), then
  `fan-out summary: targets=11 ok=<n> skipped=<n> failed=<n>`; all-skipped ⇒
  `::warning::` line, exit 0. Exit codes: 0 success (runtime failures logged),
  1 config/setup error (stderr line prefixed `argocd-fanout config:`), 2 usage (argparse).
- Modes: `--check` = parse roster + vault fully, print the table (`--check: OK`,
  categories/URLs/ref-list/tunables — no values), **zero network**; `--dry-run` = live
  GETs only, eligibility + would-sync counts per target, **zero POSTs** (reachability +
  proxy-backup preflight leg for the runbook smoke).
- Job wiring (C06): step env `ARGOCD_SYNC_TOKENS: ${{ secrets.ARGOCD_SYNC_TOKENS }}` —
  the ORG-level secret resolves through scope inheritance (repo→org→user, repo wins
  [21][27]); the reference form is scope-blind, and the repo must NOT carry a
  repo-level key of that name (owner's org hygiene is the single instance),
  `EVT_REF`/`GH_REF`; unset guard ⇒ pinned
  `::warning::sync-fanout not configured (org-level Actions secret ARGOCD_SYNC_TOKENS absent) — fan-out skipped, manual sync or the next push covers it` + exit 0;
  `REF="${EVT_REF:-${GH_REF:-refs/heads/main}}"` fallback chain (dispatch/first-push,
  release.yaml:54 precedent); then `python3 scripts/argocd-fanout.py --config
  scripts/argocd-fanout.json --ref "$REF"` UN-guarded (set -e propagates a config-error
  red; runtime already exits 0 by construction). `needs: [push-gh]`, exact guard bytes,
  `runs-on: ubuntu-24.04`, diag step, exactly one `uses: actions/checkout@v7` (bare —
  the fan-out needs no history).

## Human-owned list (never agent-executed — collapsed vs reopen1)

Plan approval of this re-cut + the batched round (DONE 2026-11-23 — OQ8/OQ9/OQ10 taken,
scope ruled org-level) · **mint 11 `mcp-bot`
API tokens, one per cluster, against the cluster's OWN [P2] route host** (`argocd
account generate-token --account mcp-bot`; the runbook's appendix table moves verbatim) ·
**ONE vault paste: CREATE the org-level Actions secret `ARGOCD_SYNC_TOKENS` in the PROD
instance's forge ORG Settings → Actions** (CuratedForest org at git.spencerslab.com —
NOT repo settings; the repo inherits it, keep it the single instance) **= the 11
newline `cat:token` records** (OQ8 ruled; multi-line paste behavior in the instance UI
is the owner's to confirm at creation — one leg) · **DELETE the moot
pair `vars.ARGOCD_HOOK_URL` + `secrets.ARGOCD_HOOK_SECRET`** (repo-scoped pair, owner
hygiene, runbook
leg) · verify proxy-backup reachability from a vantage that can (posture ruled OQ9; the
check itself stays yours) · smoke =
`workflow_dispatch` of main-sync on the prod instance + check audit lines + masking
spot-check (echo-visibility of one record) · first-time bootstrap syncs · PR open/merge
(Deployment stage unchecked: commits stay local) · card Review→Finished.
**Zero Bitwarden legs, zero webhook-creation legs, zero cluster-secret annotation legs.**

## Risks / assumptions

- **Config-error red is a deliberate posture change** (shipped t12 pinned "no exit 1
  anywhere"). Justification + reversibility pinned in DECISIONS 2026-11-23; if the owner
  prefers always-green, the python call gains `|| echo '::warning::…'` — one line.
- **gpu self-restart window:** the runner lives on the gpu cluster, and the fan-out syncs
  gpu's root too; a gpu root sync that changes runner-pod manifests can truncate the
  running job (the shipped `local:`-last rule existed for the relay's own restart, not
  this one). Accepted: rare (only when the push touched those manifests), parallelism
  keeps the job ≈1–3 min, next push self-heals. Documented, not asked.
- proxy-backup is a listed warn-and-skip target per the ruled posture (OQ9 answered
  2026-11-23); its silent row is an honest `failed` audit line, never a silent drop,
  until the owner's reachability check lands its own conclusion.
- [26] masking evidence (the load-bearing fact behind the ruled newline form) was read
  via a search index — the smoke's masking spot-check verifies it live; a failed
  spot-check flags the delimiter ruling for re-weigh, the ruling stands until evidence
  moves it.
- **Org-scope visibility (ruled trade-off):** an org Actions secret surfaces into every
  repo's job env within the prod instance's org [21][22] (fork-PR jobs excluded);
  accepted under the owner's org-scoped key hygiene with this repo the sole consumer —
  the store already holds the main-push token, the crown-jewel argument is unchanged.
- Runner dind DNS inheritance inferred → dispatch smoke is the acceptance leg (§1).
- Shipped limitations survive: fan-out skipped until the vault is filled (warn-not-break,
  manual sync meanwhile); mirror lag of seconds after push-gh; `home` root's Unknown
  drift (preflight row, `ok` while Unknown); widening = edit `allowed_refs` + merge.

## Open questions — RESOLVED BY RULING 2026-11-23 (batched owner round; re-cut APPROVED)

1. **OQ8 — delimiter: NEWLINE `cat:token` records (recommendation taken).** Per-line
   masking granularity [26] wins over the floated comma/space; the tolerant parser keeps
   comma/space inputs parsing as paste-accident defense only.
2. **OQ9 — proxy-backup: LISTED + warn-and-skip + preflight row (recommendation taken).**
   The owner reachability check from a capable vantage remains a runbook leg; the fix (if
   the box is truly dead) is follow-up, out of this ticket.
3. **OQ10 — token TTL: INDEFINITE mints + `argocd account delete-token` revoke +
   rotation-by-vault-overwrite (recommendation taken).** No expiry treadmill: mcp-bot is
   apiKey-only, cannot self-mint, and expiry without a rotator converts leak-posture into
   outage-posture (silent 401s behind the warn-and-green lane).
4. **Vault scope — ORG-LEVEL (the one deviation from the plan's pinned repo-scoped best
   guess).** `secrets.ARGOCD_SYNC_TOKENS` is created in the prod instance's org Actions
   settings, inherited by the repo; the job reference is IDENTICAL because scope
   resolution is repo→org→user with repo winning [21][27] — enforced only by the header
   sentence + runbook (the repo must not define its own key of that name; owner's org
   hygiene keeps a single instance).

No further open questions. The remaining unverified facts are all smoke-time owner legs
already scripted in the runbook (multi-line paste behavior, [26] spot-check, proxy-backup
vantage check, dind DNS acceptance), not design gaps.

## Rejected alternatives

Everything rejected in prior rounds stands (annotation flip, N public cluster hooks,
GitHub Actions direct sync from public runners — premise change noted, centralizing,
argocd-notifications, refresh-only fan-out, blanket any-ref, settle/re-verify leg, raw
Forgejo push webhook race, R2 door kept *with* a backend). NEW this round: inline heredoc
logic (a), image-as-job-container (c), argocd-CLI+kubeconfigs (d), 11 separate vault
secrets (per-value masking is strongest but 11 rows per fleet change + the
`${{ secrets[matrix] }}` selection wall [21][25]), JSON/YAML blob secret ([28] doctrine +
a parser failure class for zero gain), 20 s tightened timeouts (60 s shipped value +
4 workers already bounds the run at ~1–3 min), keeping `local:`-last ordering (rationale
died with the relay), config errors on the warn-and-green lane (hides a permanent
silent-no-op class). Repo-scoped placement of the tokens secret — the plan's pinned
repo-scope best guess — was superseded by the 2026-11-23 ORG-LEVEL ruling (owner runs
org-scoped key hygiene; org-wide job visibility accepted with that governance, the
`${{ secrets.* }}` reference form unchanged under repo→org→user inheritance [21][27]).
