# PLAN: Tune Strata for parallel performance (AD-141) — bump + 8-slot envelope frame (round 3, finalized draft)

feature: 2026/2026-11-cf-141-refactor-strata-parallel-tuning
card: AD-141 (board TNQJ2BrXenZovngTS, card pjLoQbzXpT2NemCSm)
type: refactor · service: gpu-ai · models (all stages): openrouter/qwen/qwen3.8-flash ·
priority: default · hitl: Final Review · no Deployment stage, no single-session opt-in
grounding: EXPLORE.md (Round 1 + Round 2 R2-A…R2) and RESEARCH.md (Round 1 + Round 2
"v0.2.13 / engine 0.1.59 under the bump frame") — all read in full, binding; owner answers
of the round-1 batch (Q1–Q8) and round-2 batch (Q9–Q16) recorded verbatim in DECISIONS.md.

> **ROUND-3 STATUS (2026-11-10T23:09+00:00): answers folded, ONE question remains (Q17).**
> The round-2 batch resolved: **Q13 = (a) pin-first, bump gated**; **Q9 = the non-recommended
> OVERRIDE "8 slots everywhere. I know it won't fit, but I also know I won't be running 8
> sessions at full context. I'd rather crash it and scale back from there."**; **Q10 = yes,
> row-H as planned (primary)**; **Q11 = row-G authorized as experiment only, no pre-committed
> chunk**; **Q12 = "No" — the U3-v2 on-pod cgroup-detection leg is NOT run** (row-G's premise
> therefore stays unmeasured; a future row-G decision needs its own probe — recorded so a
> later run cannot assume it was answered); **Q14 = fold the three extra stale spots** (seven
> doc fixes total); **Q15 = two PRs — PR-1 carries C01+C02+C03 (runbook + lever + envelope),
> PR-2 is the bump**; **Q16 = post-bump, `STRATA_MMQ_KQ=1` and `"drafting":"mtp"` stay
> PRESENT, each carrying an experimental-flag comment at the new engine — not
> settled-intent-pinning wording.**
> **The unresolved tension is Q17** (this plan proceeds on best-guess (a) and re-cuts if
> answered otherwise): Q9's "8 everywhere" ships at the pin precisely where Q13(a)'s rationale
> ("the pin is safe") says the (N+1)-session pinning law is unconditional at engine start
> (byte-identical at both pins; the KV-window walkdown grace exists ONLY at 0.1.59, i.e.
> after C04). "8 everywhere at the pin" is therefore a deliberate crash-and-scale-back
> posture (per-rung boot-read gates + the 110Gi cgroup keeping kills inside the container),
> while "pin-first because the pin is safe" is a different rationale. Owner words authorize
> the crash; the plan carries the contradiction openly rather than smoothing it.

## Goal

