# PLAN: cf-139 — Pushes to main auto-sync every cluster (no manual `argocd sync`)
feature: 2026/2026-11-cf-139-feat-argocd-webhook-sync
card: AD-139 "Sync ArgoCD with Webhooks" (Y3vPeX4nhtDbsdwCg)

## Goal

Make a push to main land automatically on every cluster with zero new public network
surface, by making the root Application auto-sync path safe, audited and documented — the
actual blocker is the `services.<cat>.selfHeal="false"` cluster-secret annotations gating
`syncPolicy.automated` OFF on every root app, not the absence of a webhook (webhooks only
refresh, they never sync — RESEARCH [4][10]). The repo-side deliverable is one chunk: a
live pre-flip drift audit + `ignoreDifferences` hardening as it dictates + a human-facing
flip runbook; the annotation flip itself is a per-cluster human action (cf-11 precedent).

## Context — verified facts (this planning run, 2026-11-12)

- Root cause **[E §2 + repo grep]**: both ApplicationSets gate `automated: {prune, selfHeal}`
  on the cluster-secret annotation `services.<cat>.selfHeal` — service appset
  `services/<cat>/prod/templates/appset.yaml` (identical gate line in all 11 category
  templates, grepped 2026-11-12; e.g. infra:126) and charts appset
  `charts/base/templates/appset-charts.yaml:132-138` (adds per-app override
  `services.<cat>.<app>.selfHeal`). Gate semantics: automated renders **only when the
  annotation is absent or exactly `"true"`** — deleting it also turns automated ON.
- Live: root apps `infra`,`dev`,`gpu`,`home` render syncOptions-only and sit OutOfSync
  **[E §2 table]** ⇒ each cluster's own cluster secret carries the `"false"` annotation
  (secret itself unreadable via readonly MCP — RBAC).
