# PLAN: cf-139 — Pushes to main auto-sync every cluster (no manual `argocd sync`)
feature: 2026/2026-11-cf-139-feat-argocd-webhook-sync
card: AD-139 "Sync ArgoCD with Webhooks" (Y3vPeX4nhtDbsdwCg)
status: REOPENED 2026-11-21 at Final Review (owner ruling, STATE `reopen`), re-cut
APPROVED same day — rulings R1–R4 folded in, no new open questions. C01–C03 stay
DONE-AT-REVIEW with their commits; the delta is one new chunk (C04) + three fix rounds
(C01-fix, C02-fix, C03-fix) behind a test re-pin session.
Earlier history: APPROVED 2026-11-17 batch-2 (OQ5 merge-first, OQ6 prune=false, OQ7
config-list filter) atop the OQ1–OQ4 rework (kill-switch KEPT, relay IN scope on
proxy-local with one shared HMAC; flip-shape recorded for a future flip; DNS leak
note-only).

## Goal

Make a push to `main` land on every cluster automatically, without touching the
`services.<cat>.selfHeal="false"` kill-switch annotations or any appset gate. The trigger
is the canonical Forgejo repo's own CI: `.forgejo/workflows/main-sync.yaml` gains a final
`hook-relay` job (after `push-gh` has advanced GitHub) that POSTs a signed push payload to
the `argocd-hook` relay; the relay (hosted on the proxy-local hub, one shared HMAC) drives
an ACTUAL SYNC of each cluster's root app and every still-Out-Of-Sync app tracking that
ref, through each cluster's own ArgoCD REST API with the existing `mcp-bot` apiKey RBAC.
The card's manual workflow ("go into each cluster, run argocd sync") is automated; the
automated syncPolicy stays off everywhere.

## Scope decisions — origin, mechanism, race (rulings R1–R3 + OQ1/OQ2)

- **Origin (R1, option (c)) — no external webhook.** A raw Forgejo repo webhook is
  structurally raced: the fleet's app sources track GitHub 9/9, byte-exact, at probe time
  **[P §1]**, and the forge push hook would fire BEFORE `main-sync` has pushed main to
  GitHub — every fan-out sync would resolve the previous revision **[P §3]**. The
  main-sync hook job fires *after* `push-gh` success, so GitHub (what the apps read) has
  already advanced — timing-correct, zero cluster-secret annotation churn. Rejected:
  (a) flipping all 11 clusters' `services.repo`/`values.repo` annotations to forge sources
  (out-of-band human churn + `trackedRepo` atomic-flip trap — flipping while sources are
  still GitHub makes every root ineligible and the fan-out a silent skipped×10 no-op
  **[P §3]**); (b) settle/re-verify leg (new relay code + a GitHub read credential).
  GitHub Actions sync fan-out, N public cluster hooks, centralizing, argocd-notifications
  and refresh-only webhooks stay rejected (RESEARCH Agenda 2 / OQ1).
- **Public edge stays (R2).** The shipped crowdsec-only `argocd-hook` Ingress entry is
  kept. Its meaning shifts from "the path GitHub calls" to "the door stays open": with the
  fleet tracking GitHub (option c), a real GitHub repo webhook fires race-free and works
  against the relay TODAY (the `X-Hub-Signature-256` dialect remains fully supported per
  R3) — the owner declined to close that door. No git change; documentation-only in C03-fix.
- **Mechanism: sync-by-API, not the flip or a refresh webhook** (unchanged): webhooks alone
  only refresh and with the gate kept off a refresh lands nothing; no flip — the 12 appset
  gates, `charts/base` and the annotations stay untouched.
- **Signature dialect (R3):** the relay accepts BOTH `X-Hub-Signature-256` (GitHub/Forgejo
  union-header family, `sha256=` prefixed) and `X-Forgejo-Signature` (PLAIN hex
  HMAC-SHA256, no prefix **[P §4]** — the shipped relay 401s every such delivery today,
  so this is a code change). Constant-time verify either way, over the raw body;
  first-present header wins, NO cross-dialect fallback (signature-confusion hygiene);
  absent both → 401.
- **Secret key rename (R4):** the flat `/secrets/github-webhook` file + rendered
  ExternalSecret key becomes `hook-secret` — the key's semantics moved off GitHub (the
  caller is the Actions job). Ripple: chart ES template, `main.py` constant + help text +
  READMEs, harness greps, runbook §2. Bitwarden item CONTENT is unchanged (same login
  item, same password field) — no owner re-mint.

## Context — verified facts

