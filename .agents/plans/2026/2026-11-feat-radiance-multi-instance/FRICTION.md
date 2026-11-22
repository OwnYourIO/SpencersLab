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
  one porcelain call every time; no surface reports it automatically)
