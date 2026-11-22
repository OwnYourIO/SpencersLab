# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives
rejected, why.

## Conventions
- D-number namespace: THIS ticket's decisions occupy D1–D25; any citation to another ticket's
  decision (cf-143/cf-144/cf-86 …) MUST carry its ticket prefix — bare `D21`, `D24`, `D8`, `D13`
  mean THIS file. (cf-143 recycles the same numbers; unqualified reuse is a dev-error generator.)
- Pool string law: from C01's wave the ONLY live name is `amd.com/gpu-r9700`;
  `amd.com/gpu-r9700-1` joins `gpu-ai-pro-r9700` as a historical name that may survive ONLY
  outside AC4's scan scopes (plan folders, git) and as bracketed transcription-correction notes.
  The new HISTORICAL constant stays ASSEMBLED (`"gpu-r9700" + "-1"`) — the substring relationship
  (new name is a prefix of old) means any literal leaks the sweep trips itself. `amd.com/r9700` /
  `amd.com/r9700-1` stay impossible-by-construction (§R7-Q1 code constants) and barred.
- Constants-site law (cf-143 D24 carry-over): name needles are `charts/amd-gpu/tests/amd_gpu_testlib.py`
  (python canonical) + the marked bash blocks (`tests/services/amd-gpu-naming.sh`,
  `tests/notes/radiance-{runbook,tp2}.sh`) — one edit site per language, never needle archaeology.
- Sizing laws this ticket TRANSCRIBES and never re-decides: fn memory HELD 110 (cf-144 P11 — the
  post-boot DOWN re-pin is cf-144's deferred owner leg, not here); q27 24Gi + claim-1 overlay pin
  (P05); every new number is boot-print-adjudicated (cf-143 D28(6)/D30(2)); `--expert-vs-cache-ratio`
  never ships.
- Carrier law (cf-143 D26): extended-resource claims cross the appset→Application chain as POSITIVE
  ADD/UPDATE only (nulls die, 0 illegal). From C03 the radiance lanes' claim carrier is the
  per-release service block (n3 relocated); the chart ships NO claim (OQ-D posture).
- Keyless-cf-143-D8 survives: no bitwardenIds / no ExternalSecret / NO `custom-values/` leg for any
  radiance lane. "Generic shell + exact settings per instance" = the service roster blocks (the
  appset `index $.Values $appName` channel). `OVERRIDE_VIA_CUSTOM_VALUES` keeps its repo meaning:
  secrets-only carrier. (Ask 4's convention reconciliation; the cf-143/cf-144 "one chart-value
  home" (D15) single-source law is DELIBERATELY superseded for charts/radiance — per-instance
  DATA home is the block, chart = mechanism.)
- Doc-edit law: annotate, never rewrite (dated markers, T1/T2-resolvable citations); the ONLY
  exception class is the cf-143 D24-precedent NAME-TOKEN sweep inside AC4-scanned surfaces (C01) and the
  bracketed transcription-correction idiom for factual mis-quotes — both move tokens, neither
  rewrites narrative.
- `export PATH=$HOME/.local/bin:$PATH` before any helm-backed run; pytest per-directory; never run
  the rulesync-WRITING legs (`surface.sh` M6, agents-md c1, gate t14, rulesync-surface c7) in a
  read-only session; evidence YAMLs are test-session property, dev conforms.
- Git law unchanged: coordinator is sole committer; nothing pushes/merges/advances main; landing
  = owner push/PR/merge/sync (pipeline-push-pr discipline; Deployment is a checked HITL stage).

## Decisions
- 2026-11-22 plan D1 (**base = main @ 193c12798, cf-144 is the BASE not a prerequisite**): the
  launch brief's "cf-144 unpushed / in Review" is stale (EXPLORE §0 deviation, re-verified by
  plan-session git reads); the TP2 chart-arg literals this ticket relocates are the SHIPPED ones.
  Alternatives rejected: rebasing on the cf-144 branch (content-identical, verified empty diff).
