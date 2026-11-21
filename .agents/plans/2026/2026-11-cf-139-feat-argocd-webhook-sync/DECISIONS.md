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
