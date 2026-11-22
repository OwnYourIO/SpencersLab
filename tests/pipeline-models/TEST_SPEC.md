# TEST_SPEC — `tests/pipeline-models/surface.sh`

Contract notes for the routing/catalog surface suite. The suite header carries
the per-leg AC trace; this file records only the decisions a reviewer or a dev
must not have to re-derive: where a pinned number came from, which ruling retired
an older needle, and what each arm's red posture means.

Sections are cited by number from inside `surface.sh` — keep the numbering
stable when you extend it.

## 1. The radiance context axis (two figures, one honest pair)

The catalog row and the pod disagree about context length ON PURPOSE, and this
suite pins both ends instead of forcing one number:

| Surface | Figure | Whose ruling |
|---|---|---|
| `.opencode/opencode.jsonc`, all twelve radiance-family rows (fn trio, q27 trio, flash-TP1 trio, 27b-TP2 trio) | `limit.context: 262144` | the owner's catalog edit `b3d7fada8` (2026-11-22) set the six then-live rows, protected by DECISIONS D27 ("never those six context values"); owner ruling D47 (2026-11-23) moved the six C05 rows to the same figure — it is the trained window the CLIENT budgets against, on every row |
| `charts/radiance/values.yaml` → `app-template.maxModelLen`, and the `--max-model-len` the chart renders | `200000` | D17 FULL profile — what the engine ADMITS per request |

The cf-143 needle asserted the two were EQUAL (`ctx == maxModelLen`, the
"catalog mirrors served truth" law). The owner's edit retired that equality by
ruling, so M8-B is now three teeth rather than a dropped leg: the served scalar
stays 200000, the catalog figure stays above it, and the catalog COMMENT must
name both figures where the rows sit. An unexplained gap between what the client
plans and what the pod admits is exactly the drift class this suite exists to
catch — the numbers may differ, the prose may not go silent.

Rejected alternative, recorded so nobody re-files it: re-pinning the six rows to
200000. D27 puts those bytes outside this ticket (and outside every later one
until the owner moves them), and M3/M8 would then be editing owner catalog
policy rather than testing it.

**Consequence for new lanes (M9) — rewritten by owner ruling D47 (2026-11-23).**
The family is UNIFORM: the six rows C05 authored at `200000` were flipped to the
family figure `262144` by D47, and the served `200000` survives as a separate,
named figure in the commentary governing those rows — the M9-A2 ctx leg pins both
halves (per-row `limit.context == 262144`, AND both figures named in the
governing prose, with planted-drift teeth on each half). The dissent D47 records
rather than buries, in one line: 200000 was defensible because it EQUALS the
served admission of all four lanes (no truncation class exists there; the risk
runs the other way — a catalog above served means over-budgeted requests meet a
loud server refusal); the owner chose one family-wide meaning for the field, a
convention decision, not a bug fix. The split this paragraph used to describe
(six at 262144, six at 200000) is closed history.

## 2. The 2026-11-22 routing move (D4/D16/D20) and the flipped M8-F

`gpu-ai/qwen3.8-flash-next-radiance` becomes every tier's default and the
scheduled runner's model; explicit `Qwen Dense + Local` becomes
`gpu-ai/qwen3.8-27b-radiance` (D20, with its accepted 502-loud consequence —
that lane rests at `replicas: 0`); the `10+`/background leg of the class table
STAYS `gpu-ai/qwen3.8-27b-q4`, which is why M7's background row leg and M4's
27b-q4 serving leg survive the move unedited.

The Strata lane is DEMOTED, not deleted, and M8-F flipped to match:

* pipeline-models keeps the `qwen3.8-flash-next-strata-q4` id (one documented
  alternate sentence + the favorited inventory row) and must NOT carry it as the
  routed form — M1 and M8-F both bar the routed string;
* pipeline-kickoff and boards must not name it at all — the single-authority bar
  the q3 alternate has always had;
* the catalog rows stay live (M3 HOLD) and served (M4), so the lane still answers
  when a human routes to it.

