# PLAN: Radiance replaces Strata on gpu-ai (AD-143)
feature: 2026/2026-11-cf-143-feat-radiance-replaces-strata
Owner rulings 2026-11-11: round-2 (Q1–Q8) · approval round (Q9→research, Q10, Q11, APPROVE) ·
R6 round (Q9 OPTION 1 + "fold and run on"). All folded below; DECISIONS.md is the verbatim ledger.

## Goal
Land a new `charts/radiance` (engine: `stilldeadcode/radiance` v1.17.0 — the C++/HIP one,
NOT the vllm-radiance fork behind `charts/vllm`, unrelated to Strata) as a non-privileged,
Guaranteed-QoS peer Deployment that claims the R9700 **by name** (`amd.com/gpu-ai-pro-r9700`,
made possible by a vendored `charts/amd-gpu` fork enabling the plugin's `product` naming
strategy — the llama-swap APU claim flips to `amd.com/gpu-8060s` in the same wave VIA the
gpu-ai service overlay, per-cluster shielded so the gpu cluster keeps its bare-claim chart
default (B1/D21)), serving
the FULL Flash-Next 8-session profile, joined ADDITIVELY to llama-swap via `peers.radiance`
while Strata stays fully live (Q5) — the owner scales strata down manually when testing
radiance (Q10). The vLLM chart+peer+catalog lane is disabled commented-out; the agent-context
catalog gains radiance rows with radiance's flipped priority polarity; runbook + TP2-expansion
doc land as artifacts.

