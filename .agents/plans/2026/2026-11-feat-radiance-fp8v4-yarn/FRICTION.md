# Friction

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored
(accepted). Agents read this at run start so known workarounds are not rediscovered.

Friction = anything an agent could not find or had no access to, crashes/tool/MCP failures, stale
docs/plans, forced repeats or workarounds — each with the resolution actually used. Agents report
via RESULT `friction:`; coord appends (its own items included).

- 2026-11-23 · plan(feat-radiance-fp8v4-lane) · The launch brief's `--extra_body` "repo law" does
  not exist as a literal rule (repo-wide grep empty) — searching for a named law that isn't there
  burns round-trips. · resolution: the real governing law is D43 (chart FORM owns argv;
  `charts/radiance/values.yaml:182-195`, multi-instance DECISIONS.md:399-422); named with file:line
  in DECISIONS D-8. · fixed
- 2026-11-23 · plan · RESEARCH §5 named THREE llama-swap exact-set peers legs; the tree carries
  SIX widening sites (4 set-pins + `RESTING_RADIANCE_LANES` testlib tuple + golden fixture, plus
  the phantom-list/read arms that ride the tuple). · resolution: full file:line inventory in plan
  V-10 + chunks/C01. · fixed
- 2026-11-23 · plan · The prior-ticket carry_forward line
  (`context-window STATE.json handoff_2026_11_23`) still carries the uncorrected "k6_v4/fp8_v4 …
  7.7/6.8 sessions, +12% long-prompt prefill" pairing that fed the owner's mislabeled framing;
  reading it without this folder's RESEARCH §2.2/§9 C1 re-imports the error. · resolution:
  corrected numbers pinned in plan V-3/V-4 + DECISIONS D-5/D-6; later agents read RESEARCH first. · fixed
- 2026-11-23 · launch-record · An earlier kickoff of this plan named model
  `openrouter/qwen/qwen3.8-flash-12k`; the registry rejected it and the attempt was dropped (why
  no plan existed). Also recorded: a base sha was orphaned by an amend after recording, so NO
  artifact may hardcode shas. · resolution: kickoff models recorded as "inherited session
  default"; base referenced only as "branch HEAD, verify `git rev-parse HEAD`" (STATE.json,
  DECISIONS Conventions). · fixed
- 2026-11-23 · research-record (carried, RESEARCH §0.7) · A phantom future-dated RESEARCH.md
  listing at this folder's deliverable path mid-round; folder absent on re-check. · resolution:
  treated as noise by the research session; the file it wrote is the ground truth this plan reads. · ignored
- 2026-11-23 · plan · Environment: `helm` lives at `~/.local/bin` (needs PATH export or pytest
  silently mass-skips the helm-guarded legs); no docker daemon; pytest must run PER DIRECTORY
  (`test_render.py` exists in both charts/radiance/tests and charts/llama-swap/tests — one
  combined command collides). · resolution: baked into the plan Commands section. · fixed
