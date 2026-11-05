# PLAN: vLLM for qwen3.8-27b on the R9700 + llama-swap FE + card Priority → vLLM scheduling + monitoring

feature: 2026/2026-11-cf-105-feat-implement-vllm

## Goal

Add vLLM (upstream ROCm image v0.33.0, via a thin `containers/vllm-rocm` overlay that
adds the GGUF plugin) serving the dense `qwen3.8-27b` on the R9700 of the gpu-ai
cluster, reached exclusively through the existing llama-swap surface via a `peers.vllm`
hop (no new ingress). Wire the board's `Priority` custom field end-to-end into vLLM
request-level priority (card → class → OpenCode model-row `body` carrier → vLLM
`--scheduling-policy priority`), using agent-context skill changes only. Close the
monitoring thread with the least-new-surface scrape (`k8s.grafana.com/*` pod
annotations: scrape + metrics port; 60 s interval = the v4 autodiscovery feature
default, no `metrics.scrapeInterval` annotation — Q5), the official vLLM Grafana
dashboards pinned to tag v0.33.0, and the one access-log suppression flag — logs
already reach Loki via `podLogsViaLoki`.

## Research verdicts this plan builds on (RESEARCH.md — cited, not re-litigated)

- **R1** — conditional GO on the R9700 (gfx1201); MARGINAL on the 8060S. The stated
  "3–4 sessions at 256k" is **physically impossible on any single 32 GiB card**
  (GDN-hybrid KV math, R1 §3: 4×256k = 31.2 GiB of KV alone). R1's own re-scoped
  envelope (3–4×≈100k) is superseded by the owner's Q3 ruling — see D4.
- **R2** — the "50+ tok/s for the flash model, else keep Strata" condition **FAILS**
  (OCuLink x4 ≈ 7.2 GB/s, PLE-offload CUDA-only, RAM coexistence law). **Strata keeps
  the flash model; vLLM takes the dense 27B.** 8060S-vLLM-flash = watch-item card, not
  a chunk.
- **R3** — vLLM ships no UI → **reuse llama-swap as the FE** (`peers.vllm`), zero new
  chart/ingress/proxy surface for the UI itself. Open WebUI = optional, separable,
  owner-decided (Q1).
- **R4** — vLLM has real request-level `priority` (needs `--scheduling-policy
  priority`; lower = earlier; forced recompute preemption on KV exhaustion). llama-swap
  passes body fields through by default; the agent-side carrier is the OpenCode
  v2.1.4 model-row `body` config (verified in the installed binary). **Recommended
  option E** (card `Priority` → class → model row + body priority); the boards-skill
  roster line and the D12 ruling are the text that changes (`.rulesync/` sources +
  `rulesync generate`, never hand-edited generated surfaces).
- **R5** — least-new-surface scrape = two pod annotations under the already-enabled v4
  `annotationAutodiscovery` (`k8s.grafana.com/scrape` + `metrics.portNumber: "8000"`)
  — **not** `prometheus.io/*` (R5 corrects EXPLORE §3); official dashboards import via
  the repo's `grafana.dashboards` `url:` convention pinned to tag v0.33.0; logs already
  reach Loki; GPU-side (ROCm) exporter is out of scope → follow-up card.

## Out of scope

- vLLM serving of the flash model (R2 verdict — Strata keeps it); 8060S vLLM variant
  (follow-up card pending GTT/RAM verification, R1 OQ1).
- Public `vllm.<domain>` host + proxy-local/SSO leg (best guess Q4: internal-only).
- Open WebUI chat app (best guess Q1: no; follow-up card if the owner wants it).
- llama-swap `selectors` unified 27B ID (strategy needs the R9700/Strata time-sharing
  ruling — follow-up card).
- PrometheusRule alert convention + the R5 Q4 alert set (thresholds need the C06
  benchmark — follow-up card).
- ROCm Device Metrics Exporter (R5 GPU-side gap — follow-up card).
- Any change to the existing llama.cpp/Strata rosters, matrix, or the Strata peer
  block (C03 touches only an additive `peers.vllm` block + one golden re-capture).
- Node re-architecture, kubectl, pod exec — on-target acceptance is operator-run per
  the C06 runbook (EXPLORE §7: no exec tier).

