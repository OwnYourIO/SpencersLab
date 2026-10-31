# THIRD FINAL WHOLE-PLAN REVIEW — cf-86 (card #86), 2026-10-31

Range: `617e18488..9400951cb` (branch `cf-86-feat-more-strata-models` @ HEAD, tree clean —
`git status --porcelain` empty, verified this session). READ-ONLY run: zero git write ops,
writes only in this folder; scratch `/tmp/opencode/final3/` (removed at hand-back).
Card read live and read-only via `dev-boards.get_card` (#86 `Yb9sccTQ3wq2445ib`, still in
**Executing**, labels `Pipeline: Context` + `Pipeline: Local`, slug + session CFs set).

Precedent honored: the round-2 review session's commit/push incident — nothing here writes
git; the pushed tip `5a03cec40` remains an owner disposition.

## 1. Validation, all re-run this session (`PATH=$HOME/.local/bin:$PATH`, helm v3.16.4)

| run | measured | compared against | verdict |
|---|---|---|---|
| `helm lint charts/llama-swap` | 0 failed (1 INFO icon) | — | pass |
| default render (strata OFF) | rc 0, 1794 lines, zero strata strings | off-parity posture | pass |
| gpu-ai overlay render (plan Commands recipe) | rc 0, 2729 lines | — | pass |
| `pytest charts/llama-swap/tests -q` | **0F / 406P / 9S** | C09 landing record 406/9 | exact |
| same, `RUN_HF_CHECK=1 RUN_FLAG_AUDIT=1` | **0F / 415P / 0S** | C09 landing record 415/0 | exact |
| `pytest containers/strata/tests -q` | **24P** | "containers 24P" | exact |
| guards rulesync-surface / gate / agents-md / agent-perms / pipeline-models / validation-fix / coord-inwork | **19 / 22 / 9 / 15 / 6 / 8 / 7**, all rc 0 | the guard family | exact |
| `npx aislop ci --changes` (clean tree) | score **100**, 64 files, 0 errors / 0 warnings / 0 fixable | whole-ticket ledger posture | pass |
| `npx aislop ci --changes --base 617e18488` | identical (100 / 64 / 0 / 0) | `617e18488` **is** `git merge-base HEAD origin/main` | pass |
| `npx aislop ci --changes --base 5a03cec40` | also 100 / 64 / 0 / 0 | the tool resolves `--changes` against the main merge-base regardless of the flag (nit: post-commit, `--changes` == the whole ticket, not the working tree) | noted |

Skip posture, honestly: this env has `torch`/`transformers`/`safetensors` (so the three
`test_convert_lora` arms RUN) and lacks `websockets` (no arm depends on it unguarded). The
9 plain skips are exactly the evidence gates, named: `test_flashnext_regime:188`
(RUN_FLAG_AUDIT), `test_heretic_rungs_27b:237/272`, `test_heretic_rungs_flashnext:188/221`,
`test_hf_liveness:26`, `test_strata_c08_rung_shifts:349`,
`test_strata_c09_ornith_carry:389`, `test_strata_q4_rung:310`. The C09 review env's
403P/12S / 412P/3S is the same suite minus torch — no hidden red in either.
Armed posture is not decorative: it re-reads the live trees today, including the ornith
public-tree pin equality plus a ranged resolve of shard 2 (206 + GGUF magic, no Bearer),
the orcarouter IQ4_XS trio against the 97,473,155,200 Σ, and the unsloth UD-Q4_K_XL set.

Upstream re-probed today (API): latest release still **v0.2.9** (no 0.2.10); **#4460**
ornith **open**, 1 comment, housekeeping countdown ~2026-11-02; **#3574** closed
`not_planned` (2026-10-26); **#3678** open. So the shipped 0.2.9 pin is current and the
carry's re-watch triggers still describe reality.

## 2. U-registry closure U1–U11 (against the live card text, not the plan prose)

