# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|coord|human), decision, alternatives
rejected, why.

## Conventions
- Parent law this ticket inherits unchanged: cf-143 D27 (`.opencode/opencode.jsonc` bytes are the
  owner's — rows are owner-landed even when authorized); context-window D6 (seqs FORM-fixed),
  D7/D10 (held 110Gi/24Gi move only on a boot print), D16 (gate limits: M is self-reported, N% is
  owner-read, absence is never a pass), D8/D49 (one receipt artifact, gate+block together);
  multi-instance D35/D43/D45/D46 (FORM-vs-DATA, serve wrapper, per-lane peer floors).
- ArgoCD-only (never kubectl apply); never advance/push `main`; no hand-bumped chart versions;
  no commits by the plan session.
- Every plan artifact refers to the base as "branch HEAD, verify `git rev-parse HEAD`" — NO sha
  literals (one was orphaned by an amend on 2026-11-23 after recording).
- Kickoff models: **inherited session default** — an earlier launch naming a specific openrouter
  model was registry-rejected and dropped; no artifact invents a model id.

## Decisions
- 2026-11-23 plan **D-1 (folder name "yarn" is HISTORICAL — recorded so no later agent reads it
  as scope)**: fractional YaRN (1.5× context) was considered in the grounding round (RESEARCH G1:
  parse-legal-by-wording at v1.17.0 but validated ONLY at factor 2, worst-position edge at 1.5,
  and 1.5× × 8 seqs multiplies the pool worst case past what any dtype gains — §2.2/§2.8) and the
  owner withdrew it at the batched round (ruling R1: no rope scaling, served context stays native
  262,144). The folder `2026-11-feat-radiance-fp8v4-yarn` is NOT renamed (plan file and
  RESEARCH.md stay adjacent per AGENTS.md); the plan of record is
  `2026-11-23-feat-radiance-fp8v4-lane.md`. Rejected alternative: a new folder — splits the
  research from its plan, violates one-plan-per-work.
- 2026-11-23 plan **D-2 (naming — RFC1123 resolved deliberately)**: underscores are illegal in
  Kubernetes object names, the owner wrote `-fp8_v4`. Decision: identifiers use compact
  **`fp8v4`** — lane key `radiance-q27-fp8v4` (Application/Service `gpu-ai-radiance-q27-fp8v4`,
  peers key identical), served id / catalog base `qwen3.8-27b-radiance-fp8v4` (matches the
  `-tp1`/`-tp2` suffix precedent); the literal **`fp8_v4` appears ONLY as the engine dtype value**
  (env value, composed argv, boot echo) and in prose. Rejected: (a) `radiance-fp8-v4` — drops the
  q27 lineage the release belongs to and collides in style with the `-tpN` suffixes; (b) keeping
  `fp8_v4` in ids (the research's `qwen3.8-27b-radiance-fp8_v4` sketch) — legal in env strings but
  creates THREE spellings (release/row/value) that every mapping leg must name, and
  `surface.sh:1632`'s host derivation underscore-replaces; a pod-name rejection at apply time is
  the surprise-class this resolves. Confirmation is OQ-4 (cheap pre-boot, annoying after).
- 2026-11-23 plan **D-3 (dtype becomes DATA through ONE env channel with a suite-pinned
  fallback)**: `RADIANCE_KV_CACHE_DTYPE` (flag-mirroring name per the ENV_TO_FLAG convention —
  chosen over the brief's `RADIANCE_KV_DTYPE` example) leaves `FORM_FIXED_FLAGS` and joins a new
  testlib class `ENV_DEFAULTED` with default `fp8`; the FORM composes
  `--kv-cache-dtype "${RADIANCE_KV_CACHE_DTYPE:-fp8}"` ON THE FIXED SPINE LINE (same slot order)
  so the four existing lanes' composed argv is BYTE-IDENTICAL and their blocks stay byte-untouched.
  Rejected: "absent env ⇒ absent flag" (the ENV_OPTIONAL idiom) — the engine default is bf16,
  silently 2× the bytes on any parked lane (RESEARCH §3.3/§8.3); rejected: routing dtype through
  any request-body/`--extra_body`-style channel — see D-8; rejected: four per-block args — dead
  carrier class (D43). The byte-equivalence is an AC, not an assertion (C02 AC1).
- 2026-11-23 plan **D-4 (the lane is TP2, not TP1)**: design choice with consequences. TP2 (claim
  "2", q27-TP2 geometry, replicas 0): this is the ONLY shape where the dtype story means anything —
  the funding figures are the TP2 dense geometry (RESEARCH §2/§5); TP1 funds M ≈ 1.9 even at
  fp8_v4 (§2.4) — a big-single-window pod, not the concurrency pod asked for. Consequences encoded:
  the lane co-boots with NOTHING (any second claimant = Pending — the exclusivity table lands in
  C04's roster note so no future agent schedules two TP2 lanes and waits); `replicas: 0` resting,
  owner scale act flips; pack-shared with its q27 siblings (marker skip, no second 18 GiB fetch);
  belongs in the EXISTING machine-tied roster note (a second note = drift class, RESEARCH §5).
- 2026-11-23 plan **D-5 (dtype attribution CORRECTED; the build still follows the ruling)**:
  the framing shown to the owner ("fp8_v4 alone funds 7.66 of 8 at native 262,144") mixed the rows —
  RESEARCH §2.2: at 262,144 × 8 seqs, q27-TP2 geometry, 22.15 GiB/card context pool (from the
  MEASURED 22.24 = 20.98 kv_attn + 1.16 state + 0.09 kv_draft decomposition, kv_draft stays fp8 —
  the 0.09 term does NOT shrink, [E27]/§2.0): **fp8_v4 funds M 6.77 at 84.7% backing (unfunded at
  8 by 1.2)**; **k6_v4 funds M 7.65 at 95.7%**; fp8 today M 5.34 at 66.8%. The 7.65 figure is
  k6_v4's row (§7 Option A). The fp8_v4 choice STANDS as ruled (it is still +26% funded sessions
  fp8_v4 (it is still +26% funded sessions
  over today's 5.34 on identical everything-else); the correction is OQ-1 so the owner can re-rule
  before test authoring — silently building k6_v4 instead is the same class of error in reverse.
  **[RESOLVED 2026-11-23 owner scope-change round R1: the corrected matrix WAS surfaced (see D-15)
  and the owner kept `fp8_v4` informed. OQ-1 retires as answered; this entry stands as the
  correction-of-record so nobody later claims the choice was made blind.]**
- 2026-11-23 plan **D-6 (the lane is a capacity/pool change with NEUTRAL speed — prose law)**: the
  "+12% long-prompt prefill" was a misattribution (RESEARCH TL;DR-3, §3.2, §9 C1): the pin's dtype
  table shows 9.76/9.76/9.84 s at 41k across fp8/fp8_v4/k6_v4 — dtype alone buys ZERO speed; the
  gain belongs to `--attn-prefill-fp8 both` (lossy; worst movers are tool-calling transcripts —
  this route's actual workload) which is OUT OF SCOPE (not stacked, not this ticket's
  enthusiasm — §8.1). Every artifact (block comment, evidence YAML, catalog-row commentary, roster
  note) must describe the lane as pool/concurrency capacity (+28% pool tokens, 16 → 12.5
  KiB/token/card) with speed-neutral expectation and its creator-rig attribution caveat (§0 — our
  rig has only the fp8 baseline print; first boot prices everything).
- 2026-11-23 plan **D-7 (scope reduction VERIFIED, not adopted)**: under ruling R2 (seqs stays 8
  everywhere) the receipt gate's single-distinct-`--max-num-seqs` leg needs NO rewrite —
  `receipt_gate.py:262-280` reads the chart file's `--max-num-seqs (\d+)` matches and refuses only
  on >1 distinct value; verified this session: exactly one occurrence in `charts/radiance/values.yaml`
  (line 227), and the post-change FORM keeps the single literal (dtype moves, seqs does not). The
  two proof legs (`test_receipt_gate.py:228-247`) stay green untouched — C01 AC3 machine-proves
  it. Guardrail recorded: no `charts/radiance/values.yaml` comment may add a second
  `--max-num-seqs <digit>` match (the regex scans comment text too).
  **[SUPERSEDED 2026-11-23 by D-16 — owner scope change: seqs becomes PER-LANE (5/5/5/5/8); the
  gate leg DOES need the structural re-cut. The verification above stands as history: on the
  ORIGINAL uniform-8 ruling the reduction was real; it died with the ruling, not with the read.]**
- 2026-11-23 plan **D-8 (the "no `--extra_body`" law, named as it actually exists)**: repo-wide
  grep finds NO literal `extra_body` rule — the governing law the brief meant is **D43**: the
  engine's argv is composed ONLY by the chart FORM from `RADIANCE_*` env
  (`charts/radiance/values.yaml:182-195`; multi-instance `DECISIONS.md:399-422`), enforced by the
  single-source/dual-channel legs (`radiance_testlib.py:967/:985-997/:1186-1200`,
  `test_c03_generic_shell.py:266-301/:326-348`); the only per-request body seam on the peers side
  is `filters.setParams "priority?"` (services values :741/:780/:813/:823). A per-request dtype
  would be a second argv source AND a boot-time decision made per-request (the pool is built at
  startup — dtype is not a request knob). Cite D43; dev must not re-derive it. Recorded honestly:
  the brief's law name does not exist verbatim; this is its real home.
- 2026-11-23 plan **D-9 (catalog row shape — the 4096 page-size trap made impossible)**: verified
  census this session — the twelve existing radiance rows (`opencode.jsonc:727-879`) carry EXACTLY
  the five keys `modelID / name / capabilities{input[text,image],output[text],tools true} /
  limit.context 262144 / body.priority`; NO pages/pagesize-form field exists anywhere. The trap
  (prior dtype incident, cf-131 STATE.json:90 chain — the drafter's `1696×4096` bf16 page became
  the model MAX page and strided-padded every group: page-BYTE figures masquerading as capacity):
  the new trio rows must repeat the SAFE SHAPE verbatim — token-count `limit.context 262144`
  unchanged at the family figure (M9-A2 equality: trained == served == 262144, legal per D4
  restatement), no page-shaped number (`4096` and friends) in any row field, engine page figures
  (`page 256.00 → ~200.00 KiB per 16-token block`) live ONLY in boot-print expectations/tests,
  never in the catalog. Commentary for the new rows must name both D47 figures (262,144 /
  200000-stale-needle) per M9-A2's prose half.
- 2026-11-23 plan **D-10 (fifth trio 5/1/0, floor 1 — best guess pending OQ-2; existing lanes
  never re-rank)**: RESEARCH §6.1 proved there is NO collision-free fifth trio under the M9-A2
  laws (urgent column {9,8,7,6} taken → ≤5; default column {5,4,3,2} taken, must be below 2 → 1
  or 0, 0 forces a negative low; low 0 ties q27's 0). Plan default: urgent 5 / default 1 / low 0
  with a SECOND NAMED entry in `ACCEPTED_LOW_TIES` (`surface.sh:1499`) — the per-lane-queue
  justification ("four engines, four queues") extends to five. The tie is the owner's ruling
  (OQ-2); the legs stay designed-red until it lands. Existing twelve rows/quarters byte-untouched.
- 2026-11-23 plan **D-11 (never a default route; hardware items stay separate)**: no runner-literal,
  class-table, favorited-table or pipeline-models-prose moves for this lane (M9-F not extended);
  the lane's peers hop answers 502-loud while parked. The ReBAR receipt (`lspci -vv -d 1002:7551 |
  grep "Region 0"` → `size=32G` per card; cf-143 records ReBAR PROVEN-DONE, P2P observed working
  boot-to-boot on both TP2 pods) is owner COLLECTION ONLY — not BIOS-change authorization — and
  the rank-1 Gen3×4 link-width defect (boot WARN, 8.0 vs 16.0 GT/s on 0000:c7:00.0) is slot/link
  training, a DIFFERENT knob with its own owner lane; the roster note gives them separate named
  items so no agent conflates them (ruling R4).
- 2026-11-23 plan **D-12 (catalog timing + landing discipline)**: `limit.context` (and the rows
  whole) follow the lane's boot receipts, never precede them (RESEARCH §6.4 — the D19 lesson);
  standing risk stated: this lane is a serving route for the pipeline itself (fn is every tier +
  the runner; a TP2 bring-up interrupts that route), so every scale act and the merge itself are
  owner-gated. The five-lane D8 block supersedes the owed four-lane block as ONE artifact (R2/D8
  law — lane-count changes land in block+gate together).
- 2026-11-23 plan **D-13 (chunking)**: four chunks, one subsystem each, test authority FIRST
  (C01 red-first covers radiance tests + receipt gate + M-series + roster legs + evidence YAML);
  C02 chart FORM; C03 service wave (roster+block+peers+CI+golden in ONE commit — the parity legs
  cross-pin them); C04 roster-note docs. Dependency reasons are per-chunk files. Rejected: a
  dtype+seqs+rope "one FORM wave with three env channels" (RESEARCH implications) — rulings R1/R2
  deleted two of the three channels, so the wave collapses to dtype-only; rejected: separate
  catalog-rows chunk — the rows are owner-landed bytes (D27), not a dev chunk.
- 2026-11-23 plan **D-14 (receipt LAW adopted family-wide — bound by the sibling coord round that
  landed during this plan's authoring)**: context-window's FRICTION now records a
  near-miss FABRICATED RECEIPT (a drafted `merge_receipt_2026_11_23` asserting legs passed at ~97%
  never landed; its number traced to RESEARCH.md:292 — a DERIVED **k6_v4** prediction, not a
  print — corroborating this folder's V-3/D-5 correction independently). Binding rule for every
  later round on this family, cited verbatim from that file: **a receipt/observation record may
  cite ONLY (i) output pasted by the owner in-session, or (ii) a boot print captured from Loki
  with its pod, timestamp and raw line quoted — never a derived matrix figure, never a prediction
  phrased as "prints N", never a number whose dtype/lane conditions differ; any STATE.json record
  of a run must be verified ON DISK before it is cited.** Consequences here: every "≈85% / M ≈
  6.8 / page ~200 KiB" figure in this plan and its chunks is labeled a DERIVED PREDICTION that the
  lane's first boot prices (it already is — V-3/D-5/D-6, R-7); the Landing steps 3–4 receipts are
  owner-executed artifacts recorded under this law; the owed four-lane D8 block stays "NO RECEIPT
  IS ON RECORD — PROVISIONAL open on all four lanes" (the sibling's own status wording — not
  "never run" as fact), and the unified five-lane block (OQ-5) closes it. Also carried: branch-
  local record commits self-stale — re-derive with `git branch -a --contains` at the current tip,
  never `git rev-parse @{u}`, and never cite a commit from memory (the sibling's `test_c03_chart_
  canary.py`/`REQUIRED` misrememberings are why this plan's file:line inventory was re-read from
  the tree this session).

- 2026-11-23 owner-ruling (scope-change round) **D-15 (R1 — `fp8_v4` CONFIRMED INFORMED; k6_v4
  stays out; the choice may never be recorded as uninformed)**: the coordinator surfaced the
  corrected matrix to the owner BEFORE this ruling — RESEARCH.md:284-295 (at 262,144 × 8 seqs:
  **fp8_v4 = 84.7% backing / M 6.77**, k6_v4 = 95.7% / M 7.65, today's fp8 = 66.8% / 5.34) and
  §3.2 (**k6_v4 DOMINATES fp8_v4 on every measured column of the pin docs' table: +46% vs +28%
  pool, KL 0.039965 vs 0.040076, top-1 94.06 vs 94.03, equal speed**) — **the owner read that and
  kept `fp8_v4`**. Recorded deliberately: a later agent may NOT claim the choice was uninformed,
  and no wave may "helpfully" swap k6_v4 in. Discipline that survives from the VERIFY round:
  (a) this lane's funding figure is **6.77 / 84.7% at 262,144 × 8** — **7.65/95.7% belongs to
  k6_v4 and must not appear anywhere in this ticket's success criteria**; (b) both are DERIVED
  predictions (creator-rig ratios × our measured pool) — no AC reads a prediction as a pass; the
  lane's first boot print (owner-executed) is the only evidence; (c) **upgrade consequence:
  `fp8_v4`/`k6_v4` are REFUSED at `main`/2.x** (RESEARCH §0/[G@m], §8.6) — shipping this lane
  **pins the deployment to the 1.17.0 line**. That is a risk-register entry (R-9) and a
  DECISIONS note, NOT a reason to reconsider. Supersedes OQ-1 (retired as answered); amends D-5.
- 2026-11-23 owner-ruling (scope-change round) **D-16 (R2 — `--max-num-seqs` becomes PER-LANE:
  5 on the existing four lanes, 8 on the new `fp8_v4` lane; the D-7 scope reduction is VOID and
  the receipt gate MUST be re-cut)**: the owner's original ask, re-confirmed with the cost known
  (§2.3: fn's MEASURED M ≈ 4.1 still refutes against a 5 bar; §4.2's engine-number effects).
  Mechanism mirrors D-3: seqs leaves `FORM_FIXED_FLAGS` (radiance_testlib.py:970-975) into the
  `ENV_DEFAULTED` class — `RADIANCE_MAX_NUM_SEQS`, **FORM fallback 8** (the ENGINE default is 256
  — absent-means-absent would size the worst case at 256×context and re-write admission math
  wholesale, RESEARCH §4.1 [G@t:2069]; the fallback is mandatory and suite-pinned). The four
  existing lane blocks author env `"5"` (the ONE intended delta per lane); the new lane authors
  NOTHING (8 = fallback; profile carries 8). Rejected: separate FORMs or block args for seqs
  (D43 class); rejected: fallback 5 (would silently move the new lane — the fallback preserves
  TODAY, the env carries the RULING). The testlib :90-97 comment (seqs "FORM-fixed … the lane may
  not size it at all") goes STALE — annotate dated, never rewrite (the ticket's own law). The
  blast-radius inventory used is **RESEARCH §4.2 (:443-468)** with the plan-session
  re-verification folded in (plan V-2/V-6): receipt_gate.py :253/:262-280 single-distinct refusal now
  fires BY DESIGN and must be re-cut to per-lane bars (chart fallback + the lane's block env)
  with test_receipt_gate.py :228-247 re-pinned FIRST (parent-D30); :80 item-3 wording + :410 PASS
  banner per-lane; `FN_LANE`/`SMOKE_SESSIONS` :63/:71 — the eight-admitted-sessions smoke becomes
  a FIVE-admitted smoke (§4.2; supersedes context-window D9(b)'s count for fn — recorded, not
  silently). `tests/notes/radiance-runbook.sh:278` needle re-pin + its doc half
  (`radiance-on-target-acceptance.md` :524 ledger / :641-642 eight-admitted / :781
  `--max-queued-requests (default 8×max-num-seqs = 64 queued)` → 40) assigned **both by name in
  the fn chunk** — the D12 lesson, never split across chunks. **M-leg churn: NONE from seqs —
  verified personally this session** (grep over tests/pipeline-models/surface.sh: zero functional
  `--max-num-seqs`/smoke needles; M8 pins ctx/priority only, §4.2 holds) — the difference between
  a small and a large test wave, recorded; TEST_SPEC.md :33's "M ≥ 8 bar … eight-admitted" fn-row
  prose gets the dated annotation (D15/D16 idiom). Engine-number effects carried into the design,
  each CLAIMED [G@t] not measured here (RESEARCH §4.2): `--max-queued-requests` default 8×seqs ⇒
  **40 at 5** (was 64) — 429-class admission pressure changes (peers surface 429+Retry-After
  verbatim); `--max-n = max(8, seqs)` **stays 8**; checkpoint-slots auto ⇒ **seqs×10** (5×10 = 50
  slots ≈ 7.49 GiB vs the measured 80×153.38 MiB = 11.98, §2.7 — ~4.5 GiB host slack appears on
  the 27b lanes and is recorded ONLY — D10 stands, no memory value moves pre-print); and the
  **wht6 law ⇒ a 5-row lane crosses the lossy-allreduce threshold LESS often — a small accuracy
  WIN at 5**, stated in the plan rationale so the move is not read as pure loss.
- 2026-11-23 plan **D-17 (fn leg: not oversold; own chunk; order gate; receipt LAW honored)**:
  per RESEARCH §4.3, the fn seqs-5 edit changes admission width 64→40 and drops the D9(a) bar
  8→5, but **fn's M ≈ 4.1 is MEASURED ([EF]: flash print 52%/4.1 at both ceilings) — 4.1 < 5: fn
  STILL REFUTES**. Every fn-facing AC states positively that **"5 fixes funding" is FALSE**; what
  5 buys is an honest bar + wht6 margin + the 40-queued admission shape. fn is the default route
  for every tier + the scheduled runner → **fn's leg is its own chunk (C05) with its own review**,
  carrying §4.3's reviewer-evidence set (a)-(f) verbatim (owed baseline print quoted FIRST,
  composed-argv echo, per-lane M≥5 read, five-admitted smoke, roll window stated, battery green
  with the named re-pins). **Order constraint (§4.1)**: the CURRENT-SHAPE receipt block runs at
  the next owner scale act BEFORE the seqs wave syncs — otherwise no baseline print exists to
  price the change against (and the ticket re-opens the CW D3 merged-unobserved wound). Recorded,
  NOT closed: the parent's C04 is `owner-triggered-not-run` — **no receipt output is on record
  anywhere** (context-window FRICTION 2026-11-23 "NEAR-MISS FABRICATED RECEIPT"); the D-14 receipt
  LAW binds every AC in this plan: **an AC may require a boot print, never a derived prediction,
  and may not assume a receipt happened.**
- 2026-11-23 plan **D-18 (chunk restructure 4→6: waves 1-6, fn solo, doc/test halves named)**:
  C01 test authority (incl. the receipt-gate re-cut + its tests, per-lane profiles 5/5/5/5/8, the
  three-swap flash-TP1 transcription re-pin, M-series, evidence, roster-script legs); C02 chart
  FORM (BOTH channels on the spine line, fallbacks 8/fp8 — composes today's bytes for every
  env-less lane, so landing it moves NO live vector); C03 new-lane service wave (block authors
  dtype env; NO seqs env — fallback 8; roster/peers/CI/golden); C04 existing RESTING-lane seqs
  wave (env "5" × 3 blocks + `radiance-q27-boot.md` doc half — its script half live-compares and
  needs no literal, pair lands HERE); C05 fn seqs wave (env "5" + `radiance-on-target-acceptance.md`
  doc half + `radiance-runbook.sh` test-half needle re-pins TOGETHER — D12's "both by name, never
  split across chunks" read literally; + §4.3 evidence set, roll window, five-admitted smoke;
  **order-gated on D-17's baseline receipts or a dated owner waiver**); C06 roster note + residual
  dated annotations. Rejected: one services mega-chunk (fn's risk class differs from a parked
  lane's); rejected: runbook test-half in C01 (would split the D12 pair); rejected: keeping doc
  halves anywhere their tree-side isn't landing.

## Deferred
- See STATE.json `deferred` (YaRN path, k6_v4-on-this-lane (declined INFORMED, D-15), fn dtype
  (§C6 — the only lever that could fund fn past a 5 bar; separate ruling), 2.x move, hardware
  lanes) — each with its revisit trigger (owner ruling / boot receipts / fresh validation).
  **[AMENDED 2026-11-23 by D-16: "per-lane seqs" MOVED from Deferred to IN-SCOPE by owner ruling
  R2 — an earlier draft of this section listed it as deferred; that line would mis-record the
  ticket, so the amendment is dated here rather than the line erased.]**
