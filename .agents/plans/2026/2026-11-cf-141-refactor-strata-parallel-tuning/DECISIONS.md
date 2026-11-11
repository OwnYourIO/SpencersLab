# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision,
alternatives rejected, why.

## Conventions

- This ticket's tuning surface: `strata.config.engineProfile*` in `charts/llama-swap/values.yaml`
  (→ `strata-profile` ConfigMap → `/profile/strata-*.json`) + notes + docs. Chart templates are
  never the tuning surface (EXPLORE §2).
- Engine-consumed `STRATA_*` vars ride the profile-layer `env`; serve-consumed vars stay on the
  arena model env (T0 precedent). Env-form levers preferred for perf arms — they never disturb
  the `cmd` byte-equality loop.
- Docs and the `test_strata_runbook.py` DOC arms move in the same chunk (§9.13 doctrine); dev
  reports a law collision as NEEDS_INFO, the test session moves the law, nobody weakens it.
- On-target commands are `run_by: user` legs (no pod exec in any agent tier; ArgoCD syncs
  `main` only). Validation-first: offline render/equality gates prove every chunk; on-target
  proof rides the owner merge + the runbook capture.
- Evidence gates `RUN_HF_CHECK` / `RUN_FLAG_AUDIT` not required (no catalog/pack or llama.cpp
  flag surface moves).

## Decisions

- 2026-11-10 plan: **Frame = methodology transfer at the pin.** The card's guide (0.2.13/engine
  0.1.59 world) is adapted to Strata 0.2.9/engine 0.1.55 with NO version bump and NO envelope
  change; the guide's 8×256K targets are owner-envelope-bound and ride the pending
  `.agents/plans/2026-11-10-dep-strata-engine-0213-eval.md` instead. Rejected: re-cutting the
  ticket around the bump (the bump eval is explicitly gated and not executed; launch brief
  binding). (Q8 asks the owner to confirm the frame.)