- **[P] = EXPLORE.md "Forgejo rework probe (2026-11-21)" — the ground truth for this
  re-cut.** Highlights: all 9 reachable clusters' roots AND sampled children carry
  `https://github.com/OwnYourIO/SpencersLab.git` @ `main` byte-exact (incl. `.git`);
  repoURLs come from cluster-secret annotations — zero github literals in appset templates;
  Forgejo signs plain hex, sends the full `X-GitHub-Event`/`X-*-Delivery` header union;
  the push payload `repository` field is NOT matched by the relay — re-verified against
  shipped code (`main.py:213-215` byte-exact `app_matches` vs target.repo; only `ref`
  consumed at `:379`). ⇒ the roster's `trackedRepo` GitHub URL stays CORRECT under (c).
- **main-sync.yaml shape (read 2026-11-21)**: both jobs guard on the exact bytes
  `contains(vars.ROLE, 'prod')` (unset stays fail-safe-skipped); destinations/credentials
  live instance-side (`vars.PUSH_URL_*`, `secrets.PUSH_TOKEN_*`) — "the file carries no
  repo URL and no token". The C04 job follows BOTH conventions verbatim.
  `tests/services/forgejo-main-sync.sh` is the offline static contract suite (bash +
  python3/pyyaml; t3 pins the job SET, t4 bans force spellings, t5 pins instance-side keys
  count/no-URL-literals/reserved-prefix-ban, t6 pins `set -euo pipefail` heads, t7 pins
  lab runner labels, t8 push-dev hygiene) — the repo has NO actionlint precedent; this
  suite is THE validation shape for `.forgejo/**`.
- Kill-switch/gate + non-force rationale, mcp-bot RBAC (`applications get,sync */*`),
  proxy-local hosting, fan-out roster of 11 categories (`backups`/`personal` have no root
  app): unchanged from the shipped plan; final review additionally corrected the roster
  hosts to the live-verified set (dev → `cluster.dev.scifi.farm`, home →
  `cluster.home-lab.spencerslab.com` via chart `clusterHosts`, DECISIONS 2026-11-21) —
  untouched by this re-cut.
- Shipped-relay facts the fix rounds must respect: module docstring/README still frame
  GitHub as the caller (cosmetic rename target); `GITHUB_SECRET_FILE` constant at
  `main.py:30`; header read at `:365`; `--check` HMAC round-trip at `:163-168` (becomes
  dual-dialect); job failure CANNOT reach the fleet by other means — poll detection only
  surfaces OutOfSync (automated off), so the fallback is the manual sync this ticket set
  out to replace (R1 documented limitation, self-heals on the NEXT push since fan-out
  syncs everything OutOfSync-tracking-main regardless of SHA).

## Out of scope (ruling-backed)

- Flipping/editing `services.<cat>.selfHeal` annotations or ANY appset gate; automated
  policies anywhere (OQ1). Edits to `charts/base` (values or templates).
- **Fleet source migration to Forgejo annotations** (option (a) — declined; a future full
  forge-origin migration is its own ticket, and then `trackedRepo` flips in the SAME
  release **[P §3]**).
- Creating the instance-side Actions var/secret, Bitwarden item fill, token mints, GitHub
  webhook (optional door — NOT created in this run) — human legs, runbook-scripted.
- `cluster.proxy-local` public-A-record leak — note-only (OQ4). ArgoCD `/api/webhook`
  refresh fan-out, ApplicationSet webhook, poll-interval tuning, per-cluster exposure.
- Retiring `ownyourio.github.io` chart index or the `upstream` GitHub remote — not
  ref-tracked surfaces, stay (probe q5 answer: (c) keeps the GitHub mirror load-bearing).

## Commands (shipped-legs verified; fix-round legs land with C04/test session)

- `export PATH=$HOME/.local/bin:$PATH` (helm lives in `~/.local/bin`).
- `.forgejo` validation (C04; THE precedent for forge-workflow checks — no actionlint in
  repo): `bash tests/services/forgejo-main-sync.sh` (extended: job-set re-pin + new
  hook-relay legs, incl. `bash -n` of every extracted run block) + the suite's existing
  t4/t5/t6/t7 sweep the new job automatically.
- Relay (C01-fix): `python3 -m py_compile containers/argocd-hook/main.py`;
  `main.py --check` dual-dialect round-trip; `bash tests/containers/argocd-hook-relay.sh`
  (re-pinned: both dialects + `hook-secret` filename); grep `github-webhook` over
  `containers/ charts/argocd-hook/` ⇒ 0 hits. `docker build => no-daemon, CI-deferred`
  (Forgejo `containers-build.yaml` authoritative) — the relay image rebuilds on this change.
