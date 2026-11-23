# PLAN: radiance `-fp8_v4` lane + per-lane seqs (5/5/5/5/8) — fifth release, three catalog rows

feature: 2026/2026-11-feat-radiance-fp8v4-lane (folder: `2026-11-feat-radiance-fp8v4-yarn` — the
"yarn" in the folder name is HISTORICAL, DECISIONS D-1: fractional YaRN was considered and ruled
out; folder not renamed)

> **For agentic workers:** pipeline role contracts from `pipeline-role-test` /
> `pipeline-role-dev-local` / `pipeline-role-review`; read `RESEARCH.md` (same folder) FIRST —
> ground truth. Base = branch HEAD of `feat-radiance-multi-instance` at each chunk start — verify
> with `git rev-parse HEAD`; **never hardcode a sha** (one was orphaned by an amend 2026-11-23).
> This plan was REVISED same-day by the owner scope-change round — DECISIONS D-15/D-16/D-17/D-18
> supersede any sentence you may find quoted elsewhere from the first draft (esp. the voided
> uniform-seqs scope reduction, D-7).

**Goal:** Add a fifth radiance release, lane `radiance-q27-fp8v4` — q27-TP2 geometry with KV dtype
`fp8_v4`, served context native 262,144, `--max-num-seqs 8` — AND move `--max-num-seqs` to **5 on
the four existing lanes**, by making BOTH the dtype and the seqs per-lane DATA: two new env
channels (`RADIANCE_KV_CACHE_DTYPE` default `fp8`, `RADIANCE_MAX_NUM_SEQS` default `8`) whose
FORM fallbacks preserve today's shipped bytes, so the ONLY composed-argv deltas are the owner's
intended seqs 5 on the existing four and `fp8_v4` on the new lane. Re-cut the receipt gate to
**per-lane M bars** (the load-bearing rewrite), widen every lane/row-enumerating leg four→five /
12→15, and hand the owner the three-row jsonc spec (rows land after the boot receipts, D27).

**Architecture:** D43's FORM-vs-DATA split is the only mechanism. Both flags leave
`FORM_FIXED_FLAGS` and join a new testlib class `ENV_DEFAULTED` (env absent ⇒ flag composes at the
FORM default; NOT flag-absent — engine defaults bf16/256 are the hazards, RESEARCH §3.3/§4.1/§8.3).
`expected_env` projects an env entry only when a profile's value differs from the default ⇒ the
four existing blocks gain exactly one new line each (`RADIANCE_MAX_NUM_SEQS "5"`), the new block
carries exactly one dtype env and no seqs env (8 = default).

**Tech Stack:** Helm (bjw-s app-template 5.0.1), ArgoCD ApplicationSets, pytest render-contract
suites, bash surface suites, `receipt_gate.py`, llama-swap peers, OpenCode project config (owner).

**Spec:** `RESEARCH.md` (G1–G6; §4.1–§4.3 are the seqs authority — its measured inventory is used
as-is and cited §4.2) + parent law: cf-143 D27, context-window D6/D7/D8/D9/D10/D16, multi-instance
D43/D45/D46.

## Owner rulings — SETTLED, do NOT re-open (original batched round + 2026-11-23 scope-change round)

1. **R1 (informed, final):** new lane dtype **`fp8_v4`**, no rope scaling, served context native
   262,144. The owner was shown the corrected matrix (RESEARCH.md:284-295 — fp8_v4 = 84.7%/M 6.77
   vs k6_v4 = 95.7%/M 7.65) and §3.2's finding that **k6_v4 dominates fp8_v4 on every measured
   column**, and kept `fp8_v4`. This is an informed deliberate choice (DECISIONS D-15): no AC or
   success criterion may cite the k6_v4 figures; no agent swaps the dtype "helpfully"; the
   first-boot print — owner-executed — is the only evidence for any number.