Deliver the card's parallel-performance upgrade on the owner's chosen shape: **PR-1 at the
current pin** — the tuning runbook (capture/bench/stop-criteria methodology, bump-gate
appendix, arm + envelope tables, scale-back ladder), the L2 lever (`STRATA_MMQ_KQ=1` on the
q4 arena), the seven doc-truth corrections with their law moves, and **the owner-ruled
envelope: `parallel: 8` on every flash-next rung (primary, strix, orca, q4; ornith stays 1) —
the primary landing the full row-H shape (conv→16384, PLE forced direct) that genuinely fits
at the pin (99.0 GiB), the other rungs shipped deliberately beyond their budget with
per-rung boot-read gates and a documented scale-back ladder ("crash it and scale back from
there", owner Q9)**; then **PR-2 the gated bump** — Strata 0.2.13 / engine 0.1.59 per the
superseded eval's gates plus #5614/#5701, the carry-patch re-verify, the
`"drafting": "mtp"` pins (experimental-flagged per Q16), and a post-merge soak watch whose
stop condition is binding.

## Out of scope (round-3 frame)

- **Row-G as a regime** (q4 file-tier 8×262144 via `--resident-budget-gib`/`--ram-keep-gib`)
  — Q11: experiment-only authorization, never a default, **no chunk pre-committed**; its
  premise (cgroup-limit detection under k3s) was NOT measured — Q12 declined the probe, so a
  future row-G round must run its own. What DOES ship (Q9) is q4's bare `parallel: 8`, which
  the pin's arithmetic says will boot-degrade or take a cgroup kill (123.9 GiB ≫ cgroup); the
  engine's fit-down and the 110Gi containment (a6e493b78 doctrine) are the accepted safety
  net, and the runbook's ladder prescribes per-rung scale-back.
- `--kv q4_0` adoption — owner-gated scaffolding in the runbook only (Q4 "No"; its 8-slot
  value is nil — q4+q4_0@8 = 109.2 still over the safe line).
- U3-v2 cgroup probe — declined for this run (Q12 "No"); listed in the runbook solely as the
  future row-G precondition, not a scheduled leg.
- V3.1-rung routing, engram/PLE table swap, `--ram-keep-gib` as a default, `--resident-experts`
  (hazardous, CUDA-only evidence), the outer llama-swap matrix / `unified-vulkan-266`
  supervisor pin, renovate coverage for strata, chart templates (tuning surface =
  values/notes/docs).
- On-target execution: pod exec, kubectl mutations, image pushes, workflow_dispatch, soak
  runs — all `run_by: user`; ArgoCD syncs `main` only; landing = the owner's two PRs.

## Laws every chunk obeys

1. **Version-churn gate:** no flag adopted before the startup/`--help` capture verifies it on
   the installed build — U1 at the pin (PR-1 legs), **U1-v2 on the post-bump build** (the
   churn checklist is RESEARCH Round 2 OQ-R2b.5, less the U3-v2 item per Q12).
2. **Landing shape (owner Q15):** **PR-1 = C01+C02+C03, PR-2 = C04** — chunk commit-sets
   stay individually revertable (per-rung lines in C03); the owner accepted the attribution
   trade of merging the lever with the envelope: the runbook's pre-PR-1 baseline is the
   attribution control, and the q4 rung's §10 round reads L2-armed-@-8-slot combined vs the
   a6e493b78-era baseline, stated plainly rather than pretended-separable.
3. **Crash-and-scale-back discipline (owner Q9):** every rung's raise carries its own
   boot-read gate (startup `INFO batch_slots`, degrade warnings, cgroup kill / restart pair)
   recorded per-rung in the runbook; scale-back = a follow-up single-value PR (rung → 4)
   under an explicit in-round owner word — no agent discretion, no silent half-reverts.
4. **GitOps only; bump lands via merge→CI `:main`.** Chosen soak shape (Q13a): post-merge
   production watch (the hourly fleet IS #5559's traffic shape) with tripwires +
   revert-PR-ready; the branch-image alternative (`workflow_dispatch` + hand-swap, its
   GitOps-revert caveat) stays documented-only.
5. **Soak stop condition (C04, binding):** reproduction of #5559 (`libhsa-runtime64` GPF /
   `hsa_signal_*` vtable), #5635 (load-peak RAM class), #5614 (MES `REMOVE_QUEUE` wedge), or
   #5701-class non-finite-logit decay ⇒ the bump leg STOPS, revert PR prepared, evidence to
   the owner. No fix-forward.
6. **Ledger law:** both FROM tags + clone tag + README rows + digests (re-read live via
   anonymous token + manifest HEAD; `com.strata.engine` label = engine proof) move in ONE
   commit; `strata update` never runs in the container; claim-compiled `exe` paths are
   version-free and do NOT move (marker-keyed migration recompiles in place).
7. **Envelope law (updated by Q9/Q15):** the parallel-equality interlock LOSES the
   `parallel` key by owner word — each rung's slot count is per-rung data under its own
   ruling (so scale-back cannot violate a cross-rung law); cgroup and all `--memory-limit-mib`
   caps stay UNCHANGED (no owner ruling re-opens them; row-H's 99.0 ≤ 108 ≤ 110 is the only
   cap-math that moves); fixture-era chains move through the test session with each
   rung's delta == its pinned step-set (shape step / `{parallel}` step / bump-config
   `{drafting}` step / engine `{exe,lib_dirs}` step) — history verified byte-true, nothing
   weakened.
8. **List-merge trap / env placement / argv shape / docs-move-with-laws / same-day
   crash-cluster re-fetch before C04-readiness** — unchanged from round 2.

## Commands (verified 2026-11-10 on this worktree)

```sh
export PATH=$HOME/.local/bin:$PATH
helm dependency update charts/llama-swap     # fresh worktrees: subchart not vendored — renders ERROR without it
helm lint charts/llama-swap                 # measured: 0 failed
helm template charts/llama-swap > /dev/null # measured: OK
cd charts/llama-swap && python3 -m pytest tests/ -q       # measured baseline: 417 passed / 9 skipped / 0 failed (~25 s)
cd containers/strata && python3 -m pytest tests/ -q       # measured baseline: 24 passed / 0 failed (C04's gate surface)
npx aislop ci --changes                                    # 0 errors / 0 warnings on touched files
```

