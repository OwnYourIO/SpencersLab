# PLAN: SeaweedFS incident-runbook corrections + seaweedfs-debug skill
feature: 2026/2026-11-feat-seaweedfs-debug-skill

## Goal
Correct the live SeaweedFS incident runbook (`.agents/plans/2026-11-10-dep-seaweedfs-ec-removal.md`)
against the weed-4.50-source-verified findings in `RESEARCH.md` §R1 so the human-run repair —
per-volume EC decode/removal, split-brain check.disk healing, the live bad Loki index delete, and
the Phase-0 deploy via a manual ArgoCD sync — executes correctly on first paste. Then compile the
durable debugging knowledge into a new self-written skill `skills/seaweedfs-debug/` (terse
SKILL.md + deep references + a read-only probe script), including the follow-up card's pointer
file `references/mcp-server-spec.md` (§R2 distillation), and register the skill in the generated
AGENTS.md via rulesync.

## Out of scope
- **Executing the repair.** Every weed-shell/kubectl phase is human-run (no agent tier grants pod
  exec) and `argocd app sync infra-seaweedfs` is a human/admin action. The repo deliverable is
  the corrected pasteable runbook + verification checklists, not the live fix.
- **Live unknowns R1 §R1.10 U1–U7** (compaction revisions, orphan classification, group-448
  shard roles, 1982649 `.vif` vs idx>dat, which selfHeal annotation, umbrella `infra` app):
  docs instruct the PROBES; they never assume answers.
- **Building seaweedfs-mcp** — follow-up card `HhiinjT5hdi8D6fCY` (Inbox) owns it; this plan
  lands only the spec file the card points at.
- **Editing `.agents/notes/2026-11-10-seaweedfs-incident-findings.md`** — dated evidence record;
  its "Superseded by the runbook" pointer already routes readers to the corrected doc.
- **Re-enabling `services.infra.selfHeal`** — owner decision, affects every infra app.
- **The three stale incident branches** — content is already on main (EXPLORE §1.1); nothing to
  merge or cherry-pick.

## Commands
Validation suite for this plan (repo-local; no cluster access; npx pins match CI):

- test: `bash tests/seaweedfs-debug/surface.sh` — arms `t1..t5` map to chunks C01..C05 and
  arm `t7` maps to C07 (friction-round addition 2026-11-11, DECISIONS human ruling — mode:
  current session). Arm `t6` stays unwritten (C06 declined at approval; its number is never
  reassigned). (Statics-only per the `tests/wekan-mcp/skill-surface.sh` precedent; subset:
  `bash tests/seaweedfs-debug/surface.sh t2 t4`.) agent-test writes arms before any dev; each
  chunk's `## Tests` names its arm.
- lint: `npx --yes aislop@0.20.0 scan skills/seaweedfs-debug` — report honestly: markdown is
  NOT scoreable (`scoreable:false`, score null — EXPLORE §2.4), so prose cannot fail the CI
  floor; any scorable file (`.py`) must clear floor 80 with zero errors → the probe script is
  bash, and `aislop scan` takes a DIRECTORY, never a file.
- lint: `npx --yes rulesync@37.0.0 generate --check` — drift gate; green at plan time
  (verified 2026-11-11, exit 0); must stay green after C05 and after C07 (C07 re-runs
  `rulesync generate`; only the seven dev-family agent mirrors + the agents-sync
  permissions.md mirror may move).
- typecheck: none — no typed code in this plan.
- smoke (discovery + pointer claims, EXPLORE-grounded):
  - `test -f skills/seaweedfs-debug/references/mcp-server-spec.md && grep -Fq
    'skills/seaweedfs-debug/references/mcp-server-spec.md' skills/seaweedfs-debug/SKILL.md`
    — path string byte-matches card `HhiinjT5hdi8D6fCY`'s description (verified live 2026-11-11).
  - `grep -n '"skills' .opencode/opencode.jsonc` — the `skills/` discovery path already exists;
    NO chunk edits opencode config.
  - `git grep -n seaweedfs-debug .rulesync/rules/overview.md AGENTS.md` — after C05 both hit.
  - negatives: `git grep -rn seaweedfs-debug skills-lock.json .rulesync/skills .agents/skills`
    → empty (never lock-file, never rulesync/third-party dirs);
    `git grep -rniE 'abliterated|strata|gguf' skills/seaweedfs-debug` → empty
    (`live_code_grep` spans `skills/` — retired needles turn `charts/llama-swap/tests/` red).
- smoke (C06 ONLY, if opted in): `export PATH=$HOME/.local/bin:$PATH && helm lint
  charts/seaweedfs && helm template charts/seaweedfs >/dev/null` — no other chunk touches
  `charts/`, so no helm render belongs to C01–C05.
