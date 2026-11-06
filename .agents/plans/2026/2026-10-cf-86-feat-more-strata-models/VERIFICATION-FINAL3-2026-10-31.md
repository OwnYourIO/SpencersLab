# VERIFICATION PASS — third-final-review routings (2026-10-31, read-only, HEAD 98a669a3f)

Scope per launch: confirm-or-reject the §6 close-outs (findings 1–3 + STATE hygiene) at
`98a669a3f`; do not re-open scope or re-review chunks. Tree verified clean at start
(`git status --porcelain` empty) on branch `cf-86-feat-more-strata-models`. READ-ONLY run:
zero git write ops, writes only this file; probes used /tmp/opencode/verify-cf86/ file-copy
backups with byte-exact restore + `cmp` + `git status` re-verified clean (0 lines) after
every mutation.

## Verdicts

### Finding 1 (MAJOR, checkout-delete supersede) — CLOSED
- Plan Commands on-target line: L62 carries the **SUPERSEDED** clause with the why
  (engine/.venv/expert-profile.bin/run-configs INSIDE, outside markers suppress recompile)
  and points at C09's `.checkout-0.2.9-carry1` first-boot migration as the only refresh.
  (Commit msg says "L61"; clause sits at L62 — one-line numbering slip, clause verbatim.)
