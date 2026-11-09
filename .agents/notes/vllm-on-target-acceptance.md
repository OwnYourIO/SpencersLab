# vLLM on target — acceptance runbook (operator-owned)

**Provenance.** WeKan card #131 (`cf-131-feat-vllm-fp8-official`), the
cf-105 successor (`R4EjaHtDeHMjAkDpf`), whose shape this file documented
until the owner's re-scope ruling ("you need to include the MXFP4 fork in
the R9700 image. I've dropped the official checkpoint mandate") and the
round-2/round-3 batched rulings moved the shipping path. Feature folder
`.agents/plans/2026/2026-11-cf-131-feat-vllm-fp8-official/` — plan of
record `2026-11-07-cf-131-feat-vllm-fp8-official.md`, `DECISIONS.md`
(D23–D38), `RESEARCH.md` (cited `R2/R3 L<n>.<m>` + the later-round
`R5.x`/`R6.x` section forms + bracketed source ids),
`chunks/C05.md`. This file is C05: what to verify on the ai-gpu node after
the branch merges and ArgoCD syncs; it documents the 0.30-fork shape over
R3's ground. The official-FP8 stock path (round 1) and the 0.9.3 + GGZ14
base (the re-plan) are the RECORDED ALTERNATIVES — the section after step
10 — not this runbook's subject. The first deploy is a benchmark/acceptance
run, not a service flip (the RDNA-vLLM software-maturity risk class carries
from cf-105); its measured numbers feed follow-up card #2 (alert
thresholds) and the step-10 re-pin surfaces.

**Citation shapes.** Bare cf-105-era references in this file (`R<n> §x`,
`R<n> Qx`, `R<n> OQx`, `Post Research Vx`, `EXPLORE §x`, the `D`/`HR` law
ids) resolve in the cf-105 folder's `RESEARCH.md`/`EXPLORE.md`. cf-131
findings are the explicit `R2 L<n>.<m>` / `R3 L<n>.<m>` / `R5.x` / `R6.x`
forms and the
`[n]` source ids in the cf-131 `RESEARCH.md`.

**Ground rules.** The cluster's only input is git — ArgoCD applies
everything, and no step here mutates cluster objects. The sanctioned change
class is a values-only GIT change picked up by ArgoCD's own reconciliation
(human-run): the optional 5.2 fcfs negative proof, a 3.6-FAIL return to
the recorded fp8+R4D alternative (a values edit plus the fresh cap ruling
it forces — D36),
and step 10's pin. Agent sessions have no pod-exec tier (EXPLORE §7), so
every pod-internal command is operator-run through the operator's own pod
access, and every node-side command runs on the `ai-gpu` node.

**Names used throughout (no placeholders).** Pod selector
`app.kubernetes.io/name=vllm`, namespace `default`, release `gpu-ai-vllm`,
node `ai-gpu`. Engine service
`gpu-ai-vllm.default.svc.cluster.local:8000`. Public FE chain
`https://llama.spencerslab.com/v1`. Served model name `qwen3.8-27b-vllm`;
urgent class row `qwen3.8-27b-vllm-urgent`, low class row
`qwen3.8-27b-vllm-low` — both UNCHANGED from cf-105 (the fork's alias trio
`Qwen3.8 Qwen3.6 Qwen3.8-MXFP4` is dropped — the single
`--served-model-name` law, the R2 record carries). Central stack:
Prometheus `prometheus.spencerslab.com`, Grafana `grafana.spencerslab.com`,
Loki `loki.spencerslab.com`.

Image `ghcr.io/ownyourio/vllm-radiance-mxfp4:main` — the first-build shape;
step 10's PIN-ME follow-through flips it to the first `:v<run>`. THE single
ledger pin (one record, three surfaces: this block, the chart image comment,
the `containers/vllm-radiance-mxfp4/README.md` ledger): upstream
`magiccodingman/vllm-radiance:1.0.397` @ digest
`sha256:b73bf3e41bc0a1cf7aaa5935bebe31123f549639e69b61a3ffa81acd5f7313e0`,
source commit `5b99d66c844f` (the image's OCI `revision` label), engine
vLLM 0.30.0 @ `ced6857a` (the exact tag commit, no post-release
follow-ups). Tag↔commit law: publishes run on the upstream `release`
branch only — `1.0.<pipeline-IID>` pairs with `sha-<commit>` (R3 L1.1).
Release-branch watch: the next `1.0.<n>`/`sha-…` pair is the bump trigger,
NOT main's movement (step 10).

Weight set (the round-2 Q8 raw-release ruling): the raw release
`/models/Qwen3.8-27B-Quark-AWQ-MXFP4` (source
`amd/Qwen3.8-27B-Quark-AWQ-MXFP4` @ main-sha `93245f7c…`, the 2026-11-03
mtp-exclude-fix revision) + the drafter
`/models/Qwen3.8-27B-DFlash2-FP8/` @ revision `ee0cb26a…` (the qualified
pin; the weight etag is identical to current main, recorded) + the marker
file `/models/.staged-mxfp4-<both shas>` keyed on the pair. No HF_TOKEN:
both checkpoints are public/ungated — the cf-86 ruling carries.

TRUE-AXIS note: the catalog `limit.context` 262144 == the engine
`--max-model-len` 262144 — the advertisement is true at the engine (the
round-2 Q3 keep + the round-3 Q11 engine-cap ruling; the re-plan's band law
is superseded on the record, D31). The D36 q4 ruling re-frames the axis
as the q4 BOOT GOAL: it stays TRUE iff the 262144 boot holds — if the boot
refuses, the 3.1b contingency is the SANCTIONED B fall-through (the engine
prints its estimated-max-length line and the owner caps the engine arg at
that number, a fresh D31(e)-class ruling). LIVE RISK one-liner: the 262144
ceiling at TP=1 was the owner-ruled risk class — the 0.9.3-stack "does not
fit at TP=1" record (R2 L3.5) plus no 0.30 TP1 measurement anywhere
(R3 L2.4) — crash #4 materialized it at the fp8 shape, and the R6 round +
the owner's q4 ruling RESOLVED the line (D36). The 3.5 re-measure gate
owns the pool; the 3.1b startup contingency owns the refusal class.

**The honest envelope (the owner's Q2 standing condition re-bound by the
round-3 Q11 ruling; the cf-105 D4/HR3-class envelope law on this ground) —
the benchmark expectations in steps 3.5 and 6 are pre-registered against
this, not vibes. These are expectations, not claims: the R3 L3.3
weakest-claim law says no 0.30 TP1 measurement exists in any published
form — the on-target run is the first datum:**

- Weight side: MXFP4 raw release 18.41 GiB + DFlash2 drafter 1.97 GiB
  ≈ 20.4 GiB resident at TP=1 before the KV pool gets anything.
- Shipped shape: `--max-model-len 262144` / `--max-num-seqs 3` /
  `--max-num-batched-tokens 2560` — the round-2 Q2 Shape-B seqs/chunk
  constants + the round-3 Q11 engine-cap 262144, the model's native
  ceiling, the owner-ruled PLAN shape and (D36) the q4 BOOT GOAL — the
  advertisement holds iff the boot holds, else 3.1b's sanctioned B
  fall-through caps the engine arg at the printed estimate. Util `0.98`
  start (the D36 raise of the R3-Q2 0.90 start — the pre-D36 0.90 state
  is where the crash-#4 1.12 GiB pool datum landed): 0.99 is
  startup-dead on this card (asks 31.54 > 31.46 free [158]), 0.98 is the
  ceiling, 0.95 stands recorded as the conservative rung, and the 0.85
  compose default stays recorded. D37 (2026-11-09): the owner re-ruled
  0.98 KEPT after an explicit headroom review — the shipped ceiling
  stands, it is not a pending question.
- The 8.49 GiB KV pin is the recorded REFERENCE ROW, nothing more: the
  220000-class, 0.9.3-stack (vLLM 0.27.1-era) user-reported profile pin —
  provenance only, NO 0.30 validity (R3 L1.3/L2.4). It ships as NO pin:
  the chart carries no `--kv-cache-memory-bytes` (the re-measure-gate law,
  D24) and the 3.5 gate DERIVES the pool at the shipped 262144 shape.
- The 3.5 re-measure gate is the SOLE envelope path: no 0.30 measurement
  exists at any TP1 shape (R3 L2.4); the 0.30 TP2 Quark capacity table is
  the calibration CLASS, not the TP1 constant.
- The LIVE RISK (the Q11 consequence, D31) — RESOLVED by the R6 round +
  the D36 q4 ruling: crash #4 was its materialization (the fp8 shape at
  262144 computed a 1.12 GiB degenerate pool and died at the KV check —
  the R2 L3.5 "does not fit at TP=1" record is now observed fact, not a
  hypothetical), and the q4 boot config is the owner's answer. Backstops
  unchanged: the 40-min startup probe (a refusal is a loud, GATED failure
  — the pod fails at startup, it does not silently mis-serve), the 3.5
  gate (the pool's truth + the values-only `--kv-cache-memory-bytes`
  re-tune), and the 3.1b startup contingency — under D36 the sanctioned
  engine-estimate fall-through: with the q4 floor the refusal PRINTS the
  cap number instead of dying silent [155].
- The true axis means the ADVERTISEMENT is true, not that the physics are:
  sessions beyond the DERIVED POOL still reject/preempt at arrival — the
  vLLM admission behavior is pool-governed, not cap-governed. A
  full-context 262144-class pool on one 32 GiB card is impossible: three
  262144-token sessions ≈ 24 GiB of attention KV alone at the fp8 class
  (the ~32 KiB/token, the cf-105 R1 §3 arithmetic), ≈ 12.4 GiB at the
  shipped int4 class (the ~16.5 KiB/token [163]) — either way on a card
  whose allocatable class after the 20.4 GiB weights is
  small. One 256k-class session is a pool question, not a cap question.
  True long-context beyond the 262144 native ceiling stays on the
  llama.cpp `qwen3.8-27b-q8-1m` rung (the R1 OQ-E ruling).
- Preemption is intended: when the pool exhausts, vLLM
  priority-preempts the lower-priority class by recompute — the four-class
  victim order low(9) → default(5), never urgent(1) (the §5 constants are
  byte-stable).
- Power-policy caveat up front: the 0.9.3 TP1 137.7/416 class is the
  ANCHOR CLASS on the same card signature — provenance: measured at the
  65536 Shape-A context on the 0.9.3 stack at the 210 W cap −75 mV —
  the context-class reference, NOT the like-for-like 262144 datum. The
  0.30 TP1 numbers at the shipped shape are the on-target UNKNOWN.

## 0. Host gates

Operator commands on the `ai-gpu` node, before the vLLM pod is expected to
commit anything. Record every result; the `free -h` reading is the RAM-law
baseline (EXPLORE §8.6: ~125 GiB usable shared by Strata's 116 Gi-limit
pod, the llama.cpp trio, and the OS). The device-node group facts (GID 486,
the hostPath pair) are the pod-shape record's ground (charts/vllm
securityContext comment) — nothing here needs them changed.

