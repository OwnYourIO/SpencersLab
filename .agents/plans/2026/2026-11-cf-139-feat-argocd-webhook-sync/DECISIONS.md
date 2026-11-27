# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Repo validation stands for this ticket: helm lint/template (+ mandatory `helm dependency
  build charts/base` first), grep/file checks; no unit-test suite; secrets-free plan →
  custom-values 1:1 check N/A.
- Cluster-secret annotation flips are human out-of-band actions (cf-11 precedent); this
  repo never kubectl-applies. Runbook commands are marked human-executed.

## Decisions
- 2026-11-12 plan: Scope = RESEARCH's staged shape. Stage 1 (automated-sync enablement via
  audit + hardening + runbook) is the one chunk; the "webhook" title is honored only as
  the optional Stage 2 (webhooks refresh, never sync — RESEARCH [4][10]). Rejected: shape
  A (N public cluster webhooks — mesh-only rule, NXDOMAIN measured), B (GitHub Actions sync
  fan-out — same reachability wall + N write tokens), D (centralize ArgoCD), E
  (argocd-notifications — outbound-only). Why: RESEARCH Agenda 2 verdicts + fleet rules.
- 2026-11-12 plan: Mechanism = human flip of `services.<cat>.selfHeal` per cluster's own
  cluster secret; no new git-side knob. The repo-side default is ALREADY automated-ON (gate
  passes on absent or "true", verified identical in all 11 service appsets + charts appset);
  a git default change could not reach the out-of-band annotations anyway. Rejected:
  managing cluster secrets from git (bootstrap is out-of-band by design; big architecture
  change unrelated to the ask).
- 2026-11-12 plan: Flip form assumed as-is `automated:{prune:true, selfHeal:true}` mirror
  (OQ3); drift-writer protection via ignoreDifferences instead of dropping selfHeal —
  pattern already proven by the system-upgrade Plan /status fix. Alternative
  (automated-without-selfHeal for roots) triggers a re-plan (12 appset template files).
- 2026-11-12 plan: Single chunk C01 — audit results feed the runbook's preflight and the
  conditional values hardening in one reviewable commit. Rejected: audit-only chunk (no
  mergeable deliverable) and doc-only chunk (would need the audit first; artificial
  handoff). Rejected splitting values from docs: same subsystem, same review question
  ("is the flip safe and fully documented?").
- 2026-11-12 plan: EXPLORE's root-vs-child tension (same gate key, children "Synced") is
  recorded as an audit question, not resolved by assumption; C01 reads real child
  syncPolicy. Working hypothesis (explicitly unconfirmed): the service-wide "false" gates
  children too and "Synced" reflects manual syncs — consistent with the card's phrasing.
- 2026-11-12 plan: Stage 2 (public `argocd-hook` relay + in-mesh fan-out + HMAC
  ExternalSecret trio) deliberately NOT chunked — conditional on OQ2; a yes answer relaunches
  planning seeded by RESEARCH Agenda 2 shape C + Agenda 4/5.
- 2026-11-12 plan: `cluster.proxy-local` public-A-record leak = follow-up card candidate
  for coord (OQ4), not a chunk (launch ruling). `infra-seaweedfs` drift = runbook preflight
  pointer to `.agents/notes/2026-11-10-seaweedfs-incident-findings.md`, not a chunk.
- 2026-11-12 plan: No speculative HPA ignoreDifferences — fleet has no HPAs (grep verified);
  audit evidence only.

## Deferred
- Stage 2 relay (OQ2) — replan trigger, fully seeded in RESEARCH.
- GitHub-side webhook creation — user action, only under Stage 2.
- Appset variant drift (dev/gpu/gpu-ai newer copies, older baseChartVersion pins) —
  cosmetic, separate concern.

## Rework 2026-11-17 (batched OQ round answered — plan re-cut around the answers)
- 2026-11-17 human (batched round): **OQ1 — kill-switch KEPT.** The
  `services.<cat>.selfHeal="false"` cluster-secret annotations stay; nothing in this ticket
  flips them or edits the 12 appset templates' gate. Alternatives rejected: the flip
  (old Stage 1), automated-without-selfHeal. Why: owner ruling — root auto-sync remains
  deliberately off.
- 2026-11-17 human (batched round): **OQ2 — Stage 2 IS this run's deliverable**: one
  crowdsec-only `argocd-hook` relay, hosted proxy-local, ONE shared GitHub↔fleet HMAC.
- 2026-11-17 human (batched round): **OQ3 — as-is mirror is the recorded preference for a
  FUTURE flip**: if the owner ever flips a gate, they want
  `automated:{prune:true, selfHeal:true}` (the gate's own default — zero template churn).
  Moot for this plan (flip off-table); recorded here so a future flip run starts informed.
  No appset template edits in this ticket.
- 2026-11-17 human (batched round): **OQ4 — `cluster.proxy-local` public-A-record leak is
  NOTE-ONLY** (this log + runbook appendix): NOT a follow-up card, not fixed here. It does
  not impede this work (relay uses mesh hostnames, never the public record) → no FRICTION
  entry.
- 2026-11-17 plan(rework): Mechanism = relay drives **actual API syncs** (POST
  `…/api/v1/applications/<root>/sync` per cluster, mcp-bot bearer tokens), because with the
  gate kept off a refresh webhook lands nothing (RESEARCH [4][10]) — the card's ask
  ("automatic when pushed to main") is met with the annotations untouched. Old C01 (pre-flip
  drift audit + ignoreDifferences hardening + flip runbook) VOID. Re-evaluated piecewise:
  ignoreDifferences additions DROPPED (they served the flip; the 4 shipped entries +
  non-force syncs cover the relay path and charts/base stays untouched); the flip runbook
  DROPPED; the live-probe audit KEPT only in slimmed form as C03's preflight table (evidence,
  not a gate); k3s-incident history KEPT as the runbook's WHY of never-force.
- 2026-11-17 plan(rework): Relay host VERIFIED proxy-local per EXPLORE/RESEARCH: it owns the
  public-edge hop (RESEARCH Agenda-2 shape C, q6), its hub values already carry the
  crowdsec-only public exceptions (`forms`/`git`/`forgejo`,
  `services/proxy-local/prod/values.yaml:102-131`) and locally-hosted charts (`smtp-relay`
  entry precedent lines 55-59); external-dns publishes the public name from those entries.
  Fan-out rides existing per-cluster `cluster.<name>` argocd-server routes over mesh DNS —
  zero new cluster-side exposure.
- 2026-11-17 plan(rework): Credentials = REUSE the existing `mcp-bot` local account
  (`charts/base/values.yaml:147`, RBAC `applications get,sync */*` lines 157-158, apiKey
  survives `authMode: sso`); mint NEW per-cluster tokens into a dedicated Bitwarden item
  (`argocd-hook-tokens`) rather than reusing the argocd-mcp servers' tokens (rotation
  isolation). Rejected: new `hook-bot` account (would edit charts/base + RBAC — zero-base-
  edit is a rework constraint) and shared-token reuse. HMAC + tokens via ExternalSecret +
  Bitwarden (2 items: `argocd-hook`, `argocd-hook-tokens`); `configs.secret.githubSecret` /
  `$ref` argocd-side indirection NOT used — the relay never forwards to `/api/webhook`, it
  syncs by API, so ArgoCD's own webhook secret is out of scope entirely.
- 2026-11-17 plan(rework): Fan-out is POLICY-AGNOSTIC: sync root, settle, then sync every
  still-OutOfSync app whose source is the tracked repo. This settles EXPLORE's root-vs-child
  tension by design (works whether or not children carry automated) instead of by audit.
- 2026-11-17 plan(rework): Sync semantics = `prune=false`, never force, remote-clusters-
  first / self-last (hub self-sync restarts the relay mid-fan-out), stateless no replay
  queue (missed deliveries = today's manual-sync fallback, logged). Rationale: kill-switch
  posture = conservative mirror of the user's current manual sync; OQ6 asks only if the
  owner wants prune automated.
- 2026-11-17 plan(rework): Chunks re-cut 1→3 (C01 container, C02 chart+trio, C03
  runbook+preflight; waves 1→2→3 serial, interface→consumer→docs-parity). Validation
  posture updated to current repo rules: CI for containers is
  `.forgejo/workflows/containers-build.yaml` (docker-build AC = no-daemon CI-deferred,
  GitHub docker-build.yaml is workflow_dispatch fallback); service-trio rule now LIVE for
  this ticket (chart entry + ApplicationSet values entry + proxy values entry + custom-values
  1:1 for the two new Bitwarden items).
- 2026-11-17 plan(rework): Deferred-status — former "Stage 2 relay" defer is superseded
  (now in-scope, C01–C03); former "GitHub-side webhook creation only under Stage 2" defer is
  promoted to the C03 runbook's step 2 (still human-owned).
- 2026-11-17 human (launch note): STATE.json `kickoff.models` rerouted to
  `openrouter/qwen/qwen3.8-flash` both tiers (gpu-ai proxy down) — recorded, kickoff block
  left as-is; model routing stays card/STATE-driven, no plan change.

## Batch-2 round 2026-11-17 (plan finalized — APPROVED)
- 2026-11-17 human: **PLAN APPROVED** with the re-cut 3-chunk design (C01 relay container →
  C02 chart+trio → C03 runbook; waves 1→2→3) as-is, plus the two deltas below; STATE
  `plan_status` → approved.
- 2026-11-17 human: **OQ5 — "Merge first, fill later".** The branch merges with the
  `OVERRIDE_VIA_CUSTOM_VALUES`/`OVERRIDE_NEEDED` sentinels intact; the owner creates the
  Bitwarden items + mints tokens + fills the two custom-values UUIDs post-merge at
  convenience. The `proxy-local-argocd-hook` crash-loop until fill+re-sync is ACCEPTED as
  designed behavior (visible, non-destructive; runbook C03 §2 states it and recommends
  Step 0 before Step 1 for a clean single-pass bootstrap). Rejected: pre-merge UUID fill.
- 2026-11-17 human: **OQ6 — prune=false CONFIRMED** as ruling: status-quo mirror —
  non-force, no prune on every relay sync; git-removed resources need an occasional manual
  prune by owner choice (kill-switch-conservative posture).
- 2026-11-17 human: **OQ7 — "Wider filter".** Design: the ref accept-list is the
  `allowed_refs` CONFIG LIST in `targets.json` (chart values key `allowedRefs`, shipped
  default `["refs/heads/main"]`), widening = one values PR, no code change; blanket any-ref
  rejected. Grounding of the shipped set (grepped 2026-11-17): every appset git source
  resolves branch revisions via `$targetRevision := (eq $stage "prod") | ternary "main"
  $stage` (service appsets, e.g. `services/infra/prod/templates/appset.yaml:40`) and
  `dig "version" "main"` for repo-sourced children
  (`charts/base/templates/appset-charts.yaml:65`); all live `version:` chart entries carry
  an external `repository:` (helm-index semver — never a branch ref); no
  `services/<cat>/<non-prod>` dir and no origin stage branch exist ⇒ the revisions in use
  are `{main}` plus any future per-cluster `stage` passthrough branch, exactly what a
  config list covers. Second layer (per-target, zero-config): fan-out syncs only apps whose
  live `spec.targetRevision` equals the fired ref — a widened stage push can never
  sync-fire prod clusters.
- 2026-11-17 plan: Rework deltas applied in place — C01 (config-list filter + spec-match
  fan-out + `repo` per-target field + widened behavior tests), C02 (`allowedRefs`/
  `trackedRepo` values keys, targets.json object shape, post-merge sentinel AC/tests), C03
  (post-merge Step 0/1 wording, ref-model + widening doc, smoke test b′ non-matching-ref
  case). Open questions: none remain — all seven (OQ1–OQ7) resolved by ruling; no genuine
  new gap surfaced by the answers.

## Final-review owner reopen 2026-11-21 (rulings R1–R4; evidence = EXPLORE.md
## "Forgejo rework probe (2026-11-21)" [P] + shipped-code reads; plan re-cut APPROVED)
- 2026-11-21 human (reopen, STATE `reopen`): the webhook SOURCE must be Forgejo (canonical
  forge = `git.spencerslab.com`, prod-role infra instance), not GitHub — probe [P] run as
  the reopen's read-only ground truth before re-planning.
- 2026-11-21 human: **R1 — race resolution option (c): NO external webhook.**
  `.forgejo/workflows/main-sync.yaml` gains a final `hook-relay` job (`needs: push-gh`)
  that POSTs the push payload (`ref`, `before`, `after`, `repository.full_name` —
  contract pinned in C04; the relay consumes only `ref`) signed `X-Forgejo-Signature`
  plain-hex HMAC of the raw body, shared secret from the Actions vault. WHY (c): [P §1]
  all 9 reachable clusters' roots AND sampled children still track GitHub
  `https://github.com/OwnYourIO/SpencersLab.git@main` BYTE-EXACT (repoURLs from the
  cluster-secret annotations, no git literal); [P §3] a raw Forgejo push webhook fires
  BEFORE `main-sync` advances GitHub ⇒ every fan-out would resolve the PREVIOUS
  revision — the race is structural, not tunable. Rejected: (a) flipping the 11-cluster
  annotation set to forge sources (+ atomic `trackedRepo` flip — flipping early is the
  silent skipped×11 no-op trap [P §3]) — out-of-band churn beyond this ticket;
  (b) settle/re-verify leg — new relay code + a GitHub read credential. Consequence
  ruled-in as documented limitation: fan-out trigger failure ⇒ that push lands as a
  no-op at the old revision (no Actions redeliveries; the next push self-heals — the
  fan-out is SHA-agnostic; fallback = manual sync).
- 2026-11-21 human: **R2 — the public crowdsec-only Ingress entry STAYS as shipped**
  (owner wants a real webhook path possible later). No git change; C03-fix documents the
  door: the race-free future webhook is the GITHUB repo one (apps track GitHub under
  (c)); a raw Forgejo push webhook must not be created.
- 2026-11-21 human: **R3 — signature dialect: the relay accepts BOTH**
  `X-Hub-Signature-256` (GitHub/`sha256=`-prefixed) and `X-Forgejo-Signature`
  (PLAIN hex, no prefix — verified from Forgejo v17.0 docs in [P §4]; the shipped relay
  401s such deliveries today, so this is sanctioned CODE work). Constant-time verify
  either way, per-header verification over the raw body. Plan-pinned detail: first-present
  header decides the dialect, NO cross-dialect fallback (signature-confusion hygiene);
  the job sends the full Forgejo-webhook header family (`X-GitHub-Event: push` included)
  so the relay's event gate stays untouched — keeps the R2 door honest and C04 minimal.
- 2026-11-21 human: **R4 — secret key rename `github-webhook` → `hook-secret`.** The
  flat `/secrets` file + rendered ExternalSecret key rename together (semantics moved off
  GitHub — the caller is now the Actions job). Ripple pinned across chunks: chart ES
  template + chart README (C02-fix), `main.py` constant/`--check`/help/README + harness
  fixtures (C01-fix), runbook §2 (C03-fix). Bitwarden item CONTENT unchanged (same login
  item, same password field) — no owner re-mint. Parity rule: C01-fix + C02-fix ship in
  the SAME release; a half-landed rename crash-loops the relay at startup (visible
  `ConfigError`, not silent).
- 2026-11-21 plan: contract re-verifications against shipped code before pinning (per the
  reopen brief): `trackedRepo` is matched BYTE-LITERALLY against each app's LIVE
  `spec.source.repoURL` (`main.py:213-215 app_matches`), NOT against the payload's
  `repository` field (relay consumes only `ref`, `main.py:379) ⇒ the roster keeps the
  GitHub URL and stays CORRECT under (c); payload `repository.full_name` is delivery
  identity only, signature-covered, not matched. Event/delivery headers GitHub-compatible
  per [P §4] — unchanged. [P §3]'s "flip `trackedRepo` atomically with annotations" stays
  the standing rule for a future option-(a) migration ticket.
- 2026-11-21 plan: C04 conventions pinned to the file's own doctrine: guard on the
  exact bytes `contains(vars.ROLE, 'prod')` (membership, unset fail-safe-narrow — AGENTS.md
  ROLE convention; dev instance and unset fire nothing, `needs: push-gh` chains the skip),
  destination+credential instance-side (`vars.ARGOCD_HOOK_URL` +
  `secrets.ARGOCD_HOOK_SECRET` — zero URL/secret literals in the file, per its header),
  unset ⇒ `::warning::` + exit 0 (the mirror must never break over the hook — same
  philosophy as the unset-ROLE posture; pinned best guess, reversible one-liner),
  bounded POST retries (`--retry 3 --retry-delay 5 --retry-all-errors --max-time 15`) then
  warn-and-continue. `.forgejo/**` validation = the offline static contract suite
  `tests/services/forgejo-main-sync.sh` (bash+python3/pyyaml; NO actionlint precedent in
  repo — inspected) extended t3/t5 + new t9–t13 incl. `bash -n` of every run block; live
  proof is the human's `workflow_dispatch` smoke (C03-fix §5).
- 2026-11-21 plan: Chunks re-cut with C01–C03 kept DONE-at-review (commits `dae5bc5f4`
  / `0cf6e5338`+`43e69f0b9`+`19cc8f504` / `a3c2c2f15`+`0ccf80196`): NEW wave 4 `C01-fix`
  (S — dialect+rename, the contract everything else consumes); wave 5 `C02-fix` (S — ES
  key rename ripple) ∥ `C04` (S — main-sync hook job + suite extension, `.forgejo/`
  in-scope first time); wave 6 `C03-fix` (S — runbook origin/vault/job/door/smoke/kill-
  switch/limitations). Test session precedes dev: re-pin relay/wiring/runbook suites +
  extend forgejo-main-sync. `plan_status` stays approved — R1–R4 covered the open design
  space; the three pinned micro-calls (unset posture, header family, dispatch fallbacks)
  are implementation judgments, reversible one-liners, NOT new questions.



## Final whole-plan review 2026-11-21 (RESEARCH measurement corrected — C02 fix round)
- 2026-11-21 review(final): **the derived roster host `cluster.<cat>.<domain>` is
  wrong for 2 of 11 targets.** Live reads (readonly route Ingresses in ns
  `default` on each cluster + mesh DNS resolution, 2026-11-21) are ground truth:
  dev's argocd-server route is `cluster.dev.scifi.farm` (dev's own `domain`
  annotation is the fleet's second apex scifi.farm) and home's is
  `cluster.home-lab.spencerslab.com` (home's `clusterName` is `home-lab`); the
  derived forms answer NXDOMAIN. RESEARCH Agenda-2's "cluster.{…} → workspace
  split-horizon 10.x" measurement line is disproved for these two entries;
  EXPLORE §3's display-name warning (`home→home-lab`) was never reconciled with
  the roster, and the C02 round-1 review's "EXPLORE §5 confirms the 11
  cluster.<name> routes" citation was false (§5 contains no such confirmation).
  The frozen research record must not be re-trusted for route hosts — re-verify
  against live Ingresses.
- 2026-11-21 ruling (coord→dev): **fix with values, not code** — chart
  `clusterHosts` map (category → full host, no scheme; defaults exactly
  {dev: cluster.dev.scifi.farm, home: cluster.home-lab.spencerslab.com});
  `templates/configmap-targets.yaml` renders `https://` + (override ||
  derived), keeping the template free of domain literals. No `main.py` change
  (the relay is config-driven); no other category gets an entry. Harness t3
  repinned to the live-verified host set (commit 43e69f0b9); its
  spencerslab.com ban leg strips exactly the two sanctioned hosts, so a third
  baked domain still trips it.

## Owner reopen 2026-11-23 — reopen2 (STATE `reopen2`): VAULT-DIRECT ruling (R5/R6);
## plan re-cut around RESEARCH round 2 ("vault-direct fan-out"); approval gated on the
## OQ8–OQ10 batched round
- 2026-11-23 human (in-session instruction, STATE `reopen2.reason`): secrets belong in
  the Forgejo Actions vault (delimited input); fan-out goes DIRECT to the clusters —
  the proxy-local relay hop is removed. Recorded as R5.
- 2026-11-23 human: **R5 — vault-direct.** No Bitwarden, no ExternalSecrets, no relay
  hop: the main-sync job itself drives each cluster's ArgoCD REST API with per-cluster
  `mcp-bot` bearer tokens from ONE Actions vault secret. Runner-vantage reachability is
  the enabling measurement [P2 §1: 10/11 hosts TLS-verified from the gpu runner's
  network — the very network main-sync jobs execute in; proxy-backup silent].
  proxy-backup shipped per the RESEARCH best-guess posture (listed + warn-and-skip +
  preflight row) PENDING owner OQ9. Rejected (again, with the premise fixed): the old
  shape-B objection died on GitHub-hosted PUBLIC runners + NXDOMAIN mesh hosts;
  self-hosted lab runners change the premise — not a reversal [RESEARCH §Contradictions].
- 2026-11-23 human: **R6 — branch-local disposal.** The relay layer (chart, container,
  proxy-local trio entries incl. the R2 crowdsec-only door, custom-values block, HMAC
  vault pair, both relay suites) is `git rm`'d — [P2] verified NONE of it was ever
  deployed (no Deployment/Ingress on proxy-local, sentinels unfilled), so rollback =
  revert the PR, no cluster-side leg, ever. Fan-out logic lands at
  `scripts/argocd-fanout.py` (stdlib-only, python3 proven on the runner image family),
  invoked via a new `actions/checkout@v7` step — precedent containers-build's
  `scripts/forgejo-container-detect.sh` [RESEARCH §4b]. Rejected logic homes: (a)
  inline 150-line heredoc (bash -n can't lint the python), (c) image-as-job-container
  (daemon never re-pulls a cached tag — manual bump law to keep an image lane only a
  relay would need; `jobs.<id>.container` IS supported [23][24], declined anyway), (d)
  argocd CLI + 11 kubeconfigs (breaks "workflows install no tools at run time", worse
  masking shape, stronger creds).
- 2026-11-23 human (R5 corollary, RESEARCH §3 ruled in the brief): the R2 public door
  DISPOSES WITH the relay — a door serving no backend for a caller that no longer
  exists. A future real webhook would need some in-cluster inbound component (i.e.
  re-incepting a relay); that's a separate ruling, out of this ticket.
- 2026-11-23 plan(reopen2): Vault input contract pinned (OQ8-code-independent): ONE
  secret `secrets.ARGOCD_SYNC_TOKENS` (repo-scoped — best guess pinned, single
  consumer; org scope widens the read surface), records `cat:token`, parser
  DELIMITER-TOLERANT (`[,\s]+` split then first-colon split) so the owner's delimiter
  ruling changes vault style + runbook + masking strength, never code. Newline records
  RECOMMENDED [26: forgejo-runner masks each line of a multi-line secret
  independently; comma/space = one blob, split-token echoes leak] — caveat: [26] read
  via search index (source Anubis-gated), the dispatch smoke's log-cleanliness leg
  verifies it live. Set-equality roster↔tokens enforced BOTH directions, loud
  ConfigError naming categories never values; JWT-shape validation per record (ArgoCD
  tokens are JWTs, no comma/space/newline [30][31]). Rejected: 11 separate vault
  secrets (per-value masking strongest but `${{ secrets[matrix] }}` selection is
  unsupported [21][25] + 11 rows per fleet change), JSON-blob secret ([28] doctrine +
  parser-failure class for zero gain given [26]).
- 2026-11-23 plan(reopen2): Roster = repo-side `scripts/argocd-fanout.json` riding the
  checkout, chart values folded in (`allowed_refs`, `tracked_repo` GitHub byte-exact —
  R1(c) truth, [P §1/§3] skipped×11 trap note and lockstep-flip rule transfer verbatim,
  `settle_seconds` 10, `target_timeout_seconds` 60, `parallel_workers` 4, 11 targets).
  **Full literal URLs from [P2 §1], NOT the derived-host + `clusterHosts`-exception
  indirection**: the script runs outside helm where the injection never happens, and
  the indirection is exactly what produced reopen1's two wrong hosts — the final
  review's route-truth doctrine ("live-verified or nothing") transfers with a suite leg
  pinning all 11 hosts against the [P2] table. `backups`/`personal` stay absent (no
  root app).
- 2026-11-23 plan(reopen2): Exit-posture doctrine REFINED vs the shipped all-warn
  rule (was t12 "no exit 1 anywhere"): unset secret ⇒ warn+exit 0 (not-yet-filled vault
  is a designed state); per-target RUNTIME failure ⇒ audit line + job green (R1
  self-heal); SET-UP error (roster/token mismatch, non-JWT token, malformed roster) ⇒
  script exit 1, job RED — RESEARCH Implications 4 names the typo'd-category
  silent-losing-a-cluster class as the fan-out's one new silent failure; hiding it in
  the warn-and-green lane recreates the skipped×11 trap. A red fan-out job cannot
  break the mirror: push-gh/push-dev already completed and jobs are independent.
  All-skipped run additionally warns (`::warning::`) and exits 0. Reversible one-liner
  if the owner overrules; recorded as a pinned micro-call.
- 2026-11-23 plan(reopen2): Semantics ported 1:1 from the shipped `main.py` (the file's
  final use before C07 deletes it): root-first → settle → re-list → children sweep;
  live `spec.targetRevision` == ref-tail + byte-compare `repoURL == tracked_repo`
  (OQ7 layer 2); `prune=false` in query AND body, never force (OQ6); 409/"already in
  progress" = success; per-target isolation + per-request 60 s timeout; audit-line
  grammar preserved verbatim (operators grep it); `ref_tail`/full-ref asymmetry kept.
  Dropped: HTTP server, HMAC dual-dialect verify, event gate, header family, `local:`
  self-last ordering (the relay no longer restarts itself mid-fan-out — ordering
  cosmetic), targets.json ConfigMap, `--check`'s HMAC round-trip (replaced: `--check`
  offline config parse + `--dry-run` live GETs only, zero POSTs — the smoke +
  proxy-backup preflight legs). NEW: `ThreadPoolExecutor(4)` (RESEARCH Implications 6:
  serial 11 × list/settle against the 30-min job ceiling; timeouts stay 60 s —
  shipped-verified — parallelism is the lever, a 20 s tightening rejected).
- 2026-11-23 plan(reopen2): Job pinned as rename `hook-relay` → `sync-fanout`
  (`needs: [push-gh]` byte-true — R1(c) race resolution SURVIVES untouched; exact
  `contains(vars.ROLE, 'prod')` bytes; `set -euo pipefail` heads; lab labels; diag
  step; one bare `actions/checkout@v7` — no history needed; the python call UN-guarded
  so the exit posture above is real; REF fallback chain `EVT_REF→GH_REF→refs/heads/main`
  per the release.yaml:54 dispatch-precedent). Header-comment block reworded:
  transport sentence flips to direct-per-cluster-API; zero secret VALUES in the file
  stays true (roster hosts are non-secret route truth reviewed in PRs).
- 2026-11-23 plan(reopen2): Known accepted risks (documented, not asked): (1) the
  runner lives on the GPU cluster — a gpu root sync that changes runner-pod manifests
  can truncate the running job (rare, bounded ≈1–3 min by parallelism, next push
  self-heals); (2) dind DNS inheritance is inferred — the dispatch smoke is THE
  acceptance leg; (3) vault multi-line paste behavior in the instance UI unverified
  (owner leg, rides OQ8).
- 2026-11-23 plan(reopen2): Chunks re-cut as reopen2 waves 7–9 (numbering continues —
  reopen1's waves 1–6 stay untouched as done-at-review history, their artifacts now
  explicitly port-source-then-disposal-target): C05 fan-out engine + roster + behavior
  suite (interface-first); C06 job rework + forgejo-main-sync t3/t5/t9–t13 replacement;
  C07 disposals (file-disjoint with C06 → parallel wave 8; gated on C05 landing so the
  port completes before the port source goes); C08 runbook rewrite #3 + `git mv` of the
  runbook to `.agents/notes/2026-11-17-argocd-sync-fanout.md` + suite rename/re-pin
  (`argocd-hook-runbook.sh` → `argocd-fanout-runbook.sh`). Validation law shifts: the
  helm-trio checks are N/A for the disposed chart — replaced by the disposal.sh absence
  asserts + a structural render of `services/proxy-local/prod` without the entry;
  `.forgejo` sweep stays C06's suite duty (chunk separation under the parallel wave).
  Test session owns ALL test-file changes including the two relay-suite deletions and
  the runbook-suite rename (designed-red carriers, kickoff-script.sh precedent).
  `plan_status` → draft: approval of the re-cut waits on ONE batched owner round —
  OQ8 delimiter (newline recommended), OQ9 proxy-backup posture, OQ10 token TTL
  (indefinite + delete-token revoke recommended; mcp-bot is apiKey-only, cannot
  self-mint [R], an expiry treadmill would need admin creds in the same vault — strictly
  worse). None of the three reshapes the chunk table.

## Batched owner round 2026-11-23 — reopen2 re-cut APPROVED (OQ8/OQ9/OQ10 taken;
## vault scope ruled ORG-level — the single deviation from the plan's pinned best guess)
- 2026-11-23 human (batched round, four answers): **OQ8 — delimiter: NEWLINE-delimited
  `cat:token` records** (recommendation taken; per-line masking granularity [26]). The
  tolerant parser stays exactly as pinned (`[,\s]+`) — the ruling lands on vault record
  style + runbook wording only, zero code change; comma/space still parse as
  paste-accident defense, not an advertised style. The [26] live-verification leg
  (smoke-time log-cleanliness spot-check) stays scripted as designed.
- 2026-11-23 human: **OQ9 — proxy-backup: listed + warn-and-skip + preflight row taken**
  (recommendation adopted verbatim). The owner reachability check from a capable vantage
  remains a runbook leg; if the box is truly dead, the fix is follow-up, out of this
  ticket. Per-target isolation contains the honest `failed` audit line meanwhile.
- 2026-11-23 human: **OQ10 — token TTL: indefinite mints + `argocd account delete-token`
  revoke + rotation-by-vault-overwrite taken** (recommendation adopted; expiry without
  an automated rotator converts leak-posture into outage-posture — silent 401s behind
  the warn-and-green lane — and mcp-bot is apiKey-only, cannot self-mint).
- 2026-11-23 human: **Vault scope — ORG-LEVEL — the one deviation from the plan's
  pinned best guess.** `secrets.ARGOCD_SYNC_TOKENS` is created as an ORG Actions secret
  on the prod instance (owner runs org-scoped key hygiene; CuratedForest org at
  git.spencerslab.com), inherited by this repo. The job reference is UNCHANGED —
  `${{ secrets.ARGOCD_SYNC_TOKENS }}` resolves through scope inheritance
  (repo→org→user, repo winning [21][27]) — so the file cannot distinguish scopes;
  the repo must NOT define a key of that name and the workflow header sentence +
  runbook §2/§7 carry the org-placement fact (C06/C08 updated same day). Accepted
  trade-off: every repo job in the org can surface the value [21][22] (fork-PR jobs
  excluded), under the owner's org governance with this repo the sole consumer — the
  store already holds the main-push token, the crown-jewel argument is unchanged.
- 2026-11-23 plan (batched-round follow-up): re-cut finalized in place — plan header +
  Open-questions section flipped to RESOLVED-BY-RULING, `STATE.plan_status → approved`
  (gate note kept as history), C06 pins the org-scope header leg + the exact
  unset-warning wording (`sync-fanout not configured (org-level Actions secret
  ARGOCD_SYNC_TOKENS absent) — fan-out skipped, …`) + the no-var-twin leg, C08 moves the
  create + unset legs to ORG scope and states all three answers as rulings (no
  "pending owner" markers survive), C05/C07 unchanged (delimiter-independent; no scope
  surface). No open questions remain; the unverified facts left are owner smoke legs
  (multi-line paste UI, [26] spot-check, proxy-backup vantage, dind DNS acceptance).

## C05 review rounds 2026-11-23 (round 1 CHANGES_REQUESTED -> round 2 APPROVED; coord rulings)
- 2026-11-23 ruling (coord, M2): the no-follow opener (`_NoRedirect`, both GET-list and
  POST-sync legs) DEVIATES the plan's "api_request ports 1:1" pin, and security +
  truthful-audit override fidelity: urllib would re-send the cluster bearer to any 3xx
  target (proved off-origin egress; live trigger = hub Keycloak 307) and a POST answering
  301/302/303 audited `result=ok` with nothing synced. 3xx now surfaces in the existing
  failed lanes (`applications list HTTP 30x` / `sync HTTP 30x`). The hole was INHERITED
  from main.py — the vault-direct vantage (SSO-fronted routes) is what made it live.
- 2026-11-23 ruling (coord, M1): reversed `token:cat` vault records raise a FOURTH
  value-free config error (`vault record looks reversed (token before category)`); a
  JWT-shaped first field is never echoed; other echoes bounded `cat[:64]`. The pinned
  three config-error messages stay byte-unchanged.
- 2026-11-23 ruling (coord, minors in): all-skipped `::warning::` at column 0 (job-log
  annotation grammar — mid-line it never annotates); `allowed_refs: []` -> ConfigError
  (silent disable contradicts the config-red posture); unknown top-level roster keys ->
  ConfigError (symmetry with per-target extras); tunable finiteness/whole-number guards.
- 2026-11-23 review: OWNER-LEG finding strengthened — `cluster.proxy-local` answers 307
  (Keycloak `userAuth`, `UseAuthHeader: "false"`) where gpu/dev answer 401: the hub's own
  target may STRUCTURALLY refuse the bearer regardless of mint. Post-fix it reads as an
  honest failed line meanwhile; the mint+dispatch smoke answers definitively, likely
  remedy = the crowdsec-only `git`/`forms` route exception precedent (separate owner call,
  out of this ticket if needed). C08 preflight row carries the 307-vs-401 reading.
- 2026-11-24 coord (C07 ownership re-stamp): the two relay suites' physical `git rm` was
  executed by C07, not the test session, as an earlier line implied — the test session's
  commit renamed/re-pinned what survives; a suite whose implementation is disposed cannot
  self-delete, and C07's AC1/AC6 need the tracked absence. Law stands: test session owns
  test CONTENT; the disposal chunk owns test DELETION of disposed surfaces.

## Owner reopen 2026-11-25 — reopen3 (STATE `reopen3`, card comment DM2pP35CGPbCjAWXu):
## vault INPUT redesign (R7); waves 7–9 stand as done history; input-mechanism ONLY
- 2026-11-25 human: **R7 — per-cluster Actions key pairs, env discovery.** The
  single-blob secret is ruled out (too error-prone): org VARS `ARGOCD_SYNC_<CAT>_URL` +
  org SECRETS `ARGOCD_SYNC_<CAT>_TOKEN` (category upper-snake: gpu-ai→GPU_AI,
  proxy-remote→PROXY_REMOTE); `scripts/argocd-fanout.py` builds its endpoint list by
  SCANNING ITS ENVIRONMENT for the `ARGOCD_SYNC_*` pairs — no category list in code or
  JSON. Supersedes OQ8's MECHANICS only (newline `cat:token` records, multi-line paste,
  [26] per-line-masking legs): the fan-out semantics, job shape, disposals and doc spine
  from waves 7–9 stand untouched. This adopts RESEARCH §2 option (2) — strongest masking
  (native per-secret single-line values [21][22]) — accepting its two named costs
  knowingly: static enumeration rows per fleet change, and no dynamic secret indexing
  (`${{ secrets[matrix] }}` unsupported [21][25]), the latter resolved by moving
  discovery into the script's env scan instead of expressions.
- 2026-11-25 human/coord (consequences pinned WITH the ruling, recorded as ruled,
  reversible): (1) **pair integrity** — unset org keys arrive as EMPTY STRINGS (static
  enumeration passes them), so the script's empty-detection is the guard: partial pair or
  empty-string residue ⇒ config RED naming the category, value-free; all-absent ⇒
  designed warn-green skip. (2) **static enumeration** — the workflow env map carries all
  22 lines. (3) **roster shrinks to GLOBALS** — `scripts/argocd-fanout.json` keeps
  allowed_refs/tracked_repo/settle/timeout/workers; `targets[]` DELETES, URLs come from
  env; `tracked_repo` stays the one global GitHub URL ([P §3] lockstep law unchanged),
  allowed_refs unchanged; root_app == category == discovered name becomes a code
  convention. (4) **masking simplifies** — [26] per-line verification leg and the
  multi-line-paste UI leg DROP from the runbook; the comma/newline-tolerant parser and
  the M1 reversed-record arm DIE with the blob (the JWT-shape guard survives on the
  TOKEN side; the value-never-echoed law matters more).
- 2026-11-25 coord (labeled record for the micro-call cited everywhere as (i)): **(i)
  RED-FIRST ordering** — a malformed ARGOCD_SYNC_* key carrying a non-empty value is
  evaluated BEFORE the all-absent kill lane: configured-but-malformed residue must never
  skip green past its only visible trace (a typo'd enumeration row); the kill-lane
  warn-green applies only when NO malformed non-empty residue exists. Origin: the test
  session's spec-gap flag at the wave-10 re-pin, ruled by coord 2026-11-25 (recorded in
  STATE `reopen3.recut`); the script's lane order and behavior t5/t4 arms implement it.
- 2026-11-25 ruling (coord, C11 review MAJOR 1): **(j) double-empty enumeration rows
  RED in a configured fleet — CODE REPAIR (C12), not doc reword.** Landed C09 treats
  an all-empty pair (both sides "", e.g. after an accidental org-key deletion while the
  workflow row survives) as `unattempted` GREEN — visible only via the discovered count.
  That contradicts micro-call (d) ("key-only delete ⇒ residue RED by design") AND the
  asymmetry already ruled elsewhere: one-sided residue (URL set + TOKEN blanked) is
  integrity-RED, and §7's single-cluster kill is deliberately RED. A fleet that IS
  configured (≥1 non-empty TOKEN) must account for EVERY enumerated row: both-empty ⇒
  violation `category <cat> enumerated but both values empty` in the aggregated sorted
  RED. UNCHANGED lanes: zero non-empty tokens anywhere ⇒ kill-lane warn-green (the
  paste-pending state + the whole-fleet §7 lever both survive — the fix only fires when
  OTHER clusters are configured, which is exactly when silence is wrong); empty
  malformed-shape residue still ignored; direction-2 drift (workflow row deleted, org
  keys survive) stays invisible to the script by construction — vault hygiene, doc must
  state that precisely, not "both directions visible".
   EXECUTION RECORD (C12 — no chunks/C12.md: dev AND coord sessions are write-denied on chunks/** since the restarts; folded here): carrier 178b4e020 (t4 (j)-family + t5 boundary arms, oracle /tmp/opencode/cf139-ref4) + repair de3bccf43 (discover_targets body+docstring only, +16/−6, AST-verified; both-empty phrase `category "<cat>" enumerated but both values empty` in the aggregated sorted RED only when ≥1 non-empty *_TOKEN; kill lane untouched in both boundary shapes; ABSENT names are NOT enumerated-empty; direction-2 invisible by construction). behavior 13/13 split-proven, disposal 7/7, forgejo 13/13, self-probes a/b/c, aislop 100/0; chain re-review #3 CLOSED C12 with own 29/29 posture probes + own AST diff; sole finding (§5a mirror clause) fixed same day suite-neutral. PERMISSION DRIFT FLAG: coord-to-chunks grant not in force this session — audit when the permission layer settles.
- 2026-11-25 plan(reopen3): pinned micro-calls (best guesses; none gates; each a
  one-line follow-up): **(a) configured predicate keys on the TOKEN side** — a fleet is
  configured iff ≥1 non-empty `*_TOKEN` exists; forced by the owner's own kill-lever
  statement ("deleting the TOKEN secrets suffices — empty env ⇒ all-absent warn-green"):
  URL-side keying would turn §7's lever into a red-storm. All-absent lane pins the
  column-0 line `::warning::sync-fanout not configured (no ARGOCD_SYNC_*_TOKEN keys with
  values) — fan-out skipped, manual sync or the next push covers it`. **(b) aggregated
  RED** — every pair-integrity violation is COLLECTED and listed (categories sorted) in
  one `argocd-fanout config:` line — first-error-raise would hide half a broken fleet.
  **(c) broad-catch category law** — env names are scanned broadly (`^ARGOCD_SYNC_(.+)_(URL|TOKEN)$`)
  then STRICT-validated; a malformed segment with a NON-EMPTY value (typo'd enumeration
  row) goes RED naming the raw key — silently ignoring it would re-open the exact
  silent-cluster-loss class the whole red posture exists for; empty malformed residue is
  ignored. Category constraint recorded: fleet categories MUST be hyphen-only DNS labels
  (`_` in a real category name is unrepresentable — collides with its hyphen twin on one
  env key, undetectable at scan; dots are unrepresentable in `vars.` expressions).
  **(d) decommission lockstep** — removing a cluster = org pair + its 2 workflow rows in
  the SAME release (a key-only delete leaves residue ⇒ RED by design; both drift
  directions are visible, none silent — the enumeration cost, paid knowingly).
  **(e) shell guard dies** — the job's `-z` unset-guard is DELETED (no 22-way emptiness
  test in YAML); the script owns both lanes, single source of truth. **(f)
  route-truth test duty relocates** — the repo can no longer test-pin the 11 hosts
  (instance-side now): behavior t2's host pins are replaced by the runbook §6 table +
  `--check` pair listing + the dispatch smoke; the "live-verified, never guessed"
  doctrine transfers with them. **(g) enumeration order** alphabetical by category
  (proxy-backup before proxy-local — a deliberate sort-order change vs the old roster
  array), t5 pins it. **(h) no-back-compat** — `ARGOCD_SYNC_TOKENS` is banned file-wide
  (t10 gains the ban) and ignored by construction in the script; runbook §2.4's
  delete-check grows to the moot TRIO (hook pair + the reopen2 blob, which the
  11-23→11-25 window may have had created).
- 2026-11-25 ruling (coord, C09 review minors): **(i-adj-1) catch envelope ACCEPTED AS-IS,
  no widening** — value-carrying degenerate shapes (`ARGOCD_SYNC__TOKEN=x`, lowercase
  side-suffixes) fall outside the pinned regex and stay ignored: in Actions the ONLY
  values reaching the env are the 22 enumerated names, and C10's t11 env-name
  set-equality leg is the primary guard there; the script's broad-catch is defense in
  depth for manual/local runs, and the class it must catch (a typo'd ENUMERATION ROW)
  it does. C11 §8 states the true envelope (valid-shape malformed ⇒ RED; degenerate
  value-carrying shapes ignored by design; repo-side rows are review-guarded). One
  future cluster rule stands from micro-call (c): categories stay hyphen-only DNS
  labels. **(i-adj-2) two-round posture ACCEPTED** — malformed-with-value short-circuits
  the integrity aggregation; violations are never silent, one class surfaces per push,
  fix-forward is the designed loop.
- 2026-11-25 plan(reopen3): Chunks = waves 10–12 (continuing numbering): C09 (M) engine
  input redesign + behavior.sh re-pin; C10 (S) workflow 22-row env map + guard deletion +
  main-sync suite re-pin; C11 (S) runbook rewrite #4 + runbook-suite re-pin executed as a
  SECOND test launch at wave-12 start (its parity greps read the C09/C10 landed files —
  per brief, rides their landing). Test session law holds for the first launch (one
  session, behavior + main-sync re-pins, before wave 10). C05/C06/C08 stay done history
  with reopen3 supersession notes; C07's disposals unaffected; disposal.sh untouched.
  plan_status stays APPROVED — the ruling is complete, no batched round needed.

## Reopen4 research outcome 2026-11-26 (RESEARCH round 3; NOT yet a ruling — owner
## decision pending on the probe-gated adoption)
- 2026-11-26 coord: the reopen3 static-enumeration premise ("Forgejo cannot index
  secrets dynamically" [21][25], micro-call (2) consequence) is SOURCE-REFUTED — the
  Forgejo server hands every task the complete merged org+repo SECRETS and VARS maps
  with no reference scanning; the act-lineage evaluator keeps the secrets context
  first-class with ungated toJSON + working [ ] indexing; production precedent
  (mitosis) runs the dynamic-discovery pattern and locates the real security lever at
  .forgejo/workflows/** branch protection, not the reference syntax. Recommended
  shape: 22 rows to toJSON blobs + inline filter step writing $RUNNER_TEMP/pairs.json
  (about 0 widening delta under no-branches/no-environments), script gains
  ARGOCD_PAIRS_FILE with the env scan kept default. PROBE-GATED: dispatch legs A-E on
  prod 17.3.x / runner-13.2 decide; fallback = keep d81831446 static with a one-line
  record. Queued from this round: the header precedence sentence's vars-half is wrong
  per GetVariablesOfRun (repo wins; moot under the no-repo-twin rule - wording fix
  rides the next workflow pass); org-key typo envelope re-verification rides any C13
  plan round (micro-calls (c)/(i-adj-1) lanes).

## Owner reopen 2026-11-26 — reopen4 (STATE `reopen4`): DYNAMIC discovery (R8),
## probe gate explicitly overridden; plan re-cut, approval gated on ONE owner call (OQ-A)
- 2026-11-26 human (STATE `reopen4.owner_decision`, card comment rWTMRa4opbxwCP6jb):
  **R8 — adopt the dynamic shape WITHOUT running RESEARCH's probe legs A–E.** The
  22-row enumeration must not exist ("the 11 shouldn't be hardcoded into the job —
  detect dynamically and pass in"). Build on the source-refuted premise (delivery is
  unconditional [43][44][46]; `toJSON` ungated, `secrets` first-class, index op works
  [40][41][49][50]); the FIRST dispatch smoke is the de-facto live validation.
  Documented fallback, pinned with the ruling: a red smoke on an ENGINE claim ⇒ the
  probe-never-ran conclusions were wrong ⇒ revert to `d81831446`'s static enumeration
  (one commit, zero cluster impact). RESEARCH's probe-gated recommendation is
  overridden, not ignored — its legs A–D become runbook §5's enumerated
  validate-on-first-run assertions; v13's fail-loud-on-expression-error doctrine
  [53] makes the residual risk visible instead of silent. Branch-protection follow-up
  card `abkP2XsbuuPuuvri6` (mitosis #16 lever [55]) stands OUTSIDE this ticket.
- 2026-11-26 plan(reopen4): design pins (all reversible one-liners; the fan-out core,
  both lane strings, and the owner's vault procedures are byte-untouched): **(a) the
  filter is a dumb serializer** — selection regex + union (secrets-wins) + write +
  chmod 0600 + a count line ONLY; the script owns every integrity/kill/membership
  decision identically for both channels (keeps C09's contract offline-testable — the
  landed `discover_targets(source)` is dict-shaped, the file drops straight in).
  **(b) pairs file = flat `{NAME: value}`** in the SAME `ARGOCD_SYNC_*` namespace
  (deliberate deviation from RESEARCH's `{cat:{url,token}}` phrasing: one validator
  body serves env AND file; a second grammar would fork the laws). **(c) channel =
  env var `ARGOCD_PAIRS_FILE`, not a CLI flag** (argparse surface frozen; env-mapping
  matches the tokens-by-env doctrine; paths aren't secrets so argv would've been legal
  anyway). **(d) precedence: set-and-non-empty ⇒ file wins, env scan skipped entirely**;
  unset/empty ⇒ env scan byte-unchanged (local/manual posture, all existing arms).
  **(e) file errors are config RED naming the PATH** (missing/unreadable/non-JSON/
  non-dict/non-string-values — never values); **an empty `{}` file is not an error** —
  it is the all-absent discovery result ⇒ the SAME `WARN_NOT_CONFIGURED` green lane
  (the string verified still-true in the blob world: "no ARGOCD_SYNC_*_TOKEN keys with
  values" — zero text change anywhere, exactly the owner's §7 lever requirement).
  **(f) mode duty is the filter's** (chmod 0600; RUNNER_TEMP per-job ephemeral [40][51],
  same trust zone as today's step env); the script does not stat. **(g) the
  "enumerated-but-empty" (j)-class dissolves honestly:** blanked keys still arrive as
  `""` in the map ⇒ (j) RED survives; DELETED pairs leave no residue — clean deletes
  need the OQ-A oracle to stay loud (below); half-pairs (one side deleted) were and
  stay RED. **(h) the header's precedence sentence is fixed this round per source**
  (vars: repo > org/user > global [45] — the v17 docs sentence stale [41]; secrets:
  repo > owner [44]; moot under the no-repo-twin rule), and the enumeration/"cannot
  index" sentences retire with the rows.
- 2026-11-26 plan(reopen4): SUPERSEDED records (micro-call chain stays readable):
  R7-consequence-(2)/micro-call (e)'s "static enumeration IS the discovery surface" —
  dies with the rows; (d) decommission lockstep — no rows exist to leave behind, the
  lockstep becomes vault↔list (oracle) or vault-only (none); (g) alphabetical row pins
  — obsolete; (i-adj-1)'s "rows" vocabulary re-reads "delivered keys" (the malformed-
  with-value lane now guards ORG KEY NAMES, making org write-access fleet-meaningful —
  the runbook §8 sentence + the protection card carry it). R7 itself stands for the
  KEY NAMES (upper-snake pairs) and the org placement; only their DELIVERY to the job
  went dynamic.
- 2026-11-26 plan(reopen4): chunks = waves 13–15: C13 (M, w13) workflow fleet-blind +
  main-sync suite re-pin (t13 roster leg RELAXED to parse-only so the six-vs-five
  schema question cannot red wave 13 — schema pin moves to behavior t2); C14 (M, w14)
  script channel + `categories` oracle + behavior re-pin (core byte-lock leg extended);
  C15 (S, w15) runbook rewrite #5 (surgery, not rewrite — §2 owner legs byte-unchanged)
  + second test launch at wave start. **OQ-A (the single real owner call, gates
  approval):** cleanly-deleted pair = silent fleet shrink in the blob world. (a)
  RECOMMENDED — minimal `categories` array in `scripts/argocd-fanout.json` as the
  membership oracle: configured-lane set-equality list↔discovered BOTH directions RED;
  agile on values, PR-gated on names; the JOB stays fleet-blind (the owner's objection
  was the job, not config-in-git); interim windows (vault-ahead-of-PR and reverse)
  loud-RED by design; (b) pure discovery, zero-file fleet ops, accepting count-only
  drift and org-write-equals-fleet-config (protection card weighs more). Pinned best
  guesses either way: oracle enforced on the FILE channel only (manual env exports
  need not mirror the fleet); `filter: N keys selected` print line; secrets-side wins
  collisions; malformed-preemption order preserved.

## OQ-A batched-round answer 2026-11-26 — reopen4 APPROVED (pure discovery; the
## coordinator-recommended categories oracle is DECLINED)
- 2026-11-26 human (batched round): **OQ-A = PURE DISCOVERY (option b) — adopted
  against the recommendation.** No membership list anywhere: the org vault map alone IS
  fleet membership; `scripts/argocd-fanout.json` stays the five globals exactly as
  landed (zero schema churn — the main-sync t13 parse-only split becomes PERMANENT,
  the six-vs-five question dies with the oracle).
- 2026-11-26 human/plan: resulting posture stated precisely (ruled envelope, survives
  in exactly these words): **(1)** one-sided delete (TOKEN gone, URL survives — or the
  reverse) ⇒ half-pair ⇒ config RED naming the category — the existing class,
  untouched; **(2)** BOTH keys deleted ⇒ CLEAN INTENTIONAL DECOMMISSION ⇒ the category
  vanishes, fleet−1, the `fan-out summary: targets=N` count is the ONLY signal — by
  design: making that state RED would demand a repo edit per decommission and the owner
  declined the friction; **(3)** blanked-but-present pair (`""` arrives in the map) ⇒
  still the (j) RED while the fleet is configured (blank-everything stays the §7
  all-absent warn-green lever); **(4)** a stray COMPLETE valid pair JOINS silently —
  the mirror image of (2), same rationale; org Actions write is therefore
  fleet-config, and the weight the oracle would have carried in code shifts to the
  branch-protection follow-up card `abkP2XsbuuPuuvri6` + §8's org-name discipline.
- 2026-11-26 plan: supersession deltas — reopen4 micro-call (g)'s "deletes need the
  oracle to stay loud" re-reads: clean deletes were RULED quiet; the (j) subclass
  survives only for BLANKED pairs (both names present, both empty); half-pair/malformed/
  JWT/URL classes all survive untouched. R7 micro-call (d) stays dead (it died with the
  rows). The malformed-lane script phrase "enumeration keys" stays byte-true (docs
  re-read it as "delivered vault keys"; the script retypes nothing). C14/C15 specs
  updated in place; the test session's pre-wave-13 launch brief must NOT write the
  drafted oracle arms (behavior t9 becomes the ruled-envelope arms per C14's Tests).
  plan_status → APPROVED; waves 13–15 unblocked; no open questions remain.

## Post-rebase adaptation 2026-11-26 (reopen4 wave-15 — main moved under the branch; cf-55 merge)
- 2026-11-26 (rebase, coord): origin/main advanced under cf-139 carrying cf-55's
  evolutions (C11/C14/C15: the called-builders fan from main-sync, the D54
  advance-marker single writer, the D59 owner ruling). The branch was rebased:
  19 commits replayed clean, 2 conflict regions resolved — the `sync-fanout` needs
  list KEPT main's D59 shape (`needs: [push-gh, build-containers, build-charts]` —
  R1 option (c) GROWN: the fan-out fires after push-gh AND both builders green; a
  red builder holds the fleet at the previous revision and the unmoved
  `ci/last-built` marker re-covers the failed range by construction), with the
  cf-139 job shape (blobs + filter + pairs channel) replayed onto it. D59's
  builder-wait is now part of the sync-fanout contract.
- Canonical SHA map (pre-rebase references are dangling duplicates on the new
  line): `d81831446`→`3f330df1a` (reopen3 close = the pre-R8 fallback shape the
  runbook's §5a/§7 revert leg now names), `6ed762140`/`de3bccf43`→`0d1ba90eb`
  (C12), `ad86dd576`→`c95cbaabf` (C13+C14), `a10a956c8`→`1767b05e9` (C15 docs),
  plus subject-verified replays `a65d60e05`→`b828bd725` (reopen4 owner stamp).
  The runbook fallback hashes and the plan's stale `needs: [push-gh]`/SHA
  sentences were re-pointed in this round; the runbook-suite baselines are
  re-pointed by the test session (same map, in parallel — suites are their
  authority, not this note).
- Byte-locked strings verified UNCHANGED through the replay: the script's
  `WARN_NOT_CONFIGURED`, the `pairs: %d targets discovered` /
  `filter: %d keys selected` lines, the invocation line, and the five-globals
  roster — the runbook's byte-parity quotes stay true against the landed files.

## Rebase round 2 2026-11-27 (fold-forward + content-lock convention — C13 adaptation)
- 2026-11-27 dev (coord brief): cf-56 C04's D4 ref-context convention folded into the final
  fleet-blind sync-fanout job — the fan-out step env now reads `EVT_REF:
  ${{ forgejo.event.ref }}` with `GH_REF: ${{ github.ref }}` carrying the builder
  family's compat comment VERBATIM (landed pattern evidence: main's pre-rebase
  sync-fanout cut at commit 86b3682c2, main-sync.yaml lines 207-212; the
  fleet-proven `forgejo.event.*` sub-context otherwise at build-charts.yaml:95
  and build-containers.yaml:181-183). The run block's precedent citation now
  points at the post-rebase build-charts.yaml:96 (same env-block lines the
  main-side cut cited). Semantics unchanged: REF chain bytes, invocation bytes,
  `needs: [push-gh, build-containers, build-charts]` STAYS — excluding
  push-coder-templates from the gate is an owner decision, header-documented.
- 2026-11-27 convention (owner-ruled via the same brief): runbook fallback
  citations adopt the CONTENT-LOCK convention — a revert target is named by its
  commit SUBJECT plus a structural anchor ("the last commit before
  "plans(cf-139): reopen4 re-cut (R8)" on this branch"), and a raw SHA may only
  appear as an annotated "at time of writing" aside, never as the identity.
  Driver: the 2026-11-26 FRICTION dangling-merged-history hazard — rebases
  rewrite hashes (d81831446→3f330df1a did exactly that), and the owner reaches
  for these sentences precisely when history has just moved.

## Deploy incident 2026-11-27 (advance-marker bad-substitution — engine fact + consumer law)
- 2026-11-27 engine fact (owner-reported failure, resolved on the fork's act
  engine): an UNRESOLVED called-workflow output reaches a consumer step's
  rendered script as the literal expression text — `${{ steps.bump.outputs.sha
  }}` arrived verbatim inside `TARGET=...`, and bash's parameter expansion
  died with "bad substitution" when the bump step (build-charts) had minted
  no sha (a fan with no charts change). Consumer hardening ADOPTED here
  (main-sync advance-marker block): `RAW` is captured in SINGLE quotes (an
  unexpanded `${{` cannot expand or error), and a case sanitizer routes
  empty-or-literal-expression text to the event-sha endpoint (correct per
  D53 when no bump exists) while a RESOLVED non-40-hex value stays loud red
  (exit 1 naming it). Four-way simulated on the extracted block: literal
  expression -> fallback, empty -> fallback, valid hex -> used, garbage ->
  loud red.
- 2026-11-27 producer-side law NOTED, not executed (cf-55/cf-159 territory):
  build-charts.yaml's bump step should emit `sha=` on every path (emit-
  always), which would make the pass-through class impossible at source.
  Out of this ticket's file scope — a follow-up the owner may want; the
  consumer sanitizer stands regardless.
