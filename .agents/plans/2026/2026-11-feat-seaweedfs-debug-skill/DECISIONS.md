# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Skill lives at `skills/seaweedfs-debug/` (top-level self-written tree). NEVER in
  `.rulesync/skills/` (rulesync-owned → CI drift gate) or `.agents/skills/` (third-party,
  `skills-lock.json` integrity) — EXPLORE §2.2/§2.3.
- Frontmatter is exactly two keys (`name`, `description`); `name` == directory name; description
  follows the house trigger pattern (what → "Use this skill whenever …" → literal trigger tokens
  → "even if the user doesn't name this skill directly") — EXPLORE §2.1.
- SKILL.md stays terse (target ≤ ~200 lines); depth lives in `references/` with a "What lives in
  this skill" index giving each file a one-line when-to-consult hook (wekan-api model).
- All weed-4.50 facts pin to the deployed build (`weed v4.50 ec8f97935`) and carry the
  re-verify-on-bump rule (renovate has 4.53.0 pending).
- Agent-safety posture in all docs: read-only HTTP probes are agent-runnable; every weed-shell /
  kubectl-exec / argocd-sync step is a human-pasteable block (no agent tier grants pod exec or
  ArgoCD writes).
- Comment/prose discipline: comment-slop three-clause test; why-not-what; no history narration.

## Decisions
- 2026-11-11 human (approval round): plan approved C01–C05 as planned; **C06 declined** —
  duplicate Services stay, RepeatedResourceWarnings accepted as cosmetic (v3.5.6 dedupes,
  last-wins), manual sync still lands Phase 0. Test arms t6 not written.
- 2026-11-11 human: Phase-0 deploy = human runs the ArgoCD sync of `infra-seaweedfs` manually
  after this run ships; chunks' post-sync verification checklist (C01) is the acceptance aid.
- 2026-11-11 coord: remaining planner best-guesses adopted unanswered — skill stays
  methodology + pointer to the dated runbook; `scripts/health-probe.sh` ships (bash);
  self-query-noise recipe wording per plan Q4; findings note untouched; U1–U7 documented as
  probes, never assumed.
- 2026-11-11 plan: Skill folder name is `seaweedfs-debug`. Rejected: any other name + amending
  card `HhiinjT5hdi8D6fCY`'s pointer. Why: the card description (verified live, byte-exact)
  promises `skills/seaweedfs-debug/references/mcp-server-spec.md` on main — matching the folder
  to the card needs no board write and no second source of truth.
- 2026-11-11 plan: Skill = evergreen debug methodology + mechanism references; the incident
  repair sequence stays normative in the dated runbook
  `.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md`, which the skill points at (answers
  EXPLORE Q5, best guess — human may override at approval). Rejected: restating runbook
  procedures inside the skill (two owners drift; repo's single-normative-home precedent).
- 2026-11-11 plan: Chunk split C03 (mechanics refs) → C04 (observability refs + SKILL.md +
  script), i.e. references land BEFORE the entry point. Rejected: SKILL.md-first (would index
  files that do not exist yet — broken surface checks mid-branch) and one L mega-chunk (not
  single-session-sized for the code-model tier: ~1,200+ lines of distillation).
- 2026-11-11 plan: C02 (`mcp-server-spec.md`) is its own wave-1 chunk sourced purely from
  §R2. Rejected: folding it into the skill chunks. Why: it is the card-pointer deliverable with
  a different evidence base (§R2 verdicts/deltas) and can proceed in parallel with the §R1-based
  runbook corrections.
- 2026-11-11 plan: C05 (rulesync regen) stays a separate S chunk despite the
  "no standalone S chunk" preference. Why: `rulesync generate` rewrites ALL generated surfaces —
  quarantining that diff keeps content-chunk reviews clean and makes the "commit source +
  generated together" hard rule trivially auditable in one dedicated commit. Rejected: folding
  into C04 (mixes content review with generated-surface churn).
- 2026-11-11 plan: C06 (duplicate-Services fix) is OPTIONAL, wave-last, human opt-in at
  approval; default option (a) delete the four wrapper templates per R1 §Q6 ranking, with the
  human pre-delete step (`kubectl delete svc seaweedfs-filer seaweedfs-s3` — clusterIP
  immutable) documented, option (b) rename as recorded fallback. Rejected as defaults: (c)
  subchart value toggles (do not exist in 4.50 chart), (d) resource-exclusions/ignoreDifferences
  (ineffective — dedup happens before exclusions, R1 §R1.6).
- 2026-11-11 plan: C01 additionally fixes the Phase 3 heredoc/tee stdin-binding bug (verified by
  experiment 2026-11-11: `A | tee f <<'EOF'` feeds tee, not weed shell; corrected form
  `A 2>&1 <<'EOF' | tee f`). Why: a repair block that silently feeds nothing is worse than no
  block; Phase 4's single-segment form is already correct and stays.
- 2026-11-11 plan: Findings note
  `.agents/notes/2026-11-10-seaweedfs-incident-findings.md` is NOT edited. Why: dated evidence
  record with an existing supersession pointer; corrections land in the runbook (operational
  doc) and the skill (durable knowledge).
- 2026-11-11 plan: Probe script ships as bash `scripts/health-probe.sh` (read-only curl GETs).
  Rejected: Python helper. Why: aislop scores `.py` (floor 80 + zero errors; `skills/` already
  sits at 47 Critical from wekan-api's scripts) while markdown/bash prose keeps the new skill
  out of that blast radius; statics-only tests still `bash -n` it.
- 2026-11-11 plan: Tests live in ONE arms-style statics-only suite
  `tests/seaweedfs-debug/surface.sh` (t1..t6 ↔ C01..C06; t6 written only if C06 is approved),
  per the `tests/wekan-mcp/skill-surface.sh` precedent. Rejected: per-chunk script files
  (cross-file drift) and live-network smoke (suites are statics-only by design).

## Deferred
- C02 review minor (deferred by coord, verdict was APPROVED): `mcp-server-spec.md` §9 "verbatim" quote silently drops the "(such as a NetworkPolicy or service mesh)" parenthetical — restore on next touch of that file.
- Re-enabling `services.infra.selfHeal` cluster annotation (owner decision; affects every infra
  charts-appset app, not just seaweedfs) — surfaced by R1 §R1.6, out of this plan's scope.
- Answering R1 §R1.10 U1–U7 live unknowns — human-run probes during the repair; docs instruct
  the probes, results feed back into the runbook at run time, not via this plan.