- Chart (C02-fix): `helm dependency update charts/argocd-hook && helm lint
  charts/argocd-hook && helm template charts/argocd-hook --set domain=test.example.com
  --set bitwardenIds.argocd-hook-secret=test-uuid --set
  bitwardenIds.argocd-hook-tokens=test-uuid` ⇒ 0 `OVERRIDE_` leakage; ES secretKey
  renders `hook-secret`; `bash tests/services/argocd-hook-wiring.sh` (re-pinned).
- Trio + 1:1 sentinel check (unchanged files, re-run): grep `argocd-hook` in
  `services/proxy-local/prod/values.yaml` (charts entry + subdomain entry), the two UUID
  lines in `custom-values/proxy-local/prod-values.yaml`.
- Regression on base (untouched): `helm dependency build charts/base && helm lint
  charts/base && helm template charts/base` (dep-build first — FRICTION trap; note
  FRICTION 2026-11-21 open: base dep-build currently hard-fails on a pre-existing
  renovate-class lock drift on main — NOT cf-139's; validate via vendored 10.11.6
  tarballs per the recorded resolution).
- Gate-untouched: `git diff --name-only` shows no `services/*/templates/appset.yaml`, no
  `charts/base/**`.
- Runbook (C03-fix): `bash tests/notes/argocd-hook-runbook.sh` (re-pinned: no GitHub-
  webhook-creation legs, Actions-vault legs + both-dialect smoke + unset-var kill-switch
  greps present).
- No unit-test suite; "tests" = the above + `tests/<area>/*.sh` harness files per chunk.

## Chunks

| id | title | size | wave | status | depends_on | why the dependency |
|----|-------|------|------|--------|------------|--------------------|
| C01 | relay container (as shipped) | M | 1 | **DONE-at-review** — `dae5bc5f4` | — | — |
| C02 | chart + proxy-local trio (as shipped) | M | 2 | **DONE-at-review** — `0cf6e5338` + fix `19cc8f504` (harness `43e69f0b9`) | — | — |
| C03 | runbook + preflight (as shipped) | M | 3 | **DONE-at-review** — `a3c2c2f15` + fix `0ccf80196` | — | — |
| C01-fix | relay: dual signature dialect (R3) + `hook-secret` rename (R4), docs reword | S | 4 | pending | [] | sits on shipped C01; everything else consumes its contract |
| C02-fix | chart ES `secretKey` rename ripple + READMEs/values comments | S | 5 | pending | [C01-fix] | rendered key must match the relay filename byte-for-byte IN THE SAME RELEASE (mismatch = startup ConfigError crash-loop, visible) |
| C04 | `main-sync.yaml hook-relay` job: payload + plain-hex HMAC POST + instance-side keys + retry/warn posture, suite extension | S | 5 | pending | [C01-fix] | the job's signature only works once the relay accepts the Forgejo dialect (R3); git-parallel with C02-fix |
| C03-fix | runbook rework: §2 Actions-vault legs, §4 job-origin replacing webhook creation (R2 door documented), §5 both-dialect + dispatch smoke, §7/§8 kill-switch + failure limitations | S | 6 | pending | [C02-fix, C04] | documents the shipped job and final secret names — docs-parity |