| # | Check | Command | Gate / record |
|---|---|---|---|
| 0.1 | GPU enumeration | `rocminfo` | the agent list shows `gfx1201` and the R9700 is enumerated as device 0 (the 8060S is gfx1151, device 1) — the host driver sees the chip the pod will claim |
| 0.2 | amdgpu driver | `modinfo amdgpu \| grep version` | record the version against the ROCm 7.14 userspace the 0.30 image bundles (R3 L1.2) — the host-driver/userspace expectation class is R1 OQ5's; a driver too old for the bundled userspace is the first suspect for every later GPU failure |
| 0.3 | RAM baseline | `free -h` | record `available` — the node-RAM headroom baseline before vLLM commits anything (EXPLORE §8.6); steps 6 and 9 compare against this |

## 1. Pod facts

After ArgoCD syncs the merged branch, the pod must land on `ai-gpu` and
pass the C02 startup probe (`/health`, 60 s initial delay + 15 s × 160
failures — the 40-minute envelope, D18). The pod pulls the rolling `:main`
and `docker-build.yaml`'s post-merge run is the build authority for its
contents (cf-77): the D34 flash-attn layer reaches the pod only through
that build — a pod whose pull predates it runs the pre-layer image. Post
D38 this ordering is RECORDS-ONLY: the layer is decorative at text-only
serving, the 3.4 install gate it fed is retired, and the step-3 ViT rows
read ABSENCE-expected — the positive step-3 marker is the registry
text-only INFO line.

**1.1 — Pod lands, node is ai-gpu.**

```
kubectl -n default get pod -l app.kubernetes.io/name=vllm -o wide
```

Expected: one pod, node column `ai-gpu`, `READY 1/1` (or `0/1` inside the
40-minute probe window — see 1.2).
If it fails: `Pending` or a different node means node placement is wrong —
the chart values are the fix surface, not this runbook.

**1.2 — Startup duration against the probe envelope (the D18 two-class
window).**

```
kubectl -n default get pod -l app.kubernetes.io/name=vllm \
  -o jsonpath='{.items[0].status.startTime}'
kubectl -n default logs -l app.kubernetes.io/name=vllm --tail=100
kubectl -n default logs -l app.kubernetes.io/name=vllm -c setup --tail=20
```

Expected, the two classes: FIRST deploy ~40–60 min — the init staging (the
two `local_dir` downloads, ~20.4 GiB) plus the cold-cache serve boot
(the first-use AITER JIT — there is NO 0.30 pre-bake, R3 L1.2 — plus the
PIECEWISE graph capture) — inside the 40-minute probe envelope (staging is
init-container time, pod-level, not probe failure). RE-BOOT ~7–10 min —
the marker skip plus the warm boot. Record both classes; the number feeds
the follow-up probe sizing.
If it fails: restarting past the 160-failure window means the engine never
reached `/health` — 3.1's marker set localizes which leg; the
startup-refusal class (a hard reject at the 262144 ceiling) is 3.1b.

**1.3 — The chip actually selected (confirms the `ROCR_VISIBLE_DEVICES`
spelling — R1 OQ4).**

```
kubectl -n default logs -l app.kubernetes.io/name=vllm | grep -i -m 5 'gfx\|device'
```

Expected: the log names exactly one chip — `gfx1201` (the R9700).
If it fails: if the env was ignored, the pod sees BOTH chips and the run is
aborted — fix the values key (`rocrVisibleDevices`, under `app-template:`
in `charts/vllm/values.yaml` AND the `services/gpu-ai/prod/values.yaml`
twin — the dual-edit path law), not the template. The
`HIP_VISIBLE_DEVICES: "0"` twin is the 8060S-exclusion half of the D25
env law: the entrypoint's NUMA helper reads the HIP/ROCR/CUDA visible-device
lists, and the auto-detect path would count both render nodes on this
arch-mixed pair (R2 L4.3) — never leave the TP=1 pin to detection. The
variable's semantics (device index or UUID, ROCm 10) confirmed (Post
Research V2); only the index is target-verified.

**1.4 — Image-side `rocminfo` (the C01 re-export's OWN ROCr
enumeration).**

Step 0.1 proves the host driver; this one-shot container run of the pulled
image proves the image's enumeration — under the 0.30 re-export the R9700
must sit at index 0, which is what `ROCR_VISIBLE_DEVICES: "0"` targets.
Node-side, on `ai-gpu` (containerd via k3s; the pod has already pulled the
image into the `k3s.io` namespace):

```
ctr -n k3s.io run --rm \
  --entrypoint rocminfo \
  --device /dev/kfd --device /dev/dri --group-add 44 \
  ghcr.io/ownyourio/vllm-radiance-mxfp4:main
```

(docker equivalent, if the node has it:
`docker run --rm --entrypoint rocminfo --device /dev/kfd --device /dev/dri
--group-add 44 ghcr.io/ownyourio/vllm-radiance-mxfp4:main`.)

Expected: the gfx1201 R9700 at ROCr index 0 (the R9700-at-index-0 law).
If it fails: a different index means `ROCR_VISIBLE_DEVICES: "0"` targets
the wrong chip — retarget the values key (dual edit), then re-run 1.3.
Record alongside: the 0.30 image's own backgrounded `rocm-bandwidth-test`
sweep at serve start is the 0.30-class enumeration record (R3 L3.1) — its
output lands at the 3.1 capture.

## 2. Weights + staging facts

The `setup` init container is the staging actor (D14/D26); the pod log's
`mxfp4 staging:` lines are the authority — they say skip or download, per
tree:

```
kubectl -n default logs -l app.kubernetes.io/name=vllm -c setup
```

**2.1 — The trees, the marker, and the drafter.**

```
# run inside the vllm main container — the operator's own pod access (no agent tier grants it, EXPLORE §7)
ls /models/Qwen3.8-27B-Quark-AWQ-MXFP4
ls /models/Qwen3.8-27B-DFlash2-FP8
ls -la /models/.staged-mxfp4-*
```

Expected: the raw-release tree (the 18.41 GiB `model.safetensors` +
`config.json`), the drafter tree, and ONE marker file whose name keys both
shas: `/models/.staged-mxfp4-93245f7c00f1…-ee0cb26a8279…` (full
40-char pair). The `--model` value is the plain dir
`/models/Qwen3.8-27B-Quark-AWQ-MXFP4` — no HF-snapshot-hash segment: the
SHA pins the source, the PATH pins the output; this listing is the path
authority, a divergence is a values-side dual edit, never a template fix.
If it fails: trees absent = the init has not completed — the engine legs
are down, read the `-c setup` log above; a marker naming different shas = a
stale tree under moved pins — reconcile the chart's staging command (values
side), owner-visible.