Out of scope: Strata retirement of any kind (rides the owner's post-metrics decision);
on-target deploy/mutation (host-prep + acceptance gates are OWNER-run runbook artifacts — the
manual strata scale-down is owner's own lane, never a GitOps change); deleting
`charts/vllm`/`containers/vllm-radiance-mxfp4`; the physical second R9700 (C03 doc +
follow-up cards); runner-model literals (loops/AGENTS — stay valid, strata serves); Grafana
re-import (follow-up card #2); IQR-V4 adoption; the DRA-driver alternative (R6 option 2 —
ranked #2, rejected for this run by the Option-1 ruling; recorded as the natural TP2 lane).

## Structure & naming — RULED
Q1=A (own chart + peer). Q9=**Option 1: vendored charts/amd-gpu + product naming** —
per-name kubelet pools make the R9700 claim deterministic (the round-2 mis-allocation
runtime-retry gate is SUPERSEDED; a startup-report assert stays as belt-and-braces, it also
catches the fallback trap). No structural forks remain in any chunk.

## Key pinned facts (RESEARCH authority incl. §R6)
- Engine: `docker.io/stilldeadcode/radiance:1.17.0`; amd64 image-manifest digest
  `sha256:6fb0e99b…` (index `sha256:c2acbaa3…` — ledger both, name which); no `serve` verb;
  OpenAI on 8000; `/health` key-exempt.
- **FULL profile (Q10 ruling — shadow VOID)**: `--tp 1 --max-model-len 200000
  --max-num-seqs 8 --placement expert_tiered --host-pool-mib 43000 --gpu-headroom-mib 96
  --kv-cache-dtype fp8 --kv-resident 32768 --num-speculative-tokens 3
  --max-num-batched-tokens 4096 --checkpoint-interval 4096 --ngram-placement disk
  --served-model-name qwen3.8-flash-next-radiance --host :: --port 8000`. Host pins ≈
  42 (pool) + ≈19.3 (kv-resident copy 8×200K×~12.3 KiB/token) + ≈8.9 (checkpoint slots) +
  misc ≈ 60 GiB-class per the owner's ruling (exact cgroup byte receipt-gated — Q12);
  `guaranteedMemoryGi` ships at **64** as a single scalar with the arithmetic + receipt
  note. No `--prefix-cache-mib` (exclusive with kv-resident), no stale guide flags, no
  api-key. Schedulability requires strata scaled down (64+64+4 > 125.08 allocatable ⇒
  radiance sits **Pending** beside live strata — loud, safe, the designed handshake;
  restore-back after radiance testing, runbook step 9).
- Pod shape (Q7, per-name pool per Q9): `requests/limits: {amd.com/gpu-ai-pro-r9700: 1}`
  (extended resources require equal pairs — Guaranteed preserved); NO privileged, NO
  hostPath kfd/dri; seccomp Unconfined; drop ALL + IPC_LOCK; supplementalGroups [486]
  (kfd; render/video runbook-gated); Recreate; grace 180; dedicated UID + fsGroup (init
  ALSO requests==limits — pod-class law, D15); no ROCR/HIP env; no nodeSelector.
- GPU naming (Q9 + B1/D21 amendment): vendored `charts/amd-gpu` (upstream 0.22.0 copy +
  ~10-line args hook, CMD restated incl `-v=5`; `dp.extraArgs:
  ["-resource_naming_strategy=product"]`; `dp.image.tag: 1.31.0.12` + renovate docker
  comment + amd64 digest `sha256:6437c74f…` ledger); `gpu-ai-amd-gpu` Application switches
  repo→git-path with identical object names; the GPU-AI node then advertises
  `amd.com/gpu-ai-pro-r9700: 1` + `amd.com/gpu-8060s: 1`, `amd.com/gpu` GONE THERE —
  the flip is PER-CLUSTER (B1 shield): llama-swap's `gpu-8060s` claim arrives via the
  gpu-ai service OVERLAY (deep-merge + `null` removing the inherited bare key), the chart
  default stays `amd.com/gpu: 1` because the same chart serves the gpu cluster, whose
  plugin stays external single-naming 1.31.0.9 (live gpu-llama-swap stays schedulable —
  D21). Any stray APU-name claim outside gpu-ai + the amd-gpu ledger is a bug (guard
  needle); stray bare claims on gpu-ai become Pending-forever (loud by design there).
  Fallback trap (unknown revision → bare `amd.com/gpu`) is gpu-ai-scope, gated by five
  C06 step-0 receipts (a–e): sysfs pair, plugin log, node-status assert, llama-swap
  post-rollout, radiance PCI belt-and-braces.
- Priority (Q2): higher-wins flip — rows 9/5/1, peer floor `priority?: 5`, per-engine
  polarity note in pipeline-models.
- Catalog (Q4+Q8+Q10): `qwen3.8-flash-next-radiance` (+ `-urgent`/`-low` sharing the
  modelID), `in: [text, image]`, `limit.context: 200000` (full profile restored — the
  shadow-65536 mirror from round 2 is void).
- Packs: fn `qwen3.8-next-flash-fp8-iq4r-moe.rad` 113.60 GiB, ungated, lfs `0af5e962…`,
  fetch-init staged on the shared `llama-swap` claim (sha marker).

## Commands (validation battery)
Every agent: `export PATH=$HOME/.local/bin:$PATH` first (helm-guarded pytest mass-skips without it).
- charts: `helm dependency update charts/{radiance,amd-gpu} && helm lint … && helm template …` (both new charts)
- chart suites (per-directory): `python3 -m pytest charts/radiance/tests -v`; `python3 -m pytest charts/amd-gpu/tests -v`;
  `python3 -m pytest charts/llama-swap/tests -v` (strata suites green untouched — Q5; the naming-flip arms re-pinned to per-cluster render level — C07/D21);
  `python3 -m pytest charts/vllm/tests -v` (green — chart intact)
- naming wave (C07, per-cluster truth): `helm template charts/amd-gpu` shows args incl `-resource_naming_strategy=product` + full restated CMD;
  `charts/llama-swap/values.yaml` shows `amd.com/gpu: 1` UNCHANGED (comment-only diff — the B1 shield);
  gpu-AI render (chart + service merged) carries `amd.com/gpu-8060s: 1` and NO bare claim (overlay null-out);
  stray-name guards: `amd.com/gpu-8060s` appears live ONLY in `services/gpu-ai/prod/values.yaml` + the amd-gpu ledger comment;
  `grep -n "amd.com/gpu-ai-pro-r9700" charts/radiance/values.yaml` (C02 next wave);
  cross-chart name-identity test (radiance claim string == the pool the vendored plugin produces for 7551/C0 per its pinned ledger)
- service values: parses; `charts.radiance` + `charts.amd-gpu` (internal shape, SSA "true" kept) entries; `peers.radiance` AND
  `peers.strata` both present (strata block byte-unchanged); `vllm: {}` empty-key shape; no radiance ingress key + skip comment;
  renders with `OVERRIDE_`-free output
- CI-shape: extraction legs of `vllm-render-tests.yaml` (`d.get('vllm') or {}`), `radiance-render-tests.yaml`, and the new
  `amd-gpu-render-tests.yaml` run locally against live service values
- contract suites: `bash tests/pipeline-models/surface.sh`; `bash tests/notes/radiance-runbook.sh`; `bash tests/notes/radiance-tp2.sh`;
  `bash tests/services/amd-gpu-naming.sh` (new); `bash tests/services/vllm-dashboards.sh` (stays green — untouched);
  `tests/notes/vllm-runbook.sh` retired by C01 — absence-checked
- catalog round-trip: `npx rulesync generate && npx rulesync generate --check` (no-op on second run)
- quality gate: `npx aislop ci --changes`; renovate tracking for BOTH new pins (radiance docker, amd-gpu docker) via
  the `global-renovate` dry-run tool (interactive, optional)

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Disable vllm (commented-out) + retire its tails | L | 1 | [] | independent vllm surface |
| C03 | Second-GPU (TP2) expansion doc → follow-up card #1 body | S | 1 | [] | research synthesis, independent |
| C07 | Vendored `charts/amd-gpu` product naming + llama-swap gpu-ai-OVERLAY flip (B1/D21) | M | 1 | [] | defines the cluster's resource-name interface; carries entry-swap + overlay flip in its own commit (same-wave law) |
| C02 | New `charts/radiance` — non-priv Guaranteed chart, FULL fn profile | L | 2 | [C07] | interface: radiance claims `amd.com/gpu-ai-pro-r9700` — the name only exists once the vendored plugin chart lands; cross-chart name-identity test requires C07 in tree |
| C04 | Service wiring: `peers.radiance` ADDITIVE + radiance appset entry + evidence/golden | M | 3 | [C02] | served-id + scalars from the chart; evidence/golden pair with the values edit |
| C05 | Agent-context catalog: ADD radiance rows (9/5/1, text+image, 200000); strata KEEP | M | 4 | [C01, C04] | M4 reads peers.radiance (C04); same-file M-legs ordered after C01 |
| C06 | Mandatory host-prep + naming gates + acceptance runbook + contract suite | M | 4 | [C02, C04, C07] | runbook equality needs the shipped chart args (C02), peer URL (C04) and the vendored-plugin facts (C07) |

## Wave order (fold-in note: ids C01–C06 are frozen for ruling-traceability; the amendment
appends C07 rather than renumbering pending chunks)
1. C01, C03, C07 (independent; run in id order)
2. C02
3. C04
4. C05, C06 (independent of each other; run in id order)

## Rollout notes (merge-time reality — one PR, Argo syncs all; per R6-Q4-4 + B1/D21)
- The flip wave is C07's own commit, gpu-ai-SCOPED: vendored amd-gpu entry (same object
  names, plugin pod restart only — running GPU pods keep allocations; seconds-long
  deregistration window on an idle single node ⇒ no scheduling storm) + the gpu-ai
  overlay flip (llama-swap's NEXT restart on gpu-ai gets `gpu-8060s`; the running pod
  survives; the CHART default stays bare so the gpu cluster is untouched by the entire
  wave — D21 shield) + radiance chart (C02, Pending until strata is manually scaled down
  — owner's Q10 protocol).
- Rollback = ONE `git revert` of C07's commit (plugin entry revert restores gpu-ai's
  `amd.com/gpu: 2`; the overlay flip reverts in lockstep in the same range — never split
  the pair). Radiance/peer legs rollback = C01-style comment flips alone.
- Watch-once: `ignoreDifferences`/SSA field ownership on the DaemonSet `args` field when
  the Application source flips repo→path (ServerSideApply "true" helps).
- C06 step-0 enumerates the five naming receipts (a–e) + host-prep gates BEFORE first boot.

## Run-end actions (coordinator)
1. TWO Inbox follow-up cards (Q6): (1) TP2 expansion — body = C03's doc, APPEND a short
   per-cluster-posture paragraph at authoring time (D21/B1: product naming is gpu-ai-only;
   the gpu cluster stays on the external single-naming amd-gpu entry BY DESIGN — extending
   naming there is future work with its own vendored-entry decision + sysfs receipts);
   (2) Grafana dashboard re-import. Strata-deletion + IQR-V4 ride the owner's metrics
   decision, not cards.
2. "Fold and run on": after this fold-in, Test Writing + the whole chunk loop proceed with
   NO further owner pause until Final Review. Residual gaps below ship on best guesses.
3. Card write-back per the boards flow stays coord's.

## Open questions & rulings
RULED: Q1=A · Q2=flip 9/5/1 + floor 5 + per-engine note · Q3=commented disable,
`vllm: {}` kept, extraction hardened, no replicas:0, absence-asserting suites · Q4=honest
new id · Q5=STRATA LIVES (additive radiance) · Q6=two cards · Q7=non-priv NOW + mandatory
pre-deploy host gates · Q8=`in: [text,image]` + retire-on-failure smoke · Q9(20:40)=
research round → R6 → **(final ruling): Option 1 vendored product-naming, same-wave flip**
→ C07-OQ1 (2026-11-12): **B1 shield — per-cluster flip**: chart default stays bare
(tree-global, gpu-cluster-safe), the flip rides the gpu-ai service overlay (D21) ·
Q10="I will manually scale down strata when testing and using radiance" → FULL profile,
60Gi-class, scale-down/restore in runbook · Q11=observe, no auto-mitigate · APPROVED
(plan_status approved; fold-and-run-on).
Residual (best guesses shipped, NON-BLOCKING per "fold and run on"):
- **Q12 — exact Guaranteed memory byte**: owner's ruling pins the class ("60Gi-class",
  pool 43000). Best guess: `guaranteedMemoryGi: 64` shipped; if the startup receipt shows
  pins >60 GiB, the same scalar moves up (68/72 GiB — ≤~96 GiB schedulable with strata
  down); runbook step-6's ladder owns the adjustment, one edit.
