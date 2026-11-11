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

## Deferred
- Strata cutover/retirement — OWNER's metrics decision (Q5 ruling 2026-11-11): the future
  ticket re-authors the peers evidence chain, flips the strata enable-set + peer, and moves
  radiance up the sole-tenant ladder (pool 43000 / 200K ctx / ≈110Gi cgroup — chart+catalog
  honesty pair together) with it.
- Runner-model literal re-ruling (loops file + AGENTS.md): NOT needed this run (strata
  survives, Q5); rides the cutover above as an owner ruling.
- Chart-side strata surface deletion — rides the cutover decision naturally (Q6 dropped it
  as a standalone card ask).
- Plugin bump for product-named resources (`amd.com/Radeon-AI-PRO-R9700` claims; needs
  plugin ≥1.31.0.12 — lab runs 1.31.0.9) — clean fix for the mis-allocation class (D14/Q9);
  near-prerequisite at TP2 (C03); own-concern branch.
- supplementalGroups render/video extension + k3s LimitMEMLOCK drop-in — gated on C06
  step-0 host receipts (owner-run); one-edit service-block override when/if needed.
- Grafana dashboard re-import / radiance-native dashboard — FOLLOW-UP CARD #2 (Q6):
  `/metrics` is vllm-compat-family, the two existing dashboards are cheap candidates.
- q27-on-radiance second lane + IQR-V4 pack adoption — unlocks with card 2 (TP2) /
  post-cutover (C03 doc).
- `AMD_GPU_DEVICE_COUNT` / t1m.me plugin-claim pin-or-drop (RESEARCH UNVERIFIABLE items;
  owner if a citation exists).