## Commands

`export PATH=$HOME/.local/bin:$PATH` first (helm v3.16.4; without it the helm-guarded
pytest mass-skips silently). No unit-test suite exists for engine behavior — these are
the repo validations (EXPLORE §4); the on-target run in C06 is the engine's test.

```
# C01 (image)
docker build containers/vllm-rocm                # => no-daemon, CI-deferred (designed gate shape)
curl -s https://hub.docker.com/v2/repositories/vllm/vllm-openai-rocm/tags/v0.33.0-rocm100   # digest re-verify for the ledger (record output)
curl -s https://api.github.com/repos/vllm-project/vllm-gguf-plugin/commits/e454affe0ca23c9dc8754ec3033270cb30622ed5   # plugin ref re-verify for the ledger (record output)

# C02 (chart + trio)
helm dependency update charts/vllm               # writes Chart.lock + vendored charts/common-5.0.1.tgz
helm lint charts/vllm
helm template vllm charts/vllm --set domain=spencerslab.com --set clusterName=gpu-ai
python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml'))['vllm']; yaml.safe_dump(d, open('/tmp/vllm-vals.yaml','w'))"
helm template vllm charts/vllm -f /tmp/vllm-vals.yaml --set domain=spencerslab.com --set clusterName=gpu-ai
grep -rn "OVERRIDE_" <each rendered output>      # must be empty

# C03 (peers + catalog)
python3 -c "import yaml; d=yaml.safe_load(open('services/gpu-ai/prod/values.yaml'))['llama-swap']; yaml.safe_dump(d, open('/tmp/gpu-ai-vals.yaml','w'))"
helm template llama-swap charts/llama-swap -f /tmp/gpu-ai-vals.yaml --set domain=spencerslab.com --set clusterName=gpu-ai --set bitwardenIds.hf-token=test-uuid --show-only templates/configmap-llama-swap.yaml

# trio greps (all chunks)
grep -n "vllm" services/gpu-ai/prod/values.yaml          # charts: entry + vllm: block + peers.vllm
grep -rn "vllm" services/proxy-local/prod/values.yaml    # must be EMPTY (no public host — Q4)
grep -rn "vllm" custom-values/                           # must be EMPTY (no secrets)
grep -rn "vllm" services/gpu/prod/values.yaml            # must be EMPTY (8 GiB box untouched)

# pytest (per-directory — basenames duplicate across suites)
python3 -m pytest charts/vllm/tests -v
python3 -m pytest charts/llama-swap/tests -v

# C04 (agent context)
rulesync generate                # after the .rulesync/ source edits
rulesync generate --check        # committed generated surfaces are current

# C05 (dashboards)
python3 -c "import yaml; d=yaml.safe_load(open('services/monitoring/prod/values.yaml')); print(sorted(d['grafana']['dashboards']['default'].keys()))"  # both vLLM entries present

# C06 (runbook)
test -f .agents/notes/vllm-on-target-acceptance.md

# surface suites (bash, per tests/ convention — run by dev/review locally; NOT in CI):
bash tests/pipeline-models/surface.sh            # M1..M7 — C03's dev/review runs the M1..M6 subset
                                                 # (M7 is C04's designed-red module, cf-83 posture); C04 and the
                                                 # final review run the full set
bash tests/containers/vllm-rocm.sh               # C01 image contract
bash tests/services/vllm-dashboards.sh           # C05 dashboard pins
bash tests/notes/vllm-runbook.sh                 # C06 runbook contract

# quality gate (AGENTS.md "Comments and code quality"): the repo aislop gate is clean
# for every file this ticket touches — CI runs `aislop ci --changes` on the PR (config:
# .aislop/config.yml); locally: npx aislop (see the vendored aislop skill) on the diff
```

## Chunks

