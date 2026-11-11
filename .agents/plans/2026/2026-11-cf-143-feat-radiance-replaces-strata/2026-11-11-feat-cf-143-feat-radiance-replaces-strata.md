# PLAN: Radiance replaces Strata on gpu-ai (AD-143)
feature: 2026/2026-11-cf-143-feat-radiance-replaces-strata
owner rulings 2026-11-11 (batched round, Q1–Q8) applied; see "Open questions & rulings".

## Goal
Land a new `charts/radiance` (engine: `stilldeadcode/radiance` v1.17.0 — the C++/HIP one,
NOT the vllm-radiance fork behind `charts/vllm` and unrelated to Strata) as a non-privileged,
device-plugin-allocated, Guaranteed-QoS peer Deployment serving the Flash-Next lane, joined
to llama-swap via an ADDITIVE `peers.radiance` block — Strata stays fully live alongside it
(owner ruling Q5: "Strata shouldn't be disabled yet. Once I get good metrics from Rediance,
then we'll look at what to do with Strata") — while the vLLM chart+peer+catalog lane is
disabled commented-out, the agent-context catalog gains radiance rows with radiance's
flipped priority polarity, and the runbook + TP2-expansion doc land as artifacts.

Out of scope (explicit): Strata retirement/disabled-state of any kind (this run adds beside
it; retirement rides the owner's metrics decision — Deferred); any on-target deploy or
mutation (Deployment stage unchecked — host-prep gates + acceptance runbook are OWNER-run
artifacts); deleting `charts/vllm` or `containers/vllm-radiance-mxfp4` (disabled-commented
only, owner circles back); the physical second R9700 (docs + follow-up cards only); the
runner-model literals in `.agents/loops/pipeline-worker.md` + AGENTS.md text — they STAY
VALID this run (strata survives, Q5/Q4) — a re-ruling is the later cutover's step, Deferred;
Grafana dashboard re-import (follow-up card #2, Q6); IQR-V4 pack adoption.

## Structure — RULED (Q1=A)
Own `charts/radiance` + llama-swap peer. The B (controller) / C (child-swap) options are
closed; no chunk forks on structure any more.

## Key pinned facts (RESEARCH.md authority, restated for coexistence)
- Engine: `docker.io/stilldeadcode/radiance:1.17.0`, amd64 image-manifest digest
  `sha256:6fb0e99b…` (index `sha256:c2acbaa3…` — ledger both, name which); no `serve` verb;
  OpenAI on 8000; `/health` key-exempt.
- **Shadow profile (coexistence-governed — Q5+Q7 arithmetic, see Risks)**:
  `--tp 1 --max-model-len 65536 --max-num-seqs 8 --placement expert_tiered
  --host-pool-mib 28000 --gpu-headroom-mib 96 --kv-cache-dtype fp8 --kv-resident 32768
  --num-speculative-tokens 3 --max-num-batched-tokens 4096 --checkpoint-interval 4096
  --ngram-placement disk --served-model-name qwen3.8-flash-next-radiance --host :: --port 8000`
  — host pins ≈ 27.3 (pool) + ≈4.1 (kv-resident copy 8×64K×12.3 KiB/token) + ≈0.9 (slots)
  + ≈1.5 (embed/vision/rows) ≈ 34 GiB under a 52Gi Guaranteed cgroup (≥4 GiB-free rule +
  burst margin). The 8-session ask is met at 64K ctx; the **full sole-tenant profile
  (pool 43000, 200K, 8 seqs, ≈110Gi cgroup) is the documented post-retirement ladder**
  (runbook), NOT this run's shipped values. No `--prefix-cache-mib` (exclusive with
  kv-resident), no `--expert-vs-cache-ratio`, no api-key.
- Pod shape (Q7 override): plugin claim `amd.com/gpu: 1`; NO privileged, NO hostPath
  kfd/dri; `seccompProfile: Unconfined`; `capabilities.drop: [ALL]` + `add: [IPC_LOCK]`;
  `supplementalGroups: [486]` (kfd, live-verified) + runbook-gated render/video additions;
  Guaranteed requests==limits (mem 52Gi, cpu 8, gpu 1); dedicated non-root runAsUser +
  fsGroup (fresh per-UID io_uring memlock budget — llmkube precedent); Recreate; grace 180;
  no ROCR/HIP env (plugin injects devices, sets no env — don't rely on host enumeration);
  no nodeSelector/tolerations (single untainted k3s node — EXPLORE §4).
- Priority (Q2 ruling): radiance higher-wins + preemption-by-recompute; rows carry
  9/5/1, peer floor `priority?: 5`, pipeline-models keeps a per-engine polarity note.
- Catalog (Q4+Q8): new honest id `qwen3.8-flash-next-radiance` (+ `-urgent`/`-low`
  wire-siblings sharing modelID); rows advertise `in: [text, image]` (vision in-pack) and
  context 65536 (shadow-served truth; 200000 rides the retirement ladder).
- Pack: `qwen3.8-next-flash-fp8-iq4r-moe.rad` 113.60 GiB, ungated, lfs `0af5e962…`, staged
  on the shared `llama-swap` claim by the fetch-init (sha marker).

## Commands (validation battery — repo has no unit-test suite; this IS the proof)
Every agent: `export PATH=$HOME/.local/bin:$PATH` first (helm-guarded pytest mass-skips without it).
- chart: `helm dependency update charts/radiance && helm lint charts/radiance && helm template charts/radiance --debug`
- chart suites (per-directory): `python3 -m pytest charts/radiance/tests -v`;
  `python3 -m pytest charts/llama-swap/tests -v` (strata suites MUST stay green untouched —
  coexistence is the regression test for Q5); `python3 -m pytest charts/vllm/tests -v` (green — chart intact)
- service values: `python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml'))"`
  + greps: `charts.radiance` entry, `peers.radiance` present, `peers.strata` PRESENT-UNCHANGED
  (byte-diff its block vs pre-ticket), top-level `vllm: {}` empty-key shape, no radiance
  ingress subdomain + skip comment; `helm template charts/llama-swap -f <extracted llama-swap:
  block>` renders peers.strata AND peers.radiance, no `OVERRIDE_` strings.
- CI-shape parity: `.github/workflows/vllm-render-tests.yaml` extraction leg (`d.get('vllm') or {}`)
  + `radiance-render-tests.yaml` extraction leg run locally against the live service values.
- contract suites: `bash tests/pipeline-models/surface.sh`; `bash tests/notes/radiance-runbook.sh` (new);
  `bash tests/notes/radiance-tp2.sh` (new); `bash tests/services/vllm-dashboards.sh` (stays green — untouched);
  `tests/notes/vllm-runbook.sh` retired by C01 — absence-checked.
- catalog round-trip: `npx rulesync generate && npx rulesync generate --check`; second generate is a no-op.
- quality gate: `npx aislop ci --changes`.
- No container chunk (upstream image) — `docker build => no-daemon, CI-deferred` is N/A;
  renovate tracking verified via the `global-renovate` dry-run tool (interactive, optional, C02).

## Chunks
| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | Disable vllm (commented-out) + retire its tails | L | 1 | [] | independent: vllm surface does not touch radiance chart |
| C02 | New `charts/radiance` — non-priv plugin-allocated chart, shadow TP1 profile | L | 1 | [] | interface producer (served id, scalars, evidence targets) |
| C03 | Second-GPU (TP2) expansion doc → follow-up card #1 body | S | 1 | [] | pure research synthesis; independent of the pod shape |
| C04 | Service wiring: `peers.radiance` ADDITIVE + radiance appset entry + evidence/golden | M | 2 | [C02] | interface: chart scalars + served id the peer names; evidence/golden pair with the values edit |
| C05 | Agent-context catalog: ADD radiance rows (9/5/1, text+image) — strata rows KEEP | M | 3 | [C01, C04] | data: M4 serving-fact reads peers.radiance (C04); same-file M-legs ordered after C01's vllm retirements |
| C06 | Mandatory host-prep gates + on-target acceptance runbook + contract suite | M | 3 | [C02, C04] | test equality: runbook flags/URLs/GIDs must match the SHIPPED chart args (C02) + peer URL (C04) |

## Wave order
1. C01, C02, C03 (independent; run in id order)
2. C04
3. C05, C06 (independent of each other; run in id order)

## Run-end actions (coordinator, not chunk work)
1. Create TWO Inbox follow-up cards (Q6): (1) "Radiance second-GPU (TP2) expansion" — body
   = C03's doc; (2) "Radiance metrics → Grafana dashboard re-import" — body = C06's
   metrics-adjacent notes (the `/metrics` vllm-compat family makes the existing dashboards
   cheap candidates). Drop the strata-deletion + IQR-V4 asks from the card content
   (strata-deletion rides the owner's metrics decision naturally).
2. No pre-merge owner gate: the runner-model literal `gpu-ai/qwen3.8-flash-next-strata-q4`
   stays served (strata live). Record the cutover re-ruling as a Deferred item for the
   future strata decision.
3. Card write-back per the boards flow (slug stack, Lifecycle checkboxes, Review move) stays coord's.

## Open questions & rulings
Ruled (owner round 2026-11-11, verbatim in DECISIONS): Q1=A · Q2=flip-per-engine 9/5/1 +
floor 5 + per-engine polarity note · Q3=comment entry+peer, `vllm: {}` kept, extraction
hardened, charts/vllm byte-intact, NO explicit replicas:0, suites assert absence ·
Q4=new honest id · Q5=STRATA NOT RETIRED — coexist, evidence law resolved as a separate
radiance evidence file (D13) · Q6=two Inbox cards · Q7=non-privileged NOW (plugin +
supplementalGroups + drop ALL + IPC_LOCK + Guaranteed; host-prep receipts become MANDATORY
pre-deploy gates) · Q8=advertise `in: [text, image]`.
NEW gaps created by the rulings (best guesses shipped, Q9/Q10 go to the next round):
- **Q9 — named-card guarantee:** plugin 1.31.0.9 counts BOTH cards with nodeId-ascending
  APU-first allocation and no occupancy persistence across restarts (19 observed) —
  radiance can receive the 8060S after a shuffle. Best guess: ship `amd.com/gpu: 1` + a
  MANDATORY runbook startup gate asserting the startup-report PCI/gfx id is the R9700
  (delete-pod retry on mis-allocation); product-named resources (plugin ≥1.31.0.12 →
  `amd.com/Radeon-AI-PRO-R9700`) recorded as the clean fix, deferred (chart bump = own
  concern). Alternative if owner prefers: pin via hostPath-env idiom for radiance only
  (contradicts Q7 — needs the word).
- **Q10 — shadow-profile sizing under Guaranteed coexistence:** node allocatable ≈125.08 GiB
  minus strata's 64Gi request − llama-swap 4Gi − sidecars/reloader leaves ≤ ~52 Gi
  requestable for a Guaranteed radiance pod — the full 8×200K envelope (~80 GiB pinned)
  does not fit while Strata keeps its exact requests. Best guess: ship 52Gi/8×64K/pool-28000
  (single scalar pair, receipt-adjustable one-edit knobs, downward ladder documented);
  alternatives: trim strata requests (against Q5's "exactly as is"), burstable radiance
  (against Q7's Guaranteed), or smaller first-boot until the owner's decision.
- Q11 — VRAM contention posture: radiance resident (~28–30 GiB of 31.86) + Strata's
  R9700 arenas cannot both be hot (one-engine-per-card law; the runner route may arena-fail
  during radiance windows). Best guess: ship additive, runbook documents the contention
  matrix + owner's metrics window; no auto-mitigation in GitOps (owner's call per Q5).

## Risks / assumptions
- Coexistence is RAM-tight: Guaranteed 52Gi + strata requests 64Gi + outer 4Gi sits within
  allocatable ONLY if the runbook's step-0 request-sum holds (Q10); the engine's own
  ≥4 GiB-free-under-cgroup refusal + the Wilde pinned-demotion-burst class are the failure
  modes to watch (runbook §9).
- Cutover has none: merging lands radiance ADDITIVE; Argo creates gpu-ai-radiance beside the
  live strata pod; first boot may refuse (VRAM/cgroup) until arenas idle — loud failure at
  the engine, never a node-OOM bet, per the Guaranteed cap.
- `--kv-resident` at 8×64K has not started on this host (RESEARCH OQ3 was about 8×200K —
  smaller copy; the runbook's refusal ladder still owns it).
- D38 honesty: catalog ctx 65536 mirrors the shadow profile; if the owner ships the full
  profile earlier, C05's row + chart move together (dual-surface needle in surface.sh).
- Plugin mis-allocation (Q9) is a real boot-shape risk on a mixed node; the startup PCI gate
  is mandatory, and Recreate + delete-retry is the sanctioned remedy.
- Assumed-unchanged from round 1 except where rulings overrode: image posture D2 (upstream
  pin + ledger), keyless/no-secrets D8, fetch-init staging D10, evidence/golden laws.
