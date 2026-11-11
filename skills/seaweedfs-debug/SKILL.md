---
name: seaweedfs-debug
description: "Debug the lab's SeaweedFS deployment (weed 4.50) and its consumers. Use this skill whenever a task touches SeaweedFS, the seaweedfs-master / volume / filer / s3 / admin endpoints or charts/seaweedfs, weed shell, weed fix, volume.fsck, volume.check.disk, ec.decode, a volume server, filer-store lookups, EC shards, split-brain divergence, read-only volumes, vacuum skips, NoSuchKey, no entry is found in filer store, retry-loop 404s, CSI/FUSE mounts on seaweedfs, or Loki-on-SeaweedFS index errors — even if the user doesn't name this skill directly."
---

# SeaweedFS debug — triage entry point

Triage knowledge for this lab's SeaweedFS deployment: weed **4.50** (build `ec8f97935`,
chart wrapper `charts/seaweedfs`, ns `default` on the infra cluster) and its consumers —
Loki (whose chunks AND index objects live ON SeaweedFS), CSI/FUSE mounts on the other
clusters, the S3 gateway, the filer. Every fact in this skill and its references was
pinned against the running build on 2026-11-11.

**Version pin → re-verify on bump.** Route existence, flag names and log wording churn
between releases — renovate carries 4.53.0 pending. After ANY chart/image bump, re-check
the claims before trusting them (the probe set in `references/mcp-server-spec.md` §11 is
the re-verify harness).

## Agent-safety posture

- **Agent-runnable:** read-only HTTP probes over the ingress (anonymous as configured —
  an exposure caveat, not a permission: see the Guardrails) and Loki queries via
  `readonly-global-grafana`. `scripts/health-probe.sh` is the full sweep of that surface.
- **Human-paste-only:** every `weed shell` verb, pod exec, and ArgoCD sync — no agent
  tier grants pod exec or ArgoCD writes (AGENTS.md). Command blocks are written to be
  pasted by a human under `references/weed-shell.md` discipline.
- **Lock-first law:** mutation verbs fail unless the SAME piped session holds the
  cluster lock (`lock` → verbs → `unlock`); read-only verbs never lock. Full law and
  stuck-lock recovery: `references/weed-shell.md`.

## Triage workflow

1. **Establish endpoints + version.** One call answers both: admin `/api/admin` (cluster
   totals incl. EC counts) or master `/dir/status` (its `Version` field). Base URLs, what
   each route answers, size/cost: `references/endpoints-and-probes.md`. Sweep first:
   `scripts/health-probe.sh` (PASS/WARN lines, exit 1 only on unreachable).
2. **Classify by error signature.** A log line in hand goes to `references/error-signatures.md`
   first: the row carries meaning, the ONE first probe, and where the procedure lives.
   Do not improvise meanings — several scary lines are designed behavior (kubelet RST
   noise, the EC churn trio, `skipping readonly volume`).
3. **Mechanism deep-dive** for anything the row references: collections / unnamed pool /
   EC arithmetic / read-only trigger sites / vacuum rules in
   `references/collections-and-ec.md`; shell operation (heredoc binding, exit codes,
   `-collection` matcher) in `references/weed-shell.md`.
4. **Repair.** The 2026-11 EC-removal incident sequence has ONE normative home: the dated
   runbook `.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md` (Phases 0–5, paste
   blocks, deploy reality) — this skill never restates it. General repair discipline
   (simulate-first, lock bracket, read-only pre-checks, idempotent verbs):
   `references/weed-shell.md`.
5. **Verify.** Re-probe the HTTP trio (step 1) and measure log rates in FRESH windows —
   `references/loki-recipes.md`; never historical totals spanning the corrupt window.

## What lives in this skill

`references/**` — read the one that matches the task; do not preload all of them.

- `references/error-signatures.md` — grep-able log line → meaning → first probe →
  procedure home. Open FIRST for any error text.
- `references/endpoints-and-probes.md` — live-measured HTTP surface: which URL answers
  what, response sizes/costs, curl shapes, the two routes that do NOT exist, the
  fid→carrier properties probe.
- `references/loki-recipes.md` — LogQL for weed and its consumers: the label reality, the
  structured-metadata `pod` rule, the self-query-noise law, paste-ready rate recipes.
- `references/weed-shell.md` — shell operating discipline: run form, heredoc stdin
  binding, lock-first law, exit-code law, `-collection` matcher law, paste-block
  conventions. Open before writing ANY command block for the human.
- `references/collections-and-ec.md` — mechanism facts repair decisions branch on: the
  unnamed pool + display-alias trap, RS(10,4) math and its floors, the five read-only
  trigger sites, vacuum/husk rules.
- `references/mcp-server-spec.md` — the seaweedfs-mcp build spec (follow-up card's
  pointer: `skills/seaweedfs-debug/references/mcp-server-spec.md`). Read when BUILDING
  on these endpoints rather than triaging; it owns the tool mapping and the
  auth-exposure gate.
- `scripts/health-probe.sh` — read-only triage sweep (liveness, cluster totals, EC
  health, read-only replica count). The step-1 automation.

## Guardrails

- **Never mutate from an agent session.** Docs here teach probes; changes are
  human-paste blocks, lock-wrapped, simulate-first.
- **Never alert on the known-noise lines**: `error writing JSON status` (~1.5–1.7k
  lines/h = steady-state kubelet probe RST) and per-volume `is read only` refusals on
  marked volumes — full context in `references/error-signatures.md`.
- **Fresh windows only** for log verification: a query through this Loki touches index
  objects stored on the very SeaweedFS it diagnoses and can regenerate the lines it
  measures (`references/loki-recipes.md`).
- **Single normative homes:** repair sequence → the dated runbook; incident evidence →
  the findings note; durable mechanics → this skill. On conflict about the incident,
  the runbook wins.
- **Anonymous answers are a posture, not an architecture.** Today every probe is
  credential-free; anything built in front of these endpoints inherits that exposure —
  gate mutating tiers first (`references/mcp-server-spec.md` §9).
- **No credential values** anywhere in these docs — posture prose only.

## Cross-pointers

- `skills/helm-chart-creation` — chart/ApplicationSet/proxy wiring when the fix is a
  deploy change (adding a service needs the full trio).
- `.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md` — the 2026-11 EC-removal
  runbook: normative for that repair, including the human `argocd app sync
  infra-seaweedfs` gate.
- `.agents/notes/2026-11-10-seaweedfs-incident-findings.md` — the incident's dated
  evidence record (superseded where the runbook corrected it).
- `.agents/plans/2026-10-25-debug-seaweedfs-csi-vac-http.md` — upgrade-induced CSI
  failure precedent (chart 4.35→4.50 broke every mount): the precedent chapter for
  version-bump fallout and `corrupted mount` consumer pain.
- Evidence base for every claim here and in the references: `RESEARCH.md` + `EXPLORE.md`
  in `.agents/plans/2026/2026-11-feat-seaweedfs-debug-skill/` (anchors cited in-file).
