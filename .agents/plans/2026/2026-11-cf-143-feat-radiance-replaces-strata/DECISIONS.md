# Decisions

Append-only. Newest at the bottom. Format: date, who (plan|cord|human), decision, alternatives rejected, why.

## Conventions
- Naming landmine (EXPLORE preamble / RESEARCH RQ0): "radiance" in this ticket means the
  `StillDeadcode/radiance` ENGINE. The `vllm-radiance` name inside `charts/vllm` /
  `containers/vllm-radiance-mxfp4` is the magiccodingman vLLM FORK — a different artifact;
  "Strata" (`Niko1221/Strata`) is unrelated. Every comment/test name disambiguates.
- Profile numbers come from RESEARCH.md "Serving envelope" (receipt-gated), never the
  card's deployment guide (its headline recipe was corrected: pool 43000/200K/chunk 4096,
  no `--expert-vs-cache-ratio`, no `serve` verb, startup probe `/health`).
- Peers single-source law continues: a new `radiance-peers-expected.yaml` evidence file is
  authored by the test session; dev conforms values to it; golden re-capture is the paired
  obligation (TEST_SPEC §1).
- Scalars-only service overrides (lists deep-merge REPLACE); directory mounts never
  subPath; ServerSideApply "false" for the llama-swap family; the trio law with the
  documented internal-only ingress skip.
- Repo version law: `version: 1.0.0` only because charts/radiance is brand-new; release.yaml
  owns every later bump. No hand-bumps, no hand-tags.