| id  | title | size | wave | depends_on | why the dependency |
|-----|-------|------|------|------------|--------------------|
| C01 | `containers/vllm-rocm` overlay image (v0.33.0-rocm100 base + `vllm-gguf-plugin`) | M | 1 | [] | — |
| C02 | `charts/vllm` chart + gpu-ai ApplicationSet trio (internal-only, proxy leg skipped by ruling) | L | 1 | [] | — |
| C03 | llama-swap `peers.vllm` + gpu-ai provider catalog rows (priority `body` carrier) | M | 2 | [C02] | peer `proxy` URL is the C02 Service DNS name; golden re-capture runs against the post-C02 tree |
| C04 | agent-context Priority wiring (`.rulesync/` sources + `rulesync generate`) | M | 2 | [C03] | the class table cites C03's row IDs; the single-authority table must match the carrier rows exactly |
| C05 | monitoring: official vLLM Grafana dashboards (`url:`-pinned to v0.33.0) | S | 2 | [C02] | dashboard pins pair with the C02 image pin (comment coupling); scrape annotations ship in C02 |
| C06 | on-target acceptance runbook + post-merge verification list | S | 3 | [C01–C05] | runbook references the shipped values/flags/names of every prior chunk |

## Wave order

1. C01, C02 (independent — image and chart; run in id order)
2. C03, C04, C05 (C04 after C03 — row-ID naming; C05 independent of C03/C04)
3. C06 (after all surfaces exist)

## REPLAN ROUND 2 (2026-11-04 — batched question round answers folded in)

One plan, reworked in place; **no chunking change** (C01–C06, waves as above). User
rulings and the resulting edits:

- **Q1 — Open WebUI: DECLINED.** The follow-up card is **NOT created** (DECISIONS,
  human entry); llama-swap `/ui` + Grafana remain the UI surfaces.
- **Q2 — Priority: as recommended** (option E full; 1:1 polarity; classes
  1–3/urgent/p1, unset/default/p10, 4+/background/off-vLLM). C03/C04 unchanged.