Red posture: M1/M2/M5/M8-F/M8-H are the designed reds naming C02; M3/M4/M6/M7
are HOLD and must stay green across the window.

## 3. The four-lane priority ladder (D19's numbers, resolved by the coordinator's follow-up ruling on the test author's D-3)

Owner ruling D19 adopts the sibling's starting shape (`flash-tp1 7/3/2`,
`27b-tp2 6/2/1`), states laws (full trios, strictly-below-live per class column,
unique per class column), and names the shipped collision — 27b-tp2's `low 1`
duplicating fn's `low 1` — as the test author's to resolve. The test author's
first resolution extended the low column below zero (`7/3/-1`, `6/2/-2`) to keep
all three laws literally; the coordinator REJECTED the negative rungs and the
plan's starting shape stands:

| Lane (rank order) | urgent | default | low | peer floor |
|---|---|---|---|---|
| fn (live) | 9 | 5 | 1 | 5 |
| q27 (live) | 8 | 4 | 0 | 4 |
| flash-TP1 (C05) | 7 | 3 | 2 | 3 |
| 27b-TP2 (C05) | 6 | 2 | 1 | 2 |

**Why the negatives were rejected** (the coordinator's citation, kept because a
resolution is only as honest as its evidence): the catalog has ONLY ever shipped
non-negative `body.priority` — the six live rows at ruling time span 0..9 (the
family is twelve rows since C05; the class is unchanged) — and cf-143 already
records `priority-0` SEMANTICS as UNVERIFIED with the CI smoke as the receipt
(`charts/llama-swap/tests/evidence/radiance-q27-peers-expected.yaml:28`,
`charts/radiance/tests/radiance_testlib.py:317`). An authoring session does not
extend an already-unverified behaviour class into untested negatives on its own
authority; **rejected: the negative-rung ladder `7/3/-1` + `6/2/-2`**, and M9-A2
bars any negative rung on its face.