- Open tension for the audit: EXPLORE inferred children have automated while the SAME
  service-wide key gates them — possibly mis-inferred from "Synced" status; if the
  annotation gates the whole fleet, "Synced" children just reflect the user's manual syncs
  (matches the card's phrasing). C01 reads real child specs; the plan assumes neither.
- Webhooks: ArgoCD `/api/webhook` = refresh only (source-proven, RESEARCH [10]);
  `cluster.<name>.spencerslab.com` is mesh-only (public NXDOMAIN, measured) ⇒ direct
  GitHub→cluster hooks are physically impossible without new exposure **[R §Agenda 2]**.
  Per-push latency after the flip: poll 120s + 60s jitter ≈ ≤3 min [R 5,11].
- Why the flip may have been deliberate: the root app's tree **contains ArgoCD itself**,
  and `charts/base/values.yaml:135-142` records a *fired* incident (2026-10-20) where
  automated selfHeal re-applied system-upgrade-controller Plans on `/status` drift and
  SIGTERM'd k3s. The fix (Plan `/status` ignoreDifferences) shipped; the flip-back is safe
  *if* the audit finds no other live-drift writers — that is exactly C01's job.
- Fleet shape: every cluster runs its own ArgoCD and manages only itself **[E §3]** ⇒ the
  flip is per-cluster × 11 categories (`backups`,`personal` have no root app).
- No HPAs anywhere in the repo (grep autoscaling/HPA 2026-11-12: only disabled subchart
  values) — HPA-replica ignoreDifferences is NOT needed unless the live audit surprises.
- Existing ignoreDifferences in `charts/base/values.yaml`: apps_Deployment,
  apps_StatefulSet, apps_DaemonSet, upgrade.cattle.io_Plan (4 rendered keys, verified).

## Scope decision (staged, per RESEARCH TL;DR)

- **Stage 0 — gate question (user, OQ1 below):** why was the annotation set `"false"`, and
  is the flip sanctioned? Best guess: deliberate kill-switch around the 2026-10-20 k3s
  incident / bootstrap-era caution; the card's ask sanctions reversing it. If the answer is
  "no, roots must never auto-sync", this plan is re-worked (webhook = refresh-only status
  visibility + per-appset opt-ins) — plan stays `draft` until the batched answer lands.
- **Stage 1 — this plan (chunk C01):** pre-flip drift audit + `ignoreDifferences`
  hardening as dictated + human flip runbook → pushes land automatically in ≤~3 min via
  polling, zero new network surface, nothing else in git changes.
- **Stage 2 — NOT chunked (OQ2):** seconds-level relay (one crowdsec-only
  `argocd-hook.<domain>` edge verifying the GitHub push-hook HMAC once, fanning out
  in-mesh to each cluster's existing `argocd-server /api/webhook`; secret via
  ExternalSecret+Bitwarden `configs.secret.extra` `$ref` indirection). Only if the user
  wants sub-poll latency → follow-up replan seeded by RESEARCH Agenda 2 shape C + 4/5.

## Out of scope

- `cluster.proxy-local` public-A-record (10.0.77.54) DNS leak — **follow-up card candidate**
  for coord (own bug card; launch ruling).
- Creating GitHub webhooks / flipping cluster-secret annotations — human actions (the
  runbook scripts them; repo never `kubectl apply`s).
- Fixing `infra-seaweedfs` OutOfSync drift (its own incident runbook:
  `.agents/notes/2026-11-10-seaweedfs-incident-findings.md`) — C01 only pre-flips it into
  the runbook's preflight checklist.
- Appset variant drift (dev/gpu/gpu-ai newer-copy + older `baseChartVersion` pins **[E §2]**)
  — cosmetic, unrelated to the gate.
- Poll-interval (`timeout.reconciliation`) tuning; ApplicationSet webhook (matrix
  generators don't need it [R 6]); argocd-notifications; any public exposure.

## Commands (validated 2026-11-12 on this branch)

- `export PATH=$HOME/.local/bin:$PATH` (helm lives in `~/.local/bin`)
- `helm dependency build charts/base` — **mandatory before template**: without the vendored
  deps, `helm template charts/base` renders ZERO argo-cd objects (verified: 0 hits for
  `resource.customizations.*`). Tarballs under `charts/base/charts/` are gitignored.
- `helm lint charts/base` → expect `0 chart(s) failed` (the missing-deps WARNING disappears
  after the dependency build).
- `helm template charts/base` → expect: `grep -c 'resource.customizations.ignoreDifferences'`
  ≥ 4 (existing keys intact + any C01 additions), `grep -c OVERRIDE_` = 0.
- Grep trio (chart + ApplicationSet + proxy entries): **N/A** — no service added, no wiring
  change. custom-values 1:1 placeholder check: **N/A** — no secrets added by this plan
  (Stage 2 would need the `argocd-webhook` Bitwarden item + ExternalSecret trio).
- No unit-test suite (repo standard: "tests" = the validations above + file/section greps).

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Pre-flip drift audit + `ignoreDifferences` hardening as dictated + root-autosync runbook | M | 1 | [] | — (single chunk; audit feeds the runbook + conditional values hardening in one commit) |

## Wave order

1. C01 (alone).

## Human-owned list (never agent-executed)

Plan approval after the batched question round · per-cluster cluster-secret annotation flip
(runbook §5, kubectl/UI, admin) · first post-flip push verification on real clusters ·
PR open/merge · card Review→Finished. Deployment stage unchecked: commits stay local.

## Risks / assumptions

- **Self-managing root**: a selfHealing root can apply changes to its own controlling
  ArgoCD mid-sync (RESEARCH blind-spot; the 2026-10-20 k3s SIGTERM is the precedent).
  Mitigation: existing + audit-dictated ignoreDifferences, runbook callout, staged rollout
  (one pilot cluster first — runbook prescribes it).
- **First sync after flip cascades** stale drift (e.g. `infra-seaweedfs` + the 4
  long-OutOfSync roots). Mitigation: audit preflight lists every OutOfSync resource the
  human must consciously accept or fix before flipping that cluster.
- **Audit coverage gaps**: no `readonly` MCP servers for proxy-remote/proxy-backup; media's
  endpoint was ECONNREFUSED at scout time **[E §5]**. Runbook manual-preflight rows cover them.
- **prune=true rides the same gate** — a bad git removal could prune cluster-wide from a
  root; same exposure children already run, but consequences differ at a root. Runbook
  states it; allow-empty exists upstream [R 5].
- Chart 10.11.6 (ArgoCD v3.5.6) key shapes verified there only; renovate bumps re-verify
  (matters for Stage 2, not for C01's plain argocd-cm keys).
- If OQ3 is answered "automated-without-selfHeal", this plan is re-worked (gate edits across
  12 appset template files + variant drift) — deliberately NOT pre-chunked.

## Open questions (accumulated — none asked yet; they go in ONE batched round)

1. **OQ1 (stage-0 gate) — Why is `services.<cat>.selfHeal="false"` on every cluster's
   cluster secret, and is flipping it to `"true"` sanctioned?** Best guess taken: it was a
   deliberate kill-switch (2026-10-20 k3s selfHeal/SIGTERM incident and/or bootstrap-era
   manual caution), its cause is already fixed in git, and the card sanctions reversal.
   Impact if wrong ("roots must never auto-sync"): C01's runbook becomes a refresh-only
   design (webhook = status visibility), Stage 1 re-plans entirely; plan stays draft.
2. **OQ2 — Is ≤~3-min poll-based landing acceptable as "automatic", or is seconds-level
   wanted (Stage 2 relay: one public `argocd-hook` edge + in-mesh fan-out)?** Sub-questions
   if yes: host the relay on proxy-local (best guess, it owns the public-edge hop) and one
   shared GitHub↔fleet HMAC (best guess; per-cluster via relay re-sign only if it lands
   cleanly). Best guess taken: poll-only satisfies the card; Stage 2 deferred → a follow-up
   replan (chunked then). Impact: one optional relay project added/not-added.
3. **OQ3 — Flip form: full `automated:{prune:true, selfHeal:true}` (mirrors the gate;
   manual live edits on root-owned resources get reverted), or automated-without-selfHeal
   for roots?** Best guess taken: as-is mirror (zero git churn on 12 appset templates;
   drift-writer protection instead via ignoreDifferences, the pattern already proven by the
   Plan `/status` fix). Impact if wrong: appset templatePatch changes ×12 categories +
   variant reconciliation → re-plan.
4. **OQ4 — `cluster.proxy-local` publishes a public A record to 10.0.77.54, violating the
   mesh-only rule — file as its own follow-up bug card (recommended)?** Best guess taken:
   yes, separate card (out of this ticket per launch ruling). Impact: coord creates (or
   skips) the Inbox follow-up card.
