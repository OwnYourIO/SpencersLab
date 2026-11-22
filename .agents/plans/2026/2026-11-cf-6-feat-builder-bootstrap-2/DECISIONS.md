# Decisions — cf-6-feat-builder-bootstrap-2 (forge-only lane + fleet credential alignment)

Append-only. New entries at the bottom.

## Kickoff

- 2026-11-22 human (pre-merge review of run -1's commits): "GHCR_PUSH_PAT should match what's already used - PUSH_TOKEN_GH. Though if I'm honest, the bootstrap build only should go to the Forgejo instance, not github." Two rulings: (1) the ghcr credential name shipped by cf-6 is WRONG fleet-wide — the established secret is `PUSH_TOKEN_GH` (owner-side fact; the instance's secret list is not agent-readable, the owner's word is the grounding); the latent containers-build release-arm bug never executed because every run dies upstream. (2) the bootstrap lane is FORGE-ONLY (instance registry, not ghcr) — the lane's ghcr login/push/credential DELETE, which also moots the name fix FOR THE LANE but not for containers-build.
- 2026-11-22 coord: run -2 seeded; branch `cf-6-feat-builder-bootstrap-1` REUSED (unmerged run -1 commits `fab419cb1` + `d92d0814d` stay as history; run -2 lands additional commits — owner squash-at-merge decides the final PR shape). Planner scope (two questions it must answer with the inventory): (a) does `GHCR_PUSH_PAT` appear anywhere else (docs/SKILLs/suites/other workflows) and what's the alignment change-set + teeth moves (the 41-leg suite pins containers-build's text — the secret-name leg(s) move WITH the file, one change); (b) lane forge-only WALK semantics — keep the anonymous ghcr READ-walk for union-max parity with containers-build's N (recommended: yes — the same calendar N must mean the same build everywhere, and anonymous manifest reads need no credential) vs forge-only walk (simpler, but the lane and the release arm could then mint DIFFERENT N for the same content when ghcr's max is higher). Docs trio moves a third time (the just-committed AGENTS paragraph "(re)mints ... to ghcr.io/ownyourio/forgejo-runner AND that instance's own registry" becomes false); suite b-shapes rewrite accordingly; b6's closed set shrinks to {FORGE_PUSH_TOKEN}. No owner round expected beyond a genuine inventory surprise — rulings themselves are explicit.

## Planning (2026-11-22, agent-plan on the flash route)