| # | ruling / ask | closure | authority + pointer |
|---|---|---|---|
| U1 | breadth-with-swaps, 3–6 min cold pins accepted | **DELIVERED** — one pod, five arenas as alternatives `(p \| s \| o \| q \| n)`, ttl 3600/180, no preload | DECISIONS "User rulings"; render verified this round |
| U2 | both ablated Strata rungs (SC117 + orcarouter) | **SUPERSEDED-BY-OWNER, half DELIVERED** — orca survives (now IQ4_XS, same frozen id); SC117 removed by U9.3; zero sweep residue re-verified | DECISIONS U9.3 + C08 round |
| U3 | Coder IQ1_M | **DECLINED** (draft chunk deleted, renumber map recorded) | plan renumber map |
| U4 | qwen3.6-35B-A3B on Strata | **DECLINED**, confirmed, no duplicate | DECISIONS Deferred |
| U5 | "served from Strata" (ornith) + `.opencode.jsonc` entries | **DELIVERED** — catalog half landed in C05; the Strata half now lands via C09 (U10.2), so the Shape-B absence-arm flipped to presence and stayed truthful in between | chunks/C05.md (e), C09 flip ledger |
| U6 | flash-next Q4 "should fit. Double check." | **CONFIRMED → DELIVERED** — `qwen3.8-flash-next-strata-q4` (UD-Q4_K_XL, 95232 + conv 8192 + slot-save-path) renders byte-stable through C08/C09 | DECISIONS R-b; q4 profile re-read this round |
| — | the card's parenthetical **"Lets make Q4 the default"** | **STILL OPEN — carry, not a regression** (see §3) | C05 round-3 note |
| U7 | slug kept | **DELIVERED** | card CF + folder name |
| U8 | conv-trim + session round-trip trade; disk gate "Enough free" | **DELIVERED** — conv 8192×16, `--slot-save-path /models/strata/sessions`, driver creates the dir; the HIP round-trip stays the human gate with the pre-registered UD-IQ4_XS fallback | DECISIONS U8/Round-3; C06 |
| U9.1–U9.5 | heretic stays llama.cpp / orca→IQ4_XS / SC117 removed / image lift + 0.2.8 / RW-C skipped | **ALL DELIVERED as ruled** (C07/C08), heretic and session-management as records | DECISIONS "Rework round 2" |
| U10.1 | "27b in strata … Llama.cpp IS NOT GOOD ENOUGH" | **ANSWER RECORD (NO-GO), ACCEPTED by U11** — re-grepped this round: no `qwen35`-dense door anywhere Strata-side (`charts/llama-swap/values.yaml`, `containers/strata/**` zero hits; `STRATA_DENSE_MMQ=1` is the q36 dense-*projection* MMQ knob on the ornith arm, not a 27B door; zero `27b…strata` ids) | DECISIONS revision-3 + RESEARCH R5 |
| U10.2 | "I also expect Ornith in STRATA" | **DELIVERED per the pre-recorded DONE≠PREFERRED semantics** — arena + profile + carry + GGUF-direct leg + trio 3/3 + catalog entry; the on-target A/B decides preference only, and neither outcome reopens C09 | DECISIONS "C09 DONE semantics pre-recorded"; chunks/C09.md AC8 |
| U11 | "Proceed C09, decline C11" | **HONORED** — C09 landed; C11 was never created (no chunk, no code, no placeholder) | DECISIONS U11; C11 absent from the chunk table |

Special scrutiny asked for, answered:
- **U6/U8/U9/U10 "Q4" chain:** the *model* chain closed (U6 → R-b → U8 pins → C06 → still
  renders). The *routing* half of the card sentence never landed — see §3.
- **U10.1 coherence:** zero dense/27B Strata-side doors anywhere (re-grepped; the only
  `dense` tokens in values are the llama.cpp 27B rungs' matrix comments + the q36 MMQ
  knob). The ORCA_Q4_K_S name-collision correction is recorded and C11 stayed a reserved
  id, not code.
- **U10.2 semantics:** C09 is DONE as shipped; the A/B is a human record line, and the
  landing commit message states "DONE != PREFERRED pre-recorded" where the operator reads it.

## 3. The one card instruction still unexecuted (re-verified today, still a carry)

`.rulesync/skills/pipeline-models/SKILL.md:31,49`, `pipeline-kickoff/SKILL.md:26`,
`boards/SKILL.md:121` all still route Flash+Local to `gpu-ai/qwen3.8-flash-next-strata`
(IQ3_S); zero `.rulesync/**` q4-route mentions in the range; `tests/pipeline-models/surface.sh`
M5 and `test_catalog_contract.py::test_c05_default_route_flip_not_applied_without_a_repin`
both GREEN ⇒ the absence guard proves the flip never landed **and** proves the suite still
pins the un-flipped route. This is the round-2 blind review's major-1; U9/U10/U11 never
touched it, so it is unchanged, recorded in STATE `routed_run_end` + `revision_final_round.carry`
as a user call — **carry, not a regression**. Closing it is one owner election
(target: `gpu-ai/qwen3.8-flash-next-strata-q4` or `gpu-ai/qwen3.8-flash-next-q4`) plus a
rulesync trio edit + `rulesync generate` + the test-session re-pin of
`tests/pipeline-models/surface.sh` and that catalog arm — never a silent route flip.