2. **R2 (scope change, D-16):** `--max-num-seqs` becomes **per-lane: 5 on the existing four, 8 on
   the new lane**. The first draft's uniform-8 scope reduction (D-7) is VOID — `receipt_gate.py`'s
   single-distinct-seqs rule (:278) now fires by design and the gate is re-cut to per-lane
   resolution (chart fallback + that lane's env), its own tests re-pinned first (parent-D30).
3. **R3:** `.opencode/opencode.jsonc` rows authorized — owner-landed bytes (D27); existing rows'
   `limit.context` byte-untouched; context figure follows the lane's boot receipts, never precedes.
4. **R4:** ReBAR = owner-side per-card receipt only (`lspci -vv -d 1002:7551 | grep "Region 0"` →
   `size=32G`; cf-143 records cwsr/ECC/ReBAR PROVEN-DONE; P2P observed working boot-to-boot on both
   TP2 pods) — NOT BIOS-change authorization, and kept **separate from the rank-1 Gen3×4
   link-width defect** (slot/link training, different knob; 27b EXPLORE:396, flash EXPLORE:212).
   No chunk conflates them.
5. **R5 (scope-change discipline, D-17):** fn's leg is never oversold — at seqs 5 fn's MEASURED
   M ≈ 4.1 [EF] still refutes the 5 bar; "5 fixes funding" is explicitly FALSE in every fn AC.
   fn gets its own chunk + own review. **Order constraint (RESEARCH §4.1): the current-shape
   receipt block runs at the next owner scale act BEFORE the seqs wave lands** — else no baseline
   print exists to price the change against. Parent C04 stays `owner-triggered-not-run`; this
   ticket records that and does NOT try to close it. The family receipt LAW (DECISIONS D-14) binds
   every AC: require a boot print, never a derived prediction, never assume a receipt happened.

## Out of scope (explicit)

- Any context/window change; any rope/YaRN surface (`--rope-scaling` stays absent everywhere).
- **k6_v4** on any lane (R1 — declined informed); `--attn-prefill-fp8` or any lossy-attention
  stacking (the "+12% prefill" was its misattributed sell — RESEARCH §3.2/§9 C1; this ticket
  sells NO speed win).
- Any seqs value other than 5 (existing) / 8 (new); no general seqs policy beyond these blocks.
- Memory re-pin of any held pair (D7/D10 — 110Gi/24Gi move only on a boot print; the seqs-5
  checkpoint-slot shrink §2.7 is recorded, never pre-empted).
- Routing dtype/seqs through request-body params or any non-D43 channel (DECISIONS D-8 names the
  real law: D43 — no literal `--extra_body` rule exists in this repo).
- BIOS/host mutations; executing the Gen3×4 retrain/reseat (owner lanes; receipts only).
- Hand-bumped chart versions; `kubectl apply`; push/merge to `main`; agent edits to
  `.opencode/opencode.jsonc`; runner-literal / class-table / favorited-table moves (the lane is
  never a default route).
- Closing the parent ticket's C04 receipts (owner leg there; this plan only honors its LAW).

## Verified facts (plan-session reads + RESEARCH citations; scope-change round folded)

- **V-1 FORM pair**: `charts/radiance/values.yaml:226-228` fixed spine carries
  `--max-num-seqs 8 --kv-cache-dtype fp8` (both halves now become env-defaulted channels, same
  slots); comment law "absent env means absent flag" at :220-225 must be re-pinned for the new
  class; dual-channel ban :192-195.
- **V-2 gate re-cut (load-bearing)**: `receipt_gate.py` — `LANES` :56-61 four→five;
  `EXPECTED_SERVED` 262144 :66 unchanged (no context move; five lanes); `SMOKE_SESSIONS = 8` :71 →
  **5** (§4.2, D9(b)'s count superseded for fn by owner ruling — dated); block spec lines :111-115
  += fifth; smoke loop `i -le 8` :224 → 5; **`_SEQS_RE` :253 + `read_configured_max_num_seqs`
  :262-280 refuse on two distinct values (:277-279) — with per-lane FORM the chart now carries the
  fallback INSIDE `${RADIANCE_MAX_NUM_SEQS:-8}`, so the old regex matches NOTHING → today's gate
  would REFUSE (D49) on absence: the re-cut resolves per lane = chart fallback + that lane's
  `RADIANCE_MAX_NUM_SEQS` block env (from services values); item-3 text :80 + `_pool_diags`
  :329-355 + PASS banner :410 become per-lane bars; `FN_LANE` :63 keeps the smoke gating, count 5.
  Tests re-pin FIRST: `test_receipt_gate.py` :228-236 ("bar follows the FORM" → fallback read +
  per-lane override arms), :239-247 ("two distinct = ambiguous" → replaced by the per-lane
  resolution proof), HELD_GIB :38 / `_served_id` :64-70 / five-lane set :250-257 / smoke arms
  :167-188 (planted four-of-five).
- **V-3 funding (corrected, RESEARCH §2.0-§2.3, [E27], [EF])**: q27-TP2 pool 22.24 GiB/card =
  20.98 kv_attn + 1.16 state + 0.09 kv_draft (MEASURED; kv_draft stays fp8 under v4 — the 0.09
  does not shrink; context pool 22.15). Per-token/card: fp8 16 KiB, fp8_v4 12.5, k6_v4 11 (§2.1).
  NEW lane fp8_v4@262,144×**8**: **84.7% / M ≈ 6.77** (worst case 26.16 GiB/card) — DERIVED
  prediction, unfunded at 8 by 1.2; the gate refuses by design at first receipt (OQ-3).
  Existing lanes at **5** seqs: fp8@262,144×5 = 100% (106.9%) / M 5.34 — the 27b lanes become
  FUNDED (predictions; prints adjudicate); **fn (MoE geometry, [EF]): backing 52→82.4%, M ≈ 4.1 —
  REFUTES the 5 bar; §2.3/§4.3 — R5's no-oversell law.** The k6_v4 row (7.65/95.7%) is R1-rejected
  and appears in NO success criterion.
- **V-4 speed**: dtype-alone and seqs-alone are NOT sold as speed wins: 41k prefill 9.76/9.76/9.84
  s across dtypes (§3.2); seqs changes admission shape, not decode rate. The genuine non-loss
  rationale for 5 (put it in prose so the move isn't read as pure loss): **wht6 law — a 5-row lane
  crosses the lossy-allreduce threshold less often → small accuracy WIN** (§4.2), honest bar +
  ~4.5 GiB host slack from the auto slot law (§2.7, recorded only — D10).
- **V-5 engine-number effects (CLAIMED [G@t], §4.1/§4.2 — carry, don't measure)**: engine seqs
  default **256** (fallback mandatory); queued default 8×seqs ⇒ **64→40 at 5** (429+Retry-After
  pressure changes, peers surface it verbatim); `--max-n = max(8,seqs)` stays 8; checkpoint slots
  auto ⇒ seqs×10 (§2.7 arithmetic).
- **V-6 M-legs NOT pinning seqs — self-verified this session**: grep of
  `tests/pipeline-models/surface.sh` finds zero functional `--max-num-seqs`/admitted-smoke needles
  (M8 pins ctx/priority; the :769/:800 "session" hits are the M7 roster-semantic arms, unrelated).
  **No M-leg churn from seqs** — RESEARCH §4.2 confirmed; the difference between a small and a
  large test wave is this line. `tests/pipeline-models/TEST_SPEC.md:33` ("M ≥ 8 bar, D9(a);
  eight-admitted-sessions smoke, D9(b)") gets the D15/D16-style dated annotation only.
- **V-7 doc/test halves for seqs (both named, never split — D12)**: fn half =
  `tests/notes/radiance-runbook.sh` (:10 header prose, :278-279 `max-num-seqs…8|8 sessions|8
  concurrent` needle, :593-601 "8-session gate" needles, :747-760 step-6 capture keys, :788 marker
  list) ↔ doc half `.agents/notes/radiance-on-target-acceptance.md` (:524 ledger `--max-num-seqs
  8`, :641-642 "8 concurrent … eight admitted", :781 "default 8×max-num-seqs = 64 queued") —
  **both in C05**. q27 half = `.agents/notes/radiance-q27-boot.md:213` fenced vector ↔
  `tests/notes/radiance-q27-boot.sh` T2 (:239-284, live-compares against the COMPOSED vector —
  the script itself carries no seqs literal, verified) — **doc edit in C04**. Historical quote
  `radiance-second-gpu-tp2.md:251` (`--max-num-seqs 8 --max-model-len 200000`, already pre-D9):
  annotate-only, dated (C06); `radiance-tp2.sh` carries no seqs needle (verified).
  `charts/radiance/templates/NOTES.txt:73` "8-session ladder" re-aims in C02.
- **V-8 test authority**: radiance_testlib.py — `FORM_FIXED_FLAGS` :970-975 shrinks to
  port/host; new `ENV_DEFAULTED` class (dtype→fp8, seqs→8); `ENV_TO_FLAG` :967 gains both names;
  `expected_env` :978-997 (default-equal ⇒ no projection); `data_pair_bans` :1186-1200 skip widened
  (default-equal pairs legal FORM bytes; `--max-num-seqs 5` and `--kv-cache-dtype fp8_v4` stay
  BANNED literals in chart bytes); profiles re-pinned BY RULING: `FULL_PROFILE` :141 8→5,
  `Q27_PROFILE` :309 8→5 (dated annotation in the D9 style — "constant re-pin by ruling", the
  §4.2/:93 comment goes stale → annotate, never rewrite); `flash_tp1_profile()` :1000-1024 becomes
  the **three-value-swap** derivation (id + ctx + seqs, bounded-by-ruling again) and its
  transcription leg `test_resting_lanes.py:218-262` re-pins to "exactly THREE values swapped vs
  `e7536b2c9^`" with four-swap teeth; `q27_tp2_profile()` inherits 5 by derivation; new
  `q27_fp8v4_profile()` = `{**q27_tp2_profile(), "--max-num-seqs": "8", "--kv-cache-dtype":
  "fp8_v4", "--served-model-name": Q27_FP8V4_SERVED_ID}` — **the seqs re-override is mandatory:
  its parent profile now carries 5** (the derivation trap). `LANES` :715-743, `COMPOSITION_LANES`
  :1051-1056, `all_ruled_profiles` :1203-1206, `LANE_IDENTITY_LITERALS` :1211 widen four→five.
  `test_c03_generic_shell.py` :173-209 FORM-flag parametrize now covers port/host only + new
  rename/mutation teeth per channel; :521 tuple keeps BOTH flag NAMES (still FORM bytes) with the
  label re-aimed.
- **V-9 naming (unchanged)**: RFC1123 — identifiers `radiance-q27-fp8v4` /
  `gpu-ai-radiance-q27-fp8v4` / `qwen3.8-27b-radiance-fp8v4`; literal `fp8_v4` ONLY as the engine
  dtype value (env value/composed argv/prose); `surface.sh:1632` host-derivation is
  underscore-replace-safe. OQ-4 confirms.
- **V-10 pool/exclusivity (RESEARCH §5, roster note)**: 5 radiance releases + strata = **six
  claimants / 2 cards**; the new lane is TP2 (claim "2"): co-boots with NOTHING; the four seqs-5
  lanes change no claim. TP1 rejected for this lane (§2.4: funds M ≤ 2 at any dtype — not the
  concurrency pod asked for). Resting `replicas: 0`, owner scale act; pack-shared with q27
  siblings (marker skip). TP-vs-claim equality is pinned by `test_c03_tp_env_matches_the_gpu_claim`
  (:303-320) — the new seqs env rides no such cross-check; the dtype env likewise.
- **V-11 catalog/ladder (unchanged from first round)**: twelve existing radiance rows at
  `limit.context 262144`, five-key safe shape, no page/pagesize form (the cf-131 page-unification
  trap, cf-131 STATE.json:90 chain); ladder fn 9/5/1 · q27 8/4/0 · flash-TP1 7/3/2 · 27b-TP2 6/2/1
  (TEST_SPEC §3); fifth trio best guess 5/1/0 floor 1 needs the second NAMED low tie (OQ-2);
  M9-A2 equality trained==served==262144, value UNCHANGED.
- **V-12 six llama-swap widening sites (unchanged)**: llama_swap_testlib.py:957
  `RESTING_RADIANCE_LANES`; test_config_parity.py:337; test_flashnext_blast_radius.py:217;
  test_radiance_peer.py:130; test_strata_wiring.py:184; test_catalog_contract.py:233 (auto via
  tuple) + golden/gpu-ai.config.yaml re-capture (TEST_SPEC §13.2 cadence).
- **V-13 CI**: `.github/workflows/radiance-render-tests.yaml` one extraction+render step per lane
  (four today → five; `test_resting_lanes.py:468-480` pins both substrings); trigger paths stay
  byte-untouched.
- **V-14 roster note + script**: `radiance-multi-instance-roster.md` heading/table/steady-state
  rows machine-tied; `tests/notes/radiance-roster.sh` T1 :174-177 ("five things"), T2 :100 loop —
  widen four→five radiance keys (claim/replicas/served re-derive from the tree; **seqs is NOT a
  T2-derived field — the note's prose must still tell the per-lane seqs truth, C06**).
- **V-15 existing blocks**: none authors a seqs or dtype env (both env names are new — grep-verified
  this session); fn env :1126-1173 (git replicas 1 at :1063 — live-vs-git delta is context-window
  D11's note), q27 :1415-1443, flash-TP1 :1563-1610, q27-TP2 :1687-1717 (block template; resources
  :1718-1734). Each existing block gains EXACTLY one env entry (`RADIANCE_MAX_NUM_SEQS "5"`); no
  other byte moves.
- **V-16 2.x anti-direction (now also R1's upgrade-consequence note)**: 2.x refuses fp8_v4/k6_v4,
  refuses most `fp8`, refuses our MXFP4 packs by name (RESEARCH §0/[G@m], §8.6, issue #457) —
  two env channels now pin the deployment to the 1.17.0 line; the values annotations must say so
  (R-9; a risk-register entry, not a reconsideration).
- **V-17 measurement honesty**: all v4/seqs-effect figures except fn's 52%/4.1 and q27's
  66%/5.3 prints are DERIVED/CLAIMED (RESEARCH §0 "could NOT verify"); every AC requiring a number
  requires a PRINT, under the D-14 receipt LAW.

## Commands (validation battery; repo has no unit suite — these ARE the tests)

`export PATH=$HOME/.local/bin:$PATH` first; pytest runs **per directory** (`test_render.py` exists
in two suites — never combine).

- `python3 -m pytest charts/radiance/tests -v` — render/composition/gate suite (five lanes;
  designed-reds per chunk map).
- `python3 -m pytest charts/llama-swap/tests -v` — peers/evidence/catalog/golden contract.
- `python3 -m pytest charts/amd-gpu/tests -v` — pool-name identity (unchanged guard).
- `bash tests/pipeline-models/surface.sh M8 M9` + HOLD sweep `M1 M2 M3 M4 M5 M7` (NEVER M6 — write
  arm; run arms individually, fail-fast prints only the first red);
  `CF143_BASE_SHA=$(git merge-base main HEAD) bash tests/pipeline-models/surface.sh M8` (runner-
  literal pairing must stay untouched — this lane never routes by default).
- `bash tests/notes/radiance-runbook.sh` (GREEN through C01–C04 — the fn vector/env are unmoved
  until C05 lands its doc+test PAIR in one commit; any interim red means the pair split — a
  review blocker), `bash tests/notes/radiance-q27-boot.sh` (same law with C04's pair),
  `bash tests/notes/radiance-roster.sh` (red naming C06),
  `bash tests/notes/radiance-tp2.sh`, `bash tests/notes/radiance-host-tuning.sh` (unchanged).
- `bash tests/services/amd-gpu-naming.sh n1 n2 n3 n4 n5` — verified no-widen (admit predicate
  `startswith("radiance")`:366; python twin path-based).
- `helm lint charts/radiance` && `helm dependency update charts/radiance` && `helm template
  radiance charts/radiance --set domain=spencerslab.com --set clusterName=gpu-ai`.
- Five-lane render battery (extract-and-render per lane, plan idiom) for
  `radiance radiance-q27 radiance-flash-tp1 radiance-q27-tp2 radiance-q27-fp8v4`.
- **receipt_gate**: `python3 charts/radiance/tests/receipt_gate.py --commands > /tmp/block-<phase>.txt`
  — diff phases: C01 is the ONLY block-text wave (five lanes + per-lane bars + five-admitted
  smoke); C02–C06 must show EMPTY diffs. Behavior checks (all synthetic, no cluster): gate on the
  current tree resolves every bar to 8 (pre-env state, D49-clean); with C04/C05 envs landed the
  bars read 5/5/5/5/8; absent lane env ⇒ fallback, never a hardcoded guess.
- **Byte-stability AC (per lane, the intended-delta proof)**: for each existing lane, composed
  vector via the sandbox harness equals its ruled profile with **exactly one delta vs today:
  `--max-num-seqs 5`**; the new lane's vector carries `--max-num-seqs 8 --kv-cache-dtype fp8_v4`;
  `git diff` shows each existing block gained exactly one env line and zero other bytes.
- `npx aislop scan --changes --json` (errors zero; CI runs `aislop ci --changes`).
- JSON round-trip with duplicate-key detection for STATE.json (family corrupted twice 2026-11-23
  via hand-patched JSON): parse with `object_pairs_hook` counting per-level key duplicates; any
  duplicate is fatal.

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Test-authority wave — BOTH channels' legs, per-lane profiles 5/5/5/5/8, receipt-gate per-lane RE-CUT + its tests re-pinned, five-lane maps, M-series ladder, evidence, roster-script legs (RED-FIRST) | L | 1 | [] | test authority before any charts/**/services/** edit (parent-D30); the gate re-cut + test re-pin must land in the SAME wave (a gate rewrite after the FORM would certify nothing) |
| C02 | Chart FORM — seqs + dtype env-defaulted channels on the spine line + NOTES five-lane/8-session-ladder re-aim | M | 2 | [C01] | C01 pins the byte-shape the FORM must compose; landing alone changes NO lane (fallbacks = today's shipped bytes) |
| C03 | New-lane service wave — roster entry, `radiance-q27-fp8v4` block (dtype env, no seqs env), peers + evidence, CI step, golden re-capture | M | 3 | [C01, C02] | block's dtype env needs the C02 channel; peers+evidence+golden+CI land in ONE commit (parity cross-pins) |
| C04 | Resting-lane seqs wave — env `"5"` on q27 / flash-TP1 / q27-TP2 blocks + `radiance-q27-boot.md:213` doc half (both named here) | M | 4 | [C01, C02] | profiles/gate bars for 5 are pinned by C01, the channel exists after C02; parked lanes carry no live-route risk — fn deliberately NOT here (R5) |
| C05 | fn seqs wave — env `"5"` on the live-default-route block + runbook doc half + runbook-script test half (§4.3 evidence set, roll window, five-admitted smoke) | M | 5 | [C01, C02] + **order-gate: owner baseline receipts landed or waiver ruled (D-17)** | fn is every tier + the runner (context-window D16/D19 chain): own chunk, own review, and NO sync of this chunk's seqs change before the current-shape print exists (§4.1) |
| C06 | Docs — roster note six-claimant re-title + exclusivity + per-lane seqs prose + ReBAR/Gen3×4 separate receipt items; dated annotations (second-gpu-tp2.md:251, TEST_SPEC §13.2) | S | 6 | [C03, C04, C05] | roster T2 re-derives rows from the final tree; the note must describe 5/5/5/5/8 truthfully |

## Wave order

1. **C01** — nothing greens; gate/tests self-prove the per-lane bar resolution against synthetics.
2. **C02** — greens: channel legs + fallback legs + existing-lane **byte-identity at this point**
   (no lane envs yet → composed argv byte-identical for ALL FOUR); M8 HOLD unaffected.
3. **C03** — greens the new lane's render/roster/peers/golden legs (composes 8/fp8_v4).
4. **C04** — greens q27-family profiles-vs-env (5), q27-boot note pair; catalog legs still owner-red.
5. **C05** — greens fn's whole re-pinned pair (runbook doc+test, five-admitted smoke legs);
   **refuses to start** until the D-17 order gate is satisfied (baseline receipts recorded under
   the receipt LAW, or the owner's waiver ruled and dated in DECISIONS).
6. **C06** — greens radiance-roster.sh T1/T2/T4; final whole-plan review runs the full battery and
   records the remaining owner-gated reds BY NAME (D12).

## Landing shape — owner legs (nothing lands on main here)

0. **Baseline receipts FIRST (order constraint, §4.1/R5)**: at the next scale act, the owner runs
   the CURRENT-shape D8 block (today's four-lane artifact as merged — before any seqs/dtype env
   reaches it) and the output is recorded under the D-14 receipt LAW (owner-paste or Loki-quoted
   print only). This closes the evidence debt context-window left (`C04 owner-triggered-not-run`,
   NO receipt on record — recorded, not closed, by this ticket). If the owner instead rules
   "receipts taken on the new shape directly", the waiver is dated into DECISIONS BEFORE C05
   starts. Without one of the two, C05 does not run.
1. **Push/PR/merge** — owner creates/merges; agents never advance/push `main`.
2. **Sync + scale acts**: per-lane down-then-up as needed (three TP2 lanes still mutually
   exclusive); fn's re-roll carries the seqs-5 change = a pod roll on the pipeline's own route
   (stated window, D9(c) class). ArgoCD only.
3. **Boot prints (owner-executed; the only evidence)**: existing four — echo shows
   `--max-num-seqs 5 --kv-cache-dtype fp8`, queued default now 40, checkpoint slots ≈ 50/lane
   (§2.7 slack recorded, memory untouched D10); new lane — echo shows `--max-num-seqs 8
   --kv-cache-dtype fp8_v4 --max-model-len 262144`; pool-backs expected near 84.7%/M 6.77
   (PREDICTION, D-15(b)); page line expected ~200.00 KiB/16-token block (print calibrates).
4. **Gate run**: `receipt_gate.py --gate` with per-lane bars 5/5/5/5/8 — expected REFUSALS, each
   an owner-read: fn (M 4.1 < 5, R5's honest bar) and the new lane (6.77 < 8, OQ-3) unless the
   prints differ; N% < 100 warnings are owner-read, never machine bars (D16).
5. **jsonc trio rows** (owner diff per plan spec; AFTER step 3 receipts): rows 5/1/0 floor 1,
   shared modelID, five-key safe shape (V-11 — NO pages/pagesize form anywhere; context stays the
   family 262,144 token figure, M9-A2 equality legal), commentary names BOTH D47 figures and the
   honest capacity/no-speed prose.
6. **ReBAR receipts** (owner, independent of 2–5): `lspci -vv -d 1002:7551 | grep "Region 0"` →
   `size=32G` per card, both cards — collection only, NOT BIOS authorization; kept textually and
   operationally **separate from the rank-1 Gen3×4 width defect** (own reseat lane) in C06's note.

## Risks

- **R-1** (was the attribution risk; CLOSED as R1-informed) — residual: a later agent must not
  re-litigate the dtype or import the k6_v4 figures into success criteria (D-15 guards).
- **R-2** new lane prints M < 8 (6.77 expected) → gate refuses — owner-RULED deficit (OQ-3), same
  class as fn's open 5.3/66%; never a silent "fix" by dropping the new lane below 8 later.
- **R-3** fn refutes at 5 (M 4.1 < 5) — the ruling does not fund fn; C05's review set must prove
  the honesty; any prose claiming otherwise is a review blocker (R5/D-17).
- **R-4** live-route rolls: fn's seqs-5 sync + the new lane's bring-up both interrupt capacity on
  the pipeline's own route (V-16 class); order-gated and owner-paced.
- **R-5** admission-shape drift at 5: queued 64→40 [G@t] — 429-class pressure rises under
  many-client bursts; recorded in each lane's block comment; peers surface 429+Retry-After as-is.
- **R-6 catalog-red window**: M8-A2/M9 catalog halves stay red until owner step 5 — designed,
  named, dated (D12/D15 precedent), never "fixed" by relaxing legs.
- **R-7 print-shape**: v4/seqs prints are DERIVED expectations; gate greps calibrate on first run
  (D16); absence/unparseable M keeps refusing (D49) — never a pass on absence, never a prediction
  recorded as receipt (D-14).
- **R-8 test-map drift**: five-lane widening comes from the SAME testlib/gate/M9 sources
  (V-2/V-8/V-11/V-12/V-13/V-14); prose re-pins ride it so fail messages never lie.
- **R-9 1.17.0-line pin**: both env channels name dtype/seqs shapes that 2.x refuses (V-16) — any
  future engine move is a separate from-scratch ruling; the values annotations carry the law.
- **R-10 order-gate erosion**: if C05 lands without the baseline print (or a dated waiver), the
  ticket re-pays CW D3's merged-unobserved wound; the gate is a plan constraint, not a suggestion.

## Open questions (ONE batched round — OQ-1 CLOSED by R1, kept numbered for traceability)

- **OQ-1 — CLOSED 2026-11-23 (R1/D-15)**: dtype kept `fp8_v4` informed; figures recorded.
- **OQ-2 (fifth-trio ladder / second named low-tie)**: no collision-free fifth trio under M9-A2
  laws; best guess urgent 5 / default 1 / low 0 + second NAMED tie in `ACCEPTED_LOW_TIES`
  (surface.sh:1499). Impact: M9 reds until ruled; existing twelve rows never move.
- **OQ-3 (new-lane deficit at 8)**: expected print M ≈ 6.77 < 8 → gate refuses at step 4. Confirm
  the owner accepts the explicit deficit (recorded with the receipt), or pre-authorizes the
  alternative lever. Best guess: accept. Impact: unretracted, the lane's PROVISIONAL reads as
  failure, not ruling.
- **OQ-4 (spelling)**: identifiers `fp8v4` compact / literal `fp8_v4` only as dtype value
  (V-9/D-2). Best guess: as specced. Impact: cosmetic pre-boot, annoying after rows/receipts.
- **OQ-5 (baseline timing vs waiver)**: when at the next scale act does step 0 run (it may ride
  the same window as fn's bring-up)? Best guess: block-first in the window, then the seqs sync.
  Impact: this is C05's order gate — slipping it re-opens CW D3's wound (R-10).
- **OQ-6 (quality probe)**: one small tool-calling accuracy A/B on the lane's first boot (fp8_v4
  vs today's fp8; V int4 never scored on agent transcripts — RESEARCH §0 "could not verify" 3)
  before routing opt-in. Best guess: run, quote into DECISIONS; declining is legitimate at
  replicas 0. Note: the existing lanes' seqs 5 needs no probe (wht6 crossing gets RARER — small
  win, V-4).
- **OQ-7 (fn's standing refutation)**: fn at 5 still prints 4.1 < 5 (§2.3); the ONLY lever that
  funds fn is its own dtype move (§2.3: fp8_v4→≈5.1, k6_v4→≈5.7 — changes the live route's output
  bits; RESEARCH §9 C6 left it un-asked). Does the owner want fn's lane dtype ruled NOW (it would
  ride a follow-up ticket), or accept fn's deficit-with-honest-bar and keep dtype where it is?
  Best guess: accept 5 + deficit; a dtype follow-up gets its own receipts. Impact: decides whether
  a follow-up ticket spawns; nothing in THIS plan depends on the answer.

## Deviations recorded (from the first launch brief; scope-change round folded)

1. Brief's "`--extra_body` law with file:line" → no literal rule exists; D43 named with real
   cites (DECISIONS D-8).
2. Brief's `RADIANCE_KV_DTYPE` example → `RADIANCE_KV_CACHE_DTYPE`; plus new `RADIANCE_MAX_NUM_SEQS`
   (flag-mirroring convention).
3. Brief's example `radiance-fp8-v4` → `radiance-q27-fp8v4` identifiers (D-2).
4. Brief's "scope reduction to exploit" (uniform-8 → no gate rewrite) → VOID per owner R2; the
   gate re-cut is first-class C01 work (D-16). The D-7 verification stands as history of the
   superseded ruling.
5. RESEARCH §5's "three exact-set legs" → six widening sites (V-12).
6. RESEARCH §4.2's M-leg "no churn" claim → **independently verified** this session before
   trusting it in the chunk plan (V-6).
