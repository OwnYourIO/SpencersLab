# PLAN: builder-bootstrap-2 — forge-only lane (READ and PUSH, OQ-1 ruled B) + fleet credential alignment
feature: 2026/2026-11-cf-6-feat-builder-bootstrap-2
status: draft — v2, the two-owner-corrections run after the reviewed-and-merged run -1;
OQ-1 RESOLVED by the owner this round: **OPTION B — forge-only WALK** (supersedes the v1
option-A best-guess; the [B] deltas pre-written in chunks/C01.md are now THE shipped shape).
Model routing: every tier `openrouter/qwen/qwen3.8-flash` (kickoff STATE, standing directive).

## Goal
Land the two human rulings of 2026-11-22: **R-A** — the ghcr push credential is `PUSH_TOKEN_GH`
fleet-wide; every live occurrence of the wrong `GHCR_PUSH_PAT` name moves with the file and the
suite legs that pin it. **R-B + OQ-1=B** — the builder-bootstrap lane is the instance registry's
alone: its ghcr login, ghcr push chain, ghcr credential reference AND the ghcr calendar
READ-walk all die — the calendar N is a single-registry walk on the instance registry — the
closed credential surface shrinks to secrets {FORGE_PUSH_TOKEN} × vars {ROLE}, and the law/docs
trio states the single-registry truth (no parity claim) in the same-change shape.

## Out of scope
- Re-litigating R-A/R-B/OQ-1=B or the surviving run -1 rulings (no-input dispatch, ubuntu-22.04
  paradox guard, narrow prod guard, calendar law SCOPED to one registry, P4' no-peer posture —
  B shrinks the closed set by owner word, it does not reopen it). Option A is DEAD as a
  proposal — recorded, do not re-offer.
- containers-build's DUAL-publish law (ghcr + own release arm, two-registry union walk) —
  untouched by R-B; it remains the dual-registry authority for every other image and for THIS
  image's automatic lane; only the credential NAME moves there (R-A). The PR-arm law, the
  detector script, main-sync/release/renovate workflows (already correct `PUSH_TOKEN_GH` users),
  `.github/**` (GitHub-native `secrets.GITHUB_TOKEN` builder — different platform namespace, not
  an instance secret, fact 4), `charts/**`, `services/**`, `custom-values/**`.
- Any live dispatch/push/merge; readonly probes only. Registry mutation and secret-scope work is
  owner-side (OL legs below).

## USER-RULED asks (recorded verbatim in STATE.kickoff.human_rulings)
1. R-A: "GHCR_PUSH_PAT should match what's already used - PUSH_TOKEN_GH."
2. R-B: "if I'm honest, the bootstrap build only should go to the Forgejo instance, not github."
3. OQ-1 answer (this round): OPTION B — forge-only walk; the lane reads ONLY the instance
   registry for the calendar N AND pushes only there; docs say exactly that, no parity claim.