**The laws as enforced** (surface.sh M9-A2, stated generally for any future
lane): full trios registered per lane; the `urgent`/`default` columns are
cross-lane law — pairwise unique and strictly decreasing in lane rank (every new
lane below both live lanes); every trio strictly decreasing WITHIN its lane; no
rung negative. The `low` column is per-lane law: the four lanes are four
separate engines with four separate queues, each peer's `priority?` floor is
per-lane, and no M8 leg requires cross-peer uniqueness — so fn's `low 1` and
27b-TP2's `low 1` are an **ACCEPTED CROSS-PEER TIE, not a collision**. The tie
is enumerated in the suite (`ACCEPTED_LOW_TIES`); a second, unnamed tie reddens,
and the teeth plant exactly one (`flash-tp1 low := 0` vs q27's shipped `0`).

**Peer floors vs the chunk text (the D-2 law, unchanged).** chunks/C05.md says
"floor = 5 fn-class floor for the flash lane, 4 for the 27b lane". Those numbers
pre-date D19's trio shape: a floor ABOVE the lane's own default row would land
non-priority clients above the lane's default class, which is what the cf-143
per-lane M8 coherence law forbids (`peers.<lane>.filters.setParams "priority?"`
== the lane's default-class row — fn 5, q27 4, flash-TP1 3, 27b-TP2 2). The
evidence YAMLs carry 3 and 2; recorded as a test deviation for the coordinator.

**Receipt, not claim.** The rungs ship inside the non-negative class the catalog
has always used — `low 1` is fn's own shipped value, `0` stays q27's — so nothing
new is claimed about engine behaviour; the on-target smoke read remains the
receipt for the values AS SHIPPED, and a correction re-pins here through a
DECISIONS line, never a silent retarget.

## 4. The boards blank-Model(s) default (RESOLVED by the coordinator's ruling, 2026-11-22)

A card with no `Model(s)` item checked resolves exactly as today's defaults, with
the radiance move applied to the FLASH size and NOT to the big-context background
leg:

* blank → the default selection is `Qwen Flash + Local` →
  `gpu-ai/qwen3.8-flash-next-radiance` (the same move the Model(s) checklist's
  default-checked row rides);
* blank + the `10+` (≥100k context) item → `gpu-ai/qwen3.8-27b-q4` via the outer
  swap — the sentence that has never moved (the `:750-751` requirement the M7 leg
  correctly KEPT green through this ticket).

**Why the 10+ leg does not move.** Routing the pipeline's big-context default
onto the parked q27 RADIANCE lane would 502 it while that lane rests — a silent
pipeline default landing on a replicas-0 engine. And D16 already concentrates
every other tier on the single live fn lane; the same surface must not gain a
second silent failure mode. The q4 outer-swap engine is live today and stays the
blank+10+ answer.

This closes the test wave's open question: the earlier §4 wording ("the leg
accepts either honest resolution") is superseded — dev and review read ONE law
here, and a boards surface teaching a blank default of `27b-q4`/strata, or of
`Qwen Dense` onto the parked radiance q27 lane, is drift. The radiance lane names
and the cite-don't-restate posture stay as the leg already enforces them.

## 5. The runner-literal pairing law (M8-H)

Six surfaces carry the scheduled runner's model byte:
`.agents/loops/pipeline-worker.md`, `.rulesync/rules/overview.md`, generated
`AGENTS.md`, `tests/opencode/pipeline-locks-tick.test.ts`,
`tests/provider-loops/surface.sh` (t1 + t3) and
`tests/agent-board-coord/agents-md.sh` (c11). The cf-143 leg was an empty-diff
inventory that failed on ANY touch of the rules/loop pair — it blocked precisely
the edit the 2026-11-22 ruling ordered. The bar is now PAIRING: all six carry the
same byte (currently `gpu-ai/qwen3.8-flash-next-radiance`), the ruling chain is
cited where the literal lives, and a planted single-surface drift must be caught
(the leg re-runs its own comparison against a mutated copy, so an inventory that
cannot fail cannot pass either). `CF143_BASE_SHA=<merge-base>` adds the range
half: over a review range, the six move together or not at all.

## 6. Run matrix

| Run | Command | Posture |
|---|---|---|
| any read-only review before C05 | `bash tests/pipeline-models/surface.sh` (M1–M7) | M1/M2/M5 red naming C02; M3/M4/M6/M7 green |
| C02 review | `bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M7 M8` | all green once C02 lands (M6 is a WRITE arm — regenerate leg, never in a read-only run) |
| C05 review + final | `bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M7 M8 M9` | M9 green only with the six catalog rows, the two peers and both evidence files |
| review-time pairing | `CF143_BASE_SHA=$(git merge-base main HEAD) bash tests/pipeline-models/surface.sh M8` | range half of the pairing leg |

`bash -n` is not a check: every arm runs `python3`/`node` heredocs, so a leg that
never executed is indistinguishable from a green one. Run the arms, read the
`ok:` lines.

**Coverage split (settles the test wave's D-10).** M4 is the serving-authority
leg for the two ROUTED-TO ids only (`qwen3.8-flash-next-radiance`,
`qwen3.8-27b-radiance`); the two NEW lane ids are deliberately out of M4's loop
and pinned by M9 — M9-E extends the serving-fact guard to them and M9-C is their
peers↔evidence unit.

**M6 is a WRITE arm — and a conditional one (settles the test wave's D-8).** In
THIS suite M6 regenerates: after the pair-sync reads it runs `rulesync generate
--check` and then `rulesync generate` TWICE (the second proving idempotency) —
real writes into `.opencode/` whenever rulesync resolves; only when it does not
resolve does the arm take its documented skip path (read-only pair checks,
warning). In the test-wave sweep rulesync DID resolve, the generated twins were
already in sync, and both generates were no-ops — that is why the arm reads green
with zero file changes, not because the arm is read-only. Repo law therefore
keeps M6 out of bare read-only runs; review sessions run it only when a
regeneration is intended.
