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

## Rework delta 3 — live defect C10 (claim carrier + appset null-drop) — 2026-11-13, appended per §D2
Second LIVE defect from the same on-target round (EXPLORE.md §D2, scout round 3 — AUTHORITATIVE,
plan-session readonly re-verified ~03:4xZ): the B1 overlay's `amd.com/gpu: null` retirement is
DROPPED in the ApplicationSet→Application valuesObject chain (null present in the live
ApplicationSet generator, absent from the live Application's `spec.sources[].helm.valuesObject`;
helm alone honors it — locally reproduced). The chart's tree-global bare claim therefore survives
live on gpu-ai against a capacity-0 bare pool → the outer llama-swap pod is Pending-forever under
`strategy: Recreate`: **llama.spencerslab.com router DOWN since 01:52:09Z; runbook step 3 will NOT
restore it** (radiance's Pending IS the designed handshake). Fix: the CARRIER moves — deletion is
inert through this chain, positive ADDs survive. D26 supersedes D21's MECHANISM only; the owner's
B1 intent (gpu keeps the bare claim, gpu-ai the named APU pool, no workload strands) stands
verbatim. plan_status stays reopened-approved (wave 6 → 7).

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C10 | llama-swap GPU-claim carrier move: chart default ships NO claim; `services/gpu` ADDs bare `amd.com/gpu: 1` (limits-only, byte-neutral); `services/gpu-ai` keeps the 8060s add, drops the inert null + false prose; naming-flip oracle re-pinned to the valuesObject layer; runbook live-closure truths | S | 7 | [C09] | same file set as C09's landed wave (n2 WAVE-C matcher extends the accepted shapes); the claim surface C07/D21 placed tree-global+null is what §D2 proves dead in production |

Wave 7: C10 (alone). Commands additions (beyond the standing battery): the AC1 consumer
enumeration table is the truth set (per-cluster claim law verified LIVE, both directions — no
consumer loses its only schedulable claim); gpu-merge render `limits == {amd.com/gpu: 1}` EXACTLY +
**gpu-cluster rendered resources block BYTE-equal to its pre-C10 render** (the net-neutral transfer
proof); gpu-ai render + the new valuesObject-PROJECTION legs (appset render → documented
mergo-nil-skip projection → chart overlay → exact claim sets) and the null-absence guard
("the pattern that cannot fail silently") — red-first today; charts/llama-swap bar 495P/9S +
re-pinned/renamed flip legs, 0F; radiance 43P, amd-gpu 29P, vllm 36P;
`bash tests/services/amd-gpu-naming.sh` bare + `AMD_GPU_FLIP_COMMIT=<C10 sha>` (WAVE-C = chart
values + BOTH service overlays + the runbook doc, ONE commit — split carrier = a
zero-schedulable-claims window; transfer check: chart 1→0 AND services/gpu 0→1 same commit);
runbook 5 ok (count-0 reading of the bare-ABSENT gate lines, the third failure class, the
step-3-does-not-restore-the-router truth, §D2 numbers 65.158/125.08/59.92), tp2 3 ok (grep-verified
out of scope — it quotes no claim-carrier shape), dashboards 5 ok, surface bare 9 ok +
`CF143_BASE_SHA=0d9b41785` M1..M8 10 ok (explicit check-ids law), helm lint x4 +
`services/{gpu,gpu-ai}` umbrella renders, zero-stale sweep unchanged, placement scans re-scoped
(n3 bare site: ONLY `services/gpu/prod/values.yaml`; chart carries ZERO live claims), rulesync
--check @37.0.0, `npx --no-install aislop ci --changes` 0/0. LIVE closure stays OWNER-RUN read-only
prose (AC7): post-sync router pod Running on `gpu-8060s` (node allocation names llama-swap),
radiance still Pending until the owner's step 3; the `charts/base` appset-charts passthrough
root-fix is OUT OF SCOPE (repo-wide blast radius) → coord files the follow-up card (body line in
chunks/C10.md AC5 / DECISIONS D26).

---

## FINAL whole-plan review round 3 (live-defect deltas C09+C10) — 2026-11-13, fresh
planning-tier session, HEAD 4652671fd (C09 = b1def8d1f, C10 = 56142d511 amended + records)

**Verdict: APPROVED.** Zero blockers, zero majors. Both live-defect rounds re-verified against
the LIVE cluster truth (readonly MCP only) and re-derived bar-for-bar with no trust in prior
verdicts; the eight earlier chunks' guarantees re-checked post-C09/C10. NOTE on the landing
state: the owner already rebase-landed the branch through C09 onto main (`main == origin/main
== ec18281fb` carries the re-hashed C09 wave — that is why C09 is LIVE-GOOD and the router is
still broken); the remaining merge delta `main..HEAD` is exactly 19 files — 56142d511 (C10) +
1b89da994 (its plan round) + 4652671fd (records). **56142d511 is the router's cure.**

**Bars (all run fresh, sequential, PATH-exported, dep-update only in /tmp copies):**
charts/llama-swap **498P/9S/0F** (9 skips enumerated = standing RUN_FLAG_AUDIT/RUN_HF_CHECK
network evidence gates, zero helm-skips) · charts/radiance **43P/0F** · charts/amd-gpu
**29P/0F** · charts/vllm **36P/0F** · amd-gpu-naming **5 ok bare AND** full green with
`AMD_GPU_FLIP_COMMIT=56142d5115…` (WAVE-C same-wave guard + carrier transfer verified: chart
bare 1→0 AND services/gpu +1, one commit) **with teeth re-proven by this review** (bogus sha →
RED "is not a commit"; plans commit 1b89da994 → RED "matches NO accepted shape") · runbook
**5 ok** · tp2 **3 ok** · dashboards **5 ok** · surface **9 ok bare** AND
`CF143_BASE_SHA=0d9b41785 … M1..M8` **10 ok** (M8 needs explicit check-ids — env-var-only is
9 ok BY DESIGN) · helm lint charts/{amd-gpu,radiance,llama-swap,vllm} + both service umbrellas
**0 failed**, renders exit 0 · rulesync @repo-pin `generate --check` clean · aislop: local-pin
`ci --changes` 0/0/0 (106 files) AND the `--base main` form answered promptly 0/0/0/106 at the
final tree — the C09-r1 drift reading (35/78E on out-of-branch files) did NOT reproduce here;
the CI-authoritative form (`@0.20.0 ci --changes --base origin/main`) passed at C09 r1 and the
workflow header's full-repo-debt note stays accurate. Tree clean after every run.

**FOCUS 1 — C09+C10 as a pair, vs the live truth:**
(a) `charts/amd-gpu` renders `command: ['/root/k8s-device-plugin']` + the EXACT 4-item args +
the ids-table subPath mount over `/usr/share/libdrm/amdgpu.ids` (readOnly), kinds
{ConfigMap, DaemonSet}, zero RBAC ✓. The image-config evidence json is the COMMAND authority
(Entrypoint ABSENT, Cmd four items `./k8s-device-plugin`-first, WorkingDir `/root/`, manifest
digest byte-equal the 6437c74f values ledger) and the testlib RE-DERIVES PLUGIN_COMMAND from
it (cmd[:1] pinned before the WorkingDir join — constants cannot drift silently). The oracle
carries its KNOWN-DEFECT header (one authorized comment) with the parsed body **byte-equal to
the a81989b47 capture** — re-verified here, not trusted. The radiance asymmetry is DOCUMENTED
and frozen: `test_main_container_stays_command_absent_entrypoint_witnessed` states the image
HAS Entrypoint [radiance] (registry receipt at 5b4c1470/6fb0e99b, §D1.5), args-only is the
ruled shape, a consistency-copy would RED, and the leg names its own removal law.
(b) `charts/llama-swap` ships **NO GPU claim** (requests cpu/memory only; the WHY block carries
the per-cluster-ADD law + both dead ends named — null AND 0). `services/gpu/prod` ADDs bare
`amd.com/gpu: 1` **limits-only** — my adjudication, once more, against the LIVE witness: the
running gpu-llama-swap template is exactly `limits {amd.com/gpu:1}` + `requests {cpu:1,
memory:4Gi}` (kubelet mirrors extended resources), so limits-only is the byte-exact transfer;
a requests mirror would MOVE the shielded render and is NOT owed (owner overrule = one line +
leg-B re-pin, presented below). `services/gpu-ai` keeps the gpu-8060s add + mirror; the inert
null and its false prose are gone; a repo-wide scan finds NO live `: null` retirement anywhere
under `services/` (the supabase `'{"data": null}'` hit is a JSON-string body, not YAML null).
(c) PROJECTION re-derived by this reviewer independently (umbrella render → generator values →
recursive nil-drop → helm → Deployment): **gpu-ai** = limits EXACTLY {gpu-8060s:1}, requests
{gpu-8060s:1, cpu, mem}, generator subtree null-free; **gpu** = limits EXACTLY {amd.com/gpu:1},
requests {cpu, mem} — byte-equal to the pre-C10 chart-default render (the C07/C10 live-witness
included): the shield's REAL meaning — the rendered gpu pod unchanged — holds
carrier-independently. LIVE reads (readonly tier): Application `gpu-ai-llama-swap@default`
valuesObject = APU-only pair, ZERO null keys, sources[0].helm absent (MAJOR-1's shape lives);
plugin DS 1/1 ready with command+4-args (C09 live-good); node `ai-gpu` capacity `amd.com/gpu:
"0"` + both pools 1 (the count-0 reading the C10 docs sweep teaches IS the live truth); memory
allocatable 125.08Gi. The router Deployment remains the BROKEN pair (gen 49, unavailable 1,
Recreate, limits {amd.com/gpu, gpu-8060s}) — **owner-side pending sync, not a branch fault →
AC7 hand-back item, first in the receipts order below.**
(d) Silent-failure guard: leg C walks the PRE-projection generator values of BOTH umbrellas
(null ⇒ RED — verified non-vacuous: the walk reads the raw map, the projection is a separate
step) and text-scans EVERY `services/*/*/values.yaml` for live `amd.com/…: null` lines —
so re-introducing the GPU-claim null-retirement ANYWHERE under services/ is impossible.
Honest coverage note: the GENERALIZED class (a null retiring a NON-amd.com key on some other
app) is enforced only for the two watched llama-swap subtrees + prose; its repo-wide form
naturally belongs to the D26 passthrough card (its companion would be a repo-wide
null-scan arm) — recorded, not a gap of this ticket.
(e) Zero-stale sweep re-run: `gpu-ai-pro-r9700` 0 hits across charts/ services/ tests/
.agents/notes/ .github/ custom-values/ containers/ .opencode/ .rulesync/ (records-only);
`amd.com/r9700-1` 0 live hits (rejected literal stays record-side + assembled absence-checks);
`gpu-r9700-1` exactly at the AC4 placement set. ids-table: rendered sha 864da869…c6f5 == the
runbook pin, 455 bytes, 10 data rows; the fixture files were untouched since C08 (C09 added
only the image-config json + oracle header) — the APU-rows/7551-row byte-parity legs re-ran
green inside the 29P.

**FOCUS 2 — goal-vs-card after two live rounds:** every prior chunk's guarantee holds at the
post-C09/C10 tree: C01 vllm disable intact (golden 0 'vllm' hits, 0 live catalog rows — the
jsonc is 86 live rows = C01-era 83 + C05's radiance trio, the trio commented with markers);
C02 full profile + Guaranteed pairs + the 64Gi answer-in-place — and the owner is LIVING the
arithmetic: 64+64+4 = 132 > 125.08 shipped, live-grounded 65.158 + 64 = 129.16 (§D2.4; the
shipped 132's undercount is documented as MORE-over-budget direction, never less), radiance
Pending-by-design to the byte; the runbook's THIRD-CLASS section does NOT contradict step 3 —
it scopes it (step 3 schedules RADIANCE; the OUTAGE TRUTH line says plainly the router returns
only with the C10 merge+sync); C04 peers.radiance live in the golden + projection render; C05
trio 9/5/1 higher-wins + polarity + [text,image] (M8 green); C06 runbook complete at 717 lines
incl. the C09 exec receipt (-A4 describe lens) and the C10 diagnostic (pinned RUNNABLE shape:
`-n default get application`, `sources[1].helm.valuesObject`); C07 shield proven at the
projection layer; C08 first-party chart + rename unmoved. Strata LIVES (Q5) — its pod Running
33h on its pre-swap allocation; TP2 doc + card #1 (re-published POST-rename — live-checked:
carries gpu-r9700-1 + the RE-VERIFICATION law) + card #2 + the pending D26 card close the
card's documented-instructions ask.

**Carry-list dispositions:** M-1 grep fold — CLOSED, `-A4` ACCEPTED over the carry-literal
`-A1` (describe emits four Args lines; -A4 ⊇ -A1; doc :237 names four; T5 holds green).
Chart.yaml governance-header one-line fold — ACCEPTED AS DEFERRED, row stays open (Chart.yaml
is outside every wave's sanctioned set since; the authoritative corrected story is
test-pinned in values.yaml; behavior-irrelevant). MINOR-2 frozen strata prose ~1348-1354 —
POINTER ADEQUATE: three dated homes (STATE.deferred names the exact range + FORWARD, TEST_SPEC
§12.9 ledger, DECISIONS cutover line); the region is byte-frozen by C04/AC4 and dies at the
cutover anyway — no edit owed. NIT-2 "without a single-naming history" (:278) — ACCEPTED as
dev-lane optional wording (the count-0 conjunct independently catches every real fallback).
NIT-3 PROVENANCE delta-header direction — cosmetic, closed-by-parenthetical, concurred. M8
explicit-check-id law — documented in TEST_SPEC §12's run-posture section + the script, but it
has now tripped a second reader: recommend ONE FRICTION line (coord's write). D26 follow-up
card — body line recorded at chunks/C10.md AC5/DECISIONS D26 is ADEQUATE for the root fix
(fact + both sanctioned fix shapes + evidence-pair citation + blast radius + latent-not-active
status); recommend the created card also cite TEST_SPEC §12.9's class law (and consider the
repo-wide null-scan companion there); board check this round: NOT yet in Inbox → coord
run-end action, still owed. Class laws L1 (command/entrypoint parity + image-config receipt),
L2 (valuesObject projection), L3 (owner-facing commands are RUNNABLE SHAPE) are each STATED
where agents read them (FRICTION 2026-11-13 lines + DECISIONS D25/D26 + TEST_SPEC §12.8/§12.9)
AND test-armed on their ticket planes; L4 (patched-regex byte audit) is a process law —
prose-only by nature, FRICTION + §12.9 AMENDMENT are its homes, flagged honestly.

**FOCUS 4 — git/scope:** per-commit audit of all five post-5d2afd129 commits: e086638b4 and
1b89da994 are plan-folder-only records (6 files each); b1def8d1f = exactly C09's 11-file set
(2 dev + 8 test-wave + 1 evidence json, zero services/gpu-cluster files); 56142d511 = the 13
WAVE-C-shaped files (four dev values/docs + eight test files incl. the amended chunks/C10.md
record); 4652671fd = three plan-folder files. The AMEND was lawful: branch never pushed
(no upstream, `origin` carries no cf-143 ref), 698af3b78 unreferenced and NOT an ancestor,
a81989b47/b1def8d1f intact, main == origin/main == ec18281fb untouched by any agent write.
Test-integrity: every removed assertion line across C09+C10 classified — each is either a
D26-ruled carrier flip (its inverse guard shipped strictly stronger: legs A/B/C + WAVE-C
transfer + null-absence repo scan) or a re-embedded prior shape; the off-parity fixture moved
by EXACTLY the sanctioned 2 transferred lines with a PROVENANCE era entry and teeth (synthesized
third change reddens both arms per §12.9); NO weakening. Tree clean after all runs.

**Owner hand-back, in order:** (1) MERGE + SYNC 56142d511 (with its records) — the router cure;
then the AC7 receipts IN SEQUENCE: (i) router pod Running on `amd.com/gpu-8060s` (Recreate
replacement — llama.spencerslab.com back); (ii) node pools `amd.com/gpu-r9700-1: 1` +
`amd.com/gpu-8060s: 1`, bare `amd.com/gpu` at COUNT 0 — already true live (C09 receipts
re-confirmed this round); (iii) radiance schedules ONLY after step 3 — SUSPEND auto-sync of
gpu-ai-llama-swap first, then the owner's `kubectl scale deploy/gpu-ai-llama-swap-strata
--replicas=0` (free 59.92 → 123.92 ≥ 64; do NOT touch guaranteedMemoryGi to clear it);
(iv) the 8-session gate at full sizing (step 6); (v) then the receipt-gated ladder 64→68/72
(→~96 while strata is down). (2) DECISIONS owed: the limits-only word (live witness says the
transfer is exact; overrule = one line + leg-B re-pin); the D26 passthrough card — file it
(adequate body ready, see above) and triage it as its own ticket; the upstream naming-feature
ask (D24) remains an optional filing. (3) Card #1/#2 sit in Inbox awaiting the owner's pickup;
AD-143 moving Executing→Review→Finished stays the owner's alone.

— final reviewer round 3, 2026-11-13 (fresh session; no implementation or validation file
edited; renders/dep-updates confined to /tmp copies; cluster reads readonly-tier only; repo
tree verified clean post-runs).

### Round 3 ADDENDUM — §D2.8 adjudication, the D26 card, and the full fresh re-run (2026-11-13, later the same day)

The record above was written before scout round 4 (§D2.8, EXPLORE) and the DECISIONS D26
AMENDMENT landed in the worktree, and before the D26 follow-up card was filed. This addendum
closes those and re-runs the ENTIRE bar fresh at the current tree (HEAD 4652671fd + the
uncommitted §D2.8/D26 records fold — zero implementation files moved since 56142d511, verified
by `git status`). **Verdict unchanged: APPROVED. Zero blockers, zero majors — and §D2.8
introduces no record defect: the falsified-cause hunt is CLEAN (below).**

**(1) THE MECHANISM ADJUDICATION (FOCUS 1(e) — a surviving falsified claim would be a MAJOR).**
§D2.8 falsifies CAUSE-A ("helm ignores nulls" — helm v3.16.4 `coalesce.go` deletes nil keys,
docs 'Deleting a default key', offline render A on the pre-C10 blobs RETIRES the bare) and
CAUSE-B ("propagation staleness / transient wedge" — `Application.status.history` ids 123–132
show the APU ADD present in every snapshot from 01:52:08Z, the null absent from ALL of them,
across 4 syncs and 2 ReplicaSets; no schedulable shape ever existed, and no APU-only template
has EVER been live). The surviving story is §D2.6's, hardened: the null dies whole-tree inside
the ApplicationSet-controller hand-off; my OWN live re-read this round confirms the killer
datum — `gpu-ai-amd-gpu`'s valuesObject is literally `{}` (its only generator content was the
inert `shared-storage: null`), and every Application read is null-free doc-wide. **Record grep
hunts (DECISIONS/STATE/FRICTION/plan/chunks/EXPLORE + shipped docs): the retired-NORMATIVE
framing = 0 hits; 'stale/transient' near valuesObject/hand-off/wedge = only §D2.8's own
falsification paragraphs and the D26 AMENDMENT (correct usage); helm-ignores-null claims = 0.**
Per §D2.8.5(ii): the C10 commit message stands VERBATIM, D26 stands with the appended
boundary clause (present in the worktree diff), FRICTION line 26 stands (names the hand-off,
not helm). No falsified cause survives → no MAJOR. One honest self-note: nothing in my record
above asserted either falsified theory; its "the chain drops nulls before helm" wording is
exactly the surviving adjudicated truth.

**(2) LIVE TRUTH RE-VERIFIED (FOCUS 1(c)).** origin/main is STILL `ec18281fb` (C09) — C10 is
NOT merged and the gpu-ai router is STILL DOWN (Deployment gen 49, available 0, unavailable 1,
template the broken pair `{amd.com/gpu, gpu-8060s}`; Pending pod 3eac8cad…). The §D2.8.1
correction is load-bearing for the hand-back: the "04:01 recovery" premise matches NOTHING on
this cluster (likely the GPU-cluster router — live-healthy, gen 22, Available=True since
17:50:43Z — or the ticket-side r2 approval). Node: bare `amd.com/gpu` at CAPACITY 0, pools 1/1
both UNALLOCATED, radiance still Pending (step 3 NOT yet run: strata 64Gi resident, free
59.92 < 64). My projection re-derivation on a fresh /tmp archive reproduces both production
shapes EXACTLY: gpu-ai → limits {gpu-8060s:1} + requests {gpu-8060s:1,cpu,memory}, generator
nulls NONE; gpu → limits {amd.com/gpu:1} requests {cpu,memory} — byte-matching the live
gpu-llama-swap template (the D26 limits-only witness), so **the rendered gpu pod is unchanged
by the carrier move — the shield's real meaning, proven carrier-independent, and the router's
cure is confirmed as the chart-side deletion + sync, nothing else.**

**(3) THE D26 FOLLOW-UP CARD — created and verified.** `Eev5WkDieH6TH2pEW` ("ApplicationSet→
Application hand-off strips null values (deletion instructions never reach Helm)"), Inbox per
the protocol. Body = the §D2.8.5(iii) corrected text (supersedes the chunks/C10.md:204
placeholder framing) — factually checked line-by-line against §D2.8 and re-verified against
my own live reads: the `{}` datum TRUE (read it myself), "every live Application null-free"
TRUE (3 apps censused), "helm honors nulls (coalesce.go/docs/offline render)" TRUE per
§D2.8.3, the title's "never reach Helm" is the surviving hand-off framing (NOT the falsified
helm-ignores reading). "Blast radius today: ZERO / every other consumer ADD-only" — consistent
with §D2.8 + my own repo scan (no live `amd.com/…: null` anywhere under services/ post-C10;
the two surviving generator nulls are exactly as the card says). No overstatement found.
Default-checked legs verified live: Services `infra`, Type `bug`, Model(s) `Qwen Flash`.
**ONE deviation to fix at run end: the card carries NO labels** (`label_ids` empty; parent
AD-143 carries `Provider: API` + `Pipeline: AI`) — the boards follow-up protocol says
parent-minus-`Research`. Unlabeled it derives the `default` pipeline (not `AI`) and its future
pickup owes a Provider kickoff question. Defensible as a separate hardening track, but if the
owner wants it on the AI lane, `set_card_labels` is the one-call patch.

**(4) FULL FRESH BAR (this addendum's runs, sequential, PATH-exported, dep-update /tmp-only):**
charts/llama-swap **498P/9S/0F** · charts/radiance **43P/0F** · charts/amd-gpu **29P/0F** ·
charts/vllm **36P/0F** · naming **5 ok bare** AND `AMD_GPU_FLIP_COMMIT=56142d5115…` **full
green** (WAVE-C + transfer: chart bare 1→0, gpu overlay +1) AND both teeth RED (bogus sha →
"is not a commit"; plans 1b89da994 → "matches NO accepted shape") · runbook **5 ok** · tp2
**3 ok** · dashboards **5 ok** · surface **9 ok bare** + explicit `M1 M2 M3 M4 M5 M6 M7 M8`
with `CF143_BASE_SHA=0d9b41785` → **10 ok** · helm lint ×4 (fresh /tmp archive) + both umbrella
renders rc0 · rulesync `generate --check` clean · aislop local-pin `ci --changes` 0/0/0/106 AND
`--base main` answered promptly rc0 (drift class did NOT recur; CI `@0.20.0 --changes --base
origin/main` form authoritative and passing per C09 r1).

**(5) GUARD-SCOPE ADJUDICATION (FOCUS 1(d)):** the null-retirement pattern is un-reintroducible
IN ITS CHANNEL — the render-side walk keeps BOTH clusters' llama-swap generator values null-free
(pre-projection — non-vacuous, verified), and the text-side scan catches any live
`amd.com/…: null` line in EVERY `services/*/*/values.yaml` (all categories, repo-wide within
services/). The scope is ADEQUATE because per-cluster deletion intent can ONLY be expressed in
service overlays — charts/ nulls are local helm semantics (honored at coalesce, proven by
§D2.8.3), not hand-off claims; a non-GPU key's null-retirement in some OTHER category's
overlay is the residual prose-only sliver, and its natural repo-wide home is the D26 card's
task (3) ("deletion-inherited-by-null banned pattern repo-wide") — recorded honestly, no gap
against this ticket's acceptance.

**(6) CARRY-LIST FINAL DISPOSITIONS (incl. the C09 r1 open questions answered):**
- M8 explicit-check-id law — **documented where it must be read: the surface.sh header itself
  (Usage block: bare = M1..M7; full set spelled verbatim; C01 AC6 rationale paragraph) + TEST_SPEC
  §12 run-posture.** The C09-r1 question "whether a FRICTION line is still owed": **NOT owed** —
  the header is the durable home, the second reader was cured by reading it, and this launch's
  own bar text now invokes the form correctly. (FRICTION keeps its four 2026-11-13 class-law
  lines + the re-statused aislop line; FRICTION line 26 confirmed standing per §D2.8.5(ii).)
- C09 Chart.yaml governance-header one-line fold — **ACCEPTED as Deferred** (row stays; the
  file has not been touched since; the authoritative corrected story is test-pinned values-side;
  no behavioral risk). Not demanded for merge.
- MINOR-2 strata :1348-1354 — **pointer adequate** (STATE.deferred names the exact range +
  TEST_SPEC §12.9 ledger + DECISIONS cutover line; region byte-frozen by C04/AC4, dies at the
  cutover anyway).
- NIT-2 (:278 "without a single-naming history") — accepted, dev-lane optional wording; the
  count-0 conjunct independently catches every real fallback (and §D2.2/§D2.8.1 live prove the
  0-retention story).
- NIT-3 PROVENANCE header direction — cosmetic, closed-by-parenthetical, concurred.
- D26 card — CREATED + body adequate; labels deviation above.
- Class laws: command/entrypoint-parity = TESTED (amd-gpu command/joint legs + radiance
  Entrypoint-witness with removal law); valuesObject-projection = TESTED (legs A/B/C + the
  transfer check + pre-projection null walk); owner-facing-commands-runnable-shape = TESTED
  (T5 shape pins, teeth both directions proven r2); patched-regex-byte-audit = PROSE-ONLY
  (FRICTION + §12.9 AMENDMENT item 1) — honestly flagged as the one law without an arm; it is
  a repair-recipe, not a checkable property; no CI arm is practical, no action owed.
- FR-2 "vendored" wordings — residual pair STILL live (radiance `test_resource_name_identity.py:36`
  docstring; naming.sh era-comment lines) — the C10 MINOR-1 fold correctly scoped itself to the
  null-retire law; one-word next-touch folds per STATE row.

**(7) GIT/SCOPE FINAL (unchanged conclusions, re-verified this pass):** per-commit audit of
e086638b4 (plans-only), b1def8d1f (exactly C09's 11-file set), 1b89da994 (plans-only),
56142d511 (13-file WAVE-C), 4652671fd (records-only) — all scope-coherent; the uncommitted
delta now is three records files (EXPLORE §D2.8, DECISIONS D26-amendment, my two plan records)
— records-only by class. Amend lawful: `origin` has no cf-143 ref, 698af3b78 unreferenced and
NOT an ancestor, `main == origin/main == ec18281fb` untouched by any agent write. Removed-
assertion sweep (C09+C10 test files): every deletion classified — ruled carrier flips with
stronger inverse guards (legs A/B/C + WAVE-C transfer + repo-wide amd.com null scan), re-embedded
prior shapes (zero-diff for WAVE-A/B), comment/message rewords; the off-parity re-baseline stays
EXACTLY the 2 sanctioned transferred lines with its PROVENANCE era entry; no weakening anywhere.
Tree clean apart from the records files.

**(8) OWNER HAND-BACK — ORDER (supersedes nothing above, completes it):**
1. **MERGE + SYNC 56142d511 (+ 1b89da994/4652671fd records) — this is the router's ONLY cure.**
   main lacks it (verified live: origin/main still ec18281fb = C09). Nothing else — not a retry,
   not a sync refresh, not step 3 — moves a capacity-0 pool (§D2.8.2).
2. **AC7 receipt sequence, in order:** (i) router pod Running on `amd.com/gpu-8060s`
   (Recreate replacement; llama.spencerslab.com back — expect within ~seconds of sync + a cold-
   load watch per the runbook); (ii) node check: `gpu-r9700-1: 1` + `gpu-8060s: 1`, bare
   `amd.com/gpu` at COUNT 0 — already true live, re-confirm post-sync it stays; (iii) radiance
   schedules ONLY after step 3: suspend auto-sync for gpu-ai-llama-swap in the ArgoCD UI first,
   then OWNER `kubectl -n default scale deploy/gpu-ai-llama-swap-strata --replicas=0` (free
   59.92 → 123.92 ≥ 64; do NOT touch guaranteedMemoryGi to clear this Pending); (iv) the
   8-session gate at full sizing (runbook step 6, STARTUP REPORT receipts); (v) the receipt-
   gated 64 → 68/72 (→ ~96 max, strata-down only) ladder — one-scalar edits.
3. **Owner decisions outstanding:** the limits-only word (live gpu pod proves the transfer
   byte-exact; overrule = one line + leg-B re-pin); the upstream naming-feature ask filing
   (D24, optional); D26 card `Eev5WkDieH6TH2pEW` triage (its Inbox landing is per protocol;
   decide the labels: AI lane needs the parent-minus-Research label patch); moving AD-143
   Executing→Review→**Finished** stays the owner's alone — the branch's work is complete at
   chunk and final-review level, all ten chunks APPROVED, the ticket-wide bar green.

— final reviewer round 3 ADDENDUM, 2026-11-13 (same reviewer session line: fresh bars re-run;
§D2.8 + D26-amendment audited as records; D26 card verified against the live datum; no
implementation or validation file edited; /tmp-only dep updates; readonly-tier cluster reads).

## FINAL whole-plan review round 5 (C12+C13 live deltas + landed-state verification) —
2026-11-14, fresh planning-tier session, HEAD bf950d22a, main == origin/main == da46cee2e

**Verdict: APPROVED.** Zero blockers, zero majors. Rounds 1–4 stand; C09–C13 — the four LIVE
re-opens — re-verified against the cluster as it runs NOW (readonly tier only), every bar fresh
and sequential, every arithmetic line re-derived by this reviewer, and the removed-assertion
sweep across the whole live-round window came back CLEAN.

**TICKET-WIDE BAR (all exact):** charts/llama-swap **498P/9S/0F** (9 skips = standing
RUN_HF_CHECK/RUN_FLAG_AUDIT gates) · charts/radiance **46P/0F** (43 + C11's three grammar legs)
· charts/amd-gpu **29P/0F** · charts/vllm **36P/0F** · amd-gpu-naming **5 ok bare**;
`AMD_GPU_FLIP_COMMIT=384e3135e` → **NON-FLIP green** (census-unchanged wording); historical
re-proofs at the REAL commits — a81989b47→WAVE-A, b1def8d1f→WAVE-B, 56142d511→WAVE-C; bogus sha
**RED**; claim-drop synthetic (services/gpu bare ADD deleted in a /tmp clone) **RED naming the
carrier law** · runbook **5 ok** (805 lines) · host-tuning **4 ok** (new C12 suite) · tp2 **3 ok**
· dashboards **5 ok** · surface **9 ok bare** + explicit `M1..M8` @`CF143_BASE_SHA=0d9b41785`
**10 ok** (the M8 explicit-check-id law now documented in the script's own Usage header + TEST_SPEC
§12 posture — re-confirmed, no FRICTION line owed) · helm lint ×4 + both umbrella renders (fresh
/tmp archive + dep-updates /tmp-only) 0 failed · rulesync `--check` clean · aislop local-pin
`ci --changes` 0/0/0/106. Repo tree clean after every run.

**FOCUS 1 — THE LANDED, LIVE TRUTH (readonly MCP, this session).** Device-plugin DS 1/1
Ready with `command [/root/k8s-device-plugin]` + the exact 4 args (C09). Node `ai-gpu`:
`amd.com/gpu-r9700-1: 1` + `amd.com/gpu-8060s: 1`, bare `amd.com/gpu` capacity **"0"** — the
count-0 state the C13-corrected runbook teaches. **Router `gpu-ai-llama-swap` AVAILABLE (1),
template APU-pair only** — the C10 cure landed (recovered 13:32:43Z, round-4 record; my own
live read agrees), and its Application sits **OutOfSync with NO automated policy** (syncPolicy
= syncOptions only, last op manual Succeeded) — that OutOfSync IS the DESIGNED parked scale-down
(strata `replicas: 0` survives only while unsynced; the 16:29:51Z click precedent proved any
sync re-applies git). Radiance pod `gpu-ai-radiance-5f7d6b95d7-4fccz`: **Running 17:20:05Z,
QoS Guaranteed, 0 restarts, 110Gi requests==limits BOTH maps + gpu-r9700-1 1==1, init pair
1000m/2Gi, radiance-fetch terminated (marker-skip path, hash passed)**. Its startup report
reprints exactly the §R8/§R9 record: `ttm.pages_limit 112.00 GiB | pinned by this process
71.04 GiB`, `kv cache 4.49 GiB a card: 1600000 tokens, 8.0 sessions at 200000`, FINDINGS =
1 warning + 4 notes (experts-from-host 41.52 GiB, link-capped, memlock 8.00 MiB, governor
powersave) — and the warning STILL reads `link-below-max: 8.0 GT/s x4 of its 16.0 GT/s x4`:
**the crashloop AND OOM classes are dead; the rate is STILL the owner's open complaint**
(freshest receipt `req … done … gen=884 ttft=13.42s 12.4 tok/s`), and per §R9/D33 its fix is
the owner-lane link item (BIOS per-slot speed pin / cable / dock power sequence), not the repo.
NOT yet closed by evidence, honestly listed: runbook **step 6's 8-session gate + §R8 capture
keys** (the one known open AC), the Q11 co-existence metrics window (owner observation), and
the cutover decision below.

**FOCUS 2 — C12+C13 AS RECORDS:** (a) render diff `56142d511..384e3135e` = exactly the init-gate
rewrite, `cpu 200m→1000m`, `memory 64Gi→110Gi ×2` — claims/marker-skip/`--continue-at` intact;
C13's own values edit is **comment-only (0-line render diff re-derived)**; my arithmetic
independently reproduces every sum: 110+4.125+1.158=**115.283 ≤ 125.08, free 9.80**;
110+64+6.3=**180.3 > 125.08** (the inverted either/or — restore-back needs radiance off first);
110−71.04=**38.96 ≥ 4**; 71.04+47.68=**118.72 > 110** (RAM tier dead); 71.04+21+4=**96.04 ≤ 110**
(§R8); and the figure from first principles: 121,969,901,568 B ÷ 150–350 MB/s = **5.8–13.6 min**
(≡ §D4's ÷5) ✓. (b) step-3/step-10 prose verified live-true AS WRITTEN; my two re-syntheses
went RED with exact names: the old "suspend auto-sync" instruction → "INSTRUCTS a suspend/resume";
a reversed restore (strata-back sentence before radiance-off) → "reaches the strata/sync step
BEFORE radiance's 110 request leaves the node" — and the base doc stays 5 ok; the :486
residual-clause ban + capture-key arms (memory.peak/oom_kill/file≈0 present ×2) pin the rest.
(c) NO stale 8–23 satisfaction token survives anywhere: the five repo-wide hits are all
correction-annotations (values:392 historical note + the two suites' split-arm comments); docs
carry 5.8–13.6 in all three carriers (T4/T5 two-half pins green). (d) §R9 fiction fold in the
branch doc is complete — "no switch, no retimer" asserted, c2/c3 attributed to the card's OWN
integrated Navi pair, the engine's "clears on reboot" advice marked WITNESSED-FALSE (:42–:74);
the existence law lives in FRICTION with resolution. **BUT: main's copy of the tuning note still
says "reseat/inspect … cable or the retimer" (:59) — the fold is branch-side ONLY, and NOTHING
in CI pressures it (no arm forbids the token; the doc isn't a rendered surface): see the
residual-delta section — this is now the single most urgent branch→main landing.** (e) The five
tuning arms state only receipt-supported truth: 3.42<5 recorded (not met), 118.72 kill-sum,
sandbox-vs-container memlock read (16787369984 = PAUSE-SANDBOX limit; crictl route),
O_DIRECT-never-page-cache (D30(3)), `amd_iommu=off` supersession + the amdxdna/NPU side effect,
governor persistence-not-proven with "MOST PROBABLY" body-strength (suite proven strength-blind,
NO arm invented) — each cross-checked against §D6/§R8/§R9; T4's two-doc coherence arm keeps them
locked.

**FOCUS 3 — GOAL-VS-CARD, five live rounds on:** card intent delivered and LANDED: radiance
deployed beside strata (Q5 — strata kept, parked; cutover still the owner's metrics call), vllm
disabled commented (0 live rows, golden 0 hits byte-equal main↔HEAD, 83-row era + C05 trio = 86
live, circle-back markers untouched), TP2 documented (card #1 body verified post-rename but
STALE AGAIN — no 110/5.8 tokens; third re-publish owed, same-artifact law), Grafana deferred
(card #2 in Inbox), priority handled (9/5/1 + floor 5 + M8). C01–C08 guarantees hold post-
C09–C13: suites green = the whole prior contract re-proven (vllm disable, full 8×200K profile +
Guaranteed, peers.radiance, catalog trio, runbook completeness, shield — the gpu cluster's bare
claim now arrives via its OVERLAY ADD, and the RENDERED gpu pod is unchanged, which is what the
D21 intent actually requires; naming n2/n3 + the 498P carry it), first-party amd-gpu + patched
table re-verified (rendered sha **864da8694ab5**/455B == runbook :273 pin; fixtures untouched
since C08/C09 additions), zero-stale sweep clean (old literal records-only; impossible literal
nowhere claim-shaped).

**FOCUS 4 — RECORDS + GIT:** STATE parses; 13 rows; plan_status approved (pending this
verdict); 16 honest null-session rows; per-commit audit of the window CLEAN — e086638b4/a533048fd/
1aceb102f/9248151c9/446fc73e2/627a2fdd0/94b143ee8/b09764ab0/cf037ef07 records-only; b71c8dfac =
C11's 6-file set; 027d3b4ee 11; ec92229ce 4 (fix-round scope); 384e3135e 9 (C13 wave);
bf950d22a 4 (fiction fold + records). The amend/landing history is lawful: no cf-143 ref on
origin, branch has no upstream, main moved ONLY via the owner's own cherry-picks/rebases (twins
verified content-equivalent by the C12 r2 review + my own byte-comparisons), zero agent pushes.
Removed-lines sweep `4652671fd..HEAD`: every deletion is a 64-era budget/gate line replaced by
its 110-based equal-or-stronger successor, or C10's already-adjudicated re-pin (off-parity/
evidence fixtures moved ZERO lines this window — C12 touched no llama-swap render surface);
C11's grammar suite + C13's split-arm needles are net-new enforcement. **No weakening; the only
fixture move in the whole live-round window remains the sanctioned C10 off-parity re-baseline.**
Records folds for coord (non-gating): (1) C13 row `in_review` → done + C12/C13 `commit` fields
(027d3b4ee+ec92229ce / 384e3135e+bf950d22a); (2) RESEARCH:777 SUPERSEDED annotation on the
12.5 MB/token line (D30(2)/§D8's ~16–18 KiB/token) still OWED; (3) C13 r1 minor-1's §12.13
wrap/exemption-sensitivity sentence → test lane at the notes-suite's next touch; (4) the
STATE.deferred Q12 row's "shipped 64Gi" phrase is era-stale (history line, harmless).
Prose-only-laws audit (the class we keep hitting): FOUR of the new laws are arm-backed —
image-grammar (radiance suite: family set + digest seed + long-option bans + exit<touch order),
budget-sum (T2 scalars both-sides + T4 coherence + suite SCALARS), probe-falsification
(the corrected claims themselves are pinned), sync-guard-shape (AC4's (a)/(b)/(c)/(e) arms +
figure split-arms); THREE remain prose BY NATURE or by ruling — the existence law (a
token-presence test structurally cannot catch naming a nonexistent device: honestly un-armable,
though a cheap NEGATIVE needle — ban "the retimer" as advice — is now justified precisely because
main still carries the fiction; recommend it with the doc landing), the marker line-adjacency
class (a repair recipe, not a property), and the governor strength-blinding (deliberate: r2
proved the suite blind BOTH directions and NO arm was invented — right call).

**RESIDUAL BRANCH-vs-MAIN DELTA (what to merge):** implementation + runbook + TP2 + tuning
PRE-fictive-copy + every suite are ALREADY IN MAIN (content hashes byte-equal — golden, values,
runbook, naming, radiance suites). What main lacks: (1) the **fiction-fold tuning doc**
(bf95022a — the retimer/Navi/witnessed-false corrections; owner-facing doc hazard live on main
until landed), (2) the branch's own **cf-143 records delta** (plan deltas 4–6 + FINAL r3–r5
records, STATE/DECISIONS/D26-amendment/EXPLORE §D3–§D8/RESEARCH §R8–§R9 + the C13 chunk records)
— records ride the same landing PR; and main additionally carries cf-135 files the branch lacks
(the D30(7) no-rebase ruling stands: zero intersection, branch records keep their SHAs).

**COMPLETE-EXCEPT:** the ticket is COMPLETE except (a) the owner's runbook **step 6** 8-session
gate + capture keys (the ticket's last open AC), and (b) the **run-end card actions**: card #1
re-publish (third TP2 move), XFS/ext4 storage-lane card, fleet selfHeal-prose card (D32(4) body
line), the D26 card ALREADY filed+labelled (verified live, labels now present), plus the fiction-
fold landing. Nothing else in the ten-round review history remains open.

**OWNER HAND-BACK:** merge the branch remainder (tuning-doc fold + records; docs-only, zero
sync impact beyond nothing — no rendered surface moves; the landing is safe any time, DON'T
sync anything else meanwhile). Receipt sequence for normal operation, in order: (1) router stays
Running on gpu-8060s ✓ live — do NOT sync gpu-ai-llama-swap while strata is parked (the
OutOfSync you see is the parked scale-down, by design); (2) node pools ✓ bare-0 live;
(3) for radiance use: step 3 (scale strata 0 — already parked; 115.28 fits with 9.80 free) ✓
live; (4) **step 6: run the 8-session gate** with §R8 capture keys (memory.peak ≤100,
oom_kill=0, file≈0, MemAvailable ≥8, pinned 71–78 window — receipts close D30(4)); the ladder
UP stays capped by D29's envelope (~96 was the documented ceiling before the 110 ruling — the
110 already contains it; a step-down only via pool/ctx, never the scalar below 71.04+4);
(5) restore is the ORDERED, either/or law: radiance's 110 off the node FIRST, then sync +
strata back (180.3 > 125.08). OPEN DECISIONS (owner's alone): the limits-only word (D26 shape —
live gpu pod still proves it byte-exact; overrule = one line + leg-B re-pin); the D24 upstream
naming-ask filing (still optional, still open); the cutover — at 110 the strata co-residency is
arithmetically dead (D29's "real either/or" + §R8-Q5: TP2's ~30–35 re-pin may RE-OPEN
co-existence ≈104.3 — the cutover ticket's call); AD-146 (D26 card) triage + the two new cards'
prioritization; gpu-box spec-drift card (28.60 GiB truth vs the 64-era notes); the owner-lane
link fix (BIOS per-slot Gen4 pin / cable / power sequence — the ONLY thing that moves the
12.4 tok/s today; 110 provably cannot — pinned 71.04 at both caps, §D8); and AD-143's move to
Finished stays theirs.

— final reviewer round 5, 2026-11-14 (fresh session; no implementation or validation file
edited; sole write = this record; dep-updates/renders/synthetics in /tmp; cluster reads
readonly-tier only; repo tree verified clean post-runs).

---

## Rework delta 4 — live defect C11 (BusyBox checksum grammar) — 2026-11-13, appended per owner report
Third live-defect round (C09 §D1, C10 §D2, C11 §D3/§D3b). The fetch-init's completion gate is
GNU grammar (`sha256sum --check`) inside an Alpine/BusyBox image — long-option parse dies at
exit 1, `set -e` skips the marker, pod CrashLoops on 1-second no-op iterations while the
113.6 GiB pack is COMPLETE (size-proven, never yet hash-proven). The "timeout/stall" premise
was refuted by the same scout round (§D3; first scout launch cancelled by the user, re-run
produced §D3b — both recorded honestly). Authority: EXPLORE §D3b; ledger D27. plan_status
reopened complete→approved for this delta.

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C11 | fetch-init checksum gate → portable shell-EQUALITY form (+WHY comment, grammar-leg suite law, runbook carrier) | S | 8 | [C10] | repairs C02's authored line as shipped through C08-C10's world; live closure chains after C10's router recovery + step 3 |

Wave 8: C11 (alone). One-site fix `charts/radiance/values.yaml:346` per §D3b.4's verbatim
replacement block; rejected shapes recorded with source reasons (`-c -s` GNU-has-no-`-s`;
`-c -` coarser-not-chosen; extra `[ -s ]` guard unnecessary — empty-actual covers the
missing-file case). Commands additions (beyond the standing battery): the render-diff proof
that ONLY the init command string moved (claim pair, curl line, D15 QoS byte-kept);
`AMD_GPU_FLIP_COMMIT=<C11 sha>` => **NON-FLIP** acceptance (new n2 class — census of claim
lines unchanged, carrier files untouched; WAVE-E deliberately NOT minted); the red-first
grammar legs (`--`-ban on hash-applet lines gated on busybox-family IMAGE IDENTITY +
digest-ledger pin + positive equality/MISMATCH/marker-order arms) go green only with the
fix; radiance suite 43P+legs/0F, witnesses 498P-9S/29P/36P unmoved; zero-stale sweep
re-run (names frozen). Live closure owner-run (AC6): one minutes-class sha256 pass,
marker lands, serve container pulls + boots; the host-side hash+marker-touch stays the
human-only same-verification loop-breaker, never a substitute for the chart fix.

---

## FINAL whole-plan review round 4 (C11 + landed-state verification) — 2026-11-13, fresh
planning-tier session, HEAD `cf037ef07`; **main == origin/main == `de02e1884`** (the owner
has already cherry-picked + pushed C10-rehash and the C11 landing).

**Verdict: APPROVED.** Zero blockers, zero majors. C11 re-verified bar-for-bar AND against
the LANDED truth on the live cluster (readonly tier only); the C09/C10/C11 live-defect
CLASS adjudicated as a pair; all four r1 carries dispositioned below.

**Bars (all run fresh, sequential, PATH-exported, dep-update /tmp-clone-only):**
charts/llama-swap **498P/9S/0F** (9 skips enumerated by name = 8× RUN_HF_CHECK +
1× RUN_FLAG_AUDIT network-evidence gates, zero helm-skips) · charts/radiance **46P/0F**
(`-k staging` = 4 legs RUN-and-pass, not skipped) · charts/amd-gpu **29P/0F** · charts/vllm
**36P/0F** · naming **5 ok bare** AND `AMD_GPU_FLIP_COMMIT=b71c8dfac…` **full green with n2
NON-FLIP** (class message printed verbatim: "no carrier file touched; amd.com/gpu* claim
census unchanged across the commit's files — C11 grammar fix, D27") · historical
re-proofs: a81989b47→**WAVE-A**, b1def8d1f→**WAVE-B**, 698af3b78→**WAVE-C** all ok ·
bogus sha → **FAIL "is not a commit"** rc1 · **teeth re-synthesized in the /tmp clone**:
claim-dropping commit touching NO carrier → **"matches NO accepted shape" REJECT**;
comment-only CARRIER-touch without a wave → same REJECT (NON-FLIP correctly unavailable);
clone restored byte-clean · runbook **5 ok** · tp2 **3 ok** · dashboards **5 ok** · surface
**9 ok bare** + `CF143_BASE_SHA=0d9b41785 … M1..M8` **10 ok** · `helm lint` ×4 charts
0 failed · both umbrella renders rc0 · rulesync `generate --check` clean @**37.0.0** ·
aislop `ci --changes` **0 errors/0 warnings/0 fixable over 106 files** @**0.20.1**. Tree
clean after every run (`git status --porcelain` = 0).

**FOCUS A — C11 as a PAIR with C09/C10 (the "contract lives one layer below where the tests
read" class; third confirmation):**
(a) *Grammar first-hand*: rendered `command[2]` read line-by-line AND scanned — exactly ONE
hash-applet invocation on an executable line (`actual=$(sha256sum "$PACK" | cut -d' ' -f1)`,
zero options); NO GNU long option and none of the D27-rejected forms (`--check/--status/-cs/
-c -s/lone -s/-w/operand-less -c`) on ANY executable line. Long-option occurrences
classified: line 16 curl's REAL flags (full curl binary, not the coreutils-applet family —
legit, byte-kept); `--check` at the WHY-comment and `--continue-at` in the rc-33 comment —
`#`-lines, inert to `sh`. The equality form EMPIRICALLY proven in a /tmp harness with
both-family stubs (BB stub rejects long opts exit-1 + two-space compute print + `can't
open` on missing; GNU shim honours `--check` stdin): correct digest ⇒ `complete` + rc0 +
marker; TRUNCATED pack ⇒ MISMATCH naming expected= AND actual=, rc1, NO marker; MISSING pack
⇒ stderr + `actual=` EMPTY ⇒ MISMATCH rc1 NO marker — `set -e` does NOT abort at the
assignment (pipeline rc = `cut`'s 0) — exactly D27's adjudication; GNU family + same script
⇒ passes (portability both ways). The OLD gate under the BB stub reproduces the live defect
verbatim (`unrecognized option: check`, rc1, no marker) and under the GNU stub would have
PASSED — the proof that the family premise, not the script text, carries the contract.
(b) *Digest pin verified LIVE and INDEPENDENTLY*: new pod `gpu-ai-radiance-7b4b757fff-dnfbf`
initContainerStatuses imageID = `sha256:3fb7e13e5d17…` — full-64-hex EXACT match to the
values ledger pin; registry re-read by this reviewer: Docker Hub `8.23.0`
`Docker-Content-Digest` = the same value with content-type
`manifest.list.v2+json` (⇒ NIT-1's descriptor point proven — see carries); amd64 platform
manifest = `3b8fde20…` (NOT what is pinned, and correctly so — imageID is the index digest).
VACUITY test re-run on the /tmp clone: repository → `docker.io/library/ubuntu` ⇒ BOTH
`…image_identity_pinned_and_digest_ledged` AND `…grammar_matches_the_init_image_applets`
RED — the ban refuses to pass vacuously on an unruled family ✓.
(c) *Class coverage beyond radiance (own grep, classified)*: executable hash-applet call
sites repo-side = radiance:357 (portable form) + `containers/coder-workspace/Dockerfile` +
`containers/forgejo-host-runner/Dockerfile` — all `sha256sum -c -`/`-c file` (SHORT option +
explicit operand = portable BOTH families, and build-time GNU anyway — doubly legit); busybox/
alpine-family `repository:` sites = playsms (busybox:stable, 0 long opts), prowlarr
(alpine, 0 long opts), privatebin (app image, no shell init), radiance (fixed).
`--checkpoint-interval` (engine arg), `git apply --check` (GNU git at build), rulesync/aislop
(dev CI) stay classified non-class per §D3b.7. Verdict: no second live site of the class.
(d) *Curl line*: `git show <rev>:charts/radiance/values.yaml | grep 'curl --fail'` at
72770056e (C02-era), 56142d511, b71c8dfac, de02e1884 and the LIVE pod spec = ONE unique
byte-identical line; no `--max-time`/speed/timeout flags crept anywhere — the NOT-A-TIMEOUT
adjudication is honored in bytes, and the live log proves the resume no-op (~2 s) as
designed.

**FOCUS B — LANDED-STATE TRUTH (all reads readonly; zero mutations by this session):**
(1) **C09 live-good**: DS `gpu-ai-amd-gpu-device-plugin-daemonset` 1/1 ready, container
`command: ["/root/k8s-device-plugin"]` + the EXACT 4-item args, image 1.31.0.12.
(2) **ROUTER RECOVERED — AC7's first receipt**: sync id **137** (initiatedBy `tms@…`)
deployed revision `dc3570741` (carries C10 `dc69d64ec`) at 13:32:08Z → new pod
`…6796d989db-l5b74` created 13:32:11Z, Deployment **Available=True at 13:32:43Z** (the
outage began 01:52:09Z — recovered after 11h40m34s, exactly on C10's landing sync). Live
pod limits **EXACTLY {amd.com/gpu-8060s: 1}**, requests mirror {gpu-8060s:1, cpu:1,
memory:4Gi}, ZERO bare claim; Application `gpu-ai-llama-swap` valuesObject = APU-only pair,
null-free. The app now reports **OutOfSync with Health=Healthy** — the witness is the
STRATA Deployment's live `replicas: 0` vs the git-rendered 1: that is the owner's
runbook-step-3 manual scale-down (see (3)), i.e. the DESIGNED posture, not a sync gap —
syncs are manual here (ids 137/138 both `tms`).
(3) **RADIANCE — step 3 ALREADY RUN, init in its first-ever hash pass**: the owner scaled
`gpu-ai-llama-swap-strata` to **0** (live receipted). New pod `…7b4b757fff-dnfbf` (the
C11-fixed template) hit `FailedScheduling Insufficient memory` at 13:38:18+13:38:28 (the
old crashlooping pod still held the 64Gi reservation under Recreate), **Scheduled 13:38:47Z**
once the replacement rolled, `radiance-fetch` RUNNING since 13:38:48Z — **restartCount 0,
no MISMATCH line, no crashloop signature** (vs the 1-second-exit iterations of §D3b.2): the
`sha256sum --check` wedge is empirically GONE and the one minutes-class full-pack hash pass
(~15 min at read time 13:53:45Z, disk-bound single-thread reading the 113.6 GiB — slower
than the 1–6 min envelope, still in-envelope) is the FIRST hash-verification these bytes
ever receive, with zero re-download (log shows the resume-from-121,969,901,568 no-op
exactly as designed). Serve container `PodInitializing`, `imageID: ""` — the engine pull
awaits init completion, per contract. Application `gpu-ai-radiance` **Synced @de02e1884**;
Argo health currently `Degraded` = the §D3-adjudicated `progressDeadlineSeconds: 600`
condition theater while a legitimately-long init runs — NOT the crashloop signature;
the AC6 closure receipts (marker `.staged-0af5e962…` + "radiance staging: complete" +
exit 0 + serve pull/boot under the 180×10 s startupProbe) land within minutes of the pass
finishing and are the owner's next-window read (or the next coord tick's), per the
owner-run closure law. fsGroup warning (`AlreadyMountedVolume`, GID 0 vs 65532
"may not be shareable") observed — kubelet informational; the pack+marker writes belong to
the same init that already wrote 113.6 GiB successfully — watch item, not a finding.
(4) **Node pools**: `amd.com/gpu-r9700-1: 1` + `amd.com/gpu-8060s: 1`, bare `amd.com/gpu`
at **capacity 0** (the count-0 reading the C10 docs teach), allocatable 125.08Gi — all as
ruled. (5) **gpu cluster untouched**: `gpu-llama-swap` 1/1 Available at gen **22** (the
pre-C10 gen), rendered template EXACTLY limits `{amd.com/gpu: 1}` + requests `{cpu, memory}`
(live pod additionally shows the API-server-defaulted `amd.com/gpu` requests entry —
extended-resource defaulting at pod admission, the template is unchanged — this refines,
without contradicting, round 3's template-side witness); `gpu-amd-gpu` external entry
Synced/Healthy. The `gpu` umbrella app shows OutOfSync (child apps already carry the
C10-era content; umbrella re-sync is the owner's manual lane) — receipt nuance, not a
branch fault.

**FOCUS C — goal-vs-card re-derivation after three live rounds (board reads):** radiance
LIVES BESIDE strata per Q5 (peer block live in valuesObject, models list intact; strata's
0-replica is the owner's Q10 scale-down, restore-back is step 9/10 theirs) · vllm
disabled-commented (M3/M4 green) · 9/5/1 higher-wins trio + floor `priority?: 5` (M8 green)
· FULL 8×200K profile shipped and now being exercised (64Gi + full serveArgs + Q12 ladder
rulers live) · TP2 doc + **card #1 AD-144 "Radiance second-GPU (TP2) expansion"** — Inbox,
`Provider: API`+`Pipeline: AI`, body RE-PUBLISHED POST-RENAME: 10× `gpu-r9700-1`, ZERO
`gpu-ai-pro-r9700`, no null-mechanism prose ✓ · **card #2 AD-145 "Radiance Grafana
dashboard + metrics scrape wiring"** — Inbox, labels ✓ · **D26 card AD-146
`Eev5WkDieH6TH2pEW`** — Inbox, **labels now APPLIED** (closes round 3's one-label
deviation; `set_card_labels` was run), body = the §D2.8.5(iii) corrected framing: it names
the HAND-OFF strip, HELM-EXONERATED, "never retired normatively / NOT staleness" — NO card
describes null-retirement as the mechanism ✓; only stale pointer found (cosmetic): its
reference-implementation cites `56142d511` (branch sha) while main carries the re-hash
`dc69d64ec` — both reachable, same content. AD-143 sits in **Executing** with the slug
custom-field naming this session ✓; its body is the original intake sketch (predates the
rename/conversion rulings) — per the boards law the card body is human intake, the plan
folder is the record — no write-back owed beyond the Review move below.

**FOCUS D — git/scope:** per-commit audit: a533048fd = plan-folder-only 6 files · b71c8dfac
= exactly the 6 contracted files (2 dev + 4 test-wave) · cf037ef07 = 3 records files ·
owner's landings `cf14837ed`/`de02e1884` are cherry-picks with **patch-ids IDENTICAL** to
their branch twins (verified by hash) and **main == HEAD implementation-content: 0 lines
of diff** across charts/ services/ tests/ containers/ .agents/notes/ .github/ custom-values/
.opencode/ .rulesync/ — the residual `main..HEAD` delta is **EXACTLY cf037ef07's records**
(STATE +30, FRICTION +2, chunks/C11.md +48 — the C11 fold the coord owes main) **plus this
round's record below**. main advanced only by owner commits (committer `Spencer` on every
landing) — no agent merge/push: `origin` carries no cf-143 ref, branch never pushed; the
earlier amend (698af3b78→56142d511) stays lawful (unpushed, unreferenced). Test-integrity:
every removed line across the three landed fix-commits re-enumerated by this reviewer —
C11: **4 deletions, ZERO in test files** (old gate line + 2 comment tails + 1 runbook
sentence); C09 test deletions = comment/docstring rewords + the n2 message reword (inverse
guards shipped); C10 test deletions = the D26-ruled carrier flip (legs A/B/C + WAVE-C
transfer + null-absence scan shipped STRICTLY stronger) + re-embedded prior shapes; the
off-parity fixture moved **EXACTLY the 2 sanctioned transferred lines, 0 added**, with its
cf-143 era-chain PROVENANCE entry present on main. **No weakening anywhere.** Clone/tree
verified byte-clean after every probe.

**Carry dispositions (C11 r1 → FINAL):**
- **NIT-2 (grammar-ban line-scoping): ACCEPTED AS A RECORDED FORWARD ITEM — hardening NOT
  demanded now.** My synthesis proves the hole exactly as described (smuggled
  `sha256sum \` + next-line `--check` passes all legs) — and proves the legs are
  CONTRACT-CONFORMANT (§D3b.5 defines the ban per-line; demanding continuation-join now
  would be a test-lane SCOPE EXPANSION mid-FINAL, minor/nit never gates per the role law,
  and the positive equality leg still pins the shipped gate — a smuggled SECOND gate cannot
  delete the first). Forward item for the next test wave touching this chart: join
  `\`-continuations before scanning OR assert exactly-one hash-applet invocation on
  executable lines. Coord: add as a STATE.deferred row.
- **NIT-1 (values.yaml:318 "amd64 IMAGE-MANIFEST digest"): DEFERRED one-word fold —
  confirmed and independentized** (my own registry read: the pinned 3fb7e13e… is the tag's
  MANIFEST-LIST/index digest == what containerd records as imageID; the amd64 platform
  manifest is 3b8fde20…). Value, pin role and premise-leg all verified correct; the
  descriptor rides any future values.yaml touch (owner may also fold it into the PR
  narrative). Not blocking: a fold NOW = history churn on a just-pushed main.
- **MINOR-1 (commit-message payload): record-do-not-amend CONFIRMED — and now doubly:**
  `de02e1884` is on origin/main; amending would mean rewriting pushed main, the repo's
  single most forbidden act. The owner-facing PR/merge narrative paragraph (source:
  chunks/C11.md notes + D27/§D3b) — to append to the AD-143 merge text: *"The fetch-init's
  completion gate was `sha256sum --check` — GNU long-option grammar inside
  curlimages/curl:8.23.0, whose coreutils are BusyBox v1.37.0 (the container's own banner;
  hash applets declare short `scwbt` only, `md5_sha1_sum.c`), so the gate died at option
  parse (exit 1), `set -e` skipped `touch "$MARKER"`, and the pod crashlooped while the
  113.6 GiB pack was COMPLETE (resume offset == ledger size 121,969,901,568; triple-matched
  x-linked-etag/HF-tree/ledger) yet NEVER hash-verified. Fix: the portable compute+compare
  equality gate — `actual=$(sha256sum "$PACK" | cut -d' ' -f1)` + MISMATCH echo naming
  BOTH digests + `exit 1` strictly before the marker-touch — the only shape both applet
  families pass loudly. Rejected with source reasons: `-c -s`/`-cs` (BusyBox-only, GNU has
  no short `-s` — breaks an image swap), `-c -` (portable but names only the file on
  failure — coarser, not chosen), an extra `[ -s ]` guard (a missing pack yields an empty
  actual — the equality already catches it). NOT a timeout — the curl line is byte-unchanged,
  no timeout flags added. Cost from today: zero re-download + one minutes-class sha256
  pass (the bytes' first-ever verification); every later restart marker-skips <1 s. Also
  pins the init-image family's digest (sha256:3fb7e13e… = the tag manifest-list digest =
  the live imageID) as the grammar's PREMISE — a family swap now reddens the premise leg
  instead of passing the ban vacuously. Honesty: authored at C02, survived four green
  reviews because every leg checked the script's VOCABULARY, never its GRAMMAR against the
  pinned image's applet family (class law: TEST_SPEC §12.10 / D27 / FRICTION)."*
- **Records-fold status: ADEQUATE, with two coord residuals.** STATE's C11 rows match
  chunks/C11.md r1 notes line-for-line (verdict, per-bar counts — every number reproduced
  identically by this fresh run; dev/tests handoffs carry real session ids read from tool
  results; review row `session: null` + `session_note` + `review_session_note` name exactly
  what is evidenced (disk notes) and what is unknown — the correct shape per the same
  honesty law; NOT treated as an unrun review). FRICTION class law is where future agents
  read it: the C11 line + the coord second-sighting line are on main? NO — they live in
  `cf037ef07` (branch-side records fold, still residual; the FRICTION/STATE/C11-notes delta
  is precisely the main-vs-branch gap). TEST_SPEC §12.10 + DECISIONS D27 ARE on main (they
  rode the fix/plan commits). Coord residuals to fold next: (i) STATE.deferred rows for
  NIT-1/NIT-2/MINOR-1 dispositions; (ii) the D26 deferred row still reads "IN FLIGHT this
  round" — CLOSE it (card AD-146 created + labels applied, receipted by this round).

**Residual delta main-vs-branch (stated precisely):** `cf037ef07` (C11 records fold: 3 plan-
folder files) + this round's record = the whole of `main..HEAD`; implementation content
0-diff. Landing them is the owner's cherry-pick/merge lane, same as every prior round.

**Owner decision list (unchanged heads, updated states):** (1) the limits-only word —
gpu-cluster witness REFINED this round (template limits-only + pod-admission defaulting —
the byte-neutral transfer holds); (2) D24 upstream naming ask — still an optional filing;
(3) D26/AD-146 card triage — now label-clean in Inbox, decide AI-lane pickup; (4) NIT-1
one-word fold + NIT-2 test-lane hardening — record-and-ride (this round's dispositions) or
demand a follow-up; (5) **AD-143 Executing→Review — yours**; Finished stays yours; the
restore-back of strata after radiance testing (runbook step 9/10) and the Q12 ladder are
likewise your live lanes. Watch-items: the first hash pass' terminal receipt (marker +
complete + serve boot) and the fsGroup warning at init completion.

— final reviewer round 4, 2026-11-13 (fresh session; no implementation or validation file
edited; /tmp-only renders, stubs, clone and dep-copies; readonly-tier cluster reads only;
repo tree verified clean post-runs).

---

## Rework delta 5 — live defects C12 (pod memory scalar + host tuning checklist) — 2026-11-13, appended per owner reports
Fourth live-delta family (C09 §D1 command, C10 §D2 carrier, C11 §D3b grammar, C12 §D4 +
two owner reports). Report 1: the repaired C11 gate completed the first-ever hash
(CPU-quota-bound, ~30–70 min — §D4) and the SERVE container then printed its budget and
OOMed — cgroup 64.00 GiB vs **71.04 GiB observed pinned** (pool 42.70 + kv-resident
mirror ≈32 + arena 2.00 + placement 1.18 + staging): the shipped `guaranteedMemoryGi: 64`
could never hold the profile. Report 2: the owner's MANUAL 94 GiB bump proves the shape —
engine loads, SERVES — at `5.1 tok/s decode` / ~142 t/s prefill vs the RQ1 envelope
(142–160 / ~450–600-class): a host-tuning story (LINK half-width, memlock, DIO,
governor, swap, runtime-pm, clocks, heat-engine idleness). D28 class law: read the
printed budget BEFORE shipping the scalar. plan_status reopened complete→approved.

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C12 | Two-part: memory scalar 64→96 (receipt-anchored) + init-CPU knob · host-tuning checklist note + gate corrections | M | 9 | [C11] | repairs C11's completed gate's next step (the boot); AC2/AC3 fold the gate prose C09–C11 proved on-target; two halves separable for the owner |

Wave 9: C12 (alone). Commands additions: the render-diff proof (ONLY the memory pair
64→96 both maps + init cpu pair change; claim pair/equality gate/serveArgs byte-kept);
`AMD_GPU_FLIP_COMMIT=<C12 sha>` => NON-FLIP path (zero claim surfaces — re-proves the
C11 class); NEW `bash tests/notes/radiance-host-tuning.sh` (T1 citation-resolver w/
fixture-probe leg per §12.7 law, T2 fifteen stable family tokens, T3 read-only/owner-
executed law, T4 two-doc gate coherence incl the iommu correction); radiance suite
red-first legs (test_ac2_guaranteed_pair_with_named_pool, test_ac2_init_container_is_
guaranteed_too, test_ac3_scalar_splice_is_single_source, test_scalars_commented_with_
the_arithmetic + testlib SCALARS 64→96) + runbook.sh scalar/minutes/arithmetic needles;
radiance 46P+arms, witnesses 498P-9S/29P/36P unmoved. Live closure owner-run: repo
lands 96 OVER the hand-edit 94 (desired end state), budget-line check on every future
profile change (D28), tuning loop one-variable-at-a-time with the 8-session bar.

**Dated supersession (2026-11-13, owner batched round — D29; the 96 text above stays as
written history):** the shipped `guaranteedMemoryGi` is **110**, per the owner's verbatim
"110 GiB (your figure)" extending their own 2026-11-10 strata node-envelope law
(110+~7.3 floor ≤ 125.08) to radiance — arithmetically legal at §D6.2's sums
(115.28 ≤ 125.08 strata-down, free 9.80; 110−71.04 = 38.96 ≥ 4; strata-up 180.3 > 125.08
keeps the designed handshake AND inverts it — at 110-radiance strata's restore-back can
never co-reside). C12.md amended in place (dated markers) incl. five §D6 probe corrections
(LINK proven-downgraded, GOVERNOR non-persistent, MEMLOCK sandbox-vs-container probe fix,
RAM-tier arithmetically DEAD at 118.72 > 110 > 96, IOMMU confirmation + NPU side effect);
the live 94 was a LIMIT-ONLY hand-edit (pod is Burstable NOW) — the 110-pair sync restores
Guaranteed in the same roll (AC6). The uncommitted 96-pinned test round re-points to 110
per C12 AC4's exact list. Lock anomaly: "Yes, continue anyway" (D29.2); gpu-box spec:
owner "upgraded/different box" without a number → live 28.60 GiB governs, docs follow-up
card owed (D29.3).

## Rework delta 6 — C13 doc micro-round (figures + the §D7 sync guard) — 2026-11-13
Routed items from C12's review rounds + the §D7 live-object finding (D32). plan_status
stands approved (STATE never re-closed after the C12 re-opens; wave 10 reason recorded in
D32's head). Six folds: 8–23→~5.8–13.6 min @1000m (doc AND its pinning arms, same wave —
D30(6)); tier-hierarchy + BOUNDED-residual wording (D30(2)/(3)); the runbook's step-3/step-10
selfHeal machinery REPLACED by the procedural DON'T-SYNC guard (§D7: no automated on any
gpu-ai app; sync — not selfHeal — re-applies git over hand-edits; OutOfSync through the
strata-down window is EXPECTED; ordered restore sequence; review-r2's MINOR-R2-1
superseded-by-objects, guard preserved; CLASS LAW: template-verification ≠
cluster-verification for sync-policy claims); step-6 gains §R8-Q4's capture-key receipt
list; TP2 §12 gains D30(5)'s forward-look pointer (~30–35 host class at TP2, co-existence
may re-open ≈104.3 — cutover's decision); the r2-cosmetics bundle (governor heading to
body strength — suite is strength-blind, no arm invented; two grammar words; naming.sh
NON-FLIP label). `charts/radiance/values.yaml:40-41` verified-NIL for the false belief; its
actual carrier (services/gpu-ai values comment) routes to the NEW fleet prose card (AC8),
not this ticket.

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C13 | Doc micro-round: figure fix (doc+needle same-wave), tier honesty, §D7 don't-sync guard, step-6 capture keys, TP2 pointer, r2-cosmetics | S | 10 | [C12] | everything folds lands on C12's freshly-landed doc/comment surface; the envelope figure is pinned by C12's own suite arms |

Wave 10: C13 (alone). Commands: three notes suites at the new figure
(`radiance-runbook.sh` 5 ok, `radiance-host-tuning.sh` 4 ok incl stale-figure RED re-proof,
`radiance-tp2.sh` 3 ok), radiance **46P with render-diff EMPTY** (values edits comment-only
— asserted in commit), naming 5 ok + `AMD_GPU_FLIP_COMMIT=<C13 sha>` ⇒ NON-FLIP, witnesses
498P/9S + 29P + 36P + surface 9/M1..M8 10, aislop/rulesync repo-pins, zero-stale re-run.
Run-end: card #1 re-publish AGAIN + NEW fleet selfHeal-prose card (D32(4) body line).

## Rework delta 7 — C14 (LINK ladder refresh + mover facts) — 2026-11-14, docs-only
§D10 (scout round 10) falsified the tuning note's top LINK candidate on the record: the
owner ran §R10's dock-first cold-boot ritual verbatim; the genuinely NEW boot
(`4d6202d9…` @21:34:43Z) reprinted the chain degraded — **the rate didn't move because the
LINK didn't move**; power-ordering latch CLOSED by its own experiment; BIOS-pin already
closed by D34's TargetSpeed=16 read. The drained pod's exit banner proved the MOVER
ENGAGED AND CHURNING (20678 dispatches; boot-B's 0-dispatches was a read artifact; §D8's
154-capacity inference corrected — layers reach 300; churn = ~90–100 MiB/token of extra
link traffic → link-first STRENGTHENED; post-ritual 11.0/16.4 tok/s = same, mid-ramp —
"same or worse" adjudicated; fair number still gated on the never-run fixed probe + step 6).
D36 carries the two self-corrections (154-capacity; the "61% busy" citation that NEVER
existed — honest census 49/50/48) and the law: falsified checklist rows get re-pointed in
the SAME ticket. plan_status reopened complete(FINAL r5)→approved, reason recorded.

| id | title | size | wave | depends_on | why the dependency |
|----|-------|------|------|------------|--------------------|
| C14 | LINK ladder refresh (falsified rung + reseat→cable→DOCK-BYPASS→last-resort BIOS-EQ) + NOT-fixes & d3cold/runpm STABILITY row + HEAT-ENGINE mover facts | S | 11 | [C13] | edits C13's freshly-landed note; the fiction-ban/marker/coherence arms C13 added are the rewrite's rails |

Wave 11: C14 (alone; docs-only). Commands: the two notes suites' LINK arms (TargetSpeed /
REPRINTED-at-49% / fiction-ban) must SURVIVE the rewrite unchanged; `tests/notes/radiance-
host-tuning.sh` 4 ok + runbook 5 ok + tp2 3 ok; envelope/sums tokens frozen (30–70 /
5.8–13.6 / 110 / 71.04 / 118.72); witnesses 46P/498P-9S/29P/36P unmoved; naming NON-FLIP
at C14's sha; **render-diff MUST BE EMPTY (zero charts/services files)**. Run-end: active-
dock-vs-3.94-GB/s purchase decision + guards-optimality observation recorded for the owner
(AC6), card-#1 re-publish ledger unchanged.

## FINAL whole-plan review round 6 (C14 docs refresh + record corrections) — 2026-11-14,
fresh planning-tier session, HEAD 3261a92f3, main == origin/main == da46cee2e

**Verdict: APPROVED.** Zero blockers, zero majors. C14's four claims verified — not trusted —
against the receipts and the live cluster; the record-corrections and the lock incident audited
honestly, including the coordinator's self-reported errors. The ticket is now **COMPLETE except
(i) the owner's hardware rungs and the two never-run gates, and (ii) the run-end card/merge
actions** — nothing in the repo awaits agent work.

**TICKET-WIDE BAR (all fresh, sequential, PATH-exported, /tmp-only dep updates):**
charts/llama-swap **498P/9S/0F** · charts/radiance **46P/0F** · charts/amd-gpu **29P/0F** ·
charts/vllm **36P/0F** · amd-gpu-naming **5 ok bare** AND `AMD_GPU_FLIP_COMMIT=d645b7cf8` ⇒
**NON-FLIP** green; historical witnesses re-proved on the real commits (a81989b47→WAVE-A,
b1def8d1f→WAVE-B, 56142d511→WAVE-C); **bogus sha RED** and a **claim-drop synthetic**
(delete services/gpu's bare ADD in a /tmp clone) **RED** naming the carrier law ·
host-tuning **4 ok** · runbook **5 ok** · tp2 **3 ok** · dashboards **5 ok** · surface **9 ok
bare** + `CF143_BASE_SHA=0d9b41785` explicit `M1..M8` **10 ok** · helm lint ×4 (fresh /tmp
archive + dependency update) **0 failed** + both umbrella renders rc0 · rulesync `--check` clean
· **aislop: the §12.14 footnote reproduced exactly under my own hands** — `npx --no-install
aislop` REFUSES ("missing packages… aislop@0.21.0"; the float reached the registry in the C14
window) and the cached binary `node ~/.npm/_npx/74a4a2793e1dc310/node_modules/aislop/dist/
cli.js ci --changes` answers **cliVersion 0.20.1, 0/0/0 over 106 files, exit 0**. The footnote's
ask — make the pin repo-visible (package.json devDependency or a documented hash path) — is
carried as an infra-lane suggestion. Tree clean after every run.

**FOCUS 1 — C14's claims:** (a) the falsified Rung 0 carries its full receipt (boot id
`4d6202d9-…-1edec278a73d` @21:34:43Z, SIGTERM 21:31:24Z ≈3 m 19 s off-window, the verbatim
reprinted chain `00:03.1 8.0 GT/s x4 (max 16.0…) … [read at 48% busy]` + WARN + "FALSIFIED, not
owed a repeat") and my own repo-wide sweep finds the dead candidate re-advertised NOWHERE (the
"`those ARE its settings`" phrase survives ONLY inside §R9/D35's falsification prose in
EXPLORE/plan records — no note, runbook or TP2 site teaches it; the runbook/TP2 files were
untouched by the window — 4 "sequenc" hits elsewhere are the C13 restore-ORDER law and a
curl-**resume** line, different words). (b) the ladder reads reseat → Gen4 SFF-8611 cable →
**DOCK BYPASS — the decisive separator** → BIOS-EQ LAST and trust-flagged (R9-S17 SEO-lead,
menu existence UNVERIFIED — "do not promise it"), the READ-UNDER-LOAD witness law is stated
(:60–:64, "idle parks the link at 2.5 GT/s, the trap that fooled early reads"), the census is
**49/50/48** with D36's explicit "a 61% reading never existed" self-correction, and the terminal
fork (active redriver/PEX dock = TP2 §2 lane, owner decision, "never a repo step" / accept
3.94 GB/s / profile levers / TP2) is presented as exactly that — OWNER's, not a plan.
(c) the NOT-fixes row keeps BOTH verbatim field quotes ("no change to PCIe link speed" /
"no effect"), the setpci row keeps NOT-FIX + OWNER-lane on one line (the marker-adjacency law
honoured), and the `d3cold_allowed=0` + `amdgpu.runpm=0` row is labelled **STABILITY — due
regardless, explicitly NOT a throughput fix** with the ArcheoCodix same-DEG1 precedent;
§D10.6's live read agrees the D3cold symptom has NOT appeared while its precondition stays
armed. (d) the HEAT-ENGINE section is now the COMPLETE exit banner (the tail restored at
3261a92f3: `328 dispatches declined / 265 starved of a slab slot, 3721 of a pool slot` — I
re-fetched the drained pod's log myself: 4fccz is Completed, banner byte-matches §D10.5),
READ ARTIFACT names boot-B's `0 dispatches`, SUPERSEDED names §D8.2(b)'s 154-capacity with the
300-reach + 520+1416 loans arithmetic, and the churn claim **recomputes**: h2d alone
71.40 GiB × 1024 ÷ 884 tokens = 82.7 MiB/token, both directions 90.48 × 1024 ÷ 884 = 102.4 →
"on the order of ~90–100 MiB/token" is honest framed arithmetic, not a measurement — and the
honest bound stands as written: m-model fits FOUR samples, "same or worse" adjudicates to
SAME-mid-ramp, and **no fair settled number exists until the fixed ≥2000-token probe (never
run) + the step-6 8-session gate (never run)**. The card-class exoneration is labelled EXTERNAL:
"the dock trains Gen4 in other hands (chimolog, R10-S8) and the card's class is ruled out —
other hosts report this card at Gen4 x4 (R10-Q2(f), §R9)" — cited witnesses, not our measurement.
**LIVE re-verification (readonly, this session): post-ritual truth holds** — the new radiance
pod `gpu-ai-radiance-…-6h9cz` Running (4fccz Completed with the drained banner), the old boot's
report still prints `8.0 GT/s x4 (max 16.0)`, cgroup **110.00 GiB**, `pinned by this process
71.04 GiB`, `ttm.pages_limit 112.00 GiB`, memlock 8.00 MiB, governor powersave, iommu off,
power cap 300 W — the hardware-did-not-move finding re-witnessed; router Deployment 1 Available
(gen 50) with its Application OutOfSync and NO automated policy — the designed parked
scale-down exactly as D31/§D7 teach.

**FOCUS 2 — records integrity incl the coordinator's self-corrections:** the ttm
`293610128→29360128` transcription is corrected at every LIVE site (note :24/:25/:30/:287 —
:24 now states the arithmetic 29,360,128 × 4 KiB = 112.00 GiB exactly; D33's paste + a dated
bracket) — **ruling on chunks/C12.md:177: ACCEPTABLE as-is** — that line quotes C12's frozen
chunk-contract text (a record of what the wave PINNED, and rewriting a landed contract quote
falsifies history); any reader grepping the mis-type lands on C14.md's info-1 + the D33 bracket
one hop away — but a one-line dated bracket in C12's Review-notes section (coord lane, optional)
would close the last hop. D36's two self-corrections (the never-existent 61%; the superseded
154-inference) are recorded as defects of OUR reasoning with the corrected census — the honest
shape. **Lock incident: truthful-but-incomplete.** STATE.lock_incident is accurate on every
checkable claim (prune at 16:09:03Z after `no_claim`; setId b60c418b → reaped; three records
commits f13200cdc/bf95022a/2c5151179 branch-local; owner verbatim; re-claim as `4cc5d898-…`,
new set, not inherited; practice correction "a no_claim heartbeat means treat the lease as
LOST"). **One omission I must name: the window was NOT board-write-free** — 2c5151179's own
message records the XFS/ext4 + fleet selfHeal-prose cards FILED and AD-144 RE-PUBLISHED at
18:46:52Z, minutes before the ~18:5xZ re-claim. Those were Inbox/Backlog additions (no
claimed-card move, no AD-143 touch, no push, no cluster write — the cluster check above re-
confirms nothing C14-era is deployed and main still lacks the docs-only C14 anyway), so zero
contention risk — but "no card move" ≠ "no board write", and the append-only repair is one
amendment line in lock_incident (coord lane). Null-session honesty rows: C11's review session
stays `null` beside the coord's self-recorded invented-id friction — exemplary; **one flag**:
C13-r1 and C14-r1 review rows carry the SAME session id (ses_e29eb1f7cffe…) while both chunk
notes say "fresh session" — coord to verify copy-paste vs reuse and re-word one record. C13
status correctly `done`; C14 done with all three handoffs and real session ids; **C13/C14 rows
still carry no `commit` field** (027d3b4ee+ec92229ce / 384e3135e / d645b7cf8+3261a92f3 — fold
owed); STATE parses, plan_status approved (delta 7 records the reopen reason), 42 top handoffs
+ per-chunk rows complete.

**FOCUS 3 — goal-vs-card, FINAL: every card ask is delivered and LIVE.** Radiance deployed
beside strata (Q5 co-existence held — strata parked at replicas:0 under the don't-sync law, its
re-restore is step 10's ordered either/or at 110: 180.3 > 125.08); vllm disabled commented-out
(C01, zero live rows); honest catalog trio (C05, 9/5/1 higher-wins, [text,image]); the ladder
documented end-to-end (C06 runbook + C12's 110 + D30's capture keys); product-named pools +
patched ids table (C07/C08, table sha 864da869… live-mounted, "Loaded 10" receipted);
110/110 Guaranteed LIVE with the D21/D26 shield delivered by the per-cluster OVERLAY ADD (gpu
pod rendered unchanged — naming n2/n3 + 498P carry it); four doc artifacts mutually coherent
(T4 two-doc coherence arm green, cross-doc token census frozen, no stale survivor anywhere:
zero 8–23, zero re-advertised rungs, zero fictive-retimer INSTRUCTION — the two branch "retimer"
hits are the PASSIVE-dock denies). **TP2/card freshness: `git diff 2c5151179..HEAD` touched ONLY
the tuning note among the four artifacts — TP2's body did NOT move in C14 ⇒ AD-144's C13-era
re-publish is CURRENT, no fourth re-publish owed** (verified by diff, not by claim). Remaining
owner-side items, named exactly: rungs 1–3 (reseat / Gen4 SFF-8611 cable swap / DOCK BYPASS —
the decisive separator), the terminal purchase fork (active dock vs accept 3.94 GB/s vs levers
vs TP2), the d3cold/runpm STABILITY hygiene (due regardless, host lane), the two gates (fixed
probe at request ≥4; step-6 8-session + §R8 capture keys), the cutover either/or (110 made it
binary; §R8-Q5: TP2's ~30–35 may re-open co-existence ≈104.3), and the five Inbox cards —
AD-144 TP2 / AD-145 Grafana / AD-146 appset-passthrough (labels confirmed) / XFS-ext4 storage
lane / fleet selfHeal-prose. **Zero repo-side work remains for ANY of them** — every follow-up
is an owner action or a future ticket; the only branch→main delta left is this run's own landing.

**FOCUS 4 — git/scope:** per-commit audit `2c5151179..HEAD`: d645b7cf8 = EXACTLY 3 files
(note + TEST_SPEC ledger + suite arms — the docs-only claim holds, 0 render-plane files,
confirmed by my own name-only diff and the input-zero-diff renders); 3261a92f3 = docs
(banner tail + rung-0 quote + the 3 transcription sites) + records (STATE/DECISIONS/chunks) —
inside the r1-fold lane. `4652671fd..HEAD`-wide removed-assertion state unchanged from round 5
(0 removed assertions this window; the off-parity re-baseline remains the only fixture move of
the whole live-round saga, already sanctioned-with-provenance). Branch local-only (no
`cf-143*` ref on origin; no upstream); main moved solely by the owner's own landings (twins,
content-equivalence law D30(7)/D31 — and main's advance to da46cee2e + the cf-135 files the
branch lacks are exactly the no-rebase posture, re-verified intersect-free: the main..HEAD delta
touches none of cf-135's files). Tree clean after my runs.

**HAND-BACK (owner's word on all of it, in order):** (1) **Merge + sync the branch remainder** —
d645b7cf8 + 3261a92f3 (+ the records): the owner-facing tuning note on main STILL carries the
retimer fiction and the falsified Rung-0, and NOTHING syncs it automatically, so this is a
docs-landing, not a sync — merging changes no rendered object (0 render-plane files).
(2) The hardware ladder in the note's own order: reseat → cable → DOCK BYPASS (the decisive
separator; open-frame or a second Gen4 host) → BIOS/EQ last; the d3cold/runpm stability row is
due regardless; record the LnkSta verdict. (3) Then the two rate gates: the fixed probe
(≥2000 tokens, n=1, temperature 0, run twice, quote the SECOND) at request ≥4 — the
`stream_bytes ÷ decode_tokens_total` line is the one number that ends the debate — and
step 6's 8-session gate with §R8 capture keys; report per "the receipt decides, never the rate".
(4) Then the cutover decision (110's either/or), the five Inbox cards' triage, the D24 upstream
naming-ask word. (5) AD-143: coord moves the card Executing→Review with the round-1–6 summary
once the owner gives the word (records fold above are the final's asks), releases the
`4cc5d898` claim, and the session goes home; **Finished is the owner's hand alone.** Ten rounds
of review, four live-defect classes closed on-target, all fourteen chunks
APPROVED: **this plan is complete.**

— final reviewer round 6, 2026-11-14 (fresh session; sole write = this record; renders, dep
updates and the claim-drop synthetic confined to /tmp; cluster reads readonly-tier only; repo
tree verified clean post-runs).

---

## Rework delta 8 — owner extension: q27 on radiance (C15 + C16) — 2026-11-15, appended per owner ask ("Please add support for 27b in radiance")

plan_status reopened `complete`(=FINAL r6 APPROVED, fourteen chunks)→**approved** for this
extension wave (the C09→C14 reopen pattern, D54); waves 12→13; **this activates the Deferred
row DECISIONS:1696** "q27-on-radiance second lane" — the IQR-V4 half of that row STAYS
deferred. Authorities: RESEARCH §R19 (the q27 round) + EXPLORE §D54 (the file-map) — cited,
never re-derived. Owner rulings consumed verbatim (D54), NOT re-asked: **pod-swap** (`radiance-q27`
own Application, git renders `replicas: 0`, owner flips by scaling; two pods NEVER both
schedule — capacity-1 pool + chart-baked non-subtractable claim (D26) + fn-110 leaves 9.80 GiB),
**keyless** (the recipe's `--api-key "$RADIANCE_API_KEY"` DROPPED — zero repo hits, four D8
arms; no fourth custom-values leg), **24 GiB request==limit** (Guaranteed, mirroring fn's D29
shape), **catalog trio in the same wave ranked below fn** (8/4/0 under fn's un-inverted
higher-wins 9/5/1; fn's ranks not stolen; rows are a measurement-conditional candidate — the
runner-model literal does NOT move).

**Topology DECIDED (D56): roster `chart: radiance` override + `radiance-q27:` overlay subtree**
(one chart, two releases) — the base template's `hasKey "chart"` branch is the documented lever
(zigbee2mqtt/actualbudget precedents; §D54's local render proved rc=0 + the inherited
`cpu: "8"`/`gpu-r9700-1: 1`). Rejected `charts/radiance-q27/` sibling dir with its duplication
cost named: a second image-pin/digest ledger/renovate comment (drift class this ticket keeps
paying), a second BusyBox init-grammar home (C11 class), new CI workflow + re-pinned
test_contract path-set. Payoff pinned as an AC: `charts/radiance/values.yaml` **ZERO diff** —
the chart's 46 legs stay green by construction; every fn-shaped q27 truth is a whole-list
replacement in the service overlay (§D54-B's list-replacement law, with the anchor trap
reversed: `--model` moves ONLY because the overlay's args list carries the path literally).

### Chunk table (extension)
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C15 | q27 lane plumbing: roster entry + overlay subtree (args/init/24Gi pair/replicas 0) + `peers.radiance-q27` + catalog trio + pipeline-models row + CI leg + golden + the third-peer re-pin wave + new q27 test legs | L | 12 | [C14] | builds on the landed fn lane; the test re-pin wave (parity 3-peer law, golden keys, phantom allowlist, M8-A2 delta) MUST land same commit-wave as the values edits it greens |
| C16 | q27 docs: `.agents/notes/radiance-q27-boot.md` (the owner's first-boot receipt step) + TP2 §9/§11 SHIPPED annotation + own contract script `tests/notes/radiance-q27-boot.sh` + tp2-suite re-pin | M | 13 | [C15] | REAL dep: the note's single fenced args block equality-checks the LANDED overlay subtree (C06 idiom); runbook T2's "EXACTLY ONE" fn-block law forces a SEPARATE doc+script (q27 prose inside the fn runbook reds it) — split reason stated in the chunk, not churn |

Wave 12 → C15; wave 13 → C16. Both inside the existing `## Commands` battery; the chunk files
carry the q27-specific legs. `tests/notes/radiance-host-tuning.sh` stays IMMUTABLE (run-only);
the strata surfaces, the D8 keyless arms, the §12.14 frozen sums, `charts/radiance/values.yaml`
and NOTES.txt are do-NOT-touch lists in both chunks. Red-first law holds: agent-test writes
T-legs BEFORE dev (the third-peer re-pins are RED against today's tree by design; the fn arms
are GREEN witnesses and must stay byte-untouched).

### Risks (extension)
- The boot of the `.rad` on OUR card is the load-bearing receipt (§R19 Implications): every
  q27 number shipped here (200K per-session ceiling, 24 GiB, aggregate ~335–409K) is written
  to be CONFIRMED OR CORRECTED by the engine's own VRAM-split + budget prints; `limit.context`
  moves only if that print contradicts it, via DECISIONS→values→arms one wave (D36(4)).
- Priority-0 semantics (the q27 `-low` rank under fn's 1) is UNVERIFIED engine behavior —
  best guess shipped; C16's smoke step 5 reads it on the boot lane, correction = prose fold +
  arm re-pin, never a silent retarget.
- The idle lane answers 503 through the peer hop (Service exists, endpoints empty) — honest
  by design, stated in the overlay comment + the boot note; nothing auto-routes there.

### Open questions (extension — for the coord's ONE batched round; best guesses already shipped)
- **OQ-15** — `--host ::` (shipped, the fn-lane idiom) vs the recipe's literal `0.0.0.0`: both
  serve, `::` is the live-witnessed form on this pod network. Recommendation: keep `::`; flip
  is one value edit if the owner wants their literal. (Best guess shipped, NON-BLOCKING.)
- **OQ-16** — the q27 trio's exact ranks 8/4/0 (each strictly below fn's matching 9/5/1,
  higher-wins kept, fn's ranks untouched). The engine's priority-0 behavior is unverified
  (§R19 carries no floor row; vLLM's `priority=0`=unset precedent does NOT transfer).
  Recommendation: ship 8/4/0, let C16's smoke confirm; fallback 8/4/2 if 0 reads oddly.
  (Best guess shipped, NON-BLOCKING.)