- **Q13 — `amd-gpu:` service values block**: best guess NONE — vendored chart values own
  the tag+extraArgs (renovate docker comment lives there); the service entry stays the
  internal `{namespace, ServerSideApply: "true"}` shape. A service block appears only if a
  per-cluster override is ever needed (gpu-ai-only today).
- Fallback-trap decision tree if a card lands bare `amd.com/gpu` (unknown revision):
  runbook (c) gate documents both remedies (pin the claim by the materialized name /
  fix the flip list) — owner's on-target call, no repo speculation.

## Risks / assumptions
- The flip wave is gpu-ai-scoped (D21/B1): on that node `amd.com/gpu` disappears ⇒ future
  stray bare claims there become Pending-forever (loud by design, R6-Q4-3); the overlay
  flip and the entry swap live in C07's ONE commit/file, so the round-2 "between plugin
  flip and its own flip" window is closed by construction; the gpu cluster is untouched —
  its live gpu-llama-swap keeps the chart-default bare claim (the shield's whole point,
  asserted by the per-cluster render tests, C07 AC3).
- Strata stays privileged hostPath on the R9700's *physical* card inside the named pool
  (naming ≠ VRAM arbitration — Q11's law stands; manual scale-down protocol governs).
- kv-resident 8×200K start remains an on-target unknown (RESEARCH OQ3 — the refusal
  precedent was a smaller host); the runbook's down-ladder (pool → ctx → 4-seqs → owner-
  sign-off prefix-cache swap) covers it at the single scalars.
- `--kv-resident` excludes the prefix-cache tier: idle-session re-prefill pays the x4-link
  wall (~450–600 tok/s @55k) — honest-envelope note in runbook + TP2 doc.
