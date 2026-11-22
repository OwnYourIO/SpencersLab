# Decisions — cf-6-feat-builder-bootstrap-1 (lane scope-reduction: build image only)

Append-only. New entries at the bottom.

## Kickoff

- 2026-11-22 human: "Ok, the bootstrapper doesn't work when blank is entered. It should really only be responsible for building the builid image anyway." Grounded by coord BEFORE recording as defect-or-design: the PR merged (f236be07f labels / ae7c7e64b bootstrap / 1d6d56dc0 records; origin/main's builder-bootstrap.yaml byte-identical to 23c444f4d — `git diff` empty), and blank-input ⇒ no-op is the SHIPPED silent-empty law working exactly as the human-ruled OQ-2 shape specified it (input '' ⇒ no-op, `all` ⇒ everything; b8-proven). NOT a bug; a design the owner has now decided they don't want. The specific dispatch's run record was NOT independently verified (curl/webfetch denied at the coord floor; anonymous Actions API unreliability known — FRICTION) — the owner's report + the shipped semantics fully explain the observed no-effect; the plan's first live probe should list recent builder-bootstrap runs to close that gap.
- 2026-11-22 human ruling (SUPERSEDES the base run's OQ-2 "general any-container bootstrap lane"): the lane is responsible ONLY for building/publishing the BUILD IMAGE = `containers/forgejo-runner` (the baked job image whose absence IS the paradox). Consequences: the dispatch input disappears entirely (no names/containers param, no `all`, no silent-empty trap — a dispatch always does the one thing), the matrix + detector-consumption legs disappear, and the docs paragraph committed today that says "(re)mints any named container" must be reworded to the single-purpose truth (AGENTS.md moves with .rulesync again, twin regenerated). NOT re-litigating the base run — its rulings stand as history; this is owner correction after live use, normal iteration.
- 2026-11-22 coord: surfaces kept UNCHANGED by the reduction (recorded so the plan doesn't drift them): dispatch-only (OQ-3); runs-on ubuntu-22.04 public label (b2 paradox guard — the whole point survives); narrow bare contains(vars.ROLE,'prod') guard (fail-safe calendar lane); calendar law mirror (walks before push, union max, three tags, ghcr→own, no skip-if-exists — plan to rule whether :latest/:main ride too; recommendation YES for parity); P4' closed credential surface (b6); detector + containers-build byte-untouched; OL0–OL9 owner legs with ONE change: OL2's dispatch takes no input (blank IS the button now — the trap the owner hit becomes impossible). Urgency noted: the instance is STILL dead-on-arrival for forge builds until this lands and one dispatch mints 26.11.1 (both registries verified empty of it; the blank dispatch minted nothing).
- 2026-11-22 coord: folder seeded; branch `cf-6-feat-builder-bootstrap-1` minted from origin/main 1d6d56dc0 (worktree established; AGENTS.md delta seen on checkout = the unrelated cf-126 dispatcher landing, ride-in, not our change). Models: flash every tier (standing directive). Committing: coord, compact-shape pathspec commits (standing ruling). Plan launching now — expect a tight single-chunk rework plan; genuine forks (rolling tags; keep-any-detect-call-for-parity) go through ONE batched owner round per the no-questions rule.

## Planning (2026-11-22, agent-plan on the flash route)

- 2026-11-22 plan: **GROUNDING RE-VERIFIED LIVE, all three probe families answered** (plan session
  ~17:10–17:25Z @ 1d6d56dc0): (1) registries STILL empty — ghcr token 403 (absent-vs-private),
  BOTH instance registries' org pkg-api 200 `[]` and tags/list 401-anon (package absent) ⇒ the
  owner's earlier dispatch minted NOTHING and the first reduced-lane dispatch legitimately mints
  **26.11.1** = exactly what the merged run-1 labels pin; (2) Actions-API gap closed as far as the
  anonymous surface allows: builder-bootstrap total_count **1** (id 222, post-merge), row metadata
  null-sparse + jobs endpoint unreadable anonymously — the run's INPUT value stays inconclusive
  and design-irrelevant (outcome registry-proven; the input surface dies); not spun further per
  launch. (3) shipped-suite baselines re-run: bb suite 20 ok green, ci-surface t1 five-set green +
  ONLY-t4-red carried. NOTED: curl/webfetch-capable probes WORK in this plan session (the coord-
  floor curl denial did not extend here) — no probe had to be routed downstream.
- 2026-11-22 plan: **R1/R2 — the input and the pair die**: `on: workflow_dispatch` with NO `inputs`
  section anywhere (b1 parses the whole doc for any `inputs` mapping + accessor greps; battery bt9
  re-purposed to the TRAP PROBE: restoring the input reddens b1 by construction); single job
  `publish` (name kept — b5/b6/b10 anchors, minimal honest move), bare membership the ONLY `if:`
  clause (the `!= '[]'` matrix-skip clause banned — a dangling reference with no matrix). Rejected:
  keeping `containers` with default `forgejo-runner` — a defaulted input is the trap's door ajar;
  the owner ruling's "no dispatch input at all" read literally.
- 2026-11-22 plan: **R3 — "no detector consumption" adjudicated as: detect-mode DIES, next-n
  STAYS** (OQ-1, best-guess-ruled): the detect step existed ONLY to gate the dispatch list; with
  no input there is nothing to gate. The two registry walks' month math (`next-n`, YYMM env) is
  part of the SURVIVING calendar-law mirror the ruling names ("both walks before push, union
  max"); inlining it would fork the arithmetic away from containers-build's proven single source
  (P6 reuse law) for zero behavioral gain. b7 flips halves: next-n×2 REQUIRED, detect-mode call
  FORBIDDEN (its return = the general-lane sneak-in, bt7-probed).
- 2026-11-22 plan: **R4 — the fixed target forces the b2 paradox-pin to MOVE**: the shipped b2 bans
  raw `ownyourio/forgejo-runner`, written when the file could only ever name the image as its
  RUNNER; the single-purpose file must name it as its PAYLOAD. The ban moves to the scheduling
  surface (every runs-on == ubuntu-22.04, none containing `forgejo-runner` or a baked label; zero
  docker://). b8 REPURPOSED (its behavioral detect-shape subject evaporated): pins the ONE
  `docker build` with context `containers/forgejo-runner`, both image refs naming forgejo-runner,
  and ZERO name-carrier shapes (variable/matrix/loop) anywhere.
- 2026-11-22 plan: **R5/R6 — rolling tags YES, arms ghcr+own only**: the trio (`:yy.mm.N`+`:latest`
  +`:main`) × two targets survives byte-parity with the release arm (containers-build L338–339
  re-read — identical shape shipped in the base lane; parity argument CLOSED, launch recommendation
  was already implemented). P4' closed credential surface (b6) byte-stable; no-peer law unchanged;
  OL3's manual dev push stays the accepted permanent cost.
- 2026-11-22 plan: **R7 — F1 ADOPTED-CLOSED here** (base review's advisory: b5's skip-if-exists ban
  was LEXICAL; a semantic manifest-inspect guard would pass everything): this suite rewrite is the
  deferred item's stated natural home (next `tests/**` touch), so b5 gains the SEMANTIC pin —
  every `docker push` unconditional inside its attributed `for` chain, plus a battery probe that
  wraps one ⇒ b5 red. Removed from STATE.deferred; the shipped file is already push-unconditional,
  so this costs DEV nothing and closes the deferral with reason (launch recommendation YES adopted).
- 2026-11-22 plan: **R8/R9 — fence and doc deltas are small and forced**: ci-surface t1 five-set
  UNCHANGED (file persists; re-verified green this session) — the suite file joins the byte-proof
  list; the residue inventory for the general-lane wording is exactly six live surfaces (AGENTS +
  overview twin pair, SKILL L114+L119, workflow header L1, suite header L3) — all move or die in
  the change; the README was ALREADY written single-purpose-true by the base deviation-2 fix ⇒
  byte-untouched, pinned by b9's re-read; the residue grep is scoped to LIVE surfaces — plan-record
  history (base ticket folder, this folder's kickoff entries) keeps the superseded wording as
  dated append-only record, which is truth-about-past, not a lie-about-now. Running the bar grep
  early surfaced two required exemptions, both recorded: `containers-build.yaml` L78 "name the
  containers" describes ITS OWN dispatch input (true there, file FORBIDDEN) and the rewritten
  SUITE legitimately embeds the banned phrases inside b9's prohibition tuples (teeth, not lies) —
  the pin greps exactly the five lane-wording surfaces.
- 2026-11-22 plan: **R10 + owner legs re-sequenced for real**: single new commit on this branch
  (no staged-set to protect this time), coord compact-shape commit, push/PR/merge owner-owned;
  PR-body caveats: lane is single-purpose (base OQ-2 supersession note) + inherited run-1
  freshness-prose caveats still ride. OL2 now takes NO INPUT (blank IS the button — the trap is
  structurally gone); month-cross risk restated for the MERGED pins: a December dispatch mints
  26.12.1 and the run-1 label pair (both sites, already on main) needs the owner amend PR to the
  actually-minted literal — OL3 second, never predicted. Genuine forks left for the owner: exactly
  one (OQ-1, best-guess ruled and shipped into the plan), per the no-questions rule.

## Approval + waves (2026-11-22, coord)

- 2026-11-22 coord: PLAN RECORDED + APPROVED straight (no second owner round — OQ-1 explicitly non-blocking, "adopt the alternative only on the owner's word", standing implement-directive governs; owner-vetoable at PR). R7 noted with satisfaction: F1 closes at exactly its stated natural home, and at zero cost to DEV since the shipped file is already push-unconditional. R4's forced b2-ban relocation and R9's two grounded exemptions (containers-build self-description; suite prohibition-tuples-as-teeth) are recorded rulings, not drift. `plan_status`: draft → **approved**. TEST wave launched (rewrite forgejo-builder-bootstrap.sh to the target leg list — RED-vs-SHIPPED from authoring this time (the file EXISTS and must fail the new no-input/single-job/fixed-context pins until DEV lands); ci-surface byte-frozen with proof; the trap-probe bt9 + semantic push-pin are the load-bearing new teeth).
- 2026-11-22 coord: WAVES RECORDED — test rewrite (authoring bar red-vs-shipped at exactly the 7-leg DEV target list, sim 20/20, F1 absorbed as the semantic push pin), dev landing (all 7 reds closed together; body byte-identical to sim walk; rulesync twin-only; README verified-unchanged; escalated the b4 backtick-noise bug it could not touch), test-repair (noise class closed — the suite's first in-tree landing green, zero stray stderr), chunk review APPROVE (independent parses, b1 fool-attempt failed as designed, R7 teeth standalone, g1 cross-suite; header count nit → test-repair2: fixed at BOTH halves — the phantom sixth name was the twin-pair double count; header now equals the tuple's five literal members). FINAL WHOLE-PLAN REVIEW APPROVE (fresh full bar; one-change invariant replayed in BOTH half-move directions; live registry re-probe: still zero 26.11.1 everywhere, first bare dispatch legitimately mints the pinned literal; supersession clean; F1 RESOLVED at natural home). `plan_status`: approved → **complete**. Hygiene nits fixed pre-commit: STATE duplicate `plan` key removed (lesson booked: key-uniqueness belongs to the parse check), FRICTION.md seeded. Landing commit next: 5 paths + 5-file ticket folder, explicit add, compact message; PR body carries the OQ-2 supersession note + caveat ⑤ + month-cross + OL2 bare-dispatch. Foreigns stay out: .pytest_cache (ignored), stash@{0} concurrent ref.
- 2026-11-22 coord: LANDING COMMITTED — `fab419cb1` (10 files: workflow, overview, AGENTS twin, SKILL, suite + the 5-file ticket record). Commit-shape calibration refined the same day: two long -m paragraphs were denied even fully-ASCII while a subject-only landed — the floor limit is TOTAL COMMAND LENGTH (~>700 chars), not -m argument structure; run-1's two-`-m` success sat under it, this run's draft exceeded it. Full law/body content lives in the committed ticket folder and must be restated in the PR body at push (OL package + OQ-2 supersession note + run-1 caveat ⑤ + month-cross). This booking line + the STATE landing fields ride the record-tail commit next.
