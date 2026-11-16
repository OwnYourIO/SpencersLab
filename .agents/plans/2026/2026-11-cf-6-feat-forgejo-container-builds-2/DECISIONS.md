# DECISIONS — cf-6 run -2 (forgejo-container-builds-2)

Append-only log of decisions, rejected alternatives, conventions. Coord/plan write.

Predecessors: run 0 (`…/2026-11-cf-6-feat-forgejo-container-builds/DECISIONS.md`, D1–D8) and run -1
(`…/2026-11-cf-6-feat-forgejo-container-builds-1/DECISIONS.md`, RD1–RD13 + the owner batched round
+ two coord-ruling sections). Nothing here re-decides those except where run -1's shipped bytes are
the subject of the owner's review follow-up.

## 2026-11-13 — the trigger for this run (owner review follow-up, not a new request)

- While reviewing the branch diff vs `refs/heads/main` the owner commented on
  `.forgejo/workflows/containers-build.yaml:88` (`fetch-depth: 0`): *"Most of the things that need to
  get built aren't the top commit, and I'm worried fetch-depth: 0 will mask those changes. A round of
  research on how others address this is needed."* Everything else on the diff was called reasonable,
  so this run's scope is **that one line and the detection contract behind it** — not a re-open of C02/C03/C04.
- Card 6 moved Review → Executing on this follow-up; claim is the derived set `[CICD]` (free at claim
  time, taken exclusively, setId 9cb75b2c). Release point stays the move back to Review.

## 2026-11-13 — model routing detour: OpenRouter flash for every tier (owner ruling, in-session)

- Ruling (in-session, 2026-11-13): *"you'll have to use the OpenRouter flash for all subagents."*
  Every run -2 subagent launches on `openrouter/qwen/qwen3.8-flash`, not the local arena.
- Why it moved: the 2026-11-09 ruling (`Qwen Flash` + `Local` → `gpu-ai/qwen3.8-flash-next-strata-q4`)
  could not execute in this window — the `-strata-q4` first fire returned `connection refused` and the
  retry was `cancelled`, twice in a row on the same launch (the cold-arena failure mode run 0 and run -1
  each logged). AGENTS.md records that the runner-model literal moves **only** by a fresh user ruling;
  this is that ruling, and it is scoped to subagent routing for this run.
- Lands as: `kickoff.models` in STATE.json for run -2 + every launch message. It does **not** rewrite
  the `pipeline-models` / `pipeline-kickoff` / `boards` rule sources — those still carry the q4 route,
  and if the owner wants the OpenRouter flash to be the standing route for this combo that is a separate,
  rulesync-sourced change with its own `tests/pipeline-models/surface.sh` re-pin. Flagged, not done here.

## 2026-11-13 — surface: run -2 reuses run -1's worktree and branch

- Same reasoning as run -1's deviation: runs 0 and -1 exist only as local commits on
  `cf-6-feat-forgejo-container-builds` (never pushed, ~18 commits over `main`), and the line under
  review lives in those bytes. New folder only: `…-2/`. Nothing is pushed — `Deployment` stays
  unchecked on the card, so this run is commit-only as well.

## 2026-11-13 — research verdict on the owner's literal sentence (facts, from EXPLORE.md + RESEARCH.md R1)

Recorded here because it is the answer the owner asked for, and because the fix package is derived
from it. Full citations are in `RESEARCH.md` R1.

- **`fetch-depth: 0` cannot mask non-tip changes; it is what makes them visible.** The detector diffs
  `git diff --name-only before sha` — a *tree* diff across the whole push (`scripts/forgejo-container-detect.sh:44-45,52`).
  Removing the line puts `actions/checkout` at its documented `fetch-depth: 1` default, where the range
  endpoints do not exist locally and the step fails **loud** (`fatal: bad object`, exit 128, measured in a
  depth-1 clone) — never a silent partial set. So the causality in the owner's worry is inverted.
- **The multi-commit case is already correct**: probed live — a container changed in the *middle* commit
  of a 2-commit push IS detected (output `["beta"]`, exit 0).
- **Payload reality settled from v15.0.10 source (exhaustive producer sweep):** a push event always
  carries `forgejo.event.before` — the previous tip, or the all-zero OID on branch creation; no producer
  in the tree sets it empty (`cmd/hook.go`, `routers/private/hook_post_receive.go`,
  `services/actions/{notifier,notifier_helper,context}.go`, `modules/structs/hook.go`). Branch deletion
  notifies nothing at all.