**2.2 — Partial-tree remedy (node-side, never a cluster change).**

A pod kill mid-download leaves a partial tree. The automatic cover is by
construction: the marker `touch` is the command's LAST step (a partial
stage leaves no marker) and the `local_dir` layout resumes completed files
(HF downloader), so the pod's own init restart re-stages without operator
action. Where files are corrupted and the resume does not self-heal, the
operator's remedy is node-side on the local-path host directory behind the
`llama-swap` claim (the runbook's standing operator-access pattern — a node
command, no cluster instruction):

```
# on ai-gpu: the claim's host dir (k3s local-path convention, the llama-swap claim):
ls -d /var/lib/rancher/k3s/storage/pvc-e4f5adf3*_default_llama-swap
# then remove ONLY the partial tree so the next pod re-stages it whole:
rm -rf '<host-dir>/Qwen3.8-27B-Quark-AWQ-MXFP4'
```

**2.3 — The mtp-profile contingency ladder (the Q8 ruling's if-fails).**

The shipped dflash default does not touch the MTP load path — "Non-spec and
DFlash do not need that override" [84]: the recipe sets no
`RADIANCE_QUARK_BF16_MTP`. If a serve on the mtp profile dies at the MTP
head load: (1) verify `RADIANCE_QUARK_BF16_MTP=1` is set for that profile —
the baked `patch_quark_bf16_mtp` load path is the documented first step
(R3 L2.6: the raw release's embedded MTP tensors are BF16, and the
2026-11-03 module-name fix at `93245f7c` makes this revision strictly MORE
loadable than the `156be69f` revision the stack was qualified on); (2) if
that still dies, the `fp8_mtp.py` rewrite RE-LAND is the next rung — 0.27.1
tooling, two generations away from the shipped stack: the recorded fallback,
the owner's call, a re-scope decision, never a runbook improvisation.

**2.4 — The GGUF-stays line.**

`Qwen3.8-27B-UD-Q4_K_XL.gguf` STAYS on this claim — the class-10 llama.cpp
rung serves it (the D9 invariant). Do not delete it with any staging
cleanup.

## 3. Engine smoke (first engine gate)

The first on-RDNA proof of the 0.30 stack: does the recipe actually run as
planned? The GGUF-era plugin probe retires with its format — the marker
set below is the gate, and the recipe's source-verified-but-never-executed
status (R3's medium-confidence flag) is closed by the 3.1a capture.

**3.1 — FIRST-ENGINE GATE: the 0.30 marker set (grep the pod log).**

```
kubectl -n default logs -l app.kubernetes.io/name=vllm --tail=5000
```

Record every row from the first serve (R3 implications, the [94]/[92]
class):

| Marker | Expected | If missing / wrong |
|---|---|---|
| Entrypoint banner | the `radiance_preamble.py` preamble/banner lines | a bare vLLM banner = the wrong image is running — verify the pin (names block) |
| No exit-64 gate trip | the entrypoint's startup gates hard-exit 64 on retired/experimental var combinations [94 L10-64]; the D25 21-var law (D34-restored, D38-extended) is gate-clean, so NO exit-64 appears | an exit-64 = the pod env drifted from the qualified combination — the env block is the values-side fix |
| Target-attention engagement (the D36 re-pin — pre-D36 this row pinned the R4D report/selection lines) | the TRITON_ATTN engagement on the named backend + the `int4_per_token_head` KV info line; the GDN kernel lines STAY (the named-backend swap moves the target attention only [171]); the crash-#4 paste's `attn_*_h256_gqa6_fp8kv` prefill + decode kernel lines (5.7 MiB split-KV scratch) proved the fp8+R4D shape honored — that kernel pair is the recorded ALTERNATIVE's signature, not the shipped shape | TRITON_ATTN not engaged = backend/dtype drift — and under the int4 default an R4D-configured pod dies at startup rather than serving: R4D's `validate_configuration` prints its reason and refuses rather than falling back, its supported list at the pin being auto/bfloat16/fp8/fp8_e4m3 [171] |
| MXFP4 W4A8 GEMM engagement | the 0.30 analog of the 0.9.3 kernel-selection marker — RECORD THE EXACT STRING from the first serve (the qualified `RADIANCE_MXFP4_W4A8=1` set) | absent = the W4A8 lane did not engage — the env set is the suspect |
| WRONG-ENGINE absence marker | the stock "default W8A8 Block FP8 kernel config" line must NOT appear — the 16 R9700-named tuned block-FP8 config JSONs are baked (R3 L1.2), so the generic line is the wrong-engine signal | it appears = the tuned configs were not picked up — record and stop |
| Text-only serving marker (the D38 NEW positive step-3 line) | the INFO-once `All limits of multimodal modalities supported by the model are set to 0, running in text-only mode.` (registry.py L146-149 @ `ced6857a`, R8b 226) — the shipped `--language-model-only` zeroes every modality limit at the getter and trips the registry's text-only short-circuit, so the encoder rehearsal never runs. R8b.1 correction on the record: the `compute_mm_encoder_budget` WARNING that R8.1c predicted does NOT fire on this path (the whole MultiModalBudget build is skipped before it) — the INFO is the line the boot day greps | absent = `--language-model-only` lost from the serveArgs — the 3.1a args diff localizes; a bare `{"image": 0}` restore is the known WRONG shape (the video-999 default keeps the encoder rehearsal alive on a max-size VIDEO dummy with this line absent — the image-0 trap, R8b q1) |
| ViT backend lines — ABSENCE-EXPECTED (the D38 inversion of the D34-era row) | both the RDNA FA literal `Using Flash Attention (Triton backend) for ViT model on RDNA.` (rocm.py L771-773 @ `ced6857a` [139]) and the per-layer `Using AttentionBackendEnum.FLASH_ATTN for MMEncoderAttention.` confirm are ABSENT BY DESIGN at text-only serving — the ViT never runs, so absence IS the shipped state. The drift reading INVERTS: a Flash/Triton-ViT line now means the `--language-model-only` flag was LOST — record and stop. The two literals stay recorded verbatim here for the 48 GB-RDNA3 re-enable rider (R8b.4e): together with the C02 serveArgs pair and the C04 `input` leg they copy back, and this row's expectation flips to PRESENT | the PRESENCE of either literal = the serveArgs moved (3.1a). A bare `Using Flash Attention backend for ViT model.` = the CDNA branch (L757-763) — the arch-view drift signal: `RADIANCE_GFX_ARCH` un-spoofed to gfx1250 running AITER's Triton mha, a different, unqualified config — recorded BARRED (R5.3), that reading standing whenever the ViT runs |
| `Mamba cache mode` | align | drift = the serveArgs moved — 3.1a diff |
| Spec-family registration | the `spec_decode_*` metric family EXPECTED at 0.30 (dflash rides the stock V2 dflash2 path, R3 L2.3); the `diffusion_*` family is the RECORDED fallback assertion — which one registers is what the capture closes | neither family = the speculative config did not load |
| KV triple | `Available KV cache memory` / `GPU KV cache size` / `Maximum concurrency` — record VERBATIM (the 3.5 re-measure gate's input; no pre-registered target, the gate derives it) | triple absent = boot died before the pool — 1.2/3.1b |
| Graph capture | the PIECEWISE compilation/graph lines (the `RADIANCE_COMPILATION_CONFIG` seam appends `--compilation-config {"cudagraph_mode":"PIECEWISE"}`) | eager/other mode = the seam not honored — record |
| Startup complete | `Application startup complete` (the vLLM-standard line, the FASTBOOT-class log-read carries [52]) | absent = never reached serving — 1.2's failure class |
| Topology sweep | the backgrounded `rocm-bandwidth-test` output [94] — the 0.30-class enumeration record | absent = record why |

The spec-method toggle (the record, not a day-one lane): swapping the
`specMethod` key to `mtp` is three coupled values edits — the specConfig
JSON `{"method":"mtp","num_speculative_tokens":4,…}` (K4, the measured
depth), the main env's `RADIANCE_QUARK_BF16_MTP=1` (the raw release's
BF16-head load path, the R3-Q6 coupling), and the C03 init's drafter-skip
record. The MTP K4 lane carries a 29/30 tool-gate FAIL caveat [108] — the
toggle is not tool-qualified. Every gate below runs on the shipped dflash
default.

**3.1a — DRY_RUN-analog capture (closes R3's "no execution of the 0.30
recipe" medium-confidence flag).** The guide's standing DRY_RUN rule
translated to this surface — a READ, then a diff:

```
kubectl -n default get pod -l app.kubernetes.io/name=vllm \
  -o jsonpath='{.items[0].spec.containers[?(@.name=="vllm")].args}'
```

Record the rendered args, the startup-log resolution lines, and the
entrypoint seam outputs (the appended `--compilation-config`, the
`RADIANCE_WEIGHT_QUANTIZATION=auto`'s omission of `--quantization`), and
DIFF against the plan's D24 recipe — the chart's serveArgs is the expected
side. A diff is a values-only fix at the C02 surface (the dual-edit path
law: chart serveArgs + the service twin), recorded here. The pod args
start with the MODEL PATH (the entrypoint supplies the verb) — a
`vllm serve` token in the args is the double-verb transcription error, the
capture's first check.

**3.1b — THE STARTUP CONTINGENCY — THE SANCTIONED B FALL-THROUGH (the
OQ13 dual-edit class, the D31 live-risk backstop — re-framed by D36:
recorded, not improvised).** If the engine refuses at startup at the
262144 ceiling — the KV-pool-degenerate class, and by the envelope's own
law the failure is loud and probe-gated (1.2), never a silent mis-serve —
then, under the shipped q4 boot config, this is the DESIGNED OUTCOME PATH,
not a crash class: with `--mamba-ssm-cache-dtype bfloat16` the fixed
admission floor fits (the crash-#4 silence — a zero estimate, no number —
was the fp8/fp32-ssm shape, R6.1.2), so the refusal PRINTS the engine's
estimated-max-length line (`estimate_max_model_len`, emitted only when a
positive length fits [155]) — RECORD that number, it is the cap value.
The owner rules the cap AFTER the refusal (a fresh D31(e)-class ruling)
and the operator applies it as the values dual edit (the C02 serveArgs
line + the service twin), recording the engine-log KV triple before/after.
The catalog/surface re-pin follows the same ruling: the contingency moves
ONLY THE ENGINE ARG; the advertisement-following-the-engine-down question
re-opens only if the owner wants it (the D31 record — the 262144
advertisement stays TRUE iff the boot holds, D36). D37 promotes this row
to THE RUNNING PATH (the boot-now / B-on-the-print ruling); D38 ships
the donor package that ruling anticipated — f2 + the vision drop,
expected pool 4.74 + δ against the grouped 5.06 bar (the 3.5 f2 row
owns the δ readout) — so the 262144 attempt now clears UNLESS the
pathological sampler/drafter-binding tail misses it by ≈0.16; there the
printed estimate (the C+f2 print law: ≥243k + δ, a prediction not a
promise) is the cap-ruling source and the route to walk, not a failure
to dodge.

**3.2 — In-cluster `curl` to the vLLM service.** Operator-run, from any
machine with cluster access (read-only probe):

```
kubectl -n default port-forward svc/gpu-ai-vllm 8000:8000
curl -sS http://127.0.0.1:8000/health
curl -sS http://127.0.0.1:8000/v1/models
```

Expected: `/health` → 200; `/v1/models` lists the served name
`qwen3.8-27b-vllm` with `max_model_len: 262144` — the engine cap == the
catalog axis: the true axis is readable on both sides (the Q11 ruling).
If it fails: `/health` down = the pod is not actually serving (1.2); a
different served name = `--served-model-name` drift in the serveArgs;
a SMALLER `max_model_len` = 3.1a's diff or 3.1b firing — which side moves,
and whether the advertisement follows the engine down, is the owner's
call.

**3.3 — One 1-token chat completion.** The MXFP4 serve + first-token
proof — weights load from the step-2 raw-release tree through the native
Quark MXFP4/W4A8 path (the `RADIANCE_WEIGHT_QUANTIZATION=auto` seam
omits `--quantization`; vLLM consumes the checkpoint's Quark metadata),
not a GGUF-plugin or stock-safetensors path:

```
curl -sS http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","messages":[{"role":"user","content":"Reply with the single word: ok"}],"max_tokens":1}'
```

Expected: HTTP 200 with one generated token.
If it fails: the weights loaded but decode dies — the recipe runs graphed
(PIECEWISE, no `--enforce-eager`), so the suspects are the W4A8 GEMM / GDN
kernel lanes on gfx1201 (report the log lines; the software-maturity
class).

**3.4 — RETIRED BY D38: the multimodal 1-image smoke (the vision-drop
ruling).** Requirement #3's owner-visible proof DIES WITH VISION by the
owner's own ruling (R8-Q1 "C — drop vision"; DECISIONS D38): the shipped
`--language-model-only` makes the engine refuse image inputs at
validation and the catalog `input.image` marker is FALSE. DO NOT RUN a
multimodal smoke — an image request is REFUSED at input validation BY
DESIGN and the refusal proves nothing about the install. The FA
crash-gate class of crash #2 is
NO LONGER REACHABLE: 3.4 was the first-multimodal-request DETECTOR for
the D34/D35 flash-attn install + the (8)-slot var surfaces, and at
text-only serving no request can ever reach the ViT path. The D33–D35
records above stand as history — record, don't erase: the install layer
and the var are DECORATIVE-BUT-HARMLESS (C01's dated line; the var stays
in the 21-var law), and R5-Q2 (the crash-#2a `ValueError:
total_mblocks exceeds MAX_PROGRAM_GRID_SIZE` provenance) stays OPEN with
its crash class now permanently unreachable. 3.3 the 1-token completion
STAYS as the serve gate. The `TRITON_ATTN` encoder-pin future-performance
alternative (R4.5(c)) rides the re-enable below, gated on its own
vision smoke.

48 GB-RDNA3 re-enable rider (R8b.4e): the restore is a copy-back across
three surfaces — the C02 values.yaml serveArgs comment carries the
removed `--limit-mm-per-prompt` + `'{"image": 4}'` pair VERBATIM with
its D32-era parse law (the 0.30 CLI parses the flag through json.loads —
a single-quoted JSON dict; the 0.27.1 launcher's `image=4` passthrough
dies at argument parse, observed on-target), the C04 catalog rows'
`input` leg returns to `["text", "image"]`, and this step's smoke + the
step-3 ViT marker row return — the literals are recorded verbatim in
that row. The restored smoke shape: the `{"image": 4}` limit, a tiny
data-URL 1×1-PNG request, HTTP 200 + completion expected with no
text-only stripping, and the 3.1 Flash-(Triton)-on-RDNA marker row
expected PRESENT again (absence = package or var drift — the D34-era
reading returns). NEVER restore with a partial zeroing: `{"image": 0}`
alone leaves video at its 999 default and the warmup profiles a
max-size VIDEO dummy instead — the image-0 trap, zero saving (R8b q1).

**3.5 — THE DAY-ONE RE-MEASURE GATE (the owner's Q2 standing condition —
the SOLE envelope path at 0.30, R3 L2.4 — re-bound by the Q11 ruling to
the SHIPPED 262144/2560/3 shape).** BEFORE any step-6 number is trusted:

(a) Record the 3.1 KV triple (the pool's birth certificate —
`Available KV cache memory` / `GPU KV cache size` / `Maximum concurrency`).
(b) Drive the shipped-shape load class: the three-session saturation
drive at the step-5/6 class — 262144-class contexts within the DERIVED
pool (`--max-num-seqs 3` is the Shape-B constant that saturates it).
(c) Read the pool headroom and the preemption behavior (the 6.6
signals).
(d) Optional post-calibration: `--kv-cache-memory-bytes <int-bytes>` as a
values-only swap — the flag exists at 0.30, int bytes, "when not-None
ignores gpu_memory_utilization" (R3 L2.5). The gate DERIVES the pool at
the shipped shape; the 8.49 GiB reference row is the 220000-class 0.9.3
artifact — a provenance datum, NOT the target, and the chart deliberately
ships no pin.
(e) The re-measured constants are the follow-up re-pin. Marked surfaces:
the C02 serveArgs util/KV-pin lines, the testlib pairs, and this
runbook's envelope block.

The D36 amendment adds the NAMED INVESTIGATION legs below (flagged
levers — no prescribed edits on the runbook's authority); D37 adds f4,
the owner-run host datum:

(f1) The KV-grouping/padding lever — CLOSED as the R7 deep-dive's F1-0
resolution (DECISIONS D37), records-only, NO ship edit:
`RADIANCE_KV_GROUP_OPT=1` / size 8 stays image-baked, no new env (one
would re-open the 20-var law).
The PASS marker PAIR: PRESENT — `[radiance] kv cache groups: size 8, 9
groups, ~368-378 blocks/request (upstream would pick size 5)` (378 proven
at the fp8 crash boot, 368 predicted at the int4 boot — the boot log
arbitrates); ABSENT — the upstream pair `Add 2 padding layers … 4.17%` +
`Add 4 … 25.00%`: its presence means `RADIANCE_KV_GROUP_OPT` got flipped
= the anti-lever (+1.08 GiB grouped demand, halved concurrency, never
set): record and stop. The single `Add 3 padding layers, may waste at most
60.00% KV cache memory` (`kv_cache_utils.py:1617`) is EXPECTED-AND-PRICED
at 0.021 GiB per max request (3 SWA dummy slots × 4 blocks — the % is
per-bucket, not per-pool: where the padding lands is what matters, the
fork's law); its ×2 in the crash-#4 paste = two grouping passes, restart
class, covered by the f3 log-top ask. The re-pin law reads live off the
boot log: `needed GiB = blocks × S × bs × 1088` (int4 shape), arbitrated
by `Setting attention block size to N tokens` + `Padding mamba page size
by X%`; 368 blocks/request ⇒ prefill-checkpoint-blocks 0 (374 ⇒ 1) —
closes R6's blind spot. The force-S alternatives F1-1..F1-4 are
recorded-priced-not-shipped (R7.5 + the R7.3(e) S-sweep: no legal S boots
262144, max recovery 0.021 GiB paid in 69 block tables).
(f2) The graph-profiling pre-tax — **SHIPPED UNDER D38**: the row
re-pins from advisory-quote to shipped-shape readout.
`VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS: "0"` joins the main-container
env law (the 20-var exact set becomes the 21-var law — the C02 pair);
the PRICED-NOT-SHIPPED status ENDS. The turn-off adds the FULL estimate
to the check-time pool (~1.27 at this capture set — the `gpu_worker.py:655`
advisory's disabled half and the `Graph capturing finished in 4 secs,
took 1.26 GiB` real capture stand as the shape record), NOT
"estimate − real": the graphs STILL capture at runtime and land on
allocator slack AFTER the KV sizing — the recorded capture-bet. The
δ-READOUT LAW: the boot prints `Available KV cache memory: X`; the C+f2
pool decomposes X = 3.47 (the measured D36-combo pool) + ~1.27 (f2,
deterministic) + δ, so δ = X − 3.47 − 1.27 = X − 4.74, where δ ∈ [0.16,
2.1] is the removed encoder rehearsal — a phase-max competitor inside
the transient-peak headroom, NOT additive [R8b 229]; ONE boot line
settles it. The BARS: expected pool 4.74 + δ vs the grouped 5.06 wants
δ ≥ 0.32 (the plain check X ≥ 5.06); the full-session admission
(0.95·pool ≥ 5.06) wants δ ≥ 0.59 (X ≥ 5.33) — likely with f2, not
certain. The engine's disabled-branch WARNING — `CUDA graph memory is
not accounted for during KV cache allocation, which may require lowering
--gpu-memory-utilization to avoid OOM` — is the EXPECTED-AND-PRICED line
of the shipped bet [R8 209]. Surviving detectors of the bet, 3.4
retired: the boot-day WARNING/δ readout + the first long session — f2's
honest residual risk, on the record; the f1 marker pair is UNAFFECTED
(R8b.2) and the f4 host datum carries. The advisory's raise-util half is
already the shipped state — the D36 0.98.
(f3) THE MODEL-LOADING-LINE ASK — the crash-#4 paste window began at
`Available KV cache memory: 1.12 GiB` (`gpu_worker.py:640`) and did NOT
include `Model loading took X GiB` (it prints before the KV check): the
ask STANDS for the log TOP [160], the weights datum stays formally open.
The bounds argument (reaching the KV check ⇒ resident ≤ ~25.9 GiB; the
INT2 draft head at 0.33 GiB/rank corroborates the packed-load side)
keeps hypothesis (a) favored. The optional `VLLM_LOGGING_LEVEL: "DEBUG"`
diagnostic re-boot (values-side, removable, NOT ship shape — R6.2
item 4) rides the same day to split the ~27.5 GiB held.
(f4) The owner-run host datum — `rocm-smi --showmeminfo vram` on ai-gpu,
sampled during the load window (R6.2 item 5): host-side ground truth of
the held-vs-pool split for the f3 ledger. Human-run — the repo's
no-agent-pod-exec law; no agent tier grants it and none is asked.

The arithmetic this gate owns (the D38 re-pin ON THE BOOT DATA — D37's
insurance-vs-resident ledger stands as amended): the shipped D36-combo
boot printed needed 5.06 GiB / available 3.47 GiB / estimated maximum
model length 164,512 — requested ceil(31.86·0.98) = 31.22 ⇒ held
≈ 27.75 — splitting as resident ~21–22 (weights incl. the PERMANENT
0.858 GiB ViT tower — the vision drop frees insurance, never the tower
[R8] — plus HIP context) and ~5–6 GiB of STARTUP-REHEARSAL INSURANCE
the engine deducts before sizing: the profiling-dummy peak (pure-LLM
dummy + drafter propose + sampler at 2560 tokens — 262144 lives only in
the check formula [R8b.1] — plus, pre-D38, the mm encoder's one max-item
rehearsal), the graph estimate pre-tax ~1.27. The D38 shape ships TWO
insurance legs off that ledger: f2 returns the full ~1.27, and
`--language-model-only` removes the encoder rehearsal (δ ∈ [0.16, 2.1],
phase-max, not additive — the f2 row owns the δ readout) — expected
pool 4.74 + δ vs the GROUPED bar 5.06 (S=8, bs 1696, 368 blocks/request
— the bar UNCHANGED by the vision drop, R8b.2; the raw per-layer
4.93/5.63 stand as BOUNDS; D37's predicted ~3.67 landed 3.47 measured).
Boot bar δ ≥ 0.32; the pathological sampler/drafter-binding tail misses
5.06 by ≈0.16 — there the 262144 boot still refuses and PRINTS the
fresh cap: the print law at the C+f2 pool class is ≥243k + δ (f2 alone
re-printed ≈243k at the 4.74 pool; δ moves it up), and the print drives
the B cap ruling exactly as D37 ruled. Donor rows retired on evidence:
D36's `{"image": 1}` profile-day knob is RETIRED by R8's one-dummy law
(the warmup profiles ONE maximum-feature-size dummy whatever the limit
— 0 GiB freed), and the mtp-K4 lane (−~2.0 at its 29/30 tool caveat)
stays the named-not-shipped donor.

PASS = the shipped 262144/2560/3 q4 plan shape boots and holds for this
node (record the derived pool). FAIL = the values re-pin to the measured
pool; and if the failure was a hard reject rather than a tight pool, that
is the 3.1b contingency's class — under D37 the loud refusal printing the
estimate is the OWNER-RULED RUNNING PATH (the boot-now / B-on-the-print
ruling: record the printed number — at the shipped C+f2 shape the print
law is ≥243k + δ (R8b), a prediction not a promise — the owner caps the
engine arg there as a fresh
D31(e)-class ruling), not a failure to dodge. Owner-visible at the
presentation either way.

**3.6 — THE INT4 GATE — BOOT-CONFIG QUALIFICATION (the round-2 Q5 ruling +
the D36 promotion — the owner's R6-Q1 answer "A — q4 default, boot at
262144").** The two 0.30 edits are no longer a day-one VALUES experiment:
they ARE the shipped boot config — the `kvCacheDtype` default is
`int4_per_token_head`, the C02 serveArgs carry `--attention-backend
TRITON_ATTN` + `--mamba-ssm-cache-dtype bfloat16` + util 0.98, and ArgoCD
boots the shape. There is no flip step to run anymore (the pre-D36 flip
recipe — the sanctioned 5.2-style git-only pair + ArgoCD's own
reconciliation, no manual sync — stands as the superseded record). The
gate legs are unchanged and now BIND the ship path IFF THE BOOT HAPPENS
(the D37 rider: a 262144 refusal routes the day through the 3.1b
B fall-through BEFORE these legs run), in order:

1. Startup acceptance: the boot at 262144 — the `int4_per_token_head` KV
   info line appears and no refusal-shaped startup death occurs (an
   R4D-configured pod under int4 would print its refusal and die —
   R4D's supported list at the pin is auto/bfloat16/fp8/fp8_e4m3 [171]);
   on refusal the engine PRINTS its estimated-max-length line — the 3.1b
   sanctioned B fall-through, not a crash class. Re-record the 3.1 KV
   triple: the ~16.5 KiB/token class should widen the pool over the
   crash-#4 fp8 datum (record, do not assume).
2. The 3.3 smoke (the 3.4 vision smoke retired with D38 — no separate
   vision-quality sub-leg existed here to retire).
3. The acceptance-rate smoke (the 6.4 either-family counters).
4. The quality leg: a GSM8K-class probe against the 97.6–98.4% reference
   row of the 0.9.3-era MXFP4 record [45] — the reference class NAMED,
   recorded not claimed (int4 changes the KV path that reference ran on);
   the upstream int4 defect classes — #53086 (wrong-values, open at the
   tag) and #48721 (the SWA-crash class our 5 sliding drafter layers sit
   in) [168][169] — make this leg the LOCAL AUTHORITY.
5. The tool smoke (3.7) — int4 changes the KV path the 30/30 record
   exercised, which is fp8-only [108].

Gate PASS → the q4 ship shape holds and the 262144 advertisement stays
TRUE. Gate FAIL (quality/tool on target) → the fp8 + R4D pairing returns
as the recorded ALTERNATIVE — the original D27 gate logic inverted on
evidence — and that return forces its own D31(e)-class cap ruling,
fp8@262144 being arithmetically dead on this card (R6). The D27-era close
("Revert to the default after the gate either way — the fp8 default is the
ship state; the gate is a measurement step, not a config flip") is
SUPERSEDED — recorded, not erased. The 48 GB-RDNA3 note stays ledgered
either way.

**3.7 — THE TOOL SMOKE (the round-2 Q6 marker's closing gate — the
TP2→TP1 transfer, R3 L3.2's confidence statement).** The
keypress-fixture class against the live pod, via the public chain (step 4's
route). The 3-tool browser-style fixture set (`click` / `keypress` /
`assert`, each with typed required fields `reasoning` / `confidence` /
`stepComplete` + per-tool key/condition/ref); the two cases are
`keypress_auto` (tool_choice=auto, parallel_tool_calls, two independent
calls) and `keypress_parallel` (tool_choice=required, two calls). These are
the synthetic wire regressions — NEVER execute the generated tools [112];
inspect the wire. Operator-constructed `keypress_auto` request:

```
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","temperature":1,"stream":true,"parallel_tool_calls":true,"tool_choice":"auto","messages":[{"role":"user","content":"On the search box (ref 12), press Enter, then press Tab. Call keypress once per key."}],"tools":[{"type":"function","function":{"name":"click","description":"Click an element on the page","parameters":{"type":"object","properties":{"reasoning":{"type":"string"},"confidence":{"type":"number"},"stepComplete":{"type":"boolean"},"ref":{"type":"string"}},"required":["reasoning","confidence","stepComplete","ref"]}}},{"type":"function","function":{"name":"keypress","description":"Press a key in the focused element","parameters":{"type":"object","properties":{"reasoning":{"type":"string"},"confidence":{"type":"number"},"stepComplete":{"type":"boolean"},"key":{"type":"string"}},"required":["reasoning","confidence","stepComplete","key"]}}},{"type":"function","function":{"name":"assert","description":"Assert page state","parameters":{"type":"object","properties":{"reasoning":{"type":"string"},"confidence":{"type":"number"},"stepComplete":{"type":"boolean"},"condition":{"type":"string"}},"required":["reasoning","confidence","stepComplete","condition"]}}}]}'
```

For `keypress_parallel`: same request with `"tool_choice":"required"`.
Expected: tool-call JSON validity — exact tool names, exact/typed
arguments, no unexpected fields, `finish_reason` ∈ {stop, tool_calls}, and
the complete SSE stream (incremental `data:` events, no stream error,
`data: [DONE]` at the end). Repeat both cases several times and RECORD THE
PASS/FAIL COUNTS as the TP1 tool datum — the first one that exists (the
upstream 30/30 record is TP2-only: two GPUs "is the only configuration
tested so far" [91]) — the `tools: true` marker's standing risk closes or
re-opens on this leg.
If it fails: the marker's owner-visible reconsideration — the `tools: true`
row key is the C04 surface (the three catalog rows); the revert is a
values+M3 re-pin, the owner's call, recorded not improvised.

## 4. FE chain smoke

Through the public chain `https://llama.spencerslab.com/v1` — the peers.vllm
hop is the only client route (D7; the gpu-ai generic-ingress injects the
`llama-timeouts` ServersTransport, `responseHeaderTimeout: 0`, on every
subdomain Ingress, so deep prefills do not 499). The whole step carries
UNCHANGED through the base move — the hop is byte-stable: the recipe keeps
the engine on port 8000 (the service, probes, peer hop, and catalog all sit
on it), and the upstream launcher's 8080 default never reaches the pod
(R3 L1.3; D20/D28).

**4.1 — Models list: qualified AND unqualified.**

```
curl -sS https://llama.spencerslab.com/v1/models
```

Expected: `qwen3.8-27b-vllm` is listed (unqualified resolution — lab
convention, D10) and the qualified form `vllm/qwen3.8-27b-vllm` resolves.
Record whether the entry carries a `max_model_len` — that is R3 OQ3
(closes on-target: does the pinned llama-swap v266 populate the peer
model's context length in `/v1/models`?).
If it fails: the model missing from the list = the peer block or its
`models:` entry is wrong in `services/gpu-ai/prod/values.yaml`.

**4.2 — STREAMED chat completion (SSE through the public chain).** This is
the R3-weakest-claim verification: "no SSE risk through the lab's public
chain" was inferred (Go flush semantics, no compress middleware, the
working llama.cpp streaming chain) and never measured — the first streamed
vLLM response through the public host is the measurement.

```
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","stream":true,"max_tokens":32,"messages":[{"role":"user","content":"Count from one to five, one word per line."}]}'
```

Expected: `data:` lines arrive incrementally (several bytes at a time over
seconds), ending `data: [DONE]`.
If it fails: one lump at the end = a hop is buffering (next suspect: a
compress middleware — none is in the repo — or the transport); 502-EOF =
the post-SSE keep-alive class (R3 OQ4 watch-item: no peer-level
`disableKeepAlives` in v266 — file upstream, tune uvicorn).

**4.3 — The `/ui` models page.** Open `https://llama.spencerslab.com/ui` →
Models.
Expected: `qwen3.8-27b-vllm` listed (peer models appear in listings — R3 Q5).

**4.4 — The urgent model row.** A request via `qwen3.8-27b-vllm-urgent`
works — the OpenCode row's `body` merge is live:

```
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm-urgent","max_tokens":8,"messages":[{"role":"user","content":"Reply: ready"}]}'
```

Expected: 200 + completion — the row resolved to the same wire model with a
different body priority. This closes R4's medium-confidence claim (a): the
first observed model-level `body` merge on this exact provider chain.
If it fails: the row 404s or resolves to a different model = the catalog
row / peer name is wrong in `.opencode/opencode.jsonc` or the peer block.

## 5. Priority proof (R4 acceptance lines)

The engine runs `--scheduling-policy priority` — the D24 CARRIED flag,
0.30-verified (R3 L2.5): the four-class wiring's engine half. The
scheduler knob is unmeasured under this stack — that risk stands and this
step is its measurement. The peer floor `filters.setParams
"priority?": 5` puts non-priority clients in the default class. The class
rows (the four-class contract, cf-105-vllm-followup D1): urgent class row
`qwen3.8-27b-vllm-urgent` (priority 1), default class row
`qwen3.8-27b-vllm` (priority 5), low class row `qwen3.8-27b-vllm-low`
(priority 9). The background class (card `Priority` 10+) is OFF vLLM
entirely — the llama.cpp `qwen3.8-27b-q4` leg, no vLLM row, no preemption
surface.

**5.1 — Explicit `priority: 5` through the full chain.**

```
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","priority":5,"max_tokens":8,"messages":[{"role":"user","content":"Reply: ack"}]}'
```

Expected: 200 + completion — the non-zero value is legal under the
priority policy and the body field reached vLLM.

**5.2 — OPTIONAL: fcfs negative proof.** The only step that requires a
temporary flip; belt-and-braces for the R4 pass-through claim (the step-4
chain smoke already exercises the body merge for the default and urgent
rows). Run it only if the owner wants the negative proof:

1. GIT values change (human-run): in `charts/vllm/values.yaml`'s
   `app-template.serveArgs`, flip `--scheduling-policy` from `priority`
   to `fcfs`; commit on the ticket branch; ArgoCD's own reconciliation
   picks it up (no manual sync — sync is not a runbook step).
2. Re-run the 5.1 request.
   Expected: vLLM REJECTS it with the non-zero-priority error (the fcfs
   gate, R4 Q1) — proving the body field survived both OpenCode's merge
   AND llama-swap's proxy end-to-end.
3. Flip the values back to `priority`; let reconciliation restore the pod;
   re-run 5.1 to confirm 200. Do not leave `fcfs` in place.

**5.3 — Behavioral: the classes saturating the pool** (R4 acceptance
line 2). The `--max-num-seqs 3` drive (the Shape-B constant — three
concurrent sessions saturate the re-measured pool, the 3.5 gate reads its
truth): drive long-context sessions of the low and default classes
concurrently, keep an urgent-class request running as the control, until
the pool saturates; then read the preemption split in central Prometheus:

```
sum by (model_name) (increase(vllm:num_preemptions_total[10m]))
```

Expected: the urgent class shows NO preemptions while the default/low
classes do. A PASS is the priority split holding — preemption under
exhaustion is the design (the envelope block), not a fault. Under KV
exhaustion the four-class victim order is low(9) → default(5), never
urgent(1): vLLM force-preempts the highest-numbered priority first (R4 Q1:
victim = `max (priority, arrival_time)`); the carried `--watermark 0.05`
preserves the arbitration headroom.
If it fails: urgent-class preemptions mean the class values did not reach
the engine (check 4.4 and the row's `body` merge); zero preemptions
anywhere = the pool never saturated (drive longer contexts — at the 262144
cap the pool is the binding side, not the cap, per the envelope).

## 6. Benchmark (pre-registered expectations — NOT claims)

Registered BEFORE the numbers, on the R3 L3.3 weakest-claim ground stated at
the envelope block: no 0.30 TP1 measurement exists in any published form,
so what follows is anchor classes and sanity rows; the 0.30 TP1 dflash
numbers at the shipped shape are the ON-TARGET UNKNOWN, and the 3.5
re-measure gate owns them. Record every number — they are the follow-up
card #2 thresholds and the 3.5(e) re-pin input.

**6.1 — The 0.9.3 TP1 ANCHOR CLASS (same-card-signature record, the
0.27.1-era stack):** single-stream combined decode **137.7 t/s** /
c=8 aggregate **416.3 t/s** / update p99 **35.7 ms** / TTFT p50 **95 ms** /
prefill **2.5–2.8k t/s** — measured on the `1x7551-32624` card signature
at the 65536 Shape-A context, at the 210 W cap −75 mV [49]. Provenance
caveats ride: a different engine generation, a different (smaller) context
shape, the reference box's power conditions — the context-class reference,
NOT the like-for-like 262144 datum.

**6.2 — The 0.30 TP2 cross-stack SANITY class (record only):** the
publication table [108] — non-spec 53.9 weighted / DFlash K7 186.7
weighted; acceptance MTP 55.79% / K5 51.92% / K7 42.26%; accepted-plus-
bonus tokens per draft 3.596 (DFlash K5) / 3.958 (K7). Topology-confounded
against our TP1 pod (their qualified configurations are TP2 — R3 L3.3) —
same engine family, different topology; a sanity row, never an expectation.

**6.3 — The on-target drive (the unknown's first datum):** single-stream
tok/s, c=3 aggregate at the shipped shape, prefill rate, TTFT — at the
262144/2560/3 constants within the 3.5-derived pool. These numbers are the
3.5(e) re-pin input and the follow-up card #2 thresholds.

**6.4 — Acceptance smoke (the shipped K7 dflash lane):** the either-family
counters from 3.1's capture — `spec_decode_*` expected (stock V2 dflash2
path, R3 L2.3), `diffusion_*` the recorded fallback:

```
sum(rate(vllm:spec_decode_num_accepted_tokens_total[5m])) > 0
```

(re-run under whichever family 3.1 says registered). Anchor class for the
K7 lane: the TP2 42.26% / 3.958 row [108] — sanity, not expectation.

**6.5 — Node RAM headroom after full load.**

```
free -h
```

Compare `available` against the step 0.3 baseline (EXPLORE §8.6).
Expected: the delta stays inside the vLLM pod's 16 Gi request / 32 Gi
limit — no swap-thrash, no pressure on Strata's 116 Gi-limit pod.

**6.6 — KV-pool exhaustion behavior.** Several simultaneous long sessions
until `vllm:kv_cache_usage_perc` (central Prometheus) peaks:

```
vllm:kv_cache_usage_perc{model_name="qwen3.8-27b-vllm"}
```

The gauge is a fraction 0–1 (the R2 L4.5 name, presumed stable at 0.30 —
the first-serve `/metrics` scrape at 3.1 confirms the name). Expected: the
gauge peaks, the lower-priority class is preempted + recomputed while the
urgent class is unimpeded. A PASS when the priority split holds —
preemption is intended; the recompute cost is R4 OQ6 territory (the
prefix-caching interaction, the carried `--enable-prefix-caching`),
recorded for the follow-up.

**The step-7 queries' name set** (the 0.27.1-verified class, presumed
stable at 0.30 — the 3.1 `/metrics` scrape is the confirmation):
`vllm:time_to_first_token_seconds`, `vllm:inter_token_latency_seconds`,
`vllm:num_preemptions` (exposition `vllm:num_preemptions_total`),
`vllm:request_success`, plus `vllm:kv_cache_usage_perc` above.

**The power-policy caveat (carried from the envelope):** the anchor rows
were measured under the reference box's 210 W cap −75 mV; this node runs
BOCO runtime power management on the R9700 (EXPLORE §1) — different
conditions, prefill is same-card-only comparable. 6.1/6.2 are anchor
classes, not expectations.

## 7. Monitoring check (R5 deploy confirmations)

**7.1 — `up{job="vllm"}` in central Prometheus**
(`prometheus.spencerslab.com`):

```
up{job="vllm"}
```

Expected: 1. This confirms the job-label fallback (R5 Q2): no
`k8s.grafana.com/job` annotation is shipped, so the job falls back to
`app.kubernetes.io/name` = `vllm`.
If it fails: `up` absent = the pod annotations did not land (7.6);
`up{job="..."}` under a different job name = the fallback chain broke.

**7.2 — The histograms are quantile-computable** (RW 0.1 classic-histogram
integrity through the remote-write into central Prometheus 3.6.0, R5 Q2),
on the step-6 name set:

```
histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[10m])))
```

Expected: a finite number once 6.3 has produced TTFT samples (not NaN, not
empty).

**7.3 — Dashboards: the re-pin need (NOT this ticket's bar).** The
central Grafana's vLLM dashboard entries (the cf-105-era `url:`-pinned
imports, upstream tag v0.33.0) do NOT fit this engine — the metric names
drifted (this stack's 0.27.1/0.30-class set vs the v0.33 panels). The
re-import is a CENTRAL-STACK edit — the owner's surface, not this repo's:
this step records the re-pin need + the step-6 name set as the follow-up
action (the recorded follow-up of the D-T2 disposition: the dashboards
values' v0.33.0 base-image pin is stale by design until the owner
re-imports). The repo-side bar for step 7 is the central-Prometheus legs of
6.6/7.1/7.2 only.

**7.4 — The Loki stream for the pod** (`loki.spencerslab.com`, LogQL):

```
{container="vllm"}
```

Expected: the engine log lines (the periodic engine stat line, which
self-demotes to DEBUG when idle) plus uvicorn access lines — note the
`--disable-access-log-for-endpoints` flag is NOT in the shipped recipe (the
round-2 Q7 drop — the flag exists at 0.30, the drop is a choice, R3 L2.5),
so `/health` and `/metrics` access lines DO appear with the probe traffic:
record their volume, it is noise, not a fault.

**7.5 — `finished_reason` enum values** observed in central Prometheus:

```
vllm:request_success_total
```

Record the distinct `finished_reason` label values seen (R5 OQ6 — they feed
follow-up card #2 alert #9, which filters
`finished_reason=~"error|abort"`).

**7.6 — Scrape annotations: exactly two, no interval key.**

```
kubectl -n default get pod -l app.kubernetes.io/name=vllm \
  -o jsonpath='{.items[0].metadata.annotations}'
```

Expected: `k8s.grafana.com/scrape: "true"` and
`k8s.grafana.com/metrics.portNumber: "8000"` — and the ABSENCE of a
`metrics.scrapeInterval` annotation (the cf-105 scrape ruling: the 60 s
scrape is the k8s-monitoring v4 annotationAutodiscovery feature default;
the absence is the contract).
If it fails: a third `k8s.grafana.com/*` key = an annotation crept into
`charts/vllm/values.yaml`; an enabled value that is not `"true"`/`"8000"` =
the `app-template.monitoring.annotations` gate is mis-rendered.

## 8. Coexistence — the ONE-ENGINE-PER-CARD law

The static coexistence law (the round-2 Q7 ruling's consequence; unchanged
in substance from the re-plan, re-scoped here): **one engine per card.**
The vLLM pod holds the R9700 at its 0.98-util / Shape-B footprint
permanently — its KV + GDN-state pool, graph workspace, and AITER cache
are sized to be resident, not to time-share. Strata's arena must NOT be
re-pinned onto the R9700 while the vLLM pod is warm; the llama-swap/strata
roster is the fix surface if it is.

The sleep/wake time-sharing sequence is GONE: cf-105's D5/HR6
`/sleep`/`/wake_up` procedure and its `VLLM_SERVER_DEV_MODE` dev-route
pair are dropped from the recipe by the Q7 ruling, and the 2×-peak
VRAM-reclaim OOM caveat retired with them. The `--enable-sleep-mode` flag
EXISTS at 0.30 (R3 L2.5) and is the documented re-enable surface — the
owner's follow-up call if the one-engine discipline bites; not this
runbook's step.

The escape hatch (the memory-pressure valve, default OFF): the 0.30
`--kv-offloading-size` / `RADIANCE_KV_OFFLOADING_SIZE` seam (R3 L2.2 — the
0.9.3 `KVCACHE=ram` tier's successor). Enabling it moves pool pages into
host RAM and re-opens the 16Gi-shm headroom question — the 8Gi shm emptyDir
was kept (D19) on the stated condition that the offload tier stays off;
enabling the seam is an owner-visible decision with that condition
re-argued, not a runbook step.

Observation legs (read-only):

```
# on ai-gpu:
rocm-smi --showmeminfo vram    # one compute tenant on the R9700
free -h                        # the RAM-law read (EXPLORE §8.6)
```

## 9. Strata coexistence observation

The one-engine-per-card read, not a coexistence-success test: "Strata warm
on the R9700 while vLLM is up" is the VIOLATION to catch, not the target to
hold. The `free -h` RAM-law leg carries:

```
# on ai-gpu, before/after one public-chain request:
free -h
curl -sS https://llama.spencerslab.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b-vllm","max_tokens":8,"messages":[{"role":"user","content":"Reply: ok"}]}'
free -h
rocm-smi --showmeminfo vram
```

Expected: the request completes; no OOM-kill of either pod; the
`available` delta stays inside the vLLM pod's 32 Gi limit; and the R9700
shows the vLLM pod as its single heavy VRAM tenant while warm.
If it fails: a second heavy R9700 tenant (Strata's arena re-pinned while
vLLM is up) is the law broken — restore the roster discipline (the
llama-swap/strata side), owner-visible. Node-level RAM pressure means the
pods' budgets do not coexist — that is the EXPLORE §8.6 law biting, and it
is a sizing change (chart values), not a runbook fix.

## 10. PIN-ME follow-through

After the CI build lands (`docker-build.yaml` pushes `:v<run_number>`
(immutable) + `:main` (rolling) on the merge touching
`containers/vllm-radiance-mxfp4/**`):

1. In `charts/vllm/values.yaml`, pin the image `tag` to the first
   `:v<run_number>` (the immutable tag — never `:main` steady-state) and
   drop `pullPolicy` to the default (delete the `pullPolicy: Always` line).
2. Delete the PIN-ME comment.
3. Re-record the ledger: the `containers/vllm-radiance-mxfp4/README.md`
   tag→pin table — the single base pin is now the tag/digest/source-commit
   triple of the upstream `magiccodingman/vllm-radiance` row, plus our
   first `:v<run>` (the D12-amended dual surface: the README ledger + the
   chart image comment — both move in the same change).
4. Record which leg this landed as: a values-only commit on the ticket
   branch BEFORE the PR (if the `:v<run>` exists at review time) — or the
   owner's first post-merge follow-up commit.

**The manual-bump procedure** (for a future base move — three reads plus
one re-bench, every edit landing together):

- Read 1: the Hub tags API for the upstream tag (`curl
  https://hub.docker.com/v2/repositories/magiccodingman/vllm-radiance/tags/<tag>`
  — the `digest` field is the ledger value; the README carries the exact
  shape).
- Read 2: the registry manifest + config-blob probe (anonymous pull-scope
  token; sha256-of-manifest-bytes must equal the Hub digest; the config's
  `org.opencontainers.image.revision` label names the source commit).
- Read 3: the tag↔commit law read — the upstream `release`-branch tip
  paired with the `1.0.<n>` pipeline-IID cross-check (a `main`-only
  movement is NOT a publish).
- Then the on-target re-bench: the 3.1 marker set + the 3.5 re-measure gate
  + the 6.x anchors + the 3.7 tool smoke. The bump is not done until those
  pass on the R9700.

**The issue watch** (R3 L1.4): issues #6/#12 (the HSA idle-CPU spin — one
native thread pinning a core at idle) are OPEN; the mitigation
`HSA_TOOLS_DISABLE_REGISTER=1` is in the pod env (the R3-Q5 adoption —
reporter-verified on this stack lineage, no functional impact on serving,
metrics, or GPU monitoring). The drop condition: PR #19 merge (the
in-repo DOCS for the override) or PR #42 promotion (the experimental ROCr
idle-spin fix into the production default) landing in a new pin — until
then the reporter-verified mitigation IS our pin. The watch's caution
stands with it: "do not promote the experimental runtime to a production
default on this evidence" [98].

**The release-branch cadence**: the bump trigger is the next
`1.0.<n>`/`sha-…` pair on the upstream release line — NOT main's movement
(main carries test-only merges that never reach an image; R3 L1.1 /
conflict #4). Do not conflate the source `VERSION` string
(`1.1.0-rc1.vllm0.30.0`) with the published `1.0.<n>` tag series.

## The recorded alternatives (not a step)

The R3 L1.5 three-stack table, kept apart on purpose (the card's own
instruction). This section is documentation — none of it is wired in this
ticket.

- **(a) The stilldeadcode `vllm-radiance:0.9.3` base + the GGZ14 launcher
  recipe — the SUPERSEDED base** (the round-2 Q10 ruling's record). Its
  pin set (R2): Codeberg `df0af7cf6b…` + `stilldeadcode/vllm-radiance:0.9.3`
  @ digest `sha256:45694209…` + the libr4d `b9e42ab-rx9` build key + the
  `Dockerfile.ggz14.top` transcription overlay. Its measured record: the
  Shape-A/B 0.27.1-era pins, the 137.7/416 TP1 numbers (the step-6.1
  anchor class), the 6.09 GiB (Shape A) / 8.49 GiB (Shape B) KV rows —
  the reference row this runbook demotes to provenance. Restoring it would
  need the re-plan's full substance: the D11-as-replanned overlay, the D15
  recipe, the D17 9-var env, and the `fp8_mtp.py` rewrite staging. The
  line is deprecated + frozen upstream, and its start-time patch machinery
  does not run against the 0.30 image (R3 L1.3).
- **(b) The round-1 official-FP8 stock path — the owner-REJECTED
  alternative** (the re-scope ruling: "I've dropped the official
  checkpoint mandate"). Its evidence class (R1): the v0.33.0 stock image @
  `sha256:4fcd39b7…`, the `Qwen/Qwen3.8-27B-FP8` checkpoint, the 2×R9700
  25.8 tok/s c=1 anchor with issue #28649's open FP32-dequant-fallback
  caveat, and the 0.99/2seq/MTP-k=1 envelope — the rejected-plan record.
- **(c) The capicua25x `vllm-rocm-rdna4` degraded fallback** — the guide's
  one-flag-swap (R2 L1.4). It runs a DIFFERENT checkpoint:
  `Capicua25x/Qwen3.8-27B-MXFP4-Quark-RDNA4`, their own quantization pass
  (different excludes/naming) — stock `TRITON_ATTN`, no R4D, MTP-3, vLLM
  0.26.1-era. The degraded path IF the 0.30 image proves unrunnable on
  target; NOT wired, NOT pinned in this ticket.
- **(d) The stilldeadcode standalone `radiance` engine — OUT OF SCOPE**:
  not an OpenAI-shaped surface, so it cannot sit behind the llama-swap
  hop's contract (R2 L1.2/L1.5, R3 L1.1).

## If the owner wants a public host later (not a step)

The Q4 ruling kept vLLM cluster-internal (no `vllm.<domain>`); the
alternative, when the owner changes their mind, is two values edits — no
chart work:

1. One `ingress.subdomains.vllm` entry in `services/gpu-ai/prod/values.yaml`
   (`service: gpu-ai-vllm`, `port: 8000`). The gpu-ai generic-ingress
   already injects the `llama-timeouts` ServersTransport on every
   subdomain Ingress (`forwardingTimeouts.responseHeaderTimeout: 0`) — a
   public vLLM surface needs exactly that for deep-prefill 499s (EXPLORE
   §8.8).
2. The proxy-local `target: gpu-ai` leg in
   `services/proxy-local/prod/values.yaml` (the `llama:` entry is the
   shape precedent, with the Keycloak SSO redirect).

If browser UIs ever point at the public host directly, the v0.32+ CORS
`--allowed-origins` story (R3 OQ6) also enters.