Per-chunk gates: rendered `strata-profile` + `strata-config` ConfigMap delta equality (only
sanctioned keys move), goldens byte-identical (inner/profile/pod keys never reach them —
§9.27), four-surface engine-label law for C04. On-target legs (U1/U1-v2 captures, §3.4
`--plan` re-checks, §10 sweeps, per-rung boot-reads, soak watch) are `run_by: user`, gated in
the runbook, riding the owner's merges — never agent commands. Evidence gates
`RUN_HF_CHECK`/`RUN_FLAG_AUDIT` not required.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Tuning runbook — capture/bench method, bump-gate appendix, arm + envelope tables + scale-back ladder | M | 1 | [] | — |
| C02 | Ship L2 (`STRATA_MMQ_KQ=1` on q4) + doc-truth corrections (4 + confirmed PIN-ME fold) | M | 2 | [C01] | the note's L2 row is the byte-exact diff contract C02 ships (its fidelity arm ties them); corrections restate C01's settled adjudications — authority first |
| C03 | Owner-ruled envelope: `parallel: 8` on primary/strix/orca/q4 (primary full row-H), ornith stays 1; per-rung boot-read gates + scale-back ladder | M | 3 | [C02] | same file + the q4-era/env laws C02 just re-pinned; C03 adds q4's `{parallel}` era step on top of C02's `{env}` era — sequential captures, one delta per step |
| C04 | Bump: Strata 0.2.13 / engine 0.1.59 — PR-2, gated (same-day re-fetch → ledger+patch+drafting(experimental-flagged)+tests → merge → soak watch) | L | 4 | [C01, C02, C03] | Q13(a): lands only after PR-1 has landed and its per-rung boot-reads are recorded — the envelope state is the bump soak's baseline and its re-derivation subject |

## Wave order

1. C01 → 2. C02 → 3. C03 → 4. C04. Order settled by **Q13(a)** (no swap). C03's dev start is
gated on **Q17**: if the answer differs from the plan's best-guess (a), C03 re-cuts (and C01's
envelope-table/shipped-in legs re-pin with it) before any execution.

## Risks / assumptions

- **Q17 is the plan's live hinge.** Under best-guess (a): at the pin, q4@8 is arithmetically
  over budget (123.9 vs 110 cgroup vs 125.08 node) — the expected outcomes at PR-1 merge are
  engine fit-down (degraded `batch_slots`), conversation-park refusals, or a contained
  cgroup kill on the q4/orca rungs; that IS the owner's authorized posture, controlled by the
  per-rung boot-read gates and the ladder. The residual risk the owner should re-acknowledge
  at approval: two of PR-1's rungs may be non-serving until a scale-back round.