- C07 (permission machinery; friction-round addition 2026-11-11, rides THIS branch per the
  human's current-session ruling):
  - `npx --yes rulesync@37.0.0 generate` after the 7-source edit — `git status` may show
    ONLY the seven dev-family agent mirrors + the agents-sync permissions.md mirror.
  - `npx --yes rulesync@37.0.0 generate --check` — exit 0; an immediate second `generate`
    is a no-op (idempotence).
  - `bash tests/seaweedfs-debug/surface.sh t7` — C07's arm (byte-identical row across all
    7 sources + 7 mirrors, ordering invariant, policy.py verdict arms, generate gate).
  - pair-equality regressions: `bash tests/standalone-agents/surface.sh s2 s3 s10`
    (dev==dev-local alias parity + delta-aware pipeline-vs-standalone equality + source/mirror
    honesty), `bash tests/agent-dev-deploy/surface.sh` (deploy twins == baseline + the one
    cleanup row), `bash tests/agent-perms/surface.sh a1 a2 a3` (edit-pivot contracts + row
    needles), `bash tests/wekan-mcp/board-context.sh t4` (matrix walk — green only after the
    test wave's DEV_DEPLOY_SETTLED re-pin).
  - `bash tests/seaweedfs-debug/surface.sh t1 t2 t3 t4 t5` — C01–C05 arms unchanged
    (regression; the suite file itself is untouched by C07's dev round).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Runbook corrections (ec.decode per-volume, check.disk/fsck reality, deploy verification, heredoc fix) | M | 1 | [] | — |
| C02 | `references/mcp-server-spec.md` — the card-pointer file (§R2 distillation) | M | 1 | [] | independent of C01: different file, §R2 source (C01 uses §R1) |
| C03 | Skill mechanics references (`error-signatures.md`, `weed-shell.md`, `collections-and-ec.md`) | M | 2 | [C01] | data: must cite/align with the CORRECTED runbook, not the stale one |
| C04 | Skill entry: `SKILL.md` + `endpoints-and-probes.md` + `loki-recipes.md` + `scripts/health-probe.sh` | M | 3 | [C02, C03] | interface: SKILL.md indexes every reference file — all must exist first |
| C05 | rulesync regen: `.rulesync/rules/overview.md` + generated `AGENTS.md`, drift check | S | 4 | [C04] | registration needs the finished skill under its final name |
| C06 | OPTIONAL (human opts in at approval) — duplicate-Services fix in `charts/seaweedfs` per R1 §Q6 | M | 4 | [] | independent; last so declining it leaves no hole in earlier waves |
| C07 | Dev-family plans-root deliverable fix — depth-2 deny `.agents/plans/*/*` replaces the `.agents/plans/**` sweep on all 7 dev sources + regenerated mirrors + permissions.md rows (friction-round addition) | S | 5 | [] | independent: agent-permission machinery, touches no skill/chart files; rides THIS branch per the human's 2026-11-11 current-session ruling |

## Wave order
1. C01, C02 — independent (different files, different RESEARCH sections); run in id order if serial.
2. C03
3. C04
4. C05; and C06 only if the human opted in at approval (independent of C05). C06 was DECLINED
   at approval — its number stays unused and is never reassigned.
5. C07 — friction-round addition (DECISIONS 2026-11-11, human ruling, mode: current session):
   independent of C01–C05 (agent-permission sources + mirrors only); the sanctioned exception
   to one-branch-one-concern, recorded in the chunk's boundary note.

## Risks / assumptions
- **Distillation volume** (C03/C04): ~500–700 lines each of dense markdown for a flash-class dev
  session. Mitigation: sources are pre-distilled (RESEARCH.md verdict tables), chunk split keeps
  each session single-sized, chunk files enumerate the required content rows explicitly.
- **The runbook's Phase 3 heredoc block is broken as written** — verified by experiment
  2026-11-11: in `A | tee f <<'EOF'` the heredoc binds to `tee` (last segment), so commands
  never reach `weed shell`. C01 fixes the ordering (`A 2>&1 <<'EOF' | tee f`); C03 documents the
  gotcha. (Phase 4's block is single-segment and correct.)
- **aislop cannot score markdown** — the CI floor only bites scorable files; keep the probe
  script in bash and report the scan output honestly (EXPLORE gotcha 6).
- **`live_code_grep` negative pins span `skills/`** — retired llama-swap/strata needles in the
  new prose break green suites elsewhere (EXPLORE §2.3); negative greps are in Commands + t3/t4.
- **C06 option (a) needs human surgery at sync time**: live `seaweedfs-filer`/`seaweedfs-s3`
  Services must be pre-deleted (clusterIP immutable) and routing to headless backends re-verified
  (R1 §R1.6). Pre-existing debt (filer warning since 11-03), not this ticket's regression.
- Assumption: skill folder is `seaweedfs-debug` — byte-matches the card pointer, so NO card
  amendment is needed (alternative rejected in DECISIONS.md).
- Assumption: skill = evergreen debug methodology; the incident repair sequence stays in the
  dated runbook and the skill POINTS at it (single-normative-home precedent). Human can override
  at approval (Open questions #1).
- `RepeatedResourceWarning` persists after the Phase-0 sync unless C06 lands — warning-only,
  sync succeeds anyway (11-09 proof, R1 §R1.6). C01's checklist says so explicitly.
- **C07 rides the shipped OpenCode matcher semantics** (verified 2026-11-11 against the
  installed v2.2.6 binary + opencode.ai/docs/permissions): `*` matches any character
  INCLUDING `/` (whole-value anchored; `**` ≡ `*` — there is no globstar). The depth-2 deny
  shape is correct under exactly those semantics; if upstream ever ships segment-scoped
  globs, `.agents/plans/*/*` silently narrows to exactly-2-segment paths and depth-3+
  bookkeeping falls through to allow. Guard: t7's verdict arms run through the repo's
  fnmatch-based simulator (byte-faithful to the shipped matcher) — an upstream matcher
  change reddens loudly at the next suite run instead of silently opening ticket records.

## Open questions
Accumulated per the no-questions-until-final rule; best guesses applied throughout. The human
resolves any of these at plan approval (coord relays).

1. **Skill shape (EXPLORE Q5).** Debug-methodology + mechanism knowledge in the skill, with the
   incident repair sequence left in the dated runbook/notes as pointers? Best guess: YES —
   single-normative-home precedent (`tests/wekan-mcp/skill-surface.sh` one-owner prose) and skill
   longevity. Impact if overridden: C03/C04 grow to restate runbook procedures; duplicate-owner
   drift risk.
2. **C06 include/decline, and option (a) vs (b).** Best guess: include as OPTIONAL, default
   option (a) delete-wrapper-templates (R1's ranked recommendation) with the documented human
   pre-delete step; (b) rename is the fallback if a filer/s3 VIP gap is unacceptable. Impact:
   (a) = brief Service gap + routing re-verify at next sync; declined = warnings persist
   (cosmetic, non-blocking).
3. **Ship `scripts/health-probe.sh`?** Best guess: yes, bash (read-only curl GETs; aislop scores
   `.py`, bash keeps the skill unscorable-clean). Impact if dropped: SKILL.md keeps inline curl
   one-liners only.
4. **"Self-query-noise trick" precise definition.** Best guess: verification queries run THROUGH
   Loki touch the very index objects stored on SeaweedFS — a query covering the corrupt window
   regenerates the error lines it measures (and drove the original retry loop), so recipes must
   measure fresh-window rates / s3-side `retry reading` counts, never historical totals. Impact:
   one loki-recipes.md subsection; low.
5. **C01 also fixes the heredoc/tee binding bug** (verified broken). Best guess: yes — corrected
   in place with a one-line why-note; gotcha documented in `weed-shell.md`. Impact if skipped:
   the Phase 3 repair block feeds nothing to `weed shell` when pasted.
6. **Findings note stays unedited.** Best guess: yes (historical record; its wrong
   `-collection=default` snippet stays as history, corrections live in runbook + skill). Impact:
   readers of the note alone see stale commands — mitigated by its existing supersession pointer.
7. **Live unknowns (R1 U1–U7).** Best guess: docs instruct probes (simulate check.disk prints
   compaction revisions; admin EC page names shard roles; volume-log grep `idx references end=`);
   no chunk assumes answers. Impact: none on chunk structure; the human gathers answers at run time.
8. **Arm t6 when C06 is declined.** Best guess: agent-test does not write t6; surface.sh usage
   block lists t1..t5 (+t6 only when present). Impact: trivial.
9. **C07 shape (friction-round addition — grounded correction of the FRICTION proposal).**
   Best guess: the depth-2 deny — `.agents/plans/*/*` REPLACES the `.agents/plans/**` deny on
   all SEVEN dev-family sources (the brief-enumerated five plus `agent-dev-deploy(-pr)`,
   which `tests/agent-dev-deploy/surface.sh` t2 pins byte-equal to their baselines plus one
   row — editing five alone reddens a suite this plan promises green). Why not the proposed
   `edit .agents/plans/*-*.md` allow: the shipped OpenCode matcher's `*` crosses `/`
   (verified 2026-11-11, chunks/C07.md "Grounded semantics"), so placed before the deny it is
   dead code (last match wins) and placed after it also re-opens every per-ticket
   plan-of-record (identical dated-name shape; the matcher is depth-blind). The depth-2 deny
   is the only shape that opens root deliverables while STATE/chunks/FRICTION/DECISIONS/
   plan-of-record/templates stay denied. Impact if overridden: none feasible — see C07.
10. **Multi-repo port re-sync (C07, informational).** The ported repos (HomeAssistant etc.)
    keep the old `.agents/plans/**` deny until their next port; the `tests/multi-repo/
    port-*.sh` t5 pins assert each ported repo's own landed state, which C07 does not touch.
    Best guess: fold into the next scheduled port; no action in this ticket.