- 2026-11-22 plan D2 (**rename is ONE atomic wave (C01), ids-table + every claim + every sweep
  needle + the two stale-prose fixes in one commit**): R-Q5's mechanism law — old name → capacity 0
  permanently, old-name pods Pending-forever with no bare fallback (bare sits at 0), table read
  once at startup; any two-step ordering orphans a pod class in the gap. The stale "each pool holds
  one device" comment (RESEARCH C1) and NOTES.txt:25 ride the same commit (they describe the very
  mechanism being renamed). Rejected: separate docs wave (the prose IS the claim's law text).
- 2026-11-22 plan D3 (**notes name-token sweep in place, cf-143 D24 precedent; history stays in
  plan-folders/git**): AC4 scans `.agents/notes/`, so the old token cannot survive there; the
  alternative (AC4 carve-out for receipt quotes) was rejected — it dulls the ticket's own
  completeness sweep on the exact class of residue it must catch, and cf-143 C14-r1 already owns
  the in-place-with-bracketed-note idiom for quoted text.
- 2026-11-22 plan D4 (**routing wave (C02) ships radiance as BOTH tiers' default; Dense+Local and
  the 10+-background legs keep their `27b-q4` routes; q27 stays never-default**): matches the
  owner's "for everything" + how this run itself launched; fn is the only hot lane (live 1/1,
  boots-once, no lazy-load penalty — EXPLORE §1) and the 502-loud law covers fn-down. Runner-
  literal scope is OQ-A (recommended: MOVE it too — the strata lane is 0/0 today, making the
  current runner literal an idle hop, and the loop is literally the board-coord's context; scout
  guessed defaults-only, the owner's verbatim wins the recommendation). Pre-existing reds
  (provider-loops t1/t3, agents-md c11) are dispositioned in-wave either way — never carried
  silently.
- 2026-11-22 plan D5 (**ask 3's honest shape: pool arithmetic + receipts, NOT per-card pins**):
  R-Q1/R-Q4/R-Q6 verdicts — the pinned plugin injects no env and has no visibility strategy
  (per-lane specific-card pinning is structurally impossible in the plugin path); one-card-under-
  two-names is a double-booking trap. Shipped determinism statement (acceptance criteria phrase
  it EXACTLY so): (a) a free single-card claim takes the lowest-KFD-NodeId card (advisory-at-API,
  source-pinned-at-v1.31.0.12), (b) concurrent claims take distinct cards by occupancy, (c) a TP2
  claim gets both, (d) "lane X pinned to c3/c7" is NOT expressible here. OQ-B presents the owner
  ruling; the recommended leg is (a)-values+receipts; strata keeps hostPath per the standing
  2026-10-27 ruling.
- 2026-11-22 plan D6 (**OQ-R1/OQ-R2 become OWNER-RECEIPT legs inside C04, never blind pins**): no
  agent tier has pod exec; the UUID form is opt-in strictly after a landed nonzero-unique_id
  receipt (silent-truncation failure class); the NodeId→BDF map is recorded, not assumed (best
  guess c3). cf-144 P15's paste-collection pattern at the chunk's turn is the mechanism.
- 2026-11-22 plan D7 (**generic shell: chart = mechanism, per-release service blocks = data;
  fn-TP2 + q27-TP1 transcribe with render BYTE-EQUIVALENCE proof (C03), then two new resting
  lanes (C05)**): the q27 pod-swap and roster `chart:` lever already prove both halves live
  (EXPLORE §4a). Alternatives rejected: sibling chart dirs (cf-143 D56(1) law — pin/ledger/grammar drift
  duplication); per-cluster template discrimination (repo law); custom-values channel
  (secrets-only). The inert `radianceFetch.sourceDir` trap (gotcha 11) dies by parameterizing the
  init script (PACK/LFS_SHA/URL/MARKER scalars) while D27's BusyBox-portable equality gate +
  image-identity legs survive in the template.
- 2026-11-22 plan D8 (**lane naming (OQ-C best guess): keep `radiance` (flash-TP2) +
  `radiance-q27` (27b-TP1) keys/Applications byte-stable; add `radiance-flash-tp1` +
  `radiance-q27-tp2`**): renaming the live keys would prune+recreate the running fn Application
  and rewrite peers/evidence pins for symmetry alone. Rejected: symmetric 4-rename (a second live
  churn wave).
- 2026-11-22 plan D9 (**new served ids = suffixed base ids, ONE catalog row each (no priority
  siblings yet); three-surface join in law order evidence→peers→catalog; peers floors 5/4 per
  lane class**): honest-id law (D7-cf143) bars reusing existing ids across lanes; two peers
  declaring one id is ambiguity. Trios join only when a lane becomes a routed tier (owner's
  priority policy then).
- 2026-11-22 plan D10 (**lane profiles: flash-TP1 = git-history transcription of the cf-143 TP1
  array (110Gi held, claim 1, replicas 0); 27b-TP2 = q27 array + `--tp 2 --tp-wire wht6` (24Gi
  held, claim 2, replicas 0)**): transcriptions with a shipped precedent beat inventions; every
  number stays boot-print-adjudicated. Claim-math documented: one TP2 class UP at a time;
  flash-TP1+27b-TP1 fit the pool but NOT RAM at held values (110+24+~5.3 > 125.08) — stated, not
  silently mitigated (the P11 re-pin outside this ticket is what re-opens it).
- 2026-11-22 plan D11 (**DRA: zero chart work; revisit triggers recorded — a release carrying
  `extendedResourceName` AND issue #75 closed; then CEL on `pciBusID` ONLY (productName empty on
  R9700, DRM-minor names reboot-unstable)**): R-Q3 verdict; adopting now trades one proven
  weakness for three live ones.
- 2026-11-22 plan D12 (**chunk/wave shape: C01+C02 wave 1 (independent, id order) → C03+C04 wave 2
  (independent of each other) → C05 wave 3 → C06 wave 4**): validates the scout's landing-order
  hint with mechanisms — rename first (atomic sync set, every later string quotes the final name),
  routing next (zero GPU-file overlap, clears pre-existing reds early), restructure last (depends
  on final pool name + relocated carrier + a settled surface.sh base); C05→C02 edge is a byte-pin
  conflict (both touch surface.sh/M8 + the favorited table), C05→C03 is interface (the shell must
  exist before the new blocks feed it), C06 last (annotations quote the shipped shape).
- 2026-11-22 plan D13 (**FOLD PROVENANCE — this is the re-launched planning session's folded set;
  the superseded sibling 4-chunk draft (routing-first: C01 routing / C02 rename / C03 shell /
  C04 fleet) is preserved VERBATIM in `PARALLEL-DRAFT.md`**): planning launched twice in parallel
  (coordinator FRICTION rows 2026-11-22), both hand-backs reported cancelled, the coordinator
  ruled the re-launch owns the fold. The two drafts AGREED on: rename atomicity + mechanism,
  routing-site inventory, never-default/502-idle laws, owner-receipt shaping of OQ-R1/R2, the
  three-surface id join, landing shape, board-vocabulary staying out-of-ticket. Differences folded
  toward this set: rename-first wave 1 (the atomic-sync story is cleaner when the rename leads and
  no routing commit can ever be mistaken for part of its set); a 6-chunk split (the sibling's C04
  merged ask-3 receipts + the lane add + docs into one L chunk — split per the role's reviewability
  rule: the receipts leg is owner-gated and must close as an honest no-op WITHOUT holding the lane
  add, and the docs wave must trail both). OQ set extended (the sibling's Dense-row OQ-K kept as
  OQ-J; its trio-priority proposal kept as OQ-E's alternative; its `radiance-27b-tp2` key variant
  noted under OQ-C). Absorbed verbatim: the sanitizer-port reachability proof, the
  `r9700([^0-9-]|$)` word-boundary pattern, the TEST_SPEC.md:3762 history-site, the
  "provider-loops exits 0 despite RED t1" tail-behavior (C02 AC3 now asserts the FAIL-line count),
  the "tests/ sibling dir fires NO workflow" CI note. Nothing in the sibling draft was deleted —
  the record is the product (cf-143 law).
- 2026-11-22 plan D14 (**marketing-string reading (OQ-I) resolved to mechanism, kept open for
  the round**): the launch cites "ids-table row `7551 C0` marketing → `AI PRO R9700`" beside a
  target pool `amd.com/gpu-r9700`; the suite's sanitizer port PROVES the marketing string derives
  `gpu-ai-pro-r9700` (fillers drop, `pro` kept) — mechanically incompatible with the stated target.
  Best guess: product field becomes exactly `r9700`; `AMD Radeon AI PRO R9700` is recorded as the
  row's marketing IDENTITY in the ledger comment. If the owner truly wants the pool re-named to
  the marketing derivation, that flips the ticket's target — C01's notes stop the dev there.
- 2026-11-22 rework D15 (**BATCHED ROUND ANSWERED — letter map + fold provenance**): the owner's
  answers arrived numbered against the SIBLING draft's lettering (PARALLEL-DRAFT.md); mapped onto
  THIS plan's authoritative letters: owner-1 → **OQ-A** (sibling OQ-4), owner-2 → **OQ-B** (ask-3
  mechanism; no sibling letter), owner-3 → **OQ-C**, owner-4 → **OQ-E** (sibling OQ-5/I-adjacent),
  owner-5 → **OQ-J** (sibling kept this as adopted-D, no letter), owner-6 → **OQ-I** (sibling OQ-2),
  owner-7 → **OQ-H + OQ-R2/OQ-R3**. Owner verdict: "Approve — run all waves" — the coordinator flips
  `plan_status`; this write leaves it draft (plan-agent law). Pitfall recorded in FRICTION: rework
  rounds must cite the folded plan's letters as authoritative.