## 4. Cross-revision coherence (what per-chunk reviews cannot see)

- **Wave story:** the peers evidence chain reads end-to-end in one file: 2 (pre-cf-86) →
  3 (C01) → 4 (C02) → 5 (C06) → 4 (C08 sweep, the one sanctioned removal-only amendment) →
  5 (C09 "growth — no law amendment, the monotone chain holds"). My fresh render's
  `peers.strata.models` equals the final state exactly.
- **Era chains, recomputed byte-wise:** primary `strata-iq3_s.json` never moved an era
  (`a8de596c…` == era-1 fixture == today's render); strix chain
  `28d0ed38… → 547ba10d… → b0a35bcd…` with each era's latest link == today's render and
  each step's delta exactly {`exe`, `lib_dirs`}. Era-3 landed ATOMIC with the 0.1.55 flip
  in `9400951cb` (the round-1 BINDING held).
- **Secret posture:** one `hf-token` secretKeyRef, init-container only, UUID
  2ebdd082-… from `custom-values/gpu-ai/prod-values.yaml`; five profiles at
  `api_key: "none"`; inner `apiKeys: []`; no secret anywhere on the ornith leg (bytes
  proven public today); no secret string anywhere in the C09 diff. The bare extract-render
  still carries `OVERRIDE_VIA_CUSTOM_VALUES` in the ExternalSecret `remoteRef.key` —
  expected (the UUID arrives via the cluster-secret overlay), and worth knowing because the
  round-2 record says "no OVERRIDE_* sentinels observed" for that same recipe.
- **Trio / frozen ids:** all five Strata ids 3/3 (chart + service + catalog); the two
  llama.cpp rungs chart+catalog (peers n/a — correct); catalog 83 keys, every new id at
  262144, no phantom among them (the 24 unmatched `qwen3-vl-*:caption/:tags` entries are
  the pre-existing served matrix profiles); SC117 sweep zero hits outside sanctioned test
  homes; matrix letter `c` not reused; `n` quoted (YAML 1.1 boolean trap law).
- **Driver↔runbook seam (the between-chunks test):** the copy-once law re-seeds the PATCHED
  checkout on a deleted `$SRC` (correct), but the checkout-delete refresh line from the C07
  round is now the forbidden shape — the engine, the `.venv` `lib_dirs` every profile
  names, `Strata/data/expert-profile.bin` and the run configs all die with it and nothing
  recompiles, because `.setup-*` markers survive outside the checkout and the just-written
  marker satisfies the migration step. The refresh is C09's marker mismatch, automatic on
  first boot. Full write-up: chunks/C07.md + chunks/C09.md round 3.
- **Nothing phantomed, no scaffolding:** no TODO/FIXME anywhere in the C09 surfaces, no
  second patch file (the gate probes reject one), `carry/ornith-q36.patch` is exactly 2
  hunks each citing #3574 + the drop trigger. One scaffold-shaped string does remain —
  `values.yaml:1209` "# PIN-ME: brand-new container, no :v<run> exists yet" — which is the
  pre-existing recorded chores item (the "PIN-ME 1209-vs-1160" note in the carry list),
  ruled settled as a Renovate-owned decision, not new scaffolding and not a hand-bump.

## 5. FRICTION re-status + the final carry list

Open FRICTION items (9), all still open, all already routed — nothing new surfaced in
waves 7–9: cf-78 stale reference (chores); NVMe throughput unmeasured (on-target record);
dev-boards `list_comments` empty-text projection (chores); pipeline-locks heartbeat vs
multi-hour subagent chains (engine card); `set(<dict>)` vacuous-law, SETUP_KEYS-before-
flag-arms, read-every-failure-message, baseline-proof triple (agents-sync convention
promotions); dev-boards MCP vanishing post-restart and mid-flight subagent deaths (infra
churn — both actually bit this ticket's history and cost real rounds).

**STATE bookkeeping (coord-only, hygiene):** `current_wave: 4` predates waves 7–9 (nine
chunks, all `done`); `revision_round_3_2026_10_31.plan_status_gate` still reads "stays
needs-replan" although U11 resolved it and `plan_status: approved`; `run_state.status:
"completed"` predates both revision rounds. Chunk records themselves are current (C01–C09
done, verdicts and round counts correct). Worth one STATE edit in the closing commit so the
machine state matches the plan of record.

Deferred / carry, final shape:
- **On-target human gates:** migration-marker boot proof; `--families`; `serve --plan` per
  all five profiles; the q4 HIP session round-trip (fallback pre-registered); orca
  `iq_pack --compat-bf16` fidelity + 3-shard PLE placement; ornith cap/slot finalization;
  `df` before/after each new token; the ornith decode A/B (llama.cpp rung unloaded).
- **Owner elections:** Q4-default routing (§3); 27B-orca-at-Q4-class (blind review minor-1,
  upstream publishes Q4_K_M/Q4_K_S/IQ4_XS ungated); llama.cpp-ornith retirement (only if
  the A/B says faster); C11 stays declined unless re-elected; strix catalog entry; 10
  pre-existing unroutable rungs; machine-local gpu-moe catalog cleanup; disposition of the
  pushed tip `5a03cec40`.
- **Chores:** descBase 180B-vs-177B/125B + KLD phrasing; cf-78; PIN-ME 1209-vs-1160;
  PROVENANCE line-count nits; RESEARCH [S7] byte total (111,334,654,784).
- **Re-watch:** #4460 housekeeping auto-close ~2026-11-02 → cite as housekeeping-not-
  rejection, keep the trigger on #3574's "we want to add it later"; drop
  `carry/ornith-q36.patch` the moment upstream ships first-class; #3678 (q36 quantized KV)
  is the ornith rung's biggest lever (fp32 KV ≈13.1 GiB @262K); #3925/#3926 bind only if
  the ladder moves off unsloth UD-Q4_K_XL / if DENSE_MMQ defaulting lands.

## 6. Verdict

**CHANGES_REQUESTED** — nothing shipped is wrong; three record/docs defects must be closed
before the ticket hands to Review, and none reopens a chunk, touches code, or touches a
validation:

1. **MAJOR (operator-safety, coord-only):** retire the C07-era "delete the checkout"
   refresh instruction (plan Commands C07 bullet + DECISIONS entry annotated superseded;
   one prohibition line in the host-prep note) and use the corrected sequence in §7 on the
   card. Proof: chunks/C07.md / chunks/C09.md round 3.
2. **MAJOR (docs-truth, mechanical):** `charts/llama-swap/README.md` L75/76/L148 →
   0.1.55 (the shipped image has no 0.1.54 packaged roots); test-session widens
   `test_c07_engine_package_labels_are_one_fact_across_three_surfaces` to that fourth
   surface so the next bump cannot drift.
3. **MAJOR-bundle (docs, one follow-up round like the 2026-10-31 one):** the runbook +
   chart README still describe the two/three-arena world — host-prep L257, §3.4 (2 of 5
   `--plan` runs), §3.8 `(p | s)`, §4 arena/caps framing + the missing ornith row + the
   unnamed llama.cpp-ornith × strata-ornith collision; chart README L115–120 (2-row inner
   table, "(p | s) … the two alternatives"). Plus the C08 record notes (peers-header
   "four served ids") and the per-env posture ledger line, test-session property.

Everything else: APPROVED-grade — the shipped surface is render-verified, zero-red in both
postures, chain-clean across eras, secret-clean, and every U-ruling is visible in the
state or in an explicit answer record.

## 7. CONSOLIDATED OPERATOR SEQUENCE (the card hand-off text, as derived from all carried
runbook lines with the §4 seam corrected — every step human/on-target, never an agent
command)

1. **Landing window (C07's one-commit law).** Merge once PR `docker-build` is green (it is
   the only pre-merge proof of the carry: CI never compiles HIP, the verify layer's
   `git apply --check --reverse` + the two constant greps are the evidence). The push of
   `ghcr.io/ownyourio/strata:main` (0.2.9 flavor tags + patched checkout + baked driver)
   must precede the ArgoCD sync of `gpu-ai-llama-swap-strata`, or hold the sync until it
   lands. If a sync beats the image, the exec-form init guard fails container START loudly
   with zero script executed and markers untouched, and `pullPolicy: Always` + restart
   backoff self-heal once the image is there.
2. **First boot = the claim refresh; do nothing but watch the init log.** The live claim has
   no `.checkout-0.2.9-carry1` marker, so the driver syncs sources image→claim (source-only
   list), wipes `build-hip`, recompiles the engine (10–20 min ninja inside the init's
   32 Gi), installs `Strata/engine/strata`, and writes the marker only after a green
   compile. That single step is what lands the patched, 0.1.55-era engine on the primary
   path (the 0.2.9 decode/prompt win needs no other action).
   **Never delete `/models/strata/Strata`.** The engine binary, the `.venv` ROCm
   `lib_dirs` that every profile names, `Strata/data/expert-profile.bin` and the
   `strata-*.json` run configs live inside that checkout, while the `.setup-*`/`.pack-*`/
   `.dl-*` markers live outside it — so after a deletion the driver re-copies the checkout
   but nothing recompiles, and every claim-compiled arena fails at serve time. A failed
   recompile is loud and re-entrant (marker unwritten; the strata pod stays down); the
   escape is a revert commit → `:main` rebuild → the sync re-runs from the older image.
   Never "fix" it with `rm -rf`.
3. **Claim cleanup — only if the claim already ran a pre-C08 boot.** `.pack-orca` FIRST
   (the marker is tier-independent: with an IQ3_XXS pack on disk the driver prints "orca
   pack complete, skipping" and never stages the IQ4_XS trio the profile now points at),
   then `/models/strata/.setup-ABL`, then the swept SC117 + old-IQ3_XXS-orca dirs
   (~161 GB back, against +97.47 GB of new orca shards plus its own `iq_pack` copy).
4. **Disk gates:** `df -h /models/strata` before and after each first token run — orca
   +97.47 GB, q4 +111.33 GB set plus its pack, ornith +79.7 GB; session files land in
   `/models/strata/sessions` at ~4.7 GiB per full 262k conversation.
5. **Provisioning is already declared** (`STRATA_QUANTS=q3,orca,q4,orn`). The ornith leg is
   GGUF-direct, anonymous, ungated, no pack step — if unsloth ever gates, the live suite
   arm reddens and the token question comes back through coord, never as a silent gated
   edit.
6. **`strata --families` on the claim engine** must print both families
   (`qwen4exp qwen35moe`) — proof the patched checkout compiled.
7. **`serve --plan` per profile — all five, not two:** primary (`--expert-cache auto`
   resolution + conv 32768×16 against real RAM); strix (the `24576` / `55 GiB` hypothesis
   pair); orca (3-shard PLE placement + the first IQ4_XS `iq_pack --compat-bf16` fidelity
   read — a BF16 surprise is a one-line iq_pack flip + pack rebuild as a follow-up
   commit); q4 (PLE-mmap pin + the **first HIP session save/restore round-trip** — its
   failure triggers the pre-registered UD-IQ4_XS conv-32 / 108Gi / 102400 fallback, decided
   by the operator, never by a dev); ornith (memory cap + `--expert-slots/--expert-vram`
   finalize here — R5 sizes ~10–14 GiB / 300–400 slots; nothing is guessed in the repo).
   Deltas land as `charts/llama-swap/values.yaml` edits, re-PR, re-sync.
8. **Unload + keyless proofs (unchanged):** one real pin, then
   `POST /api/models/unload/<id>` must drain inside the 180 s window (grace 420 > 180 + 30
   stays an invariant), and an unauthenticated chat must complete — five profiles at
   `api_key: "none"`, inner `apiKeys: []`, the only credential in the pod being the
   init-only `hf-token` for the orca download leg.
9. **Ornith decode A/B, outcomes pre-recorded:** compare `ornith-1.5-122b-strata-q4`
   against the llama.cpp `ornith-1.5-122b-q4` with that llama.cpp rung **unloaded** during
   the run (both are large; peers are invisible to the outer solver, so this is operator
   discipline). Faster → llama.cpp-ornith retirement is a separate later owner election.
   Slower or parity → present-but-not-preferred stands; that is an accepted outcome, not a
   failure.
10. **RAM law for the five arenas:** `(p | s | o | q | n)` are alternatives, never
    co-loadable; the q4 arena (71.7 GiB pinned) is the biggest, ornith (~40–48 GiB) the
    second; no Strata request while a large llama.cpp model is mid-session, and never
    preload.
11. **Still-open owner decisions after landing:** "make Q4 the default" at the routing
    layer (the card's only imperative — untouched, all three routing surfaces still default
    to IQ3_S and the suite pins that until an election + re-pin); 27B-orca at Q4-class;
    llama.cpp-ornith retirement (if step 9 says faster); strix catalog entry; 10
    pre-existing unroutable rungs; the machine-local gpu-moe catalog cleanup; and the
    disposition of the pushed branch tip `5a03cec40`.
12. **Re-watch:** upstream is at v0.2.9 (re-checked today); #4460 open with a housekeeping
    auto-close countdown ~2026-11-02 — if it closes, that is housekeeping, not rejection,
    and the trigger stays on #3574's "we want to add it later"; drop
    `containers/strata/carry/ornith-q36.patch` the moment upstream ships the support
    first-class. #3678 (q36 quantized KV) is this rung's biggest future lever.