Test session precedes all dev rounds: re-pin `tests/containers/argocd-hook-relay.sh`
(dual dialect, `hook-secret` filename, forge-shaped-delivery e2e leg),
`tests/services/argocd-hook-wiring.sh` (secretKey grep),
`tests/notes/argocd-hook-runbook.sh` (post-rework greps); extend
`tests/services/forgejo-main-sync.sh` (t3 job set → `push-gh/push-dev/hook-relay`; new
t9–t13 per C04's Tests).

## Wave order

4. C01-fix → 5. C02-fix ∥ C04 (independent of each other; both consume C01-fix's
contract; the relay-filename vs rendered-key parity closes at wave 5 end) → 6. C03-fix.
Waves 1–3 done; execution continues serially per the pipeline (test session first).

## Relay behavior (updated origin block; rest as shipped)

- **Trigger (R1):** `hook-relay` job in `.forgejo/workflows/main-sync.yaml`, `needs:
  push-gh` (GitHub has advanced), guard the exact `contains(vars.ROLE, 'prod')` bytes
  (dev instance and unset ROLE fire nothing — the file's own fail-safe convention).
  Payload: GitHub-push-shaped `{"ref", "before", "after",
  "repository": {"full_name"}}` built with `python3 -m json.tool`-safe json.dumps from
  env (dispatch/first-push fallbacks: `ref` → `refs/heads/main`, `after` → `github.sha`,
  `full_name` → `${{ github.repository }}`). Headers: `Content-Type: application/json`,
  `X-Forgejo-Signature: <plain hex HMAC of raw body>` (openssl-dgst | awk, no `sha256=`
  prefix), plus the header family a real Forgejo webhook would send (`X-Forgejo-Event:
  push`, `X-GitHub-Event: push`, delivery ids = run id/attempt — the relay reads
  `X-GitHub-Event` unchanged). Destination/credentials instance-side: `vars.ARGOCD_HOOK_URL`
  + `secrets.ARGOCD_HOOK_SECRET` — the workflow file keeps zero URL literals and zero
  secret values. Unset → skip with `::warning::`, exit 0 (mirror unimpeded; R1 limitation).
  POST failure after bounded retries (`--retry 3 --retry-delay 5 --max-time 15
  --retry-all-errors`) → `::warning::`, exit 0 — sync-lands-as-if-no-hook; next push
  self-heals.
- **Public edge (R2):** `https://argocd-hook.spencerslab.com/` crowdsec-only entry stays;
  today it serves `/health`, the future-GitHub-webhook door, and manual signed smokes.
  Whether the Actions job's `ARGOCD_HOOK_URL` is set to the mesh or public name is
  instance-side owner choice, proven by the runbook's dispatch smoke.
- Ref filter (`allowed_refs` list, default `["refs/heads/main"]`), per-app live
  `spec.targetRevision` match, remote-first/self-last ordering, non-force `prune=false`
  in query AND body, 409-as-success, per-target isolation/timeout, 202-before-fan-out,
  stateless-no-replay, OQ5 sentinel lifecycle: ALL UNCHANGED from shipped C01/C02.

## Human-owned list (never agent-executed)

Plan approval (done 2026-11-21 — owner ruled at Final Review) · **NEW: on the prod Forgejo
repo set Actions `vars.ARGOCD_HOOK_URL` (relay URL the runner can reach) +
`secrets.ARGOCD_HOOK_SECRET` = the `argocd-hook` Bitwarden item password** (same shared
HMAC, R2/R4 — one value, two vaults) · Bitwarden items + `mcp-bot` token mints +
custom-values UUID fill (unchanged legs) · first-time bootstrap syncs · smoke (incl. the
`workflow_dispatch` main-sync trigger) and verification merge · optional GitHub repo
webhook — explicitly NOT now (R2 door left open for the owner, uncreated) · PR open/merge
(Deployment stage unchecked: commits stay local) · card Review→Finished.

## Risks / assumptions

- **Rename parity window:** a deploy where C01-fix landed but C02-fix didn't (or vice
  versa) crash-loops the relay at startup (`ConfigError` — filename not found). Waves
  4–5 close it; both merge in the SAME PR before any sync. Accepted, visible, self-evident.
- **Job failure = silent-ish until noticed:** warn-and-continue posture (pinned best
  guess, mirrors the file's unset-ROLE fail-safe philosophy — the mirror must never break
  over the hook). Mitigation: `::warning::` in every run log + runbook tells the owner
  where to look; the next successful push self-heals the fleet.
- **Actions runner reachability of the relay URL is unproven from repo** (instance-side
  var choice) — the dispatch smoke (§5) is the acceptance leg; mesh name expected (same
  mesh the relay itself fans out over).
- Shipped-plan risks stand unchanged: self-mutating hub (self-last), first-sync drift
  application (preflight table), mirror lag adds seconds after `push-gh` (timing-correct,
  not instant), home root's pre-existing manifest-generation drift (runbook §6 row — the
  relay logs `ok` while the app stays Unknown; manual sync fails identically).
- Forgejo Test-Delivery (real-webhook-type) payload/event name remains unverified **[P
  q4]** — moot for (c): the job's own payload/header shape is what we control and pin;
  only a future real Forgejo webhook needs that verification.

## Open questions (batch-3 — all resolved by the owner's four rulings; none remain)

R1–R4 covered the entire open design space (origin, race, edge, dialect, key name). The
three micro-calls this plan pinned as designed behavior (not questions): unset-instance-key
skip-with-warning posture; dispatch payload fallbacks; the job sending the full
Forgejo-webhook header family so the relay's event handling stays untouched. If the owner
disagrees with any, each is a one-line follow-up — none gates execution.

## Rejected alternatives

Everything rejected in waves 1–2 (annotation flip, N public cluster hooks, GitHub Actions
direct sync, centralizing, notifications, refresh-only fan-out, blanket any-ref) PLUS:
option (a) fleet-annotation forge migration, option (b) settle/re-verify GitHub leg, a raw
Forgejo repo webhook on push (the structural race R1 resolves), and closing the public
edge (R2 declined).