- DECISIONS: 2026-10-31 coord routing-1 entry at L42 names all three sites (plan bullet,
  DECISIONS entry, chunks/C07.md L79-adjacent) as SUPERSEDED and forbids the shape. The
  old plan entry (L75) stays verbatim per append-only, superseded-by-name — the same-file
  precedent (L77 "C08 supersede note — DECISIONS append-only, U2's line stands as
  history") is exactly this mechanism. Nit: the pointer quotes "operator claim-refresh"
  vs the entry's own title "(v0.2.8 re-pin decode caveat)" — identification still unique.
- Host-prep §2 (L230–240): **Never delete `/models/strata/Strata`** prohibition line with
  full why-clause + "the refresh is the driver's own step" pointer to the marker migration.
- §1 sweep re-run (repo-wide grep for every delete-instruction variant): every survivor is
  either (a) the prohibition/supersede prose itself, (b) annotated history in the same
  record (chunks/C07.md L79 carries the round-3 F-A supersede note appended at L164+;
  chunks/C09.md L154 is the supersede statement), (c) sanctioned data-dir cleanup
  (host-prep §3.3 trio, correctly `.pack-orca` FIRST with the tier-independent why), or
  (d) protective negative pins (`rm -rf /models/strata/Strata-data` absent-arms). Chart
  README L150–156 caveat rewritten from "only moves when that checkout is refreshed" to
  the marker-keyed migration wording — the README-side survivor is gone too.

### Finding 2 (MAJOR, README 0.1.55 + four-surface label law) — CLOSED
- README: both engine-exe rows 0.1.55; five-row inner table (orca/q4/ornith added);
  `(p | s | o | q | n)` five-alternatives paragraph with RAM-class ordering; "all five
  run-config profiles" keyless fix; perf paragraph now 0.1.55-era + migration wording.
  Zero survivors: grep `0.1.54|(p | s)|two alternatives|both run-config` over the README
  → no hits (rc 1).
- Four-surface law exists by name —
  `containers/strata/tests/test_dockerfile.py::test_c07_engine_package_labels_are_one_fact_across_four_surfaces`
  — GREEN on shipped docs; surfaces = Dockerfile, containers README, values.yaml
  (halo-only), chart README (pair-expected). Era-3 PROVENANCE carries the new name +
  rename note; era-2 keeps the old name as frozen history (correct).
- Presence-arm widening verified: `allowed_homes` = values.yaml + **charts/llama-swap/README.md**
  + services overlay; docstring rewritten to the presence-era homes.
- Teeth spot-probed this session (file-copy discipline):
  P1 stray needle appended to `containers/strata/README.md` (a live non-home) → presence
  arm RED naming `['containers/strata/README.md']` (negatives intact elsewhere; README's
  own legitimate needles no longer stray — arm green with the five-row table present).
  P2 (reproduces §9.21 P-B) README halo 0.1.55→0.1.56 → four-surface arm RED "chart
  README engine labels … lack …". Both files restored byte-identical (cmp clean).

### Finding 3 (MAJOR-bundle, runbook five-arena era + host-prep) — CLOSED
- Host-prep §3.3: five-row arena table incl. ornith row (`strata-ornith-q4.json`, none
  declared, ~40–48 GiB R5 estimate) + "#1601's pairing covers three of the five rungs".
- §3.4: **five** serve --plan invocations (iq3_s / strix / orca-iq4_xs / q4 / ornith) each
  with its per-chunk finalize list (primary auto-cache, strix hypothesis pair, orca 3-shard
  PLE + first compat-bf16 fidelity read, q4 PLE-mmap pin + HIP round-trip gate with the
  pre-registered fallback, ornith cap + expert-slots/vram finalization "nothing guessed").
- §3.8 anchor `(p | s | o | q | n)` + the pre-declared law sentence verbatim ("that string
  is the alternation the runbook pin law ties to the live render"); §4 RAM law carries the
  same anchor, five-arena sizes, and the now-NAMED collision rule: llama.cpp
  `ornith-1.5-122b-q4` × Strata `ornith-1.5-122b-strata-q4` want the same 32 GB R9700 —
  NEVER both resident, A/B runs with the other unloaded, discipline-not-enforcement.
- New pin arm `test_strata_runbook.py::test_c09_runbook_alternation_ties_to_the_rendered_sets_main`
  run here: GREEN; regex finds exactly 2 anchors, both == rendered sets.main.
  §9.21 ledger honesty verified by reproduction: P3 (reproduces P-C) §4 anchor shortened →
  RED "drifted from the rendered sets.main '(p | s | o | q | n)'"; P4 (reproduces P-C2)
  §3.8 anchor dropped → count-half RED "want exactly 2", 1 found. (First P4 sed silently
  no-op'd — the green on that run was a non-mutation, re-run with a verified 1-line diff.)
  All note mutations restored byte-identical.
- Peers header: comment-only rewrite (0 non-comment lines changed in the file's diff);
  era-honest prose (six-state APPEND-ONLY history, C08 sweep the one sanctioned shrink,
  models_allowed = five served ids since C09). Chain data untouched.
- X(12) wording sweep: shipped surfaces say **Q4_K (fmt 12)** — patch L18/L55,
  values.yaml:2193; chunks/C09.md prose carries the correction with the census citation;
  test docstring Q3_K_M mention is the correction ledger itself. Constants byte-unchanged:
  98a669a3f touched neither `carry/ornith-q36.patch` nor `values.yaml` (diffstat), and the
  C09 landing commit `9400951cb` carries the relabelled wording with correct constants at
  HEAD (`kNativeHBytes 1024→2048` hunk, X(12) in both D_FMTS branches) — pinned green by
  the carry arms (`+ line adding X(12)`, `kNativeHBytes = 2048` greps) inside the 24P/416P
  runs. The unrelated `gguf-py/constants.py MOSTLY_Q3_K_M` is the vendored gguf enum, not
  cf-86 prose.

### §6-minor STATE hygiene — CLOSED
`json.load` passes; `current_wave: 9`; `plan_status: "approved"`;
`revision_round_3_2026_10_31.plan_status_gate` = "RESOLVED 2026-10-31 …";
`run_state.status` = "revision-3-closing (waves 7-9 + docs x2 landed; third-final
verification pass pending)" — the three stale fields my §5 called out all now match the
plan of record. (This file lands after that "pending" phrase resolves — expected.)

## FULL posture (this session, PATH=$HOME/.local/bin:$PATH, helm v3.16.4)

| run | measured | expected | verdict |
|---|---|---|---|
| pytest charts/llama-swap/tests -q | **0F / 407P / 9S** | 407/9 | exact |
| same RUN_HF_CHECK=1 RUN_FLAG_AUDIT=1 | **0F / 416P / 0S** | 416/0 | exact |
| pytest containers/strata/tests -q | **24P** | 24 | exact |
| guards rulesync-surface/gate/agents-md/agent-perms/pipeline-models/validation-fix/coord-inwork | **19/22/9/15/6/8/7**, all rc 0 | same | exact |
| npx aislop ci --changes | 0E / 0W / 0 fixable, 64 files | clean | pass |

Skip law honored: the 9 plain skips named by `-rs` — 8× RUN_HF_CHECK
(heretic_rungs_27b:237/272, heretic_rungs_flashnext:188/221, hf_liveness:26,
strata_c08_rung_shifts:349, strata_c09_ornith_carry:392, strata_q4_rung:310) + 1×
RUN_FLAG_AUDIT (flashnext_regime:188). The +1/+1 vs the final3 406/415 pair is the NEW
runbook arm (9 skips unchanged). c09 skip line moved 389→392 (docs-round drift, same arm).
aislop note (per my own final3 §1 nit): on the now-clean tree `--changes` resolves against
the main merge-base `617e18488` — this run IS the whole-ticket posture, not the working
tree; verified merge-base this session.

## Overall

**APPROVED — the final3 gate lifts.** All three MAJOR routings and the STATE hygiene
minor are closed with evidence; no blocker or major remains. Non-blocking nits (no action
required): (1) supersede-pointer label "operator claim-refresh" ≠ entry's own title
(unique identification still holds); (2) commit-msg "L61" vs clause at plan L62; (3)
`containers/strata/tests/__pycache__/` on disk (untracked, recorded hygiene item).
Observation for coord (engine-domain, already a FRICTION item, NOT a gate):
`pipeline_status` showed the Context set (8b162ddf / card #86) heartbeat state as
"failed" with ageMs 15 — confirm the lock is live (a heartbeat beat) before the card move
+ `pipeline_release(outcome:"done")` in the closing sequence.
