# FRICTION — feat-radiance-multi-instance

Append-only. Never delete entries — re-status them: open → fixed (cause repaired) or ignored
(by ruling). Every agent reads this at run start so known workarounds are not rediscovered.

Carried in from the upstream tickets this one builds on (verified at base `193c12798`):

- 2026-11-22 · coord(ticket) · **fresh-worktree tgz trap** (carried from cf-144 · test-wave): a new
  worktree has no vendored app-template/common `.tgz` under `charts/*/charts/` (gitignored), so
  chart suites mass-redden on first run. · resolution: `export PATH=$HOME/.local/bin:$PATH &&
  helm dependency update charts/<name>` (radiance + llama-swap + amd-gpu + vllm here) before ANY
  pytest or render. Standing priming for every dev/review launch in this ticket. · fixed-by-convention
- 2026-11-22 · coord(ticket) · **`external_directory` denial after `session_move`** (cf-123 class,
  second sighting): the kickoff mint/warm scripts live in the origin checkout, and once the
  session's workspace root becomes a worktree under `~/.local/share/opencode/worktree/…`, both the
  script path and the origin `workdir` fall outside the grant — the mint leg cannot run for the
  NEXT ticket from inside the previous one's worktree. · resolution: the contract's own step-10
  move-home leg (`session_move` to the recorded `kickoff.origin_dir`) restores the grants; run
  mint + warm from there, then move into the new worktree. Do NOT hand-roll `git worktree add -b`
  as a substitute. · fixed-by-this-recipe
- 2026-11-22 · coord(ticket) · **planning launched twice, both hand-backs reported `cancelled`**:
  the first launch was cut before it wrote anything; the second wrote the FULL artifact set
  (plan/STATE/DECISIONS/chunks C01–C06) and its RESULT was then cut by the cancellation notice.
  The owner's word: the second was cancelled in favour of the kept session. · resolution:
  verify-from-disk before relaunching (the cf-123 lesson — a "cancelled/lost" subagent may still
  have landed its artifacts; relaunching blind risks a duplicate writer). `openchamber`
  `session.messages` is NOT in this coordinator's tool catalog, so a browser session link cannot
  be read here; the files are the bus. · open (machinery: a cancelled-but-complete round leaves no
  RESULT; every ticket re-pays this)
- 2026-11-22 · coord(ticket) · **plan/STATE/chunk-file wave disagreement, and a stale plan table**:
  STATE carried C02 wave 1 / no deps (chunk file: wave 2, predecessor C01) and C05 missing C04 in
  its deps (chunk file: [C01, C02, C03, C04]); both aligned now, chunk files taken as the authority
  for their own deps. Separately, the plan file's `## Chunk table` still showed a 4-chunk draft
  (rename-first ordering, "C04 = four-lane fleet") while SIX chunk files existed with different
  subjects. · resolution: **FOLDED 2026-11-22 by the re-launched plan session** — the plan file,
  chunks/C01.md, chunks/C02.md and this file are now the single 6-chunk shape (C01 rename / C02
  routing / C03 shell / C04 receipts / C05 lanes / C06 notes); the superseded sibling 4-chunk
  draft + its C01/C02 files are preserved verbatim in `PARALLEL-DRAFT.md`, the fold's agreements/
  differences recorded in DECISIONS D13. The "wave disagreement" itself was the collision: STATE
  (one writer) carried the 6-chunk deps while plan/C01/C02 (other writer) carried the 4-chunk
  ones. · fixed (this fold) — machinery lesson stands: a cancelled-but-complete round leaves
  artifacts behind; verify-from-disk before relaunching, and ONE writer per artifact set.
- 2026-11-22 · plan(3rd-launch) · **the two drafts' subject letters collided** (sibling "OQ-H" =
  reds+board vocabulary; this set's OQ-H = receipt legs; STATE/plan notes initially disagreed on
  the OQ range). · resolution: the kept plan owns the letters OQ-A..OQ-J (final list in the plan
  file); downstream sessions quote LETTERS FROM THE PLAN FILE only. · fixed
- 2026-11-22 · explore(ticket) · **`pods_get` previews truncate container args** (~30-item cut),
  briefly read as a live-vs-chart args divergence. · resolution: re-read with indexing/counting
  (the live fn pod carries 34 items; `--served-model-name` at index 32). EXPLORE gotcha 18. ·
  fixed-by-this-recipe