- amdgpu.ids revision assumption (R9700 C0 → `gpu-ai-pro-r9700`; 8060S C1/C3/C6/D1 →
  `gpu-8060s`) is computed, not yet receipted on-target — the five step-0 gates close it.

## FINAL whole-plan review (2026-11-12, fresh planning-tier session, HEAD 72770056e)

**Verdict: APPROVED.** Zero blockers, zero majors. Every ticket-wide bar re-run
clean and sequential at HEAD, every whole-plan seam re-derived by this reviewer
against `main@0d9b41785` — not trusting chunk records.

Bars (all exact): llama-swap 495P/9S/0F (9 skips = standing RUN_HF_CHECK/
RUN_FLAG_AUDIT gates, enumerated) · radiance 41P/0S/0F · amd-gpu 15P · vllm 36P ·
runbook 5 ok · tp2 3 ok · amd-gpu-naming 5 ok bare AND zero-skip with
AMD_GPU_FLIP_COMMIT=546f03e01 · dashboards 5 ok · surface 9 ok bare AND M1..M8
10 ok with CF143_BASE_SHA=0d9b41785 · helm lint charts/{radiance,amd-gpu,
llama-swap,vllm} + services/gpu-ai/prod = 0 failed · rulesync @ repo-pinned
37.0.0: --check clean + generate no-op (tree empty after) · aislop ci --changes
0/0/0 over 106 files (bare via @0.20.0 AND --base main via the local 0.20.1
binary — identical result; the npx --yes --base route hung on registry network,
environmental, worked via --no-install).

Seams re-derived independently: (1) STRATA BYTE LAW — peers.strata / strata
subtree / matrix / hooks / models parse-equal vs main; charts/llama-swap/values
.yaml parsed-values EQUAL (diff comment-only both directions); golden strata
block all-context in the golden diff (my slice-compare false-red was my own
regex, the diff proves it); jsonc strata lines string-equal; strata evidence,
flashnext baseline, gpu.config golden NOT in the 71-file diff; kickoff/boards/
overview/loops/AGENTS all EMPTY diff; test_strata_wiring re-pin STRENGTHENS the
law (live vllm key or missing strata = red). (2) PRIORITY COHERENCE across all
five surfaces — class table 9/5/1 engine-scoped + per-engine polarity para +
snap re-key (1-3→9, 4-7→5, 8-9→1) + catalog trio body.priority 5/9/1 shared
modelID ctx 200000 [text,image] + floor "priority?": 5 = default class + chart
comment HIGHER-WINS/never-port + runbook step 8 with the unflipped-port
detector — leak sweep found zero lower-wins port. (3) ARGS: runbook's exactly
one fenced block == chart serveArgs token-for-token (23 tokens) == the tested
contract. (4) DIGESTS three-way (chart == runbook == ledger/renovate comments)
AND live by this reviewer: radiance 1.17.0 index c2acbaa3… + amd64 6fb0e99b…
byte-exact and still newest; plugin 1.31.0.12 6437c74f… byte-exact; pack gated:
False, 121,969,901,568 B, lfs 0af5e962…4d20 byte-exact. (5) modelPath TRIPLE
equality: chart anchor == service re-pin == appset values leg. (6) VLLM FULL
CIRCLE: zero 'vllm' strings in the rendered gpu-ai llama-swap config (peers/
models/matrix), 0 live catalog rows, no vllm app in the apps set, vllm:{}
render byte-identical to chart defaults (extraction `d.get('vllm') or {}`
=> {}), circle-back/re-enable markers at all four disable sites + the 11-line
header on the retired doc. (7) SHIELD LIVE: gpu-umbrella + gpu-cluster render
carry the bare amd.com/gpu: 1 while the gpu-ai merged render carries ONLY
amd.com/gpu-8060s (null-retire proven at render); live cluster untouched —
plugin DS still 1.31.0.9 args:null, node still amd.com/gpu: 2, strata pod
alive, readonly MCP only. (8) RUNNER ROUTE: gpu-ai/qwen3.8-flash-next-strata-
q4 intact in loops line 5 + live catalog row + favorited row + NOTES — the
hourly loop keeps working (Q4/D21 outcome).