- **The trigger's own path filter also walks the whole range** (`diff-tree --name-only --root -r before head`,
  `modules/git/repo_compare.go`), so a run dispatched for a middle-commit change is dispatched *correctly*;
  Forgejo's prose doc line ("the pushed commit") is the misleading part, not the behaviour.
- **What genuinely narrows to the tip**: an empty/missing `before` falls into the all-zero first-push
  branch (`detect.sh:38` strips empty as well as zeros) → `HEAD^..HEAD`. Source says payload reality
  cannot produce it, so the residual risk is a typo'd accessor or a future regression — which is exactly
  what the next two items make unpunished today.
- **The real gap is test coverage, not the code:** no leg mentions `fetch-depth` (deleting L85–88 keeps
  all 29 legs green) and every d-leg fixture is exactly one commit wide, so narrowing the range to
  `$SHA~1..$SHA` also survives 29/29. The property the owner is worried about is *present but unpinned*.
- **And the empty outcome is quiet:** the port dropped the predecessor's `echo "Changed containers: …"`
  (`main`'s `docker-build.yaml:85`), and the `!= '[]'` guard skips both build jobs with no log reason —
  a green run that built nothing is indistinguishable from a run that found nothing.
- First-push asymmetry, stated for the record: the trigger goes **fail-wide** (`--root` → every file
  counts) while the detector's fallback goes **fail-narrow** (tip-only). Designed, low impact behind
  `branches: [main]`, but untested.

## 2026-11-13 — run -2 planning rulings (agent-plan; batched-question rule — every guess is also an Open question in the plan)

Evidence keys: X-2 = this folder's `EXPLORE.md`, R1 = this folder's `RESEARCH.md` R1, RD*/owner round = run -1's
`DECISIONS.md`. The research verdict above is the factual baseline; nothing here re-argues it.

- **RP1 Scope: this run is a pin-and-legibility change, not a rescue.** No range math is changed:
  `git diff --name-only "$a" "$b"` stays as shipped (middle-commit detection is measured, X-2 §2). In:
  B1 (keep `fetch-depth: 0` + say why), A4 (annotate the fallback), A5 (separate empty from all-zero),
  B4 (echo the set and its endpoints; `::warning::` on an empty push/PR set), and the legs that make
  the owner's fear shape red offline. Out: run -1's C02/C03/C04 decisions, guards, tag math, docs.
- **RP2 One chunk (M), not two.** The candidate split was "behaviour" + "the suite's new legs", but
  `agent-test` authors every chunk's legs in one session *before* dev and `tests/**` is read-only to
  the implementer (run -1's C03/C04 accepted that deviation twice), so a "legs chunk" would carry no
  dev-side work — and a pin is not reviewable apart from the bytes it pins. Reviewer scoping is
  served instead by the `t d` loop subset (30 ok) and the mutation table in `chunks/C01.md` AC2.
- **RP3 Package = the researcher's cheapest honest one: B1 + A4 + A5 + B4.** Rejected: **B2**
  (depth-1 + targeted fill — 172 ms vs 1,849 ms is a saving nobody needs at lab scale, it re-implements
  checkout v6's own ref-race guard, and it couples to `allowAnySHA1InWant` staying enabled); **B3**
  (`filter: blob:none` — couples correctness to `--no-renames`, unverified on-platform); **B6**
  (a cadence/rebuild-all hatch — `workflow_dispatch` already names its list and a scheduled full
  rebuild starves the capacity-1 runner). B2/B3 and A2/A3/B5 stay alive as OQ-a…d owner calls,
  deferred with reasons in the plan, not silently dropped.
- **RP4 A5 adopted (empty `before` ⇒ red), and it is the only green→red change in the run.** Source
  sweep says an empty `before` cannot arrive from a git-push/mirror event at v15.0.10 (R1 §1), so the
  only way to see one is a wrong accessor or an unexpected event routed into the push arm — precisely
  the silent tip-only shape the owner fears. Rejected alternative: warn-and-keep-scanning-the-tip (that
  *is* the defect). Rejected: making it a `::warning::` only. Failure channel = the script's existing
  `die()` (exit 2) — OQ-m. Accepted-cost statement: with zero live runs ever executed (X-2 §8) nothing
  documented can break, and a payload surprise now self-announces, which is why the optional live probe
  (H-P1) stays optional.
- **RP5 Channel law: detector stdout stays exactly the one JSON line; every new diagnostic goes to
  stderr.** stdout is the captured carrier for `changed=$(…)` → `changed-containers=` (t10's
  assign-then-emit), so a stray echo inside the script would poison the matrix. d11 pins stdout purity;
  the workflow-side echo (B4) is the sanctioned stdout writer and it must not re-inline the command.
- **RP6 Legibility shape (B4 + OQ-e):** always echo `changed containers: <set>` with the event and the
  endpoint values it holds; `::warning::` only when a **push or PR** resolves to `[]`; nothing extra for
  `before == sha` (a genuinely empty range) or an empty dispatch list (both correct semantics). Claims
  stay log-line-only: v15.0.10 has no annotation/summary store and runner v13.2.0 does not interpret
  `::notice::` (R1 §7.2/§7.3) — reviewers must not let any surface call this a UI chip.
- **RP7 Legs 5 and 8 taken** (the launch left them to judgement): **t15** extends the `|| true` ban to
  the detector's `git diff` line — scoped, with `next-n`'s tolerated `grep … || true` (L88) named as
  exempt so no later hand "cleans" it; **d13/d15** pin the loud-failure postures that X-2 §3 measured
  by hand and that today have no teeth. **d14** pins the PR two-dot over-detect as the *chosen* posture,
  so B5 can only arrive as a deliberate re-pin, never as drift.
- **RP8 t13 (accessor byte-pin) is accepted with its limit stated in the leg text.** It cannot prove the
  payload carries `before` — only R1 §1's source chain (and optionally H-P1) do that. Pinning it is
  cheap insurance for exactly the typo class A5 catches at runtime; r1's byte-constant discipline is the
  model.
- **RP9 Fixture plan over mutation-testing the 29-leg baseline:** X-2 §6's mutation table says
  `$SHA~1..$SHA` and deleting L85–88 both survive today. New wide fixture **fix3**
  (A creates → B changes `beta` → C changes `alpha` → E tip-only README) reddens both narrowings
  (d9/d10) and separates the fallback from the event range (d11); **fix4** pins the PR posture (d14).
  Existing d1–d8 stay byte-stable so run -1's regressions remain legible (RD13's economics hold).
- **RP10 Cosmetic close-out folded in (the one exception to "no re-open"):** the detector header still
  says "ghcr" at L4/L13 where `next-n` reads both registries — run -1's final review explicitly asked
  "whoever next touches the script". Comment-only, zero legs affected.
- **RP11 No docs/rulesync surface this run** (OQ-l): x3's pins and the gated docs stay green
  untouched; nothing in `skills/container-creation/SKILL.md:57` becomes false. So `rulesync generate`
  is NOT RUN — and `AGENTS.md` is generated, never hand-edited. The dev-renovate MCP line runs only
  via the inline `configContent` route (no worktree visibility — inherited FRICTION), and it is a
  regression check, not a change gate: run -2 edits no `renovate.json` byte.
- **RP12 Re-verification of the post-merge base (the launch asked for it).** `main` is now
  `4cac77725`; since run -1's verified `0d9b41785`, two commits touch our surface: `06b352423`
  (`renovate.json` limits → `0`/`0` — verified `x2` still green) and `93e37f9d2` (**new
  `.forgejo/workflows/renovate.yaml`, guarding `vars.ROLE == 'dev'`**). A `git merge-tree` replay of
  `main` × this branch measures **28 ok / 1 FAIL: g1** — run -1's repo-wide membership leg reddens on
  that cf-135 byte. Ruling: NOT this run's surface (it would re-open the guard convention the owner
  fenced off) — surfaced as **OQ-j** with the measurement, the C01 gate is defined on the branch's own
  base `a6e493b78`, and no mid-run rebase onto current `main` without the coordinator's word. Neither
  `containers/` (13 dirs, re-counted) nor the gated docs moved; the branch still lacks
  `renovate.yaml`, so today's 29 ok at `762cfec1d` is honest for this base.
- **RP13 Card-6 intake answers are taken as given** (Services `dev`, Type `feat`, Lifecycle minus
  `Deployment`, HITL `Final Review`): commit-only class, nothing pushed, and the plan's human legs
  restate that run -1's H1/H2/H3/H7/H8 stand untouched — including the lead-the-hand-off fact that
  until the H3 PATs land, any `containers/**` merge to `main` goes loudly red at the login step.

- **RP14 Ground measured, not inherited.** The blind spot was re-created by execution in a scratch
  copy (`git archive HEAD` → `/tmp/opencode/cf6r2-teeth`, `git init`): deleting L85–88 → **29 ok**, and
  rewriting the detector's range to `"${SHA:-HEAD}~1" "${SHA:-HEAD}"` → **29 ok**. The package was then
  prototyped the same way and is **additive**: the B4 echo line, the detector's stderr range +
  `::warning::` lines, and the A5 `[ -n "$before" ] || die …` guard each left the full suite at
  **29 ok**, and A5 makes an empty `before` exit **2** with a named message. Fixture expectations for
  the new legs were measured with `HEAD`'s detector (`/tmp/opencode/cf6r2-fixture`): `A..C` ⇒
  `["alpha","beta"]`, `B..C` ⇒ `["alpha"]`, all-zero ⇒ `["alpha"]`, empty ⇒ `[]` exit 0, garbage ⇒ 128,
  PR empty `BASE_SHA`/`HEAD_SHA` ⇒ 128, PR two-dot base-ahead ⇒ `["alpha","beta"]` vs merge-base
  `["beta"]`. Recorded so `agent-test` writes from measured values and dev is not guessing shapes.

## 2026-11-13 — owner batched-round answers (ONE round) + post-merge ground (agent-plan finalize pass)

Supersede the RP-guesses they answer; RP1–RP14 stay as the trail. The plan of record and
`chunks/C01.md` now carry the rulings; `chunks/C02.md` + `chunks/C03.md` are new.

- **OQ-scope IMPLEMENT** (after one contradictory answer the owner confirmed: *"Implement per Q3–Q6"*) —
  the hardening package ships in run -2: code + legs + docs.
- **OQ-c ANSWERED — keep `fetch-depth: 0` (B1).** B2 (depth-1 + targeted fill) and B3
  (`filter: blob:none`) are considered-and-declined for this run, with the numbers on the record
  (depth-0 = 21.23 MiB / 1,849 ms measured; the fill = 172 ms; blobless = 5.8 MiB). OQ-d (blobless) is
  therefore parked by ruling, not by guess.
- **OQ-a ANSWERED — A1 + A4 + A5.** First push stays `HEAD^..HEAD`; the fallback must log a warning
  naming the narrowing; an **empty** `before` must exit red via the existing `die()` — and because
  `d12` pins "non-zero", **the exact exit code is dev's choice** (RP14's prototype used `die`'s 2).
  A2 (fail-wide) and A3 (merge-base first push) stay deferred: behind `branches: [main]` the case is
  rare, and A2 would enqueue up to 13 matrix builds on a capacity-1 runner.
- **OQ-b ANSWERED — ADOPT B5: the PR arm moves to a merge-base diff, HAND-ROLLED.** Instruction of
  record: `git diff --name-only "$(git merge-base "$BASE_SHA" "$HEAD_SHA")" "$HEAD_SHA" -- containers/`
  — only the `git diff --merge-base` *flag* needs git ≥ 2.43, and the runner image's git is unverified,
  so hand-rolling removes the dependency entirely. **OQ-g (runner git version) is therefore MOOT** —
  recorded as closed-by-ruling, no probe owed. Measured consequences on the scratch fixtures: d14's
  expectation flips from the two-dot `["alpha","beta"]` to `["beta"]`; d1–d8 all stay green under the
  change (a PR whose base is an ancestor has merge-base == base); empty `BASE_SHA`/`HEAD_SHA` stay
  exit 128, and a genuinely unrelated history exits **1** (loud, not silent). Accepted trade: the
  benign over-detect waste is gone, and a rewritten PR branch now goes RED where two-dot quietly worked.
- **OQ-e + OQ-k ANSWERED — BOTH the echo and the warning.** Always echo the changed set + event + both
  endpoints on the step's stdout (predecessor parity with `main:.github/workflows/docker-build.yaml:93`
  `echo "Changed containers: $RESULT"` — the port dropped it); `::warning::` when a push/PR set comes
  back empty; keep the proposed exemptions (`before == sha`, empty dispatch list). Platform truth stays
  in the record: runner v13.2.0 renders `warning`/`error` as log text, and Forgejo v15.0.10 has no
  annotation store and no step-summary render — log legibility, never a UI chip.