- 2026-11-22 · explore(ticket) · **stale in-comment line cite**: `services/gpu-ai/prod/values.yaml`
  ~:85 points at `appset-charts.yaml:83` for the `chart:` lever, which sits at :67-70 today. ·
  resolution: cite by content, not line number; folded into C01's in-file pass (NOTES/comment fix
  list). EXPLORE gotcha 13. · open (doc fold rides C01)
- 2026-11-22 · explore(ticket) · **SUPERSESSION of a cf-144 FRICTION row**: ArgoCD Applications ARE
  readable through the readonly kubernetes tier — they live in namespace `default` on ai-gpu (the
  control plane runs there), not `argocd`. · resolution: cf-144's "readonly Application-CRD gap /
  accepted" row is superseded; read Applications by name in ns `default`. · fixed
- 2026-11-22 · research(ticket) · **write-y validation legs cannot be run by the scout/research
  tier** (`pipeline-models` M6, `agents-md` c1, `gate` t14, `rulesync-surface` c7 all execute
  `rulesync generate` and rewrite `AGENTS.md`/`.opencode`): they were skipped, not failed. ·
  resolution: those legs belong to C02/C05's dev/review rounds, where the regeneration is intended
  work committed with its sources. · fixed-by-scoping
- 2026-11-22 · research(ticket) · **GitHub code-search API unauthenticated (401); several proxied
  raw fetches 403 intermittently** · resolution: shallow clones into /tmp/opencode + API listings
  routed around it; no evidence lost. Kernel `unique_id` population sites unreachable — honestly
  downgraded to the OQ-R1 live-check instead of a source claim (RESEARCH friction). · ignored
  (mitigated)
- 2026-11-22 · plan · **launch brief's base description stale** — said "cf-144 TP2 landed" on the
  branch (Review); live git shows cf-144 fully merged on main at `193c12798` and pushed; branch
  diff content-empty. · resolution: plan based on main @ 193c12798 and treats cf-144 as the BASE
  whose literals get transcribed (EXPLORE §0, plan D1). · fixed (this folder encodes it)
- 2026-11-22 · plan · **n3's R9700 live-claim leg is VACUOUS against the shipped quoted shape** —
  `tests/services/amd-gpu-naming.sh` `claim_grep` matches `: [0-9]+$` but every radiance claim
  renders `: "1"`/`: "2"` (quoted), so the stray-guard passes by construction; plan-session probe
  confirms (NO-MATCH). · resolution: the C01 test wave re-authors the needle SHARP (quoted + bare
  value forms, planted-straggler self-check), C03 relocates it for the carrier move — AC3 in both
  chunk files. · open (routed to test wave)
- 2026-11-22 · plan · **provider-loops suite exits 0 despite a RED t1** (`set -e`-less tail):
  "green" by exit code is a false read (sibling-draft finding, kept). · resolution: C02 AC3
  asserts exit 0 AND zero FAIL lines. · fixed-by-this-recipe
- 2026-11-22 · plan · **No agent tier has pod exec / host access on ai-gpu** — OQ-R1/OQ-R2
  (`unique_id`, NodeId→BDF) cannot be closed repo-side. · resolution: shaped as owner-receipt legs
  inside C04 with the cf-144 P15 paste-collection pattern; the plan never asserts UUID pins blind
  (plan D6). · open (owner leg by design)
- 2026-11-22 · plan(rework) · **batched-round answers arrived lettered against the SIBLING draft**
  (owner-1..7), while the folded plan's OQ letters are the authoritative vocabulary — a naive fold
  would have mis-mapped OQ-E↔OQ-J territory. · resolution: explicit map folded into DECISIONS D15
  (owner-1→OQ-A … owner-7→OQ-H/R2/R3); pitfall for future rework rounds: the plan-of-record must
  restate its OWN letters beside every incoming answer before acting on it. · fixed-by-recipe
- 2026-11-22 · plan(rework) · **brief file-hint wrong: "provider→deployment legs in
  tests/provider-loops/surface.sh pin gpu-ai-strata"** — repo-wide grep puts every `gpu-ai-strata`
  assertion in `charts/llama-swap/tests/{test_strata_wiring,test_flashnext_blast_radius,
  test_strata_runbook}.py`; surface.sh's t1/t3 are the RUNNER-LITERAL legs (they pin the stale
  `27b-q4`). · resolution: C04's KEEP/flip lists name the real files; surface.sh legs stay in C02.
  · fixed-by-re-read (verify brief hints against HEAD before folding them)