- 2026-11-23 · plan · Machine-consumed JSON in this family corrupted twice TODAY via hand-patched
  edits (context-window D15's duplicate-key incident). · resolution: STATE.json written whole by
  the `write` tool and validated by round-trip + per-key duplicate check; the check command is in
  the plan Commands. · fixed
- 2026-11-23 · plan · **Mid-round scope change**: after the first artifacts landed (plan + C01-C04
  + STATE/DECISIONS/FRICTION), the owner re-ruled: R1 confirmed `fp8_v4` INFORMED (correction
  accepted, choice stands) and R2 REVERSED the uniform-seqs ruling to per-lane 5/5/5/5/8 — voiding
  the first draft's D-7 scope reduction and the "ruling 2 consequence to exploit" the launch brief
  explicitly pointed at; the gate re-cut, per-lane profiles, smoke 8→5, runbook pair, and three
  new chunks appeared mid-flight. · resolution: coordinator delivered the change BEFORE completion
  (as instructed); folded as DECISIONS D-15..D-18 with D-5/D-7 dated supersession annotations,
  RESEARCH §4.2's measured inventory adopted as-is (not re-derived), and the M-legs-no-seqs claim
  re-verified from the tree before trusting it in the chunk split (surface.sh + TEST_SPEC + both
  notes scripts + charts grep — inventory closed at V-2/V-6/V-7). · fixed
- 2026-11-23 · plan · D12-pair ambiguity: whether the runbook.sh test-half re-pin belongs to the
  red-first C01 wave (test-authority ordering) or to the fn chunk (both-halves-together). ·
  resolution: the scope-change note's "do not split them across chunks" is the sharper law — the
  pair lands in C05; C01–C04 keep the runbook script green because C02's fallbacks compose TODAY's
  bytes (no premature vector move) — recorded D-18. · fixed
- 2026-11-23 · plan · The branch HEAD MOVED mid-planning (a sibling context-window coord record
  commit landing while this plan was authored — the plan-session tip advanced by exactly one child
  commit, old tip verified still an ancestor) — the exact amend/orphan hazard the launch warned
  about; every file:line citation in the plan
  inventory needed re-validation against the new tip. · resolution: verified the new commit is a
  child (old tip still an ancestor) touching only context-window FRICTION/STATE — all cited
  surfaces byte-identical, citations hold; the retraction's family-wide receipt LAW folded in as
  DECISIONS D-14 + plan OQ-5/Landing-3. · fixed
- 2026-11-24 · plan(approval-fold) · The pre-fold chunk files contradicted three fresh rulings
  (C03/C01 read the deficit as "pending OQ-3 / confirm", C01/C06 read the ladder as "PENDING
  OQ-2", C05's header made C05 wait on a baseline that D-21 just waived) — the exact stale-artifact
  class this ticket family pays for. · resolution: single-round fold — D-19..D-26 dated 2026-11-24;
  C01 (ladder AUTHORIZED, floors 5/4/3/2/1 explicit, D-20 refusal-as-expected test encoding), C03
  (success criterion re-cut per D-20, opt-in gate line per D-23), C05 (order gate → WAIVED with
  cost stated, parent discipline), C06 (ladder/tie cite now a ruling, floor set, step numbers);
  D-14/D-17 got dated inline AMENDED annotations (body never rewritten). · fixed
- 2026-11-24 · plan(approval-fold) · Landing-step renumbering after the A/B insertion broke
  cross-references (three artifacts still said "step 5"/"step-5" for the jsonc leg). ·
  resolution: renumbered Landing shape 0–7 and grepped every artifact for stale step cites;
  C03/C06/R-6 now say step 6 for the rows, steps 3–5 for the receipt/gate sequence. · fixed
- 2026-11-24 · plan(approval-fold) · RESEARCH.md §7's Option-A/Option-C k6_v4 lines were the
  mislabel's origin — a plan session editing another role's research artifact is normally out of
  contract. · resolution: the coordinator's fold brief NAMED the dated-erratum annotation as the
  sanctioned form; applied two bracket erratums (:598/:613 areas) with the analysis bytes
  untouched; had it not been named, the honest move is to decline and record in RESULT — judged
  in-contract here and applied. · fixed
- 2026-11-24 · review(C02) · **`tests/provider-loops/surface.sh` REWRITES `AGENTS.md` in place
  mid-review** — its `t14` leg runs `rulesync generate`, and because `rulesync generate --check` is
  RED on this branch's base (the cf-126 dispatcher paragraph in committed `AGENTS.md` is not the
  rulesync output of committed `.rulesync/rules/overview.md`), running that suite in a worktree
  **silently deleted** that hand-carried paragraph; the reviewer caught it, restored with
  `git restore AGENTS.md`, and re-verified the tree clean. This is a live footgun for every agent in
  this repo, not a C02 artifact: AGENTS.md is a GENERATED surface (hard rule: never hand-edit; edit
  `.rulesync/` and regenerate), so any leg that regenerates while sources and output disagree will
  drop prose that only exists in the committed output. · open (LAW for this family: before running
  any `tests/provider-loops/**` or other rulesync-invoking suite in a worktree, note that it mutates
  `AGENTS.md`; run `git status --porcelain` immediately after and restore anything regenerated;
  reconcile the drift in the cf-126 C04 flip wave, which is owner-gated — the runner literal moves
  only by a fresh owner ruling)
- 2026-11-24 · review(C02) · **A `git archive` HEAD tree is NOT a faithful red-set baseline** — the
  author's byte-identity proof used one, and it is sound for argv comparison, but as a *baseline* for
  counting designed reds it distorts: git-dependent transcription legs and one skip behave differently
  in an extracted tree, reporting **55F/193P/1S** against the true HEAD state of **48F/201P/0S**, which
  would have falsely implied that C02 introduced new reds. · resolution: for red-set deltas use a real
  detached worktree (`git worktree add --detach` + copy the vendored `app-template-5.0.1.tgz`), which
  reproduced the baseline exactly; recorded so no later round misreads an archive-tree count as a
  regression. · fixed
- 2026-11-24 · dev(C02) · **`npx aislop scan --changes` scopes ZERO files on an uncommitted wave** —
  `--changes` reads committed state, and this pipeline holds a chunk uncommitted until the coordinator
  commits on review approval, so a chunk hand-off cannot get a diff-scoped gate result from it; a naive
  `0 changed file(s)` reads as a clean pass. · resolution: run `npx aislop scan <path>` on the touched
  trees (C02: `charts/radiance` 100/0/0, 14 files) and rely on CI's `aislop ci --changes` after the
  commit; the author flagged the discrepancy instead of reporting the vacuous 100. · fixed