- 2026-11-22 plan: **LAUNCH-BRIEF CORRECTION — run -1 is MERGED.** `origin/main` tip `2b11120a8`
  carries run -1's commits as `adc12c767`/`2b11120a8` with patch-ids BYTE-IDENTICAL to the
  branch's `fab419cb1`/`d92d0814d` (git patch-id: 3f0ed07b6…, b31933ae1…); `git diff HEAD
  origin/main` empty; local `main` == `2b11120a8`. Consequence ruled: `BASE = 2b11120a8` for
  this run's byte-proofs AND `GPU_RUNNER_DIFF_BASE` — g7 fences run -2's own hunks; the
  "union of run-1+run-2 consumes the caps" worry is moot ON FACTS: run -1 touched zero g7 paths
  (`git show --stat fab419cb1`: workflow/docs/suite/ticket only) and gpu re-ran 19 ok LIVE at
  BOTH candidate bases this session ("0 docker:// lines at cap 8"). Run -2 touches none either.
  The branch stays un-rebased (owner's view of run -1's commits intact; trees equivalent).
- 2026-11-22 plan: **R-A INVENTORY COMPLETE (the first task, done).** Wrong name
  `GHCR_PUSH_PAT` lives in 7 files: containers-build.yaml L37+L182 (the latent-bug login; the
  file's ghcr WALK is anonymous-pull-token — L264+ — so the rename is exactly 2 lines),
  builder-bootstrap.yaml L98 (dies via R-B, C01 territory — the name fix is DELETED there, not
  renamed), SKILL.md L109 (credential sentence, C02), forgejo-containers-build.sh
  L426/428/432/433/442/445/455 (ALL inside leg t7 — the one-change pair), forgejo-ci-surface.sh
  L171/187 (leg t5), forgejo-builder-bootstrap.sh L71/619-620/672 (leg b6 — mooted by R-B, C01).
  Establishment proof for `PUSH_TOKEN_GH`: main-sync.yaml L43 (push-gh) + release.yaml L272
  (CR_TOKEN) — both live, repeatedly executed, pinned green by forgejo-main-sync.sh (t5-style
  key pin) and forgejo-release.sh t8; t8's "once file-wide" is RELEASE.yaml-scoped (rel/fp are
  its own jobs, L327-328) — NO collision with containers-build gaining the name. CLEAN (zero
  occurrences): .github/** (docker-build.yaml logs in with GitHub-native `secrets.GITHUB_TOKEN`
  — a different platform's namespace, not an instance secret: out of R-A's scope, byte-untouched),
  .rulesync/**, AGENTS.md, services/**, custom-values/**, containers/**, every other suite.
- 2026-11-22 plan: **RR6 — ci-surface's run -1 "byte-frozen" framing SUPERSEDED by evidence.**
  t5 REQUIRES `GHCR_PUSH_PAT` in SKILL (presence tuple L187) — the fleet alignment cannot land
  without moving t5 or ci-surface reddens post-fix. Recorded as a rework ruling with the line
  read, not drift: run -1's freeze was sound then (nothing in its scope contradicted t5); R-A
  created the contradiction. All other ci-surface legs (incl. the carried ONLY-t4 two-liner at
  seaweedfs-debug/references/mcp-server-spec.md L281/L287) stay byte-untouched.
- 2026-11-22 plan: **RR2 — wrong-name bans scoped PER-SURFACE, not one new repo-wide leg**: t7
  bans GHCR_PUSH_PAT in containers-build (raw, comments included); the rewritten b6 bans BOTH
  ghcr-credential names in the lane (the shrunk closed set holds no ghcr credential of any
  name); t5 adds the wrong name to the SKILL+AGENTS retired-ban lists. Rejected: a whole-repo
  ci-surface sweep — every live file is already owned by a suite that pins or bans it, and the
  suites legitimately carry the literal as ban-tuple teeth (the established ci-surface/b9
  self-safety pattern; no other leg's routes sweep tests/**).
- 2026-11-22 plan: **OQ-1 (RR4) — walk semantics, best-guess OPTION A (KEEP the anonymous ghcr
  READ-walk, push forge-only).** Collision math ruled both ways (plan RR4 + chunks/C01.md):
  A preserves "one calendar N = one build everywhere" — a half-failed containers-build (ghcr
  trio out, forge chain dead — the designed gap side) leaves ghcr ahead, and a later lane
  dispatch READS past it; under B (forge-only walk) the lane would mint forge-N equal to a taken
  ghcr-N for DIFFERENT content, and the fleet's labels pin forge refs. The read needs no
  credential (the shipped ghcr-N step is already anonymous-token-only, fact 9), so A is fully
  compatible with the R-B credential deletion; 401/403/404 degrade-to-forge-max unchanged,
  never a fail. B is simpler (3 blocks, next-n×1) and recorded with full [B]-marked leg deltas.
  Strengthening fact 6: NO workload anywhere pulls ghcr.io/ownyourio/forgejo-runner — the
  merged per-release labels pin the instance registries' calendar refs (chart L141-145 infra,
  services/dev L194-198); R-B deletes an UNCONSUMED publish, and the read-walk is pure N-parity.
  Owner-vetoable; ONE batched round carries it.
- 2026-11-22 plan: **RR5 — README byte-keep CONFIRMED (the brief's "check").** Its
  dual-publish line ("Bump law": "the containers-build workflow publishes … to
  ghcr.io/ownyourio/forgejo-runner and the instance registry") names CONTAINERS-BUILD — TRUE,
  untouched by R-B; its lane claims (L8, L24-28, read in full) carry NO target statement. Third
  consecutive byte-keep, pinned by b9's claims + the bar's git-diff. containers-build's DUAL
  law likewise untouched by R-B — only R-A's name moves there.
- 2026-11-22 plan: **Fence battery run — conceptually AND live where cheap (the
  verify-don't-assume order).** g1 sweeps ALL .forgejo workflows for URL/ROLE shapes only —
  post-C01/C02 the lane still passes (contains() membership, zero URL literals; `ghcr.io` is
  NOT a g1 banned substring; the containers-build rename touches none of g1's patterns); re-
  verified green over the shipped lane this session (41-suite run). x4 = .github cutover
  siblings only; ci-surface t1 five-set unchanged (file persists). NO surface outside the bb
  suite pins builder-bootstrap.yaml CONTENT — the bb suite is the content-fence by design.
  Registry probes re-run LIVE: ghcr token 403-absent, infra pkg-api 200 `[]`, infra tags/list
  401-anon, dev pkg-api 200 `[]` ⇒ still ZERO 26.11.1 anywhere; first OL2 dispatch legitimately
  mints the pinned literal; month-cross coupling still live. Full suite baselines re-run green
  this session: bb 20; containers-build 41; main-sync 8; **release 20** (NEW bar member —
  credential-law adjacency, proven untouched by the rename); renovate 8+skip; move-config 8;
  dev 58; gpu 19 @`GPU_RUNNER_DIFF_BASE=2b11120a8` zero-skip; `tests/containers/forgejo-runner.sh`
  8 (path correction: tests/containers/, not tests/services/); ci-surface ONLY-t4-red (two
  FAIL lines, carried).
- 2026-11-22 plan: **RR1/RR8 + chunk shape + owner premise.** Two chunks per the launch
  recommendation: C01 lane forge-only (workflow cut + bb-suite rewrite + overview/AGENTS twin +
  SKILL lane block), C02 credential alignment (containers-build 2 lines + t7 rewrite + SKILL
  credential line + t5 rewrite) — SKILL.md's disjoint paragraphs are the only overlap; chunks
  declared INDEPENDENT (verified: no leg of one reads the other's target state; either order
  lands green-then-green), waves 1/2 for landing clarity only. C02 rides THIS run, separate
  commit (different file family, different teeth: 41+7-suite vs 20-suite; owner merges both at
  once). RR7: OL0' gains the secret-SCOPE premise — PUSH_TOKEN_GH's existing uses prove the
  NAME, not ghcr write:packages scope (instance secrets are unlistable to agents: owner word +
  file evidence); without scope the renamed login fails exactly where the phantom-name login
  would today, so nothing regresses — OL0' lands before the first release-arm green run;
  GHCR_PUSH_PAT retires AFTER C02 merges. Red-first honesty per leg written in both chunk
  files: C01 authored-red {b5, b6, b8, b9} + bt3's new R-B-reversal anchor (b7 green under A,
  red under B); C02 authored-red {t7, t5} with ci-surface temporarily t4-carried + t5-red until
  the file pair lands. Genuine forks for the owner round: exactly one (OQ-1), per the
  no-questions rule.
- 2026-11-22 coord: PLAN RECORDED — launch-brief corrections accepted on evidence (run -1 MERGED as 2b11120a8 via the owner's rebase-merge, patch-ids proven — which explains the live state precisely: the shipped lane's ghcr login names the phantom GHCR_PUSH_PAT, so even a bare dispatch today would die BEFORE the forge push — registry re-probes confirm still zero 26.11.1 anywhere; this is why the owner's two rulings are the recovery path, not polish). RR6 accepted (ci-surface t5 actively pins the wrong name — unfreeze with evidence, other legs stay frozen). RR7 noted: PUSH_TOKEN_GH's existence is proven by live green usage, its ghcr write scope is not (unlistable) — owner OL0' confirmation before the first release-arm success; no regression either way. OQ-1 to the batched owner round now; approval booked on the answer.

## OQ-1 ruled + plan v2 rework (2026-11-22, agent-plan, plan-rework2)

- 2026-11-22 human (OQ-1 answer, via coord): **OPTION B — forge-only WALK.** "The lane reads
  ONLY the instance registry for the calendar N AND pushes only there." Supersedes the v1
  plan's option-A best-guess (RR4). Recorded append-only: the A proposal and its collision
  math stay above as dated record — the owner weighed them and chose simplicity knowingly.
- 2026-11-22 plan (rework): **the pre-written [B] deltas are now THE shape.** Workflow: 3 run
  blocks (diag + forge login/walk + build&push), `next-n` exactly ONCE, N single-registry
  (`n=$n_forge`), one forge trio chain, ONE login, secrets {FORGE_PUSH_TOKEN} × vars {ROLE};
  the entire anonymous ghcr-N step (L163-237) is DELETED, not kept. Suite: b5 drops the
  ghcr-side pins + order clause, adds the ghcr-push-absence + single-registry pins; b7 flips
  to next-n×1 REQUIRED + the NEW ABSENCE teeth (no `ghcr.io/token`/`ghcr_api`/`ghcr_list`/
  `ghcr_token` read shapes in code — the parity-walk shape is the BANNED shape); b8 bans
  `ghcr.io`/`ownyourio/forgejo-runner`/`ghcr_image`/`ghcr_tags` outright; b9 moves the doc pins
  to the single-registry truth; bt3 becomes the R-B push-arm-reversal probe (⇒ b5+b6+b8) and
  bt4 the read-walk-restoration + F1 probe (⇒ b7 + b5, b8 tolerated-collateral). Authored-red
  set: exactly **{b5, b6, b7, b8, b9, bt3, bt4}** (13 ok/7 red vs shipped — b7
  LEFT the green-under-A set as the owner's table predicted).
- 2026-11-22 plan: **ACCEPTED CONSEQUENCE (one paragraph, owner-chosen with eyes open)** — the
  lane's N and containers-build's union-N are different namespaces for this image: after a
  containers-build half-fail that leaves ghcr ahead (ghcr trio out, forge chain dead — the
  designed gap side), a lane dispatch reading forge-only can mint an instance N EQUAL to a
  taken ghcr N of different content, so the same number can mean different builds across the
  registries for forgejo-runner. Mitigation (fact 6, grep-verified): NOTHING consumes the ghcr
  ref for this image — every runner label pins instance-registry calendar refs — and
  containers-build stays the dual-registry authority for every other image; divergence
  self-heals on the next containers-build union. Docs state the single-registry scoping
  plainly ("say exactly that, no parity claim" — owner wording), so no reader mistakes the
  namespaces. Rejected: any parity hedge (re-adding the read walk) — that IS option A.
- 2026-11-22 plan: **B-target SIM EXECUTED (the launch's re-verify obligation), repo
  untouched.** `/tmp/opencode/cf6-bb2-plan-sim/sim.py` built throwaway trees from BASE
  2b11120a8: T_B (mechanical cut per fact 9's map — 187 lines, 3 steps, zero ghcr substrings;
  B-shaped overview/AGENTS/SKILL sentences; B-patched suite) → **PASS 20 ok rc=0** with the
  battery's new reversal probes biting; T_B2 (shipped file+docs, B-patched suite) → **exactly
  13 ok / 7 red at {b5,b6,b7,b8,b9,bt3,bt4}** — authored-red exact. Adjacents: g1 GREEN over
  the B lane; ci-surface keeps the carried ONLY-t4 two-liner against the B docs; five-parse
  clean. THE SIM'S FIND: b9's pair-block ghcr ban must anchor on the LANE-SENTENCE TAIL (from
  'builder-bootstrap') — the AGENTS/overview bullet carries containers-build's legitimate
  `ghcr.io/ownyourio/<image>` dual sentence in the SAME block; a block-wide ban false-positives
  on the correct landing tree (caught red-handed by the sim, re-scoped, re-ran green). Booked
  into chunks/C01.md as a SIM-CAUGHT AUTHORING PIN for TEST.
- 2026-11-22 plan: **scope untouched by the rework:** C02 unchanged (grep-verified
  option-agnostic — the credential alignment never referenced the walk); plan_status stays
  draft for coord to book approval; BASE/g7/byte-proof/registry facts stand (v2 edits only the
  RR4/OQ/Commands-bar/walk-shape surfaces).
- 2026-11-22 coord: PLAN v2 (B) APPROVED — `plan_status`: draft → **approved** (OQ-1 was the last fork; owner answered B; rework sim-verified authored-red exactly {b5,b6,b7,b8,b9,bt3,bt4} against shipped, T_B 20/20; the accepted-consequence paragraph stands as the owner-priced trade; the SIM-caught b9 tail-scope pin ships as an authoring law for TEST). C01 TEST wave launched (suite rewrite to pure-B, ci-surface/containers-build/detector/README byte-frozen this chunk; BASE=2b11120a8 resolve-checked, origin/main confirmed unmoved at launch). Then C01 DEV (fact-9 cut map: 3-block file) + docs trio third move → commit; C02 (credential alignment, option-agnostic) TEST→DEV → commit; chunk reviews + final at BASE; PR body carries OL0' + RR7 scope-confirmation note + the divergence paragraph in owner words.
- 2026-11-22 coord: RUN CLOSED — FINAL WHOLE-PLAN REVIEW APPROVE at HEAD `44086389a` (fresh full bar byte-verified against the sweep records incl. the symmetric-pair-law correction absorbing my disproved asymmetry brief; doc-sediment sweep zero stale live text; F1 promise's closure location cited; OL0'–OL9 re-derived with the OL8 CONSOLIDATION precision — every GitHub-side leg now rides ONE confirmed secret name). `plan_status`: approved → **complete**. RECORD CORRECTION GOVERNING (dated here; append-only): the in-tree "ci-surface prints t4+t5 during C02 authoring" expectation repeated at plan L133-135/L144-145 + chunks/C02 L107-109 is DISPROVED by measurement (fail() exits at t4 before t5 runs — the honest channels are the leg-block-alone / t4-neutralized tree, both recorded); c02_review + Review notes govern over those lines; the plan-file itself awaits its author's next touch (coord floor cannot edit plan files — recorded drift). Floor calibration REFINED: the commit-message landmine is the case-sensitive lowercase word `push` in the command line (uppercase `PUSH_TOKEN_GH` is safe) — supersedes both the length theory and my case-insensitive guess. FRICTION appended. Record commit follows.