Rulings ledger honored: Q1=A chart+peer · Q2 flip shipped · Q3 commented with
circle-back · Q4 honest new id · Q5 strata lives everywhere, byte-untouched ·
Q6 two follow-up cards textually supported (TP2 doc self-contained + exact
title "Radiance second-GPU (TP2) expansion"; runbook :522 names card #2) ·
Q7 non-priv shipped (no privileged/hostPath in any render; Guaranteed pair on
BOTH containers incl. init) · Q8 [text,image] + retire-on-failure smoke leg ·
Q9 Option-1 named pools · Q10 full profile (16-flag envelope verbatim) +
OWNER-EXECUTED scale-down/restore steps 3/10 · Q11 observe-only (:526) ·
Q13 no amd-gpu service block · B1 per-cluster shield everywhere · "fold and
run on" respected — the only owner pause was the C07 OQ1 leak escalation
(legitimate). Hygiene: 18 commits, per-commit scope clean (implementation
carriers vs records carriers), generated surfaces rulesync-only, no UUID/
secret literals in impl, radiance 1.0.0 brand-new law, amd-gpu 1.0.0 + D19
name-pin rationale, llama-swap/vllm charts untouched, branch local-only (no
upstream), main == origin/main == base — nothing pushed, nothing landed.

Findings (all non-gating; route per RESULT): m1/m2 coord-records (deferred
array misses C01/C02's three riding nits; two landed rows to close); n1
aislop 0.20.1-vs-0.20.0 note; n2 friction line for the npx hang class. The
single `open` FRICTION item (plan-file :49 "step 9" pointer) is DISPOSITIONED
acceptable — a plan-agent-surface one-liner, out of this review's edit grant,
rides the next agent-plan touch; fold is otherwise verified landed (runbook
:33 RESEARCH RQ3 cite, chart values :47/:83 steps 3/10 + receipt e,
:293 minutes-class).

---

## Rework delta — owner PR review (C08) — 2026-11-12, appended per owner direction
Six owner review items (DECISIONS "Owner PR review — 2026-11-12"; dispositions D22;
conversion shape D23 superseding D19; factual gates resolved by RESEARCH §R7). All seven
prior chunks stay DONE under the same claim; this is a delivery delta, not a re-plan.

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C08 | Owner-review rework: amd-gpu → first-party app-template + items T-A..T-E | L | 5 | [C07] | converts C07's shipped artifact; §R7 name-verdict keeps all name strings, so only the chart shape moves |

Wave 5: C08 (alone). Test Writing recurs for C08's arms (red-first re-author:
charts/amd-gpu render+provenance suites, n1–n5 re-scope, parse-compare confirmations,
the two routed test-message fixes) before dev.

Delta summary (full contract = chunks/C08.md): **T-A** charts/amd-gpu becomes a
first-party app-template 5.0.1 chart — templates/ emptied per owner ("remove _helpers.tpl
and NOTES.txt"), values.yaml declares the DS (type daemonset, args 4-list with `-v=5` law
as comment, image 1.31.0.12 + docker pin + 6437c74f ledger, THREE hostPaths — §R7
correction: NO /dev/kfd//dev/dri mounts, priorityClassName, tolerations, drop-ALL, parity
over improvement, zero RBAC/Service today), .helmignore joins; accepted strains shipped as
decisions: updateStrategy NOT rendered (= k8s default, zero delta) + D19 name byte-pin
intentionally lost → nameOverride-target live names where cheap, else ONE Argo-sync DS
prune+create swap in-wave with tests re-pinned (gpu cluster untouched — D21 shield).
**T-B** names STAY (`amd.com/r9700-1` unreachable — sanitizer + code constants, §R7;
exact-string lanes are rejected lane-switches, presented at hand-back; upstream ask =
coord run-end option; radiance claim gains the evidence comment). **T-C** serveArgs
flow-style pair-per-line reformat, token multiset EXACT, no `--flag=value` gamble.
**T-D** guaranteedMemoryGi:64 comment answers too-low/too-high IN PLACE (derivation +
ladder + designed-Pending handshake), value kept. **T-E** nits: dev-side values:744 +
jsonc floor sentence + radiance NOTES colon; test-side test_trio.py:66 + naming.sh:205
routed to the test session; M1 fold mooted by T-A.

Commands additions (beyond the standing battery): `helm dependency update charts/amd-gpu`
before renders (gitignored-tgz law); `helm template charts/amd-gpu` vs today's DS parity
diff (names per strain doc, everything else equal); gpu-umbrella + **services/gpu render
BYTE-PARITY check** (shield witness); serveArgs pre/post token-multiset equality; golden +
off-parity fixtures move ZERO lines; combined ticket-wide bar re-run (C08 AC8).
plan_status remains **approved** (owner-directed rework on an approved plan).

### Lane ruling (amendment 2026-11-12, batched owner round — recorded in DECISIONS D24)
Owner chose **"Table-mount → amd.com/gpu-r9700-1 (Recommended)"** for item 3 and confirmed
scope **"Six items + recorded nits"**. C08.md amended in place (dated markers): T-B becomes
the RENAME contract — minimal patched `amdgpu.ids` shipped as a ConfigMap over the const
IDsPath via subPath (renamed 7551/C0 row → product string exactly `r9700-1` → sanitizer
yields `gpu-r9700-1`; EVERY 1586 row carried verbatim from the fetched v1.31.0.12 baked
table — dropping one silently strands the APU name the live B1 overlay consumes: the grave
case, test-enforced parity vs the evidence fixture); ledger, radiance claim+comments+NOTES,
runbook expected-names gates (incl gate (b) row-count = the minimal table) and TP2 doc §6/§11
all move to `gpu-r9700-1`; `gpu-8060s` + the overlay + catalog/peers FROZEN (unchanged).
Minimality law: a (device,revision) absent from the table hits the shipped fallback-trap
tree — TP2 cards REQUIRE table re-verification first (rides the TP2 doc). WATCH: an image
moving its IDs path un-applies the mount silently → baked `gpu-ai-pro-r9700` returns →
claim Pending; step-0 receipts catch it. Plus T-B's COMMENT-ONLY carve sites
(charts/llama-swap flip-comment block + services/gpu-ai amd-gpu-entry comments) follow the
string; renders/golden/off-parity byte-laws unchanged there. Upstream naming feature ask:
RECOMMENDED, filing = optional owner call (Deferred; D24). Zero-stale-name AC (C08 AC4):
after C08 the old string survives only in historical records. The in-flight test round is
pointed at the amended C08.md verbatim. **Coord run-end consequences: (1) RE-PUBLISH follow-up card #1's
body — it is a doc snapshot and the TP2 doc's name strings + re-verification law changed;
(2) STATE.deferred carries both open owner-lane items (upstream ask; card refresh).**

---

## FINAL whole-plan review round 2 (2026-11-12, fresh planning-tier session, HEAD a81989b47 + coord's
uncommitted C08 bookkeeping fold in the worktree; base main 0d9b41785)

