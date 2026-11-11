# PLAN: Radiance replaces Strata on gpu-ai (AD-143)
feature: 2026/2026-11-cf-143-feat-radiance-replaces-strata
Owner rulings 2026-11-11: round-2 (Q1–Q8) · approval round (Q9→research, Q10, Q11, APPROVE) ·
R6 round (Q9 OPTION 1 + "fold and run on"). All folded below; DECISIONS.md is the verbatim ledger.

## Goal
Land a new `charts/radiance` (engine: `stilldeadcode/radiance` v1.17.0 — the C++/HIP one,
NOT the vllm-radiance fork behind `charts/vllm`, unrelated to Strata) as a non-privileged,
Guaranteed-QoS peer Deployment that claims the R9700 **by name** (`amd.com/gpu-ai-pro-r9700`,
made possible by a vendored `charts/amd-gpu` fork enabling the plugin's `product` naming
strategy — the llama-swap APU claim flips to `amd.com/gpu-8060s` in the same wave), serving
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
- GPU naming (Q9): vendored `charts/amd-gpu` (upstream 0.22.0 copy + ~10-line args hook,
  CMD restated incl `-v=5`; `dp.extraArgs: ["-resource_naming_strategy=product"]`;
  `dp.image.tag: 1.31.0.12` + renovate docker comment + amd64 digest `sha256:6437c74f…`
  ledger); `gpu-ai-amd-gpu` Application switches repo→git-path with identical object
  names; node then advertises `amd.com/gpu-ai-pro-r9700: 1` + `amd.com/gpu-8060s: 1`,
  `amd.com/gpu` GONE — any stray bare claim becomes Pending-forever (loud by design).
  Fallback trap: unknown (device,revision) pair → bare `amd.com/gpu` — five C06 step-0
  receipts gate it (sysfs pair, plugin log, node-status assert, llama-swap post-rollout,
  radiance PCI belt-and-braces).
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
  `python3 -m pytest charts/llama-swap/tests -v` (strata suites green untouched — Q5; resources needle re-pinned to `gpu-8060s` — C07);
  `python3 -m pytest charts/vllm/tests -v` (green — chart intact)
- naming wave (C07): `helm template charts/amd-gpu` shows args incl `-resource_naming_strategy=product` + full restated CMD;
  `grep -rn "amd.com/gpu:" charts/ services/` finds ZERO live bare claims post-flip (comments excluded — the suite's own pattern);
  `grep -n "amd.com/gpu-8060s" charts/llama-swap/values.yaml` + `grep -n "amd.com/gpu-ai-pro-r9700" charts/radiance/values.yaml`;
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
| C07 | Vendored `charts/amd-gpu` product-naming + llama-swap same-wave flip | M | 1 | [] | defines the cluster's resource-name interface; carries the flip in its own commit (same-wave law) |
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

## Rollout notes (merge-time reality — one PR, Argo syncs all; per R6-Q4-4)
- All flips land together on merge: vendored amd-gpu (new DS source, same object names,
  plugin pod restart only — running GPU pods keep their allocations; seconds-long
  deregistration window, single idle node ⇒ no scheduling storm) + llama-swap `gpu-8060s`
  flip (its NEXT restart needs the new name; the running pod survives) + radiance chart
  (Pending until strata is manually scaled down — owner's Q10 protocol).
- Rollback = ONE `git revert` of the flip wave (plugin revert restores `amd.com/gpu: 2`;
  the llama-swap flip MUST revert in lockstep — same values history). Rollback of the
  radiance/peer legs alone = C01-style comment flips; never split the plugin+llama-swap pair.
- Watch-once: `ignoreDifferences`/SSA field ownership on the DaemonSet `args` field when
  the Application source flips repo→path (ServerSideApply "true" helps).
- C06 step-0 enumerates the five naming receipts (a–e) + host-prep gates BEFORE first boot.

## Run-end actions (coordinator)
1. TWO Inbox follow-up cards (Q6): (1) TP2 expansion — body = C03's doc; (2) Grafana
   dashboard re-import. Strata-deletion + IQR-V4 ride the owner's metrics decision, not cards.
2. "Fold and run on": after this fold-in, Test Writing + the whole chunk loop proceed with
   NO further owner pause until Final Review. Residual gaps below ship on best guesses.
3. Card write-back per the boards flow stays coord's.

## Open questions & rulings
RULED: Q1=A · Q2=flip 9/5/1 + floor 5 + per-engine note · Q3=commented disable,
`vllm: {}` kept, extraction hardened, no replicas:0, absence-asserting suites · Q4=honest
new id · Q5=STRATA LIVES (additive radiance) · Q6=two cards · Q7=non-priv NOW + mandatory
pre-deploy host gates · Q8=`in: [text,image]` + retire-on-failure smoke · Q9(20:40)=
research round → R6 → **(final ruling): Option 1 vendored product-naming, same-wave flip** ·
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
- The flip wave is the ticket's only cluster-wide behavioral change beyond adding radiance:
  `amd.com/gpu` disappearing strays ANY future bare claim to Pending-forever (loud by
  design, R6-Q4-3); a llama-swap pod rescheduled between plugin-flip and its own flip lands
  Pending — same-wave law + single-PR merge is the mitigation, runbook (d) verifies after.
- Strata stays privileged hostPath on the R9700's *physical* card inside the named pool
  (naming ≠ VRAM arbitration — Q11's law stands; manual scale-down protocol governs).
- kv-resident 8×200K start remains an on-target unknown (RESEARCH OQ3 — the refusal
  precedent was a smaller host); the runbook's down-ladder (pool → ctx → 4-seqs → owner-
  sign-off prefix-cache swap) covers it at the single scalars.
- `--kv-resident` excludes the prefix-cache tier: idle-session re-prefill pays the x4-link
  wall (~450–600 tok/s @55k) — honest-envelope note in runbook + TP2 doc.
- amdgpu.ids revision assumption (R9700 C0 → `gpu-ai-pro-r9700`; 8060S C1/C3/C6/D1 →
  `gpu-8060s`) is computed, not yet receipted on-target — the five step-0 gates close it.
