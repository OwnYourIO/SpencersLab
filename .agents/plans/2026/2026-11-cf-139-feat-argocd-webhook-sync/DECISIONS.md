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