- **OQ-l ANSWERED — docs prose NOW** (chunk C03): state the detection contract (whole pushed range for
  pushes, merge-base for PRs, loud-on-empty, first-push tip-only-and-annotated) in
  `skills/container-creation/SKILL.md` + `.rulesync/rules/overview.md`, then `rulesync generate` +
  `--check`; `AGENTS.md` is generated, never hand-edited.
- **OQ-j ANSWERED — MIGRATE renovate.yaml INSIDE run -2** (chunk C02). **RP12's deviation is
  superseded**: the plan is now measured on the post-merge tree, `main` merged in at `7a82dfb21`
  (0 behind / 21 ahead, clean, `renovate.json` auto-merged). **RP2's one-chunk shape is superseded**
  too: three chunks (C01 detection+legs, C02 the renovate guard + cf-135's suite bytes, C03 docs).

### 2026-11-13 — post-merge ground, measured by this finalize pass (all numbers re-taken at `7a82dfb21`)

- What the merge brought onto our surfaces: `.forgejo/workflows/renovate.yaml` (cf-135; `if:
  vars.ROLE == 'dev'` at L43, header L7–8 states the intent — fires only where ROLE is dev, unset fires
  nothing, so its polarity is **narrow-on-unset**, the `main-sync.yaml` class, NOT the containers-build
  widen class) and `tests/services/forgejo-renovate.sh` (9 legs, fail-fast: `fail(){ exit 1 }`). The
  containers suite's `g1` walk now covers **three** `.forgejo` workflows, so its equality-form clause
  reddens on `renovate.yaml`: baseline **28 ok / 1 FAIL (g1)** on the branch (was 29 ok pre-merge —
  RP14's and R2's numbers are void). `.github/workflows` gained `amd-gpu-` and `radiance-render-tests`
  (nine files now); they are outside `g1` (which walks `.forgejo` only) and outside `x4`'s named
  six-sibling fence, so they land on **no** run -2 leg — the render-test surfaces are cf-141/143's own.
  `containers/` is still **13 dirs**; detector, workflow and suite bytes are identical to pre-merge
  (`git diff c5daed362 7a82dfb21` on them: empty).
- **The merge also turned two cf-135 count legs red on OUR branch, before run -2 changes anything**:
  `forgejo-renovate.sh t8` (`need(len(rules) == 9 …)`) and `forgejo-move-config.sh m5` (same pin) both
  answer `packageRules has 10 entries, expected 9` — because run -0's calendar rule is the 10th. Pure
  `main` answers 9 → green; our branch → red. Ruling for C02: re-pin those two constants to 10 in the
  same commit as the guard byte (they are count pins, not behaviour), and re-word the suite header's
  `t3` line and its `GUARD` constant. `tests/renovate/kubernetes-mcp-version-floor.sh k2` (expects 8)
  is **red on pure `main` already** — pre-existing upstream staleness, not our byte, not ours to fix
  (OQ-o).
- **C02's migration prototype, measured**: `if: contains(vars.ROLE, 'dev')` + `GUARD` re-pin + the two
  count constants 9→10 ⇒ `forgejo-renovate.sh` **8 ok / 1 skip (t9 default-OFF probe) / PASS**,
  `forgejo-move-config.sh` **6 ok / PASS**, and `containers g1` **green**. Trap proven: cf-135's `t3`
  sweep forbids the literal token `vars.ROLE` anywhere outside the job `if:` and the diag echo —
  a header gloss writing `vars.ROLE` reddens t3 (`FAIL: t3: vars.ROLE appears outside the job if: guard
  and the diag echo`), while the same meaning phrased "never an exact-value match" stays green. So C02's
  header comment must name the membership idea WITHOUT writing `vars.ROLE`, and its L7–8 polarity sentence
  must survive verbatim in spirit.
- **C01's package prototype, measured**: deleting L85–88 → **29… 28 ok / same red** (blind spot intact);
  range narrowed to `"${SHA:-HEAD}~1" "${SHA:-HEAD}"` → **28 ok** (blind spot intact); adding the B4
  echo + the detector's stderr range/`::warning::` lines + the A5 `die` guard → **28 ok / 1 FAIL**, i.e.
  byte-additive and no existing leg moves, with empty `before` → exit 2 and message, all-zero →
  tip-only + annotation. Merge-base-only variant measured **d1–d8 all green** (P3), so B5 is also
  byte-additive to the existing set.
- **Full post-merge neighbour posture** (for the Commands section): `forgejo-containers-build.sh`
  28 ok / 1 red (g1), `forgejo-main-sync.sh` 8 ok, `pipeline-push-pr/surface.sh` 10 ok,
  `wekan-mcp/tools.sh` 10 ok, `pipeline-models/surface.sh` 9 ok, `dockerfile-pins.sh` 36 ok,
  `forgejo-renovate.sh` 7 ok / red t8, `forgejo-move-config.sh` 4 ok / red m5,
  `kubernetes-mcp-version-floor.sh` 1 ok / red k2, `chart-yaml-legs.sh` 10 ok / red k5+k10,
  `forgejo-ssh-gateway.sh` + `forgejo-ssh-audit-trail.sh` red on the `storm-runs/` clause. All of those
  last five reds are pre-existing or cf-135-count-shaped, and C02 clears exactly two of them.
- **Model routing, corrected as a fact**: `main`'s `pipeline-models` still maps `Qwen Flash` + `Local`
  → `gpu-ai/qwen3.8-flash-next-strata-q4`, with `openrouter/qwen/qwen3.8-flash` documented as the
  fallback when the local route is unavailable. This run's cold-arena failure (`connection refused` /
  `cancelled`, twice) is exactly that unavailability, so the OpenRouter route is **rule-conformant**,
  not a new ruling; the owner's in-session word stands as the authorisation, and no rulesync rule
  source moves here.