## Decisions
- 2026-11-11 plan D1: structure best guess **A** (own `charts/radiance` + llama-swap peer) —
  card's literal "new chart … as a peer"; RESEARCH RQ5: every production witness is the peer
  shape. Rejected-today: B (packaging-only variant, folds C02's values into charts/llama-swap),
  C (only one-card fn↔q27 swap shape; +66 GiB reload + #1255 fd class). Q1 owner-rules;
  C02/C04 fork on it.
- 2026-11-11 plan D2: image posture = upstream `docker.io/stilldeadcode/radiance:1.17.0` +
  renovate `datasource=docker` pin comment + tag→digest ledger comment (amd64 manifest
  `sha256:6fb0e99b…` vs index `sha256:c2acbaa3…`, which is which), pullPolicy IfNotPresent.
  Rejected: thin `containers/radiance` re-export (strata/vllm precedent — no buildable
  glue needed; engine ships usable) and `:latest`/digest-field (repo has no `image.digest`
  precedent). Tag-rebuild risk (unified-vulkan-262 history) recorded in the ledger comment.
- 2026-11-11 plan D3: one-card profile = fn TP1 200K × 8 seqs with `--kv-resident 32768`
  (the owner's KV-to-RAM lever) + `--ngram-placement disk`, pool 43000, chunk 4096.
  Rejected: `--prefix-cache-mib` tier (mutually exclusive with kv-resident; kept as the
  runbook's owner-sign-off fallback), fn-tp1-ram (sole-large-tenant + Wilde demotion-burst
  OOM class), q27-only lane (card says radiance replaces STRATA = the flash-next lane),
  fn+q27 co-residency (ruled out by capacity, RESEARCH option D).
- 2026-11-11 plan D4: priority = FLIP polarity on radiance (urgent 9 / default 5 / low 1
  on catalog rows; peer `setParams "priority?"` floor 5), because radiance honors the body
  field and the four-class board feature should keep working. Rejected: port the vLLM
  numbers unflipped (the inversion bug RESEARCH RQ2 names), stripParams→FIFO (drops the
  feature the card asked to handle gracefully — held as Q2 alternative),
  matrix `evict_costs` (inoperative for peers — peers are not matrix members).
- 2026-11-11 plan D5: strata retirement = SERVICE-level disable (enable-set false, peer
  commented) with chart-side strata surface left DORMANT + pointer comments this run.
  Rejected: wholesale chart-side deletion now (~1000 values lines + ~20 test files +
  evidence dirs) — the off-state is parity-tested, the lane stays rollback-live until the
  owner's on-target acceptance, deletion is a Q5-gated follow-up.
- 2026-11-11 plan D6: vllm disable shape = comment the `charts.vllm` entry + `peers.vllm`,
  keep a live empty `vllm: {}` key, AND harden the CI workflow extraction to
  `d.get('vllm') or {}`; charts/vllm and containers/vllm-radiance-mxfp4 untouched; the two
  Grafana vllm dashboards untouched (owner re-import stays a recorded follow-up); the
  vllm-runbook suite retires when its catalog rows sleep. Q3 confirms/adjusts (incl. the
  who-zeroed-replicas history).
- 2026-11-11 plan D7: new honest ids — served/catalog/peer id `qwen3.8-flash-next-radiance`
  (+ `-urgent`/`-low` wire-siblings sharing the modelID, the vllm row pattern). Rejected:
  reusing `…-strata-q4` via `--served-model-name` for id-stability (a radiance-served model
  named "-strata" is the exact confusion the three-way collision warns about) — but noted
  as Q4's alternative because the hourly loop's runner literal is owner-ruling-owned and
  MUST move pre-merge either way.
- 2026-11-11 plan D8: no secret surface — keyless peer (C-A precedent) + ungated packs
  (gated:False verified RQ0) ⇒ no ExternalSecret template, no bitwardenIds, no
  custom-values entry (trio law's documented skip). Re-verified against the Serving
  envelope before deciding: nothing in the profile needs `--api-key(-env)`.
- 2026-11-11 plan D9: pod posture ships privileged + hostPath kfd/dri + seccomp Unconfined
  (the lab's proven idiom — GID-486/setuid-caps history), `supplementalGroups: []` with
  the on-target deferral; non-privileged upgrade (llmkube shape) is the runbook's gate
  feeding a later owner ruling (Q7). Rejected: non-privileged now (kfd GID + io_uring
  memlock posture unverifiable from a planning session; no pod exec per MCP law).
- 2026-11-11 plan D10: model staging = `radiance-fetch` init with curl-resume from the
  ungated HF resolve URL + `.staged-<lfs-sha>` marker on the shared `llama-swap` claim
  (vllm setup-init idiom). Rejected: `--model hf/repo-id --model-revision` boot-fetch
  (RESEARCH calls it easier but it puts 113.6 GiB on the engine-boot path and needs
  HF egress from the serving container).
- 2026-11-11 plan D11: catalog context honesty = radiance rows advertise 200000 ctx and
  `input: [text]` (served 200K even though trained 262,144; vision is in-pack but the D38
  text-only marker stands until an owner re-advertise call — Q8).
- 2026-11-11 human (owner batched round, Q1–Q8 RULED): Q1=**A** own chart+peer.
  Q2=**flip polarity per engine** — radiance rows `body.priority` 9/5/1, peer floor
  `priority?: 5` polarity-safe, pipeline-models carries a per-engine polarity note.
  Q3=**comment entry+peer, keep charts/vllm byte-intact; `vllm: {}` key kept, CI extraction
  hardened; NO explicit `replicas: 0`; suites re-pinned to assert absence.**
  Q4=**new honest id** `qwen3.8-flash-next-radiance` via `--served-model-name`; catalog rows
  added. Q5=**SCOPE CHANGE — "Strata shouldn't be disabled yet. Once I get good metrics from
  Rediance, then we'll look at what to do with Strata."** Radiance runs ALONGSIDE: controller,
  peer route, matrix arenas, model entries stay exactly as they are; peers.radiance is
  ADDITIVE; the runner-model literal stays valid (no pre-merge owner re-rule this run).
  Q6=**two Inbox follow-up cards** at run end: (1) TP2 instructions (C03 doc as body);
  (2) Grafana dashboard re-import follow-up; strata-deletion + IQR-V4 dropped from the card
  ask. Q7=**non-privileged NOW** (override of plan D9): device-plugin `amd.com/gpu`
  allocation + supplementalGroups (render/video/kfd per the 486 finding), seccomp Unconfined,
  drop ALL + IPC_LOCK, Guaranteed QoS requests==limits; host-prep receipts (containerd/k3s
  memlock, GIDs, /proc/self/limits) become MANDATORY pre-first-deploy gates in C06.
  Q8=**advertise image input** — radiance rows `in: [text, image]`; the runbook smoke carries
  an image leg that can retire the claim on-target if it fails.
- 2026-11-11 plan D12 (supersedes D3's shipped numbers, keeps its mechanism): Q5+Q7+Q10
  arithmetic — node allocatable ≈125.08 GiB, strata keeps its 64Gi request, outer 4Gi, plus
  sidecars/reloader ⇒ a Guaranteed radiance pod requests==limits ≤ ~52 GiB ⇒ the
  sole-tenant 8×200K envelope (~80 GiB pinned) CANNOT ship during coexistence. SHIPPED:
  shadow profile 8×64K ctx, `--host-pool-mib 28000`, 52Gi/8cpu Guaranteed (pins ≈34 GiB,
  ≥4 GiB-free rule satisfied with margin); the full profile (pool 43000/200K/≈110Gi) is the
  runbook's documented post-retirement ladder; catalog ctx mirrors 65536 (D38 honesty pair
  moves with the chart). Rejected: trimming strata requests (against Q5's verbatim),
  burstable radiance (against Q7), shipping 8×200K Guaranteed (Pending forever).
- 2026-11-11 plan D13 (Q5's "verify the evidence law" item resolved): evidence files are
  PER-PEER-KEY — `strata-peers-expected.yaml`'s law governs the `strata:` subtree + the
  cf-77 additive delta and its `models_states` is strata history; it STAYS VALID AND
  UNEDITED. A sibling `radiance-peers-expected.yaml` (test-session authored, same header
  law + fresh one-id `models_states` chain) is the radiance peer's single source; the
  parity/blast-radius consumers get a sanctioned additive-delta carve-out for the
  `radiance:` key only. Alternative rejected: folding radiance into the strata file
  (violates its per-key scope + its dev-must-not-edit history chain's meaning).
- 2026-11-11 plan D14 (Q9, new gap from Q7+Q5): plugin 1.31.0.9 counts BOTH cards,
  allocates nodeId-ascending APU-first, no occupancy persistence (19 restarts) — the claim
  can land the 8060S on radiance. SHIPPED posture: `amd.com/gpu: 1` + MANDATORY
  startup-report PCI/gfx1201 gate (delete→Recreate re-claim on mis-allocation). Rejected
  for now: product-named resources (needs plugin ≥1.31.0.12 / chart bump — own-concern,
  Deferred; near-prerequisite at TP2 per C03) and privileged hostPath env-naming (directly
  contradicts the Q7 ruling).
- 2026-11-11 plan D15: Guaranteed QoS is a POD-class property ⇒ the `radiance-fetch` init
  must also carry requests==limits (200m/2Gi pair) or the pod silently downgrades to
  Burstable; single-source sizing scalars in chart values (guaranteedMemoryGi/hostPoolMib/
  maxModelLen/maxNumSeqs) so both runbook ladders are one-edit moves.
- 2026-11-11 plan D16 (scope shrink from Q5): C05 edits ONLY `pipeline-models` (+ catalog +
  surface.sh); `pipeline-kickoff` 26 and `boards` 251 keep the strata default route
  untouched — routing defaults move only at the owner's later cutover, never as a
  drive-by. D5/D7/D9's retirement-framing, deletion-pointers and pre-merge owner-gate are
  SUPERSEDED by the Q5/Q7/Q4 rulings above (entries kept for the record, append-only law);
  D11's ctx-200000/text-only stance is superseded by D12 (65536 shadow truth) + the Q8
  `[text, image]` ruling; D3's mechanism survives, its shipped numbers move to D12.
- 2026-11-11 human (approval-round rulings, recorded here retroactively — the coord logged
  them at 20:40 while the round-2 rework was in flight and round 2 had not yet folded the
  Q10 half): Q9 = "Do another round of research on this. I'd like to have apu and the R9700
  have different resource names. the APU should stay assigned to the llama-swap pod" →
  §R6 commissioned; Q10 = "I will manually scale down strata when testing and using
  radiance." → "the shadow-profile shrink is VOID: ship the FULL RESEARCH serving envelope
  (pool 43000 / 60Gi class, 8-session fn-TP1); the runbook documents the owner's manual
  strata scale-down as the pre-radiance step + restore-back"; Q11 = "Observe, no
  auto-mitigate"; APPROVAL = "Approve — run the plan" (plan_status approved).
- 2026-11-11 human (R6 round, post-research stop — verbatim rulings): Q9 FINAL = "**Option
  1: per-device PRODUCT NAMING via a VENDORED charts/amd-gpu chart** (the ~10-line fork
  adding the args/command hook the released chart lacks; image tag dp.image.tag
  values-reachable; plugin v1.31.0.12 with -resource_naming_strategy=product). Node lands
  amd.com/gpu-ai-pro-r9700 (radiance claims it) + amd.com/gpu-8060s (llama-swap flips to it
  in the SAME wave — mandatory same-wave, old amd.com/gpu disappears), plus unknown-revision
  fallback trap (bare amd.com/gpu) gated by runbook step-0 sysfs receipts. Vendored-chart
  governance DECISIONS line owed." · PROCESS = "**Fold and run on**: after this fold-in,
  Test Writing + the whole chunk loop proceed (no further owner pause until Final Review)."
- 2026-11-11 plan D17 (supersedes D12's shipped numbers; restores D3's profile; folds the
  Q10 ruling the round-2 rework had not yet applied): SHIP THE FULL fn-TP1 8-session
  profile — pool 43000, 200K ctx, 8 seqs, kv-resident 32768, chunks 4096, ngram disk;
  guaranteedMemoryGi 64 as the single scalar honoring the owner's "60Gi-class" (the
  arithmetic spans 60–70 GiB-class pins; the C06 receipt ladder decides up (64→96Gi,
  schedulable only while strata is manually scaled down — 64+64+4 > 125.08 allocatable
  ⇒ Pending beside live strata is the designed handshake, loud and safe) or down (pool →
  ctx → last-resort prefix-tier with owner sign-off)). Catalog rows return to
  `limit.context: 200000` (served-truth honesty, D38 pattern). Rejected: keeping any
  shadow sizing; GitOps-izing the scale-down (owner lane, Q5 letter).
- 2026-11-11 plan D18 (supersedes D14/round-2-Q9 best-guess — the runtime PCI-retry gate):
  named-pool determinism via `-resource_naming_strategy=product` (plugin 1.31.0.12, PR
  #246, per-name kubelet pools verified from source, RESEARCH §R6-Q1): radiance requests
  `amd.com/gpu-ai-pro-r9700: 1`, llama-swap flips to `amd.com/gpu-8060s: 1` in the SAME
  wave (old name disappears — stray bare claims Pending-forever = loud by design; strata/
  vllm hostPath pods have NO plugin interaction, confirmed R6-Q4-3). The startup-report
  PCI/gfx1201 assert SURVIVES only as belt-and-braces (catches the unknown-revision
  fallback-to-bare trap), moved from C02 runtime-gate framing into C06 step gates (a)–(e).
  Rejected per owner ruling + R6 ranking: DRA-driver option 2 (strongest determinism,
  zero llama-swap churn — recorded in Deferred as the TP2-era alternative and the R6
  witness path, dsluo `r9700-x2`), squat generic-device-plugin minor-path pin ("never
  ship while 1/2 exist"), two-DaemonSet filtering (source-verified DEAD), waiting on
  upstream PR #122 (stale 19+ months).
- 2026-11-11 plan D19 (the vendored-chart governance line §R6-open-question-3 owes):
  `charts/amd-gpu` is a VENDORED third-party chart — copy of upstream chart 0.22.0
  (helm index digest 791ada88…, @ tag amd-gpu-helm-0.22.0; template identical at .12 tag
  and master) + an EXACT ~10-line delta: the `args:` hook in deviceplugin-daemonset.yaml
  restating the image CMD fully (`-logtostderr=true`, `-stderrthreshold=INFO`, `-v=5` —
  `-v=5` is runbook-log-bearing, not cosmetic) + `dp.extraArgs` values plumbing;
  Chart.yaml `name: amd-gpu` PINNED (templates hardcode .Chart.Name — rendered object
  names must stay byte-identical across the Application source-flip repo→git-path so
  `gpu-ai-amd-gpu` swaps without orphan-prune); `version: 1.0.0` (brand-new entry, repo
  version law), `appVersion: "1.31.0.12"`; image pin moves values-owned
  (`dp.image.tag` + renovate `datasource=docker` comment + amd64 digest ledger
  6437c74f…) — the `# renovate: datasource=helm` comment LEAVES the service entry.
  REFRESH POLICY: on any upstream chart release ≥0.23 or PR #122 merge, re-copy upstream,
  re-apply the args delta by hand, diff against the recorded fork-point, bump via a
  fresh dated decision line (never a silent overwrite); until then the fork is a
  self-owned liability logged here and in the chart's header comment.
- 2026-11-11 plan D20 (delivery chunking + wave reorder): the naming delivery is its OWN
  chunk C07 (vendored chart + service entry swap + llama-swap flip + `tests/services/
  amd-gpu-naming.sh` + render CI), NOT folded into C02 — different chart family,
  different blast radius (whole-node resource accounting), and a reviewer can reject the
  cluster-wide flip independently of the radiance chart. Same-wave cohesion holds inside
  C07's single commit (flip + vendored chart + entry swap land together). Waves become:
  1 → C01, C03, C07 · 2 → C02 [dep C07: the name it claims must exist in tree for the
  cross-chart name-identity test] · 3 → C04 · 4 → C05, C06. Ids C01–C06 stay frozen
  (ruling-traceability across three owner rounds); the appended C07 bends the
  "ids-in-wave-order" convention once, deliberately, recorded here. ArgoCD merge-time
  sync coherence + the lockstep-revert law are the plan's Rollout notes, the on-target
  receipts are C06's gates — chunk waves are BRANCH order only, not sync order.
- 2026-11-11 human (C07 OQ1 ruling — verbatim, STATE top handoffs
  "Owner ruling — C07 open question 1 (gpu-cluster cross-wave leak)"): OWNER chose **B1
  (shield — per-cluster flip)**: "charts/llama-swap/values.yaml default REVERTS to
  amd.com/gpu: 1 (the gpu cluster's plugin stays single-naming 1.31.0.9 — that name is all
  it can advertise; gpu-llama-swap live 1/1 stays schedulable); services/gpu-ai/prod/values.yaml
  llama-swap: block carries the amd.com/gpu-8060s resources override (gpu-ai-only flip);
  the n3/AC4 bare-claim sweep + test_cf143_naming_flip arms + off-parity baseline re-scoped
  to per-cluster truth by the test round. No live workload endangered on merge; no
  gpu-cluster sysfs research needed; services/gpu external amd-gpu entry unchanged. C07
  dev round 2 reworks the flip placement."
- 2026-11-12 plan D21 (folds B1; supersedes D18's FLIP-LOCATION assumption and C07's
  round-1 AC3 shape — D18's strategy stands: same-wave law, per-name pools, lockstep
  revert, strata/vllm non-interaction all survive): the leak the C07 dev found is real and
  repo-grounded — `services/gpu/prod/values.yaml:135-139` keeps the gpu cluster on the
  EXTERNAL amd-gpu chart 0.22.0 (appVersion 1.31.0.9, single naming), which can only ever
  advertise bare `amd.com/gpu`; a tree-global chart flip to `amd.com/gpu-8060s` would
  strand the live gpu-llama-swap (1/1) on its next reschedule. MECHANISM: chart default
  stays `amd.com/gpu: 1` (gpu-cluster-safe tree-global claim — the llama-swap chart renders
  in both clusters) with the comment rewritten to say exactly why; the gpu-ai service
  overlay flips it — `app-template.controllers.llama-swap.containers.main.resources:
  limits {amd.com/gpu: null, amd.com/gpu-8060s: 1} + requests {amd.com/gpu-8060s: 1}` —
  maps deep-merge so keys ADD and never remove: the `null` on the inherited bare key is
  load-bearing (cf-97's proven per-app valuesObject subtree-merge fact; requests-mirror
  explicit for self-documentation, scheduler auto-mirrors extended resources anyway).
  Test consequences (round-1 dev-routed re-pins, test-session property): n3/AC4 sweep →
  per-cluster truth (bare allowed ONLY as the chart default; stray-guard: the APU name
  appears nowhere but the gpu-ai overlay + the amd-gpu expected-names ledger; radiance's
  R9700 name only in charts/radiance + that ledger); test_cf143_naming_flip tree-line grep
  → rendered `res=`-level legs (gpu-ai render APU+no-bare; default/gpu-cluster render
  bare); test_provenance window-join → flattened replay; off-parity render-default
  fixture moves ZERO lines (the shield's proof) — its scheduled re-baseline collapses to
  a TEST_SPEC §9.8 era note. GOVERNANCE: services/gpu stays on the external chart entry —
  documented per-cluster posture, NOT drift; extending product naming to the gpu cluster
  (would need its own vendored-entry decision + sysfs receipts) rides the TP2 follow-up
  CARD #1 as a one-line posture note in the C03 doc (placement call: card #1 is the GPU
  scheduling home; the dashboard card stays dashboard-only).

## Deferred
- Strata cutover/retirement — OWNER's metrics decision (Q5 ruling 2026-11-11): the future
  ticket re-authors the peers evidence chain, flips the strata enable-set + peer; the full
  8×200K profile SHIPS NOW under the owner's manual scale-down protocol (Q10/D17), so the
  cutover no longer gates the profile — it only ends the scale-down dance.
- Runner-model literal re-ruling (loops file + AGENTS.md): NOT needed this run (strata
  survives, Q5); rides the cutover above as an owner ruling.
- Chart-side strata surface deletion — rides the cutover decision naturally (Q6 dropped it
  as a standalone card ask).
- Plugin bump for per-product resources — REALIZED this run by C07 (D18/D19: vendored
  0.22.0 + args hook + plugin 1.31.0.12; names `amd.com/gpu-ai-pro-r9700` /
  `amd.com/gpu-8060s`; the earlier bullet's name form `Radeon-AI-PRO-R9700` was
  CORRECTED by R6 — the sanitizer lowercases, drops "Radeon", prefixes `gpu-`).
- Upstream amd-gpu chart refresh (≥0.23 or PR #122 merge): re-copy + re-apply the args
  delta per the D19 refresh policy; watch, don't wait.
- Plugin occupancy PRs #243/#247 (opt-in KFD occupancy): upstream concedes the
  no-occupancy class; a future bump could make within-bucket choice occupancy-aware —
  watch (moot while each bucket holds one device).
- DRA route (ROCm/k8s-gpu-dra-driver v1.0.1, dsluo `r9700-x2` CEL-claim shape) — R6's
  ranked-2 alternative, rejected for this run by the Option-1 ruling; the natural TP2
  claim-based lane if the owner ever prefers it (C03 records it as the documented
  alternative).
- supplementalGroups render/video extension + k3s LimitMEMLOCK drop-in — gated on C06
  step-0 host receipts (owner-run); one-edit service-block override when/if needed.
- Grafana dashboard re-import / radiance-native dashboard — FOLLOW-UP CARD #2 (Q6):
  `/metrics` is vllm-compat-family, the two existing dashboards are cheap candidates.
- q27-on-radiance second lane + IQR-V4 pack adoption — unlocks with card 2 (TP2) /
  post-cutover (C03 doc).
- `AMD_GPU_DEVICE_COUNT` / t1m.me plugin-claim — CLOSED by §R6: the .12 binary implements
  neither `AMD_GPU_DEVICE_COUNT` nor `CONFIG_FILE_PATH` (docs lead code; a count cap
  could never choose a card anyway); the t1m.me kernel-7.1.3 story stays dropped unless
  the owner produces the citation.