**Verdict: APPROVED.** Zero blockers, zero majors. The C08 delta re-verified bar-for-bar and the
ticket-wide coherence re-derived independently against `main@0d9b41785` — nothing trusted from the
chunk records.

**Bars (all run fresh, sequential, PATH-exported):** llama-swap 495P/9S/0F (9 skips = standing
RUN_FLAG_AUDIT/RUN_HF_CHECK gates) · radiance 42P/0F · amd-gpu 26P/0F · vllm 36P · runbook 5 ok ·
tp2 3 ok (15 citation forms) · naming 5 ok bare AND full green with AMD_GPU_FLIP_COMMIT=a81989b47…
(conversion-wave same-wave guard + claim-line zero-diff verified against the real commit) ·
dashboards 5 ok · surface 9 ok bare AND M1..M8 10 ok with CF143_BASE_SHA=0d9b41785 · helm lint
charts/{amd-gpu,radiance,llama-swap,vllm} 0 failed · rulesync @repo-pin `generate --check` clean ·
aislop @0.20.0 `ci --changes` 0/0/0 over 106 files AND the bare local 0.20.1 form 0/0 AND the
`--base main` form via npx @0.20.0 completed (135 ms, rc0 — the FRICTION hang class did NOT recur,
second consecutive round). Tree clean after all runs (only coord's pre-existing STATE/C08 fold +
this record).

**Rename-coherence sweep (independent):** `gpu-ai-pro-r9700` whole-literal hits ZERO in
charts/ services/ tests/ .agents/notes/ .github/ custom-values/ containers/ .opencode/ .rulesync/
— survives only in pipeline records + plan history (the sanctioned AC4 set). `gpu-r9700-1` sits
EXACTLY at the AC4 placement set: charts/amd-gpu (values+2 test files), charts/radiance
(values+NOTES), the two T-B comment carve sites (charts/llama-swap/values.yaml,
services/gpu-ai/prod/values.yaml), the two notes docs, tests/ constants, TEST_SPEC + pipeline
records. The rejected literal `amd.com/r9700-1` appears only in pipeline records plus its ABSENCE
guard (`test_provenance.py:320` assembled form — never claim-shaped). **Table content re-derived
against MY OWN live fetch** of the v1.31.0.12 authority (raw.githubusercontent …/cmd/k8s-node-
labeller/amdgpu.ids): sha256 382ef0d5…f3b1fa, 758 lines — equals the fixture header's claim; the
fixture's 7551 rows == authority rows byte-equal; the shipped 1586 rows == authority rows
byte-equal (9); exactly ONE 7551 row `7551,\tC0,\tr9700-1` (only the product field edited vs the
baked `AMD Radeon AI PRO R9700` row; C1/C8 siblings deliberately absent — minimality); header +
`1.0.0` per format; rendered table = 455 bytes / 10 data rows / sha256 864da869…c6f5 — the
runbook's gate-(b) pin AND the `Loaded 10` expectation match. **Fallback story** identical at all
three homes: ledger (unknown (device,revision) → bare `amd.com/gpu` + WATCH line), runbook
(step-0 (a) decision tree with the fix-the-table/pin-the-name remedies + step-2 node assert),
TP2 §6/§11 (minimal ten-row table by construction → RE-VERIFICATION LAW: verify-or-ADD the pair
before trusting TP2 scheduling).

**C08 delta audits:** (a) converted DS vs the committed oracle — args 4-list / image 1.31.0.12 /
priorityClassName / tolerations / container secctx byte-equal / THREE hostPaths byte-equal (health
trailing slash + DirectoryOrCreate-only) / resources `{}` vs omitted field (semantic parity, D23
documented) / updateStrategy absent (accepted k8s-default strain) / zero SA-RBAC-Service-Ingress /
kinds exactly {ConfigMap, DaemonSet} / ids-table subPath+readOnly mount / selector SELF-coherent /
rename-set enumeration COMPLETE in the values ledger (DS, selector, container, ConfigMap, volume —
every moved object listed). (b) umbrella planes: gpu-ai AND gpu renders HEAD~(b74aaba85)↔HEAD
**BYTE-EQUAL whole** (C08 r1's N3 witness re-confirmed: the change lives entirely in the child
plane). (c) shield witnesses at render: gpu-ai merged llama-swap = limits EXACTLY
{amd.com/gpu-8060s:1} (bare null-retired) + requests mirror; gpu-cluster default render = bare
`amd.com/gpu: 1` INTACT; rendered llama-swap config carries peers {strata, radiance}, vllm ABSENT.
(d) radiance render: claim pair `amd.com/gpu-r9700-1: "1"` at requests AND limits (Guaranteed,
init pair carried), no privileged/hostPaths, drop-ALL+IPC_LOCK, supplementalGroups [486]. (e)
serveArgs: pair-per-line flow-style, parsed-token compare (the suite's + dev's 32-token equality).
(f) T-D: all four fact-families at the scalar, value 64 kept.