- 2026-11-10 plan: **OQ-1 closed as fact for this plan** — `parallel:` ≡ `--batch` at 0.2.9 via
  `serve/server.py parallel_args` (RESEARCH OQ-1); the N-slots + 1-main full-max-context
  pinning law holds at the pin. The cf-77 "Q2 batch rejection" ruling re-read as rejecting the
  literal argv element, not the engine path (EXPLORE §5's open mapping question resolved).
- 2026-11-10 plan: **three chunks, chained waves 1→2→3** (runbook → arm+doc-truth → quality-arm
  docs). Rejected: one mega-chunk (docs+values+tests crossing reviewable boundaries at once);
  five per-arm chunks (arms beyond L2 are owner-gated follow-up PRs by the one-change-at-a-time
  law — planning them as chunks would pre-commit owner decisions). The chain exists because
  all three touch the same note file and later chunks' pins read earlier chunks' artifacts.
- 2026-11-10 plan: **new note file** `.agents/notes/strata-parallel-tuning-runbook.md` for the
  tuning runbook (Q6). Rejected: extending `strata-host-prep-gpu-ai.md` — its content is
  byte-pinned by `test_strata_runbook.py` DOC windows/pairs/alternation arms; a large new
  section would churn those laws for no gain. Cross-references only.
- 2026-11-10 plan: **exactly one live lever in this PR: L2 `STRATA_MMQ_KQ=1` on the q4 arena**
  (Q1 best guess yes). Chosen over L1 (9-var parallel stack): HIP-unqualified, confidence 6/10
  per RESEARCH's own reliability note — document-only (Q2). Chosen over L3 (batch-MTP):
  interacts with expert-cache shrink and needs a per-boot read-back the owner hasn't consented
  to spend a round on (Q3 → documented follow-up). If Q1 answers no, C02 degrades to doc-truth
  and L2 becomes a follow-up row.
- 2026-11-10 plan: **supersedes §9.24's T5 deferral for L2**: "upstream speed unmeasured on
  AMD" is no longer true — release 0.2.11 [36] carries R9700 prompt measurements and made the
  K-quant prompt kernels the gfx12 default; our pin just has to opt in via env.
- 2026-11-10 plan: **L4 (`--kv q4_0`) stays owner-gated, shipped as decision scaffolding only**
  (Q4 best guess no; C03): agent-segment KL ×2.2 [42] on an agent-heavy fleet is a quality
  trade, not a perf lever. Guide's "+8–12% PPL" recorded as refuted-at-PR-#21 [43].
- 2026-11-10 plan: **benchmark sweep localized to c ∈ {1,2,4}** (Q5) inside the shipped
  `parallel: 4` envelope; 6/8 cells documented as out-of-envelope, runnable only under a fresh
  owner ruling — never silently re-litigating a6e493b78.
- 2026-11-10 plan: **the doc-truth corrections ride C02** (Q7): the four pre-registered stale
  spots (service L207 ttl wording, chart L1524 "90 GiB", README rung-5 conv "24576 ×16",
  runbook §4 "no `--batch`") land with their law re-pins in the same chunk; supersession-
  history sentences stay untouched.
- 2026-11-10 plan: **hipBLASLt topic closed as no-op-at-pin** (U3): three independent layers
  (gfx1151-only auto rule, unpackaged claim-compiled engine, no 100401-class gfx1201 table) —
  the runbook's only obligation is the startup-log grep inside U1. Table generation
  (`tools/hip/tune_hipblaslt.cpp`) is out of scope.
- 2026-11-10 plan: **KV constant band 3.09–3.35 GiB/slot@262K int8** — budgets plan at the
  code-law 3.35 (our build), the U1 startup line is truth, neither doc gets "fixed" to the
  other (RESEARCH contradiction #1).
- 2026-11-10 plan: **EXPLORE gotcha 5 corrected, not edited**: `STRATA_KV_GROW_HOLD` DOES exist
  at 0.2.9 (`generate.cpp:14636`, RESEARCH adjacent-note) — the correction lands in the
  runbook's corrections ledger; EXPLORE.md stays as the historical scout record.

## Deferred

- Owner-gated follow-up arm PRs (each its own one-change merge, after C01's runbook gates a
  round): L1 parallel-stack arm, L3 batch-MTP arm, L5 vram-reserve arm, L4 per-rung flips.
  Priority per Q2/Q3/Q4 answers.
- Per-rung extension of L2 beyond q4 (primary/orca) — after the fleet-agent near-tie check.
- Replica mode (`serve/replicas.py`) as an alternative parallelism surface — RESEARCH's missed
  angle; out of the single-pod 110Gi envelope; legitimate new ticket if L1 disappoints.
- Host Step-0 [VERIFY] re-read results and every U1 startup capture — human-owned, gate the
  first bench round.
- On-target validation of C02's flip (post-merge bench baseline) — owner merge + user run per
  the runbook; the plan's chunk gates are offline-only.

---

# Round 2 — replan under the owner's frame overrides (2026-11-10)

## Decisions (round 2)

- 2026-11-10 human (batched round, verbatim): **Q5 — "Open the envelope to 8 slots"** and
  **Q8 — "No — re-plan with bump/envelope"**, overriding the round-1 recommendations; Q1–Q4,
  Q6, Q7 answered as recommended (L2 ships; L1/L3 documented; `--kv q4_0` stays owner-gated;
  new note file; stale-doc corrections fold). These two answers are owner rulings: the
  round-1 plan's "No version bump / No envelope changes" Out-of-scope is void, and the
  bump-eval plan `2026-11-10-dep-strata-engine-0213-eval.md` is **superseded-as-executed-by-
  AD-141** at its gate 6 — its gates 1–5 become this ticket's C04 work (verbatim-condensed
  into the runbook). The a6e493b78 4-slot ruling is re-opened ONLY as far as the owner's
  words go; the plan reads them as the row-H licensing question (Q9), not a uniform mandate.
- 2026-11-10 plan: **the round-2 plan replaces the round-1 body wholesale** (the round-1 file
  carried its own supersession clause for exactly this answer; all chunks were pending, so
  renumbering is sanctioned). Old C03 (quality-arm chunk) retires as a chunk — its content
  survives, folded into the C01 runbook's quality-arm section (Q4 scaffolding) + the envelope
  table. New chunk set: C01 runbook (M) → C02 L2+docs (M) → C03 row-H envelope (M) →
  C04 bump (L).
- 2026-11-10 plan: **the Q5×Q8 interaction is surfaced, not smoothed.** Facts the owner may
  not have had in front of them (plan law: state plainly): row-H (primary IQ3_S 8×262144
  int8, conv→16, PLE-direct) **fits at the CURRENT 0.2.9 pin** — the deliverable 8-slot shape
  needs no bump; q4@8×262144 int8 is physically impossible at BOTH pins (only the row-G
  file-tier regime, [E]-grade, ever fits it); and the bump today carries zero upstream
  clearance — five+ open crash-cluster issues, no maintainer replies, 0.1.59 CONFIRMED in the
  failing set (#5559/#5635 same-day reporter updates; #5614/#5701 new; the eval's "0.1.57
  clean" premise dead). Sequencing is Q13; the plan's default is **pin-first** (PR-A: runbook
  + L2; PR-B: row-H; PR-C: bump gated by same-day re-fetch + soak stop condition).
- 2026-11-10 plan: **L2 ships at the pin AND stays meaningful post-bump** (the launch's
  ruling-for-plan: decide + record). At 0.2.9 the env is the live lever; at 0.1.59 it becomes
  the engine's own Linux-gfx12 default for UD-Q4-class packs (NOT the IQ3_S primary) — the
  pin is kept as intent-pinning (user-set wins [61][62]), the comment carries the supersession,
  and the re-bench attribution sheet forbids double-counting L2's delta against the bump's.
- 2026-11-10 plan: **bump-soak shape = post-merge production watch** (chosen from R2-D's two
  vehicles): the hourly fleet IS #5559's traffic shape; the branch-image alternative
  (`workflow_dispatch` + hand-swap) stays documented in the runbook with its GitOps-revert
  caveat because it needs admin mutation outside GitOps. Stop condition is binding (law 4):
  any reproduced signature ⇒ revert PR prepared + evidence back to the owner, no fix-forward.
- 2026-11-10 plan: **row-H is a law-move chunk, not just a values chunk.** The shipped
  parallel-equality interlock (`test_strata_q4_rung.py` L175–179 + the profile comments)
  currently FORBIDS a per-rung slot shape; narrowing it to siblings {strix,orca,q4}=4 with
  primary excluded is legal only under the owner's Q5/Q10 words, cited at the exclusion.
  The primary fixture-era chain law gains **step kinds** (single-flag steps t03/u14 preserved
  byte-true; owner-ruled shape steps with an exact pinned surface set; the bump's config-
  obligation step delta == exactly {drafting}) — every era delta stays machine-re-verifiable,
  nothing weakens (§9.16/§9.25 doctrine extended, the precedent's own words).
- 2026-11-10 plan: **`"drafting": "mtp"` pins ride ONLY the bump PR** (0.2.13 runs
  `drafting.apply()` unconditionally [79]; at 0.2.9 it would be a foreign key against the
  closed-world surface laws — the suite's q36 closed-world arm pattern shows why unknown keys
  are red). Four flash-next profiles; ornith's q36 surface separately checked, not pinned blind.
- 2026-11-10 plan: **extra stale spots proposed for fold (Q14):** containers README
  alpine-3.22≠3.24 + "72Gi" → C04 (same files); chart-values dead PIN-ME comment → C02
  (comment housekeeping adjacent to its values edits). Comment-only, law-adjacent, owner
  ratifies.
- 2026-11-10 plan: **quality-arm economics updated at the bump frame:** `--kv q4_0` no longer
  even relieves the 8-slot case (q4+q4_0@8×262K = 109.2 ≫ safe line — arena term is the wall),
  it halves deep-park KV at the 4-slot posture instead; still owner-gated scaffolding only
  (Q4 "No" unchanged by the frame).
- 2026-11-10 plan: **Landing shape recommended as three PRs** from the one ticket branch
  (Q15), each chunk commit-set independently mergeable and suite-green by construction;
  landing mechanics stay the owner's.

## Deferred (round-2 status)

- **row-G experiment** (q4 file-tier 8×262K via `--resident-budget-gib`/`--ram-keep-gib`) —
  chunkless until owner Q11 authorization + U3-v2 cgroup-probe result + post-C04 measurements;
  then its own soak-only PR with rollback, planned by re-plan, not smuggled here.
- L1 / L3 / L5 / **L6' `STRATA_PREFILL_CPU_SHARE_BATCH=1`** (new, 0.1.59-only) — documented
  follow-up arms per Q2/Q3 answers, each its own bench round + PR.
- Per-rung extension of L2 (primary excluded from the engine flip anyway; orca/ornith are
  UD-Q4-class — candidates only after the q4 round's verdict).
- U1-v2 numeric answers (hipBLASLt venv line, pinned-RAM GiB at 0.1.59 settling the
  3.09–3.35 band, `expert cache auto → N` at 8-slot windows, drafting/walkdown lines) +
  §3.4 `--plan` re-checks + soak verdict + re-bench sheet — all user legs, gated in the
  runbook, riding the owner's merges.
- v3.1-rung routing, engram/PLE table swap, `--ram-keep-gib` as a DEFAULT posture,
  `--resident-experts`, replica mode — unchanged out-of-scope (bump-eval exclusions kept;
  replica mode remains the legit new-ticket angle if the arms disappoint).
- gate.sh t17[C03] flaky-on-origin-main (TEST_SPEC §9.22) — unrelated to this ticket; own
  debug card still recommended.

---

# Round 3 — third answer batch folded, plan finalized on best-guess (2026-11-10)

## Decisions (round 3)

- 2026-11-10/11 human (verbatim, batched round 3): **Q13 = "(a) Pin-first, bump gated"**;
  **Q9 = "8 slots everywhere. I know it won't fit, but I also know I won't be running 8
  sessions at full context. I'd rather crash it and scale back from there."** (non-recommended
  OVERRIDE — every flash-next rung, not primary-only); **Q10 = "Yes — as planned"** (full
  row-H for the primary); **Q11 = "Authorize as experiment only"** (row-G: own future soak PR,
  never default, no chunk pre-committed); **Q12 = "No"** (the U3-v2 on-pod cgroup-detection
  user leg is NOT run in this run); **Q14 = "Fold them in"** (three extra stale spots join the
  four confirmed — doc-fix total now SEVEN); **Q15 = "Two PRs (A+B merged)"** (PR-1 =
  C01+C02+C03 runbook+lever+envelope; PR-2 = C04 bump; commits stay coord's on-branch);
  **Q16 = "After bumping, have them present, but leave a comment they are experimental"**
  (`STRATA_MMQ_KQ=1` and `"drafting":"mtp"` both stay present post-bump, each with an
  experimental-flag comment — never settled intent-pinning wording).
- 2026-11-10 plan: **Q9×Q13(a) tension is carried as Q17, not silently resolved.** Facts
  stated to the owner: the (N+1)×full-context pinning law is unconditional at engine start at
  BOTH pins (byte-identical block; the KV-window walkdown grace exists only at 0.1.59), so
  "8 everywhere at the pin" ships strix/orca/q4 knowingly beyond their pin arithmetic — the
  authorized outcomes are engine fit-down (degraded `batch_slots`), park refusals, or a
  contained cgroup kill (the 110Gi containment + MALLOC protections survive as exactly that
  safety net). **Best guess (a) = the plan's written shape** (8 everywhere at the pin now,
  per-rung boot-read gates, per-rung revert lines, scale-back only on an explicit in-round
  owner word), because the owner's own words authorize crashing-and-scaling-back and (a)
  honors Q9 verbatim; (b) = raise lands with the bump's walkdown; (c) = revert to primary-
  only. C03's dev start is gated until coord folds Q17; waves 3/4 reorder under (b) with no
  other text change.
- 2026-11-10 plan: **the parallel-equality interlock LOSES the `parallel` key entirely**
  (test session moves it in C03): with all four flash-next rungs raised by one ruling,
  keeping byte-equality would forbid the owner's own pre-authorized scale-backs (one rung →
  4) from being lawful single-value edits. Each rung's parallel becomes per-rung data pinned
  individually with its ruling citation; ornith pinned at 1 — its surface ruling survives
  Q9's words under the plan's reading ("flash-next rungs"), and Q17 re-flags that reading.
- 2026-11-10 plan: **Q12's decline is recorded as a decline, not an answer.** The cgroup-
  detection premise behind row-G stays UNMEASURED; the runbook carries row-G marked
  "premise unmeasured — probe declined 2026-11-10/11; any future row-G authorization must
  run its own" and the U1-v2 checklist drops the probe leg entirely. This prevents a later
  run from treating [67]'s "no limit detected?" question as settled.
- 2026-11-10 plan: **Q15 accepted with named controls:** attribution of L2 vs the envelope
  inside one PR rides the runbook's pre-PR-1 baseline (§10 standard run before merge) and
  C03's per-rung commits (revertable individually, cherry-pick-droppable pre-merge); the
  one-change-per-merge law is amended for PR-1 by owner word, NOT by planner convenience.
- 2026-11-10 plan: **Q16 comment doctrine:** "experimental" is the owner's own word and is
  what the comments must say at the new engine; the repo comment law keeps them why-only (no
  history narration), so the drafting/MMQ comments state: what the key pins, that the engine
  default now also applies (or resolves MTP anyway), that it is experimental per owner
  ruling Q16, and the revert line. Review verifies wording; the suite verifies the rendered
  keys.
- 2026-11-10 plan: **doc-fix roster final at seven:** four confirmed (service ttl wording,
  chart L1524 description, README rung-5 conv, runbook §4 phrasing) + three folded (chart-
  values PIN-ME → C02; containers README alpine 3.22→3.24 + "72Gi" → C04). README L1524-
  era sentence is era-consistent: C02 states 32768 (true at its gate), C03 re-moves to the
  row-H/8-everywhere truth before PR-1 merges.

## Approval (human, 2026-11-10)

- 2026-11-10 human: **plan APPROVED — option (a) stands** (Q17 resolved with the approval
  itself, not by a separate round). Consequences as written: C03 ships 8 slots on all four
  flash-next rungs at the 0.2.9 pin with the per-rung boot-read gates and pre-written revert
  lines; PR-1 = C01+C02+C03; PR-2 = C04, gated on the same-day crash-cluster re-fetch plus the
  post-merge soak watch. Rejected at approval: (b) defer the slot raise to C04 (loses the
  at-pin row-H win), (c) primary-only (contradicts the owner's Q9 word). The owner explicitly
  accepts crash-and-scale-back as the at-pin posture for strix/orca/q4.
- 2026-11-10 human (Q12, standing): the U3-v2 cgroup-detection probe is **not** run in this
  ticket; row-G's premise therefore stays unmeasured and any future row-G authorization must
  carry its own probe leg.

## Deferred (round-3 status)

- Q17 RESOLVED (see approval entry at end of Decisions): plan APPROVED with (a) —
  crash-and-scale-back at the pin ships as written; (b)/(c) re-wave
  or shrink C03 before execution — nothing else in the plan changes.
- row-G file-tier q4@8 experiment — owner-authorized **as experiment only** (Q11), premise
  unmeasured (Q12 declined), post-C04 subject: its own probe leg, its own PR, its own
  rollback, its own planning round.
- Scale-back PRs per rung if boot-reads degrade (owner in-round word required; ladder lines
  pre-written by C01/C03).
- L1 / L3 / L5 / L6' follow-up arms; per-rung L2 extension; v3.1 routing; engram table;
  `--resident-experts`; replica mode — all as in round-2 Deferred, unchanged.

## Owner directive — CI delta (2026-11-11)

- 2026-11-11 human (in-session, after the post-merge CI `docker-build.yaml` strata build failed
  in the runtime stage's `apt-get update` — `Could not resolve 'archive.ubuntu.com' /
  'security.ubuntu.com'`; my earlier transient-runner-DNS reading SUPERSEDED: the domains
  themselves are down at fetch time, confirmed by the owner): **"those domains are down right
  now. Can you do something like the following to get around it? RUN sed -i
  's|http://archive.ubuntu.com|http://mirrors.edge.kernel.org|;
  s|http://security.ubuntu.com|http://mirrors.edge.kernel.org|'
  /etc/apt/sources.list.d/ubuntu.sources && apt-get update ..."** — recorded verbatim.
- 2026-11-11 coord shape ruling within the directive's "something like": implement as an
  **official-first, mirror-on-failure fallback** (plain `apt-get update` tried first; on
  non-zero exit the sed re-points both stanzas at kernel.org and retries), NOT an unconditional
  re-pin — Canonical being briefly unreachable is an outage workaround, not a permanent trust
  move; the fallback self-retires when the mirrors heal. Obligations the dev round must verify
  live and record: `mirrors.edge.kernel.org` actually serves the `dists/noble/InRelease` AND
  `dists/noble-security/InRelease` shapes the two stanzas produce (if security's suite is not
  hosted there, adjust the fallback's security stanza — drop-with-why is the accepted
  alternative for the throwaway toolchain layer only) and the file is the deb822
  `ubuntu.sources` (noble) the sed assumes. Lands as delta chunk C05 on this ticket (cf-122
  delta precedent); PR-3 rides the same branch, now rebased clean onto origin/main.

## Coord rulings (2026-11-11)

- 2026-11-11 coord: **the official-first shape ruling for C05 is WITHDRAWN — CI evidence proves
  it dead.** The landed guarded step ran (`apt-get update || { sed → mirror && update; }`) and
  the CI log shows no mirror line at all: apt's `apt-get update` exits 0 even when every
  stanza host is unresolvable (it prints `W: … ignored, or old ones used instead` and
  succeeds), so the `||` branch never fires and the step dies later at the install's
  `E: Unable to locate package`. The dash behavioral proof stubbed update as failing — real
  apt doesn't. Reinstated: the owner's verbatim form — sed re-points BOTH stanza hosts to
  `http://mirrors.edge.kernel.org` UNCONDITIONALLY before the single `apt-get update`. The
  kernel.org noble + noble-security serveability probes (both 200, dev + reviewer passes) are
  what make the direct form safe; the "never the primary path" ideal is ceded — this base
  image's builds take the mirror, and that is now the documented posture, not a fallback.
- 2026-11-11 coord: **per-rung commit split WAIVED for C03** (review r1 open question): the
  envelope landed as one commit 2e1ee3a20 against §9.28's four-commit control; branch is
  unpushed and PR-1 landing is the owner's act — the runbook ladder's per-rung revert lines
  keep the drop-a-rung option fully available pre-merge without rewriting recorded history.
  Owner objects → a mechanical split is one coordination round away.