## Verified facts (plan session 2026-11-22 ~19:00–19:35Z, read-only + offline suite re-runs;
fact 9 re-aimed at B in the v2 rework; B-target SIM in fact 10)
1. **Run -1 is MERGED, not unmerged**: `origin/main` tip `2b11120a8` carries run -1's two
   commits as `adc12c767`/`2b11120a8` with IDENTICAL patch-ids (`3f0ed07b6…`, `b31933ae1…`);
   `git diff HEAD origin/main` EMPTY; local `main` == `2b11120a8`. Run -2's commits land atop
   `d92d0814d` on the same branch (owner's view of run -1's SHAs preserved; trees equivalent, so
   the PR diff is exactly run-2's hunks). **BASE for this run = `2b11120a8`** (resolve-checked)
   for byte-proofs AND `GPU_RUNNER_DIFF_BASE`.
2. **g7 consumes nothing**: run -1 touched only workflow/docs/suite/ticket surfaces (git show
   --stat) — zero lines under `charts/forgejo-runner`, `services/dev`, `custom-values/dev`; gpu
   suite re-ran LIVE **19 ok at BOTH candidate bases** ("0 docker:// lines at cap 8"). Run -2
   touches no g7 path either — the union-vs-own-diff worry is moot on facts.
3. **R-A inventory — every occurrence, file+line (grep over the nine launch-named surfaces)**:
   WRONG name `GHCR_PUSH_PAT` (7 files):
   - `.forgejo/workflows/containers-build.yaml:37` (credential comment) + `:182` (release-arm
     `docker login ghcr.io -u OwnYourIO` — the latent bug, never executed: every run dies
     upstream at detect-changes; the file's ghcr WALK (L264+) is anonymous-pull-token, so the
     rename is EXACTLY 2 lines + t7's legs).
   - `.forgejo/workflows/builder-bootstrap.yaml:98` (lane login — DELETED by R-B/B; the name fix
     is deleted there, not renamed — C01).
   - `skills/container-creation/SKILL.md:109` (fleet credential sentence → renamed in C02).
   - `tests/services/forgejo-containers-build.sh:426,428,432,433,442,445,455` — ALL inside leg
     **t7** (verified): the 41-suite pins the workflow text → t7 rewrites WITH the file.
   - `tests/services/forgejo-ci-surface.sh:171,187` — **t5**'s comment prose + SKILL presence
     tuple. This OVERTURNS run -1's "ci-surface byte-frozen" framing for run -2: t5 actively
     REQUIRES the wrong name in SKILL (rework ruling RR6, evidence-read, not drift).
   - `tests/services/forgejo-builder-bootstrap.sh:71,619-620,672` — leg **b6**; mooted by B (the
     rewritten b6 bans BOTH credential names in the lane file).
   ESTABLISHED name `PUSH_TOKEN_GH` (proof it is the instance's shipped GitHub-side secret):
   `main-sync.yaml:43` (push-gh) + `release.yaml:272` (CR_TOKEN), both live and repeatedly
   executed, pinned green by `forgejo-main-sync.sh` and `forgejo-release.sh` t8 — whose "once
   file-wide" is release.yaml-scoped (rel/fp are its own jobs, L327-328): NO collision with
   containers-build gaining the name. CLEAN: `.github/**`, `.rulesync/**`, `AGENTS.md`,
   `services/**`, `custom-values/**`, `containers/**`, all other suites.
4. **GitHub side is a different namespace**: `.github/workflows/docker-build.yaml:118-122` logs
   in with `secrets.GITHUB_TOKEN` — GitHub-native; out of R-A's scope, byte-untouched.
5. **Live registries STILL mint nothing** (re-probed): ghcr token
   `?scope=repository:ownyourio/forgejo-runner:pull` → **403** (absent shape); infra pkg-api
   200 `[]` + `/v2/curatedforest/forgejo-runner/tags/list` 401-anon; dev pkg-api 200 `[]`. The
   first lane dispatch legitimately mints **26.11.1** (month-cross coupling still live — Risks).
   Under B this is the LAST run-2 session probe obligation; the lane's single-registry walk
   derives N from the infra `[]` state ⇒ starts at 1 regardless of ghcr.
6. **The fleet's consumed refs are already forge-only**: `charts/forgejo-runner/values.yaml:141-145`
   + `services/dev/prod/values.yaml:194-198` pin `docker://<instance-host>/curatedforest/forgejo-runner:26.11.1`
   — NO workload pulls `ghcr.io/ownyourio/forgejo-runner` anywhere (grep-verified). This is the
   mitigation half of B's accepted collision consequence (Risks) and the strongest grounding for
   R-B itself: B deletes an unconsumed publish AND the parity read it fed.
7. **Suite baselines re-run green on this tree**: bb 20; containers-build 41; main-sync 8;
   **forgejo-release 20** (added to the bar — credential-law adjacency); renovate 8+t9-skip;
   move-config 8; dev 58; gpu 19 @pinned-base; `tests/containers/forgejo-runner.sh` 8 (path
   correction: tests/containers/). ci-surface rc=1: ONLY-t4-red, the two FAIL lines =
   `skills/seaweedfs-debug/references/mcp-server-spec.md:281/:287` (carried D29 deferral).
8. **README claims audited**: its "Bump law" dual-publish line names **containers-build** (TRUE,
   untouched by R-B); its lane claims (L8, L24-28) carry no target AND no walk claim ⇒ README
   byte-kept (third consecutive byte-keep; bar + b9 claims pin).
9. **Shipped lane bytes — the B cut map** (builder-bootstrap.yaml @ 2b11120a8, 275 L, 5 run
   blocks): DELETE the `log in to ghcr` step (L93-98), the ENTIRE `derive the ghcr-side calendar
   N` step (L163-237 — the anonymous token/tags/manifest walk that v1-option-A would have kept;
   OQ-1=B kills it whole), `ghcr_image`/`ghcr_tags` (L254/L256), the `$ghcr_tags $forge_tags`
   build-arg pair (L259 → forge trio only), the ghcr push chain (L269-272), the union math
   `n=$n_ghcr`/`-gt n_forge` (L249-253 → `n=$n_forge` single-registry) and the `. ./ghcr-n.env`
   source. Header law moves: Targets P4' paragraph (L40-44), the "push order ghcr then own" +
   two-registry union clause of the calendar paragraph (L46-55, rescope to single-registry,
   keep walks-before-push/month/N+1-gaps/cold-30m), "two human-minted PATs" (L62-64 → one forge
   PAT, without naming the dead keys). b7's shipped next-n count is 2 → target **1**; run
   blocks 5 → **3**. Trigger/jobs/guard/runs-on/uses/checkout byte-stable (b1-b4).
10. **B-target SIM EXECUTED this session** (`/tmp/opencode/cf6-bb2-plan-sim/sim.py`, throwaway
    trees, repo NEVER mutated): the mechanical cut of the shipped file per fact 9's map (3 run
    blocks, 187 lines, one `next-n` call, one login, zero ghcr substrings anywhere in the file)
    + B-shaped docs + a B-patched bb suite **PASSES 20/20 rc=0** (green-direction: the absence
    teeth hold on the B file; battery bt1–bt10 all bite on TMP copies — bt3's push-arm
    restoration reddens exactly [b5 b6 b8], bt4's read-walk restoration + F1 wrapper redden
    [b5 b7] with b8 as documented collateral); the same B-patched suite against the SHIPPED
    file+docs reads **exactly 13 ok / 7 red at {b5, b6, b7, b8, b9, bt3, bt4}** (red-direction:
    authored honesty per the chunk table, the bt-anchors refuse to bite pre-DEV as designed);
    adjacents re-verified in the sim tree — containers-build **g1 GREEN** over the B lane,
    ci-surface holds the carried ONLY-t4 two-liner shape against the B docs, five-workflow
    True-key parse clean. The SIM caught one authoring pin v1 did not know: **b9's
    ghcr-target ban must anchor on the LANE-SENTENCE TAIL** (from 'builder-bootstrap' onward),
    because the AGENTS/overview bullet carries containers-build's legitimate
    `ghcr.io/ownyourio/<image>` dual sentence in the SAME block — a block-wide ban
    false-positives on the truth (recorded in chunks/C01.md b9).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | lane forge-only (READ and PUSH): workflow cut to the single-registry walk + bb-suite rewrite (×1 next-n, ghcr-read ABSENCE teeth, shrunk closed set) + law/docs trio, one change | M | 1 | [] | — |
| C02 | fleet credential alignment: containers-build name fix + 41-suite t7 + SKILL credential line + ci-surface t5, one change | M | 2 | [] (INDEPENDENT of C01 — ordered for landing clarity, not correctness) | none: disjoint file families (containers-build/SKILL-credential-line/41+ci-surface suites vs lane/bb-suite/overview-lane-sentence/SKILL-lane-block); SKILL.md carries both runs' lines but disjoint paragraphs; no leg of one reads the other's target state (b6's bans fire on the LANE file which C02 never touches; t7's fire on containers-build which C01 never touches). Either order lands green-then-green trees. |

## Wave order
1. **C01** — TEST first (REWRITE `tests/services/forgejo-builder-bootstrap.sh` to the
   target-leg list in chunks/C01.md — designed-RED vs the shipped file at EXACTLY
   {b5, b6, b7, b8, b9, bt3, bt4}; GREEN at b1/b2/b3/b4/b10: 13 ok/7 red at authoring), then
   DEV (workflow cut per fact 9's map + overview lane sentence + `rulesync@37.0.0 generate` →
   AGENTS twin + SKILL lane block). One commit: cut-without-docs leaves the AGENTS paragraph
   lying; docs-without-cut reds b9 — same-change law.
2. **C02** — TEST first (t7 rewrite in the 41-suite + t5 rewrite in ci-surface — authored-RED vs
   the shipped containers-build/SKILL; ci-surface then reads t4-carried + t5-red until the file
   pair lands), then DEV (containers-build.yaml L37+L182 + SKILL.md L107-109). One commit: the
   suites pin the workflow text, teeth move WITH the file. Coord commits each chunk (compact
   `-m`, ≤ ~700-char total command length — the run-1 floor lesson).

## Commands (the validation bar — landing tree)
```bash
export PATH=$HOME/.local/bin:$PATH
BASE=2b11120a8   # ALWAYS resolve-check: git cat-file -t $BASE => commit (vacuous-green law; fact 1)
bash tests/services/forgejo-builder-bootstrap.sh   # 20 ok — B-shapes: single walk, absence teeth (C01)
bash tests/services/forgejo-ci-surface.sh          # ONLY-t4-red, the two FAIL lines byte-carried (fact 7)
                                                   # (during C02 authoring t4+t5 red; landing restores ONLY-t4)
bash tests/services/forgejo-containers-build.sh    # 41 ok — t7 rewritten with the file (C02)
bash tests/services/forgejo-main-sync.sh           # 8 ok — untouched
bash tests/services/forgejo-release.sh             # 20 ok — credential-law adjacency (fact 7)
bash tests/services/forgejo-renovate.sh            # 8 ok (+ t9 default-off skip) — untouched
bash tests/renovate/forgejo-move-config.sh         # 8 ok — untouched
bash tests/services/dev-forgejo-runner.sh          # 58 ok — untouched
GPU_RUNNER_DIFF_BASE=$BASE bash tests/services/gpu-forgejo-runner.sh   # 19 ok; ZERO diff on g7's
                                                   # surfaces this run (fact 2 — caps intact)
bash tests/containers/forgejo-runner.sh            # 8 ok (path: tests/containers/, fact 7)
# unchanged-surface byte-proofs (each must be EMPTY vs BASE):
git diff $BASE --exit-code -- scripts/forgejo-container-detect.sh containers/forgejo-runner/README.md
git diff $BASE --exit-code -- .forgejo/workflows/main-sync.yaml .forgejo/workflows/release.yaml \
    .forgejo/workflows/renovate.yaml .github/workflows/docker-build.yaml
# C01 lane cuts — the B ABSENCE greps (each EMPTY against the landed lane):
grep -nE 'ghcr\.io' .forgejo/workflows/builder-bootstrap.yaml | grep -vE '^\s*[0-9]+:\s*#'   # code lines
grep -nE 'secrets\.GHCR_PUSH_PAT|secrets\.PUSH_TOKEN_GH|docker login ghcr|ghcr_image|ghcr_tags' .forgejo/workflows/builder-bootstrap.yaml
grep -n 'ghcr-n.env' .forgejo/workflows/builder-bootstrap.yaml
# C01 single-registry pins (NON-empty):
grep -c 'forgejo-container-detect.sh next-n' .forgejo/workflows/builder-bootstrap.yaml   # => 1
# credential alignment (C02; each EMPTY):
grep -n 'GHCR_PUSH_PAT' .forgejo/workflows/containers-build.yaml skills/container-creation/SKILL.md AGENTS.md
# single-purpose + residue (unchanged law, re-verified):
grep -rlE "any named container|any container's|name the containers" \
  .forgejo/workflows/builder-bootstrap.yaml .rulesync/rules skills/container-creation AGENTS.md containers  # EMPTY
npx --yes rulesync@37.0.0 generate --check          # sources moved + twin current
python3 - <<'PY'                                    # five .forgejo workflows parse + True-key probe each
import glob, yaml
for p in sorted(glob.glob('.forgejo/workflows/*.yaml')):
    d = yaml.safe_load(open(p)); assert (d.get(True) or d.get('on')) , p
PY
# run-block recount: 3 extracted run blocks (was 5), each bash -n clean (suite b10 prints it;
# local mirror: yaml-extract all `run:` bodies of builder-bootstrap.yaml to /tmp/opencode, bash -n ×3)
npx --yes aislop ci --changes                       # quality gate (score floor, zero errors)
# docker build => no-daemon, CI-deferred (the lane's live build proof stays owner OL2)
```
No helm render moves (nothing under charts/ or services/ changes). No cluster mutation, no
dispatch, no push, no secret changes in any agent session.

## Rulings (planner; the launch's design forks, OQ-1 now OWNER-RULED)
- **RR1 — R-A rides THIS run as C02, separate commit** (launch recommendation adopted):
  different file family, different suite teeth, owner merges both at once. The containers-build
  fix is exactly the L37 comment + L182 login + t7's pin sites + ci-surface t5's two sites +
  SKILL L109 (inventory fact 3 — complete; no other live occurrence).
- **RR2 — wrong-name ban is PER-SURFACE, not a new repo-wide leg**: t7 bans `GHCR_PUSH_PAT`
  (raw, comments included) in containers-build.yaml; the rewritten b6 bans BOTH `GHCR_PUSH_PAT`
  and `PUSH_TOKEN_GH` in the lane file raw (the lane holds no ghcr credential of any name —
  R-A's rename and R-B's deletion meet here); t5 swaps SKILL's presence pin and adds the wrong
  name to the SKILL+AGENTS retired-ban lists. Rejected: a whole-repo ci-surface sweep — every
  live file is owned by a suite that pins or bans it (duplication law, b9-style precise
  scoping); the suites carry the literal as ban-tuple teeth (established self-safety pattern;
  no other leg's routes sweep tests/**).
- **RR3 — R-B+B cut list (fact 9 is the map)**: ghcr login step, the WHOLE ghcr-N read step,
  `ghcr_image`/`ghcr_tags`, the ghcr trio `-t` pair, the ghcr push chain, the union math, and
  the header's targets/order/PATs clauses ALL die; what survives is diag + the single PAT-
  authenticated forge walk (`next-n` ×1, tolerance posture, TLS scheme law) + one unconditional
  forge trio chain + fixed month + N+1-gaps law text + the b1-b4 trigger/scheduling/guard/flow
  shapes untouched. Closed surface: secrets {FORGE_PUSH_TOKEN}, vars {ROLE}, ONE login, push
  sides {forge}. Battery carries BOTH reversal teeth the owner named: bt3 restore-a-ghcr-push-arm
  ⇒ [b5 b6 b8]; bt4's first half restore-the-ghcr-read-walk ⇒ **b7** (the parity-walk shape is
  now the banned shape), second half the F1 wrapper ⇒ b5.
- **RR4 — OQ-1 ANSWERED BY THE OWNER: OPTION B, forge-only walk** (supersedes v1's option-A
  best-guess; the [B] deltas pre-written in chunks/C01.md are now the whole target). Consequence
  accepted knowingly and recorded: after a containers-build half-fail that left ghcr ahead
  (ghcr trio out, forge chain dead — the designed gap side), a lane dispatch can mint an
  instance-registry N equal to a TAKEN ghcr N of DIFFERENT content — the same number then means
  different builds across registries for THIS image. Mitigation (facts 6+3): the fleet consumes
  ONLY instance-registry refs for forgejo-runner (chart L141-145, dev L194-198 — nothing pulls
  `ghcr.io/ownyourio/forgejo-runner`), containers-build stays the dual-registry authority for
  every other image, and the lane's dispatch record (`n_forge=` log line) disambiguates its own
  mint. Simplicity was the ask; the collision risk is priced in, not discovered later.
- **RR5 — docs trio moves a THIRD time, single-registry wording** (owner: "say exactly that, no
  parity claim"): overview lane sentence → own-registry-ONLY + single-registry calendar walk,
  dated ruling; rulesync twin; SKILL lane block same truth (no-input dispatch sentence stays;
  L107-109 credential line is C02's, untouched here). The narrow-guard ROLE paragraph SURVIVES.
  README byte-kept (fact 8). x3: no new bare `docker-build.yaml` mention on any t4 route (the
  carried two FAIL lines stay byte-identical).
- **RR6 — run -1's "ci-surface byte-frozen" framing SUPERSEDED by evidence** (fact 3): t5 pins
  the WRONG credential name in SKILL, so the fleet alignment cannot land without moving t5.
  Run -1's freeze was sound then; R-A created the contradiction. All other ci-surface legs
  (incl. the carried ONLY-t4 shape) and every other suite stay byte-untouched. Fence battery
  re-verified for B: g1 sweeps all `.forgejo/workflows/*.yaml` for URL/ROLE SHAPES only — the B
  lane still passes (contains() membership, zero URL literals; bare `ghcr` prose is not a g1
  pattern); x4 = .github siblings only; t1 five-set unchanged (file persists); no surface
  outside the bb suite pins builder-bootstrap.yaml CONTENT.
- **RR7 — OL0 gains the scope check**: renaming a credential is only correct if the established
  `PUSH_TOKEN_GH` PAT carries `write:packages` on ghcr for ownyourio (its proven uses are repo
  push + gh-pages publish). Instance secrets are unlistable to agents — owner word + file
  evidence. Under B the LANE needs no ghcr scope at all; OL0' serves containers-build's release
  arm only. Retiring the `GHCR_PUSH_PAT` secret: AFTER C02 merges.
- **RR8 — commit/record shape**: two new commits on `cf-6-feat-builder-bootstrap-1` atop
  `d92d0814d` (branch tree == `origin/main`, so the PR diff is exactly this run), coord sole
  committer, compact `-m` ≤ ~700-char floor, detail here. PR-body caveats: R-A/R-B/OQ-1=B
  rulings quoted; the UNMERGED→MERGED correction (fact 1); month-cross; the accepted single-
  registry N-divergence paragraph (RR4, one paragraph, owner-chosen); OL0' scope leg.

## Owner legs (delta on run -1's OL0–OL9; every one user-owned)
- **OL0'** (replaces OL0): instance Settings — confirm `PUSH_TOKEN_GH` carries ghcr
  `write:packages` for ownyourio (extend or re-mint); `FORGE_PUSH_TOKEN` unchanged;
  `GHCR_PUSH_PAT` retires after C02 merges. (R-A owner-side premise, RR7 — containers-build's
  release arm only.)
- **OL1** merge the run -2 PR (both chunks).
- **OL2** bare dispatch on INFRA ⇒ mints `26.11.1` (or month-cross `26.12.1`) at 3 tags to the
  INFRA registry ONLY — the N derives from the instance registry's own empty `[]` state (fact 5);
  ghcr never sees a lane publish or a lane read. Make the forge package public if defaults differ.
- **OL3** dev-copy manual push — unchanged (already forge-only).
- **OL4** probes: the infra side must hit the LANDED `26.11.1`; the ghcr side now EXPECTS
  ABSENCE of `forgejo-runner` (the lane never publishes there; a future containers-build release
  arm may still dual-publish on a merge — the probe judges what the LANE minted, and the RR4
  divergence note tells the owner what a ghcr hit later would mean).
- **OL5–OL9** unchanged from run -1 (hand-push, ArgoCD syncs, gpu/dev verification).

## Risks / merge caveats
- **MONTH-CROSS**: registries verified still-empty (fact 5); if OL1+OL2 slip into December the
  lane mints `26.12.1` while the MERGED label pins (chart L141-145 / dev L194-198, all
  `26.11.1`) — the owner's paired amend PR to the actually-minted literal at both sites, the
  standing coupling, unchanged.
- **SINGLE-REGISTRY N (B's accepted consequence, one paragraph, owner-chosen with eyes open)**:
  the lane and containers-build can mint different Ns for the same content (containers-build
  unions ghcr+forge; the lane reads forge alone). The sharpest shape: a half-failed
  containers-build leaves `26.11.k` on ghcr only, and a later lane dispatch — reading forge's
  max — republishes `26.11.k` on forge from NEWER content, so the same number means different
  builds across registries for this image. Accepted because NOTHING consumes the ghcr ref
  (fact 6: all runners pull instance-registry calendar refs), containers-build stays the
  dual-registry authority for everything else, and the divergence self-heals on the next
  containers-build union (it walks past both sides' maxima). The mitigation is prose: the lane
  header + docs state the single-registry scoping plainly so no reader treats lane-N and
  release-arm-N as the same namespace.
- **Latent-bug fix stays latent**: containers-build's release arm has never executed (every run
  dies at detect-changes — owner-confirmed shape); C02's rename lands unproven live until the
  first full-range green run (cf-55 retest seed, inherited). Without OL0' scope the renamed
  login fails exactly where the phantom-name login would — nothing regresses, nothing is proven.
- **Two chunks, one-file overlap (SKILL.md)**: disjoint paragraphs; a hunk collision at rebase
  time is resolved by re-doing the second hunk (coord note, not a plan dependency).
- The one-change law pairs are load-bearing: a mid-landing tree where the B-shaped suite pins
  meet the shipped dual file (or t7/ci-surface pins meet the shipped SKILL/workflow) is a RED
  tree BY DESIGN — never land half of a pair; per-leg red-first honesty is in the chunk files.

## Deferred (follow-up card seeds — inherited set)
- Lane-design card: per-registry pin reads, published-not-predicted, dev-copy automation.
- UA-10 probe card; run-1 carried set: post-heal `26.11.2` re-pin pair, ghcr absent-vs-private
  settle, cf-55 retests (94/97/101/106), ci-surface t4 (the two carried FAIL lines — D29 sweep
  card), t9-exemption retirement.
- NEW seed (replaces v1's option-A card note): B divergence re-check — if a ghcr consumer for
  forgejo-runner ever APPEARS, or containers-build's ghcr arm flips off, re-open the single-
  registry-N ruling (the fleet is forge-only TODAY — fact 6 — so this is a consumer-appears
  tripwire, not work).

## Open questions
NONE — OQ-1 was the one genuine fork and the owner ruled OPTION B this round (RR4); C02-same-run
(RR1), per-surface bans (RR2), README byte-keep (RR5/fact 8), ci-surface-t5-unfreeze (RR6,
forced by fact 3) all ruled on evidence. Coord books approval on this package.

## RESULT handoff
Plan v2 (B-as-shipped) + chunks/C01.md rewritten to B + chunks/C02.md unchanged (already
option-agnostic, verified by grep); DECISIONS appended (OQ-1=B ruling, A-supersession, the B SIM
record); STATE.json: chunk table {C01, C02 pending}, `plan_status: draft` (coord books approval),
`updated_at` via `date -Iseconds`; fact 10 = the /tmp SIM re-verification (20/20 target, absence
teeth both directions, authored-red set exact, adjacents green).
