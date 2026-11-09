# PLAN: cf-131 — vLLM: drop GGUF, serve the MXFP4 Radiance fork on the R9700 (0.30 base — owner rounds 1+2+3)
feature: 2026/2026-11-cf-131-feat-vllm-fp8-official

> **Re-plan record (round 1).** The original FP8-official plan (D1–D10 +
> rework R1–R7, DECISIONS.md) was REJECTED by the owner at the approval
> round: *"you need to include the MXFP4 fork in the R9700 image. I've
> dropped the official checkpoint mandate."* (record: STATE.json
> `plan.approval` + DECISIONS.md "Re-scope ruling"). The re-plan on R2
> (the 0.9.3/GGZ14 ground, D11–D22) is the round-1 re-plan record.
>
> **Final rework record (round 2, this pass).** The owner's batched
> round-2 rulings over the re-plan's Q1–Q10 (STATE.json
> `plan.owner_batched_round_2` + DECISIONS.md "Owner rulings — batched
> round 2", both kept as-is) overrode six assumptions: Q10 MIGRATED THE
> BASE to `magiccodingman/vllm-radiance:1.0.397` (vLLM 0.30.0) — which
> voids the R2 0.9.3/GGZ14 build story (the launcher does not work against
> the 0.30 image; the `.top` transcription + the rx9 deviation stop
> applying; the overlay COLLAPSES to a thin digest-pinned re-export); Q2
> SHAPE B (220000/2560/3) with the re-measure gate as the SOLE envelope
> path (no 0.30 TP1 measurement exists at any shape); Q3 the catalog
> `limit.context` STAYS 262144 (the D9 breach does not happen — the
> 220000–262144 band is owner-ruled and runbook-documented); Q5 the int4
> KV leg gains its ON-TARGET QUALIFICATION GATE in this ticket; Q6 the
> three rows gain the `tools` capability marker (grounded on the 0.30
> stack's own 30/30 record with its caveats); Q8 RAW-RELEASE staging (the
> `fp8_mtp.py` rewrite stays dropped). The round-3 research (RESEARCH.md
> **R3**, L2183+ — the 0.30 base grounding) is this pass's authority; R2
> is the superseded-base record; R1 stays supporting context. The D11–D22
> disposition pass + the new decisions D23–D30 are in DECISIONS.md
> ("Final rework — the 0.30 base round"). One folder, one plan file: this
> file reworked in place, no second plan file.
>
> **Final pass record (round 3 answers, this pass).** The owner's
> batched round-3 rulings (STATE.json top-level `owner_batched_round_3`
> + DECISIONS.md "Owner rulings — batched round 3", 2026-11-08, kept
> as-is) confirmed all six R3 questions as this rework's best guesses
> (no chunk change — verified on the record) and overrode **Q11:
> ENGINE CAP 262144** — the round-2 "Keep 262144" ruling consumed as
> the engine `--max-model-len` shipping at 262144. The 220000–262144
> band law (the final rework's D28) is SUPERSEDED (D31): the context
> axis is now TRUE on both sides (catalog 262144 == engine 262144), and
> R2 L3.5's "262144 does not fit at TP=1" record (0.9.3-stack; no
> 0.30 TP1 measurement exists at any shape) becomes the LIVE owner-
> ruled risk with its named backstops (the 40-min startup probe — a
> loud, gated refusal; the day-one re-measure gate re-bound to the
> shipped 262144/2560/3 shape, the 8.49 GiB pin demoted to the recorded
> 220000-class reference row; the runbook's documented startup
> contingency). The only legs that move are the max-model-len leg (C02
> serveArgs + the dflash JSON, re-bound to the drafter's native
> 262144) + the band→true-axis documentation (C04's comment wording,
> C05's runbook/suite). The 20-var env, the util 0.90 start, the probe,
> and every other constant are untouched by this pass.

## Goal

Serve the R9700 through the maintained MXFP4 Radiance stack: the
`magiccodingman/vllm-radiance:1.0.397` image (vLLM 0.30.0 @ `ced6857a`,
libr4d 0.5.0 + 35 release overlays + the tuned R9700 FP8 GEMM configs
baked — a self-contained terminal build), re-exported under the repo's CI
law as the thin overlay `ghcr.io/ownyourio/vllm-radiance-mxfp4` (C01),
serving the AMD `Qwen3.8-27B-Quark-AWQ-MXFP4` checkpoint RAW (the 2026-
11-03 mtp-exclude-fix revision — the rewrite step is dropped per the
round-2 Q8 ruling) + the revision-pinned DFlash2-FP8 drafter, in the
owner-ruled TP=1 envelope (262144 ctx — the round-3 Q11 engine-cap
ruling, the model's native ceiling; 3 seqs / 2560 chunk — the round-2
Shape B ruling's seqs/chunk constants; util 0.90 start — round-3
confirmed) with the dflash K7 spec lane (the draft context matched to
the same 262144 native ceiling), the KV-dtype values key (fp8 default;
int4 experimental with its day-one on-target qualification gate), and
the served name + four-class priority wiring byte-stable — the catalog
`limit.context` 262144 is the TRUE axis: the engine ships the same
262144 cap, so the round-2 Q3 keep + the round-3 Q11 engine-cap ruling
make the advertisement accurate (the final rework's band law, D28, is
superseded — D31; its LIVE risk + backstops ride the plan Risks and
C05's runbook record).
The llama.cpp roster (incl. the class-10 GGUF rung) is untouched; the old
GGUF overlay retires.

## Ground

- **RESEARCH.md R3 (L2183+, round-3 commission, the authority for this
  pass)** — the 0.30 pin (L1: `magiccodingman/vllm-radiance:1.0.397`
  (= `latest` = `1.0` = `sha-5b99d66c844f`) @ `sha256:b73bf3e4…7313e0`,
  source commit `5b99d66c`, four-source corroboration + the tag↔commit
  release-branch law), the image contents (L1.2: the stack, the 35
  overlays, the baked kernels/configs, the no-prebake AITER JIT boot
  cost), the pairing answer (L1.3: the GGZ14 launcher does NOT work
  against the 0.30 image — the qualified combo is image + magiccodingman's
  own compose/env recipe; the pod args start with the model path), issue
  #6/#12 + the HSA workaround (L1.4), the three-stack separation table
  (L1.5), the 0.30 engine re-grounding (L2: the dtype qualification + the
  int4 gate ground, the native dflash/mtp spec story + the drafter
  revision pin `ee0cb26a`, the Shape-B carry + the re-measure binding,
  the Q7 flag spot-check DONE at 0.30, the raw-release checkpoint ground +
  the `RADIANCE_QUARK_BF16_MTP` mtp-toggle coupling), the 0.30 bake + the
  30/30 tool record + the performance anchor classes (L3), the
  contradictions map, the D-delta implications, and open questions
  R3-Q1–R3-Q6.
- **RESEARCH.md R2 (L711+, round 2)** — the SUPERSEDED-BASE record: the
  0.9.3/GGZ14 pin set + the L2.4 transcription + the L3.4/L3.5 0.9.3
  measurements (the 137.7/416 anchor class the runbook pre-registers) +
  the L4.5/L4.6 0.27.1 surface (the re-grounding's diff base).
- **EXPLORE.md** (2026-11-07) — the live pod/args/env/PVC facts (the
  GID-486 proven shape, the chip map R9700=0 / 8060S=1, the storage map,
  the priority-wiring pin set §4, the test-suite re-pin surfaces §2).
- **cf-105 backlinks** — the D1–D10 + followup D1–D7 decisions, the GID-
  486 root-cause chain (the pod-shape law), the runbook + its contract
  suite (the re-pin targets).
- **The owner's rounds** — round 1 (DECISIONS "Owner rulings — batched
  plan-question round": the OQ9 catalog-capability + the OQ12 ViT-var
  rulings carry where R3's ground allows, D25/D28) and round 2 (DECISIONS
  "Owner rulings — batched round 2": Q1–Q10, the six overrides driving
  this pass).

## Out of scope

- **The stilldeadcode 0.9.3 base + the GGZ14 launcher recipe** — the
  SUPERSEDED base (the round-2 Q10 ruling). Its pin set (Codeberg
  `df0af7cf6b` + the 0.9.3 @ `45694209…` digest + the `b9e42ab-rx9`
  libr4d key + the `.top` transcription overlay + the rx9 deviation)
  survives as the runbook's recorded-alternative (a) — the 137.7/416 TP1
  numbers are its measured record (the runbook's anchor class). The
  launcher's value (its start-time patch machinery) keys on 0.9.3/0.27.1
  and does not apply to the 0.30 image (R3 L1.3).
- **The round-1 official FP8 stock path** — the owner-rejected alternative
  (the re-scope ruling: "I've dropped the official checkpoint mandate"):
  the R1 evidence class (the v0.33.0 stock image, `Qwen/Qwen3.8-27B-FP8`,
  the 2×R9700 25.8 tok/s c=1 anchor, issue #28649's open caveat, the
  0.99/2seq/MTP envelope) recorded in the runbook's recorded-alternatives
  as the rejected path.
- **Building from the magiccodingman GitHub `main` movement** — the
  publishes are release-branch-only (`$CI_COMMIT_BRANCH == "release"`);
  the watch trigger is the next `1.0.<n>`/`sha-…` pair, NOT main's test-
  only merges (R3 L1.1, conflict #4). No renovate datasource covers this
  line — the manual ledger law (D12-amended).
- **The capicua25x `vllm-rocm-rdna4` fallback** (R3 L1.5: the guide's
  one-flag-swap degraded fallback — a DIFFERENT checkpoint, their own
  quantization pass, stock TRITON_ATTN, no R4D, MTP-3). Recorded in the
  runbook as the degraded fallback only; not wired, not tested, not
  pinned.
- **The stilldeadcode standalone `radiance` engine** — out of scope
  (not an OpenAI-shaped surface — the llama-swap hop's contract, R2
  L1.2/L1.5; the deprecation's own target).
- **The MTP rewrite re-land** — the round-2 Q8 ruling drops the
  `fp8_mtp.py` step from the shipped staging; the rewrite survives ONLY as
  the recorded two-generation-removed fallback (the runbook step-2.3
  contingency ladder: verify `RADIANCE_QUARK_BF16_MTP=1` first, then the
  re-land — the owner's call, D26).
- **TP>1** — the 0.30 stack's qualified configurations are all TP2 ("two
  GPUs is the only configuration tested so far" [91]); our node's arch-
  mixed pair (R9700 gfx1201 + 8060S gfx1151) cannot run a TP2 of the
  same card, and auto-detect would pick the broken mixed pair (the R2
  L4.3 pitfall carries). The recipe pins `--tensor-parallel-size 1`; the
  TP2→TP1 transfer is the recorded caveat class (the tool record, the
  performance anchors, the verify-head "experimental at TP1" note — R3
  L2.3/L3.2/L3.3).
- **1M context on the vLLM rung** — the engine cap is 262144 (the
  round-3 Q11 engine-cap ruling — the model's native ceiling; the
  round-2 Shape B ruling's 220000 leg is superseded on that axis, D31);
  the catalog advertises the same 262144 (the true axis); true
  long-context beyond the 262144 native ceiling stays on the llama.cpp
  `qwen3.8-27b-q8-1m` rung (the R1 OQ-E ruling carries).
- **The KV offload tiers** (`--kv-offloading-size` / the `RADIANCE_
  KV_OFFLOADING_SIZE` seam, default off, R3 L2.2) + `RADIANCE_EMBED_HOST`
  (off, the host-pinned-embed escape hatch) + the lazy-GDN feature
  (deliberately NOT ported into the 0.30 stack [89] — the multi-turn
  corruption law is satisfied structurally; the re-plan's
  `RADIANCE_GDN_LAZY=0` env var has no 0.30 counterpart and drops, D25)
  + the RX4/RX5 experimental tiers (the entrypoint hard-gates their
  combinations; the publication used them off [108]).
- **The KVCACHE-tier 16Gi-shm headroom** — the guide's docker-compose-
  class shm sizing is not adopted (the 8Gi proven shm carries, D19 kept).
- Any `kubectl apply`/cluster mutation (ArgoCD-only law), the guide's
  docker-run/kustomize-specific instructions (requirement 5: translated
  onto the repo's charts/vllm + containers/ CI + llama-swap peers hop
  surfaces — at 0.30 the translation target is magiccodingman's OWN
  compose/env recipe, not the GGZ14 launcher's).

## Commands

Recorded for the test/dev/review agents (no docker daemon in agent
sessions — image facts are CI/registry-primary per the cf-77 ruling:
`docker build => no-daemon, CI-deferred` is the designed passing gate
shape; on-target verification is operator-run per the runbook).

```
export PATH=$HOME/.local/bin:$PATH        # helm v3.16.4 (without it the
                                          # helm-guarded tests mass-skip silently)

# C02/C03 — the chart switch (the primary surface)
helm lint charts/vllm
helm template vllm charts/vllm --set domain=spencerslab.com --set clusterName=gpu-ai   # chart defaults
python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml')); yaml.safe_dump(d['vllm'], open('/tmp/vllm-vals.yaml','w'))"
helm template vllm charts/vllm -f /tmp/vllm-vals.yaml --set domain=spencerslab.com --set clusterName=gpu-ai   # service-level
python3 -m pytest charts/vllm/tests -v     # per-directory pytest law (test basenames duplicate)

# C04 — the catalog/surface (the marker + the M3 re-pin; the context assert stays 262144)
bash tests/pipeline-models/surface.sh      # M1..M7 — M3 re-pinned (capability+tools asserts added; the context leg unmodified), other arms byte-untouched

# No-move confirmations (C05 review; green without edits is the bar)
python3 -m pytest charts/llama-swap/tests -v   # peers.vllm exact + golden byte-parity (no llama-swap values edit)
git diff -- .opencode/opencode.jsonc tests/pipeline-models/surface.sh   # the C04 sanctioned delta only (the capability key per row)
git diff -- charts/llama-swap services/gpu/prod/values.yaml custom-values/gpu-ai   # empty (vllm-free / untouched law)

# C05 — the runbook contract
bash tests/notes/vllm-runbook.sh           # T1..T5 (re-pinned by C05)

# Quality gate
npx aislop ci --changes
```

`OVERRIDE_VIA_CUSTOM_VALUES` 1:1 law: this ticket adds no secrets and no
chart bitwardenIds — `charts/vllm` carries zero placeholders by design
(pinned vllm-free on `custom-values/gpu-ai` by test_trio; no
custom-values edit anywhere in the ticket). Both checkpoints are
public/ungated — no HF_TOKEN (the `hf-token` secret stays orca's alone,
the cf-86 ruling).

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | The thin fork overlay: `containers/vllm-radiance-mxfp4` (the 0.30 digest-pinned re-export + the ledger README) + the `vllm-rocm` retirement + CI paths | M | 1 | [] | |
| C02 | The engine switch: 0.30 image pin @ first-build shape, the Shape-B serve recipe (compose-baseline ground + the Q7 carries), the 20-var env law, the probe carry, the values keys, the service twin, the test re-pins | L | 2 | [C01] | Same `values.yaml` + same testlib — the recipe/env/test re-pins build on the C01 state; the image pin flip names the dir C01 created |
| C03 | The staging + storage switch: the `setup` init container (the raw-release + drafter-revision staging, Q8), the persistence restructure (advancedMounts models ro/rw, `/data` → `/cache`), the test re-pins | M | 3 | [C02] | Same values.yaml + the test_render persistence legs build on C02's serve-plane state; the init container's image is C02's pin |
| C04 | The catalog + surface: the `capabilities` marker (input/output + `tools: true`, the round-2 Q6 override) + the `surface.sh` M3 re-pin; the `limit.context` 262144 stays (the Q3 keep-ruling voids the re-plan's breach) | M | 3 | [C02] | The marker's grounding keys on C02's shipped 0.30 recipe (the tool trio); zero file overlap with C03 (parallel wave) |
| C05 | The runbook + `vllm-runbook.sh` re-pin for the 0.30 Shape-B shape (the day-one re-measure gate, the true-axis note + the LIVE 262144 risk, the int4 gate, the tool smoke, the recorded alternatives) + the no-move confirmation (the final-chunk bar) | M | 4 | [C03, C04] | The runbook documents the fully-shipped shape (recipe C02 + staging C03 + catalog C04); its T3 cross-check reads the final chart values; docs+pins land together (parity law) |

## Wave order

1. C01 — the thin overlay + the retirement. Green on its own: the chart
   still points at the old image (which still exists in the registry),
   `test_ac6` untouched, `test_ac7` re-pins with the workflow path swap.
2. C02 — the serve plane (image + recipe + env + probe + keys + tests).
   Green on its own once C01's dir + the testlib stand (the persistence
   restructure waits for C03 — C02 renders on the re-plan's mount shape).
3. C03 and C04 (independent; run in id order) — the data plane (staging +
   storage) and the picker surface (the capability marker + the M3 re-
   pin).
4. C05 — the operator doc + its suite + the no-move confirmation as the
   final-chunk bar (the card law: the priority wiring / pod shape /
   roster invariants + the `limit.context` keep verified at the end).

HIL stops per the card's Human-in-the-Loop checklist: Planning (this
plan, the batched round-3 question call, approval) and Chunk Review (each
chunk's review is a stop point — the coordinator presents per chunk).

## Risks / assumptions

- **Every 0.30 datum on record is TP2 — our pod is TP1.** The 0.30 stack's
  qualified configurations are all two-R9700 TP2 (R3 L2.4: "no 0.30-stack
  measurement exists at ANY TP1 shape"; [91]: "two GPUs is the only
  configuration tested so far"). The plan ships the owner-ruled Shape-B
  constants as the PLAN shape, and the **day-one re-measure gate** (the
  runbook's sole envelope path) + the DRY_RUN-analog capture + the
  benchmark steps close the gap on target. No 0.30 TP1 number is assumed
  anywhere — the 0.9.3 TP1 record (137.7/416, the same card signature)
  is pre-registered as the ANCHOR CLASS only (R3 L3.3's weakest-claim
  law).
- **The 262144 ceiling at TP=1 is a LIVE owner-ruled risk (the round-3
  Q11 ruling's consequence, D31).** R2 L3.5 recorded "262144 does not
  fit at TP=1" on the 0.9.3 stack, and no 0.30 TP1 measurement exists
  at any shape (R3 L2.4) — at the shipped 262144/2560/3 shape the KV
  pool at the 0.90 util start may be small or the engine may compute a
  degenerate pool. The backstops, all named in the plan: the 40-min
  startup probe (a refusal is a loud, GATED failure — the pod fails at
  startup, it does not silently mis-serve) + the day-one re-measure gate
  (the pool's truth; the values-only `--kv-cache-memory-bytes` re-tune
  is the post-calibration lever) + the runbook's documented startup
  contingency (the OQ13 dual-edit class: if the engine hard-rejects, the
  operator lowers `--max-model-len` on target per the runbook recipe —
  the byte-stable catalog is protected because it was already 262144, so
  the contingency moves only the ENGINE arg; the catalog re-pin question
  resurfaces only if the owner wants the advertisement to follow the
  engine down).

- **The raw-release load is a stated assumption, not a verified one**
  (R3 reliability notes (b)): the 0.30 stack was qualified on the PRE-
  fix checkpoint revision `156be69f` (whose bf16 MTP head needed the
  baked `patch_quark_bf16_mtp` load path); our pin `93245f7c` is post
  the 2026-11-03 module-name fix and "strictly more loadable" (R3
  conflict #3 — risk direction: DOWN on load, unchanged on numerics for
  the shipped lanes) — but no public run exists on the post-fix revision
  with this stack. The closing gates: the runbook step-3 first-serve (the
  dflash lane's load) + the Q8 contingency ladder (step 2.3: the
  `RADIANCE_QUARK_BF16_MTP` first step, the rewrite re-land fallback —
  the mtp toggle's load path is the owner-gated one).
- **The re-measure gate may re-pin the shipped constants** (the 0.90 util
  start, the shipped 262144/2560/3 shape, an eventual
  `--kv-cache-memory-bytes` pin): the chart ships NO pool pin by law
  (D24); the 8.49 GiB carried number is the 220000-class 0.9.3-stack
  user-reported artifact (the recorded reference row) with no 0.30
  validity — the gate DERIVES the pool at the shipped 262144 shape. The
  gate's PASS = confirm; its FAIL = the marked values re-pin (C02's
  serveArgs lines + the testlib pairs + the runbook block — one line
  per chunk, D30's marked surface).
- **The int4 gate is a day-one measurement, not a shipped change** (the
  round-2 Q5 ruling): the shipped recipe is fp8; the gate's two 0.30
  edits (the dtype value + the TRITON_ATTN swap) + the gate legs run on
  target, and int4 promotes to documented-tested ONLY on a pass (D27).
  The gate's quality/tool legs are reference-class records, not claims
  (the 30/30 record is fp8-KV-only).
- **The tools marker's standing risk** (the round-2 Q6 override + R3
  L3.2's confidence statement): the 30/30 record is the 0.30 stack's own
  and covers the shipped dflash K7 default + the non-spec fallback — but
  is TP2-only (no TP1 tool datum exists), the mtp toggle carries the
  29/30 tool-gate-FAIL class, and the record is a synthetic wire gate.
  The on-target tool smoke (the keypress-fixture class, the runbook's
  closing gate) is what the marker ultimately stands on — the risk
  statement rides the approval presentation (the owner's ruling's own
  condition).
- **`--scheduling-policy priority` is UNMEASURED under the 0.30 stack**
  (the flag is 0.30-verified [R3 L2.5] but absent from the publication's
  measured lanes — the scheduler-knob-class risk, the R2 framing carries):
  the runbook step-5 priority proof is the on-target gate; if the R4D
  path rejects the knob, the re-pin is the flag drop + the owner's
  ruling on the wiring's engine half (marked, not improvised).
- **The HSA workaround var's persistence at 1.0.397 is medium-confidence**
  (R3 reliability notes (c): the reporter's evidence is on the 1.0.15-
  era digest, same bundled ROCr runtime pin; PR #19/#42 confirm the
  issue pair on the current stack but neither is merged). The var ships
  (R3-Q5, round-3 confirmed) with the runbook's on-target confirmation leg (the
  pod CPU-idle probe) + the #6/#12/#42 watch (the drop condition).
- **The entrypoint's combination gates are the env law's risk control**
  (D25: exit 64 on the retired/experimental var mixes [94 L10-64] — the
  first-boot banner + exit behavior are the runbook's step-1/3 legs; a
  gate trip means a var combination drift, localized to the 20-var set).
- **First-deploy pod start is ~40–60 min** (the init staging (~20.4 GiB
  `local_dir` downloads) + the cold-cache 0.30 boot incl. the first-use
  AITER JIT — NO pre-bake at 0.30, R3 L1.2 — inside the 40-min probe
  budget class); re-boots are ~7–10 min (the marker skip + the warm
  boot). The one-cache-per-config law + the entrypoint's `-fast-draft`
  cache suffix make the config isolation structural (R3 L3.1).
- **Assumed**: Docker Hub reachability from the cluster (the re-export's
  upstream pull at node boot — the ghcr re-export is the cluster's pull
  target, the upstream digest is build-time); the 500Gi claim headroom
  (~20.4 GiB steady + the llama.cpp caches — non-binding, R2 L4.4); the
  node keeps serving the llama.cpp roster unchanged (the 32Gi pod limit
  + the 125Gi node RAM law untouched — D19 kept).

## Open questions — round-3 outcomes (all answered; nothing left open)

Batched round 3 (STATE.json top-level `owner_batched_round_3`, 2026-11-
08, + DECISIONS.md "Owner rulings — batched round 3", both kept as-is)
answered the entire round-3 set:

- **R3-Q1 (thin overlay) / R3-Q2 (util 0.90) / R3-Q3 (matched draft
  context) / R3-Q4 (K4 doc depth) / R3-Q5 (HSA var adopted) / R3-Q6
  (BF16-MTP coupled to the mtp toggle)** — all CONFIRMED as the final
  rework's best guesses: no chunk change needed (verified on the record
  — each was planned against exactly the confirmed best guess).
- **Q11 (the engine cap) — OVERRIDDEN: 262144.** The round-2 "Keep
  262144" ruling is consumed as the engine `--max-model-len` shipping
  at 262144. The 220000–262144 band (the final rework's D28 band law)
  is VOID (superseded — D31); the context axis is now true on both
  sides. The Q11 chain re-binds the R3-Q3 "matched" ruling to the
  drafter's native 262144 — the match becomes exact in the most precise
  sense (draft and target share the native ceiling). Only the
  max-model-len leg moves: C02's serveArgs `--max-model-len` + the
  dflash JSON's `max_model_len`; C05's day-one re-measure gate re-binds
  its physics to the shipped 262144/2560/3 shape (the 8.49 GiB pin
  becomes the recorded 220000-class REFERENCE row — the gate DERIVES
  the pool, still the sole envelope path); C05's band documentation is
  replaced by the (now-trivial) true-axis note + the LIVE risk + the
  runbook's documented startup contingency.

**Left open after the final pass: nothing.** The approval presentation
carries two RISK STATEMENTS, not questions: (a) the LIVE 262144 risk —
R2 L3.5's "does not fit at TP=1" record is now owner-ruled, with no
0.30 TP1 measurement at any shape, and the pool outcome at the 0.90
start is an on-target unknown until the day-one re-measure gate (the
backstops: the 40-min probe as a loud gated refusal, the re-measure
gate, the documented startup contingency); (b) the tools marker's
standing risk (R3 L3.2: the 30/30 record is TP2-only, the mtp toggle
carries the 29/30 tool-gate-FAIL class, the record is a synthetic wire
gate — the on-target tool smoke is the closing gate).

## Decisions (full text in DECISIONS.md, "Final rework — the 0.30 base
round" section: the D11–D22 disposition pass + D23–D30, and the
"Final pass — the Q11 engine-cap ruling" section: D28's disposition +
D31)

D23 the 0.30 pin set + the thin-overlay collapse (Q10 ruling; R3-Q1
best-guess on the record: the thin re-export over
`magiccodingman/vllm-radiance:1.0.397` @ the digest, source commit
`5b99d66c`, the tag↔commit release-branch watch; the `vllm-rocm`
retirement carries) · D24 the serve recipe (the 0.30 Shape-B constants on
the compose-baseline ground: args start with the model path; the tool
trio + the 0.30 sampling surface; the Q7 carries `--scheduling-policy
priority` / `--watermark 0.05` / `--limit-mm-per-prompt image=4` — all
0.30-verified; the Q7 drops stand; NO `--kv-cache-memory-bytes` pin —
the re-measure gate owns the pool; the `kvCacheDtype`/`specMethod`/
`specConfig` keys on the 0.30 ground) · D25 the 20-var env law (the
device pins, `HF_HUB_OFFLINE`, the OQ12 ViT var carry, the four `/cache/*`
re-declarations, the `RADIANCE_WEIGHT_QUANTIZATION=auto` seam, the MXFP4
W4A8 qualified set, the dflash prerequisites V2/FAST_DRAFT/PIECEWISE, the
HSA workaround var; the `RADIANCE_GDN_LAZY` drop — the feature is absent
from the 0.30 stack; the entrypoint combination gates as the risk
control) · D26 the staging re-grounding (the Q8 raw release @
`93245f7c` + the drafter revision pin `ee0cb26a` + the both-shas marker +
the Q8 contingency ladder) · D27 the int4 qualification gate (the round-2
Q5 ruling, 0.30-grounded: `int4_per_token_head` ships
documented-experimental + non-default, with the ON-TARGET acceptance gate
in this ticket (the D29 day-one runbook step) — the two 0.30 edits + the
gate legs + the promote/stay-experimental outcome (gate PASS → promoted
to the documented-tested toggle value, values-only re-pin; gate FAIL →
stays experimental-OFF, the status quo — the 48GB-RDNA3 note's home
stands); the fp8 default + the `bf16`/`auto` tested toggles untouched by
the gate) · D28 the catalog surface + the
band law — SUPERSEDED by D31 (the band half died with the round-3 Q11
engine-cap ruling; the Q3 `limit.context` keep + the Q6 `tools: true`
marker + the OQ9/R4 input/output marker stand) · D29
day-one re-measure gate as the SOLE envelope path; the 0.30 marker set +
the DRY_RUN-analog capture; the int4 gate; the tool smoke; the 0.9.3-TP1
anchor class + the 0.30-TP2 sanity class; the HSA watch; the one-
engine-per-card step 8/9; the recorded alternatives on R3 L1.5's table;
the T3 12-flag dict + the kv-pin ABSENCE leg + the T5 needle set) · D30
the chunking (the five-chunk seam stays the shape per the round-3
instruction; the content re-grounds per D23–D29) · D31 the engine-cap
262144 law + the LIVE risk (the round-3 Q11 ruling: the round-2 "Keep
262144" ruling consumed as the engine `--max-model-len` 262144 — the
220000–262144 band is void, the context axis is true on both sides; the
Q11 chain re-binds the R3-Q3 matched draft context to the drafter's
native 262144; only the max-model-len leg moves — C02 serveArgs + the
dflash JSON + C05's day-one re-measure gate physics (the gate derives
the pool at 262144/2560/3; the 8.49 GiB pin = the recorded 220000-class
reference row) + the band→true-axis documentation; the LIVE risk = R2
L3.5's "does not fit at TP=1" record, now owner-ruled, with the three
named backstops: the 40-min probe, the re-measure gate, and the
runbook's startup contingency (the OQ13 dual-edit class — the
contingency moves only the engine arg; the catalog re-pin question
resurfaces only if the owner wants the advertisement to follow the
engine down)).