- **Q3 — OVERRIDE: "as much room on the card as possible."** D4 re-scoped to
  `--max-model-len 262144` (the model's native ceiling) with `--max-num-seqs 4` kept;
  pool math re-verified against R1 §3 (single 256k ≈ 7.8 GiB KV fits; 4×100k ≈ 12.2 GiB
  at the pool edge; 4×256k still impossible). Constants updated in C02 (serve arg),
  C03 (catalog `limit.context`), C04 (M7 test value), C06 (runbook expectations).
- **Q4 — cluster-internal only.** Trio proxy leg stays skipped with the ruling
  comment. Unchanged.
- **Q5 — 60 s scrape; alerts = follow-up card #2.** Implementation fixed: **no
  `metrics.scrapeInterval` annotation at all** — the v4 `annotationAutodiscovery` 60 s
  default governs (least surface). C02 task/AC updated (exactly two annotations).
- **Q6 — `--enable-sleep-mode` ON** + operator time-sharing discipline in the C06
  runbook. C02 default already true; runbook step explicit.
- **Q7 — Q4_K GGUF via the overlay plugin**, reusing the existing 500 GiB PVC weights.
  Unchanged.

Test Writing is ONE `agent-test` session after planning, writing every chunk's tests
before any dev runs (per this repo's pipeline specifics); a test judged faulty routes
back to the test session, never to the reviewer.

## Follow-up cards (cards, NOT chunks — coord creates cards #1–#4 per the boards
follow-up-card protocol at the Post Research stage, landing in Inbox/Backlog, parent =
cf-105)

1. **ROCm Device Metrics Exporter** — R5: image tag, R9700+8060S sensor availability on
   the openSUSE TW host, DaemonSet on ai-gpu, scrape via the same annotation mechanism,
   optional device-plugin health enablement; GPU Operator recorded as the heavy
   alternative (KMM collides with the manual driver policy).
2. **PrometheusRule alert convention + vLLM alert set** — R5 Q4 table (12 signals);
   thresholds marked *(calibrate)* are set from the C06 benchmark numbers.
3. **8060S vLLM-flash re-evaluation (watch-item)** — R2: GTT verification (R1 OQ1),
   UVA-on-ROCm + PLE placement smokes, re-check when vLLM #31938/#33869 (expert cache),
   PLE-offload-on-AMD, or RDNA MTP land.
4. **llama-swap `selectors` unified 27B ID** (vLLM peer + llama.cpp rungs) — R3 OQ2;
   strategy decision waits on the R9700/Strata time-sharing ruling (Q6 answered:
   sleep-mode ON, but the selector strategy itself is still open).
5. ~~**Open WebUI**~~ — **DECLINED in the 2026-11-04 batched round (Q1)**: llama-swap
   `/ui` + Grafana suffice; the card is **NOT created** (recorded in DECISIONS, human
   entry). Re-request via a fresh card if the owner changes their mind.

## Locked decisions (full evidence log in DECISIONS.md)

- **D1 image/container** — upstream `vllm/vllm-openai-rocm:v0.33.0-rocm100`
  (digest-pinned, R1 §Q2) + thin `containers/vllm-rocm` overlay adding the OOT
  `vllm-gguf-plugin` — pinned to a GIT REF (main ≥ `e454affe…`; no PyPI release
  carries the Qwen3.5 adapter) + a 2-line import-compat patch (RESEARCH Post
  Research V1 — ref/patch mechanics live in the C01 chunk). The overlay exists
  because the 32 GiB multi-session envelope only fits under Q4-class GGUF (R1 §3)
  and GGUF is not in the stock image (R1 §Q3). Rejected:
  AMD-validated `rocm/vllm` 0.29/ROCm 10.1 (lags upstream; py3.14 split), community forks
  (`strix-vllm` — only relevant to the flash model), FP8-weights-only (≈0.9–2.8 GiB KV
  headroom — kills the 3–4-session target).
- **D2 chip** — R9700 (`ROCR_VISIBLE_DEVICES: "0"`; the variable's semantics —
  device index or UUID — are confirmed under ROCm 10, Post Research V2; the R9700's
  index under the v0.33.0-rocm100 image is the C06 step-1 `rocminfo` gate, R1 OQ4).
  8060S = follow-up card (MARGINAL — single-stream ceiling ≈16 tok/s, i.e. at
  best parity with today's measured llama.cpp+MTP 15.35, and vLLM-AMD has no MTP —
  R1 §Q4/§Q6).
- **D3 shape** — standalone `charts/vllm` + `peers.vllm` hop (R1 implications + R3 Q4).
  Rejected: strata-style second controller of the llama-swap Application — vLLM is a
  long-running API server, not a swappable process (R3 Q3 alternative-patterns row).
- **D4 envelope (HR3 override, 2026-11-04)** — `--max-model-len 262144`,
  `--max-num-seqs 4`, `--kv-cache-dtype fp8`, `--gpu-memory-utilization 0.95`,
  `--enable-prefix-caching`, `--enforce-eager` (gfx1201 FP8 graph-capture NaN bug,
  R1 §Q6), Q4 GGUF from the existing 500 GiB PVC. **Pool math (re-verified against
  R1 §3 before this rework):** fp8 KV = 32 KiB/token; one 256k session = 262144 ×
  32 KiB ≈ **7.8 GiB**; the Q4 pool holds ~13.4 GiB of fp8 KV → **one full 256k
  session, or ≈4×100k (12.2 GiB, at the edge), or any mix inside the ~13.4 GiB
  budget** (plus ~2 GiB workspace and 4×144 MiB fixed GDN state already budgeted in
  R1's fit math). **Honest statement (plan approval text + C06 runbook):** this
  configuration maximizes per-session room at the cost of concurrent-session count —
  several simultaneous long sessions exhaust the pool and vLLM priority-preempts the
  lower-priority class by recompute; that preemption IS the intended behavior, and it
  is exactly the arbitration the card-Priority work (C03/C04) exists to provide.
  256k×3–4 simultaneously remains physically impossible (31.2 GiB of KV alone —
  R1 §3). Owner reasoning (HR3): the agent threads are not full simultaneously, so
  per-session room is worth more than guaranteed 4-way concurrency.
- **D5 coexistence** — `--enable-sleep-mode` ON by default (hip-supported, R1 Q5.7) +
  documented time-sharing discipline with Strata on the R9700 (owner ruling Q6).
- **D6 priority (option E, R4)** — 3-class table, 1:1 polarity passthrough (lower = more
  urgent, vLLM's own convention): `1–3 → urgent` (vLLM `priority: 1`, row
  `qwen3.8-27b-vllm-urgent`), `unset → default` (vLLM `priority: 10`, row
  `qwen3.8-27b-vllm`), `4+ → background` (off vLLM entirely, onto llama.cpp
  `qwen3.8-27b-q4` — keeps KV headroom for urgent/default). The peer carries
  `filters.setParams: {"priority?": 10}` so non-priority clients land in the default
  class (set-if-undefined; a client-sent value wins). Boards-skill roster line + D12
  carve-out + `pipeline-models` class table + `pipeline-kickoff`/STATE.json
  `kickoff.priority` record change — `.rulesync/` sources + `rulesync generate` only.
- **D7 FE/UI** — llama-swap `peers.vllm` only; `/ui` (playground + Activity with vLLM
  usage parsing) + Grafana dashboards are the surfaces (R3 Q4). No new ingress.
- **D8 monitoring** — two pod annotations in C02 (`k8s.grafana.com/scrape`,
  `metrics.portNumber: "8000"`; 60 s scrape = the v4 feature default — NO
  `metrics.scrapeInterval` annotation, Q5) — ONE mechanism, never
  both annotations and a PodMonitor CR (no dedup, R5 Q2); `--disable-access-log-for-
  endpoints /health,/metrics,/ping` (R5 #29023); two dashboard `url:` entries in C05
  under the existing `default` folder, pinned to tag v0.33.0 with a comment pairing the
  pin to the image pin (renovate can't track raw URLs); NO PrometheusRule in this ticket
  (Q5); do NOT enable `--enable-log-requests`/`--enable-log-outputs` (prompt content
  into Loki), leave OTLP unset (R5 implications).
- **D9 flash model** — unchanged; Strata keeps it (R2 verdict; the evidence log is
  DECISIONS.md entry D9).
- **D10 naming** — served model name `qwen3.8-27b-vllm` (no collision with any local
  rung — llama-swap precedence: local IDs beat unqualified peer IDs, so the name is
  deliberately new); unqualified addressing (lab convention, cf. the
  `qwen3.8-flash-next-strata` row).

## Run protocol (board run, card cf-105 `R4EjaHtDeHMjAkDpf`)

- Branch/worktree `cf-105-feat-implement-vllm`; commits local only. **PR + merge are
  human-owned** (HITL `PR`); ArgoCD applies everything — no kubectl.
- Post-plan-approval: card write-back (slug field combined value + unchecked-item
  deletion) per the boards skill; follow-up cards (above) created at the Post Research
  stage.
- Exit: final whole-plan review passed → card to **Review** + summary comment →
  `pipeline_release(outcome:"done")`. **Finished** stays human-owned.
- On-target acceptance (C06 runbook) runs post-merge, operator-driven; its benchmark
  numbers feed the follow-up alert card's thresholds.

## Risks / assumptions

- **RDNA vLLM software maturity** (R1 top-3 risk): the first deploy is a
  benchmark/acceptance run, not a service flip (C06). `--enforce-eager` stays until the
  FP8 graph-capture NaN bug clears upstream (vllm#28649).
- **256k prefill TTFT (D4 override)**: a single 256k-context request pays a minutes-
  scale prefill (R1 §Q4: 131.5 s at 128K / 320.7 s at 256K measured on the 8060S even
  under llama.cpp; the R9700 is faster but the same physics). The C03 peer
  `responseHeader: 1800` covers the first byte; the C02 startup probe (15 min envelope)
  is unaffected (it hits `/health`, not a completion). The `request_tokens` histogram
  family scales with `--max-model-len` (262k) — more metric cardinality than 131k would
  have given; accepted per D4, noted for the alert follow-up card.
- **256k single-session prefill** (D4 override): a 256k prefill takes minutes on this
  pool (R1 §Q4: the 8060S measured 131.5 s TTFT at 128K / 320.7 s at 256K even under
  llama.cpp; the R9700 has more compute but the same KV physics) — the C03 peer
  `responseHeader: 1800` covers the end-to-end first byte, and the C02 startup probe is
  unaffected (it probes `/health`, not a request). The `request_tokens` histogram
  bucket family scales with `--max-model-len` (262k) — extra metric cardinality,
  accepted in D4, noted for the alert follow-up card.
- **R9700 contention with Strata**: both claim the same 32 GiB GDDR6; sleep mode is the
  lever, but llama-swap cannot unload a peer (R3 Q5.5) — time-sharing is operator
  discipline documented in the C06 runbook until the owner rules (Q6).
- **GGUF+vLLM on RDNA is experimental** (R1 §Q3, "highly experimental and
  under-optimized" — Post Research V1: the risk concentrates in the weight ADAPTER
  (the plugin), not the model class, which is in-tree since Feb 2026). Fallback leg
  if the on-target load fails: official FP8 checkpoint — CONFIRMED to exist (RESEARCH
  Post Research V4: `Qwen/Qwen3.8-27B-FP8`, 28.77 GiB, W8A8 dynamic e4m3, stock-
  loadable) — values-only `modelPath` swap (`--model Qwen/Qwen3.8-27B-FP8` +
  `--language-model-only`, no plugin, no chart change — but KV headroom drops to
  ~1 session).
- **Unverified on-target facts** the runbook resolves (no exec tier in agent
  sessions): the R9700's ROCr index under the v0.33.0-rocm100 image (the
  `ROCR_VISIBLE_DEVICES` variable itself is confirmed — index or UUID, ROCm 10 —
  Post Research V2; the index is the C06 step-1 image-side `rocminfo` gate), host
  amdgpu driver vs ROCm 10 expectations (R1 OQ5), 18 GiB first pull + Triton JIT
  startup time (probe sizing), `job="vllm"` label fallback (R5), `finished_reason`
  enum values (R5 OQ6), vLLM peer `max_model_len` discovery in the pinned v266
  (R3 OQ3).
- **Golden churn (C03)**: adding `peers.vllm` changes the rendered gpu-ai llama-swap
  config — golden re-captured per the TEST_SPEC pattern; the gpu-cluster golden stays
  byte-identical (the block is gpu-ai-only).
- **RAM coexistence law** (EXPLORE §8.6): the vLLM pod's system-RAM budget is sized in
  the chart (16 Gi request / 32 Gi limit) so it cannot destabilize the 125 Gi node
  shared with Strata's 116 Gi-limit pod.

## Open questions — ANSWERED (2026-11-04 batched question round; rulings above)

All seven questions were answered in the one batched round before final approval; the
answers are the round-2 rulings (REPLAN ROUND 2 above). Recorded for the card trail:

- **Q1 — human chat UI (Open WebUI)?** **No, declined.** llama-swap `/ui` + Grafana
  suffice. Consequence: follow-up card #5 is NOT created (DECISIONS, human entry).
- **Q2 — `Priority` polarity + class table + model-tier leg?** **As recommended:** 1 =
  most urgent, 1:1 passthrough (vLLM lower = earlier); 3 classes — 1–3 urgent (vLLM
  priority 1), unset default (priority 10), 4+ background (off vLLM onto llama.cpp
  `qwen3.8-27b-q4`); yes to the model-tier leg (option E full).
- **Q3 — context envelope to ship?** **OVERRIDE of the recommendation:** "as much room
  on the card as possible" → `--max-model-len 262144` (model's native ceiling),
  `--max-num-seqs 4` kept. Per-session room maximized at 256k; simultaneous sessions
  share the ~13.4 GiB fp8-KV pool and are arbitrated by the Priority→vLLM preemption
  work (C03/C04) when it exhausts. 4×256k simultaneously remains physically impossible
  (R1 §3).
- **Q4 — public host or cluster-internal?** **Cluster-internal** (no `vllm.<domain>`;
  trio proxy leg skipped with the ruling comment; agents reach vLLM through
  `llama.<domain>/v1`).
- **Q5 — scrape interval + alert convention?** **60 s** (no `metrics.scrapeInterval`
  annotation — the v4 feature default governs) and **alerts as follow-up card #2**
  (thresholds need the C06 benchmark numbers).
- **Q6 — R9700 coexistence with Strata?** **`--enable-sleep-mode` ON + operator
  time-sharing discipline** (C02 default; C06 runbook documents /sleep, /wake_up and
  the R9700 contention expectations).
- **Q7 — weight format?** **Q4_K GGUF via the overlay plugin**, reusing the existing
  500 GiB PVC weights (the 32 GiB path that fits the envelope; official-FP8-checkpoint
  question R1 OQ2 noted, values-only swappable later).
