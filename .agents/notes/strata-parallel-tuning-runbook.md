# Strata parallel-tuning runbook — cf-141 (AD-141)

Operator-facing method document for "Tune Strata for parallel performance"
(card AD-141, plan `2026-11-10-refactor-cf-141-refactor-strata-parallel-tuning`,
approved 2026-11-10 with Q17 resolved to option (a)). It is the ticket's
attribution control: every later chunk's shipped state must agree with a row
here. Read current-posture-first — §4 is gate work that has NOT shipped, and
the shipped-anyway rows in §6 are honest over-budget shapes, not fits. Every
in-pod / on-node command in this note is `run_by: user` (no pod exec exists at
any agent tier); agent-capable reads are labeled as such. Evidence tags follow
the guide's ground rule 1 — [M] measured, [E] arithmetic, [I] inferred,
[V]/[R] read — because this ticket exists to stop untagged numbers hardening.
Source keys `[n]` resolve in the ticket's `RESEARCH.md` (rounds 1–2).

## 1. Pin & envelope state board

One dated row per owner ruling and per merge; the board is the truth-check
surface after every ArgoCD sync (live ConfigMap `strata-profile` is the
rendered echo).

| date | kind | state |
| --- | --- | --- |
| 2026-11-10 | pin (baseline) | Strata 0.2.9 / engine 0.1.55 at commit `a6e493b78` — the pre-PR-1 posture: per-rung parallel {4,4,4,4,1}, cgroup 110Gi, caps 110592/103680/92160, MALLOC_MMAP protections live |
| 2026-11-10 | ruling Q5 | "Open the envelope to 8 slots" — frame override |
| 2026-11-10/11 | ruling Q9 | "8 slots everywhere. I know it won't fit, but I also know I won't be running 8 sessions at full context. I'd rather crash it and scale back from there." Accepted outcomes: engine fit-down (degraded `batch_slots`), conversation-park refusals, contained cgroup kills until a per-rung scale-back |
| 2026-11-10 | ruling Q10 | yes — the full row-H shape for the primary (conv 16384 + PLE auto off) |
| 2026-11-10 | ruling Q8 | "No — re-plan with bump/envelope" — the 0.2.13 bump is this ticket's work |
| 2026-11-10/11 | ruling Q13 | "(a) Pin-first, bump gated" — PR-1 ships at the current pin |
| 2026-11-10/11 | ruling Q15 | two PRs: PR-1 = C01+C02+C03 (runbook + lever + envelope), PR-2 = C04 (the bump) |
| 2026-11-10/11 | ruling Q12 | the U3-v2 cgroup-detection user leg is declined — not run in this ticket (see §3's standing note) |
| 2026-11-10/11 | approval Q17 | plan approved, option (a) stands: crash-and-scale-back at the pin with per-rung boot-read gates and pre-written revert lines |
| 2026-11-11 | shipped (PR-1, C03) | per-rung parallel 8/8/8/8/1 (primary, strix, orca, q4 raised; ornith stays 1 by its surface law); primary conv 16384 + `STRATA_PLE_AUTO_RAM=0` (row-H trio); the §6 ladder rows are the live shipped state, boot-read evidence fills from the owner's post-merge runs |
| 2026-11-11 | shipped (PR-2, C04) | Strata 0.2.13 / engine 0.1.59 on the cf-141 branch in ONE ledger commit set: Dockerfile FROM pair + clone `v0.2.13` + 0.1.59 label dirs, README ledger with digests re-read 2026-11-11 (anonymous token + manifest HEAD), marker pair `.checkout-0.2.13-carry1`, carry patch re-cut at d2f0964 (RESEARCH R3 verdict (a)), drafting pins ×4 (Q16 experimental). Reaches the node only via merge→CI `:main` + the marker-keyed claim migration, then §3 U1-v2 and §4's soak watch with the binding stop condition — the on-target verdict is the bump's "done", not this row |

Pointer: the bump-evaluation plan `.agents/plans/2026-11-10-dep-strata-engine-0213-eval.md`
is **superseded-as-executed-by-AD-141** at its gate 6 — the owner un-deferred
the bump; its gates 1–5 live in this note's §4 and are the ticket's work.

## 2. U1 capture (at-pin, gates every arm)

Plan law 1 (version-churn gate): no flag is adopted before the startup/`--help`
capture verifies it on the **installed** build. One operator session, three
legs; the shapes come from `charts/llama-swap/README.md` ladder rungs 1–2 and
host-runbook §3.4.

Leg A — version truth + flag audit, run_by: user:

    # run_by: user (operator) — README ladder rung 1 shape
    kubectl -n default exec deploy/gpu-ai-llama-swap-strata -- /opt/strata/terminal/bin/strata --version
    kubectl -n default exec deploy/gpu-ai-llama-swap-strata -- /models/strata/Strata/engine/strata --help > strata-engine-help-$(date +%F).txt

Leg A read-back — grep the `--help` capture for every RESEARCH OQ-2 table flag
before any adoption: `--expert-cache`, `--vram-reserve-mib` (default 700
[18]), `--prefill auto[:N]`, `--kv fp16|int8|q4_0|k8v4`, `--kv-resident`,
`--ple-io` (the `ram` value stays forbidden — hazard law [26]),
`--mtp`/`--spec`/`--spec-min-p`, `--batch-mtp` or `STRATA_BATCH_MTP`,
`--resident-experts` (forbidden, not an arm [21][48][49]), `--mtp-window`,
`--lookup-chain`, route-tail (`STRATA_ROUTE_TAIL_SKIP`), `--no-prefill-borrow`,
`STRATA_PREFILL_CPU_SHARE`, `STRATA_ENGINE_NICE`,
`--conversation-cache-mib/-slots`, `--memory-limit-mib`, `--kv-grow` +
`STRATA_KV_GROW_HOLD` (it exists [V]), and the bench suite choices
(`standard-v1`, `parallel-mixed-v1` [31]). Expect ABSENT at the pin:
`--kv-pool-tokens`, `--ram-keep-gib`, `STRATA_ARENA_FILE_CACHE` [34].

Leg B — startup-log read-back for the **q4 AND the primary** arenas
(operator-run; the discipline layer, all lines exist at the pin [4][6][7][55]):
`INFO batch_slots=N`; `expert cache auto: … -> N slots`; `the slot sessions
take … GiB`; the K/V pinned-RAM GiB line — it settles the 3.09–3.35 band as
truth for our build, and neither doc gets "fixed" to the other (DECISIONS);
the hipBLASLt line (silence expected — OQ-6 closed as grounded no-op
[22][23][24]); the `--ple-io`/residency resolution line.

Leg C — host Step-0 [VERIFY] re-read, operator-run on the node: cmdline trio
(ttm.pages_limit / amd_iommu=off), memlock/nofile limits, GIDs, `rocminfo`
ROCm-index map, OCuLink `LnkSta`. The cells and exact commands live in
`.agents/notes/strata-host-prep-gpu-ai.md` Step 0 — this note layers on that
runbook and never restates its cells (one home per fact).

`strata update` never runs in the container — version moves ride the
tag→digest ledger in one commit (plan law 6; containers README cadence §6).

## 3. U1-v2 capture (post-bump, re-arms §2 on the new build)

RESEARCH round 2 OQ-R2b.5 churn checklist, less the U3-v2 item (declined at
Q12) — the names that move semantics without moving spelling.

- run_by: user (operator session after PR-2 merges): `strata --version` and
  the engine label dirs — expect `0.1.59-linux-x86_64-hip-halo` /
  `…-hip-rx9070` [73][77]; the chart's strix `exe`/`lib_dirs` must match.
- the `[strata] drafting:` line — `drafting.apply()` now runs unconditionally
  at 0.2.13 [79]; the `"drafting": "mtp"` profile pins (experimental-flagged
  per Q16) must resolve to MTP on gfx1201.
- arch-default lines: the MMQ K-quant prompt line on UD-Q4-class packs
  (NOT the IQ3_S primary) [61][62], `STRATA_SELECT_WMMA` /
  `STRATA_SELECT_ALT_MIN_TOKENS=28672` [62], chunked-GDN.
- the bare-`auto` prefill ceiling evidence: 8192 → 32768 on gfx12,
  `STRATA_GFX12_CHUNK` steps it back [63].
- the `vram_fit` window-walkdown lines 20480→8192→4096 — the grace that makes
  the post-bump 8-everywhere posture materially different from the pin's,
  where no walkdown exists [60].
- the "starting again without a drafter" warning — a silent decode-speed drop
  class, watch `[strata]` lines and `drafting_note` [79].
- the `KV streaming: % hit` line — hit-rate is observable per start [74].
- shipped-env re-grep (all must still parse at 0.1.59): `STRATA_REQUEST_LINES`,
  `STRATA_PREFILL_CPU_SHARE`, `STRATA_PF_FUSED`, `MALLOC_MMAP_THRESHOLD_`,
  `ROCR_VISIBLE_DEVICES` [65][73].
- bench suite choices re-check — verified identical at the tag [72].

Standing note (Q12): there is **no U3-v2 leg** — the cgroup-detection probe
was declined and is NOT a scheduled step. The row-G cgroup-detection premise
(whether our k3s pod presents a detectable limit to the engine's file-cache
rescue [67]) stays **UNMEASURED**, and any future row-G authorization must
carry its own probe — recorded so no later run mistakes it for answered.

## 4. Bump-gate appendix (C04 satisfies; Q13(a) fixed the shape)

Condensed from the superseded bump-eval plan
`.agents/plans/2026-11-10-dep-strata-engine-0213-eval.md` — AD-141 answered
gate 6; gates 1–5 are C04's work. A HOLD at gate 1 after a fresh re-fetch is
compliance, not failure. Gate 1 and gate 2's digest re-reads are agent-capable
reads (GitHub API; GHCR anonymous token + manifest HEAD — no daemon).

Gate 1 — same-day crash-cluster re-fetch (must be re-run the day C04 lands
ready; the cluster churns daily). Last fetch 2026-11-11 (ready-day; second pass
at commit-set assembly): all eight issues still open; the crash classes keep the
zero maintainer-reply posture (#5559/#5608/#5635/#5558/#5564/#5629 comment
authors are reporter-only).
**0.1.59 confirmed in the failing set** (#5559 and #5635 reporter updates,
unchanged). #5701 carries the cluster's first maintainer touch (Niko1221,
2026-11-10 23:22Z): a reproduction request — their own run of the reporter's
124K-token shape on a 32 GB R9700, Linux, engine 0.1.59 did not fail; not a
"do not upgrade", no fix named. #5614 gained a reporter cross-reference to the
same MES `REMOVE_QUEUE` wedge seen outside Strata on a single R9700 (cold-cache
start, external project) — corroboration of the class, not a new Strata crash.
New gfx1201 reports since 2026-11-10: none in the crash class — #5762
(2026-11-11) is a benchmark, not a regression: DFlash2 does not prompt-stall
on the R9700 at 0.1.59.1 (our rungs pin MTP; the 0.2.13 Known-problems DFlash2
line stands as upstream wrote it). No release names a cluster fix; v0.2.13
(2026-11-09) is still the newest — the candidate is not re-ordered. The eval's
"0.1.57 clean" premise is dead (the twin-box reporter corrected it [74]); its
"#5317/#5341" citations correct to **#5327** (PR #5531, merged 2026-11-09
[68]). Ready-day verdict: NO deterioration; the soak's binding stop condition
(gate 6's paragraph below) still governs after merge.

| issue | class | engine-0.1.59 evidence |
| --- | --- | --- |
| #5559 | GPF storm in `libhsa-runtime64`; `hsa_signal_load_relaxed` / `hsa_signal_store_relaxed` freed-signal vtable pairs; nearest published twin of the ai-gpu node (R9700 + 128 GB, IQ3_S, 262144 int8) | "0.1.59 stops the same way" (reporter 2026-11-10) [74] |
| #5608 | AMDGPU gfxhub page faults during IQ3_S inference | faults again under Docker 0.2.13 [74] |
| #5635 | load-RAM regression 68→114.8 GB at 0.1.58 → systemd-oomd SIGKILL — the load-peak `MemAvailable` class, exactly the 2026-11-10 incident class | confirmed on engine 0.1.59 (~64→~92 GB) [74] |
| #5614 | kernel MES wedge, `REMOVE_QUEUE`, after "verify: unspecified launch failure" | not yet run by the reporter [75] |
| #5558 | 0.2.12 fails to start — startup-timeout class | reporter on 0.1.56, not gfx1201 [74] |
| #5564 | prefill stuck ~111K; cancel leaves a busy-wait | class-relevant watch-item, not gfx1201 [74] |
| #5701 | gfx1201 + 0.1.59 long agent sessions → non-finite logit decay (#879/#2519 GDN-overflow family) | runs on 0.1.59 and fails [75] |
| #5629 | "verify: layer N never rang" illegal-memory-access, int8 KV | arch unconfirmed in body [75] |
| #5020 | arena keeps all 24,576 experts resident on top of the VRAM cache (filed at 0.1.55) | open, zero comments [74] |
| #3364 | expert-cache auto vs batch-slot ordering | open, no fix recorded [74] |
| #3693 / #3734 | explicit-cache overshoot; AMD duplication | closed by housekeeping bots, not fixes [40][49] |
| #3574 | carry-patch home — closed **not_planned**: `carry/ornith-q36.patch` MUST apply at v0.2.13 | Dockerfile verify layer is the build tripwire [74] |

Gate 2 — ledger-law build, ONE commit: both FROM tags (0.2.13-rocm-gfx120x +
0.2.13-rocm-gfx1151), the clone tag `v0.2.13`, the README rows, and digests
re-read live via anonymous token + manifest HEAD; the `com.strata.engine` OCI
label is the engine-version proof [R]. Claim-compiled `exe` paths are
version-free and do NOT move (marker-keyed migration recompiles in place).

Gate 3 — soak. Chosen shape per Q13(a): the **post-merge production watch** —
the hourly fleet IS #5559's traffic shape (conv-heavy 35K–92K controller/worker
sessions on the q4 arena), watched with §5's Grafana/Loki method plus dmesg.
Tripwire signatures: dmesg `libhsa-runtime64` GPF and the
`hsa_signal_load_relaxed`/`hsa_signal_store_relaxed` vtable pairs; the gfxhub /
`REMOVE_QUEUE` MES wedge; the load-peak `MemAvailable` class (#5635);
non-finite logit decay probes (#5701 class).

Documented alternative, NOT chosen: user `workflow_dispatch` of a branch-built
image plus a hand-swap of the live pod (`kubectl set image`). It stays
documented-only because it is an admin mutation outside GitOps — ArgoCD
reverts any object it did not apply — and carries that GitOps-revert caveat
(if the app is not paused) every time it is mentioned [R2-D].

Gate 4 — on-node `--plan` re-checks per host-runbook §3.4, run_by: user
(operator session): `strata serve --plan --output json` against the
**post-PR-1 posture** — engine label/version, arena fit, KV/slot sizing, PLE
resolution, prompt-chunk lines. The eval's stale "parallel 2 +
concurrencyLimit 1" sentence is superseded, not copied; the Q9/Q10 shipped
values are the baseline it checks.

Gate 5 — re-bench with the bump-attribution sheet: the MMQ K-quant fold
[61][62], `SELECT_WMMA` +5.7% at 98K [62], the bare-auto 32768 ceiling [63],
chunked GDN — attributed to the BUMP. L2's env pin is the engine's own default
at 0.1.59: its delta is explicitly not double-counted against the bump's (Q16).

Gate 6 — the owner gate was answered by AD-141 (Q8 override + Q13(a)
sequencing); gates 1–5 above are this ticket's work. **Stop condition,
binding**: any reproduced signature stops the bump leg — a revert PR is
prepared and the evidence returns to the owner — no fix-forward.

## 5. Benchmark procedure (guide §10 localized, per-rung)

Preconditions per run (all run_by: user, operator session): a fresh engine
start; the host cache drop (`echo 3 > /proc/sys/vm/drop_caches`); GPU idle;
nothing else scheduled on the node. The `--plan`/startup read-backs of §2
precede every round.

Suites at the pin: `standard-v1` baseline passes; `parallel-mixed-v1` sweeps
(both exist in the 0.2.9 cli choices [31]). Sweep sets per rung: the primary
sweeps {1, 2, 4, 8} — C03 shipped row H, which genuinely fits at the pin;
every other rung sweeps ONLY after its **boot-read gate** confirmed real
8-slot service — a
degraded `batch_slots` rung sweeps to its REAL serving count with that recorded
(sweeping past the confirmed count is exactly the self-deception the guide's
read-back law forbids). The ornith sweep stays {1} — its `parallel: 1` is a
surface-law negative pin. Depth sweep {8K, 32K, 128K, 256K} with frozen
prompts (SHA-256 recorded), distinct suffixes per cell, and pinned
`stream`/`max_tokens`/`reasoning_effort`. batch-MTP on/off passes ride the L3
follow-up round, not this PR.

Per-cell logging via Grafana/Loki (agent-capable reads,
`readonly-global-grafana`; method proven in
`.agents/plans/2026-11-10-debug-strata-q4-oom-crashloop.md`):
`node_memory_MemAvailable_bytes`,
`kube_pod_container_status_restarts_total` for the strata container, and LogQL
`{container="strata"}`.

Stop criteria (the guide's §10.6 rows 1–5, localized — [R] card AD-141; any
one ends the round):

1. `batch_slots` below requested — the engine reports serving fewer slots than
   configured; this is the boot-read gate's own line, so a degraded boot ends
   the round before any sweep is trusted
2. stall (`no progress for 60 s`), an engine restart, an amdgpu reset / AER
   event, or a cgroup kill + restart pair inside the window
3. `VRAM free` below 1 GiB, MemAvailable below the guide's 4 GiB floor, or
   sustained swap-out — the Grafana/Loki watch rows above carry the series
4. per-stream decode below the usability floor or p95/first-token latency past
   the fleet agent timeout — the fleet rides q4, so its row is the sharpest
   line (the agent-traffic band floor is the measured 40–60 q4 decode band)
5. aggregate tok/s rising under the guide's <5% bar from one sweep level to
   the next — the last cell before that is the parallel limit; the whole
   ticket tunes to move it

Repo-local additions, deliberately OUTSIDE the numbered §10.6 list and never
counted as guide rows: the host-runbook §3.4a prompt-rate bar (≈2,519 tok/s
@64–200K — gate 5's re-bench floor [R2-A]) and the near-tie quality-flip probe
(the MMQ-KQ / SELECT_WMMA known class [36][62]).

## 6. Envelope table (honest math) + scale-back ladder

Rows are [E] arithmetic on [M-node] arena terms, per RESEARCH R2-C/R2 tables —
cited, not invented. "Shipped anyway" rows are NOT fits: Q9 authorizes
crashing into them; the boot-read gates decide what actually serves. As of
C03's landing this table IS the shipped envelope: row H fits at the pin, the
strix/orca/q4 raises ride it knowingly over budget, ornith's 1 stands — the
per-rung boot-reads the owner runs after PR-1 merges are the first real
verdicts on these rows.

| row | shape | host terms (GiB) | verdict |
| --- | --- | --- | --- |
| H | primary IQ3_S 8x262144 int8, conv 16384, PLE-direct (`STRATA_PLE_AUTO_RAM=0` [26]) | 46.84 + 30.15 + 16 + 6 = **99.0** ≤ 108 ≤ 110 | fits AT THE PIN — no bump needed; the bump only adds walkdown grace [52][58] |
| A′ | q4 bare 8x262144 int8 | 71.73 + 30.15 + 16 + 6 = **123.9** | over the 110Gi cgroup and the node — shipped anyway per Q9; expect engine fit-down or a contained cgroup kill |
| — | orca 8x262144 | 57.7 + 30.15 + 8 + 6 = **101.9** | over its declared cap (the U9.2 zero-growth law) — shipped anyway per Q9; park refusals expected |
| — | strix 8x262144 | own UMA ruling class (8060S shared memory, no declared cap) | shipped anyway per Q9; boot-read gate applies identically |
| — | ornith | `parallel: 1` negative pin | stays 1 — surface law; Q9 reads as the flash-next rungs only, interpretation flagged at Q17 and confirmed by the approval |
| G | q4 file-tier (`--resident-budget-gib ~44` + honest-cgroup page cache), PLE-direct | ≈ **96.2** anon [66][67] | row G is Q11 experiment-authorized only, never default, premise UNMEASURED (Q12 declined its probe), no pre-committed chunk |
| E | `--resident-experts` complement | ≈51.7 + 30.15 + 16 + 6 = 103.9 | fits on paper only — CUDA-only evidence, #3734 unfixed, #5020 open [21][48][49]; it and A′ are the reason row G is an experiment, not a shipping shape |

Laws cited: the **(N+1)** rule — N slot sessions + 1 main session, each pinned
for the whole `--max-context` at engine start — survives at both pins
[57][58][59], the pinned block byte-identical; at 8 slots the **9 sessions**
pin **30.15 GiB** of int8 KV at 262144. The **13,728 B/token** law (13
KV-bearing layers × 1,056 B/cell int8) and the measured band **3.09–3.35
GiB/slot@262K** also survive both pins [7][52][59] — U1's own pinned-RAM line
is truth for our build. VRAM: 9 sessions × ≈0.4–0.56 GiB of resident window
before the expert cache auto-sizes (slots-before-cache order at both tags
[6][58]). The `vram_fit` window walkdown grace exists post-bump only
(0.1.59-only floor path) — that asymmetry is exactly why Q17's (a) was stated
as crash-and-scale-back at the pin [60].

Scale-back ladder — the shipped rows below ARE the live envelope values
(C03 landed them); boot-read evidence fills from the owner's post-merge
runs. Discipline: scale-back
executes ONLY on an explicit in-round owner word, one rung per commit, never
agent discretion; a degraded boot-read is recorded, not success (plan law 3).

| rung | shipped parallel | budget verdict at the pin | first symptom | revert value | gate = startup read when that arena loads |
| --- | --- | --- | --- | --- | --- |
| primary | 8 | fits (row H) | degraded `batch_slots` | `parallel: 4` | INFO batch_slots + slot-session GiB lines |
| strix | 8 | own UMA class | degraded `batch_slots` | `parallel: 4` | INFO batch_slots |
| orca | 8 | 101.9 over cap | park refusals | `parallel: 4` | INFO batch_slots + parking refusals |
| q4 | 8 | 123.9 over cgroup | cgroup kill + restart pair | `parallel: 4` — the a6e493b78 posture is q4's scale-back target | INFO batch_slots + restart counter |

## 7. Arm table (exact diffs, one change per merge)

`shipped-in:` marks which chunk's commit-set flips the row; every key-path
resolves in `charts/llama-swap/values.yaml` today. Follow-up arms are
documented here and shipped by NO chunk — each needs its own owner round.

| arm | key-path | before | after | effect | citation | risk | on-target check | revert | shipped-in |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L2 | strata.config.engineProfileStrataQ4.env | {} | {"STRATA_MMQ_KQ": "1"} | +10.3 / +14.3 / +16.8% prompt speed on R9700 [36] | [32][36][61][62] | near-tie answer flips [36] | U1 read-back + §5 round | remove the line | C02 |
| envelope-primary | strata.config.engineProfile.parallel | 4 | 8 | row H fits at 99.0 | Q9+Q10 | crash-and-scale-back | boot-read gate | `parallel: 4` | C03 |
| envelope-strix | strata.config.engineProfileStrix.parallel | 4 | 8 | 8-everywhere at the pin | Q9 | boot-read subject | boot-read gate | `parallel: 4` | C03 |
| envelope-orca | strata.config.engineProfileOrca.parallel | 4 | 8 | 8-everywhere at the pin | Q9 | park refusals | boot-read gate | `parallel: 4` | C03 |
| envelope-q4 | strata.config.engineProfileStrataQ4.parallel | 4 | 8 | Q9 supersedes a6e493b78 | Q9 | 123.9 over cgroup | boot-read gate | `parallel: 4` | C03 |
| envelope-ornith | strata.config.engineProfileStrataOrnith.parallel | 1 | 1 | unchanged negative pin | q36 surface law | none | none | n/a | unchanged |
| L1 | strata.config.engineProfileStrataQ4.env | {} | the nine-var manual stack (`STRATA_CKPT_POOL=1`, `STRATA_CKPT_POOL_READY=4`, `STRATA_SLOT_CKPT_MOVE=1`, `STRATA_SLOT_COPY_DIRECT=1`, `STRATA_SLOT_COPY_BATCHSYNC=1`, `STRATA_BATCH_GDN_GROUPS=1`, `STRATA_BATCH_ATTN_ROWS=1`, `STRATA_BATCH_SELF_COMMIT=1`, `STRATA_QSA_SLOTS=1`) | the 1.45×@c=8 headline — never auto-applied on HIP at either pin [14][38][61] | [14][38][61] | HIP-unqualified, confidence 6/10 | full §5 bench round | remove block | follow-up (Q2) |
| L3 | strata.config.engineProfileStrataQ4.env | {} | {"STRATA_BATCH_MTP": "1"} env form | per-slot drafters; single-GPU semantics at our shape [6] | [6][58] | per-slot drafters + pinned-RAM rings shrink the cache further | drafter line + `batch_slots` read-back | remove line | follow-up (Q3) — never stacked in an envelope PR |
| L4 | --kv q4_0 (profile args element) | int8 | q4_0 | decision scaffolding ONLY (Q4): #4159 measured — int8 KL 0.055 / top-1 94.9 / PPL 2.762; q4_0 KL 0.130 / top-1 91.7 / PPL 2.793; agent segment 0.090 vs 0.200; the guide's "+8–12% PPL" is refuted at PR #21, whose merged body preserves perplexity [43]; q4+q4_0@8 = 109.2 stays over — the arena term is the wall, so its 8-slot value is nil, while it halves deep-park KV at the 4-slot posture | [42][43][8] | agent-segment KL ×2.2 on an agent-heavy fleet | owner per-rung round | none shipped | decision-only (Q4) |
| L5 | --vram-reserve-mib 2048 (args) | engine default 700 | 2048 | VRAM reserve floor; also disables the small-card auto-shrink [18][17] | [18] | lowest priority | bench round | drop flag | follow-up |
| L6′ | STRATA_PREFILL_CPU_SHARE_BATCH=1 (env) | off (0.2.9 behaviour) | 1 | CPU pool beside batch slots — the named answer to the guide's "CPU share helps only without --batch" row; 0.1.59-only [69] | [69] | post-bump only | bench round | remove line | follow-up |

Post-bump posture (Q16, the owner's word): `STRATA_MMQ_KQ=1` and
`"drafting": "mtp"` stay PRESENT at 0.1.59, each carrying an experimental-flag
comment — kept as an experimental pin, NOT as settled intent-pinning; the
engine's own Linux-gfx12 default already applies to UD-Q4-class packs
(user-set wins [61][62]) and the IQ3_S primary sits outside that flip. Q16
comment doctrine: state what the key pins, that the engine default now applies,
that it is experimental per the ruling, and the revert line — why-only, no
history narration. `--kv` is engine-args surface: changing it re-pins the
`--kv`-mirroring law through the test session, never a dev edit.

Forbidden forms in the chosen flow: `--ple-io ram` stays a negative-pinned
hazard (the 2026-10-29 OOM law [26]) — never a posture here;
`--resident-experts` is not an arm (unproven on gfx1201, AMD duplication
open [21][48][49]); `strata update` never runs in the container; hipBLASLt
table steps are a no-op at our posture [22][23][24].

## 8. Quality/decision record (Q1–Q17 dispositions)

| Q | owner answer | disposition |
| --- | --- | --- |
| Q1 | yes — ship L2 (`STRATA_MMQ_KQ=1` on q4) | answered — rides C02 |
| Q2 | L1 documented, not shipped | answered — follow-up arm |
| Q3 | L3 env form documented | answered — follow-up arm |
| Q4 | no — `--kv q4_0` stays owner-gated | answered — §7 decision scaffolding only |
| Q5 | open the envelope to 8 slots | answered — frame override |
| Q6 | yes — new `.agents/notes/strata-parallel-tuning-runbook.md` | answered — this note |
| Q7 | four stale-doc corrections with law moves | answered — ride C02 (+Q14 fold) |
| Q8 | no — re-plan with bump/envelope | answered — frame override |
| Q9 | 8 everywhere — "crash it and scale back from there" | answered — override; shipped-anyway rows in §6 |
| Q10 | yes — full row-H for the primary | answered — C03 primary row |
| Q11 | authorize as experiment only (row-G, no chunk pre-committed) | experiment-authorized, NOT scheduled |
| Q12 | No — the U3-v2 cgroup-detection user leg is not run | declined 2026-11-10/11 and recorded — row-G premise stays UNMEASURED; re-probe required for any future row-G decision |
| Q13 | (a) pin-first, bump gated | answered — sequencing + soak shape |
| Q14 | fold them in — doc-fix total seven | answered — roster in the plan/STATE |
| Q15 | two PRs: PR-1 = C01+C02+C03, PR-2 = C04 | answered — landing shape |
| Q16 | flags stay present, commented experimental | answered — §7 posture |
| Q17 | resolved at approval — option (a) stands | approved 2026-11-10: crash-and-scale-back at the pin |

## 9. Verdict-record template

Copy one block per bench round into the ticket folder's follow-up notes:
fields — pre-read startup table (per arena: batch_slots, expert-cache slots,
slot-session GiB, pinned-RAM GiB), sweep table (one cell per concurrency ×
depth), stop criteria hit, Grafana/Loki links, decision (retain / revert /
gate), follow-ups. Pre-filled round rows waiting for their chunks: the C02
L2 arm round; the C03 per-rung boot-read rounds (and any scale-back round);
the C04 post-merge soak watch plus the re-bench attribution sheet.

## 10. Corrections ledger

Round 1 (ten) + rounds 2–3 — each with its citation; these adjudicate what
earlier docs and the card guide got wrong:

- `parallel:` IS `--batch` at the pin, via serve/server.py `parallel_args` [5]; the cf-77 Q2 ruling rejected the literal argv element, not the engine path (OQ-1 settled).
- `STRATA_KV_GROW_HOLD` exists at 0.2.9 (`generate.cpp:14636`) [V] — EXPLORE gotcha 5 corrected, not edited; the scout file stands as history.
- `--vram-reserve-mib` exists at the pin, default 700 [18] — the guide's 2048 is a supported value; EXPLORE §6's "unknown at 0.2.9" closed.
- the bench suites exist at the pin — `standard-v1` and `parallel-mixed-v1` in the 0.2.9 cli choices [31].
- k8v4's `--kv-resident` repetition bug is fixed pre-pin and the help streams k8v4 too [41][7] — no fresh HIP confirmation, stays [E].
- the conversation cache auto-sizes from free RAM up to 8192 MiB on the serve path [27] — the guide's "opt-in, leave it at 0" is refuted; the shipped 16384×16 is a deliberate doubling.
- hipBLASLt: silence expected on gfx1201 at our stack [22][23][24] — gfx1151-only auto rule, unpackaged claim-compiled engine, no 100401-class gfx1201 table (OQ-6).
- `STRATA_ENGINE_NICE` is a no-op on R9700-only rungs (default 0 there; +5 needs a visible iGPU) [16] — live only on the strix arena.
- `--resident-experts` is not a plan arm [21][48][49] — CUDA-only evidence and live AMD hazards.
- route-tail skip is engine-default-on for gfx1200/1201 at the pin [12][9] — the guide's "since 0.2.11" conflated setup's config change [36]; never applied with batch slots either way.
- `drafting.apply()` runs unconditionally at 0.2.13 [79] — the `"drafting": "mtp"` pins are EXPERIMENTAL-flagged per Q16 and ride PR-2 only (at 0.2.9 the key would be foreign to the closed-world profile surface).
- the file-cache arena rescue is excluded under cgroups [67] — and whether OUR pod presents a detectable limit is UNMEASURED, the probe declined at Q12; do not read [67] as settled for this box.
- the eval's "0.1.57 clean" premise is dead — reporter-corrected same-day [74].
- #5327 is the arena-file-cache issue fixed by PR #5531 — not #5317/#5341 [68].
- `PARALLEL_MAX = 8` survives at 0.1.59 [57]; `kVerifyNarrowT` unchanged [70] — the owner's 8 is the exact pin ceiling at both builds.
- hipBLASLt is still a no-op at 0.2.13 [71] — launcher rule unchanged, gfx1201 tables still only 100202/100500.
- a6e493b78's q4 4-slot ruling is superseded by Q9's 8-everywhere override — both stand as dated owner rulings, quoted here; the 110Gi containment + MALLOC_MMAP protections survive into the 8-everywhere posture as exactly its safety net (plan law 3).

## 11. Cross-references

- `.agents/notes/strata-host-prep-gpu-ai.md` §3.3/§3.4/§3.4a/§3.5/§4/§5/§6 — the host/enablement runbook this note layers on; its Step-0 [VERIFY] cells have one home and it is not this file.
- `charts/llama-swap/README.md` — the validation ladder, rungs 1–4 (the U1 command shapes), the strix fallback, the bump cadence.
- `containers/strata/README.md` — the tag→digest ledger and interface freeze; law 6 moves it in one commit (agent-capable digest re-read documented there).
- `.agents/plans/2026-11-10-dep-strata-engine-0213-eval.md` — superseded-as-executed-by-AD-141 at gate 6; its gates 1–5 live in §4.
- `.agents/plans/2026-11-10-research-strata-q3-q4-rungs.md` — the rung math behind the KV law and the arena calibrations.
- `.agents/plans/2026-11-10-debug-strata-q4-oom-crashloop.md` — the Grafana/Loki per-cell method and the containment doctrine §6's safety net refers to.
