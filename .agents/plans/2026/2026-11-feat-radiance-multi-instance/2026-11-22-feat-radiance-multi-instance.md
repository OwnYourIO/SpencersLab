# PLAN: Radiance multi-instance — radiance-default routing, pool rename, generic 4-lane shell
feature: 2026/2026-11-feat-radiance-multi-instance

Drafted 2026-11-22 by `agent-plan` (re-launched planning session — the coordinator's ruling after
the double-launch: this set is the folded shape, the superseded 4-chunk sibling draft is preserved
verbatim in `PARALLEL-DRAFT.md`, FRICTION rows record the collision) from the owner's in-session
five-piece ask (verbatim intent in STATE kickoff), grounded in EXPLORE.md (scout, live ai-gpu
reads 2026-11-21 ~23:05–00:0xZ) and RESEARCH.md (storm round 2026-11-22, R-Q1..R-Q6 +
contradiction map C1–C7), plus the cf-143 DECISIONS (D7/D8/D15/D17/D21/D24/D26/D27/D29/D30,
B1-shield + carrier laws) and the cf-144 DECISIONS (P02/P05/P11/P15 laws this ticket TRANSCRIBES,
never re-decides). Base: branch `feat-radiance-multi-instance` at main `193c12798` — **cf-144 is
already landed and is the BASE, not a prerequisite** (EXPLORE §0; the launch brief's "unpushed"
framing is stale — FRICTION row). **`plan_status: approved`** — the owner ruled "Approve — run all
waves" at the batched round and the coordinator flipped it; mid-execution folds keep it approved.
**Rework round 2026-11-22: the batched question round RAN and every answer is folded here**
(the answers were delivered against the sibling draft's lettering — the authoritative letter map is
DECISIONS D15; letters below are THIS plan's, now recorded as ANSWERED verdicts).
**Post-approval fold round 2 (2026-11-22): owner ruling D35 resolves the C03 fork — the CHART owns
the generic init-script FORM via a configMap/env carrier, AC1's byte-equivalence is REPLACED by the
four-path intentional-delta proof, and C03's rework becomes its OWN watched sync set — folded
together with three review-owed corrections (noop baselines, the write-arm "not run, no claim"
line, the relocation intermediate-pass law, and C06's D32 scope).** OQ-K stands as C04's embedded
STOP-condition contract (the re-anchored same-wave `replicas: 0` designed-red leg per D31 is the
executable shape of K1).

## Goal
Route every coord/subagent model surface to `gpu-ai/qwen3.8-flash-next-radiance`, rename the GPU
pool `amd.com/gpu-r9700-1` → `amd.com/gpu-r9700` in one atomic wave, and restructure
`charts/radiance` into a generic mechanism shell deployed 4× (flash-TP2, flash-TP1, 27b-TP2,
27b-TP1) with per-instance data in the service roster blocks and only flash-TP2 at `replicas: 1`.
Determinism ships in TWO legs (owner ruling 2026-11-22, OQ-B answer (b)): llama-swap/strata gets a
REAL `amd.com/gpu-r9700` claim — scheduling-level exclusivity + lowest-KFD-NodeId allocation order —
while its hostPath/privileged runtime posture and the dated-receipt ordinal discipline stay; the
claim parks strata at `replicas: 0` beside the other resting lanes (OQ-K). Per-lane SPECIFIC-CARD
pinning through the device-plugin path remains structurally impossible (RESEARCH R-Q1/R-Q4) and any
prose claiming otherwise is an error, not a ruling.

## Out of scope
- Re-deciding cf-144 sizing law: fn memory stays the HELD 110 (P11) — the post-boot DOWN re-pin
  remains an owner-receipt leg OUTSIDE this ticket; this plan transcribes the number as lane DATA.
- DRA adoption (R-Q3: watch-list — revisit triggers recorded in DECISIONS, zero chart work).
- Grafana dashboards (cf-143 follow-up card #2 owns them), the gpu-cluster product-naming
  extension (cf-144 C04, deferred to its own card), strata's on-target [VERIFY] legs, any live
  host mutation.
- WeKan board-vocabulary changes: the card Model(s) CHECKLIST option strings name the old route
  ids; provisioning (`scripts/provision-board.py` / board MCP) is an OWNER follow-on, never an
  in-ticket board write (the boards SKILL mapping moves; the vocabulary does not — sibling-draft
  ruling kept).
- Any chart version bump (release.yaml owns), any sync or push (owner legs, see Landing shape).
- Editing cf-143/cf-144 plan folders — other tickets' records are append-only to THEIR owners;
  supersession is recorded in THIS folder's DECISIONS with pointers (ask 5's "annotate never
  rewrite" handling).

## Verified facts (plan-session re-reads at HEAD `193c12798`; full inventory in EXPLORE/RESEARCH)
1. **fn lane is LIVE 1/1** (Deployment `gpu-ai-radiance`, pod args = the 34-item TP2 set,
   `/health:8000` readiness) — EXPLORE §1; so routing the defaults to
   `qwen3.8-flash-next-radiance` works today. **q27 rests at 0 → its peer hop answers 502 and must
   stay non-default** (EXPLORE §1, `.opencode/opencode.jsonc:758-761` measurement-conditional).
2. **This run already launched every subagent on `gpu-ai/qwen3.8-flash-next-radiance`** per the
   owner's word — the shipped rule must match that (launch brief; recorded in kickoff).
3. **Pool name derivation is machine-verified**: `charts/amd-gpu/tests/amd_gpu_testlib.py` carries
   a faithful sanitizer PORT (`sanitize_product`, :181-202 — the derivation engine the table legs
   run) and re-reads confirm: `sanitize('r9700') == 'gpu-r9700'` (the target IS reachable by the
   mechanism — set the 7551/C0 product field to exactly `r9700`), while `sanitize('AMD Radeon AI
   PRO R9700') == 'gpu-ai-pro-r9700'` (fillers {amd, ati, instinct, radeon, graphics, series}
   drop, `pro`/`rx` KEPT — the marketing string CANNOT yield `gpu-r9700`; settled by the round,
   D21). `amd.com/`
   + `gpu-` are code constants (EXPLORE §2a). Table read ONCE at startup (R-Q5); APU 1586 rows
   carry VERBATIM (cf-143 D24 law, evidence fixture `pre-c08-amdgpu-ids-rows.txt`).
4. **One-wave law** (R-Q5 + EXPLORE §2b): old name → capacity 0 PERMANENTLY on rename; running
   pods keep injected devices; any pod spec still carrying `gpu-r9700-1` PENDINGs forever; bare
   `amd.com/gpu` sits at 0 — no fallback. Claims + ids-table ship in ONE commit / one sync set.
   The stale "each pool holds one device" prose (RESEARCH C1) rides the wave — re-read at
   `charts/radiance/values.yaml` ~:157 and `templates/NOTES.txt:25` ("exactly one device").
5. **Prefix hazard**: `gpu-r9700` is a substring of `gpu-r9700-1`. AC4's sweep uses Python `in` —
   one surviving `-1` occurrence trips BOTH legs (zero-stale + placement). The new historical
   constant stays ASSEMBLED (`"gpu-r9700" + "-1"`); bash needles anchor the trailing boundary
   (e.g. `r9700([^0-9-]|$)`) so a straggler never false-greens (R-Q5, EXPLORE gotcha 6,
   sibling-draft pattern kept).
6. **Name needles have ONE edit site per language** (`amd_gpu_testlib.py:44-62` re-read incl. the
   `HISTORICAL` assembly; bash twins `tests/services/amd-gpu-naming.sh:66-73`,
   `tests/notes/radiance-{runbook,tp2}.sh` marked blocks); cross-chart consumers resolve the
   module (EXPLORE §2c). Blast radius measured: `git grep -c "r9700-1" -- ':!.agents/plans'` =
   19 files — live claims (`charts/radiance/values.yaml:348-353`, q27 overlay
   `services/gpu-ai/prod/values.yaml:992/:995`), prose lines (`:50/:852/:878/:896`,
   `charts/llama-swap/values.yaml:1352` comment-only), ledger/test sites,
   `charts/llama-swap/tests/TEST_SPEC.md:3762` (history prose — test-record class, re-pin with a
   dated footnote by the test wave), and 26-27 note lines across 4 docs.
7. **AC4 zero-stale scans `charts/ services/ tests/ .agents/notes/`** — NOT `.agents/plans/`
   (re-read `test_provenance.py:369-434` + teeth probe). Precedent cf-143 D24 ("TP2 doc pool strings"
   moved): the rename wave sweeps the notes' name TOKENS in place; narrative stays
   annotate-never-rewrite; old-name history lives in plan folders/git, outside the scan.
8. **n3's R9700 claim leg is VACUOUS against the shipped quoted shape** (plan-session probe:
   `claim_grep` pattern `[0-9]+$` does not match `: "2"`/`: "1"` — NO-MATCH verified). The test
   wave must sharpen the needle while re-authoring it for the carrier relocation (FRICTION row).
9. **Four releases on one chart is pure values**: the roster `chart:` lever already yields
   `gpu-ai-radiance` + `gpu-ai-radiance-q27` from `charts/radiance` (live Applications, EXPLORE
   §4a; lever re-read at `charts/base/templates/appset-charts.yaml:67-70` — the `:85` comment cite
   is stale, gotcha 13). Per-app values ride `values: merge $extraValues (index $.Values $appName)`
   (re-read :36); app-template list-merge = whole-list REPLACEMENT (the q27 precedent proves the
   mechanism). No base-chart bump.
10. **Claim math (2-card node)** (EXPLORE §4b): fn TP2 claims both ⇒ at most one TP2-class lane
    UP; the other three render `replicas: 0` (owner's ask), idle hop = loud 502. RAM note: at
    transcribed values the two TP1 lanes CANNOT co-boot (110 + 24 + ~5.3 > 125.08) — documented in
    NOTES, never silently mitigated.
11. **Strata's landed shape (re-read this round, post-answers)**: the strata container is claim-less
    with `privileged: true` + hostPath `/dev/kfd`+`/dev/dri` (standing 2026-10-27 ruling — now
    superseded in its NO-CLAIM half by owner ruling D17) and renders `replicas: 1` today (evidence
    `charts/llama-swap/tests/evidence/cf143-pre-ticket-strata/gpu-ai.strata-docs.yaml:44`); its
    selection is `rocrVisibleDevices: "0"` + `rocrVisibleDevicesByModel` (strix `"2"`, P15 rocminfo
    receipt). The gpu-ai overlay ALREADY ADDs `amd.com/gpu-8060s: 1` + requests mirror on the
    llama-swap MAIN container (`services/gpu-ai/prod/values.yaml:200-205`, cf-143 C07/C10 — the
    carrier-shape precedent strata's new claim clones). `charts/llama-swap/values.yaml:1352-1360`
    pre-legislates the post-D17 posture verbatim: "Strata keeps this privileged hostPath shape
    either way: per-name pools settle cross-card choice, never VRAM arbitration … hostPath sits
    outside plugin accounting entirely". R-Q2 stays: `ROCR_VISIBLE_DEVICES` accepts `GPU-<16hex>`
    UUID prefixes (≥6.3) with SILENT-TRUNCATION failure; the UUID pin is gated on the owner's
    promised OQ-R1 paste — never blind.
12. **Routing-site coupling (Leg B now MANDATORY per D16)**: `tests/pipeline-models/surface.sh`
    M1/M2/M5 pins the defaults; M8-F KEEP needles (`:1013,:1030,:1037`) REQUIRE strata-q4 as a
    present route string — C02 re-authors them to "present as the documented alternate route".
    M8-H (`CF143_BASE_SHA` diff inventory, `:1059-1064`) FAILS on touching
    `.rulesync/rules/overview.md` or `.agents/loops/pipeline-worker.md` ⇒ re-authored into the
    pairing leg the owner's answer names. Runner-literal byte sites measured this round:
    `.agents/loops/pipeline-worker.md:5`+`:11`, `tests/provider-loops/surface.sh` t1 (`:182-184`)
    and t3 (`:220-225`) + `tests/agent-board-coord/agents-md.sh` c11 (`:588`) pin the STALE
    `gpu-ai/qwen3.8-27b-q4` (pre-existing REDs — they drifted two rulings behind), while
    `tests/opencode/pipeline-locks-tick.test.ts:163` is GREEN pinning `strata-q4` (the tsx tick).
    All four re-pin to the RADIANCE literal with the full ruling chain (D23); leaving any red is
    not an option.
13. **Serving-a-new-id is a three-surface join, in order** (EXPLORE §4c): test-authored evidence
    YAML (`models_states` APPEND-ONLY, dev-must-not-edit) → `config.peers` entry (proxy =
    `http://<Application-name>.default.svc.cluster.local:8000`, no `/v1`, `setParams "priority?"`
    floor, id OUT of the outer models/matrix) → catalog row(s) + pipeline-models tables (+ M8
    frozen-delta re-author). CI: `test_contract.py::test_ac6` pins the workflow TRIGGER PATHS
    exactly — add STEPS, never paths (gotcha 12); new lane coverage lives inside
    `charts/radiance/tests/` (a `tests/` sibling dir would fire NO workflow — sibling finding kept).
14. **Carrier law (cf-143 D26)**: overlays ADD/UPDATE positive claims, never REMOVE (nulls die in the
    appset→Application chain; `0` illegal). q27's overlay claim-1 pin against the chart's 2 is the
    sanctioned precedent — the restructure's per-release claim blocks live by it.
15. **No secret surface** (keyless cf-143 D8): no `bitwardenIds`, no ExternalSecret, no `custom-values/`
    leg — "generic shell + exact settings per instance" lands in the SERVICE roster blocks (the
    appset `index $.Values $appName` channel), and `OVERRIDE_VIA_CUSTOM_VALUES` keeps its repo
    meaning: secrets-only carrier. cf-144's "one chart-value home" (D15 single-source scalars) is
    DELIBERATELY superseded for this chart by ask 4 — recorded D-series, prose reconciled at C06.

## Commands (validation battery — every session exports PATH first)
`export PATH=$HOME/.local/bin:$PATH` (without it helm-guarded pytest silently mass-skips);
`helm dependency build/update` FIRST in any fresh worktree (the gitignored `.tgz` trap — FRICTION).
Baseline measured by the scout at HEAD (EXPLORE §6), corrected post-C01/C02 where re-measured:
radiance 70P/1S · amd-gpu 29P · llama-swap 507P/9S · vllm 36P · naming.sh PASS · surface
M1–M5,M7,M8 PASS (9 ok) · notes suites 5/3/6 PASS · **cf106-noop 11 ok · noop-marker 11 ok** (both
measure 11 ok on suite files byte-identical to scout HEAD — the scout-era 8/9 expectations were
stale; a stale expected number turns an honest green into a false finding) ·
**provider-loops RED t1 (pre-existing)** · **agents-md c11 RED (pre-existing)** · tsx tick 15 pass.
- chart suites per-directory (basenames duplicate): `python3 -m pytest charts/{radiance,amd-gpu,llama-swap,vllm}/tests -q`
- contracts: `bash tests/services/amd-gpu-naming.sh` (review sets `AMD_GPU_FLIP_COMMIT` for n2) ·
  `bash tests/pipeline-models/surface.sh M1 M2 M3 M4 M5 M7 M8` (M8 named explicitly; final review
  also runs M8 with `CF143_BASE_SHA` = the merge-base) ·
  `bash tests/notes/radiance-{runbook,tp2,q27-boot,host-tuning}.sh` ·
  `bash tests/{cf106-noop,noop-marker}/surface.sh` · `bash tests/provider-loops/surface.sh` ·
  `bash tests/agent-board-coord/agents-md.sh c11` ·
  `npx --yes tsx --test tests/opencode/pipeline-locks-tick.test.ts`
- **Standing WRITE-arm rule (D33(c), D34-scope):** the WRITE arms — `pipeline-models M6`,
  `agents-md c1`, `rulesync-surface c7`, `gate t14` — are **not run, no claim** in any read-only
  session; they belong to writer sessions and no expected-status list handed to a reviewer or test
  session may list them as expected-green.
- regenerate (writer sessions only, C02/C05): `npx --yes rulesync@37.0.0 generate` then
  `generate --check`; run twice — the second generate must be a no-op; sources + generated twins
  commit together.
- renders: `helm lint charts/radiance` · `helm template radiance charts/radiance --set
  domain=spencerslab.com --set clusterName=gpu-ai` · per-release extraction legs per
  `.github/workflows/radiance-render-tests.yaml:57-77` idiom (`d.get(key) or {}`) · every
  CLAIM-shape assertion (radiance lanes and C04's strata claim alike) goes through the
  appset-projection layer `charts/llama-swap/tests/llama_swap_testlib.py::project_valuesobject`
  (cf-143 D26: helm-only claims prove a shape the cluster never renders).
- rename sweeps (word-boundary-safe): `grep -rn "gpu-r9700-1" charts services tests .agents/notes`
  → ZERO after C01 (plans folder exempt by design); new-name placement via
  `grep -rnE 'amd\.com/gpu-r9700([^-]|$)'`; impossible-string bars: `amd.com/r9700` /
  `amd.com/r9700-1` appear nowhere claim-shaped (tests assemble them).
- equivalence proofs: **C03 INTENTIONAL-DELTA proof (D35 — replaces the old EMPTY-diff law, which
  the owner ruled relaxed for this one carrier):** per existing lane, the post-move rendered
  Deployment may differ from the pre-move fixture on EXACTLY four paths —
  `metadata.annotations."checksum/configMaps"`, `spec.volumes`, the init container's
  `volumes`+`volumeMounts`, and its `command` — and NOTHING ELSE (serve args, claim pair, memory,
  replicas, probes, securityContext, image@digest stay byte-equal). The fixtures remain the
  comparison baseline and `charts/radiance/tests/capture_c03_fixtures.py` remains the
  re-derivation tool; the budget leg needs teeth (a planted unauthorized-path diff must redden
  it). "The script is in the chart" is NOT the gate — the bounded diff IS.
  C05 four-lane render battery (args equality per lane, claims {fn:"2", q27:"1", flash-tp1:"1",
  q27-tp2:"2"}, replicas {1,0,0,0}, served-model-name uniqueness across the four).
- **Relocation-chunk law (D30 corollary, review-owed):** any chunk that MOVES a data home (C03)
  runs its wave order **dev → TEST RE-PIN PASS → review** — a dev tier never edits `tests/**`
  (D30), and the relocated-carrier legs are structurally red for dev until the test session
  re-pins them (measured on C03 round 1: 19 legs across 12 sites bound the old carriers). The
  relocation list must be DERIVED by grepping the OLD carrier homes (chart values serveArgs /
  modelPath / pack literals, the q27 overlay `command:`, carrier constants, extractor anchors,
  CI extraction steps), never recalled.
- quality: `npx --yes aislop@0.20.0 ci --changes` must clear the gate on every chunk.

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Pool rename `gpu-r9700-1`→`gpu-r9700`, ONE atomic wave — ids-table row (product field exactly `r9700`, marketing identity in the ledger comment per D21) + all claims + both guard sweeps + notes token sweep + C1 comment fix | L | 1 | [] | the table and every claim must flip together (R-Q5: old name PENDINGs forever; split wave = stranded pods) |
| C02 | Routing surface → radiance every tier — pipeline-models/kickoff/boards re-author (incl. the D20 Dense+Local move to `qwen3.8-27b-radiance`) + **runner literal MOVES (Leg B mandatory per D16: loop md + overview.md/AGENTS.md + t1/t3 + c11 + tsx tick `:163` + M8-H pairing-leg re-author)** + pre-existing reds cleared + rulesync regenerate | L | 1 | [] | independent of C01 (zero file overlap: `.rulesync`/`.opencode`/`.agents/loops`/`tests/{pipeline-models,provider-loops,agent-board-coord,opencode}`); id-order run keeps the rename's atomic sync story clean |
| C03 | Generic shell — charts/radiance becomes mechanism-only; fn-TP2 + q27-TP1 lane data transcribed into per-release service blocks; chart owns the generic init-script FORM via a configMap/env carrier (D35); **INTENTIONAL-DELTA proof (four-path budget) replacing AC1 byte-equivalence**; testlib/CI/n3 carrier relocation via the dev → test re-pin → review pass | L | 2 | [C01] | the transcribed claim lines must carry the FINAL pool name (data dependency) and the n3/AC4 re-author edits the constants C01 just moved (fixture dependency) |
| C04 | **Strata REAL CLAIM (OQ-B(b), owner ruling D17)** — gpu-ai overlay positive-ADD `amd.com/gpu-r9700: 1` (+ requests mirror) on the strata container, hostPath/privileged/rocr posture KEPT (b1), `replicas: 0` in the same commit (OQ-K), corrected determinism prose (scheduler-vs-container legs), updated steady-state claim table incl. strata, OQ-R1 receipt leg + gated UUID arm, DRA revisit record | M | 2 | [C01] | the claim line must carry the FINAL pool name (data dependency); otherwise independent of C03 (different chart, different blocks — same service file, id order when both ready) |
| C05 | Four-lane roster — add resting `radiance-flash-tp1` + `radiance-q27-tp2` releases: per-lane served ids + three-surface join with **FULL CATALOG TRIOS now (D19)** (evidence → peers → 6 catalog rows + M8 frozen-delta widened) + lane profiles + per-lane test files + CI steps | L | 3 | [C01, C02, C03, C04] | C01: claim names; C03: the shell + relocated carriers these blocks feed (interface); C02: surface.sh M8 + the pipeline-models tables are re-authored once on a stable base (byte-pin conflict); **C04: same service file, the overlay-claim wave lands first (D25)** |
| C06 | Notes & docs layer — dated annotate-never-rewrite pass: four-lane switch discipline + the strata-parked MoE bring-up runbook (fn→0 → strata→1), supersession pointers for cf-143/cf-144 prose, "one chart-value home" prose reconciliation, **the D32 trio: the false `charts/amd-gpu/values.yaml:30` "one device each" header correction, the cf-143-vs-cf-radiance `D21`/`D24` citation-prefix pass, the optional `32 GB dGPU` ledger tag** | S | 4 | [C01, C02, C03, C04, C05] | the annotations quote the SHIPPED shape (markers + needles re-pin in the same commit as the prose they govern — cf-144 C02 precedent); the D32 trio rides last because the header truth and the citation state are only final once the waves landed |

## Wave order
1. **C01** (rename — the ticket's keystone), **C02** (routing — independent, run in id order).
2. **C03** (shell), **C04** (strata real-claim + receipts; the owner's OQ-R1 paste arrives at this
   chunk's turn — the UUID arm is live but gated on it, D22).
3. **C05** (four-lane add).
4. **C06** (notes layer).
Scout hint VALIDATED with reasons (the sibling draft's routing-first ordering was considered and
set aside — same-file safety wins over cosmetic ordering; both plans agree the fleet wave must
follow both): rename first because everything downstream quotes the final name and its sync is the
one atomic set (a routing commit landing after the rename can never be part of that set anyway);
routing next (zero GPU-file overlap, own review window, clears the pre-existing reds early);
restructure last (its lanes depend on the final pool name, the relocated claim carrier, AND a
settled surface.sh/M8 base). The two pre-existing reds ride the ROUTING wave either way (their
subject is the runner literal — same semantic surface; both plans agree).

## Transcribed vs superseded (ask 5)
| Today (cf-144 shape on main) | After this ticket |
|---|---|
| `charts/radiance/values.yaml` serveArgs anchor = the 34-item TP2 array | TRANSCRIBED verbatim into the `radiance:` (flash-TP2) service block; the chart ships NO lane args (OQ-D) |
| fn claim pair `gpu-r9700-1: "2"` / 110Gi | MOVED to the block, name RENAMED (`gpu-r9700`), count/memory HELD (P11 law survives as DATA) |
| q27 overlay: whole-array args + init `command` script replacement + claim-1 pin | args + ledger fields TRANSCRIBED; the whole-SCRIPT replacement SUPERSEDED by parameterized init (PACK/LFS_SHA/URL/MARKER as per-release scalars; cf-143 D27 grammar + image-identity legs survive). **MECHANISM FIXED by D35:** app-template 5.0.1 renders container `command`/`args` via plain `toYaml` with NO `tpl` (only `_name`/`_env`/`_probes`/`_volumeMounts` + configMap data are tpl'd) — so the chart ships the generic script FORM in a configMap and the blocks ship PACK/LFS_SHA/URL/MARKER as DATA; the init-carrier delta is bounded by AC1's four-path budget, not byte-equivalence |
| `modelPath` anchor + dual-edit guard | SUPERSEDED per release: `--model` lives in each block's args; guard re-armed to block-subtree modelPath == block-args `--model`, per lane (the anchor dies with the anchor trap) |
| `TP2_LEDGER_KEYS` scalar carriers, `test_q27_lane` single-file shape | RE-AUTHORED by the test wave: per-lane ledger carriers / parameterized lane suites (clone-the-shape idiom) |
| NOTES.txt claim-math prose, "one chart-value home" prose | REWRITTEN as shell law + per-lane blocks (dated DECISIONS line records the deliberate change) |
| flash-TP1 profile | TRANSCRIBE the cf-143 TP1-era array from git history (`git show e7536b2c9^:charts/radiance/values.yaml` — verified this session: `--tp 1`, pool 43000, `--kv-resident 32768`, batched 4096, served fn id) with its own served id (OQ-F — coord-disclosed default, D24) |
| 27b-TP2 profile | q27 array + `--tp 2 --tp-wire wht6`, memory 24Gi held, claim "2", replicas 0 — first-boot print adjudicates (cf-143 D28(6); OQ-G — coord-disclosed default, D24) |
| strata device posture (2026-10-27 ruling: hostPath + privileged, deliberately NO claim) | **SUPERSEDED in the no-claim half by owner ruling D17**: overlay positive-ADD claim `amd.com/gpu-r9700: 1` + requests mirror; hostPath/privileged/rocr carriers KEEP (b1, R-Q5 device-mount law); `replicas 1→0` same commit (OQ-K); the ruling line lands in the values comment + DECISIONS |
| explicit `Qwen Dense + Local` route → `gpu-ai/qwen3.8-27b-q4` | **MOVED to `gpu-ai/qwen3.8-27b-radiance`** (owner ruling D20; the 502-while-parked consequence is recorded as accepted, not a bug); the `10+` background leg's `27b-q4` stays (outer llama.cpp swap, different surface) |
| hourly-loop runner `model: …strata-q4` (2026-11-09 ruling) | **MOVED to `gpu-ai/qwen3.8-flash-next-radiance`** (fresh owner ruling 2026-11-22, D16 — the old ruling's own "moves only by a fresh user ruling" clause exercised); all five byte-pinned sites re-pin in C02 |

## Landing shape (Deployment is a checked HITL stage — nothing here lands main)
- Coordinator commits chunks locally on `feat-radiance-multi-instance`; **push, PR, merge, sync
  are OWNER legs** (pipeline-push-pr discipline; repo law: never advance main from a session).
- Post-merge sync plan (owner-executed, manual — EXPLORE §1: no `syncPolicy.automated` anywhere;
  `gpu-ai-llama-swap` is ALREADY OutOfSync/Healthy — net that pre-existing delta out):
  1. rename wave as ONE sync set: `gpu-ai-amd-gpu` (ids ConfigMap → configMap-checksum rolls the
     DaemonSet; table read once at startup) + `gpu-ai-radiance` (+ q27 app) in the same window.
     Running fn pod keeps its injected devices (R-Q5); the straggler window is loud-Pending and
     self-heals at rollout completion; failure is attributable
     (`Insufficient amd.com/gpu-r9700-1`) and the revert is the same wave rolled back.
  2. **C03 restructure — its OWN watched sync set (D35):** never bundled with the rename wave or
     the later fleet wave. The generic init carrier changes `checksum/configMaps` on the live fn
     lane ⇒ the pod RECREATES (Recreate strategy): expected outage ≈ terminationGracePeriodSeconds
     (180 s) + fn model load, during which the default route 502s. Watch it to Healthy; receipt is
     the cf-143 D28(6) first-boot print of the live fn lane. If the print shows wrong pack/args,
     the revert is this sync set rolled back — nothing else moved with it.
  3. fleet wave: owner syncs parent `gpu-ai` (base) FIRST to materialize the two new
     Applications, then the children. New lanes render replicas 0 ⇒ zero scheduling impact; the
     serve-side render is delta-budget-proven (C03 AC) ⇒ no args/claims/memory change rides in.
     The C04 wave parks strata (`replicas: 1→0`) in the SAME commit that adds its claim — syncing
     it can never leave a Pending strata pod; bringing MoE up later is the owner runbook act
     (fn→0, then strata→1 — C06 prose).
  4. routing wave: repo-side surfaces take effect on landing; the hourly loop's model field is
     consumed by OpenChamber from the repo file — per D16 the loop's next scheduled run rides
     `gpu-ai/qwen3.8-flash-next-radiance` (scheduler hygiene stays human-owned per AGENTS.md; if
     the live OpenChamber task needs a manual re-sync, that is an owner leg C02 flags).
- Receipt legs (owner-executed): the OQ-R1 `unique_id` paste arrives at C04's turn (owner-committed
  at the round — cf-144 P15 pattern; the UUID arm is gated on it, D22); OQ-R2 runs on cf-144 P15's
  ordinals cited RECEIPT-PENDING; post-merge first-boot prints for the resting lanes on scale-up
  stay owner legs, never blocking this plan.

## Risks / assumptions
- **Half-wave stranding** (the ticket's worst class): mitigated by the one-commit/one-sync-set law
  (C01) and the AC4/n3 zero-stale sweeps with word-boundary-safe needles; a surviving `-1` in a
  NEW path reads as a stray placement hit — that is the sweep working, not a false positive.
- **fn single point of failure for the pipeline**: routing EVERYTHING — coord/subagent defaults,
  the Dense+Local explicit route (parked q27 lane, 502-loud by ruling D20), and now the hourly
  RUNNER (D16) — onto/through the radiance family means a Pending/crash-looping fn 502s the default
  route for all coord runs AND stalls the scheduled worker. The owner's "for everything" + the
  round's answers accept this; the resting lanes' never-default/502-idle law survives verbatim.
- **Strata claim vs the approved steady state (NEW, OQ-K)**: with a real claim, strata at
  `replicas: 1` and fn at claim-2 cannot share a 2-card pool — strata would Pending forever while
  the approved live lane runs. The plan's answer is git-parking strata at 0 in C04's commit; if the
  owner instead wants strata live, the ONLY alternatives are parking fn (contradicts the approved
  table) or dropping the claim (contradicts D17) — NOT invented in-plan, escalated as OQ-K.
- **C03 touches the live lane's values home**: the INTENTIONAL-DELTA proof (AC1 per D35 — four
  allowed paths, serve-side byte-equal) is the gate; any diff outside the budget stops the chunk —
  this is a relocation plus one ruled carrier change, not a re-decision. The delta carries a real
  fn ROLL (Recreate + `checksum/configMaps` ⇒ ≈180 s grace + model load of 502s) — hence C03's own
  watched sync set in the landing shape. The anchor trap
  runs in REVERSE during genericization (a half-moved literal could ship fn args carrying a q27
  path) — per-lane modelPath==args equality legs are the fence, asserted independently per lane
  (cross-lane drift guard, D35).
- **The two TP1 lanes cannot co-boot at transcribed memory** (110+24+5.3 > 125.08): documented
  claim/RAM math in NOTES + block comments; no silent shrink; the P11 post-boot re-pin (outside
  this ticket) is what eventually re-opens it.
- **Pinned-needles sprawl**: the four-lane fleet multiplies M8 frozen sets (evidence floors,
  catalog HOLD, peers set-equality) — the C05 test wave extends the freezes DELIBERATELY, never
  loosens them silently.
- **M8 frozen-delta + evidence append-only re-authoring is test-session work**: dev conforming to
  a designed-red evidence file is normal; a reviewer judging a test faulty routes mechanical
  repair back to the test session (repo pipeline law), never edits.
- **CI churn**: every touch of `services/gpu-ai/prod/values.yaml` fires 4 chart workflows +
  rulesync drift + aislop; expected, not a failure.
- **Concurrent-writer hazard (materialized this planning round)**: the folder saw two parallel
  plan writers; artifacts are now folded to ONE shape (this file + chunks C01–C06 + STATE +
  DECISIONS + merged FRICTION), sibling draft preserved in `PARALLEL-DRAFT.md`. Subsequent
  sessions: re-read the folder from DISK before trusting any hand-off (FRICTION row).
- Assumption: radiance 1.17.0 accepts `--tp 2` for the 27b pack (flag parity across packs); the
  boot print is the witness (OQ-G's honest hedge: the lane rests at 0 until the owner boots it).
- No agent tier has pod exec ⇒ all host-side determinism facts are owner receipts (OQ-H).

## Batched question round — ANSWERED 2026-11-22 (owner verdict: "Approve — run all waves")
The round ran against the SIBLING draft's lettering; the owner-1..7 -> OQ-x map is DECISIONS D15.
Dispositions (all now rulings, not recommendations):
- **OQ-A -> MOVE the runner literal** to `gpu-ai/qwen3.8-flash-next-radiance` (fresh owner ruling
  superseding 2026-11-09's strata-q4 ruling under that ruling's own fresh-ruling clause; D16). Full
  Leg B mandatory - C02.
- **OQ-B -> (b): strata gets a REAL extended-resource claim** on `amd.com/gpu-r9700`, OVERTURNING the
  2026-10-27 ruling's no-claim half (D17). Mechanism (b1): overlay positive-ADD claim 1 + requests
  mirror, hostPath/privileged/rocr carriers kept (R-Q5 device-mount law makes claim-instead-of-
  hostPath - b2 - a runtime break the repo already ruled against); determinism prose corrected to
  the two-leg truth (scheduler: exclusive NodeId-order allocation; container: ordinals still govern,
  receipts stay). C04 re-authored; the steady-state table below ships in C04's notes + C06's roster
  note. **(b) changes the approved steady state exactly one way: strata must join the resting set at
  `replicas: 0` - see OQ-K.**
- **OQ-C -> as proposed** (D18): keep `radiance` + `radiance-q27`; add `radiance-flash-tp1` +
  `radiance-q27-tp2`.
- **OQ-E -> FULL TRIOS NOW** (D19): both new lanes register complete catalog trios with strictly-
  below-live priority classes (starting shape flash-tp1 7/3/2, 27b-tp2 6/2/1 in the fn 9/5/1 /
  q27 8/4/0 urgent/base/low grammar; low-column collision vs fn's 1 resolved by the test author;
  M8 frozen-delta widened to +6 rows).
- **OQ-J -> Dense+Local moves to `gpu-ai/qwen3.8-27b-radiance`** (D20). Recorded accepted
  consequence: an explicit Dense+Local card now routes to a replicas-0 lane and answers 502-loud
  until a manual scale-up - accepted, not a bug. Tables + M1/M5 needles follow in C02.
- **OQ-I -> SETTLED by the rename answer** (D21): ids-row product field exactly `r9700`;
  `AMD Radeon AI PRO R9700` recorded as the row's marketing identity in the ledger comment.
- **OQ-H / OQ-R2 / OQ-R3** (D22): in-ticket atomic wave; the owner WILL paste the OQ-R1
  `unique_id` receipt at C04's turn (UUID arm live, gated on the paste); OQ-R2 re-uses cf-144 P15
  ordinals as working evidence cited RECEIPT-PENDING, not host-proven.
- **OQ-D / OQ-F / OQ-G - NOT ASKED; recommendations adopted as coordinator-disclosed defaults**
  (D24, owner may still change at Final Review): chart = mechanism-only shell; flash-TP1 =
  git-transcribed cf-143 TP1 array + 110 held + claim 1 + replicas 0; 27b-TP2 = q27 array +
  `--tp 2 --tp-wire wht6` + 24Gi held + claim 2 + replicas 0.
- **Pre-existing reds** -> dispositioned in-wave re-pinned to the RADIANCE literal (D23).

### Steady-state claim table after (b) - pool `amd.com/gpu-r9700`, capacity 2, exclusive allocations
| fn-TP2 | flash-TP1 | 27b-TP1 (q27) | 27b-TP2 | strata | claims | schedulable? |
|---|---|---|---|---|---|---|
| 1 (c2) | 0 | 0 | 0 | 0 | 2 | YES - THE approved live steady state |
| 1 (c2) | any>0 | any>0 | any>0 | any>0 | >2 | NO - every other lane Pends while fn is UP |
| 0 | 0 | 0 | 0 | 1 (c1) | 1 | YES - strata alone -> lowest-KFD-NodeId card (c3 best guess, receipt-pending) |
| 0 | 1 (c1) | 0 | 0 | 1 (c1) | 2 | YES - claim-1 lanes stack in NodeId order; the lower card goes to whoever is admitted first (scheduling order, NOT model identity) |
| 0 | 0 | 1 (c1) | 0 | 1 (c1) | 2 | pool-wise YES; RAM-wise NO at held values (110+24+~5.3 > 125.08) - never co-boot |
| 0 | 1 (c1) | 0 | 1 (c2) | any | >2 | NO - 1+2 already exceeds the pool |
| 0 | 0 | 0 | 1 (c2) | 0 | 2 | YES - 27b-TP2 alone takes both cards |
Owner-approved table (fn 1x2; flash-TP1 0x1; 27b-TP2 0x2; 27b-TP1 0x1) - unchanged for the radiance
lanes; **strata is the delta: it must rest at 0** (row 2 is why).

### OQ-K - NEW, created by the OQ-B(b) answer (confirmation round, with recommendation)
(b) is in genuine conflict with the approved steady state UNLESS strata parks: today strata is
live 1/1 OUTSIDE claim accounting (hostPath coexistence with fn is today's accidental physical
reality); a real claim converts coexistence into 3-claims-on-2-cards. Options: **(K1, recommended)
strata at `replicas: 0` in git** - a parked, 502-loud MoE lane exactly like the other resting
lanes; provider stays registered; MoE bring-up = owner scale act with the fn->0 step (C06 runbook);
the runner already left strata via D16, so the pipeline loses nothing automatic. (K2) park fn
instead - contradicts the approved fn-live lane. (K3) keep strata live claim-less - guts D17.
C04 executes K1; if the confirmation round rejects it, C04 STOPS (no invented resolution).

## Deferred (recorded, not planned)
- DRA revisit triggers (DECISIONS D11): revisit when a release carries `extendedResourceName` AND
  issue #75 closes; then CEL-select on `pciBusID` only (C6).
- fn memory DOWN re-pin from held 110 (cf-144 P11's own post-boot owner leg — not this ticket).
- ~~`-urgent`/`-low` catalog siblings for the resting lanes~~ WITHDRAWN by the round — full trios
  ship in C05 (D19); only a SEVENTH row would need a fresh wave.
- WeKan board-vocabulary (Model(s) checklist option strings) re-provisioning — owner leg via
  `wekan-board-provision`, never an in-ticket board write.
- Grafana per-lane dashboards (cf-143 follow-up card #2); gpu-cluster naming (cf-144 C04 card);
  strata on-target [VERIFY] posture (cf-144 P17 owner leg).
- Machinery (coordinator's, not this ticket's): the double-launch/cancel-but-complete class — a
  cancelled plan round CAN land a full artifact set; verify-from-disk before relaunching.