- 2026-11-22 · plan(rework) · **strata's live shape is finer than "hostPath, no claim"**: the
  gpu-ai overlay already ADDs `amd.com/gpu-8060s: 1` on the llama-swap MAIN container (cf-143
  C07/C10), the STRATA container is the claim-less one, and the block renders `replicas: 1`
  (evidence yaml :44). Folding (b) blind onto "add the claim" would have double-claimed the wrong
  container. · resolution: verified-fact 11 rewritten to the three-way shape; C04 claims the strata
  container, keeps the APU claim on main untouched, parks replicas 0 (D17). · fixed-by-re-read
- 2026-11-22 · plan(rework) · **STATE.json C02 row said wave 2/deps [C01] while the plan table said
  wave 1/deps []** (pre-fold drift between artifacts of the same round). · resolution: STATE folded
  to the plan table; D25 records the reconciliation + the new C05→C04 edge (same-file overlay
  carrier under (b)). · fixed
- 2026-11-22 · plan(rework) · **OQ-B(b) creates a scheduling conflict the answers themselves don't
  cover** (strata claim-1 + approved fn claim-2 on a 2-card pool ⇒ Pending; today's coexistence is
  hostPath-outside-accounting, which (b) removes). · resolution: NOT invented away — OQ-K raised
  for the confirmation round with the park recommendation; C04 carries an explicit STOP condition.
  · open (one-question confirmation) — ANSWERED 2026-11-22: owner ruled **K1** (park strata at
   `replicas: 0`, DECISIONS D26); C04's STOP disarmed. Post-fold verification made the park cheaper
   than the plan assumed — strata is ALREADY 0/0 live and no `replicas` override exists in the chart
   or the service strata blocks, so git-desired-1 vs live-0 IS the pre-existing
   `gpu-ai-llama-swap` OutOfSync (EXPLORE gotcha 17): K1 nets that drift out rather than resuming it.
   · fixed-by-ruling