- **The agent-surface scope fences reddened on *uncommitted* plan work, not on run -2's content.** With
  the folder uncommitted, `agents-md.sh c7`, `rulesync-surface.sh c8` and `gate.sh t14` fail with
  "path outside the ticket's in-scope set" naming our own plan files; replayed in a scratch repo **with**
  a commit, those three legs pass and only `main`'s pre-existing staleness remains (`c11` runner-model
  pairing, `t17` coord-family contract, `c19` custom-field count — each also red on a pure-`main`
  replay). Recorded so no agent "fixes" a fence by touching another ticket's rule source: the commit is
  the coordinator's job and it clears class (i) by itself.

### 2026-11-13 — the renovate guard's semantic consequence (state it plainly; re-confirmation asked)

- `contains(vars.ROLE,'dev')` is not purely a shape change. **A `dev,prod` instance starts running the
  daily Renovate pass where `== 'dev'` did not.** Infra (`ROLE=prod`) and the dev instance (`ROLE=dev`)
  behave exactly as before, and unset stays narrow/fail-safe (the `main-sync` class survives because
  bare `contains()` on an unset var is false — R1 §2's truth table). The interaction that matters:
  **run -1's H1 leg** (infra `ROLE` → `dev,prod` after C04 merges) would, with this migration, also turn
  on Renovate on infra — one more PR-opening writer on the repo. Best guess (OQ-p): accept it — infra is
  the box with the proven runner, cf-135's intent ("the dev-stage instance") reads as a role test, and
  the alternative is a dedicated per-instance variable, which OQ-8 already rejected. Surfaced, not decided.

### 2026-11-13 — finalize-pass rulings (agent-plan, after the owner round + the merge)

- **RP15 Three chunks, not one.** The owner's answers widened the run past the detector: OQ-j put
  `renovate.yaml` + cf-135's suite bytes here (C02) and OQ-l put prose + `rulesync generate` here (C03).
  RP2's single-chunk reasoning still holds for the detection package (legs are `agent-test`'s, `tests/**`
  is read-only to dev, and a pin is not reviewable apart from the bytes it pins), so C01 stays whole;
  C02 and C03 are split because each is a surface a reviewer could reject while approving its neighbour
  (a guard byte on another card's file; docs prose + regen). Ids are new — nothing from run -1's C02/C03/
  C04 is re-used or re-numbered, and C01's name keeps its meaning from the draft.
- **RP16 x5 is the docs leg.** OQ-l made docs in-scope, so the prose needs teeth or it drifts the same
  way the echo did: one leg, marker-keyed (range / merge base / first push / announced), line-number-free,
  with the negative clause that forbids UI-annotation claims. Written red-first; C03 turns it green.
- **RP17 `d14` and `d15` are red-by-design, not pins** (this corrects the draft's 3-red arithmetic to
  5 red in C01, 6 across the run): with the shipped two-dot arm the PR pair `M↔H` answers
  `["alpha","beta"]` where the merge-base pin demands `["beta"]`, and an unrelated base/head pair exits
  **0** where the pin demands non-zero. Measured, both directions.
- **RP18 OQ-g is closed as MOOT by the OQ-b wording** — hand-rolling `git merge-base` removes the
  git ≥ 2.43 question entirely, so no version probe is owed by anyone. Recorded so nobody re-opens it.
- **RP19 Legibility ordering became a hard design rule.** Measured: `git merge-base` on an
  unrelated/rewritten pair exits **1 and writes nothing to stderr** — so the endpoint line must precede
  the call or the red run is undiagnosable. That is why C01's task list puts the stderr endpoint/range
  line BEFORE the git call, and why d15 pins both the exit and the message.
- **RP20 Count re-pins are ours, other cards' reds are not.** `forgejo-renovate t8` /
  `forgejo-move-config m5` (`packageRules == 9` → 10) are red because **our** branch carries the
  calendar rule, so C02 owns them. `kubernetes-mcp-version-floor k2`, `chart-yaml-legs k5/k10` and the
  two `forgejo-ssh-*` suites are red on `main` independently of run -2 → recorded, not touched (OQ-o).

## 2026-11-14 — run -2 complete: the verdict the owner asked for, and what was NOT carded

- **The owner's comment answered with bytes:** `fetch-depth: 0` cannot mask non-tip changes — it is what makes them visible (`before..sha` is a tree diff over the whole range; at the checkout default of 1 the endpoints are absent and the step fails LOUD with `bad object`/128, never silently partial), the payload always carries `before` (v15.0.10 producer sweep), and the trigger's own `paths:` filter walks the whole range too. **But the follow-up was worth making**: the contract was present-and-unpinned (deleting the line OR narrowing to the tip both kept 29/29 green) and the empty outcome was silent (the port had dropped the predecessor's changed-set echo). Both are now closed with teeth.
- **What was NOT carded, deliberately:** the final review recommended follow-up cards for OQ-o's four foreign red families, the `pipeline_claim` engine defect (a `failed` claim leaves its holder locked out — unable to revive by heartbeat, unable to re-take the card, the only exit being release-then-re-claim), NB-1's stale matrix anchor, and the four prose nits. **Card creation on this board is owner-owned** — the "Create follow-up cards" HITL item was deleted at run 0's write-back — so they are recorded here and on the card instead, exactly as in run -1.
- **The one thing this run changed for real operators** (owner re-confirmation carried to this pause as OQ-p): migrating `renovate.yaml` to `contains(vars.ROLE,'dev')` means a `dev,prod` instance runs the daily Renovate pass and opens its own dependency PRs, where equality withheld it. **Nothing moves today, twice over** — the instances execute `main`'s copy (still equality, this branch is unpushed), and infra `prod` / dev unset / unset all evaluate false under BOTH forms. The rule itself is unchanged (infra flips only after the convention merges); only the flip's consequence widened, so H1 is now a two-effect decision.
- **Lock honesty:** the CICD claim went `failed` at 2026-11-13T21:47:35Z (the long Test-Writing session outran the heartbeat). Verified before acting, one sanctioned question, owner said continue; the takeover path was BLOCKED (`already_held` naming this session's own failed set) so the only exit was `pipeline_release` + immediate re-claim under the card-id key. That release necessarily used `outcome: abandoned`, which the tool's vocabulary forces even though nothing was abandoned — the card stayed in Executing and the run continued. Recorded on the card so a future reader does not misread that event.

## Deferred (run -2)

- The owner legs inherited from run -1 are unchanged and still unexecuted (H1 merge-before-flip,
  H2 dev ROLE, H3 the two non-admin PATs + `FORGE_PUSH_TOKEN`, H7 the two-registry smoke, H8 Cleanup
  Rules). Nothing in run -2 touches them; a `containers/**` merge to `main` still goes loudly red until
  the PATs exist.
- `toJSON(forgejo)` one-dispatch live probe: optional owner leg only. The payload question is
  source-proven, so this buys live confirmation, not a decision.
