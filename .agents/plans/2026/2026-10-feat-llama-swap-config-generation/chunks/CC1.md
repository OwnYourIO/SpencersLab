# CC1: contract retirement — autogen test scope deleted, HF liveness retained (sole gate), evidence yaml re-balanced
size: M   wave: 8   depends_on: [user approval of the CR6 replan (2026-10-24: plan approved as planned + "retire c04_4 too")]
TEST-SESSION-ONLY chunk: agent-test session ses_e9bdebccbffe7bYG46Fm9LO8FG writes this
(tests immutable downstream; CA1/CB1 precedent). Ledger discipline: every retirement
records WHAT was removed, which chunk it belonged to, and WHY (CR6 declared-only
ruling, DECISIONS 2026-10-24) — same audit standard as amendments.

## Goal
Shrink the test contract to the DECLARED-ONLY surface: retire every test whose reason
for existence is the autogen machinery or the fleet-image validation path (user ruled
c04_4 retired too — pod boot on-cluster is the only -validate proof), while KEEPING
the live HF re-verification of every -hf/-hfd ref (re-homed, gate-decoupled) and the
reloader-annotation guard re-expressed for the single ConfigMap. Source untouched:
after CC1 the shrunk suite must still be fully green against the CURRENT (still
autogen-wired) chart — no surviving test may assert autogen's EXISTENCE.