- C04's clearance is not established: five+ open cluster issues, zero maintainer replies,
  0.1.59 confirmed in the failing set (#5559/#5635); the re-fetch + stop condition are
  first-class acceptance, and a HOLD at gate 1 is compliance, not failure.
- Carry patch #3574 (closed not_planned) must apply at v0.2.13; the Dockerfile verify layer is
  the build tripwire; a re-cut routes through the test session (2-hunk law), never dev.
- Row-G decisions downstream of C04 carry an UNMEASURED premise (Q12 declined U3-v2): the
  runbook says so in row-G's row, so a future owner cannot mistake [E] for measured.
- If Q17 answers (b) or (c), waves 3/4 reorder (b) or C03 shrinks to primary-only (c); no
  other chunk text moves.

## Open questions (round-3 batch — ONE remains; plan proceeds on the best guess below)

- **Q17 (Q9 × Q13(a) tension — the crash-and-scale-back scope at the pin):** the owner's Q9
  override says 8 everywhere and accepts crashing; Q13(a) was chosen because the pin is the
  safe place — but the (N+1)×full-context pinning law is unconditional at engine start at
  BOTH pins (walkdown grace is 0.1.59-only). Options: **(a)** ship 8-everywhere at the pin
  now — primary fits (row H), strix/orca/q4 ship knowingly over budget with per-rung
  boot-read gates + scale-back ladder (expect degraded `batch_slots`, park refusals, or
  contained cgroup kills on q4/orca until a scale-back round) — **this is the plan's
  best-guess and its written shape**, because the owner's own words authorize crashing and
  scaling back and (a) honors the ruling verbatim; **(b)** 8-everywhere but landing the slot
  raise with C04 (post-bump, where the engine's walkdown protects the VRAM side) — keeps the
  pin safe, contradicts Q13(a)'s pin-first rationale only for the envelope half; **(c)**
  primary-only per Q10 — reverts Q9 to the recommendation. Impact: (a) = plan as written;
  (b) = C03 re-waved behind C04 + C01's board rows swap; (c) = C03 shrinks to the round-2
  shape (per-rung law narrowing survives anyway).
- Recorded, NOT asked: **Q12's "No"** leaves the row-G cgroup-detection premise unmeasured —
  future row-G authorization must carry its own probe leg (noted in plan Out-of-scope,
  DECISIONS, and the runbook's row-G cell so no later run mistakes it for answered).

## Review record (final whole-plan)

- 2026-11-11 · final review (fresh session ses_e36ffc873ffeCe8qd0sz89Te1O) ·
  **CHANGES_REQUESTED → CLOSED-APPROVED-ON-FOLD.** Finding 1 (MAJOR, fold-now): one
  doc-truth clause — the `containers/strata/README.md` Publishing posture — fixed prose-only
  by dev, suites re-verified unchanged (charts 466 passed / 9 skipped / 0 failed; containers
  25 / 0; aislop 0 errors / 0 warnings). Two MINOR items are pure bookkeeping and closed by
  this records pass (C03 Review-notes transcription from the STATE r1 handoff, cf-131 C09
  precedent; the 2026-11-11 coord waiver re-shelved under its own `## Coord rulings
  (2026-11-11)` heading in DECISIONS). Everything else the verdict rested on — era-chain
  deltas, owner-round records, ledger digests, gate-1 claims — was independently
  re-derived green by the reviewer. The approval's HITL point is satisfied by the owner's
  standing rulings; the plan itself is not re-opened.
- **Remaining owner legs (unchanged by the final review):** PR-1 (C01+C02+C03) lands before
  PR-2 (C04) per Q13(a); landing-day gate-1 crash-cluster re-fetch against the runbook row
  law; the P1 probe trio (research Round 3 — `--families`/`--geometry` reads + ornith
  load-smoke, both refusal strings checked) as user legs post-branch-build; U1-v2 capture +
  §3.4 `--plan` re-checks + post-merge soak watch (binding stop condition) + re-bench
  attribution sheet; row-G stays deferred (Q11 experiment-only, Q12 premise unmeasured).

## Delta round — CI mirror fallback (C05, owner directive 2026-11-11)

Authority: DECISIONS "Owner directive — CI delta (2026-11-11)" (owner's verbatim sed + the
coord official-first/fallback-on-failure shape ruling). Ticket is otherwise landed and
complete; C05 is the cf-122-precedent delta chunk — see `chunks/C05.md` for the contract.
`plan_status` is the coordinator's record and stays as it is.

Commands slice for the delta (supplements the plan's Commands above; chart surfaces are
re-checked, not edited):

```sh
export PATH=$HOME/.local/bin:$PATH
cd containers/strata && python3 -m pytest tests/ -q   # C05's gate surface; entering baseline 25P/0F + new test_c05_* arms
cd charts/llama-swap && python3 -m pytest tests/ -q   # unchanged re-check: 466P/9S/0F (no chart file moves)
# dev-round live probes (agent-capable HTTPS, outcomes recorded in the handoff):
curl -sSI https://mirrors.edge.kernel.org/ubuntu/dists/noble/InRelease
curl -sSI https://mirrors.edge.kernel.org/ubuntu/dists/noble-security/InRelease   # decides host-sed vs stanza-drop
# base file-shape evidence: GHCR anonymous-token manifest HEAD + layer tar-listing proving
# /etc/apt/sources.list.d/ubuntu.sources deb822 + the two hosts on 0.2.13-rocm-gfx120x
npx aislop ci --changes                               # 0/0 on the touched files
# docker build => no-daemon, CI-deferred; docker-build.yaml on the PR-3 branch is the authoritative build proof
```

Closure (2026-11-11): C05 dev `590f5b9db` + review **APPROVED r1** (full record in
`chunks/C05.md`); AC6 — the authoritative build proof — rides PR-3's CI `docker-build.yaml`
success.