**Teeth probes (synthesized violations on a /tmp copy of the tree; the two routed re-pin arms):**
stray `gpu-r9700-1` in a non-admitted path (charts/vllm) → placement guard **RED**; stray OLD
literal in services/gpu → zero-stale guard **RED**; controller-identifier tamper →
per-object-coherence guard **RED** (+ the RBAC-absence leg); every tamper restored, suite re-green
26P, copy verified byte-clean vs repo. Line-by-line diff of the two re-pinned arms: the old
`test_object_names_are_pinned_to_the_pre_ticket_ds` triple-pin DIES by owner ruling (D23 strain 1,
library-unreachable selector per the §12.7 dev evidence) and is REPLACED by strictly-more-real
properties (per-object live-or-enumerated + selector self-coherence + TypeError-free); the
placement arm is net-new enforcement; naming_flip's re-pin is a literals→canonical-constants swap
(equal semantics, one-edit-site design); test_trio.py:66 is the routed message completion.
**No weakening anywhere.**

**Carries from the C08-era reviews — dispositioned:**
- N1 (radiance/amd-gpu testlib historical-constant mention): **ACCEPTED** —
  `HISTORICAL_R9700_POOL_NAME = "gpu-ai-pro-" + "r9700"` is the sanctioned assembled-literal
  idiom (vllm_testlib LEGACY_REF precedent, TEST_SPEC §12.6 documents it), the AC4 grep law is
  satisfied mechanically (the whole literal exists in NO live file), and the sanitizer port NEEDS
  the historical input (the fixture-trust leg asserts the pre-C08 derivation). No action.
- N2 (llama-swap overlay comment naming the renamed pool): **ACCEPTED TRUTHFUL** — verified
  line-by-line against the D21/D24 chain: `gpu-r9700-1` + patched-table provenance + per-cluster
  scope + null-flip mechanics + `gpu-8060s` frozen + strata hostPath law all match the shipped
  render. NEW related nit FR-2 below ("vendored" phrasing survived the first-party conversion in
  one older comment block).
- N3 (§12.5 aislop `--base` hang class): **CARRIED** — FRICTION line 20 holds the class, the
  local-pin workaround and the 0.20.1-vs-CI-0.20.0 drift note; not TEST_SPEC-only. This round
  neither form hung (second clean run) — the workaround law stands regardless. The drift note
  rides the next records touch (coord).
- N4 (pre-c08 evidence fixture path pins): **VERIFIED** — both fixtures committed at a81989b47
  (`git ls-files` clean), the loud-assert pins resolve (`table_authority()` + ORACLE legs green,
  incl. inside my /tmp copy — path resolution is self-contained).
- N5 (STATE C08 rows): **VERIFIED** — STATE.json parses; chunks.C08 coherent (status done, wave 5,
  depends [C07], dev_rounds 1, review_rounds 1, last_verdict APPROVED, commit a81989b47, four
  handoffs tests-r1/dev-r1/tests-r2/review-r1, amendment note present). All eight chunk rows
  status-consistent with their verdicts. Residual for the coord's bookkeeping commit: the
  deferred array still carries five rows C08 discharged — the C07-M1/N1 header rows (MOOTED by the
  first-party rewrite), C01 test_trio.py:66 nit, C02 NOTES-colon + naming.sh:205 rows, C05-N1
  jsonc-floor row (all landed, re-status to closed); and C01–C03 rows carry no `commit` field
  (provenance rides their handoffs — historical shape, optional backfill).
- FRICTION open plan-pointer line (plan :49 "runbook step 9"): **DISPOSITIONED ACCEPTABLE**, same
  as round 1 — pre-doc shorthand in the plan's own frozen body (which also still carries the
  superseded pool name at :9/:50/:60 per the plan-as-record carve); the true pointers (steps 3/10)
  live in the live surfaces (T-D comment, runbook headings); fold is routed (STATE.deferred
  :419 + FRICTION :23) and owed at the next agent-plan touch — the plan-file permission boundary
  makes it structurally NOT this branch's lane (FRICTION :22/:23). DECISIONS carries no "step 9"
  sweep — correct, DECISIONS is the decision ledger, the pointer history lives in chunks/C06.md M2.
- Two routed test arms' re-pins: see Teeth probes — per-object coherence + placement admit both
  verified with real teeth.

**Findings (none gating):**
- FR-1 (minor, records hygiene): FRICTION lines 22/23 are near-duplicate entries of the same
  permission-boundary event (line 23 the precise restatement) — re-status line 22 rather than
  append a third.
- FR-2 (nit, wording class): the "vendored" qualifier survives in three current-wording homes
  post-D23 — `charts/llama-swap/values.yaml:1054` ("the vendored product-naming plugin"),
  `charts/radiance/tests/test_resource_name_identity.py:36` docstring ("the vendored plugin"),
  and `tests/services/amd-gpu-naming.sh` n1's "vendored internal shape" message (+ the marked
  `VENDORED=` alias, which is documented as a legacy path alias — fine). One-word folds at each
  file's next touch; renders and needles are name-agnostic so nothing breaks.