## Tasks
- [ ] RETIRE `test_autogen_wiring.py` (32p): all C03/CA4 wiring contracts (init
      image/secCtx/mounts/volumes/env-config-dir, base.yaml x4, degrade trio,
      usage/home/args-not-command, drift probes x2, synthetic-scanned disjoint) +
      `test_c03_4_declared_model_ids_are_colon_free` (two-file-merge invariant;
      P1's colon-free CATALOG exact-set subsumes it).
      RE-HOME+RE-EXPRESS: `test_c03_5_reloader_annotation_covers_both_configmaps`
      -> declared-scope guard x2 clusters (auto-annotation OR explicit match naming
      `llama-swap-config` ONLY; BASE_CM leg deleted) — place in
      test_config_schema.py (the hot-reload contract is what CR6 KEEPS).
- [ ] RETIRE `test_autogen_image.py` whole (6p/4s) — parses the Dockerfile that CC2
      deletes; its LLAMA_SWAP_IMAGE_EVIDENCE gate retires with it.
- [ ] RETIRE `test_autogen_integration.py` whole (8 tests, all gated):
      `c03_2_3_base_yaml_*` (x2), `c03_4_scanned_half_*`,
      `c03_5_declared_only_with_empty_config_dir_*`, `c04_4_full_roster_declared_
      validates` (x2 — USER-RULED RETIRED, 2026-10-24 CR6 gate: pod boot is the
      -validate proof), `autogen_cli` + `fleet_image` fixtures.
      RE-HOME the sole keeper: `test_c04_1_hf_repo_tags_resolve` -> new file
      (e.g. `test_hf_liveness.py`) gated on RUN_HF_CHECK ALONE — decoupled from the
      LLAMA_SWAP_EVIDENCE module skipif it currently hides behind (it uses helm
      renders + the HF API, never the venv or docker; C04 friction logged the
      accidental coupling). KEEP `hf_check.py` verbatim (roster-liveness machinery).
      RETIRE `fixtures/scanned_synthetic.yaml` (sole consumer: the disjoint test —
      grep-prove before deleting).
- [ ] `LLAMA_SWAP_EVIDENCE` retires ENTIRELY as an env gate (last consumers were
      the venv/fleet tests). Evidence-gate inventory: 12 -> 1.
- [ ] testlib prune AFTER the above, zero-consumer grep per symbol RECORDED:
      ENTRYPOINT_FILE, _comment_only, FAIL_STUB/OK_STUB, BASE_CM, scanPaths/venv
      helpers, FLEET_IMAGE, docker_ready (+ any fixture helper left purposeless).
      KEEP: is_echo_cmd, render_rc, chart_values/service_overlay, ALL frozen tables
      (CATALOG/REMOVED/ENABLEMENT/C04_HF_REFS...), golden + render + model_tokens +
      derived-id machinery.
- [ ] `evidence/c05_expected_evidence.yaml` re-balance: drop prerequisites
      [containers/llama-swap-autogen rebuild], gpu_box items [initContainer state,
      entrypoint degrade log, scanned-half content, reloader coverage of the NEW CM
      -> replaced by ONE line: declared-CM watch-config hot-reload observation],
      and every merged/-config-dir/-validate test-hook wording (pod boot = the
      validation). KEEP verbatim: 58 counts + gpu 34/24 partition, echo spot,
      /v1/models completeness + CR5 picker-vs-display-table check, serve-smoke
      approval gate, gpu-ai config-level confirmation, q5/q6 routable-unpreloaded,
      removals + matrix-closure sweeps, machine-global 13+9 enumeration, runbook
      addenda (first-load measures, uppercase-MTP, enlarged picker lists, rollback).
      Regenerate programmatically; attach the dropped-vs-kept item diff to RESULT.
- [ ] TEST_SPEC: §4 gating matrix re-baseline (12 gates -> 1: RUN_HF_CHECK), §6
      trace lines for retired C03/C04/CA4 criteria marked retired-with-reason, NEW
      §7quinquies retirement ledger (every item: what / owning chunk / why + the
      user ruling on c04_4) + FROZEN completion bars + carry-fix the 7quater
      159->155 digit and the 7-D 17->16 nit (final-3 findings, next-test-touch
      convention).

## Files in scope
- charts/llama-swap/tests/test_autogen_wiring.py (deleted)
- charts/llama-swap/tests/test_autogen_image.py (deleted)
- charts/llama-swap/tests/test_autogen_integration.py (deleted)
- charts/llama-swap/tests/test_hf_liveness.py (new — re-homed keeper)
- charts/llama-swap/tests/fixtures/scanned_synthetic.yaml (deleted)
- charts/llama-swap/tests/llama_swap_testlib.py (pruned)
- charts/llama-swap/tests/test_config_schema.py (+2 reloader guard)
- charts/llama-swap/tests/evidence/c05_expected_evidence.yaml (re-balanced)
- charts/llama-swap/tests/TEST_SPEC.md (7quinquies + §4/§6 re-baselines)
- NOTHING outside charts/llama-swap/tests/ (source untouched — see Goal invariant)

## Acceptance criteria
1. FROZEN BAR: `pytest charts/llama-swap/tests -v` => **0 failed / 119 passed /
   1 skipped**. Arithmetic tied in 7quinquies: passed 155 − wiring 32 + re-expressed
   reloader 2 − image 6 = 119; skips 12 − image 4 − integration 8 + re-homed HF
   keeper 1 = 1. Per-file recount: parity 34, schema 22 (20+2), roster 30,
   hf_liveness 1S, CI-existing 33.
2. THE INVARIANT: the bar passes against the CURRENT UNMODIFIED SOURCE (autogen
   still wired at HEAD) — proof no surviving test references autogen.
3. `RUN_HF_CHECK=1 pytest charts/llama-swap/tests -k hf_repo_tags_resolve` => 1p
   WITHOUT docker, WITHOUT any venv, WITHOUT LLAMA_SWAP_EVIDENCE (decoupling proven).
4. Goldens `git diff` empty; no source file touched (git show scope audit);
   direct `hf_check.py` => 98 refs OK exit 0 (unchanged behavior).
5. 7quinquies ledger complete: every deletion mapped, zero-consumer greps recorded
   (incl. FLEET_IMAGE/docker_ready), dropped-vs-kept evidence-item diff attached;
   audit = retirements + re-homes only, NO silent weakening of kept scope (P1–P6,
   schema family/grammar tests, roster, CI-existing all byte-verified unchanged).
6. aislop 0 attributable on touched trees; TEST_SPEC digit fixes applied.

## Tests (agent-test writes, review runs)
This IS the test round. CC2 review re-runs the frozen bar (must remain
0f/119p/1s with the source removed) + criteria 3-4 + the residual sweep.

## Notes for dev
N/A — test-session round. CC2 starts only after CC1 lands APPROVED.

## Review notes (review agent fills)

### Round 1 — commit 0e7eafd36 (tests-only, 9 files) — verdict APPROVED

Bars + invariant (all re-run independently, helm v3.16.4 via /tmp/opencode/bin):
- `pytest charts/llama-swap/tests -v` => **0 failed / 119 passed / 1 skipped**, 120
  collected — EXACT against UNMODIFIED source (autogen confirmed still present:
  containers/llama-swap-autogen + configmap-autogen-base.yaml + 23 values hits at
  HEAD). Per-module recount: parity 34, schema 22 (20+2), roster 30, CI-existing 33
  (lora 3 + tools 20 + render 7 + prov 3), hf_liveness 1S. The single skip is the
  RUN_HF_CHECK gate — skip inventory 12 -> 1 verified.
- Arithmetic re-derived from the ACTUAL parent tree (detached worktree at
  f4bdcab6e, collect-only): 167 items = parity 34 + schema 20 + wiring 32 + image
  10 (6p/4s) + integration 8 (all gated) + roster 30 + CI 33 => 155p/12s.
  155 − 32 − 6 + 2 = 119 ✓; 12 − 4 − 8 + 1 = 1 ✓.
- `RUN_HF_CHECK=1 pytest -k hf_repo_tags_resolve` ALONE (no LLAMA_SWAP_EVIDENCE,
  no venv, docker-daemon-absent) => 1p in 2.35s — decoupling proven.
- Direct `hf_check.py` => "checking 98 -hf/-hfd refs ... OK", exit 0.
- Goldens byte-diff vs 49e977faf: EMPTY. helm lint + renders x3: pass.
- `git show --name-only` = 9 files, all under charts/llama-swap/tests/; tree diff
  parent->commit outside tests = zero lines. Kept scope byte-verified:
  parity/roster/CI files absent from diff entirely; schema +31/−0 (purely
  additive); testlib −62/0-ADDED (purely subtractive).

Retirement-ledger honesty:
- Deleted-case enumeration at parent: wiring 32 + image 10 + integration 8 = 50.
  Spot-audited 12+ across all three files (init pinned-image/security/mounts,
  main_env CONFIG_DIR, base_yaml macros-superset, degrade fail-open,
  drift_probe command-reintroduction, colon-free, entrypoint usage-error,
  dockerfile_exists, console-script x3, base_yaml_parses x2, scanned_half,
  c04_4 x2, c04_1 re-home) — every case maps to a 7quinquies entry and/or a
  §6 CR6-RETIRED/RE-HOMED trace line; wiring arithmetic in the ledger (30 retired
  + 2 re-homed = 32) ties exactly. `merged_declared_plus_scanned_validates` is
  §6-mapped (C03-4 trace) — see nit-3 for its 7quinquies-bullet gap.
- Reloader re-home (CA4 carry-forward): new schema guard preserves the original
  decision structure (rendered Deployment annotations only — the 7bis-K lesson
  verbatim in the docstring), x2 clusters, auto-annotation OR explicit match,
  BASE_CM leg deleted per ruling; failure message preserves cluster context.
  One wording regression -> nit-2.
- c04_4 retirement = user ruling exactly (supersession subsection + DECISIONS
  gate outcome; ledger says USER-RULED; §6 C04-4 line carries the pod-boot-is-
  proof rationale). ✓
- Colon-free retirement GENUINELY SUBSUMED: P1 asserts rendered-ID set == frozen
  CATALOG; measured 58/58 colon-free; any colon-bearing render ID would either
  miss a catalog member or appear unexpected => P1 red. The retired guard's
  collision invariant existed only under the (removed) two-file merge. No
  surviving hole.
- testlib prune re-verified: AST symbol-set diff parent vs HEAD = exactly 13
  removed (AUTOGEN_REPO/COMMIT/TARBALL_URL/IMAGE, FLEET_IMAGE, docker_ready,
  ENTRYPOINT_FILE, FIXTURES_DIR, pod_spec, container, init_container, env_map,
  mount_paths) — zero-consumer greps all clean (sole `container` hit is English
  prose in test_render.py:172; zero `L.<removed>` attribute refs).
  FAIL_STUB/OK_STUB/BASE_CM/_comment_only were wiring-file-locals (retired with
  the file, nothing to prune); `scanPaths` was never a testlib constant (only a
  kept docstring word) — planner wording approximated, ledger records measured
  reality honestly.
- tests/** grep posture: kept PY code has ZERO functional references to
  LLAMA_SWAP_EVIDENCE/FLEET_IMAGE/docker_ready/init_container/autogen — hits are
  provenance comments only (liveness header, schema re-home block), TEST_SPEC
  ledger lines, and evidence-yaml history notes = the allowed posture.
- Dev self-caught prune accident (_COMMENT_LINE eaten by range-cut, restored
  pre-commit): confirmed — _COMMENT_LINE present at HEAD, suite green; the
  ledger's "−70 lines" vs actual −62 is that restore.

Evidence yaml: item-level parent-vs-HEAD diff ties to the CR6 checklist:
dropped = [autogen-rebuild prereq, initContainer-state, entrypoint-degrade,
scanned-half-content, reloader-new-CM]; replaced by ONE declared-CM watch-config
hot-reload line (kubelet ~1min -> -watch-config in-place, reloader coarse
backstop, v262 keeps old config on bad reload — matches the plan's reload story);
reworded = merged-config -> POD-BOOT-IS-THE-FLEET-PROOF + operator -validate
demoted to runbook step, /v1/models + CR5 picker-vs-display-table check; ADDED =
CR6 pin-retirement runbook line. Kept-verbatim items byte-checked: PR/version
prereq, CA3 sweep prereq, ArgoCD health, echo spot, serve-smoke gate, q5/q6
set-less, REMOVED-13 + matrix-closure, machine-global 13+9, first-load +
uppercase-MTP + enlarged-picker + rollback. C05 readiness: good, modulo minor-1.

Findings:
- minor-1: evidence yaml gpu_ai_box item 1 expect still reads "startup merged
  load with 58 models" — verbatim-keep, but post-CR6 there is no merge surface;
  the mechanical OBSERVED-vs-EXPECTED diff at C05 can be confused by a log line
  that will never say "merged". Fix (test session, next touch): reword to
  "clean single-file config load with 58 models, ALL live".
- nit-2: re-homed reloader guard checks `"llama-swap-config" in match` (substring)
  where the original used `needed <= set(match.split(","))` (exact comma-token
  membership). A match of e.g. "llama-swap-config-backup" would now pass. Fix:
  `assert "llama-swap-config" in {m.strip() for m in match.split(",")}`.
  Non-blocking: the chart's actual path is auto=true; the match leg is the
  contingency branch.
- nit-3: 7quinquies integration bullet omits
  `test_c03_4_merged_declared_plus_scanned_validates` from its explicit list
  (covered by file-level retirement + §6 C03-4 trace). Fix: add it to the bullet
  on the next TEST_SPEC touch so the item-by-item enumeration is complete.
- CC2 handoff note: the CR6 residual-sweep grep ("autogen|LLAMA_SWAP_CONFIG_DIR|
  /app/gen|10-scanned" over charts/) WILL hit — measured exactly 4 files with
  ledger-style mentions only: test_hf_liveness.py header, test_config_schema.py
  re-home comment, evidence yaml (header + final runbook line), TEST_SPEC
  (§4/§6/7quinquies). llama_swap_testlib.py does NOT match the sweep patterns
  (its retained docstring word "CA4 args/scanPaths" is not a sweep token). CC2
  review must treat those 4 files' mentions as the allowed ledger-history
  exclusion; any OTHER hit is a real residual.
- Fresh-eyes quality: test_hf_liveness.py is clean (single RUN_HF_CHECK skipif,
  reason carries provenance + token caveat, test-time hf_check import keeps
  collection helm/network-free, body byte-faithful to the parent keeper minus
  the in-test skip). TEST_SPEC digit carry-fixes applied: 7quater 159->155 and
  7-D 17->16 both corrected WITH the miscount note; no stale bare 159/17
  remains. §4 re-baseline (12->1, bullets kept as history) and §6 retired/
  re-homed trace lines present with reasons. Stale /tmp vals artifacts: tests
  code has zero /tmp references — suite is path-independent, repo unaffected.
- aislop (dir-scope): 0 ERRORS; testlib warnings 11 (parent) -> 10 (HEAD), zero
  new attributable to CC1 (the diff is purely subtractive); liveness/schema
  files 0 findings.

Deviations by reviewer: none. Dev's declared deviation (c04_4 x2 retired per
user ruling superseding the planner keep-posture) verified against the ruling of
record — correctly executed and ledgered.

next_suggested: CC2 source removal against this green shrunk suite (bars: same
0f/119p/1s post-removal + declared-CM byte-equal x3 + pod-delta removals-only +
residual sweep with the enumerated ledger exclusions); fold minor-1/nit-2/nit-3
into the next test-session touch (hardening-bundle style, non-blocking).