- 2026-11-22 owner-ruling D16 (**RUNNER LITERAL MOVES TO RADIANCE (OQ-A answer) — fresh owner
  ruling dated 2026-11-22, superseding the 2026-11-09 strata-q4 runner ruling**): the 2026-11-09
  ruling's own clause says the literal "moves only by a fresh user ruling" — this is that ruling.
  Full Leg B becomes mandatory (no longer conditional): `.agents/loops/pipeline-worker.md:5` + its
  ruling comment, `.rulesync/rules/overview.md:304` (+ AGENTS.md regeneration), provider-loops
  t1/t3 + agents-md c11 + the tsx tick `pipeline-locks-tick.test.ts:163` byte-pin all re-pin to
  `gpu-ai/qwen3.8-flash-next-radiance`, and M8-H's diff-inventory touch-bar is re-authored into a
  PAIRING leg (all six surfaces must carry the same literal; touching one without moving the others
  fails). Consequence accepted at ruling time: the strata lane is 0/0 today (EXPLORE), so the
  old literal was routing the hourly runner to an idle-502 hop; the fn lane is the runner's model —
  fn-down now also stalls the scheduled runner (same SPOF the coord defaults already carry).
- 2026-11-22 owner-ruling D17 (**OQ-B lands on (b): llama-swap/strata gets a REAL claim on the
  renamed `amd.com/gpu-r9700` pool — OVERTURNS the standing 2026-10-27 device-access ruling's
  no-claim posture**): D5's shipped-shape ("strata keeps hostPath, zero claims") is SUPERSEDED in
  that half; the D5 determinism LAWS (R-Q1 lowest-NodeId, R-Q4 exclusivity, no specific-card
  expressibility) survive and become the documentation authority. Mechanism chosen (b1): claim
  POSITIVE-ADDED on the gpu-ai SERVICE OVERLAY (D26 carrier law — nulls die in the appset→valuesObject
  chain; the cf-143 C07/C10 APU-claim idiom at `services/gpu-ai/prod/values.yaml:188-205` is the
  shape precedent), count 1 + requests mirror; **hostPath `/dev/kfd`+`/dev/dri`, privileged and the
  rocrVisibleDevices carriers STAY byte-kept** (b1, not b2): RESEARCH R-Q5 shows the patched plugin
  mounts `/dev/kfd`+`/dev/vdi` only — llama.cpp needs the `/dev/dri` render nodes — and
  `charts/llama-swap/values.yaml:1352-1360` already legislated the b1 shape in anticipation ("Strata
  keeps this privileged hostPath shape either way: per-name pools settle cross-card choice, never
  VRAM arbitration, and hostPath sits outside plugin accounting entirely"). Honest scope of the
  claim: SCHEDULING exclusivity + NodeId-order card allocation at the scheduler; in-container device
  visibility remains ordinal/hostPath territory, so the R1/R2 receipt discipline still governs —
  the claim does NOT make card selection inside the pod deterministic. Scheduling consequence
  (the round's material discovery): strata renders `replicas: 1` today
  (evidence `charts/llama-swap/tests/evidence/cf143-pre-ticket-strata/gpu-ai.strata-docs.yaml:44`);
  with claim 1 against the 2-card pool and the approved fn lane at claim 2 replicas 1, strata would
  Pending-forever — so the git steady state MUST park strata at `replicas: 0` in the same commit
  (parking-in-the-same-wave also prevents any apply-time Pending). That parking is not in the
  owner-approved lane table (computed without strata) ⇒ surfaced as OQ-K with recommendation
  (park = the only resolution consistent with fn-live-approved); NO invented resolution.
- 2026-11-22 owner-ruling D18 (**OQ-C SETTLED as proposed (D8 stands as ruling)**): keep live keys
  `radiance` + `radiance-q27`; ADD `radiance-flash-tp1` + `radiance-q27-tp2`.
- 2026-11-22 owner-ruling D19 (**OQ-E: FULL TRIOS REGISTERED NOW (deploy-ready), D9's base-row-only
  default SUPERSEDED**): each new lane gets its complete catalog trio with strictly-below-live
  priority classes — sibling proposal adopted as the starting shape (flash-tp1 7/3/2, 27b-tp2
  6/2/1 in the fn 9/5/1 / q27 8/4/0 urgent/base/low grammar), class-column uniqueness across the
  radiance family resolved by the TEST AUTHOR (note the shipped collision: proposed 27b-tp2 low=1
  duplicates fn's low=1); M8 frozen-delta widens to +6 added rows. The "-urgent/-low siblings join
  later" deferral (plan Deferred / STATE deferred) is WITHDRAWN.
- 2026-11-22 owner-ruling D20 (**OQ-J: explicit `Qwen Dense + Local` routes to
  `gpu-ai/qwen3.8-27b-radiance` (the parked q27 lane) — D4's kept-27b-q4 row SUPERSEDED**): the
  owner chose the literal "everything → radiance[-family]" over the 502-trap recommendation.
  ACCEPTED CONSEQUENCE, recorded so nobody refiles it as a bug: an explicit Dense+Local card now
  routes to a lane at `replicas: 0` and answers 502-loud until a manual scale-up. Moves:
  pipeline-models `:35` row + kickoff/boards tables + M1/M5 needles (M5 `:579` 27b+Local window).
  The `10+` background leg stays `gpu-ai/qwen3.8-27b-q4` (llama.cpp outer-swap leg, surface.sh
  `:750-751` REQUIRES it — not part of this row).
- 2026-11-22 owner-ruling D21 (**OQ-I SETTLED BY the rename answer (D14's best guess ratified)**):
  the 7551/C0 ids-row PRODUCT FIELD becomes exactly `r9700` (the sanitizer port proves
  `AI PRO R9700` derives the historical `gpu-ai-pro-r9700`, not the target pool); `AMD Radeon AI
  PRO R9700` is recorded as the row's marketing identity in the ledger comment. C01's stop-condition
  for the alternative derivation is retired.
- 2026-11-22 owner-ruling D22 (**OQ-H/OQ-R2/OQ-R3 answered**): in-ticket atomic wave stays (D2
  intact). OQ-R1: the owner WILL paste the `unique_id` receipt at C04's turn — the UUID-upgrade arm
  stays LIVE, gated strictly on that paste (never blind). OQ-R2: the owner elects to RE-USE
  cf-144's recorded ordinals (P15: agents 0/1 = the two R9700s, 2 = the APU) as WORKING EVIDENCE
  cited as RECEIPT-PENDING — not host-proven; prose and tests phrase it that way.
- 2026-11-22 owner-ruling D23 (**pre-existing reds re-pin to the RADIANCE literal**): consequence of
  D16 — provider-loops t1/t3 + agents-md c11 (today pinning the stale `27b-q4` runner string) clear
  to radiance in C02, with the ruling-chain comment (cf-106 OQ-14 → 2026-11-09 strata-q4 →
  2026-11-22 radiance) carried in each leg's message; never carried silently.
- 2026-11-22 coord-disclosed defaults D24 (**NOT ASKED, ADOPTED AS RECOMMENDED — owner may still
  change at Final Review**): OQ-D chart = mechanism-only shell (D7 stands); OQ-F flash-TP1 profile =
  transcribed cf-143 TP1-era array (source commit `git show e7536b2c9^:charts/radiance/values.yaml`,
  verified) + memory 110 held + claim 1 + replicas 0 (D10 stands); OQ-G 27b-TP2 profile = q27 array
  + `--tp 2 --tp-wire wht6`, 24Gi held, claim 2, replicas 0 (D10 stands). These are the
  coordinator's disclosed defaults folded from the plan's recommendations, not owner verdicts.
- 2026-11-22 rework D25 (**wave/depends reconciliation after (b)**): C04's claim now rides
  `services/gpu-ai/prod/values.yaml` (llama-swap overlay block) — the SAME FILE C05 edits (radiance
  blocks/peers/roster). C05's depends_on gains **C04** (both plans' tables previously read
  [C01,C02,C03]; STATE's C02 row also mis-stated wave 2/deps [C01] against the plan table's wave
  1/[] — folded to the plan table: C02 wave 1). Waves unchanged: 1 {C01,C02} → 2 {C03,C04} → 3
  {C05} → 4 {C06}; same-file safety is served by wave ordering plus the added depends edge.
- 2026-11-22 owner-ruling D26 (**OQ-K: K1 — strata parks at `replicas: 0`**, confirmation round):
  D17's conflict resolved by parking, not by moving fn. C04's STOP condition is therefore DISARMED —
  it executes as specced. Live grounding verified post-fold: `Deployment/gpu-ai-llama-swap-strata` is
  ALREADY `0/0` on ai-gpu (EXPLORE §1 live table), and no `replicas` override exists in
  `charts/llama-swap/values.yaml` or the strata blocks of `services/gpu-ai/prod/values.yaml` (the
  controller renders app-template's default 1) — so git-desired-1 vs live-0 IS the pre-existing
  `OutOfSync/Healthy` delta on `gpu-ai-llama-swap` (EXPLORE gotcha 17). K1 thus makes git match the
  running reality and NETS OUT that drift instead of resuming it; a sync that left strata at 1 would
  have produced a permanently-Pending pod (`Insufficient amd.com/gpu-r9700`). Provider stays
  registered (MoE route answers loud 502 while parked, same law as the resting radiance lanes);
  MoE bring-up is the owner's scale act (fn→0 first) per the C06 runbook. Rejected alternatives
  recorded: K2 (keep 1, accept Pending) and K3 (park fn — contradicts D16/D18's approved fn-live
  default lane) and K4 (revert to (a) — would un-rule D17).
- 2026-11-22 owner-ruling D27 (**model routing re-confirmed for the EXECUTION half of the ticket**):
  "use the radiance flash going forward" — every subagent launch of this ticket (test, dev, review,
  final review) passes `gpu-ai/qwen3.8-flash-next-radiance` explicitly. Not a plan change: it matches
  D16/D4's already-ruled-everything-tiers-radiance posture; the moment of the word was the owner's own
  catalog edit (the 6 radiance `limit.context` rows, isolated at `b3d7fada8`), which is why the first
  test launch was cancelled mid-flight. Verified the id is live: `.opencode/opencode.jsonc:716`
  (class rows `-urgent :723`, `-low :730`). Catalog bytes are the owner's — this ticket's C02/C05
  routing legs touch skills/rules/loop surfaces and the catalog rows for the NEW lanes only, never
  those six context values.
- 2026-11-22 coord-ruling D28 (**C05 priority ladder: reject the negative rungs; cross-peer tie accepted**),
  made on the test wave's D-3 escalation. The test author had resolved the fn-low-1 vs 27b-TP2-low-1
  collision by dropping the parked lanes' low rows to `-1/-2`. Rejected on evidence: the catalog ships only
  NON-NEGATIVE `body.priority` (`git grep '"priority"' .opencode/opencode.jsonc` → six live rows, 0..9), and
  cf-143 already records `priority-0` SEMANTICS AS UNVERIFIED with the CI smoke read as the receipt
  (`charts/llama-swap/tests/evidence/radiance-q27-peers-expected.yaml:28`,
  `charts/radiance/tests/radiance_testlib.py:317`) — a first-ever negative value is a strictly bigger
  unknown than a zero. SHIPPED SHAPE: fn 9/5/1, q27 8/4/0, flash-TP1 7/3/2, 27b-TP2 6/2/1, with each peer's
  `setParams "priority?"` floor == that lane's OWN base row (floors **3** and **2** — the test author's D-2
  law, which IS the per-lane coherence law cf-143 established, and it survives this ruling unchanged).
  fn-low-1 == 27b-TP2-low-1 is recorded as an ACCEPTED CROSS-PEER TIE, not a collision: the two lanes are
  separate peers with separate floors and no M8 leg demands class-column uniqueness across the family.
  Rejected alternative (the negatives) is named in TEST_SPEC so Final Review sees the trade, and the
  smoke-read leg stays the receipt for the numbers actually shipped.
- 2026-11-22 coord-ruling D29 (**blank `Model(s)` default path, closing the test wave's open question 1**):
  a card with NO `Model(s)` item checked routes as today's defaults with the radiance move applied to the
  FLASH size only — blank → `Qwen Flash + Local` → `gpu-ai/qwen3.8-flash-next-radiance`; blank + `10+`
  (≥100k) → `gpu-ai/qwen3.8-27b-q4` through the outer swap, which NEVER moved (`surface.sh`'s kept
  `:750-751` requirement is exactly this row). Chosen over moving the big-context default to radiance
  because that would put it on the PARKED q27 lane: a second silent failure on the same surface, after D16
  already concentrated every other tier on the single live fn lane. Recorded in
  `tests/pipeline-models/TEST_SPEC.md` §4 so dev and review read one law instead of a gap.
- 2026-11-22 coord-ruling D30 (**test-file edits are never assignable to a dev tier** — from C01's NI-1/NI-2).
  Dev permissions deny `tests/**` by design, so any chunk instruction of the form "dev flips this constant in
  the testlib" is unsatisfiable and silently transfers work that belongs to the test wave. Binding for
  C02-C06: every needle home (bash AND python AND `TEST_SPEC` prose) is pre-flipped by the test session; dev
  changes only implementation, values, notes and generated surfaces; a leg dev believes is wrong is escalated
  as NEEDS_INFO and repaired by the test session, never by dev, review or me. Corollary proven this round: the
  python twin at `amd_gpu_testlib.py:46` and the spec heading at `TEST_SPEC.md:4556` had to move in the SAME
  test-session turn as the bash twins, because n3's zero-stale sweep scans `tests/` too.
- 2026-11-22 coord-ruling D31 (**gate-integrity rule for early-green legs**): a leg that turns green on an
  incidental token is a BROKEN gate, not progress. `test_c04_supersession_annotation_on_the_2026_10_27_ruling`
  went green on dev's `renamed 2026-11-22` date comment rather than on C04's substance; it is re-anchored to
  the real claim + same-wave `replicas: 0` and must stay a designed red until C04 lands. Reviewers may not
  credit a chunk for a leg that was already green when the chunk started — the per-chunk designed-red
  inventory in STATE is the baseline, not the count at review time.
- 2026-11-22 coord-ruling D32 (**C01 APPROVED at `b577e32fe`, and its orphan prose assigned**): C01's review
  came back APPROVED with no blockers/majors and surfaced a governance hole my own record had created —
  FRICTION says `charts/amd-gpu/values.yaml:30` ("one device each on the ai-gpu node") is C06's, but **no
  chunk file carries that task** (`grep "one device each" chunks/*.md` → 0 hits), so a statement that is
  false post-TP2 would survive the ticket by nobody's decision. FRICTION ownership is not a work item:
  **C06's scope is amended** to (i) the `:30` header correction, (ii) the citation-prefix pass from Minor 1,
  and (iii) optional restore of the `32 GB dGPU` ledger tag the review judged non-required. Recorded in the
  ruling channel precisely because executable scope belongs to a chunk file, not a friction row.
- 2026-11-22 coord-ruling D33 (**review-grade evidence rules from C01's review, binding later rounds**):
  (a) `amd-gpu-naming.sh` **n2 is a file-set guard, not a content guard** (`wave_a()` greps only
  `git show --stat` for three paths), so rename-wave atomicity must be audited CONTENT-side by the reviewer —
  a green n2 alone never proves the claims moved. (b) A raw `grep -rn` for the retired literal shows
  gitignored `__pycache__/*.pyc` in any worktree that has run pytest (CPython constant-folds the assembled
  name); the needles exclude it, a human must add `--binary-files=without-match`. (c) A reviewer must not be
  handed an expected-status list that includes the write arm (`surface.sh` M6) — repo law bars read-only
  sessions from it, so my C01 brief was wrong to list M6 as expected-green and the reviewer correctly claimed
  nothing. Later briefs record M6 as "not run, no claim".
- 2026-11-22 owner-ruling D35 (**C03 fork RESOLVED: the CHART owns the generic init script; byte-equivalence is
  RELAXED for that one carrier**). PATH ANNOTATION (correction, not a change of ruling): the four budget paths
  are stated in the suite's Deployment-rooted grammar as
  `$.spec.template.metadata.annotations["checksum/configMaps"]`, `$.spec.template.spec.volumes`,
  `$.spec.template.spec.initContainers[0].command`. My original shorthand "`spec.volumes`" meant the POD-SPEC
  volumes; a Deployment has no `spec.volumes`, so the
  test needle written from my shorthand named a nonexistent path and made both arms of the delta leg fail for
  ANY carrier. The ruling's intent is unchanged; the exact path is now recorded so no later round re-derives it
  from the shorthand. Asked with the mechanism verified (app-template 5.0.1 renders `command`/
  `args` via plain `toYaml`, no `tpl`; only configMap data and env are tpl'd), the owner chose the parameterized
  shape over keeping the pre-move fixtures green, accepting that the LIVE fn lane's pod spec changes. Binding
  consequences, recorded as rulings not notes: (1) **AC1 is replaced, never deleted** — the equivalence legs
  become an INTENTIONAL-DELTA proof: exactly four paths may change
  (`metadata.annotations."checksum/configMaps"`, `spec.volumes`, the init container's `volumes`+`volumeMounts`,
  its `command`) and NOTHING ELSE (serve args, claim pair, memory, replicas, probes, securityContext,
  image@digest all byte-equal); a leg asserting only "the script is in the chart" would admit unrelated drift,
  so the diff-budget IS the new gate. (2) **The fn lane rolls** — `restartPolicy: Recreate` + changed template
  means the default route for every tier (D16) restarts at the owner's sync of `gpu-ai-radiance`, a 502 window
  of ~grace 180s + model load; so C03's rework lands as its OWN watched sync set, never bundled with the rename
  or fleet wave, with the cf-143 D28(6) first-boot print as receipt. (3) **Per-lane scalars survive as DATA**
  (`PACK`/`LFS_SHA`/`URL`/`MARKER` in each block) and the chart ships the script FORM, which makes the plan's
  "parameterized init" supersession row true as written. (4) **Cross-lane drift guard stays**: fn and q27 scalar
  sets asserted independently, so a chart-side script edit cannot silently re-point one lane at the other's pack.
  Order: `agent-plan` folds the plan + `chunks/C03.md` (my tier edits neither) → test wave re-aims the
  equivalence legs to the diff-budget shape → C03 dev round 2 → C03 review.
- 2026-11-22 coord-ruling D38 (**C03 APPROVED at `b8c01489e`; two of its minors become named work**). C03's
  review wrote its OWN independent differ rather than trusting the suite's, and confirmed: exactly four delta
  paths on both lanes, zero unauthorized; script semantics equal (OLD-only statements: NONE; NEW-only: the
  `-z` empty-scalar guard); all six behavioural arms proven under `dash`; fixture baseline re-validated, not
  laundered; ledger drift caught doubly; and the fetch/serve coupling asserted at every hop
  (`FORM PACK = modelPath`, `modelPath == rendered --model` per lane, rendered `PACK=` literal == lane
  modelPath) — so no lane can fetch one pack and serve another. It also corrected MY overstatement: the
  empty-scalar guard is behaviourally proven but **no leg asserts the guard token exists**. Work now named:
  (1) TEST wave — append a guard-token assertion to
  `test_c03_chart_ships_the_script_form` (`charts/radiance/tests/test_c03_generic_shell.py:253-274`) so a future
  FORM edit cannot silently drop the guard; dispatched immediately, before C05.
  (2) C06 wave — annotate three stale law sites in `services/gpu-ai/prod/values.yaml` falsified by C01/D35:
  `:1103-1108` ("Decorative ledger ONLY … moves NOTHING that renders" — the FORM renders from it now, and it
  contradicts the `radianceFetch` comment 9 lines below), and the claim-count prose at `:1098-1100` +
  `:1213-1222` ("the chart pair moved to 2", "OVERLAY-PINS", "inheritance would render the chart's 2" — the
  chart has shipped no claim since C01). Use the `:1056` annotate idiom. CI cannot catch these (its
  pair-form regexes miss the 6-space-quoted block), which is precisely why prose needs a named owner.
  Recorded here because `chunks/*.md` are not editable by my tier (D30-adjacent) — C06's launch brief carries
  both items verbatim.
- 2026-11-22 coord-ruling D39 (**my C02-review noop re-baseline was WRONG; the scout-era 8/9 stands**). The
  test session swept every committed revision of both scripts: `cf106-noop/surface.sh` has only ever carried
  7 or 8 `ok` calls, `noop-marker/surface.sh` only 5/5/5/6/9/9. Eleven exists in no revision, and invocation
  mode cannot inflate the count because arms are `want`-gated one-`ok`-each, so a full-suite run is already
  the maximum. Authoritative baseline for all later rounds: **8 ok / 9 ok, both rc 0, full-suite invocation**;
  per-arm runs legitimately print fewer. I retract the "scout baseline was stale" claim I folded into the plan
  at `:152-153` (planner fold owed — my tier cannot edit the plan of record). Standing lesson, written where I
  will meet it again: **one review measurement is not a baseline** — before overwriting a recorded expectation,
  reproduce it or read the source of truth (here, `grep -c '^\s*ok '` across revisions). I did neither, and
  "corrected" a number that was right.
- 2026-11-22 coord-ruling D40 (**D36 is OVERTURNED on consequences: `.aislop/history.jsonl` churn causes FALSE
  gate reds; interim posture = revert before gate runs**). C04 found `gate t14`, `rulesync-surface c8` and
  `provider-loops t6` (which wraps the gate suite) all red on a correct tree, and the test session proved sole
  causation: with only that file dirty, t14 and c8 rc=1 naming it verbatim; after `git checkout --
  .aislop/history.jsonl`, **t14 rc=0, c8 rc=0, t6 rc=0**. Mechanism: t14 and c8 are SCOPE guards — every
  changed/untracked path must sit in the ticket's admitted Files list — so a tracked file that every scan
  dirties is structurally guaranteed to trip them. My D36 posture ("leave it dirty, it is machine churn") is
  therefore NOT neutral: it makes three gates lie on every round, including the hourly loop. Interim rule for
  all remaining rounds and briefs: revert the file before any scope-guard leg. Permanent fix is a
  human-owned hygiene call and I have not made it: `git rm --cached .aislop/history.jsonl` + a `.gitignore`
  line (it is machine-local score-trend telemetry, cf. `aislop trend`; exactly one commit ever touched it and
  `.gitignore` does not mention it). The alternatives are worse — committing the append is a treadmill,
  `skip-worktree` is invisible to other clones and breaks on fresh worktrees.
- 2026-11-22 coord-ruling D41 (**the 110Gi question I raised is CLOSED — and closed AGAINST me**). I flagged
  strata's `requests.memory: 110Gi` as possibly a test-invented production number and said I'd put it to the
  owner. Evidence resolves it without an owner round: the frozen cf-143 baseline's own `limits.memory` was
  ALREADY `110Gi` (requests were `64Gi`), so C04 mirrored requests TO the pre-existing ceiling and the pod is
  now Guaranteed-QoS (`req == lim == 110Gi`) — which is what a pod booking a whole GPU should be; the value
  traces to `strata_testlib.py:431` / cf-143 D26 chart truth, NOT to `test_c04_strata_claim.py:100` (which
  asserts the named constant rather than authoring a number); and fn(110)+strata(110) > 125.08 GiB node RAM
  enforces the never-co-exist law a SECOND time below the GPU claim's 1+2>2, matching the plan's own pattern
  for lanes that "fit the pool but NOT RAM … stated, not a defect". The only lawful bring-up still fits:
  strata 110 + the always-on main pod's 4.125Gi ≈ 114.1 < 125.08. The number's home is cf-143, not this
  ticket. Recorded because my instinct to escalate was right as a reflex and wrong on the facts — asking for
  evidence before escalating is what distinguished the two.
- 2026-11-22 owner-ruling D42 (**churn false reds are ACCEPTED and DOCUMENTED — supersedes D40's
  revert-before-gate posture**). Asked with the three options and their costs, the owner chose to leave
  `.aislop/history.jsonl` exactly as it is: tracked, dirtied by every scan, never staged. Consequence that is
  now policy rather than drift: `gate t14`, `rulesync-surface c8` and `provider-loops t6` (which wraps the gate
  suite) will show **red with the file named verbatim** whenever the tree carries the churn, and that reading is
  CORRECT — a scope guard doing its job on a known-dirty path. Every review and dev brief from here states the
  three leg names as "expected red iff `.aislop/history.jsonl` is dirty; confirm the FAIL line names ONLY that
  file and move on", so no round burns time reverting, re-running or re-litigating it. Two rules I keep from
  D40 because they are what made this provable and stay true under D42: (a) the file is NEVER staged into a work
  commit (D36 stands on that half), and (b) when one of these three legs is red, the first question is whether
  the FAIL names only the churn file — if it names anything else, that IS a finding. The distinction D42 draws
  is that a documented known-red is cheaper than a per-session ritual that races the next scan.
- 2026-11-22 coord-ruling D36 (**`.aislop/history.jsonl` per-run appends are machine churn — never staged into
  work commits**). Evidence: the file has exactly ONE commit in history (`6230e1297`, its cf-6-era
  introduction); every gate run since has left it dirty and no wave commit has ever staged it. So it is tracked
  as an artifact but its appends are not work product: leaving it dirty out of ticket commits is correct, and
  promoting a line into a feature commit would attribute CLI bookkeeping to a chunk. Turning it into an ignore
  rule is a human hygiene call, not a mid-ticket edit.
- 2026-11-22 coord-ruling D37 (**commit scope: a directory path spec silently bundles its tests**). My C03
  round-2 commit used `git add charts/radiance services/gpu-ai`, which swallowed
  `charts/radiance/tests/test_c03_generic_shell.py` too — so the impl and its two test repairs landed in ONE
  commit (`b8c01489e`) instead of two. Rather than split a coherent, unpushed change, I amended the message to
  disclose the bundling and describe the test repairs in full. Rule going forward: stage implementation paths
  and `tests/` paths as SEPARATE `git add` arguments when a chunk carries both, and check `git show --stat`
  before describing a commit as impl-only.

## Deferred
- DRA lane (triggers in D11) — recorded, no action.
- fn memory DOWN re-pin (cf-144 P11's owner leg) and the §12 co-existence re-open it unlocks.
- ~~`-urgent`/`-low` siblings for resting lanes~~ WITHDRAWN by D19 (full trios ship in C05).
  Strata on-target [VERIFY] posture (cf-144 P17, owner leg); Grafana per-lane dashboards
  (cf-143 card #2); gpu-cluster naming (cf-144 C04 card).
- MoE bring-up runbook (fn→0 then strata→1 scale act) — prose ships in C06 (roster note); the
  scale acts themselves are owner legs forever.
- Upstream feature ask (per-card selection in the plugin — cf-143 §R7's RECOMMENDED ask) stays
  unfiled, owner's call.