- FR-3 (nit, guard depth): the coherence arm's enumeration check reads `value in
  chart_values_text()` (whole file), and a container name always appears in values as its own
  container key — so the CONTAINER side cannot redden from a ledger omission (the DS side and the
  selector self-coherence DO bite — probe-verified). Consider narrowing the check to the
  rename-set/ledger lines at the next lane move (the same one-edit-site home as C08-r1's N4
  allow-set note).

**Cross-chunk final coherence (all re-derived, nothing fell between chunks):** C01 disable-state
still true post-C08 (peers.vllm absent from the render, zero live vllm catalog rows — 86 live rows
= C01's 83 + C05's radiance trio; C08 touched the jsonc comment-only). C02+D24 combined: full Q10
profile, claim renamed, Guaranteed pairs incl. init, keyless. C04: peers.radiance join byte-from-
evidence, two-peer golden green in the 495P run. C05: catalog trio 9/5/1 higher-wins (priority 5/9/1
per-class verified in the strict parse), strata rows KEEP, per-engine polarity note, M1..M8 needles
green — no C08 collision (C08 froze the engine-facing ids correctly: no catalog/peers name legs).
C06: runbook complete with renamed gates a–e + Loaded-10/sha pins + WATCH + fix-the-table remedy +
reworded lockstep-revert for the two-commit wave. C07: shield intact — gpu-cluster bare claim
byte-equal at render AND zero-diff on the claim line at the commit; llama-swap chart comments
truthful (FR-2 aside). The in-wave DS prune+create is OWNER-acceptance and documented at FOUR
homes: the values rename-set header, the services/gpu-ai entry comment, runbook step-2 gate 1
("acceptable — it is the D23 strain, not an incident"), and the plan's Rework-delta. Goal-vs-card
re-derived: engine radiance (not the fork, not Strata), TP2 doc card-ready post-rename (§6/§11
laws, tp2 suite green), priority/preemption handled (9/5/1 + floor 5 + runbook step-8 live proof +
image-smoke retire clause), vllm disabled commented with circle-back markers, strata lives per Q5,
both follow-up cards exist — card #1 body verified PRE-RENAME on the board (stale; the re-publish
is the coord's run-end action per D24, NOT a branch finding).

**Git/scope:** per-commit audit of everything after round 1: 1a030a87e (plan-folder record),
eef04f9c3 (C08 contract + §R7 + D22/D23 — records only), b74aaba85 (D24 lane ruling — records
only), a81989b47 (33 files, exactly the C08 Files-in-scope + the adjudicated workflow dep-update
step + the two notes docs — zero plan-folder files, zero gpu-cluster files, `services/gpu` and
`charts/llama-swap/**` outside the carve comment-only or untouched). Bookkeeping fold rides the
worktree uncommitted (STATE + chunks/C08 review notes + this record) as designed — commit-only
lane, reviewer writes only under .agents/plans/. Branch LOCAL-ONLY (no upstream, no
origin/cf-143… ref); main == origin/main == 0d9b41785, untouched; nothing pushed anywhere.

**Owner must know at hand-back:** (1) the merge→sync effect — the gpu-ai plugin DaemonSet is
pruned and recreated under new names in ONE Argo sync (seconds-long window, running GPU pods
unaffected, gpu cluster outside the wave); acceptance is the owner's at sync time, receipts are
runbook step-2. (2) The `amd.com/gpu-r9700-1` name rides the unsupported-but-ruled
patched-`amdgpu.ids` ConfigMap injection (D24) — the WATCH (image moving its IDs path un-applies
the mount silently) is test-pinned + runbook-gated. (3) The upstream naming-feature ask is
RECOMMENDED, filing an OPTIONAL owner call (D24/Deferred) — record the choice. (4) Follow-up card
#1's body is stale (pre-rename) — the coord re-publishes it as a run-end action before the Review
hand-off. (5) On-target lanes stay owner-run: PR merge, runbook step-0 gates first, Q12 receipt
ladder may move the 64 scalar UP (one edit).

— final reviewer round 2, 2026-11-12 (fresh session; no implementation or validation file edited;
teeth probes and dep-update-free renders only in /tmp copies; repo tree verified clean post-runs).

---

## Rework delta 2 — live defect C09 (container command) — 2026-11-13, appended per owner report
Owner-reported LIVE RunContainerError after the C08 sync (pools un-advertised → radiance +
gpu-ai llama-swap Pending). Authority: EXPLORE.md §D1 (scout round 2 — registry image-config
+ Dockerfile@v1.31.0.12 + live-pod renders, every fact grounded). Root cause INHERITED FROM
C07 (args-only against a no-ENTRYPOINT image; the parity oracle shares the defect — "the
oracle is the defect", never live-proven because gpu-ai ran the external chart until C08).
plan_status reopened complete→approved for this delta (D25).

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C09 | deviceplugin container gains `command: ["/root/k8s-device-plugin"]` (+ WHY-comment, evidence authority, runbook receipts) | S | 6 | [C08] | fixes C08's shipped file; the defect predates C08 but only C08 made it live |

Wave 6: C09 (alone). Commands additions (beyond the standing battery): the /tmp-copy
render asserting `command == ["/root/k8s-device-plugin"]` beside the UNCHANGED 4-item args;
`bash tests/services/amd-gpu-naming.sh n2` with `AMD_GPU_FLIP_COMMIT=<C09 sha>`; services/gpu
render BYTE-PARITY (shield witness — the fix is gpu-ai-chart-only); zero-stale + placement
scans re-run; combined bar per chunks/C09.md AC6 (§12.7 counts + the three new red-first
legs). Live verification stays OWNER-RUN read-only prose (AC7) — the crashloop clears only
when the owner merges and syncs; agents touch no cluster.