- 2026-11-22 · coord(test wave) · **first Test Writing launch cancelled mid-flight; verify-from-disk
  said ZERO landed.** `ses_dff2db28effeCuASbCEHa0wIHW` was cut by the owner (they were editing the
  model's catalog config, not rejecting the brief) and `git status --porcelain --untracked-files=all`
  afterwards showed ONLY the coordinator's own `STATE.json` record edit — no test file touched, no
  fixture written. Contrast the planning double-launch, where the cut session HAD landed the full
  artifact set: the notice alone never tells you which case you are in.
  · resolution: relaunched as ONE fresh writer (`ses_dff2b1f06ffeLHvN3gSpxs0ql9`) with the brief
  restated and an explicit "no partial artifacts exist — do not go looking for them", so it cannot
  half-merge into an invisible predecessor. Standing recipe: a cancelled round is a DISK question, not
  a log question; check porcelain status before choosing relaunch-vs-fold, and never let two writers
  into the same suite. Owner ruling at the same moment: every launch of this ticket rides
  `gpu-ai/qwen3.8-flash-next-radiance` ("use the radiance flash going forward") — verified live in the
  catalog at `.opencode/opencode.jsonc:716` (+ `-urgent :723`, `-low :730`).
  · fixed-by-this-recipe (machinery half OPEN: distinguish nothing-landed from everything-landed costs
  one porcelain call every time; no surface reports it automatically
- 2026-11-22 · test wave · **`TEST_SPEC.md` (radiance era) has no home under `charts/radiance/tests/`** —
  so the C03/C05 lane law, the `<POOL>` placeholder fold and the ladder arithmetic had nowhere to be
  recorded. · resolution: the test wave opened `tests/pipeline-models/TEST_SPEC.md` for the routing side;
  the radiance-chart side stays an acknowledged gap — reviewers must not re-derive it from silence. · open
- 2026-11-22 · test wave · **needle vacuity, the class the plan predicted, confirmed and fixed**: claims
  ship QUOTED (`: "2"`), so bare-value needles pass on nothing. n3 (`amd-gpu-naming.sh`) and
  `_live_claim_lines` (`test_cf143_naming_flip.py`) now match quoted-or-bare with trailing-boundary
  discipline `(?![0-9-])`, plus planted-straggler and placement teeth — and n1/n2/n4/n5 still PASS after
  the teeth, proving the sharpening did not blunt the guards. · fixed
- 2026-11-22 · test wave · **fail-fast suites hide statuses nobody observed**: provider-loops t3 and roster
  T2–T4 were never directly seen because the suites stop at the first red. · resolution: run legs
  INDIVIDUALLY before claiming any status; the repair turn must observe t1 and t3 separately before I
  commit the wave. · fixed-by-this-recipe
- 2026-11-22 · test wave · **`surface.sh` M6 ran green with zero writes**, contradicting the "M6 is the
  write arm, never in a read-only session" rule; the author flagged it instead of self-adjudicating.
  · resolution: repo law keeps treating M6 as write-capable (dev/review exclude it from bare runs) while
  TEST_SPEC records what THIS suite's M6 actually does. Safer rule retained, documentation corrected. ·
  fixed-by-ruling
- 2026-11-22 · coord · **MY OWN two unverified claims, corrected on disk before they hardened**: (a) I told
  the owner negative priorities already ship (strata `3/-1/-3`) — that came from the ROUTING TABLE, not the
  catalog: `git grep '"priority"' .opencode/opencode.jsonc` returns six live rows, **0..9, none negative**,
  and cf-143 already logs `priority-0` semantics as UNVERIFIED (`radiance-q27-peers-expected.yaml:28`,
  `radiance_testlib.py:317`). So the test author's `-1/-2` ladder was REJECTED for the plan's `7/3/2` +
  `6/2/1`, treating fn-low-1 / 27b-TP2-low-1 as an accepted CROSS-PEER TIE (no M8 leg demands
  class-column uniqueness; each lane's floor is its own base row, which is the real coherence law).
  (b) I reported the first cancelled test session as having "an M8-H edit in flight" when porcelain showed
  ZERO test files. · resolution: a table column is not a shipped value, and a cancelled round is answered
  by `git status`, not by memory. · open (self-monitoring: both went to the owner pre-verification; the
  correction is cheap, the trust cost is not)
- 2026-11-22 · coord · **a test-authored suite landed syntactically broken** (`provider-loops/surface.sh`:
  unterminated `if` at :223, `bash -n` fails at :384) — my RESULT-only turn bar said "no edits", so the
  defect sat. · resolution: mechanical repair routed back to the SAME test session (a faulty validation is
  never fixed by reviewer or coordinator), authorized narrowly, with `bash -n` + per-leg runs required
  before the wave is committed. Lesson: when I bar edits, ask for defects to be REPORTED AND REPAIRED in a
  following authorized turn, not left in the tree. · fixed-by-recipe)
- 2026-11-22 · dev(C01) · **needle homes assigned to a tier that cannot write them + one plan premise flat
  wrong + one defective needle.** (a) The test wave called `amd_gpu_testlib.py`'s python constants "dev's C01
  edit site", but dev's permissions deny `tests/**` — its probe edit returned `Permission denied: edit`, and
  `git status` proves ZERO test paths in its 9-file set. (b) The plan says C01 flips pool-name legs INSIDE
  `charts/radiance/tests`: false. Radiance carries no pool-name constants; it reddens through the `AMDNAMES`
  import chain, so C01 took it 24F→33F (9 constants-lag legs, one root cause) before NI-1 could fix them.
  (c) `test_provenance.py:512` asserts `R9700_PRODUCT_STRING == "gpu-r9700"`, contradicting :326/:330 in the
  same file AND the sanitizer law (`sanitize('gpu-r9700') == 'gpu-gpu-r9700'`) — unsatisfiable by ANY legal
  implementation, and not constants-lag. (d) `TEST_SPEC.md:4556`: the test wave's own C01 heading carries the
  retired literal whole, so the suite flags its own record.
  · resolution: NI-1/NI-2 routed to the test session (repo law: a faulty validation is never fixed by
  reviewer or coordinator), with the assembled-constant law restated so the retired literal is never
  contiguous. General rule for later chunks: **never assign a test-file edit to dev** — needles are
  test-owned by permission design; the bash twin pre-flip was right, the python twin should have been too.
  · fixed-by-routing (class OPEN: audit every remaining chunk for "test-file edit assigned to a tier that
  cannot write it")
- 2026-11-22 · dev(C01) · **two legs flipped green EARLY — gate integrity, not progress.** (a)
  `test_c04_supersession_annotation_on_the_2026_10_27_ruling` went green on dev's incidental
  `renamed 2026-11-22` comment at `charts/llama-swap/values.yaml:1352`: a date token satisfied it, not the
  supersession. (b) runbook **T5** flipped green during C01 though the plan booked it for C06 (stash-proven:
  its baseline-red cause was exactly the new-name gate-(a) needle).
  · resolution: (a) re-anchored to the substance of C04 (real claim + same-wave `replicas: 0`) and kept a
  DESIGNED RED; (b) recorded — C06's leg set is one smaller, and no reviewer may read an early-green leg as
  its chunk's work being done. · fixed-by-repair / recorded
- 2026-11-22 · dev(C01) · **the two zero-stale sweeps scan different tokens**: bash n3 greps the PREFIXED
  `amd.com/gpu-r9700-1`, the pytest AC4 leg greps pool-only `gpu-r9700-1`, so their file lists legitimately
  differ — treating one as proof of the other reads as "the sweep is broken" when it is not.
  · resolution: always name which sweep produced which list. · fixed-by-this-recipe
- 2026-11-22 · dev(C01) · **stale prose deliberately left behind, per chunk law**: `charts/amd-gpu/values.yaml`
  header "(one device each on the ai-gpu node)" survives C01 (C06 owns it); the in-comment lever cite
  `appset-charts.yaml:83` was stale and was corrected to `:67-70` inside C01's sweep.
  · resolution: C06 carries the header prose; the cite correction rides C01's commit. · open (C06)
- 2026-11-22 · dev(C01) · **roster T4's harness faults before the leg executes** (`cp: cannot stat
  radiance-multi-instance-roster.md`) where it should SKIP with a designed-red message; sibling arms T1-T3
  fail correctly for the same missing-note cause.
  · resolution: handed to the test session to harden the arm harness; the red itself is right (the roster doc
  is C06's to author). · open (repair in flight)
- 2026-11-22 · dev(C01) · **pipe caveat + self-report drift, both settled by disk**: pytest behind a pipe loses
  `$?` (counts then come from pytest's own summary line), and dev's interim "12 files changed" was actually 9
  per `git status`.
  · resolution: capture rc un-piped whenever a status is being CLAIMED; settle scope from disk, never from a
  mid-run self-report. · fixed-by-this-recipe
- 2026-11-22 · review(C01) · **`amd-gpu-naming.sh` n2 is a FILE-SET guard, not a content guard** — `wave_a()`
  (:204-208) only greps `git show --stat` for the three paths, so a green n2 proves the wave is CO-LOCATED,
  never that the claim lines actually moved. The reviewer audited content itself (hand-ran n3's quoted-or-bare
  pattern → the 4 live claim lines; the old bare-only pattern → 0), and THAT is what proved atomicity.
  · resolution: every later rename/carrier-wave review pairs the file-set guard with a content audit; never
  cite n2 alone as "the wave is atomic". Separately: `test_provenance.py`'s `_NEW_NAME_ALLOW` comment still
  says "the two current docs" where four now carry the name (comment-only staleness; prefix matching works).
  · fixed-by-this-recipe
- 2026-11-22 · review(C01) · **raw `grep -rn` for the retired literal reports gitignored `__pycache__/*.pyc`**
  in any worktree that has run pytest — CPython constant-folds `"gpu-r9700" + "-1"`, so the retired bytes are
  real in the .pyc. The needles filter `__pycache__|\.pyc` (naming.sh:318); a human re-running the sweep does
  not know that. · resolution: add `--binary-files=without-match` for manual sweeps; three matching .pyc files
  are NOT a leak (`.gitignore:14`, absent from porcelain). · fixed-by-this-recipe
- 2026-11-22 · review(C01) · **NOTES.txt cannot be rendered cluster-free**: `helm template --show-only
  templates/NOTES.txt` fails (helm excludes NOTES) and `helm install --dry-run=client` fails on a forbidden
  API read for the workspace SA. · resolution: rely on `helm lint` (parses all templates) + the executed NOTES
  legs; the reviewer reported render-through-install as UNVERIFIED instead of crediting it. Do not burn a round
  trying to observe it. · fixed-by-this-recipe
- 2026-11-22 · review(C01) · **the roster T4 harness repair was reported "in flight" and did NOT land** —
  `4c267ca58` carried NI-1/NI-2/C04-re-arm only, so `radiance-roster.sh:172` still `cp`-faults before its
  designed-red message prints (polarity right, message wrong).
  · resolution: re-issued to the test session with the comment staleness; the earlier "in flight" is corrected
  here so nobody reads it as done. · open (test session, batched)
- 2026-11-22 · coord · **`chunks/*.md` are not editable by my tier** (the edit surfaced as a denied `ask`),
  which collides with a real need: C01's review found scope no chunk file carried — FRICTION merely NAMED C06
  as owner of the `charts/amd-gpu/values.yaml:30` "one device each" prose, and `grep "one device each"
  chunks/*.md` → 0 hits, so a false post-TP2 statement would have survived the ticket by nobody's decision.
  · resolution: amendments travel as DECISIONS rulings (D32) + the chunk's LAUNCH BRIEF, and the planner folds
  the chunk file at the next plan touch. Lesson: **a FRICTION ownership note is not a work item** — prose that
  must change belongs in the chunk contract or the brief that hands it over. · fixed-by-recipe (machinery half
  OPEN: a coord-legal way to amend chunk scope without a full plan round)
- 2026-11-22 · review(C01) · **a review brief must not list the write arm as expected-green**: my C01 launch
  said "M6 green", yet repo law bars read-only sessions from running it — the correct behavior was to run
  nothing and claim nothing, which is what happened. · resolution: later briefs say "M6: not run, no claim"
  (DECISIONS D33(c)). · fixed-by-this-recipe
- 2026-11-22 · dev(C02) · **the D30 re-pin sweep MISSED a suite: `tests/agent-board-coord/rulesync-surface.sh`
  arm c11 still demanded the cf-83-era routing** (`'flash' 'local' 'flash-next-strata' 'assume'` inside 600
  chars of the boards mirror), which the re-pinned authority itself forbids (`pipeline-models/surface.sh:668`
  bars strata text from boards; `:662` requires radiance in the same window). Green at baseline, red after
  C02, and unsatisfiable without needle-hacking (a bare `-strata` token would pass the stale leg while
  violating the intent at `:664-667`). Its header still read "red before C01 dev".
  · resolution: re-pin routed to the test session with the dated ruling chain in the leg message. Lesson:
  **a routing-authority re-pin must enumerate every suite that byte-pins routing prose**, not only the suites
  the plan named — the test wave's list came from EXPLORE §1 and this file was not in it. · open (in flight)
- 2026-11-22 · dev(C02) · **two reds proved PRE-EXISTING by building a scratch detached worktree at HEAD**
  (`rulesync-surface` c19, `gate` t17) — the right way to separate "my change broke it" from "it was already
  broken", at the cost of one throwaway worktree.
  · resolution: per-arm characterization demanded from the test session — stale test encoding / later chunk of
  this ticket / outside-the-ticket drift — none absorbed silently. · open (classification owed)
- 2026-11-22 · coord · **the roster T4 harness fix was reported "in flight" twice and shipped neither time**
  (`4c267ca58` carried NI-1/NI-2/C04-re-arm only). A repeated promise that never lands reads as progress in
  the record, which is worse than an honest open row.
  · resolution: batched into the current repair turn with proof demanded (run T4 alone, quote the new message).
  Standing rule: **an escalation closes on observed output, never on an intention.** · CLOSED 2026-11-22: the fences shipped in `2ee1313a2` (`require_note` guarding T2's python traceback, T3's
     misleading grep error, T4's `cp: cannot stat`), and C02's review observed the identical clean line per arm
     with exit 1 — quoted output, as demanded. · fixed
- 2026-11-22 · review(C02) · **the write-arm family is bigger than M6**: a read-only review tier must decline
  FOUR legs, not one — `pipeline-models/surface.sh M6`, `agents-md.sh c1`, `rulesync-surface.sh c7`,
  `gate.sh t14` — while `npx --yes rulesync@37.0.0 generate --check` (exit 0, "All files are up to date") is
  the legitimate read-only sync evidence. Consequence: "the second generate is a no-op" is UNVERIFIABLE by a
  read-only reviewer, so that claim belongs to a writer session's transcript, never to a review verdict.
  · resolution: briefs enumerate all four as "not run, no claim" (generalizes D33(c)). · fixed-by-this-recipe
- 2026-11-22 · review(C02) · **two reds are OUTSIDE this ticket and have no owner here**: `rulesync-surface`
  **c19** (cf-85 pinned "exactly one" custom field; cf-124 legitimately grew the roster to slug+Priority,
  scoped AC2 around it, and left AC3 for a ruling nobody has given) and `gate` **t17** (warm-location
  permissions drift). Blast radius verified zero: `git diff main...HEAD` touches no roster file and no
  subagent file. Until ruled, every later gate run carries both BY NAME so they are not re-read as this
  ticket's regressions.
  · resolution: cleanest landing is one follow-up card each (owner decision); meanwhile they ride the
  final-review packet as documented pre-existing. · open (owner: card or rule)
- 2026-11-22 · review(C02) · **stale ok-count baselines in the plan's `## Commands`**: it recorded
  `cf106-noop 8 ok · noop-marker 9 ok`; both observed **11 ok** with the suite files byte-identical to scout
  HEAD (last touched pre-ticket). Scout-era counts, not drift — but a stale expected number turns an honest
  green into a "finding", so later rounds read 11/11 from this row until the planner folds the plan file.
  · open (planner fold owed: my tier cannot edit the plan of record OR `chunks/*.md` — both are plan-role
  surfaces; see the coord row on chunk-scope amendments)
  · **THIS ROW WAS WRONG — CORRECTED 2026-11-22 by the test session's git-history sweep.** The "11 ok"
  measurement (taken at C03's review and folded into the plan of record by me) is impossible on this repo's
  history: every committed revision of `cf106-noop/surface.sh` has carried only 7 or 8 `ok` calls
  (`67b029cb9`, `7bebb3505`) and `noop-marker/surface.sh` only 5/5/5/6/9/9 across six revisions
  (`197598170`→`7790414fe`). Neither file ever had eleven. Invocation mode cannot inflate the count either —
  arms are `want`-gated, one `ok` each, so a full-suite run is the maximum. **The scout-era 8/9 was right all
  along, and my "the scout baseline was stale" re-baseline inverted the truth.** Authoritative statement for
  the plan: `bash tests/cf106-noop/surface.sh` → 8 ok (rc 0) · `bash tests/noop-marker/surface.sh` → 9 ok
  (rc 0), full-suite invocation; per-arm runs print fewer `ok` lines BY DESIGN and are not a count mismatch.
  Lesson, and it is mine: **a single review measurement is not a baseline.** Before overwriting a recorded
  expectation I must reproduce it twice or read the source of truth (here: `grep -c '^\s*ok '` across
  revisions), because I did the opposite — trusted one observation and "corrected" a number that was right. ·
  fixed-by-evidence (planner still owes the plan `:152-153` fold; `chunks/*.md` and the plan file are not
  editable by my tier)
- 2026-11-22 · coord-ruling D34 · **aislop: do NOT re-wrap the moved YAML comments.** The edit-time plugin runs
  `aislop scan --changes` (advisory: echoes every diagnostic; `.opencode/plugin/aislop-gate/index.ts:62`), while
  the gate is `aislop ci --changes`, which fails only below `failBelow: 80` or on ERROR-severity findings
  (`.aislop/config.yml:23-24`) — warnings never fail it. And on aislop@0.20.0 **YAML is outside the scan scope
  entirely** (verified with a ruff-bearing PATH: full-repo scan = zero findings in any `values.yaml`; prod-dir
  scan resolves to 0 files; `ci --changes --json` scores 100 with 0 diagnostics), so dev's ~219-line echo could
  not be reproduced on the pinned version and never reached the gate. Re-wrapping would churn relocated lane
  bytes for a class the gate cannot flag — the repo already carries 63 over-length lines in that file.
  · resolution: moved comments stay wrapped as moved; if the echo recurs, capture the plugin output verbatim
  (likely a session with different tool availability). · fixed-by-ruling
- 2026-11-22 · test wave · **C03's mechanism claim VERIFIED independently, and it indicts the plan.** From the
  tgz extracted to `/tmp/opencode/at501`: `_command.tpl`/`_args.tpl` render via plain `toYaml` with **no `tpl`**,
  while `_name`/`_env`/`_probes`/`_volumeMounts` ARE tpl'd (lifecycle raw at `container/_spec.tpl:27-28`). The
  only in-library tpl carriers are configMap data (`classes/_configmap.tpl:37`) and env values — and a
  configMap-mounted script adds `checksum/configMaps` (`lib/pod/metadata/_annotations.tpl:54,61`) plus a volume
  and a volumeMount and rewrites the init `command`, so **both equivalence fixtures fail**. Consequence: under
  the no-byte-move law, per-block literal scripts are the ONLY possible shape, and the plan's
  "parameterized init" row (plan ~:205) + C03 task-1 wording are a plan-internal contradiction, now surfaced to
  the owner. · resolution: byte-equivalence kept; the supersession row gets corrected whichever way the ruling
  goes. · SUPERSEDED by D35 (owner, 2026-11-22): byte-equivalence is RELAXED for this one carrier — the chart owns the script and AC1 becomes an intentional-delta proof over exactly four paths. The contradiction this row surfaced was real and is now ruled, not worked around. · closed-by-ruling
- 2026-11-22 · dev(C03 r2) · **two authoring defects shipped inside the delta-budget suite.** (a) My D35
  shorthand "`spec.volumes`" was transcribed literally into `DELTA_BUDGET` as `$.spec.volumes`, but the suite's
  diff grammar is DEPLOYMENT-rooted and a Deployment has no `spec.volumes` — so BOTH arms of the delta leg
  failed for any carrier (the real pod-volume path fell outside the budget, and the budgeted entry can never
  exist). (b) `_assert_block_shape()` takes 3 parameters while both call sites pass 4 → `TypeError`, so two
  legs asserted nothing at all.
  · resolution: path annotation added to DECISIONS D35 (intent unchanged; never widen a budget to fit a bad
  needle), repairs routed to the test session with a demand to re-confirm the planted-drift teeth AFTER the
  path fix and to plant one NEW unauthorized drift the old needle would have missed. Rule for every path-list
  gate: state paths in the grammar the comparing code actually uses, and re-derive a quoted path from the
  object being diffed rather than from ruling prose. · open (repair in flight)
- 2026-11-22 · dev(C03 r2) · **the correct shape of a test-blocked handoff**: dev proved its delta out-of-band
  (replaying the 3-arg body in a scratch script; replaying the diff under correct grammar), reported
  NEEDS_INFO, and left the legs red with the fixtures byte-untouched — no fixture laundering, no test edit, no
  "temporary relaxation". It also caught my stale brief baseline (llama-swap 510P, not 509P) and re-measured
  with its own files reverted to show the suite was unmoved.
  · resolution: treat out-of-band proof + honestly red legs as a PASSING handoff shape; a green obtained by
  editing the gate is not. Applied to C04-C06 briefs. · fixed-by-this-recipe
- 2026-11-22 · dev(C03 r2) · **`.aislop/history.jsonl` gains a line whenever the aislop CLI runs** — it is
  machine churn, not a work artifact, and it keeps showing up in porcelain output mid-round.
  · resolution: disposition requested from the test session via `git log -- .aislop/history.jsonl`; until then
  I neither stage nor read meaning into it. · open (history.jsonl disposition)
- 2026-11-22 · review(C02) · **`boards` SKILL "Default selection: `Qwen Dense`" now reads two ways** — the board
  RULE's checked item (accurate: OQ13, rule dormant) versus the blank-route default (radiance). NOT fixable
  inside C02: c11 and M5 pin the sentence verbatim as HOLD, so prose tidying would break two green arms, and
  the vocabulary itself is a Deferred owner leg.
  · resolution: belongs to the board-provisioning follow-up as ONE coordinated set — the live rule's default
  check + this line + the c11/M5 needles (TEST_SPEC §4 anticipates the move). · open (owner leg)
- 2026-11-22 · dev(C03) · **AC5 as written is UNREACHABLE in a dev session, structurally**: "the radiance suite
  goes green with the relocated carriers" cannot happen from a dev tier — 19 legs across 12 sites bind the
  PRE-C03 carriers and dev never edits tests (D30). Three sites were missing from the chunk's own relocation
  list (`test_renovate_ledger.py:106-112`, `llama-swap/test_coexistence_wiring.py`,
  `pipeline-models/surface.sh:1016-1020`), so the suite went 24F→37F instead of converging.
  · resolution: any chunk that MOVES a data home needs an explicit **test pass between dev and review**, and a
  relocation list must be built by grepping the OLD carrier rather than recalled. Standing recipe for later
  chunks; never gate a dev round on "suite green" when the green is test-owned. · fixed-by-this-recipe (the
  plan's Commands should list the intermediate test pass — planner fold owed)
- 2026-11-22 · dev(C03) · **aislop edit-time noise vs ci-gate silence**: the edit-time plugin echoed
  "long line" on ~219 PRE-EXISTING lines of `services/gpu-ai/prod/values.yaml` (moved comments land at a deeper
  indent) while `aislop ci --changes` reported 0 errors / 0 warnings over 112 files. Dev treated it as
  advisory rather than re-wrapping 219 lines of somebody else's prose — correct restraint.
  · resolution: scope question sent to the test session against `.aislop/config.yml` (ci scope ≠ edit-time
  scope?); re-wrap of moved comments only if the gate demands it. · open (verification in flight)
- 2026-11-22 · coord · **one C03 leg is a design fork, not a defect.**
  `test_c03_generic_shell.py:154` demands the q27 block DROP its whole init script in favour of scalars; dev
  shows that cannot coexist with byte-equivalence AC1 if app-template renders `command`/`args` verbatim (no
  `tpl`). Dev kept AC1+AC2 and left the leg RED instead of bending the equivalence gate — the right call for a
  chunk whose whole purpose is "relocation, not re-decision". The plan's own supersession row promised
  "parameterized init", so this is an owner question, not a coord ruling.
  · resolution: mechanism claim being independently verified (dependency tgz extracted under `/tmp/opencode`,
  never into the repo) before the owner is asked, so the trade is stated on evidence: keep script bytes in the
  lane block (equivalence intact) vs move them to a chart-side/env carrier (parameterized, but the rendered
  pod spec changes and the fixtures must be re-derived). · open (verification + owner ruling)
